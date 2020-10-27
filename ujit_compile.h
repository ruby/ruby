#ifndef UJIT_COMPILE_H
#define UJIT_COMPILE_H 1

#include "stddef.h"
#include "stdint.h"
#include "stdbool.h"
#include "method.h"

#ifndef rb_iseq_t
typedef struct rb_iseq_struct rb_iseq_t;
#define rb_iseq_t rb_iseq_t
#endif

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN bool rb_ujit_enabled;
RUBY_SYMBOL_EXPORT_END

static inline
bool rb_ujit_enabled_p(void)
{
    return rb_ujit_enabled;
}

#define UJIT_CALL_THRESHOLD (10u)

void rb_ujit_method_lookup_change(VALUE cme_or_cc);
void rb_ujit_init(void);
uint8_t *ujit_compile_insn(const rb_iseq_t *iseq, unsigned int insn_idx, unsigned int *next_ujit_idx);
void rb_ujit_compile_iseq(const rb_iseq_t *iseq);

#endif
