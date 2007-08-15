/* $RoughId: md5init.c,v 1.2 2001/07/13 19:49:10 knu Exp $ */
/* $Id: md5init.c,v 1.5 2002/09/26 16:27:23 knu Exp $ */

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
    (hash_end_func_t)MD5_End,
    (hash_final_func_t)MD5_Final,
    (hash_equal_func_t)MD5_Equal,
};

void
Init_md5()
{
    VALUE mDigest, cDigest_Base, cDigest_MD5;

    rb_require("digest.so");

    mDigest = rb_path2class("Digest");
    cDigest_Base = rb_path2class("Digest::Base");

    cDigest_MD5 = rb_define_class_under(mDigest, "MD5", cDigest_Base);

    rb_cvar_set(cDigest_MD5, rb_intern("metadata"),
		Data_Wrap_Struct(rb_cObject, 0, 0, &md5), Qtrue);
}
