/**********************************************************************

  mjit.h - Interface to MRI method JIT compiler

  Copyright (C) 2017 Vladimir Makarov <vmakarov@redhat.com>.

**********************************************************************/

#ifndef RUBY_MJIT_H
#define RUBY_MJIT_H 1

#include "ruby.h"

/* Special address values of a function generated from the
   corresponding iseq by MJIT: */
enum rb_mjit_iseq_func {
    /* ISEQ was not queued yet for the machine code generation */
    NOT_ADDED_JIT_ISEQ_FUNC = 0,
    /* ISEQ is already queued for the machine code generation but the
       code is not ready yet for the execution */
    NOT_READY_JIT_ISEQ_FUNC = 1,
    /* ISEQ included not compilable insn or some assertion failed  */
    NOT_COMPILABLE_JIT_ISEQ_FUNC = 2,
    /* End mark */
    LAST_JIT_ISEQ_FUNC = 3,
};

/* C compiler used to generate native code. */
enum rb_mjit_cc {
    /* Not selected */
    MJIT_CC_DEFAULT = 0,
    /* GNU Compiler Collection */
    MJIT_CC_GCC = 1,
    /* LLVM/Clang */
    MJIT_CC_CLANG = 2,
};

/* MJIT options which can be defined on the MRI command line.  */
struct mjit_options {
    char on; /* flag of MJIT usage  */
    /* Default: clang for macOS, cl for Windows, gcc for others. */
    enum rb_mjit_cc cc;
    /* Save temporary files after MRI finish.  The temporary files
       include the pre-compiled header, C code file generated for ISEQ,
       and the corresponding object file.  */
    char save_temps;
    /* Print MJIT warnings to stderr.  */
    char warnings;
    /* Disable compiler optimization and add debug symbols. It can be
       very slow.  */
    char debug;
    /* If not 0, all ISeqs are compiled after `aot` calls. For testing. */
    unsigned int aot;
    /* Force printing info about MJIT work of level VERBOSE or
       less. 0=silence, 1=medium, 2=verbose.  */
    int verbose;
    /* Maximal permitted number of iseq JIT codes in a MJIT memory
       cache.  */
    int max_cache_size;
};

typedef VALUE (*mjit_func_t)(rb_execution_context_t *, rb_control_frame_t *);

RUBY_SYMBOL_EXPORT_BEGIN
extern struct mjit_options mjit_opts;
extern int mjit_init_p;

extern void mjit_add_iseq_to_process(const rb_iseq_t *iseq);
extern mjit_func_t mjit_get_iseq_func(const struct rb_iseq_constant_body *body);
RUBY_SYMBOL_EXPORT_END

extern int mjit_compile(FILE *f, const struct rb_iseq_constant_body *body, const char *funcname);
extern void mjit_init(struct mjit_options *opts);
extern void mjit_finish(void);
extern void mjit_gc_start_hook(void);
extern void mjit_gc_finish_hook(void);
extern void mjit_free_iseq(const rb_iseq_t *iseq);
extern void mjit_mark(void);
extern struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec);
extern void mjit_cont_free(struct mjit_cont *cont);
extern void mjit_add_class_serial(rb_serial_t class_serial);
extern void mjit_remove_class_serial(rb_serial_t class_serial);
extern int mjit_valid_class_serial_p(rb_serial_t class_serial);

/* A threshold used to add iseq to JIT. */
#define NUM_CALLS_TO_ADD 5

/* A threshold used to reject long iseqs from JITting as such iseqs
   takes too much time to be compiled.  */
#define JIT_ISEQ_SIZE_THRESHOLD 1000

/* Return TRUE if given ISeq body should be compiled by MJIT */
static inline int
mjit_target_iseq_p(struct rb_iseq_constant_body *body)
{
    return (body->type == ISEQ_TYPE_METHOD || body->type == ISEQ_TYPE_BLOCK)
	&& body->iseq_size < JIT_ISEQ_SIZE_THRESHOLD;
}

/* Try to execute the current iseq in ec.  Use JIT code if it is ready.
   If it is not, add ISEQ to the compilation queue and return Qundef.  */
static inline VALUE
mjit_exec(rb_execution_context_t *ec)
{
    const rb_iseq_t *iseq;
    struct rb_iseq_constant_body *body;
    long unsigned total_calls;
    mjit_func_t func;

    if (!mjit_init_p)
	return Qundef;

    iseq = ec->cfp->iseq;
    body = iseq->body;
    total_calls = ++body->total_calls;

    func = body->jit_func;
    if (UNLIKELY(mjit_opts.aot == total_calls && mjit_target_iseq_p(body)
		 && (enum rb_mjit_iseq_func)func == NOT_ADDED_JIT_ISEQ_FUNC)) {
	mjit_add_iseq_to_process(iseq);
	func = mjit_get_iseq_func(body);
    }

    if (UNLIKELY((ptrdiff_t)func <= (ptrdiff_t)LAST_JIT_ISEQ_FUNC)) {
	switch ((enum rb_mjit_iseq_func)func) {
	  case NOT_ADDED_JIT_ISEQ_FUNC:
	    if (total_calls == NUM_CALLS_TO_ADD && mjit_target_iseq_p(body)) {
		mjit_add_iseq_to_process(iseq);
	    }
	    return Qundef;
	  case NOT_READY_JIT_ISEQ_FUNC:
	  case NOT_COMPILABLE_JIT_ISEQ_FUNC:
	    return Qundef;
	  default: /* to avoid warning with LAST_JIT_ISEQ_FUNC */
	    break;
	}
    }

    return func(ec, ec->cfp);
}

#endif /* RUBY_MJIT_H */
