#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "ujit_asm.h"
#include "ujit_utils.h"
#include "ujit_iface.h"
#include "ujit_core.h"
#include "ujit_codegen.h"

// Maximum number of branch instructions we can track
#define MAX_BRANCHES 32768

// Table of block versions indexed by (iseq, index) tuples
st_table * version_tbl;

// Registered branch entries
branch_t branch_entries[MAX_BRANCHES];
uint32_t num_branches = 0;

/*
Get an operand for the adjusted stack pointer address
*/
x86opnd_t
ctx_sp_opnd(ctx_t* ctx, int32_t offset_bytes)
{
    int32_t offset = (ctx->stack_size) * 8 + offset_bytes;
    return mem_opnd(64, REG_SP, offset);
}

/*
Make space on the stack for N values
Return a pointer to the new stack top
*/
x86opnd_t
ctx_stack_push(ctx_t* ctx, size_t n)
{
    ctx->stack_size += n;

    // SP points just above the topmost value
    int32_t offset = (ctx->stack_size - 1) * 8;
    return mem_opnd(64, REG_SP, offset);
}

/*
Pop N values off the stack
Return a pointer to the stack top before the pop operation
*/
x86opnd_t
ctx_stack_pop(ctx_t* ctx, size_t n)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_size - 1) * 8;
    x86opnd_t top = mem_opnd(64, REG_SP, offset);

    ctx->stack_size -= n;

    return top;
}

x86opnd_t
ctx_stack_opnd(ctx_t* ctx, int32_t idx)
{
    // SP points just above the topmost value
    int32_t offset = (ctx->stack_size - 1 - idx) * 8;
    x86opnd_t opnd = mem_opnd(64, REG_SP, offset);

    return opnd;
}

// Add an incoming branch for a given block version
static void add_incoming(block_t* p_block, uint32_t branch_idx)
{
    // Add this branch to the list of incoming branches for the target
    uint32_t* new_list = malloc(sizeof(uint32_t) * p_block->num_incoming + 1);
    memcpy(new_list, p_block->incoming, p_block->num_incoming);
    new_list[p_block->num_incoming] = branch_idx;
    p_block->incoming = new_list;
    p_block->num_incoming += 1;
}

// Retrieve a basic block version for an (iseq, idx) tuple
block_t* find_block_version(blockid_t blockid, const ctx_t* ctx)
{
    // If there exists a version for this block id
    st_data_t st_version;
    if (rb_st_lookup(version_tbl, (st_data_t)&blockid, &st_version)) {
        return (block_t*)st_version;
    }

    //
    // TODO: use the ctx parameter to search existing versions for a match
    //

    return NULL;
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
    st_insert(version_tbl, (st_data_t)&block->blockid, (st_data_t)block);

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

        // Allocate a new block version object
        block = calloc(1, sizeof(block_t));
        block->blockid = last_branch->targets[0];
        memcpy(&block->ctx, ctx, sizeof(ctx_t));

        // Generate code for the current block
        ujit_gen_block(ctx, block);

        // Keep track of the new block version
        st_insert(version_tbl, (st_data_t)&block->blockid, (st_data_t)block);

        // Patch the last branch address
        last_branch->dst_addrs[0] = cb_get_ptr(cb, block->start_pos);
        add_incoming(block, branch_idx);
        assert (block->start_pos == last_branch->end_pos);
    }

    return first_block;
}

// Generate a block version that is an entry point inserted into an iseq
uint8_t* gen_entry_point(const rb_iseq_t *iseq, uint32_t insn_idx)
{
    // The entry context makes no assumptions about types
    blockid_t blockid = { iseq, insn_idx };
    ctx_t ctx = { 0 };

    // Write the interpreter entry prologue
    uint8_t* code_ptr = ujit_entry_prologue();

    // Try to generate code for the entry block
    block_t* block = gen_block_version(blockid, &ctx);

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
    assert (branch_idx < num_branches);
    assert (target_idx < 2);
    branch_t *branch = &branch_entries[branch_idx];
    blockid_t target = branch->targets[target_idx];
    ctx_t* target_ctx = &branch->target_ctxs[target_idx];

    //fprintf(stderr, "\nstub hit, branch idx: %d, target idx: %d\n", branch_idx, target_idx);
    //fprintf(stderr, "cb->write_pos=%ld\n", cb->write_pos);
    //fprintf(stderr, "branch->end_pos=%d\n", branch->end_pos);

    // If either of the target blocks will be placed next
    if (cb->write_pos == branch->end_pos)
    {
        //fprintf(stderr, "target idx %d will be placed next\n", target_idx);
        branch->shape = (uint8_t)target_idx;

        // Rewrite the branch with the new, potentially more compact shape
        cb_set_pos(cb, branch->start_pos);
        branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
        assert (cb->write_pos <= branch->end_pos);
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
    uint8_t* dst_addr = cb_get_ptr(cb, p_block->start_pos);
    branch->dst_addrs[target_idx] = dst_addr;

    // Rewrite the branch with the new jump target address
    assert (branch->dst_addrs[0] != NULL);
    assert (branch->dst_addrs[1] != NULL);
    uint32_t cur_pos = cb->write_pos;
    cb_set_pos(cb, branch->start_pos);
    branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
    assert (cb->write_pos <= branch->end_pos);
    branch->end_pos = cb->write_pos;
    cb_set_pos(cb, cur_pos);

    // Return a pointer to the compiled block version
    return dst_addr;
}

// Get a version or stub corresponding to a branch target
// TODO: need incoming and target contexts
uint8_t* get_branch_target(
    blockid_t target,
    const ctx_t* ctx,
    uint32_t branch_idx,
    uint32_t target_idx
)
{
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

    //fprintf(stderr, "REQUESTING STUB FOR IDX: %d\n", target.idx);

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
    assert (target0.iseq != NULL);
    assert (num_branches < MAX_BRANCHES);
    uint32_t branch_idx = num_branches++;

    // Branch targets or stub adddresses (code pointers)
    uint8_t* dst_addr0;
    uint8_t* dst_addr1;

    // Shape of the branch
    uint8_t branch_shape;

    // If there's only one branch target
    if (target1.iseq == NULL)
    {
        block_t* p_block = find_block_version(target0, ctx0);

        // If the version already exists
        if (p_block)
        {
            add_incoming(p_block, branch_idx);
            dst_addr0 = cb_get_ptr(cb, p_block->start_pos);
            dst_addr1 = NULL;
            branch_shape = SHAPE_DEFAULT;
        }
        else
        {
            // The target block will follow next
            // It will be compiled in gen_block_version()
            dst_addr0 = NULL;
            dst_addr1 = NULL;
            branch_shape = SHAPE_NEXT0;
        }
    }
    else
    {
        // Get the branch targets or stubs
        dst_addr0 = get_branch_target(target0, ctx0, branch_idx, 0);
        dst_addr1 = get_branch_target(target1, ctx1, branch_idx, 1);
        branch_shape = SHAPE_DEFAULT;
    }

    // Call the branch generation function
    uint32_t start_pos = cb->write_pos;
    gen_fn(cb, dst_addr0, dst_addr1, branch_shape);
    uint32_t end_pos = cb->write_pos;

    // Register this branch entry
    branch_t branch_entry = {
        start_pos,
        end_pos,
        *src_ctx,
        { target0, target1 },
        { *ctx0, *ctx1 },
        { dst_addr0, dst_addr1 },
        gen_fn,
        branch_shape
    };

    branch_entries[branch_idx] = branch_entry;
}

// Invalidate one specific block version
void invalidate(block_t* block)
{
    fprintf(stderr, "invalidating block (%p, %d)\n", block->blockid.iseq, block->blockid.idx);

    // Remove the version object from the map so we can re-generate stubs
    st_delete(version_tbl, (st_data_t*)&block->blockid, NULL);

    // Get a pointer to the generated code for this block
    uint8_t* code_ptr = cb_get_ptr(cb, block->start_pos);

    // For each incoming branch
    for (uint32_t i = 0; i < block->num_incoming; ++i)
    {
        uint32_t branch_idx = block->incoming[i];
        branch_t* branch = &branch_entries[branch_idx];
        uint32_t target_idx = (branch->dst_addrs[0] == code_ptr)? 0:1;

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
            // Reset the branch shape
            branch->shape = SHAPE_DEFAULT;
        }

        // Rewrite the branch with the new jump target address
        assert (branch->dst_addrs[0] != NULL);
        assert (branch->dst_addrs[1] != NULL);
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

    //
    // Optional: may want to recompile a new deoptimized entry point
    //

    // TODO:
    // Call continuation addresses on the stack can also be atomically replaced by jumps going to the stub.
    // For now this isn't an issue

    // Free the block version object
    free(block);
}

int blockid_cmp(st_data_t arg0, st_data_t arg1)
{
    const blockid_t *block0 = (const blockid_t*)arg0;
    const blockid_t *block1 = (const blockid_t*)arg1;
    return block0->iseq == block1->iseq && block0->idx == block1->idx;
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
