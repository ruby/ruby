/* comments are in doxygen format, autobrief assumed. */

/**
 * ISeq deoptimization infrastructure, implementation.
 *
 * @file      deoptimize.c
 * @author    Urabe, Shyouhei.
 * @date      Apr. 11th, 2016
 * @copyright Ruby's
 */

#include "ruby/config.h"

#ifndef HAVE_TYPEOF
#error "This  code is intentionally  written  in GCC's  language, to  minimize"
#error "the patch size. Once it's accepted, I can translate this into ANSI C."
#endif

#include <stddef.h>             // size_t
#include <stdint.h>             // uintptr_t
#include "vm_core.h"            // rb_iseq_t
#include "iseq.h"               // ISEQ_ORIGINAL_ISEQ
#include "deoptimize.h"

typedef struct iseq_to_deoptimize target_t;
typedef struct rb_iseq_constant_body body_t;

void
iseq_prepare_to_deoptimize(
    const rb_iseq_t *restrict i,
    rb_serial_t t)
{
    body_t *restrict b = i->body;

    if (b->deoptimize) {
        memcpy((void *)&b->deoptimize->created_at, &t, sizeof(t));
    }
    else {
        const VALUE *restrict x = b->iseq_encoded;
        unsigned int n          = b->iseq_size;
        size_t s                = sizeof(VALUE) * n;
        void *restrict y        = ruby_xmalloc(s);
        target_t *restrict d    = ruby_xmalloc(sizeof(*d));
        target_t buf            = (typeof(buf)) {
            .created_at         = t,
            .ptr                = y,
            .nelems             = n,
        };
        b->deoptimize           = d;
        memcpy(d, &buf, sizeof(buf));
        memcpy(y, x, s);
    }
}

void
iseq_to_deoptimize_free(const target_t *i)
{
    if (UNLIKELY(! i)) {
        return;
    }
    else {
        ruby_xfree((void *)i->ptr);
        ruby_xfree((void *)i);
    }
}

size_t
iseq_to_deoptimize_memsize(const target_t *i)
{
    size_t ret = sizeof(*i);

    if (UNLIKELY(! i)) {
        return 0;
    }
    if (LIKELY(i->ptr)) {
        ret += i->nelems * sizeof(i->ptr[0]);
    }
    return ret;
}

void
iseq_deoptimize(const rb_iseq_t *restrict i)
{
    extern rb_serial_t rb_vm_global_timestamp();
    rb_serial_t const t   = rb_vm_global_timestamp();
    body_t *b             = i->body;
    const target_t *d     = b->deoptimize;
    const uintptr_t *orig = d->ptr;

    memcpy((void *)b->iseq_encoded, orig, b->iseq_size * sizeof(VALUE));
    memcpy((void *)&d->created_at, &t, sizeof(t));
    ISEQ_RESET_ORIGINAL_ISEQ(i);
    FL_SET(i, ISEQ_NEEDS_ANALYZE);
    for (unsigned i = 0; i < b->ci_size; i++) {
        b->cc_entries[i].temperature = 0;
    }
}

/* 
 * Local Variables:
 * mode: C
 * coding: utf-8-unix
 * indent-tabs-mode: nil
 * tab-width: 8
 * fill-column: 79
 * default-justification: full
 * c-file-style: "Ruby"
 * c-doc-comment-style: javadoc
 * End:
 */
