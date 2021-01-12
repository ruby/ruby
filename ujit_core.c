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

// Retrieve a basic block version for an (iseq, idx) tuple
version_t* find_block_version(blockid_t block, const ctx_t* ctx)
{
    // If there exists a version for this block id
    st_data_t st_version;
    if (rb_st_lookup(version_tbl, (st_data_t)&block, &st_version)) {
        return (version_t*)st_version;
    }

    //
    // TODO: use the ctx parameter to search available versions
    //

    return NULL;
}

// Compile a new block version immediately
version_t* gen_block_version(blockid_t blockid, const ctx_t* ctx)
{
    // Allocate a version object
    version_t* p_version = malloc(sizeof(version_t));
    memcpy(&p_version->blockid, &blockid, sizeof(blockid_t));
    memcpy(&p_version->ctx, ctx, sizeof(ctx_t));

    // Compile the block version
    ctx_t ctx_copy = *ctx;
    uint32_t num_instrs = 0;
    p_version->start_pos = cb->write_pos;
    ujit_compile_block(blockid.iseq, blockid.idx, &ctx_copy, &num_instrs);
    p_version->end_pos = cb->write_pos;

    // Keep track of the new block version
    st_insert(version_tbl, (st_data_t)&p_version->blockid, (st_data_t)p_version);

    return p_version;
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
    version_t* p_version = find_block_version(target, target_ctx);

    // If this block hasn't yet been compiled
    if (!p_version)
    {
        p_version = gen_block_version(target, target_ctx);
    }

    // Update the branch target address
    uint8_t* dst_addr = cb_get_ptr(cb, p_version->start_pos);
    branch->dst_addrs[target_idx] = dst_addr;

    // Rewrite the branch with the new jump target address
    assert (branch->dst_addrs[0] != NULL);
    assert (branch->dst_addrs[1] != NULL);
    uint32_t cur_pos = cb->write_pos;
    cb_set_pos(cb, branch->start_pos);
    branch->gen_fn(cb, branch->dst_addrs[0], branch->dst_addrs[1], branch->shape);
    assert (cb->write_pos <= branch->end_pos);
    cb_set_pos(cb, cur_pos);

    // Return a pointer to the compiled block version
    return dst_addr;
}

// Get a version or stub corresponding to a branch target
// TODO: need incoming and target versioning contexts
uint8_t* get_branch_target(
    blockid_t target,
    const ctx_t* ctx,
    codeblock_t* ocb,
    uint32_t branch_idx,
    uint32_t target_idx
)
{
    version_t* p_version = find_block_version(target, ctx);

    if (p_version)
    {
        return cb_get_ptr(cb, p_version->start_pos);
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
    // Get branch targets or stubs (code pointers)
    uint8_t* dst_addr0 = get_branch_target(target0, ctx0, ocb, num_branches, 0);
    uint8_t* dst_addr1 = get_branch_target(target1, ctx1, ocb, num_branches, 1);

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
        { *ctx0, *ctx1 },
        { dst_addr0, dst_addr1 },
        gen_fn,
        SHAPE_DEFAULT
    };

    assert (num_branches < MAX_BRANCHES);
    branch_entries[num_branches] = branch_entry;
    num_branches++;
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
