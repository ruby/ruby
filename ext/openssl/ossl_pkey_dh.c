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
#if !defined(OPENSSL_NO_DH)

#include "ossl.h"

#define GetPKeyDH(obj, pkey) do { \
    GetPKey(obj, pkey); \
    if (EVP_PKEY_type(pkey->type) != EVP_PKEY_DH) { /* PARANOIA? */ \
	ossl_raise(rb_eRuntimeError, "THIS IS NOT A DH!") ; \
    } \
} while (0)

#define DH_HAS_PRIVATE(dh) ((dh)->priv_key)

#ifdef OSSL_ENGINE_ENABLED
#  define DH_PRIVATE(dh) (DH_HAS_PRIVATE(dh) || (dh)->engine)
#else
#  define DH_PRIVATE(dh) DH_HAS_PRIVATE(dh)
#endif


/*
 * Classes
 */
VALUE cDH;
VALUE eDHError;

/*
 * Public
 */
static VALUE
dh_instance(VALUE klass, DH *dh)
{
    EVP_PKEY *pkey;
    VALUE obj;
	
    if (!dh) {
	return Qfalse;
    }
    if (!(pkey = EVP_PKEY_new())) {
	return Qfalse;
    }
    if (!EVP_PKEY_assign_DH(pkey, dh)) {
	EVP_PKEY_free(pkey);
	return Qfalse;
    }
    WrapPKey(klass, obj, pkey);

    return obj;
}

VALUE
ossl_dh_new(EVP_PKEY *pkey)
{
    VALUE obj;

    if (!pkey) {
	obj = dh_instance(cDH, DH_new());
    } else {
	if (EVP_PKEY_type(pkey->type) != EVP_PKEY_DH) {
	    ossl_raise(rb_eTypeError, "Not a DH key!");
	}
	WrapPKey(cDH, obj, pkey);
    }
    if (obj == Qfalse) {
	ossl_raise(eDHError, NULL);
    }

    return obj;
}

/*
 * Private
 */
static DH *
dh_generate(int size, int gen)
{
    DH *dh;
    
    dh = DH_generate_parameters(size, gen,
	    rb_block_given_p() ? ossl_generate_cb : NULL,
	    NULL);
    if (!dh) return 0;

    if (!DH_generate_key(dh)) {
	DH_free(dh);
	return 0;
    }

    return dh;
}

static VALUE
ossl_dh_s_generate(int argc, VALUE *argv, VALUE klass)
{
    DH *dh ;
    int g = 2;
    VALUE size, gen, obj;
	
    if (rb_scan_args(argc, argv, "11", &size, &gen) == 2) {
	g = FIX2INT(gen);
    }
    dh = dh_generate(FIX2INT(size), g);
    obj = dh_instance(klass, dh);
    if (obj == Qfalse) {
	DH_free(dh);
	ossl_raise(eDHError, NULL);
    }

    return obj;
}

static VALUE
ossl_dh_initialize(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    DH *dh;
    int g = 2;
    BIO *in;
    VALUE arg, gen;

    GetPKey(self, pkey);
    if(rb_scan_args(argc, argv, "02", &arg, &gen) == 0) {
      dh = DH_new();
    }
    else if (FIXNUM_P(arg)) {
	if (!NIL_P(gen)) {
	    g = FIX2INT(gen);
	}
	if (!(dh = dh_generate(FIX2INT(arg), g))) {
	    ossl_raise(eDHError, NULL);
	}
    }
    else {
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(arg);
	dh = PEM_read_bio_DHparams(in, NULL, NULL, NULL);
	if (!dh){
	    BIO_reset(in);
	    dh = d2i_DHparams_bio(in, NULL);
	}
	BIO_free(in);
	if (!dh) ossl_raise(eDHError, NULL);
    }
    if (!EVP_PKEY_assign_DH(pkey, dh)) {
	DH_free(dh);
	ossl_raise(eDHError, NULL);
    }
    return self;
}

static VALUE
ossl_dh_is_public(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyDH(self, pkey);
    /*
     * Do we need to check dhp->dh->public_pkey?
     * return Qtrue;
     */
    return (pkey->pkey.dh->pub_key) ? Qtrue : Qfalse;
}

static VALUE
ossl_dh_is_private(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyDH(self, pkey);
	
    return (DH_PRIVATE(pkey->pkey.dh)) ? Qtrue : Qfalse;
}

static VALUE
ossl_dh_export(VALUE self)
{
    EVP_PKEY *pkey;
    BIO *out;
    VALUE str;

    GetPKeyDH(self, pkey);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDHError, NULL);
    }
    if (!PEM_write_bio_DHparams(out, pkey->pkey.dh)) {
	BIO_free(out);
	ossl_raise(eDHError, NULL);
    }
    str = ossl_membio2str(out);

    return str;
}

static VALUE
ossl_dh_to_der(VALUE self)
{       
    EVP_PKEY *pkey;
    unsigned char *p;
    long len;
    VALUE str;

    GetPKeyDH(self, pkey);
    if((len = i2d_DHparams(pkey->pkey.dh, NULL)) <= 0)
	ossl_raise(eDHError, NULL);
    str = rb_str_new(0, len);
    p = RSTRING(str)->ptr;
    if(i2d_DHparams(pkey->pkey.dh, &p) < 0)
	ossl_raise(eDHError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 * Stores all parameters of key to the hash
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (I's up to you)
 */
static VALUE
ossl_dh_get_params(VALUE self)
{
    EVP_PKEY *pkey;
    VALUE hash;

    GetPKeyDH(self, pkey);

    hash = rb_hash_new();

    rb_hash_aset(hash, rb_str_new2("p"), ossl_bn_new(pkey->pkey.dh->p));
    rb_hash_aset(hash, rb_str_new2("g"), ossl_bn_new(pkey->pkey.dh->g));
    rb_hash_aset(hash, rb_str_new2("pub_key"), ossl_bn_new(pkey->pkey.dh->pub_key));
    rb_hash_aset(hash, rb_str_new2("priv_key"), ossl_bn_new(pkey->pkey.dh->priv_key));
    
    return hash;
}

/*
 * Prints all parameters of key to buffer
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (I's up to you)
 */
static VALUE
ossl_dh_to_text(VALUE self)
{
    EVP_PKEY *pkey;
    BIO *out;
    VALUE str;

    GetPKeyDH(self, pkey);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDHError, NULL);
    }
    if (!DHparams_print(out, pkey->pkey.dh)) {
	BIO_free(out);
	ossl_raise(eDHError, NULL);
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 * Makes new instance DH PUBLIC_KEY from PRIVATE_KEY
 */
static VALUE
ossl_dh_to_public_key(VALUE self)
{
    EVP_PKEY *pkey;
    DH *dh;
    VALUE obj;
	
    GetPKeyDH(self, pkey);
    dh = DHparams_dup(pkey->pkey.dh); /* err check perfomed by dh_instance */
    obj = dh_instance(CLASS_OF(self), dh);
    if (obj == Qfalse) {
	DH_free(dh);
	ossl_raise(eDHError, NULL);
    }

    return obj;
}

static VALUE
ossl_dh_check_params(VALUE self)
{
    DH *dh;
    EVP_PKEY *pkey;
    int codes;
    
    GetPKeyDH(self, pkey);
    dh = pkey->pkey.dh;

    if (!DH_check(dh, &codes)) {
	return Qfalse;
    }

    return codes == 0 ? Qtrue : Qfalse;
}

static VALUE
ossl_dh_generate_key(VALUE self)
{
    DH *dh;
    EVP_PKEY *pkey;

    GetPKeyDH(self, pkey);
    dh = pkey->pkey.dh;

    if (!DH_generate_key(dh))
	ossl_raise(eDHError, "Failed to generate key");
    return self;
}

static VALUE
ossl_dh_compute_key(VALUE self, VALUE pub)
{
    DH *dh;
    EVP_PKEY *pkey;
    BIGNUM *pub_key;
    VALUE str;
    int len;

    GetPKeyDH(self, pkey);
    dh = pkey->pkey.dh;
    pub_key = GetBNPtr(pub);
    len = DH_size(dh);
    str = rb_str_new(0, len);
    if ((len = DH_compute_key(RSTRING(str)->ptr, pub_key, dh)) < 0) {
	ossl_raise(eDHError, NULL);
    }
    RSTRING(str)->len = len;
    RSTRING(str)->ptr[len] = 0;

    return str;
}

OSSL_PKEY_BN(dh, p);
OSSL_PKEY_BN(dh, g);
OSSL_PKEY_BN(dh, pub_key);
OSSL_PKEY_BN(dh, priv_key);

/*
 * INIT
 */
void
Init_ossl_dh()
{
    eDHError = rb_define_class_under(mPKey, "DHError", ePKeyError);

    cDH = rb_define_class_under(mPKey, "DH", cPKey);
	
    rb_define_singleton_method(cDH, "generate", ossl_dh_s_generate, -1);
    rb_define_method(cDH, "initialize", ossl_dh_initialize, -1);

    rb_define_method(cDH, "public?", ossl_dh_is_public, 0);
    rb_define_method(cDH, "private?", ossl_dh_is_private, 0);
    rb_define_method(cDH, "to_text", ossl_dh_to_text, 0);
    rb_define_method(cDH, "export", ossl_dh_export, 0);
    rb_define_alias(cDH, "to_pem", "export");
    rb_define_alias(cDH, "to_s", "export");
    rb_define_method(cDH, "to_der", ossl_dh_to_der, 0);
    rb_define_method(cDH, "public_key", ossl_dh_to_public_key, 0);

    rb_define_method(cDH, "params_ok?", ossl_dh_check_params, 0);
    rb_define_method(cDH, "generate_key!", ossl_dh_generate_key, 0);
    rb_define_method(cDH, "compute_key", ossl_dh_compute_key, 1);

    DEF_OSSL_PKEY_BN(cDH, dh, p);
    DEF_OSSL_PKEY_BN(cDH, dh, g);
    DEF_OSSL_PKEY_BN(cDH, dh, pub_key);
    DEF_OSSL_PKEY_BN(cDH, dh, priv_key);

    rb_define_method(cDH, "params", ossl_dh_get_params, 0);
}

#else /* defined NO_DH */
#   warning >>> OpenSSL is compiled without DH support <<<

void
Init_ossl_dh()
{
    rb_warning("OpenSSL is compiled without DH support");
}
#endif /* NO_DH */

