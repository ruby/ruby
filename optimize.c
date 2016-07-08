/* comments are in doxygen format, autobrief assumed. */

/**
 * ISeq optimization infrastructure, implementation.
 *
 * @file      optimize.c
 * @author    Urabe, Shyouhei.
 * @date      Apr. 14th, 2016
 * @copyright Ruby's
 */

#include "ruby/config.h"

#ifndef HAVE_TYPEOF
#error "This  code is intentionally  written  in GCC's  language, to  minimize"
#error "the patch size. Once it's accepted, I can translate this into ANSI C."
#endif

#include <stddef.h>             // size_t
#include <stdint.h>             // uintptr_t
#include "vm_core.h"            // rb_iseq_t
#include "optimize.h"
#include "deoptimize.h"

#include "insns.inc"            // enum ruby_vminsn_type
#include "insns_info.inc"       // insn_len

/**
 * Per-instruction purity  is either definitely  pure, definitely not  pure, or
 * uncertain.
 */
enum insn_purity {
    insn_is_pure          = Qtrue,
    insn_is_not_pure      = Qfalse,
    insn_is_unpredictable = Qnil,
};

/**
 * Flexible array struct that lists up  pointers to each instructions inside of
 * an instruction sequence.  Handy when you go back and forth while iterating.
 */
struct iseq_map {
    uintptr_t nelems;
    const VALUE *ptr[];
};

/**
 * Purity of a specific instruction.
 *
 * @param [in] insn instruction.
 * @param [in] map  insn map, in case a insn's purity depends others.
 * @return purity of the insn.
 */
static inline enum insn_purity purity_of_insn(enum ruby_vminsn_type insn, const struct iseq_map *map);

/**
 * Merge purity; a pure + pure is pure, pure + nonpure is nonpure, and so on.
 *
 * @param [in] p1 purity left hand side
 * @param [in] p2 purity right hand side
 * @return p1 + p2
 */
static inline enum insn_purity purity_merge(enum insn_purity p1, enum insn_purity p2)
    __attribute__((const));

/**
 * Purity of the call cache's pointed entry.
 *
 * @param [in] cc call cache in question.
 * @return purity of cc's method entry.
 */
static inline enum insn_purity purity_of_cc(const struct rb_call_cache *cc)
    __attribute__((nonnull))
    __attribute__((pure));

/**
 * Purity of tostring instruction. It tries to  look at the last insn: if it is
 * either putstring or concatstrings, the stack top is a string, and is safe to
 * say this  tostring is pure (no  funcall involved).  Otherwise it  _can_ call
 * to_s method so the purity is not detectable.
 *
 * @param [in] map  insn map
 * @return purity of the tostring.
 */
static inline enum insn_purity purity_of_tostring(enum ruby_vminsn_type prev)
    __attribute__((const));

/**
 * Purity of defined instruction.  It is pure  for 99% cases but there are some
 * glitchy corner cases where method call is involved.
 *
 * @param [in] type defined's type
 * @return purity of the defined
 */
static inline enum insn_purity purity_of_defined(enum defined_type type)
    __attribute__((const));

/**
 * Purity  of send-ish  instructions.  Note  that there  are instructions  that
 * calls multiple  methods inside,  so things  are not as  simple as  bare send
 * instruction.
 *
 * @param [in] argv instruction sequence
 * @return purity of the instruction
 */
static inline enum insn_purity purity_of_sendish(const VALUE *seq)
    __attribute__((nonnull))
    __attribute__((pure));

/**
 * As you see, purity can be mapped to VALUE.  This is to do that.
 *
 * @param [in] v either Qtrue, Qfalse, or Qnil
 * @return corresponding VALUE
 */
static inline enum insn_purity purity_of_VALUE(VALUE v)
    __attribute__((const));

/**
 * @see purity_of_VALUE
 *
 * @param [in] p purity
 * @return corresponding VALUE
 */
static inline VALUE VALUE_of_purity(enum insn_purity p)
    __attribute__((const));

/**
 * Checks if the cached entry points to rb_obj_not_equal.
 *
 * @param [in] cc call cache in question
 * @return true if it is  rb_obj_not_equal, false otherwise.
 */
static inline bool cc_is_neq(const struct rb_call_cache *cc)
    __attribute__((nonnull))
    __attribute__((pure));

/**
 * Find an ISeq from inside of a method entry
 *
 * @param [in] cc call cache in question
 * @return correspoinding ISeq if any, NULL otherwise.
 */
static inline const rb_iseq_t *iseq_of_me(const struct rb_callable_method_entry_struct *me)
    __attribute__((nonnull))
    __attribute__((pure));

/**
 * Initializes memory pattern.  Never called explicitly.
 */
static void construct_pattern(void)
    __attribute__((constructor))
    __attribute__((used))
    __attribute__((noinline));

/**
 * See if two iseqs are in parental relationship.
 *
 * @param [in] parent (possible) ascendant.
 * @param [in] child  (possible) encumbrance.
 * @return degree  of relationships  between two,  0 if they  are same,  -1 for
 *     strangers.
 */
static inline int relative_p(const rb_iseq_t *parent, const rb_iseq_t *child)
    __attribute__((nonnull));

/**
 * getlocal's distance of  EP.  It depends to the instructoin  because they can
 * (tends to) be operands-unified.
 *
 * @param [in] ptr getlocal-ish insn sequence.
 * @return level, a la vanilla getlocal's.
 */
static inline int getlocal_level(const VALUE *ptr)
    __attribute__((pure))
    __attribute__((nonnull));

/**
 * ditto for setlocal.
 *
 * @param [in] ptr setlocal-ish insn sequence.
 * @return level, a la vanilla setlocal's.
 */
static inline int setlocal_level(const VALUE *ptr)
    __attribute__((pure))
    __attribute__((nonnull));

/**
 * iseq_analyze() can recur.  This is the recursion part.
 *
 * @param [in]  iseq   target iseq.
 * @param [in]  parent parent iseq.
 * @param [out] info   recursion pass-over.
 * @return iseq's purity.
 */
static enum insn_purity iseq_analyze_i(const rb_iseq_t *iseq, const rb_iseq_t *parent, VALUE info)
    __attribute__((nonnull));

/**
 * squash iseq.
 *
 * @param [out]  iseq  target iseq.
 * @param [out]  pc    start pointer to the buffer to squash.
 * @param [in]   n     length to squash.
 */
static inline void iseq_squash(const rb_iseq_t *iseq, VALUE * pc, int n);

int
relative_p(
    const rb_iseq_t *parent,
    const rb_iseq_t *child)
{
    const rb_iseq_t *i = child;

    for (int j = 0; /* */; j++) {
        if (! i) {
            return -1;
        }
        else if (i == parent) {
            return j;
        }
        else {
            i = i->body->parent_iseq;
        }
    }
}

int
getlocal_level(const VALUE *ptr)
{
    enum ruby_vminsn_type insn = (typeof(insn))ptr[0];

    switch (insn) {
      case BIN(setlocal):
      case BIN(setlocal_OP__WC__0):
      case BIN(setlocal_OP__WC__1):
      case BIN(checkkeyword):
        return -1;  /* OK known safe insns */

      case BIN(getlocal):
        return ptr[2];

      case BIN(getlocal_OP__WC__0):
        return 0;

      case BIN(getlocal_OP__WC__1):
        return 1;

      default:
        rb_bug("unknown instruction %s: blame @shyouhei.", insn_name(insn));
    }
}

int
setlocal_level(const VALUE *ptr)
{
    enum ruby_vminsn_type insn = (typeof(insn))ptr[0];

    switch (insn) {
      case BIN(setlocal):
        return ptr[2];

      case BIN(setlocal_OP__WC__0):
        return 0;

      case BIN(setlocal_OP__WC__1):
        return 1;

      default:
        return -1;
    }
}

bool
cc_is_neq(const struct rb_call_cache *cc)
{
    extern VALUE rb_obj_not_equal(VALUE obj1, VALUE obj2);
    const rb_callable_method_entry_t *me;

    if (! (me = cc->me)) {
        return false;
    }
    else if (me->def->type != VM_METHOD_TYPE_CFUNC) {
        return false;
    }
    else {
        return me->def->body.cfunc.func == rb_obj_not_equal;
    }
}

enum insn_purity
purity_of_VALUE(VALUE v)
{
    /* This is an  extremely politely written version  of const_cast.  Expected
     * to be compiled to no-op when properly optimized, because it just returns
     * what was passed. */
    return (enum insn_purity)v;
}

VALUE
VALUE_of_purity(enum insn_purity p)
{
    /* ... and vice versa. */ 
    return (VALUE)p;
}

const rb_iseq_t *
iseq_of_me(const struct rb_callable_method_entry_struct *me)
{
    const rb_method_definition_t *d = me->def;
    switch (d->type) {
      case VM_METHOD_TYPE_ISEQ:
	return d->body.iseq.iseqptr;
      case VM_METHOD_TYPE_BMETHOD:
	return rb_proc_get_iseq(d->body.proc, 0);
      default:
	return NULL;
    }
}

enum insn_purity
purity_of_cc(const struct rb_call_cache *cc)
{
    const rb_iseq_t *i;

    if (! cc->me) {
        return insn_is_unpredictable; /* method missing */
    }
    else if (! (i = iseq_of_me(cc->me))) {
        return insn_is_not_pure;
    }
    else if (! i->body->attributes) {
        /* Note,  we do  not recursively  analyze.  That  can lead  to infinite
         * recursion  on mutually  recursive calls  and detecting  that is  too
         * expensive in this hot path.*/
        return insn_is_unpredictable;
    }
    else {
        return purity_of_VALUE(RB_ISEQ_ANNOTATED_P(i, core::purity));
    }
}

enum insn_purity
purity_of_tostring(enum ruby_vminsn_type prev)
{
    switch (prev) {
      case BIN(putstring):
      case BIN(concatstrings):
        return insn_is_pure;
      default:
        return insn_is_unpredictable;
    }
}

enum insn_purity
purity_of_defined(enum defined_type type)
{
    switch (type) {
      case DEFINED_IVAR:
      case DEFINED_IVAR2:
      case DEFINED_GVAR:
      case DEFINED_CVAR:
      case DEFINED_YIELD:
      case DEFINED_REF:
        return insn_is_pure;
      case DEFINED_CONST:
        return insn_is_unpredictable; /* can kick autoload */
      case DEFINED_FUNC:
      case DEFINED_METHOD:
        return insn_is_unpredictable; /* can kick respond_to_missing? */
      case DEFINED_ZSUPER:
        return insn_is_unpredictable; /* what if super is method missing? */
      default:
        rb_bug("unknown operand %d: blame @shyouhei.", type);
    }
}

enum insn_purity
purity_merge(
    enum insn_purity p1,
    enum insn_purity p2)
{
    switch (p1) {
      case insn_is_not_pure:
        return p1;

      case insn_is_pure:
        return p2;

      case insn_is_unpredictable:
        return p2 == insn_is_pure ? p1 : p2;

      default:
        UNREACHABLE;
    }
}

enum insn_purity
purity_of_sendish(const VALUE *argv)
{
    enum ruby_vminsn_type insn = argv[0];
    const char *ops            = insn_op_types(insn);
    enum insn_purity purity    = insn_is_pure;

    for (int j = 0; j < insn_len(insn); j++) {
        if (ops[j] == TS_CALLCACHE) {
            struct rb_call_cache *cc = (void *)argv[j + 1];

            purity = purity_merge(purity, purity_of_cc(cc));
        }
    }
    return purity;
}

enum insn_purity
purity_of_insn(
    enum ruby_vminsn_type insn,
    const struct iseq_map *map)
{
    uintptr_t i = map->nelems - 1;

    switch(insn) {
#define case_BIN_opt(op, bop, flag)                             \
      case BIN(opt_##op):                                       \
        /* safe to say pure if basic op is unredefined */       \
        if (BASIC_OP_UNREDEFINED_P(BOP_##bop, flag)) {          \
            return insn_is_pure;                                \
        }                                                       \
        else {                                                  \
            goto sendish;                                       \
        }
#define case_BIN(op, purity)                                    \
      case BIN(op): return insn_is_##purity
      case_BIN(nop, pure);
      case_BIN(getlocal, pure);
      case_BIN(setlocal, pure);
      case_BIN(getspecial, pure);
      case_BIN(setspecial, not_pure);
      case_BIN(getinstancevariable, pure);
      case_BIN(setinstancevariable, not_pure);
      case_BIN(getclassvariable, pure);
      case_BIN(setclassvariable, not_pure);
      case_BIN(getconstant, pure);
      case_BIN(setconstant, not_pure);
      case_BIN(getglobal, unpredictable); /* can be hooked */
      case_BIN(setglobal, not_pure);
      case_BIN(putnil, pure);
      case_BIN(putself, pure);
      case_BIN(putobject, pure);
      case_BIN(putspecialobject, pure);
      case_BIN(putiseq, pure);
      case_BIN(putstring, pure);
      case_BIN(concatstrings, pure);
      case BIN(tostring):
        return purity_of_tostring((enum ruby_vminsn_type)*map->ptr[i - 1]);

      case_BIN(freezestring, pure);
      case_BIN(toregexp, pure);
      case_BIN(newarray, pure);
      case_BIN(duparray, pure);
      case_BIN(expandarray, unpredictable);
      case_BIN(concatarray, unpredictable); /* TODO: maybe detectable? */
      case_BIN(splatarray, unpredictable);  /* TODO: maybe detectable? */
      case_BIN(newhash, pure);
      case_BIN(newrange, pure);
      case_BIN(pop, pure);
      case_BIN(dup, pure);
      case_BIN(dupn, pure);
      case_BIN(swap, pure);
      case_BIN(reverse, pure);
      case_BIN(reput, pure);
      case_BIN(topn, pure);
      case_BIN(setn, pure);
      case_BIN(adjuststack, pure);
      case BIN(defined):
        return purity_of_defined((enum defined_type)map->ptr[i][1]);

      case_BIN(checkmatch, unpredictable); /* TODO: maybe detectable? */
      case_BIN(checkkeyword, pure);
      case_BIN(trace, pure);
      case_BIN(defineclass, not_pure);
      case BIN(send): goto sendish;
      case_BIN_opt(str_freeze, FREEZE, STRING_REDEFINED_OP_FLAG);
      case_BIN_opt(newarray_max, MAX, ARRAY_REDEFINED_OP_FLAG);
      case_BIN_opt(newarray_min, MIN, ARRAY_REDEFINED_OP_FLAG);
      case BIN(opt_send_without_block): goto sendish;
      case BIN(invokesuper): goto sendish;
      case_BIN(invokeblock, unpredictable);
      case_BIN(leave, pure);
      case_BIN(throw, pure);
      case_BIN(jump, pure);
      case_BIN(branchif, pure);
      case_BIN(branchunless, pure);
      case_BIN(branchnil, pure);
      case_BIN(getinlinecache, pure);
      case_BIN(setinlinecache, pure);
      case_BIN(once, not_pure); /* global side-effect */
      case_BIN(opt_case_dispatch, pure);
      case_BIN_opt(plus, PLUS, ~0); /* ~0 means anything */
      case_BIN_opt(minus, MINUS, ~0);
      case_BIN_opt(mult, MULT, ~0);
      case_BIN_opt(div, DIV, ~0);
      case_BIN_opt(mod, MOD, ~0);
      case_BIN_opt(eq, EQ, ~0);
      case BIN(opt_neq):
        /* beware: neq has 2 call caches; one for not and another for eq. */
        if (BASIC_OP_UNREDEFINED_P(BOP_EQ, ~0)) {
            goto notish;
        }
        else {
            goto sendish;
        }

      case_BIN_opt(lt, LT, ~0);
      case_BIN_opt(le, LE, ~0);
      case_BIN_opt(gt, GT, ~0);
      case_BIN_opt(ge, GE, ~0);
      case_BIN(opt_ltlt, unpredictable);
      case_BIN_opt(aref, AREF, ~0);
      case_BIN(opt_aset, unpredictable);
      case_BIN(opt_aset_with, unpredictable);
      case_BIN_opt(aref_with, AREF, HASH_REDEFINED_OP_FLAG);
      case_BIN_opt(length, LENGTH, ~0);
      case_BIN_opt(size, SIZE, ~0);
      case_BIN_opt(empty_p, EMPTY_P, ~0);
      case_BIN(opt_succ, unpredictable);
      case BIN(opt_not): goto notish;
      case_BIN_opt(regexpmatch1, MATCH,  REGEXP_REDEFINED_OP_FLAG);
      case_BIN_opt(regexpmatch2, MATCH,  STRING_REDEFINED_OP_FLAG);
      case_BIN(opt_call_c_function, not_pure); /* not detectable */
      case_BIN(bitblt, pure);
      case_BIN(answer, pure);
      case_BIN(getlocal_OP__WC__0, pure);
      case_BIN(getlocal_OP__WC__1, pure);
      case_BIN(setlocal_OP__WC__0, pure);
      case_BIN(setlocal_OP__WC__1, pure);
      case_BIN(putobject_OP_INT2FIX_O_0_C_, pure);
      case_BIN(putobject_OP_INT2FIX_O_1_C_, pure);

      notish:
        if (cc_is_neq((struct rb_call_cache *)map->ptr[i][2])) {
            return insn_is_pure;
        }
        /* FALLTHROUGH */

      sendish:
        return purity_of_sendish(map->ptr[i]);

      default:
        rb_bug("unknown instruction %s: blame @shyouhei.", insn_name(insn));

#undef case_BIN
#undef case_BIN_opt
    }
}

enum insn_purity
iseq_analyze_i(
    const rb_iseq_t *iseq,
    const rb_iseq_t *parent,
    VALUE info)
{
    enum insn_purity purity = insn_is_pure;
    const VALUE *ptr        = rb_iseq_original_iseq(iseq);
    int n                   = iseq->body->iseq_size;
    VALUE buf[n + 1];
    struct iseq_map *map    = (void *)buf;
    map->nelems             = 0;

    for (int len = 0, i = 0; i < n; i += len) {
        enum insn_purity p;
        enum ruby_vminsn_type insn = (typeof(insn))ptr[i];
        const char *ops            = insn_op_types(insn);
        const VALUE *now           = map->ptr[map->nelems++] = &ptr[i];
        p                          = purity_of_insn(insn, map);
        len                        = insn_len(insn);
        purity                     = purity_merge(purity, p);

        for (int j = 0; j < len - 1; j++) {
            VALUE op = now[j + 1];
            int degree;
            const rb_iseq_t *child;
            int lv;

            switch (ops[j]) {
              case TS_LINDEX:
                if ((lv = getlocal_level(now)) <  0) {
                    break;
                }
                else if (lv != relative_p(parent, iseq)) {
                    break;
                }
                else {
                    rb_ary_store(info, now[1], Qtrue);
                }
                break;

              case TS_VALUE:
                if (LIKELY(CLASS_OF(op) != rb_cISeq)) {
                    break;
                }
                /* FALLTHROUGH */

              case TS_ISEQ:
                child = (typeof(child))op;
                if ((degree = relative_p(parent, child)) >= 0) {
                    iseq_analyze_i(child, parent, info);
                }
            }
        }
    }

    return purity;
}

void
iseq_analyze(rb_iseq_t *iseq)
{
    if ((! iseq->body->attributes) ||
        FL_TEST(iseq, ISEQ_NEEDS_ANALYZE)) {
        int n       = iseq->body->local_size;
        VALUE rw    = rb_ary_tmp_new(n + 1);
        VALUE wo    = rb_ary_new_capa(n + 1);
        VALUE purep = VALUE_of_purity(iseq_analyze_i(iseq, iseq, rw));

        if (purep == Qfalse) {
            iseq->body->temperature = -1;
        }
        for (int i = 0; i < n + 1; i++) {
            if (rb_ary_entry(rw, i) != Qtrue) {
                rb_ary_store(wo, i, Qtrue);
            }
        }
        RB_ISEQ_ANNOTATE(iseq, core::writeonly_local_variables, wo);
        RB_ISEQ_ANNOTATE(iseq, core::purity, purep);
        FL_UNSET(iseq, ISEQ_NEEDS_ANALYZE);
    }
}

static const VALUE wipeout_pattern[8]; /* maybe 5+2==7 should suffice? */
static VALUE adjuststack;
static VALUE nop;
static VALUE putobject;

void
construct_pattern(void)
{
#define LABEL_PTR(insn) addrs[BIN(insn)]
    const void **addrs = rb_vm_get_insns_address_table();
    const typeof(wipeout_pattern) p = {
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
        (VALUE)LABEL_PTR(nop),
    };

    memcpy((void *)wipeout_pattern, p, sizeof(p));
    adjuststack = (VALUE)LABEL_PTR(adjuststack);
    nop         = (VALUE)LABEL_PTR(nop);
    putobject   = (VALUE)LABEL_PTR(putobject);
#undef LABEL_PTR
}

void
iseq_squash(const rb_iseq_t *iseq, VALUE * pc, int n)
{
    const size_t s = sizeof(wipeout_pattern);
    const int    m = s / sizeof(VALUE); /* == 8 */

    while (UNLIKELY(n > m)) {
        memcpy(pc, wipeout_pattern, s);
        pc += m;
        n  -= m;
    }
    memcpy(pc, wipeout_pattern, n * sizeof(VALUE));
    ISEQ_RESET_ORIGINAL_ISEQ(iseq);
    FL_SET(iseq, ISEQ_NEEDS_ANALYZE);
}

void
iseq_eager_optimize(rb_iseq_t *iseq)
{
    const VALUE *ptr = rb_iseq_original_iseq(iseq);
    VALUE *buf       = (VALUE *)iseq->body->iseq_encoded;
    int n            = iseq->body->iseq_size;
    bool f           = false;

    for (int len = 0, i = 0; i < n; i += len) {
        int level                  = setlocal_level(&ptr[i]);
        enum ruby_vminsn_type insn = (typeof(insn))ptr[i];
        len                        = insn_len(insn);

        if (level >= 0) {
            unsigned long lindex = (unsigned long)ptr[i + 1];
            const rb_iseq_t *p   = iseq;

            for (int j = 0; j < level; j++) {
                p = p->body->parent_iseq;
            }
            if (RTEST(iseq_local_variable_is_writeonly(p, lindex))) {
                f          = true;
                buf[i]     = adjuststack;
                buf[i + 1] = 1;
                for (int k = 2; k < len; k++) {
                    /* this loops at most once, as of writing. */
                    buf[i + k] = nop;
                }
            }
        }
    }

    FL_SET(iseq, ISEQ_EAGER_OPTIMIZED);
    if (f) {
        ISEQ_RESET_ORIGINAL_ISEQ(iseq);
        FL_SET(iseq, ISEQ_NEEDS_ANALYZE);
    }
}

void
iseq_move_nop(const rb_iseq_t *restrict i, int j)
{
    VALUE m    = i->body->iseq_encoded[j + 2];
    VALUE *buf = (VALUE *)&i->body->iseq_encoded[j];

    iseq_squash(i, buf, 3);
    buf[0] = adjuststack;
    buf[1] = m;
}

void
iseq_eliminate_insn(
    const rb_iseq_t *restrict i,
    struct cfp_last_insn *restrict p,
    int n,
    rb_num_t m)
{
    VALUE *buf = (VALUE *)&i->body->iseq_encoded[p->pc];
    int len    = p->len + n;
    int argc   = p->argc + m;

    memset(p, 0, sizeof(*p));
    iseq_squash(i, buf, len);
    if (argc != 0) {
        buf[0] = adjuststack;
        buf[1] = argc;
    }
}

void
iseq_const_fold(
    const rb_iseq_t *restrict i,
    const VALUE *pc,
    int n,
    long m,
    VALUE konst)
{
    VALUE *buf = (VALUE *)&pc[-n];
    int len    = n + m;

    iseq_squash(i, buf, len);
    buf[0] = putobject;
    buf[1] = konst;
}

/* 
 * Local Variables:
 * mode: C
 * coding: utf-8-unix
 * indent-tabs-mode: nil
 * tab-width: 8
 * fill-column: 79
 * default-justification: full
 * c-file-style: "Ruby"
 * c-doc-comment-style: javadoc
 * End:
 */
