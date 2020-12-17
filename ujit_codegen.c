#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "internal/compile.h"
#include "internal/class.h"
#include "insns_info.inc"
#include "ujit.h"
#include "ujit_iface.h"
#include "ujit_core.h"
#include "ujit_codegen.h"
#include "ujit_asm.h"
#include "ujit_utils.h"

// Map from YARV opcodes to code generation functions
static st_table *gen_fns;

// Code block into which we write machine code
static codeblock_t block;
codeblock_t* cb = NULL;

// Code block into which we write out-of-line machine code
static codeblock_t outline_block;
codeblock_t* ocb = NULL;

// Ruby instruction entry
static void
ujit_gen_entry(codeblock_t* cb)
{
    cb_write_pre_call_bytes(cb);

    // Load the current SP from the CFP into REG_SP
    mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));
}

/**
Generate an inline exit to return to the interpreter
*/
static void
ujit_gen_exit(codeblock_t* cb, ctx_t* ctx, VALUE* exit_pc)
{
    // Write the adjusted SP back into the CFP
    if (ctx->stack_size != 0)
    {
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx, 0);
        lea(cb, REG_SP, stack_pointer);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG_SP);
    }

    // Directly return the next PC, which is a constant
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), RAX);

    // Write the post call bytes
    cb_write_post_call_bytes(cb);
}

/**
Generate an out-of-line exit to return to the interpreter
*/
static uint8_t *
ujit_side_exit(codeblock_t* cb, ctx_t* ctx)
{
    uint8_t* code_ptr = cb_get_ptr(cb, cb->write_pos);

    // Table mapping opcodes to interpreter handlers
    const void * const *table = rb_vm_get_insns_address_table();

    // Write back the old instruction at the entry PC
    // To deotimize the code block this instruction belongs to
    VALUE* entry_pc = &ctx->iseq->body->iseq_encoded[ctx->start_idx];
    int entry_opcode = opcode_at_pc(ctx->iseq, entry_pc);
    void* entry_instr = (void*)table[entry_opcode];
    mov(cb, RAX, const_ptr_opnd(entry_pc));
    mov(cb, RCX, const_ptr_opnd(entry_instr));
    mov(cb, mem_opnd(64, RAX, 0), RCX);

    // Write back the old instruction at the exit PC
    // Otherwise the interpreter may jump right back to the
    // JITted code we're trying to exit
    VALUE* exit_pc = &ctx->iseq->body->iseq_encoded[ctx->insn_idx];
    int exit_opcode = opcode_at_pc(ctx->iseq, exit_pc);
    void* exit_instr = (void*)table[exit_opcode];
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, RCX, const_ptr_opnd(exit_instr));
    mov(cb, mem_opnd(64, RAX, 0), RCX);

    // Generate the code to exit to the interpreters
    ujit_gen_exit(cb, ctx, exit_pc);

    return code_ptr;
}

/*
Compile a sequence of bytecode instructions starting at `insn_idx`.
Returns `NULL` if compilation fails.
*/
uint8_t *
ujit_compile_block(const rb_iseq_t *iseq, uint32_t insn_idx, bool gen_entry)
{
    assert (cb != NULL);
    VALUE *encoded = iseq->body->iseq_encoded;

    // NOTE: if we are ever deployed in production, we
    // should probably just log an error and return NULL here,
    // so we can fail more gracefully
    if (cb->write_pos + 1024 >= cb->mem_size) {
        rb_bug("out of executable memory");
    }
    if (ocb->write_pos + 1024 >= ocb->mem_size) {
        rb_bug("out of executable memory (outlined block)");
    }

    // Align the current write positon to cache line boundaries
    cb_align_pos(cb, 64);

    // Get a pointer to the current write position in the code block
    uint8_t *code_ptr = &cb->mem_block[cb->write_pos];
    //printf("write pos: %ld\n", cb->write_pos);

    // Get the first opcode in the sequence
    int first_opcode = opcode_at_pc(iseq, &encoded[insn_idx]);

    // Create codegen context
    ctx_t ctx = { 0 };
    ctx.iseq = iseq;
    ctx.code_ptr = code_ptr;
    ctx.start_idx = insn_idx;

    // For each instruction to compile
    unsigned num_instrs = 0;
    for (;;) {
        // Set the current instruction
        ctx.insn_idx = insn_idx;
        ctx.pc = &encoded[insn_idx];

        // Get the current opcode
        int opcode = ctx_get_opcode(&ctx);

        // Lookup the codegen function for this instruction
        st_data_t st_gen_fn;
        if (!rb_st_lookup(gen_fns, opcode, &st_gen_fn)) {
            //print_int(cb, imm_opnd(num_instrs));
            //print_str(cb, insn_name(opcode));
            break;
        }

        // If requested, write the interpreter entry
        // prologue before the first instruction
        if (gen_entry && num_instrs == 0) {
            ujit_gen_entry(cb);
        }

        // Call the code generation function
        codegen_fn gen_fn = (codegen_fn)st_gen_fn;
        if (!gen_fn(cb, ocb, &ctx)) {
            break;
        }

    	// Move to the next instruction
        insn_idx += insn_len(opcode);
        num_instrs++;

        // Ensure we only have one send per region. Our code invalidation mechanism can't
        // invalidate running code and one send could invalidate the other if we had
        // multiple in the same region.
        if (opcode == BIN(opt_send_without_block)) {
            break;
        }
    }

    // If no instructions were compiled
    if (num_instrs == 0) {
        return NULL;
    }

    // Generate code to exit to the interpreter
    ujit_gen_exit(cb, &ctx, &encoded[insn_idx]);

    map_addr2insn(code_ptr, first_opcode);

    if (UJIT_DUMP_MODE >= 2) {
        // Dump list of compiled instrutions
        fprintf(stderr, "Compiled the following for iseq=%p:\n", (void *)iseq);
        VALUE *pc = &encoded[ctx.start_idx];
        VALUE *end_pc = &encoded[insn_idx];
        while (pc < end_pc) {
            int opcode = opcode_at_pc(iseq, pc);
            fprintf(stderr, "  %04td %s\n", pc - encoded, insn_name(opcode));
            pc += insn_len(opcode);
        }
    }

    return code_ptr;
}

static bool
gen_dup(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    x86opnd_t dup_val = ctx_stack_pop(ctx, 1);
    x86opnd_t loc0 = ctx_stack_push(ctx, 1);
    x86opnd_t loc1 = ctx_stack_push(ctx, 1);
    mov(cb, RAX, dup_val);
    mov(cb, loc0, RAX);
    mov(cb, loc1, RAX);
    return true;
}

static bool
gen_nop(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Do nothing
    return true;
}

static bool
gen_pop(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Decrement SP
    ctx_stack_pop(ctx, 1);
    return true;
}

static bool
gen_putnil(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(Qnil));
    return true;
}

static bool
gen_putobject(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load the argument from the bytecode sequence.
    // We need to do this as the argument can change due to GC compaction.
    x86opnd_t pc_imm = const_ptr_opnd((void*)ctx->pc);
    mov(cb, RAX, pc_imm);
    mov(cb, RAX, mem_opnd(64, RAX, 8)); // One after the opcode

    // Write argument at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RAX);

    return true;
}

static bool
gen_putobject_int2fix(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    int opcode = ctx_get_opcode(ctx);
    int cst_val = (opcode == BIN(putobject_INT2FIX_0_))? 0:1;

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(INT2FIX(cst_val)));

    return true;
}

static bool
gen_putself(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load self from CFP
    mov(cb, RAX, member_opnd(REG_CFP, rb_control_frame_t, self));

    // Write it on the stack
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RAX);

    return true;
}

static bool
gen_getlocal_wc0(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load environment pointer EP from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));

    // Compute the offset from BP to the local
    int32_t local_idx = (int32_t)ctx_get_arg(ctx, 0);
    const int32_t offs = -8 * local_idx;

    // Load the local from the block
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, REG0);

    return true;
}

static bool
gen_setlocal_wc0(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    /*
    vm_env_write(const VALUE *ep, int index, VALUE v)
    {
        VALUE flags = ep[VM_ENV_DATA_INDEX_FLAGS];
        if (LIKELY((flags & VM_ENV_FLAG_WB_REQUIRED) == 0)) {
    	VM_STACK_ENV_WRITE(ep, index, v);
        }
        else {
    	vm_env_write_slowpath(ep, index, v);
        }
    }
    */

    // Load environment pointer EP from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));

    // flags & VM_ENV_FLAG_WB_REQUIRED
    x86opnd_t flags_opnd = mem_opnd(64, REG0, 8 * VM_ENV_DATA_INDEX_FLAGS);
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED));

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Pop the value to write from the stack
    x86opnd_t stack_top = ctx_stack_pop(ctx, 1);
    mov(cb, REG1, stack_top);

    // Write the value at the environment pointer
    int32_t local_idx = (int32_t)ctx_get_arg(ctx, 0);
    const int32_t offs = -8 * local_idx;
    mov(cb, mem_opnd(64, REG0, offs), REG1);

    return true;
}

// Check that `self` is a pointer to an object on the GC heap
static void
guard_self_is_object(codeblock_t *cb, x86opnd_t self_opnd, uint8_t *side_exit, ctx_t *ctx)
{
    // `self` is constant throughout the entire region, so we only need to do this check once.
    if (!ctx->self_is_object) {
        test(cb, self_opnd, imm_opnd(RUBY_IMMEDIATE_MASK));
        jnz_ptr(cb, side_exit);
        cmp(cb, self_opnd, imm_opnd(Qfalse));
        je_ptr(cb, side_exit);
        cmp(cb, self_opnd, imm_opnd(Qnil));
        je_ptr(cb, side_exit);
        ctx->self_is_object = true;
    }
}

static bool
gen_getinstancevariable(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    IVC ic = (IVC)ctx_get_arg(ctx, 1);

    // Check that the inline cache has been set, slot index is known
    if (!ic->entry)
    {
        return false;
    }

    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    if (rb_get_alloc_func(ic->entry->class_value) != rb_class_allocate_instance)
    {
        return false;
    }

    uint32_t ivar_index = ic->entry->index;

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // Load self from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, self));

    guard_self_is_object(cb, REG0, side_exit, ctx);

    // Bail if receiver class is different from compiled time call cache class
    x86opnd_t klass_opnd = mem_opnd(64, REG0, offsetof(struct RBasic, klass));
    mov(cb, REG1, klass_opnd);
    x86opnd_t serial_opnd = mem_opnd(64, REG1, offsetof(struct RClass, class_serial));
    cmp(cb, serial_opnd, imm_opnd(ic->entry->class_serial));
    jne_ptr(cb, side_exit);

    // Bail if the ivars are not on the extended table
    // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h
    x86opnd_t flags_opnd = member_opnd(REG0, struct RBasic, flags);
    test(cb, flags_opnd, imm_opnd(ROBJECT_EMBED));
    jnz_ptr(cb, side_exit);

    // Get a pointer to the extended table
    x86opnd_t tbl_opnd = mem_opnd(64, REG0, offsetof(struct RObject, as.heap.ivptr));
    mov(cb, REG0, tbl_opnd);

    // Read the ivar from the extended table
    x86opnd_t ivar_opnd = mem_opnd(64, REG0, sizeof(VALUE) * ivar_index);
    mov(cb, REG0, ivar_opnd);

    // Check that the ivar is not Qundef
    cmp(cb, REG0, imm_opnd(Qundef));
    je_ptr(cb, side_exit);

    // Push the ivar on the stack
    x86opnd_t out_opnd = ctx_stack_push(ctx, 1);
    mov(cb, out_opnd, REG0);

    return true;
}

static bool
gen_setinstancevariable(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    IVC ic = (IVC)ctx_get_arg(ctx, 1);

    // Check that the inline cache has been set, slot index is known
    if (!ic->entry)
    {
        return false;
    }

    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    if (rb_get_alloc_func(ic->entry->class_value) != rb_class_allocate_instance)
    {
        return false;
    }

    uint32_t ivar_index = ic->entry->index;

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // Load self from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, self));

    guard_self_is_object(cb, REG0, side_exit, ctx);

    // Bail if receiver class is different from compiled time call cache class
    x86opnd_t klass_opnd = mem_opnd(64, REG0, offsetof(struct RBasic, klass));
    mov(cb, REG1, klass_opnd);
    x86opnd_t serial_opnd = mem_opnd(64, REG1, offsetof(struct RClass, class_serial));
    cmp(cb, serial_opnd, imm_opnd(ic->entry->class_serial));
    jne_ptr(cb, side_exit);

    // Bail if the ivars are not on the extended table
    // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h
    x86opnd_t flags_opnd = member_opnd(REG0, struct RBasic, flags);
    test(cb, flags_opnd, imm_opnd(ROBJECT_EMBED));
    jnz_ptr(cb, side_exit);

    // If we can't guarantee that the extended table is big enoughg
    if (ivar_index >= ROBJECT_EMBED_LEN_MAX + 1)
    {
        // Check that the slot is inside the extended table (num_slots > index)
        x86opnd_t num_slots = mem_opnd(32, REG0, offsetof(struct RObject, as.heap.numiv));
        cmp(cb, num_slots, imm_opnd(ivar_index));
        jle_ptr(cb, side_exit);
    }

    // Get a pointer to the extended table
    x86opnd_t tbl_opnd = mem_opnd(64, REG0, offsetof(struct RObject, as.heap.ivptr));
    mov(cb, REG0, tbl_opnd);

    // Pop the value to write from the stack
    x86opnd_t stack_top = ctx_stack_pop(ctx, 1);
    mov(cb, REG1, stack_top);

    // Bail if this is a heap object, because this needs a write barrier
    test(cb, REG1, imm_opnd(RUBY_IMMEDIATE_MASK));
    jz_ptr(cb, side_exit);

    // Write the ivar to the extended table
    x86opnd_t ivar_opnd = mem_opnd(64, REG0, sizeof(VALUE) * ivar_index);
    mov(cb, ivar_opnd, REG1);

    return true;
}

static bool
gen_opt_lt(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // TODO: make a helper function for guarding on op-not-redefined
    // Make sure that minus isn't redefined for integers
    mov(cb, RAX, const_ptr_opnd(ruby_current_vm_ptr));
    test(
        cb,
        member_opnd_idx(RAX, rb_vm_t, redefined_flag, BOP_LT),
        imm_opnd(INTEGER_REDEFINED_OP_FLAG)
    );
    jnz_ptr(cb, side_exit);

    // Get the operands and destination from the stack
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // If not fixnums, fall back
    test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);
    test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);

    // Compare the arguments
    mov(cb, REG0, arg0);
    cmp(cb, REG0, arg1);
    mov(cb, REG0, imm_opnd(Qfalse));
    mov(cb, REG1, imm_opnd(Qtrue));
    cmovl(cb, REG0, REG1);

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, 1);
    mov(cb, dst, REG0);

    return true;
}

static bool
gen_opt_minus(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // TODO: make a helper function for guarding on op-not-redefined
    // Make sure that minus isn't redefined for integers
    mov(cb, RAX, const_ptr_opnd(ruby_current_vm_ptr));
    test(
        cb,
        member_opnd_idx(RAX, rb_vm_t, redefined_flag, BOP_MINUS),
        imm_opnd(INTEGER_REDEFINED_OP_FLAG)
    );
    jnz_ptr(cb, side_exit);

    // Get the operands and destination from the stack
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // If not fixnums, fall back
    test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);
    test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);

    // Subtract arg0 - arg1 and test for overflow
    mov(cb, REG0, arg0);
    sub(cb, REG0, arg1);
    jo_ptr(cb, side_exit);
    add(cb, REG0, imm_opnd(1));

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, 1);
    mov(cb, dst, REG0);

    return true;
}

static bool
gen_opt_plus(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // TODO: make a helper function for guarding on op-not-redefined
    // Make sure that plus isn't redefined for integers
    mov(cb, RAX, const_ptr_opnd(ruby_current_vm_ptr));
    test(
        cb,
        member_opnd_idx(RAX, rb_vm_t, redefined_flag, BOP_PLUS),
        imm_opnd(INTEGER_REDEFINED_OP_FLAG)
    );
    jnz_ptr(cb, side_exit);

    // Get the operands and destination from the stack
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // If not fixnums, fall back
    test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);
    test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);

    // Add arg0 + arg1 and test for overflow
    mov(cb, REG0, arg0);
    sub(cb, REG0, imm_opnd(1));
    add(cb, REG0, arg1);
    jo_ptr(cb, side_exit);

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, 1);
    mov(cb, dst, REG0);

    return true;
}

// Verify that calling with cd on receiver goes to callee
static void
check_cfunc_dispatch(VALUE receiver, struct rb_call_data *cd, void *callee, rb_callable_method_entry_t *compile_time_cme)
{
    if (METHOD_ENTRY_INVALIDATED(compile_time_cme)) {
        rb_bug("ujit: output code uses invalidated cme %p", (void *)compile_time_cme);
    }

    bool callee_correct = false;
    const rb_callable_method_entry_t *cme = rb_callable_method_entry(CLASS_OF(receiver), vm_ci_mid(cd->ci));
    if (cme->def->type == VM_METHOD_TYPE_CFUNC) {
        const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);
        if ((void *)cfunc->func == callee) {
            callee_correct = true;
        }
    }
    if (!callee_correct) {
        rb_bug("ujit: output code calls wrong method cd->cc->klass: %p", (void *)cd->cc->klass);
    }
}

MJIT_FUNC_EXPORTED VALUE rb_hash_has_key(VALUE hash, VALUE key);

static bool
cfunc_needs_frame(const rb_method_cfunc_t *cfunc)
{
    void* fptr = (void*)cfunc->func;

    // Leaf C functions do not need a stack frame
    // or a stack overflow check
    return !(
        // Hash#key?
        fptr == (void*)rb_hash_has_key
    );
}

static bool
gen_opt_send_without_block(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Relevant definitions:
    // rb_execution_context_t       : vm_core.h
    // invoker, cfunc logic         : method.h, vm_method.c
    // rb_callable_method_entry_t   : method.h
    // vm_call_cfunc_with_frame     : vm_insnhelper.c
    // rb_callcache                 : vm_callinfo.h

    struct rb_call_data * cd = (struct rb_call_data *)ctx_get_arg(ctx, 0);
    int32_t argc = (int32_t)vm_ci_argc(cd->ci);

    // Don't JIT calls with keyword splat
    if (vm_ci_flag(cd->ci) & VM_CALL_KW_SPLAT)
    {
        return false;
    }

    // Don't JIT calls that aren't simple
    if (!(vm_ci_flag(cd->ci) & VM_CALL_ARGS_SIMPLE))
    {
        return false;
    }

    // Don't JIT if the inline cache is not set
    if (!cd->cc || !cd->cc->klass) {
        return false;
    }

    const rb_callable_method_entry_t *cme = vm_cc_cme(cd->cc);

    // Don't JIT if the method entry is out of date
    if (METHOD_ENTRY_INVALIDATED(cme)) {
        return false;
    }

    // Don't JIT if this is not a C call
    if (cme->def->type != VM_METHOD_TYPE_CFUNC)
    {
        return false;
    }

    const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);

    // Don't JIT if the argument count doesn't match
    if (cfunc->argc < 0 || cfunc->argc != argc)
    {
        return false;
    }

    // Don't JIT functions that need C stack arguments for now
    if (argc + 1 > NUM_C_ARG_REGS)
    {
        return false;
    }

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(ocb, ctx);

    // Check for interrupts
    // RUBY_VM_CHECK_INTS(ec)
    mov(cb, REG0_32, member_opnd(REG_EC, rb_execution_context_t, interrupt_mask));
    not(cb, REG0_32);
    test(cb, member_opnd(REG_EC, rb_execution_context_t, interrupt_flag), REG0_32);
    jnz_ptr(cb, side_exit);

    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);
    mov(cb, REG0, recv);

    // Callee method ID
    //ID mid = vm_ci_mid(cd->ci);
    //printf("JITting call to C function \"%s\", argc: %lu\n", rb_id2name(mid), argc);
    //print_str(cb, "");
    //print_str(cb, "calling CFUNC:");
    //print_str(cb, rb_id2name(mid));
    //print_str(cb, "recv");
    //print_ptr(cb, recv);

    // Check that the receiver is a heap object
    test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
    jnz_ptr(cb, side_exit);
    cmp(cb, REG0, imm_opnd(Qfalse));
    je_ptr(cb, side_exit);
    cmp(cb, REG0, imm_opnd(Qnil));
    je_ptr(cb, side_exit);

    // Pointer to the klass field of the receiver &(recv->klass)
    x86opnd_t klass_opnd = mem_opnd(64, REG0, offsetof(struct RBasic, klass));

    // Bail if receiver class is different from compiled time call cache class
    mov(cb, REG1, imm_opnd(cd->cc->klass));
    cmp(cb, klass_opnd, REG1);
    jne_ptr(cb, side_exit);

    // Store incremented PC into current control frame in case callee raises.
    mov(cb, REG0, const_ptr_opnd(ctx->pc + insn_len(BIN(opt_send_without_block))));
    mov(cb, mem_opnd(64, REG_CFP, offsetof(rb_control_frame_t, pc)), REG0);

    // If this function needs a Ruby stack frame
    if (cfunc_needs_frame(cfunc))
    {
        // Stack overflow check
        // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
        // REG_CFP <= REG_SP + 4 * sizeof(VALUE) + sizeof(rb_control_frame_t)
        lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * 4 + sizeof(rb_control_frame_t)));
        cmp(cb, REG_CFP, REG0);
        jle_ptr(cb, side_exit);

        // Increment the stack pointer by 3 (in the callee)
        // sp += 3
        lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * 3));

        // Put compile time cme into REG1. It's assumed to be valid because we are notified when
        // any cme we depend on become outdated. See rb_ujit_method_lookup_change().
        mov(cb, REG1, const_ptr_opnd(cme));
        // Write method entry at sp[-3]
        // sp[-3] = me;
        mov(cb, mem_opnd(64, REG0, 8 * -3), REG1);

        // Write block handler at sp[-2]
        // sp[-2] = block_handler;
        mov(cb, mem_opnd(64, REG0, 8 * -2), imm_opnd(VM_BLOCK_HANDLER_NONE));

        // Write env flags at sp[-1]
        // sp[-1] = frame_type;
        uint64_t frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
        mov(cb, mem_opnd(64, REG0, 8 * -1), imm_opnd(frame_type));

        // Allocate a new CFP (ec->cfp--)
        sub(
            cb,
            member_opnd(REG_EC, rb_execution_context_t, cfp),
            imm_opnd(sizeof(rb_control_frame_t))
        );

        // Setup the new frame
        // *cfp = (const struct rb_control_frame_struct) {
        //    .pc         = 0,
        //    .sp         = sp,
        //    .iseq       = 0,
        //    .self       = recv,
        //    .ep         = sp - 1,
        //    .block_code = 0,
        //    .__bp__     = sp,
        // };
        mov(cb, REG1, member_opnd(REG_EC, rb_execution_context_t, cfp));
        mov(cb, member_opnd(REG1, rb_control_frame_t, pc), imm_opnd(0));
        mov(cb, member_opnd(REG1, rb_control_frame_t, sp), REG0);
        mov(cb, member_opnd(REG1, rb_control_frame_t, iseq), imm_opnd(0));
        mov(cb, member_opnd(REG1, rb_control_frame_t, block_code), imm_opnd(0));
        mov(cb, member_opnd(REG1, rb_control_frame_t, __bp__), REG0);
        sub(cb, REG0, imm_opnd(sizeof(VALUE)));
        mov(cb, member_opnd(REG1, rb_control_frame_t, ep), REG0);
        mov(cb, REG0, recv);
        mov(cb, member_opnd(REG1, rb_control_frame_t, self), REG0);
    }

    if (UJIT_CHECK_MODE > 0) {
        // Verify that we are calling the right function
        // Save MicroJIT registers
        push(cb, REG_CFP);
        push(cb, REG_EC);
        push(cb, REG_SP);
        // Maintain 16-byte RSP alignment
        sub(cb, RSP, imm_opnd(8));

        // Call check_cfunc_dispatch
        mov(cb, RDI, recv);
        mov(cb, RSI, const_ptr_opnd(cd));
        mov(cb, RDX, const_ptr_opnd((void *)cfunc->func));
        mov(cb, RCX, const_ptr_opnd(cme));
        call_ptr(cb, REG0, (void *)&check_cfunc_dispatch);

        // Restore registers
        add(cb, RSP, imm_opnd(8));
        pop(cb, REG_SP);
        pop(cb, REG_EC);
        pop(cb, REG_CFP);
    }

    // Save the MicroJIT registers
    push(cb, REG_CFP);
    push(cb, REG_EC);
    push(cb, REG_SP);

    // Maintain 16-byte RSP alignment
    sub(cb, RSP, imm_opnd(8));

    // Copy SP into RAX because REG_SP will get overwritten
    lea(cb, RAX, ctx_sp_opnd(ctx, 0));

    // Copy the arguments from the stack to the C argument registers
    // self is the 0th argument and is at index argc from the stack top
    for (int32_t i = 0; i < argc + 1; ++i)
    {
        x86opnd_t stack_opnd = mem_opnd(64, RAX, -(argc + 1 - i) * 8);
        //print_ptr(cb, stack_opnd);
        x86opnd_t c_arg_reg = C_ARG_REGS[i];
        mov(cb, c_arg_reg, stack_opnd);
    }

    // Pop the C function arguments from the stack (in the caller)
    ctx_stack_pop(ctx, argc + 1);

    //print_str(cb, "before C call");

    assume_method_lookup_stable(cd->cc, cme, ctx);

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
    // cfunc comes from compile-time cme->def, which we assume to be stable.
    // Invalidation logic is in rb_ujit_method_lookup_change()
    call_ptr(cb, REG0, (void*)cfunc->func);

    //print_str(cb, "after C call");

    // Maintain 16-byte RSP alignment
    add(cb, RSP, imm_opnd(8));

    // Restore MicroJIT registers
    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    // Push the return value on the Ruby stack
    x86opnd_t stack_ret = ctx_stack_push(ctx, 1);
    mov(cb, stack_ret, RAX);

    // If this function needs a Ruby stack frame
    if (cfunc_needs_frame(cfunc))
    {
        // Pop the stack frame (ec->cfp++)
        add(
            cb,
            member_opnd(REG_EC, rb_execution_context_t, cfp),
            imm_opnd(sizeof(rb_control_frame_t))
        );
    }

    return true;
}

void 
gen_branchunless_branch(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape)
{
    jz_ptr(cb, target0);
    jmp_ptr(cb, target1);
}

static bool
gen_branchunless(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Get the branch target instruction offsets
    int32_t jump_idx = (int32_t)ctx_get_arg(ctx, 0);
    int32_t next_idx = ctx->insn_idx + 1;
    blockid_t jump_block = { ctx->iseq, jump_idx };
    blockid_t next_block = { ctx->iseq, next_idx };

    // TODO: we need to eventually do an interrupt check when jumping/branching
    // How can we do this while keeping the check logic out of line?
	// RUBY_VM_CHECK_INTS(ec);

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    test(cb, val_opnd, imm_opnd(~Qnil));

    // Generate the branch instructions
    gen_branch(cb, ocb, jump_block, next_block, gen_branchunless_branch);

    return true;
}

void
ujit_init_codegen(void)
{
    // Initialize the code blocks
    size_t mem_size = 128 * 1024 * 1024;
    uint8_t* mem_block = alloc_exec_mem(mem_size);
    cb = &block;
    cb_init(cb, mem_block, mem_size/2);
    ocb = &outline_block;
    cb_init(ocb, mem_block + mem_size/2, mem_size/2);

    // Initialize the codegen function table
    gen_fns = rb_st_init_numtable();

    // Map YARV opcodes to the corresponding codegen functions
    st_insert(gen_fns, (st_data_t)BIN(dup), (st_data_t)&gen_dup);
    st_insert(gen_fns, (st_data_t)BIN(nop), (st_data_t)&gen_nop);
    st_insert(gen_fns, (st_data_t)BIN(pop), (st_data_t)&gen_pop);
    st_insert(gen_fns, (st_data_t)BIN(putnil), (st_data_t)&gen_putnil);
    st_insert(gen_fns, (st_data_t)BIN(putobject), (st_data_t)&gen_putobject);
    st_insert(gen_fns, (st_data_t)BIN(putobject_INT2FIX_0_), (st_data_t)&gen_putobject_int2fix);
    st_insert(gen_fns, (st_data_t)BIN(putobject_INT2FIX_1_), (st_data_t)&gen_putobject_int2fix);
    st_insert(gen_fns, (st_data_t)BIN(putself), (st_data_t)&gen_putself);
    st_insert(gen_fns, (st_data_t)BIN(getlocal_WC_0), (st_data_t)&gen_getlocal_wc0);
    st_insert(gen_fns, (st_data_t)BIN(setlocal_WC_0), (st_data_t)&gen_setlocal_wc0);
    st_insert(gen_fns, (st_data_t)BIN(getinstancevariable), (st_data_t)&gen_getinstancevariable);
    st_insert(gen_fns, (st_data_t)BIN(setinstancevariable), (st_data_t)&gen_setinstancevariable);
    st_insert(gen_fns, (st_data_t)BIN(opt_lt), (st_data_t)&gen_opt_lt);
    st_insert(gen_fns, (st_data_t)BIN(opt_minus), (st_data_t)&gen_opt_minus);
    st_insert(gen_fns, (st_data_t)BIN(opt_plus), (st_data_t)&gen_opt_plus);
    st_insert(gen_fns, (st_data_t)BIN(opt_send_without_block), (st_data_t)&gen_opt_send_without_block);
}
