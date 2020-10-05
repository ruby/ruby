#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns_info.inc"
#include "ujit_compile.h"
#include "ujit_asm.h"
#include "ujit_utils.h"

// TODO: give ujit_examples.inc some more meaningful file name
// eg ujit_hook.h
#include "ujit_examples.inc"

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

// Code generation context
typedef struct ctx_struct
{
    // Current PC
    VALUE* pc;

    // Difference between the current stack pointer and actual stack top
    int32_t stack_diff;

} ctx_t;

// MicroJIT code generation function signature
typedef void (*codegen_fn)(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx);

// Map from YARV opcodes to code generation functions
static st_table *gen_fns;

// Code block into which we write machine code
static codeblock_t block;
static codeblock_t* cb = NULL;

// Code block into which we write out-of-line machine code
static codeblock_t outline_block;
static codeblock_t* ocb = NULL;

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

// Get the current instruction opcode from the context object
int ctx_get_opcode(ctx_t* ctx)
{
    return (int)(*ctx->pc);
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
x86opnd_t ctx_sp_opnd(ctx_t* ctx, size_t n)
{
    int32_t offset = (ctx->stack_diff) * 8;
    return mem_opnd(64, RSI, offset);
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
    return mem_opnd(64, RSI, offset);
}

/*
Pop N values off the stack
Return a pointer to the stack top before the pop operation
*/
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_diff - 1) * 8;
    x86opnd_t top = mem_opnd(64, RSI, offset);

    ctx->stack_diff -= n;

    return top;
}

x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_diff - 1 - idx) * 8;
    x86opnd_t opnd = mem_opnd(64, RSI, offset);

    return opnd;
}

// Ruby instruction entry
static void
ujit_gen_entry(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_pre_call_bytes); ++i)
        cb_write_byte(cb, ujit_pre_call_bytes[i]);
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
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx, 1);
        lea(cb, RSI, stack_pointer);
        mov(cb, mem_opnd(64, RDI, 8), RSI);
    }

    // Directly return the next PC, which is a constant
    mov(cb, RAX, const_ptr_opnd(exit_pc));

    // Write PC back into the CFP
    mov(cb, mem_opnd(64, RDI, 0), RAX);

    // Write the post call bytes
    for (size_t i = 0; i < sizeof(ujit_post_call_bytes); ++i)
        cb_write_byte(cb, ujit_post_call_bytes[i]);
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
    int opcode = (int)(*exit_pc);
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

MicroJIT code gets a pointer to the cfp as the first argument in RDI
See rb_ujit_empty_func(rb_control_frame_t *cfp) in iseq.c

Throughout the generated code, we store the current stack pointer in RSI

System V ABI reference:
https://wiki.osdev.org/System_V_ABI#x86-64
*/
uint8_t *
ujit_compile_insn(rb_iseq_t *iseq, unsigned int insn_idx, unsigned int* next_ujit_idx)
{
    if (!cb) {
        return NULL;
    }

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
    int first_opcode = (int)iseq->body->iseq_encoded[insn_idx];

    // Create codegen context
    ctx_t ctx;
    ctx.pc = NULL;
    ctx.stack_diff = 0;

    // For each instruction to compile
    size_t num_instrs;
    for (num_instrs = 0;; ++num_instrs)
    {
        // Set the current PC
        ctx.pc = &iseq->body->iseq_encoded[insn_idx];

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

            // Load the current SP from the CFP into RSI
            mov(cb, RSI, mem_opnd(64, RDI, 8));
        }

        // Call the code generation function
        codegen_fn gen_fn = (codegen_fn)st_gen_fn;
        gen_fn(cb, ocb, &ctx);

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

void gen_dup(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    x86opnd_t dup_val = ctx_stack_pop(ctx, 1);
    x86opnd_t loc0 = ctx_stack_push(ctx, 1);
    x86opnd_t loc1 = ctx_stack_push(ctx, 1);
    mov(cb, RAX, dup_val);
    mov(cb, loc0, RAX);
    mov(cb, loc1, RAX);
}

void gen_nop(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Do nothing
}

void gen_pop(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Decrement SP
    ctx_stack_pop(ctx, 1);
}

void gen_putnil(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(Qnil));
}

void gen_putobject(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Get the argument
    VALUE object = ctx_get_arg(ctx, 0);
    x86opnd_t ptr_imm = const_ptr_opnd((void*)object);

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, RAX, ptr_imm);
    mov(cb, stack_top, RAX);
}

void gen_putobject_int2fix(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    int opcode = ctx_get_opcode(ctx);
    int cst_val = (opcode == BIN(putobject_INT2FIX_0_))? 0:1;

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(INT2FIX(cst_val)));
}

void gen_putself(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load self from CFP
    mov(cb, RAX, mem_opnd(64, RDI, 24));

    // Write it on the stack
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RAX);
}

void gen_getlocal_wc0(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Load environment pointer EP from CFP
    mov(cb, RDX, member_opnd(RDI, rb_control_frame_t, ep));

    // Compute the offset from BP to the local
    int32_t local_idx = (int32_t)ctx_get_arg(ctx, 0);
    const int32_t offs = -8 * local_idx;

    // Load the local from the block
    mov(cb, RCX, mem_opnd(64, RDX, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RCX);
}

void gen_setlocal_wc0(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
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
    mov(cb, RDX, member_opnd(RDI, rb_control_frame_t, ep));

    // flags & VM_ENV_FLAG_WB_REQUIRED
    x86opnd_t flags_opnd = mem_opnd(64, RDX, 8 * VM_ENV_DATA_INDEX_FLAGS);
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED));

    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(ocb, ctx, ctx->pc);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Pop the value to write from the stack
    x86opnd_t stack_top = ctx_stack_pop(ctx, 1);
    mov(cb, RCX, stack_top);

    // Write the value at the environment pointer
    int32_t local_idx = (int32_t)ctx_get_arg(ctx, 0);
    const int32_t offs = -8 * local_idx;
    mov(cb, mem_opnd(64, RDX, offs), RCX);
}

void gen_opt_minus(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
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

    /*
    print_int(cb, arg0);
    print_int(cb, arg1);
    print_int(cb, RAX);
    print_str(cb, "");
    */

    // Push the output on the stack
    x86opnd_t dst = ctx_stack_push(ctx, 1);
    mov(cb, dst, RAX);
}

void gen_opt_send_without_block(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx)
{
    // Create a size-exit to fall back to the interpreter
    uint8_t* side_exit = ujit_side_exit(ocb, ctx, ctx->pc);



    /*
    struct rb_call_data * cd = (struct rb_call_data *)ctx_get_arg(ctx, 0);
    int32_t argc = (int32_t)vm_ci_argc(cd->ci);
    const struct rb_callcache *cc = cd->cc;

    ID mid = vm_ci_mid(cd->ci);
    //fprintf(stderr, "jitting call to \"%s\", argc: %lu\n", rb_id2name(mid), argc);

    // TODO: don't jit calls that aren't simple
    // have this codegen function return false, make codegen stop?
    if (vm_ci_flag(cd->ci) & VM_CALL_ARGS_SIMPLE)
    {
        //fprintf(stderr, "simple call\n");
    }

    mov(cb, RAX, const_ptr_opnd(cd));
    x86opnd_t ptr_to_cc = member_opnd(RAX, struct rb_call_data, cc);
    mov(cb, RAX, ptr_to_cc);
    */





    /*
    x86opnd_t ptr_to_klass = mem_opnd(64, RAX, offsetof(struct rb_callcache, klass));
    x86opnd_t ptr_to_cme_ = mem_opnd(64, RAX, offsetof(struct rb_callcache, cme_));
    mov(cb, RBX, ptr_to_klass);
    mov(cb, RCX, ptr_to_cme_);

    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);
    mov(cb, RDX, recv);
    // Pointer to the klass field of the receiver
    x86opnd_t klass_opnd = mem_opnd(64, RDX, offsetof(struct RBasic, klass));

    print_int(cb, klass_opnd);

    cmp(cb, RBX, klass_opnd);
    jne_ptr(cb, side_exit);

    print_str(cb, "cache klass hit");

    //#define METHOD_ENTRY_INVALIDATED(me)         ((me)->flags & IMEMO_FL_USER5)
    x86opnd_t flags_opnd = mem_opnd(64, RCX, offsetof( rb_callable_method_entry_t, flags));
    test(cb, flags_opnd, imm_opnd(IMEMO_FL_USER5));
    jnz_ptr(cb, side_exit);

    print_str(cb, "method entry not invalidated!!!1");
    */





    jmp_ptr(cb, side_exit);
}

bool
rb_ujit_enabled_p(void)
{
    return !!cb;
}

void
rb_ujit_init(void)
{
    if (!ujit_scrape_successful) {
        return;
    }
    // Initialize the code blocks
    size_t mem_size = 64 * 1024 * 1024;
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
