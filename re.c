/************************************************

  re.c -

  $Author: matz $
  $Date: 1994/12/19 08:30:12 $
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

/* Generate compiled regular expressions */
#if 'a' == 97   /* it's ascii */
static char casetable[] = {
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
>>> "You lose. You will need a translation table for your character set." <<<
#endif

#define min(a,b) (((a)>(b))?(b):(a))

int
str_cicmp(str1, str2)
    struct RString *str1, *str2;
{
    int len, i;
    char *p1, *p2;

    len = min(str1->len, str2->len);
    p1 = str1->ptr; p2 = str2->ptr;
    
    for (i = 0; i < len; i++, p1++, p2++) {
	if (casetable[*p1] != casetable[*p2])
	    return casetable[*p1] - casetable[*p2];
    }
    return str1->len - str2->len;
}

Regexp*
make_regexp(s, len)
char *s;
int len;
{
    Regexp *rp;
    char *err;
    register int c;

    /* Handle escaped characters first. */

    /* Build a copy of the string (in dest) with the
       escaped characters translated,  and generate the regex
       from that.  
    */

    rp = ALLOC(Regexp);
    memset((char *)rp, 0, sizeof(Regexp));
    rp->pat.buffer = ALLOC_N(char, 16);
    rp->pat.allocated = 16;
    rp->pat.fastmap = ALLOC_N(char, 256);

    if ((err = re_compile_pattern(s, (size_t)len, &(rp->pat))) != NULL)
	Fail("%s: /%s/", err, s);
    return rp;
}

struct match {
    UINT len;
    char *ptr;
    struct re_registers regs;
};

static void
free_match(data)
    struct match *data;
{
    free(data->ptr);
}

VALUE last_match_data;

int
research(reg, str, start, ignorecase)
    struct RRegexp *reg;
    struct RString *str;
    int start;
    int ignorecase;
{
    int result;

    if (FL_TEST(reg, FL_USER1)) { /* case-flag set for the object */
	ignorecase = FL_TEST(reg, FL_USER2); /* case-flag */
    }
    if (ignorecase)
	reg->ptr->pat.translate = casetable;
    else
	reg->ptr->pat.translate = NULL;

    if (start >= str->len) return -1;
    result = re_search(&(reg->ptr->pat), str->ptr, str->len,
		       start, str->len - start, &(reg->ptr->regs));

    if (result >= 0) {
	struct RData *obj;
	struct match *data;
	int beg, i;

	data = ALLOC(struct match);
	obj = (struct RData*)data_new(data, free_match, Qnil);

	data->len = str->len;
	data->ptr = ALLOC_N(char, str->len+1);
	memcpy(data->ptr, str->ptr, data->len);
	data->ptr[data->len] = '\0';
	data->regs = reg->ptr->regs;

	last_match_data = (VALUE)obj;
    }

    return result;
}

static VALUE
nth_match(nth)
    int nth;
{
    if (nth >= RE_NREGS) {
	Fail("argument out of range %d, %d", nth, RE_NREGS);
    }
    if (last_match_data) {
	int start, end, len;
	struct match *match;

	match = (struct match*)DATA_PTR(last_match_data);
	start = match->regs.start[nth];
	if (start == -1) return Qnil;
	end   = match->regs.end[nth];
	len = end - start;
	return str_new(match->ptr + start, len);
    }
    return Qnil;
}

VALUE
re_last_match(id)
    ID id;
{
    return nth_match(0);
}

static VALUE
re_match_pre()
{
    struct match *match;

    if (!last_match_data) return Qnil;

    match = (struct match*)DATA_PTR(last_match_data);
    return str_new(match->ptr, match->regs.start[0]);
}

static VALUE
re_match_post()
{
    struct match *match;

    if (!last_match_data) return Qnil;

    match = (struct match*)DATA_PTR(last_match_data);
    return str_new(match->ptr+match->regs.end[0], match->ptr+match->len);
}

static VALUE
re_match_last()
{
    struct match *match;
    int i;

    if (!last_match_data) return Qnil;

    match = (struct match*)DATA_PTR(last_match_data);
    for (i=0; i<RE_NREGS; i++) {
	if (match->regs.start[i] == -1) break;
    }
    i--;
    return nth_match(i);
}

static VALUE
get_match_data(id, nth)
    ID id;
    int nth;
{
    return nth_match(nth);
}

static VALUE
store_match_data(val)
    struct RArray *val;
{
    Check_Type(val, T_DATA);
    return (VALUE)val;
}

void
reg_free(rp)
Regexp *rp;
{
    free(rp->pat.buffer);
    free(rp->pat.fastmap);
    free(rp);
}

void
reg_error(s)
const char *s;
{
    Fail(s);
}

VALUE ignorecase;
VALUE C_Regexp;

static VALUE
regexp_new_1(class, s, len)
    VALUE class;
    char *s;
    int len;
{
    NEWOBJ(re, struct RRegexp);
    OBJSETUP(re, class, T_REGEXP);

    re->ptr = make_regexp(s, len);
    re->str = ALLOC_N(char, len+1);
    memcpy(re->str, s, len);
    re->str[len] = '\0';
    re->len = len;
    return (VALUE)re;
}

VALUE
regexp_new(s, len)
    char *s;
    int len;
{
    return regexp_new_1(C_Regexp, s, len);
}

static VALUE str_cache, reg_cache;

VALUE
re_regcomp(str)
    struct RString *str;
{
    if (str_cache && RSTRING(str_cache)->len == str->len &&
	memcmp(RSTRING(str_cache)->ptr, str->ptr, str->len))
	return reg_cache;

    str_cache = (VALUE)str;
    return reg_cache = regexp_new(str->ptr, str->len);
}

VALUE
Freg_match(re, str)
    struct RRegexp *re;
    struct RString *str;
{
    int start;

    Check_Type(str, T_STRING);
    start = research(re, str, 0, ignorecase);
    if (start == -1) {
	return Qnil;
    }
    return INT2FIX(start);
}

VALUE
Freg_match2(re)
    struct RRegexp *re;
{
    extern VALUE rb_lastline;
    int start;

    if (TYPE(rb_lastline) != T_STRING)
	Fail("$_ is not a string");

    start = research(re, rb_lastline, 0, ignorecase);
    if (start == -1) {
	return Qnil;
    }
    return INT2FIX(start);
}

static VALUE
Sreg_new(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE src, reg;

    if (argc == 0 || argc > 2) {
	Fail("wrong # of argument");
    }

    src = argv[0];
    switch (TYPE(src)) {
      case T_STRING:
	reg = regexp_new_1(Qself, RREGEXP(src)->ptr, RREGEXP(src)->len);

      case T_REGEXP:
	reg = regexp_new_1(Qself, RREGEXP(src)->str, RREGEXP(src)->len);

      default:
	Check_Type(src, T_STRING);
    }

    if (argc == 2) {
	FL_SET(reg, FL_USER1);
	if (argv[1]) {
	    FL_SET(reg, FL_USER2);
	}
	else {
	    FL_UNSET(reg, FL_USER2);
	}
    }

    return Qnil;
}

static VALUE
Freg_clone(re)
    struct RRegexp *re;
{
    return regexp_new_1(CLASS_OF(re), re->str, re->len);
}

VALUE
re_regsub(str)
    struct RString *str;
{
    VALUE val = Qnil;
    char *p, *s, *e, c;
    int no, len;

    p = s = str->ptr;
    e = s + str->len;

    while (s < e) {
	char *ss = s;

	c = *s++;
	if (c == '&')
	    no = 0;
	else if (c == '\\' && '0' <= *s && *s <= '9')
	    no = *s++ - '0';
	else
	    no = -1;

	if (no >= 0) {
	    if (val == Qnil) {
		val = str_new(p, ss-p);
	    }
	    else {
		str_cat(val, p, ss-p);
	    }
	    p = s;
	}

	if (no < 0) {   /* Ordinary character. */
	    if (c == '\\' && (*s == '\\' || *s == '&'))
		p = ++s;
	} else if (last_match_data) {
	    struct match *match;

#define BEG(no) match->regs.start[no]
#define END(no) match->regs.end[no]

	    match = (struct match*)DATA_PTR(last_match_data);
	    if (BEG(no) == -1) continue;
	    str_cat(val, match->ptr+BEG(no), END(no)-BEG(no));
	}
    }

    if (val == Qnil) return (VALUE)str;
    if (p < e) {
	str_cat(val, p, e-p);
    }
    if (RSTRING(val)->len == 0) {
	return (VALUE)str;
    }
    return val;
}

void
rb_set_kanjicode(code)
    char *code;
{
    if (code == Qnil) goto set_no_conversion;

    switch (code[0]) {
      case 'E':
      case 'e':
	obscure_syntax &= ~RE_MBCTYPE_MASK;
	obscure_syntax |= RE_MBCTYPE_EUC;
	break;
      case 'S':
      case 's':
	obscure_syntax &= ~RE_MBCTYPE_MASK;
	obscure_syntax |= RE_MBCTYPE_SJIS;
	break;
      default:
      case 'N':
      case 'n':
      set_no_conversion:
	obscure_syntax &= ~RE_MBCTYPE_MASK;
	break;
    }
    re_set_syntax(obscure_syntax);
}

static VALUE
kanji_var_get()
{
    switch (obscure_syntax & RE_MBCTYPE_MASK) {
      case RE_MBCTYPE_SJIS:
	return str_new2("SJIS");
      case RE_MBCTYPE_EUC:
	return str_new2("EUC");
      default:
	return Qnil;
    }
}

static void
kanji_var_set(val)
    struct RString *val;
{
    if (val == Qnil) rb_set_kanjicode(Qnil);
    Check_Type(val, T_STRING);
    rb_set_kanjicode(val->ptr);
}

void
Init_Regexp()
{
    obscure_syntax = RE_NO_BK_PARENS | RE_NO_BK_VBAR
	| RE_CONTEXT_INDEP_OPS | RE_INTERVALS
	| RE_NO_BK_CURLY_BRACES
	| RE_MBCTYPE_EUC;

    rb_define_variable("$~", last_match_data, Qnil, store_match_data, 0);

    rb_define_variable("$&", Qnil, re_last_match, Qnil, 0);
    rb_define_variable("$`", Qnil, re_match_pre,  Qnil, 0);
    rb_define_variable("$'", Qnil, re_match_post, Qnil, 0);
    rb_define_variable("$+", Qnil, re_match_last, Qnil, 0);

    rb_define_variable("$1", Qnil, get_match_data, Qnil, 1);
    rb_define_variable("$2", Qnil, get_match_data, Qnil, 2);
    rb_define_variable("$3", Qnil, get_match_data, Qnil, 3);
    rb_define_variable("$4", Qnil, get_match_data, Qnil, 4);
    rb_define_variable("$5", Qnil, get_match_data, Qnil, 5);
    rb_define_variable("$6", Qnil, get_match_data, Qnil, 6);
    rb_define_variable("$7", Qnil, get_match_data, Qnil, 7);
    rb_define_variable("$8", Qnil, get_match_data, Qnil, 8);
    rb_define_variable("$9", Qnil, get_match_data, Qnil, 9);

    rb_define_variable("$KANJI", Qnil, kanji_var_get, kanji_var_set, 0);

    rb_define_variable("$=", &ignorecase, Qnil, Qnil, 0);

    C_Regexp  = rb_define_class("Regexp", C_Object);
    rb_define_single_method(C_Regexp, "new", Sreg_new, -1);
    rb_define_single_method(C_Regexp, "compile", Sreg_new, -1);

    rb_define_method(C_Regexp, "=~", Freg_match, 1);
    rb_define_method(C_Regexp, "~", Freg_match2, 0);

    rb_global_variable(&str_cache);
    rb_global_variable(&reg_cache);
}
