/*
 *
 * Ruby BigDecimal(Variable decimal precision) extension library.
 *
 * Copyright(C) 2002 by Shigeo Kobayashi(shigeo@tinyforest.gr.jp)
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the README file
 * of this BigDecimal distribution.
 *
 *  NOTE: Change log in this source removed to reduce source code size. 
 *        See rev. 1.25 if needed.
 *
 */

#include "ruby.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <float.h>
#include <math.h>
#include "math.h"
#include "version.h"
 
/* #define ENABLE_NUMERIC_STRING */

VALUE rb_cBigDecimal;

#include "bigdecimal.h"

/* MACRO's to guard objects from GC by keeping them in stack */
#define ENTER(n) volatile VALUE vStack[n];int iStack=0
#define PUSH(x)  vStack[iStack++] = (unsigned long)(x);
#define SAVE(p)  PUSH(p->obj);
#define GUARD_OBJ(p,y) {p=y;SAVE(p);}

/*
 * ================== Ruby Interface part ==========================
 */
#define DoSomeOne(x,y) rb_num_coerce_bin(x,y)

#if 0
/* BigDecimal provides arbitrary-precision floating point decimal arithmetic.
 *
 * Copyright (C) 2002 by Shigeo Kobayashi <shigeo@tinyforest.gr.jp>.
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the README file
 * of the BigDecimal distribution.
 *
 * Documented by mathew <meta@pobox.com>.
 *
 * = Introduction
 *
 * Ruby provides built-in support for arbitrary precision integer arithmetic.
 * For example:
 *
 * 42**13   ->   1265437718438866624512
 *
 * BigDecimal provides similar support for very large or very accurate floating
 * point numbers.
 *
 * Decimal arithmetic is also useful for general calculation, because it
 * provides the correct answers people expect--whereas normal binary floating
 * point arithmetic often introduces subtle errors because of the conversion
 * between base 10 and base 2. For example, try:
 *
 *   sum = 0
 *   for i in (1..10000)
 *     sum = sum + 0.0001
 *   end
 *   print sum
 *
 * and contrast with the output from:
 *
 *   require 'bigdecimal'
 *
 *   sum = BigDecimal.new("0")
 *   for i in (1..10000)
 *     sum = sum + BigDecimal.new("0.0001")
 *   end
 *   print sum
 *
 * Similarly:
 *
 * (BigDecimal.new("1.2") - BigDecimal("1.0")) == BigDecimal("0.2") -> true
 *
 * (1.2 - 1.0) == 0.2 -> false
 *
 * = Special features of accurate decimal arithmetic
 *
 * Because BigDecimal is more accurate than normal binary floating point
 * arithmetic, it requires some special values.
 *
 * == Infinity
 *
 * BigDecimal sometimes needs to return infinity, for example if you divide
 * a value by zero.
 *
 * BigDecimal.new("1.0") / BigDecimal.new("0.0")  -> infinity
 *
 * BigDecimal.new("-1.0") / BigDecimal.new("0.0")  -> -infinity
 *
 * You can represent infinite numbers to BigDecimal using the strings
 * 'Infinity', '+Infinity' and '-Infinity' (case-sensitive)
 *
 * == Not a Number
 *
 * When a computation results in an undefined value, the special value NaN
 * (for 'not a number') is returned.
 *
 * Example:
 *
 * BigDecimal.new("0.0") / BigDecimal.new("0.0") -> NaN
 *
 * You can also create undefined values.  NaN is never considered to be the
 * same as any other value, even NaN itself:
 *
 * n = BigDecimal.new('NaN')
 *
 * n == 0.0 -> nil
 *
 * n == n -> nil
 *
 * == Positive and negative zero
 *
 * If a computation results in a value which is too small to be represented as
 * a BigDecimal within the currently specified limits of precision, zero must
 * be returned.
 *
 * If the value which is too small to be represented is negative, a BigDecimal
 * value of negative zero is returned. If the value is positive, a value of
 * positive zero is returned.
 *
 * BigDecimal.new("1.0") / BigDecimal.new("-Infinity") -> -0.0
 *
 * BigDecimal.new("1.0") / BigDecimal.new("Infinity") -> 0.0
 *
 * (See BigDecimal.mode for how to specify limits of precision.)
 *
 * Note that -0.0 and 0.0 are considered to be the same for the purposes of
 * comparison.
 *
 * Note also that in mathematics, there is no particular concept of negative 
 * or positive zero; true mathematical zero has no sign.
 */
void
Init_BigDecimal()
{
    /* This is a #if-ed out function to fool Rdoc into documenting the class. */
    /* The real init function is Init_bigdecimal() further down. */
}
#endif

/*
 * Returns the BigDecimal version number.
 *
 * Ruby 1.8.0 returns 1.0.0.
 * Ruby 1.8.1 thru 1.8.3 return 1.0.1.
 */
static VALUE
BigDecimal_version(VALUE self)
{
    /*
     * 1.0.0: Ruby 1.8.0
     * 1.0.1: Ruby 1.8.1
    */
    return rb_str_new2("1.0.1");
}

/*
 *   VP routines used in BigDecimal part 
 */
static unsigned short VpGetException(void);
static void  VpSetException(unsigned short f);
static void  VpInternalRound(Real *c,int ixDigit,U_LONG vPrev,U_LONG v);
static int   VpLimitRound(Real *c,U_LONG ixDigit);

/*
 *  **** BigDecimal part ****
 */

static void
BigDecimal_delete(Real *pv)
{
    VpFree(pv);
}

static VALUE
ToValue(Real *p)
{
    if(VpIsNaN(p)) {
        VpException(VP_EXCEPTION_NaN,"Computation results to 'NaN'(Not a Number)",0);
    } else if(VpIsPosInf(p)) {
        VpException(VP_EXCEPTION_INFINITY,"Computation results to 'Infinity'",0);
    } else if(VpIsNegInf(p)) {
        VpException(VP_EXCEPTION_INFINITY,"Computation results to '-Infinity'",0);
    }
    return p->obj;
}

static Real *
GetVpValue(VALUE v, int must)
{
    Real *pv;
    VALUE bg;
    char szD[128];

    switch(TYPE(v))
    {
    case T_DATA:
        if(RDATA(v)->dfree ==(void *) BigDecimal_delete) {
            Data_Get_Struct(v, Real, pv);
            return pv;
        } else {
            goto SomeOneMayDoIt;
        }
        break;
    case T_FIXNUM:
        sprintf(szD, "%ld", FIX2LONG(v));
        return VpCreateRbObject(VpBaseFig() * 2 + 1, szD);

#ifdef ENABLE_NUMERIC_STRING
    case T_STRING:
        SafeStringValue(v);
        return VpCreateRbObject(strlen(RSTRING_PTR(v)) + VpBaseFig() + 1,
                                RSTRING_PTR(v));
#endif /* ENABLE_NUMERIC_STRING */

    case T_BIGNUM:
        bg = rb_big2str(v, 10);
        return VpCreateRbObject(strlen(RSTRING_PTR(bg)) + VpBaseFig() + 1,
                                RSTRING_PTR(bg));
    default:
        goto SomeOneMayDoIt;
    }

SomeOneMayDoIt:
    if(must) {
        rb_raise(rb_eTypeError, "%s can't be coerced into BigDecimal",
                    rb_special_const_p(v)?
                    RSTRING_PTR(rb_inspect(v)):
                    rb_obj_classname(v)
                );
    }
    return NULL; /* NULL means to coerce */
}

/* call-seq:
 * BigDecimal.double_fig
 *
 * The BigDecimal.double_fig class method returns the number of digits a
 * Float number is allowed to have. The result depends upon the CPU and OS
 * in use.
 */
static VALUE
BigDecimal_double_fig(VALUE self)
{
    return INT2FIX(VpDblFig());
}

/* call-seq:
 * precs
 *
 * Returns an Array of two Integer values.
 *
 * The first value is the current number of significant digits in the 
 * BigDecimal. The second value is the maximum number of significant digits
 * for the BigDecimal.
 */
static VALUE
BigDecimal_prec(VALUE self)
{
    ENTER(1);
    Real *p;
    VALUE obj;

    GUARD_OBJ(p,GetVpValue(self,1));
    obj = rb_assoc_new(INT2NUM(p->Prec*VpBaseFig()),
		       INT2NUM(p->MaxPrec*VpBaseFig()));
    return obj;
}

static VALUE
BigDecimal_hash(VALUE self)
{
    ENTER(1);
    Real *p;
    U_LONG hash,i;

    GUARD_OBJ(p,GetVpValue(self,1));
    hash = (U_LONG)p->sign;
    /* hash!=2: the case for 0(1),NaN(0) or +-Infinity(3) is sign itself */
    if(hash==2) {
        for(i = 0; i < p->Prec;i++) {
            hash = 31 * hash + p->frac[i];
            hash ^= p->frac[i];
        }
        hash += p->exponent;
    }
    return INT2FIX(hash);
}

static VALUE
BigDecimal_dump(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    char sz[50];
    Real *vp;
    char *psz;
    VALUE dummy;
    rb_scan_args(argc, argv, "01", &dummy);
    GUARD_OBJ(vp,GetVpValue(self,1));
    sprintf(sz,"%lu:",VpMaxPrec(vp)*VpBaseFig());
    psz = ALLOCA_N(char,(unsigned int)VpNumOfChars(vp,"E")+strlen(sz));
    sprintf(psz,"%s",sz);
    VpToString(vp, psz+strlen(psz), 0, 0);
    return rb_str_new2(psz);
}

/*
 * Internal method used to provide marshalling support. See the Marshal module.
 */
static VALUE
BigDecimal_load(VALUE self, VALUE str)
{
    ENTER(2);
    Real *pv;
    unsigned char *pch;
    unsigned char ch;
    unsigned long m=0;

    SafeStringValue(str);
    pch = (unsigned char *)RSTRING_PTR(str);
    /* First get max prec */
    while((*pch)!=(unsigned char)'\0' && (ch=*pch++)!=(unsigned char)':') {
        if(!ISDIGIT(ch)) {
            rb_raise(rb_eTypeError, "load failed: invalid character in the marshaled string");
        }
        m = m*10 + (unsigned long)(ch-'0');
    }
    if(m>VpBaseFig()) m -= VpBaseFig();
    GUARD_OBJ(pv,VpNewRbClass(m,(char *)pch,self));
    m /= VpBaseFig();
    if(m && pv->MaxPrec>m) pv->MaxPrec = m+1;
    return ToValue(pv);
}

 /* call-seq:
  * BigDecimal.mode(mode, value)
  *
  * Controls handling of arithmetic exceptions and rounding. If no value
  * is supplied, the current value is returned.
  *
  * Six values of the mode parameter control the handling of arithmetic
  * exceptions:
  *
  * BigDecimal::EXCEPTION_NaN
  * BigDecimal::EXCEPTION_INFINITY
  * BigDecimal::EXCEPTION_UNDERFLOW
  * BigDecimal::EXCEPTION_OVERFLOW
  * BigDecimal::EXCEPTION_ZERODIVIDE
  * BigDecimal::EXCEPTION_ALL
  *
  * For each mode parameter above, if the value set is false, computation 
  * continues after an arithmetic exception of the appropriate type. 
  * When computation continues, results are as follows:
  *
  * EXCEPTION_NaN:: NaN
  * EXCEPTION_INFINITY:: +infinity or -infinity
  * EXCEPTION_UNDERFLOW:: 0
  * EXCEPTION_OVERFLOW:: +infinity or -infinity
  * EXCEPTION_ZERODIVIDE:: +infinity or -infinity
  *
  * One value of the mode parameter controls the rounding of numeric values:
  * BigDecimal::ROUND_MODE. The values it can take are:
  *
  * ROUND_UP:: round away from zero
  * ROUND_DOWN:: round towards zero (truncate)
  * ROUND_HALF_UP:: round up if the appropriate digit >= 5, otherwise truncate (default)
  * ROUND_HALF_DOWN:: round up if the appropriate digit >= 6, otherwise truncate
  * ROUND_HALF_EVEN:: round towards the even neighbor (Banker's rounding)
  * ROUND_CEILING:: round towards positive infinity (ceil)
  * ROUND_FLOOR:: round towards negative infinity (floor)
  *
  */
static VALUE
BigDecimal_mode(int argc, VALUE *argv, VALUE self)
{
    VALUE which;
    VALUE val;
    unsigned long f,fo;
 
    if(rb_scan_args(argc,argv,"11",&which,&val)==1) val = Qnil;

    Check_Type(which, T_FIXNUM);
    f = (unsigned long)FIX2INT(which);

    if(f&VP_EXCEPTION_ALL) {
        /* Exception mode setting */
        fo = VpGetException();
        if(val==Qnil) return INT2FIX(fo);
        if(val!=Qfalse && val!=Qtrue) {
            rb_raise(rb_eTypeError, "second argument must be true or false");
            return Qnil; /* Not reached */
        }
        if(f&VP_EXCEPTION_INFINITY) {
            VpSetException((unsigned short)((val==Qtrue)?(fo|VP_EXCEPTION_INFINITY):
                           (fo&(~VP_EXCEPTION_INFINITY))));
        }
        if(f&VP_EXCEPTION_NaN) {
            VpSetException((unsigned short)((val==Qtrue)?(fo|VP_EXCEPTION_NaN):
                           (fo&(~VP_EXCEPTION_NaN))));
        }
        fo = VpGetException();
        return INT2FIX(fo);
    }
    if(VP_ROUND_MODE==f) {
        /* Rounding mode setting */
        fo = VpGetRoundMode();
        if(val==Qnil) return INT2FIX(fo);
        Check_Type(val, T_FIXNUM);
        if(!VpIsRoundMode(FIX2INT(val))) {
            rb_raise(rb_eTypeError, "invalid rounding mode");
            return Qnil;
        }
        fo = VpSetRoundMode((unsigned long)FIX2INT(val));
        return INT2FIX(fo);
    }
    rb_raise(rb_eTypeError, "first argument for BigDecimal#mode invalid");
    return Qnil;
}

static U_LONG
GetAddSubPrec(Real *a, Real *b)
{
    U_LONG mxs;
    U_LONG mx = a->Prec;
    S_INT d;

    if(!VpIsDef(a) || !VpIsDef(b)) return (-1L);
    if(mx < b->Prec) mx = b->Prec;
    if(a->exponent!=b->exponent) {
        mxs = mx;
        d = a->exponent - b->exponent;
        if(d<0) d = -d;
        mx = mx+(U_LONG)d;
        if(mx<mxs) {
            return VpException(VP_EXCEPTION_INFINITY,"Exponent overflow",0);
        }
    }
    return mx;
}

static S_INT
GetPositiveInt(VALUE v)
{
    S_INT n;
    Check_Type(v, T_FIXNUM);
    n = FIX2INT(v);
    if(n < 0) {
        rb_raise(rb_eArgError, "argument must be positive");
    }
    return n;
}

VP_EXPORT Real *
VpNewRbClass(U_LONG mx, char *str, VALUE klass)
{
    Real *pv = VpAlloc(mx,str);
    pv->obj = (VALUE)Data_Wrap_Struct(klass, 0, BigDecimal_delete, pv);
    return pv;
}

VP_EXPORT Real *
VpCreateRbObject(U_LONG mx, const char *str)
{
    Real *pv = VpAlloc(mx,str);
    pv->obj = (VALUE)Data_Wrap_Struct(rb_cBigDecimal, 0, BigDecimal_delete, pv);
    return pv;
}

/* Returns True if the value is Not a Number */
static VALUE
BigDecimal_IsNaN(VALUE self)
{
    Real *p = GetVpValue(self,1);
    if(VpIsNaN(p))  return Qtrue;
    return Qfalse;
}

/* Returns True if the value is infinite */
static VALUE
BigDecimal_IsInfinite(VALUE self)
{
    Real *p = GetVpValue(self,1);
    if(VpIsPosInf(p)) return INT2FIX(1);
    if(VpIsNegInf(p)) return INT2FIX(-1);
    return Qnil;
}

/* Returns True if the value is finite (not NaN or infinite) */
static VALUE
BigDecimal_IsFinite(VALUE self)
{
    Real *p = GetVpValue(self,1);
    if(VpIsNaN(p)) return Qfalse;
    if(VpIsInf(p)) return Qfalse;
    return Qtrue;
}

/* Returns the value as an integer (Fixnum or Bignum).
 *
 * If the BigNumber is infinity or NaN, returns nil.
 */
static VALUE
BigDecimal_to_i(VALUE self)
{
    ENTER(5);
    int e,n,i,nf;
    U_LONG v,b,j;
    char *psz,*pch;
    Real *p;

    GUARD_OBJ(p,GetVpValue(self,1));

    /* Infinity or NaN not converted. */
    if(VpIsNaN(p)) {
       VpException(VP_EXCEPTION_NaN,"Computation results to 'NaN'(Not a Number)",0);
       return Qnil;
    } else if(VpIsPosInf(p)) {
       VpException(VP_EXCEPTION_INFINITY,"Computation results to 'Infinity'",0);
       return Qnil;
    } else if(VpIsNegInf(p)) {
       VpException(VP_EXCEPTION_INFINITY,"Computation results to '-Infinity'",0);
       return Qnil;
    }

    e = VpExponent10(p);
    if(e<=0) return INT2FIX(0);
    nf = VpBaseFig();
    if(e<=nf) {
        e = VpGetSign(p)*p->frac[0];
        return INT2FIX(e);
    }
    psz = ALLOCA_N(char,(unsigned int)(e+nf+2));

    n = (e+nf-1)/nf;
    pch = psz;
    if(VpGetSign(p)<0) *pch++ = '-';
    for(i=0;i<n;++i) {
        b = VpBaseVal()/10;
        if(i>=(int)p->Prec) {
            while(b) {
                *pch++ = '0';
                b /= 10;
            }
            continue;
        }
        v = p->frac[i];
        while(b) {
            j = v/b;
            *pch++ = (char)(j + '0');
            v -= j*b;
            b /= 10;
        }
    }
    *pch++ = 0;
    return rb_cstr2inum(psz,10);
}

static VALUE
BigDecimal_induced_from(VALUE self, VALUE x)
{
    Real *p = GetVpValue(x,1);
    return p->obj;
}

/* Returns a new Float object having approximately the same value as the
 * BigDecimal number. Normal accuracy limits and built-in errors of binary
 * Float arithmetic apply.
 */
static VALUE
BigDecimal_to_f(VALUE self)
{
    ENTER(1);
    Real *p;
    double d, d2;
    S_LONG e;

    GUARD_OBJ(p,GetVpValue(self,1));
    if(VpVtoD(&d, &e, p)!=1) return rb_float_new(d);
    errno = 0;
    d2 = pow(10.0,(double)e);
    if((errno == ERANGE && e>0) || (d2>1.0 && (fabs(d) > (DBL_MAX / d2)))) {
       VpException(VP_EXCEPTION_OVERFLOW,"BigDecimal to Float conversion",0);
       if(d>0.0) return rb_float_new(DBL_MAX);
       else      return rb_float_new(-DBL_MAX);
    }
    return rb_float_new(d*d2);
}

/* The coerce method provides support for Ruby type coercion. It is not
 * enabled by default.
 * 
 * This means that binary operations like + * / or - can often be performed 
 * on a BigDecimal and an object of another type, if the other object can
 * be coerced into a BigDecimal value.
 *
 * e.g.
 * a = BigDecimal.new("1.0")
 * b = a / 2.0  -> 0.5
 *
 * Note that coercing a String to a BigDecimal is not supported by default;
 * it requires a special compile-time option when building Ruby.
 */
static VALUE
BigDecimal_coerce(VALUE self, VALUE other)
{
    ENTER(2);
    VALUE obj;
    Real *b;
    if(TYPE(other) == T_FLOAT) {
       obj = rb_assoc_new(other, BigDecimal_to_f(self));
    } else {
       GUARD_OBJ(b,GetVpValue(other,1));
       obj = rb_assoc_new(b->obj, self);
    }
    return obj;
}

static VALUE
BigDecimal_uplus(VALUE self)
{
    return self;
}

 /* call-seq:
  * add(value, digits)
  *
  * Add the specified value. 
  *
  * e.g.
  *   c = a.add(b,n)
  *   c = a + b
  *
  * digits:: If specified and less than the number of significant digits of the result, the result is rounded to that number of digits, according to BigDecimal.mode.
  */
static VALUE
BigDecimal_add(VALUE self, VALUE r)
{
    ENTER(5);
    Real *c, *a, *b;
    U_LONG mx;
    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);
    if(VpIsNaN(b)) return b->obj;
    if(VpIsNaN(a)) return a->obj;
    mx = GetAddSubPrec(a,b);
    if(mx==(-1L)) {
        GUARD_OBJ(c,VpCreateRbObject(VpBaseFig() + 1, "0"));
        VpAddSub(c, a, b, 1);
    } else {
        GUARD_OBJ(c,VpCreateRbObject(mx *(VpBaseFig() + 1), "0"));
        if(!mx) {
            VpSetInf(c,VpGetSign(a));
        } else {
            VpAddSub(c, a, b, 1);
        }
    }
    return ToValue(c);
}

 /* call-seq:
  * sub(value, digits)
  *
  * Subtract the specified value. 
  *
  * e.g.
  *   c = a.sub(b,n)
  *   c = a - b
  *
  * digits:: If specified and less than the number of significant digits of the result, the result is rounded to that number of digits, according to BigDecimal.mode.
  */
static VALUE
BigDecimal_sub(VALUE self, VALUE r)
{
    ENTER(5);
    Real *c, *a, *b;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);

    if(VpIsNaN(b)) return b->obj;
    if(VpIsNaN(a)) return a->obj;

    mx = GetAddSubPrec(a,b);
    if(mx==(-1L)) {
        GUARD_OBJ(c,VpCreateRbObject(VpBaseFig() + 1, "0"));
        VpAddSub(c, a, b, -1);
    } else {
        GUARD_OBJ(c,VpCreateRbObject(mx *(VpBaseFig() + 1), "0"));
        if(!mx) {
            VpSetInf(c,VpGetSign(a));
        } else {
            VpAddSub(c, a, b, -1);
        }
    }
    return ToValue(c);
}

static VALUE
BigDecimalCmp(VALUE self, VALUE r,char op)
{
    ENTER(5);
    S_INT e;
    Real *a, *b;
    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return rb_num_coerce_cmp(self,r);
    SAVE(b);
    e = VpComp(a, b);
    if(e==999) return Qnil;
    switch(op)
    {
    case '*': return   INT2FIX(e); /* any op */
    case '=': if(e==0) return Qtrue ; return Qfalse;
    case '!': if(e!=0) return Qtrue ; return Qfalse;
    case 'G': if(e>=0) return Qtrue ; return Qfalse;
    case '>': if(e> 0) return Qtrue ; return Qfalse;
    case 'L': if(e<=0) return Qtrue ; return Qfalse;
    case '<': if(e< 0) return Qtrue ; return Qfalse;
    }
    rb_bug("Undefined operation in BigDecimalCmp()");
}

/* Returns True if the value is zero. */
static VALUE
BigDecimal_zero(VALUE self)
{
    Real *a = GetVpValue(self,1);
    return VpIsZero(a) ? Qtrue : Qfalse;
}

/* Returns True if the value is non-zero. */
static VALUE
BigDecimal_nonzero(VALUE self)
{
    Real *a = GetVpValue(self,1);
    return VpIsZero(a) ? Qnil : self;
}

/* The comparison operator.
 * a <=> b is 0 if a == b, 1 if a > b, -1 if a < b.
 */
static VALUE
BigDecimal_comp(VALUE self, VALUE r)
{
    return BigDecimalCmp(self, r, '*');
}

/*
 * Tests for value equality; returns true if the values are equal.
 *
 * The == and === operators and the eql? method have the same implementation 
 * for BigDecimal.
 *
 * Values may be coerced to perform the comparison:
 *
 * BigDecimal.new('1.0') == 1.0  -> true
 */
static VALUE
BigDecimal_eq(VALUE self, VALUE r)
{
    return BigDecimalCmp(self, r, '=');
}

/* call-seq:
 * a < b
 *
 * Returns true if a is less than b. Values may be coerced to perform the
 * comparison (see ==, coerce).
 */
static VALUE
BigDecimal_lt(VALUE self, VALUE r)
{
    return BigDecimalCmp(self, r, '<');
}

/* call-seq:
 * a <= b
 *
 * Returns true if a is less than or equal to b. Values may be coerced to 
 * perform the comparison (see ==, coerce).
 */
static VALUE
BigDecimal_le(VALUE self, VALUE r)
{
    return BigDecimalCmp(self, r, 'L');
}

/* call-seq:
 * a > b
 *
 * Returns true if a is greater than b.  Values may be coerced to 
 * perform the comparison (see ==, coerce).
 */
static VALUE
BigDecimal_gt(VALUE self, VALUE r)
{
    return BigDecimalCmp(self, r, '>');
}

/* call-seq:
 * a >= b
 *
 * Returns true if a is greater than or equal to b. Values may be coerced to 
 * perform the comparison (see ==, coerce)
 */
static VALUE
BigDecimal_ge(VALUE self, VALUE r)
{
    return BigDecimalCmp(self, r, 'G');
}

static VALUE
BigDecimal_neg(VALUE self)
{
    ENTER(5);
    Real *c, *a;
    GUARD_OBJ(a,GetVpValue(self,1));
    GUARD_OBJ(c,VpCreateRbObject(a->Prec *(VpBaseFig() + 1), "0"));
    VpAsgn(c, a, -1);
    return ToValue(c);
}

 /* call-seq:
  * mult(value, digits)
  *
  * Multiply by the specified value. 
  *
  * e.g.
  *   c = a.mult(b,n)
  *   c = a * b
  *
  * digits:: If specified and less than the number of significant digits of the result, the result is rounded to that number of digits, according to BigDecimal.mode.
  */
static VALUE
BigDecimal_mult(VALUE self, VALUE r)
{
    ENTER(5);
    Real *c, *a, *b;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);

    mx = a->Prec + b->Prec;
    GUARD_OBJ(c,VpCreateRbObject(mx *(VpBaseFig() + 1), "0"));
    VpMult(c, a, b);
    return ToValue(c);
}

static VALUE
BigDecimal_divide(Real **c, Real **res, Real **div, VALUE self, VALUE r)
/* For c = self.div(r): with round operation */
{
    ENTER(5);
    Real *a, *b;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);
    *div = b;
    mx =(a->MaxPrec + b->MaxPrec + 1) * VpBaseFig();
    GUARD_OBJ((*c),VpCreateRbObject(mx, "#0"));
    GUARD_OBJ((*res),VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
    VpDivd(*c, *res, a, b);
    return (VALUE)0;
}

 /* call-seq:
  * div(value, digits)
  * quo(value)
  *
  * Divide by the specified value. 
  *
  * e.g.
  *   c = a.div(b,n)
  *
  * digits:: If specified and less than the number of significant digits of the result, the result is rounded to that number of digits, according to BigDecimal.mode.
  * 
  * If digits is 0, the result is the same as the / operator. If not, the
  * result is an integer BigDecimal, by analogy with Float#div.
  *
  * The alias quo is provided since div(value, 0) is the same as computing
  * the quotient; see divmod.
  */
static VALUE
BigDecimal_div(VALUE self, VALUE r)
/* For c = self/r: with round operation */
{
    ENTER(5);
    Real *c=NULL, *res=NULL, *div = NULL;
    r = BigDecimal_divide(&c, &res, &div, self, r);
    if(r!=(VALUE)0) return r; /* coerced by other */
    SAVE(c);SAVE(res);SAVE(div);
    /* a/b = c + r/b */
    /* c xxxxx
       r 00000yyyyy  ==> (y/b)*BASE >= HALF_BASE
     */
    /* Round */
    if(VpHasVal(div)) { /* frac[0] must be zero for NaN,INF,Zero */
       VpInternalRound(c,0,c->frac[c->Prec-1],(VpBaseVal()*res->frac[0])/div->frac[0]);
    }
    return ToValue(c);
}

/*
 * %: mod = a%b = a - (a.to_f/b).floor * b
 * div = (a.to_f/b).floor
 */
static VALUE
BigDecimal_DoDivmod(VALUE self, VALUE r, Real **div, Real **mod)
{
    ENTER(8);
    Real *c=NULL, *d=NULL, *res=NULL;
    Real *a, *b;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);

    if(VpIsNaN(a) || VpIsNaN(b)) goto NaN;
    if(VpIsInf(a) || VpIsInf(b)) goto NaN;
    if(VpIsZero(b))              goto NaN;
    if(VpIsZero(a)) {
       GUARD_OBJ(c,VpCreateRbObject(1, "0"));
       GUARD_OBJ(d,VpCreateRbObject(1, "0"));
       *div = d;
       *mod = c;
       return (VALUE)0;
    }

    mx = a->Prec;
    if(mx<b->Prec) mx = b->Prec;
    mx =(mx + 1) * VpBaseFig();
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    GUARD_OBJ(res,VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
    VpDivd(c, res, a, b);
    mx = c->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(d,VpCreateRbObject(mx, "0"));
    VpActiveRound(d,c,VP_ROUND_DOWN,0);
    VpMult(res,d,b);
    VpAddSub(c,a,res,-1);
    if(!VpIsZero(c) && (VpGetSign(a)*VpGetSign(b)<0)) {
        VpAddSub(res,d,VpOne(),-1);
        VpAddSub(d  ,c,b,       1);
        *div = res;
        *mod = d;
    } else {
        *div = d;
        *mod = c;
    }
    return (VALUE)0;

NaN:
    GUARD_OBJ(c,VpCreateRbObject(1, "NaN"));
    GUARD_OBJ(d,VpCreateRbObject(1, "NaN"));
    *div = d;
    *mod = c;
    return (VALUE)0;
}

/* call-seq:
 * a % b
 * a.modulo(b)
 *
 * Returns the modulus from dividing by b. See divmod.
 */
static VALUE
BigDecimal_mod(VALUE self, VALUE r) /* %: a%b = a - (a.to_f/b).floor * b */
{
    ENTER(3);
    VALUE obj;
    Real *div=NULL, *mod=NULL;

    obj = BigDecimal_DoDivmod(self,r,&div,&mod);
    if(obj!=(VALUE)0) return obj;
    SAVE(div);SAVE(mod);
    return ToValue(mod);
}

static VALUE
BigDecimal_divremain(VALUE self, VALUE r, Real **dv, Real **rv)
{
    ENTER(10);
    U_LONG mx;
    Real *a=NULL, *b=NULL, *c=NULL, *res=NULL, *d=NULL, *rr=NULL, *ff=NULL;
    Real *f=NULL;

    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);

    mx  =(a->MaxPrec + b->MaxPrec) *VpBaseFig();
    GUARD_OBJ(c  ,VpCreateRbObject(mx, "0"));
    GUARD_OBJ(res,VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
    GUARD_OBJ(rr ,VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
    GUARD_OBJ(ff ,VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));

    VpDivd(c, res, a, b);

    mx = c->Prec *(VpBaseFig() + 1);

    GUARD_OBJ(d,VpCreateRbObject(mx, "0"));
    GUARD_OBJ(f,VpCreateRbObject(mx, "0"));

    VpActiveRound(d,c,VP_ROUND_DOWN,0); /* 0: round off */

    VpFrac(f, c);
    VpMult(rr,f,b);
    VpAddSub(ff,res,rr,1);

    *dv = d;
    *rv = ff;
    return (VALUE)0;
}

/* Returns the remainder from dividing by the value.
 *
 * If the values divided are of the same sign, the remainder is the same as
 * the modulus (see divmod).
 *
 * Otherwise, the remainder is the modulus minus the value divided by.
 */
static VALUE
BigDecimal_remainder(VALUE self, VALUE r) /* remainder */
{
    VALUE  f;
    Real  *d,*rv;
    f = BigDecimal_divremain(self,r,&d,&rv);
    if(f!=(VALUE)0) return f;
    return ToValue(rv);
}

/* Divides by the specified value, and returns the quotient and modulus
 * as BigDecimal numbers. The quotient is rounded towards negative infinity.
 *
 * For example:
 *
 * require 'bigdecimal'
 *
 * a = BigDecimal.new("42")
 * b = BigDecimal.new("9")
 *
 * q,m = a.divmod(b)
 *
 * c = q * b + m
 *
 * a == c  -> true
 *
 * The quotient q is (a/b).floor, and the modulus is the amount that must be 
 * added to q * b to get a.
 */
static VALUE
BigDecimal_divmod(VALUE self, VALUE r)
{
    ENTER(5);
    VALUE obj;
    Real *div=NULL, *mod=NULL;

    obj = BigDecimal_DoDivmod(self,r,&div,&mod);
    if(obj!=(VALUE)0) return obj;
    SAVE(div);SAVE(mod);
    obj = rb_assoc_new(ToValue(div), ToValue(mod));
    return obj;
}

static VALUE
BigDecimal_div2(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    VALUE b,n;
    int na = rb_scan_args(argc,argv,"11",&b,&n);
    if(na==1) { /* div in Float sense */
       VALUE obj;
       Real *div=NULL;
       Real *mod;
       obj = BigDecimal_DoDivmod(self,b,&div,&mod);
       if(obj!=(VALUE)0) return obj;
       return ToValue(div);
    } else {    /* div in BigDecimal sense */
       U_LONG ix = (U_LONG)GetPositiveInt(n);
       if(ix==0) return BigDecimal_div(self,b);
       else {
          Real *res=NULL;
          Real *av=NULL, *bv=NULL, *cv=NULL;
          U_LONG mx = (ix+VpBaseFig()*2);
          U_LONG pl = VpSetPrecLimit(0);

          GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
          GUARD_OBJ(av,GetVpValue(self,1));
          GUARD_OBJ(bv,GetVpValue(b,1));
          mx = av->Prec + bv->Prec + 2;
          if(mx <= cv->MaxPrec) mx = cv->MaxPrec+1;
          GUARD_OBJ(res,VpCreateRbObject((mx * 2  + 2)*VpBaseFig(), "#0"));
          VpDivd(cv,res,av,bv);
          VpSetPrecLimit(pl);
          VpLeftRound(cv,VpGetRoundMode(),ix);
          return ToValue(cv);
       }
    }
}

static VALUE
BigDecimal_add2(VALUE self, VALUE b, VALUE n)
{
    ENTER(2);
    Real   *cv;
    U_LONG mx = (U_LONG)GetPositiveInt(n);
    if(mx==0) return BigDecimal_add(self,b);
    else {
       U_LONG pl = VpSetPrecLimit(0);
       VALUE   c = BigDecimal_add(self,b);
       VpSetPrecLimit(pl);
       GUARD_OBJ(cv,GetVpValue(c,1));
       VpLeftRound(cv,VpGetRoundMode(),mx);
       return ToValue(cv);
    }
}

static VALUE
BigDecimal_sub2(VALUE self, VALUE b, VALUE n)
{
    ENTER(2);
    Real *cv;
    U_LONG mx = (U_LONG)GetPositiveInt(n);
    if(mx==0) return BigDecimal_sub(self,b);
    else {
       U_LONG pl = VpSetPrecLimit(0);
       VALUE   c = BigDecimal_sub(self,b);
       VpSetPrecLimit(pl);
       GUARD_OBJ(cv,GetVpValue(c,1));
       VpLeftRound(cv,VpGetRoundMode(),mx);
       return ToValue(cv);
    }
}

static VALUE
BigDecimal_mult2(VALUE self, VALUE b, VALUE n)
{
    ENTER(2);
    Real *cv;
    U_LONG mx = (U_LONG)GetPositiveInt(n);
    if(mx==0) return BigDecimal_mult(self,b);
    else {
       U_LONG pl = VpSetPrecLimit(0);
       VALUE   c = BigDecimal_mult(self,b);
       VpSetPrecLimit(pl);
       GUARD_OBJ(cv,GetVpValue(c,1));
       VpLeftRound(cv,VpGetRoundMode(),mx);
       return ToValue(cv);
    }
}

/* Returns the absolute value.
 *
 * BigDecimal('5').abs -> 5
 *
 * BigDecimal('-3').abs -> 3
 */
static VALUE
BigDecimal_abs(VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpAsgn(c, a, 1);
    VpChangeSign(c,(S_INT)1);
    return ToValue(c);
}

/* call-seq:
 * sqrt(n)
 *
 * Returns the square root of the value.
 *
 * If n is specified, returns at least that many significant digits.
 */
static VALUE
BigDecimal_sqrt(VALUE self, VALUE nFig)
{
    ENTER(5);
    Real *c, *a;
    S_INT mx, n;

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);

    n = GetPositiveInt(nFig) + VpDblFig() + 1;
    if(mx <= n) mx = n;
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpSqrt(c, a);
    return ToValue(c);
}

/* Return the integer part of the number.
 */
static VALUE
BigDecimal_fix(VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpActiveRound(c,a,VP_ROUND_DOWN,0); /* 0: round off */
    return ToValue(c);
}

/* call-seq:
 * round(n,mode)
 *
 * Round to the nearest 1 (by default), returning the result as a BigDecimal.
 *
 * BigDecimal('3.14159').round -> 3
 *
 * BigDecimal('8.7').round -> 9
 *
 * If n is specified and positive, the fractional part of the result has no
 * more than that many digits. 
 *
 * If n is specified and negative, at least that many digits to the left of the
 * decimal point will be 0 in the result.
 *
 * BigDecimal('3.14159').round(3) -> 3.142
 *
 * BigDecimal('13345.234').round(-2) -> 13300.0
 *
 * The value of the optional mode argument can be used to determine how 
 * rounding is performed; see BigDecimal.mode.
 */
static VALUE
BigDecimal_round(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real   *c, *a;
    int    iLoc = 0;
    U_LONG mx;
    VALUE  vLoc;
    VALUE  vRound;
    U_LONG pl;

    int    sw = VpGetRoundMode();

    int na = rb_scan_args(argc,argv,"02",&vLoc,&vRound);
    switch(na) {
    case 0:
        iLoc = 0;
        break;
    case 1:
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
        break;
    case 2:
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
        Check_Type(vRound, T_FIXNUM);
        sw   = FIX2INT(vRound);
        if(!VpIsRoundMode(sw)) {
            rb_raise(rb_eTypeError, "invalid rounding mode");
            return Qnil;
        }
        break;
    }

    pl = VpSetPrecLimit(0);
    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpSetPrecLimit(pl);
    VpActiveRound(c,a,sw,iLoc);
    return ToValue(c);
}

/* call-seq:
 * truncate(n)
 *
 * Truncate to the nearest 1, returning the result as a BigDecimal.
 *
 * BigDecimal('3.14159').truncate -> 3
 *
 * BigDecimal('8.7').truncate -> 8
 *
 * If n is specified and positive, the fractional part of the result has no
 * more than that many digits. 
 *
 * If n is specified and negative, at least that many digits to the left of the
 * decimal point will be 0 in the result.
 *
 * BigDecimal('3.14159').truncate(3) -> 3.141
 *
 * BigDecimal('13345.234').truncate(-2) -> 13300.0
 */
static VALUE
BigDecimal_truncate(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *c, *a;
    int iLoc;
    U_LONG mx;
    VALUE vLoc;
    U_LONG pl = VpSetPrecLimit(0);

    if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
        iLoc = 0;
    } else {
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpSetPrecLimit(pl);
    VpActiveRound(c,a,VP_ROUND_DOWN,iLoc); /* 0: truncate */
    return ToValue(c);
}

/* Return the fractional part of the number.
 */
static VALUE
BigDecimal_frac(VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpFrac(c, a);
    return ToValue(c);
}

/* call-seq:
 * floor(n)
 *
 * Return the largest integer less than or equal to the value, as a BigDecimal.
 *
 * BigDecimal('3.14159').floor -> 3
 *
 * BigDecimal('-9.1').floor -> -10
 *
 * If n is specified and positive, the fractional part of the result has no
 * more than that many digits.  
 *
 * If n is specified and negative, at least that
 * many digits to the left of the decimal point will be 0 in the result.
 *
 * BigDecimal('3.14159').floor(3) -> 3.141
 *
 * BigDecimal('13345.234').floor(-2) -> 13300.0
 */
static VALUE
BigDecimal_floor(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;
    int iLoc;
    VALUE vLoc;
    U_LONG pl = VpSetPrecLimit(0);

    if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
        iLoc = 0;
    } else {
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpSetPrecLimit(pl);
    VpActiveRound(c,a,VP_ROUND_FLOOR,iLoc);
    return ToValue(c);
}

/* call-seq:
 * ceil(n)
 *
 * Return the smallest integer greater than or equal to the value, as a BigDecimal.
 *
 * BigDecimal('3.14159').ceil -> 4
 *
 * BigDecimal('-9.1').ceil -> -9
 *
 * If n is specified and positive, the fractional part of the result has no
 * more than that many digits.  
 *
 * If n is specified and negative, at least that
 * many digits to the left of the decimal point will be 0 in the result.
 *
 * BigDecimal('3.14159').ceil(3) -> 3.142
 *
 * BigDecimal('13345.234').ceil(-2) -> 13400.0
 */
static VALUE
BigDecimal_ceil(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;
    int iLoc;
    VALUE vLoc;
    U_LONG pl = VpSetPrecLimit(0);

    if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
        iLoc = 0;
    } else {
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpSetPrecLimit(pl);
    VpActiveRound(c,a,VP_ROUND_CEIL,iLoc);
    return ToValue(c);
}

/* call-seq:
 * to_s(s)
 *
 * Converts the value to a string.
 *
 * The default format looks like  0.xxxxEnn.
 *
 * The optional parameter s consists of either an integer; or an optional '+'
 * or ' ', followed by an optional number, followed by an optional 'E' or 'F'.
 *
 * If there is a '+' at the start of s, positive values are returned with
 * a leading '+'.
 *
 * A space at the start of s returns positive values with a leading space.
 *
 * If s contains a number, a space is inserted after each group of that many 
 * fractional digits.
 *
 * If s ends with an 'E', engineering notation (0.xxxxEnn) is used.
 *
 * If s ends with an 'F', conventional floating point notation is used.
 *
 * Examples:
 *
 * BigDecimal.new('-123.45678901234567890').to_s('5F') -> '-123.45678 90123 45678 9'
 *
 * BigDecimal.new('123.45678901234567890').to_s('+8F') -> '+123.45678901 23456789'
 *
 * BigDecimal.new('123.45678901234567890').to_s(' F') -> ' 123.4567890123456789'
 */
static VALUE
BigDecimal_to_s(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    int   fmt=0;   /* 0:E format */
    int   fPlus=0; /* =0:default,=1: set ' ' before digits ,set '+' before digits. */
    Real  *vp;
    char  *psz;
    char   ch;
    U_LONG nc;
    S_INT  mc = 0;
    VALUE  f;

    GUARD_OBJ(vp,GetVpValue(self,1));
    
    if(rb_scan_args(argc,argv,"01",&f)==1) {
        if(TYPE(f)==T_STRING) {
            SafeStringValue(f);
            psz = RSTRING_PTR(f);
            if(*psz==' ') {
                fPlus = 1; psz++;
            } else if(*psz=='+') {
                fPlus = 2; psz++;
            }
            while(ch=*psz++) {
                if(ISSPACE(ch)) continue;
                if(!ISDIGIT(ch)) {
                    if(ch=='F' || ch=='f') fmt = 1; /* F format */
                    break;
                }
                mc = mc * 10 + ch - '0';
            }
        } else {
            mc  = GetPositiveInt(f);
        }
    }
    if(fmt) {
        nc = VpNumOfChars(vp,"F");
    } else {
        nc = VpNumOfChars(vp,"E");
    }
    if(mc>0) nc += (nc + mc - 1) / mc + 1;

    psz = ALLOCA_N(char,(unsigned int)nc);

    if(fmt) {
        VpToFString(vp, psz, mc, fPlus);
    } else {
        VpToString (vp, psz, mc, fPlus);
    }
    return rb_str_new2(psz);
}

/* Splits a BigDecimal number into four parts, returned as an array of values.
 *
 * The first value represents the sign of the BigDecimal, and is -1 or 1, or 0
 * if the BigDecimal is Not a Number.
 *
 * The second value is a string representing the significant digits of the
 * BigDecimal, with no leading zeros.
 *
 * The third value is the base used for arithmetic (currently always 10) as an
 * Integer.
 *
 * The fourth value is an Integer exponent.
 *
 * If the BigDecimal can be represented as 0.xxxxxx*10**n, then xxxxxx is the 
 * string of significant digits with no leading zeros, and n is the exponent.
 *
 * From these values, you can translate a BigDecimal to a float as follows:
 *
 *   sign, significant_digits, base, exponent = a.split
 *   f = sign * "0.#{significant_digits}".to_f * (base ** exponent)
 *
 * (Note that the to_f method is provided as a more convenient way to translate 
 * a BigDecimal to a Float.)
 */
static VALUE
BigDecimal_split(VALUE self)
{
    ENTER(5);
    Real *vp;
    VALUE obj,obj1;
    S_LONG e;
    S_LONG s;
    char *psz1;

    GUARD_OBJ(vp,GetVpValue(self,1));
    psz1 = ALLOCA_N(char,(unsigned int)VpNumOfChars(vp,"E"));
    VpSzMantissa(vp,psz1);
    s = 1;
    if(psz1[0]=='-') {
        s = -1; ++psz1;
    }
    if(psz1[0]=='N') s=0; /* NaN */
    e = VpExponent10(vp);
    obj1 = rb_str_new2(psz1);
    obj  = rb_ary_new2(4);
    rb_ary_push(obj, INT2FIX(s));
    rb_ary_push(obj, obj1);
    rb_ary_push(obj, INT2FIX(10));
    rb_ary_push(obj, INT2NUM(e));
    return obj;
}

/* Returns the exponent of the BigDecimal number, as an Integer.
 *
 * If the number can be represented as 0.xxxxxx*10**n where xxxxxx is a string
 * of digits with no leading zeros, then n is the exponent.
 */
static VALUE
BigDecimal_exponent(VALUE self)
{
    S_LONG e = VpExponent10(GetVpValue(self,1));
    return INT2NUM(e);
}

/* Returns debugging information about the value as a string of comma-separated
 * values in angle brackets with a leading #:
 *
 * BigDecimal.new("1234.5678").inspect ->
 * "#<BigDecimal:b7ea1130,'0.12345678E4',8(12)>"
 *
 * The first part is the address, the second is the value as a string, and
 * the final part ss(mm) is the current number of significant digits and the
 * maximum number of significant digits, respectively.
 */
static VALUE
BigDecimal_inspect(VALUE self)
{
    ENTER(5);
    Real *vp;
    VALUE obj;
    unsigned int nc;
    char *psz1;
    char *pszAll;

    GUARD_OBJ(vp,GetVpValue(self,1));
    nc = VpNumOfChars(vp,"E");
    nc +=(nc + 9) / 10;

    psz1   = ALLOCA_N(char,nc);
    pszAll = ALLOCA_N(char,nc+256);
    VpToString(vp, psz1, 10, 0);
    sprintf(pszAll,"#<BigDecimal:%lx,'%s',%lu(%lu)>",self,psz1,VpPrec(vp)*VpBaseFig(),VpMaxPrec(vp)*VpBaseFig());
    obj = rb_str_new2(pszAll);
    return obj;
}

/* call-seq:
 * power(n)
 *
 * Returns the value raised to the power of n. Note that n must be an Integer.
 *
 * Also available as the operator **
 */
static VALUE
BigDecimal_power(VALUE self, VALUE p)
{
    ENTER(5);
    Real *x, *y;
    S_LONG mp, ma, n;

    Check_Type(p, T_FIXNUM);
    n = FIX2INT(p);
    ma = n;
    if(ma < 0)  ma = -ma;
    if(ma == 0) ma = 1;

    GUARD_OBJ(x,GetVpValue(self,1));
    if(VpIsDef(x)) {
        mp = x->Prec *(VpBaseFig() + 1);
        GUARD_OBJ(y,VpCreateRbObject(mp *(ma + 1), "0"));
    } else {
        GUARD_OBJ(y,VpCreateRbObject(1, "0"));
    }
    VpPower(y, x, n);
    return ToValue(y);
}

static VALUE
BigDecimal_global_new(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *pv;
    S_LONG mf;
    VALUE  nFig;
    VALUE  iniValue;

    if(rb_scan_args(argc,argv,"11",&iniValue,&nFig)==1) {
        mf = 0;
    } else {
        mf = GetPositiveInt(nFig);
    }
    SafeStringValue(iniValue);
    GUARD_OBJ(pv,VpCreateRbObject(mf, RSTRING_PTR(iniValue)));
    return ToValue(pv);
}

 /* call-seq:
  * new(initial, digits)
  *
  * Create a new BigDecimal object.
  *
  * initial:: The initial value, as a String. Spaces are ignored, unrecognized characters terminate the value.
  *
  * digits:: The number of significant digits, as a Fixnum. If omitted or 0, the number of significant digits is determined from the initial value.
  *
  * The actual number of significant digits used in computation is usually
  * larger than the specified number.
  */
static VALUE
BigDecimal_new(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *pv;
    S_LONG mf;
    VALUE  nFig;
    VALUE  iniValue;

    if(rb_scan_args(argc,argv,"11",&iniValue,&nFig)==1) {
        mf = 0;
    } else {
        mf = GetPositiveInt(nFig);
    }
    SafeStringValue(iniValue);
    GUARD_OBJ(pv,VpNewRbClass(mf, RSTRING_PTR(iniValue),self));
    return ToValue(pv);
}

 /* call-seq:
  * BigDecimal.limit(digits)
  *
  * Limit the number of significant digits in newly created BigDecimal 
  * numbers to the specified value. Rounding is performed as necessary, 
  * as specified by BigDecimal.mode.
  *
  * A limit of 0, the default, means no upper limit.
  *
  * The limit specified by this method takes priority over any limit 
  * specified to instance methods such as ceil, floor, truncate, or round.
  */
static VALUE
BigDecimal_limit(int argc, VALUE *argv, VALUE self)
{
    VALUE  nFig;
    VALUE  nCur = INT2NUM(VpGetPrecLimit());

    if(rb_scan_args(argc,argv,"01",&nFig)==1) {
        int nf;
        if(nFig==Qnil) return nCur;
        Check_Type(nFig, T_FIXNUM);
        nf = FIX2INT(nFig);
        if(nf<0) {
            rb_raise(rb_eArgError, "argument must be positive");
        }
        VpSetPrecLimit(nf);
    }
    return nCur;
}

/* Returns the sign of the value.
 *
 * Returns a positive value if > 0, a negative value if < 0, and a 
 * zero if == 0.
 *
 * The specific value returned indicates the type and sign of the BigDecimal, 
 * as follows:
 *
 * BigDecimal::SIGN_NaN:: value is Not a Number
 * BigDecimal::SIGN_POSITIVE_ZERO:: value is +0
 * BigDecimal::SIGN_NEGATIVE_ZERO:: value is -0
 * BigDecimal::SIGN_POSITIVE_INFINITE:: value is +infinity
 * BigDecimal::SIGN_NEGATIVE_INFINITE:: value is -infinity
 * BigDecimal::SIGN_POSITIVE_FINITE:: value is positive
 * BigDecimal::SIGN_NEGATIVE_FINITE:: value is negative
 */
static VALUE
BigDecimal_sign(VALUE self)
{ /* sign */
    int s = GetVpValue(self,1)->sign;
    return INT2FIX(s);
}

void
Init_bigdecimal(void)
{
    /* Initialize VP routines */
    VpInit((U_LONG)0);

    /* Class and method registration */
    rb_cBigDecimal = rb_define_class("BigDecimal",rb_cNumeric);

    /* Global function */
    rb_define_global_function("BigDecimal", BigDecimal_global_new, -1);

    /* Class methods */
    rb_define_singleton_method(rb_cBigDecimal, "new", BigDecimal_new, -1);
    rb_define_singleton_method(rb_cBigDecimal, "mode", BigDecimal_mode, -1);
    rb_define_singleton_method(rb_cBigDecimal, "limit", BigDecimal_limit, -1);
    rb_define_singleton_method(rb_cBigDecimal, "double_fig", BigDecimal_double_fig, 0);
    rb_define_singleton_method(rb_cBigDecimal, "induced_from",BigDecimal_induced_from, 1);
    rb_define_singleton_method(rb_cBigDecimal, "_load", BigDecimal_load, 1);
    rb_define_singleton_method(rb_cBigDecimal, "ver", BigDecimal_version, 0);

    /* Constants definition */

    /* 
     * Base value used in internal calculations.  On a 32 bit system, BASE 
     * is 10000, indicating that calculation is done in groups of 4 digits.  
     * (If it were larger, BASE**2 wouldn't fit in 32 bits, so you couldn't
     * guarantee that two groups could always be multiplied together without 
     * overflow.) 
     */
    rb_define_const(rb_cBigDecimal, "BASE", INT2FIX((S_INT)VpBaseVal()));

    /* Exceptions */

    /*
     * 0xff: Determines whether overflow, underflow or zero divide result in 
     * an exception being thrown. See BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_ALL",INT2FIX(VP_EXCEPTION_ALL));

    /* 
     * 0x02: Determines what happens when the result of a computation is not a 
     * number (NaN). See BigDecimal.mode. 
     */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_NaN",INT2FIX(VP_EXCEPTION_NaN));

    /* 
     * 0x01: Determines what happens when the result of a computation is
     * infinity.  See BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_INFINITY",INT2FIX(VP_EXCEPTION_INFINITY));

    /* 
     * 0x04: Determines what happens when the result of a computation is an
     * underflow (a result too small to be represented). See BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_UNDERFLOW",INT2FIX(VP_EXCEPTION_UNDERFLOW));

    /* 
     * 0x01: Determines what happens when the result of a computation is an
     * underflow (a result too large to be represented). See BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_OVERFLOW",INT2FIX(VP_EXCEPTION_OVERFLOW));

    /* 
     * 0x01: Determines what happens when a division by zero is performed.
     * See BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_ZERODIVIDE",INT2FIX(VP_EXCEPTION_ZERODIVIDE));

    /* 
     * 0x100: Determines what happens when a result must be rounded in order to
     * fit in the appropriate number of significant digits. See
     * BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "ROUND_MODE",INT2FIX(VP_ROUND_MODE));

    /* 1: Indicates that values should be rounded away from zero. See
     * BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "ROUND_UP",INT2FIX(VP_ROUND_UP));

    /* 2: Indicates that values should be rounded towards zero. See
     * BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "ROUND_DOWN",INT2FIX(VP_ROUND_DOWN));

    /* 3: Indicates that digits >= 5 should be rounded up, others rounded down.
     * See BigDecimal.mode. */
    rb_define_const(rb_cBigDecimal, "ROUND_HALF_UP",INT2FIX(VP_ROUND_HALF_UP));

    /* 4: Indicates that digits >= 6 should be rounded up, others rounded down.
     * See BigDecimal.mode.
     */
    rb_define_const(rb_cBigDecimal, "ROUND_HALF_DOWN",INT2FIX(VP_ROUND_HALF_DOWN));
    /* 5: Round towards +infinity. See BigDecimal.mode. */
    rb_define_const(rb_cBigDecimal, "ROUND_CEILING",INT2FIX(VP_ROUND_CEIL));

    /* 6: Round towards -infinity. See BigDecimal.mode. */
    rb_define_const(rb_cBigDecimal, "ROUND_FLOOR",INT2FIX(VP_ROUND_FLOOR));

    /* 7: Round towards the even neighbor. See BigDecimal.mode. */
    rb_define_const(rb_cBigDecimal, "ROUND_HALF_EVEN",INT2FIX(VP_ROUND_HALF_EVEN));

    /* 0: Indicates that a value is not a number. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_NaN",INT2FIX(VP_SIGN_NaN));

    /* 1: Indicates that a value is +0. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_POSITIVE_ZERO",INT2FIX(VP_SIGN_POSITIVE_ZERO));

    /* -1: Indicates that a value is -0. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_NEGATIVE_ZERO",INT2FIX(VP_SIGN_NEGATIVE_ZERO));

    /* 2: Indicates that a value is positive and finite. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_POSITIVE_FINITE",INT2FIX(VP_SIGN_POSITIVE_FINITE));

    /* -2: Indicates that a value is negative and finite. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_NEGATIVE_FINITE",INT2FIX(VP_SIGN_NEGATIVE_FINITE));

    /* 3: Indicates that a value is positive and infinite. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_POSITIVE_INFINITE",INT2FIX(VP_SIGN_POSITIVE_INFINITE));

    /* -3: Indicates that a value is negative and infinite. See BigDecimal.sign. */
    rb_define_const(rb_cBigDecimal, "SIGN_NEGATIVE_INFINITE",INT2FIX(VP_SIGN_NEGATIVE_INFINITE));

    /* instance methods */
    rb_define_method(rb_cBigDecimal, "precs", BigDecimal_prec, 0);

    rb_define_method(rb_cBigDecimal, "add", BigDecimal_add2, 2);
    rb_define_method(rb_cBigDecimal, "sub", BigDecimal_sub2, 2);
    rb_define_method(rb_cBigDecimal, "mult", BigDecimal_mult2, 2);
    rb_define_method(rb_cBigDecimal, "div",BigDecimal_div2, -1);
    rb_define_method(rb_cBigDecimal, "hash", BigDecimal_hash, 0);
    rb_define_method(rb_cBigDecimal, "to_s", BigDecimal_to_s, -1);
    rb_define_method(rb_cBigDecimal, "to_i", BigDecimal_to_i, 0);
    rb_define_method(rb_cBigDecimal, "to_int", BigDecimal_to_i, 0);
    rb_define_method(rb_cBigDecimal, "split", BigDecimal_split, 0);
    rb_define_method(rb_cBigDecimal, "+", BigDecimal_add, 1);
    rb_define_method(rb_cBigDecimal, "-", BigDecimal_sub, 1);
    rb_define_method(rb_cBigDecimal, "+@", BigDecimal_uplus, 0);
    rb_define_method(rb_cBigDecimal, "-@", BigDecimal_neg, 0);
    rb_define_method(rb_cBigDecimal, "*", BigDecimal_mult, 1);
    rb_define_method(rb_cBigDecimal, "/", BigDecimal_div, 1);
    rb_define_method(rb_cBigDecimal, "quo", BigDecimal_div, 1);
    rb_define_method(rb_cBigDecimal, "%", BigDecimal_mod, 1);
    rb_define_method(rb_cBigDecimal, "modulo", BigDecimal_mod, 1);
    rb_define_method(rb_cBigDecimal, "remainder", BigDecimal_remainder, 1);
    rb_define_method(rb_cBigDecimal, "divmod", BigDecimal_divmod, 1);
    /* rb_define_method(rb_cBigDecimal, "dup", BigDecimal_dup, 0); */
    rb_define_method(rb_cBigDecimal, "to_f", BigDecimal_to_f, 0);
    rb_define_method(rb_cBigDecimal, "abs", BigDecimal_abs, 0);
    rb_define_method(rb_cBigDecimal, "sqrt", BigDecimal_sqrt, 1);
    rb_define_method(rb_cBigDecimal, "fix", BigDecimal_fix, 0);
    rb_define_method(rb_cBigDecimal, "round", BigDecimal_round, -1);
    rb_define_method(rb_cBigDecimal, "frac", BigDecimal_frac, 0);
    rb_define_method(rb_cBigDecimal, "floor", BigDecimal_floor, -1);
    rb_define_method(rb_cBigDecimal, "ceil", BigDecimal_ceil, -1);
    rb_define_method(rb_cBigDecimal, "power", BigDecimal_power, 1);
    rb_define_method(rb_cBigDecimal, "**", BigDecimal_power, 1);
    rb_define_method(rb_cBigDecimal, "<=>", BigDecimal_comp, 1);
    rb_define_method(rb_cBigDecimal, "==", BigDecimal_eq, 1);
    rb_define_method(rb_cBigDecimal, "===", BigDecimal_eq, 1);
    rb_define_method(rb_cBigDecimal, "eql?", BigDecimal_eq, 1);
    rb_define_method(rb_cBigDecimal, "<", BigDecimal_lt, 1);
    rb_define_method(rb_cBigDecimal, "<=", BigDecimal_le, 1);
    rb_define_method(rb_cBigDecimal, ">", BigDecimal_gt, 1);
    rb_define_method(rb_cBigDecimal, ">=", BigDecimal_ge, 1);
    rb_define_method(rb_cBigDecimal, "zero?", BigDecimal_zero, 0);
    rb_define_method(rb_cBigDecimal, "nonzero?", BigDecimal_nonzero, 0);
    rb_define_method(rb_cBigDecimal, "coerce", BigDecimal_coerce, 1);
    rb_define_method(rb_cBigDecimal, "inspect", BigDecimal_inspect, 0);
    rb_define_method(rb_cBigDecimal, "exponent", BigDecimal_exponent, 0);
    rb_define_method(rb_cBigDecimal, "sign", BigDecimal_sign, 0);
    rb_define_method(rb_cBigDecimal, "nan?",      BigDecimal_IsNaN, 0);
    rb_define_method(rb_cBigDecimal, "infinite?", BigDecimal_IsInfinite, 0);
    rb_define_method(rb_cBigDecimal, "finite?",   BigDecimal_IsFinite, 0);
    rb_define_method(rb_cBigDecimal, "truncate",  BigDecimal_truncate, -1);
    rb_define_method(rb_cBigDecimal, "_dump", BigDecimal_dump, -1);
}

/*
 *
 *  ============================================================================
 *
 *  vp_ routines begin from here.
 *
 *  ============================================================================
 *
 */
#ifdef _DEBUG
/*static int gfDebug = 1;*/         /* Debug switch */
static int gfCheckVal = 1;      /* Value checking flag in VpNmlz()  */
#endif /* _DEBUG */

static U_LONG gnPrecLimit = 0;  /* Global upper limit of the precision newly allocated */
static U_LONG gfRoundMode = VP_ROUND_HALF_UP; /* Mode for general rounding operation   */

static U_LONG BASE_FIG = 4;     /* =log10(BASE)  */
static U_LONG BASE = 10000L;    /* Base value(value must be 10**BASE_FIG) */
                /* The value of BASE**2 + BASE must be represented */
                /* within one U_LONG. */
static U_LONG HALF_BASE = 5000L;/* =BASE/2  */
static S_LONG DBLE_FIG = 8;    /* figure of double */
static U_LONG BASE1 = 1000L;    /* =BASE/10  */

static Real *VpConstOne;    /* constant 1.0 */
static Real *VpPt5;        /* constant 0.5 */
static U_LONG maxnr = 100;    /* Maximum iterations for calcurating sqrt. */
                /* used in VpSqrt() */

/* ETC */
#define MemCmp(x,y,z) memcmp(x,y,z)
#define StrCmp(x,y)   strcmp(x,y)

static int VpIsDefOP(Real *c,Real *a,Real *b,int sw);
static int AddExponent(Real *a,S_INT n);
static U_LONG VpAddAbs(Real *a,Real *b,Real *c);
static U_LONG VpSubAbs(Real *a,Real *b,Real *c);
static U_LONG VpSetPTR(Real *a,Real *b,Real *c,U_LONG *a_pos,U_LONG *b_pos,U_LONG *c_pos,U_LONG *av,U_LONG *bv);
static int VpNmlz(Real *a);
static void VpFormatSt(char *psz,S_INT fFmt);
static int VpRdup(Real *m,U_LONG ind_m);

#ifdef _DEBUG
static int gnAlloc=0; /* Memory allocation counter */
#endif /* _DEBUG */

VP_EXPORT void *
VpMemAlloc(U_LONG mb)
{
    void *p = xmalloc((unsigned int)mb);
    if(!p) {
        VpException(VP_EXCEPTION_MEMORY,"failed to allocate memory",1);
    }
    memset(p,0,mb);
#ifdef _DEBUG
    gnAlloc++; /* Count allocation call */
#endif /* _DEBUG */
    return p;
}

VP_EXPORT void
VpFree(Real *pv)
{
    if(pv != NULL) {
        xfree(pv);
#ifdef _DEBUG
        gnAlloc--; /* Decrement allocation count */
        if(gnAlloc==0) {
            printf(" *************** All memories allocated freed ****************");
            getchar();
        }
        if(gnAlloc<0) {
            printf(" ??????????? Too many memory free calls(%d) ?????????????\n",gnAlloc);
            getchar();
        }
#endif /* _DEBUG */
    }
}

/*
 * EXCEPTION Handling.
 */
static unsigned short gfDoException = 0; /* Exception flag */

static unsigned short
VpGetException (void)
{
    return gfDoException;
}

static void
VpSetException(unsigned short f)
{
    gfDoException = f;
}

/* These 2 functions added at v1.1.7 */
VP_EXPORT U_LONG
VpGetPrecLimit(void)
{
    return gnPrecLimit;
}

VP_EXPORT U_LONG
VpSetPrecLimit(U_LONG n)
{
    U_LONG s = gnPrecLimit;
    gnPrecLimit = n;
    return s;
}

VP_EXPORT unsigned long
VpGetRoundMode(void)
{
    return gfRoundMode;
}

VP_EXPORT int
VpIsRoundMode(unsigned long n)
{
    if(n==VP_ROUND_UP      || n!=VP_ROUND_DOWN      ||
       n==VP_ROUND_HALF_UP || n!=VP_ROUND_HALF_DOWN ||
       n==VP_ROUND_CEIL    || n!=VP_ROUND_FLOOR     ||
       n==VP_ROUND_HALF_EVEN
      ) return 1;
    return 0;
}

VP_EXPORT unsigned long
VpSetRoundMode(unsigned long n)
{
    if(VpIsRoundMode(n)) gfRoundMode = n;
    return gfRoundMode;
}

/*
 *  0.0 & 1.0 generator
 *    These gZero_..... and gOne_..... can be any name
 *    referenced from nowhere except Zero() and One().
 *    gZero_..... and gOne_..... must have global scope
 *    (to let the compiler know they may be changed in outside
 *    (... but not actually..)).
 */
volatile double gZero_ABCED9B1_CE73__00400511F31D = 0.0;
volatile double gOne_ABCED9B4_CE73__00400511F31D  = 1.0;
static double
Zero(void)
{
    return gZero_ABCED9B1_CE73__00400511F31D;
}

static double
One(void)
{
    return gOne_ABCED9B4_CE73__00400511F31D;
}

VP_EXPORT U_LONG
VpBaseFig(void)
{
    return BASE_FIG;
}

VP_EXPORT U_LONG
VpDblFig(void)
{
    return DBLE_FIG;
}

VP_EXPORT U_LONG
VpBaseVal(void)
{
    return BASE;
}

/*
  ----------------------------------------------------------------
  Value of sign in Real structure is reserved for future use.
  short sign;
                    ==0 : NaN
                      1 : Positive zero
                     -1 : Negative zero
                      2 : Positive number
                     -2 : Negative number
                      3 : Positive infinite number
                     -3 : Negative infinite number
  ----------------------------------------------------------------
*/

VP_EXPORT double
VpGetDoubleNaN(void) /* Returns the value of NaN */
{
    static double fNaN = 0.0;
    if(fNaN==0.0) fNaN = Zero()/Zero();
    return fNaN;
}

VP_EXPORT double
VpGetDoublePosInf(void) /* Returns the value of +Infinity */
{
    static double fInf = 0.0;
    if(fInf==0.0) fInf = One()/Zero();
    return fInf;
}

VP_EXPORT double
VpGetDoubleNegInf(void) /* Returns the value of -Infinity */
{
    static double fInf = 0.0;
    if(fInf==0.0) fInf = -(One()/Zero());
    return fInf;
}

VP_EXPORT double
VpGetDoubleNegZero(void) /* Returns the value of -0 */
{
    static double nzero = 1000.0;
    if(nzero!=0.0) nzero = (One()/VpGetDoubleNegInf());
    return nzero;
}

VP_EXPORT int
VpIsNegDoubleZero(double v)
{
    double z = VpGetDoubleNegZero();
    return MemCmp(&v,&z,sizeof(v))==0;
}

VP_EXPORT int
VpException(unsigned short f, const char *str,int always)
{
    VALUE exc;
    int   fatal=0;

    if(f==VP_EXCEPTION_OP || f==VP_EXCEPTION_MEMORY) always = 1;

    if(always||(gfDoException&f)) {
        switch(f)
        {
        /*
        case VP_EXCEPTION_ZERODIVIDE:
        case VP_EXCEPTION_OVERFLOW:
        */
        case VP_EXCEPTION_INFINITY:
             exc = rb_eFloatDomainError;
             goto raise;
        case VP_EXCEPTION_NaN:
             exc = rb_eFloatDomainError;
             goto raise;
        case VP_EXCEPTION_UNDERFLOW:
             exc = rb_eFloatDomainError;
             goto raise;
        case VP_EXCEPTION_OP:
             exc = rb_eFloatDomainError;
             goto raise;
        case VP_EXCEPTION_MEMORY:
             fatal = 1;
             goto raise;
        default:
             fatal = 1;
             goto raise;
        }
    }
    return 0; /* 0 Means VpException() raised no exception */

raise:
    if(fatal) rb_fatal("%s", str);
    else   rb_raise(exc, "%s", str);
    return 0;
}

/* Throw exception or returns 0,when resulting c is Inf or NaN */
/*  sw=1:+ 2:- 3:* 4:/ */
static int
VpIsDefOP(Real *c,Real *a,Real *b,int sw)
{
    if(VpIsNaN(a) || VpIsNaN(b)) {
        /* at least a or b is NaN */
        VpSetNaN(c);
        goto NaN;
    }

    if(VpIsInf(a)) {
        if(VpIsInf(b)) {
            switch(sw)
            {
            case 1: /* + */
                if(VpGetSign(a)==VpGetSign(b)) {
                    VpSetInf(c,VpGetSign(a));
                    goto Inf;
                } else {
                    VpSetNaN(c);
                    goto NaN;
                }
            case 2: /* - */
                if(VpGetSign(a)!=VpGetSign(b)) {
                    VpSetInf(c,VpGetSign(a));
                    goto Inf;
                } else {
                    VpSetNaN(c);
                    goto NaN;
                }
                break;
            case 3: /* * */
                VpSetInf(c,VpGetSign(a)*VpGetSign(b));
                goto Inf;
                break;
            case 4: /* / */
                VpSetNaN(c);
                goto NaN;
            }
            VpSetNaN(c);
            goto NaN;
        }
        /* Inf op Finite */
        switch(sw)
        {
        case 1: /* + */
        case 2: /* - */
                VpSetInf(c,VpGetSign(a));
                break;
        case 3: /* * */
                if(VpIsZero(b)) {
                    VpSetNaN(c);
                    goto NaN;
                }
                VpSetInf(c,VpGetSign(a)*VpGetSign(b));
                break;
        case 4: /* / */
                VpSetInf(c,VpGetSign(a)*VpGetSign(b));
        }
        goto Inf;
    }

    if(VpIsInf(b)) {
        switch(sw)
        {
        case 1: /* + */
                VpSetInf(c,VpGetSign(b));
                break;
        case 2: /* - */
                VpSetInf(c,-VpGetSign(b));
                break;
        case 3: /* * */
                if(VpIsZero(a)) {
                    VpSetNaN(c);
                    goto NaN;
                }
                VpSetInf(c,VpGetSign(a)*VpGetSign(b));
                break;
        case 4: /* / */
                VpSetZero(c,VpGetSign(a)*VpGetSign(b));
        }
        goto Inf;
    }
    return 1; /* Results OK */

Inf:
    return VpException(VP_EXCEPTION_INFINITY,"Computation results to 'Infinity'",0);
NaN:
    return VpException(VP_EXCEPTION_NaN,"Computation results to 'NaN'",0);
}

/*
  ----------------------------------------------------------------
*/

/*
 *    returns number of chars needed to represent vp in specified format.
 */
VP_EXPORT U_LONG
VpNumOfChars(Real *vp,const char *pszFmt)
{
    S_INT  ex;
    U_LONG nc;

    if(vp == NULL)   return BASE_FIG*2+6;
    if(!VpIsDef(vp)) return 32; /* not sure,may be OK */

    switch(*pszFmt)
    {
    case 'F':
         nc = BASE_FIG*(vp->Prec + 1)+2;
         ex = vp->exponent;
         if(ex<0) {
             nc += BASE_FIG*(-ex);
         } else {
             if(ex > (S_INT)vp->Prec) {
                 nc += BASE_FIG*(ex - (S_INT)vp->Prec);
             }
         }
         break;
    case 'E':
    default:
         nc = BASE_FIG*(vp->Prec + 2)+6; /* 3: sign + exponent chars */
    }
    return nc;
}

/*
 * Initializer for Vp routines and constants used.
 * [Input]
 *   BaseVal: Base value(assigned to BASE) for Vp calculation.
 *   It must be the form BaseVal=10**n.(n=1,2,3,...)
 *   If Base <= 0L,then the BASE will be calcurated so
 *   that BASE is as large as possible satisfying the
 *   relation MaxVal <= BASE*(BASE+1). Where the value
 *   MaxVal is the largest value which can be represented
 *   by one U_LONG word(LONG) in the computer used.
 *
 * [Returns]
 * DBLE_FIG   ... OK
 */
VP_EXPORT U_LONG
VpInit(U_LONG BaseVal)
{
    U_LONG w;
    double v;

    /* Setup +/- Inf  NaN -0 */
    VpGetDoubleNaN();
    VpGetDoublePosInf();
    VpGetDoubleNegInf();
    VpGetDoubleNegZero();

    if(BaseVal <= 0) {
        /* Base <= 0, then determine Base by calcuration. */
        BASE = 1;
        while(
               (BASE > 0) &&
               ((w = BASE *(BASE + 1)) > BASE) &&((w / BASE) ==(BASE + 1))
            ) {
            BaseVal = BASE;
            BASE = BaseVal * 10L;
        }
    }
    /* Set Base Values */
    BASE = BaseVal;
    HALF_BASE = BASE / 2;
    BASE1 = BASE / 10;
    BASE_FIG = 0;
    while(BaseVal /= 10) ++BASE_FIG;
    /* Allocates Vp constants. */
    VpConstOne = VpAlloc((U_LONG)1, "1");
    VpPt5 = VpAlloc((U_LONG)1, ".5");

#ifdef _DEBUG
    gnAlloc = 0;
#endif /* _DEBUG */

    /* Determine # of digits available in one 'double'. */

    v = 1.0;
    DBLE_FIG = 0;
    while(v + 1.0 > 1.0) {
        ++DBLE_FIG;
        v /= 10;
    }

#ifdef _DEBUG
    if(gfDebug) {
        printf("VpInit: BaseVal   = %lu\n", BaseVal);
        printf("  BASE   = %lu\n", BASE);
        printf("  HALF_BASE = %lu\n", HALF_BASE);
        printf("  BASE1  = %lu\n", BASE1);
        printf("  BASE_FIG  = %lu\n", BASE_FIG);
        printf("  DBLE_FIG  = %lu\n", DBLE_FIG);
    }
#endif /* _DEBUG */

    return DBLE_FIG;
}

VP_EXPORT Real *
VpOne(void)
{
    return VpConstOne;
}

/* If exponent overflows,then raise exception or returns 0 */
static int
AddExponent(Real *a,S_INT n)
{
    S_INT e = a->exponent;
    S_INT m = e+n;
    S_INT eb,mb;
    if(e>0) {
        if(n>0) {
            mb = m*BASE_FIG;
            eb = e*BASE_FIG;
            if(mb<eb) goto overflow;
        }
    } else if(n<0) {
        mb = m*BASE_FIG;
        eb = e*BASE_FIG;
        if(mb>eb) goto underflow;
    }
    a->exponent = m;
    return 1;

/* Overflow/Underflow ==> Raise exception or returns 0 */
underflow:
    VpSetZero(a,VpGetSign(a));
    return VpException(VP_EXCEPTION_UNDERFLOW,"Exponent underflow",0);

overflow:
    VpSetInf(a,VpGetSign(a));
    return VpException(VP_EXCEPTION_OVERFLOW,"Exponent overflow",0);
}

/*
 * Allocates variable.
 * [Input]
 *   mx ... allocation unit, if zero then mx is determined by szVal.
 *    The mx is the number of effective digits can to be stored.
 *   szVal ... value assigned(char). If szVal==NULL,then zero is assumed.
 *            If szVal[0]=='#' then Max. Prec. will not be considered(1.1.7),
 *            full precision specified by szVal is allocated.
 *
 * [Returns]
 *   Pointer to the newly allocated variable, or
 *   NULL be returned if memory allocation is failed,or any error.
 */
VP_EXPORT Real *
VpAlloc(U_LONG mx, const char *szVal)
{
    U_LONG i, ni, ipn, ipf, nf, ipe, ne, nalloc;
    char v,*psz;
    int  sign=1;
    Real *vp = NULL;
    U_LONG mf = VpGetPrecLimit();

    mx = (mx + BASE_FIG - 1) / BASE_FIG + 1;    /* Determine allocation unit. */
    if(szVal) {
        while(ISSPACE(*szVal)) szVal++;
        if(*szVal!='#') {
             if(mf) {
                mf = (mf + BASE_FIG - 1) / BASE_FIG + 2; /* Needs 1 more for div */
                if(mx>mf) {
                    mx = mf;
                }
            }
        } else {
            ++szVal;
        }
    } else {
       /* necessary to be able to store */
       /* at least mx digits. */
       /* szVal==NULL ==> allocate zero value. */
       vp = (Real *) VpMemAlloc(sizeof(Real) + mx * sizeof(U_LONG));
       /* xmalloc() alway returns(or throw interruption) */
       vp->MaxPrec = mx;    /* set max precision */
       VpSetZero(vp,1);    /* initialize vp to zero. */
       return vp;
    }

    /* Skip all '_' after digit: 2006-6-30 */
    ni = 0;
    psz = ALLOCA_N(char,strlen(szVal)+1);
    i   = 0;
    ipn = 0;
    while(psz[i]=szVal[ipn]) {
        if(ISDIGIT(psz[i])) ++ni;
        if(psz[i]=='_') {
            if(ni>0) {ipn++;continue;}
            psz[i]=0;
            break;
        }
        ++i; ++ipn;
    }
    /* Skip trailing spaces */
    while((--i)>0) {
        if(ISSPACE(psz[i])) psz[i] = 0;
        else                break;
    }
    szVal = psz;

    /* Check on Inf & NaN */
    if(StrCmp(szVal,SZ_PINF)==0 ||
       StrCmp(szVal,SZ_INF)==0 ) {
        vp = (Real *) VpMemAlloc(sizeof(Real) + sizeof(U_LONG));
        vp->MaxPrec = 1;    /* set max precision */
        VpSetPosInf(vp);
        return vp;
    }
    if(StrCmp(szVal,SZ_NINF)==0) {
        vp = (Real *) VpMemAlloc(sizeof(Real) + sizeof(U_LONG));
        vp->MaxPrec = 1;    /* set max precision */
        VpSetNegInf(vp);
        return vp;
    }
    if(StrCmp(szVal,SZ_NaN)==0) {
        vp = (Real *) VpMemAlloc(sizeof(Real) + sizeof(U_LONG));
        vp->MaxPrec = 1;    /* set max precision */
        VpSetNaN(vp);
        return vp;
    }

    /* check on number szVal[] */
    ipn = i = 0;
    if     (szVal[i] == '-') {sign=-1;++i;}
    else if(szVal[i] == '+')          ++i;
    /* Skip digits */
    ni = 0;            /* digits in mantissa */
    while(v = szVal[i]) {
        if(!ISDIGIT(v)) break;
        ++i;
        ++ni;
    }
    nf  = 0;
    ipf = 0;
    ipe = 0;
    ne  = 0;
    if(v) {
        /* other than digit nor \0 */
        if(szVal[i] == '.') {    /* xxx. */
            ++i;
            ipf = i;
            while(v = szVal[i]) {    /* get fraction part. */
                if(!ISDIGIT(v)) break;
                ++i;
                ++nf;
            }
        }
        ipe = 0;        /* Exponent */

        switch(szVal[i]) {
        case '\0': break;
        case 'e':
        case 'E':
        case 'd':
        case 'D':
            ++i;
            ipe = i;
            v = szVal[i];
            if((v == '-') ||(v == '+')) ++i;
            while(v=szVal[i]) {
                if(!ISDIGIT(v)) break;
                ++i;
                ++ne;
            }
            break;
        default:
            break;
        }
    }
    nalloc =(ni + nf + BASE_FIG - 1) / BASE_FIG + 1;    /* set effective allocation  */
    /* units for szVal[]  */
    if(mx <= 0) mx = 1;
    nalloc = Max(nalloc, mx);
    mx = nalloc;
    vp =(Real *) VpMemAlloc(sizeof(Real) + mx * sizeof(U_LONG));
    /* xmalloc() alway returns(or throw interruption) */
    vp->MaxPrec = mx;        /* set max precision */
    VpSetZero(vp,sign);
    VpCtoV(vp, &(szVal[ipn]), ni, &(szVal[ipf]), nf, &(szVal[ipe]), ne);
    return vp;
}

/*
 * Assignment(c=a).
 * [Input]
 *   a   ... RHSV
 *   isw ... switch for assignment.
 *    c = a  when isw > 0
 *    c = -a when isw < 0
 *    if c->MaxPrec < a->Prec,then round operation
 *    will be performed.
 * [Output]
 *  c  ... LHSV
 */
VP_EXPORT int
VpAsgn(Real *c, Real *a, int isw)
{
    U_LONG n;
    if(VpIsNaN(a)) {
        VpSetNaN(c);
        return 0;
    }
    if(VpIsInf(a)) {
        VpSetInf(c,isw*VpGetSign(a));
        return 0;
    }

    /* check if the RHS is zero */
    if(!VpIsZero(a)) {
        c->exponent = a->exponent;    /* store  exponent */
        VpSetSign(c,(isw*VpGetSign(a)));    /* set sign */
        n =(a->Prec < c->MaxPrec) ?(a->Prec) :(c->MaxPrec);
        c->Prec = n;
        memcpy(c->frac, a->frac, n * sizeof(U_LONG));
        /* Needs round ? */
        if(isw!=10) {
            /* Not in ActiveRound */
            if(c->Prec < a->Prec) {
               VpInternalRound(c,n,(n>0)?a->frac[n-1]:0,a->frac[n]);
            } else {
               VpLimitRound(c,0);
            }
        }
    } else {
        /* The value of 'a' is zero.  */
        VpSetZero(c,isw*VpGetSign(a));
        return 1;
    }
    return c->Prec*BASE_FIG;
}

/*
 *   c = a + b  when operation =  1 or 2
 *  = a - b  when operation = -1 or -2.
 *   Returns number of significant digits of c
 */
VP_EXPORT int
VpAddSub(Real *c, Real *a, Real *b, int operation)
{
    S_INT sw, isw;
    Real *a_ptr, *b_ptr;
    U_LONG n, na, nb, i;
    U_LONG mrv;

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpAddSub(enter) a=% \n", a);
        VPrint(stdout, "     b=% \n", b);
        printf(" operation=%d\n", operation);
    }
#endif /* _DEBUG */

    if(!VpIsDefOP(c,a,b,(operation>0)?1:2)) return 0; /* No significant digits */

    /* check if a or b is zero  */
    if(VpIsZero(a)) {
        /* a is zero,then assign b to c */
        if(!VpIsZero(b)) {
            VpAsgn(c, b, operation);
        } else {
            /* Both a and b are zero. */
            if(VpGetSign(a)<0 && operation*VpGetSign(b)<0) {
                /* -0 -0 */
                VpSetZero(c,-1);
            } else {
                VpSetZero(c,1);
            }
            return 1; /* 0: 1 significant digits */
        }
        return c->Prec*BASE_FIG;
    }
    if(VpIsZero(b)) {
        /* b is zero,then assign a to c. */
        VpAsgn(c, a, 1);
        return c->Prec*BASE_FIG;
    }

    if(operation < 0) sw = -1;
    else              sw =  1;

    /* compare absolute value. As a result,|a_ptr|>=|b_ptr| */
    if(a->exponent > b->exponent) {
        a_ptr = a;
        b_ptr = b;
    }         /* |a|>|b| */
    else if(a->exponent < b->exponent) {
        a_ptr = b;
        b_ptr = a;
    }                /* |a|<|b| */
    else {
        /* Exponent part of a and b is the same,then compare fraction */
        /* part */
        na = a->Prec;
        nb = b->Prec;
        n = Min(na, nb);
        for(i=0;i < n; ++i) {
            if(a->frac[i] > b->frac[i]) {
                a_ptr = a;
                b_ptr = b;
                goto end_if;
            } else if(a->frac[i] < b->frac[i]) {
                a_ptr = b;
                b_ptr = a;
                goto end_if;
            }
        }
        if(na > nb) {
         a_ptr = a;
            b_ptr = b;
            goto end_if;
        } else if(na < nb) {
            a_ptr = b;
            b_ptr = a;
            goto end_if;
        }
        /* |a| == |b| */
        if(VpGetSign(a) + sw *VpGetSign(b) == 0) {
            VpSetZero(c,1);        /* abs(a)=abs(b) and operation = '-'  */
            return c->Prec*BASE_FIG;
        }
        a_ptr = a;
        b_ptr = b;
    }

end_if:
    isw = VpGetSign(a) + sw *VpGetSign(b);
    /*
     *  isw = 0 ...( 1)+(-1),( 1)-( 1),(-1)+(1),(-1)-(-1)
     *      = 2 ...( 1)+( 1),( 1)-(-1)
     *      =-2 ...(-1)+(-1),(-1)-( 1)
     *   If isw==0, then c =(Sign a_ptr)(|a_ptr|-|b_ptr|)
     *              else c =(Sign ofisw)(|a_ptr|+|b_ptr|)
    */
    if(isw) {            /* addition */
        VpSetSign(c,(S_INT)1);
        mrv = VpAddAbs(a_ptr, b_ptr, c);
        VpSetSign(c,isw / 2);
    } else {            /* subtraction */
        VpSetSign(c,(S_INT)1);
        mrv = VpSubAbs(a_ptr, b_ptr, c);
        if(a_ptr == a) {
            VpSetSign(c,VpGetSign(a));
        } else    {
            VpSetSign(c,VpGetSign(a_ptr) * sw);
        }
    }
    VpInternalRound(c,0,(c->Prec>0)?c->frac[c->Prec-1]:0,mrv);

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpAddSub(result) c=% \n", c);
        VPrint(stdout, "     a=% \n", a);
        VPrint(stdout, "     b=% \n", b);
        printf(" operation=%d\n", operation);
    }
#endif /* _DEBUG */
    return c->Prec*BASE_FIG;
}

/*
 * Addition of two variable precisional variables
 * a and b assuming abs(a)>abs(b).
 *   c = abs(a) + abs(b) ; where |a|>=|b|
 */
static U_LONG
VpAddAbs(Real *a, Real *b, Real *c)
{
    U_LONG word_shift;
    U_LONG carry;
    U_LONG ap;
    U_LONG bp;
    U_LONG cp;
    U_LONG a_pos;
    U_LONG b_pos;
    U_LONG c_pos;
    U_LONG av, bv, mrv;

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpAddAbs called: a = %\n", a);
        VPrint(stdout, "     b = %\n", b);
    }
#endif /* _DEBUG */

    word_shift = VpSetPTR(a, b, c, &ap, &bp, &cp, &av, &bv);
    a_pos = ap;
    b_pos = bp;
    c_pos = cp;
    if(word_shift==-1L) return 0; /* Overflow */
    if(b_pos == -1L) goto Assign_a;

    mrv = av + bv; /* Most right val. Used for round. */

    /* Just assign the last few digits of b to c because a has no  */
    /* corresponding digits to be added. */
    while(b_pos + word_shift > a_pos) {
        --c_pos;
        if(b_pos > 0) {
            c->frac[c_pos] = b->frac[--b_pos];
        } else {
            --word_shift;
            c->frac[c_pos] = 0;
        }
    }

    /* Just assign the last few digits of a to c because b has no */
    /* corresponding digits to be added. */
    bv = b_pos + word_shift;
    while(a_pos > bv) {
        c->frac[--c_pos] = a->frac[--a_pos];
    }
    carry = 0;    /* set first carry be zero */

    /* Now perform addition until every digits of b will be */
    /* exhausted. */
    while(b_pos > 0) {
        c->frac[--c_pos] = a->frac[--a_pos] + b->frac[--b_pos] + carry;
        if(c->frac[c_pos] >= BASE) {
            c->frac[c_pos] -= BASE;
            carry = 1;
        } else {
            carry = 0;
        }
    }

    /* Just assign the first few digits of a with considering */
    /* the carry obtained so far because b has been exhausted. */
    while(a_pos > 0) {
        c->frac[--c_pos] = a->frac[--a_pos] + carry;
        if(c->frac[c_pos] >= BASE) {
            c->frac[c_pos] -= BASE;
            carry = 1;
        } else {
            carry = 0;
        }
    }
    if(c_pos) c->frac[c_pos - 1] += carry;
    goto Exit;

Assign_a:
    VpAsgn(c, a, 1);
    mrv = 0;

Exit:

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpAddAbs exit: c=% \n", c);
    }
#endif /* _DEBUG */
    return mrv;
}

/*
 * c = abs(a) - abs(b)
 */
static U_LONG
VpSubAbs(Real *a, Real *b, Real *c)
{
    U_LONG word_shift;
    U_LONG mrv;
    U_LONG borrow;
    U_LONG ap;
    U_LONG bp;
    U_LONG cp;
    U_LONG a_pos;
    U_LONG b_pos;
    U_LONG c_pos;
    U_LONG av, bv;

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpSubAbs called: a = %\n", a);
        VPrint(stdout, "     b = %\n", b);
    }
#endif /* _DEBUG */

    word_shift = VpSetPTR(a, b, c, &ap, &bp, &cp, &av, &bv);
    a_pos = ap;
    b_pos = bp;
    c_pos = cp;
    if(word_shift==-1L) return 0; /* Overflow */
    if(b_pos == -1L) goto Assign_a;

    if(av >= bv) {
        mrv = av - bv;
        borrow = 0;
    } else {
        mrv    = 0;
        borrow = 1;
    }

    /* Just assign the values which are the BASE subtracted by   */
    /* each of the last few digits of the b because the a has no */
    /* corresponding digits to be subtracted. */
    if(b_pos + word_shift > a_pos) {
        while(b_pos + word_shift > a_pos) {
            --c_pos;
            if(b_pos > 0) {
                c->frac[c_pos] = BASE - b->frac[--b_pos] - borrow;
            } else {
                --word_shift;
                c->frac[c_pos] = BASE - borrow;
            }
            borrow = 1;
        }
    }
    /* Just assign the last few digits of a to c because b has no */
    /* corresponding digits to subtract. */

    bv = b_pos + word_shift;
    while(a_pos > bv) {
        c->frac[--c_pos] = a->frac[--a_pos];
    }

    /* Now perform subtraction until every digits of b will be */
    /* exhausted. */
    while(b_pos > 0) {
        --c_pos;
        if(a->frac[--a_pos] < b->frac[--b_pos] + borrow) {
            c->frac[c_pos] = BASE + a->frac[a_pos] - b->frac[b_pos] - borrow;
            borrow = 1;
        } else {
            c->frac[c_pos] = a->frac[a_pos] - b->frac[b_pos] - borrow;
            borrow = 0;
        }
    }

    /* Just assign the first few digits of a with considering */
    /* the borrow obtained so far because b has been exhausted. */
    while(a_pos > 0) {
        --c_pos;
        if(a->frac[--a_pos] < borrow) {
            c->frac[c_pos] = BASE + a->frac[a_pos] - borrow;
            borrow = 1;
        } else {
            c->frac[c_pos] = a->frac[a_pos] - borrow;
            borrow = 0;
        }
    }
    if(c_pos) c->frac[c_pos - 1] -= borrow;
    goto Exit;

Assign_a:
    VpAsgn(c, a, 1);
    mrv = 0;

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpSubAbs exit: c=% \n", c);
    }
#endif /* _DEBUG */
    return mrv;
}

/*
 * Note: If(av+bv)>= HALF_BASE,then 1 will be added to the least significant
 *    digit of c(In case of addition).
 * ------------------------- figure of output -----------------------------------
 *      a =  xxxxxxxxxxx
 *      b =    xxxxxxxxxx
 *      c =xxxxxxxxxxxxxxx
 *      word_shift =  |   |
 *      right_word =  |    | (Total digits in RHSV)
 *      left_word  = |   |   (Total digits in LHSV)
 *      a_pos      =    |
 *      b_pos      =     |
 *      c_pos      =      |
 */
static U_LONG
VpSetPTR(Real *a, Real *b, Real *c, U_LONG *a_pos, U_LONG *b_pos, U_LONG *c_pos, U_LONG *av, U_LONG *bv)
{
    U_LONG left_word, right_word, word_shift;
    c->frac[0] = 0;
    *av = *bv = 0;
    word_shift =((a->exponent) -(b->exponent));
    left_word = b->Prec + word_shift;
    right_word = Max((a->Prec),left_word);
    left_word =(c->MaxPrec) - 1;    /* -1 ... prepare for round up */
    /*
     * check if 'round' is needed.
     */
    if(right_word > left_word) {    /* round ? */
        /*---------------------------------
         *  Actual size of a = xxxxxxAxx
         *  Actual size of b = xxxBxxxxx
         *  Max. size of   c = xxxxxx
         *  Round off        =   |-----|
         *  c_pos            =   |
         *  right_word       =   |
         *  a_pos            =    |
         */
        *c_pos = right_word = left_word + 1;    /* Set resulting precision */
        /* be equal to that of c */
        if((a->Prec) >=(c->MaxPrec)) {
            /*
             *   a =  xxxxxxAxxx
             *   c =  xxxxxx
             *   a_pos =    |
             */
            *a_pos = left_word;
            *av = a->frac[*a_pos];    /* av is 'A' shown in above. */
        } else {
            /*
             *   a = xxxxxxx
             *   c = xxxxxxxxxx
             *  a_pos =     |
             */
            *a_pos = a->Prec;
        }
        if((b->Prec + word_shift) >= c->MaxPrec) {
            /*
             *   a = xxxxxxxxx
             *   b =  xxxxxxxBxxx
             *   c = xxxxxxxxxxx
             *  b_pos =   |
             */
            if(c->MaxPrec >=(word_shift + 1)) {
                *b_pos = c->MaxPrec - word_shift - 1;
                *bv = b->frac[*b_pos];
            } else {
                *b_pos = -1L;
            }
        } else {
            /*
             *   a = xxxxxxxxxxxxxxxx
             *   b =  xxxxxx
             *   c = xxxxxxxxxxxxx
             *  b_pos =     |
             */
            *b_pos = b->Prec;
        }
    } else {            /* The MaxPrec of c - 1 > The Prec of a + b  */
        /*
         *    a =   xxxxxxx
         *    b =   xxxxxx
         *    c = xxxxxxxxxxx
         *   c_pos =   |
         */
        *b_pos = b->Prec;
        *a_pos = a->Prec;
        *c_pos = right_word + 1;
    }
    c->Prec = *c_pos;
    c->exponent = a->exponent;
    if(!AddExponent(c,(S_LONG)1)) return (-1L);
    return word_shift;
}

/*
 * Return number og significant digits
 *       c = a * b , Where a = a0a1a2 ... an
 *             b = b0b1b2 ... bm
 *             c = c0c1c2 ... cl
 *          a0 a1 ... an   * bm
 *       a0 a1 ... an   * bm-1
 *         .   .    .
 *       .   .   .
 *        a0 a1 .... an    * b0
 *      +_____________________________
 *     c0 c1 c2  ......  cl
 *     nc      <---|
 *     MaxAB |--------------------|
 */
VP_EXPORT int
VpMult(Real *c, Real *a, Real *b)
{
    U_LONG MxIndA, MxIndB, MxIndAB, MxIndC;
    U_LONG ind_c, i, ii, nc;
    U_LONG ind_as, ind_ae, ind_bs, ind_be;
    U_LONG Carry, s;
    Real *w;

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpMult(Enter): a=% \n", a);
        VPrint(stdout, "      b=% \n", b);
    }
#endif /* _DEBUG */

    if(!VpIsDefOP(c,a,b,3)) return 0; /* No significant digit */

    if(VpIsZero(a) || VpIsZero(b)) {
        /* at least a or b is zero */
        VpSetZero(c,VpGetSign(a)*VpGetSign(b));
        return 1; /* 0: 1 significant digit */
    }

    if(VpIsOne(a)) {
        VpAsgn(c, b, VpGetSign(a));
        goto Exit;
    }
    if(VpIsOne(b)) {
        VpAsgn(c, a, VpGetSign(b));
        goto Exit;
    }
    if((b->Prec) >(a->Prec)) {
        /* Adjust so that digits(a)>digits(b) */
        w = a;
        a = b;
        b = w;
    }
    w = NULL;
    MxIndA = a->Prec - 1;
    MxIndB = b->Prec - 1;
    MxIndC = c->MaxPrec - 1;
    MxIndAB = a->Prec + b->Prec - 1;

    if(MxIndC < MxIndAB) {    /* The Max. prec. of c < Prec(a)+Prec(b) */
        w = c;
        c = VpAlloc((U_LONG)((MxIndAB + 1) * BASE_FIG), "#0");
        MxIndC = MxIndAB;
    }

    /* set LHSV c info */

    c->exponent = a->exponent;    /* set exponent */
    if(!AddExponent(c,b->exponent)) return 0;
    VpSetSign(c,VpGetSign(a)*VpGetSign(b));    /* set sign  */
    Carry = 0;
    nc = ind_c = MxIndAB;
    memset(c->frac, 0, (nc + 1) * sizeof(U_LONG));        /* Initialize c  */
    c->Prec = nc + 1;        /* set precision */
    for(nc = 0; nc < MxIndAB; ++nc, --ind_c) {
        if(nc < MxIndB) {    /* The left triangle of the Fig. */
            ind_as = MxIndA - nc;
            ind_ae = MxIndA;
            ind_bs = MxIndB;
            ind_be = MxIndB - nc;
        } else if(nc <= MxIndA) {    /* The middle rectangular of the Fig. */
            ind_as = MxIndA - nc;
            ind_ae = MxIndA -(nc - MxIndB);
            ind_bs = MxIndB;
            ind_be = 0;
        } else if(nc > MxIndA) {    /*  The right triangle of the Fig. */
            ind_as = 0;
            ind_ae = MxIndAB - nc - 1;
            ind_bs = MxIndB -(nc - MxIndA);
            ind_be = 0;
        }

        for(i = ind_as; i <= ind_ae; ++i) {
            s =((a->frac[i]) *(b->frac[ind_bs--]));
            Carry = s / BASE;
            s = s -(Carry * BASE);
            c->frac[ind_c] += s;
            if(c->frac[ind_c] >= BASE) {
                s = c->frac[ind_c] / BASE;
                Carry += s;
                c->frac[ind_c] -= (s * BASE);
            }
            if(Carry) {
                ii = ind_c;
                while((--ii) >= 0) {
                    c->frac[ii] += Carry;
                    if(c->frac[ii] >= BASE) {
                        Carry = c->frac[ii] / BASE;
                        c->frac[ii] -=(Carry * BASE);
                    } else {
                        break;
                    }
                }
            }
        }
    }
    if(w != NULL) {        /* free work variable */
        VpNmlz(c);
        VpAsgn(w, c, 1);
        VpFree(c);
        c = w;
    } else {
        VpLimitRound(c,0);
    }

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpMult(c=a*b): c=% \n", c);
        VPrint(stdout, "      a=% \n", a);
        VPrint(stdout, "      b=% \n", b);
    }
#endif /*_DEBUG */
    return c->Prec*BASE_FIG;
}

/*
 *   c = a / b,  remainder = r
 */
VP_EXPORT int
VpDivd(Real *c, Real *r, Real *a, Real *b)
{
    U_LONG word_a, word_b, word_c, word_r;
    U_LONG i, n, ind_a, ind_b, ind_c, ind_r;
    U_LONG nLoop;
    U_LONG q, b1, b1p1, b1b2, b1b2p1, r1r2;
    U_LONG borrow, borrow1, borrow2, qb;

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, " VpDivd(c=a/b)  a=% \n", a);
        VPrint(stdout, "    b=% \n", b);
    }
#endif /*_DEBUG */

    VpSetNaN(r);
    if(!VpIsDefOP(c,a,b,4)) goto Exit;
    if(VpIsZero(a)&&VpIsZero(b)) {
        VpSetNaN(c);
        return VpException(VP_EXCEPTION_NaN,"(VpDivd) 0/0 not defined(NaN)",0);
    }
    if(VpIsZero(b)) {
        VpSetInf(c,VpGetSign(a)*VpGetSign(b));
        return VpException(VP_EXCEPTION_ZERODIVIDE,"(VpDivd) Divide by zero",0);
    }
    if(VpIsZero(a)) {
        /* numerator a is zero  */
        VpSetZero(c,VpGetSign(a)*VpGetSign(b));
        VpSetZero(r,VpGetSign(a)*VpGetSign(b));
        goto Exit;
    }
    if(VpIsOne(b)) {
        /* divide by one  */
        VpAsgn(c, a, VpGetSign(b));
        VpSetZero(r,VpGetSign(a));
        goto Exit;
    }

    word_a = a->Prec;
    word_b = b->Prec;
    word_c = c->MaxPrec;
    word_r = r->MaxPrec;

    ind_c = 0;
    ind_r = 1;

    if(word_a >= word_r) goto space_error;

    r->frac[0] = 0;
    while(ind_r <= word_a) {
        r->frac[ind_r] = a->frac[ind_r - 1];
        ++ind_r;
    }

    while(ind_r < word_r) r->frac[ind_r++] = 0;
    while(ind_c < word_c) c->frac[ind_c++] = 0;

    /* initial procedure */
    b1 = b1p1 = b->frac[0];
    if(b->Prec <= 1) {
        b1b2p1 = b1b2 = b1p1 * BASE;
    } else {
        b1p1 = b1 + 1;
        b1b2p1 = b1b2 = b1 * BASE + b->frac[1];
        if(b->Prec > 2) ++b1b2p1;
    }

    /* */
    /* loop start */
    ind_c = word_r - 1;
    nLoop = Min(word_c,ind_c);
    ind_c = 1;
    while(ind_c < nLoop) {
        if(r->frac[ind_c] == 0) {
            ++ind_c;
            continue;
        }
        r1r2 = r->frac[ind_c] * BASE + r->frac[ind_c + 1];
        if(r1r2 == b1b2) {
            /* The first two word digits is the same */
            ind_b = 2;
            ind_a = ind_c + 2;
            while(ind_b < word_b) {
                if(r->frac[ind_a] < b->frac[ind_b]) goto div_b1p1;
                if(r->frac[ind_a] > b->frac[ind_b]) break;
                ++ind_a;
                ++ind_b;
            }
            /* The first few word digits of r and b is the same and */
            /* the first different word digit of w is greater than that */
            /* of b, so quotinet is 1 and just subtract b from r. */
            borrow = 0;        /* quotient=1, then just r-b */
            ind_b = b->Prec - 1;
            ind_r = ind_c + ind_b;
            if(ind_r >= word_r) goto space_error;
            n = ind_b;
            for(i = 0; i <= n; ++i) {
                if(r->frac[ind_r] < b->frac[ind_b] + borrow) {
                    r->frac[ind_r] +=(BASE -(b->frac[ind_b] + borrow));
                    borrow = 1;
                } else {
                    r->frac[ind_r] = r->frac[ind_r] - b->frac[ind_b] - borrow;
                    borrow = 0;
                }
                --ind_r;
                --ind_b;
            }
            ++(c->frac[ind_c]);
            goto carry;
        }
        /* The first two word digits is not the same, */
        /* then compare magnitude, and divide actually. */
        if(r1r2 >= b1b2p1) {
            q = r1r2 / b1b2p1;
            c->frac[ind_c] += q;
            ind_r = b->Prec + ind_c - 1;
            goto sub_mult;
        }

div_b1p1:
        if(ind_c + 1 >= word_c) goto out_side;
        q = r1r2 / b1p1;
        c->frac[ind_c + 1] += q;
        ind_r = b->Prec + ind_c;

sub_mult:
        borrow1 = borrow2 = 0;
        ind_b = word_b - 1;
        if(ind_r >= word_r) goto space_error;
        n = ind_b;
        for(i = 0; i <= n; ++i) {
            /* now, perform r = r - q * b */
            qb = q *(b->frac[ind_b]);
            if(qb < BASE) borrow1 = 0;
            else {
                borrow1 = qb / BASE;
                qb = qb - borrow1 * BASE;
            }
            if(r->frac[ind_r] < qb) {
                r->frac[ind_r] +=(BASE - qb);
                borrow2 = borrow2 + borrow1 + 1;
            } else {
                r->frac[ind_r] -= qb;
                borrow2 += borrow1;
            }
            if(borrow2) {
                if(r->frac[ind_r - 1] < borrow2) {
                    r->frac[ind_r - 1] +=(BASE - borrow2);
                    borrow2 = 1;
                } else {
                    r->frac[ind_r - 1] -= borrow2;
                    borrow2 = 0;
                }
            }
            --ind_r;
            --ind_b;
        }

        r->frac[ind_r] -= borrow2;
carry:
        ind_r = ind_c;
        while(c->frac[ind_r] >= BASE) {
            c->frac[ind_r] -= BASE;
            --ind_r;
            ++(c->frac[ind_r]);
        }
    }
    /* End of operation, now final arrangement */
out_side:
    c->Prec = word_c;
    c->exponent = a->exponent;
    if(!AddExponent(c,(S_LONG)2))   return 0;
    if(!AddExponent(c,-(b->exponent))) return 0;

    VpSetSign(c,VpGetSign(a)*VpGetSign(b));
    VpNmlz(c);            /* normalize c */
    r->Prec = word_r;
    r->exponent = a->exponent;
    if(!AddExponent(r,(S_LONG)1)) return 0;
    VpSetSign(r,VpGetSign(a));
    VpNmlz(r);            /* normalize r(remainder) */
    goto Exit;

space_error:
#ifdef _DEBUG
    if(gfDebug) {
        printf("   word_a=%lu\n", word_a);
        printf("   word_b=%lu\n", word_b);
        printf("   word_c=%lu\n", word_c);
        printf("   word_r=%lu\n", word_r);
        printf("   ind_r =%lu\n", ind_r);
    }
#endif /* _DEBUG */
    rb_bug("ERROR(VpDivd): space for remainder too small.");

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, " VpDivd(c=a/b), c=% \n", c);
        VPrint(stdout, "    r=% \n", r);
    }
#endif /* _DEBUG */
    return c->Prec*BASE_FIG;
}

/*
 *  Input  a = 00000xxxxxxxx En(5 preceeding zeros)
 *  Output a = xxxxxxxx En-5
 */
static int
VpNmlz(Real *a)
{
    U_LONG ind_a, i;

    if(!VpIsDef(a)) goto NoVal;
    if(VpIsZero(a)) goto NoVal;

    ind_a = a->Prec;
    while(ind_a--) {
        if(a->frac[ind_a]) {
            a->Prec = ind_a + 1;
            i = 0;
            while(a->frac[i] == 0) ++i;        /* skip the first few zeros */
            if(i) {
                a->Prec -= i;
                if(!AddExponent(a,-((S_INT)i))) return 0;
                memmove(&(a->frac[0]),&(a->frac[i]),(a->Prec)*sizeof(U_LONG));
            }
            return 1;
        }
    }
    /* a is zero(no non-zero digit) */
    VpSetZero(a,VpGetSign(a));
    return 0;

NoVal:
    a->frac[0] = 0;
    a->Prec=1;
    return 0;
}

/*
 *  VpComp = 0  ... if a=b,
 *   Pos  ... a>b,
 *   Neg  ... a<b.
 *   999  ... result undefined(NaN)
 */
VP_EXPORT int
VpComp(Real *a, Real *b)
{
    int val;
    U_LONG mx, ind;
    int e;
    val = 0;
    if(VpIsNaN(a)||VpIsNaN(b)) return 999;
    if(!VpIsDef(a)) {
        if(!VpIsDef(b)) e = a->sign - b->sign;
        else             e = a->sign;
        if(e>0)   return  1;
        else if(e<0) return -1;
        else   return  0;
    }
    if(!VpIsDef(b)) {
        e = -b->sign;
        if(e>0) return  1;
        else return -1;
    }
    /* Zero check */
    if(VpIsZero(a)) {
        if(VpIsZero(b))      return 0; /* both zero */
        val = -VpGetSign(b);
        goto Exit;
    }
    if(VpIsZero(b)) {
        val = VpGetSign(a);
        goto Exit;
    }

    /* compare sign */
    if(VpGetSign(a) > VpGetSign(b)) {
        val = 1;        /* a>b */
        goto Exit;
    }
    if(VpGetSign(a) < VpGetSign(b)) {
        val = -1;        /* a<b */
        goto Exit;
    }

    /* a and b have same sign, && signe!=0,then compare exponent */
    if((a->exponent) >(b->exponent)) {
        val = VpGetSign(a);
        goto Exit;
    }
    if((a->exponent) <(b->exponent)) {
        val = -VpGetSign(b);
        goto Exit;
    }

    /* a and b have same exponent, then compare significand. */
    mx =((a->Prec) <(b->Prec)) ?(a->Prec) :(b->Prec);
    ind = 0;
    while(ind < mx) {
        if((a->frac[ind]) >(b->frac[ind])) {
            val = VpGetSign(a);
         goto Exit;
        }
        if((a->frac[ind]) <(b->frac[ind])) {
            val = -VpGetSign(b);
            goto Exit;
        }
        ++ind;
    }
    if((a->Prec) >(b->Prec)) {
        val = VpGetSign(a);
    } else if((a->Prec) <(b->Prec)) {
        val = -VpGetSign(b);
    }

Exit:
    if  (val> 1) val =  1;
    else if(val<-1) val = -1;

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, " VpComp a=%\n", a);
        VPrint(stdout, "  b=%\n", b);
        printf("  ans=%d\n", val);
    }
#endif /* _DEBUG */
    return (int)val;
}

#ifdef _DEBUG
/*
 *    cntl_chr ... ASCIIZ Character, print control characters
 *     Available control codes:
 *      %  ... VP variable. To print '%', use '%%'.
 *      \n ... new line
 *      \b ... backspace
 *           ... tab
 *     Note: % must must not appear more than once
 *    a  ... VP variable to be printed
 */
VP_EXPORT int
VPrint(FILE *fp, char *cntl_chr, Real *a)
{
    U_LONG i, j, nc, nd, ZeroSup;
    U_LONG n, m, e, nn;

    /* Check if NaN & Inf. */
    if(VpIsNaN(a)) {
        fprintf(fp,SZ_NaN);
        return 8;
    }
    if(VpIsPosInf(a)) {
        fprintf(fp,SZ_INF);
        return 8;
    }
    if(VpIsNegInf(a)) {
        fprintf(fp,SZ_NINF);
        return 9;
    }
    if(VpIsZero(a)) {
        fprintf(fp,"0.0");
        return 3;
    }

    j = 0;
    nd = nc = 0;        /*  nd : number of digits in fraction part(every 10 digits, */
    /*    nd<=10). */
    /*  nc : number of caracters printed  */
    ZeroSup = 1;        /* Flag not to print the leading zeros as 0.00xxxxEnn */
    while(*(cntl_chr + j)) {
        if((*(cntl_chr + j) == '%') &&(*(cntl_chr + j + 1) != '%')) {
         nc = 0;
         if(!VpIsZero(a)) {
                if(VpGetSign(a) < 0) {
                    fprintf(fp, "-");
                    ++nc;
                }
                nc += fprintf(fp, "0.");
                n = a->Prec;
                for(i=0;i < n;++i) {
                 m = BASE1;
                    e = a->frac[i];
                    while(m) {
                        nn = e / m;
                        if((!ZeroSup) || nn) {
                            nc += fprintf(fp, "%lu", nn);    /* The reading zero(s) */
                            /* as 0.00xx will not */
                            /* be printed. */
                            ++nd;
                            ZeroSup = 0;    /* Set to print succeeding zeros */
                        }
                        if(nd >= 10) {    /* print ' ' after every 10 digits */
                            nd = 0;
                            nc += fprintf(fp, " ");
                        }
                        e = e - nn * m;
                        m /= 10;
                    }
                }
                nc += fprintf(fp, "E%ld", VpExponent10(a));
            } else {
                nc += fprintf(fp, "0.0");
            }
        } else {
            ++nc;
            if(*(cntl_chr + j) == '\\') {
                switch(*(cntl_chr + j + 1)) {
                case 'n':
                    fprintf(fp, "\n");
                    ++j;
                    break;
                case 't':
                    fprintf(fp, "\t");
                    ++j;
                 break;
                case 'b':
                    fprintf(fp, "\n");
                    ++j;
                    break;
                default:
                    fprintf(fp, "%c", *(cntl_chr + j));
                    break;
                }
            } else {
                fprintf(fp, "%c", *(cntl_chr + j));
                if(*(cntl_chr + j) == '%') ++j;
            }
        }
        j++;
    }
    return (int)nc;
}
#endif /* _DEBUG */

static void
VpFormatSt(char *psz,S_INT fFmt)
{
    U_LONG ie;
    U_LONG i;
    S_INT nf = 0;
    char ch;

    if(fFmt<=0) return;

    ie = strlen(psz);
    for(i = 0; i < ie; ++i) {
        ch = psz[i];
        if(!ch) break;
        if(ISSPACE(ch) || ch=='-' || ch=='+') continue;
        if(ch == '.')                { nf = 0;continue;}
        if(ch == 'E') break;
        nf++;
        if(nf > fFmt) {
            memmove(psz + i + 1, psz + i, ie - i + 1);
            ++ie;
            nf = 0;
            psz[i] = ' ';
        }
    }
}

VP_EXPORT S_LONG
VpExponent10(Real *a)
{
    S_LONG ex;
    U_LONG n;

    if(!VpHasVal(a)) return 0;

    ex =(a->exponent) * BASE_FIG;
    n = BASE1;
    while((a->frac[0] / n) == 0) {
         --ex;
         n /= 10;
    }
    return ex;
}

VP_EXPORT void
VpSzMantissa(Real *a,char *psz)
{
    U_LONG i, ZeroSup;
    U_LONG n, m, e, nn;

    if(VpIsNaN(a)) {
        sprintf(psz,SZ_NaN);
        return;
    }
    if(VpIsPosInf(a)) {
        sprintf(psz,SZ_INF);
        return;
    }
    if(VpIsNegInf(a)) {
        sprintf(psz,SZ_NINF);
        return;
    }

    ZeroSup = 1;        /* Flag not to print the leading zeros as 0.00xxxxEnn */
    if(!VpIsZero(a)) {
        if(VpGetSign(a) < 0) *psz++ = '-';
        n = a->Prec;
        for(i=0;i < n;++i) {
            m = BASE1;
            e = a->frac[i];
            while(m) {
                nn = e / m;
                if((!ZeroSup) || nn) {
                    sprintf(psz, "%lu", nn);    /* The reading zero(s) */
                    psz += strlen(psz);
                    /* as 0.00xx will be ignored. */
                    ZeroSup = 0;    /* Set to print succeeding zeros */
                }
                e = e - nn * m;
                m /= 10;
            }
        }
        *psz = 0;
        while(psz[-1]=='0') *(--psz) = 0;
    } else {
        if(VpIsPosZero(a)) sprintf(psz, "0");
        else      sprintf(psz, "-0");
    }
}

VP_EXPORT int
VpToSpecialString(Real *a,char *psz,int fPlus)
/* fPlus =0:default, =1: set ' ' before digits , =2: set '+' before digits. */
{
    if(VpIsNaN(a)) {
        sprintf(psz,SZ_NaN);
        return 1;
    }

    if(VpIsPosInf(a)) {
        if(fPlus==1) {
           *psz++ = ' ';
        } else if(fPlus==2) {
           *psz++ = '+';
        }
        sprintf(psz,SZ_INF);
        return 1;
    }
    if(VpIsNegInf(a)) {
        sprintf(psz,SZ_NINF);
        return 1;
    }
    if(VpIsZero(a)) {
        if(VpIsPosZero(a)) {
            if(fPlus==1)      sprintf(psz, " 0.0");
            else if(fPlus==2) sprintf(psz, "+0.0");
            else              sprintf(psz, "0.0");
        } else    sprintf(psz, "-0.0");
        return 1;
    }
    return 0;
}

VP_EXPORT void
VpToString(Real *a,char *psz,int fFmt,int fPlus)
/* fPlus =0:default, =1: set ' ' before digits , =2:set '+' before digits. */
{
    U_LONG i, ZeroSup;
    U_LONG n, m, e, nn;
    char *pszSav = psz;
    S_LONG ex;

    if(VpToSpecialString(a,psz,fPlus)) return;

    ZeroSup = 1;    /* Flag not to print the leading zeros as 0.00xxxxEnn */

    if(VpGetSign(a) < 0) *psz++ = '-';
    else if(fPlus==1)    *psz++ = ' ';
    else if(fPlus==2)    *psz++ = '+';

    *psz++ = '0';
    *psz++ = '.';
    n = a->Prec;
    for(i=0;i < n;++i) {
        m = BASE1;
        e = a->frac[i];
        while(m) {
            nn = e / m;
            if((!ZeroSup) || nn) {
                sprintf(psz, "%lu", nn);    /* The reading zero(s) */
                psz += strlen(psz);
                /* as 0.00xx will be ignored. */
                ZeroSup = 0;    /* Set to print succeeding zeros */
            }
            e = e - nn * m;
            m /= 10;
        }
    }
    ex =(a->exponent) * BASE_FIG;
    n = BASE1;
    while((a->frac[0] / n) == 0) {
        --ex;
        n /= 10;
    }
    while(psz[-1]=='0') *(--psz) = 0;
    sprintf(psz, "E%ld", ex);
    if(fFmt) VpFormatSt(pszSav, fFmt);
}

VP_EXPORT void
VpToFString(Real *a,char *psz,int fFmt,int fPlus)
/* fPlus =0:default,=1: set ' ' before digits ,set '+' before digits. */
{
    U_LONG i;
    U_LONG n, m, e, nn;
    char *pszSav = psz;
    S_LONG ex;

    if(VpToSpecialString(a,psz,fPlus)) return;

    if(VpGetSign(a) < 0) *psz++ = '-';
    else if(fPlus==1)    *psz++ = ' ';
    else if(fPlus==2)    *psz++ = '+';

    n  = a->Prec;
    ex = a->exponent;
    if(ex<=0) {
       *psz++ = '0';*psz++ = '.';
       while(ex<0) {
          for(i=0;i<BASE_FIG;++i) *psz++ = '0';
          ++ex;
       }
       ex = -1;
    }

    for(i=0;i < n;++i) {
       --ex;
       if(i==0 && ex >= 0) {
           sprintf(psz, "%lu", a->frac[i]);
           psz += strlen(psz);
       } else {
           m = BASE1;
           e = a->frac[i];
           while(m) {
               nn = e / m;
               *psz++ = (char)(nn + '0');
               e = e - nn * m;
               m /= 10;
           }
       }
       if(ex == 0) *psz++ = '.';
    }
    while(--ex>=0) {
       m = BASE;
       while(m/=10) *psz++ = '0';
       if(ex == 0) *psz++ = '.';
    }
    *psz = 0;
    while(psz[-1]=='0') *(--psz) = 0;
    if(psz[-1]=='.') sprintf(psz, "0");
    if(fFmt) VpFormatSt(pszSav, fFmt);
}

/*
 *  [Output]
 *   a[]  ... variable to be assigned the value.
 *  [Input]
 *   int_chr[]  ... integer part(may include '+/-').
 *   ni   ... number of characters in int_chr[],not including '+/-'.
 *   frac[]  ... fraction part.
 *   nf   ... number of characters in frac[].
 *   exp_chr[]  ... exponent part(including '+/-').
 *   ne   ... number of characters in exp_chr[],not including '+/-'.
 */
VP_EXPORT int
VpCtoV(Real *a, const char *int_chr, U_LONG ni, const char *frac, U_LONG nf, const char *exp_chr, U_LONG ne)
{
    U_LONG i, j, ind_a, ma, mi, me;
    U_LONG loc;
    S_INT  e,es, eb, ef;
    S_INT  sign, signe;
    /* get exponent part */
    e = 0;
    ma = a->MaxPrec;
    mi = ni;
    me = ne;
    signe = 1;
    memset(a->frac, 0, ma * sizeof(U_LONG));
    if(ne > 0) {
        i = 0;
        if(exp_chr[0] == '-') {
            signe = -1;
            ++i;
            ++me;
        } else if(exp_chr[0] == '+') {
            ++i;
            ++me;
        }
        while(i < me) {
            es = e*((S_INT)BASE_FIG);
            e = e * 10 + exp_chr[i] - '0';
            if(es>e*((S_INT)BASE_FIG)) {
                return VpException(VP_EXCEPTION_INFINITY,"exponent overflow",0);
            }
            ++i;
        }
    }

    /* get integer part */
    i = 0;
    sign = 1;
    if(ni >= 0) {
        if(int_chr[0] == '-') {
            sign = -1;
            ++i;
            ++mi;
        } else if(int_chr[0] == '+') {
            ++i;
            ++mi;
        }
    }

    e = signe * e;        /* e: The value of exponent part. */
    e = e + ni;        /* set actual exponent size. */

    if(e > 0)    signe = 1;
    else        signe = -1;

    /* Adjust the exponent so that it is the multiple of BASE_FIG. */
    j = 0;
    ef = 1;
    while(ef) {
        if(e>=0) eb =  e;
        else  eb = -e;
        ef = eb / ((S_INT)BASE_FIG);
        ef = eb - ef * ((S_INT)BASE_FIG);
        if(ef) {
            ++j;        /* Means to add one more preceeding zero */
            ++e;
        }
    }

    eb = e / ((S_INT)BASE_FIG);

    ind_a = 0;
    while(i < mi) {
        a->frac[ind_a] = 0;
        while((j < (U_LONG)BASE_FIG) &&(i < mi)) {
            a->frac[ind_a] = a->frac[ind_a] * 10 + int_chr[i] - '0';
            ++j;
            ++i;
        }
        if(i < mi) {
            ++ind_a;
            if(ind_a >= ma) goto over_flow;
            j = 0;
        }
    }
    loc = 1;

    /* get fraction part */

    i = 0;
    while(i < nf) {
        while((j < (U_LONG)BASE_FIG) &&(i < nf)) {
            a->frac[ind_a] = a->frac[ind_a] * 10 + frac[i] - '0';
            ++j;
            ++i;
        }
        if(i < nf) {
            ++ind_a;
            if(ind_a >= ma) goto over_flow;
            j = 0;
        }
    }
    goto Final;

over_flow:
    rb_warn("Conversion from String to BigDecimal overflow (last few digits discarded).");

Final:
    if(ind_a >= ma) ind_a = ma - 1;
    while(j < (U_LONG)BASE_FIG) {
        a->frac[ind_a] = a->frac[ind_a] * 10;
        ++j;
    }
    a->Prec = ind_a + 1;
    a->exponent = eb;
    VpSetSign(a,sign);
    VpNmlz(a);
    return 1;
}

/*
 * [Input]
 *   *m  ... Real
 * [Output]
 *   *d  ... fraction part of m(d = 0.xxxxxxx). where # of 'x's is fig.
 *   *e  ... U_LONG,exponent of m.
 * DBLE_FIG ... Number of digits in a double variable.
 *
 *  m -> d*10**e, 0<d<BASE
 * [Returns]
 *   0 ... Zero
 *   1 ... Normal
 *   2 ... Infinity
 *  -1 ... NaN
 */
VP_EXPORT int
VpVtoD(double *d, S_LONG *e, Real *m)
{
    U_LONG ind_m, mm, fig;
    double div;
    int    f = 1;

    if(VpIsNaN(m)) {
        *d = VpGetDoubleNaN();
        *e = 0;
        f = -1; /* NaN */
        goto Exit;
    } else
    if(VpIsPosZero(m)) {
        *d = 0.0;
        *e = 0;
        f  = 0;
        goto Exit;
    } else
    if(VpIsNegZero(m)) {
        *d = VpGetDoubleNegZero();
        *e = 0;
        f  = 0;
        goto Exit;
    } else
    if(VpIsPosInf(m)) {
        *d = VpGetDoublePosInf();
        *e = 0;
        f  = 2;
        goto Exit;
    } else
    if(VpIsNegInf(m)) {
        *d = VpGetDoubleNegInf();
        *e = 0;
        f  = 2;
        goto Exit;
    }
    /* Normal number */
    fig =(DBLE_FIG + BASE_FIG - 1) / BASE_FIG;
    ind_m = 0;
    mm = Min(fig,(m->Prec));
    *d = 0.0;
    div = 1.;
    while(ind_m < mm) {
        div /=(double)((S_INT)BASE);
        *d = *d +((double) ((S_INT)m->frac[ind_m++])) * div;
    }
    *e = m->exponent * ((S_INT)BASE_FIG);
    *d *= VpGetSign(m);

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, " VpVtoD: m=%\n", m);
        printf("   d=%e * 10 **%ld\n", *d, *e);
        printf("   DBLE_FIG = %ld\n", DBLE_FIG);
    }
#endif /*_DEBUG */
    return f;
}

/*
 * m <- d
 */
VP_EXPORT void
VpDtoV(Real *m, double d)
{
    U_LONG i, ind_m, mm;
    U_LONG ne;
    double  val, val2;

    if(isnan(d)) {
        VpSetNaN(m);
        goto Exit;
    }
    if(isinf(d)) {
        if(d>0.0) VpSetPosInf(m);
        else   VpSetNegInf(m);
        goto Exit;
    }

    if(d == 0.0) {
        VpSetZero(m,1);
        goto Exit;
    }
    val =(d > 0.) ? d :(-d);
    ne = 0;
    if(val >= 1.0) {
        while(val >= 1.0) {
            val /=(double)((S_INT)BASE);
            ++ne;
        }
    } else {
        val2 = 1.0 /(double)((S_INT)BASE);
        while(val < val2) {
            val *=(double)((S_INT)BASE);
            --ne;
        }
    }
    /* Now val = 0.xxxxx*BASE**ne */

    mm = m->MaxPrec;
    memset(m->frac, 0, mm * sizeof(U_LONG));
    for(ind_m = 0;val > 0.0 && ind_m < mm;ind_m++) {
        val *=(double)((S_INT)BASE);
        i =(U_LONG) val;
        val -=(double)((S_INT)i);
        m->frac[ind_m] = i;
    }
    if(ind_m >= mm) ind_m = mm - 1;
    if(d > 0.0) {
        VpSetSign(m, (S_INT)1);
    } else {
        VpSetSign(m,-(S_INT)1);
    }
    m->Prec = ind_m + 1;
    m->exponent = ne;

    VpInternalRound(m,0,(m->Prec>0)?m->frac[m->Prec-1]:0,
                      (U_LONG)(val*((double)((S_INT)BASE))));

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        printf("VpDtoV d=%30.30e\n", d);
        VPrint(stdout, "  m=%\n", m);
    }
#endif /* _DEBUG */
    return;
}

/*
 *  m <- ival
 */
VP_EXPORT void
VpItoV(Real *m, S_INT ival)
{
    U_LONG mm, ind_m;
    U_LONG val, v1, v2, v;
    int isign;
    S_INT ne;

    if(ival == 0) {
        VpSetZero(m,1);
        goto Exit;
    }
    isign = 1;
    val = ival;
    if(ival < 0) {
        isign = -1;
        val =(U_LONG)(-ival);
    }
    ne = 0;
    ind_m = 0;
    mm = m->MaxPrec;
    while(ind_m < mm) {
        m->frac[ind_m] = 0;
        ++ind_m;
    }
    ind_m = 0;
    while(val > 0) {
        if(val) {
         v1 = val;
         v2 = 1;
            while(v1 >= BASE) {
                v1 /= BASE;
                v2 *= BASE;
            }
            val = val - v2 * v1;
            v = v1;
        } else {
            v = 0;
        }
        m->frac[ind_m] = v;
        ++ind_m;
        ++ne;
    }
    m->Prec = ind_m - 1;
    m->exponent = ne;
    VpSetSign(m,isign);
    VpNmlz(m);

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        printf(" VpItoV i=%d\n", ival);
        VPrint(stdout, "  m=%\n", m);
    }
#endif /* _DEBUG */
    return;
}

/*
 * y = SQRT(x),  y*y - x =>0
 */
VP_EXPORT int
VpSqrt(Real *y, Real *x)
{
    Real *f = NULL;
    Real *r = NULL;
    S_LONG y_prec, f_prec;
    S_LONG n;
    S_LONG e;
    S_LONG prec;
    S_LONG nr;
    double val;

    /* Zero, NaN or Infinity ? */
    if(!VpHasVal(x)) {
        if(VpIsZero(x)||VpGetSign(x)>0) {
            VpAsgn(y,x,1);
            goto Exit;
        }
        VpSetNaN(y);
        return VpException(VP_EXCEPTION_OP,"(VpSqrt) SQRT(NaN or negative value)",0);
        goto Exit;
    }

     /* Negative ? */
    if(VpGetSign(x) < 0) {
        VpSetNaN(y);
        return VpException(VP_EXCEPTION_OP,"(VpSqrt) SQRT(negative value)",0);
    }

    /* One ? */
    if(VpIsOne(x)) {
        VpSetOne(y);
        goto Exit;
    }

    n = (S_LONG)y->MaxPrec;
    if((S_LONG)x->MaxPrec > n) n = (S_LONG)x->MaxPrec;
    /* allocate temporally variables  */
    f = VpAlloc(y->MaxPrec *(BASE_FIG + 2), "#1");
    r = VpAlloc((n + n) *(BASE_FIG + 2), "#1");

    nr = 0;
    y_prec = (S_LONG)y->MaxPrec;
    f_prec = (S_LONG)f->MaxPrec;

    prec = x->exponent;
    if(prec > 0)    ++prec;
    else            --prec;
    prec = prec - (S_LONG)y->MaxPrec;
    VpVtoD(&val, &e, x);    /* val <- x  */
    e /= ((S_LONG)BASE_FIG);
    n = e / 2;
    if(e - n * 2 != 0) {
        val /=(double)((S_INT)BASE);
        n =(e + 1) / 2;
    }
    VpDtoV(y, sqrt(val));    /* y <- sqrt(val) */
    y->exponent += n;
    n = (DBLE_FIG + BASE_FIG - 1) / BASE_FIG;
    y->MaxPrec = (U_LONG)Min(n , y_prec);
    f->MaxPrec = y->MaxPrec + 1;
    n = y_prec*((S_LONG)BASE_FIG);
    if((U_LONG)n<maxnr) n = (U_LONG)maxnr;
    do {
        y->MaxPrec *= 2;
        if(y->MaxPrec > (U_LONG)y_prec) y->MaxPrec = (U_LONG)y_prec;
        f->MaxPrec = y->MaxPrec;
        VpDivd(f, r, x, y);     /* f = x/y    */
        VpAddSub(r, f, y, -1);  /* r = f - y  */
        VpMult(f, VpPt5, r);    /* f = 0.5*r  */
        if(VpIsZero(f))         goto converge;
        VpAddSub(r, f, y, 1);   /* r = y + f  */
        VpAsgn(y, r, 1);        /* y = r      */
        if(f->exponent <= prec) goto converge;
    } while(++nr < n);
    /* */
#ifdef _DEBUG
    if(gfDebug) {
        printf("ERROR(VpSqrt): did not converge within %ld iterations.\n",
            nr);
    }
#endif /* _DEBUG */
    y->MaxPrec = y_prec;

converge:
    VpChangeSign(y,(S_INT)1);
#ifdef _DEBUG
    if(gfDebug) {
        VpMult(r, y, y);
        VpAddSub(f, x, r, -1);
        printf("VpSqrt: iterations = %lu\n", nr);
        VPrint(stdout, "  y =% \n", y);
        VPrint(stdout, "  x =% \n", x);
        VPrint(stdout, "  x-y*y = % \n", f);
    }
#endif /* _DEBUG */
    y->MaxPrec = y_prec;

Exit:
    VpFree(f);
    VpFree(r);
    return 1;
}

/*
 *
 * f = 0: Round off/Truncate, 1: round up, 2:ceil, 3: floor, 4: Banker's rounding
 * nf: digit position for operation.
 *
 */
VP_EXPORT int
VpMidRound(Real *y, int f, int nf)
/*
 * Round reletively from the decimal point.
 *    f: rounding mode
 *   nf: digit location to round from the the decimal point.
 */
{
    /* fracf: any positive digit under rounding position? */
    /* exptoadd: number of digits needed to compensate negative nf */
    int n,i,ix,ioffset,fracf,exptoadd;
    U_LONG v,shifter;
    U_LONG div;

    nf += y->exponent*((int)BASE_FIG);
    exptoadd=0;
    if (nf < 0) {
        exptoadd = -nf;
        nf = 0;
    }
    /* ix: x->fraq[ix] contains round position */
    ix = nf/(int)BASE_FIG;
    if(((U_LONG)ix)>=y->Prec) return 0; /* Unable to round */
    ioffset = nf - ix*((int)BASE_FIG);

    v = y->frac[ix];
    /* drop digits after pointed digit */
    n = BASE_FIG - ioffset - 1;
    for(shifter=1,i=0;i<n;++i) shifter *= 10;
    fracf = (v%(shifter*10) > 0);
    v /= shifter;
    div = v/10;
    v = v - div*10;
    if (fracf == 0) {
        for(i=ix+1;i<y->Prec;i++) {
            if (y->frac[i]%BASE) {
                fracf = 1;
                break;
            }
        }
    }
    memset(y->frac+ix+1, 0, (y->Prec - (ix+1)) * sizeof(U_LONG));
    switch(f) {
    case VP_ROUND_DOWN: /* Truncate */
         break;
    case VP_ROUND_UP:   /* Roundup */
        if(fracf) ++div;
         break;
    case VP_ROUND_HALF_UP:   /* Round half up  */
        if(v>=5) ++div;
        break;
    case VP_ROUND_HALF_DOWN: /* Round half down  */
        if(v>=6) ++div;
        break;
    case VP_ROUND_CEIL: /* ceil */
        if(fracf && (VpGetSign(y)>0)) ++div;
        break;
    case VP_ROUND_FLOOR: /* floor */
        if(fracf && (VpGetSign(y)<0)) ++div;
        break;
    case VP_ROUND_HALF_EVEN: /* Banker's rounding */
        if(v>5) ++div;
        else if(v==5) {
            if((U_LONG)i==(BASE_FIG-1)) {
                if(ix && (y->frac[ix-1]%2)) ++div;
            } else {
                if(div%2) ++div;
            }
        }
        break;
    }
    for(i=0;i<=n;++i) div *= 10;
    if(div>=BASE) {
        if(ix) {
            y->frac[ix] = 0;
            VpRdup(y,ix);
        } else {
            S_INT s = VpGetSign(y);
            int e = y->exponent;
            VpSetOne(y);
            VpSetSign(y,s);
            y->exponent = e+1;
        }
    } else {
        y->frac[ix] = div;
        VpNmlz(y);
    }
    if (exptoadd > 0) {
        y->exponent += exptoadd/BASE_FIG;
        exptoadd %= BASE_FIG;
        for(i=0;i<exptoadd;i++) {
            y->frac[0] *= 10;
            if (y->frac[0] >= BASE) {
                y->frac[0] /= BASE;
                y->exponent++;
            }
        }
    }
    return 1;
}

VP_EXPORT int
VpLeftRound(Real *y, int f, int nf)
/*
 * Round from the left hand side of the digits.
 */
{
    U_LONG v;
    if(!VpHasVal(y)) return 0; /* Unable to round */
    v = y->frac[0];
    nf -= VpExponent(y)*BASE_FIG;
    while(v=v/10) nf--;
    nf += (BASE_FIG-1);
    return VpMidRound(y,f,nf);
}

VP_EXPORT int 
VpActiveRound(Real *y, Real *x, int f, int nf)
{
    /* First,assign whole value in truncation mode */
    if(VpAsgn(y, x, 10)<=1) return 0; /* Zero,NaN,or Infinity */
    return VpMidRound(y,f,nf);
}

static int
VpLimitRound(Real *c,U_LONG ixDigit)
{
    U_LONG ix = VpGetPrecLimit();
    if(!VpNmlz(c))    return -1;
    if(!ix)           return 0;
    if(!ixDigit) ixDigit = c->Prec-1;
    if((ix+BASE_FIG-1)/BASE_FIG > ixDigit+1) return 0;
    return VpLeftRound(c,VpGetRoundMode(),ix);
}

static void 
VpInternalRound(Real *c,int ixDigit,U_LONG vPrev,U_LONG v)
{
    int f = 0;

    if(VpLimitRound(c,ixDigit)) return;
    if(!v)                      return;

    v /= BASE1;
    switch(gfRoundMode) {
    case VP_ROUND_DOWN:
        break;
    case VP_ROUND_UP:
        if(v)                    f = 1;
        break;
    case VP_ROUND_HALF_UP:
        if(v >= 5)               f = 1;
        break;
    case VP_ROUND_HALF_DOWN:
        if(v >= 6)               f = 1;
        break;
    case VP_ROUND_CEIL:  /* ceil */
        if(v && (VpGetSign(c)>0)) f = 1;
        break;
    case VP_ROUND_FLOOR: /* floor */
        if(v && (VpGetSign(c)<0)) f = 1;
        break;
    case VP_ROUND_HALF_EVEN:  /* Banker's rounding */
        if(v>5) f = 1;
        else if(v==5 && vPrev%2)  f = 1;
        break;
    }
    if(f) {
        VpRdup(c,ixDigit);    /* round up */
        VpNmlz(c);
    }
}

/*
 *  Rounds up m(plus one to final digit of m).
 */
static int
VpRdup(Real *m,U_LONG ind_m)
{
    U_LONG carry;

    if(!ind_m) ind_m = m->Prec;

    carry = 1;
    while(carry > 0 && (ind_m--)) {
        m->frac[ind_m] += carry;
        if(m->frac[ind_m] >= BASE) m->frac[ind_m] -= BASE;
        else                       carry = 0;
    }
    if(carry > 0) {        /* Overflow,count exponent and set fraction part be 1  */
        if(!AddExponent(m,(S_LONG)1)) return 0;
        m->Prec = m->frac[0] = 1;
    } else {
        VpNmlz(m);
    }
    return 1;
}

/*
 *  y = x - fix(x)
 */
VP_EXPORT void
VpFrac(Real *y, Real *x)
{
    U_LONG my, ind_y, ind_x;

    if(!VpHasVal(x)) {
        VpAsgn(y,x,1);
        goto Exit;
    }

    if(x->exponent > 0 && (U_LONG)x->exponent >= x->Prec) {
        VpSetZero(y,VpGetSign(x));
        goto Exit;
    } else if(x->exponent <= 0) {
        VpAsgn(y, x, 1);
        goto Exit;
    }

    y->Prec = x->Prec -(U_LONG) x->exponent;
    y->Prec = Min(y->Prec, y->MaxPrec);
    y->exponent = 0;
    VpSetSign(y,VpGetSign(x));
    ind_y = 0;
    my = y->Prec;
    ind_x = x->exponent;
    while(ind_y < my) {
        y->frac[ind_y] = x->frac[ind_x];
        ++ind_y;
        ++ind_x;
    }
    VpNmlz(y);

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpFrac y=%\n", y);
        VPrint(stdout, "    x=%\n", x);
    }
#endif /* _DEBUG */
    return;
}

/*
 *   y = x ** n
 */
VP_EXPORT int
VpPower(Real *y, Real *x, S_INT n)
{
    U_LONG s, ss;
    S_LONG sign;
    Real *w1 = NULL;
    Real *w2 = NULL;

    if(VpIsZero(x)) {
        if(n==0) {
           VpSetOne(y);
           goto Exit;
        }
        sign = VpGetSign(x);
        if(n<0) {
           n = -n;
           if(sign<0) sign = (n%2)?(-1):(1);
           VpSetInf (y,sign);
        } else {
           if(sign<0) sign = (n%2)?(-1):(1);
           VpSetZero(y,sign);
        }
        goto Exit;
    }
    if(!VpIsDef(x)) {
        VpSetNaN(y); /* Not sure !!! */
        goto Exit;
    }

    if((x->exponent == 1) &&(x->Prec == 1) &&(x->frac[0] == 1)) {
        /* abs(x) = 1 */
        VpSetOne(y);
        if(VpGetSign(x) > 0) goto Exit;
        if((n % 2) == 0) goto Exit;
        VpSetSign(y,-(S_INT)1);
        goto Exit;
    }

    if(n > 0) sign = 1;
    else if(n < 0) {
        sign = -1;
        n = -n;
    } else {
        VpSetOne(y);
        goto Exit;
    }

    /* Allocate working variables  */

    w1 = VpAlloc((y->MaxPrec + 2) * BASE_FIG, "#0");
    w2 = VpAlloc((w1->MaxPrec * 2 + 1) * BASE_FIG, "#0");
    /* calculation start */

    VpAsgn(y, x, 1);
    --n;
    while(n > 0) {
        VpAsgn(w1, x, 1);
        s = 1;
loop1:  ss = s;
        s += s;
        if(s >(U_LONG) n) goto out_loop1;
        VpMult(w2, w1, w1);
        VpAsgn(w1, w2, 1);
        goto loop1;
out_loop1:
        n -= ss;
        VpMult(w2, y, w1);
        VpAsgn(y, w2, 1);
    }
    if(sign < 0) {
        VpDivd(w1, w2, VpConstOne, y);
        VpAsgn(y, w1, 1);
    }

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpPower y=%\n", y);
        VPrint(stdout, "VpPower x=%\n", x);
        printf("  n=%d\n", n);
    }
#endif /* _DEBUG */
    VpFree(w2);
    VpFree(w1);
    return 1;
}

#ifdef _DEBUG
int
VpVarCheck(Real * v)
/*
 * Checks the validity of the Real variable v.
 * [Input]
 *   v ... Real *, variable to be checked.
 * [Returns]
 *   0  ... correct v.
 *   other ... error
 */
{
    U_LONG i;

    if(v->MaxPrec <= 0) {
        printf("ERROR(VpVarCheck): Illegal Max. Precision(=%lu)\n",
            v->MaxPrec);
        return 1;
    }
    if((v->Prec <= 0) ||((v->Prec) >(v->MaxPrec))) {
        printf("ERROR(VpVarCheck): Illegal Precision(=%lu)\n", v->Prec);
        printf("       Max. Prec.=%lu\n", v->MaxPrec);
        return 2;
    }
    for(i = 0; i < v->Prec; ++i) {
        if((v->frac[i] >= BASE)) {
            printf("ERROR(VpVarCheck): Illegal fraction\n");
            printf("       Frac[%ld]=%lu\n", i, v->frac[i]);
            printf("       Prec.   =%lu\n", v->Prec);
            printf("       Exp. =%d\n", v->exponent);
            printf("       BASE =%lu\n", BASE);
            return 3;
        }
    }
    return 0;
}
#endif /* _DEBUG */
