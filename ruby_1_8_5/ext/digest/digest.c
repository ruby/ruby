/************************************************

  digest.c -

  $Author: matz $
  created at: Fri May 25 08:57:27 JST 2001

  Copyright (C) 1995-2001 Yukihiro Matsumoto
  Copyright (C) 2001 Akinori MUSHA

  $RoughId: digest.c,v 1.16 2001/07/13 15:38:27 knu Exp $
  $Id: digest.c,v 1.14.2.2 2005/12/12 00:36:51 matz Exp $

************************************************/

/*
 * This module provides an interface to the following hash algorithms:
 *
 *   - the MD5 Message-Digest Algorithm by the RSA Data Security,
 *     Inc., described in RFC 1321
 *
 *   - the SHA-1 Secure Hash Algorithm by NIST (the US' National
 *     Institute of Standards and Technology), described in FIPS PUB
 *     180-1.
 *
 *   - the SHA-256/384/512 Secure Hash Algorithm by NIST (the US'
 *     National Institute of Standards and Technology), described in
 *     FIPS PUB 180-2.
 *
 *   - the RIPEMD-160 cryptographic hash function, designed by Hans
 *     Dobbertin, Antoon Bosselaers, and Bart Preneel.
 */

#include "digest.h"

static VALUE mDigest, cDigest_Base;
static ID id_metadata;

/*
 * Digest::Base
 */

static algo_t *
get_digest_base_metadata(klass)
    VALUE klass;
{
    VALUE obj;
    algo_t *algo;

    if (rb_cvar_defined(klass, id_metadata) == Qfalse) {
	rb_notimplement();
    }

    obj = rb_cvar_get(klass, id_metadata);

    Data_Get_Struct(obj, algo_t, algo);

    return algo;
}

static VALUE rb_digest_base_alloc _((VALUE));
static VALUE
rb_digest_base_alloc(klass)
    VALUE klass;
{
    algo_t *algo;
    VALUE obj;
    void *pctx;

    if (klass == cDigest_Base) {
	rb_raise(rb_eNotImpError, "Digest::Base is an abstract class");
    }

    algo = get_digest_base_metadata(klass);

    /* XXX: An uninitialized buffer leads ALGO_Equal() to fail */
    pctx = xcalloc(algo->ctx_size, 1);
    algo->init_func(pctx);

    obj = Data_Wrap_Struct(klass, 0, free, pctx);

    return obj;
}

static VALUE
rb_digest_base_s_digest(klass, str)
    VALUE klass;
    VALUE str;
{
    algo_t *algo;
    void *pctx;
    size_t len;
    unsigned char *digest;
    volatile VALUE obj = rb_digest_base_alloc(klass);

    algo = get_digest_base_metadata(klass);
    Data_Get_Struct(obj, void, pctx);

    StringValue(str);
    algo->update_func(pctx, RSTRING(str)->ptr, RSTRING(str)->len);

    len = algo->digest_len;

    digest = xmalloc(len);
    algo->final_func(digest, pctx);

    obj = rb_str_new(digest, len);

    free(digest);

    return obj;
}

static VALUE
rb_digest_base_s_hexdigest(klass, str)
    VALUE klass;
    VALUE str;
{
    algo_t *algo;
    void *pctx;
    size_t len;
    unsigned char *hexdigest;
    volatile VALUE obj = rb_digest_base_alloc(klass);

    algo = get_digest_base_metadata(klass);
    Data_Get_Struct(obj, void, pctx);

    StringValue(str);
    algo->update_func(pctx, RSTRING(str)->ptr, RSTRING(str)->len);

    len = algo->digest_len * 2;

    hexdigest = xmalloc(len + 1); /* +1 is for '\0' */
    algo->end_func(pctx, hexdigest);

    obj = rb_str_new(hexdigest, len);

    free(hexdigest);

    return obj;
}

static VALUE
rb_digest_base_copy(copy, obj)
    VALUE copy, obj;
{
    algo_t *algo;
    void *pctx1, *pctx2;

    if (copy == obj) return copy;
    rb_check_frozen(copy);
    algo = get_digest_base_metadata(rb_obj_class(copy));
    if (algo != get_digest_base_metadata(rb_obj_class(obj))) {
	rb_raise(rb_eTypeError, "wrong argument class");
    }
    Data_Get_Struct(obj, void, pctx1);
    Data_Get_Struct(copy, void, pctx2);
    memcpy(pctx2, pctx1, algo->ctx_size);

    return copy;
}

static VALUE
rb_digest_base_update(self, str)
    VALUE self, str;
{
    algo_t *algo;
    void *pctx;

    StringValue(str);
    algo = get_digest_base_metadata(rb_obj_class(self));
    Data_Get_Struct(self, void, pctx);

    algo->update_func(pctx, RSTRING(str)->ptr, RSTRING(str)->len);

    return self;
}

static VALUE
rb_digest_base_init(argc, argv, self)
    int argc;
    VALUE* argv;
    VALUE self;
{
    VALUE arg;

    rb_scan_args(argc, argv, "01", &arg);

    if (!NIL_P(arg)) rb_digest_base_update(self, arg);

    return self;
}

static VALUE
rb_digest_base_digest(self)
    VALUE self;
{
    algo_t *algo;
    void *pctx1, *pctx2;
    unsigned char *digest;
    size_t len;
    VALUE str;

    algo = get_digest_base_metadata(rb_obj_class(self));
    Data_Get_Struct(self, void, pctx1);

    len = algo->ctx_size;

    pctx2 = xmalloc(len);
    memcpy(pctx2, pctx1, len);

    len = algo->digest_len;

    digest = xmalloc(len);
    algo->final_func(digest, pctx2);

    str = rb_str_new(digest, len);

    free(digest);
    free(pctx2);

    return str;
}

static VALUE
rb_digest_base_hexdigest(self)
    VALUE self;
{
    algo_t *algo;
    void *pctx1, *pctx2;
    unsigned char *hexdigest;
    size_t len;
    VALUE str;

    algo = get_digest_base_metadata(rb_obj_class(self));
    Data_Get_Struct(self, void, pctx1);

    len = algo->ctx_size;

    pctx2 = xmalloc(len);
    memcpy(pctx2, pctx1, len);

    len = algo->digest_len * 2;

    hexdigest = xmalloc(len + 1); /* +1 is for '\0' */
    algo->end_func(pctx2, hexdigest);

    str = rb_str_new(hexdigest, len);

    free(hexdigest);
    free(pctx2);

    return str;
}

static VALUE
rb_digest_base_equal(self, other)
    VALUE self, other;
{
    algo_t *algo;
    VALUE klass;
    VALUE str1, str2;

    klass = rb_obj_class(self);
    algo = get_digest_base_metadata(klass);

    if (rb_obj_class(other) == klass) {
	void *pctx1, *pctx2;

	Data_Get_Struct(self, void, pctx1);
	Data_Get_Struct(other, void, pctx2);

	return algo->equal_func(pctx1, pctx2) ? Qtrue : Qfalse;
    }

    StringValue(other);
    str2 = other;

    if (RSTRING(str2)->len == algo->digest_len)
	str1 = rb_digest_base_digest(self);
    else
	str1 = rb_digest_base_hexdigest(self);

    if (RSTRING(str1)->len == RSTRING(str2)->len
      && rb_str_cmp(str1, str2) == 0)
	return Qtrue;

    return Qfalse;
}

/*
 * Init
 */

void
Init_digest()
{
    mDigest = rb_define_module("Digest");

    cDigest_Base = rb_define_class_under(mDigest, "Base", rb_cObject);

    rb_define_alloc_func(cDigest_Base, rb_digest_base_alloc);
    rb_define_singleton_method(cDigest_Base, "digest", rb_digest_base_s_digest, 1);
    rb_define_singleton_method(cDigest_Base, "hexdigest", rb_digest_base_s_hexdigest, 1);

    rb_define_method(cDigest_Base, "initialize", rb_digest_base_init, -1);
    rb_define_method(cDigest_Base, "initialize_copy",  rb_digest_base_copy, 1);
    rb_define_method(cDigest_Base, "update", rb_digest_base_update, 1);
    rb_define_method(cDigest_Base, "<<", rb_digest_base_update, 1);
    rb_define_method(cDigest_Base, "digest", rb_digest_base_digest, 0);
    rb_define_method(cDigest_Base, "hexdigest", rb_digest_base_hexdigest, 0);
    rb_define_method(cDigest_Base, "to_s", rb_digest_base_hexdigest, 0);
    rb_define_method(cDigest_Base, "==", rb_digest_base_equal, 1);

    id_metadata = rb_intern("metadata");
}
