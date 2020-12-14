/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if !defined(OPENSSL_NO_RSA)

#define GetPKeyRSA(obj, pkey) do { \
    GetPKey((obj), (pkey)); \
    if (EVP_PKEY_base_id(pkey) != EVP_PKEY_RSA) { /* PARANOIA? */ \
	ossl_raise(rb_eRuntimeError, "THIS IS NOT A RSA!") ; \
    } \
} while (0)
#define GetRSA(obj, rsa) do { \
    EVP_PKEY *_pkey; \
    GetPKeyRSA((obj), _pkey); \
    (rsa) = EVP_PKEY_get0_RSA(_pkey); \
} while (0)

static inline int
RSA_HAS_PRIVATE(RSA *rsa)
{
    const BIGNUM *e, *d;

    RSA_get0_key(rsa, NULL, &e, &d);
    return e && d;
}

static inline int
RSA_PRIVATE(VALUE obj, RSA *rsa)
{
    return RSA_HAS_PRIVATE(rsa) || OSSL_PKEY_IS_PRIVATE(obj);
}

/*
 * Classes
 */
VALUE cRSA;
VALUE eRSAError;

/*
 * Private
 */
struct rsa_blocking_gen_arg {
    RSA *rsa;
    BIGNUM *e;
    int size;
    BN_GENCB *cb;
    int result;
};

static void *
rsa_blocking_gen(void *arg)
{
    struct rsa_blocking_gen_arg *gen = (struct rsa_blocking_gen_arg *)arg;
    gen->result = RSA_generate_key_ex(gen->rsa, gen->size, gen->e, gen->cb);
    return 0;
}

static RSA *
rsa_generate(int size, unsigned long exp)
{
    int i;
    struct ossl_generate_cb_arg cb_arg = { 0 };
    struct rsa_blocking_gen_arg gen_arg;
    RSA *rsa = RSA_new();
    BIGNUM *e = BN_new();
    BN_GENCB *cb = BN_GENCB_new();

    if (!rsa || !e || !cb) {
	RSA_free(rsa);
	BN_free(e);
	BN_GENCB_free(cb);
        ossl_raise(eRSAError, "malloc failure");
    }
    for (i = 0; i < (int)sizeof(exp) * 8; ++i) {
	if (exp & (1UL << i)) {
	    if (BN_set_bit(e, i) == 0) {
		BN_free(e);
		RSA_free(rsa);
		BN_GENCB_free(cb);
                ossl_raise(eRSAError, "BN_set_bit");
	    }
	}
    }

    if (rb_block_given_p())
	cb_arg.yield = 1;
    BN_GENCB_set(cb, ossl_generate_cb_2, &cb_arg);
    gen_arg.rsa = rsa;
    gen_arg.e = e;
    gen_arg.size = size;
    gen_arg.cb = cb;
    if (cb_arg.yield == 1) {
	/* we cannot release GVL when callback proc is supplied */
	rsa_blocking_gen(&gen_arg);
    } else {
	/* there's a chance to unblock */
	rb_thread_call_without_gvl(rsa_blocking_gen, &gen_arg, ossl_generate_cb_stop, &cb_arg);
    }

    BN_GENCB_free(cb);
    BN_free(e);
    if (!gen_arg.result) {
	RSA_free(rsa);
	if (cb_arg.state) {
	    /* must clear OpenSSL error stack */
	    ossl_clear_error();
	    rb_jump_tag(cb_arg.state);
	}
        ossl_raise(eRSAError, "RSA_generate_key_ex");
    }

    return rsa;
}

/*
 * call-seq:
 *   RSA.generate(size)           => RSA instance
 *   RSA.generate(size, exponent) => RSA instance
 *
 * Generates an RSA keypair.  _size_ is an integer representing the desired key
 * size.  Keys smaller than 1024 should be considered insecure.  _exponent_ is
 * an odd number normally 3, 17, or 65537.
 */
static VALUE
ossl_rsa_s_generate(int argc, VALUE *argv, VALUE klass)
{
/* why does this method exist?  why can't initialize take an optional exponent? */
    EVP_PKEY *pkey;
    RSA *rsa;
    VALUE size, exp;
    VALUE obj;

    rb_scan_args(argc, argv, "11", &size, &exp);
    obj = rb_obj_alloc(klass);
    GetPKey(obj, pkey);

    rsa = rsa_generate(NUM2INT(size), NIL_P(exp) ? RSA_F4 : NUM2ULONG(exp));
    if (!EVP_PKEY_assign_RSA(pkey, rsa)) {
        RSA_free(rsa);
        ossl_raise(eRSAError, "EVP_PKEY_assign_RSA");
    }
    return obj;
}

/*
 * call-seq:
 *   RSA.new(size [, exponent])        => RSA instance
 *   RSA.new(encoded_key)              => RSA instance
 *   RSA.new(encoded_key, pass_phrase) => RSA instance
 *
 * Generates or loads an RSA keypair.  If an integer _key_size_ is given it
 * represents the desired key size.  Keys less than 1024 bits should be
 * considered insecure.
 *
 * A key can instead be loaded from an _encoded_key_ which must be PEM or DER
 * encoded.  A _pass_phrase_ can be used to decrypt the key.  If none is given
 * OpenSSL will prompt for the pass phrase.
 *
 * = Examples
 *
 *   OpenSSL::PKey::RSA.new 2048
 *   OpenSSL::PKey::RSA.new File.read 'rsa.pem'
 *   OpenSSL::PKey::RSA.new File.read('rsa.pem'), 'my pass phrase'
 */
static VALUE
ossl_rsa_initialize(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey, *tmp;
    RSA *rsa = NULL;
    BIO *in;
    VALUE arg, pass;

    GetPKey(self, pkey);
    rb_scan_args(argc, argv, "02", &arg, &pass);
    if (argc == 0) {
	rsa = RSA_new();
        if (!rsa)
            ossl_raise(eRSAError, "RSA_new");
    }
    else if (RB_INTEGER_TYPE_P(arg)) {
	rsa = rsa_generate(NUM2INT(arg), NIL_P(pass) ? RSA_F4 : NUM2ULONG(pass));
    }
    else {
	pass = ossl_pem_passwd_value(pass);
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(&arg);

        tmp = ossl_pkey_read_generic(in, pass);
        if (tmp) {
            if (EVP_PKEY_base_id(tmp) != EVP_PKEY_RSA)
                rb_raise(eRSAError, "incorrect pkey type: %s",
                         OBJ_nid2sn(EVP_PKEY_base_id(tmp)));
            rsa = EVP_PKEY_get1_RSA(tmp);
            EVP_PKEY_free(tmp);
        }
	if (!rsa) {
	    OSSL_BIO_reset(in);
	    rsa = PEM_read_bio_RSAPublicKey(in, NULL, NULL, NULL);
	}
	if (!rsa) {
	    OSSL_BIO_reset(in);
	    rsa = d2i_RSAPublicKey_bio(in, NULL);
	}
	BIO_free(in);
	if (!rsa) {
            ossl_clear_error();
	    ossl_raise(eRSAError, "Neither PUB key nor PRIV key");
	}
    }
    if (!EVP_PKEY_assign_RSA(pkey, rsa)) {
	RSA_free(rsa);
	ossl_raise(eRSAError, "EVP_PKEY_assign_RSA");
    }

    return self;
}

static VALUE
ossl_rsa_initialize_copy(VALUE self, VALUE other)
{
    EVP_PKEY *pkey;
    RSA *rsa, *rsa_new;

    GetPKey(self, pkey);
    if (EVP_PKEY_base_id(pkey) != EVP_PKEY_NONE)
	ossl_raise(eRSAError, "RSA already initialized");
    GetRSA(other, rsa);

    rsa_new = ASN1_dup((i2d_of_void *)i2d_RSAPrivateKey, (d2i_of_void *)d2i_RSAPrivateKey, (char *)rsa);
    if (!rsa_new)
	ossl_raise(eRSAError, "ASN1_dup");

    EVP_PKEY_assign_RSA(pkey, rsa_new);

    return self;
}

/*
 * call-seq:
 *   rsa.public? => true
 *
 * The return value is always +true+ since every private key is also a public
 * key.
 */
static VALUE
ossl_rsa_is_public(VALUE self)
{
    RSA *rsa;

    GetRSA(self, rsa);
    /*
     * This method should check for n and e.  BUG.
     */
    (void)rsa;
    return Qtrue;
}

/*
 * call-seq:
 *   rsa.private? => true | false
 *
 * Does this keypair contain a private key?
 */
static VALUE
ossl_rsa_is_private(VALUE self)
{
    RSA *rsa;

    GetRSA(self, rsa);

    return RSA_PRIVATE(self, rsa) ? Qtrue : Qfalse;
}

static int
can_export_rsaprivatekey(VALUE self)
{
    RSA *rsa;
    const BIGNUM *n, *e, *d, *p, *q, *dmp1, *dmq1, *iqmp;

    GetRSA(self, rsa);

    RSA_get0_key(rsa, &n, &e, &d);
    RSA_get0_factors(rsa, &p, &q);
    RSA_get0_crt_params(rsa, &dmp1, &dmq1, &iqmp);

    return n && e && d && p && q && dmp1 && dmq1 && iqmp;
}

/*
 * call-seq:
 *   rsa.export([cipher, pass_phrase]) => PEM-format String
 *   rsa.to_pem([cipher, pass_phrase]) => PEM-format String
 *   rsa.to_s([cipher, pass_phrase]) => PEM-format String
 *
 * Outputs this keypair in PEM encoding.  If _cipher_ and _pass_phrase_ are
 * given they will be used to encrypt the key.  _cipher_ must be an
 * OpenSSL::Cipher instance.
 */
static VALUE
ossl_rsa_export(int argc, VALUE *argv, VALUE self)
{
    if (can_export_rsaprivatekey(self))
        return ossl_pkey_export_traditional(argc, argv, self, 0);
    else
        return ossl_pkey_export_spki(self, 0);
}

/*
 * call-seq:
 *   rsa.to_der => DER-format String
 *
 * Outputs this keypair in DER encoding.
 */
static VALUE
ossl_rsa_to_der(VALUE self)
{
    if (can_export_rsaprivatekey(self))
        return ossl_pkey_export_traditional(0, NULL, self, 1);
    else
        return ossl_pkey_export_spki(self, 1);
}

/*
 * call-seq:
 *   rsa.public_encrypt(string)          => String
 *   rsa.public_encrypt(string, padding) => String
 *
 * Encrypt _string_ with the public key.  _padding_ defaults to PKCS1_PADDING.
 * The encrypted string output can be decrypted using #private_decrypt.
 */
static VALUE
ossl_rsa_public_encrypt(int argc, VALUE *argv, VALUE self)
{
    RSA *rsa;
    const BIGNUM *rsa_n;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetRSA(self, rsa);
    RSA_get0_key(rsa, &rsa_n, NULL, NULL);
    if (!rsa_n)
	ossl_raise(eRSAError, "incomplete RSA");
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, RSA_size(rsa));
    buf_len = RSA_public_encrypt(RSTRING_LENINT(buffer), (unsigned char *)RSTRING_PTR(buffer),
				 (unsigned char *)RSTRING_PTR(str), rsa, pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 * call-seq:
 *   rsa.public_decrypt(string)          => String
 *   rsa.public_decrypt(string, padding) => String
 *
 * Decrypt _string_, which has been encrypted with the private key, with the
 * public key.  _padding_ defaults to PKCS1_PADDING.
 */
static VALUE
ossl_rsa_public_decrypt(int argc, VALUE *argv, VALUE self)
{
    RSA *rsa;
    const BIGNUM *rsa_n;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetRSA(self, rsa);
    RSA_get0_key(rsa, &rsa_n, NULL, NULL);
    if (!rsa_n)
	ossl_raise(eRSAError, "incomplete RSA");
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, RSA_size(rsa));
    buf_len = RSA_public_decrypt(RSTRING_LENINT(buffer), (unsigned char *)RSTRING_PTR(buffer),
				 (unsigned char *)RSTRING_PTR(str), rsa, pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 * call-seq:
 *   rsa.private_encrypt(string)          => String
 *   rsa.private_encrypt(string, padding) => String
 *
 * Encrypt _string_ with the private key.  _padding_ defaults to PKCS1_PADDING.
 * The encrypted string output can be decrypted using #public_decrypt.
 */
static VALUE
ossl_rsa_private_encrypt(int argc, VALUE *argv, VALUE self)
{
    RSA *rsa;
    const BIGNUM *rsa_n;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetRSA(self, rsa);
    RSA_get0_key(rsa, &rsa_n, NULL, NULL);
    if (!rsa_n)
	ossl_raise(eRSAError, "incomplete RSA");
    if (!RSA_PRIVATE(self, rsa))
	ossl_raise(eRSAError, "private key needed.");
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, RSA_size(rsa));
    buf_len = RSA_private_encrypt(RSTRING_LENINT(buffer), (unsigned char *)RSTRING_PTR(buffer),
				  (unsigned char *)RSTRING_PTR(str), rsa, pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 * call-seq:
 *   rsa.private_decrypt(string)          => String
 *   rsa.private_decrypt(string, padding) => String
 *
 * Decrypt _string_, which has been encrypted with the public key, with the
 * private key.  _padding_ defaults to PKCS1_PADDING.
 */
static VALUE
ossl_rsa_private_decrypt(int argc, VALUE *argv, VALUE self)
{
    RSA *rsa;
    const BIGNUM *rsa_n;
    int buf_len, pad;
    VALUE str, buffer, padding;

    GetRSA(self, rsa);
    RSA_get0_key(rsa, &rsa_n, NULL, NULL);
    if (!rsa_n)
	ossl_raise(eRSAError, "incomplete RSA");
    if (!RSA_PRIVATE(self, rsa))
	ossl_raise(eRSAError, "private key needed.");
    rb_scan_args(argc, argv, "11", &buffer, &padding);
    pad = (argc == 1) ? RSA_PKCS1_PADDING : NUM2INT(padding);
    StringValue(buffer);
    str = rb_str_new(0, RSA_size(rsa));
    buf_len = RSA_private_decrypt(RSTRING_LENINT(buffer), (unsigned char *)RSTRING_PTR(buffer),
				  (unsigned char *)RSTRING_PTR(str), rsa, pad);
    if (buf_len < 0) ossl_raise(eRSAError, NULL);
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 * call-seq:
 *    rsa.sign_pss(digest, data, salt_length:, mgf1_hash:) -> String
 *
 * Signs _data_ using the Probabilistic Signature Scheme (RSA-PSS) and returns
 * the calculated signature.
 *
 * RSAError will be raised if an error occurs.
 *
 * See #verify_pss for the verification operation.
 *
 * === Parameters
 * _digest_::
 *   A String containing the message digest algorithm name.
 * _data_::
 *   A String. The data to be signed.
 * _salt_length_::
 *   The length in octets of the salt. Two special values are reserved:
 *   +:digest+ means the digest length, and +:max+ means the maximum possible
 *   length for the combination of the private key and the selected message
 *   digest algorithm.
 * _mgf1_hash_::
 *   The hash algorithm used in MGF1 (the currently supported mask generation
 *   function (MGF)).
 *
 * === Example
 *   data = "Sign me!"
 *   pkey = OpenSSL::PKey::RSA.new(2048)
 *   signature = pkey.sign_pss("SHA256", data, salt_length: :max, mgf1_hash: "SHA256")
 *   pub_key = pkey.public_key
 *   puts pub_key.verify_pss("SHA256", signature, data,
 *                           salt_length: :auto, mgf1_hash: "SHA256") # => true
 */
static VALUE
ossl_rsa_sign_pss(int argc, VALUE *argv, VALUE self)
{
    VALUE digest, data, options, kwargs[2], signature;
    static ID kwargs_ids[2];
    EVP_PKEY *pkey;
    EVP_PKEY_CTX *pkey_ctx;
    const EVP_MD *md, *mgf1md;
    EVP_MD_CTX *md_ctx;
    size_t buf_len;
    int salt_len;

    if (!kwargs_ids[0]) {
	kwargs_ids[0] = rb_intern_const("salt_length");
	kwargs_ids[1] = rb_intern_const("mgf1_hash");
    }
    rb_scan_args(argc, argv, "2:", &digest, &data, &options);
    rb_get_kwargs(options, kwargs_ids, 2, 0, kwargs);
    if (kwargs[0] == ID2SYM(rb_intern("max")))
	salt_len = -2; /* RSA_PSS_SALTLEN_MAX_SIGN */
    else if (kwargs[0] == ID2SYM(rb_intern("digest")))
	salt_len = -1; /* RSA_PSS_SALTLEN_DIGEST */
    else
	salt_len = NUM2INT(kwargs[0]);
    mgf1md = ossl_evp_get_digestbyname(kwargs[1]);

    pkey = GetPrivPKeyPtr(self);
    buf_len = EVP_PKEY_size(pkey);
    md = ossl_evp_get_digestbyname(digest);
    StringValue(data);
    signature = rb_str_new(NULL, (long)buf_len);

    md_ctx = EVP_MD_CTX_new();
    if (!md_ctx)
	goto err;

    if (EVP_DigestSignInit(md_ctx, &pkey_ctx, md, NULL, pkey) != 1)
	goto err;

    if (EVP_PKEY_CTX_set_rsa_padding(pkey_ctx, RSA_PKCS1_PSS_PADDING) != 1)
	goto err;

    if (EVP_PKEY_CTX_set_rsa_pss_saltlen(pkey_ctx, salt_len) != 1)
	goto err;

    if (EVP_PKEY_CTX_set_rsa_mgf1_md(pkey_ctx, mgf1md) != 1)
	goto err;

    if (EVP_DigestSignUpdate(md_ctx, RSTRING_PTR(data), RSTRING_LEN(data)) != 1)
	goto err;

    if (EVP_DigestSignFinal(md_ctx, (unsigned char *)RSTRING_PTR(signature), &buf_len) != 1)
	goto err;

    rb_str_set_len(signature, (long)buf_len);

    EVP_MD_CTX_free(md_ctx);
    return signature;

  err:
    EVP_MD_CTX_free(md_ctx);
    ossl_raise(eRSAError, NULL);
}

/*
 * call-seq:
 *    rsa.verify_pss(digest, signature, data, salt_length:, mgf1_hash:) -> true | false
 *
 * Verifies _data_ using the Probabilistic Signature Scheme (RSA-PSS).
 *
 * The return value is +true+ if the signature is valid, +false+ otherwise.
 * RSAError will be raised if an error occurs.
 *
 * See #sign_pss for the signing operation and an example code.
 *
 * === Parameters
 * _digest_::
 *   A String containing the message digest algorithm name.
 * _data_::
 *   A String. The data to be signed.
 * _salt_length_::
 *   The length in octets of the salt. Two special values are reserved:
 *   +:digest+ means the digest length, and +:auto+ means automatically
 *   determining the length based on the signature.
 * _mgf1_hash_::
 *   The hash algorithm used in MGF1.
 */
static VALUE
ossl_rsa_verify_pss(int argc, VALUE *argv, VALUE self)
{
    VALUE digest, signature, data, options, kwargs[2];
    static ID kwargs_ids[2];
    EVP_PKEY *pkey;
    EVP_PKEY_CTX *pkey_ctx;
    const EVP_MD *md, *mgf1md;
    EVP_MD_CTX *md_ctx;
    int result, salt_len;

    if (!kwargs_ids[0]) {
	kwargs_ids[0] = rb_intern_const("salt_length");
	kwargs_ids[1] = rb_intern_const("mgf1_hash");
    }
    rb_scan_args(argc, argv, "3:", &digest, &signature, &data, &options);
    rb_get_kwargs(options, kwargs_ids, 2, 0, kwargs);
    if (kwargs[0] == ID2SYM(rb_intern("auto")))
	salt_len = -2; /* RSA_PSS_SALTLEN_AUTO */
    else if (kwargs[0] == ID2SYM(rb_intern("digest")))
	salt_len = -1; /* RSA_PSS_SALTLEN_DIGEST */
    else
	salt_len = NUM2INT(kwargs[0]);
    mgf1md = ossl_evp_get_digestbyname(kwargs[1]);

    GetPKey(self, pkey);
    md = ossl_evp_get_digestbyname(digest);
    StringValue(signature);
    StringValue(data);

    md_ctx = EVP_MD_CTX_new();
    if (!md_ctx)
	goto err;

    if (EVP_DigestVerifyInit(md_ctx, &pkey_ctx, md, NULL, pkey) != 1)
	goto err;

    if (EVP_PKEY_CTX_set_rsa_padding(pkey_ctx, RSA_PKCS1_PSS_PADDING) != 1)
	goto err;

    if (EVP_PKEY_CTX_set_rsa_pss_saltlen(pkey_ctx, salt_len) != 1)
	goto err;

    if (EVP_PKEY_CTX_set_rsa_mgf1_md(pkey_ctx, mgf1md) != 1)
	goto err;

    if (EVP_DigestVerifyUpdate(md_ctx, RSTRING_PTR(data), RSTRING_LEN(data)) != 1)
	goto err;

    result = EVP_DigestVerifyFinal(md_ctx,
				   (unsigned char *)RSTRING_PTR(signature),
				   RSTRING_LEN(signature));

    switch (result) {
      case 0:
	ossl_clear_error();
	EVP_MD_CTX_free(md_ctx);
	return Qfalse;
      case 1:
	EVP_MD_CTX_free(md_ctx);
	return Qtrue;
      default:
	goto err;
    }

  err:
    EVP_MD_CTX_free(md_ctx);
    ossl_raise(eRSAError, NULL);
}

/*
 * call-seq:
 *   rsa.params => hash
 *
 * THIS METHOD IS INSECURE, PRIVATE INFORMATION CAN LEAK OUT!!!
 *
 * Stores all parameters of key to the hash.  The hash has keys 'n', 'e', 'd',
 * 'p', 'q', 'dmp1', 'dmq1', 'iqmp'.
 *
 * Don't use :-)) (It's up to you)
 */
static VALUE
ossl_rsa_get_params(VALUE self)
{
    RSA *rsa;
    VALUE hash;
    const BIGNUM *n, *e, *d, *p, *q, *dmp1, *dmq1, *iqmp;

    GetRSA(self, rsa);
    RSA_get0_key(rsa, &n, &e, &d);
    RSA_get0_factors(rsa, &p, &q);
    RSA_get0_crt_params(rsa, &dmp1, &dmq1, &iqmp);

    hash = rb_hash_new();
    rb_hash_aset(hash, rb_str_new2("n"), ossl_bn_new(n));
    rb_hash_aset(hash, rb_str_new2("e"), ossl_bn_new(e));
    rb_hash_aset(hash, rb_str_new2("d"), ossl_bn_new(d));
    rb_hash_aset(hash, rb_str_new2("p"), ossl_bn_new(p));
    rb_hash_aset(hash, rb_str_new2("q"), ossl_bn_new(q));
    rb_hash_aset(hash, rb_str_new2("dmp1"), ossl_bn_new(dmp1));
    rb_hash_aset(hash, rb_str_new2("dmq1"), ossl_bn_new(dmq1));
    rb_hash_aset(hash, rb_str_new2("iqmp"), ossl_bn_new(iqmp));

    return hash;
}

/*
 * call-seq:
 *   rsa.to_text => String
 *
 * THIS METHOD IS INSECURE, PRIVATE INFORMATION CAN LEAK OUT!!!
 *
 * Dumps all parameters of a keypair to a String
 *
 * Don't use :-)) (It's up to you)
 */
static VALUE
ossl_rsa_to_text(VALUE self)
{
    RSA *rsa;
    BIO *out;
    VALUE str;

    GetRSA(self, rsa);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eRSAError, NULL);
    }
    if (!RSA_print(out, rsa, 0)) { /* offset = 0 */
	BIO_free(out);
	ossl_raise(eRSAError, NULL);
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 * call-seq:
 *    rsa.public_key -> RSA
 *
 * Makes new RSA instance containing the public key from the private key.
 */
static VALUE
ossl_rsa_to_public_key(VALUE self)
{
    EVP_PKEY *pkey, *pkey_new;
    RSA *rsa;
    VALUE obj;

    GetPKeyRSA(self, pkey);
    obj = rb_obj_alloc(rb_obj_class(self));
    GetPKey(obj, pkey_new);

    rsa = RSAPublicKey_dup(EVP_PKEY_get0_RSA(pkey));
    if (!rsa)
        ossl_raise(eRSAError, "RSAPublicKey_dup");
    if (!EVP_PKEY_assign_RSA(pkey_new, rsa)) {
        RSA_free(rsa);
        ossl_raise(eRSAError, "EVP_PKEY_assign_RSA");
    }
    return obj;
}

/*
 * TODO: Test me

static VALUE
ossl_rsa_blinding_on(VALUE self)
{
    RSA *rsa;

    GetRSA(self, rsa);

    if (RSA_blinding_on(rsa, ossl_bn_ctx) != 1) {
	ossl_raise(eRSAError, NULL);
    }
    return self;
}

static VALUE
ossl_rsa_blinding_off(VALUE self)
{
    RSA *rsa;

    GetRSA(self, rsa);
    RSA_blinding_off(rsa);

    return self;
}
 */

/*
 * Document-method: OpenSSL::PKey::RSA#set_key
 * call-seq:
 *   rsa.set_key(n, e, d) -> self
 *
 * Sets _n_, _e_, _d_ for the RSA instance.
 */
OSSL_PKEY_BN_DEF3(rsa, RSA, key, n, e, d)
/*
 * Document-method: OpenSSL::PKey::RSA#set_factors
 * call-seq:
 *   rsa.set_factors(p, q) -> self
 *
 * Sets _p_, _q_ for the RSA instance.
 */
OSSL_PKEY_BN_DEF2(rsa, RSA, factors, p, q)
/*
 * Document-method: OpenSSL::PKey::RSA#set_crt_params
 * call-seq:
 *   rsa.set_crt_params(dmp1, dmq1, iqmp) -> self
 *
 * Sets _dmp1_, _dmq1_, _iqmp_ for the RSA instance. They are calculated by
 * <tt>d mod (p - 1)</tt>, <tt>d mod (q - 1)</tt> and <tt>q^(-1) mod p</tt>
 * respectively.
 */
OSSL_PKEY_BN_DEF3(rsa, RSA, crt_params, dmp1, dmq1, iqmp)

/*
 * INIT
 */
#define DefRSAConst(x) rb_define_const(cRSA, #x, INT2NUM(RSA_##x))

void
Init_ossl_rsa(void)
{
#if 0
    mPKey = rb_define_module_under(mOSSL, "PKey");
    cPKey = rb_define_class_under(mPKey, "PKey", rb_cObject);
    ePKeyError = rb_define_class_under(mPKey, "PKeyError", eOSSLError);
#endif

    /* Document-class: OpenSSL::PKey::RSAError
     *
     * Generic exception that is raised if an operation on an RSA PKey
     * fails unexpectedly or in case an instantiation of an instance of RSA
     * fails due to non-conformant input data.
     */
    eRSAError = rb_define_class_under(mPKey, "RSAError", ePKeyError);

    /* Document-class: OpenSSL::PKey::RSA
     *
     * RSA is an asymmetric public key algorithm that has been formalized in
     * RFC 3447. It is in widespread use in public key infrastructures (PKI)
     * where certificates (cf. OpenSSL::X509::Certificate) often are issued
     * on the basis of a public/private RSA key pair. RSA is used in a wide
     * field of applications such as secure (symmetric) key exchange, e.g.
     * when establishing a secure TLS/SSL connection. It is also used in
     * various digital signature schemes.
     */
    cRSA = rb_define_class_under(mPKey, "RSA", cPKey);

    rb_define_singleton_method(cRSA, "generate", ossl_rsa_s_generate, -1);
    rb_define_method(cRSA, "initialize", ossl_rsa_initialize, -1);
    rb_define_method(cRSA, "initialize_copy", ossl_rsa_initialize_copy, 1);

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
    rb_define_method(cRSA, "sign_pss", ossl_rsa_sign_pss, -1);
    rb_define_method(cRSA, "verify_pss", ossl_rsa_verify_pss, -1);

    DEF_OSSL_PKEY_BN(cRSA, rsa, n);
    DEF_OSSL_PKEY_BN(cRSA, rsa, e);
    DEF_OSSL_PKEY_BN(cRSA, rsa, d);
    DEF_OSSL_PKEY_BN(cRSA, rsa, p);
    DEF_OSSL_PKEY_BN(cRSA, rsa, q);
    DEF_OSSL_PKEY_BN(cRSA, rsa, dmp1);
    DEF_OSSL_PKEY_BN(cRSA, rsa, dmq1);
    DEF_OSSL_PKEY_BN(cRSA, rsa, iqmp);
    rb_define_method(cRSA, "set_key", ossl_rsa_set_key, 3);
    rb_define_method(cRSA, "set_factors", ossl_rsa_set_factors, 2);
    rb_define_method(cRSA, "set_crt_params", ossl_rsa_set_crt_params, 3);

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
Init_ossl_rsa(void)
{
}
#endif /* NO_RSA */
