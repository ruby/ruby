#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "internal/compile.h"
#include "insns_info.inc"
#include "ujit_compile.h"
#include "ujit_asm.h"
#include "ujit_utils.h"

// TODO: give ujit_examples.inc some more meaningful file name
// eg ujit_hook.h
#include "ujit_examples.inc"

#ifdef _WIN32
#define PLATFORM_SUPPORTED_P 0
#else
#define PLATFORM_SUPPORTED_P 1
#endif

bool rb_ujit_enabled;

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

// Code generation context
typedef struct ctx_struct
{
    // Current PC
    VALUE *pc;

    // Difference between the current stack pointer and actual stack top
    int32_t stack_diff;

    const rb_iseq_t *iseq;

} ctx_t;

// MicroJIT code generation function signature
typedef bool (*codegen_fn)(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx);

// Map from YARV opcodes to code generation functions
static st_table *gen_fns;

// Code block into which we write machine code
static codeblock_t block;
static codeblock_t* cb = NULL;

// Code block into which we write out-of-line machine code
static codeblock_t outline_block;
static codeblock_t* ocb = NULL;

// Register MicroJIT receives the CFP and EC into
#define REG_CFP RDI
#define REG_EC RSI

// Register MicroJIT loads the SP into
#define REG_SP RDX

// Scratch registers used by MicroJIT
#define REG0 RAX
#define REG1 RCX
#define REG0_32 EAX
#define REG1_32 ECX

// Keep track of mapping from instructions to generated code
// See comment for rb_encoded_insn_data in iseq.c
static void
addr2insn_bookkeeping(void *code_ptr, int insn)
{
    const void * const *table = rb_vm_get_insns_address_table();
    const void * const translated_address = table[insn];
    st_data_t encoded_insn_data;
    if (st_lookup(rb_encoded_insn_data, (st_data_t)translated_address, &encoded_insn_data)) {
        st_insert(rb_encoded_insn_data, (st_data_t)code_ptr, encoded_insn_data);
    }
    else {
        rb_bug("ujit: failed to find info for original instruction while dealing with addr2insn");
    }
}

static int
opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc)
{
    const VALUE at_pc = *pc;
    if (FL_TEST_RAW((VALUE)iseq, ISEQ_TRANSLATED)) {
        return rb_vm_insn_addr2opcode((const void *)at_pc);
    }
    else {
        return (int)at_pc;
    }
}

// Get the current instruction opcode from the context object
int ctx_get_opcode(ctx_t *ctx)
{
    return opcode_at_pc(ctx->iseq, ctx->pc);
}


// Get an instruction argument from the context object
VALUE ctx_get_arg(ctx_t* ctx, size_t arg_idx)
{
    assert (arg_idx + 1 < insn_len(ctx_get_opcode(ctx)));
    return *(ctx->pc + arg_idx + 1);
}

/*
Get an operand for the adjusted stack pointer address
*/
x86opnd_t ctx_sp_opnd(ctx_t* ctx)
{
    int32_t offset = (ctx->stack_diff) * 8;
    return mem_opnd(64, REG_SP, offset);
}

/*
Make space on the stack for N values
Return a pointer to the new stack top
*/
x86opnd_t ctx_stack_push(ctx_t* ctx, size_t n)
{
    ctx->stack_diff += n;

    // SP points just above the topmost value
    int32_t offset = (ctx->stack_diff - 1) * 8;
    return mem_opnd(64, REG_SP, offset);
}

/*
Pop N values off the stack
Return a pointer to the stack top before the pop operation
*/
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_diff - 1) * 8;
    x86opnd_t top = mem_opnd(64, REG_SP, offset);

    ctx->stack_diff -= n;

    return top;
}

x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_diff - 1 - idx) * 8;
    x86opnd_t opnd = mem_opnd(64, REG_SP, offset);

    return opnd;
}

// Ruby instruction entry
static void
ujit_gen_entry(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_pre_call_with_ec_bytes); ++i)
        cb_write_byte(cb, ujit_pre_call_with_ec_bytes[i]);
}

/**
Generate an inline exit to return to the interpreter
*/
static void
ujit_gen_exit(codeblock_t* cb, ctx_t* ctx, VALUE* exit_pc)
{
    // Write the adjusted SP back into the CFP
    if (ctx->stack_diff != 0)
    {
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx);
        lea(cb, REG_SP, stack_pointer);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG_SP);
    }

    // Directly return the next PC, which is a constant
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), RAX);

    // Write the post call bytes
    for (size_t i = 0; i < sizeof(ujit_post_call_with_ec_bytes); ++i)
        cb_write_byte(cb, ujit_post_call_with_ec_bytes[i]);
}

/**
Generate an out-of-line exit to return to the interpreter
*/
uint8_t*
ujit_side_exit(codeblock_t* cb, ctx_t* ctx, VALUE* exit_pc)
{
    uint8_t* code_ptr = cb_get_ptr(cb, cb->write_pos);

    // Write back the old instruction at the exit PC
    // Otherwise the interpreter may jump right back to the
    // JITted code we're trying to exit
    const void * const *table = rb_vm_get_insns_address_table();
    int opcode = opcode_at_pc(ctx->iseq, exit_pc);
    void* old_instr = (void*)table[opcode];
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, RCX, const_ptr_opnd(old_instr));
    mov(cb, mem_opnd(64, RAX, 0), RCX);

    // Generate the code to exit to the interpreters
    ujit_gen_exit(cb, ctx, exit_pc);

    return code_ptr;
}

/*
Generate a chunk of machine code for one individual bytecode instruction
Eventually, this will handle multiple instructions in a sequence
*/
uint8_t *
ujit_compile_insn(const rb_iseq_t *iseq, unsigned int insn_idx, unsigned int* next_ujit_idx)
{
    assert (cb != NULL);

    VALUE *encoded = iseq->body->iseq_encoded;

    // NOTE: if we are ever deployed in production, we
    // should probably just log an error and return NULL here,
    // so we can fail more gracefully
    if (cb->write_pos + 1024 >= cb->mem_size)
    {
        rb_bug("out of executable memory");
    }
    if (ocb->write_pos + 1024 >= ocb->mem_size)
    {
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
    ctx_t ctx;
    ctx.pc = NULL;
    ctx.stack_diff = 0;
    ctx.iseq = iseq;

    // For each instruction to compile
    size_t num_instrs;
    for (num_instrs = 0;; ++num_instrs)
    {
        // Set the current PC
        ctx.pc = &encoded[insn_idx];

        // Get the current opcode
        int opcode = ctx_get_opcode(&ctx);

        // Lookup the codegen function for this instruction
        st_data_t st_gen_fn;
        if (!rb_st_lookup(gen_fns, opcode, &st_gen_fn))
        {
            //print_int(cb, imm_opnd(num_instrs));
            //print_str(cb, insn_name(opcode));
            break;
        }

        // Write the pre call bytes before the first instruction
        if (num_instrs == 0)
        {
            ujit_gen_entry(cb);

            // Load the current SP from the CFP into REG_SP
            mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));
        }

        // Call the code generation function
        codegen_fn gen_fn = (codegen_fn)st_gen_fn;
        if (!gen_fn(cb, ocb, &ctx))
        {
            break;
        }

    	// Move to the next instruction
        insn_idx += insn_len(opcode);
    }

    // Let the caller know how many instructions ujit compiled
    *next_ujit_idx = insn_idx;

    // If no instructions were compiled
    if (num_instrs == 0)
    {
        return NULL;
    }

    // Generate code to exit to the interpreter
    ujit_gen_exit(cb, &ctx, ctx.pc);

    addr2insn_bookkeeping(code_ptr, first_opcode);

    return code_ptr;
}

bool
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

bool
gen_nop(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Do nothing
    return true;
}

bool
gen_pop(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Decrement SP
    ctx_stack_pop(ctx, 1);
    return true;
}

bool
gen_putnil(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(Qnil));
    return true;
}

bool
gen_putobject(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load the argument from the bytecode sequence.
    // We need to do this as the argument can chanage due to GC compaction.
    x86opnd_t pc_imm = const_ptr_opnd((void*)ctx->pc);
    mov(cb, RAX, pc_imm);
    mov(cb, RAX, mem_opnd(64, RAX, 8)); // One after the opcode

    // Write argument at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RAX);

    return true;
}

bool
gen_putobject_int2fix(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    int opcode = ctx_get_opcode(ctx);
    int cst_val = (opcode == BIN(putobject_INT2FIX_0_))? 0:1;

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(INT2FIX(cst_val)));

    return true;
}

bool
gen_putself(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load self from CFP
    mov(cb, RAX, member_opnd(REG_CFP, rb_control_frame_t, self));

    // Write it on the stack
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RAX);

    return true;
}

bool
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

bool
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
    uint8_t* side_exit = ujit_side_exit(ocb, ctx, ctx->pc);

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

bool
gen_opt_minus(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    // Note: we generate the side-exit before popping operands from the stack
    uint8_t* side_exit = ujit_side_exit(ocb, ctx, ctx->pc);

    // TODO: make a helper function for this
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
    mov(cb, RAX, arg0);
    sub(cb, RAX, arg1);
    jo_ptr(cb, side_exit);
    add(cb, RAX, imm_opnd(1));

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, 1);
    mov(cb, dst, RAX);

    return true;
}

bool
gen_opt_send_without_block(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Relevant definitions:
    // vm_call_cfunc_with_frame : vm_insnhelper.c
    // rb_callcache             : vm_callinfo.h
    // invoker, cfunc logic     : method.h, vm_method.c
    // rb_callable_method_entry_t: method.h

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
    if (cd->cc == vm_cc_empty())
    {
        //printf("call cache is empty\n");
        return false;
    }

    const rb_callable_method_entry_t *me = vm_cc_cme(cd->cc);

    // Don't JIT if this is not a C call
    if (me->def->type != VM_METHOD_TYPE_CFUNC)
    {
        return false;
    }

    const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(me->def, body.cfunc);

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
    uint8_t* side_exit = ujit_side_exit(ocb, ctx, ctx->pc);

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

    // Load the call cache pointer into REG1
    mov(cb, REG1, const_ptr_opnd(cd));
    x86opnd_t ptr_to_cc = member_opnd(REG1, struct rb_call_data, cc);
    mov(cb, REG1, ptr_to_cc);

    // Check the class of the receiver against the call cache
    mov(cb, REG0, klass_opnd);
    cmp(cb, REG0, mem_opnd(64, REG1, offsetof(struct rb_callcache, klass)));
    jne_ptr(cb, side_exit);

    // NOTE: there *has to be* a way to optimize the entry invalidated check
    // Could we have Ruby invalidate the JIT code instead of invalidating CME?
    //
    // Check that the method entry is not invalidated
    // cd->cc->cme->flags
    // #define METHOD_ENTRY_INVALIDATED(me) ((me)->flags & IMEMO_FL_USER5)
    x86opnd_t ptr_to_cme_ = mem_opnd(64, REG1, offsetof(struct rb_callcache, cme_));
    mov(cb, REG1, ptr_to_cme_);
    x86opnd_t flags_opnd = mem_opnd(64, REG1, offsetof(rb_callable_method_entry_t, flags));
    test(cb, flags_opnd, imm_opnd(IMEMO_FL_USER5));
    jnz_ptr(cb, side_exit);

    // IDEA: stack frame setup may not be needed for some C functions
    // We could profile the most called C functions and identify which are safe
    // This may help us eliminate stack overflow checks as well

    // TODO: do we need this check?
    //vm_check_frame(type, specval, cref_or_me, iseq);

    // TODO: stack overflow check
    //vm_check_canary(ec, sp);

    // Increment the stack pointer by 3 (in the callee)
    // sp += 3
    lea(cb, REG0, ctx_sp_opnd(ctx));
    add(cb, REG0, imm_opnd(8 * 3));

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

    // Save the MicroJIT registers
    push(cb, REG_CFP);
    push(cb, REG_EC);
    push(cb, REG_SP);

    // Maintain 16-byte RSP alignment
    sub(cb, RSP, imm_opnd(8));

    // Copy SP into RAX because REG_SP will get overwritten
    lea(cb, RAX, ctx_sp_opnd(ctx));

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

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
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

    // Pop the stack frame (ec->cfp++)
    add(
        cb,
        member_opnd(REG_EC, rb_execution_context_t, cfp),
        imm_opnd(sizeof(rb_control_frame_t))
    );

    return true;
}

void
rb_ujit_compile_iseq(const rb_iseq_t *iseq)
{
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    RB_VM_LOCK();
    VALUE *encoded = (VALUE *)iseq->body->iseq_encoded;

    unsigned int insn_idx;
    unsigned int next_ujit_idx = 0;

    for (insn_idx = 0; insn_idx < iseq->body->iseq_size; /* */) {
        int insn = opcode_at_pc(iseq, &encoded[insn_idx]);
        int len = insn_len(insn);

        uint8_t *native_code_ptr = NULL;

        // If ujit hasn't already compiled this instruction
        if (insn_idx >= next_ujit_idx) {
            native_code_ptr = ujit_compile_insn(iseq, insn_idx, &next_ujit_idx);
        }

        if (native_code_ptr) {
            encoded[insn_idx] = (VALUE)native_code_ptr;
        }
        insn_idx += len;
    }
    RB_VM_UNLOCK();
#endif
}

void
rb_ujit_init(void)
{
    if (!ujit_scrape_successful || !PLATFORM_SUPPORTED_P)
    {
        return;
    }

    rb_ujit_enabled = true;

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
    st_insert(gen_fns, (st_data_t)BIN(opt_minus), (st_data_t)&gen_opt_minus);
    st_insert(gen_fns, (st_data_t)BIN(opt_send_without_block), (st_data_t)&gen_opt_send_without_block);
}
