/**********************************************************************

  vm.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "internal.h"
#include "ruby/vm.h"
#include "ruby/st.h"

#include "gc.h"
#include "vm_core.h"
#include "iseq.h"
#include "eval_intern.h"
#include "probes.h"
#include "probes_helper.h"

VALUE rb_str_concat_literals(size_t, const VALUE*);

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
rb_vm_search_cf_from_ep(const rb_thread_t * const th, const rb_control_frame_t *cfp, const VALUE * const ep)
{
    if (!ep) {
	return NULL;
    }
    else {
	const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(th); /* end of control frame pointer */

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

VALUE
rb_vm_frame_block_handler(const rb_control_frame_t *cfp)
{
    return VM_CF_BLOCK_HANDLER(cfp);
}

#if VM_CHECK_MODE > 0
static int
VM_CFP_IN_HEAP_P(const rb_thread_t *th, const rb_control_frame_t *cfp)
{
    const VALUE *start = th->stack;
    const VALUE *end = (VALUE *)th->stack + th->stack_size;
    if (start <= (VALUE *)cfp && (VALUE *)cfp < end) {
	return FALSE;
    }
    else {
	return TRUE;
    }
}

static int
VM_EP_IN_HEAP_P(const rb_thread_t *th, const VALUE *ep)
{
    const VALUE *start = th->stack;
    const VALUE *end = (VALUE *)th->cfp;
    if (start <= ep && ep < end) {
	return FALSE;
    }
    else {
	return TRUE;
    }
}

int
vm_ep_in_heap_p_(const rb_thread_t *th, const VALUE *ep)
{
    if (VM_EP_IN_HEAP_P(th, ep)) {
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
    return vm_ep_in_heap_p_(GET_THREAD(), ep);
}
#endif

static struct rb_captured_block *
VM_CFP_TO_CAPTURED_BLOCK(const rb_control_frame_t *cfp)
{
    VM_ASSERT(!VM_CFP_IN_HEAP_P(GET_THREAD(), cfp));
    return (struct rb_captured_block *)&cfp->self;
}

static rb_control_frame_t *
VM_CAPTURED_BLOCK_TO_CFP(const struct rb_captured_block *captured)
{
    rb_control_frame_t *cfp = ((rb_control_frame_t *)((VALUE *)(captured) - 3));
    VM_ASSERT(!VM_CFP_IN_HEAP_P(GET_THREAD(), cfp));
    VM_ASSERT(sizeof(rb_control_frame_t)/sizeof(VALUE) == 6 + VM_DEBUG_BP_CHECK ? 1 : 0);
    return cfp;
}

static int
VM_BH_FROM_CFP_P(VALUE block_handler, const rb_control_frame_t *cfp)
{
    const struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
    return VM_TAGGED_PTR_REF(block_handler, 0x03) == captured;
}

static VALUE
vm_passed_block_handler(rb_thread_t *th)
{
    VALUE block_handler = th->passed_block_handler;
    th->passed_block_handler = VM_BLOCK_HANDLER_NONE;
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

static rb_cref_t *
vm_cref_dup(const rb_cref_t *cref)
{
    VALUE klass = CREF_CLASS(cref);
    const rb_scope_visibility_t *visi = CREF_SCOPE_VISI(cref);
    rb_cref_t *next_cref = CREF_NEXT(cref), *new_cref;
    int pushed_by_eval = CREF_PUSHED_BY_EVAL(cref);

    new_cref = vm_cref_new(klass, visi->method_visi, visi->module_func, next_cref, pushed_by_eval);

    if (!NIL_P(CREF_REFINEMENTS(cref))) {
	CREF_REFINEMENTS_SET(new_cref, rb_hash_dup(CREF_REFINEMENTS(cref)));
	CREF_OMOD_SHARED_UNSET(new_cref);
    }

    return new_cref;
}

static rb_cref_t *
vm_cref_new_toplevel(rb_thread_t *th)
{
    rb_cref_t *cref = vm_cref_new(rb_cObject, METHOD_VISI_PRIVATE /* toplevel visibility is private */, FALSE, NULL, FALSE);

    if (th->top_wrapper) {
	cref = vm_cref_new(th->top_wrapper, METHOD_VISI_PRIVATE, FALSE, cref, FALSE);
    }

    return cref;
}

rb_cref_t *
rb_vm_cref_new_toplevel(void)
{
    return vm_cref_new_toplevel(GET_THREAD());
}

static void
vm_cref_dump(const char *mesg, const rb_cref_t *cref)
{
    fprintf(stderr, "vm_cref_dump: %s (%p)\n", mesg, cref);

    while (cref) {
	fprintf(stderr, "= cref| klass: %s\n", RSTRING_PTR(rb_class_path(CREF_CLASS(cref))));
	cref = CREF_NEXT(cref);
    }
}

static void
vm_bind_update_env(rb_binding_t *bind, VALUE envval)
{
    const rb_env_t *env = (rb_env_t *)envval;
    bind->block.as.captured.code.iseq = env->iseq;
    bind->block.as.captured.ep = env->ep;
}

#if VM_COLLECT_USAGE_DETAILS
static void vm_collect_usage_operand(int insn, int n, VALUE op);
static void vm_collect_usage_insn(int insn);
static void vm_collect_usage_register(int reg, int isset);
#endif

static VALUE vm_make_env_object(rb_thread_t *th, rb_control_frame_t *cfp);

static VALUE vm_invoke_bmethod(rb_thread_t *th, rb_proc_t *proc, VALUE self,
			       int argc, const VALUE *argv, VALUE block_handler);
static VALUE vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc, VALUE self,
			    int argc, const VALUE *argv, VALUE block_handler);

static rb_serial_t ruby_vm_global_method_state = 1;
static rb_serial_t ruby_vm_global_constant_state = 1;
static rb_serial_t ruby_vm_class_serial = 1;

#include "vm_insnhelper.h"
#include "vm_exec.h"
#include "vm_insnhelper.c"
#include "vm_exec.c"

#include "vm_method.c"
#include "vm_eval.c"

#define PROCDEBUG 0

rb_serial_t
rb_next_class_serial(void)
{
    return NEXT_CLASS_SERIAL();
}

VALUE rb_cRubyVM;
VALUE rb_cThread;
VALUE rb_mRubyVMFrozenCore;

#define ruby_vm_redefined_flag GET_VM()->redefined_flag
VALUE ruby_vm_const_missing_count = 0;
rb_thread_t *ruby_current_thread = 0;
rb_vm_t *ruby_current_vm = 0;
rb_event_flag_t ruby_vm_event_flags;

static void thread_free(void *ptr);

void
rb_vm_inc_const_missing_count(void)
{
    ruby_vm_const_missing_count +=1;
}

VALUE rb_class_path_no_cache(VALUE _klass);

int
ruby_th_dtrace_setup(rb_thread_t *th, VALUE klass, ID id,
		     struct ruby_dtrace_method_hook_args *args)
{
    enum ruby_value_type type;
    if (!klass) {
	if (!th) th = GET_THREAD();
	if (!rb_thread_method_id_and_class(th, &id, 0, &klass) || !klass)
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
	VALUE name = rb_class_path_no_cache(klass);
	const char *classname, *filename;
	const char *methodname = rb_id2name(id);
	if (methodname && (filename = rb_source_loc(&args->line_no)) != 0) {
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
 *      :global_method_state=>251,
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
    static VALUE sym_global_method_state, sym_global_constant_state, sym_class_serial;
    VALUE arg = Qnil;
    VALUE hash = Qnil, key = Qnil;

    if (rb_scan_args(argc, argv, "01", &arg) == 1) {
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

    if (sym_global_method_state == 0) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
	S(global_method_state);
	S(global_constant_state);
	S(class_serial);
#undef S
    }

#define SET(name, attr) \
    if (key == sym_##name) \
	return SERIALT2NUM(attr); \
    else if (hash != Qnil) \
	rb_hash_aset(hash, sym_##name, SERIALT2NUM(attr));

    SET(global_method_state, ruby_vm_global_method_state);
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
vm_set_top_stack(rb_thread_t *th, const rb_iseq_t *iseq)
{
    if (iseq->body->type != ISEQ_TYPE_TOP) {
	rb_raise(rb_eTypeError, "Not a toplevel InstructionSequence");
    }

    /* for return */
    vm_push_frame(th, iseq, VM_FRAME_MAGIC_TOP | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH, th->top_self,
		  VM_BLOCK_HANDLER_NONE,
		  (VALUE)vm_cref_new_toplevel(th), /* cref or me */
		  iseq->body->iseq_encoded, th->cfp->sp, iseq->body->local_table_size, iseq->body->stack_max);
}

static void
vm_set_eval_stack(rb_thread_t * th, const rb_iseq_t *iseq, const rb_cref_t *cref, const struct rb_block *base_block)
{
    vm_push_frame(th, iseq, VM_FRAME_MAGIC_EVAL | VM_FRAME_FLAG_FINISH,
		  vm_block_self(base_block), VM_GUARDED_PREV_EP(vm_block_ep(base_block)),
		  (VALUE)cref, /* cref or me */
		  iseq->body->iseq_encoded,
		  th->cfp->sp, iseq->body->local_table_size, iseq->body->stack_max);
}

static void
vm_set_main_stack(rb_thread_t *th, const rb_iseq_t *iseq)
{
    VALUE toplevel_binding = rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING"));
    rb_binding_t *bind;

    GetBindingPtr(toplevel_binding, bind);
    RUBY_ASSERT_MESG(bind, "TOPLEVEL_BINDING is not built");

    vm_set_eval_stack(th, iseq, 0, &bind->block);

    /* save binding */
    if (iseq->body->local_table_size > 0) {
	vm_bind_update_env(bind, vm_make_env_object(th, th->cfp));
    }
}

rb_control_frame_t *
rb_vm_get_binding_creatable_next_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (cfp->iseq) {
	    return (rb_control_frame_t *)cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

rb_control_frame_t *
rb_vm_get_ruby_level_next_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (VM_FRAME_RUBYFRAME_P(cfp)) {
	    return (rb_control_frame_t *)cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

static rb_control_frame_t *
vm_get_ruby_level_caller_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp)
{
    if (VM_FRAME_RUBYFRAME_P(cfp)) {
	return (rb_control_frame_t *)cfp;
    }

    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
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

void
rb_vm_pop_cfunc_frame(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, cfp->self, me->def->original_id, me->called_id, me->owner, Qnil);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->owner, me->def->original_id);
    vm_pop_frame(th, cfp, cfp->ep);
}

void
rb_vm_rewind_cfp(rb_thread_t *th, rb_control_frame_t *cfp)
{
    /* check skipped frame */
    while (th->cfp != cfp) {
#if VMDEBUG
	printf("skipped frame: %s\n", vm_frametype_name(th->cfp));
#endif
	if (VM_FRAME_TYPE(th->cfp) != VM_FRAME_MAGIC_CFUNC) {
	    rb_vm_pop_frame(th);
	}
	else { /* unlikely path */
	    rb_vm_pop_cfunc_frame();
	}
    }
}

/* obsolete */
void
rb_frame_pop(void)
{
    ONLY_FOR_INTERNAL_USE("rb_frame_pop()");
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
	free(l);
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

static void
vm_block_handler_escape(rb_thread_t *th, VALUE block_handler, VALUE *procvalptr)
{
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_ifunc:
      case block_handler_type_iseq:
	*procvalptr = rb_vm_make_proc(th, VM_BH_TO_CAPT_BLOCK(block_handler), rb_cProc);
	return;

      case block_handler_type_symbol:
      case block_handler_type_proc:
	*procvalptr = block_handler;
	return;
    }
    VM_UNREACHABLE(vm_block_handler_escape);
    return;
}

static VALUE
vm_make_env_each(rb_thread_t *const th, rb_control_frame_t *const cfp)
{
    VALUE blockprocval = Qfalse;
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

	    vm_make_env_each(th, prev_cfp);
	    VM_FORCE_WRITE_SPECIAL_CONST(&ep[VM_ENV_DATA_INDEX_SPECVAL], VM_GUARDED_PREV_EP(prev_cfp->ep));
	}
    }
    else {
	VALUE block_handler = VM_ENV_BLOCK_HANDLER(ep);

	if (block_handler != VM_BLOCK_HANDLER_NONE) {
	    vm_block_handler_escape(th, block_handler, &blockprocval);
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
	       1 /* envval */ +
	       (blockprocval ? 1 : 0) /* blockprocval */;
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

    if (blockprocval) RB_OBJ_WRITE(env, &env_ep[2], blockprocval);
    cfp->ep = env_ep;
    VM_ENV_FLAGS_SET(env_ep, VM_ENV_FLAG_ESCAPED | VM_ENV_FLAG_WB_REQUIRED);
    VM_STACK_ENV_WRITE(ep, 0, (VALUE)env);		/* GC mark */
    return (VALUE)env;
}

static VALUE
vm_make_env_object(rb_thread_t *th, rb_control_frame_t *cfp)
{
    VALUE envval = vm_make_env_each(th, cfp);

    if (PROCDEBUG) {
	check_env_value((const rb_env_t *)envval);
    }

    return envval;
}

void
rb_vm_stack_to_heap(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    while ((cfp = rb_vm_get_binding_creatable_next_cfp(th, cfp)) != 0) {
	vm_make_env_object(th, cfp);
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
	return VM_ENV_ENVVAL_PTR(VM_ENV_PREV_EP(ep));
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
	collect_local_variables_in_iseq(env->iseq, vars);
    } while ((env = rb_vm_env_prev_env(env)) != NULL);
}

static int
vm_collect_local_variables_in_heap(rb_thread_t *th, const VALUE *ep, const struct local_var_list *vars)
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

VALUE
rb_proc_create_from_captured(VALUE klass,
			     const struct rb_captured_block *captured,
			     enum rb_block_type block_type,
			     int8_t safe_level, int8_t is_from_method, int8_t is_lambda)
{
    VALUE procval = rb_proc_alloc(klass);
    rb_proc_t *proc = RTYPEDDATA_DATA(procval);

    VM_ASSERT(VM_EP_IN_HEAP_P(GET_THREAD(), captured->ep));

    /* copy block */
    RB_OBJ_WRITE(procval, &proc->block.as.captured.self, captured->self);
    RB_OBJ_WRITE(procval, &proc->block.as.captured.code.val, captured->code.val);
    *((const VALUE **)&proc->block.as.captured.ep) = captured->ep;
    RB_OBJ_WRITTEN(procval, Qundef, VM_ENV_ENVVAL(captured->ep));

    vm_block_type_set(&proc->block, block_type);
    proc->safe_level = safe_level;
    proc->is_from_method = is_from_method;
    proc->is_lambda = is_lambda;

    return procval;
}

VALUE
rb_proc_create(VALUE klass, const struct rb_block *block,
	       int8_t safe_level, int8_t is_from_method, int8_t is_lambda)
{
    VALUE procval = rb_proc_alloc(klass);
    rb_proc_t *proc = RTYPEDDATA_DATA(procval);

    VM_ASSERT(VM_EP_IN_HEAP_P(GET_THREAD(), vm_block_ep(block)));

    /* copy block */
    switch (vm_block_type(block)) {
      case block_type_iseq:
      case block_type_ifunc:
	RB_OBJ_WRITE(procval, &proc->block.as.captured.self, block->as.captured.self);
	RB_OBJ_WRITE(procval, &proc->block.as.captured.code.val, block->as.captured.code.val);
	*((const VALUE **)&proc->block.as.captured.ep) = block->as.captured.ep;
	RB_OBJ_WRITTEN(procval, Qundef, VM_ENV_ENVVAL(block->as.captured.ep));
	break;
      case block_type_symbol:
	RB_OBJ_WRITE(procval, &proc->block.as.symbol, block->as.symbol);
	break;
      case block_type_proc:
	RB_OBJ_WRITE(procval, &proc->block.as.proc, block->as.proc);
	break;
    }
    vm_block_type_set(&proc->block, block->type);
    proc->safe_level = safe_level;
    proc->is_from_method = is_from_method;
    proc->is_lambda = is_lambda;

    return procval;
}

VALUE
rb_vm_make_proc(rb_thread_t *th, const struct rb_captured_block *captured, VALUE klass)
{
    return rb_vm_make_proc_lambda(th, captured, klass, FALSE);
}

VALUE
rb_vm_make_proc_lambda(rb_thread_t *th, const struct rb_captured_block *captured, VALUE klass, int8_t is_lambda)
{
    VALUE procval;

    if (!VM_ENV_ESCAPED_P(captured->ep)) {
	rb_control_frame_t *cfp = VM_CAPTURED_BLOCK_TO_CFP(captured);
	vm_make_env_object(th, cfp);
    }
    VM_ASSERT(VM_EP_IN_HEAP_P(th, captured->ep));
    VM_ASSERT(RB_TYPE_P(captured->code.val, T_IMEMO));

    procval = rb_proc_create_from_captured(klass, captured,
					   imemo_type(captured->code.val) == imemo_iseq ? block_type_iseq : block_type_ifunc,
					   (int8_t)th->safe_level, FALSE, is_lambda);
    return procval;
}

/* Binding */

VALUE
rb_vm_make_binding(rb_thread_t *th, const rb_control_frame_t *src_cfp)
{
    rb_control_frame_t *cfp = rb_vm_get_binding_creatable_next_cfp(th, src_cfp);
    rb_control_frame_t *ruby_level_cfp = rb_vm_get_ruby_level_next_cfp(th, src_cfp);
    VALUE bindval, envval;
    rb_binding_t *bind;

    if (cfp == 0 || ruby_level_cfp == 0) {
	rb_raise(rb_eRuntimeError, "Can't create Binding Object on top of Fiber.");
    }

    while (1) {
	envval = vm_make_env_object(th, cfp);
	if (cfp == ruby_level_cfp) {
	    break;
	}
	cfp = rb_vm_get_binding_creatable_next_cfp(th, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
    }

    bindval = rb_binding_alloc(rb_cBinding);
    GetBindingPtr(bindval, bind);
    vm_bind_update_env(bind, envval);
    bind->block.as.captured.self = cfp->self;
    bind->block.as.captured.code.iseq = cfp->iseq;
    bind->path = ruby_level_cfp->iseq->body->location.path;
    bind->first_lineno = rb_vm_get_sourceline(ruby_level_cfp);

    return bindval;
}

const VALUE *
rb_binding_add_dynavars(rb_binding_t *bind, int dyncount, const ID *dynvars)
{
    VALUE envval, path = bind->path;
    const struct rb_block *base_block;
    const rb_env_t *env;
    rb_thread_t *th = GET_THREAD();
    const rb_iseq_t *base_iseq, *iseq;
    NODE *node = 0;
    ID minibuf[4], *dyns = minibuf;
    VALUE idtmp = 0;

    if (dyncount < 0) return 0;

    base_block = &bind->block;
    base_iseq = vm_block_iseq(base_block);

    if (dyncount >= numberof(minibuf)) dyns = ALLOCV_N(ID, idtmp, dyncount + 1);

    dyns[0] = dyncount;
    MEMCPY(dyns + 1, dynvars, ID, dyncount);
    node = NEW_NODE(NODE_SCOPE, dyns, 0, 0);

    if (base_iseq) {
	iseq = rb_iseq_new(node, base_iseq->body->location.label, path, path, base_iseq, ISEQ_TYPE_EVAL);
    }
    else {
	VALUE tempstr = rb_fstring_cstr("<temp>");
	iseq = rb_iseq_new_top(node, tempstr, tempstr, tempstr, NULL);
    }
    node->u1.tbl = 0; /* reset table */
    ALLOCV_END(idtmp);

    vm_set_eval_stack(th, iseq, 0, base_block);
    vm_bind_update_env(bind, envval = vm_make_env_object(th, th->cfp));
    rb_vm_pop_frame(th);

    env = (const rb_env_t *)envval;
    return env->env;
}

/* C -> Ruby: block */

static inline VALUE
invoke_block(rb_thread_t *th, const rb_iseq_t *iseq, VALUE self, const struct rb_captured_block *captured, const rb_cref_t *cref, VALUE type, int opt_pc)
{
    int arg_size = iseq->body->param.size;

    vm_push_frame(th, iseq, type | VM_FRAME_FLAG_FINISH, self,
		  VM_GUARDED_PREV_EP(captured->ep),
		  (VALUE)cref, /* cref or method */
		  iseq->body->iseq_encoded + opt_pc,
		  th->cfp->sp + arg_size, iseq->body->local_table_size - arg_size,
		  iseq->body->stack_max);
    return vm_exec(th);
}

static VALUE
invoke_bmethod(rb_thread_t *th, const rb_iseq_t *iseq, VALUE self, const struct rb_captured_block *captured, const rb_callable_method_entry_t *me, VALUE type, int opt_pc)
{
    /* bmethod */
    int arg_size = iseq->body->param.size;
    VALUE ret;

    vm_push_frame(th, iseq, type | VM_FRAME_FLAG_FINISH | VM_FRAME_FLAG_BMETHOD, self,
		  VM_GUARDED_PREV_EP(captured->ep),
		  (VALUE)me,
		  iseq->body->iseq_encoded + opt_pc,
		  th->cfp->sp + arg_size, iseq->body->local_table_size - arg_size,
		  iseq->body->stack_max);

    RUBY_DTRACE_METHOD_ENTRY_HOOK(th, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_CALL, self, me->def->original_id, me->called_id, me->owner, Qnil);
    ret = vm_exec(th);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_RETURN, self, me->def->original_id, me->called_id, me->owner, ret);
    RUBY_DTRACE_METHOD_RETURN_HOOK(th, me->owner, me->def->original_id);
    return ret;
}

static inline VALUE
invoke_iseq_block_from_c(rb_thread_t *th, const struct rb_captured_block *captured,
			 VALUE self, int argc, const VALUE *argv, VALUE passed_block_handler,
			 const rb_cref_t *cref, const int splattable, int is_lambda)
{
    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
    int i, opt_pc;
    VALUE type = is_lambda ? VM_FRAME_MAGIC_LAMBDA : VM_FRAME_MAGIC_BLOCK;
    VALUE *sp = th->cfp->sp;
    const rb_callable_method_entry_t *me = th->passed_bmethod_me;
    th->passed_bmethod_me = NULL;

    for (i=0; i<argc; i++) {
	sp[i] = argv[i];
    }

    opt_pc = vm_yield_setup_args(th, iseq, argc, sp, passed_block_handler,
				 (type == VM_FRAME_MAGIC_LAMBDA ? (splattable ? arg_setup_lambda : arg_setup_method) : arg_setup_block));

    if (me == NULL) {
	return invoke_block(th, iseq, self, captured, cref, type, opt_pc);
    }
    else {
	return invoke_bmethod(th, iseq, self, captured, me, type, opt_pc);
    }
}

static inline VALUE
invoke_block_from_c_splattable(rb_thread_t *th, VALUE block_handler,
			       int argc, const VALUE *argv,
			       VALUE passed_block_handler, const rb_cref_t *cref)
{
    int is_lambda = FALSE;
  again:
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_iseq:
	{
	    const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
	    return invoke_iseq_block_from_c(th, captured, captured->self, argc, argv, passed_block_handler, cref, TRUE, is_lambda);
	}
      case block_handler_type_ifunc:
	return vm_yield_with_cfunc(th, VM_BH_TO_IFUNC_BLOCK(block_handler), VM_BH_TO_IFUNC_BLOCK(block_handler)->self,
				   argc, argv, passed_block_handler);
      case block_handler_type_symbol:
	return vm_yield_with_symbol(th, VM_BH_TO_SYMBOL(block_handler), argc, argv, passed_block_handler);
      case block_handler_type_proc:
	is_lambda = block_proc_is_lambda(VM_BH_TO_PROC(block_handler));
	block_handler = vm_proc_to_block_handler(VM_BH_TO_PROC(block_handler));
	goto again;
    }
    VM_UNREACHABLE(invoke_block_from_c_splattable);
    return Qundef;
}

static inline VALUE
check_block_handler(rb_thread_t *th)
{
    VALUE block_handler = VM_CF_BLOCK_HANDLER(th->cfp);
    VM_ASSERT(vm_block_handler_verify(block_handler));
    if (UNLIKELY(block_handler == VM_BLOCK_HANDLER_NONE)) {
	rb_vm_localjump_error("no block given", Qnil, 0);
    }

    return block_handler;
}

static VALUE
vm_yield_with_cref(rb_thread_t *th, int argc, const VALUE *argv, const rb_cref_t *cref)
{
    return invoke_block_from_c_splattable(th, check_block_handler(th), argc, argv, VM_BLOCK_HANDLER_NONE, cref);
}

static VALUE
vm_yield(rb_thread_t *th, int argc, const VALUE *argv)
{
    return invoke_block_from_c_splattable(th, check_block_handler(th), argc, argv, VM_BLOCK_HANDLER_NONE, NULL);
}

static VALUE
vm_yield_with_block(rb_thread_t *th, int argc, const VALUE *argv, VALUE block_handler)
{
    return invoke_block_from_c_splattable(th, check_block_handler(th), argc, argv, block_handler, NULL);
}

static inline VALUE
invoke_block_from_c_unsplattable(rb_thread_t *th, const struct rb_block *block,
				 VALUE self, int argc, const VALUE *argv,
				 VALUE passed_block_handler, int is_lambda)
{
  again:
    switch (vm_block_type(block)) {
      case block_type_iseq:
	return invoke_iseq_block_from_c(th, &block->as.captured, self, argc, argv, passed_block_handler, NULL, FALSE, is_lambda);
      case block_type_ifunc:
	return vm_yield_with_cfunc(th, &block->as.captured, self, argc, argv, passed_block_handler);
      case block_type_symbol:
	return vm_yield_with_symbol(th, block->as.symbol, argc, argv, passed_block_handler);
      case block_type_proc:
	is_lambda = block_proc_is_lambda(block->as.proc);
	block = vm_proc_block(block->as.proc);
	goto again;
    }
    VM_UNREACHABLE(invoke_block_from_c_unsplattable);
    return Qundef;
}

static VALUE
vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc, VALUE self,
	       int argc, const VALUE *argv, VALUE passed_block_handler)
{
    VALUE val = Qundef;
    int state;
    volatile int stored_safe = th->safe_level;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	th->safe_level = proc->safe_level;
	val = invoke_block_from_c_unsplattable(th, &proc->block, self, argc, argv, passed_block_handler, proc->is_lambda);
    }
    TH_POP_TAG();

    th->safe_level = stored_safe;

    if (state) {
	TH_JUMP_TAG(th, state);
    }
    return val;
}

static VALUE
vm_invoke_bmethod(rb_thread_t *th, rb_proc_t *proc, VALUE self,
		  int argc, const VALUE *argv, VALUE block_handler)
{
    return invoke_block_from_c_unsplattable(th, &proc->block, self, argc, argv, block_handler, TRUE);
}

VALUE
rb_vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
		  int argc, const VALUE *argv, VALUE passed_block_handler)
{
    VALUE self = vm_block_self(&proc->block);
    VM_ASSERT(vm_block_handler_verify(passed_block_handler));

    if (proc->is_from_method) {
	return vm_invoke_bmethod(th, proc, self, argc, argv, passed_block_handler);
    }
    else {
	return vm_invoke_proc(th, proc, self, argc, argv, passed_block_handler);
    }
}

/* special variable */

static rb_control_frame_t *
vm_normal_frame(rb_thread_t *th, rb_control_frame_t *cfp)
{
    while (cfp->pc == 0) {
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	    return 0;
	}
    }
    return cfp;
}

static VALUE
vm_cfp_svar_get(rb_thread_t *th, rb_control_frame_t *cfp, VALUE key)
{
    cfp = vm_normal_frame(th, cfp);
    return lep_svar_get(th, cfp ? VM_CF_LEP(cfp) : 0, key);
}

static void
vm_cfp_svar_set(rb_thread_t *th, rb_control_frame_t *cfp, VALUE key, const VALUE val)
{
    cfp = vm_normal_frame(th, cfp);
    lep_svar_set(th, cfp ? VM_CF_LEP(cfp) : 0, key, val);
}

static VALUE
vm_svar_get(VALUE key)
{
    rb_thread_t *th = GET_THREAD();
    return vm_cfp_svar_get(th, th->cfp, key);
}

static void
vm_svar_set(VALUE key, VALUE val)
{
    rb_thread_t *th = GET_THREAD();
    vm_cfp_svar_set(th, th->cfp, key, val);
}

VALUE
rb_backref_get(void)
{
    return vm_svar_get(VM_SVAR_BACKREF);
}

void
rb_backref_set(VALUE val)
{
    vm_svar_set(VM_SVAR_BACKREF, val);
}

VALUE
rb_lastline_get(void)
{
    return vm_svar_get(VM_SVAR_LASTLINE);
}

void
rb_lastline_set(VALUE val)
{
    vm_svar_set(VM_SVAR_LASTLINE, val);
}

/* misc */

VALUE
rb_sourcefilename(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	return cfp->iseq->body->location.path;
    }
    else {
	return Qnil;
    }
}

const char *
rb_sourcefile(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	return RSTRING_PTR(cfp->iseq->body->location.path);
    }
    else {
	return 0;
    }
}

int
rb_sourceline(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

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
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	if (pline) *pline = rb_vm_get_sourceline(cfp);
	return cfp->iseq->body->location.path;
    }
    else {
	if (pline) *pline = 0;
	return 0;
    }
}

const char *
rb_source_loc(int *pline)
{
    VALUE path = rb_source_location(pline);
    if (!path) return 0;
    return RSTRING_PTR(path);
}

rb_cref_t *
rb_vm_cref(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp == NULL) {
	return NULL;
    }

    return rb_vm_get_cref(cfp->ep);
}

rb_cref_t *
rb_vm_cref_replace_with_duplicated_cref(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);
    rb_cref_t *cref = vm_cref_replace_with_duplicated_cref(cfp->ep);
    return cref;
}

const rb_cref_t *
rb_vm_cref_in_context(VALUE self, VALUE cbase)
{
    rb_thread_t *th = GET_THREAD();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);
    const rb_cref_t *cref;
    if (cfp->self != self) return NULL;
    if (!vm_env_cref_by_cref(cfp->ep)) return NULL;
    cref = rb_vm_get_cref(cfp->ep);
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
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

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

void
rb_vm_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc = make_localjump_error(mesg, value, reason);
    rb_exc_raise(exc);
}

VALUE
rb_vm_make_jump_tag_but_local_jump(int state, VALUE val)
{
    VALUE result = Qnil;

    if (val == Qundef) {
	val = GET_THREAD()->tag->retval;
    }
    switch (state) {
      case 0:
	break;
      case TAG_RETURN:
	result = make_localjump_error("unexpected return", val, state);
	break;
      case TAG_BREAK:
	result = make_localjump_error("unexpected break", val, state);
	break;
      case TAG_NEXT:
	result = make_localjump_error("unexpected next", val, state);
	break;
      case TAG_REDO:
	result = make_localjump_error("unexpected redo", Qnil, state);
	break;
      case TAG_RETRY:
	result = make_localjump_error("retry outside of rescue clause", Qnil, state);
	break;
      default:
	break;
    }
    return result;
}

void
rb_vm_jump_tag_but_local_jump(int state)
{
    VALUE exc = rb_vm_make_jump_tag_but_local_jump(state, Qundef);
    if (!NIL_P(exc)) rb_exc_raise(exc);
    JUMP_TAG(state);
}

NORETURN(static void vm_iter_break(rb_thread_t *th, VALUE val));

static rb_control_frame_t *
next_not_local_frame(rb_control_frame_t *cfp)
{
    while (VM_ENV_LOCAL_P(cfp->ep)) {
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return cfp;
}

static void
vm_iter_break(rb_thread_t *th, VALUE val)
{
    rb_control_frame_t *cfp = next_not_local_frame(th->cfp);
    const VALUE *ep = VM_CF_PREV_EP(cfp);
    const rb_control_frame_t *target_cfp = rb_vm_search_cf_from_ep(th, cfp, ep);

#if 0				/* raise LocalJumpError */
    if (!target_cfp) {
	rb_vm_localjump_error("unexpected break", val, TAG_BREAK);
    }
#endif

    th->state = TAG_BREAK;
    th->errinfo = (VALUE)THROW_DATA_NEW(val, target_cfp, TAG_BREAK);
    TH_JUMP_TAG(th, TAG_BREAK);
}

void
rb_iter_break(void)
{
    vm_iter_break(GET_THREAD(), Qnil);
}

void
rb_iter_break_value(VALUE val)
{
    vm_iter_break(GET_THREAD(), val);
}

/* optimization: redefine management */

static st_table *vm_opt_method_table = 0;

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
    return 0;
}

static void
rb_vm_check_redefinition_opt_method(const rb_method_entry_t *me, VALUE klass)
{
    st_data_t bop;
    if (RB_TYPE_P(klass, T_ICLASS) && FL_TEST(klass, RICLASS_IS_ORIGIN)) {
       klass = RBASIC_CLASS(klass);
    }
    if (me->def->type == VM_METHOD_TYPE_CFUNC) {
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

    if (me && me->def->type == VM_METHOD_TYPE_CFUNC) {
	st_insert(vm_opt_method_table, (st_data_t)me, (st_data_t)bop);
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

#define OP(mid_, bop_) (mid = id##mid_, bop = BOP_##bop_, ruby_vm_redefined_flag[bop] = 0)
#define C(k) add_opt_method(rb_c##k, mid, bop)
    OP(PLUS, PLUS), (C(Integer), C(Float), C(String), C(Array));
    OP(MINUS, MINUS), (C(Integer), C(Float));
    OP(MULT, MULT), (C(Integer), C(Float));
    OP(DIV, DIV), (C(Integer), C(Float));
    OP(MOD, MOD), (C(Integer), C(Float));
    OP(Eq, EQ), (C(Integer), C(Float), C(String));
    OP(Eqq, EQQ), (C(Integer), C(Float), C(Symbol), C(String),
		   C(NilClass), C(TrueClass), C(FalseClass));
    OP(LT, LT), (C(Integer), C(Float));
    OP(LE, LE), (C(Integer), C(Float));
    OP(GT, GT), (C(Integer), C(Float));
    OP(GE, GE), (C(Integer), C(Float));
    OP(LTLT, LTLT), (C(String), C(Array));
    OP(AREF, AREF), (C(Array), C(Hash));
    OP(ASET, ASET), (C(Array), C(Hash));
    OP(Length, LENGTH), (C(Array), C(String), C(Hash));
    OP(Size, SIZE), (C(Array), C(String), C(Hash));
    OP(EmptyP, EMPTY_P), (C(Array), C(String), C(Hash));
    OP(Succ, SUCC), (C(Integer), C(String), C(Time));
    OP(EqTilde, MATCH), (C(Regexp), C(String));
    OP(Freeze, FREEZE), (C(String));
    OP(Max, MAX), (C(Array));
    OP(Min, MIN), (C(Array));
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
      case VM_FRAME_MAGIC_PROC:   return "proc";
      case VM_FRAME_MAGIC_IFUNC:  return "ifunc";
      case VM_FRAME_MAGIC_EVAL:   return "eval";
      case VM_FRAME_MAGIC_LAMBDA: return "lambda";
      case VM_FRAME_MAGIC_RESCUE: return "rescue";
      default:
	rb_bug("unknown frame");
    }
}
#endif

static void
hook_before_rewind(rb_thread_t *th, rb_control_frame_t *cfp, int will_finish_vm_exec)
{
    switch (VM_FRAME_TYPE(th->cfp)) {
      case VM_FRAME_MAGIC_METHOD:
	RUBY_DTRACE_METHOD_RETURN_HOOK(th, 0, 0);
	EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_RETURN, th->cfp->self, 0, 0, 0, Qnil);
	break;
      case VM_FRAME_MAGIC_BLOCK:
      case VM_FRAME_MAGIC_LAMBDA:
	if (VM_FRAME_BMETHOD_P(th->cfp)) {
	    EXEC_EVENT_HOOK(th, RUBY_EVENT_B_RETURN, th->cfp->self, 0, 0, 0, Qnil);

	    if (!will_finish_vm_exec) {
		/* kick RUBY_EVENT_RETURN at invoke_block_from_c() for bmethod */
		EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_RETURN, th->cfp->self,
					      rb_vm_frame_method_entry(th->cfp)->def->original_id,
					      rb_vm_frame_method_entry(th->cfp)->called_id,
					      rb_vm_frame_method_entry(th->cfp)->owner, Qnil);
	    }
	}
	else {
	    EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_B_RETURN, th->cfp->self, 0, 0, 0, Qnil);
	}
	break;
      case VM_FRAME_MAGIC_CLASS:
	EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_END, th->cfp->self, 0, 0, 0, Qnil);
	break;
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
    const void *block_code;     // cfp[5], blcok code
  };

  struct rb_captured_blcok {
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
 */

static VALUE
vm_exec(rb_thread_t *th)
{
    int state;
    VALUE result;
    VALUE initial = 0;
    struct vm_throw_data *err;

    TH_PUSH_TAG(th);
    _tag.retval = Qnil;
    if ((state = EXEC_TAG()) == 0) {
      vm_loop_start:
	result = vm_exec_core(th, initial);
	if ((state = th->state) != 0) {
	    err = (struct vm_throw_data *)result;
	    th->state = 0;
	    goto exception_handler;
	}
    }
    else {
	unsigned int i;
	const struct iseq_catch_table_entry *entry;
	const struct iseq_catch_table *ct;
	unsigned long epc, cont_pc, cont_sp;
	const rb_iseq_t *catch_iseq;
	rb_control_frame_t *cfp;
	VALUE type;
	const rb_control_frame_t *escape_cfp;

	err = (struct vm_throw_data *)th->errinfo;

      exception_handler:
	cont_pc = cont_sp = 0;
	catch_iseq = NULL;

	while (th->cfp->pc == 0 || th->cfp->iseq == 0) {
	    if (UNLIKELY(VM_FRAME_TYPE(th->cfp) == VM_FRAME_MAGIC_CFUNC)) {
		EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, th->cfp->self,
				rb_vm_frame_method_entry(th->cfp)->def->original_id,
				rb_vm_frame_method_entry(th->cfp)->called_id,
				rb_vm_frame_method_entry(th->cfp)->owner, Qnil);
		RUBY_DTRACE_CMETHOD_RETURN_HOOK(th,
					       rb_vm_frame_method_entry(th->cfp)->owner,
					       rb_vm_frame_method_entry(th->cfp)->def->original_id);
	    }
	    rb_vm_pop_frame(th);
	}

	cfp = th->cfp;
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
			    entry = &ct->entries[i];
			    if (entry->start < epc && entry->end >= epc) {
				if (entry->type == CATCH_TYPE_ENSURE) {
				    catch_iseq = entry->iseq;
				    cont_pc = entry->cont;
				    cont_sp = entry->sp;
				    break;
				}
			    }
			}
			if (!catch_iseq) {
			    th->errinfo = Qnil;
			    result = THROW_DATA_VAL(err);
			    hook_before_rewind(th, th->cfp, TRUE);
			    rb_vm_pop_frame(th);
			    goto finish_vme;
			}
		    }
		    /* through */
		}
		else {
		    /* TAG_BREAK */
#if OPT_STACK_CACHING
		    initial = THROW_DATA_VAL(err);
#else
		    *th->cfp->sp++ = THROW_DATA_VAL(err);
#endif
		    th->errinfo = Qnil;
		    goto vm_loop_start;
		}
	    }
	}

	if (state == TAG_RAISE) {
	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = &ct->entries[i];
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
		entry = &ct->entries[i];
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
			    th->errinfo = Qnil;
			    goto vm_loop_start;
			}
		    }
		}
	    }
	}
	else if (state == TAG_BREAK && !escape_cfp) {
	    type = CATCH_TYPE_BREAK;

	  search_restart_point:
	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = &ct->entries[i];

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
			    initial = THROW_DATA_VAL(err);
#else
			    *th->cfp->sp++ = THROW_DATA_VAL(err);
#endif
			}
			th->errinfo = Qnil;
			th->state = 0;
			goto vm_loop_start;
		    }
		}
	    }
	}
	else if (state == TAG_REDO) {
	    type = CATCH_TYPE_REDO;
	    goto search_restart_point;
	}
	else if (state == TAG_NEXT) {
	    type = CATCH_TYPE_NEXT;
	    goto search_restart_point;
	}
	else {
	    ct = cfp->iseq->body->catch_table;
	    if (ct) for (i = 0; i < ct->size; i++) {
		entry = &ct->entries[i];
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
	    vm_push_frame(th, catch_iseq, VM_FRAME_MAGIC_RESCUE,
			  cfp->self,
			  VM_GUARDED_PREV_EP(cfp->ep),
			  0, /* cref or me */
			  catch_iseq->body->iseq_encoded,
			  cfp->sp + arg_size /* push value */,
			  catch_iseq->body->local_table_size - arg_size,
			  catch_iseq->body->stack_max);

	    state = 0;
	    th->state = 0;
	    th->errinfo = Qnil;
	    goto vm_loop_start;
	}
	else {
	    /* skip frame */
	    hook_before_rewind(th, th->cfp, FALSE);

	    if (VM_FRAME_FINISHED_P(th->cfp)) {
		rb_vm_pop_frame(th);
		th->errinfo = (VALUE)err;
		TH_TMPPOP_TAG();
		TH_JUMP_TAG(th, state);
	    }
	    else {
		rb_vm_pop_frame(th);
		goto exception_handler;
	    }
	}
    }
  finish_vme:
    TH_POP_TAG();
    return result;
}

/* misc */

VALUE
rb_iseq_eval(const rb_iseq_t *iseq)
{
    rb_thread_t *th = GET_THREAD();
    VALUE val;
    vm_set_top_stack(th, iseq);
    val = vm_exec(th);
    return val;
}

VALUE
rb_iseq_eval_main(const rb_iseq_t *iseq)
{
    rb_thread_t *th = GET_THREAD();
    VALUE val;

    vm_set_main_stack(th, iseq);
    val = vm_exec(th);
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
rb_thread_method_id_and_class(rb_thread_t *th, ID *idp, ID *called_idp, VALUE *klassp)
{
    return rb_vm_control_frame_id_and_class(th->cfp, idp, called_idp, klassp);
}

int
rb_frame_method_id_and_class(ID *idp, VALUE *klassp)
{
    return rb_thread_method_id_and_class(GET_THREAD(), idp, 0, klassp);
}

VALUE
rb_thread_current_status(const rb_thread_t *th)
{
    const rb_control_frame_t *cfp = th->cfp;
    const rb_callable_method_entry_t *me;
    VALUE str = Qnil;

    if (cfp->iseq != 0) {
	if (cfp->pc != 0) {
	    const rb_iseq_t *iseq = cfp->iseq;
	    int line_no = rb_vm_get_sourceline(cfp);
	    str = rb_sprintf("%"PRIsVALUE":%d:in `%"PRIsVALUE"'",
			     iseq->body->location.path, line_no, iseq->body->location.label);
	}
    }
    else if ((me = rb_vm_frame_method_entry(cfp)) && me->def->original_id) {
	str = rb_sprintf("`%"PRIsVALUE"#%"PRIsVALUE"' (cfunc)",
			 rb_class_path(me->owner),
			 rb_id2str(me->def->original_id));
    }

    return str;
}

VALUE
rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg,
		 VALUE block_handler, VALUE filename)
{
    rb_thread_t *th = GET_THREAD();
    const rb_control_frame_t *reg_cfp = th->cfp;
    const rb_iseq_t *iseq = rb_iseq_new(0, filename, filename, Qnil, 0, ISEQ_TYPE_TOP);
    VALUE val;

    vm_push_frame(th, iseq, VM_FRAME_MAGIC_TOP | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH,
		  recv, block_handler,
		  (VALUE)vm_cref_new_toplevel(th), /* cref or me */
		  0, reg_cfp->sp, 0, 0);

    val = (*func)(arg);

    rb_vm_pop_frame(th);
    return val;
}

/* vm */

void rb_vm_trace_mark_event_hooks(rb_hook_list_t *hooks);

void
rb_vm_mark(void *ptr)
{
    int i;

    RUBY_MARK_ENTER("vm");
    RUBY_GC_INFO("-------------------------------------------------\n");
    if (ptr) {
	rb_vm_t *vm = ptr;
	rb_thread_t *th = 0;

	list_for_each(&vm->living_threads, th, vmlt_node) {
	    rb_gc_mark(th->self);
	}
	rb_gc_mark(vm->thgroup_default);
	rb_gc_mark(vm->mark_object_ary);
	rb_gc_mark(vm->load_path);
	rb_gc_mark(vm->load_path_snapshot);
	RUBY_MARK_UNLESS_NULL(vm->load_path_check_cache);
	rb_gc_mark(vm->expanded_load_path);
	rb_gc_mark(vm->loaded_features);
	rb_gc_mark(vm->loaded_features_snapshot);
	rb_gc_mark(vm->top_self);
	RUBY_MARK_UNLESS_NULL(vm->coverages);
	rb_gc_mark(vm->defined_module_hash);

	if (vm->loading_table) {
	    rb_mark_tbl(vm->loading_table);
	}

	rb_vm_trace_mark_event_hooks(&vm->event_hooks);

	for (i = 0; i < RUBY_NSIG; i++) {
	    if (vm->trap_list[i].cmd)
		rb_gc_mark(vm->trap_list[i].cmd);
	}
    }

    RUBY_MARK_LEAVE("vm");
}

void
rb_vm_register_special_exception(enum ruby_special_exceptions sp, VALUE cls, const char *mesg)
{
    rb_vm_t *vm = GET_VM();
    VALUE exc = rb_exc_new3(cls, rb_obj_freeze(rb_str_new2(mesg)));
    OBJ_TAINT(exc);
    OBJ_FREEZE(exc);
    ((VALUE *)vm->special_exceptions)[sp] = exc;
    rb_gc_register_mark_object(exc);
}

int
rb_vm_add_root_module(ID id, VALUE module)
{
    rb_vm_t *vm = GET_VM();

    rb_hash_aset(vm->defined_module_hash, ID2SYM(id), module);

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
	rb_thread_t *th = vm->main_thread;
	struct rb_objspace *objspace = vm->objspace;
	vm->main_thread = 0;
	if (th) {
	    rb_fiber_reset_root_local_storage(th->self);
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
	rb_vm_gvl_destroy(vm);
	if (objspace) {
	    rb_objspace_free(objspace);
	}
	/* after freeing objspace, you *can't* use ruby_xfree() */
	ruby_mimfree(vm);
	ruby_current_vm = 0;
    }
    RUBY_FREE_LEAVE("vm");
    return 0;
}

static size_t
vm_memsize(const void *ptr)
{
    const rb_vm_t *vmobj = ptr;
    size_t size = sizeof(rb_vm_t);

    size += vmobj->living_thread_num * sizeof(rb_thread_t);

    if (vmobj->defined_strings) {
	size += DEFINED_EXPR * sizeof(VALUE);
    }
    return size;
}

static const rb_data_type_t vm_data_type = {
    "VM",
    {NULL, NULL, vm_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};


static VALUE
vm_default_params(void)
{
    rb_vm_t *vm = GET_VM();
    VALUE result = rb_hash_new();
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
    vm->src_encoding_index = -1;

    vm_default_params_setup(vm);
}

/* Thread */

#define USE_THREAD_DATA_RECYCLE 1

#if USE_THREAD_DATA_RECYCLE
#define RECYCLE_MAX 64
static VALUE *thread_recycle_stack_slot[RECYCLE_MAX];
static int thread_recycle_stack_count = 0;

static VALUE *
thread_recycle_stack(size_t size)
{
    if (thread_recycle_stack_count) {
	/* TODO: check stack size if stack sizes are variable */
	return thread_recycle_stack_slot[--thread_recycle_stack_count];
    }
    else {
	return ALLOC_N(VALUE, size);
    }
}

#else
#define thread_recycle_stack(size) ALLOC_N(VALUE, (size))
#endif

void
rb_thread_recycle_stack_release(VALUE *stack)
{
#if USE_THREAD_DATA_RECYCLE
    if (thread_recycle_stack_count < RECYCLE_MAX) {
	thread_recycle_stack_slot[thread_recycle_stack_count++] = stack;
	return;
    }
#endif
    ruby_xfree(stack);
}

void rb_fiber_mark_self(rb_fiber_t *fib);

void
rb_thread_mark(void *ptr)
{
    rb_thread_t *th = ptr;
    RUBY_MARK_ENTER("thread");

    if (th->stack) {
	VALUE *p = th->stack;
	VALUE *sp = th->cfp->sp;
	rb_control_frame_t *cfp = th->cfp;
	rb_control_frame_t *limit_cfp = (void *)(th->stack + th->stack_size);

	rb_gc_mark_values((long)(sp - p), p);

	while (cfp != limit_cfp) {
#if VM_CHECK_MODE > 0
	    const VALUE *ep = cfp->ep;
	    VM_ASSERT(!!VM_ENV_FLAGS(ep, VM_ENV_FLAG_ESCAPED) == vm_ep_in_heap_p_(th, ep));
#endif
	    rb_gc_mark(cfp->self);
	    rb_gc_mark((VALUE)cfp->iseq);
	    rb_gc_mark((VALUE)cfp->block_code);

	    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	}
    }

    /* mark ruby objects */
    RUBY_MARK_UNLESS_NULL(th->first_proc);
    if (th->first_proc) RUBY_MARK_UNLESS_NULL(th->first_args);

    RUBY_MARK_UNLESS_NULL(th->thgroup);
    RUBY_MARK_UNLESS_NULL(th->value);
    RUBY_MARK_UNLESS_NULL(th->errinfo);
    RUBY_MARK_UNLESS_NULL(th->pending_interrupt_queue);
    RUBY_MARK_UNLESS_NULL(th->pending_interrupt_mask_stack);
    RUBY_MARK_UNLESS_NULL(th->root_svar);
    RUBY_MARK_UNLESS_NULL(th->top_self);
    RUBY_MARK_UNLESS_NULL(th->top_wrapper);
    rb_fiber_mark_self(th->fiber);
    rb_fiber_mark_self(th->root_fiber);
    RUBY_MARK_UNLESS_NULL(th->stat_insn_usage);
    RUBY_MARK_UNLESS_NULL(th->last_status);

    RUBY_MARK_UNLESS_NULL(th->locking_mutex);

    rb_mark_tbl(th->local_storage);
    RUBY_MARK_UNLESS_NULL(th->local_storage_recursive_hash);
    RUBY_MARK_UNLESS_NULL(th->local_storage_recursive_hash_for_trace);

    if (GET_THREAD() != th && th->machine.stack_start && th->machine.stack_end) {
	rb_gc_mark_machine_stack(th);
	rb_gc_mark_locations((VALUE *)&th->machine.regs,
			     (VALUE *)(&th->machine.regs) +
			     sizeof(th->machine.regs) / sizeof(VALUE));
    }

    RUBY_MARK_UNLESS_NULL(th->name);

    rb_vm_trace_mark_event_hooks(&th->event_hooks);

    RUBY_MARK_LEAVE("thread");
}

static void
thread_free(void *ptr)
{
    rb_thread_t *th;
    RUBY_FREE_ENTER("thread");

    if (ptr) {
	th = ptr;

	if (!th->root_fiber) {
	    RUBY_FREE_UNLESS_NULL(th->stack);
	}

	if (th->locking_mutex != Qfalse) {
	    rb_bug("thread_free: locking_mutex must be NULL (%p:%p)", (void *)th, (void *)th->locking_mutex);
	}
	if (th->keeping_mutexes != NULL) {
	    rb_bug("thread_free: keeping_mutexes must be NULL (%p:%p)", (void *)th, (void *)th->keeping_mutexes);
	}

	if (th->local_storage) {
	    st_free_table(th->local_storage);
	}

	if (th->vm && th->vm->main_thread == th) {
	    RUBY_GC_INFO("main thread\n");
	}
	else {
#ifdef USE_SIGALTSTACK
	    if (th->altstack) {
		free(th->altstack);
	    }
#endif
	    ruby_xfree(ptr);
	}
        if (ruby_current_thread == th)
            ruby_current_thread = NULL;
    }
    RUBY_FREE_LEAVE("thread");
}

static size_t
thread_memsize(const void *ptr)
{
    const rb_thread_t *th = ptr;
    size_t size = sizeof(rb_thread_t);

    if (!th->root_fiber) {
	size += th->stack_size * sizeof(VALUE);
    }
    if (th->local_storage) {
	size += st_memsize(th->local_storage);
    }
    return size;
}

#define thread_data_type ruby_threadptr_data_type
const rb_data_type_t ruby_threadptr_data_type = {
    "VM/thread",
    {
	rb_thread_mark,
	thread_free,
	thread_memsize,
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

static void
th_init(rb_thread_t *th, VALUE self)
{
    th->self = self;

    /* allocate thread stack */
#ifdef USE_SIGALTSTACK
    /* altstack of main thread is reallocated in another place */
    th->altstack = malloc(rb_sigaltstack_size());
#endif
    /* th->stack_size is word number.
     * th->vm->default_params.thread_vm_stack_size is byte size.
     */
    th->stack_size = th->vm->default_params.thread_vm_stack_size / sizeof(VALUE);
    th->stack = thread_recycle_stack(th->stack_size);

    th->cfp = (void *)(th->stack + th->stack_size);

    vm_push_frame(th, 0 /* dummy iseq */, VM_FRAME_MAGIC_DUMMY | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH | VM_FRAME_FLAG_CFRAME /* dummy frame */,
		  Qnil /* dummy self */, VM_BLOCK_HANDLER_NONE /* dummy block ptr */,
		  0 /* dummy cref/me */,
		  0 /* dummy pc */, th->stack, 0, 0);

    th->status = THREAD_RUNNABLE;
    th->errinfo = Qnil;
    th->last_status = Qnil;
    th->waiting_fd = -1;
    th->root_svar = Qfalse;
    th->local_storage_recursive_hash = Qnil;
    th->local_storage_recursive_hash_for_trace = Qnil;
#ifdef NON_SCALAR_THREAD_ID
    th->thread_id_string[0] = '\0';
#endif

#if OPT_CALL_THREADED_CODE
    th->retval = Qundef;
#endif
    th->name = Qnil;
}

static VALUE
ruby_thread_init(VALUE self)
{
    rb_thread_t *th;
    rb_vm_t *vm = GET_THREAD()->vm;
    GetThreadPtr(self, th);

    th->vm = vm;
    th_init(th, self);
    rb_ivar_set(self, rb_intern("locals"), rb_hash_new());

    th->top_wrapper = 0;
    th->top_self = rb_vm_top_self();
    th->root_svar = Qfalse;
    return self;
}

VALUE
rb_thread_alloc(VALUE klass)
{
    VALUE self = thread_alloc(klass);
    ruby_thread_init(self);
    return self;
}

static void
vm_define_method(rb_thread_t *th, VALUE obj, ID id, VALUE iseqval, int is_singleton)
{
    VALUE klass;
    rb_method_visibility_t visi;
    rb_cref_t *cref = rb_vm_cref();

    if (!is_singleton) {
	klass = CREF_CLASS(cref);
	visi = rb_scope_visibility_get();
    }
    else { /* singleton */
	klass = rb_singleton_class(obj); /* class and frozen checked in this API */
	visi = METHOD_VISI_PUBLIC;
    }

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class/module to add method");
    }

    rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, visi);

    if (!is_singleton && rb_scope_module_func_check()) {
	klass = rb_singleton_class(klass);
	rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, METHOD_VISI_PUBLIC);
    }
}

#define REWIND_CFP(expr) do { \
    rb_thread_t *th__ = GET_THREAD(); \
    VALUE *const curr_sp = (th__->cfp++)->sp; \
    VALUE *const saved_sp = th__->cfp->sp; \
    th__->cfp->sp = curr_sp; \
    expr; \
    (th__->cfp--)->sp = saved_sp; \
} while (0)

static VALUE
m_core_define_method(VALUE self, VALUE sym, VALUE iseqval)
{
    REWIND_CFP({
	vm_define_method(GET_THREAD(), Qnil, SYM2ID(sym), iseqval, FALSE);
    });
    return sym;
}

static VALUE
m_core_define_singleton_method(VALUE self, VALUE cbase, VALUE sym, VALUE iseqval)
{
    REWIND_CFP({
	vm_define_method(GET_THREAD(), cbase, SYM2ID(sym), iseqval, TRUE);
    });
    return sym;
}

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
	rb_undef(cbase, SYM2ID(sym));
	rb_clear_method_cache_by_class(self);
    });
    return Qnil;
}

static VALUE
m_core_set_postexe(VALUE self)
{
    rb_set_end_proc(rb_call_end_proc, rb_block_proc());
    return Qnil;
}

static VALUE core_hash_merge_ary(VALUE hash, VALUE ary);
static VALUE core_hash_from_ary(VALUE ary);
static VALUE core_hash_merge_kwd(int argc, VALUE *argv);

static VALUE
core_hash_merge(VALUE hash, long argc, const VALUE *argv)
{
    long i;

    Check_Type(hash, T_HASH);
    VM_ASSERT(argc % 2 == 0);
    for (i=0; i<argc; i+=2) {
	rb_hash_aset(hash, argv[i], argv[i+1]);
    }
    return hash;
}

static VALUE
m_core_hash_from_ary(VALUE self, VALUE ary)
{
    VALUE hash;
    REWIND_CFP(hash = core_hash_from_ary(ary));
    return hash;
}

static VALUE
core_hash_from_ary(VALUE ary)
{
    VALUE hash = rb_hash_new();

    RUBY_DTRACE_CREATE_HOOK(HASH, (Check_Type(ary, T_ARRAY), RARRAY_LEN(ary)));
    return core_hash_merge_ary(hash, ary);
}

#if 0
static VALUE
m_core_hash_merge_ary(VALUE self, VALUE hash, VALUE ary)
{
    REWIND_CFP(core_hash_merge_ary(hash, ary));
    return hash;
}
#endif

static VALUE
core_hash_merge_ary(VALUE hash, VALUE ary)
{
    Check_Type(ary, T_ARRAY);
    core_hash_merge(hash, RARRAY_LEN(ary), RARRAY_CONST_PTR(ary));
    return hash;
}

static VALUE
m_core_hash_merge_ptr(int argc, VALUE *argv, VALUE recv)
{
    VALUE hash = argv[0];

    REWIND_CFP(core_hash_merge(hash, argc-1, argv+1));

    return hash;
}

static int
kwmerge_i(VALUE key, VALUE value, VALUE hash)
{
    Check_Type(key, T_SYMBOL);
    rb_hash_aset(hash, key, value);
    return ST_CONTINUE;
}

static int
kwcheck_i(VALUE key, VALUE value, VALUE hash)
{
    Check_Type(key, T_SYMBOL);
    return ST_CONTINUE;
}

static VALUE
m_core_hash_merge_kwd(int argc, VALUE *argv, VALUE recv)
{
    VALUE hash;
    REWIND_CFP(hash = core_hash_merge_kwd(argc, argv));
    return hash;
}

static VALUE
core_hash_merge_kwd(int argc, VALUE *argv)
{
    VALUE hash, kw;
    rb_check_arity(argc, 1, 2);
    hash = argv[0];
    kw = argv[argc-1];
    kw = rb_convert_type(kw, T_HASH, "Hash", "to_hash");
    if (argc < 2) hash = kw;
    rb_hash_foreach(kw, argc < 2 ? kwcheck_i : kwmerge_i, hash);
    return hash;
}

extern VALUE *rb_gc_stack_start;
extern size_t rb_gc_stack_maxsize;
#ifdef __ia64
extern VALUE *rb_gc_register_stack_start;
#endif

/* debug functions */

/* :nodoc: */
static VALUE
sdr(void)
{
    rb_vm_bugreport(NULL);
    return Qnil;
}

/* :nodoc: */
static VALUE
nsdr(void)
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
static VALUE usage_analysis_insn_stop(VALUE self);
static VALUE usage_analysis_operand_stop(VALUE self);
static VALUE usage_analysis_register_stop(VALUE self);
#endif

void
Init_VM(void)
{
    VALUE opts;
    VALUE klass;
    VALUE fcore;

    /* ::RubyVM */
    rb_cRubyVM = rb_define_class("RubyVM", rb_cObject);
    rb_undef_alloc_func(rb_cRubyVM);
    rb_undef_method(CLASS_OF(rb_cRubyVM), "new");
    rb_define_singleton_method(rb_cRubyVM, "stat", vm_stat, -1);

    /* FrozenCore (hidden) */
    fcore = rb_class_new(rb_cBasicObject);
    RBASIC(fcore)->flags = T_ICLASS;
    klass = rb_singleton_class(fcore);
    rb_define_method_id(klass, id_core_set_method_alias, m_core_set_method_alias, 3);
    rb_define_method_id(klass, id_core_set_variable_alias, m_core_set_variable_alias, 2);
    rb_define_method_id(klass, id_core_undef_method, m_core_undef_method, 2);
    rb_define_method_id(klass, id_core_define_method, m_core_define_method, 2);
    rb_define_method_id(klass, id_core_define_singleton_method, m_core_define_singleton_method, 3);
    rb_define_method_id(klass, id_core_set_postexe, m_core_set_postexe, 0);
    rb_define_method_id(klass, id_core_hash_from_ary, m_core_hash_from_ary, 1);
#if 0
    rb_define_method_id(klass, id_core_hash_merge_ary, m_core_hash_merge_ary, 2);
#endif
    rb_define_method_id(klass, id_core_hash_merge_ptr, m_core_hash_merge_ptr, -1);
    rb_define_method_id(klass, id_core_hash_merge_kwd, m_core_hash_merge_kwd, -1);
    rb_define_method_id(klass, idProc, rb_block_proc, 0);
    rb_define_method_id(klass, idLambda, rb_block_lambda, 0);
    rb_obj_freeze(fcore);
    RBASIC_CLEAR_CLASS(klass);
    rb_obj_freeze(klass);
    rb_gc_register_mark_object(fcore);
    rb_mRubyVMFrozenCore = fcore;

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
     *	    thr = Thread.new { puts "Whats the big deal" }
     *
     *	Then we are able to pause the execution of the main thread and allow
     *	our new thread to finish, using #join:
     *
     *	    thr.join #=> "Whats the big deal"
     *
     *	If we don't call +thr.join+ before the main thread terminates, then all
     *	other threads including +thr+ will be killed.
     *
     *	Alternatively, you can use an array for handling multiple threads at
     *	once, like in the following example:
     *
     *	    threads = []
     *	    threads << Thread.new { puts "Whats the big deal" }
     *	    threads << Thread.new { 3.times { puts "Threads are fun!" } }
     *
     *	After creating a few threads we wait for them all to finish
     *	consecutively.
     *
     *	    threads.each { |thr| thr.join }
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
     *	    thr = Thread.new { ... }
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
     *	Any thread can raise an exception using the #raise instance method,
     *	which operates similarly to Kernel#raise.
     *
     *	However, it's important to note that an exception that occurs in any
     *	thread except the main thread depends on #abort_on_exception. This
     *	option is +false+ by default, meaning that any unhandled exception will
     *	cause the thread to terminate silently when waited on by either #join
     *	or #value. You can change this default by either #abort_on_exception=
     *	+true+ or setting $DEBUG to +true+.
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

    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_INSN_STOP", usage_analysis_insn_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_OPERAND_STOP", usage_analysis_operand_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_REGISTER_STOP", usage_analysis_register_stop, 0);
#endif

    /* ::RubyVM::OPTS, which shows vm build options */
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

    /* ::RubyVM::INSTRUCTION_NAMES */
    rb_define_const(rb_cRubyVM, "INSTRUCTION_NAMES", rb_insns_name_array());

    /* ::RubyVM::DEFAULT_PARAMS
     * This constant variable shows VM's default parameters.
     * Note that changing these values does not affect VM execution.
     * Specification is not stable and you should not depend on this value.
     * Of course, this constant is MRI specific.
     */
    rb_define_const(rb_cRubyVM, "DEFAULT_PARAMS", vm_default_params());

    /* debug functions ::RubyVM::SDR(), ::RubyVM::NSDR() */
#if VMDEBUG
    rb_define_singleton_method(rb_cRubyVM, "SDR", sdr, 0);
    rb_define_singleton_method(rb_cRubyVM, "NSDR", nsdr, 0);
#else
    (void)sdr;
    (void)nsdr;
#endif

    /* VM bootstrap: phase 2 */
    {
	rb_vm_t *vm = ruby_current_vm;
	rb_thread_t *th = GET_THREAD();
	VALUE filename = rb_fstring_cstr("<main>");
	const rb_iseq_t *iseq = rb_iseq_new(0, filename, filename, Qnil, 0, ISEQ_TYPE_TOP);
        volatile VALUE th_self;

	/* create vm object */
	vm->self = TypedData_Wrap_Struct(rb_cRubyVM, &vm_data_type, vm);

	/* create main thread */
	th_self = th->self = TypedData_Wrap_Struct(rb_cThread, &thread_data_type, th);
	rb_iv_set(th_self, "locals", rb_hash_new());
	vm->main_thread = th;
	vm->running_thread = th;
	th->vm = vm;
	th->top_wrapper = 0;
	th->top_self = rb_vm_top_self();
	rb_thread_set_current(th);

	rb_vm_living_threads_insert(vm, th);

	rb_gc_register_mark_object((VALUE)iseq);
	th->cfp->iseq = iseq;
	th->cfp->pc = iseq->body->iseq_encoded;
	th->cfp->self = th->top_self;

	VM_ENV_FLAGS_UNSET(th->cfp->ep, VM_FRAME_FLAG_CFRAME);
	VM_STACK_ENV_WRITE(th->cfp->ep, VM_ENV_DATA_INDEX_ME_CREF, (VALUE)vm_cref_new(rb_cObject, METHOD_VISI_PRIVATE, FALSE, NULL, FALSE));

	/*
	 * The Binding of the top level scope
	 */
	rb_define_global_const("TOPLEVEL_BINDING", rb_binding_new());
    }
    vm_init_redefined_flag();

    /* vm_backtrace.c */
    Init_vm_backtrace();
    VM_PROFILE_ATEXIT();
}

void
rb_vm_set_progname(VALUE filename)
{
    rb_thread_t *th = GET_VM()->main_thread;
    rb_control_frame_t *cfp = (void *)(th->stack + th->stack_size);
    --cfp;
    RB_OBJ_WRITE(cfp->iseq, &cfp->iseq->body->location.path, filename);
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
    rb_thread_set_current_raw(th);

    vm_init2(vm);
    vm->objspace = rb_objspace_alloc();
    ruby_current_vm = vm;

    Init_native_thread();
    th->vm = vm;
    th_init(th, 0);
    ruby_thread_init_stack(th);
}

void
Init_vm_objects(void)
{
    rb_vm_t *vm = GET_VM();

    vm->defined_module_hash = rb_hash_new();

    /* initialize mark object array, hash */
    vm->mark_object_ary = rb_ary_tmp_new(128);
    vm->loading_table = st_init_strtable();
    vm->frozen_strings = st_init_table_with_size(&rb_fstring_hash_type, 1000);
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

static VALUE *
ruby_vm_verbose_ptr(rb_vm_t *vm)
{
    return &vm->verbose;
}

static VALUE *
ruby_vm_debug_ptr(rb_vm_t *vm)
{
    return &vm->debug;
}

VALUE *
rb_ruby_verbose_ptr(void)
{
    return ruby_vm_verbose_ptr(GET_VM());
}

VALUE *
rb_ruby_debug_ptr(void)
{
    return ruby_vm_debug_ptr(GET_VM());
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
    valstr = rb_insn_operand_intern(GET_THREAD()->cfp->iseq, insn, n, op, 0, 0, 0, 0);

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

void (*ruby_vm_collect_usage_func_insn)(int insn) = vm_analysis_insn;
void (*ruby_vm_collect_usage_func_operand)(int insn, int n, VALUE op) = vm_analysis_operand;
void (*ruby_vm_collect_usage_func_register)(int reg, int isset) = vm_analysis_register;

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

#else

void (*ruby_vm_collect_usage_func_insn)(int insn) = NULL;
void (*ruby_vm_collect_usage_func_operand)(int insn, int n, VALUE op) = NULL;
void (*ruby_vm_collect_usage_func_register)(int reg, int isset) = NULL;

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

	valstr = rb_insn_operand_intern(GET_THREAD()->cfp->iseq, insn, n, op, 0, 0, 0, 0);

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

#include "vm_call_iseq_optimized.inc" /* required from vm_insnhelper.c */
