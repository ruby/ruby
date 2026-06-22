/* $RoughId: crc32init.c,v 1.3 2001/07/13 20:00:43 knu Exp $ */
/* $Id$ */

#include <ruby/ruby.h>
#include "../digest.h"
#include "crc32.h"

static const rb_digest_metadata_t crc32 = {
    RUBY_DIGEST_API_VERSION,
    CRC32_DIGEST_LENGTH,
    CRC32_BLOCK_LENGTH,
    sizeof(CRC32_CTX),
    (rb_digest_hash_init_func_t)CRC32_Init,
    (rb_digest_hash_update_func_t)CRC32_Update,
    (rb_digest_hash_finish_func_t)CRC32_Finish,
};

/*
 * Document-class: Digest::CRC32 < Digest::Base
 * A class for calculating message digests using CRC32 algorithm.
 *
 * CRC32 calculates a digest of 32 bits (4 bytes).
 *
 * == Examples
 *  require 'digest'
 *
 *  # Compute a complete digest
 *  Digest::CRC32.hexdigest 'abc'      #=> "8eb208f7..."
 *
 *  # Compute digest by chunks
 *  crc32 = Digest::CRC32.new               # =>#<Digest::CRC32>
 *  crc32.update "ab"
 *  crc32 << "c"                           # alias for #update
 *  crc32.hexdigest                        # => "352441c2"
 *
 *  # Use the same object to compute another digest
 *  crc32.reset
 *  crc32 << "message"
 *  crc32.hexdigest                        # => "b6bd307f"
 */
void
Init_crc32(void)
{
    VALUE mDigest, cDigest_Base, cDigest_CRC32;

#if 0
    mDigest = rb_define_module("Digest"); /* let rdoc know */
#endif
    mDigest = rb_digest_namespace();
    cDigest_Base = rb_const_get(mDigest, rb_intern_const("Base"));

    cDigest_CRC32 = rb_define_class_under(mDigest, "CRC32", cDigest_Base);
    rb_iv_set(cDigest_CRC32, "metadata", rb_digest_make_metadata(&crc32));
}
