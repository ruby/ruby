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
    const BIGNUM *p, *q;

    RSA_get0_factors(rsa, &p, &q);
    return p && q; /* d? why? */
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
    obj = NewPKey(klass);
    if (!(pkey = EVP_PKEY_new())) {
	return Qfalse;
    }
    if (!EVP_PKEY_assign_RSA(pkey, rsa)) {
	EVP_PKEY_free(pkey);
	return Qfalse;
    }
    SetPKey(obj, pkey);

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
	obj = NewPKey(cRSA);
	if (EVP_PKEY_base_id(pkey) != EVP_PKEY_RSA) {
	    ossl_raise(rb_eTypeError, "Not a RSA key!");
	}
	SetPKey(obj, pkey);
    }
    if (obj == Qfalse) {
	ossl_raise(eRSAError, NULL);
    }

    return obj;
}

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
	return NULL;
    }
    for (i = 0; i < (int)sizeof(exp) * 8; ++i) {
	if (exp & (1UL << i)) {
	    if (BN_set_bit(e, i) == 0) {
		BN_free(e);
		RSA_free(rsa);
		BN_GENCB_free(cb);
		return NULL;
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
	return NULL;
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
    RSA *rsa;
    VALUE size, exp;
    VALUE obj;

    rb_scan_args(argc, argv, "11", &size, &exp);

    rsa = rsa_generate(NUM2INT(size), NIL_P(exp) ? RSA_F4 : NUM2ULONG(exp)); /* err handled by rsa_instance */
    obj = rsa_instance(klass, rsa);

    if (obj == Qfalse) {
	RSA_free(rsa);
	ossl_raise(eRSAError, NULL);
    }

    return obj;
}

/*
 * call-seq:
 *   RSA.new(key_size)                 => RSA instance
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
    EVP_PKEY *pkey;
    RSA *rsa;
    BIO *in;
    VALUE arg, pass;

    GetPKey(self, pkey);
    if(rb_scan_args(argc, argv, "02", &arg, &pass) == 0) {
	rsa = RSA_new();
    }
    else if (RB_INTEGER_TYPE_P(arg)) {
	rsa = rsa_generate(NUM2INT(arg), NIL_P(pass) ? RSA_F4 : NUM2ULONG(pass));
	if (!rsa) ossl_raise(eRSAError, NULL);
    }
    else {
	pass = ossl_pem_passwd_value(pass);
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(&arg);
	rsa = PEM_read_bio_RSAPrivateKey(in, NULL, ossl_pem_passwd_cb, (void *)pass);
	if (!rsa) {
	    OSSL_BIO_reset(in);
	    rsa = PEM_read_bio_RSA_PUBKEY(in, NULL, NULL, NULL);
	}
	if (!rsa) {
	    OSSL_BIO_reset(in);
	    rsa = d2i_RSAPrivateKey_bio(in, NULL);
	}
	if (!rsa) {
	    OSSL_BIO_reset(in);
	    rsa = d2i_RSA_PUBKEY_bio(in, NULL);
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
	    ossl_raise(eRSAError, "Neither PUB key nor PRIV key");
	}
    }
    if (!EVP_PKEY_assign_RSA(pkey, rsa)) {
	RSA_free(rsa);
	ossl_raise(eRSAError, NULL);
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
    RSA *rsa;
    BIO *out;
    const EVP_CIPHER *ciph = NULL;
    VALUE cipher, pass, str;

    GetRSA(self, rsa);

    rb_scan_args(argc, argv, "02", &cipher, &pass);

    if (!NIL_P(cipher)) {
	ciph = ossl_evp_get_cipherbyname(cipher);
	pass = ossl_pem_passwd_value(pass);
    }
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eRSAError, NULL);
    }
    if (RSA_HAS_PRIVATE(rsa)) {
	if (!PEM_write_bio_RSAPrivateKey(out, rsa, ciph, NULL, 0,
					 ossl_pem_passwd_cb, (void *)pass)) {
	    BIO_free(out);
	    ossl_raise(eRSAError, NULL);
	}
    } else {
	if (!PEM_write_bio_RSA_PUBKEY(out, rsa)) {
	    BIO_free(out);
	    ossl_raise(eRSAError, NULL);
	}
    }
    str = ossl_membio2str(out);

    return str;
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
    RSA *rsa;
    int (*i2d_func)(const RSA *, unsigned char **);
    unsigned char *p;
    long len;
    VALUE str;

    GetRSA(self, rsa);
    if (RSA_HAS_PRIVATE(rsa))
	i2d_func = i2d_RSAPrivateKey;
    else
	i2d_func = (int (*)(const RSA *, unsigned char **))i2d_RSA_PUBKEY;
    if((len = i2d_func(rsa, NULL)) <= 0)
	ossl_raise(eRSAError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_func(rsa, &p) < 0)
	ossl_raise(eRSAError, NULL);
    ossl_str_adjust(str, p);

    return str;
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
    EVP_PKEY *pkey;
    RSA *rsa;
    VALUE obj;

    GetPKeyRSA(self, pkey);
    /* err check performed by rsa_instance */
    rsa = RSAPublicKey_dup(EVP_PKEY_get0_RSA(pkey));
    obj = rsa_instance(rb_obj_class(self), rsa);
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
