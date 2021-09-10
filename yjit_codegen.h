#ifndef YJIT_CODEGEN_H
#define YJIT_CODEGEN_H 1

#include "stddef.h"
#include "yjit_core.h"

// Code blocks we generate code into
extern codeblock_t *cb;
extern codeblock_t *ocb;
extern uint32_t yjit_codepage_frozen_bytes;

// Code generation state
typedef struct JITState
{
    // Block version being compiled
    block_t *block;

    // Instruction sequence this is associated with
    const rb_iseq_t *iseq;

    // Index of the current instruction being compiled
    uint32_t insn_idx;

    // Opcode for the instruction being compiled
    int opcode;

    // PC of the instruction being compiled
    VALUE *pc;

    // Side exit to the instruction being compiled. See :side-exit:.
    uint8_t *side_exit_for_pc;

    // Execution context when compilation started
    // This allows us to peek at run-time values
    rb_execution_context_t *ec;

    // Whether we need to record the code address at
    // the end of this bytecode instruction for global invalidation
    bool record_boundary_patch_point;

} jitstate_t;

typedef enum codegen_status {
    YJIT_END_BLOCK,
    YJIT_KEEP_COMPILING,
    YJIT_CANT_COMPILE
} codegen_status_t;

// Code generation function signature
typedef codegen_status_t (*codegen_fn)(jitstate_t* jit, ctx_t* ctx);

uint8_t* yjit_entry_prologue(const rb_iseq_t* iseq);

void yjit_gen_block(block_t* block, rb_execution_context_t* ec);

void yjit_init_codegen(void);

#endif // #ifndef YJIT_CODEGEN_H
