/************************************************

  re.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:49 $
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

#define BEG(no) regs->beg[no]
#define END(no) regs->end[no]

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
	if (casetable[(int)*p1] != casetable[(int)*p2])
	    return casetable[(int)*p1] - casetable[(int)*p2];
    }
    return str1->len - str2->len;
}

#define REG_IGNORECASE FL_USER0

#define KCODE_NONE 0
#define KCODE_EUC  FL_USER1
#define KCODE_SJIS FL_USER2
#define KCODE_MASK (KCODE_EUC|KCODE_SJIS)

static int reg_kcode = 
#ifdef EUC
    KCODE_EUC;
#else
# ifdef SJIS
    KCODE_SJIS;
# else
    KCODE_NONE;
# endif
#endif

static Regexp*
make_regexp(s, len)
    char *s;
    int len;
{
    Regexp *rp;
    char *err;

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

static VALUE
match_alloc()
{
    NEWOBJ(match, struct RMatch);
    OBJSETUP(match, cData, T_MATCH);

    match->ptr = 0;
    match->len = 0;
    match->regs = ALLOC(struct re_registers);
    MEMZERO(match->regs, struct re_registers, 1);

    return (VALUE)match;
}

VALUE ignorecase;

int
reg_search(reg, str, start, regs)
    struct RRegexp *reg;
    struct RString *str;
    int start;
    struct re_registers *regs;
{
    int result;
    int casefold = ignorecase;
    VALUE match = 0;
    struct re_registers *regs0 = 0;

    /* case-flag set for the object */
    if (FL_TEST(reg, REG_IGNORECASE)) {
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

    if (regs == (struct re_registers *)-1) {
	regs = 0;
    }
    else if (match = backref_get()) {
	if (match == 1) {
	    match = match_alloc();
	    backref_set(match);
	}
	regs0 = RMATCH(match)->regs;
    }

    if (regs && !match) regs0 = regs;

    if ((RBASIC(reg)->flags & KCODE_MASK) != reg_kcode) {
	char *err;

	if ((err = re_compile_pattern(reg->str, reg->len, reg->ptr)) != NULL)
	    Fail("%s: /%s/", err, reg->str);
	RBASIC(reg)->flags = RBASIC(reg)->flags & ~KCODE_MASK;
	RBASIC(reg)->flags |= reg_kcode;
    }

    result = re_search(reg->ptr, str->ptr, str->len,
		       start, str->len - start, regs0);

    if (match && result >= 0) {
	RMATCH(match)->len = str->len;
	REALLOC_N(RMATCH(match)->ptr, char, str->len+1);
	memcpy(RMATCH(match)->ptr, str->ptr, str->len);
	RMATCH(match)->ptr[str->len] = '\0';
    }
    if (regs && regs0 && regs0 != regs) re_copy_registers(regs, regs0);

    return result;
}

VALUE
reg_nth_defined(nth, match)
    int nth;
    struct RMatch *match;
{
    if (!match) return FALSE;
    if (nth >= match->regs->num_regs) {
	return FALSE;
    }
    if (match->BEG(nth) == -1) return FALSE;
    return TRUE;
}

VALUE
reg_nth_match(nth, match)
    int nth;
    struct RMatch *match;
{
    int start, end, len;

    if (!match) return Qnil;
    if (nth >= match->regs->num_regs) {
	return Qnil;
    }
    start = match->BEG(nth);
    if (start == -1) return Qnil;
    end = match->END(nth);
    len = end - start;
    return str_new(match->ptr + start, len);
}

VALUE
reg_last_match(match)
    struct RMatch *match;
{
    return reg_nth_match(0, match);
}

VALUE
reg_match_pre(match)
    struct RMatch *match;
{
    if (!match) return Qnil;
    if (match->BEG(0) == -1) return Qnil;
    return str_new(match->ptr, match->BEG(0));
}

VALUE
reg_match_post(match)
    struct RMatch *match;
{
    if (!match) return Qnil;
    if (match->BEG(0) == -1) return Qnil;
    return str_new(match->ptr+match->END(0),
		   match->len-match->END(0));
}

VALUE
reg_match_last(match)
    struct RMatch *match;
{
    int i;

    if (!match) return Qnil;
    if (match->BEG(0) == -1) return Qnil;

    for (i=match->regs->num_regs-1; match->BEG(i) == -1 && i > 0; i--)
	;
    if (i == 0) return Qnil;
    return reg_nth_match(i, match);
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

VALUE cRegexp;

static VALUE
reg_new_1(class, s, len, ci)
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

    FL_SET(re, reg_kcode);
    if (ci) FL_SET(re, REG_IGNORECASE);

    return (VALUE)re;
}

VALUE
reg_new(s, len, ci)
    char *s;
    int len, ci;
{
    return reg_new_1(cRegexp, s, len, ci);
}

static VALUE reg_cache, ign_cache;

VALUE
reg_regcomp(str)
    struct RString *str;
{
    if (reg_cache && RREGEXP(reg_cache)->len == str->len
	&& ign_cache == ignorecase
	&& memcmp(RREGEXP(reg_cache)->str, str->ptr, str->len) == 0)
	return reg_cache;

    ign_cache = ignorecase;
    return reg_cache = reg_new(str->ptr, str->len, ignorecase);
}

VALUE
reg_match(re, str)
    struct RRegexp *re;
    struct RString *str;
{
    int start;

    if (TYPE(str) != T_STRING) return FALSE;
    start = reg_search(re, str, 0, 0);
    if (start < 0) {
	return Qnil;
    }
    return INT2FIX(start);
}

VALUE
reg_match2(re)
    struct RRegexp *re;
{
    extern VALUE rb_lastline;
    int start;

    if (TYPE(rb_lastline) != T_STRING)
	Fail("$_ is not a string");

    start = reg_search(re, rb_lastline, 0, 0);
    if (start == -1) {
	return Qnil;
    }
    return INT2FIX(start);
}

static VALUE
reg_s_new(argc, argv, self)
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
	reg = reg_new_1(self, RREGEXP(src)->ptr, RREGEXP(src)->len, ci);

      case T_REGEXP:
	reg = reg_new_1(self, RREGEXP(src)->str, RREGEXP(src)->len, ci);

      default:
	Check_Type(src, T_STRING);
    }

    return Qnil;
}

static VALUE
reg_s_quote(re, str)
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
reg_clone(re)
    struct RRegexp *re;
{
    int ci = FL_TEST(re, REG_IGNORECASE);
    return reg_new_1(CLASS_OF(re), re->str, re->len, ci);
}

VALUE
reg_regsub(str, src, regs)
    struct RString *str;
    struct RString *src;
    struct re_registers *regs;
{
    VALUE val = Qnil;
    char *p, *s, *e, c;
    int no;

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
		p = s++;
	} else {
	    if (BEG(no) == -1) continue;
	    str_cat(val, src->ptr+BEG(no), END(no)-BEG(no));
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
reg_to_s(re)
    struct RRegexp *re;
{
    VALUE str = str_new2("/");

    str_cat(str, re->str, re->len);
    str_cat(str, "/", 1);
    if (FL_TEST(re, REG_IGNORECASE)) {
	str_cat(str, "i", 1);
    }
    return str;
}

static VALUE
kcode_getter()
{
    switch (reg_kcode) {
      case KCODE_SJIS:
	return str_new2("SJIS");
      case KCODE_EUC:
	return str_new2("EUC");
      default:
	return str_new2("NONE");
    }
}

void
rb_set_kcode(code)
    char *code;
{
    if (code == 0) goto set_no_conversion;

    switch (code[0]) {
      case 'E':
      case 'e':
	reg_kcode = KCODE_EUC;
	re_syntax_options &= ~RE_MBCTYPE_MASK;
	re_syntax_options |= RE_MBCTYPE_EUC;
	break;
      case 'S':
      case 's':
	reg_kcode = KCODE_SJIS;
	re_syntax_options &= ~RE_MBCTYPE_MASK;
	re_syntax_options |= RE_MBCTYPE_SJIS;
	break;
      default:
      case 'N':
      case 'n':
      set_no_conversion:
	reg_kcode = KCODE_NONE;
	re_syntax_options &= ~RE_MBCTYPE_MASK;
	break;
    }
    re_set_syntax(re_syntax_options);
}

static VALUE
kcode_setter(val)
    struct RString *val;
{
    Check_Type(val, T_STRING);
    rb_set_kcode(val->ptr);
    return (VALUE)val;
}

static VALUE
match_getter()
{
    VALUE match = backref_get();

    if (match && match != 1) {
	NEWOBJ(m, struct RMatch);
	OBJSETUP(m, cData, T_MATCH);

	m->len = RMATCH(match)->len;
	if (RMATCH(match)->ptr) {
	    m->ptr = ALLOC_N(char, m->len+1);
	    memcpy(m->ptr, RMATCH(match)->ptr, m->len);
	    m->ptr[m->len] = '\0';
	}
	else {
	    m->ptr = 0;
	}
	m->regs = ALLOC(struct re_registers);
	re_copy_registers(m->regs, RMATCH(match)->regs);
	return (VALUE)m;
    }
    return Qnil;
}

static void
match_setter(val)
{
    Check_Type(val, T_MATCH);
    backref_set(val);
}

void
Init_Regexp()
{
    re_set_syntax(RE_NO_BK_PARENS | RE_NO_BK_VBAR
		  | RE_AWK_CLASS_HACK
		  | RE_INTERVALS
		  | RE_NO_BK_BRACES
		  | RE_BACKSLASH_ESCAPE_IN_LISTS
#ifdef DEFAULT_MBCTYPE
		  | DEFAULT_MBCTYPE
#endif
);

    rb_define_virtual_variable("$~", match_getter, match_setter);

    rb_define_variable("$=", &ignorecase, 0);
    rb_define_virtual_variable("$KCODE", kcode_getter, kcode_setter);

    cRegexp  = rb_define_class("Regexp", cObject);
    rb_define_singleton_method(cRegexp, "new", reg_s_new, -1);
    rb_define_singleton_method(cRegexp, "compile", reg_s_new, -1);
    rb_define_singleton_method(cRegexp, "quote", reg_s_quote, 1);

    rb_define_method(cRegexp, "clone", reg_clone, 0);
    rb_define_method(cRegexp, "=~", reg_match, 1);
    rb_define_method(cRegexp, "~", reg_match2, 0);
    rb_define_method(cRegexp, "to_s", reg_to_s, 0);

    rb_global_variable(&reg_cache);
}
