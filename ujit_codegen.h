#ifndef UJIT_CODEGEN_H
#define UJIT_CODEGEN_H 1

#include "stddef.h"
#include "ujit_core.h"

// Code blocks we generate code into
extern codeblock_t *cb;
extern codeblock_t *ocb;

// Code generation state
typedef struct JITState
{
    // Block version being compiled
    block_t* block;

    // Instruction sequence this is associated with
    const rb_iseq_t *iseq;

    // Index of the current instruction being compiled
    uint32_t insn_idx;

    // PC of the instruction being compiled
    VALUE *pc;

    // Execution context when compilation started
    // This allows us to peek at run-time values
    rb_execution_context_t* ec;

} jitstate_t;

typedef enum codegen_status {
    UJIT_END_BLOCK,
    UJIT_KEEP_COMPILING,
    UJIT_CANT_COMPILE
} codegen_status_t;

// Code generation function signature
typedef codegen_status_t (*codegen_fn)(jitstate_t* jit, ctx_t* ctx);

uint8_t* ujit_entry_prologue();

void ujit_gen_block(ctx_t* ctx, block_t* block, rb_execution_context_t* ec);

void ujit_init_codegen(void);

#endif // #ifndef UJIT_CODEGEN_H
