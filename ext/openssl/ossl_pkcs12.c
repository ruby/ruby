/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 * $Id: ossl_pkcs12.c,v 1.2 2003/12/15 00:30:12 usa Exp $
 */
#include "ossl.h"

#define WrapPKCS12(klass, obj, p12) do { \
    if(!p12) ossl_raise(rb_eRuntimeError, "PKCS12 wasn't initialized."); \
    obj = Data_Wrap_Struct(klass, 0, PKCS12_free, p12); \
} while (0)

#define GetPKCS12(obj, p12) do { \
    Data_Get_Struct(obj, PKCS12, p12); \
    if(!p12) ossl_raise(rb_eRuntimeError, "PKCS12 wasn't initialized."); \
} while (0)

#define SafeGetPKCS12(obj, p12) do { \
    OSSL_Check_Kind(obj, cPKCS12); \
    GetPKCS12(obj, p12); \
} while (0)

#define ossl_pkcs12_set_key(o,v)      rb_iv_set((o), "@key", (v))
#define ossl_pkcs12_set_cert(o,v)     rb_iv_set((o), "@certificate", (v))
#define ossl_pkcs12_set_ca_certs(o,v) rb_iv_set((o), "@ca_certs", (v))
#define ossl_pkcs12_get_key(o)        rb_iv_get((o), "@key")
#define ossl_pkcs12_get_cert(o)       rb_iv_get((o), "@certificate")
#define ossl_pkcs12_get_ca_certs(o)   rb_iv_get((o), "@ca_certs")

/*
 * Classes
 */
VALUE mPKCS12;
VALUE cPKCS12;
VALUE ePKCS12Error;

/*
 * Private
 */
static VALUE
ossl_pkcs12_s_allocate(VALUE klass)
{
    PKCS12 *p12;
    VALUE obj;

    if(!(p12 = PKCS12_new())) ossl_raise(ePKCS12Error, NULL);
    WrapPKCS12(klass, obj, p12);

    return obj;
}

static VALUE
ossl_pkcs12_s_create(int argc, VALUE *argv, VALUE self)
{
    VALUE pass, name, pkey, cert, ca;
    VALUE obj;
    char *passphrase, *friendlyname;
    EVP_PKEY *key;
    X509 *x509;
    STACK_OF(X509) *x509s;
    PKCS12 *p12;
    
    rb_scan_args(argc, argv, "41", &pass, &name, &pkey, &cert, &ca);
    passphrase = NIL_P(pass) ? NULL : StringValuePtr(pass);
    friendlyname = NIL_P(name) ? NULL : StringValuePtr(name);
    key = GetPKeyPtr(pkey);
    x509 = GetX509CertPtr(cert);
    x509s = NIL_P(ca) ? NULL : ossl_x509_ary2sk(ca);
    p12 = PKCS12_create(passphrase, friendlyname, key, x509, x509s,
                        0, 0, 0, 0, 0);
    sk_X509_pop_free(x509s, X509_free);
    if(!p12) ossl_raise(ePKCS12Error, NULL);
    WrapPKCS12(cPKCS12, obj, p12);

    return obj;
}

static VALUE
ossl_pkcs12_initialize(int argc, VALUE *argv, VALUE self)
{
    BIO *in;
    VALUE arg, pass, pkey, cert, ca;
    char *passphrase;
    EVP_PKEY *key;
    X509 *x509;
    STACK_OF(X509) *x509s = NULL;
    int st = 0;

    if(rb_scan_args(argc, argv, "02", &arg, &pass) == 0) return self;
    passphrase = NIL_P(pass) ? NULL : StringValuePtr(pass);
    in = ossl_obj2bio(arg);
    d2i_PKCS12_bio(in, (PKCS12 **)&DATA_PTR(self));
    BIO_free(in);

    pkey = cert = ca = Qnil;
    if(!PKCS12_parse((PKCS12*)DATA_PTR(self), passphrase, &key, &x509, &x509s))
	ossl_raise(ePKCS12Error, NULL);
    pkey = rb_protect((VALUE(*)_((VALUE)))ossl_pkey_new, (VALUE)key,
		      &st); /* NO DUP */
    if(st) goto err;
    cert = rb_protect((VALUE(*)_((VALUE)))ossl_x509_new, (VALUE)x509, &st);
    if(st) goto err;
    if(x509s){
	ca =
	    rb_protect((VALUE(*)_((VALUE)))ossl_x509_sk2ary, (VALUE)x509s, &st);
	if(st) goto err;
    }

  err:
    X509_free(x509);
    sk_X509_pop_free(x509s, X509_free);
    ossl_pkcs12_set_key(self, pkey);
    ossl_pkcs12_set_cert(self, cert);
    ossl_pkcs12_set_ca_certs(self, ca);
    if(st) rb_jump_tag(st);

    return self;
}

static VALUE
ossl_pkcs12_to_der(VALUE self)
{
    PKCS12 *p12;
    VALUE str;
    long len;
    unsigned char *p;

    GetPKCS12(self, p12);
    if((len = i2d_PKCS12(p12, NULL)) <= 0)
	ossl_raise(ePKCS12Error, NULL);
    str = rb_str_new(0, len);
    p = RSTRING(str)->ptr;
    if(i2d_PKCS12(p12, &p) <= 0)
	ossl_raise(ePKCS12Error, NULL);
    ossl_str_adjust(str, p);

    return str;
}

void
Init_ossl_pkcs12()
{
    mPKCS12 = rb_define_module_under(mOSSL, "PKCS12");
    cPKCS12 = rb_define_class_under(mPKCS12, "PKCS12", rb_cObject);
    ePKCS12Error = rb_define_class_under(mPKCS12, "PKCS12Error", eOSSLError);
    rb_define_module_function(mPKCS12, "create", ossl_pkcs12_s_create, -1);

    rb_define_alloc_func(cPKCS12, ossl_pkcs12_s_allocate);
    rb_attr(cPKCS12, rb_intern("key"), 1, 0, Qfalse);
    rb_attr(cPKCS12, rb_intern("certificate"), 1, 0, Qfalse);
    rb_attr(cPKCS12, rb_intern("ca_certs"), 1, 0, Qfalse);
    rb_define_method(cPKCS12, "initialize", ossl_pkcs12_initialize, -1);
    rb_define_method(cPKCS12, "to_der", ossl_pkcs12_to_der, 0);
}
