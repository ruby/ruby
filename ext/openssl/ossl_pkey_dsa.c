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

#if !defined(OPENSSL_NO_DSA)

#define GetPKeyDSA(obj, pkey) do { \
    GetPKey((obj), (pkey)); \
    if (EVP_PKEY_base_id(pkey) != EVP_PKEY_DSA) { /* PARANOIA? */ \
	ossl_raise(rb_eRuntimeError, "THIS IS NOT A DSA!"); \
    } \
} while (0)
#define GetDSA(obj, dsa) do { \
    EVP_PKEY *_pkey; \
    GetPKeyDSA((obj), _pkey); \
    (dsa) = EVP_PKEY_get0_DSA(_pkey); \
} while (0)

static inline int
DSA_HAS_PRIVATE(DSA *dsa)
{
    const BIGNUM *bn;
    DSA_get0_key(dsa, NULL, &bn);
    return !!bn;
}

static inline int
DSA_PRIVATE(VALUE obj, DSA *dsa)
{
    return DSA_HAS_PRIVATE(dsa) || OSSL_PKEY_IS_PRIVATE(obj);
}

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
    obj = NewPKey(klass);
    if (!(pkey = EVP_PKEY_new())) {
	return Qfalse;
    }
    if (!EVP_PKEY_assign_DSA(pkey, dsa)) {
	EVP_PKEY_free(pkey);
	return Qfalse;
    }
    SetPKey(obj, pkey);

    return obj;
}

VALUE
ossl_dsa_new(EVP_PKEY *pkey)
{
    VALUE obj;

    if (!pkey) {
	obj = dsa_instance(cDSA, DSA_new());
    } else {
	obj = NewPKey(cDSA);
	if (EVP_PKEY_base_id(pkey) != EVP_PKEY_DSA) {
	    ossl_raise(rb_eTypeError, "Not a DSA key!");
	}
	SetPKey(obj, pkey);
    }
    if (obj == Qfalse) {
	ossl_raise(eDSAError, NULL);
    }

    return obj;
}

/*
 * Private
 */
struct dsa_blocking_gen_arg {
    DSA *dsa;
    int size;
    int *counter;
    unsigned long *h;
    BN_GENCB *cb;
    int result;
};

static void *
dsa_blocking_gen(void *arg)
{
    struct dsa_blocking_gen_arg *gen = (struct dsa_blocking_gen_arg *)arg;
    gen->result = DSA_generate_parameters_ex(gen->dsa, gen->size, NULL, 0,
					     gen->counter, gen->h, gen->cb);
    return 0;
}

static DSA *
dsa_generate(int size)
{
    struct ossl_generate_cb_arg cb_arg = { 0 };
    struct dsa_blocking_gen_arg gen_arg;
    DSA *dsa = DSA_new();
    BN_GENCB *cb = BN_GENCB_new();
    int counter;
    unsigned long h;

    if (!dsa || !cb) {
	DSA_free(dsa);
	BN_GENCB_free(cb);
	return NULL;
    }

    if (rb_block_given_p())
	cb_arg.yield = 1;
    BN_GENCB_set(cb, ossl_generate_cb_2, &cb_arg);
    gen_arg.dsa = dsa;
    gen_arg.size = size;
    gen_arg.counter = &counter;
    gen_arg.h = &h;
    gen_arg.cb = cb;
    if (cb_arg.yield == 1) {
	/* we cannot release GVL when callback proc is supplied */
	dsa_blocking_gen(&gen_arg);
    } else {
	/* there's a chance to unblock */
	rb_thread_call_without_gvl(dsa_blocking_gen, &gen_arg, ossl_generate_cb_stop, &cb_arg);
    }

    BN_GENCB_free(cb);
    if (!gen_arg.result) {
	DSA_free(dsa);
	if (cb_arg.state) {
	    /* Clear OpenSSL error queue before re-raising. By the way, the
	     * documentation of DSA_generate_parameters_ex() says the error code
	     * can be obtained by ERR_get_error(), but the default
	     * implementation, dsa_builtin_paramgen() doesn't put any error... */
	    ossl_clear_error();
	    rb_jump_tag(cb_arg.state);
	}
	return NULL;
    }

    if (!DSA_generate_key(dsa)) {
	DSA_free(dsa);
	return NULL;
    }

    return dsa;
}

/*
 *  call-seq:
 *    DSA.generate(size) -> dsa
 *
 * Creates a new DSA instance by generating a private/public key pair
 * from scratch.
 *
 * === Parameters
 * * _size_ is an integer representing the desired key size.
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
 *    DSA.new -> dsa
 *    DSA.new(size) -> dsa
 *    DSA.new(string [, pass]) -> dsa
 *
 * Creates a new DSA instance by reading an existing key from _string_.
 *
 * === Parameters
 * * _size_ is an integer representing the desired key size.
 * * _string_ contains a DER or PEM encoded key.
 * * _pass_ is a string that contains an optional password.
 *
 * === Examples
 *  DSA.new -> dsa
 *  DSA.new(1024) -> dsa
 *  DSA.new(File.read('dsa.pem')) -> dsa
 *  DSA.new(File.read('dsa.pem'), 'mypassword') -> dsa
 *
 */
static VALUE
ossl_dsa_initialize(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    DSA *dsa;
    BIO *in;
    VALUE arg, pass;

    GetPKey(self, pkey);
    if(rb_scan_args(argc, argv, "02", &arg, &pass) == 0) {
        dsa = DSA_new();
    }
    else if (RB_INTEGER_TYPE_P(arg)) {
	if (!(dsa = dsa_generate(NUM2INT(arg)))) {
	    ossl_raise(eDSAError, NULL);
	}
    }
    else {
	pass = ossl_pem_passwd_value(pass);
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(&arg);
	dsa = PEM_read_bio_DSAPrivateKey(in, NULL, ossl_pem_passwd_cb, (void *)pass);
	if (!dsa) {
	    OSSL_BIO_reset(in);
	    dsa = PEM_read_bio_DSA_PUBKEY(in, NULL, NULL, NULL);
	}
	if (!dsa) {
	    OSSL_BIO_reset(in);
	    dsa = d2i_DSAPrivateKey_bio(in, NULL);
	}
	if (!dsa) {
	    OSSL_BIO_reset(in);
	    dsa = d2i_DSA_PUBKEY_bio(in, NULL);
	}
	if (!dsa) {
	    OSSL_BIO_reset(in);
#define PEM_read_bio_DSAPublicKey(bp,x,cb,u) (DSA *)PEM_ASN1_read_bio( \
	(d2i_of_void *)d2i_DSAPublicKey, PEM_STRING_DSA_PUBLIC, (bp), (void **)(x), (cb), (u))
	    dsa = PEM_read_bio_DSAPublicKey(in, NULL, NULL, NULL);
#undef PEM_read_bio_DSAPublicKey
	}
	BIO_free(in);
	if (!dsa) {
	    ossl_clear_error();
	    ossl_raise(eDSAError, "Neither PUB key nor PRIV key");
	}
    }
    if (!EVP_PKEY_assign_DSA(pkey, dsa)) {
	DSA_free(dsa);
	ossl_raise(eDSAError, NULL);
    }

    return self;
}

static VALUE
ossl_dsa_initialize_copy(VALUE self, VALUE other)
{
    EVP_PKEY *pkey;
    DSA *dsa, *dsa_new;

    GetPKey(self, pkey);
    if (EVP_PKEY_base_id(pkey) != EVP_PKEY_NONE)
	ossl_raise(eDSAError, "DSA already initialized");
    GetDSA(other, dsa);

    dsa_new = ASN1_dup((i2d_of_void *)i2d_DSAPrivateKey, (d2i_of_void *)d2i_DSAPrivateKey, (char *)dsa);
    if (!dsa_new)
	ossl_raise(eDSAError, "ASN1_dup");

    EVP_PKEY_assign_DSA(pkey, dsa_new);

    return self;
}

/*
 *  call-seq:
 *    dsa.public? -> true | false
 *
 * Indicates whether this DSA instance has a public key associated with it or
 * not. The public key may be retrieved with DSA#public_key.
 */
static VALUE
ossl_dsa_is_public(VALUE self)
{
    DSA *dsa;
    const BIGNUM *bn;

    GetDSA(self, dsa);
    DSA_get0_key(dsa, &bn, NULL);

    return bn ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    dsa.private? -> true | false
 *
 * Indicates whether this DSA instance has a private key associated with it or
 * not. The private key may be retrieved with DSA#private_key.
 */
static VALUE
ossl_dsa_is_private(VALUE self)
{
    DSA *dsa;

    GetDSA(self, dsa);

    return DSA_PRIVATE(self, dsa) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    dsa.export([cipher, password]) -> aString
 *    dsa.to_pem([cipher, password]) -> aString
 *    dsa.to_s([cipher, password]) -> aString
 *
 * Encodes this DSA to its PEM encoding.
 *
 * === Parameters
 * * _cipher_ is an OpenSSL::Cipher.
 * * _password_ is a string containing your password.
 *
 * === Examples
 *  DSA.to_pem -> aString
 *  DSA.to_pem(cipher, 'mypassword') -> aString
 *
 */
static VALUE
ossl_dsa_export(int argc, VALUE *argv, VALUE self)
{
    DSA *dsa;
    BIO *out;
    const EVP_CIPHER *ciph = NULL;
    VALUE cipher, pass, str;

    GetDSA(self, dsa);
    rb_scan_args(argc, argv, "02", &cipher, &pass);
    if (!NIL_P(cipher)) {
	ciph = ossl_evp_get_cipherbyname(cipher);
	pass = ossl_pem_passwd_value(pass);
    }
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDSAError, NULL);
    }
    if (DSA_HAS_PRIVATE(dsa)) {
	if (!PEM_write_bio_DSAPrivateKey(out, dsa, ciph, NULL, 0,
					 ossl_pem_passwd_cb, (void *)pass)){
	    BIO_free(out);
	    ossl_raise(eDSAError, NULL);
	}
    } else {
	if (!PEM_write_bio_DSA_PUBKEY(out, dsa)) {
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
 * Encodes this DSA to its DER encoding.
 *
 */
static VALUE
ossl_dsa_to_der(VALUE self)
{
    DSA *dsa;
    int (*i2d_func)(DSA *, unsigned char **);
    unsigned char *p;
    long len;
    VALUE str;

    GetDSA(self, dsa);
    if(DSA_HAS_PRIVATE(dsa))
	i2d_func = (int (*)(DSA *,unsigned char **))i2d_DSAPrivateKey;
    else
	i2d_func = i2d_DSA_PUBKEY;
    if((len = i2d_func(dsa, NULL)) <= 0)
	ossl_raise(eDSAError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_func(dsa, &p) < 0)
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
    DSA *dsa;
    VALUE hash;
    const BIGNUM *p, *q, *g, *pub_key, *priv_key;

    GetDSA(self, dsa);
    DSA_get0_pqg(dsa, &p, &q, &g);
    DSA_get0_key(dsa, &pub_key, &priv_key);

    hash = rb_hash_new();
    rb_hash_aset(hash, rb_str_new2("p"), ossl_bn_new(p));
    rb_hash_aset(hash, rb_str_new2("q"), ossl_bn_new(q));
    rb_hash_aset(hash, rb_str_new2("g"), ossl_bn_new(g));
    rb_hash_aset(hash, rb_str_new2("pub_key"), ossl_bn_new(pub_key));
    rb_hash_aset(hash, rb_str_new2("priv_key"), ossl_bn_new(priv_key));

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
    DSA *dsa;
    BIO *out;
    VALUE str;

    GetDSA(self, dsa);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDSAError, NULL);
    }
    if (!DSA_print(out, dsa, 0)) { /* offset = 0 */
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
 * Returns a new DSA instance that carries just the public key information.
 * If the current instance has also private key information, this will no
 * longer be present in the new instance. This feature is helpful for
 * publishing the public key information without leaking any of the private
 * information.
 *
 * === Example
 *  dsa = OpenSSL::PKey::DSA.new(2048) # has public and private information
 *  pub_key = dsa.public_key # has only the public part available
 *  pub_key_der = pub_key.to_der # it's safe to publish this
 *
 *
 */
static VALUE
ossl_dsa_to_public_key(VALUE self)
{
    EVP_PKEY *pkey;
    DSA *dsa;
    VALUE obj;

    GetPKeyDSA(self, pkey);
    /* err check performed by dsa_instance */
#define DSAPublicKey_dup(dsa) (DSA *)ASN1_dup( \
	(i2d_of_void *)i2d_DSAPublicKey, (d2i_of_void *)d2i_DSAPublicKey, (char *)(dsa))
    dsa = DSAPublicKey_dup(EVP_PKEY_get0_DSA(pkey));
#undef DSAPublicKey_dup
    obj = dsa_instance(rb_obj_class(self), dsa);
    if (obj == Qfalse) {
	DSA_free(dsa);
	ossl_raise(eDSAError, NULL);
    }
    return obj;
}

/*
 *  call-seq:
 *    dsa.syssign(string) -> aString
 *
 * Computes and returns the DSA signature of _string_, where _string_ is
 * expected to be an already-computed message digest of the original input
 * data. The signature is issued using the private key of this DSA instance.
 *
 * === Parameters
 * * _string_ is a message digest of the original input data to be signed.
 *
 * === Example
 *  dsa = OpenSSL::PKey::DSA.new(2048)
 *  doc = "Sign me"
 *  digest = OpenSSL::Digest::SHA1.digest(doc)
 *  sig = dsa.syssign(digest)
 *
 *
 */
static VALUE
ossl_dsa_sign(VALUE self, VALUE data)
{
    DSA *dsa;
    const BIGNUM *dsa_q;
    unsigned int buf_len;
    VALUE str;

    GetDSA(self, dsa);
    DSA_get0_pqg(dsa, NULL, &dsa_q, NULL);
    if (!dsa_q)
	ossl_raise(eDSAError, "incomplete DSA");
    if (!DSA_PRIVATE(self, dsa))
	ossl_raise(eDSAError, "Private DSA key needed!");
    StringValue(data);
    str = rb_str_new(0, DSA_size(dsa));
    if (!DSA_sign(0, (unsigned char *)RSTRING_PTR(data), RSTRING_LENINT(data),
		  (unsigned char *)RSTRING_PTR(str),
		  &buf_len, dsa)) { /* type is ignored (0) */
	ossl_raise(eDSAError, NULL);
    }
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 *  call-seq:
 *    dsa.sysverify(digest, sig) -> true | false
 *
 * Verifies whether the signature is valid given the message digest input. It
 * does so by validating _sig_ using the public key of this DSA instance.
 *
 * === Parameters
 * * _digest_ is a message digest of the original input data to be signed
 * * _sig_ is a DSA signature value
 *
 * === Example
 *  dsa = OpenSSL::PKey::DSA.new(2048)
 *  doc = "Sign me"
 *  digest = OpenSSL::Digest::SHA1.digest(doc)
 *  sig = dsa.syssign(digest)
 *  puts dsa.sysverify(digest, sig) # => true
 *
 */
static VALUE
ossl_dsa_verify(VALUE self, VALUE digest, VALUE sig)
{
    DSA *dsa;
    int ret;

    GetDSA(self, dsa);
    StringValue(digest);
    StringValue(sig);
    /* type is ignored (0) */
    ret = DSA_verify(0, (unsigned char *)RSTRING_PTR(digest), RSTRING_LENINT(digest),
		     (unsigned char *)RSTRING_PTR(sig), RSTRING_LENINT(sig), dsa);
    if (ret < 0) {
	ossl_raise(eDSAError, NULL);
    }
    else if (ret == 1) {
	return Qtrue;
    }

    return Qfalse;
}

/*
 * Document-method: OpenSSL::PKey::DSA#set_pqg
 * call-seq:
 *   dsa.set_pqg(p, q, g) -> self
 *
 * Sets _p_, _q_, _g_ to the DSA instance.
 */
OSSL_PKEY_BN_DEF3(dsa, DSA, pqg, p, q, g)
/*
 * Document-method: OpenSSL::PKey::DSA#set_key
 * call-seq:
 *   dsa.set_key(pub_key, priv_key) -> self
 *
 * Sets _pub_key_ and _priv_key_ for the DSA instance. _priv_key_ may be +nil+.
 */
OSSL_PKEY_BN_DEF2(dsa, DSA, key, pub_key, priv_key)

/*
 * INIT
 */
void
Init_ossl_dsa(void)
{
#if 0
    mPKey = rb_define_module_under(mOSSL, "PKey");
    cPKey = rb_define_class_under(mPKey, "PKey", rb_cObject);
    ePKeyError = rb_define_class_under(mPKey, "PKeyError", eOSSLError);
#endif

    /* Document-class: OpenSSL::PKey::DSAError
     *
     * Generic exception that is raised if an operation on a DSA PKey
     * fails unexpectedly or in case an instantiation of an instance of DSA
     * fails due to non-conformant input data.
     */
    eDSAError = rb_define_class_under(mPKey, "DSAError", ePKeyError);

    /* Document-class: OpenSSL::PKey::DSA
     *
     * DSA, the Digital Signature Algorithm, is specified in NIST's
     * FIPS 186-3. It is an asymmetric public key algorithm that may be used
     * similar to e.g. RSA.
     */
    cDSA = rb_define_class_under(mPKey, "DSA", cPKey);

    rb_define_singleton_method(cDSA, "generate", ossl_dsa_s_generate, 1);
    rb_define_method(cDSA, "initialize", ossl_dsa_initialize, -1);
    rb_define_method(cDSA, "initialize_copy", ossl_dsa_initialize_copy, 1);

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
    rb_define_method(cDSA, "set_pqg", ossl_dsa_set_pqg, 3);
    rb_define_method(cDSA, "set_key", ossl_dsa_set_key, 2);

    rb_define_method(cDSA, "params", ossl_dsa_get_params, 0);
}

#else /* defined NO_DSA */
void
Init_ossl_dsa(void)
{
}
#endif /* NO_DSA */
