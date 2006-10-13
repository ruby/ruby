/* $RoughId: md5init.c,v 1.2 2001/07/13 19:49:10 knu Exp $ */
/* $Id$ */

#include "digest.h"
#if defined(HAVE_OPENSSL_MD5_H)
#include "md5ossl.h"
#else
#include "md5.h"
#endif

static algo_t md5 = {
    MD5_DIGEST_LENGTH,
    sizeof(MD5_CTX),
    (hash_init_func_t)MD5_Init,
    (hash_update_func_t)MD5_Update,
    (hash_finish_func_t)MD5_Finish,
};

/*
 * A class for calculating message digests using the MD5
 * Message-Digest Algorithm by RSA Data Security, Inc., described in
 * RFC1321.
 */
void
Init_md5()
{
    VALUE mDigest, cDigest_Base, cDigest_MD5;

    rb_require("digest");

    mDigest = rb_path2class("Digest");
    cDigest_Base = rb_path2class("Digest::Base");

    cDigest_MD5 = rb_define_class_under(mDigest, "MD5", cDigest_Base);

    rb_define_const(cDigest_MD5, "DIGEST_LENGTH", INT2NUM(MD5_DIGEST_LENGTH));
    rb_define_const(cDigest_MD5, "BLOCK_LENGTH",  INT2NUM(MD5_BLOCK_LENGTH));

    rb_ivar_set(cDigest_MD5, rb_intern("metadata"),
      Data_Wrap_Struct(rb_cObject, 0, 0, &md5));
}
