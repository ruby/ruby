#ifndef YJIT_CODEGEN_H
#define YJIT_CODEGEN_H 1

#include "stddef.h"
#include "yjit_core.h"

// Code blocks we generate code into
extern codeblock_t *cb;
extern codeblock_t *ocb;
extern uint32_t yjit_codepage_frozen_bytes;

typedef enum codegen_status {
    YJIT_END_BLOCK,
    YJIT_KEEP_COMPILING,
    YJIT_CANT_COMPILE
} codegen_status_t;

// Code generation function signature
typedef codegen_status_t (*codegen_fn)(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb);

uint8_t *yjit_entry_prologue(codeblock_t *cb, const rb_iseq_t *iseq);

void yjit_gen_block(block_t *block, rb_execution_context_t *ec);

void yjit_init_codegen(void);

#endif // #ifndef YJIT_CODEGEN_H
