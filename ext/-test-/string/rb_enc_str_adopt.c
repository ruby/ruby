#include "ruby.h"
#include "ruby/encoding.h"

static VALUE
enc_str_adopt(VALUE self, VALUE vstr, VALUE vlen, VALUE vcapa, VALUE vencoding)
{
    long capa = FIX2LONG(vcapa);
    long len = FIX2LONG(vlen);
    rb_encoding *enc = NIL_P(vencoding) ? NULL : rb_to_encoding(vencoding);
    char *ptr = ALLOC_N(char, capa);

    long copy_length = len;
    if (capa < len) {
        copy_length = capa;
    }

    if (copy_length > 0) {
        MEMCPY(ptr, RSTRING_PTR(vstr), char, copy_length);
    }

    return rb_enc_str_adopt(ptr, len, capa, enc);
}

void
Init_string_rb_enc_str_adopt(VALUE klass)
{
    rb_define_singleton_method(klass, "rb_enc_str_adopt", enc_str_adopt, 4);
}
