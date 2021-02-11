#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "vm_sync.h"
#include "ujit_asm.h"
#include "ujit_utils.h"
#include "ujit_iface.h"
#include "ujit_core.h"
#include "ujit_codegen.h"

// Maximum number of versions per block
#define MAX_VERSIONS 4

// Maximum number of branch instructions we can track
#define MAX_BRANCHES 32768

// Default versioning context (no type information)
const ctx_t DEFAULT_CTX = { { 0 }, 0 };

// Table of block versions indexed by (iseq, index) tuples
st_table *version_tbl;

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

// Add a block version to the map
static void add_block_version(blockid_t blockid, block_t* block)
{
    // Function entry blocks must have stack size 0
    RUBY_ASSERT(!(block->blockid.idx == 0 && block->ctx.stack_size > 0));

    // If there exists a version for this block id
    block_t* first_version = NULL;
    st_lookup(version_tbl, (st_data_t)&blockid, (st_data_t*)&first_version);

    // Link to the next version in a linked list
    if (first_version != NULL) {
        RUBY_ASSERT(block->next == NULL);
        block->next = first_version;
    }

    // Add the block version to the map
    st_insert(version_tbl, (st_data_t)&block->blockid, (st_data_t)block);
    RUBY_ASSERT(find_block_version(blockid, &block->ctx) != NULL);
}

// Add an incoming branch for a given block version
static void add_incoming(block_t* p_block, uint32_t branch_idx)
{
    // Add this branch to the list of incoming branches for the target
    uint32_t* new_list = malloc(sizeof(uint32_t) * (p_block->num_incoming + 1));
    memcpy(new_list, p_block->incoming, p_block->num_incoming);
    new_list[p_block->num_incoming] = branch_idx;
    p_block->incoming = new_list;
    p_block->num_incoming += 1;
}

// Count the number of block versions matching a given blockid
static size_t count_block_versions(blockid_t blockid)
{
    // If there exists a version for this block id
    block_t* first_version;
    if (!rb_st_lookup(version_tbl, (st_data_t)&blockid, (st_data_t*)&first_version))
        return 0;

    size_t count = 0;

    // For each version matching the blockid
    for (block_t* version = first_version; version != NULL; version = version->next)
    {
        count += 1;
    }

    return count;
}

// Retrieve a basic block version for an (iseq, idx) tuple
block_t* find_block_version(blockid_t blockid, const ctx_t* ctx)
{
    // If there exists a version for this block id
    block_t* first_version;
    if (!rb_st_lookup(version_tbl, (st_data_t)&blockid, (st_data_t*)&first_version))
        return NULL;

    // Best match found
    block_t* best_version = NULL;
    int best_diff = INT_MAX;

    // For each version matching the blockid
    for (block_t* version = first_version; version != NULL; version = version->next)
    {
        int diff = ctx_diff(ctx, &version->ctx);

        if (diff < best_diff)
        {
            best_version = version;
            best_diff = diff;
        }
    }

    if (best_version == NULL)
    {
        return NULL;
    }

    return best_version;
}

// Compile a new block version immediately
block_t* gen_block_version(blockid_t blockid, const ctx_t* start_ctx)
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
    ujit_gen_block(ctx, block);

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
        ujit_gen_block(ctx, block);

        // Keep track of the new block version
        add_block_version(block->blockid, block);

        // Patch the last branch address
        last_branch->dst_addrs[0] = cb_get_ptr(cb, block->start_pos);
        add_incoming(block, branch_idx);
        RUBY_ASSERT(block->start_pos == last_branch->end_pos);
    }

    return first_block;
}

// Generate a block version that is an entry point inserted into an iseq
uint8_t* gen_entry_point(const rb_iseq_t *iseq, uint32_t insn_idx)
{
    // The entry context makes no assumptions about types
    blockid_t blockid = { iseq, insn_idx };

    // Write the interpreter entry prologue
    uint8_t* code_ptr = ujit_entry_prologue();

    // Try to generate code for the entry block
    block_t* block = gen_block_version(blockid, &DEFAULT_CTX);

    // If we couldn't generate any code
    if (block->end_idx == insn_idx)
    {
        return NULL;
    }

    return code_ptr;
}

// Called by the generated code when a branch stub is executed
// Triggers compilation of branches and code patching
uint8_t* branch_stub_hit(uint32_t branch_idx, uint32_t target_idx)
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
    if (count_block_versions(target) >= MAX_VERSIONS - 1)
    {
        fprintf(stderr, "version limit hit in branch_stub_hit\n");
        target_ctx = &generic_ctx;
    }

    // Try to find a compiled version of this block
    block_t* p_block = find_block_version(target, target_ctx);

    // If this block hasn't yet been compiled
    if (!p_block)
    {
        p_block = gen_block_version(target, target_ctx);
    }

    // Add this branch to the list of incoming branches for the target
    add_incoming(p_block, branch_idx);

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
        add_incoming(p_block, branch_idx);

        return cb_get_ptr(cb, p_block->start_pos);
    }

    // Generate an outlined stub that will call
    // branch_stub_hit(uint32_t branch_idx, uint32_t target_idx)
    uint8_t* stub_addr = cb_get_ptr(ocb, ocb->write_pos);

    // Save the ujit registers
    push(ocb, REG_CFP);
    push(ocb, REG_EC);
    push(ocb, REG_SP);
    push(ocb, REG_SP);

    mov(ocb, RDI, imm_opnd(branch_idx));
    mov(ocb, RSI, imm_opnd(target_idx));
    call_ptr(ocb, REG0, (void *)&branch_stub_hit);

    // Restore the ujit registers
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
    if (count_block_versions(target0) >= MAX_VERSIONS - 1)
    {
        fprintf(stderr, "version limit hit in branch_stub_hit\n");
        ctx = &generic_ctx;
    }

    block_t* p_block = find_block_version(target0, ctx);

    // If the version already exists
    if (p_block)
    {
        add_incoming(p_block, branch_idx);
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

// Invalidate one specific block version
void
invalidate_block_version(block_t* block)
{
    fprintf(stderr, "invalidating block (%p, %d)\n", block->blockid.iseq, block->blockid.idx);
    fprintf(stderr, "block=%p\n", block);

    // Find the first version for this blockid
    block_t* first_block = NULL;
    rb_st_lookup(version_tbl, (st_data_t)&block->blockid, (st_data_t*)&first_block);
    RUBY_ASSERT(first_block != NULL);

    // Remove the version object from the map so we can re-generate stubs
    if (first_block == block)
    {
        st_data_t key = (st_data_t)&block->blockid;
        int success = st_delete(version_tbl, &key, NULL);
        RUBY_ASSERT(success);
    }
    else
    {
        bool deleted = false;
        for (block_t* cur = first_block; cur != NULL; cur = cur->next)
        {
            if (cur->next == block)
            {
                cur->next = cur->next->next;
                break;
            }
        }
        RUBY_ASSERT(deleted);
    }

    // Get a pointer to the generated code for this block
    uint8_t* code_ptr = cb_get_ptr(cb, block->start_pos);

    // For each incoming branch
    for (uint32_t i = 0; i < block->num_incoming; ++i)
    {
        uint32_t branch_idx = block->incoming[i];
        branch_t* branch = &branch_entries[branch_idx];
        uint32_t target_idx = (branch->dst_addrs[0] == code_ptr)? 0:1;
        //fprintf(stderr, "branch_idx=%d, target_idx=%d\n", branch_idx, target_idx);
        //fprintf(stderr, "blockid.iseq=%p, blockid.idx=%d\n", block->blockid.iseq, block->blockid.idx);

        // Create a stub for this branch target
        branch->dst_addrs[target_idx] = get_branch_target(
            block->blockid,
            &block->ctx,
            branch_idx,
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
            rb_bug("ujit invalidate rewrote branch past block end");
        }
    }

    // If the block is an entry point, it needs to be unmapped from its iseq
    const rb_iseq_t* iseq = block->blockid.iseq;
    uint32_t idx = block->blockid.idx;
    VALUE* entry_pc = &iseq->body->iseq_encoded[idx];
    int entry_opcode = opcode_at_pc(iseq, entry_pc);

    // TODO: unmap_addr2insn in ujit_iface.c? Maybe we can write a function to encompass this logic?
    // Should check how it's used in exit and side-exit
    const void * const *handler_table = rb_vm_get_insns_address_table();
    void* handler_addr = (void*)handler_table[entry_opcode];
    iseq->body->iseq_encoded[idx] = (VALUE)handler_addr;    

    // TODO:
    // May want to recompile a new entry point (for interpreter entry blocks)
    // This isn't necessary for correctness

    // FIXME:
    // Call continuation addresses on the stack can also be atomically replaced by jumps going to the stub.

    // Free the old block version object
    free(block->incoming);
    free(block);

    fprintf(stderr, "invalidation done\n");
}

int blockid_cmp(st_data_t arg0, st_data_t arg1)
{
    const blockid_t *block0 = (const blockid_t*)arg0;
    const blockid_t *block1 = (const blockid_t*)arg1;
    return (block0->iseq != block1->iseq) || (block0->idx != block1->idx);
}

st_index_t blockid_hash(st_data_t arg)
{
    const blockid_t *blockid = (const blockid_t*)arg;
    st_index_t hash0 = st_numhash((st_data_t)blockid->iseq);
    st_index_t hash1 = st_numhash((st_data_t)(uint64_t)blockid->idx);

    // Use XOR to combine the hashes
    return hash0 ^ hash1;
}

static const struct st_hash_type hashtype_blockid = {
    blockid_cmp,
    blockid_hash,
};

void
ujit_init_core(void)
{
    // Initialize the version hash table
    version_tbl = st_init_table(&hashtype_blockid);
}
