/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002 Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#include "ossl.h"

#define GetX509CRL(obj, crl) do { \
    TypedData_Get_Struct((obj), X509_CRL, &ossl_x509crl_type, (crl)); \
    if (!(crl)) { \
        ossl_raise(rb_eRuntimeError, "CRL wasn't initialized!"); \
    } \
} while (0)

/*
 * Classes
 */
static VALUE cX509CRL;
static VALUE eX509CRLError;

static void
ossl_x509crl_free(void *ptr)
{
    X509_CRL_free(ptr);
}

static const rb_data_type_t ossl_x509crl_type = {
    "OpenSSL/X509/CRL",
    {
        0, ossl_x509crl_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

static VALUE
ossl_x509crl_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &ossl_x509crl_type, NULL);
}

/*
 * PUBLIC
 */
X509_CRL *
GetX509CRLPtr(VALUE obj)
{
    X509_CRL *crl;

    GetX509CRL(obj, crl);

    return crl;
}

VALUE
ossl_x509crl_new(const X509_CRL *crl)
{
    X509_CRL *tmp;
    VALUE obj;

    obj = ossl_x509crl_alloc(cX509CRL);
    /* OpenSSL 1.1.1 takes a non-const pointer */
    tmp = X509_CRL_dup((X509_CRL *)crl);
    if (!tmp)
        ossl_raise(eX509CRLError, "X509_CRL_dup");
    RTYPEDDATA_DATA(obj) = tmp;

    return obj;
}

static VALUE
ossl_x509crl_initialize(int argc, VALUE *argv, VALUE self)
{
    BIO *in;
    X509_CRL *crl;
    VALUE arg;

    rb_scan_args(argc, argv, "01", &arg);
    ossl_want_uninitialized(self, &ossl_x509crl_type);
    if (argc == 0) {
        crl = X509_CRL_new();
        if (!crl)
            ossl_raise(eX509CRLError, "X509_CRL_new");
        RTYPEDDATA_DATA(self) = crl;
        return self;
    }
    arg = ossl_to_der_if_possible(arg);
    in = ossl_obj2bio(&arg);
    crl = d2i_X509_CRL_bio(in, NULL);
    if (!crl) {
        OSSL_BIO_reset(in);
        crl = PEM_read_bio_X509_CRL(in, NULL, NULL, NULL);
    }
    BIO_free(in);
    if (!crl)
        ossl_raise(eX509CRLError, "PEM_read_bio_X509_CRL");
    RTYPEDDATA_DATA(self) = crl;

    return self;
}

/* :nodoc: */
static VALUE
ossl_x509crl_copy(VALUE self, VALUE other)
{
    X509_CRL *b, *crl;

    ossl_want_uninitialized(self, &ossl_x509crl_type);
    GetX509CRL(other, b);
    if (!(crl = X509_CRL_dup(b))) {
        ossl_raise(eX509CRLError, NULL);
    }
    RTYPEDDATA_DATA(self) = crl;

    return self;
}

static VALUE
ossl_x509crl_get_version(VALUE self)
{
    X509_CRL *crl;
    long ver;

    GetX509CRL(self, crl);
    ver = X509_CRL_get_version(crl);

    return LONG2NUM(ver);
}

static VALUE
ossl_x509crl_set_version(VALUE self, VALUE version)
{
    X509_CRL *crl;
    long ver;

    if ((ver = NUM2LONG(version)) < 0) {
        ossl_raise(eX509CRLError, "version must be >= 0!");
    }
    GetX509CRL(self, crl);
    if (!X509_CRL_set_version(crl, ver)) {
        ossl_raise(eX509CRLError, NULL);
    }

    return version;
}

/*
 * call-seq:
 *    crl.signature_algorithm -> string
 *
 * Returns the signature algorithm used to sign this CRL.
 *
 * Returns the long name of the signature algorithm, or the dotted decimal
 * notation if \OpenSSL does not define a long name for it.
 */
static VALUE
ossl_x509crl_get_signature_algorithm(VALUE self)
{
    X509_CRL *crl;
    const X509_ALGOR *alg;
    const ASN1_OBJECT *obj;

    GetX509CRL(self, crl);
    X509_CRL_get0_signature(crl, NULL, &alg);
    X509_ALGOR_get0(&obj, NULL, NULL, alg);
    return ossl_asn1obj_to_string_long_name(obj);
}

static VALUE
ossl_x509crl_get_issuer(VALUE self)
{
    X509_CRL *crl;

    GetX509CRL(self, crl);

    return ossl_x509name_new(X509_CRL_get_issuer(crl)); /* NO DUP - don't free */
}

static VALUE
ossl_x509crl_set_issuer(VALUE self, VALUE issuer)
{
    X509_CRL *crl;

    GetX509CRL(self, crl);

    if (!X509_CRL_set_issuer_name(crl, GetX509NamePtr(issuer))) { /* DUPs name */
        ossl_raise(eX509CRLError, NULL);
    }
    return issuer;
}

static VALUE
ossl_x509crl_get_last_update(VALUE self)
{
    X509_CRL *crl;
    const ASN1_TIME *time;

    GetX509CRL(self, crl);
    time = X509_CRL_get0_lastUpdate(crl);
    if (!time)
        return Qnil;

    return asn1time_to_time(time);
}

static VALUE
ossl_x509crl_set_last_update(VALUE self, VALUE time)
{
    X509_CRL *crl;
    ASN1_TIME *asn1time;

    GetX509CRL(self, crl);
    asn1time = ossl_x509_time_adjust(NULL, time);
    if (!X509_CRL_set1_lastUpdate(crl, asn1time)) {
        ASN1_TIME_free(asn1time);
        ossl_raise(eX509CRLError, "X509_CRL_set_lastUpdate");
    }
    ASN1_TIME_free(asn1time);

    return time;
}

static VALUE
ossl_x509crl_get_next_update(VALUE self)
{
    X509_CRL *crl;
    const ASN1_TIME *time;

    GetX509CRL(self, crl);
    time = X509_CRL_get0_nextUpdate(crl);
    if (!time)
        return Qnil;

    return asn1time_to_time(time);
}

static VALUE
ossl_x509crl_set_next_update(VALUE self, VALUE time)
{
    X509_CRL *crl;
    ASN1_TIME *asn1time;

    GetX509CRL(self, crl);
    asn1time = ossl_x509_time_adjust(NULL, time);
    if (!X509_CRL_set1_nextUpdate(crl, asn1time)) {
        ASN1_TIME_free(asn1time);
        ossl_raise(eX509CRLError, "X509_CRL_set_nextUpdate");
    }
    ASN1_TIME_free(asn1time);

    return time;
}

static VALUE
ossl_x509crl_get_revoked(VALUE self)
{
    X509_CRL *crl;
    int i, num;
    STACK_OF(X509_REVOKED) *sk;
    VALUE ary;

    GetX509CRL(self, crl);
    sk = X509_CRL_get_REVOKED(crl);
    if (!sk)
        return rb_ary_new();

    num = sk_X509_REVOKED_num(sk);
    ary = rb_ary_new_capa(num);
    for(i=0; i<num; i++) {
        const X509_REVOKED *rev = sk_X509_REVOKED_value(sk, i);
        rb_ary_push(ary, ossl_x509revoked_new(rev));
    }

    return ary;
}

static VALUE
ossl_x509crl_set_revoked(VALUE self, VALUE ary)
{
    X509_CRL *crl;
    X509_REVOKED *rev;
    STACK_OF(X509_REVOKED) *sk;
    long i;

    Check_Type(ary, T_ARRAY);
    /* All ary members should be X509 Revoked */
    for (i=0; i<RARRAY_LEN(ary); i++) {
        OSSL_Check_Kind(RARRAY_AREF(ary, i), cX509Rev);
    }
    GetX509CRL(self, crl);
    if ((sk = X509_CRL_get_REVOKED(crl))) {
        while ((rev = sk_X509_REVOKED_pop(sk)))
            X509_REVOKED_free(rev);
    }
    for (i=0; i<RARRAY_LEN(ary); i++) {
        rev = DupX509RevokedPtr(RARRAY_AREF(ary, i));
        if (!X509_CRL_add0_revoked(crl, rev)) { /* NO DUP - don't free! */
            X509_REVOKED_free(rev);
            ossl_raise(eX509CRLError, "X509_CRL_add0_revoked");
        }
    }
    X509_CRL_sort(crl);

    return ary;
}

/*
 * call-seq:
 *    crl.by_serial(serial) -> OpenSSL::X509::Revoked or nil
 *
 * Looks up the certificate _serial_ (an Integer or OpenSSL::BN) in the CRL and
 * returns the matching OpenSSL::X509::Revoked entry, or +nil+ if that serial is
 * not listed.
 *
 * Unlike iterating over #revoked, this does not instantiate the entire
 * revocation list: it performs a sorted lookup (wrapping the OpenSSL function
 * +X509_CRL_get0_by_serial+), which is significantly faster and uses far less
 * memory for large CRLs.
 *
 *    crl.by_serial(cert.serial)        #=> #<OpenSSL::X509::Revoked> or nil
 *    crl.by_serial(cert.serial)&.time  #=> revocation time, if revoked
 */
static VALUE
ossl_x509crl_by_serial(VALUE self, VALUE serial)
{
    X509_CRL *crl;
    X509_REVOKED *rev = NULL;
    ASN1_INTEGER *asn1_serial;
    int found;

    GetX509CRL(self, crl);
    asn1_serial = num_to_asn1integer(serial, NULL);

    /* 0 = not found, 1 = found, 2 = found with reason removeFromCRL */
    found = X509_CRL_get0_by_serial(crl, &rev, asn1_serial);
    ASN1_INTEGER_free(asn1_serial);

    if (found == 0)
        return Qnil;

    /* ossl_x509revoked_new dups, so the result outlives the CRL safely */
    return ossl_x509revoked_new(rev);
}

static VALUE
ossl_x509crl_add_revoked(VALUE self, VALUE revoked)
{
    X509_CRL *crl;
    X509_REVOKED *rev;

    GetX509CRL(self, crl);
    rev = DupX509RevokedPtr(revoked);
    if (!X509_CRL_add0_revoked(crl, rev)) { /* NO DUP - don't free! */
        X509_REVOKED_free(rev);
        ossl_raise(eX509CRLError, "X509_CRL_add0_revoked");
    }
    X509_CRL_sort(crl);

    return revoked;
}

static VALUE
ossl_x509crl_sign(VALUE self, VALUE key, VALUE digest)
{
    X509_CRL *crl;
    EVP_PKEY *pkey;
    const EVP_MD *md;
    VALUE md_holder;

    GetX509CRL(self, crl);
    pkey = GetPrivPKeyPtr(key); /* NO NEED TO DUP */
    /* NULL needed for some key types, e.g. Ed25519 */
    md = NIL_P(digest) ? NULL : ossl_evp_md_fetch(digest, &md_holder);
    if (!X509_CRL_sign(crl, pkey, md))
        ossl_raise(eX509CRLError, "X509_CRL_sign");

    return self;
}

static VALUE
ossl_x509crl_verify(VALUE self, VALUE key)
{
    X509_CRL *crl;
    EVP_PKEY *pkey;

    GetX509CRL(self, crl);
    pkey = GetPKeyPtr(key);
    ossl_pkey_check_public_key(pkey);
    switch (X509_CRL_verify(crl, pkey)) {
      case 1:
        return Qtrue;
      case 0:
        ossl_clear_error();
        return Qfalse;
      default:
        ossl_raise(eX509CRLError, NULL);
    }
}

static VALUE
ossl_x509crl_to_der(VALUE self)
{
    X509_CRL *crl;
    BIO *out;

    GetX509CRL(self, crl);
    if (!(out = BIO_new(BIO_s_mem()))) {
        ossl_raise(eX509CRLError, NULL);
    }
    if (!i2d_X509_CRL_bio(out, crl)) {
        BIO_free(out);
        ossl_raise(eX509CRLError, NULL);
    }

    return ossl_membio2str(out);
}

static VALUE
ossl_x509crl_to_pem(VALUE self)
{
    X509_CRL *crl;
    BIO *out;

    GetX509CRL(self, crl);
    if (!(out = BIO_new(BIO_s_mem()))) {
        ossl_raise(eX509CRLError, NULL);
    }
    if (!PEM_write_bio_X509_CRL(out, crl)) {
        BIO_free(out);
        ossl_raise(eX509CRLError, NULL);
    }

    return ossl_membio2str(out);
}

static VALUE
ossl_x509crl_to_text(VALUE self)
{
    X509_CRL *crl;
    BIO *out;

    GetX509CRL(self, crl);
    if (!(out = BIO_new(BIO_s_mem()))) {
        ossl_raise(eX509CRLError, NULL);
    }
    if (!X509_CRL_print(out, crl)) {
        BIO_free(out);
        ossl_raise(eX509CRLError, NULL);
    }

    return ossl_membio2str(out);
}

/*
 * Gets X509v3 extensions as array of X509Ext objects
 */
static VALUE
ossl_x509crl_get_extensions(VALUE self)
{
    X509_CRL *crl;
    int count, i;
    VALUE ary;

    GetX509CRL(self, crl);
    count = X509_CRL_get_ext_count(crl);
    ary = rb_ary_new_capa(count);
    for (i=0; i<count; i++) {
        const X509_EXTENSION *ext = X509_CRL_get_ext(crl, i);
        rb_ary_push(ary, ossl_x509ext_new(ext));
    }

    return ary;
}

/*
 * Sets X509_EXTENSIONs
 */
static VALUE
ossl_x509crl_set_extensions(VALUE self, VALUE ary)
{
    X509_CRL *crl;
    X509_EXTENSION *ext;
    long i;

    Check_Type(ary, T_ARRAY);
    /* All ary members should be X509 Extensions */
    for (i=0; i<RARRAY_LEN(ary); i++) {
        OSSL_Check_Kind(RARRAY_AREF(ary, i), cX509Ext);
    }
    GetX509CRL(self, crl);
    for (i = X509_CRL_get_ext_count(crl); i > 0; i--)
        X509_EXTENSION_free(X509_CRL_delete_ext(crl, 0));
    for (i=0; i<RARRAY_LEN(ary); i++) {
        ext = GetX509ExtPtr(RARRAY_AREF(ary, i)); /* NO NEED TO DUP */
        if (!X509_CRL_add_ext(crl, ext, -1)) {
            ossl_raise(eX509CRLError, "X509_CRL_add_ext");
        }
    }

    return ary;
}

static VALUE
ossl_x509crl_add_extension(VALUE self, VALUE extension)
{
    X509_CRL *crl;
    X509_EXTENSION *ext;

    GetX509CRL(self, crl);
    ext = GetX509ExtPtr(extension);
    if (!X509_CRL_add_ext(crl, ext, -1)) {
        ossl_raise(eX509CRLError, NULL);
    }

    return extension;
}

/*
 * INIT
 */
void
Init_ossl_x509crl(void)
{
    eX509CRLError = rb_define_class_under(mX509, "CRLError", eOSSLError);

    cX509CRL = rb_define_class_under(mX509, "CRL", rb_cObject);

    rb_define_alloc_func(cX509CRL, ossl_x509crl_alloc);
    rb_define_method(cX509CRL, "initialize", ossl_x509crl_initialize, -1);
    rb_define_method(cX509CRL, "initialize_copy", ossl_x509crl_copy, 1);

    rb_define_method(cX509CRL, "version", ossl_x509crl_get_version, 0);
    rb_define_method(cX509CRL, "version=", ossl_x509crl_set_version, 1);
    rb_define_method(cX509CRL, "signature_algorithm", ossl_x509crl_get_signature_algorithm, 0);
    rb_define_method(cX509CRL, "issuer", ossl_x509crl_get_issuer, 0);
    rb_define_method(cX509CRL, "issuer=", ossl_x509crl_set_issuer, 1);
    rb_define_method(cX509CRL, "last_update", ossl_x509crl_get_last_update, 0);
    rb_define_method(cX509CRL, "last_update=", ossl_x509crl_set_last_update, 1);
    rb_define_method(cX509CRL, "next_update", ossl_x509crl_get_next_update, 0);
    rb_define_method(cX509CRL, "next_update=", ossl_x509crl_set_next_update, 1);
    rb_define_method(cX509CRL, "revoked", ossl_x509crl_get_revoked, 0);
    rb_define_method(cX509CRL, "revoked=", ossl_x509crl_set_revoked, 1);
    rb_define_method(cX509CRL, "by_serial", ossl_x509crl_by_serial, 1);
    rb_define_method(cX509CRL, "add_revoked", ossl_x509crl_add_revoked, 1);
    rb_define_method(cX509CRL, "sign", ossl_x509crl_sign, 2);
    rb_define_method(cX509CRL, "verify", ossl_x509crl_verify, 1);
    rb_define_method(cX509CRL, "to_der", ossl_x509crl_to_der, 0);
    rb_define_method(cX509CRL, "to_pem", ossl_x509crl_to_pem, 0);
    rb_define_alias(cX509CRL, "to_s", "to_pem");
    rb_define_method(cX509CRL, "to_text", ossl_x509crl_to_text, 0);
    rb_define_method(cX509CRL, "extensions", ossl_x509crl_get_extensions, 0);
    rb_define_method(cX509CRL, "extensions=", ossl_x509crl_set_extensions, 1);
    rb_define_method(cX509CRL, "add_extension", ossl_x509crl_add_extension, 1);
}
