
#line 1 "parser.rl"
#include "../fbuffer/fbuffer.h"
#include "parser.h"

#if defined HAVE_RUBY_ENCODING_H
# define EXC_ENCODING rb_utf8_encoding(),
# ifndef HAVE_RB_ENC_RAISE
static void
enc_raise(rb_encoding *enc, VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_enc_vsprintf(enc, fmt, args);
    va_end(args);

    rb_exc_raise(rb_exc_new3(exc, mesg));
}
#   define rb_enc_raise enc_raise
# endif
#else
# define EXC_ENCODING /* nothing */
# define rb_enc_raise rb_raise
#endif

/* unicode */

static const char digit_values[256] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1,
    -1, -1, -1, -1, -1, -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1
};

static UTF32 unescape_unicode(const unsigned char *p)
{
    char b;
    UTF32 result = 0;
    b = digit_values[p[0]];
    if (b < 0) return UNI_REPLACEMENT_CHAR;
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[1]];
    if (b < 0) return UNI_REPLACEMENT_CHAR;
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[2]];
    if (b < 0) return UNI_REPLACEMENT_CHAR;
    result = (result << 4) | (unsigned char)b;
    b = digit_values[p[3]];
    if (b < 0) return UNI_REPLACEMENT_CHAR;
    result = (result << 4) | (unsigned char)b;
    return result;
}

static int convert_UTF32_to_UTF8(char *buf, UTF32 ch)
{
    int len = 1;
    if (ch <= 0x7F) {
        buf[0] = (char) ch;
    } else if (ch <= 0x07FF) {
        buf[0] = (char) ((ch >> 6) | 0xC0);
        buf[1] = (char) ((ch & 0x3F) | 0x80);
        len++;
    } else if (ch <= 0xFFFF) {
        buf[0] = (char) ((ch >> 12) | 0xE0);
        buf[1] = (char) (((ch >> 6) & 0x3F) | 0x80);
        buf[2] = (char) ((ch & 0x3F) | 0x80);
        len += 2;
    } else if (ch <= 0x1fffff) {
        buf[0] =(char) ((ch >> 18) | 0xF0);
        buf[1] =(char) (((ch >> 12) & 0x3F) | 0x80);
        buf[2] =(char) (((ch >> 6) & 0x3F) | 0x80);
        buf[3] =(char) ((ch & 0x3F) | 0x80);
        len += 3;
    } else {
        buf[0] = '?';
    }
    return len;
}

static VALUE mJSON, mExt, cParser, eParserError, eNestingError;
static VALUE CNaN, CInfinity, CMinusInfinity;

static ID i_json_creatable_p, i_json_create, i_create_id, i_create_additions,
          i_chr, i_max_nesting, i_allow_nan, i_symbolize_names,
          i_object_class, i_array_class, i_key_p, i_deep_const_get, i_match,
          i_match_string, i_aset, i_aref, i_leftshift;


#line 124 "parser.rl"



#line 106 "parser.c"
enum {JSON_object_start = 1};
enum {JSON_object_first_final = 27};
enum {JSON_object_error = 0};

enum {JSON_object_en_main = 1};


#line 165 "parser.rl"


static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting)
{
    int cs = EVIL;
    VALUE last_name = Qnil;
    VALUE object_class = json->object_class;

    if (json->max_nesting && current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", current_nesting);
    }

    *result = NIL_P(object_class) ? rb_hash_new() : rb_class_new_instance(0, 0, object_class);


#line 130 "parser.c"
	{
	cs = JSON_object_start;
	}

#line 180 "parser.rl"

#line 137 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
case 1:
	if ( (*p) == 123 )
		goto st2;
	goto st0;
st0:
cs = 0;
	goto _out;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	switch( (*p) ) {
		case 13: goto st2;
		case 32: goto st2;
		case 34: goto tr2;
		case 47: goto st23;
		case 125: goto tr4;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st2;
	goto st0;
tr2:
#line 147 "parser.rl"
	{
        char *np;
        json->parsing_name = 1;
        np = JSON_parse_string(json, p, pe, &last_name);
        json->parsing_name = 0;
        if (np == NULL) { p--; {p++; cs = 3; goto _out;} } else {p = (( np))-1;}
    }
	goto st3;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
#line 178 "parser.c"
	switch( (*p) ) {
		case 13: goto st3;
		case 32: goto st3;
		case 47: goto st4;
		case 58: goto st8;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st3;
	goto st0;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	switch( (*p) ) {
		case 42: goto st5;
		case 47: goto st7;
	}
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( (*p) == 42 )
		goto st6;
	goto st5;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	switch( (*p) ) {
		case 42: goto st6;
		case 47: goto st3;
	}
	goto st5;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	if ( (*p) == 10 )
		goto st3;
	goto st7;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	switch( (*p) ) {
		case 13: goto st8;
		case 32: goto st8;
		case 34: goto tr11;
		case 45: goto tr11;
		case 47: goto st19;
		case 73: goto tr11;
		case 78: goto tr11;
		case 91: goto tr11;
		case 102: goto tr11;
		case 110: goto tr11;
		case 116: goto tr11;
		case 123: goto tr11;
	}
	if ( (*p) > 10 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto tr11;
	} else if ( (*p) >= 9 )
		goto st8;
	goto st0;
tr11:
#line 132 "parser.rl"
	{
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, p, pe, &v, current_nesting);
        if (np == NULL) {
            p--; {p++; cs = 9; goto _out;}
        } else {
            if (NIL_P(json->object_class)) {
                rb_hash_aset(*result, last_name, v);
            } else {
                rb_funcall(*result, i_aset, 2, last_name, v);
            }
            {p = (( np))-1;}
        }
    }
	goto st9;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
#line 265 "parser.c"
	switch( (*p) ) {
		case 13: goto st9;
		case 32: goto st9;
		case 44: goto st10;
		case 47: goto st15;
		case 125: goto tr4;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st9;
	goto st0;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
	switch( (*p) ) {
		case 13: goto st10;
		case 32: goto st10;
		case 34: goto tr2;
		case 47: goto st11;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st10;
	goto st0;
st11:
	if ( ++p == pe )
		goto _test_eof11;
case 11:
	switch( (*p) ) {
		case 42: goto st12;
		case 47: goto st14;
	}
	goto st0;
st12:
	if ( ++p == pe )
		goto _test_eof12;
case 12:
	if ( (*p) == 42 )
		goto st13;
	goto st12;
st13:
	if ( ++p == pe )
		goto _test_eof13;
case 13:
	switch( (*p) ) {
		case 42: goto st13;
		case 47: goto st10;
	}
	goto st12;
st14:
	if ( ++p == pe )
		goto _test_eof14;
case 14:
	if ( (*p) == 10 )
		goto st10;
	goto st14;
st15:
	if ( ++p == pe )
		goto _test_eof15;
case 15:
	switch( (*p) ) {
		case 42: goto st16;
		case 47: goto st18;
	}
	goto st0;
st16:
	if ( ++p == pe )
		goto _test_eof16;
case 16:
	if ( (*p) == 42 )
		goto st17;
	goto st16;
st17:
	if ( ++p == pe )
		goto _test_eof17;
case 17:
	switch( (*p) ) {
		case 42: goto st17;
		case 47: goto st9;
	}
	goto st16;
st18:
	if ( ++p == pe )
		goto _test_eof18;
case 18:
	if ( (*p) == 10 )
		goto st9;
	goto st18;
tr4:
#line 155 "parser.rl"
	{ p--; {p++; cs = 27; goto _out;} }
	goto st27;
st27:
	if ( ++p == pe )
		goto _test_eof27;
case 27:
#line 361 "parser.c"
	goto st0;
st19:
	if ( ++p == pe )
		goto _test_eof19;
case 19:
	switch( (*p) ) {
		case 42: goto st20;
		case 47: goto st22;
	}
	goto st0;
st20:
	if ( ++p == pe )
		goto _test_eof20;
case 20:
	if ( (*p) == 42 )
		goto st21;
	goto st20;
st21:
	if ( ++p == pe )
		goto _test_eof21;
case 21:
	switch( (*p) ) {
		case 42: goto st21;
		case 47: goto st8;
	}
	goto st20;
st22:
	if ( ++p == pe )
		goto _test_eof22;
case 22:
	if ( (*p) == 10 )
		goto st8;
	goto st22;
st23:
	if ( ++p == pe )
		goto _test_eof23;
case 23:
	switch( (*p) ) {
		case 42: goto st24;
		case 47: goto st26;
	}
	goto st0;
st24:
	if ( ++p == pe )
		goto _test_eof24;
case 24:
	if ( (*p) == 42 )
		goto st25;
	goto st24;
st25:
	if ( ++p == pe )
		goto _test_eof25;
case 25:
	switch( (*p) ) {
		case 42: goto st25;
		case 47: goto st2;
	}
	goto st24;
st26:
	if ( ++p == pe )
		goto _test_eof26;
case 26:
	if ( (*p) == 10 )
		goto st2;
	goto st26;
	}
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;
	_test_eof6: cs = 6; goto _test_eof;
	_test_eof7: cs = 7; goto _test_eof;
	_test_eof8: cs = 8; goto _test_eof;
	_test_eof9: cs = 9; goto _test_eof;
	_test_eof10: cs = 10; goto _test_eof;
	_test_eof11: cs = 11; goto _test_eof;
	_test_eof12: cs = 12; goto _test_eof;
	_test_eof13: cs = 13; goto _test_eof;
	_test_eof14: cs = 14; goto _test_eof;
	_test_eof15: cs = 15; goto _test_eof;
	_test_eof16: cs = 16; goto _test_eof;
	_test_eof17: cs = 17; goto _test_eof;
	_test_eof18: cs = 18; goto _test_eof;
	_test_eof27: cs = 27; goto _test_eof;
	_test_eof19: cs = 19; goto _test_eof;
	_test_eof20: cs = 20; goto _test_eof;
	_test_eof21: cs = 21; goto _test_eof;
	_test_eof22: cs = 22; goto _test_eof;
	_test_eof23: cs = 23; goto _test_eof;
	_test_eof24: cs = 24; goto _test_eof;
	_test_eof25: cs = 25; goto _test_eof;
	_test_eof26: cs = 26; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 181 "parser.rl"

    if (cs >= JSON_object_first_final) {
        if (json->create_additions) {
            VALUE klassname;
            if (NIL_P(json->object_class)) {
              klassname = rb_hash_aref(*result, json->create_id);
            } else {
              klassname = rb_funcall(*result, i_aref, 1, json->create_id);
            }
            if (!NIL_P(klassname)) {
                VALUE klass = rb_funcall(mJSON, i_deep_const_get, 1, klassname);
                if (RTEST(rb_funcall(klass, i_json_creatable_p, 0))) {
                    *result = rb_funcall(klass, i_json_create, 1, *result);
                }
            }
        }
        return p + 1;
    } else {
        return NULL;
    }
}



#line 484 "parser.c"
enum {JSON_value_start = 1};
enum {JSON_value_first_final = 29};
enum {JSON_value_error = 0};

enum {JSON_value_en_main = 1};


#line 281 "parser.rl"


static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting)
{
    int cs = EVIL;


#line 500 "parser.c"
	{
	cs = JSON_value_start;
	}

#line 288 "parser.rl"

#line 507 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
st1:
	if ( ++p == pe )
		goto _test_eof1;
case 1:
	switch( (*p) ) {
		case 13: goto st1;
		case 32: goto st1;
		case 34: goto tr2;
		case 45: goto tr3;
		case 47: goto st6;
		case 73: goto st10;
		case 78: goto st17;
		case 91: goto tr7;
		case 102: goto st19;
		case 110: goto st23;
		case 116: goto st26;
		case 123: goto tr11;
	}
	if ( (*p) > 10 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto tr3;
	} else if ( (*p) >= 9 )
		goto st1;
	goto st0;
st0:
cs = 0;
	goto _out;
tr2:
#line 233 "parser.rl"
	{
        char *np = JSON_parse_string(json, p, pe, result);
        if (np == NULL) { p--; {p++; cs = 29; goto _out;} } else {p = (( np))-1;}
    }
	goto st29;
tr3:
#line 238 "parser.rl"
	{
        char *np;
        if(pe > p + 8 && !strncmp(MinusInfinity, p, 9)) {
            if (json->allow_nan) {
                *result = CMinusInfinity;
                {p = (( p + 10))-1;}
                p--; {p++; cs = 29; goto _out;}
            } else {
                rb_enc_raise(EXC_ENCODING eParserError, "%u: unexpected token at '%s'", __LINE__, p);
            }
        }
        np = JSON_parse_float(json, p, pe, result);
        if (np != NULL) {p = (( np))-1;}
        np = JSON_parse_integer(json, p, pe, result);
        if (np != NULL) {p = (( np))-1;}
        p--; {p++; cs = 29; goto _out;}
    }
	goto st29;
tr7:
#line 256 "parser.rl"
	{
        char *np;
        np = JSON_parse_array(json, p, pe, result, current_nesting + 1);
        if (np == NULL) { p--; {p++; cs = 29; goto _out;} } else {p = (( np))-1;}
    }
	goto st29;
tr11:
#line 262 "parser.rl"
	{
        char *np;
        np =  JSON_parse_object(json, p, pe, result, current_nesting + 1);
        if (np == NULL) { p--; {p++; cs = 29; goto _out;} } else {p = (( np))-1;}
    }
	goto st29;
tr25:
#line 226 "parser.rl"
	{
        if (json->allow_nan) {
            *result = CInfinity;
        } else {
            rb_enc_raise(EXC_ENCODING eParserError, "%u: unexpected token at '%s'", __LINE__, p - 8);
        }
    }
	goto st29;
tr27:
#line 219 "parser.rl"
	{
        if (json->allow_nan) {
            *result = CNaN;
        } else {
            rb_enc_raise(EXC_ENCODING eParserError, "%u: unexpected token at '%s'", __LINE__, p - 2);
        }
    }
	goto st29;
tr31:
#line 213 "parser.rl"
	{
        *result = Qfalse;
    }
	goto st29;
tr34:
#line 210 "parser.rl"
	{
        *result = Qnil;
    }
	goto st29;
tr37:
#line 216 "parser.rl"
	{
        *result = Qtrue;
    }
	goto st29;
st29:
	if ( ++p == pe )
		goto _test_eof29;
case 29:
#line 268 "parser.rl"
	{ p--; {p++; cs = 29; goto _out;} }
#line 627 "parser.c"
	switch( (*p) ) {
		case 13: goto st29;
		case 32: goto st29;
		case 47: goto st2;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st29;
	goto st0;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	switch( (*p) ) {
		case 42: goto st3;
		case 47: goto st5;
	}
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	if ( (*p) == 42 )
		goto st4;
	goto st3;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	switch( (*p) ) {
		case 42: goto st4;
		case 47: goto st29;
	}
	goto st3;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( (*p) == 10 )
		goto st29;
	goto st5;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	switch( (*p) ) {
		case 42: goto st7;
		case 47: goto st9;
	}
	goto st0;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	if ( (*p) == 42 )
		goto st8;
	goto st7;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	switch( (*p) ) {
		case 42: goto st8;
		case 47: goto st1;
	}
	goto st7;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
	if ( (*p) == 10 )
		goto st1;
	goto st9;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
	if ( (*p) == 110 )
		goto st11;
	goto st0;
st11:
	if ( ++p == pe )
		goto _test_eof11;
case 11:
	if ( (*p) == 102 )
		goto st12;
	goto st0;
st12:
	if ( ++p == pe )
		goto _test_eof12;
case 12:
	if ( (*p) == 105 )
		goto st13;
	goto st0;
st13:
	if ( ++p == pe )
		goto _test_eof13;
case 13:
	if ( (*p) == 110 )
		goto st14;
	goto st0;
st14:
	if ( ++p == pe )
		goto _test_eof14;
case 14:
	if ( (*p) == 105 )
		goto st15;
	goto st0;
st15:
	if ( ++p == pe )
		goto _test_eof15;
case 15:
	if ( (*p) == 116 )
		goto st16;
	goto st0;
st16:
	if ( ++p == pe )
		goto _test_eof16;
case 16:
	if ( (*p) == 121 )
		goto tr25;
	goto st0;
st17:
	if ( ++p == pe )
		goto _test_eof17;
case 17:
	if ( (*p) == 97 )
		goto st18;
	goto st0;
st18:
	if ( ++p == pe )
		goto _test_eof18;
case 18:
	if ( (*p) == 78 )
		goto tr27;
	goto st0;
st19:
	if ( ++p == pe )
		goto _test_eof19;
case 19:
	if ( (*p) == 97 )
		goto st20;
	goto st0;
st20:
	if ( ++p == pe )
		goto _test_eof20;
case 20:
	if ( (*p) == 108 )
		goto st21;
	goto st0;
st21:
	if ( ++p == pe )
		goto _test_eof21;
case 21:
	if ( (*p) == 115 )
		goto st22;
	goto st0;
st22:
	if ( ++p == pe )
		goto _test_eof22;
case 22:
	if ( (*p) == 101 )
		goto tr31;
	goto st0;
st23:
	if ( ++p == pe )
		goto _test_eof23;
case 23:
	if ( (*p) == 117 )
		goto st24;
	goto st0;
st24:
	if ( ++p == pe )
		goto _test_eof24;
case 24:
	if ( (*p) == 108 )
		goto st25;
	goto st0;
st25:
	if ( ++p == pe )
		goto _test_eof25;
case 25:
	if ( (*p) == 108 )
		goto tr34;
	goto st0;
st26:
	if ( ++p == pe )
		goto _test_eof26;
case 26:
	if ( (*p) == 114 )
		goto st27;
	goto st0;
st27:
	if ( ++p == pe )
		goto _test_eof27;
case 27:
	if ( (*p) == 117 )
		goto st28;
	goto st0;
st28:
	if ( ++p == pe )
		goto _test_eof28;
case 28:
	if ( (*p) == 101 )
		goto tr37;
	goto st0;
	}
	_test_eof1: cs = 1; goto _test_eof;
	_test_eof29: cs = 29; goto _test_eof;
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;
	_test_eof6: cs = 6; goto _test_eof;
	_test_eof7: cs = 7; goto _test_eof;
	_test_eof8: cs = 8; goto _test_eof;
	_test_eof9: cs = 9; goto _test_eof;
	_test_eof10: cs = 10; goto _test_eof;
	_test_eof11: cs = 11; goto _test_eof;
	_test_eof12: cs = 12; goto _test_eof;
	_test_eof13: cs = 13; goto _test_eof;
	_test_eof14: cs = 14; goto _test_eof;
	_test_eof15: cs = 15; goto _test_eof;
	_test_eof16: cs = 16; goto _test_eof;
	_test_eof17: cs = 17; goto _test_eof;
	_test_eof18: cs = 18; goto _test_eof;
	_test_eof19: cs = 19; goto _test_eof;
	_test_eof20: cs = 20; goto _test_eof;
	_test_eof21: cs = 21; goto _test_eof;
	_test_eof22: cs = 22; goto _test_eof;
	_test_eof23: cs = 23; goto _test_eof;
	_test_eof24: cs = 24; goto _test_eof;
	_test_eof25: cs = 25; goto _test_eof;
	_test_eof26: cs = 26; goto _test_eof;
	_test_eof27: cs = 27; goto _test_eof;
	_test_eof28: cs = 28; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 289 "parser.rl"

    if (cs >= JSON_value_first_final) {
        return p;
    } else {
        return NULL;
    }
}


#line 878 "parser.c"
enum {JSON_integer_start = 1};
enum {JSON_integer_first_final = 3};
enum {JSON_integer_error = 0};

enum {JSON_integer_en_main = 1};


#line 305 "parser.rl"


static char *JSON_parse_integer(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;


#line 894 "parser.c"
	{
	cs = JSON_integer_start;
	}

#line 312 "parser.rl"
    json->memo = p;

#line 902 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
case 1:
	switch( (*p) ) {
		case 45: goto st2;
		case 48: goto st3;
	}
	if ( 49 <= (*p) && (*p) <= 57 )
		goto st5;
	goto st0;
st0:
cs = 0;
	goto _out;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	if ( (*p) == 48 )
		goto st3;
	if ( 49 <= (*p) && (*p) <= 57 )
		goto st5;
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st0;
	goto tr4;
tr4:
#line 302 "parser.rl"
	{ p--; {p++; cs = 4; goto _out;} }
	goto st4;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
#line 943 "parser.c"
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st5;
	goto tr4;
	}
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 314 "parser.rl"

    if (cs >= JSON_integer_first_final) {
        long len = p - json->memo;
        fbuffer_clear(json->fbuffer);
        fbuffer_append(json->fbuffer, json->memo, len);
        fbuffer_append_char(json->fbuffer, '\0');
        *result = rb_cstr2inum(FBUFFER_PTR(json->fbuffer), 10);
        return p + 1;
    } else {
        return NULL;
    }
}


#line 977 "parser.c"
enum {JSON_float_start = 1};
enum {JSON_float_first_final = 8};
enum {JSON_float_error = 0};

enum {JSON_float_en_main = 1};


#line 339 "parser.rl"


static char *JSON_parse_float(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;


#line 993 "parser.c"
	{
	cs = JSON_float_start;
	}

#line 346 "parser.rl"
    json->memo = p;

#line 1001 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
case 1:
	switch( (*p) ) {
		case 45: goto st2;
		case 48: goto st3;
	}
	if ( 49 <= (*p) && (*p) <= 57 )
		goto st7;
	goto st0;
st0:
cs = 0;
	goto _out;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	if ( (*p) == 48 )
		goto st3;
	if ( 49 <= (*p) && (*p) <= 57 )
		goto st7;
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	switch( (*p) ) {
		case 46: goto st4;
		case 69: goto st5;
		case 101: goto st5;
	}
	goto st0;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st8;
	goto st0;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	switch( (*p) ) {
		case 69: goto st5;
		case 101: goto st5;
	}
	if ( (*p) > 46 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st8;
	} else if ( (*p) >= 45 )
		goto st0;
	goto tr9;
tr9:
#line 333 "parser.rl"
	{ p--; {p++; cs = 9; goto _out;} }
	goto st9;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
#line 1066 "parser.c"
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	switch( (*p) ) {
		case 43: goto st6;
		case 45: goto st6;
	}
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st10;
	goto st0;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st10;
	goto st0;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
	switch( (*p) ) {
		case 69: goto st0;
		case 101: goto st0;
	}
	if ( (*p) > 46 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st10;
	} else if ( (*p) >= 45 )
		goto st0;
	goto tr9;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	switch( (*p) ) {
		case 46: goto st4;
		case 69: goto st5;
		case 101: goto st5;
	}
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st7;
	goto st0;
	}
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof8: cs = 8; goto _test_eof;
	_test_eof9: cs = 9; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;
	_test_eof6: cs = 6; goto _test_eof;
	_test_eof10: cs = 10; goto _test_eof;
	_test_eof7: cs = 7; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 348 "parser.rl"

    if (cs >= JSON_float_first_final) {
        long len = p - json->memo;
        fbuffer_clear(json->fbuffer);
        fbuffer_append(json->fbuffer, json->memo, len);
        fbuffer_append_char(json->fbuffer, '\0');
        *result = rb_float_new(rb_cstr_to_dbl(FBUFFER_PTR(json->fbuffer), 1));
        return p + 1;
    } else {
        return NULL;
    }
}



#line 1143 "parser.c"
enum {JSON_array_start = 1};
enum {JSON_array_first_final = 17};
enum {JSON_array_error = 0};

enum {JSON_array_en_main = 1};


#line 391 "parser.rl"


static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result, int current_nesting)
{
    int cs = EVIL;
    VALUE array_class = json->array_class;

    if (json->max_nesting && current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", current_nesting);
    }
    *result = NIL_P(array_class) ? rb_ary_new() : rb_class_new_instance(0, 0, array_class);


#line 1165 "parser.c"
	{
	cs = JSON_array_start;
	}

#line 404 "parser.rl"

#line 1172 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
case 1:
	if ( (*p) == 91 )
		goto st2;
	goto st0;
st0:
cs = 0;
	goto _out;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	switch( (*p) ) {
		case 13: goto st2;
		case 32: goto st2;
		case 34: goto tr2;
		case 45: goto tr2;
		case 47: goto st13;
		case 73: goto tr2;
		case 78: goto tr2;
		case 91: goto tr2;
		case 93: goto tr4;
		case 102: goto tr2;
		case 110: goto tr2;
		case 116: goto tr2;
		case 123: goto tr2;
	}
	if ( (*p) > 10 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto tr2;
	} else if ( (*p) >= 9 )
		goto st2;
	goto st0;
tr2:
#line 368 "parser.rl"
	{
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, p, pe, &v, current_nesting);
        if (np == NULL) {
            p--; {p++; cs = 3; goto _out;}
        } else {
            if (NIL_P(json->array_class)) {
                rb_ary_push(*result, v);
            } else {
                rb_funcall(*result, i_leftshift, 1, v);
            }
            {p = (( np))-1;}
        }
    }
	goto st3;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
#line 1231 "parser.c"
	switch( (*p) ) {
		case 13: goto st3;
		case 32: goto st3;
		case 44: goto st4;
		case 47: goto st9;
		case 93: goto tr4;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st3;
	goto st0;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	switch( (*p) ) {
		case 13: goto st4;
		case 32: goto st4;
		case 34: goto tr2;
		case 45: goto tr2;
		case 47: goto st5;
		case 73: goto tr2;
		case 78: goto tr2;
		case 91: goto tr2;
		case 102: goto tr2;
		case 110: goto tr2;
		case 116: goto tr2;
		case 123: goto tr2;
	}
	if ( (*p) > 10 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto tr2;
	} else if ( (*p) >= 9 )
		goto st4;
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	switch( (*p) ) {
		case 42: goto st6;
		case 47: goto st8;
	}
	goto st0;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	if ( (*p) == 42 )
		goto st7;
	goto st6;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	switch( (*p) ) {
		case 42: goto st7;
		case 47: goto st4;
	}
	goto st6;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	if ( (*p) == 10 )
		goto st4;
	goto st8;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
	switch( (*p) ) {
		case 42: goto st10;
		case 47: goto st12;
	}
	goto st0;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
	if ( (*p) == 42 )
		goto st11;
	goto st10;
st11:
	if ( ++p == pe )
		goto _test_eof11;
case 11:
	switch( (*p) ) {
		case 42: goto st11;
		case 47: goto st3;
	}
	goto st10;
st12:
	if ( ++p == pe )
		goto _test_eof12;
case 12:
	if ( (*p) == 10 )
		goto st3;
	goto st12;
tr4:
#line 383 "parser.rl"
	{ p--; {p++; cs = 17; goto _out;} }
	goto st17;
st17:
	if ( ++p == pe )
		goto _test_eof17;
case 17:
#line 1338 "parser.c"
	goto st0;
st13:
	if ( ++p == pe )
		goto _test_eof13;
case 13:
	switch( (*p) ) {
		case 42: goto st14;
		case 47: goto st16;
	}
	goto st0;
st14:
	if ( ++p == pe )
		goto _test_eof14;
case 14:
	if ( (*p) == 42 )
		goto st15;
	goto st14;
st15:
	if ( ++p == pe )
		goto _test_eof15;
case 15:
	switch( (*p) ) {
		case 42: goto st15;
		case 47: goto st2;
	}
	goto st14;
st16:
	if ( ++p == pe )
		goto _test_eof16;
case 16:
	if ( (*p) == 10 )
		goto st2;
	goto st16;
	}
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;
	_test_eof6: cs = 6; goto _test_eof;
	_test_eof7: cs = 7; goto _test_eof;
	_test_eof8: cs = 8; goto _test_eof;
	_test_eof9: cs = 9; goto _test_eof;
	_test_eof10: cs = 10; goto _test_eof;
	_test_eof11: cs = 11; goto _test_eof;
	_test_eof12: cs = 12; goto _test_eof;
	_test_eof17: cs = 17; goto _test_eof;
	_test_eof13: cs = 13; goto _test_eof;
	_test_eof14: cs = 14; goto _test_eof;
	_test_eof15: cs = 15; goto _test_eof;
	_test_eof16: cs = 16; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 405 "parser.rl"

    if(cs >= JSON_array_first_final) {
        return p + 1;
    } else {
        rb_enc_raise(EXC_ENCODING eParserError, "%u: unexpected token at '%s'", __LINE__, p);
        return NULL;
    }
}

static VALUE json_string_unescape(VALUE result, char *string, char *stringEnd)
{
    char *p = string, *pe = string, *unescape;
    int unescape_len;
    char buf[4];

    while (pe < stringEnd) {
        if (*pe == '\\') {
            unescape = (char *) "?";
            unescape_len = 1;
            if (pe > p) rb_str_buf_cat(result, p, pe - p);
            switch (*++pe) {
                case 'n':
                    unescape = (char *) "\n";
                    break;
                case 'r':
                    unescape = (char *) "\r";
                    break;
                case 't':
                    unescape = (char *) "\t";
                    break;
                case '"':
                    unescape = (char *) "\"";
                    break;
                case '\\':
                    unescape = (char *) "\\";
                    break;
                case 'b':
                    unescape = (char *) "\b";
                    break;
                case 'f':
                    unescape = (char *) "\f";
                    break;
                case 'u':
                    if (pe > stringEnd - 4) {
                      rb_enc_raise(
                        EXC_ENCODING eParserError,
                        "%u: incomplete unicode character escape sequence at '%s'", __LINE__, p
                      );
                    } else {
                        UTF32 ch = unescape_unicode((unsigned char *) ++pe);
                        pe += 3;
                        if (UNI_SUR_HIGH_START == (ch & 0xFC00)) {
                            pe++;
                            if (pe > stringEnd - 6) {
                              rb_enc_raise(
                                EXC_ENCODING eParserError,
                                "%u: incomplete surrogate pair at '%s'", __LINE__, p
                                );
                            }
                            if (pe[0] == '\\' && pe[1] == 'u') {
                                UTF32 sur = unescape_unicode((unsigned char *) pe + 2);
                                ch = (((ch & 0x3F) << 10) | ((((ch >> 6) & 0xF) + 1) << 16)
                                        | (sur & 0x3FF));
                                pe += 5;
                            } else {
                                unescape = (char *) "?";
                                break;
                            }
                        }
                        unescape_len = convert_UTF32_to_UTF8(buf, ch);
                        unescape = buf;
                    }
                    break;
                default:
                    p = pe;
                    continue;
            }
            rb_str_buf_cat(result, unescape, unescape_len);
            p = ++pe;
        } else {
            pe++;
        }
    }
    rb_str_buf_cat(result, p, pe - p);
    return result;
}


#line 1483 "parser.c"
enum {JSON_string_start = 1};
enum {JSON_string_first_final = 8};
enum {JSON_string_error = 0};

enum {JSON_string_en_main = 1};


#line 512 "parser.rl"


static int
match_i(VALUE regexp, VALUE klass, VALUE memo)
{
    if (regexp == Qundef) return ST_STOP;
    if (RTEST(rb_funcall(klass, i_json_creatable_p, 0)) &&
      RTEST(rb_funcall(regexp, i_match, 1, rb_ary_entry(memo, 0)))) {
        rb_ary_push(memo, klass);
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    VALUE match_string;

    *result = rb_str_buf_new(0);

#line 1513 "parser.c"
	{
	cs = JSON_string_start;
	}

#line 533 "parser.rl"
    json->memo = p;

#line 1521 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
case 1:
	if ( (*p) == 34 )
		goto st2;
	goto st0;
st0:
cs = 0;
	goto _out;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	switch( (*p) ) {
		case 34: goto tr2;
		case 92: goto st3;
	}
	if ( 0 <= (*p) && (*p) <= 31 )
		goto st0;
	goto st2;
tr2:
#line 498 "parser.rl"
	{
        *result = json_string_unescape(*result, json->memo + 1, p);
        if (NIL_P(*result)) {
            p--;
            {p++; cs = 8; goto _out;}
        } else {
            FORCE_UTF8(*result);
            {p = (( p + 1))-1;}
        }
    }
#line 509 "parser.rl"
	{ p--; {p++; cs = 8; goto _out;} }
	goto st8;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
#line 1564 "parser.c"
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	if ( (*p) == 117 )
		goto st4;
	if ( 0 <= (*p) && (*p) <= 31 )
		goto st0;
	goto st2;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st5;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st5;
	} else
		goto st5;
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st6;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st6;
	} else
		goto st6;
	goto st0;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st7;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st7;
	} else
		goto st7;
	goto st0;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	if ( (*p) < 65 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st2;
	} else if ( (*p) > 70 ) {
		if ( 97 <= (*p) && (*p) <= 102 )
			goto st2;
	} else
		goto st2;
	goto st0;
	}
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof8: cs = 8; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;
	_test_eof6: cs = 6; goto _test_eof;
	_test_eof7: cs = 7; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 535 "parser.rl"

    if (json->create_additions && RTEST(match_string = json->match_string)) {
          VALUE klass;
          VALUE memo = rb_ary_new2(2);
          rb_ary_push(memo, *result);
          rb_hash_foreach(match_string, match_i, memo);
          klass = rb_ary_entry(memo, 1);
          if (RTEST(klass)) {
              *result = rb_funcall(klass, i_json_create, 1, *result);
          }
    }

    if (json->symbolize_names && json->parsing_name) {
      *result = rb_str_intern(*result);
    } else {
      rb_str_resize(*result, RSTRING_LEN(*result));
    }
    if (cs >= JSON_string_first_final) {
        return p + 1;
    } else {
        return NULL;
    }
}

/*
 * Document-class: JSON::Ext::Parser
 *
 * This is the JSON parser implemented as a C extension. It can be configured
 * to be used by setting
 *
 *  JSON.parser = JSON::Ext::Parser
 *
 * with the method parser= in JSON.
 *
 */

static VALUE convert_encoding(VALUE source)
{
#ifdef HAVE_RUBY_ENCODING_H
  rb_encoding *enc = rb_enc_get(source);
  if (enc == rb_ascii8bit_encoding()) {
    if (OBJ_FROZEN(source)) {
      source = rb_str_dup(source);
    }
    FORCE_UTF8(source);
  } else {
    source = rb_str_conv_enc(source, rb_enc_get(source), rb_utf8_encoding());
  }
#endif
    return source;
}

/*
 * call-seq: new(source, opts => {})
 *
 * Creates a new JSON::Ext::Parser instance for the string _source_.
 *
 * Creates a new JSON::Ext::Parser instance for the string _source_.
 *
 * It will be configured by the _opts_ hash. _opts_ can have the following
 * keys:
 *
 * _opts_ can have the following keys:
 * * *max_nesting*: The maximum depth of nesting allowed in the parsed data
 *   structures. Disable depth checking with :max_nesting => false|nil|0, it
 *   defaults to 100.
 * * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
 *   defiance of RFC 4627 to be parsed by the Parser. This option defaults to
 *   false.
 * * *symbolize_names*: If set to true, returns symbols for the names
 *   (keys) in a JSON object. Otherwise strings are returned, which is
 *   also the default. It's not possible to use this option in
 *   conjunction with the *create_additions* option.
 * * *create_additions*: If set to false, the Parser doesn't create
 *   additions even if a matching class and create_id was found. This option
 *   defaults to false.
 * * *object_class*: Defaults to Hash
 * * *array_class*: Defaults to Array
 */
static VALUE cParser_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE source, opts;
    GET_PARSER_INIT;

    if (json->Vsource) {
        rb_raise(rb_eTypeError, "already initialized instance");
    }
#ifdef HAVE_RB_SCAN_ARGS_OPTIONAL_HASH
    rb_scan_args(argc, argv, "1:", &source, &opts);
#else
    rb_scan_args(argc, argv, "11", &source, &opts);
#endif
    if (!NIL_P(opts)) {
#ifndef HAVE_RB_SCAN_ARGS_OPTIONAL_HASH
        opts = rb_convert_type(opts, T_HASH, "Hash", "to_hash");
        if (NIL_P(opts)) {
            rb_raise(rb_eArgError, "opts needs to be like a hash");
        } else {
#endif
            VALUE tmp = ID2SYM(i_max_nesting);
            if (option_given_p(opts, tmp)) {
                VALUE max_nesting = rb_hash_aref(opts, tmp);
                if (RTEST(max_nesting)) {
                    Check_Type(max_nesting, T_FIXNUM);
                    json->max_nesting = FIX2INT(max_nesting);
                } else {
                    json->max_nesting = 0;
                }
            } else {
                json->max_nesting = 100;
            }
            tmp = ID2SYM(i_allow_nan);
            if (option_given_p(opts, tmp)) {
                json->allow_nan = RTEST(rb_hash_aref(opts, tmp)) ? 1 : 0;
            } else {
                json->allow_nan = 0;
            }
            tmp = ID2SYM(i_symbolize_names);
            if (option_given_p(opts, tmp)) {
                json->symbolize_names = RTEST(rb_hash_aref(opts, tmp)) ? 1 : 0;
            } else {
                json->symbolize_names = 0;
            }
            tmp = ID2SYM(i_create_additions);
            if (option_given_p(opts, tmp)) {
                json->create_additions = RTEST(rb_hash_aref(opts, tmp));
            } else {
                json->create_additions = 0;
            }
            if (json->symbolize_names && json->create_additions) {
              rb_raise(rb_eArgError,
                "options :symbolize_names and :create_additions cannot be "
                " used in conjunction");
            }
            tmp = ID2SYM(i_create_id);
            if (option_given_p(opts, tmp)) {
                json->create_id = rb_hash_aref(opts, tmp);
            } else {
                json->create_id = rb_funcall(mJSON, i_create_id, 0);
            }
            tmp = ID2SYM(i_object_class);
            if (option_given_p(opts, tmp)) {
                json->object_class = rb_hash_aref(opts, tmp);
            } else {
                json->object_class = Qnil;
            }
            tmp = ID2SYM(i_array_class);
            if (option_given_p(opts, tmp)) {
                json->array_class = rb_hash_aref(opts, tmp);
            } else {
                json->array_class = Qnil;
            }
            tmp = ID2SYM(i_match_string);
            if (option_given_p(opts, tmp)) {
                VALUE match_string = rb_hash_aref(opts, tmp);
                json->match_string = RTEST(match_string) ? match_string : Qnil;
            } else {
                json->match_string = Qnil;
            }
#ifndef HAVE_RB_SCAN_ARGS_OPTIONAL_HASH
        }
#endif
    } else {
        json->max_nesting = 100;
        json->allow_nan = 0;
        json->create_additions = 1;
        json->create_id = rb_funcall(mJSON, i_create_id, 0);
        json->object_class = Qnil;
        json->array_class = Qnil;
    }
    source = convert_encoding(StringValue(source));
    StringValue(source);
    json->len = RSTRING_LEN(source);
    json->source = RSTRING_PTR(source);;
    json->Vsource = source;
    return self;
}


#line 1820 "parser.c"
enum {JSON_start = 1};
enum {JSON_first_final = 10};
enum {JSON_error = 0};

enum {JSON_en_main = 1};


#line 728 "parser.rl"


/*
 * call-seq: parse()
 *
 *  Parses the current JSON text _source_ and returns the complete data
 *  structure as a result.
 */
static VALUE cParser_parse(VALUE self)
{
  char *p, *pe;
  int cs = EVIL;
  VALUE result = Qnil;
  GET_PARSER;


#line 1845 "parser.c"
	{
	cs = JSON_start;
	}

#line 744 "parser.rl"
  p = json->source;
  pe = p + json->len;

#line 1854 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
st1:
	if ( ++p == pe )
		goto _test_eof1;
case 1:
	switch( (*p) ) {
		case 13: goto st1;
		case 32: goto st1;
		case 34: goto tr2;
		case 45: goto tr2;
		case 47: goto st6;
		case 73: goto tr2;
		case 78: goto tr2;
		case 91: goto tr2;
		case 102: goto tr2;
		case 110: goto tr2;
		case 116: goto tr2;
		case 123: goto tr2;
	}
	if ( (*p) > 10 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto tr2;
	} else if ( (*p) >= 9 )
		goto st1;
	goto st0;
st0:
cs = 0;
	goto _out;
tr2:
#line 720 "parser.rl"
	{
        char *np = JSON_parse_value(json, p, pe, &result, 0);
        if (np == NULL) { p--; {p++; cs = 10; goto _out;} } else {p = (( np))-1;}
    }
	goto st10;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
#line 1898 "parser.c"
	switch( (*p) ) {
		case 13: goto st10;
		case 32: goto st10;
		case 47: goto st2;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st10;
	goto st0;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	switch( (*p) ) {
		case 42: goto st3;
		case 47: goto st5;
	}
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	if ( (*p) == 42 )
		goto st4;
	goto st3;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	switch( (*p) ) {
		case 42: goto st4;
		case 47: goto st10;
	}
	goto st3;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( (*p) == 10 )
		goto st10;
	goto st5;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	switch( (*p) ) {
		case 42: goto st7;
		case 47: goto st9;
	}
	goto st0;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	if ( (*p) == 42 )
		goto st8;
	goto st7;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	switch( (*p) ) {
		case 42: goto st8;
		case 47: goto st1;
	}
	goto st7;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
	if ( (*p) == 10 )
		goto st1;
	goto st9;
	}
	_test_eof1: cs = 1; goto _test_eof;
	_test_eof10: cs = 10; goto _test_eof;
	_test_eof2: cs = 2; goto _test_eof;
	_test_eof3: cs = 3; goto _test_eof;
	_test_eof4: cs = 4; goto _test_eof;
	_test_eof5: cs = 5; goto _test_eof;
	_test_eof6: cs = 6; goto _test_eof;
	_test_eof7: cs = 7; goto _test_eof;
	_test_eof8: cs = 8; goto _test_eof;
	_test_eof9: cs = 9; goto _test_eof;

	_test_eof: {}
	_out: {}
	}

#line 747 "parser.rl"

  if (cs >= JSON_first_final && p == pe) {
    return result;
  } else {
    rb_enc_raise(EXC_ENCODING eParserError, "%u: unexpected token at '%s'", __LINE__, p);
    return Qnil;
  }
}

static void JSON_mark(void *ptr)
{
    JSON_Parser *json = ptr;
    rb_gc_mark_maybe(json->Vsource);
    rb_gc_mark_maybe(json->create_id);
    rb_gc_mark_maybe(json->object_class);
    rb_gc_mark_maybe(json->array_class);
    rb_gc_mark_maybe(json->match_string);
}

static void JSON_free(void *ptr)
{
    JSON_Parser *json = ptr;
    fbuffer_free(json->fbuffer);
    ruby_xfree(json);
}

static size_t JSON_memsize(const void *ptr)
{
    const JSON_Parser *json = ptr;
    return sizeof(*json) + FBUFFER_CAPA(json->fbuffer);
}

#ifdef NEW_TYPEDDATA_WRAPPER
static const rb_data_type_t JSON_Parser_type = {
    "JSON/Parser",
    {JSON_mark, JSON_free, JSON_memsize,},
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
#endif
};
#endif

static VALUE cJSON_parser_s_allocate(VALUE klass)
{
    JSON_Parser *json;
    VALUE obj = TypedData_Make_Struct(klass, JSON_Parser, &JSON_Parser_type, json);
    json->fbuffer = fbuffer_alloc(0);
    return obj;
}

/*
 * call-seq: source()
 *
 * Returns a copy of the current _source_ string, that was used to construct
 * this Parser.
 */
static VALUE cParser_source(VALUE self)
{
    GET_PARSER;
    return rb_str_dup(json->Vsource);
}

void Init_parser(void)
{
    rb_require("json/common");
    mJSON = rb_define_module("JSON");
    mExt = rb_define_module_under(mJSON, "Ext");
    cParser = rb_define_class_under(mExt, "Parser", rb_cObject);
    eParserError = rb_path2class("JSON::ParserError");
    eNestingError = rb_path2class("JSON::NestingError");
    rb_define_alloc_func(cParser, cJSON_parser_s_allocate);
    rb_define_method(cParser, "initialize", cParser_initialize, -1);
    rb_define_method(cParser, "parse", cParser_parse, 0);
    rb_define_method(cParser, "source", cParser_source, 0);

    CNaN = rb_const_get(mJSON, rb_intern("NaN"));
    CInfinity = rb_const_get(mJSON, rb_intern("Infinity"));
    CMinusInfinity = rb_const_get(mJSON, rb_intern("MinusInfinity"));

    i_json_creatable_p = rb_intern("json_creatable?");
    i_json_create = rb_intern("json_create");
    i_create_id = rb_intern("create_id");
    i_create_additions = rb_intern("create_additions");
    i_chr = rb_intern("chr");
    i_max_nesting = rb_intern("max_nesting");
    i_allow_nan = rb_intern("allow_nan");
    i_symbolize_names = rb_intern("symbolize_names");
    i_object_class = rb_intern("object_class");
    i_array_class = rb_intern("array_class");
    i_match = rb_intern("match");
    i_match_string = rb_intern("match_string");
    i_key_p = rb_intern("key?");
    i_deep_const_get = rb_intern("deep_const_get");
    i_aset = rb_intern("[]=");
    i_aref = rb_intern("[]");
    i_leftshift = rb_intern("<<");
}

/*
 * Local variables:
 * mode: c
 * c-file-style: ruby
 * indent-tabs-mode: nil
 * End:
 */
