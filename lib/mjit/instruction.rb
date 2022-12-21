module RubyVM::MJIT
  Instruction = Struct.new(
    :name,
    :bin,
    :len,
    :expr,
    :declarations,
    :preamble,
    :opes,
    :pops,
    :rets,
    :always_leaf?,
    :leaf_without_check_ints?,
    :handles_sp?,
  )

  INSNS = {
    0 => Instruction.new(
      name: :nop,
      bin: 0, # BIN(nop)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    /* none */
}
      EXPR
      declarations: [],
      preamble: [],
      opes: [],
      pops: [],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    1 => Instruction.new(
      name: :getlocal,
      bin: 1, # BIN(getlocal)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = *(vm_get_ep(GET_EP(), level) - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: [],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}, {:decl=>"rb_num_t level", :type=>"rb_num_t", :name=>"level"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    2 => Instruction.new(
      name: :setlocal,
      bin: 2, # BIN(setlocal)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    vm_env_write(vm_get_ep(GET_EP(), level), -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: [],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}, {:decl=>"rb_num_t level", :type=>"rb_num_t", :name=>"level"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    3 => Instruction.new(
      name: :getblockparam,
      bin: 3, # BIN(getblockparam)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: [],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}, {:decl=>"rb_num_t level", :type=>"rb_num_t", :name=>"level"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    4 => Instruction.new(
      name: :setblockparam,
      bin: 4, # BIN(setblockparam)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: [],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}, {:decl=>"rb_num_t level", :type=>"rb_num_t", :name=>"level"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    5 => Instruction.new(
      name: :getblockparamproxy,
      bin: 5, # BIN(getblockparamproxy)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: [],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}, {:decl=>"rb_num_t level", :type=>"rb_num_t", :name=>"level"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    6 => Instruction.new(
      name: :getspecial,
      bin: 6, # BIN(getspecial)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_getspecial(ec, GET_LEP(), key, type);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) key, type"],
      preamble: [],
      opes: [{:decl=>"rb_num_t key", :type=>"rb_num_t", :name=>"key"}, {:decl=>"rb_num_t type", :type=>"rb_num_t", :name=>"type"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    7 => Instruction.new(
      name: :setspecial,
      bin: 7, # BIN(setspecial)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    lep_svar_set(ec, GET_LEP(), key, obj);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) obj", "MAYBE_UNUSED(rb_num_t) key"],
      preamble: [],
      opes: [{:decl=>"rb_num_t key", :type=>"rb_num_t", :name=>"key"}],
      pops: [{:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    8 => Instruction.new(
      name: :getinstancevariable,
      bin: 8, # BIN(getinstancevariable)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_getinstancevariable(GET_ISEQ(), GET_SELF(), id, ic);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(IVC) ic", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"IVC ic", :type=>"IVC", :name=>"ic"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    9 => Instruction.new(
      name: :setinstancevariable,
      bin: 9, # BIN(setinstancevariable)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    vm_setinstancevariable(GET_ISEQ(), GET_SELF(), id, val, ic);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(IVC) ic", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"IVC ic", :type=>"IVC", :name=>"ic"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    10 => Instruction.new(
      name: :getclassvariable,
      bin: 10, # BIN(getclassvariable)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    rb_control_frame_t *cfp = GET_CFP();
    val = vm_getclassvariable(GET_ISEQ(), cfp, id, ic);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ICVARC) ic", "MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"ICVARC ic", :type=>"ICVARC", :name=>"ic"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    11 => Instruction.new(
      name: :setclassvariable,
      bin: 11, # BIN(setclassvariable)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    vm_ensure_not_refinement_module(GET_SELF());
    vm_setclassvariable(GET_ISEQ(), GET_CFP(), id,  val, ic);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ICVARC) ic", "MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"ICVARC ic", :type=>"ICVARC", :name=>"ic"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    12 => Instruction.new(
      name: :opt_getconstant_path,
      bin: 12, # BIN(opt_getconstant_path)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    const ID *segments = ic->segments;
    struct iseq_inline_constant_cache_entry *ice = ic->entry;
    if (ice && vm_ic_hit_p(ice, GET_EP())) {
        val = ice->value;

        VM_ASSERT(val == vm_get_ev_const_chain(ec, segments));
    } else {
        ruby_vm_constant_cache_misses++;
        val = vm_get_ev_const_chain(ec, segments);
        vm_ic_track_const_chain(GET_CFP(), ic, segments);
        // Because leaf=false, we need to undo the PC increment to get the address to this instruction
        // INSN_ATTR(width) == 2
        vm_ic_update(GET_ISEQ(), ic, val, GET_EP(), GET_PC() - 2);
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(IC) ic", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"IC ic", :type=>"IC", :name=>"ic"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    13 => Instruction.new(
      name: :getconstant,
      bin: 13, # BIN(getconstant)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_get_ev_const(ec, klass, id, allow_nil == Qtrue, 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(VALUE) allow_nil, klass, val"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}],
      pops: [{:decl=>"VALUE klass", :type=>"VALUE", :name=>"klass"}, {:decl=>"VALUE allow_nil", :type=>"VALUE", :name=>"allow_nil"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    14 => Instruction.new(
      name: :setconstant,
      bin: 14, # BIN(setconstant)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    vm_check_if_namespace(cbase);
    vm_ensure_not_refinement_module(GET_SELF());
    rb_const_set(cbase, id, val);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(VALUE) cbase, val"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}, {:decl=>"VALUE cbase", :type=>"VALUE", :name=>"cbase"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    15 => Instruction.new(
      name: :getglobal,
      bin: 15, # BIN(getglobal)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = rb_gvar_get(gid);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) gid", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ID gid", :type=>"ID", :name=>"gid"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    16 => Instruction.new(
      name: :setglobal,
      bin: 16, # BIN(setglobal)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    rb_gvar_set(gid, val);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) gid", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ID gid", :type=>"ID", :name=>"gid"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    17 => Instruction.new(
      name: :putnil,
      bin: 17, # BIN(putnil)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    val = Qnil;
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    18 => Instruction.new(
      name: :putself,
      bin: 18, # BIN(putself)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    val = GET_SELF();
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    19 => Instruction.new(
      name: :putobject,
      bin: 19, # BIN(putobject)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    /* */
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    20 => Instruction.new(
      name: :putspecialobject,
      bin: 20, # BIN(putspecialobject)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    enum vm_special_object_type type;

    type = (enum vm_special_object_type)value_type;
    val = vm_get_special_object(GET_EP(), type);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) value_type"],
      preamble: [],
      opes: [{:decl=>"rb_num_t value_type", :type=>"rb_num_t", :name=>"value_type"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    21 => Instruction.new(
      name: :putstring,
      bin: 21, # BIN(putstring)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = rb_ec_str_resurrect(ec, str);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) str, val"],
      preamble: [],
      opes: [{:decl=>"VALUE str", :type=>"VALUE", :name=>"str"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    22 => Instruction.new(
      name: :concatstrings,
      bin: 22, # BIN(concatstrings)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = rb_str_concat_literals(num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    23 => Instruction.new(
      name: :anytostring,
      bin: 23, # BIN(anytostring)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    val = rb_obj_as_string_result(str, val);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) str, val"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}, {:decl=>"VALUE str", :type=>"VALUE", :name=>"str"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    24 => Instruction.new(
      name: :toregexp,
      bin: 24, # BIN(toregexp)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    const VALUE ary = rb_ary_tmp_new_from_values(0, cnt, STACK_ADDR_FROM_TOP(cnt));
    val = rb_reg_new_ary(ary, (int)opt);
    rb_ary_clear(ary);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) cnt, opt"],
      preamble: [],
      opes: [{:decl=>"rb_num_t opt", :type=>"rb_num_t", :name=>"opt"}, {:decl=>"rb_num_t cnt", :type=>"rb_num_t", :name=>"cnt"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    25 => Instruction.new(
      name: :intern,
      bin: 25, # BIN(intern)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    sym = rb_str_intern(str);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) str, sym"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE str", :type=>"VALUE", :name=>"str"}],
      rets: [{:decl=>"VALUE sym", :type=>"VALUE", :name=>"sym"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    26 => Instruction.new(
      name: :newarray,
      bin: 26, # BIN(newarray)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = rb_ec_ary_new_from_values(ec, num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    27 => Instruction.new(
      name: :newarraykwsplat,
      bin: 27, # BIN(newarraykwsplat)
      len: 2, # insn_len
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
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    28 => Instruction.new(
      name: :duparray,
      bin: 28, # BIN(duparray)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    RUBY_DTRACE_CREATE_HOOK(ARRAY, RARRAY_LEN(ary));
    val = rb_ary_resurrect(ary);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) ary, val"],
      preamble: [],
      opes: [{:decl=>"VALUE ary", :type=>"VALUE", :name=>"ary"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    29 => Instruction.new(
      name: :duphash,
      bin: 29, # BIN(duphash)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    RUBY_DTRACE_CREATE_HOOK(HASH, RHASH_SIZE(hash) << 1);
    val = rb_hash_resurrect(hash);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) hash, val"],
      preamble: [],
      opes: [{:decl=>"VALUE hash", :type=>"VALUE", :name=>"hash"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    30 => Instruction.new(
      name: :expandarray,
      bin: 30, # BIN(expandarray)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    vm_expandarray(GET_SP(), ary, num, (int)flag);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) ary", "MAYBE_UNUSED(rb_num_t) flag, num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}, {:decl=>"rb_num_t flag", :type=>"rb_num_t", :name=>"flag"}],
      pops: [{:decl=>"VALUE ary", :type=>"VALUE", :name=>"ary"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    31 => Instruction.new(
      name: :concatarray,
      bin: 31, # BIN(concatarray)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    ary = vm_concat_array(ary1, ary2);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) ary, ary1, ary2"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE ary1", :type=>"VALUE", :name=>"ary1"}, {:decl=>"VALUE ary2", :type=>"VALUE", :name=>"ary2"}],
      rets: [{:decl=>"VALUE ary", :type=>"VALUE", :name=>"ary"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    32 => Instruction.new(
      name: :splatarray,
      bin: 32, # BIN(splatarray)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    obj = vm_splat_array(flag, ary);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) ary, flag, obj"],
      preamble: [],
      opes: [{:decl=>"VALUE flag", :type=>"VALUE", :name=>"flag"}],
      pops: [{:decl=>"VALUE ary", :type=>"VALUE", :name=>"ary"}],
      rets: [{:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    33 => Instruction.new(
      name: :newhash,
      bin: 33, # BIN(newhash)
      len: 2, # insn_len
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
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    34 => Instruction.new(
      name: :newrange,
      bin: 34, # BIN(newrange)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = rb_range_new(low, high, (int)flag);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) high, low, val", "MAYBE_UNUSED(rb_num_t) flag"],
      preamble: [],
      opes: [{:decl=>"rb_num_t flag", :type=>"rb_num_t", :name=>"flag"}],
      pops: [{:decl=>"VALUE low", :type=>"VALUE", :name=>"low"}, {:decl=>"VALUE high", :type=>"VALUE", :name=>"high"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    35 => Instruction.new(
      name: :pop,
      bin: 35, # BIN(pop)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    (void)val;
    /* none */
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    36 => Instruction.new(
      name: :dup,
      bin: 36, # BIN(dup)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    val1 = val2 = val;
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val, val1, val2"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [{:decl=>"VALUE val1", :type=>"VALUE", :name=>"val1"}, {:decl=>"VALUE val2", :type=>"VALUE", :name=>"val2"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    37 => Instruction.new(
      name: :dupn,
      bin: 37, # BIN(dupn)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    void *dst = GET_SP();
    void *src = STACK_ADDR_FROM_TOP(n);

    MEMCPY(dst, src, VALUE, n);
}
      EXPR
      declarations: ["MAYBE_UNUSED(rb_num_t) n"],
      preamble: [],
      opes: [{:decl=>"rb_num_t n", :type=>"rb_num_t", :name=>"n"}],
      pops: [],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    38 => Instruction.new(
      name: :swap,
      bin: 38, # BIN(swap)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    /* none */
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) obj, val"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}, {:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    39 => Instruction.new(
      name: :opt_reverse,
      bin: 39, # BIN(opt_reverse)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    rb_num_t i;
    VALUE *sp = STACK_ADDR_FROM_TOP(n);

    for (i=0; i<n/2; i++) {
        VALUE v0 = sp[i];
        VALUE v1 = TOPN(i);
        sp[i] = v1;
        TOPN(i) = v0;
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(rb_num_t) n"],
      preamble: [],
      opes: [{:decl=>"rb_num_t n", :type=>"rb_num_t", :name=>"n"}],
      pops: [],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    40 => Instruction.new(
      name: :topn,
      bin: 40, # BIN(topn)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = TOPN(n);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) n"],
      preamble: [],
      opes: [{:decl=>"rb_num_t n", :type=>"rb_num_t", :name=>"n"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    41 => Instruction.new(
      name: :setn,
      bin: 41, # BIN(setn)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    TOPN(n) = val;
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) n"],
      preamble: [],
      opes: [{:decl=>"rb_num_t n", :type=>"rb_num_t", :name=>"n"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    42 => Instruction.new(
      name: :adjuststack,
      bin: 42, # BIN(adjuststack)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    /* none */
}
      EXPR
      declarations: ["MAYBE_UNUSED(rb_num_t) n"],
      preamble: [],
      opes: [{:decl=>"rb_num_t n", :type=>"rb_num_t", :name=>"n"}],
      pops: [],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    43 => Instruction.new(
      name: :defined,
      bin: 43, # BIN(defined)
      len: 4, # insn_len
      expr: <<-EXPR,
{
    val = Qnil;
    if (vm_defined(ec, GET_CFP(), op_type, obj, v)) {
        val = pushval;
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) obj, pushval, v, val", "MAYBE_UNUSED(rb_num_t) op_type"],
      preamble: [],
      opes: [{:decl=>"rb_num_t op_type", :type=>"rb_num_t", :name=>"op_type"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}, {:decl=>"VALUE pushval", :type=>"VALUE", :name=>"pushval"}],
      pops: [{:decl=>"VALUE v", :type=>"VALUE", :name=>"v"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    44 => Instruction.new(
      name: :checkmatch,
      bin: 44, # BIN(checkmatch)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    result = vm_check_match(ec, target, pattern, flag);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) pattern, result, target", "MAYBE_UNUSED(rb_num_t) flag"],
      preamble: [],
      opes: [{:decl=>"rb_num_t flag", :type=>"rb_num_t", :name=>"flag"}],
      pops: [{:decl=>"VALUE target", :type=>"VALUE", :name=>"target"}, {:decl=>"VALUE pattern", :type=>"VALUE", :name=>"pattern"}],
      rets: [{:decl=>"VALUE result", :type=>"VALUE", :name=>"result"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    45 => Instruction.new(
      name: :checkkeyword,
      bin: 45, # BIN(checkkeyword)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    ret = vm_check_keyword(kw_bits_index, keyword_index, GET_EP());
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) ret", "MAYBE_UNUSED(lindex_t) keyword_index, kw_bits_index"],
      preamble: [],
      opes: [{:decl=>"lindex_t kw_bits_index", :type=>"lindex_t", :name=>"kw_bits_index"}, {:decl=>"lindex_t keyword_index", :type=>"lindex_t", :name=>"keyword_index"}],
      pops: [],
      rets: [{:decl=>"VALUE ret", :type=>"VALUE", :name=>"ret"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    46 => Instruction.new(
      name: :checktype,
      bin: 46, # BIN(checktype)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    ret = RBOOL(TYPE(val) == (int)type);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) ret, val", "MAYBE_UNUSED(rb_num_t) type"],
      preamble: [],
      opes: [{:decl=>"rb_num_t type", :type=>"rb_num_t", :name=>"type"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [{:decl=>"VALUE ret", :type=>"VALUE", :name=>"ret"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    47 => Instruction.new(
      name: :defineclass,
      bin: 47, # BIN(defineclass)
      len: 4, # insn_len
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
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(ISEQ) class_iseq", "MAYBE_UNUSED(VALUE) cbase, super, val", "MAYBE_UNUSED(rb_num_t) flags"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"ISEQ class_iseq", :type=>"ISEQ", :name=>"class_iseq"}, {:decl=>"rb_num_t flags", :type=>"rb_num_t", :name=>"flags"}],
      pops: [{:decl=>"VALUE cbase", :type=>"VALUE", :name=>"cbase"}, {:decl=>"VALUE super", :type=>"VALUE", :name=>"super"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    48 => Instruction.new(
      name: :definemethod,
      bin: 48, # BIN(definemethod)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    vm_define_method(ec, Qnil, id, (VALUE)iseq, FALSE);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(ISEQ) iseq"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"ISEQ iseq", :type=>"ISEQ", :name=>"iseq"}],
      pops: [],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    49 => Instruction.new(
      name: :definesmethod,
      bin: 49, # BIN(definesmethod)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    vm_define_method(ec, obj, id, (VALUE)iseq, TRUE);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ID) id", "MAYBE_UNUSED(ISEQ) iseq", "MAYBE_UNUSED(VALUE) obj"],
      preamble: [],
      opes: [{:decl=>"ID id", :type=>"ID", :name=>"id"}, {:decl=>"ISEQ iseq", :type=>"ISEQ", :name=>"iseq"}],
      pops: [{:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    50 => Instruction.new(
      name: :send,
      bin: 50, # BIN(send)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(ISEQ) blockiseq", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}, {:decl=>"ISEQ blockiseq", :type=>"ISEQ", :name=>"blockiseq"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    51 => Instruction.new(
      name: :opt_send_without_block,
      bin: 51, # BIN(opt_send_without_block)
      len: 2, # insn_len
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
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    52 => Instruction.new(
      name: :objtostring,
      bin: 52, # BIN(objtostring)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_objtostring(GET_ISEQ(), recv, cd);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    53 => Instruction.new(
      name: :opt_str_freeze,
      bin: 53, # BIN(opt_str_freeze)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_str_freeze(str, BOP_FREEZE, idFreeze);

    if (val == Qundef) {
        PUSH(rb_str_resurrect(str));
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) str, val"],
      preamble: [],
      opes: [{:decl=>"VALUE str", :type=>"VALUE", :name=>"str"}, {:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    54 => Instruction.new(
      name: :opt_nil_p,
      bin: 54, # BIN(opt_nil_p)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_nil_p(GET_ISEQ(), cd, recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    55 => Instruction.new(
      name: :opt_str_uminus,
      bin: 55, # BIN(opt_str_uminus)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_str_freeze(str, BOP_UMINUS, idUMinus);

    if (val == Qundef) {
        PUSH(rb_str_resurrect(str));
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) str, val"],
      preamble: [],
      opes: [{:decl=>"VALUE str", :type=>"VALUE", :name=>"str"}, {:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    56 => Instruction.new(
      name: :opt_newarray_max,
      bin: 56, # BIN(opt_newarray_max)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_newarray_max(ec, num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    57 => Instruction.new(
      name: :opt_newarray_min,
      bin: 57, # BIN(opt_newarray_min)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_newarray_min(ec, num, STACK_ADDR_FROM_TOP(num));
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) num"],
      preamble: [],
      opes: [{:decl=>"rb_num_t num", :type=>"rb_num_t", :name=>"num"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    58 => Instruction.new(
      name: :invokesuper,
      bin: 58, # BIN(invokesuper)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(ISEQ) blockiseq", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}, {:decl=>"ISEQ blockiseq", :type=>"ISEQ", :name=>"blockiseq"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    59 => Instruction.new(
      name: :invokeblock,
      bin: 59, # BIN(invokeblock)
      len: 2, # insn_len
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
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    60 => Instruction.new(
      name: :leave,
      bin: 60, # BIN(leave)
      len: 1, # insn_len
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
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    61 => Instruction.new(
      name: :throw,
      bin: 61, # BIN(throw)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_throw(ec, GET_CFP(), throw_state, throwobj);
    THROW_EXCEPTION(val);
    /* unreachable */
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) throwobj, val", "MAYBE_UNUSED(rb_num_t) throw_state"],
      preamble: [],
      opes: [{:decl=>"rb_num_t throw_state", :type=>"rb_num_t", :name=>"throw_state"}],
      pops: [{:decl=>"VALUE throwobj", :type=>"VALUE", :name=>"throwobj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    62 => Instruction.new(
      name: :jump,
      bin: 62, # BIN(jump)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    RUBY_VM_CHECK_INTS(ec);
    JUMP(dst);
}
      EXPR
      declarations: ["MAYBE_UNUSED(OFFSET) dst"],
      preamble: [],
      opes: [{:decl=>"OFFSET dst", :type=>"OFFSET", :name=>"dst"}],
      pops: [],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: true,
      handles_sp?: false,
    ),
    63 => Instruction.new(
      name: :branchif,
      bin: 63, # BIN(branchif)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    if (RTEST(val)) {
        RUBY_VM_CHECK_INTS(ec);
        JUMP(dst);
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(OFFSET) dst", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"OFFSET dst", :type=>"OFFSET", :name=>"dst"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: true,
      handles_sp?: false,
    ),
    64 => Instruction.new(
      name: :branchunless,
      bin: 64, # BIN(branchunless)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    if (!RTEST(val)) {
        RUBY_VM_CHECK_INTS(ec);
        JUMP(dst);
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(OFFSET) dst", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"OFFSET dst", :type=>"OFFSET", :name=>"dst"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: true,
      handles_sp?: false,
    ),
    65 => Instruction.new(
      name: :branchnil,
      bin: 65, # BIN(branchnil)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    if (NIL_P(val)) {
        RUBY_VM_CHECK_INTS(ec);
        JUMP(dst);
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(OFFSET) dst", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"OFFSET dst", :type=>"OFFSET", :name=>"dst"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: false,
      leaf_without_check_ints?: true,
      handles_sp?: false,
    ),
    66 => Instruction.new(
      name: :once,
      bin: 66, # BIN(once)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_once_dispatch(ec, iseq, ise);
}
      EXPR
      declarations: ["MAYBE_UNUSED(ISE) ise", "MAYBE_UNUSED(ISEQ) iseq", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"ISEQ iseq", :type=>"ISEQ", :name=>"iseq"}, {:decl=>"ISE ise", :type=>"ISE", :name=>"ise"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: true,
    ),
    67 => Instruction.new(
      name: :opt_case_dispatch,
      bin: 67, # BIN(opt_case_dispatch)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    OFFSET dst = vm_case_dispatch(hash, else_offset, key);

    if (dst) {
        JUMP(dst);
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CDHASH) hash", "MAYBE_UNUSED(OFFSET) else_offset", "MAYBE_UNUSED(VALUE) key"],
      preamble: [],
      opes: [{:decl=>"CDHASH hash", :type=>"CDHASH", :name=>"hash"}, {:decl=>"OFFSET else_offset", :type=>"OFFSET", :name=>"else_offset"}],
      pops: [{:decl=>"VALUE key", :type=>"VALUE", :name=>"key"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    68 => Instruction.new(
      name: :opt_plus,
      bin: 68, # BIN(opt_plus)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_plus(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    69 => Instruction.new(
      name: :opt_minus,
      bin: 69, # BIN(opt_minus)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_minus(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    70 => Instruction.new(
      name: :opt_mult,
      bin: 70, # BIN(opt_mult)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_mult(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    71 => Instruction.new(
      name: :opt_div,
      bin: 71, # BIN(opt_div)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_div(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    72 => Instruction.new(
      name: :opt_mod,
      bin: 72, # BIN(opt_mod)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_mod(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    73 => Instruction.new(
      name: :opt_eq,
      bin: 73, # BIN(opt_eq)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = opt_equality(GET_ISEQ(), recv, obj, cd);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    74 => Instruction.new(
      name: :opt_neq,
      bin: 74, # BIN(opt_neq)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_neq(GET_ISEQ(), cd, cd_eq, recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd, cd_eq", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd_eq", :type=>"CALL_DATA", :name=>"cd_eq"}, {:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    75 => Instruction.new(
      name: :opt_lt,
      bin: 75, # BIN(opt_lt)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_lt(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    76 => Instruction.new(
      name: :opt_le,
      bin: 76, # BIN(opt_le)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_le(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    77 => Instruction.new(
      name: :opt_gt,
      bin: 77, # BIN(opt_gt)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_gt(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    78 => Instruction.new(
      name: :opt_ge,
      bin: 78, # BIN(opt_ge)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_ge(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    79 => Instruction.new(
      name: :opt_ltlt,
      bin: 79, # BIN(opt_ltlt)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_ltlt(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    80 => Instruction.new(
      name: :opt_and,
      bin: 80, # BIN(opt_and)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_and(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    81 => Instruction.new(
      name: :opt_or,
      bin: 81, # BIN(opt_or)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_or(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    82 => Instruction.new(
      name: :opt_aref,
      bin: 82, # BIN(opt_aref)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_aref(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    83 => Instruction.new(
      name: :opt_aset,
      bin: 83, # BIN(opt_aset)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_aset(recv, obj, set);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj, recv, set, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE obj", :type=>"VALUE", :name=>"obj"}, {:decl=>"VALUE set", :type=>"VALUE", :name=>"set"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    84 => Instruction.new(
      name: :opt_aset_with,
      bin: 84, # BIN(opt_aset_with)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) key, recv, val"],
      preamble: [],
      opes: [{:decl=>"VALUE key", :type=>"VALUE", :name=>"key"}, {:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}, {:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    85 => Instruction.new(
      name: :opt_aref_with,
      bin: 85, # BIN(opt_aref_with)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) key, recv, val"],
      preamble: [],
      opes: [{:decl=>"VALUE key", :type=>"VALUE", :name=>"key"}, {:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    86 => Instruction.new(
      name: :opt_length,
      bin: 86, # BIN(opt_length)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_length(recv, BOP_LENGTH);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    87 => Instruction.new(
      name: :opt_size,
      bin: 87, # BIN(opt_size)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_length(recv, BOP_SIZE);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    88 => Instruction.new(
      name: :opt_empty_p,
      bin: 88, # BIN(opt_empty_p)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_empty_p(recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    89 => Instruction.new(
      name: :opt_succ,
      bin: 89, # BIN(opt_succ)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_succ(recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    90 => Instruction.new(
      name: :opt_not,
      bin: 90, # BIN(opt_not)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_not(GET_ISEQ(), cd, recv);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) recv, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE recv", :type=>"VALUE", :name=>"recv"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    91 => Instruction.new(
      name: :opt_regexpmatch2,
      bin: 91, # BIN(opt_regexpmatch2)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_opt_regexpmatch2(obj2, obj1);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
      EXPR
      declarations: ["MAYBE_UNUSED(CALL_DATA) cd", "MAYBE_UNUSED(VALUE) obj1, obj2, val"],
      preamble: [],
      opes: [{:decl=>"CALL_DATA cd", :type=>"CALL_DATA", :name=>"cd"}],
      pops: [{:decl=>"VALUE obj2", :type=>"VALUE", :name=>"obj2"}, {:decl=>"VALUE obj1", :type=>"VALUE", :name=>"obj1"}],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    92 => Instruction.new(
      name: :invokebuiltin,
      bin: 92, # BIN(invokebuiltin)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = vm_invoke_builtin(ec, reg_cfp, bf, STACK_ADDR_FROM_TOP(bf->argc));
}
      EXPR
      declarations: ["MAYBE_UNUSED(RB_BUILTIN) bf", "MAYBE_UNUSED(VALUE) val"],
      preamble: [],
      opes: [{:decl=>"RB_BUILTIN bf", :type=>"RB_BUILTIN", :name=>"bf"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    93 => Instruction.new(
      name: :opt_invokebuiltin_delegate,
      bin: 93, # BIN(opt_invokebuiltin_delegate)
      len: 3, # insn_len
      expr: <<-EXPR,
{
    val = vm_invoke_builtin_delegate(ec, reg_cfp, bf, (unsigned int)index);
}
      EXPR
      declarations: ["MAYBE_UNUSED(RB_BUILTIN) bf", "MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) index"],
      preamble: [],
      opes: [{:decl=>"RB_BUILTIN bf", :type=>"RB_BUILTIN", :name=>"bf"}, {:decl=>"rb_num_t index", :type=>"rb_num_t", :name=>"index"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    94 => Instruction.new(
      name: :opt_invokebuiltin_delegate_leave,
      bin: 94, # BIN(opt_invokebuiltin_delegate_leave)
      len: 3, # insn_len
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
      declarations: ["MAYBE_UNUSED(RB_BUILTIN) bf", "MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(rb_num_t) index"],
      preamble: [],
      opes: [{:decl=>"RB_BUILTIN bf", :type=>"RB_BUILTIN", :name=>"bf"}, {:decl=>"rb_num_t index", :type=>"rb_num_t", :name=>"index"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: false,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    95 => Instruction.new(
      name: :getlocal_WC_0,
      bin: 95, # BIN(getlocal_WC_0)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = *(vm_get_ep(GET_EP(), level) - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: ["    const rb_num_t level = 0;"],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    96 => Instruction.new(
      name: :getlocal_WC_1,
      bin: 96, # BIN(getlocal_WC_1)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    val = *(vm_get_ep(GET_EP(), level) - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: ["    const rb_num_t level = 1;"],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    97 => Instruction.new(
      name: :setlocal_WC_0,
      bin: 97, # BIN(setlocal_WC_0)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    vm_env_write(vm_get_ep(GET_EP(), level), -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: ["    const rb_num_t level = 0;"],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    98 => Instruction.new(
      name: :setlocal_WC_1,
      bin: 98, # BIN(setlocal_WC_1)
      len: 2, # insn_len
      expr: <<-EXPR,
{
    vm_env_write(vm_get_ep(GET_EP(), level), -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val", "MAYBE_UNUSED(lindex_t) idx", "MAYBE_UNUSED(rb_num_t) level"],
      preamble: ["    const rb_num_t level = 1;"],
      opes: [{:decl=>"lindex_t idx", :type=>"lindex_t", :name=>"idx"}],
      pops: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      rets: [],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    99 => Instruction.new(
      name: :putobject_INT2FIX_0_,
      bin: 99, # BIN(putobject_INT2FIX_0_)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    /* */
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: ["    const VALUE val = INT2FIX(0);"],
      opes: [],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
    100 => Instruction.new(
      name: :putobject_INT2FIX_1_,
      bin: 100, # BIN(putobject_INT2FIX_1_)
      len: 1, # insn_len
      expr: <<-EXPR,
{
    /* */
}
      EXPR
      declarations: ["MAYBE_UNUSED(VALUE) val"],
      preamble: ["    const VALUE val = INT2FIX(1);"],
      opes: [],
      pops: [],
      rets: [{:decl=>"VALUE val", :type=>"VALUE", :name=>"val"}],
      always_leaf?: true,
      leaf_without_check_ints?: false,
      handles_sp?: false,
    ),
  }

  private_constant(*constants)
end
