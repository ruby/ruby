/*
    $Id$

    Copyright (c) 1999-2006 Minero Aoki

    This program is free software.
    You can redistribute this program under the terms of the Ruby's or 2-clause
    BSD License.  For details, see the COPYING and LICENSE.txt files.
*/

#include "ruby/ruby.h"
#include "ruby/re.h"
#include "ruby/encoding.h"

#ifdef RUBY_EXTCONF_H
#  include RUBY_EXTCONF_H
#endif

#ifdef HAVE_ONIG_REGION_MEMSIZE
extern size_t onig_region_memsize(const struct re_registers *regs);
#endif

#include <stdbool.h>

#define STRSCAN_VERSION "3.0.0"

/* =======================================================================
                         Data Type Definitions
   ======================================================================= */

static VALUE StringScanner;
static VALUE ScanError;
static ID id_byteslice;

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

    /* regexp used for last scan */
    VALUE regex;

    /* anchor mode */
    bool fixed_anchor_p;
};

#define MATCHED_P(s)          ((s)->flags & FLAG_MATCHED)
#define MATCHED(s)             (s)->flags |= FLAG_MATCHED
#define CLEAR_MATCH_STATUS(s)  (s)->flags &= ~FLAG_MATCHED

#define S_PBEG(s)  (RSTRING_PTR((s)->str))
#define S_LEN(s)  (RSTRING_LEN((s)->str))
#define S_PEND(s)  (S_PBEG(s) + S_LEN(s))
#define CURPTR(s) (S_PBEG(s) + (s)->curr)
#define S_RESTLEN(s) (S_LEN(s) - (s)->curr)

#define EOS_P(s) ((s)->curr >= RSTRING_LEN(p->str))

#define GET_SCANNER(obj,var) do {\
    (var) = check_strscan(obj);\
    if (NIL_P((var)->str)) rb_raise(rb_eArgError, "uninitialized StringScanner object");\
} while (0)

/* =======================================================================
                            Function Prototypes
   ======================================================================= */

static inline long minl _((const long n, const long x));
static VALUE extract_range _((struct strscanner *p, long beg_i, long end_i));
static VALUE extract_beg_len _((struct strscanner *p, long beg_i, long len));

static struct strscanner *check_strscan _((VALUE obj));
static void strscan_mark _((void *p));
static void strscan_free _((void *p));
static size_t strscan_memsize _((const void *p));
static VALUE strscan_s_allocate _((VALUE klass));
static VALUE strscan_initialize _((int argc, VALUE *argv, VALUE self));
static VALUE strscan_init_copy _((VALUE vself, VALUE vorig));

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
str_new(struct strscanner *p, const char *ptr, long len)
{
    VALUE str = rb_str_new(ptr, len);
    rb_enc_copy(str, p->str);
    return str;
}

static inline long
minl(const long x, const long y)
{
    return (x < y) ? x : y;
}

static VALUE
extract_range(struct strscanner *p, long beg_i, long end_i)
{
    if (beg_i > S_LEN(p)) return Qnil;
    end_i = minl(end_i, S_LEN(p));
    return str_new(p, S_PBEG(p) + beg_i, end_i - beg_i);
}

static VALUE
extract_beg_len(struct strscanner *p, long beg_i, long len)
{
    if (beg_i > S_LEN(p)) return Qnil;
    len = minl(len, S_LEN(p) - beg_i);
    return str_new(p, S_PBEG(p) + beg_i, len);
}

/* =======================================================================
                               Constructor
   ======================================================================= */

static void
strscan_mark(void *ptr)
{
    struct strscanner *p = ptr;
    rb_gc_mark(p->str);
    rb_gc_mark(p->regex);
}

static void
strscan_free(void *ptr)
{
    struct strscanner *p = ptr;
    onig_region_free(&(p->regs), 0);
    ruby_xfree(p);
}

static size_t
strscan_memsize(const void *ptr)
{
    const struct strscanner *p = ptr;
    size_t size = sizeof(*p) - sizeof(p->regs);
#ifdef HAVE_ONIG_REGION_MEMSIZE
    size += onig_region_memsize(&p->regs);
#endif
    return size;
}

static const rb_data_type_t strscanner_type = {
    "StringScanner",
    {strscan_mark, strscan_free, strscan_memsize},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
strscan_s_allocate(VALUE klass)
{
    struct strscanner *p;
    VALUE obj = TypedData_Make_Struct(klass, struct strscanner, &strscanner_type, p);

    CLEAR_MATCH_STATUS(p);
    onig_region_init(&(p->regs));
    p->str = Qnil;
    p->regex = Qnil;
    return obj;
}

/*
 * call-seq:
 *    StringScanner.new(string, fixed_anchor: false)
 *    StringScanner.new(string, dup = false)
 *
 * Creates a new StringScanner object to scan over the given +string+.
 *
 * If +fixed_anchor+ is +true+, +\A+ always matches the beginning of
 * the string. Otherwise, +\A+ always matches the current position.
 *
 * +dup+ argument is obsolete and not used now.
 */
static VALUE
strscan_initialize(int argc, VALUE *argv, VALUE self)
{
    struct strscanner *p;
    VALUE str, options;

    p = check_strscan(self);
    rb_scan_args(argc, argv, "11", &str, &options);
    options = rb_check_hash_type(options);
    if (!NIL_P(options)) {
        VALUE fixed_anchor;
        ID keyword_ids[1];
        keyword_ids[0] = rb_intern("fixed_anchor");
        rb_get_kwargs(options, keyword_ids, 0, 1, &fixed_anchor);
        if (fixed_anchor == Qundef) {
            p->fixed_anchor_p = false;
        }
        else {
            p->fixed_anchor_p = RTEST(fixed_anchor);
        }
    }
    else {
        p->fixed_anchor_p = false;
    }
    StringValue(str);
    p->str = str;

    return self;
}

static struct strscanner *
check_strscan(VALUE obj)
{
    return rb_check_typeddata(obj, &strscanner_type);
}

/*
 * call-seq:
 *   dup
 *   clone
 *
 * Duplicates a StringScanner object.
 */
static VALUE
strscan_init_copy(VALUE vself, VALUE vorig)
{
    struct strscanner *self, *orig;

    self = check_strscan(vself);
    orig = check_strscan(vorig);
    if (self != orig) {
	self->flags = orig->flags;
	self->str = orig->str;
	self->prev = orig->prev;
	self->curr = orig->curr;
	if (rb_reg_region_copy(&self->regs, &orig->regs))
	    rb_memerror();
	RB_GC_GUARD(vorig);
    }

    return vself;
}

/* =======================================================================
                          Instance Methods
   ======================================================================= */

/*
 * call-seq: StringScanner.must_C_version
 *
 * This method is defined for backward compatibility.
 */
static VALUE
strscan_s_mustc(VALUE self)
{
    return self;
}

/*
 * Reset the scan pointer (index 0) and clear matching data.
 */
static VALUE
strscan_reset(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    p->curr = 0;
    CLEAR_MATCH_STATUS(p);
    return self;
}

/*
 * call-seq:
 *   terminate
 *   clear
 *
 * Sets the scan pointer to the end of the string and clear matching data.
 */
static VALUE
strscan_terminate(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    p->curr = S_LEN(p);
    CLEAR_MATCH_STATUS(p);
    return self;
}

/*
 * Equivalent to #terminate.
 * This method is obsolete; use #terminate instead.
 */
static VALUE
strscan_clear(VALUE self)
{
    rb_warning("StringScanner#clear is obsolete; use #terminate instead");
    return strscan_terminate(self);
}

/*
 * Returns the string being scanned.
 */
static VALUE
strscan_get_string(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return p->str;
}

/*
 * call-seq: string=(str)
 *
 * Changes the string being scanned to +str+ and resets the scanner.
 * Returns +str+.
 */
static VALUE
strscan_set_string(VALUE self, VALUE str)
{
    struct strscanner *p = check_strscan(self);

    StringValue(str);
    p->str = str;
    p->curr = 0;
    CLEAR_MATCH_STATUS(p);
    return str;
}

/*
 * call-seq:
 *   concat(str)
 *   <<(str)
 *
 * Appends +str+ to the string being scanned.
 * This method does not affect scan pointer.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.scan(/Fri /)
 *   s << " +1000 GMT"
 *   s.string            # -> "Fri Dec 12 1975 14:39 +1000 GMT"
 *   s.scan(/Dec/)       # -> "Dec"
 */
static VALUE
strscan_concat(VALUE self, VALUE str)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    StringValue(str);
    rb_str_append(p->str, str);
    return self;
}

/*
 * Returns the byte position of the scan pointer.  In the 'reset' position, this
 * value is zero.  In the 'terminated' position (i.e. the string is exhausted),
 * this value is the bytesize of the string.
 *
 * In short, it's a 0-based index into bytes of the string.
 *
 *   s = StringScanner.new('test string')
 *   s.pos               # -> 0
 *   s.scan_until /str/  # -> "test str"
 *   s.pos               # -> 8
 *   s.terminate         # -> #<StringScanner fin>
 *   s.pos               # -> 11
 */
static VALUE
strscan_get_pos(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return INT2FIX(p->curr);
}

/*
 * Returns the character position of the scan pointer.  In the 'reset' position, this
 * value is zero.  In the 'terminated' position (i.e. the string is exhausted),
 * this value is the size of the string.
 *
 * In short, it's a 0-based index into the string.
 *
 *   s = StringScanner.new("abcädeföghi")
 *   s.charpos           # -> 0
 *   s.scan_until(/ä/)   # -> "abcä"
 *   s.pos               # -> 5
 *   s.charpos           # -> 4
 */
static VALUE
strscan_get_charpos(VALUE self)
{
    struct strscanner *p;
    VALUE substr;

    GET_SCANNER(self, p);

    substr = rb_funcall(p->str, id_byteslice, 2, INT2FIX(0), LONG2NUM(p->curr));

    return rb_str_length(substr);
}

/*
 * call-seq: pos=(n)
 *
 * Sets the byte position of the scan pointer.
 *
 *   s = StringScanner.new('test string')
 *   s.pos = 7            # -> 7
 *   s.rest               # -> "ring"
 */
static VALUE
strscan_set_pos(VALUE self, VALUE v)
{
    struct strscanner *p;
    long i;

    GET_SCANNER(self, p);
    i = NUM2INT(v);
    if (i < 0) i += S_LEN(p);
    if (i < 0) rb_raise(rb_eRangeError, "index out of range");
    if (i > S_LEN(p)) rb_raise(rb_eRangeError, "index out of range");
    p->curr = i;
    return LONG2NUM(i);
}

static inline UChar *
match_target(struct strscanner *p)
{
    if (p->fixed_anchor_p) {
        return (UChar *)S_PBEG(p);
    }
    else
    {
        return (UChar *)CURPTR(p);
    }
}

static inline void
set_registers(struct strscanner *p, size_t length)
{
    const int at = 0;
    OnigRegion *regs = &(p->regs);
    onig_region_clear(regs);
    if (onig_region_set(regs, at, 0, 0)) return;
    if (p->fixed_anchor_p) {
        regs->beg[at] = p->curr;
        regs->end[at] = p->curr + length;
    }
    else
    {
        regs->end[at] = length;
    }
}

static inline void
succ(struct strscanner *p)
{
    if (p->fixed_anchor_p) {
        p->curr = p->regs.end[0];
    }
    else
    {
        p->curr += p->regs.end[0];
    }
}

static inline long
last_match_length(struct strscanner *p)
{
    if (p->fixed_anchor_p) {
        return p->regs.end[0] - p->prev;
    }
    else
    {
        return p->regs.end[0];
    }
}

static inline long
adjust_register_position(struct strscanner *p, long position)
{
    if (p->fixed_anchor_p) {
        return position;
    }
    else {
        return p->prev + position;
    }
}

static VALUE
strscan_do_scan(VALUE self, VALUE pattern, int succptr, int getstr, int headonly)
{
    struct strscanner *p;

    if (headonly) {
        if (!RB_TYPE_P(pattern, T_REGEXP)) {
            StringValue(pattern);
        }
    }
    else {
        Check_Type(pattern, T_REGEXP);
    }
    GET_SCANNER(self, p);

    CLEAR_MATCH_STATUS(p);
    if (S_RESTLEN(p) < 0) {
        return Qnil;
    }

    if (RB_TYPE_P(pattern, T_REGEXP)) {
        regex_t *rb_reg_prepare_re(VALUE re, VALUE str);
        regex_t *re;
        long ret;
        int tmpreg;

        p->regex = pattern;
        re = rb_reg_prepare_re(pattern, p->str);
        tmpreg = re != RREGEXP_PTR(pattern);
        if (!tmpreg) RREGEXP(pattern)->usecnt++;

        if (headonly) {
            ret = onig_match(re,
                             match_target(p),
                             (UChar* )(CURPTR(p) + S_RESTLEN(p)),
                             (UChar* )CURPTR(p),
                             &(p->regs),
                             ONIG_OPTION_NONE);
        }
        else {
            ret = onig_search(re,
                              match_target(p),
                              (UChar* )(CURPTR(p) + S_RESTLEN(p)),
                              (UChar* )CURPTR(p),
                              (UChar* )(CURPTR(p) + S_RESTLEN(p)),
                              &(p->regs),
                              ONIG_OPTION_NONE);
        }
        if (!tmpreg) RREGEXP(pattern)->usecnt--;
        if (tmpreg) {
            if (RREGEXP(pattern)->usecnt) {
                onig_free(re);
            }
            else {
                onig_free(RREGEXP_PTR(pattern));
                RREGEXP_PTR(pattern) = re;
            }
        }

        if (ret == -2) rb_raise(ScanError, "regexp buffer overflow");
        if (ret < 0) {
            /* not matched */
            return Qnil;
        }
    }
    else {
        rb_enc_check(p->str, pattern);
        if (S_RESTLEN(p) < RSTRING_LEN(pattern)) {
            return Qnil;
        }
        if (memcmp(CURPTR(p), RSTRING_PTR(pattern), RSTRING_LEN(pattern)) != 0) {
            return Qnil;
        }
        set_registers(p, RSTRING_LEN(pattern));
    }

    MATCHED(p);
    p->prev = p->curr;

    if (succptr) {
        succ(p);
    }
    {
        const long length = last_match_length(p);
        if (getstr) {
            return extract_beg_len(p, p->prev, length);
        }
        else {
            return INT2FIX(length);
        }
    }
}

/*
 * call-seq: scan(pattern) => String
 *
 * Tries to match with +pattern+ at the current position. If there's a match,
 * the scanner advances the "scan pointer" and returns the matched string.
 * Otherwise, the scanner returns +nil+.
 *
 *   s = StringScanner.new('test string')
 *   p s.scan(/\w+/)   # -> "test"
 *   p s.scan(/\w+/)   # -> nil
 *   p s.scan(/\s+/)   # -> " "
 *   p s.scan("str")   # -> "str"
 *   p s.scan(/\w+/)   # -> "ing"
 *   p s.scan(/./)     # -> nil
 *
 */
static VALUE
strscan_scan(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 1, 1);
}

/*
 * call-seq: match?(pattern)
 *
 * Tests whether the given +pattern+ is matched from the current scan pointer.
 * Returns the length of the match, or +nil+.  The scan pointer is not advanced.
 *
 *   s = StringScanner.new('test string')
 *   p s.match?(/\w+/)   # -> 4
 *   p s.match?(/\w+/)   # -> 4
 *   p s.match?("test")  # -> 4
 *   p s.match?(/\s+/)   # -> nil
 */
static VALUE
strscan_match_p(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 0, 1);
}

/*
 * call-seq: skip(pattern)
 *
 * Attempts to skip over the given +pattern+ beginning with the scan pointer.
 * If it matches, the scan pointer is advanced to the end of the match, and the
 * length of the match is returned.  Otherwise, +nil+ is returned.
 *
 * It's similar to #scan, but without returning the matched string.
 *
 *   s = StringScanner.new('test string')
 *   p s.skip(/\w+/)   # -> 4
 *   p s.skip(/\w+/)   # -> nil
 *   p s.skip(/\s+/)   # -> 1
 *   p s.skip("st")    # -> 2
 *   p s.skip(/\w+/)   # -> 4
 *   p s.skip(/./)     # -> nil
 *
 */
static VALUE
strscan_skip(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 0, 1);
}

/*
 * call-seq: check(pattern)
 *
 * This returns the value that #scan would return, without advancing the scan
 * pointer.  The match register is affected, though.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.check /Fri/               # -> "Fri"
 *   s.pos                       # -> 0
 *   s.matched                   # -> "Fri"
 *   s.check /12/                # -> nil
 *   s.matched                   # -> nil
 *
 * Mnemonic: it "checks" to see whether a #scan will return a value.
 */
static VALUE
strscan_check(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 1, 1);
}

/*
 * call-seq: scan_full(pattern, advance_pointer_p, return_string_p)
 *
 * Tests whether the given +pattern+ is matched from the current scan pointer.
 * Advances the scan pointer if +advance_pointer_p+ is true.
 * Returns the matched string if +return_string_p+ is true.
 * The match register is affected.
 *
 * "full" means "#scan with full parameters".
 */
static VALUE
strscan_scan_full(VALUE self, VALUE re, VALUE s, VALUE f)
{
    return strscan_do_scan(self, re, RTEST(s), RTEST(f), 1);
}

/*
 * call-seq: scan_until(pattern)
 *
 * Scans the string _until_ the +pattern+ is matched.  Returns the substring up
 * to and including the end of the match, advancing the scan pointer to that
 * location. If there is no match, +nil+ is returned.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.scan_until(/1/)        # -> "Fri Dec 1"
 *   s.pre_match              # -> "Fri Dec "
 *   s.scan_until(/XYZ/)      # -> nil
 */
static VALUE
strscan_scan_until(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 1, 0);
}

/*
 * call-seq: exist?(pattern)
 *
 * Looks _ahead_ to see if the +pattern+ exists _anywhere_ in the string,
 * without advancing the scan pointer.  This predicates whether a #scan_until
 * will return a value.
 *
 *   s = StringScanner.new('test string')
 *   s.exist? /s/            # -> 3
 *   s.scan /test/           # -> "test"
 *   s.exist? /s/            # -> 2
 *   s.exist? /e/            # -> nil
 */
static VALUE
strscan_exist_p(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 0, 0);
}

/*
 * call-seq: skip_until(pattern)
 *
 * Advances the scan pointer until +pattern+ is matched and consumed.  Returns
 * the number of bytes advanced, or +nil+ if no match was found.
 *
 * Look ahead to match +pattern+, and advance the scan pointer to the _end_
 * of the match.  Return the number of characters advanced, or +nil+ if the
 * match was unsuccessful.
 *
 * It's similar to #scan_until, but without returning the intervening string.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.skip_until /12/           # -> 10
 *   s                           #
 */
static VALUE
strscan_skip_until(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 0, 0);
}

/*
 * call-seq: check_until(pattern)
 *
 * This returns the value that #scan_until would return, without advancing the
 * scan pointer.  The match register is affected, though.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.check_until /12/          # -> "Fri Dec 12"
 *   s.pos                       # -> 0
 *   s.matched                   # -> 12
 *
 * Mnemonic: it "checks" to see whether a #scan_until will return a value.
 */
static VALUE
strscan_check_until(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 1, 0);
}

/*
 * call-seq: search_full(pattern, advance_pointer_p, return_string_p)
 *
 * Scans the string _until_ the +pattern+ is matched.
 * Advances the scan pointer if +advance_pointer_p+, otherwise not.
 * Returns the matched string if +return_string_p+ is true, otherwise
 * returns the number of bytes advanced.
 * This method does affect the match register.
 */
static VALUE
strscan_search_full(VALUE self, VALUE re, VALUE s, VALUE f)
{
    return strscan_do_scan(self, re, RTEST(s), RTEST(f), 0);
}

static void
adjust_registers_to_matched(struct strscanner *p)
{
    onig_region_clear(&(p->regs));
    if (p->fixed_anchor_p) {
        onig_region_set(&(p->regs), 0, (int)p->prev, (int)p->curr);
    }
    else {
        onig_region_set(&(p->regs), 0, 0, (int)(p->curr - p->prev));
    }
}

/*
 * Scans one character and returns it.
 * This method is multibyte character sensitive.
 *
 *   s = StringScanner.new("ab")
 *   s.getch           # => "a"
 *   s.getch           # => "b"
 *   s.getch           # => nil
 *
 *   s = StringScanner.new("\244\242".force_encoding("euc-jp"))
 *   s.getch           # => "\x{A4A2}"   # Japanese hira-kana "A" in EUC-JP
 *   s.getch           # => nil
 */
static VALUE
strscan_getch(VALUE self)
{
    struct strscanner *p;
    long len;

    GET_SCANNER(self, p);
    CLEAR_MATCH_STATUS(p);
    if (EOS_P(p))
        return Qnil;

    len = rb_enc_mbclen(CURPTR(p), S_PEND(p), rb_enc_get(p->str));
    len = minl(len, S_RESTLEN(p));
    p->prev = p->curr;
    p->curr += len;
    MATCHED(p);
    adjust_registers_to_matched(p);
    return extract_range(p,
                         adjust_register_position(p, p->regs.beg[0]),
                         adjust_register_position(p, p->regs.end[0]));
}

/*
 * Scans one byte and returns it.
 * This method is not multibyte character sensitive.
 * See also: #getch.
 *
 *   s = StringScanner.new('ab')
 *   s.get_byte         # => "a"
 *   s.get_byte         # => "b"
 *   s.get_byte         # => nil
 *
 *   s = StringScanner.new("\244\242".force_encoding("euc-jp"))
 *   s.get_byte         # => "\xA4"
 *   s.get_byte         # => "\xA2"
 *   s.get_byte         # => nil
 */
static VALUE
strscan_get_byte(VALUE self)
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
    return extract_range(p,
                         adjust_register_position(p, p->regs.beg[0]),
                         adjust_register_position(p, p->regs.end[0]));
}

/*
 * Equivalent to #get_byte.
 * This method is obsolete; use #get_byte instead.
 */
static VALUE
strscan_getbyte(VALUE self)
{
    rb_warning("StringScanner#getbyte is obsolete; use #get_byte instead");
    return strscan_get_byte(self);
}

/*
 * call-seq: peek(len)
 *
 * Extracts a string corresponding to <tt>string[pos,len]</tt>, without
 * advancing the scan pointer.
 *
 *   s = StringScanner.new('test string')
 *   s.peek(7)          # => "test st"
 *   s.peek(7)          # => "test st"
 *
 */
static VALUE
strscan_peek(VALUE self, VALUE vlen)
{
    struct strscanner *p;
    long len;

    GET_SCANNER(self, p);

    len = NUM2LONG(vlen);
    if (EOS_P(p))
        return str_new(p, "", 0);

    len = minl(len, S_RESTLEN(p));
    return extract_beg_len(p, p->curr, len);
}

/*
 * Equivalent to #peek.
 * This method is obsolete; use #peek instead.
 */
static VALUE
strscan_peep(VALUE self, VALUE vlen)
{
    rb_warning("StringScanner#peep is obsolete; use #peek instead");
    return strscan_peek(self, vlen);
}

/*
 * Sets the scan pointer to the previous position.  Only one previous position is
 * remembered, and it changes with each scanning operation.
 *
 *   s = StringScanner.new('test string')
 *   s.scan(/\w+/)        # => "test"
 *   s.unscan
 *   s.scan(/../)         # => "te"
 *   s.scan(/\d/)         # => nil
 *   s.unscan             # ScanError: unscan failed: previous match record not exist
 */
static VALUE
strscan_unscan(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))
        rb_raise(ScanError, "unscan failed: previous match record not exist");
    p->curr = p->prev;
    CLEAR_MATCH_STATUS(p);
    return self;
}

/*
 * Returns +true+ iff the scan pointer is at the beginning of the line.
 *
 *   s = StringScanner.new("test\ntest\n")
 *   s.bol?           # => true
 *   s.scan(/te/)
 *   s.bol?           # => false
 *   s.scan(/st\n/)
 *   s.bol?           # => true
 *   s.terminate
 *   s.bol?           # => true
 */
static VALUE
strscan_bol_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (CURPTR(p) > S_PEND(p)) return Qnil;
    if (p->curr == 0) return Qtrue;
    return (*(CURPTR(p) - 1) == '\n') ? Qtrue : Qfalse;
}

/*
 * Returns +true+ if the scan pointer is at the end of the string.
 *
 *   s = StringScanner.new('test string')
 *   p s.eos?          # => false
 *   s.scan(/test/)
 *   p s.eos?          # => false
 *   s.terminate
 *   p s.eos?          # => true
 */
static VALUE
strscan_eos_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return EOS_P(p) ? Qtrue : Qfalse;
}

/*
 * Equivalent to #eos?.
 * This method is obsolete, use #eos? instead.
 */
static VALUE
strscan_empty_p(VALUE self)
{
    rb_warning("StringScanner#empty? is obsolete; use #eos? instead");
    return strscan_eos_p(self);
}

/*
 * Returns true iff there is more data in the string.  See #eos?.
 * This method is obsolete; use #eos? instead.
 *
 *   s = StringScanner.new('test string')
 *   s.eos?              # These two
 *   s.rest?             # are opposites.
 */
static VALUE
strscan_rest_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return EOS_P(p) ? Qfalse : Qtrue;
}

/*
 * Returns +true+ iff the last match was successful.
 *
 *   s = StringScanner.new('test string')
 *   s.match?(/\w+/)     # => 4
 *   s.matched?          # => true
 *   s.match?(/\d+/)     # => nil
 *   s.matched?          # => false
 */
static VALUE
strscan_matched_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return MATCHED_P(p) ? Qtrue : Qfalse;
}

/*
 * Returns the last matched string.
 *
 *   s = StringScanner.new('test string')
 *   s.match?(/\w+/)     # -> 4
 *   s.matched           # -> "test"
 */
static VALUE
strscan_matched(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;
    return extract_range(p,
                         adjust_register_position(p, p->regs.beg[0]),
                         adjust_register_position(p, p->regs.end[0]));
}

/*
 * Returns the size of the most recent match in bytes, or +nil+ if there
 * was no recent match.  This is different than <tt>matched.size</tt>,
 * which will return the size in characters.
 *
 *   s = StringScanner.new('test string')
 *   s.check /\w+/           # -> "test"
 *   s.matched_size          # -> 4
 *   s.check /\d+/           # -> nil
 *   s.matched_size          # -> nil
 */
static VALUE
strscan_matched_size(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;
    return LONG2NUM(p->regs.end[0] - p->regs.beg[0]);
}

static int
name_to_backref_number(struct re_registers *regs, VALUE regexp, const char* name, const char* name_end, rb_encoding *enc)
{
    int num;

    num = onig_name_to_backref_number(RREGEXP_PTR(regexp),
	(const unsigned char* )name, (const unsigned char* )name_end, regs);
    if (num >= 1) {
	return num;
    }
    else {
	rb_enc_raise(enc, rb_eIndexError, "undefined group name reference: %.*s",
					  rb_long2int(name_end - name), name);
    }

    UNREACHABLE;
}

/*
 * call-seq: [](n)
 *
 * Returns the n-th subgroup in the most recent match.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.scan(/(\w+) (\w+) (\d+) /)       # -> "Fri Dec 12 "
 *   s[0]                               # -> "Fri Dec 12 "
 *   s[1]                               # -> "Fri"
 *   s[2]                               # -> "Dec"
 *   s[3]                               # -> "12"
 *   s.post_match                       # -> "1975 14:39"
 *   s.pre_match                        # -> ""
 *
 *   s.reset
 *   s.scan(/(?<wday>\w+) (?<month>\w+) (?<day>\d+) /)       # -> "Fri Dec 12 "
 *   s[0]                               # -> "Fri Dec 12 "
 *   s[1]                               # -> "Fri"
 *   s[2]                               # -> "Dec"
 *   s[3]                               # -> "12"
 *   s[:wday]                           # -> "Fri"
 *   s[:month]                          # -> "Dec"
 *   s[:day]                            # -> "12"
 *   s.post_match                       # -> "1975 14:39"
 *   s.pre_match                        # -> ""
 */
static VALUE
strscan_aref(VALUE self, VALUE idx)
{
    const char *name;
    struct strscanner *p;
    long i;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))        return Qnil;

    switch (TYPE(idx)) {
        case T_SYMBOL:
            idx = rb_sym2str(idx);
            /* fall through */
        case T_STRING:
            if (!RTEST(p->regex)) return Qnil;
            RSTRING_GETMEM(idx, name, i);
            i = name_to_backref_number(&(p->regs), p->regex, name, name + i, rb_enc_get(idx));
            break;
        default:
            i = NUM2LONG(idx);
    }

    if (i < 0)
        i += p->regs.num_regs;
    if (i < 0)                 return Qnil;
    if (i >= p->regs.num_regs) return Qnil;
    if (p->regs.beg[i] == -1)  return Qnil;

    return extract_range(p,
                         adjust_register_position(p, p->regs.beg[i]),
                         adjust_register_position(p, p->regs.end[i]));
}

/*
 * call-seq: size
 *
 * Returns the amount of subgroups in the most recent match.
 * The full match counts as a subgroup.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.scan(/(\w+) (\w+) (\d+) /)       # -> "Fri Dec 12 "
 *   s.size                             # -> 4
 */
static VALUE
strscan_size(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))        return Qnil;
    return INT2FIX(p->regs.num_regs);
}

/*
 * call-seq: captures
 *
 * Returns the subgroups in the most recent match (not including the full match).
 * If nothing was priorly matched, it returns nil.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.scan(/(\w+) (\w+) (\d+) /)       # -> "Fri Dec 12 "
 *   s.captures                         # -> ["Fri", "Dec", "12"]
 *   s.scan(/(\w+) (\w+) (\d+) /)       # -> nil
 *   s.captures                         # -> nil
 */
static VALUE
strscan_captures(VALUE self)
{
    struct strscanner *p;
    int   i, num_regs;
    VALUE new_ary;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))        return Qnil;

    num_regs = p->regs.num_regs;
    new_ary  = rb_ary_new2(num_regs);

    for (i = 1; i < num_regs; i++) {
        VALUE str = extract_range(p,
                                  adjust_register_position(p, p->regs.beg[i]),
                                  adjust_register_position(p, p->regs.end[i]));
        rb_ary_push(new_ary, str);
    }

    return new_ary;
}

/*
 *  call-seq:
 *     scanner.values_at( i1, i2, ... iN )   -> an_array
 *
 * Returns the subgroups in the most recent match at the given indices.
 * If nothing was priorly matched, it returns nil.
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.scan(/(\w+) (\w+) (\d+) /)       # -> "Fri Dec 12 "
 *   s.values_at 0, -1, 5, 2            # -> ["Fri Dec 12 ", "12", nil, "Dec"]
 *   s.scan(/(\w+) (\w+) (\d+) /)       # -> nil
 *   s.values_at 0, -1, 5, 2            # -> nil
 */

static VALUE
strscan_values_at(int argc, VALUE *argv, VALUE self)
{
    struct strscanner *p;
    long i;
    VALUE new_ary;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p))        return Qnil;

    new_ary = rb_ary_new2(argc);
    for (i = 0; i<argc; i++) {
        rb_ary_push(new_ary, strscan_aref(self, argv[i]));
    }

    return new_ary;
}

/*
 * Returns the <i><b>pre</b>-match</i> (in the regular expression sense) of the last scan.
 *
 *   s = StringScanner.new('test string')
 *   s.scan(/\w+/)           # -> "test"
 *   s.scan(/\s+/)           # -> " "
 *   s.pre_match             # -> "test"
 *   s.post_match            # -> "string"
 */
static VALUE
strscan_pre_match(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;
    return extract_range(p,
                         0,
                         adjust_register_position(p, p->regs.beg[0]));
}

/*
 * Returns the <i><b>post</b>-match</i> (in the regular expression sense) of the last scan.
 *
 *   s = StringScanner.new('test string')
 *   s.scan(/\w+/)           # -> "test"
 *   s.scan(/\s+/)           # -> " "
 *   s.pre_match             # -> "test"
 *   s.post_match            # -> "string"
 */
static VALUE
strscan_post_match(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (! MATCHED_P(p)) return Qnil;
    return extract_range(p,
                         adjust_register_position(p, p->regs.end[0]),
                         S_LEN(p));
}

/*
 * Returns the "rest" of the string (i.e. everything after the scan pointer).
 * If there is no more data (eos? = true), it returns <tt>""</tt>.
 */
static VALUE
strscan_rest(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (EOS_P(p)) {
        return str_new(p, "", 0);
    }
    return extract_range(p, p->curr, S_LEN(p));
}

/*
 * <tt>s.rest_size</tt> is equivalent to <tt>s.rest.size</tt>.
 */
static VALUE
strscan_rest_size(VALUE self)
{
    struct strscanner *p;
    long i;

    GET_SCANNER(self, p);
    if (EOS_P(p)) {
        return INT2FIX(0);
    }
    i = S_RESTLEN(p);
    return INT2FIX(i);
}

/*
 * <tt>s.restsize</tt> is equivalent to <tt>s.rest_size</tt>.
 * This method is obsolete; use #rest_size instead.
 */
static VALUE
strscan_restsize(VALUE self)
{
    rb_warning("StringScanner#restsize is obsolete; use #rest_size instead");
    return strscan_rest_size(self);
}

#define INSPECT_LENGTH 5

/*
 * Returns a string that represents the StringScanner object, showing:
 * - the current position
 * - the size of the string
 * - the characters surrounding the scan pointer
 *
 *   s = StringScanner.new("Fri Dec 12 1975 14:39")
 *   s.inspect            # -> '#<StringScanner 0/21 @ "Fri D...">'
 *   s.scan_until /12/    # -> "Fri Dec 12"
 *   s.inspect            # -> '#<StringScanner 10/21 "...ec 12" @ " 1975...">'
 */
static VALUE
strscan_inspect(VALUE self)
{
    struct strscanner *p;
    VALUE a, b;

    p = check_strscan(self);
    if (NIL_P(p->str)) {
	a = rb_sprintf("#<%"PRIsVALUE" (uninitialized)>", rb_obj_class(self));
	return a;
    }
    if (EOS_P(p)) {
	a = rb_sprintf("#<%"PRIsVALUE" fin>", rb_obj_class(self));
	return a;
    }
    if (p->curr == 0) {
	b = inspect2(p);
	a = rb_sprintf("#<%"PRIsVALUE" %ld/%ld @ %"PRIsVALUE">",
		       rb_obj_class(self),
		       p->curr, S_LEN(p),
		       b);
	return a;
    }
    a = inspect1(p);
    b = inspect2(p);
    a = rb_sprintf("#<%"PRIsVALUE" %ld/%ld %"PRIsVALUE" @ %"PRIsVALUE">",
		   rb_obj_class(self),
		   p->curr, S_LEN(p),
		   a, b);
    return a;
}

static VALUE
inspect1(struct strscanner *p)
{
    VALUE str;
    long len;

    if (p->curr == 0) return rb_str_new2("");
    if (p->curr > INSPECT_LENGTH) {
	str = rb_str_new_cstr("...");
	len = INSPECT_LENGTH;
    }
    else {
	str = rb_str_new(0, 0);
	len = p->curr;
    }
    rb_str_cat(str, CURPTR(p) - len, len);
    return rb_str_dump(str);
}

static VALUE
inspect2(struct strscanner *p)
{
    VALUE str;
    long len;

    if (EOS_P(p)) return rb_str_new2("");
    len = S_RESTLEN(p);
    if (len > INSPECT_LENGTH) {
	str = rb_str_new(CURPTR(p), INSPECT_LENGTH);
	rb_str_cat2(str, "...");
    }
    else {
	str = rb_str_new(CURPTR(p), len);
    }
    return rb_str_dump(str);
}

/*
 * call-seq:
 *    scanner.fixed_anchor? -> true or false
 *
 * Whether +scanner+ uses fixed anchor mode or not.
 *
 * If fixed anchor mode is used, +\A+ always matches the beginning of
 * the string. Otherwise, +\A+ always matches the current position.
 */
static VALUE
strscan_fixed_anchor_p(VALUE self)
{
    struct strscanner *p;
    p = check_strscan(self);
    return p->fixed_anchor_p ? Qtrue : Qfalse;
}

/* =======================================================================
                              Ruby Interface
   ======================================================================= */

/*
 * Document-class: StringScanner
 *
 * StringScanner provides for lexical scanning operations on a String.  Here is
 * an example of its usage:
 *
 *   s = StringScanner.new('This is an example string')
 *   s.eos?               # -> false
 *
 *   p s.scan(/\w+/)      # -> "This"
 *   p s.scan(/\w+/)      # -> nil
 *   p s.scan(/\s+/)      # -> " "
 *   p s.scan(/\s+/)      # -> nil
 *   p s.scan(/\w+/)      # -> "is"
 *   s.eos?               # -> false
 *
 *   p s.scan(/\s+/)      # -> " "
 *   p s.scan(/\w+/)      # -> "an"
 *   p s.scan(/\s+/)      # -> " "
 *   p s.scan(/\w+/)      # -> "example"
 *   p s.scan(/\s+/)      # -> " "
 *   p s.scan(/\w+/)      # -> "string"
 *   s.eos?               # -> true
 *
 *   p s.scan(/\s+/)      # -> nil
 *   p s.scan(/\w+/)      # -> nil
 *
 * Scanning a string means remembering the position of a <i>scan pointer</i>,
 * which is just an index.  The point of scanning is to move forward a bit at
 * a time, so matches are sought after the scan pointer; usually immediately
 * after it.
 *
 * Given the string "test string", here are the pertinent scan pointer
 * positions:
 *
 *     t e s t   s t r i n g
 *   0 1 2 ...             1
 *                         0
 *
 * When you #scan for a pattern (a regular expression), the match must occur
 * at the character after the scan pointer.  If you use #scan_until, then the
 * match can occur anywhere after the scan pointer.  In both cases, the scan
 * pointer moves <i>just beyond</i> the last character of the match, ready to
 * scan again from the next character onwards.  This is demonstrated by the
 * example above.
 *
 * == Method Categories
 *
 * There are other methods besides the plain scanners.  You can look ahead in
 * the string without actually scanning.  You can access the most recent match.
 * You can modify the string being scanned, reset or terminate the scanner,
 * find out or change the position of the scan pointer, skip ahead, and so on.
 *
 * === Advancing the Scan Pointer
 *
 * - #getch
 * - #get_byte
 * - #scan
 * - #scan_until
 * - #skip
 * - #skip_until
 *
 * === Looking Ahead
 *
 * - #check
 * - #check_until
 * - #exist?
 * - #match?
 * - #peek
 *
 * === Finding Where we Are
 *
 * - #beginning_of_line? (#bol?)
 * - #eos?
 * - #rest?
 * - #rest_size
 * - #pos
 *
 * === Setting Where we Are
 *
 * - #reset
 * - #terminate
 * - #pos=
 *
 * === Match Data
 *
 * - #matched
 * - #matched?
 * - #matched_size
 * - []
 * - #pre_match
 * - #post_match
 *
 * === Miscellaneous
 *
 * - <<
 * - #concat
 * - #string
 * - #string=
 * - #unscan
 *
 * There are aliases to several of the methods.
 */
void
Init_strscan(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

#undef rb_intern
    ID id_scanerr = rb_intern("ScanError");
    VALUE tmp;

    id_byteslice = rb_intern("byteslice");

    StringScanner = rb_define_class("StringScanner", rb_cObject);
    ScanError = rb_define_class_under(StringScanner, "Error", rb_eStandardError);
    if (!rb_const_defined(rb_cObject, id_scanerr)) {
	rb_const_set(rb_cObject, id_scanerr, ScanError);
    }
    tmp = rb_str_new2(STRSCAN_VERSION);
    rb_obj_freeze(tmp);
    rb_const_set(StringScanner, rb_intern("Version"), tmp);
    tmp = rb_str_new2("$Id$");
    rb_obj_freeze(tmp);
    rb_const_set(StringScanner, rb_intern("Id"), tmp);

    rb_define_alloc_func(StringScanner, strscan_s_allocate);
    rb_define_private_method(StringScanner, "initialize", strscan_initialize, -1);
    rb_define_private_method(StringScanner, "initialize_copy", strscan_init_copy, 1);
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
    rb_define_method(StringScanner, "charpos",     strscan_get_charpos, 0);
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
    rb_alias(StringScanner, rb_intern("bol?"), rb_intern("beginning_of_line?"));
    rb_define_method(StringScanner, "eos?",        strscan_eos_p,       0);
    rb_define_method(StringScanner, "empty?",      strscan_empty_p,     0);
    rb_define_method(StringScanner, "rest?",       strscan_rest_p,      0);

    rb_define_method(StringScanner, "matched?",    strscan_matched_p,   0);
    rb_define_method(StringScanner, "matched",     strscan_matched,     0);
    rb_define_method(StringScanner, "matched_size", strscan_matched_size, 0);
    rb_define_method(StringScanner, "[]",          strscan_aref,        1);
    rb_define_method(StringScanner, "pre_match",   strscan_pre_match,   0);
    rb_define_method(StringScanner, "post_match",  strscan_post_match,  0);
    rb_define_method(StringScanner, "size",        strscan_size,        0);
    rb_define_method(StringScanner, "captures",    strscan_captures,    0);
    rb_define_method(StringScanner, "values_at",   strscan_values_at,  -1);

    rb_define_method(StringScanner, "rest",        strscan_rest,        0);
    rb_define_method(StringScanner, "rest_size",   strscan_rest_size,   0);
    rb_define_method(StringScanner, "restsize",    strscan_restsize,    0);

    rb_define_method(StringScanner, "inspect",     strscan_inspect,     0);

    rb_define_method(StringScanner, "fixed_anchor?", strscan_fixed_anchor_p, 0);
}
