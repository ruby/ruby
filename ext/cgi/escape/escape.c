#include "ruby.h"
#include "ruby/encoding.h"

RUBY_EXTERN const char ruby_hexdigits[];
RUBY_EXTERN const signed char ruby_digit36_to_number_table[];
#define lower_hexdigits (ruby_hexdigits+0)
#define upper_hexdigits (ruby_hexdigits+16)
#define char_to_number(c) ruby_digit36_to_number_table[(unsigned char)(c)]

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

static VALUE
optimized_unescape(VALUE str, VALUE encoding)
{
    long i, len, beg = 0;
    VALUE dest = 0;
    const char *cstr;
    int cr, origenc, encidx = rb_to_encoding_index(encoding);

    len  = RSTRING_LEN(str);
    cstr = RSTRING_PTR(str);

    for (i = 0; i < len; ++i) {
	char buf[1];
	const char c = cstr[i];
	int clen = 0;
	if (c == '%') {
	    if (i + 3 > len) break;
	    if (!ISXDIGIT(cstr[i+1])) continue;
	    if (!ISXDIGIT(cstr[i+2])) continue;
	    buf[0] = ((char_to_number(cstr[i+1]) << 4)
		      | char_to_number(cstr[i+2]));
	    clen = 2;
	}
	else if (c == '+') {
	    buf[0] = ' ';
	}
	else {
	    continue;
	}

	if (!dest) {
	    dest = rb_str_buf_new(len);
	}

	rb_str_cat(dest, cstr + beg, i - beg);
	i += clen;
	beg = i + 1;

	rb_str_cat(dest, buf, 1);
    }

    if (dest) {
	rb_str_cat(dest, cstr + beg, len - beg);
	preserve_original_state(str, dest);
	cr = ENC_CODERANGE_UNKNOWN;
    }
    else {
	dest = rb_str_dup(str);
	cr = ENC_CODERANGE(str);
    }
    origenc = rb_enc_get_index(str);
    if (origenc != encidx) {
	rb_enc_associate_index(dest, encidx);
	if (!ENC_CODERANGE_CLEAN_P(rb_enc_str_coderange(dest))) {
	    rb_enc_associate_index(dest, origenc);
	    if (cr != ENC_CODERANGE_UNKNOWN)
		ENC_CODERANGE_SET(dest, cr);
	}
    }
    return dest;
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

/* :nodoc: */
static VALUE
cgiesc_unescape(VALUE self, VALUE str, VALUE enc)
{
    StringValue(str);

    if (rb_enc_str_asciicompat_p(str)) {
	return optimized_unescape(str, enc);
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
    rb_define_method(rb_mEscape, "escape", cgiesc_escape, 1);
    rb_define_private_method(rb_mEscape, "_unescape", cgiesc_unescape, 2);
    rb_prepend_module(rb_mUtil, rb_mEscape);
    rb_extend_object(rb_cCGI, rb_mEscape);
}
