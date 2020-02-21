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
#define CI_EMBED_ARGC_MASK ((1UL<<CI_EMBED_ARGC_bits) - 1)
#define CI_EMBED_FLAG_SHFT (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits)
#define CI_EMBED_FLAG_MASK ((1UL<<CI_EMBED_FLAG_bits) - 1)
#define CI_EMBED_ID_SHFT   (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits + CI_EMBED_FLAG_bits)
#define CI_EMBED_ID_MASK   ((1UL<<CI_EMBED_ID_bits) - 1)

static inline int
vm_ci_packed_p(const struct rb_callinfo *ci)
{
#if USE_EMBED_CI
    if (LIKELY(((VALUE)ci) & 0x01)) {
        return 1;
    }
    else {
        VM_ASSERT(imemo_type_p((VALUE)ci, imemo_callinfo));
        return 0;
    }
#else
    return 0;
#endif
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

#if 0 // for debug
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
#endif

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
          1L                           |
          ((VALUE)argc << CI_EMBED_ARGC_SHFT) |
          ((VALUE)flag << CI_EMBED_FLAG_SHFT) |
          ((VALUE)mid  << CI_EMBED_ID_SHFT);
        RB_DEBUG_COUNTER_INC(ci_packed);
        return (const struct rb_callinfo *)embed_ci;
    }
#endif
    const bool debug = 0;
    if (debug) fprintf(stderr, "%s:%d ", file, line);
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
