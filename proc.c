/**********************************************************************

  proc.c - Proc, Binding, Env

  $Author$
  created at: Wed Jan 17 12:13:14 2007

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "eval_intern.h"
#include "gc.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/symbol.h"
#include "method.h"
#include "iseq.h"
#include "vm_core.h"
#include "yjit.h"

#if !defined(__GNUC__) || __GNUC__ < 5 || defined(__MINGW32__)
# define NO_CLOBBERED(v) (*(volatile VALUE *)&(v))
#else
# define NO_CLOBBERED(v) (v)
#endif

#define UPDATE_TYPED_REFERENCE(_type, _ref) *(_type*)&_ref = (_type)rb_gc_location((VALUE)_ref)
#define UPDATE_REFERENCE(_ref) UPDATE_TYPED_REFERENCE(VALUE, _ref)

const rb_cref_t *rb_vm_cref_in_context(VALUE self, VALUE cbase);

struct METHOD {
    const VALUE recv;
    const VALUE klass;
    /* needed for #super_method */
    const VALUE iclass;
    /* Different than me->owner only for ZSUPER methods.
       This is error-prone but unavoidable unless ZSUPER methods are removed. */
    const VALUE owner;
    const rb_method_entry_t * const me;
    /* for bound methods, `me' should be rb_callable_method_entry_t * */
};

VALUE rb_cUnboundMethod;
VALUE rb_cMethod;
VALUE rb_cBinding;
VALUE rb_cProc;

static rb_block_call_func bmcall;
static int method_arity(VALUE);
static int method_min_max_arity(VALUE, int *max);
static VALUE proc_binding(VALUE self);

#define attached id__attached__

/* Proc */

#define IS_METHOD_PROC_IFUNC(ifunc) ((ifunc)->func == bmcall)

/* :FIXME: The way procs are cloned has been historically different from the
 * way everything else are.  @shyouhei is not sure for the intention though.
 */
#undef CLONESETUP
static inline void
CLONESETUP(VALUE clone, VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(! RB_SPECIAL_CONST_P(obj));
    RBIMPL_ASSERT_OR_ASSUME(! RB_SPECIAL_CONST_P(clone));

    const VALUE flags = RUBY_FL_PROMOTED0 | RUBY_FL_PROMOTED1 | RUBY_FL_FINALIZE;
    rb_obj_setup(clone, rb_singleton_class_clone(obj),
                 RB_FL_TEST_RAW(obj, ~flags));
    rb_singleton_class_attached(RBASIC_CLASS(clone), clone);
    if (RB_FL_TEST(obj, RUBY_FL_EXIVAR)) rb_copy_generic_ivar(clone, obj);
}

static void
block_mark(const struct rb_block *block)
{
    switch (vm_block_type(block)) {
      case block_type_iseq:
      case block_type_ifunc:
        {
            const struct rb_captured_block *captured = &block->as.captured;
            RUBY_MARK_MOVABLE_UNLESS_NULL(captured->self);
            RUBY_MARK_MOVABLE_UNLESS_NULL((VALUE)captured->code.val);
            if (captured->ep && !UNDEF_P(captured->ep[VM_ENV_DATA_INDEX_ENV]) /* cfunc_proc_t */) {
                rb_gc_mark(VM_ENV_ENVVAL(captured->ep));
            }
        }
        break;
      case block_type_symbol:
        RUBY_MARK_MOVABLE_UNLESS_NULL(block->as.symbol);
        break;
      case block_type_proc:
        RUBY_MARK_MOVABLE_UNLESS_NULL(block->as.proc);
        break;
    }
}

static void
block_compact(struct rb_block *block)
{
    switch (block->type) {
      case block_type_iseq:
      case block_type_ifunc:
        {
            struct rb_captured_block *captured = &block->as.captured;
            captured->self = rb_gc_location(captured->self);
            captured->code.val = rb_gc_location(captured->code.val);
        }
        break;
      case block_type_symbol:
        block->as.symbol = rb_gc_location(block->as.symbol);
        break;
      case block_type_proc:
        block->as.proc = rb_gc_location(block->as.proc);
        break;
    }
}

static void
proc_compact(void *ptr)
{
    rb_proc_t *proc = ptr;
    block_compact((struct rb_block *)&proc->block);
}

static void
proc_mark(void *ptr)
{
    rb_proc_t *proc = ptr;
    block_mark(&proc->block);
    RUBY_MARK_LEAVE("proc");
}

typedef struct {
    rb_proc_t basic;
    VALUE env[VM_ENV_DATA_SIZE + 1]; /* ..., envval */
} cfunc_proc_t;

static size_t
proc_memsize(const void *ptr)
{
    const rb_proc_t *proc = ptr;
    if (proc->block.as.captured.ep == ((const cfunc_proc_t *)ptr)->env+1)
        return sizeof(cfunc_proc_t);
    return sizeof(rb_proc_t);
}

static const rb_data_type_t proc_data_type = {
    "proc",
    {
        proc_mark,
        RUBY_TYPED_DEFAULT_FREE,
        proc_memsize,
        proc_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

VALUE
rb_proc_alloc(VALUE klass)
{
    rb_proc_t *proc;
    return TypedData_Make_Struct(klass, rb_proc_t, &proc_data_type, proc);
}

VALUE
rb_obj_is_proc(VALUE proc)
{
    return RBOOL(rb_typeddata_is_kind_of(proc, &proc_data_type));
}

/* :nodoc: */
static VALUE
proc_clone(VALUE self)
{
    VALUE procval = rb_proc_dup(self);
    CLONESETUP(procval, self);
    return procval;
}

/*
 * call-seq:
 *   prc.lambda? -> true or false
 *
 * Returns +true+ if a Proc object is lambda.
 * +false+ if non-lambda.
 *
 * The lambda-ness affects argument handling and the behavior of +return+ and +break+.
 *
 * A Proc object generated by +proc+ ignores extra arguments.
 *
 *   proc {|a,b| [a,b] }.call(1,2,3)    #=> [1,2]
 *
 * It provides +nil+ for missing arguments.
 *
 *   proc {|a,b| [a,b] }.call(1)        #=> [1,nil]
 *
 * It expands a single array argument.
 *
 *   proc {|a,b| [a,b] }.call([1,2])    #=> [1,2]
 *
 * A Proc object generated by +lambda+ doesn't have such tricks.
 *
 *   lambda {|a,b| [a,b] }.call(1,2,3)  #=> ArgumentError
 *   lambda {|a,b| [a,b] }.call(1)      #=> ArgumentError
 *   lambda {|a,b| [a,b] }.call([1,2])  #=> ArgumentError
 *
 * Proc#lambda? is a predicate for the tricks.
 * It returns +true+ if no tricks apply.
 *
 *   lambda {}.lambda?            #=> true
 *   proc {}.lambda?              #=> false
 *
 * Proc.new is the same as +proc+.
 *
 *   Proc.new {}.lambda?          #=> false
 *
 * +lambda+, +proc+ and Proc.new preserve the tricks of
 * a Proc object given by <code>&</code> argument.
 *
 *   lambda(&lambda {}).lambda?   #=> true
 *   proc(&lambda {}).lambda?     #=> true
 *   Proc.new(&lambda {}).lambda? #=> true
 *
 *   lambda(&proc {}).lambda?     #=> false
 *   proc(&proc {}).lambda?       #=> false
 *   Proc.new(&proc {}).lambda?   #=> false
 *
 * A Proc object generated by <code>&</code> argument has the tricks
 *
 *   def n(&b) b.lambda? end
 *   n {}                         #=> false
 *
 * The <code>&</code> argument preserves the tricks if a Proc object
 * is given by <code>&</code> argument.
 *
 *   n(&lambda {})                #=> true
 *   n(&proc {})                  #=> false
 *   n(&Proc.new {})              #=> false
 *
 * A Proc object converted from a method has no tricks.
 *
 *   def m() end
 *   method(:m).to_proc.lambda?   #=> true
 *
 *   n(&method(:m))               #=> true
 *   n(&method(:m).to_proc)       #=> true
 *
 * +define_method+ is treated the same as method definition.
 * The defined method has no tricks.
 *
 *   class C
 *     define_method(:d) {}
 *   end
 *   C.new.d(1,2)       #=> ArgumentError
 *   C.new.method(:d).to_proc.lambda?   #=> true
 *
 * +define_method+ always defines a method without the tricks,
 * even if a non-lambda Proc object is given.
 * This is the only exception for which the tricks are not preserved.
 *
 *   class C
 *     define_method(:e, &proc {})
 *   end
 *   C.new.e(1,2)       #=> ArgumentError
 *   C.new.method(:e).to_proc.lambda?   #=> true
 *
 * This exception ensures that methods never have tricks
 * and makes it easy to have wrappers to define methods that behave as usual.
 *
 *   class C
 *     def self.def2(name, &body)
 *       define_method(name, &body)
 *     end
 *
 *     def2(:f) {}
 *   end
 *   C.new.f(1,2)       #=> ArgumentError
 *
 * The wrapper <i>def2</i> defines a method which has no tricks.
 *
 */

VALUE
rb_proc_lambda_p(VALUE procval)
{
    rb_proc_t *proc;
    GetProcPtr(procval, proc);

    return RBOOL(proc->is_lambda);
}

/* Binding */

static void
binding_free(void *ptr)
{
    RUBY_FREE_ENTER("binding");
    ruby_xfree(ptr);
    RUBY_FREE_LEAVE("binding");
}

static void
binding_mark(void *ptr)
{
    rb_binding_t *bind = ptr;

    RUBY_MARK_ENTER("binding");
    block_mark(&bind->block);
    rb_gc_mark_movable(bind->pathobj);
    RUBY_MARK_LEAVE("binding");
}

static void
binding_compact(void *ptr)
{
    rb_binding_t *bind = ptr;

    block_compact((struct rb_block *)&bind->block);
    UPDATE_REFERENCE(bind->pathobj);
}

static size_t
binding_memsize(const void *ptr)
{
    return sizeof(rb_binding_t);
}

const rb_data_type_t ruby_binding_data_type = {
    "binding",
    {
        binding_mark,
        binding_free,
        binding_memsize,
        binding_compact,
    },
    0, 0, RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE
rb_binding_alloc(VALUE klass)
{
    VALUE obj;
    rb_binding_t *bind;
    obj = TypedData_Make_Struct(klass, rb_binding_t, &ruby_binding_data_type, bind);
#if YJIT_STATS
    rb_yjit_collect_binding_alloc();
#endif
    return obj;
}


/* :nodoc: */
static VALUE
binding_dup(VALUE self)
{
    VALUE bindval = rb_binding_alloc(rb_cBinding);
    rb_binding_t *src, *dst;
    GetBindingPtr(self, src);
    GetBindingPtr(bindval, dst);
    rb_vm_block_copy(bindval, &dst->block, &src->block);
    RB_OBJ_WRITE(bindval, &dst->pathobj, src->pathobj);
    dst->first_lineno = src->first_lineno;
    return bindval;
}

/* :nodoc: */
static VALUE
binding_clone(VALUE self)
{
    VALUE bindval = binding_dup(self);
    CLONESETUP(bindval, self);
    return bindval;
}

VALUE
rb_binding_new(void)
{
    rb_execution_context_t *ec = GET_EC();
    return rb_vm_make_binding(ec, ec->cfp);
}

/*
 *  call-seq:
 *     binding -> a_binding
 *
 *  Returns a +Binding+ object, describing the variable and
 *  method bindings at the point of call. This object can be used when
 *  calling +eval+ to execute the evaluated command in this
 *  environment. See also the description of class +Binding+.
 *
 *     def get_binding(param)
 *       binding
 *     end
 *     b = get_binding("hello")
 *     eval("param", b)   #=> "hello"
 */

static VALUE
rb_f_binding(VALUE self)
{
    return rb_binding_new();
}

/*
 *  call-seq:
 *     binding.eval(string [, filename [,lineno]])  -> obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>, in the
 *  <em>binding</em>'s context.  If the optional <em>filename</em> and
 *  <em>lineno</em> parameters are present, they will be used when
 *  reporting syntax errors.
 *
 *     def get_binding(param)
 *       binding
 *     end
 *     b = get_binding("hello")
 *     b.eval("param")   #=> "hello"
 */

static VALUE
bind_eval(int argc, VALUE *argv, VALUE bindval)
{
    VALUE args[4];

    rb_scan_args(argc, argv, "12", &args[0], &args[2], &args[3]);
    args[1] = bindval;
    return rb_f_eval(argc+1, args, Qnil /* self will be searched in eval */);
}

static const VALUE *
get_local_variable_ptr(const rb_env_t **envp, ID lid)
{
    const rb_env_t *env = *envp;
    do {
        if (!VM_ENV_FLAGS(env->ep, VM_FRAME_FLAG_CFRAME)) {
            if (VM_ENV_FLAGS(env->ep, VM_ENV_FLAG_ISOLATED)) {
                return NULL;
            }

            const rb_iseq_t *iseq = env->iseq;
            unsigned int i;

            VM_ASSERT(rb_obj_is_iseq((VALUE)iseq));

            for (i=0; i<ISEQ_BODY(iseq)->local_table_size; i++) {
                if (ISEQ_BODY(iseq)->local_table[i] == lid) {
                    if (ISEQ_BODY(iseq)->local_iseq == iseq &&
                            ISEQ_BODY(iseq)->param.flags.has_block &&
                            (unsigned int)ISEQ_BODY(iseq)->param.block_start == i) {
                        const VALUE *ep = env->ep;
                        if (!VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)) {
                            RB_OBJ_WRITE(env, &env->env[i], rb_vm_bh_to_procval(GET_EC(), VM_ENV_BLOCK_HANDLER(ep)));
                            VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
                        }
                    }

                    *envp = env;
                    return &env->env[i];
                }
            }
        }
        else {
            *envp = NULL;
            return NULL;
        }
    } while ((env = rb_vm_env_prev_env(env)) != NULL);

    *envp = NULL;
    return NULL;
}

/*
 * check local variable name.
 * returns ID if it's an already interned symbol, or 0 with setting
 * local name in String to *namep.
 */
static ID
check_local_id(VALUE bindval, volatile VALUE *pname)
{
    ID lid = rb_check_id(pname);
    VALUE name = *pname;

    if (lid) {
        if (!rb_is_local_id(lid)) {
            rb_name_err_raise("wrong local variable name `%1$s' for %2$s",
                              bindval, ID2SYM(lid));
        }
    }
    else {
        if (!rb_is_local_name(name)) {
            rb_name_err_raise("wrong local variable name `%1$s' for %2$s",
                              bindval, name);
        }
        return 0;
    }
    return lid;
}

/*
 *  call-seq:
 *     binding.local_variables -> Array
 *
 *  Returns the names of the binding's local variables as symbols.
 *
 *	def foo
 *  	  a = 1
 *  	  2.times do |n|
 *  	    binding.local_variables #=> [:a, :n]
 *  	  end
 *  	end
 *
 *  This method is the short version of the following code:
 *
 *	binding.eval("local_variables")
 *
 */
static VALUE
bind_local_variables(VALUE bindval)
{
    const rb_binding_t *bind;
    const rb_env_t *env;

    GetBindingPtr(bindval, bind);
    env = VM_ENV_ENVVAL_PTR(vm_block_ep(&bind->block));
    return rb_vm_env_local_variables(env);
}

/*
 *  call-seq:
 *     binding.local_variable_get(symbol) -> obj
 *
 *  Returns the value of the local variable +symbol+.
 *
 *	def foo
 *  	  a = 1
 *  	  binding.local_variable_get(:a) #=> 1
 *  	  binding.local_variable_get(:b) #=> NameError
 *  	end
 *
 *  This method is the short version of the following code:
 *
 *	binding.eval("#{symbol}")
 *
 */
static VALUE
bind_local_variable_get(VALUE bindval, VALUE sym)
{
    ID lid = check_local_id(bindval, &sym);
    const rb_binding_t *bind;
    const VALUE *ptr;
    const rb_env_t *env;

    if (!lid) goto undefined;

    GetBindingPtr(bindval, bind);

    env = VM_ENV_ENVVAL_PTR(vm_block_ep(&bind->block));
    if ((ptr = get_local_variable_ptr(&env, lid)) != NULL) {
        return *ptr;
    }

    sym = ID2SYM(lid);
  undefined:
    rb_name_err_raise("local variable `%1$s' is not defined for %2$s",
                      bindval, sym);
    UNREACHABLE_RETURN(Qundef);
}

/*
 *  call-seq:
 *     binding.local_variable_set(symbol, obj) -> obj
 *
 *  Set local variable named +symbol+ as +obj+.
 *
 *	def foo
 *  	  a = 1
 *  	  bind = binding
 *  	  bind.local_variable_set(:a, 2) # set existing local variable `a'
 *  	  bind.local_variable_set(:b, 3) # create new local variable `b'
 *  	                                 # `b' exists only in binding
 *
 *  	  p bind.local_variable_get(:a)  #=> 2
 *  	  p bind.local_variable_get(:b)  #=> 3
 *  	  p a                            #=> 2
 *  	  p b                            #=> NameError
 *  	end
 *
 *  This method behaves similarly to the following code:
 *
 *    binding.eval("#{symbol} = #{obj}")
 *
 *  if +obj+ can be dumped in Ruby code.
 */
static VALUE
bind_local_variable_set(VALUE bindval, VALUE sym, VALUE val)
{
    ID lid = check_local_id(bindval, &sym);
    rb_binding_t *bind;
    const VALUE *ptr;
    const rb_env_t *env;

    if (!lid) lid = rb_intern_str(sym);

    GetBindingPtr(bindval, bind);
    env = VM_ENV_ENVVAL_PTR(vm_block_ep(&bind->block));
    if ((ptr = get_local_variable_ptr(&env, lid)) == NULL) {
        /* not found. create new env */
        ptr = rb_binding_add_dynavars(bindval, bind, 1, &lid);
        env = VM_ENV_ENVVAL_PTR(vm_block_ep(&bind->block));
    }

#if YJIT_STATS
    rb_yjit_collect_binding_set();
#endif

    RB_OBJ_WRITE(env, ptr, val);

    return val;
}

/*
 *  call-seq:
 *     binding.local_variable_defined?(symbol) -> obj
 *
 *  Returns +true+ if a local variable +symbol+ exists.
 *
 *	def foo
 *  	  a = 1
 *  	  binding.local_variable_defined?(:a) #=> true
 *  	  binding.local_variable_defined?(:b) #=> false
 *  	end
 *
 *  This method is the short version of the following code:
 *
 *	binding.eval("defined?(#{symbol}) == 'local-variable'")
 *
 */
static VALUE
bind_local_variable_defined_p(VALUE bindval, VALUE sym)
{
    ID lid = check_local_id(bindval, &sym);
    const rb_binding_t *bind;
    const rb_env_t *env;

    if (!lid) return Qfalse;

    GetBindingPtr(bindval, bind);
    env = VM_ENV_ENVVAL_PTR(vm_block_ep(&bind->block));
    return RBOOL(get_local_variable_ptr(&env, lid));
}

/*
 *  call-seq:
 *     binding.receiver    -> object
 *
 *  Returns the bound receiver of the binding object.
 */
static VALUE
bind_receiver(VALUE bindval)
{
    const rb_binding_t *bind;
    GetBindingPtr(bindval, bind);
    return vm_block_self(&bind->block);
}

/*
 *  call-seq:
 *     binding.source_location  -> [String, Integer]
 *
 *  Returns the Ruby source filename and line number of the binding object.
 */
static VALUE
bind_location(VALUE bindval)
{
    VALUE loc[2];
    const rb_binding_t *bind;
    GetBindingPtr(bindval, bind);
    loc[0] = pathobj_path(bind->pathobj);
    loc[1] = INT2FIX(bind->first_lineno);

    return rb_ary_new4(2, loc);
}

static VALUE
cfunc_proc_new(VALUE klass, VALUE ifunc)
{
    rb_proc_t *proc;
    cfunc_proc_t *sproc;
    VALUE procval = TypedData_Make_Struct(klass, cfunc_proc_t, &proc_data_type, sproc);
    VALUE *ep;

    proc = &sproc->basic;
    vm_block_type_set(&proc->block, block_type_ifunc);

    *(VALUE **)&proc->block.as.captured.ep = ep = sproc->env + VM_ENV_DATA_SIZE-1;
    ep[VM_ENV_DATA_INDEX_FLAGS]   = VM_FRAME_MAGIC_IFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL | VM_ENV_FLAG_ESCAPED;
    ep[VM_ENV_DATA_INDEX_ME_CREF] = Qfalse;
    ep[VM_ENV_DATA_INDEX_SPECVAL] = VM_BLOCK_HANDLER_NONE;
    ep[VM_ENV_DATA_INDEX_ENV]     = Qundef; /* envval */

    /* self? */
    RB_OBJ_WRITE(procval, &proc->block.as.captured.code.ifunc, ifunc);
    proc->is_lambda = TRUE;
    return procval;
}

static VALUE
sym_proc_new(VALUE klass, VALUE sym)
{
    VALUE procval = rb_proc_alloc(klass);
    rb_proc_t *proc;
    GetProcPtr(procval, proc);

    vm_block_type_set(&proc->block, block_type_symbol);
    proc->is_lambda = TRUE;
    RB_OBJ_WRITE(procval, &proc->block.as.symbol, sym);
    return procval;
}

struct vm_ifunc *
rb_vm_ifunc_new(rb_block_call_func_t func, const void *data, int min_argc, int max_argc)
{
    union {
        struct vm_ifunc_argc argc;
        VALUE packed;
    } arity;

    if (min_argc < UNLIMITED_ARGUMENTS ||
#if SIZEOF_INT * 2 > SIZEOF_VALUE
        min_argc >= (int)(1U << (SIZEOF_VALUE * CHAR_BIT) / 2) ||
#endif
        0) {
        rb_raise(rb_eRangeError, "minimum argument number out of range: %d",
                 min_argc);
    }
    if (max_argc < UNLIMITED_ARGUMENTS ||
#if SIZEOF_INT * 2 > SIZEOF_VALUE
        max_argc >= (int)(1U << (SIZEOF_VALUE * CHAR_BIT) / 2) ||
#endif
        0) {
        rb_raise(rb_eRangeError, "maximum argument number out of range: %d",
                 max_argc);
    }
    arity.argc.min = min_argc;
    arity.argc.max = max_argc;
    VALUE ret = rb_imemo_new(imemo_ifunc, (VALUE)func, (VALUE)data, arity.packed, 0);
    return (struct vm_ifunc *)ret;
}

MJIT_FUNC_EXPORTED VALUE
rb_func_proc_new(rb_block_call_func_t func, VALUE val)
{
    struct vm_ifunc *ifunc = rb_vm_ifunc_proc_new(func, (void *)val);
    return cfunc_proc_new(rb_cProc, (VALUE)ifunc);
}

MJIT_FUNC_EXPORTED VALUE
rb_func_lambda_new(rb_block_call_func_t func, VALUE val, int min_argc, int max_argc)
{
    struct vm_ifunc *ifunc = rb_vm_ifunc_new(func, (void *)val, min_argc, max_argc);
    return cfunc_proc_new(rb_cProc, (VALUE)ifunc);
}

static const char proc_without_block[] = "tried to create Proc object without a block";

static VALUE
proc_new(VALUE klass, int8_t is_lambda, int8_t kernel)
{
    VALUE procval;
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    VALUE block_handler;

    if ((block_handler = rb_vm_frame_block_handler(cfp)) == VM_BLOCK_HANDLER_NONE) {
        rb_raise(rb_eArgError, proc_without_block);
    }

    /* block is in cf */
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_proc:
        procval = VM_BH_TO_PROC(block_handler);

        if (RBASIC_CLASS(procval) == klass) {
            return procval;
        }
        else {
            VALUE newprocval = rb_proc_dup(procval);
            RBASIC_SET_CLASS(newprocval, klass);
            return newprocval;
        }
        break;

      case block_handler_type_symbol:
        return (klass != rb_cProc) ?
          sym_proc_new(klass, VM_BH_TO_SYMBOL(block_handler)) :
          rb_sym_to_proc(VM_BH_TO_SYMBOL(block_handler));
        break;

      case block_handler_type_ifunc:
        return rb_vm_make_proc_lambda(ec, VM_BH_TO_CAPT_BLOCK(block_handler), klass, is_lambda);
      case block_handler_type_iseq:
        {
            const struct rb_captured_block *captured = VM_BH_TO_CAPT_BLOCK(block_handler);
            rb_control_frame_t *last_ruby_cfp = rb_vm_get_ruby_level_next_cfp(ec, cfp);
            if (is_lambda && last_ruby_cfp && vm_cfp_forwarded_bh_p(last_ruby_cfp, block_handler)) {
                is_lambda = false;
            }
            return rb_vm_make_proc_lambda(ec, captured, klass, is_lambda);
        }
    }
    VM_UNREACHABLE(proc_new);
    return Qnil;
}

/*
 *  call-seq:
 *     Proc.new {|...| block } -> a_proc
 *
 *  Creates a new Proc object, bound to the current context.
 *
 *     proc = Proc.new { "hello" }
 *     proc.call   #=> "hello"
 *
 *  Raises ArgumentError if called without a block.
 *
 *     Proc.new    #=> ArgumentError
 */

static VALUE
rb_proc_s_new(int argc, VALUE *argv, VALUE klass)
{
    VALUE block = proc_new(klass, FALSE, FALSE);

    rb_obj_call_init_kw(block, argc, argv, RB_PASS_CALLED_KEYWORDS);
    return block;
}

VALUE
rb_block_proc(void)
{
    return proc_new(rb_cProc, FALSE, FALSE);
}

/*
 * call-seq:
 *   proc   { |...| block }  -> a_proc
 *
 * Equivalent to Proc.new.
 */

static VALUE
f_proc(VALUE _)
{
    return proc_new(rb_cProc, FALSE, TRUE);
}

VALUE
rb_block_lambda(void)
{
    return proc_new(rb_cProc, TRUE, FALSE);
}

static void
f_lambda_warn(void)
{
    rb_control_frame_t *cfp = GET_EC()->cfp;
    VALUE block_handler = rb_vm_frame_block_handler(cfp);

    if (block_handler != VM_BLOCK_HANDLER_NONE) {
        switch (vm_block_handler_type(block_handler)) {
          case block_handler_type_iseq:
            if (RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp)->ep == VM_BH_TO_ISEQ_BLOCK(block_handler)->ep) {
                return;
            }
            break;
          case block_handler_type_symbol:
            return;
          case block_handler_type_proc:
            if (rb_proc_lambda_p(VM_BH_TO_PROC(block_handler))) {
                return;
            }
            break;
          case block_handler_type_ifunc:
            break;
        }
    }

    rb_warn_deprecated("lambda without a literal block", "the proc without lambda");
}

/*
 * call-seq:
 *   lambda { |...| block }  -> a_proc
 *
 * Equivalent to Proc.new, except the resulting Proc objects check the
 * number of parameters passed when called.
 */

static VALUE
f_lambda(VALUE _)
{
    f_lambda_warn();
    return rb_block_lambda();
}

/*  Document-method: Proc#===
 *
 *  call-seq:
 *     proc === obj   -> result_of_proc
 *
 *  Invokes the block with +obj+ as the proc's parameter like Proc#call.
 *  This allows a proc object to be the target of a +when+ clause
 *  in a case statement.
 */

/* CHECKME: are the argument checking semantics correct? */

/*
 *  Document-method: Proc#[]
 *  Document-method: Proc#call
 *  Document-method: Proc#yield
 *
 *  call-seq:
 *     prc.call(params,...)   -> obj
 *     prc[params,...]        -> obj
 *     prc.(params,...)       -> obj
 *     prc.yield(params,...)  -> obj
 *
 *  Invokes the block, setting the block's parameters to the values in
 *  <i>params</i> using something close to method calling semantics.
 *  Returns the value of the last expression evaluated in the block.
 *
 *     a_proc = Proc.new {|scalar, *values| values.map {|value| value*scalar } }
 *     a_proc.call(9, 1, 2, 3)    #=> [9, 18, 27]
 *     a_proc[9, 1, 2, 3]         #=> [9, 18, 27]
 *     a_proc.(9, 1, 2, 3)        #=> [9, 18, 27]
 *     a_proc.yield(9, 1, 2, 3)   #=> [9, 18, 27]
 *
 *  Note that <code>prc.()</code> invokes <code>prc.call()</code> with
 *  the parameters given.  It's syntactic sugar to hide "call".
 *
 *  For procs created using #lambda or <code>->()</code> an error is
 *  generated if the wrong number of parameters are passed to the
 *  proc.  For procs created using Proc.new or Kernel.proc, extra
 *  parameters are silently discarded and missing parameters are set
 *  to +nil+.
 *
 *     a_proc = proc {|a,b| [a,b] }
 *     a_proc.call(1)   #=> [1, nil]
 *
 *     a_proc = lambda {|a,b| [a,b] }
 *     a_proc.call(1)   # ArgumentError: wrong number of arguments (given 1, expected 2)
 *
 *  See also Proc#lambda?.
 */
#if 0
static VALUE
proc_call(int argc, VALUE *argv, VALUE procval)
{
    /* removed */
}
#endif

#if SIZEOF_LONG > SIZEOF_INT
static inline int
check_argc(long argc)
{
    if (argc > INT_MAX || argc < 0) {
        rb_raise(rb_eArgError, "too many arguments (%lu)",
                 (unsigned long)argc);
    }
    return (int)argc;
}
#else
#define check_argc(argc) (argc)
#endif

VALUE
rb_proc_call_kw(VALUE self, VALUE args, int kw_splat)
{
    VALUE vret;
    rb_proc_t *proc;
    int argc = check_argc(RARRAY_LEN(args));
    const VALUE *argv = RARRAY_CONST_PTR(args);
    GetProcPtr(self, proc);
    vret = rb_vm_invoke_proc(GET_EC(), proc, argc, argv,
                             kw_splat, VM_BLOCK_HANDLER_NONE);
    RB_GC_GUARD(self);
    RB_GC_GUARD(args);
    return vret;
}

VALUE
rb_proc_call(VALUE self, VALUE args)
{
    return rb_proc_call_kw(self, args, RB_NO_KEYWORDS);
}

static VALUE
proc_to_block_handler(VALUE procval)
{
    return NIL_P(procval) ? VM_BLOCK_HANDLER_NONE : procval;
}

VALUE
rb_proc_call_with_block_kw(VALUE self, int argc, const VALUE *argv, VALUE passed_procval, int kw_splat)
{
    rb_execution_context_t *ec = GET_EC();
    VALUE vret;
    rb_proc_t *proc;
    GetProcPtr(self, proc);
    vret = rb_vm_invoke_proc(ec, proc, argc, argv, kw_splat, proc_to_block_handler(passed_procval));
    RB_GC_GUARD(self);
    return vret;
}

VALUE
rb_proc_call_with_block(VALUE self, int argc, const VALUE *argv, VALUE passed_procval)
{
    return rb_proc_call_with_block_kw(self, argc, argv, passed_procval, RB_NO_KEYWORDS);
}


/*
 *  call-seq:
 *     prc.arity -> integer
 *
 *  Returns the number of mandatory arguments. If the block
 *  is declared to take no arguments, returns 0. If the block is known
 *  to take exactly n arguments, returns n.
 *  If the block has optional arguments, returns -n-1, where n is the
 *  number of mandatory arguments, with the exception for blocks that
 *  are not lambdas and have only a finite number of optional arguments;
 *  in this latter case, returns n.
 *  Keyword arguments will be considered as a single additional argument,
 *  that argument being mandatory if any keyword argument is mandatory.
 *  A #proc with no argument declarations is the same as a block
 *  declaring <code>||</code> as its arguments.
 *
 *     proc {}.arity                  #=>  0
 *     proc { || }.arity              #=>  0
 *     proc { |a| }.arity             #=>  1
 *     proc { |a, b| }.arity          #=>  2
 *     proc { |a, b, c| }.arity       #=>  3
 *     proc { |*a| }.arity            #=> -1
 *     proc { |a, *b| }.arity         #=> -2
 *     proc { |a, *b, c| }.arity      #=> -3
 *     proc { |x:, y:, z:0| }.arity   #=>  1
 *     proc { |*a, x:, y:0| }.arity   #=> -2
 *
 *     proc   { |a=0| }.arity         #=>  0
 *     lambda { |a=0| }.arity         #=> -1
 *     proc   { |a=0, b| }.arity      #=>  1
 *     lambda { |a=0, b| }.arity      #=> -2
 *     proc   { |a=0, b=0| }.arity    #=>  0
 *     lambda { |a=0, b=0| }.arity    #=> -1
 *     proc   { |a, b=0| }.arity      #=>  1
 *     lambda { |a, b=0| }.arity      #=> -2
 *     proc   { |(a, b), c=0| }.arity #=>  1
 *     lambda { |(a, b), c=0| }.arity #=> -2
 *     proc   { |a, x:0, y:0| }.arity #=>  1
 *     lambda { |a, x:0, y:0| }.arity #=> -2
 */

static VALUE
proc_arity(VALUE self)
{
    int arity = rb_proc_arity(self);
    return INT2FIX(arity);
}

static inline int
rb_iseq_min_max_arity(const rb_iseq_t *iseq, int *max)
{
    *max = ISEQ_BODY(iseq)->param.flags.has_rest == FALSE ?
      ISEQ_BODY(iseq)->param.lead_num + ISEQ_BODY(iseq)->param.opt_num + ISEQ_BODY(iseq)->param.post_num +
      (ISEQ_BODY(iseq)->param.flags.has_kw == TRUE || ISEQ_BODY(iseq)->param.flags.has_kwrest == TRUE)
      : UNLIMITED_ARGUMENTS;
    return ISEQ_BODY(iseq)->param.lead_num + ISEQ_BODY(iseq)->param.post_num + (ISEQ_BODY(iseq)->param.flags.has_kw && ISEQ_BODY(iseq)->param.keyword->required_num > 0);
}

static int
rb_vm_block_min_max_arity(const struct rb_block *block, int *max)
{
  again:
    switch (vm_block_type(block)) {
      case block_type_iseq:
        return rb_iseq_min_max_arity(rb_iseq_check(block->as.captured.code.iseq), max);
      case block_type_proc:
        block = vm_proc_block(block->as.proc);
        goto again;
      case block_type_ifunc:
        {
            const struct vm_ifunc *ifunc = block->as.captured.code.ifunc;
            if (IS_METHOD_PROC_IFUNC(ifunc)) {
                /* e.g. method(:foo).to_proc.arity */
                return method_min_max_arity((VALUE)ifunc->data, max);
            }
            *max = ifunc->argc.max;
            return ifunc->argc.min;
        }
      case block_type_symbol:
        *max = UNLIMITED_ARGUMENTS;
        return 1;
    }
    *max = UNLIMITED_ARGUMENTS;
    return 0;
}

/*
 * Returns the number of required parameters and stores the maximum
 * number of parameters in max, or UNLIMITED_ARGUMENTS if no max.
 * For non-lambda procs, the maximum is the number of non-ignored
 * parameters even though there is no actual limit to the number of parameters
 */
static int
rb_proc_min_max_arity(VALUE self, int *max)
{
    rb_proc_t *proc;
    GetProcPtr(self, proc);
    return rb_vm_block_min_max_arity(&proc->block, max);
}

int
rb_proc_arity(VALUE self)
{
    rb_proc_t *proc;
    int max, min;
    GetProcPtr(self, proc);
    min = rb_vm_block_min_max_arity(&proc->block, &max);
    return (proc->is_lambda ? min == max : max != UNLIMITED_ARGUMENTS) ? min : -min-1;
}

static void
block_setup(struct rb_block *block, VALUE block_handler)
{
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_iseq:
        block->type = block_type_iseq;
        block->as.captured = *VM_BH_TO_ISEQ_BLOCK(block_handler);
        break;
      case block_handler_type_ifunc:
        block->type = block_type_ifunc;
        block->as.captured = *VM_BH_TO_IFUNC_BLOCK(block_handler);
        break;
      case block_handler_type_symbol:
        block->type = block_type_symbol;
        block->as.symbol = VM_BH_TO_SYMBOL(block_handler);
        break;
      case block_handler_type_proc:
        block->type = block_type_proc;
        block->as.proc = VM_BH_TO_PROC(block_handler);
    }
}

int
rb_block_pair_yield_optimizable(void)
{
    int min, max;
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    VALUE block_handler = rb_vm_frame_block_handler(cfp);
    struct rb_block block;

    if (block_handler == VM_BLOCK_HANDLER_NONE) {
        rb_raise(rb_eArgError, "no block given");
    }

    block_setup(&block, block_handler);
    min = rb_vm_block_min_max_arity(&block, &max);

    switch (vm_block_type(&block)) {
      case block_handler_type_symbol:
        return 0;

      case block_handler_type_proc:
        {
            VALUE procval = block_handler;
            rb_proc_t *proc;
            GetProcPtr(procval, proc);
            if (proc->is_lambda) return 0;
            if (min != max) return 0;
            return min > 1;
        }

      default:
        return min > 1;
    }
}

int
rb_block_arity(void)
{
    int min, max;
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    VALUE block_handler = rb_vm_frame_block_handler(cfp);
    struct rb_block block;

    if (block_handler == VM_BLOCK_HANDLER_NONE) {
        rb_raise(rb_eArgError, "no block given");
    }

    block_setup(&block, block_handler);

    switch (vm_block_type(&block)) {
      case block_handler_type_symbol:
        return -1;

      case block_handler_type_proc:
        return rb_proc_arity(block_handler);

      default:
        min = rb_vm_block_min_max_arity(&block, &max);
        return max != UNLIMITED_ARGUMENTS ? min : -min-1;
    }
}

int
rb_block_min_max_arity(int *max)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    VALUE block_handler = rb_vm_frame_block_handler(cfp);
    struct rb_block block;

    if (block_handler == VM_BLOCK_HANDLER_NONE) {
        rb_raise(rb_eArgError, "no block given");
    }

    block_setup(&block, block_handler);
    return rb_vm_block_min_max_arity(&block, max);
}

const rb_iseq_t *
rb_proc_get_iseq(VALUE self, int *is_proc)
{
    const rb_proc_t *proc;
    const struct rb_block *block;

    GetProcPtr(self, proc);
    block = &proc->block;
    if (is_proc) *is_proc = !proc->is_lambda;

    switch (vm_block_type(block)) {
      case block_type_iseq:
        return rb_iseq_check(block->as.captured.code.iseq);
      case block_type_proc:
        return rb_proc_get_iseq(block->as.proc, is_proc);
      case block_type_ifunc:
        {
            const struct vm_ifunc *ifunc = block->as.captured.code.ifunc;
            if (IS_METHOD_PROC_IFUNC(ifunc)) {
                /* method(:foo).to_proc */
                if (is_proc) *is_proc = 0;
                return rb_method_iseq((VALUE)ifunc->data);
            }
            else {
                return NULL;
            }
        }
      case block_type_symbol:
        return NULL;
    }

    VM_UNREACHABLE(rb_proc_get_iseq);
    return NULL;
}

/* call-seq:
 *   prc == other -> true or false
 *   prc.eql?(other) -> true or false
 *
 * Two procs are the same if, and only if, they were created from the same code block.
 *
 *   def return_block(&block)
 *     block
 *   end
 *
 *   def pass_block_twice(&block)
 *     [return_block(&block), return_block(&block)]
 *   end
 *
 *   block1, block2 = pass_block_twice { puts 'test' }
 *   # Blocks might be instantiated into Proc's lazily, so they may, or may not,
 *   # be the same object.
 *   # But they are produced from the same code block, so they are equal
 *   block1 == block2
 *   #=> true
 *
 *   # Another Proc will never be equal, even if the code is the "same"
 *   block1 == proc { puts 'test' }
 *   #=> false
 *
 */
static VALUE
proc_eq(VALUE self, VALUE other)
{
    const rb_proc_t *self_proc, *other_proc;
    const struct rb_block *self_block, *other_block;

    if (rb_obj_class(self) !=  rb_obj_class(other)) {
        return Qfalse;
    }

    GetProcPtr(self, self_proc);
    GetProcPtr(other, other_proc);

    if (self_proc->is_from_method != other_proc->is_from_method ||
            self_proc->is_lambda != other_proc->is_lambda) {
        return Qfalse;
    }

    self_block = &self_proc->block;
    other_block = &other_proc->block;

    if (vm_block_type(self_block) != vm_block_type(other_block)) {
        return Qfalse;
    }

    switch (vm_block_type(self_block)) {
      case block_type_iseq:
        if (self_block->as.captured.ep != \
                other_block->as.captured.ep ||
                self_block->as.captured.code.iseq != \
                other_block->as.captured.code.iseq) {
            return Qfalse;
        }
        break;
      case block_type_ifunc:
        if (self_block->as.captured.ep != \
                other_block->as.captured.ep ||
                self_block->as.captured.code.ifunc != \
                other_block->as.captured.code.ifunc) {
            return Qfalse;
        }
        break;
      case block_type_proc:
        if (self_block->as.proc != other_block->as.proc) {
            return Qfalse;
        }
        break;
      case block_type_symbol:
        if (self_block->as.symbol != other_block->as.symbol) {
            return Qfalse;
        }
        break;
    }

    return Qtrue;
}

static VALUE
iseq_location(const rb_iseq_t *iseq)
{
    VALUE loc[2];

    if (!iseq) return Qnil;
    rb_iseq_check(iseq);
    loc[0] = rb_iseq_path(iseq);
    loc[1] = RB_INT2NUM(ISEQ_BODY(iseq)->location.first_lineno);

    return rb_ary_new4(2, loc);
}

MJIT_FUNC_EXPORTED VALUE
rb_iseq_location(const rb_iseq_t *iseq)
{
    return iseq_location(iseq);
}

/*
 * call-seq:
 *    prc.source_location  -> [String, Integer]
 *
 * Returns the Ruby source filename and line number containing this proc
 * or +nil+ if this proc was not defined in Ruby (i.e. native).
 */

VALUE
rb_proc_location(VALUE self)
{
    return iseq_location(rb_proc_get_iseq(self, 0));
}

VALUE
rb_unnamed_parameters(int arity)
{
    VALUE a, param = rb_ary_new2((arity < 0) ? -arity : arity);
    int n = (arity < 0) ? ~arity : arity;
    ID req, rest;
    CONST_ID(req, "req");
    a = rb_ary_new3(1, ID2SYM(req));
    OBJ_FREEZE(a);
    for (; n; --n) {
        rb_ary_push(param, a);
    }
    if (arity < 0) {
        CONST_ID(rest, "rest");
        rb_ary_store(param, ~arity, rb_ary_new3(1, ID2SYM(rest)));
    }
    return param;
}

/*
 * call-seq:
 *    prc.parameters(lambda: nil)  -> array
 *
 * Returns the parameter information of this proc.  If the lambda
 * keyword is provided and not nil, treats the proc as a lambda if
 * true and as a non-lambda if false.
 *
 *    prc = proc{|x, y=42, *other|}
 *    prc.parameters  #=> [[:opt, :x], [:opt, :y], [:rest, :other]]
 *    prc = lambda{|x, y=42, *other|}
 *    prc.parameters  #=> [[:req, :x], [:opt, :y], [:rest, :other]]
 *    prc = proc{|x, y=42, *other|}
 *    prc.parameters(lambda: true)  #=> [[:req, :x], [:opt, :y], [:rest, :other]]
 *    prc = lambda{|x, y=42, *other|}
 *    prc.parameters(lambda: false) #=> [[:opt, :x], [:opt, :y], [:rest, :other]]
 */

static VALUE
rb_proc_parameters(int argc, VALUE *argv, VALUE self)
{
    static ID keyword_ids[1];
    VALUE opt, lambda;
    VALUE kwargs[1];
    int is_proc ;
    const rb_iseq_t *iseq;

    iseq = rb_proc_get_iseq(self, &is_proc);

    if (!keyword_ids[0]) {
        CONST_ID(keyword_ids[0], "lambda");
    }

    rb_scan_args(argc, argv, "0:", &opt);
    if (!NIL_P(opt)) {
        rb_get_kwargs(opt, keyword_ids, 0, 1, kwargs);
        lambda = kwargs[0];
        if (!NIL_P(lambda)) {
            is_proc = !RTEST(lambda);
        }
    }

    if (!iseq) {
        return rb_unnamed_parameters(rb_proc_arity(self));
    }
    return rb_iseq_parameters(iseq, is_proc);
}

st_index_t
rb_hash_proc(st_index_t hash, VALUE prc)
{
    rb_proc_t *proc;
    GetProcPtr(prc, proc);
    hash = rb_hash_uint(hash, (st_index_t)proc->block.as.captured.code.val);
    hash = rb_hash_uint(hash, (st_index_t)proc->block.as.captured.self);
    return rb_hash_uint(hash, (st_index_t)proc->block.as.captured.ep);
}


/*
 *  call-seq:
 *    to_proc
 *
 *  Returns a Proc object which calls the method with name of +self+
 *  on the first parameter and passes the remaining parameters to the method.
 *
 *    proc = :to_s.to_proc   # => #<Proc:0x000001afe0e48680(&:to_s) (lambda)>
 *    proc.call(1000)        # => "1000"
 *    proc.call(1000, 16)    # => "3e8"
 *    (1..3).collect(&:to_s) # => ["1", "2", "3"]
 *
 */

MJIT_FUNC_EXPORTED VALUE
rb_sym_to_proc(VALUE sym)
{
    static VALUE sym_proc_cache = Qfalse;
    enum {SYM_PROC_CACHE_SIZE = 67};
    VALUE proc;
    long index;
    ID id;

    if (!sym_proc_cache) {
        sym_proc_cache = rb_ary_hidden_new(SYM_PROC_CACHE_SIZE * 2);
        rb_gc_register_mark_object(sym_proc_cache);
        rb_ary_store(sym_proc_cache, SYM_PROC_CACHE_SIZE*2 - 1, Qnil);
    }

    id = SYM2ID(sym);
    index = (id % SYM_PROC_CACHE_SIZE) << 1;

    if (RARRAY_AREF(sym_proc_cache, index) == sym) {
        return RARRAY_AREF(sym_proc_cache, index + 1);
    }
    else {
        proc = sym_proc_new(rb_cProc, ID2SYM(id));
        RARRAY_ASET(sym_proc_cache, index, sym);
        RARRAY_ASET(sym_proc_cache, index + 1, proc);
        return proc;
    }
}

/*
 * call-seq:
 *   prc.hash   ->  integer
 *
 * Returns a hash value corresponding to proc body.
 *
 * See also Object#hash.
 */

static VALUE
proc_hash(VALUE self)
{
    st_index_t hash;
    hash = rb_hash_start(0);
    hash = rb_hash_proc(hash, self);
    hash = rb_hash_end(hash);
    return ST2FIX(hash);
}

VALUE
rb_block_to_s(VALUE self, const struct rb_block *block, const char *additional_info)
{
    VALUE cname = rb_obj_class(self);
    VALUE str = rb_sprintf("#<%"PRIsVALUE":", cname);

  again:
    switch (vm_block_type(block)) {
      case block_type_proc:
        block = vm_proc_block(block->as.proc);
        goto again;
      case block_type_iseq:
        {
            const rb_iseq_t *iseq = rb_iseq_check(block->as.captured.code.iseq);
            rb_str_catf(str, "%p %"PRIsVALUE":%d", (void *)self,
                        rb_iseq_path(iseq),
                        ISEQ_BODY(iseq)->location.first_lineno);
        }
        break;
      case block_type_symbol:
        rb_str_catf(str, "%p(&%+"PRIsVALUE")", (void *)self, block->as.symbol);
        break;
      case block_type_ifunc:
        rb_str_catf(str, "%p", (void *)block->as.captured.code.ifunc);
        break;
    }

    if (additional_info) rb_str_cat_cstr(str, additional_info);
    rb_str_cat_cstr(str, ">");
    return str;
}

/*
 * call-seq:
 *   prc.to_s   -> string
 *
 * Returns the unique identifier for this proc, along with
 * an indication of where the proc was defined.
 */

static VALUE
proc_to_s(VALUE self)
{
    const rb_proc_t *proc;
    GetProcPtr(self, proc);
    return rb_block_to_s(self, &proc->block, proc->is_lambda ? " (lambda)" : NULL);
}

/*
 *  call-seq:
 *     prc.to_proc -> proc
 *
 *  Part of the protocol for converting objects to Proc objects.
 *  Instances of class Proc simply return themselves.
 */

static VALUE
proc_to_proc(VALUE self)
{
    return self;
}

static void
bm_mark(void *ptr)
{
    struct METHOD *data = ptr;
    rb_gc_mark_movable(data->recv);
    rb_gc_mark_movable(data->klass);
    rb_gc_mark_movable(data->iclass);
    rb_gc_mark_movable(data->owner);
    rb_gc_mark_movable((VALUE)data->me);
}

static void
bm_compact(void *ptr)
{
    struct METHOD *data = ptr;
    UPDATE_REFERENCE(data->recv);
    UPDATE_REFERENCE(data->klass);
    UPDATE_REFERENCE(data->iclass);
    UPDATE_REFERENCE(data->owner);
    UPDATE_TYPED_REFERENCE(rb_method_entry_t *, data->me);
}

static size_t
bm_memsize(const void *ptr)
{
    return sizeof(struct METHOD);
}

static const rb_data_type_t method_data_type = {
    "method",
    {
        bm_mark,
        RUBY_TYPED_DEFAULT_FREE,
        bm_memsize,
        bm_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE
rb_obj_is_method(VALUE m)
{
    return RBOOL(rb_typeddata_is_kind_of(m, &method_data_type));
}

static int
respond_to_missing_p(VALUE klass, VALUE obj, VALUE sym, int scope)
{
    /* TODO: merge with obj_respond_to() */
    ID rmiss = idRespond_to_missing;

    if (UNDEF_P(obj)) return 0;
    if (rb_method_basic_definition_p(klass, rmiss)) return 0;
    return RTEST(rb_funcall(obj, rmiss, 2, sym, RBOOL(!scope)));
}


static VALUE
mnew_missing(VALUE klass, VALUE obj, ID id, VALUE mclass)
{
    struct METHOD *data;
    VALUE method = TypedData_Make_Struct(mclass, struct METHOD, &method_data_type, data);
    rb_method_entry_t *me;
    rb_method_definition_t *def;

    RB_OBJ_WRITE(method, &data->recv, obj);
    RB_OBJ_WRITE(method, &data->klass, klass);
    RB_OBJ_WRITE(method, &data->owner, klass);

    def = ZALLOC(rb_method_definition_t);
    def->type = VM_METHOD_TYPE_MISSING;
    def->original_id = id;

    me = rb_method_entry_create(id, klass, METHOD_VISI_UNDEF, def);

    RB_OBJ_WRITE(method, &data->me, me);

    return method;
}

static VALUE
mnew_missing_by_name(VALUE klass, VALUE obj, VALUE *name, int scope, VALUE mclass)
{
    VALUE vid = rb_str_intern(*name);
    *name = vid;
    if (!respond_to_missing_p(klass, obj, vid, scope)) return Qfalse;
    return mnew_missing(klass, obj, SYM2ID(vid), mclass);
}

static VALUE
mnew_internal(const rb_method_entry_t *me, VALUE klass, VALUE iclass,
              VALUE obj, ID id, VALUE mclass, int scope, int error)
{
    struct METHOD *data;
    VALUE method;
    const rb_method_entry_t *original_me = me;
    rb_method_visibility_t visi = METHOD_VISI_UNDEF;

  again:
    if (UNDEFINED_METHOD_ENTRY_P(me)) {
        if (respond_to_missing_p(klass, obj, ID2SYM(id), scope)) {
            return mnew_missing(klass, obj, id, mclass);
        }
        if (!error) return Qnil;
        rb_print_undef(klass, id, METHOD_VISI_UNDEF);
    }
    if (visi == METHOD_VISI_UNDEF) {
        visi = METHOD_ENTRY_VISI(me);
        RUBY_ASSERT(visi != METHOD_VISI_UNDEF); /* !UNDEFINED_METHOD_ENTRY_P(me) */
        if (scope && (visi != METHOD_VISI_PUBLIC)) {
            if (!error) return Qnil;
            rb_print_inaccessible(klass, id, visi);
        }
    }
    if (me->def->type == VM_METHOD_TYPE_ZSUPER) {
        if (me->defined_class) {
            VALUE klass = RCLASS_SUPER(RCLASS_ORIGIN(me->defined_class));
            id = me->def->original_id;
            me = (rb_method_entry_t *)rb_callable_method_entry_with_refinements(klass, id, &iclass);
        }
        else {
            VALUE klass = RCLASS_SUPER(RCLASS_ORIGIN(me->owner));
            id = me->def->original_id;
            me = rb_method_entry_without_refinements(klass, id, &iclass);
        }
        goto again;
    }

    method = TypedData_Make_Struct(mclass, struct METHOD, &method_data_type, data);

    RB_OBJ_WRITE(method, &data->recv, obj);
    RB_OBJ_WRITE(method, &data->klass, klass);
    RB_OBJ_WRITE(method, &data->iclass, iclass);
    RB_OBJ_WRITE(method, &data->owner, original_me->owner);
    RB_OBJ_WRITE(method, &data->me, me);

    return method;
}

static VALUE
mnew_from_me(const rb_method_entry_t *me, VALUE klass, VALUE iclass,
             VALUE obj, ID id, VALUE mclass, int scope)
{
    return mnew_internal(me, klass, iclass, obj, id, mclass, scope, TRUE);
}

static VALUE
mnew_callable(VALUE klass, VALUE obj, ID id, VALUE mclass, int scope)
{
    const rb_method_entry_t *me;
    VALUE iclass = Qnil;

    ASSUME(!UNDEF_P(obj));
    me = (rb_method_entry_t *)rb_callable_method_entry_with_refinements(klass, id, &iclass);
    return mnew_from_me(me, klass, iclass, obj, id, mclass, scope);
}

static VALUE
mnew_unbound(VALUE klass, ID id, VALUE mclass, int scope)
{
    const rb_method_entry_t *me;
    VALUE iclass = Qnil;

    me = rb_method_entry_with_refinements(klass, id, &iclass);
    return mnew_from_me(me, klass, iclass, Qundef, id, mclass, scope);
}

static inline VALUE
method_entry_defined_class(const rb_method_entry_t *me)
{
    VALUE defined_class = me->defined_class;
    return defined_class ? defined_class : me->owner;
}

/**********************************************************************
 *
 * Document-class: Method
 *
 *  Method objects are created by Object#method, and are associated
 *  with a particular object (not just with a class).  They may be
 *  used to invoke the method within the object, and as a block
 *  associated with an iterator.  They may also be unbound from one
 *  object (creating an UnboundMethod) and bound to another.
 *
 *     class Thing
 *       def square(n)
 *         n*n
 *       end
 *     end
 *     thing = Thing.new
 *     meth  = thing.method(:square)
 *
 *     meth.call(9)                 #=> 81
 *     [ 1, 2, 3 ].collect(&meth)   #=> [1, 4, 9]
 *
 *     [ 1, 2, 3 ].each(&method(:puts)) #=> prints 1, 2, 3
 *
 *     require 'date'
 *     %w[2017-03-01 2017-03-02].collect(&Date.method(:parse))
 *     #=> [#<Date: 2017-03-01 ((2457814j,0s,0n),+0s,2299161j)>, #<Date: 2017-03-02 ((2457815j,0s,0n),+0s,2299161j)>]
 */

/*
 * call-seq:
 *   meth.eql?(other_meth)  -> true or false
 *   meth == other_meth  -> true or false
 *
 * Two method objects are equal if they are bound to the same
 * object and refer to the same method definition and the classes
 * defining the methods are the same class or module.
 */

static VALUE
method_eq(VALUE method, VALUE other)
{
    struct METHOD *m1, *m2;
    VALUE klass1, klass2;

    if (!rb_obj_is_method(other))
        return Qfalse;
    if (CLASS_OF(method) != CLASS_OF(other))
        return Qfalse;

    Check_TypedStruct(method, &method_data_type);
    m1 = (struct METHOD *)DATA_PTR(method);
    m2 = (struct METHOD *)DATA_PTR(other);

    klass1 = method_entry_defined_class(m1->me);
    klass2 = method_entry_defined_class(m2->me);

    if (!rb_method_entry_eq(m1->me, m2->me) ||
        klass1 != klass2 ||
        m1->klass != m2->klass ||
        m1->recv != m2->recv) {
        return Qfalse;
    }

    return Qtrue;
}

/*
 * call-seq:
 *    meth.hash   -> integer
 *
 * Returns a hash value corresponding to the method object.
 *
 * See also Object#hash.
 */

static VALUE
method_hash(VALUE method)
{
    struct METHOD *m;
    st_index_t hash;

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, m);
    hash = rb_hash_start((st_index_t)m->recv);
    hash = rb_hash_method_entry(hash, m->me);
    hash = rb_hash_end(hash);

    return ST2FIX(hash);
}

/*
 *  call-seq:
 *     meth.unbind    -> unbound_method
 *
 *  Dissociates <i>meth</i> from its current receiver. The resulting
 *  UnboundMethod can subsequently be bound to a new object of the
 *  same class (see UnboundMethod).
 */

static VALUE
method_unbind(VALUE obj)
{
    VALUE method;
    struct METHOD *orig, *data;

    TypedData_Get_Struct(obj, struct METHOD, &method_data_type, orig);
    method = TypedData_Make_Struct(rb_cUnboundMethod, struct METHOD,
                                   &method_data_type, data);
    RB_OBJ_WRITE(method, &data->recv, Qundef);
    RB_OBJ_WRITE(method, &data->klass, orig->klass);
    RB_OBJ_WRITE(method, &data->iclass, orig->iclass);
    RB_OBJ_WRITE(method, &data->owner, orig->owner);
    RB_OBJ_WRITE(method, &data->me, rb_method_entry_clone(orig->me));

    return method;
}

/*
 *  call-seq:
 *     meth.receiver    -> object
 *
 *  Returns the bound receiver of the method object.
 *
 *    (1..3).method(:map).receiver # => 1..3
 */

static VALUE
method_receiver(VALUE obj)
{
    struct METHOD *data;

    TypedData_Get_Struct(obj, struct METHOD, &method_data_type, data);
    return data->recv;
}

/*
 *  call-seq:
 *     meth.name    -> symbol
 *
 *  Returns the name of the method.
 */

static VALUE
method_name(VALUE obj)
{
    struct METHOD *data;

    TypedData_Get_Struct(obj, struct METHOD, &method_data_type, data);
    return ID2SYM(data->me->called_id);
}

/*
 *  call-seq:
 *     meth.original_name    -> symbol
 *
 *  Returns the original name of the method.
 *
 *    class C
 *      def foo; end
 *      alias bar foo
 *    end
 *    C.instance_method(:bar).original_name # => :foo
 */

static VALUE
method_original_name(VALUE obj)
{
    struct METHOD *data;

    TypedData_Get_Struct(obj, struct METHOD, &method_data_type, data);
    return ID2SYM(data->me->def->original_id);
}

/*
 *  call-seq:
 *     meth.owner    -> class_or_module
 *
 *  Returns the class or module on which this method is defined.
 *  In other words,
 *
 *    meth.owner.instance_methods(false).include?(meth.name) # => true
 *
 *  holds as long as the method is not removed/undefined/replaced,
 *  (with private_instance_methods instead of instance_methods if the method
 *  is private).
 *
 *  See also Method#receiver.
 *
 *    (1..3).method(:map).owner #=> Enumerable
 */

static VALUE
method_owner(VALUE obj)
{
    struct METHOD *data;
    TypedData_Get_Struct(obj, struct METHOD, &method_data_type, data);
    return data->owner;
}

void
rb_method_name_error(VALUE klass, VALUE str)
{
#define MSG(s) rb_fstring_lit("undefined method `%1$s' for"s" `%2$s'")
    VALUE c = klass;
    VALUE s = Qundef;

    if (FL_TEST(c, FL_SINGLETON)) {
        VALUE obj = rb_ivar_get(klass, attached);

        switch (BUILTIN_TYPE(obj)) {
          case T_MODULE:
          case T_CLASS:
            c = obj;
            break;
          default:
            break;
        }
    }
    else if (RB_TYPE_P(c, T_MODULE)) {
        s = MSG(" module");
    }
    if (UNDEF_P(s)) {
        s = MSG(" class");
    }
    rb_name_err_raise_str(s, c, str);
#undef MSG
}

static VALUE
obj_method(VALUE obj, VALUE vid, int scope)
{
    ID id = rb_check_id(&vid);
    const VALUE klass = CLASS_OF(obj);
    const VALUE mclass = rb_cMethod;

    if (!id) {
        VALUE m = mnew_missing_by_name(klass, obj, &vid, scope, mclass);
        if (m) return m;
        rb_method_name_error(klass, vid);
    }
    return mnew_callable(klass, obj, id, mclass, scope);
}

/*
 *  call-seq:
 *     obj.method(sym)    -> method
 *
 *  Looks up the named method as a receiver in <i>obj</i>, returning a
 *  Method object (or raising NameError). The Method object acts as a
 *  closure in <i>obj</i>'s object instance, so instance variables and
 *  the value of <code>self</code> remain available.
 *
 *     class Demo
 *       def initialize(n)
 *         @iv = n
 *       end
 *       def hello()
 *         "Hello, @iv = #{@iv}"
 *       end
 *     end
 *
 *     k = Demo.new(99)
 *     m = k.method(:hello)
 *     m.call   #=> "Hello, @iv = 99"
 *
 *     l = Demo.new('Fred')
 *     m = l.method("hello")
 *     m.call   #=> "Hello, @iv = Fred"
 *
 *  Note that Method implements <code>to_proc</code> method, which
 *  means it can be used with iterators.
 *
 *     [ 1, 2, 3 ].each(&method(:puts)) # => prints 3 lines to stdout
 *
 *     out = File.open('test.txt', 'w')
 *     [ 1, 2, 3 ].each(&out.method(:puts)) # => prints 3 lines to file
 *
 *     require 'date'
 *     %w[2017-03-01 2017-03-02].collect(&Date.method(:parse))
 *     #=> [#<Date: 2017-03-01 ((2457814j,0s,0n),+0s,2299161j)>, #<Date: 2017-03-02 ((2457815j,0s,0n),+0s,2299161j)>]
 */

VALUE
rb_obj_method(VALUE obj, VALUE vid)
{
    return obj_method(obj, vid, FALSE);
}

/*
 *  call-seq:
 *     obj.public_method(sym)    -> method
 *
 *  Similar to _method_, searches public method only.
 */

VALUE
rb_obj_public_method(VALUE obj, VALUE vid)
{
    return obj_method(obj, vid, TRUE);
}

/*
 *  call-seq:
 *     obj.singleton_method(sym)    -> method
 *
 *  Similar to _method_, searches singleton method only.
 *
 *     class Demo
 *       def initialize(n)
 *         @iv = n
 *       end
 *       def hello()
 *         "Hello, @iv = #{@iv}"
 *       end
 *     end
 *
 *     k = Demo.new(99)
 *     def k.hi
 *       "Hi, @iv = #{@iv}"
 *     end
 *     m = k.singleton_method(:hi)
 *     m.call   #=> "Hi, @iv = 99"
 *     m = k.singleton_method(:hello) #=> NameError
 */

VALUE
rb_obj_singleton_method(VALUE obj, VALUE vid)
{
    VALUE klass = rb_singleton_class_get(obj);
    ID id = rb_check_id(&vid);

    if (NIL_P(klass)) {
        /* goto undef; */
    }
    else if (NIL_P(klass = RCLASS_ORIGIN(klass))) {
        /* goto undef; */
    }
    else if (! id) {
        VALUE m = mnew_missing_by_name(klass, obj, &vid, FALSE, rb_cMethod);
        if (m) return m;
        /* else goto undef; */
    }
    else {
        const rb_method_entry_t *me = rb_method_entry_at(klass, id);
        vid = ID2SYM(id);

        if (UNDEFINED_METHOD_ENTRY_P(me)) {
            /* goto undef; */
        }
        else if (UNDEFINED_REFINED_METHOD_P(me->def)) {
            /* goto undef; */
        }
        else {
            return mnew_from_me(me, klass, klass, obj, id, rb_cMethod, FALSE);
        }
    }

  /* undef: */
    rb_name_err_raise("undefined singleton method `%1$s' for `%2$s'",
                      obj, vid);
    UNREACHABLE_RETURN(Qundef);
}

/*
 *  call-seq:
 *     mod.instance_method(symbol)   -> unbound_method
 *
 *  Returns an +UnboundMethod+ representing the given
 *  instance method in _mod_.
 *
 *     class Interpreter
 *       def do_a() print "there, "; end
 *       def do_d() print "Hello ";  end
 *       def do_e() print "!\n";     end
 *       def do_v() print "Dave";    end
 *       Dispatcher = {
 *         "a" => instance_method(:do_a),
 *         "d" => instance_method(:do_d),
 *         "e" => instance_method(:do_e),
 *         "v" => instance_method(:do_v)
 *       }
 *       def interpret(string)
 *         string.each_char {|b| Dispatcher[b].bind(self).call }
 *       end
 *     end
 *
 *     interpreter = Interpreter.new
 *     interpreter.interpret('dave')
 *
 *  <em>produces:</em>
 *
 *     Hello there, Dave!
 */

static VALUE
rb_mod_instance_method(VALUE mod, VALUE vid)
{
    ID id = rb_check_id(&vid);
    if (!id) {
        rb_method_name_error(mod, vid);
    }
    return mnew_unbound(mod, id, rb_cUnboundMethod, FALSE);
}

/*
 *  call-seq:
 *     mod.public_instance_method(symbol)   -> unbound_method
 *
 *  Similar to _instance_method_, searches public method only.
 */

static VALUE
rb_mod_public_instance_method(VALUE mod, VALUE vid)
{
    ID id = rb_check_id(&vid);
    if (!id) {
        rb_method_name_error(mod, vid);
    }
    return mnew_unbound(mod, id, rb_cUnboundMethod, TRUE);
}

static VALUE
rb_mod_define_method_with_visibility(int argc, VALUE *argv, VALUE mod, const struct rb_scope_visi_struct* scope_visi)
{
    ID id;
    VALUE body;
    VALUE name;
    int is_method = FALSE;

    rb_check_arity(argc, 1, 2);
    name = argv[0];
    id = rb_check_id(&name);
    if (argc == 1) {
        body = rb_block_lambda();
    }
    else {
        body = argv[1];

        if (rb_obj_is_method(body)) {
            is_method = TRUE;
        }
        else if (rb_obj_is_proc(body)) {
            is_method = FALSE;
        }
        else {
            rb_raise(rb_eTypeError,
                     "wrong argument type %s (expected Proc/Method/UnboundMethod)",
                     rb_obj_classname(body));
        }
    }
    if (!id) id = rb_to_id(name);

    if (is_method) {
        struct METHOD *method = (struct METHOD *)DATA_PTR(body);
        if (method->me->owner != mod && !RB_TYPE_P(method->me->owner, T_MODULE) &&
            !RTEST(rb_class_inherited_p(mod, method->me->owner))) {
            if (FL_TEST(method->me->owner, FL_SINGLETON)) {
                rb_raise(rb_eTypeError,
                         "can't bind singleton method to a different class");
            }
            else {
                rb_raise(rb_eTypeError,
                         "bind argument must be a subclass of % "PRIsVALUE,
                         method->me->owner);
            }
        }
        rb_method_entry_set(mod, id, method->me, scope_visi->method_visi);
        if (scope_visi->module_func) {
            rb_method_entry_set(rb_singleton_class(mod), id, method->me, METHOD_VISI_PUBLIC);
        }
        RB_GC_GUARD(body);
    }
    else {
        VALUE procval = rb_proc_dup(body);
        if (vm_proc_iseq(procval) != NULL) {
            rb_proc_t *proc;
            GetProcPtr(procval, proc);
            proc->is_lambda = TRUE;
            proc->is_from_method = TRUE;
        }
        rb_add_method(mod, id, VM_METHOD_TYPE_BMETHOD, (void *)procval, scope_visi->method_visi);
        if (scope_visi->module_func) {
            rb_add_method(rb_singleton_class(mod), id, VM_METHOD_TYPE_BMETHOD, (void *)body, METHOD_VISI_PUBLIC);
        }
    }

    return ID2SYM(id);
}

/*
 *  call-seq:
 *     define_method(symbol, method)     -> symbol
 *     define_method(symbol) { block }   -> symbol
 *
 *  Defines an instance method in the receiver. The _method_
 *  parameter can be a +Proc+, a +Method+ or an +UnboundMethod+ object.
 *  If a block is specified, it is used as the method body.
 *  If a block or the _method_ parameter has parameters,
 *  they're used as method parameters.
 *  This block is evaluated using #instance_eval.
 *
 *     class A
 *       def fred
 *         puts "In Fred"
 *       end
 *       def create_method(name, &block)
 *         self.class.define_method(name, &block)
 *       end
 *       define_method(:wilma) { puts "Charge it!" }
 *       define_method(:flint) {|name| puts "I'm #{name}!"}
 *     end
 *     class B < A
 *       define_method(:barney, instance_method(:fred))
 *     end
 *     a = B.new
 *     a.barney
 *     a.wilma
 *     a.flint('Dino')
 *     a.create_method(:betty) { p self }
 *     a.betty
 *
 *  <em>produces:</em>
 *
 *     In Fred
 *     Charge it!
 *     I'm Dino!
 *     #<B:0x401b39e8>
 */

static VALUE
rb_mod_define_method(int argc, VALUE *argv, VALUE mod)
{
    const rb_cref_t *cref = rb_vm_cref_in_context(mod, mod);
    const rb_scope_visibility_t default_scope_visi = {METHOD_VISI_PUBLIC, FALSE};
    const rb_scope_visibility_t *scope_visi = &default_scope_visi;

    if (cref) {
        scope_visi = CREF_SCOPE_VISI(cref);
    }

    return rb_mod_define_method_with_visibility(argc, argv, mod, scope_visi);
}

/*
 *  call-seq:
 *     define_singleton_method(symbol, method) -> symbol
 *     define_singleton_method(symbol) { block } -> symbol
 *
 *  Defines a public singleton method in the receiver. The _method_
 *  parameter can be a +Proc+, a +Method+ or an +UnboundMethod+ object.
 *  If a block is specified, it is used as the method body.
 *  If a block or a method has parameters, they're used as method parameters.
 *
 *     class A
 *       class << self
 *         def class_name
 *           to_s
 *         end
 *       end
 *     end
 *     A.define_singleton_method(:who_am_i) do
 *       "I am: #{class_name}"
 *     end
 *     A.who_am_i   # ==> "I am: A"
 *
 *     guy = "Bob"
 *     guy.define_singleton_method(:hello) { "#{self}: Hello there!" }
 *     guy.hello    #=>  "Bob: Hello there!"
 *
 *     chris = "Chris"
 *     chris.define_singleton_method(:greet) {|greeting| "#{greeting}, I'm Chris!" }
 *     chris.greet("Hi") #=> "Hi, I'm Chris!"
 */

static VALUE
rb_obj_define_method(int argc, VALUE *argv, VALUE obj)
{
    VALUE klass = rb_singleton_class(obj);
    const rb_scope_visibility_t scope_visi = {METHOD_VISI_PUBLIC, FALSE};

    return rb_mod_define_method_with_visibility(argc, argv, klass, &scope_visi);
}

/*
 *     define_method(symbol, method)     -> symbol
 *     define_method(symbol) { block }   -> symbol
 *
 *  Defines a global function by _method_ or the block.
 */

static VALUE
top_define_method(int argc, VALUE *argv, VALUE obj)
{
    rb_thread_t *th = GET_THREAD();
    VALUE klass;

    klass = th->top_wrapper;
    if (klass) {
        rb_warning("main.define_method in the wrapped load is effective only in wrapper module");
    }
    else {
        klass = rb_cObject;
    }
    return rb_mod_define_method(argc, argv, klass);
}

/*
 *  call-seq:
 *    method.clone -> new_method
 *
 *  Returns a clone of this method.
 *
 *    class A
 *      def foo
 *        return "bar"
 *      end
 *    end
 *
 *    m = A.new.method(:foo)
 *    m.call # => "bar"
 *    n = m.clone.call # => "bar"
 */

static VALUE
method_clone(VALUE self)
{
    VALUE clone;
    struct METHOD *orig, *data;

    TypedData_Get_Struct(self, struct METHOD, &method_data_type, orig);
    clone = TypedData_Make_Struct(CLASS_OF(self), struct METHOD, &method_data_type, data);
    CLONESETUP(clone, self);
    RB_OBJ_WRITE(clone, &data->recv, orig->recv);
    RB_OBJ_WRITE(clone, &data->klass, orig->klass);
    RB_OBJ_WRITE(clone, &data->iclass, orig->iclass);
    RB_OBJ_WRITE(clone, &data->owner, orig->owner);
    RB_OBJ_WRITE(clone, &data->me, rb_method_entry_clone(orig->me));
    return clone;
}

/*  Document-method: Method#===
 *
 *  call-seq:
 *     method === obj   -> result_of_method
 *
 *  Invokes the method with +obj+ as the parameter like #call.
 *  This allows a method object to be the target of a +when+ clause
 *  in a case statement.
 *
 *      require 'prime'
 *
 *      case 1373
 *      when Prime.method(:prime?)
 *        # ...
 *      end
 */


/*  Document-method: Method#[]
 *
 *  call-seq:
 *     meth[args, ...]         -> obj
 *
 *  Invokes the <i>meth</i> with the specified arguments, returning the
 *  method's return value, like #call.
 *
 *     m = 12.method("+")
 *     m[3]         #=> 15
 *     m[20]        #=> 32
 */

/*
 *  call-seq:
 *     meth.call(args, ...)    -> obj
 *
 *  Invokes the <i>meth</i> with the specified arguments, returning the
 *  method's return value.
 *
 *     m = 12.method("+")
 *     m.call(3)    #=> 15
 *     m.call(20)   #=> 32
 */

static VALUE
rb_method_call_pass_called_kw(int argc, const VALUE *argv, VALUE method)
{
    return rb_method_call_kw(argc, argv, method, RB_PASS_CALLED_KEYWORDS);
}

VALUE
rb_method_call_kw(int argc, const VALUE *argv, VALUE method, int kw_splat)
{
    VALUE procval = rb_block_given_p() ? rb_block_proc() : Qnil;
    return rb_method_call_with_block_kw(argc, argv, method, procval, kw_splat);
}

VALUE
rb_method_call(int argc, const VALUE *argv, VALUE method)
{
    VALUE procval = rb_block_given_p() ? rb_block_proc() : Qnil;
    return rb_method_call_with_block(argc, argv, method, procval);
}

static const rb_callable_method_entry_t *
method_callable_method_entry(const struct METHOD *data)
{
    if (data->me->defined_class == 0) rb_bug("method_callable_method_entry: not callable.");
    return (const rb_callable_method_entry_t *)data->me;
}

static inline VALUE
call_method_data(rb_execution_context_t *ec, const struct METHOD *data,
                 int argc, const VALUE *argv, VALUE passed_procval, int kw_splat)
{
    vm_passed_block_handler_set(ec, proc_to_block_handler(passed_procval));
    return rb_vm_call_kw(ec, data->recv, data->me->called_id, argc, argv,
                         method_callable_method_entry(data), kw_splat);
}

VALUE
rb_method_call_with_block_kw(int argc, const VALUE *argv, VALUE method, VALUE passed_procval, int kw_splat)
{
    const struct METHOD *data;
    rb_execution_context_t *ec = GET_EC();

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    if (UNDEF_P(data->recv)) {
        rb_raise(rb_eTypeError, "can't call unbound method; bind first");
    }
    return call_method_data(ec, data, argc, argv, passed_procval, kw_splat);
}

VALUE
rb_method_call_with_block(int argc, const VALUE *argv, VALUE method, VALUE passed_procval)
{
    return rb_method_call_with_block_kw(argc, argv, method, passed_procval, RB_NO_KEYWORDS);
}

/**********************************************************************
 *
 * Document-class: UnboundMethod
 *
 *  Ruby supports two forms of objectified methods. Class Method is
 *  used to represent methods that are associated with a particular
 *  object: these method objects are bound to that object. Bound
 *  method objects for an object can be created using Object#method.
 *
 *  Ruby also supports unbound methods; methods objects that are not
 *  associated with a particular object. These can be created either
 *  by calling Module#instance_method or by calling #unbind on a bound
 *  method object. The result of both of these is an UnboundMethod
 *  object.
 *
 *  Unbound methods can only be called after they are bound to an
 *  object. That object must be a kind_of? the method's original
 *  class.
 *
 *     class Square
 *       def area
 *         @side * @side
 *       end
 *       def initialize(side)
 *         @side = side
 *       end
 *     end
 *
 *     area_un = Square.instance_method(:area)
 *
 *     s = Square.new(12)
 *     area = area_un.bind(s)
 *     area.call   #=> 144
 *
 *  Unbound methods are a reference to the method at the time it was
 *  objectified: subsequent changes to the underlying class will not
 *  affect the unbound method.
 *
 *     class Test
 *       def test
 *         :original
 *       end
 *     end
 *     um = Test.instance_method(:test)
 *     class Test
 *       def test
 *         :modified
 *       end
 *     end
 *     t = Test.new
 *     t.test            #=> :modified
 *     um.bind(t).call   #=> :original
 *
 */

static void
convert_umethod_to_method_components(const struct METHOD *data, VALUE recv, VALUE *methclass_out, VALUE *klass_out, VALUE *iclass_out, const rb_method_entry_t **me_out, const bool clone)
{
    VALUE methclass = data->owner;
    VALUE iclass = data->me->defined_class;
    VALUE klass = CLASS_OF(recv);

    if (RB_TYPE_P(methclass, T_MODULE)) {
        VALUE refined_class = rb_refinement_module_get_refined_class(methclass);
        if (!NIL_P(refined_class)) methclass = refined_class;
    }
    if (!RB_TYPE_P(methclass, T_MODULE) && !RTEST(rb_obj_is_kind_of(recv, methclass))) {
        if (FL_TEST(methclass, FL_SINGLETON)) {
            rb_raise(rb_eTypeError,
                     "singleton method called for a different object");
        }
        else {
            rb_raise(rb_eTypeError, "bind argument must be an instance of % "PRIsVALUE,
                     methclass);
        }
    }

    const rb_method_entry_t *me;
    if (clone) {
        me = rb_method_entry_clone(data->me);
    }
    else {
        me = data->me;
    }

    if (RB_TYPE_P(me->owner, T_MODULE)) {
        if (!clone) {
            // if we didn't previously clone the method entry, then we need to clone it now
            // because this branch manipulates it in rb_method_entry_complement_defined_class
            me = rb_method_entry_clone(me);
        }
        VALUE ic = rb_class_search_ancestor(klass, me->owner);
        if (ic) {
            klass = ic;
            iclass = ic;
        }
        else {
            klass = rb_include_class_new(methclass, klass);
        }
        me = (const rb_method_entry_t *) rb_method_entry_complement_defined_class(me, me->called_id, klass);
    }

    *methclass_out = methclass;
    *klass_out = klass;
    *iclass_out = iclass;
    *me_out = me;
}

/*
 *  call-seq:
 *     umeth.bind(obj) -> method
 *
 *  Bind <i>umeth</i> to <i>obj</i>. If Klass was the class from which
 *  <i>umeth</i> was obtained, <code>obj.kind_of?(Klass)</code> must
 *  be true.
 *
 *     class A
 *       def test
 *         puts "In test, class = #{self.class}"
 *       end
 *     end
 *     class B < A
 *     end
 *     class C < B
 *     end
 *
 *
 *     um = B.instance_method(:test)
 *     bm = um.bind(C.new)
 *     bm.call
 *     bm = um.bind(B.new)
 *     bm.call
 *     bm = um.bind(A.new)
 *     bm.call
 *
 *  <em>produces:</em>
 *
 *     In test, class = C
 *     In test, class = B
 *     prog.rb:16:in `bind': bind argument must be an instance of B (TypeError)
 *     	from prog.rb:16
 */

static VALUE
umethod_bind(VALUE method, VALUE recv)
{
    VALUE methclass, klass, iclass;
    const rb_method_entry_t *me;
    const struct METHOD *data;
    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    convert_umethod_to_method_components(data, recv, &methclass, &klass, &iclass, &me, true);

    struct METHOD *bound;
    method = TypedData_Make_Struct(rb_cMethod, struct METHOD, &method_data_type, bound);
    RB_OBJ_WRITE(method, &bound->recv, recv);
    RB_OBJ_WRITE(method, &bound->klass, klass);
    RB_OBJ_WRITE(method, &bound->iclass, iclass);
    RB_OBJ_WRITE(method, &bound->owner, methclass);
    RB_OBJ_WRITE(method, &bound->me, me);

    return method;
}

/*
 *  call-seq:
 *     umeth.bind_call(recv, args, ...) -> obj
 *
 *  Bind <i>umeth</i> to <i>recv</i> and then invokes the method with the
 *  specified arguments.
 *  This is semantically equivalent to <code>umeth.bind(recv).call(args, ...)</code>.
 */
static VALUE
umethod_bind_call(int argc, VALUE *argv, VALUE method)
{
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    VALUE recv = argv[0];
    argc--;
    argv++;

    VALUE passed_procval = rb_block_given_p() ? rb_block_proc() : Qnil;
    rb_execution_context_t *ec = GET_EC();

    const struct METHOD *data;
    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);

    const rb_callable_method_entry_t *cme = rb_callable_method_entry(CLASS_OF(recv), data->me->called_id);
    if (data->me == (const rb_method_entry_t *)cme) {
        vm_passed_block_handler_set(ec, proc_to_block_handler(passed_procval));
        return rb_vm_call_kw(ec, recv, cme->called_id, argc, argv, cme, RB_PASS_CALLED_KEYWORDS);
    }
    else {
        VALUE methclass, klass, iclass;
        const rb_method_entry_t *me;
        convert_umethod_to_method_components(data, recv, &methclass, &klass, &iclass, &me, false);
        struct METHOD bound = { recv, klass, 0, methclass, me };

        return call_method_data(ec, &bound, argc, argv, passed_procval, RB_PASS_CALLED_KEYWORDS);
    }
}

/*
 * Returns the number of required parameters and stores the maximum
 * number of parameters in max, or UNLIMITED_ARGUMENTS
 * if there is no maximum.
 */
static int
method_def_min_max_arity(const rb_method_definition_t *def, int *max)
{
  again:
    if (!def) return *max = 0;
    switch (def->type) {
      case VM_METHOD_TYPE_CFUNC:
        if (def->body.cfunc.argc < 0) {
            *max = UNLIMITED_ARGUMENTS;
            return 0;
        }
        return *max = check_argc(def->body.cfunc.argc);
      case VM_METHOD_TYPE_ZSUPER:
        *max = UNLIMITED_ARGUMENTS;
        return 0;
      case VM_METHOD_TYPE_ATTRSET:
        return *max = 1;
      case VM_METHOD_TYPE_IVAR:
        return *max = 0;
      case VM_METHOD_TYPE_ALIAS:
        def = def->body.alias.original_me->def;
        goto again;
      case VM_METHOD_TYPE_BMETHOD:
        return rb_proc_min_max_arity(def->body.bmethod.proc, max);
      case VM_METHOD_TYPE_ISEQ:
        return rb_iseq_min_max_arity(rb_iseq_check(def->body.iseq.iseqptr), max);
      case VM_METHOD_TYPE_UNDEF:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
        return *max = 0;
      case VM_METHOD_TYPE_MISSING:
        *max = UNLIMITED_ARGUMENTS;
        return 0;
      case VM_METHOD_TYPE_OPTIMIZED: {
        switch (def->body.optimized.type) {
          case OPTIMIZED_METHOD_TYPE_SEND:
            *max = UNLIMITED_ARGUMENTS;
            return 0;
          case OPTIMIZED_METHOD_TYPE_CALL:
            *max = UNLIMITED_ARGUMENTS;
            return 0;
          case OPTIMIZED_METHOD_TYPE_BLOCK_CALL:
            *max = UNLIMITED_ARGUMENTS;
            return 0;
          case OPTIMIZED_METHOD_TYPE_STRUCT_AREF:
            *max = 0;
            return 0;
          case OPTIMIZED_METHOD_TYPE_STRUCT_ASET:
            *max = 1;
            return 1;
          default:
            break;
        }
        break;
      }
      case VM_METHOD_TYPE_REFINED:
        *max = UNLIMITED_ARGUMENTS;
        return 0;
    }
    rb_bug("method_def_min_max_arity: invalid method entry type (%d)", def->type);
    UNREACHABLE_RETURN(Qnil);
}

static int
method_def_arity(const rb_method_definition_t *def)
{
    int max, min = method_def_min_max_arity(def, &max);
    return min == max ? min : -min-1;
}

int
rb_method_entry_arity(const rb_method_entry_t *me)
{
    return method_def_arity(me->def);
}

/*
 *  call-seq:
 *     meth.arity    -> integer
 *
 *  Returns an indication of the number of arguments accepted by a
 *  method. Returns a nonnegative integer for methods that take a fixed
 *  number of arguments. For Ruby methods that take a variable number of
 *  arguments, returns -n-1, where n is the number of required arguments.
 *  Keyword arguments will be considered as a single additional argument,
 *  that argument being mandatory if any keyword argument is mandatory.
 *  For methods written in C, returns -1 if the call takes a
 *  variable number of arguments.
 *
 *     class C
 *       def one;    end
 *       def two(a); end
 *       def three(*a);  end
 *       def four(a, b); end
 *       def five(a, b, *c);    end
 *       def six(a, b, *c, &d); end
 *       def seven(a, b, x:0); end
 *       def eight(x:, y:); end
 *       def nine(x:, y:, **z); end
 *       def ten(*a, x:, y:); end
 *     end
 *     c = C.new
 *     c.method(:one).arity     #=> 0
 *     c.method(:two).arity     #=> 1
 *     c.method(:three).arity   #=> -1
 *     c.method(:four).arity    #=> 2
 *     c.method(:five).arity    #=> -3
 *     c.method(:six).arity     #=> -3
 *     c.method(:seven).arity   #=> -3
 *     c.method(:eight).arity   #=> 1
 *     c.method(:nine).arity    #=> 1
 *     c.method(:ten).arity     #=> -2
 *
 *     "cat".method(:size).arity      #=> 0
 *     "cat".method(:replace).arity   #=> 1
 *     "cat".method(:squeeze).arity   #=> -1
 *     "cat".method(:count).arity     #=> -1
 */

static VALUE
method_arity_m(VALUE method)
{
    int n = method_arity(method);
    return INT2FIX(n);
}

static int
method_arity(VALUE method)
{
    struct METHOD *data;

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    return rb_method_entry_arity(data->me);
}

static const rb_method_entry_t *
original_method_entry(VALUE mod, ID id)
{
    const rb_method_entry_t *me;

    while ((me = rb_method_entry(mod, id)) != 0) {
        const rb_method_definition_t *def = me->def;
        if (def->type != VM_METHOD_TYPE_ZSUPER) break;
        mod = RCLASS_SUPER(me->owner);
        id = def->original_id;
    }
    return me;
}

static int
method_min_max_arity(VALUE method, int *max)
{
    const struct METHOD *data;

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    return method_def_min_max_arity(data->me->def, max);
}

int
rb_mod_method_arity(VALUE mod, ID id)
{
    const rb_method_entry_t *me = original_method_entry(mod, id);
    if (!me) return 0;		/* should raise? */
    return rb_method_entry_arity(me);
}

int
rb_obj_method_arity(VALUE obj, ID id)
{
    return rb_mod_method_arity(CLASS_OF(obj), id);
}

VALUE
rb_callable_receiver(VALUE callable)
{
    if (rb_obj_is_proc(callable)) {
        VALUE binding = proc_binding(callable);
        return rb_funcall(binding, rb_intern("receiver"), 0);
    }
    else if (rb_obj_is_method(callable)) {
        return method_receiver(callable);
    }
    else {
        return Qundef;
    }
}

const rb_method_definition_t *
rb_method_def(VALUE method)
{
    const struct METHOD *data;

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    return data->me->def;
}

static const rb_iseq_t *
method_def_iseq(const rb_method_definition_t *def)
{
    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
        return rb_iseq_check(def->body.iseq.iseqptr);
      case VM_METHOD_TYPE_BMETHOD:
        return rb_proc_get_iseq(def->body.bmethod.proc, 0);
      case VM_METHOD_TYPE_ALIAS:
        return method_def_iseq(def->body.alias.original_me->def);
      case VM_METHOD_TYPE_CFUNC:
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_UNDEF:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_OPTIMIZED:
      case VM_METHOD_TYPE_MISSING:
      case VM_METHOD_TYPE_REFINED:
        break;
    }
    return NULL;
}

const rb_iseq_t *
rb_method_iseq(VALUE method)
{
    return method_def_iseq(rb_method_def(method));
}

static const rb_cref_t *
method_cref(VALUE method)
{
    const rb_method_definition_t *def = rb_method_def(method);

  again:
    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
        return def->body.iseq.cref;
      case VM_METHOD_TYPE_ALIAS:
        def = def->body.alias.original_me->def;
        goto again;
      default:
        return NULL;
    }
}

static VALUE
method_def_location(const rb_method_definition_t *def)
{
    if (def->type == VM_METHOD_TYPE_ATTRSET || def->type == VM_METHOD_TYPE_IVAR) {
        if (!def->body.attr.location)
            return Qnil;
        return rb_ary_dup(def->body.attr.location);
    }
    return iseq_location(method_def_iseq(def));
}

VALUE
rb_method_entry_location(const rb_method_entry_t *me)
{
    if (!me) return Qnil;
    return method_def_location(me->def);
}

/*
 * call-seq:
 *    meth.source_location  -> [String, Integer]
 *
 * Returns the Ruby source filename and line number containing this method
 * or nil if this method was not defined in Ruby (i.e. native).
 */

VALUE
rb_method_location(VALUE method)
{
    return method_def_location(rb_method_def(method));
}

static const rb_method_definition_t *
vm_proc_method_def(VALUE procval)
{
    const rb_proc_t *proc;
    const struct rb_block *block;
    const struct vm_ifunc *ifunc;

    GetProcPtr(procval, proc);
    block = &proc->block;

    if (vm_block_type(block) == block_type_ifunc &&
        IS_METHOD_PROC_IFUNC(ifunc = block->as.captured.code.ifunc)) {
        return rb_method_def((VALUE)ifunc->data);
    }
    else {
        return NULL;
    }
}

static VALUE
method_def_parameters(const rb_method_definition_t *def)
{
    const rb_iseq_t *iseq;
    const rb_method_definition_t *bmethod_def;

    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
        iseq = method_def_iseq(def);
        return rb_iseq_parameters(iseq, 0);
      case VM_METHOD_TYPE_BMETHOD:
        if ((iseq = method_def_iseq(def)) != NULL) {
            return rb_iseq_parameters(iseq, 0);
        }
        else if ((bmethod_def = vm_proc_method_def(def->body.bmethod.proc)) != NULL) {
            return method_def_parameters(bmethod_def);
        }
        break;

      case VM_METHOD_TYPE_ALIAS:
        return method_def_parameters(def->body.alias.original_me->def);

      case VM_METHOD_TYPE_OPTIMIZED:
        if (def->body.optimized.type == OPTIMIZED_METHOD_TYPE_STRUCT_ASET) {
            VALUE param = rb_ary_new_from_args(2, ID2SYM(rb_intern("req")), ID2SYM(rb_intern("_")));
            return rb_ary_new_from_args(1, param);
        }
        break;

      case VM_METHOD_TYPE_CFUNC:
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_UNDEF:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_MISSING:
      case VM_METHOD_TYPE_REFINED:
        break;
    }

    return rb_unnamed_parameters(method_def_arity(def));

}

/*
 * call-seq:
 *    meth.parameters  -> array
 *
 * Returns the parameter information of this method.
 *
 *    def foo(bar); end
 *    method(:foo).parameters #=> [[:req, :bar]]
 *
 *    def foo(bar, baz, bat, &blk); end
 *    method(:foo).parameters #=> [[:req, :bar], [:req, :baz], [:req, :bat], [:block, :blk]]
 *
 *    def foo(bar, *args); end
 *    method(:foo).parameters #=> [[:req, :bar], [:rest, :args]]
 *
 *    def foo(bar, baz, *args, &blk); end
 *    method(:foo).parameters #=> [[:req, :bar], [:req, :baz], [:rest, :args], [:block, :blk]]
 */

static VALUE
rb_method_parameters(VALUE method)
{
    return method_def_parameters(rb_method_def(method));
}

/*
 *  call-seq:
 *   meth.to_s      ->  string
 *   meth.inspect   ->  string
 *
 *  Returns a human-readable description of the underlying method.
 *
 *    "cat".method(:count).inspect   #=> "#<Method: String#count(*)>"
 *    (1..3).method(:map).inspect    #=> "#<Method: Range(Enumerable)#map()>"
 *
 *  In the latter case, the method description includes the "owner" of the
 *  original method (+Enumerable+ module, which is included into +Range+).
 *
 *  +inspect+ also provides, when possible, method argument names (call
 *  sequence) and source location.
 *
 *    require 'net/http'
 *    Net::HTTP.method(:get).inspect
 *    #=> "#<Method: Net::HTTP.get(uri_or_host, path=..., port=...) <skip>/lib/ruby/2.7.0/net/http.rb:457>"
 *
 *  <code>...</code> in argument definition means argument is optional (has
 *  some default value).
 *
 *  For methods defined in C (language core and extensions), location and
 *  argument names can't be extracted, and only generic information is provided
 *  in form of <code>*</code> (any number of arguments) or <code>_</code> (some
 *  positional argument).
 *
 *    "cat".method(:count).inspect   #=> "#<Method: String#count(*)>"
 *    "cat".method(:+).inspect       #=> "#<Method: String#+(_)>""

 */

static VALUE
method_inspect(VALUE method)
{
    struct METHOD *data;
    VALUE str;
    const char *sharp = "#";
    VALUE mklass;
    VALUE defined_class;

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    str = rb_sprintf("#<% "PRIsVALUE": ", rb_obj_class(method));

    mklass = data->iclass;
    if (!mklass) mklass = data->klass;

    if (RB_TYPE_P(mklass, T_ICLASS)) {
        /* TODO: I'm not sure why mklass is T_ICLASS.
         * UnboundMethod#bind() can set it as T_ICLASS at convert_umethod_to_method_components()
         * but not sure it is needed.
         */
        mklass = RBASIC_CLASS(mklass);
    }

    if (data->me->def->type == VM_METHOD_TYPE_ALIAS) {
        defined_class = data->me->def->body.alias.original_me->owner;
    }
    else {
        defined_class = method_entry_defined_class(data->me);
    }

    if (RB_TYPE_P(defined_class, T_ICLASS)) {
        defined_class = RBASIC_CLASS(defined_class);
    }

    if (FL_TEST(mklass, FL_SINGLETON)) {
        VALUE v = rb_ivar_get(mklass, attached);

        if (UNDEF_P(data->recv)) {
            rb_str_buf_append(str, rb_inspect(mklass));
        }
        else if (data->recv == v) {
            rb_str_buf_append(str, rb_inspect(v));
            sharp = ".";
        }
        else {
            rb_str_buf_append(str, rb_inspect(data->recv));
            rb_str_buf_cat2(str, "(");
            rb_str_buf_append(str, rb_inspect(v));
            rb_str_buf_cat2(str, ")");
            sharp = ".";
        }
    }
    else {
        mklass = data->klass;
        if (FL_TEST(mklass, FL_SINGLETON)) {
            VALUE v = rb_ivar_get(mklass, attached);
            if (!(RB_TYPE_P(v, T_CLASS) || RB_TYPE_P(v, T_MODULE))) {
                do {
                   mklass = RCLASS_SUPER(mklass);
                } while (RB_TYPE_P(mklass, T_ICLASS));
            }
        }
        rb_str_buf_append(str, rb_inspect(mklass));
        if (defined_class != mklass) {
            rb_str_catf(str, "(% "PRIsVALUE")", defined_class);
        }
    }
    rb_str_buf_cat2(str, sharp);
    rb_str_append(str, rb_id2str(data->me->called_id));
    if (data->me->called_id != data->me->def->original_id) {
        rb_str_catf(str, "(%"PRIsVALUE")",
                    rb_id2str(data->me->def->original_id));
    }
    if (data->me->def->type == VM_METHOD_TYPE_NOTIMPLEMENTED) {
        rb_str_buf_cat2(str, " (not-implemented)");
    }

    // parameter information
    {
        VALUE params = rb_method_parameters(method);
        VALUE pair, name, kind;
        const VALUE req = ID2SYM(rb_intern("req"));
        const VALUE opt = ID2SYM(rb_intern("opt"));
        const VALUE keyreq = ID2SYM(rb_intern("keyreq"));
        const VALUE key = ID2SYM(rb_intern("key"));
        const VALUE rest = ID2SYM(rb_intern("rest"));
        const VALUE keyrest = ID2SYM(rb_intern("keyrest"));
        const VALUE block = ID2SYM(rb_intern("block"));
        const VALUE nokey = ID2SYM(rb_intern("nokey"));
        int forwarding = 0;

        rb_str_buf_cat2(str, "(");

        if (RARRAY_LEN(params) == 3 &&
            RARRAY_AREF(RARRAY_AREF(params, 0), 0) == rest &&
            RARRAY_AREF(RARRAY_AREF(params, 0), 1) == ID2SYM('*') &&
            RARRAY_AREF(RARRAY_AREF(params, 1), 0) == keyrest &&
            RARRAY_AREF(RARRAY_AREF(params, 1), 1) == ID2SYM(idPow) &&
            RARRAY_AREF(RARRAY_AREF(params, 2), 0) == block &&
            RARRAY_AREF(RARRAY_AREF(params, 2), 1) == ID2SYM('&')) {
            forwarding = 1;
        }

        for (int i = 0; i < RARRAY_LEN(params); i++) {
            pair = RARRAY_AREF(params, i);
            kind = RARRAY_AREF(pair, 0);
            name = RARRAY_AREF(pair, 1);
            // FIXME: in tests it turns out that kind, name = [:req] produces name to be false. Why?..
            if (NIL_P(name) || name == Qfalse) {
                // FIXME: can it be reduced to switch/case?
                if (kind == req || kind == opt) {
                    name = rb_str_new2("_");
                }
                else if (kind == rest || kind == keyrest) {
                    name = rb_str_new2("");
                }
                else if (kind == block) {
                    name = rb_str_new2("block");
                }
                else if (kind == nokey) {
                    name = rb_str_new2("nil");
                }
            }

            if (kind == req) {
                rb_str_catf(str, "%"PRIsVALUE, name);
            }
            else if (kind == opt) {
                rb_str_catf(str, "%"PRIsVALUE"=...", name);
            }
            else if (kind == keyreq) {
                rb_str_catf(str, "%"PRIsVALUE":", name);
            }
            else if (kind == key) {
                rb_str_catf(str, "%"PRIsVALUE": ...", name);
            }
            else if (kind == rest) {
                if (name == ID2SYM('*')) {
                    rb_str_cat_cstr(str, forwarding ? "..." : "*");
                }
                else {
                    rb_str_catf(str, "*%"PRIsVALUE, name);
                }
            }
            else if (kind == keyrest) {
                if (name != ID2SYM(idPow)) {
                    rb_str_catf(str, "**%"PRIsVALUE, name);
                }
                else if (i > 0) {
                    rb_str_set_len(str, RSTRING_LEN(str) - 2);
                }
                else {
                    rb_str_cat_cstr(str, "**");
                }
            }
            else if (kind == block) {
                if (name == ID2SYM('&')) {
                    if (forwarding) {
                        rb_str_set_len(str, RSTRING_LEN(str) - 2);
                    }
                    else {
                        rb_str_cat_cstr(str, "...");
                    }
                }
                else {
                    rb_str_catf(str, "&%"PRIsVALUE, name);
                }
            }
            else if (kind == nokey) {
                rb_str_buf_cat2(str, "**nil");
            }

            if (i < RARRAY_LEN(params) - 1) {
                rb_str_buf_cat2(str, ", ");
            }
        }
        rb_str_buf_cat2(str, ")");
    }

    { // source location
        VALUE loc = rb_method_location(method);
        if (!NIL_P(loc)) {
            rb_str_catf(str, " %"PRIsVALUE":%"PRIsVALUE,
                        RARRAY_AREF(loc, 0), RARRAY_AREF(loc, 1));
        }
    }

    rb_str_buf_cat2(str, ">");

    return str;
}

static VALUE
bmcall(RB_BLOCK_CALL_FUNC_ARGLIST(args, method))
{
    return rb_method_call_with_block_kw(argc, argv, method, blockarg, RB_PASS_CALLED_KEYWORDS);
}

VALUE
rb_proc_new(
    rb_block_call_func_t func,
    VALUE val)
{
    VALUE procval = rb_block_call(rb_mRubyVMFrozenCore, idProc, 0, 0, func, val);
    return procval;
}

/*
 *  call-seq:
 *     meth.to_proc    -> proc
 *
 *  Returns a Proc object corresponding to this method.
 */

static VALUE
method_to_proc(VALUE method)
{
    VALUE procval;
    rb_proc_t *proc;

    /*
     * class Method
     *   def to_proc
     *     lambda{|*args|
     *       self.call(*args)
     *     }
     *   end
     * end
     */
    procval = rb_block_call(rb_mRubyVMFrozenCore, idLambda, 0, 0, bmcall, method);
    GetProcPtr(procval, proc);
    proc->is_from_method = 1;
    return procval;
}

extern VALUE rb_find_defined_class_by_owner(VALUE current_class, VALUE target_owner);

/*
 * call-seq:
 *   meth.super_method  -> method
 *
 * Returns a Method of superclass which would be called when super is used
 * or nil if there is no method on superclass.
 */

static VALUE
method_super_method(VALUE method)
{
    const struct METHOD *data;
    VALUE super_class, iclass;
    ID mid;
    const rb_method_entry_t *me;

    TypedData_Get_Struct(method, struct METHOD, &method_data_type, data);
    iclass = data->iclass;
    if (!iclass) return Qnil;
    if (data->me->def->type == VM_METHOD_TYPE_ALIAS && data->me->defined_class) {
        super_class = RCLASS_SUPER(rb_find_defined_class_by_owner(data->me->defined_class,
            data->me->def->body.alias.original_me->owner));
        mid = data->me->def->body.alias.original_me->def->original_id;
    }
    else {
        super_class = RCLASS_SUPER(RCLASS_ORIGIN(iclass));
        mid = data->me->def->original_id;
    }
    if (!super_class) return Qnil;
    me = (rb_method_entry_t *)rb_callable_method_entry_with_refinements(super_class, mid, &iclass);
    if (!me) return Qnil;
    return mnew_internal(me, me->owner, iclass, data->recv, mid, rb_obj_class(method), FALSE, FALSE);
}

/*
 * call-seq:
 *   local_jump_error.exit_value  -> obj
 *
 * Returns the exit value associated with this +LocalJumpError+.
 */
static VALUE
localjump_xvalue(VALUE exc)
{
    return rb_iv_get(exc, "@exit_value");
}

/*
 * call-seq:
 *    local_jump_error.reason   -> symbol
 *
 * The reason this block was terminated:
 * :break, :redo, :retry, :next, :return, or :noreason.
 */

static VALUE
localjump_reason(VALUE exc)
{
    return rb_iv_get(exc, "@reason");
}

rb_cref_t *rb_vm_cref_new_toplevel(void); /* vm.c */

static const rb_env_t *
env_clone(const rb_env_t *env, const rb_cref_t *cref)
{
    VALUE *new_ep;
    VALUE *new_body;
    const rb_env_t *new_env;

    VM_ASSERT(env->ep > env->env);
    VM_ASSERT(VM_ENV_ESCAPED_P(env->ep));

    if (cref == NULL) {
        cref = rb_vm_cref_new_toplevel();
    }

    new_body = ALLOC_N(VALUE, env->env_size);
    MEMCPY(new_body, env->env, VALUE, env->env_size);
    new_ep = &new_body[env->ep - env->env];
    new_env = vm_env_new(new_ep, new_body, env->env_size, env->iseq);
    RB_OBJ_WRITE(new_env, &new_ep[VM_ENV_DATA_INDEX_ME_CREF], (VALUE)cref);
    VM_ASSERT(VM_ENV_ESCAPED_P(new_ep));
    return new_env;
}

/*
 *  call-seq:
 *     prc.binding    -> binding
 *
 *  Returns the binding associated with <i>prc</i>.
 *
 *     def fred(param)
 *       proc {}
 *     end
 *
 *     b = fred(99)
 *     eval("param", b.binding)   #=> 99
 */
static VALUE
proc_binding(VALUE self)
{
    VALUE bindval, binding_self = Qundef;
    rb_binding_t *bind;
    const rb_proc_t *proc;
    const rb_iseq_t *iseq = NULL;
    const struct rb_block *block;
    const rb_env_t *env = NULL;

    GetProcPtr(self, proc);
    block = &proc->block;

    if (proc->is_isolated) rb_raise(rb_eArgError, "Can't create Binding from isolated Proc");

  again:
    switch (vm_block_type(block)) {
      case block_type_iseq:
        iseq = block->as.captured.code.iseq;
        binding_self = block->as.captured.self;
        env = VM_ENV_ENVVAL_PTR(block->as.captured.ep);
        break;
      case block_type_proc:
        GetProcPtr(block->as.proc, proc);
        block = &proc->block;
        goto again;
      case block_type_ifunc:
        {
            const struct vm_ifunc *ifunc = block->as.captured.code.ifunc;
            if (IS_METHOD_PROC_IFUNC(ifunc)) {
                VALUE method = (VALUE)ifunc->data;
                VALUE name = rb_fstring_lit("<empty_iseq>");
                rb_iseq_t *empty;
                binding_self = method_receiver(method);
                iseq = rb_method_iseq(method);
                env = VM_ENV_ENVVAL_PTR(block->as.captured.ep);
                env = env_clone(env, method_cref(method));
                /* set empty iseq */
                empty = rb_iseq_new(NULL, name, name, Qnil, 0, ISEQ_TYPE_TOP);
                RB_OBJ_WRITE(env, &env->iseq, empty);
                break;
            }
        }
        /* FALLTHROUGH */
      case block_type_symbol:
        rb_raise(rb_eArgError, "Can't create Binding from C level Proc");
        UNREACHABLE_RETURN(Qnil);
    }

    bindval = rb_binding_alloc(rb_cBinding);
    GetBindingPtr(bindval, bind);
    RB_OBJ_WRITE(bindval, &bind->block.as.captured.self, binding_self);
    RB_OBJ_WRITE(bindval, &bind->block.as.captured.code.iseq, env->iseq);
    rb_vm_block_ep_update(bindval, &bind->block, env->ep);
    RB_OBJ_WRITTEN(bindval, Qundef, VM_ENV_ENVVAL(env->ep));

    if (iseq) {
        rb_iseq_check(iseq);
        RB_OBJ_WRITE(bindval, &bind->pathobj, ISEQ_BODY(iseq)->location.pathobj);
        bind->first_lineno = ISEQ_BODY(iseq)->location.first_lineno;
    }
    else {
        RB_OBJ_WRITE(bindval, &bind->pathobj,
                     rb_iseq_pathobj_new(rb_fstring_lit("(binding)"), Qnil));
        bind->first_lineno = 1;
    }

    return bindval;
}

static rb_block_call_func curry;

static VALUE
make_curry_proc(VALUE proc, VALUE passed, VALUE arity)
{
    VALUE args = rb_ary_new3(3, proc, passed, arity);
    rb_proc_t *procp;
    int is_lambda;

    GetProcPtr(proc, procp);
    is_lambda = procp->is_lambda;
    rb_ary_freeze(passed);
    rb_ary_freeze(args);
    proc = rb_proc_new(curry, args);
    GetProcPtr(proc, procp);
    procp->is_lambda = is_lambda;
    return proc;
}

static VALUE
curry(RB_BLOCK_CALL_FUNC_ARGLIST(_, args))
{
    VALUE proc, passed, arity;
    proc = RARRAY_AREF(args, 0);
    passed = RARRAY_AREF(args, 1);
    arity = RARRAY_AREF(args, 2);

    passed = rb_ary_plus(passed, rb_ary_new4(argc, argv));
    rb_ary_freeze(passed);

    if (RARRAY_LEN(passed) < FIX2INT(arity)) {
        if (!NIL_P(blockarg)) {
            rb_warn("given block not used");
        }
        arity = make_curry_proc(proc, passed, arity);
        return arity;
    }
    else {
        return rb_proc_call_with_block(proc, check_argc(RARRAY_LEN(passed)), RARRAY_CONST_PTR(passed), blockarg);
    }
}

 /*
  *  call-seq:
  *     prc.curry         -> a_proc
  *     prc.curry(arity)  -> a_proc
  *
  *  Returns a curried proc. If the optional <i>arity</i> argument is given,
  *  it determines the number of arguments.
  *  A curried proc receives some arguments. If a sufficient number of
  *  arguments are supplied, it passes the supplied arguments to the original
  *  proc and returns the result. Otherwise, returns another curried proc that
  *  takes the rest of arguments.
  *
  *  The optional <i>arity</i> argument should be supplied when currying procs with
  *  variable arguments to determine how many arguments are needed before the proc is
  *  called.
  *
  *     b = proc {|x, y, z| (x||0) + (y||0) + (z||0) }
  *     p b.curry[1][2][3]           #=> 6
  *     p b.curry[1, 2][3, 4]        #=> 6
  *     p b.curry(5)[1][2][3][4][5]  #=> 6
  *     p b.curry(5)[1, 2][3, 4][5]  #=> 6
  *     p b.curry(1)[1]              #=> 1
  *
  *     b = proc {|x, y, z, *w| (x||0) + (y||0) + (z||0) + w.inject(0, &:+) }
  *     p b.curry[1][2][3]           #=> 6
  *     p b.curry[1, 2][3, 4]        #=> 10
  *     p b.curry(5)[1][2][3][4][5]  #=> 15
  *     p b.curry(5)[1, 2][3, 4][5]  #=> 15
  *     p b.curry(1)[1]              #=> 1
  *
  *     b = lambda {|x, y, z| (x||0) + (y||0) + (z||0) }
  *     p b.curry[1][2][3]           #=> 6
  *     p b.curry[1, 2][3, 4]        #=> wrong number of arguments (given 4, expected 3)
  *     p b.curry(5)                 #=> wrong number of arguments (given 5, expected 3)
  *     p b.curry(1)                 #=> wrong number of arguments (given 1, expected 3)
  *
  *     b = lambda {|x, y, z, *w| (x||0) + (y||0) + (z||0) + w.inject(0, &:+) }
  *     p b.curry[1][2][3]           #=> 6
  *     p b.curry[1, 2][3, 4]        #=> 10
  *     p b.curry(5)[1][2][3][4][5]  #=> 15
  *     p b.curry(5)[1, 2][3, 4][5]  #=> 15
  *     p b.curry(1)                 #=> wrong number of arguments (given 1, expected 3)
  *
  *     b = proc { :foo }
  *     p b.curry[]                  #=> :foo
  */
static VALUE
proc_curry(int argc, const VALUE *argv, VALUE self)
{
    int sarity, max_arity, min_arity = rb_proc_min_max_arity(self, &max_arity);
    VALUE arity;

    if (rb_check_arity(argc, 0, 1) == 0 || NIL_P(arity = argv[0])) {
        arity = INT2FIX(min_arity);
    }
    else {
        sarity = FIX2INT(arity);
        if (rb_proc_lambda_p(self)) {
            rb_check_arity(sarity, min_arity, max_arity);
        }
    }

    return make_curry_proc(self, rb_ary_new(), arity);
}

/*
 *  call-seq:
 *     meth.curry        -> proc
 *     meth.curry(arity) -> proc
 *
 *  Returns a curried proc based on the method. When the proc is called with a number of
 *  arguments that is lower than the method's arity, then another curried proc is returned.
 *  Only when enough arguments have been supplied to satisfy the method signature, will the
 *  method actually be called.
 *
 *  The optional <i>arity</i> argument should be supplied when currying methods with
 *  variable arguments to determine how many arguments are needed before the method is
 *  called.
 *
 *     def foo(a,b,c)
 *       [a, b, c]
 *     end
 *
 *     proc  = self.method(:foo).curry
 *     proc2 = proc.call(1, 2)          #=> #<Proc>
 *     proc2.call(3)                    #=> [1,2,3]
 *
 *     def vararg(*args)
 *       args
 *     end
 *
 *     proc = self.method(:vararg).curry(4)
 *     proc2 = proc.call(:x)      #=> #<Proc>
 *     proc3 = proc2.call(:y, :z) #=> #<Proc>
 *     proc3.call(:a)             #=> [:x, :y, :z, :a]
 */

static VALUE
rb_method_curry(int argc, const VALUE *argv, VALUE self)
{
    VALUE proc = method_to_proc(self);
    return proc_curry(argc, argv, proc);
}

static VALUE
compose(RB_BLOCK_CALL_FUNC_ARGLIST(_, args))
{
    VALUE f, g, fargs;
    f = RARRAY_AREF(args, 0);
    g = RARRAY_AREF(args, 1);

    if (rb_obj_is_proc(g))
        fargs = rb_proc_call_with_block_kw(g, argc, argv, blockarg, RB_PASS_CALLED_KEYWORDS);
    else
        fargs = rb_funcall_with_block_kw(g, idCall, argc, argv, blockarg, RB_PASS_CALLED_KEYWORDS);

    if (rb_obj_is_proc(f))
        return rb_proc_call(f, rb_ary_new3(1, fargs));
    else
        return rb_funcallv(f, idCall, 1, &fargs);
}

static VALUE
to_callable(VALUE f)
{
    VALUE mesg;

    if (rb_obj_is_proc(f)) return f;
    if (rb_obj_is_method(f)) return f;
    if (rb_obj_respond_to(f, idCall, TRUE)) return f;
    mesg = rb_fstring_lit("callable object is expected");
    rb_exc_raise(rb_exc_new_str(rb_eTypeError, mesg));
}

static VALUE rb_proc_compose_to_left(VALUE self, VALUE g);
static VALUE rb_proc_compose_to_right(VALUE self, VALUE g);

/*
 *  call-seq:
 *     prc << g -> a_proc
 *
 *  Returns a proc that is the composition of this proc and the given <i>g</i>.
 *  The returned proc takes a variable number of arguments, calls <i>g</i> with them
 *  then calls this proc with the result.
 *
 *     f = proc {|x| x * x }
 *     g = proc {|x| x + x }
 *     p (f << g).call(2) #=> 16
 *
 *  See Proc#>> for detailed explanations.
 */
static VALUE
proc_compose_to_left(VALUE self, VALUE g)
{
    return rb_proc_compose_to_left(self, to_callable(g));
}

static VALUE
rb_proc_compose_to_left(VALUE self, VALUE g)
{
    VALUE proc, args, procs[2];
    rb_proc_t *procp;
    int is_lambda;

    procs[0] = self;
    procs[1] = g;
    args = rb_ary_tmp_new_from_values(0, 2, procs);

    if (rb_obj_is_proc(g)) {
        GetProcPtr(g, procp);
        is_lambda = procp->is_lambda;
    }
    else {
        VM_ASSERT(rb_obj_is_method(g) || rb_obj_respond_to(g, idCall, TRUE));
        is_lambda = 1;
    }

    proc = rb_proc_new(compose, args);
    GetProcPtr(proc, procp);
    procp->is_lambda = is_lambda;

    return proc;
}

/*
 *  call-seq:
 *     prc >> g -> a_proc
 *
 *  Returns a proc that is the composition of this proc and the given <i>g</i>.
 *  The returned proc takes a variable number of arguments, calls this proc with them
 *  then calls <i>g</i> with the result.
 *
 *     f = proc {|x| x * x }
 *     g = proc {|x| x + x }
 *     p (f >> g).call(2) #=> 8
 *
 *  <i>g</i> could be other Proc, or Method, or any other object responding to
 *  +call+ method:
 *
 *     class Parser
 *       def self.call(text)
 *          # ...some complicated parsing logic...
 *       end
 *     end
 *
 *     pipeline = File.method(:read) >> Parser >> proc { |data| puts "data size: #{data.count}" }
 *     pipeline.call('data.json')
 *
 *  See also Method#>> and Method#<<.
 */
static VALUE
proc_compose_to_right(VALUE self, VALUE g)
{
    return rb_proc_compose_to_right(self, to_callable(g));
}

static VALUE
rb_proc_compose_to_right(VALUE self, VALUE g)
{
    VALUE proc, args, procs[2];
    rb_proc_t *procp;
    int is_lambda;

    procs[0] = g;
    procs[1] = self;
    args = rb_ary_tmp_new_from_values(0, 2, procs);

    GetProcPtr(self, procp);
    is_lambda = procp->is_lambda;

    proc = rb_proc_new(compose, args);
    GetProcPtr(proc, procp);
    procp->is_lambda = is_lambda;

    return proc;
}

/*
 *  call-seq:
 *     meth << g -> a_proc
 *
 *  Returns a proc that is the composition of this method and the given <i>g</i>.
 *  The returned proc takes a variable number of arguments, calls <i>g</i> with them
 *  then calls this method with the result.
 *
 *     def f(x)
 *       x * x
 *     end
 *
 *     f = self.method(:f)
 *     g = proc {|x| x + x }
 *     p (f << g).call(2) #=> 16
 */
static VALUE
rb_method_compose_to_left(VALUE self, VALUE g)
{
    g = to_callable(g);
    self = method_to_proc(self);
    return proc_compose_to_left(self, g);
}

/*
 *  call-seq:
 *     meth >> g -> a_proc
 *
 *  Returns a proc that is the composition of this method and the given <i>g</i>.
 *  The returned proc takes a variable number of arguments, calls this method
 *  with them then calls <i>g</i> with the result.
 *
 *     def f(x)
 *       x * x
 *     end
 *
 *     f = self.method(:f)
 *     g = proc {|x| x + x }
 *     p (f >> g).call(2) #=> 8
 */
static VALUE
rb_method_compose_to_right(VALUE self, VALUE g)
{
    g = to_callable(g);
    self = method_to_proc(self);
    return proc_compose_to_right(self, g);
}

/*
 *  call-seq:
 *     proc.ruby2_keywords -> proc
 *
 *  Marks the proc as passing keywords through a normal argument splat.
 *  This should only be called on procs that accept an argument splat
 *  (<tt>*args</tt>) but not explicit keywords or a keyword splat.  It
 *  marks the proc such that if the proc is called with keyword arguments,
 *  the final hash argument is marked with a special flag such that if it
 *  is the final element of a normal argument splat to another method call,
 *  and that method call does not include explicit keywords or a keyword
 *  splat, the final element is interpreted as keywords.  In other words,
 *  keywords will be passed through the proc to other methods.
 *
 *  This should only be used for procs that delegate keywords to another
 *  method, and only for backwards compatibility with Ruby versions before
 *  2.7.
 *
 *  This method will probably be removed at some point, as it exists only
 *  for backwards compatibility. As it does not exist in Ruby versions
 *  before 2.7, check that the proc responds to this method before calling
 *  it. Also, be aware that if this method is removed, the behavior of the
 *  proc will change so that it does not pass through keywords.
 *
 *    module Mod
 *      foo = ->(meth, *args, &block) do
 *        send(:"do_#{meth}", *args, &block)
 *      end
 *      foo.ruby2_keywords if foo.respond_to?(:ruby2_keywords)
 *    end
 */

static VALUE
proc_ruby2_keywords(VALUE procval)
{
    rb_proc_t *proc;
    GetProcPtr(procval, proc);

    rb_check_frozen(procval);

    if (proc->is_from_method) {
            rb_warn("Skipping set of ruby2_keywords flag for proc (proc created from method)");
            return procval;
    }

    switch (proc->block.type) {
      case block_type_iseq:
        if (ISEQ_BODY(proc->block.as.captured.code.iseq)->param.flags.has_rest &&
                !ISEQ_BODY(proc->block.as.captured.code.iseq)->param.flags.has_kw &&
                !ISEQ_BODY(proc->block.as.captured.code.iseq)->param.flags.has_kwrest) {
            ISEQ_BODY(proc->block.as.captured.code.iseq)->param.flags.ruby2_keywords = 1;
        }
        else {
            rb_warn("Skipping set of ruby2_keywords flag for proc (proc accepts keywords or proc does not accept argument splat)");
        }
        break;
      default:
        rb_warn("Skipping set of ruby2_keywords flag for proc (proc not defined in Ruby)");
        break;
    }

    return procval;
}

/*
 *  Document-class: LocalJumpError
 *
 *  Raised when Ruby can't yield as requested.
 *
 *  A typical scenario is attempting to yield when no block is given:
 *
 *     def call_block
 *       yield 42
 *     end
 *     call_block
 *
 *  <em>raises the exception:</em>
 *
 *     LocalJumpError: no block given (yield)
 *
 *  A more subtle example:
 *
 *     def get_me_a_return
 *       Proc.new { return 42 }
 *     end
 *     get_me_a_return.call
 *
 *  <em>raises the exception:</em>
 *
 *     LocalJumpError: unexpected return
 */

/*
 *  Document-class: SystemStackError
 *
 *  Raised in case of a stack overflow.
 *
 *     def me_myself_and_i
 *       me_myself_and_i
 *     end
 *     me_myself_and_i
 *
 *  <em>raises the exception:</em>
 *
 *    SystemStackError: stack level too deep
 */

/*
 *  Document-class: Proc
 *
 * A +Proc+ object is an encapsulation of a block of code, which can be stored
 * in a local variable, passed to a method or another Proc, and can be called.
 * Proc is an essential concept in Ruby and a core of its functional
 * programming features.
 *
 *      square = Proc.new {|x| x**2 }
 *
 *      square.call(3)  #=> 9
 *      # shorthands:
 *      square.(3)      #=> 9
 *      square[3]       #=> 9
 *
 * Proc objects are _closures_, meaning they remember and can use the entire
 * context in which they were created.
 *
 *     def gen_times(factor)
 *       Proc.new {|n| n*factor } # remembers the value of factor at the moment of creation
 *     end
 *
 *     times3 = gen_times(3)
 *     times5 = gen_times(5)
 *
 *     times3.call(12)               #=> 36
 *     times5.call(5)                #=> 25
 *     times3.call(times5.call(4))   #=> 60
 *
 * == Creation
 *
 * There are several methods to create a Proc
 *
 * * Use the Proc class constructor:
 *
 *      proc1 = Proc.new {|x| x**2 }
 *
 * * Use the Kernel#proc method as a shorthand of Proc.new:
 *
 *      proc2 = proc {|x| x**2 }
 *
 * * Receiving a block of code into proc argument (note the <code>&</code>):
 *
 *      def make_proc(&block)
 *        block
 *      end
 *
 *      proc3 = make_proc {|x| x**2 }
 *
 * * Construct a proc with lambda semantics using the Kernel#lambda method
 *   (see below for explanations about lambdas):
 *
 *      lambda1 = lambda {|x| x**2 }
 *
 * * Use the {Lambda proc literal}[rdoc-ref:syntax/literals.rdoc@Lambda+Proc+Literals] syntax
 *   (also constructs a proc with lambda semantics):
 *
 *      lambda2 = ->(x) { x**2 }
 *
 * == Lambda and non-lambda semantics
 *
 * Procs are coming in two flavors: lambda and non-lambda (regular procs).
 * Differences are:
 *
 * * In lambdas, +return+ and +break+ means exit from this lambda;
 * * In non-lambda procs, +return+ means exit from embracing method
 *   (and will throw +LocalJumpError+ if invoked outside the method);
 * * In non-lambda procs, +break+ means exit from the method which the block given for.
 *   (and will throw +LocalJumpError+ if invoked after the method returns);
 * * In lambdas, arguments are treated in the same way as in methods: strict,
 *   with +ArgumentError+ for mismatching argument number,
 *   and no additional argument processing;
 * * Regular procs accept arguments more generously: missing arguments
 *   are filled with +nil+, single Array arguments are deconstructed if the
 *   proc has multiple arguments, and there is no error raised on extra
 *   arguments.
 *
 * Examples:
 *
 *      # +return+ in non-lambda proc, +b+, exits +m2+.
 *      # (The block +{ return }+ is given for +m1+ and embraced by +m2+.)
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1 { return }; $a << :m2 end; m2; p $a
 *      #=> []
 *
 *      # +break+ in non-lambda proc, +b+, exits +m1+.
 *      # (The block +{ break }+ is given for +m1+ and embraced by +m2+.)
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1 { break }; $a << :m2 end; m2; p $a
 *      #=> [:m2]
 *
 *      # +next+ in non-lambda proc, +b+, exits the block.
 *      # (The block +{ next }+ is given for +m1+ and embraced by +m2+.)
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1 { next }; $a << :m2 end; m2; p $a
 *      #=> [:m1, :m2]
 *
 *      # Using +proc+ method changes the behavior as follows because
 *      # The block is given for +proc+ method and embraced by +m2+.
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1(&proc { return }); $a << :m2 end; m2; p $a
 *      #=> []
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1(&proc { break }); $a << :m2 end; m2; p $a
 *      # break from proc-closure (LocalJumpError)
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1(&proc { next }); $a << :m2 end; m2; p $a
 *      #=> [:m1, :m2]
 *
 *      # +return+, +break+ and +next+ in the stubby lambda exits the block.
 *      # (+lambda+ method behaves same.)
 *      # (The block is given for stubby lambda syntax and embraced by +m2+.)
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1(&-> { return }); $a << :m2 end; m2; p $a
 *      #=> [:m1, :m2]
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1(&-> { break }); $a << :m2 end; m2; p $a
 *      #=> [:m1, :m2]
 *      $a = []; def m1(&b) b.call; $a << :m1 end; def m2() m1(&-> { next }); $a << :m2 end; m2; p $a
 *      #=> [:m1, :m2]
 *
 *      p = proc {|x, y| "x=#{x}, y=#{y}" }
 *      p.call(1, 2)      #=> "x=1, y=2"
 *      p.call([1, 2])    #=> "x=1, y=2", array deconstructed
 *      p.call(1, 2, 8)   #=> "x=1, y=2", extra argument discarded
 *      p.call(1)         #=> "x=1, y=", nil substituted instead of error
 *
 *      l = lambda {|x, y| "x=#{x}, y=#{y}" }
 *      l.call(1, 2)      #=> "x=1, y=2"
 *      l.call([1, 2])    # ArgumentError: wrong number of arguments (given 1, expected 2)
 *      l.call(1, 2, 8)   # ArgumentError: wrong number of arguments (given 3, expected 2)
 *      l.call(1)         # ArgumentError: wrong number of arguments (given 1, expected 2)
 *
 *      def test_return
 *        -> { return 3 }.call      # just returns from lambda into method body
 *        proc { return 4 }.call    # returns from method
 *        return 5
 *      end
 *
 *      test_return # => 4, return from proc
 *
 * Lambdas are useful as self-sufficient functions, in particular useful as
 * arguments to higher-order functions, behaving exactly like Ruby methods.
 *
 * Procs are useful for implementing iterators:
 *
 *      def test
 *        [[1, 2], [3, 4], [5, 6]].map {|a, b| return a if a + b > 10 }
 *                                  #  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
 *      end
 *
 * Inside +map+, the block of code is treated as a regular (non-lambda) proc,
 * which means that the internal arrays will be deconstructed to pairs of
 * arguments, and +return+ will exit from the method +test+. That would
 * not be possible with a stricter lambda.
 *
 * You can tell a lambda from a regular proc by using the #lambda? instance method.
 *
 * Lambda semantics is typically preserved during the proc lifetime, including
 * <code>&</code>-deconstruction to a block of code:
 *
 *      p = proc {|x, y| x }
 *      l = lambda {|x, y| x }
 *      [[1, 2], [3, 4]].map(&p) #=> [1, 3]
 *      [[1, 2], [3, 4]].map(&l) # ArgumentError: wrong number of arguments (given 1, expected 2)
 *
 * The only exception is dynamic method definition: even if defined by
 * passing a non-lambda proc, methods still have normal semantics of argument
 * checking.
 *
 *   class C
 *     define_method(:e, &proc {})
 *   end
 *   C.new.e(1,2)       #=> ArgumentError
 *   C.new.method(:e).to_proc.lambda?   #=> true
 *
 * This exception ensures that methods never have unusual argument passing
 * conventions, and makes it easy to have wrappers defining methods that
 * behave as usual.
 *
 *   class C
 *     def self.def2(name, &body)
 *       define_method(name, &body)
 *     end
 *
 *     def2(:f) {}
 *   end
 *   C.new.f(1,2)       #=> ArgumentError
 *
 * The wrapper <code>def2</code> receives _body_ as a non-lambda proc,
 * yet defines a method which has normal semantics.
 *
 * == Conversion of other objects to procs
 *
 * Any object that implements the +to_proc+ method can be converted into
 * a proc by the <code>&</code> operator, and therefore can be
 * consumed by iterators.
 *

 *      class Greeter
 *        def initialize(greeting)
 *          @greeting = greeting
 *        end
 *
 *        def to_proc
 *          proc {|name| "#{@greeting}, #{name}!" }
 *        end
 *      end
 *
 *      hi = Greeter.new("Hi")
 *      hey = Greeter.new("Hey")
 *      ["Bob", "Jane"].map(&hi)    #=> ["Hi, Bob!", "Hi, Jane!"]
 *      ["Bob", "Jane"].map(&hey)   #=> ["Hey, Bob!", "Hey, Jane!"]
 *
 * Of the Ruby core classes, this method is implemented by Symbol,
 * Method, and Hash.
 *
 *      :to_s.to_proc.call(1)           #=> "1"
 *      [1, 2].map(&:to_s)              #=> ["1", "2"]
 *
 *      method(:puts).to_proc.call(1)   # prints 1
 *      [1, 2].each(&method(:puts))     # prints 1, 2
 *
 *      {test: 1}.to_proc.call(:test)       #=> 1
 *      %i[test many keys].map(&{test: 1})  #=> [1, nil, nil]
 *
 * == Orphaned Proc
 *
 * +return+ and +break+ in a block exit a method.
 * If a Proc object is generated from the block and the Proc object
 * survives until the method is returned, +return+ and +break+ cannot work.
 * In such case, +return+ and +break+ raises LocalJumpError.
 * A Proc object in such situation is called as orphaned Proc object.
 *
 * Note that the method to exit is different for +return+ and +break+.
 * There is a situation that orphaned for +break+ but not orphaned for +return+.
 *
 *     def m1(&b) b.call end; def m2(); m1 { return } end; m2 # ok
 *     def m1(&b) b.call end; def m2(); m1 { break } end; m2 # ok
 *
 *     def m1(&b) b end; def m2(); m1 { return }.call end; m2 # ok
 *     def m1(&b) b end; def m2(); m1 { break }.call end; m2 # LocalJumpError
 *
 *     def m1(&b) b end; def m2(); m1 { return } end; m2.call # LocalJumpError
 *     def m1(&b) b end; def m2(); m1 { break } end; m2.call # LocalJumpError
 *
 * Since +return+ and +break+ exits the block itself in lambdas,
 * lambdas cannot be orphaned.
 *
 * == Numbered parameters
 *
 * Numbered parameters are implicitly defined block parameters intended to
 * simplify writing short blocks:
 *
 *     # Explicit parameter:
 *     %w[test me please].each { |str| puts str.upcase } # prints TEST, ME, PLEASE
 *     (1..5).map { |i| i**2 } # => [1, 4, 9, 16, 25]
 *
 *     # Implicit parameter:
 *     %w[test me please].each { puts _1.upcase } # prints TEST, ME, PLEASE
 *     (1..5).map { _1**2 } # => [1, 4, 9, 16, 25]
 *
 * Parameter names from +_1+ to +_9+ are supported:
 *
 *     [10, 20, 30].zip([40, 50, 60], [70, 80, 90]).map { _1 + _2 + _3 }
 *     # => [120, 150, 180]
 *
 * Though, it is advised to resort to them wisely, probably limiting
 * yourself to +_1+ and +_2+, and to one-line blocks.
 *
 * Numbered parameters can't be used together with explicitly named
 * ones:
 *
 *     [10, 20, 30].map { |x| _1**2 }
 *     # SyntaxError (ordinary parameter is defined)
 *
 * To avoid conflicts, naming local variables or method
 * arguments +_1+, +_2+ and so on, causes a warning.
 *
 *     _1 = 'test'
 *     # warning: `_1' is reserved as numbered parameter
 *
 * Using implicit numbered parameters affects block's arity:
 *
 *     p = proc { _1 + _2 }
 *     l = lambda { _1 + _2 }
 *     p.parameters     # => [[:opt, :_1], [:opt, :_2]]
 *     p.arity          # => 2
 *     l.parameters     # => [[:req, :_1], [:req, :_2]]
 *     l.arity          # => 2
 *
 * Blocks with numbered parameters can't be nested:
 *
 *     %w[test me].each { _1.each_char { p _1 } }
 *     # SyntaxError (numbered parameter is already used in outer block here)
 *     # %w[test me].each { _1.each_char { p _1 } }
 *     #                    ^~
 *
 * Numbered parameters were introduced in Ruby 2.7.
 */


void
Init_Proc(void)
{
#undef rb_intern
    /* Proc */
    rb_cProc = rb_define_class("Proc", rb_cObject);
    rb_undef_alloc_func(rb_cProc);
    rb_define_singleton_method(rb_cProc, "new", rb_proc_s_new, -1);

    rb_add_method_optimized(rb_cProc, idCall, OPTIMIZED_METHOD_TYPE_CALL, 0, METHOD_VISI_PUBLIC);
    rb_add_method_optimized(rb_cProc, rb_intern("[]"), OPTIMIZED_METHOD_TYPE_CALL, 0, METHOD_VISI_PUBLIC);
    rb_add_method_optimized(rb_cProc, rb_intern("==="), OPTIMIZED_METHOD_TYPE_CALL, 0, METHOD_VISI_PUBLIC);
    rb_add_method_optimized(rb_cProc, rb_intern("yield"), OPTIMIZED_METHOD_TYPE_CALL, 0, METHOD_VISI_PUBLIC);

#if 0 /* for RDoc */
    rb_define_method(rb_cProc, "call", proc_call, -1);
    rb_define_method(rb_cProc, "[]", proc_call, -1);
    rb_define_method(rb_cProc, "===", proc_call, -1);
    rb_define_method(rb_cProc, "yield", proc_call, -1);
#endif

    rb_define_method(rb_cProc, "to_proc", proc_to_proc, 0);
    rb_define_method(rb_cProc, "arity", proc_arity, 0);
    rb_define_method(rb_cProc, "clone", proc_clone, 0);
    rb_define_method(rb_cProc, "dup", rb_proc_dup, 0);
    rb_define_method(rb_cProc, "hash", proc_hash, 0);
    rb_define_method(rb_cProc, "to_s", proc_to_s, 0);
    rb_define_alias(rb_cProc, "inspect", "to_s");
    rb_define_method(rb_cProc, "lambda?", rb_proc_lambda_p, 0);
    rb_define_method(rb_cProc, "binding", proc_binding, 0);
    rb_define_method(rb_cProc, "curry", proc_curry, -1);
    rb_define_method(rb_cProc, "<<", proc_compose_to_left, 1);
    rb_define_method(rb_cProc, ">>", proc_compose_to_right, 1);
    rb_define_method(rb_cProc, "==", proc_eq, 1);
    rb_define_method(rb_cProc, "eql?", proc_eq, 1);
    rb_define_method(rb_cProc, "source_location", rb_proc_location, 0);
    rb_define_method(rb_cProc, "parameters", rb_proc_parameters, -1);
    rb_define_method(rb_cProc, "ruby2_keywords", proc_ruby2_keywords, 0);
    // rb_define_method(rb_cProc, "isolate", rb_proc_isolate, 0); is not accepted.

    /* Exceptions */
    rb_eLocalJumpError = rb_define_class("LocalJumpError", rb_eStandardError);
    rb_define_method(rb_eLocalJumpError, "exit_value", localjump_xvalue, 0);
    rb_define_method(rb_eLocalJumpError, "reason", localjump_reason, 0);

    rb_eSysStackError = rb_define_class("SystemStackError", rb_eException);
    rb_vm_register_special_exception(ruby_error_sysstack, rb_eSysStackError, "stack level too deep");

    /* utility functions */
    rb_define_global_function("proc", f_proc, 0);
    rb_define_global_function("lambda", f_lambda, 0);

    /* Method */
    rb_cMethod = rb_define_class("Method", rb_cObject);
    rb_undef_alloc_func(rb_cMethod);
    rb_undef_method(CLASS_OF(rb_cMethod), "new");
    rb_define_method(rb_cMethod, "==", method_eq, 1);
    rb_define_method(rb_cMethod, "eql?", method_eq, 1);
    rb_define_method(rb_cMethod, "hash", method_hash, 0);
    rb_define_method(rb_cMethod, "clone", method_clone, 0);
    rb_define_method(rb_cMethod, "call", rb_method_call_pass_called_kw, -1);
    rb_define_method(rb_cMethod, "===", rb_method_call_pass_called_kw, -1);
    rb_define_method(rb_cMethod, "curry", rb_method_curry, -1);
    rb_define_method(rb_cMethod, "<<", rb_method_compose_to_left, 1);
    rb_define_method(rb_cMethod, ">>", rb_method_compose_to_right, 1);
    rb_define_method(rb_cMethod, "[]", rb_method_call_pass_called_kw, -1);
    rb_define_method(rb_cMethod, "arity", method_arity_m, 0);
    rb_define_method(rb_cMethod, "inspect", method_inspect, 0);
    rb_define_method(rb_cMethod, "to_s", method_inspect, 0);
    rb_define_method(rb_cMethod, "to_proc", method_to_proc, 0);
    rb_define_method(rb_cMethod, "receiver", method_receiver, 0);
    rb_define_method(rb_cMethod, "name", method_name, 0);
    rb_define_method(rb_cMethod, "original_name", method_original_name, 0);
    rb_define_method(rb_cMethod, "owner", method_owner, 0);
    rb_define_method(rb_cMethod, "unbind", method_unbind, 0);
    rb_define_method(rb_cMethod, "source_location", rb_method_location, 0);
    rb_define_method(rb_cMethod, "parameters", rb_method_parameters, 0);
    rb_define_method(rb_cMethod, "super_method", method_super_method, 0);
    rb_define_method(rb_mKernel, "method", rb_obj_method, 1);
    rb_define_method(rb_mKernel, "public_method", rb_obj_public_method, 1);
    rb_define_method(rb_mKernel, "singleton_method", rb_obj_singleton_method, 1);

    /* UnboundMethod */
    rb_cUnboundMethod = rb_define_class("UnboundMethod", rb_cObject);
    rb_undef_alloc_func(rb_cUnboundMethod);
    rb_undef_method(CLASS_OF(rb_cUnboundMethod), "new");
    rb_define_method(rb_cUnboundMethod, "==", method_eq, 1);
    rb_define_method(rb_cUnboundMethod, "eql?", method_eq, 1);
    rb_define_method(rb_cUnboundMethod, "hash", method_hash, 0);
    rb_define_method(rb_cUnboundMethod, "clone", method_clone, 0);
    rb_define_method(rb_cUnboundMethod, "arity", method_arity_m, 0);
    rb_define_method(rb_cUnboundMethod, "inspect", method_inspect, 0);
    rb_define_method(rb_cUnboundMethod, "to_s", method_inspect, 0);
    rb_define_method(rb_cUnboundMethod, "name", method_name, 0);
    rb_define_method(rb_cUnboundMethod, "original_name", method_original_name, 0);
    rb_define_method(rb_cUnboundMethod, "owner", method_owner, 0);
    rb_define_method(rb_cUnboundMethod, "bind", umethod_bind, 1);
    rb_define_method(rb_cUnboundMethod, "bind_call", umethod_bind_call, -1);
    rb_define_method(rb_cUnboundMethod, "source_location", rb_method_location, 0);
    rb_define_method(rb_cUnboundMethod, "parameters", rb_method_parameters, 0);
    rb_define_method(rb_cUnboundMethod, "super_method", method_super_method, 0);

    /* Module#*_method */
    rb_define_method(rb_cModule, "instance_method", rb_mod_instance_method, 1);
    rb_define_method(rb_cModule, "public_instance_method", rb_mod_public_instance_method, 1);
    rb_define_method(rb_cModule, "define_method", rb_mod_define_method, -1);

    /* Kernel */
    rb_define_method(rb_mKernel, "define_singleton_method", rb_obj_define_method, -1);

    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
                             "define_method", top_define_method, -1);
}

/*
 *  Objects of class Binding encapsulate the execution context at some
 *  particular place in the code and retain this context for future
 *  use. The variables, methods, value of <code>self</code>, and
 *  possibly an iterator block that can be accessed in this context
 *  are all retained. Binding objects can be created using
 *  Kernel#binding, and are made available to the callback of
 *  Kernel#set_trace_func and instances of TracePoint.
 *
 *  These binding objects can be passed as the second argument of the
 *  Kernel#eval method, establishing an environment for the
 *  evaluation.
 *
 *     class Demo
 *       def initialize(n)
 *         @secret = n
 *       end
 *       def get_binding
 *         binding
 *       end
 *     end
 *
 *     k1 = Demo.new(99)
 *     b1 = k1.get_binding
 *     k2 = Demo.new(-3)
 *     b2 = k2.get_binding
 *
 *     eval("@secret", b1)   #=> 99
 *     eval("@secret", b2)   #=> -3
 *     eval("@secret")       #=> nil
 *
 *  Binding objects have no class-specific methods.
 *
 */

void
Init_Binding(void)
{
    rb_cBinding = rb_define_class("Binding", rb_cObject);
    rb_undef_alloc_func(rb_cBinding);
    rb_undef_method(CLASS_OF(rb_cBinding), "new");
    rb_define_method(rb_cBinding, "clone", binding_clone, 0);
    rb_define_method(rb_cBinding, "dup", binding_dup, 0);
    rb_define_method(rb_cBinding, "eval", bind_eval, -1);
    rb_define_method(rb_cBinding, "local_variables", bind_local_variables, 0);
    rb_define_method(rb_cBinding, "local_variable_get", bind_local_variable_get, 1);
    rb_define_method(rb_cBinding, "local_variable_set", bind_local_variable_set, 2);
    rb_define_method(rb_cBinding, "local_variable_defined?", bind_local_variable_defined_p, 1);
    rb_define_method(rb_cBinding, "receiver", bind_receiver, 0);
    rb_define_method(rb_cBinding, "source_location", bind_location, 0);
    rb_define_global_function("binding", rb_f_binding, 0);
}
