#ifndef RUBY_INTERNAL_ENCODING_CODERANGE_H           /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_CODERANGE_H
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
 * @brief      Routines for code ranges.
 */

#include "ruby/internal/attr/const.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/** What rb_enc_str_coderange() returns. */
enum ruby_coderange_type {

    /** The object's coderange is unclear yet. */
    RUBY_ENC_CODERANGE_UNKNOWN  = 0,

    /** The object holds 0 to 127 inclusive and nothing else. */
    RUBY_ENC_CODERANGE_7BIT     = ((int)RUBY_FL_USER8),

    /** The object's encoding and contents are consistent each other */
    RUBY_ENC_CODERANGE_VALID    = ((int)RUBY_FL_USER9),

    /** The object holds invalid/malformed/broken character(s). */
    RUBY_ENC_CODERANGE_BROKEN   = ((int)(RUBY_FL_USER8|RUBY_FL_USER9)),

    /** Where the coderange resides. */
    RUBY_ENC_CODERANGE_MASK     = (RUBY_ENC_CODERANGE_7BIT|
                                   RUBY_ENC_CODERANGE_VALID|
                                   RUBY_ENC_CODERANGE_BROKEN)
};

RBIMPL_ATTR_CONST()
/**
 * @private
 *
 * This is an implementation detail of #RB_ENC_CODERANGE_CLEAN_P.  People don't
 * use it directly.
 *
 * @param[in]  cr  An enum ::ruby_coderange_type.
 * @retval     1   It is.
 * @retval     0   It isn't.
 */
static inline int
rb_enc_coderange_clean_p(int cr)
{
    return (cr ^ (cr >> 1)) & RUBY_ENC_CODERANGE_7BIT;
}

/**
 * Queries if  a code range  is "clean".  "Clean" in  this context means  it is
 * known and valid.
 *
 * @param[in]  cr  An enum ::ruby_coderange_type.
 * @retval     1   It is.
 * @retval     0   It isn't.
 */
#define RB_ENC_CODERANGE_CLEAN_P(cr) rb_enc_coderange_clean_p(cr)

/**
 * Queries the  (inline) code range of  the passed object.  The  object must be
 * capable  of   having  inline   encoding.   Using   this  macro   needs  deep
 * understanding of bit level object binary layout.
 *
 * @param[in]  obj  Target object.
 * @return     An enum ::ruby_coderange_type.
 */
#define RB_ENC_CODERANGE(obj) ((int)RBASIC(obj)->flags & RUBY_ENC_CODERANGE_MASK)

/**
 * Queries   the    (inline)   code   range    of   the   passed    object   is
 * ::RUBY_ENC_CODERANGE_7BIT.   The object  must  be capable  of having  inline
 * encoding.  Using  this macro  needs deep understanding  of bit  level object
 * binary layout.
 *
 * @param[in]  obj  Target object.
 * @retval     1    It is ascii only.
 * @retval     0    Otherwise (including cases when the range is not known).
 */
#define RB_ENC_CODERANGE_ASCIIONLY(obj) (RB_ENC_CODERANGE(obj) == RUBY_ENC_CODERANGE_7BIT)

/**
 * Destructively modifies the passed object so  that its (inline) code range is
 * the  passed one.   The object  must be  capable of  having inline  encoding.
 * Using this macro needs deep understanding of bit level object binary layout.
 *
 * @param[out]  obj  Target object.
 * @param[out]  cr   An enum ::ruby_coderange_type.
 * @post        `obj`'s code range is `cr`.
 */
#define RB_ENC_CODERANGE_SET(obj,cr) (\
        RBASIC(obj)->flags = \
        (RBASIC(obj)->flags & ~RUBY_ENC_CODERANGE_MASK) | (cr))

/**
 * Destructively clears  the passed object's  (inline) code range.   The object
 * must be  capable of  having inline  encoding.  Using  this macro  needs deep
 * understanding of bit level object binary layout.
 *
 * @param[out]  obj  Target object.
 * @post        `obj`'s code range is ::RUBY_ENC_CODERANGE_UNKNOWN.
 */
#define RB_ENC_CODERANGE_CLEAR(obj) RB_ENC_CODERANGE_SET((obj),0)

/* assumed ASCII compatibility */
/**
 * "Mix"  two code  ranges  into one.   This  is handy  for  instance when  you
 * concatenate two  strings into one.   Consider one of  then is valid  but the
 * other isn't.  The result must be  invalid.  This macro computes that kind of
 * mixture.
 *
 * @param[in]  a  An enum ::ruby_coderange_type.
 * @param[in]  b  Another enum ::ruby_coderange_type.
 * @return     The `a` "and" `b`.
 */
#define RB_ENC_CODERANGE_AND(a, b) \
    ((a) == RUBY_ENC_CODERANGE_7BIT ? (b) : \
     (a) != RUBY_ENC_CODERANGE_VALID ? RUBY_ENC_CODERANGE_UNKNOWN : \
     (b) == RUBY_ENC_CODERANGE_7BIT ? RUBY_ENC_CODERANGE_VALID : (b))

/**
 * This is #RB_ENCODING_SET  + RB_ENC_CODERANGE_SET combo.  The  object must be
 * capable  of   having  inline   encoding.   Using   this  macro   needs  deep
 * understanding of bit level object binary layout.
 *
 * @param[out]  obj       Target object.
 * @param[in]   encindex  Encoding in encindex format.
 * @param[in]   cr        An enum ::ruby_coderange_type.
 * @post        `obj`'s encoding is `encindex`.
 * @post        `obj`'s code range is `cr`.
 */
#define RB_ENCODING_CODERANGE_SET(obj, encindex, cr) \
    do { \
        VALUE rb_encoding_coderange_obj = (obj); \
        RB_ENCODING_SET(rb_encoding_coderange_obj, (encindex)); \
        RB_ENC_CODERANGE_SET(rb_encoding_coderange_obj, (cr)); \
    } while (0)

#define ENC_CODERANGE_MASK                        RUBY_ENC_CODERANGE_MASK                      /**< @old{RUBY_ENC_CODERANGE_MASK} */
#define ENC_CODERANGE_UNKNOWN                     RUBY_ENC_CODERANGE_UNKNOWN                   /**< @old{RUBY_ENC_CODERANGE_UNKNOWN} */
#define ENC_CODERANGE_7BIT                        RUBY_ENC_CODERANGE_7BIT                      /**< @old{RUBY_ENC_CODERANGE_7BIT} */
#define ENC_CODERANGE_VALID                       RUBY_ENC_CODERANGE_VALID                     /**< @old{RUBY_ENC_CODERANGE_VALID} */
#define ENC_CODERANGE_BROKEN                      RUBY_ENC_CODERANGE_BROKEN                    /**< @old{RUBY_ENC_CODERANGE_BROKEN} */
#define ENC_CODERANGE_CLEAN_P(cr)                 RB_ENC_CODERANGE_CLEAN_P(cr)                 /**< @old{RB_ENC_CODERANGE_CLEAN_P} */
#define ENC_CODERANGE(obj)                        RB_ENC_CODERANGE(obj)                        /**< @old{RB_ENC_CODERANGE} */
#define ENC_CODERANGE_ASCIIONLY(obj)              RB_ENC_CODERANGE_ASCIIONLY(obj)              /**< @old{RB_ENC_CODERANGE_ASCIIONLY} */
#define ENC_CODERANGE_SET(obj,cr)                 RB_ENC_CODERANGE_SET(obj,cr)                 /**< @old{RB_ENC_CODERANGE_SET} */
#define ENC_CODERANGE_CLEAR(obj)                  RB_ENC_CODERANGE_CLEAR(obj)                  /**< @old{RB_ENC_CODERANGE_CLEAR} */
#define ENC_CODERANGE_AND(a, b)                   RB_ENC_CODERANGE_AND(a, b)                   /**< @old{RB_ENC_CODERANGE_AND} */
#define ENCODING_CODERANGE_SET(obj, encindex, cr) RB_ENCODING_CODERANGE_SET(obj, encindex, cr) /**< @old{RB_ENCODING_CODERANGE_SET} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_CODERANGE_H */
