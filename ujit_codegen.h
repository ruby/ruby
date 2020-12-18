#ifndef UJIT_CODEGEN_H
#define UJIT_CODEGEN_H 1

#include "stddef.h"

// Code blocks we generate code into
codeblock_t* cb;
codeblock_t* ocb;

// Code generation state
typedef struct JITState
{
    // Instruction sequence this is associated with
    const rb_iseq_t *iseq;

    // Index in the iseq of the opcode we are replacing
    uint32_t start_idx;

    // Index of the current instruction being compiled
    uint32_t insn_idx;

    // Current PC
    VALUE *pc;

} jitstate_t;

// Code generation function signature
typedef bool (*codegen_fn)(jitstate_t* jit, ctx_t* ctx);

uint8_t* ujit_compile_entry(const rb_iseq_t *iseq, uint32_t insn_idx);

uint8_t *ujit_compile_block(const rb_iseq_t *iseq, uint32_t insn_idx, uint32_t* num_instrs);

void ujit_init_codegen(void);

#endif // #ifndef UJIT_CODEGEN_H
