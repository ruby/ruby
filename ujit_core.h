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

// Code generation context
typedef struct CtxStruct
{
    // Number of values pushed on the temporary stack
    uint32_t stack_size;

    // Whether we know self is a heap object
    bool self_is_object;

} ctx_t;

// Tuple of (iseq, idx) used to idenfity basic blocks
typedef struct BlockId
{
    // Instruction sequence
    const rb_iseq_t *iseq;

    // Instruction index
    const uint32_t idx;

} blockid_t;

/// Branch code shape enumeration
enum uint8_t
{
    SHAPE_NEXT0,  // Target 0 is next
    SHAPE_NEXT1,  // Target 1 is next
    SHAPE_DEFAULT // Neither target is next
};

// Branch code generation function signature
typedef void (*branchgen_fn)(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape);

// Store info about an outgoing branch in a code segment
typedef struct BranchEntry
{
    // Context right after the branch instruction
    ctx_t ctx;

    // Positions where the generated code starts and ends
    uint32_t start_pos;
    uint32_t end_pos;

    // Branch target blocks
    blockid_t targets[2];

    // Jump target addresses
    uint8_t* dst_addrs[2];

    // Branch code generation function
    branchgen_fn gen_fn;

    // Shape of the branch
    uint8_t shape;

} branch_t;

// Context object methods
int ctx_get_opcode(ctx_t *ctx);
uint32_t ctx_next_idx(ctx_t* ctx);
VALUE ctx_get_arg(ctx_t* ctx, size_t arg_idx);
x86opnd_t ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes);
x86opnd_t ctx_stack_push(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx);

void gen_branch(ctx_t* ctx, blockid_t target0, blockid_t target1, branchgen_fn gen_fn);

void ujit_init_core(void);

#endif // #ifndef UJIT_CORE_H
