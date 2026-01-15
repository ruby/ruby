/* $RoughId: sha2init.c,v 1.3 2001/07/13 20:00:43 knu Exp $ */
/* $Id$ */

#include <ruby/ruby.h>
#include "../digest.h"
#if defined(SHA2_USE_COMMONDIGEST)
#include "sha2cc.h"
#else
#include "sha2.h"
#endif

#define FOREACH_BITLEN(func)	func(256) func(384) func(512)

#define DEFINE_ALGO_METADATA(bitlen) \
static const rb_digest_metadata_t sha##bitlen = { \
    RUBY_DIGEST_API_VERSION, \
    SHA##bitlen##_DIGEST_LENGTH, \
    SHA##bitlen##_BLOCK_LENGTH, \
    sizeof(SHA##bitlen##_CTX), \
    (rb_digest_hash_init_func_t)SHA##bitlen##_Init, \
    (rb_digest_hash_update_func_t)SHA##bitlen##_Update, \
    (rb_digest_hash_finish_func_t)SHA##bitlen##_Finish, \
};

FOREACH_BITLEN(DEFINE_ALGO_METADATA)

/*
 * Document-class: Digest::SHA256 < Digest::Base
 *
 * Classes for calculating message digests using the SHA-256/384/512
 * Secure Hash Algorithm(s) by NIST (the US' National Institute of
 * Standards and Technology), described in FIPS PUB 180-2.
 *
 * See SHA2.
 */
/*
 * Document-class: Digest::SHA384 < Digest::Base
 *
 * Classes for calculating message digests using the SHA-256/384/512
 * Secure Hash Algorithm(s) by NIST (the US' National Institute of
 * Standards and Technology), described in FIPS PUB 180-2.
 *
 * See SHA2.
 */
/*
 * Document-class: Digest::SHA512 < Digest::Base
 *
 * Classes for calculating message digests using the SHA-256/384/512
 * Secure Hash Algorithm(s) by NIST (the US' National Institute of
 * Standards and Technology), described in FIPS PUB 180-2.
 *
 * See SHA2.
 */
void
Init_sha2(void)
{
    VALUE mDigest, cDigest_Base, cDigest_SHA2;
    ID id_metadata = rb_id_metadata();

#if 0
    mDigest = rb_define_module("Digest"); /* let rdoc know */
#endif
    mDigest = rb_digest_namespace();
    cDigest_Base = rb_const_get(mDigest, rb_intern_const("Base"));

    cDigest_SHA2 = rb_define_class_under(mDigest, "SHA256", cDigest_Base);
    rb_ivar_set(cDigest_SHA2, id_metadata, rb_digest_make_metadata(&sha256));

    cDigest_SHA2 = rb_define_class_under(mDigest, "SHA384", cDigest_Base);
    rb_ivar_set(cDigest_SHA2, id_metadata, rb_digest_make_metadata(&sha384));

    cDigest_SHA2 = rb_define_class_under(mDigest, "SHA512", cDigest_Base);
    rb_ivar_set(cDigest_SHA2, id_metadata, rb_digest_make_metadata(&sha512));
}
