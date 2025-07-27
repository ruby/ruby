/**********************************************************************

  time.c -

  $Author$
  created at: Tue Dec 28 14:31:59 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#define _DEFAULT_SOURCE
#define _BSD_SOURCE
#include "ruby/internal/config.h"

#include <errno.h>
#include <float.h>
#include <math.h>
#include <time.h>
#include <sys/types.h>

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_STRINGS_H
# include <strings.h>
#endif

#if defined(HAVE_SYS_TIME_H)
# include <sys/time.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/hash.h"
#include "internal/compar.h"
#include "internal/numeric.h"
#include "internal/rational.h"
#include "internal/string.h"
#include "internal/time.h"
#include "internal/variable.h"
#include "ruby/encoding.h"
#include "ruby/util.h"
#include "timev.h"

#if defined(_WIN32)
# include <timezoneapi.h> /* DYNAMIC_TIME_ZONE_INFORMATION */
#endif

#include "builtin.h"

static ID id_submicro, id_nano_num, id_nano_den, id_offset, id_zone;
static ID id_nanosecond, id_microsecond, id_millisecond, id_nsec, id_usec;
static ID id_local_to_utc, id_utc_to_local, id_find_timezone;
static ID id_year, id_mon, id_mday, id_hour, id_min, id_sec, id_isdst;
static VALUE str_utc, str_empty;

// used by deconstruct_keys
static VALUE sym_year, sym_month, sym_day, sym_yday, sym_wday;
static VALUE sym_hour, sym_min, sym_sec, sym_subsec, sym_dst, sym_zone;

#define id_quo idQuo
#define id_div idDiv
#define id_divmod idDivmod
#define id_name idName
#define UTC_ZONE Qundef

#define NDIV(x,y) (-(-((x)+1)/(y))-1)
#define NMOD(x,y) ((y)-(-((x)+1)%(y))-1)
#define DIV(n,d) ((n)<0 ? NDIV((n),(d)) : (n)/(d))
#define MOD(n,d) ((n)<0 ? NMOD((n),(d)) : (n)%(d))
#define VTM_WDAY_INITVAL (7)
#define VTM_ISDST_INITVAL (3)

static int
eq(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        return x == y;
    }
    return RTEST(rb_funcall(x, idEq, 1, y));
}

static int
cmp(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        if ((long)x < (long)y)
            return -1;
        if ((long)x > (long)y)
            return 1;
        return 0;
    }
    if (RB_BIGNUM_TYPE_P(x)) return FIX2INT(rb_big_cmp(x, y));
    return rb_cmpint(rb_funcall(x, idCmp, 1, y), x, y);
}

#define ne(x,y) (!eq((x),(y)))
#define lt(x,y) (cmp((x),(y)) < 0)
#define gt(x,y) (cmp((x),(y)) > 0)
#define le(x,y) (cmp((x),(y)) <= 0)
#define ge(x,y) (cmp((x),(y)) >= 0)

static VALUE
addv(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        return LONG2NUM(FIX2LONG(x) + FIX2LONG(y));
    }
    if (RB_BIGNUM_TYPE_P(x)) return rb_big_plus(x, y);
    return rb_funcall(x, '+', 1, y);
}

static VALUE
subv(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        return LONG2NUM(FIX2LONG(x) - FIX2LONG(y));
    }
    if (RB_BIGNUM_TYPE_P(x)) return rb_big_minus(x, y);
    return rb_funcall(x, '-', 1, y);
}

static VALUE
mulv(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        return rb_fix_mul_fix(x, y);
    }
    if (RB_BIGNUM_TYPE_P(x))
        return rb_big_mul(x, y);
    return rb_funcall(x, '*', 1, y);
}

static VALUE
divv(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        return rb_fix_div_fix(x, y);
    }
    if (RB_BIGNUM_TYPE_P(x))
        return rb_big_div(x, y);
    return rb_funcall(x, id_div, 1, y);
}

static VALUE
modv(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        if (FIX2LONG(y) == 0) rb_num_zerodiv();
        if (FIXNUM_P(x)) return rb_fix_mod_fix(x, y);
    }
    if (RB_BIGNUM_TYPE_P(x)) return rb_big_modulo(x, y);
    return rb_funcall(x, '%', 1, y);
}

#define neg(x) (subv(INT2FIX(0), (x)))

static VALUE
quor(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
        long a, b, c;
        a = FIX2LONG(x);
        b = FIX2LONG(y);
        if (b == 0) rb_num_zerodiv();
        if (a == FIXNUM_MIN && b == -1) return LONG2NUM(-a);
        c = a / b;
        if (c * b == a) {
            return LONG2FIX(c);
        }
    }
    return rb_numeric_quo(x, y);
}

static VALUE
quov(VALUE x, VALUE y)
{
    VALUE ret = quor(x, y);
    if (RB_TYPE_P(ret, T_RATIONAL) &&
        RRATIONAL(ret)->den == INT2FIX(1)) {
        ret = RRATIONAL(ret)->num;
    }
    return ret;
}

#define mulquov(x,y,z) (((y) == (z)) ? (x) : quov(mulv((x),(y)),(z)))

static void
divmodv(VALUE n, VALUE d, VALUE *q, VALUE *r)
{
    VALUE tmp, ary;
    if (FIXNUM_P(d)) {
        if (FIX2LONG(d) == 0) rb_num_zerodiv();
        if (FIXNUM_P(n)) {
            rb_fix_divmod_fix(n, d, q, r);
            return;
        }
    }
    tmp = rb_funcall(n, id_divmod, 1, d);
    ary = rb_check_array_type(tmp);
    if (NIL_P(ary)) {
        rb_raise(rb_eTypeError, "unexpected divmod result: into %"PRIsVALUE,
                 rb_obj_class(tmp));
    }
    *q = rb_ary_entry(ary, 0);
    *r = rb_ary_entry(ary, 1);
}

#if SIZEOF_LONG == 8
# define INT64toNUM(x) LONG2NUM(x)
#elif defined(HAVE_LONG_LONG) && SIZEOF_LONG_LONG == 8
# define INT64toNUM(x) LL2NUM(x)
#endif

#if defined(HAVE_UINT64_T) && SIZEOF_LONG*2 <= SIZEOF_UINT64_T
    typedef uint64_t uwideint_t;
    typedef int64_t wideint_t;
    typedef uint64_t WIDEVALUE;
    typedef int64_t SIGNED_WIDEVALUE;
#   define WIDEVALUE_IS_WIDER 1
#   define UWIDEINT_MAX UINT64_MAX
#   define WIDEINT_MAX INT64_MAX
#   define WIDEINT_MIN INT64_MIN
#   define FIXWINT_P(tv) ((tv) & 1)
#   define FIXWVtoINT64(tv) RSHIFT((SIGNED_WIDEVALUE)(tv), 1)
#   define INT64toFIXWV(wi) ((WIDEVALUE)((SIGNED_WIDEVALUE)(wi) << 1 | FIXNUM_FLAG))
#   define FIXWV_MAX (((int64_t)1 << 62) - 1)
#   define FIXWV_MIN (-((int64_t)1 << 62))
#   define FIXWVABLE(wi) (POSFIXWVABLE(wi) && NEGFIXWVABLE(wi))
#   define WINT2FIXWV(i) WIDEVAL_WRAP(INT64toFIXWV(i))
#   define FIXWV2WINT(w) FIXWVtoINT64(WIDEVAL_GET(w))
#else
    typedef unsigned long uwideint_t;
    typedef long wideint_t;
    typedef VALUE WIDEVALUE;
    typedef SIGNED_VALUE SIGNED_WIDEVALUE;
#   define WIDEVALUE_IS_WIDER 0
#   define UWIDEINT_MAX ULONG_MAX
#   define WIDEINT_MAX LONG_MAX
#   define WIDEINT_MIN LONG_MIN
#   define FIXWINT_P(v) FIXNUM_P(v)
#   define FIXWV_MAX FIXNUM_MAX
#   define FIXWV_MIN FIXNUM_MIN
#   define FIXWVABLE(i) FIXABLE(i)
#   define WINT2FIXWV(i) WIDEVAL_WRAP(LONG2FIX(i))
#   define FIXWV2WINT(w) FIX2LONG(WIDEVAL_GET(w))
#endif

#define SIZEOF_WIDEINT SIZEOF_INT64_T
#define POSFIXWVABLE(wi) ((wi) < FIXWV_MAX+1)
#define NEGFIXWVABLE(wi) ((wi) >= FIXWV_MIN)
#define FIXWV_P(w) FIXWINT_P(WIDEVAL_GET(w))
#define MUL_OVERFLOW_FIXWV_P(a, b) MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, FIXWV_MIN, FIXWV_MAX)

/* #define STRUCT_WIDEVAL */
#ifdef STRUCT_WIDEVAL
    /* for type checking */
    typedef struct {
        WIDEVALUE value;
    } wideval_t;
    static inline wideval_t WIDEVAL_WRAP(WIDEVALUE v) { wideval_t w = { v }; return w; }
#   define WIDEVAL_GET(w) ((w).value)
#else
    typedef WIDEVALUE wideval_t;
#   define WIDEVAL_WRAP(v) (v)
#   define WIDEVAL_GET(w) (w)
#endif

#if WIDEVALUE_IS_WIDER
    static inline wideval_t
    wint2wv(wideint_t wi)
    {
        if (FIXWVABLE(wi))
            return WINT2FIXWV(wi);
        else
            return WIDEVAL_WRAP(INT64toNUM(wi));
    }
#   define WINT2WV(wi) wint2wv(wi)
#else
#   define WINT2WV(wi) WIDEVAL_WRAP(LONG2NUM(wi))
#endif

static inline VALUE
w2v(wideval_t w)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(w))
        return INT64toNUM(FIXWV2WINT(w));
    return (VALUE)WIDEVAL_GET(w);
#else
    return WIDEVAL_GET(w);
#endif
}

#if WIDEVALUE_IS_WIDER
static wideval_t
v2w_bignum(VALUE v)
{
    int sign;
    uwideint_t u;
    sign = rb_integer_pack(v, &u, 1, sizeof(u), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER);
    if (sign == 0)
        return WINT2FIXWV(0);
    else if (sign == -1) {
        if (u <= -FIXWV_MIN)
            return WINT2FIXWV(-(wideint_t)u);
    }
    else if (sign == +1) {
        if (u <= FIXWV_MAX)
            return WINT2FIXWV((wideint_t)u);
    }
    return WIDEVAL_WRAP(v);
}
#endif

static inline wideval_t
v2w(VALUE v)
{
    if (RB_TYPE_P(v, T_RATIONAL)) {
        if (RRATIONAL(v)->den != LONG2FIX(1))
            return WIDEVAL_WRAP(v);
        v = RRATIONAL(v)->num;
    }
#if WIDEVALUE_IS_WIDER
    if (FIXNUM_P(v)) {
        return WIDEVAL_WRAP((WIDEVALUE)(SIGNED_WIDEVALUE)(long)v);
    }
    else if (RB_BIGNUM_TYPE_P(v) &&
        rb_absint_size(v, NULL) <= sizeof(WIDEVALUE)) {
        return v2w_bignum(v);
    }
#endif
    return WIDEVAL_WRAP(v);
}

#define NUM2WV(v) v2w(rb_Integer(v))

static int
weq(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(wx) && FIXWV_P(wy)) {
        return WIDEVAL_GET(wx) == WIDEVAL_GET(wy);
    }
    return RTEST(rb_funcall(w2v(wx), idEq, 1, w2v(wy)));
#else
    return eq(WIDEVAL_GET(wx), WIDEVAL_GET(wy));
#endif
}

static int
wcmp(wideval_t wx, wideval_t wy)
{
    VALUE x, y;
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(wx) && FIXWV_P(wy)) {
        wideint_t a, b;
        a = FIXWV2WINT(wx);
        b = FIXWV2WINT(wy);
        if (a < b)
            return -1;
        if (a > b)
            return 1;
        return 0;
    }
#endif
    x = w2v(wx);
    y = w2v(wy);
    return cmp(x, y);
}

#define wne(x,y) (!weq((x),(y)))
#define wlt(x,y) (wcmp((x),(y)) < 0)
#define wgt(x,y) (wcmp((x),(y)) > 0)
#define wle(x,y) (wcmp((x),(y)) <= 0)
#define wge(x,y) (wcmp((x),(y)) >= 0)

static wideval_t
wadd(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(wx) && FIXWV_P(wy)) {
        wideint_t r = FIXWV2WINT(wx) + FIXWV2WINT(wy);
        return WINT2WV(r);
    }
#endif
    return v2w(addv(w2v(wx), w2v(wy)));
}

static wideval_t
wsub(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(wx) && FIXWV_P(wy)) {
        wideint_t r = FIXWV2WINT(wx) - FIXWV2WINT(wy);
        return WINT2WV(r);
    }
#endif
    return v2w(subv(w2v(wx), w2v(wy)));
}

static wideval_t
wmul(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(wx) && FIXWV_P(wy)) {
        if (!MUL_OVERFLOW_FIXWV_P(FIXWV2WINT(wx), FIXWV2WINT(wy)))
            return WINT2WV(FIXWV2WINT(wx) * FIXWV2WINT(wy));
    }
#endif
    return v2w(mulv(w2v(wx), w2v(wy)));
}

static wideval_t
wquo(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(wx) && FIXWV_P(wy)) {
        wideint_t a, b, c;
        a = FIXWV2WINT(wx);
        b = FIXWV2WINT(wy);
        if (b == 0) rb_num_zerodiv();
        c = a / b;
        if (c * b == a) {
            return WINT2WV(c);
        }
    }
#endif
    return v2w(quov(w2v(wx), w2v(wy)));
}

#define wmulquo(x,y,z) ((WIDEVAL_GET(y) == WIDEVAL_GET(z)) ? (x) : wquo(wmul((x),(y)),(z)))
#define wmulquoll(x,y,z) (((y) == (z)) ? (x) : wquo(wmul((x),WINT2WV(y)),WINT2WV(z)))

#if WIDEVALUE_IS_WIDER
static int
wdivmod0(wideval_t wn, wideval_t wd, wideval_t *wq, wideval_t *wr)
{
    if (FIXWV_P(wn) && FIXWV_P(wd)) {
        wideint_t n, d, q, r;
        d = FIXWV2WINT(wd);
        if (d == 0) rb_num_zerodiv();
        if (d == 1) {
            *wq = wn;
            *wr = WINT2FIXWV(0);
            return 1;
        }
        if (d == -1) {
            wideint_t xneg = -FIXWV2WINT(wn);
            *wq = WINT2WV(xneg);
            *wr = WINT2FIXWV(0);
            return 1;
        }
        n = FIXWV2WINT(wn);
        if (n == 0) {
            *wq = WINT2FIXWV(0);
            *wr = WINT2FIXWV(0);
            return 1;
        }
        q = n / d;
        r = n % d;
        if (d > 0 ? r < 0 : r > 0) {
            q -= 1;
            r += d;
        }
        *wq = WINT2FIXWV(q);
        *wr = WINT2FIXWV(r);
        return 1;
    }
    return 0;
}
#endif

static void
wdivmod(wideval_t wn, wideval_t wd, wideval_t *wq, wideval_t *wr)
{
    VALUE vq, vr;
#if WIDEVALUE_IS_WIDER
    if (wdivmod0(wn, wd, wq, wr)) return;
#endif
    divmodv(w2v(wn), w2v(wd), &vq, &vr);
    *wq = v2w(vq);
    *wr = v2w(vr);
}

static void
wmuldivmod(wideval_t wx, wideval_t wy, wideval_t wz, wideval_t *wq, wideval_t *wr)
{
    if (WIDEVAL_GET(wy) == WIDEVAL_GET(wz)) {
        *wq = wx;
        *wr = WINT2FIXWV(0);
        return;
    }
    wdivmod(wmul(wx,wy), wz, wq, wr);
}

static wideval_t
wdiv(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    wideval_t q, dmy;
    if (wdivmod0(wx, wy, &q, &dmy)) return q;
#endif
    return v2w(divv(w2v(wx), w2v(wy)));
}

static wideval_t
wmod(wideval_t wx, wideval_t wy)
{
#if WIDEVALUE_IS_WIDER
    wideval_t r, dmy;
    if (wdivmod0(wx, wy, &dmy, &r)) return r;
#endif
    return v2w(modv(w2v(wx), w2v(wy)));
}

static VALUE
num_exact_check(VALUE v)
{
    VALUE tmp;

    switch (TYPE(v)) {
      case T_FIXNUM:
      case T_BIGNUM:
        tmp = v;
        break;

      case T_RATIONAL:
        tmp = rb_rational_canonicalize(v);
        break;

      default:
        if (!UNDEF_P(tmp = rb_check_funcall(v, idTo_r, 0, NULL))) {
            /* test to_int method availability to reject non-Numeric
             * objects such as String, Time, etc which have to_r method. */
            if (!rb_respond_to(v, idTo_int)) {
                /* FALLTHROUGH */
            }
            else if (RB_INTEGER_TYPE_P(tmp)) {
                break;
            }
            else if (RB_TYPE_P(tmp, T_RATIONAL)) {
                tmp = rb_rational_canonicalize(tmp);
                break;
            }
        }
        else if (!NIL_P(tmp = rb_check_to_int(v))) {
            return tmp;
        }

      case T_NIL:
      case T_STRING:
        return Qnil;
    }
    ASSUME(!NIL_P(tmp));
    return tmp;
}

NORETURN(static void num_exact_fail(VALUE v));
static void
num_exact_fail(VALUE v)
{
    rb_raise(rb_eTypeError, "can't convert %"PRIsVALUE" into an exact number",
             rb_obj_class(v));
}

static VALUE
num_exact(VALUE v)
{
    VALUE num = num_exact_check(v);
    if (NIL_P(num)) num_exact_fail(v);
    return num;
}

/* time_t */

/* TIME_SCALE should be 10000... */
static const int TIME_SCALE_NUMDIGITS = rb_strlen_lit(STRINGIZE(TIME_SCALE)) - 1;

static wideval_t
rb_time_magnify(wideval_t w)
{
    return wmul(w, WINT2FIXWV(TIME_SCALE));
}

static VALUE
rb_time_unmagnify_to_rational(wideval_t w)
{
    return quor(w2v(w), INT2FIX(TIME_SCALE));
}

static wideval_t
rb_time_unmagnify(wideval_t w)
{
    return v2w(rb_time_unmagnify_to_rational(w));
}

static VALUE
rb_time_unmagnify_to_float(wideval_t w)
{
    VALUE v;
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(w)) {
        wideint_t a, b, c;
        a = FIXWV2WINT(w);
        b = TIME_SCALE;
        c = a / b;
        if (c * b == a) {
            return DBL2NUM((double)c);
        }
        v = DBL2NUM((double)FIXWV2WINT(w));
        return quov(v, DBL2NUM(TIME_SCALE));
    }
#endif
    v = w2v(w);
    if (RB_TYPE_P(v, T_RATIONAL))
        return rb_Float(quov(v, INT2FIX(TIME_SCALE)));
    else
        return quov(v, DBL2NUM(TIME_SCALE));
}

static void
split_second(wideval_t timew, wideval_t *timew_p, VALUE *subsecx_p)
{
    wideval_t q, r;
    wdivmod(timew, WINT2FIXWV(TIME_SCALE), &q, &r);
    *timew_p = q;
    *subsecx_p = w2v(r);
}

static wideval_t
timet2wv(time_t t)
{
#if WIDEVALUE_IS_WIDER
    if (TIMET_MIN == 0) {
        uwideint_t wi = (uwideint_t)t;
        if (wi <= FIXWV_MAX) {
            return WINT2FIXWV(wi);
        }
    }
    else {
        wideint_t wi = (wideint_t)t;
        if (FIXWV_MIN <= wi && wi <= FIXWV_MAX) {
            return WINT2FIXWV(wi);
        }
    }
#endif
    return v2w(TIMET2NUM(t));
}
#define TIMET2WV(t) timet2wv(t)

static time_t
wv2timet(wideval_t w)
{
#if WIDEVALUE_IS_WIDER
    if (FIXWV_P(w)) {
        wideint_t wi = FIXWV2WINT(w);
        if (TIMET_MIN == 0) {
            if (wi < 0)
                rb_raise(rb_eRangeError, "negative value to convert into 'time_t'");
            if (TIMET_MAX < (uwideint_t)wi)
                rb_raise(rb_eRangeError, "too big to convert into 'time_t'");
        }
        else {
            if (wi < TIMET_MIN || TIMET_MAX < wi)
                rb_raise(rb_eRangeError, "too big to convert into 'time_t'");
        }
        return (time_t)wi;
    }
#endif
    return NUM2TIMET(w2v(w));
}
#define WV2TIMET(t) wv2timet(t)

VALUE rb_cTime;
static VALUE rb_cTimeTM;

static int obj2int(VALUE obj);
static uint32_t obj2ubits(VALUE obj, unsigned int bits);
static VALUE obj2vint(VALUE obj);
static uint32_t month_arg(VALUE arg);
static VALUE validate_utc_offset(VALUE utc_offset);
static VALUE validate_zone_name(VALUE zone_name);
static void validate_vtm(struct vtm *vtm);
static void vtm_add_day(struct vtm *vtm, int day);
static uint32_t obj2subsecx(VALUE obj, VALUE *subsecx);

static VALUE time_gmtime(VALUE);
static VALUE time_localtime(VALUE);
static VALUE time_fixoff(VALUE);
static VALUE time_zonelocal(VALUE time, VALUE off);

static time_t timegm_noleapsecond(struct tm *tm);
static int tmcmp(struct tm *a, struct tm *b);
static int vtmcmp(struct vtm *a, struct vtm *b);
static const char *find_time_t(struct tm *tptr, int utc_p, time_t *tp);

static struct vtm *localtimew(wideval_t timew, struct vtm *result);

static int leap_year_p(long y);
#define leap_year_v_p(y) leap_year_p(NUM2LONG(modv((y), INT2FIX(400))))

static VALUE tm_from_time(VALUE klass, VALUE time);

bool ruby_tz_uptodate_p;

#ifdef _WIN32
enum {tzkey_max = numberof(((DYNAMIC_TIME_ZONE_INFORMATION *)NULL)->TimeZoneKeyName)};
static struct {
    char use_tzkey;
    char name[tzkey_max * 4 + 1];
} w32_tz;

static char *
get_tzname(int dst)
{
    if (w32_tz.use_tzkey) {
        if (w32_tz.name[0]) {
            return w32_tz.name;
        }
        else {
            /*
             * Use GetDynamicTimeZoneInformation::TimeZoneKeyName, Windows
             * time zone ID, which is not localized because it is the key
             * for "Dynamic DST" keys under the "Time Zones" registry.
             * Available since Windows Vista and Windows Server 2008.
             */
            DYNAMIC_TIME_ZONE_INFORMATION tzi;
            WCHAR *const wtzkey = tzi.TimeZoneKeyName;
            DWORD tzret = GetDynamicTimeZoneInformation(&tzi);
            if (tzret != TIME_ZONE_ID_INVALID && *wtzkey) {
                int wlen = (int)wcsnlen(wtzkey, tzkey_max);
                int clen = WideCharToMultiByte(CP_UTF8, 0, wtzkey, wlen,
                                               w32_tz.name, sizeof(w32_tz.name) - 1,
                                               NULL, NULL);
                w32_tz.name[clen] = '\0';
                return w32_tz.name;
            }
        }
    }
    return _tzname[_daylight && dst];
}
#endif

void
ruby_reset_timezone(const char *val)
{
    ruby_tz_uptodate_p = false;
#ifdef _WIN32
    w32_tz.use_tzkey = !val || !*val;
#endif
    ruby_reset_leap_second_info();
}

static void
update_tz(void)
{
    if (ruby_tz_uptodate_p) return;
    ruby_tz_uptodate_p = true;
    tzset();
}

static struct tm *
rb_localtime_r(const time_t *t, struct tm *result)
{
#if defined __APPLE__ && defined __LP64__
    if (*t != (time_t)(int)*t) return NULL;
#endif
    update_tz();
#ifdef HAVE_GMTIME_R
    result = localtime_r(t, result);
#else
    {
        struct tm *tmp = localtime(t);
        if (tmp) *result = *tmp;
    }
#endif
#if defined(HAVE_MKTIME) && defined(LOCALTIME_OVERFLOW_PROBLEM)
    if (result) {
        long gmtoff1 = 0;
        long gmtoff2 = 0;
        struct tm tmp = *result;
        time_t t2;
        t2 = mktime(&tmp);
#  if defined(HAVE_STRUCT_TM_TM_GMTOFF)
        gmtoff1 = result->tm_gmtoff;
        gmtoff2 = tmp.tm_gmtoff;
#  endif
        if (*t + gmtoff1 != t2 + gmtoff2)
            result = NULL;
    }
#endif
    return result;
}
#define LOCALTIME(tm, result) rb_localtime_r((tm), &(result))

#ifndef HAVE_STRUCT_TM_TM_GMTOFF
static struct tm *
rb_gmtime_r(const time_t *t, struct tm *result)
{
#ifdef HAVE_GMTIME_R
    result = gmtime_r(t, result);
#else
    struct tm *tmp = gmtime(t);
    if (tmp) *result = *tmp;
#endif
#if defined(HAVE_TIMEGM) && defined(LOCALTIME_OVERFLOW_PROBLEM)
    if (result && *t != timegm(result)) {
        return NULL;
    }
#endif
    return result;
}
#   define GMTIME(tm, result) rb_gmtime_r((tm), &(result))
#endif

static const int16_t common_year_yday_offset[] = {
    -1,
    -1 + 31,
    -1 + 31 + 28,
    -1 + 31 + 28 + 31,
    -1 + 31 + 28 + 31 + 30,
    -1 + 31 + 28 + 31 + 30 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30
      /* 1    2    3    4    5    6    7    8    9    10   11 */
};
static const int16_t leap_year_yday_offset[] = {
    -1,
    -1 + 31,
    -1 + 31 + 29,
    -1 + 31 + 29 + 31,
    -1 + 31 + 29 + 31 + 30,
    -1 + 31 + 29 + 31 + 30 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30
      /* 1    2    3    4    5    6    7    8    9    10   11 */
};

static const int8_t common_year_days_in_month[] = {
    31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};
static const int8_t leap_year_days_in_month[] = {
    31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

#define days_in_month_of(leap) ((leap) ? leap_year_days_in_month : common_year_days_in_month)
#define days_in_month_in(y) days_in_month_of(leap_year_p(y))
#define days_in_month_in_v(y) days_in_month_of(leap_year_v_p(y))

#define M28(m) \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m)
#define M29(m) \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m)
#define M30(m) \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m)
#define M31(m) \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), \
    (m),(m),(m),(m),(m),(m),(m),(m),(m),(m), (m)

static const uint8_t common_year_mon_of_yday[] = {
    M31(1), M28(2), M31(3), M30(4), M31(5), M30(6),
    M31(7), M31(8), M30(9), M31(10), M30(11), M31(12)
};
static const uint8_t leap_year_mon_of_yday[] = {
    M31(1), M29(2), M31(3), M30(4), M31(5), M30(6),
    M31(7), M31(8), M30(9), M31(10), M30(11), M31(12)
};

#undef M28
#undef M29
#undef M30
#undef M31

#define D28 \
    1,2,3,4,5,6,7,8,9, \
    10,11,12,13,14,15,16,17,18,19, \
    20,21,22,23,24,25,26,27,28
#define D29 \
    1,2,3,4,5,6,7,8,9, \
    10,11,12,13,14,15,16,17,18,19, \
    20,21,22,23,24,25,26,27,28,29
#define D30 \
    1,2,3,4,5,6,7,8,9, \
    10,11,12,13,14,15,16,17,18,19, \
    20,21,22,23,24,25,26,27,28,29,30
#define D31 \
    1,2,3,4,5,6,7,8,9, \
    10,11,12,13,14,15,16,17,18,19, \
    20,21,22,23,24,25,26,27,28,29,30,31

static const uint8_t common_year_mday_of_yday[] = {
  /*  1    2    3    4    5    6    7    8    9   10   11   12 */
    D31, D28, D31, D30, D31, D30, D31, D31, D30, D31, D30, D31
};
static const uint8_t leap_year_mday_of_yday[] = {
    D31, D29, D31, D30, D31, D30, D31, D31, D30, D31, D30, D31
};

#undef D28
#undef D29
#undef D30
#undef D31

static int
calc_tm_yday(long tm_year, int tm_mon, int tm_mday)
{
    int tm_year_mod400 = (int)MOD(tm_year, 400);
    int tm_yday = tm_mday;

    if (leap_year_p(tm_year_mod400 + 1900))
        tm_yday += leap_year_yday_offset[tm_mon];
    else
        tm_yday += common_year_yday_offset[tm_mon];

    return tm_yday;
}

static wideval_t
timegmw_noleapsecond(struct vtm *vtm)
{
    VALUE year1900;
    VALUE q400, r400;
    int year_mod400;
    int yday;
    long days_in400;
    VALUE vdays, ret;
    wideval_t wret;

    year1900 = subv(vtm->year, INT2FIX(1900));

    divmodv(year1900, INT2FIX(400), &q400, &r400);
    year_mod400 = NUM2INT(r400);

    yday = calc_tm_yday(year_mod400, vtm->mon-1, vtm->mday);

    /*
     *  `Seconds Since the Epoch' in SUSv3:
     *  tm_sec + tm_min*60 + tm_hour*3600 + tm_yday*86400 +
     *  (tm_year-70)*31536000 + ((tm_year-69)/4)*86400 -
     *  ((tm_year-1)/100)*86400 + ((tm_year+299)/400)*86400
     */
    ret = LONG2NUM(vtm->sec
                 + vtm->min*60
                 + vtm->hour*3600);
    days_in400 = yday
               - 70*365
               + DIV(year_mod400 - 69, 4)
               - DIV(year_mod400 - 1, 100)
               + (year_mod400 + 299) / 400;
    vdays = LONG2NUM(days_in400);
    vdays = addv(vdays, mulv(q400, INT2FIX(97)));
    vdays = addv(vdays, mulv(year1900, INT2FIX(365)));
    wret = wadd(rb_time_magnify(v2w(ret)), wmul(rb_time_magnify(v2w(vdays)), WINT2FIXWV(86400)));
    wret = wadd(wret, v2w(vtm->subsecx));

    return wret;
}

static VALUE
zone_str(const char *zone)
{
    const char *p;
    int ascii_only = 1;
    VALUE str;
    size_t len;

    if (zone == NULL) {
        return rb_fstring_lit("(NO-TIMEZONE-ABBREVIATION)");
    }

    for (p = zone; *p; p++) {
        if (!ISASCII(*p)) {
            ascii_only = 0;
            p += strlen(p);
            break;
        }
    }
    len = p - zone;
    if (ascii_only) {
        str = rb_usascii_str_new(zone, len);
    }
    else {
#ifdef _WIN32
        str = rb_utf8_str_new(zone, len);
        /* until we move to UTF-8 on Windows completely */
        str = rb_str_export_locale(str);
#else
        str = rb_enc_str_new(zone, len, rb_locale_encoding());
#endif
    }
    return rb_fstring(str);
}

static void
gmtimew_noleapsecond(wideval_t timew, struct vtm *vtm)
{
    VALUE v;
    int n, x, y;
    int wday;
    VALUE timev;
    wideval_t timew2, w, w2;
    VALUE subsecx;

    vtm->isdst = 0;

    split_second(timew, &timew2, &subsecx);
    vtm->subsecx = subsecx;

    wdivmod(timew2, WINT2FIXWV(86400), &w2, &w);
    timev = w2v(w2);
    v = w2v(w);

    wday = NUM2INT(modv(timev, INT2FIX(7)));
    vtm->wday = (wday + 4) % 7;

    n = NUM2INT(v);
    vtm->sec = n % 60; n = n / 60;
    vtm->min = n % 60; n = n / 60;
    vtm->hour = n;

    /* 97 leap days in the 400 year cycle */
    divmodv(timev, INT2FIX(400*365 + 97), &timev, &v);
    vtm->year = mulv(timev, INT2FIX(400));

    /* n is the days in the 400 year cycle.
     * the start of the cycle is 1970-01-01. */

    n = NUM2INT(v);
    y = 1970;

    /* 30 years including 7 leap days (1972, 1976, ... 1996),
     * 31 days in January 2000 and
     * 29 days in February 2000
     * from 1970-01-01 to 2000-02-29 */
    if (30*365+7+31+29-1 <= n) {
        /* 2000-02-29 or after */
        if (n < 31*365+8) {
            /* 2000-02-29 to 2000-12-31 */
            y += 30;
            n -= 30*365+7;
            goto found;
        }
        else {
            /* 2001-01-01 or after */
            n -= 1;
        }
    }

    x = n / (365*100 + 24);
    n = n % (365*100 + 24);
    y += x * 100;
    if (30*365+7+31+29-1 <= n) {
        if (n < 31*365+7) {
            y += 30;
            n -= 30*365+7;
            goto found;
        }
        else
            n += 1;
    }

    x = n / (365*4 + 1);
    n = n % (365*4 + 1);
    y += x * 4;
    if (365*2+31+29-1 <= n) {
        if (n < 365*2+366) {
            y += 2;
            n -= 365*2;
            goto found;
        }
        else
            n -= 1;
    }

    x = n / 365;
    n = n % 365;
    y += x;

  found:
    vtm->yday = n+1;
    vtm->year = addv(vtm->year, INT2NUM(y));

    if (leap_year_p(y)) {
        vtm->mon = leap_year_mon_of_yday[n];
        vtm->mday = leap_year_mday_of_yday[n];
    }
    else {
        vtm->mon = common_year_mon_of_yday[n];
        vtm->mday = common_year_mday_of_yday[n];
    }

    vtm->utc_offset = INT2FIX(0);
    vtm->zone = str_utc;
}

static struct tm *
gmtime_with_leapsecond(const time_t *timep, struct tm *result)
{
#if defined(HAVE_STRUCT_TM_TM_GMTOFF)
    /* 4.4BSD counts leap seconds only with localtime, not with gmtime. */
    struct tm *t;
    int sign;
    int gmtoff_sec, gmtoff_min, gmtoff_hour, gmtoff_day;
    long gmtoff;
    t = LOCALTIME(timep, *result);
    if (t == NULL)
        return NULL;

    /* subtract gmtoff */
    if (t->tm_gmtoff < 0) {
        sign = 1;
        gmtoff = -t->tm_gmtoff;
    }
    else {
        sign = -1;
        gmtoff = t->tm_gmtoff;
    }
    gmtoff_sec = (int)(gmtoff % 60);
    gmtoff = gmtoff / 60;
    gmtoff_min = (int)(gmtoff % 60);
    gmtoff = gmtoff / 60;
    gmtoff_hour = (int)gmtoff;	/* <= 12 */

    gmtoff_sec *= sign;
    gmtoff_min *= sign;
    gmtoff_hour *= sign;

    gmtoff_day = 0;

    if (gmtoff_sec) {
        /* If gmtoff_sec == 0, don't change result->tm_sec.
         * It may be 60 which is a leap second. */
        result->tm_sec += gmtoff_sec;
        if (result->tm_sec < 0) {
            result->tm_sec += 60;
            gmtoff_min -= 1;
        }
        if (60 <= result->tm_sec) {
            result->tm_sec -= 60;
            gmtoff_min += 1;
        }
    }
    if (gmtoff_min) {
        result->tm_min += gmtoff_min;
        if (result->tm_min < 0) {
            result->tm_min += 60;
            gmtoff_hour -= 1;
        }
        if (60 <= result->tm_min) {
            result->tm_min -= 60;
            gmtoff_hour += 1;
        }
    }
    if (gmtoff_hour) {
        result->tm_hour += gmtoff_hour;
        if (result->tm_hour < 0) {
            result->tm_hour += 24;
            gmtoff_day = -1;
        }
        if (24 <= result->tm_hour) {
            result->tm_hour -= 24;
            gmtoff_day = 1;
        }
    }

    if (gmtoff_day) {
        if (gmtoff_day < 0) {
            if (result->tm_yday == 0) {
                result->tm_mday = 31;
                result->tm_mon = 11; /* December */
                result->tm_year--;
                result->tm_yday = leap_year_p(result->tm_year + 1900) ? 365 : 364;
            }
            else if (result->tm_mday == 1) {
                const int8_t *days_in_month = days_in_month_in(result->tm_year + 1900);
                result->tm_mon--;
                result->tm_mday = days_in_month[result->tm_mon];
                result->tm_yday--;
            }
            else {
                result->tm_mday--;
                result->tm_yday--;
            }
            result->tm_wday = (result->tm_wday + 6) % 7;
        }
        else {
            int leap = leap_year_p(result->tm_year + 1900);
            if (result->tm_yday == (leap ? 365 : 364)) {
                result->tm_year++;
                result->tm_mon = 0; /* January */
                result->tm_mday = 1;
                result->tm_yday = 0;
            }
            else if (result->tm_mday == days_in_month_of(leap)[result->tm_mon]) {
                result->tm_mon++;
                result->tm_mday = 1;
                result->tm_yday++;
            }
            else {
                result->tm_mday++;
                result->tm_yday++;
            }
            result->tm_wday = (result->tm_wday + 1) % 7;
        }
    }
    result->tm_isdst = 0;
    result->tm_gmtoff = 0;
#if defined(HAVE_TM_ZONE)
    result->tm_zone = (char *)"UTC";
#endif
    return result;
#else
    return GMTIME(timep, *result);
#endif
}

static long this_year = 0;
static time_t known_leap_seconds_limit;
static int number_of_leap_seconds_known;

static void
init_leap_second_info(void)
{
    /*
     * leap seconds are determined by IERS.
     * It is announced 6 months before the leap second.
     * So no one knows leap seconds in the future after the next year.
     */
    if (this_year == 0) {
        time_t now;
        struct tm *tm, result;
        struct vtm vtm;
        wideval_t timew;
        now = time(NULL);
#ifdef HAVE_GMTIME_R
        gmtime_r(&now, &result);
#else
        gmtime(&now);
#endif
        tm = gmtime_with_leapsecond(&now, &result);
        if (!tm) return;
        this_year = tm->tm_year;

        if (TIMET_MAX - now < (time_t)(366*86400))
            known_leap_seconds_limit = TIMET_MAX;
        else
            known_leap_seconds_limit = now + (time_t)(366*86400);

        if (!gmtime_with_leapsecond(&known_leap_seconds_limit, &result))
            return;

        vtm.year = LONG2NUM(result.tm_year + 1900);
        vtm.mon = result.tm_mon + 1;
        vtm.mday = result.tm_mday;
        vtm.hour = result.tm_hour;
        vtm.min = result.tm_min;
        vtm.sec = result.tm_sec;
        vtm.subsecx = INT2FIX(0);
        vtm.utc_offset = INT2FIX(0);

        timew = timegmw_noleapsecond(&vtm);

        number_of_leap_seconds_known = NUM2INT(w2v(wsub(TIMET2WV(known_leap_seconds_limit), rb_time_unmagnify(timew))));
    }
}

/* Use this if you want to re-run init_leap_second_info() */
void
ruby_reset_leap_second_info(void)
{
    this_year = 0;
}

static wideval_t
timegmw(struct vtm *vtm)
{
    wideval_t timew;
    struct tm tm;
    time_t t;
    const char *errmsg;

    /* The first leap second is 1972-06-30 23:59:60 UTC.
     * No leap seconds before. */
    if (gt(INT2FIX(1972), vtm->year))
        return timegmw_noleapsecond(vtm);

    init_leap_second_info();

    timew = timegmw_noleapsecond(vtm);


    if (number_of_leap_seconds_known == 0) {
        /* When init_leap_second_info() is executed, the timezone doesn't have
         * leap second information. Disable leap second for calculating gmtime.
         */
        return timew;
    }
    else if (wlt(rb_time_magnify(TIMET2WV(known_leap_seconds_limit)), timew)) {
        return wadd(timew, rb_time_magnify(WINT2WV(number_of_leap_seconds_known)));
    }

    tm.tm_year = rb_long2int(NUM2LONG(vtm->year) - 1900);
    tm.tm_mon = vtm->mon - 1;
    tm.tm_mday = vtm->mday;
    tm.tm_hour = vtm->hour;
    tm.tm_min = vtm->min;
    tm.tm_sec = vtm->sec;
    tm.tm_isdst = 0;

    errmsg = find_time_t(&tm, 1, &t);
    if (errmsg)
        rb_raise(rb_eArgError, "%s", errmsg);
    return wadd(rb_time_magnify(TIMET2WV(t)), v2w(vtm->subsecx));
}

static struct vtm *
gmtimew(wideval_t timew, struct vtm *result)
{
    time_t t;
    struct tm tm;
    VALUE subsecx;
    wideval_t timew2;

    if (wlt(timew, WINT2FIXWV(0))) {
        gmtimew_noleapsecond(timew, result);
        return result;
    }

    init_leap_second_info();

    if (number_of_leap_seconds_known == 0) {
        /* When init_leap_second_info() is executed, the timezone doesn't have
         * leap second information. Disable leap second for calculating gmtime.
         */
        gmtimew_noleapsecond(timew, result);
        return result;
    }
    else if (wlt(rb_time_magnify(TIMET2WV(known_leap_seconds_limit)), timew)) {
        timew = wsub(timew, rb_time_magnify(WINT2WV(number_of_leap_seconds_known)));
        gmtimew_noleapsecond(timew, result);
        return result;
    }

    split_second(timew, &timew2, &subsecx);

    t = WV2TIMET(timew2);
    if (!gmtime_with_leapsecond(&t, &tm))
        return NULL;

    result->year = LONG2NUM((long)tm.tm_year + 1900);
    result->mon = tm.tm_mon + 1;
    result->mday = tm.tm_mday;
    result->hour = tm.tm_hour;
    result->min = tm.tm_min;
    result->sec = tm.tm_sec;
    result->subsecx = subsecx;
    result->utc_offset = INT2FIX(0);
    result->wday = tm.tm_wday;
    result->yday = tm.tm_yday+1;
    result->isdst = tm.tm_isdst;

    return result;
}

#define GMTIMEW(w, v) \
    (gmtimew(w, v) ? (void)0 : rb_raise(rb_eArgError, "gmtime error"))

static struct tm *localtime_with_gmtoff_zone(const time_t *t, struct tm *result, long *gmtoff, VALUE *zone);

/*
 * The idea, extrapolate localtime() function, is borrowed from Perl:
 * http://web.archive.org/web/20080211114141/http://use.perl.org/articles/08/02/07/197204.shtml
 *
 * compat_common_month_table is generated by the following program.
 * This table finds the last month which starts at the same day of a week.
 * The year 2037 is not used because:
 * https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=522949
 *
 *  #!/usr/bin/ruby
 *
 *  require 'date'
 *
 *  h = {}
 *  2036.downto(2010) {|y|
 *    1.upto(12) {|m|
 *      next if m == 2 && y % 4 == 0
 *      d = Date.new(y,m,1)
 *      h[m] ||= {}
 *      h[m][d.wday] ||= y
 *    }
 *  }
 *
 *  1.upto(12) {|m|
 *    print "{"
 *    0.upto(6) {|w|
 *      y = h[m][w]
 *      print " #{y},"
 *    }
 *    puts "},"
 *  }
 *
 */
static const int compat_common_month_table[12][7] = {
  /* Sun   Mon   Tue   Wed   Thu   Fri   Sat */
  { 2034, 2035, 2036, 2031, 2032, 2027, 2033 }, /* January */
  { 2026, 2027, 2033, 2034, 2035, 2030, 2031 }, /* February */
  { 2026, 2032, 2033, 2034, 2035, 2030, 2036 }, /* March */
  { 2035, 2030, 2036, 2026, 2032, 2033, 2034 }, /* April */
  { 2033, 2034, 2035, 2030, 2036, 2026, 2032 }, /* May */
  { 2036, 2026, 2032, 2033, 2034, 2035, 2030 }, /* June */
  { 2035, 2030, 2036, 2026, 2032, 2033, 2034 }, /* July */
  { 2032, 2033, 2034, 2035, 2030, 2036, 2026 }, /* August */
  { 2030, 2036, 2026, 2032, 2033, 2034, 2035 }, /* September */
  { 2034, 2035, 2030, 2036, 2026, 2032, 2033 }, /* October */
  { 2026, 2032, 2033, 2034, 2035, 2030, 2036 }, /* November */
  { 2030, 2036, 2026, 2032, 2033, 2034, 2035 }, /* December */
};

/*
 * compat_leap_month_table is generated by following program.
 *
 *  #!/usr/bin/ruby
 *
 *  require 'date'
 *
 *  h = {}
 *  2037.downto(2010) {|y|
 *    1.upto(12) {|m|
 *      next unless m == 2 && y % 4 == 0
 *      d = Date.new(y,m,1)
 *      h[m] ||= {}
 *      h[m][d.wday] ||= y
 *    }
 *  }
 *
 *  2.upto(2) {|m|
 *    0.upto(6) {|w|
 *      y = h[m][w]
 *      print " #{y},"
 *    }
 *    puts
 *  }
 */
static const int compat_leap_month_table[7] = {
/* Sun   Mon   Tue   Wed   Thu   Fri   Sat */
  2032, 2016, 2028, 2012, 2024, 2036, 2020, /* February */
};

static int
calc_wday(int year_mod400, int month, int day)
{
    int a, y, m;
    int wday;

    a = (14 - month) / 12;
    y = year_mod400 + 4800 - a;
    m = month + 12 * a - 3;
    wday = day + (153*m+2)/5 + 365*y + y/4 - y/100 + y/400 + 2;
    wday = wday % 7;
    return wday;
}

static VALUE
guess_local_offset(struct vtm *vtm_utc, int *isdst_ret, VALUE *zone_ret)
{
    struct tm tm;
    long gmtoff;
    VALUE zone;
    time_t t;
    struct vtm vtm2;
    VALUE timev;
    int year_mod400, wday;

    /* Daylight Saving Time was introduced in 1916.
     * So we don't need to care about DST before that. */
    if (lt(vtm_utc->year, INT2FIX(1916))) {
        VALUE off = INT2FIX(0);
        int isdst = 0;
        zone = str_utc;

# if defined(NEGATIVE_TIME_T)
#  if SIZEOF_TIME_T <= 4
    /* 1901-12-13 20:45:52 UTC : The oldest time in 32-bit signed time_t. */
#   define THE_TIME_OLD_ENOUGH ((time_t)0x80000000)
#  else
    /* Since the Royal Greenwich Observatory was commissioned in 1675,
       no timezone defined using GMT at 1600. */
#   define THE_TIME_OLD_ENOUGH ((time_t)(1600-1970)*366*24*60*60)
#  endif
        if (localtime_with_gmtoff_zone((t = THE_TIME_OLD_ENOUGH, &t), &tm, &gmtoff, &zone)) {
            off = LONG2FIX(gmtoff);
            isdst = tm.tm_isdst;
        }
        else
# endif
        /* 1970-01-01 00:00:00 UTC : The Unix epoch - the oldest time in portable time_t. */
        if (localtime_with_gmtoff_zone((t = 0, &t), &tm, &gmtoff, &zone)) {
            off = LONG2FIX(gmtoff);
            isdst = tm.tm_isdst;
        }

        if (isdst_ret)
            *isdst_ret = isdst;
        if (zone_ret)
            *zone_ret = zone;
        return off;
    }

    /* It is difficult to guess the future. */

    vtm2 = *vtm_utc;

    /* guess using a year before 2038. */
    year_mod400 = NUM2INT(modv(vtm_utc->year, INT2FIX(400)));
    wday = calc_wday(year_mod400, vtm_utc->mon, 1);
    if (vtm_utc->mon == 2 && leap_year_p(year_mod400))
        vtm2.year = INT2FIX(compat_leap_month_table[wday]);
    else
        vtm2.year = INT2FIX(compat_common_month_table[vtm_utc->mon-1][wday]);

    timev = w2v(rb_time_unmagnify(timegmw(&vtm2)));
    t = NUM2TIMET(timev);
    zone = str_utc;
    if (localtime_with_gmtoff_zone(&t, &tm, &gmtoff, &zone)) {
        if (isdst_ret)
            *isdst_ret = tm.tm_isdst;
        if (zone_ret)
            *zone_ret = zone;
        return LONG2FIX(gmtoff);
    }

    {
        /* Use the current time offset as a last resort. */
        static time_t now = 0;
        static long now_gmtoff = 0;
        static int now_isdst = 0;
        static VALUE now_zone;
        if (now == 0) {
            VALUE zone;
            now = time(NULL);
            localtime_with_gmtoff_zone(&now, &tm, &now_gmtoff, &zone);
            now_isdst = tm.tm_isdst;
            zone = rb_fstring(zone);
            rb_vm_register_global_object(zone);
            now_zone = zone;
        }
        if (isdst_ret)
            *isdst_ret = now_isdst;
        if (zone_ret)
            *zone_ret = now_zone;
        return LONG2FIX(now_gmtoff);
    }
}

static VALUE
small_vtm_sub(struct vtm *vtm1, struct vtm *vtm2)
{
    int off;

    off = vtm1->sec - vtm2->sec;
    off += (vtm1->min - vtm2->min) * 60;
    off += (vtm1->hour - vtm2->hour) * 3600;
    if (ne(vtm1->year, vtm2->year))
        off += lt(vtm1->year, vtm2->year) ? -24*3600 : 24*3600;
    else if (vtm1->mon != vtm2->mon)
        off += vtm1->mon < vtm2->mon ? -24*3600 : 24*3600;
    else if (vtm1->mday != vtm2->mday)
        off += vtm1->mday < vtm2->mday ? -24*3600 : 24*3600;

    return INT2FIX(off);
}

static wideval_t
timelocalw(struct vtm *vtm)
{
    time_t t;
    struct tm tm;
    VALUE v;
    wideval_t timew1, timew2;
    struct vtm vtm1, vtm2;
    int n;

    if (FIXNUM_P(vtm->year)) {
        long l = FIX2LONG(vtm->year) - 1900;
        if (l < INT_MIN || INT_MAX < l)
            goto no_localtime;
        tm.tm_year = (int)l;
    }
    else {
        v = subv(vtm->year, INT2FIX(1900));
        if (lt(v, INT2NUM(INT_MIN)) || lt(INT2NUM(INT_MAX), v))
            goto no_localtime;
        tm.tm_year = NUM2INT(v);
    }

    tm.tm_mon = vtm->mon-1;
    tm.tm_mday = vtm->mday;
    tm.tm_hour = vtm->hour;
    tm.tm_min = vtm->min;
    tm.tm_sec = vtm->sec;
    tm.tm_isdst = vtm->isdst == VTM_ISDST_INITVAL ? -1 : vtm->isdst;

    if (find_time_t(&tm, 0, &t))
        goto no_localtime;
    return wadd(rb_time_magnify(TIMET2WV(t)), v2w(vtm->subsecx));

  no_localtime:
    timew1 = timegmw(vtm);

    if (!localtimew(timew1, &vtm1))
        rb_raise(rb_eArgError, "localtimew error");

    n = vtmcmp(vtm, &vtm1);
    if (n == 0) {
        timew1 = wsub(timew1, rb_time_magnify(WINT2FIXWV(12*3600)));
        if (!localtimew(timew1, &vtm1))
            rb_raise(rb_eArgError, "localtimew error");
        n = 1;
    }

    if (n < 0) {
        timew2 = timew1;
        vtm2 = vtm1;
        timew1 = wsub(timew1, rb_time_magnify(WINT2FIXWV(24*3600)));
        if (!localtimew(timew1, &vtm1))
            rb_raise(rb_eArgError, "localtimew error");
    }
    else {
        timew2 = wadd(timew1, rb_time_magnify(WINT2FIXWV(24*3600)));
        if (!localtimew(timew2, &vtm2))
            rb_raise(rb_eArgError, "localtimew error");
    }
    timew1 = wadd(timew1, rb_time_magnify(v2w(small_vtm_sub(vtm, &vtm1))));
    timew2 = wadd(timew2, rb_time_magnify(v2w(small_vtm_sub(vtm, &vtm2))));

    if (weq(timew1, timew2))
        return timew1;

    if (!localtimew(timew1, &vtm1))
        rb_raise(rb_eArgError, "localtimew error");
    if (vtm->hour != vtm1.hour || vtm->min != vtm1.min || vtm->sec != vtm1.sec)
        return timew2;

    if (!localtimew(timew2, &vtm2))
        rb_raise(rb_eArgError, "localtimew error");
    if (vtm->hour != vtm2.hour || vtm->min != vtm2.min || vtm->sec != vtm2.sec)
        return timew1;

    if (vtm->isdst)
        return lt(vtm1.utc_offset, vtm2.utc_offset) ? timew2 : timew1;
    else
        return lt(vtm1.utc_offset, vtm2.utc_offset) ? timew1 : timew2;
}

static struct tm *
localtime_with_gmtoff_zone(const time_t *t, struct tm *result, long *gmtoff, VALUE *zone)
{
    struct tm tm;

    if (LOCALTIME(t, tm)) {
#if defined(HAVE_STRUCT_TM_TM_GMTOFF)
        *gmtoff = tm.tm_gmtoff;
#else
        struct tm *u, *l;
        long off;
        struct tm tmbuf;
        l = &tm;
        u = GMTIME(t, tmbuf);
        if (!u)
            return NULL;
        if (l->tm_year != u->tm_year)
            off = l->tm_year < u->tm_year ? -1 : 1;
        else if (l->tm_mon != u->tm_mon)
            off = l->tm_mon < u->tm_mon ? -1 : 1;
        else if (l->tm_mday != u->tm_mday)
            off = l->tm_mday < u->tm_mday ? -1 : 1;
        else
            off = 0;
        off = off * 24 + l->tm_hour - u->tm_hour;
        off = off * 60 + l->tm_min - u->tm_min;
        off = off * 60 + l->tm_sec - u->tm_sec;
        *gmtoff = off;
#endif

        if (zone) {
#if defined(HAVE_TM_ZONE)
            *zone = zone_str(tm.tm_zone);
#elif defined(_WIN32)
            *zone = zone_str(get_tzname(tm.tm_isdst));
#elif defined(HAVE_TZNAME) && defined(HAVE_DAYLIGHT)
            /* this needs tzset or localtime, instead of localtime_r */
            *zone = zone_str(tzname[daylight && tm.tm_isdst]);
#else
            {
                char buf[64];
                strftime(buf, sizeof(buf), "%Z", &tm);
                *zone = zone_str(buf);
            }
#endif
        }

        *result = tm;
        return result;
    }
    return NULL;
}

static int
timew_out_of_timet_range(wideval_t timew)
{
    VALUE timexv;
#if WIDEVALUE_IS_WIDER && SIZEOF_TIME_T < SIZEOF_INT64_T
    if (FIXWV_P(timew)) {
        wideint_t t = FIXWV2WINT(timew);
        if (t < TIME_SCALE * (wideint_t)TIMET_MIN ||
            TIME_SCALE * (1 + (wideint_t)TIMET_MAX) <= t)
            return 1;
        return 0;
    }
#endif
#if SIZEOF_TIME_T == SIZEOF_INT64_T
    if (FIXWV_P(timew)) {
        wideint_t t = FIXWV2WINT(timew);
        if (~(time_t)0 <= 0) {
            return 0;
        }
        else {
            if (t < 0)
                return 1;
            return 0;
        }
    }
#endif
    timexv = w2v(timew);
    if (lt(timexv, mulv(INT2FIX(TIME_SCALE), TIMET2NUM(TIMET_MIN))) ||
        le(mulv(INT2FIX(TIME_SCALE), addv(TIMET2NUM(TIMET_MAX), INT2FIX(1))), timexv))
        return 1;
    return 0;
}

static struct vtm *
localtimew(wideval_t timew, struct vtm *result)
{
    VALUE subsecx, offset;
    VALUE zone;
    int isdst;

    if (!timew_out_of_timet_range(timew)) {
        time_t t;
        struct tm tm;
        long gmtoff;
        wideval_t timew2;

        split_second(timew, &timew2, &subsecx);

        t = WV2TIMET(timew2);

        if (localtime_with_gmtoff_zone(&t, &tm, &gmtoff, &zone)) {
            result->year = LONG2NUM((long)tm.tm_year + 1900);
            result->mon = tm.tm_mon + 1;
            result->mday = tm.tm_mday;
            result->hour = tm.tm_hour;
            result->min = tm.tm_min;
            result->sec = tm.tm_sec;
            result->subsecx = subsecx;
            result->wday = tm.tm_wday;
            result->yday = tm.tm_yday+1;
            result->isdst = tm.tm_isdst;
            result->utc_offset = LONG2NUM(gmtoff);
            result->zone = zone;
            return result;
        }
    }

    if (!gmtimew(timew, result))
        return NULL;

    offset = guess_local_offset(result, &isdst, &zone);

    if (!gmtimew(wadd(timew, rb_time_magnify(v2w(offset))), result))
        return NULL;

    result->utc_offset = offset;
    result->isdst = isdst;
    result->zone = zone;

    return result;
}

#define TIME_TZMODE_LOCALTIME 0
#define TIME_TZMODE_UTC 1
#define TIME_TZMODE_FIXOFF 2
#define TIME_TZMODE_UNINITIALIZED 3

struct time_object {
    wideval_t timew; /* time_t value * TIME_SCALE.  possibly Rational. */
    struct vtm vtm;
};

#define GetTimeval(obj, tobj) ((tobj) = get_timeval(obj))
#define GetNewTimeval(obj, tobj) ((tobj) = get_new_timeval(obj))

#define IsTimeval(obj) rb_typeddata_is_kind_of((obj), &time_data_type)
#define TIME_INIT_P(tobj) ((tobj)->vtm.tzmode != TIME_TZMODE_UNINITIALIZED)

#define TZMODE_UTC_P(tobj) ((tobj)->vtm.tzmode == TIME_TZMODE_UTC)
#define TZMODE_SET_UTC(tobj) ((tobj)->vtm.tzmode = TIME_TZMODE_UTC)

#define TZMODE_LOCALTIME_P(tobj) ((tobj)->vtm.tzmode == TIME_TZMODE_LOCALTIME)
#define TZMODE_SET_LOCALTIME(tobj) ((tobj)->vtm.tzmode = TIME_TZMODE_LOCALTIME)

#define TZMODE_FIXOFF_P(tobj) ((tobj)->vtm.tzmode == TIME_TZMODE_FIXOFF)
#define TZMODE_SET_FIXOFF(time, tobj, off) do { \
    (tobj)->vtm.tzmode = TIME_TZMODE_FIXOFF; \
    RB_OBJ_WRITE_UNALIGNED(time, &(tobj)->vtm.utc_offset, off); \
} while (0)

#define TZMODE_COPY(tobj1, tobj2) \
    ((tobj1)->vtm.tzmode = (tobj2)->vtm.tzmode, \
     (tobj1)->vtm.utc_offset = (tobj2)->vtm.utc_offset, \
     (tobj1)->vtm.zone = (tobj2)->vtm.zone)

static int zone_localtime(VALUE zone, VALUE time);
static VALUE time_get_tm(VALUE, struct time_object *);
#define MAKE_TM(time, tobj) \
  do { \
    if ((tobj)->vtm.tm_got == 0) { \
        time_get_tm((time), (tobj)); \
    } \
  } while (0)
#define MAKE_TM_ENSURE(time, tobj, cond) \
    do { \
        MAKE_TM(time, tobj); \
        if (!(cond)) { \
            force_make_tm(time, tobj); \
        } \
    } while (0)

static void
time_set_timew(VALUE time, struct time_object *tobj, wideval_t timew)
{
    tobj->timew = timew;
    if (!FIXWV_P(timew)) {
        RB_OBJ_WRITTEN(time, Qnil, w2v(timew));
    }
}

static void
time_set_vtm(VALUE time, struct time_object *tobj, struct vtm vtm)
{
    tobj->vtm = vtm;

    RB_OBJ_WRITTEN(time, Qnil, tobj->vtm.year);
    RB_OBJ_WRITTEN(time, Qnil, tobj->vtm.subsecx);
    RB_OBJ_WRITTEN(time, Qnil, tobj->vtm.utc_offset);
    RB_OBJ_WRITTEN(time, Qnil, tobj->vtm.zone);
}

static inline void
force_make_tm(VALUE time, struct time_object *tobj)
{
    VALUE zone = tobj->vtm.zone;
    if (!NIL_P(zone) && zone != str_empty && zone != str_utc) {
        if (zone_localtime(zone, time)) return;
    }
    tobj->vtm.tm_got = 0;
    time_get_tm(time, tobj);
}

static void
time_mark(void *ptr)
{
    struct time_object *tobj = ptr;
    if (!FIXWV_P(tobj->timew)) {
        rb_gc_mark_movable(w2v(tobj->timew));
    }
    rb_gc_mark_movable(tobj->vtm.year);
    rb_gc_mark_movable(tobj->vtm.subsecx);
    rb_gc_mark_movable(tobj->vtm.utc_offset);
    rb_gc_mark_movable(tobj->vtm.zone);
}

static void
time_compact(void *ptr)
{
    struct time_object *tobj = ptr;
    if (!FIXWV_P(tobj->timew)) {
        WIDEVAL_GET(tobj->timew) = WIDEVAL_WRAP(rb_gc_location(w2v(tobj->timew)));
    }

    tobj->vtm.year = rb_gc_location(tobj->vtm.year);
    tobj->vtm.subsecx = rb_gc_location(tobj->vtm.subsecx);
    tobj->vtm.utc_offset = rb_gc_location(tobj->vtm.utc_offset);
    tobj->vtm.zone = rb_gc_location(tobj->vtm.zone);
}

static const rb_data_type_t time_data_type = {
    .wrap_struct_name = "time",
    .function = {
        .dmark = time_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE,
        .dsize = NULL,
        .dcompact = time_compact,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_FROZEN_SHAREABLE | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE,
};

static VALUE
time_s_alloc(VALUE klass)
{
    VALUE obj;
    struct time_object *tobj;

    obj = TypedData_Make_Struct(klass, struct time_object, &time_data_type, tobj);
    tobj->vtm.tzmode = TIME_TZMODE_UNINITIALIZED;
    tobj->vtm.tm_got = 0;
    time_set_timew(obj, tobj, WINT2FIXWV(0));
    tobj->vtm.zone = Qnil;

    return obj;
}

static struct time_object *
get_timeval(VALUE obj)
{
    struct time_object *tobj;
    TypedData_Get_Struct(obj, struct time_object, &time_data_type, tobj);
    if (!TIME_INIT_P(tobj)) {
        rb_raise(rb_eTypeError, "uninitialized %"PRIsVALUE, rb_obj_class(obj));
    }
    return tobj;
}

static struct time_object *
get_new_timeval(VALUE obj)
{
    struct time_object *tobj;
    TypedData_Get_Struct(obj, struct time_object, &time_data_type, tobj);
    if (TIME_INIT_P(tobj)) {
        rb_raise(rb_eTypeError, "already initialized %"PRIsVALUE, rb_obj_class(obj));
    }
    return tobj;
}

static void
time_modify(VALUE time)
{
    rb_check_frozen(time);
}

static wideval_t
timenano2timew(wideint_t sec, long nsec)
{
    wideval_t timew;

    timew = rb_time_magnify(WINT2WV(sec));
    if (nsec)
        timew = wadd(timew, wmulquoll(WINT2WV(nsec), TIME_SCALE, 1000000000));
    return timew;
}

static struct timespec
timew2timespec(wideval_t timew)
{
    VALUE subsecx;
    struct timespec ts;
    wideval_t timew2;

    if (timew_out_of_timet_range(timew))
        rb_raise(rb_eArgError, "time out of system range");
    split_second(timew, &timew2, &subsecx);
    ts.tv_sec = WV2TIMET(timew2);
    ts.tv_nsec = NUM2LONG(mulquov(subsecx, INT2FIX(1000000000), INT2FIX(TIME_SCALE)));
    return ts;
}

static struct timespec *
timew2timespec_exact(wideval_t timew, struct timespec *ts)
{
    VALUE subsecx;
    wideval_t timew2;
    VALUE nsecv;

    if (timew_out_of_timet_range(timew))
        return NULL;
    split_second(timew, &timew2, &subsecx);
    ts->tv_sec = WV2TIMET(timew2);
    nsecv = mulquov(subsecx, INT2FIX(1000000000), INT2FIX(TIME_SCALE));
    if (!FIXNUM_P(nsecv))
        return NULL;
    ts->tv_nsec = NUM2LONG(nsecv);
    return ts;
}

void
rb_timespec_now(struct timespec *ts)
{
#ifdef HAVE_CLOCK_GETTIME
    if (clock_gettime(CLOCK_REALTIME, ts) == -1) {
        rb_sys_fail("clock_gettime");
    }
#else
    {
        struct timeval tv;
        if (gettimeofday(&tv, 0) < 0) {
            rb_sys_fail("gettimeofday");
        }
        ts->tv_sec = tv.tv_sec;
        ts->tv_nsec = tv.tv_usec * 1000;
    }
#endif
}

/*
 * Sets the current time information into _time_.
 * Returns _time_.
 */
static VALUE
time_init_now(rb_execution_context_t *ec, VALUE time, VALUE zone)
{
    struct time_object *tobj;
    struct timespec ts;

    time_modify(time);
    GetNewTimeval(time, tobj);
    TZMODE_SET_LOCALTIME(tobj);
    tobj->vtm.tm_got=0;
    rb_timespec_now(&ts);
    time_set_timew(time, tobj, timenano2timew(ts.tv_sec, ts.tv_nsec));

    if (!NIL_P(zone)) {
        time_zonelocal(time, zone);
    }
    return time;
}

static VALUE
time_s_now(rb_execution_context_t *ec, VALUE klass, VALUE zone)
{
    VALUE t = time_s_alloc(klass);
    return time_init_now(ec, t, zone);
}

static VALUE
time_set_utc_offset(VALUE time, VALUE off)
{
    struct time_object *tobj;
    off = num_exact(off);

    time_modify(time);
    GetTimeval(time, tobj);

    tobj->vtm.tm_got = 0;
    tobj->vtm.zone = Qnil;
    TZMODE_SET_FIXOFF(time, tobj, off);

    return time;
}

static void
vtm_add_offset(struct vtm *vtm, VALUE off, int sign)
{
    VALUE subsec, v;
    int sec, min, hour;
    int day;

    if (lt(off, INT2FIX(0))) {
        sign = -sign;
        off = neg(off);
    }
    divmodv(off, INT2FIX(1), &off, &subsec);
    divmodv(off, INT2FIX(60), &off, &v);
    sec = NUM2INT(v);
    divmodv(off, INT2FIX(60), &off, &v);
    min = NUM2INT(v);
    divmodv(off, INT2FIX(24), &off, &v);
    hour = NUM2INT(v);

    if (sign < 0) {
        subsec = neg(subsec);
        sec = -sec;
        min = -min;
        hour = -hour;
    }

    day = 0;

    if (!rb_equal(subsec, INT2FIX(0))) {
        vtm->subsecx = addv(vtm->subsecx, w2v(rb_time_magnify(v2w(subsec))));
        if (lt(vtm->subsecx, INT2FIX(0))) {
            vtm->subsecx = addv(vtm->subsecx, INT2FIX(TIME_SCALE));
            sec -= 1;
        }
        if (le(INT2FIX(TIME_SCALE), vtm->subsecx)) {
            vtm->subsecx = subv(vtm->subsecx, INT2FIX(TIME_SCALE));
            sec += 1;
        }
    }
    if (sec) {
        /* If sec + subsec == 0, don't change vtm->sec.
         * It may be 60 which is a leap second. */
        sec += vtm->sec;
        if (sec < 0) {
            sec += 60;
            min -= 1;
        }
        if (60 <= sec) {
            sec -= 60;
            min += 1;
        }
        vtm->sec = sec;
    }
    if (min) {
        min += vtm->min;
        if (min < 0) {
            min += 60;
            hour -= 1;
        }
        if (60 <= min) {
            min -= 60;
            hour += 1;
        }
        vtm->min = min;
    }
    if (hour) {
        hour += vtm->hour;
        if (hour < 0) {
            hour += 24;
            day = -1;
        }
        if (24 <= hour) {
            hour -= 24;
            day = 1;
        }
        vtm->hour = hour;
    }

    vtm_add_day(vtm, day);
}

static void
vtm_add_day(struct vtm *vtm, int day)
{
    if (day) {
        if (day < 0) {
            if (vtm->mon == 1 && vtm->mday == 1) {
                vtm->mday = 31;
                vtm->mon = 12; /* December */
                vtm->year = subv(vtm->year, INT2FIX(1));
                if (vtm->yday != 0)
                    vtm->yday = leap_year_v_p(vtm->year) ? 366 : 365;
            }
            else if (vtm->mday == 1) {
                const int8_t *days_in_month = days_in_month_in_v(vtm->year);
                vtm->mon--;
                vtm->mday = days_in_month[vtm->mon-1];
                if (vtm->yday != 0) vtm->yday--;
            }
            else {
                vtm->mday--;
                if (vtm->yday != 0) vtm->yday--;
            }
            if (vtm->wday != VTM_WDAY_INITVAL) vtm->wday = (vtm->wday + 6) % 7;
        }
        else {
            int leap = leap_year_v_p(vtm->year);
            if (vtm->mon == 12 && vtm->mday == 31) {
                vtm->year = addv(vtm->year, INT2FIX(1));
                vtm->mon = 1; /* January */
                vtm->mday = 1;
                vtm->yday = 1;
            }
            else if (vtm->mday == days_in_month_of(leap)[vtm->mon-1]) {
                vtm->mon++;
                vtm->mday = 1;
                if (vtm->yday != 0) vtm->yday++;
            }
            else {
                vtm->mday++;
                if (vtm->yday != 0) vtm->yday++;
            }
            if (vtm->wday != VTM_WDAY_INITVAL) vtm->wday = (vtm->wday + 1) % 7;
        }
    }
}

static int
maybe_tzobj_p(VALUE obj)
{
    if (NIL_P(obj)) return FALSE;
    if (RB_INTEGER_TYPE_P(obj)) return FALSE;
    if (RB_TYPE_P(obj, T_STRING)) return FALSE;
    return TRUE;
}

NORETURN(static void invalid_utc_offset(VALUE));
static void
invalid_utc_offset(VALUE zone)
{
    rb_raise(rb_eArgError, "\"+HH:MM\", \"-HH:MM\", \"UTC\" or "
             "\"A\"..\"I\",\"K\"..\"Z\" expected for utc_offset: %"PRIsVALUE,
             zone);
}

#define have_2digits(ptr) (ISDIGIT((ptr)[0]) && ISDIGIT((ptr)[1]))
#define num_from_2digits(ptr) ((ptr)[0] * 10 + (ptr)[1] - '0' * 11)

static VALUE
utc_offset_arg(VALUE arg)
{
    VALUE tmp;
    if (!NIL_P(tmp = rb_check_string_type(arg))) {
        int n = 0;
        const char *s = RSTRING_PTR(tmp), *min = NULL, *sec = NULL;
        if (!rb_enc_str_asciicompat_p(tmp)) {
            goto invalid_utc_offset;
        }
        switch (RSTRING_LEN(tmp)) {
          case 1:
            if (s[0] == 'Z') {
                return UTC_ZONE;
            }
            /* Military Time Zone Names */
            if (s[0] >= 'A' && s[0] <= 'I') {
                n = (int)s[0] - 'A' + 1;
            }
            /* No 'J' zone */
            else if (s[0] >= 'K' && s[0] <= 'M') {
                n = (int)s[0] - 'A';
            }
            else if (s[0] >= 'N' && s[0] <= 'Y') {
                n = 'M' - (int)s[0];
            }
            else {
                goto invalid_utc_offset;
            }
            n *= 3600;
            return INT2FIX(n);
          case 3:
            if (STRNCASECMP("UTC", s, 3) == 0) {
                return UTC_ZONE;
            }
            break; /* +HH */
          case 7: /* +HHMMSS */
            sec = s+5;
            /* fallthrough */
          case 5: /* +HHMM */
            min = s+3;
            break;
          case 9: /* +HH:MM:SS */
            if (s[6] != ':') goto invalid_utc_offset;
            sec = s+7;
            /* fallthrough */
          case 6: /* +HH:MM */
            if (s[3] != ':') goto invalid_utc_offset;
            min = s+4;
            break;
          default:
            goto invalid_utc_offset;
        }
        if (sec) {
            if (!have_2digits(sec)) goto invalid_utc_offset;
            if (sec[0] > '5') goto invalid_utc_offset;
            n += num_from_2digits(sec);
            ASSUME(min);
        }
        if (min) {
            if (!have_2digits(min)) goto invalid_utc_offset;
            if (min[0] > '5') goto invalid_utc_offset;
            n += num_from_2digits(min) * 60;
        }
        if (s[0] != '+' && s[0] != '-') goto invalid_utc_offset;
        if (!have_2digits(s+1)) goto invalid_utc_offset;
        n += num_from_2digits(s+1) * 3600;
        if (s[0] == '-') {
            if (n == 0) return UTC_ZONE;
            n = -n;
        }
        return INT2FIX(n);
    }
    else {
        return num_exact(arg);
    }
  invalid_utc_offset:
    return Qnil;
}

static void
zone_set_offset(VALUE zone, struct time_object *tobj,
                wideval_t tlocal, wideval_t tutc, VALUE time)
{
    /* tlocal and tutc must be unmagnified and in seconds */
    wideval_t w = wsub(tlocal, tutc);
    VALUE off = w2v(w);
    validate_utc_offset(off);
    RB_OBJ_WRITE(time, &tobj->vtm.utc_offset, off);
    RB_OBJ_WRITE(time, &tobj->vtm.zone, zone);
    TZMODE_SET_LOCALTIME(tobj);
}

static wideval_t
extract_time(VALUE time)
{
    wideval_t t;
    const ID id_to_i = idTo_i;

#define EXTRACT_TIME() do { \
        t = NUM2WV(AREF(to_i)); \
    } while (0)

    if (rb_typeddata_is_kind_of(time, &time_data_type)) {
        struct time_object *tobj = RTYPEDDATA_GET_DATA(time);

        time_gmtime(time); /* ensure tm got */
        t = rb_time_unmagnify(tobj->timew);

        RB_GC_GUARD(time);
    }
    else if (RB_TYPE_P(time, T_STRUCT)) {
#define AREF(x) rb_struct_aref(time, ID2SYM(id_##x))
        EXTRACT_TIME();
#undef AREF
    }
    else {
#define AREF(x) rb_funcallv(time, id_##x, 0, 0)
        EXTRACT_TIME();
#undef AREF
    }
#undef EXTRACT_TIME

    return t;
}

static wideval_t
extract_vtm(VALUE time, VALUE orig_time, struct time_object *orig_tobj, VALUE subsecx)
{
    wideval_t t;
    const ID id_to_i = idTo_i;
    struct vtm *vtm = &orig_tobj->vtm;

#define EXTRACT_VTM() do { \
        VALUE subsecx; \
        vtm->year = obj2vint(AREF(year)); \
        vtm->mon = month_arg(AREF(mon)); \
        vtm->mday = obj2ubits(AREF(mday), 5); \
        vtm->hour = obj2ubits(AREF(hour), 5); \
        vtm->min = obj2ubits(AREF(min), 6); \
        vtm->sec = obj2subsecx(AREF(sec), &subsecx); \
        vtm->isdst = RTEST(AREF(isdst));             \
        vtm->utc_offset = Qnil; \
        t = NUM2WV(AREF(to_i)); \
    } while (0)

    if (rb_typeddata_is_kind_of(time, &time_data_type)) {
        struct time_object *tobj = RTYPEDDATA_GET_DATA(time);

        time_get_tm(time, tobj);
        time_set_vtm(orig_time, orig_tobj, tobj->vtm);
        t = rb_time_unmagnify(tobj->timew);
        if (TZMODE_FIXOFF_P(tobj) && vtm->utc_offset != INT2FIX(0))
            t = wadd(t, v2w(vtm->utc_offset));

        RB_GC_GUARD(time);
    }
    else if (RB_TYPE_P(time, T_STRUCT)) {
#define AREF(x) rb_struct_aref(time, ID2SYM(id_##x))
        EXTRACT_VTM();
#undef AREF
    }
    else if (rb_integer_type_p(time)) {
        t = v2w(time);
        struct vtm temp_vtm = *vtm;
        GMTIMEW(rb_time_magnify(t), &temp_vtm);
        time_set_vtm(orig_time, orig_tobj, temp_vtm);
    }
    else {
#define AREF(x) rb_funcallv(time, id_##x, 0, 0)
        EXTRACT_VTM();
#undef AREF
    }
#undef EXTRACT_VTM

    RB_OBJ_WRITE_UNALIGNED(orig_time, &vtm->subsecx, subsecx);

    validate_vtm(vtm);
    return t;
}

static void
zone_set_dst(VALUE zone, struct time_object *tobj, VALUE tm)
{
    ID id_dst_p;
    VALUE dst;
    CONST_ID(id_dst_p, "dst?");
    dst = rb_check_funcall(zone, id_dst_p, 1, &tm);
    tobj->vtm.isdst = (!UNDEF_P(dst) && RTEST(dst));
}

static int
zone_timelocal(VALUE zone, VALUE time)
{
    VALUE utc, tm;
    struct time_object *tobj = RTYPEDDATA_GET_DATA(time);
    wideval_t t, s;

    wdivmod(tobj->timew, WINT2FIXWV(TIME_SCALE), &t, &s);
    tm = tm_from_time(rb_cTimeTM, time);
    utc = rb_check_funcall(zone, id_local_to_utc, 1, &tm);
    if (UNDEF_P(utc)) return 0;

    s = extract_time(utc);
    zone_set_offset(zone, tobj, t, s, time);
    s = rb_time_magnify(s);
    if (tobj->vtm.subsecx != INT2FIX(0)) {
        s = wadd(s, v2w(tobj->vtm.subsecx));
    }
    time_set_timew(time, tobj, s);

    zone_set_dst(zone, tobj, tm);

    RB_GC_GUARD(time);

    return 1;
}

static int
zone_localtime(VALUE zone, VALUE time)
{
    VALUE local, tm, subsecx;
    struct time_object *tobj = RTYPEDDATA_GET_DATA(time);
    wideval_t t, s;

    split_second(tobj->timew, &t, &subsecx);
    tm = tm_from_time(rb_cTimeTM, time);

    local = rb_check_funcall(zone, id_utc_to_local, 1, &tm);
    if (UNDEF_P(local)) return 0;

    s = extract_vtm(local, time, tobj, subsecx);
    tobj->vtm.tm_got = 1;
    zone_set_offset(zone, tobj, s, t, time);
    zone_set_dst(zone, tobj, tm);

    RB_GC_GUARD(time);

    return 1;
}

static VALUE
find_timezone(VALUE time, VALUE zone)
{
    VALUE klass = CLASS_OF(time);

    return rb_check_funcall_default(klass, id_find_timezone, 1, &zone, Qnil);
}

/* Turn the special case 24:00:00 of already validated vtm into
 * 00:00:00 the next day */
static void
vtm_day_wraparound(struct vtm *vtm)
{
    if (vtm->hour < 24) return;

    /* Assuming UTC and no care of DST, just reset hour and advance
     * date, not to discard the validated vtm. */
    vtm->hour = 0;
    vtm_add_day(vtm, 1);
}

static VALUE time_init_vtm(VALUE time, struct vtm vtm, VALUE zone);

/*
 * Sets the broken-out time information into _time_.
 * Returns _time_.
 */
static VALUE
time_init_args(rb_execution_context_t *ec, VALUE time, VALUE year, VALUE mon, VALUE mday,
               VALUE hour, VALUE min, VALUE sec, VALUE zone)
{
    struct vtm vtm;

    vtm.wday = VTM_WDAY_INITVAL;
    vtm.yday = 0;
    vtm.zone = str_empty;

    vtm.year = obj2vint(year);

    vtm.mon = NIL_P(mon) ? 1 : month_arg(mon);

    vtm.mday = NIL_P(mday) ? 1 : obj2ubits(mday, 5);

    vtm.hour = NIL_P(hour) ? 0 : obj2ubits(hour, 5);

    vtm.min  = NIL_P(min) ? 0 : obj2ubits(min, 6);

    if (NIL_P(sec)) {
        vtm.sec = 0;
        vtm.subsecx = INT2FIX(0);
    }
    else {
        VALUE subsecx;
        vtm.sec = obj2subsecx(sec, &subsecx);
        vtm.subsecx = subsecx;
    }

    return time_init_vtm(time, vtm, zone);
}

static VALUE
time_init_vtm(VALUE time, struct vtm vtm, VALUE zone)
{
    VALUE utc = Qnil;
    struct time_object *tobj;

    vtm.isdst = VTM_ISDST_INITVAL;
    vtm.utc_offset = Qnil;
    const VALUE arg = zone;
    if (!NIL_P(arg)) {
        zone = Qnil;
        if (arg == ID2SYM(rb_intern("dst")))
            vtm.isdst = 1;
        else if (arg == ID2SYM(rb_intern("std")))
            vtm.isdst = 0;
        else if (maybe_tzobj_p(arg))
            zone = arg;
        else if (!NIL_P(utc = utc_offset_arg(arg)))
            vtm.utc_offset = utc == UTC_ZONE ? INT2FIX(0) : utc;
        else if (NIL_P(zone = find_timezone(time, arg)))
            invalid_utc_offset(arg);
    }

    validate_vtm(&vtm);

    time_modify(time);
    GetNewTimeval(time, tobj);

    if (!NIL_P(zone)) {
        time_set_timew(time, tobj, timegmw(&vtm));
        vtm_day_wraparound(&vtm);
        time_set_vtm(time, tobj, vtm);
        tobj->vtm.tm_got = 1;
        TZMODE_SET_LOCALTIME(tobj);
        if (zone_timelocal(zone, time)) {
            return time;
        }
        else if (NIL_P(vtm.utc_offset = utc_offset_arg(zone))) {
            if (NIL_P(zone = find_timezone(time, zone)) || !zone_timelocal(zone, time))
                invalid_utc_offset(arg);
        }
    }

    if (utc == UTC_ZONE) {
        time_set_timew(time, tobj, timegmw(&vtm));
        vtm.isdst = 0; /* No DST in UTC */
        vtm_day_wraparound(&vtm);
        time_set_vtm(time, tobj, vtm);
        tobj->vtm.tm_got = 1;
        TZMODE_SET_UTC(tobj);
        return time;
    }

    TZMODE_SET_LOCALTIME(tobj);
    tobj->vtm.tm_got=0;

    if (!NIL_P(vtm.utc_offset)) {
        VALUE off = vtm.utc_offset;
        vtm_add_offset(&vtm, off, -1);
        vtm.utc_offset = Qnil;
        time_set_timew(time, tobj, timegmw(&vtm));

        return time_set_utc_offset(time, off);
    }
    else {
        time_set_timew(time, tobj, timelocalw(&vtm));

        return time_localtime(time);
    }
}

static int
two_digits(const char *ptr, const char *end, const char **endp, const char *name)
{
    ssize_t len = end - ptr;
    if (len < 2 || !have_2digits(ptr) || ((len > 2) && ISDIGIT(ptr[2]))) {
        VALUE mesg = rb_sprintf("two digits %s is expected", name);
        if (ptr[-1] == '-' || ptr[-1] == ':') {
            rb_str_catf(mesg, " after '%c'", ptr[-1]);
        }
        rb_str_catf(mesg, ": %.*s", ((len > 10) ? 10 : (int)(end - ptr)) + 1, ptr - 1);
        rb_exc_raise(rb_exc_new_str(rb_eArgError, mesg));
    }
    *endp = ptr + 2;
    return num_from_2digits(ptr);
}

static VALUE
parse_int(const char *ptr, const char *end, const char **endp, size_t *ndigits, bool sign)
{
    ssize_t len = (end - ptr);
    int flags = sign ? RB_INT_PARSE_SIGN : 0;
    return rb_int_parse_cstr(ptr, len, (char **)endp, ndigits, 10, flags);
}

/*
 * Parses _str_ and sets the broken-out time information into _time_.
 * If _str_ is not a String, returns +nil+, otherwise returns _time_.
 */
static VALUE
time_init_parse(rb_execution_context_t *ec, VALUE time, VALUE str, VALUE zone, VALUE precision)
{
    if (NIL_P(str = rb_check_string_type(str))) return Qnil;
    if (!rb_enc_str_asciicompat_p(str)) {
        rb_raise(rb_eArgError, "time string should have ASCII compatible encoding");
    }

    const char *const begin = RSTRING_PTR(str);
    const char *const end = RSTRING_END(str);
    const char *ptr = begin;
    VALUE year = Qnil, subsec = Qnil;
    int mon = -1, mday = -1, hour = -1, min = -1, sec = -1;
    size_t ndigits;
    size_t prec = NIL_P(precision) ? SIZE_MAX : NUM2SIZET(precision);

    if ((ptr < end) && (ISSPACE(*ptr) || ISSPACE(*(end-1)))) {
        rb_raise(rb_eArgError, "can't parse: %+"PRIsVALUE, str);
    }
    year = parse_int(ptr, end, &ptr, &ndigits, true);
    if (NIL_P(year)) {
        rb_raise(rb_eArgError, "can't parse: %+"PRIsVALUE, str);
    }
    else if (ndigits < 4) {
        rb_raise(rb_eArgError, "year must be 4 or more digits: %.*s", (int)ndigits, ptr - ndigits);
    }
    else if (ptr == end) {
        goto only_year;
    }
    do {
#define peekable_p(n) ((ptrdiff_t)(n) < (end - ptr))
#define peek_n(c, n) (peekable_p(n) && ((unsigned char)ptr[n] == (c)))
#define peek(c) peek_n(c, 0)
#define peekc_n(n) (peekable_p(n) ? (int)(unsigned char)ptr[n] : -1)
#define peekc() peekc_n(0)
#define expect_two_digits(x, bits) \
        (((unsigned int)(x = two_digits(ptr + 1, end, &ptr, #x)) > (1U << bits) - 1) ? \
         rb_raise(rb_eArgError, #x" out of range") : (void)0)
        if (!peek('-')) break;
        expect_two_digits(mon, 4);
        if (!peek('-')) break;
        expect_two_digits(mday, 5);
        if (!peek(' ') && !peek('T')) break;
        const char *const time_part = ptr + 1;
        if (!ISDIGIT(peekc_n(1))) break;
#define nofraction(x) \
        if (peek('.')) { \
            rb_raise(rb_eArgError, "fraction " #x " is not supported: %.*s", \
                     (int)(ptr + 1 - time_part), time_part); \
        }
#define need_colon(x) \
        if (!peek(':')) { \
            rb_raise(rb_eArgError, "missing " #x " part: %.*s", \
                     (int)(ptr + 1 - time_part), time_part); \
        }
        expect_two_digits(hour, 5);
        nofraction(hour);
        need_colon(min);
        expect_two_digits(min, 6);
        nofraction(min);
        need_colon(sec);
        expect_two_digits(sec, 6);
        if (peek('.')) {
            ptr++;
            for (ndigits = 0; ndigits < prec && ISDIGIT(peekc_n(ndigits)); ++ndigits);
            if (!ndigits) {
                int clen = rb_enc_precise_mbclen(ptr, end, rb_enc_get(str));
                if (clen < 0) clen = 0;
                rb_raise(rb_eArgError, "subsecond expected after dot: %.*s",
                         (int)(ptr - time_part) + clen, time_part);
            }
            subsec = parse_int(ptr, ptr + ndigits, &ptr, &ndigits, false);
            if (NIL_P(subsec)) break;
            while (ptr < end && ISDIGIT(*ptr)) ptr++;
        }
    } while (0);
    while (ptr < end && ISSPACE(*ptr)) ptr++;
    const char *const zstr = ptr;
    while (ptr < end && !ISSPACE(*ptr)) ptr++;
    const char *const zend = ptr;
    while (ptr < end && ISSPACE(*ptr)) ptr++;
    if (ptr < end) {
        VALUE mesg = rb_str_new_cstr("can't parse at: ");
        rb_str_cat(mesg, ptr, end - ptr);
        rb_exc_raise(rb_exc_new_str(rb_eArgError, mesg));
    }
    if (zend > zstr) {
        zone = rb_str_subseq(str, zstr - begin, zend - zstr);
    }
    else if (hour == -1) {
        rb_raise(rb_eArgError, "no time information");
    }
    if (!NIL_P(subsec)) {
        /* subseconds is the last using ndigits */
        if (ndigits < (size_t)TIME_SCALE_NUMDIGITS) {
            VALUE mul = rb_int_positive_pow(10, TIME_SCALE_NUMDIGITS - ndigits);
            subsec = rb_int_mul(subsec, mul);
        }
        else if (ndigits > (size_t)TIME_SCALE_NUMDIGITS) {
            VALUE num = rb_int_positive_pow(10, ndigits - TIME_SCALE_NUMDIGITS);
            subsec = rb_rational_new(subsec, num);
        }
    }

only_year:
    ;

    struct vtm vtm = {
        .wday = VTM_WDAY_INITVAL,
        .yday = 0,
        .zone = str_empty,
        .year = year,
        .mon  = (mon < 0)  ? 1 : mon,
        .mday = (mday < 0) ? 1 : mday,
        .hour = (hour < 0) ? 0 : hour,
        .min  = (min < 0)  ? 0 : min,
        .sec  = (sec < 0)  ? 0 : sec,
        .subsecx = NIL_P(subsec) ? INT2FIX(0) : subsec,
    };
    return time_init_vtm(time, vtm, zone);
}

static void
subsec_normalize(wideint_t *secp, long *subsecp, const long maxsubsec)
{
    wideint_t sec = *secp;
    long subsec = *subsecp;
    long sec2;

    if (UNLIKELY(subsec >= maxsubsec)) { /* subsec positive overflow */
        sec2 = subsec / maxsubsec;
        if (WIDEINT_MAX - sec2 < sec) {
            rb_raise(rb_eRangeError, "out of Time range");
        }
        subsec -= sec2 * maxsubsec;
        sec += sec2;
    }
    else if (UNLIKELY(subsec < 0)) {    /* subsec negative overflow */
        sec2 = NDIV(subsec, maxsubsec); /* negative div */
        if (sec < WIDEINT_MIN - sec2) {
            rb_raise(rb_eRangeError, "out of Time range");
        }
        subsec -= sec2 * maxsubsec;
        sec += sec2;
    }
    *secp = sec;
    *subsecp = subsec;
}

#define time_usec_normalize(secp, usecp) subsec_normalize(secp, usecp, 1000000)
#define time_nsec_normalize(secp, nsecp) subsec_normalize(secp, nsecp, 1000000000)

static VALUE
time_new_timew(VALUE klass, wideval_t timew)
{
    VALUE time = time_s_alloc(klass);
    struct time_object *tobj;

    tobj = RTYPEDDATA_GET_DATA(time);	/* skip type check */
    TZMODE_SET_LOCALTIME(tobj);
    time_set_timew(time, tobj, timew);

    return time;
}

static wideint_t
TIMETtoWIDEINT(time_t t)
{
#if SIZEOF_TIME_T * CHAR_BIT - (SIGNEDNESS_OF_TIME_T < 0) > \
    SIZEOF_WIDEINT * CHAR_BIT - 1
    /* compare in bit size without sign bit */
    if (t > WIDEINT_MAX) rb_raise(rb_eArgError, "out of Time range");
#endif
    return (wideint_t)t;
}

VALUE
rb_time_new(time_t sec, long usec)
{
    wideint_t isec = TIMETtoWIDEINT(sec);
    time_usec_normalize(&isec, &usec);
    return time_new_timew(rb_cTime, timenano2timew(isec, usec * 1000));
}

/* returns localtime time object */
VALUE
rb_time_nano_new(time_t sec, long nsec)
{
    wideint_t isec = TIMETtoWIDEINT(sec);
    time_nsec_normalize(&isec, &nsec);
    return time_new_timew(rb_cTime, timenano2timew(isec, nsec));
}

VALUE
rb_time_timespec_new(const struct timespec *ts, int offset)
{
    struct time_object *tobj;
    VALUE time = rb_time_nano_new(ts->tv_sec, ts->tv_nsec);

    if (-86400 < offset && offset <  86400) { /* fixoff */
        GetTimeval(time, tobj);
        TZMODE_SET_FIXOFF(time, tobj, INT2FIX(offset));
    }
    else if (offset == INT_MAX) { /* localtime */
    }
    else if (offset == INT_MAX-1) { /* UTC */
        GetTimeval(time, tobj);
        TZMODE_SET_UTC(tobj);
    }
    else {
        rb_raise(rb_eArgError, "utc_offset out of range");
    }

    return time;
}

VALUE
rb_time_num_new(VALUE timev, VALUE off)
{
    VALUE time = time_new_timew(rb_cTime, rb_time_magnify(v2w(timev)));

    if (!NIL_P(off)) {
        VALUE zone = off;

        if (maybe_tzobj_p(zone)) {
            time_gmtime(time);
            if (zone_timelocal(zone, time)) return time;
        }
        if (NIL_P(off = utc_offset_arg(off))) {
            off = zone;
            if (NIL_P(zone = find_timezone(time, off))) invalid_utc_offset(off);
            time_gmtime(time);
            if (!zone_timelocal(zone, time)) invalid_utc_offset(off);
            return time;
        }
        else if (off == UTC_ZONE) {
            return time_gmtime(time);
        }

        validate_utc_offset(off);
        time_set_utc_offset(time, off);
        return time;
    }

    return time;
}

static struct timespec
time_timespec(VALUE num, int interval)
{
    struct timespec t;
    const char *const tstr = interval ? "time interval" : "time";
    VALUE i, f, ary;

#ifndef NEGATIVE_TIME_T
# define arg_range_check(v) \
    (((v) < 0) ? \
     rb_raise(rb_eArgError, "%s must not be negative", tstr) : \
     (void)0)
#else
# define arg_range_check(v) \
    ((interval && (v) < 0) ? \
     rb_raise(rb_eArgError, "time interval must not be negative") : \
     (void)0)
#endif

    if (FIXNUM_P(num)) {
        t.tv_sec = NUM2TIMET(num);
        arg_range_check(t.tv_sec);
        t.tv_nsec = 0;
    }
    else if (RB_FLOAT_TYPE_P(num)) {
        double x = RFLOAT_VALUE(num);
        arg_range_check(x);
        {
            double f, d;

            d = modf(x, &f);
            if (d >= 0) {
                t.tv_nsec = (int)(d*1e9+0.5);
                if (t.tv_nsec >= 1000000000) {
                    t.tv_nsec -= 1000000000;
                    f += 1;
                }
            }
            else if ((t.tv_nsec = (int)(-d*1e9+0.5)) > 0) {
                t.tv_nsec = 1000000000 - t.tv_nsec;
                f -= 1;
            }
            t.tv_sec = (time_t)f;
            if (f != t.tv_sec) {
                rb_raise(rb_eRangeError, "%f out of Time range", x);
            }
        }
    }
    else if (RB_BIGNUM_TYPE_P(num)) {
        t.tv_sec = NUM2TIMET(num);
        arg_range_check(t.tv_sec);
        t.tv_nsec = 0;
    }
    else {
        i = INT2FIX(1);
        ary = rb_check_funcall(num, id_divmod, 1, &i);
        if (!UNDEF_P(ary) && !NIL_P(ary = rb_check_array_type(ary))) {
            i = rb_ary_entry(ary, 0);
            f = rb_ary_entry(ary, 1);
            t.tv_sec = NUM2TIMET(i);
            arg_range_check(t.tv_sec);
            f = rb_funcall(f, '*', 1, INT2FIX(1000000000));
            t.tv_nsec = NUM2LONG(f);
        }
        else {
            rb_raise(rb_eTypeError, "can't convert %"PRIsVALUE" into %s",
                     rb_obj_class(num), tstr);
        }
    }
    return t;
#undef arg_range_check
}

static struct timeval
time_timeval(VALUE num, int interval)
{
    struct timespec ts;
    struct timeval tv;

    ts = time_timespec(num, interval);
    tv.tv_sec = (TYPEOF_TIMEVAL_TV_SEC)ts.tv_sec;
    tv.tv_usec = (TYPEOF_TIMEVAL_TV_USEC)(ts.tv_nsec / 1000);

    return tv;
}

struct timeval
rb_time_interval(VALUE num)
{
    return time_timeval(num, TRUE);
}

struct timeval
rb_time_timeval(VALUE time)
{
    struct time_object *tobj;
    struct timeval t;
    struct timespec ts;

    if (IsTimeval(time)) {
        GetTimeval(time, tobj);
        ts = timew2timespec(tobj->timew);
        t.tv_sec = (TYPEOF_TIMEVAL_TV_SEC)ts.tv_sec;
        t.tv_usec = (TYPEOF_TIMEVAL_TV_USEC)(ts.tv_nsec / 1000);
        return t;
    }
    return time_timeval(time, FALSE);
}

struct timespec
rb_time_timespec(VALUE time)
{
    struct time_object *tobj;
    struct timespec t;

    if (IsTimeval(time)) {
        GetTimeval(time, tobj);
        t = timew2timespec(tobj->timew);
        return t;
    }
    return time_timespec(time, FALSE);
}

struct timespec
rb_time_timespec_interval(VALUE num)
{
    return time_timespec(num, TRUE);
}

static int
get_scale(VALUE unit)
{
    if (unit == ID2SYM(id_nanosecond) || unit == ID2SYM(id_nsec)) {
        return 1000000000;
    }
    else if (unit == ID2SYM(id_microsecond) || unit == ID2SYM(id_usec)) {
        return 1000000;
    }
    else if (unit == ID2SYM(id_millisecond)) {
        return 1000;
    }
    else {
        rb_raise(rb_eArgError, "unexpected unit: %"PRIsVALUE, unit);
    }
}

static VALUE
time_s_at(rb_execution_context_t *ec, VALUE klass, VALUE time, VALUE subsec, VALUE unit, VALUE zone)
{
    VALUE t;
    wideval_t timew;

    if (subsec) {
        int scale = get_scale(unit);
        time = num_exact(time);
        t = num_exact(subsec);
        timew = wadd(rb_time_magnify(v2w(time)), wmulquoll(v2w(t), TIME_SCALE, scale));
        t = time_new_timew(klass, timew);
    }
    else if (IsTimeval(time)) {
        struct time_object *tobj, *tobj2;
        GetTimeval(time, tobj);
        t = time_new_timew(klass, tobj->timew);
        GetTimeval(t, tobj2);
        TZMODE_COPY(tobj2, tobj);
    }
    else {
        timew = rb_time_magnify(v2w(num_exact(time)));
        t = time_new_timew(klass, timew);
    }
    if (!NIL_P(zone)) {
        time_zonelocal(t, zone);
    }

    return t;
}

static VALUE
time_s_at1(rb_execution_context_t *ec, VALUE klass, VALUE time)
{
    return time_s_at(ec, klass, time, Qfalse, ID2SYM(id_microsecond), Qnil);
}

static const char months[][4] = {
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
};

static int
obj2int(VALUE obj)
{
    if (RB_TYPE_P(obj, T_STRING)) {
        obj = rb_str_to_inum(obj, 10, TRUE);
    }

    return NUM2INT(obj);
}

/* bits should be 0 <= x <= 31 */
static uint32_t
obj2ubits(VALUE obj, unsigned int bits)
{
    const unsigned int usable_mask = (1U << bits) - 1;
    unsigned int rv = (unsigned int)obj2int(obj);

    if ((rv & usable_mask) != rv)
        rb_raise(rb_eArgError, "argument out of range");
    return (uint32_t)rv;
}

static VALUE
obj2vint(VALUE obj)
{
    if (RB_TYPE_P(obj, T_STRING)) {
        obj = rb_str_to_inum(obj, 10, TRUE);
    }
    else {
        obj = rb_to_int(obj);
    }

    return obj;
}

static uint32_t
obj2subsecx(VALUE obj, VALUE *subsecx)
{
    VALUE subsec;

    if (RB_TYPE_P(obj, T_STRING)) {
        obj = rb_str_to_inum(obj, 10, TRUE);
        *subsecx = INT2FIX(0);
    }
    else {
        divmodv(num_exact(obj), INT2FIX(1), &obj, &subsec);
        *subsecx = w2v(rb_time_magnify(v2w(subsec)));
    }
    return obj2ubits(obj, 6); /* vtm->sec */
}

static VALUE
usec2subsecx(VALUE obj)
{
    if (RB_TYPE_P(obj, T_STRING)) {
        obj = rb_str_to_inum(obj, 10, TRUE);
    }

    return mulquov(num_exact(obj), INT2FIX(TIME_SCALE), INT2FIX(1000000));
}

static uint32_t
month_arg(VALUE arg)
{
    int i, mon;

    if (FIXNUM_P(arg)) {
        return obj2ubits(arg, 4);
    }

    mon = 0;
    VALUE s = rb_check_string_type(arg);
    if (!NIL_P(s) && RSTRING_LEN(s) > 0) {
        arg = s;
        for (i=0; i<12; i++) {
            if (RSTRING_LEN(s) == 3 &&
                STRNCASECMP(months[i], RSTRING_PTR(s), 3) == 0) {
                mon = i+1;
                break;
            }
        }
    }
    if (mon == 0) {
        mon = obj2ubits(arg, 4);
    }
    return mon;
}

static VALUE
validate_utc_offset(VALUE utc_offset)
{
    if (le(utc_offset, INT2FIX(-86400)) || ge(utc_offset, INT2FIX(86400)))
        rb_raise(rb_eArgError, "utc_offset out of range");
    return utc_offset;
}

static VALUE
validate_zone_name(VALUE zone_name)
{
    StringValueCStr(zone_name);
    return zone_name;
}

static void
validate_vtm(struct vtm *vtm)
{
#define validate_vtm_range(mem, b, e) \
    ((vtm->mem < b || vtm->mem > e) ? \
     rb_raise(rb_eArgError, #mem" out of range") : (void)0)
    validate_vtm_range(mon, 1, 12);
    validate_vtm_range(mday, 1, 31);
    validate_vtm_range(hour, 0, 24);
    validate_vtm_range(min, 0, (vtm->hour == 24 ? 0 : 59));
    validate_vtm_range(sec, 0, (vtm->hour == 24 ? 0 : 60));
    if (lt(vtm->subsecx, INT2FIX(0)) || ge(vtm->subsecx, INT2FIX(TIME_SCALE)))
        rb_raise(rb_eArgError, "subsecx out of range");
    if (!NIL_P(vtm->utc_offset)) validate_utc_offset(vtm->utc_offset);
#undef validate_vtm_range
}

static void
time_arg(int argc, const VALUE *argv, struct vtm *vtm)
{
    VALUE v[8];
    VALUE subsecx = INT2FIX(0);

    vtm->year = INT2FIX(0);
    vtm->mon = 0;
    vtm->mday = 0;
    vtm->hour = 0;
    vtm->min = 0;
    vtm->sec = 0;
    vtm->subsecx = INT2FIX(0);
    vtm->utc_offset = Qnil;
    vtm->wday = 0;
    vtm->yday = 0;
    vtm->isdst = 0;
    vtm->zone = str_empty;

    if (argc == 10) {
        v[0] = argv[5];
        v[1] = argv[4];
        v[2] = argv[3];
        v[3] = argv[2];
        v[4] = argv[1];
        v[5] = argv[0];
        v[6] = Qnil;
        vtm->isdst = RTEST(argv[8]) ? 1 : 0;
    }
    else {
        rb_scan_args(argc, argv, "17", &v[0],&v[1],&v[2],&v[3],&v[4],&v[5],&v[6],&v[7]);
        /* v[6] may be usec or zone (parsedate) */
        /* v[7] is wday (parsedate; ignored) */
        vtm->wday = VTM_WDAY_INITVAL;
        vtm->isdst = VTM_ISDST_INITVAL;
    }

    vtm->year = obj2vint(v[0]);

    if (NIL_P(v[1])) {
        vtm->mon = 1;
    }
    else {
        vtm->mon = month_arg(v[1]);
    }

    if (NIL_P(v[2])) {
        vtm->mday = 1;
    }
    else {
        vtm->mday = obj2ubits(v[2], 5);
    }

    /* normalize month-mday */
    switch (vtm->mon) {
      case 2:
        {
            /* this drops higher bits but it's not a problem to calc leap year */
            unsigned int mday2 = leap_year_v_p(vtm->year) ? 29 : 28;
            if (vtm->mday > mday2) {
                vtm->mday -= mday2;
                vtm->mon++;
            }
        }
        break;
      case 4:
      case 6:
      case 9:
      case 11:
        if (vtm->mday == 31) {
            vtm->mon++;
            vtm->mday = 1;
        }
        break;
    }

    vtm->hour = NIL_P(v[3])?0:obj2ubits(v[3], 5);

    vtm->min  = NIL_P(v[4])?0:obj2ubits(v[4], 6);

    if (!NIL_P(v[6]) && argc == 7) {
        vtm->sec = NIL_P(v[5])?0:obj2ubits(v[5],6);
        subsecx  = usec2subsecx(v[6]);
    }
    else {
        /* when argc == 8, v[6] is timezone, but ignored */
        if (NIL_P(v[5])) {
            vtm->sec = 0;
        }
        else {
            vtm->sec = obj2subsecx(v[5], &subsecx);
        }
    }
    vtm->subsecx = subsecx;

    validate_vtm(vtm);
    RB_GC_GUARD(subsecx);
}

static int
leap_year_p(long y)
{
    /* TODO:
     *  ensure about negative years in proleptic Gregorian calendar.
     */
    unsigned long uy = (unsigned long)(LIKELY(y >= 0) ? y : -y);

    if (LIKELY(uy % 4 != 0)) return 0;

    unsigned long century = uy / 100;
    if (LIKELY(uy != century * 100)) return 1;
    return century % 4 == 0;
}

static time_t
timegm_noleapsecond(struct tm *tm)
{
    long tm_year = tm->tm_year;
    int tm_yday = calc_tm_yday(tm->tm_year, tm->tm_mon, tm->tm_mday);

    /*
     *  `Seconds Since the Epoch' in SUSv3:
     *  tm_sec + tm_min*60 + tm_hour*3600 + tm_yday*86400 +
     *  (tm_year-70)*31536000 + ((tm_year-69)/4)*86400 -
     *  ((tm_year-1)/100)*86400 + ((tm_year+299)/400)*86400
     */
    return tm->tm_sec + tm->tm_min*60 + tm->tm_hour*3600 +
           (time_t)(tm_yday +
                    (tm_year-70)*365 +
                    DIV(tm_year-69,4) -
                    DIV(tm_year-1,100) +
                    DIV(tm_year+299,400))*86400;
}

#if 0
#define DEBUG_FIND_TIME_NUMGUESS
#define DEBUG_GUESSRANGE
#endif

static const bool debug_guessrange =
#ifdef DEBUG_GUESSRANGE
    true;
#else
    false;
#endif

#define DEBUG_REPORT_GUESSRANGE \
    (debug_guessrange ? debug_report_guessrange(guess_lo, guess_hi) : (void)0)

static inline void
debug_report_guessrange(time_t guess_lo, time_t guess_hi)
{
    time_t guess_diff = guess_hi - guess_lo;
    fprintf(stderr, "find time guess range: %"PRI_TIMET_PREFIX"d - "
            "%"PRI_TIMET_PREFIX"d : %"PRI_TIMET_PREFIX"u\n",
            guess_lo, guess_hi, guess_diff);
}

static const bool debug_find_time_numguess =
#ifdef DEBUG_FIND_TIME_NUMGUESS
    true;
#else
    false;
#endif

#define DEBUG_FIND_TIME_NUMGUESS_INC \
    (void)(debug_find_time_numguess && find_time_numguess++),
static unsigned long long find_time_numguess;

static VALUE
find_time_numguess_getter(ID name, VALUE *data)
{
    unsigned long long *numguess = (void *)data;
    return ULL2NUM(*numguess);
}

static const char *
find_time_t(struct tm *tptr, int utc_p, time_t *tp)
{
    time_t guess, guess0, guess_lo, guess_hi;
    struct tm *tm, tm0, tm_lo, tm_hi;
    int d;
    int find_dst;
    struct tm result;
    int status;
    int tptr_tm_yday;

#define GUESS(p) (DEBUG_FIND_TIME_NUMGUESS_INC (utc_p ? gmtime_with_leapsecond((p), &result) : LOCALTIME((p), result)))

    guess_lo = TIMET_MIN;
    guess_hi = TIMET_MAX;

    find_dst = 0 < tptr->tm_isdst;

    /* /etc/localtime might be changed. reload it. */
    update_tz();

    tm0 = *tptr;
    if (tm0.tm_mon < 0) {
        tm0.tm_mon = 0;
        tm0.tm_mday = 1;
        tm0.tm_hour = 0;
        tm0.tm_min = 0;
        tm0.tm_sec = 0;
    }
    else if (11 < tm0.tm_mon) {
        tm0.tm_mon = 11;
        tm0.tm_mday = 31;
        tm0.tm_hour = 23;
        tm0.tm_min = 59;
        tm0.tm_sec = 60;
    }
    else if (tm0.tm_mday < 1) {
        tm0.tm_mday = 1;
        tm0.tm_hour = 0;
        tm0.tm_min = 0;
        tm0.tm_sec = 0;
    }
    else if ((d = days_in_month_in(1900 + tm0.tm_year)[tm0.tm_mon]) < tm0.tm_mday) {
        tm0.tm_mday = d;
        tm0.tm_hour = 23;
        tm0.tm_min = 59;
        tm0.tm_sec = 60;
    }
    else if (tm0.tm_hour < 0) {
        tm0.tm_hour = 0;
        tm0.tm_min = 0;
        tm0.tm_sec = 0;
    }
    else if (23 < tm0.tm_hour) {
        tm0.tm_hour = 23;
        tm0.tm_min = 59;
        tm0.tm_sec = 60;
    }
    else if (tm0.tm_min < 0) {
        tm0.tm_min = 0;
        tm0.tm_sec = 0;
    }
    else if (59 < tm0.tm_min) {
        tm0.tm_min = 59;
        tm0.tm_sec = 60;
    }
    else if (tm0.tm_sec < 0) {
        tm0.tm_sec = 0;
    }
    else if (60 < tm0.tm_sec) {
        tm0.tm_sec = 60;
    }

    DEBUG_REPORT_GUESSRANGE;
    guess0 = guess = timegm_noleapsecond(&tm0);
    tm = GUESS(&guess);
    if (tm) {
        d = tmcmp(tptr, tm);
        if (d == 0) { goto found; }
        if (d < 0) {
            guess_hi = guess;
            guess -= 24 * 60 * 60;
        }
        else {
            guess_lo = guess;
            guess += 24 * 60 * 60;
        }
        DEBUG_REPORT_GUESSRANGE;
        if (guess_lo < guess && guess < guess_hi && (tm = GUESS(&guess)) != NULL) {
            d = tmcmp(tptr, tm);
            if (d == 0) { goto found; }
            if (d < 0)
                guess_hi = guess;
            else
                guess_lo = guess;
            DEBUG_REPORT_GUESSRANGE;
        }
    }

    tm = GUESS(&guess_lo);
    if (!tm) goto error;
    d = tmcmp(tptr, tm);
    if (d < 0) goto out_of_range;
    if (d == 0) { guess = guess_lo; goto found; }
    tm_lo = *tm;

    tm = GUESS(&guess_hi);
    if (!tm) goto error;
    d = tmcmp(tptr, tm);
    if (d > 0) goto out_of_range;
    if (d == 0) { guess = guess_hi; goto found; }
    tm_hi = *tm;

    DEBUG_REPORT_GUESSRANGE;

    status = 1;

    while (guess_lo + 1 < guess_hi) {
      binsearch:
        if (status == 0) {
            guess = guess_lo / 2 + guess_hi / 2;
            if (guess <= guess_lo)
                guess = guess_lo + 1;
            else if (guess >= guess_hi)
                guess = guess_hi - 1;
            status = 1;
        }
        else {
            if (status == 1) {
                time_t guess0_hi = timegm_noleapsecond(&tm_hi);
                guess = guess_hi - (guess0_hi - guess0);
                if (guess == guess_hi) /* hh:mm:60 tends to cause this condition. */
                    guess--;
                status = 2;
            }
            else if (status == 2) {
                time_t guess0_lo = timegm_noleapsecond(&tm_lo);
                guess = guess_lo + (guess0 - guess0_lo);
                if (guess == guess_lo)
                    guess++;
                status = 0;
            }
            if (guess <= guess_lo || guess_hi <= guess) {
                /* Previous guess is invalid. try binary search. */
                if (debug_guessrange) {
                    if (guess <= guess_lo) {
                        fprintf(stderr, "too small guess: %"PRI_TIMET_PREFIX"d"\
                                " <= %"PRI_TIMET_PREFIX"d\n", guess, guess_lo);
                    }
                    if (guess_hi <= guess) {
                        fprintf(stderr, "too big guess: %"PRI_TIMET_PREFIX"d"\
                                " <= %"PRI_TIMET_PREFIX"d\n", guess_hi, guess);
                    }
                }
                status = 0;
                goto binsearch;
            }
        }

        tm = GUESS(&guess);
        if (!tm) goto error;

        d = tmcmp(tptr, tm);

        if (d < 0) {
            guess_hi = guess;
            tm_hi = *tm;
            DEBUG_REPORT_GUESSRANGE;
        }
        else if (d > 0) {
            guess_lo = guess;
            tm_lo = *tm;
            DEBUG_REPORT_GUESSRANGE;
        }
        else {
            goto found;
        }
    }

    /* Given argument has no corresponding time_t. Let's extrapolate. */
    /*
     *  `Seconds Since the Epoch' in SUSv3:
     *  tm_sec + tm_min*60 + tm_hour*3600 + tm_yday*86400 +
     *  (tm_year-70)*31536000 + ((tm_year-69)/4)*86400 -
     *  ((tm_year-1)/100)*86400 + ((tm_year+299)/400)*86400
     */

    tptr_tm_yday = calc_tm_yday(tptr->tm_year, tptr->tm_mon, tptr->tm_mday);

    *tp = guess_lo +
          ((tptr->tm_year - tm_lo.tm_year) * 365 +
           DIV((tptr->tm_year-69), 4) -
           DIV((tptr->tm_year-1), 100) +
           DIV((tptr->tm_year+299), 400) -
           DIV((tm_lo.tm_year-69), 4) +
           DIV((tm_lo.tm_year-1), 100) -
           DIV((tm_lo.tm_year+299), 400) +
           tptr_tm_yday -
           tm_lo.tm_yday) * 86400 +
          (tptr->tm_hour - tm_lo.tm_hour) * 3600 +
          (tptr->tm_min - tm_lo.tm_min) * 60 +
          (tptr->tm_sec - (tm_lo.tm_sec == 60 ? 59 : tm_lo.tm_sec));

    return NULL;

  found:
    if (!utc_p) {
        /* If localtime is nonmonotonic, another result may exist. */
        time_t guess2;
        if (find_dst) {
            guess2 = guess - 2 * 60 * 60;
            tm = LOCALTIME(&guess2, result);
            if (tm) {
                if (tptr->tm_hour != (tm->tm_hour + 2) % 24 ||
                    tptr->tm_min != tm->tm_min ||
                    tptr->tm_sec != tm->tm_sec) {
                    guess2 -= (tm->tm_hour - tptr->tm_hour) * 60 * 60 +
                        (tm->tm_min - tptr->tm_min) * 60 +
                        (tm->tm_sec - tptr->tm_sec);
                    if (tptr->tm_mday != tm->tm_mday)
                        guess2 += 24 * 60 * 60;
                    if (guess != guess2) {
                        tm = LOCALTIME(&guess2, result);
                        if (tm && tmcmp(tptr, tm) == 0) {
                            if (guess < guess2)
                                *tp = guess;
                            else
                                *tp = guess2;
                            return NULL;
                        }
                    }
                }
            }
        }
        else {
            guess2 = guess + 2 * 60 * 60;
            tm = LOCALTIME(&guess2, result);
            if (tm) {
                if ((tptr->tm_hour + 2) % 24 != tm->tm_hour ||
                    tptr->tm_min != tm->tm_min ||
                    tptr->tm_sec != tm->tm_sec) {
                    guess2 -= (tm->tm_hour - tptr->tm_hour) * 60 * 60 +
                        (tm->tm_min - tptr->tm_min) * 60 +
                        (tm->tm_sec - tptr->tm_sec);
                    if (tptr->tm_mday != tm->tm_mday)
                        guess2 -= 24 * 60 * 60;
                    if (guess != guess2) {
                        tm = LOCALTIME(&guess2, result);
                        if (tm && tmcmp(tptr, tm) == 0) {
                            if (guess < guess2)
                                *tp = guess2;
                            else
                                *tp = guess;
                            return NULL;
                        }
                    }
                }
            }
        }
    }
    *tp = guess;
    return NULL;

  out_of_range:
    return "time out of range";

  error:
    return "gmtime/localtime error";
}

static int
vtmcmp(struct vtm *a, struct vtm *b)
{
    if (ne(a->year, b->year))
        return lt(a->year, b->year) ? -1 : 1;
    else if (a->mon != b->mon)
        return a->mon < b->mon ? -1 : 1;
    else if (a->mday != b->mday)
        return a->mday < b->mday ? -1 : 1;
    else if (a->hour != b->hour)
        return a->hour < b->hour ? -1 : 1;
    else if (a->min != b->min)
        return a->min < b->min ? -1 : 1;
    else if (a->sec != b->sec)
        return a->sec < b->sec ? -1 : 1;
    else if (ne(a->subsecx, b->subsecx))
        return lt(a->subsecx, b->subsecx) ? -1 : 1;
    else
        return 0;
}

static int
tmcmp(struct tm *a, struct tm *b)
{
    if (a->tm_year != b->tm_year)
        return a->tm_year < b->tm_year ? -1 : 1;
    else if (a->tm_mon != b->tm_mon)
        return a->tm_mon < b->tm_mon ? -1 : 1;
    else if (a->tm_mday != b->tm_mday)
        return a->tm_mday < b->tm_mday ? -1 : 1;
    else if (a->tm_hour != b->tm_hour)
        return a->tm_hour < b->tm_hour ? -1 : 1;
    else if (a->tm_min != b->tm_min)
        return a->tm_min < b->tm_min ? -1 : 1;
    else if (a->tm_sec != b->tm_sec)
        return a->tm_sec < b->tm_sec ? -1 : 1;
    else
        return 0;
}

/*
 * call-seq:
 *   Time.utc(year, month = 1, mday = 1, hour = 0, min = 0, sec = 0, usec = 0) -> new_time
 *   Time.utc(sec, min, hour, mday, month, year, dummy, dummy, dummy, dummy) -> new_time
 *
 * Returns a new +Time+ object based the on given arguments,
 * in the UTC timezone.
 *
 * With one to seven arguments given,
 * the arguments are interpreted as in the first calling sequence above:
 *
 *   Time.utc(year, month = 1, mday = 1, hour = 0, min = 0, sec = 0, usec = 0)
 *
 * Examples:
 *
 *   Time.utc(2000)  # => 2000-01-01 00:00:00 UTC
 *   Time.utc(-2000) # => -2000-01-01 00:00:00 UTC
 *
 * There are no minimum and maximum values for the required argument +year+.
 *
 * For the optional arguments:
 *
 * - +month+: Month in range (1..12), or case-insensitive
 *   3-letter month name:
 *
 *     Time.utc(2000, 1)     # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 12)    # => 2000-12-01 00:00:00 UTC
 *     Time.utc(2000, 'jan') # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 'JAN') # => 2000-01-01 00:00:00 UTC
 *
 * - +mday+: Month day in range(1..31):
 *
 *     Time.utc(2000, 1, 1)  # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 1, 31) # => 2000-01-31 00:00:00 UTC
 *
 * - +hour+: Hour in range (0..23), or 24 if +min+, +sec+, and +usec+
 *   are zero:
 *
 *     Time.utc(2000, 1, 1, 0)  # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 1, 1, 23) # => 2000-01-01 23:00:00 UTC
 *     Time.utc(2000, 1, 1, 24) # => 2000-01-02 00:00:00 UTC
 *
 * - +min+: Minute in range (0..59):
 *
 *     Time.utc(2000, 1, 1, 0, 0)  # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 1, 1, 0, 59) # => 2000-01-01 00:59:00 UTC
 *
 * - +sec+: Second in range (0..59), or 60 if +usec+ is zero:
 *
 *     Time.utc(2000, 1, 1, 0, 0, 0)  # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 1, 1, 0, 0, 59) # => 2000-01-01 00:00:59 UTC
 *     Time.utc(2000, 1, 1, 0, 0, 60) # => 2000-01-01 00:01:00 UTC
 *
 * - +usec+: Microsecond in range (0..999999):
 *
 *     Time.utc(2000, 1, 1, 0, 0, 0, 0)      # => 2000-01-01 00:00:00 UTC
 *     Time.utc(2000, 1, 1, 0, 0, 0, 999999) # => 2000-01-01 00:00:00.999999 UTC
 *
 * The values may be:
 *
 * - Integers, as above.
 * - Numerics convertible to integers:
 *
 *     Time.utc(Float(0.0), Rational(1, 1), 1.0, 0.0, 0.0, 0.0, 0.0)
 *     # => 0000-01-01 00:00:00 UTC
 *
 * - String integers:
 *
 *     a = %w[0 1 1 0 0 0 0 0]
 *     # => ["0", "1", "1", "0", "0", "0", "0", "0"]
 *     Time.utc(*a) # => 0000-01-01 00:00:00 UTC
 *
 * When exactly ten arguments are given,
 * the arguments are interpreted as in the second calling sequence above:
 *
 *   Time.utc(sec, min, hour, mday, month, year, dummy, dummy, dummy, dummy)
 *
 * where the +dummy+ arguments are ignored:
 *
 *   a = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *   # => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
 *   Time.utc(*a) # => 0005-04-03 02:01:00 UTC
 *
 * This form is useful for creating a +Time+ object from a 10-element
 * array returned by Time.to_a:
 *
 *   t = Time.new(2000, 1, 2, 3, 4, 5, 6) # => 2000-01-02 03:04:05 +000006
 *   a = t.to_a   # => [5, 4, 3, 2, 1, 2000, 0, 2, false, nil]
 *   Time.utc(*a) # => 2000-01-02 03:04:05 UTC
 *
 * The two forms have their first six arguments in common,
 * though in different orders;
 * the ranges of these common arguments are the same for both forms; see above.
 *
 * Raises an exception if the number of arguments is eight, nine,
 * or greater than ten.
 *
 * Related: Time.local.
 *
 */
static VALUE
time_s_mkutc(int argc, VALUE *argv, VALUE klass)
{
    struct vtm vtm;

    time_arg(argc, argv, &vtm);
    return time_gmtime(time_new_timew(klass, timegmw(&vtm)));
}

/*
 * call-seq:
 *   Time.local(year, month = 1, mday = 1, hour = 0, min = 0, sec = 0, usec = 0) -> new_time
 *   Time.local(sec, min, hour, mday, month, year, dummy, dummy, dummy, dummy) -> new_time
 *
 * Like Time.utc, except that the returned +Time+ object
 * has the local timezone, not the UTC timezone:
 *
 *   # With seven arguments.
 *   Time.local(0, 1, 2, 3, 4, 5, 6)
 *   # => 0000-01-02 03:04:05.000006 -0600
 *   # With exactly ten arguments.
 *   Time.local(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
 *   # => 0005-04-03 02:01:00 -0600
 *
 */

static VALUE
time_s_mktime(int argc, VALUE *argv, VALUE klass)
{
    struct vtm vtm;

    time_arg(argc, argv, &vtm);
    return time_localtime(time_new_timew(klass, timelocalw(&vtm)));
}

/*
 *  call-seq:
 *    to_i -> integer
 *
 *  Returns the value of +self+ as integer
 *  {Epoch seconds}[rdoc-ref:Time@Epoch+Seconds];
 *  subseconds are truncated (not rounded):
 *
 *    Time.utc(1970, 1, 1, 0, 0, 0).to_i         # => 0
 *    Time.utc(1970, 1, 1, 0, 0, 0, 999999).to_i # => 0
 *    Time.utc(1950, 1, 1, 0, 0, 0).to_i         # => -631152000
 *    Time.utc(1990, 1, 1, 0, 0, 0).to_i         # => 631152000
 *
 *  Related: Time#to_f Time#to_r.
 */

static VALUE
time_to_i(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return w2v(wdiv(tobj->timew, WINT2FIXWV(TIME_SCALE)));
}

/*
 *  call-seq:
 *    to_f -> float
 *
 *  Returns the value of +self+ as a Float number
 *  {Epoch seconds}[rdoc-ref:Time@Epoch+Seconds];
 *  subseconds are included.
 *
 *  The stored value of +self+ is a
 *  {Rational}[rdoc-ref:Rational@#method-i-to_f],
 *  which means that the returned value may be approximate:
 *
 *    Time.utc(1970, 1, 1, 0, 0, 0).to_f         # => 0.0
 *    Time.utc(1970, 1, 1, 0, 0, 0, 999999).to_f # => 0.999999
 *    Time.utc(1950, 1, 1, 0, 0, 0).to_f         # => -631152000.0
 *    Time.utc(1990, 1, 1, 0, 0, 0).to_f         # => 631152000.0
 *
 *  Related: Time#to_i, Time#to_r.
 */

static VALUE
time_to_f(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_Float(rb_time_unmagnify_to_float(tobj->timew));
}

/*
 *  call-seq:
 *    to_r -> rational
 *
 *  Returns the value of +self+ as a Rational exact number of
 *  {Epoch seconds}[rdoc-ref:Time@Epoch+Seconds];
 *
 *    Time.now.to_r # => (16571402750320203/10000000)
 *
 *  Related: Time#to_f, Time#to_i.
 */

static VALUE
time_to_r(VALUE time)
{
    struct time_object *tobj;
    VALUE v;

    GetTimeval(time, tobj);
    v = rb_time_unmagnify_to_rational(tobj->timew);
    if (!RB_TYPE_P(v, T_RATIONAL)) {
        v = rb_Rational1(v);
    }
    return v;
}

/*
 *  call-seq:
 *    usec -> integer
 *
 *  Returns the number of microseconds in the subseconds part of +self+
 *  in the range (0..999_999);
 *  lower-order digits are truncated, not rounded:
 *
 *    t = Time.now # => 2022-07-11 14:59:47.5484697 -0500
 *    t.usec       # => 548469
 *
 *  Related: Time#subsec (returns exact subseconds).
 */

static VALUE
time_usec(VALUE time)
{
    struct time_object *tobj;
    wideval_t w, q, r;

    GetTimeval(time, tobj);

    w = wmod(tobj->timew, WINT2WV(TIME_SCALE));
    wmuldivmod(w, WINT2FIXWV(1000000), WINT2FIXWV(TIME_SCALE), &q, &r);
    return rb_to_int(w2v(q));
}

/*
 *  call-seq:
 *    nsec -> integer
 *
 *  Returns the number of nanoseconds in the subseconds part of +self+
 *  in the range (0..999_999_999);
 *  lower-order digits are truncated, not rounded:
 *
 *    t = Time.now # => 2022-07-11 15:04:53.3219637 -0500
 *    t.nsec       # => 321963700
 *
 *  Related: Time#subsec (returns exact subseconds).
 */

static VALUE
time_nsec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_to_int(w2v(wmulquoll(wmod(tobj->timew, WINT2WV(TIME_SCALE)), 1000000000, TIME_SCALE)));
}

/*
 *  call-seq:
 *    subsec -> numeric
 *
 *  Returns the exact subseconds for +self+ as a Numeric
 *  (Integer or Rational):
 *
 *    t = Time.now # => 2022-07-11 15:11:36.8490302 -0500
 *    t.subsec     # => (4245151/5000000)
 *
 *  If the subseconds is zero, returns integer zero:
 *
 *    t = Time.new(2000, 1, 1, 2, 3, 4) # => 2000-01-01 02:03:04 -0600
 *    t.subsec                          # => 0
 *
 */

static VALUE
time_subsec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return quov(w2v(wmod(tobj->timew, WINT2FIXWV(TIME_SCALE))), INT2FIX(TIME_SCALE));
}

/*
 *  call-seq:
 *    self <=> other_time -> -1, 0, +1, or nil
 *
 *  Compares +self+ with +other_time+; returns:
 *
 *  - +-1+, if +self+ is less than +other_time+.
 *  - +0+, if +self+ is equal to +other_time+.
 *  - +1+, if +self+ is greater then +other_time+.
 *  - +nil+, if +self+ and +other_time+ are incomparable.
 *
 *  Examples:
 *
 *     t = Time.now     # => 2007-11-19 08:12:12 -0600
 *     t2 = t + 2592000 # => 2007-12-19 08:12:12 -0600
 *     t <=> t2         # => -1
 *     t2 <=> t         # => 1
 *
 *     t = Time.now     # => 2007-11-19 08:13:38 -0600
 *     t2 = t + 0.1     # => 2007-11-19 08:13:38 -0600
 *     t.nsec           # => 98222999
 *     t2.nsec          # => 198222999
 *     t <=> t2         # => -1
 *     t2 <=> t         # => 1
 *     t <=> t          # => 0
 *
 */

static VALUE
time_cmp(VALUE time1, VALUE time2)
{
    struct time_object *tobj1, *tobj2;
    int n;

    GetTimeval(time1, tobj1);
    if (IsTimeval(time2)) {
        GetTimeval(time2, tobj2);
        n = wcmp(tobj1->timew, tobj2->timew);
    }
    else {
        return rb_invcmp(time1, time2);
    }
    if (n == 0) return INT2FIX(0);
    if (n > 0) return INT2FIX(1);
    return INT2FIX(-1);
}

/*
 * call-seq:
 *   eql?(other_time)
 *
 * Returns +true+ if +self+ and +other_time+ are
 * both +Time+ objects with the exact same time value.
 */

static VALUE
time_eql(VALUE time1, VALUE time2)
{
    struct time_object *tobj1, *tobj2;

    GetTimeval(time1, tobj1);
    if (IsTimeval(time2)) {
        GetTimeval(time2, tobj2);
        return rb_equal(w2v(tobj1->timew), w2v(tobj2->timew));
    }
    return Qfalse;
}

/*
 *  call-seq:
 *    utc? -> true or false
 *
 *  Returns +true+ if +self+ represents a time in UTC (GMT):
 *
 *    now = Time.now
 *    # => 2022-08-18 10:24:13.5398485 -0500
 *    now.utc? # => false
 *    now.getutc.utc? # => true
 *    utc = Time.utc(2000, 1, 1, 20, 15, 1)
 *    # => 2000-01-01 20:15:01 UTC
 *    utc.utc? # => true
 *
 *  +Time+ objects created with these methods are considered to be in
 *  UTC:
 *
 *  * Time.utc
 *  * Time#utc
 *  * Time#getutc
 *
 *  Objects created in other ways will not be treated as UTC even if
 *  the environment variable "TZ" is "UTC".
 *
 *  Related: Time.utc.
 */

static VALUE
time_utc_p(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return RBOOL(TZMODE_UTC_P(tobj));
}

/*
 * call-seq:
 *   hash -> integer
 *
 * Returns the integer hash code for +self+.
 *
 * Related: Object#hash.
 */

static VALUE
time_hash(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_hash(w2v(tobj->timew));
}

/* :nodoc: */
static VALUE
time_init_copy(VALUE copy, VALUE time)
{
    struct time_object *tobj, *tcopy;

    if (!OBJ_INIT_COPY(copy, time)) return copy;
    GetTimeval(time, tobj);
    GetNewTimeval(copy, tcopy);

    time_set_timew(copy, tcopy, tobj->timew);
    time_set_vtm(copy, tcopy, tobj->vtm);

    return copy;
}

static VALUE
time_dup(VALUE time)
{
    VALUE dup = time_s_alloc(rb_obj_class(time));
    time_init_copy(dup, time);
    return dup;
}

static VALUE
time_localtime(VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm;
    VALUE zone;

    GetTimeval(time, tobj);
    if (TZMODE_LOCALTIME_P(tobj)) {
        if (tobj->vtm.tm_got)
            return time;
    }
    else {
        time_modify(time);
    }

    zone = tobj->vtm.zone;
    if (maybe_tzobj_p(zone) && zone_localtime(zone, time)) {
        return time;
    }

    if (!localtimew(tobj->timew, &vtm))
        rb_raise(rb_eArgError, "localtime error");
    time_set_vtm(time, tobj, vtm);

    tobj->vtm.tm_got = 1;
    TZMODE_SET_LOCALTIME(tobj);
    return time;
}

static VALUE
time_zonelocal(VALUE time, VALUE off)
{
    VALUE zone = off;
    if (zone_localtime(zone, time)) return time;

    if (NIL_P(off = utc_offset_arg(off))) {
        off = zone;
        if (NIL_P(zone = find_timezone(time, off))) invalid_utc_offset(off);
        if (!zone_localtime(zone, time)) invalid_utc_offset(off);
        return time;
    }
    else if (off == UTC_ZONE) {
        return time_gmtime(time);
    }
    validate_utc_offset(off);

    time_set_utc_offset(time, off);
    return time_fixoff(time);
}

/*
 *  call-seq:
 *    localtime -> self or new_time
 *    localtime(zone) -> new_time
 *
 *  With no argument given:
 *
 *  - Returns +self+ if +self+ is a local time.
 *  - Otherwise returns a new +Time+ in the user's local timezone:
 *
 *      t = Time.utc(2000, 1, 1, 20, 15, 1) # => 2000-01-01 20:15:01 UTC
 *      t.localtime                         # => 2000-01-01 14:15:01 -0600
 *
 *  With argument +zone+ given,
 *  returns the new +Time+ object created by converting
 *  +self+ to the given time zone:
 *
 *    t = Time.utc(2000, 1, 1, 20, 15, 1) # => 2000-01-01 20:15:01 UTC
 *    t.localtime("-09:00")               # => 2000-01-01 11:15:01 -0900
 *
 *  For forms of argument +zone+, see
 *  {Timezone Specifiers}[rdoc-ref:Time@Timezone+Specifiers].
 *
 */

static VALUE
time_localtime_m(int argc, VALUE *argv, VALUE time)
{
    VALUE off;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(off = argv[0])) {
        return time_zonelocal(time, off);
    }

    return time_localtime(time);
}

/*
 *  call-seq:
 *    utc -> self
 *
 *  Returns +self+, converted to the UTC timezone:
 *
 *    t = Time.new(2000) # => 2000-01-01 00:00:00 -0600
 *    t.utc?             # => false
 *    t.utc              # => 2000-01-01 06:00:00 UTC
 *    t.utc?             # => true
 *
 *  Related: Time#getutc (returns a new converted +Time+ object).
 */

static VALUE
time_gmtime(VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm;

    GetTimeval(time, tobj);
    if (TZMODE_UTC_P(tobj)) {
        if (tobj->vtm.tm_got)
            return time;
    }
    else {
        time_modify(time);
    }

    vtm.zone = str_utc;
    GMTIMEW(tobj->timew, &vtm);
    time_set_vtm(time, tobj, vtm);

    tobj->vtm.tm_got = 1;
    TZMODE_SET_UTC(tobj);
    return time;
}

static VALUE
time_fixoff(VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm;
    VALUE off, zone;

    GetTimeval(time, tobj);
    if (TZMODE_FIXOFF_P(tobj)) {
       if (tobj->vtm.tm_got)
           return time;
    }
    else {
       time_modify(time);
    }

    if (TZMODE_FIXOFF_P(tobj))
        off = tobj->vtm.utc_offset;
    else
        off = INT2FIX(0);

    GMTIMEW(tobj->timew, &vtm);

    zone = tobj->vtm.zone;
    vtm_add_offset(&vtm, off, +1);

    time_set_vtm(time, tobj, vtm);
    RB_OBJ_WRITE_UNALIGNED(time, &tobj->vtm.zone, zone);

    tobj->vtm.tm_got = 1;
    TZMODE_SET_FIXOFF(time, tobj, off);
    return time;
}

/*
 *  call-seq:
 *    getlocal(zone = nil) -> new_time
 *
 *  Returns a new +Time+ object representing the value of +self+
 *  converted to a given timezone;
 *  if +zone+ is +nil+, the local timezone is used:
 *
 *    t = Time.utc(2000)                    # => 2000-01-01 00:00:00 UTC
 *    t.getlocal                            # => 1999-12-31 18:00:00 -0600
 *    t.getlocal('+12:00')                  # => 2000-01-01 12:00:00 +1200
 *
 *  For forms of argument +zone+, see
 *  {Timezone Specifiers}[rdoc-ref:Time@Timezone+Specifiers].
 *
 */

static VALUE
time_getlocaltime(int argc, VALUE *argv, VALUE time)
{
    VALUE off;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(off = argv[0])) {
        VALUE zone = off;
        if (maybe_tzobj_p(zone)) {
            VALUE t = time_dup(time);
            if (zone_localtime(off, t)) return t;
        }

        if (NIL_P(off = utc_offset_arg(off))) {
            off = zone;
            if (NIL_P(zone = find_timezone(time, off))) invalid_utc_offset(off);
            time = time_dup(time);
            if (!zone_localtime(zone, time)) invalid_utc_offset(off);
            return time;
        }
        else if (off == UTC_ZONE) {
            return time_gmtime(time_dup(time));
        }
        validate_utc_offset(off);

        time = time_dup(time);
        time_set_utc_offset(time, off);
        return time_fixoff(time);
    }

    return time_localtime(time_dup(time));
}

/*
 *  call-seq:
 *    getutc -> new_time
 *
 *  Returns a new +Time+ object representing the value of +self+
 *  converted to the UTC timezone:
 *
 *    local = Time.local(2000) # => 2000-01-01 00:00:00 -0600
 *    local.utc?               # => false
 *    utc = local.getutc       # => 2000-01-01 06:00:00 UTC
 *    utc.utc?                 # => true
 *    utc == local             # => true
 *
 */

static VALUE
time_getgmtime(VALUE time)
{
    return time_gmtime(time_dup(time));
}

static VALUE
time_get_tm(VALUE time, struct time_object *tobj)
{
    if (TZMODE_UTC_P(tobj)) return time_gmtime(time);
    if (TZMODE_FIXOFF_P(tobj)) return time_fixoff(time);
    return time_localtime(time);
}

static VALUE strftime_cstr(const char *fmt, size_t len, VALUE time, rb_encoding *enc);
#define strftimev(fmt, time, enc) strftime_cstr((fmt), rb_strlen_lit(fmt), (time), (enc))

/*
 *  call-seq:
 *    ctime -> string
 *
 *  Returns a string representation of +self+,
 *  formatted by <tt>strftime('%a %b %e %T %Y')</tt>
 *  or its shorthand version <tt>strftime('%c')</tt>;
 *  see {Formats for Dates and Times}[rdoc-ref:strftime_formatting.rdoc]:
 *
 *    t = Time.new(2000, 12, 31, 23, 59, 59, 0.5)
 *    t.ctime                      # => "Sun Dec 31 23:59:59 2000"
 *    t.strftime('%a %b %e %T %Y') # => "Sun Dec 31 23:59:59 2000"
 *    t.strftime('%c')             # => "Sun Dec 31 23:59:59 2000"
 *
 *  Related: Time#to_s, Time#inspect:
 *
 *    t.inspect                    # => "2000-12-31 23:59:59.5 +000001"
 *    t.to_s                       # => "2000-12-31 23:59:59 +0000"
 *
 */

static VALUE
time_asctime(VALUE time)
{
    return strftimev("%a %b %e %T %Y", time, rb_usascii_encoding());
}

/*
 *  call-seq:
 *    to_s    -> string
 *
 *  Returns a string representation of +self+, without subseconds:
 *
 *    t = Time.new(2000, 12, 31, 23, 59, 59, 0.5)
 *    t.to_s    # => "2000-12-31 23:59:59 +0000"
 *
 *  Related: Time#ctime, Time#inspect:
 *
 *    t.ctime   # => "Sun Dec 31 23:59:59 2000"
 *    t.inspect # => "2000-12-31 23:59:59.5 +000001"
 *
 */

static VALUE
time_to_s(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (TZMODE_UTC_P(tobj))
        return strftimev("%Y-%m-%d %H:%M:%S UTC", time, rb_usascii_encoding());
    else
        return strftimev("%Y-%m-%d %H:%M:%S %z", time, rb_usascii_encoding());
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+ with subseconds:
 *
 *    t = Time.new(2000, 12, 31, 23, 59, 59, 0.5)
 *    t.inspect # => "2000-12-31 23:59:59.5 +000001"
 *
 *  Related: Time#ctime, Time#to_s:
 *
 *    t.ctime   # => "Sun Dec 31 23:59:59 2000"
 *    t.to_s    # => "2000-12-31 23:59:59 +0000"
 *
 */

static VALUE
time_inspect(VALUE time)
{
    struct time_object *tobj;
    VALUE str, subsec;

    GetTimeval(time, tobj);
    str = strftimev("%Y-%m-%d %H:%M:%S", time, rb_usascii_encoding());
    subsec = w2v(wmod(tobj->timew, WINT2FIXWV(TIME_SCALE)));
    if (subsec == INT2FIX(0)) {
    }
    else if (FIXNUM_P(subsec) && FIX2LONG(subsec) < TIME_SCALE) {
        long len;
        rb_str_catf(str, ".%09ld", FIX2LONG(subsec));
        for (len=RSTRING_LEN(str); RSTRING_PTR(str)[len-1] == '0' && len > 0; len--)
            ;
        rb_str_resize(str, len);
    }
    else {
        rb_str_cat_cstr(str, " ");
        subsec = quov(subsec, INT2FIX(TIME_SCALE));
        rb_str_concat(str, rb_obj_as_string(subsec));
    }
    if (TZMODE_UTC_P(tobj)) {
        rb_str_cat_cstr(str, " UTC");
    }
    else {
        /* ?TODO: subsecond offset */
        long off = NUM2LONG(rb_funcall(tobj->vtm.utc_offset, rb_intern("round"), 0));
        char sign = (off < 0) ? (off = -off, '-') : '+';
        int sec = off % 60;
        int min = (off /= 60) % 60;
        off /= 60;
        rb_str_catf(str, " %c%.2d%.2d", sign, (int)off, min);
        if (sec) rb_str_catf(str, "%.2d", sec);
    }
    return str;
}

static VALUE
time_add0(VALUE klass, const struct time_object *tobj, VALUE torig, VALUE offset, int sign)
{
    VALUE result;
    struct time_object *result_tobj;

    offset = num_exact(offset);
    if (sign < 0)
        result = time_new_timew(klass, wsub(tobj->timew, rb_time_magnify(v2w(offset))));
    else
        result = time_new_timew(klass, wadd(tobj->timew, rb_time_magnify(v2w(offset))));
    GetTimeval(result, result_tobj);
    TZMODE_COPY(result_tobj, tobj);

    return result;
}

static VALUE
time_add(const struct time_object *tobj, VALUE torig, VALUE offset, int sign)
{
    return time_add0(rb_cTime, tobj, torig, offset, sign);
}

/*
 *  call-seq:
 *    self + numeric -> new_time
 *
 *  Returns a new +Time+ object whose value is the sum of the numeric value
 *  of +self+ and the given +numeric+:
 *
 *    t = Time.new(2000) # => 2000-01-01 00:00:00 -0600
 *    t + (60 * 60 * 24) # => 2000-01-02 00:00:00 -0600
 *    t + 0.5            # => 2000-01-01 00:00:00.5 -0600
 *
 *  Related: Time#-.
 */

static VALUE
time_plus(VALUE time1, VALUE time2)
{
    struct time_object *tobj;
    GetTimeval(time1, tobj);

    if (IsTimeval(time2)) {
        rb_raise(rb_eTypeError, "time + time?");
    }
    return time_add(tobj, time1, time2, 1);
}

/*
 *  call-seq:
 *    self - numeric -> new_time
 *    self - other_time -> float
 *
 *  When +numeric+ is given,
 *  returns a new +Time+ object whose value is the difference
 *  of the numeric value of +self+ and +numeric+:
 *
 *    t = Time.new(2000) # => 2000-01-01 00:00:00 -0600
 *    t - (60 * 60 * 24) # => 1999-12-31 00:00:00 -0600
 *    t - 0.5            # => 1999-12-31 23:59:59.5 -0600
 *
 *  When +other_time+ is given,
 *  returns a Float whose value is the difference
 *  of the numeric values of +self+ and +other_time+ in seconds:
 *
 *    t - t # => 0.0
 *
 *  Related: Time#+.
 */

static VALUE
time_minus(VALUE time1, VALUE time2)
{
    struct time_object *tobj;

    GetTimeval(time1, tobj);
    if (IsTimeval(time2)) {
        struct time_object *tobj2;

        GetTimeval(time2, tobj2);
        return rb_Float(rb_time_unmagnify_to_float(wsub(tobj->timew, tobj2->timew)));
    }
    return time_add(tobj, time1, time2, -1);
}

static VALUE
ndigits_denominator(VALUE ndigits)
{
    long nd = NUM2LONG(ndigits);

    if (nd < 0) {
        rb_raise(rb_eArgError, "negative ndigits given");
    }
    if (nd == 0) {
        return INT2FIX(1);
    }
    return rb_rational_new(INT2FIX(1),
                           rb_int_positive_pow(10, (unsigned long)nd));
}

/*
 * call-seq:
 *   round(ndigits = 0) -> new_time
 *
 * Returns a new +Time+ object whose numeric value is that of +self+,
 * with its seconds value rounded to precision +ndigits+:
 *
 *   t = Time.utc(2010, 3, 30, 5, 43, 25.123456789r)
 *   t          # => 2010-03-30 05:43:25.123456789 UTC
 *   t.round    # => 2010-03-30 05:43:25 UTC
 *   t.round(0) # => 2010-03-30 05:43:25 UTC
 *   t.round(1) # => 2010-03-30 05:43:25.1 UTC
 *   t.round(2) # => 2010-03-30 05:43:25.12 UTC
 *   t.round(3) # => 2010-03-30 05:43:25.123 UTC
 *   t.round(4) # => 2010-03-30 05:43:25.1235 UTC
 *
 *   t = Time.utc(1999, 12,31, 23, 59, 59)
 *   t                # => 1999-12-31 23:59:59 UTC
 *   (t + 0.4).round  # => 1999-12-31 23:59:59 UTC
 *   (t + 0.49).round # => 1999-12-31 23:59:59 UTC
 *   (t + 0.5).round  # => 2000-01-01 00:00:00 UTC
 *   (t + 1.4).round  # => 2000-01-01 00:00:00 UTC
 *   (t + 1.49).round # => 2000-01-01 00:00:00 UTC
 *   (t + 1.5).round  # => 2000-01-01 00:00:01 UTC
 *
 * Related: Time#ceil, Time#floor.
 */

static VALUE
time_round(int argc, VALUE *argv, VALUE time)
{
    VALUE ndigits, v, den;
    struct time_object *tobj;

    if (!rb_check_arity(argc, 0, 1) || NIL_P(ndigits = argv[0]))
        den = INT2FIX(1);
    else
        den = ndigits_denominator(ndigits);

    GetTimeval(time, tobj);
    v = w2v(rb_time_unmagnify(tobj->timew));

    v = modv(v, den);
    if (lt(v, quov(den, INT2FIX(2))))
        return time_add(tobj, time, v, -1);
    else
        return time_add(tobj, time, subv(den, v), 1);
}

/*
 * call-seq:
 *   floor(ndigits = 0) -> new_time
 *
 * Returns a new +Time+ object whose numerical value
 * is less than or equal to +self+ with its seconds
 * truncated to precision +ndigits+:
 *
 *   t = Time.utc(2010, 3, 30, 5, 43, 25.123456789r)
 *   t           # => 2010-03-30 05:43:25.123456789 UTC
 *   t.floor     # => 2010-03-30 05:43:25 UTC
 *   t.floor(2)  # => 2010-03-30 05:43:25.12 UTC
 *   t.floor(4)  # => 2010-03-30 05:43:25.1234 UTC
 *   t.floor(6)  # => 2010-03-30 05:43:25.123456 UTC
 *   t.floor(8)  # => 2010-03-30 05:43:25.12345678 UTC
 *   t.floor(10) # => 2010-03-30 05:43:25.123456789 UTC
 *
 *   t = Time.utc(1999, 12, 31, 23, 59, 59)
 *   t               # => 1999-12-31 23:59:59 UTC
 *   (t + 0.4).floor # => 1999-12-31 23:59:59 UTC
 *   (t + 0.9).floor # => 1999-12-31 23:59:59 UTC
 *   (t + 1.4).floor # => 2000-01-01 00:00:00 UTC
 *   (t + 1.9).floor # => 2000-01-01 00:00:00 UTC
 *
 * Related: Time#ceil, Time#round.
 */

static VALUE
time_floor(int argc, VALUE *argv, VALUE time)
{
    VALUE ndigits, v, den;
    struct time_object *tobj;

    if (!rb_check_arity(argc, 0, 1) || NIL_P(ndigits = argv[0]))
        den = INT2FIX(1);
    else
        den = ndigits_denominator(ndigits);

    GetTimeval(time, tobj);
    v = w2v(rb_time_unmagnify(tobj->timew));

    v = modv(v, den);
    return time_add(tobj, time, v, -1);
}

/*
 * call-seq:
 *   ceil(ndigits = 0)   -> new_time
 *
 * Returns a new +Time+ object whose numerical value
 * is greater than or equal to +self+ with its seconds
 * truncated to precision +ndigits+:
 *
 *   t = Time.utc(2010, 3, 30, 5, 43, 25.123456789r)
 *   t          # => 2010-03-30 05:43:25.123456789 UTC
 *   t.ceil     # => 2010-03-30 05:43:26 UTC
 *   t.ceil(2)  # => 2010-03-30 05:43:25.13 UTC
 *   t.ceil(4)  # => 2010-03-30 05:43:25.1235 UTC
 *   t.ceil(6)  # => 2010-03-30 05:43:25.123457 UTC
 *   t.ceil(8)  # => 2010-03-30 05:43:25.12345679 UTC
 *   t.ceil(10) # => 2010-03-30 05:43:25.123456789 UTC
 *
 *   t = Time.utc(1999, 12, 31, 23, 59, 59)
 *   t              # => 1999-12-31 23:59:59 UTC
 *   (t + 0.4).ceil # => 2000-01-01 00:00:00 UTC
 *   (t + 0.9).ceil # => 2000-01-01 00:00:00 UTC
 *   (t + 1.4).ceil # => 2000-01-01 00:00:01 UTC
 *   (t + 1.9).ceil # => 2000-01-01 00:00:01 UTC
 *
 * Related: Time#floor, Time#round.
 */

static VALUE
time_ceil(int argc, VALUE *argv, VALUE time)
{
    VALUE ndigits, v, den;
    struct time_object *tobj;

    if (!rb_check_arity(argc, 0, 1) || NIL_P(ndigits = argv[0]))
        den = INT2FIX(1);
    else
        den = ndigits_denominator(ndigits);

    GetTimeval(time, tobj);
    v = w2v(rb_time_unmagnify(tobj->timew));

    v = modv(v, den);
    if (!rb_equal(v, INT2FIX(0))) {
        v = subv(den, v);
    }
    return time_add(tobj, time, v, 1);
}

/*
 *  call-seq:
 *    sec -> integer
 *
 *  Returns the integer second of the minute for +self+,
 *  in range (0..60):
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.sec # => 5
 *
 *  Note: the second value may be 60 when there is a
 *  {leap second}[https://en.wikipedia.org/wiki/Leap_second].
 *
 *  Related: Time#year, Time#mon, Time#min.
 */

static VALUE
time_sec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.sec);
}

/*
 *  call-seq:
 *    min -> integer
 *
 *  Returns the integer minute of the hour for +self+,
 *  in range (0..59):
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.min # => 4
 *
 *  Related: Time#year, Time#mon, Time#sec.
 */

static VALUE
time_min(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.min);
}

/*
 *  call-seq:
 *    hour -> integer
 *
 *  Returns the integer hour of the day for +self+,
 *  in range (0..23):
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.hour # => 3
 *
 *  Related: Time#year, Time#mon, Time#min.
 */

static VALUE
time_hour(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.hour);
}

/*
 *  call-seq:
 *    mday -> integer
 *
 *  Returns the integer day of the month for +self+,
 *  in range (1..31):
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.mday # => 2
 *
 *  Related: Time#year, Time#hour, Time#min.
 */

static VALUE
time_mday(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.mday);
}

/*
 *  call-seq:
 *    mon -> integer
 *
 *  Returns the integer month of the year for +self+,
 *  in range (1..12):
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.mon # => 1
 *
 *  Related: Time#year, Time#hour, Time#min.
 */

static VALUE
time_mon(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.mon);
}

/*
 *  call-seq:
 *    year -> integer
 *
 *  Returns the integer year for +self+:
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.year # => 2000
 *
 *  Related: Time#mon, Time#hour, Time#min.
 */

static VALUE
time_year(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return tobj->vtm.year;
}

/*
 *  call-seq:
 *    wday -> integer
 *
 *  Returns the integer day of the week for +self+,
 *  in range (0..6), with Sunday as zero.
 *
 *    t = Time.new(2000, 1, 2, 3, 4, 5, 6)
 *    # => 2000-01-02 03:04:05 +000006
 *    t.wday    # => 0
 *    t.sunday? # => true
 *
 *  Related: Time#year, Time#hour, Time#min.
 */

static VALUE
time_wday(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM_ENSURE(time, tobj, tobj->vtm.wday != VTM_WDAY_INITVAL);
    return INT2FIX((int)tobj->vtm.wday);
}

#define wday_p(n) {\
    return RBOOL(time_wday(time) == INT2FIX(n)); \
}

/*
 *  call-seq:
 *    sunday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Sunday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 2) # => 2000-01-02 00:00:00 UTC
 *    t.sunday?                # => true
 *
 *  Related: Time#monday?, Time#tuesday?, Time#wednesday?.
 */

static VALUE
time_sunday(VALUE time)
{
    wday_p(0);
}

/*
 *  call-seq:
 *    monday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Monday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 3) # => 2000-01-03 00:00:00 UTC
 *    t.monday?                # => true
 *
 *  Related: Time#tuesday?, Time#wednesday?, Time#thursday?.
 */

static VALUE
time_monday(VALUE time)
{
    wday_p(1);
}

/*
 *  call-seq:
 *    tuesday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Tuesday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 4) # => 2000-01-04 00:00:00 UTC
 *    t.tuesday?               # => true
 *
 *  Related: Time#wednesday?, Time#thursday?, Time#friday?.
 */

static VALUE
time_tuesday(VALUE time)
{
    wday_p(2);
}

/*
 *  call-seq:
 *    wednesday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Wednesday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 5) # => 2000-01-05 00:00:00 UTC
 *    t.wednesday?             # => true
 *
 *  Related: Time#thursday?, Time#friday?, Time#saturday?.
 */

static VALUE
time_wednesday(VALUE time)
{
    wday_p(3);
}

/*
 *  call-seq:
 *    thursday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Thursday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 6) # => 2000-01-06 00:00:00 UTC
 *    t.thursday?              # => true
 *
 *  Related: Time#friday?, Time#saturday?, Time#sunday?.
 */

static VALUE
time_thursday(VALUE time)
{
    wday_p(4);
}

/*
 *  call-seq:
 *    friday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Friday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 7) # => 2000-01-07 00:00:00 UTC
 *    t.friday?                # => true
 *
 *  Related: Time#saturday?, Time#sunday?, Time#monday?.
 */

static VALUE
time_friday(VALUE time)
{
    wday_p(5);
}

/*
 *  call-seq:
 *    saturday? -> true or false
 *
 *  Returns +true+ if +self+ represents a Saturday, +false+ otherwise:
 *
 *    t = Time.utc(2000, 1, 1) # => 2000-01-01 00:00:00 UTC
 *    t.saturday?              # => true
 *
 *  Related: Time#sunday?, Time#monday?, Time#tuesday?.
 */

static VALUE
time_saturday(VALUE time)
{
    wday_p(6);
}

/*
 *  call-seq:
 *    yday -> integer
 *
 *  Returns the integer day of the year of +self+, in range (1..366).
 *
 *    Time.new(2000, 1, 1).yday   # => 1
 *    Time.new(2000, 12, 31).yday # => 366
 */

static VALUE
time_yday(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM_ENSURE(time, tobj, tobj->vtm.yday != 0);
    return INT2FIX(tobj->vtm.yday);
}

/*
 *  call-seq:
 *    dst?  -> true or false
 *
 *  Returns +true+ if +self+ is in daylight saving time, +false+ otherwise:
 *
 *    t = Time.local(2000, 1, 1) # => 2000-01-01 00:00:00 -0600
 *    t.zone                     # => "Central Standard Time"
 *    t.dst?                     # => false
 *    t = Time.local(2000, 7, 1) # => 2000-07-01 00:00:00 -0500
 *    t.zone                     # => "Central Daylight Time"
 *    t.dst?                     # => true
 *
 */

static VALUE
time_isdst(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    if (tobj->vtm.isdst == VTM_ISDST_INITVAL) {
        rb_raise(rb_eRuntimeError, "isdst is not set yet");
    }
    return RBOOL(tobj->vtm.isdst);
}

/*
 *  call-seq:
 *     time.zone -> string or timezone
 *
 *  Returns the string name of the time zone for +self+:
 *
 *    Time.utc(2000, 1, 1).zone # => "UTC"
 *    Time.new(2000, 1, 1).zone # => "Central Standard Time"
 */

static VALUE
time_zone(VALUE time)
{
    struct time_object *tobj;
    VALUE zone;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);

    if (TZMODE_UTC_P(tobj)) {
        return rb_usascii_str_new_cstr("UTC");
    }
    zone = tobj->vtm.zone;
    if (NIL_P(zone))
        return Qnil;

    if (RB_TYPE_P(zone, T_STRING))
        zone = rb_str_dup(zone);
    return zone;
}

/*
 *  call-seq:
 *    utc_offset -> integer
 *
 *  Returns the offset in seconds between the timezones of UTC and +self+:
 *
 *    Time.utc(2000, 1, 1).utc_offset   # => 0
 *    Time.local(2000, 1, 1).utc_offset # => -21600 # -6*3600, or minus six hours.
 *
 */

VALUE
rb_time_utc_offset(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);

    if (TZMODE_UTC_P(tobj)) {
        return INT2FIX(0);
    }
    else {
        MAKE_TM(time, tobj);
        return tobj->vtm.utc_offset;
    }
}

/*
 *  call-seq:
 *    to_a -> array
 *
 *  Returns a 10-element array of values representing +self+:
 *
 *    Time.utc(2000, 1, 1).to_a
 *    # => [0,   0,   0,    1,   1,   2000, 6,    1,    false, "UTC"]
 *    #    [sec, min, hour, day, mon, year, wday, yday, dst?,   zone]
 *
 *  The returned array is suitable for use as an argument to Time.utc or Time.local
 *  to create a new +Time+ object.
 *
 */

static VALUE
time_to_a(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM_ENSURE(time, tobj, tobj->vtm.yday != 0);
    return rb_ary_new3(10,
                    INT2FIX(tobj->vtm.sec),
                    INT2FIX(tobj->vtm.min),
                    INT2FIX(tobj->vtm.hour),
                    INT2FIX(tobj->vtm.mday),
                    INT2FIX(tobj->vtm.mon),
                    tobj->vtm.year,
                    INT2FIX(tobj->vtm.wday),
                    INT2FIX(tobj->vtm.yday),
                    RBOOL(tobj->vtm.isdst),
                    time_zone(time));
}

/*
 *  call-seq:
 *    deconstruct_keys(array_of_names_or_nil) -> hash
 *
 *  Returns a hash of the name/value pairs, to use in pattern matching.
 *  Possible keys are: <tt>:year</tt>, <tt>:month</tt>, <tt>:day</tt>,
 *  <tt>:yday</tt>, <tt>:wday</tt>, <tt>:hour</tt>, <tt>:min</tt>, <tt>:sec</tt>,
 *  <tt>:subsec</tt>, <tt>:dst</tt>, <tt>:zone</tt>.
 *
 *  Possible usages:
 *
 *    t = Time.utc(2022, 10, 5, 21, 25, 30)
 *
 *    if t in wday: 3, day: ..7  # uses deconstruct_keys underneath
 *      puts "first Wednesday of the month"
 *    end
 *    #=> prints "first Wednesday of the month"
 *
 *    case t
 *    in year: ...2022
 *      puts "too old"
 *    in month: ..9
 *      puts "quarter 1-3"
 *    in wday: 1..5, month:
 *      puts "working day in month #{month}"
 *    end
 *    #=> prints "working day in month 10"
 *
 *  Note that deconstruction by pattern can also be combined with class check:
 *
 *    if t in Time(wday: 3, day: ..7)
 *      puts "first Wednesday of the month"
 *    end
 *
 */
static VALUE
time_deconstruct_keys(VALUE time, VALUE keys)
{
    struct time_object *tobj;
    VALUE h;
    long i;

    GetTimeval(time, tobj);
    MAKE_TM_ENSURE(time, tobj, tobj->vtm.yday != 0);

    if (NIL_P(keys)) {
        h = rb_hash_new_with_size(11);

        rb_hash_aset(h, sym_year, tobj->vtm.year);
        rb_hash_aset(h, sym_month, INT2FIX(tobj->vtm.mon));
        rb_hash_aset(h, sym_day, INT2FIX(tobj->vtm.mday));
        rb_hash_aset(h, sym_yday, INT2FIX(tobj->vtm.yday));
        rb_hash_aset(h, sym_wday, INT2FIX(tobj->vtm.wday));
        rb_hash_aset(h, sym_hour, INT2FIX(tobj->vtm.hour));
        rb_hash_aset(h, sym_min, INT2FIX(tobj->vtm.min));
        rb_hash_aset(h, sym_sec, INT2FIX(tobj->vtm.sec));
        rb_hash_aset(h, sym_subsec,
                     quov(w2v(wmod(tobj->timew, WINT2FIXWV(TIME_SCALE))), INT2FIX(TIME_SCALE)));
        rb_hash_aset(h, sym_dst, RBOOL(tobj->vtm.isdst));
        rb_hash_aset(h, sym_zone, time_zone(time));

        return h;
    }
    if (UNLIKELY(!RB_TYPE_P(keys, T_ARRAY))) {
        rb_raise(rb_eTypeError,
                 "wrong argument type %"PRIsVALUE" (expected Array or nil)",
                 rb_obj_class(keys));

    }

    h = rb_hash_new_with_size(RARRAY_LEN(keys));

    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE key = RARRAY_AREF(keys, i);

        if (sym_year == key) rb_hash_aset(h, key, tobj->vtm.year);
        if (sym_month == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.mon));
        if (sym_day == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.mday));
        if (sym_yday == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.yday));
        if (sym_wday == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.wday));
        if (sym_hour == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.hour));
        if (sym_min == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.min));
        if (sym_sec == key) rb_hash_aset(h, key, INT2FIX(tobj->vtm.sec));
        if (sym_subsec == key) {
            rb_hash_aset(h, key, quov(w2v(wmod(tobj->timew, WINT2FIXWV(TIME_SCALE))), INT2FIX(TIME_SCALE)));
        }
        if (sym_dst == key) rb_hash_aset(h, key, RBOOL(tobj->vtm.isdst));
        if (sym_zone == key) rb_hash_aset(h, key, time_zone(time));
    }
    return h;
}

static VALUE
rb_strftime_alloc(const char *format, size_t format_len, rb_encoding *enc,
                  VALUE time, struct vtm *vtm, wideval_t timew, int gmt)
{
    VALUE timev = Qnil;
    struct timespec ts;

    if (!timew2timespec_exact(timew, &ts))
        timev = w2v(rb_time_unmagnify(timew));

    if (NIL_P(timev)) {
        return rb_strftime_timespec(format, format_len, enc, time, vtm, &ts, gmt);
    }
    else {
        return rb_strftime(format, format_len, enc, time, vtm, timev, gmt);
    }
}

static VALUE
strftime_cstr(const char *fmt, size_t len, VALUE time, rb_encoding *enc)
{
    struct time_object *tobj;
    VALUE str;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    str = rb_strftime_alloc(fmt, len, enc, time, &tobj->vtm, tobj->timew, TZMODE_UTC_P(tobj));
    if (!str) rb_raise(rb_eArgError, "invalid format: %s", fmt);
    return str;
}

/*
 *  call-seq:
 *    strftime(format_string) -> string
 *
 *  Returns a string representation of +self+,
 *  formatted according to the given string +format+.
 *  See {Formats for Dates and Times}[rdoc-ref:strftime_formatting.rdoc].
 */

static VALUE
time_strftime(VALUE time, VALUE format)
{
    struct time_object *tobj;
    const char *fmt;
    long len;
    rb_encoding *enc;
    VALUE tmp;

    GetTimeval(time, tobj);
    MAKE_TM_ENSURE(time, tobj, tobj->vtm.yday != 0);
    StringValue(format);
    if (!rb_enc_str_asciicompat_p(format)) {
        rb_raise(rb_eArgError, "format should have ASCII compatible encoding");
    }
    tmp = rb_str_tmp_frozen_acquire(format);
    fmt = RSTRING_PTR(tmp);
    len = RSTRING_LEN(tmp);
    enc = rb_enc_get(format);
    if (len == 0) {
        rb_warning("strftime called with empty format string");
        return rb_enc_str_new(0, 0, enc);
    }
    else {
        VALUE str = rb_strftime_alloc(fmt, len, enc, time, &tobj->vtm, tobj->timew,
                                      TZMODE_UTC_P(tobj));
        rb_str_tmp_frozen_release(format, tmp);
        if (!str) rb_raise(rb_eArgError, "invalid format: %"PRIsVALUE, format);
        return str;
    }
}

/*
 *  call-seq:
 *    xmlschema(fraction_digits=0) -> string
 *
 *  Returns a string which represents the time as a dateTime defined by XML
 *  Schema:
 *
 *    CCYY-MM-DDThh:mm:ssTZD
 *    CCYY-MM-DDThh:mm:ss.sssTZD
 *
 *  where TZD is Z or [+-]hh:mm.
 *
 *  If self is a UTC time, Z is used as TZD.  [+-]hh:mm is used otherwise.
 *
 *  +fraction_digits+ specifies a number of digits to use for fractional
 *  seconds.  Its default value is 0.
 *
 *      t = Time.now
 *      t.xmlschema  # => "2011-10-05T22:26:12-04:00"
 */

static VALUE
time_xmlschema(int argc, VALUE *argv, VALUE time)
{
    long fraction_digits = 0;
    rb_check_arity(argc, 0, 1);
    if (argc > 0) {
        fraction_digits = NUM2LONG(argv[0]);
        if (fraction_digits < 0) {
            fraction_digits = 0;
        }
    }

    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);

    const long size_after_year = sizeof("-MM-DDTHH:MM:SS+ZH:ZM") + fraction_digits
        + (fraction_digits > 0);
    VALUE str;
    char *ptr;

# define fill_digits_long(len, prec, n) \
    for (int fill_it = 1, written = snprintf(ptr, len, "%0*ld", prec, n); \
         fill_it; ptr += written, fill_it = 0)

    if (FIXNUM_P(tobj->vtm.year)) {
        long year = FIX2LONG(tobj->vtm.year);
        int year_width = (year < 0) + rb_strlen_lit("YYYY");
        int w = (year >= -9999 && year <= 9999 ? year_width : (year < 0) + (int)DECIMAL_SIZE_OF(year));
        str = rb_usascii_str_new(0, w + size_after_year);
        ptr = RSTRING_PTR(str);
        fill_digits_long(w + 1, year_width, year) {
            if (year >= -9999 && year <= 9999) {
                RUBY_ASSERT(written == year_width);
            }
            else {
                RUBY_ASSERT(written >= year_width);
                RUBY_ASSERT(written <= w);
            }
        }
    }
    else {
        str = rb_int2str(tobj->vtm.year, 10);
        rb_str_modify_expand(str, size_after_year);
        ptr = RSTRING_END(str);
    }

# define fill_2(c, n) (*ptr++ = c, *ptr++ = '0' + (n) / 10, *ptr++ = '0' + (n) % 10)
    fill_2('-', tobj->vtm.mon);
    fill_2('-', tobj->vtm.mday);
    fill_2('T', tobj->vtm.hour);
    fill_2(':', tobj->vtm.min);
    fill_2(':', tobj->vtm.sec);

    if (fraction_digits > 0) {
        VALUE subsecx = tobj->vtm.subsecx;
        long subsec;
        int digits = -1;
        *ptr++ = '.';
        if (fraction_digits <= TIME_SCALE_NUMDIGITS) {
            digits = TIME_SCALE_NUMDIGITS - (int)fraction_digits;
        }
        else {
            long w = fraction_digits - TIME_SCALE_NUMDIGITS; /* > 0 */
            subsecx = mulv(subsecx, rb_int_positive_pow(10, (unsigned long)w));
            if (!RB_INTEGER_TYPE_P(subsecx)) { /* maybe Rational */
                subsecx = rb_Integer(subsecx);
            }
            if (FIXNUM_P(subsecx)) digits = 0;
        }
        if (digits >= 0 && fraction_digits < INT_MAX) {
            subsec = NUM2LONG(subsecx);
            if (digits > 0) subsec /= (long)pow(10, digits);
            fill_digits_long(fraction_digits + 1, (int)fraction_digits, subsec) {
                RUBY_ASSERT(written == (int)fraction_digits);
            }
        }
        else {
            subsecx = rb_int2str(subsecx, 10);
            long len = RSTRING_LEN(subsecx);
            if (fraction_digits > len) {
                memset(ptr, '0', fraction_digits - len);
            }
            else {
                len = fraction_digits;
            }
            ptr += fraction_digits;
            memcpy(ptr - len, RSTRING_PTR(subsecx), len);
        }
    }

    if (TZMODE_UTC_P(tobj)) {
        *ptr = 'Z';
        ptr++;
    }
    else {
        long offset = NUM2LONG(rb_time_utc_offset(time));
        char sign = offset < 0 ? '-' : '+';
        if (offset < 0) offset = -offset;
        offset /= 60;
        fill_2(sign, offset / 60);
        fill_2(':', offset % 60);
    }
    const char *const start = RSTRING_PTR(str);
    rb_str_set_len(str, ptr - start); // We could skip coderange scanning as we know it's full ASCII.
    return str;
}

int ruby_marshal_write_long(long x, char *buf);

enum {base_dump_size = 8};

/* :nodoc: */
static VALUE
time_mdump(VALUE time)
{
    struct time_object *tobj;
    unsigned long p, s;
    char buf[base_dump_size + sizeof(long) + 1];
    int i;
    VALUE str;

    struct vtm vtm;
    long year;
    long usec, nsec;
    VALUE subsecx, nano, subnano, v, zone;

    VALUE year_extend = Qnil;
    const int max_year = 1900+0xffff;

    GetTimeval(time, tobj);

    gmtimew(tobj->timew, &vtm);

    if (FIXNUM_P(vtm.year)) {
        year = FIX2LONG(vtm.year);
        if (year > max_year) {
            year_extend = INT2FIX(year - max_year);
            year = max_year;
        }
        else if (year < 1900) {
            year_extend = LONG2NUM(1900 - year);
            year = 1900;
        }
    }
    else {
        if (rb_int_positive_p(vtm.year)) {
            year_extend = rb_int_minus(vtm.year, INT2FIX(max_year));
            year = max_year;
        }
        else {
            year_extend = rb_int_minus(INT2FIX(1900), vtm.year);
            year = 1900;
        }
    }

    subsecx = vtm.subsecx;

    nano = mulquov(subsecx, INT2FIX(1000000000), INT2FIX(TIME_SCALE));
    divmodv(nano, INT2FIX(1), &v, &subnano);
    nsec = FIX2LONG(v);
    usec = nsec / 1000;
    nsec = nsec % 1000;

    nano = addv(LONG2FIX(nsec), subnano);

    p = 0x1UL            << 31 | /*  1 */
        TZMODE_UTC_P(tobj) << 30 | /*  1 */
        (year-1900)      << 14 | /* 16 */
        (vtm.mon-1)      << 10 | /*  4 */
        vtm.mday         <<  5 | /*  5 */
        vtm.hour;                /*  5 */
    s = (unsigned long)vtm.min << 26 | /*  6 */
        vtm.sec          << 20 | /*  6 */
        usec;    /* 20 */

    for (i=0; i<4; i++) {
        buf[i] = (unsigned char)p;
        p = RSHIFT(p, 8);
    }
    for (i=4; i<8; i++) {
        buf[i] = (unsigned char)s;
        s = RSHIFT(s, 8);
    }

    if (!NIL_P(year_extend)) {
        /*
         * Append extended year distance from 1900..(1900+0xffff).  In
         * each cases, there is no sign as the value is positive.  The
         * format is length (marshaled long) + little endian packed
         * binary (like as Integer).
         */
        size_t ysize = rb_absint_size(year_extend, NULL);
        char *p, *const buf_year_extend = buf + base_dump_size;
        if (ysize > LONG_MAX ||
            (i = ruby_marshal_write_long((long)ysize, buf_year_extend)) < 0) {
            rb_raise(rb_eArgError, "year too %s to marshal: %"PRIsVALUE" UTC",
                     (year == 1900 ? "small" : "big"), vtm.year);
        }
        i += base_dump_size;
        str = rb_str_new(NULL, i + ysize);
        p = RSTRING_PTR(str);
        memcpy(p, buf, i);
        p += i;
        rb_integer_pack(year_extend, p, ysize, 1, 0, INTEGER_PACK_LITTLE_ENDIAN);
    }
    else {
        str = rb_str_new(buf, base_dump_size);
    }
    rb_copy_generic_ivar(str, time);
    if (!rb_equal(nano, INT2FIX(0))) {
        if (RB_TYPE_P(nano, T_RATIONAL)) {
            rb_ivar_set(str, id_nano_num, RRATIONAL(nano)->num);
            rb_ivar_set(str, id_nano_den, RRATIONAL(nano)->den);
        }
        else {
            rb_ivar_set(str, id_nano_num, nano);
            rb_ivar_set(str, id_nano_den, INT2FIX(1));
        }
    }
    if (nsec) { /* submicro is only for Ruby 1.9.1 compatibility */
        /*
         * submicro is formatted in fixed-point packed BCD (without sign).
         * It represent digits under microsecond.
         * For nanosecond resolution, 3 digits (2 bytes) are used.
         * However it can be longer.
         * Extra digits are ignored for loading.
         */
        char buf[2];
        int len = (int)sizeof(buf);
        buf[1] = (char)((nsec % 10) << 4);
        nsec /= 10;
        buf[0] = (char)(nsec % 10);
        nsec /= 10;
        buf[0] |= (char)((nsec % 10) << 4);
        if (buf[1] == 0)
            len = 1;
        rb_ivar_set(str, id_submicro, rb_str_new(buf, len));
    }
    if (!TZMODE_UTC_P(tobj)) {
        VALUE off = rb_time_utc_offset(time), div, mod;
        divmodv(off, INT2FIX(1), &div, &mod);
        if (rb_equal(mod, INT2FIX(0)))
            off = rb_Integer(div);
        rb_ivar_set(str, id_offset, off);
    }
    zone = tobj->vtm.zone;
    if (maybe_tzobj_p(zone)) {
        zone = rb_funcallv(zone, id_name, 0, 0);
    }
    rb_ivar_set(str, id_zone, zone);
    return str;
}

/* :nodoc: */
static VALUE
time_dump(int argc, VALUE *argv, VALUE time)
{
    VALUE str;

    rb_check_arity(argc, 0, 1);
    str = time_mdump(time);

    return str;
}

static VALUE
mload_findzone(VALUE arg)
{
    VALUE *argp = (VALUE *)arg;
    VALUE time = argp[0], zone = argp[1];
    return find_timezone(time, zone);
}

static VALUE
mload_zone(VALUE time, VALUE zone)
{
    VALUE z, args[2];
    args[0] = time;
    args[1] = zone;
    z = rb_rescue(mload_findzone, (VALUE)args, 0, Qnil);
    if (NIL_P(z)) return rb_fstring(zone);
    if (RB_TYPE_P(z, T_STRING)) return rb_fstring(z);
    return z;
}

long ruby_marshal_read_long(const char **buf, long len);

/* :nodoc: */
static VALUE
time_mload(VALUE time, VALUE str)
{
    struct time_object *tobj;
    unsigned long p, s;
    time_t sec;
    long usec;
    unsigned char *buf;
    struct vtm vtm;
    int i, gmt;
    long nsec;
    VALUE submicro, nano_num, nano_den, offset, zone, year;
    wideval_t timew;

    time_modify(time);

#define get_attr(attr, iffound) \
    attr = rb_attr_delete(str, id_##attr); \
    if (!NIL_P(attr)) { \
        iffound; \
    }

    get_attr(nano_num, {});
    get_attr(nano_den, {});
    get_attr(submicro, {});
    get_attr(offset, (offset = rb_rescue(validate_utc_offset, offset, 0, Qnil)));
    get_attr(zone, (zone = rb_rescue(validate_zone_name, zone, 0, Qnil)));
    get_attr(year, {});

#undef get_attr

    rb_copy_generic_ivar(time, str);

    StringValue(str);
    buf = (unsigned char *)RSTRING_PTR(str);
    if (RSTRING_LEN(str) < base_dump_size) {
        goto invalid_format;
    }

    p = s = 0;
    for (i=0; i<4; i++) {
        p |= (unsigned long)buf[i]<<(8*i);
    }
    for (i=4; i<8; i++) {
        s |= (unsigned long)buf[i]<<(8*(i-4));
    }

    if ((p & (1UL<<31)) == 0) {
        gmt = 0;
        offset = Qnil;
        sec = p;
        usec = s;
        nsec = usec * 1000;
        timew = wadd(rb_time_magnify(TIMET2WV(sec)), wmulquoll(WINT2FIXWV(usec), TIME_SCALE, 1000000));
    }
    else {
        p &= ~(1UL<<31);
        gmt        = (int)((p >> 30) & 0x1);

        if (NIL_P(year)) {
            year = INT2FIX(((int)(p >> 14) & 0xffff) + 1900);
        }
        if (RSTRING_LEN(str) > base_dump_size) {
            long len = RSTRING_LEN(str) - base_dump_size;
            long ysize = 0;
            VALUE year_extend;
            const char *ybuf = (const char *)(buf += base_dump_size);
            ysize = ruby_marshal_read_long(&ybuf, len);
            len -= ybuf - (const char *)buf;
            if (ysize < 0 || ysize > len) goto invalid_format;
            year_extend = rb_integer_unpack(ybuf, ysize, 1, 0, INTEGER_PACK_LITTLE_ENDIAN);
            if (year == INT2FIX(1900)) {
                year = rb_int_minus(year, year_extend);
            }
            else {
                year = rb_int_plus(year, year_extend);
            }
        }
        unsigned int mon = ((int)(p >> 10) & 0xf); /* 0...12 */
        if (mon >= 12) {
            mon -= 12;
            year = addv(year, LONG2FIX(1));
        }
        vtm.year = year;
        vtm.mon  = mon + 1;
        vtm.mday = (int)(p >>  5) & 0x1f;
        vtm.hour = (int) p        & 0x1f;
        vtm.min  = (int)(s >> 26) & 0x3f;
        vtm.sec  = (int)(s >> 20) & 0x3f;
        vtm.utc_offset = INT2FIX(0);
        vtm.yday = vtm.wday = 0;
        vtm.isdst = 0;
        vtm.zone = str_empty;

        usec = (long)(s & 0xfffff);
        nsec = usec * 1000;


        vtm.subsecx = mulquov(LONG2FIX(nsec), INT2FIX(TIME_SCALE), LONG2FIX(1000000000));
        if (nano_num != Qnil) {
            VALUE nano = quov(num_exact(nano_num), num_exact(nano_den));
            vtm.subsecx = addv(vtm.subsecx, mulquov(nano, INT2FIX(TIME_SCALE), LONG2FIX(1000000000)));
        }
        else if (submicro != Qnil) { /* for Ruby 1.9.1 compatibility */
            unsigned char *ptr;
            long len;
            int digit;
            ptr = (unsigned char*)StringValuePtr(submicro);
            len = RSTRING_LEN(submicro);
            nsec = 0;
            if (0 < len) {
                if (10 <= (digit = ptr[0] >> 4)) goto end_submicro;
                nsec += digit * 100;
                if (10 <= (digit = ptr[0] & 0xf)) goto end_submicro;
                nsec += digit * 10;
            }
            if (1 < len) {
                if (10 <= (digit = ptr[1] >> 4)) goto end_submicro;
                nsec += digit;
            }
            vtm.subsecx = addv(vtm.subsecx, mulquov(LONG2FIX(nsec), INT2FIX(TIME_SCALE), LONG2FIX(1000000000)));
end_submicro: ;
        }
        timew = timegmw(&vtm);
    }

    GetNewTimeval(time, tobj);
    TZMODE_SET_LOCALTIME(tobj);
    tobj->vtm.tm_got = 0;
    time_set_timew(time, tobj, timew);

    if (gmt) {
        TZMODE_SET_UTC(tobj);
    }
    else if (!NIL_P(offset)) {
        time_set_utc_offset(time, offset);
        time_fixoff(time);
    }
    if (!NIL_P(zone)) {
        zone = mload_zone(time, zone);
        RB_OBJ_WRITE(time, &tobj->vtm.zone, zone);
        zone_localtime(zone, time);
    }

    return time;

  invalid_format:
    rb_raise(rb_eTypeError, "marshaled time format differ");
    UNREACHABLE_RETURN(Qundef);
}

/* :nodoc: */
static VALUE
time_load(VALUE klass, VALUE str)
{
    VALUE time = time_s_alloc(klass);

    time_mload(time, str);
    return time;
}

/* :nodoc:*/
/* Document-class: Time::tm
 *
 * A container class for timezone conversion.
 */

/*
 * call-seq:
 *   Time::tm.from_time(t) -> tm
 *
 * Creates new Time::tm object from a Time object.
 */

static VALUE
tm_from_time(VALUE klass, VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm, *v;
    VALUE tm;
    struct time_object *ttm;

    GetTimeval(time, tobj);
    tm = time_s_alloc(klass);
    ttm = RTYPEDDATA_GET_DATA(tm);
    v = &vtm;

    WIDEVALUE timew = tobj->timew;
    GMTIMEW(timew, v);
    time_set_timew(tm, ttm, wsub(timew, v->subsecx));
    v->subsecx = INT2FIX(0);
    v->zone = Qnil;
    time_set_vtm(tm, ttm, *v);

    ttm->vtm.tm_got = 1;
    TZMODE_SET_UTC(ttm);
    return tm;
}

/*
 * call-seq:
 *   Time::tm.new(year, month=nil, day=nil, hour=nil, min=nil, sec=nil, zone=nil) -> tm
 *
 * Creates new Time::tm object.
 */

static VALUE
tm_initialize(int argc, VALUE *argv, VALUE time)
{
    struct vtm vtm;
    wideval_t t;

    if (rb_check_arity(argc, 1, 7) > 6) argc = 6;
    time_arg(argc, argv, &vtm);
    t = timegmw(&vtm);
    struct time_object *tobj = RTYPEDDATA_GET_DATA(time);
    TZMODE_SET_UTC(tobj);
    time_set_timew(time, tobj, t);
    time_set_vtm(time, tobj, vtm);

    return time;
}

/* call-seq:
 *   tm.to_time -> time
 *
 * Returns a new Time object.
 */

static VALUE
tm_to_time(VALUE tm)
{
    struct time_object *torig = get_timeval(tm);
    VALUE dup = time_s_alloc(rb_cTime);
    struct time_object *tobj = RTYPEDDATA_GET_DATA(dup);
    *tobj = *torig;
    return dup;
}

static VALUE
tm_plus(VALUE tm, VALUE offset)
{
    return time_add0(rb_obj_class(tm), get_timeval(tm), tm, offset, +1);
}

static VALUE
tm_minus(VALUE tm, VALUE offset)
{
    return time_add0(rb_obj_class(tm), get_timeval(tm), tm, offset, -1);
}

static VALUE
Init_tm(VALUE outer, const char *name)
{
    /* :stopdoc:*/
    VALUE tm;
    tm = rb_define_class_under(outer, name, rb_cObject);
    rb_define_alloc_func(tm, time_s_alloc);
    rb_define_method(tm, "sec", time_sec, 0);
    rb_define_method(tm, "min", time_min, 0);
    rb_define_method(tm, "hour", time_hour, 0);
    rb_define_method(tm, "mday", time_mday, 0);
    rb_define_method(tm, "day", time_mday, 0);
    rb_define_method(tm, "mon", time_mon, 0);
    rb_define_method(tm, "month", time_mon, 0);
    rb_define_method(tm, "year", time_year, 0);
    rb_define_method(tm, "isdst", time_isdst, 0);
    rb_define_method(tm, "dst?", time_isdst, 0);
    rb_define_method(tm, "zone", time_zone, 0);
    rb_define_method(tm, "gmtoff", rb_time_utc_offset, 0);
    rb_define_method(tm, "gmt_offset", rb_time_utc_offset, 0);
    rb_define_method(tm, "utc_offset", rb_time_utc_offset, 0);
    rb_define_method(tm, "utc?", time_utc_p, 0);
    rb_define_method(tm, "gmt?", time_utc_p, 0);
    rb_define_method(tm, "to_s", time_to_s, 0);
    rb_define_method(tm, "inspect", time_inspect, 0);
    rb_define_method(tm, "to_a", time_to_a, 0);
    rb_define_method(tm, "tv_sec", time_to_i, 0);
    rb_define_method(tm, "tv_usec", time_usec, 0);
    rb_define_method(tm, "usec", time_usec, 0);
    rb_define_method(tm, "tv_nsec", time_nsec, 0);
    rb_define_method(tm, "nsec", time_nsec, 0);
    rb_define_method(tm, "subsec", time_subsec, 0);
    rb_define_method(tm, "to_i", time_to_i, 0);
    rb_define_method(tm, "to_f", time_to_f, 0);
    rb_define_method(tm, "to_r", time_to_r, 0);
    rb_define_method(tm, "+", tm_plus, 1);
    rb_define_method(tm, "-", tm_minus, 1);
    rb_define_method(tm, "initialize", tm_initialize, -1);
    rb_define_method(tm, "utc", tm_to_time, 0);
    rb_alias(tm, rb_intern_const("to_time"), rb_intern_const("utc"));
    rb_define_singleton_method(tm, "from_time", tm_from_time, 1);
    /* :startdoc:*/

    return tm;
}

VALUE
rb_time_zone_abbreviation(VALUE zone, VALUE time)
{
    VALUE tm, abbr, strftime_args[2];

    abbr = rb_check_string_type(zone);
    if (!NIL_P(abbr)) return abbr;

    tm = tm_from_time(rb_cTimeTM, time);
    abbr = rb_check_funcall(zone, rb_intern("abbr"), 1, &tm);
    if (!UNDEF_P(abbr)) {
        goto found;
    }
#ifdef SUPPORT_TZINFO_ZONE_ABBREVIATION
    abbr = rb_check_funcall(zone, rb_intern("period_for_utc"), 1, &tm);
    if (!UNDEF_P(abbr)) {
        abbr = rb_funcallv(abbr, rb_intern("abbreviation"), 0, 0);
        goto found;
    }
#endif
    strftime_args[0] = rb_fstring_lit("%Z");
    strftime_args[1] = tm;
    abbr = rb_check_funcall(zone, rb_intern("strftime"), 2, strftime_args);
    if (!UNDEF_P(abbr)) {
        goto found;
    }
    abbr = rb_check_funcall_default(zone, idName, 0, 0, Qnil);
  found:
    return rb_obj_as_string(abbr);
}

//
void
Init_Time(void)
{
#ifdef _WIN32
    ruby_reset_timezone(getenv("TZ"));
#endif

    id_submicro = rb_intern_const("submicro");
    id_nano_num = rb_intern_const("nano_num");
    id_nano_den = rb_intern_const("nano_den");
    id_offset = rb_intern_const("offset");
    id_zone = rb_intern_const("zone");
    id_nanosecond = rb_intern_const("nanosecond");
    id_microsecond = rb_intern_const("microsecond");
    id_millisecond = rb_intern_const("millisecond");
    id_nsec = rb_intern_const("nsec");
    id_usec = rb_intern_const("usec");
    id_local_to_utc = rb_intern_const("local_to_utc");
    id_utc_to_local = rb_intern_const("utc_to_local");
    id_year = rb_intern_const("year");
    id_mon = rb_intern_const("mon");
    id_mday = rb_intern_const("mday");
    id_hour = rb_intern_const("hour");
    id_min = rb_intern_const("min");
    id_sec = rb_intern_const("sec");
    id_isdst = rb_intern_const("isdst");
    id_find_timezone = rb_intern_const("find_timezone");

    sym_year = ID2SYM(rb_intern_const("year"));
    sym_month = ID2SYM(rb_intern_const("month"));
    sym_yday = ID2SYM(rb_intern_const("yday"));
    sym_wday = ID2SYM(rb_intern_const("wday"));
    sym_day = ID2SYM(rb_intern_const("day"));
    sym_hour = ID2SYM(rb_intern_const("hour"));
    sym_min = ID2SYM(rb_intern_const("min"));
    sym_sec = ID2SYM(rb_intern_const("sec"));
    sym_subsec = ID2SYM(rb_intern_const("subsec"));
    sym_dst = ID2SYM(rb_intern_const("dst"));
    sym_zone = ID2SYM(rb_intern_const("zone"));

    str_utc = rb_fstring_lit("UTC");
    rb_vm_register_global_object(str_utc);
    str_empty = rb_fstring_lit("");
    rb_vm_register_global_object(str_empty);

    rb_cTime = rb_define_class("Time", rb_cObject);
    VALUE scTime = rb_singleton_class(rb_cTime);
    rb_include_module(rb_cTime, rb_mComparable);

    rb_define_alloc_func(rb_cTime, time_s_alloc);
    rb_define_singleton_method(rb_cTime, "utc", time_s_mkutc, -1);
    rb_define_singleton_method(rb_cTime, "local", time_s_mktime, -1);
    rb_define_alias(scTime, "gm", "utc");
    rb_define_alias(scTime, "mktime", "local");

    rb_define_method(rb_cTime, "to_i", time_to_i, 0);
    rb_define_method(rb_cTime, "to_f", time_to_f, 0);
    rb_define_method(rb_cTime, "to_r", time_to_r, 0);
    rb_define_method(rb_cTime, "<=>", time_cmp, 1);
    rb_define_method(rb_cTime, "eql?", time_eql, 1);
    rb_define_method(rb_cTime, "hash", time_hash, 0);
    rb_define_method(rb_cTime, "initialize_copy", time_init_copy, 1);

    rb_define_method(rb_cTime, "localtime", time_localtime_m, -1);
    rb_define_method(rb_cTime, "gmtime", time_gmtime, 0);
    rb_define_method(rb_cTime, "utc", time_gmtime, 0);
    rb_define_method(rb_cTime, "getlocal", time_getlocaltime, -1);
    rb_define_method(rb_cTime, "getgm", time_getgmtime, 0);
    rb_define_method(rb_cTime, "getutc", time_getgmtime, 0);

    rb_define_method(rb_cTime, "ctime", time_asctime, 0);
    rb_define_method(rb_cTime, "asctime", time_asctime, 0);
    rb_define_method(rb_cTime, "to_s", time_to_s, 0);
    rb_define_method(rb_cTime, "inspect", time_inspect, 0);
    rb_define_method(rb_cTime, "to_a", time_to_a, 0);
    rb_define_method(rb_cTime, "deconstruct_keys", time_deconstruct_keys, 1);

    rb_define_method(rb_cTime, "+", time_plus, 1);
    rb_define_method(rb_cTime, "-", time_minus, 1);

    rb_define_method(rb_cTime, "round", time_round, -1);
    rb_define_method(rb_cTime, "floor", time_floor, -1);
    rb_define_method(rb_cTime, "ceil", time_ceil, -1);

    rb_define_method(rb_cTime, "sec", time_sec, 0);
    rb_define_method(rb_cTime, "min", time_min, 0);
    rb_define_method(rb_cTime, "hour", time_hour, 0);
    rb_define_method(rb_cTime, "mday", time_mday, 0);
    rb_define_method(rb_cTime, "day", time_mday, 0);
    rb_define_method(rb_cTime, "mon", time_mon, 0);
    rb_define_method(rb_cTime, "month", time_mon, 0);
    rb_define_method(rb_cTime, "year", time_year, 0);
    rb_define_method(rb_cTime, "wday", time_wday, 0);
    rb_define_method(rb_cTime, "yday", time_yday, 0);
    rb_define_method(rb_cTime, "isdst", time_isdst, 0);
    rb_define_method(rb_cTime, "dst?", time_isdst, 0);
    rb_define_method(rb_cTime, "zone", time_zone, 0);
    rb_define_method(rb_cTime, "gmtoff", rb_time_utc_offset, 0);
    rb_define_method(rb_cTime, "gmt_offset", rb_time_utc_offset, 0);
    rb_define_method(rb_cTime, "utc_offset", rb_time_utc_offset, 0);

    rb_define_method(rb_cTime, "utc?", time_utc_p, 0);
    rb_define_method(rb_cTime, "gmt?", time_utc_p, 0);

    rb_define_method(rb_cTime, "sunday?", time_sunday, 0);
    rb_define_method(rb_cTime, "monday?", time_monday, 0);
    rb_define_method(rb_cTime, "tuesday?", time_tuesday, 0);
    rb_define_method(rb_cTime, "wednesday?", time_wednesday, 0);
    rb_define_method(rb_cTime, "thursday?", time_thursday, 0);
    rb_define_method(rb_cTime, "friday?", time_friday, 0);
    rb_define_method(rb_cTime, "saturday?", time_saturday, 0);

    rb_define_method(rb_cTime, "tv_sec", time_to_i, 0);
    rb_define_method(rb_cTime, "tv_usec", time_usec, 0);
    rb_define_method(rb_cTime, "usec", time_usec, 0);
    rb_define_method(rb_cTime, "tv_nsec", time_nsec, 0);
    rb_define_method(rb_cTime, "nsec", time_nsec, 0);
    rb_define_method(rb_cTime, "subsec", time_subsec, 0);

    rb_define_method(rb_cTime, "strftime", time_strftime, 1);
    rb_define_method(rb_cTime, "xmlschema", time_xmlschema, -1);
    rb_define_alias(rb_cTime, "iso8601", "xmlschema");

    /* methods for marshaling */
    rb_define_private_method(rb_cTime, "_dump", time_dump, -1);
    rb_define_private_method(scTime, "_load", time_load, 1);

    if (debug_find_time_numguess) {
        rb_define_hooked_variable("$find_time_numguess", (VALUE *)&find_time_numguess,
                                  find_time_numguess_getter, 0);
    }

    rb_cTimeTM = Init_tm(rb_cTime, "tm");
}

#include "timev.rbinc"
