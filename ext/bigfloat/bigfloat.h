/*
 *
 * Ruby BIGFLOAT(Variable Precision) extension library. 
 *
 *  Version 1.1.7(2001/08/27)
 *  Version 1.1.6(2001/03/28)
 *
 * Copyright(C) 1999  by Shigeo Kobayashi(shigeo@tinyforest.gr.jp) 
 *
 * You may distribute under the terms of either the GNU General Public 
 * License or the Artistic License, as specified in the README file 
 * of this BigFloat distribution. 
 *
 */

#ifndef  ____BIG_FLOAT__H____
#define  ____BIG_FLOAT__H____

#if defined(__cplusplus)
extern "C" {
#endif

/*
 *   #define VP_EXPORT other than static to let VP_ routines 
 *   be called from outside of this module.
 */
#define VP_EXPORT static 

#define U_LONG unsigned long
#define S_LONG long
#define U_INT  unsigned int
#define S_INT  int

/* Exception codes */
#define VP_EXCEPTION_ALL        ((unsigned short)0xFFFF)
#define VP_EXCEPTION_INFINITY   ((unsigned short)0x0001)
#define VP_EXCEPTION_NaN        ((unsigned short)0x0002)
#define VP_EXCEPTION_UNDERFLOW  ((unsigned short)0x0004)
#define VP_EXCEPTION_OVERFLOW   ((unsigned short)0x0001) /* 0x0008) */
#define VP_EXCEPTION_ZERODIVIDE ((unsigned short)0x0001) /* 0x0010) */
/* Following 2 exceptions cann't controlled by user */
#define VP_EXCEPTION_OP         ((unsigned short)0x0020)
#define VP_EXCEPTION_MEMORY     ((unsigned short)0x0040)

#define VP_SIGN_NaN                0 /* NaN                      */
#define VP_SIGN_POSITIVE_ZERO      1 /* Positive zero            */
#define VP_SIGN_NEGATIVE_ZERO     -1 /* Negative zero            */
#define VP_SIGN_POSITIVE_FINITE    2 /* Positive finite number   */
#define VP_SIGN_NEGATIVE_FINITE   -2 /* Negative finite number   */
#define VP_SIGN_POSITIVE_INFINITE  3 /* Positive infinite number */
#define VP_SIGN_NEGATIVE_INFINITE -3 /* Negative infinite number */

/*
 * VP representation
 *  r = 0.xxxxxxxxx *BASE**exponent
 */
typedef struct {
	VALUE  obj;     /* Back pointer(VALUE) for Ruby object.     */
	U_LONG MaxPrec;	/* Maximum precision size                   */
					/* This is the actual size of pfrac[]       */
					/*(frac[0] to frac[MaxPrec] are available). */
	U_LONG Prec;	/* Current precision size.                  */
					/* This indicates how much the.             */
					/* the array frac[] is actually used.       */
	S_INT  exponent;/* Exponent part.                           */
	short  sign;	/* Attributes of the value.                 */
					/*
					 *		==0 : NaN
					 *		  1 : Positive zero
					 *		 -1 : Negative zero
					 *		  2 : Positive number
					 *		 -2 : Negative number
					 *		  3 : Positive infinite number
					 *		 -3 : Negative infinite number
					 */
	short  flag;   /* Not used in vp_routines,space for user.  */
	U_LONG frac[1];	/* Pointer to array of fraction part.       */
} Real;

/*  
 *  ------------------
 *   EXPORTables.
 *  ------------------
 */

VP_EXPORT  Real *
#ifdef HAVE_STDARG_PROTOTYPES
VpNewRbClass(U_LONG mx,char *str,VALUE klass);
#else
VpNewRbClass();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT  Real *
#ifdef HAVE_STDARG_PROTOTYPES
VpCreateRbObject(U_LONG mx,char *str);
#else
VpCreateRbObject();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT S_LONG VpBaseFig();
VP_EXPORT S_LONG VpDblFig();
VP_EXPORT U_LONG VpBaseVal();

/* Zero,Inf,NaN (isinf(),isnan() used to check) */
VP_EXPORT double VpGetDoubleNaN();
VP_EXPORT double VpGetDoublePosInf();
VP_EXPORT double VpGetDoubleNegInf();
VP_EXPORT double VpGetDoubleNegZero();

/* These 2 functions added at v1.1.7 */
VP_EXPORT U_LONG VpGetPrecLimit();
#ifdef HAVE_STDARG_PROTOTYPES
VP_EXPORT U_LONG VpSetPrecLimit(U_LONG n);
#else
VP_EXPORT U_LONG VpSetPrecLimit();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpException(unsigned short f,char *str,int always);
#else
VpException();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpIsNegDoubleZero(double v);
#else
VpIsNegDoubleZero();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpNumOfChars(Real *vp);
#else
VpNumOfChars();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpInit(U_LONG BaseVal);
#else
VpInit();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpFree(Real *pv);
#else
VpFree();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT Real *
#ifdef HAVE_STDARG_PROTOTYPES
VpAlloc(U_LONG mx, char *szVal);
#else
VpAlloc();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpAsgn(Real *c,Real *a,int isw);
#else
VpAsgn();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpAddSub(Real *c,Real *a,Real *b,int operation);
#else
VpAddSub();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpMult(Real *c,Real *a,Real *b);
#else
VpMult();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpDivd(Real *c,Real *r,Real *a,Real *b);
#else
VpDivd(c, r, a, b);
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpComp(Real *a,Real *b);
#else
VpComp();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT S_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpExponent10(Real *a);
#else
VpExponent10();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpSzMantissa(Real *a,char *psz);
#else
VpSzMantissa();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpToString(Real *a,char *psz,int fFmt);
#else
VpToString();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpCtoV(Real *a,char *int_chr,U_LONG ni,char *frac,U_LONG nf,char *exp_chr,U_LONG ne);
#else
VpCtoV();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpVtoD(double *d,U_LONG *e,Real *m);
#else
VpVtoD();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpDtoV(Real *m,double d);
#else
VpDtoV();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpItoV(Real *m,S_INT ival);
#else
VpItoV();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpSqrt(Real *y,Real *x);
#else
VpSqrt();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpRound(Real *y,Real *x,int sw,int f,int il);
#else
VpRound();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpFrac(Real *y,Real *x);
#else
VpFrac();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VpPower(Real *y,Real *x,S_INT n);
#else
VpPower();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpPai(Real *y);
#else
VpPai();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpExp1(Real *y);
#else
VpExp1();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpExp(Real *y,Real *x);
#else
VpExp();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT void
#ifdef HAVE_STDARG_PROTOTYPES
VpSinCos(Real *psin,Real *pcos,Real *x);
#else
VpSinCos();
#endif /* HAVE_STDARG_PROTOTYPES */

VP_EXPORT int
#ifdef HAVE_STDARG_PROTOTYPES
VPrint(FILE *fp,char *cntl_chr,Real *a);
#else
VPrint();
#endif /* HAVE_STDARG_PROTOTYPES */

/*  
 *  ------------------
 *   static routines.
 *  ------------------
 */

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpIsDefOP(Real *c,Real *a,Real *b,int sw);
#else
VpIsDefOP();
#endif /* HAVE_STDARG_PROTOTYPES */

static int
#ifdef HAVE_STDARG_PROTOTYPES
AddExponent(Real *a,S_INT n);
#else
AddExponent();
#endif /* HAVE_STDARG_PROTOTYPES */

static void *
#ifdef HAVE_STDARG_PROTOTYPES
VpMemAlloc(U_LONG mb);
#else
VpMemAlloc();
#endif /* HAVE_STDARG_PROTOTYPES */

static unsigned short VpGetException();

static void 
#ifdef HAVE_STDARG_PROTOTYPES
VpSetException(unsigned short f);
#else
VpSetException();
#endif /* HAVE_STDARG_PROTOTYPES */

static int
#ifdef HAVE_STDARG_PROTOTYPES
MemCmp(	unsigned char *a,unsigned char *b,int n);
#else
MemCmp(a,b,n);
#endif /* HAVE_STDARG_PROTOTYPES */

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpAddAbs(Real *a,Real *b,Real *c);
#else
VpAddAbs();
#endif /* HAVE_STDARG_PROTOTYPES */

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpSubAbs(Real *a,Real *b,Real *c);
#else
VpSubAbs();
#endif /* HAVE_STDARG_PROTOTYPES */

static U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
VpSetPTR(Real *a,Real *b,Real *c,U_LONG *a_pos,U_LONG *b_pos,U_LONG *c_pos,U_LONG *av,U_LONG *bv);
#else
VpSetPTR();
#endif /* HAVE_STDARG_PROTOTYPES */

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpNmlz(Real *a);
#else
VpNmlz();
#endif /* HAVE_STDARG_PROTOTYPES */

static void
#ifdef HAVE_STDARG_PROTOTYPES
VpFormatSt(char *psz,S_INT fFmt);
#else
VpFormatSt();
#endif /* HAVE_STDARG_PROTOTYPES */

static int
#ifdef HAVE_STDARG_PROTOTYPES
VpRdup(Real *m);
#else
VpRdup();
#endif /* HAVE_STDARG_PROTOTYPES */

static U_LONG
#ifdef HAVE_STDARG_PROTOTYPES
SkipWhiteChar(char *szVal);
#else
SkipWhiteChar();
#endif /* HAVE_STDARG_PROTOTYPES */

static U_LONG 
#ifdef HAVE_STDARG_PROTOTYPES
GetAddSubPrec(Real *a,Real *b);
#else
GetAddSubPrec();
#endif /* HAVE_STDARG_PROTOTYPES */

static S_INT
#ifdef HAVE_STDARG_PROTOTYPES
GetPositiveInt(VALUE v);
#else
GetPositiveInt();
#endif /* HAVE_STDARG_PROTOTYPES */

static Real *
#ifdef HAVE_STDARG_PROTOTYPES
GetVpValue(VALUE v,int must);
#else
GetVpValue();
#endif /* HAVE_STDARG_PROTOTYPES */

static VALUE
#ifdef HAVE_STDARG_PROTOTYPES
ToValue(Real *p);
#else
ToValue();
#endif /* HAVE_STDARG_PROTOTYPES */

static S_INT 
#ifdef HAVE_STDARG_PROTOTYPES
BigFloatCmp(VALUE self,VALUE r);
#else
BigFloatCmp();
#endif /* HAVE_STDARG_PROTOTYPES */

static VALUE
#ifdef HAVE_STDARG_PROTOTYPES
BigFloat_divide(Real **c,Real **res,Real **div,VALUE self,VALUE r);
#else
BigFloat_divide();
#endif /* HAVE_STDARG_PROTOTYPES */

static VALUE
#ifdef HAVE_STDARG_PROTOTYPES
BigFloat_DoDivmod(VALUE self,VALUE r,Real **div,Real **mod);
#else
BigFloat_DoDivmod();
#endif /* HAVE_STDARG_PROTOTYPES */

/*  
 *  ------------------
 *  MACRO definitions.
 *  ------------------
 */
#define Abs(a)     (((a)>= 0)?(a):(-(a)))
#define Max(a, b)  (((a)>(b))?(a):(b))
#define Min(a, b)  (((a)>(b))?(b):(a))

#define IsWhiteChar(ch) (((ch==' ')||(ch=='\n')||(ch=='\t')||(ch=='\b'))?1:0)

#define VpMaxPrec(a)   ((a)->MaxPrec)
#define VpPrec(a)      ((a)->Prec)
#define VpGetFlag(a)   ((a)->flag)

/* Sign */

/* VpGetSign(a) returns 1,-1 if a>0,a<0 respectively */
#define VpGetSign(a) (((a)->sign>0)?1:(-1))
/* Change sign of a to a>0,a<0 if s = 1,-1 respectively */
#define VpChangeSign(a,s) {if((s)>0) (a)->sign=(short)Abs((S_LONG)(a)->sign);else (a)->sign=-(short)Abs((S_LONG)(a)->sign);}
/* Sets sign of a to a>0,a<0 if s = 1,-1 respectively */
#define VpSetSign(a,s)    {if((s)>0) (a)->sign=(short)VP_SIGN_POSITIVE_FINITE;else (a)->sign=(short)VP_SIGN_NEGATIVE_FINITE;}

/* 1 */
#define VpSetOne(a)       {(a)->frac[0]=(a)->exponent=(a)->Prec=1;(a)->sign=VP_SIGN_POSITIVE_FINITE;}

/* ZEROs */
#define VpIsPosZero(a)  ((a)->sign==VP_SIGN_POSITIVE_ZERO)
#define VpIsNegZero(a)  ((a)->sign==VP_SIGN_NEGATIVE_ZERO)
#define VpIsZero(a)     (VpIsPosZero(a) || VpIsNegZero(a))
#define VpSetPosZero(a) ((a)->frac[0]=0,(a)->Prec=1,(a)->sign=VP_SIGN_POSITIVE_ZERO)
#define VpSetNegZero(a) ((a)->frac[0]=0,(a)->Prec=1,(a)->sign=VP_SIGN_NEGATIVE_ZERO)
#define VpSetZero(a,s)  ( ((s)>0)?VpSetPosZero(a):VpSetNegZero(a) )

/* NaN */
#define VpIsNaN(a)      ((a)->sign==VP_SIGN_NaN)
#define VpSetNaN(a)     ((a)->frac[0]=0,(a)->Prec=1,(a)->sign=VP_SIGN_NaN)

/* Infinity */
#define VpIsPosInf(a)   ((a)->sign==VP_SIGN_POSITIVE_INFINITE)
#define VpIsNegInf(a)   ((a)->sign==VP_SIGN_NEGATIVE_INFINITE)
#define VpIsInf(a)      (VpIsPosInf(a) || VpIsNegInf(a))
#define VpIsDef(a)      ( !(VpIsNaN(a)||VpIsInf(a)) )
#define VpSetPosInf(a)  ((a)->frac[0]=0,(a)->Prec=1,(a)->sign=VP_SIGN_POSITIVE_INFINITE)
#define VpSetNegInf(a)  ((a)->frac[0]=0,(a)->Prec=1,(a)->sign=VP_SIGN_NEGATIVE_INFINITE)
#define VpSetInf(a,s)   ( ((s)>0)?VpSetPosInf(a):VpSetNegInf(a) )

#ifdef _DEBUG
int VpVarCheck(Real * v);
#endif /* _DEBUG */

#if defined(__cplusplus)
}  /* extern "C" { */
#endif
#endif //____BIG_FLOAT__H____
