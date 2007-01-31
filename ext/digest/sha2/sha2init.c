/* $RoughId: sha2init.c,v 1.3 2001/07/13 20:00:43 knu Exp $ */
/* $Id: sha2init.c,v 1.2 2002/02/17 12:43:44 nobu Exp $ */

#include "digest.h"
#include "sha2.h"

#define FOREACH_BITLEN(func)	func(256) func(384) func(512)

#define DEFINE_ALGO_METADATA(bitlen) \
static algo_t sha##bitlen = { \
    SHA##bitlen##_DIGEST_LENGTH, \
    sizeof(SHA##bitlen##_CTX), \
    (hash_init_func_t)SHA##bitlen##_Init, \
    (hash_update_func_t)SHA##bitlen##_Update, \
    (hash_end_func_t)SHA##bitlen##_End, \
    (hash_final_func_t)SHA##bitlen##_Final, \
    (hash_equal_func_t)SHA##bitlen##_Equal, \
};

FOREACH_BITLEN(DEFINE_ALGO_METADATA)

void
Init_sha2()
{
    VALUE mDigest, cDigest_Base;
    ID id_metadata;

#define DECLARE_ALGO_CLASS(bitlen) \
    VALUE cDigest_SHA##bitlen;

    FOREACH_BITLEN(DECLARE_ALGO_CLASS)

    rb_require("digest.so");

    id_metadata = rb_intern("metadata");

    mDigest = rb_path2class("Digest");
    cDigest_Base = rb_path2class("Digest::Base");

#define DEFINE_ALGO_CLASS(bitlen) \
    cDigest_SHA##bitlen = rb_define_class_under(mDigest, "SHA" #bitlen, cDigest_Base); \
\
    rb_cvar_set(cDigest_SHA##bitlen, id_metadata, \
		Data_Wrap_Struct(rb_cObject, 0, 0, &sha##bitlen), Qtrue);

    FOREACH_BITLEN(DEFINE_ALGO_CLASS)
}
