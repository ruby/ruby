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

#define STRSCAN_VERSION "3.1.1"

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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   StringScanner.new(string, fixed_anchor: false) -> string_scanner
 *
 * Returns a new `StringScanner` object whose [stored string][1]
 * is the given `string`;
 * sets the [fixed-anchor property][10]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.string        # => "foobarbaz"
 * scanner.fixed_anchor? # => false
 * put_situation(scanner)
 * # Situation:
 * #   pos:       0
 * #   charpos:   0
 * #   rest:      "foobarbaz"
 * #   rest_size: 9
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   dup -> shallow_copy
 *
 * Returns a shallow copy of `self`;
 * the [stored string][1] in the copy is the same string as in `self`.
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
 * call-seq:
 *   StringScanner.must_C_version -> self
 *
 * Returns +self+; defined for backward compatibility.
 */

 /* :nodoc: */
static VALUE
strscan_s_mustc(VALUE self)
{
    return self;
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   reset -> self
 *
 * Sets both [byte position][2] and [character position][7] to zero,
 * and clears [match values][9];
 * returns +self+:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.exist?(/bar/)          # => 6
 * scanner.reset                  # => #<StringScanner 0/9 @ "fooba...">
 * put_situation(scanner)
 * # Situation:
 * #   pos:       0
 * #   charpos:   0
 * #   rest:      "foobarbaz"
 * #   rest_size: 9
 * # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   terminate -> self
 *
 * Sets the scanner to end-of-string;
 * returns +self+:
 *
 * - Sets both [positions][11] to end-of-stream.
 * - Clears [match values][9].
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string                 # => "こんにちは"
 * scanner.scan_until(/に/)
 * put_situation(scanner)
 * # Situation:
 * #   pos:       9
 * #   charpos:   3
 * #   rest:      "ちは"
 * #   rest_size: 6
 * match_values_cleared?(scanner) # => false
 *
 * scanner.terminate              # => #<StringScanner fin>
 * put_situation(scanner)
 * # Situation:
 * #   pos:       15
 * #   charpos:   5
 * #   rest:      ""
 * #   rest_size: 0
 * match_values_cleared?(scanner) # => true
 * ```
 *
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
 * call-seq:
 *   clear -> self
 *
 * This method is obsolete; use the equivalent method StringScanner#terminate.
 */

 /* :nodoc: */
static VALUE
strscan_clear(VALUE self)
{
    rb_warning("StringScanner#clear is obsolete; use #terminate instead");
    return strscan_terminate(self);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   string -> stored_string
 *
 * Returns the [stored string][1]:
 *
 * ```
 * scanner = StringScanner.new('foobar')
 * scanner.string # => "foobar"
 * scanner.concat('baz')
 * scanner.string # => "foobarbaz"
 * ```
 *
 */
static VALUE
strscan_get_string(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return p->str;
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   string = other_string -> other_string
 *
 * Replaces the [stored string][1] with the given `other_string`:
 *
 * - Sets both [positions][11] to zero.
 * - Clears [match values][9].
 * - Returns `other_string`.
 *
 * ```
 * scanner = StringScanner.new('foobar')
 * scanner.scan(/foo/)
 * put_situation(scanner)
 * # Situation:
 * #   pos:       3
 * #   charpos:   3
 * #   rest:      "bar"
 * #   rest_size: 3
 * match_values_cleared?(scanner) # => false
 *
 * scanner.string = 'baz'         # => "baz"
 * put_situation(scanner)
 * # Situation:
 * #   pos:       0
 * #   charpos:   0
 * #   rest:      "baz"
 * #   rest_size: 3
 * match_values_cleared?(scanner) # => true
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   concat(more_string) -> self
 *
 * - Appends the given `more_string`
 *   to the [stored string][1].
 * - Returns `self`.
 * - Does not affect the [positions][11]
 *   or [match values][9].
 *
 *
 * ```
 * scanner = StringScanner.new('foo')
 * scanner.string           # => "foo"
 * scanner.terminate
 * scanner.concat('barbaz') # => #<StringScanner 3/9 "foo" @ "barba...">
 * scanner.string           # => "foobarbaz"
 * put_situation(scanner)
 * # Situation:
 * #   pos:       3
 * #   charpos:   3
 * #   rest:      "barbaz"
 * #   rest_size: 6
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   pos -> byte_position
 *
 * Returns the integer [byte position][2],
 * which may be different from the [character position][7]:
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string  # => "こんにちは"
 * scanner.pos     # => 0
 * scanner.getch   # => "こ" # 3-byte character.
 * scanner.charpos # => 1
 * scanner.pos     # => 3
 * ```
 *
 */
static VALUE
strscan_get_pos(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return INT2FIX(p->curr);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   charpos -> character_position
 *
 * Returns the [character position][7] (initially zero),
 * which may be different from the [byte position][2]
 * given by method #pos:
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string # => "こんにちは"
 * scanner.getch  # => "こ" # 3-byte character.
 * scanner.getch  # => "ん" # 3-byte character.
 * put_situation(scanner)
 * # Situation:
 * #   pos:       6
 * #   charpos:   2
 * #   rest:      "にちは"
 * #   rest_size: 9
 * ```
 *
 */
static VALUE
strscan_get_charpos(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);

    return LONG2NUM(rb_enc_strlen(S_PBEG(p), CURPTR(p), rb_enc_get(p->str)));
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   pos = n -> n
 *
 * Sets the [byte position][2] and the [character position][11];
 * returns `n`.
 *
 * Does not affect [match values][9].
 *
 * For non-negative `n`, sets the position to `n`:
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string  # => "こんにちは"
 * scanner.pos = 3 # => 3
 * scanner.rest    # => "んにちは"
 * scanner.charpos # => 1
 * ```
 *
 * For negative `n`, counts from the end of the [stored string][1]:
 *
 * ```
 * scanner.pos = -9 # => -9
 * scanner.pos      # => 6
 * scanner.rest     # => "にちは"
 * scanner.charpos  # => 2
 * ```
 *
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

/* rb_reg_onig_match is available in Ruby 3.3 and later. */
#ifndef HAVE_RB_REG_ONIG_MATCH
static OnigPosition
rb_reg_onig_match(VALUE re, VALUE str,
                  OnigPosition (*match)(regex_t *reg, VALUE str, struct re_registers *regs, void *args),
                  void *args, struct re_registers *regs)
{
    regex_t *reg = rb_reg_prepare_re(re, str);

    bool tmpreg = reg != RREGEXP_PTR(re);
    if (!tmpreg) RREGEXP(re)->usecnt++;

    OnigPosition result = match(reg, str, regs, args);

    if (!tmpreg) RREGEXP(re)->usecnt--;
    if (tmpreg) {
        if (RREGEXP(re)->usecnt) {
            onig_free(reg);
        }
        else {
            onig_free(RREGEXP_PTR(re));
            RREGEXP_PTR(re) = reg;
        }
    }

    if (result < 0) {
        if (result != ONIG_MISMATCH) {
            rb_raise(ScanError, "regexp buffer overflow");
        }
    }

    return result;
}
#endif

static OnigPosition
strscan_match(regex_t *reg, VALUE str, struct re_registers *regs, void *args_ptr)
{
    struct strscanner *p = (struct strscanner *)args_ptr;

    return onig_match(reg,
                      match_target(p),
                      (UChar* )(CURPTR(p) + S_RESTLEN(p)),
                      (UChar* )CURPTR(p),
                      regs,
                      ONIG_OPTION_NONE);
}

static OnigPosition
strscan_search(regex_t *reg, VALUE str, struct re_registers *regs, void *args_ptr)
{
    struct strscanner *p = (struct strscanner *)args_ptr;

    return onig_search(reg,
                       match_target(p),
                       (UChar *)(CURPTR(p) + S_RESTLEN(p)),
                       (UChar *)CURPTR(p),
                       (UChar *)(CURPTR(p) + S_RESTLEN(p)),
                       regs,
                       ONIG_OPTION_NONE);
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
        p->regex = pattern;
        OnigPosition ret = rb_reg_onig_match(pattern,
                                             p->str,
                                             headonly ? strscan_match : strscan_search,
                                             (void *)p,
                                             &(p->regs));

        if (ret == ONIG_MISMATCH) {
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   scan(pattern) -> substring or nil
 *
 * Attempts to [match][17] the given `pattern`
 * at the beginning of the [target substring][3].
 *
 * If the match succeeds:
 *
 * - Returns the matched substring.
 * - Increments the [byte position][2] by <tt>substring.bytesize</tt>,
 *   and may increment the [character position][7].
 * - Sets [match values][9].
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string     # => "こんにちは"
 * scanner.pos = 6
 * scanner.scan(/に/) # => "に"
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "こん"
 * #   matched  :      "に"
 * #   post_match:     "ちは"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["に", nil]
 * #   []:
 * #     [0]:          "に"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       9
 * #   charpos:   3
 * #   rest:      "ちは"
 * #   rest_size: 6
 * ```
 *
 * If the match fails:
 *
 * - Returns `nil`.
 * - Does not increment byte and character positions.
 * - Clears match values.
 *
 * ```
 * scanner.scan(/nope/)           # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_scan(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 1, 1);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   match?(pattern) -> updated_position or nil
 *
 * Attempts to [match][17] the given `pattern`
 * at the beginning of the [target substring][3];
 * does not modify the [positions][11].
 *
 * If the match succeeds:
 *
 * - Sets [match values][9].
 * - Returns the size in bytes of the matched substring.
 *
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.pos = 3
 * scanner.match?(/bar/) => 3
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "foo"
 * #   matched  :      "bar"
 * #   post_match:     "baz"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["bar", nil]
 * #   []:
 * #     [0]:          "bar"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       3
 * #   charpos:   3
 * #   rest:      "barbaz"
 * #   rest_size: 6
 * ```
 *
 * If the match fails:
 *
 * - Clears match values.
 * - Returns `nil`.
 * - Does not increment positions.
 *
 * ```
 * scanner.match?(/nope/)         # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_match_p(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 0, 1);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   skip(pattern) match_size or nil
 *
 * Attempts to [match][17] the given `pattern`
 * at the beginning of the [target substring][3];
 *
 * If the match succeeds:
 *
 * - Increments the [byte position][2] by substring.bytesize,
 *   and may increment the [character position][7].
 * - Sets [match values][9].
 * - Returns the size (bytes) of the matched substring.
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string                  # => "こんにちは"
 * scanner.pos = 6
 * scanner.skip(/に/)              # => 3
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "こん"
 * #   matched  :      "に"
 * #   post_match:     "ちは"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["に", nil]
 * #   []:
 * #     [0]:          "に"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       9
 * #   charpos:   3
 * #   rest:      "ちは"
 * #   rest_size: 6
 *
 * scanner.skip(/nope/)            # => nil
 * match_values_cleared?(scanner)  # => true
 * ```
 *
 */
static VALUE
strscan_skip(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 0, 1);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   check(pattern) -> matched_substring or nil
 *
 * Attempts to [match][17] the given `pattern`
 * at the beginning of the [target substring][3];
 * does not modify the [positions][11].
 *
 * If the match succeeds:
 *
 * - Returns the matched substring.
 * - Sets all [match values][9].
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.pos = 3
 * scanner.check('bar') # => "bar"
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "foo"
 * #   matched  :      "bar"
 * #   post_match:     "baz"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["bar", nil]
 * #   []:
 * #     [0]:          "bar"
 * #     [1]:          nil
 * # => 0..1
 * put_situation(scanner)
 * # Situation:
 * #   pos:       3
 * #   charpos:   3
 * #   rest:      "barbaz"
 * #   rest_size: 6
 * ```
 *
 * If the match fails:
 *
 * - Returns `nil`.
 * - Clears all [match values][9].
 *
 * ```
 * scanner.check(/nope/)          # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_check(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 1, 1);
}

/*
 * call-seq:
 *   scan_full(pattern, advance_pointer_p, return_string_p) -> matched_substring or nil
 *
 * Equivalent to one of the following:
 *
 * - +advance_pointer_p+ +true+:
 *
 *   - +return_string_p+ +true+: StringScanner#scan(pattern).
 *   - +return_string_p+ +false+: StringScanner#skip(pattern).
 *
 * - +advance_pointer_p+ +false+:
 *
 *   - +return_string_p+ +true+: StringScanner#check(pattern).
 *   - +return_string_p+ +false+: StringScanner#match?(pattern).
 *
 */

 /* :nodoc: */
static VALUE
strscan_scan_full(VALUE self, VALUE re, VALUE s, VALUE f)
{
    return strscan_do_scan(self, re, RTEST(s), RTEST(f), 1);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   scan_until(pattern) -> substring or nil
 *
 * Attempts to [match][17] the given `pattern`
 * anywhere (at any [position][2]) in the [target substring][3].
 *
 * If the match attempt succeeds:
 *
 * - Sets [match values][9].
 * - Sets the [byte position][2] to the end of the matched substring;
 *   may adjust the [character position][7].
 * - Returns the matched substring.
 *
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string           # => "こんにちは"
 * scanner.pos = 6
 * scanner.scan_until(/ち/) # => "にち"
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "こんに"
 * #   matched  :      "ち"
 * #   post_match:     "は"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["ち", nil]
 * #   []:
 * #     [0]:          "ち"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       12
 * #   charpos:   4
 * #   rest:      "は"
 * #   rest_size: 3
 * ```
 *
 * If the match attempt fails:
 *
 * - Clears match data.
 * - Returns `nil`.
 * - Does not update positions.
 *
 * ```
 * scanner.scan_until(/nope/)     # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_scan_until(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 1, 0);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   exist?(pattern) -> byte_offset or nil
 *
 * Attempts to [match][17] the given `pattern`
 * anywhere (at any [position][2])
 * n the [target substring][3];
 * does not modify the [positions][11].
 *
 * If the match succeeds:
 *
 * - Returns a byte offset:
 *   the distance in bytes between the current [position][2]
 *   and the end of the matched substring.
 * - Sets all [match values][9].
 *
 * ```
 * scanner = StringScanner.new('foobarbazbatbam')
 * scanner.pos = 6
 * scanner.exist?(/bat/) # => 6
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "foobarbaz"
 * #   matched  :      "bat"
 * #   post_match:     "bam"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["bat", nil]
 * #   []:
 * #     [0]:          "bat"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       6
 * #   charpos:   6
 * #   rest:      "bazbatbam"
 * #   rest_size: 9
 * ```
 *
 * If the match fails:
 *
 * - Returns `nil`.
 * - Clears all [match values][9].
 *
 * ```
 * scanner.exist?(/nope/)         # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_exist_p(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 0, 0);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   skip_until(pattern) -> matched_substring_size or nil
 *
 * Attempts to [match][17] the given `pattern`
 * anywhere (at any [position][2]) in the [target substring][3];
 * does not modify the positions.
 *
 * If the match attempt succeeds:
 *
 * - Sets [match values][9].
 * - Returns the size of the matched substring.
 *
 * ```
 * scanner = StringScanner.new(HIRAGANA_TEXT)
 * scanner.string           # => "こんにちは"
 * scanner.pos = 6
 * scanner.skip_until(/ち/) # => 6
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "こんに"
 * #   matched  :      "ち"
 * #   post_match:     "は"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["ち", nil]
 * #   []:
 * #     [0]:          "ち"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       12
 * #   charpos:   4
 * #   rest:      "は"
 * #   rest_size: 3
 * ```
 *
 * If the match attempt fails:
 *
 * - Clears match values.
 * - Returns `nil`.
 *
 * ```
 * scanner.skip_until(/nope/)     # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_skip_until(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 1, 0, 0);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   check_until(pattern) -> substring or nil
 *
 * Attempts to [match][17] the given `pattern`
 * anywhere (at any [position][2])
 * in the [target substring][3];
 * does not modify the [positions][11].
 *
 * If the match succeeds:
 *
 * - Sets all [match values][9].
 * - Returns the matched substring,
 *   which extends from the current [position][2]
 *   to the end of the matched substring.
 *
 * ```
 * scanner = StringScanner.new('foobarbazbatbam')
 * scanner.pos = 6
 * scanner.check_until(/bat/) # => "bazbat"
 * put_match_values(scanner)
 * # Basic match values:
 * #   matched?:       true
 * #   matched_size:   3
 * #   pre_match:      "foobarbaz"
 * #   matched  :      "bat"
 * #   post_match:     "bam"
 * # Captured match values:
 * #   size:           1
 * #   captures:       []
 * #   named_captures: {}
 * #   values_at:      ["bat", nil]
 * #   []:
 * #     [0]:          "bat"
 * #     [1]:          nil
 * put_situation(scanner)
 * # Situation:
 * #   pos:       6
 * #   charpos:   6
 * #   rest:      "bazbatbam"
 * #   rest_size: 9
 * ```
 *
 * If the match fails:
 *
 * - Clears all [match values][9].
 * - Returns `nil`.
 *
 * ```
 * scanner.check_until(/nope/)    # => nil
 * match_values_cleared?(scanner) # => true
 * ```
 *
 */
static VALUE
strscan_check_until(VALUE self, VALUE re)
{
    return strscan_do_scan(self, re, 0, 1, 0);
}

/*
 * call-seq:
 *   search_full(pattern, advance_pointer_p, return_string_p) -> matched_substring or position_delta or nil
 *
 * Equivalent to one of the following:
 *
 * - +advance_pointer_p+ +true+:
 *
 *   - +return_string_p+ +true+: StringScanner#scan_until(pattern).
 *   - +return_string_p+ +false+: StringScanner#skip_until(pattern).
 *
 * - +advance_pointer_p+ +false+:
 *
 *   - +return_string_p+ +true+: StringScanner#check_until(pattern).
 *   - +return_string_p+ +false+: StringScanner#exist?(pattern).
 *
 */

 /* :nodoc: */
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   getch -> character or nil
 *
 * Returns the next (possibly multibyte) character,
 * if available:
 *
 * - If the [position][2]
 *   is at the beginning of a character:
 *
 *     - Returns the character.
 *     - Increments the [character position][7] by 1.
 *     - Increments the [byte position][2]
 *       by the size (in bytes) of the character.
 *
 *     ```
 *     scanner = StringScanner.new(HIRAGANA_TEXT)
 *     scanner.string                                # => "こんにちは"
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["こ", 3, 1]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["ん", 6, 2]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["に", 9, 3]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["ち", 12, 4]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["は", 15, 5]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => [nil, 15, 5]
 *     ```
 *
 * - If the [position][2] is within a multi-byte character
 *   (that is, not at its beginning),
 *   behaves like #get_byte (returns a 1-byte character):
 *
 *     ```
 *     scanner.pos = 1
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["\x81", 2, 2]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["\x93", 3, 1]
 *     [scanner.getch, scanner.pos, scanner.charpos] # => ["ん", 6, 2]
 *     ```
 *
 * - If the [position][2] is at the end of the [stored string][1],
 *   returns `nil` and does not modify the positions:
 *
 *     ```
 *     scanner.terminate
 *     [scanner.getch, scanner.pos, scanner.charpos] # => [nil, 15, 5]
 *     ```
 *
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
 * call-seq:
 *   scan_byte -> integer_byte
 *
 * Scans one byte and returns it as an integer.
 * This method is not multibyte character sensitive.
 * See also: #getch.
 *
 */
static VALUE
strscan_scan_byte(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    CLEAR_MATCH_STATUS(p);
    if (EOS_P(p))
        return Qnil;

    VALUE byte = INT2FIX((unsigned char)*CURPTR(p));
    p->prev = p->curr;
    p->curr++;
    MATCHED(p);
    adjust_registers_to_matched(p);
    return byte;
}

/*
 * Peeks at the current byte and returns it as an integer.
 *
 *   s = StringScanner.new('ab')
 *   s.peek_byte         # => 97
 */
static VALUE
strscan_peek_byte(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    if (EOS_P(p))
        return Qnil;

    return INT2FIX((unsigned char)*CURPTR(p));
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   get_byte -> byte_as_character or nil
 *
 * Returns the next byte, if available:
 *
 * - If the [position][2]
 *   is not at the end of the [stored string][1]:
 *
 *     - Returns the next byte.
 *     - Increments the [byte position][2].
 *     - Adjusts the [character position][7].
 *
 *     ```
 *     scanner = StringScanner.new(HIRAGANA_TEXT)
 *     # => #<StringScanner 0/15 @ "\xE3\x81\x93\xE3\x82...">
 *     scanner.string                                   # => "こんにちは"
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\xE3", 1, 1]
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x81", 2, 2]
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x93", 3, 1]
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\xE3", 4, 2]
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x82", 5, 3]
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x93", 6, 2]
 *     ```

 * - Otherwise, returns `nil`, and does not change the positions.
 *
 *     ```
 *     scanner.terminate
 *     [scanner.get_byte, scanner.pos, scanner.charpos] # => [nil, 15, 5]
 *     ```
 *
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
 * call-seq:
 *   getbyte
 *
 * Equivalent to #get_byte.
 * This method is obsolete; use #get_byte instead.
 */

 /* :nodoc: */
static VALUE
strscan_getbyte(VALUE self)
{
    rb_warning("StringScanner#getbyte is obsolete; use #get_byte instead");
    return strscan_get_byte(self);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   peek(length) -> substring
 *
 * Returns the substring `string[pos, length]`;
 * does not update [match values][9] or [positions][11]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.pos = 3
 * scanner.peek(3)   # => "bar"
 * scanner.terminate
 * scanner.peek(3)   # => ""
 * ```
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
 * call-seq:
 *   peep
 *
 * Equivalent to #peek.
 * This method is obsolete; use #peek instead.
 */

 /* :nodoc: */
static VALUE
strscan_peep(VALUE self, VALUE vlen)
{
    rb_warning("StringScanner#peep is obsolete; use #peek instead");
    return strscan_peek(self, vlen);
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   unscan -> self
 *
 * Sets the [position][2] to its value previous to the recent successful
 * [match][17] attempt:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.scan(/foo/)
 * put_situation(scanner)
 * # Situation:
 * #   pos:       3
 * #   charpos:   3
 * #   rest:      "barbaz"
 * #   rest_size: 6
 * scanner.unscan
 * # => #<StringScanner 0/9 @ "fooba...">
 * put_situation(scanner)
 * # Situation:
 * #   pos:       0
 * #   charpos:   0
 * #   rest:      "foobarbaz"
 * #   rest_size: 9
 * ```
 *
 * Raises an exception if match values are clear:
 *
 * ```
 * scanner.scan(/nope/)           # => nil
 * match_values_cleared?(scanner) # => true
 * scanner.unscan                 # Raises StringScanner::Error.
 * ```
 *
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
 *
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   beginning_of_line? -> true or false
 *
 * Returns whether the [position][2] is at the beginning of a line;
 * that is, at the beginning of the [stored string][1]
 * or immediately after a newline:
 *
 *     scanner = StringScanner.new(MULTILINE_TEXT)
 *     scanner.string
 *     # => "Go placidly amid the noise and haste,\nand remember what peace there may be in silence.\n"
 *     scanner.pos                # => 0
 *     scanner.beginning_of_line? # => true
 *
 *     scanner.scan_until(/,/)    # => "Go placidly amid the noise and haste,"
 *     scanner.beginning_of_line? # => false
 *
 *     scanner.scan(/\n/)         # => "\n"
 *     scanner.beginning_of_line? # => true
 *
 *     scanner.terminate
 *     scanner.beginning_of_line? # => true
 *
 *     scanner.concat('x')
 *     scanner.terminate
 *     scanner.beginning_of_line? # => false
 *
 * StringScanner#bol? is an alias for StringScanner#beginning_of_line?.
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   eos? -> true or false
 *
 * Returns whether the [position][2]
 * is at the end of the [stored string][1]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.eos? # => false
 * pos = 3
 * scanner.eos? # => false
 * scanner.terminate
 * scanner.eos? # => true
 * ```
 *
 */
static VALUE
strscan_eos_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return EOS_P(p) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   empty?
 *
 * Equivalent to #eos?.
 * This method is obsolete, use #eos? instead.
 */

 /* :nodoc: */
static VALUE
strscan_empty_p(VALUE self)
{
    rb_warning("StringScanner#empty? is obsolete; use #eos? instead");
    return strscan_eos_p(self);
}

/*
 * call-seq:
 *   rest?
 *
 * Returns true if and only if there is more data in the string.  See #eos?.
 * This method is obsolete; use #eos? instead.
 *
 *   s = StringScanner.new('test string')
 *   # These two are opposites
 *   s.eos? # => false
 *   s.rest? # => true
 */

 /* :nodoc: */
static VALUE
strscan_rest_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return EOS_P(p) ? Qfalse : Qtrue;
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   matched? -> true or false
 *
 * Returns `true` of the most recent [match attempt][17] was successful,
 * `false` otherwise;
 * see [Basic Matched Values][18]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.matched?       # => false
 * scanner.pos = 3
 * scanner.exist?(/baz/)  # => 6
 * scanner.matched?       # => true
 * scanner.exist?(/nope/) # => nil
 * scanner.matched?       # => false
 * ```
 *
 */
static VALUE
strscan_matched_p(VALUE self)
{
    struct strscanner *p;

    GET_SCANNER(self, p);
    return MATCHED_P(p) ? Qtrue : Qfalse;
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   matched -> matched_substring or nil
 *
 * Returns the matched substring from the most recent [match][17] attempt
 * if it was successful,
 * or `nil` otherwise;
 * see [Basic Matched Values][18]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.matched        # => nil
 * scanner.pos = 3
 * scanner.match?(/bar/)  # => 3
 * scanner.matched        # => "bar"
 * scanner.match?(/nope/) # => nil
 * scanner.matched        # => nil
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   matched_size -> substring_size or nil
 *
 * Returns the size (in bytes) of the matched substring
 * from the most recent match [match attempt][17] if it was successful,
 * or `nil` otherwise;
 * see [Basic Matched Values][18]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.matched_size   # => nil
 *
 * pos = 3
 * scanner.exist?(/baz/)  # => 9
 * scanner.matched_size   # => 3
 *
 * scanner.exist?(/nope/) # => nil
 * scanner.matched_size   # => nil
 * ```
 *
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
 *
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   [](specifier) -> substring or nil
 *
 * Returns a captured substring or `nil`;
 * see [Captured Match Values][13].
 *
 * When there are captures:
 *
 * ```
 * scanner = StringScanner.new('Fri Dec 12 1975 14:39')
 * scanner.scan(/(?<wday>\w+) (?<month>\w+) (?<day>\d+) /)
 * ```
 *
 * - `specifier` zero: returns the entire matched substring:
 *
 *     ```
 *     scanner[0]         # => "Fri Dec 12 "
 *     scanner.pre_match  # => ""
 *     scanner.post_match # => "1975 14:39"
 *     ```
 *
 * - `specifier` positive integer. returns the `n`th capture, or `nil` if out of range:
 *
 *     ```
 *     scanner[1] # => "Fri"
 *     scanner[2] # => "Dec"
 *     scanner[3] # => "12"
 *     scanner[4] # => nil
 *     ```
 *
 * - `specifier` negative integer. counts backward from the last subgroup:
 *
 *     ```
 *     scanner[-1] # => "12"
 *     scanner[-4] # => "Fri Dec 12 "
 *     scanner[-5] # => nil
 *     ```
 *
 * - `specifier` symbol or string. returns the named subgroup, or `nil` if no such:
 *
 *     ```
 *     scanner[:wday]  # => "Fri"
 *     scanner['wday'] # => "Fri"
 *     scanner[:month] # => "Dec"
 *     scanner[:day]   # => "12"
 *     scanner[:nope]  # => nil
 *     ```
 *
 * When there are no captures, only `[0]` returns non-`nil`:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.exist?(/bar/)
 * scanner[0] # => "bar"
 * scanner[1] # => nil
 * ```
 *
 * For a failed match, even `[0]` returns `nil`:
 *
 * ```
 * scanner.scan(/nope/) # => nil
 * scanner[0]           # => nil
 * scanner[1]           # => nil
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   size -> captures_count
 *
 * Returns the count of captures if the most recent match attempt succeeded, `nil` otherwise;
 * see [Captures Match Values][13]:
 *
 * ```
 * scanner = StringScanner.new('Fri Dec 12 1975 14:39')
 * scanner.size                        # => nil
 *
 * pattern = /(?<wday>\w+) (?<month>\w+) (?<day>\d+) /
 * scanner.match?(pattern)
 * scanner.values_at(*0..scanner.size) # => ["Fri Dec 12 ", "Fri", "Dec", "12", nil]
 * scanner.size                        # => 4
 *
 * scanner.match?(/nope/)              # => nil
 * scanner.size                        # => nil
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   captures -> substring_array or nil
 *
 * Returns the array of [captured match values][13] at indexes `(1..)`
 * if the most recent match attempt succeeded, or `nil` otherwise:
 *
 * ```
 * scanner = StringScanner.new('Fri Dec 12 1975 14:39')
 * scanner.captures         # => nil
 *
 * scanner.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+) /)
 * scanner.captures         # => ["Fri", "Dec", "12"]
 * scanner.values_at(*0..4) # => ["Fri Dec 12 ", "Fri", "Dec", "12", nil]
 *
 * scanner.exist?(/Fri/)
 * scanner.captures         # => []
 *
 * scanner.scan(/nope/)
 * scanner.captures         # => nil
 * ```
 *
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
        VALUE str;
        if (p->regs.beg[i] == -1)
            str = Qnil;
        else
            str = extract_range(p,
                                adjust_register_position(p, p->regs.beg[i]),
                                adjust_register_position(p, p->regs.end[i]));
        rb_ary_push(new_ary, str);
    }

    return new_ary;
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   values_at(*specifiers) -> array_of_captures or nil
 *
 * Returns an array of captured substrings, or `nil` of none.
 *
 * For each `specifier`, the returned substring is `[specifier]`;
 * see #[].
 *
 * ```
 * scanner = StringScanner.new('Fri Dec 12 1975 14:39')
 * pattern = /(?<wday>\w+) (?<month>\w+) (?<day>\d+) /
 * scanner.match?(pattern)
 * scanner.values_at(*0..3)               # => ["Fri Dec 12 ", "Fri", "Dec", "12"]
 * scanner.values_at(*%i[wday month day]) # => ["Fri", "Dec", "12"]
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   pre_match -> substring
 *
 * Returns the substring that precedes the matched substring
 * from the most recent match attempt if it was successful,
 * or `nil` otherwise;
 * see [Basic Match Values][18]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.pre_match      # => nil
 *
 * scanner.pos = 3
 * scanner.exist?(/baz/)  # => 6
 * scanner.pre_match      # => "foobar" # Substring of entire string, not just target string.
 *
 * scanner.exist?(/nope/) # => nil
 * scanner.pre_match      # => nil
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   post_match -> substring
 *
 * Returns the substring that follows the matched substring
 * from the most recent match attempt if it was successful,
 * or `nil` otherwise;
 * see [Basic Match Values][18]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.post_match     # => nil
 *
 * scanner.pos = 3
 * scanner.match?(/bar/)  # => 3
 * scanner.post_match     # => "baz"
 *
 * scanner.match?(/nope/) # => nil
 * scanner.post_match     # => nil
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   rest -> target_substring
 *
 * Returns the 'rest' of the [stored string][1] (all after the current [position][2]),
 * which is the [target substring][3]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.rest # => "foobarbaz"
 * scanner.pos = 3
 * scanner.rest # => "barbaz"
 * scanner.terminate
 * scanner.rest # => ""
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   rest_size -> integer
 *
 * Returns the size (in bytes) of the #rest of the [stored string][1]:
 *
 * ```
 * scanner = StringScanner.new('foobarbaz')
 * scanner.rest      # => "foobarbaz"
 * scanner.rest_size # => 9
 * scanner.pos = 3
 * scanner.rest      # => "barbaz"
 * scanner.rest_size # => 6
 * scanner.terminate
 * scanner.rest      # => ""
 * scanner.rest_size # => 0
 * ```
 *
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
 * call-seq:
 *   restsize
 *
 * <tt>s.restsize</tt> is equivalent to <tt>s.rest_size</tt>.
 * This method is obsolete; use #rest_size instead.
 */

 /* :nodoc: */
static VALUE
strscan_restsize(VALUE self)
{
    rb_warning("StringScanner#restsize is obsolete; use #rest_size instead");
    return strscan_rest_size(self);
}

#define INSPECT_LENGTH 5

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   inspect -> string
 *
 * Returns a string representation of `self` that may show:
 *
 * 1. The current [position][2].
 * 2. The size (in bytes) of the [stored string][1].
 * 3. The substring preceding the current position.
 * 4. The substring following the current position (which is also the [target substring][3]).
 *
 * ```
 * scanner = StringScanner.new("Fri Dec 12 1975 14:39")
 * scanner.pos = 11
 * scanner.inspect # => "#<StringScanner 11/21 \"...c 12 \" @ \"1975 ...\">"
 * ```
 *
 * If at beginning-of-string, item 4 above (following substring) is omitted:
 *
 * ```
 * scanner.reset
 * scanner.inspect # => "#<StringScanner 0/21 @ \"Fri D...\">"
 * ```
 *
 * If at end-of-string, all items above are omitted:
 *
 * ```
 * scanner.terminate
 * scanner.inspect # => "#<StringScanner fin>"
 * ```
 *
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
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   fixed_anchor? -> true or false
 *
 * Returns whether the [fixed-anchor property][10] is set.
 */
static VALUE
strscan_fixed_anchor_p(VALUE self)
{
    struct strscanner *p;
    p = check_strscan(self);
    return p->fixed_anchor_p ? Qtrue : Qfalse;
}

typedef struct {
    VALUE self;
    VALUE captures;
} named_captures_data;

static int
named_captures_iter(const OnigUChar *name,
                    const OnigUChar *name_end,
                    int back_num,
                    int *back_refs,
                    OnigRegex regex,
                    void *arg)
{
    named_captures_data *data = arg;

    VALUE key = rb_str_new((const char *)name, name_end - name);
    VALUE value = RUBY_Qnil;
    int i;
    for (i = 0; i < back_num; i++) {
        value = strscan_aref(data->self, INT2NUM(back_refs[i]));
    }
    rb_hash_aset(data->captures, key, value);
    return 0;
}

/*
 * :markup: markdown
 * :include: ../../doc/strscan/link_refs.txt
 *
 * call-seq:
 *   named_captures -> hash
 *
 * Returns the array of captured match values at indexes (1..)
 * if the most recent match attempt succeeded, or nil otherwise;
 * see [Captured Match Values][13]:
 *
 * ```
 * scanner = StringScanner.new('Fri Dec 12 1975 14:39')
 * scanner.named_captures # => {}
 *
 * pattern = /(?<wday>\w+) (?<month>\w+) (?<day>\d+) /
 * scanner.match?(pattern)
 * scanner.named_captures # => {"wday"=>"Fri", "month"=>"Dec", "day"=>"12"}
 *
 * scanner.string = 'nope'
 * scanner.match?(pattern)
 * scanner.named_captures # => {"wday"=>nil, "month"=>nil, "day"=>nil}
 *
 * scanner.match?(/nosuch/)
 * scanner.named_captures # => {}
 * ```
 *
 */
static VALUE
strscan_named_captures(VALUE self)
{
    struct strscanner *p;
    GET_SCANNER(self, p);
    named_captures_data data;
    data.self = self;
    data.captures = rb_hash_new();
    if (!RB_NIL_P(p->regex)) {
        onig_foreach_name(RREGEXP_PTR(p->regex), named_captures_iter, &data);
    }

    return data.captures;
}

/* =======================================================================
                              Ruby Interface
   ======================================================================= */

/*
 * Document-class: StringScanner
 *
 * :markup: markdown
 *
 * :include: ../../doc/strscan/link_refs.txt
 * :include: ../../doc/strscan/strscan.md
 *
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
    rb_define_method(StringScanner, "scan_byte",   strscan_scan_byte,   0);
    rb_define_method(StringScanner, "peek",        strscan_peek,        1);
    rb_define_method(StringScanner, "peek_byte",   strscan_peek_byte,   0);
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

    rb_define_method(StringScanner, "named_captures", strscan_named_captures, 0);
}
