#include "ruby.h"
#include "ruby/encoding.h"

static VALUE rb_cERB, rb_mUtil, rb_cCGI;
static ID id_escapeHTML;

#define HTML_ESCAPE_MAX_LEN 6

static const struct {
    uint8_t len;
    char str[HTML_ESCAPE_MAX_LEN+1];
} html_escape_table[UCHAR_MAX+1] = {
#define HTML_ESCAPE(c, str) [c] = {rb_strlen_lit(str), str}
    HTML_ESCAPE('\'', "&#39;"),
    HTML_ESCAPE('&', "&amp;"),
    HTML_ESCAPE('"', "&quot;"),
    HTML_ESCAPE('<', "&lt;"),
    HTML_ESCAPE('>', "&gt;"),
#undef HTML_ESCAPE
};

static inline void
preserve_original_state(VALUE orig, VALUE dest)
{
    rb_enc_associate(dest, rb_enc_get(orig));
}

static inline long
escaped_length(VALUE str)
{
    const long len = RSTRING_LEN(str);
    if (len >= LONG_MAX / HTML_ESCAPE_MAX_LEN) {
        ruby_malloc_size_overflow(len, HTML_ESCAPE_MAX_LEN);
    }
    return len * HTML_ESCAPE_MAX_LEN;
}

static VALUE
optimized_escape_html(VALUE str)
{
    if (strpbrk(RSTRING_PTR(str), "'&\"<>") == NULL) {
        return str;
    }

    VALUE vbuf;
    char *buf = ALLOCV_N(char, vbuf, escaped_length(str));
    const char *cstr = RSTRING_PTR(str);
    const char *end = cstr + RSTRING_LEN(str);

    char *dest = buf;
    while (cstr < end) {
        const unsigned char c = *cstr++;
        uint8_t len = html_escape_table[c].len;
        if (len) {
            memcpy(dest, html_escape_table[c].str, len);
            dest += len;
        }
        else {
            *dest++ = c;
        }
    }

    VALUE escaped = rb_str_new(buf, dest - buf);
    preserve_original_state(str, escaped);
    ALLOCV_END(vbuf);
    return escaped;
}

// ERB::Util.html_escape is different from CGI.escapeHTML in the following two parts:
//   * ERB::Util.html_escape converts an argument with #to_s first (only if it's not T_STRING)
//   * ERB::Util.html_escape does not allocate a new string when nothing needs to be escaped
static VALUE
erb_escape_html(VALUE self, VALUE str)
{
    str = rb_convert_type(str, T_STRING, "String", "to_s");

    if (rb_enc_str_asciicompat_p(str)) {
        return optimized_escape_html(str);
    }
    else {
        return rb_funcall(rb_cCGI, id_escapeHTML, 1, str);
    }
}

void
Init_erb(void)
{
    rb_cERB = rb_define_class("ERB", rb_cObject);
    rb_mUtil = rb_define_module_under(rb_cERB, "Util");
    rb_define_method(rb_mUtil, "html_escape", erb_escape_html, 1);

    rb_cCGI = rb_define_class("CGI", rb_cObject);
    id_escapeHTML = rb_intern("escapeHTML");
}
