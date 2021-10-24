// This file is a fragment of the yjit.o compilation unit. See yjit.c.
#include "internal.h"
#include "vm_sync.h"
#include "builtin.h"

#include "yjit.h"
#include "yjit_asm.h"
#include "yjit_iface.h"
#include "yjit_core.h"
#include "yjit_codegen.h"

/*
Get an operand for the adjusted stack pointer address
*/
static x86opnd_t
ctx_sp_opnd(ctx_t *ctx, int32_t offset_bytes)
{
    int32_t offset = (ctx->sp_offset * sizeof(VALUE)) + offset_bytes;
    return mem_opnd(64, REG_SP, offset);
}

/*
Push one new value on the temp stack with an explicit mapping
Return a pointer to the new stack top
*/
static x86opnd_t
ctx_stack_push_mapping(ctx_t *ctx, temp_type_mapping_t mapping)
{
    // Keep track of the type and mapping of the value
    if (ctx->stack_size < MAX_TEMP_TYPES) {
        ctx->temp_mapping[ctx->stack_size] = mapping.mapping;
        ctx->temp_types[ctx->stack_size] = mapping.type;

        RUBY_ASSERT(mapping.mapping.kind != TEMP_LOCAL || mapping.mapping.idx < MAX_LOCAL_TYPES);
        RUBY_ASSERT(mapping.mapping.kind != TEMP_STACK || mapping.mapping.idx == 0);
        RUBY_ASSERT(mapping.mapping.kind != TEMP_SELF || mapping.mapping.idx == 0);
    }

    ctx->stack_size += 1;
    ctx->sp_offset += 1;

    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1) * sizeof(VALUE);
    return mem_opnd(64, REG_SP, offset);
}


/*
Push one new value on the temp stack
Return a pointer to the new stack top
*/
static x86opnd_t
ctx_stack_push(ctx_t *ctx, val_type_t type)
{
    temp_type_mapping_t mapping = { MAP_STACK, type };
    return ctx_stack_push_mapping(ctx, mapping);
}

/*
Push the self value on the stack
*/
static x86opnd_t
ctx_stack_push_self(ctx_t *ctx)
{
    temp_type_mapping_t mapping = { MAP_SELF, TYPE_UNKNOWN };
    return ctx_stack_push_mapping(ctx, mapping);
}

/*
Push a local variable on the stack
*/
static x86opnd_t
ctx_stack_push_local(ctx_t *ctx, size_t local_idx)
{
    if (local_idx >= MAX_LOCAL_TYPES) {
        return ctx_stack_push(ctx, TYPE_UNKNOWN);
    }

    temp_type_mapping_t mapping = {
        (temp_mapping_t){ .kind = TEMP_LOCAL, .idx = local_idx },
        TYPE_UNKNOWN
    };
    return ctx_stack_push_mapping(ctx, mapping);
}

/*
Pop N values off the stack
Return a pointer to the stack top before the pop operation
*/
static x86opnd_t
ctx_stack_pop(ctx_t *ctx, size_t n)
{
    RUBY_ASSERT(n <= ctx->stack_size);

    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1) * sizeof(VALUE);
    x86opnd_t top = mem_opnd(64, REG_SP, offset);

    // Clear the types of the popped values
    for (size_t i = 0; i < n; ++i)
    {
        size_t idx = ctx->stack_size - i - 1;
        if (idx < MAX_TEMP_TYPES) {
            ctx->temp_types[idx] = TYPE_UNKNOWN;
            ctx->temp_mapping[idx] = MAP_STACK;
        }
    }

    ctx->stack_size -= n;
    ctx->sp_offset -= n;

    return top;
}

/**
Get an operand pointing to a slot on the temp stack
*/
static x86opnd_t
ctx_stack_opnd(ctx_t *ctx, int32_t idx)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1 - idx) * sizeof(VALUE);
    x86opnd_t opnd = mem_opnd(64, REG_SP, offset);

    return opnd;
}

/**
Get the type of an instruction operand
*/
static val_type_t
ctx_get_opnd_type(const ctx_t *ctx, insn_opnd_t opnd)
{
    if (opnd.is_self)
        return ctx->self_type;

    RUBY_ASSERT(opnd.idx < ctx->stack_size);
    int stack_idx = ctx->stack_size - 1 - opnd.idx;

    // If outside of tracked range, do nothing
    if (stack_idx >= MAX_TEMP_TYPES)
        return TYPE_UNKNOWN;

    temp_mapping_t mapping = ctx->temp_mapping[stack_idx];

    switch (mapping.kind) {
      case TEMP_SELF:
        return ctx->self_type;

      case TEMP_STACK:
        return ctx->temp_types[ctx->stack_size - 1 - opnd.idx];

      case TEMP_LOCAL:
        RUBY_ASSERT(mapping.idx < MAX_LOCAL_TYPES);
        return ctx->local_types[mapping.idx];
    }

    rb_bug("unreachable");
}

static int type_diff(val_type_t src, val_type_t dst);

#define UPGRADE_TYPE(dest, src) do { \
    RUBY_ASSERT(type_diff((src), (dest)) != INT_MAX); \
    (dest) = (src); \
} while (false)


/**
Upgrade (or "learn") the type of an instruction operand
This value must be compatible and at least as specific as the previously known type.
If this value originated from self, or an lvar, the learned type will be
propagated back to its source.
*/
static void
ctx_upgrade_opnd_type(ctx_t *ctx, insn_opnd_t opnd, val_type_t type)
{
    if (opnd.is_self) {
        UPGRADE_TYPE(ctx->self_type, type);
        return;
    }

    RUBY_ASSERT(opnd.idx < ctx->stack_size);
    int stack_idx = ctx->stack_size - 1 - opnd.idx;

    // If outside of tracked range, do nothing
    if (stack_idx >= MAX_TEMP_TYPES)
        return;

    temp_mapping_t mapping = ctx->temp_mapping[stack_idx];

    switch (mapping.kind) {
      case TEMP_SELF:
        UPGRADE_TYPE(ctx->self_type, type);
        break;

      case TEMP_STACK:
        UPGRADE_TYPE(ctx->temp_types[stack_idx], type);
        break;

      case TEMP_LOCAL:
        RUBY_ASSERT(mapping.idx < MAX_LOCAL_TYPES);
        UPGRADE_TYPE(ctx->local_types[mapping.idx], type);
        break;
    }
}

/*
Get both the type and mapping (where the value originates) of an operand.
This is can be used with ctx_stack_push_mapping or ctx_set_opnd_mapping to copy
a stack value's type while maintaining the mapping.
*/
static temp_type_mapping_t
ctx_get_opnd_mapping(const ctx_t *ctx, insn_opnd_t opnd)
{
    temp_type_mapping_t type_mapping;
    type_mapping.type = ctx_get_opnd_type(ctx, opnd);

    if (opnd.is_self) {
        type_mapping.mapping = MAP_SELF;
        return type_mapping;
    }

    RUBY_ASSERT(opnd.idx < ctx->stack_size);
    int stack_idx = ctx->stack_size - 1 - opnd.idx;

    if (stack_idx < MAX_TEMP_TYPES) {
        type_mapping.mapping = ctx->temp_mapping[stack_idx];
    }
    else {
        // We can't know the source of this stack operand, so we assume it is
        // a stack-only temporary. type will be UNKNOWN
        RUBY_ASSERT(type_mapping.type.type == ETYPE_UNKNOWN);
        type_mapping.mapping = MAP_STACK;
    }

    return type_mapping;
}

/*
Overwrite both the type and mapping of a stack operand.
*/
static void
ctx_set_opnd_mapping(ctx_t *ctx, insn_opnd_t opnd, temp_type_mapping_t type_mapping)
{
    // self is always MAP_SELF
    RUBY_ASSERT(!opnd.is_self);

    RUBY_ASSERT(opnd.idx < ctx->stack_size);
    int stack_idx = ctx->stack_size - 1 - opnd.idx;

    // If outside of tracked range, do nothing
    if (stack_idx >= MAX_TEMP_TYPES)
        return;

    ctx->temp_mapping[stack_idx] = type_mapping.mapping;

    // Only used when mapping == MAP_STACK
    ctx->temp_types[stack_idx] = type_mapping.type;
}

/**
Set the type of a local variable
*/
static void
ctx_set_local_type(ctx_t *ctx, size_t idx, val_type_t type)
{
    if (idx >= MAX_LOCAL_TYPES)
        return;

    // If any values on the stack map to this local we must detach them
    for (int i = 0; i < MAX_TEMP_TYPES; i++) {
        temp_mapping_t *mapping = &ctx->temp_mapping[i];
        if (mapping->kind == TEMP_LOCAL && mapping->idx == idx) {
            ctx->temp_types[i] = ctx->local_types[mapping->idx];
            *mapping = MAP_STACK;
        }
    }

    ctx->local_types[idx] = type;
}

// Erase local variable type information
// eg: because of a call we can't track
static void
ctx_clear_local_types(ctx_t *ctx)
{
    // When clearing local types we must detach any stack mappings to those
    // locals. Even if local values may have changed, stack values will not.
    for (int i = 0; i < MAX_TEMP_TYPES; i++) {
        temp_mapping_t *mapping = &ctx->temp_mapping[i];
        if (mapping->kind == TEMP_LOCAL) {
            RUBY_ASSERT(mapping->idx < MAX_LOCAL_TYPES);
            ctx->temp_types[i] = ctx->local_types[mapping->idx];
            *mapping = MAP_STACK;
        }
        RUBY_ASSERT(mapping->kind == TEMP_STACK || mapping->kind == TEMP_SELF);
    }
    memset(&ctx->local_types, 0, sizeof(ctx->local_types));
}


/* This returns an appropriate val_type_t based on a known value */
static val_type_t
yjit_type_of_value(VALUE val)
{
    if (SPECIAL_CONST_P(val)) {
        if (FIXNUM_P(val)) {
            return TYPE_FIXNUM;
        }
        else if (NIL_P(val)) {
            return TYPE_NIL;
        }
        else if (val == Qtrue) {
            return TYPE_TRUE;
        }
        else if (val == Qfalse) {
            return TYPE_FALSE;
        }
        else if (STATIC_SYM_P(val)) {
            return TYPE_STATIC_SYMBOL;
        }
        else if (FLONUM_P(val)) {
            return TYPE_FLONUM;
        }
        else {
            RUBY_ASSERT(false);
            UNREACHABLE_RETURN(TYPE_IMM);
        }
    }
    else {
        switch (BUILTIN_TYPE(val)) {
          case T_ARRAY:
            return TYPE_ARRAY;
          case T_HASH:
            return TYPE_HASH;
          case T_STRING:
            return TYPE_STRING;
          default:
            // generic heap object
            return TYPE_HEAP;
        }
    }
}

/* The name of a type, for debugging */
RBIMPL_ATTR_MAYBE_UNUSED()
static const char *
yjit_type_name(val_type_t type)
{
    RUBY_ASSERT(!(type.is_imm && type.is_heap));

    switch (type.type) {
      case ETYPE_UNKNOWN:
        if (type.is_imm) {
            return "unknown immediate";
        }
        else if (type.is_heap) {
            return "unknown heap";
        }
        else {
            return "unknown";
        }
      case ETYPE_NIL:
        return "nil";
      case ETYPE_TRUE:
        return "true";
      case ETYPE_FALSE:
        return "false";
      case ETYPE_FIXNUM:
        return "fixnum";
      case ETYPE_FLONUM:
        return "flonum";
      case ETYPE_ARRAY:
        return "array";
      case ETYPE_HASH:
        return "hash";
      case ETYPE_SYMBOL:
        return "symbol";
      case ETYPE_STRING:
        return "string";
    }

    UNREACHABLE_RETURN("");
}

/*
Compute a difference between two value types
Returns 0 if the two are the same
Returns > 0 if different but compatible
Returns INT_MAX if incompatible
*/
static int
type_diff(val_type_t src, val_type_t dst)
{
    RUBY_ASSERT(!src.is_heap || !src.is_imm);
    RUBY_ASSERT(!dst.is_heap || !dst.is_imm);

    // If dst assumes heap but src doesn't
    if (dst.is_heap && !src.is_heap)
        return INT_MAX;

    // If dst assumes imm but src doesn't
    if (dst.is_imm && !src.is_imm)
        return INT_MAX;

    // If dst assumes known type different from src
    if (dst.type != ETYPE_UNKNOWN && dst.type != src.type)
        return INT_MAX;

    if (dst.is_heap != src.is_heap)
        return 1;

    if (dst.is_imm != src.is_imm)
        return 1;

    if (dst.type != src.type)
        return 1;

    return 0;
}

/**
Compute a difference score for two context objects
Returns 0 if the two contexts are the same
Returns > 0 if different but compatible
Returns INT_MAX if incompatible
*/
static int
ctx_diff(const ctx_t *src, const ctx_t *dst)
{
    // Can only lookup the first version in the chain
    if (dst->chain_depth != 0)
        return INT_MAX;

    // Blocks with depth > 0 always produce new versions
    // Sidechains cannot overlap
    if (src->chain_depth != 0)
        return INT_MAX;

    if (dst->stack_size != src->stack_size)
        return INT_MAX;

    if (dst->sp_offset != src->sp_offset)
        return INT_MAX;

    // Difference sum
    int diff = 0;

    // Check the type of self
    int self_diff = type_diff(src->self_type, dst->self_type);

    if (self_diff == INT_MAX)
        return INT_MAX;

    diff += self_diff;

    // For each local type we track
    for (size_t i = 0; i < MAX_LOCAL_TYPES; ++i)
    {
        val_type_t t_src = src->local_types[i];
        val_type_t t_dst = dst->local_types[i];
        int temp_diff = type_diff(t_src, t_dst);

        if (temp_diff == INT_MAX)
            return INT_MAX;

        diff += temp_diff;
    }

    // For each value on the temp stack
    for (size_t i = 0; i < src->stack_size; ++i)
    {
        temp_type_mapping_t m_src = ctx_get_opnd_mapping(src, OPND_STACK(i));
        temp_type_mapping_t m_dst = ctx_get_opnd_mapping(dst, OPND_STACK(i));

        if (m_dst.mapping.kind != m_src.mapping.kind) {
            if (m_dst.mapping.kind == TEMP_STACK) {
                // We can safely drop information about the source of the temp
                // stack operand.
                diff += 1;
            }
            else {
                return INT_MAX;
            }
        }
        else if (m_dst.mapping.idx != m_src.mapping.idx) {
            return INT_MAX;
        }

        int temp_diff = type_diff(m_src.type, m_dst.type);

        if (temp_diff == INT_MAX)
            return INT_MAX;

        diff += temp_diff;
    }

    return diff;
}

// Get all blocks for a particular place in an iseq.
static rb_yjit_block_array_t
yjit_get_version_array(const rb_iseq_t *iseq, unsigned idx)
{
    struct rb_iseq_constant_body *body = iseq->body;

    if (rb_darray_size(body->yjit_blocks) == 0) {
        return NULL;
    }

    RUBY_ASSERT((unsigned)rb_darray_size(body->yjit_blocks) == body->iseq_size);
    return rb_darray_get(body->yjit_blocks, idx);
}

// Count the number of block versions matching a given blockid
static size_t get_num_versions(blockid_t blockid)
{
    return rb_darray_size(yjit_get_version_array(blockid.iseq, blockid.idx));
}

// Keep track of a block version. Block should be fully constructed.
static void
add_block_version(blockid_t blockid, block_t *block)
{
    const rb_iseq_t *iseq = block->blockid.iseq;
    struct rb_iseq_constant_body *body = iseq->body;

    // Function entry blocks must have stack size 0
    RUBY_ASSERT(!(block->blockid.idx == 0 && block->ctx.stack_size > 0));

    // Ensure yjit_blocks is initialized for this iseq
    if (rb_darray_size(body->yjit_blocks) == 0) {
        // Initialize yjit_blocks to be as wide as body->iseq_encoded
        int32_t casted = (int32_t)body->iseq_size;
        if ((unsigned)casted != body->iseq_size) {
            rb_bug("iseq too large");
        }
        if (!rb_darray_make(&body->yjit_blocks, casted)) {
            rb_bug("allocation failed");
        }

#if YJIT_STATS
        // First block compiled for this iseq
        yjit_runtime_counters.compiled_iseq_count++;
#endif
    }

    RUBY_ASSERT((int32_t)blockid.idx < rb_darray_size(body->yjit_blocks));
    rb_yjit_block_array_t *block_array_ref = rb_darray_ref(body->yjit_blocks, blockid.idx);

    // Add the new block
    if (!rb_darray_append(block_array_ref, block)) {
        rb_bug("allocation failed");
    }

    {
        // By writing the new block to the iseq, the iseq now
        // contains new references to Ruby objects. Run write barriers.
        cme_dependency_t *cme_dep;
        rb_darray_foreach(block->cme_dependencies, cme_dependency_idx, cme_dep) {
            RB_OBJ_WRITTEN(iseq, Qundef, cme_dep->receiver_klass);
            RB_OBJ_WRITTEN(iseq, Qundef, cme_dep->callee_cme);
        }

        // Run write barriers for all objects in generated code.
        uint32_t *offset_element;
        rb_darray_foreach(block->gc_object_offsets, offset_idx, offset_element) {
            uint32_t offset_to_value = *offset_element;
            uint8_t *value_address = cb_get_ptr(cb, offset_to_value);

            VALUE object;
            memcpy(&object, value_address, SIZEOF_VALUE);
            RB_OBJ_WRITTEN(iseq, Qundef, object);
        }
    }

#if YJIT_STATS
    yjit_runtime_counters.compiled_block_count++;
#endif
}

// Create a new outgoing branch entry for a block
static branch_t*
make_branch_entry(block_t *block, const ctx_t *src_ctx, branchgen_fn gen_fn)
{
    RUBY_ASSERT(block != NULL);

    // Allocate and zero-initialize
    branch_t *branch = calloc(1, sizeof(branch_t));

    branch->block = block;
    branch->src_ctx = *src_ctx;
    branch->gen_fn = gen_fn;
    branch->shape = SHAPE_DEFAULT;

    // Add to the list of outgoing branches for the block
    rb_darray_append(&block->outgoing, branch);

    return branch;
}

// Retrieve a basic block version for an (iseq, idx) tuple
static block_t *
find_block_version(blockid_t blockid, const ctx_t *ctx)
{
    rb_yjit_block_array_t versions = yjit_get_version_array(blockid.iseq, blockid.idx);

    // Best match found
    block_t *best_version = NULL;
    int best_diff = INT_MAX;

    // For each version matching the blockid
    rb_darray_for(versions, idx) {
        block_t *version = rb_darray_get(versions, idx);
        int diff = ctx_diff(ctx, &version->ctx);

        // Note that we always prefer the first matching
        // version because of inline-cache chains
        if (diff < best_diff) {
            best_version = version;
            best_diff = diff;
        }
    }

    // If greedy versioning is enabled
    if (rb_yjit_opts.greedy_versioning)
    {
        // If we're below the version limit, don't settle for an imperfect match
        if ((uint32_t)rb_darray_size(versions) + 1 < rb_yjit_opts.max_versions && best_diff > 0) {
            return NULL;
        }
    }

    return best_version;
}

// Produce a generic context when the block version limit is hit for a blockid
// Note that this will mutate the ctx argument
static void
limit_block_versions(blockid_t blockid, ctx_t *ctx)
{
    // Guard chains implement limits separately, do nothing
    if (ctx->chain_depth > 0)
        return;

    // If this block version we're about to add will hit the version limit
    if (get_num_versions(blockid) + 1 >= rb_yjit_opts.max_versions)
    {
        // Produce a generic context that stores no type information,
        // but still respects the stack_size and sp_offset constraints
        // This new context will then match all future requests.
        ctx_t generic_ctx = DEFAULT_CTX;
        generic_ctx.stack_size = ctx->stack_size;
        generic_ctx.sp_offset = ctx->sp_offset;

        // Mutate the incoming context
        *ctx = generic_ctx;
    }
}

// Compile a new block version immediately
static block_t *
gen_block_version(blockid_t blockid, const ctx_t *start_ctx, rb_execution_context_t *ec)
{
    // Allocate a new block version object
    block_t *block = calloc(1, sizeof(block_t));
    block->blockid = blockid;
    memcpy(&block->ctx, start_ctx, sizeof(ctx_t));

    // Store a pointer to the first block (returned by this function)
    block_t *first_block = block;

    // Limit the number of specialized versions for this block
    limit_block_versions(block->blockid, &block->ctx);

    // Generate code for the first block
    yjit_gen_block(block, ec);

    // Keep track of the new block version
    add_block_version(block->blockid, block);

    // For each successor block to compile
    for (;;) {
        // If the previous block compiled doesn't have outgoing branches, stop
        if (rb_darray_size(block->outgoing) == 0) {
            break;
        }

        // Get the last outgoing branch from the previous block
        branch_t *last_branch = rb_darray_back(block->outgoing);

        // If there is no next block to compile, stop
        if (last_branch->dst_addrs[0] || last_branch->dst_addrs[1]) {
            break;
        }

        if (last_branch->targets[0].iseq == NULL) {
            rb_bug("invalid target for last branch");
        }

        // Allocate a new block version object
        // Use the context from the branch
        block = calloc(1, sizeof(block_t));
        block->blockid = last_branch->targets[0];
        block->ctx = last_branch->target_ctxs[0];
        //memcpy(&block->ctx, ctx, sizeof(ctx_t));

        // Limit the number of specialized versions for this block
        limit_block_versions(block->blockid, &block->ctx);

        // Generate code for the current block
        yjit_gen_block(block, ec);

        // Keep track of the new block version
        add_block_version(block->blockid, block);

        // Patch the last branch address
        last_branch->dst_addrs[0] = cb_get_ptr(cb, block->start_pos);
        rb_darray_append(&block->incoming, last_branch);
        last_branch->blocks[0] = block;

        RUBY_ASSERT(block->start_pos == last_branch->end_pos);
    }

    return first_block;
}

// Generate a block version that is an entry point inserted into an iseq
static uint8_t *
gen_entry_point(const rb_iseq_t *iseq, uint32_t insn_idx, rb_execution_context_t *ec)
{
    // If we aren't at PC 0, don't generate code
    // See yjit_pc_guard
    if (iseq->body->iseq_encoded != ec->cfp->pc) {
        return NULL;
    }

    // The entry context makes no assumptions about types
    blockid_t blockid = { iseq, insn_idx };

    // Write the interpreter entry prologue
    uint8_t *code_ptr = yjit_entry_prologue(cb, iseq);

    // Try to generate code for the entry block
    block_t *block = gen_block_version(blockid, &DEFAULT_CTX, ec);

    // If we couldn't generate any code
    if (block->end_idx == insn_idx)
    {
        return NULL;
    }

    return code_ptr;
}

// Called by the generated code when a branch stub is executed
// Triggers compilation of branches and code patching
static uint8_t *
branch_stub_hit(branch_t *branch, const uint32_t target_idx, rb_execution_context_t *ec)
{
    uint8_t *dst_addr;

    // Stop other ractors since we are going to patch machine code.
    // This is how the GC does it.
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    RUBY_ASSERT(branch != NULL);
    RUBY_ASSERT(target_idx < 2);
    blockid_t target = branch->targets[target_idx];
    const ctx_t *target_ctx = &branch->target_ctxs[target_idx];

    // If this branch has already been patched, return the dst address
    // Note: ractors can cause the same stub to be hit multiple times
    if (branch->blocks[target_idx]) {
        dst_addr = branch->dst_addrs[target_idx];
    }
    else
    {
        //fprintf(stderr, "\nstub hit, branch: %p, target idx: %d\n", branch, target_idx);
        //fprintf(stderr, "blockid.iseq=%p, blockid.idx=%d\n", target.iseq, target.idx);
        //fprintf(stderr, "chain_depth=%d\n", target_ctx->chain_depth);

        // :stub-sp-flush:
        // Generated code do stack operations without modifying cfp->sp, while the
        // cfp->sp tells the GC what values on the stack to root. Generated code
        // generally takes care of updating cfp->sp when it calls runtime routines that
        // could trigger GC, but for the case of branch stubs, it's inconvenient. So
        // we do it here.
        VALUE *const original_interp_sp = ec->cfp->sp;
        ec->cfp->sp += target_ctx->sp_offset;

        // Update the PC in the current CFP, because it
        // may be out of sync in JITted code
        ec->cfp->pc = yjit_iseq_pc_at_idx(target.iseq, target.idx);

        // Try to find an existing compiled version of this block
        block_t *p_block = find_block_version(target, target_ctx);

        // If this block hasn't yet been compiled
        if (!p_block) {
            // If the new block can be generated right after the branch (at cb->write_pos)
            if (cb->write_pos == branch->end_pos && branch->start_pos >= yjit_codepage_frozen_bytes) {
                // This branch should be terminating its block
                RUBY_ASSERT(branch->end_pos == branch->block->end_pos);

                // Change the branch shape to indicate the target block will be placed next
                branch->shape = (uint8_t)target_idx;

                // Rewrite the branch with the new, potentially more compact shape
                cb_set_pos(cb, branch->start_pos);
                branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
                RUBY_ASSERT(cb->write_pos <= branch->end_pos && "can't enlarge branches");
                branch->end_pos = cb->write_pos;
                branch->block->end_pos = cb->write_pos;
            }

            // Compile the new block version
            p_block = gen_block_version(target, target_ctx, ec);
            RUBY_ASSERT(p_block);
            RUBY_ASSERT(!(branch->shape == (uint8_t)target_idx && p_block->start_pos != branch->end_pos));
        }

        // Add this branch to the list of incoming branches for the target
        rb_darray_append(&p_block->incoming, branch);

        // Update the branch target address
        dst_addr = cb_get_ptr(cb, p_block->start_pos);
        branch->dst_addrs[target_idx] = dst_addr;

        // Rewrite the branch with the new jump target address
        if (branch->start_pos >= yjit_codepage_frozen_bytes) {
            RUBY_ASSERT(branch->dst_addrs[0] != NULL);
            uint32_t cur_pos = cb->write_pos;
            cb_set_pos(cb, branch->start_pos);
            branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
            RUBY_ASSERT(cb->write_pos == branch->end_pos && "branch can't change size");
            cb_set_pos(cb, cur_pos);
        }

        // Mark this branch target as patched (no longer a stub)
        branch->blocks[target_idx] = p_block;

        // Restore interpreter sp, since the code hitting the stub expects the original.
        ec->cfp->sp = original_interp_sp;
    }

    RB_VM_LOCK_LEAVE();

    // Return a pointer to the compiled block version
    return dst_addr;
}

// Get a version or stub corresponding to a branch target
static uint8_t *
get_branch_target(
    blockid_t target,
    const ctx_t *ctx,
    branch_t *branch,
    uint32_t target_idx
)
{
    //fprintf(stderr, "get_branch_target, block (%p, %d)\n", target.iseq, target.idx);

    block_t *p_block = find_block_version(target, ctx);

    // If the block already exists
    if (p_block)
    {
        // Add an incoming branch for this version
        rb_darray_append(&p_block->incoming, branch);
        branch->blocks[target_idx] = p_block;

        // Return a pointer to the compiled code
        return cb_get_ptr(cb, p_block->start_pos);
    }

    // Generate an outlined stub that will call branch_stub_hit()
    uint8_t *stub_addr = cb_get_ptr(ocb, ocb->write_pos);

    // Call branch_stub_hit(branch_idx, target_idx, ec)
    mov(ocb, C_ARG_REGS[2], REG_EC);
    mov(ocb, C_ARG_REGS[1],  imm_opnd(target_idx));
    mov(ocb, C_ARG_REGS[0], const_ptr_opnd(branch));
    call_ptr(ocb, REG0, (void *)&branch_stub_hit);

    // Jump to the address returned by the
    // branch_stub_hit call
    jmp_rm(ocb, RAX);

    return stub_addr;
}

static void
gen_branch(
    jitstate_t *jit,
    const ctx_t *src_ctx,
    blockid_t target0,
    const ctx_t *ctx0,
    blockid_t target1,
    const ctx_t *ctx1,
    branchgen_fn gen_fn
)
{
    RUBY_ASSERT(target0.iseq != NULL);

    branch_t *branch = make_branch_entry(jit->block, src_ctx, gen_fn);
    branch->targets[0] = target0;
    branch->targets[1] = target1;
    branch->target_ctxs[0] = *ctx0;
    branch->target_ctxs[1] = ctx1? *ctx1:DEFAULT_CTX;

    // Get the branch targets or stubs
    branch->dst_addrs[0] = get_branch_target(target0, ctx0, branch, 0);
    branch->dst_addrs[1] = ctx1? get_branch_target(target1, ctx1, branch, 1):NULL;

    // Call the branch generation function
    branch->start_pos = cb->write_pos;
    gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], SHAPE_DEFAULT);
    branch->end_pos = cb->write_pos;
}

static void
gen_jump_branch(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
        break;

      case SHAPE_NEXT1:
        RUBY_ASSERT(false);
        break;

      case SHAPE_DEFAULT:
        jmp_ptr(cb, target0);
        break;
    }
}

static void
gen_direct_jump(
    jitstate_t *jit,
    const ctx_t *ctx,
    blockid_t target0
)
{
    RUBY_ASSERT(target0.iseq != NULL);

    branch_t *branch = make_branch_entry(jit->block, ctx, gen_jump_branch);
    branch->targets[0] = target0;
    branch->target_ctxs[0] = *ctx;

    block_t *p_block = find_block_version(target0, ctx);

    // If the version already exists
    if (p_block) {
        rb_darray_append(&p_block->incoming, branch);

        branch->dst_addrs[0] = cb_get_ptr(cb, p_block->start_pos);
        branch->blocks[0] = p_block;
        branch->shape = SHAPE_DEFAULT;

        // Call the branch generation function
        branch->start_pos = cb->write_pos;
        gen_jump_branch(cb, branch->dst_addrs[0], NULL, SHAPE_DEFAULT);
        branch->end_pos = cb->write_pos;
    }
    else {
        // This NULL target address signals gen_block_version() to compile the
        // target block right after this one (fallthrough).
        branch->dst_addrs[0] = NULL;
        branch->shape = SHAPE_NEXT0;
        branch->start_pos = cb->write_pos;
        branch->end_pos = cb->write_pos;
    }
}

// Create a stub to force the code up to this point to be executed
static void
defer_compilation(
    jitstate_t *jit,
    ctx_t *cur_ctx
)
{
    //fprintf(stderr, "defer compilation at (%p, %d) depth=%d\n", block->blockid.iseq, insn_idx, cur_ctx->chain_depth);

    if (cur_ctx->chain_depth != 0) {
        rb_bug("double defer");
    }

    ctx_t next_ctx = *cur_ctx;

    if (next_ctx.chain_depth >= UINT8_MAX) {
        rb_bug("max block version chain depth reached");
    }

    next_ctx.chain_depth += 1;

    branch_t *branch = make_branch_entry(jit->block, cur_ctx, gen_jump_branch);

    // Get the branch targets or stubs
    branch->target_ctxs[0] = next_ctx;
    branch->targets[0] = (blockid_t){ jit->block->blockid.iseq, jit->insn_idx };
    branch->dst_addrs[0] = get_branch_target(branch->targets[0], &next_ctx, branch, 0);

    // Call the branch generation function
    codeblock_t *cb = jit->cb;
    branch->start_pos = cb->write_pos;
    gen_jump_branch(cb, branch->dst_addrs[0], NULL, SHAPE_DEFAULT);
    branch->end_pos = cb->write_pos;
}

// Remove all references to a block then free it.
static void
yjit_free_block(block_t *block)
{
    yjit_unlink_method_lookup_dependency(block);
    yjit_block_assumptions_free(block);

    // Remove this block from the predecessor's targets
    rb_darray_for(block->incoming, incoming_idx) {
        // Branch from the predecessor to us
        branch_t *pred_branch = rb_darray_get(block->incoming, incoming_idx);

        // If this is us, nullify the target block
        for (size_t succ_idx = 0; succ_idx < 2; succ_idx++) {
            if (pred_branch->blocks[succ_idx] == block) {
                pred_branch->blocks[succ_idx] = NULL;
            }
        }
    }

    // For each outgoing branch
    rb_darray_for(block->outgoing, branch_idx) {
        branch_t *out_branch = rb_darray_get(block->outgoing, branch_idx);

        // For each successor block
        for (size_t succ_idx = 0; succ_idx < 2; succ_idx++) {
            block_t *succ = out_branch->blocks[succ_idx];

            if (succ == NULL)
                continue;

            // Remove this block from the successor's incoming list
            rb_darray_for(succ->incoming, incoming_idx) {
                branch_t *pred_branch = rb_darray_get(succ->incoming, incoming_idx);
                if (pred_branch == out_branch) {
                    rb_darray_remove_unordered(succ->incoming, incoming_idx);
                    break;
                }
            }
        }

        // Free the outgoing branch entry
        free(out_branch);
    }

    rb_darray_free(block->incoming);
    rb_darray_free(block->outgoing);
    rb_darray_free(block->gc_object_offsets);

    free(block);
}

// Remove a block version
static void
block_array_remove(rb_yjit_block_array_t block_array, block_t *block)
{
    block_t **element;
    rb_darray_foreach(block_array, idx, element) {
        if (*element == block) {
            rb_darray_remove_unordered(block_array, idx);
            return;
        }
    }

    RUBY_ASSERT(false);
}

// Invalidate one specific block version
static void
invalidate_block_version(block_t *block)
{
    ASSERT_vm_locking();
    // TODO: want to assert that all other ractors are stopped here. Can't patch
    // machine code that some other thread is running.

    const rb_iseq_t *iseq = block->blockid.iseq;

    //fprintf(stderr, "invalidating block (%p, %d)\n", block->blockid.iseq, block->blockid.idx);
    //fprintf(stderr, "block=%p\n", block);

    // Remove this block from the version array
    rb_yjit_block_array_t versions = yjit_get_version_array(iseq, block->blockid.idx);
    block_array_remove(versions, block);

    // Get a pointer to the generated code for this block
    uint8_t *code_ptr = cb_get_ptr(cb, block->start_pos);

    // For each incoming branch
    rb_darray_for(block->incoming, incoming_idx) {
        branch_t *branch = rb_darray_get(block->incoming, incoming_idx);
        uint32_t target_idx = (branch->dst_addrs[0] == code_ptr)? 0:1;
        RUBY_ASSERT(branch->dst_addrs[target_idx] == code_ptr);
        RUBY_ASSERT(branch->blocks[target_idx] == block);

        // Mark this target as being a stub
        branch->blocks[target_idx] = NULL;

        // Don't patch frozen code region
        if (branch->start_pos < yjit_codepage_frozen_bytes) {
            continue;
        }

        // Create a stub for this branch target
        branch->dst_addrs[target_idx] = get_branch_target(
            block->blockid,
            &block->ctx,
            branch,
            target_idx
        );

        // Check if the invalidated block immediately follows
        bool target_next = block->start_pos == branch->end_pos;

        if (target_next) {
            // The new block will no longer be adjacent
            branch->shape = SHAPE_DEFAULT;
        }

        // Rewrite the branch with the new jump target address
        RUBY_ASSERT(branch->dst_addrs[0] != NULL);
        uint32_t cur_pos = cb->write_pos;
        cb_set_pos(cb, branch->start_pos);
        branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
        branch->end_pos = cb->write_pos;
        branch->block->end_pos = cb->write_pos;
        cb_set_pos(cb, cur_pos);

        if (target_next && branch->end_pos > block->end_pos) {
            fprintf(stderr, "branch_block_idx=%u block_idx=%u over=%d block_size=%d\n",
                branch->block->blockid.idx,
                block->blockid.idx,
                branch->end_pos - block->end_pos,
                block->end_pos - block->start_pos);
            yjit_print_iseq(branch->block->blockid.iseq);
            rb_bug("yjit invalidate rewrote branch past end of invalidated block");
        }
    }

    // Clear out the JIT func so that we can recompile later and so the
    // interpreter will run the iseq

#if JIT_ENABLED
    // Only clear the jit_func when we're invalidating the JIT entry block.
    // We only support compiling iseqs from index 0 right now.  So entry
    // points will always have an instruction index of 0.  We'll need to
    // change this in the future when we support optional parameters because
    // they enter the function with a non-zero PC
    if (block->blockid.idx == 0) {
        iseq->body->jit_func = 0;
    }
#endif

    // TODO:
    // May want to recompile a new entry point (for interpreter entry blocks)
    // This isn't necessary for correctness

    // FIXME:
    // Call continuation addresses on the stack can also be atomically replaced by jumps going to the stub.

    yjit_free_block(block);

#if YJIT_STATS
    yjit_runtime_counters.invalidation_count++;
#endif

    // fprintf(stderr, "invalidation done\n");
}

static void
yjit_init_core(void)
{
    // Nothing yet
}
