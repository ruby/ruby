#include "ruby.h"
#include "rubyspec.h"

#include "ruby/digest.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DIGEST_LENGTH 20
#define BLOCK_LENGTH 40

const char *init_string = "Initialized\n";
const char *update_string = "Updated: ";
const char *finish_string = "Finished\n";

#define PAYLOAD_SIZE 128

typedef struct CTX {
  uint8_t pos;
  char payload[PAYLOAD_SIZE];
} CTX;

void* context = NULL;

int digest_spec_plugin_init(void *raw_ctx) {
    // Make the context accessible to tests. This isn't safe, but there's no way to access the context otherwise.
    context = raw_ctx;
 
    struct CTX *ctx = (struct CTX *)raw_ctx;
    size_t len = strlen(init_string);

    // Clear the payload since this init function will be invoked as part of the `reset` operation.
    memset(ctx->payload, 0, PAYLOAD_SIZE);

    // Write a simple value we can verify in tests.
    // This is not what a real digest would do, but we're using a dummy digest plugin to test interactions.
    memcpy(ctx->payload, init_string, len);
    ctx->pos = (uint8_t) len;

    return 1;
}

void digest_spec_plugin_update(void *raw_ctx, unsigned char *ptr, size_t size) {
    struct CTX *ctx = (struct CTX *)raw_ctx;
    size_t update_str_len = strlen(update_string);
    
    if (ctx->pos + update_str_len + size >= PAYLOAD_SIZE) {
        rb_raise(rb_eRuntimeError, "update size too large; reset the digest and write fewer updates");
    }

    // Write the supplied value to the payload so it can be easily verified in test.
    // This is not what a real digest would do, but we're using a dummy digest plugin to test interactions.
    memcpy(ctx->payload + ctx->pos, update_string, update_str_len);
    ctx->pos += update_str_len;

    memcpy(ctx->payload + ctx->pos, ptr, size);
    ctx->pos += size;

    return;
}

int digest_spec_plugin_finish(void *raw_ctx, unsigned char *ptr) {
    struct CTX *ctx = (struct CTX *)raw_ctx;
    size_t finish_string_len = strlen(finish_string);
    
    // We're always going to write DIGEST_LENGTH bytes. In a real plugin, this would be the digest value. Here we
    // write out a text string in order to make validation in tests easier.
    //
    // In order to delineate the output more clearly from an `Digest#update` call, we always write out the
    // `finish_string` message. That leaves `DIGEST_LENGTH - finish_string_len` bytes to read out of the context.
    size_t context_bytes = DIGEST_LENGTH - finish_string_len;

    memcpy(ptr, ctx->payload + (ctx->pos - context_bytes), context_bytes);
    memcpy(ptr + context_bytes, finish_string, finish_string_len);

    return 1;
}

static const rb_digest_metadata_t metadata = {
    // The RUBY_DIGEST_API_VERSION value comes from ruby/digest.h and may vary based on the Ruby being tested. Since
    // it isn't publicly exposed in the digest gem, we ignore for these tests. Either the test hard-codes an expected
    // value and is subject to breaking depending on the Ruby being run or we publicly expose `RUBY_DIGEST_API_VERSION`,
    // in which case the test would pass trivially.
    RUBY_DIGEST_API_VERSION,
    DIGEST_LENGTH,
    BLOCK_LENGTH,
    sizeof(CTX),
    (rb_digest_hash_init_func_t) digest_spec_plugin_init,
    (rb_digest_hash_update_func_t) digest_spec_plugin_update,
    (rb_digest_hash_finish_func_t) digest_spec_plugin_finish,
};

// The `get_metadata_ptr` function is not publicly available in the digest gem. However, we need to use
// to extract the `rb_digest_metadata_t*` value set up by the plugin so we reproduce and adjust the
// definition here.
//
// Taken and adapted from https://github.com/ruby/digest/blob/v3.2.0/ext/digest/digest.c#L558-L568
static rb_digest_metadata_t * get_metadata_ptr(VALUE obj) {
    rb_digest_metadata_t *algo;

#ifdef DIGEST_USE_RB_EXT_RESOLVE_SYMBOL
    // In the digest gem there is an additional data type check performed before reading the value out.
    // Since the type definition isn't public, we can't use it as part of a type check here so we omit it.
    // This is safe to do because this code is intended to only load digest plugins written as part of this test suite.
    algo = (rb_digest_metadata_t *) RTYPEDDATA_DATA(obj);
#else
# undef RUBY_UNTYPED_DATA_WARNING
# define RUBY_UNTYPED_DATA_WARNING 0
    Data_Get_Struct(obj, rb_digest_metadata_t, algo);
#endif

    return algo;
}

VALUE digest_spec_rb_digest_make_metadata(VALUE self) {
    return rb_digest_make_metadata(&metadata);
}

VALUE digest_spec_block_length(VALUE self, VALUE meta) {
    rb_digest_metadata_t* algo = get_metadata_ptr(meta);

    return SIZET2NUM(algo->block_len);
}

VALUE digest_spec_digest_length(VALUE self, VALUE meta) {
    rb_digest_metadata_t* algo = get_metadata_ptr(meta);

    return SIZET2NUM(algo->digest_len);
}

VALUE digest_spec_context_size(VALUE self, VALUE meta) {
    rb_digest_metadata_t* algo = get_metadata_ptr(meta);

    return SIZET2NUM(algo->ctx_size);
}

#define PTR2NUM(x) (rb_int2inum((intptr_t)(void *)(x)))

VALUE digest_spec_context(VALUE self, VALUE digest) {
    return PTR2NUM(context);
}

void Init_digest_spec(void) {
    VALUE cls;

    cls = rb_define_class("CApiDigestSpecs", rb_cObject);
    rb_define_method(cls, "rb_digest_make_metadata", digest_spec_rb_digest_make_metadata, 0);
    rb_define_method(cls, "block_length", digest_spec_block_length, 1);
    rb_define_method(cls, "digest_length", digest_spec_digest_length, 1);
    rb_define_method(cls, "context_size", digest_spec_context_size, 1);
    rb_define_method(cls, "context", digest_spec_context, 1);

    VALUE mDigest, cDigest_Base, cDigest;

    mDigest = rb_define_module("Digest");
    mDigest = rb_digest_namespace();
    cDigest_Base = rb_const_get(mDigest, rb_intern_const("Base"));

    cDigest = rb_define_class_under(mDigest, "TestDigest", cDigest_Base);
    rb_iv_set(cDigest, "metadata", rb_digest_make_metadata(&metadata));
}

#ifdef __cplusplus
}
#endif
