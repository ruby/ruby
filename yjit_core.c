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

// Maximum number of branch instructions we can track
#define MAX_BRANCHES 100000

// Registered branch entries
branch_t branch_entries[MAX_BRANCHES];
uint32_t num_branches = 0;

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
ctx_stack_push(ctx_t* ctx, int type)
{
    // Keep track of the type of the value
    RUBY_ASSERT(type <= RUBY_T_MASK);
    if (ctx->stack_size < MAX_TEMP_TYPES)
        ctx->temp_types[ctx->stack_size] = type;

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
        if (idx < MAX_TEMP_TYPES)
            ctx->temp_types[idx] = T_NONE;
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
Get the type of the topmost value on the temp stack
Returns T_NONE if unknown
*/
int
ctx_get_top_type(ctx_t* ctx)
{
    RUBY_ASSERT(ctx->stack_size > 0);

    if (ctx->stack_size > MAX_TEMP_TYPES)
        return T_NONE;

    return ctx->temp_types[ctx->stack_size - 1];
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

    if (dst->self_is_object != src->self_is_object)
        return INT_MAX;

    // Difference sum
    int diff = 0;

    // For each temporary variable
    for (size_t i = 0; i < MAX_TEMP_TYPES; ++i)
    {
        int t_src = src->temp_types[i];
        int t_dst = dst->temp_types[i];

        if (t_dst != t_src)
        {
            // It's OK to lose some type information
            if (t_dst == T_NONE)
                diff += 1;
            else
                return INT_MAX;
        }
    }

    return diff;
}

// Get all blocks for a particular place in an iseq.
static rb_yjit_block_array_t
get_version_array(const rb_iseq_t *iseq, unsigned idx)
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
    return rb_darray_size(get_version_array(blockid.iseq, blockid.idx));
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

// Retrieve a basic block version for an (iseq, idx) tuple
block_t* find_block_version(blockid_t blockid, const ctx_t* ctx)
{
    rb_yjit_block_array_t versions = get_version_array(blockid.iseq, blockid.idx);

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

void
yjit_branches_update_references(void)
{
    for (uint32_t i = 0; i < num_branches; i++) {
        branch_entries[i].targets[0].iseq = (const void *)rb_gc_location((VALUE)branch_entries[i].targets[0].iseq);
        branch_entries[i].targets[1].iseq = (const void *)rb_gc_location((VALUE)branch_entries[i].targets[1].iseq);
    }
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
        // If no branches were generated, stop
        if (num_branches == 0) {
            break;
        }

        // Get the last branch entry
        uint32_t branch_idx = num_branches - 1;
        branch_t* last_branch = &branch_entries[num_branches - 1];

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
        rb_darray_append(&block->incoming, branch_idx);

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
branch_stub_hit(uint32_t branch_idx, uint32_t target_idx, rb_execution_context_t* ec)
{
    uint8_t* dst_addr;

    RB_VM_LOCK_ENTER();

    RUBY_ASSERT(branch_idx < num_branches);
    RUBY_ASSERT(target_idx < 2);
    branch_t *branch = &branch_entries[branch_idx];
    blockid_t target = branch->targets[target_idx];
    const ctx_t* target_ctx = &branch->target_ctxs[target_idx];

    //fprintf(stderr, "\nstub hit, branch idx: %d, target idx: %d\n", branch_idx, target_idx);
    //fprintf(stderr, "blockid.iseq=%p, blockid.idx=%d\n", target.iseq, target.idx);
    //fprintf(stderr, "chain_depth=%d\n", target_ctx->chain_depth);

    // Update the PC in the current CFP, because it
    // may be out of sync in JITted code
    ec->cfp->pc = iseq_pc_at_idx(target.iseq, target.idx);

    // If either of the target blocks will be placed next
    if (cb->write_pos == branch->end_pos)
    {
        //fprintf(stderr, "target idx %d will be placed next\n", target_idx);
        branch->shape = (uint8_t)target_idx;

        // Rewrite the branch with the new, potentially more compact shape
        cb_set_pos(cb, branch->start_pos);
        branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
        RUBY_ASSERT(cb->write_pos <= branch->end_pos);
    }

    // Limit the number of block versions
    ctx_t generic_ctx = DEFAULT_CTX;
    generic_ctx.stack_size = target_ctx->stack_size;
    generic_ctx.sp_offset = target_ctx->sp_offset;
    if (target_ctx->chain_depth == 0) { // guard chains implement limits individually
        if (get_num_versions(target) >= MAX_VERSIONS - 1) {
            //fprintf(stderr, "version limit hit in branch_stub_hit\n");
            target_ctx = &generic_ctx;
        }
    }

    // Try to find a compiled version of this block
    block_t* p_block = find_block_version(target, target_ctx);

    // If this block hasn't yet been compiled
    if (!p_block) {
        p_block = gen_block_version(target, target_ctx, ec);
    }

    // Add this branch to the list of incoming branches for the target
    rb_darray_append(&p_block->incoming, branch_idx);

    // Update the branch target address
    dst_addr = cb_get_ptr(cb, p_block->start_pos);
    branch->dst_addrs[target_idx] = dst_addr;

    // Rewrite the branch with the new jump target address
    RUBY_ASSERT(branch->dst_addrs[0] != NULL);
    uint32_t cur_pos = cb->write_pos;
    cb_set_pos(cb, branch->start_pos);
    branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
    RUBY_ASSERT(cb->write_pos <= branch->end_pos);
    branch->end_pos = cb->write_pos;
    cb_set_pos(cb, cur_pos);

    RB_VM_LOCK_LEAVE();

    // Return a pointer to the compiled block version
    return dst_addr;
}

// Get a version or stub corresponding to a branch target
uint8_t* get_branch_target(
    blockid_t target,
    const ctx_t* ctx,
    uint32_t branch_idx,
    uint32_t target_idx
)
{
    //fprintf(stderr, "get_branch_target, block (%p, %d)\n", target.iseq, target.idx);

    block_t* p_block = find_block_version(target, ctx);

    if (p_block)
    {
        // Add an incoming branch for this version
        rb_darray_append(&p_block->incoming, branch_idx);

        // Return a pointer to the compiled code
        return cb_get_ptr(cb, p_block->start_pos);
    }

    // Generate an outlined stub that will call
    // branch_stub_hit(uint32_t branch_idx, uint32_t target_idx)
    uint8_t* stub_addr = cb_get_ptr(ocb, ocb->write_pos);

    // Save the yjit registers
    push(ocb, REG_CFP);
    push(ocb, REG_EC);
    push(ocb, REG_SP);
    push(ocb, REG_SP);

    // Call branch_stub_hit(branch_idx, target_idx, ec)
    mov(ocb, C_ARG_REGS[2], REG_EC);
    mov(ocb, C_ARG_REGS[1], imm_opnd(target_idx));
    mov(ocb, C_ARG_REGS[0], imm_opnd(branch_idx));
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
    const ctx_t* src_ctx,
    blockid_t target0,
    const ctx_t* ctx0,
    blockid_t target1,
    const ctx_t* ctx1,
    branchgen_fn gen_fn
)
{
    RUBY_ASSERT(target0.iseq != NULL);
    //RUBY_ASSERT(target1.iseq != NULL);
    RUBY_ASSERT(num_branches < MAX_BRANCHES);
    uint32_t branch_idx = num_branches++;

    // Get the branch targets or stubs
    uint8_t* dst_addr0 = get_branch_target(target0, ctx0, branch_idx, 0);
    uint8_t* dst_addr1 = ctx1? get_branch_target(target1, ctx1, branch_idx, 1):NULL;

    // Call the branch generation function
    uint32_t start_pos = cb->write_pos;
    gen_fn(cb, dst_addr0, dst_addr1, SHAPE_DEFAULT);
    uint32_t end_pos = cb->write_pos;

    // Register this branch entry
    branch_t branch_entry = {
        start_pos,
        end_pos,
        *src_ctx,
        { target0, target1 },
        { *ctx0, ctx1? *ctx1:DEFAULT_CTX },
        { dst_addr0, dst_addr1 },
        gen_fn,
        SHAPE_DEFAULT
    };

    branch_entries[branch_idx] = branch_entry;
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
    const ctx_t* ctx,
    blockid_t target0
)
{
    RUBY_ASSERT(target0.iseq != NULL);
    RUBY_ASSERT(num_branches < MAX_BRANCHES);
    uint32_t branch_idx = num_branches++;

    // Branch targets or stub adddress
    uint8_t* dst_addr0;

    // Shape of the branch
    uint8_t branch_shape;

    // Branch start and end positions
    uint32_t start_pos;
    uint32_t end_pos;

    // Limit the number of block versions
    ctx_t generic_ctx = DEFAULT_CTX;
    generic_ctx.stack_size = ctx->stack_size;
    generic_ctx.sp_offset = ctx->sp_offset;
    if (get_num_versions(target0) >= MAX_VERSIONS - 1)
    {
        //fprintf(stderr, "version limit hit in gen_direct_jump\n");
        ctx = &generic_ctx;
    }

    block_t* p_block = find_block_version(target0, ctx);

    // If the version already exists
    if (p_block)
    {
        rb_darray_append(&p_block->incoming, branch_idx);
        dst_addr0 = cb_get_ptr(cb, p_block->start_pos);
        branch_shape = SHAPE_DEFAULT;

        // Call the branch generation function
        start_pos = cb->write_pos;
        gen_jump_branch(cb, dst_addr0, NULL, branch_shape);
        end_pos = cb->write_pos;
    }
    else
    {
        // The target block will follow next
        // It will be compiled in gen_block_version()
        dst_addr0 = NULL;
        branch_shape = SHAPE_NEXT0;
        start_pos = cb->write_pos;
        end_pos = cb->write_pos;
    }

    // Register this branch entry
    branch_t branch_entry = {
        start_pos,
        end_pos,
        *ctx,
        { target0, BLOCKID_NULL },
        { *ctx, *ctx },
        { dst_addr0, NULL },
        gen_jump_branch,
        branch_shape
    };

    branch_entries[branch_idx] = branch_entry;
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
        rb_backtrace();
        exit(1);
    }

    ctx_t next_ctx = *cur_ctx;

    if (next_ctx.chain_depth >= UINT8_MAX) {
        rb_bug("max block version chain depth reached");
    }

    next_ctx.chain_depth += 1;

    RUBY_ASSERT(num_branches < MAX_BRANCHES);
    uint32_t branch_idx = num_branches++;

    // Get the branch targets or stubs
    blockid_t target0 = (blockid_t){ block->blockid.iseq, insn_idx };
    uint8_t* dst_addr0 = get_branch_target(target0, &next_ctx, branch_idx, 0);

    // Call the branch generation function
    uint32_t start_pos = cb->write_pos;
    gen_jump_branch(cb, dst_addr0, NULL, SHAPE_DEFAULT);
    uint32_t end_pos = cb->write_pos;

    // Register this branch entry
    branch_t branch_entry = {
        start_pos,
        end_pos,
        *cur_ctx,
        { target0, BLOCKID_NULL },
        { next_ctx, next_ctx },
        { dst_addr0, NULL },
        gen_jump_branch,
        SHAPE_DEFAULT
    };

    branch_entries[branch_idx] = branch_entry;
}

// Remove all references to a block then free it.
void
yjit_free_block(block_t *block)
{
    yjit_unlink_method_lookup_dependency(block);
    yjit_block_assumptions_free(block);

    rb_darray_free(block->incoming);
    rb_darray_free(block->gc_object_offsets);

    free(block);
}

// Remove a block version without reordering the version array
static bool
block_array_remove(rb_yjit_block_array_t block_array, block_t *block)
{
    bool after_target = false;
    block_t **element;
    rb_darray_foreach(block_array, idx, element) {
        if (after_target) {
            rb_darray_set(block_array, idx - 1, *element);
        }
        else if (*element == block) {
            after_target = true;
        }
    }

    if (after_target) rb_darray_pop_back(block_array);

    return after_target;
}

// Invalidate one specific block version
void
invalidate_block_version(block_t* block)
{
    const rb_iseq_t *iseq = block->blockid.iseq;

    // fprintf(stderr, "invalidating block (%p, %d)\n", block->blockid.iseq, block->blockid.idx);
    // fprintf(stderr, "block=%p\n", block);

    // Remove this block from the version array
    rb_yjit_block_array_t versions = get_version_array(iseq, block->blockid.idx);
    RB_UNUSED_VAR(bool removed);
    removed = block_array_remove(versions, block);
    RUBY_ASSERT(removed);

    // Get a pointer to the generated code for this block
    uint8_t* code_ptr = cb_get_ptr(cb, block->start_pos);

    // For each incoming branch
    uint32_t* branch_idx;
    rb_darray_foreach(block->incoming, i, branch_idx)
    {
        //uint32_t branch_idx = block->incoming[i];
        branch_t* branch = &branch_entries[*branch_idx];
        uint32_t target_idx = (branch->dst_addrs[0] == code_ptr)? 0:1;
        //fprintf(stderr, "branch_idx=%d, target_idx=%d\n", branch_idx, target_idx);
        //fprintf(stderr, "blockid.iseq=%p, blockid.idx=%d\n", block->blockid.iseq, block->blockid.idx);

        // Create a stub for this branch target
        branch->dst_addrs[target_idx] = get_branch_target(
            block->blockid,
            &block->ctx,
            *branch_idx,
            target_idx
        );

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
    VALUE* entry_pc = iseq_pc_at_idx(iseq, idx);
    int entry_opcode = opcode_at_pc(iseq, entry_pc);

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
