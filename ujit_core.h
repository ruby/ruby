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

// Maximum number of versions per block
#define MAX_VERSIONS 5

// Tuple of (iseq, idx) used to idenfity basic blocks
typedef struct BlockId
{
    // Instruction sequence
    const rb_iseq_t *iseq;

    // Instruction index
    const unsigned int idx;

} blockid_t;

// Code generation context
typedef struct ctx_struct
{
    // TODO: we may want to remove information that is not
    // strictly necessary for versioning from this struct
    // Some of the information here is only needed during
    // code generation, eg: current pc

    // Instruction sequence this is associated with
    const rb_iseq_t *iseq;

    // Index in the iseq of the opcode we are replacing
    size_t start_idx;

    // The start of the generated code
    uint8_t *code_ptr;

    // Current PC
    VALUE *pc;

    // Number of values pushed on the temporary stack
    int32_t stack_size;

    // Whether we know self is a heap object
    bool self_is_object;

} ctx_t;

// Context object methods
int ctx_get_opcode(ctx_t *ctx);
VALUE ctx_get_arg(ctx_t* ctx, size_t arg_idx);
x86opnd_t ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes);
x86opnd_t ctx_stack_push(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx);

void ujit_init_core(void);

#endif // #ifndef UJIT_CORE_H
