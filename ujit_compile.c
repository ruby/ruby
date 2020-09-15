#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns_info.inc"
#include "ujit_compile.h"
#include "ujit_asm.h"

// TODO: give ujit_examples.h some more meaningful file name
#include "ujit_examples.h"

// Code generation context
typedef struct ctx_struct
{
    // TODO: virtual stack pointer handling

} ctx_t;

// Code generation function
typedef void (*codegen_fn)(codeblock_t* cb, ctx_t* ctx);

// Map from YARV opcodes to code generation functions
static st_table *gen_fns;

// Code block into which we write machine code
static codeblock_t block;
static codeblock_t* cb = NULL;

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

static void ujit_init();

// Ruby instruction entry
static void
ujit_instr_entry(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_pre_call_bytes); ++i)
        cb_write_byte(cb, ujit_pre_call_bytes[i]);
}

// Ruby instruction exit
static void
ujit_instr_exit(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_post_call_bytes); ++i)
        cb_write_byte(cb, ujit_post_call_bytes[i]);
}

// Keep track of mapping from instructions to generated code
// See comment for rb_encoded_insn_data in iseq.c
static void
addr2insn_bookkeeping(void *code_ptr, int insn)
{
    const void * const *table = rb_vm_get_insns_address_table();
    const void * const translated_address = table[insn];
    st_data_t encoded_insn_data;
    if (st_lookup(rb_encoded_insn_data, (st_data_t)translated_address, &encoded_insn_data)) {
        st_insert(rb_encoded_insn_data, (st_data_t)code_ptr, encoded_insn_data);
    }
    else {
        rb_bug("ujit: failed to find info for original instruction while dealing with addr2insn");
    }
}

// Generate a chunk of machine code for one individual bytecode instruction
// Eventually, this will handle multiple instructions in a sequence
//
// MicroJIT code gets a pointer to the cfp as the first argument in RSI
// See rb_ujit_empty_func(rb_control_frame_t *cfp) in iseq.c
uint8_t *
ujit_compile_insn(rb_iseq_t *iseq, size_t insn_idx)
{
    // If not previously done, initialize ujit
    if (!cb)
    {
        ujit_init();
    }

    if (cb->write_pos + 1024 >= cb->mem_size)
    {
        rb_bug("out of executable memory");
    }

    int insn = (int)iseq->body->iseq_encoded[insn_idx];
	int len = insn_len(insn);

    //const char* name = insn_name(insn);
    //printf("%s\n", name);

    // Lookup the codegen function for this instruction
    st_data_t st_gen_fn;
    int found = rb_st_lookup(gen_fns, insn, &st_gen_fn);

    if (!found)
        return 0;

    codegen_fn gen_fn = (codegen_fn)st_gen_fn;

    // Compute the address of the next instruction
    void *next_pc = &iseq->body->iseq_encoded[insn_idx + len];

    // Get a pointer to the current write position in the code block
    uint8_t *code_ptr = &cb->mem_block[cb->write_pos];
    //printf("write pos: %ld\n", cb->write_pos);

    // Write the pre call bytes
    ujit_instr_entry(cb);

    // TODO: create codegen context

    // Call the code generation function
    gen_fn(cb, NULL);

    // Directly return the next PC, which is a constant
    mov(cb, RAX, const_ptr_opnd(next_pc));

    // Write the post call bytes
    ujit_instr_exit(cb);

    addr2insn_bookkeeping(code_ptr, insn);

    return code_ptr;







    /*
    if (insn == BIN(putobject_INT2FIX_0_) || insn == BIN(putobject_INT2FIX_1_))
    {
        // Load current SP into RAX
        mov(cb, RAX, mem_opnd(64, RDI, 8));

        // Write constant at SP
        int cst_val = (insn == BIN(putobject_INT2FIX_0_))? 0:1;
        mov(cb, mem_opnd(64, RAX, 0), imm_opnd(INT2FIX(cst_val)));

        // Load incremented SP into RCX
        lea(cb, RCX, mem_opnd(64, RAX, 8));

        // Write back incremented SP
        mov(cb, mem_opnd(64, RDI, 8), RCX);

        // Directly return the next PC, which is a constant
        mov(cb, RAX, const_ptr_opnd(next_pc));

        // Write the post call bytes
        ujit_instr_exit(cb);

        addr2insn_bookkeeping(code_ptr, insn);

        return code_ptr;
    }
    */

    // TODO: implement putself
    /*
    if (insn == BIN(putself))
    {
    }
    */

    // TODO: implement putobject
    /*
    if (insn == BIN(putobject))
    {
    }
    */

    /*
    if (insn == BIN(getlocal_WC_0))
    {
        //printf("compiling getlocal_WC_0\n");

        // Load current SP from CFP
        mov(cb, RAX, mem_opnd(64, RDI, 8));

        // Load block pointer from CFP
        mov(cb, RDX, mem_opnd(64, RDI, 32));

        // TODO: we may want a macro or helper function to get insn operands
        // Compute the offset from BP to the local
        int32_t opnd0 = (int)iseq->body->iseq_encoded[insn_idx+1];
        const int32_t offs = -8 * opnd0;

        // Load the local from the block
        mov(cb, RCX, mem_opnd(64, RDX, offs));

        // Write the local at SP
        mov(cb, mem_opnd(64, RAX, 0), RCX);

        // Compute address of incremented SP
        lea(cb, RCX, mem_opnd(64, RAX, 8));

        // Write back incremented SP
        mov(cb, mem_opnd(64, RDI, 8), RCX);

        // Directly return the next PC, which is a constant
        mov(cb, RAX, const_ptr_opnd(next_pc));

        // Write the post call bytes
        ujit_instr_exit(cb);

        addr2insn_bookkeeping(code_ptr, insn);
    }
    */
}

void gen_nop(codeblock_t* cb, ctx_t* ctx)
{
}

void gen_pop(codeblock_t* cb, ctx_t* ctx)
{
    // Decrement SP
    sub(cb, mem_opnd(64, RDI, 8), imm_opnd(8));
}

static void ujit_init()
{
    // 4MB ought to be enough for anybody
    cb = &block;
    cb_init(cb, 4000000);

    // Initialize the codegen function table
    gen_fns = rb_st_init_numtable();

    // Map YARV opcodes to the corresponding codegen functions
    st_insert(gen_fns, (st_data_t)BIN(nop), (st_data_t)&gen_nop);
    st_insert(gen_fns, (st_data_t)BIN(pop), (st_data_t)&gen_pop);
}
