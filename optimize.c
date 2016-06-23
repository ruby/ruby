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
static inline const struct rb_iseq_struct *iseq_of_me(const struct rb_callable_method_entry_struct *me)
    __attribute__((nonnull))
    __attribute__((pure));

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

const struct rb_iseq_struct *
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
    const struct rb_iseq_struct *i;

    if (! cc->me) {
        return insn_is_unpredictable; /* method missing */
    }
    else if (! (i = iseq_of_me(cc->me))) {
        return insn_is_not_pure;
    }
    else if (! i->body->attributes) {
        return insn_is_unpredictable; /* not yet analyzed */
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
iseq_purity(const rb_iseq_t *iseq)
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
        map->ptr[map->nelems++]    = &ptr[i];
        p                          = purity_of_insn(insn, map);
        len                        = insn_len(insn);
        purity                     = purity_merge(purity, p);
    }

    return purity;
}

void
iseq_analyze(rb_iseq_t *iseq)
{
    if ((! iseq->body->attributes) ||
        FL_TEST(iseq, ISEQ_NEEDS_ANALYZE)) {
        VALUE purep = VALUE_of_purity(iseq_purity(iseq));

        RB_ISEQ_ANNOTATE(iseq, core::purity, purep);
        FL_UNSET(iseq, ISEQ_NEEDS_ANALYZE);
    }
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
