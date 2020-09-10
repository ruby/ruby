#ifndef UJIT_COMPILE_H
#define UJIT_COMPILE_H 1

#include "stddef.h"
#include "stdint.h"

#ifndef rb_iseq_t
typedef struct rb_iseq_struct rb_iseq_t;
#define rb_iseq_t rb_iseq_t
#endif

uint8_t* ujit_compile_insn(rb_iseq_t* iseq, size_t insn_idx);

#endif
