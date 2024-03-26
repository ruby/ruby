#ifndef RBIMPL_RARRAY_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RARRAY_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Defines struct ::RArray.
 */
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/maybe_unused.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/gc.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/assert.h"

#if USE_MMTK
#include "ruby/internal/memory.h" // for RB_GC_GUARD
#endif

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an ::RArray.
 * @return  The passed object casted to ::RArray.
 */
#define RARRAY(obj)            RBIMPL_CAST((struct RArray *)(obj))
/** @cond INTERNAL_MACRO */
#define RARRAY_EMBED_FLAG      RARRAY_EMBED_FLAG
#define RARRAY_EMBED_LEN_MASK  RARRAY_EMBED_LEN_MASK
#define RARRAY_EMBED_LEN_MAX   RARRAY_EMBED_LEN_MAX
#define RARRAY_EMBED_LEN_SHIFT RARRAY_EMBED_LEN_SHIFT
/** @endcond */
#define RARRAY_LEN                 rb_array_len                 /**< @alias{rb_array_len} */
#define RARRAY_CONST_PTR           rb_array_const_ptr           /**< @alias{rb_array_const_ptr} */

/** @cond INTERNAL_MACRO */
#if defined(__fcc__) || defined(__fcc_version) || \
    defined(__FCC__) || defined(__FCC_VERSION)
/* workaround for old version of Fujitsu C Compiler (fcc) */
# define FIX_CONST_VALUE_PTR(x) ((const VALUE *)(x))
#else
# define FIX_CONST_VALUE_PTR(x) (x)
#endif

#define RARRAY_EMBED_LEN   RARRAY_EMBED_LEN
#define RARRAY_LENINT      RARRAY_LENINT
#define RARRAY_ASET        RARRAY_ASET
#define RARRAY_PTR         RARRAY_PTR
/** @endcond */

/**
 * @private
 *
 * Bits that you can set to ::RBasic::flags.
 *
 * @warning  These enums are not the only bits we use for arrays.
 *
 * @internal
 *
 * Unlike  strings, flag  usages for  arrays  are scattered  across the  entire
 * source codes.  @shyouhei doesn't know the complete list.  But what is listed
 * here is at least incomplete.
 */
enum ruby_rarray_flags {
    /**
     * This flag  has something to do  with memory footprint.  If  the array is
     * "small"  enough, ruby  tries to  be creative  to abuse  padding bits  of
     * struct  ::RArray  for storing  its  contents.   This flag  denotes  that
     * situation.
     *
     * @warning  This  bit has  to be  considered read-only.   Setting/clearing
     *           this  bit without  corresponding fix  up must  cause immediate
     *           SEGV.    Also,  internal   structures  of   an  array   change
     *           dynamically  and  transparently  throughout of  its  lifetime.
     *           Don't assume it being persistent.
     *
     * @internal
     *
     * 3rd parties must  not be aware that  there even is more than  one way to
     * store array elements.  It was a bad idea to expose this to them.
     */
    RARRAY_EMBED_FLAG      = RUBY_FL_USER1,

    /* RUBY_FL_USER2 is for ELTS_SHARED */

    /**
     * When an array employs embedded strategy (see ::RARRAY_EMBED_FLAG), these
     * bits  are used  to store  the number  of elements  actually filled  into
     * ::RArray::ary.
     *
     * @internal
     *
     * 3rd parties must  not be aware that  there even is more than  one way to
     * store array elements.  It was a bad idea to expose this to them.
     */
    RARRAY_EMBED_LEN_MASK  = RUBY_FL_USER9 | RUBY_FL_USER8 | RUBY_FL_USER7 | RUBY_FL_USER6 |
                                 RUBY_FL_USER5 | RUBY_FL_USER4 | RUBY_FL_USER3
};

/**
 * This is an enum because GDB wants it (rather than a macro).  People need not
 * bother.
 */
enum ruby_rarray_consts {
    /** Where ::RARRAY_EMBED_LEN_MASK resides. */
    RARRAY_EMBED_LEN_SHIFT = RUBY_FL_USHIFT + 3
};

/** Ruby's array. */
struct RArray {

    /** Basic part, including flags and class. */
    struct RBasic basic;

    /** Array's specific fields. */
    union {

        /**
         * Arrays  that  use separated  memory  region  for elements  use  this
         * pattern.
         */
        struct {

            /** Number of elements of the array. */
            long len;

            /** Auxiliary info. */
            union {

                /**
                 * Capacity of `*ptr`.  A continuous  memory region of at least
                 * `capa` elements is expected to exist at `*ptr`.  This can be
                 * bigger than `len`.
                 */
                long capa;

                /**
                 * Parent  of  the  array.   Nowadays arrays  can  share  their
                 * backend  memory regions  each  other, constructing  gigantic
                 * nest  of objects.   This situation  is called  "shared", and
                 * this is the field to control such properties.
                 */
#if defined(__clang__)      /* <- clang++ is sane */ || \
    !defined(__cplusplus)   /* <- C99 is sane */     || \
    (__cplusplus > 199711L) /* <- C++11 is sane */
                const
#endif
                VALUE shared_root;
            } aux;

            /**
             * Pointer to the C array that holds the elements of the array.  In
             * the old days  each array had dedicated memory  regions.  That is
             * no  longer  true today,  but  there  still  are arrays  of  such
             * properties.  This field could be used to point such things.
             */
            const VALUE *ptr;
        } heap;

        /**
         * Embedded elements.  When an array is short enough, it uses this area
         * to store its elements.  In this  case the length is encoded into the
         * flags.
         */
        /* This is a length 1 array because:
         *   1. GCC has a bug that does not optimize C flexible array members
         *      (https://gcc.gnu.org/bugzilla/show_bug.cgi?id=102452)
         *   2. Zero length arrays are not supported by all compilers
         */
        const VALUE ary[1];
    } as;
};

#if USE_MMTK
typedef struct rb_mmtk_arrayext_struct {
    VALUE objbuf; // points to rb_mmtk_objbuf_t in the GC'ed heap
} rb_mmtk_arrayext_t;

#define RARRAY_EXT(s) ((rb_mmtk_arrayext_t *)((char *)(s) + sizeof(struct RArray)))
#endif

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * @private
 *
 * Declares  a  section of  code  where  raw pointers  are  used.   This is  an
 * implementation detail of #RARRAY_PTR_USE.  People don't use it directly.
 *
 * @param[in]  ary  An object of ::RArray.
 * @return     `ary`'s backend C array.
 */
VALUE *rb_ary_ptr_use_start(VALUE ary);

/**
 * @private
 *
 * Declares an  end of  a section  formerly started  by rb_ary_ptr_use_start().
 * This is  an implementation detail  of #RARRAY_PTR_USE.  People don't  use it
 * directly.
 *
 * @param[in]  a  An object of ::RArray.
 */
void rb_ary_ptr_use_end(VALUE a);

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries the length of the array.
 *
 * @param[in]  ary  Array in question.
 * @return     Its number of elements.
 * @pre        `ary`  must  be  an  instance  of ::RArray,  and  must  has  its
 *             ::RARRAY_EMBED_FLAG flag set.
 *
 * @internal
 *
 * This was a macro  before.  It was inevitable to be  public, since macros are
 * global constructs.   But should it be  forever?  Now that it  is a function,
 * @shyouhei thinks  it could  just be  eliminated, hidden  into implementation
 * details.
 */
static inline long
RARRAY_EMBED_LEN(VALUE ary)
{
    RBIMPL_ASSERT_TYPE(ary, RUBY_T_ARRAY);
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ANY_RAW(ary, RARRAY_EMBED_FLAG));

    VALUE f = RBASIC(ary)->flags;
    f &= RARRAY_EMBED_LEN_MASK;
    f >>= RARRAY_EMBED_LEN_SHIFT;
    return RBIMPL_CAST((long)f);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * Queries the length of the array.
 *
 * @param[in]  a  Array in question.
 * @return     Its number of elements.
 * @pre        `a` must be an instance of ::RArray.
 */
static inline long
rb_array_len(VALUE a)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return RARRAY_EMBED_LEN(a);
    }
    else {
        return RARRAY(a)->as.heap.len;
    }
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * Identical to rb_array_len(), except it differs for the return type.
 *
 * @param[in]  ary             Array in question.
 * @exception  rb_eRangeError  Too long.
 * @return     Its number of elements.
 * @pre        `ary` must be an instance of ::RArray.
 *
 * @internal
 *
 * This API seems redundant but has actual usages.
 */
static inline int
RARRAY_LENINT(VALUE ary)
{
    return rb_long2int(RARRAY_LEN(ary));
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * @private
 *
 * This is  an implementation  detail of  RARRAY_PTR().  People  do not  use it
 * directly.
 *
 * @param[in]  a  An object of ::RArray.
 * @return     Its backend storage.
 */
static inline const VALUE *
rb_array_const_ptr(VALUE a)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return FIX_CONST_VALUE_PTR(RARRAY(a)->as.ary);
    }
    else {
        return FIX_CONST_VALUE_PTR(RARRAY(a)->as.heap.ptr);
    }
}

#if USE_MMTK
/**
 * @private
 *
 * Return the object that holds the content of the array.
 * Only relevant when using MMTk.
 * For embedded arrays, it is the array itself;
 * for heap arrays, it is the the underlying imemo:mmtk_objbuf
 *
 * @param[in]  a  An object of ::RArray.
 * @return     The object holding its backend storage.
 */
static inline VALUE
rb_mmtk_array_content_holder(VALUE a)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return a;
    }
    else {
        return RARRAY_EXT(a)->objbuf;
    }
}

void rb_mmtk_remember_array_content_holder(VALUE ary);
#endif

#if USE_MMTK
// Defined in mmtk_support.c
bool rb_mmtk_enabled_p(void);

// When using MMTk, we need to
// 1.  Apply RB_GC_GUARD to the underlying buffer if the array is not embedded
//     becuase the buffer is in the GC heap.  Otherwise, if C calls back to
//     Ruby, and Ruby triggers GC, and GC moves the array buffer, the C
//     function will be operating on the old address of the buffer.
// 2.  Apply write barrier to the actual array content holder if the caller
//     writes to the array.  Currently this is done by the caller.  It's better
//     to find a way to encapsulate the write barrier access in this macro.
#define RBIMPL_RARRAY_STMT(ary, var, expr) do {         \
    RBIMPL_ASSERT_TYPE((ary), RUBY_T_ARRAY);                    \
    const VALUE rbimpl_ary = (ary);                             \
    volatile VALUE rb_mmtk_actual_array_content_holder = 0;     \
    if (rb_mmtk_enabled_p()) {                                  \
        rb_mmtk_actual_array_content_holder = rb_mmtk_array_content_holder(ary); \
    }                                                           \
    VALUE *var = rb_ary_ptr_use_start(rbimpl_ary);              \
    expr;                                                       \
    rb_ary_ptr_use_end(rbimpl_ary);                             \
    RB_GC_GUARD(rb_mmtk_actual_array_content_holder);           \
} while (0)
#else
/**
 * @private
 *
 * This is an  implementation detail of #RARRAY_PTR_USE.  People do  not use it
 * directly.
 */
#define RBIMPL_RARRAY_STMT(ary, var, expr) do {        \
    RBIMPL_ASSERT_TYPE((ary), RUBY_T_ARRAY);                 \
    const VALUE rbimpl_ary = (ary);                          \
    VALUE *var = rb_ary_ptr_use_start(rbimpl_ary); \
    expr;                                                   \
    rb_ary_ptr_use_end(rbimpl_ary);                \
} while (0)
#endif

/**
 * Declares a section of code where raw pointers are used.  In case you need to
 * touch the raw C array instead of  polite CAPIs, then that operation shall be
 * wrapped using this macro.
 *
 * ```CXX
 * const auto ary = rb_eval_string("[...]");
 * const auto len = RARRAY_LENINT(ary);
 * const auto symwrite = rb_intern("write");
 *
 * RARRAY_PTR_USE(ary, ptr, {
 *     rb_funcallv(rb_stdout, symwrite, len, ptr);
 * });
 * ```
 *
 * @param  ary       An object of ::RArray.
 * @param  ptr_name  A variable name which points the C array in `expr`.
 * @param  expr      The expression that touches `ptr_name`.
 *
 * @internal
 *
 * For  historical reasons  use  of  this macro  is  not  enforced.  There  are
 * extension libraries in the wild which call RARRAY_PTR() without it.  We want
 * them use it...  Maybe some transition path can be implemented later.
 */
#define RARRAY_PTR_USE(ary, ptr_name, expr)     \
    RBIMPL_RARRAY_STMT(ary, ptr_name, expr)

/**
 * Wild  use of  a  C  pointer.  This  function  accesses  the backend  storage
 * directly.   This is  slower  than  #RARRAY_PTR_USE.  It  exercises
 * extra manoeuvres  to protect our generational  GC.  Use of this  function is
 * considered archaic.  Use a modern way instead.
 *
 * @param[in]  ary  An object of ::RArray.
 * @return     The backend C array.
 *
 * @internal
 *
 * That said...  there are  extension libraries  in the wild  who uses  it.  We
 * cannot but continue supporting.
 */
static inline VALUE *
RARRAY_PTR(VALUE ary)
{
    RBIMPL_ASSERT_TYPE(ary, RUBY_T_ARRAY);

    VALUE tmp = RB_OBJ_WB_UNPROTECT_FOR(ARRAY, ary);
    return RBIMPL_CAST((VALUE *)RARRAY_CONST_PTR(tmp));
}

/**
 * Assigns an object in an array.
 *
 * @param[out]  ary  Destination array object.
 * @param[in]   i    Index of `ary`.
 * @param[in]   v    Arbitrary ruby object.
 * @pre         `ary` must be an instance of ::RArray.
 * @pre         `ary`'s length must be longer than or equal to `i`.
 * @pre         `i` must be greater than or equal to zero.
 * @post        `ary`'s `i`th element is set to `v`.
 */
static inline void
RARRAY_ASET(VALUE ary, long i, VALUE v)
{
#if USE_MMTK
    if (rb_mmtk_enabled_p()) {
        // When using MMTk, a non-embedded array consists of two heap objects: the array itself and
        // and underlying buffer (imemo:mmtk_objbuf).  The GC considers them as two separate
        // objects.  So when writing to a non-embedded array, we should apply write barrier to the
        // underlying buffer (imemo:mmtk_objbuf) instead of the array itself.
        // We also don't need to use RARRAY_PTR_USE.  It is for keeping a pointer to the ary on the
        // stack so that it will be treated as a pinning root if GC is triggered inside the
        // operation which RARRAY_PTR_USE wraps.  But when using MMTk, write barriers never trigger
        // GC.

        // Determine the source object. Select the objbuf if it is not embedded.
        VALUE src_obj = FL_TEST_RAW(ary, RARRAY_EMBED_FLAG) ? ary : RARRAY_EXT(ary)->objbuf;
        // Apply the (subsuming) write barrier.
        RB_OBJ_WRITE(src_obj, &RARRAY_CONST_PTR(ary)[i], v);
    } else {
#endif
    RARRAY_PTR_USE(ary, ptr,
        RB_OBJ_WRITE(ary, &ptr[i], v));
#if USE_MMTK
    }
#endif
}

/**
 * @deprecated
 *
 * :FIXME: we want to convert RARRAY_AREF into an inline function (to add rooms
 * for more sanity checks).  However there were situations where the address of
 * this macro is taken i.e. &RARRAY_AREF(...).  They cannot be possible if this
 * is not a  macro.  Such usages are abuse, and  we eliminated them internally.
 * However we are afraid  of similar things to remain in  the wild.  This macro
 * remains as  it is due to  that.  If we could  warn such usages we  can set a
 * transition path, but currently no way is found to do so.
 */
#define RARRAY_AREF(a, i) RARRAY_CONST_PTR(a)[i]

#endif /* RBIMPL_RARRAY_H */
