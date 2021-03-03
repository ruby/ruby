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

// Print the current source location for debugging purposes
RBIMPL_ATTR_MAYBE_UNUSED()
static void
jit_print_loc(jitstate_t* jit, const char* msg)
{
    char *ptr;
    long len;
    VALUE path = rb_iseq_path(jit->iseq);
    RSTRING_GETMEM(path, ptr, len);
    fprintf(stderr, "%s %s:%u\n", msg, ptr, rb_iseq_line_no(jit->iseq, jit->insn_idx));
}

// Get the current instruction's opcode
static int
jit_get_opcode(jitstate_t* jit)
{
    return opcode_at_pc(jit->iseq, jit->pc);
}

// Get the index of the next instruction
static uint32_t
jit_next_idx(jitstate_t* jit)
{
    return jit->insn_idx + insn_len(jit_get_opcode(jit));
}

// Get an instruction argument by index
static VALUE
jit_get_arg(jitstate_t* jit, size_t arg_idx)
{
    RUBY_ASSERT(arg_idx + 1 < (size_t)insn_len(jit_get_opcode(jit)));
    return *(jit->pc + arg_idx + 1);
}

// Load a VALUE into a register and keep track of the reference if it is on the GC heap.
static void
jit_mov_gc_ptr(jitstate_t* jit, codeblock_t* cb, x86opnd_t reg, VALUE ptr)
{
    RUBY_ASSERT(reg.type == OPND_REG && reg.num_bits == 64);

    // Load the pointer constant into the specified register
    mov(cb, reg, const_ptr_opnd((void*)ptr));

    // The pointer immediate is encoded as the last part of the mov written out
    uint32_t ptr_offset = cb->write_pos - sizeof(VALUE);

    if (!SPECIAL_CONST_P(ptr)) {
        if (!rb_darray_append(&jit->block->gc_object_offsets, ptr_offset)) {
            rb_bug("allocation failed");
        }
    }
}

// Check if we are compiling the instruction at the stub PC
// Meaning we are compiling the instruction that is next to execute
static bool
jit_at_current_insn(jitstate_t* jit, ctx_t* ctx)
{
    const VALUE* stub_pc = jit->ec->cfp->pc;
    return (stub_pc == jit->pc);
}

// Peek at the topmost value on the Ruby stack
static VALUE
jit_peek_at_stack(jitstate_t* jit, ctx_t* ctx)
{
    RUBY_ASSERT(jit_at_current_insn(jit, ctx));

    VALUE* sp = jit->ec->cfp->sp + ctx->sp_offset;

    return *(sp - 1);
}

// Save uJIT registers prior to a C call
static void
ujit_save_regs(codeblock_t* cb)
{
    push(cb, REG_CFP);
    push(cb, REG_EC);
    push(cb, REG_SP);
    push(cb, REG_SP); // Maintain 16-byte RSP alignment
}

// Restore uJIT registers after a C call
static void
ujit_load_regs(codeblock_t* cb)
{
    pop(cb, REG_SP); // Maintain 16-byte RSP alignment
    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);
}

/**
Generate an inline exit to return to the interpreter
*/
static void
ujit_gen_exit(jitstate_t* jit, ctx_t* ctx, codeblock_t* cb, VALUE* exit_pc)
{
    // Write the adjusted SP back into the CFP
    if (ctx->sp_offset != 0)
    {
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx, 0);
        lea(cb, REG_SP, stack_pointer);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG_SP);
    }

    // Update the CFP on the EC
    mov(cb, member_opnd(REG_EC, rb_execution_context_t, cfp), REG_CFP);

    // Directly return the next PC, which is a constant
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), RAX);

    // Accumulate stats about interpreter exits
#if RUBY_DEBUG
    if (rb_ujit_opts.gen_stats) {
        mov(cb, RDI, const_ptr_opnd(exit_pc));
        call_ptr(cb, RSI, (void *)&rb_ujit_count_side_exit_op);
    }
#endif

    // Write the post call bytes
    cb_write_post_call_bytes(cb);
}

/**
Generate an out-of-line exit to return to the interpreter
*/
static uint8_t *
ujit_side_exit(jitstate_t* jit, ctx_t* ctx)
{
    uint8_t* code_ptr = cb_get_ptr(ocb, ocb->write_pos);

    // Table mapping opcodes to interpreter handlers
    const void * const *handler_table = rb_vm_get_insns_address_table();

    // FIXME: rewriting the old instruction is only necessary if we're
    // exiting right at an interpreter entry point

    // Write back the old instruction at the exit PC
    // Otherwise the interpreter may jump right back to the
    // JITted code we're trying to exit
    VALUE* exit_pc = iseq_pc_at_idx(jit->iseq, jit->insn_idx);
    int exit_opcode = opcode_at_pc(jit->iseq, exit_pc);
    void* handler_addr = (void*)handler_table[exit_opcode];
    mov(ocb, RAX, const_ptr_opnd(exit_pc));
    mov(ocb, RCX, const_ptr_opnd(handler_addr));
    mov(ocb, mem_opnd(64, RAX, 0), RCX);

    // Generate the code to exit to the interpreters
    ujit_gen_exit(jit, ctx, ocb, exit_pc);

    return code_ptr;
}

#if RUBY_DEBUG

// Increment a profiling counter with counter_name
#define GEN_COUNTER_INC(cb, counter_name) _gen_counter_inc(cb, &(ujit_runtime_counters . counter_name))
static void
_gen_counter_inc(codeblock_t *cb, int64_t *counter)
{
    if (!rb_ujit_opts.gen_stats) return;
     mov(cb, REG0, const_ptr_opnd(counter));
     cb_write_lock_prefix(cb); // for ractors.
     add(cb, mem_opnd(64, REG0, 0), imm_opnd(1));
}

// Increment a counter then take an existing side exit.
#define COUNTED_EXIT(side_exit, counter_name) _counted_side_exit(side_exit, &(ujit_runtime_counters . counter_name))
static uint8_t *
_counted_side_exit(uint8_t *existing_side_exit, int64_t *counter)
{
    if (!rb_ujit_opts.gen_stats) return existing_side_exit;

    uint8_t *start = cb_get_ptr(ocb, ocb->write_pos);
    _gen_counter_inc(ocb, counter);
    jmp_ptr(ocb, existing_side_exit);
    return start;
}

#else
#define GEN_COUNTER_INC(cb, counter_name) ((void)0)
#define COUNTED_EXIT(side_exit, counter_name) side_exit
#endif // if RUBY_DEBUG

/*
Compile an interpreter entry block to be inserted into an iseq
Returns `NULL` if compilation fails.
*/
uint8_t*
ujit_entry_prologue(void)
{
    RUBY_ASSERT(cb != NULL);

    if (cb->write_pos + 1024 >= cb->mem_size) {
        rb_bug("out of executable memory");
    }

    // Align the current write positon to cache line boundaries
    cb_align_pos(cb, 64);

    uint8_t *code_ptr = cb_get_ptr(cb, cb->write_pos);

    // Write the interpreter entry prologue
    cb_write_pre_call_bytes(cb);

    // Load the current SP from the CFP into REG_SP
    mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));

    return code_ptr;
}

/*
Generate code to check for interrupts and take a side-exit
*/
static void
ujit_check_ints(codeblock_t* cb, uint8_t* side_exit)
{
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    mov(cb, REG0_32, member_opnd(REG_EC, rb_execution_context_t, interrupt_mask));
    not(cb, REG0_32);
    test(cb, member_opnd(REG_EC, rb_execution_context_t, interrupt_flag), REG0_32);
    jnz_ptr(cb, side_exit);
}

/*
Compile a sequence of bytecode instructions for a given basic block version
*/
void
ujit_gen_block(ctx_t* ctx, block_t* block, rb_execution_context_t* ec)
{
    RUBY_ASSERT(cb != NULL);
    RUBY_ASSERT(block != NULL);

    const rb_iseq_t *iseq = block->blockid.iseq;
    uint32_t insn_idx = block->blockid.idx;

    // NOTE: if we are ever deployed in production, we
    // should probably just log an error and return NULL here,
    // so we can fail more gracefully
    if (cb->write_pos + 1024 >= cb->mem_size) {
        rb_bug("out of executable memory");
    }
    if (ocb->write_pos + 1024 >= ocb->mem_size) {
        rb_bug("out of executable memory (outlined block)");
    }

    // Initialize a JIT state object
    jitstate_t jit = {
        block,
        iseq,
        0,
        0,
        ec
    };

    // Mark the start position of the block
    block->start_pos = cb->write_pos;

    // For each instruction to compile
    for (;;) {
        // Set the current instruction
        jit.insn_idx = insn_idx;
        jit.pc = iseq_pc_at_idx(iseq, insn_idx);

        // Get the current opcode
        int opcode = jit_get_opcode(&jit);

        // Lookup the codegen function for this instruction
        codegen_fn gen_fn;
        if (!rb_st_lookup(gen_fns, opcode, (st_data_t*)&gen_fn)) {
            // If we reach an unknown instruction,
            // exit to the interpreter and stop compiling
            ujit_gen_exit(&jit, ctx, cb, jit.pc);
            break;
        }

        //fprintf(stderr, "compiling %d: %s\n", insn_idx, insn_name(opcode));
        //print_str(cb, insn_name(opcode));

        // Count bytecode instructions that execute in generated code
        // FIXME: when generation function returns false, we shouldn't increment
        //        this counter.
        GEN_COUNTER_INC(cb, exec_instruction);

        // Call the code generation function
        bool continue_generating = p_desc->gen_fn(&jit, ctx);

        if (!continue_generating) {
            break;
        }

        // Move to the next instruction
        p_last_op = p_desc;
        insn_idx += insn_len(opcode);

        // If the instruction terminates this block
        if (status == UJIT_END_BLOCK) {
            break;
        }
    }

    // Mark the end position of the block
    block->end_pos = cb->write_pos;

    // Store the index of the last instruction in the block
    block->end_idx = insn_idx;

    if (UJIT_DUMP_MODE >= 2) {
        // Dump list of compiled instrutions
        fprintf(stderr, "Compiled the following for iseq=%p:\n", (void *)iseq);
        for (uint32_t idx = block->blockid.idx; idx < insn_idx;)
        {
            int opcode = opcode_at_pc(iseq, iseq_pc_at_idx(iseq, idx));
            fprintf(stderr, "  %04d %s\n", idx, insn_name(opcode));
            idx += insn_len(opcode);
        }
    }
}

static codegen_status_t
gen_dup(jitstate_t* jit, ctx_t* ctx)
{
    // Get the top value and its type
    x86opnd_t dup_val = ctx_stack_pop(ctx, 0);
    int dup_type = ctx_get_top_type(ctx);

    // Push the same value on top
    x86opnd_t loc0 = ctx_stack_push(ctx, dup_type);
    mov(cb, REG0, dup_val);
    mov(cb, loc0, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_nop(jitstate_t* jit, ctx_t* ctx)
{
    // Do nothing
    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_pop(jitstate_t* jit, ctx_t* ctx)
{
    // Decrement SP
    ctx_stack_pop(ctx, 1);
    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putnil(jitstate_t* jit, ctx_t* ctx)
{
    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, T_NIL);
    mov(cb, stack_top, imm_opnd(Qnil));
    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putobject(jitstate_t* jit, ctx_t* ctx)
{
    VALUE arg = jit_get_arg(jit, 0);

    if (FIXNUM_P(arg))
    {
        // Keep track of the fixnum type tag
        x86opnd_t stack_top = ctx_stack_push(ctx, T_FIXNUM);

        x86opnd_t imm = imm_opnd((int64_t)arg);

        // 64-bit immediates can't be directly written to memory
        if (imm.num_bits <= 32)
        {
            mov(cb, stack_top, imm);
        }
        else
        {
            mov(cb, REG0, imm);
            mov(cb, stack_top, REG0);
        }
    }
    else if (arg == Qtrue || arg == Qfalse)
    {
        x86opnd_t stack_top = ctx_stack_push(ctx, T_NONE);
        mov(cb, stack_top, imm_opnd((int64_t)arg));
    }
    else
    {
        // Load the argument from the bytecode sequence.
        // We need to do this as the argument can change due to GC compaction.
        x86opnd_t pc_plus_one = const_ptr_opnd((void*)(jit->pc + 1));
        mov(cb, RAX, pc_plus_one);
        mov(cb, RAX, mem_opnd(64, RAX, 0));

        // Write argument at SP
        x86opnd_t stack_top = ctx_stack_push(ctx, T_NONE);
        mov(cb, stack_top, RAX);
    }

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putobject_int2fix(jitstate_t* jit, ctx_t* ctx)
{
    int opcode = jit_get_opcode(jit);
    int cst_val = (opcode == BIN(putobject_INT2FIX_0_))? 0:1;

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, T_FIXNUM);
    mov(cb, stack_top, imm_opnd(INT2FIX(cst_val)));

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putself(jitstate_t* jit, ctx_t* ctx)
{
    // Load self from CFP
    mov(cb, RAX, member_opnd(REG_CFP, rb_control_frame_t, self));

    // Write it on the stack
    x86opnd_t stack_top = ctx_stack_push(ctx, T_NONE);
    mov(cb, stack_top, RAX);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_getlocal_wc0(jitstate_t* jit, ctx_t* ctx)
{
    // Load environment pointer EP from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));

    // Compute the offset from BP to the local
    int32_t local_idx = (int32_t)jit_get_arg(jit, 0);
    const int32_t offs = -(SIZEOF_VALUE * local_idx);

    // Load the local from the block
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, T_NONE);
    mov(cb, stack_top, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_getlocal_wc1(jitstate_t* jit, ctx_t* ctx)
{
    //fprintf(stderr, "gen_getlocal_wc1\n");

    // Load environment pointer EP from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));

    // Get the previous EP from the current EP
    // See GET_PREV_EP(ep) macro
    // VALUE* prev_ep = ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))
    mov(cb, REG0, mem_opnd(64, REG0, SIZEOF_VALUE * VM_ENV_DATA_INDEX_SPECVAL));
    and(cb, REG0, imm_opnd(~0x03));

    // Load the local from the block
    // val = *(vm_get_ep(GET_EP(), level) - idx);
    int32_t local_idx = (int32_t)jit_get_arg(jit, 0);
    const int32_t offs = -(SIZEOF_VALUE * local_idx);
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, T_NONE);
    mov(cb, stack_top, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_setlocal_wc0(jitstate_t* jit, ctx_t* ctx)
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
    x86opnd_t flags_opnd = mem_opnd(64, REG0, sizeof(VALUE) * VM_ENV_DATA_INDEX_FLAGS);
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED));

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Pop the value to write from the stack
    x86opnd_t stack_top = ctx_stack_pop(ctx, 1);
    mov(cb, REG1, stack_top);

    // Write the value at the environment pointer
    int32_t local_idx = (int32_t)jit_get_arg(jit, 0);
    const int32_t offs = -8 * local_idx;
    mov(cb, mem_opnd(64, REG0, offs), REG1);

    return UJIT_KEEP_COMPILING;
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

static codegen_status_t
gen_getinstancevariable(jitstate_t* jit, ctx_t* ctx)
{
    IVC ic = (IVC)jit_get_arg(jit, 1);

    // Check that the inline cache has been set, slot index is known
    if (!ic->entry) {
        return UJIT_CANT_COMPILE;
    }







    /*
    if (defer_compilation(this_instruction, ctx))
        return JIT_END_BLOCK;

    VALUE top_val = jit_peek_at_stack();
    */









    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    if (rb_get_alloc_func(ic->entry->class_value) != rb_class_allocate_instance) {
        return UJIT_CANT_COMPILE;
    }

    uint32_t ivar_index = ic->entry->index;

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

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

    // check that the extended table is big enough
    if (ivar_index >= ROBJECT_EMBED_LEN_MAX + 1) {
        // Check that the slot is inside the extended table (num_slots > index)
        x86opnd_t num_slots = mem_opnd(32, REG0, offsetof(struct RObject, as.heap.numiv));
        cmp(cb, num_slots, imm_opnd(ivar_index));
        jle_ptr(cb, side_exit);
    }

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
    x86opnd_t out_opnd = ctx_stack_push(ctx, T_NONE);
    mov(cb, out_opnd, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_setinstancevariable(jitstate_t* jit, ctx_t* ctx)
{
    IVC ic = (IVC)jit_get_arg(jit, 1);

    // Check that the inline cache has been set, slot index is known
    if (!ic->entry) {
        return UJIT_CANT_COMPILE;
    }

    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    if (rb_get_alloc_func(ic->entry->class_value) != rb_class_allocate_instance) {
        return UJIT_CANT_COMPILE;
    }

    uint32_t ivar_index = ic->entry->index;

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

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
    if (ivar_index >= ROBJECT_EMBED_LEN_MAX + 1) {
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

    return UJIT_KEEP_COMPILING;
}

// Conditional move operation used by comparison operators
typedef void (*cmov_fn)(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);

static codegen_status_t
gen_fixnum_cmp(jitstate_t* jit, ctx_t* ctx, cmov_fn cmov_op)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

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
    int arg1_type = ctx_get_top_type(ctx);
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    int arg0_type = ctx_get_top_type(ctx);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // If not fixnums, fall back
    if (arg0_type != T_FIXNUM) {
        test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }
    if (arg1_type != T_FIXNUM) {
        test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }

    // Compare the arguments
    xor(cb, REG0_32, REG0_32); // REG0 = Qfalse
    mov(cb, REG1, arg0);
    cmp(cb, REG1, arg1);
    mov(cb, REG1, imm_opnd(Qtrue));
    cmov_op(cb, REG0, REG1);

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, T_NONE);
    mov(cb, dst, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_lt(jitstate_t* jit, ctx_t* ctx)
{
    return gen_fixnum_cmp(jit, ctx, cmovl);
}

static codegen_status_t
gen_opt_le(jitstate_t* jit, ctx_t* ctx)
{
    return gen_fixnum_cmp(jit, ctx, cmovle);
}

static codegen_status_t
gen_opt_ge(jitstate_t* jit, ctx_t* ctx)
{
    return gen_fixnum_cmp(jit, ctx, cmovge);
}

static codegen_status_t
gen_opt_aref(jitstate_t* jit, ctx_t* ctx)
{
    struct rb_call_data * cd = (struct rb_call_data *)jit_get_arg(jit, 0);
    int32_t argc = (int32_t)vm_ci_argc(cd->ci);

    // Only JIT one arg calls like `ary[6]`
    if (argc != 1) {
        return UJIT_CANT_COMPILE;
    }

    const rb_callable_method_entry_t *cme = vm_cc_cme(cd->cc);

    // Bail if the inline cache has been filled.  Currently, certain types
    // (including arrays) don't use the inline cache, so if the inline cache
    // has an entry, then this must be used by some other type.
    if (cme) {
        return UJIT_CANT_COMPILE;
    }

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

    // TODO: make a helper function for guarding on op-not-redefined
    // Make sure that aref isn't redefined for arrays.
    mov(cb, RAX, const_ptr_opnd(ruby_current_vm_ptr));
    test(
        cb,
        member_opnd_idx(RAX, rb_vm_t, redefined_flag, BOP_AREF),
        imm_opnd(ARRAY_REDEFINED_OP_FLAG)
    );
    jnz_ptr(cb, side_exit);

    // Pop the stack operands
    x86opnd_t idx_opnd = ctx_stack_pop(ctx, 1);
    x86opnd_t recv_opnd = ctx_stack_pop(ctx, 1);
    mov(cb, REG0, recv_opnd);

    // if (SPECIAL_CONST_P(recv)) {
    // Bail if it's not a heap object
    test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
    jnz_ptr(cb, side_exit);
    cmp(cb, REG0, imm_opnd(Qfalse));
    je_ptr(cb, side_exit);
    cmp(cb, REG0, imm_opnd(Qnil));
    je_ptr(cb, side_exit);

    // Bail if recv has a class other than ::Array.
    // BOP_AREF check above is only good for ::Array.
    mov(cb, REG1, mem_opnd(64, REG0, offsetof(struct RBasic, klass)));
    mov(cb, REG0, const_ptr_opnd((void *)rb_cArray));
    cmp(cb, REG0, REG1);
    jne_ptr(cb, side_exit);

    // Bail if idx is not a FIXNUM
    mov(cb, REG1, idx_opnd);
    test(cb, REG1, imm_opnd(RUBY_FIXNUM_FLAG));
    jz_ptr(cb, side_exit);

    // Save uJIT registers
    ujit_save_regs(cb);

    mov(cb, RDI, recv_opnd);
    sar(cb, REG1, imm_opnd(1)); // Convert fixnum to int
    mov(cb, RSI, REG1);
    call_ptr(cb, REG0, (void *)rb_ary_entry_internal);

    // Restore uJIT registers
    ujit_load_regs(cb);

    x86opnd_t stack_ret = ctx_stack_push(ctx, T_NONE);
    mov(cb, stack_ret, RAX);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_and(jitstate_t* jit, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

    // TODO: make a helper function for guarding on op-not-redefined
    // Make sure that plus isn't redefined for integers
    mov(cb, RAX, const_ptr_opnd(ruby_current_vm_ptr));
    test(
        cb,
        member_opnd_idx(RAX, rb_vm_t, redefined_flag, BOP_AND),
        imm_opnd(INTEGER_REDEFINED_OP_FLAG)
    );
    jnz_ptr(cb, side_exit);

    // Get the operands and destination from the stack
    int arg1_type = ctx_get_top_type(ctx);
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    int arg0_type = ctx_get_top_type(ctx);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // If not fixnums, fall back
    if (arg0_type != T_FIXNUM) {
        test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }
    if (arg1_type != T_FIXNUM) {
        test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }

    // Do the bitwise and arg0 & arg1
    mov(cb, REG0, arg0);
    and(cb, REG0, arg1);

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, T_FIXNUM);
    mov(cb, dst, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_minus(jitstate_t* jit, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

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
    x86opnd_t dst = ctx_stack_push(ctx, T_FIXNUM);
    mov(cb, dst, REG0);

    return UJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_plus(jitstate_t* jit, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

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
    int arg1_type = ctx_get_top_type(ctx);
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    int arg0_type = ctx_get_top_type(ctx);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // If not fixnums, fall back
    if (arg0_type != T_FIXNUM) {
        test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }
    if (arg1_type != T_FIXNUM) {
        test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }

    // Add arg0 + arg1 and test for overflow
    mov(cb, REG0, arg0);
    sub(cb, REG0, imm_opnd(1));
    add(cb, REG0, arg1);
    jo_ptr(cb, side_exit);

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, T_FIXNUM);
    mov(cb, dst, REG0);

    return UJIT_KEEP_COMPILING;
}

void
gen_branchif_branch(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape)
{
    switch (shape)
    {
        case SHAPE_NEXT0:
        jz_ptr(cb, target1);
        break;

        case SHAPE_NEXT1:
        jnz_ptr(cb, target0);
        break;

        case SHAPE_DEFAULT:
        jnz_ptr(cb, target0);
        jmp_ptr(cb, target1);
        break;
    }
}

static codegen_status_t
gen_branchif(jitstate_t* jit, ctx_t* ctx)
{
    // FIXME: eventually, put VM_CHECK_INTS() only on backward branch targets
    // Check for interrupts
    uint8_t* side_exit = ujit_side_exit(jit, ctx);
    ujit_check_ints(cb, side_exit);

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    test(cb, val_opnd, imm_opnd(~Qnil));

    // Get the branch target instruction offsets
    uint32_t next_idx = jit_next_idx(jit);
    uint32_t jump_idx = next_idx + (uint32_t)jit_get_arg(jit, 0);
    blockid_t next_block = { jit->iseq, next_idx };
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the branch instructions
    gen_branch(
        ctx,
        jump_block,
        ctx,
        next_block,
        ctx,
        gen_branchif_branch
    );

    return UJIT_END_BLOCK;
}

void 
gen_branchunless_branch(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape)
{
    switch (shape)
    {
        case SHAPE_NEXT0:
        jnz_ptr(cb, target1);
        break;

        case SHAPE_NEXT1:
        jz_ptr(cb, target0);
        break;

        case SHAPE_DEFAULT:
        jz_ptr(cb, target0);
        jmp_ptr(cb, target1);
        break;
    }
}

static codegen_status_t
gen_branchunless(jitstate_t* jit, ctx_t* ctx)
{
    // FIXME: eventually, put VM_CHECK_INTS() only on backward branch targets
    // Check for interrupts
    uint8_t* side_exit = ujit_side_exit(jit, ctx);
    ujit_check_ints(cb, side_exit);

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    test(cb, val_opnd, imm_opnd(~Qnil));

    // Get the branch target instruction offsets
    uint32_t next_idx = jit_next_idx(jit);
    uint32_t jump_idx = next_idx + (uint32_t)jit_get_arg(jit, 0);
    blockid_t next_block = { jit->iseq, next_idx };
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the branch instructions
    gen_branch(
        ctx,
        jump_block,
        ctx,
        next_block,
        ctx,
        gen_branchunless_branch
    );

    return UJIT_END_BLOCK;
}

static codegen_status_t
gen_jump(jitstate_t* jit, ctx_t* ctx)
{
    // FIXME: eventually, put VM_CHECK_INTS() only on backward branch targets
    // Check for interrupts
    uint8_t* side_exit = ujit_side_exit(jit, ctx);
    ujit_check_ints(cb, side_exit);

    // Get the branch target instruction offsets
    uint32_t jump_idx = jit_next_idx(jit) + (int32_t)jit_get_arg(jit, 0);
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the jump instruction
    gen_direct_jump(
        ctx,
        jump_block
    );

    return UJIT_END_BLOCK;
}

static void
jit_protected_guard(jitstate_t *jit, codeblock_t *cb, const rb_callable_method_entry_t *cme, uint8_t *side_exit)
{
    // Callee is protected. Generate ancestry guard.
    // See vm_call_method().
    ujit_save_regs(cb);
    mov(cb, C_ARG_REGS[0], member_opnd(REG_CFP, rb_control_frame_t, self));
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], cme->defined_class);
    // Note: PC isn't written to current control frame as rb_is_kind_of() shouldn't raise.
    // VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);
    call_ptr(cb, REG0, (void *)&rb_obj_is_kind_of);
    ujit_load_regs(cb);
    cmp(cb, RAX, imm_opnd(0));
    jz_ptr(cb, COUNTED_EXIT(side_exit, oswb_se_protected_check_failed));
}

static bool
gen_oswb_cfunc(jitstate_t* jit, ctx_t* ctx, struct rb_call_data * cd, const rb_callable_method_entry_t *cme, int32_t argc)
{
    const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);

    // If the function expects a Ruby array of arguments
    if (cfunc->argc < 0 && cfunc->argc != -1)
    {
        GEN_COUNTER_INC(cb, oswb_cfunc_ruby_array_varg);
        return false;
    }

    // If the argument count doesn't match
    if (cfunc->argc >= 0 && cfunc->argc != argc)
    {
        GEN_COUNTER_INC(cb, oswb_cfunc_argc_mismatch);
        return false;
    }

    // Don't JIT functions that need C stack arguments for now
    if (argc + 1 > NUM_C_ARG_REGS) {
        GEN_COUNTER_INC(cb, oswb_cfunc_toomany_args);
        return false;
    }

    // Create a size-exit to fall back to the interpreter
    uint8_t *side_exit = ujit_side_exit(jit, ctx);

    // Check for interrupts
    ujit_check_ints(cb, side_exit);

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
    {
        uint8_t *receiver_not_heap = COUNTED_EXIT(side_exit, oswb_se_receiver_not_heap);
        test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
        jnz_ptr(cb, receiver_not_heap);
        cmp(cb, REG0, imm_opnd(Qfalse));
        je_ptr(cb, receiver_not_heap);
        cmp(cb, REG0, imm_opnd(Qnil));
        je_ptr(cb, receiver_not_heap);
    }

    // Pointer to the klass field of the receiver &(recv->klass)
    x86opnd_t klass_opnd = mem_opnd(64, REG0, offsetof(struct RBasic, klass));

    // FIXME: This leaks when st_insert raises NoMemoryError
    assume_method_lookup_stable(cd->cc, cme, jit->block);

    // Bail if receiver class is different from compile-time call cache class
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)cd->cc->klass);
    cmp(cb, klass_opnd, REG1);
    jne_ptr(cb, COUNTED_EXIT(side_exit, oswb_se_cc_klass_differ));

    // Store incremented PC into current control frame in case callee raises.
    mov(cb, REG0, const_ptr_opnd(jit->pc + insn_len(BIN(opt_send_without_block))));
    mov(cb, mem_opnd(64, REG_CFP, offsetof(rb_control_frame_t, pc)), REG0);

    if (METHOD_ENTRY_VISI(cme) == METHOD_VISI_PROTECTED) {
        // Generate ancestry guard for protected callee.
        jit_protected_guard(jit, cb, cme, side_exit);
    }

    // If this function needs a Ruby stack frame
    if (cfunc_needs_frame(cfunc))
    {
        // Stack overflow check
        // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
        // REG_CFP <= REG_SP + 4 * sizeof(VALUE) + sizeof(rb_control_frame_t)
        lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * 4 + sizeof(rb_control_frame_t)));
        cmp(cb, REG_CFP, REG0);
        jle_ptr(cb, COUNTED_EXIT(side_exit, oswb_se_cf_overflow));

        // Increment the stack pointer by 3 (in the callee)
        // sp += 3
        lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * 3));

        // Put compile time cme into REG1. It's assumed to be valid because we are notified when
        // any cme we depend on become outdated. See rb_ujit_method_lookup_change().
        jit_mov_gc_ptr(jit, cb, REG1, (VALUE)cme);
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

    // Verify that we are calling the right function
    if (UJIT_CHECK_MODE > 0) {
        // Save uJIT registers
        ujit_save_regs(cb);

        // Call check_cfunc_dispatch
        mov(cb, RDI, recv);
        jit_mov_gc_ptr(jit, cb, RSI, (VALUE)cd);
        mov(cb, RDX, const_ptr_opnd((void *)cfunc->func));
        jit_mov_gc_ptr(jit, cb, RCX, (VALUE)cme);
        call_ptr(cb, REG0, (void *)&check_cfunc_dispatch);

        // Load uJIT registers
        ujit_load_regs(cb);
    }

    // Save uJIT registers
    ujit_save_regs(cb);

    // Copy SP into RAX because REG_SP will get overwritten
    lea(cb, RAX, ctx_sp_opnd(ctx, 0));

    // Non-variadic method
    if (cfunc->argc >= 0)
    {
        // Copy the arguments from the stack to the C argument registers
        // self is the 0th argument and is at index argc from the stack top
        for (int32_t i = 0; i < argc + 1; ++i)
        {
            x86opnd_t stack_opnd = mem_opnd(64, RAX, -(argc + 1 - i) * SIZEOF_VALUE);
            x86opnd_t c_arg_reg = C_ARG_REGS[i];
            mov(cb, c_arg_reg, stack_opnd);
        }
    }
    // Variadic method
    if (cfunc->argc == -1)
    {
        // The method gets a pointer to the first argument
        // rb_f_puts(int argc, VALUE *argv, VALUE recv)
        mov(cb, C_ARG_REGS[0], imm_opnd(argc));
        lea(cb, C_ARG_REGS[1], mem_opnd(64, RAX, -(argc) * SIZEOF_VALUE));
        mov(cb, C_ARG_REGS[2], mem_opnd(64, RAX, -(argc + 1) * SIZEOF_VALUE));
    }

    // Pop the C function arguments from the stack (in the caller)
    ctx_stack_pop(ctx, argc + 1);

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
    // cfunc comes from compile-time cme->def, which we assume to be stable.
    // Invalidation logic is in rb_ujit_method_lookup_change()
    call_ptr(cb, REG0, (void*)cfunc->func);

    // Load uJIT registers
    ujit_load_regs(cb);

    // Push the return value on the Ruby stack
    x86opnd_t stack_ret = ctx_stack_push(ctx, T_NONE);
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

    // Jump (fall through) to the call continuation block
    // We do this to end the current block after the call
    blockid_t cont_block = { jit->iseq, jit_next_idx(jit) };
    gen_direct_jump(
        ctx,
        cont_block
    );

    return UJIT_END_BLOCK;
}

bool rb_simple_iseq_p(const rb_iseq_t *iseq);

static void
gen_return_branch(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape)
{
    switch (shape)
    {
        case SHAPE_NEXT0:
        case SHAPE_NEXT1:
        RUBY_ASSERT(false);
        break;

        case SHAPE_DEFAULT:
        mov(cb, REG0, const_ptr_opnd(target0));
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, jit_return), REG0);
        break;
    }
}

static codegen_status_t
gen_oswb_iseq(jitstate_t* jit, ctx_t* ctx, struct rb_call_data * cd, const rb_callable_method_entry_t *cme, int32_t argc)
{
    const rb_iseq_t *iseq = def_iseq_ptr(cme->def);
    const VALUE* start_pc = iseq->body->iseq_encoded;
    int num_params = iseq->body->param.size;
    int num_locals = iseq->body->local_table_size - num_params;

    if (num_params != argc) {
        GEN_COUNTER_INC(cb, oswb_iseq_argc_mismatch);
        return false;
    }

    if (!rb_simple_iseq_p(iseq)) {
        // Only handle iseqs that have simple parameters.
        // See vm_callee_setup_arg().
        GEN_COUNTER_INC(cb, oswb_iseq_not_simple);
        return false;
    }

    if (vm_ci_flag(cd->ci) & VM_CALL_TAILCALL) {
        // We can't handle tailcalls
        GEN_COUNTER_INC(cb, oswb_iseq_tailcall);
        return false;
    }

    rb_gc_register_mark_object((VALUE)iseq); // FIXME: intentional LEAK!

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

    // Check for interrupts
    ujit_check_ints(cb, side_exit);

    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);
    mov(cb, REG0, recv);

    // Callee method ID
    //ID mid = vm_ci_mid(cd->ci);
    //printf("JITting call to Ruby function \"%s\", argc: %d\n", rb_id2name(mid), argc);
    //print_str(cb, "");
    //print_str(cb, "recv");
    //print_ptr(cb, recv);

    // Check that the receiver is a heap object
    {
        uint8_t *receiver_not_heap = COUNTED_EXIT(side_exit, oswb_se_receiver_not_heap);
        test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
        jnz_ptr(cb, receiver_not_heap);
        cmp(cb, REG0, imm_opnd(Qfalse));
        je_ptr(cb, receiver_not_heap);
        cmp(cb, REG0, imm_opnd(Qnil));
        je_ptr(cb, receiver_not_heap);
    }

    // Pointer to the klass field of the receiver &(recv->klass)
    x86opnd_t klass_opnd = mem_opnd(64, REG0, offsetof(struct RBasic, klass));

    assume_method_lookup_stable(cd->cc, cme, jit->block);

    // Bail if receiver class is different from compile-time call cache class
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)cd->cc->klass);
    cmp(cb, klass_opnd, REG1);
    jne_ptr(cb, COUNTED_EXIT(side_exit, oswb_se_cc_klass_differ));


    if (METHOD_ENTRY_VISI(cme) == METHOD_VISI_PROTECTED) {
        // Generate ancestry guard for protected callee.
        jit_protected_guard(jit, cb, cme, side_exit);
    }

    // Store the updated SP on the current frame (pop arguments and receiver)
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * -(argc + 1)));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG0);

    // Store the next PC i the current frame
    mov(cb, REG0, const_ptr_opnd(jit->pc + insn_len(BIN(opt_send_without_block))));
    mov(cb, mem_opnd(64, REG_CFP, offsetof(rb_control_frame_t, pc)), REG0);

    // Stack overflow check
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * (num_locals + iseq->body->stack_max) + sizeof(rb_control_frame_t)));
    cmp(cb, REG_CFP, REG0);
    jle_ptr(cb, COUNTED_EXIT(side_exit, oswb_se_cf_overflow));

    // Adjust the callee's stack pointer
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * (3 + num_locals)));

    // Initialize local variables to Qnil
    for (int i = 0; i < num_locals; i++) {
        mov(cb, mem_opnd(64, REG0, sizeof(VALUE) * (i - num_locals - 3)), imm_opnd(Qnil));
    }

    // Put compile time cme into REG1. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See rb_ujit_method_lookup_change().
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)cme);
    // Write method entry at sp[-3]
    // sp[-3] = me;
    mov(cb, mem_opnd(64, REG0, 8 * -3), REG1);

    // Write block handler at sp[-2]
    // sp[-2] = block_handler;
    mov(cb, mem_opnd(64, REG0, 8 * -2), imm_opnd(VM_BLOCK_HANDLER_NONE));

    // Write env flags at sp[-1]
    // sp[-1] = frame_type;
    uint64_t frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
    mov(cb, mem_opnd(64, REG0, 8 * -1), imm_opnd(frame_type));

    // Allocate a new CFP (ec->cfp--)
    sub(cb, REG_CFP, imm_opnd(sizeof(rb_control_frame_t)));
    mov(cb, member_opnd(REG_EC, rb_execution_context_t, cfp), REG_CFP);

    // Setup the new frame
    // *cfp = (const struct rb_control_frame_struct) {
    //    .pc         = pc,
    //    .sp         = sp,
    //    .iseq       = iseq,
    //    .self       = recv,
    //    .ep         = sp - 1,
    //    .block_code = 0,
    //    .__bp__     = sp,
    // };
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, block_code), imm_opnd(0));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG0);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, __bp__), REG0);
    sub(cb, REG0, imm_opnd(sizeof(VALUE)));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, ep), REG0);
    mov(cb, REG0, recv);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, self), REG0);
    jit_mov_gc_ptr(jit, cb, REG0, (VALUE)iseq);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, iseq), REG0);
    mov(cb, REG0, const_ptr_opnd(start_pc));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), REG0);

    // Stub so we can return to JITted code
    blockid_t return_block = { jit->iseq, jit_next_insn_idx(jit) };

    // Pop arguments and receiver in return context, push the return value
    // After the return, the JIT and interpreter SP will match up
    ctx_t return_ctx = *ctx;
    ctx_stack_pop(&return_ctx, argc + 1);
    ctx_stack_push(&return_ctx, T_NONE);
    return_ctx.sp_offset = 0;

    // Write the JIT return address on the callee frame
    gen_branch(
        ctx,
        return_block,
        &return_ctx,
        return_block,
        &return_ctx,
        gen_return_branch
    );

    //print_str(cb, "calling Ruby func:");
    //print_str(cb, rb_id2name(vm_ci_mid(cd->ci)));

    // Load the updated SP
    mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));

    // Directly jump to the entry point of the callee
    gen_direct_jump(
        &DEFAULT_CTX,
        (blockid_t){ iseq, 0 }
    );

    // TODO: create stub for call continuation

    // TODO: need to pop args in the caller ctx

    // TODO: stub so we can return to JITted code
    //blockid_t cont_block = { jit->iseq, jit_next_insn_idx(jit) };



    return UJIT_END_BLOCK;
}

static codegen_status_t
gen_opt_send_without_block(jitstate_t* jit, ctx_t* ctx)
{
    // Relevant definitions:
    // rb_execution_context_t       : vm_core.h
    // invoker, cfunc logic         : method.h, vm_method.c
    // rb_callable_method_entry_t   : method.h
    // vm_call_cfunc_with_frame     : vm_insnhelper.c
    // rb_callcache                 : vm_callinfo.h

    struct rb_call_data * cd = (struct rb_call_data *)jit_get_arg(jit, 0);
    int32_t argc = (int32_t)vm_ci_argc(cd->ci);

    // Don't JIT calls with keyword splat
    if (vm_ci_flag(cd->ci) & VM_CALL_KW_SPLAT) {
        GEN_COUNTER_INC(cb, oswb_kw_splat);
        return false;
    }

    // Don't JIT calls that aren't simple
    if (!(vm_ci_flag(cd->ci) & VM_CALL_ARGS_SIMPLE)) {
        GEN_COUNTER_INC(cb, oswb_callsite_not_simple);
        return false;
    }

    // Don't JIT if the inline cache is not set
    if (!cd->cc || !cd->cc->klass) {
        GEN_COUNTER_INC(cb, oswb_ic_empty);
        return false;
    }

    const rb_callable_method_entry_t *cme = vm_cc_cme(cd->cc);

    // Don't JIT if the method entry is out of date
    if (METHOD_ENTRY_INVALIDATED(cme)) {
        GEN_COUNTER_INC(cb, oswb_invalid_cme);
        return false;
    }

    switch (cme->def->type) {
    case VM_METHOD_TYPE_ISEQ:
        return gen_oswb_iseq(jit, ctx, cd, cme, argc);
    case VM_METHOD_TYPE_CFUNC:
        return gen_oswb_cfunc(jit, ctx, cd, cme, argc);
    case VM_METHOD_TYPE_ATTRSET:
        GEN_COUNTER_INC(cb, oswb_ivar_set_method);
        return false;
    case VM_METHOD_TYPE_BMETHOD:
        GEN_COUNTER_INC(cb, oswb_bmethod);
        return false;
    case VM_METHOD_TYPE_IVAR:
        GEN_COUNTER_INC(cb, oswb_ivar_get_method);
        return false;
    case VM_METHOD_TYPE_ZSUPER:
        GEN_COUNTER_INC(cb, oswb_zsuper_method);
        return false;
    case VM_METHOD_TYPE_ALIAS:
        GEN_COUNTER_INC(cb, oswb_alias_method);
        return false;
    case VM_METHOD_TYPE_UNDEF:
        GEN_COUNTER_INC(cb, oswb_undef_method);
        return false;
    case VM_METHOD_TYPE_NOTIMPLEMENTED:
        GEN_COUNTER_INC(cb, oswb_not_implemented_method);
        return false;
    case VM_METHOD_TYPE_OPTIMIZED:
        GEN_COUNTER_INC(cb, oswb_optimized_method);
        return false;
    case VM_METHOD_TYPE_MISSING:
        GEN_COUNTER_INC(cb, oswb_missing_method);
        return false;
    case VM_METHOD_TYPE_REFINED:
        GEN_COUNTER_INC(cb, oswb_refined_method);
        return false;
    // no default case so compiler issues a warning if this is not exhaustive
    }
}

static codegen_status_t
gen_leave(jitstate_t* jit, ctx_t* ctx)
{
    // Only the return value should be on the stack
    RUBY_ASSERT(ctx->stack_size == 1);

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(jit, ctx);

    // Load environment pointer EP from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));

    // if (flags & VM_FRAME_FLAG_FINISH) != 0
    x86opnd_t flags_opnd = mem_opnd(64, REG0, sizeof(VALUE) * VM_ENV_DATA_INDEX_FLAGS);
    test(cb, flags_opnd, imm_opnd(VM_FRAME_FLAG_FINISH));
    jnz_ptr(cb, side_exit);

    // Check for interrupts
    ujit_check_ints(cb, side_exit);

    // Load the return value
    mov(cb, REG0, ctx_stack_pop(ctx, 1));

    // Load the JIT return address
    mov(cb, REG1, member_opnd(REG_CFP, rb_control_frame_t, jit_return));

    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    add(cb, REG_CFP, imm_opnd(sizeof(rb_control_frame_t)));
    mov(cb, member_opnd(REG_EC, rb_execution_context_t, cfp), REG_CFP);

    // Push the return value on the caller frame
    // The SP points one above the topmost value
    add(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), imm_opnd(SIZEOF_VALUE));
    mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));
    mov(cb, mem_opnd(64, REG_SP, -SIZEOF_VALUE), REG0);  

    // If the return address is NULL, fall back to the interpreter
    int FALLBACK_LABEL = cb_new_label(cb, "FALLBACK");
    cmp(cb, REG1, imm_opnd(0));
    jz_label(cb, FALLBACK_LABEL);

    // Jump to the JIT return address
    jmp_rm(cb, REG1);

    // Fall back to the interpreter
    cb_write_label(cb, FALLBACK_LABEL);
    cb_link_labels(cb);
    cb_write_post_call_bytes(cb);

    return UJIT_END_BLOCK;
}

RUBY_EXTERN rb_serial_t ruby_vm_global_constant_state;
static codegen_status_t
gen_opt_getinlinecache(jitstate_t *jit, ctx_t *ctx)
{
    VALUE jump_offset = jit_get_arg(jit, 0);
    VALUE const_cache_as_value = jit_get_arg(jit, 1);
    IC ic = (IC)const_cache_as_value;

    // See vm_ic_hit_p().
    struct iseq_inline_constant_cache_entry *ice = ic->entry;
    if (!ice) {
        // Cache not filled
        return UJIT_CANT_COMPILE;
    }
    if (ice->ic_serial != ruby_vm_global_constant_state) {
        // Cache miss at compile time.
        return UJIT_CANT_COMPILE;
    }
    if (ice->ic_cref) {
        // Only compile for caches that don't care about lexical scope.
        return UJIT_CANT_COMPILE;
    }

    // Optimize for single ractor mode.
    // FIXME: This leaks when st_insert raises NoMemoryError
    if (!assume_single_ractor_mode(jit->block)) return UJIT_CANT_COMPILE;

    // Invalidate output code on any and all constant writes
    // FIXME: This leaks when st_insert raises NoMemoryError
    if (!assume_stable_global_constant_state(jit->block)) return UJIT_CANT_COMPILE;

    x86opnd_t stack_top = ctx_stack_push(ctx, T_NONE);
    jit_mov_gc_ptr(jit, cb, REG0, ice->value);
    mov(cb, stack_top, REG0);

    // Jump over the code for filling the cache
    uint32_t jump_idx = jit_next_insn_idx(jit) + (int32_t)jump_offset;
    gen_direct_jump(
        ctx,
        (blockid_t){ .iseq = jit->iseq, .idx = jump_idx }
    );

    return UJIT_END_BLOCK;
}

void ujit_reg_op(int opcode, codegen_fn gen_fn)
{
    // Check that the op wasn't previously registered
    st_data_t st_gen;
    if (rb_st_lookup(gen_fns, opcode, &st_gen)) {
        rb_bug("op already registered");
    }

    st_insert(gen_fns, (st_data_t)opcode, (st_data_t)gen_fn);
}

void
ujit_init_codegen(void)
{
    // Initialize the code blocks
    uint32_t mem_size = 128 * 1024 * 1024;
    uint8_t* mem_block = alloc_exec_mem(mem_size);
    cb = &block;
    cb_init(cb, mem_block, mem_size/2);
    ocb = &outline_block;
    cb_init(ocb, mem_block + mem_size/2, mem_size/2);

    // Initialize the codegen function table
    gen_fns = rb_st_init_numtable();

    // Map YARV opcodes to the corresponding codegen functions
    ujit_reg_op(BIN(dup), gen_dup);
    ujit_reg_op(BIN(nop), gen_nop);
    ujit_reg_op(BIN(pop), gen_pop);
    ujit_reg_op(BIN(putnil), gen_putnil);
    ujit_reg_op(BIN(putobject), gen_putobject);
    ujit_reg_op(BIN(putobject_INT2FIX_0_), gen_putobject_int2fix);
    ujit_reg_op(BIN(putobject_INT2FIX_1_), gen_putobject_int2fix);
    ujit_reg_op(BIN(putself), gen_putself);
    ujit_reg_op(BIN(getlocal_WC_0), gen_getlocal_wc0);
    ujit_reg_op(BIN(getlocal_WC_1), gen_getlocal_wc1);
    ujit_reg_op(BIN(setlocal_WC_0), gen_setlocal_wc0);
    ujit_reg_op(BIN(getinstancevariable), gen_getinstancevariable);
    ujit_reg_op(BIN(setinstancevariable), gen_setinstancevariable);
    ujit_reg_op(BIN(opt_lt), gen_opt_lt);
    ujit_reg_op(BIN(opt_le), gen_opt_le);
    ujit_reg_op(BIN(opt_ge), gen_opt_ge);
    ujit_reg_op(BIN(opt_aref), gen_opt_aref);
    ujit_reg_op(BIN(opt_and), gen_opt_and);
    ujit_reg_op(BIN(opt_minus), gen_opt_minus);
    ujit_reg_op(BIN(opt_plus), gen_opt_plus);

    // Map branch instruction opcodes to codegen functions
    ujit_reg_op(BIN(opt_getinlinecache), gen_opt_getinlinecache);
    ujit_reg_op(BIN(branchif), gen_branchif);
    ujit_reg_op(BIN(branchunless), gen_branchunless);
    ujit_reg_op(BIN(jump), gen_jump);
    ujit_reg_op(BIN(opt_send_without_block), gen_opt_send_without_block);
    ujit_reg_op(BIN(leave), gen_leave);
}
