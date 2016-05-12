/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2003  Michal Rokos <m.rokos@sh.cvut.cz>
 * Copyright (C) 2003  GOTOU Yuuzou <gotoyuzo@notwork.org>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if defined(OSSL_OCSP_ENABLED)

#define NewOCSPReq(klass) \
    TypedData_Wrap_Struct((klass), &ossl_ocsp_request_type, 0)
#define SetOCSPReq(obj, req) do { \
    if(!(req)) ossl_raise(rb_eRuntimeError, "Request wasn't initialized!"); \
    RTYPEDDATA_DATA(obj) = (req); \
} while (0)
#define GetOCSPReq(obj, req) do { \
    TypedData_Get_Struct((obj), OCSP_REQUEST, &ossl_ocsp_request_type, (req)); \
    if(!(req)) ossl_raise(rb_eRuntimeError, "Request wasn't initialized!"); \
} while (0)
#define SafeGetOCSPReq(obj, req) do { \
    OSSL_Check_Kind((obj), cOCSPReq); \
    GetOCSPReq((obj), (req)); \
} while (0)

#define NewOCSPRes(klass) \
    TypedData_Wrap_Struct((klass), &ossl_ocsp_response_type, 0)
#define SetOCSPRes(obj, res) do { \
    if(!(res)) ossl_raise(rb_eRuntimeError, "Response wasn't initialized!"); \
    RTYPEDDATA_DATA(obj) = (res); \
} while (0)
#define GetOCSPRes(obj, res) do { \
    TypedData_Get_Struct((obj), OCSP_RESPONSE, &ossl_ocsp_response_type, (res)); \
    if(!(res)) ossl_raise(rb_eRuntimeError, "Response wasn't initialized!"); \
} while (0)
#define SafeGetOCSPRes(obj, res) do { \
    OSSL_Check_Kind((obj), cOCSPRes); \
    GetOCSPRes((obj), (res)); \
} while (0)

#define NewOCSPBasicRes(klass) \
    TypedData_Wrap_Struct((klass), &ossl_ocsp_basicresp_type, 0)
#define SetOCSPBasicRes(obj, res) do { \
    if(!(res)) ossl_raise(rb_eRuntimeError, "Response wasn't initialized!"); \
    RTYPEDDATA_DATA(obj) = (res); \
} while (0)
#define GetOCSPBasicRes(obj, res) do { \
    TypedData_Get_Struct((obj), OCSP_BASICRESP, &ossl_ocsp_basicresp_type, (res)); \
    if(!(res)) ossl_raise(rb_eRuntimeError, "Response wasn't initialized!"); \
} while (0)
#define SafeGetOCSPBasicRes(obj, res) do { \
    OSSL_Check_Kind((obj), cOCSPBasicRes); \
    GetOCSPBasicRes((obj), (res)); \
} while (0)

#define NewOCSPCertId(klass) \
    TypedData_Wrap_Struct((klass), &ossl_ocsp_certid_type, 0)
#define SetOCSPCertId(obj, cid) do { \
    if(!(cid)) ossl_raise(rb_eRuntimeError, "Cert ID wasn't initialized!"); \
    RTYPEDDATA_DATA(obj) = (cid); \
} while (0)
#define GetOCSPCertId(obj, cid) do { \
    TypedData_Get_Struct((obj), OCSP_CERTID, &ossl_ocsp_certid_type, (cid)); \
    if(!(cid)) ossl_raise(rb_eRuntimeError, "Cert ID wasn't initialized!"); \
} while (0)
#define SafeGetOCSPCertId(obj, cid) do { \
    OSSL_Check_Kind((obj), cOCSPCertId); \
    GetOCSPCertId((obj), (cid)); \
} while (0)

VALUE mOCSP;
VALUE eOCSPError;
VALUE cOCSPReq;
VALUE cOCSPRes;
VALUE cOCSPBasicRes;
VALUE cOCSPCertId;

static void
ossl_ocsp_request_free(void *ptr)
{
    OCSP_REQUEST_free(ptr);
}

static const rb_data_type_t ossl_ocsp_request_type = {
    "OpenSSL/OCSP/REQUEST",
    {
	0, ossl_ocsp_request_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static void
ossl_ocsp_response_free(void *ptr)
{
    OCSP_RESPONSE_free(ptr);
}

static const rb_data_type_t ossl_ocsp_response_type = {
    "OpenSSL/OCSP/RESPONSE",
    {
	0, ossl_ocsp_response_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static void
ossl_ocsp_basicresp_free(void *ptr)
{
    OCSP_BASICRESP_free(ptr);
}

static const rb_data_type_t ossl_ocsp_basicresp_type = {
    "OpenSSL/OCSP/BASICRESP",
    {
	0, ossl_ocsp_basicresp_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static void
ossl_ocsp_certid_free(void *ptr)
{
    OCSP_CERTID_free(ptr);
}

static const rb_data_type_t ossl_ocsp_certid_type = {
    "OpenSSL/OCSP/CERTID",
    {
	0, ossl_ocsp_certid_free,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

/*
 * Public
 */
static VALUE
ossl_ocspcertid_new(OCSP_CERTID *cid)
{
    VALUE obj = NewOCSPCertId(cOCSPCertId);
    SetOCSPCertId(obj, cid);
    return obj;
}

/*
 * OCSP::Resquest
 */
static VALUE
ossl_ocspreq_alloc(VALUE klass)
{
    OCSP_REQUEST *req;
    VALUE obj;

    obj = NewOCSPReq(klass);
    if (!(req = OCSP_REQUEST_new()))
	ossl_raise(eOCSPError, NULL);
    SetOCSPReq(obj, req);

    return obj;
}

/*
 * call-seq:
 *   OpenSSL::OCSP::Request.new              -> request
 *   OpenSSL::OCSP::Request.new(request_der) -> request
 *
 * Creates a new OpenSSL::OCSP::Request.  The request may be created empty or
 * from a +request_der+ string.
 */

static VALUE
ossl_ocspreq_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE arg;
    const unsigned char *p;

    rb_scan_args(argc, argv, "01", &arg);
    if(!NIL_P(arg)){
	OCSP_REQUEST *req = DATA_PTR(self), *x;
	arg = ossl_to_der_if_possible(arg);
	StringValue(arg);
	p = (unsigned char*)RSTRING_PTR(arg);
	x = d2i_OCSP_REQUEST(&req, &p, RSTRING_LEN(arg));
	DATA_PTR(self) = req;
	if(!x){
	    ossl_raise(eOCSPError, "cannot load DER encoded request");
	}
    }

    return self;
}

/*
 * call-seq:
 *   request.add_nonce(nonce = nil) -> request
 *
 * Adds a +nonce+ to the OCSP request.  If no nonce is given a random one will
 * be generated.
 *
 * The nonce is used to prevent replay attacks but some servers do not support
 * it.
 */

static VALUE
ossl_ocspreq_add_nonce(int argc, VALUE *argv, VALUE self)
{
    OCSP_REQUEST *req;
    VALUE val;
    int ret;

    rb_scan_args(argc, argv, "01", &val);
    if(NIL_P(val)) {
	GetOCSPReq(self, req);
	ret = OCSP_request_add1_nonce(req, NULL, -1);
    }
    else{
	StringValue(val);
	GetOCSPReq(self, req);
	ret = OCSP_request_add1_nonce(req, (unsigned char *)RSTRING_PTR(val), RSTRING_LENINT(val));
    }
    if(!ret) ossl_raise(eOCSPError, NULL);

    return self;
}

/*
 * call-seq:
 *   request.check_nonce(response) -> result
 *
 * Checks the nonce validity for this request and +response+.
 *
 * The return value is one of the following:
 *
 * -1 :: nonce in request only.
 *  0 :: nonces both present and not equal.
 *  1 :: nonces present and equal.
 *  2 :: nonces both absent.
 *  3 :: nonce present in response only.
 *
 * For most responses, clients can check +result+ > 0.  If a responder doesn't
 * handle nonces <code>result.nonzero?</code> may be necessary.  A result of
 * <code>0</code> is always an error.
 */

static VALUE
ossl_ocspreq_check_nonce(VALUE self, VALUE basic_resp)
{
    OCSP_REQUEST *req;
    OCSP_BASICRESP *bs;
    int res;

    GetOCSPReq(self, req);
    SafeGetOCSPBasicRes(basic_resp, bs);
    res = OCSP_check_nonce(req, bs);

    return INT2NUM(res);
}

/*
 * call-seq:
 *   request.add_certid(certificate_id) -> request
 *
 * Adds +certificate_id+ to the request.
 */

static VALUE
ossl_ocspreq_add_certid(VALUE self, VALUE certid)
{
    OCSP_REQUEST *req;
    OCSP_CERTID *id;

    GetOCSPReq(self, req);
    GetOCSPCertId(certid, id);
    if(!OCSP_request_add0_id(req, OCSP_CERTID_dup(id)))
	ossl_raise(eOCSPError, NULL);

    return self;
}

/*
 * call-seq:
 *   request.certid -> [certificate_id, ...]
 *
 * Returns all certificate IDs in this request.
 */

static VALUE
ossl_ocspreq_get_certid(VALUE self)
{
    OCSP_REQUEST *req;
    OCSP_ONEREQ *one;
    OCSP_CERTID *id;
    VALUE ary, tmp;
    int i, count;

    GetOCSPReq(self, req);
    count = OCSP_request_onereq_count(req);
    ary = (count > 0) ? rb_ary_new() : Qnil;
    for(i = 0; i < count; i++){
	one = OCSP_request_onereq_get0(req, i);
	tmp = NewOCSPCertId(cOCSPCertId);
	if(!(id = OCSP_CERTID_dup(OCSP_onereq_get0_id(one))))
	    ossl_raise(eOCSPError, NULL);
	SetOCSPCertId(tmp, id);
	rb_ary_push(ary, tmp);
    }

    return ary;
}

/*
 * call-seq:
 *   request.sign(signer_cert, signer_key)                      -> self
 *   request.sign(signer_cert, signer_key, certificates)        -> self
 *   request.sign(signer_cert, signer_key, certificates, flags) -> self
 *
 * Signs this OCSP request using +signer_cert+ and +signer_key+.
 * +certificates+ is an optional Array of certificates that may be included in
 * the request.
 */

static VALUE
ossl_ocspreq_sign(int argc, VALUE *argv, VALUE self)
{
    VALUE signer_cert, signer_key, certs, flags;
    OCSP_REQUEST *req;
    X509 *signer;
    EVP_PKEY *key;
    STACK_OF(X509) *x509s;
    unsigned long flg;
    int ret;

    rb_scan_args(argc, argv, "22", &signer_cert, &signer_key, &certs, &flags);
    signer = GetX509CertPtr(signer_cert);
    key = GetPrivPKeyPtr(signer_key);
    flg = NIL_P(flags) ? 0 : NUM2INT(flags);
    if(NIL_P(certs)){
	x509s = sk_X509_new_null();
	flags |= OCSP_NOCERTS;
    }
    else x509s = ossl_x509_ary2sk(certs);
    GetOCSPReq(self, req);
    ret = OCSP_request_sign(req, signer, key, EVP_sha1(), x509s, flg);
    sk_X509_pop_free(x509s, X509_free);
    if(!ret) ossl_raise(eOCSPError, NULL);

    return self;
}

/*
 * call-seq:
 *   request.verify(certificates, store)        -> true or false
 *   request.verify(certificates, store, flags) -> true or false
 *
 * Verifies this request using the given +certificates+ and X509 +store+.
 */

static VALUE
ossl_ocspreq_verify(int argc, VALUE *argv, VALUE self)
{
    VALUE certs, store, flags;
    OCSP_REQUEST *req;
    STACK_OF(X509) *x509s;
    X509_STORE *x509st;
    int flg, result;

    rb_scan_args(argc, argv, "21", &certs, &store, &flags);
    x509st = GetX509StorePtr(store);
    flg = NIL_P(flags) ? 0 : NUM2INT(flags);
    x509s = ossl_x509_ary2sk(certs);
    GetOCSPReq(self, req);
    result = OCSP_request_verify(req, x509s, x509st, flg);
    sk_X509_pop_free(x509s, X509_free);
    if(!result) rb_warn("%s", ERR_error_string(ERR_peek_error(), NULL));

    return result ? Qtrue : Qfalse;
}

/*
 * Returns this request as a DER-encoded string
 */

static VALUE
ossl_ocspreq_to_der(VALUE self)
{
    OCSP_REQUEST *req;
    VALUE str;
    unsigned char *p;
    long len;

    GetOCSPReq(self, req);
    if((len = i2d_OCSP_REQUEST(req, NULL)) <= 0)
	ossl_raise(eOCSPError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_OCSP_REQUEST(req, &p) <= 0)
	ossl_raise(eOCSPError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 * OCSP::Response
 */

/* call-seq:
 *   OpenSSL::OCSP::Response.create(status, basic_response = nil) -> response
 *
 * Creates an OpenSSL::OCSP::Response from +status+ and +basic_response+.
 */

static VALUE
ossl_ocspres_s_create(VALUE klass, VALUE status, VALUE basic_resp)
{
    OCSP_BASICRESP *bs;
    OCSP_RESPONSE *res;
    VALUE obj;
    int st = NUM2INT(status);

    if(NIL_P(basic_resp)) bs = NULL;
    else GetOCSPBasicRes(basic_resp, bs); /* NO NEED TO DUP */
    obj = NewOCSPRes(klass);
    if(!(res = OCSP_response_create(st, bs)))
	ossl_raise(eOCSPError, NULL);
    SetOCSPRes(obj, res);

    return obj;
}

static VALUE
ossl_ocspres_alloc(VALUE klass)
{
    OCSP_RESPONSE *res;
    VALUE obj;

    obj = NewOCSPRes(klass);
    if(!(res = OCSP_RESPONSE_new()))
	ossl_raise(eOCSPError, NULL);
    SetOCSPRes(obj, res);

    return obj;
}

/*
 * call-seq:
 *   OpenSSL::OCSP::Response.new               -> response
 *   OpenSSL::OCSP::Response.new(response_der) -> response
 *
 * Creates a new OpenSSL::OCSP::Response.  The response may be created empty or
 * from a +response_der+ string.
 */

static VALUE
ossl_ocspres_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE arg;
    const unsigned char *p;

    rb_scan_args(argc, argv, "01", &arg);
    if(!NIL_P(arg)){
	OCSP_RESPONSE *res = DATA_PTR(self), *x;
	arg = ossl_to_der_if_possible(arg);
	StringValue(arg);
	p = (unsigned char *)RSTRING_PTR(arg);
	x = d2i_OCSP_RESPONSE(&res, &p, RSTRING_LEN(arg));
	DATA_PTR(self) = res;
	if(!x){
	    ossl_raise(eOCSPError, "cannot load DER encoded response");
	}
    }

    return self;
}

/*
 * call-seq:
 *   response.status -> Integer
 *
 * Returns the status of the response.
 */

static VALUE
ossl_ocspres_status(VALUE self)
{
    OCSP_RESPONSE *res;
    int st;

    GetOCSPRes(self, res);
    st = OCSP_response_status(res);

    return INT2NUM(st);
}

/*
 * call-seq:
 *   response.status_string -> String
 *
 * Returns a status string for the response.
 */

static VALUE
ossl_ocspres_status_string(VALUE self)
{
    OCSP_RESPONSE *res;
    int st;

    GetOCSPRes(self, res);
    st = OCSP_response_status(res);

    return rb_str_new2(OCSP_response_status_str(st));
}

/*
 * call-seq:
 *   response.basic
 *
 * Returns a BasicResponse for this response
 */

static VALUE
ossl_ocspres_get_basic(VALUE self)
{
    OCSP_RESPONSE *res;
    OCSP_BASICRESP *bs;
    VALUE ret;

    GetOCSPRes(self, res);
    ret = NewOCSPBasicRes(cOCSPBasicRes);
    if(!(bs = OCSP_response_get1_basic(res)))
	return Qnil;
    SetOCSPBasicRes(ret, bs);

    return ret;
}

/*
 * call-seq:
 *   response.to_der -> String
 *
 * Returns this response as a DER-encoded string.
 */

static VALUE
ossl_ocspres_to_der(VALUE self)
{
    OCSP_RESPONSE *res;
    VALUE str;
    long len;
    unsigned char *p;

    GetOCSPRes(self, res);
    if((len = i2d_OCSP_RESPONSE(res, NULL)) <= 0)
	ossl_raise(eOCSPError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_OCSP_RESPONSE(res, &p) <= 0)
	ossl_raise(eOCSPError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 * OCSP::BasicResponse
 */
static VALUE
ossl_ocspbres_alloc(VALUE klass)
{
    OCSP_BASICRESP *bs;
    VALUE obj;

    obj = NewOCSPBasicRes(klass);
    if(!(bs = OCSP_BASICRESP_new()))
	ossl_raise(eOCSPError, NULL);
    SetOCSPBasicRes(obj, bs);

    return obj;
}

/*
 * call-seq:
 *   OpenSSL::OCSP::BasicResponse.new(*) -> basic_response
 *
 * Creates a new BasicResponse and ignores all arguments.
 */

static VALUE
ossl_ocspbres_initialize(int argc, VALUE *argv, VALUE self)
{
    return self;
}

/*
 * call-seq:
 *   basic_response.copy_nonce(request) -> Integer
 *
 * Copies the nonce from +request+ into this response.  Returns 1 on success
 * and 0 on failure.
 */

static VALUE
ossl_ocspbres_copy_nonce(VALUE self, VALUE request)
{
    OCSP_BASICRESP *bs;
    OCSP_REQUEST *req;
    int ret;

    GetOCSPBasicRes(self, bs);
    SafeGetOCSPReq(request, req);
    ret = OCSP_copy_nonce(bs, req);

    return INT2NUM(ret);
}

/*
 * call-seq:
 *   basic_response.add_nonce(nonce = nil)
 *
 * Adds +nonce+ to this response.  If no nonce was provided a random nonce
 * will be added.
 */

static VALUE
ossl_ocspbres_add_nonce(int argc, VALUE *argv, VALUE self)
{
    OCSP_BASICRESP *bs;
    VALUE val;
    int ret;

    rb_scan_args(argc, argv, "01", &val);
    if(NIL_P(val)) {
	GetOCSPBasicRes(self, bs);
	ret = OCSP_basic_add1_nonce(bs, NULL, -1);
    }
    else{
	StringValue(val);
	GetOCSPBasicRes(self, bs);
	ret = OCSP_basic_add1_nonce(bs, (unsigned char *)RSTRING_PTR(val), RSTRING_LENINT(val));
    }
    if(!ret) ossl_raise(eOCSPError, NULL);

    return self;
}

/*
 * call-seq:
 *   basic_response.add_status(certificate_id, status, reason, revocation_time, this_update, next_update, extensions) -> basic_response
 *
 * Adds a validation +status+ (0 for good, 1 for revoked, 2 for unknown) to this
 * response for +certificate_id+.  +reason+ describes the reason for the
 * revocation, if any.
 *
 * The +revocation_time+, +this_update+ and +next_update+ are times for the
 * certificate's revocation time, the time of this status and the next update
 * time for a new status, respectively.
 *
 * +extensions+ may be an Array of OpenSSL::X509::Extension that will
 * be added to this response or nil.
 */

static VALUE
ossl_ocspbres_add_status(VALUE self, VALUE cid, VALUE status,
			 VALUE reason, VALUE revtime,
			 VALUE thisupd, VALUE nextupd, VALUE ext)
{
    OCSP_BASICRESP *bs;
    OCSP_SINGLERESP *single;
    OCSP_CERTID *id;
    ASN1_TIME *ths, *nxt, *rev;
    int st, rsn, error, rstatus = 0;
    long i;
    VALUE tmp;

    st = NUM2INT(status);
    rsn = NIL_P(status) ? 0 : NUM2INT(reason);
    if(!NIL_P(ext)){
	/* All ary's members should be X509Extension */
	Check_Type(ext, T_ARRAY);
	for (i = 0; i < RARRAY_LEN(ext); i++)
	    OSSL_Check_Kind(RARRAY_AREF(ext, i), cX509Ext);
    }

    error = 0;
    ths = nxt = rev = NULL;
    if(!NIL_P(revtime)){
	tmp = rb_protect(rb_Integer, revtime, &rstatus);
	if(rstatus) goto err;
	rev = X509_gmtime_adj(NULL, NUM2INT(tmp));
    }
    tmp = rb_protect(rb_Integer, thisupd, &rstatus);
    if(rstatus) goto err;
    ths = X509_gmtime_adj(NULL, NUM2INT(tmp));
    tmp = rb_protect(rb_Integer, nextupd, &rstatus);
    if(rstatus) goto err;
    nxt = X509_gmtime_adj(NULL, NUM2INT(tmp));

    GetOCSPBasicRes(self, bs);
    SafeGetOCSPCertId(cid, id);
    if(!(single = OCSP_basic_add1_status(bs, id, st, rsn, rev, ths, nxt))){
	error = 1;
	goto err;
    }

    if(!NIL_P(ext)){
	X509_EXTENSION *x509ext;
	sk_X509_EXTENSION_pop_free(single->singleExtensions, X509_EXTENSION_free);
	single->singleExtensions = NULL;
	for(i = 0; i < RARRAY_LEN(ext); i++){
	    x509ext = DupX509ExtPtr(RARRAY_AREF(ext, i));
	    if(!OCSP_SINGLERESP_add_ext(single, x509ext, -1)){
		X509_EXTENSION_free(x509ext);
		error = 1;
		goto err;
	    }
	    X509_EXTENSION_free(x509ext);
	}
    }

 err:
    ASN1_TIME_free(ths);
    ASN1_TIME_free(nxt);
    ASN1_TIME_free(rev);
    if(error) ossl_raise(eOCSPError, NULL);
    if(rstatus) rb_jump_tag(rstatus);

    return self;
}

/*
 * call-seq:
 *   basic_response.status -> statuses
 *
 * Returns an Array of statuses for this response.  Each status contains a
 * CertificateId, the status (0 for good, 1 for revoked, 2 for unknown), the reason for
 * the status, the revocation time, the time of this update, the time for the
 * next update and a list of OpenSSL::X509::Extensions.
 */

static VALUE
ossl_ocspbres_get_status(VALUE self)
{
    OCSP_BASICRESP *bs;
    OCSP_SINGLERESP *single;
    OCSP_CERTID *cid;
    ASN1_TIME *revtime, *thisupd, *nextupd;
    int status, reason;
    X509_EXTENSION *x509ext;
    VALUE ret, ary, ext;
    int count, ext_count, i, j;

    GetOCSPBasicRes(self, bs);
    ret = rb_ary_new();
    count = OCSP_resp_count(bs);
    for(i = 0; i < count; i++){
	single = OCSP_resp_get0(bs, i);
	if(!single) continue;

	revtime = thisupd = nextupd = NULL;
	status = OCSP_single_get0_status(single, &reason, &revtime,
					 &thisupd, &nextupd);
	if(status < 0) continue;
	if(!(cid = OCSP_CERTID_dup(single->certId)))
	    ossl_raise(eOCSPError, NULL);
	ary = rb_ary_new();
	rb_ary_push(ary, ossl_ocspcertid_new(cid));
	rb_ary_push(ary, INT2NUM(status));
	rb_ary_push(ary, INT2NUM(reason));
	rb_ary_push(ary, revtime ? asn1time_to_time(revtime) : Qnil);
	rb_ary_push(ary, thisupd ? asn1time_to_time(thisupd) : Qnil);
	rb_ary_push(ary, nextupd ? asn1time_to_time(nextupd) : Qnil);
	ext = rb_ary_new();
	ext_count = OCSP_SINGLERESP_get_ext_count(single);
	for(j = 0; j < ext_count; j++){
	    x509ext = OCSP_SINGLERESP_get_ext(single, j);
	    rb_ary_push(ext, ossl_x509ext_new(x509ext));
	}
	rb_ary_push(ary, ext);
	rb_ary_push(ret, ary);
    }

    return ret;
}

/*
 * call-seq:
 *   basic_response.sign(signer_cert, signer_key) -> self
 *   basic_response.sign(signer_cert, signer_key, certificates) -> self
 *   basic_response.sign(signer_cert, signer_key, certificates, flags) -> self
 *
 * Signs this response using the +signer_cert+ and +signer_key+.  Additional
 * +certificates+ may be added to the signature along with a set of +flags+.
 */

static VALUE
ossl_ocspbres_sign(int argc, VALUE *argv, VALUE self)
{
    VALUE signer_cert, signer_key, certs, flags;
    OCSP_BASICRESP *bs;
    X509 *signer;
    EVP_PKEY *key;
    STACK_OF(X509) *x509s;
    unsigned long flg;
    int ret;

    rb_scan_args(argc, argv, "22", &signer_cert, &signer_key, &certs, &flags);
    signer = GetX509CertPtr(signer_cert);
    key = GetPrivPKeyPtr(signer_key);
    flg = NIL_P(flags) ? 0 : NUM2INT(flags);
    if(NIL_P(certs)){
	x509s = sk_X509_new_null();
	flg |= OCSP_NOCERTS;
    }
    else{
	x509s = ossl_x509_ary2sk(certs);
    }
    GetOCSPBasicRes(self, bs);
    ret = OCSP_basic_sign(bs, signer, key, EVP_sha1(), x509s, flg);
    sk_X509_pop_free(x509s, X509_free);
    if(!ret) ossl_raise(eOCSPError, NULL);

    return self;
}

/*
 * call-seq:
 *   basic_response.verify(certificates, store) -> true or false
 *   basic_response.verify(certificates, store, flags) -> true or false
 *
 * Verifies the signature of the response using the given +certificates+,
 * +store+ and +flags+.
 */
static VALUE
ossl_ocspbres_verify(int argc, VALUE *argv, VALUE self)
{
    VALUE certs, store, flags, result;
    OCSP_BASICRESP *bs;
    STACK_OF(X509) *x509s;
    X509_STORE *x509st;
    int flg;

    rb_scan_args(argc, argv, "21", &certs, &store, &flags);
    x509st = GetX509StorePtr(store);
    flg = NIL_P(flags) ? 0 : NUM2INT(flags);
    x509s = ossl_x509_ary2sk(certs);
    GetOCSPBasicRes(self, bs);
    result = OCSP_basic_verify(bs, x509s, x509st, flg) > 0 ? Qtrue : Qfalse;
    sk_X509_pop_free(x509s, X509_free);
    if(!result) rb_warn("%s", ERR_error_string(ERR_peek_error(), NULL));

    return result;
}

/*
 * OCSP::CertificateId
 */
static VALUE
ossl_ocspcid_alloc(VALUE klass)
{
    OCSP_CERTID *id;
    VALUE obj;

    obj = NewOCSPCertId(klass);
    if(!(id = OCSP_CERTID_new()))
	ossl_raise(eOCSPError, NULL);
    SetOCSPCertId(obj, id);

    return obj;
}

/*
 * call-seq:
 *   OpenSSL::OCSP::CertificateId.new(subject, issuer, digest = nil) -> certificate_id
 *
 * Creates a new OpenSSL::OCSP::CertificateId for the given +subject+ and
 * +issuer+ X509 certificates.  The +digest+ is used to compute the
 * certificate ID and must be an OpenSSL::Digest instance.
 */

static VALUE
ossl_ocspcid_initialize(int argc, VALUE *argv, VALUE self)
{
    OCSP_CERTID *id, *newid;
    X509 *x509s, *x509i;
    VALUE subject, issuer, digest;
    const EVP_MD *md;

    if (rb_scan_args(argc, argv, "21", &subject, &issuer, &digest) == 0) {
	return self;
    }

    x509s = GetX509CertPtr(subject); /* NO NEED TO DUP */
    x509i = GetX509CertPtr(issuer); /* NO NEED TO DUP */

    if (!NIL_P(digest)) {
	md = GetDigestPtr(digest);
	newid = OCSP_cert_to_id(md, x509s, x509i);
    } else {
	newid = OCSP_cert_to_id(NULL, x509s, x509i);
    }
    if(!newid)
	ossl_raise(eOCSPError, NULL);
    GetOCSPCertId(self, id);
    OCSP_CERTID_free(id);
    RDATA(self)->data = newid;

    return self;
}

/*
 * call-seq:
 *   certificate_id.cmp(other) -> true or false
 *
 * Compares this certificate id with +other+ and returns true if they are the
 * same.
 */
static VALUE
ossl_ocspcid_cmp(VALUE self, VALUE other)
{
    OCSP_CERTID *id, *id2;
    int result;

    GetOCSPCertId(self, id);
    SafeGetOCSPCertId(other, id2);
    result = OCSP_id_cmp(id, id2);

    return (result == 0) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   certificate_id.cmp_issuer(other) -> true or false
 *
 * Compares this certificate id's issuer with +other+ and returns true if
 * they are the same.
 */

static VALUE
ossl_ocspcid_cmp_issuer(VALUE self, VALUE other)
{
    OCSP_CERTID *id, *id2;
    int result;

    GetOCSPCertId(self, id);
    SafeGetOCSPCertId(other, id2);
    result = OCSP_id_issuer_cmp(id, id2);

    return (result == 0) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   certificate_id.get_serial -> Integer
 *
 * Returns the serial number of the issuing certificate.
 */

static VALUE
ossl_ocspcid_get_serial(VALUE self)
{
    OCSP_CERTID *id;

    GetOCSPCertId(self, id);

    return asn1integer_to_num(id->serialNumber);
}

void
Init_ossl_ocsp(void)
{
    /*
     * OpenSSL::OCSP implements Online Certificate Status Protocol requests
     * and responses.
     *
     * Creating and sending an OCSP request requires a subject certificate
     * that contains an OCSP URL in an authorityInfoAccess extension and the
     * issuer certificate for the subject certificate.  First, load the issuer
     * and subject certificates:
     *
     *   subject = OpenSSL::X509::Certificate.new subject_pem
     *   issuer  = OpenSSL::X509::Certificate.new issuer_pem
     *
     * To create the request we need to create a certificate ID for the
     * subject certificate so the CA knows which certificate we are asking
     * about:
     *
     *   digest = OpenSSL::Digest::SHA1.new
     *   certificate_id =
     *     OpenSSL::OCSP::CertificateId.new subject, issuer, digest
     *
     * Then create a request and add the certificate ID to it:
     *
     *   request = OpenSSL::OCSP::Request.new
     *   request.add_certid certificate_id
     *
     * Adding a nonce to the request protects against replay attacks but not
     * all CA process the nonce.
     *
     *   request.add_nonce
     *
     * To submit the request to the CA for verification we need to extract the
     * OCSP URI from the subject certificate:
     *
     *   authority_info_access = subject.extensions.find do |extension|
     *     extension.oid == 'authorityInfoAccess'
     *   end
     *
     *   descriptions = authority_info_access.value.split "\n"
     *   ocsp = descriptions.find do |description|
     *     description.start_with? 'OCSP'
     *   end
     *
     *   require 'uri'
     *
     *   ocsp_uri = URI ocsp[/URI:(.*)/, 1]
     *
     * To submit the request we'll POST the request to the OCSP URI (per RFC
     * 2560).  Note that we only handle HTTP requests and don't handle any
     * redirects in this example, so this is insufficient for serious use.
     *
     *   require 'net/http'
     *
     *   http_response =
     *     Net::HTTP.start ocsp_uri.hostname, ocsp.port do |http|
     *       http.post ocsp_uri.path, request.to_der,
     *                 'content-type' => 'application/ocsp-request'
     *   end
     *
     *   response = OpenSSL::OCSP::Response.new http_response.body
     *   response_basic = response.basic
     *
     * First we check if the response has a valid signature.  Without a valid
     * signature we cannot trust it.  If you get a failure here you may be
     * missing a system certificate store or may be missing the intermediate
     * certificates.
     *
     *   store = OpenSSL::X509::Store.new
     *   store.set_default_paths
     *
     *   unless response.verify [], store then
     *     raise 'response is not signed by a trusted certificate'
     *   end
     *
     * The response contains the status information (success/fail).  We can
     * display the status as a string:
     *
     *   puts response.status_string #=> successful
     *
     * Next we need to know the response details to determine if the response
     * matches our request.  First we check the nonce.  Again, not all CAs
     * support a nonce.  See Request#check_nonce for the meanings of the
     * return values.
     *
     *   p request.check_nonce basic_response #=> value from -1 to 3
     *
     * Then extract the status information from the basic response.  (You can
     * check multiple certificates in a request, but for this example we only
     * submitted one.)
     *
     *   response_certificate_id, status, reason, revocation_time,
     *     this_update, next_update, extensions = basic_response.status
     *
     * Then check the various fields.
     *
     *   unless response_certificate_id == certificate_id then
     *     raise 'certificate id mismatch'
     *   end
     *
     *   now = Time.now
     *
     *   if this_update > now then
     *     raise 'update date is in the future'
     *   end
     *
     *   if now > next_update then
     *     raise 'next update time has passed'
     *   end
     */

    mOCSP = rb_define_module_under(mOSSL, "OCSP");

    /*
     * OCSP error class.
     */

    eOCSPError = rb_define_class_under(mOCSP, "OCSPError", eOSSLError);

    /*
     * An OpenSSL::OCSP::Request contains the certificate information for
     * determining if a certificate has been revoked or not.  A Request can be
     * created for a certificate or from a DER-encoded request created
     * elsewhere.
     */

    cOCSPReq = rb_define_class_under(mOCSP, "Request", rb_cObject);
    rb_define_alloc_func(cOCSPReq, ossl_ocspreq_alloc);
    rb_define_method(cOCSPReq, "initialize", ossl_ocspreq_initialize, -1);
    rb_define_method(cOCSPReq, "add_nonce", ossl_ocspreq_add_nonce, -1);
    rb_define_method(cOCSPReq, "check_nonce", ossl_ocspreq_check_nonce, 1);
    rb_define_method(cOCSPReq, "add_certid", ossl_ocspreq_add_certid, 1);
    rb_define_method(cOCSPReq, "certid", ossl_ocspreq_get_certid, 0);
    rb_define_method(cOCSPReq, "sign", ossl_ocspreq_sign, -1);
    rb_define_method(cOCSPReq, "verify", ossl_ocspreq_verify, -1);
    rb_define_method(cOCSPReq, "to_der", ossl_ocspreq_to_der, 0);

    /*
     * An OpenSSL::OCSP::Response contains the status of a certificate check
     * which is created from an OpenSSL::OCSP::Request.
     */

    cOCSPRes = rb_define_class_under(mOCSP, "Response", rb_cObject);
    rb_define_singleton_method(cOCSPRes, "create", ossl_ocspres_s_create, 2);
    rb_define_alloc_func(cOCSPRes, ossl_ocspres_alloc);
    rb_define_method(cOCSPRes, "initialize", ossl_ocspres_initialize, -1);
    rb_define_method(cOCSPRes, "status", ossl_ocspres_status, 0);
    rb_define_method(cOCSPRes, "status_string", ossl_ocspres_status_string, 0);
    rb_define_method(cOCSPRes, "basic", ossl_ocspres_get_basic, 0);
    rb_define_method(cOCSPRes, "to_der", ossl_ocspres_to_der, 0);

    /*
     * An OpenSSL::OCSP::BasicResponse contains the status of a certificate
     * check which is created from an OpenSSL::OCSP::Request.  A
     * BasicResponse is more detailed than a Response.
     */

    cOCSPBasicRes = rb_define_class_under(mOCSP, "BasicResponse", rb_cObject);
    rb_define_alloc_func(cOCSPBasicRes, ossl_ocspbres_alloc);
    rb_define_method(cOCSPBasicRes, "initialize", ossl_ocspbres_initialize, -1);
    rb_define_method(cOCSPBasicRes, "copy_nonce", ossl_ocspbres_copy_nonce, 1);
    rb_define_method(cOCSPBasicRes, "add_nonce", ossl_ocspbres_add_nonce, -1);
    rb_define_method(cOCSPBasicRes, "add_status", ossl_ocspbres_add_status, 7);
    rb_define_method(cOCSPBasicRes, "status", ossl_ocspbres_get_status, 0);
    rb_define_method(cOCSPBasicRes, "sign", ossl_ocspbres_sign, -1);
    rb_define_method(cOCSPBasicRes, "verify", ossl_ocspbres_verify, -1);

    /*
     * An OpenSSL::OCSP::CertificateId identifies a certificate to the CA so
     * that a status check can be performed.
     */

    cOCSPCertId = rb_define_class_under(mOCSP, "CertificateId", rb_cObject);
    rb_define_alloc_func(cOCSPCertId, ossl_ocspcid_alloc);
    rb_define_method(cOCSPCertId, "initialize", ossl_ocspcid_initialize, -1);
    rb_define_method(cOCSPCertId, "cmp", ossl_ocspcid_cmp, 1);
    rb_define_method(cOCSPCertId, "cmp_issuer", ossl_ocspcid_cmp_issuer, 1);
    rb_define_method(cOCSPCertId, "serial", ossl_ocspcid_get_serial, 0);

    /* Internal error in issuer */
    rb_define_const(mOCSP, "RESPONSE_STATUS_INTERNALERROR", INT2NUM(OCSP_RESPONSE_STATUS_INTERNALERROR));

    /* Illegal confirmation request */
    rb_define_const(mOCSP, "RESPONSE_STATUS_MALFORMEDREQUEST", INT2NUM(OCSP_RESPONSE_STATUS_MALFORMEDREQUEST));

    /* The certificate was revoked for an unknown reason */
    rb_define_const(mOCSP, "REVOKED_STATUS_NOSTATUS", INT2NUM(OCSP_REVOKED_STATUS_NOSTATUS));

    /* You must sign the request and resubmit */
    rb_define_const(mOCSP, "RESPONSE_STATUS_SIGREQUIRED", INT2NUM(OCSP_RESPONSE_STATUS_SIGREQUIRED));

    /* Response has valid confirmations */
    rb_define_const(mOCSP, "RESPONSE_STATUS_SUCCESSFUL", INT2NUM(OCSP_RESPONSE_STATUS_SUCCESSFUL));

    /* Try again later */
    rb_define_const(mOCSP, "RESPONSE_STATUS_TRYLATER", INT2NUM(OCSP_RESPONSE_STATUS_TRYLATER));

    /* The certificate subject's name or other information changed */
    rb_define_const(mOCSP, "REVOKED_STATUS_AFFILIATIONCHANGED", INT2NUM(OCSP_REVOKED_STATUS_AFFILIATIONCHANGED));

    /* This CA certificate was revoked due to a key compromise */
    rb_define_const(mOCSP, "REVOKED_STATUS_CACOMPROMISE", INT2NUM(OCSP_REVOKED_STATUS_CACOMPROMISE));

    /* The certificate is on hold */
    rb_define_const(mOCSP, "REVOKED_STATUS_CERTIFICATEHOLD", INT2NUM(OCSP_REVOKED_STATUS_CERTIFICATEHOLD));

    /* The certificate is no longer needed */
    rb_define_const(mOCSP, "REVOKED_STATUS_CESSATIONOFOPERATION", INT2NUM(OCSP_REVOKED_STATUS_CESSATIONOFOPERATION));

    /* The certificate was revoked due to a key compromise */
    rb_define_const(mOCSP, "REVOKED_STATUS_KEYCOMPROMISE", INT2NUM(OCSP_REVOKED_STATUS_KEYCOMPROMISE));

    /* The certificate was previously on hold and should now be removed from
     * the CRL */
    rb_define_const(mOCSP, "REVOKED_STATUS_REMOVEFROMCRL", INT2NUM(OCSP_REVOKED_STATUS_REMOVEFROMCRL));

    /* The certificate was superseded by a new certificate */
    rb_define_const(mOCSP, "REVOKED_STATUS_SUPERSEDED", INT2NUM(OCSP_REVOKED_STATUS_SUPERSEDED));

    /* Your request is unauthorized. */
    rb_define_const(mOCSP, "RESPONSE_STATUS_UNAUTHORIZED", INT2NUM(OCSP_RESPONSE_STATUS_UNAUTHORIZED));

    /* The certificate was revoked for an unspecified reason */
    rb_define_const(mOCSP, "REVOKED_STATUS_UNSPECIFIED", INT2NUM(OCSP_REVOKED_STATUS_UNSPECIFIED));

    /* Do not include certificates in the response */
    rb_define_const(mOCSP, "NOCERTS", INT2NUM(OCSP_NOCERTS));

    /* Do not search certificates contained in the response for a signer */
    rb_define_const(mOCSP, "NOINTERN", INT2NUM(OCSP_NOINTERN));

    /* Do not check the signature on the response */
    rb_define_const(mOCSP, "NOSIGS", INT2NUM(OCSP_NOSIGS));

    /* Do not verify the certificate chain on the response */
    rb_define_const(mOCSP, "NOCHAIN", INT2NUM(OCSP_NOCHAIN));

    /* Do not verify the response at all */
    rb_define_const(mOCSP, "NOVERIFY", INT2NUM(OCSP_NOVERIFY));

    /* Do not check trust */
    rb_define_const(mOCSP, "NOEXPLICIT", INT2NUM(OCSP_NOEXPLICIT));

    /* (This flag is not used by OpenSSL 1.0.1g) */
    rb_define_const(mOCSP, "NOCASIGN", INT2NUM(OCSP_NOCASIGN));

    /* (This flag is not used by OpenSSL 1.0.1g) */
    rb_define_const(mOCSP, "NODELEGATED", INT2NUM(OCSP_NODELEGATED));

    /* Do not make additional signing certificate checks */
    rb_define_const(mOCSP, "NOCHECKS", INT2NUM(OCSP_NOCHECKS));

    /* Do not verify additional certificates */
    rb_define_const(mOCSP, "TRUSTOTHER", INT2NUM(OCSP_TRUSTOTHER));

    /* Identify the response by signing the certificate key ID */
    rb_define_const(mOCSP, "RESPID_KEY", INT2NUM(OCSP_RESPID_KEY));

    /* Do not include producedAt time in response */
    rb_define_const(mOCSP, "NOTIME", INT2NUM(OCSP_NOTIME));

    /* Indicates the certificate is not revoked but does not necessarily mean
     * the certificate was issued or that this response is within the
     * certificate's validity interval */
    rb_define_const(mOCSP, "V_CERTSTATUS_GOOD", INT2NUM(V_OCSP_CERTSTATUS_GOOD));
    /* Indicates the certificate has been revoked either permanently or
     * temporarily (on hold). */
    rb_define_const(mOCSP, "V_CERTSTATUS_REVOKED", INT2NUM(V_OCSP_CERTSTATUS_REVOKED));

    /* Indicates the responder does not know about the certificate being
     * requested. */
    rb_define_const(mOCSP, "V_CERTSTATUS_UNKNOWN", INT2NUM(V_OCSP_CERTSTATUS_UNKNOWN));

    /* The responder ID is based on the key name. */
    rb_define_const(mOCSP, "V_RESPID_NAME", INT2NUM(V_OCSP_RESPID_NAME));

    /* The responder ID is based on the public key. */
    rb_define_const(mOCSP, "V_RESPID_KEY", INT2NUM(V_OCSP_RESPID_KEY));
}

#else /* ! OSSL_OCSP_ENABLED */
void
Init_ossl_ocsp(void)
{
}
#endif
