/**********************************************************************

  util.c -

  $Author$
  created at: Fri Mar 10 17:22:34 JST 1995

  Copyright (C) 1993-2008 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "internal.h"

#include <ctype.h>
#include <stdio.h>
#include <errno.h>
#include <math.h>
#include <float.h>

#ifdef _WIN32
#include "missing/file.h"
#endif

#include "ruby/util.h"

unsigned long
ruby_scan_oct(const char *start, size_t len, size_t *retlen)
{
    register const char *s = start;
    register unsigned long retval = 0;

    while (len-- && *s >= '0' && *s <= '7') {
	retval <<= 3;
	retval |= *s++ - '0';
    }
    *retlen = (int)(s - start);	/* less than len */
    return retval;
}

unsigned long
ruby_scan_hex(const char *start, size_t len, size_t *retlen)
{
    static const char hexdigit[] = "0123456789abcdef0123456789ABCDEF";
    register const char *s = start;
    register unsigned long retval = 0;
    const char *tmp;

    while (len-- && *s && (tmp = strchr(hexdigit, *s))) {
	retval <<= 4;
	retval |= (tmp - hexdigit) & 15;
	s++;
    }
    *retlen = (int)(s - start);	/* less than len */
    return retval;
}

const signed char ruby_digit36_to_number_table[] = {
    /*     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f */
    /*0*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*1*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*2*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*3*/  0, 1, 2, 3, 4, 5, 6, 7, 8, 9,-1,-1,-1,-1,-1,-1,
    /*4*/ -1,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,
    /*5*/ 25,26,27,28,29,30,31,32,33,34,35,-1,-1,-1,-1,-1,
    /*6*/ -1,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,
    /*7*/ 25,26,27,28,29,30,31,32,33,34,35,-1,-1,-1,-1,-1,
    /*8*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*9*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*a*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*b*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*c*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*d*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*e*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    /*f*/ -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
};

static unsigned long
scan_digits(const char *str, int base, size_t *retlen, int *overflow)
{

    const char *start = str;
    unsigned long ret = 0, x;
    unsigned long mul_overflow = (~(unsigned long)0) / base;
    int c;
    *overflow = 0;

    while ((c = (unsigned char)*str++) != '\0') {
        int d = ruby_digit36_to_number_table[c];
        if (d == -1 || base <= d) {
            *retlen = (str-1) - start;
            return ret;
        }
        if (mul_overflow < ret)
            *overflow = 1;
        ret *= base;
        x = ret;
        ret += d;
        if (ret < x)
            *overflow = 1;
    }
    *retlen = (str-1) - start;
    return ret;
}

unsigned long
ruby_strtoul(const char *str, char **endptr, int base)
{
    int c, b, overflow;
    int sign = 0;
    size_t len;
    unsigned long ret;
    const char *subject_found = str;

    if (base == 1 || 36 < base) {
        errno = EINVAL;
        return 0;
    }

    while ((c = *str) && ISSPACE(c))
        str++;

    if (c == '+') {
        sign = 1;
        str++;
    }
    else if (c == '-') {
        sign = -1;
        str++;
    }

    if (str[0] == '0') {
        subject_found = str+1;
        if (base == 0 || base == 16) {
            if (str[1] == 'x' || str[1] == 'X') {
                b = 16;
                str += 2;
            }
            else {
                b = base == 0 ? 8 : 16;
                str++;
            }
        }
        else {
            b = base;
            str++;
        }
    }
    else {
        b = base == 0 ? 10 : base;
    }

    ret = scan_digits(str, b, &len, &overflow);

    if (0 < len)
        subject_found = str+len;

    if (endptr)
        *endptr = (char*)subject_found;

    if (overflow) {
        errno = ERANGE;
        return ULONG_MAX;
    }

    if (sign < 0) {
        ret = (unsigned long)(-(long)ret);
        return ret;
    }
    else {
        return ret;
    }
}

#include <sys/types.h>
#include <sys/stat.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#if defined(HAVE_FCNTL_H)
#include <fcntl.h>
#endif

#ifndef S_ISDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif


#ifndef HAVE_GNU_QSORT_R
/* mm.c */

#define mmtype long
#define mmcount (16 / SIZEOF_LONG)
#define A ((mmtype*)a)
#define B ((mmtype*)b)
#define C ((mmtype*)c)
#define D ((mmtype*)d)

#define mmstep (sizeof(mmtype) * mmcount)
#define mmprepare(base, size) do {\
 if (((VALUE)(base) % sizeof(mmtype)) == 0 && ((size) % sizeof(mmtype)) == 0) \
   if ((size) >= mmstep) mmkind = 1;\
   else              mmkind = 0;\
 else                mmkind = -1;\
 high = ((size) / mmstep) * mmstep;\
 low  = ((size) % mmstep);\
} while (0)\

#define mmarg mmkind, size, high, low
#define mmargdecl int mmkind, size_t size, size_t high, size_t low

static void mmswap_(register char *a, register char *b, mmargdecl)
{
 if (a == b) return;
 if (mmkind >= 0) {
   register mmtype s;
#if mmcount > 1
   if (mmkind > 0) {
     register char *t = a + high;
     do {
       s = A[0]; A[0] = B[0]; B[0] = s;
       s = A[1]; A[1] = B[1]; B[1] = s;
#if mmcount > 2
       s = A[2]; A[2] = B[2]; B[2] = s;
#if mmcount > 3
       s = A[3]; A[3] = B[3]; B[3] = s;
#endif
#endif
       a += mmstep; b += mmstep;
     } while (a < t);
   }
#endif
   if (low != 0) { s = A[0]; A[0] = B[0]; B[0] = s;
#if mmcount > 2
     if (low >= 2 * sizeof(mmtype)) { s = A[1]; A[1] = B[1]; B[1] = s;
#if mmcount > 3
       if (low >= 3 * sizeof(mmtype)) {s = A[2]; A[2] = B[2]; B[2] = s;}
#endif
     }
#endif
   }
 }
 else {
   register char *t = a + size, s;
   do {s = *a; *a++ = *b; *b++ = s;} while (a < t);
 }
}
#define mmswap(a,b) mmswap_((a),(b),mmarg)

/* a, b, c = b, c, a */
static void mmrot3_(register char *a, register char *b, register char *c, mmargdecl)
{
 if (mmkind >= 0) {
   register mmtype s;
#if mmcount > 1
   if (mmkind > 0) {
     register char *t = a + high;
     do {
       s = A[0]; A[0] = B[0]; B[0] = C[0]; C[0] = s;
       s = A[1]; A[1] = B[1]; B[1] = C[1]; C[1] = s;
#if mmcount > 2
       s = A[2]; A[2] = B[2]; B[2] = C[2]; C[2] = s;
#if mmcount > 3
       s = A[3]; A[3] = B[3]; B[3] = C[3]; C[3] = s;
#endif
#endif
       a += mmstep; b += mmstep; c += mmstep;
     } while (a < t);
   }
#endif
   if (low != 0) { s = A[0]; A[0] = B[0]; B[0] = C[0]; C[0] = s;
#if mmcount > 2
     if (low >= 2 * sizeof(mmtype)) { s = A[1]; A[1] = B[1]; B[1] = C[1]; C[1] = s;
#if mmcount > 3
       if (low == 3 * sizeof(mmtype)) {s = A[2]; A[2] = B[2]; B[2] = C[2]; C[2] = s;}
#endif
     }
#endif
   }
 }
 else {
   register char *t = a + size, s;
   do {s = *a; *a++ = *b; *b++ = *c; *c++ = s;} while (a < t);
 }
}
#define mmrot3(a,b,c) mmrot3_((a),(b),(c),mmarg)

/* qs6.c */
/*****************************************************/
/*                                                   */
/*          qs6   (Quick sort function)              */
/*                                                   */
/* by  Tomoyuki Kawamura              1995.4.21      */
/* kawamura@tokuyama.ac.jp                           */
/*****************************************************/

typedef struct { char *LL, *RR; } stack_node; /* Stack structure for L,l,R,r */
#define PUSH(ll,rr) do { top->LL = (ll); top->RR = (rr); ++top; } while (0)  /* Push L,l,R,r */
#define POP(ll,rr)  do { --top; (ll) = top->LL; (rr) = top->RR; } while (0)      /* Pop L,l,R,r */

#define med3(a,b,c) ((*cmp)((a),(b),d)<0 ?                                   \
                       ((*cmp)((b),(c),d)<0 ? (b) : ((*cmp)((a),(c),d)<0 ? (c) : (a))) : \
                       ((*cmp)((b),(c),d)>0 ? (b) : ((*cmp)((a),(c),d)<0 ? (a) : (c))))

typedef int (cmpfunc_t)(const void*, const void*, void*);
void
ruby_qsort(void* base, const size_t nel, const size_t size, cmpfunc_t *cmp, void *d)
{
  register char *l, *r, *m;          	/* l,r:left,right group   m:median point */
  register int t, eq_l, eq_r;       	/* eq_l: all items in left group are equal to S */
  char *L = base;                    	/* left end of current region */
  char *R = (char*)base + size*(nel-1); /* right end of current region */
  size_t chklim = 63;                   /* threshold of ordering element check */
  enum {size_bits = sizeof(size) * CHAR_BIT};
  stack_node stack[size_bits];          /* enough for size_t size */
  stack_node *top = stack;
  int mmkind;
  size_t high, low, n;

  if (nel <= 1) return;        /* need not to sort */
  mmprepare(base, size);
  goto start;

  nxt:
  if (stack == top) return;    /* return if stack is empty */
  POP(L,R);

  for (;;) {
    start:
    if (L + size == R) {       /* 2 elements */
      if ((*cmp)(L,R,d) > 0) mmswap(L,R); goto nxt;
    }

    l = L; r = R;
    n = (r - l + size) / size;  /* number of elements */
    m = l + size * (n >> 1);    /* calculate median value */

    if (n >= 60) {
      register char *m1;
      register char *m3;
      if (n >= 200) {
	n = size*(n>>3); /* number of bytes in splitting 8 */
	{
	  register char *p1 = l  + n;
	  register char *p2 = p1 + n;
	  register char *p3 = p2 + n;
	  m1 = med3(p1, p2, p3);
	  p1 = m  + n;
	  p2 = p1 + n;
	  p3 = p2 + n;
	  m3 = med3(p1, p2, p3);
	}
      }
      else {
	n = size*(n>>2); /* number of bytes in splitting 4 */
	m1 = l + n;
	m3 = m + n;
      }
      m = med3(m1, m, m3);
    }

    if ((t = (*cmp)(l,m,d)) < 0) {                           /*3-5-?*/
      if ((t = (*cmp)(m,r,d)) < 0) {                         /*3-5-7*/
	if (chklim && nel >= chklim) {   /* check if already ascending order */
	  char *p;
	  chklim = 0;
	  for (p=l; p<r; p+=size) if ((*cmp)(p,p+size,d) > 0) goto fail;
	  goto nxt;
	}
	fail: goto loopA;                                    /*3-5-7*/
      }
      if (t > 0) {
	if ((*cmp)(l,r,d) <= 0) {mmswap(m,r); goto loopA;}     /*3-5-4*/
	mmrot3(r,m,l); goto loopA;                           /*3-5-2*/
      }
      goto loopB;                                            /*3-5-5*/
    }

    if (t > 0) {                                             /*7-5-?*/
      if ((t = (*cmp)(m,r,d)) > 0) {                         /*7-5-3*/
	if (chklim && nel >= chklim) {   /* check if already ascending order */
	  char *p;
	  chklim = 0;
	  for (p=l; p<r; p+=size) if ((*cmp)(p,p+size,d) < 0) goto fail2;
	  while (l<r) {mmswap(l,r); l+=size; r-=size;}  /* reverse region */
	  goto nxt;
	}
	fail2: mmswap(l,r); goto loopA;                      /*7-5-3*/
      }
      if (t < 0) {
	if ((*cmp)(l,r,d) <= 0) {mmswap(l,m); goto loopB;}   /*7-5-8*/
	mmrot3(l,m,r); goto loopA;                           /*7-5-6*/
      }
      mmswap(l,r); goto loopA;                               /*7-5-5*/
    }

    if ((t = (*cmp)(m,r,d)) < 0)  {goto loopA;}              /*5-5-7*/
    if (t > 0) {mmswap(l,r); goto loopB;}                    /*5-5-3*/

    /* determining splitting type in case 5-5-5 */           /*5-5-5*/
    for (;;) {
      if ((l += size) == r)      goto nxt;                   /*5-5-5*/
      if (l == m) continue;
      if ((t = (*cmp)(l,m,d)) > 0) {mmswap(l,r); l = L; goto loopA;}/*575-5*/
      if (t < 0)                 {mmswap(L,l); l = L; goto loopB;}  /*535-5*/
    }

    loopA: eq_l = 1; eq_r = 1;  /* splitting type A */ /* left <= median < right */
    for (;;) {
      for (;;) {
	if ((l += size) == r)
	  {l -= size; if (l != m) mmswap(m,l); l -= size; goto fin;}
	if (l == m) continue;
	if ((t = (*cmp)(l,m,d)) > 0) {eq_r = 0; break;}
	if (t < 0) eq_l = 0;
      }
      for (;;) {
	if (l == (r -= size))
	  {l -= size; if (l != m) mmswap(m,l); l -= size; goto fin;}
	if (r == m) {m = l; break;}
	if ((t = (*cmp)(r,m,d)) < 0) {eq_l = 0; break;}
	if (t == 0) break;
      }
      mmswap(l,r);    /* swap left and right */
    }

    loopB: eq_l = 1; eq_r = 1;  /* splitting type B */ /* left < median <= right */
    for (;;) {
      for (;;) {
	if (l == (r -= size))
	  {r += size; if (r != m) mmswap(r,m); r += size; goto fin;}
	if (r == m) continue;
	if ((t = (*cmp)(r,m,d)) < 0) {eq_l = 0; break;}
	if (t > 0) eq_r = 0;
      }
      for (;;) {
	if ((l += size) == r)
	  {r += size; if (r != m) mmswap(r,m); r += size; goto fin;}
	if (l == m) {m = r; break;}
	if ((t = (*cmp)(l,m,d)) > 0) {eq_r = 0; break;}
	if (t == 0) break;
      }
      mmswap(l,r);    /* swap left and right */
    }

    fin:
    if (eq_l == 0)                         /* need to sort left side */
      if (eq_r == 0)                       /* need to sort right side */
	if (l-L < R-r) {PUSH(r,R); R = l;} /* sort left side first */
	else           {PUSH(L,l); L = r;} /* sort right side first */
      else R = l;                          /* need to sort left side only */
    else if (eq_r == 0) L = r;             /* need to sort right side only */
    else goto nxt;                         /* need not to sort both sides */
  }
}
#endif /* HAVE_GNU_QSORT_R */

char *
ruby_strdup(const char *str)
{
    char *tmp;
    size_t len = strlen(str) + 1;

    tmp = xmalloc(len);
    memcpy(tmp, str, len);

    return tmp;
}

#ifdef __native_client__
char *
ruby_getcwd(void)
{
    char *buf = xmalloc(2);
    strcpy(buf, ".");
    return buf;
}
#else
char *
ruby_getcwd(void)
{
#ifdef HAVE_GETCWD
    int size = 200;
    char *buf = xmalloc(size);

    while (!getcwd(buf, size)) {
	if (errno != ERANGE) {
	    xfree(buf);
	    rb_sys_fail("getcwd");
	}
	size *= 2;
	buf = xrealloc(buf, size);
    }
#else
# ifndef PATH_MAX
#  define PATH_MAX 8192
# endif
    char *buf = xmalloc(PATH_MAX+1);

    if (!getwd(buf)) {
	xfree(buf);
	rb_sys_fail("getwd");
    }
#endif
    return buf;
}
#endif

/****************************************************************
 *
 * The author of this software is David M. Gay.
 *
 * Copyright (c) 1991, 2000, 2001 by Lucent Technologies.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose without fee is hereby granted, provided that this entire notice
 * is included in all copies of any software which is or includes a copy
 * or modification of this software and in all copies of the supporting
 * documentation for such software.
 *
 * THIS SOFTWARE IS BEING PROVIDED "AS IS", WITHOUT ANY EXPRESS OR IMPLIED
 * WARRANTY.  IN PARTICULAR, NEITHER THE AUTHOR NOR LUCENT MAKES ANY
 * REPRESENTATION OR WARRANTY OF ANY KIND CONCERNING THE MERCHANTABILITY
 * OF THIS SOFTWARE OR ITS FITNESS FOR ANY PARTICULAR PURPOSE.
 *
 ***************************************************************/

/* Please send bug reports to David M. Gay (dmg at acm dot org,
 * with " at " changed at "@" and " dot " changed to ".").	*/

/* On a machine with IEEE extended-precision registers, it is
 * necessary to specify double-precision (53-bit) rounding precision
 * before invoking strtod or dtoa.  If the machine uses (the equivalent
 * of) Intel 80x87 arithmetic, the call
 *	_control87(PC_53, MCW_PC);
 * does this with many compilers.  Whether this or another call is
 * appropriate depends on the compiler; for this to work, it may be
 * necessary to #include "float.h" or another system-dependent header
 * file.
 */

/* strtod for IEEE-, VAX-, and IBM-arithmetic machines.
 *
 * This strtod returns a nearest machine number to the input decimal
 * string (or sets errno to ERANGE).  With IEEE arithmetic, ties are
 * broken by the IEEE round-even rule.  Otherwise ties are broken by
 * biased rounding (add half and chop).
 *
 * Inspired loosely by William D. Clinger's paper "How to Read Floating
 * Point Numbers Accurately" [Proc. ACM SIGPLAN '90, pp. 92-101].
 *
 * Modifications:
 *
 *	1. We only require IEEE, IBM, or VAX double-precision
 *		arithmetic (not IEEE double-extended).
 *	2. We get by with floating-point arithmetic in a case that
 *		Clinger missed -- when we're computing d * 10^n
 *		for a small integer d and the integer n is not too
 *		much larger than 22 (the maximum integer k for which
 *		we can represent 10^k exactly), we may be able to
 *		compute (d*10^k) * 10^(e-k) with just one roundoff.
 *	3. Rather than a bit-at-a-time adjustment of the binary
 *		result in the hard case, we use floating-point
 *		arithmetic to determine the adjustment to within
 *		one bit; only in really hard cases do we need to
 *		compute a second residual.
 *	4. Because of 3., we don't need a large table of powers of 10
 *		for ten-to-e (just some small tables, e.g. of 10^k
 *		for 0 <= k <= 22).
 */

/*
 * #define IEEE_LITTLE_ENDIAN for IEEE-arithmetic machines where the least
 *	significant byte has the lowest address.
 * #define IEEE_BIG_ENDIAN for IEEE-arithmetic machines where the most
 *	significant byte has the lowest address.
 * #define Long int on machines with 32-bit ints and 64-bit longs.
 * #define IBM for IBM mainframe-style floating-point arithmetic.
 * #define VAX for VAX-style floating-point arithmetic (D_floating).
 * #define No_leftright to omit left-right logic in fast floating-point
 *	computation of dtoa.
 * #define Honor_FLT_ROUNDS if FLT_ROUNDS can assume the values 2 or 3
 *	and strtod and dtoa should round accordingly.
 * #define Check_FLT_ROUNDS if FLT_ROUNDS can assume the values 2 or 3
 *	and Honor_FLT_ROUNDS is not #defined.
 * #define RND_PRODQUOT to use rnd_prod and rnd_quot (assembly routines
 *	that use extended-precision instructions to compute rounded
 *	products and quotients) with IBM.
 * #define ROUND_BIASED for IEEE-format with biased rounding.
 * #define Inaccurate_Divide for IEEE-format with correctly rounded
 *	products but inaccurate quotients, e.g., for Intel i860.
 * #define NO_LONG_LONG on machines that do not have a "long long"
 *	integer type (of >= 64 bits).  On such machines, you can
 *	#define Just_16 to store 16 bits per 32-bit Long when doing
 *	high-precision integer arithmetic.  Whether this speeds things
 *	up or slows things down depends on the machine and the number
 *	being converted.  If long long is available and the name is
 *	something other than "long long", #define Llong to be the name,
 *	and if "unsigned Llong" does not work as an unsigned version of
 *	Llong, #define #ULLong to be the corresponding unsigned type.
 * #define KR_headers for old-style C function headers.
 * #define Bad_float_h if your system lacks a float.h or if it does not
 *	define some or all of DBL_DIG, DBL_MAX_10_EXP, DBL_MAX_EXP,
 *	FLT_RADIX, FLT_ROUNDS, and DBL_MAX.
 * #define MALLOC your_malloc, where your_malloc(n) acts like malloc(n)
 *	if memory is available and otherwise does something you deem
 *	appropriate.  If MALLOC is undefined, malloc will be invoked
 *	directly -- and assumed always to succeed.
 * #define Omit_Private_Memory to omit logic (added Jan. 1998) for making
 *	memory allocations from a private pool of memory when possible.
 *	When used, the private pool is PRIVATE_MEM bytes long:  2304 bytes,
 *	unless #defined to be a different length.  This default length
 *	suffices to get rid of MALLOC calls except for unusual cases,
 *	such as decimal-to-binary conversion of a very long string of
 *	digits.  The longest string dtoa can return is about 751 bytes
 *	long.  For conversions by strtod of strings of 800 digits and
 *	all dtoa conversions in single-threaded executions with 8-byte
 *	pointers, PRIVATE_MEM >= 7400 appears to suffice; with 4-byte
 *	pointers, PRIVATE_MEM >= 7112 appears adequate.
 * #define INFNAN_CHECK on IEEE systems to cause strtod to check for
 *	Infinity and NaN (case insensitively).  On some systems (e.g.,
 *	some HP systems), it may be necessary to #define NAN_WORD0
 *	appropriately -- to the most significant word of a quiet NaN.
 *	(On HP Series 700/800 machines, -DNAN_WORD0=0x7ff40000 works.)
 *	When INFNAN_CHECK is #defined and No_Hex_NaN is not #defined,
 *	strtod also accepts (case insensitively) strings of the form
 *	NaN(x), where x is a string of hexadecimal digits and spaces;
 *	if there is only one string of hexadecimal digits, it is taken
 *	for the 52 fraction bits of the resulting NaN; if there are two
 *	or more strings of hex digits, the first is for the high 20 bits,
 *	the second and subsequent for the low 32 bits, with intervening
 *	white space ignored; but if this results in none of the 52
 *	fraction bits being on (an IEEE Infinity symbol), then NAN_WORD0
 *	and NAN_WORD1 are used instead.
 * #define MULTIPLE_THREADS if the system offers preemptively scheduled
 *	multiple threads.  In this case, you must provide (or suitably
 *	#define) two locks, acquired by ACQUIRE_DTOA_LOCK(n) and freed
 *	by FREE_DTOA_LOCK(n) for n = 0 or 1.  (The second lock, accessed
 *	in pow5mult, ensures lazy evaluation of only one copy of high
 *	powers of 5; omitting this lock would introduce a small
 *	probability of wasting memory, but would otherwise be harmless.)
 *	You must also invoke freedtoa(s) to free the value s returned by
 *	dtoa.  You may do so whether or not MULTIPLE_THREADS is #defined.
 * #define NO_IEEE_Scale to disable new (Feb. 1997) logic in strtod that
 *	avoids underflows on inputs whose result does not underflow.
 *	If you #define NO_IEEE_Scale on a machine that uses IEEE-format
 *	floating-point numbers and flushes underflows to zero rather
 *	than implementing gradual underflow, then you must also #define
 *	Sudden_Underflow.
 * #define YES_ALIAS to permit aliasing certain double values with
 *	arrays of ULongs.  This leads to slightly better code with
 *	some compilers and was always used prior to 19990916, but it
 *	is not strictly legal and can cause trouble with aggressively
 *	optimizing compilers (e.g., gcc 2.95.1 under -O2).
 * #define USE_LOCALE to use the current locale's decimal_point value.
 * #define SET_INEXACT if IEEE arithmetic is being used and extra
 *	computation should be done to set the inexact flag when the
 *	result is inexact and avoid setting inexact when the result
 *	is exact.  In this case, dtoa.c must be compiled in
 *	an environment, perhaps provided by #include "dtoa.c" in a
 *	suitable wrapper, that defines two functions,
 *		int get_inexact(void);
 *		void clear_inexact(void);
 *	such that get_inexact() returns a nonzero value if the
 *	inexact bit is already set, and clear_inexact() sets the
 *	inexact bit to 0.  When SET_INEXACT is #defined, strtod
 *	also does extra computations to set the underflow and overflow
 *	flags when appropriate (i.e., when the result is tiny and
 *	inexact or when it is a numeric value rounded to +-infinity).
 * #define NO_ERRNO if strtod should not assign errno = ERANGE when
 *	the result overflows to +-Infinity or underflows to 0.
 */

#ifdef WORDS_BIGENDIAN
#define IEEE_BIG_ENDIAN
#else
#define IEEE_LITTLE_ENDIAN
#endif

#ifdef __vax__
#define VAX
#undef IEEE_BIG_ENDIAN
#undef IEEE_LITTLE_ENDIAN
#endif

#if defined(__arm__) && !defined(__VFP_FP__)
#define IEEE_BIG_ENDIAN
#undef IEEE_LITTLE_ENDIAN
#endif

#undef Long
#undef ULong

#if SIZEOF_INT == 4
#define Long int
#define ULong unsigned int
#elif SIZEOF_LONG == 4
#define Long long int
#define ULong unsigned long int
#endif

#if HAVE_LONG_LONG
#define Llong LONG_LONG
#endif

#ifdef DEBUG
#include "stdio.h"
#define Bug(x) {fprintf(stderr, "%s\n", (x)); exit(EXIT_FAILURE);}
#endif

#include "stdlib.h"
#include "string.h"

#ifdef USE_LOCALE
#include "locale.h"
#endif

#ifdef MALLOC
extern void *MALLOC(size_t);
#else
#define MALLOC malloc
#endif
#ifdef FREE
extern void FREE(void*);
#else
#define FREE free
#endif

#ifndef Omit_Private_Memory
#ifndef PRIVATE_MEM
#define PRIVATE_MEM 2304
#endif
#define PRIVATE_mem ((PRIVATE_MEM+sizeof(double)-1)/sizeof(double))
static double private_mem[PRIVATE_mem], *pmem_next = private_mem;
#endif

#undef IEEE_Arith
#undef Avoid_Underflow
#ifdef IEEE_BIG_ENDIAN
#define IEEE_Arith
#endif
#ifdef IEEE_LITTLE_ENDIAN
#define IEEE_Arith
#endif

#ifdef Bad_float_h

#ifdef IEEE_Arith
#define DBL_DIG 15
#define DBL_MAX_10_EXP 308
#define DBL_MAX_EXP 1024
#define FLT_RADIX 2
#endif /*IEEE_Arith*/

#ifdef IBM
#define DBL_DIG 16
#define DBL_MAX_10_EXP 75
#define DBL_MAX_EXP 63
#define FLT_RADIX 16
#define DBL_MAX 7.2370055773322621e+75
#endif

#ifdef VAX
#define DBL_DIG 16
#define DBL_MAX_10_EXP 38
#define DBL_MAX_EXP 127
#define FLT_RADIX 2
#define DBL_MAX 1.7014118346046923e+38
#endif

#ifndef LONG_MAX
#define LONG_MAX 2147483647
#endif

#else /* ifndef Bad_float_h */
#include "float.h"
#endif /* Bad_float_h */

#ifndef __MATH_H__
#include "math.h"
#endif

#ifdef __cplusplus
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#if defined(IEEE_LITTLE_ENDIAN) + defined(IEEE_BIG_ENDIAN) + defined(VAX) + defined(IBM) != 1
Exactly one of IEEE_LITTLE_ENDIAN, IEEE_BIG_ENDIAN, VAX, or IBM should be defined.
#endif

typedef union { double d; ULong L[2]; } U;

#ifdef YES_ALIAS
typedef double double_u;
#  define dval(x) (x)
#  ifdef IEEE_LITTLE_ENDIAN
#    define word0(x) (((ULong *)&(x))[1])
#    define word1(x) (((ULong *)&(x))[0])
#  else
#    define word0(x) (((ULong *)&(x))[0])
#    define word1(x) (((ULong *)&(x))[1])
#  endif
#else
typedef U double_u;
#  ifdef IEEE_LITTLE_ENDIAN
#    define word0(x) ((x).L[1])
#    define word1(x) ((x).L[0])
#  else
#    define word0(x) ((x).L[0])
#    define word1(x) ((x).L[1])
#  endif
#  define dval(x) ((x).d)
#endif

/* The following definition of Storeinc is appropriate for MIPS processors.
 * An alternative that might be better on some machines is
 * #define Storeinc(a,b,c) (*a++ = b << 16 | c & 0xffff)
 */
#if defined(IEEE_LITTLE_ENDIAN) + defined(VAX) + defined(__arm__)
#define Storeinc(a,b,c) (((unsigned short *)(a))[1] = (unsigned short)(b), \
((unsigned short *)(a))[0] = (unsigned short)(c), (a)++)
#else
#define Storeinc(a,b,c) (((unsigned short *)(a))[0] = (unsigned short)(b), \
((unsigned short *)(a))[1] = (unsigned short)(c), (a)++)
#endif

/* #define P DBL_MANT_DIG */
/* Ten_pmax = floor(P*log(2)/log(5)) */
/* Bletch = (highest power of 2 < DBL_MAX_10_EXP) / 16 */
/* Quick_max = floor((P-1)*log(FLT_RADIX)/log(10) - 1) */
/* Int_max = floor(P*log(FLT_RADIX)/log(10) - 1) */

#ifdef IEEE_Arith
#define Exp_shift  20
#define Exp_shift1 20
#define Exp_msk1    0x100000
#define Exp_msk11   0x100000
#define Exp_mask  0x7ff00000
#define P 53
#define Bias 1023
#define Emin (-1022)
#define Exp_1  0x3ff00000
#define Exp_11 0x3ff00000
#define Ebits 11
#define Frac_mask  0xfffff
#define Frac_mask1 0xfffff
#define Ten_pmax 22
#define Bletch 0x10
#define Bndry_mask  0xfffff
#define Bndry_mask1 0xfffff
#define LSB 1
#define Sign_bit 0x80000000
#define Log2P 1
#define Tiny0 0
#define Tiny1 1
#define Quick_max 14
#define Int_max 14
#ifndef NO_IEEE_Scale
#define Avoid_Underflow
#ifdef Flush_Denorm	/* debugging option */
#undef Sudden_Underflow
#endif
#endif

#ifndef Flt_Rounds
#ifdef FLT_ROUNDS
#define Flt_Rounds FLT_ROUNDS
#else
#define Flt_Rounds 1
#endif
#endif /*Flt_Rounds*/

#ifdef Honor_FLT_ROUNDS
#define Rounding rounding
#undef Check_FLT_ROUNDS
#define Check_FLT_ROUNDS
#else
#define Rounding Flt_Rounds
#endif

#else /* ifndef IEEE_Arith */
#undef Check_FLT_ROUNDS
#undef Honor_FLT_ROUNDS
#undef SET_INEXACT
#undef  Sudden_Underflow
#define Sudden_Underflow
#ifdef IBM
#undef Flt_Rounds
#define Flt_Rounds 0
#define Exp_shift  24
#define Exp_shift1 24
#define Exp_msk1   0x1000000
#define Exp_msk11  0x1000000
#define Exp_mask  0x7f000000
#define P 14
#define Bias 65
#define Exp_1  0x41000000
#define Exp_11 0x41000000
#define Ebits 8	/* exponent has 7 bits, but 8 is the right value in b2d */
#define Frac_mask  0xffffff
#define Frac_mask1 0xffffff
#define Bletch 4
#define Ten_pmax 22
#define Bndry_mask  0xefffff
#define Bndry_mask1 0xffffff
#define LSB 1
#define Sign_bit 0x80000000
#define Log2P 4
#define Tiny0 0x100000
#define Tiny1 0
#define Quick_max 14
#define Int_max 15
#else /* VAX */
#undef Flt_Rounds
#define Flt_Rounds 1
#define Exp_shift  23
#define Exp_shift1 7
#define Exp_msk1    0x80
#define Exp_msk11   0x800000
#define Exp_mask  0x7f80
#define P 56
#define Bias 129
#define Exp_1  0x40800000
#define Exp_11 0x4080
#define Ebits 8
#define Frac_mask  0x7fffff
#define Frac_mask1 0xffff007f
#define Ten_pmax 24
#define Bletch 2
#define Bndry_mask  0xffff007f
#define Bndry_mask1 0xffff007f
#define LSB 0x10000
#define Sign_bit 0x8000
#define Log2P 1
#define Tiny0 0x80
#define Tiny1 0
#define Quick_max 15
#define Int_max 15
#endif /* IBM, VAX */
#endif /* IEEE_Arith */

#ifndef IEEE_Arith
#define ROUND_BIASED
#endif

#ifdef RND_PRODQUOT
#define rounded_product(a,b) ((a) = rnd_prod((a), (b)))
#define rounded_quotient(a,b) ((a) = rnd_quot((a), (b)))
extern double rnd_prod(double, double), rnd_quot(double, double);
#else
#define rounded_product(a,b) ((a) *= (b))
#define rounded_quotient(a,b) ((a) /= (b))
#endif

#define Big0 (Frac_mask1 | Exp_msk1*(DBL_MAX_EXP+Bias-1))
#define Big1 0xffffffff

#ifndef Pack_32
#define Pack_32
#endif

#define FFFFFFFF 0xffffffffUL

#ifdef NO_LONG_LONG
#undef ULLong
#ifdef Just_16
#undef Pack_32
/* When Pack_32 is not defined, we store 16 bits per 32-bit Long.
 * This makes some inner loops simpler and sometimes saves work
 * during multiplications, but it often seems to make things slightly
 * slower.  Hence the default is now to store 32 bits per Long.
 */
#endif
#else	/* long long available */
#ifndef Llong
#define Llong long long
#endif
#ifndef ULLong
#define ULLong unsigned Llong
#endif
#endif /* NO_LONG_LONG */

#define MULTIPLE_THREADS 1

#ifndef MULTIPLE_THREADS
#define ACQUIRE_DTOA_LOCK(n)	/*nothing*/
#define FREE_DTOA_LOCK(n)	/*nothing*/
#else
#define ACQUIRE_DTOA_LOCK(n)	/*unused right now*/
#define FREE_DTOA_LOCK(n)	/*unused right now*/
#endif

#define Kmax 15

struct Bigint {
    struct Bigint *next;
    int k, maxwds, sign, wds;
    ULong x[1];
};

typedef struct Bigint Bigint;

static Bigint *freelist[Kmax+1];

static Bigint *
Balloc(int k)
{
    int x;
    Bigint *rv;
#ifndef Omit_Private_Memory
    size_t len;
#endif

    ACQUIRE_DTOA_LOCK(0);
    if (k <= Kmax && (rv = freelist[k]) != 0) {
        freelist[k] = rv->next;
    }
    else {
        x = 1 << k;
#ifdef Omit_Private_Memory
        rv = (Bigint *)MALLOC(sizeof(Bigint) + (x-1)*sizeof(ULong));
#else
        len = (sizeof(Bigint) + (x-1)*sizeof(ULong) + sizeof(double) - 1)
                /sizeof(double);
        if (k <= Kmax && pmem_next - private_mem + len <= PRIVATE_mem) {
            rv = (Bigint*)pmem_next;
            pmem_next += len;
        }
        else
            rv = (Bigint*)MALLOC(len*sizeof(double));
#endif
        rv->k = k;
        rv->maxwds = x;
    }
    FREE_DTOA_LOCK(0);
    rv->sign = rv->wds = 0;
    return rv;
}

static void
Bfree(Bigint *v)
{
    if (v) {
        if (v->k > Kmax) {
            FREE(v);
            return;
        }
        ACQUIRE_DTOA_LOCK(0);
        v->next = freelist[v->k];
        freelist[v->k] = v;
        FREE_DTOA_LOCK(0);
    }
}

#define Bcopy(x,y) memcpy((char *)&(x)->sign, (char *)&(y)->sign, \
(y)->wds*sizeof(Long) + 2*sizeof(int))

static Bigint *
multadd(Bigint *b, int m, int a)   /* multiply by m and add a */
{
    int i, wds;
    ULong *x;
#ifdef ULLong
    ULLong carry, y;
#else
    ULong carry, y;
#ifdef Pack_32
    ULong xi, z;
#endif
#endif
    Bigint *b1;

    wds = b->wds;
    x = b->x;
    i = 0;
    carry = a;
    do {
#ifdef ULLong
        y = *x * (ULLong)m + carry;
        carry = y >> 32;
        *x++ = (ULong)(y & FFFFFFFF);
#else
#ifdef Pack_32
        xi = *x;
        y = (xi & 0xffff) * m + carry;
        z = (xi >> 16) * m + (y >> 16);
        carry = z >> 16;
        *x++ = (z << 16) + (y & 0xffff);
#else
        y = *x * m + carry;
        carry = y >> 16;
        *x++ = y & 0xffff;
#endif
#endif
    } while (++i < wds);
    if (carry) {
        if (wds >= b->maxwds) {
            b1 = Balloc(b->k+1);
            Bcopy(b1, b);
            Bfree(b);
            b = b1;
        }
        b->x[wds++] = (ULong)carry;
        b->wds = wds;
    }
    return b;
}

static Bigint *
s2b(const char *s, int nd0, int nd, ULong y9)
{
    Bigint *b;
    int i, k;
    Long x, y;

    x = (nd + 8) / 9;
    for (k = 0, y = 1; x > y; y <<= 1, k++) ;
#ifdef Pack_32
    b = Balloc(k);
    b->x[0] = y9;
    b->wds = 1;
#else
    b = Balloc(k+1);
    b->x[0] = y9 & 0xffff;
    b->wds = (b->x[1] = y9 >> 16) ? 2 : 1;
#endif

    i = 9;
    if (9 < nd0) {
        s += 9;
        do {
            b = multadd(b, 10, *s++ - '0');
        } while (++i < nd0);
        s++;
    }
    else
        s += 10;
    for (; i < nd; i++)
        b = multadd(b, 10, *s++ - '0');
    return b;
}

static int
hi0bits(register ULong x)
{
    register int k = 0;

    if (!(x & 0xffff0000)) {
        k = 16;
        x <<= 16;
    }
    if (!(x & 0xff000000)) {
        k += 8;
        x <<= 8;
    }
    if (!(x & 0xf0000000)) {
        k += 4;
        x <<= 4;
    }
    if (!(x & 0xc0000000)) {
        k += 2;
        x <<= 2;
    }
    if (!(x & 0x80000000)) {
        k++;
        if (!(x & 0x40000000))
            return 32;
    }
    return k;
}

static int
lo0bits(ULong *y)
{
    register int k;
    register ULong x = *y;

    if (x & 7) {
        if (x & 1)
            return 0;
        if (x & 2) {
            *y = x >> 1;
            return 1;
        }
        *y = x >> 2;
        return 2;
    }
    k = 0;
    if (!(x & 0xffff)) {
        k = 16;
        x >>= 16;
    }
    if (!(x & 0xff)) {
        k += 8;
        x >>= 8;
    }
    if (!(x & 0xf)) {
        k += 4;
        x >>= 4;
    }
    if (!(x & 0x3)) {
        k += 2;
        x >>= 2;
    }
    if (!(x & 1)) {
        k++;
        x >>= 1;
        if (!x)
            return 32;
    }
    *y = x;
    return k;
}

static Bigint *
i2b(int i)
{
    Bigint *b;

    b = Balloc(1);
    b->x[0] = i;
    b->wds = 1;
    return b;
}

static Bigint *
mult(Bigint *a, Bigint *b)
{
    Bigint *c;
    int k, wa, wb, wc;
    ULong *x, *xa, *xae, *xb, *xbe, *xc, *xc0;
    ULong y;
#ifdef ULLong
    ULLong carry, z;
#else
    ULong carry, z;
#ifdef Pack_32
    ULong z2;
#endif
#endif

    if (a->wds < b->wds) {
        c = a;
        a = b;
        b = c;
    }
    k = a->k;
    wa = a->wds;
    wb = b->wds;
    wc = wa + wb;
    if (wc > a->maxwds)
        k++;
    c = Balloc(k);
    for (x = c->x, xa = x + wc; x < xa; x++)
        *x = 0;
    xa = a->x;
    xae = xa + wa;
    xb = b->x;
    xbe = xb + wb;
    xc0 = c->x;
#ifdef ULLong
    for (; xb < xbe; xc0++) {
        if ((y = *xb++) != 0) {
            x = xa;
            xc = xc0;
            carry = 0;
            do {
                z = *x++ * (ULLong)y + *xc + carry;
                carry = z >> 32;
                *xc++ = (ULong)(z & FFFFFFFF);
            } while (x < xae);
            *xc = (ULong)carry;
        }
    }
#else
#ifdef Pack_32
    for (; xb < xbe; xb++, xc0++) {
        if (y = *xb & 0xffff) {
            x = xa;
            xc = xc0;
            carry = 0;
            do {
                z = (*x & 0xffff) * y + (*xc & 0xffff) + carry;
                carry = z >> 16;
                z2 = (*x++ >> 16) * y + (*xc >> 16) + carry;
                carry = z2 >> 16;
                Storeinc(xc, z2, z);
            } while (x < xae);
            *xc = (ULong)carry;
        }
        if (y = *xb >> 16) {
            x = xa;
            xc = xc0;
            carry = 0;
            z2 = *xc;
            do {
                z = (*x & 0xffff) * y + (*xc >> 16) + carry;
                carry = z >> 16;
                Storeinc(xc, z, z2);
                z2 = (*x++ >> 16) * y + (*xc & 0xffff) + carry;
                carry = z2 >> 16;
            } while (x < xae);
            *xc = z2;
        }
    }
#else
    for (; xb < xbe; xc0++) {
        if (y = *xb++) {
            x = xa;
            xc = xc0;
            carry = 0;
            do {
                z = *x++ * y + *xc + carry;
                carry = z >> 16;
                *xc++ = z & 0xffff;
            } while (x < xae);
            *xc = (ULong)carry;
        }
    }
#endif
#endif
    for (xc0 = c->x, xc = xc0 + wc; wc > 0 && !*--xc; --wc) ;
    c->wds = wc;
    return c;
}

static Bigint *p5s;

static Bigint *
pow5mult(Bigint *b, int k)
{
    Bigint *b1, *p5, *p51;
    int i;
    static int p05[3] = { 5, 25, 125 };

    if ((i = k & 3) != 0)
        b = multadd(b, p05[i-1], 0);

    if (!(k >>= 2))
        return b;
    if (!(p5 = p5s)) {
        /* first time */
#ifdef MULTIPLE_THREADS
        ACQUIRE_DTOA_LOCK(1);
        if (!(p5 = p5s)) {
            p5 = p5s = i2b(625);
            p5->next = 0;
        }
        FREE_DTOA_LOCK(1);
#else
        p5 = p5s = i2b(625);
        p5->next = 0;
#endif
    }
    for (;;) {
        if (k & 1) {
            b1 = mult(b, p5);
            Bfree(b);
            b = b1;
        }
        if (!(k >>= 1))
            break;
        if (!(p51 = p5->next)) {
#ifdef MULTIPLE_THREADS
            ACQUIRE_DTOA_LOCK(1);
            if (!(p51 = p5->next)) {
                p51 = p5->next = mult(p5,p5);
                p51->next = 0;
            }
            FREE_DTOA_LOCK(1);
#else
            p51 = p5->next = mult(p5,p5);
            p51->next = 0;
#endif
        }
        p5 = p51;
    }
    return b;
}

static Bigint *
lshift(Bigint *b, int k)
{
    int i, k1, n, n1;
    Bigint *b1;
    ULong *x, *x1, *xe, z;

#ifdef Pack_32
    n = k >> 5;
#else
    n = k >> 4;
#endif
    k1 = b->k;
    n1 = n + b->wds + 1;
    for (i = b->maxwds; n1 > i; i <<= 1)
        k1++;
    b1 = Balloc(k1);
    x1 = b1->x;
    for (i = 0; i < n; i++)
        *x1++ = 0;
    x = b->x;
    xe = x + b->wds;
#ifdef Pack_32
    if (k &= 0x1f) {
        k1 = 32 - k;
        z = 0;
        do {
            *x1++ = *x << k | z;
            z = *x++ >> k1;
        } while (x < xe);
        if ((*x1 = z) != 0)
            ++n1;
    }
#else
    if (k &= 0xf) {
        k1 = 16 - k;
        z = 0;
        do {
            *x1++ = *x << k  & 0xffff | z;
            z = *x++ >> k1;
        } while (x < xe);
        if (*x1 = z)
            ++n1;
    }
#endif
    else
        do {
            *x1++ = *x++;
        } while (x < xe);
    b1->wds = n1 - 1;
    Bfree(b);
    return b1;
}

static int
cmp(Bigint *a, Bigint *b)
{
    ULong *xa, *xa0, *xb, *xb0;
    int i, j;

    i = a->wds;
    j = b->wds;
#ifdef DEBUG
    if (i > 1 && !a->x[i-1])
        Bug("cmp called with a->x[a->wds-1] == 0");
    if (j > 1 && !b->x[j-1])
        Bug("cmp called with b->x[b->wds-1] == 0");
#endif
    if (i -= j)
        return i;
    xa0 = a->x;
    xa = xa0 + j;
    xb0 = b->x;
    xb = xb0 + j;
    for (;;) {
        if (*--xa != *--xb)
            return *xa < *xb ? -1 : 1;
        if (xa <= xa0)
            break;
    }
    return 0;
}

static Bigint *
diff(Bigint *a, Bigint *b)
{
    Bigint *c;
    int i, wa, wb;
    ULong *xa, *xae, *xb, *xbe, *xc;
#ifdef ULLong
    ULLong borrow, y;
#else
    ULong borrow, y;
#ifdef Pack_32
    ULong z;
#endif
#endif

    i = cmp(a,b);
    if (!i) {
        c = Balloc(0);
        c->wds = 1;
        c->x[0] = 0;
        return c;
    }
    if (i < 0) {
        c = a;
        a = b;
        b = c;
        i = 1;
    }
    else
        i = 0;
    c = Balloc(a->k);
    c->sign = i;
    wa = a->wds;
    xa = a->x;
    xae = xa + wa;
    wb = b->wds;
    xb = b->x;
    xbe = xb + wb;
    xc = c->x;
    borrow = 0;
#ifdef ULLong
    do {
        y = (ULLong)*xa++ - *xb++ - borrow;
        borrow = y >> 32 & (ULong)1;
        *xc++ = (ULong)(y & FFFFFFFF);
    } while (xb < xbe);
    while (xa < xae) {
        y = *xa++ - borrow;
        borrow = y >> 32 & (ULong)1;
        *xc++ = (ULong)(y & FFFFFFFF);
    }
#else
#ifdef Pack_32
    do {
        y = (*xa & 0xffff) - (*xb & 0xffff) - borrow;
        borrow = (y & 0x10000) >> 16;
        z = (*xa++ >> 16) - (*xb++ >> 16) - borrow;
        borrow = (z & 0x10000) >> 16;
        Storeinc(xc, z, y);
    } while (xb < xbe);
    while (xa < xae) {
        y = (*xa & 0xffff) - borrow;
        borrow = (y & 0x10000) >> 16;
        z = (*xa++ >> 16) - borrow;
        borrow = (z & 0x10000) >> 16;
        Storeinc(xc, z, y);
    }
#else
    do {
        y = *xa++ - *xb++ - borrow;
        borrow = (y & 0x10000) >> 16;
        *xc++ = y & 0xffff;
    } while (xb < xbe);
    while (xa < xae) {
        y = *xa++ - borrow;
        borrow = (y & 0x10000) >> 16;
        *xc++ = y & 0xffff;
    }
#endif
#endif
    while (!*--xc)
        wa--;
    c->wds = wa;
    return c;
}

static double
ulp(double x_)
{
    register Long L;
    double_u x, a;
    dval(x) = x_;

    L = (word0(x) & Exp_mask) - (P-1)*Exp_msk1;
#ifndef Avoid_Underflow
#ifndef Sudden_Underflow
    if (L > 0) {
#endif
#endif
#ifdef IBM
        L |= Exp_msk1 >> 4;
#endif
        word0(a) = L;
        word1(a) = 0;
#ifndef Avoid_Underflow
#ifndef Sudden_Underflow
    }
    else {
        L = -L >> Exp_shift;
        if (L < Exp_shift) {
            word0(a) = 0x80000 >> L;
            word1(a) = 0;
        }
        else {
            word0(a) = 0;
            L -= Exp_shift;
            word1(a) = L >= 31 ? 1 : 1 << 31 - L;
        }
    }
#endif
#endif
    return dval(a);
}

static double
b2d(Bigint *a, int *e)
{
    ULong *xa, *xa0, w, y, z;
    int k;
    double_u d;
#ifdef VAX
    ULong d0, d1;
#else
#define d0 word0(d)
#define d1 word1(d)
#endif

    xa0 = a->x;
    xa = xa0 + a->wds;
    y = *--xa;
#ifdef DEBUG
    if (!y) Bug("zero y in b2d");
#endif
    k = hi0bits(y);
    *e = 32 - k;
#ifdef Pack_32
    if (k < Ebits) {
        d0 = Exp_1 | y >> (Ebits - k);
        w = xa > xa0 ? *--xa : 0;
        d1 = y << ((32-Ebits) + k) | w >> (Ebits - k);
        goto ret_d;
    }
    z = xa > xa0 ? *--xa : 0;
    if (k -= Ebits) {
        d0 = Exp_1 | y << k | z >> (32 - k);
        y = xa > xa0 ? *--xa : 0;
        d1 = z << k | y >> (32 - k);
    }
    else {
        d0 = Exp_1 | y;
        d1 = z;
    }
#else
    if (k < Ebits + 16) {
        z = xa > xa0 ? *--xa : 0;
        d0 = Exp_1 | y << k - Ebits | z >> Ebits + 16 - k;
        w = xa > xa0 ? *--xa : 0;
        y = xa > xa0 ? *--xa : 0;
        d1 = z << k + 16 - Ebits | w << k - Ebits | y >> 16 + Ebits - k;
        goto ret_d;
    }
    z = xa > xa0 ? *--xa : 0;
    w = xa > xa0 ? *--xa : 0;
    k -= Ebits + 16;
    d0 = Exp_1 | y << k + 16 | z << k | w >> 16 - k;
    y = xa > xa0 ? *--xa : 0;
    d1 = w << k + 16 | y << k;
#endif
ret_d:
#ifdef VAX
    word0(d) = d0 >> 16 | d0 << 16;
    word1(d) = d1 >> 16 | d1 << 16;
#else
#undef d0
#undef d1
#endif
    return dval(d);
}

static Bigint *
d2b(double d_, int *e, int *bits)
{
    double_u d;
    Bigint *b;
    int de, k;
    ULong *x, y, z;
#ifndef Sudden_Underflow
    int i;
#endif
#ifdef VAX
    ULong d0, d1;
#endif
    dval(d) = d_;
#ifdef VAX
    d0 = word0(d) >> 16 | word0(d) << 16;
    d1 = word1(d) >> 16 | word1(d) << 16;
#else
#define d0 word0(d)
#define d1 word1(d)
#endif

#ifdef Pack_32
    b = Balloc(1);
#else
    b = Balloc(2);
#endif
    x = b->x;

    z = d0 & Frac_mask;
    d0 &= 0x7fffffff;   /* clear sign bit, which we ignore */
#ifdef Sudden_Underflow
    de = (int)(d0 >> Exp_shift);
#ifndef IBM
    z |= Exp_msk11;
#endif
#else
    if ((de = (int)(d0 >> Exp_shift)) != 0)
        z |= Exp_msk1;
#endif
#ifdef Pack_32
    if ((y = d1) != 0) {
        if ((k = lo0bits(&y)) != 0) {
            x[0] = y | z << (32 - k);
            z >>= k;
        }
        else
            x[0] = y;
#ifndef Sudden_Underflow
        i =
#endif
        b->wds = (x[1] = z) ? 2 : 1;
    }
    else {
#ifdef DEBUG
        if (!z)
            Bug("Zero passed to d2b");
#endif
        k = lo0bits(&z);
        x[0] = z;
#ifndef Sudden_Underflow
        i =
#endif
        b->wds = 1;
        k += 32;
    }
#else
    if (y = d1) {
        if (k = lo0bits(&y))
            if (k >= 16) {
                x[0] = y | z << 32 - k & 0xffff;
                x[1] = z >> k - 16 & 0xffff;
                x[2] = z >> k;
                i = 2;
            }
            else {
                x[0] = y & 0xffff;
                x[1] = y >> 16 | z << 16 - k & 0xffff;
                x[2] = z >> k & 0xffff;
                x[3] = z >> k+16;
                i = 3;
            }
        else {
            x[0] = y & 0xffff;
            x[1] = y >> 16;
            x[2] = z & 0xffff;
            x[3] = z >> 16;
            i = 3;
        }
    }
    else {
#ifdef DEBUG
        if (!z)
            Bug("Zero passed to d2b");
#endif
        k = lo0bits(&z);
        if (k >= 16) {
            x[0] = z;
            i = 0;
        }
        else {
            x[0] = z & 0xffff;
            x[1] = z >> 16;
            i = 1;
        }
        k += 32;
    }
    while (!x[i])
        --i;
    b->wds = i + 1;
#endif
#ifndef Sudden_Underflow
    if (de) {
#endif
#ifdef IBM
        *e = (de - Bias - (P-1) << 2) + k;
        *bits = 4*P + 8 - k - hi0bits(word0(d) & Frac_mask);
#else
        *e = de - Bias - (P-1) + k;
        *bits = P - k;
#endif
#ifndef Sudden_Underflow
    }
    else {
        *e = de - Bias - (P-1) + 1 + k;
#ifdef Pack_32
        *bits = 32*i - hi0bits(x[i-1]);
#else
        *bits = (i+2)*16 - hi0bits(x[i]);
#endif
    }
#endif
    return b;
}
#undef d0
#undef d1

static double
ratio(Bigint *a, Bigint *b)
{
    double_u da, db;
    int k, ka, kb;

    dval(da) = b2d(a, &ka);
    dval(db) = b2d(b, &kb);
#ifdef Pack_32
    k = ka - kb + 32*(a->wds - b->wds);
#else
    k = ka - kb + 16*(a->wds - b->wds);
#endif
#ifdef IBM
    if (k > 0) {
        word0(da) += (k >> 2)*Exp_msk1;
        if (k &= 3)
            dval(da) *= 1 << k;
    }
    else {
        k = -k;
        word0(db) += (k >> 2)*Exp_msk1;
        if (k &= 3)
            dval(db) *= 1 << k;
    }
#else
    if (k > 0)
        word0(da) += k*Exp_msk1;
    else {
        k = -k;
        word0(db) += k*Exp_msk1;
    }
#endif
    return dval(da) / dval(db);
}

static const double
tens[] = {
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9,
    1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
    1e20, 1e21, 1e22
#ifdef VAX
    , 1e23, 1e24
#endif
};

static const double
#ifdef IEEE_Arith
bigtens[] = { 1e16, 1e32, 1e64, 1e128, 1e256 };
static const double tinytens[] = { 1e-16, 1e-32, 1e-64, 1e-128,
#ifdef Avoid_Underflow
    9007199254740992.*9007199254740992.e-256
    /* = 2^106 * 1e-53 */
#else
    1e-256
#endif
};
/* The factor of 2^53 in tinytens[4] helps us avoid setting the underflow */
/* flag unnecessarily.  It leads to a song and dance at the end of strtod. */
#define Scale_Bit 0x10
#define n_bigtens 5
#else
#ifdef IBM
bigtens[] = { 1e16, 1e32, 1e64 };
static const double tinytens[] = { 1e-16, 1e-32, 1e-64 };
#define n_bigtens 3
#else
bigtens[] = { 1e16, 1e32 };
static const double tinytens[] = { 1e-16, 1e-32 };
#define n_bigtens 2
#endif
#endif

#ifndef IEEE_Arith
#undef INFNAN_CHECK
#endif

#ifdef INFNAN_CHECK

#ifndef NAN_WORD0
#define NAN_WORD0 0x7ff80000
#endif

#ifndef NAN_WORD1
#define NAN_WORD1 0
#endif

static int
match(const char **sp, char *t)
{
    int c, d;
    const char *s = *sp;

    while (d = *t++) {
        if ((c = *++s) >= 'A' && c <= 'Z')
            c += 'a' - 'A';
        if (c != d)
            return 0;
    }
    *sp = s + 1;
    return 1;
}

#ifndef No_Hex_NaN
static void
hexnan(double *rvp, const char **sp)
{
    ULong c, x[2];
    const char *s;
    int havedig, udx0, xshift;

    x[0] = x[1] = 0;
    havedig = xshift = 0;
    udx0 = 1;
    s = *sp;
    while (c = *(const unsigned char*)++s) {
        if (c >= '0' && c <= '9')
            c -= '0';
        else if (c >= 'a' && c <= 'f')
            c += 10 - 'a';
        else if (c >= 'A' && c <= 'F')
            c += 10 - 'A';
        else if (c <= ' ') {
            if (udx0 && havedig) {
                udx0 = 0;
                xshift = 1;
            }
            continue;
        }
        else if (/*(*/ c == ')' && havedig) {
            *sp = s + 1;
            break;
        }
        else
            return; /* invalid form: don't change *sp */
        havedig = 1;
        if (xshift) {
            xshift = 0;
            x[0] = x[1];
            x[1] = 0;
        }
        if (udx0)
            x[0] = (x[0] << 4) | (x[1] >> 28);
        x[1] = (x[1] << 4) | c;
    }
    if ((x[0] &= 0xfffff) || x[1]) {
        word0(*rvp) = Exp_mask | x[0];
        word1(*rvp) = x[1];
    }
}
#endif /*No_Hex_NaN*/
#endif /* INFNAN_CHECK */

double
ruby_strtod(const char *s00, char **se)
{
#ifdef Avoid_Underflow
    int scale;
#endif
    int bb2, bb5, bbe, bd2, bd5, bbbits, bs2, c, dsign,
         e, e1, esign, i, j, k, nd, nd0, nf, nz, nz0, sign;
    const char *s, *s0, *s1;
    double aadj, adj;
    double_u aadj1, rv, rv0;
    Long L;
    ULong y, z;
    Bigint *bb, *bb1, *bd, *bd0, *bs, *delta;
#ifdef SET_INEXACT
    int inexact, oldinexact;
#endif
#ifdef Honor_FLT_ROUNDS
    int rounding;
#endif
#ifdef USE_LOCALE
    const char *s2;
#endif

    errno = 0;
    sign = nz0 = nz = 0;
    dval(rv) = 0.;
    for (s = s00;;s++)
        switch (*s) {
          case '-':
            sign = 1;
            /* no break */
          case '+':
            if (*++s)
                goto break2;
            /* no break */
          case 0:
            goto ret0;
          case '\t':
          case '\n':
          case '\v':
          case '\f':
          case '\r':
          case ' ':
            continue;
          default:
            goto break2;
        }
break2:
    if (*s == '0') {
	if (s[1] == 'x' || s[1] == 'X') {
	    static const char hexdigit[] = "0123456789abcdef0123456789ABCDEF";
	    s0 = ++s;
	    adj = 0;
	    aadj = 1.0;
	    nd0 = -4;

	    if (!*++s || !(s1 = strchr(hexdigit, *s))) goto ret0;
	    if (*s == '0') {
		while (*++s == '0');
		s1 = strchr(hexdigit, *s);
	    }
	    if (s1 != NULL) {
		do {
		    adj += aadj * ((s1 - hexdigit) & 15);
		    nd0 += 4;
		    aadj /= 16;
		} while (*++s && (s1 = strchr(hexdigit, *s)));
	    }

	    if (*s == '.') {
		dsign = 1;
		if (!*++s || !(s1 = strchr(hexdigit, *s))) goto ret0;
		if (nd0 < 0) {
		    while (*s == '0') {
			s++;
			nd0 -= 4;
		    }
		}
		for (; *s && (s1 = strchr(hexdigit, *s)); ++s) {
		    adj += aadj * ((s1 - hexdigit) & 15);
		    if ((aadj /= 16) == 0.0) {
			while (strchr(hexdigit, *++s));
			break;
		    }
		}
	    }
	    else {
		dsign = 0;
	    }

	    if (*s == 'P' || *s == 'p') {
		dsign = 0x2C - *++s; /* +: 2B, -: 2D */
		if (abs(dsign) == 1) s++;
		else dsign = 1;

		nd = 0;
		c = *s;
		if (c < '0' || '9' < c) goto ret0;
		do {
		    nd *= 10;
		    nd += c;
		    nd -= '0';
		    c = *++s;
		    /* Float("0x0."+("0"*267)+"1fp2095") */
		    if (nd + dsign * nd0 > 2095) {
			while ('0' <= c && c <= '9') c = *++s;
			break;
		    }
		} while ('0' <= c && c <= '9');
		nd0 += nd * dsign;
	    }
	    else {
		if (dsign) goto ret0;
	    }
	    dval(rv) = ldexp(adj, nd0);
	    goto ret;
	}
        nz0 = 1;
        while (*++s == '0') ;
        if (!*s)
            goto ret;
    }
    s0 = s;
    y = z = 0;
    for (nd = nf = 0; (c = *s) >= '0' && c <= '9'; nd++, s++)
        if (nd < 9)
            y = 10*y + c - '0';
        else if (nd < 16)
            z = 10*z + c - '0';
    nd0 = nd;
#ifdef USE_LOCALE
    s1 = localeconv()->decimal_point;
    if (c == *s1) {
        c = '.';
        if (*++s1) {
            s2 = s;
            for (;;) {
                if (*++s2 != *s1) {
                    c = 0;
                    break;
                }
                if (!*++s1) {
                    s = s2;
                    break;
                }
            }
        }
    }
#endif
    if (c == '.') {
        if (!ISDIGIT(s[1]))
            goto dig_done;
        c = *++s;
        if (!nd) {
            for (; c == '0'; c = *++s)
                nz++;
            if (c > '0' && c <= '9') {
                s0 = s;
                nf += nz;
                nz = 0;
                goto have_dig;
            }
            goto dig_done;
        }
        for (; c >= '0' && c <= '9'; c = *++s) {
have_dig:
            nz++;
            if (nf > DBL_DIG * 4) continue;
            if (c -= '0') {
                nf += nz;
                for (i = 1; i < nz; i++)
                    if (nd++ < 9)
                        y *= 10;
                    else if (nd <= DBL_DIG + 1)
                        z *= 10;
                if (nd++ < 9)
                    y = 10*y + c;
                else if (nd <= DBL_DIG + 1)
                    z = 10*z + c;
                nz = 0;
            }
        }
    }
dig_done:
    e = 0;
    if (c == 'e' || c == 'E') {
        if (!nd && !nz && !nz0) {
            goto ret0;
        }
        s00 = s;
        esign = 0;
        switch (c = *++s) {
          case '-':
            esign = 1;
          case '+':
            c = *++s;
        }
        if (c >= '0' && c <= '9') {
            while (c == '0')
                c = *++s;
            if (c > '0' && c <= '9') {
                L = c - '0';
                s1 = s;
                while ((c = *++s) >= '0' && c <= '9')
                    L = 10*L + c - '0';
                if (s - s1 > 8 || L > 19999)
                    /* Avoid confusion from exponents
                     * so large that e might overflow.
                     */
                    e = 19999; /* safe for 16 bit ints */
                else
                    e = (int)L;
                if (esign)
                    e = -e;
            }
            else
                e = 0;
        }
        else
            s = s00;
    }
    if (!nd) {
        if (!nz && !nz0) {
#ifdef INFNAN_CHECK
            /* Check for Nan and Infinity */
            switch (c) {
              case 'i':
              case 'I':
                if (match(&s,"nf")) {
                    --s;
                    if (!match(&s,"inity"))
                        ++s;
                    word0(rv) = 0x7ff00000;
                    word1(rv) = 0;
                    goto ret;
                }
                break;
              case 'n':
              case 'N':
                if (match(&s, "an")) {
                    word0(rv) = NAN_WORD0;
                    word1(rv) = NAN_WORD1;
#ifndef No_Hex_NaN
                    if (*s == '(') /*)*/
                        hexnan(&rv, &s);
#endif
                    goto ret;
                }
            }
#endif /* INFNAN_CHECK */
ret0:
            s = s00;
            sign = 0;
        }
        goto ret;
    }
    e1 = e -= nf;

    /* Now we have nd0 digits, starting at s0, followed by a
     * decimal point, followed by nd-nd0 digits.  The number we're
     * after is the integer represented by those digits times
     * 10**e */

    if (!nd0)
        nd0 = nd;
    k = nd < DBL_DIG + 1 ? nd : DBL_DIG + 1;
    dval(rv) = y;
    if (k > 9) {
#ifdef SET_INEXACT
        if (k > DBL_DIG)
            oldinexact = get_inexact();
#endif
        dval(rv) = tens[k - 9] * dval(rv) + z;
    }
    bd0 = bb = bd = bs = delta = 0;
    if (nd <= DBL_DIG
#ifndef RND_PRODQUOT
#ifndef Honor_FLT_ROUNDS
        && Flt_Rounds == 1
#endif
#endif
    ) {
        if (!e)
            goto ret;
        if (e > 0) {
            if (e <= Ten_pmax) {
#ifdef VAX
                goto vax_ovfl_check;
#else
#ifdef Honor_FLT_ROUNDS
                /* round correctly FLT_ROUNDS = 2 or 3 */
                if (sign) {
                    dval(rv) = -dval(rv);
                    sign = 0;
                }
#endif
                /* rv = */ rounded_product(dval(rv), tens[e]);
                goto ret;
#endif
            }
            i = DBL_DIG - nd;
            if (e <= Ten_pmax + i) {
                /* A fancier test would sometimes let us do
                 * this for larger i values.
                 */
#ifdef Honor_FLT_ROUNDS
                /* round correctly FLT_ROUNDS = 2 or 3 */
                if (sign) {
                    dval(rv) = -dval(rv);
                    sign = 0;
                }
#endif
                e -= i;
                dval(rv) *= tens[i];
#ifdef VAX
                /* VAX exponent range is so narrow we must
                 * worry about overflow here...
                 */
vax_ovfl_check:
                word0(rv) -= P*Exp_msk1;
                /* rv = */ rounded_product(dval(rv), tens[e]);
                if ((word0(rv) & Exp_mask)
                        > Exp_msk1*(DBL_MAX_EXP+Bias-1-P))
                    goto ovfl;
                word0(rv) += P*Exp_msk1;
#else
                /* rv = */ rounded_product(dval(rv), tens[e]);
#endif
                goto ret;
            }
        }
#ifndef Inaccurate_Divide
        else if (e >= -Ten_pmax) {
#ifdef Honor_FLT_ROUNDS
            /* round correctly FLT_ROUNDS = 2 or 3 */
            if (sign) {
                dval(rv) = -dval(rv);
                sign = 0;
            }
#endif
            /* rv = */ rounded_quotient(dval(rv), tens[-e]);
            goto ret;
        }
#endif
    }
    e1 += nd - k;

#ifdef IEEE_Arith
#ifdef SET_INEXACT
    inexact = 1;
    if (k <= DBL_DIG)
        oldinexact = get_inexact();
#endif
#ifdef Avoid_Underflow
    scale = 0;
#endif
#ifdef Honor_FLT_ROUNDS
    if ((rounding = Flt_Rounds) >= 2) {
        if (sign)
            rounding = rounding == 2 ? 0 : 2;
        else
            if (rounding != 2)
                rounding = 0;
    }
#endif
#endif /*IEEE_Arith*/

    /* Get starting approximation = rv * 10**e1 */

    if (e1 > 0) {
        if ((i = e1 & 15) != 0)
            dval(rv) *= tens[i];
        if (e1 &= ~15) {
            if (e1 > DBL_MAX_10_EXP) {
ovfl:
#ifndef NO_ERRNO
                errno = ERANGE;
#endif
                /* Can't trust HUGE_VAL */
#ifdef IEEE_Arith
#ifdef Honor_FLT_ROUNDS
                switch (rounding) {
                  case 0: /* toward 0 */
                  case 3: /* toward -infinity */
                    word0(rv) = Big0;
                    word1(rv) = Big1;
                    break;
                  default:
                    word0(rv) = Exp_mask;
                    word1(rv) = 0;
                }
#else /*Honor_FLT_ROUNDS*/
                word0(rv) = Exp_mask;
                word1(rv) = 0;
#endif /*Honor_FLT_ROUNDS*/
#ifdef SET_INEXACT
                /* set overflow bit */
                dval(rv0) = 1e300;
                dval(rv0) *= dval(rv0);
#endif
#else /*IEEE_Arith*/
                word0(rv) = Big0;
                word1(rv) = Big1;
#endif /*IEEE_Arith*/
                if (bd0)
                    goto retfree;
                goto ret;
            }
            e1 >>= 4;
            for (j = 0; e1 > 1; j++, e1 >>= 1)
                if (e1 & 1)
                    dval(rv) *= bigtens[j];
            /* The last multiplication could overflow. */
            word0(rv) -= P*Exp_msk1;
            dval(rv) *= bigtens[j];
            if ((z = word0(rv) & Exp_mask)
                    > Exp_msk1*(DBL_MAX_EXP+Bias-P))
                goto ovfl;
            if (z > Exp_msk1*(DBL_MAX_EXP+Bias-1-P)) {
                /* set to largest number */
                /* (Can't trust DBL_MAX) */
                word0(rv) = Big0;
                word1(rv) = Big1;
            }
            else
                word0(rv) += P*Exp_msk1;
        }
    }
    else if (e1 < 0) {
        e1 = -e1;
        if ((i = e1 & 15) != 0)
            dval(rv) /= tens[i];
        if (e1 >>= 4) {
            if (e1 >= 1 << n_bigtens)
                goto undfl;
#ifdef Avoid_Underflow
            if (e1 & Scale_Bit)
                scale = 2*P;
            for (j = 0; e1 > 0; j++, e1 >>= 1)
                if (e1 & 1)
                    dval(rv) *= tinytens[j];
            if (scale && (j = 2*P + 1 - ((word0(rv) & Exp_mask)
                    >> Exp_shift)) > 0) {
                /* scaled rv is denormal; zap j low bits */
                if (j >= 32) {
                    word1(rv) = 0;
                    if (j >= 53)
                        word0(rv) = (P+2)*Exp_msk1;
                    else
                        word0(rv) &= 0xffffffff << (j-32);
                }
                else
                    word1(rv) &= 0xffffffff << j;
            }
#else
            for (j = 0; e1 > 1; j++, e1 >>= 1)
                if (e1 & 1)
                    dval(rv) *= tinytens[j];
            /* The last multiplication could underflow. */
            dval(rv0) = dval(rv);
            dval(rv) *= tinytens[j];
            if (!dval(rv)) {
                dval(rv) = 2.*dval(rv0);
                dval(rv) *= tinytens[j];
#endif
                if (!dval(rv)) {
undfl:
                    dval(rv) = 0.;
#ifndef NO_ERRNO
                    errno = ERANGE;
#endif
                    if (bd0)
                        goto retfree;
                    goto ret;
                }
#ifndef Avoid_Underflow
                word0(rv) = Tiny0;
                word1(rv) = Tiny1;
                /* The refinement below will clean
                 * this approximation up.
                 */
            }
#endif
        }
    }

    /* Now the hard part -- adjusting rv to the correct value.*/

    /* Put digits into bd: true value = bd * 10^e */

    bd0 = s2b(s0, nd0, nd, y);

    for (;;) {
        bd = Balloc(bd0->k);
        Bcopy(bd, bd0);
        bb = d2b(dval(rv), &bbe, &bbbits);  /* rv = bb * 2^bbe */
        bs = i2b(1);

        if (e >= 0) {
            bb2 = bb5 = 0;
            bd2 = bd5 = e;
        }
        else {
            bb2 = bb5 = -e;
            bd2 = bd5 = 0;
        }
        if (bbe >= 0)
            bb2 += bbe;
        else
            bd2 -= bbe;
        bs2 = bb2;
#ifdef Honor_FLT_ROUNDS
        if (rounding != 1)
            bs2++;
#endif
#ifdef Avoid_Underflow
        j = bbe - scale;
        i = j + bbbits - 1; /* logb(rv) */
        if (i < Emin)   /* denormal */
            j += P - Emin;
        else
            j = P + 1 - bbbits;
#else /*Avoid_Underflow*/
#ifdef Sudden_Underflow
#ifdef IBM
        j = 1 + 4*P - 3 - bbbits + ((bbe + bbbits - 1) & 3);
#else
        j = P + 1 - bbbits;
#endif
#else /*Sudden_Underflow*/
        j = bbe;
        i = j + bbbits - 1; /* logb(rv) */
        if (i < Emin)   /* denormal */
            j += P - Emin;
        else
            j = P + 1 - bbbits;
#endif /*Sudden_Underflow*/
#endif /*Avoid_Underflow*/
        bb2 += j;
        bd2 += j;
#ifdef Avoid_Underflow
        bd2 += scale;
#endif
        i = bb2 < bd2 ? bb2 : bd2;
        if (i > bs2)
            i = bs2;
        if (i > 0) {
            bb2 -= i;
            bd2 -= i;
            bs2 -= i;
        }
        if (bb5 > 0) {
            bs = pow5mult(bs, bb5);
            bb1 = mult(bs, bb);
            Bfree(bb);
            bb = bb1;
        }
        if (bb2 > 0)
            bb = lshift(bb, bb2);
        if (bd5 > 0)
            bd = pow5mult(bd, bd5);
        if (bd2 > 0)
            bd = lshift(bd, bd2);
        if (bs2 > 0)
            bs = lshift(bs, bs2);
        delta = diff(bb, bd);
        dsign = delta->sign;
        delta->sign = 0;
        i = cmp(delta, bs);
#ifdef Honor_FLT_ROUNDS
        if (rounding != 1) {
            if (i < 0) {
                /* Error is less than an ulp */
                if (!delta->x[0] && delta->wds <= 1) {
                    /* exact */
#ifdef SET_INEXACT
                    inexact = 0;
#endif
                    break;
                }
                if (rounding) {
                    if (dsign) {
                        adj = 1.;
                        goto apply_adj;
                    }
                }
                else if (!dsign) {
                    adj = -1.;
                    if (!word1(rv)
                     && !(word0(rv) & Frac_mask)) {
                        y = word0(rv) & Exp_mask;
#ifdef Avoid_Underflow
                        if (!scale || y > 2*P*Exp_msk1)
#else
                        if (y)
#endif
                        {
                            delta = lshift(delta,Log2P);
                            if (cmp(delta, bs) <= 0)
                                adj = -0.5;
                        }
                    }
apply_adj:
#ifdef Avoid_Underflow
                    if (scale && (y = word0(rv) & Exp_mask)
                            <= 2*P*Exp_msk1)
                        word0(adj) += (2*P+1)*Exp_msk1 - y;
#else
#ifdef Sudden_Underflow
                    if ((word0(rv) & Exp_mask) <=
                            P*Exp_msk1) {
                        word0(rv) += P*Exp_msk1;
                        dval(rv) += adj*ulp(dval(rv));
                        word0(rv) -= P*Exp_msk1;
                    }
                    else
#endif /*Sudden_Underflow*/
#endif /*Avoid_Underflow*/
                    dval(rv) += adj*ulp(dval(rv));
                }
                break;
            }
            adj = ratio(delta, bs);
            if (adj < 1.)
                adj = 1.;
            if (adj <= 0x7ffffffe) {
                /* adj = rounding ? ceil(adj) : floor(adj); */
                y = adj;
                if (y != adj) {
                    if (!((rounding>>1) ^ dsign))
                        y++;
                    adj = y;
                }
            }
#ifdef Avoid_Underflow
            if (scale && (y = word0(rv) & Exp_mask) <= 2*P*Exp_msk1)
                word0(adj) += (2*P+1)*Exp_msk1 - y;
#else
#ifdef Sudden_Underflow
            if ((word0(rv) & Exp_mask) <= P*Exp_msk1) {
                word0(rv) += P*Exp_msk1;
                adj *= ulp(dval(rv));
                if (dsign)
                    dval(rv) += adj;
                else
                    dval(rv) -= adj;
                word0(rv) -= P*Exp_msk1;
                goto cont;
            }
#endif /*Sudden_Underflow*/
#endif /*Avoid_Underflow*/
            adj *= ulp(dval(rv));
            if (dsign)
                dval(rv) += adj;
            else
                dval(rv) -= adj;
            goto cont;
        }
#endif /*Honor_FLT_ROUNDS*/

        if (i < 0) {
            /* Error is less than half an ulp -- check for
             * special case of mantissa a power of two.
             */
            if (dsign || word1(rv) || word0(rv) & Bndry_mask
#ifdef IEEE_Arith
#ifdef Avoid_Underflow
                || (word0(rv) & Exp_mask) <= (2*P+1)*Exp_msk1
#else
                || (word0(rv) & Exp_mask) <= Exp_msk1
#endif
#endif
            ) {
#ifdef SET_INEXACT
                if (!delta->x[0] && delta->wds <= 1)
                    inexact = 0;
#endif
                break;
            }
            if (!delta->x[0] && delta->wds <= 1) {
                /* exact result */
#ifdef SET_INEXACT
                inexact = 0;
#endif
                break;
            }
            delta = lshift(delta,Log2P);
            if (cmp(delta, bs) > 0)
                goto drop_down;
            break;
        }
        if (i == 0) {
            /* exactly half-way between */
            if (dsign) {
                if ((word0(rv) & Bndry_mask1) == Bndry_mask1
                        &&  word1(rv) == (
#ifdef Avoid_Underflow
                        (scale && (y = word0(rv) & Exp_mask) <= 2*P*Exp_msk1)
                        ? (0xffffffff & (0xffffffff << (2*P+1-(y>>Exp_shift)))) :
#endif
                        0xffffffff)) {
                    /*boundary case -- increment exponent*/
                    word0(rv) = (word0(rv) & Exp_mask)
                                + Exp_msk1
#ifdef IBM
                                | Exp_msk1 >> 4
#endif
                    ;
                    word1(rv) = 0;
#ifdef Avoid_Underflow
                    dsign = 0;
#endif
                    break;
                }
            }
            else if (!(word0(rv) & Bndry_mask) && !word1(rv)) {
drop_down:
                /* boundary case -- decrement exponent */
#ifdef Sudden_Underflow /*{{*/
                L = word0(rv) & Exp_mask;
#ifdef IBM
                if (L <  Exp_msk1)
#else
#ifdef Avoid_Underflow
                if (L <= (scale ? (2*P+1)*Exp_msk1 : Exp_msk1))
#else
                if (L <= Exp_msk1)
#endif /*Avoid_Underflow*/
#endif /*IBM*/
                    goto undfl;
                L -= Exp_msk1;
#else /*Sudden_Underflow}{*/
#ifdef Avoid_Underflow
                if (scale) {
                    L = word0(rv) & Exp_mask;
                    if (L <= (2*P+1)*Exp_msk1) {
                        if (L > (P+2)*Exp_msk1)
                            /* round even ==> */
                            /* accept rv */
                            break;
                        /* rv = smallest denormal */
                        goto undfl;
                    }
                }
#endif /*Avoid_Underflow*/
                L = (word0(rv) & Exp_mask) - Exp_msk1;
#endif /*Sudden_Underflow}}*/
                word0(rv) = L | Bndry_mask1;
                word1(rv) = 0xffffffff;
#ifdef IBM
                goto cont;
#else
                break;
#endif
            }
#ifndef ROUND_BIASED
            if (!(word1(rv) & LSB))
                break;
#endif
            if (dsign)
                dval(rv) += ulp(dval(rv));
#ifndef ROUND_BIASED
            else {
                dval(rv) -= ulp(dval(rv));
#ifndef Sudden_Underflow
                if (!dval(rv))
                    goto undfl;
#endif
            }
#ifdef Avoid_Underflow
            dsign = 1 - dsign;
#endif
#endif
            break;
        }
        if ((aadj = ratio(delta, bs)) <= 2.) {
            if (dsign)
                aadj = dval(aadj1) = 1.;
            else if (word1(rv) || word0(rv) & Bndry_mask) {
#ifndef Sudden_Underflow
                if (word1(rv) == Tiny1 && !word0(rv))
                    goto undfl;
#endif
                aadj = 1.;
                dval(aadj1) = -1.;
            }
            else {
                /* special case -- power of FLT_RADIX to be */
                /* rounded down... */

                if (aadj < 2./FLT_RADIX)
                    aadj = 1./FLT_RADIX;
                else
                    aadj *= 0.5;
                dval(aadj1) = -aadj;
            }
        }
        else {
            aadj *= 0.5;
            dval(aadj1) = dsign ? aadj : -aadj;
#ifdef Check_FLT_ROUNDS
            switch (Rounding) {
              case 2: /* towards +infinity */
                dval(aadj1) -= 0.5;
                break;
              case 0: /* towards 0 */
              case 3: /* towards -infinity */
                dval(aadj1) += 0.5;
            }
#else
            if (Flt_Rounds == 0)
                dval(aadj1) += 0.5;
#endif /*Check_FLT_ROUNDS*/
        }
        y = word0(rv) & Exp_mask;

        /* Check for overflow */

        if (y == Exp_msk1*(DBL_MAX_EXP+Bias-1)) {
            dval(rv0) = dval(rv);
            word0(rv) -= P*Exp_msk1;
            adj = dval(aadj1) * ulp(dval(rv));
            dval(rv) += adj;
            if ((word0(rv) & Exp_mask) >=
                    Exp_msk1*(DBL_MAX_EXP+Bias-P)) {
                if (word0(rv0) == Big0 && word1(rv0) == Big1)
                    goto ovfl;
                word0(rv) = Big0;
                word1(rv) = Big1;
                goto cont;
            }
            else
                word0(rv) += P*Exp_msk1;
        }
        else {
#ifdef Avoid_Underflow
            if (scale && y <= 2*P*Exp_msk1) {
                if (aadj <= 0x7fffffff) {
                    if ((z = (int)aadj) <= 0)
                        z = 1;
                    aadj = z;
                    dval(aadj1) = dsign ? aadj : -aadj;
                }
                word0(aadj1) += (2*P+1)*Exp_msk1 - y;
            }
            adj = dval(aadj1) * ulp(dval(rv));
            dval(rv) += adj;
#else
#ifdef Sudden_Underflow
            if ((word0(rv) & Exp_mask) <= P*Exp_msk1) {
                dval(rv0) = dval(rv);
                word0(rv) += P*Exp_msk1;
                adj = dval(aadj1) * ulp(dval(rv));
                dval(rv) += adj;
#ifdef IBM
                if ((word0(rv) & Exp_mask) <  P*Exp_msk1)
#else
                if ((word0(rv) & Exp_mask) <= P*Exp_msk1)
#endif
                {
                    if (word0(rv0) == Tiny0 && word1(rv0) == Tiny1)
                        goto undfl;
                    word0(rv) = Tiny0;
                    word1(rv) = Tiny1;
                    goto cont;
                }
                else
                    word0(rv) -= P*Exp_msk1;
            }
            else {
                adj = dval(aadj1) * ulp(dval(rv));
                dval(rv) += adj;
            }
#else /*Sudden_Underflow*/
            /* Compute adj so that the IEEE rounding rules will
             * correctly round rv + adj in some half-way cases.
             * If rv * ulp(rv) is denormalized (i.e.,
             * y <= (P-1)*Exp_msk1), we must adjust aadj to avoid
             * trouble from bits lost to denormalization;
             * example: 1.2e-307 .
             */
            if (y <= (P-1)*Exp_msk1 && aadj > 1.) {
                dval(aadj1) = (double)(int)(aadj + 0.5);
                if (!dsign)
                    dval(aadj1) = -dval(aadj1);
            }
            adj = dval(aadj1) * ulp(dval(rv));
            dval(rv) += adj;
#endif /*Sudden_Underflow*/
#endif /*Avoid_Underflow*/
        }
        z = word0(rv) & Exp_mask;
#ifndef SET_INEXACT
#ifdef Avoid_Underflow
        if (!scale)
#endif
        if (y == z) {
            /* Can we stop now? */
            L = (Long)aadj;
            aadj -= L;
            /* The tolerances below are conservative. */
            if (dsign || word1(rv) || word0(rv) & Bndry_mask) {
                if (aadj < .4999999 || aadj > .5000001)
                    break;
            }
            else if (aadj < .4999999/FLT_RADIX)
                break;
        }
#endif
cont:
        Bfree(bb);
        Bfree(bd);
        Bfree(bs);
        Bfree(delta);
    }
#ifdef SET_INEXACT
    if (inexact) {
        if (!oldinexact) {
            word0(rv0) = Exp_1 + (70 << Exp_shift);
            word1(rv0) = 0;
            dval(rv0) += 1.;
        }
    }
    else if (!oldinexact)
        clear_inexact();
#endif
#ifdef Avoid_Underflow
    if (scale) {
        word0(rv0) = Exp_1 - 2*P*Exp_msk1;
        word1(rv0) = 0;
        dval(rv) *= dval(rv0);
#ifndef NO_ERRNO
        /* try to avoid the bug of testing an 8087 register value */
        if (word0(rv) == 0 && word1(rv) == 0)
            errno = ERANGE;
#endif
    }
#endif /* Avoid_Underflow */
#ifdef SET_INEXACT
    if (inexact && !(word0(rv) & Exp_mask)) {
        /* set underflow bit */
        dval(rv0) = 1e-300;
        dval(rv0) *= dval(rv0);
    }
#endif
retfree:
    Bfree(bb);
    Bfree(bd);
    Bfree(bs);
    Bfree(bd0);
    Bfree(delta);
ret:
    if (se)
        *se = (char *)s;
    return sign ? -dval(rv) : dval(rv);
}

static int
quorem(Bigint *b, Bigint *S)
{
    int n;
    ULong *bx, *bxe, q, *sx, *sxe;
#ifdef ULLong
    ULLong borrow, carry, y, ys;
#else
    ULong borrow, carry, y, ys;
#ifdef Pack_32
    ULong si, z, zs;
#endif
#endif

    n = S->wds;
#ifdef DEBUG
    /*debug*/ if (b->wds > n)
    /*debug*/   Bug("oversize b in quorem");
#endif
    if (b->wds < n)
        return 0;
    sx = S->x;
    sxe = sx + --n;
    bx = b->x;
    bxe = bx + n;
    q = *bxe / (*sxe + 1);  /* ensure q <= true quotient */
#ifdef DEBUG
    /*debug*/ if (q > 9)
    /*debug*/   Bug("oversized quotient in quorem");
#endif
    if (q) {
        borrow = 0;
        carry = 0;
        do {
#ifdef ULLong
            ys = *sx++ * (ULLong)q + carry;
            carry = ys >> 32;
            y = *bx - (ys & FFFFFFFF) - borrow;
            borrow = y >> 32 & (ULong)1;
            *bx++ = (ULong)(y & FFFFFFFF);
#else
#ifdef Pack_32
            si = *sx++;
            ys = (si & 0xffff) * q + carry;
            zs = (si >> 16) * q + (ys >> 16);
            carry = zs >> 16;
            y = (*bx & 0xffff) - (ys & 0xffff) - borrow;
            borrow = (y & 0x10000) >> 16;
            z = (*bx >> 16) - (zs & 0xffff) - borrow;
            borrow = (z & 0x10000) >> 16;
            Storeinc(bx, z, y);
#else
            ys = *sx++ * q + carry;
            carry = ys >> 16;
            y = *bx - (ys & 0xffff) - borrow;
            borrow = (y & 0x10000) >> 16;
            *bx++ = y & 0xffff;
#endif
#endif
        } while (sx <= sxe);
        if (!*bxe) {
            bx = b->x;
            while (--bxe > bx && !*bxe)
                --n;
            b->wds = n;
        }
    }
    if (cmp(b, S) >= 0) {
        q++;
        borrow = 0;
        carry = 0;
        bx = b->x;
        sx = S->x;
        do {
#ifdef ULLong
            ys = *sx++ + carry;
            carry = ys >> 32;
            y = *bx - (ys & FFFFFFFF) - borrow;
            borrow = y >> 32 & (ULong)1;
            *bx++ = (ULong)(y & FFFFFFFF);
#else
#ifdef Pack_32
            si = *sx++;
            ys = (si & 0xffff) + carry;
            zs = (si >> 16) + (ys >> 16);
            carry = zs >> 16;
            y = (*bx & 0xffff) - (ys & 0xffff) - borrow;
            borrow = (y & 0x10000) >> 16;
            z = (*bx >> 16) - (zs & 0xffff) - borrow;
            borrow = (z & 0x10000) >> 16;
            Storeinc(bx, z, y);
#else
            ys = *sx++ + carry;
            carry = ys >> 16;
            y = *bx - (ys & 0xffff) - borrow;
            borrow = (y & 0x10000) >> 16;
            *bx++ = y & 0xffff;
#endif
#endif
        } while (sx <= sxe);
        bx = b->x;
        bxe = bx + n;
        if (!*bxe) {
            while (--bxe > bx && !*bxe)
                --n;
            b->wds = n;
        }
    }
    return q;
}

#ifndef MULTIPLE_THREADS
static char *dtoa_result;
#endif

#ifndef MULTIPLE_THREADS
static char *
rv_alloc(int i)
{
    return dtoa_result = xmalloc(i);
}
#else
#define rv_alloc(i) xmalloc(i)
#endif

static char *
nrv_alloc(const char *s, char **rve, size_t n)
{
    char *rv, *t;

    t = rv = rv_alloc(n);
    while ((*t = *s++) != 0) t++;
    if (rve)
        *rve = t;
    return rv;
}

#define rv_strdup(s, rve) nrv_alloc((s), (rve), strlen(s)+1)

#ifndef MULTIPLE_THREADS
/* freedtoa(s) must be used to free values s returned by dtoa
 * when MULTIPLE_THREADS is #defined.  It should be used in all cases,
 * but for consistency with earlier versions of dtoa, it is optional
 * when MULTIPLE_THREADS is not defined.
 */

static void
freedtoa(char *s)
{
    xfree(s);
}
#endif

static const char INFSTR[] = "Infinity";
static const char NANSTR[] = "NaN";
static const char ZEROSTR[] = "0";

/* dtoa for IEEE arithmetic (dmg): convert double to ASCII string.
 *
 * Inspired by "How to Print Floating-Point Numbers Accurately" by
 * Guy L. Steele, Jr. and Jon L. White [Proc. ACM SIGPLAN '90, pp. 112-126].
 *
 * Modifications:
 *  1. Rather than iterating, we use a simple numeric overestimate
 *     to determine k = floor(log10(d)).  We scale relevant
 *     quantities using O(log2(k)) rather than O(k) multiplications.
 *  2. For some modes > 2 (corresponding to ecvt and fcvt), we don't
 *     try to generate digits strictly left to right.  Instead, we
 *     compute with fewer bits and propagate the carry if necessary
 *     when rounding the final digit up.  This is often faster.
 *  3. Under the assumption that input will be rounded nearest,
 *     mode 0 renders 1e23 as 1e23 rather than 9.999999999999999e22.
 *     That is, we allow equality in stopping tests when the
 *     round-nearest rule will give the same floating-point value
 *     as would satisfaction of the stopping test with strict
 *     inequality.
 *  4. We remove common factors of powers of 2 from relevant
 *     quantities.
 *  5. When converting floating-point integers less than 1e16,
 *     we use floating-point arithmetic rather than resorting
 *     to multiple-precision integers.
 *  6. When asked to produce fewer than 15 digits, we first try
 *     to get by with floating-point arithmetic; we resort to
 *     multiple-precision integer arithmetic only if we cannot
 *     guarantee that the floating-point calculation has given
 *     the correctly rounded result.  For k requested digits and
 *     "uniformly" distributed input, the probability is
 *     something like 10^(k-15) that we must resort to the Long
 *     calculation.
 */

char *
ruby_dtoa(double d_, int mode, int ndigits, int *decpt, int *sign, char **rve)
{
 /* Arguments ndigits, decpt, sign are similar to those
    of ecvt and fcvt; trailing zeros are suppressed from
    the returned string.  If not null, *rve is set to point
    to the end of the return value.  If d is +-Infinity or NaN,
    then *decpt is set to 9999.

    mode:
        0 ==> shortest string that yields d when read in
            and rounded to nearest.
        1 ==> like 0, but with Steele & White stopping rule;
            e.g. with IEEE P754 arithmetic , mode 0 gives
            1e23 whereas mode 1 gives 9.999999999999999e22.
        2 ==> max(1,ndigits) significant digits.  This gives a
            return value similar to that of ecvt, except
            that trailing zeros are suppressed.
        3 ==> through ndigits past the decimal point.  This
            gives a return value similar to that from fcvt,
            except that trailing zeros are suppressed, and
            ndigits can be negative.
        4,5 ==> similar to 2 and 3, respectively, but (in
            round-nearest mode) with the tests of mode 0 to
            possibly return a shorter string that rounds to d.
            With IEEE arithmetic and compilation with
            -DHonor_FLT_ROUNDS, modes 4 and 5 behave the same
            as modes 2 and 3 when FLT_ROUNDS != 1.
        6-9 ==> Debugging modes similar to mode - 4:  don't try
            fast floating-point estimate (if applicable).

        Values of mode other than 0-9 are treated as mode 0.

        Sufficient space is allocated to the return value
        to hold the suppressed trailing zeros.
    */

    int bbits, b2, b5, be, dig, i, ieps, ilim, ilim0, ilim1,
        j, j1, k, k0, k_check, leftright, m2, m5, s2, s5,
        spec_case, try_quick;
    Long L;
#ifndef Sudden_Underflow
    int denorm;
    ULong x;
#endif
    Bigint *b, *b1, *delta, *mlo = 0, *mhi = 0, *S;
    double ds;
    double_u d, d2, eps;
    char *s, *s0;
#ifdef Honor_FLT_ROUNDS
    int rounding;
#endif
#ifdef SET_INEXACT
    int inexact, oldinexact;
#endif

    dval(d) = d_;

#ifndef MULTIPLE_THREADS
    if (dtoa_result) {
        freedtoa(dtoa_result);
        dtoa_result = 0;
    }
#endif

    if (word0(d) & Sign_bit) {
        /* set sign for everything, including 0's and NaNs */
        *sign = 1;
        word0(d) &= ~Sign_bit;  /* clear sign bit */
    }
    else
        *sign = 0;

#if defined(IEEE_Arith) + defined(VAX)
#ifdef IEEE_Arith
    if ((word0(d) & Exp_mask) == Exp_mask)
#else
    if (word0(d)  == 0x8000)
#endif
    {
        /* Infinity or NaN */
        *decpt = 9999;
#ifdef IEEE_Arith
        if (!word1(d) && !(word0(d) & 0xfffff))
            return rv_strdup(INFSTR, rve);
#endif
        return rv_strdup(NANSTR, rve);
    }
#endif
#ifdef IBM
    dval(d) += 0; /* normalize */
#endif
    if (!dval(d)) {
        *decpt = 1;
        return rv_strdup(ZEROSTR, rve);
    }

#ifdef SET_INEXACT
    try_quick = oldinexact = get_inexact();
    inexact = 1;
#endif
#ifdef Honor_FLT_ROUNDS
    if ((rounding = Flt_Rounds) >= 2) {
        if (*sign)
            rounding = rounding == 2 ? 0 : 2;
        else
            if (rounding != 2)
                rounding = 0;
    }
#endif

    b = d2b(dval(d), &be, &bbits);
#ifdef Sudden_Underflow
    i = (int)(word0(d) >> Exp_shift1 & (Exp_mask>>Exp_shift1));
#else
    if ((i = (int)(word0(d) >> Exp_shift1 & (Exp_mask>>Exp_shift1))) != 0) {
#endif
        dval(d2) = dval(d);
        word0(d2) &= Frac_mask1;
        word0(d2) |= Exp_11;
#ifdef IBM
        if (j = 11 - hi0bits(word0(d2) & Frac_mask))
            dval(d2) /= 1 << j;
#endif

        /* log(x)   ~=~ log(1.5) + (x-1.5)/1.5
         * log10(x)  =  log(x) / log(10)
         *      ~=~ log(1.5)/log(10) + (x-1.5)/(1.5*log(10))
         * log10(d) = (i-Bias)*log(2)/log(10) + log10(d2)
         *
         * This suggests computing an approximation k to log10(d) by
         *
         * k = (i - Bias)*0.301029995663981
         *  + ( (d2-1.5)*0.289529654602168 + 0.176091259055681 );
         *
         * We want k to be too large rather than too small.
         * The error in the first-order Taylor series approximation
         * is in our favor, so we just round up the constant enough
         * to compensate for any error in the multiplication of
         * (i - Bias) by 0.301029995663981; since |i - Bias| <= 1077,
         * and 1077 * 0.30103 * 2^-52 ~=~ 7.2e-14,
         * adding 1e-13 to the constant term more than suffices.
         * Hence we adjust the constant term to 0.1760912590558.
         * (We could get a more accurate k by invoking log10,
         *  but this is probably not worthwhile.)
         */

        i -= Bias;
#ifdef IBM
        i <<= 2;
        i += j;
#endif
#ifndef Sudden_Underflow
        denorm = 0;
    }
    else {
        /* d is denormalized */

        i = bbits + be + (Bias + (P-1) - 1);
        x = i > 32  ? word0(d) << (64 - i) | word1(d) >> (i - 32)
	    : word1(d) << (32 - i);
        dval(d2) = x;
        word0(d2) -= 31*Exp_msk1; /* adjust exponent */
        i -= (Bias + (P-1) - 1) + 1;
        denorm = 1;
    }
#endif
    ds = (dval(d2)-1.5)*0.289529654602168 + 0.1760912590558 + i*0.301029995663981;
    k = (int)ds;
    if (ds < 0. && ds != k)
        k--;    /* want k = floor(ds) */
    k_check = 1;
    if (k >= 0 && k <= Ten_pmax) {
        if (dval(d) < tens[k])
            k--;
        k_check = 0;
    }
    j = bbits - i - 1;
    if (j >= 0) {
        b2 = 0;
        s2 = j;
    }
    else {
        b2 = -j;
        s2 = 0;
    }
    if (k >= 0) {
        b5 = 0;
        s5 = k;
        s2 += k;
    }
    else {
        b2 -= k;
        b5 = -k;
        s5 = 0;
    }
    if (mode < 0 || mode > 9)
        mode = 0;

#ifndef SET_INEXACT
#ifdef Check_FLT_ROUNDS
    try_quick = Rounding == 1;
#else
    try_quick = 1;
#endif
#endif /*SET_INEXACT*/

    if (mode > 5) {
        mode -= 4;
        try_quick = 0;
    }
    leftright = 1;
    ilim = ilim1 = -1;
    switch (mode) {
      case 0:
      case 1:
        i = 18;
        ndigits = 0;
        break;
      case 2:
        leftright = 0;
        /* no break */
      case 4:
        if (ndigits <= 0)
            ndigits = 1;
        ilim = ilim1 = i = ndigits;
        break;
      case 3:
        leftright = 0;
        /* no break */
      case 5:
        i = ndigits + k + 1;
        ilim = i;
        ilim1 = i - 1;
        if (i <= 0)
            i = 1;
    }
    s = s0 = rv_alloc(i+1);

#ifdef Honor_FLT_ROUNDS
    if (mode > 1 && rounding != 1)
        leftright = 0;
#endif

    if (ilim >= 0 && ilim <= Quick_max && try_quick) {

        /* Try to get by with floating-point arithmetic. */

        i = 0;
        dval(d2) = dval(d);
        k0 = k;
        ilim0 = ilim;
        ieps = 2; /* conservative */
        if (k > 0) {
            ds = tens[k&0xf];
            j = k >> 4;
            if (j & Bletch) {
                /* prevent overflows */
                j &= Bletch - 1;
                dval(d) /= bigtens[n_bigtens-1];
                ieps++;
            }
            for (; j; j >>= 1, i++)
                if (j & 1) {
                    ieps++;
                    ds *= bigtens[i];
                }
            dval(d) /= ds;
        }
        else if ((j1 = -k) != 0) {
            dval(d) *= tens[j1 & 0xf];
            for (j = j1 >> 4; j; j >>= 1, i++)
                if (j & 1) {
                    ieps++;
                    dval(d) *= bigtens[i];
                }
        }
        if (k_check && dval(d) < 1. && ilim > 0) {
            if (ilim1 <= 0)
                goto fast_failed;
            ilim = ilim1;
            k--;
            dval(d) *= 10.;
            ieps++;
        }
        dval(eps) = ieps*dval(d) + 7.;
        word0(eps) -= (P-1)*Exp_msk1;
        if (ilim == 0) {
            S = mhi = 0;
            dval(d) -= 5.;
            if (dval(d) > dval(eps))
                goto one_digit;
            if (dval(d) < -dval(eps))
                goto no_digits;
            goto fast_failed;
        }
#ifndef No_leftright
        if (leftright) {
            /* Use Steele & White method of only
             * generating digits needed.
             */
            dval(eps) = 0.5/tens[ilim-1] - dval(eps);
            for (i = 0;;) {
                L = (int)dval(d);
                dval(d) -= L;
                *s++ = '0' + (int)L;
                if (dval(d) < dval(eps))
                    goto ret1;
                if (1. - dval(d) < dval(eps))
                    goto bump_up;
                if (++i >= ilim)
                    break;
                dval(eps) *= 10.;
                dval(d) *= 10.;
            }
        }
        else {
#endif
            /* Generate ilim digits, then fix them up. */
            dval(eps) *= tens[ilim-1];
            for (i = 1;; i++, dval(d) *= 10.) {
                L = (Long)(dval(d));
                if (!(dval(d) -= L))
                    ilim = i;
                *s++ = '0' + (int)L;
                if (i == ilim) {
                    if (dval(d) > 0.5 + dval(eps))
                        goto bump_up;
                    else if (dval(d) < 0.5 - dval(eps)) {
                        while (*--s == '0') ;
                        s++;
                        goto ret1;
                    }
                    break;
                }
            }
#ifndef No_leftright
        }
#endif
fast_failed:
        s = s0;
        dval(d) = dval(d2);
        k = k0;
        ilim = ilim0;
    }

    /* Do we have a "small" integer? */

    if (be >= 0 && k <= Int_max) {
        /* Yes. */
        ds = tens[k];
        if (ndigits < 0 && ilim <= 0) {
            S = mhi = 0;
            if (ilim < 0 || dval(d) <= 5*ds)
                goto no_digits;
            goto one_digit;
        }
        for (i = 1;; i++, dval(d) *= 10.) {
            L = (Long)(dval(d) / ds);
            dval(d) -= L*ds;
#ifdef Check_FLT_ROUNDS
            /* If FLT_ROUNDS == 2, L will usually be high by 1 */
            if (dval(d) < 0) {
                L--;
                dval(d) += ds;
            }
#endif
            *s++ = '0' + (int)L;
            if (!dval(d)) {
#ifdef SET_INEXACT
                inexact = 0;
#endif
                break;
            }
            if (i == ilim) {
#ifdef Honor_FLT_ROUNDS
                if (mode > 1)
                switch (rounding) {
                  case 0: goto ret1;
                  case 2: goto bump_up;
                }
#endif
                dval(d) += dval(d);
                if (dval(d) > ds || (dval(d) == ds && (L & 1))) {
bump_up:
                    while (*--s == '9')
                        if (s == s0) {
                            k++;
                            *s = '0';
                            break;
                        }
                    ++*s++;
                }
                break;
            }
        }
        goto ret1;
    }

    m2 = b2;
    m5 = b5;
    if (leftright) {
        i =
#ifndef Sudden_Underflow
            denorm ? be + (Bias + (P-1) - 1 + 1) :
#endif
#ifdef IBM
            1 + 4*P - 3 - bbits + ((bbits + be - 1) & 3);
#else
            1 + P - bbits;
#endif
        b2 += i;
        s2 += i;
        mhi = i2b(1);
    }
    if (m2 > 0 && s2 > 0) {
        i = m2 < s2 ? m2 : s2;
        b2 -= i;
        m2 -= i;
        s2 -= i;
    }
    if (b5 > 0) {
        if (leftright) {
            if (m5 > 0) {
                mhi = pow5mult(mhi, m5);
                b1 = mult(mhi, b);
                Bfree(b);
                b = b1;
            }
            if ((j = b5 - m5) != 0)
                b = pow5mult(b, j);
        }
        else
            b = pow5mult(b, b5);
    }
    S = i2b(1);
    if (s5 > 0)
        S = pow5mult(S, s5);

    /* Check for special case that d is a normalized power of 2. */

    spec_case = 0;
    if ((mode < 2 || leftright)
#ifdef Honor_FLT_ROUNDS
            && rounding == 1
#endif
    ) {
        if (!word1(d) && !(word0(d) & Bndry_mask)
#ifndef Sudden_Underflow
            && word0(d) & (Exp_mask & ~Exp_msk1)
#endif
        ) {
            /* The special case */
            b2 += Log2P;
            s2 += Log2P;
            spec_case = 1;
        }
    }

    /* Arrange for convenient computation of quotients:
     * shift left if necessary so divisor has 4 leading 0 bits.
     *
     * Perhaps we should just compute leading 28 bits of S once
     * and for all and pass them and a shift to quorem, so it
     * can do shifts and ors to compute the numerator for q.
     */
#ifdef Pack_32
    if ((i = ((s5 ? 32 - hi0bits(S->x[S->wds-1]) : 1) + s2) & 0x1f) != 0)
        i = 32 - i;
#else
    if ((i = ((s5 ? 32 - hi0bits(S->x[S->wds-1]) : 1) + s2) & 0xf) != 0)
        i = 16 - i;
#endif
    if (i > 4) {
        i -= 4;
        b2 += i;
        m2 += i;
        s2 += i;
    }
    else if (i < 4) {
        i += 28;
        b2 += i;
        m2 += i;
        s2 += i;
    }
    if (b2 > 0)
        b = lshift(b, b2);
    if (s2 > 0)
        S = lshift(S, s2);
    if (k_check) {
        if (cmp(b,S) < 0) {
            k--;
            b = multadd(b, 10, 0);  /* we botched the k estimate */
            if (leftright)
                mhi = multadd(mhi, 10, 0);
            ilim = ilim1;
        }
    }
    if (ilim <= 0 && (mode == 3 || mode == 5)) {
        if (ilim < 0 || cmp(b,S = multadd(S,5,0)) <= 0) {
            /* no digits, fcvt style */
no_digits:
            k = -1 - ndigits;
            goto ret;
        }
one_digit:
        *s++ = '1';
        k++;
        goto ret;
    }
    if (leftright) {
        if (m2 > 0)
            mhi = lshift(mhi, m2);

        /* Compute mlo -- check for special case
         * that d is a normalized power of 2.
         */

        mlo = mhi;
        if (spec_case) {
            mhi = Balloc(mhi->k);
            Bcopy(mhi, mlo);
            mhi = lshift(mhi, Log2P);
        }

        for (i = 1;;i++) {
            dig = quorem(b,S) + '0';
            /* Do we yet have the shortest decimal string
             * that will round to d?
             */
            j = cmp(b, mlo);
            delta = diff(S, mhi);
            j1 = delta->sign ? 1 : cmp(b, delta);
            Bfree(delta);
#ifndef ROUND_BIASED
            if (j1 == 0 && mode != 1 && !(word1(d) & 1)
#ifdef Honor_FLT_ROUNDS
                && rounding >= 1
#endif
            ) {
                if (dig == '9')
                    goto round_9_up;
                if (j > 0)
                    dig++;
#ifdef SET_INEXACT
                else if (!b->x[0] && b->wds <= 1)
                    inexact = 0;
#endif
                *s++ = dig;
                goto ret;
            }
#endif
            if (j < 0 || (j == 0 && mode != 1
#ifndef ROUND_BIASED
                && !(word1(d) & 1)
#endif
            )) {
                if (!b->x[0] && b->wds <= 1) {
#ifdef SET_INEXACT
                    inexact = 0;
#endif
                    goto accept_dig;
                }
#ifdef Honor_FLT_ROUNDS
                if (mode > 1)
                    switch (rounding) {
                      case 0: goto accept_dig;
                      case 2: goto keep_dig;
                    }
#endif /*Honor_FLT_ROUNDS*/
                if (j1 > 0) {
                    b = lshift(b, 1);
                    j1 = cmp(b, S);
                    if ((j1 > 0 || (j1 == 0 && (dig & 1))) && dig++ == '9')
                        goto round_9_up;
                }
accept_dig:
                *s++ = dig;
                goto ret;
            }
            if (j1 > 0) {
#ifdef Honor_FLT_ROUNDS
                if (!rounding)
                    goto accept_dig;
#endif
                if (dig == '9') { /* possible if i == 1 */
round_9_up:
                    *s++ = '9';
                    goto roundoff;
                }
                *s++ = dig + 1;
                goto ret;
            }
#ifdef Honor_FLT_ROUNDS
keep_dig:
#endif
            *s++ = dig;
            if (i == ilim)
                break;
            b = multadd(b, 10, 0);
            if (mlo == mhi)
                mlo = mhi = multadd(mhi, 10, 0);
            else {
                mlo = multadd(mlo, 10, 0);
                mhi = multadd(mhi, 10, 0);
            }
        }
    }
    else
        for (i = 1;; i++) {
            *s++ = dig = quorem(b,S) + '0';
            if (!b->x[0] && b->wds <= 1) {
#ifdef SET_INEXACT
                inexact = 0;
#endif
                goto ret;
            }
            if (i >= ilim)
                break;
            b = multadd(b, 10, 0);
        }

    /* Round off last digit */

#ifdef Honor_FLT_ROUNDS
    switch (rounding) {
      case 0: goto trimzeros;
      case 2: goto roundoff;
    }
#endif
    b = lshift(b, 1);
    j = cmp(b, S);
    if (j > 0 || (j == 0 && (dig & 1))) {
 roundoff:
        while (*--s == '9')
            if (s == s0) {
                k++;
                *s++ = '1';
                goto ret;
            }
        ++*s++;
    }
    else {
        while (*--s == '0') ;
        s++;
    }
ret:
    Bfree(S);
    if (mhi) {
        if (mlo && mlo != mhi)
            Bfree(mlo);
        Bfree(mhi);
    }
ret1:
#ifdef SET_INEXACT
    if (inexact) {
        if (!oldinexact) {
            word0(d) = Exp_1 + (70 << Exp_shift);
            word1(d) = 0;
            dval(d) += 1.;
        }
    }
    else if (!oldinexact)
        clear_inexact();
#endif
    Bfree(b);
    *s = 0;
    *decpt = k + 1;
    if (rve)
        *rve = s;
    return s0;
}

void
ruby_each_words(const char *str, void (*func)(const char*, int, void*), void *arg)
{
    const char *end;
    int len;

    if (!str) return;
    for (; *str; str = end) {
	while (ISSPACE(*str) || *str == ',') str++;
	if (!*str) break;
	end = str;
	while (*end && !ISSPACE(*end) && *end != ',') end++;
	len = (int)(end - str);	/* assume no string exceeds INT_MAX */
	(*func)(str, len, arg);
    }
}

/*-
 * Copyright (c) 2004-2008 David Schultz <das@FreeBSD.ORG>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#define	DBL_MANH_SIZE	20
#define	DBL_MANL_SIZE	32
#define	DBL_ADJ	(DBL_MAX_EXP - 2)
#define	SIGFIGS	((DBL_MANT_DIG + 3) / 4 + 1)
#define dexp_get(u) ((int)(word0(u) >> Exp_shift) & ~Exp_msk1)
#define dexp_set(u,v) (word0(u) = (((int)(word0(u)) & ~Exp_mask) | ((v) << Exp_shift)))
#define dmanh_get(u) ((uint32_t)(word0(u) & Frac_mask))
#define dmanl_get(u) ((uint32_t)word1(u))


/*
 * This procedure converts a double-precision number in IEEE format
 * into a string of hexadecimal digits and an exponent of 2.  Its
 * behavior is bug-for-bug compatible with dtoa() in mode 2, with the
 * following exceptions:
 *
 * - An ndigits < 0 causes it to use as many digits as necessary to
 *   represent the number exactly.
 * - The additional xdigs argument should point to either the string
 *   "0123456789ABCDEF" or the string "0123456789abcdef", depending on
 *   which case is desired.
 * - This routine does not repeat dtoa's mistake of setting decpt
 *   to 9999 in the case of an infinity or NaN.  INT_MAX is used
 *   for this purpose instead.
 *
 * Note that the C99 standard does not specify what the leading digit
 * should be for non-zero numbers.  For instance, 0x1.3p3 is the same
 * as 0x2.6p2 is the same as 0x4.cp3.  This implementation always makes
 * the leading digit a 1. This ensures that the exponent printed is the
 * actual base-2 exponent, i.e., ilogb(d).
 *
 * Inputs:	d, xdigs, ndigits
 * Outputs:	decpt, sign, rve
 */
char *
ruby_hdtoa(double d, const char *xdigs, int ndigits, int *decpt, int *sign,
    char **rve)
{
	U u;
	char *s, *s0;
	int bufsize;
	uint32_t manh, manl;

	u.d = d;
	if (word0(u) & Sign_bit) {
	    /* set sign for everything, including 0's and NaNs */
	    *sign = 1;
	    word0(u) &= ~Sign_bit;  /* clear sign bit */
	}
	else
	    *sign = 0;

	if (isinf(d)) { /* FP_INFINITE */
	    *decpt = INT_MAX;
	    return rv_strdup(INFSTR, rve);
	}
	else if (isnan(d)) { /* FP_NAN */
	    *decpt = INT_MAX;
	    return rv_strdup(NANSTR, rve);
	}
	else if (d == 0.0) { /* FP_ZERO */
	    *decpt = 1;
	    return rv_strdup(ZEROSTR, rve);
	}
	else if (dexp_get(u)) { /* FP_NORMAL */
	    *decpt = dexp_get(u) - DBL_ADJ;
	}
	else { /* FP_SUBNORMAL */
	    u.d *= 5.363123171977039e+154 /* 0x1p514 */;
	    *decpt = dexp_get(u) - (514 + DBL_ADJ);
	}

	if (ndigits == 0)		/* dtoa() compatibility */
		ndigits = 1;

	/*
	 * If ndigits < 0, we are expected to auto-size, so we allocate
	 * enough space for all the digits.
	 */
	bufsize = (ndigits > 0) ? ndigits : SIGFIGS;
	s0 = rv_alloc(bufsize+1);

	/* Round to the desired number of digits. */
	if (SIGFIGS > ndigits && ndigits > 0) {
		float redux = 1.0f;
		int offset = 4 * ndigits + DBL_MAX_EXP - 4 - DBL_MANT_DIG;
		dexp_set(u, offset);
		u.d += redux;
		u.d -= redux;
		*decpt += dexp_get(u) - offset;
	}

	manh = dmanh_get(u);
	manl = dmanl_get(u);
	*s0 = '1';
	for (s = s0 + 1; s < s0 + bufsize; s++) {
		*s = xdigs[(manh >> (DBL_MANH_SIZE - 4)) & 0xf];
		manh = (manh << 4) | (manl >> (DBL_MANL_SIZE - 4));
		manl <<= 4;
	}

	/* If ndigits < 0, we are expected to auto-size the precision. */
	if (ndigits < 0) {
		for (ndigits = SIGFIGS; s0[ndigits - 1] == '0'; ndigits--)
			;
	}

	s = s0 + ndigits;
	*s = '\0';
	if (rve != NULL)
		*rve = s;
	return (s0);
}

#ifdef __cplusplus
#if 0
{ /* satisfy cc-mode */
#endif
}
#endif
