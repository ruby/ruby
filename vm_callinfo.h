#include "debug_counter.h"

enum vm_call_flag_bits {
    VM_CALL_ARGS_SPLAT_bit,     /* m(*args) */
    VM_CALL_ARGS_BLOCKARG_bit,  /* m(&block) */
    VM_CALL_FCALL_bit,          /* m(...) */
    VM_CALL_VCALL_bit,          /* m */
    VM_CALL_ARGS_SIMPLE_bit,    /* (ci->flag & (SPLAT|BLOCKARG)) && blockiseq == NULL && ci->kw_arg == NULL */
    VM_CALL_BLOCKISEQ_bit,      /* has blockiseq */
    VM_CALL_KWARG_bit,          /* has kwarg */
    VM_CALL_KW_SPLAT_bit,       /* m(**opts) */
    VM_CALL_TAILCALL_bit,       /* located at tail position */
    VM_CALL_SUPER_bit,          /* super */
    VM_CALL_ZSUPER_bit,         /* zsuper */
    VM_CALL_OPT_SEND_bit,       /* internal flag */
    VM_CALL__END
};

#define VM_CALL_ARGS_SPLAT      (0x01 << VM_CALL_ARGS_SPLAT_bit)
#define VM_CALL_ARGS_BLOCKARG   (0x01 << VM_CALL_ARGS_BLOCKARG_bit)
#define VM_CALL_FCALL           (0x01 << VM_CALL_FCALL_bit)
#define VM_CALL_VCALL           (0x01 << VM_CALL_VCALL_bit)
#define VM_CALL_ARGS_SIMPLE     (0x01 << VM_CALL_ARGS_SIMPLE_bit)
#define VM_CALL_BLOCKISEQ       (0x01 << VM_CALL_BLOCKISEQ_bit)
#define VM_CALL_KWARG           (0x01 << VM_CALL_KWARG_bit)
#define VM_CALL_KW_SPLAT        (0x01 << VM_CALL_KW_SPLAT_bit)
#define VM_CALL_TAILCALL        (0x01 << VM_CALL_TAILCALL_bit)
#define VM_CALL_SUPER           (0x01 << VM_CALL_SUPER_bit)
#define VM_CALL_ZSUPER          (0x01 << VM_CALL_ZSUPER_bit)
#define VM_CALL_OPT_SEND        (0x01 << VM_CALL_OPT_SEND_bit)

struct rb_callinfo_kwarg {
    int keyword_len;
    VALUE keywords[1];
};

static inline size_t
rb_callinfo_kwarg_bytes(int keyword_len)
{
    return rb_size_mul_add_or_raise(
        keyword_len - 1,
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

#ifndef USE_EMBED_CI
#define USE_EMBED_CI 1
#endif

#if SIZEOF_VALUE == 8
#define CI_EMBED_TAG_bits   1
#define CI_EMBED_ARGC_bits 15
#define CI_EMBED_FLAG_bits 16
#define CI_EMBED_ID_bits   32
#elif SIZEOF_VALUE == 4
#define CI_EMBED_TAG_bits   1
#define CI_EMBED_ARGC_bits  4
#define CI_EMBED_FLAG_bits 12
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
#if USE_EMBED_CI
    if (LIKELY(((VALUE)ci) & 0x01)) {
        return 1;
    }
    else {
        VM_ASSERT(IMEMO_TYPE_P(ci, imemo_callinfo));
        return 0;
    }
#else
    return 0;
#endif
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
        fprintf(stderr, "packed_ci ID:%s flag:%x argc:%u\n",
                rb_id2name(vm_ci_mid(ci)), vm_ci_flag(ci), vm_ci_argc(ci));
    }
    else {
        rp(ci);
    }
}

#define vm_ci_new(mid, flag, argc, kwarg) vm_ci_new_(mid, flag, argc, kwarg, __FILE__, __LINE__)
#define vm_ci_new_runtime(mid, flag, argc, kwarg) vm_ci_new_runtime_(mid, flag, argc, kwarg, __FILE__, __LINE__)

static inline const struct rb_callinfo *
vm_ci_new_(ID mid, unsigned int flag, unsigned int argc, const struct rb_callinfo_kwarg *kwarg, const char *file, int line)
{
#if USE_EMBED_CI
    if ((mid & ~CI_EMBED_ID_MASK) == 0 &&
        (argc & ~CI_EMBED_ARGC_MASK) == 0 &&
        kwarg == NULL) {
        VALUE embed_ci =
          1L                                  |
          ((VALUE)argc << CI_EMBED_ARGC_SHFT) |
          ((VALUE)flag << CI_EMBED_FLAG_SHFT) |
          ((VALUE)mid  << CI_EMBED_ID_SHFT);
        RB_DEBUG_COUNTER_INC(ci_packed);
        return (const struct rb_callinfo *)embed_ci;
    }
#endif

    const bool debug = 0;
    if (debug) fprintf(stderr, "%s:%d ", file, line);

    // TODO: dedup
    const struct rb_callinfo *ci = (const struct rb_callinfo *)
      rb_imemo_new(imemo_callinfo,
                   (VALUE)mid,
                   (VALUE)flag,
                   (VALUE)argc,
                   (VALUE)kwarg);
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

typedef VALUE (*vm_call_handler)(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *cfp,
    struct rb_calling_info *calling,
    struct rb_call_data *cd);

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
        const unsigned int attr_index;
        const enum method_missing_reason method_missing_reason; /* used by method_missing */
        VALUE v;
    } aux_;
};

#define VM_CALLCACHE_UNMARKABLE IMEMO_FL_USER0

static inline const struct rb_callcache *
vm_cc_new(VALUE klass,
          const struct rb_callable_method_entry_struct *cme,
          vm_call_handler call)
{
    const struct rb_callcache *cc = (const struct rb_callcache *)rb_imemo_new(imemo_callcache, (VALUE)cme, (VALUE)call, 0, klass);
    RB_DEBUG_COUNTER_INC(cc_new);
    return cc;
}

static inline const struct rb_callcache *
vm_cc_fill(struct rb_callcache *cc,
           VALUE klass,
           const struct rb_callable_method_entry_struct *cme,
           vm_call_handler call)
{
    struct rb_callcache cc_body = {
        .flags = T_IMEMO | (imemo_callcache << FL_USHIFT) | VM_CALLCACHE_UNMARKABLE,
        .klass = klass,
        .cme_ = cme,
        .call_ = call,
        .aux_.v = 0,
    };
    MEMCPY(cc, &cc_body, struct rb_callcache, 1);
    return cc;
}

static inline bool
vm_cc_class_check(const struct rb_callcache *cc, VALUE klass)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc->klass == 0 ||
              RB_TYPE_P(cc->klass, T_CLASS) || RB_TYPE_P(cc->klass, T_ICLASS));
    return cc->klass == klass;
}

static inline const struct rb_callable_method_entry_struct *
vm_cc_cme(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return cc->cme_;
}

static inline vm_call_handler
vm_cc_call(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return cc->call_;
}

static inline unsigned int
vm_cc_attr_index(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return cc->aux_.attr_index;
}

static inline unsigned int
vm_cc_cmethod_missing_reason(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return cc->aux_.method_missing_reason;
}

static inline int
vm_cc_markable(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    return FL_TEST_RAW(cc, VM_CALLCACHE_UNMARKABLE) == 0;
}

static inline bool
vm_cc_valid_p(const struct rb_callcache *cc, VALUE klass)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    if (cc->klass == klass && !METHOD_ENTRY_INVALIDATED(vm_cc_cme(cc))) {
        return 1;
    }
    else {
        return 0;
    }
}

#ifndef MJIT_HEADER
extern const struct rb_callcache *vm_empty_cc;
#else
extern const struct rb_callcache *rb_vm_empty_cc(void);
#endif

static inline const struct rb_callcache *
vm_cc_empty(void)
{
#ifndef MJIT_HEADER
    return vm_empty_cc;
#else
    return rb_vm_empty_cc();
#endif
}

/* callcache: mutete */

static inline void
vm_cc_cme_set(const struct rb_callcache *cc, const struct rb_callable_method_entry_struct *cme)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    VM_ASSERT(vm_cc_cme(cc) != NULL);
    VM_ASSERT(vm_cc_cme(cc)->called_id == cme->called_id);
    VM_ASSERT(!vm_cc_markable(cc)); // only used for vm_eval.c

    *((const struct rb_callable_method_entry_struct **)&cc->cme_) = cme;
}

static inline void
vm_cc_call_set(const struct rb_callcache *cc, vm_call_handler call)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *(vm_call_handler *)&cc->call_ = call;
}

static inline void
vm_cc_attr_index_set(const struct rb_callcache *cc, int index)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *(int *)&cc->aux_.attr_index = index;
}

static inline void
vm_cc_method_missing_reason_set(const struct rb_callcache *cc, enum method_missing_reason reason)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());
    *(enum method_missing_reason *)&cc->aux_.method_missing_reason = reason;
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
        const struct rb_callinfo *ci;
        const struct rb_callcache *cc;
    } *entries;
};

#if VM_CHECK_MODE > 0
static inline bool
vm_ccs_p(const struct rb_class_cc_entries *ccs)
{
    return ccs->debug_sig == ~(VALUE)ccs;
}
#endif

// gc.c
void rb_vm_ccs_free(struct rb_class_cc_entries *ccs);
