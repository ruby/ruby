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
 * Does in-place optimization.  This transforms
 *
 *                                           +-- PC
 *                                           v
 *      +------+-----+-----+-----+-----+-----+-----+
 *      | send |  ci |  cc | blk | adj |  m  | ... |
 *      +------+-----+-----+-----+-----+-----+-----+
 *      \-----------len---------/ \----n----/
 *
 *  into:
 *
 *                                          +-- PC
 *                                          v
 *      +-----+-----+-----+-----+-----+-----+-----+
 *      | adj | m+x | nop | nop | nop | nop | ... |
 *      +-----+-----+-----+-----+-----+-----+-----+
 *                (x == send's argc)
 *
 * or, from:
 *
 *     obj.puremethod(arg1, arg2,...)
 *
 * to:
 *
 *     push obj;
 *     push arg1;
 *     push arg2;
 *     push ...;
 *     pop $argc;
 *
 * @param [out] i target iseq struct to squash.
 * @param [in]  p pattern to fill in.
 * @param [in]  n # of words to additionaly wipe out
 * @param [in]  m # of values to additionaly pop from stack
 */
void iseq_eliminate_insn(const struct rb_iseq_struct *restrict i, struct cfp_last_insn *restrict p, int n, rb_num_t m)
    __attribute__((hot))
    __attribute__((nonnull))
    __attribute__((leaf));

/**
 * Swaps nop -> adjuststack sequence into adjuststack -> nop sequence.
 *
 * @param [out] i target iseq struct to swap instructions.
 * @param [in]  j index of nop to swap.
 */
void iseq_move_nop(const struct rb_iseq_struct *restrict i, int j)
    __attribute__((hot))
    __attribute__((nonnull))
    __attribute__((leaf));

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
