/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#include "ossl.h"

#define NewCipher(klass) \
    TypedData_Wrap_Struct((klass), &ossl_cipher_type, 0)
#define AllocCipher(obj, ctx) do { \
    (ctx) = EVP_CIPHER_CTX_new(); \
    if (!(ctx)) \
        ossl_raise(rb_eRuntimeError, NULL); \
    RTYPEDDATA_DATA(obj) = (ctx); \
} while (0)
#define GetCipherInit(obj, ctx) do { \
    TypedData_Get_Struct((obj), EVP_CIPHER_CTX, &ossl_cipher_type, (ctx)); \
} while (0)
#define GetCipher(obj, ctx) do { \
    GetCipherInit((obj), (ctx)); \
    if (!(ctx)) { \
        ossl_raise(rb_eRuntimeError, "Cipher not initialized!"); \
    } \
} while (0)

/*
 * Classes
 */
static VALUE cCipher;
static VALUE eCipherError;
static VALUE eAuthTagError;
static ID id_auth_tag_len, id_key_set, id_cipher_holder;

static VALUE ossl_cipher_alloc(VALUE klass);
static void ossl_cipher_free(void *ptr);

static const rb_data_type_t ossl_cipher_type = {
    "OpenSSL/Cipher",
    {
        0, ossl_cipher_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

#ifdef OSSL_USE_PROVIDER
static void
ossl_evp_cipher_free(void *ptr)
{
    // This is safe to call against const EVP_CIPHER * returned by
    // EVP_get_cipherbyname()
    EVP_CIPHER_free(ptr);
}

static const rb_data_type_t ossl_evp_cipher_holder_type = {
    "OpenSSL/EVP_CIPHER",
    {
        .dfree = ossl_evp_cipher_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};
#endif

/*
 * PUBLIC
 */
const EVP_CIPHER *
ossl_evp_cipher_fetch(VALUE obj, volatile VALUE *holder)
{
    *holder = Qnil;
    if (rb_obj_is_kind_of(obj, cCipher)) {
        EVP_CIPHER_CTX *ctx;
        GetCipher(obj, ctx);
        EVP_CIPHER *cipher = (EVP_CIPHER *)EVP_CIPHER_CTX_cipher(ctx);
#ifdef OSSL_USE_PROVIDER
        *holder = TypedData_Wrap_Struct(0, &ossl_evp_cipher_holder_type, NULL);
        if (!EVP_CIPHER_up_ref(cipher))
            ossl_raise(eCipherError, "EVP_CIPHER_up_ref");
        RTYPEDDATA_DATA(*holder) = cipher;
#endif
        return cipher;
    }

    const char *name = StringValueCStr(obj);
    EVP_CIPHER *cipher = (EVP_CIPHER *)EVP_get_cipherbyname(name);
#ifdef OSSL_USE_PROVIDER
    if (!cipher) {
        ossl_clear_error();
        *holder = TypedData_Wrap_Struct(0, &ossl_evp_cipher_holder_type, NULL);
        cipher = EVP_CIPHER_fetch(NULL, name, NULL);
        RTYPEDDATA_DATA(*holder) = cipher;
    }
#endif
    if (!cipher)
        ossl_raise(eCipherError, "unsupported cipher algorithm: %"PRIsVALUE,
                   obj);
    return cipher;
}

VALUE
ossl_cipher_new(const EVP_CIPHER *cipher)
{
    VALUE ret;
    EVP_CIPHER_CTX *ctx;

    // NOTE: This does not set id_cipher_holder because this function should
    // only be called from ossl_engine.c, which will not use any
    // reference-counted ciphers.
    ret = ossl_cipher_alloc(cCipher);
    AllocCipher(ret, ctx);
    if (EVP_CipherInit_ex(ctx, cipher, NULL, NULL, NULL, -1) != 1)
        ossl_raise(eCipherError, NULL);

    return ret;
}

/*
 * PRIVATE
 */
static void
ossl_cipher_free(void *ptr)
{
    EVP_CIPHER_CTX_free(ptr);
}

static VALUE
ossl_cipher_alloc(VALUE klass)
{
    return NewCipher(klass);
}

/*
 *  call-seq:
 *     Cipher.new(string) -> cipher
 *
 *  The string must contain a valid cipher name like "aes-256-cbc".
 *
 *  A list of cipher names is available by calling OpenSSL::Cipher.ciphers.
 */
static VALUE
ossl_cipher_initialize(VALUE self, VALUE str)
{
    EVP_CIPHER_CTX *ctx;
    const EVP_CIPHER *cipher;
    VALUE cipher_holder;

    GetCipherInit(self, ctx);
    if (ctx) {
        ossl_raise(rb_eRuntimeError, "Cipher already initialized!");
    }
    cipher = ossl_evp_cipher_fetch(str, &cipher_holder);
    AllocCipher(self, ctx);
    if (EVP_CipherInit_ex(ctx, cipher, NULL, NULL, NULL, -1) != 1)
        ossl_raise(eCipherError, "EVP_CipherInit_ex");
    rb_ivar_set(self, id_cipher_holder, cipher_holder);

    return self;
}

/* :nodoc: */
static VALUE
ossl_cipher_copy(VALUE self, VALUE other)
{
    EVP_CIPHER_CTX *ctx1, *ctx2;

    rb_check_frozen(self);
    if (self == other) return self;

    GetCipherInit(self, ctx1);
    if (!ctx1) {
        AllocCipher(self, ctx1);
    }
    GetCipher(other, ctx2);
    if (EVP_CIPHER_CTX_copy(ctx1, ctx2) != 1)
        ossl_raise(eCipherError, NULL);

    return self;
}

static void
add_cipher_name_to_ary(const OBJ_NAME *name, void *arg)
{
    VALUE ary = (VALUE)arg;
    rb_ary_push(ary, rb_str_new2(name->name));
}

/*
 *  call-seq:
 *     OpenSSL::Cipher.ciphers -> array[string...]
 *
 *  Returns the names of all available ciphers in an array.
 */
static VALUE
ossl_s_ciphers(VALUE self)
{
    VALUE ary;

    ary = rb_ary_new();
    OBJ_NAME_do_all_sorted(OBJ_NAME_TYPE_CIPHER_METH,
                           add_cipher_name_to_ary,
                           (void*)ary);

    return ary;
}

/*
 *  call-seq:
 *     cipher.reset -> self
 *
 *  Fully resets the internal state of the Cipher. By using this, the same
 *  Cipher instance may be used several times for encryption or decryption tasks.
 *
 *  Internally calls EVP_CipherInit_ex(ctx, NULL, NULL, NULL, NULL, -1).
 */
static VALUE
ossl_cipher_reset(VALUE self)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);
    if (EVP_CipherInit_ex(ctx, NULL, NULL, NULL, NULL, -1) != 1)
        ossl_raise(eCipherError, NULL);

    return self;
}

static VALUE
ossl_cipher_init(VALUE self, int enc)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);
    if (EVP_CipherInit_ex(ctx, NULL, NULL, NULL, NULL, enc) != 1) {
        ossl_raise(eCipherError, "EVP_CipherInit_ex");
    }

    rb_ivar_set(self, id_key_set, Qfalse);

    return self;
}

/*
 *  call-seq:
 *     cipher.encrypt -> self
 *
 *  Initializes the Cipher for encryption.
 *
 *  Make sure to call either #encrypt or #decrypt before using the Cipher for
 *  any operation or setting any parameters.
 *
 *  Internally calls EVP_CipherInit_ex(ctx, NULL, NULL, NULL, NULL, 1).
 */
static VALUE
ossl_cipher_encrypt(VALUE self)
{
    return ossl_cipher_init(self, 1);
}

/*
 *  call-seq:
 *     cipher.decrypt -> self
 *
 *  Initializes the Cipher for decryption.
 *
 *  Make sure to call either #encrypt or #decrypt before using the Cipher for
 *  any operation or setting any parameters.
 *
 *  Internally calls EVP_CipherInit_ex(ctx, NULL, NULL, NULL, NULL, 0).
 */
static VALUE
ossl_cipher_decrypt(VALUE self)
{
    return ossl_cipher_init(self, 0);
}

/*
 *  call-seq:
 *     cipher.pkcs5_keyivgen(pass, salt = nil, iterations = 2048, digest = "MD5") -> nil
 *
 *  Generates and sets the key/IV based on a password.
 *
 *  *WARNING*: This method is deprecated and should not be used. This method
 *  corresponds to EVP_BytesToKey(), a non-standard OpenSSL extension of the
 *  legacy PKCS #5 v1.5 key derivation function. See OpenSSL::KDF for other
 *  options to derive keys from passwords.
 *
 *  === Parameters
 *  * _salt_ must be an 8 byte string if provided.
 *  * _iterations_ is an integer with a default of 2048.
 *  * _digest_ is a Digest object that defaults to 'MD5'
 */
static VALUE
ossl_cipher_pkcs5_keyivgen(int argc, VALUE *argv, VALUE self)
{
    EVP_CIPHER_CTX *ctx;
    const EVP_MD *digest;
    VALUE vpass, vsalt, viter, vdigest, md_holder;
    unsigned char key[EVP_MAX_KEY_LENGTH], iv[EVP_MAX_IV_LENGTH], *salt = NULL;
    int iter;

    rb_scan_args(argc, argv, "13", &vpass, &vsalt, &viter, &vdigest);
    StringValue(vpass);
    if(!NIL_P(vsalt)){
        StringValue(vsalt);
        if(RSTRING_LEN(vsalt) != PKCS5_SALT_LEN)
            ossl_raise(eCipherError, "salt must be an 8-octet string");
        salt = (unsigned char *)RSTRING_PTR(vsalt);
    }
    iter = NIL_P(viter) ? 2048 : NUM2INT(viter);
    if (iter <= 0)
        rb_raise(rb_eArgError, "iterations must be a positive integer");
    digest = NIL_P(vdigest) ? EVP_md5() : ossl_evp_md_fetch(vdigest, &md_holder);
    GetCipher(self, ctx);
    EVP_BytesToKey(EVP_CIPHER_CTX_cipher(ctx), digest, salt,
                   (unsigned char *)RSTRING_PTR(vpass), RSTRING_LENINT(vpass), iter, key, iv);
    if (EVP_CipherInit_ex(ctx, NULL, NULL, key, iv, -1) != 1)
        ossl_raise(eCipherError, NULL);
    OPENSSL_cleanse(key, sizeof key);
    OPENSSL_cleanse(iv, sizeof iv);

    rb_ivar_set(self, id_key_set, Qtrue);

    return Qnil;
}

static int
ossl_cipher_update_long(EVP_CIPHER_CTX *ctx, unsigned char *out, long *out_len_ptr,
                        const unsigned char *in, long in_len)
{
    int out_part_len;
    int limit = INT_MAX / 2 + 1;
    long out_len = 0;

    do {
        int in_part_len = in_len > limit ? limit : (int)in_len;

        if (!EVP_CipherUpdate(ctx, out ? (out + out_len) : 0,
                              &out_part_len, in, in_part_len))
            return 0;

        out_len += out_part_len;
        in += in_part_len;
    } while ((in_len -= limit) > 0);

    if (out_len_ptr)
        *out_len_ptr = out_len;

    return 1;
}

/*
 *  call-seq:
 *     cipher.update(data [, buffer]) -> string or buffer
 *
 *  Encrypts data in a streaming fashion. Hand consecutive blocks of data
 *  to the #update method in order to encrypt it. Returns the encrypted
 *  data chunk. When done, the output of Cipher#final should be additionally
 *  added to the result.
 *
 *  If _buffer_ is given, the encryption/decryption result will be written to
 *  it. _buffer_ will be resized automatically.
 *
 *  *NOTE*: When decrypting using an AEAD cipher, the integrity of the output
 *  is not verified until #final has been called.
 */
static VALUE
ossl_cipher_update(int argc, VALUE *argv, VALUE self)
{
    EVP_CIPHER_CTX *ctx;
    unsigned char *in;
    long in_len, out_len;
    VALUE data, str;

    rb_scan_args(argc, argv, "11", &data, &str);

    if (!RTEST(rb_attr_get(self, id_key_set)))
        ossl_raise(eCipherError, "key not set");

    StringValue(data);
    in = (unsigned char *)RSTRING_PTR(data);
    in_len = RSTRING_LEN(data);
    GetCipher(self, ctx);

    /*
     * As of OpenSSL 3.2, there is no reliable way to determine the required
     * output buffer size for arbitrary cipher modes.
     * https://github.com/openssl/openssl/issues/22628
     *
     * in_len+block_size is usually sufficient, but AES key wrap with padding
     * ciphers require in_len+15 even though they have a block size of 8 bytes.
     *
     * Using EVP_MAX_BLOCK_LENGTH (32) as a safe upper bound for ciphers
     * currently implemented in OpenSSL, but this can change in the future.
     */
    if (in_len > LONG_MAX - EVP_MAX_BLOCK_LENGTH) {
        ossl_raise(rb_eRangeError,
                   "data too big to make output buffer: %ld bytes", in_len);
    }
    out_len = in_len + EVP_MAX_BLOCK_LENGTH;

    if (NIL_P(str)) {
        str = rb_str_new(0, out_len);
    } else {
        StringValue(str);
        if ((long)rb_str_capacity(str) >= out_len)
            rb_str_modify(str);
        else
            rb_str_modify_expand(str, out_len - RSTRING_LEN(str));
    }

    if (!ossl_cipher_update_long(ctx, (unsigned char *)RSTRING_PTR(str), &out_len, in, in_len))
        ossl_raise(eCipherError, NULL);
    assert(out_len <= RSTRING_LEN(str));
    rb_str_set_len(str, out_len);

    return str;
}

/*
 *  call-seq:
 *     cipher.final -> string
 *
 *  Returns the remaining data held in the cipher object. Further calls to
 *  Cipher#update or Cipher#final are invalid. This call should always
 *  be made as the last call of an encryption or decryption operation, after
 *  having fed the entire plaintext or ciphertext to the Cipher instance.
 *
 *  When encrypting using an AEAD cipher, the authentication tag can be
 *  retrieved by #auth_tag after #final has been called.
 *
 *  When decrypting using an AEAD cipher, this method will verify the integrity
 *  of the ciphertext and the associated data with the authentication tag,
 *  which must be set by #auth_tag= prior to calling this method.
 *  If the verification fails, CipherError will be raised.
 */
static VALUE
ossl_cipher_final(VALUE self)
{
    EVP_CIPHER_CTX *ctx;
    int out_len;
    VALUE str;

    GetCipher(self, ctx);
    str = rb_str_new(0, EVP_CIPHER_CTX_block_size(ctx));
    if (!EVP_CipherFinal_ex(ctx, (unsigned char *)RSTRING_PTR(str), &out_len)) {
        /* For AEAD ciphers, this is likely an authentication failure */
        if (EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER) {
            /* For AEAD ciphers, EVP_CipherFinal_ex failures are authentication tag verification failures */
            ossl_raise(eAuthTagError, "AEAD authentication tag verification failed");
        }
        else {
            /* For non-AEAD ciphers */
            ossl_raise(eCipherError, "cipher final failed");
        }
    }
    assert(out_len <= RSTRING_LEN(str));
    rb_str_set_len(str, out_len);

    return str;
}

/*
 *  call-seq:
 *     cipher.name -> string
 *
 *  Returns the short name of the cipher which may differ slightly from the
 *  original name provided.
 */
static VALUE
ossl_cipher_name(VALUE self)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);

    return rb_str_new2(EVP_CIPHER_name(EVP_CIPHER_CTX_cipher(ctx)));
}

/*
 *  call-seq:
 *     cipher.key = string
 *
 *  Sets the cipher key. To generate a key, you should either use a secure
 *  random byte string or, if the key is to be derived from a password, you
 *  should rely on PBKDF2 functionality provided by OpenSSL::PKCS5. To
 *  generate a secure random-based key, Cipher#random_key may be used.
 *
 *  Only call this method after calling Cipher#encrypt or Cipher#decrypt.
 *
 *  See also the man page EVP_CipherInit_ex(3).
 */
static VALUE
ossl_cipher_set_key(VALUE self, VALUE key)
{
    EVP_CIPHER_CTX *ctx;
    int key_len;

    StringValue(key);
    GetCipher(self, ctx);

    key_len = EVP_CIPHER_CTX_key_length(ctx);
    if (RSTRING_LEN(key) != key_len)
        ossl_raise(rb_eArgError, "key must be %d bytes", key_len);

    if (EVP_CipherInit_ex(ctx, NULL, NULL, (unsigned char *)RSTRING_PTR(key), NULL, -1) != 1)
        ossl_raise(eCipherError, NULL);

    rb_ivar_set(self, id_key_set, Qtrue);

    return key;
}

/*
 *  call-seq:
 *     cipher.iv = string
 *
 *  Sets the cipher IV. Please note that since you should never be using ECB
 *  mode, an IV is always explicitly required and should be set prior to
 *  encryption. The IV itself can be safely transmitted in public.
 *
 *  This method expects the String to have the length equal to #iv_len. To use
 *  a different IV length with an AEAD cipher, #iv_len= must be set prior to
 *  calling this method.
 *
 *  *NOTE*: In OpenSSL API conventions, the IV value may correspond to the
 *  "nonce" instead in some cipher modes. Refer to the OpenSSL man pages for
 *  details.
 *
 *  See also the man page EVP_CipherInit_ex(3).
 */
static VALUE
ossl_cipher_set_iv(VALUE self, VALUE iv)
{
    EVP_CIPHER_CTX *ctx;
    int iv_len = 0;

    StringValue(iv);
    GetCipher(self, ctx);

    if (EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER)
        iv_len = (int)(VALUE)EVP_CIPHER_CTX_get_app_data(ctx);
    if (!iv_len)
        iv_len = EVP_CIPHER_CTX_iv_length(ctx);
    if (RSTRING_LEN(iv) != iv_len)
        ossl_raise(rb_eArgError, "iv must be %d bytes", iv_len);

    if (EVP_CipherInit_ex(ctx, NULL, NULL, NULL, (unsigned char *)RSTRING_PTR(iv), -1) != 1)
        ossl_raise(eCipherError, NULL);

    return iv;
}

/*
 *  call-seq:
 *     cipher.authenticated? -> true | false
 *
 *  Indicates whether this Cipher instance uses an AEAD mode.
 */
static VALUE
ossl_cipher_is_authenticated(VALUE self)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);

    return (EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     cipher.auth_data = string
 *
 *  Sets additional authenticated data (AAD), also called associated data, for
 *  this Cipher. This method is available for AEAD ciphers.
 *
 *  The contents of this field should be non-sensitive data which will be
 *  added to the ciphertext to generate the authentication tag which validates
 *  the contents of the ciphertext.
 *
 *  This method must be called after #key= and #iv= have been set, but before
 *  starting actual encryption or decryption with #update. In some cipher modes,
 *  #auth_tag_len= and #ccm_data_len= may also need to be called before this
 *  method.
 *
 *  See also the "AEAD Interface" section of the man page EVP_EncryptInit(3).
 *  This method internally calls EVP_CipherUpdate() with the output buffer
 *  set to NULL.
 */
static VALUE
ossl_cipher_set_auth_data(VALUE self, VALUE data)
{
    EVP_CIPHER_CTX *ctx;
    unsigned char *in;
    long in_len, out_len;

    StringValue(data);

    in = (unsigned char *) RSTRING_PTR(data);
    in_len = RSTRING_LEN(data);

    GetCipher(self, ctx);
    if (!(EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER))
        ossl_raise(eCipherError, "AEAD not supported by this cipher");

    if (!ossl_cipher_update_long(ctx, NULL, &out_len, in, in_len))
        ossl_raise(eCipherError, "couldn't set additional authenticated data");

    return data;
}

/*
 *  call-seq:
 *     cipher.auth_tag(tag_len = 16) -> String
 *
 *  Gets the generated authentication tag. This method is available for AEAD
 *  ciphers, and should be called after encryption has been finalized by calling
 *  #final.
 *
 *  The returned tag will be _tag_len_ bytes long. Some cipher modes require
 *  the desired length in advance using a separate call to #auth_tag_len=,
 *  before starting encryption.
 *
 *  See also the "AEAD Interface" section of the man page EVP_EncryptInit(3).
 *  This method internally calls EVP_CIPHER_CTX_ctrl() with
 *  EVP_CTRL_AEAD_GET_TAG.
 */
static VALUE
ossl_cipher_get_auth_tag(int argc, VALUE *argv, VALUE self)
{
    VALUE vtag_len, ret;
    EVP_CIPHER_CTX *ctx;
    int tag_len = 16;

    rb_scan_args(argc, argv, "01", &vtag_len);
    if (NIL_P(vtag_len))
        vtag_len = rb_attr_get(self, id_auth_tag_len);
    if (!NIL_P(vtag_len))
        tag_len = NUM2INT(vtag_len);

    GetCipher(self, ctx);

    if (!(EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER))
        ossl_raise(eCipherError, "authentication tag not supported by this cipher");

    ret = rb_str_new(NULL, tag_len);
    if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, tag_len, RSTRING_PTR(ret)))
        ossl_raise(eCipherError, "retrieving the authentication tag failed");

    return ret;
}

/*
 *  call-seq:
 *     cipher.auth_tag = string
 *
 *  Sets the authentication tag to verify the integrity of the ciphertext.
 *
 *  The authentication tag must be set before #final is called. The tag is
 *  verified during the #final call.
 *
 *  Note that, for CCM mode and OCB mode, the expected length of the tag must
 *  be set before starting decryption by a separate call to #auth_tag_len=.
 *  The content of the tag can be provided at any time before #final is called.
 *
 *  *NOTE*: The caller must ensure that the String passed to this method has
 *  the desired length. Some cipher modes support variable tag lengths, and
 *  this method may accept a truncated tag without raising an exception.
 *
 *  See also the "AEAD Interface" section of the man page EVP_EncryptInit(3).
 *  This method internally calls EVP_CIPHER_CTX_ctrl() with
 *  EVP_CTRL_AEAD_SET_TAG.
 */
static VALUE
ossl_cipher_set_auth_tag(VALUE self, VALUE vtag)
{
    EVP_CIPHER_CTX *ctx;
    unsigned char *tag;
    int tag_len;

    StringValue(vtag);
    tag = (unsigned char *) RSTRING_PTR(vtag);
    tag_len = RSTRING_LENINT(vtag);

    GetCipher(self, ctx);
    if (!(EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER))
        ossl_raise(eCipherError, "authentication tag not supported by this cipher");

    if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, tag_len, tag))
        ossl_raise(eCipherError, "unable to set AEAD tag");

    return vtag;
}

/*
 *  call-seq:
 *     cipher.auth_tag_len = integer
 *
 *  Sets the length of the expected authentication tag for this Cipher. This
 *  method is available for some of AEAD ciphers that require the length to be
 *  set before starting encryption or decryption, such as CCM mode or OCB mode.
 *
 *  For CCM mode and OCB mode, the tag length must be set before #iv= is set.
 *
 *  See also the "AEAD Interface" section of the man page EVP_EncryptInit(3).
 *  This method internally calls EVP_CIPHER_CTX_ctrl() with
 *  EVP_CTRL_AEAD_SET_TAG and a NULL buffer.
 */
static VALUE
ossl_cipher_set_auth_tag_len(VALUE self, VALUE vlen)
{
    int tag_len = NUM2INT(vlen);
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);
    if (!(EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER))
        ossl_raise(eCipherError, "AEAD not supported by this cipher");

    if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, tag_len, NULL))
        ossl_raise(eCipherError, "unable to set authentication tag length");

    /* for #auth_tag */
    rb_ivar_set(self, id_auth_tag_len, INT2NUM(tag_len));

    return vlen;
}

/*
 * call-seq:
 *    cipher.iv_len = integer
 *
 * Sets the IV/nonce length for this Cipher. This method is available for AEAD
 * ciphers that support variable IV lengths. This method can be called if a
 * different IV length than OpenSSL's default is desired, prior to calling
 * #iv=.
 *
 * See also the "AEAD Interface" section of the man page EVP_EncryptInit(3).
 * This method internally calls EVP_CIPHER_CTX_ctrl() with
 * EVP_CTRL_AEAD_SET_IVLEN.
 */
static VALUE
ossl_cipher_set_iv_length(VALUE self, VALUE iv_length)
{
    int len = NUM2INT(iv_length);
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);
    if (!(EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER))
        ossl_raise(eCipherError, "cipher does not support AEAD");

    if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, len, NULL))
        ossl_raise(eCipherError, "unable to set IV length");

    /*
     * EVP_CIPHER_CTX_iv_length() returns the default length. So we need to save
     * the length somewhere. Luckily currently we aren't using app_data.
     */
    EVP_CIPHER_CTX_set_app_data(ctx, (void *)(VALUE)len);

    return iv_length;
}

/*
 *  call-seq:
 *     cipher.key_len = integer
 *
 *  Sets the key length of the cipher.  If the cipher is a fixed length cipher
 *  then attempting to set the key length to any value other than the fixed
 *  value is an error.
 *
 *  Under normal circumstances you do not need to call this method (and
 *  probably shouldn't).
 *
 *  See EVP_CIPHER_CTX_set_key_length for further information.
 */
static VALUE
ossl_cipher_set_key_length(VALUE self, VALUE key_length)
{
    int len = NUM2INT(key_length);
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);
    if (EVP_CIPHER_CTX_set_key_length(ctx, len) != 1)
        ossl_raise(eCipherError, NULL);

    return key_length;
}

// TODO: Should #padding= take a boolean value instead?
/*
 *  call-seq:
 *     cipher.padding = 1 or 0
 *
 *  Enables or disables padding. By default encryption operations are padded
 *  using standard block padding and the padding is checked and removed when
 *  decrypting. If the pad parameter is zero then no padding is performed, the
 *  total amount of data encrypted or decrypted must then be a multiple of the
 *  block size or an error will occur.
 *
 *  See EVP_CIPHER_CTX_set_padding for further information.
 */
static VALUE
ossl_cipher_set_padding(VALUE self, VALUE padding)
{
    EVP_CIPHER_CTX *ctx;
    int pad = NUM2INT(padding);

    GetCipher(self, ctx);
    if (EVP_CIPHER_CTX_set_padding(ctx, pad) != 1)
        ossl_raise(eCipherError, NULL);
    return padding;
}

/*
 *  call-seq:
 *     cipher.key_len -> integer
 *
 *  Returns the key length in bytes of the Cipher.
 */
static VALUE
ossl_cipher_key_length(VALUE self)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);

    return INT2NUM(EVP_CIPHER_CTX_key_length(ctx));
}

/*
 *  call-seq:
 *     cipher.iv_len -> integer
 *
 *  Returns the expected length in bytes for an IV for this Cipher.
 */
static VALUE
ossl_cipher_iv_length(VALUE self)
{
    EVP_CIPHER_CTX *ctx;
    int len = 0;

    GetCipher(self, ctx);
    if (EVP_CIPHER_flags(EVP_CIPHER_CTX_cipher(ctx)) & EVP_CIPH_FLAG_AEAD_CIPHER)
        len = (int)(VALUE)EVP_CIPHER_CTX_get_app_data(ctx);
    if (!len)
        len = EVP_CIPHER_CTX_iv_length(ctx);

    return INT2NUM(len);
}

/*
 *  call-seq:
 *     cipher.block_size -> integer
 *
 *  Returns the size in bytes of the blocks on which this Cipher operates on.
 */
static VALUE
ossl_cipher_block_size(VALUE self)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);

    return INT2NUM(EVP_CIPHER_CTX_block_size(ctx));
}

/*
 *  call-seq:
 *     cipher.ccm_data_len = integer
 *
 *  Sets the total length of the plaintext / ciphertext message that will be
 *  processed by #update in CCM mode.
 *
 *  Make sure to call this method after #key= and #iv= have been set, and
 *  before #auth_data= or #update are called.
 *
 *  This method is only available for CCM mode ciphers.
 *
 *  See also the "AEAD Interface" section of the man page EVP_EncryptInit(3).
 */
static VALUE
ossl_cipher_set_ccm_data_len(VALUE self, VALUE data_len)
{
    int in_len, out_len;
    EVP_CIPHER_CTX *ctx;

    in_len = NUM2INT(data_len);

    GetCipher(self, ctx);
    if (EVP_CipherUpdate(ctx, NULL, &out_len, NULL, in_len) != 1)
        ossl_raise(eCipherError, NULL);

    return data_len;
}

/*
 * INIT
 */
void
Init_ossl_cipher(void)
{
    /* Document-class: OpenSSL::Cipher
     *
     * Provides symmetric algorithms for encryption and decryption. The
     * algorithms that are available depend on the particular version
     * of OpenSSL that is installed.
     *
     * === Listing all supported algorithms
     *
     * A list of supported algorithms can be obtained by
     *
     *   puts OpenSSL::Cipher.ciphers
     *
     * === Instantiating a Cipher
     *
     * There are several ways to create a Cipher instance. Generally, a
     * Cipher algorithm is categorized by its name, the key length in bits
     * and the cipher mode to be used. The most generic way to create a
     * Cipher is the following
     *
     *   cipher = OpenSSL::Cipher.new('<name>-<key length>-<mode>')
     *
     * That is, a string consisting of the hyphenated concatenation of the
     * individual components name, key length and mode. Either all uppercase
     * or all lowercase strings may be used, for example:
     *
     *  cipher = OpenSSL::Cipher.new('aes-128-cbc')
     *
     * === Choosing either encryption or decryption mode
     *
     * Encryption and decryption are often very similar operations for
     * symmetric algorithms, this is reflected by not having to choose
     * different classes for either operation, both can be done using the
     * same class. Still, after obtaining a Cipher instance, we need to
     * tell the instance what it is that we intend to do with it, so we
     * need to call either
     *
     *   cipher.encrypt
     *
     * or
     *
     *   cipher.decrypt
     *
     * on the Cipher instance. This should be the first call after creating
     * the instance, otherwise configuration that has already been set could
     * get lost in the process.
     *
     * === Choosing a key
     *
     * Symmetric encryption requires a key that is the same for the encrypting
     * and for the decrypting party and after initial key establishment should
     * be kept as private information. There are a lot of ways to create
     * insecure keys, the most notable is to simply take a password as the key
     * without processing the password further. A simple and secure way to
     * create a key for a particular Cipher is
     *
     *  cipher = OpenSSL::Cipher.new('aes-256-cfb')
     *  cipher.encrypt
     *  key = cipher.random_key # also sets the generated key on the Cipher
     *
     * If you absolutely need to use passwords as encryption keys, you
     * should use Password-Based Key Derivation Function 2 (PBKDF2) by
     * generating the key with the help of the functionality provided by
     * OpenSSL::PKCS5.pbkdf2_hmac_sha1 or OpenSSL::PKCS5.pbkdf2_hmac.
     *
     * Although there is Cipher#pkcs5_keyivgen, its use is deprecated and
     * it should only be used in legacy applications because it does not use
     * the newer PKCS#5 v2 algorithms.
     *
     * === Choosing an IV
     *
     * The cipher modes CBC, CFB, OFB and CTR all need an "initialization
     * vector", or short, IV. ECB mode is the only mode that does not require
     * an IV, but there is almost no legitimate use case for this mode
     * because of the fact that it does not sufficiently hide plaintext
     * patterns. Therefore
     *
     * <b>You should never use ECB mode unless you are absolutely sure that
     * you absolutely need it</b>
     *
     * Because of this, you will end up with a mode that explicitly requires
     * an IV in any case. Although the IV can be seen as public information,
     * i.e. it may be transmitted in public once generated, it should still
     * stay unpredictable to prevent certain kinds of attacks. Therefore,
     * ideally
     *
     * <b>Always create a secure random IV for every encryption of your
     * Cipher</b>
     *
     * A new, random IV should be created for every encryption of data. Think
     * of the IV as a nonce (number used once) - it's public but random and
     * unpredictable. A secure random IV can be created as follows
     *
     *   cipher = ...
     *   cipher.encrypt
     *   key = cipher.random_key
     *   iv = cipher.random_iv # also sets the generated IV on the Cipher
     *
     * Although the key is generally a random value, too, it is a bad choice
     * as an IV. There are elaborate ways how an attacker can take advantage
     * of such an IV. As a general rule of thumb, exposing the key directly
     * or indirectly should be avoided at all cost and exceptions only be
     * made with good reason.
     *
     * === Calling Cipher#final
     *
     * ECB (which should not be used) and CBC are both block-based modes.
     * This means that unlike for the other streaming-based modes, they
     * operate on fixed-size blocks of data, and therefore they require a
     * "finalization" step to produce or correctly decrypt the last block of
     * data by appropriately handling some form of padding. Therefore it is
     * essential to add the output of OpenSSL::Cipher#final to your
     * encryption/decryption buffer or you will end up with decryption errors
     * or truncated data.
     *
     * Although this is not really necessary for streaming-mode ciphers, it is
     * still recommended to apply the same pattern of adding the output of
     * Cipher#final there as well - it also enables you to switch between
     * modes more easily in the future.
     *
     * === Encrypting and decrypting some data
     *
     *   data = "Very, very confidential data"
     *
     *   cipher = OpenSSL::Cipher.new('aes-128-cbc')
     *   cipher.encrypt
     *   key = cipher.random_key
     *   iv = cipher.random_iv
     *
     *   encrypted = cipher.update(data) + cipher.final
     *   ...
     *   decipher = OpenSSL::Cipher.new('aes-128-cbc')
     *   decipher.decrypt
     *   decipher.key = key
     *   decipher.iv = iv
     *
     *   plain = decipher.update(encrypted) + decipher.final
     *
     *   puts data == plain #=> true
     *
     * === Authenticated Encryption and Associated Data (AEAD)
     *
     * If the OpenSSL version used supports it, an Authenticated Encryption
     * mode (such as GCM or CCM) should always be preferred over any
     * unauthenticated mode. Currently, OpenSSL supports AE only in combination
     * with Associated Data (AEAD) where additional associated data is included
     * in the encryption process to compute a tag at the end of the encryption.
     * This tag will also be used in the decryption process and by verifying
     * its validity, the authenticity of a given ciphertext is established.
     *
     * This is superior to unauthenticated modes in that it allows to detect
     * if somebody effectively changed the ciphertext after it had been
     * encrypted. This prevents malicious modifications of the ciphertext that
     * could otherwise be exploited to modify ciphertexts in ways beneficial to
     * potential attackers.
     *
     * Associated data, also called additional authenticated data (AAD), is
     * optionally used where there is additional information, such as
     * headers or some metadata, that must be also authenticated but not
     * necessarily need to be encrypted.
     *
     * An example using the GCM (Galois/Counter Mode). You have 16 bytes _key_,
     * 12 bytes (96 bits) _nonce_ and the associated data _auth_data_. Be sure
     * not to reuse the _key_ and _nonce_ pair. Reusing an nonce ruins the
     * security guarantees of GCM mode.
     *
     *   key = OpenSSL::Random.random_bytes(16)
     *   nonce = OpenSSL::Random.random_bytes(12)
     *   auth_data = "authenticated but unencrypted data"
     *   data = "encrypted data"
     *
     *   cipher = OpenSSL::Cipher.new('aes-128-gcm').encrypt
     *   cipher.key = key
     *   cipher.iv = nonce
     *   cipher.auth_data = auth_data
     *
     *   encrypted = cipher.update(data) + cipher.final
     *   tag = cipher.auth_tag(16)
     *
     * Now you are the receiver. You know the _key_ and have received _nonce_,
     * _auth_data_, _encrypted_ and _tag_ through an untrusted network. Note
     * that GCM accepts an arbitrary length tag between 1 and 16 bytes. You may
     * additionally need to check that the received tag has the correct length,
     * or you allow attackers to forge a valid single byte tag for the tampered
     * ciphertext with a probability of 1/256.
     *
     *   raise "tag is truncated!" unless tag.bytesize == 16
     *   decipher = OpenSSL::Cipher.new('aes-128-gcm').decrypt
     *   decipher.key = key
     *   decipher.iv = nonce
     *   decipher.auth_tag = tag # could be called at any time before #final
     *   decipher.auth_data = auth_data
     *
     *   decrypted = decipher.update(encrypted) + decipher.final
     *
     *   puts data == decrypted #=> true
     *
     * Note that other AEAD ciphers may require additional steps, such as
     * setting the expected tag length (#auth_tag_len=) or the total data
     * length (#ccm_data_len=) in advance. Make sure to read the relevant man
     * page for details.
     */
    cCipher = rb_define_class_under(mOSSL, "Cipher", rb_cObject);
    eCipherError = rb_define_class_under(cCipher, "CipherError", eOSSLError);
    eAuthTagError = rb_define_class_under(cCipher, "AuthTagError", eCipherError);

    rb_define_alloc_func(cCipher, ossl_cipher_alloc);
    rb_define_method(cCipher, "initialize_copy", ossl_cipher_copy, 1);
    rb_define_module_function(cCipher, "ciphers", ossl_s_ciphers, 0);
    rb_define_method(cCipher, "initialize", ossl_cipher_initialize, 1);
    rb_define_method(cCipher, "reset", ossl_cipher_reset, 0);
    rb_define_method(cCipher, "encrypt", ossl_cipher_encrypt, 0);
    rb_define_method(cCipher, "decrypt", ossl_cipher_decrypt, 0);
    rb_define_method(cCipher, "pkcs5_keyivgen", ossl_cipher_pkcs5_keyivgen, -1);
    rb_define_method(cCipher, "update", ossl_cipher_update, -1);
    rb_define_method(cCipher, "final", ossl_cipher_final, 0);
    rb_define_method(cCipher, "name", ossl_cipher_name, 0);
    rb_define_method(cCipher, "key=", ossl_cipher_set_key, 1);
    rb_define_method(cCipher, "auth_data=", ossl_cipher_set_auth_data, 1);
    rb_define_method(cCipher, "auth_tag=", ossl_cipher_set_auth_tag, 1);
    rb_define_method(cCipher, "auth_tag", ossl_cipher_get_auth_tag, -1);
    rb_define_method(cCipher, "auth_tag_len=", ossl_cipher_set_auth_tag_len, 1);
    rb_define_method(cCipher, "authenticated?", ossl_cipher_is_authenticated, 0);
    rb_define_method(cCipher, "key_len=", ossl_cipher_set_key_length, 1);
    rb_define_method(cCipher, "key_len", ossl_cipher_key_length, 0);
    rb_define_method(cCipher, "iv=", ossl_cipher_set_iv, 1);
    rb_define_method(cCipher, "iv_len=", ossl_cipher_set_iv_length, 1);
    rb_define_method(cCipher, "iv_len", ossl_cipher_iv_length, 0);
    rb_define_method(cCipher, "block_size", ossl_cipher_block_size, 0);
    rb_define_method(cCipher, "padding=", ossl_cipher_set_padding, 1);
    rb_define_method(cCipher, "ccm_data_len=", ossl_cipher_set_ccm_data_len, 1);

    id_auth_tag_len = rb_intern_const("auth_tag_len");
    id_key_set = rb_intern_const("key_set");
    id_cipher_holder = rb_intern_const("EVP_CIPHER_holder");
}
