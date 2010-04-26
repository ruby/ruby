
#line 1 "parser.rl"
#include "parser.h"

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
    result = (result << 4) | b;
    b = digit_values[p[1]];
    result = (result << 4) | b;
    if (b < 0) return UNI_REPLACEMENT_CHAR;
    b = digit_values[p[2]];
    result = (result << 4) | b;
    if (b < 0) return UNI_REPLACEMENT_CHAR;
    b = digit_values[p[3]];
    result = (result << 4) | b;
    if (b < 0) return UNI_REPLACEMENT_CHAR;
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

#ifdef HAVE_RUBY_ENCODING_H
static VALUE CEncoding_ASCII_8BIT, CEncoding_UTF_8, CEncoding_UTF_16BE,
    CEncoding_UTF_16LE, CEncoding_UTF_32BE, CEncoding_UTF_32LE;
static ID i_encoding, i_encode, i_encode_bang, i_force_encoding;
#else
static ID i_iconv;
#endif

static VALUE mJSON, mExt, cParser, eParserError, eNestingError;
static VALUE CNaN, CInfinity, CMinusInfinity;

static ID i_json_creatable_p, i_json_create, i_create_id, i_create_additions,
          i_chr, i_max_nesting, i_allow_nan, i_symbolize_names, i_object_class,
          i_array_class, i_key_p, i_deep_const_get;


#line 108 "parser.rl"



#line 90 "parser.c"
static const int JSON_object_start = 1;
static const int JSON_object_first_final = 27;
static const int JSON_object_error = 0;

static const int JSON_object_en_main = 1;


#line 143 "parser.rl"


static char *JSON_parse_object(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    VALUE last_name = Qnil;
    VALUE object_class = json->object_class;

    if (json->max_nesting && json->current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", json->current_nesting);
    }

    *result = NIL_P(object_class) ? rb_hash_new() : rb_class_new_instance(0, 0, object_class);

    
#line 114 "parser.c"
	{
	cs = JSON_object_start;
	}

#line 158 "parser.rl"
    
#line 121 "parser.c"
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
#line 127 "parser.rl"
	{
        json->parsing_name = 1;
        char *np = JSON_parse_string(json, p, pe, &last_name);
        json->parsing_name = 0;
        if (np == NULL) { p--; {p++; cs = 3; goto _out;} } else {p = (( np))-1;}
    }
	goto st3;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
#line 161 "parser.c"
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
#line 116 "parser.rl"
	{
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, p, pe, &v); 
        if (np == NULL) {
            p--; {p++; cs = 9; goto _out;}
        } else {
            rb_hash_aset(*result, last_name, v);
            {p = (( np))-1;}
        }
    }
	goto st9;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
#line 244 "parser.c"
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
#line 134 "parser.rl"
	{ p--; {p++; cs = 27; goto _out;} }
	goto st27;
st27:
	if ( ++p == pe )
		goto _test_eof27;
case 27:
#line 340 "parser.c"
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

#line 159 "parser.rl"

    if (cs >= JSON_object_first_final) {
        if (RTEST(json->create_id)) {
            VALUE klassname = rb_hash_aref(*result, json->create_id);
            if (!NIL_P(klassname)) {
                VALUE klass = rb_funcall(mJSON, i_deep_const_get, 1, klassname);
                if RTEST(rb_funcall(klass, i_json_creatable_p, 0)) {
                    *result = rb_funcall(klass, i_json_create, 1, *result);
                }
            }
        }
        return p + 1;
    } else {
        return NULL;
    }
}


#line 457 "parser.c"
static const int JSON_value_start = 1;
static const int JSON_value_first_final = 21;
static const int JSON_value_error = 0;

static const int JSON_value_en_main = 1;


#line 257 "parser.rl"


static char *JSON_parse_value(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    
#line 473 "parser.c"
	{
	cs = JSON_value_start;
	}

#line 264 "parser.rl"
    
#line 480 "parser.c"
	{
	if ( p == pe )
		goto _test_eof;
	switch ( cs )
	{
case 1:
	switch( (*p) ) {
		case 34: goto tr0;
		case 45: goto tr2;
		case 73: goto st2;
		case 78: goto st9;
		case 91: goto tr5;
		case 102: goto st11;
		case 110: goto st15;
		case 116: goto st18;
		case 123: goto tr9;
	}
	if ( 48 <= (*p) && (*p) <= 57 )
		goto tr2;
	goto st0;
st0:
cs = 0;
	goto _out;
tr0:
#line 205 "parser.rl"
	{
        char *np = JSON_parse_string(json, p, pe, result);
        if (np == NULL) { p--; {p++; cs = 21; goto _out;} } else {p = (( np))-1;}
    }
	goto st21;
tr2:
#line 210 "parser.rl"
	{
        char *np;
        if(pe > p + 9 && !strncmp(MinusInfinity, p, 9)) {
            if (json->allow_nan) {
                *result = CMinusInfinity;
                {p = (( p + 10))-1;}
                p--; {p++; cs = 21; goto _out;}
            } else {
                rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p);
            }
        }
        np = JSON_parse_float(json, p, pe, result);
        if (np != NULL) {p = (( np))-1;}
        np = JSON_parse_integer(json, p, pe, result);
        if (np != NULL) {p = (( np))-1;}
        p--; {p++; cs = 21; goto _out;}
    }
	goto st21;
tr5:
#line 228 "parser.rl"
	{ 
        char *np;
        json->current_nesting++;
        np = JSON_parse_array(json, p, pe, result);
        json->current_nesting--;
        if (np == NULL) { p--; {p++; cs = 21; goto _out;} } else {p = (( np))-1;}
    }
	goto st21;
tr9:
#line 236 "parser.rl"
	{ 
        char *np;
        json->current_nesting++;
        np =  JSON_parse_object(json, p, pe, result);
        json->current_nesting--;
        if (np == NULL) { p--; {p++; cs = 21; goto _out;} } else {p = (( np))-1;}
    }
	goto st21;
tr16:
#line 198 "parser.rl"
	{
        if (json->allow_nan) {
            *result = CInfinity;
        } else {
            rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p - 8);
        }
    }
	goto st21;
tr18:
#line 191 "parser.rl"
	{
        if (json->allow_nan) {
            *result = CNaN;
        } else {
            rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p - 2);
        }
    }
	goto st21;
tr22:
#line 185 "parser.rl"
	{
        *result = Qfalse;
    }
	goto st21;
tr25:
#line 182 "parser.rl"
	{
        *result = Qnil;
    }
	goto st21;
tr28:
#line 188 "parser.rl"
	{
        *result = Qtrue;
    }
	goto st21;
st21:
	if ( ++p == pe )
		goto _test_eof21;
case 21:
#line 244 "parser.rl"
	{ p--; {p++; cs = 21; goto _out;} }
#line 595 "parser.c"
	goto st0;
st2:
	if ( ++p == pe )
		goto _test_eof2;
case 2:
	if ( (*p) == 110 )
		goto st3;
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	if ( (*p) == 102 )
		goto st4;
	goto st0;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	if ( (*p) == 105 )
		goto st5;
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( (*p) == 110 )
		goto st6;
	goto st0;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	if ( (*p) == 105 )
		goto st7;
	goto st0;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	if ( (*p) == 116 )
		goto st8;
	goto st0;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	if ( (*p) == 121 )
		goto tr16;
	goto st0;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
	if ( (*p) == 97 )
		goto st10;
	goto st0;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
	if ( (*p) == 78 )
		goto tr18;
	goto st0;
st11:
	if ( ++p == pe )
		goto _test_eof11;
case 11:
	if ( (*p) == 97 )
		goto st12;
	goto st0;
st12:
	if ( ++p == pe )
		goto _test_eof12;
case 12:
	if ( (*p) == 108 )
		goto st13;
	goto st0;
st13:
	if ( ++p == pe )
		goto _test_eof13;
case 13:
	if ( (*p) == 115 )
		goto st14;
	goto st0;
st14:
	if ( ++p == pe )
		goto _test_eof14;
case 14:
	if ( (*p) == 101 )
		goto tr22;
	goto st0;
st15:
	if ( ++p == pe )
		goto _test_eof15;
case 15:
	if ( (*p) == 117 )
		goto st16;
	goto st0;
st16:
	if ( ++p == pe )
		goto _test_eof16;
case 16:
	if ( (*p) == 108 )
		goto st17;
	goto st0;
st17:
	if ( ++p == pe )
		goto _test_eof17;
case 17:
	if ( (*p) == 108 )
		goto tr25;
	goto st0;
st18:
	if ( ++p == pe )
		goto _test_eof18;
case 18:
	if ( (*p) == 114 )
		goto st19;
	goto st0;
st19:
	if ( ++p == pe )
		goto _test_eof19;
case 19:
	if ( (*p) == 117 )
		goto st20;
	goto st0;
st20:
	if ( ++p == pe )
		goto _test_eof20;
case 20:
	if ( (*p) == 101 )
		goto tr28;
	goto st0;
	}
	_test_eof21: cs = 21; goto _test_eof; 
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

	_test_eof: {}
	_out: {}
	}

#line 265 "parser.rl"

    if (cs >= JSON_value_first_final) {
        return p;
    } else {
        return NULL;
    }
}


#line 766 "parser.c"
static const int JSON_integer_start = 1;
static const int JSON_integer_first_final = 5;
static const int JSON_integer_error = 0;

static const int JSON_integer_en_main = 1;


#line 281 "parser.rl"


static char *JSON_parse_integer(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    
#line 782 "parser.c"
	{
	cs = JSON_integer_start;
	}

#line 288 "parser.rl"
    json->memo = p;
    
#line 790 "parser.c"
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
		goto st4;
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
		goto st4;
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st0;
	goto tr4;
tr4:
#line 278 "parser.rl"
	{ p--; {p++; cs = 5; goto _out;} }
	goto st5;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
#line 831 "parser.c"
	goto st0;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st4;
	goto tr4;
	}
	_test_eof2: cs = 2; goto _test_eof; 
	_test_eof3: cs = 3; goto _test_eof; 
	_test_eof5: cs = 5; goto _test_eof; 
	_test_eof4: cs = 4; goto _test_eof; 

	_test_eof: {}
	_out: {}
	}

#line 290 "parser.rl"

    if (cs >= JSON_integer_first_final) {
        long len = p - json->memo;
        *result = rb_Integer(rb_str_new(json->memo, len));
        return p + 1;
    } else {
        return NULL;
    }
}


#line 862 "parser.c"
static const int JSON_float_start = 1;
static const int JSON_float_first_final = 10;
static const int JSON_float_error = 0;

static const int JSON_float_en_main = 1;


#line 312 "parser.rl"


static char *JSON_parse_float(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    
#line 878 "parser.c"
	{
	cs = JSON_float_start;
	}

#line 319 "parser.rl"
    json->memo = p;
    
#line 886 "parser.c"
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
		goto st9;
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
		goto st9;
	goto st0;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
	switch( (*p) ) {
		case 46: goto st4;
		case 69: goto st6;
		case 101: goto st6;
	}
	goto st0;
st4:
	if ( ++p == pe )
		goto _test_eof4;
case 4:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st5;
	goto st0;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	switch( (*p) ) {
		case 69: goto st6;
		case 101: goto st6;
	}
	if ( (*p) > 46 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st5;
	} else if ( (*p) >= 45 )
		goto st0;
	goto tr7;
tr7:
#line 306 "parser.rl"
	{ p--; {p++; cs = 10; goto _out;} }
	goto st10;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
#line 951 "parser.c"
	goto st0;
st6:
	if ( ++p == pe )
		goto _test_eof6;
case 6:
	switch( (*p) ) {
		case 43: goto st7;
		case 45: goto st7;
	}
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st8;
	goto st0;
st7:
	if ( ++p == pe )
		goto _test_eof7;
case 7:
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st8;
	goto st0;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
	switch( (*p) ) {
		case 69: goto st0;
		case 101: goto st0;
	}
	if ( (*p) > 46 ) {
		if ( 48 <= (*p) && (*p) <= 57 )
			goto st8;
	} else if ( (*p) >= 45 )
		goto st0;
	goto tr7;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
	switch( (*p) ) {
		case 46: goto st4;
		case 69: goto st6;
		case 101: goto st6;
	}
	if ( 48 <= (*p) && (*p) <= 57 )
		goto st9;
	goto st0;
	}
	_test_eof2: cs = 2; goto _test_eof; 
	_test_eof3: cs = 3; goto _test_eof; 
	_test_eof4: cs = 4; goto _test_eof; 
	_test_eof5: cs = 5; goto _test_eof; 
	_test_eof10: cs = 10; goto _test_eof; 
	_test_eof6: cs = 6; goto _test_eof; 
	_test_eof7: cs = 7; goto _test_eof; 
	_test_eof8: cs = 8; goto _test_eof; 
	_test_eof9: cs = 9; goto _test_eof; 

	_test_eof: {}
	_out: {}
	}

#line 321 "parser.rl"

    if (cs >= JSON_float_first_final) {
        long len = p - json->memo;
        *result = rb_Float(rb_str_new(json->memo, len));
        return p + 1;
    } else {
        return NULL;
    }
}



#line 1025 "parser.c"
static const int JSON_array_start = 1;
static const int JSON_array_first_final = 17;
static const int JSON_array_error = 0;

static const int JSON_array_en_main = 1;


#line 357 "parser.rl"


static char *JSON_parse_array(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;
    VALUE array_class = json->array_class;

    if (json->max_nesting && json->current_nesting > json->max_nesting) {
        rb_raise(eNestingError, "nesting of %d is too deep", json->current_nesting);
    }
    *result = NIL_P(array_class) ? rb_ary_new() : rb_class_new_instance(0, 0, array_class);

    
#line 1047 "parser.c"
	{
	cs = JSON_array_start;
	}

#line 370 "parser.rl"
    
#line 1054 "parser.c"
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
#line 338 "parser.rl"
	{
        VALUE v = Qnil;
        char *np = JSON_parse_value(json, p, pe, &v); 
        if (np == NULL) {
            p--; {p++; cs = 3; goto _out;}
        } else {
            rb_ary_push(*result, v);
            {p = (( np))-1;}
        }
    }
	goto st3;
st3:
	if ( ++p == pe )
		goto _test_eof3;
case 3:
#line 1109 "parser.c"
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
#line 349 "parser.rl"
	{ p--; {p++; cs = 17; goto _out;} }
	goto st17;
st17:
	if ( ++p == pe )
		goto _test_eof17;
case 17:
#line 1216 "parser.c"
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

#line 371 "parser.rl"

    if(cs >= JSON_array_first_final) {
        return p + 1;
    } else {
        rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p);
        return NULL;
    }
}

static VALUE json_string_unescape(VALUE result, char *string, char *stringEnd)
{
    char *p = string, *pe = string, *unescape;
    int unescape_len;

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
                        return Qnil;
                    } else {
                        char buf[4];
                        UTF32 ch = unescape_unicode((unsigned char *) ++pe);
                        pe += 3;
                        if (UNI_SUR_HIGH_START == (ch & 0xFC00)) {
                            pe++;
                            if (pe > stringEnd - 6) return Qnil;
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


#line 1353 "parser.c"
static const int JSON_string_start = 1;
static const int JSON_string_first_final = 8;
static const int JSON_string_error = 0;

static const int JSON_string_en_main = 1;


#line 470 "parser.rl"


static char *JSON_parse_string(JSON_Parser *json, char *p, char *pe, VALUE *result)
{
    int cs = EVIL;

    *result = rb_str_buf_new(0);
    
#line 1370 "parser.c"
	{
	cs = JSON_string_start;
	}

#line 478 "parser.rl"
    json->memo = p;
    
#line 1378 "parser.c"
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
#line 456 "parser.rl"
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
#line 467 "parser.rl"
	{ p--; {p++; cs = 8; goto _out;} }
	goto st8;
st8:
	if ( ++p == pe )
		goto _test_eof8;
case 8:
#line 1421 "parser.c"
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

#line 480 "parser.rl"

    if (json->symbolize_names && json->parsing_name) {
      *result = rb_str_intern(*result);
    }
    if (cs >= JSON_string_first_final) {
        return p + 1;
    } else {
        return NULL;
    }
}



#line 1511 "parser.c"
static const int JSON_start = 1;
static const int JSON_first_final = 10;
static const int JSON_error = 0;

static const int JSON_en_main = 1;


#line 517 "parser.rl"


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
    char *ptr = RSTRING_PTR(source);
    long len = RSTRING_LEN(source);
    if (len < 2) {
        rb_raise(eParserError, "A JSON text must at least contain two octets!");
    }
#ifdef HAVE_RUBY_ENCODING_H
    {
        VALUE encoding = rb_funcall(source, i_encoding, 0);
        if (encoding == CEncoding_ASCII_8BIT) {
            if (len >= 4 &&  ptr[0] == 0 && ptr[1] == 0 && ptr[2] == 0) {
                source = rb_str_dup(source);
                rb_funcall(source, i_force_encoding, 1, CEncoding_UTF_32BE);
                source = rb_funcall(source, i_encode_bang, 1, CEncoding_UTF_8);
            } else if (len >= 4 && ptr[0] == 0 && ptr[2] == 0) {
                source = rb_str_dup(source);
                rb_funcall(source, i_force_encoding, 1, CEncoding_UTF_16BE);
                source = rb_funcall(source, i_encode_bang, 1, CEncoding_UTF_8);
            } else if (len >= 4 && ptr[1] == 0 && ptr[2] == 0 && ptr[3] == 0) {
                source = rb_str_dup(source);
                rb_funcall(source, i_force_encoding, 1, CEncoding_UTF_32LE);
                source = rb_funcall(source, i_encode_bang, 1, CEncoding_UTF_8);
            } else if (len >= 4 && ptr[1] == 0 && ptr[3] == 0) {
                source = rb_str_dup(source);
                rb_funcall(source, i_force_encoding, 1, CEncoding_UTF_16LE);
                source = rb_funcall(source, i_encode_bang, 1, CEncoding_UTF_8);
            } else {
                FORCE_UTF8(source);
            }
        } else {
            source = rb_funcall(source, i_encode, 1, CEncoding_UTF_8);
        }
    }
#else
    if (len >= 4 &&  ptr[0] == 0 && ptr[1] == 0 && ptr[2] == 0) {
      source = rb_funcall(mJSON, i_iconv, 3, rb_str_new2("utf-8"), rb_str_new2("utf-32be"), source);
    } else if (len >= 4 && ptr[0] == 0 && ptr[2] == 0) {
      source = rb_funcall(mJSON, i_iconv, 3, rb_str_new2("utf-8"), rb_str_new2("utf-16be"), source);
    } else if (len >= 4 && ptr[1] == 0 && ptr[2] == 0 && ptr[3] == 0) {
      source = rb_funcall(mJSON, i_iconv, 3, rb_str_new2("utf-8"), rb_str_new2("utf-32le"), source);
    } else if (len >= 4 && ptr[1] == 0 && ptr[3] == 0) {
      source = rb_funcall(mJSON, i_iconv, 3, rb_str_new2("utf-8"), rb_str_new2("utf-16le"), source);
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
 *   defaults to 19.
 * * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
 *   defiance of RFC 4627 to be parsed by the Parser. This option defaults to
 *   false.
 * * *symbolize_names*: If set to true, returns symbols for the names
 *   (keys) in a JSON object. Otherwise strings are returned, which is also
 *   the default.
 * * *create_additions*: If set to false, the Parser doesn't create
 *   additions even if a matchin class and create_id was found. This option
 *   defaults to true.
 * * *object_class*: Defaults to Hash
 * * *array_class*: Defaults to Array
 */
static VALUE cParser_initialize(int argc, VALUE *argv, VALUE self)
{
    char *ptr;
    long len;
    VALUE source, opts;
    GET_PARSER;
    rb_scan_args(argc, argv, "11", &source, &opts);
    source = convert_encoding(StringValue(source));
    ptr = RSTRING_PTR(source);
    len = RSTRING_LEN(source);
    if (!NIL_P(opts)) {
        opts = rb_convert_type(opts, T_HASH, "Hash", "to_hash");
        if (NIL_P(opts)) {
            rb_raise(rb_eArgError, "opts needs to be like a hash");
        } else {
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
                json->max_nesting = 19;
            }
            tmp = ID2SYM(i_allow_nan);
            if (option_given_p(opts, tmp)) {
                VALUE allow_nan = rb_hash_aref(opts, tmp);
                json->allow_nan = RTEST(allow_nan) ? 1 : 0;
            } else {
                json->allow_nan = 0;
            }
            tmp = ID2SYM(i_symbolize_names);
            if (option_given_p(opts, tmp)) {
                VALUE symbolize_names = rb_hash_aref(opts, tmp);
                json->symbolize_names = RTEST(symbolize_names) ? 1 : 0;
            } else {
                json->symbolize_names = 0;
            }
            tmp = ID2SYM(i_create_additions);
            if (option_given_p(opts, tmp)) {
                VALUE create_additions = rb_hash_aref(opts, tmp);
                if (RTEST(create_additions)) {
                    json->create_id = rb_funcall(mJSON, i_create_id, 0);
                } else {
                    json->create_id = Qnil;
                }
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
        }
    } else {
        json->max_nesting = 19;
        json->allow_nan = 0;
        json->create_id = rb_funcall(mJSON, i_create_id, 0);
        json->object_class = Qnil;
        json->array_class = Qnil;
    }
    json->current_nesting = 0;
    json->len = len;
    json->source = ptr;
    json->Vsource = source;
    return self;
}

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

    
#line 1701 "parser.c"
	{
	cs = JSON_start;
	}

#line 698 "parser.rl"
    p = json->source;
    pe = p + json->len;
    
#line 1710 "parser.c"
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
		case 47: goto st2;
		case 91: goto tr3;
		case 123: goto tr4;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st1;
	goto st0;
st0:
cs = 0;
	goto _out;
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
		case 47: goto st1;
	}
	goto st3;
st5:
	if ( ++p == pe )
		goto _test_eof5;
case 5:
	if ( (*p) == 10 )
		goto st1;
	goto st5;
tr3:
#line 506 "parser.rl"
	{
        char *np;
        json->current_nesting = 1;
        np = JSON_parse_array(json, p, pe, &result);
        if (np == NULL) { p--; {p++; cs = 10; goto _out;} } else {p = (( np))-1;}
    }
	goto st10;
tr4:
#line 499 "parser.rl"
	{
        char *np;
        json->current_nesting = 1;
        np = JSON_parse_object(json, p, pe, &result);
        if (np == NULL) { p--; {p++; cs = 10; goto _out;} } else {p = (( np))-1;}
    }
	goto st10;
st10:
	if ( ++p == pe )
		goto _test_eof10;
case 10:
#line 1787 "parser.c"
	switch( (*p) ) {
		case 13: goto st10;
		case 32: goto st10;
		case 47: goto st6;
	}
	if ( 9 <= (*p) && (*p) <= 10 )
		goto st10;
	goto st0;
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
		case 47: goto st10;
	}
	goto st7;
st9:
	if ( ++p == pe )
		goto _test_eof9;
case 9:
	if ( (*p) == 10 )
		goto st10;
	goto st9;
	}
	_test_eof1: cs = 1; goto _test_eof; 
	_test_eof2: cs = 2; goto _test_eof; 
	_test_eof3: cs = 3; goto _test_eof; 
	_test_eof4: cs = 4; goto _test_eof; 
	_test_eof5: cs = 5; goto _test_eof; 
	_test_eof10: cs = 10; goto _test_eof; 
	_test_eof6: cs = 6; goto _test_eof; 
	_test_eof7: cs = 7; goto _test_eof; 
	_test_eof8: cs = 8; goto _test_eof; 
	_test_eof9: cs = 9; goto _test_eof; 

	_test_eof: {}
	_out: {}
	}

#line 701 "parser.rl"

    if (cs >= JSON_first_final && p == pe) {
        return result;
    } else {
        rb_raise(eParserError, "%u: unexpected token at '%s'", __LINE__, p);
        return Qnil;
    }
}

static JSON_Parser *JSON_allocate()
{
    JSON_Parser *json = ALLOC(JSON_Parser);
    MEMZERO(json, JSON_Parser, 1);
    return json;
}

static void JSON_mark(JSON_Parser *json)
{
    rb_gc_mark_maybe(json->Vsource);
    rb_gc_mark_maybe(json->create_id);
    rb_gc_mark_maybe(json->object_class);
    rb_gc_mark_maybe(json->array_class);
}

static void JSON_free(JSON_Parser *json)
{
    ruby_xfree(json);
}

static VALUE cJSON_parser_s_allocate(VALUE klass)
{
    JSON_Parser *json = JSON_allocate();
    return Data_Wrap_Struct(klass, JSON_mark, JSON_free, json);
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

void Init_parser()
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
    i_key_p = rb_intern("key?");
    i_deep_const_get = rb_intern("deep_const_get");
#ifdef HAVE_RUBY_ENCODING_H
    CEncoding_UTF_8 = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("utf-8"));
    CEncoding_UTF_16BE = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("utf-16be"));
    CEncoding_UTF_16LE = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("utf-16le"));
    CEncoding_UTF_32BE = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("utf-32be"));
    CEncoding_UTF_32LE = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("utf-32le"));
    CEncoding_ASCII_8BIT = rb_funcall(rb_path2class("Encoding"), rb_intern("find"), 1, rb_str_new2("ascii-8bit"));
    i_encoding = rb_intern("encoding");
    i_encode = rb_intern("encode");
    i_encode_bang = rb_intern("encode!");
    i_force_encoding = rb_intern("force_encoding");
#else
    i_iconv = rb_intern("iconv");
#endif
}
