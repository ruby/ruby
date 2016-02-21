#include "ruby.h"
#include "ruby/encoding.h"

RUBY_EXTERN unsigned long ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow);
RUBY_EXTERN const char ruby_hexdigits[];
#define lower_hexdigits (ruby_hexdigits+0)
#define upper_hexdigits (ruby_hexdigits+16)

static VALUE rb_cCGI, rb_mUtil, rb_mEscape;

static void
html_escaped_cat(VALUE str, char c)
{
    switch (c) {
      case '\'':
	rb_str_cat_cstr(str, "&#39;");
	break;
      case '&':
	rb_str_cat_cstr(str, "&amp;");
	break;
      case '"':
	rb_str_cat_cstr(str, "&quot;");
	break;
      case '<':
	rb_str_cat_cstr(str, "&lt;");
	break;
      case '>':
	rb_str_cat_cstr(str, "&gt;");
	break;
    }
}

static inline void
preserve_original_state(VALUE orig, VALUE dest)
{
    rb_enc_associate(dest, rb_enc_get(orig));

    RB_OBJ_INFECT_RAW(dest, orig);
}

static VALUE
optimized_escape_html(VALUE str)
{
    long i, len, beg = 0;
    VALUE dest = 0;
    const char *cstr;

    len  = RSTRING_LEN(str);
    cstr = RSTRING_PTR(str);

    for (i = 0; i < len; i++) {
	switch (cstr[i]) {
	  case '\'':
	  case '&':
	  case '"':
	  case '<':
	  case '>':
	    if (!dest) {
		dest = rb_str_buf_new(len);
	    }

	    rb_str_cat(dest, cstr + beg, i - beg);
	    beg = i + 1;

	    html_escaped_cat(dest, cstr[i]);
	    break;
	}
    }

    if (dest) {
	rb_str_cat(dest, cstr + beg, len - beg);
	preserve_original_state(str, dest);
	return dest;
    }
    else {
	return rb_str_dup(str);
    }
}

static VALUE
optimized_unescape_html(VALUE str)
{
    enum {UNICODE_MAX = 0x10ffff};
    rb_encoding *enc = rb_enc_get(str);
    unsigned long charlimit = (strcasecmp(rb_enc_name(enc), "UTF-8") == 0 ? UNICODE_MAX :
			       strcasecmp(rb_enc_name(enc), "ISO-8859-1") == 0 ? 256 :
			       128);
    long i, len, beg = 0;
    size_t clen, plen;
    int overflow;
    const char *cstr;
    char buf[6];
    VALUE dest = 0;

    len  = RSTRING_LEN(str);
    cstr = RSTRING_PTR(str);

    for (i = 0; i < len; i++) {
	unsigned long cc;
	char c = cstr[i];
	if (c != '&') continue;
	plen = i - beg;
	if (++i >= len) break;
	c = (unsigned char)cstr[i];
	switch (c) {
	  case 'a':
	    ++i;
	    if (len - i >= 4 && memcmp(&cstr[i], "pos;", 4) == 0) {
		c = '\'';
		i += 3;
	    }
	    else if (len - i >= 3 && memcmp(&cstr[i], "mp;", 3) == 0) {
		c = '&';
		i += 2;
	    }
	    else continue;
	    break;
	  case 'q':
	    ++i;
	    if (len - i >= 4 && memcmp(&cstr[i], "uot;", 4) == 0) {
		c = '"';
		i += 3;
	    }
	    else continue;
	    break;
	  case 'g':
	    ++i;
	    if (len - i >= 2 && memcmp(&cstr[i], "t;", 2) == 0) {
		c = '>';
		i += 1;
	    }
	    else continue;
	    break;
	  case 'l':
	    ++i;
	    if (len - i >= 2 && memcmp(&cstr[i], "t;", 2) == 0) {
		c = '<';
		i += 1;
	    }
	    else continue;
	    break;
	  case '#':
	    if (len - ++i >= 2 && ISDIGIT(cstr[i])) {
		cc = ruby_scan_digits(&cstr[i], len-i, 10, &clen, &overflow);
	    }
	    else if ((cstr[i] == 'x' || cstr[i] == 'X') && len - ++i >= 2 && ISXDIGIT(cstr[i])) {
		cc = ruby_scan_digits(&cstr[i], len-i, 16, &clen, &overflow);
	    }
	    else continue;
	    i += clen;
	    if (overflow || cc >= charlimit || cstr[i] != ';') continue;
	    if (!dest) {
		dest = rb_str_buf_new(len);
	    }
	    rb_str_cat(dest, cstr + beg, plen);
	    if (charlimit > 256) {
		rb_str_cat(dest, buf, rb_enc_mbcput((OnigCodePoint)cc, buf, enc));
	    }
	    else {
		c = (unsigned char)cc;
		rb_str_cat(dest, &c, 1);
	    }
	    beg = i + 1;
	    continue;
	  default:
	    --i;
	    continue;
	}
	if (!dest) {
	    dest = rb_str_buf_new(len);
	}
	rb_str_cat(dest, cstr + beg, plen);
	rb_str_cat(dest, &c, 1);
	beg = i + 1;
    }

    if (dest) {
	rb_str_cat(dest, cstr + beg, len - beg);
	preserve_original_state(str, dest);
	return dest;
    }
    else {
	return rb_str_dup(str);
    }
}

static int
url_unreserved_char(unsigned char c)
{
    switch (c) {
      case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9':
      case 'a': case 'b': case 'c': case 'd': case 'e': case 'f': case 'g': case 'h': case 'i': case 'j':
      case 'k': case 'l': case 'm': case 'n': case 'o': case 'p': case 'q': case 'r': case 's': case 't':
      case 'u': case 'v': case 'w': case 'x': case 'y': case 'z':
      case 'A': case 'B': case 'C': case 'D': case 'E': case 'F': case 'G': case 'H': case 'I': case 'J':
      case 'K': case 'L': case 'M': case 'N': case 'O': case 'P': case 'Q': case 'R': case 'S': case 'T':
      case 'U': case 'V': case 'W': case 'X': case 'Y': case 'Z':
      case '-': case '.': case '_':
        return 1;
      default:
        break;
    }
    return 0;
}

static VALUE
optimized_escape(VALUE str)
{
    long i, len, beg = 0;
    VALUE dest = 0;
    const char *cstr;
    char buf[4] = {'%'};

    len  = RSTRING_LEN(str);
    cstr = RSTRING_PTR(str);

    for (i = 0; i < len; ++i) {
	const unsigned char c = (unsigned char)cstr[i];
	if (!url_unreserved_char(c)) {
	    if (!dest) {
		dest = rb_str_buf_new(len);
	    }

	    rb_str_cat(dest, cstr + beg, i - beg);
	    beg = i + 1;

	    if (c == ' ') {
		rb_str_cat_cstr(dest, "+");
	    }
	    else {
		buf[1] = upper_hexdigits[(c >> 4) & 0xf];
		buf[2] = upper_hexdigits[c & 0xf];
		rb_str_cat(dest, buf, 3);
	    }
	}
    }

    if (dest) {
	rb_str_cat(dest, cstr + beg, len - beg);
	preserve_original_state(str, dest);
	return dest;
    }
    else {
	return rb_str_dup(str);
    }
}

/*
 *  call-seq:
 *     CGI.escapeHTML(string) -> string
 *
 *  Returns HTML-escaped string.
 *
 */
static VALUE
cgiesc_escape_html(VALUE self, VALUE str)
{
    StringValue(str);

    if (rb_enc_str_asciicompat_p(str)) {
	return optimized_escape_html(str);
    }
    else {
	return rb_call_super(1, &str);
    }
}

/*
 *  call-seq:
 *     CGI.unescapeHTML(string) -> string
 *
 *  Returns HTML-unescaped string.
 *
 */
static VALUE
cgiesc_unescape_html(VALUE self, VALUE str)
{
    StringValue(str);

    if (rb_enc_str_asciicompat_p(str)) {
	return optimized_unescape_html(str);
    }
    else {
	return rb_call_super(1, &str);
    }
}

/*
 *  call-seq:
 *     CGI.escape(string) -> string
 *
 *  Returns URL-escaped string.
 *
 */
static VALUE
cgiesc_escape(VALUE self, VALUE str)
{
    StringValue(str);

    if (rb_enc_str_asciicompat_p(str)) {
	return optimized_escape(str);
    }
    else {
	return rb_call_super(1, &str);
    }
}

void
Init_escape(void)
{
    rb_cCGI    = rb_define_class("CGI", rb_cObject);
    rb_mEscape = rb_define_module_under(rb_cCGI, "Escape");
    rb_mUtil   = rb_define_module_under(rb_cCGI, "Util");
    rb_define_method(rb_mEscape, "escapeHTML", cgiesc_escape_html, 1);
    rb_define_method(rb_mEscape, "unescapeHTML", cgiesc_unescape_html, 1);
    rb_define_method(rb_mEscape, "escape", cgiesc_escape, 1);
    rb_prepend_module(rb_mUtil, rb_mEscape);
    rb_extend_object(rb_cCGI, rb_mEscape);
}
