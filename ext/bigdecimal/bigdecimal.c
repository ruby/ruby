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
 * NOTES:
 *  For the notes other than listed bellow,see ruby CVS log.
 *  2003-04-17
 *    Bug in negative.exp(n) reported by Hitoshi Miyazaki fixed.
 *  2003-03-28
 *    V1.0 checked in to CVS(ruby/ext/bigdecimal).
 *    use rb_str2cstr() instead of STR2CSTR().
 *  2003-01-03
 *    assign instead of asign(by knu),use string.h functions(by t.saito).
 *  2002-12-06
 *    The sqrt() bug reported by Bret Jolly fixed.
 *  2002-5-6
 *    The bug reported by Sako Hiroshi (ruby-list:34988) in to_i fixed.
 *  2002-4-17
 *    methods prec and double_fig(class method) added(S.K).
 *  2002-04-04
 *    Copied from BigFloat 1.1.9 and
 *      hash method changed according to the suggestion from Akinori MUSHA <knu@iDaemons.org>.
 *      All ! class methods deactivated(but not actually removed).
 *      to_s and to_s2 merged to one to_s[(n)].
 *
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <float.h>
#include <math.h>
#include "ruby.h"
#include "math.h"
#include "version.h"
 
/* #define ENABLE_NUMERIC_STRING */
/* #define ENABLE_TRIAL_METHOD   */

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
static ID coerce;

/*
 *  **** BigDecimal version ****
 */
static VALUE
BigDecimal_version(VALUE self)
{
    return rb_str_new2("1.0.0");
}

/*
 *   VP routines used in BigDecimal part 
 */
static unsigned short VpGetException(void);
static void  VpSetException(unsigned short f);
static int VpInternalRound(Real *c,int ixDigit,U_LONG vPrev,U_LONG v);

/*
 *  **** BigDecimal part ****
 */
/* Following functions borrowed from numeric.c */
static VALUE
coerce_body(VALUE *x)
{
    return rb_funcall(x[1], coerce, 1, x[0]);
}

static VALUE
coerce_rescue(VALUE *x)
{
    rb_raise(rb_eTypeError, "%s can't be coerced into %s",
        rb_special_const_p(x[1])?
        rb_str2cstr(rb_inspect(x[1]),0):
        rb_class2name(CLASS_OF(x[1])),
        rb_class2name(CLASS_OF(x[0])));
    return (VALUE)0;
}

static void
do_coerce(VALUE *x, VALUE *y)
{
    VALUE ary;
    VALUE a[2];
    a[0] = *x; a[1] = *y;
    ary = rb_rescue(coerce_body, (VALUE)a, coerce_rescue, (VALUE)a);
    if (TYPE(ary) != T_ARRAY || RARRAY(ary)->len != 2) {
        rb_raise(rb_eTypeError, "coerce must return [x, y]");
    }
    *x = RARRAY(ary)->ptr[0];
    *y = RARRAY(ary)->ptr[1];
}

static VALUE
DoSomeOne(VALUE x, VALUE y)
{
    do_coerce(&x, &y);
    return rb_funcall(x, rb_frame_last_func(), 1, y);
}

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
        sprintf(szD, "%d", FIX2INT(v));
        return VpCreateRbObject(VpBaseFig() * 2 + 1, szD);

#ifdef ENABLE_NUMERIC_STRING
    case T_STRING:
        SafeStringValue(v);
        return VpCreateRbObject(strlen(RSTRING(v)->ptr) + VpBaseFig() + 1,
                                RSTRING(v)->ptr);
#endif /* ENABLE_NUMERIC_STRING */

    case T_BIGNUM:
        bg = rb_big2str(v, 10);
        return VpCreateRbObject(strlen(RSTRING(bg)->ptr) + VpBaseFig() + 1,
                                RSTRING(bg)->ptr);
    default:
        goto SomeOneMayDoIt;
    }

SomeOneMayDoIt:
    if(must) {
        rb_raise(rb_eTypeError, "%s can't be coerced into BigDecimal",
                    rb_special_const_p(v)?
                    rb_str2cstr(rb_inspect(v),0):
                    rb_class2name(CLASS_OF(v))
                );
    }
    return NULL; /* NULL means to coerce */
}

static VALUE
BigDecimal_double_fig(VALUE self)
{
    return INT2FIX(VpDblFig());
}

static VALUE
BigDecimal_prec(VALUE self)
{
    ENTER(1);
    Real *p;
    VALUE obj;

    GUARD_OBJ(p,GetVpValue(self,1));
    obj = rb_ary_new();
    obj = rb_ary_push(obj,INT2NUM(p->Prec*VpBaseFig()));
    obj = rb_ary_push(obj,INT2NUM(p->MaxPrec*VpBaseFig()));
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
    psz = ALLOCA_N(char,(unsigned int)VpNumOfChars(vp)+strlen(sz));
    sprintf(psz,"%s",sz);
    VpToString(vp, psz+strlen(psz), 0);
    return rb_str_new2(psz);
}

static VALUE
BigDecimal_load(VALUE self, VALUE str)
{
    ENTER(2);
    Real *pv;
    unsigned char *pch;
    unsigned char ch;
    unsigned long m=0;

    SafeStringValue(str);
    pch = RSTRING(str)->ptr;
    /* First get max prec */
    while((*pch)!=(unsigned char)'\0' && (ch=*pch++)!=(unsigned char)':') {
        if(!ISDIGIT(ch)) {
            rb_raise(rb_eTypeError, "Load failed: invalid character in the marshaled string");
        }
        m = m*10 + (unsigned long)(ch-'0');
    }
    if(m>VpBaseFig()) m -= VpBaseFig();
    GUARD_OBJ(pv,VpNewRbClass(m,pch,self));
    m /= VpBaseFig();
    if(m && pv->MaxPrec>m) pv->MaxPrec = m+1;
    return ToValue(pv);
}

static VALUE
BigDecimal_mode(VALUE self, VALUE which, VALUE val)
{
    unsigned long f,fo;
 
    if(TYPE(which)!=T_FIXNUM)     return Qnil;
    f = (unsigned long)FIX2INT(which);

	if(f&VP_EXCEPTION_ALL) {
        /* Exception mode setting */
        fo = VpGetException();
        if(val!=Qfalse && val!=Qtrue) return Qnil;
        if(f&VP_EXCEPTION_INFINITY) {
            VpSetException((unsigned short)((val==Qtrue)?(fo|VP_EXCEPTION_INFINITY):
                           (fo&(~VP_EXCEPTION_INFINITY))));
        }
        if(f&VP_EXCEPTION_NaN) {
            VpSetException((unsigned short)((val==Qtrue)?(fo|VP_EXCEPTION_NaN):
                           (fo&(~VP_EXCEPTION_NaN))));
        }
        return INT2FIX(fo);
    }
    if(VP_ROUND_MODE==f) {
        /* Rounding mode setting */
        if(TYPE(val)!=T_FIXNUM)     return Qnil;
        fo = VpSetRoundMode((unsigned long)FIX2INT(val));
        return INT2FIX(fo);
    }
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
    if(n <= 0) {
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
VpCreateRbObject(U_LONG mx, char *str)
{
    Real *pv = VpAlloc(mx,str);
    pv->obj = (VALUE)Data_Wrap_Struct(rb_cBigDecimal, 0, BigDecimal_delete, pv);
    return pv;
}


static VALUE
BigDecimal_IsNaN(VALUE self)
{
    Real *p = GetVpValue(self,1);
    if(VpIsNaN(p))  return Qtrue;
    return Qfalse;
}

static VALUE
BigDecimal_IsInfinite(VALUE self)
{
    Real *p = GetVpValue(self,1);
    if(VpIsPosInf(p)) return INT2FIX(1);
    if(VpIsNegInf(p)) return INT2FIX(-1);
    return Qnil;
}

static VALUE
BigDecimal_IsFinite(VALUE self)
{
    Real *p = GetVpValue(self,1);
    if(VpIsNaN(p)) return Qfalse;
    if(VpIsInf(p)) return Qfalse;
    return Qtrue;
}

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
       VpException(VP_EXCEPTION_OVERFLOW,"BigDecimal to Float conversion.",0);
       if(d>0.0) return rb_float_new(DBL_MAX);
       else      return rb_float_new(-DBL_MAX);
    }
    return rb_float_new(d*d2);
}

static VALUE
BigDecimal_coerce(VALUE self, VALUE other)
{
    ENTER(2);
    VALUE obj;
    Real *b;
    if(TYPE(other) == T_FLOAT) {
       obj = rb_ary_new();
       obj = rb_ary_push(obj,other);
       obj = rb_ary_push(obj,BigDecimal_to_f(self));
    } else {
       GUARD_OBJ(b,GetVpValue(other,1));
       obj = rb_ary_new();
       obj = rb_ary_push(obj, b->obj);
       obj = rb_ary_push(obj, self);
    }
    return obj;
}

static VALUE
BigDecimal_uplus(VALUE self)
{
    return self;
}

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

static S_INT
BigDecimalCmp(VALUE self, VALUE r)
{
    ENTER(5);
    Real *a, *b;
    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return DoSomeOne(self,r);
    SAVE(b);
    return VpComp(a, b);
}

static VALUE
BigDecimal_zero(VALUE self)
{
    Real *a = GetVpValue(self,1);
    return VpIsZero(a) ? Qtrue : Qfalse;
}

static VALUE
BigDecimal_nonzero(VALUE self)
{
    Real *a = GetVpValue(self,1);
    return VpIsZero(a) ? Qnil : self;
}

static VALUE
BigDecimal_comp(VALUE self, VALUE r)
{
    S_INT e;
    e = BigDecimalCmp(self, r);
    if(e==999) return rb_float_new(VpGetDoubleNaN());
    return INT2FIX(e);
}

static VALUE
BigDecimal_eq(VALUE self, VALUE r)
{
    ENTER(5);
    Real *a, *b;
    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return Qfalse; /* Not comparable */
    SAVE(b);
    return VpComp(a, b)? Qfalse:Qtrue;
}

static VALUE
BigDecimal_ne(VALUE self, VALUE r)
{
    ENTER(5);
    Real *a, *b;
    GUARD_OBJ(a,GetVpValue(self,1));
    b = GetVpValue(r,0);
    if(!b) return Qtrue; /* Not comparable */
    SAVE(b);
    return VpComp(a, b) ? Qtrue : Qfalse;
}

static VALUE
BigDecimal_lt(VALUE self, VALUE r)
{
    S_INT e;
    e = BigDecimalCmp(self, r);
    if(e==999) return Qfalse;
    return(e < 0) ? Qtrue : Qfalse;
}

static VALUE
BigDecimal_le(VALUE self, VALUE r)
{
    S_INT e;
    e = BigDecimalCmp(self, r);
    if(e==999) return Qfalse;
    return(e <= 0) ? Qtrue : Qfalse;
}

static VALUE
BigDecimal_gt(VALUE self, VALUE r)
{
    S_INT e;
    e = BigDecimalCmp(self, r);
    if(e==999) return Qfalse;
    return(e > 0) ? Qtrue : Qfalse;
}

static VALUE
BigDecimal_ge(VALUE self, VALUE r)
{
    S_INT e;
    e = BigDecimalCmp(self, r);
    if(e==999) return Qfalse;
    return(e >= 0) ? Qtrue : Qfalse;
}

static VALUE
BigDecimal_neg(VALUE self, VALUE r)
{
    ENTER(5);
    Real *c, *a;
    GUARD_OBJ(a,GetVpValue(self,1));
    GUARD_OBJ(c,VpCreateRbObject(a->Prec *(VpBaseFig() + 1), "0"));
    VpAsgn(c, a, -1);
    return ToValue(c);
}

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
    GUARD_OBJ((*c),VpCreateRbObject(mx, "0"));
    GUARD_OBJ((*res),VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
    VpDivd(*c, *res, a, b);
    return (VALUE)0;
}

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
    if(VpIsDef(c) && (!VpIsZero(c))) {
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

static VALUE
BigDecimal_remainder(VALUE self, VALUE r) /* remainder */
{
    VALUE  f;
    Real  *d,*rv;
    f = BigDecimal_divremain(self,r,&d,&rv);
    if(f!=(VALUE)0) return f;
    return ToValue(rv);
}

static VALUE
BigDecimal_divmod(VALUE self, VALUE r)
{
    ENTER(5);
    VALUE obj;
    Real *div=NULL, *mod=NULL;

    obj = BigDecimal_DoDivmod(self,r,&div,&mod);
    if(obj!=(VALUE)0) return obj;
    SAVE(div);SAVE(mod);
    obj = rb_ary_new();
    rb_ary_push(obj, ToValue(div));
    rb_ary_push(obj, ToValue(mod));
    return obj;
}

static VALUE
BigDecimal_div2(int argc, VALUE *argv, VALUE self)
{
    ENTER(10);
    VALUE obj;
    VALUE b,n;
    int na = rb_scan_args(argc,argv,"11",&b,&n);
    if(na==1) { /* div in Float sense */
       Real *div=NULL;
       Real *mod;
       obj = BigDecimal_DoDivmod(self,b,&div,&mod);
       if(obj!=(VALUE)0) return obj;
       return ToValue(div);
    } else {    /* div in BigDecimal sense */
       Real *res=NULL;
       Real *av=NULL, *bv=NULL, *cv=NULL;
       U_LONG ix = (U_LONG)GetPositiveInt(n);
       U_LONG mx = (ix+VpBaseFig()*2);
       GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
       GUARD_OBJ(av,GetVpValue(self,1));
       GUARD_OBJ(bv,GetVpValue(b,1));
       mx = cv->MaxPrec+1;
       GUARD_OBJ(res,VpCreateRbObject((mx * 2 + 2)*VpBaseFig(), "#0"));
       VpDivd(cv,res,av,bv);
       VpLeftRound(cv,VpGetRoundMode(),ix);
       return ToValue(cv);
    }
}

static VALUE
BigDecimal_add2(VALUE self, VALUE b, VALUE n)
{
    ENTER(2);
    Real   *cv;
    U_LONG mx = (U_LONG)GetPositiveInt(n);
    VALUE   c = BigDecimal_add(self,b);
    GUARD_OBJ(cv,GetVpValue(c,1));
    VpLeftRound(cv,VpGetRoundMode(),mx);
    return ToValue(cv);
}

static VALUE
BigDecimal_sub2(VALUE self, VALUE b, VALUE n)
{
    ENTER(2);
    Real *cv;
    U_LONG mx = (U_LONG)GetPositiveInt(n);
    VALUE   c = BigDecimal_sub(self,b);
    GUARD_OBJ(cv,GetVpValue(c,1));
    VpLeftRound(cv,VpGetRoundMode(),mx);
    return ToValue(cv);
}

static VALUE
BigDecimal_mult2(VALUE self, VALUE b, VALUE n)
{
    ENTER(2);
    Real *cv;
    U_LONG mx = (U_LONG)GetPositiveInt(n);
    VALUE   c = BigDecimal_mult(self,b);
    GUARD_OBJ(cv,GetVpValue(c,1));
    VpLeftRound(cv,VpGetRoundMode(),mx);
    return ToValue(cv);
}

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

static VALUE
BigDecimal_sqrt(VALUE self, VALUE nFig)
{
    ENTER(5);
    Real *c, *a;
    S_INT mx, n;

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    mx *= 2;

    n = GetPositiveInt(nFig) + VpBaseFig() + 1;
    if(mx <= n) mx = n;
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpSqrt(c, a);
    return ToValue(c);
}

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

static VALUE
BigDecimal_round(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real   *c, *a;
    int    iLoc;
    U_LONG mx;
    VALUE  vLoc;
    VALUE  vRound;

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
    case 2:{
        int sws = sw;
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
        Check_Type(vRound, T_FIXNUM);
        sw = VpSetRoundMode(FIX2INT(vRound));
        VpSetRoundMode(sws);
        }
        break;
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpActiveRound(c,a,sw,iLoc);
    return ToValue(c);
}

static VALUE
BigDecimal_truncate(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *c, *a;
    int iLoc;
    U_LONG mx;
    VALUE vLoc;

    if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
        iLoc = 0;
    } else {
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpActiveRound(c,a,VP_ROUND_DOWN,iLoc); /* 0: truncate */
    return ToValue(c);
}

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

static VALUE
BigDecimal_floor(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;
    int iLoc;
    VALUE vLoc;

    if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
        iLoc = 0;
    } else {
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpActiveRound(c,a,VP_ROUND_FLOOR,iLoc);
    return ToValue(c);
}

static VALUE
BigDecimal_ceil(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *c, *a;
    U_LONG mx;
    int iLoc;
    VALUE vLoc;

    if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
        iLoc = 0;
    } else {
        Check_Type(vLoc, T_FIXNUM);
        iLoc = FIX2INT(vLoc);
    }

    GUARD_OBJ(a,GetVpValue(self,1));
    mx = a->Prec *(VpBaseFig() + 1);
    GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
    VpActiveRound(c,a,VP_ROUND_CEIL,iLoc);
    return ToValue(c);
}

static VALUE
BigDecimal_to_s(int argc, VALUE *argv, VALUE self)
{
    ENTER(5);
    Real *vp;
    char *psz;
    U_LONG nc;
    S_INT mc = 0;
    VALUE f;

    GUARD_OBJ(vp,GetVpValue(self,1));
    nc = VpNumOfChars(vp)+1;
    if(rb_scan_args(argc,argv,"01",&f)==1) {
        mc  = GetPositiveInt(f);
        nc += (nc + mc - 1) / mc + 1;
    }
    psz = ALLOCA_N(char,(unsigned int)nc);
    VpToString(vp, psz, mc);
    return rb_str_new2(psz);
}

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
    psz1 = ALLOCA_N(char,(unsigned int)VpNumOfChars(vp));
    VpSzMantissa(vp,psz1);
    s = 1;
    if(psz1[0]=='-') {
        s = -1; ++psz1;
    }
    if(psz1[0]=='N') s=0; /* NaN */
    e = VpExponent10(vp);
    obj1 = rb_str_new2(psz1);
    obj  = rb_ary_new();
    rb_ary_push(obj, INT2FIX(s));
    rb_ary_push(obj, obj1);
    rb_ary_push(obj, INT2FIX(10));
    rb_ary_push(obj, INT2NUM(e));
    return obj;
}

static VALUE
BigDecimal_exponent(VALUE self)
{
    S_LONG e = VpExponent10(GetVpValue(self,1));
    return INT2NUM(e);
}

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
    nc = VpNumOfChars(vp);
    nc +=(nc + 9) / 10;

    psz1   = ALLOCA_N(char,nc);
    pszAll = ALLOCA_N(char,nc+256);
    VpToString(vp, psz1, 10);
    sprintf(pszAll,"#<BigDecimal:%lx,'%s',%lu(%lu)>",self,psz1,VpPrec(vp)*VpBaseFig(),VpMaxPrec(vp)*VpBaseFig());
    obj = rb_str_new2(pszAll);
    return obj;
}

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
    GUARD_OBJ(pv,VpCreateRbObject(mf, RSTRING(iniValue)->ptr));
    return ToValue(pv);
}

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
    GUARD_OBJ(pv,VpNewRbClass(mf, RSTRING(iniValue)->ptr,self));
    return ToValue(pv);
}

static VALUE
BigDecimal_limit(int argc, VALUE *argv, VALUE self)
{
    VALUE  nFig;
    VALUE  nCur = INT2NUM(VpGetPrecLimit());

    if(rb_scan_args(argc,argv,"01",&nFig)==1) {
        Check_Type(nFig, T_FIXNUM);
        VpSetPrecLimit(FIX2INT(nFig));
    }
    return nCur;
}

static VALUE
BigDecimal_sign(VALUE self)
{ /* sign */
    int s = GetVpValue(self,1)->sign;
    return INT2FIX(s);
}

#ifdef ENABLE_TRIAL_METHOD
static VALUE
BigDecimal_e(VALUE self, VALUE nFig)
{
    ENTER(5);
    Real *pv;
    S_LONG mf;

    mf = GetPositiveInt(nFig);
    GUARD_OBJ(pv,VpCreateRbObject(mf, "0"));
    VpExp1(pv);
    return ToValue(pv);
}

static VALUE
BigDecimal_pi(VALUE self, VALUE nFig)
{
    ENTER(5);
    Real *pv;
    S_LONG mf;

    mf = GetPositiveInt(nFig)+VpBaseFig()-1;
    GUARD_OBJ(pv,VpCreateRbObject(mf, "0"));
    VpPi(pv);
    return ToValue(pv);
}

static VALUE
BigDecimal_exp(VALUE self, VALUE nFig)
{
    ENTER(5);
    Real *c, *y;
    S_LONG mf;

    GUARD_OBJ(y,GetVpValue(self,1));
    mf = GetPositiveInt(nFig);
    GUARD_OBJ(c,VpCreateRbObject(mf, "0"));
    VpExp(c, y);
    return ToValue(c);
}

static VALUE
BigDecimal_sincos(VALUE self, VALUE nFig)
{
    ENTER(5);
    VALUE obj;
    VALUE objSin;
    VALUE objCos;
    Real *pcos, *psin, *y;
    S_LONG mf;

    obj = rb_ary_new();
    GUARD_OBJ(y,GetVpValue(self,1));
    mf = GetPositiveInt(nFig);
    GUARD_OBJ(pcos,VpCreateRbObject(mf, "0"));
    GUARD_OBJ(psin,VpCreateRbObject(mf, "0"));
    VpSinCos(psin, pcos, y);

    objSin = ToValue(psin);
    objCos = ToValue(pcos);
    rb_ary_push(obj, objSin);
    rb_ary_push(obj, objCos);
    return obj;
}
#endif /* ENABLE_TRIAL_METHOD */

void
Init_bigdecimal(void)
{
    /* Initialize VP routines */
    VpInit((U_LONG)0);
    coerce = rb_intern("coerce");
    /* Class and method registration */
    rb_cBigDecimal = rb_define_class("BigDecimal",rb_cNumeric);

    /* Global function */
    rb_define_global_function("BigDecimal", BigDecimal_global_new, -1);

    /* Class methods */
    rb_define_singleton_method(rb_cBigDecimal, "new", BigDecimal_new, -1);
    rb_define_singleton_method(rb_cBigDecimal, "mode", BigDecimal_mode, 2);
    rb_define_singleton_method(rb_cBigDecimal, "limit", BigDecimal_limit, -1);
    rb_define_singleton_method(rb_cBigDecimal, "double_fig", BigDecimal_double_fig, 0);
    rb_define_singleton_method(rb_cBigDecimal, "induced_from",BigDecimal_induced_from, 1);
    rb_define_singleton_method(rb_cBigDecimal, "_load", BigDecimal_load, 1);
    rb_define_singleton_method(rb_cBigDecimal, "ver", BigDecimal_version, 0);

    /* Constants definition */
    rb_define_const(rb_cBigDecimal, "BASE", INT2FIX((S_INT)VpBaseVal()));

    /* Exceptions */
    rb_define_const(rb_cBigDecimal, "EXCEPTION_ALL",INT2FIX(VP_EXCEPTION_ALL));
    rb_define_const(rb_cBigDecimal, "EXCEPTION_NaN",INT2FIX(VP_EXCEPTION_NaN));
    rb_define_const(rb_cBigDecimal, "EXCEPTION_INFINITY",INT2FIX(VP_EXCEPTION_INFINITY));
    rb_define_const(rb_cBigDecimal, "EXCEPTION_UNDERFLOW",INT2FIX(VP_EXCEPTION_UNDERFLOW));
    rb_define_const(rb_cBigDecimal, "EXCEPTION_OVERFLOW",INT2FIX(VP_EXCEPTION_OVERFLOW));
    rb_define_const(rb_cBigDecimal, "EXCEPTION_ZERODIVIDE",INT2FIX(VP_EXCEPTION_ZERODIVIDE));

    /* Computation mode */
    rb_define_const(rb_cBigDecimal, "ROUND_MODE",INT2FIX(VP_ROUND_MODE));
    rb_define_const(rb_cBigDecimal, "ROUND_UP",INT2FIX(VP_ROUND_UP));
    rb_define_const(rb_cBigDecimal, "ROUND_DOWN",INT2FIX(VP_ROUND_DOWN));
    rb_define_const(rb_cBigDecimal, "ROUND_HALF_UP",INT2FIX(VP_ROUND_HALF_UP));
    rb_define_const(rb_cBigDecimal, "ROUND_HALF_DOWN",INT2FIX(VP_ROUND_HALF_DOWN));
    rb_define_const(rb_cBigDecimal, "ROUND_CEILING",INT2FIX(VP_ROUND_CEIL));
    rb_define_const(rb_cBigDecimal, "ROUND_FLOOR",INT2FIX(VP_ROUND_FLOOR));
    rb_define_const(rb_cBigDecimal, "ROUND_HALF_EVEN",INT2FIX(VP_ROUND_HALF_EVEN));

    /* Constants for sign value */
    rb_define_const(rb_cBigDecimal, "SIGN_NaN",INT2FIX(VP_SIGN_NaN));
    rb_define_const(rb_cBigDecimal, "SIGN_POSITIVE_ZERO",INT2FIX(VP_SIGN_POSITIVE_ZERO));
    rb_define_const(rb_cBigDecimal, "SIGN_NEGATIVE_ZERO",INT2FIX(VP_SIGN_NEGATIVE_ZERO));
    rb_define_const(rb_cBigDecimal, "SIGN_POSITIVE_FINITE",INT2FIX(VP_SIGN_POSITIVE_FINITE));
    rb_define_const(rb_cBigDecimal, "SIGN_NEGATIVE_FINITE",INT2FIX(VP_SIGN_NEGATIVE_FINITE));
    rb_define_const(rb_cBigDecimal, "SIGN_POSITIVE_INFINITE",INT2FIX(VP_SIGN_POSITIVE_INFINITE));
    rb_define_const(rb_cBigDecimal, "SIGN_NEGATIVE_INFINITE",INT2FIX(VP_SIGN_NEGATIVE_INFINITE));

    /* instance methods */
    rb_define_method(rb_cBigDecimal, "prec", BigDecimal_prec, 0);
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
    rb_define_method(rb_cBigDecimal, "!=", BigDecimal_ne, 1);
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

#ifdef ENABLE_TRIAL_METHOD
    rb_define_singleton_method(rb_cBigDecimal, "E", BigDecimal_e, 1);
    rb_define_singleton_method(rb_cBigDecimal, "PI", BigDecimal_pi, 1);
    rb_define_method(rb_cBigDecimal, "exp", BigDecimal_exp, 1);
    rb_define_method(rb_cBigDecimal, "sincos", BigDecimal_sincos, 1);
#endif /* ENABLE_TRIAL_METHOD */
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
static int gfDebug = 0;         /* Debug switch */
static int gfCheckVal = 1;      /* Value checking flag in VpNmlz()  */
#endif /* _DEBUG */

static U_LONG gnPrecLimit = 0;  /* Global upper limit of the precision newly allocated */
static short  gfRoundMode = VP_ROUND_HALF_UP; /* Mode for general rounding operation   */

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
static int VpAddAbs(Real *a,Real *b,Real *c);
static int VpSubAbs(Real *a,Real *b,Real *c);
static U_LONG VpSetPTR(Real *a,Real *b,Real *c,U_LONG *a_pos,U_LONG *b_pos,U_LONG *c_pos,U_LONG *av,U_LONG *bv);
static int VpNmlz(Real *a);
static void VpFormatSt(char *psz,S_INT fFmt);
static int VpRdup(Real *m,U_LONG ind_m);
static U_LONG SkipWhiteChar(char *szVal);

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

VP_EXPORT unsigned long
VpSetRoundMode(unsigned long n)
{
    if(n==VP_ROUND_UP      || n!=VP_ROUND_DOWN      ||
       n==VP_ROUND_HALF_UP || n!=VP_ROUND_HALF_DOWN ||
       n==VP_ROUND_CEIL    || n!=VP_ROUND_FLOOR     ||
       n==VP_ROUND_HALF_EVEN
      ) gfRoundMode = n;
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
VpException(unsigned short f,char *str,int always)
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
    if(fatal) rb_fatal(str);
    else   rb_raise(exc,str);
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
 *    returns number of chars needed to represent vp.
 */
VP_EXPORT U_LONG
VpNumOfChars(Real *vp)
{
    if(vp == NULL)   return BASE_FIG*2+6;
    if(!VpIsDef(vp)) return 32; /* not sure,may be OK */
    return     BASE_FIG *(vp->Prec + 2)+6; /* 3: sign + exponent chars */
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
VpOne()
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
VpAlloc(U_LONG mx, char *szVal)
{
    U_LONG i, ni, ipn, ipf, nf, ipe, ne, nalloc;
    char v;
    int  sign=1;
    Real *vp = NULL;
    U_LONG mf = VpGetPrecLimit();
    mx = (mx + BASE_FIG - 1) / BASE_FIG + 1;    /* Determine allocation unit. */
    if(szVal) {
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
    }

    /* necessary to be able to store */
    /* at least mx digits. */
    if(szVal == NULL) {
        /* szVal==NULL ==> allocate zero value. */
        vp = (Real *) VpMemAlloc(sizeof(Real) + mx * sizeof(U_LONG));
        /* xmalloc() alway returns(or throw interruption) */
        vp->MaxPrec = mx;    /* set max precision */
        VpSetZero(vp,1);    /* initialize vp to zero. */
        return vp;
    }
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
    i = SkipWhiteChar(szVal);
    ipn = i;
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
            while(szVal[i]) {
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
        VpSetInf(c,isw);
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
        if(c->Prec < a->Prec) {
            VpInternalRound(c,n,(n>0)?a->frac[n-1]:0,a->frac[n]);
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
     *   = 2 ...( 1)+( 1),( 1)-(-1)
     *   =-2 ...(-1)+(-1),(-1)-( 1)
     *   If isw==0, then c =(Sign a_ptr)(|a_ptr|-|b_ptr|)
     *     else c =(Sign of isw)(|a_ptr|+|b_ptr|)
    */
    if(isw) {            /* addition */
        VpSetSign(c,(S_INT)1);
        VpAddAbs(a_ptr, b_ptr, c);
        VpSetSign(c,isw / 2);
    } else {            /* subtraction */
        VpSetSign(c,(S_INT)1);
        VpSubAbs(a_ptr, b_ptr, c);
        if(a_ptr == a) {
            VpSetSign(c,VpGetSign(a));
        } else    {
            VpSetSign(c,VpGetSign(a_ptr) * sw);
        }
    }

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
static int
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
            --b_pos;
            c->frac[c_pos] = b->frac[b_pos];
        } else {
            --word_shift;
            c->frac[c_pos] = 0;
        }
    }

    /* Just assign the last few digits of a to c because b has no */
    /* corresponding digits to be added. */
    bv = b_pos + word_shift;
    while(a_pos > bv) {
        --c_pos;
        --a_pos;
        c->frac[c_pos] = a->frac[a_pos];
    }
    carry = 0;    /* set first carry be zero */

    /* Now perform addition until every digits of b will be */
    /* exhausted. */
    while(b_pos > 0) {
        --a_pos;
        --b_pos;
        --c_pos;
        c->frac[c_pos] = a->frac[a_pos] + b->frac[b_pos] + carry;
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
        --a_pos;
        --c_pos;
        c->frac[c_pos] = a->frac[a_pos] + carry;
        if(c->frac[c_pos] >= BASE) {
            c->frac[c_pos] -= BASE;
            carry = 1;
        } else {
            carry = 0;
        }
    }
    if(c_pos) c->frac[c_pos - 1] += carry;

    if(!VpInternalRound(c,0,(c->Prec>0)?a->frac[c->Prec-1]:0,mrv)) VpNmlz(c);
    goto Exit;

Assign_a:
    VpAsgn(c, a, 1);

Exit:

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpAddAbs exit: c=% \n", c);
    }
#endif /* _DEBUG */
    return 1;
}

/*
 * c = abs(a) - abs(b)
 */
static int
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
        borrow = 1;
        --c_pos;
        --b_pos;
        c->frac[c_pos] = BASE - b->frac[b_pos];
        while(b_pos + word_shift > a_pos) {
            --c_pos;
            if(b_pos > 0) {
                --b_pos;
                c->frac[c_pos] = BASE - b->frac[b_pos] - borrow;
            } else {
                --word_shift;
                c->frac[c_pos] = BASE - borrow;
            }
        }
    }
    /* Just assign the last few digits of a to c because b has no */
    /* corresponding digits to subtract. */

    bv = b_pos + word_shift;
    while(a_pos > bv) {
        --c_pos;
        --a_pos;
        c->frac[c_pos] = a->frac[a_pos];
    }

    /* Now perform subtraction until every digits of b will be */
    /* exhausted. */
    while(b_pos > 0) {
        --a_pos;
        --b_pos;
        --c_pos;
        if(a->frac[a_pos] < b->frac[b_pos] + borrow) {
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
        --a_pos;
        if(a->frac[a_pos] < borrow) {
            c->frac[c_pos] = BASE + a->frac[a_pos] - borrow;
            borrow = 1;
        } else {
            c->frac[c_pos] = a->frac[a_pos] - borrow;
            borrow = 0;
        }
    }
    if(c_pos) c->frac[c_pos - 1] -= borrow;

    if(!VpInternalRound(c,0,(c->Prec>0)?a->frac[c->Prec-1]:0,mrv)) VpNmlz(c);
    goto Exit;

Assign_a:
    VpAsgn(c, a, 1);

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "VpSubAbs exit: c=% \n", c);
    }
#endif /* _DEBUG */
    return 1;
}

/*
 * Note: If(av+bv)>= HALF_BASE,then 1 will be added to the least significant
 *    digit of c(In case of addition).
 * ------------------------- figure of output -----------------------------------
 *      a =  xxxxxxxxxxx
 *      b =    xxxxxxxxxx
 *      c =xxxxxxxxxxxxxxx
 *   word_shift =  |   |
 *   right_word =  |    | (Total digits in RHSV)
 *   left_word  = |   |   (Total digits in LHSV)
 *   a_pos   =    |
 *   b_pos   =     |
 *   c_pos   =      |
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
     * check if 'round off' is needed.
     */
    if(right_word > left_word) {    /* round off ? */
        /*---------------------------------
         *  Actual size of a = xxxxxxAxx
         *  Actual size of b = xxxBxxxxx
         *  Max. size of   c = xxxxxx
         *  Round off  =   |-----|
         *  c_pos   =   |
         *  right_word    =   |
         *  a_pos   =    |
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
    U_LONG ind_c, i, nc;
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

        s = 0L;
        for(i = ind_as; i <= ind_ae; ++i) s +=((a->frac[i]) *(b->frac[ind_bs--]));
        Carry = s / BASE;
        s = s -(Carry * BASE);

        c->frac[ind_c] += s;
        if(c->frac[ind_c] >= BASE) {
            s = c->frac[ind_c] / BASE;
            Carry += s;
            c->frac[ind_c] -=(s * BASE);
        }
        i = ind_c;
        if(Carry) {
            while((--i) >= 0) {
                c->frac[i] += Carry;
                if(c->frac[i] >= BASE) {
                    Carry = c->frac[i] / BASE;
                    c->frac[i] -=(Carry * BASE);
                } else {
                    break;
                }
            }
        }
    }

    VpNmlz(c);            /* normalize the result */
    if(w != NULL) {        /* free work variable */
        VpAsgn(w, c, 1);
        VpFree(c);
        c = w;
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
    U_LONG ind_a, i, j;

    if(VpIsZero(a)) {
        VpSetZero(a,VpGetSign(a));
        return 1;
    }
    ind_a = a->Prec;
    while(ind_a--) {
        if(a->frac[ind_a]) {
            a->Prec = ind_a + 1;
            i = j = 0;
            while(a->frac[i] == 0) ++i;        /* skip the first few zeros */
            if(i) {
                a->Prec -= i;
                if(!AddExponent(a,-((S_INT)i))) return 0;
                while(i <= ind_a) {
                    a->frac[j] = a->frac[i];
                    ++i;
                    ++j;
                }
            }
#ifdef _DEBUG
            if(gfCheckVal)    VpVarCheck(a);
#endif /* _DEBUG */
            return 1;
        }
    }
    /* a is zero(no non-zero digit) */
    VpSetZero(a,VpGetSign(a));
    return 1;
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
    int fDot = 0;

    ie = strlen(psz);
    for(i = 0; i < ie; ++i) {
        ch = psz[i];
        if(!ch) break;
        if(ch == '.') {
            nf = 0;
            fDot = 1;
            continue;
        }
        if(!fDot)  continue;
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

    if(!VpIsDef(a)) return 0;
    if(VpIsZero(a)) return 0;

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
    } else {
        if(VpIsPosZero(a)) sprintf(psz, "0");
        else      sprintf(psz, "-0");
    }
}

VP_EXPORT void
VpToString(Real *a,char *psz,int fFmt)
{
    U_LONG i, ZeroSup;
    U_LONG n, m, e, nn;
    char *pszSav = psz;
    S_LONG ex;

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

    ZeroSup = 1;    /* Flag not to print the leading zeros as 0.00xxxxEnn */
    if(!VpIsZero(a)) {
        if(VpGetSign(a) < 0) *psz++ = '-';
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
        sprintf(psz, "E%ld", ex);
    } else {
        if(VpIsPosZero(a)) sprintf(psz, "0.0");
        else      sprintf(psz, "-0.0");
    }
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
VpCtoV(Real *a, char *int_chr, U_LONG ni, char *frac, U_LONG nf, char *exp_chr, U_LONG ne)
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
                return VpException(VP_EXCEPTION_INFINITY,"Exponent overflow",0);
            }
            ++i;
        }
    }

    /* get integer part */
    i = 0;
    sign = 1;
    if(ni > 0) {
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

    if(!VpInternalRound(m,0,(m->Prec>0)?m->frac[m->Prec-1]:0,
                      (U_LONG)(val*((double)((S_INT)BASE))))) VpNmlz(m);

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

    if(!VpIsDef(x)) {
        VpAsgn(y,x,1);
        goto Exit;
    }

    if(VpIsZero(x)) {
        VpSetZero(y,VpGetSign(x));
        goto Exit;
    }

    if(VpGetSign(x) < 0) {
        VpSetZero(y,VpGetSign(x));
        return VpException(VP_EXCEPTION_OP,"(VpSqrt) SQRT(negative valuw)",0);
    }

    n = (S_LONG)y->MaxPrec;
    if((S_LONG)x->MaxPrec > n) n = (S_LONG)x->MaxPrec;
    /* allocate temporally variables  */
    f = VpAlloc(y->MaxPrec *(BASE_FIG + 2), "#1");
    r = VpAlloc((n + n) *(BASE_FIG + 2), "#1");

    nr = 0;
    y_prec = (S_LONG)y->MaxPrec;
    f_prec = (S_LONG)f->MaxPrec;

    VpAsgn(y, x, 1);        /* assign initial guess. y <= x */
    prec = x->exponent;
    if(prec > 0)    ++prec;
    else            --prec;
    prec = prec / 2 - (S_LONG)y->MaxPrec;
    /*
     *  y  = 0.yyyy yyyy yyyy YYYY
     *  BASE_FIG =   |  |
     *  prec  =(0.YYYY*BASE-4)
     */
    VpVtoD(&val, &e, y);    /* val <- y  */
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
        VpDivd(f, r, x, y);    /* f = x/y  */
        VpAddSub(r, y, f, 1);    /* r = y + x/y  */
        VpMult(f, VpPt5, r);    /* f = 0.5*r  */
        VpAddSub(r, f, y, -1);
        if(VpIsZero(r))         goto converge;
        if(r->exponent <= prec) goto converge;
        VpAsgn(y, f, 1);
    } while(++nr < n);
    /* */
#ifdef _DEBUG
    if(gfDebug) {
        printf("ERROR(VpSqrt): did not converge within %ld iterations.\n",
            nr);
    }
#endif /* _DEBUG */
    y->MaxPrec = y_prec;
    goto Exit;

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
VP_EXPORT void
VpMidRound(Real *y, int f, int nf)
/*
 * Round reletively from the decimal point.
 *    f: rounding mode
 *   nf: digit location to round from the the decimal point.
 */
{
    int n,i,ix,ioffset;
    U_LONG v;
    U_LONG div;

    nf += y->exponent*((int)BASE_FIG);

    /* ix: x->fraq[ix] contains round position */
    ix = nf/(int)BASE_FIG;
    if(ix<0 || ((U_LONG)ix)>=y->Prec) return; /* Unable to round */
    ioffset = nf - ix*((int)BASE_FIG);
    memset(y->frac+ix+1, 0, (y->Prec - (ix+1)) * sizeof(U_LONG));
    /* VpNmlz(y); */
    v = y->frac[ix];
    /* drop digits after pointed digit */
    n = BASE_FIG - ioffset - 1;
    for(i=0;i<n;++i) v /= 10;
    div = v/10;
    v = v - div*10;
    switch(f) {
    case VP_ROUND_DOWN: /* Truncate */
         break;
    case VP_ROUND_UP:   /* Roundup */
        if(v) ++div;
         break;
    case VP_ROUND_HALF_UP:   /* Round half up  */
        if(v>=5) ++div;
        break;
    case VP_ROUND_HALF_DOWN: /* Round half down  */
        if(v>=6) ++div;
        break;
    case VP_ROUND_CEIL: /* ceil */
        if(v && (VpGetSign(y)>0)) ++div;
        break;
    case VP_ROUND_FLOOR: /* floor */
        if(v && (VpGetSign(y)<0)) ++div;
        break;
    case VP_ROUND_HALF_EVEN: /* Banker's rounding */
        if(v>5) ++div;
        else if(v==5) {
            if(i==(BASE_FIG-1)) {
                if(ix && (y->frac[ix-1]%2)) ++div;
            } else {
                if(div%2) ++div;
            }
        }
        break;
    }
    for(i=0;i<=n;++i) div *= 10;
    if(div>=BASE) {
        y->frac[ix] = 0;
        if(ix) {
            VpNmlz(y);
            VpRdup(y,0);
        } else {
            VpSetOne(y);
            VpSetSign(y,VpGetSign(y));
        }
    } else {
        y->frac[ix] = div;
        VpNmlz(y);
    }
}

VP_EXPORT void
VpLeftRound(Real *y, int f, int nf)
/*
 * Round from the left hand side of the digits.
 */
{
    U_LONG v;

    if(!VpIsDef(y)) return; /* Unable to round */
    if(VpIsZero(y)) return;

    v = y->frac[0];
    nf -= VpExponent(y)*BASE_FIG;
    while(v=v/10) nf--;
    nf += (BASE_FIG-1);
    VpMidRound(y,f,nf);
}

VP_EXPORT void
VpActiveRound(Real *y, Real *x, int f, int nf)
{
    /* First,assign whole value in truncation mode */
    VpAsgn(y, x, 1); /* 1 round off,2 round up */
    if(!VpIsDef(y)) return; /* Unable to round */
    if(VpIsZero(y)) return;
    VpMidRound(y,f,nf);
}

static int 
VpInternalRound(Real *c,int ixDigit,U_LONG vPrev,U_LONG v)
{
    int f = 0;

    if(!VpIsDef(c)) return f; /* Unable to round */
    if(VpIsZero(c)) return f;

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
    if(f) VpRdup(c,ixDigit);    /* round up */
    return f;
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

    if(!VpIsDef(x) || VpIsZero(x)) {
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
    while(ind_y <= my) {
        y->frac[ind_y] = x->frac[ind_x];
        ++ind_y;
        ++ind_x;
    }

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

#ifdef ENABLE_TRIAL_METHOD
/*
 * Calculates pi(=3.141592653589793238462........).
 */
VP_EXPORT void
VpPi(Real *y)
{
    Real *n, *n25, *n956, *n57121;
    Real *r, *f, *t;
    U_LONG p;
    U_LONG nc;
    U_LONG i1,i2;

    p = y->MaxPrec *(BASE_FIG + 2) + 2;
    if(p<maxnr) nc = maxnr;
    else  nc = p;

    /* allocate temporally variables  */
    r = VpAlloc(p * 2, "#0");
    f = VpAlloc(p, "#0");
    t = VpAlloc(p, "#-80");

    n = VpAlloc((U_LONG)10, "1");
    n25 = VpAlloc((U_LONG)2, "-0.04"); /*-25");*/
    n956 = VpAlloc((U_LONG)3, "956");
    n57121 = VpAlloc((U_LONG)5, "-57121");

    VpSetZero(y,1);        /* y   = 0 */
    i1 = 0;
    do {
        ++i1;
        /* VpDivd(f, r, t, n25); */ /* f = t/(-25) */
        VpMult(f,t,n25);
        VpAsgn(t, f, 1);       /* t = f    */

        VpDivd(f, r, t, n); /* f = t/n  */

        VpAddSub(r, y, f, 1);  /* r = y + f   */
        VpAsgn(y, r, 1);       /* y = r    */

        VpRdup(n,0);            /* n   = n + 1 */
        VpRdup(n,0);            /* n   = n + 1 */
        if(VpIsZero(f)) break;
    } while((f->exponent > 0 ||    ((U_LONG)(-(f->exponent)) < y->MaxPrec)) &&
            i1<nc
    );

    VpSetOne(n);
    VpAsgn(t, n956,1);
    i2 = 0;
    do {
        ++i2;
        VpDivd(f, r, t, n57121); /* f = t/(-57121) */
        VpAsgn(t, f, 1);      /* t = f    */

        VpDivd(f, r, t, n);   /* f = t/n  */
        VpAddSub(r, y, f, 1); /* r = y + f   */

        VpAsgn(y, r, 1);      /* y = r    */
        VpRdup(n,0);           /* n   = n + 1  */
        VpRdup(n,0);           /* n   = n + 1 */
        if(VpIsZero(f)) break;
    } while((f->exponent > 0 || ((U_LONG)(-(f->exponent)) < y->MaxPrec)) &&
            i2<nc
        );

    VpFree(n);
    VpFree(n25);
    VpFree(n956);
    VpFree(n57121);

    VpFree(t);
    VpFree(f);
    VpFree(r);
#ifdef _DEBUG
    printf("VpPi: # of iterations=%lu+%lu\n",i1,i2);
#endif /* _DEBUG */
}

/*
 * Calculates the value of e(=2.18281828459........).
 * [Output] *y ... Real , the value of e.
 *
 *     y = e
 */
VP_EXPORT void
VpExp1(Real *y)
{
    Real *n, *r, *f, *add;
    U_LONG p;
    U_LONG nc;
    U_LONG i;

    p = y->MaxPrec*(BASE_FIG + 2) + 2;
    if(p<maxnr) nc = maxnr;
    else  nc = p;

    /* allocate temporally variables  */

    r = VpAlloc(p *(BASE_FIG + 2), "#0");
    f = VpAlloc(p, "#1");
    n = VpAlloc(p, "#1");    /* n   = 1 */
    add = VpAlloc(p, "#1");    /* add = 1 */

    VpSetOne(y);            /* y   = 1 */
    VpRdup(y,0);            /* y   = y + 1  */
    i = 0;
    do {
        ++i;
        VpRdup(n,0);        /* n   = n + 1  */
        VpDivd(f, r, add, n);    /* f   = add/n(=1/n!)  */
        VpAsgn(add, f, 1);    /* add = 1/n!  */
        VpAddSub(r, y, f, 1);
        VpAsgn(y, r, 1);    /* y = y + 1/n! */
    } while((f->exponent > 0 || ((U_LONG)(-(f->exponent)) <= y->MaxPrec)) &&
            i<nc
        );

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "vpexp e=%\n", y);
        printf("   r=%d\n", f[3]);
    }
#endif /* _DEBUG */
    VpFree(add);
    VpFree(n);
    VpFree(f);
    VpFree(r);
}

/*
 * Calculates y=e**x where e(=2.18281828459........).
 */
VP_EXPORT void
VpExp(Real *y, Real *x)
{
    Real *z=NULL, *div=NULL, *n=NULL, *r=NULL, *c=NULL;
    U_LONG p;
    U_LONG nc;
    U_LONG i;
    short  fNeg=0;

    if(!VpIsDef(x)) {
        VpSetNaN(y); /* Not sure */
        goto Exit;
    }
    if(VpIsZero(x)) {
        VpSetOne(y);
        goto Exit;
    }
    p = y->MaxPrec;
    if(p < x->Prec) p = x->Prec;
    p = p *(BASE_FIG + 2) + 2;
    if(p<maxnr) nc = maxnr;
    else  nc = p;

    fNeg = x->sign;
    if(fNeg<0) x->sign = -fNeg;

    /* allocate temporally variables  */
    z = VpAlloc(p, "#1");
    div = VpAlloc(p, "#1");

    r = VpAlloc(p * 2, "#0");
    c = VpAlloc(p, "#0");
    n = VpAlloc(p, "#1");    /* n   = 1 */

    VpSetOne(r);        /* y = 1 */
    VpAddSub(y, r, x, 1);    /* y = 1 + x/1 */
    VpAsgn(z, x, 1);    /* z = x/1  */

    i = 0;
    do {
        ++i;
        VpRdup(n,0);        /* n   = n + 1  */
        VpDivd(div, r, x, n);    /* div = x/n */
        VpMult(c, z, div);    /* c   = x/(n-1)! * x/n */
        VpAsgn(z, c, 1);    /* z   = x*n/n! */
        VpAsgn(r, y, 1);    /* Save previous val. */
        VpAddSub(div, y, z, 1);    /*  */
        VpAddSub(c, div, r, -1);    /* y = y(new) - y(prev) */
        VpAsgn(y, div, 1);    /* y = y(new) */
    } while(((!VpIsZero(c)) &&(c->exponent >= 0 ||((U_LONG)(-c->exponent)) <= y->MaxPrec)) &&
            i<nc
           );

    if(fNeg < 0) {
        x->sign = fNeg;
        VpDivd(div, r, VpConstOne, y);
        VpAsgn(y, div, 1);
    }

Exit:

#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "vpexp e=%\n", y);
    }
#endif /* _DEBUG */
    VpFree(div);
    VpFree(n);
    VpFree(c);
    VpFree(r);
    VpFree(z);
}

VP_EXPORT void
VpSinCos(Real *psin,Real *pcos,Real *x)
/*
 * Calculates sin(x) & cos(x)
 *(Assumes psin->MaxPrec==pcos->MaxPrec)
 */
{
    Real *z=NULL, *div=NULL, *n=NULL, *r=NULL, *c=NULL;
    U_LONG p;
    int fcos;
    int fsin;
    int which;
    U_LONG nc;
    U_LONG i;

    if(!VpIsDef(x)) {
        VpSetNaN(psin);
        VpSetNaN(pcos);
        goto Exit;
    }

    p = pcos->MaxPrec;
    if(p < x->Prec) p = x->Prec;
    p = p *(BASE_FIG + 2) + 2;
    if(p<maxnr) nc = maxnr;
    else  nc = p;

    /* allocate temporally variables  */
    z = VpAlloc(p, "#1");
    div = VpAlloc(p, "#1");

    r = VpAlloc(p * 2, "#0");
    c = VpAlloc(p , "#0");
    n = VpAlloc(p, "#1");    /* n   = 1 */

    VpSetOne(pcos);        /* cos = 1 */
    VpAsgn(psin, x, 1);    /* sin = x/1 */
    VpAsgn(z, x, 1);        /* z = x/1  */
    fcos = 1;
    fsin = 1;
    which = 1;
    i = 0;
    do {
        ++i;
        VpRdup(n,0);        /* n   = n + 1  */
        VpDivd(div, r, x, n);    /* div = x/n */
        VpMult(c, z, div);    /* c   = x/(n-1)! * x/n */
        VpAsgn(z, c, 1);    /* z   = x*n/n! */
        if(which) {
            /* COS */
            which = 0;
            fcos *= -1;
            VpAsgn(r, pcos, 1);    /* Save previous val. */
            VpAddSub(div, pcos, z, fcos);    /*  */
            VpAddSub(c, div, r, -1);    /* cos = cos(new) - cos(prev) */
            VpAsgn(pcos, div, 1);    /* cos = cos(new) */
        } else {
            /* SIN */
            which = 1;
            fsin *= -1;
            VpAsgn(r, psin, 1);    /* Save previous val. */
            VpAddSub(div, psin, z, fsin);    /*  */
            VpAddSub(c, div, r, -1);    /* sin = sin(new) - sin(prev) */
            VpAsgn(psin, div, 1);    /* sin = sin(new) */
        }
    } while(((!VpIsZero(c)) &&(c->exponent >= 0 || ((U_LONG)(-c->exponent)) <= pcos->MaxPrec)) &&
            i<nc
    );

Exit:
#ifdef _DEBUG
    if(gfDebug) {
        VPrint(stdout, "cos=%\n", pcos);
        VPrint(stdout, "sin=%\n", psin);
    }
#endif /* _DEBUG */
    VpFree(div);
    VpFree(n);
    VpFree(c);
    VpFree(r);
    VpFree(z);
}
#endif /* ENABLE_TRIAL_METHOD */

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

static U_LONG
SkipWhiteChar(char *szVal)
{
    char ch;
    U_LONG i = 0;
    while(ch = szVal[i++]) {
        if(ISSPACE(ch)) continue;
        break;
    }
    return i - 1;
}
