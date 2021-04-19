#include "ruby/ruby.h"
#include "internal.h"
#include "vm_sync.h"
#include "builtin.h"

#include "yjit_asm.h"
#include "yjit_utils.h"
#include "yjit_iface.h"
#include "yjit_core.h"
#include "yjit_codegen.h"

// Maximum number of versions per block
#define MAX_VERSIONS 4

/*
Get an operand for the adjusted stack pointer address
*/
x86opnd_t
ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes)
{
    int32_t offset = (ctx->sp_offset * sizeof(VALUE)) + offset_bytes;
    return mem_opnd(64, REG_SP, offset);
}

/*
Push one new value on the temp stack
Return a pointer to the new stack top
*/
x86opnd_t
ctx_stack_push(ctx_t* ctx, val_type_t type)
{
    // Keep track of the type of the value
    if (ctx->stack_size < MAX_TEMP_TYPES) {
        ctx->temp_mapping[ctx->stack_size] = MAP_STACK;
        ctx->temp_types[ctx->stack_size] = type;
    }

    ctx->stack_size += 1;
    ctx->sp_offset += 1;

    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1) * sizeof(VALUE);
    return mem_opnd(64, REG_SP, offset);
}

/*
Push the self value on the stack
*/
x86opnd_t
ctx_stack_push_self(ctx_t* ctx)
{
    // Keep track of the type of the value
    if (ctx->stack_size < MAX_TEMP_TYPES) {
        ctx->temp_mapping[ctx->stack_size] = MAP_SELF;
        ctx->temp_types[ctx->stack_size] = ctx->self_type;
    }

    ctx->stack_size += 1;
    ctx->sp_offset += 1;

    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1) * sizeof(VALUE);
    return mem_opnd(64, REG_SP, offset);
}

/*
Push a local variable on the stack
*/
x86opnd_t
ctx_stack_push_local(ctx_t* ctx, size_t local_idx)
{
    // Keep track of the type of the value
    if (ctx->stack_size < MAX_TEMP_TYPES && local_idx < MAX_LOCAL_TYPES) {
        ctx->temp_mapping[ctx->stack_size] = (temp_mapping_t){ .kind = TEMP_LOCAL, .idx = local_idx };
    }

    ctx->stack_size += 1;
    ctx->sp_offset += 1;

    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1) * sizeof(VALUE);
    return mem_opnd(64, REG_SP, offset);
}

/*
Pop N values off the stack
Return a pointer to the stack top before the pop operation
*/
x86opnd_t
ctx_stack_pop(ctx_t* ctx, size_t n)
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
x86opnd_t
ctx_stack_opnd(ctx_t* ctx, int32_t idx)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->sp_offset - 1 - idx) * sizeof(VALUE);
    x86opnd_t opnd = mem_opnd(64, REG_SP, offset);

    return opnd;
}

/**
Get the type of an instruction operand
*/
val_type_t
ctx_get_opnd_type(const ctx_t* ctx, insn_opnd_t opnd)
{
    if (opnd.is_self)
        return ctx->self_type;

    if (ctx->stack_size > MAX_TEMP_TYPES)
        return TYPE_UNKNOWN;

    RUBY_ASSERT(opnd.idx < ctx->stack_size);
    temp_mapping_t mapping = ctx->temp_mapping[ctx->stack_size - 1 - opnd.idx];

    switch (mapping.kind)
    {
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

/**
Set the type of an instruction operand
*/
void ctx_set_opnd_type(ctx_t* ctx, insn_opnd_t opnd, val_type_t type)
{
    RUBY_ASSERT(opnd.idx < ctx->stack_size);

    if (opnd.is_self) {
        ctx->self_type = type;
        return;
    }

    if (ctx->stack_size > MAX_TEMP_TYPES)
        return;

    temp_mapping_t mapping = ctx->temp_mapping[ctx->stack_size - 1 - opnd.idx];

    switch (mapping.kind)
    {
        case TEMP_SELF:
        ctx->self_type = type;
        break;

        case TEMP_STACK:
        ctx->temp_types[ctx->stack_size - 1 - opnd.idx] = type;
        break;

        case TEMP_LOCAL:
        RUBY_ASSERT(mapping.idx < MAX_LOCAL_TYPES);
        ctx->local_types[mapping.idx] = type;
        break;
    }
}

/**
Set the type of a local variable
*/
void ctx_set_local_type(ctx_t* ctx, size_t idx, val_type_t type)
{
    if (idx >= MAX_LOCAL_TYPES)
        return;

    ctx->local_types[idx] = type;
}

// Erase local variable type information
// eg: because of a call we can't track
void ctx_clear_local_types(ctx_t* ctx)
{
    memset(&ctx->local_types, 0, sizeof(ctx->local_types));
}

/*
Compute a difference between two value types
Returns 0 if the two are the same
Returns > 0 if different but compatible
Returns INT_MAX if incompatible
*/
int type_diff(val_type_t src, val_type_t dst)
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
int ctx_diff(const ctx_t* src, const ctx_t* dst)
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
        val_type_t t_src = ctx_get_opnd_type(src, OPND_STACK(i));
        val_type_t t_dst = ctx_get_opnd_type(dst, OPND_STACK(i));
        int temp_diff = type_diff(t_src, t_dst);

        if (temp_diff == INT_MAX)
            return INT_MAX;

        diff += temp_diff;
    }

    return diff;
}

// Get all blocks for a particular place in an iseq.
rb_yjit_block_array_t
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
add_block_version(blockid_t blockid, block_t* block)
{
    // Function entry blocks must have stack size 0
    RUBY_ASSERT(!(block->blockid.idx == 0 && block->ctx.stack_size > 0));
    const rb_iseq_t *iseq = block->blockid.iseq;
    struct rb_iseq_constant_body *body = iseq->body;

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

#if RUBY_DEBUG
        // First block compiled for this iseq
        rb_compiled_iseq_count++;
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
        RB_OBJ_WRITTEN(iseq, Qundef, block->receiver_klass);
        RB_OBJ_WRITTEN(iseq, Qundef, block->callee_cme);

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
}

// Create a new outgoing branch entry for a block
static branch_t*
make_branch_entry(block_t* block, const ctx_t* src_ctx, branchgen_fn gen_fn)
{
    RUBY_ASSERT(block != NULL);

    // Allocate and zero-initialize
    branch_t* branch = calloc(1, sizeof(branch_t));

    branch->block = block;
    branch->src_ctx = *src_ctx;
    branch->gen_fn = gen_fn;
    branch->shape = SHAPE_DEFAULT;

    // Add to the list of outgoing branches for the block
    rb_darray_append(&block->outgoing, branch);

    return branch;
}

// Retrieve a basic block version for an (iseq, idx) tuple
block_t* find_block_version(blockid_t blockid, const ctx_t* ctx)
{
    rb_yjit_block_array_t versions = yjit_get_version_array(blockid.iseq, blockid.idx);

    // Best match found
    block_t* best_version = NULL;
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

    return best_version;
}

// Compile a new block version immediately
block_t* gen_block_version(blockid_t blockid, const ctx_t* start_ctx, rb_execution_context_t* ec)
{
    // Copy the context to avoid mutating it
    ctx_t ctx_copy = *start_ctx;
    ctx_t* ctx = &ctx_copy;

    // Allocate a new block version object
    block_t* first_block = calloc(1, sizeof(block_t));
    first_block->blockid = blockid;
    memcpy(&first_block->ctx, ctx, sizeof(ctx_t));

    // Block that is currently being compiled
    block_t* block = first_block;

    // Generate code for the first block
    yjit_gen_block(ctx, block, ec);

    // Keep track of the new block version
    add_block_version(block->blockid, block);

    // For each successor block to compile
    for (;;) {
        // If the previous block compiled doesn't have outgoing branches, stop
        if (rb_darray_size(block->outgoing) == 0) {
            break;
        }

        // Get the last outgoing branch from the previous block
        branch_t* last_branch = rb_darray_back(block->outgoing);

        // If there is no next block to compile, stop
        if (last_branch->dst_addrs[0] || last_branch->dst_addrs[1]) {
            break;
        }

        if (last_branch->targets[0].iseq == NULL) {
            rb_bug("invalid target for last branch");
        }

        // Use the context from the branch
        *ctx = last_branch->target_ctxs[0];

        // Allocate a new block version object
        block = calloc(1, sizeof(block_t));
        block->blockid = last_branch->targets[0];
        memcpy(&block->ctx, ctx, sizeof(ctx_t));

        // Generate code for the current block
        yjit_gen_block(ctx, block, ec);

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
uint8_t* gen_entry_point(const rb_iseq_t *iseq, uint32_t insn_idx, rb_execution_context_t *ec)
{
    // The entry context makes no assumptions about types
    blockid_t blockid = { iseq, insn_idx };

    // Write the interpreter entry prologue
    uint8_t* code_ptr = yjit_entry_prologue();

    // Try to generate code for the entry block
    block_t* block = gen_block_version(blockid, &DEFAULT_CTX, ec);

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
branch_stub_hit(branch_t* branch, const uint32_t target_idx, rb_execution_context_t* ec)
{
    uint8_t* dst_addr;
    ctx_t generic_ctx;

    // Stop other ractors since we are going to patch machine code.
    // This is how the GC does it.
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    RUBY_ASSERT(branch != NULL);
    RUBY_ASSERT(target_idx < 2);
    blockid_t target = branch->targets[target_idx];
    const ctx_t* target_ctx = &branch->target_ctxs[target_idx];

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
        block_t* p_block = find_block_version(target, target_ctx);

        // If this block hasn't yet been compiled
        if (!p_block) {
            // Limit the number of block versions
            if (target_ctx->chain_depth == 0) { // guard chains implement limits individually
                if (get_num_versions(target) >= MAX_VERSIONS - 1) {
                    //fprintf(stderr, "version limit hit in branch_stub_hit\n");
                    generic_ctx = DEFAULT_CTX;
                    generic_ctx.stack_size = target_ctx->stack_size;
                    generic_ctx.sp_offset = target_ctx->sp_offset;
                    target_ctx = &generic_ctx;
                }
            }

            // If the new block can be generated right after the branch (at cb->write_pos)
            if (cb->write_pos == branch->end_pos) {
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
        RUBY_ASSERT(branch->dst_addrs[0] != NULL);
        uint32_t cur_pos = cb->write_pos;
        cb_set_pos(cb, branch->start_pos);
        branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
        RUBY_ASSERT(cb->write_pos == branch->end_pos && "branch can't change size");
        cb_set_pos(cb, cur_pos);

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
uint8_t* get_branch_target(
    blockid_t target,
    const ctx_t* ctx,
    branch_t* branch,
    uint32_t target_idx
)
{
    //fprintf(stderr, "get_branch_target, block (%p, %d)\n", target.iseq, target.idx);

    block_t* p_block = find_block_version(target, ctx);

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
    uint8_t* stub_addr = cb_get_ptr(ocb, ocb->write_pos);

    // Save the yjit registers
    push(ocb, REG_CFP);
    push(ocb, REG_EC);
    push(ocb, REG_SP);
    push(ocb, REG_SP);

    // Call branch_stub_hit(branch_idx, target_idx, ec)
    mov(ocb, C_ARG_REGS[2], REG_EC);
    mov(ocb, C_ARG_REGS[1],  imm_opnd(target_idx));
    mov(ocb, C_ARG_REGS[0], const_ptr_opnd(branch));
    call_ptr(ocb, REG0, (void *)&branch_stub_hit);

    // Restore the yjit registers
    pop(ocb, REG_SP);
    pop(ocb, REG_SP);
    pop(ocb, REG_EC);
    pop(ocb, REG_CFP);

    // Jump to the address returned by the
    // branch_stub_hit call
    jmp_rm(ocb, RAX);

    return stub_addr;
}

void gen_branch(
    block_t* block,
    const ctx_t* src_ctx,
    blockid_t target0,
    const ctx_t* ctx0,
    blockid_t target1,
    const ctx_t* ctx1,
    branchgen_fn gen_fn
)
{
    RUBY_ASSERT(target0.iseq != NULL);

    branch_t* branch = make_branch_entry(block, src_ctx, gen_fn);
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

void
gen_jump_branch(codeblock_t* cb, uint8_t* target0, uint8_t* target1, uint8_t shape)
{
    switch (shape)
    {
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

void gen_direct_jump(
    block_t* block,
    const ctx_t* ctx,
    blockid_t target0
)
{
    RUBY_ASSERT(target0.iseq != NULL);
    ctx_t generic_ctx;

    branch_t* branch = make_branch_entry(block, ctx, gen_jump_branch);
    branch->targets[0] = target0;
    branch->target_ctxs[0] = *ctx;

    block_t* p_block = find_block_version(target0, ctx);

    // If the version already exists
    if (p_block)
    {
        rb_darray_append(&p_block->incoming, branch);

        branch->dst_addrs[0] = cb_get_ptr(cb, p_block->start_pos);
        branch->blocks[0] = p_block;
        branch->shape = SHAPE_DEFAULT;

        // Call the branch generation function
        branch->start_pos = cb->write_pos;
        gen_jump_branch(cb, branch->dst_addrs[0], NULL, SHAPE_DEFAULT);
        branch->end_pos = cb->write_pos;
    }
    else
    {
        // Limit the number of block versions
        if (get_num_versions(target0) >= MAX_VERSIONS - 1)
        {
            //fprintf(stderr, "version limit hit in gen_direct_jump\n");
            generic_ctx = DEFAULT_CTX;
            generic_ctx.stack_size = ctx->stack_size;
            generic_ctx.sp_offset = ctx->sp_offset;
            ctx = &generic_ctx;
        }

        // The target block will be compiled next
        // It will be compiled in gen_block_version()
        branch->dst_addrs[0] = NULL;
        branch->shape = SHAPE_NEXT0;
        branch->start_pos = cb->write_pos;
        branch->end_pos = cb->write_pos;
    }
}

// Create a stub to force the code up to this point to be executed
void defer_compilation(
    block_t* block,
    uint32_t insn_idx,
    ctx_t* cur_ctx
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

    branch_t* branch = make_branch_entry(block, cur_ctx, gen_jump_branch);

    // Get the branch targets or stubs
    branch->target_ctxs[0] = next_ctx;
    branch->targets[0] = (blockid_t){ block->blockid.iseq, insn_idx };
    branch->dst_addrs[0] = get_branch_target(branch->targets[0], &next_ctx, branch, 0);

    // Call the branch generation function
    branch->start_pos = cb->write_pos;
    gen_jump_branch(cb, branch->dst_addrs[0], NULL, SHAPE_DEFAULT);
    branch->end_pos = cb->write_pos;
}

// Remove all references to a block then free it.
void
yjit_free_block(block_t *block)
{
    yjit_unlink_method_lookup_dependency(block);
    yjit_block_assumptions_free(block);

    // For each outgoing branch
    rb_darray_for(block->outgoing, branch_idx) {
        branch_t* out_branch = rb_darray_get(block->outgoing, branch_idx);

        // For each successor block
        for (size_t succ_idx = 0; succ_idx < 2; succ_idx++) {
            block_t* succ = out_branch->blocks[succ_idx];

            if (succ == NULL)
                continue;

            // Remove this block from the successor's incoming list
            rb_darray_for(succ->incoming, incoming_idx) {
                branch_t* pred_branch = rb_darray_get(succ->incoming, incoming_idx);
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
void
invalidate_block_version(block_t* block)
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
    uint8_t* code_ptr = cb_get_ptr(cb, block->start_pos);

    // For each incoming branch
    rb_darray_for(block->incoming, incoming_idx)
    {
        branch_t* branch = rb_darray_get(block->incoming, incoming_idx);
        uint32_t target_idx = (branch->dst_addrs[0] == code_ptr)? 0:1;
        RUBY_ASSERT(!branch->blocks[target_idx] || branch->blocks[target_idx] == block);

        // Create a stub for this branch target
        branch->dst_addrs[target_idx] = get_branch_target(
            block->blockid,
            &block->ctx,
            branch,
            target_idx
        );

        // Mark this target as being a stub
        branch->blocks[target_idx] = NULL;

        // Check if the invalidated block immediately follows
        bool target_next = block->start_pos == branch->end_pos;

        if (target_next)
        {
            // The new block will no longer be adjacent
            branch->shape = SHAPE_DEFAULT;
        }

        // Rewrite the branch with the new jump target address
        RUBY_ASSERT(branch->dst_addrs[0] != NULL);
        uint32_t cur_pos = cb->write_pos;
        cb_set_pos(cb, branch->start_pos);
        branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
        branch->end_pos = cb->write_pos;
        cb_set_pos(cb, cur_pos);

        if (target_next && branch->end_pos > block->end_pos)
        {
            rb_bug("yjit invalidate rewrote branch past block end");
        }
    }

    uint32_t idx = block->blockid.idx;
    // FIXME: the following says "if", but it's unconditional.
    // If the block is an entry point, it needs to be unmapped from its iseq
    VALUE* entry_pc = yjit_iseq_pc_at_idx(iseq, idx);
    int entry_opcode = yjit_opcode_at_pc(iseq, entry_pc);

    // TODO: unmap_addr2insn in yjit_iface.c? Maybe we can write a function to encompass this logic?
    // Should check how it's used in exit and side-exit
    const void * const *handler_table = rb_vm_get_insns_address_table();
    void* handler_addr = (void*)handler_table[entry_opcode];
    iseq->body->iseq_encoded[idx] = (VALUE)handler_addr;

    // TODO:
    // May want to recompile a new entry point (for interpreter entry blocks)
    // This isn't necessary for correctness

    // FIXME:
    // Call continuation addresses on the stack can also be atomically replaced by jumps going to the stub.

    yjit_free_block(block);

    // fprintf(stderr, "invalidation done\n");
}

void
yjit_init_core(void)
{
    // Nothing yet
}
