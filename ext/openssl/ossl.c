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
#include <stdarg.h> /* for ossl_raise */

/*
 * String to HEXString conversion
 */
int
string2hex(const unsigned char *buf, int buf_len, char **hexbuf, int *hexbuf_len)
{
    static const char hex[]="0123456789abcdef";
    int i, len = 2 * buf_len;

    if (buf_len < 0 || len < buf_len) { /* PARANOIA? */
	return -1;
    }
    if (!hexbuf) { /* if no buf, return calculated len */
	if (hexbuf_len) {
	    *hexbuf_len = len;
	}
	return len;
    }
    if (!(*hexbuf = OPENSSL_malloc(len + 1))) {
	return -1;
    }
    for (i = 0; i < buf_len; i++) {
	(*hexbuf)[2 * i] = hex[((unsigned char)buf[i]) >> 4];
	(*hexbuf)[2 * i + 1] = hex[buf[i] & 0x0f];
    }
    (*hexbuf)[2 * i] = '\0';

    if (hexbuf_len) {
	*hexbuf_len = len;
    }
    return len;
}

/*
 * Data Conversion
 */
STACK_OF(X509) *
ossl_x509_ary2sk0(VALUE ary)
{
    STACK_OF(X509) *sk;
    VALUE val;
    X509 *x509;
    int i;

    Check_Type(ary, T_ARRAY);
    sk = sk_X509_new_null();
    if (!sk) ossl_raise(eOSSLError, NULL);

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        val = rb_ary_entry(ary, i);
        if (!rb_obj_is_kind_of(val, cX509Cert)) {
            sk_X509_pop_free(sk, X509_free);
            ossl_raise(eOSSLError, "object not X509 cert in array");
        }
        x509 = DupX509CertPtr(val); /* NEED TO DUP */
        sk_X509_push(sk, x509);
    }
    return sk;
}

STACK_OF(X509) *
ossl_protect_x509_ary2sk(VALUE ary, int *status)
{
    return (STACK_OF(X509)*)rb_protect((VALUE(*)_((VALUE)))ossl_x509_ary2sk0,
				       ary, status);
}

STACK_OF(X509) *
ossl_x509_ary2sk(VALUE ary)
{
    STACK_OF(X509) *sk;
    int status = 0;

    sk = ossl_protect_x509_ary2sk(ary, &status);
    if(status) rb_jump_tag(status);

    return sk;
}

#define OSSL_IMPL_SK2ARY(name, type)	        \
VALUE						\
ossl_##name##_sk2ary(STACK_OF(type) *sk)	\
{						\
    type *t;					\
    int i, num;					\
    VALUE ary;					\
						\
    if (!sk) {					\
	OSSL_Debug("empty sk!");		\
	return Qnil;				\
    }						\
    num = sk_##type##_num(sk);			\
    if (num < 0) {				\
	OSSL_Debug("items in sk < -1???");	\
	return rb_ary_new();			\
    }						\
    ary = rb_ary_new2(num);			\
						\
    for (i=0; i<num; i++) {			\
	t = sk_##type##_value(sk, i);		\
	rb_ary_push(ary, ossl_##name##_new(t));	\
    }						\
    return ary;					\
}
OSSL_IMPL_SK2ARY(x509, X509)
OSSL_IMPL_SK2ARY(x509crl, X509_CRL)

static VALUE
ossl_str_new(int size)
{
    return rb_str_new(0, size);
}

VALUE
ossl_buf2str(char *buf, int len)
{
    VALUE str;
    int status = 0;

    str = rb_protect((VALUE(*)_((VALUE)))ossl_str_new, len, &status);
    if(!NIL_P(str)) memcpy(RSTRING_PTR(str), buf, len);
    OPENSSL_free(buf);
    if(status) rb_jump_tag(status);

    return str;
}

/*
 * our default PEM callback
 */
static VALUE
ossl_pem_passwd_cb0(VALUE flag)
{	
    VALUE pass;

    pass = rb_yield(flag);
    SafeStringValue(pass);

    return pass;
}

int
ossl_pem_passwd_cb(char *buf, int max_len, int flag, void *pwd)
{
    int len, status = 0;
    VALUE rflag, pass;

    if (pwd || !rb_block_given_p())
	return PEM_def_callback(buf, max_len, flag, pwd);

    while (1) {
	/*
	 * when the flag is nonzero, this passphrase
	 * will be used to perform encryption; otherwise it will
	 * be used to perform decryption.
	 */
	rflag = flag ? Qtrue : Qfalse;
	pass  = rb_protect(ossl_pem_passwd_cb0, rflag, &status);
	if (status) return -1; /* exception was raised. */
	len = RSTRING_LEN(pass);
	if (len < 4) { /* 4 is OpenSSL hardcoded limit */
	    rb_warning("password must be longer than 4 bytes");
	    continue;
	}
	if (len > max_len) {
	    rb_warning("password must be shorter then %d bytes", max_len-1);
	    continue;
	}
	memcpy(buf, RSTRING_PTR(pass), len);
	break;
    }
    return len;
}

/*
 * Verify callback
 */
int ossl_verify_cb_idx;

VALUE
ossl_call_verify_cb_proc(struct ossl_verify_cb_args *args)
{
    return rb_funcall(args->proc, rb_intern("call"), 2,
                      args->preverify_ok, args->store_ctx);
}

int
ossl_verify_cb(int ok, X509_STORE_CTX *ctx)
{
    VALUE proc, rctx, ret;
    struct ossl_verify_cb_args args;
    int state = 0;

    proc = (VALUE)X509_STORE_CTX_get_ex_data(ctx, ossl_verify_cb_idx);
    if ((void*)proc == 0)
	proc = (VALUE)X509_STORE_get_ex_data(ctx->ctx, ossl_verify_cb_idx);
    if ((void*)proc == 0)
	return ok;
    if (!NIL_P(proc)) {
	rctx = rb_protect((VALUE(*)(VALUE))ossl_x509stctx_new,
			  (VALUE)ctx, &state);
	ret = Qfalse;
	if (!state) {
	    args.proc = proc;
	    args.preverify_ok = ok ? Qtrue : Qfalse;
	    args.store_ctx = rctx;
	    ret = rb_ensure(ossl_call_verify_cb_proc, (VALUE)&args,
			    ossl_x509stctx_clear_ptr, rctx);
	}
	if (ret == Qtrue) {
	    X509_STORE_CTX_set_error(ctx, X509_V_OK);
	    ok = 1;
	}
	else{
	    if (X509_STORE_CTX_get_error(ctx) == X509_V_OK) {
		X509_STORE_CTX_set_error(ctx, X509_V_ERR_CERT_REJECTED);
	    }
	    ok = 0;
	}
    }

    return ok;
}

/*
 * main module
 */
VALUE mOSSL;

/*
 * OpenSSLError < StandardError
 */
VALUE eOSSLError;

/*
 * Convert to DER string
 */
ID ossl_s_to_der;

VALUE
ossl_to_der(VALUE obj)
{
    VALUE tmp;

    tmp = rb_funcall(obj, ossl_s_to_der, 0);
    StringValue(tmp);

    return tmp;
}

VALUE
ossl_to_der_if_possible(VALUE obj)
{
    if(rb_respond_to(obj, ossl_s_to_der))
	return ossl_to_der(obj);
    return obj;
}

/*
 * Errors
 */
static VALUE
ossl_make_error(VALUE exc, const char *fmt, va_list args)
{
    char buf[BUFSIZ];
    const char *msg;
    long e;
    int len = 0;

#ifdef HAVE_ERR_PEEK_LAST_ERROR
    e = ERR_peek_last_error();
#else
    e = ERR_peek_error();
#endif
    if (fmt) {
	len = vsnprintf(buf, BUFSIZ, fmt, args);
    }
    if (len < BUFSIZ && e) {
	if (dOSSL == Qtrue) /* FULL INFO */
	    msg = ERR_error_string(e, NULL);
	else
	    msg = ERR_reason_error_string(e);
	len += snprintf(buf+len, BUFSIZ-len, "%s%s", (len ? ": " : ""), msg);
    }
    if (dOSSL == Qtrue){ /* show all errors on the stack */
	while ((e = ERR_get_error()) != 0){
	    rb_warn("error on stack: %s", ERR_error_string(e, NULL));
	}
    }
    ERR_clear_error();

    if(len > BUFSIZ) len = strlen(buf);
    return rb_exc_new(exc, buf, len);
}

void
ossl_raise(VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE err;
    va_start(args, fmt);
    err = ossl_make_error(exc, fmt, args);
    va_end(args);
    rb_exc_raise(err);
}

VALUE
ossl_exc_new(VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE err;
    va_start(args, fmt);
    err = ossl_make_error(exc, fmt, args);
    va_end(args);
    return err;
}

/*
 * call-seq:
 *   OpenSSL.errors -> [String...]
 *
 * See any remaining errors held in queue.
 *
 * Any errors you see here are probably due to a bug in ruby's OpenSSL implementation.
 */
VALUE
ossl_get_errors()
{
    VALUE ary;
    long e;

    ary = rb_ary_new();
    while ((e = ERR_get_error()) != 0){
        rb_ary_push(ary, rb_str_new2(ERR_error_string(e, NULL)));
    }

    return ary;
}

/*
 * Debug
 */
VALUE dOSSL;

#if !defined(HAVE_VA_ARGS_MACRO)
void
ossl_debug(const char *fmt, ...)
{
    va_list args;
	
    if (dOSSL == Qtrue) {
	fprintf(stderr, "OSSL_DEBUG: ");
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, " [CONTEXT N/A]\n");
    }
}
#endif

/*
 * call-seq:
 *   OpenSSL.debug -> true | false
 */
static VALUE
ossl_debug_get(VALUE self)
{
    return dOSSL;
}

/*
 * call-seq:
 *   OpenSSL.debug = boolean -> boolean
 *
 * Turns on or off CRYPTO_MEM_CHECK.
 * Also shows some debugging message on stderr.
 */
static VALUE
ossl_debug_set(VALUE self, VALUE val)
{
    VALUE old = dOSSL;
    dOSSL = val;
	
    if (old != dOSSL) {
	if (dOSSL == Qtrue) {
	    CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);
	    fprintf(stderr, "OSSL_DEBUG: IS NOW ON!\n");
	} else if (old == Qtrue) {
	    CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_OFF);
	    fprintf(stderr, "OSSL_DEBUG: IS NOW OFF!\n");
	}
    }
    return val;
}

/*
 * OSSL library init
 */
void
Init_openssl()
{
    /*
     * Init timezone info
     */
#if 0
    tzset();
#endif

    /*
     * Init all digests, ciphers
     */
    /* CRYPTO_malloc_init(); */
    /* ENGINE_load_builtin_engines(); */
    OpenSSL_add_ssl_algorithms();
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();
    SSL_load_error_strings();

    /*
     * FIXME:
     * On unload do:
     */
#if 0
    CONF_modules_unload(1);
    destroy_ui_method();
    EVP_cleanup();
    ENGINE_cleanup();
    CRYPTO_cleanup_all_ex_data();
    ERR_remove_state(0);
    ERR_free_strings();
#endif

    /*
     * Init main module
     */
    mOSSL = rb_define_module("OpenSSL");

    /*
     * Constants
     */
    rb_define_const(mOSSL, "VERSION", rb_str_new2(OSSL_VERSION));
    rb_define_const(mOSSL, "OPENSSL_VERSION", rb_str_new2(OPENSSL_VERSION_TEXT));
    rb_define_const(mOSSL, "OPENSSL_VERSION_NUMBER", INT2NUM(OPENSSL_VERSION_NUMBER));

    /*
     * Generic error,
     * common for all classes under OpenSSL module
     */
    eOSSLError = rb_define_class_under(mOSSL,"OpenSSLError",rb_eStandardError);

    /*
     * Verify callback Proc index for ext-data
     */
    if ((ossl_verify_cb_idx = X509_STORE_CTX_get_ex_new_index(0, (void *)"ossl_verify_cb_idx", 0, 0, 0)) < 0)
        ossl_raise(eOSSLError, "X509_STORE_CTX_get_ex_new_index");

    /*
     * Init debug core
     */
    dOSSL = Qfalse;
    rb_define_module_function(mOSSL, "debug", ossl_debug_get, 0);
    rb_define_module_function(mOSSL, "debug=", ossl_debug_set, 1);
    rb_define_module_function(mOSSL, "errors", ossl_get_errors, 0);

    /*
     * Get ID of to_der
     */
    ossl_s_to_der = rb_intern("to_der");

    /*
     * Init components
     */
    Init_ossl_bn();
    Init_ossl_cipher();
    Init_ossl_config();
    Init_ossl_digest();
    Init_ossl_hmac();
    Init_ossl_ns_spki();
    Init_ossl_pkcs12();
    Init_ossl_pkcs7();
    Init_ossl_pkcs5();
    Init_ossl_pkey();
    Init_ossl_rand();
    Init_ossl_ssl();
    Init_ossl_x509();
    Init_ossl_ocsp();
    Init_ossl_engine();
    Init_ossl_asn1();
}

#if defined(OSSL_DEBUG)
/*
 * Check if all symbols are OK with 'make LDSHARED=gcc all'
 */
int
main(int argc, char *argv[])
{
    return 0;
}
#endif /* OSSL_DEBUG */

