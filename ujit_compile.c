#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns_info.inc"
#include "ujit_compile.h"
#include "ujit_asm.h"

// NOTE: do we have to deal with multiple Ruby processes/threads compiling
// functions with the new Ractor in Ruby 3.0? If so, we need to think about
// a strategy for handling that. What does Ruby currently do for its own
// iseq translation?
static codeblock_t block;
static codeblock_t* cb = NULL;

extern uint8_t* native_pop_code; // FIXME global hack

// Generate a chunk of machinecode for one individual bytecode instruction
// Eventually, this will handle multiple instructions in a sequence
uint8_t* ujit_compile_insn(rb_iseq_t *iseq, size_t insn_idx)
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

    if (insn == BIN(pop))
    {
        //printf("COMPILING %ld\n", cb->write_pos);

        return native_pop_code;

        /*
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

        return code_ptr;
        */
    }

    return 0;
}
