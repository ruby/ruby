/**********************************************************************

  eval.c -

  $Author$
  $Date$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "eval_intern.h"

VALUE rb_cProc;
VALUE rb_cBinding;

VALUE proc_invoke(VALUE, VALUE, VALUE, VALUE);
VALUE rb_binding_new();

VALUE rb_f_block_given_p(void);

ID rb_frame_callee(void);
static VALUE rb_frame_self(void);

NODE *ruby_current_node;

static ID removed, singleton_removed, undefined, singleton_undefined;
static ID init, eqq, each, aref, aset, match, missing;
static ID added, singleton_added;
static ID object_id, __send, __send_bang, respond_to;

VALUE rb_eLocalJumpError;
VALUE rb_eSysStackError;

extern int ruby_nerrs;
extern VALUE ruby_top_self;

static VALUE ruby_wrapper;	/* security wrapper */

static VALUE eval _((VALUE, VALUE, VALUE, char *, int));

static VALUE rb_yield_0 _((VALUE, VALUE, VALUE, int, int));
static VALUE rb_call(VALUE, VALUE, ID, int, const VALUE *, int);

static void rb_clear_trace_func(void);

typedef struct event_hook {
    rb_event_hook_func_t func;
    rb_event_t events;
    struct event_hook *next;
} rb_event_hook_t;

static rb_event_hook_t *event_hooks;

#define EXEC_EVENT_HOOK(event, node, self, id, klass) \
    do { \
	rb_event_hook_t *hook; \
	\
	for (hook = event_hooks; hook; hook = hook->next) { \
	    if (hook->events & event) \
		(*hook->func)(event, node, self, id, klass); \
	} \
    } while (0)

static void call_trace_func _((rb_event_t, NODE *, VALUE, ID, VALUE));


#include "eval_error.h"
#include "eval_method.h"
#include "eval_safe.h"
#include "eval_jump.h"


/* initialize ruby */

#if defined(__APPLE__)
#define environ (*_NSGetEnviron())
#elif !defined(_WIN32) && !defined(__MACOS__) || defined(_WIN32_WCE)
extern char **environ;
#endif
char **rb_origenviron;

jmp_buf function_call_may_return_twice_jmp_buf;
int function_call_may_return_twice_false = 0;

void rb_call_inits _((void));
void Init_stack _((VALUE *));
void Init_heap _((void));
void Init_ext _((void));
void Init_yarv(void);

void
ruby_init()
{
    static int initialized = 0;
    int state;

    if (initialized)
	return;
    initialized = 1;

#ifdef __MACOS__
    rb_origenviron = 0;
#else
    rb_origenviron = environ;
#endif

    Init_stack((void *)&state);
    Init_yarv();
    Init_heap();

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();

#ifdef __MACOS__
	_macruby_init();
#elif defined(__VMS)
	_vmsruby_init();
#endif

	ruby_prog_init();
	ALLOW_INTS;
    }
    POP_TAG_INIT();

    if (state) {
	error_print();
	exit(EXIT_FAILURE);
    }
    ruby_running = 1;
}

void
ruby_options(int argc, char **argv)
{
    int state;

    Init_stack((void *)&state);
    PUSH_THREAD_TAG();
    if ((state = EXEC_TAG()) == 0) {
	ruby_process_options(argc, argv);
    }
    else {
	rb_clear_trace_func();
	exit(error_handle(state));
    }
    POP_THREAD_TAG();
}

void rb_exec_end_proc _((void));

static void
ruby_finalize_0()
{
    PUSH_TAG(PROT_NONE);
    if (EXEC_TAG() == 0) {
	rb_trap_exit();
    }
    POP_TAG();
    rb_exec_end_proc();
}

static void
ruby_finalize_1()
{
    signal(SIGINT, SIG_DFL);
    GET_THREAD()->errinfo = 0;
    rb_gc_call_finalizer_at_exit();
    rb_clear_trace_func();
}

void
ruby_finalize(void)
{
    ruby_finalize_0();
    ruby_finalize_1();
}

int
ruby_cleanup(int ex)
{
    int state;
    volatile VALUE err = GET_THREAD()->errinfo;
    yarv_vm_t *vm = GET_THREAD()->vm;

    /* th->errinfo contains a NODE while break'ing */
    if (RTEST(err) && (TYPE(err) != T_NODE) &&
	rb_obj_is_kind_of(err, rb_eSystemExit)) {
	vm->exit_code = NUM2INT(rb_iv_get(err, "status"));
    }
    else {
	vm->exit_code = 0;
    }

    GET_THREAD()->safe_level = 0;
    Init_stack((void *)&state);
    PUSH_THREAD_TAG();
    if ((state = EXEC_TAG()) == 0) {
	if (GET_THREAD()->errinfo) {
	    err = GET_THREAD()->errinfo;
	}
	ruby_finalize_0();
    }
    else if (ex == 0) {
	ex = state;
    }
    rb_thread_terminate_all();
    GET_THREAD()->errinfo = err;
    ex = error_handle(ex);
    ruby_finalize_1();
    POP_THREAD_TAG();

    if (vm->exit_code) {
	return vm->exit_code;
    }
    return ex;
}

extern NODE *ruby_eval_tree;

static int
ruby_exec_internal()
{
    int state;
    VALUE val;
    PUSH_TAG(0);
    if ((state = EXEC_TAG()) == 0) {
	GET_THREAD()->base_block = 0;
	val = yarvcore_eval_parsed(ruby_eval_tree,
				   rb_str_new2(ruby_sourcefile));
    }
    POP_TAG();
    return state;
}

int
ruby_exec()
{
    volatile NODE *tmp;

    Init_stack((void *)&tmp);
    return ruby_exec_internal();
}

void
ruby_stop(ex)
    int ex;
{
    exit(ruby_cleanup(ex));
}

void
ruby_run()
{
    int state;
    static int ex;

    if (ruby_nerrs > 0) {
	exit(EXIT_FAILURE);
    }

    state = ruby_exec();

    if (state && !ex) {
	ex = state;
    }
    ruby_stop(ex);
}

VALUE
rb_eval_string(str)
    const char *str;
{
    VALUE v;
    NODE *oldsrc = ruby_current_node;

    ruby_current_node = 0;
    ruby_sourcefile = rb_source_filename("(eval)");
    v = eval(ruby_top_self, rb_str_new2(str), Qnil, 0, 0);
    ruby_current_node = oldsrc;

    return v;
}

VALUE
rb_eval_string_protect(str, state)
    const char *str;
    int *state;
{
    return rb_protect((VALUE (*)_((VALUE)))rb_eval_string, (VALUE)str, state);
}

VALUE
rb_eval_string_wrap(str, state)
    const char *str;
    int *state;
{
    int status;
    VALUE self = ruby_top_self;
    VALUE wrapper = ruby_wrapper;
    VALUE val;

    ruby_top_self = rb_obj_clone(ruby_top_self);
    rb_extend_object(ruby_top_self, ruby_wrapper);

    val = rb_eval_string_protect(str, &status);
    ruby_top_self = self;

    ruby_wrapper = wrapper;
    if (state) {
	*state = status;
    }
    else if (status) {
	JUMP_TAG(status);
    }
    return val;
}

VALUE
rb_eval_cmd(VALUE cmd, VALUE arg, int level)
{
    int state;
    VALUE val = Qnil;		/* OK */
    volatile int safe = rb_safe_level();

    if (OBJ_TAINTED(cmd)) {
	level = 4;
    }
    if (TYPE(cmd) != T_STRING) {

	PUSH_TAG(PROT_NONE);
	rb_set_safe_level_force(level);
	if ((state = EXEC_TAG()) == 0) {
	    val =
	      rb_funcall2(cmd, rb_intern("call"), RARRAY_LEN(arg),
			  RARRAY_PTR(arg));
	}
	POP_TAG();

	rb_set_safe_level_force(safe);

	if (state)
	  JUMP_TAG(state);
	return val;
    }

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = eval(ruby_top_self, cmd, Qnil, 0, 0);
    }
    POP_TAG();

    rb_set_safe_level_force(safe);
    th_jump_tag_but_local_jump(state, val);
    return val;
}

/*
 *  call-seq:
 *     Module.nesting    => array
 *  
 *  Returns the list of +Modules+ nested at the point of call.
 *     
 *     module M1
 *       module M2
 *         $a = Module.nesting
 *       end
 *     end
 *     $a           #=> [M1::M2, M1]
 *     $a[0].name   #=> "M1::M2"
 */

static VALUE
rb_mod_nesting(void)
{
    VALUE ary = rb_ary_new();
    NODE *cref = ruby_cref();

    while (cref && cref->nd_next) {
	VALUE klass = cref->nd_clss;
	if (!NIL_P(klass)) {
	    rb_ary_push(ary, klass);
	}
	cref = cref->nd_next;
    }
    return ary;
}

/*
 *  call-seq:
 *     Module.constants   => array
 *  
 *  Returns an array of the names of all constants defined in the
 *  system. This list includes the names of all modules and classes.
 *     
 *     p Module.constants.sort[1..5]
 *     
 *  <em>produces:</em>
 *     
 *     ["ARGV", "ArgumentError", "Array", "Bignum", "Binding"]
 */

static VALUE
rb_mod_s_constants(int argc, VALUE *argv, VALUE mod)
{
    NODE *cref = ruby_cref();
    VALUE klass;
    VALUE cbase = 0;
    void *data = 0;

    if (argc > 0) {
	return rb_mod_constants(argc, argv, rb_cModule);
    }

    while (cref) {
	klass = cref->nd_clss;
	if (!NIL_P(klass)) {
	    data = rb_mod_const_at(cref->nd_clss, data);
	    if (!cbase) {
		cbase = klass;
	    }
	}
	cref = cref->nd_next;
    }

    if (cbase) {
	data = rb_mod_const_of(cbase, data);
    }
    return rb_const_list(data);
}

void
rb_frozen_class_p(VALUE klass)
{
    char *desc = "something(?!)";

    if (OBJ_FROZEN(klass)) {
	if (FL_TEST(klass, FL_SINGLETON))
	    desc = "object";
	else {
	    switch (TYPE(klass)) {
	    case T_MODULE:
	    case T_ICLASS:
		desc = "module";
		break;
	    case T_CLASS:
		desc = "class";
		break;
	    }
	}
	rb_error_frozen(desc);
    }
}

#ifdef C_ALLOCA
# define TMP_PROTECT NODE * volatile tmp__protect_tmp=0
# define TMP_ALLOC(n)							\
    (tmp__protect_tmp = NEW_NODE(NODE_ALLOCA,				\
				 ALLOC_N(VALUE,n),tmp__protect_tmp,n),	\
     (void*)tmp__protect_tmp->nd_head)
#else
# define TMP_PROTECT typedef int foobazzz
# define TMP_ALLOC(n) ALLOCA_N(VALUE,n)
#endif

#define MATCH_DATA *rb_svar(node->nd_cnt)

static VALUE
rb_obj_is_proc(proc)
    VALUE proc;
{
    return yarv_obj_is_proc(proc);
}

void
rb_add_event_hook(func, events)
    rb_event_hook_func_t func;
    rb_event_t events;
{
    rb_event_hook_t *hook;

    hook = ALLOC(rb_event_hook_t);
    hook->func = func;
    hook->events = events;
    hook->next = event_hooks;
    event_hooks = hook;
}

int
rb_remove_event_hook(rb_event_hook_func_t func)
{
    rb_event_hook_t *prev, *hook;

    prev = NULL;
    hook = event_hooks;
    while (hook) {
	if (hook->func == func) {
	    if (prev) {
		prev->next = hook->next;
	    }
	    else {
		event_hooks = hook->next;
	    }
	    xfree(hook);
	    return 0;
	}
	prev = hook;
	hook = hook->next;
    }
    return -1;
}

static void
rb_clear_trace_func(void)
{
    // TODO: fix me
}

/*
 *  call-seq:
 *     set_trace_func(proc)    => proc
 *     set_trace_func(nil)     => nil
 *  
 *  Establishes _proc_ as the handler for tracing, or disables
 *  tracing if the parameter is +nil+. _proc_ takes up
 *  to six parameters: an event name, a filename, a line number, an
 *  object id, a binding, and the name of a class. _proc_ is
 *  invoked whenever an event occurs. Events are: <code>c-call</code>
 *  (call a C-language routine), <code>c-return</code> (return from a
 *  C-language routine), <code>call</code> (call a Ruby method),
 *  <code>class</code> (start a class or module definition),
 *  <code>end</code> (finish a class or module definition),
 *  <code>line</code> (execute code on a new line), <code>raise</code>
 *  (raise an exception), and <code>return</code> (return from a Ruby
 *  method). Tracing is disabled within the context of _proc_.
 *
 *      class Test
 *	def test
 *	  a = 1
 *	  b = 2
 *	end
 *      end
 *
 *      set_trace_func proc { |event, file, line, id, binding, classname|
 *	   printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
 *      }
 *      t = Test.new
 *      t.test
 *
 *	  line prog.rb:11               false
 *      c-call prog.rb:11        new    Class
 *      c-call prog.rb:11 initialize   Object
 *    c-return prog.rb:11 initialize   Object
 *    c-return prog.rb:11        new    Class
 *	  line prog.rb:12               false
 *  	  call prog.rb:2        test     Test
 *	  line prog.rb:3        test     Test
 *	  line prog.rb:4        test     Test
 *      return prog.rb:4        test     Test
 */


static VALUE
set_trace_func(VALUE obj, VALUE trace)
{
    rb_event_hook_t *hook;

    if (NIL_P(trace)) {
	rb_clear_trace_func();
	rb_remove_event_hook(call_trace_func);
	return Qnil;
    }
    if (!rb_obj_is_proc(trace)) {
	rb_raise(rb_eTypeError, "trace_func needs to be Proc");
    }

    // register trace func
    // trace_func = trace;

    for (hook = event_hooks; hook; hook = hook->next) {
	if (hook->func == call_trace_func)
	    return trace;
    }
    rb_add_event_hook(call_trace_func, RUBY_EVENT_ALL);
    return trace;
}

static char *
get_event_name(rb_event_t event)
{
    switch (event) {
    case RUBY_EVENT_LINE:
	return "line";
    case RUBY_EVENT_CLASS:
	return "class";
    case RUBY_EVENT_END:
	return "end";
    case RUBY_EVENT_CALL:
	return "call";
    case RUBY_EVENT_RETURN:
	return "return";
    case RUBY_EVENT_C_CALL:
	return "c-call";
    case RUBY_EVENT_C_RETURN:
	return "c-return";
    case RUBY_EVENT_RAISE:
	return "raise";
    default:
	return "unknown";
    }
}

static void
call_trace_func(rb_event_t event, NODE *node, VALUE self, ID id, VALUE klass)
{
    // TODO: fix me
#if 0
    int state, raised;
    NODE *node_save;
    VALUE srcfile;
    char *event_name;

    if (!trace_func)
	return;
    if (tracing)
	return;
    if (id == ID_ALLOCATOR)
	return;
    if (!node && ruby_sourceline == 0)
      return;

    if (!(node_save = ruby_current_node)) {
	node_save = NEW_BEGIN(0);
    }
    tracing = 1;

    if (node) {
	ruby_current_node = node;
	ruby_sourcefile = node->nd_file;
	ruby_sourceline = nd_line(node);
    }
    if (klass) {
	if (TYPE(klass) == T_ICLASS) {
	    klass = RBASIC(klass)->klass;
	}
	else if (FL_TEST(klass, FL_SINGLETON)) {
	    klass = self;
	}
    }
    PUSH_TAG(PROT_NONE);
    raised = thread_reset_raised(th);
    if ((state = EXEC_TAG()) == 0) {
	srcfile = rb_str_new2(ruby_sourcefile ? ruby_sourcefile : "(ruby)");
	event_name = get_event_name(event);
	proc_invoke(trace_func, rb_ary_new3(6, rb_str_new2(event_name),
					    srcfile,
					    INT2FIX(ruby_sourceline),
					    id ? ID2SYM(id) : Qnil,
					    self ? rb_binding_new() : Qnil,
					    klass ? klass : Qnil), Qundef, 0);
    }
    if (raised)
	thread_set_raised(th);
    POP_TAG();

    tracing = 0;
    ruby_current_node = node_save;
    SET_CURRENT_SOURCE();
    if (state)
	JUMP_TAG(state);
#endif
}


/*
 *  call-seq:
 *     obj.respond_to?(symbol, include_private=false) => true or false
 *  
 *  Returns +true+> if _obj_ responds to the given
 *  method. Private methods are included in the search only if the
 *  optional second parameter evaluates to +true+.
 */

static NODE *basic_respond_to = 0;

int
rb_obj_respond_to(VALUE obj, ID id, int priv)
{
    VALUE klass = CLASS_OF(obj);

    if (rb_method_node(klass, respond_to) == basic_respond_to) {
	return rb_method_boundp(klass, id, !priv);
    }
    else {
	VALUE args[2];
	int n = 0;
	args[n++] = ID2SYM(id);
	if (priv)
	    args[n++] = Qtrue;
	return rb_funcall2(obj, respond_to, n, args);
    }
}

int
rb_respond_to(VALUE obj, ID id)
{
    return rb_obj_respond_to(obj, id, Qfalse);
}

/*
 *  call-seq:
 *     obj.respond_to?(symbol, include_private=false) => true or false
 *  
 *  Returns +true+> if _obj_ responds to the given
 *  method. Private methods are included in the search only if the
 *  optional second parameter evaluates to +true+.
 */

static VALUE
obj_respond_to(int argc, VALUE *argv, VALUE obj)
{
    VALUE mid, priv;
    ID id;

    rb_scan_args(argc, argv, "11", &mid, &priv);
    id = rb_to_id(mid);
    if (rb_method_boundp(CLASS_OF(obj), id, !RTEST(priv))) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.method_defined?(symbol)    => true or false
 *  
 *  Returns +true+ if the named method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors). Public and protected methods are matched.
 *     
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *     
 *     A.method_defined? :method1    #=> true
 *     C.method_defined? "method1"   #=> true
 *     C.method_defined? "method2"   #=> true
 *     C.method_defined? "method3"   #=> true
 *     C.method_defined? "method4"   #=> false
 */

static VALUE
rb_mod_method_defined(mod, mid)
    VALUE mod, mid;
{
    return rb_method_boundp(mod, rb_to_id(mid), 1);
}

#define VISI_CHECK(x,f) (((x)&NOEX_MASK) == (f))

/*
 *  call-seq:
 *     mod.public_method_defined?(symbol)   => true or false
 *  
 *  Returns +true+ if the named public method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
 *     
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       protected
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *     
 *     A.method_defined? :method1           #=> true
 *     C.public_method_defined? "method1"   #=> true
 *     C.public_method_defined? "method2"   #=> false
 *     C.method_defined? "method2"          #=> true
 */

static VALUE
rb_mod_public_method_defined(VALUE mod, VALUE mid)
{
    ID id = rb_to_id(mid);
    NODE *method;

    method = rb_method_node(mod, id);
    if (method) {
	if (VISI_CHECK(method->nd_noex, NOEX_PUBLIC))
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.private_method_defined?(symbol)    => true or false
 *  
 *  Returns +true+ if the named private method is defined by
 *  _ mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
 *     
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       private
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *     
 *     A.method_defined? :method1            #=> true
 *     C.private_method_defined? "method1"   #=> false
 *     C.private_method_defined? "method2"   #=> true
 *     C.method_defined? "method2"           #=> false
 */

static VALUE
rb_mod_private_method_defined(VALUE mod, VALUE mid)
{
    ID id = rb_to_id(mid);
    NODE *method;

    method = rb_method_node(mod, id);
    if (method) {
	if (VISI_CHECK(method->nd_noex, NOEX_PRIVATE))
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.protected_method_defined?(symbol)   => true or false
 *  
 *  Returns +true+ if the named protected method is defined
 *  by _mod_ (or its included modules and, if _mod_ is a
 *  class, its ancestors).
 *     
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       protected
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *     
 *     A.method_defined? :method1              #=> true
 *     C.protected_method_defined? "method1"   #=> false
 *     C.protected_method_defined? "method2"   #=> true
 *     C.method_defined? "method2"             #=> true
 */

static VALUE
rb_mod_protected_method_defined(VALUE mod, VALUE mid)
{
    ID id = rb_to_id(mid);
    NODE *method;

    method = rb_method_node(mod, id);
    if (method) {
	if (VISI_CHECK(method->nd_noex, NOEX_PROTECTED))
	    return Qtrue;
    }
    return Qfalse;
}

NORETURN(void th_iter_break _((yarv_thread_t *)));

void
rb_iter_break()
{
    th_iter_break(GET_THREAD());
}

NORETURN(static void rb_longjmp _((int, VALUE)));
static VALUE make_backtrace _((void));

static void
rb_longjmp(tag, mesg)
    int tag;
    VALUE mesg;
{
    VALUE at;
    yarv_thread_t *th = GET_THREAD();

    //while (th->cfp->pc == 0 || th->cfp->iseq == 0) {
    //th->cfp++;
    //}

    if (thread_set_raised(th)) {
	th->errinfo = exception_error;
	JUMP_TAG(TAG_FATAL);
    }
    if (NIL_P(mesg))
      mesg = GET_THREAD()->errinfo;
    if (NIL_P(mesg)) {
	mesg = rb_exc_new(rb_eRuntimeError, 0, 0);
    }

    ruby_set_current_source();
    if (ruby_sourcefile && !NIL_P(mesg)) {
	at = get_backtrace(mesg);
	if (NIL_P(at)) {
	    at = make_backtrace();
	    set_backtrace(mesg, at);
	}
    }
    if (!NIL_P(mesg)) {
	GET_THREAD()->errinfo = mesg;
    }

    if (RTEST(ruby_debug) && !NIL_P(GET_THREAD()->errinfo)
	&& !rb_obj_is_kind_of(GET_THREAD()->errinfo, rb_eSystemExit)) {
	VALUE e = GET_THREAD()->errinfo;
	int status;

	PUSH_TAG(PROT_NONE);
	if ((status = EXEC_TAG()) == 0) {
	    e = rb_obj_as_string(e);
	    warn_printf("Exception `%s' at %s:%d - %s\n",
			rb_obj_classname(GET_THREAD()->errinfo),
			ruby_sourcefile, ruby_sourceline, RSTRING_PTR(e));
	}
	POP_TAG();
	if (status == TAG_FATAL && GET_THREAD()->errinfo == exception_error) {
	    GET_THREAD()->errinfo = mesg;
	}
	else if (status) {
	    thread_reset_raised(th);
	    JUMP_TAG(status);
	}
    }

    rb_trap_restore_mask();
    if (tag != TAG_FATAL) {
	// EXEC_EVENT_HOOK(RUBY_EVENT_RAISE ...)
    }
    thread_reset_raised(th);
    JUMP_TAG(tag);
}

void
rb_exc_raise(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_RAISE, mesg);
}

void
rb_exc_fatal(mesg)
    VALUE mesg;
{
    rb_longjmp(TAG_FATAL, mesg);
}

void
rb_interrupt()
{
    rb_raise(rb_eInterrupt, "");
}

/*
 *  call-seq:
 *     raise
 *     raise(string)
 *     raise(exception [, string [, array]])
 *     fail
 *     fail(string)
 *     fail(exception [, string [, array]])
 *  
 *  With no arguments, raises the exception in <code>$!</code> or raises
 *  a <code>RuntimeError</code> if <code>$!</code> is +nil+.
 *  With a single +String+ argument, raises a
 *  +RuntimeError+ with the string as a message. Otherwise,
 *  the first parameter should be the name of an +Exception+
 *  class (or an object that returns an +Exception+ object when sent
 *  an +exception+ message). The optional second parameter sets the
 *  message associated with the exception, and the third parameter is an
 *  array of callback information. Exceptions are caught by the
 *  +rescue+ clause of <code>begin...end</code> blocks.
 *     
 *     raise "Failed to create socket"
 *     raise ArgumentError, "No parameters", caller
 */

static VALUE get_errinfo(void);

static VALUE
rb_f_raise(int argc, VALUE *argv)
{
    VALUE err;
    if (argc == 0) {
	err = get_errinfo();
	if (!NIL_P(err)) {
	    argc = 1;
	    argv = &err;
	}
    }
    rb_raise_jump(rb_make_exception(argc, argv));
    return Qnil;		/* not reached */
}

VALUE
rb_make_exception(int argc, VALUE *argv)
{
    VALUE mesg;
    ID exception;
    int n;

    mesg = Qnil;
    switch (argc) {
    case 0:
	mesg = Qnil;
	break;
    case 1:
	if (NIL_P(argv[0]))
	    break;
	if (TYPE(argv[0]) == T_STRING) {
	    mesg = rb_exc_new3(rb_eRuntimeError, argv[0]);
	    break;
	}
	n = 0;
	goto exception_call;

    case 2:
    case 3:
	n = 1;
      exception_call:
	exception = rb_intern("exception");
	if (!rb_respond_to(argv[0], exception)) {
	    rb_raise(rb_eTypeError, "exception class/object expected");
	}
	mesg = rb_funcall(argv[0], exception, n, argv[1]);
	break;
    default:
	rb_raise(rb_eArgError, "wrong number of arguments");
	break;
    }
    if (argc > 0) {
	if (!rb_obj_is_kind_of(mesg, rb_eException))
	    rb_raise(rb_eTypeError, "exception object expected");
	if (argc > 2)
	    set_backtrace(mesg, argv[2]);
    }

    return mesg;
}

void
rb_raise_jump(mesg)
    VALUE mesg;
{
    // TODO: fix me
    rb_longjmp(TAG_RAISE, mesg);
}

void
rb_jump_tag(tag)
    int tag;
{
    JUMP_TAG(tag);
}

int
rb_block_given_p()
{
    yarv_thread_t *th = GET_THREAD();
    if (GC_GUARDED_PTR_REF(th->cfp->lfp[0])) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

int
rb_iterator_p()
{
    return rb_block_given_p();
}

/*
 *  call-seq:
 *     block_given?   => true or false
 *     iterator?      => true or false
 *  
 *  Returns <code>true</code> if <code>yield</code> would execute a
 *  block in the current context. The <code>iterator?</code> form
 *  is mildly deprecated.
 *     
 *     def try
 *       if block_given?
 *         yield
 *       else
 *         "no block"
 *       end
 *     end
 *     try                  #=> "no block"
 *     try { "hello" }      #=> "hello"
 *     try do "hello" end   #=> "hello"
 */


VALUE
rb_f_block_given_p()
{
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp = th->cfp;
    cfp = th_get_ruby_level_cfp(th, YARV_PREVIOUS_CONTROL_FRAME(cfp));
    if (GC_GUARDED_PTR_REF(cfp->lfp[0])) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

VALUE rb_eThreadError;

void
rb_need_block()
{
    if (!rb_block_given_p()) {
	th_localjump_error("no block given", Qnil, 0);
    }
}

static VALUE
rb_yield_0(VALUE val, VALUE self, VALUE klass /* OK */ , int flags,
	   int avalue)
{
    if (avalue) {
	return th_invoke_yield(GET_THREAD(),
			       RARRAY_LEN(val), RARRAY_PTR(val));
    }
    else {
	int argc = (val == Qundef) ? 0 : 1;
	VALUE *argv = &val;

	/* TODO:
	if (argc == 1 && CLASS_OF(argv[0]) == rb_cValues) {
	    argc = RARRAY_LEN(argv[0]);
	    argv = RARRAY_PTR(argv[0]);
	}
	  */
	return th_invoke_yield(GET_THREAD(), argc, argv);
    }
}


VALUE
rb_yield(VALUE val)
{
    return rb_yield_0(val, 0, 0, 0, Qfalse);
}

VALUE
rb_yield_values(int n, ...)
{
    int i;
    va_list args;
    VALUE val;

    if (n == 0) {
	return rb_yield_0(Qundef, 0, 0, 0, Qfalse);
    }
    val = rb_ary_new2(n);
    va_start(args, n);
    for (i=0; i<n; i++) {
	rb_ary_push(val, va_arg(args, VALUE));
    }
    va_end(args);
    return rb_yield_0(val, 0, 0, 0, Qtrue);
}

VALUE
rb_yield_splat(VALUE values)
{
    int avalue = Qfalse;

    if (TYPE(values) == T_ARRAY) {
	if (RARRAY_LEN(values) == 0) {
	    values = Qundef;
	}
	else {
	    avalue = Qtrue;
	}
    }
    return rb_yield_0(values, 0, 0, 0, avalue);
}

/*
 *  call-seq:
 *     loop {|| block }
 *  
 *  Repeatedly executes the block.
 *     
 *     loop do
 *       print "Input: "
 *       line = gets
 *       break if !line or line =~ /^qQ/
 *       # ...
 *     end
 */

static VALUE
rb_f_loop(void)
{
    for (;;) {
	rb_yield_0(Qundef, 0, 0, 0, Qfalse);
    }
    return Qnil;		/* dummy */
}

#define GET_THROWOBJ_CATCH_POINT(obj) ((VALUE*)RNODE((obj))->u2.value)

VALUE
rb_iterate(VALUE (*it_proc) (VALUE), VALUE data1,
	   VALUE (*bl_proc) (ANYARGS), VALUE data2)
{
    int state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_IFUNC(bl_proc, data2);
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp = th->cfp;

    TH_PUSH_TAG(th);
    state = TH_EXEC_TAG();
    if (state == 0) {
      iter_retry:
	{
	    yarv_block_t *blockptr = GET_BLOCK_PTR_IN_CFP(th->cfp);
	    blockptr->iseq = (void *)node;
	    blockptr->proc = 0;
	    th->passed_block = blockptr;
	}
	retval = (*it_proc) (data1);
    }
    else {
	VALUE err = th->errinfo;
	if (state == TAG_BREAK) {
	    VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cdfp = cfp->dfp;

	    if (cdfp == escape_dfp) {
		state = 0;
		th->state = 0;
		th->errinfo = Qnil;
		th->cfp = cfp;
	    }
	    else{
		// SDR(); printf("%p, %p\n", cdfp, escape_dfp);
	    }
	}
	else if (state == TAG_RETRY) {
	    VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cdfp = cfp->dfp;

	    if (cdfp == escape_dfp) {
		state = 0;
		th->state = 0;
		th->errinfo = Qnil;
		th->cfp = cfp;
		goto iter_retry;
	    }
	}
    }
    TH_POP_TAG();

    switch (state) {
      case 0:
	break;
      default:
	TH_JUMP_TAG(th, state);
    }
    return retval;
}

struct iter_method_arg {
    VALUE obj;
    ID mid;
    int argc;
    VALUE *argv;
};

static VALUE
iterate_method(VALUE obj)
{
    struct iter_method_arg *arg;

    arg = (struct iter_method_arg *)obj;
    return rb_call(CLASS_OF(arg->obj), arg->obj, arg->mid,
		   arg->argc, arg->argv, NOEX_PRIVATE);
}

VALUE
rb_block_call(VALUE obj, ID mid, int argc, VALUE *argv,
	      VALUE (*bl_proc) (ANYARGS), VALUE data2)
{
    struct iter_method_arg arg;

    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    return rb_iterate(iterate_method, (VALUE)&arg, bl_proc, data2);
}

VALUE
rb_each(VALUE obj)
{
    return rb_call(CLASS_OF(obj), obj, rb_intern("each"), 0, 0,
		   NOEX_PRIVATE);
}

VALUE
rb_rescue2(VALUE (*b_proc) (ANYARGS), VALUE data1, VALUE (*r_proc) (ANYARGS),
	   VALUE data2, ...)
{
    int state;
    volatile VALUE result;
    volatile VALUE e_info = GET_THREAD()->errinfo;
    va_list args;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
      retry_entry:
	result = (*b_proc) (data1);
    }
    else if (state == TAG_RAISE) {
	int handle = Qfalse;
	VALUE eclass;

	va_init_list(args, data2);
	while (eclass = va_arg(args, VALUE)) {
	    if (rb_obj_is_kind_of(GET_THREAD()->errinfo, eclass)) {
		handle = Qtrue;
		break;
	    }
	}
	va_end(args);

	if (handle) {
	    if (r_proc) {
		PUSH_TAG(PROT_NONE);
		if ((state = EXEC_TAG()) == 0) {
		    result = (*r_proc) (data2, GET_THREAD()->errinfo);
		}
		POP_TAG();
		if (state == TAG_RETRY) {
		    state = 0;
		    GET_THREAD()->errinfo = Qnil;
		    goto retry_entry;
		}
	    }
	    else {
		result = Qnil;
		state = 0;
	    }
	    if (state == 0) {
		GET_THREAD()->errinfo = e_info;
	    }
	}
    }
    POP_TAG();
    if (state)
	JUMP_TAG(state);

    return result;
}

VALUE
rb_rescue(b_proc, data1, r_proc, data2)
    VALUE (*b_proc) (), (*r_proc) ();
    VALUE data1, data2;
{
    return rb_rescue2(b_proc, data1, r_proc, data2, rb_eStandardError,
		      (VALUE)0);
}

VALUE
rb_protect(VALUE (*proc) (VALUE), VALUE data, int *state)
{
    VALUE result = Qnil;	/* OK */
    int status;

    PUSH_THREAD_TAG();
    if ((status = EXEC_TAG()) == 0) {
	result = (*proc) (data);
    }
    POP_THREAD_TAG();
    if (state) {
	*state = status;
    }
    if (status != 0) {
	return Qnil;
    }

    return result;
}

VALUE
rb_ensure(VALUE (*b_proc)(ANYARGS), VALUE data1, VALUE (*e_proc)(ANYARGS), VALUE data2)
{
    int state;
    volatile VALUE result = Qnil;

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	result = (*b_proc) (data1);
    }
    POP_TAG();
    // TODO: fix me
    // retval = prot_tag ? prot_tag->retval : Qnil;     /* save retval */
    (*e_proc) (data2);
    if (state)
	JUMP_TAG(state);
    return result;
}

VALUE
rb_with_disable_interrupt(proc, data)
    VALUE (*proc) ();
    VALUE data;
{
    VALUE result = Qnil;	/* OK */
    int status;

    DEFER_INTS;
    {
	int thr_critical = rb_thread_critical;

	rb_thread_critical = Qtrue;
	PUSH_TAG(PROT_NONE);
	if ((status = EXEC_TAG()) == 0) {
	    result = (*proc) (data);
	}
	POP_TAG();
	rb_thread_critical = thr_critical;
    }
    ENABLE_INTS;
    if (status)
	JUMP_TAG(status);

    return result;
}

static inline void
stack_check()
{
    static int overflowing = 0;

    if (!overflowing && ruby_stack_check()) {
	int state;
	overflowing = 1;
	PUSH_TAG(PROT_NONE);
	if ((state = EXEC_TAG()) == 0) {
	    rb_exc_raise(sysstack_error);
	}
	POP_TAG();
	overflowing = 0;
	JUMP_TAG(state);
    }
}

/*
 *  call-seq:
 *     obj.method_missing(symbol [, *args] )   => result
 *  
 *  Invoked by Ruby when <i>obj</i> is sent a message it cannot handle.
 *  <i>symbol</i> is the symbol for the method called, and <i>args</i>
 *  are any arguments that were passed to it. By default, the interpreter
 *  raises an error when this method is called. However, it is possible
 *  to override the method to provide more dynamic behavior.
 *  The example below creates
 *  a class <code>Roman</code>, which responds to methods with names
 *  consisting of roman numerals, returning the corresponding integer
 *  values.
 *     
 *     class Roman
 *       def romanToInt(str)
 *         # ...
 *       end
 *       def method_missing(methId)
 *         str = methId.id2name
 *         romanToInt(str)
 *       end
 *     end
 *     
 *     r = Roman.new
 *     r.iv      #=> 4
 *     r.xxiii   #=> 23
 *     r.mm      #=> 2000
 */

static VALUE
rb_method_missing(int argc, const VALUE *argv, VALUE obj)
{
    ID id;
    VALUE exc = rb_eNoMethodError;
    char *format = 0;
    NODE *cnode = ruby_current_node;
    yarv_thread_t *th = GET_THREAD();
    int last_call_status = th->method_missing_reason;
    if (argc == 0 || !SYMBOL_P(argv[0])) {
	rb_raise(rb_eArgError, "no id given");
    }

    stack_check();

    id = SYM2ID(argv[0]);

    if (last_call_status & NOEX_PRIVATE) {
	format = "private method `%s' called for %s";
    }
    else if (last_call_status & NOEX_PROTECTED) {
	format = "protected method `%s' called for %s";
    }
    else if (last_call_status & NOEX_VCALL) {
	format = "undefined local variable or method `%s' for %s";
	exc = rb_eNameError;
    }
    else if (last_call_status & NOEX_SUPER) {
	format = "super: no superclass method `%s'";
    }
    if (!format) {
	format = "undefined method `%s' for %s";
    }

    ruby_current_node = cnode;
    {
	int n = 0;
	VALUE args[3];
	args[n++] = rb_funcall(rb_const_get(exc, rb_intern("message")), '!',
			       3, rb_str_new2(format), obj, argv[0]);
	args[n++] = argv[0];
	if (exc == rb_eNoMethodError) {
	    args[n++] = rb_ary_new4(argc - 1, argv + 1);
	}
	exc = rb_class_new_instance(n, args, exc);
	rb_exc_raise(exc);
    }

    return Qnil;		/* not reached */
}

static VALUE
method_missing(VALUE obj, ID id, int argc, const VALUE *argv, int call_status)
{
    VALUE *nargv;
    GET_THREAD()->method_missing_reason = call_status;

    if (id == missing) {
	rb_method_missing(argc, argv, obj);
    }
    else if (id == ID_ALLOCATOR) {
	rb_raise(rb_eTypeError, "allocator undefined for %s",
		 rb_class2name(obj));
    }

    nargv = ALLOCA_N(VALUE, argc + 1);
    nargv[0] = ID2SYM(id);
    MEMCPY(nargv + 1, argv, VALUE, argc);

    return rb_funcall2(obj, missing, argc + 1, nargv);
}

static VALUE
rb_call(VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv, int scope)
{
    NODE *body, *method;
    int noex;
    ID id = mid;
    struct cache_entry *ent;

    if (!klass) {
	rb_raise(rb_eNotImpError,
		 "method `%s' called on terminated object (%p)",
		 rb_id2name(mid), (void *)recv);
    }
    /* is it in the method cache? */
    ent = cache + EXPR1(klass, mid);
    if (ent->mid == mid && ent->klass == klass) {
	if (!ent->method)
	    return method_missing(recv, mid, argc, argv,
				  scope == 2 ? NOEX_VCALL : 0);
	id = ent->mid0;
	noex = ent->method->nd_noex;
	klass = ent->method->nd_clss;
	body = ent->method->nd_body;
    }
    else if ((method = rb_get_method_body(klass, id, &id)) != 0) {
	noex = method->nd_noex;
	klass = method->nd_clss;
	body = method->nd_body;
    }
    else {
	if (scope == 3) {
	    return method_missing(recv, mid, argc, argv, NOEX_SUPER);
	}
	return method_missing(recv, mid, argc, argv,
			      scope == 2 ? NOEX_VCALL : 0);
    }
    if (mid != missing) {
	/* receiver specified form for private method */
	if (((noex & NOEX_MASK) & NOEX_PRIVATE) && scope == 0) {
	    return method_missing(recv, mid, argc, argv, NOEX_PRIVATE);
	}

	/* self must be kind of a specified form for protected method */
	if (((noex & NOEX_MASK) & NOEX_PROTECTED) && scope == 0) {
	    VALUE defined_class = klass;

	    if (TYPE(defined_class) == T_ICLASS) {
		defined_class = RBASIC(defined_class)->klass;
	    }

	    if (!rb_obj_is_kind_of(rb_frame_self(),
				   rb_class_real(defined_class))) {
		return method_missing(recv, mid, argc, argv, NOEX_PROTECTED);
	    }
	}
    }

    {
	VALUE val;
	//static int level;
	//int i;
	//for(i=0; i<level; i++){printf("  ");}
	//printf("invoke %s (%s)\n", rb_id2name(mid), node_name(nd_type(body)));
	//level++;
	//printf("%s with %d args\n", rb_id2name(mid), argc);
	val =
	    th_call0(GET_THREAD(), klass, recv, mid, id, argc, argv, body,
		     noex & NOEX_NOSUPER);
	//level--;
	//for(i=0; i<level; i++){printf("  ");}
	//printf("done %s (%s)\n", rb_id2name(mid), node_name(nd_type(body)));
	return val;
    }
}

VALUE
rb_apply(VALUE recv, ID mid, VALUE args)
{
    int argc;
    VALUE *argv;

    argc = RARRAY_LEN(args);	/* Assigns LONG, but argc is INT */
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY_PTR(args), VALUE, argc);
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, NOEX_NOSUPER);
}

static VALUE
send_funcall(int argc, VALUE *argv, VALUE recv, int scope)
{
    VALUE vid;

    if (argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    vid = *argv++; argc--;
    PASS_PASSED_BLOCK();
    return rb_call(CLASS_OF(recv), recv, rb_to_id(vid), argc, argv, scope);
}

/*
 *  call-seq:
 *     obj.send(symbol [, args...])        => obj
 *     obj.__send__(symbol [, args...])    => obj
 *  
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. You can use <code>__send__</code> if the name
 *  +send+ clashes with an existing method in _obj_.
 *     
 *     class Klass
 *       def hello(*args)
 *         "Hello " + args.join(' ')
 *       end
 *     end
 *     k = Klass.new
 *     k.send :hello, "gentle", "readers"   #=> "Hello gentle readers"
 */

VALUE
rb_f_send(int argc, VALUE *argv, VALUE recv)
{
    int scope = NOEX_PUBLIC;
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp = YARV_PREVIOUS_CONTROL_FRAME(th->cfp);

    if (SPECIAL_CONST_P(cfp->sp[0])) {
	scope = NOEX_NOSUPER | NOEX_PRIVATE;
    }

    return send_funcall(argc, argv, recv, scope);
}

/*
 *  call-seq:
 *     obj.funcall(symbol [, args...])        => obj
 *     obj.__send!(symbol [, args...])        => obj
 *  
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. Unlike send, which calls private methods only
 *  when it is invoked in function call style, funcall always aware of
 *  private methods.
 *     
 *     1.funcall(:puts, "hello")  # prints "foo"
 */

VALUE
rb_f_funcall(int argc, VALUE *argv, VALUE recv)
{
    return send_funcall(argc, argv, recv, NOEX_NOSUPER | NOEX_PRIVATE);
}

VALUE
rb_funcall(VALUE recv, ID mid, int n, ...)
{
    VALUE *argv;
    va_list ar;
    va_init_list(ar, n);

    if (n > 0) {
	long i;

	argv = ALLOCA_N(VALUE, n);

	for (i = 0; i < n; i++) {
	    argv[i] = va_arg(ar, VALUE);
	}
	va_end(ar);
    }
    else {
	argv = 0;
    }
    return rb_call(CLASS_OF(recv), recv, mid, n, argv,
		   NOEX_NOSUPER | NOEX_PRIVATE);
}

VALUE
rb_funcall2(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv,
		   NOEX_NOSUPER | NOEX_PRIVATE);
}

VALUE
rb_funcall3(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, NOEX_PUBLIC);
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    return th_call_super(GET_THREAD(), argc, argv);
}

static VALUE
backtrace(int lev)
{
    return th_backtrace(GET_THREAD(), lev);
}

/*
 *  call-seq:
 *     caller(start=1)    => array
 *  
 *  Returns the current execution stack---an array containing strings in
 *  the form ``<em>file:line</em>'' or ``<em>file:line: in
 *  `method'</em>''. The optional _start_ parameter
 *  determines the number of initial stack entries to omit from the
 *  result.
 *     
 *     def a(skip)
 *       caller(skip)
 *     end
 *     def b(skip)
 *       a(skip)
 *     end
 *     def c(skip)
 *       b(skip)
 *     end
 *     c(0)   #=> ["prog:2:in `a'", "prog:5:in `b'", "prog:8:in `c'", "prog:10"]
 *     c(1)   #=> ["prog:5:in `b'", "prog:8:in `c'", "prog:11"]
 *     c(2)   #=> ["prog:8:in `c'", "prog:12"]
 *     c(3)   #=> ["prog:13"]
 */

static VALUE
rb_f_caller(int argc, VALUE *argv)
{
    VALUE level;
    int lev;

    rb_scan_args(argc, argv, "01", &level);

    if (NIL_P(level))
	lev = 1;
    else
	lev = NUM2INT(level);
    if (lev < 0)
	rb_raise(rb_eArgError, "negative level (%d)", lev);

    return backtrace(lev);
}

void
rb_backtrace(void)
{
    long i;
    VALUE ary;

    ary = backtrace(-1);
    for (i = 0; i < RARRAY_LEN(ary); i++) {
	printf("\tfrom %s\n", RSTRING_PTR(RARRAY_PTR(ary)[i]));
    }
}

static VALUE
make_backtrace(void)
{
    return backtrace(-1);
}

static ID
frame_func_id(yarv_control_frame_t *cfp)
{
    yarv_iseq_t *iseq = cfp->iseq;
    if (!iseq) {
	return cfp->method_id;
    }
    else if (YARV_IFUNC_P(iseq)) {
	return rb_intern("<ifunc>");
    }
    else {
	return rb_intern(RSTRING_PTR(iseq->name));
    }
}

ID
rb_frame_this_func(void)
{
    return frame_func_id(GET_THREAD()->cfp);
}

ID
rb_frame_callee(void)
{
    return frame_func_id(GET_THREAD()->cfp + 1);
}

void
rb_frame_pop(void)
{
    yarv_thread_t *th = GET_THREAD();
    th->cfp = YARV_PREVIOUS_CONTROL_FRAME(th->cfp);
}

static VALUE
rb_frame_self(void)
{
    return GET_THREAD()->cfp->self;
}

const char *
rb_sourcefile(void)
{
    yarv_iseq_t *iseq = GET_THREAD()->cfp->iseq;
    if (YARV_NORMAL_ISEQ_P(iseq)) {
	return RSTRING_PTR(iseq->file_name);
    }
    return 0;
}

int
rb_sourceline(void)
{
    yarv_thread_t *th = GET_THREAD();
    return th_get_sourceline(th->cfp);
}

VALUE th_set_eval_stack(yarv_thread_t *, VALUE iseq);
VALUE th_eval_body(yarv_thread_t *);

static VALUE
eval(VALUE self, VALUE src, VALUE scope, char *file, int line)
{
    int state;
    VALUE result = Qundef;
    VALUE envval;
    yarv_binding_t *bind = 0;
    yarv_thread_t *th = GET_THREAD();
    yarv_env_t *env = NULL;
    NODE *stored_cref_stack = 0;

    if (file == 0) {
	ruby_set_current_source();
	file = ruby_sourcefile;
	line = ruby_sourceline;
    }
    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	yarv_iseq_t *iseq;
	VALUE iseqval;

	if (scope != Qnil) {
	    
	    if (CLASS_OF(scope) == rb_cBinding) {
		GetBindingPtr(scope, bind);
		envval = bind->env;
		stored_cref_stack = bind->cref_stack;
	    }
	    else {
		rb_raise(rb_eTypeError,
			 "wrong argument type %s (expected Binding)",
			 rb_obj_classname(scope));
	    }
	    GetEnvPtr(envval, env);
	    th->base_block = &env->block;
	}
	else {
	    yarv_control_frame_t *cfp = th_get_ruby_level_cfp(th, th->cfp);
	    th->base_block = GET_BLOCK_PTR_IN_CFP(cfp);
	    th->base_block->iseq = cfp->iseq;	/* TODO */
	}


	/* make eval iseq */
	th->parse_in_eval++;
	iseqval = th_compile(th, src, rb_str_new2(file), INT2FIX(line));
	th->parse_in_eval--;
	th_set_eval_stack(th, iseqval);
	th->base_block = 0;
	if (0) {		// for debug
	    printf("%s\n", RSTRING_PTR(iseq_disasm(iseqval)));
	}

	/* save new env */
	GetISeqPtr(iseqval, iseq);
	if (bind && iseq->local_size > 0) {
	    bind->env = th_make_env_object(th, th->cfp);
	}

	/* push tag */
	if (stored_cref_stack) {
	    stored_cref_stack =
		th_set_special_cref(th, env->block.lfp, stored_cref_stack);
	}
	/* kick */
	result = th_eval_body(th);
    }
    POP_TAG();

    if (stored_cref_stack) {
	th_set_special_cref(th, env->block.lfp, stored_cref_stack);
    }

    if (state) {
	if (state == TAG_RAISE) {
	    if (strcmp(file, "(eval)") == 0) {
		VALUE mesg, errat;

		errat = get_backtrace(GET_THREAD()->errinfo);
		mesg = rb_attr_get(GET_THREAD()->errinfo, rb_intern("mesg"));
		if (!NIL_P(errat) && TYPE(errat) == T_ARRAY) {
		    if (!NIL_P(mesg) && TYPE(mesg) == T_STRING) {
			rb_str_update(mesg, 0, 0, rb_str_new2(": "));
			rb_str_update(mesg, 0, 0, RARRAY_PTR(errat)[0]);
		    }
		    RARRAY_PTR(errat)[0] = RARRAY_PTR(backtrace(-2))[0];
		}
	    }
	    rb_exc_raise(GET_THREAD()->errinfo);
	}
	JUMP_TAG(state);
    }
    return result;
}

/*
 *  call-seq:
 *     eval(string [, binding [, filename [,lineno]]])  => obj
 *  
 *  Evaluates the Ruby expression(s) in <em>string</em>. If
 *  <em>binding</em> is given, the evaluation is performed in its
 *  context. The binding may be a <code>Binding</code> object or a
 *  <code>Proc</code> object. If the optional <em>filename</em> and
 *  <em>lineno</em> parameters are present, they will be used when
 *  reporting syntax errors.
 *     
 *     def getBinding(str)
 *       return binding
 *     end
 *     str = "hello"
 *     eval "str + ' Fred'"                      #=> "hello Fred"
 *     eval "str + ' Fred'", getBinding("bye")   #=> "bye Fred"
 */

VALUE
rb_f_eval(int argc, VALUE *argv, VALUE self)
{
    VALUE src, scope, vfile, vline;
    char *file = "(eval)";
    int line = 1;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    if (rb_safe_level() >= 4) {
	StringValue(src);
	if (!NIL_P(scope) && !OBJ_TAINTED(scope)) {
	    rb_raise(rb_eSecurityError,
		     "Insecure: can't modify trusted binding");
	}
    }
    else {
	SafeStringValue(src);
    }
    if (argc >= 3) {
	StringValue(vfile);
    }
    if (argc >= 4) {
	line = NUM2INT(vline);
    }

    if (!NIL_P(vfile))
	file = RSTRING_PTR(vfile);
    return eval(self, src, scope, file, line);
}

VALUE *th_cfp_svar(yarv_control_frame_t *cfp, int idx);

/* function to call func under the specified class/module context */
static VALUE
exec_under(VALUE (*func) (VALUE), VALUE under, VALUE self, VALUE args)
{
    VALUE val = Qnil;		/* OK */
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp = th->cfp;
    yarv_control_frame_t *pcfp = YARV_PREVIOUS_CONTROL_FRAME(cfp);
    VALUE stored_self = pcfp->self;
    NODE *stored_cref = 0;
    NODE **pcref = 0;

    yarv_block_t block;
    yarv_block_t *blockptr;
    int state;

    /* replace environment */
    pcfp->self = self;
    if ((blockptr = GC_GUARDED_PTR_REF(*th->cfp->lfp)) != 0) {
	/* copy block info */
	// TODO: why?
	block = *blockptr;
	block.self = self;
	*th->cfp->lfp = GC_GUARDED_PTR(&block);
    }

    while (!YARV_NORMAL_ISEQ_P(cfp->iseq)) {
	cfp = YARV_PREVIOUS_CONTROL_FRAME(cfp);
    }
    
    pcref = (NODE **) th_cfp_svar(cfp, -1);
    stored_cref = *pcref;
    *pcref = th_cref_push(th, under, NOEX_PUBLIC);

    PUSH_TAG(PROT_NONE);
    if ((state = EXEC_TAG()) == 0) {
	val = (*func) (args);
    }
    POP_TAG();

    /* restore environment */
    *pcref = stored_cref;
    pcfp->self = stored_self;

    if (state) {
	JUMP_TAG(state);
    }
    return val;
}

static VALUE
yield_under_i(VALUE arg)
{
    int avalue = Qtrue;
    
    if (arg == Qundef) {
	avalue = Qfalse;
    }
    return rb_yield_0(arg, 0, 0, 0, avalue);
}

/* block eval under the class/module context */
static VALUE
yield_under(VALUE under, VALUE self, VALUE values)
{
    return exec_under(yield_under_i, under, self, values);
}

static VALUE
eval_under_i(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    return eval(args[0], args[1], Qnil, (char *)args[2], (int)args[3]);
}

/* string eval under the class/module context */
static VALUE
eval_under(VALUE under, VALUE self, VALUE src, const char *file, int line)
{
    VALUE args[4];

    if (rb_safe_level() >= 4) {
	StringValue(src);
    }
    else {
	SafeStringValue(src);
    }
    args[0] = self;
    args[1] = src;
    args[2] = (VALUE)file;
    args[3] = (VALUE)line;
    return exec_under(eval_under_i, under, self, (VALUE)args);
}

static VALUE
specific_eval(int argc, VALUE *argv, VALUE klass, VALUE self)
{
    if (rb_block_given_p()) {
	if (argc > 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)",
		     argc);
	}
	return yield_under(klass, self, Qundef);
    }
    else {
	char *file = "(eval)";
	int line = 1;

	if (argc == 0) {
	    rb_raise(rb_eArgError, "block not supplied");
	}
	else {
	    if (rb_safe_level() >= 4) {
		StringValue(argv[0]);
	    }
	    else {
		SafeStringValue(argv[0]);
	    }
	    if (argc > 3) {
		rb_raise(rb_eArgError,
			 "wrong number of arguments: %s(src) or %s{..}",
			 rb_frame_callee(), rb_frame_callee());
	    }
	    if (argc > 2)
		line = NUM2INT(argv[2]);
	    if (argc > 1) {
		file = StringValuePtr(argv[1]);
	    }
	}
	return eval_under(klass, self, argv[0], file, line);
    }
}

/*
 *  call-seq:
 *     obj.instance_eval(string [, filename [, lineno]] )   => obj
 *     obj.instance_eval {| | block }                       => obj
 *  
 *  Evaluates a string containing Ruby source code, or the given block,
 *  within the context of the receiver (_obj_). In order to set the
 *  context, the variable +self+ is set to _obj_ while
 *  the code is executing, giving the code access to _obj_'s
 *  instance variables. In the version of <code>instance_eval</code>
 *  that takes a +String+, the optional second and third
 *  parameters supply a filename and starting line number that are used
 *  when reporting compilation errors.
 *     
 *     class Klass
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = Klass.new
 *     k.instance_eval { @secret }   #=> 99
 */

VALUE
rb_obj_instance_eval(int argc, VALUE *argv, VALUE self)
{
    VALUE klass;

    if (SPECIAL_CONST_P(self)) {
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }
    return specific_eval(argc, argv, klass, self);
}

/*
 *  call-seq:
 *     obj.instance_exec(arg...) {|var...| block }                       => obj
 *  
 *  Executes the given block within the context of the receiver
 *  (_obj_). In order to set the context, the variable +self+ is set
 *  to _obj_ while the code is executing, giving the code access to
 *  _obj_'s instance variables.  Arguments are passed as block parameters.
 *     
 *     class Klass
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = Klass.new
 *     k.instance_exec(5) {|x| @secret+x }   #=> 104
 */

VALUE
rb_obj_instance_exec(int argc, VALUE *argv, VALUE self)
{
    VALUE klass;

    if (SPECIAL_CONST_P(self)) {
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }
    return yield_under(klass, self, rb_ary_new4(argc, argv));
}

/*
 *  call-seq:
 *     mod.class_eval(string [, filename [, lineno]])  => obj
 *     mod.module_eval {|| block }                     => obj
 *  
 *  Evaluates the string or block in the context of _mod_. This can
 *  be used to add methods to a class. <code>module_eval</code> returns
 *  the result of evaluating its argument. The optional _filename_
 *  and _lineno_ parameters set the text for error messages.
 *     
 *     class Thing
 *     end
 *     a = %q{def hello() "Hello there!" end}
 *     Thing.module_eval(a)
 *     puts Thing.new.hello()
 *     Thing.module_eval("invalid code", "dummy", 123)
 *     
 *  <em>produces:</em>
 *     
 *     Hello there!
 *     dummy:123:in `module_eval': undefined local variable
 *         or method `code' for Thing:Class
 */

VALUE
rb_mod_module_eval(int argc, VALUE *argv, VALUE mod)
{
    return specific_eval(argc, argv, mod, mod);
}

/*
 *  call-seq:
 *     mod.module_exec(arg...) {|var...| block }       => obj
 *     mod.class_exec(arg...) {|var...| block }        => obj
 *  
 *  Evaluates the given block in the context of the class/module.
 *  The method defined in the block will belong to the receiver.
 *     
 *     class Thing
 *     end
 *     Thing.class_exec{
 *       def hello() "Hello there!" end
 *     }
 *     puts Thing.new.hello()
 *     
 *  <em>produces:</em>
 *     
 *     Hello there!
 */

VALUE
rb_mod_module_exec(int argc, VALUE *argv, VALUE mod)
{
    return yield_under(mod, mod, rb_ary_new4(argc, argv));
}

static void
secure_visibility(VALUE self)
{
    if (rb_safe_level() >= 4 && !OBJ_TAINTED(self)) {
	rb_raise(rb_eSecurityError,
		 "Insecure: can't change method visibility");
    }
}

static void
set_method_visibility(VALUE self, int argc, VALUE *argv, ID ex)
{
    int i;
    secure_visibility(self);
    for (i = 0; i < argc; i++) {
	rb_export_method(self, rb_to_id(argv[i]), ex);
    }
    rb_clear_cache_by_class(self);
}

/*
 *  call-seq:
 *     public                 => self
 *     public(symbol, ...)    => self
 *  
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 */

static VALUE
rb_mod_public(int argc, VALUE *argv, VALUE module)
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_PUBLIC);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PUBLIC);
    }
    return module;
}

/*
 *  call-seq:
 *     protected                => self
 *     protected(symbol, ...)   => self
 *  
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to protected. With arguments, sets the named methods
 *  to have protected visibility.
 */

static VALUE
rb_mod_protected(int argc, VALUE *argv, VALUE module)
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_PROTECTED);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PROTECTED);
    }
    return module;
}

/*
 *  call-seq:
 *     private                 => self
 *     private(symbol, ...)    => self
 *  
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods
 *  to have private visibility.
 *     
 *     module Mod
 *       def a()  end
 *       def b()  end
 *       private
 *       def c()  end
 *       private :a
 *     end
 *     Mod.private_instance_methods   #=> ["a", "c"]
 */

static VALUE
rb_mod_private(int argc, VALUE *argv, VALUE module)
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_PRIVATE);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    }
    return module;
}

/*
 *  call-seq:
 *     mod.public_class_method(symbol, ...)    => mod
 *  
 *  Makes a list of existing class methods public.
 */

static VALUE
rb_mod_public_method(int argc, VALUE *argv, VALUE obj)
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PUBLIC);
    return obj;
}

/*
 *  call-seq:
 *     mod.private_class_method(symbol, ...)   => mod
 *  
 *  Makes existing class methods private. Often used to hide the default
 *  constructor <code>new</code>.
 *     
 *     class SimpleSingleton  # Not thread safe
 *       private_class_method :new
 *       def SimpleSingleton.create(*args, &block)
 *         @me = new(*args, &block) if ! @me
 *         @me
 *       end
 *     end
 */

static VALUE
rb_mod_private_method(int argc, VALUE *argv, VALUE obj)
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PRIVATE);
    return obj;
}

/*
 *  call-seq:
 *     public
 *     public(symbol, ...)
 *  
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 */

static VALUE
top_public(int argc, VALUE *argv)
{
    return rb_mod_public(argc, argv, rb_cObject);
}

static VALUE
top_private(int argc, VALUE *argv)
{
    return rb_mod_private(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     module_function(symbol, ...)    => self
 *  
 *  Creates module functions for the named methods. These functions may
 *  be called with the module as a receiver, and also become available
 *  as instance methods to classes that mix in the module. Module
 *  functions are copies of the original, and so may be changed
 *  independently. The instance-method versions are made private. If
 *  used with no arguments, subsequently defined methods become module
 *  functions.
 *     
 *     module Mod
 *       def one
 *         "This is one"
 *       end
 *       module_function :one
 *     end
 *     class Cls
 *       include Mod
 *       def callOne
 *         one
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c = Cls.new
 *     c.callOne   #=> "This is one"
 *     module Mod
 *       def one
 *         "This is the new one"
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c.callOne   #=> "This is the new one"
 */

static VALUE
rb_mod_modfunc(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id;
    NODE *fbody;

    if (TYPE(module) != T_MODULE) {
	rb_raise(rb_eTypeError, "module_function must be called for modules");
    }

    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_MODFUNC);
	return module;
    }

    set_method_visibility(module, argc, argv, NOEX_PRIVATE);

    for (i = 0; i < argc; i++) {
	VALUE m = module;

	id = rb_to_id(argv[i]);
	for (;;) {
	    fbody = search_method(m, id, &m);
	    if (fbody == 0) {
		fbody = search_method(rb_cObject, id, &m);
	    }
	    if (fbody == 0 || fbody->nd_body == 0) {
		rb_bug("undefined method `%s'; can't happen", rb_id2name(id));
	    }
	    if (nd_type(fbody->nd_body->nd_body) != NODE_ZSUPER) {
		break;		/* normal case: need not to follow 'super' link */
	    }
	    m = RCLASS(m)->super;
	    if (!m)
		break;
	}
	rb_add_method(rb_singleton_class(module), id, fbody->nd_body->nd_body,
		      NOEX_PUBLIC);
    }
    return module;
}

/*
 *  call-seq:
 *     append_features(mod)   => mod
 *  
 *  When this module is included in another, Ruby calls
 *  <code>append_features</code> in this module, passing it the
 *  receiving module in _mod_. Ruby's default implementation is
 *  to add the constants, methods, and module variables of this module
 *  to _mod_ if this module has not already been added to
 *  _mod_ or one of its ancestors. See also <code>Module#include</code>.
 */

static VALUE
rb_mod_append_features(VALUE module, VALUE include)
{
    switch (TYPE(include)) {
    case T_CLASS:
    case T_MODULE:
	break;
    default:
	Check_Type(include, T_CLASS);
	break;
    }
    rb_include_module(include, module);

    return module;
}

/*
 *  call-seq:
 *     include(module, ...)    => self
 *  
 *  Invokes <code>Module.append_features</code> on each parameter in turn.
 */

static VALUE
rb_mod_include(int argc, VALUE *argv, VALUE module)
{
    int i;

    for (i = 0; i < argc; i++)
	Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], rb_intern("append_features"), 1, module);
	rb_funcall(argv[argc], rb_intern("included"), 1, module);
    }
    return module;
}

void
rb_obj_call_init(VALUE obj, int argc, VALUE *argv)
{
    PASS_PASSED_BLOCK();
    rb_funcall2(obj, init, argc, argv);
}

void
rb_extend_object(VALUE obj, VALUE module)
{
    rb_include_module(rb_singleton_class(obj), module);
}

/*
 *  call-seq:
 *     extend_object(obj)    => obj
 *  
 *  Extends the specified object by adding this module's constants and
 *  methods (which are added as singleton methods). This is the callback
 *  method used by <code>Object#extend</code>.
 *     
 *     module Picky
 *       def Picky.extend_object(o)
 *         if String === o
 *           puts "Can't add Picky to a String"
 *         else
 *           puts "Picky added to #{o.class}"
 *           super
 *         end
 *       end
 *     end
 *     (s = Array.new).extend Picky  # Call Object.extend
 *     (s = "quick brown fox").extend Picky
 *     
 *  <em>produces:</em>
 *     
 *     Picky added to Array
 *     Can't add Picky to a String
 */

static VALUE
rb_mod_extend_object(VALUE mod, VALUE obj)
{
    rb_extend_object(obj, mod);
    return obj;
}

/*
 *  call-seq:
 *     obj.extend(module, ...)    => obj
 *  
 *  Adds to _obj_ the instance methods from each module given as a
 *  parameter.
 *     
 *     module Mod
 *       def hello
 *         "Hello from Mod.\n"
 *       end
 *     end
 *     
 *     class Klass
 *       def hello
 *         "Hello from Klass.\n"
 *       end
 *     end
 *     
 *     k = Klass.new
 *     k.hello         #=> "Hello from Klass.\n"
 *     k.extend(Mod)   #=> #<Klass:0x401b3bc8>
 *     k.hello         #=> "Hello from Mod.\n"
 */

static VALUE
rb_obj_extend(int argc, VALUE *argv, VALUE obj)
{
    int i;

    if (argc == 0) {
	rb_raise(rb_eArgError, "wrong number of arguments (0 for 1)");
    }
    for (i = 0; i < argc; i++)
	Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], rb_intern("extend_object"), 1, obj);
	rb_funcall(argv[argc], rb_intern("extended"), 1, obj);
    }
    return obj;
}

/*
 *  call-seq:
 *     include(module, ...)   => self
 *  
 *  Invokes <code>Module.append_features</code>
 *  on each parameter in turn. Effectively adds the methods and constants
 *  in each module to the receiver.
 */

static VALUE
top_include(int argc, VALUE *argv, VALUE self)
{
    rb_secure(4);
    if (ruby_wrapper) {
	rb_warning
	    ("main#include in the wrapped load is effective only in wrapper module");
	return rb_mod_include(argc, argv, ruby_wrapper);
    }
    return rb_mod_include(argc, argv, rb_cObject);
}

VALUE rb_f_trace_var();
VALUE rb_f_untrace_var();

static VALUE
get_errinfo(void)
{
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp = th->cfp;
    yarv_control_frame_t *end_cfp = YARV_END_CONTROL_FRAME(th);

    while (YARV_VALID_CONTROL_FRAME_P(cfp, end_cfp)) {
	if (YARV_NORMAL_ISEQ_P(cfp->iseq)) {
	    if (cfp->iseq->type == ISEQ_TYPE_RESCUE) {
		return cfp->dfp[-1];
	    }
	    else if (cfp->iseq->type == ISEQ_TYPE_ENSURE &&
		     TYPE(cfp->dfp[-1]) != T_NODE) {
		return cfp->dfp[-1];
	    }
	}
	cfp = YARV_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return Qnil;
}

static VALUE
errinfo_getter(ID id)
{
    return get_errinfo();
}

VALUE
rb_errinfo(void)
{
    return get_errinfo();
}

static void
errinfo_setter(VALUE val, ID id, VALUE *var)
{
    if (!NIL_P(val) && !rb_obj_is_kind_of(val, rb_eException)) {
	rb_raise(rb_eTypeError, "assigning non-exception to $!");
    }
    else {
	GET_THREAD()->errinfo = val;
    }
}

void
rb_set_errinfo(VALUE err)
{
    errinfo_setter(err, 0, 0);
}

static VALUE
errat_getter(ID id)
{
    VALUE err = get_errinfo();
    if (!NIL_P(err)) {
	return get_backtrace(err);
    }
    else {
	return Qnil;
    }
}

static void
errat_setter(VALUE val, ID id, VALUE *var)
{
    VALUE err = get_errinfo();
    if (NIL_P(err)) {
	rb_raise(rb_eArgError, "$! not set");
    }
    set_backtrace(err, val);
}

/*
 *  call-seq:
 *     local_variables    => array
 *  
 *  Returns the names of the current local variables.
 *     
 *     fred = 1
 *     for i in 1..10
 *        # ...
 *     end
 *     local_variables   #=> ["fred", "i"]
 */

int th_collect_local_variables_in_heap(yarv_thread_t *th, VALUE *dfp, VALUE ary);

static VALUE
rb_f_local_variables(void)
{
    VALUE ary = rb_ary_new();
    yarv_thread_t *th = GET_THREAD();
    yarv_control_frame_t *cfp =
	th_get_ruby_level_cfp(th, YARV_PREVIOUS_CONTROL_FRAME(th->cfp));
    int i;

    while (1) {
	if (cfp->iseq) {
	    int start = 0;
	    if (cfp->lfp == cfp->dfp) {
		start = 1;
	    }
	    for (i = start; i < cfp->iseq->local_size; i++) {
		ID lid = cfp->iseq->local_tbl[i];
		if (lid) {
		    rb_ary_push(ary, rb_str_new2(rb_id2name(lid)));
		}
	    }
	}
	if (cfp->lfp != cfp->dfp) {
	    /* block */
	    VALUE *dfp = GC_GUARDED_PTR_REF(cfp->dfp[0]);

	    if (th_collect_local_variables_in_heap(th, dfp, ary)) {
		break;
	    }
	    else {
		while (cfp->dfp != dfp) {
		    cfp = YARV_PREVIOUS_CONTROL_FRAME(cfp);
		}
	    }
	}
	else {
	    break;
	}
    }
    return ary;
}


void
Init_eval()
{
    /* TODO: fix position */
    GET_THREAD()->vm->mark_object_ary = rb_ary_new();
    
    init = rb_intern("initialize");
    eqq = rb_intern("===");
    each = rb_intern("each");

    aref = rb_intern("[]");
    aset = rb_intern("[]=");
    match = rb_intern("=~");
    missing = rb_intern("method_missing");
    added = rb_intern("method_added");
    singleton_added = rb_intern("singleton_method_added");
    removed = rb_intern("method_removed");
    singleton_removed = rb_intern("singleton_method_removed");
    undefined = rb_intern("method_undefined");
    singleton_undefined = rb_intern("singleton_method_undefined");

    object_id = rb_intern("object_id");
    __send = rb_intern("__send");
    __send_bang = rb_intern("__send!");

    rb_global_variable((VALUE *)&ruby_eval_tree);

    rb_define_virtual_variable("$@", errat_getter, errat_setter);
    rb_define_virtual_variable("$!", errinfo_getter, errinfo_setter);

    rb_define_global_function("eval", rb_f_eval, -1);
    rb_define_global_function("iterator?", rb_f_block_given_p, 0);
    rb_define_global_function("block_given?", rb_f_block_given_p, 0);
    rb_define_global_function("method_missing", rb_method_missing, -1);
    rb_define_global_function("loop", rb_f_loop, 0);

    rb_define_method(rb_mKernel, "respond_to?", obj_respond_to, -1);
    respond_to = rb_intern("respond_to?");
    basic_respond_to = rb_method_node(rb_cObject, respond_to);
    rb_register_mark_object((VALUE)basic_respond_to);

    rb_define_global_function("raise", rb_f_raise, -1);
    rb_define_global_function("fail", rb_f_raise, -1);

    rb_define_global_function("caller", rb_f_caller, -1);

    rb_define_global_function("global_variables", rb_f_global_variables, 0);	/* in variable.c */
    rb_define_global_function("local_variables", rb_f_local_variables, 0);

    rb_define_method(rb_cBasicObject, "send", rb_f_send, -1);
    rb_define_method(rb_cBasicObject, "__send__", rb_f_send, -1);
    rb_define_method(rb_cBasicObject, "__send", rb_f_send, -1);
    rb_define_method(rb_cBasicObject, "funcall", rb_f_funcall, -1);
    rb_define_method(rb_cBasicObject, "__send!", rb_f_funcall, -1);

    rb_define_method(rb_mKernel, "instance_eval", rb_obj_instance_eval, -1);
    rb_define_method(rb_mKernel, "instance_exec", rb_obj_instance_exec, -1);

    rb_define_private_method(rb_cModule, "append_features", rb_mod_append_features, 1);
    rb_define_private_method(rb_cModule, "extend_object", rb_mod_extend_object, 1);
    rb_define_private_method(rb_cModule, "include", rb_mod_include, -1);
    rb_define_private_method(rb_cModule, "public", rb_mod_public, -1);
    rb_define_private_method(rb_cModule, "protected", rb_mod_protected, -1);
    rb_define_private_method(rb_cModule, "private", rb_mod_private, -1);
    rb_define_private_method(rb_cModule, "module_function", rb_mod_modfunc, -1);
    rb_define_method(rb_cModule, "method_defined?", rb_mod_method_defined, 1);
    rb_define_method(rb_cModule, "public_method_defined?", rb_mod_public_method_defined, 1);
    rb_define_method(rb_cModule, "private_method_defined?", rb_mod_private_method_defined, 1);
    rb_define_method(rb_cModule, "protected_method_defined?", rb_mod_protected_method_defined, 1);
    rb_define_method(rb_cModule, "public_class_method", rb_mod_public_method, -1);
    rb_define_method(rb_cModule, "private_class_method", rb_mod_private_method, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "module_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "class_exec", rb_mod_module_exec, -1);

    rb_undef_method(rb_cClass, "module_function");

    rb_define_private_method(rb_cModule, "remove_method", rb_mod_remove_method, -1);
    rb_define_private_method(rb_cModule, "undef_method", rb_mod_undef_method, -1);
    rb_define_private_method(rb_cModule, "alias_method", rb_mod_alias_method, 2);

    rb_define_singleton_method(rb_cModule, "nesting", rb_mod_nesting, 0);
    rb_define_singleton_method(rb_cModule, "constants", rb_mod_s_constants, -1);

    rb_define_singleton_method(ruby_top_self, "include", top_include, -1);
    rb_define_singleton_method(ruby_top_self, "public", top_public, -1);
    rb_define_singleton_method(ruby_top_self, "private", top_private, -1);

    rb_define_method(rb_mKernel, "extend", rb_obj_extend, -1);

    rb_define_global_function("trace_var", rb_f_trace_var, -1);	/* in variable.c */
    rb_define_global_function("untrace_var", rb_f_untrace_var, -1);	/* in variable.c */

    rb_define_global_function("set_trace_func", set_trace_func, 1);

    rb_define_virtual_variable("$SAFE", safe_getter, safe_setter);
}


/* for parser */

VALUE
rb_dvar_defined(ID id)
{
    yarv_thread_t *th = GET_THREAD();
    yarv_iseq_t *iseq;
    if (th->base_block && (iseq = th->base_block->iseq)) {
	while (iseq->type == ISEQ_TYPE_BLOCK ||
	       iseq->type == ISEQ_TYPE_RESCUE ||
	       iseq->type == ISEQ_TYPE_ENSURE ||
	       iseq->type == ISEQ_TYPE_EVAL) {
	    int i;
	    // printf("local size: %d\n", iseq->local_size);
	    for (i = 0; i < iseq->local_size; i++) {
		// printf("id (%4d): %s\n", i, rb_id2name(iseq->local_tbl[i]));
		if (iseq->local_tbl[i] == id) {
		    return Qtrue;
		}
	    }
	    iseq = iseq->parent_iseq;
	}
    }
    return Qfalse;
}

void
rb_scope_setup_top_local_tbl(ID *tbl)
{
    yarv_thread_t *th = GET_THREAD();
    if (tbl) {
	if (th->top_local_tbl) {
	    xfree(th->top_local_tbl);
	    th->top_local_tbl = 0;
	}
	th->top_local_tbl = tbl;
    }
    else {
	th->top_local_tbl = 0;
    }
}

int
rb_scope_base_local_tbl_size(void)
{
    yarv_thread_t *th = GET_THREAD();
    if (th->base_block) {
	return th->base_block->iseq->local_iseq->local_size +
	    2 /* $_, $~ */  - 1 /* svar */ ;
    }
    else {
	return 0;
    }
}

ID
rb_scope_base_local_tbl_id(int i)
{
    yarv_thread_t *th = GET_THREAD();
    switch (i) {
    case 0:
	return rb_intern("$_");
    case 1:
	return rb_intern("$~");
    default:
	return th->base_block->iseq->local_iseq->
	    local_tbl[i - 1 /* tbl[0] is reserved by svar */ ];
    }
}

int
rb_dvar_current(void)
{
    yarv_thread_t *th = GET_THREAD();
    if (th->base_block) {
	return 1;
    }
    else {
	return 0;
    }
}

int
rb_parse_in_eval(void)
{
    return GET_THREAD()->parse_in_eval != 0;
}
