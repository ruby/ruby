/*
 * $Id$
 * 'OpenSSL for Ruby' team members
 * Copyright (C) 2003
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if defined(HAVE_SYS_TIME_H)
#  include <sys/time.h>
#elif !defined(NT) && !defined(_WIN32)
struct timeval {
    long tv_sec;	/* seconds */
    long tv_usec;	/* and microseconds */
};
#endif

/*
 * DATE conversion
 */
VALUE
asn1time_to_time(ASN1_TIME *time)
{
    struct tm tm;
    VALUE argv[6];
    
    if (!time) {
	ossl_raise(rb_eTypeError, "ASN1_TIME is NULL!");
    }
    memset(&tm, 0, sizeof(struct tm));
	
    switch (time->type) {
    case V_ASN1_UTCTIME:
	if (sscanf(time->data, "%2d%2d%2d%2d%2d%2dZ", &tm.tm_year, &tm.tm_mon,
    		&tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) != 6) {
	    ossl_raise(rb_eTypeError, "bad UTCTIME format");
	} 
	if (tm.tm_year < 69) {
	    tm.tm_year += 2000;
	} else {
	    tm.tm_year += 1900;
	}
	tm.tm_mon -= 1;
	break;
    case V_ASN1_GENERALIZEDTIME:
	if (sscanf(time->data, "%4d%2d%2d%2d%2d%2dZ", &tm.tm_year, &tm.tm_mon,
    		&tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) != 6) {
	    ossl_raise(rb_eTypeError, "bad GENERALIZEDTIME format" );
	} 
	tm.tm_mon -= 1;
	break;
    default:
	rb_warning("unknown time format");
        return Qnil;
    }
    argv[0] = INT2NUM(tm.tm_year);
    argv[1] = INT2NUM(tm.tm_mon+1);
    argv[2] = INT2NUM(tm.tm_mday);
    argv[3] = INT2NUM(tm.tm_hour);
    argv[4] = INT2NUM(tm.tm_min);
    argv[5] = INT2NUM(tm.tm_sec);

    return rb_funcall2(rb_cTime, rb_intern("utc"), 6, argv);
}

/*
 * This function is not exported in Ruby's *.h
 */
extern struct timeval rb_time_timeval(VALUE);

time_t
time_to_time_t(VALUE time)
{
    struct timeval t = rb_time_timeval(time);
    return t.tv_sec;
}

/*
 * ASN1_INTEGER conversions
 * TODO: Make a decision what's the right way to do this.
 */
#define DO_IT_VIA_RUBY 0
VALUE
asn1integer_to_num(ASN1_INTEGER *ai)
{
    BIGNUM *bn;
#if DO_IT_VIA_RUBY
    char *txt;
#endif
    VALUE num;

    if (!ai) {
	ossl_raise(rb_eTypeError, "ASN1_INTEGER is NULL!");
    }
    if (!(bn = ASN1_INTEGER_to_BN(ai, NULL))) {
	ossl_raise(eOSSLError, NULL);
    }
#if DO_IT_VIA_RUBY
    if (!(txt = BN_bn2dec(bn))) {
	BN_free(bn);
	ossl_raise(eOSSLError, NULL);
    }
    num = rb_cstr_to_inum(txt, 10, Qtrue);
    OPENSSL_free(txt);
#else
    num = ossl_bn_new(bn);
#endif
    BN_free(bn);

    return num;
}

#if DO_IT_VIA_RUBY
ASN1_INTEGER *num_to_asn1integer(VALUE obj, ASN1_INTEGER *ai)
{
    BIGNUM *bn = NULL;

    if (RTEST(rb_obj_is_kind_of(obj, cBN))) {
	bn = GetBNPtr(obj);
    } else {
	obj = rb_String(obj);
	if (!BN_dec2bn(&bn, StringValuePtr(obj))) {
	    ossl_raise(eOSSLError, NULL);
	}
    }
    if (!(ai = BN_to_ASN1_INTEGER(bn, ai))) {
	BN_free(bn);
	ossl_raise(eOSSLError, NULL);
    }
    BN_free(bn);
    return ai;
}
#else
ASN1_INTEGER *num_to_asn1integer(VALUE obj, ASN1_INTEGER *ai)
{
    BIGNUM *bn = GetBNPtr(obj);
    
    if (!(ai = BN_to_ASN1_INTEGER(bn, ai))) {
	ossl_raise(eOSSLError, NULL);
    }
    return ai;
}
#endif

