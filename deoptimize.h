#ifndef RUBY_DEOPTIMIZE_H /* comments are in doxygen format, autobrief assumed. */
#define RUBY_DEOPTIMIZE_H 1

/**
 * ISeq deoptimization infrastructure, header file.
 *
 * @file      deoptimize.h
 * @author    Urabe, Shyouhei.
 * @date      Apr. 11th, 2016
 * @copyright Ruby's
 */

#include <stdbool.h>            // bool
#include <stdint.h>             // uintptr_t
#include "internal.h"           // rb_serial_t
#include "vm_core.h"            // iseq_constant_body

/**
 * Main struct to  hold deoptimization infrastructure.  It basically  is a pair
 * of original iseq  and its length.  This struct is  expected to frequently be
 * created then removed, along with the progress of program execution.
 */
struct iseq_to_deoptimize {
    const rb_serial_t created_at;  ///< creation timestamp
    const uintptr_t *restrict ptr; ///< deoptimized raw body
    const unsigned int nelems;     ///< ptr's size, in words
};

struct rb_iseq_struct; // just forward decl

/**
 * Setup iseq to be eligible  for in-place optimization.  In-place optimization
 * here means  a kind of  optimizations such that instruction  sequence neither
 * shrink   nor   grow.    Such    optimization   can   be   done   on-the-fly,
 * instruction-by-instruction, with no need of modifying catch table.
 *
 * Note however, that it does need to update program counter.  This preparation
 * can happen  in a middle of  iseq execution.  Caller should  pass current PC.
 * and let it updated properly to point to the return value.
 *
 * Optimizations themselves happen elsewhere.
 *
 * @param [in,out] i  target iseq struct.
 * @param [in]     t  creation time stamp.
 * @param [in]     pc current program counter.
 * @return updated pc.
 */
void iseq_prepare_to_deoptimize(const struct rb_iseq_struct *restrict i, rb_serial_t t);

/**
 * Deallocates  an  iseq_to_deoptimize  struct.  Further  actions  against  the
 * argument pointer are illegal, can cause fatal failure of any kind.
 *
 * @warning  It  does _not_  deallocate  optimized  pointer because  that  were
 * created before the argument was created.  It does not have their ownership.
 *
 * @param [in] i target struct to free.
 */
void iseq_to_deoptimize_free(const struct iseq_to_deoptimize *i);

/**
 * Calculate memory size of given structure, in bytes.
 *
 * @param [in] i target struct.
 * @return size of the struct.
 */
size_t iseq_to_deoptimize_memsize(const struct iseq_to_deoptimize *i);

/**
 * Does the deoptimization process.
 *
 * @param [out] iseq iseq struct to deoptimize.
 */
void iseq_deoptimize(const struct rb_iseq_struct *restrict iseq)
    __attribute__((hot))
    __attribute__((leaf));

/**
 * Utility inline function.  Because this function resides in a super duper hot
 * path, it is worth providing a fast-escape wrapper for optimal speed.
 *
 * @param [out] iseq iseq struct to deoptimize.
 * @param [in]  now  current timestamp.
 */
static inline void iseq_deoptimize_if_needed(const struct rb_iseq_struct *restrict iseq, rb_serial_t now)
    __attribute__((nonnull));

/**
 * An  iseq _can_  have  original_iseq.   That should  be  properly reset  upon
 * successful optimization/deoptimization transformations.
 *
 * @param [out] iseq target struct.
 */
#define ISEQ_RESET_ORIGINAL_ISEQ(iseq)          \
    RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_ORIGINAL_ISEQ, Qfalse)

/**
 * Optimizations  can introduce  new VALUEs  in an  iseq, for  instance when  a
 * constant is folded.  Such VALUEs become stale on deoptimizations, subject to
 * be reset like the original iseq above.
 *
 * @param [out] iseq target struct.
 */
#define ISEQ_RESET_OPTIMIZED_VALUES(iseq)          \
    RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_OPTIMIZED_VALUES, Qnil)

void
iseq_deoptimize_if_needed(
    const rb_iseq_t *restrict i,
    rb_serial_t t)
{
    if (t != i->body->deoptimize->created_at) {
        iseq_deoptimize(i);
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
#endif
