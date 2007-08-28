/**********************************************************************

  re.c -

  $Author$
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/re.h"
#include "ruby/encoding.h"
#include "regint.h"
#include <ctype.h>

#define MBCTYPE_ASCII         0
#define MBCTYPE_EUC           1
#define MBCTYPE_SJIS          2
#define MBCTYPE_UTF8          3

VALUE rb_eRegexpError;

typedef char onig_errmsg_buffer[ONIG_MAX_ERROR_MESSAGE_LEN];

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
rb_memcicmp(const void *x, const void *y, long len)
{
    const unsigned char *p1 = x, *p2 = y;
    int tmp;

    while (len--) {
	if ((tmp = casetable[(unsigned)*p1++] - casetable[(unsigned)*p2++]))
	    return tmp;
    }
    return 0;
}

int
rb_memcmp(const void *p1, const void *p2, long len)
{
    if (!ruby_ignorecase) {
	return memcmp(p1, p2, len);
    }
    return rb_memcicmp(p1, p2, len);
}

long
rb_memsearch(const void *x0, long m, const void *y0, long n)
{
    const unsigned char *x = x0, *y = y0;
    const unsigned char *s, *e;
    long i;
    int d;
    unsigned long hx, hy;

#define KR_REHASH(a, b, h) (((h) << 1) - (((unsigned long)(a))<<d) + (b))

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

#define REG_LITERAL FL_USER5
#define REG_CASESTATE  FL_USER0

#define KCODE_NONE  0
#define KCODE_EUC   FL_USER1
#define KCODE_SJIS  FL_USER2
#define KCODE_UTF8  FL_USER3
#define KCODE_FIXED FL_USER4
#define KCODE_MASK (KCODE_EUC|KCODE_SJIS|KCODE_UTF8)

#define ARG_REG_OPTION_MASK   0x0f
#define ARG_KCODE_UNIT        16
#define ARG_KCODE_NONE       (ARG_KCODE_UNIT * 1)
#define ARG_KCODE_EUC        (ARG_KCODE_UNIT * 2)
#define ARG_KCODE_SJIS       (ARG_KCODE_UNIT * 3)
#define ARG_KCODE_UTF8       (ARG_KCODE_UNIT * 4)
#define ARG_KCODE_MASK       (ARG_KCODE_UNIT * 7)

static int reg_kcode = DEFAULT_KCODE;

static int
char_to_option(int c)
{
    int val;

    switch (c) {
      case 'i':
	val = ONIG_OPTION_IGNORECASE;
	break;
      case 'x':
	val = ONIG_OPTION_EXTEND;
	break;
      case 'm':
	val = ONIG_OPTION_MULTILINE;
	break;
      default:
	val = 0;
	break;
    }
    return val;
}

static char *
option_to_str(char str[4], int options)
{
    char *p = str;
    if (options & ONIG_OPTION_MULTILINE) *p++ = 'm';
    if (options & ONIG_OPTION_IGNORECASE) *p++ = 'i';
    if (options & ONIG_OPTION_EXTEND) *p++ = 'x';
    *p = 0;
    return str;
}

static const char *
arg_kcode(int options)
{
    switch (options & ARG_KCODE_MASK) {
      case ARG_KCODE_NONE: return "n";
      case ARG_KCODE_EUC:  return "e";
      case ARG_KCODE_SJIS: return "s";
      case ARG_KCODE_UTF8: return "u";
    }
    return "";
}

static const char *
opt_kcode(int flags)
{
    switch (flags) {
      case KCODE_NONE: return "n";
      case KCODE_EUC:  return "e";
      case KCODE_SJIS: return "s";
      case KCODE_UTF8: return "u";
    }
    return "";
}

extern int
rb_char_to_option_kcode(int c, int *option, int *kcode)
{
    *option = 0;

    switch (c) {
      case 'n':
	*kcode = ARG_KCODE_NONE;
	break;
      case 'e':
	*kcode = ARG_KCODE_EUC;
	break;
      case 's':
	*kcode = ARG_KCODE_SJIS;
	break;
      case 'u':
	*kcode = ARG_KCODE_UTF8;
	break;
      default:
	*kcode  = 0;
	*option = char_to_option(c);
	break;
    }

    return ((*kcode == 0 && *option == 0) ? 0 : 1);
}

static int
char_to_arg_kcode(int c)
{
    int kcode, option;

    if (ISUPPER(c))  c = tolower(c);

    (void )rb_char_to_option_kcode(c, &option, &kcode);
    return kcode;
}

static int
kcode_to_arg_value(unsigned int kcode)
{
    switch (kcode & KCODE_MASK) {
      case KCODE_NONE:
	return ARG_KCODE_NONE;
      case KCODE_EUC:
	return ARG_KCODE_EUC;
      case KCODE_SJIS:
	return ARG_KCODE_SJIS;
      case KCODE_UTF8:
	return ARG_KCODE_UTF8;
      default:
	return 0;
    }
}

static void
set_re_kcode_by_option(struct RRegexp *re, int options)
{
    rb_encoding *enc = 0;

    FL_UNSET(re, KCODE_MASK);
    switch (options & ARG_KCODE_MASK) {
      case ARG_KCODE_NONE:
	enc = rb_enc_from_index(0);
	FL_SET(re, KCODE_NONE);
	FL_SET(re, KCODE_FIXED);
	break;
      case ARG_KCODE_EUC:
	enc = rb_enc_find("euc-jp");
	FL_SET(re, KCODE_EUC);
	FL_SET(re, KCODE_FIXED);
	break;
      case ARG_KCODE_SJIS:
	enc = rb_enc_find("sjis");
	FL_SET(re, KCODE_FIXED);
	FL_SET(re, KCODE_SJIS);
	break;
      case ARG_KCODE_UTF8:
	enc = rb_enc_find("utf-8");
	FL_SET(re, KCODE_UTF8);
	FL_SET(re, KCODE_FIXED);
	break;

      case 0:
      default:
	FL_SET(re, reg_kcode);
	break;
    }
    if (enc) {
	rb_enc_associate((VALUE)re, enc);
    }
}

static int
re_to_kcode_arg_value(VALUE re)
{
    return kcode_to_arg_value(RBASIC(re)->flags);
}

static int curr_kcode;

static void
kcode_set_option(VALUE re)
{
    if (!FL_TEST(re, KCODE_FIXED)) return;

    curr_kcode = RBASIC(re)->flags & KCODE_MASK;
    if (reg_kcode == curr_kcode) return;
    switch (curr_kcode) {
      case KCODE_NONE:
	onigenc_set_default_encoding(ONIG_ENCODING_ASCII);
	break;
      case KCODE_EUC:
	onigenc_set_default_encoding(ONIG_ENCODING_EUC_JP);
	break;
      case KCODE_SJIS:
	onigenc_set_default_encoding(ONIG_ENCODING_SJIS);
	break;
      case KCODE_UTF8:
	onigenc_set_default_encoding(ONIG_ENCODING_UTF8);
	break;
    }
}

static void
kcode_reset_option(void)
{
    if (reg_kcode == curr_kcode) return;
    switch (reg_kcode) {
      case KCODE_NONE:
	onigenc_set_default_encoding(ONIG_ENCODING_ASCII);
	break;
      case KCODE_EUC:
	onigenc_set_default_encoding(ONIG_ENCODING_EUC_JP);
	break;
      case KCODE_SJIS:
	onigenc_set_default_encoding(ONIG_ENCODING_SJIS);
	break;
      case KCODE_UTF8:
	onigenc_set_default_encoding(ONIG_ENCODING_UTF8);
	break;
    }
}

int
rb_reg_mbclen2(unsigned int c, VALUE re)
{
    unsigned char uc = (unsigned char)c;

    return rb_enc_mbclen(&uc, rb_enc_get(re));
}

static void
rb_reg_check(VALUE re)
{
    if (!RREGEXP(re)->ptr || !RREGEXP(re)->str) {
	rb_raise(rb_eTypeError, "uninitialized Regexp");
    }
}

static void
rb_reg_expr_str(VALUE str, const char *s, long len)
{
    rb_encoding *enc = rb_enc_get(str);
    const char *p, *pend;
    int need_escape = 0;

    p = s; pend = p + len;
    while (p<pend) {
	if (*p == '/' || (!rb_enc_isprint(*p, enc) && !ismbchar(p, enc))) {
	    need_escape = 1;
	    break;
	}
	p += mbclen(p, enc);
    }
    if (!need_escape) {
	rb_str_buf_cat(str, s, len);
    }
    else {
	p = s;
	while (p<pend) {
	    if (*p == '\\') {
		int n = mbclen(p+1, enc) + 1;
		rb_str_buf_cat(str, p, n);
		p += n;
		continue;
	    }
	    else if (*p == '/') {
		char c = '\\';
		rb_str_buf_cat(str, &c, 1);
		rb_str_buf_cat(str, p, 1);
	    }
	    else if (ismbchar(p, enc)) {
	    	rb_str_buf_cat(str, p, mbclen(p, enc));
		p += mbclen(p, enc);
		continue;
	    }
	    else if (rb_enc_isprint(*p, enc)) {
		rb_str_buf_cat(str, p, 1);
	    }
	    else if (!rb_enc_isspace(*p, enc)) {
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
rb_reg_desc(const char *s, long len, VALUE re)
{
    VALUE str = rb_str_buf_new2("/");

    rb_reg_expr_str(str, s, len);
    rb_str_buf_cat2(str, "/");
    if (re) {
	char opts[4];
	rb_reg_check(re);
	if (*option_to_str(opts, RREGEXP(re)->ptr->options))
	    rb_str_buf_cat2(str, opts);

	if (FL_TEST(re, KCODE_FIXED)) {
	    rb_str_buf_cat2(str, opt_kcode(RBASIC(re)->flags & KCODE_MASK));
	}
    }
    OBJ_INFECT(str, re);
    return str;
}


/*
 *  call-seq:
 *     rxp.source   => str
 *
 *  Returns the original string of the pattern.
 *
 *     /ab+c/ix.source   #=> "ab+c"
 */

static VALUE
rb_reg_source(VALUE re)
{
    VALUE str;

    rb_reg_check(re);
    str = rb_str_new(RREGEXP(re)->str,RREGEXP(re)->len);
    if (OBJ_TAINTED(re)) OBJ_TAINT(str);
    return str;
}

/*
 * call-seq:
 *    rxp.inspect   => string
 *
 * Produce a nicely formatted string-version of _rxp_. Perhaps surprisingly,
 * <code>#inspect</code> actually produces the more natural version of
 * the string than <code>#to_s</code>.
 *
 *     /ab+c/ix.to_s         #=> /ab+c/ix
*/

static VALUE
rb_reg_inspect(VALUE re)
{
    rb_reg_check(re);
    return rb_reg_desc(RREGEXP(re)->str, RREGEXP(re)->len, re);
}


/*
 *  call-seq:
 *     rxp.to_s   => str
 *
 *  Returns a string containing the regular expression and its options (using the
 *  <code>(?xxx:yyy)</code> notation. This string can be fed back in to
 *  <code>Regexp::new</code> to a regular expression with the same semantics as
 *  the original. (However, <code>Regexp#==</code> may not return true when
 *  comparing the two, as the source of the regular expression itself may
 *  differ, as the example shows).  <code>Regexp#inspect</code> produces a
 *  generally more readable version of <i>rxp</i>.
 *
 *     r1 = /ab+c/ix         #=> /ab+c/ix
 *     s1 = r1.to_s          #=> "(?ix-m:ab+c)"
 *     r2 = Regexp.new(s1)   #=> /(?ix-m:ab+c)/
 *     r1 == r2              #=> false
 *     r1.source             #=> "ab+c"
 *     r2.source             #=> "(?ix-m:ab+c)"
 */

static VALUE
rb_reg_to_s(VALUE re)
{
    int options, opt;
    const int embeddable = ONIG_OPTION_MULTILINE|ONIG_OPTION_IGNORECASE|ONIG_OPTION_EXTEND;
    long len;
    const UChar* ptr;
    VALUE str = rb_str_buf_new2("(?");
    char optbuf[5];

    rb_reg_check(re);

    options = RREGEXP(re)->ptr->options;
    ptr = (UChar*)RREGEXP(re)->str;
    len = RREGEXP(re)->len;
  again:
    if (len >= 4 && ptr[0] == '(' && ptr[1] == '?') {
	int err = 1;
	ptr += 2;
	if ((len -= 2) > 0) {
	    do {
                opt = char_to_option((int )*ptr);
                if (opt != 0) {
                    options |= opt;
                }
                else {
                    break;
                }
		++ptr;
	    } while (--len > 0);
	}
	if (len > 1 && *ptr == '-') {
	    ++ptr;
	    --len;
	    do {
                opt = char_to_option((int )*ptr);
                if (opt != 0) {
                    options &= ~opt;
                }
                else {
                    break;
                }
		++ptr;
	    } while (--len > 0);
	}
	if (*ptr == ')') {
	    --len;
	    ++ptr;
	    goto again;
	}
	if (*ptr == ':' && ptr[len-1] == ')') {
	    int r;
	    Regexp *rp;
	    kcode_set_option(re);
            r = onig_alloc_init(&rp, ONIG_OPTION_DEFAULT,
                                ONIGENC_CASE_FOLD_DEFAULT,
                                onigenc_get_default_encoding(),
                                OnigDefaultSyntax);
	    if (r == 0) {
		 ++ptr;
 		 len -= 2;
		 err = (onig_compile(rp, ptr, ptr + len, NULL) != 0);
	    }
	    kcode_reset_option();
	    onig_free(rp);
	}
	if (err) {
	    options = RREGEXP(re)->ptr->options;
	    ptr = (UChar*)RREGEXP(re)->str;
	    len = RREGEXP(re)->len;
	}
    }

    if (*option_to_str(optbuf, options)) rb_str_buf_cat2(str, optbuf);

    if ((options & embeddable) != embeddable) {
	optbuf[0] = '-';
	option_to_str(optbuf + 1, ~options);
	rb_str_buf_cat2(str, optbuf);
    }

    rb_str_buf_cat2(str, ":");
    rb_reg_expr_str(str, (char*)ptr, len);
    rb_str_buf_cat2(str, ")");

    OBJ_INFECT(str, re);
    return str;
}

static void
rb_reg_raise(const char *s, long len, const char *err, VALUE re)
{
    VALUE desc = rb_reg_desc(s, len, re);

    rb_raise(rb_eRegexpError, "%s: %s", err, RSTRING_PTR(desc));
}

static VALUE
rb_reg_error_desc(VALUE str, int options, const char *err)
{
    char opts[6];
    VALUE desc = rb_str_buf_new2(err);

    rb_str_buf_cat2(desc, ": /");
    rb_reg_expr_str(desc, RSTRING_PTR(str), RSTRING_LEN(str));
    opts[0] = '/';
    option_to_str(opts + 1, options);
    strlcat(opts, arg_kcode(options), sizeof(opts));
    rb_str_buf_cat2(desc, opts);
    return rb_exc_new3(rb_eRegexpError, desc);
}

static void
rb_reg_raise_str(VALUE str, int options, const char *err)
{
    rb_exc_raise(rb_reg_error_desc(str, options, err));
}


/*
 *  call-seq:
 *     rxp.casefold?   => true or false
 *
 *  Returns the value of the case-insensitive flag.
 */

static VALUE
rb_reg_casefold_p(VALUE re)
{
    rb_reg_check(re);
    if (RREGEXP(re)->ptr->options & ONIG_OPTION_IGNORECASE) return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     rxp.options   => fixnum
 *
 *  Returns the set of bits corresponding to the options used when creating this
 *  Regexp (see <code>Regexp::new</code> for details. Note that additional bits
 *  may be set in the returned options: these are used internally by the regular
 *  expression code. These extra bits are ignored if the options are passed to
 *  <code>Regexp::new</code>.
 *
 *     Regexp::IGNORECASE                  #=> 1
 *     Regexp::EXTENDED                    #=> 2
 *     Regexp::MULTILINE                   #=> 4
 *
 *     /cat/.options                       #=> 128
 *     /cat/ix.options                     #=> 131
 *     Regexp.new('cat', true).options     #=> 129
 *     Regexp.new('cat', 0, 's').options   #=> 384
 *
 *     r = /cat/ix
 *     Regexp.new(r.source, r.options)     #=> /cat/ix
 */

static VALUE
rb_reg_options_m(VALUE re)
{
    int options = rb_reg_options(re);
    return INT2NUM(options);
}


/*
 *  call-seq:
 *     rxp.kcode   => str
 *
 *  Returns the character set code for the regexp.
 */

static VALUE
rb_reg_kcode_m(VALUE re)
{
    const char *kcode;

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
make_regexp(const char *s, long len, int flags, onig_errmsg_buffer err)
{
    Regexp *rp;
    int r;
    OnigErrorInfo einfo;

    /* Handle escaped characters first. */

    /* Build a copy of the string (in dest) with the
       escaped characters translated,  and generate the regex
       from that.
    */

    r = onig_alloc_init(&rp, flags,
                        ONIGENC_CASE_FOLD_DEFAULT,
                        onigenc_get_default_encoding(),
                        OnigDefaultSyntax);
    if (r) {
	onig_error_code_to_str((UChar*)err, r);
	return 0;
    }

    r = onig_compile(rp, (UChar*)s, (UChar*)(s + len), &einfo);

    if (r != 0) {
	onig_free(rp);
	(void )onig_error_code_to_str((UChar*)err, r, &einfo);
	return 0;
    }
    return rp;
}


/*
 *  Document-class: MatchData
 *
 *  <code>MatchData</code> is the type of the special variable <code>$~</code>,
 *  and is the type of the object returned by <code>Regexp#match</code> and
 *  <code>Regexp#last_match</code>. It encapsulates all the results of a pattern
 *  match, results normally accessed through the special variables
 *  <code>$&</code>, <code>$'</code>, <code>$`</code>, <code>$1</code>,
 *  <code>$2</code>, and so on. <code>Matchdata</code> is also known as
 *  <code>MatchingData</code>.
 *
 */

VALUE rb_cMatch;

static VALUE
match_alloc(VALUE klass)
{
    NEWOBJ(match, struct RMatch);
    OBJSETUP(match, klass, T_MATCH);

    match->str = 0;
    match->regs = 0;
    match->regexp = 0;
    match->regs = ALLOC(struct re_registers);
    MEMZERO(match->regs, struct re_registers, 1);

    return (VALUE)match;
}

/* :nodoc: */
static VALUE
match_init_copy(VALUE obj, VALUE orig)
{
    if (obj == orig) return obj;

    if (!rb_obj_is_instance_of(orig, rb_obj_class(obj))) {
	rb_raise(rb_eTypeError, "wrong argument class");
    }
    RMATCH(obj)->str = RMATCH(orig)->str;
    onig_region_free(RMATCH(obj)->regs, 0);
    RMATCH(obj)->regs->allocated = 0;
    onig_region_copy(RMATCH(obj)->regs, RMATCH(orig)->regs);

    return obj;
}


/*
 *  call-seq:
 *     mtch.length   => integer
 *     mtch.size     => integer
 *
 *  Returns the number of elements in the match array.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.length   #=> 5
 *     m.size     #=> 5
 */

static VALUE
match_size(VALUE match)
{
    return INT2FIX(RMATCH(match)->regs->num_regs);
}


/*
 *  call-seq:
 *     mtch.offset(n)   => array
 *
 *  Returns a two-element array containing the beginning and ending offsets of
 *  the <em>n</em>th match.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.offset(0)   #=> [1, 7]
 *     m.offset(4)   #=> [6, 7]
 */

static VALUE
match_offset(VALUE match, VALUE n)
{
    int i = NUM2INT(n);

    if (i < 0 || RMATCH(match)->regs->num_regs <= i)
	rb_raise(rb_eIndexError, "index %d out of matches", i);

    if (RMATCH(match)->regs->beg[i] < 0)
	return rb_assoc_new(Qnil, Qnil);

    return rb_assoc_new(INT2FIX(RMATCH(match)->regs->beg[i]),
			INT2FIX(RMATCH(match)->regs->end[i]));
}


/*
 *  call-seq:
 *     mtch.begin(n)   => integer
 *
 *  Returns the offset of the start of the <em>n</em>th element of the match
 *  array in the string.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.begin(0)   #=> 1
 *     m.begin(2)   #=> 2
 */

static VALUE
match_begin(VALUE match, VALUE n)
{
    int i = NUM2INT(n);

    if (i < 0 || RMATCH(match)->regs->num_regs <= i)
	rb_raise(rb_eIndexError, "index %d out of matches", i);

    if (RMATCH(match)->regs->beg[i] < 0)
	return Qnil;

    return INT2FIX(RMATCH(match)->regs->beg[i]);
}


/*
 *  call-seq:
 *     mtch.end(n)   => integer
 *
 *  Returns the offset of the character immediately following the end of the
 *  <em>n</em>th element of the match array in the string.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.end(0)   #=> 7
 *     m.end(2)   #=> 3
 */

static VALUE
match_end(VALUE match, VALUE n)
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
rb_match_busy(VALUE match)
{
    FL_SET(match, MATCH_BUSY);
}

int ruby_ignorecase;
static int may_need_recompile;

static void
rb_reg_prepare_re(VALUE re)
{
    int need_recompile = 0;
    int state;

    rb_reg_check(re);
    state = FL_TEST(re, REG_CASESTATE);
    /* ignorecase status */
    if (ruby_ignorecase && !state) {
	FL_SET(re, REG_CASESTATE);
	RREGEXP(re)->ptr->options |= ONIG_OPTION_IGNORECASE;
	need_recompile = 1;
    }
    if (!ruby_ignorecase && state) {
	FL_UNSET(re, REG_CASESTATE);
	RREGEXP(re)->ptr->options &= ~ONIG_OPTION_IGNORECASE;
	need_recompile = 1;
    }

    if (!FL_TEST(re, KCODE_FIXED) &&
	(RBASIC(re)->flags & KCODE_MASK) != reg_kcode) {
	need_recompile = 1;
	RBASIC(re)->flags &= ~KCODE_MASK;
	RBASIC(re)->flags |= reg_kcode;
    }

    if (need_recompile) {
	onig_errmsg_buffer err;
	int r;
	OnigErrorInfo einfo;
	regex_t *reg, *reg2;
	UChar *pattern;

	if (FL_TEST(re, KCODE_FIXED))
	    kcode_set_option(re);
	rb_reg_check(re);
	reg = RREGEXP(re)->ptr;
	pattern = ((UChar*)RREGEXP(re)->str);

	r = onig_new(&reg2, (UChar* )pattern,
		     (UChar* )(pattern + RREGEXP(re)->len),
		     reg->options, onigenc_get_default_encoding(),
		     OnigDefaultSyntax, &einfo);
	if (r) {
	    onig_error_code_to_str((UChar*)err, r, &einfo);
	    rb_reg_raise((char* )pattern, RREGEXP(re)->len, err, re);
	}

	RREGEXP(re)->ptr = reg2;
	onig_free(reg);
    }
}

long
rb_reg_adjust_startpos(VALUE re, VALUE str, long pos, long reverse)
{
    long range;
    OnigEncoding enc;
    UChar *p, *string;

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
	range = RSTRING_LEN(str) - pos;
    }

    enc = (RREGEXP(re)->ptr)->enc;

    if (pos > 0 && ONIGENC_MBC_MAXLEN(enc) != 1 && pos < RSTRING_LEN(str)) {
	 string = (UChar*)RSTRING_PTR(str);

	 if (range > 0) {
	      p = onigenc_get_right_adjust_char_head(enc, string, string + pos);
	 }
	 else {
	      p = ONIGENC_LEFT_ADJUST_CHAR_HEAD(enc, string, string + pos);
	 }
	 return p - string;
    }

    return pos;
}

long
rb_reg_search(VALUE re, VALUE str, long pos, long reverse)
{
    long result;
    VALUE match;
    static struct re_registers regs;
    long range;

    if (pos > RSTRING_LEN(str) || pos < 0) {
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
	range = RSTRING_LEN(str) - pos;
    }

    result = onig_search(RREGEXP(re)->ptr,
			 (UChar*)(RSTRING_PTR(str)),
			 ((UChar*)(RSTRING_PTR(str)) + RSTRING_LEN(str)),
			 ((UChar*)(RSTRING_PTR(str)) + pos),
			 ((UChar*)(RSTRING_PTR(str)) + pos + range),
			 &regs, ONIG_OPTION_NONE);

    if (FL_TEST(re, KCODE_FIXED))
	kcode_reset_option();

    if (result < 0) {
	if (result == ONIG_MISMATCH) {
	    rb_backref_set(Qnil);
	    return result;
	}
	else {
	    onig_errmsg_buffer err;
	    onig_error_code_to_str((UChar*)err, result);
	    rb_reg_raise(RREGEXP(re)->str, RREGEXP(re)->len, err, 0);
	}
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

    onig_region_copy(RMATCH(match)->regs, &regs);
    RMATCH(match)->str = rb_str_new4(str);
    RMATCH(match)->regexp = re;
    rb_backref_set(match);

    OBJ_INFECT(match, re);
    OBJ_INFECT(match, str);
    return result;
}

VALUE
rb_reg_nth_defined(int nth, VALUE match)
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
rb_reg_nth_match(int nth, VALUE match)
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
    str = rb_str_subseq(RMATCH(match)->str, start, len);
    OBJ_INFECT(str, match);
    return str;
}

VALUE
rb_reg_last_match(VALUE match)
{
    return rb_reg_nth_match(0, match);
}


/*
 *  call-seq:
 *     mtch.pre_match   => str
 *
 *  Returns the portion of the original string before the current match.
 *  Equivalent to the special variable <code>$`</code>.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.pre_match   #=> "T"
 */

VALUE
rb_reg_match_pre(VALUE match)
{
    VALUE str;

    if (NIL_P(match)) return Qnil;
    if (RMATCH(match)->BEG(0) == -1) return Qnil;
    str = rb_str_subseq(RMATCH(match)->str, 0, RMATCH(match)->BEG(0));
    if (OBJ_TAINTED(match)) OBJ_TAINT(str);
    return str;
}


/*
 *  call-seq:
 *     mtch.post_match   => str
 *
 *  Returns the portion of the original string after the current match.
 *  Equivalent to the special variable <code>$'</code>.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138: The Movie")
 *     m.post_match   #=> ": The Movie"
 */

VALUE
rb_reg_match_post(VALUE match)
{
    VALUE str;
    long pos;

    if (NIL_P(match)) return Qnil;
    if (RMATCH(match)->BEG(0) == -1) return Qnil;
    str = RMATCH(match)->str;
    pos = RMATCH(match)->END(0);
    str = rb_str_subseq(str, pos, RSTRING_LEN(str) - pos);
    if (OBJ_TAINTED(match)) OBJ_TAINT(str);
    return str;
}

VALUE
rb_reg_match_last(VALUE match)
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
last_match_getter(void)
{
    return rb_reg_last_match(rb_backref_get());
}

static VALUE
prematch_getter(void)
{
    return rb_reg_match_pre(rb_backref_get());
}

static VALUE
postmatch_getter(void)
{
    return rb_reg_match_post(rb_backref_get());
}

static VALUE
last_paren_match_getter(void)
{
    return rb_reg_match_last(rb_backref_get());
}

static VALUE
match_array(VALUE match, int start)
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
	    VALUE str = rb_str_subseq(target, regs->beg[i], regs->end[i]-regs->beg[i]);
	    if (taint) OBJ_TAINT(str);
	    rb_ary_push(ary, str);
	}
    }
    return ary;
}


/* [MG]:FIXME: I put parens around the /.../.match() in the first line of the
   second example to prevent the '*' followed by a '/' from ending the
   comment. */

/*
 *  call-seq:
 *     mtch.to_a   => anArray
 *
 *  Returns the array of matches.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.to_a   #=> ["HX1138", "H", "X", "113", "8"]
 *
 *  Because <code>to_a</code> is called when expanding
 *  <code>*</code><em>variable</em>, there's a useful assignment
 *  shortcut for extracting matched fields. This is slightly slower than
 *  accessing the fields directly (as an intermediate array is
 *  generated).
 *
 *     all,f1,f2,f3 = *(/(.)(.)(\d+)(\d)/.match("THX1138."))
 *     all   #=> "HX1138"
 *     f1    #=> "H"
 *     f2    #=> "X"
 *     f3    #=> "113"
 */

static VALUE
match_to_a(VALUE match)
{
    return match_array(match, 0);
}


/*
 *  call-seq:
 *     mtch.captures   => array
 *
 *  Returns the array of captures; equivalent to <code>mtch.to_a[1..-1]</code>.
 *
 *     f1,f2,f3,f4 = /(.)(.)(\d+)(\d)/.match("THX1138.").captures
 *     f1    #=> "H"
 *     f2    #=> "X"
 *     f3    #=> "113"
 *     f4    #=> "8"
 */
static VALUE
match_captures(VALUE match)
{
    return match_array(match, 1);
}

static int
name_to_backref_number(struct re_registers *regs, VALUE regexp, const char* name, const char* name_end)
{
  int num;

  num = onig_name_to_backref_number(RREGEXP(regexp)->ptr,
            (const unsigned char* )name, (const unsigned char* )name_end, regs);
  if (num >= 1) {
    return num;
  }
  else {
    VALUE s = rb_str_new(name, (long )(name_end - name));
    rb_raise(rb_eRuntimeError, "undefined group name reference: %s",
                                StringValuePtr(s));
  }
}

/*
 *  call-seq:
 *     mtch[i]               => str or nil
 *     mtch[start, length]   => array
 *     mtch[range]           => array
 *     mtch[name]            => str or nil
 *
 *  Match Reference---<code>MatchData</code> acts as an array, and may be
 *  accessed using the normal array indexing techniques.  <i>mtch</i>[0] is
 *  equivalent to the special variable <code>$&</code>, and returns the entire
 *  matched string.  <i>mtch</i>[1], <i>mtch</i>[2], and so on return the values
 *  of the matched backreferences (portions of the pattern between parentheses).
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m[0]       #=> "HX1138"
 *     m[1, 2]    #=> ["H", "X"]
 *     m[1..3]    #=> ["H", "X", "113"]
 *     m[-3, 2]   #=> ["X", "113"]
 *
 *     m = /(?<foo>a+)b/.match("ccaaab")
 *     m["foo"]   #=> "aaa"
 *     m[:foo]    #=> "aaa"
 */

static VALUE
match_aref(int argc, VALUE *argv, VALUE match)
{
    VALUE idx, rest;

    rb_scan_args(argc, argv, "11", &idx, &rest);

    if (NIL_P(rest)) {
      if (FIXNUM_P(idx)) {
        if (FIX2INT(idx) >= 0) {
          return rb_reg_nth_match(FIX2INT(idx), match);
        }
      }
      else {
        const char *p;
        int num;

        switch (TYPE(idx)) {
          case T_SYMBOL:
            p = rb_id2name(SYM2ID(idx));
            goto name_to_backref;
            break;
          case T_STRING:
            p = StringValuePtr(idx);

          name_to_backref:
            num = name_to_backref_number(RMATCH(match)->regs,
                       RMATCH(match)->regexp, p, p + strlen(p));
            return rb_reg_nth_match(num, match);
            break;

          default:
            break;
        }
      }
    }

    return rb_ary_aref(argc, argv, match_to_a(match));
}

static VALUE
match_entry(VALUE match, long n)
{
    return rb_reg_nth_match(n, match);
}


/*
 *  call-seq:
    if (!OBJ_TAINTED(obj) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify regexp");
 *     mtch.select([index]*)   => array
 *
 *  Uses each <i>index</i> to access the matching values, returning an array of
 *  the corresponding matches.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138: The Movie")
 *     m.to_a               #=> ["HX1138", "H", "X", "113", "8"]
 *     m.select(0, 2, -2)   #=> ["HX1138", "X", "113"]
 */

static VALUE
match_values_at(int argc, VALUE *argv, VALUE match)
{
    return rb_get_values_at(match, RMATCH(match)->regs->num_regs, argc, argv, match_entry);
}


/*
 *  call-seq:
 *     mtch.select([index]*)   => array
 *
 *  Uses each <i>index</i> to access the matching values, returning an
 *  array of the corresponding matches.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138: The Movie")
 *     m.to_a               #=> ["HX1138", "H", "X", "113", "8"]
 *     m.select(0, 2, -2)   #=> ["HX1138", "X", "113"]
 */

static VALUE
match_select(int argc, VALUE *argv, VALUE match)
{
    if (argc > 0) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
    }
    else {
	struct re_registers *regs = RMATCH(match)->regs;
	VALUE target = RMATCH(match)->str;
	VALUE result = rb_ary_new();
	int i;
	int taint = OBJ_TAINTED(match);

	for (i=0; i<regs->num_regs; i++) {
	    VALUE str = rb_str_subseq(target, regs->beg[i], regs->end[i]-regs->beg[i]);
	    if (taint) OBJ_TAINT(str);
	    if (RTEST(rb_yield(str))) {
		rb_ary_push(result, str);
	    }
	}
	return result;
    }
}


/*
 *  call-seq:
 *     mtch.to_s   => str
 *
 *  Returns the entire matched string.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.to_s   #=> "HX1138"
 */

static VALUE
match_to_s(VALUE match)
{
    VALUE str = rb_reg_last_match(match);

    if (NIL_P(str)) str = rb_str_new(0,0);
    if (OBJ_TAINTED(match)) OBJ_TAINT(str);
    if (OBJ_TAINTED(RMATCH(match)->str)) OBJ_TAINT(str);
    return str;
}


/*
 *  call-seq:
 *     mtch.string   => str
 *
 *  Returns a frozen copy of the string passed in to <code>match</code>.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.string   #=> "THX1138."
 */

static VALUE
match_string(VALUE match)
{
    return RMATCH(match)->str;	/* str is frozen */
}

static VALUE
match_inspect(VALUE match)
{
    char *cname = rb_obj_classname(match);
    VALUE str;
    int i;

    str = rb_str_buf_new2("#<");
    rb_str_buf_cat2(str, cname);

    for (i = 0; i < RMATCH(match)->regs->num_regs; i++) {
        VALUE v;
        rb_str_buf_cat2(str, " ");
        v = rb_reg_nth_match(i, match);
        if (v == Qnil)
            rb_str_buf_cat2(str, "nil");
        else
            rb_str_buf_append(str, rb_str_inspect(v));
    }
    rb_str_buf_cat2(str, ">");

    return str;
}

VALUE rb_cRegexp;

static int
rb_reg_initialize(VALUE obj, const char *s, int len, rb_encoding *enc,
		  int options, onig_errmsg_buffer err)
{
    struct RRegexp *re = RREGEXP(obj);

    if (!OBJ_TAINTED(obj) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify regexp");
    rb_check_frozen(obj);
    if (FL_TEST(obj, REG_LITERAL))
	rb_raise(rb_eSecurityError, "can't modify literal regexp");
    if (re->ptr) onig_free(re->ptr);
    if (re->str) free(re->str);
    re->ptr = 0;
    re->str = 0;

    if (options & ARG_KCODE_MASK) {
	set_re_kcode_by_option(re, options);
    }
    else {
	rb_enc_associate((VALUE)re, enc);
    }

    if (options & ARG_KCODE_MASK) {
	kcode_set_option((VALUE)re);
    }
    if (ruby_ignorecase) {
	options |= ONIG_OPTION_IGNORECASE;
	FL_SET(re, REG_CASESTATE);
    }
    re->ptr = make_regexp(s, len, options & ARG_REG_OPTION_MASK, err);
    if (!re->ptr) return -1;
    re->str = ALLOC_N(char, len+1);
    memcpy(re->str, s, len);
    re->str[len] = '\0';
    re->len = len;
    if (options & ARG_KCODE_MASK) {
	kcode_reset_option();
    }
    return 0;
}

static int
rb_reg_initialize_str(VALUE obj, VALUE str, int options, onig_errmsg_buffer err)
{
    return rb_reg_initialize(obj, RSTRING_PTR(str), RSTRING_LEN(str), rb_enc_get(str),
			     options, err);
}

static VALUE
rb_reg_s_alloc(VALUE klass)
{
    NEWOBJ(re, struct RRegexp);
    OBJSETUP(re, klass, T_REGEXP);

    re->ptr = 0;
    re->len = 0;
    re->str = 0;

    return (VALUE)re;
}

VALUE
rb_reg_new(VALUE s, int options)
{
    VALUE re = rb_reg_s_alloc(rb_cRegexp);
    onig_errmsg_buffer err;

    if (rb_reg_initialize_str(re, s, options, err) != 0) {
	rb_reg_raise_str(s, options, err);
    }

    return re;
}

VALUE
rb_reg_compile(VALUE str, int options)
{
    VALUE re = rb_reg_s_alloc(rb_cRegexp);
    onig_errmsg_buffer err;

    if (!str) str = rb_str_new(0,0);
    if (rb_reg_initialize_str(re, str, options, err) != 0) {
	rb_set_errinfo(rb_reg_error_desc(str, options, err));
	return Qnil;
    }
    FL_SET(re, REG_LITERAL);
    return re;
}

static int case_cache;
static int kcode_cache;
static VALUE reg_cache;

VALUE
rb_reg_regcomp(VALUE str)
{
    volatile VALUE save_str = str;
    if (reg_cache && RREGEXP(reg_cache)->len == RSTRING_LEN(str)
	&& case_cache == ruby_ignorecase
	&& kcode_cache == reg_kcode
	&& memcmp(RREGEXP(reg_cache)->str, RSTRING_PTR(str), RSTRING_LEN(str)) == 0)
	return reg_cache;

    case_cache = ruby_ignorecase;
    kcode_cache = reg_kcode;
    return reg_cache = rb_reg_new(save_str, ruby_ignorecase);
}

static int
rb_reg_cur_kcode(VALUE re)
{
    if (FL_TEST(re, KCODE_FIXED)) {
	return RBASIC(re)->flags & KCODE_MASK;
    }
    return 0;
}

/*
 * call-seq:
 *   rxp.hash   => fixnum
 *
 * Produce a hash based on the text and options of this regular expression.
 */

static VALUE
rb_reg_hash(VALUE re)
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


/*
 *  call-seq:
 *     rxp == other_rxp      => true or false
 *     rxp.eql?(other_rxp)   => true or false
 *
 *  Equality---Two regexps are equal if their patterns are identical, they have
 *  the same character set code, and their <code>casefold?</code> values are the
 *  same.
 *
 *     /abc/  == /abc/x   #=> false
 *     /abc/  == /abc/i   #=> false
 *     /abc/u == /abc/n   #=> false
 */

static VALUE
rb_reg_equal(VALUE re1, VALUE re2)
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

static VALUE
reg_operand(VALUE s, int check)
{
    if (SYMBOL_P(s)) {
	return rb_sym_to_s(s);
    }
    else {
	VALUE tmp = rb_check_string_type(s);
	if (check && NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "can't convert %s to String",
		     rb_obj_classname(s));
	}
	return tmp;
    }
}

static VALUE
rb_reg_match_pos(VALUE re, VALUE str, long pos)
{
    if (NIL_P(str)) {
	rb_backref_set(Qnil);
	return Qnil;
    }
    str = reg_operand(str, Qtrue);
    if (pos != 0) {
	if (pos < 0) {
	    pos += RSTRING_LEN(str);
	    if (pos < 0) {
		return Qnil;
	    }
	}
	pos = rb_reg_adjust_startpos(re, str, pos, 0);
    }
    pos = rb_reg_search(re, str, pos, 0);
    if (pos < 0) {
	return Qnil;
    }
    return LONG2FIX(pos);
}

/*
 *  call-seq:
 *     rxp =~ str    => integer or nil
 *
 *  Match---Matches <i>rxp</i> against <i>str</i>.
 *
 *     /at/ =~ "input data"   #=> 7
 */

VALUE
rb_reg_match(VALUE re, VALUE str)
{
    return rb_reg_match_pos(re, str, 0);
}

/*
 *  call-seq:
 *     rxp === str   => true or false
 *
 *  Case Equality---Synonym for <code>Regexp#=~</code> used in case statements.
 *
 *     a = "HELLO"
 *     case a
 *     when /^[a-z]*$/; print "Lower case\n"
 *     when /^[A-Z]*$/; print "Upper case\n"
 *     else;            print "Mixed case\n"
 *     end
 *
 *  <em>produces:</em>
 *
 *     Upper case
 */

VALUE
rb_reg_eqq(VALUE re, VALUE str)
{
    long start;

    str = reg_operand(str, Qfalse);
    if (NIL_P(str)) {
	rb_backref_set(Qnil);
	return Qfalse;
    }
    start = rb_reg_search(re, str, 0, 0);
    if (start < 0) {
	return Qfalse;
    }
    return Qtrue;
}


/*
 *  call-seq:
 *     ~ rxp   => integer or nil
 *
 *  Match---Matches <i>rxp</i> against the contents of <code>$_</code>.
 *  Equivalent to <code><i>rxp</i> =~ $_</code>.
 *
 *     $_ = "input data"
 *     ~ /at/   #=> 7
 */

VALUE
rb_reg_match2(VALUE re)
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


/*
 *  call-seq:
 *     rxp.match(str)       => matchdata or nil
 *     rxp.match(str,pos)   => matchdata or nil
 *
 *  Returns a <code>MatchData</code> object describing the match, or
 *  <code>nil</code> if there was no match. This is equivalent to retrieving the
 *  value of the special variable <code>$~</code> following a normal match.
 *  If the second parameter is present, it specifies the position in the string
 *  to begin the search.
 *
 *     /(.)(.)(.)/.match("abc")[2]   #=> "b"
 *     /(.)(.)/.match("abc", 1)[2]   #=> "c"
 */

static VALUE
rb_reg_match_m(int argc, VALUE *argv, VALUE re)
{
    VALUE result, str, initpos;
    long pos;

    if (rb_scan_args(argc, argv, "11", &str, &initpos) == 2) {
	pos = NUM2LONG(initpos);
    }
    else {
	pos = 0;
    }

    result = rb_reg_match_pos(re, str, pos);
    if (NIL_P(result)) {
	rb_backref_set(Qnil);
	return Qnil;
    }
    result = rb_backref_get();
    rb_match_busy(result);
    return result;
}

/*
 * Document-method: compile
 *
 * Synonym for <code>Regexp.new</code>
 */


/*
 *  call-seq:
 *     Regexp.new(string [, options [, lang]])       => regexp
 *     Regexp.new(regexp)                            => regexp
 *     Regexp.compile(string [, options [, lang]])   => regexp
 *     Regexp.compile(regexp)                        => regexp
 *
 *  Constructs a new regular expression from <i>pattern</i>, which can be either
 *  a <code>String</code> or a <code>Regexp</code> (in which case that regexp's
 *  options are propagated, and new options may not be specified (a change as of
 *  Ruby 1.8). If <i>options</i> is a <code>Fixnum</code>, it should be one or
 *  more of the constants <code>Regexp::EXTENDED</code>,
 *  <code>Regexp::IGNORECASE</code>, and <code>Regexp::MULTILINE</code>,
 *  <em>or</em>-ed together. Otherwise, if <i>options</i> is not
 *  <code>nil</code>, the regexp will be case insensitive. The <i>lang</i>
 *  parameter enables multibyte support for the regexp: `n', `N' = none, `e',
 *  `E' = EUC, `s', `S' = SJIS, `u', `U' = UTF-8.
 *
 *     r1 = Regexp.new('^a-z+:\\s+\w+')           #=> /^a-z+:\s+\w+/
 *     r2 = Regexp.new('cat', true)               #=> /cat/i
 *     r3 = Regexp.new('dog', Regexp::EXTENDED)   #=> /dog/x
 *     r4 = Regexp.new(r2)                        #=> /cat/i
 */

static VALUE
rb_reg_initialize_m(int argc, VALUE *argv, VALUE self)
{
    onig_errmsg_buffer err;
    int flags = 0;
    VALUE str;

    if (argc == 0 || argc > 3) {
	rb_raise(rb_eArgError, "wrong number of arguments");
    }
    if (TYPE(argv[0]) == T_REGEXP) {
	if (argc > 1) {
	    rb_warn("flags%s ignored", (argc == 3) ? " and encoding": "");
	}
	rb_reg_check(argv[0]);
	flags = RREGEXP(argv[0])->ptr->options & ARG_REG_OPTION_MASK;
	if (FL_TEST(argv[0], KCODE_FIXED)) {
            flags |= re_to_kcode_arg_value(argv[0]);
	}
	str = rb_enc_str_new(RREGEXP(argv[0])->str, RREGEXP(argv[0])->len,
			     rb_enc_get(argv[0]));
    }
    else {
	if (argc >= 2) {
	    if (FIXNUM_P(argv[1])) flags = FIX2INT(argv[1]);
	    else if (RTEST(argv[1])) flags = ONIG_OPTION_IGNORECASE;
	}
	if (argc == 3 && !NIL_P(argv[2])) {
	    char *kcode = StringValuePtr(argv[2]);

	    flags &= ~ARG_KCODE_MASK;
	    flags |= char_to_arg_kcode((int )kcode[0]);
	}
	str = argv[0];
    }
    if (rb_reg_initialize_str(self, str, flags, err) != 0) {
	rb_reg_raise_str(str, flags, err);
    }
    return self;
}

VALUE
rb_reg_quote(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);
    char *s, *send, *t;
    VALUE tmp;
    int c;

    s = RSTRING_PTR(str);
    send = s + RSTRING_LEN(str);
    for (; s < send; s++) {
	c = *s;
	if (ismbchar(s, enc)) {
	    int n = mbclen(s, enc);

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
    tmp = rb_str_new(0, RSTRING_LEN(str)*2);
    t = RSTRING_PTR(tmp);
    /* copy upto metacharacter */
    memcpy(t, RSTRING_PTR(str), s - RSTRING_PTR(str));
    t += s - RSTRING_PTR(str);

    for (; s < send; s++) {
	c = *s;
	if (ismbchar(s, enc)) {
	    int n = mbclen(s, enc);

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
    rb_str_resize(tmp, t - RSTRING_PTR(tmp));
    OBJ_INFECT(tmp, str);
    return tmp;
}


/*
 *  call-seq:
 *     Regexp.escape(str)   => a_str
 *     Regexp.quote(str)    => a_str
 *
 *  Escapes any characters that would have special meaning in a regular
 *  expression. Returns a new escaped string, or self if no characters are
 *  escaped.  For any string,
 *  <code>Regexp.escape(<i>str</i>)=~<i>str</i></code> will be true.
 *
 *     Regexp.escape('\\*?{}.')   #=> \\\\\*\?\{\}\.
 */

static VALUE
rb_reg_s_quote(int argc, VALUE *argv)
{
    VALUE str, kcode;
    int kcode_saved = reg_kcode;

    rb_scan_args(argc, argv, "11", &str, &kcode);
    if (!NIL_P(kcode)) {
	rb_set_kcode(StringValuePtr(kcode));
	curr_kcode = reg_kcode;
	reg_kcode = kcode_saved;
    }
    str = reg_operand(str, Qtrue);
    str = rb_reg_quote(str);
    kcode_reset_option();
    return str;
}

int
rb_kcode(void)
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

int
rb_reg_options(VALUE re)
{
    int options;

    rb_reg_check(re);
    options = RREGEXP(re)->ptr->options &
	(ONIG_OPTION_IGNORECASE|ONIG_OPTION_MULTILINE|ONIG_OPTION_EXTEND);
    if (FL_TEST(re, KCODE_FIXED)) {
	options |= re_to_kcode_arg_value(re);
    }
    return options;
}

VALUE
rb_check_regexp_type(VALUE re)
{
    return rb_check_convert_type(re, T_REGEXP, "Regexp", "to_regexp");
}

/*
 *  call-seq:
 *     Regexp.try_convert(obj) -> re or nil
 *
 *  Try to convert <i>obj</i> into a Regexp, using to_regexp method.
 *  Returns converted regexp or nil if <i>obj</i> cannot be converted
 *  for any reason.
 *
 *     Regexp.try_convert(/re/)      # => /re/
 *     Regexp.try_convert("re")      # => nil
 */
static VALUE
rb_reg_s_try_convert(VALUE dummy, VALUE re)
{
    return rb_check_regexp_type(re);
}

/*
 *  call-seq:
 *     Regexp.union([pattern]*)   => new_str
 *
 *  Return a <code>Regexp</code> object that is the union of the given
 *  <em>pattern</em>s, i.e., will match any of its parts. The <em>pattern</em>s
 *  can be Regexp objects, in which case their options will be preserved, or
 *  Strings. If no arguments are given, returns <code>/(?!)/</code>.
 *
 *     Regexp.union                         #=> /(?!)/
 *     Regexp.union("penzance")             #=> /penzance/
 *     Regexp.union("skiing", "sledding")   #=> /skiing|sledding/
 *     Regexp.union(/dogs/, /cats/i)        #=> /(?-mix:dogs)|(?i-mx:cats)/
 */
static VALUE
rb_reg_s_union(int argc, VALUE *argv)
{
    if (argc == 0) {
        VALUE args[1];
        args[0] = rb_str_new2("(?!)");
        return rb_class_new_instance(1, args, rb_cRegexp);
    }
    else if (argc == 1) {
        VALUE v;
        v = rb_check_regexp_type(argv[0]);
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
            v = rb_check_regexp_type(argv[i]);
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
                            RSTRING_PTR(str1), RSTRING_PTR(str2));
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
        if (kcode == -1) {
            args[2] = Qnil;
	}
	else {
            args[2] = rb_str_new2(opt_kcode(kcode));
        }
        return rb_class_new_instance(3, args, rb_cRegexp);
    }
}

/* :nodoc: */
static VALUE
rb_reg_init_copy(VALUE copy, VALUE re)
{
    onig_errmsg_buffer err;
    const char *s;
    long len;

    if (copy == re) return copy;
    rb_check_frozen(copy);
    /* need better argument type check */
    if (!rb_obj_is_instance_of(re, rb_obj_class(copy))) {
	rb_raise(rb_eTypeError, "wrong argument type");
    }
    rb_reg_check(re);
    s = RREGEXP(re)->str;
    len = RREGEXP(re)->len;
    if (rb_reg_initialize(copy, s, len, rb_enc_get(re), rb_reg_options(re), err) != 0) {
	rb_reg_raise(s, len, err, re);
    }
    return copy;
}

VALUE
rb_reg_regsub(VALUE str, VALUE src, struct re_registers *regs, VALUE regexp)
{
    VALUE val = 0;
    char *p, *s, *e;
    unsigned char uc;
    int no;
    rb_encoding *enc = rb_enc_check(str, src);

    rb_enc_check(str, regexp);
    p = s = RSTRING_PTR(str);
    e = s + RSTRING_LEN(str);

    while (s < e) {
	char *ss = s++;

	if (ismbchar(ss, enc)) {
	    s += mbclen(ss, enc) - 1;
	    continue;
	}
	if (*ss != '\\' || s == e) continue;

	if (!val) {
	    val = rb_str_buf_new(ss-p);
	    rb_str_buf_cat(val, p, ss-p);
	}
	else {
	    rb_str_buf_cat(val, p, ss-p);
	}

	uc = (unsigned char)*s++;
	p = s;
	switch (uc) {
	  case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
            if (onig_noname_group_capture_is_active(RREGEXP(regexp)->ptr)) {
              no = uc - '0';
            }
            else {
              continue;
            }
	    break;

          case 'k':
            if (s < e && *s == '<') {
              char *name, *name_end;

              name_end = name = s + 1;
              while (name_end < e) {
                if (*name_end == '>') break;
                name_end += mbclen(name_end, enc);
              }
              if (name_end < e) {
                no = name_to_backref_number(regs, regexp, name, name_end);
                p = s = name_end + 1;
                break;
              }
              else {
                rb_raise(rb_eRuntimeError, "invalid group name reference format");
              }
            }

            rb_str_buf_cat(val, s-2, 2);
            continue;

          case '0':
	  case '&':
	    no = 0;
	    break;

	  case '`':
	    rb_str_buf_cat(val, RSTRING_PTR(src), BEG(0));
	    continue;

	  case '\'':
	    rb_str_buf_cat(val, RSTRING_PTR(src)+END(0), RSTRING_LEN(src)-END(0));
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
	    rb_str_buf_cat(val, RSTRING_PTR(src)+BEG(no), END(no)-BEG(no));
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
rb_get_kcode(void)
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
kcode_getter(void)
{
    return rb_str_new2(rb_get_kcode());
}

void
rb_set_kcode(const char *code)
{
    if (code == 0) goto set_no_conversion;

    switch (code[0]) {
      case 'E':
      case 'e':
	reg_kcode = KCODE_EUC;
	onigenc_set_default_encoding(ONIG_ENCODING_EUC_JP);
	break;
      case 'S':
      case 's':
	reg_kcode = KCODE_SJIS;
	onigenc_set_default_encoding(ONIG_ENCODING_SJIS);
	break;
      case 'U':
      case 'u':
	reg_kcode = KCODE_UTF8;
	onigenc_set_default_encoding(ONIG_ENCODING_UTF8);
	break;
      default:
      case 'N':
      case 'n':
      case 'A':
      case 'a':
      set_no_conversion:
	reg_kcode = KCODE_NONE;
	onigenc_set_default_encoding(ONIG_ENCODING_ASCII);
	break;
    }
}

static void
kcode_setter(VALUE val)
{
    may_need_recompile = 1;
    rb_set_kcode(StringValuePtr(val));
}

static VALUE
ignorecase_getter(void)
{
    return ruby_ignorecase?Qtrue:Qfalse;
}

static void
ignorecase_setter(VALUE val, ID id)
{
    rb_warn("modifying %s is deprecated", rb_id2name(id));
    may_need_recompile = 1;
    ruby_ignorecase = RTEST(val);
}

static VALUE
match_getter(void)
{
    VALUE match = rb_backref_get();

    if (NIL_P(match)) return Qnil;
    rb_match_busy(match);
    return match;
}

static void
match_setter(VALUE val)
{
    if (!NIL_P(val)) {
	Check_Type(val, T_MATCH);
    }
    rb_backref_set(val);
}

/*
 *  call-seq:
 *     Regexp.last_match           => matchdata
 *     Regexp.last_match(fixnum)   => str
 *
 *  The first form returns the <code>MatchData</code> object generated by the
 *  last successful pattern match. Equivalent to reading the global variable
 *  <code>$~</code>. The second form returns the nth field in this
 *  <code>MatchData</code> object.
 *
 *     /c(.)t/ =~ 'cat'       #=> 0
 *     Regexp.last_match      #=> #<MatchData "cat" "a">
 *     Regexp.last_match(0)   #=> "cat"
 *     Regexp.last_match(1)   #=> "a"
 *     Regexp.last_match(2)   #=> nil
 */

static VALUE
rb_reg_s_last_match(int argc, VALUE *argv)
{
    VALUE nth;

    if (rb_scan_args(argc, argv, "01", &nth) == 1) {
	return rb_reg_nth_match(NUM2INT(nth), rb_backref_get());
    }
    return match_getter();
}


/*
 *  Document-class: Regexp
 *
 *  A <code>Regexp</code> holds a regular expression, used to match a pattern
 *  against strings. Regexps are created using the <code>/.../</code> and
 *  <code>%r{...}</code> literals, and by the <code>Regexp::new</code>
 *  constructor.
 *
 */

void
Init_Regexp(void)
{
    rb_eRegexpError = rb_define_class("RegexpError", rb_eStandardError);

    onigenc_set_default_caseconv_table((UChar*)casetable);
#if DEFAULT_KCODE == KCODE_EUC
    onigenc_set_default_encoding(ONIG_ENCODING_EUC_JP);
#else
#if DEFAULT_KCODE == KCODE_SJIS
    onigenc_set_default_encoding(ONIG_ENCODING_SJIS);
#else
#if DEFAULT_KCODE == KCODE_UTF8
    onigenc_set_default_encoding(ONIG_ENCODING_UTF8);
#else
    onigenc_set_default_encoding(ONIG_ENCODING_ASCII);
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
    rb_define_singleton_method(rb_cRegexp, "try_convert", rb_reg_s_try_convert, 1);

    rb_define_method(rb_cRegexp, "initialize", rb_reg_initialize_m, -1);
    rb_define_method(rb_cRegexp, "initialize_copy", rb_reg_init_copy, 1);
    rb_define_method(rb_cRegexp, "hash", rb_reg_hash, 0);
    rb_define_method(rb_cRegexp, "eql?", rb_reg_equal, 1);
    rb_define_method(rb_cRegexp, "==", rb_reg_equal, 1);
    rb_define_method(rb_cRegexp, "=~", rb_reg_match, 1);
    rb_define_method(rb_cRegexp, "===", rb_reg_eqq, 1);
    rb_define_method(rb_cRegexp, "~", rb_reg_match2, 0);
    rb_define_method(rb_cRegexp, "match", rb_reg_match_m, -1);
    rb_define_method(rb_cRegexp, "to_s", rb_reg_to_s, 0);
    rb_define_method(rb_cRegexp, "inspect", rb_reg_inspect, 0);
    rb_define_method(rb_cRegexp, "source", rb_reg_source, 0);
    rb_define_method(rb_cRegexp, "casefold?", rb_reg_casefold_p, 0);
    rb_define_method(rb_cRegexp, "options", rb_reg_options_m, 0);
    rb_define_method(rb_cRegexp, "kcode", rb_reg_kcode_m, 0);

    rb_define_const(rb_cRegexp, "IGNORECASE", INT2FIX(ONIG_OPTION_IGNORECASE));
    rb_define_const(rb_cRegexp, "EXTENDED", INT2FIX(ONIG_OPTION_EXTEND));
    rb_define_const(rb_cRegexp, "MULTILINE", INT2FIX(ONIG_OPTION_MULTILINE));

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
    rb_define_method(rb_cMatch, "inspect", match_inspect, 0);
    rb_define_method(rb_cMatch, "string", match_string, 0);
}
