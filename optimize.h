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
 * @param [in]  k length of moving instruction.
 */
void iseq_move_nop(const struct rb_iseq_struct *restrict i, int j, int k)
    __attribute__((hot))
    __attribute__((nonnull))
    __attribute__((leaf));

/**
 * Folds a constant to a direct access.  This converts
 *
 *                        +--- PC
 *                        v
 *      +-----+-----+-----+-----+-----+-----+-----+-----+
 *      | GIC |  m  |  x  | GET |  y  | SIC |  z  | ... |
 *      +-----+-----+-----+-----+-----+-----+-----+-----+
 *       \------ n ------/ \--------- m ---------/
 *        GIC: getinlinecache
 *        GET: getconst
 *        SIC: setinlinecache
 *
 *  into:
 *                        +--- PC
 *                        v
 *      +-----+-----+-----+-----+-----+-----+-----+-----+
 *      | PUT | val | nop | nop | nop | nop | nop | ... |
 *      +-----+-----+-----+-----+-----+-----+-----+-----+
 *        PUT: putobject
 *
 * @param [out] i target iseq struct to squash.
 * @param [in]  p PC
 * @param [in]  n length to wipe before PC
 * @param [in]  m length to wipe after PC
 */
void iseq_const_fold(const struct rb_iseq_struct *restrict i, const VALUE *pc, int n, long m, VALUE konst)
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
 * Sometimes,  iseq_analyze()  can  find  something  that  can  be  immediately
 * optimized.  This is called on such case.
 *
 * @param [out]  iseq   target iseq.
 */
void iseq_eager_optimize(rb_iseq_t *iseq)
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

/**
 * A local variable can be "write only".  On such situation such write to local
 * variables are no use; subject to elimination.
 *
 * Note however,  that a  binding could  be obtained from  this iseq.   If such
 * thing  happens,  the write-only  constraint  breaks.   This optimization  is
 * subject to deoptimization on such case.
 *
 * @param [in] iseq  target iseq.
 * @param [in] index local variable index.
 * @return if it is write-only or not.
 */
static inline VALUE iseq_local_variable_is_writeonly(const struct rb_iseq_struct *iseq, unsigned long index)
    __attribute__((nonnull));

VALUE
iseq_is_pure(const struct rb_iseq_struct *iseq)
{
    return RB_ISEQ_ANNOTATED_P(iseq, core::purity);
}

VALUE
iseq_local_variable_is_writeonly(
    const struct rb_iseq_struct *iseq,
    unsigned long index)
{
    VALUE v = iseq_is_pure(iseq);

    if (v == Qtrue) {
        v = RB_ISEQ_ANNOTATED_P(iseq, core::writeonly_local_variables);
        if (TYPE(v) == T_ARRAY) {
            return rb_ary_entry(v, index);
        }
    }
    return v;
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
