#ifndef RUBY_OPTIMIZE_H /* comments are in doxygen format, autobrief assumed. */
#define RUBY_OPTIMIZE_H 1

/**
 * ISeq optimization infrastructure, header file.
 *
 * @file      optimize.h
 * @author    Urabe, Shyouhei.
 * @date      Apr. 14th, 2016
 * @copyright Ruby's
 */

#include "ruby/config.h"             /* UNREACHABLE */
#include "iseq.h"                    /* RB_ISEQ_ANNOTATED_P */

struct rb_iseq_struct; // just forward decl.

/**
 * Analyze an iseq  to add annotations.  This only annotates  an ISeq, does not
 * change the sequence in any form by itself.
 *
 * This function is safe to call over and over again.
 *
 * @param [in,out] i iseq struct to analyze.
 */
void iseq_analyze(struct rb_iseq_struct *i)
    __attribute__((nonnull))
    __attribute__((leaf));

/**
 * Check if an iseq is pure i.e.   contains no side-effect.  ISeq purity is the
 * core concept of this optimization infrastructure.
 *
 * @param [in] iseq target iseq.
 * @return Qture, Qfalse, Qnil representing pure, not pure, unpredictable.
 */
static inline VALUE iseq_is_pure(const struct rb_iseq_struct *iseq)
    __attribute__((nonnull));

VALUE
iseq_is_pure(const struct rb_iseq_struct *iseq)
{
    return RB_ISEQ_ANNOTATED_P(iseq, core::purity);
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
#endif /* RUBY_OPTIMIZE_H */
