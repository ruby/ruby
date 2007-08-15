/* $RoughId: rmd160init.c,v 1.3 2001/07/13 20:00:43 knu Exp $ */
/* $Id: rmd160init.c,v 1.3 2002/09/26 17:26:46 knu Exp $ */

#include "digest.h"
#if defined(HAVE_OPENSSL_RIPEMD_H)
#include "rmd160ossl.h"
#else
#include "rmd160.h"
#endif

static algo_t rmd160 = {
    RMD160_DIGEST_LENGTH,
    sizeof(RMD160_CTX),
    (hash_init_func_t)RMD160_Init,
    (hash_update_func_t)RMD160_Update,
    (hash_end_func_t)RMD160_End,
    (hash_final_func_t)RMD160_Final,
    (hash_equal_func_t)RMD160_Equal,
};

void
Init_rmd160()
{
    VALUE mDigest, cDigest_Base, cDigest_RMD160;
    ID id_metadata;

    rb_require("digest.so");

    mDigest = rb_path2class("Digest");
    cDigest_Base = rb_path2class("Digest::Base");

    cDigest_RMD160 = rb_define_class_under(mDigest, "RMD160", cDigest_Base);

    id_metadata = rb_intern("metadata");

    rb_cvar_set(cDigest_RMD160, id_metadata,
		Data_Wrap_Struct(rb_cObject, 0, 0, &rmd160), Qtrue);
}
