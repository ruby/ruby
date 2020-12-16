#include "internal.h"
#include "ujit_asm.h"
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

// Get the current instruction opcode from the context object
int
ctx_get_opcode(ctx_t *ctx)
{
    return opcode_at_pc(ctx->iseq, ctx->pc);
}

// Get an instruction argument from the context object
VALUE
ctx_get_arg(ctx_t* ctx, size_t arg_idx)
{
    assert (arg_idx + 1 < insn_len(ctx_get_opcode(ctx)));
    return *(ctx->pc + arg_idx + 1);
}

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

// Called by the generated code when a branch stub is executed
// Triggers compilation of branches and code patching
void branch_stub_hit(uint32_t branch_idx, uint32_t target_idx)
{




    // TODO
    //uint8_t* code_ptr = ujit_compile_block(blockid.iseq, blockid.idx, false);
    //st_insert(version_tbl, (st_data_t)&blockid, (st_data_t)code_ptr);






}

// Retrieve a basic block version for an (iseq, idx) tuple
uint8_t* find_block_version(blockid_t block)
{
    // If there exists a version for this block id
    st_data_t st_version;
    if (rb_st_lookup(version_tbl, (st_data_t)&block, &st_version)) {
        return (uint8_t*)st_version;
    }

    return NULL;
}

// Get a version or stub corresponding to a branch target
// TODO: need incoming and target versioning contexts
uint8_t* get_branch_target(codeblock_t* ocb, blockid_t target, uint32_t branch_idx, uint32_t target_idx)
{
    uint8_t* block_code = find_block_version(target);

    if (block_code)
        return block_code;

    uint8_t* stub_addr = cb_get_ptr(ocb, ocb->write_pos);

    // Generate an outlined stub that will call
    // branch_stub_hit(uint32_t branch_idx, uint32_t target_idx)











    return stub_addr;
}

void gen_branch(codeblock_t* cb, codeblock_t* ocb, blockid_t target0, blockid_t target1, branchgen_fn gen_fn)
{
    // Get branch targets or stubs (code pointers)
    uint8_t* target_code0 = get_branch_target(ocb, target0, num_branches, 0);
    uint8_t* target_code1 = get_branch_target(ocb, target1, num_branches, 1);

    uint32_t start_pos = (uint32_t)cb->write_pos;

    // Call the branch generation function
    gen_fn(cb, target_code0, target_code1, DEFAULT);

    uint32_t end_pos = (uint32_t)cb->write_pos;

    // Register this branch entry
    branch_t branch_entry = {
        start_pos,
        end_pos,
        { target0, target1 },
        gen_fn
    };

    assert (num_branches < MAX_BRANCHES);
    branch_entries[num_branches] = branch_entry;
    num_branches++;
}

void
ujit_init_core(void)
{
    // Initialize the version hash table
    version_tbl = st_init_table(&hashtype_blockid);
}
