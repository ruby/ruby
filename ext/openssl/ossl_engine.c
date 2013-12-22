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
    if (!(engine)) { \
	ossl_raise(rb_eRuntimeError, "ENGINE wasn't initialized."); \
    } \
    (obj) = Data_Wrap_Struct((klass), 0, ENGINE_free, (engine)); \
} while(0)
#define GetEngine(obj, engine) do { \
    Data_Get_Struct((obj), ENGINE, (engine)); \
    if (!(engine)) { \
        ossl_raise(rb_eRuntimeError, "ENGINE wasn't initialized."); \
    } \
} while (0)
#define SafeGetEngine(obj, engine) do { \
    OSSL_Check_Kind((obj), cEngine); \
    GetPKCS7((obj), (engine)); \
} while (0)

/*
 * Classes
 */
/* Document-class: OpenSSL::Engine
 *
 * This class is the access to openssl's ENGINE cryptographic module
 * implementation.
 *
 * See also, https://www.openssl.org/docs/crypto/engine.html
 */
VALUE cEngine;
/* Document-class: OpenSSL::Engine::EngineError
 *
 * This is the generic exception for OpenSSL::Engine related errors
 */
VALUE eEngineError;

/*
 * Private
 */
#define OSSL_ENGINE_LOAD_IF_MATCH(x) \
do{\
  if(!strcmp(#x, RSTRING_PTR(name))){\
    ENGINE_load_##x();\
    return Qtrue;\
  }\
}while(0)

/* Document-method: OpenSSL::Engine.load
 *
 * call-seq:
 *   load(enginename = nil)
 *
 * This method loads engines. If +name+ is nil, then all builtin engines are
 * loaded. Otherwise, the given +name+, as a string,  is loaded if available to
 * your runtime, and returns true. If +name+ is not found, then nil is
 * returned.
 *
 */
static VALUE
ossl_engine_s_load(int argc, VALUE *argv, VALUE klass)
{
#if !defined(HAVE_ENGINE_LOAD_BUILTIN_ENGINES)
    return Qnil;
#else
    VALUE name;

    rb_scan_args(argc, argv, "01", &name);
    if(NIL_P(name)){
        ENGINE_load_builtin_engines();
        return Qtrue;
    }
    StringValue(name);
#ifndef OPENSSL_NO_STATIC_ENGINE
#if HAVE_ENGINE_LOAD_DYNAMIC
    OSSL_ENGINE_LOAD_IF_MATCH(dynamic);
#endif
#if HAVE_ENGINE_LOAD_4758CCA
    OSSL_ENGINE_LOAD_IF_MATCH(4758cca);
#endif
#if HAVE_ENGINE_LOAD_AEP
    OSSL_ENGINE_LOAD_IF_MATCH(aep);
#endif
#if HAVE_ENGINE_LOAD_ATALLA
    OSSL_ENGINE_LOAD_IF_MATCH(atalla);
#endif
#if HAVE_ENGINE_LOAD_CHIL
    OSSL_ENGINE_LOAD_IF_MATCH(chil);
#endif
#if HAVE_ENGINE_LOAD_CSWIFT
    OSSL_ENGINE_LOAD_IF_MATCH(cswift);
#endif
#if HAVE_ENGINE_LOAD_NURON
    OSSL_ENGINE_LOAD_IF_MATCH(nuron);
#endif
#if HAVE_ENGINE_LOAD_SUREWARE
    OSSL_ENGINE_LOAD_IF_MATCH(sureware);
#endif
#if HAVE_ENGINE_LOAD_UBSEC
    OSSL_ENGINE_LOAD_IF_MATCH(ubsec);
#endif
#if HAVE_ENGINE_LOAD_PADLOCK
    OSSL_ENGINE_LOAD_IF_MATCH(padlock);
#endif
#if HAVE_ENGINE_LOAD_CAPI
    OSSL_ENGINE_LOAD_IF_MATCH(capi);
#endif
#if HAVE_ENGINE_LOAD_GMP
    OSSL_ENGINE_LOAD_IF_MATCH(gmp);
#endif
#if HAVE_ENGINE_LOAD_GOST
    OSSL_ENGINE_LOAD_IF_MATCH(gost);
#endif
#if HAVE_ENGINE_LOAD_CRYPTODEV
    OSSL_ENGINE_LOAD_IF_MATCH(cryptodev);
#endif
#if HAVE_ENGINE_LOAD_AESNI
    OSSL_ENGINE_LOAD_IF_MATCH(aesni);
#endif
#endif
#ifdef HAVE_ENGINE_LOAD_OPENBSD_DEV_CRYPTO
    OSSL_ENGINE_LOAD_IF_MATCH(openbsd_dev_crypto);
#endif
    OSSL_ENGINE_LOAD_IF_MATCH(openssl);
    rb_warning("no such builtin loader for `%s'", RSTRING_PTR(name));
    return Qnil;
#endif /* HAVE_ENGINE_LOAD_BUILTIN_ENGINES */
}

/* Document-method: OpenSSL::Engine.cleanup
 * call-seq:
 *  OpenSSL::Engine.cleanup
 *
 * It is only necessary to run cleanup when engines are loaded via
 * OpenSSL::Engine.load. However, running cleanup before exit is recommended.
 *
 * See also, https://www.openssl.org/docs/crypto/engine.html
 */
static VALUE
ossl_engine_s_cleanup(VALUE self)
{
#if defined(HAVE_ENGINE_CLEANUP)
    ENGINE_cleanup();
#endif
    return Qnil;
}

/* Document-method: OpenSSL::Engine.engines
 *
 * Returns an array of currently loaded engines.
 */
static VALUE
ossl_engine_s_engines(VALUE klass)
{
    ENGINE *e;
    VALUE ary, obj;

    ary = rb_ary_new();
    for(e = ENGINE_get_first(); e; e = ENGINE_get_next(e)){
	/* Need a ref count of two here because of ENGINE_free being
	 * called internally by OpenSSL when moving to the next ENGINE
	 * and by us when releasing the ENGINE reference */
	ENGINE_up_ref(e);
	WrapEngine(klass, obj, e);
        rb_ary_push(ary, obj);
    }

    return ary;
}

/* Document-method: OpenSSL::Engine.by_id
 *
 * call-seq:
 *   by_id(name) -> engine
 *
 * Fetch the engine as specified by the +id+ String
 *
 *   OpenSSL::Engine.by_id("openssl")
 *    => #<OpenSSL::Engine id="openssl" name="Software engine support">
 *
 * See OpenSSL::Engine.engines for the currently loaded engines
 */
static VALUE
ossl_engine_s_by_id(VALUE klass, VALUE id)
{
    ENGINE *e;
    VALUE obj;

    StringValue(id);
    ossl_engine_s_load(1, &id, klass);
    if(!(e = ENGINE_by_id(RSTRING_PTR(id))))
	ossl_raise(eEngineError, NULL);
    WrapEngine(klass, obj, e);
    if(rb_block_given_p()) rb_yield(obj);
    if(!ENGINE_init(e))
	ossl_raise(eEngineError, NULL);
    ENGINE_ctrl(e, ENGINE_CTRL_SET_PASSWORD_CALLBACK,
		0, NULL, (void(*)(void))ossl_pem_passwd_cb);
    ERR_clear_error();

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

/* Document-method: OpenSSL::Engine#id
 *
 * Get the id for this engine
 *
 *    OpenSSL::Engine.load
 *    OpenSSL::Engine.engines #=> [#<OpenSSL::Engine#>, ...]
 *    OpenSSL::Engine.engines.first.id
 *	#=> "rsax"
 */
static VALUE
ossl_engine_get_id(VALUE self)
{
    ENGINE *e;
    GetEngine(self, e);
    return rb_str_new2(ENGINE_get_id(e));
}

/* Document-method: OpenSSL::Engine#name
 *
 * Get the descriptive name for this engine
 *
 *    OpenSSL::Engine.load
 *    OpenSSL::Engine.engines #=> [#<OpenSSL::Engine#>, ...]
 *    OpenSSL::Engine.engines.first.name
 *	#=> "RSAX engine support"
 *
 */
static VALUE
ossl_engine_get_name(VALUE self)
{
    ENGINE *e;
    GetEngine(self, e);
    return rb_str_new2(ENGINE_get_name(e));
}

/* Document-method: OpenSSL::Engine#finish
 *
 * Releases all internal structural references for this engine.
 *
 * May raise an EngineError if the engine is unavailable
 */
static VALUE
ossl_engine_finish(VALUE self)
{
    ENGINE *e;

    GetEngine(self, e);
    if(!ENGINE_finish(e)) ossl_raise(eEngineError, NULL);

    return Qnil;
}

#if defined(HAVE_ENGINE_GET_CIPHER)
/* Document-method: OpenSSL::Engine#cipher
 *
 * call-seq:
 *   engine.cipher(name) -> OpenSSL::Cipher
 *
 * This returns an OpenSSL::Cipher by +name+, if it is available in this
 * engine.
 *
 * A EngineError will be raised if the cipher is unavailable.
 *
 *    e = OpenSSL::Engine.by_id("openssl")
 *     => #<OpenSSL::Engine id="openssl" name="Software engine support">
 *    e.cipher("RC4")
 *     => #<OpenSSL::Cipher:0x007fc5cacc3048>
 *
 */
static VALUE
ossl_engine_get_cipher(VALUE self, VALUE name)
{
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
}
#else
#define ossl_engine_get_cipher rb_f_notimplement
#endif

#if defined(HAVE_ENGINE_GET_DIGEST)
/* Document-method: OpenSSL::Engine#digest
 *
 * call-seq:
 *   engine.digest(name) -> OpenSSL::Digest
 *
 * This returns an OpenSSL::Digest by +name+.
 *
 * Will raise an EngineError if the digest is unavailable.
 *
 *    e = OpenSSL::Engine.by_id("openssl")
 *	#=> #<OpenSSL::Engine id="openssl" name="Software engine support">
 *    e.digest("SHA1")
 *	#=> #<OpenSSL::Digest: da39a3ee5e6b4b0d3255bfef95601890afd80709>
 *    e.digest("zomg")
 *	#=> OpenSSL::Engine::EngineError: no such digest `zomg'
 */
static VALUE
ossl_engine_get_digest(VALUE self, VALUE name)
{
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
}
#else
#define ossl_engine_get_digest rb_f_notimplement
#endif

/* Document-method: OpenSSL::Engine#load_private_key
 *
 * call-seq:
 *    engine.load_private_key(id = nil, data = nil) -> OpenSSL::PKey
 *
 * Loads the given private key by +id+ and +data+.
 *
 * An EngineError is raised of the OpenSSL::PKey is unavailable.
 *
 */
static VALUE
ossl_engine_load_privkey(int argc, VALUE *argv, VALUE self)
{
    ENGINE *e;
    EVP_PKEY *pkey;
    VALUE id, data, obj;
    char *sid, *sdata;

    rb_scan_args(argc, argv, "02", &id, &data);
    sid = NIL_P(id) ? NULL : StringValuePtr(id);
    sdata = NIL_P(data) ? NULL : StringValuePtr(data);
    GetEngine(self, e);
#if OPENSSL_VERSION_NUMBER < 0x00907000L
    pkey = ENGINE_load_private_key(e, sid, sdata);
#else
    pkey = ENGINE_load_private_key(e, sid, NULL, sdata);
#endif
    if (!pkey) ossl_raise(eEngineError, NULL);
    obj = ossl_pkey_new(pkey);
    OSSL_PKEY_SET_PRIVATE(obj);

    return obj;
}

/* Document-method: OpenSSL::Engine#load_public_key
 *
 * call-seq:
 *    engine.load_public_key(id = nil, data = nil) -> OpenSSL::PKey
 *
 * Loads the given private key by +id+ and +data+.
 *
 * An EngineError is raised of the OpenSSL::PKey is unavailable.
 *
 */
static VALUE
ossl_engine_load_pubkey(int argc, VALUE *argv, VALUE self)
{
    ENGINE *e;
    EVP_PKEY *pkey;
    VALUE id, data;
    char *sid, *sdata;

    rb_scan_args(argc, argv, "02", &id, &data);
    sid = NIL_P(id) ? NULL : StringValuePtr(id);
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

/* Document-method: OpenSSL::Engine#set_default
 *
 * call-seq:
 *    engine.set_default(flag)
 *
 * Set the defaults for this engine with the given +flag+.
 *
 * These flags are used to control combinations of algorithm methods.
 *
 * +flag+ can be one of the following, other flags are available depending on
 * your OS.
 *
 * [All flags]  0xFFFF
 * [No flags]	0x0000
 *
 * See also <openssl/engine.h>
 */
static VALUE
ossl_engine_set_default(VALUE self, VALUE flag)
{
    ENGINE *e;
    int f = NUM2INT(flag);

    GetEngine(self, e);
    ENGINE_set_default(e, f);

    return Qtrue;
}

/* Document-method: OpenSSL::Engine#ctrl_cmd
 *
 * call-seq:
 *    engine.ctrl_cmd(command, value = nil) -> engine
 *
 * Send the given +command+ to this engine.
 *
 * Raises an EngineError if the +command+ fails.
 */
static VALUE
ossl_engine_ctrl_cmd(int argc, VALUE *argv, VALUE self)
{
    ENGINE *e;
    VALUE cmd, val;
    int ret;

    GetEngine(self, e);
    rb_scan_args(argc, argv, "11", &cmd, &val);
    StringValue(cmd);
    if (!NIL_P(val)) StringValue(val);
    ret = ENGINE_ctrl_cmd_string(e, RSTRING_PTR(cmd),
				 NIL_P(val) ? NULL : RSTRING_PTR(val), 0);
    if (!ret) ossl_raise(eEngineError, NULL);

    return self;
}

static VALUE
ossl_engine_cmd_flag_to_name(int flag)
{
    switch(flag){
    case ENGINE_CMD_FLAG_NUMERIC:  return rb_str_new2("NUMERIC");
    case ENGINE_CMD_FLAG_STRING:   return rb_str_new2("STRING");
    case ENGINE_CMD_FLAG_NO_INPUT: return rb_str_new2("NO_INPUT");
    case ENGINE_CMD_FLAG_INTERNAL: return rb_str_new2("INTERNAL");
    default: return rb_str_new2("UNKNOWN");
    }
}

/* Document-method: OpenSSL::Engine#cmds
 *
 * Returns an array of command definitions for the current engine
 */
static VALUE
ossl_engine_get_cmds(VALUE self)
{
    ENGINE *e;
    const ENGINE_CMD_DEFN *defn, *p;
    VALUE ary, tmp;

    GetEngine(self, e);
    ary = rb_ary_new();
    if ((defn = ENGINE_get_cmd_defns(e)) != NULL){
	for (p = defn; p->cmd_num > 0; p++){
	    tmp = rb_ary_new();
	    rb_ary_push(tmp, rb_str_new2(p->cmd_name));
	    rb_ary_push(tmp, rb_str_new2(p->cmd_desc));
	    rb_ary_push(tmp, ossl_engine_cmd_flag_to_name(p->cmd_flags));
	    rb_ary_push(ary, tmp);
	}
    }

    return ary;
}

/* Document-method: OpenSSL::Engine#inspect
 *
 * Pretty print this engine
 */
static VALUE
ossl_engine_inspect(VALUE self)
{
    VALUE str;
    const char *cname = rb_class2name(rb_obj_class(self));

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
    rb_define_method(cEngine, "ctrl_cmd", ossl_engine_ctrl_cmd, -1);
    rb_define_method(cEngine, "cmds", ossl_engine_get_cmds, 0);
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
