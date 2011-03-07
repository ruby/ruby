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
#include "ossl.h"

#define WrapSPKI(klass, obj, spki) do { \
    if (!(spki)) { \
	ossl_raise(rb_eRuntimeError, "SPKI wasn't initialized!"); \
    } \
    (obj) = Data_Wrap_Struct((klass), 0, NETSCAPE_SPKI_free, (spki)); \
} while (0)
#define GetSPKI(obj, spki) do { \
    Data_Get_Struct((obj), NETSCAPE_SPKI, (spki)); \
    if (!(spki)) { \
	ossl_raise(rb_eRuntimeError, "SPKI wasn't initialized!"); \
    } \
} while (0)

/*
 * Classes
 */
VALUE mNetscape;
VALUE cSPKI;
VALUE eSPKIError;

/*
 * Public functions
 */

/*
 * Private functions
 */
static VALUE
ossl_spki_alloc(VALUE klass)
{
    NETSCAPE_SPKI *spki;
    VALUE obj;

    if (!(spki = NETSCAPE_SPKI_new())) {
	ossl_raise(eSPKIError, NULL);
    }
    WrapSPKI(klass, obj, spki);

    return obj;
}

static VALUE
ossl_spki_initialize(int argc, VALUE *argv, VALUE self)
{
    NETSCAPE_SPKI *spki;
    VALUE buffer;
    const unsigned char *p;

    if (rb_scan_args(argc, argv, "01", &buffer) == 0) {
	return self;
    }
    StringValue(buffer);
    if (!(spki = NETSCAPE_SPKI_b64_decode(RSTRING_PTR(buffer), -1))) {
	p = (unsigned char *)RSTRING_PTR(buffer);
	if (!(spki = d2i_NETSCAPE_SPKI(NULL, &p, RSTRING_LEN(buffer)))) {
	    ossl_raise(eSPKIError, NULL);
	}
    }
    NETSCAPE_SPKI_free(DATA_PTR(self));
    DATA_PTR(self) = spki;
    ERR_clear_error();

    return self;
}

static VALUE
ossl_spki_to_der(VALUE self)
{
    NETSCAPE_SPKI *spki;
    VALUE str;
    long len;
    unsigned char *p;

    GetSPKI(self, spki);
    if ((len = i2d_NETSCAPE_SPKI(spki, NULL)) <= 0)
        ossl_raise(eX509CertError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if (i2d_NETSCAPE_SPKI(spki, &p) <= 0)
        ossl_raise(eX509CertError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

static VALUE
ossl_spki_to_pem(VALUE self)
{
    NETSCAPE_SPKI *spki;
    char *data;
    VALUE str;

    GetSPKI(self, spki);
    if (!(data = NETSCAPE_SPKI_b64_encode(spki))) {
	ossl_raise(eSPKIError, NULL);
    }
    str = ossl_buf2str(data, strlen(data));

    return str;
}

static VALUE
ossl_spki_print(VALUE self)
{
    NETSCAPE_SPKI *spki;
    BIO *out;
    BUF_MEM *buf;
    VALUE str;

    GetSPKI(self, spki);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eSPKIError, NULL);
    }
    if (!NETSCAPE_SPKI_print(out, spki)) {
	BIO_free(out);
	ossl_raise(eSPKIError, NULL);
    }
    BIO_get_mem_ptr(out, &buf);
    str = rb_str_new(buf->data, buf->length);
    BIO_free(out);

    return str;
}

static VALUE
ossl_spki_get_public_key(VALUE self)
{
    NETSCAPE_SPKI *spki;
    EVP_PKEY *pkey;

    GetSPKI(self, spki);
    if (!(pkey = NETSCAPE_SPKI_get_pubkey(spki))) { /* adds an reference */
	ossl_raise(eSPKIError, NULL);
    }

    return ossl_pkey_new(pkey); /* NO DUP - OK */
}

static VALUE
ossl_spki_set_public_key(VALUE self, VALUE key)
{
    NETSCAPE_SPKI *spki;

    GetSPKI(self, spki);
    if (!NETSCAPE_SPKI_set_pubkey(spki, GetPKeyPtr(key))) { /* NO NEED TO DUP */
	ossl_raise(eSPKIError, NULL);
    }

    return key;
}

static VALUE
ossl_spki_get_challenge(VALUE self)
{
    NETSCAPE_SPKI *spki;

    GetSPKI(self, spki);
    if (spki->spkac->challenge->length <= 0) {
	OSSL_Debug("Challenge.length <= 0?");
	return rb_str_new(0, 0);
    }

    return rb_str_new((const char *)spki->spkac->challenge->data,
		      spki->spkac->challenge->length);
}

static VALUE
ossl_spki_set_challenge(VALUE self, VALUE str)
{
    NETSCAPE_SPKI *spki;

    StringValue(str);
    GetSPKI(self, spki);
    if (!ASN1_STRING_set(spki->spkac->challenge, RSTRING_PTR(str),
			 RSTRING_LEN(str))) {
	ossl_raise(eSPKIError, NULL);
    }

    return str;
}

static VALUE
ossl_spki_sign(VALUE self, VALUE key, VALUE digest)
{
    NETSCAPE_SPKI *spki;
    EVP_PKEY *pkey;
    const EVP_MD *md;

    pkey = GetPrivPKeyPtr(key); /* NO NEED TO DUP */
    md = GetDigestPtr(digest);
    GetSPKI(self, spki);
    if (!NETSCAPE_SPKI_sign(spki, pkey, md)) {
	ossl_raise(eSPKIError, NULL);
    }

    return self;
}

/*
 * Checks that cert signature is made with PRIVversion of this PUBLIC 'key'
 */
static VALUE
ossl_spki_verify(VALUE self, VALUE key)
{
    NETSCAPE_SPKI *spki;

    GetSPKI(self, spki);
    switch (NETSCAPE_SPKI_verify(spki, GetPKeyPtr(key))) { /* NO NEED TO DUP */
    case 0:
	return Qfalse;
    case 1:
	return Qtrue;
    default:
	ossl_raise(eSPKIError, NULL);
    }
    return Qnil; /* dummy */
}

/*
 * NETSCAPE_SPKI init
 */
void
Init_ossl_ns_spki()
{
    mNetscape = rb_define_module_under(mOSSL, "Netscape");

    eSPKIError = rb_define_class_under(mNetscape, "SPKIError", eOSSLError);

    cSPKI = rb_define_class_under(mNetscape, "SPKI", rb_cObject);

    rb_define_alloc_func(cSPKI, ossl_spki_alloc);
    rb_define_method(cSPKI, "initialize", ossl_spki_initialize, -1);

    rb_define_method(cSPKI, "to_der", ossl_spki_to_der, 0);
    rb_define_method(cSPKI, "to_pem", ossl_spki_to_pem, 0);
    rb_define_alias(cSPKI, "to_s", "to_pem");
    rb_define_method(cSPKI, "to_text", ossl_spki_print, 0);
    rb_define_method(cSPKI, "public_key", ossl_spki_get_public_key, 0);
    rb_define_method(cSPKI, "public_key=", ossl_spki_set_public_key, 1);
    rb_define_method(cSPKI, "sign", ossl_spki_sign, 2);
    rb_define_method(cSPKI, "verify", ossl_spki_verify, 1);
    rb_define_method(cSPKI, "challenge", ossl_spki_get_challenge, 0);
    rb_define_method(cSPKI, "challenge=", ossl_spki_set_challenge, 1);
}

