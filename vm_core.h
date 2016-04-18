/**********************************************************************

  vm_core.h -

  $Author$
  created at: 04/01/01 19:41:38 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_VM_CORE_H
#define RUBY_VM_CORE_H

/*
 * Enable check mode.
 *   1: enable local assertions.
 */
#ifndef VM_CHECK_MODE
#define VM_CHECK_MODE 0
#endif

/**
 * VM Debug Level
 *
 * debug level:
 *  0: no debug output
 *  1: show instruction name
 *  2: show stack frame when control stack frame is changed
 *  3: show stack status
 *  4: show register
 *  5:
 * 10: gc check
 */

#ifndef VMDEBUG
#define VMDEBUG 0
#endif

#if 0
#undef  VMDEBUG
#define VMDEBUG 3
#endif

#if VM_CHECK_MODE > 0
#define VM_ASSERT(expr) ( \
	LIKELY(expr) ? (void)0 : \
	rb_bug("%s:%d assertion violation - %s", __FILE__, __LINE__, #expr))
#else
#define VM_ASSERT(expr) ((void)0)
#endif

#define RUBY_VM_THREAD_MODEL 2

#include "ruby/ruby.h"
#include "ruby/st.h"

#include "node.h"
#include "vm_debug.h"
#include "vm_opts.h"
#include "id.h"
#include "method.h"
#include "ruby_atomic.h"
#include "ccan/list/list.h"

#include "ruby/thread_native.h"
#if   defined(_WIN32)
#include "thread_win32.h"
#elif defined(HAVE_PTHREAD_H)
#include "thread_pthread.h"
#endif

#ifndef ENABLE_VM_OBJSPACE
#ifdef _WIN32
/*
 * TODO: object space independent st_table.
 * socklist and conlist will be freed exit_handler(), after object
 * space destruction.
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

typedef unsigned long rb_num_t;

enum ruby_tag_type {
    RUBY_TAG_RETURN	= 0x1,
    RUBY_TAG_BREAK	= 0x2,
    RUBY_TAG_NEXT	= 0x3,
    RUBY_TAG_RETRY	= 0x4,
    RUBY_TAG_REDO	= 0x5,
    RUBY_TAG_RAISE	= 0x6,
    RUBY_TAG_THROW	= 0x7,
    RUBY_TAG_FATAL	= 0x8,
    RUBY_TAG_MASK	= 0xf
};
#define TAG_RETURN	RUBY_TAG_RETURN
#define TAG_BREAK	RUBY_TAG_BREAK
#define TAG_NEXT	RUBY_TAG_NEXT
#define TAG_RETRY	RUBY_TAG_RETRY
#define TAG_REDO	RUBY_TAG_REDO
#define TAG_RAISE	RUBY_TAG_RAISE
#define TAG_THROW	RUBY_TAG_THROW
#define TAG_FATAL	RUBY_TAG_FATAL
#define TAG_MASK	RUBY_TAG_MASK

enum ruby_vm_throw_flags {
    VM_THROW_NO_ESCAPE_FLAG = 0x8000,
    VM_THROW_LEVEL_SHIFT = 16,
    VM_THROW_STATE_MASK = 0xff
};

/* forward declarations */
struct rb_thread_struct;
struct rb_control_frame_struct;

/* iseq data type */
typedef struct rb_compile_option_struct rb_compile_option_t;

struct iseq_inline_cache_entry {
    rb_serial_t ic_serial;
    const rb_cref_t *ic_cref;
    union {
	size_t index;
	VALUE value;
    } ic_value;
};

union iseq_inline_storage_entry {
    struct {
	struct rb_thread_struct *running_thread;
	VALUE value;
    } once;
    struct iseq_inline_cache_entry cache;
};

enum method_missing_reason {
    MISSING_NOENTRY   = 0x00,
    MISSING_PRIVATE   = 0x01,
    MISSING_PROTECTED = 0x02,
    MISSING_VCALL     = 0x04,
    MISSING_SUPER     = 0x08,
    MISSING_MISSING   = 0x10,
    MISSING_NONE      = 0x20
};

struct rb_call_info {
    /* fixed at compile time */
    ID mid;
    unsigned int flag;
    int orig_argc;
};

struct rb_call_info_kw_arg {
    int keyword_len;
    VALUE keywords[1];
};

struct rb_call_info_with_kwarg {
    struct rb_call_info ci;
    struct rb_call_info_kw_arg *kw_arg;
};

struct rb_calling_info {
    struct rb_block_struct *blockptr;
    VALUE recv;
    int argc;
};

struct rb_call_cache;
typedef VALUE (*vm_call_handler)(struct rb_thread_struct *th, struct rb_control_frame_struct *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);

struct rb_call_cache {
    /* inline cache: keys */
    rb_serial_t method_state;
    rb_serial_t class_serial;

    /* inline cache: values */
    const rb_callable_method_entry_t *me;

    vm_call_handler call;

    union {
	unsigned int index; /* used by ivar */
	enum method_missing_reason method_missing_reason; /* used by method_missing */
	int inc_sp; /* used by cfunc */
    } aux;
};

#if 1
#define GetCoreDataFromValue(obj, type, ptr) do { \
    (ptr) = (type*)DATA_PTR(obj); \
} while (0)
#else
#define GetCoreDataFromValue(obj, type, ptr) Data_Get_Struct((obj), type, (ptr))
#endif

typedef struct rb_iseq_location_struct {
    VALUE path;
    VALUE absolute_path;
    VALUE base_label;
    VALUE label;
    VALUE first_lineno; /* TODO: may be unsigned short */
} rb_iseq_location_t;

struct rb_iseq_constant_body {
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

    unsigned int stack_max; /* for stack overflow check */
    /* sizeof(vars) + 1 */
    unsigned int local_size;

    unsigned int iseq_size;
    const VALUE *iseq_encoded; /* encoded iseq (insn addr and operands) */

    /**
     * parameter information
     *
     *  def m(a1, a2, ..., aM,                    # mandatory
     *        b1=(...), b2=(...), ..., bN=(...),  # optional
     *        *c,                                 # rest
     *        d1, d2, ..., dO,                    # post
     *        e1:(...), e2:(...), ..., eK:(...),  # keyword
     *        **f,                                # keyword_rest
     *        &g)                                 # block
     * =>
     *
     *  lead_num     = M
     *  opt_num      = N
     *  rest_start   = M+N
     *  post_start   = M+N+(*1)
     *  post_num     = O
     *  keyword_num  = K
     *  block_start  = M+N+(*1)+O+K
     *  keyword_bits = M+N+(*1)+O+K+(&1)
     *  size         = M+N+O+(*1)+K+(&1)+(**1) // parameter size.
     */

    struct {
	struct {
	    unsigned int has_lead   : 1;
	    unsigned int has_opt    : 1;
	    unsigned int has_rest   : 1;
	    unsigned int has_post   : 1;
	    unsigned int has_kw     : 1;
	    unsigned int has_kwrest : 1;
	    unsigned int has_block  : 1;

	    unsigned int ambiguous_param0 : 1; /* {|a|} */
	} flags;

	unsigned int size;

	int lead_num;
	int opt_num;
	int rest_start;
	int post_start;
	int post_num;
	int block_start;

	const VALUE *opt_table; /* (opt_num + 1) entries. */
	/* opt_num and opt_table:
	 *
	 * def foo o1=e1, o2=e2, ..., oN=eN
	 * #=>
	 *   # prologue code
	 *   A1: e1
	 *   A2: e2
	 *   ...
	 *   AN: eN
	 *   AL: body
	 * opt_num = N
	 * opt_table = [A1, A2, ..., AN, AL]
	 */

	const struct rb_iseq_param_keyword {
	    int num;
	    int required_num;
	    int bits_start;
	    int rest_start;
	    const ID *table;
	    const VALUE *default_values;
	} *keyword;
    } param;

    rb_iseq_location_t location;

    /* insn info, must be freed */
    const struct iseq_line_info_entry *line_info_table;

    const ID *local_table;		/* must free */

    /* catch table */
    const struct iseq_catch_table *catch_table;

    /* for child iseq */
    const struct rb_iseq_struct *parent_iseq;
    struct rb_iseq_struct *local_iseq; /* local_iseq->flip_cnt can be modified */

    union iseq_inline_storage_entry *is_entries;
    struct rb_call_info *ci_entries; /* struct rb_call_info ci_entries[ci_size];
				      * struct rb_call_info_with_kwarg cikw_entries[ci_kw_size];
				      * So that:
				      * struct rb_call_info_with_kwarg *cikw_entries = &body->ci_entries[ci_size];
				      */
    struct rb_call_cache *cc_entries; /* size is ci_size = ci_kw_size */

    VALUE mark_ary;     /* Array: includes operands which should be GC marked */

    unsigned int local_table_size;
    unsigned int is_size;
    unsigned int ci_size;
    unsigned int ci_kw_size;
    unsigned int line_info_size;
};

/* T_IMEMO/iseq */
/* typedef rb_iseq_t is in method.h */
struct rb_iseq_struct {
    VALUE flags;
    VALUE reserved1;
    struct rb_iseq_constant_body *body;

    union { /* 4, 5 words */
	struct iseq_compile_data *compile_data; /* used at compile time */

	struct {
	    VALUE obj;
	    int index;
	} loader;
    } aux;
};

#ifndef USE_LAZY_LOAD
#define USE_LAZY_LOAD 0
#endif

#if USE_LAZY_LOAD
const rb_iseq_t *rb_iseq_complete(const rb_iseq_t *iseq);
#endif

static inline const rb_iseq_t *
rb_iseq_check(const rb_iseq_t *iseq)
{
#if USE_LAZY_LOAD
    if (iseq->body == NULL) {
	rb_iseq_complete((rb_iseq_t *)iseq);
    }
#endif
    return iseq;
}

enum ruby_special_exceptions {
    ruby_error_reenter,
    ruby_error_nomemory,
    ruby_error_sysstack,
    ruby_error_closed_stream,
    ruby_special_error_count
};

enum ruby_basic_operators {
    BOP_PLUS,
    BOP_MINUS,
    BOP_MULT,
    BOP_DIV,
    BOP_MOD,
    BOP_EQ,
    BOP_EQQ,
    BOP_LT,
    BOP_LE,
    BOP_LTLT,
    BOP_AREF,
    BOP_ASET,
    BOP_LENGTH,
    BOP_SIZE,
    BOP_EMPTY_P,
    BOP_SUCC,
    BOP_GT,
    BOP_GE,
    BOP_NOT,
    BOP_NEQ,
    BOP_MATCH,
    BOP_FREEZE,

    BOP_LAST_
};

#define GetVMPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_vm_t, (ptr))

struct rb_vm_struct;
typedef void rb_vm_at_exit_func(struct rb_vm_struct*);

typedef struct rb_at_exit_list {
    rb_vm_at_exit_func *func;
    struct rb_at_exit_list *next;
} rb_at_exit_list;

struct rb_objspace;
struct rb_objspace *rb_objspace_alloc(void);
void rb_objspace_free(struct rb_objspace *);

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

    struct list_head living_threads;
    size_t living_thread_num;
    VALUE thgroup_default;

    int running;
    int thread_abort_on_exception;
    int trace_running;
    volatile int sleeper;

    /* object management */
    VALUE mark_object_ary;
    const VALUE special_exceptions[ruby_special_error_count];

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

    VALUE defined_module_hash;

    struct rb_objspace *objspace;

    rb_at_exit_list *at_exit;

    VALUE *defined_strings;
    st_table *frozen_strings;

    /* params */
    struct { /* size in byte */
	size_t thread_vm_stack_size;
	size_t thread_machine_stack_size;
	size_t fiber_vm_stack_size;
	size_t fiber_machine_stack_size;
    } default_params;

    short redefined_flag[BOP_LAST_];
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

/* optimize insn */
#define FIXNUM_REDEFINED_OP_FLAG (1 << 0)
#define FLOAT_REDEFINED_OP_FLAG  (1 << 1)
#define STRING_REDEFINED_OP_FLAG (1 << 2)
#define ARRAY_REDEFINED_OP_FLAG  (1 << 3)
#define HASH_REDEFINED_OP_FLAG   (1 << 4)
#define BIGNUM_REDEFINED_OP_FLAG (1 << 5)
#define SYMBOL_REDEFINED_OP_FLAG (1 << 6)
#define TIME_REDEFINED_OP_FLAG   (1 << 7)
#define REGEXP_REDEFINED_OP_FLAG (1 << 8)
#define NIL_REDEFINED_OP_FLAG    (1 << 9)
#define TRUE_REDEFINED_OP_FLAG   (1 << 10)
#define FALSE_REDEFINED_OP_FLAG  (1 << 11)

#define BASIC_OP_UNREDEFINED_P(op, klass) (LIKELY((GET_VM()->redefined_flag[(op)]&(klass)) == 0))

#ifndef VM_DEBUG_BP_CHECK
#define VM_DEBUG_BP_CHECK 0
#endif

#ifndef VM_DEBUG_VERIFY_METHOD_CACHE
#define VM_DEBUG_VERIFY_METHOD_CACHE (VM_DEBUG_MODE != 0)
#endif

typedef struct rb_control_frame_struct {
    const VALUE *pc;		/* cfp[0] */
    VALUE *sp;			/* cfp[1] */
    const rb_iseq_t *iseq;	/* cfp[2] */
    VALUE flag;			/* cfp[3] */
    VALUE self;			/* cfp[4] / block[0] */
    VALUE *ep;			/* cfp[5] / block[1] */
    const rb_iseq_t *block_iseq;/* cfp[6] / block[2] */
    VALUE proc;			/* cfp[7] / block[3] */

#if VM_DEBUG_BP_CHECK
    VALUE *bp_check;		/* cfp[8] */
#endif
} rb_control_frame_t;

typedef struct rb_block_struct {
    VALUE self;			/* share with method frame if it's only block */
    VALUE *ep;			/* share with method frame if it's only block */
    const rb_iseq_t *iseq;
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

typedef char rb_thread_id_string_t[sizeof(rb_nativethread_id_t) * 2 + 3];

typedef struct rb_fiber_struct rb_fiber_t;

typedef struct rb_thread_struct {
    struct list_node vmlt_node;
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
    const rb_callable_method_entry_t *passed_bmethod_me;

    /* for cfunc */
    struct rb_calling_info *calling;

    /* for load(true) */
    VALUE top_self;
    VALUE top_wrapper;

    /* eval env */
    rb_block_t *base_block;

    VALUE *root_lep;
    VALUE root_svar;

    /* thread control */
    rb_nativethread_id_t thread_id;
#ifdef NON_SCALAR_THREAD_ID
    rb_thread_id_string_t thread_id_string;
#endif
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
    VALUE pending_interrupt_mask_stack;
    int pending_interrupt_queue_checked;

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
    VALUE local_storage_recursive_hash;
    VALUE local_storage_recursive_hash_for_trace;

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

    /* statistics data for profiler */
    VALUE stat_insn_usage;

    /* tracer */
    rb_hook_list_t event_hooks;
    struct rb_trace_arg_struct *trace_arg; /* trace information */

    /* fiber */
    rb_fiber_t *fiber;
    rb_fiber_t *root_fiber;
    rb_jmpbuf_t root_jmpbuf;

    /* ensure & callcc */
    rb_ensure_list_t *ensure_list;

    /* misc */
    enum method_missing_reason method_missing_reason;
    int abort_on_exception;
#ifdef USE_SIGALTSTACK
    void *altstack;
#endif
    unsigned long running_time_us;
    VALUE name;
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
rb_iseq_t *rb_iseq_new(NODE*, VALUE, VALUE, VALUE, const rb_iseq_t *parent, enum iseq_type);
rb_iseq_t *rb_iseq_new_top(NODE *node, VALUE name, VALUE path, VALUE absolute_path, const rb_iseq_t *parent);
rb_iseq_t *rb_iseq_new_main(NODE *node, VALUE path, VALUE absolute_path);
rb_iseq_t *rb_iseq_new_with_bopt(NODE*, VALUE, VALUE, VALUE, VALUE, VALUE, enum iseq_type, VALUE);
rb_iseq_t *rb_iseq_new_with_opt(NODE*, VALUE, VALUE, VALUE, VALUE, const rb_iseq_t *parent, enum iseq_type, const rb_compile_option_t*);

/* src -> iseq */
rb_iseq_t *rb_iseq_compile(VALUE src, VALUE file, VALUE line);
rb_iseq_t *rb_iseq_compile_on_base(VALUE src, VALUE file, VALUE line, rb_block_t *base_block);
rb_iseq_t *rb_iseq_compile_with_option(VALUE src, VALUE file, VALUE absolute_path, VALUE line, rb_block_t *base_block, VALUE opt);

VALUE rb_iseq_disasm(const rb_iseq_t *iseq);
int rb_iseq_disasm_insn(VALUE str, const VALUE *iseqval, size_t pos, const rb_iseq_t *iseq, VALUE child);
const char *ruby_node_name(int node);

VALUE rb_iseq_coverage(const rb_iseq_t *iseq);

RUBY_EXTERN VALUE rb_cISeq;
RUBY_EXTERN VALUE rb_cRubyVM;
RUBY_EXTERN VALUE rb_cEnv;
RUBY_EXTERN VALUE rb_mRubyVMFrozenCore;
RUBY_SYMBOL_EXPORT_END

#define GetProcPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_proc_t, (ptr))

typedef struct {
    rb_block_t block;
    int8_t safe_level;		/* 0..1 */
    int8_t is_from_method;	/* bool */
    int8_t is_lambda;		/* bool */
} rb_proc_t;

#define GetEnvPtr(obj, ptr) \
  GetCoreDataFromValue((obj), rb_env_t, (ptr))

typedef struct {
    int env_size;
    rb_block_t block;
    VALUE env[1];               /* flexible array */
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

#define VM_CALL_ARGS_SPLAT      (0x01 << 0) /* m(*args) */
#define VM_CALL_ARGS_BLOCKARG   (0x01 << 1) /* m(&block) */
#define VM_CALL_FCALL           (0x01 << 2) /* m(...) */
#define VM_CALL_VCALL           (0x01 << 3) /* m */
#define VM_CALL_ARGS_SIMPLE     (0x01 << 4) /* (ci->flag & (SPLAT|BLOCKARG)) && blockiseq == NULL && ci->kw_arg == NULL */
#define VM_CALL_BLOCKISEQ       (0x01 << 5) /* has blockiseq */
#define VM_CALL_KWARG           (0x01 << 6) /* has kwarg */
#define VM_CALL_TAILCALL        (0x01 << 7) /* located at tail position */
#define VM_CALL_SUPER           (0x01 << 8) /* super */
#define VM_CALL_OPT_SEND        (0x01 << 9) /* internal flag */

enum vm_special_object_type {
    VM_SPECIAL_OBJECT_VMCORE = 1,
    VM_SPECIAL_OBJECT_CBASE,
    VM_SPECIAL_OBJECT_CONST_BASE
};

enum vm_svar_index {
    VM_SVAR_LASTLINE = 0,      /* $_ */
    VM_SVAR_BACKREF = 1,       /* $~ */

    VM_SVAR_EXTRA_START = 2,
    VM_SVAR_FLIPFLOP_START = 2 /* flipflop */
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
#define VM_FRAME_MAGIC_RESCUE 0xb1
#define VM_FRAME_MAGIC_DUMMY  0xc1
#define VM_FRAME_MAGIC_MASK_BITS 8
#define VM_FRAME_MAGIC_MASK   (~(~(VALUE)0<<VM_FRAME_MAGIC_MASK_BITS))

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
typedef struct rb_call_info *CALL_INFO;
typedef struct rb_call_cache *CALL_CACHE;

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
rb_block_t *rb_vm_control_frame_block_ptr(const rb_control_frame_t *cfp);

#define RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp) ((cfp)+1)
#define RUBY_VM_NEXT_CONTROL_FRAME(cfp) ((cfp)-1)
#define RUBY_VM_END_CONTROL_FRAME(th) \
  ((rb_control_frame_t *)((th)->stack + (th)->stack_size))
#define RUBY_VM_VALID_CONTROL_FRAME_P(cfp, ecfp) \
  ((void *)(ecfp) > (void *)(cfp))
#define RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp) \
  (!RUBY_VM_VALID_CONTROL_FRAME_P((cfp), RUBY_VM_END_CONTROL_FRAME(th)))

#define RUBY_VM_IFUNC_P(ptr)        (RB_TYPE_P((VALUE)(ptr), T_IMEMO) && imemo_type((VALUE)ptr) == imemo_ifunc)
#define RUBY_VM_NORMAL_ISEQ_P(ptr)  (RB_TYPE_P((VALUE)(ptr), T_IMEMO) && imemo_type((VALUE)ptr) == imemo_iseq && rb_iseq_check((rb_iseq_t *)ptr))

#define RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp) ((rb_block_t *)(&(cfp)->self))
#define RUBY_VM_GET_CFP_FROM_BLOCK_PTR(b) \
  ((rb_control_frame_t *)((VALUE *)(b) - 4))
/* magic number `4' is depend on rb_control_frame_t layout. */

/* VM related object allocate functions */
VALUE rb_thread_alloc(VALUE klass);
VALUE rb_proc_alloc(VALUE klass);
VALUE rb_binding_alloc(VALUE klass);

/* for debug */
extern void rb_vmdebug_stack_dump_raw(rb_thread_t *, rb_control_frame_t *);
extern void rb_vmdebug_debug_print_pre(rb_thread_t *th, rb_control_frame_t *cfp, VALUE *_pc);
extern void rb_vmdebug_debug_print_post(rb_thread_t *th, rb_control_frame_t *cfp);

#define SDR() rb_vmdebug_stack_dump_raw(GET_THREAD(), GET_THREAD()->cfp)
#define SDR2(cfp) rb_vmdebug_stack_dump_raw(GET_THREAD(), (cfp))
void rb_vm_bugreport(const void *);
NORETURN(void rb_bug_context(const void *, const char *fmt, ...));

/* functions about thread/vm execution */
RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_iseq_eval(const rb_iseq_t *iseq);
VALUE rb_iseq_eval_main(const rb_iseq_t *iseq);
RUBY_SYMBOL_EXPORT_END
int rb_thread_method_id_and_class(rb_thread_t *th, ID *idp, VALUE *klassp);

VALUE rb_vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
			int argc, const VALUE *argv, const rb_block_t *blockptr);
VALUE rb_vm_make_proc_lambda(rb_thread_t *th, const rb_block_t *block, VALUE klass, int8_t is_lambda);
VALUE rb_vm_make_proc(rb_thread_t *th, const rb_block_t *block, VALUE klass);
VALUE rb_vm_make_binding(rb_thread_t *th, const rb_control_frame_t *src_cfp);
VALUE rb_vm_env_local_variables(const rb_env_t *env);
VALUE rb_vm_env_prev_envval(const rb_env_t *env);
VALUE rb_vm_proc_envval(const rb_proc_t *proc);
VALUE *rb_binding_add_dynavars(rb_binding_t *bind, int dyncount, const ID *dynvars);
void rb_vm_inc_const_missing_count(void);
void rb_vm_gvl_destroy(rb_vm_t *vm);
VALUE rb_vm_call(rb_thread_t *th, VALUE recv, VALUE id, int argc,
		 const VALUE *argv, const rb_callable_method_entry_t *me);

void rb_thread_start_timer_thread(void);
void rb_thread_stop_timer_thread(void);
void rb_thread_reset_timer_thread(void);
void rb_thread_wakeup_timer_thread(void);

static inline void
rb_vm_living_threads_init(rb_vm_t *vm)
{
    list_head_init(&vm->living_threads);
    vm->living_thread_num = 0;
}

static inline void
rb_vm_living_threads_insert(rb_vm_t *vm, rb_thread_t *th)
{
    list_add_tail(&vm->living_threads, &th->vmlt_node);
    vm->living_thread_num++;
}

static inline void
rb_vm_living_threads_remove(rb_vm_t *vm, rb_thread_t *th)
{
    list_del(&th->vmlt_node);
    vm->living_thread_num--;
}

typedef int rb_backtrace_iter_func(void *, VALUE, int, VALUE);
rb_control_frame_t *rb_vm_get_ruby_level_next_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp);
rb_control_frame_t *rb_vm_get_binding_creatable_next_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp);
int rb_vm_get_sourceline(const rb_control_frame_t *);
VALUE rb_name_err_mesg_new(VALUE mesg, VALUE recv, VALUE method);
void rb_vm_stack_to_heap(rb_thread_t *th);
void ruby_thread_init_stack(rb_thread_t *th);
int rb_vm_control_frame_id_and_class(const rb_control_frame_t *cfp, ID *idp, VALUE *klassp);
void rb_vm_rewind_cfp(rb_thread_t *th, rb_control_frame_t *cfp);

void rb_vm_register_special_exception(enum ruby_special_exceptions sp, VALUE exception_class, const char *mesg);

void rb_gc_mark_machine_stack(rb_thread_t *th);

int rb_autoloading_value(VALUE mod, ID id, VALUE* value);

void rb_vm_rewrite_cref(rb_cref_t *node, VALUE old_klass, VALUE new_klass, rb_cref_t **new_cref_ptr);

const rb_callable_method_entry_t *rb_vm_frame_method_entry(const rb_control_frame_t *cfp);

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

#define GET_THREAD() vm_thread_with_frame(ruby_current_thread)
#if OPT_CALL_CFUNC_WITHOUT_FRAME
static inline rb_thread_t *
vm_thread_with_frame(rb_thread_t *th)
{
    if (UNLIKELY(th->passed_ci != 0)) {
	void rb_vm_call_cfunc_push_frame(rb_thread_t *th);
	rb_vm_call_cfunc_push_frame(th);
    }
    return th;
}
#else
#define vm_thread_with_frame(th) (th)
#endif

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

#define RUBY_VM_CHECK_INTS(th) ruby_vm_check_ints(th)
static inline void
ruby_vm_check_ints(rb_thread_t *th)
{
    if (UNLIKELY(RUBY_VM_INTERRUPTED_ANY(th))) {
	rb_threadptr_execute_interrupts(th, 0);
    }
}

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
    const rb_event_flag_t flag_arg_ = (flag_); \
    if (UNLIKELY(ruby_vm_event_flags & (flag_arg_))) { \
	/* defer evaluating the other arguments */ \
	ruby_exec_event_hook_orig(th_, flag_arg_, self_, id_, klass_, data_, pop_p_); \
    } \
} while (0)

static inline void
ruby_exec_event_hook_orig(rb_thread_t *const th, const rb_event_flag_t flag,
			  VALUE self, ID id, VALUE klass, VALUE data, int pop_p)
{
    if ((th->event_hooks.events | th->vm->event_hooks.events) & flag) {
	struct rb_trace_arg_struct trace_arg;
	trace_arg.event = flag;
	trace_arg.th = th;
	trace_arg.cfp = th->cfp;
	trace_arg.self = self;
	trace_arg.id = id;
	trace_arg.klass = klass;
	trace_arg.data = data;
	trace_arg.path = Qundef;
	trace_arg.klass_solved = 0;
	if (pop_p) rb_threadptr_exec_event_hooks_and_pop_frame(&trace_arg);
	else rb_threadptr_exec_event_hooks(&trace_arg);
    }
}

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
