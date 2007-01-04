/**********************************************************************

  yarvcore.h - 

  $Author$
  $Date$
  created at: 04/01/01 01:17:22 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#include "ruby.h"
#include "node.h"

#include "yarvcore.h"
#include "yarv.h"
#include "gc.h"

VALUE mYarvCore;
VALUE cYarvISeq;
VALUE cYarvVM;
VALUE cYarvThread;
VALUE mYarvInsns;
VALUE cYarvEnv;
VALUE cYarvProc;
VALUE cYarvBinding;

VALUE symIFUNC;
VALUE symCFUNC;

ID idPLUS;
ID idMINUS;
ID idMULT;
ID idDIV;
ID idMOD;
ID idLT;
ID idLTLT;
ID idLE;
ID idEq;
ID idEqq;
ID idBackquote;
ID idEqTilde;
ID idThrowState;
ID idAREF;
ID idASET;
ID idIntern;
ID idMethodMissing;
ID idLength;
ID idLambda;
ID idGets;
ID idSucc;
ID idEach;
ID idRangeEachLT;
ID idRangeEachLE;
ID idArrayEach;
ID idTimes;
ID idEnd;
ID idBitblt;
ID idAnswer;
ID idSvarPlaceholder;

unsigned long yarvGlobalStateVersion = 1;


/* from Ruby 1.9 eval.c */
#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

VALUE yarv_th_eval(yarv_thread_t *th, VALUE iseqval);

/************/
/* YARVCore */
/************/

yarv_thread_t *yarvCurrentThread = 0;
yarv_vm_t *theYarvVM = 0;
static VALUE yarvVMArray = Qnil;

RUBY_EXTERN int rb_thread_critical;
RUBY_EXTERN int ruby_nerrs;
RUBY_EXTERN NODE *ruby_eval_tree;

VALUE
yarv_load(char *file)
{
    NODE *node;
    VALUE iseq;
    volatile int critical;
    yarv_thread_t *th = GET_THREAD();

    critical = rb_thread_critical;
    rb_thread_critical = Qtrue;
    {
	th->parse_in_eval++;
	node = (NODE *)rb_load_file(file);
	th->parse_in_eval--;
	node = ruby_eval_tree;
    }
    rb_thread_critical = critical;

    if (ruby_nerrs > 0) {
	return 0;
    }

    iseq = yarv_iseq_new(node, rb_str_new2("<top (required)>"),
			 rb_str_new2(file), Qfalse, ISEQ_TYPE_TOP);

    yarv_th_eval(GET_THREAD(), iseq);
    return 0;
}

VALUE *th_svar(yarv_thread_t *self, int cnt);

VALUE *
rb_svar(int cnt)
{
    return th_svar(GET_THREAD(), cnt);
}

VALUE
rb_backref_get(void)
{
    VALUE *var = rb_svar(1);
    if (var) {
	return *var;
    }
    return Qnil;
}

void
rb_backref_set(VALUE val)
{
    VALUE *var = rb_svar(1);
    *var = val;
}

VALUE
rb_lastline_get(void)
{
    VALUE *var = rb_svar(0);
    if (var) {
	return *var;
    }
    return Qnil;
}

void
rb_lastline_set(VALUE val)
{
    VALUE *var = rb_svar(0);
    *var = val;
}

static NODE *
compile_string(VALUE str, VALUE file, VALUE line)
{
    NODE *node;
    node = rb_compile_string(StringValueCStr(file), str, NUM2INT(line));

    if (ruby_nerrs > 0) {
	ruby_nerrs = 0;
	rb_exc_raise(GET_THREAD()->errinfo);	// TODO: check err
    }
    return node;
}

static VALUE
yarvcore_eval_iseq(VALUE iseq)
{
    return yarv_th_eval(GET_THREAD(), iseq);
}

static VALUE
th_compile_from_node(yarv_thread_t *th, NODE * node, VALUE file)
{
    VALUE iseq;
    if (th->base_block) {
	iseq = yarv_iseq_new(node,
			     th->base_block->iseq->name,
			     file,
			     th->base_block->iseq->self,
			     ISEQ_TYPE_EVAL);
    }
    else {
	iseq = yarv_iseq_new(node, rb_str_new2("<main>"), file,
			     Qfalse, ISEQ_TYPE_TOP);
    }
    return iseq;
}

VALUE
th_compile(yarv_thread_t *th, VALUE str, VALUE file, VALUE line)
{
    NODE *node = (NODE *) compile_string(str, file, line);
    return th_compile_from_node(th, (NODE *) node, file);
}

VALUE
yarvcore_eval_parsed(NODE *node, VALUE file)
{
    VALUE iseq = th_compile_from_node(GET_THREAD(), node, file);
    return yarvcore_eval_iseq(iseq);
}

VALUE
yarvcore_eval(VALUE self, VALUE str, VALUE file, VALUE line)
{
    NODE *node;
    node = compile_string(str, file, line);
    return yarvcore_eval_parsed(node, file);
}

/******/
/* VM */
/******/

void native_thread_cleanup(void *);

static void
vm_free(void *ptr)
{
    FREE_REPORT_ENTER("vm");
    if (ptr) {
	yarv_vm_t *vmobj = ptr;

	st_free_table(vmobj->living_threads);
	// TODO: MultiVM Instance
	// VM object should not be cleaned by GC
	// ruby_xfree(ptr);
	// theYarvVM = 0;
    }
    FREE_REPORT_LEAVE("vm");
}

static int
vm_mark_each_thread_func(st_data_t key, st_data_t value, st_data_t dummy)
{
    VALUE thval = (VALUE)key;
    rb_gc_mark(thval);
    return ST_CONTINUE;
}

static void
vm_mark(void *ptr)
{
    MARK_REPORT_ENTER("vm");
    GC_INFO("-------------------------------------------------\n");
    if (ptr) {
	yarv_vm_t *vm = ptr;
	if (vm->living_threads) {
	    st_foreach(vm->living_threads, vm_mark_each_thread_func, 0);
	}
	MARK_UNLESS_NULL(vm->thgroup_default);
	MARK_UNLESS_NULL(vm->mark_object_ary);
    }
    MARK_REPORT_LEAVE("vm");
}

static VALUE
vm_alloc(VALUE klass)
{
    VALUE volatile obj;
    yarv_vm_t *vm;
    obj = Data_Make_Struct(klass, yarv_vm_t, vm_mark, vm_free, vm);

    vm->self = obj;
    vm->mark_object_ary = rb_ary_new();
    return obj;
}

static void
vm_init2(yarv_vm_t *vm)
{
    MEMZERO(vm, yarv_vm_t, 1);
}


/**********/
/* Thread */
/**********/

static void
thread_free(void *ptr)
{
    yarv_thread_t *th;
    FREE_REPORT_ENTER("thread");

    if (ptr) {
	th = ptr;
	FREE_UNLESS_NULL(th->stack);
	FREE_UNLESS_NULL(th->top_local_tbl);

	if (th->local_storage) {
	    st_free_table(th->local_storage);
	}

#if USE_VALUE_CACHE
	{
	    VALUE *ptr = th->value_cache_ptr;
	    while (*ptr) {
		VALUE v = *ptr;
		RBASIC(v)->flags = 0;
		RBASIC(v)->klass = 0;
		ptr++;
	    }
	}
#endif

	if (th->vm->main_thread == th) {
	    GC_INFO("main thread\n");
	}
	else {
	    ruby_xfree(ptr);
	}
    }
    FREE_REPORT_LEAVE("thread");
}

void yarv_machine_stack_mark(yarv_thread_t *th);

static void
thread_mark(void *ptr)
{
    yarv_thread_t *th = NULL;
    MARK_REPORT_ENTER("thread");
    if (ptr) {
	th = ptr;
	if (th->stack) {
	    VALUE *p = th->stack;
	    VALUE *sp = th->cfp->sp;
	    yarv_control_frame_t *cfp = th->cfp;
	    yarv_control_frame_t *limit_cfp =
		(void *)(th->stack + th->stack_size);

	    while (p < sp) {
		rb_gc_mark(*p++);
	    }
	    while (cfp != limit_cfp) {
		rb_gc_mark(cfp->proc);
		cfp = YARV_PREVIOUS_CONTROL_FRAME(cfp);
	    }
	}

	/* mark ruby objects */
	MARK_UNLESS_NULL(th->first_proc);
	MARK_UNLESS_NULL(th->first_args);
	
	MARK_UNLESS_NULL(th->thgroup);
	MARK_UNLESS_NULL(th->value);
	MARK_UNLESS_NULL(th->errinfo);
	MARK_UNLESS_NULL(th->local_svar);

	rb_mark_tbl(th->local_storage);

	if (GET_THREAD() != th &&
	    th->machine_stack_start && th->machine_stack_end) {
	    yarv_machine_stack_mark(th);
	    rb_gc_mark_locations((VALUE *)&th->machine_regs,
				 (VALUE *)(&th->machine_regs) +
				 sizeof(th->machine_regs) / sizeof(VALUE));
	}
    }

    MARK_UNLESS_NULL(th->stat_insn_usage);
    MARK_REPORT_LEAVE("thread");
}

static VALUE
thread_alloc(VALUE klass)
{
    VALUE volatile obj;
    yarv_thread_t *th;
    obj = Data_Make_Struct(klass, yarv_thread_t,
			   thread_mark, thread_free, th);
    return obj;
}

static void
th_init2(yarv_thread_t *th)
{
    MEMZERO(th, yarv_thread_t, 1);

    /* allocate thread stack */
    th->stack = ALLOC_N(VALUE, YARV_THREAD_STACK_SIZE);

    th->stack_size = YARV_THREAD_STACK_SIZE;
    th->cfp = (void *)(th->stack + th->stack_size);
    th->cfp--;

    th->cfp->pc = 0;
    th->cfp->sp = th->stack;
    th->cfp->bp = 0;
    th->cfp->lfp = th->stack;
    th->cfp->dfp = th->stack;
    th->cfp->self = Qnil;
    th->cfp->magic = 0;
    th->cfp->iseq = 0;
    th->cfp->proc = 0;
    th->cfp->block_iseq = 0;
    
    th->status = THREAD_RUNNABLE;
    th->errinfo = Qnil;

#if USE_VALUE_CACHE
    th->value_cache_ptr = &th->value_cache[0];
#endif
}

void
th_klass_init(yarv_thread_t *th)
{
    /* */
}

static void
th_init(yarv_thread_t *th)
{
    th_init2(th);
    th_klass_init(th);
}

static VALUE
thread_init(VALUE self)
{
    yarv_thread_t *th;
    yarv_vm_t *vm = GET_THREAD()->vm;
    GetThreadPtr(self, th);

    th_init(th);
    th->self = self;
    th->vm = vm;
    return self;
}

VALUE
yarv_thread_alloc(VALUE klass)
{
    VALUE self = thread_alloc(klass);
    thread_init(self);
    return self;
}

VALUE th_eval_body(yarv_thread_t *th);
void th_set_top_stack(yarv_thread_t *, VALUE iseq);
VALUE rb_f_binding(VALUE);

VALUE
yarv_th_eval(yarv_thread_t *th, VALUE iseqval)
{
    VALUE val;
    volatile VALUE tmp;
    
    th_set_top_stack(th, iseqval);

    if (!rb_const_defined(rb_cObject, rb_intern("TOPLEVEL_BINDING"))) {
	rb_define_global_const("TOPLEVEL_BINDING", rb_f_binding(Qnil));
    }
    val = th_eval_body(th);
    tmp = iseqval; /* prohibit tail call optimization */
    return val;
}


/***************/
/* YarvEnv     */
/***************/

static void
env_free(void *ptr)
{
    yarv_env_t *env;
    FREE_REPORT_ENTER("env");
    if (ptr) {
	env = ptr;
	FREE_UNLESS_NULL(env->env);
	ruby_xfree(ptr);
    }
    FREE_REPORT_LEAVE("env");
}

static void
env_mark(void *ptr)
{
    yarv_env_t *env;
    MARK_REPORT_ENTER("env");
    if (ptr) {
	env = ptr;
	if (env->env) {
	    /* TODO: should mark more restricted range */
	    GC_INFO("env->env\n");
	    rb_gc_mark_locations(env->env, env->env + env->env_size);
	}
	GC_INFO("env->prev_envval\n");
	MARK_UNLESS_NULL(env->prev_envval);

	if (env->block.iseq) {
	    //printf("env->block.iseq <%p, %d>\n",
	    //       env->block.iseq, BUILTIN_TYPE(env->block.iseq));
	    if (BUILTIN_TYPE(env->block.iseq) == T_NODE) {
		MARK_UNLESS_NULL((VALUE)env->block.iseq);
	    }
	    else {
		MARK_UNLESS_NULL(env->block.iseq->self);
	    }
	}
    }
    MARK_REPORT_LEAVE("env");
}

VALUE
yarv_env_alloc(VALUE klass)
{
    VALUE obj;
    yarv_env_t *env;
    obj = Data_Make_Struct(klass, yarv_env_t, env_mark, env_free, env);
    env->env = 0;
    env->prev_envval = 0;
    env->block.iseq = 0;
    return obj;
}


/***************/
/* YarvProc    */
/***************/

static void
proc_free(void *ptr)
{
    FREE_REPORT_ENTER("proc");
    if (ptr) {
	ruby_xfree(ptr);
    }
    FREE_REPORT_LEAVE("proc");
}

static void
proc_mark(void *ptr)
{
    yarv_proc_t *proc;
    MARK_REPORT_ENTER("proc");
    if (ptr) {
	proc = ptr;
	MARK_UNLESS_NULL(proc->envval);
	MARK_UNLESS_NULL(proc->blockprocval);
	MARK_UNLESS_NULL((VALUE)proc->special_cref_stack);
	if (proc->block.iseq && YARV_IFUNC_P(proc->block.iseq)) {
	    MARK_UNLESS_NULL((VALUE)(proc->block.iseq));
	}
    }
    MARK_REPORT_LEAVE("proc");
}

static VALUE
proc_alloc(VALUE klass)
{
    VALUE obj;
    yarv_proc_t *proc;
    obj = Data_Make_Struct(klass, yarv_proc_t, proc_mark, proc_free, proc);
    MEMZERO(proc, yarv_proc_t, 1);
    return obj;
}

VALUE
yarv_proc_alloc(VALUE klass)
{
    return proc_alloc(cYarvProc);
}

static VALUE
proc_call(int argc, VALUE *argv, VALUE procval)
{
    yarv_proc_t *proc;
    GetProcPtr(procval, proc);
    return th_invoke_proc(GET_THREAD(), proc, proc->block.self, argc, argv);
}

static VALUE
proc_yield(int argc, VALUE *argv, VALUE procval)
{
    yarv_proc_t *proc;
    GetProcPtr(procval, proc);
    return th_invoke_proc(GET_THREAD(), proc, proc->block.self, argc, argv);
}

static VALUE
proc_to_proc(VALUE self)
{
    return self;
}

VALUE
yarv_obj_is_proc(VALUE proc)
{
    if (TYPE(proc) == T_DATA &&
	RDATA(proc)->dfree == (RUBY_DATA_FUNC) proc_free) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

static VALUE
proc_arity(VALUE self)
{
    yarv_proc_t *proc;
    yarv_iseq_t *iseq;
    GetProcPtr(self, proc);
    iseq = proc->block.iseq;
    if (iseq && BUILTIN_TYPE(iseq) != T_NODE) {
	if (iseq->arg_rest == 0 && iseq->arg_opts == 0) {
	    return INT2FIX(iseq->argc);
	}
	else {
	    return INT2FIX(-iseq->argc - 1);
	}
    }
    else {
	return INT2FIX(-1);
    }
}

int
rb_proc_arity(VALUE proc)
{
    return FIX2INT(proc_arity(proc));
}

static VALUE
proc_eq(VALUE self, VALUE other)
{
    if (self == other) {
	return Qtrue;
    }
    else {
	if (TYPE(other)          == T_DATA &&
	    RBASIC(other)->klass == cYarvProc &&
	    CLASS_OF(self)       == CLASS_OF(other)) {
	    yarv_proc_t *p1, *p2;
	    GetProcPtr(self, p1);
	    GetProcPtr(other, p2);
	    if (p1->block.iseq == p2->block.iseq && p1->envval == p2->envval) {
		return Qtrue;
	    }
	}
    }
    return Qfalse;
}

static VALUE
proc_hash(VALUE self)
{
    int hash;
    yarv_proc_t *proc;
    GetProcPtr(self, proc);
    hash = (long)proc->block.iseq;
    hash ^= (long)proc->envval;
    hash ^= (long)proc->block.lfp >> 16;
    return INT2FIX(hash);
}

static VALUE
proc_to_s(VALUE self)
{
    VALUE str = 0;
    yarv_proc_t *proc;
    char *cname = rb_obj_classname(self);
    yarv_iseq_t *iseq;
    
    GetProcPtr(self, proc);
    iseq = proc->block.iseq;

    if (YARV_NORMAL_ISEQ_P(iseq)) {
	int line_no = 0;
	
	if (iseq->insn_info_tbl) {
	    line_no = iseq->insn_info_tbl[0].line_no;
	}
	str = rb_sprintf("#<%s:%lx@%s:%d>", cname, self,
			 RSTRING_PTR(iseq->file_name),
			 line_no);
    }
    else {
	str = rb_sprintf("#<%s:%p>", cname, proc->block.iseq);
    }

    if (OBJ_TAINTED(self)) {
	OBJ_TAINT(str);
    }
    return str;
}

static VALUE
proc_dup(VALUE self)
{
    VALUE procval = proc_alloc(cYarvProc);
    yarv_proc_t *src, *dst;
    GetProcPtr(self, src);
    GetProcPtr(procval, dst);

    dst->block = src->block;
    dst->envval = src->envval;
    dst->safe_level = dst->safe_level;
    dst->special_cref_stack = src->special_cref_stack;
    
    return procval;
}

VALUE yarv_proc_dup(VALUE self)
{
    return proc_dup(self);
}
static VALUE
proc_clone(VALUE self)
{
    VALUE procval = proc_dup(self);
    CLONESETUP(procval, self);
    return procval;
}


/***************/
/* YarvBinding */
/***************/

static void
binding_free(void *ptr)
{
    yarv_binding_t *bind;
    FREE_REPORT_ENTER("binding");
    if (ptr) {
	bind = ptr;
	ruby_xfree(ptr);
    }
    FREE_REPORT_LEAVE("binding");
}

static void
binding_mark(void *ptr)
{
    yarv_binding_t *bind;
    MARK_REPORT_ENTER("binding");
    if (ptr) {
	bind = ptr;
	MARK_UNLESS_NULL(bind->env);
	MARK_UNLESS_NULL((VALUE)bind->cref_stack);
    }
    MARK_REPORT_LEAVE("binding");
}

static VALUE
binding_alloc(VALUE klass)
{
    VALUE obj;
    yarv_binding_t *bind;
    obj = Data_Make_Struct(klass, yarv_binding_t,
			   binding_mark, binding_free, bind);
    MEMZERO(bind, yarv_binding_t, 1);
    return obj;
}

VALUE
yarv_binding_alloc(VALUE klass)
{
    return binding_alloc(klass);
}

static VALUE
binding_dup(VALUE self)
{
    VALUE bindval = binding_alloc(cYarvBinding);
    yarv_binding_t *src, *dst;
    GetBindingPtr(self, src);
    GetBindingPtr(bindval, dst);
    dst->env = src->env;
    dst->cref_stack = src->cref_stack;
    return bindval;
}

static VALUE
binding_clone(VALUE self)
{
    VALUE bindval = binding_dup(self);
    CLONESETUP(bindval, self);
    return bindval;
}


/********************************************************************/

static VALUE
yarv_once()
{
    return rb_yield(Qnil);
}

static VALUE
yarv_segv()
{
    volatile int *a = 0;
    *a = 0;
    return Qnil;
}

static VALUE
cfunc(void)
{
    rb_funcall(Qnil, rb_intern("rfunc"), 0, 0);
    rb_funcall(Qnil, rb_intern("rfunc"), 0, 0);
    return Qnil;
}

// VALUE yarv_Hash_each();
VALUE insns_name_array(void);
VALUE Init_yarvthread(void);
extern VALUE *rb_gc_stack_start;

VALUE rb_proc_s_new(VALUE klass);

VALUE
sdr(void)
{
    yarv_bug();
    return Qnil;
}

static VALUE
nsdr(void)
{
    VALUE ary = rb_ary_new();
#if HAVE_BACKTRACE
#include <execinfo.h>
#define MAX_NATIVE_TRACE 1024
    static void *trace[MAX_NATIVE_TRACE];
    int n = backtrace(trace, MAX_NATIVE_TRACE);
    char **syms = backtrace_symbols(trace, n);
    int i;

    if (syms == 0) {
	rb_memerror();
    }

    for (i=0; i<n; i++) {
	rb_ary_push(ary, rb_str_new2(syms[i]));
    }
    free(syms);
#endif
    return ary;
}

char yarv_version[0x20];
char *yarv_options = ""
#if   OPT_DIRECT_THREADED_CODE
    "[direct threaded code] "
#elif OPT_TOKEN_THREADED_CODE
    "[token threaded code] "
#elif OPT_CALL_THREADED_CODE
    "[call threaded code] "
#endif

#if OPT_BASIC_OPERATIONS
    "[optimize basic operation] "
#endif
#if OPT_STACK_CACHING
    "[stack caching] "
#endif
#if OPT_OPERANDS_UNIFICATION
    "[operands unification] "
#endif
#if OPT_INSTRUCTIONS_UNIFICATION
    "[instructions unification] "
#endif
#if OPT_INLINE_METHOD_CACHE
    "[inline method cache] "
#endif
#if OPT_BLOCKINLINING
    "[block inlining] "
#endif
    ;

void Init_ISeq(void);

void
Init_yarvcore(void)
{
    /* declare YARVCore module */
    mYarvCore = rb_define_module("YARVCore");
    rb_define_const(mYarvCore, "OPTS", rb_str_new2(yarv_options));

    Init_ISeq();
    
    /* YARVCore::USAGE_ANALISYS_* */
    rb_define_const(mYarvCore, "USAGE_ANALISYS_INSN", rb_hash_new());
    rb_define_const(mYarvCore, "USAGE_ANALISYS_REGS", rb_hash_new());
    rb_define_const(mYarvCore, "USAGE_ANALISYS_INSN_BIGRAM", rb_hash_new());

    /* YARVCore::InsnNameArray */
    rb_define_const(mYarvCore, "InsnNameArray", insns_name_array());

    rb_define_singleton_method(mYarvCore, "eval", yarvcore_eval, 3);

    /* declare YARVCore::VM */
    cYarvVM = rb_define_class_under(mYarvCore, "VM", rb_cObject);
    rb_undef_alloc_func(cYarvVM);

    /* declare YARVCore::VM::Thread */
    cYarvThread = rb_define_class_under(cYarvVM, "Thread", rb_cObject);
    rb_define_global_const("Thread", cYarvThread);
    rb_undef_alloc_func(cYarvThread);
    rb_define_method(cYarvThread, "initialize", thread_init, 0);

    /* declare YARVCore::VM::Env */
    cYarvEnv = rb_define_class_under(cYarvVM, "Env", rb_cObject);
    rb_undef_alloc_func(cYarvEnv);

    /* declare YARVCore::VM::Proc */
    rb_cProc = cYarvProc = rb_define_class_under(cYarvVM, "Proc", rb_cObject);
    rb_const_set(rb_cObject, rb_intern("Proc"), cYarvProc);
    rb_undef_alloc_func(cYarvProc);
    rb_define_singleton_method(cYarvProc, "new", rb_proc_s_new, 0);
    rb_define_method(cYarvProc, "call", proc_call, -1);
    rb_define_method(cYarvProc, "[]", proc_call, -1);
    rb_define_method(cYarvProc, "yield", proc_yield, -1);
    rb_define_method(cYarvProc, "to_proc", proc_to_proc, 0);
    rb_define_method(cYarvProc, "arity", proc_arity, 0);
    rb_define_method(cYarvProc, "clone", proc_clone, 0);
    rb_define_method(cYarvProc, "dup", proc_dup, 0);
    rb_define_method(cYarvProc, "==", proc_eq, 1);
    rb_define_method(cYarvProc, "eql?", proc_eq, 1);
    rb_define_method(cYarvProc, "hash", proc_hash, 0);
    rb_define_method(cYarvProc, "to_s", proc_to_s, 0);

    /* declare YARVCore::VM::Binding */
    cYarvBinding = rb_define_class_under(cYarvVM, "Binding", rb_cObject);
    rb_const_set(rb_cObject, rb_intern("Binding"), cYarvBinding);
    rb_undef_alloc_func(cYarvBinding);
    rb_undef_method(CLASS_OF(cYarvBinding), "new");
    rb_define_method(cYarvBinding, "clone", binding_clone, 0);
    rb_define_method(cYarvBinding, "dup", binding_dup, 0);
    rb_define_global_function("binding", rb_f_binding, 0);

    /* misc */


    /* YARV test functions */

    rb_define_global_function("once", yarv_once, 0);
    rb_define_global_function("segv", yarv_segv, 0);
    rb_define_global_function("cfunc", cfunc, 0);
    rb_define_global_function("SDR", sdr, 0);
    rb_define_global_function("NSDR", nsdr, 0);

    symIFUNC = ID2SYM(rb_intern("<IFUNC>"));
    symCFUNC = ID2SYM(rb_intern("<CFUNC>"));

    /* for optimize */
    idPLUS = rb_intern("+");
    idMINUS = rb_intern("-");
    idMULT = rb_intern("*");
    idDIV = rb_intern("/");
    idMOD = rb_intern("%");
    idLT = rb_intern("<");
    idLTLT = rb_intern("<<");
    idLE = rb_intern("<=");
    idEq = rb_intern("==");
    idEqq = rb_intern("===");
    idBackquote = rb_intern("`");
    idEqTilde = rb_intern("=~");

    idAREF = rb_intern("[]");
    idASET = rb_intern("[]=");

    idEach = rb_intern("each");
    idTimes = rb_intern("times");
    idLength = rb_intern("length");
    idLambda = rb_intern("lambda");
    idIntern = rb_intern("intern");
    idGets = rb_intern("gets");
    idSucc = rb_intern("succ");
    idEnd = rb_intern("end");
    idRangeEachLT = rb_intern("Range#each#LT");
    idRangeEachLE = rb_intern("Range#each#LE");
    idArrayEach = rb_intern("Array#each");
    idMethodMissing = rb_intern("method_missing");

    idThrowState = rb_intern("#__ThrowState__");

    idBitblt = rb_intern("bitblt");
    idAnswer = rb_intern("the_answer_to_life_the_universe_and_everything");
    idSvarPlaceholder = rb_intern("#svar");

#if TEST_AOT_COMPILE
    Init_compiled();
#endif
    // make vm
    {
	/* create vm object */
	VALUE vmval = vm_alloc(cYarvVM);
	VALUE thval;

	yarv_vm_t *vm;
	yarv_thread_t *th;
	vm = theYarvVM;

	xfree(RDATA(vmval)->data);
	RDATA(vmval)->data = vm;
	vm->self = vmval;

	yarvVMArray = rb_ary_new();
	rb_register_mark_object(yarvVMArray);
	rb_ary_push(yarvVMArray, vm->self);

	/* create main thread */
	thval = yarv_thread_alloc(cYarvThread);
	GetThreadPtr(thval, th);

	vm->main_thread = th;
	vm->running_thread = th;
	GET_THREAD()->vm = vm;
	thread_free(GET_THREAD());
	th->vm = vm;
	yarv_set_current_running_thread(th);

	th->machine_stack_start = rb_gc_stack_start;
	vm->living_threads = st_init_numtable();
	st_insert(vm->living_threads, th->self, (st_data_t) th->thread_id);

	Init_yarvthread();
	th->thgroup = th->vm->thgroup_default;
    }
    yarv_init_redefined_flag();
}

static void
test(void)
{
    int i;
    int *p;
    printf("!test!\n");
    for (i = 0; i < 1000000; i++) {
	p = ALLOC(int);
    }
}

void
Init_yarv(void)
{
    /* initialize main thread */
    yarv_vm_t *vm = ALLOC(yarv_vm_t);
    yarv_thread_t *th = ALLOC(yarv_thread_t);

    vm_init2(vm);
    theYarvVM = vm;

    th_init2(th);
    th->vm = vm;
    th->machine_stack_start = rb_gc_stack_start;
    yarv_set_current_running_thread_raw(th);
}
