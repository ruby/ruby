#include "transcode_data.h"

<%
  map = {}
  map["1b2842"] = :func_so       # designate US-ASCII to G0.             "ESC ( B"
  map["1b284a"] = :func_so       # designate JIS X 0201 latin to G0.     "ESC ( J"
  map["1b2440"] = :func_so       # designate JIS X 0208 1978 to G0.      "ESC $ @"
  map["1b2442"] = :func_so       # designate JIS X 0208 1983 to G0.      "ESC $ B"
  map["{00-0d,10-1a,1c-7f}"] = :func_si

  map_jisx0208_rest = {}
  map_jisx0208_rest["{21-7e}"] = :func_so
%>

<%= transcode_generate_node(ActionMap.parse(map), "iso2022jp_to_eucjp", []) %>
<%= transcode_generate_node(ActionMap.parse(map_jisx0208_rest), "iso2022jp_to_eucjp_jisx0208_rest", []) %>

static VALUE
fun_si_iso2022jp_to_eucjp(rb_transcoding* t, const unsigned char* s, size_t l)
{
    if (t->stateful[0] == 0)
        return (VALUE)NOMAP;
    else if (0x21 <= s[0] && s[0] <= 0x7e)
        return (VALUE)&iso2022jp_to_eucjp_jisx0208_rest;
    else
        return (VALUE)INVALID;
}

static int
fun_so_iso2022jp_to_eucjp(rb_transcoding* t, const unsigned char* s, size_t l, unsigned char* o)
{
    if (s[0] == 0x1b) {
        if (s[1] == '(') {
            switch (s[l-1]) {
              case 'B':
              case 'J':
                t->stateful[0] = 0;
                break;
            }
        }
        else {
            switch (s[l-1]) {
              case '@':
              case 'B':
                t->stateful[0] = 1;
                break;
            }
        }
        return 0;
    }
    else {
        o[0] = s[0] | 0x80;
        o[1] = s[1] | 0x80;
        return 2;
    }
}

static const rb_transcoder
rb_ISO_2022_JP_to_EUC_JP = {
    "ISO-2022-JP", "EUC-JP", &iso2022jp_to_eucjp, 3, 0,
    NULL, fun_si_iso2022jp_to_eucjp, NULL, fun_so_iso2022jp_to_eucjp
};

<%
  map_eucjp = {
    "{0e,0f,1b}" => :undef,
    "{00-0d,10-1a,1c-7f}" => :func_so,
    "{a1-fe}{a1-fe}" => :func_so,
    "8e{a1-fe}" => :undef,
    "8f{a1-fe}{a1-fe}" => :undef,
  }
%>

<%= transcode_generate_node(ActionMap.parse(map_eucjp), "eucjp_to_iso2022jp", []) %>

static int
fun_so_eucjp_to_iso2022jp(rb_transcoding *t, const unsigned char *s, size_t l, unsigned char *o)
{
    unsigned char *output0 = o;

    if (t->stateful[0] == 0) {
        t->stateful[0] = 1; /* initialized flag */
        t->stateful[1] = 1; /* ASCII mode */
    }

    if (l != t->stateful[1]) {
        if (l == 1) {
            *o++ = 0x1b;
            *o++ = '(';
            *o++ = 'B';
            t->stateful[1] = 1;
        }
        else {
            *o++ = 0x1b;
            *o++ = '$';
            *o++ = 'B';
            t->stateful[1] = 2;
        }
    }

    if (l == 1) {
        *o++ = s[0] & 0x7f;
    }
    else {
        *o++ = s[0] & 0x7f;
        *o++ = s[1] & 0x7f;
    }

    return o - output0;
}

static int
finish_eucjp_to_iso2022jp(rb_transcoding *t, unsigned char *o)
{
    unsigned char *output0 = o;

    if (t->stateful[0] == 0)
        return 0;

    if (t->stateful[1] != 1) {
        *o++ = 0x1b;
        *o++ = '(';
        *o++ = 'B';
        t->stateful[1] = 1;
    }

    return o - output0;
}

static const rb_transcoder
rb_EUC_JP_to_ISO_2022_JP = {
    "EUC-JP", "ISO-2022-JP", &eucjp_to_iso2022jp, 5, 0,
    NULL, NULL, NULL, fun_so_eucjp_to_iso2022jp, finish_eucjp_to_iso2022jp
};

void
Init_iso2022(void)
{
    rb_register_transcoder(&rb_ISO_2022_JP_to_EUC_JP);
    rb_register_transcoder(&rb_EUC_JP_to_ISO_2022_JP);
}

