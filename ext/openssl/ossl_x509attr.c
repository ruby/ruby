/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001 Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#define WrapX509Attr(klass, obj, attr) do { \
    if (!attr) { \
	ossl_raise(rb_eRuntimeError, "ATTR wasn't initialized!"); \
    } \
    obj = Data_Wrap_Struct(klass, 0, X509_ATTRIBUTE_free, attr); \
} while (0)
#define GetX509Attr(obj, attr) do { \
    Data_Get_Struct(obj, X509_ATTRIBUTE, attr); \
    if (!attr) { \
	ossl_raise(rb_eRuntimeError, "ATTR wasn't initialized!"); \
    } \
} while (0)
#define SafeGetX509Attr(obj, attr) do { \
    OSSL_Check_Kind(obj, cX509Attr); \
    GetX509Attr(obj, attr); \
} while (0)

/*
 * Classes
 */
VALUE cX509Attr;
VALUE eX509AttrError;

/*
 * Public
 */
VALUE
ossl_x509attr_new(X509_ATTRIBUTE *attr)
{
    X509_ATTRIBUTE *new;
    VALUE obj;
    
    if (!attr) {
	new = X509_ATTRIBUTE_new();
    } else {
	new = X509_ATTRIBUTE_dup(attr);
    }
    if (!new) {
	ossl_raise(eX509AttrError, NULL);
    }
    WrapX509Attr(cX509Attr, obj, new);

    return obj;
}

X509_ATTRIBUTE *
DupX509AttrPtr(VALUE obj)
{
    X509_ATTRIBUTE *attr, *new;

    SafeGetX509Attr(obj, attr);
    if (!(new = X509_ATTRIBUTE_dup(attr))) {
	ossl_raise(eX509AttrError, NULL);
    }

    return new;
}

/*
 * Private
 */
static VALUE 
ossl_x509attr_s_new_from_array(VALUE klass, VALUE ary)
{
    X509_ATTRIBUTE *attr;
    int nid = NID_undef;
    VALUE item, obj;

    Check_Type(ary, T_ARRAY);
    if (RARRAY(ary)->len != 2) {
	ossl_raise(eX509AttrError, "unsupported ary structure");
    }
    /* key [0] */
    item = RARRAY(ary)->ptr[0];
    StringValue(item);
    if (!(nid = OBJ_ln2nid(RSTRING(item)->ptr))) {
	if (!(nid = OBJ_sn2nid(RSTRING(item)->ptr))) {
	    ossl_raise(eX509AttrError, NULL);
	}
    }
    /* data [1] */
    item = RARRAY(ary)->ptr[1];
    StringValuePtr(item);
    if (!(attr = X509_ATTRIBUTE_create(nid, MBSTRING_ASC, RSTRING(item)->ptr))) {
	ossl_raise(eX509AttrError, NULL);
    }
    WrapX509Attr(klass, obj, attr);
    
    return obj;
}

#if 0
/*
 * is there any print for attribute?
 * (NO, but check t_req.c in crypto/asn1)
 */
static VALUE
ossl_x509attr_to_a(VALUE self)
{
    ossl_x509attr *attrp = NULL;
    BIO *out = NULL;
    BUF_MEM *buf = NULL;
    int nid = NID_undef;
    VALUE ary, value;
	
    GetX509Attr(obj, attrp);
    ary = rb_ary_new2(2);
    nid = OBJ_obj2nid(X509_ATTRIBUTE_get0_object(attrp->attribute));
    rb_ary_push(ary, rb_str_new2(OBJ_nid2sn(nid)));
    if (!(out = BIO_new(BIO_s_mem())))
	ossl_raise(eX509ExtensionError, NULL);
    if (!X509V3_???_print(out, extp->extension, 0, 0)) {
	BIO_free(out);
	ossl_raise(eX509ExtensionError, NULL);
    }
    BIO_get_mem_ptr(out, &buf);
    value = rb_str_new(buf->data, buf->length);
    BIO_free(out);
    rb_funcall(value, rb_intern("tr!"), 2, rb_str_new2("\n"), rb_str_new2(","));
    rb_ary_push(ary, value);

    return ary;
}
#endif

/*
 * X509_ATTRIBUTE init
 */
void
Init_ossl_x509attr()
{
    eX509AttrError = rb_define_class_under(mX509, "AttributeError", eOSSLError);

    cX509Attr = rb_define_class_under(mX509, "Attribute", rb_cObject);
    rb_define_singleton_method(cX509Attr, "new_from_array", ossl_x509attr_s_new_from_array, 1);
/*
 * TODO:
    rb_define_method(cX509Attr, "to_a", ossl_x509attr_to_a, 0);
 */
}
