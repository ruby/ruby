/************************************************

  re.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:49 $
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

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

static Regexp*
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
    MEMZERO((char *)rp, Regexp, 1);
    rp->buffer = ALLOC_N(char, 16);
    rp->allocated = 16;
    rp->fastmap = ALLOC_N(char, 256);

    if ((err = re_compile_pattern(s, (size_t)len, rp)) != NULL)
	Fail("%s: /%s/", err, s);

    return rp;
}

struct match last_match;
VALUE ignorecase;

int
research(reg, str, start)
    struct RRegexp *reg;
    struct RString *str;
    int start;
{
    int result;
    int casefold = ignorecase;

    /* case-flag set for the object */
    if (FL_TEST(reg, FL_USER1)) {
	casefold = TRUE;
    }
    if (casefold) {
	if (reg->ptr->translate != casetable) {
	    reg->ptr->translate = casetable;
	    reg->ptr->fastmap_accurate = 0;
	}
    }
    else if (reg->ptr->translate) {
	reg->ptr->translate = NULL;
	reg->ptr->fastmap_accurate = 0;
    }

    if (start > str->len) return -1;
    result = re_search(reg->ptr, str->ptr, str->len,
		       start, str->len - start, &last_match.regs);

    if (result >= 0) {
	last_match.len = str->len;
	if (last_match.ptr == Qnil) {
	    last_match.ptr = ALLOC_N(char, str->len+1);
	}
	else {
	    REALLOC_N(last_match.ptr, char, str->len+1);
	}
	memcpy(last_match.ptr, str->ptr, last_match.len);
	last_match.ptr[last_match.len] = '\0';
    }

    return result;
}

VALUE
re_nth_match(nth)
    int nth;
{
    int start, end, len;

    if (nth >= last_match.regs.num_regs) {
	return Qnil;
    }
    start = BEG(nth);
    if (start == -1) return Qnil;
    end = END(nth);
    len = end - start;
    return str_new(last_match.ptr + start, len);
}

VALUE
re_last_match(id)
    ID id;
{
    return re_nth_match(0);
}

static VALUE
re_match_pre()
{
    struct match *match;

    if (BEG(0) == -1) return Qnil;
    return str_new(last_match.ptr, BEG(0));
}

static VALUE
re_match_post()
{
    struct match *match;

    if (BEG(0) == -1) return Qnil;
    return str_new(last_match.ptr+END(0),
		   last_match.len-END(0));
}

static VALUE
re_match_last()
{
    int i, len;

    if (BEG(0) == -1) return Qnil;

    for (i=last_match.regs.num_regs-1; BEG(i) == -1 && i > 0; i--) {
    }
    if (i == 0) return Qnil;
    return re_nth_match(i);
}

static VALUE
get_match_data(id, nth)
    ID id;
    int nth;
{
    return re_nth_match(nth);
}

static void
free_match(data)
    struct match *data;
{
    free(data->ptr);
    if (data->regs.allocated > 0) {
	free(data->regs.beg);
	free(data->regs.end);
    }
}

static VALUE
get_match()
{
    struct match *data;
    int beg, i;

    data = ALLOC(struct match);

    data->len = last_match.len;
    data->ptr = ALLOC_N(char, last_match.len+1);
    memcpy(data->ptr, last_match.ptr, data->len+1);
    data->regs.allocated = 0;
    re_copy_registers(&data->regs, &last_match.regs);

    return data_new(data, free_match, Qnil);
}

static VALUE
set_match(val)
    struct RArray *val;
{
    struct match *match;

    Check_Type(val, T_DATA);
    match = (struct match*)DATA_PTR(val);
    last_match.len = match->len;
    if (last_match.len == 0) {
	if (last_match.ptr) {
	    free(last_match.ptr);
	    last_match.ptr = Qnil;
	}
    }
    else {
	if (last_match.ptr == Qnil) {
	    last_match.ptr = ALLOC_N(char, match->len+1);
	}
	else {
	    REALLOC_N(last_match.ptr, char, match->len+1);
	}
    }
    memcpy(last_match.ptr, match->ptr, last_match.len+1);
    last_match.regs = match->regs;

    return (VALUE)val;
}

void
reg_free(rp)
Regexp *rp;
{
    free(rp->buffer);
    free(rp->fastmap);
    free(rp);
}

void
reg_error(s)
const char *s;
{
    Fail(s);
}

VALUE C_Regexp;

static VALUE
regexp_new_1(class, s, len, ci)
    VALUE class;
    char *s;
    int len, ci;
{
    NEWOBJ(re, struct RRegexp);
    OBJSETUP(re, class, T_REGEXP);

    re->ptr = make_regexp(s, len);
    re->str = ALLOC_N(char, len+1);
    memcpy(re->str, s, len);
    re->str[len] = '\0';
    re->len = len;

    if (ci) FL_SET(re, FL_USER1);
    return (VALUE)re;
}

VALUE
regexp_new(s, len, ci)
    char *s;
    int len, ci;
{
    return regexp_new_1(C_Regexp, s, len, ci);
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
    return reg_cache = regexp_new(str->ptr, str->len, ignorecase);
}

VALUE
Freg_match(re, str)
    struct RRegexp *re;
    struct RString *str;
{
    int start;

    Check_Type(str, T_STRING);
    start = research(re, str, 0);
    if (start < 0) {
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

    start = research(re, rb_lastline, 0);
    if (start == -1) {
	return Qnil;
    }
    return INT2FIX(start);
}

static VALUE
Sreg_new(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE src, reg;
    int ci = 0;

    if (argc == 0 || argc > 2) {
	Fail("wrong # of argument");
    }
    if (argc == 2 && argv[1]) {
	ci = 1;
    }

    src = argv[0];
    switch (TYPE(src)) {
      case T_STRING:
	reg = regexp_new_1(self, RREGEXP(src)->ptr, RREGEXP(src)->len, ci);

      case T_REGEXP:
	reg = regexp_new_1(self, RREGEXP(src)->str, RREGEXP(src)->len, ci);

      default:
	Check_Type(src, T_STRING);
    }

    return Qnil;
}

static VALUE
Sreg_quote(re, str)
    VALUE re;
    struct RString *str;
{
  char *s, *send, *t;
  char *tmp;

  Check_Type(str, T_STRING);

  tmp = ALLOCA_N(char, str->len*2);

  s = str->ptr; send = s + str->len;
  t = tmp;

  for (; s != send; s++) {
      if (*s == '[' || *s == ']'
	  || *s == '{' || *s == '}'
	  || *s == '(' || *s == ')'
	  || *s == '*' || *s == '.' || *s == '\\'
	  || *s == '?' || *s == '+'
	  || *s == '^' || *s == '$') {
	  *t++ = '\\';
      }
      *t++ = *s;
    }

  return str_new(tmp, t - tmp);
}

static VALUE
Freg_clone(re)
    struct RRegexp *re;
{
    int ci = FL_TEST(re, FL_USER1);
    return regexp_new_1(CLASS_OF(re), re->str, re->len, ci);
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
	} else {
	    if (BEG(no) == -1) continue;
	    str_cat(val, last_match.ptr+BEG(no), END(no)-BEG(no));
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

static VALUE
kcode()
{
    switch (re_syntax_options & RE_MBCTYPE_MASK) {
      case RE_MBCTYPE_SJIS:
	return str_new2("SJIS");
      case RE_MBCTYPE_EUC:
	return str_new2("EUC");
      default:
	return str_new2("NONE");
    }
}

void
rb_set_kanjicode(code)
    char *code;
{
    if (code == Qnil) goto set_no_conversion;

    switch (code[0]) {
      case 'E':
      case 'e':
	re_syntax_options &= ~RE_MBCTYPE_MASK;
	re_syntax_options |= RE_MBCTYPE_EUC;
	break;
      case 'S':
      case 's':
	re_syntax_options &= ~RE_MBCTYPE_MASK;
	re_syntax_options |= RE_MBCTYPE_SJIS;
	break;
      default:
      case 'N':
      case 'n':
      set_no_conversion:
	re_syntax_options &= ~RE_MBCTYPE_MASK;
	break;
    }
    re_set_syntax(re_syntax_options);
}

void
rb_setup_kcode()
{
    rb_define_const(C_Object, "KCODE", kcode());
}

VALUE rb_readonly_hook();

void
Init_Regexp()
{
    int i;

    re_set_syntax(RE_NO_BK_PARENS | RE_NO_BK_VBAR
		  | RE_AWK_CLASS_HACK
		  | RE_INTERVALS
		  | RE_NO_BK_BRACES
		  | RE_BACKSLASH_ESCAPE_IN_LISTS
#ifdef DEFAULT_MBCTYPE
		  | DEFAULT_MBCTYPE
#endif
);

    rb_define_variable("$~", Qnil, get_match, set_match, 0);

    rb_define_variable("$&", Qnil, re_last_match, Qnil, 0);
    rb_define_variable("$`", Qnil, re_match_pre,  Qnil, 0);
    rb_define_variable("$'", Qnil, re_match_post, Qnil, 0);
    rb_define_variable("$+", Qnil, re_match_last, Qnil, 0);

    rb_define_variable("$=", &ignorecase, Qnil, Qnil, 0);

    C_Regexp  = rb_define_class("Regexp", C_Object);
    rb_define_single_method(C_Regexp, "new", Sreg_new, -1);
    rb_define_single_method(C_Regexp, "compile", Sreg_new, -1);
    rb_define_single_method(C_Regexp, "quote", Sreg_quote, 1);

    rb_define_method(C_Regexp, "=~", Freg_match, 1);
    rb_define_method(C_Regexp, "~", Freg_match2, 0);

    rb_global_variable(&str_cache);
    rb_global_variable(&reg_cache);
}
