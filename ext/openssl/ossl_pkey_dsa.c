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
#if !defined(OPENSSL_NO_DSA)

#include "ossl.h"

#define GetPKeyDSA(obj, pkey) do { \
    GetPKey((obj), (pkey)); \
    if (EVP_PKEY_type((pkey)->type) != EVP_PKEY_DSA) { /* PARANOIA? */ \
	ossl_raise(rb_eRuntimeError, "THIS IS NOT A DSA!"); \
    } \
} while (0)

#define DSA_HAS_PRIVATE(dsa) ((dsa)->priv_key)
#define DSA_PRIVATE(obj,dsa) (DSA_HAS_PRIVATE(dsa)||OSSL_PKEY_IS_PRIVATE(obj))

/*
 * Classes
 */
VALUE cDSA;
VALUE eDSAError;

/*
 * Public
 */
static VALUE
dsa_instance(VALUE klass, DSA *dsa)
{
    EVP_PKEY *pkey;
    VALUE obj;

    if (!dsa) {
	return Qfalse;
    }
    if (!(pkey = EVP_PKEY_new())) {
	return Qfalse;
    }
    if (!EVP_PKEY_assign_DSA(pkey, dsa)) {
	EVP_PKEY_free(pkey);
	return Qfalse;
    }
    WrapPKey(klass, obj, pkey);

    return obj;
}

VALUE
ossl_dsa_new(EVP_PKEY *pkey)
{
    VALUE obj;

    if (!pkey) {
	obj = dsa_instance(cDSA, DSA_new());
    } else {
	if (EVP_PKEY_type(pkey->type) != EVP_PKEY_DSA) {
	    ossl_raise(rb_eTypeError, "Not a DSA key!");
	}
	WrapPKey(cDSA, obj, pkey);
    }
    if (obj == Qfalse) {
	ossl_raise(eDSAError, NULL);
    }

    return obj;
}

/*
 * Private
 */
static DSA *
dsa_generate(int size)
{
    DSA *dsa;
    unsigned char seed[20];
    int seed_len = 20, counter;
    unsigned long h;

    if (!RAND_bytes(seed, seed_len)) {
	return 0;
    }
    dsa = DSA_generate_parameters(size, seed, seed_len, &counter, &h,
	    rb_block_given_p() ? ossl_generate_cb : NULL,
	    NULL);
    if(!dsa) return 0;

    if (!DSA_generate_key(dsa)) {
	DSA_free(dsa);
	return 0;
    }

    return dsa;
}

/*
 *  call-seq:
 *    DSA.generate(size) -> dsa
 *
 *  === Parameters
 *  * +size+ is an integer representing the desired key size.
 *
 */
static VALUE
ossl_dsa_s_generate(VALUE klass, VALUE size)
{
    DSA *dsa = dsa_generate(NUM2INT(size)); /* err handled by dsa_instance */
    VALUE obj = dsa_instance(klass, dsa);

    if (obj == Qfalse) {
	DSA_free(dsa);
	ossl_raise(eDSAError, NULL);
    }

    return obj;
}

/*
 *  call-seq:
 *    DSA.new([size | string [, pass]) -> dsa
 *
 *  === Parameters
 *  * +size+ is an integer representing the desired key size.
 *  * +string+ contains a DER or PEM encoded key.
 *  * +pass+ is a string that contains a optional password.
 *
 *  === Examples
 *  * DSA.new -> dsa
 *  * DSA.new(1024) -> dsa
 *  * DSA.new(File.read('dsa.pem')) -> dsa
 *  * DSA.new(File.read('dsa.pem'), 'mypassword') -> dsa
 *
 */
static VALUE
ossl_dsa_initialize(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    DSA *dsa;
    BIO *in;
    char *passwd = NULL;
    VALUE arg, pass;

    GetPKey(self, pkey);
    if(rb_scan_args(argc, argv, "02", &arg, &pass) == 0) {
        dsa = DSA_new();
    }
    else if (FIXNUM_P(arg)) {
	if (!(dsa = dsa_generate(FIX2INT(arg)))) {
	    ossl_raise(eDSAError, NULL);
	}
    }
    else {
	if (!NIL_P(pass)) passwd = StringValuePtr(pass);
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(arg);
	dsa = PEM_read_bio_DSAPrivateKey(in, NULL, ossl_pem_passwd_cb, passwd);
	if (!dsa) {
	    (void)BIO_reset(in);
	    (void)ERR_get_error();
	    dsa = PEM_read_bio_DSAPublicKey(in, NULL, NULL, NULL);
	}
	if (!dsa) {
	    (void)BIO_reset(in);
	    (void)ERR_get_error();
	    dsa = PEM_read_bio_DSA_PUBKEY(in, NULL, NULL, NULL);
	}
	if (!dsa) {
	    (void)BIO_reset(in);
	    (void)ERR_get_error();
	    dsa = d2i_DSAPrivateKey_bio(in, NULL);
	}
	if (!dsa) {
	    (void)BIO_reset(in);
	    (void)ERR_get_error();
	    dsa = d2i_DSA_PUBKEY_bio(in, NULL);
	}
	BIO_free(in);
	if (!dsa) {
	    (void)ERR_get_error();
	    ossl_raise(eDSAError, "Neither PUB key nor PRIV key:");
	}
    }
    if (!EVP_PKEY_assign_DSA(pkey, dsa)) {
	DSA_free(dsa);
	ossl_raise(eDSAError, NULL);
    }

    return self;
}

/*
 *  call-seq:
 *    dsa.public? -> true | false
 *
 */
static VALUE
ossl_dsa_is_public(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyDSA(self, pkey);

    return (pkey->pkey.dsa->pub_key) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    dsa.private? -> true | false
 *
 */
static VALUE
ossl_dsa_is_private(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyDSA(self, pkey);

    return (DSA_PRIVATE(self, pkey->pkey.dsa)) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    dsa.to_pem([cipher, password]) -> aString
 *
 *  === Parameters
 *  +cipher+ is an OpenSSL::Cipher.
 *  +password+ is a string containing your password.
 *
 *  === Examples
 *  * DSA.to_pem -> aString
 *  * DSA.to_pem(cipher, 'mypassword') -> aString
 *
 */
static VALUE
ossl_dsa_export(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    BIO *out;
    const EVP_CIPHER *ciph = NULL;
    char *passwd = NULL;
    VALUE cipher, pass, str;

    GetPKeyDSA(self, pkey);
    rb_scan_args(argc, argv, "02", &cipher, &pass);
    if (!NIL_P(cipher)) {
	ciph = GetCipherPtr(cipher);
	if (!NIL_P(pass)) {
	    passwd = StringValuePtr(pass);
	}
    }
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDSAError, NULL);
    }
    if (DSA_HAS_PRIVATE(pkey->pkey.dsa)) {
	if (!PEM_write_bio_DSAPrivateKey(out, pkey->pkey.dsa, ciph,
					 NULL, 0, ossl_pem_passwd_cb, passwd)){
	    BIO_free(out);
	    ossl_raise(eDSAError, NULL);
	}
    } else {
	if (!PEM_write_bio_DSAPublicKey(out, pkey->pkey.dsa)) {
	    BIO_free(out);
	    ossl_raise(eDSAError, NULL);
	}
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 *  call-seq:
 *    dsa.to_der -> aString
 *
 */
static VALUE
ossl_dsa_to_der(VALUE self)
{
    EVP_PKEY *pkey;
    int (*i2d_func)_((DSA*, unsigned char**));
    unsigned char *p;
    long len;
    VALUE str;

    GetPKeyDSA(self, pkey);
    if(DSA_HAS_PRIVATE(pkey->pkey.dsa))
	i2d_func = (int(*)_((DSA*,unsigned char**)))i2d_DSAPrivateKey;
    else
	i2d_func = i2d_DSA_PUBKEY;
    if((len = i2d_func(pkey->pkey.dsa, NULL)) <= 0)
	ossl_raise(eDSAError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_func(pkey->pkey.dsa, &p) < 0)
	ossl_raise(eDSAError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 *  call-seq:
 *    dsa.params -> hash
 *
 * Stores all parameters of key to the hash
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (I's up to you)
 */
static VALUE
ossl_dsa_get_params(VALUE self)
{
    EVP_PKEY *pkey;
    VALUE hash;

    GetPKeyDSA(self, pkey);

    hash = rb_hash_new();

    rb_hash_aset(hash, rb_str_new2("p"), ossl_bn_new(pkey->pkey.dsa->p));
    rb_hash_aset(hash, rb_str_new2("q"), ossl_bn_new(pkey->pkey.dsa->q));
    rb_hash_aset(hash, rb_str_new2("g"), ossl_bn_new(pkey->pkey.dsa->g));
    rb_hash_aset(hash, rb_str_new2("pub_key"), ossl_bn_new(pkey->pkey.dsa->pub_key));
    rb_hash_aset(hash, rb_str_new2("priv_key"), ossl_bn_new(pkey->pkey.dsa->priv_key));

    return hash;
}

/*
 *  call-seq:
 *    dsa.to_text -> aString
 *
 * Prints all parameters of key to buffer
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (I's up to you)
 */
static VALUE
ossl_dsa_to_text(VALUE self)
{
    EVP_PKEY *pkey;
    BIO *out;
    VALUE str;

    GetPKeyDSA(self, pkey);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDSAError, NULL);
    }
    if (!DSA_print(out, pkey->pkey.dsa, 0)) { /* offset = 0 */
	BIO_free(out);
	ossl_raise(eDSAError, NULL);
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 *  call-seq:
 *    dsa.public_key -> aDSA
 *
 * Makes new instance DSA PUBLIC_KEY from PRIVATE_KEY
 */
static VALUE
ossl_dsa_to_public_key(VALUE self)
{
    EVP_PKEY *pkey;
    DSA *dsa;
    VALUE obj;

    GetPKeyDSA(self, pkey);
    /* err check performed by dsa_instance */
    dsa = DSAPublicKey_dup(pkey->pkey.dsa);
    obj = dsa_instance(CLASS_OF(self), dsa);
    if (obj == Qfalse) {
	DSA_free(dsa);
	ossl_raise(eDSAError, NULL);
    }
    return obj;
}

#define ossl_dsa_buf_size(pkey) (DSA_size((pkey)->pkey.dsa)+16)

/*
 *  call-seq:
 *    dsa.syssign(string) -> aString
 *
 */
static VALUE
ossl_dsa_sign(VALUE self, VALUE data)
{
    EVP_PKEY *pkey;
    unsigned int buf_len;
    VALUE str;

    GetPKeyDSA(self, pkey);
    StringValue(data);
    if (!DSA_PRIVATE(self, pkey->pkey.dsa)) {
	ossl_raise(eDSAError, "Private DSA key needed!");
    }
    str = rb_str_new(0, ossl_dsa_buf_size(pkey));
    if (!DSA_sign(0, (unsigned char *)RSTRING_PTR(data), RSTRING_LENINT(data),
		  (unsigned char *)RSTRING_PTR(str),
		  &buf_len, pkey->pkey.dsa)) { /* type is ignored (0) */
	ossl_raise(eDSAError, NULL);
    }
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 *  call-seq:
 *    dsa.sysverify(digest, sig) -> true | false
 *
 */
static VALUE
ossl_dsa_verify(VALUE self, VALUE digest, VALUE sig)
{
    EVP_PKEY *pkey;
    int ret;

    GetPKeyDSA(self, pkey);
    StringValue(digest);
    StringValue(sig);
    /* type is ignored (0) */
    ret = DSA_verify(0, (unsigned char *)RSTRING_PTR(digest), RSTRING_LENINT(digest),
		     (unsigned char *)RSTRING_PTR(sig), RSTRING_LENINT(sig), pkey->pkey.dsa);
    if (ret < 0) {
	ossl_raise(eDSAError, NULL);
    }
    else if (ret == 1) {
	return Qtrue;
    }

    return Qfalse;
}

OSSL_PKEY_BN(dsa, p)
OSSL_PKEY_BN(dsa, q)
OSSL_PKEY_BN(dsa, g)
OSSL_PKEY_BN(dsa, pub_key)
OSSL_PKEY_BN(dsa, priv_key)

/*
 * INIT
 */
void
Init_ossl_dsa()
{
#if 0
    mOSSL = rb_define_module("OpenSSL"); /* let rdoc know about mOSSL and mPKey */
    mPKey = rb_define_module_under(mOSSL, "PKey");
#endif

    eDSAError = rb_define_class_under(mPKey, "DSAError", ePKeyError);

    cDSA = rb_define_class_under(mPKey, "DSA", cPKey);

    rb_define_singleton_method(cDSA, "generate", ossl_dsa_s_generate, 1);
    rb_define_method(cDSA, "initialize", ossl_dsa_initialize, -1);

    rb_define_method(cDSA, "public?", ossl_dsa_is_public, 0);
    rb_define_method(cDSA, "private?", ossl_dsa_is_private, 0);
    rb_define_method(cDSA, "to_text", ossl_dsa_to_text, 0);
    rb_define_method(cDSA, "export", ossl_dsa_export, -1);
    rb_define_alias(cDSA, "to_pem", "export");
    rb_define_alias(cDSA, "to_s", "export");
    rb_define_method(cDSA, "to_der", ossl_dsa_to_der, 0);
    rb_define_method(cDSA, "public_key", ossl_dsa_to_public_key, 0);
    rb_define_method(cDSA, "syssign", ossl_dsa_sign, 1);
    rb_define_method(cDSA, "sysverify", ossl_dsa_verify, 2);

    DEF_OSSL_PKEY_BN(cDSA, dsa, p);
    DEF_OSSL_PKEY_BN(cDSA, dsa, q);
    DEF_OSSL_PKEY_BN(cDSA, dsa, g);
    DEF_OSSL_PKEY_BN(cDSA, dsa, pub_key);
    DEF_OSSL_PKEY_BN(cDSA, dsa, priv_key);

    rb_define_method(cDSA, "params", ossl_dsa_get_params, 0);
}

#else /* defined NO_DSA */
void
Init_ossl_dsa()
{
}
#endif /* NO_DSA */
