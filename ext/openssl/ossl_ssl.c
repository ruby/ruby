/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2000-2002  GOTOU Yuuzou <gotoyuzo@notwork.org>
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * Copyright (C) 2001-2007  Technorama Ltd. <oss-ruby@technorama.net>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if defined(HAVE_UNISTD_H)
#  include <unistd.h> /* for read(), and write() */
#endif

#define numberof(ary) (sizeof(ary)/sizeof(ary[0]))

#ifdef _WIN32
#  define TO_SOCKET(s) _get_osfhandle(s)
#else
#  define TO_SOCKET(s) s
#endif

VALUE mSSL;
VALUE eSSLError;
VALUE cSSLContext;
VALUE cSSLSocket;

#define ossl_sslctx_set_cert(o,v)        rb_iv_set((o),"@cert",(v))
#define ossl_sslctx_set_key(o,v)         rb_iv_set((o),"@key",(v))
#define ossl_sslctx_set_client_ca(o,v)   rb_iv_set((o),"@client_ca",(v))
#define ossl_sslctx_set_ca_file(o,v)     rb_iv_set((o),"@ca_file",(v))
#define ossl_sslctx_set_ca_path(o,v)     rb_iv_set((o),"@ca_path",(v))
#define ossl_sslctx_set_timeout(o,v)     rb_iv_set((o),"@timeout",(v))
#define ossl_sslctx_set_verify_mode(o,v) rb_iv_set((o),"@verify_mode",(v))
#define ossl_sslctx_set_verify_dep(o,v)  rb_iv_set((o),"@verify_depth",(v))
#define ossl_sslctx_set_verify_cb(o,v)   rb_iv_set((o),"@verify_callback",(v))
#define ossl_sslctx_set_options(o,v)     rb_iv_set((o),"@options",(v))
#define ossl_sslctx_set_cert_store(o,v)  rb_iv_set((o),"@cert_store",(v))
#define ossl_sslctx_set_extra_cert(o,v)  rb_iv_set((o),"@extra_chain_cert",(v))
#define ossl_sslctx_set_client_cert_cb(o,v) rb_iv_set((o),"@client_cert_cb",(v))
#define ossl_sslctx_set_tmp_dh_cb(o,v)   rb_iv_set((o),"@tmp_dh_callback",(v))
#define ossl_sslctx_set_sess_id_ctx(o, v) rb_iv_get((o),"@session_id_context"(v))

#define ossl_sslctx_get_cert(o)          rb_iv_get((o),"@cert")
#define ossl_sslctx_get_key(o)           rb_iv_get((o),"@key")
#define ossl_sslctx_get_client_ca(o)     rb_iv_get((o),"@client_ca")
#define ossl_sslctx_get_ca_file(o)       rb_iv_get((o),"@ca_file")
#define ossl_sslctx_get_ca_path(o)       rb_iv_get((o),"@ca_path")
#define ossl_sslctx_get_timeout(o)       rb_iv_get((o),"@timeout")
#define ossl_sslctx_get_verify_mode(o)   rb_iv_get((o),"@verify_mode")
#define ossl_sslctx_get_verify_dep(o)    rb_iv_get((o),"@verify_depth")
#define ossl_sslctx_get_verify_cb(o)     rb_iv_get((o),"@verify_callback")
#define ossl_sslctx_get_options(o)       rb_iv_get((o),"@options")
#define ossl_sslctx_get_cert_store(o)    rb_iv_get((o),"@cert_store")
#define ossl_sslctx_get_extra_cert(o)    rb_iv_get((o),"@extra_chain_cert")
#define ossl_sslctx_get_client_cert_cb(o) rb_iv_get((o),"@client_cert_cb")
#define ossl_sslctx_get_tmp_dh_cb(o)     rb_iv_get((o),"@tmp_dh_callback")
#define ossl_sslctx_get_sess_id_ctx(o)   rb_iv_get((o),"@session_id_context")

static const char *ossl_sslctx_attrs[] = {
    "cert", "key", "client_ca", "ca_file", "ca_path",
    "timeout", "verify_mode", "verify_depth",
    "verify_callback", "options", "cert_store", "extra_chain_cert",
    "client_cert_cb", "tmp_dh_callback", "session_id_context",
    "session_get_cb", "session_new_cb", "session_remove_cb",
#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
    "servername_cb",
#endif
};

#define ossl_ssl_get_io(o)           rb_iv_get((o),"@io")
#define ossl_ssl_get_ctx(o)          rb_iv_get((o),"@context")
#define ossl_ssl_get_sync_close(o)   rb_iv_get((o),"@sync_close")
#define ossl_ssl_get_x509(o)         rb_iv_get((o),"@x509")
#define ossl_ssl_get_key(o)          rb_iv_get((o),"@key")
#define ossl_ssl_get_tmp_dh(o)       rb_iv_get((o),"@tmp_dh")

#define ossl_ssl_set_io(o,v)         rb_iv_set((o),"@io",(v))
#define ossl_ssl_set_ctx(o,v)        rb_iv_set((o),"@context",(v))
#define ossl_ssl_set_sync_close(o,v) rb_iv_set((o),"@sync_close",(v))
#define ossl_ssl_set_x509(o,v)       rb_iv_set((o),"@x509",(v))
#define ossl_ssl_set_key(o,v)        rb_iv_set((o),"@key",(v))
#define ossl_ssl_set_tmp_dh(o,v)     rb_iv_set((o),"@tmp_dh",(v))

static const char *ossl_ssl_attr_readers[] = { "io", "context", };
static const char *ossl_ssl_attrs[] = {
#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
    "hostname",
#endif
    "sync_close",
};

ID ID_callback_state;

/*
 * SSLContext class
 */
struct {
    const char *name;
    SSL_METHOD *(*func)(void);
} ossl_ssl_method_tab[] = {
#define OSSL_SSL_METHOD_ENTRY(name) { #name, name##_method }
    OSSL_SSL_METHOD_ENTRY(TLSv1),
    OSSL_SSL_METHOD_ENTRY(TLSv1_server),
    OSSL_SSL_METHOD_ENTRY(TLSv1_client),
    OSSL_SSL_METHOD_ENTRY(SSLv2),
    OSSL_SSL_METHOD_ENTRY(SSLv2_server),
    OSSL_SSL_METHOD_ENTRY(SSLv2_client),
    OSSL_SSL_METHOD_ENTRY(SSLv3),
    OSSL_SSL_METHOD_ENTRY(SSLv3_server),
    OSSL_SSL_METHOD_ENTRY(SSLv3_client),
    OSSL_SSL_METHOD_ENTRY(SSLv23),
    OSSL_SSL_METHOD_ENTRY(SSLv23_server),
    OSSL_SSL_METHOD_ENTRY(SSLv23_client),
#undef OSSL_SSL_METHOD_ENTRY
};

int ossl_ssl_ex_vcb_idx;
int ossl_ssl_ex_store_p;
int ossl_ssl_ex_ptr_idx;
int ossl_ssl_ex_client_cert_cb_idx;
int ossl_ssl_ex_tmp_dh_callback_idx;

static void
ossl_sslctx_free(SSL_CTX *ctx)
{
    if(ctx && SSL_CTX_get_ex_data(ctx, ossl_ssl_ex_store_p)== (void*)1)
	ctx->cert_store = NULL;
    SSL_CTX_free(ctx);
}

static VALUE
ossl_sslctx_s_alloc(VALUE klass)
{
    SSL_CTX *ctx;

    ctx = SSL_CTX_new(SSLv23_method());
    if (!ctx) {
        ossl_raise(eSSLError, "SSL_CTX_new:");
    }
    SSL_CTX_set_mode(ctx, SSL_MODE_ENABLE_PARTIAL_WRITE);
    SSL_CTX_set_options(ctx, SSL_OP_ALL);
    return Data_Wrap_Struct(klass, 0, ossl_sslctx_free, ctx);
}

static VALUE
ossl_sslctx_set_ssl_version(VALUE self, VALUE ssl_method)
{
    SSL_METHOD *method = NULL;
    const char *s;
    int i;

    SSL_CTX *ctx;
    if(TYPE(ssl_method) == T_SYMBOL)
	s = rb_id2name(SYM2ID(ssl_method));
    else
	s =  StringValuePtr(ssl_method);
    for (i = 0; i < numberof(ossl_ssl_method_tab); i++) {
        if (strcmp(ossl_ssl_method_tab[i].name, s) == 0) {
            method = ossl_ssl_method_tab[i].func();
            break;
        }
    }
    if (!method) {
        ossl_raise(rb_eArgError, "unknown SSL method `%s'.", s);
    }
    Data_Get_Struct(self, SSL_CTX, ctx);
    if (SSL_CTX_set_ssl_version(ctx, method) != 1) {
        ossl_raise(eSSLError, "SSL_CTX_set_ssl_version:");
    }

    return ssl_method;
}

/*
 * call-seq:
 *    SSLContext.new => ctx
 *    SSLContext.new(:TLSv1) => ctx
 *    SSLContext.new("SSLv23_client") => ctx
 *
 * You can get a list of valid methods with OpenSSL::SSL::SSLContext::METHODS
 */
static VALUE
ossl_sslctx_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE ssl_method;
    int i;

    for(i = 0; i < numberof(ossl_sslctx_attrs); i++){
	char buf[32];
	snprintf(buf, sizeof(buf), "@%s", ossl_sslctx_attrs[i]);
	rb_iv_set(self, buf, Qnil);
    }
    if (rb_scan_args(argc, argv, "01", &ssl_method) == 0){
        return self;
    }
    ossl_sslctx_set_ssl_version(self, ssl_method);

    return self;
}

static VALUE
ossl_call_client_cert_cb(VALUE obj)
{
    VALUE cb, ary, cert, key;
    SSL *ssl;

    Data_Get_Struct(obj, SSL, ssl);
    cb = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_client_cert_cb_idx);
    if (NIL_P(cb)) return Qfalse;
    ary = rb_funcall(cb, rb_intern("call"), 1, obj);
    Check_Type(ary, T_ARRAY);
    GetX509CertPtr(cert = rb_ary_entry(ary, 0));
    GetPKeyPtr(key = rb_ary_entry(ary, 1));
    ossl_ssl_set_x509(obj, cert);
    ossl_ssl_set_key(obj, key);

    return Qtrue;
}

static int
ossl_client_cert_cb(SSL *ssl, X509 **x509, EVP_PKEY **pkey)
{
    VALUE obj;
    int status, success;

    obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    success = rb_protect((VALUE(*)_((VALUE)))ossl_call_client_cert_cb,
                         obj, &status);
    if (status || !success) return 0;
    *x509 = DupX509CertPtr(ossl_ssl_get_x509(obj));
    *pkey = DupPKeyPtr(ossl_ssl_get_key(obj));

    return 1;
}

#if !defined(OPENSSL_NO_DH)
static VALUE
ossl_call_tmp_dh_callback(VALUE *args)
{
    SSL *ssl;
    VALUE cb, dh;
    EVP_PKEY *pkey;

    Data_Get_Struct(args[0], SSL, ssl);
    cb = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_tmp_dh_callback_idx);
    if (NIL_P(cb)) return Qfalse;
    dh = rb_funcall(cb, rb_intern("call"), 3, args[0], args[1], args[2]);
    pkey = GetPKeyPtr(dh);
    if (EVP_PKEY_type(pkey->type) != EVP_PKEY_DH) return Qfalse;
    ossl_ssl_set_tmp_dh(args[0], dh);

    return Qtrue;
}

static DH*
ossl_tmp_dh_callback(SSL *ssl, int is_export, int keylength)
{
    VALUE args[3];
    int status, success;

    args[0] = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    args[1] = INT2FIX(is_export);
    args[2] = INT2FIX(keylength);
    success = rb_protect((VALUE(*)_((VALUE)))ossl_call_tmp_dh_callback,
                         (VALUE)args, &status);
    if (status || !success) return NULL;

    return GetPKeyPtr(ossl_ssl_get_tmp_dh(args[0]))->pkey.dh;
}

static DH*
ossl_default_tmp_dh_callback(SSL *ssl, int is_export, int keylength)
{
    rb_warning("using default DH parameters.");

    switch(keylength){
    case 512:
	return OSSL_DEFAULT_DH_512;
    case 1024:
	return OSSL_DEFAULT_DH_1024;
    }
    return NULL;
}
#endif /* OPENSSL_NO_DH */

static int
ossl_ssl_verify_callback(int preverify_ok, X509_STORE_CTX *ctx)
{
    VALUE cb;
    SSL *ssl;

    ssl = X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
    cb = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_vcb_idx);
    X509_STORE_CTX_set_ex_data(ctx, ossl_verify_cb_idx, (void*)cb);
    return ossl_verify_cb(preverify_ok, ctx);
}

static VALUE
ossl_call_session_get_cb(VALUE ary)
{
    VALUE ssl_obj, sslctx_obj, cb;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    sslctx_obj = rb_iv_get(ssl_obj, "@context");
    if (NIL_P(sslctx_obj)) return Qnil;
    cb = rb_iv_get(sslctx_obj, "@session_get_cb");
    if (NIL_P(cb)) return Qnil;

    return rb_funcall(cb, rb_intern("call"), 1, ary);
}

/* this method is currently only called for servers (in OpenSSL <= 0.9.8e) */
static SSL_SESSION *
ossl_sslctx_session_get_cb(SSL *ssl, unsigned char *buf, int len, int *copy)
{
    VALUE ary, ssl_obj, ret_obj;
    SSL_SESSION *sess;
    void *ptr;
    int state = 0;

    OSSL_Debug("SSL SESSION get callback entered");
    if ((ptr = SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx)) == NULL)
    	return NULL;
    ssl_obj = (VALUE)ptr;
    ary = rb_ary_new2(2);
    rb_ary_push(ary, ssl_obj);
    rb_ary_push(ary, rb_str_new((const char *)buf, len));

    ret_obj = rb_protect((VALUE(*)_((VALUE)))ossl_call_session_get_cb, ary, &state);
    if (state) {
        rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(state));
        return NULL;
    }
    if (!rb_obj_is_instance_of(ret_obj, cSSLSession))
        return NULL;

    SafeGetSSLSession(ret_obj, sess);
    *copy = 1;

    return sess;
}

static VALUE
ossl_call_session_new_cb(VALUE ary)
{
    VALUE ssl_obj, sslctx_obj, cb;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    sslctx_obj = rb_iv_get(ssl_obj, "@context");
    if (NIL_P(sslctx_obj)) return Qnil;
    cb = rb_iv_get(sslctx_obj, "@session_new_cb");
    if (NIL_P(cb)) return Qnil;

    return rb_funcall(cb, rb_intern("call"), 1, ary);
}

/* return 1 normal.  return 0 removes the session */
static int
ossl_sslctx_session_new_cb(SSL *ssl, SSL_SESSION *sess)
{
    VALUE ary, ssl_obj, sess_obj, ret_obj;
    void *ptr;
    int state = 0;

    OSSL_Debug("SSL SESSION new callback entered");

    if ((ptr = SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx)) == NULL)
    	return 1;
    ssl_obj = (VALUE)ptr;
    sess_obj = rb_obj_alloc(cSSLSession);
    CRYPTO_add(&sess->references, 1, CRYPTO_LOCK_SSL_SESSION);
    DATA_PTR(sess_obj) = sess;

    ary = rb_ary_new2(2);
    rb_ary_push(ary, ssl_obj);
    rb_ary_push(ary, sess_obj);

    ret_obj = rb_protect((VALUE(*)_((VALUE)))ossl_call_session_new_cb, ary, &state);
    if (state) {
        rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(state));
        return 0; /* what should be returned here??? */
    }

    return RTEST(ret_obj) ? 1 : 0;
}

#if 0				/* unused */
static VALUE
ossl_call_session_remove_cb(VALUE ary)
{
    VALUE sslctx_obj, cb;

    Check_Type(ary, T_ARRAY);
    sslctx_obj = rb_ary_entry(ary, 0);

    cb = rb_iv_get(sslctx_obj, "@session_remove_cb");
    if (NIL_P(cb)) return Qnil;

    return rb_funcall(cb, rb_intern("call"), 1, ary);
}
#endif

static void
ossl_sslctx_session_remove_cb(SSL_CTX *ctx, SSL_SESSION *sess)
{
    VALUE ary, sslctx_obj, sess_obj, ret_obj;
    void *ptr;
    int state = 0;

    OSSL_Debug("SSL SESSION remove callback entered");

    if ((ptr = SSL_CTX_get_ex_data(ctx, ossl_ssl_ex_ptr_idx)) == NULL)
    	return;
    sslctx_obj = (VALUE)ptr;
    sess_obj = rb_obj_alloc(cSSLSession);
    CRYPTO_add(&sess->references, 1, CRYPTO_LOCK_SSL_SESSION);
    DATA_PTR(sess_obj) = sess;

    ary = rb_ary_new2(2);
    rb_ary_push(ary, sslctx_obj);
    rb_ary_push(ary, sess_obj);

    ret_obj = rb_protect((VALUE(*)_((VALUE)))ossl_call_session_new_cb, ary, &state);
    if (state) {
/*
  the SSL_CTX is frozen, nowhere to save state.
  there is no common accessor method to check it either.
        rb_ivar_set(sslctx_obj, ID_callback_state, INT2NUM(state));
*/
    }
}

static VALUE
ossl_sslctx_add_extra_chain_cert_i(VALUE i, VALUE arg)
{
    X509 *x509;
    SSL_CTX *ctx;

    Data_Get_Struct(arg, SSL_CTX, ctx);
    x509 = DupX509CertPtr(i);
    if(!SSL_CTX_add_extra_chain_cert(ctx, x509)){
	ossl_raise(eSSLError, NULL);
    }

    return i;
}

static VALUE ossl_sslctx_setup(VALUE self);

#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
static VALUE
ossl_call_servername_cb(VALUE ary)
{
    VALUE ssl_obj, sslctx_obj, cb, ret_obj;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    sslctx_obj = rb_iv_get(ssl_obj, "@context");
    if (NIL_P(sslctx_obj)) return Qnil;
    cb = rb_iv_get(sslctx_obj, "@servername_cb");
    if (NIL_P(cb)) return Qnil;

    ret_obj = rb_funcall(cb, rb_intern("call"), 1, ary);
    if (rb_obj_is_kind_of(ret_obj, cSSLContext)) {
        SSL *ssl;
        SSL_CTX *ctx2;

        ossl_sslctx_setup(ret_obj);
        Data_Get_Struct(ssl_obj, SSL, ssl);
        Data_Get_Struct(ret_obj, SSL_CTX, ctx2);
        SSL_set_SSL_CTX(ssl, ctx2);
    } else if (!NIL_P(ret_obj)) {
            rb_raise(rb_eArgError, "servername_cb must return an OpenSSL::SSL::SSLContext object or nil");
    }

    return ret_obj;
}

static int
ssl_servername_cb(SSL *ssl, int *ad, void *arg)
{
    VALUE ary, ssl_obj, ret_obj;
    void *ptr;
    int state = 0;
    const char *servername = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);

    if (!servername)
        return SSL_TLSEXT_ERR_OK;

    if ((ptr = SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx)) == NULL)
    	return SSL_TLSEXT_ERR_ALERT_FATAL;
    ssl_obj = (VALUE)ptr;
    ary = rb_ary_new2(2);
    rb_ary_push(ary, ssl_obj);
    rb_ary_push(ary, rb_str_new2(servername));

    ret_obj = rb_protect((VALUE(*)_((VALUE)))ossl_call_servername_cb, ary, &state);
    if (state) {
        rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(state));
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    }

    return SSL_TLSEXT_ERR_OK;
}
#endif

/*
 * call-seq:
 *    ctx.setup => Qtrue # first time
 *    ctx.setup => nil # thereafter
 *
 * This method is called automatically when a new SSLSocket is created.
 * Normally you do not need to call this method (unless you are writing an extension in C).
 */
static VALUE
ossl_sslctx_setup(VALUE self)
{
    SSL_CTX *ctx;
    X509 *cert = NULL, *client_ca = NULL;
    X509_STORE *store;
    EVP_PKEY *key = NULL;
    char *ca_path = NULL, *ca_file = NULL;
    int i, verify_mode;
    VALUE val;

    if(OBJ_FROZEN(self)) return Qnil;
    Data_Get_Struct(self, SSL_CTX, ctx);

#if !defined(OPENSSL_NO_DH)
    if (RTEST(ossl_sslctx_get_tmp_dh_cb(self))){
	SSL_CTX_set_tmp_dh_callback(ctx, ossl_tmp_dh_callback);
    }
    else{
	SSL_CTX_set_tmp_dh_callback(ctx, ossl_default_tmp_dh_callback);
    }
#endif
    SSL_CTX_set_ex_data(ctx, ossl_ssl_ex_ptr_idx, (void*)self);

    val = ossl_sslctx_get_cert_store(self);
    if(!NIL_P(val)){
	/*
         * WORKAROUND:
	 *   X509_STORE can count references, but
	 *   X509_STORE_free() doesn't care it.
	 *   So we won't increment it but mark it by ex_data.
	 */
        store = GetX509StorePtr(val); /* NO NEED TO DUP */
        SSL_CTX_set_cert_store(ctx, store);
        SSL_CTX_set_ex_data(ctx, ossl_ssl_ex_store_p, (void*)1);
    }

    val = ossl_sslctx_get_extra_cert(self);
    if(!NIL_P(val)){
	rb_block_call(val, rb_intern("each"), 0, 0, ossl_sslctx_add_extra_chain_cert_i, self);
    }

    /* private key may be bundled in certificate file. */
    val = ossl_sslctx_get_cert(self);
    cert = NIL_P(val) ? NULL : GetX509CertPtr(val); /* NO DUP NEEDED */
    val = ossl_sslctx_get_key(self);
    key = NIL_P(val) ? NULL : GetPKeyPtr(val); /* NO DUP NEEDED */
    if (cert && key) {
        if (!SSL_CTX_use_certificate(ctx, cert)) {
            /* Adds a ref => Safe to FREE */
            ossl_raise(eSSLError, "SSL_CTX_use_certificate:");
        }
        if (!SSL_CTX_use_PrivateKey(ctx, key)) {
            /* Adds a ref => Safe to FREE */
            ossl_raise(eSSLError, "SSL_CTX_use_PrivateKey:");
        }
        if (!SSL_CTX_check_private_key(ctx)) {
            ossl_raise(eSSLError, "SSL_CTX_check_private_key:");
        }
    }

    val = ossl_sslctx_get_client_ca(self);
    if(!NIL_P(val)){
	if(TYPE(val) == T_ARRAY){
	    for(i = 0; i < RARRAY_LEN(val); i++){
		client_ca = GetX509CertPtr(RARRAY_PTR(val)[i]);
        	if (!SSL_CTX_add_client_CA(ctx, client_ca)){
		    /* Copies X509_NAME => FREE it. */
        	    ossl_raise(eSSLError, "SSL_CTX_add_client_CA");
        	}
	    }
        }
	else{
	    client_ca = GetX509CertPtr(val); /* NO DUP NEEDED. */
            if (!SSL_CTX_add_client_CA(ctx, client_ca)){
		/* Copies X509_NAME => FREE it. */
        	ossl_raise(eSSLError, "SSL_CTX_add_client_CA");
            }
	}
    }

    val = ossl_sslctx_get_ca_file(self);
    ca_file = NIL_P(val) ? NULL : StringValuePtr(val);
    val = ossl_sslctx_get_ca_path(self);
    ca_path = NIL_P(val) ? NULL : StringValuePtr(val);
    if(ca_file || ca_path){
	if (!SSL_CTX_load_verify_locations(ctx, ca_file, ca_path))
	    rb_warning("can't set verify locations");
    }

    val = ossl_sslctx_get_verify_mode(self);
    verify_mode = NIL_P(val) ? SSL_VERIFY_NONE : NUM2INT(val);
    SSL_CTX_set_verify(ctx, verify_mode, ossl_ssl_verify_callback);
    if (RTEST(ossl_sslctx_get_client_cert_cb(self)))
	SSL_CTX_set_client_cert_cb(ctx, ossl_client_cert_cb);

    val = ossl_sslctx_get_timeout(self);
    if(!NIL_P(val)) SSL_CTX_set_timeout(ctx, NUM2LONG(val));

    val = ossl_sslctx_get_verify_dep(self);
    if(!NIL_P(val)) SSL_CTX_set_verify_depth(ctx, NUM2LONG(val));

    val = ossl_sslctx_get_options(self);
    if(!NIL_P(val)) SSL_CTX_set_options(ctx, NUM2LONG(val));
    rb_obj_freeze(self);

    val = ossl_sslctx_get_sess_id_ctx(self);
    if (!NIL_P(val)){
	StringValue(val);
	if (!SSL_CTX_set_session_id_context(ctx, (unsigned char *)RSTRING_PTR(val),
					    RSTRING_LEN(val))){
	    ossl_raise(eSSLError, "SSL_CTX_set_session_id_context:");
	}
    }

    if (RTEST(rb_iv_get(self, "@session_get_cb"))) {
	SSL_CTX_sess_set_get_cb(ctx, ossl_sslctx_session_get_cb);
	OSSL_Debug("SSL SESSION get callback added");
    }
    if (RTEST(rb_iv_get(self, "@session_new_cb"))) {
	SSL_CTX_sess_set_new_cb(ctx, ossl_sslctx_session_new_cb);
	OSSL_Debug("SSL SESSION new callback added");
    }
    if (RTEST(rb_iv_get(self, "@session_remove_cb"))) {
	SSL_CTX_sess_set_remove_cb(ctx, ossl_sslctx_session_remove_cb);
	OSSL_Debug("SSL SESSION remove callback added");
    }

#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
    val = rb_iv_get(self, "@servername_cb");
    if (!NIL_P(val)) {
        SSL_CTX_set_tlsext_servername_callback(ctx, ssl_servername_cb);
	OSSL_Debug("SSL TLSEXT servername callback added");
    }
#endif

    return Qtrue;
}

static VALUE
ossl_ssl_cipher_to_ary(SSL_CIPHER *cipher)
{
    VALUE ary;
    int bits, alg_bits;

    ary = rb_ary_new2(4);
    rb_ary_push(ary, rb_str_new2(SSL_CIPHER_get_name(cipher)));
    rb_ary_push(ary, rb_str_new2(SSL_CIPHER_get_version(cipher)));
    bits = SSL_CIPHER_get_bits(cipher, &alg_bits);
    rb_ary_push(ary, INT2FIX(bits));
    rb_ary_push(ary, INT2FIX(alg_bits));

    return ary;
}

/*
 * call-seq:
 *    ctx.ciphers => [[name, version, bits, alg_bits], ...]
 */
static VALUE
ossl_sslctx_get_ciphers(VALUE self)
{
    SSL_CTX *ctx;
    STACK_OF(SSL_CIPHER) *ciphers;
    SSL_CIPHER *cipher;
    VALUE ary;
    int i, num;

    Data_Get_Struct(self, SSL_CTX, ctx);
    if(!ctx){
        rb_warning("SSL_CTX is not initialized.");
        return Qnil;
    }
    ciphers = ctx->cipher_list;

    if (!ciphers)
        return rb_ary_new();

    num = sk_num((STACK*)ciphers);
    ary = rb_ary_new2(num);
    for(i = 0; i < num; i++){
        cipher = (SSL_CIPHER*)sk_value((STACK*)ciphers, i);
        rb_ary_push(ary, ossl_ssl_cipher_to_ary(cipher));
    }
    return ary;
}

/*
 * call-seq:
 *    ctx.ciphers = "cipher1:cipher2:..."
 *    ctx.ciphers = [name, ...]
 *    ctx.ciphers = [[name, version, bits, alg_bits], ...]
 */
static VALUE
ossl_sslctx_set_ciphers(VALUE self, VALUE v)
{
    SSL_CTX *ctx;
    VALUE str, elem;
    int i;

    rb_check_frozen(self);
    if (NIL_P(v))
	return v;
    else if (TYPE(v) == T_ARRAY) {
        str = rb_str_new(0, 0);
        for (i = 0; i < RARRAY_LEN(v); i++) {
            elem = rb_ary_entry(v, i);
            if (TYPE(elem) == T_ARRAY) elem = rb_ary_entry(elem, 0);
            elem = rb_String(elem);
            rb_str_append(str, elem);
            if (i < RARRAY_LEN(v)-1) rb_str_cat2(str, ":");
        }
    } else {
        str = v;
        StringValue(str);
    }

    Data_Get_Struct(self, SSL_CTX, ctx);
    if(!ctx){
        ossl_raise(eSSLError, "SSL_CTX is not initialized.");
        return Qnil;
    }
    if (!SSL_CTX_set_cipher_list(ctx, RSTRING_PTR(str))) {
        ossl_raise(eSSLError, "SSL_CTX_set_cipher_list:");
    }

    return v;
}


/*
 *  call-seq:
 *     ctx.session_add(session) -> true | false
 *
 */
static VALUE
ossl_sslctx_session_add(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;
    SSL_SESSION *sess;

    Data_Get_Struct(self, SSL_CTX, ctx);
    SafeGetSSLSession(arg, sess);

    return SSL_CTX_add_session(ctx, sess) == 1 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     ctx.session_remove(session) -> true | false
 *
 */
static VALUE
ossl_sslctx_session_remove(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;
    SSL_SESSION *sess;

    Data_Get_Struct(self, SSL_CTX, ctx);
    SafeGetSSLSession(arg, sess);

    return SSL_CTX_remove_session(ctx, sess) == 1 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     ctx.session_cache_mode -> integer
 *
 */
static VALUE
ossl_sslctx_get_session_cache_mode(VALUE self)
{
    SSL_CTX *ctx;

    Data_Get_Struct(self, SSL_CTX, ctx);

    return LONG2NUM(SSL_CTX_get_session_cache_mode(ctx));
}

/*
 *  call-seq:
 *     ctx.session_cache_mode=(integer) -> integer
 *
 */
static VALUE
ossl_sslctx_set_session_cache_mode(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;

    Data_Get_Struct(self, SSL_CTX, ctx);

    SSL_CTX_set_session_cache_mode(ctx, NUM2LONG(arg));

    return arg;
}

/*
 *  call-seq:
 *     ctx.session_cache_size -> integer
 *
 */
static VALUE
ossl_sslctx_get_session_cache_size(VALUE self)
{
    SSL_CTX *ctx;

    Data_Get_Struct(self, SSL_CTX, ctx);

    return LONG2NUM(SSL_CTX_sess_get_cache_size(ctx));
}

/*
 *  call-seq:
 *     ctx.session_cache_size=(integer) -> integer
 *
 */
static VALUE
ossl_sslctx_set_session_cache_size(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;

    Data_Get_Struct(self, SSL_CTX, ctx);

    SSL_CTX_sess_set_cache_size(ctx, NUM2LONG(arg));

    return arg;
}

/*
 *  call-seq:
 *     ctx.session_cache_stats -> Hash
 *
 */
static VALUE
ossl_sslctx_get_session_cache_stats(VALUE self)
{
    SSL_CTX *ctx;
    VALUE hash;

    Data_Get_Struct(self, SSL_CTX, ctx);

    hash = rb_hash_new();
    rb_hash_aset(hash, ID2SYM(rb_intern("cache_num")), LONG2NUM(SSL_CTX_sess_number(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("connect")), LONG2NUM(SSL_CTX_sess_connect(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("connect_good")), LONG2NUM(SSL_CTX_sess_connect_good(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("connect_renegotiate")), LONG2NUM(SSL_CTX_sess_connect_renegotiate(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("accept")), LONG2NUM(SSL_CTX_sess_accept(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("accept_good")), LONG2NUM(SSL_CTX_sess_accept_good(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("accept_renegotiate")), LONG2NUM(SSL_CTX_sess_accept_renegotiate(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("cache_hits")), LONG2NUM(SSL_CTX_sess_hits(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("cb_hits")), LONG2NUM(SSL_CTX_sess_cb_hits(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("cache_misses")), LONG2NUM(SSL_CTX_sess_misses(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("cache_full")), LONG2NUM(SSL_CTX_sess_cache_full(ctx)));
    rb_hash_aset(hash, ID2SYM(rb_intern("timeouts")), LONG2NUM(SSL_CTX_sess_timeouts(ctx)));

    return hash;
}


/*
 *  call-seq:
 *     ctx.flush_sessions(time | nil) -> self
 *
 */
static VALUE
ossl_sslctx_flush_sessions(int argc, VALUE *argv, VALUE self)
{
    VALUE arg1;
    SSL_CTX *ctx;
    time_t tm = 0;

    rb_scan_args(argc, argv, "01", &arg1);

    Data_Get_Struct(self, SSL_CTX, ctx);

    if (NIL_P(arg1)) {
        tm = time(0);
    } else if (rb_obj_is_instance_of(arg1, rb_cTime)) {
        tm = NUM2LONG(rb_funcall(arg1, rb_intern("to_i"), 0));
    } else {
        rb_raise(rb_eArgError, "arg must be Time or nil");
    }

    SSL_CTX_flush_sessions(ctx, (long)tm);

    return self;
}

/*
 * SSLSocket class
 */
static void
ossl_ssl_shutdown(SSL *ssl)
{
    if (ssl) {
        SSL_shutdown(ssl);
        SSL_clear(ssl);
    }
}

static void
ossl_ssl_free(SSL *ssl)
{
    ossl_ssl_shutdown(ssl);
    SSL_free(ssl);
}

static VALUE
ossl_ssl_s_alloc(VALUE klass)
{
    return Data_Wrap_Struct(klass, 0, ossl_ssl_free, NULL);
}

/*
 * call-seq:
 *    SSLSocket.new(io) => aSSLSocket
 *    SSLSocket.new(io, ctx) => aSSLSocket
 *
 * === Parameters
 * * +io+ is a real ruby IO object.  Not an IO like object that responds to read/write.
 * * +ctx+ is an OpenSSLSSL::SSLContext.
 *
 * The OpenSSL::Buffering module provides additional IO methods.
 *
 * This method will freeze the SSLContext if one is provided;
 * however, session management is still allowed in the frozen SSLContext.
 */
static VALUE
ossl_ssl_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE io, ctx;

    if (rb_scan_args(argc, argv, "11", &io, &ctx) == 1) {
        ctx = rb_funcall(cSSLContext, rb_intern("new"), 0);
    }
    OSSL_Check_Kind(ctx, cSSLContext);
    Check_Type(io, T_FILE);
    ossl_ssl_set_io(self, io);
    ossl_ssl_set_ctx(self, ctx);
    ossl_ssl_set_sync_close(self, Qfalse);
    ossl_sslctx_setup(ctx);

    rb_iv_set(self, "@hostname", Qnil);

    rb_call_super(0, 0);

    return self;
}

static VALUE
ossl_ssl_setup(VALUE self)
{
    VALUE io, v_ctx, cb;
    SSL_CTX *ctx;
    SSL *ssl;
    rb_io_t *fptr;

    Data_Get_Struct(self, SSL, ssl);
    if(!ssl){
#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
	VALUE hostname = rb_iv_get(self, "@hostname");
#endif

        v_ctx = ossl_ssl_get_ctx(self);
        Data_Get_Struct(v_ctx, SSL_CTX, ctx);

        ssl = SSL_new(ctx);
        if (!ssl) {
            ossl_raise(eSSLError, "SSL_new:");
        }
        DATA_PTR(self) = ssl;

#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
        if (!NIL_P(hostname)) {
           if (SSL_set_tlsext_host_name(ssl, StringValuePtr(hostname)) != 1)
               ossl_raise(eSSLError, "SSL_set_tlsext_host_name:");
        }
#endif
        io = ossl_ssl_get_io(self);
        GetOpenFile(io, fptr);
        rb_io_check_readable(fptr);
        rb_io_check_writable(fptr);
        SSL_set_fd(ssl, TO_SOCKET(FPTR_TO_FD(fptr)));
	SSL_set_ex_data(ssl, ossl_ssl_ex_ptr_idx, (void*)self);
	cb = ossl_sslctx_get_verify_cb(v_ctx);
	SSL_set_ex_data(ssl, ossl_ssl_ex_vcb_idx, (void*)cb);
	cb = ossl_sslctx_get_client_cert_cb(v_ctx);
	SSL_set_ex_data(ssl, ossl_ssl_ex_client_cert_cb_idx, (void*)cb);
	cb = ossl_sslctx_get_tmp_dh_cb(v_ctx);
	SSL_set_ex_data(ssl, ossl_ssl_ex_tmp_dh_callback_idx, (void*)cb);
    }

    return Qtrue;
}

#ifdef _WIN32
#define ssl_get_error(ssl, ret) (errno = WSAGetLastError(), SSL_get_error(ssl, ret))
#else
#define ssl_get_error(ssl, ret) SSL_get_error(ssl, ret)
#endif

static void
write_would_block(int nonblock)
{
    if (nonblock) {
        VALUE exc = ossl_exc_new(eSSLError, "write would block");
        rb_extend_object(exc, rb_mWaitWritable);
        rb_exc_raise(exc);
    }
}

static void
read_would_block(int nonblock)
{
    if (nonblock) {
        VALUE exc = ossl_exc_new(eSSLError, "read would block");
        rb_extend_object(exc, rb_mWaitReadable);
        rb_exc_raise(exc);
    }
}

static VALUE
ossl_start_ssl(VALUE self, int (*func)(), const char *funcname, int nonblock)
{
    SSL *ssl;
    rb_io_t *fptr;
    int ret, ret2;
    VALUE cb_state;

    rb_ivar_set(self, ID_callback_state, Qnil);

    Data_Get_Struct(self, SSL, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);
    for(;;){
	ret = func(ssl);

        cb_state = rb_ivar_get(self, ID_callback_state);
        if (!NIL_P(cb_state))
            rb_jump_tag(NUM2INT(cb_state));

	if (ret > 0)
	    break;

	switch((ret2 = ssl_get_error(ssl, ret))){
	case SSL_ERROR_WANT_WRITE:
            write_would_block(nonblock);
            rb_io_wait_writable(FPTR_TO_FD(fptr));
            continue;
	case SSL_ERROR_WANT_READ:
            read_would_block(nonblock);
            rb_io_wait_readable(FPTR_TO_FD(fptr));
            continue;
	case SSL_ERROR_SYSCALL:
	    if (errno) rb_sys_fail(funcname);
	    ossl_raise(eSSLError, "%s SYSCALL returned=%d errno=%d state=%s", funcname, ret2, errno, SSL_state_string_long(ssl));
	default:
	    ossl_raise(eSSLError, "%s returned=%d errno=%d state=%s", funcname, ret2, errno, SSL_state_string_long(ssl));
	}
    }

    return self;
}

/*
 * call-seq:
 *    ssl.connect => self
 */
static VALUE
ossl_ssl_connect(VALUE self)
{
    ossl_ssl_setup(self);
    return ossl_start_ssl(self, SSL_connect, "SSL_connect", 0);
}

/*
 * call-seq:
 *    ssl.connect_nonblock => self
 *
 * initiate the TLS/SSL handshake as a client in non-blocking manner.
 *
 *   # emulates blocking connect
 *   begin
 *     ssl.connect_nonblock
 *   rescue IO::WaitReadable
 *     IO.select([s2])
 *     retry
 *   rescue IO::WaitWritable
 *     IO.select(nil, [s2])
 *     retry
 *   end
 *
 */
static VALUE
ossl_ssl_connect_nonblock(VALUE self)
{
    ossl_ssl_setup(self);
    return ossl_start_ssl(self, SSL_connect, "SSL_connect", 1);
}

/*
 * call-seq:
 *    ssl.accept => self
 */
static VALUE
ossl_ssl_accept(VALUE self)
{
    ossl_ssl_setup(self);
    return ossl_start_ssl(self, SSL_accept, "SSL_accept", 0);
}

/*
 * call-seq:
 *    ssl.accept_nonblock => self
 *
 * initiate the TLS/SSL handshake as a server in non-blocking manner.
 *
 *   # emulates blocking accept
 *   begin
 *     ssl.accept_nonblock
 *   rescue IO::WaitReadable
 *     IO.select([s2])
 *     retry
 *   rescue IO::WaitWritable
 *     IO.select(nil, [s2])
 *     retry
 *   end
 *
 */
static VALUE
ossl_ssl_accept_nonblock(VALUE self)
{
    ossl_ssl_setup(self);
    return ossl_start_ssl(self, SSL_accept, "SSL_accept", 1);
}

static VALUE
ossl_ssl_read_internal(int argc, VALUE *argv, VALUE self, int nonblock)
{
    SSL *ssl;
    int ilen, nread = 0;
    VALUE len, str;
    rb_io_t *fptr;

    rb_scan_args(argc, argv, "11", &len, &str);
    ilen = NUM2INT(len);
    if(NIL_P(str)) str = rb_str_new(0, ilen);
    else{
        StringValue(str);
        rb_str_modify(str);
        rb_str_resize(str, ilen);
    }
    if(ilen == 0) return str;

    Data_Get_Struct(self, SSL, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);
    if (ssl) {
	if(!nonblock && SSL_pending(ssl) <= 0)
	    rb_thread_wait_fd(FPTR_TO_FD(fptr));
	for (;;){
	    nread = SSL_read(ssl, RSTRING_PTR(str), RSTRING_LEN(str));
	    switch(ssl_get_error(ssl, nread)){
	    case SSL_ERROR_NONE:
		goto end;
	    case SSL_ERROR_ZERO_RETURN:
		rb_eof_error();
	    case SSL_ERROR_WANT_WRITE:
                write_would_block(nonblock);
                rb_io_wait_writable(FPTR_TO_FD(fptr));
                continue;
	    case SSL_ERROR_WANT_READ:
                read_would_block(nonblock);
                rb_io_wait_readable(FPTR_TO_FD(fptr));
		continue;
	    case SSL_ERROR_SYSCALL:
		if(ERR_peek_error() == 0 && nread == 0) rb_eof_error();
		rb_sys_fail(0);
	    default:
		ossl_raise(eSSLError, "SSL_read:");
	    }
        }
    }
    else {
        ID meth = nonblock ? rb_intern("read_nonblock") : rb_intern("sysread");
        rb_warning("SSL session is not started yet.");
        return rb_funcall(ossl_ssl_get_io(self), meth, 2, len, str);
    }

  end:
    rb_str_set_len(str, nread);
    OBJ_TAINT(str);

    return str;
}


/*
 * call-seq:
 *    ssl.sysread(length) => string
 *    ssl.sysread(length, buffer) => buffer
 *
 * === Parameters
 * * +length+ is a positive integer.
 * * +buffer+ is a string used to store the result.
 */
static VALUE
ossl_ssl_read(int argc, VALUE *argv, VALUE self)
{
    return ossl_ssl_read_internal(argc, argv, self, 0);
}

/*
 * call-seq:
 *    ssl.sysread_nonblock(length) => string
 *    ssl.sysread_nonblock(length, buffer) => buffer
 *
 * === Parameters
 * * +length+ is a positive integer.
 * * +buffer+ is a string used to store the result.
 */
static VALUE
ossl_ssl_read_nonblock(int argc, VALUE *argv, VALUE self)
{
    return ossl_ssl_read_internal(argc, argv, self, 1);
}

static VALUE
ossl_ssl_write_internal(VALUE self, VALUE str, int nonblock)
{
    SSL *ssl;
    int nwrite = 0;
    rb_io_t *fptr;

    StringValue(str);
    Data_Get_Struct(self, SSL, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);

    if (ssl) {
	for (;;){
	    nwrite = SSL_write(ssl, RSTRING_PTR(str), RSTRING_LEN(str));
	    switch(ssl_get_error(ssl, nwrite)){
	    case SSL_ERROR_NONE:
		goto end;
	    case SSL_ERROR_WANT_WRITE:
                write_would_block(nonblock);
                rb_io_wait_writable(FPTR_TO_FD(fptr));
                continue;
	    case SSL_ERROR_WANT_READ:
                read_would_block(nonblock);
                rb_io_wait_readable(FPTR_TO_FD(fptr));
                continue;
	    case SSL_ERROR_SYSCALL:
		if (errno) rb_sys_fail(0);
	    default:
		ossl_raise(eSSLError, "SSL_write:");
	    }
        }
    }
    else {
        ID id_syswrite = rb_intern("syswrite");
        rb_warning("SSL session is not started yet.");
	return rb_funcall(ossl_ssl_get_io(self), id_syswrite, 1, str);
    }

  end:
    return INT2NUM(nwrite);
}

/*
 * call-seq:
 *    ssl.syswrite(string) => integer
 */
static VALUE
ossl_ssl_write(VALUE self, VALUE str)
{
    return ossl_ssl_write_internal(self, str, 0);
}

/*
 * call-seq:
 *    ssl.syswrite_nonblock(string) => integer
 */
static VALUE
ossl_ssl_write_nonblock(VALUE self, VALUE str)
{
    return ossl_ssl_write_internal(self, str, 1);
}

/*
 * call-seq:
 *    ssl.sysclose => nil
 */
static VALUE
ossl_ssl_close(VALUE self)
{
    SSL *ssl;

    Data_Get_Struct(self, SSL, ssl);
    ossl_ssl_shutdown(ssl);
    if (RTEST(ossl_ssl_get_sync_close(self)))
	rb_funcall(ossl_ssl_get_io(self), rb_intern("close"), 0);

    return Qnil;
}

/*
 * call-seq:
 *    ssl.cert => cert or nil
 */
static VALUE
ossl_ssl_get_cert(VALUE self)
{
    SSL *ssl;
    X509 *cert = NULL;

    Data_Get_Struct(self, SSL, ssl);
    if (ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }

    /*
     * Is this OpenSSL bug? Should add a ref?
     * TODO: Ask for.
     */
    cert = SSL_get_certificate(ssl); /* NO DUPs => DON'T FREE. */

    if (!cert) {
        return Qnil;
    }
    return ossl_x509_new(cert);
}

/*
 * call-seq:
 *    ssl.peer_cert => cert or nil
 */
static VALUE
ossl_ssl_get_peer_cert(VALUE self)
{
    SSL *ssl;
    X509 *cert = NULL;
    VALUE obj;

    Data_Get_Struct(self, SSL, ssl);

    if (!ssl){
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }

    cert = SSL_get_peer_certificate(ssl); /* Adds a ref => Safe to FREE. */

    if (!cert) {
        return Qnil;
    }
    obj = ossl_x509_new(cert);
    X509_free(cert);

    return obj;
}

/*
 * call-seq:
 *    ssl.peer_cert_chain => [cert, ...] or nil
 */
static VALUE
ossl_ssl_get_peer_cert_chain(VALUE self)
{
    SSL *ssl;
    STACK_OF(X509) *chain;
    X509 *cert;
    VALUE ary;
    int i, num;

    Data_Get_Struct(self, SSL, ssl);
    if(!ssl){
	rb_warning("SSL session is not started yet.");
	return Qnil;
    }
    chain = SSL_get_peer_cert_chain(ssl);
    if(!chain) return Qnil;
    num = sk_X509_num(chain);
    ary = rb_ary_new2(num);
    for (i = 0; i < num; i++){
	cert = sk_X509_value(chain, i);
	rb_ary_push(ary, ossl_x509_new(cert));
    }

    return ary;
}

/*
 * call-seq:
 *    ssl.cipher => [name, version, bits, alg_bits]
 */
static VALUE
ossl_ssl_get_cipher(VALUE self)
{
    SSL *ssl;
    SSL_CIPHER *cipher;

    Data_Get_Struct(self, SSL, ssl);
    if (!ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }
    cipher = SSL_get_current_cipher(ssl);

    return ossl_ssl_cipher_to_ary(cipher);
}

/*
 * call-seq:
 *    ssl.state => string
 */
static VALUE
ossl_ssl_get_state(VALUE self)
{
    SSL *ssl;
    VALUE ret;

    Data_Get_Struct(self, SSL, ssl);
    if (!ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }
    ret = rb_str_new2(SSL_state_string(ssl));
    if (ruby_verbose) {
        rb_str_cat2(ret, ": ");
        rb_str_cat2(ret, SSL_state_string_long(ssl));
    }
    return ret;
}

/*
 * call-seq:
 *    ssl.pending => integer
 */
static VALUE
ossl_ssl_pending(VALUE self)
{
    SSL *ssl;

    Data_Get_Struct(self, SSL, ssl);
    if (!ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }

    return INT2NUM(SSL_pending(ssl));
}

/*
 *  call-seq:
 *     ssl.session_reused? -> true | false
 *
 */
static VALUE
ossl_ssl_session_reused(VALUE self)
{
    SSL *ssl;

    Data_Get_Struct(self, SSL, ssl);
    if (!ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }

    switch(SSL_session_reused(ssl)) {
    case 1:	return Qtrue;
    case 0:	return Qfalse;
    default:	ossl_raise(eSSLError, "SSL_session_reused");
    }
}

/*
 *  call-seq:
 *     ssl.session = session -> session
 *
 */
static VALUE
ossl_ssl_set_session(VALUE self, VALUE arg1)
{
    SSL *ssl;
    SSL_SESSION *sess;

/* why is ossl_ssl_setup delayed? */
    ossl_ssl_setup(self);

    Data_Get_Struct(self, SSL, ssl);
    if (!ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }

    SafeGetSSLSession(arg1, sess);

    if (SSL_set_session(ssl, sess) != 1)
        ossl_raise(eSSLError, "SSL_set_session");

    return arg1;
}

static VALUE
ossl_ssl_get_verify_result(VALUE self)
{
    SSL *ssl;

    Data_Get_Struct(self, SSL, ssl);
    if (!ssl) {
        rb_warning("SSL session is not started yet.");
        return Qnil;
    }

    return INT2FIX(SSL_get_verify_result(ssl));
}

void
Init_ossl_ssl()
{
    int i;
    VALUE ary;

#if 0 /* let rdoc know about mOSSL */
    mOSSL = rb_define_module("OpenSSL");
#endif

    ID_callback_state = rb_intern("@callback_state");

    ossl_ssl_ex_vcb_idx = SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_vcb_idx",0,0,0);
    ossl_ssl_ex_store_p = SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_store_p",0,0,0);
    ossl_ssl_ex_ptr_idx = SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_ptr_idx",0,0,0);
    ossl_ssl_ex_client_cert_cb_idx =
	SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_client_cert_cb_idx",0,0,0);
    ossl_ssl_ex_tmp_dh_callback_idx =
	SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_tmp_dh_callback_idx",0,0,0);

    mSSL = rb_define_module_under(mOSSL, "SSL");
    eSSLError = rb_define_class_under(mSSL, "SSLError", eOSSLError);

    Init_ossl_ssl_session();

    /* class SSLContext
     *
     * The following attributes are available but don't show up in rdoc.
     * All attributes must be set before calling SSLSocket.new(io, ctx).
     * * ssl_version, cert, key, client_ca, ca_file, ca_path, timeout,
     * * verify_mode, verify_depth client_cert_cb, tmp_dh_callback,
     * * session_id_context, session_add_cb, session_new_cb, session_remove_cb
     */
    cSSLContext = rb_define_class_under(mSSL, "SSLContext", rb_cObject);
    rb_define_alloc_func(cSSLContext, ossl_sslctx_s_alloc);
    for(i = 0; i < numberof(ossl_sslctx_attrs); i++)
        rb_attr(cSSLContext, rb_intern(ossl_sslctx_attrs[i]), 1, 1, Qfalse);
    rb_define_alias(cSSLContext, "ssl_timeout", "timeout");
    rb_define_alias(cSSLContext, "ssl_timeout=", "timeout=");
    rb_define_method(cSSLContext, "initialize",  ossl_sslctx_initialize, -1);
    rb_define_method(cSSLContext, "ssl_version=", ossl_sslctx_set_ssl_version, 1);
    rb_define_method(cSSLContext, "ciphers",     ossl_sslctx_get_ciphers, 0);
    rb_define_method(cSSLContext, "ciphers=",    ossl_sslctx_set_ciphers, 1);

    rb_define_method(cSSLContext, "setup", ossl_sslctx_setup, 0);


    rb_define_const(cSSLContext, "SESSION_CACHE_OFF", LONG2FIX(SSL_SESS_CACHE_OFF));
    rb_define_const(cSSLContext, "SESSION_CACHE_CLIENT", LONG2FIX(SSL_SESS_CACHE_CLIENT)); /* doesn't actually do anything in 0.9.8e */
    rb_define_const(cSSLContext, "SESSION_CACHE_SERVER", LONG2FIX(SSL_SESS_CACHE_SERVER));
    rb_define_const(cSSLContext, "SESSION_CACHE_BOTH", LONG2FIX(SSL_SESS_CACHE_BOTH)); /* no different than CACHE_SERVER in 0.9.8e */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_AUTO_CLEAR", LONG2FIX(SSL_SESS_CACHE_NO_AUTO_CLEAR));
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL_LOOKUP", LONG2FIX(SSL_SESS_CACHE_NO_INTERNAL_LOOKUP));
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL_STORE", LONG2FIX(SSL_SESS_CACHE_NO_INTERNAL_STORE));
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL", LONG2FIX(SSL_SESS_CACHE_NO_INTERNAL));
    rb_define_method(cSSLContext, "session_add",     ossl_sslctx_session_add, 1);
    rb_define_method(cSSLContext, "session_remove",     ossl_sslctx_session_remove, 1);
    rb_define_method(cSSLContext, "session_cache_mode",     ossl_sslctx_get_session_cache_mode, 0);
    rb_define_method(cSSLContext, "session_cache_mode=",     ossl_sslctx_set_session_cache_mode, 1);
    rb_define_method(cSSLContext, "session_cache_size",     ossl_sslctx_get_session_cache_size, 0);
    rb_define_method(cSSLContext, "session_cache_size=",     ossl_sslctx_set_session_cache_size, 1);
    rb_define_method(cSSLContext, "session_cache_stats",     ossl_sslctx_get_session_cache_stats, 0);
    rb_define_method(cSSLContext, "flush_sessions",     ossl_sslctx_flush_sessions, -1);

    ary = rb_ary_new2(numberof(ossl_ssl_method_tab));
    for (i = 0; i < numberof(ossl_ssl_method_tab); i++) {
        rb_ary_push(ary, ID2SYM(rb_intern(ossl_ssl_method_tab[i].name)));
    }
    rb_obj_freeze(ary);
    /* holds a list of available SSL/TLS methods */
    rb_define_const(cSSLContext, "METHODS", ary);

    /* class SSLSocket
     *
     * The following attributes are available but don't show up in rdoc.
     * * io, context, sync_close
     *
     */
    cSSLSocket = rb_define_class_under(mSSL, "SSLSocket", rb_cObject);
    rb_define_alloc_func(cSSLSocket, ossl_ssl_s_alloc);
    for(i = 0; i < numberof(ossl_ssl_attr_readers); i++)
        rb_attr(cSSLSocket, rb_intern(ossl_ssl_attr_readers[i]), 1, 0, Qfalse);
    for(i = 0; i < numberof(ossl_ssl_attrs); i++)
        rb_attr(cSSLSocket, rb_intern(ossl_ssl_attrs[i]), 1, 1, Qfalse);
    rb_define_alias(cSSLSocket, "to_io", "io");
    rb_define_method(cSSLSocket, "initialize", ossl_ssl_initialize, -1);
    rb_define_method(cSSLSocket, "connect",    ossl_ssl_connect, 0);
    rb_define_method(cSSLSocket, "connect_nonblock",    ossl_ssl_connect_nonblock, 0);
    rb_define_method(cSSLSocket, "accept",     ossl_ssl_accept, 0);
    rb_define_method(cSSLSocket, "accept_nonblock",     ossl_ssl_accept_nonblock, 0);
    rb_define_method(cSSLSocket, "sysread",    ossl_ssl_read, -1);
    rb_define_private_method(cSSLSocket, "sysread_nonblock",    ossl_ssl_read_nonblock, -1);
    rb_define_method(cSSLSocket, "syswrite",   ossl_ssl_write, 1);
    rb_define_private_method(cSSLSocket, "syswrite_nonblock",    ossl_ssl_write_nonblock, 1);
    rb_define_method(cSSLSocket, "sysclose",   ossl_ssl_close, 0);
    rb_define_method(cSSLSocket, "cert",       ossl_ssl_get_cert, 0);
    rb_define_method(cSSLSocket, "peer_cert",  ossl_ssl_get_peer_cert, 0);
    rb_define_method(cSSLSocket, "peer_cert_chain", ossl_ssl_get_peer_cert_chain, 0);
    rb_define_method(cSSLSocket, "cipher",     ossl_ssl_get_cipher, 0);
    rb_define_method(cSSLSocket, "state",      ossl_ssl_get_state, 0);
    rb_define_method(cSSLSocket, "pending",    ossl_ssl_pending, 0);
    rb_define_method(cSSLSocket, "session_reused?",    ossl_ssl_session_reused, 0);
    rb_define_method(cSSLSocket, "session=",    ossl_ssl_set_session, 1);
    rb_define_method(cSSLSocket, "verify_result", ossl_ssl_get_verify_result, 0);

#define ossl_ssl_def_const(x) rb_define_const(mSSL, #x, INT2NUM(SSL_##x))

    ossl_ssl_def_const(VERIFY_NONE);
    ossl_ssl_def_const(VERIFY_PEER);
    ossl_ssl_def_const(VERIFY_FAIL_IF_NO_PEER_CERT);
    ossl_ssl_def_const(VERIFY_CLIENT_ONCE);
    /* Not introduce constants included in OP_ALL such as...
     * ossl_ssl_def_const(OP_MICROSOFT_SESS_ID_BUG);
     * ossl_ssl_def_const(OP_NETSCAPE_CHALLENGE_BUG);
     * ossl_ssl_def_const(OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG);
     * ossl_ssl_def_const(OP_SSLREF2_REUSE_CERT_TYPE_BUG);
     * ossl_ssl_def_const(OP_MICROSOFT_BIG_SSLV3_BUFFER);
     * ossl_ssl_def_const(OP_MSIE_SSLV2_RSA_PADDING);
     * ossl_ssl_def_const(OP_SSLEAY_080_CLIENT_DH_BUG);
     * ossl_ssl_def_const(OP_TLS_D5_BUG);
     * ossl_ssl_def_const(OP_TLS_BLOCK_PADDING_BUG);
     * ossl_ssl_def_const(OP_DONT_INSERT_EMPTY_FRAGMENTS);
     */
    ossl_ssl_def_const(OP_ALL);
#if defined(SSL_OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION)
    ossl_ssl_def_const(OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION);
#endif
#if defined(SSL_OP_SINGLE_ECDH_USE)
    ossl_ssl_def_const(OP_SINGLE_ECDH_USE);
#endif
    ossl_ssl_def_const(OP_SINGLE_DH_USE);
    ossl_ssl_def_const(OP_EPHEMERAL_RSA);
#if defined(SSL_OP_CIPHER_SERVER_PREFERENCE)
    ossl_ssl_def_const(OP_CIPHER_SERVER_PREFERENCE);
#endif
    ossl_ssl_def_const(OP_TLS_ROLLBACK_BUG);
    ossl_ssl_def_const(OP_NO_SSLv2);
    ossl_ssl_def_const(OP_NO_SSLv3);
    ossl_ssl_def_const(OP_NO_TLSv1);
#if defined(SSL_OP_NO_TICKET)
    ossl_ssl_def_const(OP_NO_TICKET);
#endif
    ossl_ssl_def_const(OP_PKCS1_CHECK_1);
    ossl_ssl_def_const(OP_PKCS1_CHECK_2);
    ossl_ssl_def_const(OP_NETSCAPE_CA_DN_BUG);
    ossl_ssl_def_const(OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG);
}
