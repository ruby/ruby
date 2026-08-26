/*
 * Ruby/OpenSSL Project
 * Copyright (C) 2026 Ruby/OpenSSL Project Authors
 */
#include "ossl.h"

#if defined(HAVE_OSSL_HPKE_CTX_NEW)

#include <openssl/hpke.h>

typedef struct ossl_hpke_ctx_st {
    OSSL_HPKE_CTX  *ctx;
    OSSL_HPKE_SUITE suite;
} ossl_hpke_ctx_t;

#define GetHpke(obj, data) do {\
    TypedData_Get_Struct((obj), ossl_hpke_ctx_t, &ossl_hpke_ctx_type, (data)); \
    if (!(data)) { \
        rb_raise(rb_eRuntimeError, "OSSL_HPKE_CTX wasn't initialized!");\
    } \
} while (0)

/* Document-module: OpenSSL::HPKE
 *
 * Hybrid Public Key Encryption (HPKE) as defined in RFC 9180. HPKE encrypts
 * messages to the holder of a public key by combining a Key Encapsulation
 * Mechanism (KEM), a Key Derivation Function (KDF), and an AEAD scheme, which
 * together form an OpenSSL::HPKE::Suite.
 *
 * The sender encapsulates a key to the recipient and seals messages through an
 * OpenSSL::HPKE::Context::Sender; the recipient decapsulates that key and opens
 * the messages through an OpenSSL::HPKE::Context::Receiver. Only HPKE base mode
 * is currently supported.
 *
 * Availability depends on the underlying OpenSSL: the HPKE API was added in
 * OpenSSL 3.2.
 */
static VALUE mHPKE;
/*
 * Classes
 */
/* Document-class: OpenSSL::HPKE::Suite
 * Value object that specifies the HPKE cipher suite.
 */
static VALUE cSuite;
/* Document-class: OpenSSL::HPKE::Context
 * Abstract class for HPKE contexts to be used in subsequent HPKE operations.
 * Depending on the actor in the protocol, either Sender or
 * Receiver will be used.
 */
static VALUE cContext;
/* Document-class: OpenSSL::HPKE::Context::Sender
 * The sender's side of an HPKE context. Encapsulates a key to the recipient
 * with #encap and protects messages with #seal.
 */
static VALUE cSenderContext;
/* Document-class: OpenSSL::HPKE::Context::Receiver
 * The recipient's side of an HPKE context. Decapsulates the sender's key with
 * #decap and recovers messages with #open.
 */
static VALUE cReceiverContext;
/* Document-class: OpenSSL::HPKE::HPKEError
 * Generic exception raised when an HPKE operation fails.
 */
static VALUE eHPKEError;

static void
ossl_hpke_ctx_free(void *ptr)
{
    ossl_hpke_ctx_t *data = ptr;

    OSSL_HPKE_CTX_free(data->ctx);
    ruby_xfree(data);
}

static const rb_data_type_t ossl_hpke_ctx_type = {
    "OpenSSL/HPKE_CTX",
    {
        0, ossl_hpke_ctx_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

#define GetHpkeSuite(obj, suite) do {\
    TypedData_Get_Struct((obj), OSSL_HPKE_SUITE, &ossl_hpke_suite_type, (suite)); \
    if (!(suite)) { \
        rb_raise(rb_eRuntimeError, "OSSL_HPKE_SUITE wasn't initialized!");\
    } \
} while (0)

static void
ossl_hpke_suite_free(void *ptr)
{
    ruby_xfree(ptr);
}

static size_t
ossl_hpke_suite_memsize(const void *ptr)
{
    return sizeof(OSSL_HPKE_SUITE);
}

static const rb_data_type_t ossl_hpke_suite_type = {
    "OpenSSL/HPKE_SUITE",
    {
        0, ossl_hpke_suite_free, ossl_hpke_suite_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

/*
 * call-seq:
 *    new(suite) -> sender_context
 *
 * Takes a OpenSSL::HPKE::Suite to generate a Context for the sender.
 * Currently assumes Base mode as the HPKE mode.
 */
static VALUE
ossl_hpke_ctx_new_sender(VALUE self, VALUE suite)
{
    ossl_hpke_ctx_t *data;
    OSSL_HPKE_SUITE *suite_st;

    ossl_want_uninitialized(self, &ossl_hpke_ctx_type);
    if (!rb_obj_is_kind_of(suite, cSuite))
        ossl_raise(eHPKEError, "invalid suite specified");
    GetHpkeSuite(suite, suite_st);

    data = ALLOC(ossl_hpke_ctx_t);
    data->ctx = NULL;
    data->suite = *suite_st;

    data->ctx = OSSL_HPKE_CTX_new(OSSL_HPKE_MODE_BASE, data->suite,
                                  OSSL_HPKE_ROLE_SENDER, NULL, NULL);
    if (data->ctx == NULL) {
        ruby_xfree(data);
        ossl_raise(eHPKEError, "could not create ctx");
    }

    RTYPEDDATA_DATA(self) = data;
    return self;
}

/*
 * call-seq:
 *    new(suite) -> receiver_context
 *
 * Takes a OpenSSL::HPKE::Suite to generate a Context for the receiver.
 * Currently assumes Base mode as the HPKE mode.
 */
static VALUE
ossl_hpke_ctx_new_receiver(VALUE self, VALUE suite)
{
    ossl_hpke_ctx_t *data;
    OSSL_HPKE_SUITE *suite_st;

    ossl_want_uninitialized(self, &ossl_hpke_ctx_type);
    if (!rb_obj_is_kind_of(suite, cSuite))
        ossl_raise(eHPKEError, "invalid suite specified");
    GetHpkeSuite(suite, suite_st);

    data = ALLOC(ossl_hpke_ctx_t);
    data->ctx = NULL;
    data->suite = *suite_st;

    data->ctx = OSSL_HPKE_CTX_new(OSSL_HPKE_MODE_BASE, data->suite,
                                  OSSL_HPKE_ROLE_RECEIVER, NULL, NULL);
    if (data->ctx == NULL) {
        ruby_xfree(data);
        ossl_raise(eHPKEError, "could not create ctx");
    }

    RTYPEDDATA_DATA(self) = data;
    return self;
}

/*
 * call-seq:
 *    encap(pub, info) -> encapsulated_key
 *
 * Takes a public key (OpenSSL::PKey) of the receiver and +info+ string
 * (application context information; value that separates the domain in which
 * the key is used), and encapsulates a key to be used in subsequent operations.
 * Returns the encapsulated key as a String, which is to be passed to the
 * receiver of the following messages.
 */
static VALUE
ossl_hpke_encap(VALUE self, VALUE pub, VALUE info)
{
    VALUE enc_obj;
    size_t enclen;
    ossl_hpke_ctx_t *data;
    size_t publen;
    size_t infolen;

    GetHpke(self, data);

    StringValue(pub);
    StringValue(info);
    publen = RSTRING_LEN(pub);
    infolen = RSTRING_LEN(info);

    enclen = OSSL_HPKE_get_public_encap_size(data->suite);
    enc_obj = rb_str_new(0, enclen);

    if (OSSL_HPKE_encap(data->ctx, (unsigned char *)RSTRING_PTR(enc_obj), &enclen,
                        (unsigned char *)RSTRING_PTR(pub), publen,
                        (unsigned char *)RSTRING_PTR(info), infolen) != 1) {
        ossl_raise(eHPKEError, "could not encap");
    }

    rb_str_resize(enc_obj, enclen);
    return enc_obj;
}

/*
 * call-seq:
 *    seal(aad, plaintext) -> sealed_message
 *
 * Seals (encrypts) the +plaintext+ using the +Context+'s AEAD. +aad+ is
 * extra data authenticated with, but not encrypted into, the ciphertext, and
 * must be supplied identically to Receiver#open.
 */
static VALUE
ossl_hpke_seal(VALUE self, VALUE aad, VALUE pt)
{
    VALUE ct_obj;
    ossl_hpke_ctx_t *data;
    size_t ctlen, aadlen, ptlen;

    GetHpke(self, data);

    StringValue(aad);
    StringValue(pt);
    aadlen = RSTRING_LEN(aad);
    ptlen  = RSTRING_LEN(pt);
    ctlen = OSSL_HPKE_get_ciphertext_size(data->suite, ptlen);

    ct_obj = rb_str_new(0, ctlen);

    if (OSSL_HPKE_seal(data->ctx, (unsigned char *)RSTRING_PTR(ct_obj), &ctlen,
                       (unsigned char *)RSTRING_PTR(aad), aadlen,
                       (unsigned char *)RSTRING_PTR(pt), ptlen) != 1) {
        ossl_raise(eHPKEError, "could not seal");
    }

    return ct_obj;
}

/*
 * call-seq:
 *    decap(enc, priv, info) -> true
 *
 * Takes the encapsulated key +enc+ (a String produced by the sender's
 * Sender#encap), the receiver's own private key (OpenSSL::PKey), and +info+
 * string (application context information; value that separates the domain in
 * which the key is used), and decapsulates the key to be used in subsequent
 * operations. The +info+ must be identical to the one given to Sender#encap.
 * Returns +true+ on success.
 */
static VALUE
ossl_hpke_decap(VALUE self, VALUE enc, VALUE priv, VALUE info)
{
    ossl_hpke_ctx_t *data;
    EVP_PKEY *pkey;
    size_t enclen;
    size_t infolen;

    GetHpke(self, data);
    GetPKey(priv, pkey);

    StringValue(enc);
    StringValue(info);
    enclen = RSTRING_LEN(enc);
    infolen = RSTRING_LEN(info);

    if (OSSL_HPKE_decap(data->ctx, (unsigned char *)RSTRING_PTR(enc), enclen, pkey,
                        (unsigned char *)RSTRING_PTR(info), infolen) != 1) {
        ossl_raise(eHPKEError, "could not decap");
    }

    return Qtrue;
}

/*
 * call-seq:
 *    open(aad, ciphertext) -> plaintext
 *
 * Opens (decrypts) the +ciphertext+ using the +Context+'s AEAD and returns the
 * recovered plaintext. +aad+ is extra data authenticated with, but not
 * encrypted into, the ciphertext, and must be identical to the +aad+ supplied
 * to Sender#seal, otherwise opening fails.
 */
static VALUE
ossl_hpke_open(VALUE self, VALUE aad, VALUE ct)
{
    VALUE pt_obj;
    ossl_hpke_ctx_t *data;
    size_t ptlen, aadlen, ctlen;

    StringValue(aad);
    StringValue(ct);
    aadlen = RSTRING_LEN(aad);
    ctlen  = RSTRING_LEN(ct);
    ptlen = ctlen;

    pt_obj = rb_str_new(0, ptlen);

    GetHpke(self, data);

    if (OSSL_HPKE_open(data->ctx, (unsigned char *)RSTRING_PTR(pt_obj), &ptlen,
                       (unsigned char *)RSTRING_PTR(aad), aadlen,
                       (unsigned char *)RSTRING_PTR(ct), ctlen) != 1) {
        ossl_raise(eHPKEError, "could not open");
    }

    rb_str_resize(pt_obj, ptlen);

    return pt_obj;
}

/*
 * call-seq:
 *    export(secretlen, label) -> secret
 *
 * Derives and returns a +secretlen+-byte exporter secret bound to +label+,
 * as a String. Both parties obtain the same secret only after the shared
 * context has been established: the sender via Sender#encap and the receiver
 * via Receiver#decap. Different +label+ values yield independent secrets.
 */
static VALUE
ossl_hpke_export(VALUE self, VALUE secretlen, VALUE label)
{
    VALUE secret_obj;
    ossl_hpke_ctx_t *data;
    size_t labellen;
    int outlen = NUM2INT(secretlen);

    StringValue(label);
    labellen = RSTRING_LEN(label);

    secret_obj = rb_str_new(0, outlen);

    GetHpke(self, data);
    if (OSSL_HPKE_export(data->ctx, (unsigned char *)RSTRING_PTR(secret_obj),
                         outlen, (unsigned char *)RSTRING_PTR(label),
                         labellen) != 1) {
        ossl_raise(eHPKEError, "could not export");
    }

    return secret_obj;
}

/* Suite */
static uint16_t
ossl_hpke_suite_id(VALUE num, const char *label)
{
    long id = NUM2LONG(num);

    if (id < 0 || id > 0xFFFF)
        ossl_raise(eHPKEError, "%s id out of range (0..0xFFFF): %ld", label, id);

    return (uint16_t)id;
}

/*
 * call-seq:
 *    OpenSSL::HPKE::Suite.new(kem, kdf, aead) -> suite
 *
 * +kem+, +kdf+, and +aead+ are either all algorithm name strings (resolved via
 * OSSL_HPKE_str2suite) or all Integer IANA algorithm IDs (as carried on the
 * wire by e.g. ECH). The suite is validated against the algorithms the linked
 * OpenSSL supports before it can be used.
 */
static VALUE
ossl_hpke_suite_initialize(VALUE self, VALUE kem, VALUE kdf, VALUE aead)
{
    OSSL_HPKE_SUITE *suite, tmp;

    ossl_want_uninitialized(self, &ossl_hpke_suite_type);

    if (RB_INTEGER_TYPE_P(kem) && RB_INTEGER_TYPE_P(kdf) &&
        RB_INTEGER_TYPE_P(aead)) {
        tmp.kem_id  = ossl_hpke_suite_id(kem,  "KEM");
        tmp.kdf_id  = ossl_hpke_suite_id(kdf,  "KDF");
        tmp.aead_id = ossl_hpke_suite_id(aead, "AEAD");

        if (OSSL_HPKE_suite_check(tmp) != 1) {
            ossl_raise(eHPKEError, "unsupported HPKE suite: "
                       "kem=0x%04x kdf=0x%04x aead=0x%04x",
                       tmp.kem_id, tmp.kdf_id, tmp.aead_id);
        }
    }
    else {
        VALUE str = rb_sprintf("%"PRIsVALUE",%"PRIsVALUE",%"PRIsVALUE,
                               kem, kdf, aead);

        if (OSSL_HPKE_str2suite(StringValueCStr(str), &tmp) != 1)
            ossl_raise(eHPKEError, "unsupported HPKE suite: %"PRIsVALUE, str);
    }

    suite = ALLOC(OSSL_HPKE_SUITE);
    *suite = tmp;
    RTYPEDDATA_DATA(self) = suite;

    /*
     * A Suite is immutable: its algorithm IDs never change, and they are
     * copied into the Context at construction rather than read back later.
     * Freeze it so the immutability is enforced and visible to callers.
     */
    return rb_obj_freeze(self);
}

/*
 * call-seq:
 *    kem_id -> integer
 *
 * Returns the IANA KEM (Key Encapsulation Mechanism) algorithm ID of the
 * suite as an Integer.
 */
static VALUE
ossl_hpke_suite_kem_id(VALUE self)
{
    OSSL_HPKE_SUITE *suite;
    GetHpkeSuite(self, suite);
    return INT2NUM(suite->kem_id);
}

/*
 * call-seq:
 *    kdf_id -> integer
 *
 * Returns the IANA KDF (Key Derivation Function) algorithm ID of the suite
 * as an Integer.
 */
static VALUE
ossl_hpke_suite_kdf_id(VALUE self)
{
    OSSL_HPKE_SUITE *suite;
    GetHpkeSuite(self, suite);
    return INT2NUM(suite->kdf_id);
}

/*
 * call-seq:
 *    aead_id -> integer
 *
 * Returns the IANA AEAD algorithm ID of the suite as an Integer.
 */
static VALUE
ossl_hpke_suite_aead_id(VALUE self)
{
    OSSL_HPKE_SUITE *suite;
    GetHpkeSuite(self, suite);
    return INT2NUM(suite->aead_id);
}

/* private */
static VALUE
ossl_hpke_ctx_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &ossl_hpke_ctx_type, NULL);
}

static VALUE
ossl_hpke_suite_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &ossl_hpke_suite_type, NULL);
}

/* HPKE module method */
/*
 * call-seq:
 *    keygen(suite) -> pkey
 *
 * Takes a OpenSSL::HPKE::Suite and returns a public-private key pair
 * in the form of OpenSSL::PKey for the corresponding cipher suite.
 */
static VALUE
ossl_hpke_keygen(VALUE self, VALUE suite)
{
    EVP_PKEY *pkey;
    VALUE pkey_obj;
    OSSL_HPKE_SUITE *suite_st;
    /* as per RFC9180 section 7.1, the maximum size of Npk possible is 133 */
    unsigned char pub[133];
    size_t publen;

    if (!rb_obj_is_kind_of(suite, cSuite))
        ossl_raise(eHPKEError, "invalid suite specified");
    GetHpkeSuite(suite, suite_st);

    /* set to the maximum length first; OSSL_HPKE_keygen() shrinks it down */
    publen = 133;

    if(!OSSL_HPKE_keygen(*suite_st, pub, &publen, &pkey, NULL, 0, NULL, NULL)){
        ossl_raise(eHPKEError, "could not keygen");
    }

    pkey_obj = ossl_pkey_wrap(pkey);

    return pkey_obj;
}

void
Init_ossl_hpke(void)
{
    mHPKE            = rb_define_module_under(mOSSL, "HPKE");
    cSuite           = rb_define_class_under(mHPKE, "Suite", rb_cObject);
    cContext         = rb_define_class_under(mHPKE, "Context", rb_cObject);
    cSenderContext   = rb_define_class_under(cContext, "Sender", cContext);
    cReceiverContext = rb_define_class_under(cContext, "Receiver", cContext);
    eHPKEError = rb_define_class_under(mHPKE, "HPKEError", eOSSLError);

    rb_define_module_function(mHPKE, "keygen", ossl_hpke_keygen, 1);

    /* suite accessors for Suite (read from the wrapped OSSL_HPKE_SUITE) */
    rb_define_alloc_func(cSuite, ossl_hpke_suite_alloc);
    rb_define_method(cSuite, "initialize", ossl_hpke_suite_initialize, 3);
    rb_define_method(cSuite, "kem_id",  ossl_hpke_suite_kem_id,  0);
    rb_define_method(cSuite, "kdf_id",  ossl_hpke_suite_kdf_id,  0);
    rb_define_method(cSuite, "aead_id", ossl_hpke_suite_aead_id, 0);

    rb_define_method(cSenderContext, "initialize", ossl_hpke_ctx_new_sender, 1);
    rb_define_method(cSenderContext, "encap", ossl_hpke_encap, 2);
    rb_define_method(cSenderContext, "seal",  ossl_hpke_seal,  2);

    rb_define_method(cReceiverContext, "initialize",
                     ossl_hpke_ctx_new_receiver, 1);
    rb_define_method(cReceiverContext, "decap", ossl_hpke_decap, 3);
    rb_define_method(cReceiverContext, "open",  ossl_hpke_open,  2);

    rb_define_method(cContext, "export", ossl_hpke_export, 2);

    rb_define_alloc_func(cContext, ossl_hpke_ctx_alloc);
}

#else /* !defined(HAVE_OSSL_HPKE_CTX_NEW) */

void
Init_ossl_hpke(void)
{
}

#endif
