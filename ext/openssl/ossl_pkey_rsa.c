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
#if !defined(OPENSSL_NO_RSA)

#include "ossl.h"

#define GetPKeyRSA(obj, pkey) do { \
    GetPKey(obj, pkey); \
    if (EVP_PKEY_type(pkey->type) != EVP_PKEY_RSA) { /* PARANOIA? */ \
	ossl_raise(rb_eRuntimeError, "THIS IS NOT A RSA!") ; \
    } \
} while (0)

#define RSA_HAS_PRIVATE(rsa) ((rsa)->p && (rsa)->q)
#define RSA_PRIVATE(obj,rsa) (RSA_HAS_PRIVATE(rsa)||OSSL_PKEY_IS_PRIVATE(obj))

/*
 * Classes
 */
VALUE cRSA;
VALUE eRSAError;

/*
 * Public
 */
static VALUE
rsa_instance(VALUE klass, RSA *rsa)
{
    EVP_PKEY *pkey;
    VALUE obj;

    if (!rsa) {
	return Qfalse;
    }
    if (!(pkey = EVP_PKEY_new())) {
	return Qfalse;
    }
    if (!EVP_PKEY_assign_RSA(pkey, rsa)) {
	EVP_PKEY_free(pkey);
	return Qfalse;
    }
    WrapPKey(klass, obj, pkey);

    return obj;
}

VALUE
ossl_rsa_new(EVP_PKEY *pkey)
{
    VALUE obj;

    if (!pkey) {
	obj = rsa_instance(cRSA, RSA_new());
    }
    else {
	if (EVP_PKEY_type(pkey->type) != EVP_PKEY_RSA) {
	    ossl_raise(rb_eTypeError, "Not a RSA key!");
	}
	WrapPKey(cRSA, obj, pkey);
    }
    if (obj == Qfalse) {
	ossl_raise(eRSAError, NULL);
    }

    return obj;
}

/*
 * Private
 */
static RSA *
rsa_generate(int size, int exp)
{
    return RSA_generate_key(size, exp,
	    rb_block_given_p() ? ossl_generate_cb : NULL,
	    NULL);
}

/*
 *  call-seq:
 *     RSA.generate(size [, exponent]) -> rsa
 *
 *  === Parameters
 *  * +size+ is an integer representing the desired key size.  Keys smaller than 1024 should be considered insecure.
 *  * +exponent+ is an odd number normally 3, 17, or 65537.
 *
 */
static VALUE
ossl_rsa_s_generate(int argc, VALUE *argv, VALUE klass)
{
/* why does this method exist?  why can't initialize take an optional exponent? */
    RSA *rsa;
    VALUE size, exp;
    VALUE obj;

    rb_scan_args(argc, argv, "11", &size, &exp);

    rsa = rsa_generate(NUM2INT(size), NIL_P(exp) ? RSA_F4 : NUM2INT(exp)); /* err handled by rsa_instance */
    obj = rsa_instance(klass, rsa);

    if (obj == Qfalse) {
	RSA_free(rsa);
	ossl_raise(eRSAError, NULL);
    }

    return obj;
}

/*
 *  call-seq:
 *     RSA.new([size | encoded_key] [, pass]) -> rsa
 *
 *  === Parameters
 *  * +size+ is an integer representing the desired key size.
 *  * +encoded_key+ is a string containing PEM or DER encoded key.
 *  * +pass+ is an optional string with the password to decrypt the encoded key.
 *
 *  === Examples
 *  * RSA.new(2048) -> rsa
 *  * RSA.new(File.read("rsa.pem")) -> rsa
 *  * RSA.new(File.read("rsa.pem"), "mypassword") -> rsa
 */
static VALUE
ossl_rsa_initialize(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    RSA *rsa;
    BIO *in;
    char *passwd = NULL;
    VALUE arg, pass;

    GetPKey(self, pkey);
    if(rb_scan_args(argc, argv, "02", &arg, &pass) == 0) {
	rsa = RSA_new();
    }
    else if (FIXNUM_P(arg)) {
	rsa = rsa_generate(FIX2INT(arg), NIL_P(pass) ? RSA_F4 : NUM2INT(pass));
	if (!rsa) ossl_raise(eRSAError, NULL);
    }
    else {
	if (!NIL_P(pass)) passwd = StringValuePtr(pass);
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(arg);
	rsa = PEM_read_bio_RSAPrivateKey(in, NULL, ossl_pem_passwd_cb, passwd);
	if (!rsa) {
	    (void)BIO_reset(in);
	    rsa = PEM_read_bio_RSAPublicKey(in, NULL, NULL, NULL);
	}
	if (!rsa) {
	    (void)BIO_reset(in);
	    rsa = PEM_read_bio_RSA_PUBKEY(in, NULL, NULL, NULL);
	}
	if (!rsa) {
	    (void)BIO_reset(in);
	    rsa = d2i_RSAPrivateKey_bio(in, NULL);
	}
	if (!rsa) {
	    (void)BIO_reset(in);
	    rsa = d2i_RSAPublicKey_bio(in, NULL);
	}
	if (!rsa) {
	    (void)BIO_reset(in);
	    rsa = d2i_RSA_PUBKEY_bio(in, NULL);
	}
	BIO_free(in);
	if (!rsa) ossl_raise(eRSAError, "Neither PUB key nor PRIV key:");
    }
    if (!EVP_PKEY_assign_RSA(pkey, rsa)) {
	RSA_free(rsa);
	ossl_raise(eRSAError, NULL);
    }

    return self;
}

/*
 *  call-seq:
 *     rsa.public? -> true
 *
 *  The return value is always true since every private key is also a public key.
 *
 */
static VALUE
ossl_rsa_is_public(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyRSA(self, pkey);
    /*
     * This method should check for n and e.  BUG.
     */
    return Qtrue;
}

/*
 *  call-seq:
 *     rsa.private? -> true | false
 *
 */
static VALUE
ossl_rsa_is_private(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyRSA(self, pkey);

    return (RSA_PRIVATE(self, pkey->pkey.rsa)) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     rsa.to_pem([cipher, pass]) -> aString
 *
 *  === Parameters
 *  * +cipher+ is a Cipher object.
 *  * +pass+ is a string.
 *
 *  === Examples
 *  * rsa.to_pem -> aString
 *  * rsa.to_pem(cipher, pass) -> aString
 */
static VALUE
ossl_rsa_export(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    BIO *out;
    const EVP_CIPHER *ciph = NULL;
    char *passwd = NULL;
    VALUE cipher, pass, str;

    GetPKeyRSA(self, pkey);

    rb_scan_args(argc, argv, "02", &cipher, &pass);

    if (!NIL_P(cipher)) {
	ciph = GetCipherPtr(cipher);
	if (!NIL_P(pass)) {
	    passwd = StringValuePtr(pass);
	}
    }
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eRSAError, NULL);
    }
    if (RSA_HAS_PRIVATE(pkey->pkey.rsa)) {
	if (!PEM_write_bio_RSAPrivateKey(out, pkey->pkey.rsa, ciph,
					 NULL, 0, ossl_pem_passwd_cb, passwd)) {
	    BIO_free(out);
	    ossl_raise(eRSAError, NULL);
	}
    } else {
	if (!PEM_write_bio_RSAPublicKey(out, pkey->pkey.rsa)) {
	    BIO_free(out);
	    ossl_raise(eRSAError, NULL);
	}
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 *  call-seq:
 *     rsa.to_der -> aString
 *
 */
static VALUE
ossl_rsa_to_der(VALUE self)
{
    EVP_PKEY *pkey;
    int (*i2d_func)_((const RSA*, unsigned char**));
    unsigned char *p;
    long len;
    VALUE str;

    GetPKeyRSA(self, pkey);
    if(RSA_HAS_PRIVATE(pkey->pkey.rsa))
	i2d_func = i2d_RSAPrivateKey;
    else
	i2d_func = i2d_RSAPublicKey;
    if((len = i2d_func(pkey->pkey.rsa, NULL)) <= 0)
	ossl_raise(eRSAError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_func(pkey->pkey.rsa, &p) < 0)
	ossl_raise(eRSAError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

#define ossl_rsa_buf_size(pkey) (RSA_size((pkey)->pkey.rsa)+16)

/*
 *  call-seq:
 *     rsa.public_encrypt(string [, padding]) -> aString
 *
 */
static VALUE
ossl_rsa_public_encrypt(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetPKeyRSA(self, pkey);
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, ossl_rsa_buf_size(pkey));
    buf_len = RSA_public_encrypt(RSTRING_LEN(buffer), (unsigned char *)RSTRING_PTR(buffer),
				 (unsigned char *)RSTRING_PTR(str), pkey->pkey.rsa,
				 pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 *  call-seq:
 *     rsa.public_decrypt(string [, padding]) -> aString
 *
 */
static VALUE
ossl_rsa_public_decrypt(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetPKeyRSA(self, pkey);
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, ossl_rsa_buf_size(pkey));
    buf_len = RSA_public_decrypt(RSTRING_LEN(buffer), (unsigned char *)RSTRING_PTR(buffer),
				 (unsigned char *)RSTRING_PTR(str), pkey->pkey.rsa,
				 pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 *  call-seq:
 *     rsa.private_encrypt(string [, padding]) -> aString
 *
 */
static VALUE
ossl_rsa_private_encrypt(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetPKeyRSA(self, pkey);
    if (!RSA_PRIVATE(self, pkey->pkey.rsa)) {
	ossl_raise(eRSAError, "private key needed.");
    }
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, ossl_rsa_buf_size(pkey));
    buf_len = RSA_private_encrypt(RSTRING_LEN(buffer), (unsigned char *)RSTRING_PTR(buffer),
				  (unsigned char *)RSTRING_PTR(str), pkey->pkey.rsa,
				  pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}


/*
 *  call-seq:
 *     rsa.private_decrypt(string [, padding]) -> aString
 *
 */
static VALUE
ossl_rsa_private_decrypt(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetPKeyRSA(self, pkey);
    if (!RSA_PRIVATE(self, pkey->pkey.rsa)) {
	ossl_raise(eRSAError, "private key needed.");
    }
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, ossl_rsa_buf_size(pkey));
    buf_len = RSA_private_decrypt(RSTRING_LEN(buffer), (unsigned char *)RSTRING_PTR(buffer),
				  (unsigned char *)RSTRING_PTR(str), pkey->pkey.rsa,
				  pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 *  call-seq:
 *     rsa.params -> hash
 *
 * Stores all parameters of key to the hash
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (I's up to you)
 */
static VALUE
ossl_rsa_get_params(VALUE self)
{
    EVP_PKEY *pkey;
    VALUE hash;

    GetPKeyRSA(self, pkey);

    hash = rb_hash_new();

    rb_hash_aset(hash, rb_str_new2("n"), ossl_bn_new(pkey->pkey.rsa->n));
    rb_hash_aset(hash, rb_str_new2("e"), ossl_bn_new(pkey->pkey.rsa->e));
    rb_hash_aset(hash, rb_str_new2("d"), ossl_bn_new(pkey->pkey.rsa->d));
    rb_hash_aset(hash, rb_str_new2("p"), ossl_bn_new(pkey->pkey.rsa->p));
    rb_hash_aset(hash, rb_str_new2("q"), ossl_bn_new(pkey->pkey.rsa->q));
    rb_hash_aset(hash, rb_str_new2("dmp1"), ossl_bn_new(pkey->pkey.rsa->dmp1));
    rb_hash_aset(hash, rb_str_new2("dmq1"), ossl_bn_new(pkey->pkey.rsa->dmq1));
    rb_hash_aset(hash, rb_str_new2("iqmp"), ossl_bn_new(pkey->pkey.rsa->iqmp));

    return hash;
}

/*
 *  call-seq:
 *     rsa.to_text -> aString
 *
 * Prints all parameters of key to buffer
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (It's up to you)
 */
static VALUE
ossl_rsa_to_text(VALUE self)
{
    EVP_PKEY *pkey;
    BIO *out;
    VALUE str;

    GetPKeyRSA(self, pkey);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eRSAError, NULL);
    }
    if (!RSA_print(out, pkey->pkey.rsa, 0)) { /* offset = 0 */
	BIO_free(out);
	ossl_raise(eRSAError, NULL);
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 *  call-seq:
 *     rsa.public_key -> aRSA
 *
 * Makes new instance RSA PUBLIC_KEY from PRIVATE_KEY
 */
static VALUE
ossl_rsa_to_public_key(VALUE self)
{
    EVP_PKEY *pkey;
    RSA *rsa;
    VALUE obj;

    GetPKeyRSA(self, pkey);
    /* err check performed by rsa_instance */
    rsa = RSAPublicKey_dup(pkey->pkey.rsa);
    obj = rsa_instance(CLASS_OF(self), rsa);
    if (obj == Qfalse) {
	RSA_free(rsa);
	ossl_raise(eRSAError, NULL);
    }
    return obj;
}

/*
 * TODO: Test me

static VALUE
ossl_rsa_blinding_on(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyRSA(self, pkey);

    if (RSA_blinding_on(pkey->pkey.rsa, ossl_bn_ctx) != 1) {
	ossl_raise(eRSAError, NULL);
    }
    return self;
}

static VALUE
ossl_rsa_blinding_off(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyRSA(self, pkey);
    RSA_blinding_off(pkey->pkey.rsa);

    return self;
}
 */

OSSL_PKEY_BN(rsa, n)
OSSL_PKEY_BN(rsa, e)
OSSL_PKEY_BN(rsa, d)
OSSL_PKEY_BN(rsa, p)
OSSL_PKEY_BN(rsa, q)
OSSL_PKEY_BN(rsa, dmp1)
OSSL_PKEY_BN(rsa, dmq1)
OSSL_PKEY_BN(rsa, iqmp)

/*
 * INIT
 */
#define DefRSAConst(x) rb_define_const(cRSA, #x,INT2FIX(RSA_##x))

void
Init_ossl_rsa()
{
#if 0 /* let rdoc know about mOSSL and mPKey */
    mOSSL = rb_define_module("OpenSSL");
    mPKey = rb_define_module_under(mOSSL, "PKey");
#endif

    eRSAError = rb_define_class_under(mPKey, "RSAError", ePKeyError);

    cRSA = rb_define_class_under(mPKey, "RSA", cPKey);

    rb_define_singleton_method(cRSA, "generate", ossl_rsa_s_generate, -1);
    rb_define_method(cRSA, "initialize", ossl_rsa_initialize, -1);

    rb_define_method(cRSA, "public?", ossl_rsa_is_public, 0);
    rb_define_method(cRSA, "private?", ossl_rsa_is_private, 0);
    rb_define_method(cRSA, "to_text", ossl_rsa_to_text, 0);
    rb_define_method(cRSA, "export", ossl_rsa_export, -1);
    rb_define_alias(cRSA, "to_pem", "export");
    rb_define_alias(cRSA, "to_s", "export");
    rb_define_method(cRSA, "to_der", ossl_rsa_to_der, 0);
    rb_define_method(cRSA, "public_key", ossl_rsa_to_public_key, 0);
    rb_define_method(cRSA, "public_encrypt", ossl_rsa_public_encrypt, -1);
    rb_define_method(cRSA, "public_decrypt", ossl_rsa_public_decrypt, -1);
    rb_define_method(cRSA, "private_encrypt", ossl_rsa_private_encrypt, -1);
    rb_define_method(cRSA, "private_decrypt", ossl_rsa_private_decrypt, -1);

    DEF_OSSL_PKEY_BN(cRSA, rsa, n);
    DEF_OSSL_PKEY_BN(cRSA, rsa, e);
    DEF_OSSL_PKEY_BN(cRSA, rsa, d);
    DEF_OSSL_PKEY_BN(cRSA, rsa, p);
    DEF_OSSL_PKEY_BN(cRSA, rsa, q);
    DEF_OSSL_PKEY_BN(cRSA, rsa, dmp1);
    DEF_OSSL_PKEY_BN(cRSA, rsa, dmq1);
    DEF_OSSL_PKEY_BN(cRSA, rsa, iqmp);

    rb_define_method(cRSA, "params", ossl_rsa_get_params, 0);

    DefRSAConst(PKCS1_PADDING);
    DefRSAConst(SSLV23_PADDING);
    DefRSAConst(NO_PADDING);
    DefRSAConst(PKCS1_OAEP_PADDING);

/*
 * TODO: Test it
    rb_define_method(cRSA, "blinding_on!", ossl_rsa_blinding_on, 0);
    rb_define_method(cRSA, "blinding_off!", ossl_rsa_blinding_off, 0);
 */
}

#else /* defined NO_RSA */
void
Init_ossl_rsa()
{
}
#endif /* NO_RSA */

