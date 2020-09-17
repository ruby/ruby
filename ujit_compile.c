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

// TODO: give ujit_examples.h some more meaningful file name
// eg ujit_hook.h
#include "ujit_examples.h"

// Code generation context
typedef struct ctx_struct
{
    // Current PC
    VALUE* pc;

    // Difference between the current stack pointer and actual stack top
    int32_t stack_diff;

} ctx_t;

// Code generation function
typedef void (*codegen_fn)(codeblock_t* cb, ctx_t* ctx);

// Map from YARV opcodes to code generation functions
static st_table *gen_fns;

// Code block into which we write machine code
static codeblock_t block;
static codeblock_t* cb = NULL;

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

static void ujit_init();

// Ruby instruction entry
static void
ujit_instr_entry(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_pre_call_bytes); ++i)
        cb_write_byte(cb, ujit_pre_call_bytes[i]);
}

// Ruby instruction exit
static void
ujit_instr_exit(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_post_call_bytes); ++i)
        cb_write_byte(cb, ujit_post_call_bytes[i]);
}

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
    ctx->stack_diff -= n;

    // SP points just above the topmost value
    int32_t offset = (ctx->stack_diff - 1) * 8;
    return mem_opnd(64, RSI, offset);
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
    // If not previously done, initialize ujit
    if (!cb)
    {
        ujit_init();
    }

    // NOTE: if we are ever deployed in production, we
    // should probably just log an error and return NULL here,
    // so we can fail more gracefully
    if (cb->write_pos + 1024 >= cb->mem_size)
    {
        rb_bug("out of executable memory");
    }

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
            break;
        }

        // Write the pre call bytes before the first instruction
        if (num_instrs == 0)
        {
            ujit_instr_entry(cb);

            // Load the current SP from the CFP into RSI
            mov(cb, RSI, mem_opnd(64, RDI, 8));
        }

        // Call the code generation function
        codegen_fn gen_fn = (codegen_fn)st_gen_fn;
        gen_fn(cb, &ctx);

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

    // Write the adjusted SP back into the CFP
    if (ctx.stack_diff != 0)
    {
        // The stack pointer points one above the actual stack top
        x86opnd_t stack_pointer = ctx_stack_push(&ctx, 1);
        lea(cb, RSI, stack_pointer);
        mov(cb, mem_opnd(64, RDI, 8), RSI);
    }

    // Directly return the next PC, which is a constant
    mov(cb, RAX, const_ptr_opnd(ctx.pc));

    // Write the post call bytes
    ujit_instr_exit(cb);

    addr2insn_bookkeeping(code_ptr, first_opcode);

    return code_ptr;
}

void gen_nop(codeblock_t* cb, ctx_t* ctx)
{
}

void gen_pop(codeblock_t* cb, ctx_t* ctx)
{
    // Decrement SP
    ctx_stack_pop(ctx, 1);
}

void gen_putnil(codeblock_t* cb, ctx_t* ctx)
{
    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(Qnil));
}

void gen_putobject(codeblock_t* cb, ctx_t* ctx)
{
    // Get the argument
    VALUE object = ctx_get_arg(ctx, 0);
    x86opnd_t ptr_imm = const_ptr_opnd((void*)object);

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, RAX, ptr_imm);
    mov(cb, stack_top, RAX);
}

void gen_putobject_int2fix(codeblock_t* cb, ctx_t* ctx)
{
    int opcode = ctx_get_opcode(ctx);
    int cst_val = (opcode == BIN(putobject_INT2FIX_0_))? 0:1;

    // Write constant at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, imm_opnd(INT2FIX(cst_val)));
}

// TODO: implement putself

void gen_getlocal_wc0(codeblock_t* cb, ctx_t* ctx)
{
    // Load block pointer from CFP
    mov(cb, RDX, mem_opnd(64, RDI, 32));

    // Compute the offset from BP to the local
    int32_t local_idx = (int32_t)ctx_get_arg(ctx, 0);
    const int32_t offs = -8 * local_idx;

    // Load the local from the block
    mov(cb, RCX, mem_opnd(64, RDX, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, 1);
    mov(cb, stack_top, RCX);
}

static void ujit_init()
{
    // 4MB ought to be enough for anybody
    cb = &block;
    cb_init(cb, 4000000);

    // Initialize the codegen function table
    gen_fns = rb_st_init_numtable();

    // Map YARV opcodes to the corresponding codegen functions
    st_insert(gen_fns, (st_data_t)BIN(nop), (st_data_t)&gen_nop);
    st_insert(gen_fns, (st_data_t)BIN(pop), (st_data_t)&gen_pop);
    st_insert(gen_fns, (st_data_t)BIN(putnil), (st_data_t)&gen_putnil);
    st_insert(gen_fns, (st_data_t)BIN(putobject), (st_data_t)&gen_putobject);
    st_insert(gen_fns, (st_data_t)BIN(putobject_INT2FIX_0_), (st_data_t)&gen_putobject_int2fix);
    st_insert(gen_fns, (st_data_t)BIN(putobject_INT2FIX_1_), (st_data_t)&gen_putobject_int2fix);
    st_insert(gen_fns, (st_data_t)BIN(getlocal_WC_0), (st_data_t)&gen_getlocal_wc0);
}
