/* vi:set sw=4:

    strscan.c

    Copyright (c) 1999-2002 Minero Aoki <aamine@loveruby.net>

    This program is free software.
    You can distribute/modify this program
    under the same terms of the ruby.

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

struct strscanner
{
    /* multi-purpose flags */
    unsigned long flags;

    /* the string to scan */
    VALUE str;
    
    /* scan pointers */
    long prev;   /* legal only when MATCHED_P(s) */
    long curr;   /* always legal */

    /* the regexp register; legal only when last match had successed */
    struct re_registers regs;
};

#define S_PTR(s)  (RSTRING(s->str)->ptr)
#define S_LEN(s)  (RSTRING(s->str)->len)
#define S_END(s)  (S_PTR(s) + S_LEN(s))
#define CURPTR(s) (S_PTR(s) + s->curr)
#define S_RESTLEN(s) (S_LEN(s) - s->curr)

#define FLAG_MATCHED (1UL)

#define CLEAR_MATCH_STATUS(s)  s->flags &= ~FLAG_MATCHED
#define MATCHED(s)             s->flags |= FLAG_MATCHED
#define MATCHED_P(s)          (s->flags & FLAG_MATCHED)

#define GET_SCANNER(obj,var) Data_Get_Struct(obj, struct strscanner, var)
#define SCAN_FINISHED(s) ((s)->curr >= RSTRING(p->str)->len)

static VALUE StringScanner;
static VALUE ScanError;


/* ------------------------------------------------------------- */

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
    return infect(rb_str_new(S_PTR(p) + beg_i, end_i - beg_i), p);
}

static VALUE
extract_beg_len(p, beg_i, len)
    struct strscanner *p;
    long beg_i, len;
{
    return infect(rb_str_new(S_PTR(p) + beg_i, len), p);
}

/* ------------------------------------------------------------- */

static VALUE
strscan_s_mustc(self)
    VALUE self;
{
    return self;
}


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
strscan_s_new(argc, argv, klass)
    int argc;
    VALUE *argv, klass;
{
    VALUE str, dup_p;
    struct strscanner *p;

    if (rb_scan_args(argc, argv, "11", &str, &dup_p) == 1)
        dup_p = Qtrue;
    Check_Type(str, T_STRING);

    p = ALLOC_N(struct strscanner, 1);
    MEMZERO(p, struct strscanner, 1);
    p->str = RTEST(dup_p) ? rb_str_dup(str) : str;
    rb_obj_freeze(p->str);
    CLEAR_MATCH_STATUS(p);
    MEMZERO(&(p->regs), struct re_registers, 1);

    return Data_Wrap_Struct(klass, strscan_mark, strscan_free, p);
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
strscan_get_string(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return p->str;
}

static VALUE
strscan_set_string(self, str)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    Check_Type(str, T_STRING);
    p->str = rb_str_dup(str);
    rb_obj_freeze(p->str);
    p->curr = 0;
    CLEAR_MATCH_STATUS(p);
    return str;
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
    return INT2FIX(i);
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
    if (SCAN_FINISHED(p))
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
    if (SCAN_FINISHED(p))
        return Qnil;

    p->prev = p->curr;
    p->curr++;
    MATCHED(p);
    adjust_registers_to_matched(p);
    return extract_range(p, p->prev + p->regs.beg[0],
                            p->prev + p->regs.end[0]);
}


static VALUE
strscan_peek(self, vlen)
    VALUE self, vlen;
{
    struct strscanner *p;
    long len;

    GET_SCANNER(self, p);

    len = NUM2LONG(vlen);
    if (SCAN_FINISHED(p))
        return infect(rb_str_new("", 0), p);

    if (p->curr + len > S_LEN(p))
        len = S_LEN(p) - p->curr;
    return extract_beg_len(p, p->curr, len);
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
strscan_eos_p(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (SCAN_FINISHED(p))
        return Qtrue;
    else
        return Qfalse;
}

static VALUE
strscan_rest_p(self)
    VALUE self;
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (SCAN_FINISHED(p))
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
    if (SCAN_FINISHED(p)) {
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
    if (SCAN_FINISHED(p)) {
        return INT2FIX(0);
    }

    i = S_LEN(p) - p->curr;
    return INT2FIX(i);
}


static void
catchar(ret, c)
    VALUE ret;
    int c;
{
    char buf[1];

    buf[0] = c;
    rb_str_cat(ret, buf, 1);
}

#define CLEN 5

static VALUE
strscan_inspect(self)
    VALUE self;
{
    struct strscanner *p;
    char buf[128];
    VALUE ret;
    long len;

    GET_SCANNER(self, p);
    len = sprintf(buf, "#<%s %ld/%ld",
                  rb_class2name(CLASS_OF(self)),
                  p->curr, S_LEN(p));
    ret = rb_str_new(buf, len);
    
    if (SCAN_FINISHED(p)) {
        rb_str_cat(ret, " fin>", 4);
    }
    else {
        char *sp;

        sp = CURPTR(p) - CLEN;
        if (sp < S_PTR(p)) sp = S_PTR(p);
        if (sp != CURPTR(p)) {
            rb_str_cat(ret, " \"", 2);
            if (sp > S_PTR(p))
                rb_str_cat(ret, "...", 3);
            for (; sp < CURPTR(p); sp++) {
                catchar(ret, *sp);
            }
            rb_str_cat(ret, "\"", 1);
        }
        rb_str_cat(ret, " @", 2);
        if (sp != S_END(p)) {
            char *e;

            e = sp + CLEN;
            if (e > S_END(p)) e = S_END(p);
            rb_str_cat(ret, " \"", 2);
            for (; sp < e; sp++) {
                catchar(ret, *sp);
            }
            if (sp < S_END(p))
                rb_str_cat(ret, "...", 3);
            rb_str_cat(ret, "\"", 1);
        }
        rb_str_cat(ret, ">", 1);
    }
    return infect(ret, p);
}

/* ------------------------------------------------------------- */

void
Init_strscan()
{
    ID id_scanerr = rb_intern("ScanError");
    VALUE tmp;

    if (rb_const_defined(rb_cObject, id_scanerr)) {
        ScanError = rb_const_get(rb_cObject, id_scanerr);
    }
    else {
        ScanError = rb_define_class_id(id_scanerr, rb_eStandardError);
    }

    StringScanner = rb_define_class("StringScanner", rb_cObject);
    tmp = rb_str_new2(STRSCAN_VERSION);
    rb_obj_freeze(tmp);
    rb_const_set(StringScanner, rb_intern("Version"), tmp);
    tmp = rb_str_new2("$Id$");
    rb_obj_freeze(tmp);
    rb_const_set(StringScanner, rb_intern("Id"), tmp);
    
    rb_define_singleton_method(StringScanner, "new", strscan_s_new, -1);
    rb_define_singleton_method(StringScanner,
                               "must_C_version", strscan_s_mustc, 0);
    rb_define_method(StringScanner, "reset",       strscan_reset,       0);
    rb_define_method(StringScanner, "terminate",   strscan_terminate,   0);
    rb_define_method(StringScanner, "clear",       strscan_terminate,   0);
    rb_define_method(StringScanner, "string",      strscan_get_string,  0);
    rb_define_method(StringScanner, "string=",     strscan_set_string,  1);
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
    rb_define_method(StringScanner, "getbyte",     strscan_get_byte,    0);
    rb_define_method(StringScanner, "peek",        strscan_peek,        1);
    rb_define_method(StringScanner, "peep",        strscan_peek,        1);

    rb_define_method(StringScanner, "unscan",      strscan_unscan,      0);

    rb_define_method(StringScanner, "eos?",        strscan_eos_p,       0);
    rb_define_method(StringScanner, "empty?",      strscan_eos_p,       0);
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
