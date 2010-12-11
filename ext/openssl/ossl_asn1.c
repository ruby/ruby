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

static VALUE join_der(VALUE enumerable);

/*
 * DATE conversion
 */
VALUE
asn1time_to_time(ASN1_TIME *time)
{
    struct tm tm;
    VALUE argv[6];

    if (!time || !time->data) return Qnil;
    memset(&tm, 0, sizeof(struct tm));

    switch (time->type) {
    case V_ASN1_UTCTIME:
	if (sscanf((const char *)time->data, "%2d%2d%2d%2d%2d%2dZ", &tm.tm_year, &tm.tm_mon,
    		&tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) != 6) {
	    ossl_raise(rb_eTypeError, "bad UTCTIME format");
	}
	if (tm.tm_year < 69) {
	    tm.tm_year += 2000;
	} else {
	    tm.tm_year += 1900;
	}
	break;
    case V_ASN1_GENERALIZEDTIME:
	if (sscanf((const char *)time->data, "%4d%2d%2d%2d%2d%2dZ", &tm.tm_year, &tm.tm_mon,
    		&tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) != 6) {
	    ossl_raise(rb_eTypeError, "bad GENERALIZEDTIME format" );
	}
	break;
    default:
	rb_warning("unknown time format");
        return Qnil;
    }
    argv[0] = INT2NUM(tm.tm_year);
    argv[1] = INT2NUM(tm.tm_mon);
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
    return (time_t)NUM2LONG(rb_Integer(time));
}

/*
 * STRING conversion
 */
VALUE
asn1str_to_str(ASN1_STRING *str)
{
    return rb_str_new((const char *)str->data, str->length);
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
ASN1_INTEGER *
num_to_asn1integer(VALUE obj, ASN1_INTEGER *ai)
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
ASN1_INTEGER *
num_to_asn1integer(VALUE obj, ASN1_INTEGER *ai)
{
    BIGNUM *bn = GetBNPtr(obj);

    if (!(ai = BN_to_ASN1_INTEGER(bn, ai))) {
	ossl_raise(eOSSLError, NULL);
    }
    return ai;
}
#endif

/********/
/*
 * ASN1 module
 */
#define ossl_asn1_get_value(o)           rb_attr_get((o),rb_intern("@value"))
#define ossl_asn1_get_tag(o)             rb_attr_get((o),rb_intern("@tag"))
#define ossl_asn1_get_tagging(o)         rb_attr_get((o),rb_intern("@tagging"))
#define ossl_asn1_get_tag_class(o)       rb_attr_get((o),rb_intern("@tag_class"))
#define ossl_asn1_get_infinite_length(o) rb_attr_get((o),rb_intern("@infinite_length"))

#define ossl_asn1_set_value(o,v)           rb_iv_set((o),"@value",(v))
#define ossl_asn1_set_tag(o,v)             rb_iv_set((o),"@tag",(v))
#define ossl_asn1_set_tagging(o,v)         rb_iv_set((o),"@tagging",(v))
#define ossl_asn1_set_tag_class(o,v)       rb_iv_set((o),"@tag_class",(v))
#define ossl_asn1_set_infinite_length(o,v) rb_iv_set((o),"@infinite_length",(v))

VALUE mASN1;
VALUE eASN1Error;

VALUE cASN1Data;
VALUE cASN1Primitive;
VALUE cASN1Constructive;

VALUE cASN1EndOfContent;
VALUE cASN1Boolean;                           /* BOOLEAN           */
VALUE cASN1Integer, cASN1Enumerated;          /* INTEGER           */
VALUE cASN1BitString;                         /* BIT STRING        */
VALUE cASN1OctetString, cASN1UTF8String;      /* STRINGs           */
VALUE cASN1NumericString, cASN1PrintableString;
VALUE cASN1T61String, cASN1VideotexString;
VALUE cASN1IA5String, cASN1GraphicString;
VALUE cASN1ISO64String, cASN1GeneralString;
VALUE cASN1UniversalString, cASN1BMPString;
VALUE cASN1Null;                              /* NULL              */
VALUE cASN1ObjectId;                          /* OBJECT IDENTIFIER */
VALUE cASN1UTCTime, cASN1GeneralizedTime;     /* TIME              */
VALUE cASN1Sequence, cASN1Set;                /* CONSTRUCTIVE      */

static ID sIMPLICIT, sEXPLICIT;
static ID sUNIVERSAL, sAPPLICATION, sCONTEXT_SPECIFIC, sPRIVATE;

/*
 * Ruby to ASN1 converters
 */
static ASN1_BOOLEAN
obj_to_asn1bool(VALUE obj)
{
#if OPENSSL_VERSION_NUMBER < 0x00907000L
     return RTEST(obj) ? 0xff : 0x100;
#else
     return RTEST(obj) ? 0xff : 0x0;
#endif
}

static ASN1_INTEGER*
obj_to_asn1int(VALUE obj)
{
    return num_to_asn1integer(obj, NULL);
}

static ASN1_BIT_STRING*
obj_to_asn1bstr(VALUE obj, long unused_bits)
{
    ASN1_BIT_STRING *bstr;

    if(unused_bits < 0) unused_bits = 0;
    StringValue(obj);
    if(!(bstr = ASN1_BIT_STRING_new()))
	ossl_raise(eASN1Error, NULL);
    ASN1_BIT_STRING_set(bstr, (unsigned char *)RSTRING_PTR(obj), RSTRING_LEN(obj));
    bstr->flags &= ~(ASN1_STRING_FLAG_BITS_LEFT|0x07); /* clear */
    bstr->flags |= ASN1_STRING_FLAG_BITS_LEFT|(unused_bits&0x07);

    return bstr;
}

static ASN1_STRING*
obj_to_asn1str(VALUE obj)
{
    ASN1_STRING *str;

    StringValue(obj);
    if(!(str = ASN1_STRING_new()))
	ossl_raise(eASN1Error, NULL);
    ASN1_STRING_set(str, RSTRING_PTR(obj), RSTRING_LEN(obj));

    return str;
}

static ASN1_NULL*
obj_to_asn1null(VALUE obj)
{
    ASN1_NULL *null;

    if(!NIL_P(obj))
	ossl_raise(eASN1Error, "nil expected");
    if(!(null = ASN1_NULL_new()))
	ossl_raise(eASN1Error, NULL);

    return null;
}

static ASN1_OBJECT*
obj_to_asn1obj(VALUE obj)
{
    ASN1_OBJECT *a1obj;

    StringValue(obj);
    a1obj = OBJ_txt2obj(RSTRING_PTR(obj), 0);
    if(!a1obj) a1obj = OBJ_txt2obj(RSTRING_PTR(obj), 1);
    if(!a1obj) ossl_raise(eASN1Error, "invalid OBJECT ID");

    return a1obj;
}

static ASN1_UTCTIME*
obj_to_asn1utime(VALUE time)
{
    time_t sec;
    ASN1_UTCTIME *t;

    sec = time_to_time_t(time);
    if(!(t = ASN1_UTCTIME_set(NULL, sec)))
        ossl_raise(eASN1Error, NULL);

    return t;
}

static ASN1_GENERALIZEDTIME*
obj_to_asn1gtime(VALUE time)
{
    time_t sec;
    ASN1_GENERALIZEDTIME *t;

    sec = time_to_time_t(time);
    if(!(t =ASN1_GENERALIZEDTIME_set(NULL, sec)))
        ossl_raise(eASN1Error, NULL);

    return t;
}

static ASN1_STRING*
obj_to_asn1derstr(VALUE obj)
{
    ASN1_STRING *a1str;
    VALUE str;

    str = ossl_to_der(obj);
    if(!(a1str = ASN1_STRING_new()))
	ossl_raise(eASN1Error, NULL);
    ASN1_STRING_set(a1str, RSTRING_PTR(str), RSTRING_LEN(str));

    return a1str;
}

/*
 * DER to Ruby converters
 */
static VALUE
decode_bool(unsigned char* der, int length)
{
    int val;
    const unsigned char *p;

    p = der;
    if((val = d2i_ASN1_BOOLEAN(NULL, &p, length)) < 0)
	ossl_raise(eASN1Error, NULL);

    return val ? Qtrue : Qfalse;
}

static VALUE
decode_int(unsigned char* der, int length)
{
    ASN1_INTEGER *ai;
    const unsigned char *p;
    VALUE ret;
    int status = 0;

    p = der;
    if(!(ai = d2i_ASN1_INTEGER(NULL, &p, length)))
	ossl_raise(eASN1Error, NULL);
    ret = rb_protect((VALUE(*)_((VALUE)))asn1integer_to_num,
		     (VALUE)ai, &status);
    ASN1_INTEGER_free(ai);
    if(status) rb_jump_tag(status);

    return ret;
}

static VALUE
decode_bstr(unsigned char* der, int length, long *unused_bits)
{
    ASN1_BIT_STRING *bstr;
    const unsigned char *p;
    long len;
    VALUE ret;

    p = der;
    if(!(bstr = d2i_ASN1_BIT_STRING(NULL, &p, length)))
	ossl_raise(eASN1Error, NULL);
    len = bstr->length;
    *unused_bits = 0;
    if(bstr->flags & ASN1_STRING_FLAG_BITS_LEFT)
	*unused_bits = bstr->flags & 0x07;
    ret = rb_str_new((const char *)bstr->data, len);
    ASN1_BIT_STRING_free(bstr);

    return ret;
}

static VALUE
decode_enum(unsigned char* der, int length)
{
    ASN1_ENUMERATED *ai;
    const unsigned char *p;
    VALUE ret;
    int status = 0;

    p = der;
    if(!(ai = d2i_ASN1_ENUMERATED(NULL, &p, length)))
	ossl_raise(eASN1Error, NULL);
    ret = rb_protect((VALUE(*)_((VALUE)))asn1integer_to_num,
		     (VALUE)ai, &status);
    ASN1_ENUMERATED_free(ai);
    if(status) rb_jump_tag(status);

    return ret;
}

static VALUE
decode_null(unsigned char* der, int length)
{
    ASN1_NULL *null;
    const unsigned char *p;

    p = der;
    if(!(null = d2i_ASN1_NULL(NULL, &p, length)))
	ossl_raise(eASN1Error, NULL);
    ASN1_NULL_free(null);

    return Qnil;
}

static VALUE
decode_obj(unsigned char* der, int length)
{
    ASN1_OBJECT *obj;
    const unsigned char *p;
    VALUE ret;
    int nid;
    BIO *bio;

    p = der;
    if(!(obj = d2i_ASN1_OBJECT(NULL, &p, length)))
	ossl_raise(eASN1Error, NULL);
    if((nid = OBJ_obj2nid(obj)) != NID_undef){
	ASN1_OBJECT_free(obj);
	ret = rb_str_new2(OBJ_nid2sn(nid));
    }
    else{
	if(!(bio = BIO_new(BIO_s_mem()))){
	    ASN1_OBJECT_free(obj);
	    ossl_raise(eASN1Error, NULL);
	}
	i2a_ASN1_OBJECT(bio, obj);
	ASN1_OBJECT_free(obj);
	ret = ossl_membio2str(bio);
    }

    return ret;
}

static VALUE
decode_time(unsigned char* der, int length)
{
    ASN1_TIME *time;
    const unsigned char *p;
    VALUE ret;
    int status = 0;

    p = der;
    if(!(time = d2i_ASN1_TIME(NULL, &p, length)))
	ossl_raise(eASN1Error, NULL);
    ret = rb_protect((VALUE(*)_((VALUE)))asn1time_to_time,
		     (VALUE)time, &status);
    ASN1_TIME_free(time);
    if(status) rb_jump_tag(status);

    return ret;
}

/********/

typedef struct {
    const char *name;
    VALUE *klass;
} ossl_asn1_info_t;

static ossl_asn1_info_t ossl_asn1_info[] = {
    { "EOC",               &cASN1EndOfContent,    },  /*  0 */
    { "BOOLEAN",           &cASN1Boolean,         },  /*  1 */
    { "INTEGER",           &cASN1Integer,         },  /*  2 */
    { "BIT_STRING",        &cASN1BitString,       },  /*  3 */
    { "OCTET_STRING",      &cASN1OctetString,     },  /*  4 */
    { "NULL",              &cASN1Null,            },  /*  5 */
    { "OBJECT",            &cASN1ObjectId,        },  /*  6 */
    { "OBJECT_DESCRIPTOR", NULL,                  },  /*  7 */
    { "EXTERNAL",          NULL,                  },  /*  8 */
    { "REAL",              NULL,                  },  /*  9 */
    { "ENUMERATED",        &cASN1Enumerated,      },  /* 10 */
    { "EMBEDDED_PDV",      NULL,                  },  /* 11 */
    { "UTF8STRING",        &cASN1UTF8String,      },  /* 12 */
    { "RELATIVE_OID",      NULL,                  },  /* 13 */
    { "[UNIVERSAL 14]",    NULL,                  },  /* 14 */
    { "[UNIVERSAL 15]",    NULL,                  },  /* 15 */
    { "SEQUENCE",          &cASN1Sequence,        },  /* 16 */
    { "SET",               &cASN1Set,             },  /* 17 */
    { "NUMERICSTRING",     &cASN1NumericString,   },  /* 18 */
    { "PRINTABLESTRING",   &cASN1PrintableString, },  /* 19 */
    { "T61STRING",         &cASN1T61String,       },  /* 20 */
    { "VIDEOTEXSTRING",    &cASN1VideotexString,  },  /* 21 */
    { "IA5STRING",         &cASN1IA5String,       },  /* 22 */
    { "UTCTIME",           &cASN1UTCTime,         },  /* 23 */
    { "GENERALIZEDTIME",   &cASN1GeneralizedTime, },  /* 24 */
    { "GRAPHICSTRING",     &cASN1GraphicString,   },  /* 25 */
    { "ISO64STRING",       &cASN1ISO64String,     },  /* 26 */
    { "GENERALSTRING",     &cASN1GeneralString,   },  /* 27 */
    { "UNIVERSALSTRING",   &cASN1UniversalString, },  /* 28 */
    { "CHARACTER_STRING",  NULL,                  },  /* 29 */
    { "BMPSTRING",         &cASN1BMPString,       },  /* 30 */
};

int ossl_asn1_info_size = (sizeof(ossl_asn1_info)/sizeof(ossl_asn1_info[0]));

static int ossl_asn1_default_tag(VALUE obj);

ASN1_TYPE*
ossl_asn1_get_asn1type(VALUE obj)
{
    ASN1_TYPE *ret;
    VALUE value, rflag;
    void *ptr;
    void (*free_func)();
    long tag, flag;

    tag = ossl_asn1_default_tag(obj);
    value = ossl_asn1_get_value(obj);
    switch(tag){
    case V_ASN1_BOOLEAN:
	ptr = (void*)(VALUE)obj_to_asn1bool(value);
	free_func = NULL;
	break;
    case V_ASN1_INTEGER:         /* FALLTHROUGH */
    case V_ASN1_ENUMERATED:
	ptr = obj_to_asn1int(value);
	free_func = ASN1_INTEGER_free;
	break;
    case V_ASN1_BIT_STRING:
        rflag = rb_attr_get(obj, rb_intern("@unused_bits"));
        flag = NIL_P(rflag) ? -1 : NUM2INT(rflag);
	ptr = obj_to_asn1bstr(value, flag);
	free_func = ASN1_BIT_STRING_free;
	break;
    case V_ASN1_NULL:
	ptr = obj_to_asn1null(value);
	free_func = ASN1_NULL_free;
	break;
    case V_ASN1_OCTET_STRING:    /* FALLTHROUGH */
    case V_ASN1_UTF8STRING:      /* FALLTHROUGH */
    case V_ASN1_NUMERICSTRING:   /* FALLTHROUGH */
    case V_ASN1_PRINTABLESTRING: /* FALLTHROUGH */
    case V_ASN1_T61STRING:       /* FALLTHROUGH */
    case V_ASN1_VIDEOTEXSTRING:  /* FALLTHROUGH */
    case V_ASN1_IA5STRING:       /* FALLTHROUGH */
    case V_ASN1_GRAPHICSTRING:   /* FALLTHROUGH */
    case V_ASN1_ISO64STRING:     /* FALLTHROUGH */
    case V_ASN1_GENERALSTRING:   /* FALLTHROUGH */
    case V_ASN1_UNIVERSALSTRING: /* FALLTHROUGH */
    case V_ASN1_BMPSTRING:
	ptr = obj_to_asn1str(value);
	free_func = ASN1_STRING_free;
	break;
    case V_ASN1_OBJECT:
	ptr = obj_to_asn1obj(value);
	free_func = ASN1_OBJECT_free;
	break;
    case V_ASN1_UTCTIME:
	ptr = obj_to_asn1utime(value);
	free_func = ASN1_TIME_free;
	break;
    case V_ASN1_GENERALIZEDTIME:
	ptr = obj_to_asn1gtime(value);
	free_func = ASN1_TIME_free;
	break;
    case V_ASN1_SET:             /* FALLTHROUGH */
    case V_ASN1_SEQUENCE:
	ptr = obj_to_asn1derstr(obj);
	free_func = ASN1_STRING_free;
	break;
    default:
	ossl_raise(eASN1Error, "unsupported ASN.1 type");
    }
    if(!(ret = OPENSSL_malloc(sizeof(ASN1_TYPE)))){
	if(free_func) free_func(ptr);
	ossl_raise(eASN1Error, "ASN1_TYPE alloc failure");
    }
    memset(ret, 0, sizeof(ASN1_TYPE));
    ASN1_TYPE_set(ret, tag, ptr);

    return ret;
}

static int
ossl_asn1_default_tag(VALUE obj)
{
    int i;

    for(i = 0; i < ossl_asn1_info_size; i++){
	if(ossl_asn1_info[i].klass &&
	   rb_obj_is_kind_of(obj, *ossl_asn1_info[i].klass)){
	    return i;
	}
    }
    ossl_raise(eASN1Error, "universal tag for %s not found",
	       rb_class2name(CLASS_OF(obj)));

    return -1; /* dummy */
}

static int
ossl_asn1_tag(VALUE obj)
{
    VALUE tag;

    tag = ossl_asn1_get_tag(obj);
    if(NIL_P(tag))
	ossl_raise(eASN1Error, "tag number not specified");

    return NUM2INT(tag);
}

static int
ossl_asn1_is_explicit(VALUE obj)
{
    VALUE s;
    int ret = -1;

    s = ossl_asn1_get_tagging(obj);
    if(NIL_P(s)) return 0;
    else if(SYMBOL_P(s)){
	if (SYM2ID(s) == sIMPLICIT)
	    ret = 0;
	else if (SYM2ID(s) == sEXPLICIT)
	    ret = 1;
    }
    if(ret < 0){
	ossl_raise(eASN1Error, "invalid tag default");
    }

    return ret;
}

static int
ossl_asn1_tag_class(VALUE obj)
{
    VALUE s;
    int ret = -1;

    s = ossl_asn1_get_tag_class(obj);
    if(NIL_P(s)) ret = V_ASN1_UNIVERSAL;
    else if(SYMBOL_P(s)){
	if (SYM2ID(s) == sUNIVERSAL)
	    ret = V_ASN1_UNIVERSAL;
	else if (SYM2ID(s) == sAPPLICATION)
	    ret = V_ASN1_APPLICATION;
	else if (SYM2ID(s) == sCONTEXT_SPECIFIC)
	    ret = V_ASN1_CONTEXT_SPECIFIC;
	else if (SYM2ID(s) == sPRIVATE)
	    ret = V_ASN1_PRIVATE;
    }
    if(ret < 0){
	ossl_raise(eASN1Error, "invalid tag class");
    }

    return ret;
}

static VALUE
ossl_asn1_class2sym(int tc)
{
    if((tc & V_ASN1_PRIVATE) == V_ASN1_PRIVATE)
	return ID2SYM(sPRIVATE);
    else if((tc & V_ASN1_CONTEXT_SPECIFIC) == V_ASN1_CONTEXT_SPECIFIC)
	return ID2SYM(sCONTEXT_SPECIFIC);
    else if((tc & V_ASN1_APPLICATION) == V_ASN1_APPLICATION)
	return ID2SYM(sAPPLICATION);
    else
	return ID2SYM(sUNIVERSAL);
}

static VALUE
ossl_asn1data_initialize(VALUE self, VALUE value, VALUE tag, VALUE tag_class)
{
    if(!SYMBOL_P(tag_class))
	ossl_raise(eASN1Error, "invalid tag class");
    if((SYM2ID(tag_class) == sUNIVERSAL) && NUM2INT(tag) > 31)
	ossl_raise(eASN1Error, "tag number for Universal too large");
    ossl_asn1_set_tag(self, tag);
    ossl_asn1_set_value(self, value);
    ossl_asn1_set_tag_class(self, tag_class);
    ossl_asn1_set_infinite_length(self, Qfalse);

    return self;
}

static VALUE
join_der_i(VALUE i, VALUE str)
{
    i = ossl_to_der_if_possible(i);
    StringValue(i);
    rb_str_append(str, i);
    return Qnil;
}

static VALUE
join_der(VALUE enumerable)
{
    VALUE str = rb_str_new(0, 0);
    rb_block_call(enumerable, rb_intern("each"), 0, 0, join_der_i, str);
    return str;
}

static VALUE
ossl_asn1data_to_der(VALUE self)
{
    VALUE value, der, inf_length;
    int tag, tag_class, is_cons = 0, tmp_cons = 1;
    long length;
    unsigned char *p;

    value = ossl_asn1_get_value(self);
    if(rb_obj_is_kind_of(value, rb_cArray)){
	is_cons = 1;
	value = join_der(value);
    }
    StringValue(value);

    tag = ossl_asn1_tag(self);
    tag_class = ossl_asn1_tag_class(self);
    inf_length = ossl_asn1_get_infinite_length(self);
    if (inf_length == Qtrue) {
        is_cons = 2;
        tmp_cons = 2;
    }
    if((length = ASN1_object_size(tmp_cons, RSTRING_LEN(value), tag)) <= 0)
	ossl_raise(eASN1Error, NULL);
    der = rb_str_new(0, length);
    p = (unsigned char *)RSTRING_PTR(der);
    ASN1_put_object(&p, is_cons, RSTRING_LEN(value), tag, tag_class);
    memcpy(p, RSTRING_PTR(value), RSTRING_LEN(value));
    p += RSTRING_LEN(value);
    ossl_str_adjust(der, p);

    return der;
}

static VALUE
ossl_asn1_decode0(unsigned char **pp, long length, long *offset, long depth,
		  int once, int yield)
{
    unsigned char *start, *p;
    const unsigned char *p0;
    long len, off = *offset;
    int hlen, tag, tc, j, infinite = 0;
    VALUE ary, asn1data, value, tag_class;

    ary = rb_ary_new();
    p = *pp;
    while(length > 0){
	start = p;
	p0 = p;
	j = ASN1_get_object(&p0, &len, &tag, &tc, length);
	p = (unsigned char *)p0;
	if(j & 0x80) ossl_raise(eASN1Error, NULL);
	hlen = p - start;
	if(yield){
	    VALUE arg = rb_ary_new();
	    rb_ary_push(arg, LONG2NUM(depth));
	    rb_ary_push(arg, LONG2NUM(off));
	    rb_ary_push(arg, LONG2NUM(hlen));
	    rb_ary_push(arg, LONG2NUM(len));
	    rb_ary_push(arg, (j & V_ASN1_CONSTRUCTED) ? Qtrue : Qfalse);
	    rb_ary_push(arg, ossl_asn1_class2sym(tc));
	    rb_ary_push(arg, INT2NUM(tag));
	    rb_yield(arg);
	}
	length -= hlen;
	off += hlen;
	if(len > length) ossl_raise(eASN1Error, "value is too short");
	if((tc & V_ASN1_PRIVATE) == V_ASN1_PRIVATE)
	    tag_class = sPRIVATE;
	else if((tc & V_ASN1_CONTEXT_SPECIFIC) == V_ASN1_CONTEXT_SPECIFIC)
	    tag_class = sCONTEXT_SPECIFIC;
	else if((tc & V_ASN1_APPLICATION) == V_ASN1_APPLICATION)
	    tag_class = sAPPLICATION;
	else
	    tag_class = sUNIVERSAL;
	if(j & V_ASN1_CONSTRUCTED){
	    if((j == 0x21) && (len == 0)){
                infinite = 1;
		long lastoff = off;
		value = ossl_asn1_decode0(&p, length, &off, depth+1, 0, yield);
		len = off - lastoff;
	    }
	    else value = ossl_asn1_decode0(&p, len, &off, depth+1, 0, yield);
	}
	else{
	    value = rb_str_new((const char *)p, len);
	    p += len;
	    off += len;
	}
	if(tag_class == sUNIVERSAL &&
	   tag < ossl_asn1_info_size && ossl_asn1_info[tag].klass){
	    VALUE klass = *ossl_asn1_info[tag].klass;
	    long flag = 0;
	    if(!rb_obj_is_kind_of(value, rb_cArray)){
		switch(tag){
		case V_ASN1_BOOLEAN:
		    value = decode_bool(start, hlen+len);
		    break;
		case V_ASN1_INTEGER:
		    value = decode_int(start, hlen+len);
		    break;
		case V_ASN1_BIT_STRING:
		    value = decode_bstr(start, hlen+len, &flag);
		    break;
		case V_ASN1_NULL:
		    value = decode_null(start, hlen+len);
		    break;
		case V_ASN1_ENUMERATED:
		    value = decode_enum(start, hlen+len);
		    break;
		case V_ASN1_OBJECT:
		    value = decode_obj(start, hlen+len);
		    break;
		case V_ASN1_UTCTIME:           /* FALLTHROUGH */
		case V_ASN1_GENERALIZEDTIME:
		    value = decode_time(start, hlen+len);
		    break;
		default:
		    /* use original value */
		    break;
		}
	    }
            if (infinite && !(tag == V_ASN1_SEQUENCE || tag == V_ASN1_SET)){
                asn1data = rb_funcall(cASN1Constructive,
                                      rb_intern("new"),
                                      4,
                                      value,
                                      INT2NUM(tag),
                                      Qnil,
                                      ID2SYM(tag_class));
            }
            else{
                if (tag == V_ASN1_EOC){
                    asn1data = rb_funcall(cASN1EndOfContent,
                                          rb_intern("new"),
                                          0);
                }
                else{
                    asn1data = rb_funcall(klass, rb_intern("new"), 1, value);
                }
            }
	    if(tag == V_ASN1_BIT_STRING){
		rb_iv_set(asn1data, "@unused_bits", LONG2NUM(flag));
	    }
	}
	else{
            asn1data = rb_funcall(cASN1Data, rb_intern("new"), 3,
				  value, INT2NUM(tag), ID2SYM(tag_class));
        }

        if (infinite)
            ossl_asn1_set_infinite_length(asn1data, Qtrue);
        else
            ossl_asn1_set_infinite_length(asn1data, Qfalse);
        
	rb_ary_push(ary, asn1data);
	length -= len;
        if(once) break;
    }
    *pp = p;
    *offset = off;

    return ary;
}

static VALUE
ossl_asn1_traverse(VALUE self, VALUE obj)
{
    unsigned char *p;
    long offset = 0;
    volatile VALUE tmp;

    obj = ossl_to_der_if_possible(obj);
    tmp = rb_str_new4(StringValue(obj));
    p = (unsigned char *)RSTRING_PTR(tmp);
    ossl_asn1_decode0(&p, RSTRING_LEN(tmp), &offset, 0, 0, 1);

    return Qnil;
}

static VALUE
ossl_asn1_decode(VALUE self, VALUE obj)
{
    VALUE ret, ary;
    unsigned char *p;
    long offset = 0;
    volatile VALUE tmp;

    obj = ossl_to_der_if_possible(obj);
    tmp = rb_str_new4(StringValue(obj));
    p = (unsigned char *)RSTRING_PTR(tmp);
    ary = ossl_asn1_decode0(&p, RSTRING_LEN(tmp), &offset, 0, 1, 0);
    ret = rb_ary_entry(ary, 0);

    return ret;
}

static VALUE
ossl_asn1_decode_all(VALUE self, VALUE obj)
{
    VALUE ret;
    unsigned char *p;
    long offset = 0;
    volatile VALUE tmp;

    obj = ossl_to_der_if_possible(obj);
    tmp = rb_str_new4(StringValue(obj));
    p = (unsigned char *)RSTRING_PTR(tmp);
    ret = ossl_asn1_decode0(&p, RSTRING_LEN(tmp), &offset, 0, 0, 0);

    return ret;
}

static VALUE
ossl_asn1_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE value, tag, tagging, tag_class;

    rb_scan_args(argc, argv, "13", &value, &tag, &tagging, &tag_class);
    if(argc > 1){
	if(NIL_P(tag))
	    ossl_raise(eASN1Error, "must specify tag number");
        if(NIL_P(tagging))
	    tagging = ID2SYM(sEXPLICIT);
	if(!SYMBOL_P(tagging))
	    ossl_raise(eASN1Error, "invalid tag default");
	if(NIL_P(tag_class))
	    tag_class = ID2SYM(sCONTEXT_SPECIFIC);
	if(!SYMBOL_P(tag_class))
	    ossl_raise(eASN1Error, "invalid tag class");
	if(SYM2ID(tagging) == sIMPLICIT && NUM2INT(tag) > 31)
	    ossl_raise(eASN1Error, "tag number for Universal too large");
    }
    else{
	tag = INT2NUM(ossl_asn1_default_tag(self));
        tagging = Qnil;
	tag_class = ID2SYM(sUNIVERSAL);
    }
    ossl_asn1_set_tag(self, tag);
    ossl_asn1_set_value(self, value);
    ossl_asn1_set_tagging(self, tagging);
    ossl_asn1_set_tag_class(self, tag_class);
    ossl_asn1_set_infinite_length(self, Qfalse);

    return self;
}

static VALUE
ossl_asn1eoc_initialize(VALUE self) {
    VALUE tag, tagging, tag_class, value;
    tag = INT2NUM(ossl_asn1_default_tag(self));
    tagging = Qnil;
    tag_class = ID2SYM(sUNIVERSAL);
    value = rb_str_new("", 0);
    ossl_asn1_set_tag(self, tag);
    ossl_asn1_set_value(self, value);
    ossl_asn1_set_tagging(self, tagging);
    ossl_asn1_set_tag_class(self, tag_class);
    ossl_asn1_set_infinite_length(self, Qfalse);
    return self;
}

static int
ossl_i2d_ASN1_TYPE(ASN1_TYPE *a, unsigned char **pp)
{
#if OPENSSL_VERSION_NUMBER < 0x00907000L
    if(!a) return 0;
    if(a->type == V_ASN1_BOOLEAN)
        return i2d_ASN1_BOOLEAN(a->value.boolean, pp);
#endif
    return i2d_ASN1_TYPE(a, pp);
}

static void
ossl_ASN1_TYPE_free(ASN1_TYPE *a)
{
#if OPENSSL_VERSION_NUMBER < 0x00907000L
    if(!a) return;
    if(a->type == V_ASN1_BOOLEAN){
        OPENSSL_free(a);
        return;
    }
#endif
    ASN1_TYPE_free(a);
}

static VALUE
ossl_asn1prim_to_der(VALUE self)
{
    ASN1_TYPE *asn1;
    int tn, tc, explicit;
    long len, reallen;
    unsigned char *buf, *p;
    VALUE str;

    tn = NUM2INT(ossl_asn1_get_tag(self));
    tc = ossl_asn1_tag_class(self);
    explicit = ossl_asn1_is_explicit(self);
    asn1 = ossl_asn1_get_asn1type(self);

    len = ASN1_object_size(1, ossl_i2d_ASN1_TYPE(asn1, NULL), tn);
    if(!(buf = OPENSSL_malloc(len))){
	ossl_ASN1_TYPE_free(asn1);
	ossl_raise(eASN1Error, "cannot alloc buffer");
    }
    p = buf;
    if (tc == V_ASN1_UNIVERSAL) {
        ossl_i2d_ASN1_TYPE(asn1, &p);
    } else if (explicit) {
        ASN1_put_object(&p, 1, ossl_i2d_ASN1_TYPE(asn1, NULL), tn, tc);
        ossl_i2d_ASN1_TYPE(asn1, &p);
    } else {
        ossl_i2d_ASN1_TYPE(asn1, &p);
        *buf = tc | tn | (*buf & V_ASN1_CONSTRUCTED);
    }
    ossl_ASN1_TYPE_free(asn1);
    reallen = p - buf;
    assert(reallen <= len);
    str = ossl_buf2str((char *)buf, reallen); /* buf will be free in ossl_buf2str */

    return str;
}

static VALUE
ossl_asn1cons_to_der(VALUE self)
{
    int tag, tn, tc, explicit, constructed = 1;
    int found_prim = 0;
    long seq_len, length;
    unsigned char *p;
    VALUE value, str, inf_length, ary, example;

    tn = NUM2INT(ossl_asn1_get_tag(self));
    tc = ossl_asn1_tag_class(self);
    inf_length = ossl_asn1_get_infinite_length(self);
    if (inf_length == Qtrue) {
        constructed = 2;
        if (CLASS_OF(self) == cASN1Sequence ||
            CLASS_OF(self) == cASN1Set) {
            tag = ossl_asn1_default_tag(self);
        }
        else { /*BIT_STRING OR OCTET_STRING*/
            ary = ossl_asn1_get_value(self);
            /* Recursively descend until a primitive value is found.
               The overall value of the entire constructed encoding
               is of the type of the first primitive encoding to be
               found. */
            while (!found_prim){
                example = rb_ary_entry(ary, 0);
                if (rb_obj_is_kind_of(example, cASN1Primitive)){
                    found_prim = 1;
                }
                else {
                    /* example is another ASN1Constructive */
                    if (!rb_obj_is_kind_of(example, cASN1Constructive)){
                        ossl_raise(eASN1Error, "invalid constructed encoding");
                        return Qnil; /* dummy */
                    }
                    ary = ossl_asn1_get_value(example);
                }
            }
            tag = ossl_asn1_default_tag(example);
        }
    }
    else {
        tag = ossl_asn1_default_tag(self);
    }
    explicit = ossl_asn1_is_explicit(self);
    value = join_der(ossl_asn1_get_value(self));

    seq_len = ASN1_object_size(constructed, RSTRING_LEN(value), tag);
    length = ASN1_object_size(constructed, seq_len, tn);
    str = rb_str_new(0, length);
    p = (unsigned char *)RSTRING_PTR(str);
    if(tc == V_ASN1_UNIVERSAL)
    	ASN1_put_object(&p, constructed, RSTRING_LEN(value), tn, tc);
    else{
	if(explicit){
    	    ASN1_put_object(&p, constructed, seq_len, tn, tc);
	    ASN1_put_object(&p, constructed, RSTRING_LEN(value), tag, V_ASN1_UNIVERSAL);
	}
        else{
            ASN1_put_object(&p, constructed, RSTRING_LEN(value), tn, tc);
        }
    }
    memcpy(p, RSTRING_PTR(value), RSTRING_LEN(value));
    p += RSTRING_LEN(value);
    ossl_str_adjust(str, p);

    return str;
}

static VALUE
ossl_asn1cons_each(VALUE self)
{
    rb_ary_each(ossl_asn1_get_value(self));
    return self;
}

static VALUE
ossl_asn1obj_s_register(VALUE self, VALUE oid, VALUE sn, VALUE ln)
{
    StringValue(oid);
    StringValue(sn);
    StringValue(ln);

    if(!OBJ_create(RSTRING_PTR(oid), RSTRING_PTR(sn), RSTRING_PTR(ln)))
	ossl_raise(eASN1Error, NULL);

    return Qtrue;
}

static VALUE
ossl_asn1obj_get_sn(VALUE self)
{
    VALUE val, ret = Qnil;
    int nid;

    val = ossl_asn1_get_value(self);
    if ((nid = OBJ_txt2nid(StringValuePtr(val))) != NID_undef)
	ret = rb_str_new2(OBJ_nid2sn(nid));

    return ret;
}

static VALUE
ossl_asn1obj_get_ln(VALUE self)
{
    VALUE val, ret = Qnil;
    int nid;

    val = ossl_asn1_get_value(self);
    if ((nid = OBJ_txt2nid(StringValuePtr(val))) != NID_undef)
	ret = rb_str_new2(OBJ_nid2ln(nid));

    return ret;
}

static VALUE
ossl_asn1obj_get_oid(VALUE self)
{
    VALUE val;
    ASN1_OBJECT *a1obj;
    char buf[128];

    val = ossl_asn1_get_value(self);
    a1obj = obj_to_asn1obj(val);
    OBJ_obj2txt(buf, sizeof(buf), a1obj, 1);
    ASN1_OBJECT_free(a1obj);

    return rb_str_new2(buf);
}

#define OSSL_ASN1_IMPL_FACTORY_METHOD(klass) \
static VALUE ossl_asn1_##klass(int argc, VALUE *argv, VALUE self)\
{ return rb_funcall3(cASN1##klass, rb_intern("new"), argc, argv); }

OSSL_ASN1_IMPL_FACTORY_METHOD(Boolean)
OSSL_ASN1_IMPL_FACTORY_METHOD(Integer)
OSSL_ASN1_IMPL_FACTORY_METHOD(Enumerated)
OSSL_ASN1_IMPL_FACTORY_METHOD(BitString)
OSSL_ASN1_IMPL_FACTORY_METHOD(OctetString)
OSSL_ASN1_IMPL_FACTORY_METHOD(UTF8String)
OSSL_ASN1_IMPL_FACTORY_METHOD(NumericString)
OSSL_ASN1_IMPL_FACTORY_METHOD(PrintableString)
OSSL_ASN1_IMPL_FACTORY_METHOD(T61String)
OSSL_ASN1_IMPL_FACTORY_METHOD(VideotexString)
OSSL_ASN1_IMPL_FACTORY_METHOD(IA5String)
OSSL_ASN1_IMPL_FACTORY_METHOD(GraphicString)
OSSL_ASN1_IMPL_FACTORY_METHOD(ISO64String)
OSSL_ASN1_IMPL_FACTORY_METHOD(GeneralString)
OSSL_ASN1_IMPL_FACTORY_METHOD(UniversalString)
OSSL_ASN1_IMPL_FACTORY_METHOD(BMPString)
OSSL_ASN1_IMPL_FACTORY_METHOD(Null)
OSSL_ASN1_IMPL_FACTORY_METHOD(ObjectId)
OSSL_ASN1_IMPL_FACTORY_METHOD(UTCTime)
OSSL_ASN1_IMPL_FACTORY_METHOD(GeneralizedTime)
OSSL_ASN1_IMPL_FACTORY_METHOD(Sequence)
OSSL_ASN1_IMPL_FACTORY_METHOD(Set)
OSSL_ASN1_IMPL_FACTORY_METHOD(EndOfContent)

void
Init_ossl_asn1()
{
    VALUE ary;
    int i;

#if 0
    mOSSL = rb_define_module("OpenSSL"); /* let rdoc know about mOSSL */
#endif

    sUNIVERSAL = rb_intern("UNIVERSAL");
    sCONTEXT_SPECIFIC = rb_intern("CONTEXT_SPECIFIC");
    sAPPLICATION = rb_intern("APPLICATION");
    sPRIVATE = rb_intern("PRIVATE");
    sEXPLICIT = rb_intern("EXPLICIT");
    sIMPLICIT = rb_intern("IMPLICIT");

    mASN1 = rb_define_module_under(mOSSL, "ASN1");
    eASN1Error = rb_define_class_under(mASN1, "ASN1Error", eOSSLError);
    rb_define_module_function(mASN1, "traverse", ossl_asn1_traverse, 1);
    rb_define_module_function(mASN1, "decode", ossl_asn1_decode, 1);
    rb_define_module_function(mASN1, "decode_all", ossl_asn1_decode_all, 1);
    ary = rb_ary_new();
    rb_define_const(mASN1, "UNIVERSAL_TAG_NAME", ary);
    for(i = 0; i < ossl_asn1_info_size; i++){
	if(ossl_asn1_info[i].name[0] == '[') continue;
	rb_define_const(mASN1, ossl_asn1_info[i].name, INT2NUM(i));
	rb_ary_store(ary, i, rb_str_new2(ossl_asn1_info[i].name));
    }

    cASN1Data = rb_define_class_under(mASN1, "ASN1Data", rb_cObject);
    rb_attr(cASN1Data, rb_intern("value"), 1, 1, 0);
    rb_attr(cASN1Data, rb_intern("tag"), 1, 1, 0);
    rb_attr(cASN1Data, rb_intern("tag_class"), 1, 1, 0);
    rb_attr(cASN1Data, rb_intern("infinite_length"), 1, 1, 0);
    rb_define_method(cASN1Data, "initialize", ossl_asn1data_initialize, 3);
    rb_define_method(cASN1Data, "to_der", ossl_asn1data_to_der, 0);

    cASN1Primitive = rb_define_class_under(mASN1, "Primitive", cASN1Data);
    rb_attr(cASN1Primitive, rb_intern("tagging"), 1, 1, Qtrue);
    rb_undef_method(cASN1Primitive, "infinite_length=");
    rb_define_method(cASN1Primitive, "initialize", ossl_asn1_initialize, -1);
    rb_define_method(cASN1Primitive, "to_der", ossl_asn1prim_to_der, 0);

    cASN1Constructive = rb_define_class_under(mASN1,"Constructive", cASN1Data);
    rb_include_module(cASN1Constructive, rb_mEnumerable);
    rb_attr(cASN1Constructive, rb_intern("tagging"), 1, 1, Qtrue);
    rb_define_method(cASN1Constructive, "initialize", ossl_asn1_initialize, -1);
    rb_define_method(cASN1Constructive, "to_der", ossl_asn1cons_to_der, 0);
    rb_define_method(cASN1Constructive, "each", ossl_asn1cons_each, 0);

#define OSSL_ASN1_DEFINE_CLASS(name, super) \
do{\
    cASN1##name = rb_define_class_under(mASN1, #name, cASN1##super);\
    rb_define_module_function(mASN1, #name, ossl_asn1_##name, -1);\
}while(0)

    OSSL_ASN1_DEFINE_CLASS(Boolean, Primitive);
    OSSL_ASN1_DEFINE_CLASS(Integer, Primitive);
    OSSL_ASN1_DEFINE_CLASS(Enumerated, Primitive);
    OSSL_ASN1_DEFINE_CLASS(BitString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(OctetString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(UTF8String, Primitive);
    OSSL_ASN1_DEFINE_CLASS(NumericString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(PrintableString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(T61String, Primitive);
    OSSL_ASN1_DEFINE_CLASS(VideotexString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(IA5String, Primitive);
    OSSL_ASN1_DEFINE_CLASS(GraphicString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(ISO64String, Primitive);
    OSSL_ASN1_DEFINE_CLASS(GeneralString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(UniversalString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(BMPString, Primitive);
    OSSL_ASN1_DEFINE_CLASS(Null, Primitive);
    OSSL_ASN1_DEFINE_CLASS(ObjectId, Primitive);
    OSSL_ASN1_DEFINE_CLASS(UTCTime, Primitive);
    OSSL_ASN1_DEFINE_CLASS(GeneralizedTime, Primitive);

    OSSL_ASN1_DEFINE_CLASS(Sequence, Constructive);
    OSSL_ASN1_DEFINE_CLASS(Set, Constructive);

    OSSL_ASN1_DEFINE_CLASS(EndOfContent, Data);

    rb_define_singleton_method(cASN1ObjectId, "register", ossl_asn1obj_s_register, 3);
    rb_define_method(cASN1ObjectId, "sn", ossl_asn1obj_get_sn, 0);
    rb_define_method(cASN1ObjectId, "ln", ossl_asn1obj_get_ln, 0);
    rb_define_method(cASN1ObjectId, "oid", ossl_asn1obj_get_oid, 0);
    rb_define_alias(cASN1ObjectId, "short_name", "sn");
    rb_define_alias(cASN1ObjectId, "long_name", "ln");
    rb_attr(cASN1BitString, rb_intern("unused_bits"), 1, 1, 0);

    rb_define_method(cASN1EndOfContent, "initialize", ossl_asn1eoc_initialize, 0);
}
