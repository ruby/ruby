/* BLAKE3 binding for the Ruby digest framework. */

#include <ruby/ruby.h>
#include "../digest.h"
#include "blake3.h"

/*
 * Thin adapters mapping BLAKE3's public API onto the signatures the
 * digest framework expects (see rb_digest_metadata_t in ../digest.h).
 * The signatures line up directly, so no function-pointer casts are
 * needed.
 */

static int
rb_digest_BLAKE3_init(void *ctx)
{
    blake3_hasher_init((blake3_hasher *)ctx);
    return 1;
}

static void
rb_digest_BLAKE3_update(void *ctx, unsigned char *ptr, size_t size)
{
    blake3_hasher_update((blake3_hasher *)ctx, ptr, size);
}

static int
rb_digest_BLAKE3_finish(void *ctx, unsigned char *ptr)
{
    blake3_hasher_finalize((blake3_hasher *)ctx, ptr, BLAKE3_OUT_LEN);
    return 1;
}

static const rb_digest_metadata_t blake3 = {
    RUBY_DIGEST_API_VERSION,
    BLAKE3_OUT_LEN,
    BLAKE3_BLOCK_LEN,
    sizeof(blake3_hasher),
    rb_digest_BLAKE3_init,
    rb_digest_BLAKE3_update,
    rb_digest_BLAKE3_finish,
};

/*
 * Document-class: Digest::BLAKE3 < Digest::Base
 * A class for calculating message digests using the BLAKE3 hash function,
 * by Jack O'Connor, Jean-Philippe Aumasson, Samuel Neves, and Zooko
 * Wilcox-O'Hearn.
 *
 * BLAKE3 produces a digest of 256 bits (32 bytes) by default.
 *
 * == Examples
 *  require 'digest'
 *
 *  # Compute a complete digest
 *  Digest::BLAKE3.hexdigest 'abc'     #=> "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"
 *
 *  # Compute digest by chunks
 *  blake3 = Digest::BLAKE3.new             # =>#<Digest::BLAKE3>
 *  blake3.update "ab"
 *  blake3 << "c"                           # alias for #update
 *  blake3.hexdigest                        # => "6437b3ac..."
 *
 *  # Use the same object to compute another digest
 *  blake3.reset
 *  blake3 << "message"
 *  blake3.hexdigest
 */
void
Init_blake3(void)
{
    VALUE mDigest, cDigest_Base, cDigest_BLAKE3;

#if 0
    mDigest = rb_define_module("Digest"); /* let rdoc know */
#endif
    mDigest = rb_digest_namespace();
    cDigest_Base = rb_const_get(mDigest, rb_intern_const("Base"));

    cDigest_BLAKE3 = rb_define_class_under(mDigest, "BLAKE3", cDigest_Base);
    rb_iv_set(cDigest_BLAKE3, "metadata", rb_digest_make_metadata(&blake3));
}
