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

#define WrapX509Name(klass, obj, name) do { \
    if (!name) { \
	ossl_raise(rb_eRuntimeError, "Name wasn't initialized."); \
    } \
    obj = Data_Wrap_Struct(klass, 0, X509_NAME_free, name); \
} while (0)
#define GetX509Name(obj, name) do { \
    Data_Get_Struct(obj, X509_NAME, name); \
    if (!name) { \
	ossl_raise(rb_eRuntimeError, "Name wasn't initialized."); \
    } \
} while (0)
#define SafeGetX509Name(obj, name) do { \
    OSSL_Check_Kind(obj, cX509Name); \
    GetX509Name(obj, name); \
} while (0)

/*
 * Classes
 */
VALUE cX509Name;
VALUE eX509NameError;

/*
 * Public
 */
VALUE 
ossl_x509name_new(X509_NAME *name)
{
    X509_NAME *new;
    VALUE obj;

    if (!name) {
	new = X509_NAME_new();
    } else {
	new = X509_NAME_dup(name);
    }
    if (!new) {
	ossl_raise(eX509NameError, NULL);
    }
    WrapX509Name(cX509Name, obj, new);
    
    return obj;
}

X509_NAME *
GetX509NamePtr(VALUE obj)
{
    X509_NAME *name;

    SafeGetX509Name(obj, name);

    return name;
}

/*
 * Private
 */
static VALUE
ossl_x509name_alloc(VALUE klass)
{
    X509_NAME *name;
    VALUE obj;
	
    if (!(name = X509_NAME_new())) {
	ossl_raise(eX509NameError, NULL);
    }
    WrapX509Name(klass, obj, name);

    return obj;
}

static VALUE
ossl_x509name_initialize(int argc, VALUE *argv, VALUE self)
{
    X509_NAME *name;
    int i, type;
    VALUE arg, str_type, item, key, value;

    GetX509Name(self, name);
    if (rb_scan_args(argc, argv, "02", &arg, &str_type) == 0) {
	return self;
    }
    if (argc == 1 && rb_respond_to(arg, ossl_s_to_der)){
	unsigned char *p;
	VALUE str = rb_funcall(arg, ossl_s_to_der, 0);
	StringValue(str);
	p  = RSTRING(str)->ptr;
	if(!d2i_X509_NAME(&name, &p, RSTRING(str)->len))
	    ossl_raise(eX509NameError, NULL);
        return self;
    }
    Check_Type(arg, T_ARRAY);
    type = NIL_P(str_type) ? V_ASN1_UTF8STRING : NUM2INT(str_type);
    for (i=0; i<RARRAY(arg)->len; i++) {
	item = RARRAY(arg)->ptr[i];
	Check_Type(item, T_ARRAY);
	if (RARRAY(item)->len != 2) {
	    ossl_raise(rb_eArgError, "Unsupported structure.");
	}
	key = RARRAY(item)->ptr[0];
	value = RARRAY(item)->ptr[1];
	StringValue(key);
	StringValue(value);
	if (!X509_NAME_add_entry_by_txt(name, RSTRING(key)->ptr, type,
			RSTRING(value)->ptr, RSTRING(value)->len, -1, 0)) {
	    ossl_raise(eX509NameError, NULL);
	}
    }

    return self;
}

static VALUE
ossl_x509name_to_s(VALUE self)
{
    X509_NAME *name;
    char *buf;
    VALUE str;

    GetX509Name(self, name);
    buf = X509_NAME_oneline(name, NULL, 0);
    str = rb_str_new2(buf);
    OPENSSL_free(buf);

    return str;
}

static VALUE 
ossl_x509name_to_a(VALUE self)
{
    X509_NAME *name;
    X509_NAME_ENTRY *entry;
    int i,entries;
    char long_name[512];
    const char *short_name;
    VALUE ary;
	
    GetX509Name(self, name);
    entries = X509_NAME_entry_count(name);
    if (entries < 0) {
	OSSL_Debug("name entries < 0!");
	return rb_ary_new();
    }
    ary = rb_ary_new2(entries);
    for (i=0; i<entries; i++) {
	if (!(entry = X509_NAME_get_entry(name, i))) {
	    ossl_raise(eX509NameError, NULL);
	}
	if (!i2t_ASN1_OBJECT(long_name, sizeof(long_name), entry->object)) {
	    ossl_raise(eX509NameError, NULL);
	}
	short_name = OBJ_nid2sn(OBJ_ln2nid(long_name));
	
	rb_ary_push(ary, rb_assoc_new(rb_str_new2(short_name),
		rb_str_new(entry->value->data, entry->value->length)));
    }
    return ary;
}

static int
ossl_x509name_cmp0(VALUE self, VALUE other)
{
    X509_NAME *name1, *name2;

    GetX509Name(self, name1);
    SafeGetX509Name(other, name2);

    return X509_NAME_cmp(name1, name2);
}

static VALUE
ossl_x509name_cmp(VALUE self, VALUE other)
{
    int result;

    result = ossl_x509name_cmp0(self, other);
    if (result < 0) return INT2FIX(-1);
    if (result > 1) return INT2FIX(1);

    return INT2FIX(0);
}

static VALUE
ossl_x509name_eql(VALUE self, VALUE other)
{
    int result;

    if(CLASS_OF(other) != cX509Name) return Qfalse;
    result = ossl_x509name_cmp0(self, other);

    return (result == 0) ? Qtrue : Qfalse;
}

static VALUE
ossl_x509name_hash(VALUE self)
{
    X509_NAME *name;
    unsigned long hash;

    GetX509Name(self, name);

    hash = X509_NAME_hash(name);

    return ULONG2NUM(hash);
}

static VALUE
ossl_x509name_to_der(VALUE self)
{
    X509_NAME *name;
    VALUE str;
    long len;
    unsigned char *p;

    GetX509Name(self, name);
    if((len = i2d_X509_NAME(name, NULL)) <= 0)
	ossl_raise(eX509NameError, NULL);
    str = rb_str_new(0, len);
    p = RSTRING(str)->ptr;
    if(i2d_X509_NAME(name, &p) <= 0)
	ossl_raise(eX509NameError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 * INIT
 */
void 
Init_ossl_x509name()
{
    eX509NameError = rb_define_class_under(mX509, "NameError", eOSSLError);

    cX509Name = rb_define_class_under(mX509, "Name", rb_cObject);

    rb_define_alloc_func(cX509Name, ossl_x509name_alloc);
    rb_define_method(cX509Name, "initialize", ossl_x509name_initialize, -1);
    rb_define_method(cX509Name, "to_s", ossl_x509name_to_s, 0);
    rb_define_method(cX509Name, "to_a", ossl_x509name_to_a, 0);
    rb_define_method(cX509Name, "cmp", ossl_x509name_cmp, 1);
    rb_define_alias(cX509Name, "<=>", "cmp");
    rb_define_method(cX509Name, "eql?", ossl_x509name_eql, 1);
    rb_define_method(cX509Name, "hash", ossl_x509name_hash, 0);
    rb_define_method(cX509Name, "to_der", ossl_x509name_to_der, 0);
}
