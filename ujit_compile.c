#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns_info.inc"
#include "ujit_compile.h"
#include "ujit_asm.h"

static codeblock_t block;
static codeblock_t* cb = NULL;

extern st_table *rb_encoded_insn_data;

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

// Generate a chunk of machinecode for one individual bytecode instruction
// Eventually, this will handle multiple instructions in a sequence
uint8_t *
ujit_compile_insn(rb_iseq_t *iseq, size_t insn_idx)
{
    // Allocate the code block if not previously allocated
    if (!cb)
    {
        // 4MB ought to be enough for anybody
        cb = &block;
        cb_init(cb, 4000000);
    }

    int insn = (int)iseq->body->iseq_encoded[insn_idx];

    //const char* name = insn_name(insn);
    //printf("%s\n", name);

    // TODO: encode individual instructions, eg
    // nop, putnil, putobject, putself, pop, dup, getlocal, nilp

    if (insn == BIN(pop))
    {
        // Get a pointer to the current write position in the code block
        uint8_t* code_ptr = &cb->mem_block[cb->write_pos];

        // Write the pre call bytes
        cb_write_prologue(cb);

        sub(cb, mem_opnd(64, RDI, 8), imm_opnd(8)); // decrement SP
        add(cb, RSI, imm_opnd(8));                  // increment PC
        mov(cb, mem_opnd(64, RDI, 0), RSI);         // write new PC to EC object, not necessary for pop bytecode?
        mov(cb, RAX, RSI);                          // return new PC

        // Write the post call bytes
        cb_write_epilogue(cb);

        addr2insn_bookkeeping(code_ptr, insn);

        return code_ptr;
    }

    return 0;
}
