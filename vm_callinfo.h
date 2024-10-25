#ifndef RUBY_VM_CALLINFO_H                               /*-*-C-*-vi:se ft=c:*/
#define RUBY_VM_CALLINFO_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#include "debug_counter.h"
#include "internal/class.h"
#include "shape.h"

enum vm_call_flag_bits {
    VM_CALL_ARGS_SPLAT_bit,     // m(*args)
    VM_CALL_ARGS_BLOCKARG_bit,  // m(&block)
    VM_CALL_FCALL_bit,          // m(args)   # receiver is self
    VM_CALL_VCALL_bit,          // m         # method call that looks like a local variable
    VM_CALL_ARGS_SIMPLE_bit,    // !(ci->flag & (SPLAT|BLOCKARG|KWARG|KW_SPLAT|FORWARDING)) && !has_block_iseq
    VM_CALL_KWARG_bit,          // has kwarg
    VM_CALL_KW_SPLAT_bit,       // m(**opts)
    VM_CALL_TAILCALL_bit,       // located at tail position
    VM_CALL_SUPER_bit,          // super
    VM_CALL_ZSUPER_bit,         // zsuper
    VM_CALL_OPT_SEND_bit,       // internal flag
    VM_CALL_KW_SPLAT_MUT_bit,   // kw splat hash can be modified (to avoid allocating a new one)
    VM_CALL_ARGS_SPLAT_MUT_bit, // args splat can be modified (to avoid allocating a new one)
    VM_CALL_FORWARDING_bit,     // m(...)
    VM_CALL__END
};

#define VM_CALL_ARGS_SPLAT      (0x01 << VM_CALL_ARGS_SPLAT_bit)
#define VM_CALL_ARGS_BLOCKARG   (0x01 << VM_CALL_ARGS_BLOCKARG_bit)
#define VM_CALL_FCALL           (0x01 << VM_CALL_FCALL_bit)
#define VM_CALL_VCALL           (0x01 << VM_CALL_VCALL_bit)
#define VM_CALL_ARGS_SIMPLE     (0x01 << VM_CALL_ARGS_SIMPLE_bit)
#define VM_CALL_KWARG           (0x01 << VM_CALL_KWARG_bit)
#define VM_CALL_KW_SPLAT        (0x01 << VM_CALL_KW_SPLAT_bit)
#define VM_CALL_TAILCALL        (0x01 << VM_CALL_TAILCALL_bit)
#define VM_CALL_SUPER           (0x01 << VM_CALL_SUPER_bit)
#define VM_CALL_ZSUPER          (0x01 << VM_CALL_ZSUPER_bit)
#define VM_CALL_OPT_SEND        (0x01 << VM_CALL_OPT_SEND_bit)
#define VM_CALL_KW_SPLAT_MUT    (0x01 << VM_CALL_KW_SPLAT_MUT_bit)
#define VM_CALL_ARGS_SPLAT_MUT  (0x01 << VM_CALL_ARGS_SPLAT_MUT_bit)
#define VM_CALL_FORWARDING      (0x01 << VM_CALL_FORWARDING_bit)

struct rb_callinfo_kwarg {
    int keyword_len;
    int references;
    VALUE keywords[];
};

static inline size_t
rb_callinfo_kwarg_bytes(int keyword_len)
{
    return rb_size_mul_add_or_raise(
        keyword_len,
        sizeof(VALUE),
        sizeof(struct rb_callinfo_kwarg),
        rb_eRuntimeError);
}

// imemo_callinfo
struct rb_callinfo {
    VALUE flags;
    const struct rb_callinfo_kwarg *kwarg;
    VALUE mid;
    VALUE flag;
    VALUE argc;
};

#if !defined(USE_EMBED_CI) || (USE_EMBED_CI+0)
#undef USE_EMBED_CI
#define USE_EMBED_CI 1
#else
#undef USE_EMBED_CI
#define USE_EMBED_CI 0
#endif

#if SIZEOF_VALUE == 8
#define CI_EMBED_TAG_bits   1
#define CI_EMBED_ARGC_bits 15
#define CI_EMBED_FLAG_bits 16
#define CI_EMBED_ID_bits   32
#elif SIZEOF_VALUE == 4
#define CI_EMBED_TAG_bits   1
#define CI_EMBED_ARGC_bits  3
#define CI_EMBED_FLAG_bits 13
#define CI_EMBED_ID_bits   15
#endif

#if (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits + CI_EMBED_FLAG_bits + CI_EMBED_ID_bits) != (SIZEOF_VALUE * 8)
#error
#endif

#define CI_EMBED_FLAG 0x01
#define CI_EMBED_ARGC_SHFT (CI_EMBED_TAG_bits)
#define CI_EMBED_ARGC_MASK ((((VALUE)1)<<CI_EMBED_ARGC_bits) - 1)
#define CI_EMBED_FLAG_SHFT (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits)
#define CI_EMBED_FLAG_MASK ((((VALUE)1)<<CI_EMBED_FLAG_bits) - 1)
#define CI_EMBED_ID_SHFT   (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits + CI_EMBED_FLAG_bits)
#define CI_EMBED_ID_MASK   ((((VALUE)1)<<CI_EMBED_ID_bits) - 1)

static inline bool
vm_ci_packed_p(const struct rb_callinfo *ci)
{
    if (!USE_EMBED_CI) {
        return 0;
    }
    if (LIKELY(((VALUE)ci) & 0x01)) {
        return 1;
    }
    else {
        VM_ASSERT(IMEMO_TYPE_P(ci, imemo_callinfo));
        return 0;
    }
}

static inline bool
vm_ci_p(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci) || IMEMO_TYPE_P(ci, imemo_callinfo)) {
        return 1;
    }
    else {
        return 0;
    }
}

static inline ID
vm_ci_mid(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return (((VALUE)ci) >> CI_EMBED_ID_SHFT) & CI_EMBED_ID_MASK;
    }
    else {
        return (ID)ci->mid;
    }
}

static inline unsigned int
vm_ci_flag(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return (unsigned int)((((VALUE)ci) >> CI_EMBED_FLAG_SHFT) & CI_EMBED_FLAG_MASK);
    }
    else {
        return (unsigned int)ci->flag;
    }
}

static inline unsigned int
vm_ci_argc(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return (unsigned int)((((VALUE)ci) >> CI_EMBED_ARGC_SHFT) & CI_EMBED_ARGC_MASK);
    }
    else {
        return (unsigned int)ci->argc;
    }
}

static inline const struct rb_callinfo_kwarg *
vm_ci_kwarg(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return NULL;
    }
    else {
        return ci->kwarg;
    }
}

static inline void
vm_ci_dump(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        ruby_debug_printf("packed_ci ID:%s flag:%x argc:%u\n",
                          rb_id2name(vm_ci_mid(ci)), vm_ci_flag(ci), vm_ci_argc(ci));
    }
    else {
        rp(ci);
    }
}

#define vm_ci_new(mid, flag, argc, kwarg) vm_ci_new_(mid, flag, argc, kwarg, __FILE__, __LINE__)
#define vm_ci_new_runtime(mid, flag, argc, kwarg) vm_ci_new_runtime_(mid, flag, argc, kwarg, __FILE__, __LINE__)

/* This is passed to STATIC_ASSERT.  Cannot be an inline function. */
#define VM_CI_EMBEDDABLE_P(mid, flag, argc, kwarg) \
    (((mid ) & ~CI_EMBED_ID_MASK)   ? false :      \
     ((flag) & ~CI_EMBED_FLAG_MASK) ? false :      \
     ((argc) & ~CI_EMBED_ARGC_MASK) ? false :      \
      (kwarg)                       ? false : true)

#define vm_ci_new_id(mid, flag, argc, must_zero) \
    ((const struct rb_callinfo *)                \
     ((((VALUE)(mid )) << CI_EMBED_ID_SHFT)   |  \
      (((VALUE)(flag)) << CI_EMBED_FLAG_SHFT) |  \
      (((VALUE)(argc)) << CI_EMBED_ARGC_SHFT) |  \
      RUBY_FIXNUM_FLAG))

// vm_method.c
const struct rb_callinfo *rb_vm_ci_lookup(ID mid, unsigned int flag, unsigned int argc, const struct rb_callinfo_kwarg *kwarg);
void rb_vm_ci_free(const struct rb_callinfo *);

static inline const struct rb_callinfo *
vm_ci_new_(ID mid, unsigned int flag, unsigned int argc, const struct rb_callinfo_kwarg *kwarg, const char *file, int line)
{
    if (USE_EMBED_CI && VM_CI_EMBEDDABLE_P(mid, flag, argc, kwarg)) {
        RB_DEBUG_COUNTER_INC(ci_packed);
        return vm_ci_new_id(mid, flag, argc, kwarg);
    }

    const bool debug = 0;
    if (debug) ruby_debug_printf("%s:%d ", file, line);

    const struct rb_callinfo *ci = rb_vm_ci_lookup(mid, flag, argc, kwarg);

    if (debug) rp(ci);
    if (kwarg) {
        RB_DEBUG_COUNTER_INC(ci_kw);
    }
    else {
        RB_DEBUG_COUNTER_INC(ci_nokw);
    }

    VM_ASSERT(vm_ci_flag(ci) == flag);
    VM_ASSERT(vm_ci_argc(ci) == argc);

    return ci;
}


static inline const struct rb_callinfo *
vm_ci_new_runtime_(ID mid, unsigned int flag, unsigned int argc, const struct rb_callinfo_kwarg *kwarg, const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(ci_runtime);
    return vm_ci_new_(mid, flag, argc, kwarg, file, line);
}

#define VM_CALLINFO_NOT_UNDER_GC IMEMO_FL_USER0

static inline bool
vm_ci_markable(const struct rb_callinfo *ci)
{
    if (! ci) {
        return false; /* or true? This is Qfalse... */
    }
    else if (vm_ci_packed_p(ci)) {
        return true;
    }
    else {
        VM_ASSERT(IMEMO_TYPE_P(ci, imemo_callinfo));
        return ! FL_ANY_RAW((VALUE)ci, VM_CALLINFO_NOT_UNDER_GC);
    }
}

#define VM_CI_ON_STACK(mid_, flags_, argc_, kwarg_) \
    (struct rb_callinfo) {                          \
        .flags = T_IMEMO |                          \
            (imemo_callinfo << FL_USHIFT) |         \
            VM_CALLINFO_NOT_UNDER_GC,               \
        .mid   = mid_,                              \
        .flag  = flags_,                            \
        .argc  = argc_,                             \
        .kwarg = kwarg_,                            \
    }

typedef VALUE (*vm_call_handler)(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *cfp,
    struct rb_calling_info *calling);

// imemo_callcache

struct rb_callcache {
    const VALUE flags;

    /* inline cache: key */
    const VALUE klass; // should not mark it because klass can not be free'd
                       // because of this marking. When klass is collected,
                       // cc will be cleared (cc->klass = 0) at vm_ccs_free().

    /* inline cache: values */
    const struct rb_callable_method_entry_struct * const cme_;
    const vm_call_handler call_;

    union {
        struct {
          uintptr_t value; // Shape ID in upper bits, index in lower bits
        } attr;
        const enum method_missing_reason method_missing_reason; /* used by method_missing */
        VALUE v;
        const struct rb_builtin_function *bf;
    } aux_;
};

#define VM_CALLCACHE_UNMARKABLE FL_FREEZE
#define VM_CALLCACHE_ON_STACK   FL_EXIVAR

/* VM_CALLCACHE_IVAR used for IVAR/ATTRSET/STRUCT_AREF/STRUCT_ASET methods */
#define VM_CALLCACHE_IVAR       IMEMO_FL_USER0
#define VM_CALLCACHE_BF         IMEMO_FL_USER1
#define VM_CALLCACHE_SUPER      IMEMO_FL_USER2
#define VM_CALLCACHE_REFINEMENT IMEMO_FL_USER3

enum vm_cc_type {
    cc_type_normal, // chained from ccs
    cc_type_super,
    cc_type_refinement,
};

extern const struct rb_callcache *rb_vm_empty_cc(void);
extern const struct rb_callcache *rb_vm_empty_cc_for_super(void);

#define vm_cc_empty() rb_vm_empty_cc()

static inline void vm_cc_attr_index_set(const struct rb_callcache *cc, attr_index_t index, shape_id_t dest_shape_id);

static inline void
vm_cc_attr_index_initialize(const struct rb_callcache *cc, shape_id_t shape_id)
{
    vm_cc_attr_index_set(cc, (attr_index_t)-1, shape_id);
}

static inline const struct rb_callcache *
vm_cc_new(VALUE klass,
          const struct rb_callable_method_entry_struct *cme,
          vm_call_handler call,
          enum vm_cc_type type)
{
    struct rb_callcache *cc = IMEMO_NEW(struct rb_callcache, imemo_callcache, klass);
    *((struct rb_callable_method_entry_struct **)&cc->cme_) = (struct rb_callable_method_entry_struct *)cme;
    *((vm_call_handler *)&cc->call_) = call;

    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_ICLASS));

    switch (type) {
      case cc_type_normal:
        break;
      case cc_type_super:
        *(VALUE *)&cc->flags |= VM_CALLCACHE_SUPER;
        break;
      case cc_type_refinement:
        *(VALUE *)&cc->flags |= VM_CALLCACHE_REFINEMENT;
        break;
    }

    if (cme->def->type == VM_METHOD_TYPE_ATTRSET || cme->def->type == VM_METHOD_TYPE_IVAR) {
        vm_cc_attr_index_initialize(cc, INVALID_SHAPE_ID);
    }

    RB_DEBUG_COUNTER_INC(cc_new);
    return cc;
}

static inline bool
vm_cc_super_p(const struct rb_callcache *cc)
{
    return (cc->flags & VM_CALLCACHE_SUPER) != 0;
}

static inline bool
vm_cc_refinement_p(const struct rb_callcache *cc)
{
    return (cc->flags & VM_CALLCACHE_REFINEMENT) != 0;
}

#define VM_CC_ON_STACK(clazz, call, aux, cme) \
    (struct rb_callcache) {                   \
        .flags = T_IMEMO |                    \
            (imemo_callcache << FL_USHIFT) |  \
            VM_CALLCACHE_UNMARKABLE |         \
            VM_CALLCACHE_ON_STACK,            \
        .klass = clazz,                       \
        .cme_  = cme,                         \
        .call_ = call,                        \
        .aux_  = aux,                         \
    }

static inline bool
vm_cc_class_check(const struct rb_callcache *cc, VALUE klass)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc->klass == 0 ||
              RB_TYPE_P(cc->klass, T_CLASS) || RB_TYPE_P(cc->klass, T_ICLASS));
    return cc->klass == klass;
}

static inline int
vm_cc_markable(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return FL_TEST_RAW((VALUE)cc, VM_CALLCACHE_UNMARKABLE) == 0;
}

static inline const struct rb_callable_method_entry_struct *
vm_cc_cme(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc->call_ == NULL   || // not initialized yet
              !vm_cc_markable(cc) ||
              cc->cme_ != NULL);

    return cc->cme_;
}

static inline vm_call_handler
vm_cc_call(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc->call_ != NULL);
    return cc->call_;
}

static inline attr_index_t
vm_cc_attr_index(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return (attr_index_t)((cc->aux_.attr.value & SHAPE_FLAG_MASK) - 1);
}

static inline shape_id_t
vm_cc_attr_index_dest_shape_id(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));

    return cc->aux_.attr.value >> SHAPE_FLAG_SHIFT;
}

static inline void
vm_cc_atomic_shape_and_index(const struct rb_callcache *cc, shape_id_t * shape_id, attr_index_t * index)
{
    uintptr_t cache_value = cc->aux_.attr.value; // Atomically read 64 bits
    *shape_id = (shape_id_t)(cache_value >> SHAPE_FLAG_SHIFT);
    *index = (attr_index_t)(cache_value & SHAPE_FLAG_MASK) - 1;
    return;
}

static inline void
vm_ic_atomic_shape_and_index(const struct iseq_inline_iv_cache_entry *ic, shape_id_t * shape_id, attr_index_t * index)
{
    uintptr_t cache_value = ic->value; // Atomically read 64 bits
    *shape_id = (shape_id_t)(cache_value >> SHAPE_FLAG_SHIFT);
    *index = (attr_index_t)(cache_value & SHAPE_FLAG_MASK) - 1;
    return;
}

static inline shape_id_t
vm_ic_attr_index_dest_shape_id(const struct iseq_inline_iv_cache_entry *ic)
{
    return (shape_id_t)(ic->value >> SHAPE_FLAG_SHIFT);
}

static inline unsigned int
vm_cc_cmethod_missing_reason(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return cc->aux_.method_missing_reason;
}

static inline bool
vm_cc_invalidated_p(const struct rb_callcache *cc)
{
    if (cc->klass && !METHOD_ENTRY_INVALIDATED(vm_cc_cme(cc))) {
        return false;
    }
    else {
        return true;
    }
}

/* callcache: mutate */

static inline void
vm_cc_call_set(const struct rb_callcache *cc, vm_call_handler call)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *(vm_call_handler *)&cc->call_ = call;
}

static inline void
set_vm_cc_ivar(const struct rb_callcache *cc)
{
    *(VALUE *)&cc->flags |= VM_CALLCACHE_IVAR;
}

static inline void
vm_cc_attr_index_set(const struct rb_callcache *cc, attr_index_t index, shape_id_t dest_shape_id)
{
    uintptr_t *attr_value = (uintptr_t *)&cc->aux_.attr.value;
    if (!vm_cc_markable(cc)) {
        *attr_value = (uintptr_t)INVALID_SHAPE_ID << SHAPE_FLAG_SHIFT;
        return;
    }
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *attr_value = (attr_index_t)(index + 1) | ((uintptr_t)(dest_shape_id) << SHAPE_FLAG_SHIFT);
    set_vm_cc_ivar(cc);
}

static inline bool
vm_cc_ivar_p(const struct rb_callcache *cc)
{
    return (cc->flags & VM_CALLCACHE_IVAR) != 0;
}

static inline void
vm_ic_attr_index_set(const rb_iseq_t *iseq, const struct iseq_inline_iv_cache_entry *ic, attr_index_t index, shape_id_t dest_shape_id)
{
    *(uintptr_t *)&ic->value = ((uintptr_t)dest_shape_id << SHAPE_FLAG_SHIFT) | (attr_index_t)(index + 1);
}

static inline void
vm_ic_attr_index_initialize(const struct iseq_inline_iv_cache_entry *ic, shape_id_t shape_id)
{
    *(uintptr_t *)&ic->value = (uintptr_t)shape_id << SHAPE_FLAG_SHIFT;
}

static inline void
vm_cc_method_missing_reason_set(const struct rb_callcache *cc, enum method_missing_reason reason)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *(enum method_missing_reason *)&cc->aux_.method_missing_reason = reason;
}

static inline void
vm_cc_bf_set(const struct rb_callcache *cc, const struct rb_builtin_function *bf)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *(const struct rb_builtin_function **)&cc->aux_.bf = bf;
    *(VALUE *)&cc->flags |= VM_CALLCACHE_BF;
}

static inline bool
vm_cc_bf_p(const struct rb_callcache *cc)
{
    return (cc->flags & VM_CALLCACHE_BF) != 0;
}

static inline void
vm_cc_invalidate(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    VM_ASSERT(cc->klass != 0); // should be enable

    *(VALUE *)&cc->klass = 0;
    RB_DEBUG_COUNTER_INC(cc_ent_invalidate);
}

/* calldata */

struct rb_call_data {
    const struct rb_callinfo *ci;
    const struct rb_callcache *cc;
};

struct rb_class_cc_entries {
#if VM_CHECK_MODE > 0
    VALUE debug_sig;
#endif
    int capa;
    int len;
    const struct rb_callable_method_entry_struct *cme;
    struct rb_class_cc_entries_entry {
        unsigned int argc;
        unsigned int flag;
        const struct rb_callcache *cc;
    } *entries;
};

#if VM_CHECK_MODE > 0

const rb_callable_method_entry_t *rb_vm_lookup_overloaded_cme(const rb_callable_method_entry_t *cme);
void rb_vm_dump_overloaded_cme_table(void);

static inline bool
vm_ccs_p(const struct rb_class_cc_entries *ccs)
{
    return ccs->debug_sig == ~(VALUE)ccs;
}

static inline bool
vm_cc_check_cme(const struct rb_callcache *cc, const rb_callable_method_entry_t *cme)
{
    if (vm_cc_cme(cc) == cme ||
        (cme->def->iseq_overload && vm_cc_cme(cc) == rb_vm_lookup_overloaded_cme(cme))) {
        return true;
    }
    else {
#if 1
        // debug print

        fprintf(stderr, "iseq_overload:%d, cme:%p (def:%p), cm_cc_cme(cc):%p (def:%p)\n",
                (int)cme->def->iseq_overload,
                cme, cme->def,
                vm_cc_cme(cc), vm_cc_cme(cc)->def);
        rp(cme);
        rp(vm_cc_cme(cc));
        rp(rb_vm_lookup_overloaded_cme(cme));
#endif
        return false;
    }
}

#endif

// gc.c
void rb_vm_ccs_free(struct rb_class_cc_entries *ccs);

#endif /* RUBY_VM_CALLINFO_H */
