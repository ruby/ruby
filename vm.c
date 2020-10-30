/**********************************************************************

  Vm.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#define vm_exec rb_vm_exec

#include "eval_intern.h"
#include "gc.h"
#include "internal.h"
#include "internal/compile.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/inits.h"
#include "internal/mjit.h"
#include "internal/object.h"
#include "internal/parse.h"
#include "internal/proc.h"
#include "internal/re.h"
#include "internal/symbol.h"
#include "internal/vm.h"
#include "internal/sanitizers.h"
#include "iseq.h"
#include "mjit.h"
#include "ruby/st.h"
#include "ruby/vm.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "vm_debug.h"
#include "vm_exec.h"
#include "vm_insnhelper.h"
#include "ractor.h"
#include "vm_sync.h"

#include "builtin.h"

#ifndef MJIT_HEADER
#include "probes.h"
#else
#include "probes.dmyh"
#endif
#include "probes_helper.h"

VALUE rb_str_concat_literals(size_t, const VALUE*);

/* :FIXME: This #ifdef is because we build pch in case of mswin and
 * not in case of other situations.  That distinction might change in
 * a future.  We would better make it detectable in something better
 * than just _MSC_VER. */
#ifdef _MSC_VER
RUBY_FUNC_EXPORTED
#else
MJIT_FUNC_EXPORTED
#endif
VALUE vm_exec(rb_execution_context_t *, int);

PUREFUNC(static inline const VALUE *VM_EP_LEP(const VALUE *));
static inline const VALUE *
VM_EP_LEP(const VALUE *ep)
{
    while (!VM_ENV_LOCAL_P(ep)) {
	ep = VM_ENV_PREV_EP(ep);
    }
    return ep;
}

static inline const rb_control_frame_t *
rb_vm_search_cf_from_ep(const rb_execution_context_t *ec, const rb_control_frame_t *cfp, const VALUE * const ep)
{
    if (!ep) {
	return NULL;
    }
    else {
	const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(ec); /* end of control frame pointer */

	while (cfp < eocfp) {
	    if (cfp->ep == ep) {
		return cfp;
	    }
	    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	}

	return NULL;
    }
}

const VALUE *
rb_vm_ep_local_ep(const VALUE *ep)
{
    return VM_EP_LEP(ep);
}

PUREFUNC(static inline const VALUE *VM_CF_LEP(const rb_control_frame_t * const cfp));
static inline const VALUE *
VM_CF_LEP(const rb_control_frame_t * const cfp)
{
    return VM_EP_LEP(cfp->ep);
}

static inline const VALUE *
VM_CF_PREV_EP(const rb_control_frame_t * const cfp)
{
    return VM_ENV_PREV_EP(cfp->ep);
}

PUREFUNC(static inline VALUE VM_CF_BLOCK_HANDLER(const rb_control_frame_t * const cfp));
static inline VALUE
VM_CF_BLOCK_HANDLER(const rb_control_frame_t * const cfp)
{
    const VALUE *ep = VM_CF_LEP(cfp);
    return VM_ENV_BLOCK_HANDLER(ep);
}

int
rb_vm_cframe_keyword_p(const rb_control_frame_t *cfp)
{
    return VM_FRAME_CFRAME_KW_P(cfp);
}

VALUE
rb_vm_frame_block_handler(const rb_control_frame_t *cfp)
{
    return VM_CF_BLOCK_HANDLER(cfp);
}

#if VM_CHECK_MODE > 0
static int
VM_CFP_IN_HEAP_P(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    const VALUE *start = ec->vm_stack;
    const VALUE *end = (VALUE *)ec->vm_stack + ec->vm_stack_size;
    VM_ASSERT(start != NULL);

    if (start <= (VALUE *)cfp && (VALUE *)cfp < end) {
	return FALSE;
    }
    else {
	return TRUE;
    }
}

static int
VM_EP_IN_HEAP_P(const rb_execution_context_t *ec, const VALUE *ep)
{
    const VALUE *start = ec->vm_stack;
    const VALUE *end = (VALUE *)ec->cfp;
    VM_ASSERT(start != NULL);

    if (start <= ep && ep < end) {
	return FALSE;
    }
    else {
	return TRUE;
    }
}

static int
vm_ep_in_heap_p_(const rb_execution_context_t *ec, const VALUE *ep)
{
    if (VM_EP_IN_HEAP_P(ec, ep)) {
	VALUE envval = ep[VM_ENV_DATA_INDEX_ENV]; /* VM_ENV_ENVVAL(ep); */

	if (envval != Qundef) {
	    const rb_env_t *env = (const rb_env_t *)envval;

	    VM_ASSERT(vm_assert_env(envval));
	    VM_ASSERT(VM_ENV_FLAGS(ep, VM_ENV_FLAG_ESCAPED));
	    VM_ASSERT(env->ep == ep);
	}
	return TRUE;
    }
    else {
	return FALSE;
    }
}

int
rb_vm_ep_in_heap_p(const VALUE *ep)
{
    const rb_execution_context_t *ec = GET_EC();
    if (ec->vm_stack == NULL) return TRUE;
    return vm_ep_in_heap_p_(ec, ep);
}
#endif

static struct rb_captured_block *
VM_CFP_TO_CAPTURED_BLOCK(const rb_control_frame_t *cfp)
{
    VM_ASSERT(!VM_CFP_IN_HEAP_P(GET_EC(), cfp));
    return (struct rb_captured_block *)&cfp->self;
}

static rb_control_frame_t *
VM_CAPTURED_BLOCK_TO_CFP(const struct rb_captured_block *captured)
{
    rb_control_frame_t *cfp = ((rb_control_frame_t *)((VALUE *)(captured) - 3));
    VM_ASSERT(!VM_CFP_IN_HEAP_P(GET_EC(), cfp));
    VM_ASSERT(sizeof(rb_control_frame_t)/sizeof(VALUE) == 7 + VM_DEBUG_BP_CHECK ? 1 : 0);
    return cfp;
}

static int
VM_BH_FROM_CFP_P(VALUE block_handler, const rb_control_frame_t *cfp)
{
    const struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
    return VM_TAGGED_PTR_REF(block_handler, 0x03) == captured;
}

static VALUE
vm_passed_block_handler(rb_execution_context_t *ec)
{
    VALUE block_handler = ec->passed_block_handler;
    ec->passed_block_handler = VM_BLOCK_HANDLER_NONE;
    vm_block_handler_verify(block_handler);
    return block_handler;
}

static rb_cref_t *
vm_cref_new0(VALUE klass, rb_method_visibility_t visi, int module_func, rb_cref_t *prev_cref, int pushed_by_eval, int use_prev_prev)
{
    VALUE refinements = Qnil;
    int omod_shared = FALSE;
    rb_cref_t *cref;

    /* scope */
    union {
	rb_scope_visibility_t visi;
	VALUE value;
    } scope_visi;

    scope_visi.visi.method_visi = visi;
    scope_visi.visi.module_func = module_func;

    /* refinements */
    if (prev_cref != NULL && prev_cref != (void *)1 /* TODO: why CREF_NEXT(cref) is 1? */) {
	refinements = CREF_REFINEMENTS(prev_cref);

	if (!NIL_P(refinements)) {
	    omod_shared = TRUE;
	    CREF_OMOD_SHARED_SET(prev_cref);
	}
    }

    cref = (rb_cref_t *)rb_imemo_new(imemo_cref, klass, (VALUE)(use_prev_prev ? CREF_NEXT(prev_cref) : prev_cref), scope_visi.value, refinements);

    if (pushed_by_eval) CREF_PUSHED_BY_EVAL_SET(cref);
    if (omod_shared) CREF_OMOD_SHARED_SET(cref);

    return cref;
}

static rb_cref_t *
vm_cref_new(VALUE klass, rb_method_visibility_t visi, int module_func, rb_cref_t *prev_cref, int pushed_by_eval)
{
    return vm_cref_new0(klass, visi, module_func, prev_cref, pushed_by_eval, FALSE);
}

static rb_cref_t *
vm_cref_new_use_prev(VALUE klass, rb_method_visibility_t visi, int module_func, rb_cref_t *prev_cref, int pushed_by_eval)
{
    return vm_cref_new0(klass, visi, module_func, prev_cref, pushed_by_eval, TRUE);
}

static int
ref_delete_symkey(VALUE key, VALUE value, VALUE unused)
{
    return SYMBOL_P(key) ? ST_DELETE : ST_CONTINUE;
}

static rb_cref_t *
vm_cref_dup(const rb_cref_t *cref)
{
    VALUE klass = CREF_CLASS(cref);
    const rb_scope_visibility_t *visi = CREF_SCOPE_VISI(cref);
    rb_cref_t *next_cref = CREF_NEXT(cref), *new_cref;
    int pushed_by_eval = CREF_PUSHED_BY_EVAL(cref);

    new_cref = vm_cref_new(klass, visi->method_visi, visi->module_func, next_cref, pushed_by_eval);

    if (!NIL_P(CREF_REFINEMENTS(cref))) {
        VALUE ref = rb_hash_dup(CREF_REFINEMENTS(cref));
        rb_hash_foreach(ref, ref_delete_symkey, Qnil);
        CREF_REFINEMENTS_SET(new_cref, ref);
	CREF_OMOD_SHARED_UNSET(new_cref);
    }

    return new_cref;
}

static rb_cref_t *
vm_cref_new_toplevel(rb_execution_context_t *ec)
{
    rb_cref_t *cref = vm_cref_new(rb_cObject, METHOD_VISI_PRIVATE /* toplevel visibility is private */, FALSE, NULL, FALSE);
    VALUE top_wrapper = rb_ec_thread_ptr(ec)->top_wrapper;

    if (top_wrapper) {
	cref = vm_cref_new(top_wrapper, METHOD_VISI_PRIVATE, FALSE, cref, FALSE);
    }

    return cref;
}

rb_cref_t *
rb_vm_cref_new_toplevel(void)
{
    return vm_cref_new_toplevel(GET_EC());
}

static void
vm_cref_dump(const char *mesg, const rb_cref_t *cref)
{
    fprintf(stderr, "vm_cref_dump: %s (%p)\n", mesg, (void *)cref);

    while (cref) {
	fprintf(stderr, "= cref| klass: %s\n", RSTRING_PTR(rb_class_path(CREF_CLASS(cref))));
	cref = CREF_NEXT(cref);
    }
}

void
rb_vm_block_ep_update(VALUE obj, const struct rb_block *dst, const VALUE *ep)
{
    *((const VALUE **)&dst->as.captured.ep) = ep;
    RB_OBJ_WRITTEN(obj, Qundef, VM_ENV_ENVVAL(ep));
}

static void
vm_bind_update_env(VALUE bindval, rb_binding_t *bind, VALUE envval)
{
    const rb_env_t *env = (rb_env_t *)envval;
    RB_OBJ_WRITE(bindval, &bind->block.as.captured.code.iseq, env->iseq);
    rb_vm_block_ep_update(bindval, &bind->block, env->ep);
}

#if VM_COLLECT_USAGE_DETAILS
static void vm_collect_usage_operand(int insn, int n, VALUE op);
static void vm_collect_usage_insn(int insn);
static void vm_collect_usage_register(int reg, int isset);
#endif

static VALUE vm_make_env_object(const rb_execution_context_t *ec, rb_control_frame_t *cfp);
extern VALUE rb_vm_invoke_bmethod(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self,
                                  int argc, const VALUE *argv, int kw_splat, VALUE block_handler,
                                  const rb_callable_method_entry_t *me);
static VALUE vm_invoke_proc(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self, int argc, const VALUE *argv, int kw_splat, VALUE block_handler);

#include "vm_insnhelper.c"

#ifndef MJIT_HEADER

#include "vm_exec.c"

#include "vm_method.c"
#endif /* #ifndef MJIT_HEADER */
#include "vm_eval.c"
#ifndef MJIT_HEADER

#define PROCDEBUG 0

rb_serial_t
rb_next_class_serial(void)
{
    rb_serial_t class_serial = NEXT_CLASS_SERIAL();
    mjit_add_class_serial(class_serial);
    return class_serial;
}

VALUE rb_cRubyVM;
VALUE rb_cThread;
VALUE rb_mRubyVMFrozenCore;
VALUE rb_block_param_proxy;

#define ruby_vm_redefined_flag GET_VM()->redefined_flag
VALUE ruby_vm_const_missing_count = 0;
rb_vm_t *ruby_current_vm_ptr = NULL;

#ifdef RB_THREAD_LOCAL_SPECIFIER
RB_THREAD_LOCAL_SPECIFIER rb_execution_context_t *ruby_current_ec;

#ifdef __APPLE__
  rb_execution_context_t *
  rb_current_ec(void)
  {
      return ruby_current_ec;
  }
  void
  rb_current_ec_set(rb_execution_context_t *ec)
  {
      ruby_current_ec = ec;
  }
#endif

#else
native_tls_key_t ruby_current_ec_key;
#endif

rb_event_flag_t ruby_vm_event_flags;
rb_event_flag_t ruby_vm_event_enabled_global_flags;
unsigned int    ruby_vm_event_local_num;

rb_serial_t ruby_vm_global_constant_state = 1;
rb_serial_t ruby_vm_class_serial = 1;

static const struct rb_callcache vm_empty_cc = {
    .flags = T_IMEMO | (imemo_callcache << FL_USHIFT) | VM_CALLCACHE_UNMARKABLE,
    .klass = Qfalse,
    .cme_  = NULL,
    .call_ = vm_call_general,
    .aux_  = {
        .v = Qfalse,
    }
};

static void thread_free(void *ptr);

//

void
rb_vm_inc_const_missing_count(void)
{
    ruby_vm_const_missing_count +=1;
}

MJIT_FUNC_EXPORTED int
rb_dtrace_setup(rb_execution_context_t *ec, VALUE klass, ID id,
		struct ruby_dtrace_method_hook_args *args)
{
    enum ruby_value_type type;
    if (!klass) {
	if (!ec) ec = GET_EC();
	if (!rb_ec_frame_method_id_and_class(ec, &id, 0, &klass) || !klass)
	    return FALSE;
    }
    if (RB_TYPE_P(klass, T_ICLASS)) {
	klass = RBASIC(klass)->klass;
    }
    else if (FL_TEST(klass, FL_SINGLETON)) {
	klass = rb_attr_get(klass, id__attached__);
	if (NIL_P(klass)) return FALSE;
    }
    type = BUILTIN_TYPE(klass);
    if (type == T_CLASS || type == T_ICLASS || type == T_MODULE) {
	VALUE name = rb_class_path(klass);
	const char *classname, *filename;
	const char *methodname = rb_id2name(id);
	if (methodname && (filename = rb_source_location_cstr(&args->line_no)) != 0) {
	    if (NIL_P(name) || !(classname = StringValuePtr(name)))
		classname = "<unknown>";
	    args->classname = classname;
	    args->methodname = methodname;
	    args->filename = filename;
	    args->klass = klass;
	    args->name = name;
	    return TRUE;
	}
    }
    return FALSE;
}

/*
 *  call-seq:
 *    RubyVM.stat -> Hash
 *    RubyVM.stat(hsh) -> hsh
 *    RubyVM.stat(Symbol) -> Numeric
 *
 *  Returns a Hash containing implementation-dependent counters inside the VM.
 *
 *  This hash includes information about method/constant cache serials:
 *
 *    {
 *      :global_constant_state=>481,
 *      :class_serial=>9029
 *    }
 *
 *  The contents of the hash are implementation specific and may be changed in
 *  the future.
 *
 *  This method is only expected to work on C Ruby.
 */

static VALUE
vm_stat(int argc, VALUE *argv, VALUE self)
{
    static VALUE sym_global_constant_state, sym_class_serial;
    VALUE arg = Qnil;
    VALUE hash = Qnil, key = Qnil;

    if (rb_check_arity(argc, 0, 1) == 1) {
        arg = argv[0];
	if (SYMBOL_P(arg))
	    key = arg;
	else if (RB_TYPE_P(arg, T_HASH))
	    hash = arg;
	else
	    rb_raise(rb_eTypeError, "non-hash or symbol given");
    }
    else {
	hash = rb_hash_new();
    }

    if (sym_global_constant_state == 0) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
	S(global_constant_state);
	S(class_serial);
#undef S
    }

#define SET(name, attr) \
    if (key == sym_##name) \
	return SERIALT2NUM(attr); \
    else if (hash != Qnil) \
	rb_hash_aset(hash, sym_##name, SERIALT2NUM(attr));

    SET(global_constant_state, ruby_vm_global_constant_state);
    SET(class_serial, ruby_vm_class_serial);
#undef SET

    if (!NIL_P(key)) { /* matched key should return above */
	rb_raise(rb_eArgError, "unknown key: %"PRIsVALUE, rb_sym2str(key));
    }

    return hash;
}

/* control stack frame */

static void
vm_set_top_stack(rb_execution_context_t *ec, const rb_iseq_t *iseq)
{
    if (iseq->body->type != ISEQ_TYPE_TOP) {
	rb_raise(rb_eTypeError, "Not a toplevel InstructionSequence");
    }

    /* for return */
    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_TOP | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH, rb_ec_thread_ptr(ec)->top_self,
		  VM_BLOCK_HANDLER_NONE,
		  (VALUE)vm_cref_new_toplevel(ec), /* cref or me */
		  iseq->body->iseq_encoded, ec->cfp->sp,
		  iseq->body->local_table_size, iseq->body->stack_max);
}

static void
vm_set_eval_stack(rb_execution_context_t *ec, const rb_iseq_t *iseq, const rb_cref_t *cref, const struct rb_block *base_block)
{
    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_EVAL | VM_FRAME_FLAG_FINISH,
		  vm_block_self(base_block), VM_GUARDED_PREV_EP(vm_block_ep(base_block)),
		  (VALUE)cref, /* cref or me */
		  iseq->body->iseq_encoded,
		  ec->cfp->sp, iseq->body->local_table_size,
		  iseq->body->stack_max);
}

static void
vm_set_main_stack(rb_execution_context_t *ec, const rb_iseq_t *iseq)
{
    VALUE toplevel_binding = rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING"));
    rb_binding_t *bind;

    GetBindingPtr(toplevel_binding, bind);
    RUBY_ASSERT_MESG(bind, "TOPLEVEL_BINDING is not built");

    vm_set_eval_stack(ec, iseq, 0, &bind->block);

    /* save binding */
    if (iseq->body->local_table_size > 0) {
	vm_bind_update_env(toplevel_binding, bind, vm_make_env_object(ec, ec->cfp));
    }
}

rb_control_frame_t *
rb_vm_get_binding_creatable_next_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
	if (cfp->iseq) {
	    return (rb_control_frame_t *)cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

MJIT_FUNC_EXPORTED rb_control_frame_t *
rb_vm_get_ruby_level_next_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
	if (VM_FRAME_RUBYFRAME_P(cfp)) {
	    return (rb_control_frame_t *)cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

#endif /* #ifndef MJIT_HEADER */

static rb_control_frame_t *
vm_get_ruby_level_caller_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    if (VM_FRAME_RUBYFRAME_P(cfp)) {
	return (rb_control_frame_t *)cfp;
    }

    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
	if (VM_FRAME_RUBYFRAME_P(cfp)) {
	    return (rb_control_frame_t *)cfp;
	}

	if (VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_PASSED) == FALSE) {
	    break;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

MJIT_STATIC void
rb_vm_pop_cfunc_frame(void)
{
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, cfp->self, me->def->original_id, me->called_id, me->owner, Qnil);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);
    vm_pop_frame(ec, cfp, cfp->ep);
}

#ifndef MJIT_HEADER

void
rb_vm_rewind_cfp(rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    /* check skipped frame */
    while (ec->cfp != cfp) {
#if VMDEBUG
	printf("skipped frame: %s\n", vm_frametype_name(ec->cfp));
#endif
	if (VM_FRAME_TYPE(ec->cfp) != VM_FRAME_MAGIC_CFUNC) {
	    rb_vm_pop_frame(ec);
	}
	else { /* unlikely path */
	    rb_vm_pop_cfunc_frame();
	}
    }
}

/* at exit */

void
ruby_vm_at_exit(void (*func)(rb_vm_t *))
{
    rb_vm_t *vm = GET_VM();
    rb_at_exit_list *nl = ALLOC(rb_at_exit_list);
    nl->func = func;
    nl->next = vm->at_exit;
    vm->at_exit = nl;
}

static void
ruby_vm_run_at_exit_hooks(rb_vm_t *vm)
{
    rb_at_exit_list *l = vm->at_exit;

    while (l) {
	rb_at_exit_list* t = l->next;
	rb_vm_at_exit_func *func = l->func;
	ruby_xfree(l);
	l = t;
	(*func)(vm);
    }
}

/* Env */

static VALUE check_env_value(const rb_env_t *env);

static int
check_env(const rb_env_t *env)
{
    fprintf(stderr, "---\n");
    fprintf(stderr, "envptr: %p\n", (void *)&env->ep[0]);
    fprintf(stderr, "envval: %10p ", (void *)env->ep[1]);
    dp(env->ep[1]);
    fprintf(stderr, "ep:    %10p\n", (void *)env->ep);
    if (rb_vm_env_prev_env(env)) {
	fprintf(stderr, ">>\n");
	check_env_value(rb_vm_env_prev_env(env));
	fprintf(stderr, "<<\n");
    }
    return 1;
}

static VALUE
check_env_value(const rb_env_t *env)
{
    if (check_env(env)) {
	return (VALUE)env;
    }
    rb_bug("invalid env");
    return Qnil;		/* unreachable */
}

static VALUE
vm_block_handler_escape(const rb_execution_context_t *ec, VALUE block_handler)
{
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_ifunc:
      case block_handler_type_iseq:
        return  rb_vm_make_proc(ec, VM_BH_TO_CAPT_BLOCK(block_handler), rb_cProc);

      case block_handler_type_symbol:
      case block_handler_type_proc:
        return block_handler;
    }
    VM_UNREACHABLE(vm_block_handler_escape);
    return Qnil;
}

static VALUE
vm_make_env_each(const rb_execution_context_t * const ec, rb_control_frame_t *const cfp)
{
    const VALUE * const ep = cfp->ep;
    const rb_env_t *env;
    const rb_iseq_t *env_iseq;
    VALUE *env_body, *env_ep;
    int local_size, env_size;

    if (VM_ENV_ESCAPED_P(ep)) {
	return VM_ENV_ENVVAL(ep);
    }

    if (!VM_ENV_LOCAL_P(ep)) {
	const VALUE *prev_ep = VM_ENV_PREV_EP(ep);
        if (!VM_ENV_ESCAPED_P(prev_ep)) {
            rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

            while (prev_cfp->ep != prev_ep) {
                prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(prev_cfp);
                VM_ASSERT(prev_cfp->ep != NULL);
            }

            vm_make_env_each(ec, prev_cfp);
            VM_FORCE_WRITE_SPECIAL_CONST(&ep[VM_ENV_DATA_INDEX_SPECVAL], VM_GUARDED_PREV_EP(prev_cfp->ep));
        }
    }
    else {
	VALUE block_handler = VM_ENV_BLOCK_HANDLER(ep);

	if (block_handler != VM_BLOCK_HANDLER_NONE) {
            VALUE blockprocval = vm_block_handler_escape(ec, block_handler);
	    VM_STACK_ENV_WRITE(ep, VM_ENV_DATA_INDEX_SPECVAL, blockprocval);
	}
    }

    if (!VM_FRAME_RUBYFRAME_P(cfp)) {
	local_size = VM_ENV_DATA_SIZE;
    }
    else {
	local_size = cfp->iseq->body->local_table_size + VM_ENV_DATA_SIZE;
    }

    /*
     * # local variables on a stack frame (N == local_size)
     * [lvar1, lvar2, ..., lvarN, SPECVAL]
     *                            ^
     *                            ep[0]
     *
     * # moved local variables
     * [lvar1, lvar2, ..., lvarN, SPECVAL, Envval, BlockProcval (if needed)]
     *  ^                         ^
     *  env->env[0]               ep[0]
     */

    env_size = local_size +
	       1 /* envval */;
    env_body = ALLOC_N(VALUE, env_size);
    MEMCPY(env_body, ep - (local_size - 1 /* specval */), VALUE, local_size);

#if 0
    for (i = 0; i < local_size; i++) {
	if (VM_FRAME_RUBYFRAME_P(cfp)) {
	    /* clear value stack for GC */
	    ep[-local_size + i] = 0;
	}
    }
#endif

    env_iseq = VM_FRAME_RUBYFRAME_P(cfp) ? cfp->iseq : NULL;
    env_ep = &env_body[local_size - 1 /* specval */];

    env = vm_env_new(env_ep, env_body, env_size, env_iseq);

    cfp->ep = env_ep;
    VM_ENV_FLAGS_SET(env_ep, VM_ENV_FLAG_ESCAPED | VM_ENV_FLAG_WB_REQUIRED);
    VM_STACK_ENV_WRITE(ep, 0, (VALUE)env);		/* GC mark */
    return (VALUE)env;
}

static VALUE
vm_make_env_object(const rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    VALUE envval = vm_make_env_each(ec, cfp);

    if (PROCDEBUG) {
	check_env_value((const rb_env_t *)envval);
    }

    return envval;
}

void
rb_vm_stack_to_heap(rb_execution_context_t *ec)
{
    rb_control_frame_t *cfp = ec->cfp;
    while ((cfp = rb_vm_get_binding_creatable_next_cfp(ec, cfp)) != 0) {
	vm_make_env_object(ec, cfp);
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
}

const rb_env_t *
rb_vm_env_prev_env(const rb_env_t *env)
{
    const VALUE *ep = env->ep;

    if (VM_ENV_LOCAL_P(ep)) {
	return NULL;
    }
    else {
        const VALUE *prev_ep = VM_ENV_PREV_EP(ep);
        return VM_ENV_ENVVAL_PTR(prev_ep);
    }
}

static int
collect_local_variables_in_iseq(const rb_iseq_t *iseq, const struct local_var_list *vars)
{
    unsigned int i;
    if (!iseq) return 0;
    for (i = 0; i < iseq->body->local_table_size; i++) {
	local_var_list_add(vars, iseq->body->local_table[i]);
    }
    return 1;
}

static void
collect_local_variables_in_env(const rb_env_t *env, const struct local_var_list *vars)
{
    do {
        if (VM_ENV_FLAGS(env->ep, VM_ENV_FLAG_ISOLATED)) break;
	collect_local_variables_in_iseq(env->iseq, vars);
    } while ((env = rb_vm_env_prev_env(env)) != NULL);
}

static int
vm_collect_local_variables_in_heap(const VALUE *ep, const struct local_var_list *vars)
{
    if (VM_ENV_ESCAPED_P(ep)) {
	collect_local_variables_in_env(VM_ENV_ENVVAL_PTR(ep), vars);
	return 1;
    }
    else {
	return 0;
    }
}

VALUE
rb_vm_env_local_variables(const rb_env_t *env)
{
    struct local_var_list vars;
    local_var_list_init(&vars);
    collect_local_variables_in_env(env, &vars);
    return local_var_list_finish(&vars);
}

VALUE
rb_iseq_local_variables(const rb_iseq_t *iseq)
{
    struct local_var_list vars;
    local_var_list_init(&vars);
    while (collect_local_variables_in_iseq(iseq, &vars)) {
	iseq = iseq->body->parent_iseq;
    }
    return local_var_list_finish(&vars);
}

/* Proc */

static VALUE
vm_proc_create_from_captured(VALUE klass,
			     const struct rb_captured_block *captured,
			     enum rb_block_type block_type,
			     int8_t is_from_method, int8_t is_lambda)
{
    VALUE procval = rb_proc_alloc(klass);
    rb_proc_t *proc = RTYPEDDATA_DATA(procval);

    VM_ASSERT(VM_EP_IN_HEAP_P(GET_EC(), captured->ep));

    /* copy block */
    RB_OBJ_WRITE(procval, &proc->block.as.captured.self, captured->self);
    RB_OBJ_WRITE(procval, &proc->block.as.captured.code.val, captured->code.val);
    rb_vm_block_ep_update(procval, &proc->block, captured->ep);

    vm_block_type_set(&proc->block, block_type);
    proc->is_from_method = is_from_method;
    proc->is_lambda = is_lambda;

    return procval;
}

void
rb_vm_block_copy(VALUE obj, const struct rb_block *dst, const struct rb_block *src)
{
    /* copy block */
    switch (vm_block_type(src)) {
      case block_type_iseq:
      case block_type_ifunc:
	RB_OBJ_WRITE(obj, &dst->as.captured.self, src->as.captured.self);
	RB_OBJ_WRITE(obj, &dst->as.captured.code.val, src->as.captured.code.val);
	rb_vm_block_ep_update(obj, dst, src->as.captured.ep);
	break;
      case block_type_symbol:
	RB_OBJ_WRITE(obj, &dst->as.symbol, src->as.symbol);
	break;
      case block_type_proc:
	RB_OBJ_WRITE(obj, &dst->as.proc, src->as.proc);
	break;
    }
}

static VALUE
proc_create(VALUE klass, const struct rb_block *block, int8_t is_from_method, int8_t is_lambda)
{
    VALUE procval = rb_proc_alloc(klass);
    rb_proc_t *proc = RTYPEDDATA_DATA(procval);

    VM_ASSERT(VM_EP_IN_HEAP_P(GET_EC(), vm_block_ep(block)));
    rb_vm_block_copy(procval, &proc->block, block);
    vm_block_type_set(&proc->block, block->type);
    proc->is_from_method = is_from_method;
    proc->is_lambda = is_lambda;

    return procval;
}

VALUE
rb_proc_dup(VALUE self)
{
    VALUE procval;
    rb_proc_t *src;

    GetProcPtr(self, src);
    procval = proc_create(rb_cProc, &src->block, src->is_from_method, src->is_lambda);
    if (RB_OBJ_SHAREABLE_P(self)) FL_SET_RAW(procval, RUBY_FL_SHAREABLE);
    RB_GC_GUARD(self); /* for: body = rb_proc_dup(body) */
    return procval;
}

struct collect_outer_variable_name_data {
    VALUE ary;
    VALUE read_only;
    bool yield;
    bool isolate;
};

static enum rb_id_table_iterator_result
collect_outer_variable_names(ID id, VALUE val, void *ptr)
{
    struct collect_outer_variable_name_data *data = (struct collect_outer_variable_name_data *)ptr;

    if (id == rb_intern("yield")) {
        data->yield = true;
    }
    else {
        if (data->isolate ||
            val == Qtrue /* write */) {
            if (data->ary == Qfalse) data->ary = rb_ary_new();
            rb_ary_push(data->ary, rb_id2str(id));
        }
        else {
            if (data->read_only == Qfalse) data->read_only = rb_ary_new();
            rb_ary_push(data->read_only, rb_id2str(id));
        }
    }
    return ID_TABLE_CONTINUE;
}

VALUE rb_ractor_error_class(void);

static const rb_env_t *
env_copy(const VALUE *src_ep, VALUE read_only_variables)
{
    const rb_env_t *src_env = (rb_env_t *)VM_ENV_ENVVAL(src_ep);
    VM_ASSERT(src_env->ep == src_ep);

    VALUE *env_body = ZALLOC_N(VALUE, src_env->env_size); // fill with Qfalse
    VALUE *ep = &env_body[src_env->env_size - 2];

    if (read_only_variables) {
        for (int i=0; i<RARRAY_LENINT(read_only_variables); i++) {
            ID id = SYM2ID(rb_str_intern(RARRAY_AREF(read_only_variables, i)));

            for (unsigned int j=0; j<src_env->iseq->body->local_table_size; j++) {
                if (id ==  src_env->iseq->body->local_table[j]) {
                    VALUE v = src_env->env[j];
                    if (!rb_ractor_shareable_p(v)) {
                        rb_raise(rb_ractor_error_class(),
                                 "can not make shareable Proc because it can refer unshareable object %"
                                 PRIsVALUE" from variable `%s'", rb_inspect(v), rb_id2name(id));
                    }
                    env_body[j] = v;
                    rb_ary_delete_at(read_only_variables, i);
                    break;
                }
            }
        }
    }

    ep[VM_ENV_DATA_INDEX_ME_CREF] = src_ep[VM_ENV_DATA_INDEX_ME_CREF];
    ep[VM_ENV_DATA_INDEX_FLAGS]   = src_ep[VM_ENV_DATA_INDEX_FLAGS] | VM_ENV_FLAG_ISOLATED;

    if (!VM_ENV_LOCAL_P(src_ep)) {
        const VALUE *prev_ep = VM_ENV_PREV_EP(src_env->ep);
        const rb_env_t *new_prev_env = env_copy(prev_ep, read_only_variables);
        ep[VM_ENV_DATA_INDEX_SPECVAL] = VM_GUARDED_PREV_EP(new_prev_env->ep);
    }
    else {
        ep[VM_ENV_DATA_INDEX_SPECVAL] = VM_BLOCK_HANDLER_NONE;
    }

    return vm_env_new(ep, env_body, src_env->env_size, src_env->iseq);
}

static void
proc_isolate_env(VALUE self, rb_proc_t *proc, VALUE read_only_variables)
{
    const struct rb_captured_block *captured = &proc->block.as.captured;
    const rb_env_t *env = env_copy(captured->ep, read_only_variables);
    *((const VALUE **)&proc->block.as.captured.ep) = env->ep;
    RB_OBJ_WRITTEN(self, Qundef, env);
}

VALUE
rb_proc_isolate_bang(VALUE self)
{
    const rb_iseq_t *iseq = vm_proc_iseq(self);

    if (iseq) {
        rb_proc_t *proc = (rb_proc_t *)RTYPEDDATA_DATA(self);
        if (proc->block.type != block_type_iseq) rb_raise(rb_eRuntimeError, "not supported yet");

        if (iseq->body->outer_variables) {
            struct collect_outer_variable_name_data data = {
                .isolate = true,
                .ary = Qfalse,
                .yield = false,
            };
            rb_id_table_foreach(iseq->body->outer_variables, collect_outer_variable_names, (void *)&data);

            if (data.ary != Qfalse) {
                VALUE str = rb_ary_join(data.ary, rb_str_new2(", "));
                if (data.yield) {
                    rb_raise(rb_eArgError, "can not isolate a Proc because it accesses outer variables (%s) and uses `yield'.",
                             StringValueCStr(str));
                }
                else {
                    rb_raise(rb_eArgError, "can not isolate a Proc because it accesses outer variables (%s).",
                             StringValueCStr(str));
                }
            }
            else {
                VM_ASSERT(data.yield);
                rb_raise(rb_eArgError, "can not isolate a Proc because it uses `yield'.");
            }
        }

        proc_isolate_env(self, proc, Qfalse);
        proc->is_isolated = TRUE;
    }

    FL_SET_RAW(self, RUBY_FL_SHAREABLE);
    return self;
}

VALUE
rb_proc_isolate(VALUE self)
{
    VALUE dst = rb_proc_dup(self);
    rb_proc_isolate_bang(dst);
    return dst;
}

VALUE
rb_proc_ractor_make_shareable(VALUE self)
{
    const rb_iseq_t *iseq = vm_proc_iseq(self);

    if (iseq) {
        rb_proc_t *proc = (rb_proc_t *)RTYPEDDATA_DATA(self);
        if (proc->block.type != block_type_iseq) rb_raise(rb_eRuntimeError, "not supported yet");

        VALUE read_only_variables = Qfalse;

        if (iseq->body->outer_variables) {
            struct collect_outer_variable_name_data data = {
                .isolate = false,
                .ary = Qfalse,
                .read_only = Qfalse,
                .yield = false,
            };

            rb_id_table_foreach(iseq->body->outer_variables, collect_outer_variable_names, (void *)&data);

            if (data.ary != Qfalse) {
                VALUE str = rb_ary_join(data.ary, rb_str_new2(", "));
                if (data.yield) {
                    rb_raise(rb_eArgError, "can not make a Proc shareable because it accesses outer variables (%s) and uses `yield'.",
                             StringValueCStr(str));
                }
                else {
                    rb_raise(rb_eArgError, "can not make a Proc shareable because it accesses outer variables (%s).",
                             StringValueCStr(str));
                }
            }
            else if (data.yield) {
                rb_raise(rb_eArgError, "can not make a Proc shareable because it uses `yield'.");
            }

            read_only_variables = data.read_only;
        }

        proc_isolate_env(self, proc, read_only_variables);
        proc->is_isolated = TRUE;
    }

    FL_SET_RAW(self, RUBY_FL_SHAREABLE);
    return self;
}

MJIT_FUNC_EXPORTED VALUE
rb_vm_make_proc_lambda(const rb_execution_context_t *ec, const struct rb_captured_block *captured, VALUE klass, int8_t is_lambda)
{
    VALUE procval;

    if (!VM_ENV_ESCAPED_P(captured->ep)) {
	rb_control_frame_t *cfp = VM_CAPTURED_BLOCK_TO_CFP(captured);
	vm_make_env_object(ec, cfp);
    }
    VM_ASSERT(VM_EP_IN_HEAP_P(ec, captured->ep));
    VM_ASSERT(imemo_type_p(captured->code.val, imemo_iseq) ||
	      imemo_type_p(captured->code.val, imemo_ifunc));

    procval = vm_proc_create_from_captured(klass, captured,
					   imemo_type(captured->code.val) == imemo_iseq ? block_type_iseq : block_type_ifunc, FALSE, is_lambda);
    return procval;
}

/* Binding */

VALUE
rb_vm_make_binding(const rb_execution_context_t *ec, const rb_control_frame_t *src_cfp)
{
    rb_control_frame_t *cfp = rb_vm_get_binding_creatable_next_cfp(ec, src_cfp);
    rb_control_frame_t *ruby_level_cfp = rb_vm_get_ruby_level_next_cfp(ec, src_cfp);
    VALUE bindval, envval;
    rb_binding_t *bind;

    if (cfp == 0 || ruby_level_cfp == 0) {
	rb_raise(rb_eRuntimeError, "Can't create Binding Object on top of Fiber.");
    }

    while (1) {
	envval = vm_make_env_object(ec, cfp);
	if (cfp == ruby_level_cfp) {
	    break;
	}
	cfp = rb_vm_get_binding_creatable_next_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
    }

    bindval = rb_binding_alloc(rb_cBinding);
    GetBindingPtr(bindval, bind);
    vm_bind_update_env(bindval, bind, envval);
    RB_OBJ_WRITE(bindval, &bind->block.as.captured.self, cfp->self);
    RB_OBJ_WRITE(bindval, &bind->block.as.captured.code.iseq, cfp->iseq);
    RB_OBJ_WRITE(bindval, &bind->pathobj, ruby_level_cfp->iseq->body->location.pathobj);
    bind->first_lineno = rb_vm_get_sourceline(ruby_level_cfp);

    return bindval;
}

const VALUE *
rb_binding_add_dynavars(VALUE bindval, rb_binding_t *bind, int dyncount, const ID *dynvars)
{
    VALUE envval, pathobj = bind->pathobj;
    VALUE path = pathobj_path(pathobj);
    VALUE realpath = pathobj_realpath(pathobj);
    const struct rb_block *base_block;
    const rb_env_t *env;
    rb_execution_context_t *ec = GET_EC();
    const rb_iseq_t *base_iseq, *iseq;
    rb_ast_body_t ast;
    NODE tmp_node;
    ID minibuf[4], *dyns = minibuf;
    VALUE idtmp = 0;

    if (dyncount < 0) return 0;

    base_block = &bind->block;
    base_iseq = vm_block_iseq(base_block);

    if (dyncount >= numberof(minibuf)) dyns = ALLOCV_N(ID, idtmp, dyncount + 1);

    dyns[0] = dyncount;
    MEMCPY(dyns + 1, dynvars, ID, dyncount);
    rb_node_init(&tmp_node, NODE_SCOPE, (VALUE)dyns, 0, 0);
    ast.root = &tmp_node;
    ast.compile_option = 0;
    ast.line_count = -1;

    if (base_iseq) {
	iseq = rb_iseq_new(&ast, base_iseq->body->location.label, path, realpath, base_iseq, ISEQ_TYPE_EVAL);
    }
    else {
	VALUE tempstr = rb_fstring_lit("<temp>");
	iseq = rb_iseq_new_top(&ast, tempstr, tempstr, tempstr, NULL);
    }
    tmp_node.nd_tbl = 0; /* reset table */
    ALLOCV_END(idtmp);

    vm_set_eval_stack(ec, iseq, 0, base_block);
    vm_bind_update_env(bindval, bind, envval = vm_make_env_object(ec, ec->cfp));
    rb_vm_pop_frame(ec);

    env = (const rb_env_t *)envval;
    return env->env;
}

/* C -> Ruby: block */

static inline VALUE
invoke_block(rb_execution_context_t *ec, const rb_iseq_t *iseq, VALUE self, const struct rb_captured_block *captured, const rb_cref_t *cref, VALUE type, int opt_pc)
{
    int arg_size = iseq->body->param.size;

    vm_push_frame(ec, iseq, type | VM_FRAME_FLAG_FINISH, self,
		  VM_GUARDED_PREV_EP(captured->ep),
		  (VALUE)cref, /* cref or method */
		  iseq->body->iseq_encoded + opt_pc,
		  ec->cfp->sp + arg_size,
		  iseq->body->local_table_size - arg_size,
		  iseq->body->stack_max);
    return vm_exec(ec, TRUE);
}

static VALUE
invoke_bmethod(rb_execution_context_t *ec, const rb_iseq_t *iseq, VALUE self, const struct rb_captured_block *captured, const rb_callable_method_entry_t *me, VALUE type, int opt_pc)
{
    /* bmethod */
    int arg_size = iseq->body->param.size;
    VALUE ret;
    rb_hook_list_t *hooks;

    VM_ASSERT(me->def->type == VM_METHOD_TYPE_BMETHOD);

    vm_push_frame(ec, iseq, type | VM_FRAME_FLAG_BMETHOD, self,
		  VM_GUARDED_PREV_EP(captured->ep),
		  (VALUE)me,
		  iseq->body->iseq_encoded + opt_pc,
		  ec->cfp->sp + arg_size,
		  iseq->body->local_table_size - arg_size,
		  iseq->body->stack_max);

    RUBY_DTRACE_METHOD_ENTRY_HOOK(ec, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_CALL, self, me->def->original_id, me->called_id, me->owner, Qnil);

    if (UNLIKELY((hooks = me->def->body.bmethod.hooks) != NULL) &&
        hooks->events & RUBY_EVENT_CALL) {
        rb_exec_event_hook_orig(ec, hooks, RUBY_EVENT_CALL, self,
                                me->def->original_id, me->called_id, me->owner, Qnil, FALSE);
    }
    VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH);
    ret = vm_exec(ec, TRUE);

    EXEC_EVENT_HOOK(ec, RUBY_EVENT_RETURN, self, me->def->original_id, me->called_id, me->owner, ret);
    if ((hooks = me->def->body.bmethod.hooks) != NULL &&
        hooks->events & RUBY_EVENT_RETURN) {
        rb_exec_event_hook_orig(ec, hooks, RUBY_EVENT_RETURN, self,
                                me->def->original_id, me->called_id, me->owner, ret, FALSE);
    }
    RUBY_DTRACE_METHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);
    return ret;
}

ALWAYS_INLINE(static VALUE
              invoke_iseq_block_from_c(rb_execution_context_t *ec, const struct rb_captured_block *captured,
                                       VALUE self, int argc, const VALUE *argv, int kw_splat, VALUE passed_block_handler,
                                       const rb_cref_t *cref, int is_lambda, const rb_callable_method_entry_t *me));

static inline VALUE
invoke_iseq_block_from_c(rb_execution_context_t *ec, const struct rb_captured_block *captured,
			 VALUE self, int argc, const VALUE *argv, int kw_splat, VALUE passed_block_handler,
                         const rb_cref_t *cref, int is_lambda, const rb_callable_method_entry_t *me)
{
    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
    int i, opt_pc;
    VALUE type = VM_FRAME_MAGIC_BLOCK | (is_lambda ? VM_FRAME_FLAG_LAMBDA : 0);
    rb_control_frame_t *cfp = ec->cfp;
    VALUE *sp = cfp->sp;

    stack_check(ec);

    CHECK_VM_STACK_OVERFLOW(cfp, argc);
    vm_check_canary(ec, sp);
    cfp->sp = sp + argc;
    for (i=0; i<argc; i++) {
	sp[i] = argv[i];
    }

    opt_pc = vm_yield_setup_args(ec, iseq, argc, sp, kw_splat, passed_block_handler,
				 (is_lambda ? arg_setup_method : arg_setup_block));
    cfp->sp = sp;

    if (me == NULL) {
	return invoke_block(ec, iseq, self, captured, cref, type, opt_pc);
    }
    else {
	return invoke_bmethod(ec, iseq, self, captured, me, type, opt_pc);
    }
}

static inline VALUE
invoke_block_from_c_bh(rb_execution_context_t *ec, VALUE block_handler,
		       int argc, const VALUE *argv,
		       int kw_splat, VALUE passed_block_handler, const rb_cref_t *cref,
		       int is_lambda, int force_blockarg)
{
  again:
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_iseq:
	{
	    const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
	    return invoke_iseq_block_from_c(ec, captured, captured->self,
					    argc, argv, kw_splat, passed_block_handler,
                                            cref, is_lambda, NULL);
	}
      case block_handler_type_ifunc:
	return vm_yield_with_cfunc(ec, VM_BH_TO_IFUNC_BLOCK(block_handler),
				   VM_BH_TO_IFUNC_BLOCK(block_handler)->self,
                                   argc, argv, kw_splat, passed_block_handler, NULL);
      case block_handler_type_symbol:
	return vm_yield_with_symbol(ec, VM_BH_TO_SYMBOL(block_handler),
				    argc, argv, kw_splat, passed_block_handler);
      case block_handler_type_proc:
	if (force_blockarg == FALSE) {
	    is_lambda = block_proc_is_lambda(VM_BH_TO_PROC(block_handler));
	}
	block_handler = vm_proc_to_block_handler(VM_BH_TO_PROC(block_handler));
	goto again;
    }
    VM_UNREACHABLE(invoke_block_from_c_splattable);
    return Qundef;
}

static inline VALUE
check_block_handler(rb_execution_context_t *ec)
{
    VALUE block_handler = VM_CF_BLOCK_HANDLER(ec->cfp);
    vm_block_handler_verify(block_handler);
    if (UNLIKELY(block_handler == VM_BLOCK_HANDLER_NONE)) {
	rb_vm_localjump_error("no block given", Qnil, 0);
    }

    return block_handler;
}

static VALUE
vm_yield_with_cref(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat, const rb_cref_t *cref, int is_lambda)
{
    return invoke_block_from_c_bh(ec, check_block_handler(ec),
                                  argc, argv, kw_splat, VM_BLOCK_HANDLER_NONE,
				  cref, is_lambda, FALSE);
}

static VALUE
vm_yield(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat)
{
    return invoke_block_from_c_bh(ec, check_block_handler(ec),
                                  argc, argv, kw_splat, VM_BLOCK_HANDLER_NONE,
				  NULL, FALSE, FALSE);
}

static VALUE
vm_yield_with_block(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE block_handler, int kw_splat)
{
    return invoke_block_from_c_bh(ec, check_block_handler(ec),
                                  argc, argv, kw_splat, block_handler,
				  NULL, FALSE, FALSE);
}

static VALUE
vm_yield_force_blockarg(rb_execution_context_t *ec, VALUE args)
{
    return invoke_block_from_c_bh(ec, check_block_handler(ec), 1, &args,
                                  RB_NO_KEYWORDS, VM_BLOCK_HANDLER_NONE, NULL, FALSE, TRUE);
}

ALWAYS_INLINE(static VALUE
              invoke_block_from_c_proc(rb_execution_context_t *ec, const rb_proc_t *proc,
                                       VALUE self, int argc, const VALUE *argv,
                                       int kw_splat, VALUE passed_block_handler, int is_lambda,
                                       const rb_callable_method_entry_t *me));

static inline VALUE
invoke_block_from_c_proc(rb_execution_context_t *ec, const rb_proc_t *proc,
			 VALUE self, int argc, const VALUE *argv,
                         int kw_splat, VALUE passed_block_handler, int is_lambda,
                         const rb_callable_method_entry_t *me)
{
    const struct rb_block *block = &proc->block;

  again:
    switch (vm_block_type(block)) {
      case block_type_iseq:
        return invoke_iseq_block_from_c(ec, &block->as.captured, self, argc, argv, kw_splat, passed_block_handler, NULL, is_lambda, me);
      case block_type_ifunc:
        if (kw_splat == 1) {
            VALUE keyword_hash = argv[argc-1];
            if (!RB_TYPE_P(keyword_hash, T_HASH)) {
                keyword_hash = rb_to_hash_type(keyword_hash);
            }
            if (RHASH_EMPTY_P(keyword_hash)) {
                argc--;
            } else {
                ((VALUE *)argv)[argc-1] = rb_hash_dup(keyword_hash);
            }
        }
        return vm_yield_with_cfunc(ec, &block->as.captured, self, argc, argv, kw_splat, passed_block_handler, me);
      case block_type_symbol:
	return vm_yield_with_symbol(ec, block->as.symbol, argc, argv, kw_splat, passed_block_handler);
      case block_type_proc:
	is_lambda = block_proc_is_lambda(block->as.proc);
	block = vm_proc_block(block->as.proc);
	goto again;
    }
    VM_UNREACHABLE(invoke_block_from_c_proc);
    return Qundef;
}

static VALUE
vm_invoke_proc(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self,
	       int argc, const VALUE *argv, int kw_splat, VALUE passed_block_handler)
{
    return invoke_block_from_c_proc(ec, proc, self, argc, argv, kw_splat, passed_block_handler, proc->is_lambda, NULL);
}

MJIT_FUNC_EXPORTED VALUE
rb_vm_invoke_bmethod(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self,
                     int argc, const VALUE *argv, int kw_splat, VALUE block_handler, const rb_callable_method_entry_t *me)
{
    return invoke_block_from_c_proc(ec, proc, self, argc, argv, kw_splat, block_handler, TRUE, me);
}

MJIT_FUNC_EXPORTED VALUE
rb_vm_invoke_proc(rb_execution_context_t *ec, rb_proc_t *proc,
		  int argc, const VALUE *argv, int kw_splat, VALUE passed_block_handler)
{
    VALUE self = vm_block_self(&proc->block);
    vm_block_handler_verify(passed_block_handler);

    if (proc->is_from_method) {
        return rb_vm_invoke_bmethod(ec, proc, self, argc, argv, kw_splat, passed_block_handler, NULL);
    }
    else {
	return vm_invoke_proc(ec, proc, self, argc, argv, kw_splat, passed_block_handler);
    }
}

VALUE
rb_vm_invoke_proc_with_self(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self,
                            int argc, const VALUE *argv, int kw_splat, VALUE passed_block_handler)
{
    vm_block_handler_verify(passed_block_handler);

    if (proc->is_from_method) {
        return rb_vm_invoke_bmethod(ec, proc, self, argc, argv, kw_splat, passed_block_handler, NULL);
    }
    else {
	return vm_invoke_proc(ec, proc, self, argc, argv, kw_splat, passed_block_handler);
    }
}

/* special variable */

static rb_control_frame_t *
vm_normal_frame(const rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    while (cfp->pc == 0) {
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
	    return 0;
	}
    }
    return cfp;
}

static VALUE
vm_cfp_svar_get(const rb_execution_context_t *ec, rb_control_frame_t *cfp, VALUE key)
{
    cfp = vm_normal_frame(ec, cfp);
    return lep_svar_get(ec, cfp ? VM_CF_LEP(cfp) : 0, key);
}

static void
vm_cfp_svar_set(const rb_execution_context_t *ec, rb_control_frame_t *cfp, VALUE key, const VALUE val)
{
    cfp = vm_normal_frame(ec, cfp);
    lep_svar_set(ec, cfp ? VM_CF_LEP(cfp) : 0, key, val);
}

static VALUE
vm_svar_get(const rb_execution_context_t *ec, VALUE key)
{
    return vm_cfp_svar_get(ec, ec->cfp, key);
}

static void
vm_svar_set(const rb_execution_context_t *ec, VALUE key, VALUE val)
{
    vm_cfp_svar_set(ec, ec->cfp, key, val);
}

VALUE
rb_backref_get(void)
{
    return vm_svar_get(GET_EC(), VM_SVAR_BACKREF);
}

void
rb_backref_set(VALUE val)
{
    vm_svar_set(GET_EC(), VM_SVAR_BACKREF, val);
}

VALUE
rb_lastline_get(void)
{
    return vm_svar_get(GET_EC(), VM_SVAR_LASTLINE);
}

void
rb_lastline_set(VALUE val)
{
    vm_svar_set(GET_EC(), VM_SVAR_LASTLINE, val);
}

/* misc */

/* in intern.h */
const char *
rb_sourcefile(void)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (cfp) {
	return RSTRING_PTR(rb_iseq_path(cfp->iseq));
    }
    else {
	return 0;
    }
}

/* in intern.h */
int
rb_sourceline(void)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (cfp) {
	return rb_vm_get_sourceline(cfp);
    }
    else {
	return 0;
    }
}

VALUE
rb_source_location(int *pline)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (cfp && VM_FRAME_RUBYFRAME_P(cfp)) {
	if (pline) *pline = rb_vm_get_sourceline(cfp);
	return rb_iseq_path(cfp->iseq);
    }
    else {
	if (pline) *pline = 0;
	return Qnil;
    }
}

MJIT_FUNC_EXPORTED const char *
rb_source_location_cstr(int *pline)
{
    VALUE path = rb_source_location(pline);
    if (NIL_P(path)) return NULL;
    return RSTRING_PTR(path);
}

rb_cref_t *
rb_vm_cref(void)
{
    const rb_execution_context_t *ec = GET_EC();
    return vm_ec_cref(ec);
}

rb_cref_t *
rb_vm_cref_replace_with_duplicated_cref(void)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    rb_cref_t *cref = vm_cref_replace_with_duplicated_cref(cfp->ep);
    return cref;
}

const rb_cref_t *
rb_vm_cref_in_context(VALUE self, VALUE cbase)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    const rb_cref_t *cref;
    if (!cfp || cfp->self != self) return NULL;
    if (!vm_env_cref_by_cref(cfp->ep)) return NULL;
    cref = vm_get_cref(cfp->ep);
    if (CREF_CLASS(cref) != cbase) return NULL;
    return cref;
}

#if 0
void
debug_cref(rb_cref_t *cref)
{
    while (cref) {
	dp(CREF_CLASS(cref));
	printf("%ld\n", CREF_VISI(cref));
	cref = CREF_NEXT(cref);
    }
}
#endif

VALUE
rb_vm_cbase(void)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (cfp == 0) {
	rb_raise(rb_eRuntimeError, "Can't call on top of Fiber or Thread");
    }
    return vm_get_cbase(cfp->ep);
}

/* jump */

static VALUE
make_localjump_error(const char *mesg, VALUE value, int reason)
{
    extern VALUE rb_eLocalJumpError;
    VALUE exc = rb_exc_new2(rb_eLocalJumpError, mesg);
    ID id;

    switch (reason) {
      case TAG_BREAK:
	CONST_ID(id, "break");
	break;
      case TAG_REDO:
	CONST_ID(id, "redo");
	break;
      case TAG_RETRY:
	CONST_ID(id, "retry");
	break;
      case TAG_NEXT:
	CONST_ID(id, "next");
	break;
      case TAG_RETURN:
	CONST_ID(id, "return");
	break;
      default:
	CONST_ID(id, "noreason");
	break;
    }
    rb_iv_set(exc, "@exit_value", value);
    rb_iv_set(exc, "@reason", ID2SYM(id));
    return exc;
}

MJIT_FUNC_EXPORTED void
rb_vm_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc = make_localjump_error(mesg, value, reason);
    rb_exc_raise(exc);
}

VALUE
rb_vm_make_jump_tag_but_local_jump(int state, VALUE val)
{
    const char *mesg;

    switch (state) {
      case TAG_RETURN:
	mesg = "unexpected return";
	break;
      case TAG_BREAK:
	mesg = "unexpected break";
	break;
      case TAG_NEXT:
	mesg = "unexpected next";
	break;
      case TAG_REDO:
	mesg = "unexpected redo";
	val = Qnil;
	break;
      case TAG_RETRY:
	mesg = "retry outside of rescue clause";
	val = Qnil;
	break;
      default:
	return Qnil;
    }
    if (val == Qundef) {
	val = GET_EC()->tag->retval;
    }
    return make_localjump_error(mesg, val, state);
}

void
rb_vm_jump_tag_but_local_jump(int state)
{
    VALUE exc = rb_vm_make_jump_tag_but_local_jump(state, Qundef);
    if (!NIL_P(exc)) rb_exc_raise(exc);
    EC_JUMP_TAG(GET_EC(), state);
}

static rb_control_frame_t *
next_not_local_frame(rb_control_frame_t *cfp)
{
    while (VM_ENV_LOCAL_P(cfp->ep)) {
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return cfp;
}

NORETURN(static void vm_iter_break(rb_execution_context_t *ec, VALUE val));

static void
vm_iter_break(rb_execution_context_t *ec, VALUE val)
{
    rb_control_frame_t *cfp = next_not_local_frame(ec->cfp);
    const VALUE *ep = VM_CF_PREV_EP(cfp);
    const rb_control_frame_t *target_cfp = rb_vm_search_cf_from_ep(ec, cfp, ep);

#if 0				/* raise LocalJumpError */
    if (!target_cfp) {
	rb_vm_localjump_error("unexpected break", val, TAG_BREAK);
    }
#endif

    ec->errinfo = (VALUE)THROW_DATA_NEW(val, target_cfp, TAG_BREAK);
    EC_JUMP_TAG(ec, TAG_BREAK);
}

void
rb_iter_break(void)
{
    vm_iter_break(GET_EC(), Qnil);
}

void
rb_iter_break_value(VALUE val)
{
    vm_iter_break(GET_EC(), val);
}

/* optimization: redefine management */

static st_table *vm_opt_method_table = 0;
static st_table *vm_opt_mid_table = 0;

static int
vm_redefinition_check_flag(VALUE klass)
{
    if (klass == rb_cInteger) return INTEGER_REDEFINED_OP_FLAG;
    if (klass == rb_cFloat)  return FLOAT_REDEFINED_OP_FLAG;
    if (klass == rb_cString) return STRING_REDEFINED_OP_FLAG;
    if (klass == rb_cArray)  return ARRAY_REDEFINED_OP_FLAG;
    if (klass == rb_cHash)   return HASH_REDEFINED_OP_FLAG;
    if (klass == rb_cSymbol) return SYMBOL_REDEFINED_OP_FLAG;
    if (klass == rb_cTime)   return TIME_REDEFINED_OP_FLAG;
    if (klass == rb_cRegexp) return REGEXP_REDEFINED_OP_FLAG;
    if (klass == rb_cNilClass) return NIL_REDEFINED_OP_FLAG;
    if (klass == rb_cTrueClass) return TRUE_REDEFINED_OP_FLAG;
    if (klass == rb_cFalseClass) return FALSE_REDEFINED_OP_FLAG;
    if (klass == rb_cProc) return PROC_REDEFINED_OP_FLAG;
    return 0;
}

int
rb_vm_check_optimizable_mid(VALUE mid)
{
    if (!vm_opt_mid_table) {
      return FALSE;
    }

    return st_lookup(vm_opt_mid_table, mid, NULL);
}

static int
vm_redefinition_check_method_type(const rb_method_definition_t *def)
{
    switch (def->type) {
      case VM_METHOD_TYPE_CFUNC:
      case VM_METHOD_TYPE_OPTIMIZED:
	return TRUE;
      default:
	return FALSE;
    }
}

static void
rb_vm_check_redefinition_opt_method(const rb_method_entry_t *me, VALUE klass)
{
    st_data_t bop;
    if (RB_TYPE_P(klass, T_ICLASS) && FL_TEST(klass, RICLASS_IS_ORIGIN) &&
            RB_TYPE_P(RBASIC_CLASS(klass), T_CLASS)) {
       klass = RBASIC_CLASS(klass);
    }
    if (vm_redefinition_check_method_type(me->def)) {
	if (st_lookup(vm_opt_method_table, (st_data_t)me, &bop)) {
	    int flag = vm_redefinition_check_flag(klass);

	    ruby_vm_redefined_flag[bop] |= flag;
	}
    }
}

static enum rb_id_table_iterator_result
check_redefined_method(ID mid, VALUE value, void *data)
{
    VALUE klass = (VALUE)data;
    const rb_method_entry_t *me = (rb_method_entry_t *)value;
    const rb_method_entry_t *newme = rb_method_entry(klass, mid);

    if (newme != me) rb_vm_check_redefinition_opt_method(me, me->owner);

    return ID_TABLE_CONTINUE;
}

void
rb_vm_check_redefinition_by_prepend(VALUE klass)
{
    if (!vm_redefinition_check_flag(klass)) return;
    rb_id_table_foreach(RCLASS_M_TBL(RCLASS_ORIGIN(klass)), check_redefined_method, (void *)klass);
}

static void
add_opt_method(VALUE klass, ID mid, VALUE bop)
{
    const rb_method_entry_t *me = rb_method_entry_at(klass, mid);

    if (me && vm_redefinition_check_method_type(me->def)) {
	st_insert(vm_opt_method_table, (st_data_t)me, (st_data_t)bop);
	st_insert(vm_opt_mid_table, (st_data_t)mid, (st_data_t)Qtrue);
    }
    else {
	rb_bug("undefined optimized method: %s", rb_id2name(mid));
    }
}

static void
vm_init_redefined_flag(void)
{
    ID mid;
    VALUE bop;

    vm_opt_method_table = st_init_numtable();
    vm_opt_mid_table = st_init_numtable();

#define OP(mid_, bop_) (mid = id##mid_, bop = BOP_##bop_, ruby_vm_redefined_flag[bop] = 0)
#define C(k) add_opt_method(rb_c##k, mid, bop)
    OP(PLUS, PLUS), (C(Integer), C(Float), C(String), C(Array));
    OP(MINUS, MINUS), (C(Integer), C(Float));
    OP(MULT, MULT), (C(Integer), C(Float));
    OP(DIV, DIV), (C(Integer), C(Float));
    OP(MOD, MOD), (C(Integer), C(Float));
    OP(Eq, EQ), (C(Integer), C(Float), C(String), C(Symbol));
    OP(Eqq, EQQ), (C(Integer), C(Float), C(Symbol), C(String),
		   C(NilClass), C(TrueClass), C(FalseClass));
    OP(LT, LT), (C(Integer), C(Float));
    OP(LE, LE), (C(Integer), C(Float));
    OP(GT, GT), (C(Integer), C(Float));
    OP(GE, GE), (C(Integer), C(Float));
    OP(LTLT, LTLT), (C(String), C(Array));
    OP(AREF, AREF), (C(Array), C(Hash), C(Integer));
    OP(ASET, ASET), (C(Array), C(Hash));
    OP(Length, LENGTH), (C(Array), C(String), C(Hash));
    OP(Size, SIZE), (C(Array), C(String), C(Hash));
    OP(EmptyP, EMPTY_P), (C(Array), C(String), C(Hash));
    OP(Succ, SUCC), (C(Integer), C(String), C(Time));
    OP(EqTilde, MATCH), (C(Regexp), C(String));
    OP(Freeze, FREEZE), (C(String));
    OP(UMinus, UMINUS), (C(String));
    OP(Max, MAX), (C(Array));
    OP(Min, MIN), (C(Array));
    OP(Call, CALL), (C(Proc));
    OP(And, AND), (C(Integer));
    OP(Or, OR), (C(Integer));
    OP(NilP, NIL_P), (C(NilClass));
#undef C
#undef OP
}

/* for vm development */

#if VMDEBUG
static const char *
vm_frametype_name(const rb_control_frame_t *cfp)
{
    switch (VM_FRAME_TYPE(cfp)) {
      case VM_FRAME_MAGIC_METHOD: return "method";
      case VM_FRAME_MAGIC_BLOCK:  return "block";
      case VM_FRAME_MAGIC_CLASS:  return "class";
      case VM_FRAME_MAGIC_TOP:    return "top";
      case VM_FRAME_MAGIC_CFUNC:  return "cfunc";
      case VM_FRAME_MAGIC_IFUNC:  return "ifunc";
      case VM_FRAME_MAGIC_EVAL:   return "eval";
      case VM_FRAME_MAGIC_RESCUE: return "rescue";
      default:
	rb_bug("unknown frame");
    }
}
#endif

static VALUE
frame_return_value(const struct vm_throw_data *err)
{
    if (THROW_DATA_P(err) &&
	THROW_DATA_STATE(err) == TAG_BREAK &&
	THROW_DATA_CONSUMED_P(err) == FALSE) {
	return THROW_DATA_VAL(err);
    }
    else {
	return Qnil;
    }
}

#if 0
/* for debug */
static const char *
frame_name(const rb_control_frame_t *cfp)
{
    unsigned long type = VM_FRAME_TYPE(cfp);
#define C(t) if (type == VM_FRAME_MAGIC_##t) return #t
    C(METHOD);
    C(BLOCK);
    C(CLASS);
    C(TOP);
    C(CFUNC);
    C(PROC);
    C(IFUNC);
    C(EVAL);
    C(LAMBDA);
    C(RESCUE);
    C(DUMMY);
#undef C
    return "unknown";
}
#endif

static void
hook_before_rewind(rb_execution_context_t *ec, const rb_control_frame_t *cfp,
                   int will_finish_vm_exec, int state, struct vm_throw_data *err)
{
    if (state == TAG_RAISE && RBASIC(err)->klass == rb_eSysStackError) {
	return;
    }
    else {
        const rb_iseq_t *iseq = cfp->iseq;
        rb_hook_list_t *local_hooks = iseq->aux.exec.local_hooks;

        switch (VM_FRAME_TYPE(ec->cfp)) {
          case VM_FRAME_MAGIC_METHOD:
            RUBY_DTRACE_METHOD_RETURN_HOOK(ec, 0, 0);
            EXEC_EVENT_HOOK_AND_POP_FRAME(ec, RUBY_EVENT_RETURN, ec->cfp->self, 0, 0, 0, frame_return_value(err));

            if (UNLIKELY(local_hooks && local_hooks->events & RUBY_EVENT_RETURN)) {
                rb_exec_event_hook_orig(ec, local_hooks, RUBY_EVENT_RETURN,
                                        ec->cfp->self, 0, 0, 0, frame_return_value(err), TRUE);
            }

            THROW_DATA_CONSUMED_SET(err);
            break;
          case VM_FRAME_MAGIC_BLOCK:
            if (VM_FRAME_BMETHOD_P(ec->cfp)) {
                EXEC_EVENT_HOOK(ec, RUBY_EVENT_B_RETURN, ec->cfp->self, 0, 0, 0, frame_return_value(err));
                if (UNLIKELY(local_hooks && local_hooks->events & RUBY_EVENT_B_RETURN)) {
                    rb_exec_event_hook_orig(ec, local_hooks, RUBY_EVENT_B_RETURN,
                                            ec->cfp->self, 0, 0, 0, frame_return_value(err), FALSE);
                }

                if (!will_finish_vm_exec) {
                    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(ec->cfp);

                    /* kick RUBY_EVENT_RETURN at invoke_block_from_c() for bmethod */
                    EXEC_EVENT_HOOK_AND_POP_FRAME(ec, RUBY_EVENT_RETURN, ec->cfp->self,
                                                  rb_vm_frame_method_entry(ec->cfp)->def->original_id,
                                                  rb_vm_frame_method_entry(ec->cfp)->called_id,
                                                  rb_vm_frame_method_entry(ec->cfp)->owner,
                                                  frame_return_value(err));

                    VM_ASSERT(me->def->type == VM_METHOD_TYPE_BMETHOD);
                    local_hooks = me->def->body.bmethod.hooks;

                    if (UNLIKELY(local_hooks && local_hooks->events & RUBY_EVENT_RETURN)) {
                        rb_exec_event_hook_orig(ec, local_hooks, RUBY_EVENT_RETURN, ec->cfp->self,
                                                rb_vm_frame_method_entry(ec->cfp)->def->original_id,
                                                rb_vm_frame_method_entry(ec->cfp)->called_id,
                                                rb_vm_frame_method_entry(ec->cfp)->owner,
                                                frame_return_value(err), TRUE);
                    }
                }
                THROW_DATA_CONSUMED_SET(err);
            }
            else {
                EXEC_EVENT_HOOK_AND_POP_FRAME(ec, RUBY_EVENT_B_RETURN, ec->cfp->self, 0, 0, 0, frame_return_value(err));
                if (UNLIKELY(local_hooks && local_hooks->events & RUBY_EVENT_B_RETURN)) {
                    rb_exec_event_hook_orig(ec, local_hooks, RUBY_EVENT_B_RETURN,
                                            ec->cfp->self, 0, 0, 0, frame_return_value(err), TRUE);
                }
                THROW_DATA_CONSUMED_SET(err);
            }
            break;
          case VM_FRAME_MAGIC_CLASS:
            EXEC_EVENT_HOOK_AND_POP_FRAME(ec, RUBY_EVENT_END, ec->cfp->self, 0, 0, 0, Qnil);
            break;
        }
    }
}

/* evaluator body */

/*                  finish
  VMe (h1)          finish
    VM              finish F1 F2
      cfunc         finish F1 F2 C1
        rb_funcall  finish F1 F2 C1
          VMe       finish F1 F2 C1
            VM      finish F1 F2 C1 F3

  F1 - F3 : pushed by VM
  C1      : pushed by send insn (CFUNC)

  struct CONTROL_FRAME {
    VALUE *pc;                  // cfp[0], program counter
    VALUE *sp;                  // cfp[1], stack pointer
    rb_iseq_t *iseq;            // cfp[2], iseq
    VALUE self;                 // cfp[3], self
    const VALUE *ep;            // cfp[4], env pointer
    const void *block_code;     // cfp[5], block code
  };

  struct rb_captured_block {
    VALUE self;
    VALUE *ep;
    union code;
  };

  struct METHOD_ENV {
    VALUE param0;
    ...
    VALUE paramN;
    VALUE lvar1;
    ...
    VALUE lvarM;
    VALUE cref;    // ep[-2]
    VALUE special; // ep[-1]
    VALUE flags;   // ep[ 0] == lep[0]
  };

  struct BLOCK_ENV {
    VALUE block_param0;
    ...
    VALUE block_paramN;
    VALUE block_lvar1;
    ...
    VALUE block_lvarM;
    VALUE cref;    // ep[-2]
    VALUE special; // ep[-1]
    VALUE flags;   // ep[ 0]
  };

  struct CLASS_ENV {
    VALUE class_lvar0;
    ...
    VALUE class_lvarN;
    VALUE cref;
    VALUE prev_ep; // for frame jump
    VALUE flags;
  };

  struct C_METHOD_CONTROL_FRAME {
    VALUE *pc;                       // 0
    VALUE *sp;                       // stack pointer
    rb_iseq_t *iseq;                 // cmi
    VALUE self;                      // ?
    VALUE *ep;                       // ep == lep
    void *code;                      //
  };

  struct C_BLOCK_CONTROL_FRAME {
    VALUE *pc;                       // point only "finish" insn
    VALUE *sp;                       // sp
    rb_iseq_t *iseq;                 // ?
    VALUE self;                      //
    VALUE *ep;                       // ep
    void *code;                      //
  };

  If mjit_exec is already called before calling vm_exec, `mjit_enable_p` should
  be FALSE to avoid calling `mjit_exec` twice.
 */

static inline VALUE
vm_exec_handle_exception(rb_execution_context_t *ec, enum ruby_tag_type state,
                         VALUE errinfo, VALUE *initial);

VALUE
vm_exec(rb_execution_context_t *ec, int mjit_enable_p)
{
    enum ruby_tag_type state;
    VALUE result = Qundef;
    VALUE initial = 0;

    EC_PUSH_TAG(ec);

    _tag.retval = Qnil;
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        if (!mjit_enable_p || (result = mjit_exec(ec)) == Qundef) {
            result = vm_exec_core(ec, initial);
        }
        goto vm_loop_start; /* fallback to the VM */
    }
    else {
	result = ec->errinfo;
        rb_ec_raised_reset(ec, RAISED_STACKOVERFLOW);
        while ((result = vm_exec_handle_exception(ec, state, result, &initial)) == Qundef) {
            /* caught a jump, exec the handler */
            result = vm_exec_core(ec, initial);
	  vm_loop_start:
	    VM_ASSERT(ec->tag == &_tag);
	    /* when caught `throw`, `tag.state` is set. */
	    if ((state = _tag.state) == TAG_NONE) break;
	    _tag.state = TAG_NONE;
	}
    }
    EC_POP_TAG();
    return result;
}

static inline VALUE
vm_exec_handle_exception(rb_execution_context_t *ec, enum ruby_tag_type state,
                         VALUE errinfo, VALUE *initial)
{
    struct vm_throw_data *err = (struct vm_throw_data *)errinfo;

    for (;;) {
	unsigned int i;
	const struct iseq_catch_table_entry *entry;
	const struct iseq_catch_table *ct;
	unsigned long epc, cont_pc, cont_sp;
	const rb_iseq_t *catch_iseq;
	rb_control_frame_t *cfp;
	VALUE type;
	const rb_control_frame_t *escape_cfp;

	cont_pc = cont_sp = 0;
	catch_iseq = NULL;

	while (ec->cfp->pc == 0 || ec->cfp->iseq == 0) {
	    if (UNLIKELY(VM_FRAME_TYPE(ec->cfp) == VM_FRAME_MAGIC_CFUNC)) {
		EXEC_EVENT_HOOK_AND_POP_FRAME(ec, RUBY_EVENT_C_RETURN, ec->cfp->self,
					      rb_vm_frame_method_entry(ec->cfp)->def->original_id,
					      rb_vm_frame_method_entry(ec->cfp)->called_id,
					      rb_vm_frame_method_entry(ec->cfp)->owner, Qnil);
		RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec,
						rb_vm_frame_method_entry(ec->cfp)->owner,
						rb_vm_frame_method_entry(ec->cfp)->def->original_id);
	    }
	    rb_vm_pop_frame(ec);
	}

	cfp = ec->cfp;
	epc = cfp->pc - cfp->iseq->body->iseq_encoded;

	escape_cfp = NULL;
	if (state == TAG_BREAK || state == TAG_RETURN) {
	    escape_cfp = THROW_DATA_CATCH_FRAME(err);

	    if (cfp == escape_cfp) {
		if (state == TAG_RETURN) {
		    if (!VM_FRAME_FINISHED_P(cfp)) {
			THROW_DATA_CATCH_FRAME_SET(err, cfp + 1);
			THROW_DATA_STATE_SET(err, state = TAG_BREAK);
		    }
		    else {
			ct = cfp->iseq->body->catch_table;
			if (ct) for (i = 0; i < ct->size; i++) {
			    entry = UNALIGNED_MEMBER_PTR(ct, entries[i]);
			    if (entry->start < epc && entry->end >= epc) {
				if (entry->type == CATCH_TYPE_ENSURE) {
				    catch_iseq = entry->iseq;
				    cont_pc = entry->cont;
				    cont_sp = entry->sp;
				    break;
				}
			    }
			}
			if (catch_iseq == NULL) {
			    ec->errinfo = Qnil;
			    THROW_DATA_CATCH_FRAME_SET(err, cfp + 1);
			    hook_before_rewind(ec, ec->cfp, TRUE, state, err);
			    rb_vm_pop_frame(ec);
			    return THROW_DATA_VAL(err);
			}
		    }
		    /* through */
		}
		else {
		    /* TAG_BREAK */
#if OPT_STACK_CACHING
		    *initial = THROW_DATA_VAL(err);
#else
		    *ec->cfp->sp++ = THROW_DATA_VAL(err);
#endif
		    ec->errinfo = Qnil;
		    return Qundef;
		}
	    }
	}

	if (state == TAG_RAISE) {
	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = UNALIGNED_MEMBER_PTR(ct, entries[i]);
		if (entry->start < epc && entry->end >= epc) {

		    if (entry->type == CATCH_TYPE_RESCUE ||
			entry->type == CATCH_TYPE_ENSURE) {
			catch_iseq = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		}
	    }
	}
	else if (state == TAG_RETRY) {
	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = UNALIGNED_MEMBER_PTR(ct, entries[i]);
		if (entry->start < epc && entry->end >= epc) {

		    if (entry->type == CATCH_TYPE_ENSURE) {
			catch_iseq = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		    else if (entry->type == CATCH_TYPE_RETRY) {
			const rb_control_frame_t *escape_cfp;
			escape_cfp = THROW_DATA_CATCH_FRAME(err);
			if (cfp == escape_cfp) {
			    cfp->pc = cfp->iseq->body->iseq_encoded + entry->cont;
			    ec->errinfo = Qnil;
			    return Qundef;
			}
		    }
		}
	    }
	}
        else if ((state == TAG_BREAK && !escape_cfp) ||
                 (state == TAG_REDO) ||
                 (state == TAG_NEXT)) {
            type = (const enum catch_type[TAG_MASK]) {
                [TAG_BREAK]  = CATCH_TYPE_BREAK,
                [TAG_NEXT]   = CATCH_TYPE_NEXT,
                [TAG_REDO]   = CATCH_TYPE_REDO,
                /* otherwise = dontcare */
            }[state];

	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = UNALIGNED_MEMBER_PTR(ct, entries[i]);

		if (entry->start < epc && entry->end >= epc) {
		    if (entry->type == CATCH_TYPE_ENSURE) {
			catch_iseq = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		    else if (entry->type == type) {
			cfp->pc = cfp->iseq->body->iseq_encoded + entry->cont;
			cfp->sp = vm_base_ptr(cfp) + entry->sp;

			if (state != TAG_REDO) {
#if OPT_STACK_CACHING
			    *initial = THROW_DATA_VAL(err);
#else
			    *ec->cfp->sp++ = THROW_DATA_VAL(err);
#endif
			}
			ec->errinfo = Qnil;
			VM_ASSERT(ec->tag->state == TAG_NONE);
			return Qundef;
		    }
		}
	    }
	}
	else {
	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = UNALIGNED_MEMBER_PTR(ct, entries[i]);
		if (entry->start < epc && entry->end >= epc) {

		    if (entry->type == CATCH_TYPE_ENSURE) {
			catch_iseq = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		}
	    }
	}

	if (catch_iseq != NULL) { /* found catch table */
	    /* enter catch scope */
	    const int arg_size = 1;

	    rb_iseq_check(catch_iseq);
	    cfp->sp = vm_base_ptr(cfp) + cont_sp;
	    cfp->pc = cfp->iseq->body->iseq_encoded + cont_pc;

	    /* push block frame */
	    cfp->sp[0] = (VALUE)err;
	    vm_push_frame(ec, catch_iseq, VM_FRAME_MAGIC_RESCUE,
			  cfp->self,
			  VM_GUARDED_PREV_EP(cfp->ep),
			  0, /* cref or me */
			  catch_iseq->body->iseq_encoded,
			  cfp->sp + arg_size /* push value */,
			  catch_iseq->body->local_table_size - arg_size,
			  catch_iseq->body->stack_max);

	    state = 0;
	    ec->tag->state = TAG_NONE;
	    ec->errinfo = Qnil;

	    return Qundef;
	}
	else {
	    hook_before_rewind(ec, ec->cfp, FALSE, state, err);

	    if (VM_FRAME_FINISHED_P(ec->cfp)) {
		rb_vm_pop_frame(ec);
		ec->errinfo = (VALUE)err;
		ec->tag = ec->tag->prev;
		EC_JUMP_TAG(ec, state);
	    }
	    else {
		rb_vm_pop_frame(ec);
	    }
	}
    }
}

/* misc */

VALUE
rb_iseq_eval(const rb_iseq_t *iseq)
{
    rb_execution_context_t *ec = GET_EC();
    VALUE val;
    vm_set_top_stack(ec, iseq);
    val = vm_exec(ec, TRUE);
    return val;
}

VALUE
rb_iseq_eval_main(const rb_iseq_t *iseq)
{
    rb_execution_context_t *ec = GET_EC();
    VALUE val;

    vm_set_main_stack(ec, iseq);
    val = vm_exec(ec, TRUE);
    return val;
}

int
rb_vm_control_frame_id_and_class(const rb_control_frame_t *cfp, ID *idp, ID *called_idp, VALUE *klassp)
{
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    if (me) {
	if (idp) *idp = me->def->original_id;
	if (called_idp) *called_idp = me->called_id;
	if (klassp) *klassp = me->owner;
	return TRUE;
    }
    else {
	return FALSE;
    }
}

int
rb_ec_frame_method_id_and_class(const rb_execution_context_t *ec, ID *idp, ID *called_idp, VALUE *klassp)
{
    return rb_vm_control_frame_id_and_class(ec->cfp, idp, called_idp, klassp);
}

int
rb_frame_method_id_and_class(ID *idp, VALUE *klassp)
{
    return rb_ec_frame_method_id_and_class(GET_EC(), idp, 0, klassp);
}

VALUE
rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg,
		 VALUE block_handler, VALUE filename)
{
    rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *reg_cfp = ec->cfp;
    const rb_iseq_t *iseq = rb_iseq_new(0, filename, filename, Qnil, 0, ISEQ_TYPE_TOP);
    VALUE val;

    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_TOP | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH,
		  recv, block_handler,
		  (VALUE)vm_cref_new_toplevel(ec), /* cref or me */
		  0, reg_cfp->sp, 0, 0);

    val = (*func)(arg);

    rb_vm_pop_frame(ec);
    return val;
}

/* vm */

void
rb_vm_update_references(void *ptr)
{
    if (ptr) {
        rb_vm_t *vm = ptr;

        rb_gc_update_tbl_refs(vm->frozen_strings);
        vm->mark_object_ary = rb_gc_location(vm->mark_object_ary);
        vm->load_path = rb_gc_location(vm->load_path);
        vm->load_path_snapshot = rb_gc_location(vm->load_path_snapshot);

        if (vm->load_path_check_cache) {
            vm->load_path_check_cache = rb_gc_location(vm->load_path_check_cache);
        }

        vm->expanded_load_path = rb_gc_location(vm->expanded_load_path);
        vm->loaded_features = rb_gc_location(vm->loaded_features);
        vm->loaded_features_snapshot = rb_gc_location(vm->loaded_features_snapshot);
        vm->top_self = rb_gc_location(vm->top_self);
        vm->orig_progname = rb_gc_location(vm->orig_progname);

        if (vm->coverages) {
            vm->coverages = rb_gc_location(vm->coverages);
        }
    }
}

void
rb_vm_mark(void *ptr)
{
    RUBY_MARK_ENTER("vm");
    RUBY_GC_INFO("-------------------------------------------------\n");
    if (ptr) {
	rb_vm_t *vm = ptr;
        rb_ractor_t *r = 0;
        long i, len;
        const VALUE *obj_ary;

	list_for_each(&vm->ractor.set, r, vmlr_node) {
            // ractor.set only contains blocking or running ractors
            VM_ASSERT(rb_ractor_status_p(r, ractor_blocking) ||
                      rb_ractor_status_p(r, ractor_running));
            rb_gc_mark(rb_ractor_self(r));
	}

        rb_gc_mark_movable(vm->mark_object_ary);

        len = RARRAY_LEN(vm->mark_object_ary);
        obj_ary = RARRAY_CONST_PTR(vm->mark_object_ary);
        for (i=0; i < len; i++) {
            const VALUE *ptr;
            long j, jlen;

            rb_gc_mark(*obj_ary);
            jlen = RARRAY_LEN(*obj_ary);
            ptr = RARRAY_CONST_PTR(*obj_ary);
            for (j=0; j < jlen; j++) {
                rb_gc_mark(*ptr++);
            }
            obj_ary++;
        }

        rb_gc_mark_movable(vm->load_path);
        rb_gc_mark_movable(vm->load_path_snapshot);
        RUBY_MARK_MOVABLE_UNLESS_NULL(vm->load_path_check_cache);
        rb_gc_mark_movable(vm->expanded_load_path);
        rb_gc_mark_movable(vm->loaded_features);
        rb_gc_mark_movable(vm->loaded_features_snapshot);
        rb_gc_mark_movable(vm->top_self);
        rb_gc_mark_movable(vm->orig_progname);
        RUBY_MARK_MOVABLE_UNLESS_NULL(vm->coverages);
        /* Prevent classes from moving */
        rb_mark_tbl(vm->defined_module_hash);

	if (vm->loading_table) {
	    rb_mark_tbl(vm->loading_table);
	}

	rb_hook_list_mark(&vm->global_hooks);

	rb_gc_mark_values(RUBY_NSIG, vm->trap_list.cmd);

        mjit_mark();
    }

    RUBY_MARK_LEAVE("vm");
}

#undef rb_vm_register_special_exception
void
rb_vm_register_special_exception_str(enum ruby_special_exceptions sp, VALUE cls, VALUE mesg)
{
    rb_vm_t *vm = GET_VM();
    VALUE exc = rb_exc_new3(cls, rb_obj_freeze(mesg));
    OBJ_FREEZE(exc);
    ((VALUE *)vm->special_exceptions)[sp] = exc;
    rb_gc_register_mark_object(exc);
}

int
rb_vm_add_root_module(ID id, VALUE module)
{
    rb_vm_t *vm = GET_VM();

    st_insert(vm->defined_module_hash, (st_data_t)module, (st_data_t)module);

    return TRUE;
}

static int
free_loading_table_entry(st_data_t key, st_data_t value, st_data_t arg)
{
    xfree((char *)key);
    return ST_DELETE;
}

int
ruby_vm_destruct(rb_vm_t *vm)
{
    RUBY_FREE_ENTER("vm");

    if (vm) {
	rb_thread_t *th = vm->ractor.main_thread;
	struct rb_objspace *objspace = vm->objspace;
        vm->ractor.main_thread = NULL;

        if (th) {
            rb_fiber_reset_root_local_storage(th);
	    thread_free(th);
	}
	rb_vm_living_threads_init(vm);
	ruby_vm_run_at_exit_hooks(vm);
	if (vm->loading_table) {
	    st_foreach(vm->loading_table, free_loading_table_entry, 0);
	    st_free_table(vm->loading_table);
	    vm->loading_table = 0;
	}
	if (vm->frozen_strings) {
	    st_free_table(vm->frozen_strings);
	    vm->frozen_strings = 0;
	}
	RB_ALTSTACK_FREE(vm->main_altstack);
	if (objspace) {
	    rb_objspace_free(objspace);
	}
	/* after freeing objspace, you *can't* use ruby_xfree() */
	ruby_mimfree(vm);
	ruby_current_vm_ptr = NULL;
    }
    RUBY_FREE_LEAVE("vm");
    return 0;
}

static size_t
vm_memsize(const void *ptr)
{
    const rb_vm_t *vmobj = ptr;
    size_t size = sizeof(rb_vm_t);

    // TODO
    // size += vmobj->ractor_num * sizeof(rb_ractor_t);

    if (vmobj->defined_strings) {
	size += DEFINED_EXPR * sizeof(VALUE);
    }
    return size;
}

static const rb_data_type_t vm_data_type = {
    "VM",
    {0, 0, vm_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};


static VALUE
vm_default_params(void)
{
    rb_vm_t *vm = GET_VM();
    VALUE result = rb_hash_new_with_size(4);
#define SET(name) rb_hash_aset(result, ID2SYM(rb_intern(#name)), SIZET2NUM(vm->default_params.name));
    SET(thread_vm_stack_size);
    SET(thread_machine_stack_size);
    SET(fiber_vm_stack_size);
    SET(fiber_machine_stack_size);
#undef SET
    rb_obj_freeze(result);
    return result;
}

static size_t
get_param(const char *name, size_t default_value, size_t min_value)
{
    const char *envval;
    size_t result = default_value;
    if ((envval = getenv(name)) != 0) {
	long val = atol(envval);
	if (val < (long)min_value) {
	    val = (long)min_value;
	}
	result = (size_t)(((val -1 + RUBY_VM_SIZE_ALIGN) / RUBY_VM_SIZE_ALIGN) * RUBY_VM_SIZE_ALIGN);
    }
    if (0) fprintf(stderr, "%s: %"PRIuSIZE"\n", name, result); /* debug print */

    return result;
}

static void
check_machine_stack_size(size_t *sizep)
{
#ifdef PTHREAD_STACK_MIN
    size_t size = *sizep;
#endif

#ifdef PTHREAD_STACK_MIN
    if (size < PTHREAD_STACK_MIN) {
	*sizep = PTHREAD_STACK_MIN * 2;
    }
#endif
}

static void
vm_default_params_setup(rb_vm_t *vm)
{
    vm->default_params.thread_vm_stack_size =
      get_param("RUBY_THREAD_VM_STACK_SIZE",
		RUBY_VM_THREAD_VM_STACK_SIZE,
		RUBY_VM_THREAD_VM_STACK_SIZE_MIN);

    vm->default_params.thread_machine_stack_size =
      get_param("RUBY_THREAD_MACHINE_STACK_SIZE",
		RUBY_VM_THREAD_MACHINE_STACK_SIZE,
		RUBY_VM_THREAD_MACHINE_STACK_SIZE_MIN);

    vm->default_params.fiber_vm_stack_size =
      get_param("RUBY_FIBER_VM_STACK_SIZE",
		RUBY_VM_FIBER_VM_STACK_SIZE,
		RUBY_VM_FIBER_VM_STACK_SIZE_MIN);

    vm->default_params.fiber_machine_stack_size =
      get_param("RUBY_FIBER_MACHINE_STACK_SIZE",
		RUBY_VM_FIBER_MACHINE_STACK_SIZE,
		RUBY_VM_FIBER_MACHINE_STACK_SIZE_MIN);

    /* environment dependent check */
    check_machine_stack_size(&vm->default_params.thread_machine_stack_size);
    check_machine_stack_size(&vm->default_params.fiber_machine_stack_size);
}

static void
vm_init2(rb_vm_t *vm)
{
    MEMZERO(vm, rb_vm_t, 1);
    rb_vm_living_threads_init(vm);
    vm->thread_report_on_exception = 1;
    vm->src_encoding_index = -1;

    vm_default_params_setup(vm);
}

void
rb_execution_context_update(const rb_execution_context_t *ec)
{
    /* update VM stack */
    if (ec->vm_stack) {
        long i;
        VM_ASSERT(ec->cfp);
        VALUE *p = ec->vm_stack;
        VALUE *sp = ec->cfp->sp;
        rb_control_frame_t *cfp = ec->cfp;
        rb_control_frame_t *limit_cfp = (void *)(ec->vm_stack + ec->vm_stack_size);

        for (i = 0; i < (long)(sp - p); i++) {
            VALUE ref = p[i];
            VALUE update = rb_gc_location(ref);
            if (ref != update) {
                p[i] = update;
            }
        }

        while (cfp != limit_cfp) {
            const VALUE *ep = cfp->ep;
            cfp->self = rb_gc_location(cfp->self);
            cfp->iseq = (rb_iseq_t *)rb_gc_location((VALUE)cfp->iseq);
            cfp->block_code = (void *)rb_gc_location((VALUE)cfp->block_code);

            while (!VM_ENV_LOCAL_P(ep)) {
                if (VM_ENV_FLAGS(ep, VM_ENV_FLAG_ESCAPED)) {
                    VM_FORCE_WRITE(&ep[VM_ENV_DATA_INDEX_ENV], rb_gc_location(ep[VM_ENV_DATA_INDEX_ENV]));
                    VM_FORCE_WRITE(&ep[VM_ENV_DATA_INDEX_ME_CREF], rb_gc_location(ep[VM_ENV_DATA_INDEX_ME_CREF]));
                }
                ep = VM_ENV_PREV_EP(ep);
            }

            cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
        }
    }
}

static enum rb_id_table_iterator_result
mark_local_storage_i(VALUE local, void *data)
{
    rb_gc_mark(local);
    return ID_TABLE_CONTINUE;
}

void
rb_execution_context_mark(const rb_execution_context_t *ec)
{
    /* mark VM stack */
    if (ec->vm_stack) {
        VM_ASSERT(ec->cfp);
	VALUE *p = ec->vm_stack;
	VALUE *sp = ec->cfp->sp;
	rb_control_frame_t *cfp = ec->cfp;
	rb_control_frame_t *limit_cfp = (void *)(ec->vm_stack + ec->vm_stack_size);

        VM_ASSERT(sp == ec->cfp->sp);
        rb_gc_mark_vm_stack_values((long)(sp - p), p);

	while (cfp != limit_cfp) {
	    const VALUE *ep = cfp->ep;
	    VM_ASSERT(!!VM_ENV_FLAGS(ep, VM_ENV_FLAG_ESCAPED) == vm_ep_in_heap_p_(ec, ep));
            rb_gc_mark_movable(cfp->self);
            rb_gc_mark_movable((VALUE)cfp->iseq);
            rb_gc_mark_movable((VALUE)cfp->block_code);

            while (!VM_ENV_LOCAL_P(ep)) {
		if (VM_ENV_FLAGS(ep, VM_ENV_FLAG_ESCAPED)) {
                    rb_gc_mark_movable(ep[VM_ENV_DATA_INDEX_ENV]);
                    rb_gc_mark(ep[VM_ENV_DATA_INDEX_ME_CREF]);
		}
                ep = VM_ENV_PREV_EP(ep);
            }

	    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	}
    }

    /* mark machine stack */
    if (ec->machine.stack_start && ec->machine.stack_end &&
	ec != GET_EC() /* marked for current ec at the first stage of marking */
	) {
	rb_gc_mark_machine_stack(ec);
	rb_gc_mark_locations((VALUE *)&ec->machine.regs,
			     (VALUE *)(&ec->machine.regs) +
			     sizeof(ec->machine.regs) / (sizeof(VALUE)));
    }

    RUBY_MARK_UNLESS_NULL(ec->errinfo);
    RUBY_MARK_UNLESS_NULL(ec->root_svar);
    if (ec->local_storage) {
        rb_id_table_foreach_values(ec->local_storage, mark_local_storage_i, NULL);
    }
    RUBY_MARK_UNLESS_NULL(ec->local_storage_recursive_hash);
    RUBY_MARK_UNLESS_NULL(ec->local_storage_recursive_hash_for_trace);
    RUBY_MARK_UNLESS_NULL(ec->private_const_reference);
}

void rb_fiber_mark_self(rb_fiber_t *fib);
void rb_fiber_update_self(rb_fiber_t *fib);
void rb_threadptr_root_fiber_setup(rb_thread_t *th);
void rb_threadptr_root_fiber_release(rb_thread_t *th);

static void
thread_compact(void *ptr)
{
    rb_thread_t *th = ptr;

    th->self = rb_gc_location(th->self);

    if (!th->root_fiber) {
        rb_execution_context_update(th->ec);
    }
}

static void
thread_mark(void *ptr)
{
    rb_thread_t *th = ptr;
    RUBY_MARK_ENTER("thread");
    rb_fiber_mark_self(th->ec->fiber_ptr);

    /* mark ruby objects */
    switch (th->invoke_type) {
      case thread_invoke_type_proc:
      case thread_invoke_type_ractor_proc:
        RUBY_MARK_UNLESS_NULL(th->invoke_arg.proc.proc);
        RUBY_MARK_UNLESS_NULL(th->invoke_arg.proc.args);
        break;
      case thread_invoke_type_func:
        rb_gc_mark_maybe((VALUE)th->invoke_arg.func.arg);
        break;
      default:
        break;
    }

    rb_gc_mark(rb_ractor_self(th->ractor));
    RUBY_MARK_UNLESS_NULL(th->thgroup);
    RUBY_MARK_UNLESS_NULL(th->value);
    RUBY_MARK_UNLESS_NULL(th->pending_interrupt_queue);
    RUBY_MARK_UNLESS_NULL(th->pending_interrupt_mask_stack);
    RUBY_MARK_UNLESS_NULL(th->top_self);
    RUBY_MARK_UNLESS_NULL(th->top_wrapper);
    if (th->root_fiber) rb_fiber_mark_self(th->root_fiber);

    /* Ensure EC stack objects are pinned */
    rb_execution_context_mark(th->ec);
    RUBY_MARK_UNLESS_NULL(th->stat_insn_usage);
    RUBY_MARK_UNLESS_NULL(th->last_status);
    RUBY_MARK_UNLESS_NULL(th->locking_mutex);
    RUBY_MARK_UNLESS_NULL(th->name);

    RUBY_MARK_UNLESS_NULL(th->scheduler);

    RUBY_MARK_LEAVE("thread");
}

static void
thread_free(void *ptr)
{
    rb_thread_t *th = ptr;
    RUBY_FREE_ENTER("thread");

    if (th->locking_mutex != Qfalse) {
	rb_bug("thread_free: locking_mutex must be NULL (%p:%p)", (void *)th, (void *)th->locking_mutex);
    }
    if (th->keeping_mutexes != NULL) {
	rb_bug("thread_free: keeping_mutexes must be NULL (%p:%p)", (void *)th, (void *)th->keeping_mutexes);
    }

    rb_threadptr_root_fiber_release(th);

    if (th->vm && th->vm->ractor.main_thread == th) {
	RUBY_GC_INFO("MRI main thread\n");
    }
    else {
	ruby_xfree(ptr);
    }

    RUBY_FREE_LEAVE("thread");
}

static size_t
thread_memsize(const void *ptr)
{
    const rb_thread_t *th = ptr;
    size_t size = sizeof(rb_thread_t);

    if (!th->root_fiber) {
	size += th->ec->vm_stack_size * sizeof(VALUE);
    }
    if (th->ec->local_storage) {
	size += rb_id_table_memsize(th->ec->local_storage);
    }
    return size;
}

#define thread_data_type ruby_threadptr_data_type
const rb_data_type_t ruby_threadptr_data_type = {
    "VM/thread",
    {
	thread_mark,
	thread_free,
	thread_memsize,
        thread_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE
rb_obj_is_thread(VALUE obj)
{
    if (rb_typeddata_is_kind_of(obj, &thread_data_type)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

static VALUE
thread_alloc(VALUE klass)
{
    VALUE obj;
    rb_thread_t *th;
    obj = TypedData_Make_Struct(klass, rb_thread_t, &thread_data_type, th);

    return obj;
}

inline void
rb_ec_set_vm_stack(rb_execution_context_t *ec, VALUE *stack, size_t size)
{
    ec->vm_stack = stack;
    ec->vm_stack_size = size;
}

void
rb_ec_initialize_vm_stack(rb_execution_context_t *ec, VALUE *stack, size_t size)
{
    rb_ec_set_vm_stack(ec, stack, size);

    ec->cfp = (void *)(ec->vm_stack + ec->vm_stack_size);

    vm_push_frame(ec,
        NULL /* dummy iseq */,
        VM_FRAME_MAGIC_DUMMY | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH | VM_FRAME_FLAG_CFRAME /* dummy frame */,
        Qnil /* dummy self */, VM_BLOCK_HANDLER_NONE /* dummy block ptr */,
        0 /* dummy cref/me */,
        0 /* dummy pc */, ec->vm_stack, 0, 0
    );
}

void
rb_ec_clear_vm_stack(rb_execution_context_t *ec)
{
    rb_ec_set_vm_stack(ec, NULL, 0);

    // Avoid dangling pointers:
    ec->cfp = NULL;
}

static void
th_init(rb_thread_t *th, VALUE self)
{
    th->self = self;
    rb_threadptr_root_fiber_setup(th);

    /* All threads are blocking until a non-blocking fiber is scheduled */
    th->blocking = 1;
    th->scheduler = Qnil;

    if (self == 0) {
        size_t size = th->vm->default_params.thread_vm_stack_size / sizeof(VALUE);
        rb_ec_initialize_vm_stack(th->ec, ALLOC_N(VALUE, size), size);
    }
    else {
        VM_ASSERT(th->ec->cfp == NULL);
        VM_ASSERT(th->ec->vm_stack == NULL);
        VM_ASSERT(th->ec->vm_stack_size == 0);
    }

    th->status = THREAD_RUNNABLE;
    th->last_status = Qnil;
    th->ec->errinfo = Qnil;
    th->ec->root_svar = Qfalse;
    th->ec->local_storage_recursive_hash = Qnil;
    th->ec->local_storage_recursive_hash_for_trace = Qnil;
#ifdef NON_SCALAR_THREAD_ID
    th->thread_id_string[0] = '\0';
#endif

#if OPT_CALL_THREADED_CODE
    th->retval = Qundef;
#endif
    th->name = Qnil;
    th->report_on_exception = th->vm->thread_report_on_exception;
}

static VALUE
ruby_thread_init(VALUE self)
{
    rb_thread_t *th = GET_THREAD();
    rb_thread_t *targe_th = rb_thread_ptr(self);
    rb_vm_t *vm = th->vm;

    targe_th->vm = vm;
    th_init(targe_th, self);

    targe_th->top_wrapper = 0;
    targe_th->top_self = rb_vm_top_self();
    targe_th->ec->root_svar = Qfalse;
    targe_th->ractor = th->ractor;
    return self;
}

VALUE
rb_thread_alloc(VALUE klass)
{
    VALUE self = thread_alloc(klass);
    ruby_thread_init(self);
    return self;
}

#define REWIND_CFP(expr) do { \
    rb_execution_context_t *ec__ = GET_EC(); \
    VALUE *const curr_sp = (ec__->cfp++)->sp; \
    VALUE *const saved_sp = ec__->cfp->sp; \
    ec__->cfp->sp = curr_sp; \
    expr; \
    (ec__->cfp--)->sp = saved_sp; \
} while (0)

static VALUE
m_core_set_method_alias(VALUE self, VALUE cbase, VALUE sym1, VALUE sym2)
{
    REWIND_CFP({
	rb_alias(cbase, SYM2ID(sym1), SYM2ID(sym2));
    });
    return Qnil;
}

static VALUE
m_core_set_variable_alias(VALUE self, VALUE sym1, VALUE sym2)
{
    REWIND_CFP({
	rb_alias_variable(SYM2ID(sym1), SYM2ID(sym2));
    });
    return Qnil;
}

static VALUE
m_core_undef_method(VALUE self, VALUE cbase, VALUE sym)
{
    REWIND_CFP({
        ID mid = SYM2ID(sym);
	rb_undef(cbase, mid);
	rb_clear_method_cache(self, mid);
    });
    return Qnil;
}

static VALUE
m_core_set_postexe(VALUE self)
{
    rb_set_end_proc(rb_call_end_proc, rb_block_proc());
    return Qnil;
}

static VALUE core_hash_merge_kwd(VALUE hash, VALUE kw);

static VALUE
core_hash_merge(VALUE hash, long argc, const VALUE *argv)
{
    Check_Type(hash, T_HASH);
    VM_ASSERT(argc % 2 == 0);
    rb_hash_bulk_insert(argc, argv, hash);
    return hash;
}

static VALUE
m_core_hash_merge_ptr(int argc, VALUE *argv, VALUE recv)
{
    VALUE hash = argv[0];

    REWIND_CFP(hash = core_hash_merge(hash, argc-1, argv+1));

    return hash;
}

static int
kwmerge_i(VALUE key, VALUE value, VALUE hash)
{
    rb_hash_aset(hash, key, value);
    return ST_CONTINUE;
}

static VALUE
m_core_hash_merge_kwd(VALUE recv, VALUE hash, VALUE kw)
{
    REWIND_CFP(hash = core_hash_merge_kwd(hash, kw));
    return hash;
}

static VALUE
core_hash_merge_kwd(VALUE hash, VALUE kw)
{
    rb_hash_foreach(rb_to_hash_type(kw), kwmerge_i, hash);
    return hash;
}

/* Returns true if JIT is enabled */
static VALUE
mjit_enabled_p(VALUE _)
{
    return mjit_enabled ? Qtrue : Qfalse;
}

static VALUE
mjit_pause_m(int argc, VALUE *argv, RB_UNUSED_VAR(VALUE self))
{
    VALUE options = Qnil;
    VALUE wait = Qtrue;
    rb_scan_args(argc, argv, "0:", &options);

    if (!NIL_P(options)) {
        static ID keyword_ids[1];
        if (!keyword_ids[0])
            keyword_ids[0] = rb_intern("wait");
        rb_get_kwargs(options, keyword_ids, 0, 1, &wait);
    }

    return mjit_pause(RTEST(wait));
}

static VALUE
mjit_resume_m(VALUE _)
{
    return mjit_resume();
}

extern VALUE *rb_gc_stack_start;
extern size_t rb_gc_stack_maxsize;

/* debug functions */

/* :nodoc: */
static VALUE
sdr(VALUE self)
{
    rb_vm_bugreport(NULL);
    return Qnil;
}

/* :nodoc: */
static VALUE
nsdr(VALUE self)
{
    VALUE ary = rb_ary_new();
#if HAVE_BACKTRACE
#include <execinfo.h>
#define MAX_NATIVE_TRACE 1024
    static void *trace[MAX_NATIVE_TRACE];
    int n = (int)backtrace(trace, MAX_NATIVE_TRACE);
    char **syms = backtrace_symbols(trace, n);
    int i;

    if (syms == 0) {
	rb_memerror();
    }

    for (i=0; i<n; i++) {
	rb_ary_push(ary, rb_str_new2(syms[i]));
    }
    free(syms); /* OK */
#endif
    return ary;
}

#if VM_COLLECT_USAGE_DETAILS
static VALUE usage_analysis_insn_start(VALUE self);
static VALUE usage_analysis_operand_start(VALUE self);
static VALUE usage_analysis_register_start(VALUE self);
static VALUE usage_analysis_insn_stop(VALUE self);
static VALUE usage_analysis_operand_stop(VALUE self);
static VALUE usage_analysis_register_stop(VALUE self);
static VALUE usage_analysis_insn_running(VALUE self);
static VALUE usage_analysis_operand_running(VALUE self);
static VALUE usage_analysis_register_running(VALUE self);
static VALUE usage_analysis_insn_clear(VALUE self);
static VALUE usage_analysis_operand_clear(VALUE self);
static VALUE usage_analysis_register_clear(VALUE self);
#endif

static VALUE
f_raise(int c, VALUE *v, VALUE _)
{
    return rb_f_raise(c, v);
}

static VALUE
f_proc(VALUE _)
{
    return rb_block_proc();
}

static VALUE
f_lambda(VALUE _)
{
    return rb_block_lambda();
}

static VALUE
vm_mtbl(VALUE self, VALUE obj, VALUE sym)
{
    vm_mtbl_dump(CLASS_OF(obj), RTEST(sym) ? SYM2ID(sym) : 0);
    return Qnil;
}

static VALUE
vm_mtbl2(VALUE self, VALUE obj, VALUE sym)
{
    vm_mtbl_dump(obj, RTEST(sym) ? SYM2ID(sym) : 0);
    return Qnil;
}

void
Init_VM(void)
{
    VALUE opts;
    VALUE klass;
    VALUE fcore;
    VALUE mjit;

    /*
     * Document-class: RubyVM
     *
     * The RubyVM module only exists on MRI. +RubyVM+ is not defined in
     * other Ruby implementations such as JRuby and TruffleRuby.
     *
     * The RubyVM module provides some access to MRI internals.
     * This module is for very limited purposes, such as debugging,
     * prototyping, and research.  Normal users must not use it.
     * This module is not portable between Ruby implementations.
     */
    rb_cRubyVM = rb_define_class("RubyVM", rb_cObject);
    rb_undef_alloc_func(rb_cRubyVM);
    rb_undef_method(CLASS_OF(rb_cRubyVM), "new");
    rb_define_singleton_method(rb_cRubyVM, "stat", vm_stat, -1);
#if USE_DEBUG_COUNTER
    rb_define_singleton_method(rb_cRubyVM, "reset_debug_counters", rb_debug_counter_reset, 0);
    rb_define_singleton_method(rb_cRubyVM, "show_debug_counters", rb_debug_counter_show, 0);
#endif

    /* FrozenCore (hidden) */
    fcore = rb_class_new(rb_cBasicObject);
    rb_set_class_path(fcore, rb_cRubyVM, "FrozenCore");
    RBASIC(fcore)->flags = T_ICLASS;
    klass = rb_singleton_class(fcore);
    rb_define_method_id(klass, id_core_set_method_alias, m_core_set_method_alias, 3);
    rb_define_method_id(klass, id_core_set_variable_alias, m_core_set_variable_alias, 2);
    rb_define_method_id(klass, id_core_undef_method, m_core_undef_method, 2);
    rb_define_method_id(klass, id_core_set_postexe, m_core_set_postexe, 0);
    rb_define_method_id(klass, id_core_hash_merge_ptr, m_core_hash_merge_ptr, -1);
    rb_define_method_id(klass, id_core_hash_merge_kwd, m_core_hash_merge_kwd, 2);
    rb_define_method_id(klass, id_core_raise, f_raise, -1);
    rb_define_method_id(klass, idProc, f_proc, 0);
    rb_define_method_id(klass, idLambda, f_lambda, 0);
    rb_obj_freeze(fcore);
    RBASIC_CLEAR_CLASS(klass);
    rb_obj_freeze(klass);
    rb_gc_register_mark_object(fcore);
    rb_mRubyVMFrozenCore = fcore;

    /* ::RubyVM::MJIT
     * Provides access to the Method JIT compiler of MRI.
     * Of course, this module is MRI specific.
     */
    mjit = rb_define_module_under(rb_cRubyVM, "MJIT");
    rb_define_singleton_method(mjit, "enabled?", mjit_enabled_p, 0);
    rb_define_singleton_method(mjit, "pause", mjit_pause_m, -1);
    rb_define_singleton_method(mjit, "resume", mjit_resume_m, 0);

    /*
     * Document-class: Thread
     *
     *	Threads are the Ruby implementation for a concurrent programming model.
     *
     *	Programs that require multiple threads of execution are a perfect
     *	candidate for Ruby's Thread class.
     *
     *	For example, we can create a new thread separate from the main thread's
     *	execution using ::new.
     *
     *	    thr = Thread.new { puts "What's the big deal" }
     *
     *	Then we are able to pause the execution of the main thread and allow
     *	our new thread to finish, using #join:
     *
     *	    thr.join #=> "What's the big deal"
     *
     *	If we don't call +thr.join+ before the main thread terminates, then all
     *	other threads including +thr+ will be killed.
     *
     *	Alternatively, you can use an array for handling multiple threads at
     *	once, like in the following example:
     *
     *	    threads = []
     *	    threads << Thread.new { puts "What's the big deal" }
     *	    threads << Thread.new { 3.times { puts "Threads are fun!" } }
     *
     *	After creating a few threads we wait for them all to finish
     *	consecutively.
     *
     *	    threads.each { |thr| thr.join }
     *
     *  To retrieve the last value of a thread, use #value
     *
     *      thr = Thread.new { sleep 1; "Useful value" }
     *      thr.value #=> "Useful value"
     *
     *	=== Thread initialization
     *
     *	In order to create new threads, Ruby provides ::new, ::start, and
     *	::fork. A block must be provided with each of these methods, otherwise
     *	a ThreadError will be raised.
     *
     *	When subclassing the Thread class, the +initialize+ method of your
     *	subclass will be ignored by ::start and ::fork. Otherwise, be sure to
     *	call super in your +initialize+ method.
     *
     * 	=== Thread termination
     *
     * 	For terminating threads, Ruby provides a variety of ways to do this.
     *
     *	The class method ::kill, is meant to exit a given thread:
     *
     *	    thr = Thread.new { sleep }
     *	    Thread.kill(thr) # sends exit() to thr
     *
     *	Alternatively, you can use the instance method #exit, or any of its
     *	aliases #kill or #terminate.
     *
     *	    thr.exit
     *
     * 	=== Thread status
     *
     * 	Ruby provides a few instance methods for querying the state of a given
     * 	thread. To get a string with the current thread's state use #status
     *
     *	    thr = Thread.new { sleep }
     *	    thr.status # => "sleep"
     *	    thr.exit
     *	    thr.status # => false
     *
     *	You can also use #alive? to tell if the thread is running or sleeping,
     *	and #stop? if the thread is dead or sleeping.
     *
     * 	=== Thread variables and scope
     *
     * 	Since threads are created with blocks, the same rules apply to other
     * 	Ruby blocks for variable scope. Any local variables created within this
     * 	block are accessible to only this thread.
     *
     * 	==== Fiber-local vs. Thread-local
     *
     *	Each fiber has its own bucket for Thread#[] storage. When you set a
     *	new fiber-local it is only accessible within this Fiber. To illustrate:
     *
     *	    Thread.new {
     *	      Thread.current[:foo] = "bar"
     *	      Fiber.new {
     *	        p Thread.current[:foo] # => nil
     *	      }.resume
     *	    }.join
     *
     * 	This example uses #[] for getting and #[]= for setting fiber-locals,
     * 	you can also use #keys to list the fiber-locals for a given
     * 	thread and #key? to check if a fiber-local exists.
     *
     *	When it comes to thread-locals, they are accessible within the entire
     *	scope of the thread. Given the following example:
     *
     *	    Thread.new{
     *	      Thread.current.thread_variable_set(:foo, 1)
     *	      p Thread.current.thread_variable_get(:foo) # => 1
     *	      Fiber.new{
     *		Thread.current.thread_variable_set(:foo, 2)
     *		p Thread.current.thread_variable_get(:foo) # => 2
     *	      }.resume
     *	      p Thread.current.thread_variable_get(:foo)   # => 2
     *	    }.join
     *
     *  You can see that the thread-local +:foo+ carried over into the fiber
     *  and was changed to +2+ by the end of the thread.
     *
     *  This example makes use of #thread_variable_set to create new
     *  thread-locals, and #thread_variable_get to reference them.
     *
     *  There is also #thread_variables to list all thread-locals, and
     *  #thread_variable? to check if a given thread-local exists.
     *
     * 	=== Exception handling
     *
     *  When an unhandled exception is raised inside a thread, it will
     *  terminate. By default, this exception will not propagate to other
     *  threads. The exception is stored and when another thread calls #value
     *  or #join, the exception will be re-raised in that thread.
     *
     *      t = Thread.new{ raise 'something went wrong' }
     *      t.value #=> RuntimeError: something went wrong
     *
     *  An exception can be raised from outside the thread using the
     *  Thread#raise instance method, which takes the same parameters as
     *  Kernel#raise.
     *
     *  Setting Thread.abort_on_exception = true, Thread#abort_on_exception =
     *  true, or $DEBUG = true will cause a subsequent unhandled exception
     *  raised in a thread to be automatically re-raised in the main thread.
     *
     *	With the addition of the class method ::handle_interrupt, you can now
     *	handle exceptions asynchronously with threads.
     *
     * 	=== Scheduling
     *
     * 	Ruby provides a few ways to support scheduling threads in your program.
     *
     * 	The first way is by using the class method ::stop, to put the current
     * 	running thread to sleep and schedule the execution of another thread.
     *
     * 	Once a thread is asleep, you can use the instance method #wakeup to
     * 	mark your thread as eligible for scheduling.
     *
     * 	You can also try ::pass, which attempts to pass execution to another
     * 	thread but is dependent on the OS whether a running thread will switch
     * 	or not. The same goes for #priority, which lets you hint to the thread
     * 	scheduler which threads you want to take precedence when passing
     * 	execution. This method is also dependent on the OS and may be ignored
     * 	on some platforms.
     *
     */
    rb_cThread = rb_define_class("Thread", rb_cObject);
    rb_undef_alloc_func(rb_cThread);

#if VM_COLLECT_USAGE_DETAILS
    /* ::RubyVM::USAGE_ANALYSIS_* */
#define define_usage_analysis_hash(name) /* shut up rdoc -C */ \
    rb_define_const(rb_cRubyVM, "USAGE_ANALYSIS_" #name, rb_hash_new())
    define_usage_analysis_hash(INSN);
    define_usage_analysis_hash(REGS);
    define_usage_analysis_hash(INSN_BIGRAM);

    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_INSN_START", usage_analysis_insn_start, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_OPERAND_START", usage_analysis_operand_start, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_REGISTER_START", usage_analysis_register_start, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_INSN_STOP", usage_analysis_insn_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_OPERAND_STOP", usage_analysis_operand_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_REGISTER_STOP", usage_analysis_register_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_INSN_RUNNING", usage_analysis_insn_running, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_OPERAND_RUNNING", usage_analysis_operand_running, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_REGISTER_RUNNING", usage_analysis_register_running, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_INSN_CLEAR", usage_analysis_insn_clear, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_OPERAND_CLEAR", usage_analysis_operand_clear, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_REGISTER_CLEAR", usage_analysis_register_clear, 0);
#endif

    /* ::RubyVM::OPTS
     * An Array of VM build options.
     * This constant is MRI specific.
     */
    rb_define_const(rb_cRubyVM, "OPTS", opts = rb_ary_new());

#if   OPT_DIRECT_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("direct threaded code"));
#elif OPT_TOKEN_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("token threaded code"));
#elif OPT_CALL_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("call threaded code"));
#endif

#if OPT_STACK_CACHING
    rb_ary_push(opts, rb_str_new2("stack caching"));
#endif
#if OPT_OPERANDS_UNIFICATION
    rb_ary_push(opts, rb_str_new2("operands unification"));
#endif
#if OPT_INSTRUCTIONS_UNIFICATION
    rb_ary_push(opts, rb_str_new2("instructions unification"));
#endif
#if OPT_INLINE_METHOD_CACHE
    rb_ary_push(opts, rb_str_new2("inline method cache"));
#endif
#if OPT_BLOCKINLINING
    rb_ary_push(opts, rb_str_new2("block inlining"));
#endif

    /* ::RubyVM::INSTRUCTION_NAMES
     * A list of bytecode instruction names in MRI.
     * This constant is MRI specific.
     */
    rb_define_const(rb_cRubyVM, "INSTRUCTION_NAMES", rb_insns_name_array());

    /* ::RubyVM::DEFAULT_PARAMS
     * This constant exposes the VM's default parameters.
     * Note that changing these values does not affect VM execution.
     * Specification is not stable and you should not depend on this value.
     * Of course, this constant is MRI specific.
     */
    rb_define_const(rb_cRubyVM, "DEFAULT_PARAMS", vm_default_params());

    /* debug functions ::RubyVM::SDR(), ::RubyVM::NSDR() */
#if VMDEBUG
    rb_define_singleton_method(rb_cRubyVM, "SDR", sdr, 0);
    rb_define_singleton_method(rb_cRubyVM, "NSDR", nsdr, 0);
    rb_define_singleton_method(rb_cRubyVM, "mtbl", vm_mtbl, 2);
    rb_define_singleton_method(rb_cRubyVM, "mtbl", vm_mtbl, 2);
    rb_define_singleton_method(rb_cRubyVM, "mtbl2", vm_mtbl2, 2);
#else
    (void)sdr;
    (void)nsdr;
    (void)vm_mtbl;
    (void)vm_mtbl2;
#endif

    /* VM bootstrap: phase 2 */
    {
	rb_vm_t *vm = ruby_current_vm_ptr;
	rb_thread_t *th = GET_THREAD();
	VALUE filename = rb_fstring_lit("<main>");
	const rb_iseq_t *iseq = rb_iseq_new(0, filename, filename, Qnil, 0, ISEQ_TYPE_TOP);

        // Ractor setup
        rb_ractor_main_setup(vm, th->ractor, th);

	/* create vm object */
	vm->self = TypedData_Wrap_Struct(rb_cRubyVM, &vm_data_type, vm);

	/* create main thread */
        th->self = TypedData_Wrap_Struct(rb_cThread, &thread_data_type, th);
	vm->ractor.main_thread = th;
        vm->ractor.main_ractor = th->ractor;
	th->vm = vm;
	th->top_wrapper = 0;
	th->top_self = rb_vm_top_self();

        rb_gc_register_mark_object((VALUE)iseq);
	th->ec->cfp->iseq = iseq;
	th->ec->cfp->pc = iseq->body->iseq_encoded;
	th->ec->cfp->self = th->top_self;

	VM_ENV_FLAGS_UNSET(th->ec->cfp->ep, VM_FRAME_FLAG_CFRAME);
	VM_STACK_ENV_WRITE(th->ec->cfp->ep, VM_ENV_DATA_INDEX_ME_CREF, (VALUE)vm_cref_new(rb_cObject, METHOD_VISI_PRIVATE, FALSE, NULL, FALSE));

	/*
	 * The Binding of the top level scope
	 */
	rb_define_global_const("TOPLEVEL_BINDING", rb_binding_new());
    }
    vm_init_redefined_flag();

    rb_block_param_proxy = rb_obj_alloc(rb_cObject);
    rb_add_method(rb_singleton_class(rb_block_param_proxy), idCall, VM_METHOD_TYPE_OPTIMIZED,
		  (void *)OPTIMIZED_METHOD_TYPE_BLOCK_CALL, METHOD_VISI_PUBLIC);
    rb_obj_freeze(rb_block_param_proxy);
    rb_gc_register_mark_object(rb_block_param_proxy);

    /* vm_backtrace.c */
    Init_vm_backtrace();
}

void
rb_vm_set_progname(VALUE filename)
{
    rb_thread_t *th = GET_VM()->ractor.main_thread;
    rb_control_frame_t *cfp = (void *)(th->ec->vm_stack + th->ec->vm_stack_size);
    --cfp;

    rb_iseq_pathobj_set(cfp->iseq, rb_str_dup(filename), rb_iseq_realpath(cfp->iseq));
}

extern const struct st_hash_type rb_fstring_hash_type;

void
Init_BareVM(void)
{
    /* VM bootstrap: phase 1 */
    rb_vm_t * vm = ruby_mimmalloc(sizeof(*vm));
    rb_thread_t * th = ruby_mimmalloc(sizeof(*th));
    if (!vm || !th) {
	fprintf(stderr, "[FATAL] failed to allocate memory\n");
	exit(EXIT_FAILURE);
    }
    MEMZERO(th, rb_thread_t, 1);
    vm_init2(vm);

    vm->objspace = rb_objspace_alloc();
    ruby_current_vm_ptr = vm;

    Init_native_thread(th);
    th->vm = vm;
    th_init(th, 0);
    vm->ractor.main_ractor = th->ractor = rb_ractor_main_alloc();
    rb_ractor_set_current_ec(th->ractor, th->ec);
    ruby_thread_init_stack(th);

    rb_native_mutex_initialize(&vm->ractor.sync.lock);
    rb_native_cond_initialize(&vm->ractor.sync.barrier_cond);
    rb_native_cond_initialize(&vm->ractor.sync.terminate_cond);
}

void
Init_vm_objects(void)
{
    rb_vm_t *vm = GET_VM();

    vm->defined_module_hash = st_init_numtable();

    /* initialize mark object array, hash */
    vm->mark_object_ary = rb_ary_tmp_new(128);
    vm->loading_table = st_init_strtable();
    vm->frozen_strings = st_init_table_with_size(&rb_fstring_hash_type, 10000);

    rb_objspace_gc_enable(vm->objspace);
}

/* top self */

static VALUE
main_to_s(VALUE obj)
{
    return rb_str_new2("main");
}

VALUE
rb_vm_top_self(void)
{
    return GET_VM()->top_self;
}

void
Init_top_self(void)
{
    rb_vm_t *vm = GET_VM();

    vm->top_self = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(rb_vm_top_self(), "to_s", main_to_s, 0);
    rb_define_alias(rb_singleton_class(rb_vm_top_self()), "inspect", "to_s");
}

VALUE *
rb_ruby_verbose_ptr(void)
{
    rb_ractor_t *cr = GET_RACTOR();
    return &cr->verbose;
}

VALUE *
rb_ruby_debug_ptr(void)
{
    rb_ractor_t *cr = GET_RACTOR();
    return &cr->debug;
}

/* iseq.c */
VALUE rb_insn_operand_intern(const rb_iseq_t *iseq,
			     VALUE insn, int op_no, VALUE op,
			     int len, size_t pos, VALUE *pnop, VALUE child);

st_table *
rb_vm_fstring_table(void)
{
    return GET_VM()->frozen_strings;
}

#if VM_COLLECT_USAGE_DETAILS

#define HASH_ASET(h, k, v) rb_hash_aset((h), (st_data_t)(k), (st_data_t)(v))

/* uh = {
 *   insn(Fixnum) => ihash(Hash)
 * }
 * ihash = {
 *   -1(Fixnum) => count,      # insn usage
 *    0(Fixnum) => ophash,     # operand usage
 * }
 * ophash = {
 *   val(interned string) => count(Fixnum)
 * }
 */
static void
vm_analysis_insn(int insn)
{
    ID usage_hash;
    ID bigram_hash;
    static int prev_insn = -1;

    VALUE uh;
    VALUE ihash;
    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");
    CONST_ID(bigram_hash, "USAGE_ANALYSIS_INSN_BIGRAM");
    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((ihash = rb_hash_aref(uh, INT2FIX(insn))) == Qnil) {
	ihash = rb_hash_new();
	HASH_ASET(uh, INT2FIX(insn), ihash);
    }
    if ((cv = rb_hash_aref(ihash, INT2FIX(-1))) == Qnil) {
	cv = INT2FIX(0);
    }
    HASH_ASET(ihash, INT2FIX(-1), INT2FIX(FIX2INT(cv) + 1));

    /* calc bigram */
    if (prev_insn != -1) {
	VALUE bi;
	VALUE ary[2];
	VALUE cv;

	ary[0] = INT2FIX(prev_insn);
	ary[1] = INT2FIX(insn);
	bi = rb_ary_new4(2, &ary[0]);

	uh = rb_const_get(rb_cRubyVM, bigram_hash);
	if ((cv = rb_hash_aref(uh, bi)) == Qnil) {
	    cv = INT2FIX(0);
	}
	HASH_ASET(uh, bi, INT2FIX(FIX2INT(cv) + 1));
    }
    prev_insn = insn;
}

static void
vm_analysis_operand(int insn, int n, VALUE op)
{
    ID usage_hash;

    VALUE uh;
    VALUE ihash;
    VALUE ophash;
    VALUE valstr;
    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");

    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((ihash = rb_hash_aref(uh, INT2FIX(insn))) == Qnil) {
	ihash = rb_hash_new();
	HASH_ASET(uh, INT2FIX(insn), ihash);
    }
    if ((ophash = rb_hash_aref(ihash, INT2FIX(n))) == Qnil) {
	ophash = rb_hash_new();
	HASH_ASET(ihash, INT2FIX(n), ophash);
    }
    /* intern */
    valstr = rb_insn_operand_intern(GET_EC()->cfp->iseq, insn, n, op, 0, 0, 0, 0);

    /* set count */
    if ((cv = rb_hash_aref(ophash, valstr)) == Qnil) {
	cv = INT2FIX(0);
    }
    HASH_ASET(ophash, valstr, INT2FIX(FIX2INT(cv) + 1));
}

static void
vm_analysis_register(int reg, int isset)
{
    ID usage_hash;
    VALUE uh;
    VALUE valstr;
    static const char regstrs[][5] = {
	"pc",			/* 0 */
	"sp",			/* 1 */
	"ep",                   /* 2 */
	"cfp",			/* 3 */
	"self",			/* 4 */
	"iseq",			/* 5 */
    };
    static const char getsetstr[][4] = {
	"get",
	"set",
    };
    static VALUE syms[sizeof(regstrs) / sizeof(regstrs[0])][2];

    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_REGS");
    if (syms[0] == 0) {
	char buff[0x10];
	int i;

	for (i = 0; i < (int)(sizeof(regstrs) / sizeof(regstrs[0])); i++) {
	    int j;
	    for (j = 0; j < 2; j++) {
		snprintf(buff, 0x10, "%d %s %-4s", i, getsetstr[j], regstrs[i]);
		syms[i][j] = ID2SYM(rb_intern(buff));
	    }
	}
    }
    valstr = syms[reg][isset];

    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((cv = rb_hash_aref(uh, valstr)) == Qnil) {
	cv = INT2FIX(0);
    }
    HASH_ASET(uh, valstr, INT2FIX(FIX2INT(cv) + 1));
}

#undef HASH_ASET

static void (*ruby_vm_collect_usage_func_insn)(int insn) = NULL;
static void (*ruby_vm_collect_usage_func_operand)(int insn, int n, VALUE op) = NULL;
static void (*ruby_vm_collect_usage_func_register)(int reg, int isset) = NULL;

/* :nodoc: */
static VALUE
usage_analysis_insn_start(VALUE self)
{
    ruby_vm_collect_usage_func_insn = vm_analysis_insn;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_operand_start(VALUE self)
{
    ruby_vm_collect_usage_func_operand = vm_analysis_operand;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_register_start(VALUE self)
{
    ruby_vm_collect_usage_func_register = vm_analysis_register;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_insn_stop(VALUE self)
{
    ruby_vm_collect_usage_func_insn = 0;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_operand_stop(VALUE self)
{
    ruby_vm_collect_usage_func_operand = 0;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_register_stop(VALUE self)
{
    ruby_vm_collect_usage_func_register = 0;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_insn_running(VALUE self)
{
  if (ruby_vm_collect_usage_func_insn == 0) return Qfalse;
  return Qtrue;
}

/* :nodoc: */
static VALUE
usage_analysis_operand_running(VALUE self)
{
  if (ruby_vm_collect_usage_func_operand == 0) return Qfalse;
  return Qtrue;
}

/* :nodoc: */
static VALUE
usage_analysis_register_running(VALUE self)
{
  if (ruby_vm_collect_usage_func_register == 0) return Qfalse;
  return Qtrue;
}

/* :nodoc: */
static VALUE
usage_analysis_insn_clear(VALUE self)
{
  ID usage_hash;
  ID bigram_hash;
  VALUE uh;
  VALUE bh;

  CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");
  CONST_ID(bigram_hash, "USAGE_ANALYSIS_INSN_BIGRAM");
  uh = rb_const_get(rb_cRubyVM, usage_hash);
  bh = rb_const_get(rb_cRubyVM, bigram_hash);
  rb_hash_clear(uh);
  rb_hash_clear(bh);

  return Qtrue;
}

/* :nodoc: */
static VALUE
usage_analysis_operand_clear(VALUE self)
{
  ID usage_hash;
  VALUE uh;

  CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");
  uh = rb_const_get(rb_cRubyVM, usage_hash);
  rb_hash_clear(uh);

  return Qtrue;
}

/* :nodoc: */
static VALUE
usage_analysis_register_clear(VALUE self)
{
  ID usage_hash;
  VALUE uh;

  CONST_ID(usage_hash, "USAGE_ANALYSIS_REGS");
  uh = rb_const_get(rb_cRubyVM, usage_hash);
  rb_hash_clear(uh);

  return Qtrue;
}

#else

MAYBE_UNUSED(static void (*ruby_vm_collect_usage_func_insn)(int insn)) = 0;
MAYBE_UNUSED(static void (*ruby_vm_collect_usage_func_operand)(int insn, int n, VALUE op)) = 0;
MAYBE_UNUSED(static void (*ruby_vm_collect_usage_func_register)(int reg, int isset)) = 0;

#endif

#if VM_COLLECT_USAGE_DETAILS
/* @param insn instruction number */
static void
vm_collect_usage_insn(int insn)
{
    if (RUBY_DTRACE_INSN_ENABLED()) {
	RUBY_DTRACE_INSN(rb_insns_name(insn));
    }
    if (ruby_vm_collect_usage_func_insn)
	(*ruby_vm_collect_usage_func_insn)(insn);
}

/* @param insn instruction number
 * @param n    n-th operand
 * @param op   operand value
 */
static void
vm_collect_usage_operand(int insn, int n, VALUE op)
{
    if (RUBY_DTRACE_INSN_OPERAND_ENABLED()) {
	VALUE valstr;

	valstr = rb_insn_operand_intern(GET_EC()->cfp->iseq, insn, n, op, 0, 0, 0, 0);

	RUBY_DTRACE_INSN_OPERAND(RSTRING_PTR(valstr), rb_insns_name(insn));
	RB_GC_GUARD(valstr);
    }
    if (ruby_vm_collect_usage_func_operand)
	(*ruby_vm_collect_usage_func_operand)(insn, n, op);
}

/* @param reg register id. see code of vm_analysis_register() */
/* @param isset 0: read, 1: write */
static void
vm_collect_usage_register(int reg, int isset)
{
    if (ruby_vm_collect_usage_func_register)
	(*ruby_vm_collect_usage_func_register)(reg, isset);
}
#endif

MJIT_FUNC_EXPORTED const struct rb_callcache *
rb_vm_empty_cc(void)
{
    return &vm_empty_cc;
}

#endif /* #ifndef MJIT_HEADER */

#include "vm_call_iseq_optimized.inc" /* required from vm_insnhelper.c */
