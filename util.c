/**********************************************************************

  util.c -

  $Author$
  created at: Fri Mar 10 17:22:34 JST 1995

  Copyright (C) 1993-2008 Yukihiro Matsumoto

**********************************************************************/

#if defined __MINGW32__ || defined __MINGW64__
# define MINGW_HAS_SECURE_API 1
#endif

#include "ruby/internal/config.h"

#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <math.h>
#include <stdio.h>

#ifdef _WIN32
# include "missing/file.h"
#endif

#include "internal.h"
#include "internal/sanitizers.h"
#include "internal/util.h"
#include "ruby/util.h"
#include "ruby_atomic.h"

const char ruby_hexdigits[] = "0123456789abcdef0123456789ABCDEF";
#define hexdigit ruby_hexdigits

unsigned long
ruby_scan_oct(const char *start, size_t len, size_t *retlen)
{
    register const char *s = start;
    register unsigned long retval = 0;
    size_t i;

    for (i = 0; i < len; i++) {
        if ((s[0] < '0') || ('7' < s[0])) {
            break;
        }
	retval <<= 3;
	retval |= *s++ - '0';
    }
    *retlen = (size_t)(s - start);
    return retval;
}

unsigned long
ruby_scan_hex(const char *start, size_t len, size_t *retlen)
{
    register const char *s = start;
    register unsigned long retval = 0;
    signed char d;
    size_t i = 0;

    for (i = 0; i < len; i++) {
        d = ruby_digit36_to_number_table[(unsigned char)*s];
        if (d < 0 || 15 < d) {
            break;
        }
	retval <<= 4;
	retval |= d;
	s++;
    }
    *retlen = (size_t)(s - start);
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

NO_SANITIZE("unsigned-integer-overflow", extern unsigned long ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow));
unsigned long
ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow)
{
    RBIMPL_ASSERT_OR_ASSUME(base >= 2);
    RBIMPL_ASSERT_OR_ASSUME(base <= 36);

    const char *start = str;
    unsigned long ret = 0, x;
    unsigned long mul_overflow = (~(unsigned long)0) / base;

    *overflow = 0;

    if (!len) {
	*retlen = 0;
	return 0;
    }

    do {
	int d = ruby_digit36_to_number_table[(unsigned char)*str++];
        if (d == -1 || base <= d) {
	    --str;
	    break;
        }
        if (mul_overflow < ret)
            *overflow = 1;
        ret *= base;
        x = ret;
        ret += d;
        if (ret < x)
            *overflow = 1;
    } while (len < 0 || --len);
    *retlen = str - start;
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

    if (base < 0) {
        errno = EINVAL;
        return 0;
    }

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

    ret = ruby_scan_digits(str, -1, b, &len, &overflow);

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

#if !defined HAVE_GNU_QSORT_R
#include <sys/types.h>
#include <stdint.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

typedef int (cmpfunc_t)(const void*, const void*, void*);

#if defined HAVE_QSORT_S && defined RUBY_MSVCRT_VERSION
/* In contrast to its name, Visual Studio qsort_s is incompatible with
 * C11 in the order of the comparison function's arguments, and same
 * as BSD qsort_r rather. */
# define qsort_r(base, nel, size, arg, cmp) qsort_s(base, nel, size, cmp, arg)
# define cmp_bsd_qsort cmp_ms_qsort
# define HAVE_BSD_QSORT_R 1
#endif

#if defined HAVE_BSD_QSORT_R
struct bsd_qsort_r_args {
    cmpfunc_t *cmp;
    void *arg;
};

static int
cmp_bsd_qsort(void *d, const void *a, const void *b)
{
    const struct bsd_qsort_r_args *args = d;
    return (*args->cmp)(a, b, args->arg);
}

void
ruby_qsort(void* base, const size_t nel, const size_t size, cmpfunc_t *cmp, void *d)
{
    struct bsd_qsort_r_args args;
    args.cmp = cmp;
    args.arg = d;
    qsort_r(base, nel, size, &args, cmp_bsd_qsort);
}
#elif defined HAVE_QSORT_S
/* C11 qsort_s has the same arguments as GNU's, but uses
 * runtime-constraints handler. */
void
ruby_qsort(void* base, const size_t nel, const size_t size, cmpfunc_t *cmp, void *d)
{
    if (!nel || !size) return;  /* nothing to sort */

    /* get rid of runtime-constraints handler for MT-safeness */
    if (!base || !cmp) return;
    if (nel > RSIZE_MAX || size > RSIZE_MAX) return;

    qsort_s(base, nel, size, cmp, d);
}
# define HAVE_GNU_QSORT_R 1
#else
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
      if ((*cmp)(L,R,d) > 0) mmswap(L,R);
      goto nxt;
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
#endif
#endif /* !HAVE_GNU_QSORT_R */

char *
ruby_strdup(const char *str)
{
    char *tmp;
    size_t len = strlen(str) + 1;

    tmp = xmalloc(len);
    memcpy(tmp, str, len);

    return tmp;
}

char *
ruby_getcwd(void)
{
#if defined HAVE_GETCWD
# undef RUBY_UNTYPED_DATA_WARNING
# define RUBY_UNTYPED_DATA_WARNING 0
# if defined NO_GETCWD_MALLOC
    VALUE guard = Data_Wrap_Struct((VALUE)0, NULL, RUBY_DEFAULT_FREE, NULL);
    int size = 200;
    char *buf = xmalloc(size);

    while (!getcwd(buf, size)) {
	int e = errno;
	if (e != ERANGE) {
	    xfree(buf);
	    DATA_PTR(guard) = NULL;
	    rb_syserr_fail(e, "getcwd");
	}
	size *= 2;
	DATA_PTR(guard) = buf;
	buf = xrealloc(buf, size);
    }
# else
    VALUE guard = Data_Wrap_Struct((VALUE)0, NULL, free, NULL);
    char *buf, *cwd = getcwd(NULL, 0);
    DATA_PTR(guard) = cwd;
    if (!cwd) rb_sys_fail("getcwd");
    buf = ruby_strdup(cwd);	/* allocate by xmalloc */
    free(cwd);
# endif
    DATA_PTR(RB_GC_GUARD(guard)) = NULL;
#else
# ifndef PATH_MAX
#  define PATH_MAX 8192
# endif
    char *buf = xmalloc(PATH_MAX+1);

    if (!getwd(buf)) {
	int e = errno;
	xfree(buf);
	rb_syserr_fail(e, "getwd");
    }
#endif
    return buf;
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

#undef strtod
#define strtod ruby_strtod
#undef dtoa
#define dtoa ruby_dtoa
#undef hdtoa
#define hdtoa ruby_hdtoa
#include "missing/dtoa.c"
