/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(OPENSSL_NO_DH)

#include "ossl.h"

#define GetPKeyDH(obj, pkey) do { \
    GetPKey((obj), (pkey)); \
    if (EVP_PKEY_type((pkey)->type) != EVP_PKEY_DH) { /* PARANOIA? */ \
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
    obj = NewPKey(klass);
    if (!(pkey = EVP_PKEY_new())) {
	return Qfalse;
    }
    if (!EVP_PKEY_assign_DH(pkey, dh)) {
	EVP_PKEY_free(pkey);
	return Qfalse;
    }
    SetPKey(obj, pkey);

    return obj;
}

VALUE
ossl_dh_new(EVP_PKEY *pkey)
{
    VALUE obj;

    if (!pkey) {
	obj = dh_instance(cDH, DH_new());
    } else {
	obj = NewPKey(cDH);
	if (EVP_PKEY_type(pkey->type) != EVP_PKEY_DH) {
	    ossl_raise(rb_eTypeError, "Not a DH key!");
	}
	SetPKey(obj, pkey);
    }
    if (obj == Qfalse) {
	ossl_raise(eDHError, NULL);
    }

    return obj;
}

/*
 * Private
 */
#if defined(HAVE_DH_GENERATE_PARAMETERS_EX) && HAVE_BN_GENCB
struct dh_blocking_gen_arg {
    DH *dh;
    int size;
    int gen;
    BN_GENCB *cb;
    int result;
};

static void *
dh_blocking_gen(void *arg)
{
    struct dh_blocking_gen_arg *gen = (struct dh_blocking_gen_arg *)arg;
    gen->result = DH_generate_parameters_ex(gen->dh, gen->size, gen->gen, gen->cb);
    return 0;
}
#endif

static DH *
dh_generate(int size, int gen)
{
#if defined(HAVE_DH_GENERATE_PARAMETERS_EX) && HAVE_BN_GENCB
    BN_GENCB cb;
    struct ossl_generate_cb_arg cb_arg;
    struct dh_blocking_gen_arg gen_arg;
    DH *dh = DH_new();

    if (!dh) return 0;

    memset(&cb_arg, 0, sizeof(struct ossl_generate_cb_arg));
    if (rb_block_given_p())
	cb_arg.yield = 1;
    BN_GENCB_set(&cb, ossl_generate_cb_2, &cb_arg);
    gen_arg.dh = dh;
    gen_arg.size = size;
    gen_arg.gen = gen;
    gen_arg.cb = &cb;
    if (cb_arg.yield == 1) {
	/* we cannot release GVL when callback proc is supplied */
	dh_blocking_gen(&gen_arg);
    } else {
	/* there's a chance to unblock */
	rb_thread_call_without_gvl(dh_blocking_gen, &gen_arg, ossl_generate_cb_stop, &cb_arg);
    }

    if (!gen_arg.result) {
	DH_free(dh);
	if (cb_arg.state) rb_jump_tag(cb_arg.state);
	return 0;
    }
#else
    DH *dh;

    dh = DH_generate_parameters(size, gen, rb_block_given_p() ? ossl_generate_cb : NULL, NULL);
    if (!dh) return 0;
#endif

    if (!DH_generate_key(dh)) {
        DH_free(dh);
        return 0;
    }

    return dh;
}

/*
 *  call-seq:
 *     DH.generate(size [, generator]) -> dh
 *
 * Creates a new DH instance from scratch by generating the private and public
 * components alike.
 *
 * === Parameters
 * * +size+ is an integer representing the desired key size. Keys smaller than 1024 bits should be considered insecure.
 * * +generator+ is a small number > 1, typically 2 or 5.
 *
 */
static VALUE
ossl_dh_s_generate(int argc, VALUE *argv, VALUE klass)
{
    DH *dh ;
    int g = 2;
    VALUE size, gen, obj;

    if (rb_scan_args(argc, argv, "11", &size, &gen) == 2) {
	g = NUM2INT(gen);
    }
    dh = dh_generate(NUM2INT(size), g);
    obj = dh_instance(klass, dh);
    if (obj == Qfalse) {
	DH_free(dh);
	ossl_raise(eDHError, NULL);
    }

    return obj;
}

/*
 *  call-seq:
 *     DH.new([size [, generator] | string]) -> dh
 *
 * Either generates a DH instance from scratch or by reading already existing
 * DH parameters from +string+. Note that when reading a DH instance from
 * data that was encoded from a DH instance by using DH#to_pem or DH#to_der
 * the result will *not* contain a public/private key pair yet. This needs to
 * be generated using DH#generate_key! first.
 *
 * === Parameters
 * * +size+ is an integer representing the desired key size. Keys smaller than 1024 bits should be considered insecure.
 * * +generator+ is a small number > 1, typically 2 or 5.
 * * +string+ contains the DER or PEM encoded key.
 *
 * === Examples
 *  DH.new # -> dh
 *  DH.new(1024) # -> dh
 *  DH.new(1024, 5) # -> dh
 *  #Reading DH parameters
 *  dh = DH.new(File.read('parameters.pem')) # -> dh, but no public/private key yet
 *  dh.generate_key! # -> dh with public and private key
 */
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
	    g = NUM2INT(gen);
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
	    OSSL_BIO_reset(in);
	    dh = d2i_DHparams_bio(in, NULL);
	}
	BIO_free(in);
	if (!dh) {
	    ossl_raise(eDHError, NULL);
	}
    }
    if (!EVP_PKEY_assign_DH(pkey, dh)) {
	DH_free(dh);
	ossl_raise(eDHError, NULL);
    }
    return self;
}

/*
 *  call-seq:
 *     dh.public? -> true | false
 *
 * Indicates whether this DH instance has a public key associated with it or
 * not. The public key may be retrieved with DH#pub_key.
 */
static VALUE
ossl_dh_is_public(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyDH(self, pkey);

    return (pkey->pkey.dh->pub_key) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     dh.private? -> true | false
 *
 * Indicates whether this DH instance has a private key associated with it or
 * not. The private key may be retrieved with DH#priv_key.
 */
static VALUE
ossl_dh_is_private(VALUE self)
{
    EVP_PKEY *pkey;

    GetPKeyDH(self, pkey);

    return (DH_PRIVATE(pkey->pkey.dh)) ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     dh.export -> aString
 *     dh.to_pem -> aString
 *     dh.to_s -> aString
 *
 * Encodes this DH to its PEM encoding. Note that any existing per-session
 * public/private keys will *not* get encoded, just the Diffie-Hellman
 * parameters will be encoded.
 */
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

/*
 *  call-seq:
 *     dh.to_der -> aString
 *
 * Encodes this DH to its DER encoding. Note that any existing per-session
 * public/private keys will *not* get encoded, just the Diffie-Hellman
 * parameters will be encoded.

 */
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
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_DHparams(pkey->pkey.dh, &p) < 0)
	ossl_raise(eDHError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 *  call-seq:
 *     dh.params -> hash
 *
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
 *  call-seq:
 *     dh.to_text -> aString
 *
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
 *  call-seq:
 *     dh.public_key -> aDH
 *
 * Returns a new DH instance that carries just the public information, i.e.
 * the prime +p+ and the generator +g+, but no public/private key yet. Such
 * a pair may be generated using DH#generate_key!. The "public key" needed
 * for a key exchange with DH#compute_key is considered as per-session
 * information and may be retrieved with DH#pub_key once a key pair has
 * been generated.
 * If the current instance already contains private information (and thus a
 * valid public/private key pair), this information will no longer be present
 * in the new instance generated by DH#public_key. This feature is helpful for
 * publishing the Diffie-Hellman parameters without leaking any of the private
 * per-session information.
 *
 * === Example
 *  dh = OpenSSL::PKey::DH.new(2048) # has public and private key set
 *  public_key = dh.public_key # contains only prime and generator
 *  parameters = public_key.to_der # it's safe to publish this
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

/*
 *  call-seq:
 *     dh.params_ok? -> true | false
 *
 * Validates the Diffie-Hellman parameters associated with this instance.
 * It checks whether a safe prime and a suitable generator are used. If this
 * is not the case, +false+ is returned.
 */
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

/*
 *  call-seq:
 *     dh.generate_key! -> self
 *
 * Generates a private and public key unless a private key already exists.
 * If this DH instance was generated from public DH parameters (e.g. by
 * encoding the result of DH#public_key), then this method needs to be
 * called first in order to generate the per-session keys before performing
 * the actual key exchange.
 *
 * === Example
 *   dh = OpenSSL::PKey::DH.new(2048)
 *   public_key = dh.public_key #contains no private/public key yet
 *   public_key.generate_key!
 *   puts public_key.private? # => true
 */
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

/*
 *  call-seq:
 *     dh.compute_key(pub_bn) -> aString
 *
 * Returns a String containing a shared secret computed from the other party's public value.
 * See DH_compute_key() for further information.
 *
 * === Parameters
 * * +pub_bn+ is a OpenSSL::BN, *not* the DH instance returned by
 * DH#public_key as that contains the DH parameters only.
 */
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
    if ((len = DH_compute_key((unsigned char *)RSTRING_PTR(str), pub_key, dh)) < 0) {
	ossl_raise(eDHError, NULL);
    }
    rb_str_set_len(str, len);

    return str;
}

OSSL_PKEY_BN(dh, p)
OSSL_PKEY_BN(dh, g)
OSSL_PKEY_BN(dh, pub_key)
OSSL_PKEY_BN(dh, priv_key)

/*
 * INIT
 */
void
Init_ossl_dh(void)
{
#if 0
    mOSSL = rb_define_module("OpenSSL"); /* let rdoc know about mOSSL and mPKey */
    mPKey = rb_define_module_under(mOSSL, "PKey");
#endif

    /* Document-class: OpenSSL::PKey::DHError
     *
     * Generic exception that is raised if an operation on a DH PKey
     * fails unexpectedly or in case an instantiation of an instance of DH
     * fails due to non-conformant input data.
     */
    eDHError = rb_define_class_under(mPKey, "DHError", ePKeyError);
    /* Document-class: OpenSSL::PKey::DH
     *
     * An implementation of the Diffie-Hellman key exchange protocol based on
     * discrete logarithms in finite fields, the same basis that DSA is built
     * on.
     *
     * === Accessor methods for the Diffie-Hellman parameters
     * * DH#p
     * The prime (an OpenSSL::BN) of the Diffie-Hellman parameters.
     * * DH#g
     * The generator (an OpenSSL::BN) g of the Diffie-Hellman parameters.
     * * DH#pub_key
     * The per-session public key (an OpenSSL::BN) matching the private key.
     * This needs to be passed to DH#compute_key.
     * * DH#priv_key
     * The per-session private key, an OpenSSL::BN.
     *
     * === Example of a key exchange
     *  dh1 = OpenSSL::PKey::DH.new(2048)
     *  der = dh1.public_key.to_der #you may send this publicly to the participating party
     *  dh2 = OpenSSL::PKey::DH.new(der)
     *  dh2.generate_key! #generate the per-session key pair
     *  symm_key1 = dh1.compute_key(dh2.pub_key)
     *  symm_key2 = dh2.compute_key(dh1.pub_key)
     *
     *  puts symm_key1 == symm_key2 # => true
     */
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
void
Init_ossl_dh(void)
{
}
#endif /* NO_DH */
