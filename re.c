/************************************************

  re.c -

  $Author$
  $Date$
  created at: Mon Aug  9 18:24:49 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

static VALUE eRegxpError;

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
	if (casetable[(unsigned)*p1] != casetable[(unsigned)*p2])
	    return casetable[(unsigned)*p1] - casetable[(unsigned)*p2];
    }
    return str1->len - str2->len;
}

#define REG_IGNORECASE FL_USER0

#define KCODE_NONE  0
#define KCODE_EUC   FL_USER2
#define KCODE_SJIS  FL_USER3
#define KCODE_FIXED FL_USER4
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

static void
kcode_euc(reg)
    struct RRegexp *reg;
{
    FL_UNSET(reg, KCODE_MASK);
    FL_SET(reg, KCODE_EUC);
    FL_SET(reg, KCODE_FIXED);
}

static void
kcode_sjis(reg)
    struct RRegexp *reg;
{
    FL_UNSET(reg, KCODE_MASK);
    FL_SET(reg, KCODE_SJIS);
    FL_SET(reg, KCODE_FIXED);
}

static void
kcode_none(reg)
    struct RRegexp *reg;
{
    FL_UNSET(reg, KCODE_MASK);
    FL_SET(reg, KCODE_FIXED);
}

static void
kcode_set_option(reg)
    struct RRegexp *reg;
{
    if (!FL_TEST(reg, KCODE_FIXED)) return;

    re_syntax_options &= ~RE_MBCTYPE_MASK;
    switch ((RBASIC(reg)->flags & KCODE_MASK)) {
      case KCODE_NONE:
	break;
      case KCODE_EUC:
	re_syntax_options |= RE_MBCTYPE_EUC;
	break;
      case KCODE_SJIS:
	re_syntax_options |= RE_MBCTYPE_SJIS;
	break;
    }
    re_set_syntax(re_syntax_options);
}	  

static void
kcode_reset_option()
{
    re_syntax_options &= ~RE_MBCTYPE_MASK;
    switch (reg_kcode) {
      case KCODE_NONE:
	break;
      case KCODE_EUC:
	re_syntax_options |= RE_MBCTYPE_EUC;
	break;
      case KCODE_SJIS:
	re_syntax_options |= RE_MBCTYPE_SJIS;
	break;
    }
    re_set_syntax(re_syntax_options);
}

extern int rb_in_eval;

static VALUE
reg_desc(s, len, re)
    char *s;
    int len;
    VALUE re;
{
    VALUE str = str_new2("/");
    char *p, *pend;
    int slash = 0;

    p = s; pend = p + len;
    while (p<pend) {
	if (*p == '/') {
	    slash = 1;
	    break;
	}
	p++;
    }
    if (!slash) {
	str_cat(str, s, len);
    }
    else {
	p = s; 
	while (p<pend) {
	    if (*p == '/') {
		char c = '\\';
		str_cat(str, &c, 1);
		str_cat(str, p, 1);
	    }
	    else {
		str_cat(str, p, 1);
	    }
	    p++;
	}
    }
    str_cat(str, "/", 1);
    if (re) {
	if (FL_TEST(re, REG_IGNORECASE)) {
	    str_cat(str, "i", 1);
	}
    }
    return str;
}

static VALUE
reg_inspect(re)
    struct RRegexp *re;
{
    return reg_desc(re->str, re->len, re);
}

static void
reg_raise(s, len, err, re)
    char *s;
    int len;
    char *err;
    VALUE re;
{
    VALUE desc = reg_desc(s, len, re);

    if (rb_in_eval)
	Raise(eRegxpError, "%s: %s", err, RSTRING(desc)->ptr);
    else
	Error("%s: %s", err, RSTRING(desc)->ptr);
}

static Regexp*
make_regexp(s, len, flag)
    char *s;
    int len, flag;
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
    if (flag) {
	rp->translate = casetable;
    }
    err = re_compile_pattern(s, (size_t)len, rp);
    kcode_reset_option();
    if (err != NULL) {
	reg_raise(s, len, err, 0);
    }

    return rp;
}

extern VALUE cData;
static VALUE cMatch;

static VALUE
match_alloc()
{
    NEWOBJ(match, struct RMatch);
    OBJSETUP(match, cMatch, T_MATCH);

    match->str = 0;
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
    int casefold = RTEST(ignorecase);
    VALUE match = 0;
    struct re_registers *regs0 = 0;
    int need_recompile = 0;

    if (start > str->len) return -1;

    /* case-flag set for the object */
    if (FL_TEST(reg, REG_IGNORECASE)) {
	casefold = TRUE;
    }
    if (casefold) {
	if (reg->ptr->translate != casetable) {
	    reg->ptr->translate = casetable;
	    reg->ptr->fastmap_accurate = 0;
	    need_recompile = 1;
	}
    }
    else if (reg->ptr->translate) {
	reg->ptr->translate = NULL;
	reg->ptr->fastmap_accurate = 0;
	need_recompile = 1;
    }

    if (regs == (struct re_registers*)-1) {
	regs = 0;
    }
    else {
	match = match_alloc();
	regs0 = RMATCH(match)->regs;
    }

    if (regs && !match) regs0 = regs;

    if (FL_TEST(reg, KCODE_FIXED)) {
	kcode_set_option(reg);
    }
    else if ((RBASIC(reg)->flags & KCODE_MASK) != reg_kcode) {
	need_recompile = 1;
	RBASIC(reg)->flags = RBASIC(reg)->flags & ~KCODE_MASK;
	RBASIC(reg)->flags |= reg_kcode;
    }

    if (need_recompile) {
	char *err;

	err = re_compile_pattern(reg->str, reg->len, reg->ptr);
	if (err != NULL) {
	    kcode_reset_option();
	    reg_raise(reg->str, reg->len, err, reg);
	}
    }

    result = re_search(reg->ptr, str->ptr, str->len,
		       start, str->len - start, regs0);
    kcode_reset_option();

    if (start == -2) {
	reg_raise(reg->str, reg->len, "Stack overfow in regexp matcher", reg);
    }
    if (result < 0) {
	backref_set(Qnil);
    }
    else if (match) {
	RMATCH(match)->str = str_new4(str);
	backref_set(match);
    }
    if (regs && regs0 && regs0 != regs) re_copy_registers(regs, regs0);

    return result;
}

VALUE
reg_nth_defined(nth, match)
    int nth;
    struct RMatch *match;
{
    if (NIL_P(match)) return Qnil;
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

    if (NIL_P(match)) return Qnil;
    if (nth >= match->regs->num_regs) {
	return Qnil;
    }
    start = match->BEG(nth);
    if (start == -1) return Qnil;
    end = match->END(nth);
    len = end - start;
    return str_new(RSTRING(match->str)->ptr + start, len);
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
    if (NIL_P(match)) return Qnil;
    if (match->BEG(0) == -1) return Qnil;
    return str_new(RSTRING(match->str)->ptr, match->BEG(0));
}

VALUE
reg_match_post(match)
    struct RMatch *match;
{
    if (NIL_P(match)) return Qnil;
    if (match->BEG(0) == -1) return Qnil;
    return str_new(RSTRING(match->str)->ptr+match->END(0),
		   RSTRING(match->str)->len-match->END(0));
}

VALUE
reg_match_last(match)
    struct RMatch *match;
{
    int i;

    if (NIL_P(match)) return Qnil;
    if (match->BEG(0) == -1) return Qnil;

    for (i=match->regs->num_regs-1; match->BEG(i) == -1 && i > 0; i--)
	;
    if (i == 0) return Qnil;
    return reg_nth_match(i, match);
}

static VALUE
last_match_getter()
{
    return reg_last_match(backref_get());
}

static VALUE
prematch_getter()
{
    return reg_match_pre(backref_get());
}

static VALUE
postmatch_getter()
{
    return reg_match_post(backref_get());
}

static VALUE
last_paren_match_getter()
{
    return reg_match_last(backref_get());
}

static VALUE
match_to_a(match)
    struct RMatch *match;
{
    struct re_registers *regs = match->regs;
    VALUE ary = ary_new(regs->num_regs);
    char *ptr = RSTRING(match->str)->ptr;
    int i;

    for (i=0; i<regs->num_regs; i++) {
	if (regs->beg[0] == -1) ary_push(ary, Qnil);
	else ary_push(ary, str_new(ptr+regs->beg[i],
				   regs->end[i]-regs->beg[i]));
    }
    return ary;
}

static VALUE
match_to_s(match)
    struct RMatch *match;
{
    VALUE str = reg_last_match(match);

    if (NIL_P(str)) return str_new(0,0);
    return str;
}

void
reg_free(rp)
Regexp *rp;
{
    free(rp->buffer);
    free(rp->fastmap);
    free(rp);
}

VALUE cRegexp;

static VALUE
reg_new_1(class, s, len, flag)
    VALUE class;
    char *s;
    int len;
    int flag;			/* CASEFOLD  = 0x1 */
				/* CODE_NONE = 0x2 */
				/* CODE_EUC  = 0x4 */
				/* CODE_SJIS = 0x6 */
{
    NEWOBJ(re, struct RRegexp);
    OBJSETUP(re, class, T_REGEXP);

    if (flag & 0x1) {
	FL_SET(re, REG_IGNORECASE);
    }
    switch (flag & ~0x1) {
      case 0:
      default:
	FL_SET(re, reg_kcode);
	break;
      case 2:
	kcode_none(re);
	break;
      case 4:
	kcode_euc(re);
	break;
      case 6:
	kcode_sjis(re);
	break;
    }

    kcode_set_option(re);
    re->ptr = make_regexp(s, len, flag & 0x1);
    re->str = ALLOC_N(char, len+1);
    memcpy(re->str, s, len);
    re->str[len] = '\0';
    re->len = len;

    return (VALUE)re;
}

VALUE
reg_new(s, len, flag)
    char *s;
    int len, flag;
{
    return reg_new_1(cRegexp, s, len, flag);
}

static int ign_cache;
static VALUE reg_cache;

VALUE
reg_regcomp(str)
    struct RString *str;
{
    int ignc = RTEST(ignorecase);

    if (reg_cache && RREGEXP(reg_cache)->len == str->len
	&& ign_cache == ignc
	&& memcmp(RREGEXP(reg_cache)->str, str->ptr, str->len) == 0)
	return reg_cache;

    ign_cache = ignc;
    return reg_cache = reg_new(str->ptr, str->len, ignc);
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
	return FALSE;
    }
    return INT2FIX(start);
}

VALUE
reg_match2(re)
    struct RRegexp *re;
{
    int start;
    VALUE line = lastline_get();

    if (TYPE(line) != T_STRING)
	return FALSE;

    start = reg_search(re, line, 0, 0);
    if (start < 0) {
	return FALSE;
    }
    return INT2FIX(start);
}

static VALUE
reg_s_new(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE src;
    int flag = 0;

    if (argc == 0 || argc > 3) {
	ArgError("wrong # of argument");
    }
    if (argc >= 2 && RTEST(argv[1])) {
	flag = 1;
    }
    if (argc == 3) {
	Check_Type(argv[2], T_STRING);
	switch (RSTRING(argv[2])->ptr[0]) {
	  case 'n': case 'N':
	    flag |= 2;
	    break;
	  case 'e': case 'E':
	    flag |= 4;
	    break;
	  case 's': case 'S':
	    flag |= 6;
	    break;
	  default:
	    break;
	}
    }

    src = argv[0];
    switch (TYPE(src)) {
      case T_STRING:
	return reg_new_1(self, RSTRING(src)->ptr, RSTRING(src)->len, flag);
	break;

      case T_REGEXP:
	return reg_new_1(self, RREGEXP(src)->str, RREGEXP(src)->len, flag);
	break;

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
	  || *s == '|'
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
    int flag = FL_TEST(re, REG_IGNORECASE);
    if (FL_TEST(re, KCODE_FIXED)) {
	switch (RBASIC(re)->flags & KCODE_MASK) {
	  case KCODE_NONE:
	    flag |= 2; break;
	  case KCODE_EUC:
	    flag |= 4; break;
	  case KCODE_SJIS:
	    flag |= 6; break;
	  default:
	    break;
	}
    }
    return reg_new_1(CLASS_OF(re), re->str, re->len, flag);
}

VALUE
reg_regsub(str, src, regs)
    struct RString *str;
    struct RString *src;
    struct re_registers *regs;
{
    VALUE val = 0;
    VALUE tmp;
    char *p, *s, *e, c;
    int no;

    p = s = str->ptr;
    e = s + str->len;

    while (s < e) {
	char *ss = s;

	c = *s++;
	if (c != '\\') continue;

	if (!val) val = str_new(p, ss-p);
	else      str_cat(val, p, ss-p);

	c = *s++;
	p = s;
	switch (c) {
	  case '0': case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
	    no = c - '0';
	    break;
	  case '&':
	    no = 0;
	    break;

	  case '`':
	    str_cat(val, src->ptr, BEG(0));
	    continue;

	  case '\'':
	    str_cat(val, src->ptr+END(0), src->len-END(0));
	    continue;

	  case '+':
	    no = regs->num_regs-1;
	    while (BEG(no) == -1 && no > 0) no--;
	    if (no == 0) continue;
	    break;

	  case '\\':
	    str_cat(val, s-1, 1);
	    continue;

	  default:
	    str_cat(val, s-2, 2);
	    continue;
	}

	if (no >= 0) {
	    if (BEG(no) == -1) continue;
	    str_cat(val, src->ptr+BEG(no), END(no)-BEG(no));
	}
    }

    if (p < e) {
	if (!val) val = str_new(p, e-p);
	else      str_cat(val, p, e-p);
    }
    if (!val) return (VALUE)str;

    return val;
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
    re_syntax_options &= ~RE_MBCTYPE_MASK;
    if (code == 0) goto set_no_conversion;

    switch (code[0]) {
      case 'E':
      case 'e':
	reg_kcode = KCODE_EUC;
	re_syntax_options |= RE_MBCTYPE_EUC;
	break;
      case 'S':
      case 's':
	reg_kcode = KCODE_SJIS;
	re_syntax_options |= RE_MBCTYPE_SJIS;
	break;
      default:
      case 'N':
      case 'n':
      set_no_conversion:
	reg_kcode = KCODE_NONE;
	break;
    }
    re_set_syntax(re_syntax_options);
}

static void
kcode_setter(val)
    struct RString *val;
{
    Check_Type(val, T_STRING);
    rb_set_kcode(val->ptr);
}

static VALUE
match_getter()
{
    return backref_get();
}

static void
match_setter(val)
    VALUE val;
{
    Check_Type(val, T_MATCH);
    backref_set(val);
}

VALUE any_to_s();

void
Init_Regexp()
{
    extern VALUE eException;

    eRegxpError = rb_define_class("RegxpError", eException);

    re_set_syntax(RE_NO_BK_PARENS | RE_NO_BK_VBAR
		  | RE_INTERVALS
		  | RE_NO_BK_BRACES
		  | RE_CONTEXTUAL_INVALID_OPS
		  | RE_BACKSLASH_ESCAPE_IN_LISTS
#ifdef DEFAULT_MBCTYPE
		  | DEFAULT_MBCTYPE
#endif
);

    rb_define_virtual_variable("$~", match_getter, match_setter);
    rb_define_virtual_variable("$&", last_match_getter, 0);
    rb_define_virtual_variable("$`", prematch_getter, 0);
    rb_define_virtual_variable("$'", postmatch_getter, 0);
    rb_define_virtual_variable("$+", last_paren_match_getter, 0);

    rb_define_variable("$=", &ignorecase);
    rb_define_virtual_variable("$KCODE", kcode_getter, kcode_setter);
    rb_define_virtual_variable("$-K", kcode_getter, kcode_setter);

    cRegexp  = rb_define_class("Regexp", cObject);
    rb_define_singleton_method(cRegexp, "new", reg_s_new, -1);
    rb_define_singleton_method(cRegexp, "compile", reg_s_new, -1);
    rb_define_singleton_method(cRegexp, "quote", reg_s_quote, 1);

    rb_define_method(cRegexp, "clone", reg_clone, 0);
    rb_define_method(cRegexp, "=~", reg_match, 1);
    rb_define_method(cRegexp, "===", reg_match, 1);
    rb_define_method(cRegexp, "~", reg_match2, 0);
    rb_define_method(cRegexp, "inspect", reg_inspect, 0);

    rb_global_variable(&reg_cache);

    cMatch  = rb_define_class("MatchingData", cData);
    rb_define_method(cMatch, "to_a", match_to_a, 0);
    rb_define_method(cMatch, "to_s", match_to_s, 0);
    rb_define_method(cMatch, "inspect", any_to_s, 0);
}
