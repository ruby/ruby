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
    VALUE klass, obj;
    int type;

    if (!pkey || (type = EVP_PKEY_base_id(pkey)) == EVP_PKEY_NONE)
	ossl_raise(rb_eRuntimeError, "pkey is empty");

    switch (type) {
#if !defined(OPENSSL_NO_RSA)
      case EVP_PKEY_RSA: klass = cRSA; break;
#endif
#if !defined(OPENSSL_NO_DSA)
      case EVP_PKEY_DSA: klass = cDSA; break;
#endif
#if !defined(OPENSSL_NO_DH)
      case EVP_PKEY_DH:  klass = cDH; break;
#endif
#if !defined(OPENSSL_NO_EC)
      case EVP_PKEY_EC:  klass = cEC; break;
#endif
      default:           klass = cPKey; break;
    }
    obj = NewPKey(klass);
    SetPKey(obj, pkey);
    return obj;
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

EVP_PKEY *
ossl_pkey_read_generic(BIO *bio, VALUE pass)
{
    void *ppass = (void *)pass;
    EVP_PKEY *pkey;

    if ((pkey = d2i_PrivateKey_bio(bio, NULL)))
	goto out;
    OSSL_BIO_reset(bio);
    if ((pkey = d2i_PKCS8PrivateKey_bio(bio, NULL, ossl_pem_passwd_cb, ppass)))
	goto out;
    OSSL_BIO_reset(bio);
    if ((pkey = d2i_PUBKEY_bio(bio, NULL)))
	goto out;
    OSSL_BIO_reset(bio);
    /* PEM_read_bio_PrivateKey() also parses PKCS #8 formats */
    if ((pkey = PEM_read_bio_PrivateKey(bio, NULL, ossl_pem_passwd_cb, ppass)))
	goto out;
    OSSL_BIO_reset(bio);
    if ((pkey = PEM_read_bio_PUBKEY(bio, NULL, NULL, NULL)))
	goto out;
    OSSL_BIO_reset(bio);
    if ((pkey = PEM_read_bio_Parameters(bio, NULL)))
	goto out;

  out:
    return pkey;
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
 * * _string_ is a DER- or PEM-encoded string containing an arbitrary private
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
    bio = ossl_obj2bio(&data);
    pkey = ossl_pkey_read_generic(bio, ossl_pem_passwd_value(pass));
    BIO_free(bio);
    if (!pkey)
	ossl_raise(ePKeyError, "Could not parse PKey");
    return ossl_pkey_new(pkey);
}

static VALUE
pkey_gen_apply_options_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ctx_v))
{
    VALUE key = rb_ary_entry(i, 0), value = rb_ary_entry(i, 1);
    EVP_PKEY_CTX *ctx = (EVP_PKEY_CTX *)ctx_v;

    if (SYMBOL_P(key))
        key = rb_sym2str(key);
    value = rb_String(value);

    if (EVP_PKEY_CTX_ctrl_str(ctx, StringValueCStr(key), StringValueCStr(value)) <= 0)
        ossl_raise(ePKeyError, "EVP_PKEY_CTX_ctrl_str(ctx, %+"PRIsVALUE", %+"PRIsVALUE")",
                   key, value);
    return Qnil;
}

static VALUE
pkey_gen_apply_options0(VALUE args_v)
{
    VALUE *args = (VALUE *)args_v;

    rb_block_call(args[1], rb_intern("each"), 0, NULL,
                  pkey_gen_apply_options_i, args[0]);
    return Qnil;
}

struct pkey_blocking_generate_arg {
    EVP_PKEY_CTX *ctx;
    EVP_PKEY *pkey;
    int state;
    int yield: 1;
    int genparam: 1;
    int stop: 1;
};

static VALUE
pkey_gen_cb_yield(VALUE ctx_v)
{
    EVP_PKEY_CTX *ctx = (void *)ctx_v;
    int i, info_num;
    VALUE *argv;

    info_num = EVP_PKEY_CTX_get_keygen_info(ctx, -1);
    argv = ALLOCA_N(VALUE, info_num);
    for (i = 0; i < info_num; i++)
        argv[i] = INT2NUM(EVP_PKEY_CTX_get_keygen_info(ctx, i));

    return rb_yield_values2(info_num, argv);
}

static int
pkey_gen_cb(EVP_PKEY_CTX *ctx)
{
    struct pkey_blocking_generate_arg *arg = EVP_PKEY_CTX_get_app_data(ctx);

    if (arg->yield) {
        int state;
        rb_protect(pkey_gen_cb_yield, (VALUE)ctx, &state);
        if (state) {
            arg->stop = 1;
            arg->state = state;
        }
    }
    return !arg->stop;
}

static void
pkey_blocking_gen_stop(void *ptr)
{
    struct pkey_blocking_generate_arg *arg = ptr;
    arg->stop = 1;
}

static void *
pkey_blocking_gen(void *ptr)
{
    struct pkey_blocking_generate_arg *arg = ptr;

    if (arg->genparam && EVP_PKEY_paramgen(arg->ctx, &arg->pkey) <= 0)
        return NULL;
    if (!arg->genparam && EVP_PKEY_keygen(arg->ctx, &arg->pkey) <= 0)
        return NULL;
    return arg->pkey;
}

static VALUE
pkey_generate(int argc, VALUE *argv, VALUE self, int genparam)
{
    EVP_PKEY_CTX *ctx;
    VALUE alg, options;
    struct pkey_blocking_generate_arg gen_arg = { 0 };
    int state;

    rb_scan_args(argc, argv, "11", &alg, &options);
    if (rb_obj_is_kind_of(alg, cPKey)) {
        EVP_PKEY *base_pkey;

        GetPKey(alg, base_pkey);
        ctx = EVP_PKEY_CTX_new(base_pkey, NULL/* engine */);
        if (!ctx)
            ossl_raise(ePKeyError, "EVP_PKEY_CTX_new");
    }
    else {
        const EVP_PKEY_ASN1_METHOD *ameth;
        ENGINE *tmpeng;
        int pkey_id;

        StringValue(alg);
        ameth = EVP_PKEY_asn1_find_str(&tmpeng, RSTRING_PTR(alg),
                                       RSTRING_LENINT(alg));
        if (!ameth)
            ossl_raise(ePKeyError, "algorithm %"PRIsVALUE" not found", alg);
        EVP_PKEY_asn1_get0_info(&pkey_id, NULL, NULL, NULL, NULL, ameth);
#if !defined(OPENSSL_NO_ENGINE)
        if (tmpeng)
            ENGINE_finish(tmpeng);
#endif

        ctx = EVP_PKEY_CTX_new_id(pkey_id, NULL/* engine */);
        if (!ctx)
            ossl_raise(ePKeyError, "EVP_PKEY_CTX_new_id");
    }

    if (genparam && EVP_PKEY_paramgen_init(ctx) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_PKEY_paramgen_init");
    }
    if (!genparam && EVP_PKEY_keygen_init(ctx) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_PKEY_keygen_init");
    }

    if (!NIL_P(options)) {
        VALUE args[2];

        args[0] = (VALUE)ctx;
        args[1] = options;
        rb_protect(pkey_gen_apply_options0, (VALUE)args, &state);
        if (state) {
            EVP_PKEY_CTX_free(ctx);
            rb_jump_tag(state);
        }
    }

    gen_arg.genparam = genparam;
    gen_arg.ctx = ctx;
    gen_arg.yield = rb_block_given_p();
    EVP_PKEY_CTX_set_app_data(ctx, &gen_arg);
    EVP_PKEY_CTX_set_cb(ctx, pkey_gen_cb);
    if (gen_arg.yield)
        pkey_blocking_gen(&gen_arg);
    else
        rb_thread_call_without_gvl(pkey_blocking_gen, &gen_arg,
                                   pkey_blocking_gen_stop, &gen_arg);
    EVP_PKEY_CTX_free(ctx);
    if (!gen_arg.pkey) {
        if (gen_arg.state) {
            ossl_clear_error();
            rb_jump_tag(gen_arg.state);
        }
        else {
            ossl_raise(ePKeyError, genparam ? "EVP_PKEY_paramgen" : "EVP_PKEY_keygen");
        }
    }

    return ossl_pkey_new(gen_arg.pkey);
}

/*
 * call-seq:
 *    OpenSSL::PKey.generate_parameters(algo_name [, options]) -> pkey
 *
 * Generates new parameters for the algorithm. _algo_name_ is a String that
 * represents the algorithm. The optional argument _options_ is a Hash that
 * specifies the options specific to the algorithm. The order of the options
 * can be important.
 *
 * A block can be passed optionally. The meaning of the arguments passed to
 * the block varies depending on the implementation of the algorithm. The block
 * may be called once or multiple times, or may not even be called.
 *
 * For the supported options, see the documentation for the 'openssl genpkey'
 * utility command.
 *
 * == Example
 *   pkey = OpenSSL::PKey.generate_parameters("DSA", "dsa_paramgen_bits" => 2048)
 *   p pkey.p.num_bits #=> 2048
 */
static VALUE
ossl_pkey_s_generate_parameters(int argc, VALUE *argv, VALUE self)
{
    return pkey_generate(argc, argv, self, 1);
}

/*
 * call-seq:
 *    OpenSSL::PKey.generate_key(algo_name [, options]) -> pkey
 *    OpenSSL::PKey.generate_key(pkey [, options]) -> pkey
 *
 * Generates a new key (pair).
 *
 * If a String is given as the first argument, it generates a new random key
 * for the algorithm specified by the name just as ::generate_parameters does.
 * If an OpenSSL::PKey::PKey is given instead, it generates a new random key
 * for the same algorithm as the key, using the parameters the key contains.
 *
 * See ::generate_parameters for the details of _options_ and the given block.
 *
 * == Example
 *   pkey_params = OpenSSL::PKey.generate_parameters("DSA", "dsa_paramgen_bits" => 2048)
 *   pkey_params.priv_key #=> nil
 *   pkey = OpenSSL::PKey.generate_key(pkey_params)
 *   pkey.priv_key #=> #<OpenSSL::BN 6277...
 */
static VALUE
ossl_pkey_s_generate_key(int argc, VALUE *argv, VALUE self)
{
    return pkey_generate(argc, argv, self, 0);
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

    GetPKey(obj, pkey);
    if (OSSL_PKEY_IS_PRIVATE(obj))
        return pkey;
    /*
     * The EVP API does not provide a way to check if the EVP_PKEY has private
     * components. Assuming it does...
     */
    if (!rb_respond_to(obj, id_private_q))
        return pkey;
    if (RTEST(rb_funcallv(obj, id_private_q, 0, NULL)))
        return pkey;

    rb_raise(rb_eArgError, "private key is needed");
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

VALUE
ossl_pkey_export_traditional(int argc, VALUE *argv, VALUE self, int to_der)
{
    EVP_PKEY *pkey;
    VALUE cipher, pass;
    const EVP_CIPHER *enc = NULL;
    BIO *bio;

    GetPKey(self, pkey);
    rb_scan_args(argc, argv, "02", &cipher, &pass);
    if (!NIL_P(cipher)) {
	enc = ossl_evp_get_cipherbyname(cipher);
	pass = ossl_pem_passwd_value(pass);
    }

    bio = BIO_new(BIO_s_mem());
    if (!bio)
	ossl_raise(ePKeyError, "BIO_new");
    if (to_der) {
	if (!i2d_PrivateKey_bio(bio, pkey)) {
	    BIO_free(bio);
	    ossl_raise(ePKeyError, "i2d_PrivateKey_bio");
	}
    }
    else {
#if OPENSSL_VERSION_NUMBER >= 0x10100000 && !defined(LIBRESSL_VERSION_NUMBER)
	if (!PEM_write_bio_PrivateKey_traditional(bio, pkey, enc, NULL, 0,
						  ossl_pem_passwd_cb,
						  (void *)pass)) {
#else
	char pem_str[80];
	const char *aname;

	EVP_PKEY_asn1_get0_info(NULL, NULL, NULL, NULL, &aname, pkey->ameth);
	snprintf(pem_str, sizeof(pem_str), "%s PRIVATE KEY", aname);
	if (!PEM_ASN1_write_bio((i2d_of_void *)i2d_PrivateKey, pem_str, bio,
				pkey, enc, NULL, 0, ossl_pem_passwd_cb,
				(void *)pass)) {
#endif
	    BIO_free(bio);
	    ossl_raise(ePKeyError, "PEM_write_bio_PrivateKey_traditional");
	}
    }
    return ossl_membio2str(bio);
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

VALUE
ossl_pkey_export_spki(VALUE self, int to_der)
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
    return ossl_pkey_export_spki(self, 1);
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
    return ossl_pkey_export_spki(self, 0);
}

/*
 *  call-seq:
 *      pkey.compare?(another_pkey) -> true | false
 *
 * Used primarily to check if an OpenSSL::X509::Certificate#public_key compares to its private key.
 *
 * == Example
 *   x509 = OpenSSL::X509::Certificate.new(pem_encoded_certificate)
 *   rsa_key = OpenSSL::PKey::RSA.new(pem_encoded_private_key)
 *
 *   rsa_key.compare?(x509.public_key) => true | false
 */
static VALUE
ossl_pkey_compare(VALUE self, VALUE other)
{
    int ret;
    EVP_PKEY *selfPKey;
    EVP_PKEY *otherPKey;

    GetPKey(self, selfPKey);
    GetPKey(other, otherPKey);

    /* Explicitly check the key type given EVP_PKEY_ASN1_METHOD(3)
     * docs param_cmp could return any negative number.
     */
    if (EVP_PKEY_id(selfPKey) != EVP_PKEY_id(otherPKey))
        ossl_raise(rb_eTypeError, "cannot match different PKey types");

    ret = EVP_PKEY_cmp(selfPKey, otherPKey);

    if (ret == 0)
        return Qfalse;
    else if (ret == 1)
        return Qtrue;
    else
        ossl_raise(ePKeyError, "EVP_PKEY_cmp");
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
    const EVP_MD *md = NULL;
    EVP_MD_CTX *ctx;
    size_t siglen;
    int state;
    VALUE sig;

    pkey = GetPrivPKeyPtr(self);
    if (!NIL_P(digest))
        md = ossl_evp_get_digestbyname(digest);
    StringValue(data);

    ctx = EVP_MD_CTX_new();
    if (!ctx)
        ossl_raise(ePKeyError, "EVP_MD_CTX_new");
    if (EVP_DigestSignInit(ctx, NULL, md, /* engine */NULL, pkey) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestSignInit");
    }
#if OPENSSL_VERSION_NUMBER >= 0x10101000 && !defined(LIBRESSL_VERSION_NUMBER)
    if (EVP_DigestSign(ctx, NULL, &siglen, (unsigned char *)RSTRING_PTR(data),
                       RSTRING_LEN(data)) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestSign");
    }
    if (siglen > LONG_MAX)
        rb_raise(ePKeyError, "signature would be too large");
    sig = ossl_str_new(NULL, (long)siglen, &state);
    if (state) {
        EVP_MD_CTX_free(ctx);
        rb_jump_tag(state);
    }
    if (EVP_DigestSign(ctx, (unsigned char *)RSTRING_PTR(sig), &siglen,
                       (unsigned char *)RSTRING_PTR(data),
                       RSTRING_LEN(data)) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestSign");
    }
#else
    if (EVP_DigestSignUpdate(ctx, RSTRING_PTR(data), RSTRING_LEN(data)) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestSignUpdate");
    }
    if (EVP_DigestSignFinal(ctx, NULL, &siglen) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestSignFinal");
    }
    if (siglen > LONG_MAX)
        rb_raise(ePKeyError, "signature would be too large");
    sig = ossl_str_new(NULL, (long)siglen, &state);
    if (state) {
        EVP_MD_CTX_free(ctx);
        rb_jump_tag(state);
    }
    if (EVP_DigestSignFinal(ctx, (unsigned char *)RSTRING_PTR(sig),
                            &siglen) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestSignFinal");
    }
#endif
    EVP_MD_CTX_free(ctx);
    rb_str_set_len(sig, siglen);
    return sig;
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
    const EVP_MD *md = NULL;
    EVP_MD_CTX *ctx;
    int ret;

    GetPKey(self, pkey);
    ossl_pkey_check_public_key(pkey);
    if (!NIL_P(digest))
        md = ossl_evp_get_digestbyname(digest);
    StringValue(sig);
    StringValue(data);

    ctx = EVP_MD_CTX_new();
    if (!ctx)
        ossl_raise(ePKeyError, "EVP_MD_CTX_new");
    if (EVP_DigestVerifyInit(ctx, NULL, md, /* engine */NULL, pkey) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestVerifyInit");
    }
#if OPENSSL_VERSION_NUMBER >= 0x10101000 && !defined(LIBRESSL_VERSION_NUMBER)
    ret = EVP_DigestVerify(ctx, (unsigned char *)RSTRING_PTR(sig),
                           RSTRING_LEN(sig), (unsigned char *)RSTRING_PTR(data),
                           RSTRING_LEN(data));
    EVP_MD_CTX_free(ctx);
    if (ret < 0)
        ossl_raise(ePKeyError, "EVP_DigestVerify");
#else
    if (EVP_DigestVerifyUpdate(ctx, RSTRING_PTR(data), RSTRING_LEN(data)) < 1) {
        EVP_MD_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_DigestVerifyUpdate");
    }
    ret = EVP_DigestVerifyFinal(ctx, (unsigned char *)RSTRING_PTR(sig),
                                RSTRING_LEN(sig));
    EVP_MD_CTX_free(ctx);
    if (ret < 0)
        ossl_raise(ePKeyError, "EVP_DigestVerifyFinal");
#endif
    if (ret)
        return Qtrue;
    else {
        ossl_clear_error();
        return Qfalse;
    }
}

/*
 * call-seq:
 *    pkey.derive(peer_pkey) -> string
 *
 * Derives a shared secret from _pkey_ and _peer_pkey_. _pkey_ must contain
 * the private components, _peer_pkey_ must contain the public components.
 */
static VALUE
ossl_pkey_derive(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey, *peer_pkey;
    EVP_PKEY_CTX *ctx;
    VALUE peer_pkey_obj, str;
    size_t keylen;
    int state;

    GetPKey(self, pkey);
    rb_scan_args(argc, argv, "1", &peer_pkey_obj);
    GetPKey(peer_pkey_obj, peer_pkey);

    ctx = EVP_PKEY_CTX_new(pkey, /* engine */NULL);
    if (!ctx)
        ossl_raise(ePKeyError, "EVP_PKEY_CTX_new");
    if (EVP_PKEY_derive_init(ctx) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_PKEY_derive_init");
    }
    if (EVP_PKEY_derive_set_peer(ctx, peer_pkey) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_PKEY_derive_set_peer");
    }
    if (EVP_PKEY_derive(ctx, NULL, &keylen) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_PKEY_derive");
    }
    if (keylen > LONG_MAX)
        rb_raise(ePKeyError, "derived key would be too large");
    str = ossl_str_new(NULL, (long)keylen, &state);
    if (state) {
        EVP_PKEY_CTX_free(ctx);
        rb_jump_tag(state);
    }
    if (EVP_PKEY_derive(ctx, (unsigned char *)RSTRING_PTR(str), &keylen) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        ossl_raise(ePKeyError, "EVP_PKEY_derive");
    }
    EVP_PKEY_CTX_free(ctx);
    rb_str_set_len(str, keylen);
    return str;
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
    rb_define_module_function(mPKey, "generate_parameters", ossl_pkey_s_generate_parameters, -1);
    rb_define_module_function(mPKey, "generate_key", ossl_pkey_s_generate_key, -1);

    rb_define_alloc_func(cPKey, ossl_pkey_alloc);
    rb_define_method(cPKey, "initialize", ossl_pkey_initialize, 0);
    rb_define_method(cPKey, "oid", ossl_pkey_oid, 0);
    rb_define_method(cPKey, "inspect", ossl_pkey_inspect, 0);
    rb_define_method(cPKey, "private_to_der", ossl_pkey_private_to_der, -1);
    rb_define_method(cPKey, "private_to_pem", ossl_pkey_private_to_pem, -1);
    rb_define_method(cPKey, "public_to_der", ossl_pkey_public_to_der, 0);
    rb_define_method(cPKey, "public_to_pem", ossl_pkey_public_to_pem, 0);
    rb_define_method(cPKey, "compare?", ossl_pkey_compare, 1);

    rb_define_method(cPKey, "sign", ossl_pkey_sign, 2);
    rb_define_method(cPKey, "verify", ossl_pkey_verify, 3);
    rb_define_method(cPKey, "derive", ossl_pkey_derive, -1);

    id_private_q = rb_intern("private?");

    /*
     * INIT rsa, dsa, dh, ec
     */
    Init_ossl_rsa();
    Init_ossl_dsa();
    Init_ossl_dh();
    Init_ossl_ec();
}
