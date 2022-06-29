#ifndef INTERNAL_ENCODING_H                              /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_ENCODING_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Encoding.
 */
#include "ruby/ruby.h"          /* for ID */
#include "ruby/encoding.h"      /* for rb_encoding */
#include "encindex.h"

#define rb_enc_autoload_p(enc) (!rb_enc_mbmaxlen(enc))

/* encoding.c */
ID rb_id_encoding(void);
rb_encoding *rb_enc_get_from_index(int index);
rb_encoding *rb_enc_check_str(VALUE str1, VALUE str2);
int rb_encdb_replicate(const char *alias, const char *orig);
int rb_encdb_alias(const char *alias, const char *orig);
int rb_enc_autoload(rb_encoding *enc);
int rb_encdb_dummy(const char *name);
void rb_encdb_declare(const char *name);
void rb_enc_set_base(const char *name, const char *orig);
int rb_enc_set_dummy(int index);
void rb_encdb_set_unicode(int index);

static inline bool
rb_enc_asciicompat_from_index(int index)
{
    switch (index) {
      case ENCINDEX_ASCII:
      case ENCINDEX_UTF_8:
      case ENCINDEX_US_ASCII:
        return true;
      default:
        return rb_enc_asciicompat(rb_enc_from_index(index));
    }
}

PUREFUNC(int rb_data_is_encoding(VALUE obj));

static inline int
enc_get_index_str(VALUE str)
{
    int i = ENCODING_GET_INLINED(str);
    if (i == ENCODING_INLINE_MAX) {
	VALUE iv;

#if 0
	iv = rb_ivar_get(str, rb_id_encoding());
	i = NUM2INT(iv);
#else
        /*
         * Tentatively, assume ASCII-8BIT, if encoding index instance
         * variable is not found.  This can happen when freeing after
         * all instance variables are removed in `obj_free`.
         */
        iv = rb_attr_get(str, rb_id_encoding());
        i = NIL_P(iv) ? rb_ascii8bit_encindex() : NUM2INT(iv);
#endif
    }
    return i;
}


#endif /* INTERNAL_ENCODING_H */
