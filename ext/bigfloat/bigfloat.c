/*
 *
 * Ruby BIGFLOAT(Variable Precision) extension library. 
 *
 * Copyright(C) 1999  by Shigeo Kobayashi(shigeo@tinyforest.gr.jp) 
 *
 * You may distribute under the terms of either the GNU General Public 
 * License or the Artistic License, as specified in the README file 
 * of this BigFloat distribution. 
 *
 *  Version 1.1.8(2001/10/23)
 *    bug(reported by Stephen Legrand) on VpAlloc() fixed.
 *  Version 1.1.7(2001/08/27)
 *    limit() method added for global upper limit of precision.
 *    VpNewRbClass() added for new() to create new object from klass.
 *  Version 1.1.6(2001/03/27)
 *    Changed to use USE_XMALLOC & USE_XFREE
 *    ENTER,SAVE & GUARD_OBJ macro used insted of calling rb_gc_mark().
 *    modulo added to keep consistency with Float.
 *    Bug in abs(0.0) fixed.
 *    == and != changed not to coerce.
 *
 *  Version 1.1.5(2001/02/16)
 *    (Bug fix) BASE_FIG & DBLE_FIG changed to S_LONG
 *              Effective figures for sqrt() extended.
 *
 *  Version 1.1.4(2000/10/01)
 *    nan?,infinite?,finite?,truncate added.
 *
 *  Version 1.1.3(2000/06/16)
 *    Optional parameter is now allowed for ceil,floor,and round(1.1.2).
 *    Meanings of the optional parameter for ceil,floor,and round changed(1.1.3).
 *
 */

#include "ruby.h"
#include <stdio.h>
#include <stdlib.h>
#ifdef NT
#include <malloc.h>
#endif /* defined NT */
#include "ruby.h"
#include "math.h"
#include "version.h"

VALUE rb_cBigfloat;

#if RUBY_VERSION_CODE > 150
# define rb_str2inum rb_cstr2inum
#endif 

#include "bigfloat.h"

/* 
 *  In Windows DLL,using xmalloc() may result to an application error.
 *  This is defaulted from 1.1.6.
  */
#define USE_XMALLOC

/*
 * #define USE_XFREE calls xfree() instead of free().
 * If USE_XFREE is defined,then xfree() in gc.c must
 * be exported for other modules.
 * This is defaulted from 1.1.6.
 */
#define USE_XFREE

/* 
 *  To builtin BIGFLOAT into ruby
#define BUILTIN_BIGFLOAT
 *  and modify inits.c to call Init_Bigfloat().
 *  Class name for builtin BIGFLOAT is "Bigfloat".
 *  Class name for ext. library is "BigFloat".
 */
#ifdef BUILTIN_BIGFLOAT
/* Builtin BIGFLOAT */
#define BIGFLOAT_CLASS_NAME "Bigfloat"
#define BIGFLOAT Init_Bigfloat
#else
/* In case of ext. library */
#define BIGFLOAT_CLASS_NAME "BigFloat"
#define BIGFLOAT Init_BigFloat
#endif /* BUILTIN_BIGFLOAT */
#define Initialize(x) x()

/*
 * Uncomment if you need Float's Inf NaN instead of BigFloat's.
 *
#define USE_FLOAT_VALUE
*/

/* MACRO's to guard objects from GC by keeping it in stack */
#define ENTER(n) volatile VALUE vStack[n];int iStack=0
#define PUSH(x)  vStack[iStack++] = (unsigned long)(x);
#define SAVE(p)  PUSH(p->obj);
#define GUARD_OBJ(p,y) {p=y;SAVE(p);}

/*
 * ===================================================================
 *
 * Ruby Interface part
 *
 * ===================================================================
 */
static ID coerce;

static VALUE BigFloat_new();	/* new */
static VALUE BigFloat_limit();	/* limit */
static VALUE BigFloat_to_s();	/* to_s */
static VALUE BigFloat_to_i();	/* to_i */
static VALUE BigFloat_to_s2();	/* to_s2(spacing) */
static VALUE BigFloat_to_parts();/* to_parts(4 parts) */
static VALUE BigFloat_uplus();  /* a = +a (unary plus) */
static VALUE BigFloat_asign();	/* assign! */
static VALUE BigFloat_asign2();	/* assign */
static VALUE BigFloat_add();	/* + */
static VALUE BigFloat_sub();	/* - */
static VALUE BigFloat_add2();	/* add */
static VALUE BigFloat_sub2();	/* sub */
static VALUE BigFloat_add3();	/* add!(c,a,b) */
static VALUE BigFloat_sub3();	/* sub!(c,a,b) */
static VALUE BigFloat_neg();	/* -(unary) */
static VALUE BigFloat_mult();	/* * */
static VALUE BigFloat_mult2();	/* mult */
static VALUE BigFloat_mult3();	/* mult! */
static VALUE BigFloat_div();	/* / */
static VALUE BigFloat_mod();	/* % */
static VALUE BigFloat_remainder();	/* remainder */
static VALUE BigFloat_divmod();	/* divmod */
static VALUE BigFloat_divmod2();/* div */
static VALUE BigFloat_divmod4();/* divmod! */
static VALUE BigFloat_dup();	/* dup */
static VALUE BigFloat_abs();	/* abs */
static VALUE BigFloat_sqrt();	/* sqrt */
static VALUE BigFloat_fix();	/* fix */
static VALUE BigFloat_round();	/* round */
static VALUE BigFloat_frac();	/* frac */
static VALUE BigFloat_e();	/* e(=2.18281828459.....) */
static VALUE BigFloat_pai();	/* pai(=3.141592653589.....) */
static VALUE BigFloat_power();	/* self**p */
static VALUE BigFloat_exp();	/* e**x */
static VALUE BigFloat_sincos();	/* sin & cos */
static VALUE BigFloat_comp();	/* self <=> r */
static VALUE BigFloat_eq();	/* self ==  r */
static VALUE BigFloat_ne();	/* self !=  r */
static VALUE BigFloat_lt();	/* self <   r */
static VALUE BigFloat_le();	/* self <=  r */
static VALUE BigFloat_gt();	/* self >   r */
static VALUE BigFloat_ge();	/* self >=  r */
static VALUE BigFloat_zero();	/* self==0 ? */
static VALUE BigFloat_nonzero();/* self!=0 ? */
static VALUE BigFloat_floor();	/* floor(self) */
static VALUE BigFloat_ceil();	/* ceil(self)  */
static VALUE BigFloat_coerce();	/* coerce */
static VALUE BigFloat_inspect();/* inspect*/
static VALUE BigFloat_exponent();/* exponent */
static VALUE BigFloat_sign();/* sign */
static VALUE BigFloat_mode();   /* mode */
static VALUE BigFloat_induced_from(); /* induced_from */
static void BigFloat_delete();	/* free */

/* Added for ruby 1.6.0 */
static VALUE BigFloat_IsNaN();
static VALUE BigFloat_IsInfinite();
static VALUE BigFloat_IsFinite();
static VALUE BigFloat_truncate();

static VALUE DoSomeOne();
/* Following 3 functions borrowed from numeric.c */
static VALUE coerce_body();
static VALUE coerce_rescue();
static void  do_coerce();

static VALUE
DoSomeOne(x, y)
	VALUE x, y;
{
	do_coerce(&x, &y);
	return rb_funcall(x, rb_frame_last_func(), 1, y);
}

static VALUE
coerce_body(x)
	VALUE *x;
{
	return rb_funcall(x[1], coerce, 1, x[0]);
}

static VALUE
coerce_rescue(x)
	VALUE *x;
{
	rb_raise(rb_eTypeError, "%s can't be coerced into %s",
		rb_special_const_p(x[1])?
		STR2CSTR(rb_inspect(x[1])):
		rb_class2name(CLASS_OF(x[1])),
		rb_class2name(CLASS_OF(x[0])));
	return 	(VALUE)0;
}

static void
do_coerce(x, y)
	VALUE *x, *y;
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

void
Initialize(BIGFLOAT)
{

	/* Initialize VP routines */
	VpInit((U_LONG)0);

	coerce = rb_intern("coerce");
 
	/* Class and method registration */
	rb_cBigfloat = rb_define_class(BIGFLOAT_CLASS_NAME,rb_cNumeric);

	/* Class methods */
	rb_define_singleton_method(rb_cBigfloat, "mode", BigFloat_mode, 2);
	rb_define_singleton_method(rb_cBigfloat, "new", BigFloat_new, -1);
	rb_define_singleton_method(rb_cBigfloat, "limit", BigFloat_limit, -1);
	rb_define_singleton_method(rb_cBigfloat, "E", BigFloat_e, 1);
	rb_define_singleton_method(rb_cBigfloat, "PI", BigFloat_pai, 1);
	rb_define_singleton_method(rb_cBigfloat, "assign!", BigFloat_asign, 3);
	rb_define_singleton_method(rb_cBigfloat, "add!", BigFloat_add3, 3);
	rb_define_singleton_method(rb_cBigfloat, "sub!", BigFloat_sub3, 3);
	rb_define_singleton_method(rb_cBigfloat, "mult!", BigFloat_mult3, 3);
	rb_define_singleton_method(rb_cBigfloat, "div!",BigFloat_divmod4, 4);

	rb_define_method(rb_cBigfloat, "assign", BigFloat_asign2, 2);
	rb_define_method(rb_cBigfloat, "add", BigFloat_add2, 2);
	rb_define_method(rb_cBigfloat, "sub", BigFloat_sub2, 2);
	rb_define_method(rb_cBigfloat, "mult", BigFloat_mult2, 2);
	rb_define_method(rb_cBigfloat, "div",BigFloat_divmod2, 2);

	rb_define_singleton_method(rb_cBigfloat, "induced_from",BigFloat_induced_from, 1);

	rb_define_const(rb_cBigfloat, "BASE", INT2FIX((S_INT)VpBaseVal()));

	/* Exception constants */
	rb_define_const(rb_cBigfloat, "EXCEPTION_ALL",INT2FIX(VP_EXCEPTION_ALL));
	rb_define_const(rb_cBigfloat, "EXCEPTION_NaN",INT2FIX(VP_EXCEPTION_NaN));
	rb_define_const(rb_cBigfloat, "EXCEPTION_INFINITY",INT2FIX(VP_EXCEPTION_INFINITY));
	rb_define_const(rb_cBigfloat, "EXCEPTION_UNDERFLOW",INT2FIX(VP_EXCEPTION_UNDERFLOW));
	rb_define_const(rb_cBigfloat, "EXCEPTION_OVERFLOW",INT2FIX(VP_EXCEPTION_OVERFLOW));
	rb_define_const(rb_cBigfloat, "EXCEPTION_ZERODIVIDE",INT2FIX(VP_EXCEPTION_ZERODIVIDE));

	/* Constants for sign value */
	rb_define_const(rb_cBigfloat, "SIGN_NaN",INT2FIX(VP_SIGN_NaN));
	rb_define_const(rb_cBigfloat, "SIGN_POSITIVE_ZERO",INT2FIX(VP_SIGN_POSITIVE_ZERO));
	rb_define_const(rb_cBigfloat, "SIGN_NEGATIVE_ZERO",INT2FIX(VP_SIGN_NEGATIVE_ZERO));
	rb_define_const(rb_cBigfloat, "SIGN_POSITIVE_FINITE",INT2FIX(VP_SIGN_POSITIVE_FINITE));
	rb_define_const(rb_cBigfloat, "SIGN_NEGATIVE_FINITE",INT2FIX(VP_SIGN_NEGATIVE_FINITE));
	rb_define_const(rb_cBigfloat, "SIGN_POSITIVE_INFINITE",INT2FIX(VP_SIGN_POSITIVE_INFINITE));
	rb_define_const(rb_cBigfloat, "SIGN_NEGATIVE_INFINITE",INT2FIX(VP_SIGN_NEGATIVE_INFINITE));

	/* instance methods */
	rb_define_method(rb_cBigfloat, "to_s", BigFloat_to_s, 0);
	rb_define_method(rb_cBigfloat, "to_i", BigFloat_to_i, 0);
	rb_define_method(rb_cBigfloat, "to_s2", BigFloat_to_s2, 1);
	rb_define_method(rb_cBigfloat, "to_parts", BigFloat_to_parts, 0);
	rb_define_method(rb_cBigfloat, "+", BigFloat_add, 1);
	rb_define_method(rb_cBigfloat, "-", BigFloat_sub, 1);
	rb_define_method(rb_cBigfloat, "+@", BigFloat_uplus, 0);
	rb_define_method(rb_cBigfloat, "-@", BigFloat_neg, 0);
	rb_define_method(rb_cBigfloat, "*", BigFloat_mult, 1);
	rb_define_method(rb_cBigfloat, "/", BigFloat_div, 1);
	rb_define_method(rb_cBigfloat, "%", BigFloat_mod, 1);
	rb_define_method(rb_cBigfloat, "modulo", BigFloat_mod, 1);
	
	rb_define_method(rb_cBigfloat, "remainder", BigFloat_remainder, 1);
	rb_define_method(rb_cBigfloat, "divmod", BigFloat_divmod, 1);
	rb_define_method(rb_cBigfloat, "dup", BigFloat_dup, 0);
	rb_define_method(rb_cBigfloat, "to_f", BigFloat_dup, 0); /* to_f === dup */
	rb_define_method(rb_cBigfloat, "abs", BigFloat_abs, 0);
	rb_define_method(rb_cBigfloat, "sqrt", BigFloat_sqrt, 1);
	rb_define_method(rb_cBigfloat, "fix", BigFloat_fix, 0);
	rb_define_method(rb_cBigfloat, "round", BigFloat_round, -1);
	rb_define_method(rb_cBigfloat, "frac", BigFloat_frac, 0);
	rb_define_method(rb_cBigfloat, "floor", BigFloat_floor, -1);
	rb_define_method(rb_cBigfloat, "ceil", BigFloat_ceil, -1);
	rb_define_method(rb_cBigfloat, "power", BigFloat_power, 1);
	rb_define_method(rb_cBigfloat, "exp", BigFloat_exp, 1);
	rb_define_method(rb_cBigfloat, "sincos", BigFloat_sincos, 1);
	rb_define_method(rb_cBigfloat, "<=>", BigFloat_comp, 1);
	rb_define_method(rb_cBigfloat, "==", BigFloat_eq, 1);
	rb_define_method(rb_cBigfloat, "===", BigFloat_eq, 1);
	rb_define_method(rb_cBigfloat, "!=", BigFloat_ne, 1);
	rb_define_method(rb_cBigfloat, "<", BigFloat_lt, 1);
	rb_define_method(rb_cBigfloat, "<=", BigFloat_le, 1);
	rb_define_method(rb_cBigfloat, ">", BigFloat_gt, 1);
	rb_define_method(rb_cBigfloat, ">=", BigFloat_ge, 1);
	rb_define_method(rb_cBigfloat, "zero?", BigFloat_zero, 0);
	rb_define_method(rb_cBigfloat, "nonzero?", BigFloat_nonzero, 0);
	rb_define_method(rb_cBigfloat, "coerce", BigFloat_coerce, 1);
	rb_define_method(rb_cBigfloat, "inspect", BigFloat_inspect, 0);
	rb_define_method(rb_cBigfloat, "exponent", BigFloat_exponent, 0);
	rb_define_method(rb_cBigfloat, "sign", BigFloat_sign, 0);
    /* newly added for ruby 1.6.0 */
    rb_define_method(rb_cBigfloat, "nan?",      BigFloat_IsNaN, 0);
    rb_define_method(rb_cBigfloat, "infinite?", BigFloat_IsInfinite, 0);
    rb_define_method(rb_cBigfloat, "finite?",   BigFloat_IsFinite, 0);
	rb_define_method(rb_cBigfloat, "truncate",  BigFloat_truncate, -1);
}

static void
CheckAsign(x,y)
	VALUE x;
	VALUE y;
{
	if(x==y)
	rb_fatal("Bad assignment(the same object appears on both LHS and RHS).");
}

static VALUE
BigFloat_mode(self,which,val)
	VALUE self;
	VALUE which;
	VALUE val;
{
	unsigned short fo = VpGetException();
	unsigned short f;

	if(TYPE(which)!=T_FIXNUM)  return INT2FIX(fo);
	if(val!=Qfalse && val!=Qtrue) return INT2FIX(fo);

	f = (unsigned short)NUM2INT(which);
	if(f&VP_EXCEPTION_INFINITY) {
		fo = VpGetException();
		VpSetException((unsigned short)((val==Qtrue)?(fo|VP_EXCEPTION_INFINITY):
						 (fo&(~VP_EXCEPTION_INFINITY))));
	}
	if(f&VP_EXCEPTION_NaN) {
		fo = VpGetException();
		VpSetException((unsigned short)((val==Qtrue)?(fo|VP_EXCEPTION_NaN):
						 (fo&(~VP_EXCEPTION_NaN))));
	}
	fo = VpGetException();
	return INT2FIX(fo);
}

static U_LONG 
#ifdef HAVE_STDARG_PROTOTYPES
GetAddSubPrec(Real *a,Real *b)
#else
GetAddSubPrec(a,b)
	Real *a;
	Real *b;
#endif /* HAVE_STDARG_PROTOTYPES */
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
#ifdef HAVE_STDARG_PROTOTYPES
GetPositiveInt(VALUE v)
#else
GetPositiveInt(v)
	VALUE v;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	S_INT n;
	Check_Type(v, T_FIXNUM);
	n = NUM2INT(v);
	if(n <= 0) {
		rb_fatal("Zero or negative argument not permitted.");
	}
	return n;
}

static VALUE
#ifdef HAVE_STDARG_PROTOTYPES
ToValue(Real *p)
#else
ToValue(p)
	Real *p;
#endif /* HAVE_STDARG_PROTOTYPES */
{

#ifdef USE_FLOAT_VALUE
	VALUE v;
	if(VpIsNaN(p)) {
		VpException(VP_EXCEPTION_NaN,"Computation results to 'NaN'(Not a Number)",0);
		v = rb_float_new(VpGetDoubleNaN());
	} else if(VpIsPosInf(p)) {
		VpException(VP_EXCEPTION_INFINITY,"Computation results to 'Infinity'",0);
		v = rb_float_new(VpGetDoublePosInf());
	} else if(VpIsNegInf(p)) {
		VpException(VP_EXCEPTION_INFINITY,"Computation results to '-Infinity'",0);
		v = rb_float_new(VpGetDoubleNegInf());
	} else {
		v = (VALUE)p->obj;
	}
	return v;

#else /* ~USE_FLOAT_VALUE */
	if(VpIsNaN(p)) {
		VpException(VP_EXCEPTION_NaN,"Computation results to 'NaN'(Not a Number)",0);
	} else if(VpIsPosInf(p)) {
		VpException(VP_EXCEPTION_INFINITY,"Computation results to 'Infinity'",0);
	} else if(VpIsNegInf(p)) {
		VpException(VP_EXCEPTION_INFINITY,"Computation results to '-Infinity'",0);
	}
	return p->obj;
#endif /* ~USE_FLOAT_VALUE */
}

VP_EXPORT Real *
#ifdef HAVE_STDARG_PROTOTYPES
VpNewRbClass(U_LONG mx,char *str,VALUE klass)
#else
VpNewRbClass(mx,str,klass)
	U_LONG mx;
	char  *str;
	VALUE  klass;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	Real *pv = VpAlloc(mx,str);
	pv->obj = (VALUE)Data_Wrap_Struct(klass, 0, BigFloat_delete, pv);
	return pv;
}

VP_EXPORT Real *
#ifdef HAVE_STDARG_PROTOTYPES
VpCreateRbObject(U_LONG mx,char *str)
#else
VpCreateRbObject(mx,str)
	U_LONG mx;
	char  *str;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	Real *pv = VpAlloc(mx,str);
	pv->obj = (VALUE)Data_Wrap_Struct(rb_cBigfloat, 0, BigFloat_delete, pv);
	return pv;
}

static Real *
#ifdef HAVE_STDARG_PROTOTYPES
GetVpValue(VALUE v,int must)
#else
GetVpValue(v,must)
	VALUE v;
	int must;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	double dv;
	Real *pv;
	VALUE bg;
	char szD[128];

	switch(TYPE(v))
	{
	case T_DATA:
		if(RDATA(v)->dfree ==(void *) BigFloat_delete) {
			Data_Get_Struct(v, Real, pv);
			return pv;
		} else {
			goto SomeOneMayDoIt;
		}
		break;
	case T_FIXNUM:
		sprintf(szD, "%d", NUM2INT(v));
		return VpCreateRbObject(VpBaseFig() * 2 + 1, szD);
	case T_FLOAT:
		pv = VpCreateRbObject(VpDblFig()*2,"0");
		dv = RFLOAT(v)->value;
		/* From float */
		if (isinf(dv)) {
			VpException(VP_EXCEPTION_INFINITY,"Computation including infinity",0);
			if(dv==VpGetDoublePosInf()) {
				VpSetPosInf(pv);
			} else {
				VpSetNegInf(pv);
			}
		} else
		if (isnan(dv)) {
			VpException(VP_EXCEPTION_NaN,"Computation including NaN(Not a number)",0);
			VpSetNaN(pv);
		} else {
			if (VpIsNegDoubleZero(dv)) {
				VpSetNegZero(pv);
			} else if(dv==0.0) {
				VpSetPosZero(pv);
			} else if(dv==1.0) {
				VpSetOne(pv);
			} else if(dv==-1.0) {
				VpSetOne(pv);
				pv->sign = -pv->sign;
			} else {
				VpDtoV(pv,dv);
			}
		}
		return pv;
	case T_STRING:
		Check_SafeStr(v);
		return VpCreateRbObject(strlen(RSTRING(v)->ptr) + VpBaseFig() + 1,
								RSTRING(v)->ptr);
	case T_BIGNUM:
		bg = rb_big2str(v, 10);
		return VpCreateRbObject(strlen(RSTRING(bg)->ptr) + VpBaseFig() + 1,
								RSTRING(bg)->ptr);
	default:
		goto SomeOneMayDoIt;
	}

SomeOneMayDoIt:
	if(must) {
		rb_raise(rb_eTypeError, "%s can't be coerced into BigFloat",
		 rb_special_const_p(v)?
		 STR2CSTR(rb_inspect(v)):
		 rb_class2name(CLASS_OF(v)));
	}
	return NULL; /* NULL means to coerce */
}

static VALUE 
BigFloat_IsNaN(self)
	VALUE self;
{
	Real *p = GetVpValue(self,1);
	if(VpIsNaN(p))  return Qtrue;
	return Qfalse;
}

static VALUE
BigFloat_IsInfinite(self)
	VALUE self;
{
	Real *p = GetVpValue(self,1);
	if(VpIsInf(p)) return Qtrue;
	return Qfalse;
}

static VALUE
BigFloat_IsFinite(self)
	VALUE self;
{
	Real *p = GetVpValue(self,1);
	if(VpIsNaN(p)) return Qfalse;
	if(VpIsInf(p)) return Qfalse;
	return Qtrue;
}

static VALUE
BigFloat_to_i(self)
	VALUE self;
{
	ENTER(5);
	int e,n,i,nf;
	U_LONG v,b,j;
	char *psz,*pch;
	Real *p;
	
	GUARD_OBJ(p,GetVpValue(self,1));

	if(!VpIsDef(p)) return Qnil; /* Infinity or NaN not converted. */
	
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
		v = p->frac[i];
		b = VpBaseVal()/10;
		while(b) {
			j = v/b;
			*pch++ = (char)(j + '0');
			v -= j*b;
			b /= 10;
		}
	}
	*pch++ = 0;
	return rb_str2inum(psz,10);
}

static VALUE
BigFloat_induced_from(self,x)
	VALUE self;
	VALUE x;
{
	Real *p = GetVpValue(x,1);
	return p->obj;
}

static VALUE
BigFloat_coerce(self, other)
	VALUE self;
	VALUE other;
{
	ENTER(2);
	VALUE obj;
	Real *b;
	GUARD_OBJ(b,GetVpValue(other,1));
	obj = rb_ary_new();
	obj = rb_ary_push(obj, b->obj);
	obj = rb_ary_push(obj, self);
	return obj;
}

static VALUE
BigFloat_uplus(self)
	VALUE self;
{
	return self;
}

static VALUE
BigFloat_add(self, r)
	VALUE self;
	VALUE r;
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
BigFloat_sub(self, r)
	VALUE self;
	VALUE r;
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
#ifdef HAVE_STDARG_PROTOTYPES
BigFloatCmp(VALUE self,VALUE r)
#else
BigFloatCmp(self, r)
	VALUE self;
	VALUE r;
#endif /* HAVE_STDARG_PROTOTYPES */
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
BigFloat_zero(self)
	VALUE self;
{
	Real *a = GetVpValue(self,1);
	return VpIsZero(a) ? Qtrue : Qfalse;
}

static VALUE
BigFloat_nonzero(self)
	VALUE self;
{
	Real *a = GetVpValue(self,1);
	return VpIsZero(a) ? Qfalse : self;
}

static VALUE
BigFloat_comp(self, r)
	VALUE self;
	VALUE r;
{
	S_INT e;
	e = BigFloatCmp(self, r);
	if(e==999) return rb_float_new(VpGetDoubleNaN());
	return INT2FIX(e);
}

static VALUE
BigFloat_eq(self, r)
	VALUE self;
	VALUE r;
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
BigFloat_ne(self, r)
	VALUE self;
	VALUE r;
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
BigFloat_lt(self, r)
	VALUE self;
	VALUE r;
{
	S_INT e;
	e = BigFloatCmp(self, r);
	if(e==999) return Qfalse;
	return(e < 0) ? Qtrue : Qfalse;
}

static VALUE
BigFloat_le(self, r)
	VALUE self;
	VALUE r;
{
	S_INT e;
	e = BigFloatCmp(self, r);
	if(e==999) return Qfalse;
	return(e <= 0) ? Qtrue : Qfalse;
}

static VALUE
BigFloat_gt(self, r)
	VALUE self;
	VALUE r;
{
	S_INT e;
	e = BigFloatCmp(self, r);
	if(e==999) return Qfalse;
	return(e > 0) ? Qtrue : Qfalse;
}

static VALUE
BigFloat_ge(self, r)
	VALUE self;
	VALUE r;
{
	S_INT e;
	e = BigFloatCmp(self, r);
	if(e==999) return Qfalse;
	return(e >= 0) ? Qtrue : Qfalse;
}

static VALUE
BigFloat_neg(self, r)
	VALUE self;
	VALUE r;
{
	ENTER(5);
	Real *c, *a;
	GUARD_OBJ(a,GetVpValue(self,1));
	GUARD_OBJ(c,VpCreateRbObject(a->Prec *(VpBaseFig() + 1), "0"));
	VpAsgn(c, a, -1);
	return ToValue(c);
}

static VALUE
BigFloat_mult(self, r)
	VALUE self;
	VALUE r;
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
#ifdef HAVE_STDARG_PROTOTYPES
BigFloat_divide(Real **c,Real **res,Real **div,VALUE self,VALUE r)
#else
BigFloat_divide(c,res,div,self,r)
	Real **c;
	Real **res;
	Real **div;
	VALUE self;
	VALUE r;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	ENTER(5);
	Real *a, *b;
	U_LONG mx;

	GUARD_OBJ(a,GetVpValue(self,1));
	b = GetVpValue(r,0);
	if(!b) return DoSomeOne(self,r);
	SAVE(b);
	*div = b;
	mx =(a->MaxPrec + b->MaxPrec) *VpBaseFig();
	GUARD_OBJ((*c),VpCreateRbObject(mx, "0"));
	GUARD_OBJ((*res),VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
	VpDivd(*c, *res, a, b);
	return (VALUE)0;
}

static VALUE
BigFloat_div(self, r)
	VALUE self;
	VALUE r;
{
	ENTER(5);
	Real *c=NULL, *res=NULL, *div = NULL;
	r = BigFloat_divide(&c, &res, &div, self, r);
	SAVE(c);SAVE(res);SAVE(div);
	if(r!=(VALUE)0) return r; /* coerced by other */
	if(res->frac[0]*2>=div->frac[0]) {
		/* Round up */
		VpRdup(c);
	}
	return ToValue(c);
}

/*
 * %: mod = a%b = a - (a.to_f/b).floor * b
 * div = (a.to_f/b).floor
 */
static VALUE
#ifdef HAVE_STDARG_PROTOTYPES
BigFloat_DoDivmod(VALUE self,VALUE r,Real **div,Real **mod) 
#else
BigFloat_DoDivmod(self, r, div, mod) 
	VALUE self;
	VALUE r;
	Real **div;
	Real **mod;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	ENTER(8);
	Real *c=NULL, *d=NULL, *res=NULL;
	Real *a, *b;
	U_LONG mx;

	GUARD_OBJ(a,GetVpValue(self,1));
	b = GetVpValue(r,0);
	if(!b) return DoSomeOne(self,r);
	SAVE(b);

	mx = a->Prec;
	if(mx<b->Prec) mx = b->Prec;
	mx =(mx + 1) * VpBaseFig();
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	GUARD_OBJ(res,VpCreateRbObject((mx+1) * 2 +(VpBaseFig() + 1), "#0"));
	VpDivd(c, res, a, b);
	mx = c->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(d,VpCreateRbObject(mx, "0"));
	VpRound(d,c,1,3,0);
	VpMult(res,d,b);
	VpAddSub(c,a,res,-1);
	*div = d;
	*mod = c;
	return (VALUE)0;
}

static VALUE
BigFloat_mod(self, r) /* %: a%b = a - (a.to_f/b).floor * b */
	VALUE self;
	VALUE r;
{
	ENTER(3);
	VALUE obj;
	Real *div=NULL, *mod=NULL;

	obj = BigFloat_DoDivmod(self,r,&div,&mod); 
	SAVE(div);SAVE(mod);
	if(obj!=(VALUE)0) return obj;
	return ToValue(mod);
}

static VALUE
BigFloat_divremain(self,r,dv,rv)
	VALUE self;
	VALUE r;
	Real **dv;
	Real **rv;
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
 
	VpRound(d,c,1,1,0); /* 1: round off */
	
	VpFrac(f, c);
	VpMult(rr,f,b);
	VpAddSub(ff,res,rr,1);

	*dv = d;
	*rv = ff;
	return (VALUE)0;
}

static VALUE
BigFloat_remainder(self, r) /* remainder */
	VALUE self;
	VALUE r;
{
	VALUE  f;
	Real  *d,*rv;
	f = BigFloat_divremain(self,r,&d,&rv);
	if(f!=(VALUE)0) return f;
	return ToValue(rv);
}

static VALUE
BigFloat_divmod(self, r)
	VALUE self;
	VALUE r;
{
	ENTER(5);
	VALUE obj;
	Real *div=NULL, *mod=NULL;

	obj = BigFloat_DoDivmod(self,r,&div,&mod); 
	if(obj!=(VALUE)0) return obj;
	SAVE(div);SAVE(mod);
	obj = rb_ary_new();
	rb_ary_push(obj, ToValue(div));
	rb_ary_push(obj, ToValue(mod));
	return obj;
}

static VALUE
BigFloat_divmod2(self,b,n)
	VALUE self;
	VALUE b;
	VALUE n;
{
	ENTER(10);
	VALUE obj;
	Real *res=NULL;
	Real *av=NULL, *bv=NULL, *cv=NULL;
	U_LONG mx = (U_LONG)GetPositiveInt(n)+VpBaseFig();

	obj = rb_ary_new();
	GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
	GUARD_OBJ(av,GetVpValue(self,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	mx = cv->MaxPrec+1;
	GUARD_OBJ(res,VpCreateRbObject((mx * 2 + 1)*VpBaseFig(), "#0"));
	VpDivd(cv,res,av,bv);
	obj = rb_ary_push(obj, ToValue(cv));
	obj = rb_ary_push(obj, ToValue(res));

	return obj;
}

static VALUE
BigFloat_divmod4(self,c,r,a,b)
	VALUE self;
	VALUE c;
	VALUE r;
	VALUE a;
	VALUE b;
{
	ENTER(10);
	U_LONG f;
	Real *res=NULL;
	Real *av=NULL, *bv=NULL, *cv=NULL;
	CheckAsign(c,a);
	CheckAsign(c,b);
	CheckAsign(r,a);
	CheckAsign(r,b);
	CheckAsign(r,c);
	GUARD_OBJ(cv,GetVpValue(c,1));
	GUARD_OBJ(av,GetVpValue(a,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	GUARD_OBJ(res,GetVpValue(r,1));
	f = VpDivd(cv,res,av,bv);
	return INT2FIX(f);
}

static VALUE
BigFloat_asign(self,c,a,f)
	VALUE self;
	VALUE c;
	VALUE a;
	VALUE f;
{
	ENTER(5);
	int v;
	Real *av;
	Real *cv;
	CheckAsign(c,a);
	Check_Type(f, T_FIXNUM);
	GUARD_OBJ(cv,GetVpValue(c,1));
	GUARD_OBJ(av,GetVpValue(a,1));
	v = VpAsgn(cv,av,NUM2INT(f));
	return INT2NUM(v);
}

static VALUE
BigFloat_asign2(self,n,f)
	VALUE self;
	VALUE n;
	VALUE f;
{
	ENTER(5);
	Real *cv;
	Real *av;
	U_LONG mx = (U_LONG)GetPositiveInt(n);
	Check_Type(f, T_FIXNUM);
	GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
	GUARD_OBJ(av,GetVpValue(self,1));
	VpAsgn(cv,av,NUM2INT(f));
	return ToValue(cv);
}

static VALUE
BigFloat_add2(self,b,n)
	VALUE self;
	VALUE b;
	VALUE n;
{
	ENTER(5);
	Real *av;
	Real *bv;
	Real *cv;
	U_LONG mx = (U_LONG)GetPositiveInt(n);
	GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
	GUARD_OBJ(av,GetVpValue(self,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	VpAddSub(cv,av,bv,1);  
	return ToValue(cv);
}

static VALUE
BigFloat_add3(self,c,a,b)
	VALUE self;
	VALUE c;
	VALUE a;
	VALUE b;
{
	ENTER(5);
	Real *av;
	Real *bv;
	Real *cv;
	U_LONG f;
	CheckAsign(c,a);
	CheckAsign(c,b);
	GUARD_OBJ(cv,GetVpValue(c,1));
	GUARD_OBJ(av,GetVpValue(a,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	f = VpAddSub(cv,av,bv,1);
	return INT2NUM(f);
}

static VALUE
BigFloat_sub2(self,b,n)
	VALUE self;
	VALUE b;
	VALUE n;
{
	ENTER(5);
	Real *av;
	Real *bv;
	Real *cv;
	U_LONG mx = (U_LONG)GetPositiveInt(n);
	GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
	GUARD_OBJ(av,GetVpValue(self,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	VpAddSub(cv,av,bv,-1);
	return ToValue(cv);
}

static VALUE
BigFloat_sub3(self,c,a,b)
	VALUE self;
	VALUE c;
	VALUE a;
	VALUE b;
{
	ENTER(5);
	Real *av;
	Real *bv;
	Real *cv;
	U_LONG f;
	CheckAsign(c,a);
	CheckAsign(c,b);
	GUARD_OBJ(cv,GetVpValue(c,1));
	GUARD_OBJ(av,GetVpValue(a,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	f = VpAddSub(cv,av,bv,-1);
	return INT2NUM(f);
}

static VALUE
BigFloat_mult2(self,b,n)
	VALUE self;
	VALUE b;
	VALUE n;
{
	ENTER(5);
	Real *av;
	Real *bv;
	Real *cv;
	U_LONG mx = (U_LONG)GetPositiveInt(n);
	GUARD_OBJ(cv,VpCreateRbObject(mx,"0"));
	GUARD_OBJ(av,GetVpValue(self,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	VpMult(cv,av,bv);
	return ToValue(cv);
}

static VALUE
BigFloat_mult3(self,c,a,b)
	VALUE self;
	VALUE c;
	VALUE a;
	VALUE b;
{
	ENTER(5);
	Real *av;
	Real *bv;
	Real *cv;
	U_LONG f;
	CheckAsign(c,a);
	CheckAsign(c,b);
	GUARD_OBJ(cv,GetVpValue(c,1));
	GUARD_OBJ(av,GetVpValue(a,1));
	GUARD_OBJ(bv,GetVpValue(b,1));
	f = VpMult(cv,av,bv);
	return INT2NUM(f);
}

static VALUE
BigFloat_dup(self)
	VALUE self;
{
	ENTER(5);
	Real *c, *a;
	U_LONG mx;
	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpAsgn(c, a, 1);
	return ToValue(c);
}

static VALUE
BigFloat_abs(self)
	VALUE self;
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
BigFloat_sqrt(self, nFig)
	VALUE self;
	VALUE nFig;
{
	ENTER(5);
	Real *c, *a;
	S_INT mx, n;

	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	mx *= 2;

	n = GetPositiveInt(nFig) + VpBaseFig();
	if(mx < n) mx = n;
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpSqrt(c, a);
	return ToValue(c);
}

static VALUE
BigFloat_fix(self)
	VALUE self;
{
	ENTER(5);
	Real *c, *a;
	U_LONG mx;

	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpRound(c,a,1,1,0); /* 1: round off */
	return ToValue(c);
}

static VALUE
BigFloat_round(argc,argv,self)
	int   argc;
	VALUE *argv;
	VALUE self;
{
	ENTER(5);
	Real *c, *a;
	int iLoc;
	int sw;
	U_LONG mx;
	VALUE vLoc;

	if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
		iLoc = 0;
	} else {
		Check_Type(vLoc, T_FIXNUM);
		iLoc = NUM2INT(vLoc);
	}
	sw = 2;

	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpRound(c,a,sw,1,iLoc);
	return ToValue(c);
}

static VALUE
BigFloat_truncate(argc,argv,self)
	int   argc;
	VALUE *argv;
	VALUE self;
{
	ENTER(5);
	Real *c, *a;
	int iLoc;
	int sw;
	U_LONG mx;
	VALUE vLoc;

	if(rb_scan_args(argc,argv,"01",&vLoc)==0) {
		iLoc = 0;
	} else {
		Check_Type(vLoc, T_FIXNUM);
		iLoc = NUM2INT(vLoc);
	}
	sw = 1; /* truncate */

	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpRound(c,a,sw,1,iLoc);
	return ToValue(c);
}

static VALUE
BigFloat_frac(self)
	VALUE self;
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
BigFloat_floor(argc,argv,self)
	int   argc;
	VALUE *argv;
	VALUE self;
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
		iLoc = NUM2INT(vLoc);
	}

	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpRound(c,a,1,3,iLoc);
	return ToValue(c);
}

static VALUE
BigFloat_ceil(argc,argv,self)
	int   argc;
	VALUE *argv;
	VALUE self;
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
		iLoc = NUM2INT(vLoc);
	}

	GUARD_OBJ(a,GetVpValue(self,1));
	mx = a->Prec *(VpBaseFig() + 1);
	GUARD_OBJ(c,VpCreateRbObject(mx, "0"));
	VpRound(c,a,1,2,iLoc);
	return ToValue(c);
}


static VALUE
BigFloat_to_s(self)
	VALUE self;
{
	ENTER(5);
	Real *vp;
	char *psz;

	GUARD_OBJ(vp,GetVpValue(self,1));
	psz = ALLOCA_N(char,(unsigned int)VpNumOfChars(vp));
	VpToString(vp, psz, 0);
	return rb_str_new2(psz);
}

static VALUE
BigFloat_to_s2(self, f)
	VALUE self;
	VALUE f;
{
	ENTER(5);
	Real *vp;
	char *psz;
	U_LONG nc;
	S_INT mc;
	GUARD_OBJ(vp,GetVpValue(self,1));
	nc = VpNumOfChars(vp);
	mc = GetPositiveInt(f);
	nc +=(nc + mc - 1) / mc;
	psz = ALLOCA_N(char,(unsigned int)nc);
	VpToString(vp, psz, mc);
	return rb_str_new2(psz);
}

static VALUE
BigFloat_to_parts(self)
	VALUE self;
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
		int i=0;
		s = -1;
		while(psz1[i]=psz1[i+1]) i++ ;
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
BigFloat_exponent(self)
	VALUE self;
{
	S_LONG e = VpExponent10(GetVpValue(self,1));
	return INT2NUM(e);
}

static VALUE
BigFloat_inspect(self)
	VALUE self;
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
	sprintf(pszAll,"[BigFloat:%x,'%s',%u(%u)]",self,psz1,VpPrec(vp)*VpBaseFig(),VpMaxPrec(vp)*VpBaseFig());

	obj = rb_str_new2(pszAll);
	return obj;
}

static VALUE
BigFloat_power(self, p)
	VALUE self;
	VALUE p;
{
	ENTER(5);
	Real *x, *y;
	S_LONG mp, ma, n;

	Check_Type(p, T_FIXNUM);
	n = NUM2INT(p);
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

static void
BigFloat_delete(pv)
	Real *pv;
{
	VpFree(pv);
}

static VALUE
BigFloat_new(argc,argv,self)
	int   argc;
	VALUE *argv;
	VALUE self;
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
	Check_SafeStr(iniValue);
	GUARD_OBJ(pv,VpNewRbClass(mf, RSTRING(iniValue)->ptr,self));
	return ToValue(pv);
}

static VALUE
BigFloat_limit(argc,argv,self)
	int   argc;
	VALUE *argv;
	VALUE self;
{
	VALUE  nFig;
	VALUE  nCur = INT2NUM(VpGetPrecLimit());

	if(rb_scan_args(argc,argv,"01",&nFig)==1) {
		Check_Type(nFig, T_FIXNUM);
		VpSetPrecLimit(NUM2INT(nFig));
	}
	return nCur;
}

static VALUE
BigFloat_e(self, nFig)
	VALUE self;
	VALUE nFig;
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
BigFloat_pai(self, nFig)
	VALUE self;
	VALUE nFig;
{
	ENTER(5);
	Real *pv;
	S_LONG mf;

	mf = GetPositiveInt(nFig);
	GUARD_OBJ(pv,VpCreateRbObject(mf, "0"));
	VpPai(pv);
	return ToValue(pv);
}

static VALUE
BigFloat_exp(self, nFig)
	VALUE self;
	VALUE nFig;
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
BigFloat_sign(self)
	VALUE self;
{ /* sign */
	int s = GetVpValue(self,1)->sign;
	return INT2FIX(s);
}

static VALUE
BigFloat_sincos(self, nFig)
	VALUE self;
	VALUE nFig;
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

/*
 *
 *  ============================================================================
 *
 *  vp_ routines begins here
 *
 *  ============================================================================
 *
 */
#ifdef _DEBUG
static int gfDebug = 0;         /* Debug switch */
static int gfCheckVal = 1;      /* Value checking flag in VpNmlz()  */
#endif /* _DEBUG */

static U_LONG gnPrecLimit = 0;  /* Global upper limit of the precision newly allocated */
static S_LONG BASE_FIG = 4;     /* =log10(BASE)  */
static U_LONG BASE = 10000L;    /* Base value(value must be 10**BASE_FIG) */
				/* The value of BASE**2 + BASE must be represented */
				/* within one U_LONG. */
static U_LONG HALF_BASE = 5000L;/* =BASE/2  */
static S_LONG DBLE_FIG = 8;	/* figure of double */
static U_LONG BASE1 = 1000L;	/* =BASE/10  */

static Real *VpConstOne;	/* constant 1.0 */
static Real *VpPt5;		/* constant 0.5 */
static U_LONG maxnr = 100;	/* Maximum iterations for calcurating sqrt. */
				/* used in VpSqrt() */

#ifdef _DEBUG
static int gnAlloc=0; /* Memory allocation counter */
#endif /* _DEBUG */

/*
 * EXCEPTION Handling.
 */
static unsigned short gfDoException = 0; /* Exception flag */

static unsigned short
VpGetException()
{
	return gfDoException;
}

static void
#ifdef HAVE_STDARG_PROTOTYPES
VpSetException(unsigned short f)
#else
VpSetException(f)
	unsigned short f;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	gfDoException = f;
}

/* These 2 functions added at v1.1.7 */
VP_EXPORT U_LONG VpGetPrecLimit()
{
	return gnPrecLimit;
}

#ifdef HAVE_STDARG_PROTOTYPES
VP_EXPORT U_LONG VpSetPrecLimit(U_LONG n)
#else
VP_EXPORT U_LONG VpSetPrecLimit()
U_LONG n;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	U_LONG s = gnPrecLimit;
	gnPrecLimit = n;
	return s;
}

/*
 *  0.0 & 1.0 generator 
 *	These gZero_..... and gOne_..... can be any name 
 *	referenced from nowhere except Zero() and One().
 *	gZero_..... and gOne_..... must have global scope. 
 */
double gZero_ABCED9B1_CE73__00400511F31D = 0.0;
double gOne_ABCED9B4_CE73__00400511F31D  = 1.0;
static double Zero() { return gZero_ABCED9B1_CE73__00400511F31D;}
static double One()	 { return gOne_ABCED9B4_CE73__00400511F31D;}

VP_EXPORT S_LONG VpBaseFig()    { return BASE_FIG;}
VP_EXPORT S_LONG VpDblFig()     { return DBLE_FIG;}
VP_EXPORT U_LONG VpBaseVal()    { return BASE;}

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
VpGetDoubleNaN() /* Returns the value of NaN */
{
	static double fNaN = 0.0;
	if(fNaN==0.0) fNaN = Zero()/Zero();
	return fNaN;
}

VP_EXPORT double
VpGetDoublePosInf() /* Returns the value of +Infinity */
{
	static double fInf = 0.0;
	if(fInf==0.0) fInf = One()/Zero();
	return fInf;
}

VP_EXPORT double
VpGetDoubleNegInf() /* Returns the value of -Infinity */
{
	static double fInf = 0.0;
	if(fInf==0.0) fInf = -(One()/Zero());
	return fInf;
}

static int
#ifdef HAVE_STDARG_PROTOTYPES
MemCmp(unsigned char *a,unsigned char *b,int n)
#else
MemCmp(a,b,n)
	unsigned char *a;
	unsigned char *b;
	int n;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	int i;
	for(i=0;i<n;++i) if(*a++ != *b++) return 1;
	return 0;
}

VP_EXPORT double
VpGetDoubleNegZero() /* Returns the value of -0 */
{
	static double nzero = 1000.0;
	if(nzero!=0.0) nzero = (One()/VpGetDoubleNegInf());
	return nzero;
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpIsNegDoubleZero(double v)
#else
VpIsNegDoubleZero(v)
double v;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	double z = VpGetDoubleNegZero(); 
	return MemCmp((unsigned char *)&v,(unsigned char *)&z,sizeof(v))==0;
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpException(unsigned short f,char *str,int always)
#else
VpException(f,str,always)
	unsigned short f;
	char *str;
	int always; /* raise exception even gfDoException==0 */
#endif /* HAVE_STDARG_PROTOTYPES */
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
#ifdef HAVE_STDARG_PROTOTYPES
VpIsDefOP(Real *c,Real *a,Real *b,int sw)
#else
VpIsDefOP(c,a,b,sw)
	Real *c;
	Real *a;
	Real *b;
	int  sw;
#endif /* HAVE_STDARG_PROTOTYPES */
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


VP_EXPORT U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpNumOfChars(Real *vp)
#else
VpNumOfChars(vp)
	Real *vp;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *	returns number of chars needed to represent vp.
 */
{
	if(vp == NULL)   return BASE_FIG*2+6;
	if(!VpIsDef(vp)) return 32; /* not sure,may be OK */
	return     BASE_FIG *(vp->Prec + 2)+6; /* 3: sign + exponent chars */
}

VP_EXPORT U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpInit(U_LONG BaseVal)
#else
VpInit(BaseVal)
	U_LONG BaseVal;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 * Initializer for Vp routines and constants used. 
 * [Input] 
 *   BaseVal: Base value(asigned to BASE) for Vp calculation.
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
		printf("VpInit: BaseVal   = %u\n", BaseVal);
		printf("  BASE   = %u\n", BASE);
		printf("  HALF_BASE = %u\n", HALF_BASE);
		printf("  BASE1  = %u\n", BASE1);
		printf("  BASE_FIG  = %u\n", BASE_FIG);
		printf("  DBLE_FIG  = %u\n", DBLE_FIG);
	}
#endif /* _DEBUG */

	return DBLE_FIG;
}

/* If exponent overflows,then raise exception or returns 0 */
static int
#ifdef HAVE_STDARG_PROTOTYPES
AddExponent(Real *a,S_INT n)
#else
AddExponent(a,n)
	Real *a;
	S_INT n;
#endif /* HAVE_STDARG_PROTOTYPES */
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

#ifdef _DEBUG
/*
 *********************** DEBUGGING routines
 */
void P_Set(void *p);
void P_Free(void *p);
void P_Set(void *p)
{
}
void P_Free(void *p)
{
}
#endif /* _DEBUG */

static void *
#ifdef HAVE_STDARG_PROTOTYPES
VpMemAlloc(U_LONG mb)
#else
VpMemAlloc(mb)
	U_LONG mb;
#endif /* HAVE_STDARG_PROTOTYPES */
{
#ifdef USE_XMALLOC
	void *p = xmalloc((unsigned int)mb);
#else
	void *p = malloc((unsigned int)mb);
#endif /* ~USE_XMALLOC */
	if(!p) {
		VpException(VP_EXCEPTION_MEMORY,"failed to allocate memory",1);
	}
	memset(p,0,mb);
#ifdef _DEBUG
	++gnAlloc;
	P_Set(p);
#endif /* _DEBUG */
	return p;
}

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpFree(Real *pv)
#else
VpFree(pv)
	Real *pv;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	if(pv != NULL) {
#ifdef _DEBUG
		if(--gnAlloc<=0) {
			extern int getch();
			printf("\n=========== VpFree: All memory allocated so far freed ===========\n");
			if(gnAlloc<0) {
				printf("\n???????? VpFree(System Error): Too many free count. ????????\n");
				gnAlloc = 0;
			}
			getch();
			P_Free(pv);
		}
#endif /* _DEBUG */
#ifdef USE_XFREE
		xfree(pv);
#else
		free(pv);
#endif /* USE_XFREE */
	}
}


VP_EXPORT Real *
#ifdef HAVE_STDARG_PROTOTYPES
VpAlloc(U_LONG mx, char *szVal)
#else
VpAlloc(mx, szVal)
	U_LONG mx;
	char *szVal;
#endif /* HAVE_STDARG_PROTOTYPES */
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
{
	U_LONG i, ni, ipf, nf, ipe, ne, nalloc;
	char v;
	int  sign=1;
	Real *vp = NULL;
	U_LONG mf = VpGetPrecLimit();
	mx = (mx + BASE_FIG - 1) / BASE_FIG + 1;	/* Determine allocation unit. */
    if(szVal) {
		if(*szVal!='#') {
 			if(mf) {
				mf = (mf + BASE_FIG - 1) / BASE_FIG + 1;
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
		vp->MaxPrec = mx;	/* set max precision */
		VpSetZero(vp,1);	/* initialize vp to zero. */
		return vp;
	}
	/* Check on Inf & NaN */
	if(MemCmp(szVal,"+Infinity",sizeof("+Infinity"))==0 ||
	   MemCmp(szVal, "Infinity",sizeof ("Infinity"))==0 ) {
		vp = (Real *) VpMemAlloc(sizeof(Real) + sizeof(U_LONG));
		vp->MaxPrec = 1;	/* set max precision */
		VpSetPosInf(vp);
		return vp;
	}
	if(MemCmp(szVal,"-Infinity",sizeof("-Infinity"))==0) {
		vp = (Real *) VpMemAlloc(sizeof(Real) + sizeof(U_LONG));
		vp->MaxPrec = 1;	/* set max precision */
		VpSetNegInf(vp);
		return vp;
	}
	if(MemCmp(szVal,"NaN",sizeof("NaN"))==0) {
		vp = (Real *) VpMemAlloc(sizeof(Real) + sizeof(U_LONG));
		vp->MaxPrec = 1;	/* set max precision */
		VpSetNaN(vp);
		return vp;
	}

	/* check on number szVal[] */
	i = SkipWhiteChar(szVal);
	if  (szVal[i] == '-') {sign=-1;++i;}
	else if(szVal[i] == '+')  ++i;
	/* Skip digits */
	ni = 0;			/* digits in mantissa */
	while(v = szVal[i]) {
		if((v > '9') ||(v < '0')) break;
		++i;
		++ni;
	}
	nf = 0;
	ipf = 0;
	ipe = 0;
	ne = 0;
	if(v) {
		/* other than digit nor \0 */
		if(szVal[i] == '.') {	/* xxx. */
			++i;
			ipf = i;
			while(v = szVal[i]) {	/* get fraction part. */
				if((v > '9') ||(v < '0')) break;
				++i;
				++nf;
			}
		}
		ipe = 0;		/* Exponent */

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
	nalloc =(ni + nf + BASE_FIG - 1) / BASE_FIG + 1;	/* set effective allocation  */
	/* units for szVal[]  */
	if(mx <= 0) mx = 1;
	nalloc = Max(nalloc, mx);
	mx = nalloc;
	vp =(Real *) VpMemAlloc(sizeof(Real) + mx * sizeof(U_LONG));
	/* xmalloc() alway returns(or throw interruption) */
	vp->MaxPrec = mx;		/* set max precision */
	VpSetZero(vp,sign);
	VpCtoV(vp, szVal, ni, &(szVal[ipf]), nf, &(szVal[ipe]), ne);
	return vp;
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpAsgn(Real *c,Real *a,int isw)
#else
VpAsgn(c, a, isw)
	Real *c;
	Real *a;
	int isw;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 * Asignment(c=a). 
 * [Input] 
 *   a   ... RHSV 
 *   isw ... switch for assignment. 
 *    c = a  when isw =  1 or 2
 *    c = -a when isw = -1 or -1
 *    when |isw|==1 
 *    if c->MaxPrec < a->Prec,then round up 
 *    will not be performed. 
 * [Output] 
 *  c  ... LHSV 
 */
{
	U_LONG j, n;
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
		c->exponent = a->exponent;	/* store  exponent */
		VpSetSign(c,(isw*VpGetSign(a)));	/* set sign */
		n =(a->Prec < c->MaxPrec) ?(a->Prec) :(c->MaxPrec);
		c->Prec = n;
		for(j=0;j < n; ++j) c->frac[j] = a->frac[j];
		if(isw < 0) isw = -isw;
		if(isw == 2) {
			if(a->MaxPrec>n) {
				if((c->Prec < a->Prec) &&
				   (a->frac[n] >= HALF_BASE)) VpRdup(c);	/* round up/off */
			}
		}
	} else {
		/* The value of 'a' is zero.  */
		VpSetZero(c,isw*VpGetSign(a));
		return 1;
	}
	VpNmlz(c);
	return c->Prec*BASE_FIG;
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpAddSub(Real *c,Real *a,Real *b,int operation)
#else
VpAddSub(c, a, b, operation)
	Real *c;
	Real *a;
	Real *b;
	int operation;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *   c = a + b  when operation =  1 or 2
 *  = a - b  when operation = -1 or -2.
 *   Returns number of significant digits of c
 */
{
	S_INT sw, isw;
	Real *a_ptr, *b_ptr;
	U_LONG register n, na, nb, i;

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
	else     sw =  1;

	/* compare absolute value. As a result,|a_ptr|>=|b_ptr| */
	if(a->exponent > b->exponent) {
		a_ptr = a;
		b_ptr = b;
	} 		/* |a|>|b| */
	else if(a->exponent < b->exponent) {
		a_ptr = b;
		b_ptr = a;
	}				/* |a|<|b| */
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
			VpSetZero(c,1);		/* abs(a)=abs(b) and operation = '-'  */
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
	if(isw) {			/* addition */
		VpSetSign(c,(S_INT)1);
		VpAddAbs(a_ptr, b_ptr, c);
		VpSetSign(c,isw / 2);
	} else {			/* subtraction */
		VpSetSign(c,(S_INT)1);
		VpSubAbs(a_ptr, b_ptr, c);
		if(a_ptr == a) {
			VpSetSign(c,VpGetSign(a));
		} else	{
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

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpAddAbs(Real *a,Real *b,Real *c)
#else
VpAddAbs(a, b, c)
	Real *a;
	Real *b;
	Real *c;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 * Addition of two variable precisional variables 
 * a and b assuming abs(a)>abs(b). 
 *   c = abs(a) + abs(b) ; where |a|>=|b|
 */
{
	U_LONG word_shift;
	U_LONG round;
	U_LONG carry;
	U_LONG ap;
	U_LONG bp;
	U_LONG cp;
	U_LONG register a_pos;
	U_LONG register b_pos;
	U_LONG register c_pos;
	U_LONG av, bv;

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

	round =((av + bv) >= HALF_BASE) ? 1 : 0;

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
	carry = 0;	/* set first carry be zero */

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

	if(round) VpRdup(c);		/* Roundup and normalize. */
	else 	  VpNmlz(c);		/* normalize the result */
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

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpSubAbs(Real *a,Real *b,Real *c)
#else
VpSubAbs(a,b,c)
	Real *a;
	Real *b;
	Real *c;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 * c = abs(a) - abs(b)
 */
{
	U_LONG register word_shift;
	U_LONG round;
	U_LONG borrow;
	U_LONG ap;
	U_LONG bp;
	U_LONG cp;
	U_LONG register a_pos;
	U_LONG register b_pos;
	U_LONG register c_pos;
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
		round =((av -= bv) >= HALF_BASE) ? 1 : 0;
		borrow = 0;
	} else {
		round = 0;
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
	if(round) VpRdup(c);		/* Round up and normalize */
	else   VpNmlz(c);		/* normalize the result */
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

static U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpSetPTR(Real *a,Real *b,Real *c,U_LONG *a_pos,U_LONG *b_pos,U_LONG *c_pos,U_LONG *av,U_LONG *bv)
#else
VpSetPTR(a, b, c, a_pos, b_pos, c_pos, av, bv)
	Real *a;
	Real *b;
	Real *c;
	U_LONG *a_pos;
	U_LONG *b_pos;
	U_LONG *c_pos;
	U_LONG *av;
	U_LONG *bv;
#endif /* HAVE_STDARG_PROTOTYPES */
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
{
	U_LONG left_word, right_word, word_shift;
	c->frac[0] = 0;
	*av = *bv = 0;
	word_shift =((a->exponent) -(b->exponent));
	left_word = b->Prec + word_shift;
	right_word = Max((a->Prec),left_word);
	left_word =(c->MaxPrec) - 1;	/* -1 ... prepare for round up */
	/*
	 * check if 'round off' is needed. 
	 */
	if(right_word > left_word) {	/* round off ? */
		/*--------------------------------- 
		 *  Actual size of a = xxxxxxAxx
		 *  Actual size of b = xxxBxxxxx 
		 *  Max. size of   c = xxxxxx 
		 *  Round off  =   |-----| 
		 *  c_pos   =   | 
		 *  right_word    =   | 
		 *  a_pos   =    |
		 */
		*c_pos = right_word = left_word + 1;	/* Set resulting precision */
		/* be equal to that of c */
		if((a->Prec) >=(c->MaxPrec)) {
			/*
			 *   a =  xxxxxxAxxx 
			 *   c =  xxxxxx 
			 *  a_pos =  | 
			 */
			*a_pos = left_word;
			*av = a->frac[*a_pos];	/* av is 'A' shown in above. */
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
	} else {			/* The MaxPrec of c - 1 > The Prec of a + b  */
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

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpMult(Real *c,Real *a,Real *b)
#else
VpMult(c, a, b)
	Real *c;
	Real *a;
	Real *b;
#endif /* HAVE_STDARG_PROTOTYPES */
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
{
	U_LONG MxIndA, MxIndB, MxIndAB, MxIndC;
	U_LONG register ind_c, i, nc;
	U_LONG register ind_as, ind_ae, ind_bs, ind_be;
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

	if((a->Prec == 1) &&(a->frac[0] == 1) &&(a->exponent == 1)) {
		VpAsgn(c, b, VpGetSign(a));
		goto Exit;
	}
	if((b->Prec == 1) &&(b->frac[0] == 1) &&(b->exponent == 1)) {
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

	if(MxIndC < MxIndAB) {	/* The Max. prec. of c < Prec(a)+Prec(b) */
		w = c;
		c = VpAlloc((U_LONG)((MxIndAB + 1) * BASE_FIG), "#0");
		MxIndC = MxIndAB;
	}

	/* set LHSV c info */

	c->exponent = a->exponent;	/* set exponent */
	if(!AddExponent(c,b->exponent)) return 0;
	VpSetSign(c,VpGetSign(a)*VpGetSign(b));	/* set sign  */
	Carry = 0;
	nc = ind_c = MxIndAB;
	for(i = 0; i <= nc; i++) c->frac[i] = 0;		/* Initialize c  */
	c->Prec = nc + 1;		/* set precision */
	for(nc = 0; nc < MxIndAB; ++nc, --ind_c) {
		if(nc < MxIndB) {	/* The left triangle of the Fig. */
			ind_as = MxIndA - nc;
			ind_ae = MxIndA;
			ind_bs = MxIndB;
			ind_be = MxIndB - nc;
		} else if(nc <= MxIndA) {	/* The middle rectangular of the Fig. */
			ind_as = MxIndA - nc;
			ind_ae = MxIndA -(nc - MxIndB);
			ind_bs = MxIndB;
			ind_be = 0;
		} else if(nc > MxIndA) {	/*  The right triangle of the Fig. */
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

	VpNmlz(c);			/* normalize the result */
	if(w != NULL) {		/* free work variable */
		VpAsgn(w, c, 2);
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

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpDivd(Real *c,Real *r,Real *a,Real *b)
#else
VpDivd(c, r, a, b)
	Real *c;
	Real *r;
	Real *a;
	Real *b;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *   c = a / b,  remainder = r 
 */
{
	U_LONG word_a, word_b, word_c, word_r;
	U_LONG register i, n, ind_a, ind_b, ind_c, ind_r;
	U_LONG register nLoop;
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

	if((b->Prec == 1) &&(b->frac[0] == 1) &&(b->exponent == 1)) {
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
			borrow = 0;		/* quotient=1, then just r-b */
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
	VpNmlz(c);			/* normalize c */
	r->Prec = word_r;
	r->exponent = a->exponent;
	if(!AddExponent(r,(S_LONG)1)) return 0;
	VpSetSign(r,VpGetSign(a));
	VpNmlz(r);			/* normalize r(remainder) */
	goto Exit;

space_error:
	rb_fatal("ERROR(VpDivd): space for remainder too small.\n");
#ifdef _DEBUG
	if(gfDebug) {
		printf("   word_a=%d\n", word_a);
		printf("   word_b=%d\n", word_b);
		printf("   word_c=%d\n", word_c);
		printf("   word_r=%d\n", word_r);
		printf("   ind_r =%d\n", ind_r);
	}
#endif /* _DEBUG */

Exit:
#ifdef _DEBUG
	if(gfDebug) {
		VPrint(stdout, " VpDivd(c=a/b), c=% \n", c);
		VPrint(stdout, "    r=% \n", r);
	}
#endif /* _DEBUG */
	return c->Prec*BASE_FIG;
}

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpNmlz(Real *a)
#else
VpNmlz(a)
	Real *a;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *  Input  a = 00000xxxxxxxx En(5 preceeding zeros) 
 *  Output a = xxxxxxxx En-5 
 */
{
	U_LONG register ind_a, i, j;
	if(VpIsZero(a)) {
		VpSetZero(a,VpGetSign(a));
		return 1;
	}
	ind_a = a->Prec;
	while(ind_a--) {
		if(a->frac[ind_a]) {
			a->Prec = ind_a + 1;
			i = j = 0;
			while(a->frac[i] == 0) ++i;		/* skip the first few zeros */
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
			if(gfCheckVal)	VpVarCheck(a);
#endif /* _DEBUG */
			return 1;
		}
	}
	/* a is zero(no non-zero digit) */
	VpSetZero(a,VpGetSign(a));
	return 1;
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpComp(Real *a,Real *b)
#else
VpComp(a, b)
	Real *a;
	Real *b;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 *  VpComp = 0  ... if a=b, 
 *   Pos  ... a>b, 
 *   Neg  ... a<b. 
 *   999  ... result undefined(NaN) 
 */
{
	int val;
	U_LONG mx, ind;
	int e;
	val = 0;
	if(VpIsNaN(a)||VpIsNaN(b)) return 999;
	if(!VpIsDef(a)) {
		if(!VpIsDef(b)) e = a->sign - b->sign;
		else 			e = a->sign;
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
		val = 1;		/* a>b */
		goto Exit;
	}
	if(VpGetSign(a) < VpGetSign(b)) {
		val = -1;		/* a<b */
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

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VPrint(FILE *fp,char *cntl_chr,Real *a)
#else
VPrint(fp, cntl_chr, a)
	FILE *fp;
	char *cntl_chr;
	Real *a;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 *    cntl_chr ... ASCIIZ Character, print control characters 
 *     Available control codes: 
 *      %  ... VP variable. To print '%', use '%%'. 
 *      \n ... new line 
 *      \b ... backspace 
 *      \t ... tab 
 *     Note: % must must not appear more than once 
 *    a  ... VP variable to be printed 
 */
{
	U_LONG i, j, nc, nd, ZeroSup;
	U_LONG n, m, e, nn;

	/* Check if NaN & Inf. */
	if(VpIsNaN(a)) {
		fprintf(fp,"NaN");
		return 8;
	}
	if(VpIsPosInf(a)) {
		fprintf(fp,"Infinity");
		return 8;
	}
	if(VpIsNegInf(a)) {
		fprintf(fp,"-Infinity");
		return 9;
	}
	if(VpIsZero(a)) {
		fprintf(fp,"0.0");
		return 3;
	}

	j = 0;
	nd = nc = 0;		/*  nd : number of digits in fraction part(every 10 digits, */
	/*    nd<=10). */
	/*  nc : number of caracters printed  */
	ZeroSup = 1;		/* Flag not to print the leading zeros as 0.00xxxxEnn */
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
							nc += fprintf(fp, "%u", nn);	/* The reading zero(s) */
							/* as 0.00xx will not */
							/* be printed. */
							++nd;
							ZeroSup = 0;	/* Set to print succeeding zeros */
						}
						if(nd >= 10) {	/* print ' ' after every 10 digits */
							nd = 0;
							nc += fprintf(fp, " ");
						}
						e = e - nn * m;
						m /= 10;
					}
				}
				nc += fprintf(fp, "E%d", VpExponent10(a));
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

static void
#ifdef HAVE_STDARG_PROTOTYPES
VpFormatSt(char *psz,S_INT fFmt)
#else
VpFormatSt(psz, fFmt)
	char *psz;
	S_INT fFmt;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	U_LONG ie;
	U_LONG i, j;
	S_INT nf;
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
			for(j = ie; j >= i; --j)
			psz[j + 1] = psz[j];
			++ie;
			nf = 0;
			psz[i] = ' ';
		}
	}
}

VP_EXPORT S_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpExponent10(Real *a)
#else
VpExponent10(a)
	Real *a;
#endif /* HAVE_STDARG_PROTOTYPES */
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
#ifdef HAVE_STDARG_PROTOTYPES
VpSzMantissa(Real *a,char *psz)
#else
VpSzMantissa(a,psz)
	Real *a;
	char *psz;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	U_LONG i, ZeroSup;
	U_LONG n, m, e, nn;

	if(VpIsNaN(a)) {
		sprintf(psz,"NaN");
		return;
	}
	if(VpIsPosInf(a)) {
		sprintf(psz,"Infinity");
		return;
	}
	if(VpIsNegInf(a)) {
		sprintf(psz,"-Infinity");
		return;
	}

	ZeroSup = 1;		/* Flag not to print the leading zeros as 0.00xxxxEnn */
	if(!VpIsZero(a)) {
		if(VpGetSign(a) < 0) *psz++ = '-';
		n = a->Prec;
		for(i=0;i < n;++i) {
			m = BASE1;
			e = a->frac[i];
			while(m) {
				nn = e / m;
				if((!ZeroSup) || nn) {
					sprintf(psz, "%u", nn);	/* The reading zero(s) */
					psz += strlen(psz);
					/* as 0.00xx will be ignored. */
					ZeroSup = 0;	/* Set to print succeeding zeros */
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
#ifdef HAVE_STDARG_PROTOTYPES
VpToString(Real *a,char *psz,int fFmt)
#else
VpToString(a, psz, fFmt)
	Real *a;
	char *psz;
	int fFmt;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	U_LONG i, ZeroSup;
	U_LONG n, m, e, nn;
	char *pszSav = psz;
	S_LONG ex;

	if(VpIsNaN(a)) {
		sprintf(psz,"NaN");
		return;
	}
	if(VpIsPosInf(a)) {
		sprintf(psz,"Infinity");
		return;
	}
	if(VpIsNegInf(a)) {
		sprintf(psz,"-Infinity");
		return;
	}

	ZeroSup = 1;	/* Flag not to print the leading zeros as 0.00xxxxEnn */
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
					sprintf(psz, "%u", nn);	/* The reading zero(s) */
					psz += strlen(psz);
					/* as 0.00xx will be ignored. */
					ZeroSup = 0;	/* Set to print succeeding zeros */
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
		sprintf(psz, "E%d", ex);
	} else {
		if(VpIsPosZero(a)) sprintf(psz, "0.0");
		else      sprintf(psz, "-0.0");
	}
	if(fFmt) VpFormatSt(pszSav, fFmt);
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpCtoV(Real *a,char *int_chr,U_LONG ni,char *frac,U_LONG nf,char *exp_chr,U_LONG ne)
#else
VpCtoV(a, int_chr, ni, frac, nf, exp_chr, ne)
	Real *a;
	char *int_chr;
	U_LONG ni;
	char *frac;
	U_LONG nf;
	char *exp_chr;
	U_LONG ne;
#endif /* HAVE_STDARG_PROTOTYPES */
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
	for(i=0;i < ma;++i) a->frac[i] = 0;
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
			es = e*BASE_FIG;
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

	e = signe * e;		/* e: The value of exponent part. */
	e = e + ni;		/* set actual exponent size. */

	if(e > 0)	signe = 1;
	else		signe = -1;

	/* Adjust the exponent so that it is the multiple of BASE_FIG. */
	j = 0;
	ef = 1;
	while(ef) {
		if(e>=0) eb =  e;
		else  eb = -e;
		ef = eb / BASE_FIG;
		ef = eb - ef * BASE_FIG;
		if(ef) {
			++j;		/* Means to add one more preceeding zero */
			++e;
		}
	}

	eb = e / BASE_FIG;

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
	rb_warn("Conversion from String to BigFloat overflow (last few digits discarded).");

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

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpVtoD(double *d,U_LONG *e,Real *m)
#else
VpVtoD(d, e, m)
	double *d;
	U_LONG *e;
	Real *m;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 * [Input] 
 *   *m  ... Real 
 * [Output] 
 *   *d  ... fraction part of m(d = 0.xxxxxxx). where # of 'x's is fig. 
 *   *e  ... U_LONG,exponent of m. 
 * DBLE_FIG ... Number of digits in a double variable. 
 *
 *  m -> d*10**e, 0<d<BASE 
 */
{
	U_LONG ind_m, mm, fig;
	double div;

	fig =(DBLE_FIG + BASE_FIG - 1) / BASE_FIG;
	if(VpIsPosZero(m)) {
		*d = 0.0;
		*e = 0;
		goto Exit;
	} else
	if(VpIsNegZero(m)) {
		*d = VpGetDoubleNegZero();
		*e = 0;
		goto Exit;
	}
	ind_m = 0;
	mm = Min(fig,(m->Prec));
	*d = 0.0;
	div = 1.;
	while(ind_m < mm) {
		div /=(double)((S_INT)BASE);
		*d = *d +((double) ((S_INT)m->frac[ind_m++])) * div;
	}
	*e = m->exponent * BASE_FIG;
	*d *= VpGetSign(m);

Exit:
#ifdef _DEBUG
	if(gfDebug) {
		VPrint(stdout, " VpVtoD: m=%\n", m);
		printf("   d=%e * 10 **%d\n", *d, *e);
		printf("   DBLE_FIG = %d\n", DBLE_FIG);
	}
#endif /*_DEBUG */
	return;
}

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpDtoV(Real *m,double d)
#else
VpDtoV(m, d)
	Real *m;
	double d;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 * m <- d 
 */
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
	for(ind_m = 0;ind_m < mm;ind_m++) m->frac[ind_m] = 0;
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
	if(val*((double)((S_INT)BASE)) >=(double)((S_INT)HALF_BASE)) VpRdup(m);
	VpNmlz(m);

Exit:
#ifdef _DEBUG
	if(gfDebug) {
		printf("VpDtoV d=%30.30e\n", d);
		VPrint(stdout, "  m=%\n", m);
	}
#endif /* _DEBUG */
	return;
}

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpItoV(Real *m,S_INT ival)
#else
VpItoV(m, ival)
	Real  *m;
	S_INT ival;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *  m <- ival 
 */
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
		printf(" VpItoV i=%ld\n", ival);
		VPrint(stdout, "  m=%\n", m);
	}
#endif /* _DEBUG */
	return;
}

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpSqrt(Real *y,Real *x)
#else
VpSqrt(y, x)
	Real *y;
	Real *x;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 * y = SQRT(x),  y*y - x =>0 
 */
{
	Real *f = NULL;
	Real *r = NULL;
	U_LONG y_prec, f_prec, n, e;
	S_LONG prec;
	U_LONG nr;
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

	n = y->MaxPrec;
	if(x->MaxPrec > n) n = x->MaxPrec;
	/* allocate temporally variables  */
	f = VpAlloc(y->MaxPrec *(BASE_FIG + 2), "#1");
	r = VpAlloc((n + n) *(BASE_FIG + 2), "#1");

	nr = 0;
	y_prec = y->MaxPrec;
	f_prec = f->MaxPrec;

	VpAsgn(y, x, 1);		/* assign initial guess. y <= x */
	prec = x->exponent;
	if(prec > 0)	++prec;
	else			--prec;
	prec = prec / 2 - y->MaxPrec;
	/*
	 *  y  = 0.yyyy yyyy yyyy YYYY 
	 *  BASE_FIG =   |  | 
	 *  prec  =(0.YYYY*BASE-4)
	 */
	VpVtoD(&val, &e, y);	/* val <- y  */
	e /= BASE_FIG;
	n = e / 2;
	if(e - n * 2 != 0) {
		val /=(double)((S_INT)BASE);
		n =(e + 1) / 2;
	}
	VpDtoV(y, sqrt(val));	/* y <- sqrt(val) */
	y->exponent += n;
	n = (DBLE_FIG + BASE_FIG - 1) / BASE_FIG;
	y->MaxPrec = Min(n , y_prec);
	f->MaxPrec = y->MaxPrec + 1;
	n = y_prec*BASE_FIG;
	if(n<maxnr) n = maxnr;
	do {
		y->MaxPrec *= 2;
		if(y->MaxPrec > y_prec) y->MaxPrec = y_prec;
		f->MaxPrec = y->MaxPrec;
		VpDivd(f, r, x, y);	/* f = x/y  */
		VpAddSub(r, y, f, 1);	/* r = y + x/y  */
		VpMult(f, VpPt5, r);	/* f = 0.5*r  */
		VpAddSub(r, f, y, -1);
		if(VpIsZero(r))		 goto converge;
		if(r->exponent <= prec) goto converge;
		VpAsgn(y, f, 1);
	} while(++nr < n);
	/* */
#ifdef _DEBUG
	if(gfDebug) {
		printf("ERROR(VpSqrt): did not converge within %d iterations.\n",
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
		printf("VpSqrt: iterations = %d\n", nr);
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

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpRound(Real *y,Real *x,int sw,int f,int nf)
#else
VpRound(y, x, sw, f, nf)
	Real *y;
	Real *x;
	int  sw; /* sw==2: round up,==1 round off */
	int  f;  /* 1: round, 2:ceil, 3:floor */
	int  nf; /* Place to round(Zero base. nf=0 means the result is an integer) */
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *
 * f = 1: round, 2:ceil, 3: floor
 *
 */
{
	int n,i,j,ix,ioffset;
	U_LONG v;
	U_LONG div;

	if(!VpIsDef(x)) {
		VpAsgn(y,x,1);
		goto Exit;
	}

	/* First,assign whole value */		
	VpAsgn(y, x, sw);
	nf += y->exponent*((int)BASE_FIG);
	/* ix: x->fraq[ix] contains round position */ 
	ix = (nf + ((int)BASE_FIG))/((int)BASE_FIG)-1;
	if(ix<0 || ((U_LONG)ix)>=y->Prec) goto Exit; /* Unable to round */
	ioffset = nf - ix*((int)BASE_FIG);
	for(j=ix+1;j<(int)y->Prec;++j) y->frac[j] = 0;
	VpNmlz(y);
	v = y->frac[ix];
	/* drop digits after pointed digit */
	n = BASE_FIG - ioffset - 1;
	for(i=0;i<n;++i) v /= 10;
	div = v/10;
	v = v - div*10;
	switch(f){
	case 1: /* Round */
		if(sw==2 && v>=5) {
			++div;
		}
		break;
	case 2: /* ceil */
		if(v) {
			if(VpGetSign(x)>0) ++div;
		}
		break;
	case 3: /* floor */
		if(v) {
			if(VpGetSign(x)<0) ++div;
		}
		break;
	}
	for(i=0;i<=n;++i) div *= 10;
	if(div>=BASE) {
		y->frac[ix] = 0;
		if(ix) {
			VpNmlz(y);
			VpRdup(y);
		} else {
			VpSetOne(y);
			VpSetSign(y,VpGetSign(x));
		}
	} else {
		y->frac[ix] = div;
		VpNmlz(y);
	}

Exit:
#ifdef _DEBUG
	if(gfDebug) {
		VPrint(stdout, "VpRound y=%\n", y);
		VPrint(stdout, "  x=%\n", x);
	}
#endif /*_DEBUG */
	return;
}

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpRdup(Real *m)
#else
VpRdup(m)
	Real *m;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *  Rounds up m(plus one to final digit of m). 
 */
{
	U_LONG ind_m, carry;
	ind_m = m->Prec;
	carry = 1;
	while(carry > 0 && ind_m) {
		--ind_m;
		m->frac[ind_m] += carry;
		if(m->frac[ind_m] >= BASE) m->frac[ind_m] -= BASE;
		else					   carry = 0;
	}
	if(carry > 0) {		/* Overflow,count exponent and set fraction part be 1  */
		if(!AddExponent(m,(S_LONG)1)) return 0;
		m->Prec = m->frac[0] = 1;
	} else {
		VpNmlz(m);
	}
	return 1;
}

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpFrac(Real *y,Real *x)
#else
VpFrac(y, x)
	Real *y;
	Real *x;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 *  y = x - fix(x) 
 */
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

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpPower(Real *y,Real *x,S_INT n)
#else
VpPower(y, x, n)
	Real *y;
	Real *x;
	S_INT n;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 *   y = x ** n
 */
{
	U_LONG s, ss;
	S_LONG sign;
	Real *w1 = NULL;
	Real *w2 = NULL;

	if(VpIsZero(x)) {
		if(n<0) n = -n;
		VpSetZero(y,(n%2)?VpGetSign(x):(-VpGetSign(x)));
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

	w1 = VpAlloc((x->Prec + 2) * BASE_FIG, "#0");
	w2 = VpAlloc((w1->MaxPrec * 2 + 1) * BASE_FIG, "#0");
	/* calculation start */

	VpAsgn(y, x, 1);
	--n;
	while(n > 0) {
		VpAsgn(w1, x, 1);
		s = 1;
loop1:		ss = s;
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

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpPai(Real *y)
#else
VpPai(y)
	Real *y;
#endif /* HAVE_STDARG_PROTOTYPES */
/* 
 * Calculates pai(=3.141592653589793238462........). 
 */
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

	VpSetZero(y,1);		/* y   = 0 */
	i1 = 0;
	do {
		++i1;
		/* VpDivd(f, r, t, n25); */ /* f = t/(-25) */
		VpMult(f,t,n25);
		VpAsgn(t, f, 1);	   /* t = f    */

		VpDivd(f, r, t, n); /* f = t/n  */ 
		
		VpAddSub(r, y, f, 1);  /* r = y + f   */
		VpAsgn(y, r, 1);	   /* y = r    */

		VpRdup(n);		    /* n   = n + 1 */
		VpRdup(n);		    /* n   = n + 1 */
		if(VpIsZero(f)) break;
	} while((f->exponent > 0 ||	((U_LONG)(-(f->exponent)) < y->MaxPrec)) && 
			i1<nc
	);

	VpSetOne(n);
	VpAsgn(t, n956,1);
	i2 = 0;
	do {
		++i2;
		VpDivd(f, r, t, n57121); /* f = t/(-57121) */
		VpAsgn(t, f, 1);	  /* t = f    */

		VpDivd(f, r, t, n);   /* f = t/n  */
		VpAddSub(r, y, f, 1); /* r = y + f   */

		VpAsgn(y, r, 1);	  /* y = r    */
		VpRdup(n);		   /* n   = n + 1  */
		VpRdup(n);		   /* n   = n + 1 */
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
	printf("VpPai: # of iterations=%d+%d\n",i1,i2);
#endif /* _DEBUG */
}

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpExp1(Real *y)
#else
VpExp1(y)
	Real *y;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 * Calculates the value of e(=2.18281828459........). 
 * [Output] *y ... Real , the value of e. 
 * 
 *     y = e 
 */
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
	n = VpAlloc(p, "#1");	/* n   = 1 */
	add = VpAlloc(p, "#1");	/* add = 1 */

	VpSetOne(y);			/* y   = 1 */
	VpRdup(y);			/* y   = y + 1  */
	i = 0;
	do {
		++i;
		VpRdup(n);		/* n   = n + 1  */
		VpDivd(f, r, add, n);	/* f   = add/n(=1/n!)  */
		VpAsgn(add, f, 1);	/* add = 1/n!  */
		VpAddSub(r, y, f, 1);
		VpAsgn(y, r, 1);	/* y = y + 1/n! */
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

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpExp(Real *y,Real *x)
#else
VpExp(y, x)
	Real *y;
	Real *x;
#endif /* HAVE_STDARG_PROTOTYPES */
/*
 * Calculates y=e**x where e(=2.18281828459........). 
 */
{
	Real *z=NULL, *div=NULL, *n=NULL, *r=NULL, *c=NULL;
	U_LONG p;
	U_LONG nc;
	U_LONG i;

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

	/* allocate temporally variables  */
	z = VpAlloc(p, "#1");
	div = VpAlloc(p, "#1");

	r = VpAlloc(p * 2, "#0");
	c = VpAlloc(p, "#0");
	n = VpAlloc(p, "#1");	/* n   = 1 */

	VpSetOne(r);		/* y = 1 */
	VpAddSub(y, r, x, 1);	/* y = 1 + x/1 */
	VpAsgn(z, x, 1);	/* z = x/1  */

	i = 0;
	do {
		++i;
		VpRdup(n);		/* n   = n + 1  */
		VpDivd(div, r, x, n);	/* div = x/n */
		VpMult(c, z, div);	/* c   = x/(n-1)! * x/n */
		VpAsgn(z, c, 1);	/* z   = x*n/n! */
		VpAsgn(r, y, 1);	/* Save previous val. */
		VpAddSub(div, y, z, 1);	/*  */
		VpAddSub(c, div, r, -1);	/* y = y(new) - y(prev) */
		VpAsgn(y, div, 1);	/* y = y(new) */
	} while(((!VpIsZero(c)) &&(c->exponent >= 0 ||((U_LONG)(-c->exponent)) <= y->MaxPrec)) &&
			i<nc
		);

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
#ifdef HAVE_STDARG_PROTOTYPES
VpSinCos(Real *psin,Real *pcos,Real *x)
#else
VpSinCos(psin, pcos, x)
	Real *psin;
	Real *pcos;
	Real *x;
#endif /* HAVE_STDARG_PROTOTYPES */
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
	n = VpAlloc(p, "#1");	/* n   = 1 */

	VpSetOne(pcos);		/* cos = 1 */
	VpAsgn(psin, x, 1);	/* sin = x/1 */
	VpAsgn(z, x, 1);		/* z = x/1  */
	fcos = 1;
	fsin = 1;
	which = 1;
	i = 0;
	do {
		++i;
		VpRdup(n);		/* n   = n + 1  */
		VpDivd(div, r, x, n);	/* div = x/n */
		VpMult(c, z, div);	/* c   = x/(n-1)! * x/n */
		VpAsgn(z, c, 1);	/* z   = x*n/n! */
		if(which) {
			/* COS */
			which = 0;
			fcos *= -1;
			VpAsgn(r, pcos, 1);	/* Save previous val. */
			VpAddSub(div, pcos, z, fcos);	/*  */
			VpAddSub(c, div, r, -1);	/* cos = cos(new) - cos(prev) */
			VpAsgn(pcos, div, 1);	/* cos = cos(new) */
		} else {
			/* SIN */
			which = 1;
			fsin *= -1;
			VpAsgn(r, psin, 1);	/* Save previous val. */
			VpAddSub(div, psin, z, fsin);	/*  */
			VpAddSub(c, div, r, -1);	/* sin = sin(new) - sin(prev) */
			VpAsgn(psin, div, 1);	/* sin = sin(new) */
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
		printf("ERROR(VpVarCheck): Illegal Max. Precision(=%u)\n",
			v->MaxPrec);
		return 1;
	}
	if((v->Prec <= 0) ||((v->Prec) >(v->MaxPrec))) {
		printf("ERROR(VpVarCheck): Illegal Precision(=%u)\n", v->Prec);
		printf("       Max. Prec.=%u\n", v->MaxPrec);
		return 2;
	}
	for(i = 0; i < v->Prec; ++i) {
		if((v->frac[i] >= BASE)) {
			printf("ERROR(VpVarCheck): Illegal fraction\n");
			printf("       Frac[%d]=%u\n", i, v->frac[i]);
			printf("       Prec.   =%u\n", v->Prec);
			printf("       Exp. =%d\n", v->exponent);
			printf("       BASE =%u\n", BASE);
			return 3;
		}
	}
	return 0;
}
#endif /* _DEBUG */

static U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
SkipWhiteChar(char *szVal)
#else
SkipWhiteChar(szVal)
	char *szVal;
#endif /* HAVE_STDARG_PROTOTYPES */
{
	char ch;
	U_LONG i = 0;
	while(ch = szVal[i++]) {
		if(IsWhiteChar(ch)) continue;
		break;
	}
	return i - 1;
}
