/*

    strscan.c

    Copyright (c) 1999-2004 Minero Aoki

    This program is free software.
    You can distribute/modify this program under the terms of
    the Ruby License. For details, see the file COPYING.

    $Id$

*/


#include "ruby.h"
#include "re.h"
#include "version.h"

#if (RUBY_VERSION_CODE < 150)
#  define rb_eRangeError rb_eArgError
#  define rb_obj_freeze(obj) rb_str_freeze(obj)
#endif

#define STRSCAN_VERSION "0.7.0"

/* =======================================================================
                         Data Type Definitions
   ======================================================================= */

static VALUE StringScanner;
static VALUE ScanError;

struct strscanner
{
    /* multi-purpose flags */
    unsigned long flags;
#define FLAG_MATCHED (1 << 0)

    /* the string to scan */
    VALUE str;
    
    /* scan pointers */
    long prev;   /* legal only when MATCHED_P(s) */
    long curr;   /* always legal */

    /* the regexp register; legal only when MATCHED_P(s) */
    struct re_registers regs;
};

#define MATCHED_P(s)          ((s)->flags & FLAG_MATCHED)
#define MATCHED(s)             (s)->flags |= FLAG_MATCHED
#define CLEAR_MATCH_STATUS(s)  (s)->flags &= ~FLAG_MATCHED

#define S_PBEG(s)  (RSTRING((s)->str)->ptr)
#define S_LEN(s)  (RSTRING((s)->str)->len)
#define S_PEND(s)  (S_PBEG(s) + S_LEN(s))
#define CURPTR(s) (S_PBEG(s) + (s)->curr)
#define S_RESTLEN(s) (S_LEN(s) - (s)->curr)

#define EOS_P(s) ((s)->curr >= RSTRING(p->str)->len)

#define GET_SCANNER(obj,var) do {\
    Data_Get_Struct(obj, struct strscanner, var);\
    if (NIL_P(var->str)) rb_raise(rb_eArgError, "uninitialized StringScanner object");\
} while (0)

/* =======================================================================
                            Function Prototypes
   ======================================================================= */

static VALUE infect _((VALUE str, struct strscanner *p));
static VALUE extract_range _((struct strscanner *p, long beg_i, long end_i));
static VALUE extract_beg_len _((struct strscanner *p, long beg_i, long len));

static void strscan_mark _((struct strscanner *p));
static void strscan_free _((struct strscanner *p));
static VALUE strscan_s_allocate _((VALUE klass));
static VALUE strscan_initialize _((int argc, VALUE *argv, VALUE self));

static VALUE strscan_s_mustc _((VALUE self));
static VALUE strscan_terminate _((VALUE self));
static VALUE strscan_clear _((VALUE self));
static VALUE strscan_get_string _((VALUE self));
static VALUE strscan_set_string _((VALUE self, VALUE str));
static VALUE strscan_concat _((VALUE self, VALUE str));
static VALUE strscan_get_pos _((VALUE self));
static VALUE strscan_set_pos _((VALUE self, VALUE pos));
static VALUE strscan_do_scan _((VALUE self, VALUE regex,
                                int succptr, int getstr, int headonly));
static VALUE strscan_scan _((VALUE self, VALUE re));
static VALUE strscan_match_p _((VALUE self, VALUE re));
static VALUE strscan_skip _((VALUE self, VALUE re));
static VALUE strscan_check _((VALUE self, VALUE re));
static VALUE strscan_scan_full _((VALUE self, VALUE re,
                                  VALUE succp, VALUE getp));
static VALUE strscan_scan_until _((VALUE self, VALUE re));
static VALUE strscan_skip_until _((VALUE self, VALUE re));
static VALUE strscan_check_until _((VALUE self, VALUE re));
static VALUE strscan_search_full _((VALUE self, VALUE re,
                                    VALUE succp, VALUE getp));
static void adjust_registers_to_matched _((struct strscanner *p));
static VALUE strscan_getch _((VALUE self));
static VALUE strscan_get_byte _((VALUE self));
static VALUE strscan_getbyte _((VALUE self));
static VALUE strscan_peek _((VALUE self, VALUE len));
static VALUE strscan_peep _((VALUE self, VALUE len));
static VALUE strscan_unscan _((VALUE self));
static VALUE strscan_bol_p _((VALUE self));
static VALUE strscan_eos_p _((VALUE self));
static VALUE strscan_empty_p _((VALUE self));
static VALUE strscan_rest_p _((VALUE self));
static VALUE strscan_matched_p _((VALUE self));
static VALUE strscan_matched _((VALUE self));
static VALUE strscan_matched_size _((VALUE self));
static VALUE strscan_aref _((VALUE self, VALUE idx));
static VALUE strscan_pre_match _((VALUE self));
static VALUE strscan_post_match _((VALUE self));
static VALUE strscan_rest _((VALUE self));
static VALUE strscan_rest_size _((VALUE self));

static VALUE strscan_inspect _((VALUE self));
static VALUE inspect1 _((struct strscanner *p));
static VALUE inspect2 _((struct strscanner *p));

/* =======================================================================
                                   Utils
   ======================================================================= */

static VALUE
infect(str, p)
    VALUE str;
    struct strscanner *p;
{
    OBJ_INFECT(str, p->str);
    return str;
}

static VALUE
extract_range(p, beg_i, end_i)
    struct strscanner *p;
    long beg_i, end_i;
{
    if (beg_i > S_LEN(p)) return Qnil;
    if (end_i > S_LEN(p))
        end_i = S_LEN(p);
    return infect(rb_str_new(S_PBEG(p) + beg_i, end_i - beg_i), p);
}

static VALUE
extract_beg_len(p, beg_i, len)
    struct strscanner *p;
    long beg_i, len;
{
    if (beg_i > S_LEN(p)) return Qnil;
    if (beg_i + len > S_LEN(p))
        len = S_LEN(p) - beg_i;
    return infect(rb_str_new(S_PBEG(p) + beg_i, len), p);
}


/* =======================================================================
                               Constructor
   ======================================================================= */


static void
strscan_mark(p)
    struct strscanner *p;
{
    rb_gc_mark(p->str);
}

static void
strscan_free(p)
    struct strscanner *p;
{
    re_free_registers(&(p->regs));
    memset(p, sizeof(struct strscanner), 0);
    free(p);
}

static VALUE
strscan_s_allocate(klass)
    VALUE klass;
{
    struct strscanner *p;
    
    p = ALLOC(struct strscanner);
    MEMZERO(p, struct strscanner, 1);
    CLEAR_MATCH_STATUS(p);
    MEMZERO(&(p->regs), struct re_registers, 1);
    p->str = Qnil;
    return Data_Wrap_Struct(klass, strscan_mark, strscan_free, p);
}

static VALUE
strscan_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct strscanner *p;
    VALUE str, need_dup;

    Data_Get_Struct(self, struct strscanner, p);
    rb_scan_args(argc, argv, "11", &str, &need_dup);
    StringValue(str);
    p->str = str;

    return self;
}


/* =======================================================================
                          Instance Methods
   ======================================================================= */

static VALUE
strscan_s_mustc(self)
    VALUE self;
{
    return self;
}

static VALUE
strscan_reset(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    p->curr = 0;
    CLEAR_MATCH_STATUS(p);
    return self;
}

static VALUE
strscan_terminate(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    p->curr = S_LEN(p);
    CLEAR_MATCH_STATUS(p);
    return self;
}

static VALUE
strscan_clear(self)
    VALUE self;
{
    rb_warning("StringScanner#clear is obsolete; use #terminate instead");
    return strscan_terminate(self);
}

static VALUE
strscan_get_string(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return p->str;
}

static VALUE
strscan_set_string(self, str)
    VALUE self, str;
{
    struct strscanner *p;

    Data_Get_Struct(self, struct strscanner, p);
    StringValue(str);
    p->str = rb_str_dup(str);
    rb_obj_freeze(p->str);
    p->curr = 0;
    CLEAR_MATCH_STATUS(p);
    return str;
}

static VALUE
strscan_concat(self, str)
    VALUE self, str;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    StringValue(str);
    rb_str_append(p->str, str);
    return self;
}

static VALUE
strscan_get_pos(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return INT2FIX(p->curr);
}

static VALUE
strscan_set_pos(self, v)
    VALUE self, v;
{
    struct strscanner *p;
    long i;

    GET_SCANNER(self, p);
    i = NUM2INT(v);
    if (i < 0) i += S_LEN(p);
    if (i < 0) rb_raise(rb_eRangeError, "index out of range");
    if (i > S_LEN(p)) rb_raise(rb_eRangeError, "index out of range");
    p->curr = i;
    return INT2NUM(i);
}


/* I should implement this function? */
#define strscan_prepare_re(re)  /* none */

static VALUE
strscan_do_scan(self, regex, succptr, getstr, headonly)
    VALUE self, regex;
    int succptr, getstr, headonly;
{
    struct strscanner *p;
    int ret;

    Check_Type(regex, T_REGEXP);
    GET_SCANNER(self, p);

    CLEAR_MATCH_STATUS(p);
    if (EOS_P(p)) {
        return Qnil;
    }
    strscan_prepare_re(regex);
    if (headonly) {
        ret = re_match(RREGEXP(regex)->ptr,
                       CURPTR(p), S_RESTLEN(p),
                       0,
                       &(p->regs));
    }
    else {
        ret = re_search(RREGEXP(regex)->ptr,
                        CURPTR(p), S_RESTLEN(p),
                        0,
                        S_RESTLEN(p),
                        &(p->regs));
    }

    if (ret == -2) rb_raise(ScanError, "regexp buffer overflow");
    if (ret < 0) {
        /* not matched */
        return Qnil;
    }

    MATCHED(p);
    p->prev = p->curr;
    if (succptr) {
        p->curr += p->regs.end[0];
    }
    if (getstr) {
        return extract_beg_len(p, p->prev, p->regs.end[0]);
    }
    else {
        return INT2FIX(p->regs.end[0]);
    }
}

static VALUE
strscan_scan(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 1, 1, 1);
}

static VALUE
strscan_match_p(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 0, 0, 1);
}

static VALUE
strscan_skip(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 1, 0, 1);
}

static VALUE
strscan_check(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 0, 1, 1);
}

static VALUE
strscan_scan_full(self, re, s, f)
    VALUE self, re, s, f;
{
    return strscan_do_scan(self, re, RTEST(s), RTEST(f), 1);
}


static VALUE
strscan_scan_until(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 1, 1, 0);
}

static VALUE
strscan_exist_p(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 0, 0, 0);
}

static VALUE
strscan_skip_until(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 1, 0, 0);
}

static VALUE
strscan_check_until(self, re)
    VALUE self, re;
{
    return strscan_do_scan(self, re, 0, 1, 0);
}

static VALUE
strscan_search_full(self, re, s, f)
    VALUE self, re, s, f;
{
    return strscan_do_scan(self, re, RTEST(s), RTEST(f), 0);
}

/* DANGEROUS; need to synchronize with regex.c */
static void
adjust_registers_to_matched(p)
    struct strscanner *p;
{
    if (p->regs.allocated == 0) {
        p->regs.beg = ALLOC_N(int, RE_NREGS);
        p->regs.end = ALLOC_N(int, RE_NREGS);
        p->regs.allocated = RE_NREGS;
    }
    p->regs.num_regs = 1;
    p->regs.beg[0] = 0;
    p->regs.end[0] = p->curr - p->prev;
}

static VALUE
strscan_getch(self)
    VALUE self;
{
    struct strscanner *p;
    long len;

    GET_SCANNER(self, p);
    CLEAR_MATCH_STATUS(p);
    if (EOS_P(p))
        return Qnil;

    len = mbclen(*CURPTR(p));
    if (p->curr + len > S_LEN(p))
        len = S_LEN(p) - p->curr;
    p->prev = p->curr;
    p->curr += len;
    MATCHED(p);
    adjust_registers_to_matched(p);
    return extract_range(p, p->prev + p->regs.beg[0],
                            p->prev + p->regs.end[0]);
}

static VALUE
strscan_get_byte(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    CLEAR_MATCH_STATUS(p);
    if (EOS_P(p))
        return Qnil;

    p->prev = p->curr;
    p->curr++;
    MATCHED(p);
    adjust_registers_to_matched(p);
    return extract_range(p, p->prev + p->regs.beg[0],
                            p->prev + p->regs.end[0]);
}

static VALUE
strscan_getbyte(self)
    VALUE self;
{
    rb_warning("StringScanner#getbyte is obsolete; use #get_byte instead");
    return strscan_get_byte(self);
}


static VALUE
strscan_peek(self, vlen)
    VALUE self, vlen;
{
    struct strscanner *p;
    long len;

    GET_SCANNER(self, p);

    len = NUM2LONG(vlen);
    if (EOS_P(p))
        return infect(rb_str_new("", 0), p);

    if (p->curr + len > S_LEN(p))
        len = S_LEN(p) - p->curr;
    return extract_beg_len(p, p->curr, len);
}

static VALUE
strscan_peep(self, vlen)
    VALUE self, vlen;
{
    rb_warning("StringScanner#peep is obsolete; use #peek instead");
    return strscan_peek(self, vlen);
}

static VALUE
strscan_unscan(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))
        rb_raise(ScanError, "cannot unscan: prev match had failed");

    p->curr = p->prev;
    CLEAR_MATCH_STATUS(p);
    return self;
}

static VALUE
strscan_bol_p(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (CURPTR(p) > S_PEND(p)) return Qnil;
    if (p->curr == 0) return Qtrue;
    return (*(CURPTR(p) - 1) == '\n') ? Qtrue : Qfalse;
}

static VALUE
strscan_eos_p(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (EOS_P(p))
        return Qtrue;
    else
        return Qfalse;
}

static VALUE
strscan_empty_p(self)
    VALUE self;
{
    rb_warning("StringScanner#empty_p is obsolete; use #eos? instead");
    return strscan_eos_p(self);
}

static VALUE
strscan_rest_p(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (EOS_P(p))
        return Qfalse;
    else
        return Qtrue;
}


static VALUE
strscan_matched_p(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (MATCHED_P(p))
        return Qtrue;
    else
        return Qfalse;
}

static VALUE
strscan_matched(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;

    return extract_range(p, p->prev + p->regs.beg[0],
                            p->prev + p->regs.end[0]);
}

static VALUE
strscan_matched_size(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;

    return INT2NUM(p->regs.end[0] - p->regs.beg[0]);
}

static VALUE
strscan_aref(self, idx)
    VALUE self, idx;
{
    struct strscanner *p;
    long i;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))        return Qnil;
    
    i = NUM2LONG(idx);
    if (i < 0)
        i += p->regs.num_regs;
    if (i < 0)                 return Qnil;
    if (i >= p->regs.num_regs) return Qnil;
    if (p->regs.beg[i] == -1)  return Qnil;

    return extract_range(p, p->prev + p->regs.beg[i],
                            p->prev + p->regs.end[i]);
}

static VALUE
strscan_pre_match(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;

    return extract_range(p, 0, p->prev + p->regs.beg[0]);
}

static VALUE
strscan_post_match(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;

    return extract_range(p, p->prev + p->regs.end[0], S_LEN(p));
}


static VALUE
strscan_rest(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (EOS_P(p)) {
        return infect(rb_str_new("", 0), p);
    }
    return extract_range(p, p->curr, S_LEN(p));
}

static VALUE
strscan_rest_size(self)
    VALUE self;
{
    struct strscanner *p;
    long i;

    GET_SCANNER(self, p);
    if (EOS_P(p)) {
        return INT2FIX(0);
    }

    i = S_LEN(p) - p->curr;
    return INT2FIX(i);
}


#define INSPECT_LENGTH 5
#define BUFSIZE 256

static VALUE
strscan_inspect(self)
    VALUE self;
{
    struct strscanner *p;
    char buf[BUFSIZE];
    long len;
    VALUE a, b;

    Data_Get_Struct(self, struct strscanner, p);
    if (NIL_P(p->str)) {
        len = snprintf(buf, BUFSIZE, "#<%s (uninitialized)>",
                       rb_class2name(CLASS_OF(self)));
        return infect(rb_str_new(buf, len), p);
    }
    if (EOS_P(p)) {
        len = snprintf(buf, BUFSIZE, "#<%s fin>",
                       rb_class2name(CLASS_OF(self)));
        return infect(rb_str_new(buf, len), p);
    }
    if (p->curr == 0) {
        b = inspect2(p);
        len = snprintf(buf, BUFSIZE, "#<%s %ld/%ld @ %s>",
                       rb_class2name(CLASS_OF(self)),
                       p->curr, S_LEN(p),
                       RSTRING(b)->ptr);
        return infect(rb_str_new(buf, len), p);
    }
    a = inspect1(p);
    b = inspect2(p);
    len = snprintf(buf, BUFSIZE, "#<%s %ld/%ld %s @ %s>",
                   rb_class2name(CLASS_OF(self)),
                   p->curr, S_LEN(p),
                   RSTRING(a)->ptr,
                   RSTRING(b)->ptr);
    return infect(rb_str_new(buf, len), p);
}

static VALUE
inspect1(p)
    struct strscanner *p;
{
    char buf[BUFSIZE];
    char *bp = buf;
    long len;

    if (p->curr == 0) return rb_str_new2("");
    if (p->curr > INSPECT_LENGTH) {
        strcpy(bp, "..."); bp += 3;
        len = INSPECT_LENGTH;
    }
    else {
        len = p->curr;
    }
    memcpy(bp, CURPTR(p) - len, len); bp += len;
    return rb_str_dump(rb_str_new(buf, bp - buf));
}

static VALUE
inspect2(p)
    struct strscanner *p;
{
    char buf[BUFSIZE];
    char *bp = buf;
    long len;

    if (EOS_P(p)) return rb_str_new2("");
    len = S_LEN(p) - p->curr;
    if (len > INSPECT_LENGTH) {
        len = INSPECT_LENGTH;
        memcpy(bp, CURPTR(p), len); bp += len;
        strcpy(bp, "..."); bp += 3;
    }
    else {
        memcpy(bp, CURPTR(p), len); bp += len;
    }
    return rb_str_dump(rb_str_new(buf, bp - buf));
}

/* =======================================================================
                              Ruby Interface
   ======================================================================= */

void
Init_strscan()
{
    volatile VALUE tmp;

    StringScanner = rb_define_class("StringScanner", rb_cObject);
    ScanError = rb_eval_string("class StringScanner; class Error < StandardError; end; end; ScanError = StringScanner::Error unless defined?(ScanError); StringScanner::Error");
    tmp = rb_str_new2(STRSCAN_VERSION);
    rb_obj_freeze(tmp);
    rb_const_set(StringScanner, rb_intern("Version"), tmp);
    tmp = rb_str_new2("$Id$");
    rb_obj_freeze(tmp);
    rb_const_set(StringScanner, rb_intern("Id"), tmp);
    
    rb_define_alloc_func(StringScanner, strscan_s_allocate);
    rb_define_private_method(StringScanner, "initialize", strscan_initialize, -1);
    rb_define_singleton_method(StringScanner, "must_C_version", strscan_s_mustc, 0);
    rb_define_method(StringScanner, "reset",       strscan_reset,       0);
    rb_define_method(StringScanner, "terminate",   strscan_terminate,   0);
    rb_define_method(StringScanner, "clear",       strscan_clear,       0);
    rb_define_method(StringScanner, "string",      strscan_get_string,  0);
    rb_define_method(StringScanner, "string=",     strscan_set_string,  1);
    rb_define_method(StringScanner, "concat",      strscan_concat,      1);
    rb_define_method(StringScanner, "<<",          strscan_concat,      1);
    rb_define_method(StringScanner, "pos",         strscan_get_pos,     0);
    rb_define_method(StringScanner, "pos=",        strscan_set_pos,     1);
    rb_define_method(StringScanner, "pointer",     strscan_get_pos,     0);
    rb_define_method(StringScanner, "pointer=",    strscan_set_pos,     1);

    rb_define_method(StringScanner, "scan",        strscan_scan,        1);
    rb_define_method(StringScanner, "skip",        strscan_skip,        1);
    rb_define_method(StringScanner, "match?",      strscan_match_p,     1);
    rb_define_method(StringScanner, "check",       strscan_check,       1);
    rb_define_method(StringScanner, "scan_full",   strscan_scan_full,   3);

    rb_define_method(StringScanner, "scan_until",  strscan_scan_until,  1);
    rb_define_method(StringScanner, "skip_until",  strscan_skip_until,  1);
    rb_define_method(StringScanner, "exist?",      strscan_exist_p,     1);
    rb_define_method(StringScanner, "check_until", strscan_check_until, 1);
    rb_define_method(StringScanner, "search_full", strscan_search_full, 3);

    rb_define_method(StringScanner, "getch",       strscan_getch,       0);
    rb_define_method(StringScanner, "get_byte",    strscan_get_byte,    0);
    rb_define_method(StringScanner, "getbyte",     strscan_getbyte,     0);
    rb_define_method(StringScanner, "peek",        strscan_peek,        1);
    rb_define_method(StringScanner, "peep",        strscan_peep,        1);

    rb_define_method(StringScanner, "unscan",      strscan_unscan,      0);

    rb_define_method(StringScanner, "beginning_of_line?", strscan_bol_p, 0);
    rb_define_method(StringScanner, "bol?",        strscan_bol_p,       0);
    rb_define_method(StringScanner, "eos?",        strscan_eos_p,       0);
    rb_define_method(StringScanner, "empty?",      strscan_empty_p,     0);
    rb_define_method(StringScanner, "rest?",       strscan_rest_p,      0);

    rb_define_method(StringScanner, "matched?",    strscan_matched_p,   0);
    rb_define_method(StringScanner, "matched",     strscan_matched,     0);
    rb_define_method(StringScanner, "matched_size", strscan_matched_size, 0);
    rb_define_method(StringScanner, "matchedsize", strscan_matched_size, 0);
    rb_define_method(StringScanner, "[]",          strscan_aref,        1);
    rb_define_method(StringScanner, "pre_match",   strscan_pre_match,   0);
    rb_define_method(StringScanner, "post_match",  strscan_post_match,  0);

    rb_define_method(StringScanner, "rest",        strscan_rest,        0);
    rb_define_method(StringScanner, "rest_size",   strscan_rest_size,   0);
    rb_define_method(StringScanner, "restsize",    strscan_rest_size,   0);

    rb_define_method(StringScanner, "inspect",     strscan_inspect,     0);
}
