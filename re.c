/**********************************************************************

  re.c -

  $Author$
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "re.h"
#include <ctype.h>

static VALUE rb_eRegexpError;

#define BEG(no) regs->beg[no]
#define END(no) regs->end[no]

#if 'a' == 97   /* it's ascii */
static const char casetable[] = {
        '\000', '\001', '\002', '\003', '\004', '\005', '\006', '\007',
        '\010', '\011', '\012', '\013', '\014', '\015', '\016', '\017',
        '\020', '\021', '\022', '\023', '\024', '\025', '\026', '\027',
        '\030', '\031', '\032', '\033', '\034', '\035', '\036', '\037',
        /* ' '     '!'     '"'     '#'     '$'     '%'     '&'     ''' */
        '\040', '\041', '\042', '\043', '\044', '\045', '\046', '\047',
        /* '('     ')'     '*'     '+'     ','     '-'     '.'     '/' */
        '\050', '\051', '\052', '\053', '\054', '\055', '\056', '\057',
        /* '0'     '1'     '2'     '3'     '4'     '5'     '6'     '7' */
        '\060', '\061', '\062', '\063', '\064', '\065', '\066', '\067',
        /* '8'     '9'     ':'     ';'     '<'     '='     '>'     '?' */
        '\070', '\071', '\072', '\073', '\074', '\075', '\076', '\077',
        /* '@'     'A'     'B'     'C'     'D'     'E'     'F'     'G' */
        '\100', '\141', '\142', '\143', '\144', '\145', '\146', '\147',
        /* 'H'     'I'     'J'     'K'     'L'     'M'     'N'     'O' */
        '\150', '\151', '\152', '\153', '\154', '\155', '\156', '\157',
        /* 'P'     'Q'     'R'     'S'     'T'     'U'     'V'     'W' */
        '\160', '\161', '\162', '\163', '\164', '\165', '\166', '\167',
        /* 'X'     'Y'     'Z'     '['     '\'     ']'     '^'     '_' */
        '\170', '\171', '\172', '\133', '\134', '\135', '\136', '\137',
        /* '`'     'a'     'b'     'c'     'd'     'e'     'f'     'g' */
        '\140', '\141', '\142', '\143', '\144', '\145', '\146', '\147',
        /* 'h'     'i'     'j'     'k'     'l'     'm'     'n'     'o' */
        '\150', '\151', '\152', '\153', '\154', '\155', '\156', '\157',
        /* 'p'     'q'     'r'     's'     't'     'u'     'v'     'w' */
        '\160', '\161', '\162', '\163', '\164', '\165', '\166', '\167',
        /* 'x'     'y'     'z'     '{'     '|'     '}'     '~' */
        '\170', '\171', '\172', '\173', '\174', '\175', '\176', '\177',
        '\200', '\201', '\202', '\203', '\204', '\205', '\206', '\207',
        '\210', '\211', '\212', '\213', '\214', '\215', '\216', '\217',
        '\220', '\221', '\222', '\223', '\224', '\225', '\226', '\227',
        '\230', '\231', '\232', '\233', '\234', '\235', '\236', '\237',
        '\240', '\241', '\242', '\243', '\244', '\245', '\246', '\247',
        '\250', '\251', '\252', '\253', '\254', '\255', '\256', '\257',
        '\260', '\261', '\262', '\263', '\264', '\265', '\266', '\267',
        '\270', '\271', '\272', '\273', '\274', '\275', '\276', '\277',
        '\300', '\301', '\302', '\303', '\304', '\305', '\306', '\307',
        '\310', '\311', '\312', '\313', '\314', '\315', '\316', '\317',
        '\320', '\321', '\322', '\323', '\324', '\325', '\326', '\327',
        '\330', '\331', '\332', '\333', '\334', '\335', '\336', '\337',
        '\340', '\341', '\342', '\343', '\344', '\345', '\346', '\347',
        '\350', '\351', '\352', '\353', '\354', '\355', '\356', '\357',
        '\360', '\361', '\362', '\363', '\364', '\365', '\366', '\367',
        '\370', '\371', '\372', '\373', '\374', '\375', '\376', '\377',
};
#else
# error >>> "You lose. You will need a translation table for your character set." <<<
#endif

int
rb_memcicmp(p1, p2, len)
    char *p1, *p2;
    long len;
{
    int tmp;

    while (len--) {
	if (tmp = casetable[(unsigned)*p1++] - casetable[(unsigned)*p2++])
	    return tmp;
    }
    return 0;
}

int
rb_memcmp(p1, p2, len)
    char *p1, *p2;
    long len;
{
    if (!ruby_ignorecase) {
	return memcmp(p1, p2, len);
    }
    return rb_memcicmp(p1, p2, len);
}

long
rb_memsearch(x0, m, y0, n)
    char *x0, *y0;
    long m, n;
{
    unsigned char *x = (unsigned char *)x0, *y = (unsigned char *)y0;
    unsigned char *s, *e;
    long i;
    int d;
    unsigned long hx, hy;

#define KR_REHASH(a, b, h) (((h) << 1) - ((a)<<d) + (b))

    if (m > n) return -1;
    s = y; e = s + n - m;

    /* Preprocessing */
    /* computes d = 2^(m-1) with
       the left-shift operator */
    d = sizeof(hx) * CHAR_BIT - 1;
    if (d > m) d = m;

    if (ruby_ignorecase) {
	if (n == m) {
	    return rb_memcicmp(x, s, m) == 0 ? 0 : -1;
	}
	/* Prepare hash value */
	for (hy = hx = i = 0; i < d; ++i) {
	    hx = KR_REHASH(0, casetable[x[i]], hx);
	    hy = KR_REHASH(0, casetable[s[i]], hy);
	}
	/* Searching */
	while (hx != hy || rb_memcicmp(x, s, m)) {
	    if (s >= e) return -1;
	    hy = KR_REHASH(casetable[*s], casetable[*(s+d)], hy);
	    s++;
	}
    }
    else {
	if (n == m) {
	    return memcmp(x, s, m) == 0 ? 0 : -1;
	}
	/* Prepare hash value */
	for (hy = hx = i = 0; i < d; ++i) {
	    hx = KR_REHASH(0, x[i], hx);
	    hy = KR_REHASH(0, s[i], hy);
	}
	/* Searching */
	while (hx != hy || memcmp(x, s, m)) {
	    if (s >= e) return -1;
	    hy = KR_REHASH(*s, *(s+d), hy);
	    s++;
	}
    }
    return s-y;
}

#define REG_CASESTATE  FL_USER0
#define KCODE_NONE  0
#define KCODE_EUC   FL_USER1
#define KCODE_SJIS  FL_USER2
#define KCODE_UTF8  FL_USER3
#define KCODE_FIXED FL_USER4
#define KCODE_MASK (KCODE_EUC|KCODE_SJIS|KCODE_UTF8)

static int reg_kcode = DEFAULT_KCODE;

static void
kcode_euc(re)
    struct RRegexp *re;
{
    FL_UNSET(re, KCODE_MASK);
    FL_SET(re, KCODE_EUC);
    FL_SET(re, KCODE_FIXED);
}

static void
kcode_sjis(re)
    struct RRegexp *re;
{
    FL_UNSET(re, KCODE_MASK);
    FL_SET(re, KCODE_SJIS);
    FL_SET(re, KCODE_FIXED);
}

static void
kcode_utf8(re)
    struct RRegexp *re;
{
    FL_UNSET(re, KCODE_MASK);
    FL_SET(re, KCODE_UTF8);
    FL_SET(re, KCODE_FIXED);
}

static void
kcode_none(re)
    struct RRegexp *re;
{
    FL_UNSET(re, KCODE_MASK);
    FL_SET(re, KCODE_FIXED);
}

static int curr_kcode;

static void
kcode_set_option(re)
    VALUE re;
{
    if (!FL_TEST(re, KCODE_FIXED)) return;

    curr_kcode = RBASIC(re)->flags & KCODE_MASK;
    if (reg_kcode == curr_kcode) return;
    switch (curr_kcode) {
      case KCODE_NONE:
	re_mbcinit(MBCTYPE_ASCII);
	break;
      case KCODE_EUC:
	re_mbcinit(MBCTYPE_EUC);
	break;
      case KCODE_SJIS:
	re_mbcinit(MBCTYPE_SJIS);
	break;
      case KCODE_UTF8:
	re_mbcinit(MBCTYPE_UTF8);
	break;
    }
}	  

static void
kcode_reset_option()
{
    if (reg_kcode == curr_kcode) return;
    switch (reg_kcode) {
      case KCODE_NONE:
	re_mbcinit(MBCTYPE_ASCII);
	break;
      case KCODE_EUC:
	re_mbcinit(MBCTYPE_EUC);
	break;
      case KCODE_SJIS:
	re_mbcinit(MBCTYPE_SJIS);
	break;
      case KCODE_UTF8:
	re_mbcinit(MBCTYPE_UTF8);
	break;
    }
}

int
rb_reg_mbclen2(c, re)
    unsigned int c;
    VALUE re;
{
    int len;

    if (!FL_TEST(re, KCODE_FIXED))
	return mbclen(c);
    kcode_set_option(re);
    len = mbclen(c);
    kcode_reset_option();
    return len;
}

static void
rb_reg_check(re)
    VALUE re;
{
    if (!RREGEXP(re)->ptr || !RREGEXP(re)->str) {
	rb_raise(rb_eTypeError, "uninitialized Regexp");
    }
}

extern int ruby_in_compile;

static void
rb_reg_expr_str(str, s, len)
    VALUE str;
    const char *s;
    long len;
{
    const char *p, *pend;
    int need_escape = 0;

    p = s; pend = p + len;
    while (p<pend) {
	if (*p == '/' || (!ISPRINT(*p) && !ismbchar(*p))) {
	    need_escape = 1;
	    break;
	}
	p += mbclen(*p);
    }
    if (!need_escape) {
	rb_str_buf_cat(str, s, len);
    }
    else {
	p = s; 
	while (p<pend) {
	    if (*p == '\\') {
		int n = mbclen(p[1]) + 1;
		rb_str_buf_cat(str, p, n);
		p += n;
		continue;
	    }
	    else if (*p == '/') {
		char c = '\\';
		rb_str_buf_cat(str, &c, 1);
		rb_str_buf_cat(str, p, 1);
	    }
	    else if (ismbchar(*p)) {
	    	rb_str_buf_cat(str, p, mbclen(*p));
		p += mbclen(*p);
		continue;
	    }
	    else if (ISPRINT(*p)) {
		rb_str_buf_cat(str, p, 1);
	    }
	    else if (!ISSPACE(*p)) {
		char b[8];

		sprintf(b, "\\%03o", *p & 0377);
		rb_str_buf_cat(str, b, 4);
	    }
	    else {
		rb_str_buf_cat(str, p, 1);
	    }
	    p++;
	}
    }
}

static VALUE
rb_reg_desc(s, len, re)
    const char *s;
    long len;
    VALUE re;
{
    VALUE str = rb_str_buf_new2("/");

    rb_reg_expr_str(str, s, len);
    rb_str_buf_cat2(str, "/");
    if (re) {
	rb_reg_check(re);
	if (RREGEXP(re)->ptr->options & RE_OPTION_MULTILINE)
	    rb_str_buf_cat2(str, "m");
	if (RREGEXP(re)->ptr->options & RE_OPTION_IGNORECASE)
	    rb_str_buf_cat2(str, "i");
	if (RREGEXP(re)->ptr->options & RE_OPTION_EXTENDED)
	    rb_str_buf_cat2(str, "x");
	
	if (FL_TEST(re, KCODE_FIXED)) {
	    switch ((RBASIC(re)->flags & KCODE_MASK)) {
	      case KCODE_NONE:
		rb_str_buf_cat2(str, "n");
		break;
	      case KCODE_EUC:
		rb_str_buf_cat2(str, "e");
		break;
	      case KCODE_SJIS:
		rb_str_buf_cat2(str, "s");
		break;
	      case KCODE_UTF8:
		rb_str_buf_cat2(str, "u");
		break;
	    }
	}
    }
    OBJ_INFECT(str, re);
    return str;
}

static VALUE
rb_reg_source(re)
    VALUE re;
{
    VALUE str;

    rb_reg_check(re);
    str = rb_str_new(RREGEXP(re)->str,RREGEXP(re)->len);
    if (OBJ_TAINTED(re)) OBJ_TAINT(str);
    return str;
}

static VALUE
rb_reg_inspect(re)
    VALUE re;
{
    rb_reg_check(re);
    return rb_reg_desc(RREGEXP(re)->str, RREGEXP(re)->len, re);
}

static VALUE
rb_reg_to_s(re)
    VALUE re;
{
    int options;
    const int embeddable = RE_OPTION_MULTILINE|RE_OPTION_IGNORECASE|RE_OPTION_EXTENDED;
    long len;
    const char* ptr;
    VALUE str = rb_str_buf_new2("(?");

    rb_reg_check(re);

    options = RREGEXP(re)->ptr->options;
    ptr = RREGEXP(re)->str;
    len = RREGEXP(re)->len;
  again:
    if (len >= 4 && ptr[0] == '(' && ptr[1] == '?') {
	int err = 1;
	ptr += 2;
	if ((len -= 2) > 0) {
	    do {
		if (*ptr == 'm') {
		    options |= RE_OPTION_MULTILINE;
		}
		else if (*ptr == 'i') {
		    options |= RE_OPTION_IGNORECASE;
		}
		else if (*ptr == 'x') {
		    options |= RE_OPTION_EXTENDED;
		}
		else break;
		++ptr;
	    } while (--len > 0);
	}
	if (len > 1 && *ptr == '-') {
	    ++ptr;
	    --len;
	    do {
		if (*ptr == 'm') {
		    options &= ~RE_OPTION_MULTILINE;
		}
		else if (*ptr == 'i') {
		    options &= ~RE_OPTION_IGNORECASE;
		}
		else if (*ptr == 'x') {
		    options &= ~RE_OPTION_EXTENDED;
		}
		else break;
		++ptr;
	    } while (--len > 0);
	}
	if (*ptr == ')') {
	    --len;
	    ++ptr;
	    goto again;
	}
	if (*ptr == ':' && ptr[len-1] == ')') {
	    Regexp *rp;
	    kcode_set_option(re);
	    rp = ALLOC(Regexp);
	    MEMZERO((char *)rp, Regexp, 1);
	    err = re_compile_pattern(++ptr, len -= 2, rp) != 0;
	    kcode_reset_option();
	    re_free_pattern(rp);
	}
	if (err) {
	    options = RREGEXP(re)->ptr->options;
	    ptr = RREGEXP(re)->str;
	    len = RREGEXP(re)->len;
	}
    }

    if (options & RE_OPTION_MULTILINE) rb_str_buf_cat2(str, "m");
    if (options & RE_OPTION_IGNORECASE) rb_str_buf_cat2(str, "i");
    if (options & RE_OPTION_EXTENDED) rb_str_buf_cat2(str, "x");

    if ((options & embeddable) != embeddable) {
	rb_str_buf_cat2(str, "-");
	if (!(options & RE_OPTION_MULTILINE)) rb_str_buf_cat2(str, "m");
	if (!(options & RE_OPTION_IGNORECASE)) rb_str_buf_cat2(str, "i");
	if (!(options & RE_OPTION_EXTENDED)) rb_str_buf_cat2(str, "x");
    }

    rb_str_buf_cat2(str, ":");
    rb_reg_expr_str(str, ptr, len);
    rb_str_buf_cat2(str, ")");

    OBJ_INFECT(str, re);
    return str;
}

static void
rb_reg_raise(s, len, err, re)
    const char *s;
    long len;
    const char *err;
    VALUE re;
{
    VALUE desc = rb_reg_desc(s, len, re);

    if (ruby_in_compile)
	rb_compile_error("%s: %s", err, RSTRING(desc)->ptr);
    else
	rb_raise(rb_eRegexpError, "%s: %s", err, RSTRING(desc)->ptr);
}

static VALUE
rb_reg_casefold_p(re)
    VALUE re;
{
    rb_reg_check(re);
    if (RREGEXP(re)->ptr->options & RE_OPTION_IGNORECASE) return Qtrue;
    return Qfalse;
}

static VALUE
rb_reg_options_m(re)
    VALUE re;
{
    int options = rb_reg_options(re);
    return INT2NUM(options);
}

static VALUE
rb_reg_kcode_m(re)
    VALUE re;
{
    char *kcode;

    if (FL_TEST(re, KCODE_FIXED)) {
	switch (RBASIC(re)->flags & KCODE_MASK) {
	  case KCODE_NONE:
	    kcode = "none"; break;
	  case KCODE_EUC:
	    kcode = "euc"; break;
	  case KCODE_SJIS:
	    kcode = "sjis"; break;
	  case KCODE_UTF8:
	    kcode = "utf8"; break;
	  default:
	    rb_bug("unknown kcode - should not happen");
	    break;
	}
	return rb_str_new2(kcode);
    }
    return Qnil;
}

static Regexp*
make_regexp(s, len, flags)
    const char *s;
    long len;
    int flags;
{
    Regexp *rp;
    char *err;

    /* Handle escaped characters first. */

    /* Build a copy of the string (in dest) with the
       escaped characters translated,  and generate the regex
       from that.
    */

    rp = ALLOC(Regexp);
    MEMZERO((char *)rp, Regexp, 1);
    rp->buffer = ALLOC_N(char, 16);
    rp->allocated = 16;
    rp->fastmap = ALLOC_N(char, 256);
    if (flags) {
	rp->options = flags;
    }
    err = re_compile_pattern(s, len, rp);

    if (err != NULL) {
	rb_reg_raise(s, len, err, 0);
    }
    return rp;
}

static VALUE rb_cMatch;

static VALUE match_alloc _((VALUE));
static VALUE
match_alloc(klass)
    VALUE klass;
{
    NEWOBJ(match, struct RMatch);
    OBJSETUP(match, klass, T_MATCH);

    match->str = 0;
    match->regs = 0;
    match->regs = ALLOC(struct re_registers);
    MEMZERO(match->regs, struct re_registers, 1);

    return (VALUE)match;
}

static VALUE
match_init_copy(obj, orig)
    VALUE obj, orig;
{
    if (obj == orig) return obj;

    if (!rb_obj_is_instance_of(orig, rb_obj_class(obj))) {
	rb_raise(rb_eTypeError, "wrong argument class");
    }
    RMATCH(obj)->str = RMATCH(orig)->str;
    re_free_registers(RMATCH(obj)->regs);
    RMATCH(obj)->regs->allocated = 0;
    re_copy_registers(RMATCH(obj)->regs, RMATCH(orig)->regs);

    return obj;
}

static VALUE
match_size(match)
    VALUE match;
{
    return INT2FIX(RMATCH(match)->regs->num_regs);
}

static VALUE
match_offset(match, n)
    VALUE match, n;
{
    int i = NUM2INT(n);

    if (i < 0 || RMATCH(match)->regs->num_regs <= i)
	rb_raise(rb_eIndexError, "index %d out of matches", i);

    if (RMATCH(match)->regs->beg[i] < 0)
	return rb_assoc_new(Qnil, Qnil);

    return rb_assoc_new(INT2FIX(RMATCH(match)->regs->beg[i]),
			INT2FIX(RMATCH(match)->regs->end[i]));
}

static VALUE
match_begin(match, n)
    VALUE match, n;
{
    int i = NUM2INT(n);

    if (i < 0 || RMATCH(match)->regs->num_regs <= i)
	rb_raise(rb_eIndexError, "index %d out of matches", i);

    if (RMATCH(match)->regs->beg[i] < 0)
	return Qnil;

    return INT2FIX(RMATCH(match)->regs->beg[i]);
}

static VALUE
match_end(match, n)
    VALUE match, n;
{
    int i = NUM2INT(n);

    if (i < 0 || RMATCH(match)->regs->num_regs <= i)
	rb_raise(rb_eIndexError, "index %d out of matches", i);

    if (RMATCH(match)->regs->beg[i] < 0)
	return Qnil;

    return INT2FIX(RMATCH(match)->regs->end[i]);
}

#define MATCH_BUSY FL_USER2

void
rb_match_busy(match)
    VALUE match;
{
    FL_SET(match, MATCH_BUSY);
}

int ruby_ignorecase;
static int may_need_recompile;

static void
rb_reg_prepare_re(re)
    VALUE re;
{
    int need_recompile = 0;
    int state;

    rb_reg_check(re);
    state = FL_TEST(re, REG_CASESTATE);
    /* ignorecase status */
    if (ruby_ignorecase && !state) {
	FL_SET(re, REG_CASESTATE);
	RREGEXP(re)->ptr->options |= RE_OPTION_IGNORECASE;
	need_recompile = 1;
    }
    if (!ruby_ignorecase && state) {
	FL_UNSET(re, REG_CASESTATE);
	RREGEXP(re)->ptr->options &= ~RE_OPTION_IGNORECASE;
	need_recompile = 1;
    }

    if (!FL_TEST(re, KCODE_FIXED) &&
	(RBASIC(re)->flags & KCODE_MASK) != reg_kcode) {
	need_recompile = 1;
	RBASIC(re)->flags &= ~KCODE_MASK;
	RBASIC(re)->flags |= reg_kcode;
    }

    if (need_recompile) {
	char *err;

	if (FL_TEST(re, KCODE_FIXED))
	    kcode_set_option(re);
	rb_reg_check(re);
	RREGEXP(re)->ptr->fastmap_accurate = 0;
	err = re_compile_pattern(RREGEXP(re)->str, RREGEXP(re)->len, RREGEXP(re)->ptr);
	if (err != NULL) {
	    rb_reg_raise(RREGEXP(re)->str, RREGEXP(re)->len, err, re);
	}
    }
}

long
rb_reg_adjust_startpos(re, str, pos, reverse)
    VALUE re, str;
    long pos, reverse;
{
    long range;

    rb_reg_check(re);
    if (may_need_recompile) rb_reg_prepare_re(re);

    if (FL_TEST(re, KCODE_FIXED))
	kcode_set_option(re);
    else if (reg_kcode != curr_kcode)
	kcode_reset_option();

    if (reverse) {
	range = -pos;
    }
    else {
	range = RSTRING(str)->len - pos;
    }
    return re_adjust_startpos(RREGEXP(re)->ptr,
			      RSTRING(str)->ptr, RSTRING(str)->len,
			      pos, range);
}

long
rb_reg_search(re, str, pos, reverse)
    VALUE re, str;
    long pos, reverse;
{
    long result;
    VALUE match;
    static struct re_registers regs;
    long range;

    if (pos > RSTRING(str)->len || pos < 0) {
	rb_backref_set(Qnil);
	return -1;
    }

    rb_reg_check(re);
    if (may_need_recompile) rb_reg_prepare_re(re);

    if (FL_TEST(re, KCODE_FIXED))
	kcode_set_option(re);
    else if (reg_kcode != curr_kcode)
	kcode_reset_option();

    if (reverse) {
	range = -pos;
    }
    else {
	range = RSTRING(str)->len - pos;
    }
    result = re_search(RREGEXP(re)->ptr,RSTRING(str)->ptr,RSTRING(str)->len,
		       pos, range, &regs);

    if (FL_TEST(re, KCODE_FIXED))
	kcode_reset_option();

    if (result == -2) {
	rb_reg_raise(RREGEXP(re)->str, RREGEXP(re)->len,
		     "Stack overflow in regexp matcher", re);
    }

    if (result < 0) {
	rb_backref_set(Qnil);
	return result;
    }

    match = rb_backref_get();
    if (NIL_P(match) || FL_TEST(match, MATCH_BUSY)) {
	match = match_alloc(rb_cMatch);
    }
    else {
	if (rb_safe_level() >= 3) 
	    OBJ_TAINT(match);
	else
	    FL_UNSET(match, FL_TAINT);
    }

    re_copy_registers(RMATCH(match)->regs, &regs);
    RMATCH(match)->str = rb_str_new4(str);
    rb_backref_set(match);

    OBJ_INFECT(match, re);
    OBJ_INFECT(match, str);
    return result;
}

VALUE
rb_reg_nth_defined(nth, match)
    int nth;
    VALUE match;
{
    if (NIL_P(match)) return Qnil;
    if (nth >= RMATCH(match)->regs->num_regs) {
	return Qnil;
    }
    if (nth < 0) {
	nth += RMATCH(match)->regs->num_regs;
	if (nth <= 0) return Qnil;
    }
    if (RMATCH(match)->BEG(nth) == -1) return Qfalse;
    return Qtrue;
}

VALUE
rb_reg_nth_match(nth, match)
    int nth;
    VALUE match;
{
    VALUE str;
    long start, end, len;

    if (NIL_P(match)) return Qnil;
    if (nth >= RMATCH(match)->regs->num_regs) {
	return Qnil;
    }
    if (nth < 0) {
	nth += RMATCH(match)->regs->num_regs;
	if (nth <= 0) return Qnil;
    }
    start = RMATCH(match)->BEG(nth);
    if (start == -1) return Qnil;
    end = RMATCH(match)->END(nth);
    len = end - start;
    str = rb_str_substr(RMATCH(match)->str, start, len);
    OBJ_INFECT(str, match);
    return str;
}

VALUE
rb_reg_last_match(match)
    VALUE match;
{
    return rb_reg_nth_match(0, match);
}

VALUE
rb_reg_match_pre(match)
    VALUE match;
{
    VALUE str;

    if (NIL_P(match)) return Qnil;
    if (RMATCH(match)->BEG(0) == -1) return Qnil;
    str = rb_str_substr(RMATCH(match)->str, 0, RMATCH(match)->BEG(0));
    if (OBJ_TAINTED(match)) OBJ_TAINT(str);
    return str;
}

VALUE
rb_reg_match_post(match)
    VALUE match;
{
    VALUE str;
    long pos;

    if (NIL_P(match)) return Qnil;
    if (RMATCH(match)->BEG(0) == -1) return Qnil;
    str = RMATCH(match)->str;
    pos = RMATCH(match)->END(0);
    str = rb_str_substr(str, pos, RSTRING(str)->len - pos);
    if (OBJ_TAINTED(match)) OBJ_TAINT(str);
    return str;
}

VALUE
rb_reg_match_last(match)
    VALUE match;
{
    int i;

    if (NIL_P(match)) return Qnil;
    if (RMATCH(match)->BEG(0) == -1) return Qnil;

    for (i=RMATCH(match)->regs->num_regs-1; RMATCH(match)->BEG(i) == -1 && i > 0; i--)
	;
    if (i == 0) return Qnil;
    return rb_reg_nth_match(i, match);
}

static VALUE
last_match_getter()
{
    return rb_reg_last_match(rb_backref_get());
}

static VALUE
prematch_getter()
{
    return rb_reg_match_pre(rb_backref_get());
}

static VALUE
postmatch_getter()
{
    return rb_reg_match_post(rb_backref_get());
}

static VALUE
last_paren_match_getter()
{
    return rb_reg_match_last(rb_backref_get());
}

static VALUE
match_array(match, start)
    VALUE match;
    int start;
{
    struct re_registers *regs = RMATCH(match)->regs;
    VALUE ary = rb_ary_new2(regs->num_regs);
    VALUE target = RMATCH(match)->str;
    int i;
    int taint = OBJ_TAINTED(match);
    
    for (i=start; i<regs->num_regs; i++) {
	if (regs->beg[i] == -1) {
	    rb_ary_push(ary, Qnil);
	}
	else {
	    VALUE str = rb_str_substr(target, regs->beg[i], regs->end[i]-regs->beg[i]);
	    if (taint) OBJ_TAINT(str);
	    rb_ary_push(ary, str);
	}
    }
    return ary;
}

static VALUE
match_to_a(match)
    VALUE match;
{
    return match_array(match, 0);
}

static VALUE
match_captures(match)
    VALUE match;
{
    return match_array(match, 1);
}

static VALUE
match_aref(argc, argv, match)
    int argc;
    VALUE *argv;
    VALUE match;
{
    VALUE idx, rest;

    rb_scan_args(argc, argv, "11", &idx, &rest);

    if (!NIL_P(rest) || !FIXNUM_P(idx) || FIX2INT(idx) < 0) {
	return rb_ary_aref(argc, argv, match_to_a(match));
    }
    return rb_reg_nth_match(FIX2INT(idx), match);
}

static VALUE match_entry _((VALUE, long));
static VALUE
match_entry(match, n)
    VALUE match;
    long n;
{
    return rb_reg_nth_match(n, match);
}

static VALUE
match_values_at(argc, argv, match)
    int argc;
    VALUE *argv;
    VALUE match;
{
    return rb_values_at(match, RMATCH(match)->regs->num_regs, argc, argv, match_entry);
}

static VALUE
match_select(argc, argv, match)
    int argc;
    VALUE *argv;
    VALUE match;
{
    if (argc > 0) {
	rb_raise(rb_eArgError, "wrong number arguments(%d for 0)", argc);
    }
    else {
	struct re_registers *regs = RMATCH(match)->regs;
	VALUE target = RMATCH(match)->str;
	VALUE result = rb_ary_new();
	int i;
	int taint = OBJ_TAINTED(match);

	for (i=0; i<regs->num_regs; i++) {
	    VALUE str = rb_str_substr(target, regs->beg[i], regs->end[i]-regs->beg[i]);
	    if (taint) OBJ_TAINT(str);
	    if (RTEST(rb_yield(str))) {
		rb_ary_push(result, str);
	    }
	}
	return result;
    }
}

static VALUE
match_to_s(match)
    VALUE match;
{
    VALUE str = rb_reg_last_match(match);

    if (NIL_P(str)) str = rb_str_new(0,0);
    if (OBJ_TAINTED(match)) OBJ_TAINT(str);
    if (OBJ_TAINTED(RMATCH(match)->str)) OBJ_TAINT(str);
    return str;
}

static VALUE
match_string(match)
    VALUE match;
{
    return RMATCH(match)->str;	/* str is frozen */
}

VALUE rb_cRegexp;

static void
rb_reg_initialize(obj, s, len, options)
    VALUE obj;
    const char *s;
    long len;
    int options;		/* CASEFOLD  = 1 */
				/* EXTENDED  = 2 */
				/* MULTILINE = 4 */
				/* CODE_NONE = 16 */
				/* CODE_EUC  = 32 */
				/* CODE_SJIS = 48 */
				/* CODE_UTF8 = 64 */
{
    struct RRegexp *re = RREGEXP(obj);

    if (re->ptr) re_free_pattern(re->ptr);
    if (re->str) free(re->str);
    re->ptr = 0;
    re->str = 0;

    switch (options & ~0xf) {
      case 0:
      default:
	FL_SET(re, reg_kcode);
	break;
      case 16:
	kcode_none(re);
	break;
      case 32:
	kcode_euc(re);
	break;
      case 48:
	kcode_sjis(re);
	break;
      case 64:
	kcode_utf8(re);
	break;
    }

    if (options & ~0xf) {
	kcode_set_option((VALUE)re);
    }
    if (ruby_ignorecase) {
	options |= RE_OPTION_IGNORECASE;
	FL_SET(re, REG_CASESTATE);
    }
    re->ptr = make_regexp(s, len, options & 0xf);
    re->str = ALLOC_N(char, len+1);
    memcpy(re->str, s, len);
    re->str[len] = '\0';
    re->len = len;
    if (options & ~0xf) {
	kcode_reset_option();
    }
}

static VALUE rb_reg_s_alloc _((VALUE));
static VALUE
rb_reg_s_alloc(klass)
    VALUE klass;
{
    NEWOBJ(re, struct RRegexp);
    OBJSETUP(re, klass, T_REGEXP);

    re->ptr = 0;
    re->len = 0;
    re->str = 0;

    return (VALUE)re;
}

VALUE
rb_reg_new(s, len, options)
    const char *s;
    long len;
    int options;
{
    VALUE re = rb_reg_s_alloc(rb_cRegexp);

    rb_reg_initialize(re, s, len, options);
    return (VALUE)re;
}

static int case_cache;
static int kcode_cache;
static VALUE reg_cache;

VALUE
rb_reg_regcomp(str)
    VALUE str;
{
    if (reg_cache && RREGEXP(reg_cache)->len == RSTRING(str)->len
	&& case_cache == ruby_ignorecase
	&& kcode_cache == reg_kcode
	&& memcmp(RREGEXP(reg_cache)->str, RSTRING(str)->ptr, RSTRING(str)->len) == 0)
	return reg_cache;

    case_cache = ruby_ignorecase;
    kcode_cache = reg_kcode;
    return reg_cache = rb_reg_new(RSTRING(str)->ptr, RSTRING(str)->len,
				  ruby_ignorecase);
}

static int
rb_reg_cur_kcode(re)
    VALUE re;
{
    if (FL_TEST(re, KCODE_FIXED)) {
	return RBASIC(re)->flags & KCODE_MASK;
    }
    return 0;
}

static VALUE
rb_reg_hash(re)
    VALUE re;
{
    int hashval, len;
    char *p;

    rb_reg_check(re);
    hashval = RREGEXP(re)->ptr->options;
    len = RREGEXP(re)->len;
    p  = RREGEXP(re)->str;
    while (len--) {
	hashval = hashval * 33 + *p++;
    }
    hashval = hashval + (hashval>>5);
    
    return INT2FIX(hashval);
}

static VALUE
rb_reg_equal(re1, re2)
    VALUE re1, re2;
{
    if (re1 == re2) return Qtrue;
    if (TYPE(re2) != T_REGEXP) return Qfalse;
    rb_reg_check(re1); rb_reg_check(re2);
    if (RREGEXP(re1)->len != RREGEXP(re2)->len) return Qfalse;
    if (memcmp(RREGEXP(re1)->str, RREGEXP(re2)->str, RREGEXP(re1)->len) == 0 &&
	rb_reg_cur_kcode(re1) == rb_reg_cur_kcode(re2) &&
	RREGEXP(re1)->ptr->options == RREGEXP(re2)->ptr->options) {
	return Qtrue;
    }
    return Qfalse;
}

VALUE
rb_reg_match(re, str)
    VALUE re, str;
{
    long start;

    if (NIL_P(str)) {
	rb_backref_set(Qnil);
	return Qnil;
    }
    StringValue(str);
    start = rb_reg_search(re, str, 0, 0);
    if (start < 0) {
	return Qnil;
    }
    return LONG2FIX(start);
}

VALUE
rb_reg_eqq(re, str)
    VALUE re, str;
{
    long start;

    if (TYPE(str) != T_STRING) {
	str = rb_check_string_type(str);
	if (NIL_P(str)) {
	    rb_backref_set(Qnil);
	    return Qfalse;
	}
    }
    StringValue(str);
    start = rb_reg_search(re, str, 0, 0);
    if (start < 0) {
	return Qfalse;
    }
    return Qtrue;
}

VALUE
rb_reg_match2(re)
    VALUE re;
{
    long start;
    VALUE line = rb_lastline_get();

    if (TYPE(line) != T_STRING) {
	rb_backref_set(Qnil);
	return Qnil;
    }

    start = rb_reg_search(re, line, 0, 0);
    if (start < 0) {
	return Qnil;
    }
    return LONG2FIX(start);
}

static VALUE
rb_reg_match_m(re, str)
    VALUE re, str;
{
    VALUE result = rb_reg_match(re, str);

    if (NIL_P(result)) return Qnil;
    result = rb_backref_get();
    rb_match_busy(result);
    return result;
}

static VALUE
rb_reg_initialize_m(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    const char *s;
    long len;
    int flags = 0;

    rb_check_frozen(self);
    if (argc == 0 || argc > 3) {
	rb_raise(rb_eArgError, "wrong number of argument");
    }
    if (TYPE(argv[0]) == T_REGEXP) {
	if (argc > 1) {
	    rb_warn("flags%s ignored", (argc == 3) ? " and encoding": "");
	}
	rb_reg_check(argv[0]);
	flags = RREGEXP(argv[0])->ptr->options & 0xf;
	if (FL_TEST(argv[0], KCODE_FIXED)) {
	    switch (RBASIC(argv[0])->flags & KCODE_MASK) {
	      case KCODE_NONE:
		flags |= 16;
		break;
	      case KCODE_EUC:
		flags |= 32;
		break;
	      case KCODE_SJIS:
		flags |= 48;
		break;
	      case KCODE_UTF8:
		flags |= 64;
		break;
	      default:
		break;
	    }
	}
	s = RREGEXP(argv[0])->str;
	len = RREGEXP(argv[0])->len;
    }
    else {
	s = StringValuePtr(argv[0]);
	len = RSTRING(argv[0])->len;
	if (argc >= 2) {
	    if (FIXNUM_P(argv[1])) flags = FIX2INT(argv[1]);
	    else if (RTEST(argv[1])) flags = RE_OPTION_IGNORECASE;
	}
	if (argc == 3 && !NIL_P(argv[2])) {
	    char *kcode = StringValuePtr(argv[2]);

	    flags &= ~0x70;
	    switch (kcode[0]) {
	      case 'n': case 'N':
		flags |= 16;
		break;
	      case 'e': case 'E':
		flags |= 32;
		break;
	      case 's': case 'S':
		flags |= 48;
		break;
	      case 'u': case 'U':
		flags |= 64;
		break;
	      default:
		break;
	    }
	}
    }
    rb_reg_initialize(self, s, len, flags);
    return self;
}

VALUE
rb_reg_quote(str)
    VALUE str;
{
    char *s, *send, *t;
    VALUE tmp;
    int c;

    s = RSTRING(str)->ptr;
    send = s + RSTRING(str)->len;
    for (; s < send; s++) {
	c = *s;
	if (ismbchar(c)) {
	    int n = mbclen(c);

	    while (n-- && s < send)
		s++;
	    s--;
	    continue;
	}
	switch (c) {
	  case '[': case ']': case '{': case '}':
	  case '(': case ')': case '|': case '-':
	  case '*': case '.': case '\\':
	  case '?': case '+': case '^': case '$':
	  case ' ': case '#':
	  case '\t': case '\f': case '\n': case '\r':
	    goto meta_found;
	}
    }
    return str;

  meta_found:
    tmp = rb_str_new(0, RSTRING(str)->len*2);
    t = RSTRING(tmp)->ptr;
    /* copy upto metacharacter */
    memcpy(t, RSTRING(str)->ptr, s - RSTRING(str)->ptr);
    t += s - RSTRING(str)->ptr;

    for (; s < send; s++) {
	c = *s;
	if (ismbchar(c)) {
	    int n = mbclen(c);

	    while (n-- && s < send)
		*t++ = *s++;
	    s--;
	    continue;
	}
	switch (c) {
	  case '[': case ']': case '{': case '}':
	  case '(': case ')': case '|': case '-':
	  case '*': case '.': case '\\':
	  case '?': case '+': case '^': case '$':
	  case '#':
	    *t++ = '\\';
	    break;
	  case ' ':
	    *t++ = '\\';
	    *t++ = ' ';
	    continue;
	  case '\t':
	    *t++ = '\\';
	    *t++ = 't';
	    continue;
	  case '\n':
	    *t++ = '\\';
	    *t++ = 'n';
	    continue;
	  case '\r':
	    *t++ = '\\';
	    *t++ = 'r';
	    continue;
	  case '\f':
	    *t++ = '\\';
	    *t++ = 'f';
	    continue;
	}
	*t++ = c;
    }
    rb_str_resize(tmp, t - RSTRING(tmp)->ptr);
    OBJ_INFECT(tmp, str);
    return tmp;
}

static VALUE
rb_reg_s_quote(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str, kcode;
    int kcode_saved = reg_kcode;

    rb_scan_args(argc, argv, "11", &str, &kcode);
    if (!NIL_P(kcode)) {
	rb_set_kcode(StringValuePtr(kcode));
	curr_kcode = reg_kcode;
	reg_kcode = kcode_saved;
    }
    StringValue(str);
    str = rb_reg_quote(str);
    kcode_reset_option();
    return str;
}

int
rb_kcode()
{
    switch (reg_kcode) {
      case KCODE_EUC:
	return MBCTYPE_EUC;
      case KCODE_SJIS:
	return MBCTYPE_SJIS;
      case KCODE_UTF8:
	return MBCTYPE_UTF8;
      case KCODE_NONE:
	return MBCTYPE_ASCII;
    }
    rb_bug("wrong reg_kcode value (0x%x)", reg_kcode);
}

static int
rb_reg_get_kcode(re)
    VALUE re;
{
    switch (RBASIC(re)->flags & KCODE_MASK) {
      case KCODE_NONE:
	return 16;
      case KCODE_EUC:
	return 32;
      case KCODE_SJIS:
	return 48;
      case KCODE_UTF8:
	return 64;
      default:
	return 0;
    }
}

int
rb_reg_options(re)
    VALUE re;
{
    int options;

    rb_reg_check(re);
    options = RREGEXP(re)->ptr->options &
	(RE_OPTION_IGNORECASE|RE_OPTION_MULTILINE|RE_OPTION_EXTENDED);
    if (FL_TEST(re, KCODE_FIXED)) {
	options |= rb_reg_get_kcode(re);
    }
    return options;
}

static VALUE
rb_reg_s_union(argc, argv)
    int argc;
    VALUE *argv;
{
    if (argc == 0) {
        VALUE args[1];
        args[0] = rb_str_new2("(?!)");
        return rb_class_new_instance(1, args, rb_cRegexp);
    }
    else if (argc == 1) {
        VALUE v;
        v = rb_check_convert_type(argv[0], T_REGEXP, "Regexp", "to_regexp");
        if (!NIL_P(v))
            return v;
        else {
            VALUE args[1];
            args[0] = rb_reg_s_quote(argc, argv);
            return rb_class_new_instance(1, args, rb_cRegexp);
        }
    }
    else {
        int i, kcode = -1;
        VALUE kcode_re = Qnil;
        VALUE source = rb_str_buf_new(0);
        VALUE args[3];
        for (i = 0; i < argc; i++) {
            volatile VALUE v;
            if (0 < i)
                rb_str_buf_cat2(source, "|");
            v = rb_check_convert_type(argv[i], T_REGEXP, "Regexp", "to_regexp");
            if (!NIL_P(v)) {
                if (FL_TEST(v, KCODE_FIXED)) {
                    if (kcode == -1) {
                        kcode_re = v;
                        kcode = RBASIC(v)->flags & KCODE_MASK;
                    }
                    else if ((RBASIC(v)->flags & KCODE_MASK) != kcode) {
                        volatile VALUE str1, str2;
                        str1 = rb_inspect(kcode_re);
                        str2 = rb_inspect(v);
                        rb_raise(rb_eArgError, "mixed kcode: %s and %s",
                            RSTRING(str1)->ptr, RSTRING(str2)->ptr);
                    }
                }
                v = rb_reg_to_s(v);
            }
            else {
                args[0] = argv[i];
                v = rb_reg_s_quote(1, args);
            }
            rb_str_buf_append(source, v);
        }
        args[0] = source;
        args[1] = Qnil;
        switch (kcode) {
          case -1:
            args[2] = Qnil;
            break;
          case KCODE_NONE:
            args[2] = rb_str_new2("n");
            break;
          case KCODE_EUC:
            args[2] = rb_str_new2("e");
            break;
          case KCODE_SJIS:
            args[2] = rb_str_new2("s");
            break;
          case KCODE_UTF8:
            args[2] = rb_str_new2("u");
            break;
        }
        return rb_class_new_instance(3, args, rb_cRegexp);
    }
}

static VALUE
rb_reg_init_copy(copy, re)
    VALUE copy, re;
{
    if (copy == re) return copy;
    rb_check_frozen(copy);
    /* need better argument type check */
    if (!rb_obj_is_instance_of(re, rb_obj_class(copy))) {
	rb_raise(rb_eTypeError, "wrong argument type");
    }
    rb_reg_check(re);
    rb_reg_initialize(copy, RREGEXP(re)->str, RREGEXP(re)->len,
		      rb_reg_options(re));
    return copy;
}

VALUE
rb_reg_regsub(str, src, regs)
    VALUE str, src;
    struct re_registers *regs;
{
    VALUE val = 0;
    char *p, *s, *e, c;
    int no;

    p = s = RSTRING(str)->ptr;
    e = s + RSTRING(str)->len;

    while (s < e) {
	char *ss = s;

	c = *s++;
	if (ismbchar(c)) {
	    s += mbclen(c) - 1;
	    continue;
	}
	if (c != '\\' || s == e) continue;

	if (!val) {
	    val = rb_str_buf_new(ss-p);
	    rb_str_buf_cat(val, p, ss-p);
	}
	else {
	    rb_str_buf_cat(val, p, ss-p);
	}

	c = *s++;
	p = s;
	switch (c) {
	  case '0': case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
	    no = c - '0';
	    break;
	  case '&':
	    no = 0;
	    break;

	  case '`':
	    rb_str_buf_cat(val, RSTRING(src)->ptr, BEG(0));
	    continue;

	  case '\'':
	    rb_str_buf_cat(val, RSTRING(src)->ptr+END(0), RSTRING(src)->len-END(0));
	    continue;

	  case '+':
	    no = regs->num_regs-1;
	    while (BEG(no) == -1 && no > 0) no--;
	    if (no == 0) continue;
	    break;

	  case '\\':
	    rb_str_buf_cat(val, s-1, 1);
	    continue;

	  default:
	    rb_str_buf_cat(val, s-2, 2);
	    continue;
	}

	if (no >= 0) {
	    if (no >= regs->num_regs) continue;
	    if (BEG(no) == -1) continue;
	    rb_str_buf_cat(val, RSTRING(src)->ptr+BEG(no), END(no)-BEG(no));
	}
    }

    if (p < e) {
	if (!val) {
	    val = rb_str_buf_new(e-p);
	    rb_str_buf_cat(val, p, e-p);
	}
	else {
	    rb_str_buf_cat(val, p, e-p);
	}
    }
    if (!val) return str;

    return val;
}

const char*
rb_get_kcode()
{
    switch (reg_kcode) {
      case KCODE_SJIS:
	return "SJIS";
      case KCODE_EUC:
	return "EUC";
      case KCODE_UTF8:
	return "UTF8";
      default:
	return "NONE";
    }
}

static VALUE
kcode_getter()
{
    return rb_str_new2(rb_get_kcode());
}

void
rb_set_kcode(code)
    const char *code;
{
    if (code == 0) goto set_no_conversion;

    switch (code[0]) {
      case 'E':
      case 'e':
	reg_kcode = KCODE_EUC;
	re_mbcinit(MBCTYPE_EUC);
	break;
      case 'S':
      case 's':
	reg_kcode = KCODE_SJIS;
	re_mbcinit(MBCTYPE_SJIS);
	break;
      case 'U':
      case 'u':
	reg_kcode = KCODE_UTF8;
	re_mbcinit(MBCTYPE_UTF8);
	break;
      default:
      case 'N':
      case 'n':
      case 'A':
      case 'a':
      set_no_conversion:
	reg_kcode = KCODE_NONE;
	re_mbcinit(MBCTYPE_ASCII);
	break;
    }
}

static void
kcode_setter(val)
    VALUE val;
{
    may_need_recompile = 1;
    rb_set_kcode(StringValuePtr(val));
}

static VALUE
ignorecase_getter()
{
    return ruby_ignorecase?Qtrue:Qfalse;
}

static void
ignorecase_setter(val, id)
    VALUE val;
    ID id;
{
    rb_warn("modifying %s is deprecated", rb_id2name(id));
    may_need_recompile = 1;
    ruby_ignorecase = RTEST(val);
}

static VALUE
match_getter()
{
    VALUE match = rb_backref_get();

    if (NIL_P(match)) return Qnil;
    rb_match_busy(match);
    return match;
}

static void
match_setter(val)
    VALUE val;
{
    if (!NIL_P(val)) {
	Check_Type(val, T_MATCH);
    }
    rb_backref_set(val);
}

static VALUE
rb_reg_s_last_match(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE nth;

    if (rb_scan_args(argc, argv, "01", &nth) == 1) {
	return rb_reg_nth_match(NUM2INT(nth), rb_backref_get());
    }
    return match_getter();
}

void
Init_Regexp()
{
    rb_eRegexpError = rb_define_class("RegexpError", rb_eStandardError);

    re_set_casetable(casetable);
#if DEFAULT_KCODE == KCODE_EUC
    re_mbcinit(MBCTYPE_EUC);
#else
#if DEFAULT_KCODE == KCODE_SJIS
    re_mbcinit(MBCTYPE_SJIS);
#else
#if DEFAULT_KCODE == KCODE_UTF8
    re_mbcinit(MBCTYPE_UTF8);
#else
    re_mbcinit(MBCTYPE_ASCII);
#endif
#endif
#endif

    rb_define_virtual_variable("$~", match_getter, match_setter);
    rb_define_virtual_variable("$&", last_match_getter, 0);
    rb_define_virtual_variable("$`", prematch_getter, 0);
    rb_define_virtual_variable("$'", postmatch_getter, 0);
    rb_define_virtual_variable("$+", last_paren_match_getter, 0);

    rb_define_virtual_variable("$=", ignorecase_getter, ignorecase_setter);
    rb_define_virtual_variable("$KCODE", kcode_getter, kcode_setter);
    rb_define_virtual_variable("$-K", kcode_getter, kcode_setter);

    rb_cRegexp = rb_define_class("Regexp", rb_cObject);
    rb_define_alloc_func(rb_cRegexp, rb_reg_s_alloc);
    rb_define_singleton_method(rb_cRegexp, "compile", rb_class_new_instance, -1);
    rb_define_singleton_method(rb_cRegexp, "quote", rb_reg_s_quote, -1);
    rb_define_singleton_method(rb_cRegexp, "escape", rb_reg_s_quote, -1);
    rb_define_singleton_method(rb_cRegexp, "union", rb_reg_s_union, -1);
    rb_define_singleton_method(rb_cRegexp, "last_match", rb_reg_s_last_match, -1);

    rb_define_method(rb_cRegexp, "initialize", rb_reg_initialize_m, -1);
    rb_define_method(rb_cRegexp, "initialize_copy", rb_reg_init_copy, 1);
    rb_define_method(rb_cRegexp, "hash", rb_reg_hash, 0);
    rb_define_method(rb_cRegexp, "eql?", rb_reg_equal, 1);
    rb_define_method(rb_cRegexp, "==", rb_reg_equal, 1);
    rb_define_method(rb_cRegexp, "=~", rb_reg_match, 1);
    rb_define_method(rb_cRegexp, "===", rb_reg_eqq, 1);
    rb_define_method(rb_cRegexp, "~", rb_reg_match2, 0);
    rb_define_method(rb_cRegexp, "match", rb_reg_match_m, 1);
    rb_define_method(rb_cRegexp, "to_s", rb_reg_to_s, 0);
    rb_define_method(rb_cRegexp, "inspect", rb_reg_inspect, 0);
    rb_define_method(rb_cRegexp, "source", rb_reg_source, 0);
    rb_define_method(rb_cRegexp, "casefold?", rb_reg_casefold_p, 0);
    rb_define_method(rb_cRegexp, "options", rb_reg_options_m, 0);
    rb_define_method(rb_cRegexp, "kcode", rb_reg_kcode_m, 0);

    rb_define_const(rb_cRegexp, "IGNORECASE", INT2FIX(RE_OPTION_IGNORECASE));
    rb_define_const(rb_cRegexp, "EXTENDED", INT2FIX(RE_OPTION_EXTENDED));
    rb_define_const(rb_cRegexp, "MULTILINE", INT2FIX(RE_OPTION_MULTILINE));

    rb_global_variable(&reg_cache);

    rb_cMatch  = rb_define_class("MatchData", rb_cObject);
    rb_define_global_const("MatchingData", rb_cMatch);
    rb_define_alloc_func(rb_cMatch, match_alloc);
    rb_undef_method(CLASS_OF(rb_cMatch), "new");

    rb_define_method(rb_cMatch, "initialize_copy", match_init_copy, 1);
    rb_define_method(rb_cMatch, "size", match_size, 0);
    rb_define_method(rb_cMatch, "length", match_size, 0);
    rb_define_method(rb_cMatch, "offset", match_offset, 1);
    rb_define_method(rb_cMatch, "begin", match_begin, 1);
    rb_define_method(rb_cMatch, "end", match_end, 1);
    rb_define_method(rb_cMatch, "to_a", match_to_a, 0);
    rb_define_method(rb_cMatch, "[]", match_aref, -1);
    rb_define_method(rb_cMatch, "captures", match_captures, 0);
    rb_define_method(rb_cMatch, "select", match_select, -1);
    rb_define_method(rb_cMatch, "values_at", match_values_at, -1);
    rb_define_method(rb_cMatch, "pre_match", rb_reg_match_pre, 0);
    rb_define_method(rb_cMatch, "post_match", rb_reg_match_post, 0);
    rb_define_method(rb_cMatch, "to_s", match_to_s, 0);
    rb_define_method(rb_cMatch, "inspect", rb_any_to_s, 0);
    rb_define_method(rb_cMatch, "string", match_string, 0);
}
