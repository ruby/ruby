#ifndef UJIT_COMPILE_H
#define UJIT_COMPILE_H 1

#include "stddef.h"
#include "stdint.h"
#include "stdbool.h"

#ifndef rb_iseq_t
typedef struct rb_iseq_struct rb_iseq_t;
#define rb_iseq_t rb_iseq_t
#endif

void rb_ujit_init(void);
bool rb_ujit_enabled_p(void);
uint8_t* ujit_compile_insn(rb_iseq_t *iseq, unsigned int insn_idx, unsigned int* next_ujit_idx);

#endif
