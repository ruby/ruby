#include "ruby.h"
#include "ruby/encoding.h"

static VALUE rb_cCGI, rb_mUtil, rb_mEscape;

static VALUE
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

static VALUE
optimized_escape_html(VALUE str)
{
    long i, len, modified = 0, beg = 0, offset = 0;
    VALUE dest;
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
	    if (!modified) {
		modified = 1;
		dest = rb_str_buf_new(len);
	    }

	    rb_str_cat(dest, cstr + beg, i - beg);
	    beg = i + 1;

	    html_escaped_cat(dest, cstr[i]);
	    break;
	}
    }

    if (modified) {
	rb_str_cat(dest, cstr + beg, len - beg);
	return dest;
    } else {
	return str;
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
    Check_Type(str, T_STRING);

    if (rb_enc_str_asciicompat_p(str)) {
	return optimized_escape_html(str);
    } else {
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
    rb_prepend_module(rb_mUtil, rb_mEscape);
    rb_extend_object(rb_cCGI, rb_mEscape);
}
