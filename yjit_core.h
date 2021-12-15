#ifndef YJIT_CORE_H
#define YJIT_CORE_H 1

#include <stddef.h>
#include <stdint.h>
#include "yjit_asm.h"

// Callee-saved regs
#define REG_CFP R13
#define REG_EC R12
#define REG_SP RBX

// Scratch registers used by YJIT
#define REG0 RAX
#define REG0_32 EAX
#define REG0_8 AL
#define REG1 RCX
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
    ETYPE_TRUE,
    ETYPE_FALSE,
    ETYPE_FIXNUM,
    ETYPE_FLONUM,
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
    uint8_t type : 4;

} val_type_t;
STATIC_ASSERT(val_type_size, sizeof(val_type_t) == 1);

// Unknown type, could be anything, all zeroes
#define TYPE_UNKNOWN ( (val_type_t){ 0 } )

// Could be any heap object
#define TYPE_HEAP ( (val_type_t){ .is_heap = 1 } )

// Could be any immediate
#define TYPE_IMM ( (val_type_t){ .is_imm = 1 } )

#define TYPE_NIL ( (val_type_t){ .is_imm = 1, .type = ETYPE_NIL } )
#define TYPE_TRUE ( (val_type_t){ .is_imm = 1, .type = ETYPE_TRUE } )
#define TYPE_FALSE ( (val_type_t){ .is_imm = 1, .type = ETYPE_FALSE } )
#define TYPE_FIXNUM ( (val_type_t){ .is_imm = 1, .type = ETYPE_FIXNUM } )
#define TYPE_FLONUM ( (val_type_t){ .is_imm = 1, .type = ETYPE_FLONUM } )
#define TYPE_STATIC_SYMBOL ( (val_type_t){ .is_imm = 1, .type = ETYPE_SYMBOL } )
#define TYPE_ARRAY ( (val_type_t){ .is_heap = 1, .type = ETYPE_ARRAY } )
#define TYPE_HASH ( (val_type_t){ .is_heap = 1, .type = ETYPE_HASH } )
#define TYPE_STRING ( (val_type_t){ .is_heap = 1, .type = ETYPE_STRING } )

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

// By default, temps are just temps on the stack.
// Name conflict with an mmap flag. This is a struct instance,
// so the compiler will check for wrong usage.
#undef MAP_STACK
#define MAP_STACK ( (temp_mapping_t) { 0 } )

// Temp value is actually self
#define MAP_SELF ( (temp_mapping_t) { .kind = TEMP_SELF } )

// Represents both the type and mapping
typedef struct {
    temp_mapping_t mapping;
    val_type_t type;
} temp_type_mapping_t;
STATIC_ASSERT(temp_type_mapping_size, sizeof(temp_type_mapping_t) == 2);

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

// Tuple of (iseq, idx) used to identify basic blocks
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
    uint8_t *start_addr;
    uint8_t *end_addr;

    // Context right after the branch instruction
    // Unused for now.
    // ctx_t src_ctx;

    // Branch target blocks and their contexts
    blockid_t targets[2];
    ctx_t target_ctxs[2];
    struct yjit_block_version *blocks[2];

    // Jump target addresses
    uint8_t *dst_addrs[2];

    // Branch code generation function
    branchgen_fn gen_fn;

    // Shape of the branch
    branch_shape_t shape : 2;

} branch_t;

// In case this block is invalidated, these two pieces of info
// help to remove all pointers to this block in the system.
typedef struct {
    VALUE receiver_klass;
    VALUE callee_cme;
} cme_dependency_t;

typedef rb_darray(cme_dependency_t) cme_dependency_array_t;

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
    uint8_t *start_addr;
    uint8_t *end_addr;

    // List of incoming branches (from predecessors)
    branch_array_t incoming;

    // List of outgoing branches (to successors)
    // Note: these are owned by this block version
    branch_array_t outgoing;

    // Offsets for GC managed objects in the mainline code block
    int32_array_t gc_object_offsets;

    // CME dependencies of this block, to help to remove all pointers to this
    // block in the system.
    cme_dependency_array_t cme_dependencies;

    // Code address of an exit for `ctx` and `blockid`. Used for block
    // invalidation.
    uint8_t *entry_exit;

    // Index one past the last instruction in the iseq
    uint32_t end_idx;

} block_t;

// Code generation state
typedef struct JITState
{
    // Inline and outlined code blocks we are
    // currently generating code into
    codeblock_t* cb;
    codeblock_t* ocb;

    // Block version being compiled
    block_t *block;

    // Instruction sequence this is associated with
    const rb_iseq_t *iseq;

    // Index of the current instruction being compiled
    uint32_t insn_idx;

    // Opcode for the instruction being compiled
    int opcode;

    // PC of the instruction being compiled
    VALUE *pc;

    // Side exit to the instruction being compiled. See :side-exit:.
    uint8_t *side_exit_for_pc;

    // Execution context when compilation started
    // This allows us to peek at run-time values
    rb_execution_context_t *ec;

    // Whether we need to record the code address at
    // the end of this bytecode instruction for global invalidation
    bool record_boundary_patch_point;

} jitstate_t;

#endif // #ifndef YJIT_CORE_H
