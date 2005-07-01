/*-
 * Copyright (c) 1992, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifndef lint
static char sccsid[] = "@(#)erf.c	8.1 (Berkeley) 6/4/93";
#endif /* not lint */

#if defined(vax)||defined(tahoe)

/* Deal with different ways to concatenate in cpp */
#  ifdef __STDC__
#    define	cat3(a,b,c) a ## b ## c
#  else
#    define	cat3(a,b,c) a/**/b/**/c
#  endif

/* Deal with vax/tahoe byte order issues */
#  ifdef vax
#    define	cat3t(a,b,c) cat3(a,b,c)
#  else
#    define	cat3t(a,b,c) cat3(a,c,b)
#  endif

#  define vccast(name) (*(const double *)(cat3(name,,x)))

   /*
    * Define a constant to high precision on a Vax or Tahoe.
    *
    * Args are the name to define, the decimal floating point value,
    * four 16-bit chunks of the float value in hex
    * (because the vax and tahoe differ in float format!), the power
    * of 2 of the hex-float exponent, and the hex-float mantissa.
    * Most of these arguments are not used at compile time; they are
    * used in a post-check to make sure the constants were compiled
    * correctly.
    *
    * People who want to use the constant will have to do their own
    *     #define foo vccast(foo)
    * since CPP cannot do this for them from inside another macro (sigh).
    * We define "vccast" if this needs doing.
    */
#  define vc(name, value, x1,x2,x3,x4, bexp, xval) \
	const static long cat3(name,,x)[] = {cat3t(0x,x1,x2), cat3t(0x,x3,x4)};

#  define ic(name, value, bexp, xval) ;

#else	/* vax or tahoe */

   /* Hooray, we have an IEEE machine */
#  undef vccast
#  define vc(name, value, x1,x2,x3,x4, bexp, xval) ;

#  define ic(name, value, bexp, xval) \
	const static double name = value;

#endif	/* defined(vax)||defined(tahoe) */

const static double ln2hi = 6.9314718055829871446E-1;
const static double ln2lo = 1.6465949582897081279E-12;
const static double lnhuge = 9.4961163736712506989E1;
const static double lntiny = -9.5654310917272452386E1;
const static double invln2 = 1.4426950408889634148E0;
const static double ep1 = 1.6666666666666601904E-1;
const static double ep2 = -2.7777777777015593384E-3;
const static double ep3 = 6.6137563214379343612E-5;
const static double ep4 = -1.6533902205465251539E-6;
const static double ep5 = 4.1381367970572384604E-8;

/* returns exp(r = x + c) for |c| < |x| with no overlap.  */
double __exp__D(x, c)
double x, c;
{
	double  z,hi,lo, t;
	int k;

#if !defined(vax)&&!defined(tahoe)
	if (x!=x) return(x);	/* x is NaN */
#endif	/* !defined(vax)&&!defined(tahoe) */
	if ( x <= lnhuge ) {
		if ( x >= lntiny ) {

		    /* argument reduction : x --> x - k*ln2 */
			z = invln2*x;
			k = z + copysign(.5, x);

		    /* express (x+c)-k*ln2 as hi-lo and let x=hi-lo rounded */

			hi=(x-k*ln2hi);			/* Exact. */
			x= hi - (lo = k*ln2lo-c);
		    /* return 2^k*[1+x+x*c/(2+c)]  */
			z=x*x;
			c= x - z*(ep1+z*(ep2+z*(ep3+z*(ep4+z*ep5))));
			c = (x*c)/(2.0-c);

			return  scalb(1.+(hi-(lo - c)), k);
		}
		/* end of x > lntiny */

		else 
		     /* exp(-big#) underflows to zero */
		     if(finite(x))  return(scalb(1.0,-5000));

		     /* exp(-INF) is zero */
		     else return(0.0);
	}
	/* end of x < lnhuge */

	else 
	/* exp(INF) is INF, exp(+big#) overflows to INF */
	    return( finite(x) ?  scalb(1.0,5000)  : x);
}

/* Modified Nov 30, 1992 P. McILROY:
 *	Replaced expansions for x >= 1.25 (error 1.7ulp vs ~6ulp)
 * Replaced even+odd with direct calculation for x < .84375,
 * to avoid destructive cancellation.
 *
 * Performance of erfc(x):
 * In 300000 trials in the range [.83, .84375] the
 * maximum observed error was 3.6ulp.
 *
 * In [.84735,1.25] the maximum observed error was <2.5ulp in
 * 100000 runs in the range [1.2, 1.25].
 *
 * In [1.25,26] (Not including subnormal results)
 * the error is < 1.7ulp.
 */

/* double erf(double x)
 * double erfc(double x)
 *			     x
 *		      2      |\
 *     erf(x)  =  ---------  | exp(-t*t)dt
 *		   sqrt(pi) \|
 *			     0
 *
 *     erfc(x) =  1-erf(x)
 *
 * Method:
 *      1. Reduce x to |x| by erf(-x) = -erf(x)
 *	2. For x in [0, 0.84375]
 *	    erf(x)  = x + x*P(x^2)
 *          erfc(x) = 1 - erf(x)           if x<=0.25
 *                  = 0.5 + ((0.5-x)-x*P)  if x in [0.25,0.84375]
 *	   where
 *			2		 2	  4		  20  
 *              P =  P(x ) = (p0 + p1 * x + p2 * x + ... + p10 * x  )
 * 	   is an approximation to (erf(x)-x)/x with precision
 *
 *						 -56.45
 *			| P - (erf(x)-x)/x | <= 2
 *	
 *
 *	   Remark. The formula is derived by noting
 *          erf(x) = (2/sqrt(pi))*(x - x^3/3 + x^5/10 - x^7/42 + ....)
 *	   and that
 *          2/sqrt(pi) = 1.128379167095512573896158903121545171688
 *	   is close to one. The interval is chosen because the fixed
 *	   point of erf(x) is near 0.6174 (i.e., erf(x)=x when x is
 *	   near 0.6174), and by some experiment, 0.84375 is chosen to
 * 	   guarantee the error is less than one ulp for erf.
 *
 *      3. For x in [0.84375,1.25], let s = x - 1, and
 *         c = 0.84506291151 rounded to single (24 bits)
 *         	erf(x)  = c  + P1(s)/Q1(s)
 *         	erfc(x) = (1-c)  - P1(s)/Q1(s)
 *         	|P1/Q1 - (erf(x)-c)| <= 2**-59.06
 *	   Remark: here we use the taylor series expansion at x=1.
 *		erf(1+s) = erf(1) + s*Poly(s)
 *			 = 0.845.. + P1(s)/Q1(s)
 *	   That is, we use rational approximation to approximate
 *			erf(1+s) - (c = (single)0.84506291151)
 *	   Note that |P1/Q1|< 0.078 for x in [0.84375,1.25]
 *	   where 
 *		P1(s) = degree 6 poly in s
 *		Q1(s) = degree 6 poly in s
 *
 *	4. For x in [1.25, 2]; [2, 4]
 *         	erf(x)  = 1.0 - tiny
 *		erfc(x)	= (1/x)exp(-x*x-(.5*log(pi) -.5z + R(z)/S(z))
 *
 *	Where z = 1/(x*x), R is degree 9, and S is degree 3;
 *	
 *      5. For x in [4,28]
 *         	erf(x)  = 1.0 - tiny
 *		erfc(x)	= (1/x)exp(-x*x-(.5*log(pi)+eps + zP(z))
 *
 *	Where P is degree 14 polynomial in 1/(x*x).
 *
 *      Notes:
 *	   Here 4 and 5 make use of the asymptotic series
 *			  exp(-x*x)
 *		erfc(x) ~ ---------- * ( 1 + Poly(1/x^2) );
 *			  x*sqrt(pi)
 *
 *		where for z = 1/(x*x)
 *		P(z) ~ z/2*(-1 + z*3/2*(1 + z*5/2*(-1 + z*7/2*(1 +...))))
 *
 *	   Thus we use rational approximation to approximate
 *              erfc*x*exp(x*x) ~ 1/sqrt(pi);
 *
 *		The error bound for the target function, G(z) for
 *		the interval
 *		[4, 28]:
 * 		|eps + 1/(z)P(z) - G(z)| < 2**(-56.61)
 *		for [2, 4]:
 *      	|R(z)/S(z) - G(z)|	 < 2**(-58.24)
 *		for [1.25, 2]:
 *		|R(z)/S(z) - G(z)|	 < 2**(-58.12)
 *
 *      6. For inf > x >= 28
 *         	erf(x)  = 1 - tiny  (raise inexact)
 *         	erfc(x) = tiny*tiny (raise underflow)
 *
 *      7. Special cases:
 *         	erf(0)  = 0, erf(inf)  = 1, erf(-inf) = -1,
 *         	erfc(0) = 1, erfc(inf) = 0, erfc(-inf) = 2, 
 *	   	erfc/erf(NaN) is NaN
 */

#if defined(vax) || defined(tahoe)
#define _IEEE	0
#define TRUNC(x) (double) (float) (x)
#else
#define _IEEE	1
#define TRUNC(x) *(((int *) &x) + 1) &= 0xf8000000
#define infnan(x) 0.0
#endif

#ifdef _IEEE_LIBM
/*
 * redefining "___function" to "function" in _IEEE_LIBM mode
 */
#include "ieee_libm.h"
#endif

const static double
tiny	    = 1e-300,
half	    = 0.5,
one	    = 1.0,
two	    = 2.0,
c 	    = 8.45062911510467529297e-01, /* (float)0.84506291151 */
/*
 * Coefficients for approximation to erf in [0,0.84375]
 */
p0t8 = 1.02703333676410051049867154944018394163280,
p0 =   1.283791670955125638123339436800229927041e-0001,
p1 =  -3.761263890318340796574473028946097022260e-0001,
p2 =   1.128379167093567004871858633779992337238e-0001,
p3 =  -2.686617064084433642889526516177508374437e-0002,
p4 =   5.223977576966219409445780927846432273191e-0003,
p5 =  -8.548323822001639515038738961618255438422e-0004,
p6 =   1.205520092530505090384383082516403772317e-0004,
p7 =  -1.492214100762529635365672665955239554276e-0005,
p8 =   1.640186161764254363152286358441771740838e-0006,
p9 =  -1.571599331700515057841960987689515895479e-0007,
p10=   1.073087585213621540635426191486561494058e-0008;
/*
 * Coefficients for approximation to erf in [0.84375,1.25] 
 */
static double
pa0 =  -2.362118560752659485957248365514511540287e-0003,
pa1 =   4.148561186837483359654781492060070469522e-0001,
pa2 =  -3.722078760357013107593507594535478633044e-0001,
pa3 =   3.183466199011617316853636418691420262160e-0001,
pa4 =  -1.108946942823966771253985510891237782544e-0001,
pa5 =   3.547830432561823343969797140537411825179e-0002,
pa6 =  -2.166375594868790886906539848893221184820e-0003,
qa1 =   1.064208804008442270765369280952419863524e-0001,
qa2 =   5.403979177021710663441167681878575087235e-0001,
qa3 =   7.182865441419627066207655332170665812023e-0002,
qa4 =   1.261712198087616469108438860983447773726e-0001,
qa5 =   1.363708391202905087876983523620537833157e-0002,
qa6 =   1.198449984679910764099772682882189711364e-0002;
/*
 * log(sqrt(pi)) for large x expansions.
 * The tail (lsqrtPI_lo) is included in the rational
 * approximations.
*/
static double
   lsqrtPI_hi = .5723649429247000819387380943226;
/*
 * lsqrtPI_lo = .000000000000000005132975581353913;
 *
 * Coefficients for approximation to erfc in [2, 4]
*/
static double
rb0  =	-1.5306508387410807582e-010,	/* includes lsqrtPI_lo */
rb1  =	 2.15592846101742183841910806188e-008,
rb2  =	 6.24998557732436510470108714799e-001,
rb3  =	 8.24849222231141787631258921465e+000,
rb4  =	 2.63974967372233173534823436057e+001,
rb5  =	 9.86383092541570505318304640241e+000,
rb6  =	-7.28024154841991322228977878694e+000,
rb7  =	 5.96303287280680116566600190708e+000,
rb8  =	-4.40070358507372993983608466806e+000,
rb9  =	 2.39923700182518073731330332521e+000,
rb10 =	-6.89257464785841156285073338950e-001,
sb1  =	 1.56641558965626774835300238919e+001,
sb2  =	 7.20522741000949622502957936376e+001,
sb3  =	 9.60121069770492994166488642804e+001;
/*
 * Coefficients for approximation to erfc in [1.25, 2]
*/
static double
rc0  =	-2.47925334685189288817e-007,	/* includes lsqrtPI_lo */
rc1  =	 1.28735722546372485255126993930e-005,
rc2  =	 6.24664954087883916855616917019e-001,
rc3  =	 4.69798884785807402408863708843e+000,
rc4  =	 7.61618295853929705430118701770e+000,
rc5  =	 9.15640208659364240872946538730e-001,
rc6  =	-3.59753040425048631334448145935e-001,
rc7  =	 1.42862267989304403403849619281e-001,
rc8  =	-4.74392758811439801958087514322e-002,
rc9  =	 1.09964787987580810135757047874e-002,
rc10 =	-1.28856240494889325194638463046e-003,
sc1  =	 9.97395106984001955652274773456e+000,
sc2  =	 2.80952153365721279953959310660e+001,
sc3  =	 2.19826478142545234106819407316e+001;
/*
 * Coefficients for approximation to  erfc in [4,28]
 */
static double
rd0  =	-2.1491361969012978677e-016,	/* includes lsqrtPI_lo */
rd1  =	-4.99999999999640086151350330820e-001,
rd2  =	 6.24999999772906433825880867516e-001,
rd3  =	-1.54166659428052432723177389562e+000,
rd4  =	 5.51561147405411844601985649206e+000,
rd5  =	-2.55046307982949826964613748714e+001,
rd6  =	 1.43631424382843846387913799845e+002,
rd7  =	-9.45789244999420134263345971704e+002,
rd8  =	 6.94834146607051206956384703517e+003,
rd9  =	-5.27176414235983393155038356781e+004,
rd10 =	 3.68530281128672766499221324921e+005,
rd11 =	-2.06466642800404317677021026611e+006,
rd12 =	 7.78293889471135381609201431274e+006,
rd13 =	-1.42821001129434127360582351685e+007;

double erf(x)
	double x;
{
	double R,S,P,Q,ax,s,y,z,r,fabs(),exp();
	if(!finite(x)) {		/* erf(nan)=nan */
	    if (isnan(x))
		return(x);
	    return (x > 0 ? one : -one); /* erf(+/-inf)= +/-1 */
	}
	if ((ax = x) < 0)
		ax = - ax;
	if (ax < .84375) {
	    if (ax < 3.7e-09) {
		if (ax < 1.0e-308)
		    return 0.125*(8.0*x+p0t8*x);  /*avoid underflow */
		return x + p0*x;
	    }
	    y = x*x;
	    r = y*(p1+y*(p2+y*(p3+y*(p4+y*(p5+
			y*(p6+y*(p7+y*(p8+y*(p9+y*p10)))))))));
	    return x + x*(p0+r);
	}
	if (ax < 1.25) {		/* 0.84375 <= |x| < 1.25 */
	    s = fabs(x)-one;
	    P = pa0+s*(pa1+s*(pa2+s*(pa3+s*(pa4+s*(pa5+s*pa6)))));
	    Q = one+s*(qa1+s*(qa2+s*(qa3+s*(qa4+s*(qa5+s*qa6)))));
	    if (x>=0)
		return (c + P/Q);
	    else
		return (-c - P/Q);
	}
	if (ax >= 6.0) {		/* inf>|x|>=6 */
	    if (x >= 0.0)
		return (one-tiny);
	    else
		return (tiny-one);
	}
    /* 1.25 <= |x| < 6 */
	z = -ax*ax;
	s = -one/z;
	if (ax < 2.0) {
		R = rc0+s*(rc1+s*(rc2+s*(rc3+s*(rc4+s*(rc5+
			s*(rc6+s*(rc7+s*(rc8+s*(rc9+s*rc10)))))))));
		S = one+s*(sc1+s*(sc2+s*sc3));
	} else {
		R = rb0+s*(rb1+s*(rb2+s*(rb3+s*(rb4+s*(rb5+
			s*(rb6+s*(rb7+s*(rb8+s*(rb9+s*rb10)))))))));
		S = one+s*(sb1+s*(sb2+s*sb3));
	}
	y = (R/S -.5*s) - lsqrtPI_hi;
	z += y;
	z = exp(z)/ax;
	if (x >= 0)
		return (one-z);
	else
		return (z-one);
}

double erfc(x) 
	double x;
{
	double R,S,P,Q,s,ax,y,z,r,fabs();
	if (!finite(x)) {
		if (isnan(x))		/* erfc(NaN) = NaN */
			return(x);
		else if (x > 0)		/* erfc(+-inf)=0,2 */
			return 0.0;
		else
			return 2.0;
	}
	if ((ax = x) < 0)
		ax = -ax;
	if (ax < .84375) {			/* |x|<0.84375 */
	    if (ax < 1.38777878078144568e-17)  	/* |x|<2**-56 */
		return one-x;
	    y = x*x;
	    r = y*(p1+y*(p2+y*(p3+y*(p4+y*(p5+
			y*(p6+y*(p7+y*(p8+y*(p9+y*p10)))))))));
	    if (ax < .0625) {  	/* |x|<2**-4 */
		return (one-(x+x*(p0+r)));
	    } else {
		r = x*(p0+r);
		r += (x-half);
	        return (half - r);
	    }
	}
	if (ax < 1.25) {		/* 0.84375 <= |x| < 1.25 */
	    s = ax-one;
	    P = pa0+s*(pa1+s*(pa2+s*(pa3+s*(pa4+s*(pa5+s*pa6)))));
	    Q = one+s*(qa1+s*(qa2+s*(qa3+s*(qa4+s*(qa5+s*qa6)))));
	    if (x>=0) {
	        z  = one-c; return z - P/Q; 
	    } else {
		z = c+P/Q; return one+z;
	    }
	}
	if (ax >= 28)	/* Out of range */
 		if (x>0)
			return (tiny*tiny);
		else
			return (two-tiny);
	z = ax;
	TRUNC(z);
	y = z - ax; y *= (ax+z);
	z *= -z;			/* Here z + y = -x^2 */
		s = one/(-z-y);		/* 1/(x*x) */
	if (ax >= 4) {			/* 6 <= ax */
		R = s*(rd1+s*(rd2+s*(rd3+s*(rd4+s*(rd5+
			s*(rd6+s*(rd7+s*(rd8+s*(rd9+s*(rd10
			+s*(rd11+s*(rd12+s*rd13))))))))))));
		y += rd0;
	} else if (ax >= 2) {
		R = rb0+s*(rb1+s*(rb2+s*(rb3+s*(rb4+s*(rb5+
			s*(rb6+s*(rb7+s*(rb8+s*(rb9+s*rb10)))))))));
		S = one+s*(sb1+s*(sb2+s*sb3));
		y += R/S;
		R = -.5*s;
	} else {
		R = rc0+s*(rc1+s*(rc2+s*(rc3+s*(rc4+s*(rc5+
			s*(rc6+s*(rc7+s*(rc8+s*(rc9+s*rc10)))))))));
		S = one+s*(sc1+s*(sc2+s*sc3));
		y += R/S;
		R = -.5*s;
	}
	/* return exp(-x^2 - lsqrtPI_hi + R + y)/x;	*/
	s = ((R + y) - lsqrtPI_hi) + z;
	y = (((z-s) - lsqrtPI_hi) + R) + y;
	r = __exp__D(s, y)/x;
	if (x>0)
		return r;
	else
		return two-r;
}
