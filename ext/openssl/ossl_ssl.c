/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2000-2002  GOTOU Yuuzou <gotoyuzo@notwork.org>
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * Copyright (C) 2001-2007  Technorama Ltd. <oss-ruby@technorama.net>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if defined(HAVE_UNISTD_H)
#  include <unistd.h> /* for read(), and write() */
#endif

#define numberof(ary) (int)(sizeof(ary)/sizeof((ary)[0]))

#ifdef _WIN32
#  define TO_SOCKET(s) _get_osfhandle(s)
#else
#  define TO_SOCKET(s) (s)
#endif

#define GetSSLCTX(obj, ctx) do { \
	TypedData_Get_Struct((obj), SSL_CTX, &ossl_sslctx_type, (ctx));	\
} while (0)

VALUE mSSL;
static VALUE mSSLExtConfig;
static VALUE eSSLError;
VALUE cSSLContext;
VALUE cSSLSocket;

static VALUE eSSLErrorWaitReadable;
static VALUE eSSLErrorWaitWritable;

#define ossl_sslctx_set_cert(o,v)        	rb_iv_set((o),"@cert",(v))
#define ossl_sslctx_set_key(o,v)         	rb_iv_set((o),"@key",(v))
#define ossl_sslctx_set_client_ca(o,v)   	rb_iv_set((o),"@client_ca",(v))
#define ossl_sslctx_set_ca_file(o,v)     	rb_iv_set((o),"@ca_file",(v))
#define ossl_sslctx_set_ca_path(o,v)     	rb_iv_set((o),"@ca_path",(v))
#define ossl_sslctx_set_timeout(o,v)     	rb_iv_set((o),"@timeout",(v))
#define ossl_sslctx_set_verify_mode(o,v) 	rb_iv_set((o),"@verify_mode",(v))
#define ossl_sslctx_set_verify_dep(o,v)  	rb_iv_set((o),"@verify_depth",(v))
#define ossl_sslctx_set_verify_cb(o,v)   	rb_iv_set((o),"@verify_callback",(v))
#define ossl_sslctx_set_cert_store(o,v)  	rb_iv_set((o),"@cert_store",(v))
#define ossl_sslctx_set_extra_cert(o,v)  	rb_iv_set((o),"@extra_chain_cert",(v))
#define ossl_sslctx_set_client_cert_cb(o,v) 	rb_iv_set((o),"@client_cert_cb",(v))
#define ossl_sslctx_set_sess_id_ctx(o, v) 	rb_iv_set((o),"@session_id_context",(v))

#define ossl_sslctx_get_cert(o)          	rb_iv_get((o),"@cert")
#define ossl_sslctx_get_key(o)           	rb_iv_get((o),"@key")
#define ossl_sslctx_get_client_ca(o)     	rb_iv_get((o),"@client_ca")
#define ossl_sslctx_get_ca_file(o)       	rb_iv_get((o),"@ca_file")
#define ossl_sslctx_get_ca_path(o)       	rb_iv_get((o),"@ca_path")
#define ossl_sslctx_get_timeout(o)       	rb_iv_get((o),"@timeout")
#define ossl_sslctx_get_verify_mode(o)   	rb_iv_get((o),"@verify_mode")
#define ossl_sslctx_get_verify_dep(o)    	rb_iv_get((o),"@verify_depth")
#define ossl_sslctx_get_verify_cb(o)     	rb_iv_get((o),"@verify_callback")
#define ossl_sslctx_get_cert_store(o)    	rb_iv_get((o),"@cert_store")
#define ossl_sslctx_get_extra_cert(o)    	rb_iv_get((o),"@extra_chain_cert")
#define ossl_sslctx_get_client_cert_cb(o) 	rb_iv_get((o),"@client_cert_cb")
#define ossl_sslctx_get_tmp_ecdh_cb(o)          rb_iv_get((o),"@tmp_ecdh_callback")
#define ossl_sslctx_get_sess_id_ctx(o)   	rb_iv_get((o),"@session_id_context")

#define ossl_ssl_get_io(o)           rb_iv_get((o),"@io")
#define ossl_ssl_get_ctx(o)          rb_iv_get((o),"@context")
#define ossl_ssl_get_x509(o)         rb_iv_get((o),"@x509")
#define ossl_ssl_get_key(o)          rb_iv_get((o),"@key")

#define ossl_ssl_set_x509(o,v)       rb_iv_set((o),"@x509",(v))
#define ossl_ssl_set_key(o,v)        rb_iv_set((o),"@key",(v))
#define ossl_ssl_set_tmp_dh(o,v)     rb_iv_set((o),"@tmp_dh",(v))
#define ossl_ssl_set_tmp_ecdh(o,v)   rb_iv_set((o),"@tmp_ecdh",(v))

static ID ID_callback_state;

static VALUE sym_exception, sym_wait_readable, sym_wait_writable;

/*
 * SSLContext class
 */
static const struct {
    const char *name;
    SSL_METHOD *(*func)(void);
} ossl_ssl_method_tab[] = {
#define OSSL_SSL_METHOD_ENTRY(name) { #name, (SSL_METHOD *(*)(void))name##_method }
    OSSL_SSL_METHOD_ENTRY(TLSv1),
    OSSL_SSL_METHOD_ENTRY(TLSv1_server),
    OSSL_SSL_METHOD_ENTRY(TLSv1_client),
#if defined(HAVE_TLSV1_2_METHOD) && defined(HAVE_TLSV1_2_SERVER_METHOD) && \
        defined(HAVE_TLSV1_2_CLIENT_METHOD)
    OSSL_SSL_METHOD_ENTRY(TLSv1_2),
    OSSL_SSL_METHOD_ENTRY(TLSv1_2_server),
    OSSL_SSL_METHOD_ENTRY(TLSv1_2_client),
#endif
#if defined(HAVE_TLSV1_1_METHOD) && defined(HAVE_TLSV1_1_SERVER_METHOD) && \
        defined(HAVE_TLSV1_1_CLIENT_METHOD)
    OSSL_SSL_METHOD_ENTRY(TLSv1_1),
    OSSL_SSL_METHOD_ENTRY(TLSv1_1_server),
    OSSL_SSL_METHOD_ENTRY(TLSv1_1_client),
#endif
#if defined(HAVE_SSLV2_METHOD) && defined(HAVE_SSLV2_SERVER_METHOD) && \
        defined(HAVE_SSLV2_CLIENT_METHOD)
    OSSL_SSL_METHOD_ENTRY(SSLv2),
    OSSL_SSL_METHOD_ENTRY(SSLv2_server),
    OSSL_SSL_METHOD_ENTRY(SSLv2_client),
#endif
#if defined(HAVE_SSLV3_METHOD) && defined(HAVE_SSLV3_SERVER_METHOD) && \
        defined(HAVE_SSLV3_CLIENT_METHOD)
    OSSL_SSL_METHOD_ENTRY(SSLv3),
    OSSL_SSL_METHOD_ENTRY(SSLv3_server),
    OSSL_SSL_METHOD_ENTRY(SSLv3_client),
#endif
    OSSL_SSL_METHOD_ENTRY(SSLv23),
    OSSL_SSL_METHOD_ENTRY(SSLv23_server),
    OSSL_SSL_METHOD_ENTRY(SSLv23_client),
#undef OSSL_SSL_METHOD_ENTRY
};

static int ossl_ssl_ex_vcb_idx;
static int ossl_ssl_ex_store_p;
static int ossl_ssl_ex_ptr_idx;

static void
ossl_sslctx_free(void *ptr)
{
    SSL_CTX *ctx = ptr;
    if(ctx && SSL_CTX_get_ex_data(ctx, ossl_ssl_ex_store_p)== (void*)1)
	ctx->cert_store = NULL;
    SSL_CTX_free(ctx);
}

static const rb_data_type_t ossl_sslctx_type = {
    "OpenSSL/SSL/CTX",
    {
	0, ossl_sslctx_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
ossl_sslctx_s_alloc(VALUE klass)
{
    SSL_CTX *ctx;
    long mode = SSL_MODE_ENABLE_PARTIAL_WRITE;
    VALUE obj;

#ifdef SSL_MODE_RELEASE_BUFFERS
    mode |= SSL_MODE_RELEASE_BUFFERS;
#endif

    obj = TypedData_Wrap_Struct(klass, &ossl_sslctx_type, 0);
    ctx = SSL_CTX_new(SSLv23_method());
    if (!ctx) {
        ossl_raise(eSSLError, "SSL_CTX_new");
    }
    SSL_CTX_set_mode(ctx, mode);
    RTYPEDDATA_DATA(obj) = ctx;
    SSL_CTX_set_ex_data(ctx, ossl_ssl_ex_ptr_idx, (void*)obj);

    return obj;
}

/*
 * call-seq:
 *    ctx.ssl_version = :TLSv1
 *    ctx.ssl_version = "SSLv23_client"
 *
 * You can get a list of valid versions with OpenSSL::SSL::SSLContext::METHODS
 */
static VALUE
ossl_sslctx_set_ssl_version(VALUE self, VALUE ssl_method)
{
    SSL_METHOD *method = NULL;
    const char *s;
    VALUE m = ssl_method;
    int i;

    SSL_CTX *ctx;
    if (RB_TYPE_P(ssl_method, T_SYMBOL))
	m = rb_sym2str(ssl_method);
    s = StringValueCStr(m);
    for (i = 0; i < numberof(ossl_ssl_method_tab); i++) {
        if (strcmp(ossl_ssl_method_tab[i].name, s) == 0) {
            method = ossl_ssl_method_tab[i].func();
            break;
        }
    }
    if (!method) {
        ossl_raise(rb_eArgError, "unknown SSL method `%"PRIsVALUE"'.", m);
    }
    GetSSLCTX(self, ctx);
    if (SSL_CTX_set_ssl_version(ctx, method) != 1) {
        ossl_raise(eSSLError, "SSL_CTX_set_ssl_version");
    }

    return ssl_method;
}

static VALUE
ossl_call_client_cert_cb(VALUE obj)
{
    VALUE cb, ary, cert, key;

    cb = rb_funcall(obj, rb_intern("client_cert_cb"), 0);
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
    VALUE obj, success;

    obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    success = rb_protect(ossl_call_client_cert_cb, obj, NULL);
    if (!RTEST(success)) return 0;
    *x509 = DupX509CertPtr(ossl_ssl_get_x509(obj));
    *pkey = DupPKeyPtr(ossl_ssl_get_key(obj));

    return 1;
}

#if !defined(OPENSSL_NO_DH)
static VALUE
ossl_call_tmp_dh_callback(VALUE args)
{
    VALUE cb, dh;
    EVP_PKEY *pkey;

    cb = rb_funcall(rb_ary_entry(args, 0), rb_intern("tmp_dh_callback"), 0);

    if (NIL_P(cb)) return Qfalse;
    dh = rb_apply(cb, rb_intern("call"), args);
    pkey = GetPKeyPtr(dh);
    if (EVP_PKEY_type(pkey->type) != EVP_PKEY_DH) return Qfalse;

    return dh;
}

static DH*
ossl_tmp_dh_callback(SSL *ssl, int is_export, int keylength)
{
    VALUE args, dh, rb_ssl;

    rb_ssl = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);

    args = rb_ary_new_from_args(3, rb_ssl, INT2FIX(is_export), INT2FIX(keylength));

    dh = rb_protect(ossl_call_tmp_dh_callback, args, NULL);
    if (!RTEST(dh)) return NULL;
    ossl_ssl_set_tmp_dh(rb_ssl, dh);

    return GetPKeyPtr(dh)->pkey.dh;
}
#endif /* OPENSSL_NO_DH */

#if !defined(OPENSSL_NO_EC)
static VALUE
ossl_call_tmp_ecdh_callback(VALUE args)
{
    VALUE cb, ecdh;
    EVP_PKEY *pkey;

    cb = rb_funcall(rb_ary_entry(args, 0), rb_intern("tmp_ecdh_callback"), 0);

    if (NIL_P(cb)) return Qfalse;
    ecdh = rb_apply(cb, rb_intern("call"), args);
    pkey = GetPKeyPtr(ecdh);
    if (EVP_PKEY_type(pkey->type) != EVP_PKEY_EC) return Qfalse;

    return ecdh;
}

static EC_KEY*
ossl_tmp_ecdh_callback(SSL *ssl, int is_export, int keylength)
{
    VALUE args, ecdh, rb_ssl;

    rb_ssl = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);

    args = rb_ary_new_from_args(3, rb_ssl, INT2FIX(is_export), INT2FIX(keylength));

    ecdh = rb_protect(ossl_call_tmp_ecdh_callback, args, NULL);
    if (!RTEST(ecdh)) return NULL;
    ossl_ssl_set_tmp_ecdh(rb_ssl, ecdh);

    return GetPKeyPtr(ecdh)->pkey.ec;
}
#endif

static int
ossl_ssl_verify_callback(int preverify_ok, X509_STORE_CTX *ctx)
{
    VALUE cb;
    SSL *ssl;

    ssl = X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
    cb = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_vcb_idx);
    X509_STORE_CTX_set_ex_data(ctx, ossl_store_ctx_ex_verify_cb_idx, (void *)cb);
    return ossl_verify_cb(preverify_ok, ctx);
}

static VALUE
ossl_call_session_get_cb(VALUE ary)
{
    VALUE ssl_obj, cb;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    cb = rb_funcall(ssl_obj, rb_intern("session_get_cb"), 0);
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

    ret_obj = rb_protect(ossl_call_session_get_cb, ary, &state);
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
    VALUE ssl_obj, cb;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    cb = rb_funcall(ssl_obj, rb_intern("session_new_cb"), 0);
    if (NIL_P(cb)) return Qnil;

    return rb_funcall(cb, rb_intern("call"), 1, ary);
}

/* return 1 normal.  return 0 removes the session */
static int
ossl_sslctx_session_new_cb(SSL *ssl, SSL_SESSION *sess)
{
    VALUE ary, ssl_obj, sess_obj;
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

    rb_protect(ossl_call_session_new_cb, ary, &state);
    if (state) {
        rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(state));
    }

    /*
     * return 0 which means to OpenSSL that the session is still
     * valid (since we created Ruby Session object) and was not freed by us
     * with SSL_SESSION_free(). Call SSLContext#remove_session(sess) in
     * session_get_cb block if you don't want OpenSSL to cache the session
     * internally.
     */
    return 0;
}

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

static void
ossl_sslctx_session_remove_cb(SSL_CTX *ctx, SSL_SESSION *sess)
{
    VALUE ary, sslctx_obj, sess_obj;
    void *ptr;
    int state = 0;

    /*
     * This callback is also called for all sessions in the internal store
     * when SSL_CTX_free() is called.
     */
    if (rb_during_gc())
	return;

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

    rb_protect((VALUE(*)_((VALUE)))ossl_call_session_remove_cb, ary, &state);
    if (state) {
/*
  the SSL_CTX is frozen, nowhere to save state.
  there is no common accessor method to check it either.
        rb_ivar_set(sslctx_obj, ID_callback_state, INT2NUM(state));
*/
    }
}

static VALUE
ossl_sslctx_add_extra_chain_cert_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, arg))
{
    X509 *x509;
    SSL_CTX *ctx;

    GetSSLCTX(arg, ctx);
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
        GetSSL(ssl_obj, ssl);
        GetSSLCTX(ret_obj, ctx2);
        SSL_set_SSL_CTX(ssl, ctx2);
        rb_iv_set(ssl_obj, "@context", ret_obj);
    } else if (!NIL_P(ret_obj)) {
            ossl_raise(rb_eArgError, "servername_cb must return an OpenSSL::SSL::SSLContext object or nil");
    }

    return ret_obj;
}

static int
ssl_servername_cb(SSL *ssl, int *ad, void *arg)
{
    VALUE ary, ssl_obj;
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

    rb_protect((VALUE(*)_((VALUE)))ossl_call_servername_cb, ary, &state);
    if (state) {
        rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(state));
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    }

    return SSL_TLSEXT_ERR_OK;
}
#endif

static void
ssl_renegotiation_cb(const SSL *ssl)
{
    VALUE ssl_obj, sslctx_obj, cb;
    void *ptr;

    if ((ptr = SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx)) == NULL)
	ossl_raise(eSSLError, "SSL object could not be retrieved");
    ssl_obj = (VALUE)ptr;

    sslctx_obj = rb_iv_get(ssl_obj, "@context");
    if (NIL_P(sslctx_obj)) return;
    cb = rb_iv_get(sslctx_obj, "@renegotiation_cb");
    if (NIL_P(cb)) return;

    (void) rb_funcall(cb, rb_intern("call"), 1, ssl_obj);
}

#if defined(HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB) || defined(HAVE_SSL_CTX_SET_ALPN_SELECT_CB)
static VALUE
ssl_npn_encode_protocol_i(VALUE cur, VALUE encoded)
{
    int len = RSTRING_LENINT(cur);
    char len_byte;
    if (len < 1 || len > 255)
	ossl_raise(eSSLError, "Advertised protocol must have length 1..255");
    /* Encode the length byte */
    len_byte = len;
    rb_str_buf_cat(encoded, &len_byte, 1);
    rb_str_buf_cat(encoded, RSTRING_PTR(cur), len);
    return Qnil;
}

static VALUE
ssl_encode_npn_protocols(VALUE protocols)
{
    VALUE encoded = rb_str_new2("");
    rb_iterate(rb_each, protocols, ssl_npn_encode_protocol_i, encoded);
    StringValueCStr(encoded);
    return encoded;
}

static int
ssl_npn_select_cb_common(VALUE cb, const unsigned char **out, unsigned char *outlen, const unsigned char *in, unsigned int inlen)
{
    VALUE selected;
    long len;
    VALUE protocols = rb_ary_new();
    unsigned char l;
    const unsigned char *in_end = in + inlen;

    /* assume OpenSSL verifies this format */
    /* The format is len_1|proto_1|...|len_n|proto_n */
    while (in < in_end) {
	l = *in++;
	rb_ary_push(protocols, rb_str_new((const char *)in, l));
	in += l;
    }

    selected = rb_funcall(cb, rb_intern("call"), 1, protocols);
    StringValue(selected);
    len = RSTRING_LEN(selected);
    if (len < 1 || len >= 256) {
	ossl_raise(eSSLError, "Selected protocol name must have length 1..255");
    }
    *out = (unsigned char *)RSTRING_PTR(selected);
    *outlen = (unsigned char)len;

    return SSL_TLSEXT_ERR_OK;
}

#ifdef HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB
static int
ssl_npn_advertise_cb(SSL *ssl, const unsigned char **out, unsigned int *outlen, void *arg)
{
    VALUE sslctx_obj = (VALUE) arg;
    VALUE protocols = rb_iv_get(sslctx_obj, "@_protocols");

    *out = (const unsigned char *) RSTRING_PTR(protocols);
    *outlen = RSTRING_LENINT(protocols);

    return SSL_TLSEXT_ERR_OK;
}

static int
ssl_npn_select_cb(SSL *s, unsigned char **out, unsigned char *outlen, const unsigned char *in, unsigned int inlen, void *arg)
{
    VALUE sslctx_obj, cb;

    sslctx_obj = (VALUE) arg;
    cb = rb_iv_get(sslctx_obj, "@npn_select_cb");

    return ssl_npn_select_cb_common(cb, (const unsigned char **)out, outlen, in, inlen);
}
#endif

#ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
static int
ssl_alpn_select_cb(SSL *ssl, const unsigned char **out, unsigned char *outlen, const unsigned char *in, unsigned int inlen, void *arg)
{
    VALUE sslctx_obj, cb;

    sslctx_obj = (VALUE) arg;
    cb = rb_iv_get(sslctx_obj, "@alpn_select_cb");

    return ssl_npn_select_cb_common(cb, out, outlen, in, inlen);
}
#endif
#endif /* HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB || HAVE_SSL_CTX_SET_ALPN_SELECT_CB */

/* This function may serve as the entry point to support further
 * callbacks. */
static void
ssl_info_cb(const SSL *ssl, int where, int val)
{
    int state = SSL_state(ssl);

    if ((where & SSL_CB_HANDSHAKE_START) &&
	(state & SSL_ST_ACCEPT)) {
	ssl_renegotiation_cb(ssl);
    }
}

/*
 * Gets various OpenSSL options.
 */
static VALUE
ossl_sslctx_get_options(VALUE self)
{
    SSL_CTX *ctx;
    GetSSLCTX(self, ctx);
    return LONG2NUM(SSL_CTX_get_options(ctx));
}

/*
 * Sets various OpenSSL options.
 */
static VALUE
ossl_sslctx_set_options(VALUE self, VALUE options)
{
    SSL_CTX *ctx;

    rb_check_frozen(self);
    GetSSLCTX(self, ctx);

    SSL_CTX_clear_options(ctx, SSL_CTX_get_options(ctx));

    if (NIL_P(options)) {
	SSL_CTX_set_options(ctx, SSL_OP_ALL);
    } else {
	SSL_CTX_set_options(ctx, NUM2LONG(options));
    }

    return self;
}

/*
 * call-seq:
 *    ctx.setup => Qtrue # first time
 *    ctx.setup => nil # thereafter
 *
 * This method is called automatically when a new SSLSocket is created.
 * However, it is not thread-safe and must be called before creating
 * SSLSocket objects in a multi-threaded program.
 */
static VALUE
ossl_sslctx_setup(VALUE self)
{
    SSL_CTX *ctx;
    X509 *cert = NULL, *client_ca = NULL;
    X509_STORE *store;
    EVP_PKEY *key = NULL;
    char *ca_path = NULL, *ca_file = NULL;
    int verify_mode;
    long i;
    VALUE val;

    if(OBJ_FROZEN(self)) return Qnil;
    GetSSLCTX(self, ctx);

#if !defined(OPENSSL_NO_DH)
    SSL_CTX_set_tmp_dh_callback(ctx, ossl_tmp_dh_callback);
#endif

#if !defined(OPENSSL_NO_EC)
    if (RTEST(ossl_sslctx_get_tmp_ecdh_cb(self))){
	SSL_CTX_set_tmp_ecdh_callback(ctx, ossl_tmp_ecdh_callback);
    }
#endif

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
            ossl_raise(eSSLError, "SSL_CTX_use_certificate");
        }
        if (!SSL_CTX_use_PrivateKey(ctx, key)) {
            /* Adds a ref => Safe to FREE */
            ossl_raise(eSSLError, "SSL_CTX_use_PrivateKey");
        }
        if (!SSL_CTX_check_private_key(ctx)) {
            ossl_raise(eSSLError, "SSL_CTX_check_private_key");
        }
    }

    val = ossl_sslctx_get_client_ca(self);
    if(!NIL_P(val)){
	if (RB_TYPE_P(val, T_ARRAY)) {
	    for(i = 0; i < RARRAY_LEN(val); i++){
		client_ca = GetX509CertPtr(RARRAY_AREF(val, i));
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
    if(!NIL_P(val)) SSL_CTX_set_verify_depth(ctx, NUM2INT(val));

#ifdef HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB
    val = rb_iv_get(self, "@npn_protocols");
    if (!NIL_P(val)) {
	rb_iv_set(self, "@_protocols", ssl_encode_npn_protocols(val));
	SSL_CTX_set_next_protos_advertised_cb(ctx, ssl_npn_advertise_cb, (void *) self);
	OSSL_Debug("SSL NPN advertise callback added");
    }
    if (RTEST(rb_iv_get(self, "@npn_select_cb"))) {
	SSL_CTX_set_next_proto_select_cb(ctx, ssl_npn_select_cb, (void *) self);
	OSSL_Debug("SSL NPN select callback added");
    }
#endif

#ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
    val = rb_iv_get(self, "@alpn_protocols");
    if (!NIL_P(val)) {
	VALUE rprotos = ssl_encode_npn_protocols(val);
	SSL_CTX_set_alpn_protos(ctx, (const unsigned char *)StringValueCStr(rprotos), RSTRING_LENINT(rprotos));
	OSSL_Debug("SSL ALPN values added");
    }
    if (RTEST(rb_iv_get(self, "@alpn_select_cb"))) {
	SSL_CTX_set_alpn_select_cb(ctx, ssl_alpn_select_cb, (void *) self);
	OSSL_Debug("SSL ALPN select callback added");
    }
#endif

    rb_obj_freeze(self);

    val = ossl_sslctx_get_sess_id_ctx(self);
    if (!NIL_P(val)){
	StringValue(val);
	if (!SSL_CTX_set_session_id_context(ctx, (unsigned char *)RSTRING_PTR(val),
					    RSTRING_LENINT(val))){
	    ossl_raise(eSSLError, "SSL_CTX_set_session_id_context");
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
 *
 * The list of ciphers configured for this context.
 */
static VALUE
ossl_sslctx_get_ciphers(VALUE self)
{
    SSL_CTX *ctx;
    STACK_OF(SSL_CIPHER) *ciphers;
    SSL_CIPHER *cipher;
    VALUE ary;
    int i, num;

    GetSSLCTX(self, ctx);
    if(!ctx){
        rb_warning("SSL_CTX is not initialized.");
        return Qnil;
    }
    ciphers = ctx->cipher_list;

    if (!ciphers)
        return rb_ary_new();

    num = sk_SSL_CIPHER_num(ciphers);
    ary = rb_ary_new2(num);
    for(i = 0; i < num; i++){
        cipher = sk_SSL_CIPHER_value(ciphers, i);
        rb_ary_push(ary, ossl_ssl_cipher_to_ary(cipher));
    }
    return ary;
}

/*
 * call-seq:
 *    ctx.ciphers = "cipher1:cipher2:..."
 *    ctx.ciphers = [name, ...]
 *    ctx.ciphers = [[name, version, bits, alg_bits], ...]
 *
 * Sets the list of available ciphers for this context.  Note in a server
 * context some ciphers require the appropriate certificates.  For example, an
 * RSA cipher can only be chosen when an RSA certificate is available.
 *
 * See also OpenSSL::Cipher and OpenSSL::Cipher::ciphers
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
    else if (RB_TYPE_P(v, T_ARRAY)) {
        str = rb_str_new(0, 0);
        for (i = 0; i < RARRAY_LEN(v); i++) {
            elem = rb_ary_entry(v, i);
            if (RB_TYPE_P(elem, T_ARRAY)) elem = rb_ary_entry(elem, 0);
            elem = rb_String(elem);
            rb_str_append(str, elem);
            if (i < RARRAY_LEN(v)-1) rb_str_cat2(str, ":");
        }
    } else {
        str = v;
        StringValue(str);
    }

    GetSSLCTX(self, ctx);
    if(!ctx){
        ossl_raise(eSSLError, "SSL_CTX is not initialized.");
        return Qnil;
    }
    if (!SSL_CTX_set_cipher_list(ctx, RSTRING_PTR(str))) {
        ossl_raise(eSSLError, "SSL_CTX_set_cipher_list");
    }

    return v;
}

/*
 *  call-seq:
 *     ctx.session_add(session) -> true | false
 *
 * Adds +session+ to the session cache
 */
static VALUE
ossl_sslctx_session_add(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;
    SSL_SESSION *sess;

    GetSSLCTX(self, ctx);
    SafeGetSSLSession(arg, sess);

    return SSL_CTX_add_session(ctx, sess) == 1 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     ctx.session_remove(session) -> true | false
 *
 * Removes +session+ from the session cache
 */
static VALUE
ossl_sslctx_session_remove(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;
    SSL_SESSION *sess;

    GetSSLCTX(self, ctx);
    SafeGetSSLSession(arg, sess);

    return SSL_CTX_remove_session(ctx, sess) == 1 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     ctx.session_cache_mode -> Integer
 *
 * The current session cache mode.
 */
static VALUE
ossl_sslctx_get_session_cache_mode(VALUE self)
{
    SSL_CTX *ctx;

    GetSSLCTX(self, ctx);

    return LONG2NUM(SSL_CTX_get_session_cache_mode(ctx));
}

/*
 *  call-seq:
 *     ctx.session_cache_mode=(integer) -> Integer
 *
 * Sets the SSL session cache mode.  Bitwise-or together the desired
 * SESSION_CACHE_* constants to set.  See SSL_CTX_set_session_cache_mode(3) for
 * details.
 */
static VALUE
ossl_sslctx_set_session_cache_mode(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;

    GetSSLCTX(self, ctx);

    SSL_CTX_set_session_cache_mode(ctx, NUM2LONG(arg));

    return arg;
}

/*
 *  call-seq:
 *     ctx.session_cache_size -> Integer
 *
 * Returns the current session cache size.  Zero is used to represent an
 * unlimited cache size.
 */
static VALUE
ossl_sslctx_get_session_cache_size(VALUE self)
{
    SSL_CTX *ctx;

    GetSSLCTX(self, ctx);

    return LONG2NUM(SSL_CTX_sess_get_cache_size(ctx));
}

/*
 *  call-seq:
 *     ctx.session_cache_size=(integer) -> Integer
 *
 * Sets the session cache size.  Returns the previously valid session cache
 * size.  Zero is used to represent an unlimited session cache size.
 */
static VALUE
ossl_sslctx_set_session_cache_size(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;

    GetSSLCTX(self, ctx);

    SSL_CTX_sess_set_cache_size(ctx, NUM2LONG(arg));

    return arg;
}

/*
 *  call-seq:
 *     ctx.session_cache_stats -> Hash
 *
 * Returns a Hash containing the following keys:
 *
 * :accept:: Number of started SSL/TLS handshakes in server mode
 * :accept_good:: Number of established SSL/TLS sessions in server mode
 * :accept_renegotiate:: Number of start renegotiations in server mode
 * :cache_full:: Number of sessions that were removed due to cache overflow
 * :cache_hits:: Number of successfully reused connections
 * :cache_misses:: Number of sessions proposed by clients that were not found
 *                 in the cache
 * :cache_num:: Number of sessions in the internal session cache
 * :cb_hits:: Number of sessions retrieved from the external cache in server
 *            mode
 * :connect:: Number of started SSL/TLS handshakes in client mode
 * :connect_good:: Number of established SSL/TLS sessions in client mode
 * :connect_renegotiate:: Number of start renegotiations in client mode
 * :timeouts:: Number of sessions proposed by clients that were found in the
 *             cache but had expired due to timeouts
 */
static VALUE
ossl_sslctx_get_session_cache_stats(VALUE self)
{
    SSL_CTX *ctx;
    VALUE hash;

    GetSSLCTX(self, ctx);

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
 * Removes sessions in the internal cache that have expired at +time+.
 */
static VALUE
ossl_sslctx_flush_sessions(int argc, VALUE *argv, VALUE self)
{
    VALUE arg1;
    SSL_CTX *ctx;
    time_t tm = 0;

    rb_scan_args(argc, argv, "01", &arg1);

    GetSSLCTX(self, ctx);

    if (NIL_P(arg1)) {
        tm = time(0);
    } else if (rb_obj_is_instance_of(arg1, rb_cTime)) {
        tm = NUM2LONG(rb_funcall(arg1, rb_intern("to_i"), 0));
    } else {
        ossl_raise(rb_eArgError, "arg must be Time or nil");
    }

    SSL_CTX_flush_sessions(ctx, (long)tm);

    return self;
}

/*
 * SSLSocket class
 */
#ifndef OPENSSL_NO_SOCK
static void
ossl_ssl_shutdown(SSL *ssl)
{
    int i, rc;

    if (ssl) {
	/* 4 is from SSL_smart_shutdown() of mod_ssl.c (v2.2.19) */
	/* It says max 2x pending + 2x data = 4 */
	for (i = 0; i < 4; ++i) {
	    /*
	     * Ignore the case SSL_shutdown returns -1. Empty handshake_func
	     * must not happen.
	     */
	    if ((rc = SSL_shutdown(ssl)) != 0)
		break;
	}
	SSL_clear(ssl);
	ERR_clear_error();
    }
}

static void
ossl_ssl_free(void *ssl)
{
    SSL_free(ssl);
}

const rb_data_type_t ossl_ssl_type = {
    "OpenSSL/SSL",
    {
	0, ossl_ssl_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
ossl_ssl_s_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &ossl_ssl_type, NULL);
}

static VALUE
ossl_ssl_setup(VALUE self)
{
    VALUE io, v_ctx, cb;
    SSL_CTX *ctx;
    SSL *ssl;
    rb_io_t *fptr;

    GetSSL(self, ssl);
    if(!ssl){
#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
	VALUE hostname = rb_iv_get(self, "@hostname");
#endif

        v_ctx = ossl_ssl_get_ctx(self);
        GetSSLCTX(v_ctx, ctx);

        ssl = SSL_new(ctx);
        if (!ssl) {
            ossl_raise(eSSLError, "SSL_new");
        }
        DATA_PTR(self) = ssl;

#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
        if (!NIL_P(hostname)) {
           if (SSL_set_tlsext_host_name(ssl, StringValuePtr(hostname)) != 1)
               ossl_raise(eSSLError, "SSL_set_tlsext_host_name");
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
	SSL_set_info_callback(ssl, ssl_info_cb);
    }

    return Qtrue;
}

#ifdef _WIN32
#define ssl_get_error(ssl, ret) (errno = rb_w32_map_errno(WSAGetLastError()), SSL_get_error((ssl), (ret)))
#else
#define ssl_get_error(ssl, ret) SSL_get_error((ssl), (ret))
#endif

#define ossl_ssl_data_get_struct(v, ssl)		\
do {							\
    GetSSL((v), (ssl)); 				\
    if (!(ssl)) {					\
        rb_warning("SSL session is not started yet.");  \
        return Qnil;					\
    }							\
} while (0)

static void
write_would_block(int nonblock)
{
    if (nonblock) {
        VALUE exc = ossl_exc_new(eSSLErrorWaitWritable, "write would block");
        rb_exc_raise(exc);
    }
}

static void
read_would_block(int nonblock)
{
    if (nonblock) {
        VALUE exc = ossl_exc_new(eSSLErrorWaitReadable, "read would block");
        rb_exc_raise(exc);
    }
}

static int
no_exception_p(VALUE opts)
{
    if (RB_TYPE_P(opts, T_HASH) &&
          rb_hash_lookup2(opts, sym_exception, Qundef) == Qfalse)
	return 1;
    return 0;
}

static VALUE
ossl_start_ssl(VALUE self, int (*func)(), const char *funcname, VALUE opts)
{
    SSL *ssl;
    rb_io_t *fptr;
    int ret, ret2;
    VALUE cb_state;
    int nonblock = opts != Qfalse;

    rb_ivar_set(self, ID_callback_state, Qnil);

    ossl_ssl_data_get_struct(self, ssl);

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
            if (no_exception_p(opts)) { return sym_wait_writable; }
            write_would_block(nonblock);
            rb_io_wait_writable(FPTR_TO_FD(fptr));
            continue;
	case SSL_ERROR_WANT_READ:
            if (no_exception_p(opts)) { return sym_wait_readable; }
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
 *
 * Initiates an SSL/TLS handshake with a server.  The handshake may be started
 * after unencrypted data has been sent over the socket.
 */
static VALUE
ossl_ssl_connect(VALUE self)
{
    ossl_ssl_setup(self);

    return ossl_start_ssl(self, SSL_connect, "SSL_connect", Qfalse);
}

/*
 * call-seq:
 *    ssl.connect_nonblock([options]) => self
 *
 * Initiates the SSL/TLS handshake as a client in non-blocking manner.
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
 * By specifying `exception: false`, the options hash allows you to indicate
 * that connect_nonblock should not raise an IO::WaitReadable or
 * IO::WaitWritable exception, but return the symbol :wait_readable or
 * :wait_writable instead.
 */
static VALUE
ossl_ssl_connect_nonblock(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    rb_scan_args(argc, argv, "0:", &opts);

    ossl_ssl_setup(self);

    return ossl_start_ssl(self, SSL_connect, "SSL_connect", opts);
}

/*
 * call-seq:
 *    ssl.accept => self
 *
 * Waits for a SSL/TLS client to initiate a handshake.  The handshake may be
 * started after unencrypted data has been sent over the socket.
 */
static VALUE
ossl_ssl_accept(VALUE self)
{
    ossl_ssl_setup(self);

    return ossl_start_ssl(self, SSL_accept, "SSL_accept", Qfalse);
}

/*
 * call-seq:
 *    ssl.accept_nonblock([options]) => self
 *
 * Initiates the SSL/TLS handshake as a server in non-blocking manner.
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
 * By specifying `exception: false`, the options hash allows you to indicate
 * that accept_nonblock should not raise an IO::WaitReadable or
 * IO::WaitWritable exception, but return the symbol :wait_readable or
 * :wait_writable instead.
 */
static VALUE
ossl_ssl_accept_nonblock(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;

    rb_scan_args(argc, argv, "0:", &opts);
    ossl_ssl_setup(self);

    return ossl_start_ssl(self, SSL_accept, "SSL_accept", opts);
}

static VALUE
ossl_ssl_read_internal(int argc, VALUE *argv, VALUE self, int nonblock)
{
    SSL *ssl;
    int ilen, nread = 0;
    VALUE len, str;
    rb_io_t *fptr;
    VALUE opts = Qnil;

    if (nonblock) {
	rb_scan_args(argc, argv, "11:", &len, &str, &opts);
    } else {
	rb_scan_args(argc, argv, "11", &len, &str);
    }

    ilen = NUM2INT(len);
    if (NIL_P(str))
	str = rb_str_new(0, ilen);
    else {
	StringValue(str);
	if (RSTRING_LEN(str) >= ilen)
	    rb_str_modify(str);
	else
	    rb_str_modify_expand(str, ilen - RSTRING_LEN(str));
    }
    OBJ_TAINT(str);
    rb_str_set_len(str, 0);
    if (ilen == 0)
	return str;

    GetSSL(self, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);
    if (ssl) {
	for (;;){
	    nread = SSL_read(ssl, RSTRING_PTR(str), ilen);
	    switch(ssl_get_error(ssl, nread)){
	    case SSL_ERROR_NONE:
		goto end;
	    case SSL_ERROR_ZERO_RETURN:
		if (no_exception_p(opts)) { return Qnil; }
		rb_eof_error();
	    case SSL_ERROR_WANT_WRITE:
		if (no_exception_p(opts)) { return sym_wait_writable; }
                write_would_block(nonblock);
                rb_io_wait_writable(FPTR_TO_FD(fptr));
                continue;
	    case SSL_ERROR_WANT_READ:
		if (no_exception_p(opts)) { return sym_wait_readable; }
                read_would_block(nonblock);
                rb_io_wait_readable(FPTR_TO_FD(fptr));
		continue;
	    case SSL_ERROR_SYSCALL:
		if(ERR_peek_error() == 0 && nread == 0) {
		    if (no_exception_p(opts)) { return Qnil; }
		    rb_eof_error();
		}
		rb_sys_fail(0);
	    default:
		ossl_raise(eSSLError, "SSL_read");
	    }
        }
    }
    else {
        ID meth = nonblock ? rb_intern("read_nonblock") : rb_intern("sysread");
        rb_warning("SSL session is not started yet.");
        if (nonblock) {
          return rb_funcall(ossl_ssl_get_io(self), meth, 3, len, str, opts);
        } else {
          return rb_funcall(ossl_ssl_get_io(self), meth, 2, len, str);
        }
    }

  end:
    rb_str_set_len(str, nread);
    return str;
}

/*
 * call-seq:
 *    ssl.sysread(length) => string
 *    ssl.sysread(length, buffer) => buffer
 *
 * Reads +length+ bytes from the SSL connection.  If a pre-allocated +buffer+
 * is provided the data will be written into it.
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
 *    ssl.sysread_nonblock(length[, buffer [, opts]) => buffer
 *
 * A non-blocking version of #sysread.  Raises an SSLError if reading would
 * block.  If "exception: false" is passed, this method returns a symbol of
 * :wait_readable, :wait_writable, or nil, rather than raising an exception.
 *
 * Reads +length+ bytes from the SSL connection.  If a pre-allocated +buffer+
 * is provided the data will be written into it.
 */
static VALUE
ossl_ssl_read_nonblock(int argc, VALUE *argv, VALUE self)
{
    return ossl_ssl_read_internal(argc, argv, self, 1);
}

static VALUE
ossl_ssl_write_internal(VALUE self, VALUE str, VALUE opts)
{
    SSL *ssl;
    int nwrite = 0;
    rb_io_t *fptr;
    int nonblock = opts != Qfalse;

    StringValue(str);
    GetSSL(self, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);

    if (ssl) {
	for (;;){
	    int num = RSTRING_LENINT(str);

	    /* SSL_write(3ssl) manpage states num == 0 is undefined */
	    if (num == 0)
		goto end;

	    nwrite = SSL_write(ssl, RSTRING_PTR(str), num);
	    switch(ssl_get_error(ssl, nwrite)){
	    case SSL_ERROR_NONE:
		goto end;
	    case SSL_ERROR_WANT_WRITE:
		if (no_exception_p(opts)) { return sym_wait_writable; }
                write_would_block(nonblock);
                rb_io_wait_writable(FPTR_TO_FD(fptr));
                continue;
	    case SSL_ERROR_WANT_READ:
		if (no_exception_p(opts)) { return sym_wait_readable; }
                read_would_block(nonblock);
                rb_io_wait_readable(FPTR_TO_FD(fptr));
                continue;
	    case SSL_ERROR_SYSCALL:
		if (errno) rb_sys_fail(0);
	    default:
		ossl_raise(eSSLError, "SSL_write");
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
 *    ssl.syswrite(string) => Integer
 *
 * Writes +string+ to the SSL connection.
 */
static VALUE
ossl_ssl_write(VALUE self, VALUE str)
{
    return ossl_ssl_write_internal(self, str, Qfalse);
}

/*
 * call-seq:
 *    ssl.syswrite_nonblock(string) => Integer
 *
 * Writes +string+ to the SSL connection in a non-blocking manner.  Raises an
 * SSLError if writing would block.
 */
static VALUE
ossl_ssl_write_nonblock(int argc, VALUE *argv, VALUE self)
{
    VALUE str, opts;

    rb_scan_args(argc, argv, "1:", &str, &opts);

    return ossl_ssl_write_internal(self, str, opts);
}

/*
 * call-seq:
 *    ssl.stop => nil
 *
 * Sends "close notify" to the peer and tries to shut down the SSL connection
 * gracefully.
 */
static VALUE
ossl_ssl_stop(VALUE self)
{
    SSL *ssl;

    ossl_ssl_data_get_struct(self, ssl);

    ossl_ssl_shutdown(ssl);

    return Qnil;
}

/*
 * call-seq:
 *    ssl.cert => cert or nil
 *
 * The X509 certificate for this socket endpoint.
 */
static VALUE
ossl_ssl_get_cert(VALUE self)
{
    SSL *ssl;
    X509 *cert = NULL;

    ossl_ssl_data_get_struct(self, ssl);

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
 *
 * The X509 certificate for this socket's peer.
 */
static VALUE
ossl_ssl_get_peer_cert(VALUE self)
{
    SSL *ssl;
    X509 *cert = NULL;
    VALUE obj;

    ossl_ssl_data_get_struct(self, ssl);

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
 *
 * The X509 certificate chain for this socket's peer.
 */
static VALUE
ossl_ssl_get_peer_cert_chain(VALUE self)
{
    SSL *ssl;
    STACK_OF(X509) *chain;
    X509 *cert;
    VALUE ary;
    int i, num;

    ossl_ssl_data_get_struct(self, ssl);

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
*    ssl.ssl_version => String
*
* Returns a String representing the SSL/TLS version that was negotiated
* for the connection, for example "TLSv1.2".
*/
static VALUE
ossl_ssl_get_version(VALUE self)
{
    SSL *ssl;

    ossl_ssl_data_get_struct(self, ssl);

    return rb_str_new2(SSL_get_version(ssl));
}

/*
* call-seq:
*    ssl.cipher => [name, version, bits, alg_bits]
*
* The cipher being used for the current connection
*/
static VALUE
ossl_ssl_get_cipher(VALUE self)
{
    SSL *ssl;
    SSL_CIPHER *cipher;

    ossl_ssl_data_get_struct(self, ssl);

    cipher = (SSL_CIPHER *)SSL_get_current_cipher(ssl);

    return ossl_ssl_cipher_to_ary(cipher);
}

/*
 * call-seq:
 *    ssl.state => string
 *
 * A description of the current connection state.
 */
static VALUE
ossl_ssl_get_state(VALUE self)
{
    SSL *ssl;
    VALUE ret;

    ossl_ssl_data_get_struct(self, ssl);

    ret = rb_str_new2(SSL_state_string(ssl));
    if (ruby_verbose) {
        rb_str_cat2(ret, ": ");
        rb_str_cat2(ret, SSL_state_string_long(ssl));
    }
    return ret;
}

/*
 * call-seq:
 *    ssl.pending => Integer
 *
 * The number of bytes that are immediately available for reading
 */
static VALUE
ossl_ssl_pending(VALUE self)
{
    SSL *ssl;

    ossl_ssl_data_get_struct(self, ssl);

    return INT2NUM(SSL_pending(ssl));
}

/*
 * call-seq:
 *    ssl.session_reused? -> true | false
 *
 * Returns true if a reused session was negotiated during the handshake.
 */
static VALUE
ossl_ssl_session_reused(VALUE self)
{
    SSL *ssl;

    ossl_ssl_data_get_struct(self, ssl);

    switch(SSL_session_reused(ssl)) {
    case 1:	return Qtrue;
    case 0:	return Qfalse;
    default:	ossl_raise(eSSLError, "SSL_session_reused");
    }

    UNREACHABLE;
}

/*
 * call-seq:
 *    ssl.session = session -> session
 *
 * Sets the Session to be used when the connection is established.
 */
static VALUE
ossl_ssl_set_session(VALUE self, VALUE arg1)
{
    SSL *ssl;
    SSL_SESSION *sess;

/* why is ossl_ssl_setup delayed? */
    ossl_ssl_setup(self);

    ossl_ssl_data_get_struct(self, ssl);

    SafeGetSSLSession(arg1, sess);

    if (SSL_set_session(ssl, sess) != 1)
        ossl_raise(eSSLError, "SSL_set_session");

    return arg1;
}

/*
 * call-seq:
 *    ssl.verify_result => Integer
 *
 * Returns the result of the peer certificates verification.  See verify(1)
 * for error values and descriptions.
 *
 * If no peer certificate was presented X509_V_OK is returned.
 */
static VALUE
ossl_ssl_get_verify_result(VALUE self)
{
    SSL *ssl;

    ossl_ssl_data_get_struct(self, ssl);

    return INT2FIX(SSL_get_verify_result(ssl));
}

/*
 * call-seq:
 *    ssl.client_ca => [x509name, ...]
 *
 * Returns the list of client CAs. Please note that in contrast to
 * SSLContext#client_ca= no array of X509::Certificate is returned but
 * X509::Name instances of the CA's subject distinguished name.
 *
 * In server mode, returns the list set by SSLContext#client_ca=.
 * In client mode, returns the list of client CAs sent from the server.
 */
static VALUE
ossl_ssl_get_client_ca_list(VALUE self)
{
    SSL *ssl;
    STACK_OF(X509_NAME) *ca;

    ossl_ssl_data_get_struct(self, ssl);

    ca = SSL_get_client_CA_list(ssl);
    return ossl_x509name_sk2ary(ca);
}

# ifdef HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB
/*
 * call-seq:
 *    ssl.npn_protocol => String
 *
 * Returns the protocol string that was finally selected by the client
 * during the handshake.
 */
static VALUE
ossl_ssl_npn_protocol(VALUE self)
{
    SSL *ssl;
    const unsigned char *out;
    unsigned int outlen;

    ossl_ssl_data_get_struct(self, ssl);

    SSL_get0_next_proto_negotiated(ssl, &out, &outlen);
    if (!outlen)
	return Qnil;
    else
	return rb_str_new((const char *) out, outlen);
}
# endif

# ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
/*
 * call-seq:
 *    ssl.alpn_protocol => String
 *
 * Returns the ALPN protocol string that was finally selected by the client
 * during the handshake.
 */
static VALUE
ossl_ssl_alpn_protocol(VALUE self)
{
    SSL *ssl;
    const unsigned char *out;
    unsigned int outlen;

    ossl_ssl_data_get_struct(self, ssl);

    SSL_get0_alpn_selected(ssl, &out, &outlen);
    if (!outlen)
	return Qnil;
    else
	return rb_str_new((const char *) out, outlen);
}
# endif
#endif /* !defined(OPENSSL_NO_SOCK) */

void
Init_ossl_ssl(void)
{
    int i;
    VALUE ary;

#if 0
    mOSSL = rb_define_module("OpenSSL"); /* let rdoc know about mOSSL */
#endif

    ID_callback_state = rb_intern("@callback_state");

    ossl_ssl_ex_vcb_idx = SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_vcb_idx",0,0,0);
    ossl_ssl_ex_store_p = SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_store_p",0,0,0);
    ossl_ssl_ex_ptr_idx = SSL_get_ex_new_index(0,(void *)"ossl_ssl_ex_ptr_idx",0,0,0);

    /* Document-module: OpenSSL::SSL
     *
     * Use SSLContext to set up the parameters for a TLS (former SSL)
     * connection. Both client and server TLS connections are supported,
     * SSLSocket and SSLServer may be used in conjunction with an instance
     * of SSLContext to set up connections.
     */
    mSSL = rb_define_module_under(mOSSL, "SSL");

    /* Document-module: OpenSSL::ExtConfig
     *
     * This module contains configuration information about the SSL extension,
     * for example if socket support is enabled, or the host name TLS extension
     * is enabled.  Constants in this module will always be defined, but contain
     * `true` or `false` values depending on the configuration of your OpenSSL
     * installation.
     */
    mSSLExtConfig = rb_define_module_under(mOSSL, "ExtConfig");

    /* Document-class: OpenSSL::SSL::SSLError
     *
     * Generic error class raised by SSLSocket and SSLContext.
     */
    eSSLError = rb_define_class_under(mSSL, "SSLError", eOSSLError);
    eSSLErrorWaitReadable = rb_define_class_under(mSSL, "SSLErrorWaitReadable", eSSLError);
    rb_include_module(eSSLErrorWaitReadable, rb_mWaitReadable);
    eSSLErrorWaitWritable = rb_define_class_under(mSSL, "SSLErrorWaitWritable", eSSLError);
    rb_include_module(eSSLErrorWaitWritable, rb_mWaitWritable);

    Init_ossl_ssl_session();

    /* Document-class: OpenSSL::SSL::SSLContext
     *
     * An SSLContext is used to set various options regarding certificates,
     * algorithms, verification, session caching, etc.  The SSLContext is
     * used to create an SSLSocket.
     *
     * All attributes must be set before creating an SSLSocket as the
     * SSLContext will be frozen afterward.
     *
     * The following attributes are available but don't show up in rdoc:
     * * ssl_version, cert, key, client_ca, ca_file, ca_path, timeout,
     * * verify_mode, verify_depth client_cert_cb, tmp_dh_callback,
     * * session_id_context, session_add_cb, session_new_cb, session_remove_cb
     */
    cSSLContext = rb_define_class_under(mSSL, "SSLContext", rb_cObject);
    rb_define_alloc_func(cSSLContext, ossl_sslctx_s_alloc);

    /*
     * Context certificate
     */
    rb_attr(cSSLContext, rb_intern("cert"), 1, 1, Qfalse);

    /*
     * Context private key
     */
    rb_attr(cSSLContext, rb_intern("key"), 1, 1, Qfalse);

    /*
     * A certificate or Array of certificates that will be sent to the client.
     */
    rb_attr(cSSLContext, rb_intern("client_ca"), 1, 1, Qfalse);

    /*
     * The path to a file containing a PEM-format CA certificate
     */
    rb_attr(cSSLContext, rb_intern("ca_file"), 1, 1, Qfalse);

    /*
     * The path to a directory containing CA certificates in PEM format.
     *
     * Files are looked up by subject's X509 name's hash value.
     */
    rb_attr(cSSLContext, rb_intern("ca_path"), 1, 1, Qfalse);

    /*
     * Maximum session lifetime.
     */
    rb_attr(cSSLContext, rb_intern("timeout"), 1, 1, Qfalse);

    /*
     * Session verification mode.
     *
     * Valid modes are VERIFY_NONE, VERIFY_PEER, VERIFY_CLIENT_ONCE,
     * VERIFY_FAIL_IF_NO_PEER_CERT and defined on OpenSSL::SSL
     */
    rb_attr(cSSLContext, rb_intern("verify_mode"), 1, 1, Qfalse);

    /*
     * Number of CA certificates to walk when verifying a certificate chain.
     */
    rb_attr(cSSLContext, rb_intern("verify_depth"), 1, 1, Qfalse);

    /*
     * A callback for additional certificate verification.  The callback is
     * invoked for each certificate in the chain.
     *
     * The callback is invoked with two values.  +preverify_ok+ indicates
     * indicates if the verification was passed (true) or not (false).
     * +store_context+ is an OpenSSL::X509::StoreContext containing the
     * context used for certificate verification.
     *
     * If the callback returns false verification is stopped.
     */
    rb_attr(cSSLContext, rb_intern("verify_callback"), 1, 1, Qfalse);

    /*
     * An OpenSSL::X509::Store used for certificate verification
     */
    rb_attr(cSSLContext, rb_intern("cert_store"), 1, 1, Qfalse);

    /*
     * An Array of extra X509 certificates to be added to the certificate
     * chain.
     */
    rb_attr(cSSLContext, rb_intern("extra_chain_cert"), 1, 1, Qfalse);

    /*
     * A callback invoked when a client certificate is requested by a server
     * and no certificate has been set.
     *
     * The callback is invoked with a Session and must return an Array
     * containing an OpenSSL::X509::Certificate and an OpenSSL::PKey.  If any
     * other value is returned the handshake is suspended.
     */
    rb_attr(cSSLContext, rb_intern("client_cert_cb"), 1, 1, Qfalse);

    /*
     * A callback invoked when ECDH parameters are required.
     *
     * The callback is invoked with the Session for the key exchange, an
     * flag indicating the use of an export cipher and the keylength
     * required.
     *
     * The callback must return an OpenSSL::PKey::EC instance of the correct
     * key length.
     */
    rb_attr(cSSLContext, rb_intern("tmp_ecdh_callback"), 1, 1, Qfalse);

    /*
     * Sets the context in which a session can be reused.  This allows
     * sessions for multiple applications to be distinguished, for example, by
     * name.
     */
    rb_attr(cSSLContext, rb_intern("session_id_context"), 1, 1, Qfalse);

    /*
     * A callback invoked on a server when a session is proposed by the client
     * but the session could not be found in the server's internal cache.
     *
     * The callback is invoked with the SSLSocket and session id.  The
     * callback may return a Session from an external cache.
     */
    rb_attr(cSSLContext, rb_intern("session_get_cb"), 1, 1, Qfalse);

    /*
     * A callback invoked when a new session was negotiated.
     *
     * The callback is invoked with an SSLSocket.  If false is returned the
     * session will be removed from the internal cache.
     */
    rb_attr(cSSLContext, rb_intern("session_new_cb"), 1, 1, Qfalse);

    /*
     * A callback invoked when a session is removed from the internal cache.
     *
     * The callback is invoked with an SSLContext and a Session.
     */
    rb_attr(cSSLContext, rb_intern("session_remove_cb"), 1, 1, Qfalse);

#ifdef HAVE_SSL_SET_TLSEXT_HOST_NAME
    rb_define_const(mSSLExtConfig, "HAVE_TLSEXT_HOST_NAME", Qtrue);
#else
    rb_define_const(mSSLExtConfig, "HAVE_TLSEXT_HOST_NAME", Qfalse);
#endif

#ifdef TLS_DH_anon_WITH_AES_256_GCM_SHA384
    rb_define_const(mSSLExtConfig, "TLS_DH_anon_WITH_AES_256_GCM_SHA384", Qtrue);
#else
    rb_define_const(mSSLExtConfig, "TLS_DH_anon_WITH_AES_256_GCM_SHA384", Qfalse);
#endif

    /*
     * A callback invoked whenever a new handshake is initiated. May be used
     * to disable renegotiation entirely.
     *
     * The callback is invoked with the active SSLSocket. The callback's
     * return value is irrelevant, normal return indicates "approval" of the
     * renegotiation and will continue the process. To forbid renegotiation
     * and to cancel the process, an Error may be raised within the callback.
     *
     * === Disable client renegotiation
     *
     * When running a server, it is often desirable to disable client
     * renegotiation entirely. You may use a callback as follows to implement
     * this feature:
     *
     *   num_handshakes = 0
     *   ctx.renegotiation_cb = lambda do |ssl|
     *     num_handshakes += 1
     *     raise RuntimeError.new("Client renegotiation disabled") if num_handshakes > 1
     *   end
     */
    rb_attr(cSSLContext, rb_intern("renegotiation_cb"), 1, 1, Qfalse);
#ifdef HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB
    /*
     * An Enumerable of Strings. Each String represents a protocol to be
     * advertised as the list of supported protocols for Next Protocol
     * Negotiation. Supported in OpenSSL 1.0.1 and higher. Has no effect
     * on the client side. If not set explicitly, the NPN extension will
     * not be sent by the server in the handshake.
     *
     * === Example
     *
     *   ctx.npn_protocols = ["http/1.1", "spdy/2"]
     */
    rb_attr(cSSLContext, rb_intern("npn_protocols"), 1, 1, Qfalse);
    /*
     * A callback invoked on the client side when the client needs to select
     * a protocol from the list sent by the server. Supported in OpenSSL 1.0.1
     * and higher. The client MUST select a protocol of those advertised by
     * the server. If none is acceptable, raising an error in the callback
     * will cause the handshake to fail. Not setting this callback explicitly
     * means not supporting the NPN extension on the client - any protocols
     * advertised by the server will be ignored.
     *
     * === Example
     *
     *   ctx.npn_select_cb = lambda do |protocols|
     *     #inspect the protocols and select one
     *     protocols.first
     *   end
     */
    rb_attr(cSSLContext, rb_intern("npn_select_cb"), 1, 1, Qfalse);
#endif

#ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
    /*
     * An Enumerable of Strings. Each String represents a protocol to be
     * advertised as the list of supported protocols for Application-Layer Protocol
     * Negotiation. Supported in OpenSSL 1.0.1 and higher. Has no effect
     * on the client side. If not set explicitly, the NPN extension will
     * not be sent by the server in the handshake.
     *
     * === Example
     *
     *   ctx.alpn_protocols = ["http/1.1", "spdy/2", "h2"]
     */
    rb_attr(cSSLContext, rb_intern("alpn_protocols"), 1, 1, Qfalse);
    /*
     * A callback invoked on the server side when the server needs to select
     * a protocol from the list sent by the client. Supported in OpenSSL 1.0.2
     * and higher. The server MUST select a protocol of those advertised by
     * the client. If none is acceptable, raising an error in the callback
     * will cause the handshake to fail. Not setting this callback explicitly
     * means not supporting the ALPN extension on the client - any protocols
     * advertised by the server will be ignored.
     *
     * === Example
     *
     *   ctx.alpn_select_cb = lambda do |protocols|
     *     #inspect the protocols and select one
     *     protocols.first
     *   end
     */
    rb_attr(cSSLContext, rb_intern("alpn_select_cb"), 1, 1, Qfalse);
#endif

    rb_define_alias(cSSLContext, "ssl_timeout", "timeout");
    rb_define_alias(cSSLContext, "ssl_timeout=", "timeout=");
    rb_define_method(cSSLContext, "ssl_version=", ossl_sslctx_set_ssl_version, 1);
    rb_define_method(cSSLContext, "ciphers",     ossl_sslctx_get_ciphers, 0);
    rb_define_method(cSSLContext, "ciphers=",    ossl_sslctx_set_ciphers, 1);

    rb_define_method(cSSLContext, "setup", ossl_sslctx_setup, 0);

    /*
     * No session caching for client or server
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_OFF", LONG2FIX(SSL_SESS_CACHE_OFF));

    /*
     * Client sessions are added to the session cache
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_CLIENT", LONG2FIX(SSL_SESS_CACHE_CLIENT)); /* doesn't actually do anything in 0.9.8e */

    /*
     * Server sessions are added to the session cache
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_SERVER", LONG2FIX(SSL_SESS_CACHE_SERVER));

    /*
     * Both client and server sessions are added to the session cache
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_BOTH", LONG2FIX(SSL_SESS_CACHE_BOTH)); /* no different than CACHE_SERVER in 0.9.8e */

    /*
     * Normally the session cache is checked for expired sessions every 255
     * connections.  Since this may lead to a delay that cannot be controlled,
     * the automatic flushing may be disabled and #flush_sessions can be
     * called explicitly.
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_AUTO_CLEAR", LONG2FIX(SSL_SESS_CACHE_NO_AUTO_CLEAR));

    /*
     * Always perform external lookups of sessions even if they are in the
     * internal cache.
     *
     * This flag has no effect on clients
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL_LOOKUP", LONG2FIX(SSL_SESS_CACHE_NO_INTERNAL_LOOKUP));

    /*
     * Never automatically store sessions in the internal store.
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL_STORE", LONG2FIX(SSL_SESS_CACHE_NO_INTERNAL_STORE));

    /*
     * Enables both SESSION_CACHE_NO_INTERNAL_LOOKUP and
     * SESSION_CACHE_NO_INTERNAL_STORE.
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL", LONG2FIX(SSL_SESS_CACHE_NO_INTERNAL));

    rb_define_method(cSSLContext, "session_add",     ossl_sslctx_session_add, 1);
    rb_define_method(cSSLContext, "session_remove",     ossl_sslctx_session_remove, 1);
    rb_define_method(cSSLContext, "session_cache_mode",     ossl_sslctx_get_session_cache_mode, 0);
    rb_define_method(cSSLContext, "session_cache_mode=",     ossl_sslctx_set_session_cache_mode, 1);
    rb_define_method(cSSLContext, "session_cache_size",     ossl_sslctx_get_session_cache_size, 0);
    rb_define_method(cSSLContext, "session_cache_size=",     ossl_sslctx_set_session_cache_size, 1);
    rb_define_method(cSSLContext, "session_cache_stats",     ossl_sslctx_get_session_cache_stats, 0);
    rb_define_method(cSSLContext, "flush_sessions",     ossl_sslctx_flush_sessions, -1);
    rb_define_method(cSSLContext, "options",     ossl_sslctx_get_options, 0);
    rb_define_method(cSSLContext, "options=",     ossl_sslctx_set_options, 1);

    ary = rb_ary_new2(numberof(ossl_ssl_method_tab));
    for (i = 0; i < numberof(ossl_ssl_method_tab); i++) {
        rb_ary_push(ary, ID2SYM(rb_intern(ossl_ssl_method_tab[i].name)));
    }
    rb_obj_freeze(ary);
    /* The list of available SSL/TLS methods */
    rb_define_const(cSSLContext, "METHODS", ary);

    /*
     * Document-class: OpenSSL::SSL::SSLSocket
     *
     * The following attributes are available but don't show up in rdoc.
     * * io, context, sync_close
     *
     */
    cSSLSocket = rb_define_class_under(mSSL, "SSLSocket", rb_cObject);
#ifdef OPENSSL_NO_SOCK
    rb_define_const(mSSLExtConfig, "OPENSSL_NO_SOCK", Qtrue);
#else
    rb_define_const(mSSLExtConfig, "OPENSSL_NO_SOCK", Qfalse);
    rb_define_alloc_func(cSSLSocket, ossl_ssl_s_alloc);
    rb_define_method(cSSLSocket, "connect",    ossl_ssl_connect, 0);
    rb_define_method(cSSLSocket, "connect_nonblock",    ossl_ssl_connect_nonblock, -1);
    rb_define_method(cSSLSocket, "accept",     ossl_ssl_accept, 0);
    rb_define_method(cSSLSocket, "accept_nonblock", ossl_ssl_accept_nonblock, -1);
    rb_define_method(cSSLSocket, "sysread",    ossl_ssl_read, -1);
    rb_define_private_method(cSSLSocket, "sysread_nonblock",    ossl_ssl_read_nonblock, -1);
    rb_define_method(cSSLSocket, "syswrite",   ossl_ssl_write, 1);
    rb_define_private_method(cSSLSocket, "syswrite_nonblock",    ossl_ssl_write_nonblock, -1);
    rb_define_private_method(cSSLSocket, "stop",   ossl_ssl_stop, 0);
    rb_define_method(cSSLSocket, "cert",       ossl_ssl_get_cert, 0);
    rb_define_method(cSSLSocket, "peer_cert",  ossl_ssl_get_peer_cert, 0);
    rb_define_method(cSSLSocket, "peer_cert_chain", ossl_ssl_get_peer_cert_chain, 0);
    rb_define_method(cSSLSocket, "ssl_version",    ossl_ssl_get_version, 0);
    rb_define_method(cSSLSocket, "cipher",     ossl_ssl_get_cipher, 0);
    rb_define_method(cSSLSocket, "state",      ossl_ssl_get_state, 0);
    rb_define_method(cSSLSocket, "pending",    ossl_ssl_pending, 0);
    rb_define_method(cSSLSocket, "session_reused?",    ossl_ssl_session_reused, 0);
    /* implementation of OpenSSL::SSL::SSLSocket#session is in lib/openssl/ssl.rb */
    rb_define_method(cSSLSocket, "session=",    ossl_ssl_set_session, 1);
    rb_define_method(cSSLSocket, "verify_result", ossl_ssl_get_verify_result, 0);
    rb_define_method(cSSLSocket, "client_ca", ossl_ssl_get_client_ca_list, 0);
# ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
    rb_define_method(cSSLSocket, "alpn_protocol", ossl_ssl_alpn_protocol, 0);
# endif
# ifdef HAVE_SSL_CTX_SET_NEXT_PROTO_SELECT_CB
    rb_define_method(cSSLSocket, "npn_protocol", ossl_ssl_npn_protocol, 0);
# endif
#endif

#define ossl_ssl_def_const(x) rb_define_const(mSSL, #x, LONG2NUM(SSL_##x))

    ossl_ssl_def_const(VERIFY_NONE);
    ossl_ssl_def_const(VERIFY_PEER);
    ossl_ssl_def_const(VERIFY_FAIL_IF_NO_PEER_CERT);
    ossl_ssl_def_const(VERIFY_CLIENT_ONCE);
    /* Introduce constants included in OP_ALL.  These constants are mostly for
     * unset some bits in OP_ALL such as;
     *   ctx.options = OP_ALL & ~OP_DONT_INSERT_EMPTY_FRAGMENTS
     */
    ossl_ssl_def_const(OP_MICROSOFT_SESS_ID_BUG);
    ossl_ssl_def_const(OP_NETSCAPE_CHALLENGE_BUG);
    ossl_ssl_def_const(OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG);
    ossl_ssl_def_const(OP_SSLREF2_REUSE_CERT_TYPE_BUG);
    ossl_ssl_def_const(OP_MICROSOFT_BIG_SSLV3_BUFFER);
#if defined(SSL_OP_MSIE_SSLV2_RSA_PADDING)
    ossl_ssl_def_const(OP_MSIE_SSLV2_RSA_PADDING);
#endif
    ossl_ssl_def_const(OP_SSLEAY_080_CLIENT_DH_BUG);
    ossl_ssl_def_const(OP_TLS_D5_BUG);
    ossl_ssl_def_const(OP_TLS_BLOCK_PADDING_BUG);
    ossl_ssl_def_const(OP_DONT_INSERT_EMPTY_FRAGMENTS);
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
#if defined(SSL_OP_NO_TLSv1_1)
    ossl_ssl_def_const(OP_NO_TLSv1_1);
#endif
#if defined(SSL_OP_NO_TLSv1_2)
    ossl_ssl_def_const(OP_NO_TLSv1_2);
#endif
#if defined(SSL_OP_NO_TICKET)
    ossl_ssl_def_const(OP_NO_TICKET);
#endif
#if defined(SSL_OP_NO_COMPRESSION)
    ossl_ssl_def_const(OP_NO_COMPRESSION);
#endif
    ossl_ssl_def_const(OP_PKCS1_CHECK_1);
    ossl_ssl_def_const(OP_PKCS1_CHECK_2);
    ossl_ssl_def_const(OP_NETSCAPE_CA_DN_BUG);
    ossl_ssl_def_const(OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG);

#undef rb_intern
    sym_exception = ID2SYM(rb_intern("exception"));
    sym_wait_readable = ID2SYM(rb_intern("wait_readable"));
    sym_wait_writable = ID2SYM(rb_intern("wait_writable"));
}
