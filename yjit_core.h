#ifndef YJIT_CORE_H
#define YJIT_CORE_H 1

#include "stddef.h"
#include "yjit_asm.h"

// Register YJIT receives the CFP and EC into
#define REG_CFP RDI
#define REG_EC RSI

// Register YJIT loads the SP into
#define REG_SP RDX

// Scratch registers used by YJIT
#define REG0 RAX
#define REG1 RCX
#define REG0_32 EAX
#define REG1_32 ECX

// Maximum number of temp value types we keep track of
#define MAX_TEMP_TYPES 8

// Default versioning context (no type information)
#define DEFAULT_CTX ( (ctx_t){ 0 } )

/**
Code generation context
Contains information we can use to optimize code
*/
typedef struct yjit_context
{
    // Depth of this block in the sidechain (eg: inline-cache chain)
    uint8_t chain_depth;

    // Temporary variable types we keep track of
    // Values are `ruby_value_type`
    // T_NONE==0 is the unknown type
    uint8_t temp_types[MAX_TEMP_TYPES];

    // Number of values currently on the temporary stack
    uint16_t stack_size;

    // Offset of the JIT SP relative to the interpreter SP
    // This represents how far the JIT's SP is from the "real" SP
    int16_t sp_offset;

    // Whether we know self is a heap object
    bool self_is_object : 1;

} ctx_t;

// Tuple of (iseq, idx) used to idenfity basic blocks
typedef struct BlockId
{
    // Instruction sequence
    const rb_iseq_t *iseq;

    // Index in the iseq where the block starts
    uint32_t idx;

} blockid_t;

// Null block id constant
static const blockid_t BLOCKID_NULL = { 0, 0 };

/// Branch code shape enumeration
typedef enum branch_shape
{
    SHAPE_NEXT0,  // Target 0 is next
    SHAPE_NEXT1,  // Target 1 is next
    SHAPE_DEFAULT // Neither target is next
} branch_shape_t;

// Branch code generation function signature
typedef void (*branchgen_fn)(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape);

/**
Store info about an outgoing branch in a code segment
Note: care must be taken to minimize the size of branch_t objects
*/
typedef struct BranchEntry
{
    // Positions where the generated code starts and ends
    uint32_t start_pos;
    uint32_t end_pos;

    // Context right after the branch instruction
    ctx_t src_ctx;

    // Branch target blocks and their contexts
    blockid_t targets[2];
    ctx_t target_ctxs[2];

    // Jump target addresses
    uint8_t* dst_addrs[2];

    // Branch code generation function
    branchgen_fn gen_fn;

    // Shape of the branch
    branch_shape_t shape;

} branch_t;

typedef rb_darray(uint32_t) int32_array_t;

/**
Basic block version
Represents a portion of an iseq compiled with a given context
Note: care must be taken to minimize the size of block_t objects
*/
typedef struct yjit_block_version
{
    // Bytecode sequence (iseq, idx) this is a version of
    blockid_t blockid;

    // Context at the start of the block
    ctx_t ctx;

    // Positions where the generated code starts and ends
    uint32_t start_pos;
    uint32_t end_pos;

    // List of incoming branches indices
    int32_array_t incoming;

    // Offsets for GC managed objects in the mainline code block
    int32_array_t gc_object_offsets;

    // In case this block is invalidated, these two pieces of info
    // help to remove all pointers to this block in the system.
    VALUE receiver_klass;
    VALUE callee_cme;

    // Index one past the last instruction in the iseq
    uint32_t end_idx;
} block_t;

// Context object methods
x86opnd_t ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes);
x86opnd_t ctx_stack_push(ctx_t* ctx, int type);
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx);
int ctx_get_top_type(ctx_t* ctx);
int ctx_diff(const ctx_t* src, const ctx_t* dst);

block_t* find_block_version(blockid_t blockid, const ctx_t* ctx);
block_t* gen_block_version(blockid_t blockid, const ctx_t* ctx, rb_execution_context_t *ec);
uint8_t*  gen_entry_point(const rb_iseq_t *iseq, uint32_t insn_idx, rb_execution_context_t *ec);
void yjit_free_block(block_t *block);
void yjit_branches_update_references(void);

void gen_branch(
    const ctx_t* src_ctx,
    blockid_t target0,
    const ctx_t* ctx0,
    blockid_t target1,
    const ctx_t* ctx1,
    branchgen_fn gen_fn
);

void gen_direct_jump(
    const ctx_t* ctx,
    blockid_t target0
);

void defer_compilation(
    block_t* block,
    uint32_t insn_idx,
    ctx_t* cur_ctx
);

void invalidate_block_version(block_t* block);

void yjit_init_core(void);

#endif // #ifndef YJIT_CORE_H
