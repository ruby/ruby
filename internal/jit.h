#ifndef INTERNAL_JIT_H                                     /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_JIT_H

#include "iseq.h"

typedef void (*rb_iseq_callback)(const rb_iseq_t *, void *);

/* cont.c */
void rb_jit_cont_init(void);
void rb_jit_cont_each_iseq(rb_iseq_callback callback, void *data);
void rb_jit_cont_finish(void);

/* jit.c */
void rb_jit_for_each_iseq(rb_iseq_callback callback, void *data);
uint32_t rb_jit_get_page_size(void);
uint8_t *rb_jit_reserve_addr_space(uint32_t mem_size);

/*
 * Format the `subject` argument of JIT invalidation probes into `buf` and
 * return `buf`. Invalidation runs while the JIT is in the middle of
 * patching code, so these must not allocate on the Ruby heap.
 */
const char *rb_jit_probe_cme_subject(char *buf, size_t size, const rb_callable_method_entry_t *cme);
const char *rb_jit_probe_bop_subject(char *buf, size_t size, int redefined_flag, enum ruby_basic_operators bop);
const char *rb_jit_probe_id_subject(char *buf, size_t size, ID id);
const char *rb_jit_probe_ic_subject(char *buf, size_t size, const struct iseq_inline_constant_cache *ic);
const char *rb_jit_probe_class_subject(char *buf, size_t size, VALUE klass);
const char *rb_jit_probe_iseq_subject(char *buf, size_t size, const rb_iseq_t *iseq);

#define RB_JIT_PROBE_SUBJECT_SIZE 256

/*
 * Fire a JIT invalidation probe declared in probes.d. `subject` is only
 * evaluated when the probe is enabled.
 */
#define RUBY_DTRACE_JIT_INVALIDATE_HOOK(name, subject, count) \
do { \
    if (UNLIKELY(RUBY_DTRACE_##name##_ENABLED())) { \
        int dtrace_line; \
        const char *dtrace_subject = (subject); \
        const char *dtrace_file = rb_source_location_cstr(&dtrace_line); \
        if (!dtrace_subject) dtrace_subject = ""; \
        if (!dtrace_file) dtrace_file = ""; \
        RUBY_DTRACE_##name(dtrace_subject, (long)(count), dtrace_file, dtrace_line); \
    } \
} while (0)

/* vm.c */
RUBY_SYMBOL_EXPORT_BEGIN
unsigned int rb_jit_call_threshold(void);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_JIT_H */
