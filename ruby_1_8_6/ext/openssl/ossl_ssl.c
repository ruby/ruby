/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2000-2002  GOTOU Yuuzou <gotoyuzo@notwork.org>
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"
#include <rubysig.h>
#include <rubyio.h>

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

/*
 * SSLContext class
 */
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

static char *ossl_sslctx_attrs[] = {
    "cert", "key", "client_ca", "ca_file", "ca_path",
    "timeout", "verify_mode", "verify_depth",
    "verify_callback", "options", "cert_store", "extra_chain_cert",
    "client_cert_cb", "tmp_dh_callback", "session_id_context",
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

static char *ossl_ssl_attr_readers[] = { "io", "context", };
static char *ossl_ssl_attrs[] = { "sync_close", };

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
ossl_sslctx_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE ssl_method;
    SSL_METHOD *method = NULL;
    SSL_CTX *ctx;
    int i;
    char *s;

    for(i = 0; i < numberof(ossl_sslctx_attrs); i++){
	char buf[32];
	snprintf(buf, sizeof(buf), "@%s", ossl_sslctx_attrs[i]);
	rb_iv_set(self, buf, Qnil);
    }
    if (rb_scan_args(argc, argv, "01", &ssl_method) == 0){
        return self;
    }
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
	rb_warning("using default DH parameters.");
	SSL_CTX_set_tmp_dh_callback(ctx, ossl_default_tmp_dh_callback);
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
	rb_iterate(rb_each, val, ossl_sslctx_add_extra_chain_cert_i, self);
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
	    for(i = 0; i < RARRAY(val)->len; i++){
		client_ca = GetX509CertPtr(RARRAY(val)->ptr[i]);
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
	if (!SSL_CTX_set_session_id_context(ctx, RSTRING(val)->ptr,
					    RSTRING(val)->len)){
            ossl_raise(eSSLError, "SSL_CTX_set_session_id_context:");
	}
    }

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
        for (i = 0; i < RARRAY(v)->len; i++) {
            elem = rb_ary_entry(v, i);
            if (TYPE(elem) == T_ARRAY) elem = rb_ary_entry(elem, 0);
            elem = rb_String(elem);
            rb_str_append(str, elem);
            if (i < RARRAY(v)->len-1) rb_str_cat2(str, ":");
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
    if (!SSL_CTX_set_cipher_list(ctx, RSTRING(str)->ptr)) {
        ossl_raise(eSSLError, "SSL_CTX_set_cipher_list:");
    }

    return v;
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
    rb_call_super(0, 0);

    return self;
}

static VALUE
ossl_ssl_setup(VALUE self)
{
    VALUE io, v_ctx, cb;
    SSL_CTX *ctx;
    SSL *ssl;
    OpenFile *fptr;

    Data_Get_Struct(self, SSL, ssl);
    if(!ssl){
        v_ctx = ossl_ssl_get_ctx(self);
        Data_Get_Struct(v_ctx, SSL_CTX, ctx);

        ssl = SSL_new(ctx);
        if (!ssl) {
            ossl_raise(eSSLError, "SSL_new:");
        }
        DATA_PTR(self) = ssl;

        io = ossl_ssl_get_io(self);
        GetOpenFile(io, fptr);
        rb_io_check_readable(fptr);
        rb_io_check_writable(fptr);
        SSL_set_fd(ssl, TO_SOCKET(fileno(fptr->f)));
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
#define ssl_get_error(ssl, ret) \
  (errno = WSAGetLastError(), SSL_get_error(ssl, ret))
#else
#define ssl_get_error(ssl, ret) SSL_get_error(ssl, ret)
#endif

static VALUE
ossl_start_ssl(VALUE self, int (*func)())
{
    SSL *ssl;
    OpenFile *fptr;
    int ret;

    Data_Get_Struct(self, SSL, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);
    for(;;){
	if((ret = func(ssl)) > 0) break;
	switch(ssl_get_error(ssl, ret)){
	case SSL_ERROR_WANT_WRITE:
            rb_io_wait_writable(fileno(fptr->f));
            continue;
	case SSL_ERROR_WANT_READ:
            rb_io_wait_readable(fileno(fptr->f));
            continue;
	case SSL_ERROR_SYSCALL:
	    if (errno) rb_sys_fail(0);
	default:
	    ossl_raise(eSSLError, NULL);
	}
    }

    return self;
}

static VALUE
ossl_ssl_connect(VALUE self)
{
    ossl_ssl_setup(self);
    return ossl_start_ssl(self, SSL_connect);
}

static VALUE
ossl_ssl_accept(VALUE self)
{
    ossl_ssl_setup(self);
    return ossl_start_ssl(self, SSL_accept);
}

static VALUE
ossl_ssl_read(int argc, VALUE *argv, VALUE self)
{
    SSL *ssl;
    int ilen, nread = 0;
    VALUE len, str;
    OpenFile *fptr;

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
	if(SSL_pending(ssl) <= 0)
	    rb_thread_wait_fd(fileno(fptr->f));
	for (;;){
	    nread = SSL_read(ssl, RSTRING(str)->ptr, RSTRING(str)->len);
	    switch(ssl_get_error(ssl, nread)){
	    case SSL_ERROR_NONE:
		goto end;
	    case SSL_ERROR_ZERO_RETURN:
		rb_eof_error();
	    case SSL_ERROR_WANT_WRITE:
                rb_io_wait_writable(fileno(fptr->f));
                continue;
	    case SSL_ERROR_WANT_READ:
                rb_io_wait_readable(fileno(fptr->f));
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
        ID id_sysread = rb_intern("sysread");
        rb_warning("SSL session is not started yet.");
        return rb_funcall(ossl_ssl_get_io(self), id_sysread, 2, len, str);
    }

  end:
    RSTRING(str)->len = nread;
    RSTRING(str)->ptr[nread] = 0;
    OBJ_TAINT(str);

    return str;
}

static VALUE
ossl_ssl_write(VALUE self, VALUE str)
{
    SSL *ssl;
    int nwrite = 0;
    OpenFile *fptr;

    StringValue(str);
    Data_Get_Struct(self, SSL, ssl);
    GetOpenFile(ossl_ssl_get_io(self), fptr);

    if (ssl) {
	for (;;){
	    nwrite = SSL_write(ssl, RSTRING(str)->ptr, RSTRING(str)->len);
	    switch(ssl_get_error(ssl, nwrite)){
	    case SSL_ERROR_NONE:
		goto end;
	    case SSL_ERROR_WANT_WRITE:
                rb_io_wait_writable(fileno(fptr->f));
                continue;
	    case SSL_ERROR_WANT_READ:
                rb_io_wait_readable(fileno(fptr->f));
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
    num = sk_num(chain);
    ary = rb_ary_new2(num);
    for (i = 0; i < num; i++){
	cert = (X509*)sk_value(chain, i);
	rb_ary_push(ary, ossl_x509_new(cert));
    }

    return ary;
}

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

void
Init_ossl_ssl()
{
    int i;

#if 0 /* let rdoc know about mOSSL */
    mOSSL = rb_define_module("OpenSSL");
#endif

    ossl_ssl_ex_vcb_idx = SSL_get_ex_new_index(0,"ossl_ssl_ex_vcb_idx",0,0,0);
    ossl_ssl_ex_store_p = SSL_get_ex_new_index(0,"ossl_ssl_ex_store_p",0,0,0);
    ossl_ssl_ex_ptr_idx = SSL_get_ex_new_index(0,"ossl_ssl_ex_ptr_idx",0,0,0);
    ossl_ssl_ex_client_cert_cb_idx =
	SSL_get_ex_new_index(0,"ossl_ssl_ex_client_cert_cb_idx",0,0,0);
    ossl_ssl_ex_tmp_dh_callback_idx =
	SSL_get_ex_new_index(0,"ossl_ssl_ex_tmp_dh_callback_idx",0,0,0);

    mSSL = rb_define_module_under(mOSSL, "SSL");
    eSSLError = rb_define_class_under(mSSL, "SSLError", eOSSLError);

    /* class SSLContext */
    cSSLContext = rb_define_class_under(mSSL, "SSLContext", rb_cObject);
    rb_define_alloc_func(cSSLContext, ossl_sslctx_s_alloc);
    for(i = 0; i < numberof(ossl_sslctx_attrs); i++)
        rb_attr(cSSLContext, rb_intern(ossl_sslctx_attrs[i]), 1, 1, Qfalse);
    rb_define_method(cSSLContext, "initialize",  ossl_sslctx_initialize, -1);
    rb_define_method(cSSLContext, "ciphers",     ossl_sslctx_get_ciphers, 0);
    rb_define_method(cSSLContext, "ciphers=",    ossl_sslctx_set_ciphers, 1);

    /* class SSLSocket */
    cSSLSocket = rb_define_class_under(mSSL, "SSLSocket", rb_cObject);
    rb_define_alloc_func(cSSLSocket, ossl_ssl_s_alloc);
    for(i = 0; i < numberof(ossl_ssl_attr_readers); i++)
        rb_attr(cSSLSocket, rb_intern(ossl_ssl_attr_readers[i]), 1, 0, Qfalse);
    for(i = 0; i < numberof(ossl_ssl_attrs); i++)
        rb_attr(cSSLSocket, rb_intern(ossl_ssl_attrs[i]), 1, 1, Qfalse);
    rb_define_alias(cSSLSocket, "to_io", "io");
    rb_define_method(cSSLSocket, "initialize", ossl_ssl_initialize, -1);
    rb_define_method(cSSLSocket, "connect",    ossl_ssl_connect, 0);
    rb_define_method(cSSLSocket, "accept",     ossl_ssl_accept, 0);
    rb_define_method(cSSLSocket, "sysread",    ossl_ssl_read, -1);
    rb_define_method(cSSLSocket, "syswrite",   ossl_ssl_write, 1);
    rb_define_method(cSSLSocket, "sysclose",   ossl_ssl_close, 0);
    rb_define_method(cSSLSocket, "cert",       ossl_ssl_get_cert, 0);
    rb_define_method(cSSLSocket, "peer_cert",  ossl_ssl_get_peer_cert, 0);
    rb_define_method(cSSLSocket, "peer_cert_chain", ossl_ssl_get_peer_cert_chain, 0);
    rb_define_method(cSSLSocket, "cipher",     ossl_ssl_get_cipher, 0);
    rb_define_method(cSSLSocket, "state",      ossl_ssl_get_state, 0);
    rb_define_method(cSSLSocket, "pending",    ossl_ssl_pending, 0);

#define ossl_ssl_def_const(x) rb_define_const(mSSL, #x, INT2FIX(SSL_##x))

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
    ossl_ssl_def_const(OP_PKCS1_CHECK_1);
    ossl_ssl_def_const(OP_PKCS1_CHECK_2);
    ossl_ssl_def_const(OP_NETSCAPE_CA_DN_BUG);
    ossl_ssl_def_const(OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG);
}
