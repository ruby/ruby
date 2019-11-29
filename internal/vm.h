#ifndef INTERNAL_VM_H /* -*- C -*- */
#define INTERNAL_VM_H
/**
 * @file
 * @brief      Internal header for RubyVM.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* vm_insnhelper.h */
rb_serial_t rb_next_class_serial(void);

/* vm.c */
VALUE rb_obj_is_thread(VALUE obj);
void rb_vm_mark(void *ptr);
PUREFUNC(VALUE rb_vm_top_self(void));
void rb_vm_inc_const_missing_count(void);
const void **rb_vm_get_insns_address_table(void);
VALUE rb_source_location(int *pline);
const char *rb_source_location_cstr(int *pline);
MJIT_STATIC void rb_vm_pop_cfunc_frame(void);
int rb_vm_add_root_module(ID id, VALUE module);
void rb_vm_check_redefinition_by_prepend(VALUE klass);
int rb_vm_check_optimizable_mid(VALUE mid);
VALUE rb_yield_refine_block(VALUE refinement, VALUE refinements);
MJIT_STATIC VALUE ruby_vm_special_exception_copy(VALUE);
PUREFUNC(st_table *rb_vm_fstring_table(void));

/* vm_eval.c */
VALUE rb_adjust_argv_kw_splat(int *, const VALUE **, int *);
VALUE rb_current_realfilepath(void);
VALUE rb_check_block_call(VALUE, ID, int, const VALUE *, rb_block_call_func_t, VALUE);
typedef void rb_check_funcall_hook(int, VALUE, ID, int, const VALUE *, VALUE);
VALUE rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
                                 rb_check_funcall_hook *hook, VALUE arg);
VALUE rb_check_funcall_with_hook_kw(VALUE recv, ID mid, int argc, const VALUE *argv,
                                 rb_check_funcall_hook *hook, VALUE arg, int kw_splat);
const char *rb_type_str(enum ruby_value_type type);
VALUE rb_check_funcall_default(VALUE, ID, int, const VALUE *, VALUE);
VALUE rb_yield_1(VALUE val);
VALUE rb_yield_force_blockarg(VALUE values);
VALUE rb_lambda_call(VALUE obj, ID mid, int argc, const VALUE *argv,
                     rb_block_call_func_t bl_proc, int min_argc, int max_argc,
                     VALUE data2);

/* vm_insnhelper.c */
VALUE rb_equal_opt(VALUE obj1, VALUE obj2);
VALUE rb_eql_opt(VALUE obj1, VALUE obj2);

/* vm_method.c */
enum method_missing_reason {
    MISSING_NOENTRY   = 0x00,
    MISSING_PRIVATE   = 0x01,
    MISSING_PROTECTED = 0x02,
    MISSING_FCALL     = 0x04,
    MISSING_VCALL     = 0x08,
    MISSING_SUPER     = 0x10,
    MISSING_MISSING   = 0x20,
    MISSING_NONE      = 0x40
};
struct rb_callable_method_entry_struct;
struct rb_method_definition_struct;
struct rb_execution_context_struct;
struct rb_control_frame_struct;
struct rb_calling_info;
struct rb_call_data;
/* I have several reasons to chose 64 here:
 *
 * - A cache line must be a power-of-two size.
 * - Setting this to anything less than or equal to 32 boosts nothing.
 * - I have never seen an architecture that has 128 byte L1 cache line.
 * - I know Intel Core and Sparc T4 at least uses 64.
 * - I know jemalloc internally has this exact same `#define CACHE_LINE 64`.
 *   https://github.com/jemalloc/jemalloc/blob/dev/include/jemalloc/internal/jemalloc_internal_types.h
 */
#define CACHELINE 64
struct rb_call_cache {
    /* inline cache: keys */
    rb_serial_t method_state;
    rb_serial_t class_serial[
        (CACHELINE
         - sizeof(rb_serial_t)                                   /* method_state */
         - sizeof(struct rb_callable_method_entry_struct *)      /* me */
         - sizeof(uintptr_t)                                     /* method_serial */
         - sizeof(enum method_missing_reason)                    /* aux */
         - sizeof(VALUE (*)(                                     /* call */
               struct rb_execution_context_struct *e,
               struct rb_control_frame_struct *,
               struct rb_calling_info *,
               const struct rb_call_data *)))
        / sizeof(rb_serial_t)
    ];

    /* inline cache: values */
    const struct rb_callable_method_entry_struct *me;
    uintptr_t method_serial; /* me->def->method_serial */

    VALUE (*call)(struct rb_execution_context_struct *ec,
                  struct rb_control_frame_struct *cfp,
                  struct rb_calling_info *calling,
                  struct rb_call_data *cd);

    union {
        unsigned int index; /* used by ivar */
        enum method_missing_reason method_missing_reason; /* used by method_missing */
    } aux;
};
STATIC_ASSERT(cachelined, sizeof(struct rb_call_cache) <= CACHELINE);
struct rb_call_info {
    /* fixed at compile time */
    ID mid;
    unsigned int flag;
    int orig_argc;
};
struct rb_call_data {
    struct rb_call_cache cc;
    struct rb_call_info ci;
};
RUBY_FUNC_EXPORTED
RUBY_FUNC_NONNULL(1, VALUE rb_funcallv_with_cc(struct rb_call_data*, VALUE, ID, int, const VALUE*));
RUBY_FUNC_EXPORTED
RUBY_FUNC_NONNULL(1, bool rb_method_basic_definition_p_with_cc(struct rb_call_data *, VALUE, ID));

#ifdef __GNUC__
# define rb_funcallv(recv, mid, argc, argv) \
    __extension__({ \
        static struct rb_call_data rb_funcallv_data; \
        rb_funcallv_with_cc(&rb_funcallv_data, recv, mid, argc, argv); \
    })
# define rb_method_basic_definition_p(klass, mid) \
    __extension__({ \
        static struct rb_call_data rb_mbdp; \
        (klass == Qfalse) ? /* hidden object cannot be overridden */ true : \
            rb_method_basic_definition_p_with_cc(&rb_mbdp, klass, mid); \
    })
#endif

/* vm_dump.c */
void rb_print_backtrace(void);

/* vm_backtrace.c */
VALUE rb_vm_thread_backtrace(int argc, const VALUE *argv, VALUE thval);
VALUE rb_vm_thread_backtrace_locations(int argc, const VALUE *argv, VALUE thval);

VALUE rb_make_backtrace(void);
void rb_backtrace_print_as_bugreport(void);
int rb_backtrace_p(VALUE obj);
VALUE rb_backtrace_to_str_ary(VALUE obj);
VALUE rb_backtrace_to_location_ary(VALUE obj);
void rb_backtrace_each(VALUE (*iter)(VALUE recv, VALUE str), VALUE output);

#define RUBY_DTRACE_CREATE_HOOK(name, arg) \
    RUBY_DTRACE_HOOK(name##_CREATE, arg)
#define RUBY_DTRACE_HOOK(name, arg) \
do { \
    if (UNLIKELY(RUBY_DTRACE_##name##_ENABLED())) { \
        int dtrace_line; \
        const char *dtrace_file = rb_source_location_cstr(&dtrace_line); \
        if (!dtrace_file) dtrace_file = ""; \
        RUBY_DTRACE_##name(arg, dtrace_file, dtrace_line); \
    } \
} while (0)
#endif /* INTERNAL_VM_H */
