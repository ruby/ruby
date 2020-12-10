#include "internal.h"
#include "ujit_asm.h"
#include "ujit_iface.h"
#include "ujit_core.h"




// Table of block versions indexed by (iseq, index) tuples
st_table * version_tbl;

/*
struct st_hash_type {
    int (*compare)(st_data_t, st_data_t); // st_compare_func*
    st_index_t (*hash)(st_data_t);        // st_hash_func*
};

static const struct st_hash_type st_hashtype_num = {
    st_numcmp,
    st_numhash,
};

strcasehash(st_data_t arg)
{
    register const char *string = (const char *)arg;
    ...
}

*/





// Get the current instruction opcode from the context object
int
ctx_get_opcode(ctx_t *ctx)
{
    return opcode_at_pc(ctx->iseq, ctx->pc);
}

// Get an instruction argument from the context object
VALUE
ctx_get_arg(ctx_t* ctx, size_t arg_idx)
{
    assert (arg_idx + 1 < insn_len(ctx_get_opcode(ctx)));
    return *(ctx->pc + arg_idx + 1);
}

/*
Get an operand for the adjusted stack pointer address
*/
x86opnd_t
ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes)
{
    int32_t offset = (ctx->stack_size) * 8 + offset_bytes;
    return mem_opnd(64, REG_SP, offset);
}

/*
Make space on the stack for N values
Return a pointer to the new stack top
*/
x86opnd_t
ctx_stack_push(ctx_t* ctx, size_t n)
{
    ctx->stack_size += n;

    // SP points just above the topmost value
    int32_t offset = (ctx->stack_size - 1) * 8;
    return mem_opnd(64, REG_SP, offset);
}

/*
Pop N values off the stack
Return a pointer to the stack top before the pop operation
*/
x86opnd_t
ctx_stack_pop(ctx_t* ctx, size_t n)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_size - 1) * 8;
    x86opnd_t top = mem_opnd(64, REG_SP, offset);

    ctx->stack_size -= n;

    return top;
}

x86opnd_t
ctx_stack_opnd(ctx_t* ctx, int32_t idx)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_size - 1 - idx) * 8;
    x86opnd_t opnd = mem_opnd(64, REG_SP, offset);

    return opnd;
}
