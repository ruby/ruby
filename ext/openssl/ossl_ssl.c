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

static ID id_call, ID_callback_state, id_tmp_dh_callback, id_tmp_ecdh_callback,
	  id_npn_protocols_encoded;
static VALUE sym_exception, sym_wait_readable, sym_wait_writable;

static ID id_i_cert_store, id_i_ca_file, id_i_ca_path, id_i_verify_mode,
	  id_i_verify_depth, id_i_verify_callback, id_i_client_ca,
	  id_i_renegotiation_cb, id_i_cert, id_i_key, id_i_extra_chain_cert,
	  id_i_client_cert_cb, id_i_tmp_ecdh_callback, id_i_timeout,
	  id_i_session_id_context, id_i_session_get_cb, id_i_session_new_cb,
	  id_i_session_remove_cb, id_i_npn_select_cb, id_i_npn_protocols,
	  id_i_alpn_select_cb, id_i_alpn_protocols, id_i_servername_cb,
	  id_i_verify_hostname;
static ID id_i_io, id_i_context, id_i_hostname;

static int ossl_ssl_ex_vcb_idx;
static int ossl_ssl_ex_ptr_idx;
static int ossl_sslctx_ex_ptr_idx;
#if !defined(HAVE_X509_STORE_UP_REF)
static int ossl_sslctx_ex_store_p;
#endif

static void
ossl_sslctx_free(void *ptr)
{
    SSL_CTX *ctx = ptr;
#if !defined(HAVE_X509_STORE_UP_REF)
    if (ctx && SSL_CTX_get_ex_data(ctx, ossl_sslctx_ex_store_p))
	ctx->cert_store = NULL;
#endif
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
    long mode = 0 |
	SSL_MODE_ENABLE_PARTIAL_WRITE |
	SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER |
	SSL_MODE_RELEASE_BUFFERS;
    VALUE obj;

    obj = TypedData_Wrap_Struct(klass, &ossl_sslctx_type, 0);
#if OPENSSL_VERSION_NUMBER >= 0x10100000 && !defined(LIBRESSL_VERSION_NUMBER)
    ctx = SSL_CTX_new(TLS_method());
#else
    ctx = SSL_CTX_new(SSLv23_method());
#endif
    if (!ctx) {
        ossl_raise(eSSLError, "SSL_CTX_new");
    }
    SSL_CTX_set_mode(ctx, mode);
    RTYPEDDATA_DATA(obj) = ctx;
    SSL_CTX_set_ex_data(ctx, ossl_sslctx_ex_ptr_idx, (void *)obj);

#if !defined(OPENSSL_NO_EC) && defined(HAVE_SSL_CTX_SET_ECDH_AUTO)
    /* We use SSL_CTX_set1_curves_list() to specify the curve used in ECDH. It
     * allows to specify multiple curve names and OpenSSL will select
     * automatically from them. In OpenSSL 1.0.2, the automatic selection has to
     * be enabled explicitly. But OpenSSL 1.1.0 removed the knob and it is
     * always enabled. To uniform the behavior, we enable the automatic
     * selection also in 1.0.2. Users can still disable ECDH by removing ECDH
     * cipher suites by SSLContext#ciphers=. */
    if (!SSL_CTX_set_ecdh_auto(ctx, 1))
	ossl_raise(eSSLError, "SSL_CTX_set_ecdh_auto");
#endif

    return obj;
}

static int
parse_proto_version(VALUE str)
{
    int i;
    static const struct {
	const char *name;
	int version;
    } map[] = {
	{ "SSL2", SSL2_VERSION },
	{ "SSL3", SSL3_VERSION },
	{ "TLS1", TLS1_VERSION },
	{ "TLS1_1", TLS1_1_VERSION },
	{ "TLS1_2", TLS1_2_VERSION },
#ifdef TLS1_3_VERSION
	{ "TLS1_3", TLS1_3_VERSION },
#endif
    };

    if (NIL_P(str))
	return 0;
    if (RB_INTEGER_TYPE_P(str))
	return NUM2INT(str);

    if (SYMBOL_P(str))
	str = rb_sym2str(str);
    StringValue(str);
    for (i = 0; i < numberof(map); i++)
	if (!strncmp(map[i].name, RSTRING_PTR(str), RSTRING_LEN(str)))
	    return map[i].version;
    rb_raise(rb_eArgError, "unrecognized version %+"PRIsVALUE, str);
}

/*
 * call-seq:
 *    ctx.set_minmax_proto_version(min, max) -> nil
 *
 * Sets the minimum and maximum supported protocol versions. See #min_version=
 * and #max_version=.
 */
static VALUE
ossl_sslctx_set_minmax_proto_version(VALUE self, VALUE min_v, VALUE max_v)
{
    SSL_CTX *ctx;
    int min, max;

    GetSSLCTX(self, ctx);
    min = parse_proto_version(min_v);
    max = parse_proto_version(max_v);

#ifdef HAVE_SSL_CTX_SET_MIN_PROTO_VERSION
    if (!SSL_CTX_set_min_proto_version(ctx, min))
	ossl_raise(eSSLError, "SSL_CTX_set_min_proto_version");
    if (!SSL_CTX_set_max_proto_version(ctx, max))
	ossl_raise(eSSLError, "SSL_CTX_set_max_proto_version");
#else
    {
	unsigned long sum = 0, opts = 0;
	int i;
	static const struct {
	    int ver;
	    unsigned long opts;
	} options_map[] = {
	    { SSL2_VERSION, SSL_OP_NO_SSLv2 },
	    { SSL3_VERSION, SSL_OP_NO_SSLv3 },
	    { TLS1_VERSION, SSL_OP_NO_TLSv1 },
	    { TLS1_1_VERSION, SSL_OP_NO_TLSv1_1 },
	    { TLS1_2_VERSION, SSL_OP_NO_TLSv1_2 },
# if defined(TLS1_3_VERSION)
	    { TLS1_3_VERSION, SSL_OP_NO_TLSv1_3 },
# endif
	};

	for (i = 0; i < numberof(options_map); i++) {
	    sum |= options_map[i].opts;
            if ((min && min > options_map[i].ver) ||
                (max && max < options_map[i].ver)) {
		opts |= options_map[i].opts;
            }
	}
	SSL_CTX_clear_options(ctx, sum);
	SSL_CTX_set_options(ctx, opts);
    }
#endif

    return Qnil;
}

static VALUE
ossl_call_client_cert_cb(VALUE obj)
{
    VALUE ctx_obj, cb, ary, cert, key;

    ctx_obj = rb_attr_get(obj, id_i_context);
    cb = rb_attr_get(ctx_obj, id_i_client_cert_cb);
    if (NIL_P(cb))
	return Qnil;

    ary = rb_funcallv(cb, id_call, 1, &obj);
    Check_Type(ary, T_ARRAY);
    GetX509CertPtr(cert = rb_ary_entry(ary, 0));
    GetPrivPKeyPtr(key = rb_ary_entry(ary, 1));

    return rb_ary_new3(2, cert, key);
}

static int
ossl_client_cert_cb(SSL *ssl, X509 **x509, EVP_PKEY **pkey)
{
    VALUE obj, ret;

    obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    ret = rb_protect(ossl_call_client_cert_cb, obj, NULL);
    if (NIL_P(ret))
	return 0;

    *x509 = DupX509CertPtr(RARRAY_AREF(ret, 0));
    *pkey = DupPKeyPtr(RARRAY_AREF(ret, 1));

    return 1;
}

#if !defined(OPENSSL_NO_DH) || \
    !defined(OPENSSL_NO_EC) && defined(HAVE_SSL_CTX_SET_TMP_ECDH_CALLBACK)
struct tmp_dh_callback_args {
    VALUE ssl_obj;
    ID id;
    int type;
    int is_export;
    int keylength;
};

static EVP_PKEY *
ossl_call_tmp_dh_callback(struct tmp_dh_callback_args *args)
{
    VALUE cb, dh;
    EVP_PKEY *pkey;

    cb = rb_funcall(args->ssl_obj, args->id, 0);
    if (NIL_P(cb))
	return NULL;
    dh = rb_funcall(cb, id_call, 3, args->ssl_obj, INT2NUM(args->is_export),
		    INT2NUM(args->keylength));
    pkey = GetPKeyPtr(dh);
    if (EVP_PKEY_base_id(pkey) != args->type)
	return NULL;

    return pkey;
}
#endif

#if !defined(OPENSSL_NO_DH)
static DH *
ossl_tmp_dh_callback(SSL *ssl, int is_export, int keylength)
{
    VALUE rb_ssl;
    EVP_PKEY *pkey;
    struct tmp_dh_callback_args args;
    int state;

    rb_ssl = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    args.ssl_obj = rb_ssl;
    args.id = id_tmp_dh_callback;
    args.is_export = is_export;
    args.keylength = keylength;
    args.type = EVP_PKEY_DH;

    pkey = (EVP_PKEY *)rb_protect((VALUE (*)(VALUE))ossl_call_tmp_dh_callback,
				  (VALUE)&args, &state);
    if (state) {
	rb_ivar_set(rb_ssl, ID_callback_state, INT2NUM(state));
	return NULL;
    }
    if (!pkey)
	return NULL;

    return EVP_PKEY_get0_DH(pkey);
}
#endif /* OPENSSL_NO_DH */

#if !defined(OPENSSL_NO_EC) && defined(HAVE_SSL_CTX_SET_TMP_ECDH_CALLBACK)
static EC_KEY *
ossl_tmp_ecdh_callback(SSL *ssl, int is_export, int keylength)
{
    VALUE rb_ssl;
    EVP_PKEY *pkey;
    struct tmp_dh_callback_args args;
    int state;

    rb_ssl = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    args.ssl_obj = rb_ssl;
    args.id = id_tmp_ecdh_callback;
    args.is_export = is_export;
    args.keylength = keylength;
    args.type = EVP_PKEY_EC;

    pkey = (EVP_PKEY *)rb_protect((VALUE (*)(VALUE))ossl_call_tmp_dh_callback,
				  (VALUE)&args, &state);
    if (state) {
	rb_ivar_set(rb_ssl, ID_callback_state, INT2NUM(state));
	return NULL;
    }
    if (!pkey)
	return NULL;

    return EVP_PKEY_get0_EC_KEY(pkey);
}
#endif

static VALUE
call_verify_certificate_identity(VALUE ctx_v)
{
    X509_STORE_CTX *ctx = (X509_STORE_CTX *)ctx_v;
    SSL *ssl;
    VALUE ssl_obj, hostname, cert_obj;

    ssl = X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
    ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    hostname = rb_attr_get(ssl_obj, id_i_hostname);

    if (!RTEST(hostname)) {
	rb_warning("verify_hostname requires hostname to be set");
	return Qtrue;
    }

    cert_obj = ossl_x509_new(X509_STORE_CTX_get_current_cert(ctx));
    return rb_funcall(mSSL, rb_intern("verify_certificate_identity"), 2,
		      cert_obj, hostname);
}

static int
ossl_ssl_verify_callback(int preverify_ok, X509_STORE_CTX *ctx)
{
    VALUE cb, ssl_obj, sslctx_obj, verify_hostname, ret;
    SSL *ssl;
    int status;

    ssl = X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
    cb = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_vcb_idx);
    ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    sslctx_obj = rb_attr_get(ssl_obj, id_i_context);
    verify_hostname = rb_attr_get(sslctx_obj, id_i_verify_hostname);

    if (preverify_ok && RTEST(verify_hostname) && !SSL_is_server(ssl) &&
	!X509_STORE_CTX_get_error_depth(ctx)) {
	ret = rb_protect(call_verify_certificate_identity, (VALUE)ctx, &status);
	if (status) {
	    rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(status));
	    return 0;
	}
	preverify_ok = ret == Qtrue;
    }

    return ossl_verify_cb_call(cb, preverify_ok, ctx);
}

static VALUE
ossl_call_session_get_cb(VALUE ary)
{
    VALUE ssl_obj, cb;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    cb = rb_funcall(ssl_obj, rb_intern("session_get_cb"), 0);
    if (NIL_P(cb)) return Qnil;

    return rb_funcallv(cb, id_call, 1, &ary);
}

static SSL_SESSION *
#if (!defined(LIBRESSL_VERSION_NUMBER) ? OPENSSL_VERSION_NUMBER >= 0x10100000 : LIBRESSL_VERSION_NUMBER >= 0x2080000f)
ossl_sslctx_session_get_cb(SSL *ssl, const unsigned char *buf, int len, int *copy)
#else
ossl_sslctx_session_get_cb(SSL *ssl, unsigned char *buf, int len, int *copy)
#endif
{
    VALUE ary, ssl_obj, ret_obj;
    SSL_SESSION *sess;
    int state = 0;

    OSSL_Debug("SSL SESSION get callback entered");
    ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
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

    GetSSLSession(ret_obj, sess);
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

    return rb_funcallv(cb, id_call, 1, &ary);
}

/* return 1 normal.  return 0 removes the session */
static int
ossl_sslctx_session_new_cb(SSL *ssl, SSL_SESSION *sess)
{
    VALUE ary, ssl_obj, sess_obj;
    int state = 0;

    OSSL_Debug("SSL SESSION new callback entered");

    ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    sess_obj = rb_obj_alloc(cSSLSession);
    SSL_SESSION_up_ref(sess);
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

    cb = rb_attr_get(sslctx_obj, id_i_session_remove_cb);
    if (NIL_P(cb)) return Qnil;

    return rb_funcallv(cb, id_call, 1, &ary);
}

static void
ossl_sslctx_session_remove_cb(SSL_CTX *ctx, SSL_SESSION *sess)
{
    VALUE ary, sslctx_obj, sess_obj;
    int state = 0;

    /*
     * This callback is also called for all sessions in the internal store
     * when SSL_CTX_free() is called.
     */
    if (rb_during_gc())
	return;

    OSSL_Debug("SSL SESSION remove callback entered");

    sslctx_obj = (VALUE)SSL_CTX_get_ex_data(ctx, ossl_sslctx_ex_ptr_idx);
    sess_obj = rb_obj_alloc(cSSLSession);
    SSL_SESSION_up_ref(sess);
    DATA_PTR(sess_obj) = sess;

    ary = rb_ary_new2(2);
    rb_ary_push(ary, sslctx_obj);
    rb_ary_push(ary, sess_obj);

    rb_protect(ossl_call_session_remove_cb, ary, &state);
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

static VALUE
ossl_call_servername_cb(VALUE ary)
{
    VALUE ssl_obj, sslctx_obj, cb, ret_obj;

    Check_Type(ary, T_ARRAY);
    ssl_obj = rb_ary_entry(ary, 0);

    sslctx_obj = rb_attr_get(ssl_obj, id_i_context);
    cb = rb_attr_get(sslctx_obj, id_i_servername_cb);
    if (NIL_P(cb)) return Qnil;

    ret_obj = rb_funcallv(cb, id_call, 1, &ary);
    if (rb_obj_is_kind_of(ret_obj, cSSLContext)) {
        SSL *ssl;
        SSL_CTX *ctx2;

        ossl_sslctx_setup(ret_obj);
        GetSSL(ssl_obj, ssl);
        GetSSLCTX(ret_obj, ctx2);
        SSL_set_SSL_CTX(ssl, ctx2);
        rb_ivar_set(ssl_obj, id_i_context, ret_obj);
    } else if (!NIL_P(ret_obj)) {
	ossl_raise(rb_eArgError, "servername_cb must return an "
		   "OpenSSL::SSL::SSLContext object or nil");
    }

    return ret_obj;
}

static int
ssl_servername_cb(SSL *ssl, int *ad, void *arg)
{
    VALUE ary, ssl_obj;
    int state = 0;
    const char *servername = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);

    if (!servername)
        return SSL_TLSEXT_ERR_OK;

    ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    ary = rb_ary_new2(2);
    rb_ary_push(ary, ssl_obj);
    rb_ary_push(ary, rb_str_new2(servername));

    rb_protect(ossl_call_servername_cb, ary, &state);
    if (state) {
        rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(state));
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    }

    return SSL_TLSEXT_ERR_OK;
}

static void
ssl_renegotiation_cb(const SSL *ssl)
{
    VALUE ssl_obj, sslctx_obj, cb;

    ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);
    sslctx_obj = rb_attr_get(ssl_obj, id_i_context);
    cb = rb_attr_get(sslctx_obj, id_i_renegotiation_cb);
    if (NIL_P(cb)) return;

    rb_funcallv(cb, id_call, 1, &ssl_obj);
}

#if !defined(OPENSSL_NO_NEXTPROTONEG) || \
    defined(HAVE_SSL_CTX_SET_ALPN_SELECT_CB)
static VALUE
ssl_npn_encode_protocol_i(RB_BLOCK_CALL_FUNC_ARGLIST(cur, encoded))
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
    VALUE encoded = rb_str_new(NULL, 0);
    rb_iterate(rb_each, protocols, ssl_npn_encode_protocol_i, encoded);
    return encoded;
}

struct npn_select_cb_common_args {
    VALUE cb;
    const unsigned char *in;
    unsigned inlen;
};

static VALUE
npn_select_cb_common_i(VALUE tmp)
{
    struct npn_select_cb_common_args *args = (void *)tmp;
    const unsigned char *in = args->in, *in_end = in + args->inlen;
    unsigned char l;
    long len;
    VALUE selected, protocols = rb_ary_new();

    /* assume OpenSSL verifies this format */
    /* The format is len_1|proto_1|...|len_n|proto_n */
    while (in < in_end) {
	l = *in++;
	rb_ary_push(protocols, rb_str_new((const char *)in, l));
	in += l;
    }

    selected = rb_funcallv(args->cb, id_call, 1, &protocols);
    StringValue(selected);
    len = RSTRING_LEN(selected);
    if (len < 1 || len >= 256) {
	ossl_raise(eSSLError, "Selected protocol name must have length 1..255");
    }

    return selected;
}

static int
ssl_npn_select_cb_common(SSL *ssl, VALUE cb, const unsigned char **out,
			 unsigned char *outlen, const unsigned char *in,
			 unsigned int inlen)
{
    VALUE selected;
    int status;
    struct npn_select_cb_common_args args;

    args.cb = cb;
    args.in = in;
    args.inlen = inlen;

    selected = rb_protect(npn_select_cb_common_i, (VALUE)&args, &status);
    if (status) {
	VALUE ssl_obj = (VALUE)SSL_get_ex_data(ssl, ossl_ssl_ex_ptr_idx);

	rb_ivar_set(ssl_obj, ID_callback_state, INT2NUM(status));
	return SSL_TLSEXT_ERR_ALERT_FATAL;
    }

    *out = (unsigned char *)RSTRING_PTR(selected);
    *outlen = (unsigned char)RSTRING_LEN(selected);

    return SSL_TLSEXT_ERR_OK;
}
#endif

#ifndef OPENSSL_NO_NEXTPROTONEG
static int
ssl_npn_advertise_cb(SSL *ssl, const unsigned char **out, unsigned int *outlen,
		     void *arg)
{
    VALUE protocols = (VALUE)arg;

    *out = (const unsigned char *) RSTRING_PTR(protocols);
    *outlen = RSTRING_LENINT(protocols);

    return SSL_TLSEXT_ERR_OK;
}

static int
ssl_npn_select_cb(SSL *ssl, unsigned char **out, unsigned char *outlen,
		  const unsigned char *in, unsigned int inlen, void *arg)
{
    VALUE sslctx_obj, cb;

    sslctx_obj = (VALUE) arg;
    cb = rb_attr_get(sslctx_obj, id_i_npn_select_cb);

    return ssl_npn_select_cb_common(ssl, cb, (const unsigned char **)out,
				    outlen, in, inlen);
}
#endif

#ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
static int
ssl_alpn_select_cb(SSL *ssl, const unsigned char **out, unsigned char *outlen,
		   const unsigned char *in, unsigned int inlen, void *arg)
{
    VALUE sslctx_obj, cb;

    sslctx_obj = (VALUE) arg;
    cb = rb_attr_get(sslctx_obj, id_i_alpn_select_cb);

    return ssl_npn_select_cb_common(ssl, cb, out, outlen, in, inlen);
}
#endif

/* This function may serve as the entry point to support further callbacks. */
static void
ssl_info_cb(const SSL *ssl, int where, int val)
{
    int is_server = SSL_is_server((SSL *)ssl);

    if (is_server && where & SSL_CB_HANDSHAKE_START) {
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
    /*
     * Do explicit cast because SSL_CTX_get_options() returned (signed) long in
     * OpenSSL before 1.1.0.
     */
    return ULONG2NUM((unsigned long)SSL_CTX_get_options(ctx));
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
	SSL_CTX_set_options(ctx, NUM2ULONG(options));
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
    /* We added SSLContext#tmp_ecdh_callback= in Ruby 2.3.0,
     * but SSL_CTX_set_tmp_ecdh_callback() was removed in OpenSSL 1.1.0. */
    if (RTEST(rb_attr_get(self, id_i_tmp_ecdh_callback))) {
# if defined(HAVE_SSL_CTX_SET_TMP_ECDH_CALLBACK)
	rb_warn("#tmp_ecdh_callback= is deprecated; use #ecdh_curves= instead");
	SSL_CTX_set_tmp_ecdh_callback(ctx, ossl_tmp_ecdh_callback);
#  if defined(HAVE_SSL_CTX_SET_ECDH_AUTO)
	/* tmp_ecdh_callback and ecdh_auto conflict; OpenSSL ignores
	 * tmp_ecdh_callback. So disable ecdh_auto. */
	if (!SSL_CTX_set_ecdh_auto(ctx, 0))
	    ossl_raise(eSSLError, "SSL_CTX_set_ecdh_auto");
#  endif
# else
	ossl_raise(eSSLError, "OpenSSL does not support tmp_ecdh_callback; "
		   "use #ecdh_curves= instead");
# endif
    }
#endif /* OPENSSL_NO_EC */

    val = rb_attr_get(self, id_i_cert_store);
    if (!NIL_P(val)) {
	X509_STORE *store = GetX509StorePtr(val); /* NO NEED TO DUP */
	SSL_CTX_set_cert_store(ctx, store);
#if !defined(HAVE_X509_STORE_UP_REF)
	/*
         * WORKAROUND:
	 *   X509_STORE can count references, but
	 *   X509_STORE_free() doesn't care it.
	 *   So we won't increment it but mark it by ex_data.
	 */
        SSL_CTX_set_ex_data(ctx, ossl_sslctx_ex_store_p, ctx);
#else /* Fixed in OpenSSL 1.0.2; bff9ce4db38b (master), 5b4b9ce976fc (1.0.2) */
	X509_STORE_up_ref(store);
#endif
    }

    val = rb_attr_get(self, id_i_extra_chain_cert);
    if(!NIL_P(val)){
	rb_block_call(val, rb_intern("each"), 0, 0, ossl_sslctx_add_extra_chain_cert_i, self);
    }

    /* private key may be bundled in certificate file. */
    val = rb_attr_get(self, id_i_cert);
    cert = NIL_P(val) ? NULL : GetX509CertPtr(val); /* NO DUP NEEDED */
    val = rb_attr_get(self, id_i_key);
    key = NIL_P(val) ? NULL : GetPrivPKeyPtr(val); /* NO DUP NEEDED */
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

    val = rb_attr_get(self, id_i_client_ca);
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

    val = rb_attr_get(self, id_i_ca_file);
    ca_file = NIL_P(val) ? NULL : StringValueCStr(val);
    val = rb_attr_get(self, id_i_ca_path);
    ca_path = NIL_P(val) ? NULL : StringValueCStr(val);
    if(ca_file || ca_path){
	if (!SSL_CTX_load_verify_locations(ctx, ca_file, ca_path))
	    rb_warning("can't set verify locations");
    }

    val = rb_attr_get(self, id_i_verify_mode);
    verify_mode = NIL_P(val) ? SSL_VERIFY_NONE : NUM2INT(val);
    SSL_CTX_set_verify(ctx, verify_mode, ossl_ssl_verify_callback);
    if (RTEST(rb_attr_get(self, id_i_client_cert_cb)))
	SSL_CTX_set_client_cert_cb(ctx, ossl_client_cert_cb);

    val = rb_attr_get(self, id_i_timeout);
    if(!NIL_P(val)) SSL_CTX_set_timeout(ctx, NUM2LONG(val));

    val = rb_attr_get(self, id_i_verify_depth);
    if(!NIL_P(val)) SSL_CTX_set_verify_depth(ctx, NUM2INT(val));

#ifndef OPENSSL_NO_NEXTPROTONEG
    val = rb_attr_get(self, id_i_npn_protocols);
    if (!NIL_P(val)) {
	VALUE encoded = ssl_encode_npn_protocols(val);
	rb_ivar_set(self, id_npn_protocols_encoded, encoded);
	SSL_CTX_set_next_protos_advertised_cb(ctx, ssl_npn_advertise_cb, (void *)encoded);
	OSSL_Debug("SSL NPN advertise callback added");
    }
    if (RTEST(rb_attr_get(self, id_i_npn_select_cb))) {
	SSL_CTX_set_next_proto_select_cb(ctx, ssl_npn_select_cb, (void *) self);
	OSSL_Debug("SSL NPN select callback added");
    }
#endif

#ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
    val = rb_attr_get(self, id_i_alpn_protocols);
    if (!NIL_P(val)) {
	VALUE rprotos = ssl_encode_npn_protocols(val);

	/* returns 0 on success */
	if (SSL_CTX_set_alpn_protos(ctx, (unsigned char *)RSTRING_PTR(rprotos),
				    RSTRING_LENINT(rprotos)))
	    ossl_raise(eSSLError, "SSL_CTX_set_alpn_protos");
	OSSL_Debug("SSL ALPN values added");
    }
    if (RTEST(rb_attr_get(self, id_i_alpn_select_cb))) {
	SSL_CTX_set_alpn_select_cb(ctx, ssl_alpn_select_cb, (void *) self);
	OSSL_Debug("SSL ALPN select callback added");
    }
#endif

    rb_obj_freeze(self);

    val = rb_attr_get(self, id_i_session_id_context);
    if (!NIL_P(val)){
	StringValue(val);
	if (!SSL_CTX_set_session_id_context(ctx, (unsigned char *)RSTRING_PTR(val),
					    RSTRING_LENINT(val))){
	    ossl_raise(eSSLError, "SSL_CTX_set_session_id_context");
	}
    }

    if (RTEST(rb_attr_get(self, id_i_session_get_cb))) {
	SSL_CTX_sess_set_get_cb(ctx, ossl_sslctx_session_get_cb);
	OSSL_Debug("SSL SESSION get callback added");
    }
    if (RTEST(rb_attr_get(self, id_i_session_new_cb))) {
	SSL_CTX_sess_set_new_cb(ctx, ossl_sslctx_session_new_cb);
	OSSL_Debug("SSL SESSION new callback added");
    }
    if (RTEST(rb_attr_get(self, id_i_session_remove_cb))) {
	SSL_CTX_sess_set_remove_cb(ctx, ossl_sslctx_session_remove_cb);
	OSSL_Debug("SSL SESSION remove callback added");
    }

    val = rb_attr_get(self, id_i_servername_cb);
    if (!NIL_P(val)) {
        SSL_CTX_set_tlsext_servername_callback(ctx, ssl_servername_cb);
	OSSL_Debug("SSL TLSEXT servername callback added");
    }

    return Qtrue;
}

static VALUE
ossl_ssl_cipher_to_ary(const SSL_CIPHER *cipher)
{
    VALUE ary;
    int bits, alg_bits;

    ary = rb_ary_new2(4);
    rb_ary_push(ary, rb_str_new2(SSL_CIPHER_get_name(cipher)));
    rb_ary_push(ary, rb_str_new2(SSL_CIPHER_get_version(cipher)));
    bits = SSL_CIPHER_get_bits(cipher, &alg_bits);
    rb_ary_push(ary, INT2NUM(bits));
    rb_ary_push(ary, INT2NUM(alg_bits));

    return ary;
}

/*
 * call-seq:
 *    ctx.ciphers => [[name, version, bits, alg_bits], ...]
 *
 * The list of cipher suites configured for this context.
 */
static VALUE
ossl_sslctx_get_ciphers(VALUE self)
{
    SSL_CTX *ctx;
    STACK_OF(SSL_CIPHER) *ciphers;
    const SSL_CIPHER *cipher;
    VALUE ary;
    int i, num;

    GetSSLCTX(self, ctx);
    ciphers = SSL_CTX_get_ciphers(ctx);
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
 * Sets the list of available cipher suites for this context.  Note in a server
 * context some ciphers require the appropriate certificates.  For example, an
 * RSA cipher suite can only be chosen when an RSA certificate is available.
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
    if (!SSL_CTX_set_cipher_list(ctx, StringValueCStr(str))) {
        ossl_raise(eSSLError, "SSL_CTX_set_cipher_list");
    }

    return v;
}

#if !defined(OPENSSL_NO_EC)
/*
 * call-seq:
 *    ctx.ecdh_curves = curve_list -> curve_list
 *
 * Sets the list of "supported elliptic curves" for this context.
 *
 * For a TLS client, the list is directly used in the Supported Elliptic Curves
 * Extension. For a server, the list is used by OpenSSL to determine the set of
 * shared curves. OpenSSL will pick the most appropriate one from it.
 *
 * Note that this works differently with old OpenSSL (<= 1.0.1). Only one curve
 * can be set, and this has no effect for TLS clients.
 *
 * === Example
 *   ctx1 = OpenSSL::SSL::SSLContext.new
 *   ctx1.ecdh_curves = "X25519:P-256:P-224"
 *   svr = OpenSSL::SSL::SSLServer.new(tcp_svr, ctx1)
 *   Thread.new { svr.accept }
 *
 *   ctx2 = OpenSSL::SSL::SSLContext.new
 *   ctx2.ecdh_curves = "P-256"
 *   cli = OpenSSL::SSL::SSLSocket.new(tcp_sock, ctx2)
 *   cli.connect
 *
 *   p cli.tmp_key.group.curve_name
 *   # => "prime256v1" (is an alias for NIST P-256)
 */
static VALUE
ossl_sslctx_set_ecdh_curves(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;

    rb_check_frozen(self);
    GetSSLCTX(self, ctx);
    StringValueCStr(arg);

#if defined(HAVE_SSL_CTX_SET1_CURVES_LIST)
    if (!SSL_CTX_set1_curves_list(ctx, RSTRING_PTR(arg)))
	ossl_raise(eSSLError, NULL);
#else
    /* OpenSSL does not have SSL_CTX_set1_curves_list()... Fallback to
     * SSL_CTX_set_tmp_ecdh(). So only the first curve is used. */
    {
	VALUE curve, splitted;
	EC_KEY *ec;
	int nid;

	splitted = rb_str_split(arg, ":");
	if (!RARRAY_LEN(splitted))
	    ossl_raise(eSSLError, "invalid input format");
	curve = RARRAY_AREF(splitted, 0);
	StringValueCStr(curve);

	/* SSL_CTX_set1_curves_list() accepts NIST names */
	nid = EC_curve_nist2nid(RSTRING_PTR(curve));
	if (nid == NID_undef)
	    nid = OBJ_txt2nid(RSTRING_PTR(curve));
	if (nid == NID_undef)
	    ossl_raise(eSSLError, "unknown curve name");

	ec = EC_KEY_new_by_curve_name(nid);
	if (!ec)
	    ossl_raise(eSSLError, NULL);
	EC_KEY_set_asn1_flag(ec, OPENSSL_EC_NAMED_CURVE);
	if (!SSL_CTX_set_tmp_ecdh(ctx, ec)) {
	    EC_KEY_free(ec);
	    ossl_raise(eSSLError, "SSL_CTX_set_tmp_ecdh");
	}
	EC_KEY_free(ec);
# if defined(HAVE_SSL_CTX_SET_ECDH_AUTO)
	/* tmp_ecdh and ecdh_auto conflict. tmp_ecdh is ignored when ecdh_auto
	 * is enabled. So disable ecdh_auto. */
	if (!SSL_CTX_set_ecdh_auto(ctx, 0))
	    ossl_raise(eSSLError, "SSL_CTX_set_ecdh_auto");
# endif
    }
#endif

    return arg;
}
#else
#define ossl_sslctx_set_ecdh_curves rb_f_notimplement
#endif

/*
 * call-seq:
 *    ctx.security_level -> Integer
 *
 * Returns the security level for the context.
 *
 * See also OpenSSL::SSL::SSLContext#security_level=.
 */
static VALUE
ossl_sslctx_get_security_level(VALUE self)
{
    SSL_CTX *ctx;

    GetSSLCTX(self, ctx);

#if defined(HAVE_SSL_CTX_GET_SECURITY_LEVEL)
    return INT2NUM(SSL_CTX_get_security_level(ctx));
#else
    (void)ctx;
    return INT2FIX(0);
#endif
}

/*
 * call-seq:
 *    ctx.security_level = integer
 *
 * Sets the security level for the context. OpenSSL limits parameters according
 * to the level. The "parameters" include: ciphersuites, curves, key sizes,
 * certificate signature algorithms, protocol version and so on. For example,
 * level 1 rejects parameters offering below 80 bits of security, such as
 * ciphersuites using MD5 for the MAC or RSA keys shorter than 1024 bits.
 *
 * Note that attempts to set such parameters with insufficient security are
 * also blocked. You need to lower the level first.
 *
 * This feature is not supported in OpenSSL < 1.1.0, and setting the level to
 * other than 0 will raise NotImplementedError. Level 0 means everything is
 * permitted, the same behavior as previous versions of OpenSSL.
 *
 * See the manpage of SSL_CTX_set_security_level(3) for details.
 */
static VALUE
ossl_sslctx_set_security_level(VALUE self, VALUE value)
{
    SSL_CTX *ctx;

    rb_check_frozen(self);
    GetSSLCTX(self, ctx);

#if defined(HAVE_SSL_CTX_GET_SECURITY_LEVEL)
    SSL_CTX_set_security_level(ctx, NUM2INT(value));
#else
    (void)ctx;
    if (NUM2INT(value) != 0)
	ossl_raise(rb_eNotImpError, "setting security level to other than 0 is "
		   "not supported in this version of OpenSSL");
#endif

    return value;
}

#ifdef SSL_MODE_SEND_FALLBACK_SCSV
/*
 * call-seq:
 *    ctx.enable_fallback_scsv() => nil
 *
 * Activate TLS_FALLBACK_SCSV for this context.
 * See RFC 7507.
 */
static VALUE
ossl_sslctx_enable_fallback_scsv(VALUE self)
{
    SSL_CTX *ctx;

    GetSSLCTX(self, ctx);
    SSL_CTX_set_mode(ctx, SSL_MODE_SEND_FALLBACK_SCSV);

    return Qnil;
}
#endif

/*
 * call-seq:
 *    ctx.add_certificate(certiticate, pkey [, extra_certs]) -> self
 *
 * Adds a certificate to the context. _pkey_ must be a corresponding private
 * key with _certificate_.
 *
 * Multiple certificates with different public key type can be added by
 * repeated calls of this method, and OpenSSL will choose the most appropriate
 * certificate during the handshake.
 *
 * #cert=, #key=, and #extra_chain_cert= are old accessor methods for setting
 * certificate and internally call this method.
 *
 * === Parameters
 * _certificate_::
 *   A certificate. An instance of OpenSSL::X509::Certificate.
 * _pkey_::
 *   The private key for _certificate_. An instance of OpenSSL::PKey::PKey.
 * _extra_certs_::
 *   Optional. An array of OpenSSL::X509::Certificate. When sending a
 *   certificate chain, the certificates specified by this are sent following
 *   _certificate_, in the order in the array.
 *
 * === Example
 *   rsa_cert = OpenSSL::X509::Certificate.new(...)
 *   rsa_pkey = OpenSSL::PKey.read(...)
 *   ca_intermediate_cert = OpenSSL::X509::Certificate.new(...)
 *   ctx.add_certificate(rsa_cert, rsa_pkey, [ca_intermediate_cert])
 *
 *   ecdsa_cert = ...
 *   ecdsa_pkey = ...
 *   another_ca_cert = ...
 *   ctx.add_certificate(ecdsa_cert, ecdsa_pkey, [another_ca_cert])
 *
 * === Note
 * OpenSSL before the version 1.0.2 could handle only one extra chain across
 * all key types. Calling this method discards the chain set previously.
 */
static VALUE
ossl_sslctx_add_certificate(int argc, VALUE *argv, VALUE self)
{
    VALUE cert, key, extra_chain_ary;
    SSL_CTX *ctx;
    X509 *x509;
    STACK_OF(X509) *extra_chain = NULL;
    EVP_PKEY *pkey, *pub_pkey;

    GetSSLCTX(self, ctx);
    rb_scan_args(argc, argv, "21", &cert, &key, &extra_chain_ary);
    rb_check_frozen(self);
    x509 = GetX509CertPtr(cert);
    pkey = GetPrivPKeyPtr(key);

    /*
     * The reference counter is bumped, and decremented immediately.
     * X509_get0_pubkey() is only available in OpenSSL >= 1.1.0.
     */
    pub_pkey = X509_get_pubkey(x509);
    EVP_PKEY_free(pub_pkey);
    if (!pub_pkey)
	rb_raise(rb_eArgError, "certificate does not contain public key");
    if (EVP_PKEY_cmp(pub_pkey, pkey) != 1)
	rb_raise(rb_eArgError, "public key mismatch");

    if (argc >= 3)
	extra_chain = ossl_x509_ary2sk(extra_chain_ary);

    if (!SSL_CTX_use_certificate(ctx, x509)) {
	sk_X509_pop_free(extra_chain, X509_free);
	ossl_raise(eSSLError, "SSL_CTX_use_certificate");
    }
    if (!SSL_CTX_use_PrivateKey(ctx, pkey)) {
	sk_X509_pop_free(extra_chain, X509_free);
	ossl_raise(eSSLError, "SSL_CTX_use_PrivateKey");
    }

    if (extra_chain) {
#if OPENSSL_VERSION_NUMBER >= 0x10002000 && !defined(LIBRESSL_VERSION_NUMBER)
	if (!SSL_CTX_set0_chain(ctx, extra_chain)) {
	    sk_X509_pop_free(extra_chain, X509_free);
	    ossl_raise(eSSLError, "SSL_CTX_set0_chain");
	}
#else
	STACK_OF(X509) *orig_extra_chain;
	X509 *x509_tmp;

	/* First, clear the existing chain */
	SSL_CTX_get_extra_chain_certs(ctx, &orig_extra_chain);
	if (orig_extra_chain && sk_X509_num(orig_extra_chain)) {
	    rb_warning("SSL_CTX_set0_chain() is not available; " \
		       "clearing previously set certificate chain");
	    SSL_CTX_clear_extra_chain_certs(ctx);
	}
	while ((x509_tmp = sk_X509_shift(extra_chain))) {
	    /* Transfers ownership */
	    if (!SSL_CTX_add_extra_chain_cert(ctx, x509_tmp)) {
		X509_free(x509_tmp);
		sk_X509_pop_free(extra_chain, X509_free);
		ossl_raise(eSSLError, "SSL_CTX_add_extra_chain_cert");
	    }
	}
	sk_X509_free(extra_chain);
#endif
    }
    return self;
}

/*
 *  call-seq:
 *     ctx.session_add(session) -> true | false
 *
 * Adds _session_ to the session cache.
 */
static VALUE
ossl_sslctx_session_add(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;
    SSL_SESSION *sess;

    GetSSLCTX(self, ctx);
    GetSSLSession(arg, sess);

    return SSL_CTX_add_session(ctx, sess) == 1 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     ctx.session_remove(session) -> true | false
 *
 * Removes _session_ from the session cache.
 */
static VALUE
ossl_sslctx_session_remove(VALUE self, VALUE arg)
{
    SSL_CTX *ctx;
    SSL_SESSION *sess;

    GetSSLCTX(self, ctx);
    GetSSLSession(arg, sess);

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
 *     ctx.flush_sessions(time) -> self
 *
 * Removes sessions in the internal cache that have expired at _time_.
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
static inline int
ssl_started(SSL *ssl)
{
    /* the FD is set in ossl_ssl_setup(), called by #connect or #accept */
    return SSL_get_fd(ssl) >= 0;
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

/*
 * call-seq:
 *    SSLSocket.new(io) => aSSLSocket
 *    SSLSocket.new(io, ctx) => aSSLSocket
 *
 * Creates a new SSL socket from _io_ which must be a real IO object (not an
 * IO-like object that responds to read/write).
 *
 * If _ctx_ is provided the SSL Sockets initial params will be taken from
 * the context.
 *
 * The OpenSSL::Buffering module provides additional IO methods.
 *
 * This method will freeze the SSLContext if one is provided;
 * however, session management is still allowed in the frozen SSLContext.
 */
static VALUE
ossl_ssl_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE io, v_ctx, verify_cb;
    SSL *ssl;
    SSL_CTX *ctx;

    TypedData_Get_Struct(self, SSL, &ossl_ssl_type, ssl);
    if (ssl)
	ossl_raise(eSSLError, "SSL already initialized");

    if (rb_scan_args(argc, argv, "11", &io, &v_ctx) == 1)
	v_ctx = rb_funcall(cSSLContext, rb_intern("new"), 0);

    GetSSLCTX(v_ctx, ctx);
    rb_ivar_set(self, id_i_context, v_ctx);
    ossl_sslctx_setup(v_ctx);

    if (rb_respond_to(io, rb_intern("nonblock=")))
	rb_funcall(io, rb_intern("nonblock="), 1, Qtrue);
    rb_ivar_set(self, id_i_io, io);

    ssl = SSL_new(ctx);
    if (!ssl)
	ossl_raise(eSSLError, NULL);
    RTYPEDDATA_DATA(self) = ssl;

    SSL_set_ex_data(ssl, ossl_ssl_ex_ptr_idx, (void *)self);
    SSL_set_info_callback(ssl, ssl_info_cb);
    verify_cb = rb_attr_get(v_ctx, id_i_verify_callback);
    SSL_set_ex_data(ssl, ossl_ssl_ex_vcb_idx, (void *)verify_cb);

    rb_call_super(0, NULL);

    return self;
}

static VALUE
ossl_ssl_setup(VALUE self)
{
    VALUE io;
    SSL *ssl;
    rb_io_t *fptr;

    GetSSL(self, ssl);
    if (ssl_started(ssl))
	return Qtrue;

    io = rb_attr_get(self, id_i_io);
    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    rb_io_check_writable(fptr);
    if (!SSL_set_fd(ssl, TO_SOCKET(fptr->fd)))
	ossl_raise(eSSLError, "SSL_set_fd");

    return Qtrue;
}

#ifdef _WIN32
#define ssl_get_error(ssl, ret) (errno = rb_w32_map_errno(WSAGetLastError()), SSL_get_error((ssl), (ret)))
#else
#define ssl_get_error(ssl, ret) SSL_get_error((ssl), (ret))
#endif

static void
write_would_block(int nonblock)
{
    if (nonblock)
	ossl_raise(eSSLErrorWaitWritable, "write would block");
}

static void
read_would_block(int nonblock)
{
    if (nonblock)
	ossl_raise(eSSLErrorWaitReadable, "read would block");
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
#if defined(SSL_R_CERTIFICATE_VERIFY_FAILED)
    unsigned long err;
#endif

    rb_ivar_set(self, ID_callback_state, Qnil);

    GetSSL(self, ssl);

    GetOpenFile(rb_attr_get(self, id_i_io), fptr);
    for(;;){
	ret = func(ssl);

	cb_state = rb_attr_get(self, ID_callback_state);
        if (!NIL_P(cb_state)) {
	    /* must cleanup OpenSSL error stack before re-raising */
	    ossl_clear_error();
	    rb_jump_tag(NUM2INT(cb_state));
	}

	if (ret > 0)
	    break;

	switch((ret2 = ssl_get_error(ssl, ret))){
	case SSL_ERROR_WANT_WRITE:
            if (no_exception_p(opts)) { return sym_wait_writable; }
            write_would_block(nonblock);
            rb_io_wait_writable(fptr->fd);
            continue;
	case SSL_ERROR_WANT_READ:
            if (no_exception_p(opts)) { return sym_wait_readable; }
            read_would_block(nonblock);
            rb_io_wait_readable(fptr->fd);
            continue;
	case SSL_ERROR_SYSCALL:
	    if (errno) rb_sys_fail(funcname);
	    ossl_raise(eSSLError, "%s SYSCALL returned=%d errno=%d state=%s", funcname, ret2, errno, SSL_state_string_long(ssl));
#if defined(SSL_R_CERTIFICATE_VERIFY_FAILED)
	case SSL_ERROR_SSL:
	    err = ERR_peek_last_error();
	    if (ERR_GET_LIB(err) == ERR_LIB_SSL &&
		ERR_GET_REASON(err) == SSL_R_CERTIFICATE_VERIFY_FAILED) {
		const char *err_msg = ERR_reason_error_string(err),
		      *verify_msg = X509_verify_cert_error_string(SSL_get_verify_result(ssl));
		if (!err_msg)
		    err_msg = "(null)";
		if (!verify_msg)
		    verify_msg = "(null)";
		ossl_clear_error(); /* let ossl_raise() not append message */
		ossl_raise(eSSLError, "%s returned=%d errno=%d state=%s: %s (%s)",
			   funcname, ret2, errno, SSL_state_string_long(ssl),
			   err_msg, verify_msg);
	    }
#endif
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
 * By specifying a keyword argument _exception_ to +false+, you can indicate
 * that connect_nonblock should not raise an IO::WaitReadable or
 * IO::WaitWritable exception, but return the symbol +:wait_readable+ or
 * +:wait_writable+ instead.
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
 * By specifying a keyword argument _exception_ to +false+, you can indicate
 * that accept_nonblock should not raise an IO::WaitReadable or
 * IO::WaitWritable exception, but return the symbol +:wait_readable+ or
 * +:wait_writable+ instead.
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
    VALUE io, opts = Qnil;

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
    rb_str_set_len(str, 0);
    if (ilen == 0)
	return str;

    GetSSL(self, ssl);
    io = rb_attr_get(self, id_i_io);
    GetOpenFile(io, fptr);
    if (ssl_started(ssl)) {
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
                rb_io_wait_writable(fptr->fd);
                continue;
	    case SSL_ERROR_WANT_READ:
		if (no_exception_p(opts)) { return sym_wait_readable; }
                read_would_block(nonblock);
                rb_io_wait_readable(fptr->fd);
		continue;
	    case SSL_ERROR_SYSCALL:
		if (!ERR_peek_error()) {
		    if (errno)
			rb_sys_fail(0);
		    else {
			/*
			 * The underlying BIO returned 0. This is actually a
			 * protocol error. But unfortunately, not all
			 * implementations cleanly shutdown the TLS connection
			 * but just shutdown/close the TCP connection. So report
			 * EOF for now...
			 */
			if (no_exception_p(opts)) { return Qnil; }
			rb_eof_error();
		    }
		}
                /* fall through */
	    default:
		ossl_raise(eSSLError, "SSL_read");
	    }
        }
    }
    else {
	ID meth = nonblock ? rb_intern("read_nonblock") : rb_intern("sysread");

	rb_warning("SSL session is not started yet.");
	if (nonblock) {
            VALUE argv[3];
            argv[0] = len;
            argv[1] = str;
            argv[2] = opts;
            return rb_funcallv_kw(io, meth, 3, argv, RB_PASS_KEYWORDS);
        }
	else
	    return rb_funcall(io, meth, 2, len, str);
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
 * Reads _length_ bytes from the SSL connection.  If a pre-allocated _buffer_
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
 * Reads _length_ bytes from the SSL connection.  If a pre-allocated _buffer_
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
    VALUE io;

    StringValue(str);
    GetSSL(self, ssl);
    io = rb_attr_get(self, id_i_io);
    GetOpenFile(io, fptr);
    if (ssl_started(ssl)) {
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
                rb_io_wait_writable(fptr->fd);
                continue;
	    case SSL_ERROR_WANT_READ:
		if (no_exception_p(opts)) { return sym_wait_readable; }
                read_would_block(nonblock);
                rb_io_wait_readable(fptr->fd);
                continue;
	    case SSL_ERROR_SYSCALL:
		if (errno) rb_sys_fail(0);
	    default:
		ossl_raise(eSSLError, "SSL_write");
	    }
        }
    }
    else {
	ID meth = nonblock ?
	    rb_intern("write_nonblock") : rb_intern("syswrite");

	rb_warning("SSL session is not started yet.");
	if (nonblock) {
            VALUE argv[2];
            argv[0] = str;
            argv[1] = opts;
            return rb_funcallv_kw(io, meth, 2, argv, RB_PASS_KEYWORDS);
        }
	else
	    return rb_funcall(io, meth, 1, str);
    }

  end:
    return INT2NUM(nwrite);
}

/*
 * call-seq:
 *    ssl.syswrite(string) => Integer
 *
 * Writes _string_ to the SSL connection.
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
 * Writes _string_ to the SSL connection in a non-blocking manner.  Raises an
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
    int ret;

    GetSSL(self, ssl);
    if (!ssl_started(ssl))
	return Qnil;
    ret = SSL_shutdown(ssl);
    if (ret == 1) /* Have already received close_notify */
	return Qnil;
    if (ret == 0) /* Sent close_notify, but we don't wait for reply */
	return Qnil;

    /*
     * XXX: Something happened. Possibly it failed because the underlying socket
     * is not writable/readable, since it is in non-blocking mode. We should do
     * some proper error handling using SSL_get_error() and maybe retry, but we
     * can't block here. Give up for now.
     */
    ossl_clear_error();
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

    GetSSL(self, ssl);

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

    GetSSL(self, ssl);

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

    GetSSL(self, ssl);

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

    GetSSL(self, ssl);

    return rb_str_new2(SSL_get_version(ssl));
}

/*
 * call-seq:
 *    ssl.cipher -> nil or [name, version, bits, alg_bits]
 *
 * Returns the cipher suite actually used in the current session, or nil if
 * no session has been established.
 */
static VALUE
ossl_ssl_get_cipher(VALUE self)
{
    SSL *ssl;
    const SSL_CIPHER *cipher;

    GetSSL(self, ssl);
    cipher = SSL_get_current_cipher(ssl);
    return cipher ? ossl_ssl_cipher_to_ary(cipher) : Qnil;
}

/*
 * call-seq:
 *    ssl.state => string
 *
 * A description of the current connection state. This is for diagnostic
 * purposes only.
 */
static VALUE
ossl_ssl_get_state(VALUE self)
{
    SSL *ssl;
    VALUE ret;

    GetSSL(self, ssl);

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
 * The number of bytes that are immediately available for reading.
 */
static VALUE
ossl_ssl_pending(VALUE self)
{
    SSL *ssl;

    GetSSL(self, ssl);

    return INT2NUM(SSL_pending(ssl));
}

/*
 * call-seq:
 *    ssl.session_reused? -> true | false
 *
 * Returns +true+ if a reused session was negotiated during the handshake.
 */
static VALUE
ossl_ssl_session_reused(VALUE self)
{
    SSL *ssl;

    GetSSL(self, ssl);

    return SSL_session_reused(ssl) ? Qtrue : Qfalse;
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

    GetSSL(self, ssl);
    GetSSLSession(arg1, sess);

    if (SSL_set_session(ssl, sess) != 1)
        ossl_raise(eSSLError, "SSL_set_session");

    return arg1;
}

/*
 * call-seq:
 *    ssl.hostname = hostname -> hostname
 *
 * Sets the server hostname used for SNI. This needs to be set before
 * SSLSocket#connect.
 */
static VALUE
ossl_ssl_set_hostname(VALUE self, VALUE arg)
{
    SSL *ssl;
    char *hostname = NULL;

    GetSSL(self, ssl);

    if (!NIL_P(arg))
	hostname = StringValueCStr(arg);

    if (!SSL_set_tlsext_host_name(ssl, hostname))
	ossl_raise(eSSLError, NULL);

    /* for SSLSocket#hostname */
    rb_ivar_set(self, id_i_hostname, arg);

    return arg;
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

    GetSSL(self, ssl);

    return INT2NUM(SSL_get_verify_result(ssl));
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

    GetSSL(self, ssl);

    ca = SSL_get_client_CA_list(ssl);
    return ossl_x509name_sk2ary(ca);
}

# ifndef OPENSSL_NO_NEXTPROTONEG
/*
 * call-seq:
 *    ssl.npn_protocol => String | nil
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

    GetSSL(self, ssl);

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
 *    ssl.alpn_protocol => String | nil
 *
 * Returns the ALPN protocol string that was finally selected by the server
 * during the handshake.
 */
static VALUE
ossl_ssl_alpn_protocol(VALUE self)
{
    SSL *ssl;
    const unsigned char *out;
    unsigned int outlen;

    GetSSL(self, ssl);

    SSL_get0_alpn_selected(ssl, &out, &outlen);
    if (!outlen)
	return Qnil;
    else
	return rb_str_new((const char *) out, outlen);
}
# endif

# ifdef HAVE_SSL_GET_SERVER_TMP_KEY
/*
 * call-seq:
 *    ssl.tmp_key => PKey or nil
 *
 * Returns the ephemeral key used in case of forward secrecy cipher.
 */
static VALUE
ossl_ssl_tmp_key(VALUE self)
{
    SSL *ssl;
    EVP_PKEY *key;

    GetSSL(self, ssl);
    if (!SSL_get_server_tmp_key(ssl, &key))
	return Qnil;
    return ossl_pkey_new(key);
}
# endif /* defined(HAVE_SSL_GET_SERVER_TMP_KEY) */
#endif /* !defined(OPENSSL_NO_SOCK) */

#undef rb_intern
#define rb_intern(s) rb_intern_const(s)
void
Init_ossl_ssl(void)
{
#if 0
    mOSSL = rb_define_module("OpenSSL");
    eOSSLError = rb_define_class_under(mOSSL, "OpenSSLError", rb_eStandardError);
    rb_mWaitReadable = rb_define_module_under(rb_cIO, "WaitReadable");
    rb_mWaitWritable = rb_define_module_under(rb_cIO, "WaitWritable");
#endif

    id_call = rb_intern("call");
    ID_callback_state = rb_intern("callback_state");

    ossl_ssl_ex_vcb_idx = SSL_get_ex_new_index(0, (void *)"ossl_ssl_ex_vcb_idx", 0, 0, 0);
    if (ossl_ssl_ex_vcb_idx < 0)
	ossl_raise(rb_eRuntimeError, "SSL_get_ex_new_index");
    ossl_ssl_ex_ptr_idx = SSL_get_ex_new_index(0, (void *)"ossl_ssl_ex_ptr_idx", 0, 0, 0);
    if (ossl_ssl_ex_ptr_idx < 0)
	ossl_raise(rb_eRuntimeError, "SSL_get_ex_new_index");
    ossl_sslctx_ex_ptr_idx = SSL_CTX_get_ex_new_index(0, (void *)"ossl_sslctx_ex_ptr_idx", 0, 0, 0);
    if (ossl_sslctx_ex_ptr_idx < 0)
	ossl_raise(rb_eRuntimeError, "SSL_CTX_get_ex_new_index");
#if !defined(HAVE_X509_STORE_UP_REF)
    ossl_sslctx_ex_store_p = SSL_CTX_get_ex_new_index(0, (void *)"ossl_sslctx_ex_store_p", 0, 0, 0);
    if (ossl_sslctx_ex_store_p < 0)
	ossl_raise(rb_eRuntimeError, "SSL_CTX_get_ex_new_index");
#endif

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
     * +true+ or +false+ values depending on the configuration of your OpenSSL
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
     */
    cSSLContext = rb_define_class_under(mSSL, "SSLContext", rb_cObject);
    rb_define_alloc_func(cSSLContext, ossl_sslctx_s_alloc);
    rb_undef_method(cSSLContext, "initialize_copy");

    /*
     * Context certificate
     *
     * The _cert_, _key_, and _extra_chain_cert_ attributes are deprecated.
     * It is recommended to use #add_certificate instead.
     */
    rb_attr(cSSLContext, rb_intern("cert"), 1, 1, Qfalse);

    /*
     * Context private key
     *
     * The _cert_, _key_, and _extra_chain_cert_ attributes are deprecated.
     * It is recommended to use #add_certificate instead.
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
     * Maximum session lifetime in seconds.
     */
    rb_attr(cSSLContext, rb_intern("timeout"), 1, 1, Qfalse);

    /*
     * Session verification mode.
     *
     * Valid modes are VERIFY_NONE, VERIFY_PEER, VERIFY_CLIENT_ONCE,
     * VERIFY_FAIL_IF_NO_PEER_CERT and defined on OpenSSL::SSL
     *
     * The default mode is VERIFY_NONE, which does not perform any verification
     * at all.
     *
     * See SSL_CTX_set_verify(3) for details.
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
     * The callback is invoked with two values.  _preverify_ok_ indicates
     * indicates if the verification was passed (+true+) or not (+false+).
     * _store_context_ is an OpenSSL::X509::StoreContext containing the
     * context used for certificate verification.
     *
     * If the callback returns +false+, the chain verification is immediately
     * stopped and a bad_certificate alert is then sent.
     */
    rb_attr(cSSLContext, rb_intern("verify_callback"), 1, 1, Qfalse);

    /*
     * Whether to check the server certificate is valid for the hostname.
     *
     * In order to make this work, verify_mode must be set to VERIFY_PEER and
     * the server hostname must be given by OpenSSL::SSL::SSLSocket#hostname=.
     */
    rb_attr(cSSLContext, rb_intern("verify_hostname"), 1, 1, Qfalse);

    /*
     * An OpenSSL::X509::Store used for certificate verification.
     */
    rb_attr(cSSLContext, rb_intern("cert_store"), 1, 1, Qfalse);

    /*
     * An Array of extra X509 certificates to be added to the certificate
     * chain.
     *
     * The _cert_, _key_, and _extra_chain_cert_ attributes are deprecated.
     * It is recommended to use #add_certificate instead.
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

#if !defined(OPENSSL_NO_EC) && defined(HAVE_SSL_CTX_SET_TMP_ECDH_CALLBACK)
    /*
     * A callback invoked when ECDH parameters are required.
     *
     * The callback is invoked with the Session for the key exchange, an
     * flag indicating the use of an export cipher and the keylength
     * required.
     *
     * The callback is deprecated. This does not work with recent versions of
     * OpenSSL. Use OpenSSL::SSL::SSLContext#ecdh_curves= instead.
     */
    rb_attr(cSSLContext, rb_intern("tmp_ecdh_callback"), 1, 1, Qfalse);
#endif

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
     * The callback is invoked with an SSLSocket.  If +false+ is returned the
     * session will be removed from the internal cache.
     */
    rb_attr(cSSLContext, rb_intern("session_new_cb"), 1, 1, Qfalse);

    /*
     * A callback invoked when a session is removed from the internal cache.
     *
     * The callback is invoked with an SSLContext and a Session.
     *
     * IMPORTANT NOTE: It is currently not possible to use this safely in a
     * multi-threaded application. The callback is called inside a global lock
     * and it can randomly cause deadlock on Ruby thread switching.
     */
    rb_attr(cSSLContext, rb_intern("session_remove_cb"), 1, 1, Qfalse);

    rb_define_const(mSSLExtConfig, "HAVE_TLSEXT_HOST_NAME", Qtrue);

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
#ifndef OPENSSL_NO_NEXTPROTONEG
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
     *     # inspect the protocols and select one
     *     protocols.first
     *   end
     */
    rb_attr(cSSLContext, rb_intern("npn_select_cb"), 1, 1, Qfalse);
#endif

#ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
    /*
     * An Enumerable of Strings. Each String represents a protocol to be
     * advertised as the list of supported protocols for Application-Layer
     * Protocol Negotiation. Supported in OpenSSL 1.0.2 and higher. Has no
     * effect on the server side. If not set explicitly, the ALPN extension will
     * not be included in the handshake.
     *
     * === Example
     *
     *   ctx.alpn_protocols = ["http/1.1", "spdy/2", "h2"]
     */
    rb_attr(cSSLContext, rb_intern("alpn_protocols"), 1, 1, Qfalse);
    /*
     * A callback invoked on the server side when the server needs to select
     * a protocol from the list sent by the client. Supported in OpenSSL 1.0.2
     * and higher. The callback must return a protocol of those advertised by
     * the client. If none is acceptable, raising an error in the callback
     * will cause the handshake to fail. Not setting this callback explicitly
     * means not supporting the ALPN extension on the server - any protocols
     * advertised by the client will be ignored.
     *
     * === Example
     *
     *   ctx.alpn_select_cb = lambda do |protocols|
     *     # inspect the protocols and select one
     *     protocols.first
     *   end
     */
    rb_attr(cSSLContext, rb_intern("alpn_select_cb"), 1, 1, Qfalse);
#endif

    rb_define_alias(cSSLContext, "ssl_timeout", "timeout");
    rb_define_alias(cSSLContext, "ssl_timeout=", "timeout=");
    rb_define_private_method(cSSLContext, "set_minmax_proto_version",
			     ossl_sslctx_set_minmax_proto_version, 2);
    rb_define_method(cSSLContext, "ciphers",     ossl_sslctx_get_ciphers, 0);
    rb_define_method(cSSLContext, "ciphers=",    ossl_sslctx_set_ciphers, 1);
    rb_define_method(cSSLContext, "ecdh_curves=", ossl_sslctx_set_ecdh_curves, 1);
    rb_define_method(cSSLContext, "security_level", ossl_sslctx_get_security_level, 0);
    rb_define_method(cSSLContext, "security_level=", ossl_sslctx_set_security_level, 1);
#ifdef SSL_MODE_SEND_FALLBACK_SCSV
    rb_define_method(cSSLContext, "enable_fallback_scsv", ossl_sslctx_enable_fallback_scsv, 0);
#endif
    rb_define_method(cSSLContext, "add_certificate", ossl_sslctx_add_certificate, -1);

    rb_define_method(cSSLContext, "setup", ossl_sslctx_setup, 0);
    rb_define_alias(cSSLContext, "freeze", "setup");

    /*
     * No session caching for client or server
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_OFF", LONG2NUM(SSL_SESS_CACHE_OFF));

    /*
     * Client sessions are added to the session cache
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_CLIENT", LONG2NUM(SSL_SESS_CACHE_CLIENT)); /* doesn't actually do anything in 0.9.8e */

    /*
     * Server sessions are added to the session cache
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_SERVER", LONG2NUM(SSL_SESS_CACHE_SERVER));

    /*
     * Both client and server sessions are added to the session cache
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_BOTH", LONG2NUM(SSL_SESS_CACHE_BOTH)); /* no different than CACHE_SERVER in 0.9.8e */

    /*
     * Normally the session cache is checked for expired sessions every 255
     * connections.  Since this may lead to a delay that cannot be controlled,
     * the automatic flushing may be disabled and #flush_sessions can be
     * called explicitly.
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_AUTO_CLEAR", LONG2NUM(SSL_SESS_CACHE_NO_AUTO_CLEAR));

    /*
     * Always perform external lookups of sessions even if they are in the
     * internal cache.
     *
     * This flag has no effect on clients
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL_LOOKUP", LONG2NUM(SSL_SESS_CACHE_NO_INTERNAL_LOOKUP));

    /*
     * Never automatically store sessions in the internal store.
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL_STORE", LONG2NUM(SSL_SESS_CACHE_NO_INTERNAL_STORE));

    /*
     * Enables both SESSION_CACHE_NO_INTERNAL_LOOKUP and
     * SESSION_CACHE_NO_INTERNAL_STORE.
     */
    rb_define_const(cSSLContext, "SESSION_CACHE_NO_INTERNAL", LONG2NUM(SSL_SESS_CACHE_NO_INTERNAL));

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

    /*
     * Document-class: OpenSSL::SSL::SSLSocket
     */
    cSSLSocket = rb_define_class_under(mSSL, "SSLSocket", rb_cObject);
#ifdef OPENSSL_NO_SOCK
    rb_define_const(mSSLExtConfig, "OPENSSL_NO_SOCK", Qtrue);
    rb_define_method(cSSLSocket, "initialize", rb_f_notimplement, -1);
#else
    rb_define_const(mSSLExtConfig, "OPENSSL_NO_SOCK", Qfalse);
    rb_define_alloc_func(cSSLSocket, ossl_ssl_s_alloc);
    rb_define_method(cSSLSocket, "initialize", ossl_ssl_initialize, -1);
    rb_undef_method(cSSLSocket, "initialize_copy");
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
    /* #hostname is defined in lib/openssl/ssl.rb */
    rb_define_method(cSSLSocket, "hostname=", ossl_ssl_set_hostname, 1);
# ifdef HAVE_SSL_GET_SERVER_TMP_KEY
    rb_define_method(cSSLSocket, "tmp_key", ossl_ssl_tmp_key, 0);
# endif
# ifdef HAVE_SSL_CTX_SET_ALPN_SELECT_CB
    rb_define_method(cSSLSocket, "alpn_protocol", ossl_ssl_alpn_protocol, 0);
# endif
# ifndef OPENSSL_NO_NEXTPROTONEG
    rb_define_method(cSSLSocket, "npn_protocol", ossl_ssl_npn_protocol, 0);
# endif
#endif

    rb_define_const(mSSL, "VERIFY_NONE", INT2NUM(SSL_VERIFY_NONE));
    rb_define_const(mSSL, "VERIFY_PEER", INT2NUM(SSL_VERIFY_PEER));
    rb_define_const(mSSL, "VERIFY_FAIL_IF_NO_PEER_CERT", INT2NUM(SSL_VERIFY_FAIL_IF_NO_PEER_CERT));
    rb_define_const(mSSL, "VERIFY_CLIENT_ONCE", INT2NUM(SSL_VERIFY_CLIENT_ONCE));

    rb_define_const(mSSL, "OP_ALL", ULONG2NUM(SSL_OP_ALL));
    rb_define_const(mSSL, "OP_LEGACY_SERVER_CONNECT", ULONG2NUM(SSL_OP_LEGACY_SERVER_CONNECT));
#ifdef SSL_OP_TLSEXT_PADDING /* OpenSSL 1.0.1h and OpenSSL 1.0.2 */
    rb_define_const(mSSL, "OP_TLSEXT_PADDING", ULONG2NUM(SSL_OP_TLSEXT_PADDING));
#endif
#ifdef SSL_OP_SAFARI_ECDHE_ECDSA_BUG /* OpenSSL 1.0.1f and OpenSSL 1.0.2 */
    rb_define_const(mSSL, "OP_SAFARI_ECDHE_ECDSA_BUG", ULONG2NUM(SSL_OP_SAFARI_ECDHE_ECDSA_BUG));
#endif
#ifdef SSL_OP_ALLOW_NO_DHE_KEX /* OpenSSL 1.1.1 */
    rb_define_const(mSSL, "OP_ALLOW_NO_DHE_KEX", ULONG2NUM(SSL_OP_ALLOW_NO_DHE_KEX));
#endif
    rb_define_const(mSSL, "OP_DONT_INSERT_EMPTY_FRAGMENTS", ULONG2NUM(SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS));
    rb_define_const(mSSL, "OP_NO_TICKET", ULONG2NUM(SSL_OP_NO_TICKET));
    rb_define_const(mSSL, "OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION", ULONG2NUM(SSL_OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION));
    rb_define_const(mSSL, "OP_NO_COMPRESSION", ULONG2NUM(SSL_OP_NO_COMPRESSION));
    rb_define_const(mSSL, "OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION", ULONG2NUM(SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION));
#ifdef SSL_OP_NO_ENCRYPT_THEN_MAC /* OpenSSL 1.1.1 */
    rb_define_const(mSSL, "OP_NO_ENCRYPT_THEN_MAC", ULONG2NUM(SSL_OP_NO_ENCRYPT_THEN_MAC));
#endif
    rb_define_const(mSSL, "OP_CIPHER_SERVER_PREFERENCE", ULONG2NUM(SSL_OP_CIPHER_SERVER_PREFERENCE));
    rb_define_const(mSSL, "OP_TLS_ROLLBACK_BUG", ULONG2NUM(SSL_OP_TLS_ROLLBACK_BUG));
#ifdef SSL_OP_NO_RENEGOTIATION /* OpenSSL 1.1.1 */
    rb_define_const(mSSL, "OP_NO_RENEGOTIATION", ULONG2NUM(SSL_OP_NO_RENEGOTIATION));
#endif
    rb_define_const(mSSL, "OP_CRYPTOPRO_TLSEXT_BUG", ULONG2NUM(SSL_OP_CRYPTOPRO_TLSEXT_BUG));

    rb_define_const(mSSL, "OP_NO_SSLv3", ULONG2NUM(SSL_OP_NO_SSLv3));
    rb_define_const(mSSL, "OP_NO_TLSv1", ULONG2NUM(SSL_OP_NO_TLSv1));
    rb_define_const(mSSL, "OP_NO_TLSv1_1", ULONG2NUM(SSL_OP_NO_TLSv1_1));
    rb_define_const(mSSL, "OP_NO_TLSv1_2", ULONG2NUM(SSL_OP_NO_TLSv1_2));
#ifdef SSL_OP_NO_TLSv1_3 /* OpenSSL 1.1.1 */
    rb_define_const(mSSL, "OP_NO_TLSv1_3", ULONG2NUM(SSL_OP_NO_TLSv1_3));
#endif

    /* SSL_OP_* flags for DTLS */
#if 0
    rb_define_const(mSSL, "OP_NO_QUERY_MTU", ULONG2NUM(SSL_OP_NO_QUERY_MTU));
    rb_define_const(mSSL, "OP_COOKIE_EXCHANGE", ULONG2NUM(SSL_OP_COOKIE_EXCHANGE));
    rb_define_const(mSSL, "OP_CISCO_ANYCONNECT", ULONG2NUM(SSL_OP_CISCO_ANYCONNECT));
#endif

    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_MICROSOFT_SESS_ID_BUG", ULONG2NUM(SSL_OP_MICROSOFT_SESS_ID_BUG));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_NETSCAPE_CHALLENGE_BUG", ULONG2NUM(SSL_OP_NETSCAPE_CHALLENGE_BUG));
    /* Deprecated in OpenSSL 0.9.8q and 1.0.0c. */
    rb_define_const(mSSL, "OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG", ULONG2NUM(SSL_OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG));
    /* Deprecated in OpenSSL 1.0.1h and 1.0.2. */
    rb_define_const(mSSL, "OP_SSLREF2_REUSE_CERT_TYPE_BUG", ULONG2NUM(SSL_OP_SSLREF2_REUSE_CERT_TYPE_BUG));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_MICROSOFT_BIG_SSLV3_BUFFER", ULONG2NUM(SSL_OP_MICROSOFT_BIG_SSLV3_BUFFER));
    /* Deprecated in OpenSSL 0.9.7h and 0.9.8b. */
    rb_define_const(mSSL, "OP_MSIE_SSLV2_RSA_PADDING", ULONG2NUM(SSL_OP_MSIE_SSLV2_RSA_PADDING));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_SSLEAY_080_CLIENT_DH_BUG", ULONG2NUM(SSL_OP_SSLEAY_080_CLIENT_DH_BUG));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_TLS_D5_BUG", ULONG2NUM(SSL_OP_TLS_D5_BUG));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_TLS_BLOCK_PADDING_BUG", ULONG2NUM(SSL_OP_TLS_BLOCK_PADDING_BUG));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_SINGLE_ECDH_USE", ULONG2NUM(SSL_OP_SINGLE_ECDH_USE));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_SINGLE_DH_USE", ULONG2NUM(SSL_OP_SINGLE_DH_USE));
    /* Deprecated in OpenSSL 1.0.1k and 1.0.2. */
    rb_define_const(mSSL, "OP_EPHEMERAL_RSA", ULONG2NUM(SSL_OP_EPHEMERAL_RSA));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_NO_SSLv2", ULONG2NUM(SSL_OP_NO_SSLv2));
    /* Deprecated in OpenSSL 1.0.1. */
    rb_define_const(mSSL, "OP_PKCS1_CHECK_1", ULONG2NUM(SSL_OP_PKCS1_CHECK_1));
    /* Deprecated in OpenSSL 1.0.1. */
    rb_define_const(mSSL, "OP_PKCS1_CHECK_2", ULONG2NUM(SSL_OP_PKCS1_CHECK_2));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_NETSCAPE_CA_DN_BUG", ULONG2NUM(SSL_OP_NETSCAPE_CA_DN_BUG));
    /* Deprecated in OpenSSL 1.1.0. */
    rb_define_const(mSSL, "OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG", ULONG2NUM(SSL_OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG));


    /*
     * SSL/TLS version constants. Used by SSLContext#min_version= and
     * #max_version=
     */
    /* SSL 2.0 */
    rb_define_const(mSSL, "SSL2_VERSION", INT2NUM(SSL2_VERSION));
    /* SSL 3.0 */
    rb_define_const(mSSL, "SSL3_VERSION", INT2NUM(SSL3_VERSION));
    /* TLS 1.0 */
    rb_define_const(mSSL, "TLS1_VERSION", INT2NUM(TLS1_VERSION));
    /* TLS 1.1 */
    rb_define_const(mSSL, "TLS1_1_VERSION", INT2NUM(TLS1_1_VERSION));
    /* TLS 1.2 */
    rb_define_const(mSSL, "TLS1_2_VERSION", INT2NUM(TLS1_2_VERSION));
#ifdef TLS1_3_VERSION /* OpenSSL 1.1.1 */
    /* TLS 1.3 */
    rb_define_const(mSSL, "TLS1_3_VERSION", INT2NUM(TLS1_3_VERSION));
#endif


    sym_exception = ID2SYM(rb_intern("exception"));
    sym_wait_readable = ID2SYM(rb_intern("wait_readable"));
    sym_wait_writable = ID2SYM(rb_intern("wait_writable"));

    id_tmp_dh_callback = rb_intern("tmp_dh_callback");
    id_tmp_ecdh_callback = rb_intern("tmp_ecdh_callback");
    id_npn_protocols_encoded = rb_intern("npn_protocols_encoded");

#define DefIVarID(name) do \
    id_i_##name = rb_intern("@"#name); while (0)

    DefIVarID(cert_store);
    DefIVarID(ca_file);
    DefIVarID(ca_path);
    DefIVarID(verify_mode);
    DefIVarID(verify_depth);
    DefIVarID(verify_callback);
    DefIVarID(client_ca);
    DefIVarID(renegotiation_cb);
    DefIVarID(cert);
    DefIVarID(key);
    DefIVarID(extra_chain_cert);
    DefIVarID(client_cert_cb);
    DefIVarID(tmp_ecdh_callback);
    DefIVarID(timeout);
    DefIVarID(session_id_context);
    DefIVarID(session_get_cb);
    DefIVarID(session_new_cb);
    DefIVarID(session_remove_cb);
    DefIVarID(npn_select_cb);
    DefIVarID(npn_protocols);
    DefIVarID(alpn_protocols);
    DefIVarID(alpn_select_cb);
    DefIVarID(servername_cb);
    DefIVarID(verify_hostname);

    DefIVarID(io);
    DefIVarID(context);
    DefIVarID(hostname);
}
