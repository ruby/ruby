module RubyVM::MJIT
  Instruction = Struct.new(:expr)

  INSTRUCTIONS = {
    nop: Instruction.new(
      expr: <<-EXPR,
{
    /* none */
}
      EXPR
    ),
    getlocal: Instruction.new(
      expr: <<-EXPR,
{
    val = *(vm_get_ep(GET_EP(), level) - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
      EXPR
    ),
    setlocal: Instruction.new(
      expr: <<-EXPR,
{
    vm_env_write(vm_get_ep(GET_EP(), level), -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
      EXPR
    ),
    getblockparam: Instruction.new(
      expr: <<-EXPR,
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    VM_ASSERT(VM_ENV_LOCAL_P(ep));

    if (!VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)) {
        val = rb_vm_bh_to_procval(ec, VM_ENV_BLOCK_HANDLER(ep));
        vm_env_write(ep, -(int)idx, val);
        VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
    }
    else {
        val = *(ep - idx);
        RB_DEBUG_COUNTER_INC(lvar_get);
        (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
    }
}
      EXPR
    ),
    setblockparam: Instruction.new(
      expr: <<-EXPR,
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    VM_ASSERT(VM_ENV_LOCAL_P(ep));

    vm_env_write(ep, -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);

    VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
}
      EXPR
    ),
    getblockparamproxy: Instruction.new(
      expr: <<-EXPR,
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    VM_ASSERT(VM_ENV_LOCAL_P(ep));

    if (!VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)) {
        VALUE block_handler = VM_ENV_BLOCK_HANDLER(ep);

        if (block_handler) {
            switch (vm_block_handler_type(block_handler)) {
              case block_handler_type_iseq:
              case block_handler_type_ifunc:
                val = rb_block_param_proxy;
                break;
              case block_handler_type_symbol:
                val = rb_sym_to_proc(VM_BH_TO_SYMBOL(block_handler));
                goto INSN_LABEL(set);
              case block_handler_type_proc:
                val = VM_BH_TO_PROC(block_handler);
                goto INSN_LABEL(set);
              default:
                VM_UNREACHABLE(getblockparamproxy);
            }
        }
        else {
            val = Qnil;
          INSN_LABEL(set):
            vm_env_write(ep, -(int)idx, val);
            VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
        }
    }
    else {
        val = *(ep - idx);
        RB_DEBUG_COUNTER_INC(lvar_get);
        (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
    }
}
      EXPR
    ),
    getspecial: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_getspecial(ec, GET_LEP(), key, type);
}
      EXPR
    ),
    setspecial: Instruction.new(
      expr: <<-EXPR,
{
    lep_svar_set(ec, GET_LEP(), key, obj);
}
      EXPR
    ),
    getinstancevariable: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_getinstancevariable(GET_ISEQ(), GET_SELF(), id, ic);
}
      EXPR
    ),
    setinstancevariable: Instruction.new(
      expr: <<-EXPR,
{
    vm_setinstancevariable(GET_ISEQ(), GET_SELF(), id, val, ic);
}
      EXPR
    ),
    getclassvariable: Instruction.new(
      expr: <<-EXPR,
{
    rb_control_frame_t *cfp = GET_CFP();
    val = vm_getclassvariable(GET_ISEQ(), cfp, id, ic);
}
      EXPR
    ),
    setclassvariable: Instruction.new(
      expr: <<-EXPR,
{
    vm_ensure_not_refinement_module(GET_SELF());
    vm_setclassvariable(GET_ISEQ(), GET_CFP(), id,  val, ic);
}
      EXPR
    ),
    getconstant: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_get_ev_const(ec, klass, id, allow_nil == Qtrue, 0);
}
      EXPR
    ),
    setconstant: Instruction.new(
      expr: <<-EXPR,
{
    vm_check_if_namespace(cbase);
    vm_ensure_not_refinement_module(GET_SELF());
    rb_const_set(cbase, id, val);
}
      EXPR
    ),
    getglobal: Instruction.new(
      expr: <<-EXPR,
{
    val = rb_gvar_get(gid);
}
      EXPR
    ),
    setglobal: Instruction.new(
      expr: <<-EXPR,
{
    rb_gvar_set(gid, val);
}
      EXPR
    ),
    putnil: Instruction.new(
      expr: <<-EXPR,
{
    val = Qnil;
}
      EXPR
    ),
    putself: Instruction.new(
      expr: <<-EXPR,
{
    val = GET_SELF();
}
      EXPR
    ),
    putobject: Instruction.new(
      expr: <<-EXPR,
{
    /* */
}
      EXPR
    ),
    putspecialobject: Instruction.new(
      expr: <<-EXPR,
{
    enum vm_special_object_type type;

    type = (enum vm_special_object_type)value_type;
    val = vm_get_special_object(GET_EP(), type);
}
      EXPR
    ),
    putstring: Instruction.new(
      expr: <<-EXPR,
{
    val = rb_ec_str_resurrect(ec, str);
}
      EXPR
    ),
    concatstrings: Instruction.new(
      expr: <<-EXPR,
{
    val = rb_str_concat_literals(num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
    ),
    anytostring: Instruction.new(
      expr: <<-EXPR,
{
    val = rb_obj_as_string_result(str, val);
}
      EXPR
    ),
    toregexp: Instruction.new(
      expr: <<-EXPR,
{
    const VALUE ary = rb_ary_tmp_new_from_values(0, cnt, STACK_ADDR_FROM_TOP(cnt));
    val = rb_reg_new_ary(ary, (int)opt);
    rb_ary_clear(ary);
}
      EXPR
    ),
    intern: Instruction.new(
      expr: <<-EXPR,
{
    sym = rb_str_intern(str);
}
      EXPR
    ),
    newarray: Instruction.new(
      expr: <<-EXPR,
{
    val = rb_ec_ary_new_from_values(ec, num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
    ),
    newarraykwsplat: Instruction.new(
      expr: <<-EXPR,
{
    if (RHASH_EMPTY_P(*STACK_ADDR_FROM_TOP(1))) {
        val = rb_ary_new4(num-1, STACK_ADDR_FROM_TOP(num));
    }
    else {
        val = rb_ary_new4(num, STACK_ADDR_FROM_TOP(num));
    }
}
      EXPR
    ),
    duparray: Instruction.new(
      expr: <<-EXPR,
{
    RUBY_DTRACE_CREATE_HOOK(ARRAY, RARRAY_LEN(ary));
    val = rb_ary_resurrect(ary);
}
      EXPR
    ),
    duphash: Instruction.new(
      expr: <<-EXPR,
{
    RUBY_DTRACE_CREATE_HOOK(HASH, RHASH_SIZE(hash) << 1);
    val = rb_hash_resurrect(hash);
}
      EXPR
    ),
    expandarray: Instruction.new(
      expr: <<-EXPR,
{
    vm_expandarray(GET_SP(), ary, num, (int)flag);
}
      EXPR
    ),
    concatarray: Instruction.new(
      expr: <<-EXPR,
{
    ary = vm_concat_array(ary1, ary2);
}
      EXPR
    ),
    splatarray: Instruction.new(
      expr: <<-EXPR,
{
    obj = vm_splat_array(flag, ary);
}
      EXPR
    ),
    newhash: Instruction.new(
      expr: <<-EXPR,
{
    RUBY_DTRACE_CREATE_HOOK(HASH, num);

    if (num) {
        val = rb_hash_new_with_size(num / 2);
        rb_hash_bulk_insert(num, STACK_ADDR_FROM_TOP(num), val);
    }
    else {
        val = rb_hash_new();
    }
}
      EXPR
    ),
    newrange: Instruction.new(
      expr: <<-EXPR,
{
    val = rb_range_new(low, high, (int)flag);
}
      EXPR
    ),
    pop: Instruction.new(
      expr: <<-EXPR,
{
    (void)val;
    /* none */
}
      EXPR
    ),
    dup: Instruction.new(
      expr: <<-EXPR,
{
    val1 = val2 = val;
}
      EXPR
    ),
    dupn: Instruction.new(
      expr: <<-EXPR,
{
    void *dst = GET_SP();
    void *src = STACK_ADDR_FROM_TOP(n);

    MEMCPY(dst, src, VALUE, n);
}
      EXPR
    ),
    swap: Instruction.new(
      expr: <<-EXPR,
{
    /* none */
}
      EXPR
    ),
    topn: Instruction.new(
      expr: <<-EXPR,
{
    val = TOPN(n);
}
      EXPR
    ),
    setn: Instruction.new(
      expr: <<-EXPR,
{
    TOPN(n) = val;
}
      EXPR
    ),
    adjuststack: Instruction.new(
      expr: <<-EXPR,
{
    /* none */
}
      EXPR
    ),
    defined: Instruction.new(
      expr: <<-EXPR,
{
    val = Qnil;
    if (vm_defined(ec, GET_CFP(), op_type, obj, v)) {
      val = pushval;
    }
}
      EXPR
    ),
    checkmatch: Instruction.new(
      expr: <<-EXPR,
{
    result = vm_check_match(ec, target, pattern, flag);
}
      EXPR
    ),
    checkkeyword: Instruction.new(
      expr: <<-EXPR,
{
    ret = vm_check_keyword(kw_bits_index, keyword_index, GET_EP());
}
      EXPR
    ),
    checktype: Instruction.new(
      expr: <<-EXPR,
{
    ret = RBOOL(TYPE(val) == (int)type);
}
      EXPR
    ),
    defineclass: Instruction.new(
      expr: <<-EXPR,
{
    VALUE klass = vm_find_or_create_class_by_id(id, flags, cbase, super);

    rb_iseq_check(class_iseq);

    /* enter scope */
    vm_push_frame(ec, class_iseq, VM_FRAME_MAGIC_CLASS | VM_ENV_FLAG_LOCAL, klass,
                  GET_BLOCK_HANDLER(),
                  (VALUE)vm_cref_push(ec, klass, NULL, FALSE, FALSE),
                  ISEQ_BODY(class_iseq)->iseq_encoded, GET_SP(),
                  ISEQ_BODY(class_iseq)->local_table_size,
                  ISEQ_BODY(class_iseq)->stack_max);
    RESTORE_REGS();
    NEXT_INSN();
}
      EXPR
    ),
    definemethod: Instruction.new(
      expr: <<-EXPR,
{
    vm_define_method(ec, Qnil, id, (VALUE)iseq, FALSE);
}
      EXPR
    ),
    definesmethod: Instruction.new(
      expr: <<-EXPR,
{
    vm_define_method(ec, obj, id, (VALUE)iseq, TRUE);
}
      EXPR
    ),
    send: Instruction.new(
      expr: <<-EXPR,
{
    VALUE bh = vm_caller_setup_arg_block(ec, GET_CFP(), cd->ci, blockiseq, false);
    val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_method);

    if (val == Qundef) {
        RESTORE_REGS();
        NEXT_INSN();
    }
}
      EXPR
    ),
    opt_send_without_block: Instruction.new(
      expr: <<-EXPR,
{
    VALUE bh = VM_BLOCK_HANDLER_NONE;
    val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_method);

    if (val == Qundef) {
        RESTORE_REGS();
        NEXT_INSN();
    }
}
      EXPR
    ),
    objtostring: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_objtostring(GET_ISEQ(), recv, cd);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_str_freeze: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_str_freeze(str, BOP_FREEZE, idFreeze);

    if (val == Qundef) {
        PUSH(rb_str_resurrect(str));
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_nil_p: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_nil_p(GET_ISEQ(), cd, recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_str_uminus: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_str_freeze(str, BOP_UMINUS, idUMinus);

    if (val == Qundef) {
        PUSH(rb_str_resurrect(str));
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_newarray_max: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_newarray_max(ec, num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
    ),
    opt_newarray_min: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_newarray_min(ec, num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
    ),
    invokesuper: Instruction.new(
      expr: <<-EXPR,
{
    VALUE bh = vm_caller_setup_arg_block(ec, GET_CFP(), cd->ci, blockiseq, true);
    val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_super);

    if (val == Qundef) {
        RESTORE_REGS();
        NEXT_INSN();
    }
}
      EXPR
    ),
    invokeblock: Instruction.new(
      expr: <<-EXPR,
{
    VALUE bh = VM_BLOCK_HANDLER_NONE;
    val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_invokeblock);

    if (val == Qundef) {
        RESTORE_REGS();
        NEXT_INSN();
    }
}
      EXPR
    ),
    leave: Instruction.new(
      expr: <<-EXPR,
{
    if (OPT_CHECKED_RUN) {
        const VALUE *const bp = vm_base_ptr(GET_CFP());
        if (GET_SP() != bp) {
            vm_stack_consistency_error(ec, GET_CFP(), bp);
        }
    }

    if (vm_pop_frame(ec, GET_CFP(), GET_EP())) {
#if OPT_CALL_THREADED_CODE
        rb_ec_thread_ptr(ec)->retval = val;
        return 0;
#else
        return val;
#endif
    }
    else {
        RESTORE_REGS();
    }
}
      EXPR
    ),
    throw: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_throw(ec, GET_CFP(), throw_state, throwobj);
    THROW_EXCEPTION(val);
    /* unreachable */
}
      EXPR
    ),
    jump: Instruction.new(
      expr: <<-EXPR,
{
    RUBY_VM_CHECK_INTS(ec);
    JUMP(dst);
}
      EXPR
    ),
    branchif: Instruction.new(
      expr: <<-EXPR,
{
    if (RTEST(val)) {
        RUBY_VM_CHECK_INTS(ec);
        JUMP(dst);
    }
}
      EXPR
    ),
    branchunless: Instruction.new(
      expr: <<-EXPR,
{
    if (!RTEST(val)) {
        RUBY_VM_CHECK_INTS(ec);
        JUMP(dst);
    }
}
      EXPR
    ),
    branchnil: Instruction.new(
      expr: <<-EXPR,
{
    if (NIL_P(val)) {
        RUBY_VM_CHECK_INTS(ec);
        JUMP(dst);
    }
}
      EXPR
    ),
    opt_getinlinecache: Instruction.new(
      expr: <<-EXPR,
{
    struct iseq_inline_constant_cache_entry *ice = ic->entry;

    // If there isn't an entry, then we're going to walk through the ISEQ
    // starting at this instruction until we get to the associated
    // opt_setinlinecache and associate this inline cache with every getconstant
    // listed in between. We're doing this here instead of when the instructions
    // are first compiled because it's possible to turn off inline caches and we
    // want this to work in either case.
    if (!ice) {
        vm_ic_compile(GET_CFP(), ic);
    }

    if (ice && vm_ic_hit_p(ice, GET_EP())) {
        val = ice->value;
        JUMP(dst);
    }
    else {
        ruby_vm_constant_cache_misses++;
        val = Qnil;
    }
}
      EXPR
    ),
    opt_setinlinecache: Instruction.new(
      expr: <<-EXPR,
{
    vm_ic_update(GET_ISEQ(), ic, val, GET_EP());
}
      EXPR
    ),
    once: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_once_dispatch(ec, iseq, ise);
}
      EXPR
    ),
    opt_case_dispatch: Instruction.new(
      expr: <<-EXPR,
{
    OFFSET dst = vm_case_dispatch(hash, else_offset, key);

    if (dst) {
        JUMP(dst);
    }
}
      EXPR
    ),
    opt_plus: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_plus(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_minus: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_minus(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_mult: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_mult(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_div: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_div(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_mod: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_mod(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_eq: Instruction.new(
      expr: <<-EXPR,
{
    val = opt_equality(GET_ISEQ(), recv, obj, cd);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_neq: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_neq(GET_ISEQ(), cd, cd_eq, recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_lt: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_lt(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_le: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_le(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_gt: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_gt(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_ge: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_ge(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_ltlt: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_ltlt(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_and: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_and(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_or: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_or(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_aref: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_aref(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_aset: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_aset(recv, obj, set);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_aset_with: Instruction.new(
      expr: <<-EXPR,
{
    VALUE tmp = vm_opt_aset_with(recv, key, val);

    if (tmp != Qundef) {
        val = tmp;
    }
    else {
#ifndef MJIT_HEADER
        TOPN(0) = rb_str_resurrect(key);
        PUSH(val);
#endif
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_aref_with: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_aref_with(recv, key);

    if (val == Qundef) {
#ifndef MJIT_HEADER
        PUSH(rb_str_resurrect(key));
#endif
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_length: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_length(recv, BOP_LENGTH);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_size: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_length(recv, BOP_SIZE);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_empty_p: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_empty_p(recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_succ: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_succ(recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_not: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_not(GET_ISEQ(), cd, recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    opt_regexpmatch2: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_opt_regexpmatch2(obj2, obj1);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
    ),
    invokebuiltin: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_invoke_builtin(ec, reg_cfp, bf, STACK_ADDR_FROM_TOP(bf->argc));
}
      EXPR
    ),
    opt_invokebuiltin_delegate: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_invoke_builtin_delegate(ec, reg_cfp, bf, (unsigned int)index);
}
      EXPR
    ),
    opt_invokebuiltin_delegate_leave: Instruction.new(
      expr: <<-EXPR,
{
    val = vm_invoke_builtin_delegate(ec, reg_cfp, bf, (unsigned int)index);

    /* leave fastpath */
    /* TracePoint/return fallbacks this insn to opt_invokebuiltin_delegate */
    if (vm_pop_frame(ec, GET_CFP(), GET_EP())) {
#if OPT_CALL_THREADED_CODE
        rb_ec_thread_ptr(ec)->retval = val;
        return 0;
#else
        return val;
#endif
    }
    else {
        RESTORE_REGS();
    }
}
      EXPR
    ),
    getlocal_WC_0: Instruction.new(
      expr: <<-EXPR,
{
    val = *(vm_get_ep(GET_EP(), level) - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
      EXPR
    ),
    getlocal_WC_1: Instruction.new(
      expr: <<-EXPR,
{
    val = *(vm_get_ep(GET_EP(), level) - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
      EXPR
    ),
    setlocal_WC_0: Instruction.new(
      expr: <<-EXPR,
{
    vm_env_write(vm_get_ep(GET_EP(), level), -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
      EXPR
    ),
    setlocal_WC_1: Instruction.new(
      expr: <<-EXPR,
{
    vm_env_write(vm_get_ep(GET_EP(), level), -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
      EXPR
    ),
    putobject_INT2FIX_0_: Instruction.new(
      expr: <<-EXPR,
{
    /* */
}
      EXPR
    ),
    putobject_INT2FIX_1_: Instruction.new(
      expr: <<-EXPR,
{
    /* */
}
      EXPR
    ),
  }
end
