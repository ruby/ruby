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

/*
 * Classes
 */
VALUE mPKey;
VALUE cPKey;
VALUE ePKeyError;
static ID id_private_q;

/*
 * callback for generating keys
 */
static VALUE
call_check_ints0(VALUE arg)
{
    rb_thread_check_ints();
    return Qnil;
}

static void *
call_check_ints(void *arg)
{
    int state;
    rb_protect(call_check_ints0, Qnil, &state);
    return (void *)(VALUE)state;
}

int
ossl_generate_cb_2(int p, int n, BN_GENCB *cb)
{
    VALUE ary;
    struct ossl_generate_cb_arg *arg;
    int state;

    arg = (struct ossl_generate_cb_arg *)BN_GENCB_get_arg(cb);
    if (arg->yield) {
	ary = rb_ary_new2(2);
	rb_ary_store(ary, 0, INT2NUM(p));
	rb_ary_store(ary, 1, INT2NUM(n));

	/*
	* can be break by raising exception or 'break'
	*/
	rb_protect(rb_yield, ary, &state);
	if (state) {
	    arg->state = state;
	    return 0;
	}
    }
    if (arg->interrupted) {
	arg->interrupted = 0;
	state = (int)(VALUE)rb_thread_call_with_gvl(call_check_ints, NULL);
	if (state) {
	    arg->state = state;
	    return 0;
	}
    }
    return 1;
}

void
ossl_generate_cb_stop(void *ptr)
{
    struct ossl_generate_cb_arg *arg = (struct ossl_generate_cb_arg *)ptr;
    arg->interrupted = 1;
}

static void
ossl_evp_pkey_free(void *ptr)
{
    EVP_PKEY_free(ptr);
}

/*
 * Public
 */
const rb_data_type_t ossl_evp_pkey_type = {
    "OpenSSL/EVP_PKEY",
    {
	0, ossl_evp_pkey_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
pkey_new0(EVP_PKEY *pkey)
{
    VALUE obj;
    int type;

    if (!pkey || (type = EVP_PKEY_base_id(pkey)) == EVP_PKEY_NONE)
	ossl_raise(rb_eRuntimeError, "pkey is empty");

    switch (type) {
#if !defined(OPENSSL_NO_RSA)
    case EVP_PKEY_RSA:
	return ossl_rsa_new(pkey);
#endif
#if !defined(OPENSSL_NO_DSA)
    case EVP_PKEY_DSA:
	return ossl_dsa_new(pkey);
#endif
#if !defined(OPENSSL_NO_DH)
    case EVP_PKEY_DH:
	return ossl_dh_new(pkey);
#endif
#if !defined(OPENSSL_NO_EC)
    case EVP_PKEY_EC:
	return ossl_ec_new(pkey);
#endif
    default:
	obj = NewPKey(cPKey);
	SetPKey(obj, pkey);
	return obj;
    }
}

VALUE
ossl_pkey_new(EVP_PKEY *pkey)
{
    VALUE obj;
    int status;

    obj = rb_protect((VALUE (*)(VALUE))pkey_new0, (VALUE)pkey, &status);
    if (status) {
	EVP_PKEY_free(pkey);
	rb_jump_tag(status);
    }

    return obj;
}

/*
 *  call-seq:
 *     OpenSSL::PKey.read(string [, pwd ]) -> PKey
 *     OpenSSL::PKey.read(io [, pwd ]) -> PKey
 *
 * Reads a DER or PEM encoded string from _string_ or _io_ and returns an
 * instance of the appropriate PKey class.
 *
 * === Parameters
 * * _string+ is a DER- or PEM-encoded string containing an arbitrary private
 *   or public key.
 * * _io_ is an instance of IO containing a DER- or PEM-encoded
 *   arbitrary private or public key.
 * * _pwd_ is an optional password in case _string_ or _io_ is an encrypted
 *   PEM resource.
 */
static VALUE
ossl_pkey_new_from_data(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    BIO *bio;
    VALUE data, pass;

    rb_scan_args(argc, argv, "11", &data, &pass);
    pass = ossl_pem_passwd_value(pass);

    bio = ossl_obj2bio(&data);
    if ((pkey = d2i_PrivateKey_bio(bio, NULL)))
	goto ok;
    OSSL_BIO_reset(bio);
    if ((pkey = d2i_PKCS8PrivateKey_bio(bio, NULL, ossl_pem_passwd_cb, (void *)pass)))
	goto ok;
    OSSL_BIO_reset(bio);
    if ((pkey = d2i_PUBKEY_bio(bio, NULL)))
	goto ok;
    OSSL_BIO_reset(bio);
    /* PEM_read_bio_PrivateKey() also parses PKCS #8 formats */
    if ((pkey = PEM_read_bio_PrivateKey(bio, NULL, ossl_pem_passwd_cb, (void *)pass)))
	goto ok;
    OSSL_BIO_reset(bio);
    if ((pkey = PEM_read_bio_PUBKEY(bio, NULL, NULL, NULL)))
	goto ok;

    BIO_free(bio);
    ossl_raise(ePKeyError, "Could not parse PKey");

ok:
    BIO_free(bio);
    return ossl_pkey_new(pkey);
}

void
ossl_pkey_check_public_key(const EVP_PKEY *pkey)
{
    void *ptr;
    const BIGNUM *n, *e, *pubkey;

    if (EVP_PKEY_missing_parameters(pkey))
	ossl_raise(ePKeyError, "parameters missing");

    /* OpenSSL < 1.1.0 takes non-const pointer */
    ptr = EVP_PKEY_get0((EVP_PKEY *)pkey);
    switch (EVP_PKEY_base_id(pkey)) {
      case EVP_PKEY_RSA:
	RSA_get0_key(ptr, &n, &e, NULL);
	if (n && e)
	    return;
	break;
      case EVP_PKEY_DSA:
	DSA_get0_key(ptr, &pubkey, NULL);
	if (pubkey)
	    return;
	break;
      case EVP_PKEY_DH:
	DH_get0_key(ptr, &pubkey, NULL);
	if (pubkey)
	    return;
	break;
#if !defined(OPENSSL_NO_EC)
      case EVP_PKEY_EC:
	if (EC_KEY_get0_public_key(ptr))
	    return;
	break;
#endif
      default:
	/* unsupported type; assuming ok */
	return;
    }
    ossl_raise(ePKeyError, "public key missing");
}

EVP_PKEY *
GetPKeyPtr(VALUE obj)
{
    EVP_PKEY *pkey;

    GetPKey(obj, pkey);

    return pkey;
}

EVP_PKEY *
GetPrivPKeyPtr(VALUE obj)
{
    EVP_PKEY *pkey;

    if (rb_funcallv(obj, id_private_q, 0, NULL) != Qtrue) {
	ossl_raise(rb_eArgError, "Private key is needed.");
    }
    GetPKey(obj, pkey);

    return pkey;
}

EVP_PKEY *
DupPKeyPtr(VALUE obj)
{
    EVP_PKEY *pkey;

    GetPKey(obj, pkey);
    EVP_PKEY_up_ref(pkey);

    return pkey;
}

/*
 * Private
 */
static VALUE
ossl_pkey_alloc(VALUE klass)
{
    EVP_PKEY *pkey;
    VALUE obj;

    obj = NewPKey(klass);
    if (!(pkey = EVP_PKEY_new())) {
	ossl_raise(ePKeyError, NULL);
    }
    SetPKey(obj, pkey);

    return obj;
}

/*
 *  call-seq:
 *      PKeyClass.new -> self
 *
 * Because PKey is an abstract class, actually calling this method explicitly
 * will raise a NotImplementedError.
 */
static VALUE
ossl_pkey_initialize(VALUE self)
{
    if (rb_obj_is_instance_of(self, cPKey)) {
	ossl_raise(rb_eTypeError, "OpenSSL::PKey::PKey can't be instantiated directly");
    }
    return self;
}

/*
 * call-seq:
 *    pkey.oid -> string
 *
 * Returns the short name of the OID associated with _pkey_.
 */
static VALUE
ossl_pkey_oid(VALUE self)
{
    EVP_PKEY *pkey;
    int nid;

    GetPKey(self, pkey);
    nid = EVP_PKEY_id(pkey);
    return rb_str_new_cstr(OBJ_nid2sn(nid));
}

/*
 * call-seq:
 *    pkey.inspect -> string
 *
 * Returns a string describing the PKey object.
 */
static VALUE
ossl_pkey_inspect(VALUE self)
{
    EVP_PKEY *pkey;
    int nid;

    GetPKey(self, pkey);
    nid = EVP_PKEY_id(pkey);
    return rb_sprintf("#<%"PRIsVALUE":%p oid=%s>",
                      rb_class_name(CLASS_OF(self)), (void *)self,
                      OBJ_nid2sn(nid));
}

static VALUE
do_pkcs8_export(int argc, VALUE *argv, VALUE self, int to_der)
{
    EVP_PKEY *pkey;
    VALUE cipher, pass;
    const EVP_CIPHER *enc = NULL;
    BIO *bio;

    GetPKey(self, pkey);
    rb_scan_args(argc, argv, "02", &cipher, &pass);
    if (argc > 0) {
	/*
	 * TODO: EncryptedPrivateKeyInfo actually has more options.
	 * Should they be exposed?
	 */
	enc = ossl_evp_get_cipherbyname(cipher);
	pass = ossl_pem_passwd_value(pass);
    }

    bio = BIO_new(BIO_s_mem());
    if (!bio)
	ossl_raise(ePKeyError, "BIO_new");
    if (to_der) {
	if (!i2d_PKCS8PrivateKey_bio(bio, pkey, enc, NULL, 0,
				     ossl_pem_passwd_cb, (void *)pass)) {
	    BIO_free(bio);
	    ossl_raise(ePKeyError, "i2d_PKCS8PrivateKey_bio");
	}
    }
    else {
	if (!PEM_write_bio_PKCS8PrivateKey(bio, pkey, enc, NULL, 0,
					   ossl_pem_passwd_cb, (void *)pass)) {
	    BIO_free(bio);
	    ossl_raise(ePKeyError, "PEM_write_bio_PKCS8PrivateKey");
	}
    }
    return ossl_membio2str(bio);
}

/*
 * call-seq:
 *    pkey.private_to_der                   -> string
 *    pkey.private_to_der(cipher, password) -> string
 *
 * Serializes the private key to DER-encoded PKCS #8 format. If called without
 * arguments, unencrypted PKCS #8 PrivateKeyInfo format is used. If called with
 * a cipher name and a password, PKCS #8 EncryptedPrivateKeyInfo format with
 * PBES2 encryption scheme is used.
 */
static VALUE
ossl_pkey_private_to_der(int argc, VALUE *argv, VALUE self)
{
    return do_pkcs8_export(argc, argv, self, 1);
}

/*
 * call-seq:
 *    pkey.private_to_pem                   -> string
 *    pkey.private_to_pem(cipher, password) -> string
 *
 * Serializes the private key to PEM-encoded PKCS #8 format. See #private_to_der
 * for more details.
 */
static VALUE
ossl_pkey_private_to_pem(int argc, VALUE *argv, VALUE self)
{
    return do_pkcs8_export(argc, argv, self, 0);
}

static VALUE
do_spki_export(VALUE self, int to_der)
{
    EVP_PKEY *pkey;
    BIO *bio;

    GetPKey(self, pkey);
    bio = BIO_new(BIO_s_mem());
    if (!bio)
	ossl_raise(ePKeyError, "BIO_new");
    if (to_der) {
	if (!i2d_PUBKEY_bio(bio, pkey)) {
	    BIO_free(bio);
	    ossl_raise(ePKeyError, "i2d_PUBKEY_bio");
	}
    }
    else {
	if (!PEM_write_bio_PUBKEY(bio, pkey)) {
	    BIO_free(bio);
	    ossl_raise(ePKeyError, "PEM_write_bio_PUBKEY");
	}
    }
    return ossl_membio2str(bio);
}

/*
 * call-seq:
 *    pkey.public_to_der -> string
 *
 * Serializes the public key to DER-encoded X.509 SubjectPublicKeyInfo format.
 */
static VALUE
ossl_pkey_public_to_der(VALUE self)
{
    return do_spki_export(self, 1);
}

/*
 * call-seq:
 *    pkey.public_to_pem -> string
 *
 * Serializes the public key to PEM-encoded X.509 SubjectPublicKeyInfo format.
 */
static VALUE
ossl_pkey_public_to_pem(VALUE self)
{
    return do_spki_export(self, 0);
}

/*
 *  call-seq:
 *      pkey.sign(digest, data) -> String
 *
 * To sign the String _data_, _digest_, an instance of OpenSSL::Digest, must
 * be provided. The return value is again a String containing the signature.
 * A PKeyError is raised should errors occur.
 * Any previous state of the Digest instance is irrelevant to the signature
 * outcome, the digest instance is reset to its initial state during the
 * operation.
 *
 * == Example
 *   data = 'Sign me!'
 *   digest = OpenSSL::Digest.new('SHA256')
 *   pkey = OpenSSL::PKey::RSA.new(2048)
 *   signature = pkey.sign(digest, data)
 */
static VALUE
ossl_pkey_sign(VALUE self, VALUE digest, VALUE data)
{
    EVP_PKEY *pkey;
    const EVP_MD *md;
    EVP_MD_CTX *ctx;
    unsigned int buf_len;
    VALUE str;
    int result;

    pkey = GetPrivPKeyPtr(self);
    md = ossl_evp_get_digestbyname(digest);
    StringValue(data);
    str = rb_str_new(0, EVP_PKEY_size(pkey));

    ctx = EVP_MD_CTX_new();
    if (!ctx)
	ossl_raise(ePKeyError, "EVP_MD_CTX_new");
    if (!EVP_SignInit_ex(ctx, md, NULL)) {
	EVP_MD_CTX_free(ctx);
	ossl_raise(ePKeyError, "EVP_SignInit_ex");
    }
    if (!EVP_SignUpdate(ctx, RSTRING_PTR(data), RSTRING_LEN(data))) {
	EVP_MD_CTX_free(ctx);
	ossl_raise(ePKeyError, "EVP_SignUpdate");
    }
    result = EVP_SignFinal(ctx, (unsigned char *)RSTRING_PTR(str), &buf_len, pkey);
    EVP_MD_CTX_free(ctx);
    if (!result)
	ossl_raise(ePKeyError, "EVP_SignFinal");
    rb_str_set_len(str, buf_len);

    return str;
}

/*
 *  call-seq:
 *      pkey.verify(digest, signature, data) -> String
 *
 * To verify the String _signature_, _digest_, an instance of
 * OpenSSL::Digest, must be provided to re-compute the message digest of the
 * original _data_, also a String. The return value is +true+ if the
 * signature is valid, +false+ otherwise. A PKeyError is raised should errors
 * occur.
 * Any previous state of the Digest instance is irrelevant to the validation
 * outcome, the digest instance is reset to its initial state during the
 * operation.
 *
 * == Example
 *   data = 'Sign me!'
 *   digest = OpenSSL::Digest.new('SHA256')
 *   pkey = OpenSSL::PKey::RSA.new(2048)
 *   signature = pkey.sign(digest, data)
 *   pub_key = pkey.public_key
 *   puts pub_key.verify(digest, signature, data) # => true
 */
static VALUE
ossl_pkey_verify(VALUE self, VALUE digest, VALUE sig, VALUE data)
{
    EVP_PKEY *pkey;
    const EVP_MD *md;
    EVP_MD_CTX *ctx;
    int siglen, result;

    GetPKey(self, pkey);
    ossl_pkey_check_public_key(pkey);
    md = ossl_evp_get_digestbyname(digest);
    StringValue(sig);
    siglen = RSTRING_LENINT(sig);
    StringValue(data);

    ctx = EVP_MD_CTX_new();
    if (!ctx)
	ossl_raise(ePKeyError, "EVP_MD_CTX_new");
    if (!EVP_VerifyInit_ex(ctx, md, NULL)) {
	EVP_MD_CTX_free(ctx);
	ossl_raise(ePKeyError, "EVP_VerifyInit_ex");
    }
    if (!EVP_VerifyUpdate(ctx, RSTRING_PTR(data), RSTRING_LEN(data))) {
	EVP_MD_CTX_free(ctx);
	ossl_raise(ePKeyError, "EVP_VerifyUpdate");
    }
    result = EVP_VerifyFinal(ctx, (unsigned char *)RSTRING_PTR(sig), siglen, pkey);
    EVP_MD_CTX_free(ctx);
    switch (result) {
    case 0:
	ossl_clear_error();
	return Qfalse;
    case 1:
	return Qtrue;
    default:
	ossl_raise(ePKeyError, "EVP_VerifyFinal");
    }
}

/*
 * INIT
 */
void
Init_ossl_pkey(void)
{
#undef rb_intern
#if 0
    mOSSL = rb_define_module("OpenSSL");
    eOSSLError = rb_define_class_under(mOSSL, "OpenSSLError", rb_eStandardError);
#endif

    /* Document-module: OpenSSL::PKey
     *
     * == Asymmetric Public Key Algorithms
     *
     * Asymmetric public key algorithms solve the problem of establishing and
     * sharing secret keys to en-/decrypt messages. The key in such an
     * algorithm consists of two parts: a public key that may be distributed
     * to others and a private key that needs to remain secret.
     *
     * Messages encrypted with a public key can only be decrypted by
     * recipients that are in possession of the associated private key.
     * Since public key algorithms are considerably slower than symmetric
     * key algorithms (cf. OpenSSL::Cipher) they are often used to establish
     * a symmetric key shared between two parties that are in possession of
     * each other's public key.
     *
     * Asymmetric algorithms offer a lot of nice features that are used in a
     * lot of different areas. A very common application is the creation and
     * validation of digital signatures. To sign a document, the signatory
     * generally uses a message digest algorithm (cf. OpenSSL::Digest) to
     * compute a digest of the document that is then encrypted (i.e. signed)
     * using the private key. Anyone in possession of the public key may then
     * verify the signature by computing the message digest of the original
     * document on their own, decrypting the signature using the signatory's
     * public key and comparing the result to the message digest they
     * previously computed. The signature is valid if and only if the
     * decrypted signature is equal to this message digest.
     *
     * The PKey module offers support for three popular public/private key
     * algorithms:
     * * RSA (OpenSSL::PKey::RSA)
     * * DSA (OpenSSL::PKey::DSA)
     * * Elliptic Curve Cryptography (OpenSSL::PKey::EC)
     * Each of these implementations is in fact a sub-class of the abstract
     * PKey class which offers the interface for supporting digital signatures
     * in the form of PKey#sign and PKey#verify.
     *
     * == Diffie-Hellman Key Exchange
     *
     * Finally PKey also features OpenSSL::PKey::DH, an implementation of
     * the Diffie-Hellman key exchange protocol based on discrete logarithms
     * in finite fields, the same basis that DSA is built on.
     * The Diffie-Hellman protocol can be used to exchange (symmetric) keys
     * over insecure channels without needing any prior joint knowledge
     * between the participating parties. As the security of DH demands
     * relatively long "public keys" (i.e. the part that is overtly
     * transmitted between participants) DH tends to be quite slow. If
     * security or speed is your primary concern, OpenSSL::PKey::EC offers
     * another implementation of the Diffie-Hellman protocol.
     *
     */
    mPKey = rb_define_module_under(mOSSL, "PKey");

    /* Document-class: OpenSSL::PKey::PKeyError
     *
     *Raised when errors occur during PKey#sign or PKey#verify.
     */
    ePKeyError = rb_define_class_under(mPKey, "PKeyError", eOSSLError);

    /* Document-class: OpenSSL::PKey::PKey
     *
     * An abstract class that bundles signature creation (PKey#sign) and
     * validation (PKey#verify) that is common to all implementations except
     * OpenSSL::PKey::DH
     * * OpenSSL::PKey::RSA
     * * OpenSSL::PKey::DSA
     * * OpenSSL::PKey::EC
     */
    cPKey = rb_define_class_under(mPKey, "PKey", rb_cObject);

    rb_define_module_function(mPKey, "read", ossl_pkey_new_from_data, -1);

    rb_define_alloc_func(cPKey, ossl_pkey_alloc);
    rb_define_method(cPKey, "initialize", ossl_pkey_initialize, 0);
    rb_define_method(cPKey, "oid", ossl_pkey_oid, 0);
    rb_define_method(cPKey, "inspect", ossl_pkey_inspect, 0);
    rb_define_method(cPKey, "private_to_der", ossl_pkey_private_to_der, -1);
    rb_define_method(cPKey, "private_to_pem", ossl_pkey_private_to_pem, -1);
    rb_define_method(cPKey, "public_to_der", ossl_pkey_public_to_der, 0);
    rb_define_method(cPKey, "public_to_pem", ossl_pkey_public_to_pem, 0);

    rb_define_method(cPKey, "sign", ossl_pkey_sign, 2);
    rb_define_method(cPKey, "verify", ossl_pkey_verify, 3);

    id_private_q = rb_intern("private?");

    /*
     * INIT rsa, dsa, dh, ec
     */
    Init_ossl_rsa();
    Init_ossl_dsa();
    Init_ossl_dh();
    Init_ossl_ec();
}
