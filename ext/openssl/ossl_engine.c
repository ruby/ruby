/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2003  GOTOU Yuuzou <gotoyuzo@notwork.org>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if defined(OSSL_ENGINE_ENABLED)

#define WrapEngine(klass, obj, engine) do { \
    if (!engine) { \
	ossl_raise(rb_eRuntimeError, "ENGINE wasn't initialized."); \
    } \
    obj = Data_Wrap_Struct(klass, 0, ENGINE_free, engine); \
} while(0)
#define GetEngine(obj, engine) do { \
    Data_Get_Struct(obj, ENGINE, engine); \
    if (!engine) { \
        ossl_raise(rb_eRuntimeError, "ENGINE wasn't initialized."); \
    } \
} while (0)
#define SafeGetEngine(obj, engine) do { \
    OSSL_Check_Kind(obj, cEngine); \
    GetPKCS7(obj, engine); \
} while (0)

/* 
 * Classes
 */
VALUE cEngine;
VALUE eEngineError;

/*
 * Private
 */
#define OSSL_ENGINE_LOAD_IF_MATCH(x) \
do{\
  if(!strcmp(#x, RSTRING(name)->ptr)){\
    ENGINE_load_##x();\
    return Qtrue;\
  }\
}while(0)

static VALUE
ossl_engine_s_load(int argc, VALUE *argv, VALUE klass)
{
#if !defined(HAVE_ENGINE_LOAD_BUILTIN_ENGINES)
    return Qnil;
#else
    VALUE name;

    rb_scan_args(argc, argv, "01", &name);
    if(NIL_P(name)) ENGINE_load_builtin_engines();
    StringValue(name);
    OSSL_ENGINE_LOAD_IF_MATCH(openssl);
    OSSL_ENGINE_LOAD_IF_MATCH(dynamic);
    OSSL_ENGINE_LOAD_IF_MATCH(cswift);
    OSSL_ENGINE_LOAD_IF_MATCH(chil);
    OSSL_ENGINE_LOAD_IF_MATCH(atalla);
    OSSL_ENGINE_LOAD_IF_MATCH(nuron);
    OSSL_ENGINE_LOAD_IF_MATCH(ubsec);
    OSSL_ENGINE_LOAD_IF_MATCH(aep);
    OSSL_ENGINE_LOAD_IF_MATCH(sureware);
    OSSL_ENGINE_LOAD_IF_MATCH(4758cca);
#ifdef HAVE_ENGINE_LOAD_OPENBSD_DEV_CRYPTO
    OSSL_ENGINE_LOAD_IF_MATCH(openbsd_dev_crypto);
#endif
    rb_warning("no such engine `%s'", RSTRING(name)->ptr);
#endif /* HAVE_ENGINE_LOAD_BUILTIN_ENGINES */
}

static VALUE
ossl_engine_s_cleanup(VALUE self)
{
#if defined(HAVE_ENGINE_CLEANUP)
    ENGINE_cleanup();
#endif
    return Qnil;
}

static VALUE
ossl_engine_s_engines(VALUE klass)
{
    ENGINE *e;
    VALUE ary, obj;

    ary = rb_ary_new();
    for(e = ENGINE_get_first(); e; e = ENGINE_get_next(e)){
        WrapEngine(klass, obj, e);
        rb_ary_push(ary, obj);
    }

    return ary;
}

static VALUE
ossl_engine_s_by_id(VALUE klass, VALUE id)
{
    ENGINE *e;
    VALUE obj;

    StringValue(id);
    ossl_engine_s_load(1, &id, klass);
    if(!(e = ENGINE_by_id(RSTRING(id)->ptr)))
	ossl_raise(eEngineError, NULL);
    if(!ENGINE_init(e))
	ossl_raise(eEngineError, NULL);
    ENGINE_ctrl(e, ENGINE_CTRL_SET_PASSWORD_CALLBACK,
		0, NULL, (void(*)())ossl_pem_passwd_cb);
    ERR_clear_error();
    WrapEngine(klass, obj, e);

    return obj;
}

static VALUE
ossl_engine_s_alloc(VALUE klass)
{
    ENGINE *e;
    VALUE obj;

    if (!(e = ENGINE_new())) {
       ossl_raise(eEngineError, NULL);
    }
    WrapEngine(klass, obj, e);

    return obj;
}

static VALUE
ossl_engine_get_id(VALUE self)
{
    ENGINE *e;
    GetEngine(self, e);
    return rb_str_new2(ENGINE_get_id(e));
}

static VALUE
ossl_engine_get_name(VALUE self)
{
    ENGINE *e;
    GetEngine(self, e);
    return rb_str_new2(ENGINE_get_name(e));
}

static VALUE
ossl_engine_finish(VALUE self)
{
    ENGINE *e;

    GetEngine(self, e);
    if(!ENGINE_finish(e)) ossl_raise(eEngineError, NULL);

    return Qnil;
}

static VALUE
ossl_engine_get_cipher(VALUE self, VALUE name)
{
#if defined(HAVE_ENGINE_GET_CIPHER)
    ENGINE *e;
    const EVP_CIPHER *ciph, *tmp;
    char *s;
    int nid;

    s = StringValuePtr(name);
    tmp = EVP_get_cipherbyname(s);
    if(!tmp) ossl_raise(eEngineError, "no such cipher `%s'", s);
    nid = EVP_CIPHER_nid(tmp);
    GetEngine(self, e);
    ciph = ENGINE_get_cipher(e, nid);
    if(!ciph) ossl_raise(eEngineError, NULL);

    return ossl_cipher_new(ciph);
#else
    rb_notimplement();
#endif
}

static VALUE
ossl_engine_get_digest(VALUE self, VALUE name)
{
#if defined(HAVE_ENGINE_GET_DIGEST)
    ENGINE *e;
    const EVP_MD *md, *tmp;
    char *s;
    int nid;

    s = StringValuePtr(name);
    tmp = EVP_get_digestbyname(s);
    if(!tmp) ossl_raise(eEngineError, "no such digest `%s'", s);
    nid = EVP_MD_nid(tmp);
    GetEngine(self, e);
    md = ENGINE_get_digest(e, nid);
    if(!md) ossl_raise(eEngineError, NULL);

    return ossl_digest_new(md);
#else
    rb_notimplement();
#endif
}

static VALUE
ossl_engine_load_privkey(int argc, VALUE *argv, VALUE self)
{
    ENGINE *e;
    EVP_PKEY *pkey;
    VALUE id, data;
    char *sid, *sdata;

    rb_scan_args(argc, argv, "11", &id, &data);
    sid = StringValuePtr(id);
    sdata = NIL_P(data) ? NULL : StringValuePtr(data);
    GetEngine(self, e);
#if OPENSSL_VERSION_NUMBER < 0x00907000L
    pkey = ENGINE_load_private_key(e, sid, sdata);
#else
    pkey = ENGINE_load_private_key(e, sid, NULL, sdata);
#endif
    if (!pkey) ossl_raise(eEngineError, NULL);

    return ossl_pkey_new(pkey);
}

static VALUE
ossl_engine_load_pubkey(int argc, VALUE *argv, VALUE self)
{
    ENGINE *e;
    EVP_PKEY *pkey;
    VALUE id, data;
    char *sid, *sdata;

    rb_scan_args(argc, argv, "11", &id, &data);
    sid = StringValuePtr(id);
    sdata = NIL_P(data) ? NULL : StringValuePtr(data);
    GetEngine(self, e);
#if OPENSSL_VERSION_NUMBER < 0x00907000L
    pkey = ENGINE_load_public_key(e, sid, sdata);
#else
    pkey = ENGINE_load_public_key(e, sid, NULL, sdata);
#endif
    if (!pkey) ossl_raise(eEngineError, NULL);

    return ossl_pkey_new(pkey);
}

static VALUE
ossl_engine_set_default(VALUE self, VALUE flag)
{
    ENGINE *e;
    int f = NUM2INT(flag);

    GetEngine(self, e);
    ENGINE_set_default(e, f);

    return Qtrue;
}

static VALUE
ossl_engine_inspect(VALUE self)
{
    VALUE str;
    char *cname = rb_class2name(rb_obj_class(self));
    
    str = rb_str_new2("#<");
    rb_str_cat2(str, cname);
    rb_str_cat2(str, " id=\"");
    rb_str_append(str, ossl_engine_get_id(self));
    rb_str_cat2(str, "\" name=\"");
    rb_str_append(str, ossl_engine_get_name(self));
    rb_str_cat2(str, "\">");

    return str;
}

#define DefEngineConst(x) rb_define_const(cEngine, #x, INT2NUM(ENGINE_##x))

void
Init_ossl_engine()
{
    cEngine = rb_define_class_under(mOSSL, "Engine", rb_cObject);
    eEngineError = rb_define_class_under(cEngine, "EngineError", eOSSLError);

    rb_define_alloc_func(cEngine, ossl_engine_s_alloc);
    rb_define_singleton_method(cEngine, "load", ossl_engine_s_load, -1);
    rb_define_singleton_method(cEngine, "cleanup", ossl_engine_s_cleanup, 0);
    rb_define_singleton_method(cEngine, "engines", ossl_engine_s_engines, 0);
    rb_define_singleton_method(cEngine, "by_id", ossl_engine_s_by_id, 1);
    rb_undef_method(CLASS_OF(cEngine), "new");

    rb_define_method(cEngine, "id", ossl_engine_get_id, 0);
    rb_define_method(cEngine, "name", ossl_engine_get_name, 0);
    rb_define_method(cEngine, "finish", ossl_engine_finish, 0);
    rb_define_method(cEngine, "cipher", ossl_engine_get_cipher, 1);
    rb_define_method(cEngine, "digest",  ossl_engine_get_digest, 1);
    rb_define_method(cEngine, "load_private_key", ossl_engine_load_privkey, -1);
    rb_define_method(cEngine, "load_public_key", ossl_engine_load_pubkey, -1);
    rb_define_method(cEngine, "set_default", ossl_engine_set_default, 1);
    rb_define_method(cEngine, "inspect", ossl_engine_inspect, 0);

    DefEngineConst(METHOD_RSA);
    DefEngineConst(METHOD_DSA);
    DefEngineConst(METHOD_DH);
    DefEngineConst(METHOD_RAND);
#ifdef ENGINE_METHOD_BN_MOD_EXP
    DefEngineConst(METHOD_BN_MOD_EXP);
#endif
#ifdef ENGINE_METHOD_BN_MOD_EXP_CRT
    DefEngineConst(METHOD_BN_MOD_EXP_CRT);
#endif
#ifdef ENGINE_METHOD_CIPHERS
    DefEngineConst(METHOD_CIPHERS);
#endif
#ifdef ENGINE_METHOD_DIGESTS
    DefEngineConst(METHOD_DIGESTS);
#endif
    DefEngineConst(METHOD_ALL);
    DefEngineConst(METHOD_NONE);
}
#else
void
Init_ossl_engine()
{
}
#endif
