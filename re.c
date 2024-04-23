/**********************************************************************

  re.c -

  $Author$
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#include <ctype.h>

#include "encindex.h"
#include "hrtime.h"
#include "internal.h"
#include "internal/encoding.h"
#include "internal/hash.h"
#include "internal/imemo.h"
#include "internal/re.h"
#include "internal/string.h"
#include "internal/object.h"
#include "internal/ractor.h"
#include "internal/variable.h"
#include "regint.h"
#include "ruby/encoding.h"
#include "ruby/re.h"
#include "ruby/util.h"

#if USE_MMTK
#include "internal/mmtk_support.h"
#endif

VALUE rb_eRegexpError, rb_eRegexpTimeoutError;

typedef char onig_errmsg_buffer[ONIG_MAX_ERROR_MESSAGE_LEN];
#define errcpy(err, msg) strlcpy((err), (msg), ONIG_MAX_ERROR_MESSAGE_LEN)

#define BEG(no) (regs->beg[(no)])
#define END(no) (regs->end[(no)])

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

// The process-global timeout for regexp matching
rb_hrtime_t rb_reg_match_time_limit = 0;

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

#ifdef HAVE_MEMMEM
static inline long
rb_memsearch_ss(const unsigned char *xs, long m, const unsigned char *ys, long n)
{
    const unsigned char *y;

    if ((y = memmem(ys, n, xs, m)) != NULL)
        return y - ys;
    else
        return -1;
}
#else
static inline long
rb_memsearch_ss(const unsigned char *xs, long m, const unsigned char *ys, long n)
{
    const unsigned char *x = xs, *xe = xs + m;
    const unsigned char *y = ys, *ye = ys + n;
#define VALUE_MAX ((VALUE)~(VALUE)0)
    VALUE hx, hy, mask = VALUE_MAX >> ((SIZEOF_VALUE - m) * CHAR_BIT);

    if (m > SIZEOF_VALUE)
        rb_bug("!!too long pattern string!!");

    if (!(y = memchr(y, *x, n - m + 1)))
        return -1;

    /* Prepare hash value */
    for (hx = *x++, hy = *y++; x < xe; ++x, ++y) {
        hx <<= CHAR_BIT;
        hy <<= CHAR_BIT;
        hx |= *x;
        hy |= *y;
    }
    /* Searching */
    while (hx != hy) {
        if (y == ye)
            return -1;
        hy <<= CHAR_BIT;
        hy |= *y;
        hy &= mask;
        y++;
    }
    return y - ys - m;
}
#endif

static inline long
rb_memsearch_qs(const unsigned char *xs, long m, const unsigned char *ys, long n)
{
    const unsigned char *x = xs, *xe = xs + m;
    const unsigned char *y = ys;
    VALUE i, qstable[256];

    /* Preprocessing */
    for (i = 0; i < 256; ++i)
        qstable[i] = m + 1;
    for (; x < xe; ++x)
        qstable[*x] = xe - x;
    /* Searching */
    for (; y + m <= ys + n; y += *(qstable + y[m])) {
        if (*xs == *y && memcmp(xs, y, m) == 0)
            return y - ys;
    }
    return -1;
}

static inline unsigned int
rb_memsearch_qs_utf8_hash(const unsigned char *x)
{
    register const unsigned int mix = 8353;
    register unsigned int h = *x;
    if (h < 0xC0) {
        return h + 256;
    }
    else if (h < 0xE0) {
        h *= mix;
        h += x[1];
    }
    else if (h < 0xF0) {
        h *= mix;
        h += x[1];
        h *= mix;
        h += x[2];
    }
    else if (h < 0xF5) {
        h *= mix;
        h += x[1];
        h *= mix;
        h += x[2];
        h *= mix;
        h += x[3];
    }
    else {
        return h + 256;
    }
    return (unsigned char)h;
}

static inline long
rb_memsearch_qs_utf8(const unsigned char *xs, long m, const unsigned char *ys, long n)
{
    const unsigned char *x = xs, *xe = xs + m;
    const unsigned char *y = ys;
    VALUE i, qstable[512];

    /* Preprocessing */
    for (i = 0; i < 512; ++i) {
        qstable[i] = m + 1;
    }
    for (; x < xe; ++x) {
        qstable[rb_memsearch_qs_utf8_hash(x)] = xe - x;
    }
    /* Searching */
    for (; y + m <= ys + n; y += qstable[rb_memsearch_qs_utf8_hash(y+m)]) {
        if (*xs == *y && memcmp(xs, y, m) == 0)
            return y - ys;
    }
    return -1;
}

static inline long
rb_memsearch_with_char_size(const unsigned char *xs, long m, const unsigned char *ys, long n, int char_size)
{
    const unsigned char *x = xs, x0 = *xs, *y = ys;

    for (n -= m; n >= 0; n -= char_size, y += char_size) {
        if (x0 == *y && memcmp(x+1, y+1, m-1) == 0)
            return y - ys;
    }
    return -1;
}

static inline long
rb_memsearch_wchar(const unsigned char *xs, long m, const unsigned char *ys, long n)
{
    return rb_memsearch_with_char_size(xs, m, ys, n, 2);
}

static inline long
rb_memsearch_qchar(const unsigned char *xs, long m, const unsigned char *ys, long n)
{
    return rb_memsearch_with_char_size(xs, m, ys, n, 4);
}

long
rb_memsearch(const void *x0, long m, const void *y0, long n, rb_encoding *enc)
{
    const unsigned char *x = x0, *y = y0;

    if (m > n) return -1;
    else if (m == n) {
        return memcmp(x0, y0, m) == 0 ? 0 : -1;
    }
    else if (m < 1) {
        return 0;
    }
    else if (m == 1) {
        const unsigned char *ys = memchr(y, *x, n);

        if (ys)
            return ys - y;
        else
            return -1;
    }
    else if (LIKELY(rb_enc_mbminlen(enc) == 1)) {
        if (m <= SIZEOF_VALUE) {
            return rb_memsearch_ss(x0, m, y0, n);
        }
        else if (enc == rb_utf8_encoding()){
            return rb_memsearch_qs_utf8(x0, m, y0, n);
        }
    }
    else if (LIKELY(rb_enc_mbminlen(enc) == 2)) {
        return rb_memsearch_wchar(x0, m, y0, n);
    }
    else if (LIKELY(rb_enc_mbminlen(enc) == 4)) {
        return rb_memsearch_qchar(x0, m, y0, n);
    }
    return rb_memsearch_qs(x0, m, y0, n);
}

#define REG_ENCODING_NONE FL_USER6

#define KCODE_FIXED FL_USER4

#define ARG_REG_OPTION_MASK \
    (ONIG_OPTION_IGNORECASE|ONIG_OPTION_MULTILINE|ONIG_OPTION_EXTEND)
#define ARG_ENCODING_FIXED    16
#define ARG_ENCODING_NONE     32

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

enum { OPTBUF_SIZE = 4 };

static char *
option_to_str(char str[OPTBUF_SIZE], int options)
{
    char *p = str;
    if (options & ONIG_OPTION_MULTILINE) *p++ = 'm';
    if (options & ONIG_OPTION_IGNORECASE) *p++ = 'i';
    if (options & ONIG_OPTION_EXTEND) *p++ = 'x';
    *p = 0;
    return str;
}

extern int
rb_char_to_option_kcode(int c, int *option, int *kcode)
{
    *option = 0;

    switch (c) {
      case 'n':
        *kcode = rb_ascii8bit_encindex();
        return (*option = ARG_ENCODING_NONE);
      case 'e':
        *kcode = ENCINDEX_EUC_JP;
        break;
      case 's':
        *kcode = ENCINDEX_Windows_31J;
        break;
      case 'u':
        *kcode = rb_utf8_encindex();
        break;
      default:
        *kcode = -1;
        return (*option = char_to_option(c));
    }
    *option = ARG_ENCODING_FIXED;
    return 1;
}

static void
rb_reg_check(VALUE re)
{
    if (!RREGEXP_PTR(re) || !RREGEXP_SRC(re) || !RREGEXP_SRC_PTR(re)) {
        rb_raise(rb_eTypeError, "uninitialized Regexp");
    }
}

static void
rb_reg_expr_str(VALUE str, const char *s, long len,
                rb_encoding *enc, rb_encoding *resenc, int term)
{
    const char *p, *pend;
    int cr = ENC_CODERANGE_UNKNOWN;
    int need_escape = 0;
    int c, clen;

    p = s; pend = p + len;
    rb_str_coderange_scan_restartable(p, pend, enc, &cr);
    if (rb_enc_asciicompat(enc) && ENC_CODERANGE_CLEAN_P(cr)) {
        while (p < pend) {
            c = rb_enc_ascget(p, pend, &clen, enc);
            if (c == -1) {
                if (enc == resenc) {
                    p += mbclen(p, pend, enc);
                }
                else {
                    need_escape = 1;
                    break;
                }
            }
            else if (c != term && rb_enc_isprint(c, enc)) {
                p += clen;
            }
            else {
                need_escape = 1;
                break;
            }
        }
    }
    else {
        need_escape = 1;
    }

    if (!need_escape) {
        rb_str_buf_cat(str, s, len);
    }
    else {
        int unicode_p = rb_enc_unicode_p(enc);
        p = s;
        while (p<pend) {
            c = rb_enc_ascget(p, pend, &clen, enc);
            if (c == '\\' && p+clen < pend) {
                int n = clen + mbclen(p+clen, pend, enc);
                rb_str_buf_cat(str, p, n);
                p += n;
                continue;
            }
            else if (c == -1) {
                clen = rb_enc_precise_mbclen(p, pend, enc);
                if (!MBCLEN_CHARFOUND_P(clen)) {
                    c = (unsigned char)*p;
                    clen = 1;
                    goto hex;
                }
                if (resenc) {
                    unsigned int c = rb_enc_mbc_to_codepoint(p, pend, enc);
                    rb_str_buf_cat_escaped_char(str, c, unicode_p);
                }
                else {
                    clen = MBCLEN_CHARFOUND_LEN(clen);
                    rb_str_buf_cat(str, p, clen);
                }
            }
            else if (c == term) {
                char c = '\\';
                rb_str_buf_cat(str, &c, 1);
                rb_str_buf_cat(str, p, clen);
            }
            else if (rb_enc_isprint(c, enc)) {
                rb_str_buf_cat(str, p, clen);
            }
            else if (!rb_enc_isspace(c, enc)) {
                char b[8];

              hex:
                snprintf(b, sizeof(b), "\\x%02X", c);
                rb_str_buf_cat(str, b, 4);
            }
            else {
                rb_str_buf_cat(str, p, clen);
            }
            p += clen;
        }
    }
}

static VALUE
rb_reg_desc(VALUE re)
{
    rb_encoding *enc = rb_enc_get(re);
    VALUE str = rb_str_buf_new2("/");
    rb_encoding *resenc = rb_default_internal_encoding();
    if (resenc == NULL) resenc = rb_default_external_encoding();

    if (re && rb_enc_asciicompat(enc)) {
        rb_enc_copy(str, re);
    }
    else {
        rb_enc_associate(str, rb_usascii_encoding());
    }

    VALUE src_str = RREGEXP_SRC(re);
    rb_reg_expr_str(str, RSTRING_PTR(src_str), RSTRING_LEN(src_str), enc, resenc, '/');
    RB_GC_GUARD(src_str);

    rb_str_buf_cat2(str, "/");
    if (re) {
        char opts[OPTBUF_SIZE];
        rb_reg_check(re);
        if (*option_to_str(opts, RREGEXP_PTR(re)->options))
            rb_str_buf_cat2(str, opts);
        if (RBASIC(re)->flags & REG_ENCODING_NONE)
            rb_str_buf_cat2(str, "n");
    }
    return str;
}


/*
 *  call-seq:
 *    source -> string
 *
 *  Returns the original string of +self+:
 *
 *    /ab+c/ix.source # => "ab+c"
 *
 *  Regexp escape sequences are retained:
 *
 *    /\x20\+/.source  # => "\\x20\\+"
 *
 *  Lexer escape characters are not retained:
 *
 *    /\//.source  # => "/"
 *
 */

static VALUE
rb_reg_source(VALUE re)
{
    VALUE str;

    rb_reg_check(re);
    str = rb_str_dup(RREGEXP_SRC(re));
    return str;
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a nicely-formatted string representation of +self+:
 *
 *    /ab+c/ix.inspect # => "/ab+c/ix"
 *
 *  Related: Regexp#to_s.
 */

static VALUE
rb_reg_inspect(VALUE re)
{
    if (!RREGEXP_PTR(re) || !RREGEXP_SRC(re) || !RREGEXP_SRC_PTR(re)) {
        return rb_any_to_s(re);
    }
    return rb_reg_desc(re);
}

static VALUE rb_reg_str_with_term(VALUE re, int term);

/*
 *  call-seq:
 *    to_s -> string
 *
 *  Returns a string showing the options and string of +self+:
 *
 *    r0 = /ab+c/ix
 *    s0 = r0.to_s # => "(?ix-m:ab+c)"
 *
 *  The returned string may be used as an argument to Regexp.new,
 *  or as interpolated text for a
 *  {Regexp interpolation}[rdoc-ref:Regexp@Interpolation+Mode]:
 *
 *    r1 = Regexp.new(s0) # => /(?ix-m:ab+c)/
 *    r2 = /#{s0}/        # => /(?ix-m:ab+c)/
 *
 *  Note that +r1+ and +r2+ are not equal to +r0+
 *  because their original strings are different:
 *
 *    r0 == r1  # => false
 *    r0.source # => "ab+c"
 *    r1.source # => "(?ix-m:ab+c)"
 *
 *  Related: Regexp#inspect.
 *
 */

static VALUE
rb_reg_to_s(VALUE re)
{
    return rb_reg_str_with_term(re, '/');
}

static VALUE
rb_reg_str_with_term(VALUE re, int term)
{
    int options, opt;
    const int embeddable = ONIG_OPTION_MULTILINE|ONIG_OPTION_IGNORECASE|ONIG_OPTION_EXTEND;
    VALUE str = rb_str_buf_new2("(?");
    char optbuf[OPTBUF_SIZE + 1]; /* for '-' */
    rb_encoding *enc = rb_enc_get(re);

    rb_reg_check(re);

    rb_enc_copy(str, re);
    options = RREGEXP_PTR(re)->options;
    VALUE src_str = RREGEXP_SRC(re);
    const UChar *ptr = (UChar *)RSTRING_PTR(src_str);
    long len = RSTRING_LEN(src_str);
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
            Regexp *rp;
            VALUE verbose = ruby_verbose;
            ruby_verbose = Qfalse;

            ++ptr;
            len -= 2;
            err = onig_new(&rp, ptr, ptr + len, options,
                           enc, OnigDefaultSyntax, NULL);
            onig_free(rp);
            ruby_verbose = verbose;
        }
        if (err) {
            options = RREGEXP_PTR(re)->options;
            ptr = (UChar*)RREGEXP_SRC_PTR(re);
            len = RREGEXP_SRC_LEN(re);
        }
    }

    if (*option_to_str(optbuf, options)) rb_str_buf_cat2(str, optbuf);

    if ((options & embeddable) != embeddable) {
        optbuf[0] = '-';
        option_to_str(optbuf + 1, ~options);
        rb_str_buf_cat2(str, optbuf);
    }

    rb_str_buf_cat2(str, ":");
    if (rb_enc_asciicompat(enc)) {
        rb_reg_expr_str(str, (char*)ptr, len, enc, NULL, term);
        rb_str_buf_cat2(str, ")");
    }
    else {
        const char *s, *e;
        char *paren;
        ptrdiff_t n;
        rb_str_buf_cat2(str, ")");
        rb_enc_associate(str, rb_usascii_encoding());
        str = rb_str_encode(str, rb_enc_from_encoding(enc), 0, Qnil);

        /* backup encoded ")" to paren */
        s = RSTRING_PTR(str);
        e = RSTRING_END(str);
        s = rb_enc_left_char_head(s, e-1, e, enc);
        n = e - s;
        paren = ALLOCA_N(char, n);
        memcpy(paren, s, n);
        rb_str_resize(str, RSTRING_LEN(str) - n);

        rb_reg_expr_str(str, (char*)ptr, len, enc, NULL, term);
        rb_str_buf_cat(str, paren, n);
    }
    rb_enc_copy(str, re);

    RB_GC_GUARD(src_str);

    return str;
}

NORETURN(static void rb_reg_raise(const char *err, VALUE re));

static void
rb_reg_raise(const char *err, VALUE re)
{
    VALUE desc = rb_reg_desc(re);

    rb_raise(rb_eRegexpError, "%s: %"PRIsVALUE, err, desc);
}

static VALUE
rb_enc_reg_error_desc(const char *s, long len, rb_encoding *enc, int options, const char *err)
{
    char opts[OPTBUF_SIZE + 1];	/* for '/' */
    VALUE desc = rb_str_buf_new2(err);
    rb_encoding *resenc = rb_default_internal_encoding();
    if (resenc == NULL) resenc = rb_default_external_encoding();

    rb_enc_associate(desc, enc);
    rb_str_buf_cat2(desc, ": /");
    rb_reg_expr_str(desc, s, len, enc, resenc, '/');
    opts[0] = '/';
    option_to_str(opts + 1, options);
    rb_str_buf_cat2(desc, opts);
    return rb_exc_new3(rb_eRegexpError, desc);
}

NORETURN(static void rb_enc_reg_raise(const char *s, long len, rb_encoding *enc, int options, const char *err));

static void
rb_enc_reg_raise(const char *s, long len, rb_encoding *enc, int options, const char *err)
{
    rb_exc_raise(rb_enc_reg_error_desc(s, len, enc, options, err));
}

static VALUE
rb_reg_error_desc(VALUE str, int options, const char *err)
{
    return rb_enc_reg_error_desc(RSTRING_PTR(str), RSTRING_LEN(str),
                                 rb_enc_get(str), options, err);
}

NORETURN(static void rb_reg_raise_str(VALUE str, int options, const char *err));

static void
rb_reg_raise_str(VALUE str, int options, const char *err)
{
    rb_exc_raise(rb_reg_error_desc(str, options, err));
}


/*
 *  call-seq:
 *    casefold?-> true or false
 *
 *  Returns +true+ if the case-insensitivity flag in +self+ is set,
 *  +false+ otherwise:
 *
 *    /a/.casefold?           # => false
 *    /a/i.casefold?          # => true
 *    /(?i:a)/.casefold?      # => false
 *
 */

static VALUE
rb_reg_casefold_p(VALUE re)
{
    rb_reg_check(re);
    return RBOOL(RREGEXP_PTR(re)->options & ONIG_OPTION_IGNORECASE);
}


/*
 *  call-seq:
 *    options -> integer
 *
 *  Returns an integer whose bits show the options set in +self+.
 *
 *  The option bits are:
 *
 *    Regexp::IGNORECASE # => 1
 *    Regexp::EXTENDED   # => 2
 *    Regexp::MULTILINE  # => 4
 *
 *  Examples:
 *
 *    /foo/.options    # => 0
 *    /foo/i.options   # => 1
 *    /foo/x.options   # => 2
 *    /foo/m.options   # => 4
 *    /foo/mix.options # => 7
 *
 *  Note that additional bits may be set in the returned integer;
 *  these are maintained internally in +self+, are ignored if passed
 *  to Regexp.new, and may be ignored by the caller:
 *
 *  Returns the set of bits corresponding to the options used when
 *  creating this regexp (see Regexp::new for details). Note that
 *  additional bits may be set in the returned options: these are used
 *  internally by the regular expression code. These extra bits are
 *  ignored if the options are passed to Regexp::new:
 *
 *    r = /\xa1\xa2/e                 # => /\xa1\xa2/
 *    r.source                        # => "\\xa1\\xa2"
 *    r.options                       # => 16
 *    Regexp.new(r.source, r.options) # => /\xa1\xa2/
 *
 */

static VALUE
rb_reg_options_m(VALUE re)
{
    int options = rb_reg_options(re);
    return INT2NUM(options);
}

static int
reg_names_iter(const OnigUChar *name, const OnigUChar *name_end,
          int back_num, int *back_refs, OnigRegex regex, void *arg)
{
    VALUE ary = (VALUE)arg;
    rb_ary_push(ary, rb_enc_str_new((const char *)name, name_end-name, regex->enc));
    return 0;
}

/*
 *  call-seq:
 *   names -> array_of_names
 *
 *  Returns an array of names of captures
 *  (see {Named Captures}[rdoc-ref:Regexp@Named+Captures]):
 *
 *    /(?<foo>.)(?<bar>.)(?<baz>.)/.names # => ["foo", "bar", "baz"]
 *    /(?<foo>.)(?<foo>.)/.names          # => ["foo"]
 *    /(.)(.)/.names                      # => []
 *
 */

static VALUE
rb_reg_names(VALUE re)
{
    VALUE ary;
    rb_reg_check(re);
    ary = rb_ary_new_capa(onig_number_of_names(RREGEXP_PTR(re)));
    onig_foreach_name(RREGEXP_PTR(re), reg_names_iter, (void*)ary);
    return ary;
}

static int
reg_named_captures_iter(const OnigUChar *name, const OnigUChar *name_end,
          int back_num, int *back_refs, OnigRegex regex, void *arg)
{
    VALUE hash = (VALUE)arg;
    VALUE ary = rb_ary_new2(back_num);
    int i;

    for (i = 0; i < back_num; i++)
        rb_ary_store(ary, i, INT2NUM(back_refs[i]));

    rb_hash_aset(hash, rb_str_new((const char*)name, name_end-name),ary);

    return 0;
}

/*
 *  call-seq:
 *    named_captures  -> hash
 *
 *  Returns a hash representing named captures of +self+
 *  (see {Named Captures}[rdoc-ref:Regexp@Named+Captures]):
 *
 *  - Each key is the name of a named capture.
 *  - Each value is an array of integer indexes for that named capture.
 *
 *  Examples:
 *
 *    /(?<foo>.)(?<bar>.)/.named_captures # => {"foo"=>[1], "bar"=>[2]}
 *    /(?<foo>.)(?<foo>.)/.named_captures # => {"foo"=>[1, 2]}
 *    /(.)(.)/.named_captures             # => {}
 *
 */

static VALUE
rb_reg_named_captures(VALUE re)
{
    regex_t *reg = (rb_reg_check(re), RREGEXP_PTR(re));
    VALUE hash = rb_hash_new_with_size(onig_number_of_names(reg));
    onig_foreach_name(reg, reg_named_captures_iter, (void*)hash);
    return hash;
}

static int
onig_new_with_source(regex_t** reg, const UChar* pattern, const UChar* pattern_end,
                     OnigOptionType option, OnigEncoding enc, const OnigSyntaxType* syntax,
                     OnigErrorInfo* einfo, const char *sourcefile, int sourceline)
{
    int r;

    *reg = (regex_t* )malloc(sizeof(regex_t));
    if (IS_NULL(*reg)) return ONIGERR_MEMORY;

    r = onig_reg_init(*reg, option, ONIGENC_CASE_FOLD_DEFAULT, enc, syntax);
    if (r) goto err;

    r = onig_compile_ruby(*reg, pattern, pattern_end, einfo, sourcefile, sourceline);
    if (r) {
      err:
        onig_free(*reg);
        *reg = NULL;
    }
    return r;
}

static Regexp*
make_regexp(const char *s, long len, rb_encoding *enc, int flags, onig_errmsg_buffer err,
        const char *sourcefile, int sourceline)
{
    Regexp *rp;
    int r;
    OnigErrorInfo einfo;

    /* Handle escaped characters first. */

    /* Build a copy of the string (in dest) with the
       escaped characters translated,  and generate the regex
       from that.
    */

    r = onig_new_with_source(&rp, (UChar*)s, (UChar*)(s + len), flags,
                 enc, OnigDefaultSyntax, &einfo, sourcefile, sourceline);
    if (r) {
        onig_error_code_to_str((UChar*)err, r, &einfo);
        return 0;
    }
    return rp;
}


/*
 *  Document-class: MatchData
 *
 *  MatchData encapsulates the result of matching a Regexp against
 *  string. It is returned by Regexp#match and String#match, and also
 *  stored in a global variable returned by Regexp.last_match.
 *
 *  Usage:
 *
 *      url = 'https://docs.ruby-lang.org/en/2.5.0/MatchData.html'
 *      m = url.match(/(\d\.?)+/)   # => #<MatchData "2.5.0" 1:"0">
 *      m.string                    # => "https://docs.ruby-lang.org/en/2.5.0/MatchData.html"
 *      m.regexp                    # => /(\d\.?)+/
 *      # entire matched substring:
 *      m[0]                        # => "2.5.0"
 *
 *      # Working with unnamed captures
 *      m = url.match(%r{([^/]+)/([^/]+)\.html$})
 *      m.captures                  # => ["2.5.0", "MatchData"]
 *      m[1]                        # => "2.5.0"
 *      m.values_at(1, 2)           # => ["2.5.0", "MatchData"]
 *
 *      # Working with named captures
 *      m = url.match(%r{(?<version>[^/]+)/(?<module>[^/]+)\.html$})
 *      m.captures                  # => ["2.5.0", "MatchData"]
 *      m.named_captures            # => {"version"=>"2.5.0", "module"=>"MatchData"}
 *      m[:version]                 # => "2.5.0"
 *      m.values_at(:version, :module)
 *                                  # => ["2.5.0", "MatchData"]
 *      # Numerical indexes are working, too
 *      m[1]                        # => "2.5.0"
 *      m.values_at(1, 2)           # => ["2.5.0", "MatchData"]
 *
 *  == Global variables equivalence
 *
 *  Parts of last MatchData (returned by Regexp.last_match) are also
 *  aliased as global variables:
 *
 *  * <code>$~</code> is Regexp.last_match;
 *  * <code>$&</code> is Regexp.last_match<code>[ 0 ]</code>;
 *  * <code>$1</code>, <code>$2</code>, and so on are
 *    Regexp.last_match<code>[ i ]</code> (captures by number);
 *  * <code>$`</code> is Regexp.last_match<code>.pre_match</code>;
 *  * <code>$'</code> is Regexp.last_match<code>.post_match</code>;
 *  * <code>$+</code> is Regexp.last_match<code>[ -1 ]</code> (the last capture).
 *
 *  See also "Special global variables" section in Regexp documentation.
 */

VALUE rb_cMatch;

static VALUE
match_alloc(VALUE klass)
{
    size_t alloc_size = sizeof(struct RMatch) + sizeof(rb_matchext_t);
    VALUE flags = T_MATCH | (RGENGC_WB_PROTECTED_MATCH ? FL_WB_PROTECTED : 0);
    NEWOBJ_OF(match, struct RMatch, klass, flags, alloc_size, 0);

    match->str = Qfalse;
    match->regexp = Qfalse;
    memset(RMATCH_EXT(match), 0, sizeof(rb_matchext_t));

    return (VALUE)match;
}

int
rb_reg_region_copy(struct re_registers *to, const struct re_registers *from)
{
    onig_region_copy(to, (OnigRegion *)from);
    if (to->allocated) return 0;
    rb_gc();
    onig_region_copy(to, (OnigRegion *)from);
    if (to->allocated) return 0;
    return ONIGERR_MEMORY;
}

typedef struct {
    long byte_pos;
    long char_pos;
} pair_t;

static int
pair_byte_cmp(const void *pair1, const void *pair2)
{
    long diff = ((pair_t*)pair1)->byte_pos - ((pair_t*)pair2)->byte_pos;
#if SIZEOF_LONG > SIZEOF_INT
    return diff ? diff > 0 ? 1 : -1 : 0;
#else
    return (int)diff;
#endif
}

#if USE_MMTK
static void
rb_mmtk_char_offset_realloc(struct rmatch_offset **field, size_t num_regs)
{
    struct rmatch_offset *old_field_value = *field;
    rb_mmtk_strbuf_t *old_strbuf = old_field_value == NULL
                                   ? NULL
                                   : rb_mmtk_chars_to_strbuf((char*)old_field_value);
    rb_mmtk_strbuf_t *new_strbuf = rb_mmtk_strbuf_realloc(old_strbuf, num_regs * sizeof(struct rmatch_offset));
    // TODO: Use write barrier.
    *field = (struct rmatch_offset*)rb_mmtk_strbuf_to_chars(new_strbuf);
}
#endif

static void
update_char_offset(VALUE match)
{
    rb_matchext_t *rm = RMATCH_EXT(match);
    struct re_registers *regs;
    int i, num_regs, num_pos;
    long c;
    char *s, *p, *q;
    rb_encoding *enc;
    pair_t *pairs;

    if (rm->char_offset_num_allocated)
        return;

    regs = &rm->regs;
    num_regs = rm->regs.num_regs;

    if (rm->char_offset_num_allocated < num_regs) {
#if USE_MMTK
        if (!rb_mmtk_enabled_p()) {
#endif
        REALLOC_N(rm->char_offset, struct rmatch_offset, num_regs);
#if USE_MMTK
        } else {
            rb_mmtk_char_offset_realloc(&rm->char_offset, num_regs);
        }
#endif
        rm->char_offset_num_allocated = num_regs;
    }

    enc = rb_enc_get(RMATCH(match)->str);
    if (rb_enc_mbmaxlen(enc) == 1) {
        for (i = 0; i < num_regs; i++) {
            rm->char_offset[i].beg = BEG(i);
            rm->char_offset[i].end = END(i);
        }
        return;
    }

    pairs = ALLOCA_N(pair_t, num_regs*2);
    num_pos = 0;
    for (i = 0; i < num_regs; i++) {
        if (BEG(i) < 0)
            continue;
        pairs[num_pos++].byte_pos = BEG(i);
        pairs[num_pos++].byte_pos = END(i);
    }
    qsort(pairs, num_pos, sizeof(pair_t), pair_byte_cmp);

    s = p = RSTRING_PTR(RMATCH(match)->str);
    c = 0;
    for (i = 0; i < num_pos; i++) {
        q = s + pairs[i].byte_pos;
        c += rb_enc_strlen(p, q, enc);
        pairs[i].char_pos = c;
        p = q;
    }

    for (i = 0; i < num_regs; i++) {
        pair_t key, *found;
        if (BEG(i) < 0) {
            rm->char_offset[i].beg = -1;
            rm->char_offset[i].end = -1;
            continue;
        }

        key.byte_pos = BEG(i);
        found = bsearch(&key, pairs, num_pos, sizeof(pair_t), pair_byte_cmp);
        rm->char_offset[i].beg = found->char_pos;

        key.byte_pos = END(i);
        found = bsearch(&key, pairs, num_pos, sizeof(pair_t), pair_byte_cmp);
        rm->char_offset[i].end = found->char_pos;
    }
}

static VALUE
match_check(VALUE match)
{
    if (!RMATCH(match)->regexp) {
        rb_raise(rb_eTypeError, "uninitialized MatchData");
    }
    return match;
}

/* :nodoc: */
static VALUE
match_init_copy(VALUE obj, VALUE orig)
{
    rb_matchext_t *rm;

    if (!OBJ_INIT_COPY(obj, orig)) return obj;

    RB_OBJ_WRITE(obj, &RMATCH(obj)->str, RMATCH(orig)->str);
    RB_OBJ_WRITE(obj, &RMATCH(obj)->regexp, RMATCH(orig)->regexp);

    rm = RMATCH_EXT(obj);

#if USE_MMTK
    if (rb_mmtk_enabled_p()) {
        // The rb_reg_region_copy below may write to `obj` (`rm->registers.{beg,end}`).
        // We apply write barrier here.  It's probably not necessary because the `RB_OBJ_WRITE`
        // above executes the same object-remembering operation.
        rb_gc_writebarrier_remember(obj);
    }
#endif

    if (rb_reg_region_copy(&rm->regs, RMATCH_REGS(orig)))
        rb_memerror();

    if (RMATCH_EXT(orig)->char_offset_num_allocated) {
        if (rm->char_offset_num_allocated < rm->regs.num_regs) {
#if USE_MMTK
            if (!rb_mmtk_enabled_p()) {
#endif
            REALLOC_N(rm->char_offset, struct rmatch_offset, rm->regs.num_regs);
#if USE_MMTK
            } else {
                rb_mmtk_char_offset_realloc(&rm->char_offset, rm->regs.num_regs);
            }
#endif
            rm->char_offset_num_allocated = rm->regs.num_regs;
        }
        MEMCPY(rm->char_offset, RMATCH_EXT(orig)->char_offset,
               struct rmatch_offset, rm->regs.num_regs);
        RB_GC_GUARD(orig);
    }

    return obj;
}


/*
 *  call-seq:
 *    regexp -> regexp
 *
 *  Returns the regexp that produced the match:
 *
 *    m = /a.*b/.match("abc") # => #<MatchData "ab">
 *    m.regexp                # => /a.*b/
 *
 */

static VALUE
match_regexp(VALUE match)
{
    VALUE regexp;
    match_check(match);
    regexp = RMATCH(match)->regexp;
    if (NIL_P(regexp)) {
        VALUE str = rb_reg_nth_match(0, match);
        regexp = rb_reg_regcomp(rb_reg_quote(str));
        RB_OBJ_WRITE(match, &RMATCH(match)->regexp, regexp);
    }
    return regexp;
}

/*
 *  call-seq:
 *    names -> array_of_names
 *
 *  Returns an array of the capture names
 *  (see {Named Captures}[rdoc-ref:Regexp@Named+Captures]):
 *
 *    m = /(?<foo>.)(?<bar>.)(?<baz>.)/.match("hoge")
 *    # => #<MatchData "hog" foo:"h" bar:"o" baz:"g">
 *    m.names # => ["foo", "bar", "baz"]
 *
 *    m = /foo/.match('foo') # => #<MatchData "foo">
 *    m.names # => [] # No named captures.
 *
 *  Equivalent to:
 *
 *    m = /(?<foo>.)(?<bar>.)(?<baz>.)/.match("hoge")
 *    m.regexp.names # => ["foo", "bar", "baz"]
 *
 */

static VALUE
match_names(VALUE match)
{
    match_check(match);
    if (NIL_P(RMATCH(match)->regexp))
        return rb_ary_new_capa(0);
    return rb_reg_names(RMATCH(match)->regexp);
}

/*
 *  call-seq:
 *    size -> integer
 *
 *  Returns size of the match array:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m.size # => 5
 *
 */

static VALUE
match_size(VALUE match)
{
    match_check(match);
    return INT2FIX(RMATCH_REGS(match)->num_regs);
}

static int name_to_backref_number(struct re_registers *, VALUE, const char*, const char*);
NORETURN(static void name_to_backref_error(VALUE name));

static void
name_to_backref_error(VALUE name)
{
    rb_raise(rb_eIndexError, "undefined group name reference: % "PRIsVALUE,
             name);
}

static void
backref_number_check(struct re_registers *regs, int i)
{
    if (i < 0 || regs->num_regs <= i)
        rb_raise(rb_eIndexError, "index %d out of matches", i);
}

static int
match_backref_number(VALUE match, VALUE backref)
{
    const char *name;
    int num;

    struct re_registers *regs = RMATCH_REGS(match);
    VALUE regexp = RMATCH(match)->regexp;

    match_check(match);
    if (SYMBOL_P(backref)) {
        backref = rb_sym2str(backref);
    }
    else if (!RB_TYPE_P(backref, T_STRING)) {
        return NUM2INT(backref);
    }
    name = StringValueCStr(backref);

    num = name_to_backref_number(regs, regexp, name, name + RSTRING_LEN(backref));

    if (num < 1) {
        name_to_backref_error(backref);
    }

    return num;
}

int
rb_reg_backref_number(VALUE match, VALUE backref)
{
    return match_backref_number(match, backref);
}

/*
 *  call-seq:
 *    offset(n) -> [start_offset, end_offset]
 *    offset(name) -> [start_offset, end_offset]
 *
 *  :include: doc/matchdata/offset.rdoc
 *
 */

static VALUE
match_offset(VALUE match, VALUE n)
{
    int i = match_backref_number(match, n);
    struct re_registers *regs = RMATCH_REGS(match);

    match_check(match);
    backref_number_check(regs, i);

    if (BEG(i) < 0)
        return rb_assoc_new(Qnil, Qnil);

    update_char_offset(match);
    return rb_assoc_new(LONG2NUM(RMATCH_EXT(match)->char_offset[i].beg),
                        LONG2NUM(RMATCH_EXT(match)->char_offset[i].end));
}

/*
 *  call-seq:
 *     mtch.byteoffset(n)   -> array
 *
 *  Returns a two-element array containing the beginning and ending byte-based offsets of
 *  the <em>n</em>th match.
 *  <em>n</em> can be a string or symbol to reference a named capture.
 *
 *     m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *     m.byteoffset(0)      #=> [1, 7]
 *     m.byteoffset(4)      #=> [6, 7]
 *
 *     m = /(?<foo>.)(.)(?<bar>.)/.match("hoge")
 *     p m.byteoffset(:foo) #=> [0, 1]
 *     p m.byteoffset(:bar) #=> [2, 3]
 *
 */

static VALUE
match_byteoffset(VALUE match, VALUE n)
{
    int i = match_backref_number(match, n);
    struct re_registers *regs = RMATCH_REGS(match);

    match_check(match);
    backref_number_check(regs, i);

    if (BEG(i) < 0)
        return rb_assoc_new(Qnil, Qnil);
    return rb_assoc_new(LONG2NUM(BEG(i)), LONG2NUM(END(i)));
}


/*
 *  call-seq:
 *    begin(n) -> integer
 *    begin(name) -> integer
 *
 *  :include: doc/matchdata/begin.rdoc
 *
 */

static VALUE
match_begin(VALUE match, VALUE n)
{
    int i = match_backref_number(match, n);
    struct re_registers *regs = RMATCH_REGS(match);

    match_check(match);
    backref_number_check(regs, i);

    if (BEG(i) < 0)
        return Qnil;

    update_char_offset(match);
    return LONG2NUM(RMATCH_EXT(match)->char_offset[i].beg);
}


/*
 *  call-seq:
 *    end(n) -> integer
 *    end(name) -> integer
 *
 *  :include: doc/matchdata/end.rdoc
 *
 */

static VALUE
match_end(VALUE match, VALUE n)
{
    int i = match_backref_number(match, n);
    struct re_registers *regs = RMATCH_REGS(match);

    match_check(match);
    backref_number_check(regs, i);

    if (BEG(i) < 0)
        return Qnil;

    update_char_offset(match);
    return LONG2NUM(RMATCH_EXT(match)->char_offset[i].end);
}

/*
 *  call-seq:
 *    match(n) -> string or nil
 *    match(name) -> string or nil
 *
 *  Returns the matched substring corresponding to the given argument.
 *
 *  When non-negative argument +n+ is given,
 *  returns the matched substring for the <tt>n</tt>th match:
 *
 *    m = /(.)(.)(\d+)(\d)(\w)?/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8" 5:nil>
 *    m.match(0) # => "HX1138"
 *    m.match(4) # => "8"
 *    m.match(5) # => nil
 *
 *  When string or symbol argument +name+ is given,
 *  returns the matched substring for the given name:
 *
 *    m = /(?<foo>.)(.)(?<bar>.+)/.match("hoge")
 *    # => #<MatchData "hoge" foo:"h" bar:"ge">
 *    m.match('foo') # => "h"
 *    m.match(:bar)  # => "ge"
 *
 */

static VALUE
match_nth(VALUE match, VALUE n)
{
    int i = match_backref_number(match, n);
    struct re_registers *regs = RMATCH_REGS(match);

    backref_number_check(regs, i);

    long start = BEG(i), end = END(i);
    if (start < 0)
        return Qnil;

    return rb_str_subseq(RMATCH(match)->str, start, end - start);
}

/*
 *  call-seq:
 *    match_length(n) -> integer or nil
 *    match_length(name) -> integer or nil
 *
 *  Returns the length (in characters) of the matched substring
 *  corresponding to the given argument.
 *
 *  When non-negative argument +n+ is given,
 *  returns the length of the matched substring
 *  for the <tt>n</tt>th match:
 *
 *    m = /(.)(.)(\d+)(\d)(\w)?/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8" 5:nil>
 *    m.match_length(0) # => 6
 *    m.match_length(4) # => 1
 *    m.match_length(5) # => nil
 *
 *  When string or symbol argument +name+ is given,
 *  returns the length of the matched substring
 *  for the named match:
 *
 *    m = /(?<foo>.)(.)(?<bar>.+)/.match("hoge")
 *    # => #<MatchData "hoge" foo:"h" bar:"ge">
 *    m.match_length('foo') # => 1
 *    m.match_length(:bar)  # => 2
 *
 */

static VALUE
match_nth_length(VALUE match, VALUE n)
{
    int i = match_backref_number(match, n);
    struct re_registers *regs = RMATCH_REGS(match);

    match_check(match);
    backref_number_check(regs, i);

    if (BEG(i) < 0)
        return Qnil;

    update_char_offset(match);
    const struct rmatch_offset *const ofs =
        &RMATCH_EXT(match)->char_offset[i];
    return LONG2NUM(ofs->end - ofs->beg);
}

#define MATCH_BUSY FL_USER2

void
rb_match_busy(VALUE match)
{
    FL_SET(match, MATCH_BUSY);
}

void
rb_match_unbusy(VALUE match)
{
    FL_UNSET(match, MATCH_BUSY);
}

int
rb_match_count(VALUE match)
{
    struct re_registers *regs;
    if (NIL_P(match)) return -1;
    regs = RMATCH_REGS(match);
    if (!regs) return -1;
    return regs->num_regs;
}

static void
match_set_string(VALUE m, VALUE string, long pos, long len)
{
    struct RMatch *match = (struct RMatch *)m;
    rb_matchext_t *rmatch = RMATCH_EXT(match);

    RB_OBJ_WRITE(match, &RMATCH(match)->str, string);
    RB_OBJ_WRITE(match, &RMATCH(match)->regexp, Qnil);

#if USE_MMTK
    if (rb_mmtk_enabled_p()) {
        // The onig_region_resize below may write to `m` (`rmatch->registers.{beg,end}`).
        // We apply write barrier here.  It's probably not necessary because the `RB_OBJ_WRITE`
        // above executes the same object-remembering operation.
        rb_gc_writebarrier_remember(m);
    }
#endif
    int err = onig_region_resize(&rmatch->regs, 1);
    if (err) rb_memerror();
    rmatch->regs.beg[0] = pos;
    rmatch->regs.end[0] = pos + len;
}

void
rb_backref_set_string(VALUE string, long pos, long len)
{
    VALUE match = rb_backref_get();
    if (NIL_P(match) || FL_TEST(match, MATCH_BUSY)) {
        match = match_alloc(rb_cMatch);
    }
    match_set_string(match, string, pos, len);
    rb_backref_set(match);
}

/*
 *  call-seq:
 *    fixed_encoding?   -> true or false
 *
 *  Returns +false+ if +self+ is applicable to
 *  a string with any ASCII-compatible encoding;
 *  otherwise returns +true+:
 *
 *    r = /a/                                          # => /a/
 *    r.fixed_encoding?                               # => false
 *    r.match?("\u{6666} a")                          # => true
 *    r.match?("\xa1\xa2 a".force_encoding("euc-jp")) # => true
 *    r.match?("abc".force_encoding("euc-jp"))        # => true
 *
 *    r = /a/u                                        # => /a/
 *    r.fixed_encoding?                               # => true
 *    r.match?("\u{6666} a")                          # => true
 *    r.match?("\xa1\xa2".force_encoding("euc-jp"))   # Raises exception.
 *    r.match?("abc".force_encoding("euc-jp"))        # => true
 *
 *    r = /\u{6666}/                                  # => /\u{6666}/
 *    r.fixed_encoding?                               # => true
 *    r.encoding                                      # => #<Encoding:UTF-8>
 *    r.match?("\u{6666} a")                          # => true
 *    r.match?("\xa1\xa2".force_encoding("euc-jp"))   # Raises exception.
 *    r.match?("abc".force_encoding("euc-jp"))        # => false
 *
 */

static VALUE
rb_reg_fixed_encoding_p(VALUE re)
{
    return RBOOL(FL_TEST(re, KCODE_FIXED));
}

static VALUE
rb_reg_preprocess(const char *p, const char *end, rb_encoding *enc,
        rb_encoding **fixed_enc, onig_errmsg_buffer err, int options);

NORETURN(static void reg_enc_error(VALUE re, VALUE str));

static void
reg_enc_error(VALUE re, VALUE str)
{
    rb_raise(rb_eEncCompatError,
             "incompatible encoding regexp match (%s regexp with %s string)",
             rb_enc_name(rb_enc_get(re)),
             rb_enc_name(rb_enc_get(str)));
}

static inline int
str_coderange(VALUE str)
{
    int cr = ENC_CODERANGE(str);
    if (cr == ENC_CODERANGE_UNKNOWN) {
        cr = rb_enc_str_coderange(str);
    }
    return cr;
}

static rb_encoding*
rb_reg_prepare_enc(VALUE re, VALUE str, int warn)
{
    rb_encoding *enc = 0;
    int cr = str_coderange(str);

    if (cr == ENC_CODERANGE_BROKEN) {
        rb_raise(rb_eArgError,
            "invalid byte sequence in %s",
            rb_enc_name(rb_enc_get(str)));
    }

    rb_reg_check(re);
    enc = rb_enc_get(str);
    if (RREGEXP_PTR(re)->enc == enc) {
    }
    else if (cr == ENC_CODERANGE_7BIT &&
            RREGEXP_PTR(re)->enc == rb_usascii_encoding()) {
        enc = RREGEXP_PTR(re)->enc;
    }
    else if (!rb_enc_asciicompat(enc)) {
        reg_enc_error(re, str);
    }
    else if (rb_reg_fixed_encoding_p(re)) {
        if ((!rb_enc_asciicompat(RREGEXP_PTR(re)->enc) ||
             cr != ENC_CODERANGE_7BIT)) {
            reg_enc_error(re, str);
        }
        enc = RREGEXP_PTR(re)->enc;
    }
    else if (warn && (RBASIC(re)->flags & REG_ENCODING_NONE) &&
        enc != rb_ascii8bit_encoding() &&
        cr != ENC_CODERANGE_7BIT) {
        rb_warn("historical binary regexp match /.../n against %s string",
                rb_enc_name(enc));
    }
    return enc;
}

regex_t *
rb_reg_prepare_re(VALUE re, VALUE str)
{
    int r;
    OnigErrorInfo einfo;
    VALUE unescaped;
    rb_encoding *fixed_enc = 0;
    rb_encoding *enc = rb_reg_prepare_enc(re, str, 1);

    regex_t *reg = RREGEXP_PTR(re);
    if (reg->enc == enc) return reg;

    rb_reg_check(re);

    VALUE src_str = RREGEXP_SRC(re);
    const char *pattern = RSTRING_PTR(src_str);

    onig_errmsg_buffer err = "";
    unescaped = rb_reg_preprocess(
        pattern, pattern + RSTRING_LEN(src_str), enc,
        &fixed_enc, err, 0);

    if (NIL_P(unescaped)) {
        rb_raise(rb_eArgError, "regexp preprocess failed: %s", err);
    }

    // inherit the timeout settings
    rb_hrtime_t timelimit = reg->timelimit;

    const char *ptr;
    long len;
    RSTRING_GETMEM(unescaped, ptr, len);

    /* If there are no other users of this regex, then we can directly overwrite it. */
    if (RREGEXP(re)->usecnt == 0) {
        regex_t tmp_reg;
        r = onig_new_without_alloc(&tmp_reg, (UChar *)ptr, (UChar *)(ptr + len),
                                   reg->options, enc,
                                   OnigDefaultSyntax, &einfo);

        if (r) {
            /* There was an error so perform cleanups. */
            onig_free_body(&tmp_reg);
        }
        else {
            onig_free_body(reg);
            /* There are no errors so set reg to tmp_reg. */
            *reg = tmp_reg;
        }
    }
    else {
        r = onig_new(&reg, (UChar *)ptr, (UChar *)(ptr + len),
                     reg->options, enc,
                     OnigDefaultSyntax, &einfo);
    }

    if (r) {
        onig_error_code_to_str((UChar*)err, r, &einfo);
        rb_reg_raise(err, re);
    }

    reg->timelimit = timelimit;

    RB_GC_GUARD(unescaped);
    RB_GC_GUARD(src_str);
    return reg;
}

OnigPosition
rb_reg_onig_match(VALUE re, VALUE str,
                  OnigPosition (*match)(regex_t *reg, VALUE str, struct re_registers *regs, void *args),
                  void *args, struct re_registers *regs)
{
    regex_t *reg = rb_reg_prepare_re(re, str);

    bool tmpreg = reg != RREGEXP_PTR(re);
    if (!tmpreg) RREGEXP(re)->usecnt++;

    OnigPosition result = match(reg, str, regs, args);

    if (!tmpreg) RREGEXP(re)->usecnt--;
    if (tmpreg) {
        onig_free(reg);
    }

    if (result < 0) {
        onig_region_free(regs, 0);

        if (result != ONIG_MISMATCH) {
            onig_errmsg_buffer err = "";
            onig_error_code_to_str((UChar*)err, (int)result);
            rb_reg_raise(err, re);
        }
    }

    return result;
}

long
rb_reg_adjust_startpos(VALUE re, VALUE str, long pos, int reverse)
{
    long range;
    rb_encoding *enc;
    UChar *p, *string;

    enc = rb_reg_prepare_enc(re, str, 0);

    if (reverse) {
        range = -pos;
    }
    else {
        range = RSTRING_LEN(str) - pos;
    }

    if (pos > 0 && ONIGENC_MBC_MAXLEN(enc) != 1 && pos < RSTRING_LEN(str)) {
         string = (UChar*)RSTRING_PTR(str);

         if (range > 0) {
              p = onigenc_get_right_adjust_char_head(enc, string, string + pos, string + RSTRING_LEN(str));
         }
         else {
              p = ONIGENC_LEFT_ADJUST_CHAR_HEAD(enc, string, string + pos, string + RSTRING_LEN(str));
         }
         return p - string;
    }

    return pos;
}

struct reg_onig_search_args {
    long pos;
    long range;
};

static OnigPosition
reg_onig_search(regex_t *reg, VALUE str, struct re_registers *regs, void *args_ptr)
{
    struct reg_onig_search_args *args = (struct reg_onig_search_args *)args_ptr;
    const char *ptr;
    long len;
    RSTRING_GETMEM(str, ptr, len);

    return onig_search(
        reg,
        (UChar *)ptr,
        (UChar *)(ptr + len),
        (UChar *)(ptr + args->pos),
        (UChar *)(ptr + args->range),
        regs,
        ONIG_OPTION_NONE);
}

struct rb_reg_onig_match_args {
    VALUE re;
    VALUE str;
    struct reg_onig_search_args args;
    struct re_registers regs;

    OnigPosition result;
};

static VALUE
rb_reg_onig_match_try(VALUE value_args)
{
    struct rb_reg_onig_match_args *args = (struct rb_reg_onig_match_args *)value_args;
    args->result = rb_reg_onig_match(args->re, args->str, reg_onig_search, &args->args, &args->regs);
    return Qnil;
}

/* returns byte offset */
static long
rb_reg_search_set_match(VALUE re, VALUE str, long pos, int reverse, int set_backref_str, VALUE *set_match)
{
    long len = RSTRING_LEN(str);
    if (pos > len || pos < 0) {
        rb_backref_set(Qnil);
        return -1;
    }

    struct rb_reg_onig_match_args args = {
        .re = re,
        .str = str,
        .args = {
            .pos = pos,
            .range = reverse ? 0 : len,
        },
        .regs = {0}
    };

    /* If there is a timeout set, then rb_reg_onig_match could raise a
     * Regexp::TimeoutError so we want to protect it from leaking memory. */
    if (rb_reg_match_time_limit) {
        int state;
        rb_protect(rb_reg_onig_match_try, (VALUE)&args, &state);
        if (state) {
            onig_region_free(&args.regs, false);
            rb_jump_tag(state);
        }
    }
    else {
        rb_reg_onig_match_try((VALUE)&args);
    }

    if (args.result == ONIG_MISMATCH) {
        rb_backref_set(Qnil);
        return ONIG_MISMATCH;
    }

#if USE_MMTK
    VALUE root_beg;
    VALUE root_end;
    if (rb_mmtk_enabled_p()) {
        // When using MMTk, the `beg` and `end` fields of `re_registers` point to heap objects,
        // but are interior pointers.  The conservative stack scanner will not recognize interior
        // pointers as object references.  We compute the pointers to the beginning of those
        // objects and use RB_GC_GUARD to keep them on the stack so that even if the `match_alloc`
        // invocation triggers GC, the `beg` and `end` will still be kept alive.
        root_beg = (VALUE)rb_mmtk_chars_to_strbuf((char*)args.regs.beg);
        root_end = (VALUE)rb_mmtk_chars_to_strbuf((char*)args.regs.end);
    } else {
        root_beg = root_end = Qnil;
    }
#endif

    // MMTk note: `match_alloc` may trigger GC.
    VALUE match = match_alloc(rb_cMatch);
    rb_matchext_t *rm = RMATCH_EXT(match);
    rm->regs = args.regs;

#if USE_MMTK
    // Guard `root_beg` and `root_end` until here.  Now that `args.regs` has been assigned to a
    // field of `match`, the conservative stack scanner will pick up the `match` variable, and
    // `gc_mark_children` will take care of the interior pointers when scanning the `T_MATCH`.
    RB_GC_GUARD(root_beg);
    RB_GC_GUARD(root_end);
#endif

    if (set_backref_str) {
        RB_OBJ_WRITE(match, &RMATCH(match)->str, rb_str_new4(str));
    }
    else {
        /* Note that a MatchData object with RMATCH(match)->str == 0 is incomplete!
         * We need to hide the object from ObjectSpace.each_object.
         * https://bugs.ruby-lang.org/issues/19159
         */
        rb_obj_hide(match);
    }

    RB_OBJ_WRITE(match, &RMATCH(match)->regexp, re);
    rb_backref_set(match);
    if (set_match) *set_match = match;

    return args.result;
}

long
rb_reg_search0(VALUE re, VALUE str, long pos, int reverse, int set_backref_str)
{
    return rb_reg_search_set_match(re, str, pos, reverse, set_backref_str, NULL);
}

long
rb_reg_search(VALUE re, VALUE str, long pos, int reverse)
{
    return rb_reg_search0(re, str, pos, reverse, 1);
}

static OnigPosition
reg_onig_match(regex_t *reg, VALUE str, struct re_registers *regs, void *_)
{
    const char *ptr;
    long len;
    RSTRING_GETMEM(str, ptr, len);

    return onig_match(
        reg,
        (UChar *)ptr,
        (UChar *)(ptr + len),
        (UChar *)ptr,
        regs,
        ONIG_OPTION_NONE);
}

bool
rb_reg_start_with_p(VALUE re, VALUE str)
{
    VALUE match = rb_backref_get();
    if (NIL_P(match) || FL_TEST(match, MATCH_BUSY)) {
        match = match_alloc(rb_cMatch);
    }

    struct re_registers *regs = RMATCH_REGS(match);

    if (rb_reg_onig_match(re, str, reg_onig_match, NULL, regs) == ONIG_MISMATCH) {
        rb_backref_set(Qnil);
        return false;
    }

    RB_OBJ_WRITE(match, &RMATCH(match)->str, rb_str_new4(str));
    RB_OBJ_WRITE(match, &RMATCH(match)->regexp, re);
    rb_backref_set(match);

    return true;
}

VALUE
rb_reg_nth_defined(int nth, VALUE match)
{
    struct re_registers *regs;
    if (NIL_P(match)) return Qnil;
    match_check(match);
    regs = RMATCH_REGS(match);
    if (nth >= regs->num_regs) {
        return Qnil;
    }
    if (nth < 0) {
        nth += regs->num_regs;
        if (nth <= 0) return Qnil;
    }
    return RBOOL(BEG(nth) != -1);
}

VALUE
rb_reg_nth_match(int nth, VALUE match)
{
    VALUE str;
    long start, end, len;
    struct re_registers *regs;

    if (NIL_P(match)) return Qnil;
    match_check(match);
    regs = RMATCH_REGS(match);
    if (nth >= regs->num_regs) {
        return Qnil;
    }
    if (nth < 0) {
        nth += regs->num_regs;
        if (nth <= 0) return Qnil;
    }
    start = BEG(nth);
    if (start == -1) return Qnil;
    end = END(nth);
    len = end - start;
    str = rb_str_subseq(RMATCH(match)->str, start, len);
    return str;
}

VALUE
rb_reg_last_match(VALUE match)
{
    return rb_reg_nth_match(0, match);
}


/*
 *  call-seq:
 *    pre_match -> string
 *
 *  Returns the substring of the target string from its beginning
 *  up to the first match in +self+ (that is, <tt>self[0]</tt>);
 *  equivalent to regexp global variable <tt>$`</tt>:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m[0]        # => "HX1138"
 *    m.pre_match # => "T"
 *
 *  Related: MatchData#post_match.
 *
 */

VALUE
rb_reg_match_pre(VALUE match)
{
    VALUE str;
    struct re_registers *regs;

    if (NIL_P(match)) return Qnil;
    match_check(match);
    regs = RMATCH_REGS(match);
    if (BEG(0) == -1) return Qnil;
    str = rb_str_subseq(RMATCH(match)->str, 0, BEG(0));
    return str;
}


/*
 *  call-seq:
 *    post_match   -> str
 *
 *  Returns the substring of the target string from
 *  the end of the first match in +self+ (that is, <tt>self[0]</tt>)
 *  to the end of the string;
 *  equivalent to regexp global variable <tt>$'</tt>:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138: The Movie")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m[0]         # => "HX1138"
 *    m.post_match # => ": The Movie"\
 *
 *  Related: MatchData.pre_match.
 *
 */

VALUE
rb_reg_match_post(VALUE match)
{
    VALUE str;
    long pos;
    struct re_registers *regs;

    if (NIL_P(match)) return Qnil;
    match_check(match);
    regs = RMATCH_REGS(match);
    if (BEG(0) == -1) return Qnil;
    str = RMATCH(match)->str;
    pos = END(0);
    str = rb_str_subseq(str, pos, RSTRING_LEN(str) - pos);
    return str;
}

static int
match_last_index(VALUE match)
{
    int i;
    struct re_registers *regs;

    if (NIL_P(match)) return -1;
    match_check(match);
    regs = RMATCH_REGS(match);
    if (BEG(0) == -1) return -1;

    for (i=regs->num_regs-1; BEG(i) == -1 && i > 0; i--)
        ;
    return i;
}

VALUE
rb_reg_match_last(VALUE match)
{
    int i = match_last_index(match);
    if (i <= 0) return Qnil;
    struct re_registers *regs = RMATCH_REGS(match);
    return rb_str_subseq(RMATCH(match)->str, BEG(i), END(i) - BEG(i));
}

VALUE
rb_reg_last_defined(VALUE match)
{
    int i = match_last_index(match);
    if (i < 0) return Qnil;
    return RBOOL(i);
}

static VALUE
last_match_getter(ID _x, VALUE *_y)
{
    return rb_reg_last_match(rb_backref_get());
}

static VALUE
prematch_getter(ID _x, VALUE *_y)
{
    return rb_reg_match_pre(rb_backref_get());
}

static VALUE
postmatch_getter(ID _x, VALUE *_y)
{
    return rb_reg_match_post(rb_backref_get());
}

static VALUE
last_paren_match_getter(ID _x, VALUE *_y)
{
    return rb_reg_match_last(rb_backref_get());
}

static VALUE
match_array(VALUE match, int start)
{
    struct re_registers *regs;
    VALUE ary;
    VALUE target;
    int i;

    match_check(match);
    regs = RMATCH_REGS(match);
    ary = rb_ary_new2(regs->num_regs);
    target = RMATCH(match)->str;

    for (i=start; i<regs->num_regs; i++) {
        if (regs->beg[i] == -1) {
            rb_ary_push(ary, Qnil);
        }
        else {
            VALUE str = rb_str_subseq(target, regs->beg[i], regs->end[i]-regs->beg[i]);
            rb_ary_push(ary, str);
        }
    }
    return ary;
}


/*
 *  call-seq:
 *    to_a -> array
 *
 *  Returns the array of matches:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m.to_a # => ["HX1138", "H", "X", "113", "8"]
 *
 *  Related: MatchData#captures.
 *
 */

static VALUE
match_to_a(VALUE match)
{
    return match_array(match, 0);
}


/*
 *  call-seq:
 *    captures -> array
 *
 *  Returns the array of captures,
 *  which are all matches except <tt>m[0]</tt>:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m[0]       # => "HX1138"
 *    m.captures # => ["H", "X", "113", "8"]
 *
 *  Related: MatchData.to_a.
 *
 */
static VALUE
match_captures(VALUE match)
{
    return match_array(match, 1);
}

static int
name_to_backref_number(struct re_registers *regs, VALUE regexp, const char* name, const char* name_end)
{
    if (NIL_P(regexp)) return -1;
    return onig_name_to_backref_number(RREGEXP_PTR(regexp),
        (const unsigned char *)name, (const unsigned char *)name_end, regs);
}

#define NAME_TO_NUMBER(regs, re, name, name_ptr, name_end)	\
    (NIL_P(re) ? 0 : \
     !rb_enc_compatible(RREGEXP_SRC(re), (name)) ? 0 : \
     name_to_backref_number((regs), (re), (name_ptr), (name_end)))

static int
namev_to_backref_number(struct re_registers *regs, VALUE re, VALUE name)
{
    int num;

    if (SYMBOL_P(name)) {
        name = rb_sym2str(name);
    }
    else if (!RB_TYPE_P(name, T_STRING)) {
        return -1;
    }
    num = NAME_TO_NUMBER(regs, re, name,
                         RSTRING_PTR(name), RSTRING_END(name));
    if (num < 1) {
        name_to_backref_error(name);
    }
    return num;
}

static VALUE
match_ary_subseq(VALUE match, long beg, long len, VALUE result)
{
    long olen = RMATCH_REGS(match)->num_regs;
    long j, end = olen < beg+len ? olen : beg+len;
    if (NIL_P(result)) result = rb_ary_new_capa(len);
    if (len == 0) return result;

    for (j = beg; j < end; j++) {
        rb_ary_push(result, rb_reg_nth_match((int)j, match));
    }
    if (beg + len > j) {
        rb_ary_resize(result, RARRAY_LEN(result) + (beg + len) - j);
    }
    return result;
}

static VALUE
match_ary_aref(VALUE match, VALUE idx, VALUE result)
{
    long beg, len;
    int num_regs = RMATCH_REGS(match)->num_regs;

    /* check if idx is Range */
    switch (rb_range_beg_len(idx, &beg, &len, (long)num_regs, !NIL_P(result))) {
      case Qfalse:
        if (NIL_P(result)) return rb_reg_nth_match(NUM2INT(idx), match);
        rb_ary_push(result, rb_reg_nth_match(NUM2INT(idx), match));
        return result;
      case Qnil:
        return Qnil;
      default:
        return match_ary_subseq(match, beg, len, result);
    }
}

/*
 *  call-seq:
 *    matchdata[index] -> string or nil
 *    matchdata[start, length] -> array
 *    matchdata[range] -> array
 *    matchdata[name] -> string or nil
 *
 *  When arguments +index+, +start and +length+, or +range+ are given,
 *  returns match and captures in the style of Array#[]:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m[0] # => "HX1138"
 *    m[1, 2]  # => ["H", "X"]
 *    m[1..3]  # => ["H", "X", "113"]
 *    m[-3, 2] # => ["X", "113"]
 *
 *  When string or symbol argument +name+ is given,
 *  returns the matched substring for the given name:
 *
 *    m = /(?<foo>.)(.)(?<bar>.+)/.match("hoge")
 *    # => #<MatchData "hoge" foo:"h" bar:"ge">
 *    m['foo'] # => "h"
 *    m[:bar]  # => "ge"
 *
 *  If multiple captures have the same name, returns the last matched
 *  substring.
 *
 *    m = /(?<foo>.)(?<foo>.+)/.match("hoge")
 *    # => #<MatchData "hoge" foo:"h" foo:"oge">
 *    m[:foo] #=> "oge"
 *
 *    m = /\W(?<foo>.+)|\w(?<foo>.+)|(?<foo>.+)/.match("hoge")
 *    #<MatchData "hoge" foo:nil foo:"oge" foo:nil>
 *    m[:foo] #=> "oge"
 *
 */

static VALUE
match_aref(int argc, VALUE *argv, VALUE match)
{
    VALUE idx, length;

    match_check(match);
    rb_scan_args(argc, argv, "11", &idx, &length);

    if (NIL_P(length)) {
        if (FIXNUM_P(idx)) {
            return rb_reg_nth_match(FIX2INT(idx), match);
        }
        else {
            int num = namev_to_backref_number(RMATCH_REGS(match), RMATCH(match)->regexp, idx);
            if (num >= 0) {
                return rb_reg_nth_match(num, match);
            }
            else {
                return match_ary_aref(match, idx, Qnil);
            }
        }
    }
    else {
        long beg = NUM2LONG(idx);
        long len = NUM2LONG(length);
        long num_regs = RMATCH_REGS(match)->num_regs;
        if (len < 0) {
            return Qnil;
        }
        if (beg < 0) {
            beg += num_regs;
            if (beg < 0) return Qnil;
        }
        else if (beg > num_regs) {
            return Qnil;
        }
        if (beg+len > num_regs) {
            len = num_regs - beg;
        }
        return match_ary_subseq(match, beg, len, Qnil);
    }
}

/*
 *  call-seq:
 *    values_at(*indexes) -> array
 *
 *  Returns match and captures at the given +indexes+,
 *  which may include any mixture of:
 *
 *  - Integers.
 *  - Ranges.
 *  - Names (strings and symbols).
 *
 *
 *  Examples:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138: The Movie")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m.values_at(0, 2, -2) # => ["HX1138", "X", "113"]
 *    m.values_at(1..2, -1) # => ["H", "X", "8"]
 *
 *    m = /(?<a>\d+) *(?<op>[+\-*\/]) *(?<b>\d+)/.match("1 + 2")
 *    # => #<MatchData "1 + 2" a:"1" op:"+" b:"2">
 *    m.values_at(0, 1..2, :a, :b, :op)
 *    # => ["1 + 2", "1", "+", "1", "2", "+"]
 *
 */

static VALUE
match_values_at(int argc, VALUE *argv, VALUE match)
{
    VALUE result;
    int i;

    match_check(match);
    result = rb_ary_new2(argc);

    for (i=0; i<argc; i++) {
        if (FIXNUM_P(argv[i])) {
            rb_ary_push(result, rb_reg_nth_match(FIX2INT(argv[i]), match));
        }
        else {
            int num = namev_to_backref_number(RMATCH_REGS(match), RMATCH(match)->regexp, argv[i]);
            if (num >= 0) {
                rb_ary_push(result, rb_reg_nth_match(num, match));
            }
            else {
                match_ary_aref(match, argv[i], result);
            }
        }
    }
    return result;
}


/*
 *  call-seq:
 *    to_s -> string
 *
 *  Returns the matched string:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m.to_s # => "HX1138"
 *
 *    m = /(?<foo>.)(.)(?<bar>.+)/.match("hoge")
 *    # => #<MatchData "hoge" foo:"h" bar:"ge">
 *    m.to_s # => "hoge"
 *
 *  Related: MatchData.inspect.
 *
 */

static VALUE
match_to_s(VALUE match)
{
    VALUE str = rb_reg_last_match(match_check(match));

    if (NIL_P(str)) str = rb_str_new(0,0);
    return str;
}

static int
match_named_captures_iter(const OnigUChar *name, const OnigUChar *name_end,
        int back_num, int *back_refs, OnigRegex regex, void *arg)
{
    struct MEMO *memo = MEMO_CAST(arg);
    VALUE hash = memo->v1;
    VALUE match = memo->v2;
    long symbolize = memo->u3.state;

    VALUE key = rb_enc_str_new((const char *)name, name_end-name, regex->enc);

    if (symbolize > 0) {
        key = rb_str_intern(key);
    }

    VALUE value;

    int i;
    int found = 0;

    for (i = 0; i < back_num; i++) {
        value = rb_reg_nth_match(back_refs[i], match);
        if (RTEST(value)) {
            rb_hash_aset(hash, key, value);
            found = 1;
        }
    }

    if (found == 0) {
        rb_hash_aset(hash, key, Qnil);
    }

    return 0;
}

/*
 *  call-seq:
 *    named_captures(symbolize_names: false) -> hash
 *
 *  Returns a hash of the named captures;
 *  each key is a capture name; each value is its captured string or +nil+:
 *
 *    m = /(?<foo>.)(.)(?<bar>.+)/.match("hoge")
 *    # => #<MatchData "hoge" foo:"h" bar:"ge">
 *    m.named_captures # => {"foo"=>"h", "bar"=>"ge"}
 *
 *    m = /(?<a>.)(?<b>.)/.match("01")
 *    # => #<MatchData "01" a:"0" b:"1">
 *    m.named_captures #=> {"a" => "0", "b" => "1"}
 *
 *    m = /(?<a>.)(?<b>.)?/.match("0")
 *    # => #<MatchData "0" a:"0" b:nil>
 *    m.named_captures #=> {"a" => "0", "b" => nil}
 *
 *    m = /(?<a>.)(?<a>.)/.match("01")
 *    # => #<MatchData "01" a:"0" a:"1">
 *    m.named_captures #=> {"a" => "1"}
 *
 *  If keyword argument +symbolize_names+ is given
 *  a true value, the keys in the resulting hash are Symbols:
 *
 *    m = /(?<a>.)(?<a>.)/.match("01")
 *    # => #<MatchData "01" a:"0" a:"1">
 *    m.named_captures(symbolize_names: true) #=> {:a => "1"}
 *
 */

static VALUE
match_named_captures(int argc, VALUE *argv, VALUE match)
{
    VALUE hash;
    struct MEMO *memo;

    match_check(match);
    if (NIL_P(RMATCH(match)->regexp))
        return rb_hash_new();

    VALUE opt;
    VALUE symbolize_names = 0;

    rb_scan_args(argc, argv, "0:", &opt);

    if (!NIL_P(opt)) {
        static ID keyword_ids[1];

        VALUE symbolize_names_val;

        if (!keyword_ids[0]) {
            keyword_ids[0] = rb_intern_const("symbolize_names");
        }
        rb_get_kwargs(opt, keyword_ids, 0, 1, &symbolize_names_val);
        if (!UNDEF_P(symbolize_names_val) && RTEST(symbolize_names_val)) {
            symbolize_names = 1;
        }
    }

    hash = rb_hash_new();
    memo = MEMO_NEW(hash, match, symbolize_names);

    onig_foreach_name(RREGEXP(RMATCH(match)->regexp)->ptr, match_named_captures_iter, (void*)memo);

    return hash;
}

/*
 *  call-seq:
 *    deconstruct_keys(array_of_names) -> hash
 *
 *  Returns a hash of the named captures for the given names.
 *
 *    m = /(?<hours>\d{2}):(?<minutes>\d{2}):(?<seconds>\d{2})/.match("18:37:22")
 *    m.deconstruct_keys([:hours, :minutes]) # => {:hours => "18", :minutes => "37"}
 *    m.deconstruct_keys(nil) # => {:hours => "18", :minutes => "37", :seconds => "22"}
 *
 *  Returns an empty hash if no named captures were defined:
 *
 *    m = /(\d{2}):(\d{2}):(\d{2})/.match("18:37:22")
 *    m.deconstruct_keys(nil) # => {}
 *
 */
static VALUE
match_deconstruct_keys(VALUE match, VALUE keys)
{
    VALUE h;
    long i;

    match_check(match);

    if (NIL_P(RMATCH(match)->regexp)) {
        return rb_hash_new_with_size(0);
    }

    if (NIL_P(keys)) {
        h = rb_hash_new_with_size(onig_number_of_names(RREGEXP_PTR(RMATCH(match)->regexp)));

        struct MEMO *memo;
        memo = MEMO_NEW(h, match, 1);

        onig_foreach_name(RREGEXP_PTR(RMATCH(match)->regexp), match_named_captures_iter, (void*)memo);

        return h;
    }

    Check_Type(keys, T_ARRAY);

    if (onig_number_of_names(RREGEXP_PTR(RMATCH(match)->regexp)) < RARRAY_LEN(keys)) {
        return rb_hash_new_with_size(0);
    }

    h = rb_hash_new_with_size(RARRAY_LEN(keys));

    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE key = RARRAY_AREF(keys, i);
        VALUE name;

        Check_Type(key, T_SYMBOL);

        name = rb_sym2str(key);

        int num = NAME_TO_NUMBER(RMATCH_REGS(match), RMATCH(match)->regexp, RMATCH(match)->regexp,
                         RSTRING_PTR(name), RSTRING_END(name));

        if (num >= 0) {
            rb_hash_aset(h, key, rb_reg_nth_match(num, match));
        }
        else {
            return h;
        }
    }

    return h;
}

/*
 *  call-seq:
 *    string -> string
 *
 *  Returns the target string if it was frozen;
 *  otherwise, returns a frozen copy of the target string:
 *
 *    m = /(.)(.)(\d+)(\d)/.match("THX1138.")
 *    # => #<MatchData "HX1138" 1:"H" 2:"X" 3:"113" 4:"8">
 *    m.string # => "THX1138."
 *
 */

static VALUE
match_string(VALUE match)
{
    match_check(match);
    return RMATCH(match)->str;	/* str is frozen */
}

struct backref_name_tag {
    const UChar *name;
    long len;
};

static int
match_inspect_name_iter(const OnigUChar *name, const OnigUChar *name_end,
          int back_num, int *back_refs, OnigRegex regex, void *arg0)
{
    struct backref_name_tag *arg = (struct backref_name_tag *)arg0;
    int i;

    for (i = 0; i < back_num; i++) {
        arg[back_refs[i]].name = name;
        arg[back_refs[i]].len = name_end - name;
    }
    return 0;
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+:
 *
 *    m = /.$/.match("foo")
 *    # => #<MatchData "o">
 *    m.inspect # => "#<MatchData \"o\">"
 *
 *    m = /(.)(.)(.)/.match("foo")
 *    # => #<MatchData "foo" 1:"f" 2:"o" 3:"o">
 *    m.inspect # => "#<MatchData \"foo\" 1:\"f\" 2:\"o\
 *
 *    m = /(.)(.)?(.)/.match("fo")
 *    # => #<MatchData "fo" 1:"f" 2:nil 3:"o">
 *    m.inspect # => "#<MatchData \"fo\" 1:\"f\" 2:nil 3:\"o\">"
 *
 *  Related: MatchData#to_s.
 */

static VALUE
match_inspect(VALUE match)
{
    VALUE cname = rb_class_path(rb_obj_class(match));
    VALUE str;
    int i;
    struct re_registers *regs = RMATCH_REGS(match);
    int num_regs = regs->num_regs;
    struct backref_name_tag *names;
    VALUE regexp = RMATCH(match)->regexp;

    if (regexp == 0) {
        return rb_sprintf("#<%"PRIsVALUE":%p>", cname, (void*)match);
    }
    else if (NIL_P(regexp)) {
        return rb_sprintf("#<%"PRIsVALUE": %"PRIsVALUE">",
                          cname, rb_reg_nth_match(0, match));
    }

    names = ALLOCA_N(struct backref_name_tag, num_regs);
    MEMZERO(names, struct backref_name_tag, num_regs);

    onig_foreach_name(RREGEXP_PTR(regexp),
            match_inspect_name_iter, names);

    str = rb_str_buf_new2("#<");
    rb_str_append(str, cname);

    for (i = 0; i < num_regs; i++) {
        VALUE v;
        rb_str_buf_cat2(str, " ");
        if (0 < i) {
            if (names[i].name)
                rb_str_buf_cat(str, (const char *)names[i].name, names[i].len);
            else {
                rb_str_catf(str, "%d", i);
            }
            rb_str_buf_cat2(str, ":");
        }
        v = rb_reg_nth_match(i, match);
        if (NIL_P(v))
            rb_str_buf_cat2(str, "nil");
        else
            rb_str_buf_append(str, rb_str_inspect(v));
    }
    rb_str_buf_cat2(str, ">");

    return str;
}

VALUE rb_cRegexp;

static int
read_escaped_byte(const char **pp, const char *end, onig_errmsg_buffer err)
{
    const char *p = *pp;
    int code;
    int meta_prefix = 0, ctrl_prefix = 0;
    size_t len;

    if (p == end || *p++ != '\\') {
        errcpy(err, "too short escaped multibyte character");
        return -1;
    }

again:
    if (p == end) {
        errcpy(err, "too short escape sequence");
        return -1;
    }
    switch (*p++) {
      case '\\': code = '\\'; break;
      case 'n': code = '\n'; break;
      case 't': code = '\t'; break;
      case 'r': code = '\r'; break;
      case 'f': code = '\f'; break;
      case 'v': code = '\013'; break;
      case 'a': code = '\007'; break;
      case 'e': code = '\033'; break;

      /* \OOO */
      case '0': case '1': case '2': case '3':
      case '4': case '5': case '6': case '7':
        p--;
        code = scan_oct(p, end < p+3 ? end-p : 3, &len);
        p += len;
        break;

      case 'x': /* \xHH */
        code = scan_hex(p, end < p+2 ? end-p : 2, &len);
        if (len < 1) {
            errcpy(err, "invalid hex escape");
            return -1;
        }
        p += len;
        break;

      case 'M': /* \M-X, \M-\C-X, \M-\cX */
        if (meta_prefix) {
            errcpy(err, "duplicate meta escape");
            return -1;
        }
        meta_prefix = 1;
        if (p+1 < end && *p++ == '-' && (*p & 0x80) == 0) {
            if (*p == '\\') {
                p++;
                goto again;
            }
            else {
                code = *p++;
                break;
            }
        }
        errcpy(err, "too short meta escape");
        return -1;

      case 'C': /* \C-X, \C-\M-X */
        if (p == end || *p++ != '-') {
            errcpy(err, "too short control escape");
            return -1;
        }
      case 'c': /* \cX, \c\M-X */
        if (ctrl_prefix) {
            errcpy(err, "duplicate control escape");
            return -1;
        }
        ctrl_prefix = 1;
        if (p < end && (*p & 0x80) == 0) {
            if (*p == '\\') {
                p++;
                goto again;
            }
            else {
                code = *p++;
                break;
            }
        }
        errcpy(err, "too short control escape");
        return -1;

      default:
        errcpy(err, "unexpected escape sequence");
        return -1;
    }
    if (code < 0 || 0xff < code) {
        errcpy(err, "invalid escape code");
        return -1;
    }

    if (ctrl_prefix)
        code &= 0x1f;
    if (meta_prefix)
        code |= 0x80;

    *pp = p;
    return code;
}

static int
unescape_escaped_nonascii(const char **pp, const char *end, rb_encoding *enc,
        VALUE buf, rb_encoding **encp, onig_errmsg_buffer err)
{
    const char *p = *pp;
    int chmaxlen = rb_enc_mbmaxlen(enc);
    unsigned char *area = ALLOCA_N(unsigned char, chmaxlen);
    char *chbuf = (char *)area;
    int chlen = 0;
    int byte;
    int l;

    memset(chbuf, 0, chmaxlen);

    byte = read_escaped_byte(&p, end, err);
    if (byte == -1) {
        return -1;
    }

    area[chlen++] = byte;
    while (chlen < chmaxlen &&
           MBCLEN_NEEDMORE_P(rb_enc_precise_mbclen(chbuf, chbuf+chlen, enc))) {
        byte = read_escaped_byte(&p, end, err);
        if (byte == -1) {
            return -1;
        }
        area[chlen++] = byte;
    }

    l = rb_enc_precise_mbclen(chbuf, chbuf+chlen, enc);
    if (MBCLEN_INVALID_P(l)) {
        errcpy(err, "invalid multibyte escape");
        return -1;
    }
    if (1 < chlen || (area[0] & 0x80)) {
        rb_str_buf_cat(buf, chbuf, chlen);

        if (*encp == 0)
            *encp = enc;
        else if (*encp != enc) {
            errcpy(err, "escaped non ASCII character in UTF-8 regexp");
            return -1;
        }
    }
    else {
        char escbuf[5];
        snprintf(escbuf, sizeof(escbuf), "\\x%02X", area[0]&0xff);
        rb_str_buf_cat(buf, escbuf, 4);
    }
    *pp = p;
    return 0;
}

static int
check_unicode_range(unsigned long code, onig_errmsg_buffer err)
{
    if ((0xd800 <= code && code <= 0xdfff) || /* Surrogates */
        0x10ffff < code) {
        errcpy(err, "invalid Unicode range");
        return -1;
    }
    return 0;
}

static int
append_utf8(unsigned long uv,
        VALUE buf, rb_encoding **encp, onig_errmsg_buffer err)
{
    if (check_unicode_range(uv, err) != 0)
        return -1;
    if (uv < 0x80) {
        char escbuf[5];
        snprintf(escbuf, sizeof(escbuf), "\\x%02X", (int)uv);
        rb_str_buf_cat(buf, escbuf, 4);
    }
    else {
        int len;
        char utf8buf[6];
        len = rb_uv_to_utf8(utf8buf, uv);
        rb_str_buf_cat(buf, utf8buf, len);

        if (*encp == 0)
            *encp = rb_utf8_encoding();
        else if (*encp != rb_utf8_encoding()) {
            errcpy(err, "UTF-8 character in non UTF-8 regexp");
            return -1;
        }
    }
    return 0;
}

static int
unescape_unicode_list(const char **pp, const char *end,
        VALUE buf, rb_encoding **encp, onig_errmsg_buffer err)
{
    const char *p = *pp;
    int has_unicode = 0;
    unsigned long code;
    size_t len;

    while (p < end && ISSPACE(*p)) p++;

    while (1) {
        code = ruby_scan_hex(p, end-p, &len);
        if (len == 0)
            break;
        if (6 < len) { /* max 10FFFF */
            errcpy(err, "invalid Unicode range");
            return -1;
        }
        p += len;
        if (append_utf8(code, buf, encp, err) != 0)
            return -1;
        has_unicode = 1;

        while (p < end && ISSPACE(*p)) p++;
    }

    if (has_unicode == 0) {
        errcpy(err, "invalid Unicode list");
        return -1;
    }

    *pp = p;

    return 0;
}

static int
unescape_unicode_bmp(const char **pp, const char *end,
        VALUE buf, rb_encoding **encp, onig_errmsg_buffer err)
{
    const char *p = *pp;
    size_t len;
    unsigned long code;

    if (end < p+4) {
        errcpy(err, "invalid Unicode escape");
        return -1;
    }
    code = ruby_scan_hex(p, 4, &len);
    if (len != 4) {
        errcpy(err, "invalid Unicode escape");
        return -1;
    }
    if (append_utf8(code, buf, encp, err) != 0)
        return -1;
    *pp = p + 4;
    return 0;
}

static int
unescape_nonascii0(const char **pp, const char *end, rb_encoding *enc,
        VALUE buf, rb_encoding **encp, int *has_property,
        onig_errmsg_buffer err, int options, int recurse)
{
    const char *p = *pp;
    unsigned char c;
    char smallbuf[2];
    int in_char_class = 0;
    int parens = 1; /* ignored unless recurse is true */
    int extended_mode = options & ONIG_OPTION_EXTEND;

begin_scan:
    while (p < end) {
        int chlen = rb_enc_precise_mbclen(p, end, enc);
        if (!MBCLEN_CHARFOUND_P(chlen)) {
          invalid_multibyte:
            errcpy(err, "invalid multibyte character");
            return -1;
        }
        chlen = MBCLEN_CHARFOUND_LEN(chlen);
        if (1 < chlen || (*p & 0x80)) {
          multibyte:
            rb_str_buf_cat(buf, p, chlen);
            p += chlen;
            if (*encp == 0)
                *encp = enc;
            else if (*encp != enc) {
                errcpy(err, "non ASCII character in UTF-8 regexp");
                return -1;
            }
            continue;
        }

        switch (c = *p++) {
          case '\\':
            if (p == end) {
                errcpy(err, "too short escape sequence");
                return -1;
            }
            chlen = rb_enc_precise_mbclen(p, end, enc);
            if (!MBCLEN_CHARFOUND_P(chlen)) {
                goto invalid_multibyte;
            }
            if ((chlen = MBCLEN_CHARFOUND_LEN(chlen)) > 1) {
                /* include the previous backslash */
                --p;
                ++chlen;
                goto multibyte;
            }
            switch (c = *p++) {
              case '1': case '2': case '3':
              case '4': case '5': case '6': case '7': /* \O, \OO, \OOO or backref */
                {
                    size_t len = end-(p-1), octlen;
                    if (ruby_scan_oct(p-1, len < 3 ? len : 3, &octlen) <= 0177) {
                        /* backref or 7bit octal.
                           no need to unescape anyway.
                           re-escaping may break backref */
                        goto escape_asis;
                    }
                }
                /* xxx: How about more than 199 subexpressions? */

              case '0': /* \0, \0O, \0OO */

              case 'x': /* \xHH */
              case 'c': /* \cX, \c\M-X */
              case 'C': /* \C-X, \C-\M-X */
              case 'M': /* \M-X, \M-\C-X, \M-\cX */
                p = p-2;
                if (rb_is_usascii_enc(enc)) {
                    const char *pbeg = p;
                    int byte = read_escaped_byte(&p, end, err);
                    if (byte == -1) return -1;
                    c = byte;
                    rb_str_buf_cat(buf, pbeg, p-pbeg);
                }
                else {
                    if (unescape_escaped_nonascii(&p, end, enc, buf, encp, err) != 0)
                        return -1;
                }
                break;

              case 'u':
                if (p == end) {
                    errcpy(err, "too short escape sequence");
                    return -1;
                }
                if (*p == '{') {
                    /* \u{H HH HHH HHHH HHHHH HHHHHH ...} */
                    p++;
                    if (unescape_unicode_list(&p, end, buf, encp, err) != 0)
                        return -1;
                    if (p == end || *p++ != '}') {
                        errcpy(err, "invalid Unicode list");
                        return -1;
                    }
                    break;
                }
                else {
                    /* \uHHHH */
                    if (unescape_unicode_bmp(&p, end, buf, encp, err) != 0)
                        return -1;
                    break;
                }

              case 'p': /* \p{Hiragana} */
              case 'P':
                if (!*encp) {
                    *has_property = 1;
                }
                goto escape_asis;

              default: /* \n, \\, \d, \9, etc. */
escape_asis:
                smallbuf[0] = '\\';
                smallbuf[1] = c;
                rb_str_buf_cat(buf, smallbuf, 2);
                break;
            }
            break;

          case '#':
            if (extended_mode && !in_char_class) {
                /* consume and ignore comment in extended regexp */
                while ((p < end) && ((c = *p++) != '\n')) {
                    if ((c & 0x80) && !*encp && enc == rb_utf8_encoding()) {
                        *encp = enc;
                    }
                }
                break;
            }
            rb_str_buf_cat(buf, (char *)&c, 1);
            break;
          case '[':
            in_char_class++;
            rb_str_buf_cat(buf, (char *)&c, 1);
            break;
          case ']':
            if (in_char_class) {
                in_char_class--;
            }
            rb_str_buf_cat(buf, (char *)&c, 1);
            break;
          case ')':
            rb_str_buf_cat(buf, (char *)&c, 1);
            if (!in_char_class && recurse) {
                if (--parens == 0) {
                    *pp = p;
                    return 0;
                }
            }
            break;
          case '(':
            if (!in_char_class && p + 1 < end && *p == '?') {
                if (*(p+1) == '#') {
                    /* (?# is comment inside any regexp, and content inside should be ignored */
                    const char *orig_p = p;
                    int cont = 1;

                    while (cont && (p < end)) {
                        switch (c = *p++) {
                          default:
                            if (!(c & 0x80)) break;
                            if (!*encp && enc == rb_utf8_encoding()) {
                                *encp = enc;
                            }
                            --p;
                            /* fallthrough */
                          case '\\':
                            chlen = rb_enc_precise_mbclen(p, end, enc);
                            if (!MBCLEN_CHARFOUND_P(chlen)) {
                                goto invalid_multibyte;
                            }
                            p += MBCLEN_CHARFOUND_LEN(chlen);
                            break;
                          case ')':
                            cont = 0;
                            break;
                        }
                    }

                    if (cont) {
                        /* unterminated (?#, rewind so it is syntax error */
                        p = orig_p;
                        c = '(';
                        rb_str_buf_cat(buf, (char *)&c, 1);
                    }
                    break;
                }
                else {
                    /* potential change of extended option */
                    int invert = 0;
                    int local_extend = 0;
                    const char *s;

                    if (recurse) {
                        parens++;
                    }

                    for (s = p+1; s < end; s++) {
                        switch(*s) {
                          case 'x':
                            local_extend = invert ? -1 : 1;
                            break;
                          case '-':
                            invert = 1;
                            break;
                          case ':':
                          case ')':
                            if (local_extend == 0 ||
                                (local_extend == -1 && !extended_mode) ||
                                (local_extend == 1 && extended_mode)) {
                                /* no changes to extended flag */
                                goto fallthrough;
                            }

                            if (*s == ':') {
                                /* change extended flag until ')' */
                                int local_options = options;
                                if (local_extend == 1) {
                                    local_options |= ONIG_OPTION_EXTEND;
                                }
                                else {
                                    local_options &= ~ONIG_OPTION_EXTEND;
                                }

                                rb_str_buf_cat(buf, (char *)&c, 1);
                                int ret = unescape_nonascii0(&p, end, enc, buf, encp,
                                                             has_property, err,
                                                             local_options, 1);
                                if (ret < 0) return ret;
                                goto begin_scan;
                            }
                            else {
                                /* change extended flag for rest of expression */
                                extended_mode = local_extend == 1;
                                goto fallthrough;
                            }
                          case 'i':
                          case 'm':
                          case 'a':
                          case 'd':
                          case 'u':
                            /* other option flags, ignored during scanning */
                            break;
                          default:
                            /* other character, no extended flag change*/
                            goto fallthrough;
                        }
                    }
                }
            }
            else if (!in_char_class && recurse) {
                parens++;
            }
            /* FALLTHROUGH */
          default:
fallthrough:
            rb_str_buf_cat(buf, (char *)&c, 1);
            break;
        }
    }

    if (recurse) {
        *pp = p;
    }
    return 0;
}

static int
unescape_nonascii(const char *p, const char *end, rb_encoding *enc,
        VALUE buf, rb_encoding **encp, int *has_property,
        onig_errmsg_buffer err, int options)
{
    return unescape_nonascii0(&p, end, enc, buf, encp, has_property,
                              err, options, 0);
}

static VALUE
rb_reg_preprocess(const char *p, const char *end, rb_encoding *enc,
        rb_encoding **fixed_enc, onig_errmsg_buffer err, int options)
{
    VALUE buf;
    int has_property = 0;

    buf = rb_str_buf_new(0);

    if (rb_enc_asciicompat(enc))
        *fixed_enc = 0;
    else {
        *fixed_enc = enc;
        rb_enc_associate(buf, enc);
    }

    if (unescape_nonascii(p, end, enc, buf, fixed_enc, &has_property, err, options) != 0)
        return Qnil;

    if (has_property && !*fixed_enc) {
        *fixed_enc = enc;
    }

    if (*fixed_enc) {
        rb_enc_associate(buf, *fixed_enc);
    }

    return buf;
}

VALUE
rb_reg_check_preprocess(VALUE str)
{
    rb_encoding *fixed_enc = 0;
    onig_errmsg_buffer err = "";
    VALUE buf;
    char *p, *end;
    rb_encoding *enc;

    StringValue(str);
    p = RSTRING_PTR(str);
    end = p + RSTRING_LEN(str);
    enc = rb_enc_get(str);

    buf = rb_reg_preprocess(p, end, enc, &fixed_enc, err, 0);
    RB_GC_GUARD(str);

    if (NIL_P(buf)) {
        return rb_reg_error_desc(str, 0, err);
    }
    return Qnil;
}

static VALUE
rb_reg_preprocess_dregexp(VALUE ary, int options)
{
    rb_encoding *fixed_enc = 0;
    rb_encoding *regexp_enc = 0;
    onig_errmsg_buffer err = "";
    int i;
    VALUE result = 0;
    rb_encoding *ascii8bit = rb_ascii8bit_encoding();

    if (RARRAY_LEN(ary) == 0) {
        rb_raise(rb_eArgError, "no arguments given");
    }

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        VALUE str = RARRAY_AREF(ary, i);
        VALUE buf;
        char *p, *end;
        rb_encoding *src_enc;

        src_enc = rb_enc_get(str);
        if (options & ARG_ENCODING_NONE &&
                src_enc != ascii8bit) {
            if (str_coderange(str) != ENC_CODERANGE_7BIT)
                rb_raise(rb_eRegexpError, "/.../n has a non escaped non ASCII character in non ASCII-8BIT script");
            else
                src_enc = ascii8bit;
        }

        StringValue(str);
        p = RSTRING_PTR(str);
        end = p + RSTRING_LEN(str);

        buf = rb_reg_preprocess(p, end, src_enc, &fixed_enc, err, options);

        if (NIL_P(buf))
            rb_raise(rb_eArgError, "%s", err);

        if (fixed_enc != 0) {
            if (regexp_enc != 0 && regexp_enc != fixed_enc) {
                rb_raise(rb_eRegexpError, "encoding mismatch in dynamic regexp : %s and %s",
                         rb_enc_name(regexp_enc), rb_enc_name(fixed_enc));
            }
            regexp_enc = fixed_enc;
        }

        if (!result)
            result = rb_str_new3(str);
        else
            rb_str_buf_append(result, str);
    }
    if (regexp_enc) {
        rb_enc_associate(result, regexp_enc);
    }

    return result;
}

static void
rb_reg_initialize_check(VALUE obj)
{
    rb_check_frozen(obj);
    if (RREGEXP_PTR(obj)) {
        rb_raise(rb_eTypeError, "already initialized regexp");
    }
}

static int
rb_reg_initialize(VALUE obj, const char *s, long len, rb_encoding *enc,
                  int options, onig_errmsg_buffer err,
                  const char *sourcefile, int sourceline)
{
    struct RRegexp *re = RREGEXP(obj);
    VALUE unescaped;
    rb_encoding *fixed_enc = 0;
    rb_encoding *a_enc = rb_ascii8bit_encoding();

    rb_reg_initialize_check(obj);

    if (rb_enc_dummy_p(enc)) {
        errcpy(err, "can't make regexp with dummy encoding");
        return -1;
    }

    unescaped = rb_reg_preprocess(s, s+len, enc, &fixed_enc, err, options);
    if (NIL_P(unescaped))
        return -1;

    if (fixed_enc) {
        if ((fixed_enc != enc && (options & ARG_ENCODING_FIXED)) ||
            (fixed_enc != a_enc && (options & ARG_ENCODING_NONE))) {
            errcpy(err, "incompatible character encoding");
            return -1;
        }
        if (fixed_enc != a_enc) {
            options |= ARG_ENCODING_FIXED;
            enc = fixed_enc;
        }
    }
    else if (!(options & ARG_ENCODING_FIXED)) {
       enc = rb_usascii_encoding();
    }

    rb_enc_associate((VALUE)re, enc);
    if ((options & ARG_ENCODING_FIXED) || fixed_enc) {
        re->basic.flags |= KCODE_FIXED;
    }
    if (options & ARG_ENCODING_NONE) {
        re->basic.flags |= REG_ENCODING_NONE;
    }

    re->ptr = make_regexp(RSTRING_PTR(unescaped), RSTRING_LEN(unescaped), enc,
                          options & ARG_REG_OPTION_MASK, err,
                          sourcefile, sourceline);
    if (!re->ptr) return -1;
    RB_GC_GUARD(unescaped);
    return 0;
}

static void
reg_set_source(VALUE reg, VALUE str, rb_encoding *enc)
{
    rb_encoding *regenc = rb_enc_get(reg);
    if (regenc != enc) {
        str = rb_enc_associate(rb_str_dup(str), enc = regenc);
    }
    RB_OBJ_WRITE(reg, &RREGEXP(reg)->src, rb_fstring(str));
}

static int
rb_reg_initialize_str(VALUE obj, VALUE str, int options, onig_errmsg_buffer err,
        const char *sourcefile, int sourceline)
{
    int ret;
    rb_encoding *str_enc = rb_enc_get(str), *enc = str_enc;
    if (options & ARG_ENCODING_NONE) {
        rb_encoding *ascii8bit = rb_ascii8bit_encoding();
        if (enc != ascii8bit) {
            if (str_coderange(str) != ENC_CODERANGE_7BIT) {
                errcpy(err, "/.../n has a non escaped non ASCII character in non ASCII-8BIT script");
                return -1;
            }
            enc = ascii8bit;
        }
    }
    ret = rb_reg_initialize(obj, RSTRING_PTR(str), RSTRING_LEN(str), enc,
                            options, err, sourcefile, sourceline);
    if (ret == 0) reg_set_source(obj, str, str_enc);
    return ret;
}

static VALUE
rb_reg_s_alloc(VALUE klass)
{
    NEWOBJ_OF(re, struct RRegexp, klass, T_REGEXP | (RGENGC_WB_PROTECTED_REGEXP ? FL_WB_PROTECTED : 0), sizeof(struct RRegexp), 0);

    re->ptr = 0;
    RB_OBJ_WRITE(re, &re->src, 0);
    re->usecnt = 0;

    return (VALUE)re;
}

VALUE
rb_reg_alloc(void)
{
    return rb_reg_s_alloc(rb_cRegexp);
}

VALUE
rb_reg_new_str(VALUE s, int options)
{
    return rb_reg_init_str(rb_reg_alloc(), s, options);
}

VALUE
rb_reg_init_str(VALUE re, VALUE s, int options)
{
    onig_errmsg_buffer err = "";

    if (rb_reg_initialize_str(re, s, options, err, NULL, 0) != 0) {
        rb_reg_raise_str(s, options, err);
    }

    return re;
}

static VALUE
rb_reg_init_str_enc(VALUE re, VALUE s, rb_encoding *enc, int options)
{
    onig_errmsg_buffer err = "";

    if (rb_reg_initialize(re, RSTRING_PTR(s), RSTRING_LEN(s),
                          enc, options, err, NULL, 0) != 0) {
        rb_reg_raise_str(s, options, err);
    }
    reg_set_source(re, s, enc);

    return re;
}

VALUE
rb_reg_new_ary(VALUE ary, int opt)
{
    VALUE re = rb_reg_new_str(rb_reg_preprocess_dregexp(ary, opt), opt);
    rb_obj_freeze(re);
    return re;
}

VALUE
rb_enc_reg_new(const char *s, long len, rb_encoding *enc, int options)
{
    VALUE re = rb_reg_alloc();
    onig_errmsg_buffer err = "";

    if (rb_reg_initialize(re, s, len, enc, options, err, NULL, 0) != 0) {
        rb_enc_reg_raise(s, len, enc, options, err);
    }
    RB_OBJ_WRITE(re, &RREGEXP(re)->src, rb_fstring(rb_enc_str_new(s, len, enc)));

    return re;
}

VALUE
rb_reg_new(const char *s, long len, int options)
{
    return rb_enc_reg_new(s, len, rb_ascii8bit_encoding(), options);
}

VALUE
rb_reg_compile(VALUE str, int options, const char *sourcefile, int sourceline)
{
    VALUE re = rb_reg_alloc();
    onig_errmsg_buffer err = "";

    if (!str) str = rb_str_new(0,0);
    if (rb_reg_initialize_str(re, str, options, err, sourcefile, sourceline) != 0) {
        rb_set_errinfo(rb_reg_error_desc(str, options, err));
        return Qnil;
    }
    rb_obj_freeze(re);
    return re;
}

static VALUE reg_cache;

VALUE
rb_reg_regcomp(VALUE str)
{
    if (reg_cache && RREGEXP_SRC_LEN(reg_cache) == RSTRING_LEN(str)
        && ENCODING_GET(reg_cache) == ENCODING_GET(str)
        && memcmp(RREGEXP_SRC_PTR(reg_cache), RSTRING_PTR(str), RSTRING_LEN(str)) == 0)
        return reg_cache;

    return reg_cache = rb_reg_new_str(str, 0);
}

static st_index_t reg_hash(VALUE re);
/*
 *  call-seq:
 *    hash -> integer
 *
 *  Returns the integer hash value for +self+.
 *
 *  Related: Object#hash.
 *
 */

VALUE
rb_reg_hash(VALUE re)
{
    st_index_t hashval = reg_hash(re);
    return ST2FIX(hashval);
}

static st_index_t
reg_hash(VALUE re)
{
    st_index_t hashval;

    rb_reg_check(re);
    hashval = RREGEXP_PTR(re)->options;
    hashval = rb_hash_uint(hashval, rb_memhash(RREGEXP_SRC_PTR(re), RREGEXP_SRC_LEN(re)));
    return rb_hash_end(hashval);
}


/*
 *  call-seq:
 *    regexp == object -> true or false
 *
 *  Returns +true+ if +object+ is another \Regexp whose pattern,
 *  flags, and encoding are the same as +self+, +false+ otherwise:
 *
 *    /foo/ == Regexp.new('foo')                          # => true
 *    /foo/ == /foo/i                                     # => false
 *    /foo/ == Regexp.new('food')                         # => false
 *    /foo/ == Regexp.new("abc".force_encoding("euc-jp")) # => false
 *
 */

VALUE
rb_reg_equal(VALUE re1, VALUE re2)
{
    if (re1 == re2) return Qtrue;
    if (!RB_TYPE_P(re2, T_REGEXP)) return Qfalse;
    rb_reg_check(re1); rb_reg_check(re2);
    if (FL_TEST(re1, KCODE_FIXED) != FL_TEST(re2, KCODE_FIXED)) return Qfalse;
    if (RREGEXP_PTR(re1)->options != RREGEXP_PTR(re2)->options) return Qfalse;
    if (RREGEXP_SRC_LEN(re1) != RREGEXP_SRC_LEN(re2)) return Qfalse;
    if (ENCODING_GET(re1) != ENCODING_GET(re2)) return Qfalse;
    return RBOOL(memcmp(RREGEXP_SRC_PTR(re1), RREGEXP_SRC_PTR(re2), RREGEXP_SRC_LEN(re1)) == 0);
}

/*
 *  call-seq:
 *    hash -> integer
 *
 *  Returns the integer hash value for +self+,
 *  based on the target string, regexp, match, and captures.
 *
 *  See also Object#hash.
 *
 */

static VALUE
match_hash(VALUE match)
{
    const struct re_registers *regs;
    st_index_t hashval;

    match_check(match);
    hashval = rb_hash_start(rb_str_hash(RMATCH(match)->str));
    hashval = rb_hash_uint(hashval, reg_hash(match_regexp(match)));
    regs = RMATCH_REGS(match);
    hashval = rb_hash_uint(hashval, regs->num_regs);
    hashval = rb_hash_uint(hashval, rb_memhash(regs->beg, regs->num_regs * sizeof(*regs->beg)));
    hashval = rb_hash_uint(hashval, rb_memhash(regs->end, regs->num_regs * sizeof(*regs->end)));
    hashval = rb_hash_end(hashval);
    return ST2FIX(hashval);
}

/*
 *  call-seq:
 *    matchdata == object -> true or false
 *
 *  Returns +true+ if +object+ is another \MatchData object
 *  whose target string, regexp, match, and captures
 *  are the same as +self+, +false+ otherwise.
 */

static VALUE
match_equal(VALUE match1, VALUE match2)
{
    const struct re_registers *regs1, *regs2;

    if (match1 == match2) return Qtrue;
    if (!RB_TYPE_P(match2, T_MATCH)) return Qfalse;
    if (!RMATCH(match1)->regexp || !RMATCH(match2)->regexp) return Qfalse;
    if (!rb_str_equal(RMATCH(match1)->str, RMATCH(match2)->str)) return Qfalse;
    if (!rb_reg_equal(match_regexp(match1), match_regexp(match2))) return Qfalse;
    regs1 = RMATCH_REGS(match1);
    regs2 = RMATCH_REGS(match2);
    if (regs1->num_regs != regs2->num_regs) return Qfalse;
    if (memcmp(regs1->beg, regs2->beg, regs1->num_regs * sizeof(*regs1->beg))) return Qfalse;
    if (memcmp(regs1->end, regs2->end, regs1->num_regs * sizeof(*regs1->end))) return Qfalse;
    return Qtrue;
}

static VALUE
reg_operand(VALUE s, int check)
{
    if (SYMBOL_P(s)) {
        return rb_sym2str(s);
    }
    else if (RB_TYPE_P(s, T_STRING)) {
        return s;
    }
    else {
        return check ? rb_str_to_str(s) : rb_check_string_type(s);
    }
}

static long
reg_match_pos(VALUE re, VALUE *strp, long pos, VALUE* set_match)
{
    VALUE str = *strp;

    if (NIL_P(str)) {
        rb_backref_set(Qnil);
        return -1;
    }
    *strp = str = reg_operand(str, TRUE);
    if (pos != 0) {
        if (pos < 0) {
            VALUE l = rb_str_length(str);
            pos += NUM2INT(l);
            if (pos < 0) {
                return pos;
            }
        }
        pos = rb_str_offset(str, pos);
    }
    return rb_reg_search_set_match(re, str, pos, 0, 1, set_match);
}

/*
 *  call-seq:
 *    regexp =~ string -> integer or nil
 *
 *  Returns the integer index (in characters) of the first match
 *  for +self+ and +string+, or +nil+ if none;
 *  also sets the
 *  {rdoc-ref:Regexp global variables}[rdoc-ref:Regexp@Global+Variables]:
 *
 *    /at/ =~ 'input data' # => 7
 *    $~                   # => #<MatchData "at">
 *    /ax/ =~ 'input data' # => nil
 *    $~                   # => nil
 *
 *  Assigns named captures to local variables of the same names
 *  if and only if +self+:
 *
 *  - Is a regexp literal;
 *    see {Regexp Literals}[rdoc-ref:literals.rdoc@Regexp+Literals].
 *  - Does not contain interpolations;
 *    see {Regexp interpolation}[rdoc-ref:Regexp@Interpolation+Mode].
 *  - Is at the left of the expression.
 *
 *  Example:
 *
 *    /(?<lhs>\w+)\s*=\s*(?<rhs>\w+)/ =~ '  x = y  '
 *    p lhs # => "x"
 *    p rhs # => "y"
 *
 *  Assigns +nil+ if not matched:
 *
 *    /(?<lhs>\w+)\s*=\s*(?<rhs>\w+)/ =~ '  x = '
 *    p lhs # => nil
 *    p rhs # => nil
 *
 *  Does not make local variable assignments if +self+ is not a regexp literal:
 *
 *    r = /(?<foo>\w+)\s*=\s*(?<foo>\w+)/
 *    r =~ '  x = y  '
 *    p foo # Undefined local variable
 *    p bar # Undefined local variable
 *
 *  The assignment does not occur if the regexp is not at the left:
 *
 *    '  x = y  ' =~ /(?<foo>\w+)\s*=\s*(?<foo>\w+)/
 *    p foo, foo # Undefined local variables
 *
 *  A regexp interpolation, <tt>#{}</tt>, also disables
 *  the assignment:
 *
 *    r = /(?<foo>\w+)/
 *    /(?<foo>\w+)\s*=\s*#{r}/ =~ 'x = y'
 *    p foo # Undefined local variable
 *
 */

VALUE
rb_reg_match(VALUE re, VALUE str)
{
    long pos = reg_match_pos(re, &str, 0, NULL);
    if (pos < 0) return Qnil;
    pos = rb_str_sublen(str, pos);
    return LONG2FIX(pos);
}

/*
 *  call-seq:
 *    regexp === string -> true or false
 *
 *  Returns +true+ if +self+ finds a match in +string+:
 *
 *    /^[a-z]*$/ === 'HELLO' # => false
 *    /^[A-Z]*$/ === 'HELLO' # => true
 *
 *  This method is called in case statements:
 *
 *    s = 'HELLO'
 *    case s
 *    when /\A[a-z]*\z/; print "Lower case\n"
 *    when /\A[A-Z]*\z/; print "Upper case\n"
 *    else               print "Mixed case\n"
 *    end # => "Upper case"
 *
 */

static VALUE
rb_reg_eqq(VALUE re, VALUE str)
{
    long start;

    str = reg_operand(str, FALSE);
    if (NIL_P(str)) {
        rb_backref_set(Qnil);
        return Qfalse;
    }
    start = rb_reg_search(re, str, 0, 0);
    return RBOOL(start >= 0);
}


/*
 *  call-seq:
 *    ~ rxp -> integer or nil
 *
 *  Equivalent to <tt><i>rxp</i> =~ $_</tt>:
 *
 *    $_ = "input data"
 *    ~ /at/ # => 7
 *
 */

VALUE
rb_reg_match2(VALUE re)
{
    long start;
    VALUE line = rb_lastline_get();

    if (!RB_TYPE_P(line, T_STRING)) {
        rb_backref_set(Qnil);
        return Qnil;
    }

    start = rb_reg_search(re, line, 0, 0);
    if (start < 0) {
        return Qnil;
    }
    start = rb_str_sublen(line, start);
    return LONG2FIX(start);
}


/*
 *  call-seq:
 *    match(string, offset = 0) -> matchdata or nil
 *    match(string, offset = 0) {|matchdata| ... } -> object
 *
 *  With no block given, returns the MatchData object
 *  that describes the match, if any, or +nil+ if none;
 *  the search begins at the given character +offset+ in +string+:
 *
 *    /abra/.match('abracadabra')      # => #<MatchData "abra">
 *    /abra/.match('abracadabra', 4)   # => #<MatchData "abra">
 *    /abra/.match('abracadabra', 8)   # => nil
 *    /abra/.match('abracadabra', 800) # => nil
 *
 *    string = "\u{5d0 5d1 5e8 5d0}cadabra"
 *    /abra/.match(string, 7)          #=> #<MatchData "abra">
 *    /abra/.match(string, 8)          #=> nil
 *    /abra/.match(string.b, 8)        #=> #<MatchData "abra">
 *
 *  With a block given, calls the block if and only if a match is found;
 *  returns the block's value:
 *
 *    /abra/.match('abracadabra') {|matchdata| p matchdata }
 *    # => #<MatchData "abra">
 *    /abra/.match('abracadabra', 4) {|matchdata| p matchdata }
 *    # => #<MatchData "abra">
 *    /abra/.match('abracadabra', 8) {|matchdata| p matchdata }
 *    # => nil
 *    /abra/.match('abracadabra', 8) {|marchdata| fail 'Cannot happen' }
 *    # => nil
 *
 *  Output (from the first two blocks above):
 *
 *    #<MatchData "abra">
 *    #<MatchData "abra">
 *
 *     /(.)(.)(.)/.match("abc")[2] # => "b"
 *     /(.)(.)/.match("abc", 1)[2] # => "c"
 *
 */

static VALUE
rb_reg_match_m(int argc, VALUE *argv, VALUE re)
{
    VALUE result = Qnil, str, initpos;
    long pos;

    if (rb_scan_args(argc, argv, "11", &str, &initpos) == 2) {
        pos = NUM2LONG(initpos);
    }
    else {
        pos = 0;
    }

    pos = reg_match_pos(re, &str, pos, &result);
    if (pos < 0) {
        rb_backref_set(Qnil);
        return Qnil;
    }
    rb_match_busy(result);
    if (!NIL_P(result) && rb_block_given_p()) {
        return rb_yield(result);
    }
    return result;
}

/*
 *  call-seq:
 *    match?(string) -> true or false
 *    match?(string, offset = 0) -> true or false
 *
 *  Returns <code>true</code> or <code>false</code> to indicate whether the
 *  regexp is matched or not without updating $~ and other related variables.
 *  If the second parameter is present, it specifies the position in the string
 *  to begin the search.
 *
 *     /R.../.match?("Ruby")    # => true
 *     /R.../.match?("Ruby", 1) # => false
 *     /P.../.match?("Ruby")    # => false
 *     $&                       # => nil
 */

static VALUE
rb_reg_match_m_p(int argc, VALUE *argv, VALUE re)
{
    long pos = rb_check_arity(argc, 1, 2) > 1 ? NUM2LONG(argv[1]) : 0;
    return rb_reg_match_p(re, argv[0], pos);
}

VALUE
rb_reg_match_p(VALUE re, VALUE str, long pos)
{
    if (NIL_P(str)) return Qfalse;
    str = SYMBOL_P(str) ? rb_sym2str(str) : StringValue(str);
    if (pos) {
        if (pos < 0) {
            pos += NUM2LONG(rb_str_length(str));
            if (pos < 0) return Qfalse;
        }
        if (pos > 0) {
            long len = 1;
            const char *beg = rb_str_subpos(str, pos, &len);
            if (!beg) return Qfalse;
            pos = beg - RSTRING_PTR(str);
        }
    }

    struct reg_onig_search_args args = {
        .pos = pos,
        .range = RSTRING_LEN(str),
    };

    return rb_reg_onig_match(re, str, reg_onig_search, &args, NULL) == ONIG_MISMATCH ? Qfalse : Qtrue;
}

/*
 * Document-method: compile
 *
 * Alias for Regexp.new
 */

static int
str_to_option(VALUE str)
{
    int flag = 0;
    const char *ptr;
    long len;
    str = rb_check_string_type(str);
    if (NIL_P(str)) return -1;
    RSTRING_GETMEM(str, ptr, len);
    for (long i = 0; i < len; ++i) {
        int f = char_to_option(ptr[i]);
        if (!f) {
            rb_raise(rb_eArgError, "unknown regexp option: %"PRIsVALUE, str);
        }
        flag |= f;
    }
    return flag;
}

static void
set_timeout(rb_hrtime_t *hrt, VALUE timeout)
{
    double timeout_d = NIL_P(timeout) ? 0.0 : NUM2DBL(timeout);
    if (!NIL_P(timeout) && timeout_d <= 0) {
        rb_raise(rb_eArgError, "invalid timeout: %"PRIsVALUE, timeout);
    }
    double2hrtime(hrt, timeout_d);
}

static VALUE
reg_copy(VALUE copy, VALUE orig)
{
    int r;
    regex_t *re;

    rb_reg_initialize_check(copy);
    if ((r = onig_reg_copy(&re, RREGEXP_PTR(orig))) != 0) {
        /* ONIGERR_MEMORY only */
        rb_raise(rb_eRegexpError, "%s", onig_error_code_to_format(r));
    }
    RREGEXP_PTR(copy) = re;
    RB_OBJ_WRITE(copy, &RREGEXP(copy)->src, RREGEXP(orig)->src);
    RREGEXP_PTR(copy)->timelimit = RREGEXP_PTR(orig)->timelimit;
    rb_enc_copy(copy, orig);
    FL_SET_RAW(copy, FL_TEST_RAW(orig, KCODE_FIXED|REG_ENCODING_NONE));

    return copy;
}

struct reg_init_args {
    VALUE str;
    VALUE timeout;
    rb_encoding *enc;
    int flags;
};

static VALUE reg_extract_args(int argc, VALUE *argv, struct reg_init_args *args);
static VALUE reg_init_args(VALUE self, VALUE str, rb_encoding *enc, int flags);
void rb_warn_deprecated_to_remove(const char *removal, const char *fmt, const char *suggest, ...);

/*
 *  call-seq:
 *    Regexp.new(string, options = 0, timeout: nil) -> regexp
 *    Regexp.new(regexp, timeout: nil) -> regexp
 *
 *  With argument +string+ given, returns a new regexp with the given string
 *  and options:
 *
 *    r = Regexp.new('foo') # => /foo/
 *    r.source              # => "foo"
 *    r.options             # => 0
 *
 *  Optional argument +options+ is one of the following:
 *
 *  - A String of options:
 *
 *      Regexp.new('foo', 'i')  # => /foo/i
 *      Regexp.new('foo', 'im') # => /foo/im
 *
 *  - The bit-wise OR of one or more of the constants
 *    Regexp::EXTENDED, Regexp::IGNORECASE, Regexp::MULTILINE, and
 *    Regexp::NOENCODING:
 *
 *      Regexp.new('foo', Regexp::IGNORECASE) # => /foo/i
 *      Regexp.new('foo', Regexp::EXTENDED)   # => /foo/x
 *      Regexp.new('foo', Regexp::MULTILINE)  # => /foo/m
 *      Regexp.new('foo', Regexp::NOENCODING)  # => /foo/n
 *      flags = Regexp::IGNORECASE | Regexp::EXTENDED |  Regexp::MULTILINE
 *      Regexp.new('foo', flags)              # => /foo/mix
 *
 *  - +nil+ or +false+, which is ignored.
 *  - Any other truthy value, in which case the regexp will be
 *    case-insensitive.
 *
 *  If optional keyword argument +timeout+ is given,
 *  its float value overrides the timeout interval for the class,
 *  Regexp.timeout.
 *  If +nil+ is passed as +timeout, it uses the timeout interval
 *  for the class, Regexp.timeout.
 *
 *  With argument +regexp+ given, returns a new regexp. The source,
 *  options, timeout are the same as +regexp+. +options+ and +n_flag+
 *  arguments are ineffective.  The timeout can be overridden by
 *  +timeout+ keyword.
 *
 *      options = Regexp::MULTILINE
 *      r = Regexp.new('foo', options, timeout: 1.1) # => /foo/m
 *      r2 = Regexp.new(r)                           # => /foo/m
 *      r2.timeout                                   # => 1.1
 *      r3 = Regexp.new(r, timeout: 3.14)            # => /foo/m
 *      r3.timeout                                   # => 3.14
 *
 */

static VALUE
rb_reg_initialize_m(int argc, VALUE *argv, VALUE self)
{
    struct reg_init_args args;
    VALUE re = reg_extract_args(argc, argv, &args);

    if (NIL_P(re)) {
        reg_init_args(self, args.str, args.enc, args.flags);
    }
    else {
        reg_copy(self, re);
    }

    set_timeout(&RREGEXP_PTR(self)->timelimit, args.timeout);

    return self;
}

static VALUE
reg_extract_args(int argc, VALUE *argv, struct reg_init_args *args)
{
    int flags = 0;
    rb_encoding *enc = 0;
    VALUE str, src, opts = Qundef, kwargs;
    VALUE re = Qnil;

    rb_scan_args(argc, argv, "11:", &src, &opts, &kwargs);

    args->timeout = Qnil;
    if (!NIL_P(kwargs)) {
        static ID keywords[1];
        if (!keywords[0]) {
            keywords[0] = rb_intern_const("timeout");
        }
        rb_get_kwargs(kwargs, keywords, 0, 1, &args->timeout);
    }

    if (RB_TYPE_P(src, T_REGEXP)) {
        re = src;

        if (!NIL_P(opts)) {
            rb_warn("flags ignored");
        }
        rb_reg_check(re);
        flags = rb_reg_options(re);
        str = RREGEXP_SRC(re);
    }
    else {
        if (!NIL_P(opts)) {
            int f;
            if (FIXNUM_P(opts)) flags = FIX2INT(opts);
            else if ((f = str_to_option(opts)) >= 0) flags = f;
            else if (rb_bool_expected(opts, "ignorecase", FALSE))
                flags = ONIG_OPTION_IGNORECASE;
        }
        str = StringValue(src);
    }
    args->str = str;
    args->enc = enc;
    args->flags = flags;
    return re;
}

static VALUE
reg_init_args(VALUE self, VALUE str, rb_encoding *enc, int flags)
{
    if (enc && rb_enc_get(str) != enc)
        rb_reg_init_str_enc(self, str, enc, flags);
    else
        rb_reg_init_str(self, str, flags);
    return self;
}

VALUE
rb_reg_quote(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);
    char *s, *send, *t;
    VALUE tmp;
    int c, clen;
    int ascii_only = rb_enc_str_asciionly_p(str);

    s = RSTRING_PTR(str);
    send = s + RSTRING_LEN(str);
    while (s < send) {
        c = rb_enc_ascget(s, send, &clen, enc);
        if (c == -1) {
            s += mbclen(s, send, enc);
            continue;
        }
        switch (c) {
          case '[': case ']': case '{': case '}':
          case '(': case ')': case '|': case '-':
          case '*': case '.': case '\\':
          case '?': case '+': case '^': case '$':
          case ' ': case '#':
          case '\t': case '\f': case '\v': case '\n': case '\r':
            goto meta_found;
        }
        s += clen;
    }
    tmp = rb_str_new3(str);
    if (ascii_only) {
        rb_enc_associate(tmp, rb_usascii_encoding());
    }
    return tmp;

  meta_found:
    tmp = rb_str_new(0, RSTRING_LEN(str)*2);
    if (ascii_only) {
        rb_enc_associate(tmp, rb_usascii_encoding());
    }
    else {
        rb_enc_copy(tmp, str);
    }
    t = RSTRING_PTR(tmp);
    /* copy upto metacharacter */
    const char *p = RSTRING_PTR(str);
    memcpy(t, p, s - p);
    t += s - p;

    while (s < send) {
        c = rb_enc_ascget(s, send, &clen, enc);
        if (c == -1) {
            int n = mbclen(s, send, enc);

            while (n--)
                *t++ = *s++;
            continue;
        }
        s += clen;
        switch (c) {
          case '[': case ']': case '{': case '}':
          case '(': case ')': case '|': case '-':
          case '*': case '.': case '\\':
          case '?': case '+': case '^': case '$':
          case '#':
            t += rb_enc_mbcput('\\', t, enc);
            break;
          case ' ':
            t += rb_enc_mbcput('\\', t, enc);
            t += rb_enc_mbcput(' ', t, enc);
            continue;
          case '\t':
            t += rb_enc_mbcput('\\', t, enc);
            t += rb_enc_mbcput('t', t, enc);
            continue;
          case '\n':
            t += rb_enc_mbcput('\\', t, enc);
            t += rb_enc_mbcput('n', t, enc);
            continue;
          case '\r':
            t += rb_enc_mbcput('\\', t, enc);
            t += rb_enc_mbcput('r', t, enc);
            continue;
          case '\f':
            t += rb_enc_mbcput('\\', t, enc);
            t += rb_enc_mbcput('f', t, enc);
            continue;
          case '\v':
            t += rb_enc_mbcput('\\', t, enc);
            t += rb_enc_mbcput('v', t, enc);
            continue;
        }
        t += rb_enc_mbcput(c, t, enc);
    }
    rb_str_resize(tmp, t - RSTRING_PTR(tmp));
    return tmp;
}


/*
 *  call-seq:
 *    Regexp.escape(string) -> new_string
 *
 *  Returns a new string that escapes any characters
 *  that have special meaning in a regular expression:
 *
 *    s = Regexp.escape('\*?{}.')      # => "\\\\\\*\\?\\{\\}\\."
 *
 *  For any string +s+, this call returns a MatchData object:
 *
 *    r = Regexp.new(Regexp.escape(s)) # => /\\\\\\\*\\\?\\\{\\\}\\\./
 *    r.match(s)                       # => #<MatchData "\\\\\\*\\?\\{\\}\\.">
 *
 */

static VALUE
rb_reg_s_quote(VALUE c, VALUE str)
{
    return rb_reg_quote(reg_operand(str, TRUE));
}

int
rb_reg_options(VALUE re)
{
    int options;

    rb_reg_check(re);
    options = RREGEXP_PTR(re)->options & ARG_REG_OPTION_MASK;
    if (RBASIC(re)->flags & KCODE_FIXED) options |= ARG_ENCODING_FIXED;
    if (RBASIC(re)->flags & REG_ENCODING_NONE) options |= ARG_ENCODING_NONE;
    return options;
}

static VALUE
rb_check_regexp_type(VALUE re)
{
    return rb_check_convert_type(re, T_REGEXP, "Regexp", "to_regexp");
}

/*
 *  call-seq:
 *    Regexp.try_convert(object) -> regexp or nil
 *
 *  Returns +object+ if it is a regexp:
 *
 *    Regexp.try_convert(/re/) # => /re/
 *
 *  Otherwise if +object+ responds to <tt>:to_regexp</tt>,
 *  calls <tt>object.to_regexp</tt> and returns the result.
 *
 *  Returns +nil+ if +object+ does not respond to <tt>:to_regexp</tt>.
 *
 *    Regexp.try_convert('re') # => nil
 *
 *  Raises an exception unless <tt>object.to_regexp</tt> returns a regexp.
 *
 */
static VALUE
rb_reg_s_try_convert(VALUE dummy, VALUE re)
{
    return rb_check_regexp_type(re);
}

static VALUE
rb_reg_s_union(VALUE self, VALUE args0)
{
    long argc = RARRAY_LEN(args0);

    if (argc == 0) {
        VALUE args[1];
        args[0] = rb_str_new2("(?!)");
        return rb_class_new_instance(1, args, rb_cRegexp);
    }
    else if (argc == 1) {
        VALUE arg = rb_ary_entry(args0, 0);
        VALUE re = rb_check_regexp_type(arg);
        if (!NIL_P(re))
            return re;
        else {
            VALUE quoted;
            quoted = rb_reg_s_quote(Qnil, arg);
            return rb_reg_new_str(quoted, 0);
        }
    }
    else {
        int i;
        VALUE source = rb_str_buf_new(0);
        rb_encoding *result_enc;

        int has_asciionly = 0;
        rb_encoding *has_ascii_compat_fixed = 0;
        rb_encoding *has_ascii_incompat = 0;

        for (i = 0; i < argc; i++) {
            volatile VALUE v;
            VALUE e = rb_ary_entry(args0, i);

            if (0 < i)
                rb_str_buf_cat_ascii(source, "|");

            v = rb_check_regexp_type(e);
            if (!NIL_P(v)) {
                rb_encoding *enc = rb_enc_get(v);
                if (!rb_enc_asciicompat(enc)) {
                    if (!has_ascii_incompat)
                        has_ascii_incompat = enc;
                    else if (has_ascii_incompat != enc)
                        rb_raise(rb_eArgError, "incompatible encodings: %s and %s",
                            rb_enc_name(has_ascii_incompat), rb_enc_name(enc));
                }
                else if (rb_reg_fixed_encoding_p(v)) {
                    if (!has_ascii_compat_fixed)
                        has_ascii_compat_fixed = enc;
                    else if (has_ascii_compat_fixed != enc)
                        rb_raise(rb_eArgError, "incompatible encodings: %s and %s",
                            rb_enc_name(has_ascii_compat_fixed), rb_enc_name(enc));
                }
                else {
                    has_asciionly = 1;
                }
                v = rb_reg_str_with_term(v, -1);
            }
            else {
                rb_encoding *enc;
                StringValue(e);
                enc = rb_enc_get(e);
                if (!rb_enc_asciicompat(enc)) {
                    if (!has_ascii_incompat)
                        has_ascii_incompat = enc;
                    else if (has_ascii_incompat != enc)
                        rb_raise(rb_eArgError, "incompatible encodings: %s and %s",
                            rb_enc_name(has_ascii_incompat), rb_enc_name(enc));
                }
                else if (rb_enc_str_asciionly_p(e)) {
                    has_asciionly = 1;
                }
                else {
                    if (!has_ascii_compat_fixed)
                        has_ascii_compat_fixed = enc;
                    else if (has_ascii_compat_fixed != enc)
                        rb_raise(rb_eArgError, "incompatible encodings: %s and %s",
                            rb_enc_name(has_ascii_compat_fixed), rb_enc_name(enc));
                }
                v = rb_reg_s_quote(Qnil, e);
            }
            if (has_ascii_incompat) {
                if (has_asciionly) {
                    rb_raise(rb_eArgError, "ASCII incompatible encoding: %s",
                        rb_enc_name(has_ascii_incompat));
                }
                if (has_ascii_compat_fixed) {
                    rb_raise(rb_eArgError, "incompatible encodings: %s and %s",
                        rb_enc_name(has_ascii_incompat), rb_enc_name(has_ascii_compat_fixed));
                }
            }

            if (i == 0) {
                rb_enc_copy(source, v);
            }
            rb_str_append(source, v);
        }

        if (has_ascii_incompat) {
            result_enc = has_ascii_incompat;
        }
        else if (has_ascii_compat_fixed) {
            result_enc = has_ascii_compat_fixed;
        }
        else {
            result_enc = rb_ascii8bit_encoding();
        }

        rb_enc_associate(source, result_enc);
        return rb_class_new_instance(1, &source, rb_cRegexp);
    }
}

/*
 *  call-seq:
 *    Regexp.union(*patterns) -> regexp
 *    Regexp.union(array_of_patterns) -> regexp
 *
 *  Returns a new regexp that is the union of the given patterns:
 *
 *    r = Regexp.union(%w[cat dog])      # => /cat|dog/
 *    r.match('cat')      # => #<MatchData "cat">
 *    r.match('dog')      # => #<MatchData "dog">
 *    r.match('cog')      # => nil
 *
 *  For each pattern that is a string, <tt>Regexp.new(pattern)</tt> is used:
 *
 *    Regexp.union('penzance')             # => /penzance/
 *    Regexp.union('a+b*c')                # => /a\+b\*c/
 *    Regexp.union('skiing', 'sledding')   # => /skiing|sledding/
 *    Regexp.union(['skiing', 'sledding']) # => /skiing|sledding/
 *
 *  For each pattern that is a regexp, it is used as is,
 *  including its flags:
 *
 *    Regexp.union(/foo/i, /bar/m, /baz/x)
 *    # => /(?i-mx:foo)|(?m-ix:bar)|(?x-mi:baz)/
 *    Regexp.union([/foo/i, /bar/m, /baz/x])
 *    # => /(?i-mx:foo)|(?m-ix:bar)|(?x-mi:baz)/
 *
 *  With no arguments, returns <tt>/(?!)/</tt>:
 *
 *    Regexp.union # => /(?!)/
 *
 *  If any regexp pattern contains captures, the behavior is unspecified.
 *
 */
static VALUE
rb_reg_s_union_m(VALUE self, VALUE args)
{
    VALUE v;
    if (RARRAY_LEN(args) == 1 &&
        !NIL_P(v = rb_check_array_type(rb_ary_entry(args, 0)))) {
        return rb_reg_s_union(self, v);
    }
    return rb_reg_s_union(self, args);
}

/*
 *  call-seq:
 *    Regexp.linear_time?(re)
 *    Regexp.linear_time?(string, options = 0)
 *
 *  Returns +true+ if matching against <tt>re</tt> can be
 *  done in linear time to the input string.
 *
 *    Regexp.linear_time?(/re/) # => true
 *
 *  Note that this is a property of the ruby interpreter, not of the argument
 *  regular expression.  Identical regexp can or cannot run in linear time
 *  depending on your ruby binary.  Neither forward nor backward compatibility
 *  is guaranteed about the return value of this method.  Our current algorithm
 *  is (*1) but this is subject to change in the future.  Alternative
 *  implementations can also behave differently.  They might always return
 *  false for everything.
 *
 *  (*1): https://doi.org/10.1109/SP40001.2021.00032
 *
 */
static VALUE
rb_reg_s_linear_time_p(int argc, VALUE *argv, VALUE self)
{
    struct reg_init_args args;
    VALUE re = reg_extract_args(argc, argv, &args);

    if (NIL_P(re)) {
        re = reg_init_args(rb_reg_alloc(), args.str, args.enc, args.flags);
    }

    return RBOOL(onig_check_linear_time(RREGEXP_PTR(re)));
}

/* :nodoc: */
static VALUE
rb_reg_init_copy(VALUE copy, VALUE re)
{
    if (!OBJ_INIT_COPY(copy, re)) return copy;
    rb_reg_check(re);
    return reg_copy(copy, re);
}

VALUE
rb_reg_regsub(VALUE str, VALUE src, struct re_registers *regs, VALUE regexp)
{
    VALUE val = 0;
    char *p, *s, *e;
    int no, clen;
    rb_encoding *str_enc = rb_enc_get(str);
    rb_encoding *src_enc = rb_enc_get(src);
    int acompat = rb_enc_asciicompat(str_enc);
    long n;
#define ASCGET(s,e,cl) (acompat ? (*(cl)=1,ISASCII((s)[0])?(s)[0]:-1) : rb_enc_ascget((s), (e), (cl), str_enc))

    RSTRING_GETMEM(str, s, n);
    p = s;
    e = s + n;

    while (s < e) {
        int c = ASCGET(s, e, &clen);
        char *ss;

        if (c == -1) {
            s += mbclen(s, e, str_enc);
            continue;
        }
        ss = s;
        s += clen;

        if (c != '\\' || s == e) continue;

        if (!val) {
            val = rb_str_buf_new(ss-p);
        }
        rb_enc_str_buf_cat(val, p, ss-p, str_enc);

        c = ASCGET(s, e, &clen);
        if (c == -1) {
            s += mbclen(s, e, str_enc);
            rb_enc_str_buf_cat(val, ss, s-ss, str_enc);
            p = s;
            continue;
        }
        s += clen;

        p = s;
        switch (c) {
          case '1': case '2': case '3': case '4':
          case '5': case '6': case '7': case '8': case '9':
            if (!NIL_P(regexp) && onig_noname_group_capture_is_active(RREGEXP_PTR(regexp))) {
                no = c - '0';
            }
            else {
                continue;
            }
            break;

          case 'k':
            if (s < e && ASCGET(s, e, &clen) == '<') {
                char *name, *name_end;

                name_end = name = s + clen;
                while (name_end < e) {
                    c = ASCGET(name_end, e, &clen);
                    if (c == '>') break;
                    name_end += c == -1 ? mbclen(name_end, e, str_enc) : clen;
                }
                if (name_end < e) {
                    VALUE n = rb_str_subseq(str, (long)(name - RSTRING_PTR(str)),
                                            (long)(name_end - name));
                    if ((no = NAME_TO_NUMBER(regs, regexp, n, name, name_end)) < 1) {
                        name_to_backref_error(n);
                    }
                    p = s = name_end + clen;
                    break;
                }
                else {
                    rb_raise(rb_eRuntimeError, "invalid group name reference format");
                }
            }

            rb_enc_str_buf_cat(val, ss, s-ss, str_enc);
            continue;

          case '0':
          case '&':
            no = 0;
            break;

          case '`':
            rb_enc_str_buf_cat(val, RSTRING_PTR(src), BEG(0), src_enc);
            continue;

          case '\'':
            rb_enc_str_buf_cat(val, RSTRING_PTR(src)+END(0), RSTRING_LEN(src)-END(0), src_enc);
            continue;

          case '+':
            no = regs->num_regs-1;
            while (BEG(no) == -1 && no > 0) no--;
            if (no == 0) continue;
            break;

          case '\\':
            rb_enc_str_buf_cat(val, s-clen, clen, str_enc);
            continue;

          default:
            rb_enc_str_buf_cat(val, ss, s-ss, str_enc);
            continue;
        }

        if (no >= 0) {
            if (no >= regs->num_regs) continue;
            if (BEG(no) == -1) continue;
            rb_enc_str_buf_cat(val, RSTRING_PTR(src)+BEG(no), END(no)-BEG(no), src_enc);
        }
    }

    if (!val) return str;
    if (p < e) {
        rb_enc_str_buf_cat(val, p, e-p, str_enc);
    }

    return val;
}

static VALUE
ignorecase_getter(ID _x, VALUE *_y)
{
    rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "variable $= is no longer effective");
    return Qfalse;
}

static void
ignorecase_setter(VALUE val, ID id, VALUE *_)
{
    rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "variable $= is no longer effective; ignored");
}

static VALUE
match_getter(void)
{
    VALUE match = rb_backref_get();

    if (NIL_P(match)) return Qnil;
    rb_match_busy(match);
    return match;
}

static VALUE
get_LAST_MATCH_INFO(ID _x, VALUE *_y)
{
    return match_getter();
}

static void
match_setter(VALUE val, ID _x, VALUE *_y)
{
    if (!NIL_P(val)) {
        Check_Type(val, T_MATCH);
    }
    rb_backref_set(val);
}

/*
 *  call-seq:
 *    Regexp.last_match -> matchdata or nil
 *    Regexp.last_match(n) -> string or nil
 *    Regexp.last_match(name) -> string or nil
 *
 *  With no argument, returns the value of <tt>$!</tt>,
 *  which is the result of the most recent pattern match
 *  (see {Regexp global variables}[rdoc-ref:Regexp@Global+Variables]):
 *
 *    /c(.)t/ =~ 'cat'  # => 0
 *    Regexp.last_match # => #<MatchData "cat" 1:"a">
 *    /a/ =~ 'foo'      # => nil
 *    Regexp.last_match # => nil
 *
 *  With non-negative integer argument +n+, returns the _n_th field in the
 *  matchdata, if any, or nil if none:
 *
 *    /c(.)t/ =~ 'cat'     # => 0
 *    Regexp.last_match(0) # => "cat"
 *    Regexp.last_match(1) # => "a"
 *    Regexp.last_match(2) # => nil
 *
 *  With negative integer argument +n+, counts backwards from the last field:
 *
 *    Regexp.last_match(-1)       # => "a"
 *
 *  With string or symbol argument +name+,
 *  returns the string value for the named capture, if any:
 *
 *    /(?<lhs>\w+)\s*=\s*(?<rhs>\w+)/ =~ 'var = val'
 *    Regexp.last_match        # => #<MatchData "var = val" lhs:"var"rhs:"val">
 *    Regexp.last_match(:lhs)  # => "var"
 *    Regexp.last_match('rhs') # => "val"
 *    Regexp.last_match('foo') # Raises IndexError.
 *
 */

static VALUE
rb_reg_s_last_match(int argc, VALUE *argv, VALUE _)
{
    if (rb_check_arity(argc, 0, 1) == 1) {
        VALUE match = rb_backref_get();
        int n;
        if (NIL_P(match)) return Qnil;
        n = match_backref_number(match, argv[0]);
        return rb_reg_nth_match(n, match);
    }
    return match_getter();
}

static void
re_warn(const char *s)
{
    rb_warn("%s", s);
}

// This function is periodically called during regexp matching
bool
rb_reg_timeout_p(regex_t *reg, void *end_time_)
{
    rb_hrtime_t *end_time = (rb_hrtime_t *)end_time_;

    if (*end_time == 0) {
        // This is the first time to check interrupts;
        // just measure the current time and determine the end time
        // if timeout is set.
        rb_hrtime_t timelimit = reg->timelimit;

        if (!timelimit) {
            // no per-object timeout.
            timelimit = rb_reg_match_time_limit;
        }

        if (timelimit) {
            *end_time = rb_hrtime_add(timelimit, rb_hrtime_now());
        }
        else {
            // no timeout is set
            *end_time = RB_HRTIME_MAX;
        }
    }
    else {
        if (*end_time < rb_hrtime_now()) {
            // Timeout has exceeded
            return true;
        }
    }

    return false;
}

void
rb_reg_raise_timeout(void)
{
    rb_raise(rb_eRegexpTimeoutError, "regexp match timeout");
}

/*
 *  call-seq:
 *     Regexp.timeout  -> float or nil
 *
 *  It returns the current default timeout interval for Regexp matching in second.
 *  +nil+ means no default timeout configuration.
 */

static VALUE
rb_reg_s_timeout_get(VALUE dummy)
{
    double d = hrtime2double(rb_reg_match_time_limit);
    if (d == 0.0) return Qnil;
    return DBL2NUM(d);
}

/*
 *  call-seq:
 *     Regexp.timeout = float or nil
 *
 *  It sets the default timeout interval for Regexp matching in second.
 *  +nil+ means no default timeout configuration.
 *  This configuration is process-global. If you want to set timeout for
 *  each Regexp, use +timeout+ keyword for <code>Regexp.new</code>.
 *
 *     Regexp.timeout = 1
 *     /^a*b?a*$/ =~ "a" * 100000 + "x" #=> regexp match timeout (RuntimeError)
 */

static VALUE
rb_reg_s_timeout_set(VALUE dummy, VALUE timeout)
{
    rb_ractor_ensure_main_ractor("can not access Regexp.timeout from non-main Ractors");

    set_timeout(&rb_reg_match_time_limit, timeout);

    return timeout;
}

/*
 *  call-seq:
 *     rxp.timeout  -> float or nil
 *
 *  It returns the timeout interval for Regexp matching in second.
 *  +nil+ means no default timeout configuration.
 *
 *  This configuration is per-object. The global configuration set by
 *  Regexp.timeout= is ignored if per-object configuration is set.
 *
 *     re = Regexp.new("^a*b?a*$", timeout: 1)
 *     re.timeout               #=> 1.0
 *     re =~ "a" * 100000 + "x" #=> regexp match timeout (RuntimeError)
 */

static VALUE
rb_reg_timeout_get(VALUE re)
{
    rb_reg_check(re);
    double d = hrtime2double(RREGEXP_PTR(re)->timelimit);
    if (d == 0.0) return Qnil;
    return DBL2NUM(d);
}

/*
 *  Document-class: RegexpError
 *
 *  Raised when given an invalid regexp expression.
 *
 *     Regexp.new("?")
 *
 *  <em>raises the exception:</em>
 *
 *     RegexpError: target of repeat operator is not specified: /?/
 */

/*
 *  Document-class: Regexp
 *
 *  :include: doc/_regexp.rdoc
 */

void
Init_Regexp(void)
{
    rb_eRegexpError = rb_define_class("RegexpError", rb_eStandardError);

    onigenc_set_default_encoding(ONIG_ENCODING_ASCII);
    onig_set_warn_func(re_warn);
    onig_set_verb_warn_func(re_warn);

    rb_define_virtual_variable("$~", get_LAST_MATCH_INFO, match_setter);
    rb_define_virtual_variable("$&", last_match_getter, 0);
    rb_define_virtual_variable("$`", prematch_getter, 0);
    rb_define_virtual_variable("$'", postmatch_getter, 0);
    rb_define_virtual_variable("$+", last_paren_match_getter, 0);

    rb_gvar_ractor_local("$~");
    rb_gvar_ractor_local("$&");
    rb_gvar_ractor_local("$`");
    rb_gvar_ractor_local("$'");
    rb_gvar_ractor_local("$+");

    rb_define_virtual_variable("$=", ignorecase_getter, ignorecase_setter);

    rb_cRegexp = rb_define_class("Regexp", rb_cObject);
    rb_define_alloc_func(rb_cRegexp, rb_reg_s_alloc);
    rb_define_singleton_method(rb_cRegexp, "compile", rb_class_new_instance_pass_kw, -1);
    rb_define_singleton_method(rb_cRegexp, "quote", rb_reg_s_quote, 1);
    rb_define_singleton_method(rb_cRegexp, "escape", rb_reg_s_quote, 1);
    rb_define_singleton_method(rb_cRegexp, "union", rb_reg_s_union_m, -2);
    rb_define_singleton_method(rb_cRegexp, "last_match", rb_reg_s_last_match, -1);
    rb_define_singleton_method(rb_cRegexp, "try_convert", rb_reg_s_try_convert, 1);
    rb_define_singleton_method(rb_cRegexp, "linear_time?", rb_reg_s_linear_time_p, -1);

    rb_define_method(rb_cRegexp, "initialize", rb_reg_initialize_m, -1);
    rb_define_method(rb_cRegexp, "initialize_copy", rb_reg_init_copy, 1);
    rb_define_method(rb_cRegexp, "hash", rb_reg_hash, 0);
    rb_define_method(rb_cRegexp, "eql?", rb_reg_equal, 1);
    rb_define_method(rb_cRegexp, "==", rb_reg_equal, 1);
    rb_define_method(rb_cRegexp, "=~", rb_reg_match, 1);
    rb_define_method(rb_cRegexp, "===", rb_reg_eqq, 1);
    rb_define_method(rb_cRegexp, "~", rb_reg_match2, 0);
    rb_define_method(rb_cRegexp, "match", rb_reg_match_m, -1);
    rb_define_method(rb_cRegexp, "match?", rb_reg_match_m_p, -1);
    rb_define_method(rb_cRegexp, "to_s", rb_reg_to_s, 0);
    rb_define_method(rb_cRegexp, "inspect", rb_reg_inspect, 0);
    rb_define_method(rb_cRegexp, "source", rb_reg_source, 0);
    rb_define_method(rb_cRegexp, "casefold?", rb_reg_casefold_p, 0);
    rb_define_method(rb_cRegexp, "options", rb_reg_options_m, 0);
    rb_define_method(rb_cRegexp, "encoding", rb_obj_encoding, 0); /* in encoding.c */
    rb_define_method(rb_cRegexp, "fixed_encoding?", rb_reg_fixed_encoding_p, 0);
    rb_define_method(rb_cRegexp, "names", rb_reg_names, 0);
    rb_define_method(rb_cRegexp, "named_captures", rb_reg_named_captures, 0);
    rb_define_method(rb_cRegexp, "timeout", rb_reg_timeout_get, 0);

    rb_eRegexpTimeoutError = rb_define_class_under(rb_cRegexp, "TimeoutError", rb_eRegexpError);
    rb_define_singleton_method(rb_cRegexp, "timeout", rb_reg_s_timeout_get, 0);
    rb_define_singleton_method(rb_cRegexp, "timeout=", rb_reg_s_timeout_set, 1);

    /* see Regexp.options and Regexp.new */
    rb_define_const(rb_cRegexp, "IGNORECASE", INT2FIX(ONIG_OPTION_IGNORECASE));
    /* see Regexp.options and Regexp.new */
    rb_define_const(rb_cRegexp, "EXTENDED", INT2FIX(ONIG_OPTION_EXTEND));
    /* see Regexp.options and Regexp.new */
    rb_define_const(rb_cRegexp, "MULTILINE", INT2FIX(ONIG_OPTION_MULTILINE));
    /* see Regexp.options and Regexp.new */
    rb_define_const(rb_cRegexp, "FIXEDENCODING", INT2FIX(ARG_ENCODING_FIXED));
    /* see Regexp.options and Regexp.new */
    rb_define_const(rb_cRegexp, "NOENCODING", INT2FIX(ARG_ENCODING_NONE));

    rb_global_variable(&reg_cache);

    rb_cMatch  = rb_define_class("MatchData", rb_cObject);
    rb_define_alloc_func(rb_cMatch, match_alloc);
    rb_undef_method(CLASS_OF(rb_cMatch), "new");
    rb_undef_method(CLASS_OF(rb_cMatch), "allocate");

    rb_define_method(rb_cMatch, "initialize_copy", match_init_copy, 1);
    rb_define_method(rb_cMatch, "regexp", match_regexp, 0);
    rb_define_method(rb_cMatch, "names", match_names, 0);
    rb_define_method(rb_cMatch, "size", match_size, 0);
    rb_define_method(rb_cMatch, "length", match_size, 0);
    rb_define_method(rb_cMatch, "offset", match_offset, 1);
    rb_define_method(rb_cMatch, "byteoffset", match_byteoffset, 1);
    rb_define_method(rb_cMatch, "begin", match_begin, 1);
    rb_define_method(rb_cMatch, "end", match_end, 1);
    rb_define_method(rb_cMatch, "match", match_nth, 1);
    rb_define_method(rb_cMatch, "match_length", match_nth_length, 1);
    rb_define_method(rb_cMatch, "to_a", match_to_a, 0);
    rb_define_method(rb_cMatch, "[]", match_aref, -1);
    rb_define_method(rb_cMatch, "captures", match_captures, 0);
    rb_define_alias(rb_cMatch,  "deconstruct", "captures");
    rb_define_method(rb_cMatch, "named_captures", match_named_captures, -1);
    rb_define_method(rb_cMatch, "deconstruct_keys", match_deconstruct_keys, 1);
    rb_define_method(rb_cMatch, "values_at", match_values_at, -1);
    rb_define_method(rb_cMatch, "pre_match", rb_reg_match_pre, 0);
    rb_define_method(rb_cMatch, "post_match", rb_reg_match_post, 0);
    rb_define_method(rb_cMatch, "to_s", match_to_s, 0);
    rb_define_method(rb_cMatch, "inspect", match_inspect, 0);
    rb_define_method(rb_cMatch, "string", match_string, 0);
    rb_define_method(rb_cMatch, "hash", match_hash, 0);
    rb_define_method(rb_cMatch, "eql?", match_equal, 1);
    rb_define_method(rb_cMatch, "==", match_equal, 1);
}
