/**********************************************************************

  vm_core.h -

  $Author$
  created at: 04/01/01 19:41:38 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_VM_CORE_H
#define RUBY_VM_CORE_H

#define RUBY_VM_THREAD_MODEL 2

#include "ruby/ruby.h"
#include "ruby/st.h"

#include "node.h"
#include "vm_debug.h"
#include "vm_opts.h"
#include "id.h"
#include "method.h"
#include "ruby_atomic.h"

#include "thread_native.h"

#ifndef ENABLE_VM_OBJSPACE
#ifdef _WIN32
/*
 * TODO: object space independent st_table.
 * socklist needs st_table in rb_w32_sysinit(), before object space
 * initialization.
 * It is too early now to change st_hash_type, since it breaks binary
 * compatibility.
 */
#define ENABLE_VM_OBJSPACE 0
#else
#define ENABLE_VM_OBJSPACE 1
#endif
#endif

#include <setjmp.h>
#include <signal.h>

#ifndef NSIG
# define NSIG (_SIGMAX + 1)      /* For QNX */
#endif

#define RUBY_NSIG NSIG

#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start((a),(b))
#else
#include <varargs.h>
#define va_init_list(a,b) va_start((a))
#endif

#if defined(SIGSEGV) && defined(HAVE_SIGALTSTACK) && defined(SA_SIGINFO) && !defined(__NetBSD__)
#define USE_SIGALTSTACK
#endif

/*****************/
/* configuration */
/*****************/

/* gcc ver. check */
#if defined(__GNUC__) && __GNUC__ >= 2

#if OPT_TOKEN_THREADED_CODE
#if OPT_DIRECT_THREADED_CODE
#undef OPT_DIRECT_THREADED_CODE
#endif
#endif

#else /* defined(__GNUC__) && __GNUC__ >= 2 */

/* disable threaded code options */
#if OPT_DIRECT_THREADED_CODE
#undef OPT_DIRECT_THREADED_CODE
#endif
#if OPT_TOKEN_THREADED_CODE
#undef OPT_TOKEN_THREADED_CODE
#endif
#endif

#ifdef __native_client__
#undef OPT_DIRECT_THREADED_CODE
#endif

/* call threaded code */
#if    OPT_CALL_THREADED_CODE
#if    OPT_DIRECT_THREADED_CODE
#undef OPT_DIRECT_THREADED_CODE
#endif /* OPT_DIRECT_THREADED_CODE */
#if    OPT_STACK_CACHING
#undef OPT_STACK_CACHING
#endif /* OPT_STACK_CACHING */
#endif /* OPT_CALL_THREADED_CODE */

/* likely */
#if __GNUC__ >= 3
#define LIKELY(x)   (__builtin_expect((x), 1))
#define UNLIKELY(x) (__builtin_expect((x), 0))
#else /* __GNUC__ >= 3 */
#define LIKELY(x)   (x)
#define UNLIKELY(x) (x)
#endif /* __GNUC__ >= 3 */

#ifndef __has_attribute
# define __has_attribute(x) 0
#endif

#if __has_attribute(unused)
#define UNINITIALIZED_VAR(x) x __attribute__((unused))
#elif defined(__GNUC__) && __GNUC__ >= 3
#define UNINITIALIZED_VAR(x) x = x
#else
#define UNINITIALIZED_VAR(x) x
#endif

typedef unsigned long rb_num_t;

/* iseq data type */

struct iseq_compile_data_ensure_node_stack;

typedef struct rb_compile_option_struct rb_compile_option_t;


struct iseq_inline_cache_entry {
    rb_serial_t ic_serial;
    union {
	size_t index;
	VALUE value;
    } ic_value;
};

union iseq_inline_storage_entry {
    struct {
	struct rb_thread_struct *running_thread;
	VALUE value;
	VALUE done;
    } once;
    struct iseq_inline_cache_entry cache;
};

/* to avoid warning */
struct rb_thread_struct;
struct rb_control_frame_struct;

/* rb_call_info_t contains calling information including inline cache */
typedef struct rb_call_info_struct {
    /* fixed at compile time */
    ID mid;
    VALUE flag;
    int orig_argc;
    rb_iseq_t *blockiseq;

    /* inline cache: keys */
    rb_serial_t method_state;
    rb_serial_t class_serial;
    VALUE klass;

    /* inline cache: values */
    const rb_method_entry_t *me;
    VALUE defined_class;

    /* temporary values for method calling */
    int argc;
    struct rb_block_struct *blockptr;
    VALUE recv;
    union {
	int opt_pc; /* used by iseq */
	long index; /* used by ivar */
	int missing_reason; /* used by method_missing */
	int inc_sp; /* used by cfunc */
    } aux;

    VALUE (*call)(struct rb_thread_struct *th, struct rb_control_frame_struct *cfp, struct rb_call_info_struct *ci);
} rb_call_info_t;

#if 1
#define GetCoreDataFromValue(obj, type, ptr) do { \
    (ptr) = (type*)DATA_PTR(obj); \
} while (0)
#else
#define GetCoreDataFromValue(obj, type, ptr) Data_Get_Struct((obj), type, (ptr))
#endif

#define GetISeqPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_iseq_t, (ptr))

typedef struct rb_iseq_location_struct {
    const VALUE path;
    const VALUE absolute_path;
    const VALUE base_label;
    const VALUE label;
    size_t first_lineno;
} rb_iseq_location_t;

struct rb_iseq_struct;

struct rb_iseq_struct {
    /***************/
    /* static data */
    /***************/

    enum iseq_type {
	ISEQ_TYPE_TOP,
	ISEQ_TYPE_METHOD,
	ISEQ_TYPE_BLOCK,
	ISEQ_TYPE_CLASS,
	ISEQ_TYPE_RESCUE,
	ISEQ_TYPE_ENSURE,
	ISEQ_TYPE_EVAL,
	ISEQ_TYPE_MAIN,
	ISEQ_TYPE_DEFINED_GUARD
    } type;              /* instruction sequence type */

    rb_iseq_location_t location;

    VALUE *iseq;         /* iseq (insn number and operands) */
    VALUE *iseq_encoded; /* encoded iseq */
    unsigned long iseq_size;
    const VALUE mark_ary;     /* Array: includes operands which should be GC marked */
    const VALUE coverage;     /* coverage array */

    /* insn info, must be freed */
    struct iseq_line_info_entry *line_info_table;
    size_t line_info_size;

    ID *local_table;		/* must free */
    int local_table_size;

    /* sizeof(vars) + 1 */
    int local_size;

    union iseq_inline_storage_entry *is_entries;
    int is_size;

    rb_call_info_t *callinfo_entries;
    int callinfo_size;

    /**
     * argument information
     *
     *  def m(a1, a2, ..., aM,                    # mandatory
     *        b1=(...), b2=(...), ..., bN=(...),  # optional
     *        *c,                                 # rest
     *        d1, d2, ..., dO,                    # post
     *        e1:(...), e2:(...), ..., eK:(...),  # keyword
     *        **f,                                # keyword rest
     *        &g)                                 # block
     * =>
     *
     *  argc           = M                 // or  0 if no mandatory arg
     *  arg_opts       = N+1               // or  0 if no optional arg
     *  arg_rest       = M+N               // or -1 if no rest arg
     *  arg_opt_table  = [ (arg_opts entries) ]
     *  arg_post_start = M+N+(*1)          // or 0 if no post arguments
     *  arg_post_len   = O                 // or 0 if no post arguments
     *  arg_keywords   = K                 // or 0 if no keyword arg
     *  arg_block      = M+N+(*1)+O+K      // or -1 if no block arg
     *  arg_keyword    = M+N+(*1)+O+K+(&1) // or -1 if no keyword arg/rest
     *  arg_simple     = 0 if not simple arguments.
     *                 = 1 if no opt, rest, post, block.
     *                 = 2 if ambiguous block parameter ({|a|}).
     *  arg_size       = M+N+O+(*1)+K+(&1)+(**1) argument size.
     */

    int argc;
    int arg_simple;
    int arg_rest;
    int arg_block;
    int arg_opts;
    int arg_post_len;
    int arg_post_start;
    int arg_size;
    VALUE *arg_opt_table;
    int arg_keyword;
    int arg_keyword_check; /* if this is true, raise an ArgumentError when unknown keyword argument is passed */
    int arg_keywords;
    int arg_keyword_required;
    ID *arg_keyword_table;

    size_t stack_max; /* for stack overflow check */

    /* catch table */
    struct iseq_catch_table_entry *catch_table;
    int catch_table_size;

    /* for child iseq */
    struct rb_iseq_struct *parent_iseq;
    struct rb_iseq_struct *local_iseq;

    /****************/
    /* dynamic data */
    /****************/

    VALUE self;
    const VALUE orig;			/* non-NULL if its data have origin */

    /* block inlining */
    /*
     * NODE *node;
     * void *special_block_builder;
     * void *cached_special_block_builder;
     * VALUE cached_special_block;
     */

    /* klass/module nest information stack (cref) */
    NODE * const cref_stack;
    const VALUE klass;

    /* misc */
    ID defined_method_id;	/* for define_method */
    rb_num_t flip_cnt;

    /* used at compile time */
    struct iseq_compile_data *compile_data;
};

enum ruby_special_exceptions {
    ruby_error_reenter,
    ruby_error_nomemory,
    ruby_error_sysstack,
    ruby_error_closed_stream,
    ruby_special_error_count
};

#define GetVMPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_vm_t, (ptr))

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
struct rb_objspace;
void rb_objspace_free(struct rb_objspace *);
#endif

typedef struct rb_hook_list_struct {
    struct rb_event_hook_struct *hooks;
    rb_event_flag_t events;
    int need_clean;
} rb_hook_list_t;

typedef struct rb_vm_struct {
    VALUE self;

    rb_global_vm_lock_t gvl;
    rb_nativethread_lock_t    thread_destruct_lock;

    struct rb_thread_struct *main_thread;
    struct rb_thread_struct *running_thread;

    st_table *living_threads;
    VALUE thgroup_default;

    int running;
    int thread_abort_on_exception;
    int trace_running;
    volatile int sleeper;

    /* object management */
    VALUE mark_object_ary;

    VALUE special_exceptions[ruby_special_error_count];

    /* load */
    VALUE top_self;
    VALUE load_path;
    VALUE load_path_snapshot;
    VALUE load_path_check_cache;
    VALUE expanded_load_path;
    VALUE loaded_features;
    VALUE loaded_features_snapshot;
    struct st_table *loaded_features_index;
    struct st_table *loading_table;

    /* signal */
    struct {
	VALUE cmd;
	int safe;
    } trap_list[RUBY_NSIG];

    /* hook */
    rb_hook_list_t event_hooks;

    /* relation table of ensure - rollback for callcc */
    struct st_table *ensure_rollback_table;

    /* postponed_job */
    struct rb_postponed_job_struct *postponed_job_buffer;
    int postponed_job_index;

    int src_encoding_index;

    VALUE verbose, debug, orig_progname, progname;
    VALUE coverages;

    struct unlinked_method_entry_list_entry *unlinked_method_entry_list;

    VALUE defined_module_hash;

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
    struct rb_objspace *objspace;
#endif

    /*
     * @shyouhei notes that this is not for storing normal Ruby
     * objects so do *NOT* mark this when you GC.
     */
    struct RArray at_exit;

    VALUE *defined_strings;

    /* params */
    struct { /* size in byte */
	size_t thread_vm_stack_size;
	size_t thread_machine_stack_size;
	size_t fiber_vm_stack_size;
	size_t fiber_machine_stack_size;
    } default_params;
} rb_vm_t;

/* default values */

#define RUBY_VM_SIZE_ALIGN 4096

#define RUBY_VM_THREAD_VM_STACK_SIZE          ( 128 * 1024 * sizeof(VALUE)) /*  512 KB or 1024 KB */
#define RUBY_VM_THREAD_VM_STACK_SIZE_MIN      (   2 * 1024 * sizeof(VALUE)) /*    8 KB or   16 KB */
#define RUBY_VM_THREAD_MACHINE_STACK_SIZE     ( 128 * 1024 * sizeof(VALUE)) /*  512 KB or 1024 KB */
#define RUBY_VM_THREAD_MACHINE_STACK_SIZE_MIN (  16 * 1024 * sizeof(VALUE)) /*   64 KB or  128 KB */

#define RUBY_VM_FIBER_VM_STACK_SIZE           (  16 * 1024 * sizeof(VALUE)) /*   64 KB or  128 KB */
#define RUBY_VM_FIBER_VM_STACK_SIZE_MIN       (   2 * 1024 * sizeof(VALUE)) /*    8 KB or   16 KB */
#define RUBY_VM_FIBER_MACHINE_STACK_SIZE      (  64 * 1024 * sizeof(VALUE)) /*  256 KB or  512 KB */
#define RUBY_VM_FIBER_MACHINE_STACK_SIZE_MIN  (  16 * 1024 * sizeof(VALUE)) /*   64 KB or  128 KB */

#ifndef VM_DEBUG_BP_CHECK
#define VM_DEBUG_BP_CHECK 0
#endif

typedef struct rb_control_frame_struct {
    VALUE *pc;			/* cfp[0] */
    VALUE *sp;			/* cfp[1] */
    rb_iseq_t *iseq;		/* cfp[2] */
    VALUE flag;			/* cfp[3] */
    VALUE self;			/* cfp[4] / block[0] */
    VALUE klass;		/* cfp[5] / block[1] */
    VALUE *ep;			/* cfp[6] / block[2] */
    rb_iseq_t *block_iseq;	/* cfp[7] / block[3] */
    VALUE proc;			/* cfp[8] / block[4] */
    const rb_method_entry_t *me;/* cfp[9] */

#if VM_DEBUG_BP_CHECK
    VALUE *bp_check;		/* cfp[10] */
#endif
} rb_control_frame_t;

typedef struct rb_block_struct {
    VALUE self;			/* share with method frame if it's only block */
    VALUE klass;		/* share with method frame if it's only block */
    VALUE *ep;			/* share with method frame if it's only block */
    rb_iseq_t *iseq;
    VALUE proc;
} rb_block_t;

extern const rb_data_type_t ruby_threadptr_data_type;

#define GetThreadPtr(obj, ptr) \
    TypedData_Get_Struct((obj), rb_thread_t, &ruby_threadptr_data_type, (ptr))

enum rb_thread_status {
    THREAD_RUNNABLE,
    THREAD_STOPPED,
    THREAD_STOPPED_FOREVER,
    THREAD_KILLED
};

typedef RUBY_JMP_BUF rb_jmpbuf_t;

/*
  the members which are written in TH_PUSH_TAG() should be placed at
  the beginning and the end, so that entire region is accessible.
*/
struct rb_vm_tag {
    VALUE tag;
    VALUE retval;
    rb_jmpbuf_t buf;
    struct rb_vm_tag *prev;
};

struct rb_vm_protect_tag {
    struct rb_vm_protect_tag *prev;
};

struct rb_unblock_callback {
    rb_unblock_function_t *func;
    void *arg;
};

struct rb_mutex_struct;

struct rb_thread_struct;
typedef struct rb_thread_list_struct{
    struct rb_thread_list_struct *next;
    struct rb_thread_struct *th;
} rb_thread_list_t;


typedef struct rb_ensure_entry {
    VALUE marker;
    VALUE (*e_proc)(ANYARGS);
    VALUE data2;
} rb_ensure_entry_t;

typedef struct rb_ensure_list {
    struct rb_ensure_list *next;
    struct rb_ensure_entry entry;
} rb_ensure_list_t;

typedef struct rb_thread_struct {
    VALUE self;
    rb_vm_t *vm;

    /* execution information */
    VALUE *stack;		/* must free, must mark */
    size_t stack_size;          /* size in word (byte size / sizeof(VALUE)) */
    rb_control_frame_t *cfp;
    int safe_level;
    int raised_flag;
    VALUE last_status; /* $? */

    /* passing state */
    int state;

    int waiting_fd;

    /* for rb_iterate */
    const rb_block_t *passed_block;

    /* for bmethod */
    const rb_method_entry_t *passed_bmethod_me;

    /* for cfunc */
    rb_call_info_t *passed_ci;

    /* for load(true) */
    VALUE top_self;
    VALUE top_wrapper;

    /* eval env */
    rb_block_t *base_block;

    VALUE *root_lep;
    VALUE root_svar;

    /* thread control */
    rb_nativethread_id_t thread_id;
    enum rb_thread_status status;
    int to_kill;
    int priority;

    native_thread_data_t native_thread_data;
    void *blocking_region_buffer;

    VALUE thgroup;
    VALUE value;

    /* temporary place of errinfo */
    VALUE errinfo;

    /* temporary place of retval on OPT_CALL_THREADED_CODE */
#if OPT_CALL_THREADED_CODE
    VALUE retval;
#endif

    /* async errinfo queue */
    VALUE pending_interrupt_queue;
    int pending_interrupt_queue_checked;
    VALUE pending_interrupt_mask_stack;

    rb_atomic_t interrupt_flag;
    unsigned long interrupt_mask;
    rb_nativethread_lock_t interrupt_lock;
    rb_nativethread_cond_t interrupt_cond;
    struct rb_unblock_callback unblock;
    VALUE locking_mutex;
    struct rb_mutex_struct *keeping_mutexes;

    struct rb_vm_tag *tag;
    struct rb_vm_protect_tag *protect_tag;

    /*! Thread-local state of evaluation context.
     *
     *  If negative, this thread is evaluating the main program.
     *  If positive, this thread is evaluating a program under Kernel::eval
     *  family.
     */
    int parse_in_eval;

    /*! Thread-local state of compiling context.
     *
     * If non-zero, the parser does not automatically print error messages to
     * stderr. */
    int mild_compile_error;

    /* storage */
    st_table *local_storage;

    rb_thread_list_t *join_list;

    VALUE first_proc;
    VALUE first_args;
    VALUE (*first_func)(ANYARGS);

    /* for GC */
    struct {
	VALUE *stack_start;
	VALUE *stack_end;
	size_t stack_maxsize;
#ifdef __ia64
	VALUE *register_stack_start;
	VALUE *register_stack_end;
	size_t register_stack_maxsize;
#endif
	jmp_buf regs;
    } machine;
    int mark_stack_len;

    /* statistics data for profiler */
    VALUE stat_insn_usage;

    /* tracer */
    rb_hook_list_t event_hooks;
    struct rb_trace_arg_struct *trace_arg; /* trace information */

    /* fiber */
    VALUE fiber;
    VALUE root_fiber;
    rb_jmpbuf_t root_jmpbuf;

    /* ensure & callcc */
    rb_ensure_list_t *ensure_list;

    /* misc */
    int method_missing_reason;
    int abort_on_exception;
#ifdef USE_SIGALTSTACK
    void *altstack;
#endif
    unsigned long running_time_us;
} rb_thread_t;

typedef enum {
    VM_DEFINECLASS_TYPE_CLASS           = 0x00,
    VM_DEFINECLASS_TYPE_SINGLETON_CLASS = 0x01,
    VM_DEFINECLASS_TYPE_MODULE          = 0x02,
    /* 0x03..0x06 is reserved */
    VM_DEFINECLASS_TYPE_MASK            = 0x07
} rb_vm_defineclass_type_t;

#define VM_DEFINECLASS_TYPE(x) ((rb_vm_defineclass_type_t)(x) & VM_DEFINECLASS_TYPE_MASK)
#define VM_DEFINECLASS_FLAG_SCOPED         0x08
#define VM_DEFINECLASS_FLAG_HAS_SUPERCLASS 0x10
#define VM_DEFINECLASS_SCOPED_P(x) ((x) & VM_DEFINECLASS_FLAG_SCOPED)
#define VM_DEFINECLASS_HAS_SUPERCLASS_P(x) \
    ((x) & VM_DEFINECLASS_FLAG_HAS_SUPERCLASS)

/* iseq.c */
RUBY_SYMBOL_EXPORT_BEGIN

/* node -> iseq */
VALUE rb_iseq_new(NODE*, VALUE, VALUE, VALUE, VALUE, enum iseq_type);
VALUE rb_iseq_new_top(NODE *node, VALUE name, VALUE path, VALUE absolute_path, VALUE parent);
VALUE rb_iseq_new_main(NODE *node, VALUE path, VALUE absolute_path);
VALUE rb_iseq_new_with_bopt(NODE*, VALUE, VALUE, VALUE, VALUE, VALUE, enum iseq_type, VALUE);
VALUE rb_iseq_new_with_opt(NODE*, VALUE, VALUE, VALUE, VALUE, VALUE, enum iseq_type, const rb_compile_option_t*);

/* src -> iseq */
VALUE rb_iseq_compile(VALUE src, VALUE file, VALUE line);
VALUE rb_iseq_compile_on_base(VALUE src, VALUE file, VALUE line, rb_block_t *base_block);
VALUE rb_iseq_compile_with_option(VALUE src, VALUE file, VALUE absolute_path, VALUE line, rb_block_t *base_block, VALUE opt);

VALUE rb_iseq_disasm(VALUE self);
int rb_iseq_disasm_insn(VALUE str, VALUE *iseqval, size_t pos, rb_iseq_t *iseq, VALUE child);
const char *ruby_node_name(int node);

RUBY_EXTERN VALUE rb_cISeq;
RUBY_EXTERN VALUE rb_cRubyVM;
RUBY_EXTERN VALUE rb_cEnv;
RUBY_EXTERN VALUE rb_mRubyVMFrozenCore;
RUBY_SYMBOL_EXPORT_END

#define GetProcPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_proc_t, (ptr))

typedef struct {
    rb_block_t block;

    VALUE envval;		/* for GC mark */
    VALUE blockprocval;
    int safe_level;
    int is_from_method;
    int is_lambda;
} rb_proc_t;

#define GetEnvPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_env_t, (ptr))

typedef struct {
    VALUE *env;
    int env_size;
    int local_size;
    VALUE prev_envval;		/* for GC mark */
    rb_block_t block;
} rb_env_t;

extern const rb_data_type_t ruby_binding_data_type;

#define GetBindingPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_binding_t, (ptr))

typedef struct {
    VALUE env;
    VALUE path;
    unsigned short first_lineno;
} rb_binding_t;

/* used by compile time and send insn */

enum vm_check_match_type {
    VM_CHECKMATCH_TYPE_WHEN = 1,
    VM_CHECKMATCH_TYPE_CASE = 2,
    VM_CHECKMATCH_TYPE_RESCUE = 3
};

#define VM_CHECKMATCH_TYPE_MASK   0x03
#define VM_CHECKMATCH_ARRAY       0x04

#define VM_CALL_ARGS_SPLAT      (0x01 << 1) /* m(*args) */
#define VM_CALL_ARGS_BLOCKARG   (0x01 << 2) /* m(&block) */
#define VM_CALL_FCALL           (0x01 << 3) /* m(...) */
#define VM_CALL_VCALL           (0x01 << 4) /* m */
#define VM_CALL_TAILCALL        (0x01 << 5) /* located at tail position */
#define VM_CALL_SUPER           (0x01 << 6) /* super */
#define VM_CALL_OPT_SEND        (0x01 << 7) /* internal flag */
#define VM_CALL_ARGS_SKIP_SETUP (0x01 << 8) /* (flag & (SPLAT|BLOCKARG)) && blockiseq == 0 */

enum vm_special_object_type {
    VM_SPECIAL_OBJECT_VMCORE = 1,
    VM_SPECIAL_OBJECT_CBASE,
    VM_SPECIAL_OBJECT_CONST_BASE
};

#define VM_FRAME_MAGIC_METHOD 0x11
#define VM_FRAME_MAGIC_BLOCK  0x21
#define VM_FRAME_MAGIC_CLASS  0x31
#define VM_FRAME_MAGIC_TOP    0x41
#define VM_FRAME_MAGIC_CFUNC  0x61
#define VM_FRAME_MAGIC_PROC   0x71
#define VM_FRAME_MAGIC_IFUNC  0x81
#define VM_FRAME_MAGIC_EVAL   0x91
#define VM_FRAME_MAGIC_LAMBDA 0xa1
#define VM_FRAME_MAGIC_MASK_BITS   8
#define VM_FRAME_MAGIC_MASK   (~(~0<<VM_FRAME_MAGIC_MASK_BITS))

#define VM_FRAME_TYPE(cfp) ((cfp)->flag & VM_FRAME_MAGIC_MASK)

/* other frame flag */
#define VM_FRAME_FLAG_PASSED  0x0100
#define VM_FRAME_FLAG_FINISH  0x0200
#define VM_FRAME_FLAG_BMETHOD 0x0400
#define VM_FRAME_TYPE_FINISH_P(cfp)  (((cfp)->flag & VM_FRAME_FLAG_FINISH) != 0)
#define VM_FRAME_TYPE_BMETHOD_P(cfp) (((cfp)->flag & VM_FRAME_FLAG_BMETHOD) != 0)

#define RUBYVM_CFUNC_FRAME_P(cfp) \
  (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_CFUNC)

/* inline cache */
typedef struct iseq_inline_cache_entry *IC;
typedef rb_call_info_t *CALL_INFO;

void rb_vm_change_state(void);

typedef VALUE CDHASH;

#ifndef FUNC_FASTCALL
#define FUNC_FASTCALL(x) x
#endif

typedef rb_control_frame_t *
  (FUNC_FASTCALL(*rb_insn_func_t))(rb_thread_t *, rb_control_frame_t *);

#define GC_GUARDED_PTR(p)     ((VALUE)((VALUE)(p) | 0x01))
#define GC_GUARDED_PTR_REF(p) ((void *)(((VALUE)(p)) & ~0x03))
#define GC_GUARDED_PTR_P(p)   (((VALUE)(p)) & 0x01)

/*
 * block frame:
 *  ep[ 0]: prev frame
 *  ep[-1]: CREF (for *_eval)
 *
 * method frame:
 *  ep[ 0]: block pointer (ptr | VM_ENVVAL_BLOCK_PTR_FLAG)
 */

#define VM_ENVVAL_BLOCK_PTR_FLAG 0x02
#define VM_ENVVAL_BLOCK_PTR(v)     (GC_GUARDED_PTR(v) | VM_ENVVAL_BLOCK_PTR_FLAG)
#define VM_ENVVAL_BLOCK_PTR_P(v)   ((v) & VM_ENVVAL_BLOCK_PTR_FLAG)
#define VM_ENVVAL_PREV_EP_PTR(v)   ((VALUE)GC_GUARDED_PTR(v))
#define VM_ENVVAL_PREV_EP_PTR_P(v) (!(VM_ENVVAL_BLOCK_PTR_P(v)))

#define VM_EP_PREV_EP(ep)   ((VALUE *)GC_GUARDED_PTR_REF((ep)[0]))
#define VM_EP_BLOCK_PTR(ep) ((rb_block_t *)GC_GUARDED_PTR_REF((ep)[0]))
#define VM_EP_LEP_P(ep)     VM_ENVVAL_BLOCK_PTR_P((ep)[0])

VALUE *rb_vm_ep_local_ep(VALUE *ep);
rb_block_t *rb_vm_control_frame_block_ptr(rb_control_frame_t *cfp);

#define RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp) ((cfp)+1)
#define RUBY_VM_NEXT_CONTROL_FRAME(cfp) ((cfp)-1)
#define RUBY_VM_END_CONTROL_FRAME(th) \
  ((rb_control_frame_t *)((th)->stack + (th)->stack_size))
#define RUBY_VM_VALID_CONTROL_FRAME_P(cfp, ecfp) \
  ((void *)(ecfp) > (void *)(cfp))
#define RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp) \
  (!RUBY_VM_VALID_CONTROL_FRAME_P((cfp), RUBY_VM_END_CONTROL_FRAME(th)))

#define RUBY_VM_IFUNC_P(ptr)        (BUILTIN_TYPE(ptr) == T_NODE)
#define RUBY_VM_NORMAL_ISEQ_P(ptr) \
  ((ptr) && !RUBY_VM_IFUNC_P(ptr))

#define RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp) ((rb_block_t *)(&(cfp)->self))
#define RUBY_VM_GET_CFP_FROM_BLOCK_PTR(b) \
  ((rb_control_frame_t *)((VALUE *)(b) - 4))
/* magic number `4' is depend on rb_control_frame_t layout. */

/* VM related object allocate functions */
VALUE rb_thread_alloc(VALUE klass);
VALUE rb_proc_alloc(VALUE klass);

/* for debug */
extern void rb_vmdebug_stack_dump_raw(rb_thread_t *, rb_control_frame_t *);
extern void rb_vmdebug_debug_print_pre(rb_thread_t *th, rb_control_frame_t *cfp, VALUE *_pc);
extern void rb_vmdebug_debug_print_post(rb_thread_t *th, rb_control_frame_t *cfp);

#define SDR() rb_vmdebug_stack_dump_raw(GET_THREAD(), GET_THREAD()->cfp)
#define SDR2(cfp) rb_vmdebug_stack_dump_raw(GET_THREAD(), (cfp))
void rb_vm_bugreport(void);

/* functions about thread/vm execution */
RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_iseq_eval(VALUE iseqval);
VALUE rb_iseq_eval_main(VALUE iseqval);
RUBY_SYMBOL_EXPORT_END
int rb_thread_method_id_and_class(rb_thread_t *th, ID *idp, VALUE *klassp);

VALUE rb_vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
			int argc, const VALUE *argv, const rb_block_t *blockptr);
VALUE rb_vm_make_proc(rb_thread_t *th, const rb_block_t *block, VALUE klass);
VALUE rb_vm_make_env_object(rb_thread_t *th, rb_control_frame_t *cfp);
VALUE rb_binding_new_with_cfp(rb_thread_t *th, const rb_control_frame_t *src_cfp);
VALUE *rb_binding_add_dynavars(rb_binding_t *bind, int dyncount, const ID *dynvars);
void rb_vm_inc_const_missing_count(void);
void rb_vm_gvl_destroy(rb_vm_t *vm);
VALUE rb_vm_call(rb_thread_t *th, VALUE recv, VALUE id, int argc,
		 const VALUE *argv, const rb_method_entry_t *me,
		 VALUE defined_class);
void rb_unlink_method_entry(rb_method_entry_t *me);
void rb_gc_mark_unlinked_live_method_entries(void *pvm);

void rb_thread_start_timer_thread(void);
void rb_thread_stop_timer_thread(int);
void rb_thread_reset_timer_thread(void);
void rb_thread_wakeup_timer_thread(void);

int ruby_thread_has_gvl_p(void);
typedef int rb_backtrace_iter_func(void *, VALUE, int, VALUE);
rb_control_frame_t *rb_vm_get_ruby_level_next_cfp(rb_thread_t *th, const rb_control_frame_t *cfp);
rb_control_frame_t *rb_vm_get_binding_creatable_next_cfp(rb_thread_t *th, const rb_control_frame_t *cfp);
int rb_vm_get_sourceline(const rb_control_frame_t *);
VALUE rb_name_err_mesg_new(VALUE obj, VALUE mesg, VALUE recv, VALUE method);
void rb_vm_stack_to_heap(rb_thread_t *th);
void ruby_thread_init_stack(rb_thread_t *th);
int rb_vm_control_frame_id_and_class(const rb_control_frame_t *cfp, ID *idp, VALUE *klassp);

void rb_gc_mark_machine_stack(rb_thread_t *th);

int rb_autoloading_value(VALUE mod, ID id, VALUE* value);

#define sysstack_error GET_VM()->special_exceptions[ruby_error_sysstack]

#define RUBY_CONST_ASSERT(expr) (1/!!(expr)) /* expr must be a compile-time constant */
#define VM_STACK_OVERFLOWED_P(cfp, sp, margin) \
    (!RUBY_CONST_ASSERT(sizeof(*(sp)) == sizeof(VALUE)) || \
     !RUBY_CONST_ASSERT(sizeof(*(cfp)) == sizeof(rb_control_frame_t)) || \
     ((rb_control_frame_t *)((sp) + (margin)) + 1) >= (cfp))
#define WHEN_VM_STACK_OVERFLOWED(cfp, sp, margin) \
    if (LIKELY(!VM_STACK_OVERFLOWED_P(cfp, sp, margin))) {(void)0;} else /* overflowed */
#define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin) \
    WHEN_VM_STACK_OVERFLOWED(cfp, sp, margin) vm_stackoverflow()
#define CHECK_VM_STACK_OVERFLOW(cfp, margin) \
    WHEN_VM_STACK_OVERFLOWED(cfp, (cfp)->sp, margin) vm_stackoverflow()

/* for thread */

#if RUBY_VM_THREAD_MODEL == 2
extern rb_thread_t *ruby_current_thread;
extern rb_vm_t *ruby_current_vm;
extern rb_event_flag_t ruby_vm_event_flags;

#define GET_VM() ruby_current_vm

#ifndef OPT_CALL_CFUNC_WITHOUT_FRAME
#define OPT_CALL_CFUNC_WITHOUT_FRAME 0
#endif

static inline rb_thread_t *
GET_THREAD(void)
{
    rb_thread_t *th = ruby_current_thread;
#if OPT_CALL_CFUNC_WITHOUT_FRAME
    if (UNLIKELY(th->passed_ci != 0)) {
	void vm_call_cfunc_push_frame(rb_thread_t *th);
	vm_call_cfunc_push_frame(th);
    }
#endif
    return th;
}

#define rb_thread_set_current_raw(th) (void)(ruby_current_thread = (th))
#define rb_thread_set_current(th) do { \
    if ((th)->vm->running_thread != (th)) { \
	(th)->running_time_us = 0; \
    } \
    rb_thread_set_current_raw(th); \
    (th)->vm->running_thread = (th); \
} while (0)

#else
#error "unsupported thread model"
#endif

enum {
    TIMER_INTERRUPT_MASK         = 0x01,
    PENDING_INTERRUPT_MASK       = 0x02,
    POSTPONED_JOB_INTERRUPT_MASK = 0x04,
    TRAP_INTERRUPT_MASK	         = 0x08
};

#define RUBY_VM_SET_TIMER_INTERRUPT(th)		ATOMIC_OR((th)->interrupt_flag, TIMER_INTERRUPT_MASK)
#define RUBY_VM_SET_INTERRUPT(th)		ATOMIC_OR((th)->interrupt_flag, PENDING_INTERRUPT_MASK)
#define RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(th)	ATOMIC_OR((th)->interrupt_flag, POSTPONED_JOB_INTERRUPT_MASK)
#define RUBY_VM_SET_TRAP_INTERRUPT(th)		ATOMIC_OR((th)->interrupt_flag, TRAP_INTERRUPT_MASK)
#define RUBY_VM_INTERRUPTED(th) ((th)->interrupt_flag & ~(th)->interrupt_mask & (PENDING_INTERRUPT_MASK|TRAP_INTERRUPT_MASK))
#define RUBY_VM_INTERRUPTED_ANY(th) ((th)->interrupt_flag & ~(th)->interrupt_mask)

int rb_signal_buff_size(void);
void rb_signal_exec(rb_thread_t *th, int sig);
void rb_threadptr_check_signal(rb_thread_t *mth);
void rb_threadptr_signal_raise(rb_thread_t *th, int sig);
void rb_threadptr_signal_exit(rb_thread_t *th);
void rb_threadptr_execute_interrupts(rb_thread_t *, int);
void rb_threadptr_interrupt(rb_thread_t *th);
void rb_threadptr_unlock_all_locking_mutexes(rb_thread_t *th);
void rb_threadptr_pending_interrupt_clear(rb_thread_t *th);
void rb_threadptr_pending_interrupt_enque(rb_thread_t *th, VALUE v);
int rb_threadptr_pending_interrupt_active_p(rb_thread_t *th);

#define RUBY_VM_CHECK_INTS_BLOCKING(th) do {				\
	if (UNLIKELY(!rb_threadptr_pending_interrupt_empty_p(th))) {	\
	    th->pending_interrupt_queue_checked = 0;			\
	    RUBY_VM_SET_INTERRUPT(th);					\
	    rb_threadptr_execute_interrupts(th, 1);			\
	}								\
	else if (UNLIKELY(RUBY_VM_INTERRUPTED_ANY(th))) {		\
	    rb_threadptr_execute_interrupts(th, 1);			\
	}								\
    } while (0)

#define RUBY_VM_CHECK_INTS(th) do { \
    if (UNLIKELY(RUBY_VM_INTERRUPTED_ANY(th))) {	\
	rb_threadptr_execute_interrupts(th, 0); \
    } \
} while (0)

/* tracer */
struct rb_trace_arg_struct {
    rb_event_flag_t event;
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    VALUE self;
    ID id;
    VALUE klass;
    VALUE data;

    int klass_solved;

    /* calc from cfp */
    int lineno;
    VALUE path;
};

void rb_threadptr_exec_event_hooks(struct rb_trace_arg_struct *trace_arg);
void rb_threadptr_exec_event_hooks_and_pop_frame(struct rb_trace_arg_struct *trace_arg);

#define EXEC_EVENT_HOOK_ORIG(th_, flag_, self_, id_, klass_, data_, pop_p_) do { \
    if (UNLIKELY(ruby_vm_event_flags & (flag_))) { \
	if (((th)->event_hooks.events | (th)->vm->event_hooks.events) & (flag_)) { \
	    struct rb_trace_arg_struct trace_arg; \
	    trace_arg.event = (flag_); \
	    trace_arg.th = (th_); \
	    trace_arg.cfp = (trace_arg.th)->cfp; \
	    trace_arg.self = (self_); \
	    trace_arg.id = (id_); \
	    trace_arg.klass = (klass_); \
	    trace_arg.data = (data_); \
	    trace_arg.path = Qundef; \
	    trace_arg.klass_solved = 0; \
	    if (pop_p_) rb_threadptr_exec_event_hooks_and_pop_frame(&trace_arg); \
	    else rb_threadptr_exec_event_hooks(&trace_arg); \
	} \
    } \
} while (0)

#define EXEC_EVENT_HOOK(th_, flag_, self_, id_, klass_, data_) \
  EXEC_EVENT_HOOK_ORIG(th_, flag_, self_, id_, klass_, data_, 0)

#define EXEC_EVENT_HOOK_AND_POP_FRAME(th_, flag_, self_, id_, klass_, data_) \
  EXEC_EVENT_HOOK_ORIG(th_, flag_, self_, id_, klass_, data_, 1)

RUBY_SYMBOL_EXPORT_BEGIN

int rb_thread_check_trap_pending(void);

extern VALUE rb_get_coverages(void);
extern void rb_set_coverages(VALUE);
extern void rb_reset_coverages(void);

void rb_postponed_job_flush(rb_vm_t *vm);

RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_VM_CORE_H */
