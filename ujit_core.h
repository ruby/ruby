#ifndef UJIT_CORE_H
#define UJIT_CORE_H 1

#include "stddef.h"
#include "ujit_asm.h"

// Register uJIT receives the CFP and EC into
#define REG_CFP RDI
#define REG_EC RSI

// Register uJIT loads the SP into
#define REG_SP RDX

// Scratch registers used by uJIT
#define REG0 RAX
#define REG1 RCX
#define REG0_32 EAX
#define REG1_32 ECX

// Code generation context
typedef struct ctx_struct
{
    // Current PC
    VALUE *pc;

    // Difference between the current stack pointer and actual stack top
    int32_t stack_diff;

    // The iseq that owns the region that is compiling
    const rb_iseq_t *iseq;

    // Index in the iseq of the opcode we are replacing
    size_t start_idx;

    // The start of the generated code
    uint8_t *code_ptr;

    // Whether we know self is a heap object
    bool self_is_object;

} ctx_t;

int ctx_get_opcode(ctx_t *ctx);
VALUE ctx_get_arg(ctx_t* ctx, size_t arg_idx);
x86opnd_t ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes);
x86opnd_t ctx_stack_push(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx);

#endif // #ifndef UJIT_CORE_H
