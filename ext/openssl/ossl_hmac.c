/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(OPENSSL_NO_HMAC)

#include "ossl.h"

#define NewHMAC(klass) \
    TypedData_Wrap_Struct((klass), &ossl_hmac_type, 0)
#define GetHMAC(obj, ctx) do { \
    TypedData_Get_Struct((obj), HMAC_CTX, &ossl_hmac_type, (ctx)); \
    if (!(ctx)) { \
	ossl_raise(rb_eRuntimeError, "HMAC wasn't initialized"); \
    } \
} while (0)

/*
 * Classes
 */
VALUE cHMAC;
VALUE eHMACError;

/*
 * Public
 */

/*
 * Private
 */
static void
ossl_hmac_free(void *ctx)
{
    HMAC_CTX_free(ctx);
}

static const rb_data_type_t ossl_hmac_type = {
    "OpenSSL/HMAC",
    {
	0, ossl_hmac_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
ossl_hmac_alloc(VALUE klass)
{
    VALUE obj;
    HMAC_CTX *ctx;

    obj = NewHMAC(klass);
    ctx = HMAC_CTX_new();
    if (!ctx)
	ossl_raise(eHMACError, NULL);
    RTYPEDDATA_DATA(obj) = ctx;

    return obj;
}


/*
 *  call-seq:
 *     HMAC.new(key, digest) -> hmac
 *
 * Returns an instance of OpenSSL::HMAC set with the key and digest
 * algorithm to be used. The instance represents the initial state of
 * the message authentication code before any data has been processed.
 * To process data with it, use the instance method #update with your
 * data as an argument.
 *
 * === Example
 *
 *	key = 'key'
 * 	digest = OpenSSL::Digest.new('sha1')
 * 	instance = OpenSSL::HMAC.new(key, digest)
 * 	#=> f42bb0eeb018ebbd4597ae7213711ec60760843f
 * 	instance.class
 * 	#=> OpenSSL::HMAC
 *
 * === A note about comparisons
 *
 * Two instances won't be equal when they're compared, even if they have the
 * same value. Use #to_s or #hexdigest to return the authentication code that
 * the instance represents. For example:
 *
 *	other_instance = OpenSSL::HMAC.new('key', OpenSSL::Digest.new('sha1'))
 *  	#=> f42bb0eeb018ebbd4597ae7213711ec60760843f
 *  	instance
 *  	#=> f42bb0eeb018ebbd4597ae7213711ec60760843f
 *  	instance == other_instance
 *  	#=> false
 *  	instance.to_s == other_instance.to_s
 *  	#=> true
 *
 */
static VALUE
ossl_hmac_initialize(VALUE self, VALUE key, VALUE digest)
{
    HMAC_CTX *ctx;

    StringValue(key);
    GetHMAC(self, ctx);
    HMAC_Init_ex(ctx, RSTRING_PTR(key), RSTRING_LENINT(key),
		 ossl_evp_get_digestbyname(digest), NULL);

    return self;
}

static VALUE
ossl_hmac_copy(VALUE self, VALUE other)
{
    HMAC_CTX *ctx1, *ctx2;

    rb_check_frozen(self);
    if (self == other) return self;

    GetHMAC(self, ctx1);
    GetHMAC(other, ctx2);

    if (!HMAC_CTX_copy(ctx1, ctx2))
	ossl_raise(eHMACError, "HMAC_CTX_copy");
    return self;
}

/*
 *  call-seq:
 *     hmac.update(string) -> self
 *
 * Returns _hmac_ updated with the message to be authenticated.
 * Can be called repeatedly with chunks of the message.
 *
 * === Example
 *
 *	first_chunk = 'The quick brown fox jumps '
 * 	second_chunk = 'over the lazy dog'
 *
 * 	instance.update(first_chunk)
 * 	#=> 5b9a8038a65d571076d97fe783989e52278a492a
 * 	instance.update(second_chunk)
 * 	#=> de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9
 *
 */
static VALUE
ossl_hmac_update(VALUE self, VALUE data)
{
    HMAC_CTX *ctx;

    StringValue(data);
    GetHMAC(self, ctx);
    HMAC_Update(ctx, (unsigned char *)RSTRING_PTR(data), RSTRING_LEN(data));

    return self;
}

static void
hmac_final(HMAC_CTX *ctx, unsigned char *buf, unsigned int *buf_len)
{
    HMAC_CTX *final;

    final = HMAC_CTX_new();
    if (!final)
	ossl_raise(eHMACError, "HMAC_CTX_new");

    if (!HMAC_CTX_copy(final, ctx)) {
	HMAC_CTX_free(final);
	ossl_raise(eHMACError, "HMAC_CTX_copy");
    }

    HMAC_Final(final, buf, buf_len);
    HMAC_CTX_free(final);
}

/*
 *  call-seq:
 *     hmac.digest -> string
 *
 * Returns the authentication code an instance represents as a binary string.
 *
 * === Example
 *  instance = OpenSSL::HMAC.new('key', OpenSSL::Digest.new('sha1'))
 *  #=> f42bb0eeb018ebbd4597ae7213711ec60760843f
 *  instance.digest
 *  #=> "\xF4+\xB0\xEE\xB0\x18\xEB\xBDE\x97\xAEr\x13q\x1E\xC6\a`\x84?"
 */
static VALUE
ossl_hmac_digest(VALUE self)
{
    HMAC_CTX *ctx;
    unsigned int buf_len;
    VALUE ret;

    GetHMAC(self, ctx);
    ret = rb_str_new(NULL, EVP_MAX_MD_SIZE);
    hmac_final(ctx, (unsigned char *)RSTRING_PTR(ret), &buf_len);
    assert(buf_len <= EVP_MAX_MD_SIZE);
    rb_str_set_len(ret, buf_len);

    return ret;
}

/*
 *  call-seq:
 *     hmac.hexdigest -> string
 *
 * Returns the authentication code an instance represents as a hex-encoded
 * string.
 */
static VALUE
ossl_hmac_hexdigest(VALUE self)
{
    HMAC_CTX *ctx;
    unsigned char buf[EVP_MAX_MD_SIZE];
    unsigned int buf_len;
    VALUE ret;

    GetHMAC(self, ctx);
    hmac_final(ctx, buf, &buf_len);
    ret = rb_str_new(NULL, buf_len * 2);
    ossl_bin2hex(buf, RSTRING_PTR(ret), buf_len);

    return ret;
}

/*
 *  call-seq:
 *     hmac.reset -> self
 *
 * Returns _hmac_ as it was when it was first initialized, with all processed
 * data cleared from it.
 *
 * === Example
 *
 *	data = "The quick brown fox jumps over the lazy dog"
 * 	instance = OpenSSL::HMAC.new('key', OpenSSL::Digest.new('sha1'))
 * 	#=> f42bb0eeb018ebbd4597ae7213711ec60760843f
 *
 * 	instance.update(data)
 * 	#=> de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9
 * 	instance.reset
 * 	#=> f42bb0eeb018ebbd4597ae7213711ec60760843f
 *
 */
static VALUE
ossl_hmac_reset(VALUE self)
{
    HMAC_CTX *ctx;

    GetHMAC(self, ctx);
    HMAC_Init_ex(ctx, NULL, 0, NULL, NULL);

    return self;
}

/*
 *  call-seq:
 *     HMAC.digest(digest, key, data) -> aString
 *
 * Returns the authentication code as a binary string. The _digest_ parameter
 * specifies the digest algorithm to use. This may be a String representing
 * the algorithm name or an instance of OpenSSL::Digest.
 *
 * === Example
 *
 *	key = 'key'
 * 	data = 'The quick brown fox jumps over the lazy dog'
 *
 * 	hmac = OpenSSL::HMAC.digest('sha1', key, data)
 * 	#=> "\xDE|\x9B\x85\xB8\xB7\x8A\xA6\xBC\x8Az6\xF7\n\x90p\x1C\x9D\xB4\xD9"
 *
 */
static VALUE
ossl_hmac_s_digest(VALUE klass, VALUE digest, VALUE key, VALUE data)
{
    unsigned char *buf;
    unsigned int buf_len;

    StringValue(key);
    StringValue(data);
    buf = HMAC(ossl_evp_get_digestbyname(digest), RSTRING_PTR(key),
	       RSTRING_LENINT(key), (unsigned char *)RSTRING_PTR(data),
	       RSTRING_LEN(data), NULL, &buf_len);

    return rb_str_new((const char *)buf, buf_len);
}

/*
 *  call-seq:
 *     HMAC.hexdigest(digest, key, data) -> aString
 *
 * Returns the authentication code as a hex-encoded string. The _digest_
 * parameter specifies the digest algorithm to use. This may be a String
 * representing the algorithm name or an instance of OpenSSL::Digest.
 *
 * === Example
 *
 *	key = 'key'
 * 	data = 'The quick brown fox jumps over the lazy dog'
 *
 * 	hmac = OpenSSL::HMAC.hexdigest('sha1', key, data)
 * 	#=> "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9"
 *
 */
static VALUE
ossl_hmac_s_hexdigest(VALUE klass, VALUE digest, VALUE key, VALUE data)
{
    unsigned char buf[EVP_MAX_MD_SIZE];
    unsigned int buf_len;
    VALUE ret;

    StringValue(key);
    StringValue(data);

    if (!HMAC(ossl_evp_get_digestbyname(digest), RSTRING_PTR(key),
	      RSTRING_LENINT(key), (unsigned char *)RSTRING_PTR(data),
	      RSTRING_LEN(data), buf, &buf_len))
	ossl_raise(eHMACError, "HMAC");

    ret = rb_str_new(NULL, buf_len * 2);
    ossl_bin2hex(buf, RSTRING_PTR(ret), buf_len);

    return ret;
}

/*
 * INIT
 */
void
Init_ossl_hmac(void)
{
#if 0
    mOSSL = rb_define_module("OpenSSL");
    eOSSLError = rb_define_class_under(mOSSL, "OpenSSLError", rb_eStandardError);
#endif

    /*
     * Document-class: OpenSSL::HMAC
     *
     * OpenSSL::HMAC allows computing Hash-based Message Authentication Code
     * (HMAC). It is a type of message authentication code (MAC) involving a
     * hash function in combination with a key. HMAC can be used to verify the
     * integrity of a message as well as the authenticity.
     *
     * OpenSSL::HMAC has a similar interface to OpenSSL::Digest.
     *
     * === HMAC-SHA256 using one-shot interface
     *
     *   key = "key"
     *   data = "message-to-be-authenticated"
     *   mac = OpenSSL::HMAC.hexdigest("SHA256", key, data)
     *   #=> "cddb0db23f469c8bf072b21fd837149bd6ace9ab771cceef14c9e517cc93282e"
     *
     * === HMAC-SHA256 using incremental interface
     *
     *   data1 = File.read("file1")
     *   data2 = File.read("file2")
     *   key = "key"
     *   digest = OpenSSL::Digest::SHA256.new
     *   hmac = OpenSSL::HMAC.new(key, digest)
     *   hmac << data1
     *   hmac << data2
     *   mac = hmac.digest
     */
    eHMACError = rb_define_class_under(mOSSL, "HMACError", eOSSLError);

    cHMAC = rb_define_class_under(mOSSL, "HMAC", rb_cObject);

    rb_define_alloc_func(cHMAC, ossl_hmac_alloc);
    rb_define_singleton_method(cHMAC, "digest", ossl_hmac_s_digest, 3);
    rb_define_singleton_method(cHMAC, "hexdigest", ossl_hmac_s_hexdigest, 3);

    rb_define_method(cHMAC, "initialize", ossl_hmac_initialize, 2);
    rb_define_method(cHMAC, "initialize_copy", ossl_hmac_copy, 1);

    rb_define_method(cHMAC, "reset", ossl_hmac_reset, 0);
    rb_define_method(cHMAC, "update", ossl_hmac_update, 1);
    rb_define_alias(cHMAC, "<<", "update");
    rb_define_method(cHMAC, "digest", ossl_hmac_digest, 0);
    rb_define_method(cHMAC, "hexdigest", ossl_hmac_hexdigest, 0);
    rb_define_alias(cHMAC, "inspect", "hexdigest");
    rb_define_alias(cHMAC, "to_s", "hexdigest");
}

#else /* NO_HMAC */
#  warning >>> OpenSSL is compiled without HMAC support <<<
void
Init_ossl_hmac(void)
{
    rb_warning("HMAC is not available: OpenSSL is compiled without HMAC.");
}
#endif /* NO_HMAC */
