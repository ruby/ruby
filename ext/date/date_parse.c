/*
  date_parse.c: Coded by Tadayoshi Funaba 2011
*/

#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/re.h"
#include <ctype.h>

#define sizeof_array(o) (sizeof o / sizeof o[0])

#define f_negate(x) rb_funcall(x, rb_intern("-@"), 0)
#define f_add(x,y) rb_funcall(x, '+', 1, y)
#define f_sub(x,y) rb_funcall(x, '-', 1, y)
#define f_mul(x,y) rb_funcall(x, '*', 1, y)
#define f_div(x,y) rb_funcall(x, '/', 1, y)
#define f_mod(x,y) rb_funcall(x, '%', 1, y)
#define f_expt(x,y) rb_funcall(x, rb_intern("**"), 1, y)

#define f_lt_p(x,y) rb_funcall(x, '<', 1, y)
#define f_gt_p(x,y) rb_funcall(x, '>', 1, y)
#define f_le_p(x,y) rb_funcall(x, rb_intern("<="), 1, y)
#define f_ge_p(x,y) rb_funcall(x, rb_intern(">="), 1, y)

#define f_to_s(x) rb_funcall(x, rb_intern("to_s"), 0)

#define f_match(r,s) rb_funcall(r, rb_intern("match"), 1, s)
#define f_aref(o,i) rb_funcall(o, rb_intern("[]"), 1, i)
#define f_aref2(o,i,j) rb_funcall(o, rb_intern("[]"), 2, i, j)
#define f_begin(o,i) rb_funcall(o, rb_intern("begin"), 1, i)
#define f_end(o,i) rb_funcall(o, rb_intern("end"), 1, i)
#define f_aset(o,i,v) rb_funcall(o, rb_intern("[]="), 2, i, v)
#define f_aset2(o,i,j,v) rb_funcall(o, rb_intern("[]="), 3, i, j, v)
#define f_sub_bang(s,r,x) rb_funcall(s, rb_intern("sub!"), 2, r, x)
#define f_gsub_bang(s,r,x) rb_funcall(s, rb_intern("gsub!"), 2, r, x)
#define f_split(s,p) rb_funcall(s, rb_intern("split"), 1, p)
#define f_downcase(x) rb_funcall(x, rb_intern("downcase"), 0)

#define set_hash(k,v) rb_hash_aset(hash, ID2SYM(rb_intern(k)), v)
#define ref_hash(k) rb_hash_aref(hash, ID2SYM(rb_intern(k)))
#define del_hash(k) rb_hash_delete(hash, ID2SYM(rb_intern(k)))

#define cstr2num(s) rb_cstr_to_inum(s, 10, 0)
#define str2num(s) rb_str_to_inum(s, 10, 0)

static const char *abbr_days[] = {
    "sun", "mon", "tue", "wed",
    "thu", "fri", "sat"
};

static const char *abbr_months[] = {
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec"
};

static void
s3e(VALUE hash, VALUE y, VALUE m, VALUE d, int bc)
{
    VALUE c = Qnil;

    if (TYPE(m) != T_STRING)
	m = f_to_s(m);

    if (!NIL_P(y) && !NIL_P(m) && NIL_P(d)) {
	VALUE oy = y;
	VALUE om = m;
	VALUE od = d;

	y = od;
	m = oy;
	d = om;
    }

    if (NIL_P(y)) {
	if (!NIL_P(d) && RSTRING_LEN(d) > 2) {
	    y = d;
	    d = Qnil;
	}
	if (!NIL_P(d) && *RSTRING_PTR(d) == '\'') {
		y = d;
		d = Qnil;
	}
    }

    if (!NIL_P(y)) {
	const char *s, *bp, *ep;
	size_t l;

	s = RSTRING_PTR(y);
	while (*s != '-' && *s != '+' && !isdigit(*s))
	    s++;
	bp = s;
	if (*s == '-' || *s == '+') {
	    s++;
	}
	l = strspn(s, "0123456789");
	ep = s + l;
	if (*ep) {
	    y = d;
	    d = rb_str_new(bp, ep - bp);
	}
    }

    if (!NIL_P(m)) {
	const char *s;

	s = RSTRING_PTR(m);
	if (*s == '\'' || RSTRING_LEN(m) > 2) {
	    /* us -> be */
	    VALUE oy = y;
	    VALUE om = m;
	    VALUE od = d;

	    y = om;
	    m = od;
	    d = oy;
	}
    }

    if (!NIL_P(d)) {
	const char *s;

	s = RSTRING_PTR(d);
	if (*s == '\'' || RSTRING_LEN(d) > 2) {
	    VALUE oy = y;
	    VALUE od = d;

	    y = od;
	    d = oy;
	}
    }

    if (!NIL_P(y)) {
	const char *s, *bp, *ep;
	int sign = 0;
	size_t l;
	VALUE iy;

	s = RSTRING_PTR(y);
	while (*s != '-' && *s != '+' && !isdigit(*s))
	    s++;
	bp = s;
	if (*s == '-' || *s == '+') {
	    s++;
	    sign = 1;
	}
	if (sign)
	    c = Qfalse;
	l = strspn(s, "0123456789");
	ep = s + l;
	if (l > 2)
	    c = Qfalse;
	{
	    char *buf;

	    buf = ALLOC_N(char, ep - bp + 1);
	    memcpy(buf, bp, ep - bp);
	    buf[ep - bp] = '\0';
	    iy = cstr2num(buf);
	}
	if (bc)
	    iy = f_add(f_negate(iy), INT2FIX(1));
	set_hash("year", iy);
    }

    if (!NIL_P(m)) {
	const char *s, *bp, *ep;
	size_t l;
	VALUE im;

	s = RSTRING_PTR(m);
	while (!isdigit(*s))
	    s++;
	bp = s;
	l = strspn(s, "0123456789");
	ep = s + l;
	{
	    char *buf;

	    buf = ALLOC_N(char, ep - bp + 1);
	    memcpy(buf, bp, ep - bp);
	    buf[ep - bp] = '\0';
	    im = cstr2num(buf);
	}
	set_hash("mon", im);
    }

    if (!NIL_P(d)) {
	const char *s, *bp, *ep;
	size_t l;
	VALUE id;

	s = RSTRING_PTR(d);
	while (!isdigit(*s))
	    s++;
	bp = s;
	l = strspn(s, "0123456789");
	ep = s + l;
	{
	    char *buf;

	    buf = ALLOC_N(char, ep - bp + 1);
	    memcpy(buf, bp, ep - bp);
	    buf[ep - bp] = '\0';
	    id = cstr2num(buf);
	}
	set_hash("mday", id);
    }

    if (!NIL_P(c))
	set_hash("_comp", c);
}

#define ABBR_DAYS "sun|mon|tue|wed|thu|fri|sat"
#define ABBR_MONTHS "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"

static VALUE
regcomp(const char *source, long len, int opt)
{
    VALUE pat;

    pat = rb_reg_new(source, len, opt);
    rb_gc_register_mark_object(pat);
    return pat;
}

#define REGCOMP(pat,opt) \
{ \
    if (NIL_P(pat)) \
	pat = regcomp(pat##_source, sizeof pat##_source - 1, opt); \
}

#define REGCOMP_0(pat) REGCOMP(pat, 0)
#define REGCOMP_I(pat) REGCOMP(pat, ONIG_OPTION_IGNORECASE)

#define SUBS(s,p,c) \
{ \
    return subs(s, p, hash, c);	\
}

static int
subs(VALUE str, VALUE pat, VALUE hash, int (*cb)(VALUE, VALUE))
{
    VALUE m;

    m = f_match(pat, str);

    if (NIL_P(m))
	return 0;

    {
	VALUE be, en;

	be = f_begin(m, INT2FIX(0));
	en = f_end(m, INT2FIX(0));
	f_aset2(str, be, LONG2NUM(NUM2LONG(en) - NUM2LONG(be)),
		rb_str_new(" ", 1));
	(*cb)(m, hash);
    }

    return 1;
}

static int
day_num(VALUE s)
{
    int i;

    for (i = 0; i < (int)sizeof_array(abbr_days); i++)
	if (strncasecmp(abbr_days[i], RSTRING_PTR(s), 3) == 0)
	    break;
    return i;
}

static int
mon_num(VALUE s)
{
    int i;

    for (i = 0; i < (int)sizeof_array(abbr_months); i++)
	if (strncasecmp(abbr_months[i], RSTRING_PTR(s), 3) == 0)
	    break;
    return i + 1;
}

static int
parse_day_cb(VALUE m, VALUE hash)
{
    VALUE s;

    s = f_aref(m, INT2FIX(1));
    set_hash("wday", INT2FIX(day_num(s)));
    return 1;
}

static int
parse_day(VALUE str, VALUE hash)
{
    static const char pat_source[] = "\\b(" ABBR_DAYS ")[^-\\d\\s]*";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_day_cb);
}

static int
parse_time2_cb(VALUE m, VALUE hash)
{
    VALUE h, min, s, f, p;

    h = f_aref(m, INT2FIX(1));
    h = str2num(h);

    min = f_aref(m, INT2FIX(2));
    if (!NIL_P(min))
	min = str2num(min);

    s = f_aref(m, INT2FIX(3));
    if (!NIL_P(s))
	s = str2num(s);

    f = f_aref(m, INT2FIX(4));

    if (!NIL_P(f))
	f = rb_rational_new2(str2num(f),
			     f_expt(INT2FIX(10), LONG2NUM(RSTRING_LEN(f))));

    p = f_aref(m, INT2FIX(5));

    if (!NIL_P(p)) {
	int ih = NUM2INT(h);
	ih %= 12;
	if (*RSTRING_PTR(p) == 'P' || *RSTRING_PTR(p) == 'p')
	    ih += 12;
	h = INT2FIX(ih);
    }

    set_hash("hour", h);
    if (!NIL_P(min))
	set_hash("min", min);
    if (!NIL_P(s))
	set_hash("sec", s);
    if (!NIL_P(f))
	set_hash("sec_fraction", f);

    return 1;
}

static int
parse_time_cb(VALUE m, VALUE hash)
{
    static const char pat_source[] =
            "\\A(\\d+)h?"
	      "(?:\\s*:?\\s*(\\d+)m?"
		"(?:"
		  "\\s*:?\\s*(\\d+)(?:[,.](\\d+))?s?"
		")?"
	      ")?"
	    "(?:\\s*([ap])(?:m\\b|\\.m\\.))?";
    static VALUE pat = Qnil;
    VALUE s1, s2;

    s1 = f_aref(m, INT2FIX(1));
    s2 = f_aref(m, INT2FIX(2));

    if (!NIL_P(s2))
	set_hash("zone", s2);

    REGCOMP_I(pat);

    {
	VALUE m = f_match(pat, s1);

	if (NIL_P(m))
	    return 0;
	parse_time2_cb(m, hash);
    }

    return 1;
}

static int
parse_time(VALUE str, VALUE hash)
{
    static const char pat_source[] =
		"("
		   "(?:"
		     "\\d+\\s*:\\s*\\d+"
		     "(?:"
		       "\\s*:\\s*\\d+(?:[,.]\\d*)?"
		     ")?"
		   "|"
		     "\\d+\\s*h(?:\\s*\\d+m?(?:\\s*\\d+s?)?)?"
		   ")"
		   "(?:"
		     "\\s*"
		     "[ap](?:m\\b|\\.m\\.)"
		   ")?"
		 "|"
		   "\\d+\\s*[ap](?:m\\b|\\.m\\.)"
		 ")"
		 "(?:"
		   "\\s*"
		   "("
		     "(?:gmt|utc?)?[-+]\\d+(?:[,.:]\\d+(?::\\d+)?)?"
		   "|"
		     "[[:alpha:].\\s]+(?:standard|daylight)\\stime\\b"
		   "|"
		     "[[:alpha:]]+(?:\\sdst)?\\b"
		   ")"
		")?";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_time_cb);
}

static int
parse_eu_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d, b;

    d = f_aref(m, INT2FIX(1));
    mon = f_aref(m, INT2FIX(2));
    b = f_aref(m, INT2FIX(3));
    y = f_aref(m, INT2FIX(4));

    mon = INT2FIX(mon_num(mon));

    s3e(hash, y, mon, d, !NIL_P(b) &&
	(*RSTRING_PTR(b) == 'B' ||
	 *RSTRING_PTR(b) == 'b'));
    return 1;
}

static int
parse_eu(VALUE str, VALUE hash)
{
    static const char pat_source[] =
		"'?(\\d+)[^-\\d\\s]*"
		 "\\s*"
		 "(" ABBR_MONTHS ")[^-\\d\\s']*"
		 "(?:"
		   "\\s*"
		   "(c(?:e|\\.e\\.)|b(?:ce|\\.c\\.e\\.)|a(?:d|\\.d\\.)|b(?:c|\\.c\\.))?"
		   "\\s*"
		   "('?-?\\d+(?:(?:st|nd|rd|th)\\b)?)"
		")?";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_eu_cb);
}

static int
parse_us_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d, b;

    mon = f_aref(m, INT2FIX(1));
    d = f_aref(m, INT2FIX(2));
    b = f_aref(m, INT2FIX(3));
    y = f_aref(m, INT2FIX(4));

    mon = INT2FIX(mon_num(mon));

    s3e(hash, y, mon, d, !NIL_P(b) &&
	(*RSTRING_PTR(b) == 'B' ||
	 *RSTRING_PTR(b) == 'b'));
    return 1;
}

static int
parse_us(VALUE str, VALUE hash)
{
    static const char pat_source[] =
		"\\b(" ABBR_MONTHS ")[^-\\d\\s']*"
		 "\\s*"
		 "('?\\d+)[^-\\d\\s']*"
		 "(?:"
		   "\\s*"
		   "(c(?:e|\\.e\\.)|b(?:ce|\\.c\\.e\\.)|a(?:d|\\.d\\.)|b(?:c|\\.c\\.))?"
		   "\\s*"
		   "('?-?\\d+)"
		")?";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_us_cb);
}

static int
parse_iso_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d;

    y = f_aref(m, INT2FIX(1));
    mon = f_aref(m, INT2FIX(2));
    d = f_aref(m, INT2FIX(3));

    s3e(hash, y, mon, d, 0);
    return 1;
}

static int
parse_iso(VALUE str, VALUE hash)
{
    static const char pat_source[] = "('?[-+]?\\d+)-(\\d+)-('?-?\\d+)";
    static VALUE pat = Qnil;

    REGCOMP_0(pat);
    SUBS(str, pat, parse_iso_cb);
}

static int
parse_iso21_cb(VALUE m, VALUE hash)
{
    VALUE y, w, d;

    y = f_aref(m, INT2FIX(1));
    w = f_aref(m, INT2FIX(2));
    d = f_aref(m, INT2FIX(3));

    if (!NIL_P(y))
	set_hash("cwyear", str2num(y));
    set_hash("cweek", str2num(w));
    if (!NIL_P(d))
	set_hash("cwday", str2num(d));

    return 1;
}

static int
parse_iso21(VALUE str, VALUE hash)
{
    static const char pat_source[] =
	"\\b(\\d{2}|\\d{4})?-?w(\\d{2})(?:-?(\\d))?\\b";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_iso21_cb);
}

static int
parse_iso22_cb(VALUE m, VALUE hash)
{
    VALUE d;

    d = f_aref(m, INT2FIX(1));
    set_hash("cwday", str2num(d));
    return 1;
}

static int
parse_iso22(VALUE str, VALUE hash)
{
    static const char pat_source[] = "-w-(\\d)\\b";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_iso22_cb);
}

static int
parse_iso23_cb(VALUE m, VALUE hash)
{
    VALUE mon, d;

    mon = f_aref(m, INT2FIX(1));
    d = f_aref(m, INT2FIX(2));

    if (!NIL_P(mon))
	set_hash("mon", str2num(mon));
    set_hash("mday", str2num(d));

    return 1;
}

static int
parse_iso23(VALUE str, VALUE hash)
{
    static const char pat_source[] = "--(\\d{2})?-(\\d{2})\\b";
    static VALUE pat = Qnil;

    REGCOMP_0(pat);
    SUBS(str, pat, parse_iso23_cb);
}

static int
parse_iso24_cb(VALUE m, VALUE hash)
{
    VALUE mon, d;

    mon = f_aref(m, INT2FIX(1));
    d = f_aref(m, INT2FIX(2));

    set_hash("mon", str2num(mon));
    if (!NIL_P(d))
	set_hash("mday", str2num(d));

    return 1;
}

static int
parse_iso24(VALUE str, VALUE hash)
{
    static const char pat_source[] = "--(\\d{2})(\\d{2})?\\b";
    static VALUE pat = Qnil;

    REGCOMP_0(pat);
    SUBS(str, pat, parse_iso24_cb);
}

static int
parse_iso25_cb(VALUE m, VALUE hash)
{
    VALUE y, d;

    y = f_aref(m, INT2FIX(1));
    d = f_aref(m, INT2FIX(2));

    set_hash("year", str2num(y));
    set_hash("yday", str2num(d));

    return 1;
}

static int
parse_iso25(VALUE str, VALUE hash)
{
    static const char pat0_source[] = "[,.](\\d{2}|\\d{4})-\\d{3}\\b";
    static VALUE pat0 = Qnil;
    static const char pat_source[] = "\\b(\\d{2}|\\d{4})-(\\d{3})\\b";
    static VALUE pat = Qnil;

    REGCOMP_0(pat0);
    REGCOMP_0(pat);

    if (!NIL_P(f_match(pat0, str)))
	return 0;
    SUBS(str, pat, parse_iso25_cb);
}

static int
parse_iso26_cb(VALUE m, VALUE hash)
{
    VALUE d;

    d = f_aref(m, INT2FIX(1));
    set_hash("yday", str2num(d));

    return 1;
}
static int
parse_iso26(VALUE str, VALUE hash)
{
    static const char pat0_source[] = "\\d-\\d{3}\\b";
    static VALUE pat0 = Qnil;
    static const char pat_source[] = "\\b-(\\d{3})\\b";
    static VALUE pat = Qnil;

    REGCOMP_0(pat0);
    REGCOMP_0(pat);

    if (!NIL_P(f_match(pat0, str)))
	return 0;
    SUBS(str, pat, parse_iso26_cb);
}

static int
parse_iso2(VALUE str, VALUE hash)
{
    if (parse_iso21(str, hash))
	goto ok;
    if (parse_iso22(str, hash))
	goto ok;
    if (parse_iso23(str, hash))
	goto ok;
    if (parse_iso24(str, hash))
	goto ok;
    if (parse_iso25(str, hash))
	goto ok;
    if (parse_iso26(str, hash))
	goto ok;
    return 0;

  ok:
    return 1;
}

static int
parse_jis_cb(VALUE m, VALUE hash)
{
    VALUE e, y, mon, d;
    int ep;

    e = f_aref(m, INT2FIX(1));
    y = f_aref(m, INT2FIX(2));
    mon = f_aref(m, INT2FIX(3));
    d = f_aref(m, INT2FIX(4));

    switch (*RSTRING_PTR(e)) {
      case 'M': case 'm': ep = 1867; break;
      case 'T': case 't': ep = 1911; break;
      case 'S': case 's': ep = 1925; break;
      case 'H': case 'h': ep = 1988; break;
      default:  ep = 0; break;
    }

    set_hash("year", f_add(str2num(y), INT2FIX(ep)));
    set_hash("mon", str2num(mon));
    set_hash("mday", str2num(d));

    return 1;
}

static int
parse_jis(VALUE str, VALUE hash)
{
    static const char pat_source[] = "\\b([mtsh])(\\d+)\\.(\\d+)\\.(\\d+)";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_jis_cb);
}

static int
parse_vms11_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d;

    d = f_aref(m, INT2FIX(1));
    mon = f_aref(m, INT2FIX(2));
    y = f_aref(m, INT2FIX(3));

    mon = INT2FIX(mon_num(mon));

    s3e(hash, y, mon, d, 0);
    return 1;
}

static int
parse_vms11(VALUE str, VALUE hash)
{
    static const char pat_source[] =
	"('?-?\\d+)-(" ABBR_MONTHS ")[^-]*"
	"-('?-?\\d+)";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_vms11_cb);
}

static int
parse_vms12_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d;

    mon = f_aref(m, INT2FIX(1));
    d = f_aref(m, INT2FIX(2));
    y = f_aref(m, INT2FIX(3));

    mon = INT2FIX(mon_num(mon));

    s3e(hash, y, mon, d, 0);
    return 1;
}

static int
parse_vms12(VALUE str, VALUE hash)
{
    static const char pat_source[] =
	"\\b(" ABBR_MONTHS ")[^-]*"
	"-('?-?\\d+)(?:-('?-?\\d+))?";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_vms12_cb);
}

static int
parse_vms(VALUE str, VALUE hash)
{
    if (parse_vms11(str, hash))
	goto ok;
    if (parse_vms12(str, hash))
	goto ok;
    return 0;

  ok:
    return 1;
}

static int
parse_sla_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d;

    y = f_aref(m, INT2FIX(1));
    mon = f_aref(m, INT2FIX(2));
    d = f_aref(m, INT2FIX(3));

    s3e(hash, y, mon, d, 0);
    return 1;
}

static int
parse_sla(VALUE str, VALUE hash)
{
    static const char pat_source[] =
	"('?-?\\d+)/\\s*('?\\d+)(?:\\D\\s*('?-?\\d+))?";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_sla_cb);
}

static int
parse_dot_cb(VALUE m, VALUE hash)
{
    VALUE y, mon, d;

    y = f_aref(m, INT2FIX(1));
    mon = f_aref(m, INT2FIX(2));
    d = f_aref(m, INT2FIX(3));

    s3e(hash, y, mon, d, 0);
    return 1;
}

static int
parse_dot(VALUE str, VALUE hash)
{
    static const char pat_source[] =
	"('?-?\\d+)\\.\\s*('?\\d+)\\.\\s*('?-?\\d+)";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_dot_cb);
}

static int
parse_year_cb(VALUE m, VALUE hash)
{
    VALUE y;

    y = f_aref(m, INT2FIX(1));
    set_hash("year", str2num(y));
    return 1;
}

static int
parse_year(VALUE str, VALUE hash)
{
    static const char pat_source[] = "'(\\d+)\\b";
    static VALUE pat = Qnil;

    REGCOMP_0(pat);
    SUBS(str, pat, parse_year_cb);
}

static int
parse_mon_cb(VALUE m, VALUE hash)
{
    VALUE mon;

    mon = f_aref(m, INT2FIX(1));
    set_hash("mon", INT2FIX(mon_num(mon)));
    return 1;
}

static int
parse_mon(VALUE str, VALUE hash)
{
    static const char pat_source[] = "\\b(" ABBR_MONTHS ")\\S*";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_mon_cb);
}

static int
parse_mday_cb(VALUE m, VALUE hash)
{
    VALUE d;

    d = f_aref(m, INT2FIX(1));
    set_hash("mday", str2num(d));
    return 1;
}

static int
parse_mday(VALUE str, VALUE hash)
{
    static const char pat_source[] = "(\\d+)(st|nd|rd|th)\\b";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_mday_cb);
}

static int
n2i(const char *s, long f, long w)
{
    long e, i;
    int v;
    
    e = f + w;
    v = 0;
    for (i = f; i < e; i++) {
	v *= 10;
	v += s[i] - '0';
    }
    return v;
}

VALUE date_zone_to_diff(VALUE);

static int
parse_ddd_cb(VALUE m, VALUE hash)
{
    VALUE s1, s2, s3, s4, s5;
    const char *cs2, *cs3, *cs5;
    long l2, l3, l4, l5;

    s1 = f_aref(m, INT2FIX(1));
    s2 = f_aref(m, INT2FIX(2));
    s3 = f_aref(m, INT2FIX(3));
    s4 = f_aref(m, INT2FIX(4));
    s5 = f_aref(m, INT2FIX(5));

    cs2 = RSTRING_PTR(s2);
    l2 = RSTRING_LEN(s2);

    switch (l2) {
      case 2:
	if (NIL_P(s3) && !NIL_P(s4))
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	else
	    set_hash("mday", INT2FIX(n2i(cs2,    0, 2)));
	break;
      case 4:
	if (NIL_P(s3) && !NIL_P(s4)) {
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	    set_hash("min",  INT2FIX(n2i(cs2, l2-4, 2)));
	}
	else {
	    set_hash("mon",  INT2FIX(n2i(cs2,    0, 2)));
	    set_hash("mday", INT2FIX(n2i(cs2,    2, 2)));
	}
	break;
      case 6:
	if (NIL_P(s3) && !NIL_P(s4)) {
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	    set_hash("min",  INT2FIX(n2i(cs2, l2-4, 2)));
	    set_hash("hour", INT2FIX(n2i(cs2, l2-6, 2)));
	}
	else {
	    int                  y = n2i(cs2,    0, 2);
	    if (!NIL_P(s1) && *RSTRING_PTR(s1) == '-')
		y = -y;
	    set_hash("year", INT2FIX(y));
	    set_hash("mon",  INT2FIX(n2i(cs2,    2, 2)));
	    set_hash("mday", INT2FIX(n2i(cs2,    4, 2)));
	}
	break;
      case 8:
      case 10:
      case 12:
      case 14:
	if (NIL_P(s3) && !NIL_P(s4)) {
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	    set_hash("min",  INT2FIX(n2i(cs2, l2-4, 2)));
	    set_hash("hour", INT2FIX(n2i(cs2, l2-6, 2)));
	    set_hash("mday", INT2FIX(n2i(cs2, l2-8, 2)));
	    if (l2 >= 10)
		set_hash("mon", INT2FIX(n2i(cs2, l2-10, 2)));
	    if (l2 == 12) {
		int y = n2i(cs2, l2-12, 2);
		if (!NIL_P(s1) && *RSTRING_PTR(s1) == '-')
		    y = -y;
		set_hash("year", INT2FIX(y));
	    }
	    if (l2 == 14) {
		int y = n2i(cs2, l2-14, 4);
		if (!NIL_P(s1) && *RSTRING_PTR(s1) == '-')
		    y = -y;
		set_hash("year", INT2FIX(y));
		set_hash("_comp", Qfalse);
	    }
	}
	else {
	    int                  y = n2i(cs2,    0, 4);
	    if (!NIL_P(s1) && *RSTRING_PTR(s1) == '-')
		y = -y;
	    set_hash("year", INT2FIX(y));
	    set_hash("mon",  INT2FIX(n2i(cs2,    4, 2)));
	    set_hash("mday", INT2FIX(n2i(cs2,    6, 2)));
	    if (l2 >= 10)
		set_hash("hour", INT2FIX(n2i(cs2,    8, 2)));
	    if (l2 >= 12)
		set_hash("min",  INT2FIX(n2i(cs2,   10, 2)));
	    if (l2 >= 14)
		set_hash("sec",  INT2FIX(n2i(cs2,   12, 2)));
	    set_hash("_comp", Qfalse);
	}
	break;
      case 3:
	if (NIL_P(s3) && !NIL_P(s4)) {
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	    set_hash("min",  INT2FIX(n2i(cs2, l2-3, 1)));
	}
	else
	    set_hash("yday", INT2FIX(n2i(cs2,    0, 3)));
	break;
      case 5:
	if (NIL_P(s3) && !NIL_P(s4)) {
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	    set_hash("min",  INT2FIX(n2i(cs2, l2-4, 2)));
	    set_hash("hour", INT2FIX(n2i(cs2, l2-5, 1)));
	}
	else {
	    int                  y = n2i(cs2,    0, 2);
	    if (!NIL_P(s1) && *RSTRING_PTR(s1) == '-')
		y = -y;
	    set_hash("year", INT2FIX(y));
	    set_hash("yday", INT2FIX(n2i(cs2,    2, 3)));
	}
	break;
      case 7:
	if (NIL_P(s3) && !NIL_P(s4)) {
	    set_hash("sec",  INT2FIX(n2i(cs2, l2-2, 2)));
	    set_hash("min",  INT2FIX(n2i(cs2, l2-4, 2)));
	    set_hash("hour", INT2FIX(n2i(cs2, l2-6, 2)));
	    set_hash("mday", INT2FIX(n2i(cs2, l2-7, 1)));
	}
	else {
	    int                  y = n2i(cs2,    0, 4);
	    if (!NIL_P(s1) && *RSTRING_PTR(s1) == '-')
		y = -y;
	    set_hash("year", INT2FIX(y));
	    set_hash("yday", INT2FIX(n2i(cs2,    4, 3)));
	}
	break;
    }
    if (!NIL_P(s3)) {
	cs3 = RSTRING_PTR(s3);
	l3 = RSTRING_LEN(s3);

	if (!NIL_P(s4)) {
	    switch (l3) {
	      case 2:
	      case 4:
	      case 6:
		set_hash("sec", INT2FIX(n2i(cs3, l3-2, 2)));
		if (l3 >= 4)
		    set_hash("min", INT2FIX(n2i(cs3, l3-4, 2)));
		if (l3 >= 6)
		    set_hash("hour", INT2FIX(n2i(cs3, l3-6, 2)));
		break;
	    }
	}
	else {
	    switch (l3) {
	      case 2:
	      case 4:
	      case 6:
		set_hash("hour", INT2FIX(n2i(cs3, 0, 2)));
		if (l3 >= 4)
		    set_hash("min", INT2FIX(n2i(cs3, 2, 2)));
		if (l3 >= 6)
		    set_hash("sec", INT2FIX(n2i(cs3, 4, 2)));
		break;
	    }
	}
    }
    if (!NIL_P(s4)) {
	l4 = RSTRING_LEN(s4);

	set_hash("sec_fraction",
		 rb_rational_new2(str2num(s4),
				  f_expt(INT2FIX(10), LONG2NUM(l4))));
    }
    if (!NIL_P(s5)) {
	cs5 = RSTRING_PTR(s5);
	l5 = RSTRING_LEN(s5);

	set_hash("zone", s5);

	if (*cs5 == '[') {
	    char *buf = ALLOC_N(char, l5 + 1);
	    char *s1, *s2, *s3;
	    VALUE zone;

	    memcpy(buf, cs5, l5);
	    buf[l5 - 1] = '\0';

	    s1 = buf + 1;
	    s2 = strchr(buf, ':');
	    if (s2) {
		*s2 = '\0';
		s2++;
	    }
	    if (s2)
		s3 = s2;
	    else
		s3 = s1;
	    zone = rb_str_new2(s3);
	    set_hash("zone", zone);
	    if (isdigit(*s1))
		*--s1 = '+';
	    set_hash("offset", date_zone_to_diff(rb_str_new2(s1)));
	}
    }

    return 1;
}

static int
parse_ddd(VALUE str, VALUE hash)
{
    static const char pat_source[] =
		"([-+]?)(\\d{2,14})"
		  "(?:"
		    "\\s*"
		    "t?"
		    "\\s*"
		    "(\\d{2,6})?(?:[,.](\\d*))?"
		  ")?"
		  "(?:"
		    "\\s*"
		    "("
		      "z\\b"
		    "|"
		      "[-+]\\d{1,4}\\b"
		    "|"
		      "\\[[-+]?\\d[^\\]]*\\]"
		    ")"
		")?";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_ddd_cb);
}

static int
parse_bc_cb(VALUE m, VALUE hash)
{
    VALUE y;

    y = ref_hash("year");
    if (!NIL_P(y))
	set_hash("year", f_add(f_negate(y), INT2FIX(1)));

    return 1;
}

static int
parse_bc(VALUE str, VALUE hash)
{
    static const char pat_source[] =
	"\\b(bc\\b|bce\\b|b\\.c\\.|b\\.c\\.e\\.)";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_bc_cb);
}

static int
parse_frag_cb(VALUE m, VALUE hash)
{
    VALUE s, n;

    s = f_aref(m, INT2FIX(1));

    if (!NIL_P(ref_hash("hour")) && NIL_P(ref_hash("mday"))) {
	n = str2num(s);
	if (f_ge_p(n, INT2FIX(1)) &&
	    f_le_p(n, INT2FIX(31)))
	    set_hash("mday", n);
    }
    if (!NIL_P(ref_hash("mday")) && NIL_P(ref_hash("hour"))) {
	n = str2num(s);
	if (f_ge_p(n, INT2FIX(0)) &&
	    f_le_p(n, INT2FIX(24)))
	    set_hash("hour", n);
    }

    return 1;
}

static int
parse_frag(VALUE str, VALUE hash)
{
    static const char pat_source[] = "\\A\\s*(\\d{1,2})\\s*\\z";
    static VALUE pat = Qnil;

    REGCOMP_I(pat);
    SUBS(str, pat, parse_frag_cb);
}

#define HAVE_ALPHA (1<<0)
#define HAVE_DIGIT (1<<1)
#define HAVE_DASH (1<<2)
#define HAVE_DOT (1<<3)
#define HAVE_SLASH (1<<4)

static unsigned
check_class(VALUE s)
{
    unsigned flags;
    long i;

    flags = 0;
    for (i = 0; i < RSTRING_LEN(s); i++) {
	if (isalpha(RSTRING_PTR(s)[i]))
	    flags |= HAVE_ALPHA;
	if (isdigit(RSTRING_PTR(s)[i]))
	    flags |= HAVE_DIGIT;
	if (RSTRING_PTR(s)[i] == '-')
	    flags |= HAVE_DASH;
	if (RSTRING_PTR(s)[i] == '.')
	    flags |= HAVE_DOT;
	if (RSTRING_PTR(s)[i] == '/')
	    flags |= HAVE_SLASH;
    }
    return flags;
}

#define HAVE_ELEM_P(x) ((check_class(str) & (x)) == (x))

VALUE
date__parse(VALUE str, VALUE comp)
{
    VALUE backref, hash;

    backref = rb_backref_get();
    rb_match_busy(backref);

    {
	static const char pat_source[] = "[^-+',./:@[:alnum:]\\[\\]]+";
	static VALUE pat = Qnil;

	str = rb_str_dup(str);
	REGCOMP_0(pat);
	f_gsub_bang(str, pat, rb_str_new(" ", 1));
    }

    hash = rb_hash_new();
    set_hash("_comp", comp);

    if (HAVE_ELEM_P(HAVE_ALPHA))
	parse_day(str, hash);
    if (HAVE_ELEM_P(HAVE_DIGIT))
	parse_time(str, hash);

    if (HAVE_ELEM_P(HAVE_ALPHA|HAVE_DIGIT))
	if (parse_eu(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_ALPHA|HAVE_DIGIT))
	if (parse_us(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT|HAVE_DASH))
	if (parse_iso(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT|HAVE_DOT))
	if (parse_jis(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_ALPHA|HAVE_DIGIT|HAVE_DASH))
	if (parse_vms(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT|HAVE_SLASH))
	if (parse_sla(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT|HAVE_DOT))
	if (parse_dot(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT))
	if (parse_iso2(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT))
	if (parse_year(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_ALPHA))
	if (parse_mon(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT))
	if (parse_mday(str, hash))
	    goto ok;
    if (HAVE_ELEM_P(HAVE_DIGIT))
	if (parse_ddd(str, hash))
	    goto ok;

  ok:
    if (HAVE_ELEM_P(HAVE_ALPHA))
	parse_bc(str, hash);
    if (HAVE_ELEM_P(HAVE_DIGIT))
	parse_frag(str, hash);

    {
	if (RTEST(ref_hash("_comp"))) {
	    VALUE y;

	    y = ref_hash("cwyear");
	    if (!NIL_P(y))
		if (f_ge_p(y, INT2FIX(0)) && f_le_p(y, INT2FIX(99))) {
		    if (f_ge_p(y, INT2FIX(69)))
			set_hash("cwyear", f_add(y, INT2FIX(1900)));
		    else
			set_hash("cwyear", f_add(y, INT2FIX(2000)));
		}
	    y = ref_hash("year");
	    if (!NIL_P(y))
		if (f_ge_p(y, INT2FIX(0)) && f_le_p(y, INT2FIX(99))) {
		    if (f_ge_p(y, INT2FIX(69)))
			set_hash("year", f_add(y, INT2FIX(1900)));
		    else
			set_hash("year", f_add(y, INT2FIX(2000)));
		}
	}
    }

    del_hash("_comp");

    {
	VALUE zone = ref_hash("zone");
	if (!NIL_P(zone) && NIL_P(ref_hash("offset")))
	    set_hash("offset", date_zone_to_diff(zone));
    }

    rb_backref_set(backref);

    return hash;
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
