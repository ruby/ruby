#ifndef RUBY_ENCODING_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ENCODING_H 1
/**
 * @file
 * @author     $Author: matz $
 * @date       Thu May 24 11:49:41 JST 2007
 * @copyright  Copyright (C) 2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Encoding relates APIs.
 *
 * These APIs are mainly for  implementing encodings themselves.  Encodings are
 * built on  top of  Ruby's core  CAPIs.  Though not  prohibited, there  can be
 * relatively less rooms for things in  this header file be useful when writing
 * an extension library.
 */
#include "ruby/internal/config.h"
#include <stdarg.h>
#include "ruby/ruby.h"
#include "ruby/oniguruma.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/format.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * @private
 *
 * Bit constants used when embedding encodings into ::RBasic::flags.  Extension
 * libraries must not bother such things.
 */
enum ruby_encoding_consts {

    /** Max possible number of embeddable encodings. */
    RUBY_ENCODING_INLINE_MAX = 127,

    /** Where inline encodings reside. */
    RUBY_ENCODING_SHIFT = (RUBY_FL_USHIFT+10),

    /** Bits we use to store inline encodings. */
    RUBY_ENCODING_MASK = (RUBY_ENCODING_INLINE_MAX<<RUBY_ENCODING_SHIFT
			  /* RUBY_FL_USER10..RUBY_FL_USER16 */),

    /** Max possible length of an encoding name. */
    RUBY_ENCODING_MAXNAMELEN = 42
};

#define ENCODING_INLINE_MAX RUBY_ENCODING_INLINE_MAX /**< @old{RUBY_ENCODING_INLINE_MAX} */
#define ENCODING_SHIFT RUBY_ENCODING_SHIFT           /**< @old{RUBY_ENCODING_SHIFT} */
#define ENCODING_MASK RUBY_ENCODING_MASK             /**< @old{RUBY_ENCODING_SHIFT} */

/**
 * Destructively assigns the passed encoding  to the passed object.  The object
 * must be  capable of  having inline  encoding.  Using  this macro  needs deep
 * understanding of bit level object binary layout.
 *
 * @param[out]  obj  Target object to modify.
 * @param[in]   i    Encoding in encindex format.
 * @post        `obj`'s encoding is `i`.
 */
#define RB_ENCODING_SET_INLINED(obj,i) do {\
    RBASIC(obj)->flags &= ~RUBY_ENCODING_MASK;\
    RBASIC(obj)->flags |= (VALUE)(i) << RUBY_ENCODING_SHIFT;\
} while (0)

/** @alias{rb_enc_set_index} */
#define RB_ENCODING_SET(obj,i) rb_enc_set_index((obj), (i))

/**
 * Queries the  encoding of the  passed object.   The encoding must  be smaller
 * than ::RUBY_ENCODING_INLINE_MAX, which means you have some assumption on the
 * return value.  This means the API is for internal use only.
 *
 * @param[in]  obj  Target object.
 * @return     `obj`'s encoding index.
 */
#define RB_ENCODING_GET_INLINED(obj) \
    (int)((RBASIC(obj)->flags & RUBY_ENCODING_MASK)>>RUBY_ENCODING_SHIFT)

/**
 * @alias{rb_enc_get_index}
 *
 * @internal
 *
 * Implementation wise this is not a verbatim alias of rb_enc_get_index().  But
 * the API is consistent.  Don't bother.
 */
#define RB_ENCODING_GET(obj) \
    (RB_ENCODING_GET_INLINED(obj) != RUBY_ENCODING_INLINE_MAX ? \
     RB_ENCODING_GET_INLINED(obj) : \
     rb_enc_get_index(obj))

/**
 * Queries if  the passed  object is  in ascii 8bit  (== binary)  encoding. The
 * object must  be capable of having  inline encoding.  Using this  macro needs
 * deep understanding of bit level object binary layout.
 *
 * @param[in]  obj  An object to check.
 * @retval     1    It is.
 * @retval     0    It isn't.
 */
#define RB_ENCODING_IS_ASCII8BIT(obj) (RB_ENCODING_GET_INLINED(obj) == 0)

#define ENCODING_SET_INLINED(obj,i) RB_ENCODING_SET_INLINED(obj,i) /**< @old{RB_ENCODING_SET_INLINED} */
#define ENCODING_SET(obj,i) RB_ENCODING_SET(obj,i)                 /**< @old{RB_ENCODING_SET} */
#define ENCODING_GET_INLINED(obj) RB_ENCODING_GET_INLINED(obj)     /**< @old{RB_ENCODING_GET_INLINED} */
#define ENCODING_GET(obj) RB_ENCODING_GET(obj)                     /**< @old{RB_ENCODING_GET} */
#define ENCODING_IS_ASCII8BIT(obj) RB_ENCODING_IS_ASCII8BIT(obj)   /**< @old{RB_ENCODING_IS_ASCII8BIT} */
#define ENCODING_MAXNAMELEN RUBY_ENCODING_MAXNAMELEN               /**< @old{RUBY_ENCODING_MAXNAMELEN} */

/** What rb_enc_str_coderange() returns. */
enum ruby_coderange_type {

    /** The object's coderange is unclear yet. */
    RUBY_ENC_CODERANGE_UNKNOWN	= 0,

    /** The object holds 0 to 127 inclusive and nothing else. */
    RUBY_ENC_CODERANGE_7BIT	= ((int)RUBY_FL_USER8),

    /** The object's encoding and contents are consistent each other */
    RUBY_ENC_CODERANGE_VALID	= ((int)RUBY_FL_USER9),

    /** The object holds invalid/malformed/broken character(s). */
    RUBY_ENC_CODERANGE_BROKEN	= ((int)(RUBY_FL_USER8|RUBY_FL_USER9)),

    /** Where the coderange resides. */
    RUBY_ENC_CODERANGE_MASK	= (RUBY_ENC_CODERANGE_7BIT|
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

/**
 * The  type  of encoding.   Our  design  here  is we  take  Oniguruma/Onigmo's
 * multilingualisation schema as our base data structure.
 */
typedef const OnigEncodingType rb_encoding;

RBIMPL_ATTR_NOALIAS()
/**
 * Converts  a character  option  to its  encoding.  It  only  supports a  very
 * limited set  of Japanese encodings due  to its Japanese origin.   Ruby still
 * has this in-core for backwards compatibility.  But new codes must not bother
 * such  concept like  one-character encoding  option.  Consider  deprecated in
 * practice.
 *
 * @param[in]   c       One of `['n', 'e', 's', 'u', 'i', 'x', 'm']`.
 * @param[out]  option  Return buffer.
 * @param[out]  kcode   Return buffer.
 * @retval      1       `c` understood properly.
 * @retval      0       `c` is not understood.
 * @post        `option` is a ::OnigOptionType.
 * @post        `kcode` is an enum `ruby_preserved_encindex`.
 *
 * @internal
 *
 * `kcode`  is opaque  because  `ruby_preserved_encindex` is  not visible  from
 * extension libraries.  But who cares?
 */
int rb_char_to_option_kcode(int c, int *option, int *kcode);

/**
 * Creates a new encoding, using the passed one as a template.
 *
 * @param[in]  name          Name of the creating encoding.
 * @param[in]  src           Template.
 * @exception  rb_eArgError  Duplicated or malformed `name`.
 * @return     Replicated new encoding's index.
 * @post       Encoding named `name` is created as a copy of `src`, whose index
 *             is the return value.
 *
 * @internal
 *
 * `name` can be `NULL`,  but that just raises an exception.   OTOH it seems no
 * sanity check is done against `src`...?
 */
int rb_enc_replicate(const char *name, rb_encoding *src);

/**
 * Creates a new "dummy" encoding.  Roughly speaking, an encoding is dummy when
 * it is  stateful.  Notable  example of  dummy encoding  are those  defined in
 * ISO/IEC 2022
 *
 * @param[in]  name  Name of the creating encoding.
 * @exception  rb_eArgError  Duplicated or malformed `name`.
 * @return     New dummy encoding's index.
 * @post       Encoding  named `name`  is created,  whose index  is the  return
 *             value.
 */
int rb_define_dummy_encoding(const char *name);

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed encoding is dummy.
 *
 * @param[in]  enc  Encoding in question.
 * @retval     1    It is.
 * @retval     0    It isn't.
 */
int rb_enc_dummy_p(rb_encoding *enc);

RBIMPL_ATTR_PURE()
/**
 * Queries the  index of  the encoding.   An encoding's  index is  a Ruby-local
 * concept.  It is a (sequential) number assigned to each encoding.
 *
 * @param[in]  enc  Encoding in question.
 * @return     Its index.
 * @note       You can pass  null pointers to this function.   It is equivalent
 *             to rb_usascii_encindex() then.
 */
int rb_enc_to_index(rb_encoding *enc);

/**
 * Queries the index of the encoding of the passed object, if any.
 *
 * @param[in]  obj        Object in question.
 * @retval     -1         `obj` is incapable of having an encoding.
 * @retval     otherwise  `obj`'s encoding's index.
 */
int rb_enc_get_index(VALUE obj);

/**
 * Destructively assigns an encoding (via its index) to an object.
 *
 * @param[out]  obj                Object in question.
 * @param[in]   encindex           An encoding index.
 * @exception   rb_eFrozenError    `obj` is frozen.
 * @exception   rb_eArgError       `obj` is incapable of having an encoding.
 * @exception   rb_eEncodingError  `encindex` is out of bounds.
 * @exception   rb_eLoadError      Failed to load the encoding.
 */
void rb_enc_set_index(VALUE obj, int encindex);

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed object can have its encoding.
 *
 * @param[in]  obj  Object in question.
 * @retval     1    It can.
 * @retval     0    It cannot.
 */
int rb_enc_capable(VALUE obj);

/**
 * Queries the index of the encoding.
 *
 * @param[in]  name          Name of the encoding to find.
 * @exception  rb_eArgError  No such encoding named `name`.
 * @retval     -1            `name` exists, but unable to load.
 * @retval     otherwise     Index of encoding named `name`.
 */
int rb_enc_find_index(const char *name);

/**
 * Registers an  "alias" name.  In  the wild, an  encoding can be  called using
 * multiple names.  For instance an encoding  known as `"CP932"` is also called
 * `"SJIS"` on occasions.  This API registers such relationships.
 *
 * @param[in]  alias         New name.
 * @param[in]  orig          Old name.
 * @exception  rb_eArgError  `alias` is duplicated or malformed.
 * @retval     -1            Failed to load `orig`.
 * @retval     otherwise     The index of `orig` and `alias`.
 * @post       `alias` is  a synonym  of `orig`.  They  refer to  the identical
 *             encoding.
 */
int rb_enc_alias(const char *alias, const char *orig);

/**
 * Obtains   a  encoding   index  from   a   wider  range   of  objects   (than
 * rb_enc_find_index()).
 *
 * @param[in]  obj        An ::rb_cEncoding, or its name in ::rb_cString.
 * @retval     -1         `obj` is unexpected type/contents.
 * @retval     otherwise  Index corresponding to `obj`.
 */
int rb_to_encoding_index(VALUE obj);

/**
 * Identical to  rb_find_encoding(), except it  raises an exception  instead of
 * returning NULL.
 *
 * @param[in]  obj            An ::rb_cEncoding, or its name in ::rb_cString.
 * @exception  rb_eTypeError  `obj` is neither ::rb_cEncoding nor ::rb_cString.
 * @exception  rb_eArgError   `obj` is an unknown encoding name.
 * @return     Encoding of `obj`.
 */
rb_encoding *rb_to_encoding(VALUE obj);

/**
 * Identical to rb_to_encoding_index(), except the return type.
 *
 * @param[in]  obj            An ::rb_cEncoding, or its name in ::rb_cString.
 * @exception  rb_eTypeError  `obj` is neither ::rb_cEncoding nor ::rb_cString.
 * @retval     NULL           No such encoding.
 * @return     otherwise      Encoding of `obj`.
 */
rb_encoding *rb_find_encoding(VALUE obj);

/**
 * Identical to rb_enc_get_index(), except the return type.
 *
 * @param[in]  obj        Object in question.
 * @retval     NULL       Obj is incapable of having an encoding.
 * @retval     otherwise  `obj`'s encoding.
 */
rb_encoding *rb_enc_get(VALUE obj);

/**
 * Look for the "common" encoding between the two.  One character can or cannot
 * be expressed depending on an encoding.  This function finds the super-set of
 * encodings that  satisfy contents of  both arguments.  If that  is impossible
 * returns NULL.
 *
 * @param[in]  str1       An object.
 * @param[in]  str2       Another object.
 * @retval     NULL       No encoding can satisfy both at once.
 * @retval     otherwise  Common encoding between the two.
 * @note       Arguments can be non-string, e.g. Regexp.
 */
rb_encoding *rb_enc_compatible(VALUE str1, VALUE str2);

/**
 * Identical to rb_enc_compatible(),  except it raises an  exception instead of
 * returning NULL.
 *
 * @param[in]  str1                An object.
 * @param[in]  str2                Another object.
 * @exception  rb_eEncCompatError  No encoding can satisfy both.
 * @return     Common encoding between the two.
 * @note       Arguments can be non-string, e.g. Regexp.
 */
rb_encoding *rb_enc_check(VALUE str1,VALUE str2);

/**
 * Identical to rb_enc_set_index(), except it additionally does contents fix-up
 * depending on the passed object.  It  for instance changes the byte length of
 * terminating `U+0000` according to the passed encoding.
 *
 * @param[out]  obj                Object in question.
 * @param[in]   encindex           An encoding index.
 * @exception   rb_eFrozenError    `obj` is frozen.
 * @exception   rb_eArgError       `obj` is incapable of having an encoding.
 * @exception   rb_eEncodingError  `encindex` is out of bounds.
 * @exception   rb_eLoadError      Failed to load the encoding.
 * @return      The passed `obj`.
 * @post        `obj`'s contents might be fixed according to `encindex`.
 */
VALUE rb_enc_associate_index(VALUE obj, int encindex);

/**
 * Identical to rb_enc_associate(), except it  takes an encoding itself instead
 * of its index.
 *
 * @param[out]  obj                Object in question.
 * @param[in]   enc                An encoding.
 * @exception   rb_eFrozenError    `obj` is frozen.
 * @exception   rb_eArgError       `obj` is incapable of having an encoding.
 * @return      The passed `obj`.
 * @post        `obj`'s contents might be fixed according to `enc`.
 */
VALUE rb_enc_associate(VALUE obj, rb_encoding *enc);

/**
 * Destructively copies  the encoding of  the latter  object to that  of former
 * one.     It   can    also   be    seen   as    a   routine    identical   to
 * rb_enc_associate_index(), except it takes an object's encoding instead of an
 * encoding's index.
 *
 * @param[out]  dst                Object to modify.
 * @param[in]   src                Object to reference.
 * @exception   rb_eFrozenError    `dst` is frozen.
 * @exception   rb_eArgError       `dst` is incapable of having an encoding.
 * @exception   rb_eEncodingError  `src` is incapable of having an encoding.
 * @post        `dst`'s encoding is that of `src`'s.
 */
void rb_enc_copy(VALUE dst, VALUE src);

/**
 * Identical to rb_enc_str_new(), except it additionally takes an encoding.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @param[in]  enc             Encoding of `ptr`.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An instance  of ::rb_cString,  of `len`  bytes length,  of `enc`
 *             encoding, whose contents are verbatim copy of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 * @note       `enc` can be a  null pointer.  It can also be  seen as a routine
 *             identical to rb_usascii_str_new() then.
 */
VALUE rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to  rb_enc_str_new(), except  it assumes the  passed pointer  is a
 * pointer  to a  C string.  It can  also  be seen  as a  routine identical  to
 * rb_str_new_cstr(), except it additionally takes an encoding.
 *
 * @param[in]  ptr             A C string.
 * @param[in]  enc             Encoding of `ptr`.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString, of `enc`  encoding, whose contents
 *             are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 * @pre        Because `ptr` is  a C string it  makes no sense for  `enc` to be
 *             something like UTF-32.
 * @note       `enc` can be a  null pointer.  It can also be  seen as a routine
 *             identical to rb_usascii_str_new_cstr() then.
 */
VALUE rb_enc_str_new_cstr(const char *ptr, rb_encoding *enc);

/**
 * Identical to rb_enc_str_new(),  except it takes a C string  literal.  It can
 * also  be seen  as  a  routine identical  to  rb_str_new_static(), except  it
 * additionally takes an encoding.
 *
 * @param[in]  ptr           A C string literal.
 * @param[in]  len           `strlen(ptr)`.
 * @param[in]  enc           Encoding of `ptr`.
 * @exception  rb_eArgError  `len` out of range of `size_t`.
 * @pre        `ptr` must be a C string constant.
 * @return     An instance  of ::rb_cString,  of `enc` encoding,  whose backend
 *             storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 * @note       `enc` can be a  null pointer.  It can also be  seen as a routine
 *             identical to rb_usascii_str_new_static() then.
 */
VALUE rb_enc_str_new_static(const char *ptr, long len, rb_encoding *enc);

/**
 * Identical to rb_enc_str_new(),  except it returns a "f"string.   It can also
 * be seen as a routine  identical to rb_interned_str(), except it additionally
 * takes an encoding.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  len           Length  of  `ptr`,  in bytes,  not  including  the
 *                           terminating NUL character.
 * @param[in]  enc           Encoding of `ptr`.
 * @exception  rb_eArgError  `len` is negative.
 * @return     A  found or  created instance  of ::rb_cString,  of `len`  bytes
 *             length, of `enc` encoding, whose  contents are identical to that
 *             of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 * @note       `enc` can be a null  pointer.
 */
VALUE rb_enc_interned_str(const char *ptr, long len, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to rb_enc_str_new_cstr(),  except it returns a  "f"string.  It can
 * also be  seen as  a routine identical  to rb_interned_str_cstr(),  except it
 * additionally takes an encoding.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  enc           Encoding of `ptr`.
 * @return     A found  or created instance  of ::rb_cString of `enc` encoding,
 *             whose contents are identical to that of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 * @note       `enc` can be a null  pointer.
 */
VALUE rb_enc_interned_str_cstr(const char *ptr, rb_encoding *enc);

/**
 * Identical to rb_reg_new(), except it additionally takes an encoding.
 *
 * @param[in]  ptr              A memory region of `len` bytes length.
 * @param[in]  len              Length of  `ptr`, in  bytes, not  including the
 *                              terminating NUL character.
 * @param[in]  enc              Encoding of `ptr`.
 * @param[in]  opts             Options e.g. ONIG_OPTION_MULTILINE.
 * @exception  rb_eRegexpError  Failed to compile `ptr`.
 * @return     An allocated  new instance  of ::rb_cRegexp, of  `enc` encoding,
 *             whose expression is compiled according to `ptr`.
 */
VALUE rb_enc_reg_new(const char *ptr, long len, rb_encoding *enc, int opts);

RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical to  rb_sprintf(), except it  additionally takes an  encoding.  The
 * passed encoding rules  both the incoming format specifier  and the resulting
 * string.
 *
 * @param[in]  enc  Encoding of `fmt`.
 * @param[in]  fmt  A `printf`-like format specifier.
 * @param[in]  ...  Variadic number of contents to format.
 * @return     A rendered new instance of ::rb_cString, of `enc` encoding.
 */
VALUE rb_enc_sprintf(rb_encoding *enc, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 0)
/**
 * Identical  to  rb_enc_sprintf(), except  it  takes  a `va_list`  instead  of
 * variadic  arguments.   It  can  also  be seen  as  a  routine  identical  to
 * rb_vsprintf(), except it additionally takes an encoding.
 *
 * @param[in]  enc  Encoding of `fmt`.
 * @param[in]  fmt  A `printf`-like format specifier.
 * @param[in]  ap   Contents to format.
 * @return     A rendered new instance of ::rb_cString, of `enc` encoding.
 */
VALUE rb_enc_vsprintf(rb_encoding *enc, const char *fmt, va_list ap);

/**
 * Counts  the number  of characters  of the  passed string,  according to  the
 * passed encoding.   This has to be  complicated.  The passed string  could be
 * invalid and/or broken.   This routine would scan from the  beginning til the
 * end, byte by byte, to seek out character boundaries.  Could be super slow.
 *
 * @param[in]  head  Leftmost pointer to the string.
 * @param[in]  tail  Rightmost pointer to the string.
 * @param[in]  enc   Encoding of the string.
 * @return     Number of characters exist in  `head` .. `tail`.  The definition
 *             of "character" depends on the passed `enc`.
 */
long rb_enc_strlen(const char *head, const char *tail, rb_encoding *enc);

/**
 * Queries the n-th character.  Like  rb_enc_strlen() this function can be fast
 * or slow depending on the contents.   Don't expect characters to be uniformly
 * distributed across the entire string.
 *
 * @param[in]  head  Leftmost pointer to the string.
 * @param[in]  tail  Rightmost pointer to the string.
 * @param[in]  nth   Requested index of characters.
 * @param[in]  enc   Encoding of the string.
 * @return     Pointer  to  the first  byte  of  the  character that  is  `nth`
 *             character  ahead  of `head`,  or  `tail`  if  there is  no  such
 *             character (OOB  etc).  The definition of  "character" depends on
 *             the passed `enc`.
 */
char *rb_enc_nth(const char *head, const char *tail, long nth, rb_encoding *enc);

/**
 * Identical to rb_enc_get_index(), except the return type.
 *
 * @param[in]  obj            Object in question.
 * @exception  rb_eTypeError  `obj` is incapable of having an encoding.
 * @return     `obj`'s encoding.
 */
VALUE rb_obj_encoding(VALUE obj);

/**
 * Identical to rb_str_cat(), except it additionally takes an encoding.
 *
 * @param[out]  str                 Destination object.
 * @param[in]   ptr                 Contents to append.
 * @param[in]   len                 Length of `src`, in bytes.
 * @param[in]   enc                 Encoding of `ptr`.
 * @exception   rb_eArgError        `len` is negative.
 * @exception   rb_eEncCompatError  `enc` is not compatible with `str`.
 * @return      The passed `dst`.
 * @post        The  contents  of  `ptr`  is copied,  transcoded  into  `dst`'s
 *              encoding, then pasted into `dst`'s end.
 */
VALUE rb_enc_str_buf_cat(VALUE str, const char *ptr, long len, rb_encoding *enc);

/**
 * Encodes the passed code point into a series of bytes.
 *
 * @param[in]  code             Code point.
 * @param[in]  enc              Target encoding scheme.
 * @exception  rb_eRangeError  `enc` does not glean `code`.
 * @return     An  instance  of ::rb_cString,  of  `enc`  encoding, whose  sole
 *             contents is `code` represented in `enc`.
 * @note       No way to encode code points bigger than UINT_MAX.
 *
 * @internal
 *
 * In  other languages,  APIs like  this  one could  be seen  as the  primitive
 * routines where encodings' "encode" feature are implemented.  However in case
 * of  Ruby this  is not  the primitive  one.  We  directly manipulate  encoded
 * strings.  Encoding conversion routines  transocde an encoded string directly
 * to another one; not via a code point array.
 */
VALUE rb_enc_uint_chr(unsigned int code, rb_encoding *enc);

/**
 * Identical  to   rb_external_str_new(),  except  it  additionally   takes  an
 * encoding.  However the  whole point of rb_external_str_new() is  to encode a
 * string  into default  external encoding.   Being able  to specify  arbitrary
 * encoding just ruins the designed purpose the function meseems.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  len           Length  of  `ptr`,  in bytes,  not  including  the
 *                           terminating NUL character.
 * @param[in]  enc           Target encoding scheme.
 * @exception  rb_eArgError  `len` is negative.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default  internal" to  `enc` is  fully defined  over the  given
 *             contents, then the  return value is a string  of `enc` encoding,
 *             whose contents are the converted  ones.  Otherwise the string is
 *             a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 *
 * @internal
 *
 * @shyouhei has  no idea why  this one does  not follow the  naming convention
 * that  others obey.   It  seems to  him  that this  should  have been  called
 * `rb_enc_external_str_new`.
 */
VALUE rb_external_str_new_with_enc(const char *ptr, long len, rb_encoding *enc);

/**
 * Identical to rb_str_export(), except it additionally takes an encoding.
 *
 * @param[in]  obj            Target object.
 * @param[in]  enc            Target encoding.
 * @exception  rb_eTypeError  No implicit conversion to String.
 * @return     Converted ruby string of `enc` encoding.
 */
VALUE rb_str_export_to_enc(VALUE obj, rb_encoding *enc);

/**
 * Encoding conversion main routine.
 *
 * @param[in]  str   String to convert.
 * @param[in]  from  Source encoding.
 * @param[in]  to    Destination encoding.
 * @return     A copy of `str`, with conversion from `from` to `to` applied.
 * @note       `from` can be a null pointer.  `str`'s encoding is taken then.
 * @note       `to` can be a null pointer.  No-op then.
 */
VALUE rb_str_conv_enc(VALUE str, rb_encoding *from, rb_encoding *to);

/**
 * Identical  to rb_str_conv_enc(),  except  it additionally  takes IO  encoder
 * options.  The extra arguments  can be constructed using io_extract_modeenc()
 * etc.
 *
 * @param[in]  str      String to convert.
 * @param[in]  from     Source encoding.
 * @param[in]  to       Destination encoding.
 * @param[in]  ecflags  A set of enum ::ruby_econv_flag_type.
 * @param[in]  ecopts   Optional hash.
 * @return     A copy of `str`, with conversion from `from` to `to` applied.
 * @note       `from` can be a null pointer.  `str`'s encoding is taken then.
 * @note       `to` can be a null pointer.  No-op then.
 * @note       `ecopts` can be  ::RUBY_Qnil, which is equivalent  to passing an
 *             empty hash.
 */
VALUE rb_str_conv_enc_opts(VALUE str, rb_encoding *from, rb_encoding *to, int ecflags, VALUE ecopts);

/** @cond INTERNAL_MACRO */
#ifdef HAVE_BUILTIN___BUILTIN_CONSTANT_P
#define rb_enc_str_new(str, len, enc) RB_GNUC_EXTENSION_BLOCK( \
    (__builtin_constant_p(str) && __builtin_constant_p(len)) ? \
	rb_enc_str_new_static((str), (len), (enc)) : \
	rb_enc_str_new((str), (len), (enc)) \
)
#define rb_enc_str_new_cstr(str, enc) RB_GNUC_EXTENSION_BLOCK(	\
    (__builtin_constant_p(str)) ?	       \
	rb_enc_str_new_static((str), (long)strlen(str), (enc)) : \
	rb_enc_str_new_cstr((str), (enc)) \
)
#endif
/** @endcond */

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((3))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 3, 4)
/**
 * Identical to rb_raise(), except it additionally takes an encoding.
 *
 * @param[in]  enc  Encoding of the generating exception.
 * @param[in]  exc  A subclass of ::rb_eException.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 * @param[in]  ...  Contents of the message.
 * @exception  exc  The specified exception.
 * @note       It never returns.
 */
void rb_enc_raise(rb_encoding *enc, VALUE exc, const char *fmt, ...);

/**
 * Identical to rb_find_encoding(),  except it takes an  encoding index instead
 * of a Ruby object.
 *
 * @param[in]  idx        An encoding index.
 * @retval     NULL       No such encoding.
 * @retval     otherwise  An encoding whose index is `idx`.
 */
rb_encoding *rb_enc_from_index(int idx);

/**
 * Identical to  rb_find_encoding(), except  it takes a  C's string  instead of
 * Ruby's.
 *
 * @param[in]  name       Name of the encoding to query.
 * @retval     NULL       No such encoding.
 * @retval     otherwise  An encoding whose index is `idx`.
 */
rb_encoding *rb_enc_find(const char *name);

/**
 * Queries the (canonical) name of the passed encoding.
 *
 * @param[in]  enc  An encoding.
 * @return     Its name.
 */
#define rb_enc_name(enc) (enc)->name

/**
 * Queries  the minimum  number  of bytes  that the  passed  encoding needs  to
 * represent a character.  For ASCII and compatible encodings this is typically
 * 1.   There  are  however  encodings  whose   minimum  is  not  1;  they  are
 * historically called wide characters.
 *
 * @param[in]  enc  An encoding.
 * @return     Its least possible number of bytes except 0.
 */
#define rb_enc_mbminlen(enc) (enc)->min_enc_len

/**
 * Queries  the maximum  number  of bytes  that the  passed  encoding needs  to
 * represent a character.   Fixed-width encodings have the same  value for this
 * one  and  #rb_enc_mbminlen.   However there  are  variable-width  encodings.
 * UTF-8, for instance, takes from 1 up to 6 bytes.
 *
 * @param[in]  enc  An encoding.
 * @return     Its maximum possible number of bytes of a character.
 */
#define rb_enc_mbmaxlen(enc) (enc)->max_enc_len

/**
 * Queries the number of bytes of the character at the passed pointer.
 *
 * @param[in]  p    Pointer to a character's first byte.
 * @param[in]  e    End of the string that has `p`.
 * @param[in]  enc  Encoding of the string.
 * @return     If the character at `p` does  not end until `e`, number of bytes
 *             between `p`  and `e`.   Otherwise the number  of bytes  that the
 *             character at `p` is encoded.
 *
 * @internal
 *
 * Strictly speaking there  are chances when `p`  points to a middle  byte of a
 * wide character.   This function  returns "the  number of  bytes from  `p` to
 * nearest of either `e` or the next character boundary", if you go strict.
 */
int rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc);

/**
 * Identical to rb_enc_mbclen() unless the character at `p` overruns `e`.  That
 * can happen  for instance when  you read from a  socket and its  partial read
 * cuts  a  wide  character  in-between.  In  those  situations  this  function
 * "estimates" theoretical length  of the character in  question.  Typically it
 * tends  to be  possible  to know  how  many bytes  a  character needs  before
 * actually reaching its  end; for instance UTF-8 encodes  a character's length
 * in the first byte of it.  This function returns that info.
 *
 * @note  This implies that the string is not broken.
 *
 * @param[in]  p    Pointer to the character's first byte.
 * @param[in]  e    End of the string that has `p`.
 * @param[in]  enc  Encoding of the string.
 * @return     Number of bytes of character at `p`, measured or estimated.
 */
int rb_enc_fast_mbclen(const char *p, const char *e, rb_encoding *enc);

/**
 * Queries the  number of bytes of  the character at the  passed pointer.  This
 * function returns 3 different types of information:
 *
 * ```CXX
 * auto n = rb_enc_precise_mbclen(p, q, r);
 *
 * if (ONIGENC_MBCLEN_CHARFOUND_P(n)) {
 *     // Character found.  Normal return.
 *     auto found_length = ONIGENC_MBCLEN_CHARFOUND_LEN(n);
 * }
 * else if (ONIGENC_MBCLEN_NEEDMORE_P(n)) {
 *     // Character overruns past `q`; needs more.
 *     auto requested_length = ONIGENC_MBCLEN_NEEDMORE_LEN(n);
 * }
 * else {
 *     // `p` is broken.
 *     assert(ONIGENC_MBCLEN_INVALID_P(n));
 * }
 * ```
 *
 * @param[in]  p    Pointer to the character's first byte.
 * @param[in]  e    End of the string that has `p`.
 * @param[in]  enc  Encoding of the string.
 * @return     Encoded read/needed number of bytes (see above).
 */
int rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc);

#define MBCLEN_CHARFOUND_P(ret)   ONIGENC_MBCLEN_CHARFOUND_P(ret)   /**< @old{ONIGENC_MBCLEN_CHARFOUND_P} */
#define MBCLEN_CHARFOUND_LEN(ret) ONIGENC_MBCLEN_CHARFOUND_LEN(ret) /**< @old{ONIGENC_MBCLEN_CHARFOUND_LEN} */
#define MBCLEN_INVALID_P(ret)     ONIGENC_MBCLEN_INVALID_P(ret)     /**< @old{ONIGENC_MBCLEN_INVALID_P} */
#define MBCLEN_NEEDMORE_P(ret)    ONIGENC_MBCLEN_NEEDMORE_P(ret)    /**< @old{ONIGENC_MBCLEN_NEEDMORE_P} */
#define MBCLEN_NEEDMORE_LEN(ret)  ONIGENC_MBCLEN_NEEDMORE_LEN(ret)  /**< @old{ONIGENC_MBCLEN_NEEDMORE_LEN} */

/**
 * Queries the code point of character  pointed by the passed pointer.  If that
 * code point is included in ASCII  that code point is returned.  Otherwise -1.
 * This can be different from just looking  at the first byte.  For instance it
 * reads 2 bytes in case of UTF-16BE.
 *
 * @param[in]  p          Pointer to the character's first byte.
 * @param[in]  e          End of the string that has `p`.
 * @param[in]  len        Return buffer.
 * @param[in]  enc        Encoding of the string.
 * @retval     -1         The character at `p` is not i ASCII.
 * @retval     otherwise  A code point of the character at `p`.
 * @post       `len` (if set) is the number of bytes of `p`.
 */
int rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc);

/**
 * Queries  the  code  point  of  character  pointed  by  the  passed  pointer.
 * Exceptions happen in case of broken input.
 *
 * @param[in]  p             Pointer to the character's first byte.
 * @param[in]  e             End of the string that has `p`.
 * @param[in]  len           Return buffer.
 * @param[in]  enc           Encoding of the string.
 * @exception  rb_eArgError  `p` is broken.
 * @return     Code point of the character pointed by `p`.
 * @post       `len` (if set) is the number of bytes of `p`.
 */
unsigned int rb_enc_codepoint_len(const char *p, const char *e, int *len, rb_encoding *enc);

RBIMPL_ATTR_DEPRECATED(("use rb_enc_codepoint_len instead."))
/**
 * Queries  the  code  point  of  character  pointed  by  the  passed  pointer.
 * Exceptions happen in case of broken input.
 *
 * @deprecated  Use rb_enc_codepoint_len() instead.
 * @param[in]   p             Pointer to the character's first byte.
 * @param[in]   e             End of the string that has `p`.
 * @param[in]   enc           Encoding of the string.
 * @exception   rb_eArgError  `p` is broken.
 * @return      Code point of the character pointed by `p`.
 */
unsigned int rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc);

/** @cond INTERNAL_MACRO */
#define rb_enc_codepoint(p,e,enc) rb_enc_codepoint_len((p),(e),0,(enc))
/** @endcond */

/**
 * Identical to rb_enc_codepoint(),  except it assumes the  passed character is
 * not broken.
 *
 * @param[in]   p    Pointer to the character's first byte.
 * @param[in]   e    End of the string that has `p`.
 * @param[in]   enc  Encoding of the string.
 * @return      Code point of the character pointed by `p`.
 */
#define rb_enc_mbc_to_codepoint(p, e, enc) ONIGENC_MBC_TO_CODE((enc),(UChar*)(p),(UChar*)(e))

/**
 * Queries the  number of bytes  requested to  represent the passed  code point
 * using the passed encoding.
 *
 * @param[in]  code          Code point in question.
 * @param[in]  enc           Encoding to convert the code into a byte sequence.
 * @exception  rb_eArgError  `enc` does not glean `code`.
 * @return     Number of bytes requested to represent `code` using `enc`.
 */
int rb_enc_codelen(int code, rb_encoding *enc);

/**
 * Identical to rb_enc_codelen(), except it returns 0 for invalid code points.
 *
 * @param[in]  code       Code point in question.
 * @param[in]  enc        Encoding to convert the code into a byte sequence.
 * @retval     0          `code` is invalid.
 * @return     otherwise  Number of bytes used for `enc` to encode `code`.
 */
int rb_enc_code_to_mbclen(int code, rb_encoding *enc);

/** @cond INTERNAL_MACRO */
#define rb_enc_code_to_mbclen(c, enc) ONIGENC_CODE_TO_MBCLEN((enc), (c));
/** @endcond */

/**
 * Identical to rb_enc_uint_chr(),  except it writes back to  the passed buffer
 * instead of allocating one.
 *
 * @param[in]   c    Code point.
 * @param[out]  buf  Return buffer.
 * @param[in]   enc  Target encoding scheme.
 * @post        `c` is encoded according to `enc`, then written to `buf`.
 */
#define rb_enc_mbcput(c,buf,enc) ONIGENC_CODE_TO_MBC((enc),(c),(UChar*)(buf))

/**
 * Queries the previous (left) character.
 *
 * @param[in]  s          Start of the string.
 * @param[in]  p          Pointer to a character.
 * @param[in]  e          End of the string.
 * @param[in]  enc        Encoding.
 * @retval     NULL       No previous character.
 * @retval     otherwise  Pointer to the head of the previous character.
 */
#define rb_enc_prev_char(s,p,e,enc) ((char *)onigenc_get_prev_char_head((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e)))

/**
 * Queries the  left boundary of  a character.   This function takes  a pointer
 * that is not necessarily a head of a character, and searches for its head.
 *
 * @param[in]  s          Start of the string.
 * @param[in]  p          Pointer to a possibly-middle of a character.
 * @param[in]  e          End of the string.
 * @param[in]  enc        Encoding.
 * @return     Pointer to the head of the character that contains `p`.
 */
#define rb_enc_left_char_head(s,p,e,enc) ((char *)onigenc_get_left_adjust_char_head((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e)))

/**
 * Queries the  right boundary of a  character.  This function takes  a pointer
 * that is not necessarily a head of a character, and searches for its tail.
 *
 * @param[in]  s    Start of the string.
 * @param[in]  p    Pointer to a possibly-middle of a character.
 * @param[in]  e    End of the string.
 * @param[in]  enc  Encoding.
 * @return     Pointer to the end of the character that contains `p`.
 */
#define rb_enc_right_char_head(s,p,e,enc) ((char *)onigenc_get_right_adjust_char_head((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e)))

/**
 * Scans the string backwards for n characters.
 *
 * @param[in]  s          Start of the string.
 * @param[in]  p          Pointer to a character.
 * @param[in]  e          End of the string.
 * @param[in]  n          Steps.
 * @param[in]  enc        Encoding.
 * @retval     NULL       There are no `n` characters left.
 * @retval     otherwise  Pointer to `n` character before `p`.
 */
#define rb_enc_step_back(s,p,e,n,enc) ((char *)onigenc_step_back((enc),(UChar*)(s),(UChar*)(p),(UChar*)(e),(int)(n)))

/**
 * Queries if  the passed  pointer points  to a newline  character.  What  is a
 * newline and what is not depends on the passed encoding.
 *
 * @param[in]  p          Pointer to a possibly-middle of a character.
 * @param[in]  end        End of the string.
 * @param[in]  enc        Encoding.
 * @retval     0          It isn't.
 * @retval     otherwise  It is.
 */
#define rb_enc_is_newline(p,end,enc)  ONIGENC_IS_MBC_NEWLINE((enc),(UChar*)(p),(UChar*)(end))

/**
 * Queries if the passed  code point is of passed character  type in the passed
 * encoding.  The "character type" here is a set of macros defined in onigmo.h,
 * like `ONIGENC_CTYPE_PUNCT`.
 *
 * @param[in]  c    A code point.
 * @param[in]  t    Type (see above).
 * @param[in]  enc  Encoding.
 * @retval     1    `c` is of `t` in `enc`.
 * @retval     0    Otherwise.
 */
#define rb_enc_isctype(c,t,enc) ONIGENC_IS_CODE_CTYPE((enc),(c),(t))

/**
 * Identical to rb_isascii(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     0    `c` is out of range of ASCII character set in `enc`.
 * @retval     1    Otherwise.
 *
 * @internal
 *
 * `enc` is  ignored.  This  is at least  an intentional  implementation detail
 * (not a bug).  But there could be rooms for future extensions.
 */
#define rb_enc_isascii(c,enc) ONIGENC_IS_CODE_ASCII(c)

/**
 * Identical to rb_isalpha(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "ALPHA".
 * @retval     0    Otherwise.
 */
#define rb_enc_isalpha(c,enc) ONIGENC_IS_CODE_ALPHA((enc),(c))

/**
 * Identical to rb_islower(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "LOWER".
 * @retval     0    Otherwise.
 */
#define rb_enc_islower(c,enc) ONIGENC_IS_CODE_LOWER((enc),(c))

/**
 * Identical to rb_isupper(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "UPPER".
 * @retval     0    Otherwise.
 */
#define rb_enc_isupper(c,enc) ONIGENC_IS_CODE_UPPER((enc),(c))

/**
 * Identical to rb_ispunct(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "PUNCT".
 * @retval     0    Otherwise.
 */
#define rb_enc_ispunct(c,enc) ONIGENC_IS_CODE_PUNCT((enc),(c))

/**
 * Identical to rb_isalnum(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "ANUM".
 * @retval     0    Otherwise.
 */
#define rb_enc_isalnum(c,enc) ONIGENC_IS_CODE_ALNUM((enc),(c))

/**
 * Identical to rb_isprint(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "PRINT".
 * @retval     0    Otherwise.
 */
#define rb_enc_isprint(c,enc) ONIGENC_IS_CODE_PRINT((enc),(c))

/**
 * Identical to rb_isspace(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "PRINT".
 * @retval     0    Otherwise.
 */
#define rb_enc_isspace(c,enc) ONIGENC_IS_CODE_SPACE((enc),(c))

/**
 * Identical to rb_isdigit(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "DIGIT".
 * @retval     0    Otherwise.
 */
#define rb_enc_isdigit(c,enc) ONIGENC_IS_CODE_DIGIT((enc),(c))

/**
 * @private
 *
 * This is an implementation detail  of rb_enc_asciicompat().  People don't use
 * it directly.  Just always use rb_enc_asciicompat().
 *
 * @param[in]  enc  Encoding in question.
 * @retval     1    It is ASCII compatible.
 * @retval     0    It isn't.
 */
static inline int
rb_enc_asciicompat_inline(rb_encoding *enc)
{
    return rb_enc_mbminlen(enc)==1 && !rb_enc_dummy_p(enc);
}

/**
 * Queries if  the passed encoding  is _in  some sense_ compatible  with ASCII.
 * The  concept  of  ASCII  compatibility   is  nuanced,  and  private  to  our
 * implementation.  For instance SJIS is  ASCII compatible to us, despite their
 * having different  characters at code  point `0x5C`.   This is based  on some
 * practical  consideration that  Japanese people  confuses SJIS  to be  "upper
 * compatible" with ASCII (which is in fact  a wrong idea, but we just don't go
 * strict here).  An example of  ASCII incompatible encoding is UTF-16.  UTF-16
 * shares code points  with ASCII, but employs a  completely different encoding
 * scheme.
 *
 * @param[in]  enc  Encoding in question.
 * @retval     0    It is incompatible.
 * @retval     1    It is compatible.
 */
#define rb_enc_asciicompat(enc) rb_enc_asciicompat_inline(enc)

RBIMPL_ATTR_CONST()
/**
 * Identical to rb_toupper(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @return     `c`'s (Ruby's definition of) upper case counterpart.
 *
 * @internal
 *
 * As `RBIMPL_ATTR_CONST` implies this function ignores `enc`.
 */
int rb_enc_toupper(int c, rb_encoding *enc);

RBIMPL_ATTR_CONST()
/**
 * Identical to rb_tolower(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @return     `c`'s (Ruby's definition of) lower case counterpart.
 *
 * @internal
 *
 * As `RBIMPL_ATTR_CONST` implies this function ignores `enc`.
 */
int rb_enc_tolower(int c, rb_encoding *enc);

/**
 * Identical to rb_intern2(), except it additionally takes an encoding.
 *
 * @param[in]  name              The name of the id.
 * @param[in]  len               Length of `name`.
 * @param[in]  enc               `name`'s encoding.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given name.
 * @note       These   days  Ruby   internally   has  two   kinds  of   symbols
 *             (static/dynamic).   Symbols created  using  this function  would
 *             become static ones;  i.e. would never be  garbage collected.  It
 *             is up  to you to avoid  memory leaks.  Think twice  before using
 *             it.
 */
ID rb_intern3(const char *name, long len, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_symname_p(), except it additionally takes an encoding.
 *
 * @param[in]  str  A C string to check.
 * @param[in]  enc  `str`'s encoding.
 * @retval     1    It is a valid symbol name.
 * @retval     0    It is invalid as a symbol name.
 */
int rb_enc_symname_p(const char *str, rb_encoding *enc);

/**
 * Identical  to rb_enc_symname_p(),  except it  additionally takes  the passed
 * string's length.  This  is needed for strings containing NUL  bytes, like in
 * case of UTF-32.
 *
 * @param[in]  name  A C string to check.
 * @param[in]  len   Number of bytes of `str`.
 * @param[in]  enc   `str`'s encoding.
 * @retval     1     It is a valid symbol name.
 * @retval     0     It is invalid as a symbol name.
 */
int rb_enc_symname2_p(const char *name, long len, rb_encoding *enc);

/**
 * Scans the passed string to collect  its code range.  Because a Ruby's string
 * is mutable, its contents  change from time to time; so  does its code range.
 * A  long-lived string  tends  to fall  back to  ::RUBY_ENC_CODERANGE_UNKNOWN.
 * This API scans it and re-assigns a fine-grained code range constant.
 *
 * @param[out]  str  A string.
 * @return      An enum ::ruby_coderange_type.
 */
int rb_enc_str_coderange(VALUE str);

/**
 * Scans the passed string until it finds something odd.  Returns the number of
 * bytes scanned.  As the name implies this is suitable for repeated call.  One
 * of its application is `IO#readlines`.   The method reads from its receiver's
 * read buffer, maybe more than once,  looking for newlines.  But "newline" can
 * be different among encodings.  This API is used to detect broken contents to
 * properly mark them as such.
 *
 * @param[in]   str  String to scan.
 * @param[in]   end  End of `str`.
 * @param[in]   enc  `str`'s encoding.
 * @param[out]  cr   Return buffer.
 * @return      Distance between `str` and first such byte where broken.
 * @post        `cr` has the code range type.
 */
long rb_str_coderange_scan_restartable(const char *str, const char *end, rb_encoding *enc, int *cr);

/**
 * Queries if  the passed string  is "ASCII only".  An  ASCII only string  is a
 * string  who doesn't  have any  non-ASCII  characters at  all.  This  doesn't
 * necessarily mean the string is in  ASCII encoding.  For instance a String of
 * CP932 encoding can quite much be ASCII only, depending on its contents.
 *
 * @param[in]  str  String in question.
 * @retval     1    It doesn't have non-ASCII characters.
 * @retval     0    It has characters that are out of ASCII.
 */
int rb_enc_str_asciionly_p(VALUE str);

/**
 * Queries if the passed string is in an ASCII-compatible encoding.
 *
 * @param[in]  str  A Ruby's string to query.
 * @retval     0    `str` is not a String, or an ASCII-incompatible string.
 * @retval     1    Otherwise.
 */
#define rb_enc_str_asciicompat_p(str) rb_enc_asciicompat(rb_enc_get(str))

/**
 * Queries  the   Ruby-level  counterpart   instance  of   ::rb_cEncoding  that
 * corresponds to the passed encoding.
 *
 * @param[in]  enc  An encoding
 * @retval     RUBY_Qnil  `enc` is a null pointer.
 * @retval     otherwise  An instance of ::rb_cEncoding.
 */
VALUE rb_enc_from_encoding(rb_encoding *enc);

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed encoding is either one of UTF-8/16/32.
 *
 * @note  It does not take UTF-7, which we actually support, into account.
 *
 * @param[in]  enc        Encoding in question.
 * @retval     0          It is not a Unicode variant.
 * @retval     otherwise  It is.
 *
 * @internal
 *
 * In   reality   it   returns   1/0,   but  the   value   is   abstracted   as
 * `ONIGENC_FLAG_UNICODE`.
 */
int rb_enc_unicode_p(rb_encoding *enc);

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the encoding that represents ASCII-8BIT a.k.a. binary.
 *
 * @return  The encoding that represents ASCII-8BIT.
 *
 * @internal
 *
 * This can not return NULL once the process properly boots up.
 */
rb_encoding *rb_ascii8bit_encoding(void);

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the encoding that represents UTF-8.
 *
 * @return  The encoding that represents UTF-8.
 *
 * @internal
 *
 * This can not return NULL once the process properly boots up.
 */
rb_encoding *rb_utf8_encoding(void);

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the encoding that represents US-ASCII.
 *
 * @return  The encoding that represents US-ASCII.
 *
 * @internal
 *
 * This can not return NULL once the process properly boots up.
 */
rb_encoding *rb_usascii_encoding(void);

/**
 * Queries the encoding that represents the current locale.
 *
 * @return  The encoding that represents the process' locale.
 *
 * @internal
 *
 * This  is dynamic.   If  you  change the  process'  locale  by e.g.   calling
 * `setlocale(3)`, that should also change the return value of this function.
 *
 * There is no official way for Ruby scripts to manipulate locales, though.
 */
rb_encoding *rb_locale_encoding(void);

/**
 * Queries the "filesystem"  encoding.  This is the encoding  that ruby expects
 * info from  the OS'  file system  are in.  This  affects for  instance return
 * value of rb_dir_getwd().  Most  notably on Windows it can be  an alias of OS
 * codepage.  Most  notably on Linux  users can  set this via  default external
 * encoding.
 *
 * @return  The "filesystem" encoding.
 */
rb_encoding *rb_filesystem_encoding(void);

/**
 * Queries  the "default  external" encoding.   This is  used to  interact with
 * outer-process things such as File.  Though not recommended, you can set this
 * using rb_enc_set_default_external().
 *
 * @return  The "default external"  encoding.
 */
rb_encoding *rb_default_external_encoding(void);

/**
 * Queries  the "default  internal" encoding.   This could  be a  null pointer.
 * Otherwise, outer-process info are  transcoded from default external encoding
 * to this one during reading from an IO.
 *
 * @return  The "default internal"  encoding (if any).
 */
rb_encoding *rb_default_internal_encoding(void);

#ifndef rb_ascii8bit_encindex
RBIMPL_ATTR_CONST()
/**
 * Identical to rb_ascii8bit_encoding(), except it returns the encoding's index
 * instead of the encoding itself.
 *
 * @return  The index of encoding of ASCII-8BIT.
 *
 * @internal
 *
 * This happens to be 0.
 */
int rb_ascii8bit_encindex(void);
#endif

#ifndef rb_utf8_encindex
RBIMPL_ATTR_CONST()
/**
 * Identical  to rb_utf8_encoding(),  except  it returns  the encoding's  index
 * instead of the encoding itself.
 *
 * @return  The index of encoding of UTF-8.
 */
int rb_utf8_encindex(void);
#endif

#ifndef rb_usascii_encindex
RBIMPL_ATTR_CONST()
/**
 * Identical to  rb_usascii_encoding(), except it returns  the encoding's index
 * instead of the encoding itself.
 *
 * @return  The index of encoding of UTF-8.
 */
int rb_usascii_encindex(void);
#endif

/**
 * Identical to  rb_locale_encoding(), except  it returns the  encoding's index
 * instead of the encoding itself.
 *
 * @return  The index of the locale encoding.
 */
int rb_locale_encindex(void);

/**
 * Identical  to rb_filesystem_encoding(),  except  it  returns the  encoding's
 * index instead of the encoding itself.
 *
 * @return  The index of the filesystem encoding.
 */
int rb_filesystem_encindex(void);

/**
 * Identical   to  rb_default_external_encoding(),   except   it  returns   the
 * Ruby-level counterpart  instance of  ::rb_cEncoding that corresponds  to the
 * default external encoding.
 *
 * @return  An instance of ::rb_cEncoding of default external.
 */
VALUE rb_enc_default_external(void);

/**
 * Identical   to  rb_default_internal_encoding(),   except   it  returns   the
 * Ruby-level counterpart  instance of  ::rb_cEncoding that corresponds  to the
 * default internal encoding.
 *
 * @return  An instance of ::rb_cEncoding of default internal.
 */
VALUE rb_enc_default_internal(void);

/**
 * Destructively assigns the passed encoding  as the default external encoding.
 * You should not  use this API.  It has process-global  side effects.  Also it
 * doesn't change encodings of strings that have already been read.
 *
 * @param[in]  encoding      Ruby level encoding.
 * @exception  rb_eArgError  `encoding` is ::RUBY_Qnil.
 * @post       The default external encoding is `encoding`.
 */
void rb_enc_set_default_external(VALUE encoding);

/**
 * Destructively assigns the passed encoding  as the default internal encoding.
 * You should not  use this API.  It has process-global  side effects.  Also it
 * doesn't change encodings of strings that have already been read.
 *
 * @param[in]  encoding      Ruby level encoding.
 * @post       The default internal encoding is `encoding`.
 * @note       Unlike rb_enc_set_default_external() you can pass ::RUBY_Qnil.
 */
void rb_enc_set_default_internal(VALUE encoding);

/**
 * Returns  a   platform-depended  "charmap"  of  the   current  locale.   This
 * information  is  called   a  "Codeset  name"  in  IEEE   1003.1  section  13
 * (`<langinfo.h>`).  This is a very low-level  API.  The return value can have
 * no corresponding encoding when passed to rb_find_encoding().
 *
 * @param[in]  klass  Ignored for no reason (why...)
 * @return     The low-level locale charmap, in Ruby's String.
 */
VALUE rb_locale_charmap(VALUE klass);

RBIMPL_ATTR_NONNULL(())
/**
 * Looks for the passed string in the passed buffer.
 *
 * @param[in]  x          Buffer that potentially includes `y`.
 * @param[in]  m          Number of bytes of `x`.
 * @param[in]  y          Query string.
 * @param[in]  n          Number of bytes of `y`.
 * @param[in]  enc        Encoding of both `x` and `y`.
 * @retval     -1         Not found.
 * @retval     otherwise  Found index in `x`.
 * @note       This API can match at a non-character-boundary.
 */
long rb_memsearch(const void *x, long m, const void *y, long n, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Returns a path component directly adjacent to the passed pointer.
 *
 * ```
 * "/multi/byte/encoded/pathname.txt"
 *         ^    ^                   ^
 *         |    |                   +--- end
 *         |    +--- @return
 *         +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A pointer  in the  passed string where  the next  path component
 *             resides, or `end` if there is no next path component.
 */
char *rb_enc_path_next(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Seeks for non-prefix  part of a pathname.   This can be a no-op  when the OS
 * has no  such concept  like a  path prefix.   But there  are OSes  where path
 * prefixes do exist.
 *
 * ```
 * "C:\multi\byte\encoded\pathname.txt"
 *  ^ ^                               ^
 *  | |                               +--- end
 *  | +--- @return
 *  +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A pointer in the passed  string where non-prefix part starts, or
 *             `path` if the OS does not have path prefix.
 */
char *rb_enc_path_skip_prefix(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Returns the last path component.
 *
 * ```
 * "/multi/byte/encoded/pathname.txt"
 *        ^             ^           ^
 *        |             |           +--- end
 *        |             +--- @return
 *        +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A pointer  in the  passed string where  the last  path component
 *             resides, or `end` if there is no more path component.
 */
char *rb_enc_path_last_separator(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * This just returns the passed end basically.  It makes difference in case the
 * passed string ends with tons of path separators like the following:
 *
 * ```
 * "/path/that/ends/with/lots/of/slashes//////////////"
 *  ^                                   ^             ^
 *  |                                   |             +--- end
 *  |                                   +--- @return
 *  +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A  pointer  in  the  passed   string  where  the  trailing  path
 *             separators  start,  or  `end`  if  there  is  no  trailing  path
 *             separators.
 *
 * @internal
 *
 * It  seems this  function  was  introduced to  mimic  what  POSIX says  about
 * `basename(3)`.
 */
char *rb_enc_path_end(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1, 4))
/**
 * Our own  encoding-aware version  of `basename(3)`.  Normally,  this function
 * returns the  last path  component of  the given name.   However in  case the
 * passed  name  ends  with a  path  separator,  it  returns  the name  of  the
 * directory, not  the last (empty)  component.  Also if  the passed name  is a
 * root directory, it  returns that root directory.  Note  however that Windows
 * filesystem have drive letters, which this function does not return.
 *
 * @param[in]      name     Target path.
 * @param[out]     baselen  Return buffer.
 * @param[in,out]  alllen   Number of bytes of `name`.
 * @param[enc]     enc      Encoding of `name`.
 * @return         The rightmost component of `name`.
 * @post           `baselen`, if passed,  is updated to be the  number of bytes
 *                 of the returned basename.
 * @post           `alllen`, if passed, is updated to be the number of bytes of
 *                 strings not considered as the basename.
 */
const char *ruby_enc_find_basename(const char *name, long *baselen, long *alllen, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1, 3))
/**
 * Our own  encoding-aware version of  `extname`.  This function  first applies
 * rb_enc_path_last_separator() to the passed name and only concerns its return
 * value (ignores  any parent directories).  This  function returns complicated
 * results:
 *
 * ```CXX
 * auto path = "...";
 * auto len = strlen(path);
 * auto ret = ruby_enc_find_extname(path, &len, rb_ascii8bit_encoding());
 *
 * switch(len) {
 * case 0:
 *     if (ret == 0) {
 *         // `path` is a file without extensions.
 *     }
 *     else {
 *         // `path` is a dotfile.
 *         // `ret` is the file's name.
 *     }
 *     break;
 *
 * case 1:
 *     // `path` _ends_ with a dot.
 *     // `ret` is that dot.
 *     break;
 *
 * default:
 *     // `path` has an extension.
 *     // `ret` is that extension.
 * }
 * ```
 *
 * @param[in]      name  Target path.
 * @param[in,out]  len   Number of bytes of `name`.
 * @param[in]      enc   Encoding of `name`.
 * @return         See above.
 * @post           `len`, if passed, is updated (see above).
 */
const char *ruby_enc_find_extname(const char *name, long *len, rb_encoding *enc);

/**
 * Identical to  rb_check_id(), except it  takes a  pointer to a  memory region
 * instead of Ruby's string.
 *
 * @param[in]  ptr                A pointer to a memory region.
 * @param[in]  len                Number of bytes of `ptr`.
 * @param[in]  enc                Encoding of `ptr`.
 * @exception  rb_eEncodingError  `ptr` contains non-ASCII according to `enc`.
 * @retval     0                  No such id ever existed in the history.
 * @retval     otherwise          The id that represents the given name.
 */
ID rb_check_id_cstr(const char *ptr, long len, rb_encoding *enc);

/**
 * Identical to rb_check_id_cstr(), except for the return type.  It can also be
 * seen as a routine identical to  rb_check_symbol(), except it takes a pointer
 * to a memory region instead of Ruby's string.
 *
 * @param[in]  ptr                A pointer to a memory region.
 * @param[in]  len                Number of bytes of `ptr`.
 * @param[in]  enc                Encoding of `ptr`.
 * @exception  rb_eEncodingError  `ptr` contains non-ASCII according to `enc`.
 * @retval     RUBY_Qnil          No such id ever existed in the history.
 * @retval     otherwise          The id that represents the given name.
 */
VALUE rb_check_symbol_cstr(const char *ptr, long len, rb_encoding *enc);

/**
 * `Encoding` class.
 *
 * @ingroup object
 */
RUBY_EXTERN VALUE rb_cEncoding;

/* econv stuff */

/** return value of rb_econv_convert() */
typedef enum {

    /**
     * The conversion stopped when it found an invalid sequence.
     */
    econv_invalid_byte_sequence,

    /**
     * The conversion  stopped when  it found  a character  in the  input which
     * cannot be representable in the output.
     */
    econv_undefined_conversion,

    /**
     * The conversion stopped because there is no destination.
     */
    econv_destination_buffer_full,

    /**
     * The conversion stopped because there is no input.
     */
    econv_source_buffer_empty,

    /**
     * The conversion  stopped after  converting everything.  This  is arguably
     * the expected normal end of conversion.
     */
    econv_finished,

    /**
     * The  conversion stopped  after  writing something  to somewhere,  before
     * reading everything.
     */
    econv_after_output,

    /**
     * The conversion stopped in middle of reading a character, possibly due to
     * a partial read of a socket etc.
     */
    econv_incomplete_input
} rb_econv_result_t;

/** An opaque struct that represents a lowest level of encoding conversion. */
typedef struct rb_econv_t rb_econv_t;

/**
 * Converts the contents  of the passed string from its  encoding to the passed
 * one.
 *
 * @param[in]  str                           Target string.
 * @param[in]  to                            Destination encoding.
 * @param[in]  ecflags                       A        set        of        enum
 *                                           ::ruby_econv_flag_type.
 * @param[in]  ecopts                        A      keyword     hash,      like
 *                                           ::rb_io_t::rb_io_enc_t::ecopts.
 * @exception  rb_eArgError                  Not fully converted.
 * @exception  rb_eInvalidByteSequenceError  `str` is malformed.
 * @exception  rb_eUndefinedConversionError  `str`   has    a   character   not
 *                                           representable using `to`.
 * @exception  rb_eConversionNotFoundError   There is no  known conversion from
 *                                           `str`'s encoding to `to`.
 * @return     A string whose encoding is `to`, and whose contents is converted
 *             contents of `str`.
 * @note       Use rb_econv_prepare_options() to generate `ecopts`.
 */
VALUE rb_str_encode(VALUE str, VALUE to, int ecflags, VALUE ecopts);

/**
 * Queries if  there is  more than one  way to convert  between the  passed two
 * encodings.  Encoding  conversion are  has_and_belongs_to_many relationships.
 * There could be no direct conversion defined for the passed pair.  Ruby tries
 * to find  an indirect  way to  do so  then.  For  instance ISO-8859-1  has no
 * direct  conversion  to  ISO-2022-JP.   But  there  is  ISO-8859-1  to  UTF-8
 * conversion; then there is UTF-8 to  EUC-JP conversion; finally there also is
 * EUC-JP to ISO-2022-JP  conversion.  So in short ISO-8859-1  can be converted
 * to ISO-2022-JP using that path.   This function returns true.  Obviously not
 * everything that can be represented using UTF-8 can also be represented using
 * EUC-JP.  Conversions in practice can fail depending on the actual input, and
 * that renders exceptions in case of rb_str_encode().
 *
 * @param[in] from_encoding  One encoding.
 * @param[in] to_encoding    Another encoding.
 * @retval    0              No way to convert the two.
 * @retval    1              At least one way to convert the two.
 *
 * @internal
 *
 * Practically @shyouhei knows no way for  this function to return 0.  It seems
 * everything  can  eventually  be  converted  to/from  UTF-8,  which  connects
 * everything.
 */
int rb_econv_has_convpath_p(const char* from_encoding, const char* to_encoding);

/**
 * Identical  to  rb_econv_prepare_opts(),  except it  additionally  takes  the
 * initial  value of  flags.  The  extra bits  are bitwise-ORed  to the  return
 * value.
 *
 * @param[in]   opthash       Keyword arguments.
 * @param[out]  ecopts        Return buffer.
 * @param[in]   ecflags       Default set of enum ::ruby_econv_flag_type.
 * @exception   rb_eArgError  Unknown/Broken values passed.
 * @return      Calculated set of enum ::ruby_econv_flag_type.
 * @post        `ecopts`     holds    a     hash     object    suitable     for
 *              ::rb_io_t::rb_io_enc_t::ecopts.
 */
int rb_econv_prepare_options(VALUE opthash, VALUE *ecopts, int ecflags);

/**
 * Splits a  keyword arguments  hash (that  for instance  `String#encode` took)
 * into a  set of  enum ::ruby_econv_flag_type and  a hash  storing replacement
 * characters etc.
 *
 * @param[in]   opthash       Keyword arguments.
 * @param[out]  ecopts        Return buffer.
 * @exception   rb_eArgError  Unknown/Broken values passed.
 * @return      Calculated set of enum ::ruby_econv_flag_type.
 * @post        `ecopts`     holds    a     hash     object    suitable     for
 *              ::rb_io_t::rb_io_enc_t::ecopts.
 */
int rb_econv_prepare_opts(VALUE opthash, VALUE *ecopts);

/**
 * Creates a new instance of struct ::rb_econv_t.
 *
 * @param[in]  source_encoding       Name of an encoding.
 * @param[in]  destination_encoding  Name of another encoding.
 * @param[in]  ecflags               A set of enum ::ruby_econv_flag_type.
 * @exception  rb_eArgError          No such encoding.
 * @retval     NULL                  Failed to create a struct ::rb_econv_t.
 * @retval     otherwise             Allocated struct ::rb_econv_t.
 * @warning    Return value must be passed to rb_econv_close() exactly once.
 */
rb_econv_t *rb_econv_open(const char *source_encoding, const char *destination_encoding, int ecflags);

/**
 * Identical  to  rb_econv_open(),  except  it additionally  takes  a  hash  of
 * optional strings.
 *
 *
 * @param[in]  source_encoding       Name of an encoding.
 * @param[in]  destination_encoding  Name of another encoding.
 * @param[in]  ecflags               A set of enum ::ruby_econv_flag_type.
 * @param[in]  ecopts                Optional set of strings.
 * @exception  rb_eArgError          No such encoding.
 * @retval     NULL                  Failed to create a struct ::rb_econv_t.
 * @retval     otherwise             Allocated struct ::rb_econv_t.
 * @warning    Return value must be passed to rb_econv_close() exactly once.
 */
rb_econv_t *rb_econv_open_opts(const char *source_encoding, const char *destination_encoding, int ecflags, VALUE ecopts);

/**
 * Converts a string from an encoding to another.
 *
 * Possible  flags  are  either ::RUBY_ECONV_PARTIAL_INPUT  (means  the  source
 * buffer is a  part of much larger  one), ::RUBY_ECONV_AFTER_OUTPUT (instructs
 * the converter to stop after output before input), or both of them.
 *
 * @param[in,out]  ec                      Conversion specification/state etc.
 * @param[in]      source_buffer_ptr       Target string.
 * @param[in]      source_buffer_end       End of target string.
 * @param[out]     destination_buffer_ptr  Return buffer.
 * @param[out]     destination_buffer_end  End of return buffer.
 * @param[in]      flags                   Flags (see above).
 * @return         The status of the conversion.
 * @post           `destination_buffer_ptr` holds conversion results.
 */
rb_econv_result_t rb_econv_convert(rb_econv_t *ec,
    const unsigned char **source_buffer_ptr, const unsigned char *source_buffer_end,
    unsigned char **destination_buffer_ptr, unsigned char *destination_buffer_end,
    int flags);

/**
 * Destructs a converter.  Note that a converter  can have a buffer, and can be
 * non-empty.  Calling this would lose your data then.
 *
 * @param[out]  ec The converter to destroy.
 * @post        `ec` is no longer a valid pointer.
 */
void rb_econv_close(rb_econv_t *ec);

/**
 * Assigns  the replacement  string.  The  string passed  here would  appear in
 * converted string when it cannot  represent its source counterpart.  This can
 * happen for instance you convert an emoji to ISO-8859-1.
 *
 * @param[out]  ec       Target converter.
 * @param[in]   str      Replacement string.
 * @param[in]   len      Number of bytes of `str`.
 * @param[in]   encname  Name of encoding of `str`.
 * @retval      0        Success.
 * @retval      -1       Failure (ENOMEM etc.).
 * @post        `ec`'s replacement string is set to `str`.
 */
int rb_econv_set_replacement(rb_econv_t *ec, const unsigned char *str, size_t len, const char *encname);

/**
 * "Decorate"s  a  converter.   There  are  special  kind  of  converters  that
 * transforms the  contents, like  replacing CR  into CRLF.   You can  add such
 * decorators  to  a converter  using  this  API.   By  using this  function  a
 * decorator is prepended at the beginning of a conversion sequence: in case of
 * CRLF conversion, newlines are converted before encodings are converted.
 *
 * @param[out]  ec              Target converter to decorate.
 * @param[in]   decorator_name  Name of decorator to prepend.
 * @retval      0               Success.
 * @retval      -1              Failure (no such decorator etc.).
 * @post        Decorator works before encoding conversion happens.
 *
 * @internal
 *
 * What is the possible value of  the `decorator_name` is not public.  You have
 * to read through `transcode.c` carefully.
 */
int rb_econv_decorate_at_first(rb_econv_t *ec, const char *decorator_name);

/**
 * Identical to  rb_econv_decorate_at_first(), except  it adds to  the opposite
 * direction.  For  instance CRLF  conversion would  run _after_  encodings are
 * converted.
 *
 * @param[out]  ec              Target converter to decorate.
 * @param[in]   decorator_name  Name of decorator to prepend.
 * @retval      0               Success.
 * @retval      -1              Failure (no such decorator etc.).
 * @post        Decorator works after encoding conversion happens.
 */
int rb_econv_decorate_at_last(rb_econv_t *ec, const char *decorator_name);

/**
 * Creates  a  `rb_eConverterNotFoundError`  exception  object  (but  does  not
 * raise).
 *
 * @param[in]  senc     Name of source encoding.
 * @param[in]  denc     Name of destination encoding.
 * @param[in]  ecflags  A set of enum ::ruby_econv_flag_type.
 * @return     An instance of `rb_eConverterNotFoundError`.
 */
VALUE rb_econv_open_exc(const char *senc, const char *denc, int ecflags);

/**
 * Appends the passed string to the passed converter's output buffer.  This can
 * be  handy  when an  encoding  needs  bytes out  of  thin  air; for  instance
 * ISO-2022-JP  has  "shift   function"  which  does  not   correspond  to  any
 * characters.
 *
 * @param[out]  ec            Target converter.
 * @param[in]   str           String to insert.
 * @param[in]   len           Number of bytes of `str`.
 * @param[in]   str_encoding  Encoding of `str`.
 * @retval      0             Success.
 * @retval      -1            Failure (conversion error etc.).
 * @note        `str_encoding` can  be anything, and `str`  itself is converted
 *              when necessary.
 */
int rb_econv_insert_output(rb_econv_t *ec,
    const unsigned char *str, size_t len, const char *str_encoding);

/**
 * Queries  an encoding  name which  best suits  for rb_econv_insert_output()'s
 * last parameter.  Strings in this  encoding need no conversion when inserted;
 * can be both time/space efficient.
 *
 * @param[in]  ec  Target converter.
 * @return     Its encoding for insertion.
 */
const char *rb_econv_encoding_to_insert_output(rb_econv_t *ec);

/**
 * This is a rb_econv_make_exception() + rb_exc_raise() combo.
 *
 * @param[in]  ec                            (Possibly failed) conversion.
 * @exception  rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception  rb_eUndefinedConversionError  Conversion undefined.
 * @note       This function can return when no error.
 */
void rb_econv_check_error(rb_econv_t *ec);

/**
 * This function makes sense right after rb_econv_convert() returns.  As listed
 * in ::rb_econv_result_t, rb_econv_convert() can bail out for various reasons.
 * This function checks the passed converter's internal state and convert it to
 * an appropriate exception object.
 *
 * @param[in]  ec         Target converter.
 * @retval     RUBY_Qnil  The converter has no error.
 * @retval     otherwise  Conversion error turned into an exception.
 */
VALUE rb_econv_make_exception(rb_econv_t *ec);

/**
 * Queries  if rb_econv_putback()  makes  sense, i.e.  there  are invalid  byte
 * sequences remain in the buffer.
 *
 * @param[in]  ec  Target converter.
 * @return     Number of bytes that can be pushed back.
 */
int rb_econv_putbackable(rb_econv_t *ec);

/**
 * Puts  back the  bytes.  In  case of  ::econv_invalid_byte_sequence, some  of
 * those  invalid  bytes are  discarded  and  the  others  are buffered  to  be
 * converted later.  The latter bytes can be put back using this API.
 *
 * @param[out]  ec  Target converter (invalid byte sequence).
 * @param[out]  p   Return buffer.
 * @param[in]   n   Max number of bytes to put back.
 * @post        At most `n` bytes of what was put back is written to `p`.
 */
void rb_econv_putback(rb_econv_t *ec, unsigned char *p, int n);

/**
 * Queries the passed encoding's corresponding ASCII compatible encoding.  "The
 * corresponding  ASCII  compatible  encoding"  in this  context  is  an  ASCII
 * compatible encoding which  can represent exactly the same  character sets as
 * the given  ASCII incompatible  encoding.  For instance  that of  UTF-16LE is
 * UTF-8.
 *
 * @param[in]  encname    Name of an ASCII incompatible encoding.
 * @retval     NULL       `encname` is already ASCII compatible.
 * @retval     otherwise  The corresponding ASCII compatible encoding.
 */
const char *rb_econv_asciicompat_encoding(const char *encname);

/**
 * Identical to  rb_econv_convert(), except it  takes Ruby's string  instead of
 * C's pointer.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_str_convert(rb_econv_t *ec, VALUE src, int flags);

/**
 * Identical to rb_econv_str_convert(),  except it converts only a  part of the
 * passed string.  Can be handy when  you for instance want to do line-buffered
 * conversion.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      byteoff                       Number of bytes to seek.
 * @param[in]      bytesize                      Number of bytes to read.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_substr_convert(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, int flags);

/**
 * Identical to rb_econv_str_convert(), except it appends the conversion result
 * to the additionally passed string instead  of creating a new string.  It can
 * also be seen as a routine  identical to rb_econv_append(), except it takes a
 * Ruby's string instead of C's pointer.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      dst                           Return buffer.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_str_append(rb_econv_t *ec, VALUE src, VALUE dst, int flags);

/**
 * Identical to  rb_econv_str_append(), except  it appends only  a part  of the
 * passed string with  conversion.  It can also be seen  as a routine identical
 * to rb_econv_substr_convert(), except it appends the conversion result to the
 * additionally passed string instead of creating a new string.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      byteoff                       Number of bytes to seek.
 * @param[in]      bytesize                      Number of bytes to read.
 * @param[in]      dst                           Return buffer.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_substr_append(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, VALUE dst, int flags);

/**
 * Converts  the passed  C's pointer  according to  the passed  converter, then
 * append the conversion  result to the passed Ruby's string.   This way buffer
 * overflow is properly avoided to resize the destination properly.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      bytesrc                       Target string.
 * @param[in]      bytesize                      Number of bytes of `bytesrc`.
 * @param[in]      dst                           Return buffer.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_append(rb_econv_t *ec, const char *bytesrc, long bytesize, VALUE dst, int flags);

/**
 * This badly named  function does not set the destination  encoding to binary,
 * but  instead just  nullifies newline  conversion decorators  if any.   Other
 * ordinal character conversions still  happen after this; something non-binary
 * would still be generated.
 *
 * @param[out]  ec  Target converter to modify.
 * @post        Any newline conversions, if any, would be killed.
 */
void rb_econv_binmode(rb_econv_t *ec);

/**
 * This enum is kind of omnibus.  Gathers various constants.
 */
enum ruby_econv_flag_type {

    /**
     * @name Flags for rb_econv_open()
     *
     * @{
     */

    /** Mask for error handling related bits. */
    RUBY_ECONV_ERROR_HANDLER_MASK               = 0x000000ff,

    /** Special handling of invalid sequences are there. */
    RUBY_ECONV_INVALID_MASK                     = 0x0000000f,

    /** Invalid sequences shall be replaced. */
    RUBY_ECONV_INVALID_REPLACE                  = 0x00000002,

    /** Special handling of undefined conversion are there. */
    RUBY_ECONV_UNDEF_MASK                       = 0x000000f0,

    /** Undefined characters shall be replaced. */
    RUBY_ECONV_UNDEF_REPLACE                    = 0x00000020,

    /** Undefined characters shall be escaped. */
    RUBY_ECONV_UNDEF_HEX_CHARREF                = 0x00000030,

    /** Decorators are there. */
    RUBY_ECONV_DECORATOR_MASK                   = 0x0000ff00,

    /** Newline converters are there. */
    RUBY_ECONV_NEWLINE_DECORATOR_MASK           = 0x00003f00,

    /** (Unclear; seems unused). */
    RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK      = 0x00000f00,

    /** (Unclear; seems unused). */
    RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK     = 0x00003000,

    /** Universal newline mode. */
    RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR      = 0x00000100,

    /** CR to CRLF conversion shall happen. */
    RUBY_ECONV_CRLF_NEWLINE_DECORATOR           = 0x00001000,

    /** CRLF to CR conversion shall happen. */
    RUBY_ECONV_CR_NEWLINE_DECORATOR             = 0x00002000,

    /** Texts shall be XML-escaped. */
    RUBY_ECONV_XML_TEXT_DECORATOR               = 0x00004000,

    /** Texts shall be AttrValue escaped */
    RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR       = 0x00008000,

    /** (Unclear; seems unused). */
    RUBY_ECONV_STATEFUL_DECORATOR_MASK          = 0x00f00000,

    /** Texts shall be AttrValue escaped. */
    RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR         = 0x00100000,

    /** Newline decorator's default. */
    RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR        =
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
	RUBY_ECONV_CRLF_NEWLINE_DECORATOR,
#else
	0,
#endif

#define ECONV_ERROR_HANDLER_MASK                RUBY_ECONV_ERROR_HANDLER_MASK           /**< @old{RUBY_ECONV_ERROR_HANDLER_MASK} */
#define ECONV_INVALID_MASK                      RUBY_ECONV_INVALID_MASK                 /**< @old{RUBY_ECONV_INVALID_MASK} */
#define ECONV_INVALID_REPLACE                   RUBY_ECONV_INVALID_REPLACE              /**< @old{RUBY_ECONV_INVALID_REPLACE} */
#define ECONV_UNDEF_MASK                        RUBY_ECONV_UNDEF_MASK                   /**< @old{RUBY_ECONV_UNDEF_MASK} */
#define ECONV_UNDEF_REPLACE                     RUBY_ECONV_UNDEF_REPLACE                /**< @old{RUBY_ECONV_UNDEF_REPLACE} */
#define ECONV_UNDEF_HEX_CHARREF                 RUBY_ECONV_UNDEF_HEX_CHARREF            /**< @old{RUBY_ECONV_UNDEF_HEX_CHARREF} */
#define ECONV_DECORATOR_MASK                    RUBY_ECONV_DECORATOR_MASK               /**< @old{RUBY_ECONV_DECORATOR_MASK} */
#define ECONV_NEWLINE_DECORATOR_MASK            RUBY_ECONV_NEWLINE_DECORATOR_MASK       /**< @old{RUBY_ECONV_NEWLINE_DECORATOR_MASK} */
#define ECONV_NEWLINE_DECORATOR_READ_MASK       RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK  /**< @old{RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK} */
#define ECONV_NEWLINE_DECORATOR_WRITE_MASK      RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK /**< @old{RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK} */
#define ECONV_UNIVERSAL_NEWLINE_DECORATOR       RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR  /**< @old{RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR} */
#define ECONV_CRLF_NEWLINE_DECORATOR            RUBY_ECONV_CRLF_NEWLINE_DECORATOR       /**< @old{RUBY_ECONV_CRLF_NEWLINE_DECORATOR} */
#define ECONV_CR_NEWLINE_DECORATOR              RUBY_ECONV_CR_NEWLINE_DECORATOR         /**< @old{RUBY_ECONV_CR_NEWLINE_DECORATOR} */
#define ECONV_XML_TEXT_DECORATOR                RUBY_ECONV_XML_TEXT_DECORATOR           /**< @old{RUBY_ECONV_XML_TEXT_DECORATOR} */
#define ECONV_XML_ATTR_CONTENT_DECORATOR        RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR   /**< @old{RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR} */
#define ECONV_STATEFUL_DECORATOR_MASK           RUBY_ECONV_STATEFUL_DECORATOR_MASK      /**< @old{RUBY_ECONV_STATEFUL_DECORATOR_MASK} */
#define ECONV_XML_ATTR_QUOTE_DECORATOR          RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR     /**< @old{RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR} */
#define ECONV_DEFAULT_NEWLINE_DECORATOR         RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR    /**< @old{RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR} */
    /** @} */

    /**
     * @name Flags for rb_econv_convert()
     *
     * @{
     */

    /** Indicates the input is a part of much larger one. */
    RUBY_ECONV_PARTIAL_INPUT                    = 0x00010000,

    /** Instructs the converter to stop after output. */
    RUBY_ECONV_AFTER_OUTPUT                     = 0x00020000,
#define ECONV_PARTIAL_INPUT                     RUBY_ECONV_PARTIAL_INPUT /**< @old{RUBY_ECONV_PARTIAL_INPUT} */
#define ECONV_AFTER_OUTPUT                      RUBY_ECONV_AFTER_OUTPUT  /**< @old{RUBY_ECONV_AFTER_OUTPUT} */

    RUBY_ECONV_FLAGS_PLACEHOLDER /**< Placeholder (not used) */
};

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_ENCODING_H */
