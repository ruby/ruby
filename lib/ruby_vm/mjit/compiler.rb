# Available variables and macros in JIT-ed function:
#   ec: the first argument of _mjitXXX
#   reg_cfp: the second argument of _mjitXXX
#   GET_CFP(): refers to `reg_cfp`
#   GET_EP(): refers to `reg_cfp->ep`
#   GET_SP(): refers to `reg_cfp->sp`, or `(stack + stack_size)` if local_stack_p
#   GET_SELF(): refers to `cfp_self`
#   GET_LEP(): refers to `VM_EP_LEP(reg_cfp->ep)`
#   EXEC_EC_CFP(): refers to `val = vm_exec(ec, true)` with frame setup
#   CALL_METHOD(): using `GET_CFP()` and `EXEC_EC_CFP()`
#   TOPN(): refers to `reg_cfp->sp`, or `*(stack + (stack_size - num - 1))` if local_stack_p
#   STACK_ADDR_FROM_TOP(): refers to `reg_cfp->sp`, or `stack + (stack_size - num)` if local_stack_p
#   DISPATCH_ORIGINAL_INSN(): expanded in _mjit_compile_insn.erb
#   THROW_EXCEPTION(): specially defined for JIT
#   RESTORE_REGS(): specially defined for `leave`
class RubyVM::MJIT::Compiler # :nodoc: all
  C = RubyVM::MJIT.const_get(:C, false)
  INSNS = RubyVM::MJIT.const_get(:INSNS, false)
  UNSUPPORTED_INSNS = [
    :defineclass, # low priority
  ]

  def initialize = freeze

  # @param iseq [RubyVM::MJIT::CPointer::Struct]
  # @param funcname [String]
  # @param id [Integer]
  # @return [String,NilClass]
  def compile(iseq, funcname, id)
    status = C.compile_status.new # not freed for now
    status.compiled_iseq = iseq.body
    status.compiled_id = id
    init_compile_status(status, iseq.body, true) # not freed for now
    if iseq.body.ci_size > 0 && status.cc_entries_index == -1
      return nil
    end

    src = +''
    if !status.compile_info.disable_send_cache && !status.compile_info.disable_inlining
      unless precompile_inlinable_iseqs(src, iseq, status)
        return nil
      end
    end

    src << "VALUE\n#{funcname}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)\n{\n"
    success = compile_body(src, iseq, status)
    src << "\n} // end of #{funcname}\n"

    return success ? src : nil
  rescue Exception => e # should we use rb_rescue in C instead?
    if C.mjit_opts.warnings || C.mjit_opts.verbose > 0
      $stderr.puts "MJIT error: #{e.full_message}"
    end
    return nil
  end

  private

  def compile_body(src, iseq, status)
    status.success = true
    status.local_stack_p = !iseq.body.catch_except_p

    if status.local_stack_p
      src << "    VALUE stack[#{iseq.body.stack_max}];\n"
    else
      src << "    VALUE *stack = reg_cfp->sp;\n"
    end

    unless status.inlined_iseqs.nil? # i.e. compile root
      src << "    static const rb_iseq_t *original_iseq = (const rb_iseq_t *)#{iseq};\n"
    end
    src << "    static const VALUE *const original_body_iseq = (VALUE *)#{iseq.body.iseq_encoded};\n"

    src << "    VALUE cfp_self = reg_cfp->self;\n" # cache self across the method
    src << "#undef GET_SELF\n"
    src << "#define GET_SELF() cfp_self\n"

    # Simulate `opt_pc` in setup_parameters_complex. Other PCs which may be passed by catch tables
    # are not considered since vm_exec doesn't call jit_exec for catch tables.
    if iseq.body.param.flags.has_opt
      src << "\n"
      src << "    switch (reg_cfp->pc - ISEQ_BODY(reg_cfp->iseq)->iseq_encoded) {\n"
      (0..iseq.body.param.opt_num).each do |i|
        pc_offset = iseq.body.param.opt_table[i]
        src << "      case #{pc_offset}:\n"
        src << "        goto label_#{pc_offset};\n"
      end
      src << "    }\n"
    end

    # Generate merged ivar guards first if needed
    if !status.compile_info.disable_ivar_cache && using_ivar?(iseq.body)
      src << "    if (UNLIKELY(!RB_TYPE_P(GET_SELF(), T_OBJECT))) {"
      src << "        goto ivar_cancel;\n"
      src << "    }\n"
    end

    compile_insns(0, 0, status, iseq.body, src)
    compile_cancel_handler(src, iseq.body, status)
    src << "#undef GET_SELF\n"
    return status.success
  end

  # Compile one conditional branch. If it has branchXXX insn, this should be
  # called multiple times for each branch.
  def compile_insns(stack_size, pos, status, body, src)
    branch = C.compile_branch.new # not freed for now
    branch.stack_size = stack_size
    branch.finish_p = false

    while pos < body.iseq_size && !already_compiled?(status, pos) && !branch.finish_p
      insn = INSNS.fetch(C.rb_vm_insn_decode(body.iseq_encoded[pos]))
      status.stack_size_for_pos[pos] = branch.stack_size

      src << "\nlabel_#{pos}: /* #{insn.name} */\n"
      pos = compile_insn(insn, pos, status, body.iseq_encoded + (pos+1), body, branch, src)
      if status.success && branch.stack_size > body.stack_max
        if mjit_opts.warnings || mjit_opts.verbose > 0
          $stderr.puts "MJIT warning: JIT stack size (#{branch.stack_size}) exceeded its max size (#{body.stack_max})"
        end
        status.success = false
      end
      break unless status.success
    end
  end

  # Main function of JIT compilation, vm_exec_core counterpart for JIT. Compile one insn to `f`, may modify
  # b->stack_size and return next position.
  #
  # When you add a new instruction to insns.def, it would be nice to have JIT compilation support here but
  # it's optional. This JIT compiler just ignores ISeq which includes unknown instruction, and ISeq which
  # does not have it can be compiled as usual.
  def compile_insn(insn, pos, status, operands, body, b, src)
    sp_inc = C.mjit_call_attribute_sp_inc(insn.bin, operands)
    next_pos = pos + insn.len

    result = compile_insn_entry(insn, b.stack_size, sp_inc, status.local_stack_p, pos, next_pos, insn.len,
                                status.inlined_iseqs.nil?, status, operands, body)
    if result.nil?
      if C.mjit_opts.warnings || C.mjit_opts.verbose > 0
        $stderr.puts "MJIT warning: Skipped to compile unsupported instruction: #{insn.name}"
      end
      status.success = false
    else
      result_src, next_pos, finish_p, compile_insns_p = result

      src << result_src
      b.stack_size += sp_inc

      if finish_p
        b.finish_p = true
      end
      if compile_insns_p
        if already_compiled?(status, pos + insn.len)
          src << "goto label_#{pos + insn.len};\n"
        else
          compile_insns(b.stack_size, pos + insn.len, status, body, src)
        end
      end
    end

    # If next_pos is already compiled and this branch is not finished yet,
    # next instruction won't be compiled in C code next and will need `goto`.
    if !b.finish_p && next_pos < body.iseq_size && already_compiled?(status, next_pos)
      src << "goto label_#{next_pos};\n"

      # Verify stack size assumption is the same among multiple branches
      if status.stack_size_for_pos[next_pos] != b.stack_size
        if mjit_opts.warnings || mjit_opts.verbose > 0
          $stderr.puts "MJIT warning: JIT stack assumption is not the same between branches (#{status.stack_size_for_pos[next_pos]} != #{b.stack_size})\n"
        end
        status.success = false
      end
    end

    return next_pos
  end

  def compile_insn_entry(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, insn_len, inlined_iseq_p, status, operands, body)
    finish_p = false
    compile_insns = false

    # TODO: define this outside this method, or at least cache it
    opt_send_without_block = INSNS.values.find { |i| i.name == :opt_send_without_block }
    if opt_send_without_block.nil?
      raise 'opt_send_without_block not found'
    end
    send_compatible_opt_insns = INSNS.values.select do |insn|
      insn.name.start_with?('opt_') && opt_send_without_block.opes == insn.opes &&
        insn.expr.lines.any? { |l| l.match(/\A\s+CALL_SIMPLE_METHOD\(\);\s+\z/) }
    end.map(&:name)

    case insn.name
    when *UNSUPPORTED_INSNS
      return nil
    when :opt_send_without_block, :send
      if src = compile_send(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, status, operands, body)
        return src, next_pos, finish_p, compile_insns
      end
    when *send_compatible_opt_insns
      if C.has_cache_for_send(captured_cc_entries(status)[call_data_index(C.CALL_DATA.new(operands[0]), body)], insn.bin) &&
          src = compile_send(opt_send_without_block, stack_size, sp_inc, local_stack_p, pos, next_pos, status, operands, body)
        return src, next_pos, finish_p, compile_insns
      end
    when :getinstancevariable, :setinstancevariable
      if src = compile_ivar(insn.name, stack_size, pos, status, operands, body)
        return src, next_pos, finish_p, compile_insns
      end
    when :opt_getconstant_path
      if src = compile_getconstant_path(stack_size, pos, insn_len, operands, status)
        return src, next_pos, finish_p, compile_insns
      end
    when :invokebuiltin, :opt_invokebuiltin_delegate, :opt_invokebuiltin_delegate_leave
      if src = compile_invokebuiltin(insn, stack_size, sp_inc, body, operands)
        if insn.name == :opt_invokebuiltin_delegate_leave
          src << compile_leave(stack_size, pos, inlined_iseq_p)
          finish_p = true
        end
        return src, next_pos, finish_p, compile_insns
      end
    when :leave
      if stack_size != 1
        raise "Unexpected JIT stack_size on leave: #{stack_size}"
      end
      src = compile_leave(stack_size, pos, inlined_iseq_p)
      finish_p = true
      return src, next_pos, finish_p, compile_insns
    end

    return compile_insn_default(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, insn_len, inlined_iseq_p, operands)
  end

  # Optimized case of send / opt_send_without_block instructions.
  def compile_send(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, status, operands, body)
    # compiler: Use captured cc to avoid race condition
    cd = C.CALL_DATA.new(operands[0])
    cd_index = call_data_index(cd, body)
    captured_cc = captured_cc_entries(status)[cd_index]

    # compiler: Inline send insn where some supported fastpath is used.
    ci = cd.ci
    kw_splat = (C.vm_ci_flag(ci) & C.VM_CALL_KW_SPLAT) > 0
    if !status.compile_info.disable_send_cache && has_valid_method_type?(captured_cc) && (
        # `CC_SET_FASTPATH(cd->cc, vm_call_cfunc_with_frame, ...)` in `vm_call_cfunc`
        (vm_cc_cme(captured_cc).def.type == C.VM_METHOD_TYPE_CFUNC && !C.rb_splat_or_kwargs_p(ci) && !kw_splat) ||
        # `CC_SET_FASTPATH(cc, vm_call_iseq_setup_func(...), vm_call_iseq_optimizable_p(...))` in `vm_callee_setup_arg`,
        # and support only non-VM_CALL_TAILCALL path inside it
        (vm_cc_cme(captured_cc).def.type == C.VM_METHOD_TYPE_ISEQ &&
         C.fastpath_applied_iseq_p(ci, captured_cc, iseq = def_iseq_ptr(vm_cc_cme(captured_cc).def)) &&
         (C.vm_ci_flag(ci) & C.VM_CALL_TAILCALL) == 0)
    )
      src = +"{\n"

      # JIT: Invalidate call cache if it requires vm_search_method. This allows to inline some of following things.
      src << "    const struct rb_callcache *cc = (struct rb_callcache *)#{captured_cc};\n"
      src << "    const rb_callable_method_entry_t *cc_cme = (rb_callable_method_entry_t *)#{vm_cc_cme(captured_cc)};\n"
      src << "    const VALUE recv = stack[#{stack_size + sp_inc - 1}];\n"
      # If opt_class_of is true, use RBASIC_CLASS instead of CLASS_OF to reduce code size
      opt_class_of = !maybe_special_const?(captured_cc.klass)
      src << "    if (UNLIKELY(#{opt_class_of ? 'RB_SPECIAL_CONST_P(recv)' : 'false'} || !vm_cc_valid_p(cc, cc_cme, #{opt_class_of ? 'RBASIC_CLASS' : 'CLASS_OF'}(recv)))) {\n"
      src << "        reg_cfp->pc = original_body_iseq + #{pos};\n"
      src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
      src << "        goto send_cancel;\n"
      src << "    }\n"

      # JIT: move sp and pc if necessary
      pc_moved_p = compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

      # JIT: If ISeq is inlinable, call the inlined method without pushing a frame.
      if iseq && status.inlined_iseqs && iseq.body.to_i == status.inlined_iseqs[pos]&.to_i
        src << "    {\n"
        src << "        VALUE orig_self = reg_cfp->self;\n"
        src << "        reg_cfp->self = stack[#{stack_size + sp_inc - 1}];\n"
        src << "        stack[#{stack_size + sp_inc - 1}] = _mjit#{status.compiled_id}_inlined_#{pos}(ec, reg_cfp, orig_self, original_iseq);\n"
        src << "        reg_cfp->self = orig_self;\n"
        src << "    }\n"
      else
        # JIT: Forked `vm_sendish` (except method_explorer = vm_search_method_wrap) to inline various things
        src << "    {\n"
        src << "        VALUE val;\n"
        src << "        struct rb_calling_info calling;\n"
        if insn.name == :send
          src << "        calling.block_handler = vm_caller_setup_arg_block(ec, reg_cfp, (const struct rb_callinfo *)#{ci}, (rb_iseq_t *)0x#{operands[1].to_s(16)}, FALSE);\n"
        else
          src << "        calling.block_handler = VM_BLOCK_HANDLER_NONE;\n"
        end
        src << "        calling.kw_splat = #{kw_splat ? 1 : 0};\n"
        src << "        calling.recv = stack[#{stack_size + sp_inc - 1}];\n"
        src << "        calling.argc = #{C.vm_ci_argc(ci)};\n"

        if vm_cc_cme(captured_cc).def.type == C.VM_METHOD_TYPE_CFUNC
          # TODO: optimize this more
          src << "        calling.ci = (const struct rb_callinfo *)#{ci};\n" # creating local cd here because operand's cd->cc may not be the same as inlined cc.
          src << "        calling.cc = cc;"
          src << "        val = vm_call_cfunc_with_frame(ec, reg_cfp, &calling);\n"
        else # :iseq
          # fastpath_applied_iseq_p checks rb_simple_iseq_p, which ensures has_opt == FALSE
          src << "        vm_call_iseq_setup_normal(ec, reg_cfp, &calling, cc_cme, 0, #{iseq.body.param.size}, #{iseq.body.local_table_size});\n"
          if iseq.body.catch_except_p
            src << "        VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH);\n"
            src << "        val = vm_exec(ec, true);\n"
          else
            src << "        if ((val = jit_exec(ec)) == Qundef) {\n"
            src << "            VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH);\n" # This is vm_call0_body's code after vm_call_iseq_setup
            src << "            val = vm_exec(ec, false);\n"
            src << "        }\n"
          end
        end
        src << "        stack[#{stack_size + sp_inc - 1}] = val;\n"
        src << "    }\n"

        # JIT: We should evaluate ISeq modified for TracePoint if it's enabled. Note: This is slow.
        src << "    if (UNLIKELY(!mjit_call_p)) {\n"
        src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size + sp_inc};\n"
        if !pc_moved_p
          src << "        reg_cfp->pc = original_body_iseq + #{next_pos};\n"
        end
        src << "        goto cancel;\n"
        src << "    }\n"
      end

      src << "}\n"
      return src
    else
      return nil
    end
  end

  def compile_ivar(insn_name, stack_size, pos, status, operands, body)
    iv_cache = C.iseq_inline_storage_entry.new(operands[1]).iv_cache
    dest_shape_id = iv_cache.value >> C.SHAPE_FLAG_SHIFT
    source_shape_id = parent_shape_id(dest_shape_id)
    attr_index = iv_cache.value & ((1 << C.SHAPE_FLAG_SHIFT) - 1)

    src = +''
    if !status.compile_info.disable_ivar_cache && source_shape_id != C.INVALID_SHAPE_ID
      # JIT: optimize away motion of sp and pc. This path does not call rb_warning() and so it's always leaf and not `handles_sp`.
      # compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

      # JIT: prepare vm_getivar/vm_setivar arguments and variables
      src << "{\n"
      src << "    VALUE obj = GET_SELF();\n" # T_OBJECT guaranteed by compile_body
      # JIT: cache hit path of vm_getivar/vm_setivar, or cancel JIT (recompile it with exivar)
      if insn_name == :setinstancevariable
        src << "    const uint32_t index = #{attr_index - 1};\n"
        src << "    const shape_id_t dest_shape_id = (shape_id_t)#{dest_shape_id};\n"
        src << "    if (dest_shape_id == ROBJECT_SHAPE_ID(obj)) {\n"
        src << "        VALUE *ptr = ROBJECT_IVPTR(obj);\n"
        src << "        RB_OBJ_WRITE(obj, &ptr[index], stack[#{stack_size - 1}]);\n"
        src << "    }\n"
      else
        src << "    const shape_id_t source_shape_id = (shape_id_t)#{dest_shape_id};\n"
        if attr_index == 0 # cache hit, but uninitialized iv
          src << "    /* Uninitialized instance variable */\n"
          src << "    if (source_shape_id == ROBJECT_SHAPE_ID(obj)) {\n"
          src << "        stack[#{stack_size}] = Qnil;\n"
          src << "    }\n"
        else
          src << "    const uint32_t index = #{attr_index - 1};\n"
          src << "    if (source_shape_id == ROBJECT_SHAPE_ID(obj)) {\n"
          src << "        stack[#{stack_size}] = ROBJECT_IVPTR(obj)[index];\n"
          src << "    }\n"
        end
      end
      src << "    else {\n"
      src << "        reg_cfp->pc = original_body_iseq + #{pos};\n"
      src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
      src << "        goto ivar_cancel;\n"
      src << "    }\n"
      src << "}\n"
      return src
    elsif insn_name == :getinstancevariable && !status.compile_info.disable_exivar_cache && source_shape_id != C.INVALID_SHAPE_ID
      # JIT: optimize away motion of sp and pc. This path does not call rb_warning() and so it's always leaf and not `handles_sp`.
      # compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

      # JIT: prepare vm_getivar's arguments and variables
      src << "{\n"
      src << "    VALUE obj = GET_SELF();\n"
      src << "    const shape_id_t source_shape_id = (shape_id_t)#{dest_shape_id};\n"
      src << "    const uint32_t index = #{attr_index - 1};\n"
      # JIT: cache hit path of vm_getivar, or cancel JIT (recompile it without any ivar optimization)
      src << "    struct gen_ivtbl *ivtbl;\n"
      src << "    if (LIKELY(FL_TEST_RAW(GET_SELF(), FL_EXIVAR) && source_shape_id == rb_shape_get_shape_id(obj) && rb_ivar_generic_ivtbl_lookup(obj, &ivtbl))) {\n"
      src << "        stack[#{stack_size}] = ivtbl->ivptr[index];\n"
      src << "    }\n"
      src << "    else {\n"
      src << "        reg_cfp->pc = original_body_iseq + #{pos};\n"
      src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
      src << "        goto exivar_cancel;\n"
      src << "    }\n"
      src << "}\n"
      return src
    else
      return nil
    end
  end

  def compile_invokebuiltin(insn, stack_size, sp_inc, body, operands)
    bf = C.RB_BUILTIN.new(operands[0])
    if bf.compiler > 0
      index = (insn.name == :invokebuiltin ? -1 : operands[1])
      src = +"{\n"
      src << "    VALUE val;\n"
      C.builtin_compiler(src, bf, index, stack_size, body.builtin_inline_p)
      src << "    stack[#{stack_size + sp_inc - 1}] = val;\n"
      src << "}\n"
      return src
    else
      return nil
    end
  end

  def compile_leave(stack_size, pos, inlined_iseq_p)
    src = +''
    # Skip vm_pop_frame for inlined call
    unless inlined_iseq_p
      # Cancel on interrupts to make leave insn leaf
      src << "    if (UNLIKELY(RUBY_VM_INTERRUPTED_ANY(ec))) {\n"
      src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
      src << "        reg_cfp->pc = original_body_iseq + #{pos};\n"
      src << "        rb_threadptr_execute_interrupts(rb_ec_thread_ptr(ec), 0);\n"
      src << "    }\n"
      src << "    ec->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(reg_cfp);\n" # vm_pop_frame
    end
    src << "    return stack[0];\n"
  end

  def compile_getconstant_path(stack_size, pos, insn_len, operands, status)
    ice = C.IC.new(operands[0]).entry
    if !status.compile_info.disable_const_cache && ice
      # JIT: Inline everything in IC, and cancel the slow path
      src = +"    if (vm_inlined_ic_hit_p(#{ice.flags}, #{ice.value}, (const rb_cref_t *)#{to_addr(ice.ic_cref)}, reg_cfp->ep)) {\n"
      src << "        stack[#{stack_size}] = #{ice.value};\n"
      src << "    }\n"
      src << "    else {\n"
      src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
      src << "        reg_cfp->pc = original_body_iseq + #{pos};\n"
      src << "        goto const_cancel;\n"
      src << "    }\n"
      return src
    else
      return nil
    end
  end

  def compile_insn_default(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, insn_len, inlined_iseq_p, operands)
    src = +''
    finish_p = false
    compile_insns = false

    # JIT: Declare stack_size to be used in some macro of _mjit_compile_insn_body.erb
    src << "{\n"
    if local_stack_p
      src << "    MAYBE_UNUSED(unsigned int) stack_size = #{stack_size};\n"
    end

    # JIT: Declare variables for operands, popped values and return values
    insn.declarations.each do |decl|
      src << "    #{decl};\n"
    end

    # JIT: Set const expressions for `RubyVM::OperandsUnifications` insn
    insn.preamble.each do |amble|
      src << "#{amble.sub(/const \S+\s+/, '')}\n"
    end

    # JIT: Initialize operands
    insn.opes.each_with_index do |ope, i|
      src << "    #{ope.fetch(:name)} = (#{ope.fetch(:type)})#{operands[i]};\n"
      # TODO: resurrect comment_id
    end

    # JIT: Initialize popped values
    insn.pops.reverse_each.with_index.reverse_each do |pop, i|
      src << "    #{pop.fetch(:name)} = stack[#{stack_size - (i + 1)}];\n"
    end

    # JIT: move sp and pc if necessary
    pc_moved_p = compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

    # JIT: Print insn body in insns.def
    next_pos = compile_insn_body(src, insn, pos, next_pos, insn_len, local_stack_p, stack_size, sp_inc, operands)

    # JIT: Set return values
    insn.rets.reverse_each.with_index do |ret, i|
      # TOPN(n) = ...
      src << "    stack[#{stack_size + sp_inc - (i + 1)}] = #{ret.fetch(:name)};\n"
    end

    # JIT: We should evaluate ISeq modified for TracePoint if it's enabled. Note: This is slow.
    #      leaf insn may not cancel JIT. leaf_without_check_ints is covered in RUBY_VM_CHECK_INTS of _mjit_compile_insn_body.erb.
    unless insn.always_leaf? || insn.leaf_without_check_ints?
      src << "    if (UNLIKELY(!mjit_call_p)) {\n"
      src << "        reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size + sp_inc};\n"
      if !pc_moved_p
        src << "        reg_cfp->pc = original_body_iseq + #{next_pos};\n"
      end
      src << "        goto cancel;\n"
      src << "    }\n"
    end

    src << "}\n"

    # compiler: If insn has conditional JUMP, the code should go to the branch not targeted by JUMP next.
    if insn.expr.match?(/if\s+\([^{}]+\)\s+\{[^{}]+JUMP\([^)]+\);[^{}]+\}/)
      compile_insns = true
    end

    # compiler: If insn returns (leave) or does longjmp (throw), the branch should no longer be compiled. TODO: create attr for it?
    if insn.expr.match?(/\sTHROW_EXCEPTION\([^)]+\);/) || insn.expr.match?(/\bvm_pop_frame\(/)
      finish_p = true
    end

    return src, next_pos, finish_p, compile_insns
  end

  def compile_insn_body(src, insn, pos, next_pos, insn_len, local_stack_p, stack_size, sp_inc, operands)
    # Print a body of insn, but with macro expansion.
    expand_simple_macros(insn.expr).each_line do |line|
      # Expand dynamic macro here
      # TODO: support combination of following macros in the same line
      case line
      when /\A\s+RUBY_VM_CHECK_INTS\(ec\);\s+\z/
        if insn.leaf_without_check_ints? # lazily move PC and optionalize mjit_call_p here
          src << "            if (UNLIKELY(RUBY_VM_INTERRUPTED_ANY(ec))) {\n"
          src << "                reg_cfp->pc = original_body_iseq + #{next_pos};\n" # ADD_PC(INSN_ATTR(width));
          src << "                rb_threadptr_execute_interrupts(rb_ec_thread_ptr(ec), 0);\n"
          src << "                if (UNLIKELY(!mjit_call_p)) {\n"
          src << "                    reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
          src << "                    goto cancel;\n"
          src << "                }\n"
          src << "            }\n"
        else
          src << to_cstr(line)
        end
      when /\A\s+JUMP\((?<dest>[^)]+)\);\s+\z/
        dest = Regexp.last_match[:dest]
        if insn.name == :opt_case_dispatch # special case... TODO: use another macro to avoid checking name
          hash_offsets = C.rb_hash_values(operands[0]).uniq
          else_offset = cast_offset(operands[1])
          base_pos = pos + insn_len

          src << "    switch (#{dest}) {\n"
          hash_offsets.each do |offset|
            src << "      case #{offset}:\n"
            src << "        goto label_#{base_pos + offset};\n"
          end
          src << "      case #{else_offset}:\n"
          src << "        goto label_#{base_pos + else_offset};\n"
          src << "    }\n"
        else
          # Before we `goto` next insn, we need to set return values, especially for getinlinecache
          insn.rets.reverse_each.with_index do |ret, i|
            # TOPN(n) = ...
            src << "            stack[#{stack_size + sp_inc - (i + 1)}] = #{ret.fetch(:name)};\n"
          end

          next_pos = pos + insn_len + cast_offset(operands[0]) # workaround: assuming dest == operands[0]. TODO: avoid relying on it
          src << "            goto label_#{next_pos};\n"
        end
      when /\A\s+CALL_SIMPLE_METHOD\(\);\s+\z/
        # For `opt_xxx`'s fallbacks.
        if local_stack_p
          src << "            reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
        end
        src << "            reg_cfp->pc = original_body_iseq + #{pos};\n"
        src << "            goto cancel;\n"
      when /\A(?<prefix>.+\b)INSN_LABEL\((?<name>[^)]+)\)(?<suffix>.+)\z/m
        prefix, name, suffix = Regexp.last_match[:prefix], Regexp.last_match[:name], Regexp.last_match[:suffix]
        src << "#{prefix}INSN_LABEL(#{name}_#{pos})#{suffix}"
      else
        if insn.handles_sp?
          # If insn.handles_sp? is true, cfp->sp might be changed inside insns (like vm_caller_setup_arg_block)
          # and thus we need to use cfp->sp, even when local_stack_p is TRUE. When insn.handles_sp? is true,
          # cfp->sp should be available too because _mjit_compile_pc_and_sp.erb sets it.
          src << to_cstr(line)
        else
          # If local_stack_p is TRUE and insn.handles_sp? is false, stack values are only available in local variables
          # for stack. So we need to replace those macros if local_stack_p is TRUE here.
          case line
          when /\bGET_SP\(\)/
            # reg_cfp->sp
            src << to_cstr(line.sub(/\bGET_SP\(\)/, local_stack_p ? '(stack + stack_size)' : 'GET_SP()'))
          when /\bSTACK_ADDR_FROM_TOP\((?<num>[^)]+)\)/
            # #define STACK_ADDR_FROM_TOP(n) (GET_SP()-(n))
            num = Regexp.last_match[:num]
            src << to_cstr(line.sub(/\bSTACK_ADDR_FROM_TOP\(([^)]+)\)/, local_stack_p ? "(stack + (stack_size - (#{num})))" : "STACK_ADDR_FROM_TOP(#{num})"))
          when /\bTOPN\((?<num>[^)]+)\)/
            # #define TOPN(n) (*(GET_SP()-(n)-1))
            num = Regexp.last_match[:num]
            src << to_cstr(line.sub(/\bTOPN\(([^)]+)\)/, local_stack_p ? "*(stack + (stack_size - (#{num}) - 1))" : "TOPN(#{num})"))
          else
            src << to_cstr(line)
          end
        end
      end
    end
    return next_pos
  end

  def compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)
    # JIT: When an insn is leaf, we don't need to Move pc for a catch table on catch_except_p, #caller_locations,
    #      and rb_profile_frames. For check_ints, we lazily move PC when we have interruptions.
    pc_moved_p = false
    unless insn.always_leaf? || insn.leaf_without_check_ints?
      src << "    reg_cfp->pc = original_body_iseq + #{next_pos};\n" # ADD_PC(INSN_ATTR(width));
      pc_moved_p = true
    end

    # JIT: move sp to use or preserve stack variables
    if local_stack_p
      # sp motion is optimized away for `handles_sp? #=> false` case.
      # Thus sp should be set properly before `goto cancel`.
      if insn.handles_sp?
        # JIT-only behavior (pushing JIT's local variables to VM's stack):
        push_size = -sp_inc + insn.rets.size - insn.pops.size
        src << "    reg_cfp->sp = vm_base_ptr(reg_cfp) + #{push_size};\n"
        push_size.times do |i|
          src << "    *(reg_cfp->sp + #{i - push_size}) = stack[#{stack_size - push_size + i}];\n"
        end
      end
    else
      if insn.handles_sp?
        src << "    reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size - insn.pops.size};\n" # POPN(INSN_ATTR(popn));
      else
        src << "    reg_cfp->sp = vm_base_ptr(reg_cfp) + #{stack_size};\n"
      end
    end
    return pc_moved_p
  end

  # Print the block to cancel inlined method call. It's supporting only `opt_send_without_block` for now.
  def compile_inlined_cancel_handler(src, body, inline_context)
    src << "\ncancel:\n"
    src << "    rb_mjit_recompile_inlining(original_iseq);\n"

    # Swap pc/sp set on cancel with original pc/sp.
    src << "    const VALUE *current_pc = reg_cfp->pc;\n"
    src << "    VALUE *current_sp = reg_cfp->sp;\n"
    src << "    reg_cfp->pc = orig_pc;\n"
    src << "    reg_cfp->sp = orig_sp;\n\n"

    # Lazily push the current call frame.
    src << "    struct rb_calling_info calling;\n"
    src << "    calling.block_handler = VM_BLOCK_HANDLER_NONE;\n" # assumes `opt_send_without_block`
    src << "    calling.argc = #{inline_context.orig_argc};\n"
    src << "    calling.recv = reg_cfp->self;\n"
    src << "    reg_cfp->self = orig_self;\n"
    # fastpath_applied_iseq_p checks rb_simple_iseq_p, which ensures has_opt == FALSE
    src << "    vm_call_iseq_setup_normal(ec, reg_cfp, &calling, (const rb_callable_method_entry_t *)#{inline_context.me}, 0, #{inline_context.param_size}, #{inline_context.local_size});\n\n"

    # Start usual cancel from here.
    src << "    reg_cfp = ec->cfp;\n" # work on the new frame
    src << "    reg_cfp->pc = current_pc;\n"
    src << "    reg_cfp->sp = current_sp;\n"
    (0...body.stack_max).each do |i| # should be always `status->local_stack_p`
      src << "    *(vm_base_ptr(reg_cfp) + #{i}) = stack[#{i}];\n"
    end
    # We're not just returning Qundef here so that caller's normal cancel handler can
    # push back `stack` to `cfp->sp`.
    src << "    return vm_exec(ec, false);\n"
  end

  # Print the block to cancel JIT execution.
  def compile_cancel_handler(src, body, status)
    if status.inlined_iseqs.nil? # the current ISeq is being inlined
      compile_inlined_cancel_handler(src, body, status.inline_context)
      return
    end

    src << "\nsend_cancel:\n"
    src << "    rb_mjit_recompile_send(original_iseq);\n"
    src << "    goto cancel;\n"

    src << "\nivar_cancel:\n"
    src << "    rb_mjit_recompile_ivar(original_iseq);\n"
    src << "    goto cancel;\n"

    src << "\nexivar_cancel:\n"
    src << "    rb_mjit_recompile_exivar(original_iseq);\n"
    src << "    goto cancel;\n"

    src << "\nconst_cancel:\n"
    src << "    rb_mjit_recompile_const(original_iseq);\n"
    src << "    goto cancel;\n"

    src << "\ncancel:\n"
    if status.local_stack_p
      (0...body.stack_max).each do |i|
        src << "    *(vm_base_ptr(reg_cfp) + #{i}) = stack[#{i}];\n"
      end
    end
    src << "    return Qundef;\n"
  end

  def precompile_inlinable_child_iseq(src, child_iseq, status, ci, cc, pos)
    child_status = C.compile_status.new # not freed for now
    child_status.compiled_iseq = status.compiled_iseq
    child_status.compiled_id = status.compiled_id
    init_compile_status(child_status, child_iseq.body, false) # not freed for now
    child_status.inline_context.orig_argc = C.vm_ci_argc(ci)
    child_status.inline_context.me = vm_cc_cme(cc).to_i
    child_status.inline_context.param_size = child_iseq.body.param.size
    child_status.inline_context.local_size = child_iseq.body.local_table_size
    if child_iseq.body.ci_size > 0 && child_status.cc_entries_index == -1
      return false
    end

    src << "ALWAYS_INLINE(static VALUE _mjit#{status.compiled_id}_inlined_#{pos}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE orig_self, const rb_iseq_t *original_iseq));\n"
    src << "static inline VALUE\n_mjit#{status.compiled_id}_inlined_#{pos}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE orig_self, const rb_iseq_t *original_iseq)\n{\n"
    src << "    const VALUE *orig_pc = reg_cfp->pc;\n"
    src << "    VALUE *orig_sp = reg_cfp->sp;\n"

    success = compile_body(src, child_iseq, child_status)

    src << "\n} /* end of _mjit#{status.compiled_id}_inlined_#{pos} */\n\n"

    return success;
  end

  def precompile_inlinable_iseqs(src, iseq, status)
    body = iseq.body
    pos = 0
    while pos < body.iseq_size
      insn = INSNS.fetch(C.rb_vm_insn_decode(body.iseq_encoded[pos]))
      if insn.name == :opt_send_without_block || insn.name == :opt_size # `compile_inlined_cancel_handler` supports only `opt_send_without_block`
        cd = C.CALL_DATA.new(body.iseq_encoded[pos + 1])
        ci = cd.ci
        cc = captured_cc_entries(status)[call_data_index(cd, body)] # use copy to avoid race condition

        if (child_iseq = rb_mjit_inlinable_iseq(ci, cc)) != nil
          status.inlined_iseqs[pos] = child_iseq.body

          if C.mjit_opts.verbose >= 1 # print beforehand because ISeq may be GCed during copy job.
            child_location = child_iseq.body.location
            $stderr.puts "JIT inline: #{child_location.label}@#{C.rb_iseq_path(child_iseq)}:#{C.rb_iseq_first_lineno(child_iseq)} " \
              "=> #{iseq.body.location.label}@#{C.rb_iseq_path(iseq)}:#{C.rb_iseq_first_lineno(iseq)}"
          end
          if !precompile_inlinable_child_iseq(src, child_iseq, status, ci, cc, pos)
            return false
          end
        end
      end
      pos += insn.len
    end
    return true
  end

  def init_compile_status(status, body, compile_root_p)
    status.stack_size_for_pos = Fiddle.malloc(Fiddle::SIZEOF_INT * body.iseq_size)
    body.iseq_size.times do |i|
      status.stack_size_for_pos[i] = C.NOT_COMPILED_STACK_SIZE
    end
    if compile_root_p
      status.inlined_iseqs = Fiddle.malloc(Fiddle::SIZEOF_VOIDP * body.iseq_size)
      body.iseq_size.times do |i|
        status.inlined_iseqs[i] = nil
      end
    end
    if body.ci_size > 0
      status.cc_entries_index = C.mjit_capture_cc_entries(status.compiled_iseq, body)
    else
      status.cc_entries_index = -1
    end
    if compile_root_p
      status.compile_info = rb_mjit_iseq_compile_info(body)
    else
      status.compile_info = Fiddle.malloc(C.rb_mjit_compile_info.sizeof)
      status.compile_info.disable_ivar_cache = false
      status.compile_info.disable_exivar_cache = false
      status.compile_info.disable_send_cache = false
      status.compile_info.disable_inlining = false
      status.compile_info.disable_const_cache = false
    end
  end

  def using_ivar?(body)
    pos = 0
    while pos < body.iseq_size
      insn = INSNS.fetch(C.rb_vm_insn_decode(body.iseq_encoded[pos]))
      case insn.name
      when :getinstancevariable, :setinstancevariable
        return true
      end
      pos += insn.len
    end
    return false
  end

  # Expand simple macro that doesn't require dynamic C code.
  def expand_simple_macros(arg_expr)
    arg_expr.dup.tap do |expr|
      # For `leave`. We can't proceed next ISeq in the same JIT function.
      expr.gsub!(/^(?<indent>\s*)RESTORE_REGS\(\);\n/) do
        indent = Regexp.last_match[:indent]
        <<-end.gsub(/^ {12}/, '')
          #if OPT_CALL_THREADED_CODE
          #{indent}rb_ec_thread_ptr(ec)->retval = val;
          #{indent}return 0;
          #else
          #{indent}return val;
          #endif
        end
      end
      expr.gsub!(/^(?<indent>\s*)NEXT_INSN\(\);\n/) do
        indent = Regexp.last_match[:indent]
        <<-end.gsub(/^ {12}/, '')
          #{indent}UNREACHABLE_RETURN(Qundef);
        end
      end
    end
  end

  def to_cstr(expr)
    expr.gsub(/^(?!#)/, '    ') # indent everything but preprocessor lines
  end

  # Interpret unsigned long as signed long (VALUE -> OFFSET)
  def cast_offset(offset)
    if offset >= 1 << 8 * Fiddle::SIZEOF_VOIDP - 1 # negative
      offset -= 1 << 8 * Fiddle::SIZEOF_VOIDP
    end
    offset
  end

  def captured_cc_entries(status)
    status.compiled_iseq.mjit_unit.cc_entries + status.cc_entries_index
  end

  def call_data_index(cd, body)
    cd - body.call_data
  end

  def vm_cc_cme(cc)
    # TODO: add VM_ASSERT like actual vm_cc_cme
    cc.cme_
  end

  def def_iseq_ptr(method_def)
    C.rb_iseq_check(method_def.body.iseq.iseqptr)
  end

  def rb_mjit_iseq_compile_info(body)
    body.mjit_unit.compile_info
  end

  def ISEQ_IS_SIZE(body)
    body.ic_size + body.ivc_size + body.ise_size + body.icvarc_size
  end

  # Return true if an object of the class may be a special const (immediate).
  # It's "maybe" because Integer and Float are not guaranteed to be an immediate.
  # If this returns false, rb_class_of could be optimzied to RBASIC_CLASS.
  def maybe_special_const?(klass)
    [
      C.rb_cFalseClass,
      C.rb_cNilClass,
      C.rb_cTrueClass,
      C.rb_cInteger,
      C.rb_cSymbol,
      C.rb_cFloat,
    ].include?(klass)
  end

  def has_valid_method_type?(cc)
    vm_cc_cme(cc) != nil
  end

  def already_compiled?(status, pos)
    status.stack_size_for_pos[pos] != C.NOT_COMPILED_STACK_SIZE
  end

  # Return an iseq pointer if cc has inlinable iseq.
  def rb_mjit_inlinable_iseq(ci, cc)
    if has_valid_method_type?(cc) &&
        C.vm_ci_flag(ci) & C.VM_CALL_TAILCALL == 0 && # inlining only non-tailcall path
        vm_cc_cme(cc).def.type == C.VM_METHOD_TYPE_ISEQ &&
        C.fastpath_applied_iseq_p(ci, cc, iseq = def_iseq_ptr(vm_cc_cme(cc).def)) &&
        inlinable_iseq_p(iseq.body) # CC_SET_FASTPATH in vm_callee_setup_arg
      return iseq
    end
    return nil
  end

  # Return true if the ISeq can be inlined without pushing a new control frame.
  def inlinable_iseq_p(body)
    # 1) If catch_except_p, caller frame should be preserved when callee catches an exception.
    # Then we need to wrap `vm_exec()` but then we can't inline the call inside it.
    #
    # 2) If `body->catch_except_p` is false and `handles_sp?` of an insn is false,
    # sp is not moved as we assume `status->local_stack_p = !body->catch_except_p`.
    #
    # 3) If `body->catch_except_p` is false and `always_leaf?` of an insn is true,
    # pc is not moved.
    if body.catch_except_p
      return false
    end

    pos = 0
    while pos < body.iseq_size
      insn = INSNS.fetch(C.rb_vm_insn_decode(body.iseq_encoded[pos]))
      # All insns in the ISeq except `leave` (to be overridden in the inlined code)
      # should meet following strong assumptions:
      #   * Do not require `cfp->sp` motion
      #   * Do not move `cfp->pc`
      #   * Do not read any `cfp->pc`
      if insn.name == :invokebuiltin || insn.name == :opt_invokebuiltin_delegate || insn.name == :opt_invokebuiltin_delegate_leave
        # builtin insn's inlinability is handled by `Primitive.attr! 'inline'` per iseq
        if !body.builtin_inline_p
          return false;
        end
      elsif insn.name != :leave && C.insn_may_depend_on_sp_or_pc(insn.bin, body.iseq_encoded + (pos + 1))
        return false
      end
      # At this moment, `cfp->ep` in an inlined method is not working.
      case insn.name
      when :getlocal,
           :getlocal_WC_0,
           :getlocal_WC_1,
           :setlocal,
           :setlocal_WC_0,
           :setlocal_WC_1,
           :getblockparam,
           :getblockparamproxy,
           :setblockparam
        return false
      end
      pos += insn.len
    end
    return true
  end

  # CPointer::Struct could be nil on field reference, and this is a helper to
  # handle that case while using CPointer::Struct#to_s in most cases.
  # @param struct [RubyVM::MJIT::CPointer::Struct]
  def to_addr(struct)
    struct&.to_s || 'NULL'
  end

  def parent_shape_id(shape_id)
    return shape_id if shape_id == C.INVALID_SHAPE_ID

    parent_id = C.rb_shape_get_shape_by_id(shape_id).parent_id
    parent = C.rb_shape_get_shape_by_id(parent_id)

    if parent.type == C.SHAPE_CAPACITY_CHANGE
      parent.parent_id
    else
      parent_id
    end
  end
end
