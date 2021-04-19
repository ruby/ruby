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

// Maximum number of local variable types we keep track of
#define MAX_LOCAL_TYPES 8

// Default versioning context (no type information)
#define DEFAULT_CTX ( (ctx_t){ 0 } )

enum yjit_type_enum
{
    ETYPE_UNKNOWN = 0,
    ETYPE_NIL,
    ETYPE_FIXNUM,
    ETYPE_ARRAY,
    ETYPE_HASH,
    ETYPE_SYMBOL,
    ETYPE_STRING
};

// Represent the type of a value (local/stack/self) in YJIT
typedef struct yjit_type_struct
{
    // Value is definitely a heap object
    uint8_t is_heap : 1;

    // Value is definitely an immediate
    uint8_t is_imm : 1;

    // Specific value type, if known
    uint8_t type : 3;

} val_type_t;
STATIC_ASSERT(val_type_size, sizeof(val_type_t) == 1);

// Unknown type, could be anything, all zeroes
#define TYPE_UNKNOWN ( (val_type_t){ 0 } )

// Could be any heap object
#define TYPE_HEAP ( (val_type_t){ .is_heap = 1 } )

// Could be any immediate
#define TYPE_IMM ( (val_type_t){ .is_imm = 1 } )

#define TYPE_NIL ( (val_type_t){ .is_imm = 1, .type = ETYPE_NIL } )
#define TYPE_FIXNUM ( (val_type_t){ .is_imm = 1, .type = ETYPE_FIXNUM } )
#define TYPE_ARRAY ( (val_type_t){ .is_heap = 1, .type = ETYPE_ARRAY } )
#define TYPE_HASH ( (val_type_t){ .is_heap = 1, .type = ETYPE_HASH } )

enum yjit_temp_loc
{
    TEMP_STACK = 0,
    TEMP_SELF,
    TEMP_LOCAL,     // Local with index
    //TEMP_CONST,   // Small constant (0, 1, 2, Qnil, Qfalse, Qtrue)
};

// Potential mapping of a value on the temporary stack to
// self, a local variable or constant so that we can track its type
typedef struct yjit_temp_mapping
{
    // Where/how is the value stored?
    uint8_t kind: 2;

    // Index of the local variale,
    // or small non-negative constant in [0, 63]
    uint8_t idx : 6;

} temp_mapping_t;
STATIC_ASSERT(temp_mapping_size, sizeof(temp_mapping_t) == 1);

// By default, temps are just temps on the stack
#define MAP_STACK ( (temp_mapping_t) { 0 } )

// Temp value is actually self
#define MAP_SELF ( (temp_mapping_t) { .kind = TEMP_SELF } )

// Operand to a bytecode instruction
typedef struct yjit_insn_opnd
{
    // Indicates if the value is self
    bool is_self;

    // Index on the temporary stack (for stack operands only)
    uint16_t idx;

} insn_opnd_t;

#define OPND_SELF ( (insn_opnd_t){ .is_self = true } )
#define OPND_STACK(stack_idx) ( (insn_opnd_t){ .is_self = false, .idx = stack_idx } )

/**
Code generation context
Contains information we can use to optimize code
*/
typedef struct yjit_context
{
    // Number of values currently on the temporary stack
    uint16_t stack_size;

    // Offset of the JIT SP relative to the interpreter SP
    // This represents how far the JIT's SP is from the "real" SP
    int16_t sp_offset;

    // Depth of this block in the sidechain (eg: inline-cache chain)
    uint8_t chain_depth;

    // Local variable types we keepp track of
    val_type_t local_types[MAX_LOCAL_TYPES];

    // Temporary variable types we keep track of
    val_type_t temp_types[MAX_TEMP_TYPES];

    // Type we track for self
    val_type_t self_type;

    // Mapping of temp stack entries to types we track
    temp_mapping_t temp_mapping[MAX_TEMP_TYPES];

} ctx_t;
STATIC_ASSERT(yjit_ctx_size, sizeof(ctx_t) <= 32);

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
typedef struct yjit_branch_entry
{
    // Block this is attached to
    struct yjit_block_version *block;

    // Positions where the generated code starts and ends
    uint32_t start_pos;
    uint32_t end_pos;

    // Context right after the branch instruction
    ctx_t src_ctx;

    // Branch target blocks and their contexts
    blockid_t targets[2];
    ctx_t target_ctxs[2];
    struct yjit_block_version *blocks[2];

    // Jump target addresses
    uint8_t* dst_addrs[2];

    // Branch code generation function
    branchgen_fn gen_fn;

    // Shape of the branch
    branch_shape_t shape : 2;

} branch_t;

typedef rb_darray(branch_t*) branch_array_t;

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

    // List of incoming branches (from predecessors)
    branch_array_t incoming;

    // List of outgoing branches (to successors)
    // Note: these are owned by this block version
    branch_array_t outgoing;

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
x86opnd_t ctx_stack_push(ctx_t* ctx, val_type_t type);
x86opnd_t ctx_stack_push_self(ctx_t* ctx);
x86opnd_t ctx_stack_push_local(ctx_t* ctx, size_t local_idx);
x86opnd_t ctx_stack_pop(ctx_t* ctx, size_t n);
x86opnd_t ctx_stack_opnd(ctx_t* ctx, int32_t idx);
val_type_t ctx_get_opnd_type(const ctx_t* ctx, insn_opnd_t opnd);
void ctx_set_opnd_type(ctx_t* ctx, insn_opnd_t opnd, val_type_t type);
void ctx_set_local_type(ctx_t* ctx, size_t idx, val_type_t type);
void ctx_clear_local_types(ctx_t* ctx);
int ctx_diff(const ctx_t* src, const ctx_t* dst);

block_t* find_block_version(blockid_t blockid, const ctx_t* ctx);
block_t* gen_block_version(blockid_t blockid, const ctx_t* ctx, rb_execution_context_t *ec);
uint8_t*  gen_entry_point(const rb_iseq_t *iseq, uint32_t insn_idx, rb_execution_context_t *ec);
void yjit_free_block(block_t *block);
rb_yjit_block_array_t yjit_get_version_array(const rb_iseq_t *iseq, unsigned idx);

void gen_branch(
    block_t* block,
    const ctx_t* src_ctx,
    blockid_t target0,
    const ctx_t* ctx0,
    blockid_t target1,
    const ctx_t* ctx1,
    branchgen_fn gen_fn
);

void gen_direct_jump(
    block_t* block,
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
