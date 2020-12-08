#ifndef UJIT_CODEGEN_H
#define UJIT_CODEGEN_H 1

#include "stddef.h"

uint8_t * ujit_compile_insn(const rb_iseq_t *iseq, unsigned int insn_idx, unsigned int *next_ujit_idx);

void ujit_init_codegen(void);

#endif // #ifndef UJIT_CODEGEN_H
