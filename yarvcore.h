/**********************************************************************

  yarvcore.h - 

  $Author$
  $Date$
  created at: 04/01/01 19:41:38 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#ifndef _YARVCORE_H_INCLUDED_
#define _YARVCORE_H_INCLUDED_

#define YARV_THREAD_MODEL 2

#include <setjmp.h>

#if 0 && defined(HAVE_GETCONTEXT) && defined(HAVE_SETCONTEXT)
#include <ucontext.h>
#define USE_CONTEXT
#endif
#include "ruby.h"
#include "st.h"

#include "debug.h"
#include "vm_opts.h"

#if   defined(_WIN32) || defined(__CYGWIN__)
#include "thread_win32.h"
#elif defined(HAVE_PTHREAD_H)
#include "thread_pthread.h"
#else
#error "unsupported thread type"
#endif

#include <signal.h>

#ifndef NSIG
# ifdef DJGPP
#  define NSIG SIGMAX
# else
#  define NSIG (_SIGMAX + 1)      /* For QNX */
# endif
#endif

#define RUBY_NSIG NSIG

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

/* call threaded code */
#if    OPT_CALL_THREADED_CODE
#if    OPT_DIRECT_THREADED_CODE
#undef OPT_DIRECT_THREADED_CODE
#endif /* OPT_DIRECT_THREADED_CODE */
#if    OPT_STACK_CACHING
#undef OPT_STACK_CACHING
#endif /* OPT_STACK_CACHING */
#define YARV_AOT_COMPILED 1
#endif /* OPT_CALL_THREADED_CODE */

/* likely */
#if __GNUC__ >= 3
#define LIKELY(x)   (__builtin_expect((x), 1))
#define UNLIKELY(x) (__builtin_expect((x), 0))
#else /* __GNUC__ >= 3 */
#define LIKELY(x)   (x)
#define UNLIKELY(x) (x)
#endif /* __GNUC__ >= 3 */

#define YARVDEBUG 0
#define CPDEBUG   0
#define VMDEBUG   0
#define GCDEBUG   0




/* classes and modules */
extern VALUE cYarvVM;
extern VALUE cYarvThread;
extern VALUE rb_cISeq;
extern VALUE rb_cVM;

extern VALUE symIFUNC;
extern VALUE symCFUNC;

/* special id */
extern ID idPLUS;
extern ID idMINUS;
extern ID idMULT;
extern ID idDIV;
extern ID idMOD;
extern ID idLT;
extern ID idLTLT;
extern ID idLE;
extern ID idEq;
extern ID idEqq;
extern ID idBackquote;
extern ID idEqTilde;
extern ID idThrowState;
extern ID idAREF;
extern ID idASET;
extern ID idIntern;
extern ID idMethodMissing;
extern ID idLength;
extern ID idGets;
extern ID idSucc;
extern ID idEach;
extern ID idLambda;
extern ID idRangeEachLT;
extern ID idRangeEachLE;
extern ID idArrayEach;
extern ID idTimes;
extern ID idEnd;
extern ID idBitblt;
extern ID idAnswer;
extern ID idSvarPlaceholder;
extern ID idSend;
extern ID id__send__;
extern ID id__send;
extern ID idFuncall;
extern ID id__send_bang;


extern unsigned long yarvGlobalStateVersion;

struct insn_info_struct {
    unsigned short position;
    unsigned short line_no;
};

#define ISEQ_TYPE_TOP    INT2FIX(1)
#define ISEQ_TYPE_METHOD INT2FIX(2)
#define ISEQ_TYPE_BLOCK  INT2FIX(3)
#define ISEQ_TYPE_CLASS  INT2FIX(4)
#define ISEQ_TYPE_RESCUE INT2FIX(5)
#define ISEQ_TYPE_ENSURE INT2FIX(6)
#define ISEQ_TYPE_EVAL   INT2FIX(7)
#define ISEQ_TYPE_DEFINED_GUARD INT2FIX(8)

#define CATCH_TYPE_RESCUE INT2FIX(1)
#define CATCH_TYPE_ENSURE INT2FIX(2)
#define CATCH_TYPE_RETRY  INT2FIX(3)
#define CATCH_TYPE_BREAK  INT2FIX(4)
#define CATCH_TYPE_REDO   INT2FIX(5)
#define CATCH_TYPE_NEXT   INT2FIX(6)

struct catch_table_entry {
    VALUE type;
    VALUE iseq;
    unsigned long start;
    unsigned long end;
    unsigned long cont;
    unsigned long sp;
};

#define INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE (512)

struct iseq_compile_data_storage {
    struct iseq_compile_data_storage *next;
    unsigned long pos;
    unsigned long size;
    char *buff;
};

struct iseq_compile_data_ensure_node_stack;

typedef struct yarv_compile_option_struct {
    int inline_const_cache;
    int peephole_optimization;
    int specialized_instruction;
    int operands_unification;
    int instructions_unification;
    int stack_caching;
} yarv_compile_option_t;

struct iseq_compile_data {
    /* GC is needed */
    VALUE err_info;
    VALUE mark_ary;
    VALUE catch_table_ary;	/* Array */

    /* GC is not needed */
    struct iseq_label_data *start_label;
    struct iseq_label_data *end_label;
    struct iseq_label_data *redo_label;
    VALUE current_block;
    VALUE loopval_popped;	/* used by NODE_BREAK */
    VALUE ensure_node;
    VALUE for_iseq;
    struct iseq_compile_data_ensure_node_stack *ensure_node_stack;
    int cached_const;
    struct iseq_compile_data_storage *storage_head;
    struct iseq_compile_data_storage *storage_current;
    int last_line;
    const yarv_compile_option_t *option;
};

#define GetISeqPtr(obj, ptr) Data_Get_Struct(obj, yarv_iseq_t, ptr)

typedef struct yarv_iseq_profile_struct {
    VALUE count;
    VALUE time_self;
    VALUE time_cumu; /* cumulative */
} yarv_iseq_profile_t;

struct yarv_iseq_struct;

struct yarv_iseq_struct {
    /* instruction sequence type */
    VALUE type;

    VALUE self;
    VALUE name;			/* String: iseq name */
    VALUE *iseq;		/* iseq */
    VALUE *iseq_encoded;
    VALUE iseq_mark_ary;	/* Array: includes operands which should be GC marked */

    /* sequence size */
    unsigned long size;

    /* insn info, must be freed */
    struct insn_info_struct *insn_info_tbl;

    /* insn info size, this value shows also instruction count */
    unsigned int insn_info_size;

    /* file information where this sequence from */
    VALUE file_name;

    ID *local_tbl;		/* must free */
    int local_size;

    /* jit compiled or not */
    void *jit_compiled;
    void *iseq_orig;

  /**
   * argument information
   *
   *  def m(a1, a2, ..., aM, b1=(...), b2=(...), ..., bN=(...), *c, &d)
   * =>
   *
   *  argc          = M
   *  arg_rest      = M+N + 1 // if no rest arguments, rest is 0
   *  arg_opts      = N
   *  arg_opts_tbl  = [ (N entries) ]
   *  arg_block     = M+N + 1 (rest) + 1 (block)
   *  check:
   *    M <= num
   */

    int argc;
    int arg_simple;
    int arg_rest;
    int arg_block;
    int arg_opts;
    VALUE *arg_opt_tbl;

    /* for stack overflow check */
    int stack_max;

    /* klass/module nest information stack (cref) */
    NODE *cref_stack;
    VALUE klass;

    /* catch table */
    struct catch_table_entry *catch_table;
    int catch_table_size;

    /* for child iseq */
    struct yarv_iseq_struct *parent_iseq;
    struct yarv_iseq_struct *local_iseq;

    /* block inlining */
    NODE *node;
    void *special_block_builder;
    void *cached_special_block_builder;
    VALUE cached_special_block;

    /* misc */
    ID defined_method_id;	/* for define_method */
    yarv_iseq_profile_t profile;
    
    struct iseq_compile_data *compile_data;
};

typedef struct yarv_iseq_struct yarv_iseq_t;

#define GetVMPtr(obj, ptr) \
  Data_Get_Struct(obj, yarv_vm_t, ptr)

struct yarv_thread_struct;

typedef struct yarv_vm_struct {
    VALUE self;

    yarv_thread_lock_t global_interpreter_lock;

    struct yarv_thread_struct *main_thread;
    struct yarv_thread_struct *running_thread;

    st_table *living_threads;
    VALUE thgroup_default;

    int thread_abort_on_exception;
    int exit_code;
    unsigned long trace_flag;

    /* object management */
    VALUE mark_object_ary;

    int signal_buff[RUBY_NSIG];
    int bufferd_signal_size;
} yarv_vm_t;

typedef struct {
    VALUE *pc;			// cfp[0]
    VALUE *sp;			// cfp[1]
    VALUE *bp;			// cfp[2]
    yarv_iseq_t *iseq;		// cfp[3]
    VALUE magic;		// cfp[4]
    VALUE self;			// cfp[5] // block[0]
    VALUE *lfp;			// cfp[6] // block[1]
    VALUE *dfp;			// cfp[7] // block[2]
    yarv_iseq_t *block_iseq;	// cfp[8] // block[3]
    VALUE proc;			// cfp[9] // block[4]
    ID callee_id;               // cfp[10]
    ID method_id;               // cfp[11] saved in special case
    VALUE method_klass;         // cfp[12] saved in special case
    VALUE prof_time_self;       // cfp[13]
    VALUE prof_time_chld;       // cfp[14]
    VALUE dummy;                // cfp[15]
} yarv_control_frame_t;

typedef struct {
    VALUE self;			/* share with method frame if it's only block */
    VALUE *lfp;			/* share with method frame if it's only block */
    VALUE *dfp;			/* share with method frame if it's only block */
    yarv_iseq_t *iseq;
    VALUE proc;
} yarv_block_t;

#define GetThreadPtr(obj, ptr) \
  Data_Get_Struct(obj, yarv_thread_t, ptr)

enum yarv_thread_status {
    THREAD_TO_KILL,
    THREAD_RUNNABLE,
    THREAD_STOPPED,
    THREAD_KILLED,
};

#ifdef USE_CONTEXT
typedef struct {
    ucontext_t context;
    volatile int status;
} rb_jmpbuf_t[1];
#else
typedef jmp_buf rb_jmpbuf_t;
#endif

struct yarv_tag {
    rb_jmpbuf_t buf;
    VALUE tag;
    VALUE retval;
    struct yarv_tag *prev;
};

typedef void yarv_interrupt_function_t(struct yarv_thread_struct *);

#define YARV_VALUE_CACHE_SIZE 0x1000
#define USE_VALUE_CACHE 1

typedef struct yarv_thread_struct
{
    VALUE self;
    yarv_vm_t *vm;

    /* execution information */
    VALUE *stack;		/* must free, must mark */
    unsigned long stack_size;
    yarv_control_frame_t *cfp;
    int safe_level;
    int raised_flag;
    
    /* passing state */
    int state;

    /* for rb_iterate */
    yarv_block_t *passed_block;

    /* passed via parse.y, eval.c (rb_scope_setup_local_tbl) */
    ID *top_local_tbl;

    /* eval env */
    yarv_block_t *base_block;

    VALUE *local_lfp;
    VALUE local_svar;

    /* thread control */
    yarv_thread_id_t thread_id;
    enum yarv_thread_status status;
    int priority;

    native_thread_data_t native_thread_data;

    VALUE thgroup;
    VALUE value;

    VALUE errinfo;
    VALUE throwed_errinfo;
    int exec_signal;

    int interrupt_flag;
    yarv_interrupt_function_t *interrupt_function;
    yarv_thread_lock_t interrupt_lock;

    struct yarv_tag *tag;

    int parse_in_eval;

    /* storage */
    st_table *local_storage;
#if USE_VALUE_CACHE
    VALUE value_cache[YARV_VALUE_CACHE_SIZE + 1];
    VALUE *value_cache_ptr;
#endif

    struct yarv_thread_struct *join_list_next;
    struct yarv_thread_struct *join_list_head;

    VALUE first_proc;
    VALUE first_args;

    /* for GC */
    VALUE *machine_stack_start;
    VALUE *machine_stack_end;
    jmp_buf machine_regs;

    /* statistics data for profiler */
    VALUE stat_insn_usage;

    /* misc */
    int method_missing_reason;
    int abort_on_exception;
} yarv_thread_t;

/** node -> yarv instruction sequence object */
VALUE iseq_compile(VALUE self, NODE *node);

VALUE yarv_iseq_new(NODE *node, VALUE name, VALUE file,
		    VALUE parent, VALUE type);

VALUE yarv_iseq_new_with_bopt(NODE *node, VALUE name, VALUE file_name,
			      VALUE parent, VALUE type, VALUE bopt);

VALUE yarv_iseq_new_with_opt(NODE *node, VALUE name, VALUE file,
			     VALUE parent, VALUE type, 
			     const yarv_compile_option_t *opt);

/** disassemble instruction sequence */
VALUE iseq_disasm(VALUE self);
VALUE iseq_disasm_insn(VALUE str, VALUE *iseqval, int pos,
		       yarv_iseq_t *iseq, VALUE child);
char *node_name(int node);


/* each thread has this size stack : 2MB */
#define YARV_THREAD_STACK_SIZE (128 * 1024)


/* from ruby 1.9 variable.c */
struct global_entry {
    struct global_variable *var;
    ID id;
};

#define GetProcPtr(obj, ptr) \
  Data_Get_Struct(obj, yarv_proc_t, ptr)

typedef struct {
    yarv_block_t block;

    VALUE envval;		/* for GC mark */
    VALUE blockprocval;
    int safe_level;
    int is_lambda;

    NODE *special_cref_stack;
} yarv_proc_t;

#define GetEnvPtr(obj, ptr) \
  Data_Get_Struct(obj, yarv_env_t, ptr)

typedef struct {
    VALUE *env;
    int env_size;
    int local_size;
    VALUE prev_envval;		/* for GC mark */
    yarv_block_t block;
} yarv_env_t;

#define GetBindingPtr(obj, ptr) \
  Data_Get_Struct(obj, yarv_binding_t, ptr)

typedef struct {
    VALUE env;
    NODE *cref_stack;
} yarv_binding_t;


/* used by compile time and send insn */
#define VM_CALL_ARGS_SPLAT_BIT     (0x01 << 1)
#define VM_CALL_ARGS_BLOCKARG_BIT  (0x01 << 2)
#define VM_CALL_FCALL_BIT          (0x01 << 3)
#define VM_CALL_VCALL_BIT          (0x01 << 4)
#define VM_CALL_TAILCALL_BIT       (0x01 << 5)
#define VM_CALL_TAILRECURSION_BIT  (0x01 << 6)
#define VM_CALL_SUPER_BIT          (0x01 << 7)
#define VM_CALL_SEND_BIT           (0x01 << 8)

/* inline method cache */
#define NEW_INLINE_CACHE_ENTRY() NEW_WHILE(Qundef, 0, 0)
#define ic_klass  u1.value
#define ic_method u2.node
#define ic_value  u2.value
#define ic_vmstat u3.cnt
typedef NODE *IC;

typedef VALUE CDHASH;


#define GC_GUARDED_PTR(p)     ((VALUE)((VALUE)(p) | 0x01))
#define GC_GUARDED_PTR_REF(p) ((void *)(((VALUE)p) & ~0x03))
#define GC_GUARDED_PTR_P(p)   (((VALUE)p) & 0x01)

#define YARV_METHOD_NODE NODE_METHOD

#define YARV_PREVIOUS_CONTROL_FRAME(cfp) (cfp+1)
#define YARV_NEXT_CONTROL_FRAME(cfp) (cfp-1)
#define YARV_END_CONTROL_FRAME(th) \
  ((yarv_control_frame_t *)((th)->stack + (th)->stack_size))
#define YARV_VALID_CONTROL_FRAME_P(cfp, ecfp) \
  ((void *)(ecfp) > (void *)(cfp))
#define YARV_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp) \
  (!YARV_VALID_CONTROL_FRAME_P((cfp), YARV_END_CONTROL_FRAME(th)))

#define YARV_IFUNC_P(ptr)        (BUILTIN_TYPE(ptr) == T_NODE)
#define YARV_NORMAL_ISEQ_P(ptr) \
  (ptr && !YARV_IFUNC_P(ptr))

#define YARV_CLASS_SPECIAL_P(ptr) (((VALUE)(ptr)) & 0x02)
#define YARV_BLOCK_PTR_P(ptr) (!YARV_CLASS_SPECIAL_P(ptr) && GC_GUARDED_PTR_REF(ptr))

#define GET_BLOCK_PTR_IN_CFP(cfp) ((yarv_block_t *)(&(cfp)->self))
#define GET_CFP_FROM_BLOCK_PTR(b) \
  ((yarv_control_frame_t *)((VALUE *)(b) - 5))


/* defined? */
#define DEFINED_IVAR   INT2FIX(1)
#define DEFINED_GVAR   INT2FIX(2)
#define DEFINED_CVAR   INT2FIX(3)
#define DEFINED_CONST  INT2FIX(4)
#define DEFINED_METHOD INT2FIX(5)
#define DEFINED_YIELD  INT2FIX(6)
#define DEFINED_REF    INT2FIX(7)
#define DEFINED_ZSUPER INT2FIX(8)
#define DEFINED_FUNC   INT2FIX(9)

/* VM related object allocate functions */
/* TODO: should be static functions */
VALUE yarv_thread_alloc(VALUE klass);
VALUE yarv_env_alloc(void);
VALUE yarv_proc_alloc(void);

/* for debug */
extern void vm_stack_dump_raw(yarv_thread_t *, yarv_control_frame_t *);
#define SDR()     vm_stack_dump_raw(GET_THREAD(), GET_THREAD()->cfp)
#define SDR2(cfp) vm_stack_dump_raw(GET_THREAD(), (cfp))

/* for thread */

#include "yarv.h"

#define GVL_UNLOCK_BEGIN() do { \
  yarv_thread_t *_th_stored = GET_THREAD(); \
  yarv_save_machine_context(_th_stored); \
  native_mutex_unlock(&_th_stored->vm->global_interpreter_lock)

#define GVL_UNLOCK_END() \
  native_mutex_lock(&_th_stored->vm->global_interpreter_lock); \
  yarv_set_current_running_thread(_th_stored); \
} while(0)

NOINLINE(void yarv_set_stack_end(VALUE **stack_end_p));
NOINLINE(void yarv_save_machine_context(yarv_thread_t *));

extern int rb_thread_pending;

void yarv_thread_execute_interrupts(yarv_thread_t *);

#define YARV_CHECK_INTS_TH(th) do { \
  if(th->interrupt_flag){ \
    /* TODO: trap something event */ \
    yarv_thread_execute_interrupts(th); \
  } \
} while (0)

#define YARV_CHECK_INTS() \
  YARV_CHECK_INTS_TH(GET_THREAD())

#endif // _YARVCORE_H_INCLUDED_
