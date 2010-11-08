/*
 *  Copyright (C) 2004-2007 Technorama Ltd. <oss-ruby@technorama.net>
 */

#include "ossl.h"

#define GetSSLSession(obj, sess) do { \
	Data_Get_Struct(obj, SSL_SESSION, sess); \
	if (!sess) { \
		ossl_raise(rb_eRuntimeError, "SSL Session wasn't initialized."); \
	} \
} while (0)

#define SafeGetSSLSession(obj, sess) do { \
	OSSL_Check_Kind(obj, cSSLSession); \
	GetSSLSession(obj, sess); \
} while (0)


VALUE cSSLSession;
static VALUE eSSLSession;

static VALUE ossl_ssl_session_alloc(VALUE klass)
{
	return Data_Wrap_Struct(klass, 0, SSL_SESSION_free, NULL);
}

/*
 * call-seq:
 *    Session.new(SSLSocket | string) => session
 *
 * === Parameters
 * +SSLSocket+ is an OpenSSL::SSL::SSLSocket
 * +string+ must be a DER or PEM encoded Session.
*/
static VALUE ossl_ssl_session_initialize(VALUE self, VALUE arg1)
{
	SSL_SESSION *ctx = NULL;

	if (RDATA(self)->data)
		ossl_raise(eSSLSession, "SSL Session already initialized");

	if (rb_obj_is_instance_of(arg1, cSSLSocket)) {
		SSL *ssl;

		Data_Get_Struct(arg1, SSL, ssl);

		if (!ssl || (ctx = SSL_get1_session(ssl)) == NULL)
			ossl_raise(eSSLSession, "no session available");
	} else {
		BIO *in = ossl_obj2bio(arg1);

		ctx = PEM_read_bio_SSL_SESSION(in, NULL, NULL, NULL);

		if (!ctx) {
			(void)BIO_reset(in);
			ctx = d2i_SSL_SESSION_bio(in, NULL);
		}

		BIO_free(in);

		if (!ctx)
			ossl_raise(rb_eArgError, "unknown type");
	}

	/* should not happen */
	if (ctx == NULL)
		ossl_raise(eSSLSession, "ctx not set - internal error");

	RDATA(self)->data = ctx;

	return self;
}

#if HAVE_SSL_SESSION_CMP == 0
int SSL_SESSION_cmp(const SSL_SESSION *a,const SSL_SESSION *b)
{
    if (a->ssl_version != b->ssl_version ||
	a->session_id_length != b->session_id_length)
	return 1;
    return memcmp(a->session_id,b-> session_id, a->session_id_length);
}
#endif

/*
 * call-seq:
 *    session1 == session2 -> boolean
 *
*/
static VALUE ossl_ssl_session_eq(VALUE val1, VALUE val2)
{
	SSL_SESSION *ctx1, *ctx2;

	GetSSLSession(val1, ctx1);
	SafeGetSSLSession(val2, ctx2);

	switch (SSL_SESSION_cmp(ctx1, ctx2)) {
	case 0:		return Qtrue;
	default:	return Qfalse;
	}
}

/*
 * call-seq:
 *    session.time -> Time
 *
*/
static VALUE ossl_ssl_session_get_time(VALUE self)
{
	SSL_SESSION *ctx;
	time_t t;

	GetSSLSession(self, ctx);

	t = SSL_SESSION_get_time(ctx);

	if (t == 0)
		return Qnil;

	return rb_funcall(rb_cTime, rb_intern("at"), 1, TIMET2NUM(t));
}

/*
 * call-seq:
 *    session.timeout -> integer
 *
 * How long until the session expires in seconds.
 *
*/
static VALUE ossl_ssl_session_get_timeout(VALUE self)
{
	SSL_SESSION *ctx;
	time_t t;

	GetSSLSession(self, ctx);

	t = SSL_SESSION_get_timeout(ctx);

	return TIMET2NUM(t);
}

#define SSLSESSION_SET_TIME(func)						\
	static VALUE ossl_ssl_session_set_##func(VALUE self, VALUE time_v)	\
	{									\
		SSL_SESSION *ctx;						\
		unsigned long t;						\
										\
		GetSSLSession(self, ctx);					\
										\
		if (rb_obj_is_instance_of(time_v, rb_cTime)) {			\
			time_v = rb_funcall(time_v, rb_intern("to_i"), 0);	\
		} else if (FIXNUM_P(time_v)) {					\
			;							\
		} else {							\
			rb_raise(rb_eArgError, "unknown type");			\
		}								\
										\
		t = NUM2ULONG(time_v);						\
										\
		SSL_SESSION_set_##func(ctx, t);					\
										\
		return ossl_ssl_session_get_##func(self);			\
	}

SSLSESSION_SET_TIME(time)
SSLSESSION_SET_TIME(timeout)

#ifdef HAVE_SSL_SESSION_GET_ID
/*
 * call-seq:
 *    session.id -> aString
 *
 * Returns the Session ID.
*/
static VALUE ossl_ssl_session_get_id(VALUE self)
{
	SSL_SESSION *ctx;
	const unsigned char *p = NULL;
	unsigned int i = 0;

	GetSSLSession(self, ctx);

	p = SSL_SESSION_get_id(ctx, &i);

	return rb_str_new((const char *) p, i);
}
#endif

/*
 * call-seq:
 *    session.to_der -> aString
 *
 * Returns an ASN1 encoded String that contains the Session object.
*/
static VALUE ossl_ssl_session_to_der(VALUE self)
{
	SSL_SESSION *ctx;
	unsigned char buf[1024*10], *p;
	int len;

	GetSSLSession(self, ctx);

	p = buf;
	len = i2d_SSL_SESSION(ctx, &p);

	if (len <= 0)
		ossl_raise(eSSLSession, "i2d_SSL_SESSION");
	else if (len >= (int)sizeof(buf))
		ossl_raise(eSSLSession, "i2d_SSL_SESSION too large");

	return rb_str_new((const char *) p, len);
}

/*
 * call-seq:
 *    session.to_pem -> String
 *
 * Returns a PEM encoded String that contains the Session object.
*/
static VALUE ossl_ssl_session_to_pem(VALUE self)
{
	SSL_SESSION *ctx;
	BIO *out;
	BUF_MEM *buf;
	VALUE str;
	int i;

	GetSSLSession(self, ctx);

	if (!(out = BIO_new(BIO_s_mem()))) {
		ossl_raise(eSSLSession, "BIO_s_mem()");
	}

	if (!(i=PEM_write_bio_SSL_SESSION(out, ctx))) {
		BIO_free(out);
		ossl_raise(eSSLSession, "SSL_SESSION_print()");
	}

	BIO_get_mem_ptr(out, &buf);
	str = rb_str_new(buf->data, buf->length);
	BIO_free(out);

	return str;
}


/*
 * call-seq:
 *    session.to_text -> String
 *
 * Shows everything in the Session object.
*/
static VALUE ossl_ssl_session_to_text(VALUE self)
{
	SSL_SESSION *ctx;
	BIO *out;
	BUF_MEM *buf;
	VALUE str;

	GetSSLSession(self, ctx);

	if (!(out = BIO_new(BIO_s_mem()))) {
		ossl_raise(eSSLSession, "BIO_s_mem()");
	}

	if (!SSL_SESSION_print(out, ctx)) {
		BIO_free(out);
		ossl_raise(eSSLSession, "SSL_SESSION_print()");
	}

	BIO_get_mem_ptr(out, &buf);
	str = rb_str_new(buf->data, buf->length);
	BIO_free(out);

	return str;
}


void Init_ossl_ssl_session(void)
{
#if 0 /* let rdoc know about mOSSL */
	mOSSL = rb_define_module("OpenSSL");
	mSSL = rb_define_module_under(mOSSL, "SSL");
#endif
	cSSLSession = rb_define_class_under(mSSL, "Session", rb_cObject);
	eSSLSession = rb_define_class_under(cSSLSession, "SessionError", eOSSLError);

	rb_define_alloc_func(cSSLSession, ossl_ssl_session_alloc);
	rb_define_method(cSSLSession, "initialize", ossl_ssl_session_initialize, 1);

	rb_define_method(cSSLSession, "==", ossl_ssl_session_eq, 1);

	rb_define_method(cSSLSession, "time", ossl_ssl_session_get_time, 0);
	rb_define_method(cSSLSession, "time=", ossl_ssl_session_set_time, 1);
	rb_define_method(cSSLSession, "timeout", ossl_ssl_session_get_timeout, 0);
	rb_define_method(cSSLSession, "timeout=", ossl_ssl_session_set_timeout, 1);

#ifdef HAVE_SSL_SESSION_GET_ID
	rb_define_method(cSSLSession, "id", ossl_ssl_session_get_id, 0);
#else
	rb_undef_method(cSSLSession, "id");
#endif
	rb_define_method(cSSLSession, "to_der", ossl_ssl_session_to_der, 0);
	rb_define_method(cSSLSession, "to_pem", ossl_ssl_session_to_pem, 0);
	rb_define_method(cSSLSession, "to_text", ossl_ssl_session_to_text, 0);
}
