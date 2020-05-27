/* $RoughId: sha1init.c,v 1.2 2001/07/13 19:49:10 knu Exp $ */
/* $Id$ */

#include <ruby/ruby.h>
#include "../digest.h"
#if defined(SHA1_USE_COMMONDIGEST)
#include "sha1cc.h"
#else
#include "sha1.h"
#endif

static const rb_digest_metadata_t sha1 = {
    RUBY_DIGEST_API_VERSION,
    SHA1_DIGEST_LENGTH,
    SHA1_BLOCK_LENGTH,
    sizeof(SHA1_CTX),
    (rb_digest_hash_init_func_t)SHA1_Init,
    (rb_digest_hash_update_func_t)SHA1_Update,
    (rb_digest_hash_finish_func_t)SHA1_Finish,
};

/*
 * Document-class: Digest::SHA1 < Digest::Base
 * A class for calculating message digests using the SHA-1 Secure Hash
 * Algorithm by NIST (the US' National Institute of Standards and
 * Technology), described in FIPS PUB 180-1.
 *
 * See Digest::Instance for digest API.
 *
 * SHA-1 calculates a digest of 160 bits (20 bytes).
 *
 * == Examples
 *  require 'digest'
 *
 *  # Compute a complete digest
 *  Digest::SHA1.hexdigest 'abc'      #=> "a9993e36..."
 *
 *  # Compute digest by chunks
 *  sha1 = Digest::SHA1.new               # =>#<Digest::SHA1>
 *  sha1.update "ab"
 *  sha1 << "c"                           # alias for #update
 *  sha1.hexdigest                        # => "a9993e36..."
 *
 *  # Use the same object to compute another digest
 *  sha1.reset
 *  sha1 << "message"
 *  sha1.hexdigest                        # => "6f9b9af3..."
 */
void
Init_sha1(void)
{
    VALUE mDigest, cDigest_Base, cDigest_SHA1;

#if 0
    mDigest = rb_define_module("Digest"); /* let rdoc know */
#endif
    mDigest = rb_digest_namespace();
    cDigest_Base = rb_path2class("Digest::Base");

    cDigest_SHA1 = rb_define_class_under(mDigest, "SHA1", cDigest_Base);

#undef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 0
    rb_iv_set(cDigest_SHA1, "metadata",
	      Data_Wrap_Struct(0, 0, 0, (void *)&sha1));
}
