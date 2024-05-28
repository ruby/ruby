/**********************************************************************

  vm_eval.c -

  $Author$
  created at: Sat May 24 16:02:32 JST 2008

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal/thread.h"
struct local_var_list {
    VALUE tbl;
};

static inline VALUE method_missing(rb_execution_context_t *ec, VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status, int kw_splat);
static inline VALUE vm_yield_with_cref(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat, const rb_cref_t *cref, int is_lambda);
static inline VALUE vm_yield(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat);
static inline VALUE vm_yield_with_block(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE block_handler, int kw_splat);
static inline VALUE vm_yield_force_blockarg(rb_execution_context_t *ec, VALUE args);
VALUE vm_exec(rb_execution_context_t *ec);
static void vm_set_eval_stack(rb_execution_context_t * th, const rb_iseq_t *iseq, const rb_cref_t *cref, const struct rb_block *base_block);
static int vm_collect_local_variables_in_heap(const VALUE *dfp, const struct local_var_list *vars);

static VALUE rb_eUncaughtThrow;
static ID id_result, id_tag, id_value;
#define id_mesg idMesg

static VALUE send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope);
static VALUE vm_call0_body(rb_execution_context_t* ec, struct rb_calling_info *calling, const VALUE *argv);

static VALUE *
vm_argv_ruby_array(VALUE *av, const VALUE *argv, int *flags, int *argc, int kw_splat)
{
    *flags |= VM_CALL_ARGS_SPLAT;
    VALUE argv_ary = rb_ary_hidden_new(*argc);
    rb_ary_cat(argv_ary, argv, *argc);
    *argc = 2;
    av[0] = argv_ary;
    if (kw_splat) {
        av[1] = rb_ary_pop(argv_ary);
    }
    else {
        // Make sure flagged keyword hash passed as regular argument
        // isn't treated as keywords
        *flags |= VM_CALL_KW_SPLAT;
        av[1] = rb_hash_new();
    }
    return av;
}

static inline VALUE vm_call0_cc(rb_execution_context_t *ec, VALUE recv, ID id, int argc, const VALUE *argv, const struct rb_callcache *cc, int kw_splat);

VALUE
rb_vm_call0(rb_execution_context_t *ec, VALUE recv, ID id, int argc, const VALUE *argv, const rb_callable_method_entry_t *cme, int kw_splat)
{
    const struct rb_callcache cc = VM_CC_ON_STACK(Qfalse, vm_call_general, {{ 0 }}, cme);
    return vm_call0_cc(ec, recv, id, argc, argv, &cc, kw_splat);
}

VALUE
rb_vm_call_with_refinements(rb_execution_context_t *ec, VALUE recv, ID id, int argc, const VALUE *argv, int kw_splat)
{
    const rb_callable_method_entry_t *me =
        rb_callable_method_entry_with_refinements(CLASS_OF(recv), id, NULL);
    if (me) {
        return rb_vm_call0(ec, recv, id, argc, argv, me, kw_splat);
    }
    else {
        /* fallback to funcall (e.g. method_missing) */
        return rb_funcallv(recv, id, argc, argv);
    }
}

static inline VALUE
vm_call0_cc(rb_execution_context_t *ec, VALUE recv, ID id, int argc, const VALUE *argv, const struct rb_callcache *cc, int kw_splat)
{
    int flags = kw_splat ? VM_CALL_KW_SPLAT : 0;
    VALUE *use_argv = (VALUE *)argv;
    VALUE av[2];

    if (UNLIKELY(vm_cc_cme(cc)->def->type == VM_METHOD_TYPE_ISEQ && argc > VM_ARGC_STACK_MAX)) {
        use_argv = vm_argv_ruby_array(av, argv, &flags, &argc, kw_splat);
    }

    struct rb_calling_info calling = {
        .cd = &(struct rb_call_data) {
            .ci = &VM_CI_ON_STACK(id, flags, argc, NULL),
            .cc = NULL,
        },
        .cc = cc,
        .block_handler = vm_passed_block_handler(ec),
        .recv = recv,
        .argc = argc,
        .kw_splat = kw_splat,
    };

    return vm_call0_body(ec, &calling, use_argv);
}

static VALUE
vm_call0_cme(rb_execution_context_t *ec, struct rb_calling_info *calling, const VALUE *argv, const rb_callable_method_entry_t *cme)
{
    calling->cc = &VM_CC_ON_STACK(Qfalse, vm_call_general, {{ 0 }}, cme);
    return vm_call0_body(ec, calling, argv);
}

static VALUE
vm_call0_super(rb_execution_context_t *ec, struct rb_calling_info *calling, const VALUE *argv, VALUE klass, enum method_missing_reason ex)
{
    ID mid = vm_ci_mid(calling->cd->ci);
    klass = RCLASS_SUPER(klass);

    if (klass) {
        const rb_callable_method_entry_t *cme = rb_callable_method_entry(klass, mid);

        if (cme) {
            RUBY_VM_CHECK_INTS(ec);
            return vm_call0_cme(ec, calling, argv, cme);
        }
    }

    vm_passed_block_handler_set(ec, calling->block_handler);
    return method_missing(ec, calling->recv, mid, calling->argc, argv, ex, calling->kw_splat);
}

static VALUE
vm_call0_cfunc_with_frame(rb_execution_context_t* ec, struct rb_calling_info *calling, const VALUE *argv)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    VALUE val;
    const rb_callable_method_entry_t *me = vm_cc_cme(calling->cc);
    const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(me->def, body.cfunc);
    int len = cfunc->argc;
    VALUE recv = calling->recv;
    int argc = calling->argc;
    ID mid = vm_ci_mid(ci);
    VALUE block_handler = calling->block_handler;
    int frame_flags = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;

    if (calling->kw_splat) {
        if (argc > 0 && RB_TYPE_P(argv[argc-1], T_HASH) && RHASH_EMPTY_P(argv[argc-1])) {
            argc--;
        }
        else {
            frame_flags |= VM_FRAME_FLAG_CFRAME_KW;
        }
    }

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, recv, me->def->original_id, mid, me->owner, Qnil);
    {
        rb_control_frame_t *reg_cfp = ec->cfp;

        vm_push_frame(ec, 0, frame_flags, recv,
                      block_handler, (VALUE)me,
                      0, reg_cfp->sp, 0, 0);

        if (len >= 0) rb_check_arity(argc, len, len);

        val = (*cfunc->invoker)(recv, argc, argv, cfunc->func);

        CHECK_CFP_CONSISTENCY("vm_call0_cfunc_with_frame");
        rb_vm_pop_frame(ec);
    }
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, recv, me->def->original_id, mid, me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);

    return val;
}

static VALUE
vm_call0_cfunc(rb_execution_context_t *ec, struct rb_calling_info *calling, const VALUE *argv)
{
    return vm_call0_cfunc_with_frame(ec, calling, argv);
}

static void
vm_call_check_arity(struct rb_calling_info *calling, int argc, const VALUE *argv)
{
    if (calling->kw_splat &&
        calling->argc > 0 &&
        RB_TYPE_P(argv[calling->argc-1], T_HASH) &&
        RHASH_EMPTY_P(argv[calling->argc-1])) {
        calling->argc--;
    }

    rb_check_arity(calling->argc, argc, argc);
}

/* `ci' should point temporal value (on stack value) */
static VALUE
vm_call0_body(rb_execution_context_t *ec, struct rb_calling_info *calling, const VALUE *argv)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;
    VALUE ret;

  retry:

    switch (vm_cc_cme(cc)->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        {
            rb_control_frame_t *reg_cfp = ec->cfp;
            int i;

            CHECK_VM_STACK_OVERFLOW(reg_cfp, calling->argc + 1);
            vm_check_canary(ec, reg_cfp->sp);

            *reg_cfp->sp++ = calling->recv;
            for (i = 0; i < calling->argc; i++) {
                *reg_cfp->sp++ = argv[i];
            }

            vm_call_iseq_setup(ec, reg_cfp, calling);
            VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH);
            return vm_exec(ec); // CHECK_INTS in this function
        }
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
        ret = vm_call0_cfunc(ec, calling, argv);
        goto success;
      case VM_METHOD_TYPE_ATTRSET:
        vm_call_check_arity(calling, 1, argv);
        VM_CALL_METHOD_ATTR(ret,
                            rb_ivar_set(calling->recv, vm_cc_cme(cc)->def->body.attr.id, argv[0]),
                            (void)0);
        goto success;
      case VM_METHOD_TYPE_IVAR:
        vm_call_check_arity(calling, 0, argv);
        VM_CALL_METHOD_ATTR(ret,
                            rb_attr_get(calling->recv, vm_cc_cme(cc)->def->body.attr.id),
                            (void)0);
        goto success;
      case VM_METHOD_TYPE_BMETHOD:
        ret = vm_call_bmethod_body(ec, calling, argv);
        goto success;
      case VM_METHOD_TYPE_ZSUPER:
        {
            VALUE klass = RCLASS_ORIGIN(vm_cc_cme(cc)->defined_class);
            return vm_call0_super(ec, calling, argv, klass, MISSING_SUPER);
        }
      case VM_METHOD_TYPE_REFINED:
        {
            const rb_callable_method_entry_t *cme = vm_cc_cme(cc);

            if (cme->def->body.refined.orig_me) {
                const rb_callable_method_entry_t *orig_cme = refined_method_callable_without_refinement(cme);
                return vm_call0_cme(ec, calling, argv, orig_cme);
            }

            VALUE klass = cme->defined_class;
            return vm_call0_super(ec, calling, argv, klass, 0);
        }
      case VM_METHOD_TYPE_ALIAS:
        {
            const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
            const rb_callable_method_entry_t *orig_cme = aliased_callable_method_entry(cme);

            if (cme == orig_cme) rb_bug("same!!");

            if (vm_cc_markable(cc)) {
                return vm_call0_cme(ec, calling, argv, orig_cme);
            }
            else {
                *((const rb_callable_method_entry_t **)&cc->cme_) = orig_cme;
                goto retry;
            }
        }
      case VM_METHOD_TYPE_MISSING:
        {
            vm_passed_block_handler_set(ec, calling->block_handler);
            return method_missing(ec, calling->recv, vm_ci_mid(ci), calling->argc,
                                  argv, MISSING_NOENTRY, calling->kw_splat);
        }
      case VM_METHOD_TYPE_OPTIMIZED:
        switch (vm_cc_cme(cc)->def->body.optimized.type) {
          case OPTIMIZED_METHOD_TYPE_SEND:
            ret = send_internal(calling->argc, argv, calling->recv, calling->kw_splat ? CALL_FCALL_KW : CALL_FCALL);
            goto success;
          case OPTIMIZED_METHOD_TYPE_CALL:
            {
                rb_proc_t *proc;
                GetProcPtr(calling->recv, proc);
                ret = rb_vm_invoke_proc(ec, proc, calling->argc, argv, calling->kw_splat, calling->block_handler);
                goto success;
            }
          case OPTIMIZED_METHOD_TYPE_STRUCT_AREF:
            vm_call_check_arity(calling, 0, argv);
            VM_CALL_METHOD_ATTR(ret,
                                vm_call_opt_struct_aref0(ec, calling),
                                (void)0);
            goto success;
          case OPTIMIZED_METHOD_TYPE_STRUCT_ASET:
            vm_call_check_arity(calling, 1, argv);
            VM_CALL_METHOD_ATTR(ret,
                                vm_call_opt_struct_aset0(ec, calling, argv[0]),
                                (void)0);
            goto success;
          default:
            rb_bug("vm_call0: unsupported optimized method type (%d)", vm_cc_cme(cc)->def->body.optimized.type);
        }
        break;
      case VM_METHOD_TYPE_UNDEF:
        break;
    }
    rb_bug("vm_call0: unsupported method type (%d)", vm_cc_cme(cc)->def->type);
    return Qundef;

  success:
    RUBY_VM_CHECK_INTS(ec);
    return ret;
}

VALUE
rb_vm_call_kw(rb_execution_context_t *ec, VALUE recv, VALUE id, int argc, const VALUE *argv, const rb_callable_method_entry_t *me, int kw_splat)
{
    return rb_vm_call0(ec, recv, id, argc, argv, me, kw_splat);
}

static inline VALUE
vm_call_super(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat)
{
    VALUE recv = ec->cfp->self;
    VALUE klass;
    ID id;
    rb_control_frame_t *cfp = ec->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    if (VM_FRAME_RUBYFRAME_P(cfp)) {
        rb_bug("vm_call_super: should not be reached");
    }

    klass = RCLASS_ORIGIN(me->defined_class);
    klass = RCLASS_SUPER(klass);
    id = me->def->original_id;
    me = rb_callable_method_entry(klass, id);

    if (!me) {
        return method_missing(ec, recv, id, argc, argv, MISSING_SUPER, kw_splat);
    }
    return rb_vm_call_kw(ec, recv, id, argc, argv, me, kw_splat);
}

VALUE
rb_call_super_kw(int argc, const VALUE *argv, int kw_splat)
{
    rb_execution_context_t *ec = GET_EC();
    PASS_PASSED_BLOCK_HANDLER_EC(ec);
    return vm_call_super(ec, argc, argv, kw_splat);
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    return rb_call_super_kw(argc, argv, RB_NO_KEYWORDS);
}

VALUE
rb_current_receiver(void)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp;
    if (!ec || !(cfp = ec->cfp)) {
        rb_raise(rb_eRuntimeError, "no self, no life");
    }
    return cfp->self;
}

static inline void
stack_check(rb_execution_context_t *ec)
{
    if (!rb_ec_raised_p(ec, RAISED_STACKOVERFLOW) &&
        rb_ec_stack_check(ec)) {
        rb_ec_raised_set(ec, RAISED_STACKOVERFLOW);
        rb_ec_stack_overflow(ec, FALSE);
    }
}

void
rb_check_stack_overflow(void)
{
#ifndef RB_THREAD_LOCAL_SPECIFIER
    if (!ruby_current_ec_key) return;
#endif
    rb_execution_context_t *ec = GET_EC();
    if (ec) stack_check(ec);
}

NORETURN(static void uncallable_object(VALUE recv, ID mid));
static inline const rb_callable_method_entry_t *rb_search_method_entry(VALUE recv, ID mid);
static inline enum method_missing_reason rb_method_call_status(rb_execution_context_t *ec, const rb_callable_method_entry_t *me, call_type scope, VALUE self);

static VALUE
gccct_hash(VALUE klass, ID mid)
{
    return (klass >> 3) ^ (VALUE)mid;
}

NOINLINE(static const struct rb_callcache *gccct_method_search_slowpath(rb_vm_t *vm, VALUE klass, unsigned int index, const struct rb_callinfo * ci));

static const struct rb_callcache *
gccct_method_search_slowpath(rb_vm_t *vm, VALUE klass, unsigned int index, const struct rb_callinfo *ci)
{
    struct rb_call_data cd = {
            .ci = ci,
            .cc = NULL
    };

    vm_search_method_slowpath0(vm->self, &cd, klass);

    return vm->global_cc_cache_table[index] = cd.cc;
}

static void
scope_to_ci(call_type scope, ID mid, int argc, struct rb_callinfo *ci)
{
    int flags = 0;

    switch(scope) {
      case CALL_PUBLIC:
        break;
      case CALL_FCALL:
        flags |= VM_CALL_FCALL;
        break;
      case CALL_VCALL:
        flags |= VM_CALL_VCALL;
        break;
      case CALL_PUBLIC_KW:
        flags |= VM_CALL_KWARG;
        break;
      case CALL_FCALL_KW:
        flags |= (VM_CALL_KWARG | VM_CALL_FCALL);
        break;
    }
    *ci = VM_CI_ON_STACK(mid, flags, argc, NULL);
}

static inline const struct rb_callcache *
gccct_method_search(rb_execution_context_t *ec, VALUE recv, ID mid, const struct rb_callinfo *ci)
{
    VALUE klass;

    if (!SPECIAL_CONST_P(recv)) {
        klass = RBASIC_CLASS(recv);
        if (UNLIKELY(!klass)) uncallable_object(recv, mid);
    }
    else {
        klass = CLASS_OF(recv);
    }

    // search global method cache
    unsigned int index = (unsigned int)(gccct_hash(klass, mid) % VM_GLOBAL_CC_CACHE_TABLE_SIZE);
    rb_vm_t *vm = rb_ec_vm_ptr(ec);
    const struct rb_callcache *cc = vm->global_cc_cache_table[index];

    if (LIKELY(cc)) {
        if (LIKELY(vm_cc_class_check(cc, klass))) {
            const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
            if (LIKELY(!METHOD_ENTRY_INVALIDATED(cme) &&
                       cme->called_id == mid)) {

                VM_ASSERT(vm_cc_check_cme(cc, rb_callable_method_entry(klass, mid)));
                RB_DEBUG_COUNTER_INC(gccct_hit);

                return cc;
            }
        }
    }
    else {
        RB_DEBUG_COUNTER_INC(gccct_null);
    }

    RB_DEBUG_COUNTER_INC(gccct_miss);
    return gccct_method_search_slowpath(vm, klass, index, ci);
}

/**
 * @internal
 * calls the specified method.
 *
 * This function is called by functions in rb_call* family.
 * @param ec     current execution context
 * @param recv   receiver of the method
 * @param mid    an ID that represents the name of the method
 * @param argc   the number of method arguments
 * @param argv   a pointer to an array of method arguments
 * @param scope
 * @param self   self in the caller. Qundef means no self is considered and
 *               protected methods cannot be called
 *
 * @note `self` is used in order to controlling access to protected methods.
 */
static inline VALUE
rb_call0(rb_execution_context_t *ec,
         VALUE recv, ID mid, int argc, const VALUE *argv,
         call_type call_scope, VALUE self)
{
    enum method_missing_reason call_status;
    call_type scope = call_scope;
    int kw_splat = RB_NO_KEYWORDS;

    switch (scope) {
      case CALL_PUBLIC_KW:
        scope = CALL_PUBLIC;
        kw_splat = 1;
        break;
      case CALL_FCALL_KW:
        scope = CALL_FCALL;
        kw_splat = 1;
        break;
      default:
        break;
    }

    struct rb_callinfo ci;
    scope_to_ci(scope, mid, argc, &ci);

    const struct rb_callcache *cc = gccct_method_search(ec, recv, mid, &ci);

    if (scope == CALL_PUBLIC) {
        RB_DEBUG_COUNTER_INC(call0_public);

        const rb_callable_method_entry_t *cc_cme = cc ? vm_cc_cme(cc) : NULL;
        const rb_callable_method_entry_t *cme = callable_method_entry_refinements0(CLASS_OF(recv), mid, NULL, true, cc_cme);
        call_status = rb_method_call_status(ec, cme, scope, self);

        if (UNLIKELY(call_status != MISSING_NONE)) {
            return method_missing(ec, recv, mid, argc, argv, call_status, kw_splat);
        }
        else if (UNLIKELY(cc_cme != cme)) { // refinement is solved
            stack_check(ec);
            return rb_vm_call_kw(ec, recv, mid, argc, argv, cme, kw_splat);
        }
    }
    else {
        RB_DEBUG_COUNTER_INC(call0_other);
        call_status = rb_method_call_status(ec, cc ? vm_cc_cme(cc) : NULL, scope, self);

        if (UNLIKELY(call_status != MISSING_NONE)) {
            return method_missing(ec, recv, mid, argc, argv, call_status, kw_splat);
        }
    }

    stack_check(ec);
    return vm_call0_cc(ec, recv, mid, argc, argv, cc, kw_splat);
}

struct rescue_funcall_args {
    VALUE defined_class;
    VALUE recv;
    ID mid;
    rb_execution_context_t *ec;
    const rb_callable_method_entry_t *cme;
    unsigned int respond: 1;
    unsigned int respond_to_missing: 1;
    int argc;
    const VALUE *argv;
    int kw_splat;
};

static VALUE
check_funcall_exec(VALUE v)
{
    struct rescue_funcall_args *args = (void *)v;
    return call_method_entry(args->ec, args->defined_class,
                             args->recv, idMethodMissing,
                             args->cme, args->argc, args->argv, args->kw_splat);
}

static VALUE
check_funcall_failed(VALUE v, VALUE e)
{
    struct rescue_funcall_args *args = (void *)v;
    int ret = args->respond;
    if (!ret) {
        switch (method_boundp(args->defined_class, args->mid,
                              BOUND_PRIVATE|BOUND_RESPONDS)) {
          case 2:
            ret = TRUE;
            break;
          case 0:
            ret = args->respond_to_missing;
            break;
          default:
            ret = FALSE;
            break;
        }
    }
    if (ret) {
        rb_exc_raise(e);
    }
    return Qundef;
}

static int
check_funcall_respond_to(rb_execution_context_t *ec, VALUE klass, VALUE recv, ID mid)
{
    return vm_respond_to(ec, klass, recv, mid, TRUE);
}

static int
check_funcall_callable(rb_execution_context_t *ec, const rb_callable_method_entry_t *me)
{
    return rb_method_call_status(ec, me, CALL_FCALL, ec->cfp->self) == MISSING_NONE;
}

static VALUE
check_funcall_missing(rb_execution_context_t *ec, VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv, int respond, VALUE def, int kw_splat)
{
    struct rescue_funcall_args args;
    const rb_callable_method_entry_t *cme;
    VALUE ret = Qundef;

    ret = basic_obj_respond_to_missing(ec, klass, recv,
                                       ID2SYM(mid), Qtrue);
    if (!RTEST(ret)) return def;
    args.respond = respond > 0;
    args.respond_to_missing = !UNDEF_P(ret);
    ret = def;
    cme = callable_method_entry(klass, idMethodMissing, &args.defined_class);

    if (cme && !METHOD_ENTRY_BASIC(cme)) {
        VALUE argbuf, *new_args = ALLOCV_N(VALUE, argbuf, argc+1);

        new_args[0] = ID2SYM(mid);
        #ifdef __GLIBC__
        if (!argv) {
            static const VALUE buf = Qfalse;
            VM_ASSERT(argc == 0);
            argv = &buf;
        }
        #endif
        MEMCPY(new_args+1, argv, VALUE, argc);
        ec->method_missing_reason = MISSING_NOENTRY;
        args.ec = ec;
        args.recv = recv;
        args.cme = cme;
        args.mid = mid;
        args.argc = argc + 1;
        args.argv = new_args;
        args.kw_splat = kw_splat;
        ret = rb_rescue2(check_funcall_exec, (VALUE)&args,
                         check_funcall_failed, (VALUE)&args,
                         rb_eNoMethodError, (VALUE)0);
        ALLOCV_END(argbuf);
    }
    return ret;
}

static VALUE rb_check_funcall_default_kw(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE def, int kw_splat);

VALUE
rb_check_funcall_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat)
{
    return rb_check_funcall_default_kw(recv, mid, argc, argv, Qundef, kw_splat);
}

VALUE
rb_check_funcall(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_check_funcall_default_kw(recv, mid, argc, argv, Qundef, RB_NO_KEYWORDS);
}

static VALUE
rb_check_funcall_default_kw(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE def, int kw_splat)
{
    VM_ASSERT(ruby_thread_has_gvl_p());

    VALUE klass = CLASS_OF(recv);
    const rb_callable_method_entry_t *me;
    rb_execution_context_t *ec = GET_EC();
    int respond = check_funcall_respond_to(ec, klass, recv, mid);

    if (!respond)
        return def;

    me = rb_search_method_entry(recv, mid);
    if (!check_funcall_callable(ec, me)) {
        VALUE ret = check_funcall_missing(ec, klass, recv, mid, argc, argv,
                                          respond, def, kw_splat);
        if (UNDEF_P(ret)) ret = def;
        return ret;
    }
    stack_check(ec);
    return rb_vm_call_kw(ec, recv, mid, argc, argv, me, kw_splat);
}

VALUE
rb_check_funcall_default(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE def)
{
    return rb_check_funcall_default_kw(recv, mid, argc, argv, def, RB_NO_KEYWORDS);
}

VALUE
rb_check_funcall_with_hook_kw(VALUE recv, ID mid, int argc, const VALUE *argv,
                           rb_check_funcall_hook *hook, VALUE arg, int kw_splat)
{
    VALUE klass = CLASS_OF(recv);
    const rb_callable_method_entry_t *me;
    rb_execution_context_t *ec = GET_EC();
    int respond = check_funcall_respond_to(ec, klass, recv, mid);

    if (!respond) {
        (*hook)(FALSE, recv, mid, argc, argv, arg);
        return Qundef;
    }

    me = rb_search_method_entry(recv, mid);
    if (!check_funcall_callable(ec, me)) {
        VALUE ret = check_funcall_missing(ec, klass, recv, mid, argc, argv,
                                          respond, Qundef, kw_splat);
        (*hook)(!UNDEF_P(ret), recv, mid, argc, argv, arg);
        return ret;
    }
    stack_check(ec);
    (*hook)(TRUE, recv, mid, argc, argv, arg);
    return rb_vm_call_kw(ec, recv, mid, argc, argv, me, kw_splat);
}

VALUE
rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
                           rb_check_funcall_hook *hook, VALUE arg)
{
    return rb_check_funcall_with_hook_kw(recv, mid, argc, argv, hook, arg, RB_NO_KEYWORDS);
}

const char *
rb_type_str(enum ruby_value_type type)
{
#define type_case(t) t: return #t
    switch (type) {
      case type_case(T_NONE);
      case type_case(T_OBJECT);
      case type_case(T_CLASS);
      case type_case(T_MODULE);
      case type_case(T_FLOAT);
      case type_case(T_STRING);
      case type_case(T_REGEXP);
      case type_case(T_ARRAY);
      case type_case(T_HASH);
      case type_case(T_STRUCT);
      case type_case(T_BIGNUM);
      case type_case(T_FILE);
      case type_case(T_DATA);
      case type_case(T_MATCH);
      case type_case(T_COMPLEX);
      case type_case(T_RATIONAL);
      case type_case(T_NIL);
      case type_case(T_TRUE);
      case type_case(T_FALSE);
      case type_case(T_SYMBOL);
      case type_case(T_FIXNUM);
      case type_case(T_IMEMO);
      case type_case(T_UNDEF);
      case type_case(T_NODE);
      case type_case(T_ICLASS);
      case type_case(T_ZOMBIE);
      case type_case(T_MOVED);
      case T_MASK: break;
    }
#undef type_case
    return NULL;
}

static void
uncallable_object(VALUE recv, ID mid)
{
    VALUE flags;
    int type;
    const char *typestr;
    VALUE mname = rb_id2str(mid);

    if (SPECIAL_CONST_P(recv)) {
        rb_raise(rb_eNotImpError,
                 "method '%"PRIsVALUE"' called on unexpected immediate object (%p)",
                 mname, (void *)recv);
    }
    else if ((flags = RBASIC(recv)->flags) == 0) {
        rb_raise(rb_eNotImpError,
                 "method '%"PRIsVALUE"' called on terminated object (%p)",
                 mname, (void *)recv);
    }
    else if (!(typestr = rb_type_str(type = BUILTIN_TYPE(recv)))) {
        rb_raise(rb_eNotImpError,
                 "method '%"PRIsVALUE"' called on broken T_?""?""?(0x%02x) object"
                 " (%p flags=0x%"PRIxVALUE")",
                 mname, type, (void *)recv, flags);
    }
    else if (T_OBJECT <= type && type < T_NIL) {
        rb_raise(rb_eNotImpError,
                 "method '%"PRIsVALUE"' called on hidden %s object"
                 " (%p flags=0x%"PRIxVALUE")",
                 mname, typestr, (void *)recv, flags);
    }
    else {
        rb_raise(rb_eNotImpError,
                 "method '%"PRIsVALUE"' called on unexpected %s object"
                 " (%p flags=0x%"PRIxVALUE")",
                 mname, typestr, (void *)recv, flags);
    }
}

static inline const rb_callable_method_entry_t *
rb_search_method_entry(VALUE recv, ID mid)
{
    VALUE klass = CLASS_OF(recv);

    if (!klass) uncallable_object(recv, mid);
    return rb_callable_method_entry(klass, mid);
}

static inline enum method_missing_reason
rb_method_call_status(rb_execution_context_t *ec, const rb_callable_method_entry_t *me, call_type scope, VALUE self)
{
    if (UNLIKELY(UNDEFINED_METHOD_ENTRY_P(me))) {
        goto undefined;
    }
    else if (UNLIKELY(me->def->type == VM_METHOD_TYPE_REFINED)) {
        me = rb_resolve_refined_method_callable(Qnil, me);
        if (UNDEFINED_METHOD_ENTRY_P(me)) goto undefined;
    }

    rb_method_visibility_t visi = METHOD_ENTRY_VISI(me);

    /* receiver specified form for private method */
    if (UNLIKELY(visi != METHOD_VISI_PUBLIC)) {
        if (me->def->original_id == idMethodMissing) {
            return MISSING_NONE;
        }
        else if (visi == METHOD_VISI_PRIVATE &&
                 scope == CALL_PUBLIC) {
            return MISSING_PRIVATE;
        }
        /* self must be kind of a specified form for protected method */
        else if (visi == METHOD_VISI_PROTECTED &&
                 scope == CALL_PUBLIC) {

            VALUE defined_class = me->owner;
            if (RB_TYPE_P(defined_class, T_ICLASS)) {
                defined_class = RBASIC(defined_class)->klass;
            }

            if (UNDEF_P(self) || !rb_obj_is_kind_of(self, defined_class)) {
                return MISSING_PROTECTED;
            }
        }
    }

    return MISSING_NONE;

  undefined:
    return scope == CALL_VCALL ? MISSING_VCALL : MISSING_NOENTRY;
}


/**
 * @internal
 * calls the specified method.
 *
 * This function is called by functions in rb_call* family.
 * @param recv   receiver
 * @param mid    an ID that represents the name of the method
 * @param argc   the number of method arguments
 * @param argv   a pointer to an array of method arguments
 * @param scope
 */
static inline VALUE
rb_call(VALUE recv, ID mid, int argc, const VALUE *argv, call_type scope)
{
    rb_execution_context_t *ec = GET_EC();
    return rb_call0(ec, recv, mid, argc, argv, scope, ec->cfp->self);
}

NORETURN(static void raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv,
                                          VALUE obj, enum method_missing_reason call_status));

/*
 *  call-seq:
 *     obj.method_missing(symbol [, *args] )   -> result
 *
 *  Invoked by Ruby when <i>obj</i> is sent a message it cannot handle.
 *  <i>symbol</i> is the symbol for the method called, and <i>args</i>
 *  are any arguments that were passed to it. By default, the interpreter
 *  raises an error when this method is called. However, it is possible
 *  to override the method to provide more dynamic behavior.
 *  If it is decided that a particular method should not be handled, then
 *  <i>super</i> should be called, so that ancestors can pick up the
 *  missing method.
 *  The example below creates
 *  a class <code>Roman</code>, which responds to methods with names
 *  consisting of roman numerals, returning the corresponding integer
 *  values.
 *
 *     class Roman
 *       def roman_to_int(str)
 *         # ...
 *       end
 *
 *       def method_missing(symbol, *args)
 *         str = symbol.id2name
 *         begin
 *           roman_to_int(str)
 *         rescue
 *           super(symbol, *args)
 *         end
 *       end
 *     end
 *
 *     r = Roman.new
 *     r.iv      #=> 4
 *     r.xxiii   #=> 23
 *     r.mm      #=> 2000
 *     r.foo     #=> NoMethodError
 */

static VALUE
rb_method_missing(int argc, const VALUE *argv, VALUE obj)
{
    rb_execution_context_t *ec = GET_EC();
    raise_method_missing(ec, argc, argv, obj, ec->method_missing_reason);
    UNREACHABLE_RETURN(Qnil);
}

VALUE
rb_make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
                            int argc, const VALUE *argv, int priv)
{
    VALUE name = argv[0];

    if (!format) {
        format = rb_fstring_lit("undefined method '%1$s' for %3$s%4$s");
    }
    if (exc == rb_eNoMethodError) {
        VALUE args = rb_ary_new4(argc - 1, argv + 1);
        return rb_nomethod_err_new(format, obj, name, args, priv);
    }
    else {
        return rb_name_err_new(format, obj, name);
    }
}

static void
raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE obj,
                     enum method_missing_reason last_call_status)
{
    VALUE exc = rb_eNoMethodError;
    VALUE format = 0;

    if (UNLIKELY(argc == 0)) {
        rb_raise(rb_eArgError, "no method name given");
    }
    else if (UNLIKELY(!SYMBOL_P(argv[0]))) {
        const VALUE e = rb_eArgError; /* TODO: TypeError? */
        rb_raise(e, "method name must be a Symbol but %"PRIsVALUE" is given",
                 rb_obj_class(argv[0]));
    }

    stack_check(ec);

    if (last_call_status & MISSING_PRIVATE) {
        format = rb_fstring_lit("private method '%1$s' called for %3$s%4$s");
    }
    else if (last_call_status & MISSING_PROTECTED) {
        format = rb_fstring_lit("protected method '%1$s' called for %3$s%4$s");
    }
    else if (last_call_status & MISSING_VCALL) {
        format = rb_fstring_lit("undefined local variable or method '%1$s' for %3$s%4$s");
        exc = rb_eNameError;
    }
    else if (last_call_status & MISSING_SUPER) {
        format = rb_fstring_lit("super: no superclass method '%1$s' for %3$s%4$s");
    }

    {
        exc = rb_make_no_method_exception(exc, format, obj, argc, argv,
                                          last_call_status & (MISSING_FCALL|MISSING_VCALL));
        if (!(last_call_status & MISSING_MISSING)) {
            rb_vm_pop_cfunc_frame();
        }
        rb_exc_raise(exc);
    }
}

static void
vm_raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv,
                        VALUE obj, int call_status)
{
    vm_passed_block_handler_set(ec, VM_BLOCK_HANDLER_NONE);
    raise_method_missing(ec, argc, argv, obj, call_status | MISSING_MISSING);
}

static inline VALUE
method_missing(rb_execution_context_t *ec, VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status, int kw_splat)
{
    VALUE *nargv, result, work, klass;
    VALUE block_handler = vm_passed_block_handler(ec);
    const rb_callable_method_entry_t *me;

    ec->method_missing_reason = call_status;

    if (id == idMethodMissing) {
        goto missing;
    }

    nargv = ALLOCV_N(VALUE, work, argc + 1);
    nargv[0] = ID2SYM(id);
    #ifdef __GLIBC__
    if (!argv) {
        static const VALUE buf = Qfalse;
        VM_ASSERT(argc == 0);
        argv = &buf;
    }
    #endif
    MEMCPY(nargv + 1, argv, VALUE, argc);
    ++argc;
    argv = nargv;

    klass = CLASS_OF(obj);
    if (!klass) goto missing;
    me = rb_callable_method_entry(klass, idMethodMissing);
    if (!me || METHOD_ENTRY_BASIC(me)) goto missing;
    vm_passed_block_handler_set(ec, block_handler);
    result = rb_vm_call_kw(ec, obj, idMethodMissing, argc, argv, me, kw_splat);
    if (work) ALLOCV_END(work);
    return result;
  missing:
    raise_method_missing(ec, argc, argv, obj, call_status | MISSING_MISSING);
    UNREACHABLE_RETURN(Qundef);
}

static inline VALUE
rb_funcallv_scope(VALUE recv, ID mid, int argc, const VALUE *argv, call_type scope)
{
    rb_execution_context_t *ec = GET_EC();

    struct rb_callinfo ci;
    scope_to_ci(scope, mid, argc, &ci);

    const struct rb_callcache *cc = gccct_method_search(ec, recv, mid, &ci);
    VALUE self = ec->cfp->self;

    if (LIKELY(cc) &&
        LIKELY(rb_method_call_status(ec, vm_cc_cme(cc), scope, self) == MISSING_NONE)) {
        // fastpath
        return vm_call0_cc(ec, recv, mid, argc, argv, cc, false);
    }
    else {
        return rb_call0(ec, recv, mid, argc, argv, scope, self);
    }
}

#ifdef rb_funcallv
#undef rb_funcallv
#endif
VALUE
rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    VM_ASSERT(ruby_thread_has_gvl_p());

    return rb_funcallv_scope(recv, mid, argc, argv, CALL_FCALL);
}

VALUE
rb_funcallv_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat)
{
    VM_ASSERT(ruby_thread_has_gvl_p());

    return rb_call(recv, mid, argc, argv, kw_splat ? CALL_FCALL_KW : CALL_FCALL);
}

VALUE
rb_apply(VALUE recv, ID mid, VALUE args)
{
    int argc;
    VALUE *argv, ret;

    argc = RARRAY_LENINT(args);
    if (argc >= 0x100) {
        args = rb_ary_subseq(args, 0, argc);
        RBASIC_CLEAR_CLASS(args);
        OBJ_FREEZE(args);
        ret = rb_call(recv, mid, argc, RARRAY_CONST_PTR(args), CALL_FCALL);
        RB_GC_GUARD(args);
        return ret;
    }
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY_CONST_PTR(args), VALUE, argc);

    return rb_funcallv(recv, mid, argc, argv);
}

#ifdef rb_funcall
#undef rb_funcall
#endif

VALUE
rb_funcall(VALUE recv, ID mid, int n, ...)
{
    VALUE *argv;
    va_list ar;

    if (n > 0) {
        long i;

        va_start(ar, n);

        argv = ALLOCA_N(VALUE, n);

        for (i = 0; i < n; i++) {
            argv[i] = va_arg(ar, VALUE);
        }
        va_end(ar);
    }
    else {
        argv = 0;
    }
    return rb_funcallv(recv, mid, n, argv);
}

/**
 * Calls a method only if it is the basic method of `ancestor`
 * otherwise returns Qundef;
 * @param recv   receiver of the method
 * @param mid    an ID that represents the name of the method
 * @param ancestor the Class that defined the basic method
 * @param argc   the number of arguments
 * @param argv   pointer to an array of method arguments
 * @param kw_splat bool
 */
VALUE
rb_check_funcall_basic_kw(VALUE recv, ID mid, VALUE ancestor, int argc, const VALUE *argv, int kw_splat)
{
    const rb_callable_method_entry_t *cme;
    rb_execution_context_t *ec;
    VALUE klass = CLASS_OF(recv);
    if (!klass) return Qundef; /* hidden object */

    cme = rb_callable_method_entry(klass, mid);
    if (cme && METHOD_ENTRY_BASIC(cme) && RBASIC_CLASS(cme->defined_class) == ancestor) {
        ec = GET_EC();
        return rb_vm_call0(ec, recv, mid, argc, argv, cme, kw_splat);
    }

    return Qundef;
}

VALUE
rb_funcallv_public(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_funcallv_scope(recv, mid, argc, argv, CALL_PUBLIC);
}

VALUE
rb_funcallv_public_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat)
{
    return rb_call(recv, mid, argc, argv, kw_splat ? CALL_PUBLIC_KW : CALL_PUBLIC);
}

VALUE
rb_funcall_passing_block(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    PASS_PASSED_BLOCK_HANDLER();
    return rb_funcallv_public(recv, mid, argc, argv);
}

VALUE
rb_funcall_passing_block_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat)
{
    PASS_PASSED_BLOCK_HANDLER();
    return rb_call(recv, mid, argc, argv, kw_splat ? CALL_PUBLIC_KW : CALL_PUBLIC);
}

VALUE
rb_funcall_with_block(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE passed_procval)
{
    if (!NIL_P(passed_procval)) {
        vm_passed_block_handler_set(GET_EC(), passed_procval);
    }

    return rb_funcallv_public(recv, mid, argc, argv);
}

VALUE
rb_funcall_with_block_kw(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE passed_procval, int kw_splat)
{
    if (!NIL_P(passed_procval)) {
        vm_passed_block_handler_set(GET_EC(), passed_procval);
    }

    return rb_call(recv, mid, argc, argv, kw_splat ? CALL_PUBLIC_KW : CALL_PUBLIC);
}

static VALUE *
current_vm_stack_arg(const rb_execution_context_t *ec, const VALUE *argv)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp);
    if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, prev_cfp)) return NULL;
    if (prev_cfp->sp + 1 != argv) return NULL;
    return prev_cfp->sp + 1;
}

static VALUE
send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope)
{
    ID id;
    VALUE vid;
    VALUE self;
    VALUE ret, vargv = 0;
    rb_execution_context_t *ec = GET_EC();
    int public = scope == CALL_PUBLIC || scope == CALL_PUBLIC_KW;

    if (public) {
        self = Qundef;
    }
    else {
        self = RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp)->self;
    }

    if (argc == 0) {
        rb_raise(rb_eArgError, "no method name given");
    }

    vid = *argv;

    id = rb_check_id(&vid);
    if (!id) {
        if (rb_method_basic_definition_p(CLASS_OF(recv), idMethodMissing)) {
            VALUE exc = rb_make_no_method_exception(rb_eNoMethodError, 0,
                                                    recv, argc, argv,
                                                    !public);
            rb_exc_raise(exc);
        }
        if (!SYMBOL_P(*argv)) {
            VALUE *tmp_argv = current_vm_stack_arg(ec, argv);
            vid = rb_str_intern(vid);
            if (tmp_argv) {
                tmp_argv[0] = vid;
            }
            else if (argc > 1) {
                tmp_argv = ALLOCV_N(VALUE, vargv, argc);
                tmp_argv[0] = vid;
                MEMCPY(tmp_argv+1, argv+1, VALUE, argc-1);
                argv = tmp_argv;
            }
            else {
                argv = &vid;
            }
        }
        id = idMethodMissing;
        ec->method_missing_reason = MISSING_NOENTRY;
    }
    else {
        argv++; argc--;
    }
    PASS_PASSED_BLOCK_HANDLER_EC(ec);
    ret = rb_call0(ec, recv, id, argc, argv, scope, self);
    ALLOCV_END(vargv);
    return ret;
}

static VALUE
send_internal_kw(int argc, const VALUE *argv, VALUE recv, call_type scope)
{
    if (rb_keyword_given_p()) {
        switch (scope) {
          case CALL_PUBLIC:
            scope = CALL_PUBLIC_KW;
            break;
          case CALL_FCALL:
            scope = CALL_FCALL_KW;
            break;
          default:
            break;
        }
    }
    return send_internal(argc, argv, recv, scope);
}

/*
 * call-seq:
 *    foo.send(symbol [, args...])       -> obj
 *    foo.__send__(symbol [, args...])   -> obj
 *    foo.send(string [, args...])       -> obj
 *    foo.__send__(string [, args...])   -> obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified.
 *  When the method is identified by a string, the string is converted
 *  to a symbol.
 *
 *  BasicObject implements +__send__+, Kernel implements +send+.
 *  <code>__send__</code> is safer than +send+
 *  when _obj_ has the same method name like <code>Socket</code>.
 *  See also <code>public_send</code>.
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
    return send_internal_kw(argc, argv, recv, CALL_FCALL);
}

/*
 *  call-seq:
 *     obj.public_send(symbol [, args...])  -> obj
 *     obj.public_send(string [, args...])  -> obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. Unlike send, public_send calls public
 *  methods only.
 *  When the method is identified by a string, the string is converted
 *  to a symbol.
 *
 *     1.public_send(:puts, "hello")  # causes NoMethodError
 */

static VALUE
rb_f_public_send(int argc, VALUE *argv, VALUE recv)
{
    return send_internal_kw(argc, argv, recv, CALL_PUBLIC);
}

/* yield */

static inline VALUE
rb_yield_0_kw(int argc, const VALUE * argv, int kw_splat)
{
    return vm_yield(GET_EC(), argc, argv, kw_splat);
}

static inline VALUE
rb_yield_0(int argc, const VALUE * argv)
{
    return vm_yield(GET_EC(), argc, argv, RB_NO_KEYWORDS);
}

VALUE
rb_yield_1(VALUE val)
{
    return rb_yield_0(1, &val);
}

VALUE
rb_yield(VALUE val)
{
    if (UNDEF_P(val)) {
        return rb_yield_0(0, NULL);
    }
    else {
        return rb_yield_0(1, &val);
    }
}

#undef rb_yield_values
VALUE
rb_yield_values(int n, ...)
{
    if (n == 0) {
        return rb_yield_0(0, 0);
    }
    else {
        int i;
        VALUE *argv;
        va_list args;
        argv = ALLOCA_N(VALUE, n);

        va_start(args, n);
        for (i=0; i<n; i++) {
            argv[i] = va_arg(args, VALUE);
        }
        va_end(args);

        return rb_yield_0(n, argv);
    }
}

VALUE
rb_yield_values2(int argc, const VALUE *argv)
{
    return rb_yield_0(argc, argv);
}

VALUE
rb_yield_values_kw(int argc, const VALUE *argv, int kw_splat)
{
    return rb_yield_0_kw(argc, argv, kw_splat);
}

VALUE
rb_yield_splat(VALUE values)
{
    VALUE tmp = rb_check_array_type(values);
    VALUE v;
    if (NIL_P(tmp)) {
        rb_raise(rb_eArgError, "not an array");
    }
    v = rb_yield_0(RARRAY_LENINT(tmp), RARRAY_CONST_PTR(tmp));
    RB_GC_GUARD(tmp);
    return v;
}

VALUE
rb_yield_splat_kw(VALUE values, int kw_splat)
{
    VALUE tmp = rb_check_array_type(values);
    VALUE v;
    if (NIL_P(tmp)) {
        rb_raise(rb_eArgError, "not an array");
    }
    v = rb_yield_0_kw(RARRAY_LENINT(tmp), RARRAY_CONST_PTR(tmp), kw_splat);
    RB_GC_GUARD(tmp);
    return v;
}

VALUE
rb_yield_force_blockarg(VALUE values)
{
    return vm_yield_force_blockarg(GET_EC(), values);
}

VALUE
rb_yield_block(RB_BLOCK_CALL_FUNC_ARGLIST(val, arg))
{
    return vm_yield_with_block(GET_EC(), argc, argv,
                               NIL_P(blockarg) ? VM_BLOCK_HANDLER_NONE : blockarg,
                               rb_keyword_given_p());
}

#if VMDEBUG
static const char *
vm_frametype_name(const rb_control_frame_t *cfp);
#endif

static VALUE
rb_iterate0(VALUE (* it_proc) (VALUE), VALUE data1,
            const struct vm_ifunc *const ifunc,
            rb_execution_context_t *ec)
{
    enum ruby_tag_type state;
    volatile VALUE retval = Qnil;
    rb_control_frame_t *const cfp = ec->cfp;

    EC_PUSH_TAG(ec);
    state = EC_EXEC_TAG();
    if (state == 0) {
      iter_retry:
        {
            VALUE block_handler;

            if (ifunc) {
                struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
                captured->code.ifunc = ifunc;
                block_handler = VM_BH_FROM_IFUNC_BLOCK(captured);
            }
            else {
                block_handler = VM_CF_BLOCK_HANDLER(cfp);
            }
            vm_passed_block_handler_set(ec, block_handler);
        }
        retval = (*it_proc) (data1);
    }
    else if (state == TAG_BREAK || state == TAG_RETRY) {
        const struct vm_throw_data *const err = (struct vm_throw_data *)ec->errinfo;
        const rb_control_frame_t *const escape_cfp = THROW_DATA_CATCH_FRAME(err);

        if (cfp == escape_cfp) {
            rb_vm_rewind_cfp(ec, cfp);

            state = 0;
            ec->tag->state = TAG_NONE;
            ec->errinfo = Qnil;

            if (state == TAG_RETRY) goto iter_retry;
            retval = THROW_DATA_VAL(err);
        }
        else if (0) {
            SDR(); fprintf(stderr, "%p, %p\n", (void *)cfp, (void *)escape_cfp);
        }
    }
    EC_POP_TAG();

    if (state) {
        EC_JUMP_TAG(ec, state);
    }
    return retval;
}

static VALUE
rb_iterate_internal(VALUE (* it_proc)(VALUE), VALUE data1,
                    rb_block_call_func_t bl_proc, VALUE data2)
{
    return rb_iterate0(it_proc, data1,
                       bl_proc ? rb_vm_ifunc_proc_new(bl_proc, (void *)data2) : 0,
                       GET_EC());
}

VALUE
rb_iterate(VALUE (* it_proc)(VALUE), VALUE data1,
           rb_block_call_func_t bl_proc, VALUE data2)
{
    return rb_iterate_internal(it_proc, data1, bl_proc, data2);
}

struct iter_method_arg {
    VALUE obj;
    ID mid;
    int argc;
    const VALUE *argv;
    int kw_splat;
};

static VALUE
iterate_method(VALUE obj)
{
    const struct iter_method_arg * arg =
      (struct iter_method_arg *) obj;

    return rb_call(arg->obj, arg->mid, arg->argc, arg->argv, arg->kw_splat ? CALL_FCALL_KW : CALL_FCALL);
}

VALUE rb_block_call_kw(VALUE obj, ID mid, int argc, const VALUE * argv, rb_block_call_func_t bl_proc, VALUE data2, int kw_splat);

VALUE
rb_block_call(VALUE obj, ID mid, int argc, const VALUE * argv,
              rb_block_call_func_t bl_proc, VALUE data2)
{
    return rb_block_call_kw(obj, mid, argc, argv, bl_proc, data2, RB_NO_KEYWORDS);
}

VALUE
rb_block_call_kw(VALUE obj, ID mid, int argc, const VALUE * argv,
              rb_block_call_func_t bl_proc, VALUE data2, int kw_splat)
{
    struct iter_method_arg arg;

    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    arg.kw_splat = kw_splat;
    return rb_iterate_internal(iterate_method, (VALUE)&arg, bl_proc, data2);
}

VALUE
rb_lambda_call(VALUE obj, ID mid, int argc, const VALUE *argv,
               rb_block_call_func_t bl_proc, int min_argc, int max_argc,
               VALUE data2)
{
    struct iter_method_arg arg;
    struct vm_ifunc *block;

    if (!bl_proc) rb_raise(rb_eArgError, "NULL lambda function");
    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    arg.kw_splat = 0;
    block = rb_vm_ifunc_new(bl_proc, (void *)data2, min_argc, max_argc);
    return rb_iterate0(iterate_method, (VALUE)&arg, block, GET_EC());
}

static VALUE
iterate_check_method(VALUE obj)
{
    const struct iter_method_arg * arg =
      (struct iter_method_arg *) obj;

    return rb_check_funcall(arg->obj, arg->mid, arg->argc, arg->argv);
}

VALUE
rb_check_block_call(VALUE obj, ID mid, int argc, const VALUE *argv,
                    rb_block_call_func_t bl_proc, VALUE data2)
{
    struct iter_method_arg arg;

    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    arg.kw_splat = 0;
    return rb_iterate_internal(iterate_check_method, (VALUE)&arg, bl_proc, data2);
}

VALUE
rb_each(VALUE obj)
{
    return rb_call(obj, idEach, 0, 0, CALL_FCALL);
}

static VALUE eval_default_path = Qfalse;

#define EVAL_LOCATION_MARK "eval at "
#define EVAL_LOCATION_MARK_LEN (int)rb_strlen_lit(EVAL_LOCATION_MARK)

static VALUE
get_eval_default_path(void)
{
    int location_lineno;
    VALUE location_path = rb_source_location(&location_lineno);
    if (!NIL_P(location_path)) {
        return rb_fstring(rb_sprintf("("EVAL_LOCATION_MARK"%"PRIsVALUE":%d)",
                                     location_path, location_lineno));
    }

    if (!eval_default_path) {
        eval_default_path = rb_fstring_lit("(eval)");
        rb_vm_register_global_object(eval_default_path);
    }
    return eval_default_path;
}

static const rb_iseq_t *
pm_eval_make_iseq(VALUE src, VALUE fname, int line,
        const struct rb_block *base_block)
{
    const rb_iseq_t *const parent = vm_block_iseq(base_block);
    const rb_iseq_t *iseq = parent;
    VALUE name = rb_fstring_lit("<compiled>");

    // Conditionally enable coverage depending on the current mode:
    int coverage_enabled = ((rb_get_coverage_mode() & COVERAGE_TARGET_EVAL) != 0) ? 1 : 0;

    if (!fname) {
        fname = rb_source_location(&line);
    }

    if (!UNDEF_P(fname)) {
        if (!NIL_P(fname)) fname = rb_fstring(fname);
    }
    else {
        fname = get_eval_default_path();
        coverage_enabled = 0;
    }

    pm_parse_result_t result = { 0 };
    pm_options_line_set(&result.options, line);
    result.node.coverage_enabled = coverage_enabled;

    // Cout scopes, one for each parent iseq, plus one for our local scope
    int scopes_count = 0;
    do {
        scopes_count++;
    } while ((iseq = ISEQ_BODY(iseq)->parent_iseq) && (ISEQ_BODY(iseq)->type != ISEQ_TYPE_TOP));
    pm_options_scopes_init(&result.options, scopes_count + 1);

    // Walk over the scope tree, adding known locals at the correct depths. The
    // scope array should be deepest -> shallowest. so lower indexes in the
    // scopes array refer to root nodes on the tree, and higher indexes are the
    // leaf nodes.
    iseq = parent;
    for (int scopes_index = 0; scopes_index < scopes_count; scopes_index++) {
        int locals_count = ISEQ_BODY(iseq)->local_table_size;
        pm_options_scope_t *options_scope = &result.options.scopes[scopes_count - scopes_index - 1];
        pm_options_scope_init(options_scope, locals_count);

        for (int local_index = 0; local_index < locals_count; local_index++) {
            pm_string_t *scope_local = &options_scope->locals[local_index];
            ID local = ISEQ_BODY(iseq)->local_table[local_index];

            if (rb_is_local_id(local)) {
                const char *name = rb_id2name(local);
                size_t length = strlen(name);

                // Explicitly skip numbered parameters. These should not be sent
                // into the eval.
                if (length == 2 && name[0] == '_' && name[1] >= '1' && name[1] <= '9') {
                    continue;
                }

                pm_string_constant_init(scope_local, name, strlen(name));
            }
        }

        iseq = ISEQ_BODY(iseq)->parent_iseq;
    }

    // Add our empty local scope at the very end of the array for our eval
    // scope's locals.
    pm_options_scope_init(&result.options.scopes[scopes_count], 0);
    VALUE error = pm_parse_string(&result, src, fname);

    // If the parse failed, clean up and raise.
    if (error != Qnil) {
        pm_parse_result_free(&result);
        rb_exc_raise(error);
    }

    // Create one scope node for each scope passed in, initialize the local
    // lookup table with all the local variable information attached to the
    // scope used by the parser.
    pm_scope_node_t *node = &result.node;
    iseq = parent;

    for (int scopes_index = 0; scopes_index < scopes_count; scopes_index++) {
        pm_scope_node_t *parent_scope = ruby_xcalloc(1, sizeof(pm_scope_node_t));
        RUBY_ASSERT(parent_scope != NULL);

        pm_options_scope_t *options_scope = &result.options.scopes[scopes_count - scopes_index - 1];
        parent_scope->coverage_enabled = coverage_enabled;
        parent_scope->parser = &result.parser;
        parent_scope->index_lookup_table = st_init_numtable();

        int locals_count = ISEQ_BODY(iseq)->local_table_size;
        parent_scope->local_table_for_iseq_size = locals_count;
        pm_constant_id_list_init(&parent_scope->locals);

        for (int local_index = 0; local_index < locals_count; local_index++) {
            const pm_string_t *scope_local = &options_scope->locals[local_index];

            pm_constant_id_t constant_id = 0;
            if (pm_string_length(scope_local) > 0) {
                constant_id = pm_constant_pool_insert_constant(
                        &result.parser.constant_pool, pm_string_source(scope_local),
                        pm_string_length(scope_local));
                st_insert(parent_scope->index_lookup_table, (st_data_t)constant_id, (st_data_t)local_index);
            }
            pm_constant_id_list_append(&parent_scope->locals, constant_id);
        }

        node->previous = parent_scope;
        node = parent_scope;
        iseq = ISEQ_BODY(iseq)->parent_iseq;
    }

    iseq = pm_iseq_new_eval(&result.node, name, fname, Qnil, line, parent, 0);

    pm_scope_node_t *prev = result.node.previous;
    while (prev) {
        pm_scope_node_t *next = prev->previous;
        ruby_xfree(prev);
        prev = next;
    }

    pm_parse_result_free(&result);
    rb_exec_event_hook_script_compiled(GET_EC(), iseq, src);

    return iseq;
}

static const rb_iseq_t *
eval_make_iseq(VALUE src, VALUE fname, int line,
               const struct rb_block *base_block)
{
    if (*rb_ruby_prism_ptr()) {
        return pm_eval_make_iseq(src, fname, line, base_block);
    }
    const VALUE parser = rb_parser_new();
    const rb_iseq_t *const parent = vm_block_iseq(base_block);
    rb_iseq_t *iseq = NULL;
    VALUE ast_value;
    rb_ast_t *ast;
    int isolated_depth = 0;

    // Conditionally enable coverage depending on the current mode:
    int coverage_enabled = (rb_get_coverage_mode() & COVERAGE_TARGET_EVAL) != 0;

    {
        int depth = 1;
        const VALUE *ep = vm_block_ep(base_block);

        while (1) {
            if (VM_ENV_FLAGS(ep, VM_ENV_FLAG_ISOLATED)) {
                isolated_depth = depth;
                break;
            }
            else if (VM_ENV_LOCAL_P(ep)) {
                break;
            }
            ep = VM_ENV_PREV_EP(ep);
            depth++;
        }
    }

    if (!fname) {
        fname = rb_source_location(&line);
    }

    if (!UNDEF_P(fname)) {
        if (!NIL_P(fname)) fname = rb_fstring(fname);
    }
    else {
        fname = get_eval_default_path();
        coverage_enabled = FALSE;
    }

    rb_parser_set_context(parser, parent, FALSE);
    if (ruby_vm_keep_script_lines) rb_parser_set_script_lines(parser);
    ast_value = rb_parser_compile_string_path(parser, fname, src, line);

    ast = rb_ruby_ast_data_get(ast_value);

    if (ast->body.root) {
        ast->body.coverage_enabled = coverage_enabled;
        iseq = rb_iseq_new_eval(ast_value,
                                ISEQ_BODY(parent)->location.label,
                                fname, Qnil, line,
                                parent, isolated_depth);
    }
    rb_ast_dispose(ast);

    if (iseq != NULL) {
        if (0 && iseq) {		/* for debug */
            VALUE disasm = rb_iseq_disasm(iseq);
            printf("%s\n", StringValuePtr(disasm));
        }

        rb_exec_event_hook_script_compiled(GET_EC(), iseq, src);
    }

    return iseq;
}

static VALUE
eval_string_with_cref(VALUE self, VALUE src, rb_cref_t *cref, VALUE file, int line)
{
    rb_execution_context_t *ec = GET_EC();
    struct rb_block block;
    const rb_iseq_t *iseq;
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    if (!cfp) {
        rb_raise(rb_eRuntimeError, "Can't eval on top of Fiber or Thread");
    }

    block.as.captured = *VM_CFP_TO_CAPTURED_BLOCK(cfp);
    block.as.captured.self = self;
    block.as.captured.code.iseq = cfp->iseq;
    block.type = block_type_iseq;

    iseq = eval_make_iseq(src, file, line, &block);
    if (!iseq) {
        rb_exc_raise(ec->errinfo);
    }

    /* TODO: what the code checking? */
    if (!cref && block.as.captured.code.val) {
        rb_cref_t *orig_cref = vm_get_cref(vm_block_ep(&block));
        cref = vm_cref_dup(orig_cref);
    }
    vm_set_eval_stack(ec, iseq, cref, &block);

    /* kick */
    return vm_exec(ec);
}

static VALUE
eval_string_with_scope(VALUE scope, VALUE src, VALUE file, int line)
{
    rb_execution_context_t *ec = GET_EC();
    rb_binding_t *bind = Check_TypedStruct(scope, &ruby_binding_data_type);
    const rb_iseq_t *iseq = eval_make_iseq(src, file, line, &bind->block);
    if (!iseq) {
        rb_exc_raise(ec->errinfo);
    }

    vm_set_eval_stack(ec, iseq, NULL, &bind->block);

    /* save new env */
    if (ISEQ_BODY(iseq)->local_table_size > 0) {
        vm_bind_update_env(scope, bind, vm_make_env_object(ec, ec->cfp));
    }

    /* kick */
    return vm_exec(ec);
}

/*
 *  call-seq:
 *     eval(string [, binding [, filename [,lineno]]])  -> obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>. If
 *  <em>binding</em> is given, which must be a Binding object, the
 *  evaluation is performed in its context. If the optional
 *  <em>filename</em> and <em>lineno</em> parameters are present, they
 *  will be used when reporting syntax errors.
 *
 *     def get_binding(str)
 *       return binding
 *     end
 *     str = "hello"
 *     eval "str + ' Fred'"                      #=> "hello Fred"
 *     eval "str + ' Fred'", get_binding("bye")  #=> "bye Fred"
 */

VALUE
rb_f_eval(int argc, const VALUE *argv, VALUE self)
{
    VALUE src, scope, vfile, vline;
    VALUE file = Qundef;
    int line = 1;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    StringValue(src);
    if (argc >= 3) {
        StringValue(vfile);
    }
    if (argc >= 4) {
        line = NUM2INT(vline);
    }

    if (!NIL_P(vfile))
        file = vfile;

    if (NIL_P(scope))
        return eval_string_with_cref(self, src, NULL, file, line);
    else
        return eval_string_with_scope(scope, src, file, line);
}

/** @note This function name is not stable. */
VALUE
ruby_eval_string_from_file(const char *str, const char *filename)
{
    VALUE file = filename ? rb_str_new_cstr(filename) : 0;
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec ? rb_vm_get_ruby_level_next_cfp(ec, ec->cfp) : NULL;
    VALUE self = cfp ? cfp->self : rb_vm_top_self();
    return eval_string_with_cref(self, rb_str_new2(str), NULL, file, 1);
}

VALUE
rb_eval_string(const char *str)
{
    return ruby_eval_string_from_file(str, "eval");
}

static VALUE
eval_string_protect(VALUE str)
{
    return rb_eval_string((char *)str);
}

VALUE
rb_eval_string_protect(const char *str, int *pstate)
{
    return rb_protect(eval_string_protect, (VALUE)str, pstate);
}

struct eval_string_wrap_arg {
    VALUE top_self;
    VALUE klass;
    const char *str;
};

static VALUE
eval_string_wrap_protect(VALUE data)
{
    const struct eval_string_wrap_arg *const arg = (struct eval_string_wrap_arg*)data;
    rb_cref_t *cref = rb_vm_cref_new_toplevel();
    cref->klass_or_self = arg->klass;
    return eval_string_with_cref(arg->top_self, rb_str_new_cstr(arg->str), cref, rb_str_new_cstr("eval"), 1);
}

VALUE
rb_eval_string_wrap(const char *str, int *pstate)
{
    int state;
    rb_thread_t *th = GET_THREAD();
    VALUE self = th->top_self;
    VALUE wrapper = th->top_wrapper;
    VALUE val;
    struct eval_string_wrap_arg data;

    th->top_wrapper = rb_module_new();
    th->top_self = rb_obj_clone(rb_vm_top_self());
    rb_extend_object(th->top_self, th->top_wrapper);

    data.top_self = th->top_self;
    data.klass = th->top_wrapper;
    data.str = str;

    val = rb_protect(eval_string_wrap_protect, (VALUE)&data, &state);

    th->top_self = self;
    th->top_wrapper = wrapper;

    if (pstate) {
        *pstate = state;
    }
    else if (state != TAG_NONE) {
        EC_JUMP_TAG(th->ec, state);
    }
    return val;
}

VALUE
rb_eval_cmd_kw(VALUE cmd, VALUE arg, int kw_splat)
{
    enum ruby_tag_type state;
    volatile VALUE val = Qnil;		/* OK */
    rb_execution_context_t * volatile ec = GET_EC();

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        if (!RB_TYPE_P(cmd, T_STRING)) {
            val = rb_funcallv_kw(cmd, idCall, RARRAY_LENINT(arg),
                              RARRAY_CONST_PTR(arg), kw_splat);
        }
        else {
            val = eval_string_with_cref(rb_vm_top_self(), cmd, NULL, 0, 0);
        }
    }
    EC_POP_TAG();

    if (state) EC_JUMP_TAG(ec, state);
    return val;
}

/* block eval under the class/module context */

static VALUE
yield_under(VALUE self, int singleton, int argc, const VALUE *argv, int kw_splat)
{
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    VALUE block_handler = VM_CF_BLOCK_HANDLER(cfp);
    VALUE new_block_handler = 0;
    const struct rb_captured_block *captured = NULL;
    struct rb_captured_block new_captured;
    const VALUE *ep = NULL;
    rb_cref_t *cref;
    int is_lambda = FALSE;

    if (block_handler != VM_BLOCK_HANDLER_NONE) {
      again:
        switch (vm_block_handler_type(block_handler)) {
          case block_handler_type_iseq:
            captured = VM_BH_TO_CAPT_BLOCK(block_handler);
            new_captured = *captured;
            new_block_handler = VM_BH_FROM_ISEQ_BLOCK(&new_captured);
            break;
          case block_handler_type_ifunc:
            captured = VM_BH_TO_CAPT_BLOCK(block_handler);
            new_captured = *captured;
            new_block_handler = VM_BH_FROM_IFUNC_BLOCK(&new_captured);
            break;
          case block_handler_type_proc:
            is_lambda = rb_proc_lambda_p(block_handler) != Qfalse;
            block_handler = vm_proc_to_block_handler(VM_BH_TO_PROC(block_handler));
            goto again;
          case block_handler_type_symbol:
            return rb_sym_proc_call(SYM2ID(VM_BH_TO_SYMBOL(block_handler)),
                                    argc, argv, kw_splat,
                                    VM_BLOCK_HANDLER_NONE);
        }

        new_captured.self = self;
        ep = captured->ep;

        VM_FORCE_WRITE_SPECIAL_CONST(&VM_CF_LEP(ec->cfp)[VM_ENV_DATA_INDEX_SPECVAL], new_block_handler);
    }

    VM_ASSERT(singleton || RB_TYPE_P(self, T_MODULE) || RB_TYPE_P(self, T_CLASS));
    cref = vm_cref_push(ec, self, ep, TRUE, singleton);

    return vm_yield_with_cref(ec, argc, argv, kw_splat, cref, is_lambda);
}

VALUE
rb_yield_refine_block(VALUE refinement, VALUE refinements)
{
    rb_execution_context_t *ec = GET_EC();
    VALUE block_handler = VM_CF_BLOCK_HANDLER(ec->cfp);

    if (vm_block_handler_type(block_handler) != block_handler_type_iseq) {
        rb_bug("rb_yield_refine_block: an iseq block is required");
    }
    else {
        const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
        struct rb_captured_block new_captured = *captured;
        const VALUE *const argv = &new_captured.self; /* dummy to suppress nonnull warning from gcc */
        VALUE new_block_handler = VM_BH_FROM_ISEQ_BLOCK(&new_captured);
        const VALUE *ep = captured->ep;
        rb_cref_t *cref = vm_cref_push(ec, refinement, ep, TRUE, FALSE);
        CREF_REFINEMENTS_SET(cref, refinements);
        VM_FORCE_WRITE_SPECIAL_CONST(&VM_CF_LEP(ec->cfp)[VM_ENV_DATA_INDEX_SPECVAL], new_block_handler);
        new_captured.self = refinement;
        return vm_yield_with_cref(ec, 0, argv, RB_NO_KEYWORDS, cref, FALSE);
    }
}

/* string eval under the class/module context */
static VALUE
eval_under(VALUE self, int singleton, VALUE src, VALUE file, int line)
{
    rb_cref_t *cref = vm_cref_push(GET_EC(), self, NULL, FALSE, singleton);
    StringValue(src);

    return eval_string_with_cref(self, src, cref, file, line);
}

static VALUE
specific_eval(int argc, const VALUE *argv, VALUE self, int singleton, int kw_splat)
{
    if (rb_block_given_p()) {
        rb_check_arity(argc, 0, 0);
        return yield_under(self, singleton, 1, &self, kw_splat);
    }
    else {
        VALUE file = Qnil;
        int line = 1;
        VALUE code;

        rb_check_arity(argc, 1, 3);
        code = argv[0];
        StringValue(code);
        if (argc > 2)
            line = NUM2INT(argv[2]);
        if (argc > 1) {
            file = argv[1];
            if (!NIL_P(file)) StringValue(file);
        }

        if (NIL_P(file)) {
            file = get_eval_default_path();
        }

        return eval_under(self, singleton, code, file, line);
    }
}

/*
 *  call-seq:
 *     obj.instance_eval(string [, filename [, lineno]] )   -> obj
 *     obj.instance_eval {|obj| block }                     -> obj
 *
 *  Evaluates a string containing Ruby source code, or the given block,
 *  within the context of the receiver (_obj_). In order to set the
 *  context, the variable +self+ is set to _obj_ while
 *  the code is executing, giving the code access to _obj_'s
 *  instance variables and private methods.
 *
 *  When <code>instance_eval</code> is given a block, _obj_ is also
 *  passed in as the block's only argument.
 *
 *  When <code>instance_eval</code> is given a +String+, the optional
 *  second and third parameters supply a filename and starting line number
 *  that are used when reporting compilation errors.
 *
 *     class KlassWithSecret
 *       def initialize
 *         @secret = 99
 *       end
 *       private
 *       def the_secret
 *         "Ssssh! The secret is #{@secret}."
 *       end
 *     end
 *     k = KlassWithSecret.new
 *     k.instance_eval { @secret }          #=> 99
 *     k.instance_eval { the_secret }       #=> "Ssssh! The secret is 99."
 *     k.instance_eval {|obj| obj == self } #=> true
 */

static VALUE
rb_obj_instance_eval_internal(int argc, const VALUE *argv, VALUE self)
{
    return specific_eval(argc, argv, self, TRUE, RB_PASS_CALLED_KEYWORDS);
}

VALUE
rb_obj_instance_eval(int argc, const VALUE *argv, VALUE self)
{
    return specific_eval(argc, argv, self, TRUE, RB_NO_KEYWORDS);
}

/*
 *  call-seq:
 *     obj.instance_exec(arg...) {|var...| block }                       -> obj
 *
 *  Executes the given block within the context of the receiver
 *  (_obj_). In order to set the context, the variable +self+ is set
 *  to _obj_ while the code is executing, giving the code access to
 *  _obj_'s instance variables.  Arguments are passed as block parameters.
 *
 *     class KlassWithSecret
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = KlassWithSecret.new
 *     k.instance_exec(5) {|x| @secret+x }   #=> 104
 */

static VALUE
rb_obj_instance_exec_internal(int argc, const VALUE *argv, VALUE self)
{
    return yield_under(self, TRUE, argc, argv, RB_PASS_CALLED_KEYWORDS);
}

VALUE
rb_obj_instance_exec(int argc, const VALUE *argv, VALUE self)
{
    return yield_under(self, TRUE, argc, argv, RB_NO_KEYWORDS);
}

/*
 *  call-seq:
 *     mod.class_eval(string [, filename [, lineno]])  -> obj
 *     mod.class_eval {|mod| block }                   -> obj
 *     mod.module_eval(string [, filename [, lineno]]) -> obj
 *     mod.module_eval {|mod| block }                  -> obj
 *
 *  Evaluates the string or block in the context of _mod_, except that when
 *  a block is given, constant/class variable lookup is not affected. This
 *  can be used to add methods to a class. <code>module_eval</code> returns
 *  the result of evaluating its argument. The optional _filename_ and
 *  _lineno_ parameters set the text for error messages.
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

static VALUE
rb_mod_module_eval_internal(int argc, const VALUE *argv, VALUE mod)
{
    return specific_eval(argc, argv, mod, FALSE, RB_PASS_CALLED_KEYWORDS);
}

VALUE
rb_mod_module_eval(int argc, const VALUE *argv, VALUE mod)
{
    return specific_eval(argc, argv, mod, FALSE, RB_NO_KEYWORDS);
}

/*
 *  call-seq:
 *     mod.module_exec(arg...) {|var...| block }       -> obj
 *     mod.class_exec(arg...) {|var...| block }        -> obj
 *
 *  Evaluates the given block in the context of the class/module.
 *  The method defined in the block will belong to the receiver.
 *  Any arguments passed to the method will be passed to the block.
 *  This can be used if the block needs to access instance variables.
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

static VALUE
rb_mod_module_exec_internal(int argc, const VALUE *argv, VALUE mod)
{
    return yield_under(mod, FALSE, argc, argv, RB_PASS_CALLED_KEYWORDS);
}

VALUE
rb_mod_module_exec(int argc, const VALUE *argv, VALUE mod)
{
    return yield_under(mod, FALSE, argc, argv, RB_NO_KEYWORDS);
}

/*
 *  Document-class: UncaughtThrowError
 *
 *  Raised when +throw+ is called with a _tag_ which does not have
 *  corresponding +catch+ block.
 *
 *     throw "foo", "bar"
 *
 *  <em>raises the exception:</em>
 *
 *     UncaughtThrowError: uncaught throw "foo"
 */

static VALUE
uncaught_throw_init(int argc, const VALUE *argv, VALUE exc)
{
    rb_check_arity(argc, 2, UNLIMITED_ARGUMENTS);
    rb_call_super(argc - 2, argv + 2);
    rb_ivar_set(exc, id_tag, argv[0]);
    rb_ivar_set(exc, id_value, argv[1]);
    return exc;
}

/*
 * call-seq:
 *   uncaught_throw.tag   -> obj
 *
 * Return the tag object which was called for.
 */

static VALUE
uncaught_throw_tag(VALUE exc)
{
    return rb_ivar_get(exc, id_tag);
}

/*
 * call-seq:
 *   uncaught_throw.value   -> obj
 *
 * Return the return value which was called for.
 */

static VALUE
uncaught_throw_value(VALUE exc)
{
    return rb_ivar_get(exc, id_value);
}

/*
 * call-seq:
 *   uncaught_throw.to_s   ->  string
 *
 * Returns formatted message with the inspected tag.
 */

static VALUE
uncaught_throw_to_s(VALUE exc)
{
    VALUE mesg = rb_attr_get(exc, id_mesg);
    VALUE tag = uncaught_throw_tag(exc);
    return rb_str_format(1, &tag, mesg);
}

/*
 *  call-seq:
 *     throw(tag [, obj])
 *
 *  Transfers control to the end of the active +catch+ block
 *  waiting for _tag_. Raises +UncaughtThrowError+ if there
 *  is no +catch+ block for the _tag_. The optional second
 *  parameter supplies a return value for the +catch+ block,
 *  which otherwise defaults to +nil+. For examples, see
 *  Kernel::catch.
 */

static VALUE
rb_f_throw(int argc, VALUE *argv, VALUE _)
{
    VALUE tag, value;

    rb_scan_args(argc, argv, "11", &tag, &value);
    rb_throw_obj(tag, value);
    UNREACHABLE_RETURN(Qnil);
}

void
rb_throw_obj(VALUE tag, VALUE value)
{
    rb_execution_context_t *ec = GET_EC();
    struct rb_vm_tag *tt = ec->tag;

    while (tt) {
        if (tt->tag == tag) {
            tt->retval = value;
            break;
        }
        tt = tt->prev;
    }
    if (!tt) {
        VALUE desc[3];
        desc[0] = tag;
        desc[1] = value;
        desc[2] = rb_str_new_cstr("uncaught throw %p");
        rb_exc_raise(rb_class_new_instance(numberof(desc), desc, rb_eUncaughtThrow));
    }

    ec->errinfo = (VALUE)THROW_DATA_NEW(tag, NULL, TAG_THROW);
    EC_JUMP_TAG(ec, TAG_THROW);
}

void
rb_throw(const char *tag, VALUE val)
{
    rb_throw_obj(rb_sym_intern_ascii_cstr(tag), val);
}

static VALUE
catch_i(RB_BLOCK_CALL_FUNC_ARGLIST(tag, _))
{
    return rb_yield_0(1, &tag);
}

/*
 *  call-seq:
 *     catch([tag]) {|tag| block }  -> obj
 *
 *  +catch+ executes its block. If +throw+ is not called, the block executes
 *  normally, and +catch+ returns the value of the last expression evaluated.
 *
 *     catch(1) { 123 }            # => 123
 *
 *  If <code>throw(tag2, val)</code> is called, Ruby searches up its stack for
 *  a +catch+ block whose +tag+ has the same +object_id+ as _tag2_. When found,
 *  the block stops executing and returns _val_ (or +nil+ if no second argument
 *  was given to +throw+).
 *
 *     catch(1) { throw(1, 456) }  # => 456
 *     catch(1) { throw(1) }       # => nil
 *
 *  When +tag+ is passed as the first argument, +catch+ yields it as the
 *  parameter of the block.
 *
 *     catch(1) {|x| x + 2 }       # => 3
 *
 *  When no +tag+ is given, +catch+ yields a new unique object (as from
 *  +Object.new+) as the block parameter. This object can then be used as the
 *  argument to +throw+, and will match the correct +catch+ block.
 *
 *     catch do |obj_A|
 *       catch do |obj_B|
 *         throw(obj_B, 123)
 *         puts "This puts is not reached"
 *       end
 *
 *       puts "This puts is displayed"
 *       456
 *     end
 *
 *     # => 456
 *
 *     catch do |obj_A|
 *       catch do |obj_B|
 *         throw(obj_A, 123)
 *         puts "This puts is still not reached"
 *       end
 *
 *       puts "Now this puts is also not reached"
 *       456
 *     end
 *
 *     # => 123
 */

static VALUE
rb_f_catch(int argc, VALUE *argv, VALUE self)
{
    VALUE tag = rb_check_arity(argc, 0, 1) ? argv[0] : rb_obj_alloc(rb_cObject);
    return rb_catch_obj(tag, catch_i, 0);
}

VALUE
rb_catch(const char *tag, rb_block_call_func_t func, VALUE data)
{
    VALUE vtag = tag ? rb_sym_intern_ascii_cstr(tag) : rb_obj_alloc(rb_cObject);
    return rb_catch_obj(vtag, func, data);
}

static VALUE
vm_catch_protect(VALUE tag, rb_block_call_func *func, VALUE data,
                 enum ruby_tag_type *stateptr, rb_execution_context_t *volatile ec)
{
    enum ruby_tag_type state;
    VALUE val = Qnil;		/* OK */
    rb_control_frame_t *volatile saved_cfp = ec->cfp;

    EC_PUSH_TAG(ec);

    _tag.tag = tag;

    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        /* call with argc=1, argv = [tag], block = Qnil to insure compatibility */
        val = (*func)(tag, data, 1, (const VALUE *)&tag, Qnil);
    }
    else if (state == TAG_THROW && THROW_DATA_VAL((struct vm_throw_data *)ec->errinfo) == tag) {
        rb_vm_rewind_cfp(ec, saved_cfp);
        val = ec->tag->retval;
        ec->errinfo = Qnil;
        state = 0;
    }
    EC_POP_TAG();
    if (stateptr)
        *stateptr = state;

    return val;
}

VALUE
rb_catch_protect(VALUE t, rb_block_call_func *func, VALUE data, enum ruby_tag_type *stateptr)
{
    return vm_catch_protect(t, func, data, stateptr, GET_EC());
}

VALUE
rb_catch_obj(VALUE t, rb_block_call_func_t func, VALUE data)
{
    enum ruby_tag_type state;
    rb_execution_context_t *ec = GET_EC();
    VALUE val = vm_catch_protect(t, (rb_block_call_func *)func, data, &state, ec);
    if (state) EC_JUMP_TAG(ec, state);
    return val;
}

static void
local_var_list_init(struct local_var_list *vars)
{
    vars->tbl = rb_ident_hash_new();
    RBASIC_CLEAR_CLASS(vars->tbl);
}

static VALUE
local_var_list_finish(struct local_var_list *vars)
{
    /* TODO: not to depend on the order of st_table */
    VALUE ary = rb_hash_keys(vars->tbl);
    rb_hash_clear(vars->tbl);
    vars->tbl = 0;
    return ary;
}

static int
local_var_list_update(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    if (existing) return ST_STOP;
    *value = (st_data_t)Qtrue;	/* INT2FIX(arg) */
    return ST_CONTINUE;
}

static void
local_var_list_add(const struct local_var_list *vars, ID lid)
{
    if (lid && rb_is_local_id(lid)) {
        /* should skip temporary variable */
        st_data_t idx = 0;	/* tbl->num_entries */
        rb_hash_stlike_update(vars->tbl, ID2SYM(lid), local_var_list_update, idx);
    }
}

/*
 *  call-seq:
 *     local_variables    -> array
 *
 *  Returns the names of the current local variables.
 *
 *     fred = 1
 *     for i in 1..10
 *        # ...
 *     end
 *     local_variables   #=> [:fred, :i]
 */

static VALUE
rb_f_local_variables(VALUE _)
{
    struct local_var_list vars;
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp));
    unsigned int i;

    local_var_list_init(&vars);
    while (cfp) {
        if (cfp->iseq) {
            for (i = 0; i < ISEQ_BODY(cfp->iseq)->local_table_size; i++) {
                local_var_list_add(&vars, ISEQ_BODY(cfp->iseq)->local_table[i]);
            }
        }
        if (!VM_ENV_LOCAL_P(cfp->ep)) {
            /* block */
            const VALUE *ep = VM_CF_PREV_EP(cfp);

            if (vm_collect_local_variables_in_heap(ep, &vars)) {
                break;
            }
            else {
                while (cfp->ep != ep) {
                    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
                }
            }
        }
        else {
            break;
        }
    }
    return local_var_list_finish(&vars);
}

/*
 *  call-seq:
 *     block_given?   -> true or false
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

static VALUE
rb_f_block_given_p(VALUE _)
{
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    cfp = vm_get_ruby_level_caller_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));

    return RBOOL(cfp != NULL && VM_CF_BLOCK_HANDLER(cfp) != VM_BLOCK_HANDLER_NONE);
}

/*
 *  call-seq:
 *     iterator?      -> true or false
 *
 *  Deprecated.  Use block_given? instead.
 */

static VALUE
rb_f_iterator_p(VALUE self)
{
    rb_warn_deprecated("iterator?", "block_given?");
    return rb_f_block_given_p(self);
}

VALUE
rb_current_realfilepath(void)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    cfp = vm_get_ruby_level_caller_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
    if (cfp != NULL) {
        VALUE path = rb_iseq_realpath(cfp->iseq);
        if (RTEST(path)) return path;
        // eval context
        path = rb_iseq_path(cfp->iseq);
        if (path == eval_default_path) {
            return Qnil;
        }

        // [Feature #19755] implicit eval location is "(eval at #{__FILE__}:#{__LINE__})"
        const long len = RSTRING_LEN(path);
        if (len > EVAL_LOCATION_MARK_LEN+1) {
            const char *const ptr = RSTRING_PTR(path);
            if (ptr[len - 1] == ')' &&
                memcmp(ptr, "("EVAL_LOCATION_MARK, EVAL_LOCATION_MARK_LEN+1) == 0) {
                return Qnil;
            }
        }

        return path;
    }
    return Qnil;
}

void
Init_vm_eval(void)
{
    rb_define_global_function("eval", rb_f_eval, -1);
    rb_define_global_function("local_variables", rb_f_local_variables, 0);
    rb_define_global_function("iterator?", rb_f_iterator_p, 0);
    rb_define_global_function("block_given?", rb_f_block_given_p, 0);

    rb_define_global_function("catch", rb_f_catch, -1);
    rb_define_global_function("throw", rb_f_throw, -1);

    rb_define_method(rb_cBasicObject, "instance_eval", rb_obj_instance_eval_internal, -1);
    rb_define_method(rb_cBasicObject, "instance_exec", rb_obj_instance_exec_internal, -1);
    rb_define_private_method(rb_cBasicObject, "method_missing", rb_method_missing, -1);

#if 1
    rb_add_method(rb_cBasicObject, id__send__,
                  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, METHOD_VISI_PUBLIC);
    rb_add_method(rb_mKernel, idSend,
                  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, METHOD_VISI_PUBLIC);
#else
    rb_define_method(rb_cBasicObject, "__send__", rb_f_send, -1);
    rb_define_method(rb_mKernel, "send", rb_f_send, -1);
#endif
    rb_define_method(rb_mKernel, "public_send", rb_f_public_send, -1);

    rb_define_method(rb_cModule, "module_exec", rb_mod_module_exec_internal, -1);
    rb_define_method(rb_cModule, "class_exec", rb_mod_module_exec_internal, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval_internal, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval_internal, -1);

    rb_eUncaughtThrow = rb_define_class("UncaughtThrowError", rb_eArgError);
    rb_define_method(rb_eUncaughtThrow, "initialize", uncaught_throw_init, -1);
    rb_define_method(rb_eUncaughtThrow, "tag", uncaught_throw_tag, 0);
    rb_define_method(rb_eUncaughtThrow, "value", uncaught_throw_value, 0);
    rb_define_method(rb_eUncaughtThrow, "to_s", uncaught_throw_to_s, 0);

    id_result = rb_intern_const("result");
    id_tag = rb_intern_const("tag");
    id_value = rb_intern_const("value");
}
