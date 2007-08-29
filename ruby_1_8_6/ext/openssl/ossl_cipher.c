/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#define MakeCipher(obj, klass, ctx) \
    obj = Data_Make_Struct(klass, EVP_CIPHER_CTX, 0, ossl_cipher_free, ctx)
#define GetCipher(obj, ctx) do { \
    Data_Get_Struct(obj, EVP_CIPHER_CTX, ctx); \
    if (!ctx) { \
	ossl_raise(rb_eRuntimeError, "Cipher not inititalized!"); \
    } \
} while (0)
#define SafeGetCipher(obj, ctx) do { \
    OSSL_Check_Kind(obj, cCipher); \
    GetCipher(obj, ctx); \
} while (0)

/*
 * Classes
 */
VALUE mCipher;
VALUE cCipher;
VALUE eCipherError;

static VALUE ossl_cipher_alloc(VALUE klass);

/*
 * PUBLIC
 */
const EVP_CIPHER *
GetCipherPtr(VALUE obj)
{
    EVP_CIPHER_CTX *ctx;

    SafeGetCipher(obj, ctx);

    return EVP_CIPHER_CTX_cipher(ctx);
}

VALUE
ossl_cipher_new(const EVP_CIPHER *cipher)
{
    VALUE ret;
    EVP_CIPHER_CTX *ctx;

    ret = ossl_cipher_alloc(cCipher);
    GetCipher(ret, ctx);
    EVP_CIPHER_CTX_init(ctx);
    if (EVP_CipherInit_ex(ctx, cipher, NULL, NULL, NULL, -1) != 1)
	ossl_raise(eCipherError, NULL);

    return ret;
}

/*
 * PRIVATE
 */
static void
ossl_cipher_free(EVP_CIPHER_CTX *ctx)
{
    if (ctx) {
	EVP_CIPHER_CTX_cleanup(ctx);
	free(ctx);
    }
}

static VALUE
ossl_cipher_alloc(VALUE klass)
{
    EVP_CIPHER_CTX *ctx;
    VALUE obj;

    MakeCipher(obj, klass, ctx);
    EVP_CIPHER_CTX_init(ctx);
	
    return obj;
}

static VALUE
ossl_cipher_initialize(VALUE self, VALUE str)
{
    EVP_CIPHER_CTX *ctx;
    const EVP_CIPHER *cipher;
    char *name;

    name = StringValuePtr(str);
    GetCipher(self, ctx);
    if (!(cipher = EVP_get_cipherbyname(name))) {
	ossl_raise(rb_eRuntimeError, "unsupported cipher algorithm (%s)", name);
    }
    if (EVP_CipherInit_ex(ctx, cipher, NULL, NULL, NULL, -1) != 1)
	ossl_raise(eCipherError, NULL);

    return self;
}
static VALUE
ossl_cipher_copy(VALUE self, VALUE other)
{
    EVP_CIPHER_CTX *ctx1, *ctx2;
	
    rb_check_frozen(self);
    if (self == other) return self;

    GetCipher(self, ctx1);
    SafeGetCipher(other, ctx2);
    if (EVP_CIPHER_CTX_copy(ctx1, ctx2) != 1)
	ossl_raise(eCipherError, NULL);

    return self;
}

static void*
add_cipher_name_to_ary(const OBJ_NAME *name, VALUE ary)
{
    rb_ary_push(ary, rb_str_new2(name->name));
    return NULL;
}

static VALUE
ossl_s_ciphers(VALUE self)
{
#ifdef HAVE_OBJ_NAME_DO_ALL_SORTED
    VALUE ary;

    ary = rb_ary_new();
    OBJ_NAME_do_all_sorted(OBJ_NAME_TYPE_CIPHER_METH,
                    (void(*)(const OBJ_NAME*,void*))add_cipher_name_to_ary,
                    (void*)ary);

    return ary;
#else
    rb_notimplement();
#endif
}

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
ossl_cipher_init(int argc, VALUE *argv, VALUE self, int mode)
{
    EVP_CIPHER_CTX *ctx;
    unsigned char key[EVP_MAX_KEY_LENGTH], *p_key = NULL;
    unsigned char iv[EVP_MAX_IV_LENGTH], *p_iv = NULL;
    VALUE pass, init_v;

    if(rb_scan_args(argc, argv, "02", &pass, &init_v) > 0){
	/*
	 * oops. this code mistakes salt for IV.
	 * We deprecated the arguments for this method, but we decided
	 * keeping this behaviour for backward compatibility.
	 */
	StringValue(pass);
	GetCipher(self, ctx);
	if (NIL_P(init_v)) memcpy(iv, "OpenSSL for Ruby rulez!", sizeof(iv));
	else{
	    char *cname  = rb_class2name(rb_obj_class(self));
	    rb_warning("key derivation by %s#encrypt is deprecated; "
		       "use %s::pkcs5_keyivgen instead", cname, cname);
	    StringValue(init_v);
	    if (EVP_MAX_IV_LENGTH > RSTRING(init_v)->len) {
		memset(iv, 0, EVP_MAX_IV_LENGTH);
		memcpy(iv, RSTRING(init_v)->ptr, RSTRING(init_v)->len);
	    }
	    else memcpy(iv, RSTRING(init_v)->ptr, sizeof(iv));
	}
	EVP_BytesToKey(EVP_CIPHER_CTX_cipher(ctx), EVP_md5(), iv,
		       RSTRING(pass)->ptr, RSTRING(pass)->len, 1, key, NULL);
	p_key = key;
	p_iv = iv;
    }
    else {
	GetCipher(self, ctx);
    }
    if (EVP_CipherInit_ex(ctx, NULL, NULL, p_key, p_iv, mode) != 1) {
	ossl_raise(eCipherError, NULL);
    }

    return self;
}

static VALUE
ossl_cipher_encrypt(int argc, VALUE *argv, VALUE self)
{
    return ossl_cipher_init(argc, argv, self, 1);
}

static VALUE
ossl_cipher_decrypt(int argc, VALUE *argv, VALUE self)
{
    return ossl_cipher_init(argc, argv, self, 0);
}

static VALUE
ossl_cipher_pkcs5_keyivgen(int argc, VALUE *argv, VALUE self)
{
    EVP_CIPHER_CTX *ctx;
    const EVP_MD *digest;
    VALUE vpass, vsalt, viter, vdigest;
    unsigned char key[EVP_MAX_KEY_LENGTH], iv[EVP_MAX_IV_LENGTH], *salt = NULL;
    int iter;

    rb_scan_args(argc, argv, "13", &vpass, &vsalt, &viter, &vdigest);
    StringValue(vpass);
    if(!NIL_P(vsalt)){
	StringValue(vsalt);
	if(RSTRING(vsalt)->len != PKCS5_SALT_LEN)
	    rb_raise(eCipherError, "salt must be an 8-octet string");
	salt = RSTRING(vsalt)->ptr;
    }
    iter = NIL_P(viter) ? 2048 : NUM2INT(viter);
    digest = NIL_P(vdigest) ? EVP_md5() : GetDigestPtr(vdigest);
    GetCipher(self, ctx);
    EVP_BytesToKey(EVP_CIPHER_CTX_cipher(ctx), digest, salt,
		   RSTRING(vpass)->ptr, RSTRING(vpass)->len, iter, key, iv); 
    if (EVP_CipherInit_ex(ctx, NULL, NULL, key, iv, -1) != 1)
	ossl_raise(eCipherError, NULL);
    OPENSSL_cleanse(key, sizeof key);
    OPENSSL_cleanse(iv, sizeof iv);

    return Qnil;
}

static VALUE 
ossl_cipher_update(VALUE self, VALUE data)
{
    EVP_CIPHER_CTX *ctx;
    char *in;
    int in_len, out_len;
    VALUE str;

    StringValue(data);
    in = RSTRING(data)->ptr;
    if ((in_len = RSTRING(data)->len) == 0)
        rb_raise(rb_eArgError, "data must not be empty");
    GetCipher(self, ctx);
    str = rb_str_new(0, in_len+EVP_CIPHER_CTX_block_size(ctx));
    if (!EVP_CipherUpdate(ctx, RSTRING(str)->ptr, &out_len, in, in_len))
	ossl_raise(eCipherError, NULL);
    assert(out_len < RSTRING(str)->len);
    RSTRING(str)->len = out_len;
    RSTRING(str)->ptr[out_len] = 0;

    return str;
}

static VALUE
ossl_cipher_update_deprecated(VALUE self, VALUE data)
{
    char *cname;

    cname = rb_class2name(rb_obj_class(self));
    rb_warning("%s#<< is deprecated; use %s#update instead", cname, cname);
    return ossl_cipher_update(self, data);
}

static VALUE 
ossl_cipher_final(VALUE self)
{
    EVP_CIPHER_CTX *ctx;
    int out_len;
    VALUE str;

    GetCipher(self, ctx);
    str = rb_str_new(0, EVP_CIPHER_CTX_block_size(ctx));
    if (!EVP_CipherFinal_ex(ctx, RSTRING(str)->ptr, &out_len))
	ossl_raise(eCipherError, NULL);
    assert(out_len <= RSTRING(str)->len);
    RSTRING(str)->len = out_len;
    RSTRING(str)->ptr[out_len] = 0;

    return str;
}

static VALUE
ossl_cipher_name(VALUE self)
{
    EVP_CIPHER_CTX *ctx;

    GetCipher(self, ctx);

    return rb_str_new2(EVP_CIPHER_name(EVP_CIPHER_CTX_cipher(ctx)));
}

static VALUE
ossl_cipher_set_key(VALUE self, VALUE key)
{
    EVP_CIPHER_CTX *ctx;

    StringValue(key);
    GetCipher(self, ctx);

    if (RSTRING(key)->len < EVP_CIPHER_CTX_key_length(ctx))
        ossl_raise(eCipherError, "key length too short");

    if (EVP_CipherInit_ex(ctx, NULL, NULL, RSTRING(key)->ptr, NULL, -1) != 1)
        ossl_raise(eCipherError, NULL);

    return key;
}

static VALUE
ossl_cipher_set_iv(VALUE self, VALUE iv)
{
    EVP_CIPHER_CTX *ctx;

    StringValue(iv);
    GetCipher(self, ctx);

    if (RSTRING(iv)->len < EVP_CIPHER_CTX_iv_length(ctx))
        ossl_raise(eCipherError, "iv length too short");

    if (EVP_CipherInit_ex(ctx, NULL, NULL, NULL, RSTRING(iv)->ptr, -1) != 1)
	ossl_raise(eCipherError, NULL);

    return iv;
}

static VALUE
ossl_cipher_set_key_length(VALUE self, VALUE key_length)
{
    EVP_CIPHER_CTX *ctx;
    int len = NUM2INT(key_length);
 
    GetCipher(self, ctx);
    if (EVP_CIPHER_CTX_set_key_length(ctx, len) != 1)
        ossl_raise(eCipherError, NULL);

    return key_length;
}

static VALUE
ossl_cipher_set_padding(VALUE self, VALUE padding)
{
#if defined(HAVE_EVP_CIPHER_CTX_SET_PADDING)
    EVP_CIPHER_CTX *ctx;
    int pad = NUM2INT(padding);

    GetCipher(self, ctx);
    if (EVP_CIPHER_CTX_set_padding(ctx, pad) != 1)
	ossl_raise(eCipherError, NULL);
#else
    rb_notimplement();
#endif
    return padding;
}

#define CIPHER_0ARG_INT(func)					\
    static VALUE						\
    ossl_cipher_##func(VALUE self)				\
    {								\
	EVP_CIPHER_CTX *ctx;					\
	GetCipher(self, ctx);					\
	return INT2NUM(EVP_CIPHER_##func(EVP_CIPHER_CTX_cipher(ctx)));	\
    }
CIPHER_0ARG_INT(key_length)
CIPHER_0ARG_INT(iv_length)
CIPHER_0ARG_INT(block_size)

/*
 * INIT
 */
void 
Init_ossl_cipher(void)
{
#if 0 /* let rdoc know about mOSSL */
    mOSSL = rb_define_module("OpenSSL");
#endif

    mCipher = rb_define_module_under(mOSSL, "Cipher");
    eCipherError = rb_define_class_under(mOSSL, "CipherError", eOSSLError);
    cCipher = rb_define_class_under(mCipher, "Cipher", rb_cObject);

    rb_define_alloc_func(cCipher, ossl_cipher_alloc);
    rb_define_copy_func(cCipher, ossl_cipher_copy);
    rb_define_module_function(mCipher, "ciphers", ossl_s_ciphers, 0);
    rb_define_method(cCipher, "initialize", ossl_cipher_initialize, 1);
    rb_define_method(cCipher, "reset", ossl_cipher_reset, 0);
    rb_define_method(cCipher, "encrypt", ossl_cipher_encrypt, -1);
    rb_define_method(cCipher, "decrypt", ossl_cipher_decrypt, -1);
    rb_define_method(cCipher, "pkcs5_keyivgen", ossl_cipher_pkcs5_keyivgen, -1);
    rb_define_method(cCipher, "update", ossl_cipher_update, 1);
    rb_define_method(cCipher, "<<", ossl_cipher_update_deprecated, 1);
    rb_define_method(cCipher, "final", ossl_cipher_final, 0);
    rb_define_method(cCipher, "name", ossl_cipher_name, 0);
    rb_define_method(cCipher, "key=", ossl_cipher_set_key, 1);
    rb_define_method(cCipher, "key_len=", ossl_cipher_set_key_length, 1);
    rb_define_method(cCipher, "key_len", ossl_cipher_key_length, 0);
    rb_define_method(cCipher, "iv=", ossl_cipher_set_iv, 1);
    rb_define_method(cCipher, "iv_len", ossl_cipher_iv_length, 0);
    rb_define_method(cCipher, "block_size", ossl_cipher_block_size, 0);
    rb_define_method(cCipher, "padding=", ossl_cipher_set_padding, 1);
}
