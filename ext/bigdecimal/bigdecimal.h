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
 *   2003-03-28 V1.0 checked in.
 *
 */

#ifndef  ____BIG_DECIMAL__H____
#define  ____BIG_DECIMAL__H____

#if defined(__cplusplus)
extern "C" {
#endif

/*
 *  NaN & Infinity
 */
#define SZ_NaN  "NaN"
#define SZ_INF  "Infinity"
#define SZ_PINF "+Infinity"
#define SZ_NINF "-Infinity"

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
#define VP_EXCEPTION_ALL        ((unsigned short)0x00FF)
#define VP_EXCEPTION_INFINITY   ((unsigned short)0x0001)
#define VP_EXCEPTION_NaN        ((unsigned short)0x0002)
#define VP_EXCEPTION_UNDERFLOW  ((unsigned short)0x0004)
#define VP_EXCEPTION_OVERFLOW   ((unsigned short)0x0001) /* 0x0008) */
#define VP_EXCEPTION_ZERODIVIDE ((unsigned short)0x0001) /* 0x0010) */

/* Following 2 exceptions cann't controlled by user */
#define VP_EXCEPTION_OP         ((unsigned short)0x0020)
#define VP_EXCEPTION_MEMORY     ((unsigned short)0x0040)

/* Computation mode */
#define VP_ROUND_MODE            ((unsigned short)0x0100)
#define VP_ROUND_UP         1
#define VP_ROUND_DOWN       2
#define VP_ROUND_HALF_UP    3
#define VP_ROUND_HALF_DOWN  4
#define VP_ROUND_CEIL       5
#define VP_ROUND_FLOOR      6
#define VP_ROUND_HALF_EVEN  7

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
    U_LONG MaxPrec; /* Maximum precision size                   */
                    /* This is the actual size of pfrac[]       */
                    /*(frac[0] to frac[MaxPrec] are available). */
    U_LONG Prec;    /* Current precision size.                  */
                    /* This indicates how much the.             */
                    /* the array frac[] is actually used.       */
    S_INT  exponent;/* Exponent part.                           */
    short  sign;    /* Attributes of the value.                 */
                    /*
                     *        ==0 : NaN
                     *          1 : Positive zero
                     *         -1 : Negative zero
                     *          2 : Positive number
                     *         -2 : Negative number
                     *          3 : Positive infinite number
                     *         -3 : Negative infinite number
                     */
    short  flag;    /* Not used in vp_routines,space for user.  */
    U_LONG frac[1]; /* Pointer to array of fraction part.       */
} Real;

/*  
 *  ------------------
 *   EXPORTables.
 *  ------------------
 */

VP_EXPORT  Real *
VpNewRbClass(U_LONG mx,char *str,VALUE klass);

VP_EXPORT  Real *VpCreateRbObject(U_LONG mx,const char *str);

VP_EXPORT U_LONG VpBaseFig(void);
VP_EXPORT U_LONG VpDblFig(void);
VP_EXPORT U_LONG VpBaseVal(void);

/* Zero,Inf,NaN (isinf(),isnan() used to check) */
VP_EXPORT double VpGetDoubleNaN(void);
VP_EXPORT double VpGetDoublePosInf(void);
VP_EXPORT double VpGetDoubleNegInf(void);
VP_EXPORT double VpGetDoubleNegZero(void);

/* These 2 functions added at v1.1.7 */
VP_EXPORT U_LONG VpGetPrecLimit(void);
VP_EXPORT U_LONG VpSetPrecLimit(U_LONG n);

/* Round mode */
VP_EXPORT int           VpIsRoundMode(unsigned long n);
VP_EXPORT unsigned long VpGetRoundMode(void);
VP_EXPORT unsigned long VpSetRoundMode(unsigned long n);

VP_EXPORT int VpException(unsigned short f,const char *str,int always);
VP_EXPORT int VpIsNegDoubleZero(double v);
VP_EXPORT U_LONG VpNumOfChars(Real *vp,const char *pszFmt);
VP_EXPORT U_LONG VpInit(U_LONG BaseVal);
VP_EXPORT void *VpMemAlloc(U_LONG mb);
VP_EXPORT void VpFree(Real *pv);
VP_EXPORT Real *VpAlloc(U_LONG mx, const char *szVal);
VP_EXPORT int VpAsgn(Real *c,Real *a,int isw);
VP_EXPORT int VpAddSub(Real *c,Real *a,Real *b,int operation);
VP_EXPORT int VpMult(Real *c,Real *a,Real *b);
VP_EXPORT int VpDivd(Real *c,Real *r,Real *a,Real *b);
VP_EXPORT int VpComp(Real *a,Real *b);
VP_EXPORT S_LONG VpExponent10(Real *a);
VP_EXPORT void VpSzMantissa(Real *a,char *psz);
VP_EXPORT int VpToSpecialString(Real *a,char *psz,int fPlus);
VP_EXPORT void VpToString(Real *a,char *psz,int fFmt,int fPlus);
VP_EXPORT void VpToFString(Real *a,char *psz,int fFmt,int fPlus);
VP_EXPORT int VpCtoV(Real *a,const char *int_chr,U_LONG ni,const char *frac,U_LONG nf,const char *exp_chr,U_LONG ne);
VP_EXPORT int VpVtoD(double *d,S_LONG *e,Real *m);
VP_EXPORT void VpDtoV(Real *m,double d);
VP_EXPORT void VpItoV(Real *m,S_INT ival);
VP_EXPORT int VpSqrt(Real *y,Real *x);
VP_EXPORT int VpActiveRound(Real *y,Real *x,int f,int il);
VP_EXPORT int VpMidRound(Real *y, int f, int nf);
VP_EXPORT int VpLeftRound(Real *y, int f, int nf);
VP_EXPORT void VpFrac(Real *y,Real *x);
VP_EXPORT int VpPower(Real *y,Real *x,S_INT n);

/* VP constants */
VP_EXPORT Real *VpOne(void);

/*  
 *  ------------------
 *  MACRO definitions.
 *  ------------------
 */
#define Abs(a)     (((a)>= 0)?(a):(-(a)))
#define Max(a, b)  (((a)>(b))?(a):(b))
#define Min(a, b)  (((a)>(b))?(b):(a))

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
#define VpHasVal(a)     (a->frac[0])
#define VpIsOne(a)      ((a->Prec==1)&&(a->frac[0]==1)&&(a->exponent==1))
#define VpExponent(a)   (a->exponent)
#ifdef _DEBUG
int VpVarCheck(Real * v);
VP_EXPORT int VPrint(FILE *fp,char *cntl_chr,Real *a);
#endif /* _DEBUG */

#if defined(__cplusplus)
}  /* extern "C" { */
#endif
#endif /* ____BIG_DECIMAL__H____ */
