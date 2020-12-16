#ifndef UJIT_CODEGEN_H
#define UJIT_CODEGEN_H 1

#include "stddef.h"

// Code generation function signature
typedef bool (*codegen_fn)(codeblock_t* cb, codeblock_t* ocb, ctx_t* ctx);

uint8_t *ujit_compile_block(const rb_iseq_t *iseq, uint32_t insn_idx, bool gen_entry);

void ujit_init_codegen(void);

#endif // #ifndef UJIT_CODEGEN_H
