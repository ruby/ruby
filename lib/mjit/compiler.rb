module RubyVM::MJIT
  USE_RVARGC = C.USE_RVARGC
  ROBJECT_EMBED_LEN_MAX = C.ROBJECT_EMBED_LEN_MAX

  UNSUPPORTED_INSNS = [
    :defineclass, # low priority
  ]

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
  class << Compiler = Module.new
    # mjit_compile
    # @param funcname [String]
    def compile(f, iseq, funcname, id)
      status = C.compile_status.new # not freed for now
      status.compiled_iseq = iseq.body
      status.compiled_id = id
      init_compile_status(status, iseq.body, true) # not freed for now
      if iseq.body.ci_size > 0 && status.cc_entries_index == -1
        return false
      end

      init_ivar_compile_status(iseq.body, status)

      if !status.compile_info.disable_send_cache && !status.compile_info.disable_inlining
        unless precompile_inlinable_iseqs(f, iseq, status)
          return false
        end
      end

      C.fprintf(f, "VALUE\n#{funcname}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)\n{\n")
      success = compile_body(f, iseq, status)
      C.fprintf(f, "\n} // end of #{funcname}\n")

      return success
    rescue => e # Should rb_rescue be called in C?
      if C.mjit_opts.warnings || C.mjit_opts.verbose > 0
        $stderr.puts e.full_message
      end
      return false
    end

    # mjit_compile_body
    def compile_body(f, iseq, status)
      status.success = true
      status.local_stack_p = !iseq.body.catch_except_p

      if status.local_stack_p
        src = +"    VALUE stack[#{iseq.body.stack_max}];\n"
      else
        src = +"    VALUE *stack = reg_cfp->sp;\n"
      end

      unless status.inlined_iseqs.nil? # i.e. compile root
        src << "    static const rb_iseq_t *original_iseq = (const rb_iseq_t *)#{iseq};\n"
      end
      src << "    static const VALUE *const original_body_iseq = (VALUE *)#{iseq.body.iseq_encoded};\n"

      src << "    VALUE cfp_self = reg_cfp->self;\n" # cache self across the method
      src << "#undef GET_SELF\n"
      src << "#define GET_SELF() cfp_self\n"

      # Generate merged ivar guards first if needed
      if !status.compile_info.disable_ivar_cache && status.merge_ivar_guards_p
        src << "    if (UNLIKELY(!(RB_TYPE_P(GET_SELF(), T_OBJECT) && (rb_serial_t)#{status.ivar_serial} == RCLASS_SERIAL(RBASIC(GET_SELF())->klass) &&"
        if USE_RVARGC
          src << "#{status.max_ivar_index} < ROBJECT_NUMIV(GET_SELF())" # index < ROBJECT_NUMIV(obj)
        else
          if status.max_ivar_index >= ROBJECT_EMBED_LEN_MAX
            src << "#{status.max_ivar_index} < ROBJECT_NUMIV(GET_SELF())" # index < ROBJECT_NUMIV(obj) && !RB_FL_ANY_RAW(obj, ROBJECT_EMBED)
          else
            src << "ROBJECT_EMBED_LEN_MAX == ROBJECT_NUMIV(GET_SELF())" # index < ROBJECT_NUMIV(obj) && RB_FL_ANY_RAW(obj, ROBJECT_EMBED)
          end
        end
        src << "))) {\n"
        src << "        goto ivar_cancel;\n"
        src << "    }\n"
      end

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

      C.fprintf(f, src)
      compile_insns(0, 0, status, iseq.body, f)
      compile_cancel_handler(f, iseq.body, status)
      C.fprintf(f, "#undef GET_SELF\n")
      return status.success
    end

    # Compile one conditional branch. If it has branchXXX insn, this should be
    # called multiple times for each branch.
    def compile_insns(stack_size, pos, status, body, f)
      branch = C.compile_branch.new # not freed for now
      branch.stack_size = stack_size
      branch.finish_p = false

      while pos < body.iseq_size && !already_compiled?(status, pos) && !branch.finish_p
        insn = INSNS.fetch(C.rb_vm_insn_decode(body.iseq_encoded[pos]))
        status.stack_size_for_pos[pos] = branch.stack_size

        C.fprintf(f, "\nlabel_#{pos}: /* #{insn.name} */\n")
        pos = compile_insn(insn, pos, status, body.iseq_encoded + (pos+1), body, branch, f)
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
    def compile_insn(insn, pos, status, operands, body, b, f)
      sp_inc = C.mjit_call_attribute_sp_inc(insn.bin, operands)
      next_pos = pos + insn.len

      result = compile_insn_entry(f, insn, b.stack_size, sp_inc, status.local_stack_p, pos, next_pos, insn.len,
                                  status.inlined_iseqs.nil?, status, operands, body)
      if result.nil?
        if C.mjit_opts.warnings || C.mjit_opts.verbose > 0
          $stderr.puts "MJIT warning: Skipped to compile unsupported instruction: #{insn.name}"
        end
        status.success = false
      else
        src, next_pos, finish_p, compile_insns_p = result

        C.fprintf(f, src)
        b.stack_size += sp_inc

        if finish_p
          b.finish_p = true
        end
        if compile_insns_p
          if already_compiled?(status, pos + insn.len)
            C.fprintf(f, "goto label_#{pos + insn.len};\n")
          else
            compile_insns(b.stack_size, pos + insn.len, status, body, f)
          end
        end
      end

      # If next_pos is already compiled and this branch is not finished yet,
      # next instruction won't be compiled in C code next and will need `goto`.
      if !b.finish_p && next_pos < body.iseq_size && already_compiled?(status, next_pos)
        C.fprintf(f, "goto label_#{next_pos};\n")

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

    # mjit_comiple.inc.erb
    def compile_insn_entry(f, insn, stack_size, sp_inc, local_stack_p, pos, next_pos, insn_len, inlined_iseq_p, status, operands, body)
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
      when :invokebuiltin, :opt_invokebuiltin_delegate
        if compile_invokebuiltin(f, insn, stack_size, sp_inc, body, operands)
          return '', next_pos, finish_p, compile_insns
        end
      when :opt_getconstant_path
        if src = compile_getconstant_path(stack_size, pos, insn_len, operands, status)
          return src, next_pos, finish_p, compile_insns
        end
      when :leave, :opt_invokebuiltin_delegate_leave
        src = +''

        # opt_invokebuiltin_delegate_leave also implements leave insn. We need to handle it here for inlining.
        if insn.name == :opt_invokebuiltin_delegate_leave
          compile_invokebuiltin(f, insn, stack_size, sp_inc, body, operands)
        else
          if stack_size != 1
            $stderr.puts "MJIT warning: Unexpected JIT stack_size on leave: #{stack_size}" # TODO: check mjit_opts?
            return nil
          end
        end

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
        finish_p = true
        return src, next_pos, finish_p, compile_insns
      end

      return compile_insn_default(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, insn_len, inlined_iseq_p, operands)
    rescue => e
      puts e.full_message
      nil
    end

    private

    # Optimized case of send / opt_send_without_block instructions.
    # _mjit_compile_send.erb
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
          src << "        RB_DEBUG_COUNTER_INC(mjit_cancel_invalidate_all);\n"
          src << "        goto cancel;\n"
          src << "    }\n"
        end

        src << "}\n"
        return src
      else
        return nil
      end
    end

    # _mjit_compile_ivar.erb
    def compile_ivar(insn_name, stack_size, pos, status, operands, body)
      ic_copy = (status.is_entries + (C.iseq_inline_storage_entry.new(operands[1]) - body.is_entries)).iv_cache

      src = +''
      if !status.compile_info.disable_ivar_cache && ic_copy.entry
        # JIT: optimize away motion of sp and pc. This path does not call rb_warning() and so it's always leaf and not `handles_sp`.
        # compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

        # JIT: prepare vm_getivar/vm_setivar arguments and variables
        src << "{\n"
        src << "    VALUE obj = GET_SELF();\n"
        src << "    const uint32_t index = #{ic_copy.entry.index};\n"
        if status.merge_ivar_guards_p
          # JIT: Access ivar without checking these VM_ASSERTed prerequisites as we checked them in the beginning of `mjit_compile_body`
          src << "    VM_ASSERT(RB_TYPE_P(obj, T_OBJECT));\n"
          src << "    VM_ASSERT((rb_serial_t)#{ic_copy.entry.class_serial} == RCLASS_SERIAL(RBASIC(obj)->klass));\n"
          src << "    VM_ASSERT(index < ROBJECT_NUMIV(obj));\n"
          if insn_name == :setinstancevariable
            if USE_RVARGC
              src << "    if (LIKELY(!RB_OBJ_FROZEN_RAW(obj) && index < ROBJECT_NUMIV(obj))) {\n"
              src << "        RB_OBJ_WRITE(obj, &ROBJECT_IVPTR(obj)[index], stack[#{stack_size - 1}]);\n"
            else
              heap_ivar_p = status.max_ivar_index >= ROBJECT_EMBED_LEN_MAX
              src << "    if (LIKELY(!RB_OBJ_FROZEN_RAW(obj) && #{heap_ivar_p ? 'true' : 'RB_FL_ANY_RAW(obj, ROBJECT_EMBED)'})) {\n"
              src << "        RB_OBJ_WRITE(obj, &ROBJECT(obj)->as.#{heap_ivar_p ? 'heap.ivptr[index]' : 'ary[index]'}, stack[#{stack_size - 1}]);\n"
            end
            src << "    }\n"
          else
            src << "    VALUE val;\n"
            if USE_RVARGC
              src << "    if (LIKELY(index < ROBJECT_NUMIV(obj) && (val = ROBJECT_IVPTR(obj)[index]) != Qundef)) {\n"
            else
              heap_ivar_p = status.max_ivar_index >= ROBJECT_EMBED_LEN_MAX
              src << "    if (LIKELY(#{heap_ivar_p ? 'true' : 'RB_FL_ANY_RAW(obj, ROBJECT_EMBED)'} && (val = ROBJECT(obj)->as.#{heap_ivar_p ? 'heap.ivptr[index]' : 'ary[index]'}) != Qundef)) {\n"
            end
            src << "        stack[#{stack_size}] = val;\n"
            src << "    }\n"
          end
        else
          src << "    const rb_serial_t ic_serial = (rb_serial_t)#{ic_copy.entry.class_serial};\n"
          # JIT: cache hit path of vm_getivar/vm_setivar, or cancel JIT (recompile it with exivar)
          if insn_name == :setinstancevariable
            src << "    if (LIKELY(RB_TYPE_P(obj, T_OBJECT) && ic_serial == RCLASS_SERIAL(RBASIC(obj)->klass) && index < ROBJECT_NUMIV(obj) && !RB_OBJ_FROZEN_RAW(obj))) {\n"
            src << "        VALUE *ptr = ROBJECT_IVPTR(obj);\n"
            src << "        RB_OBJ_WRITE(obj, &ptr[index], stack[#{stack_size - 1}]);\n"
            src << "    }\n"
          else
            src << "    VALUE val;\n"
            src << "    if (LIKELY(RB_TYPE_P(obj, T_OBJECT) && ic_serial == RCLASS_SERIAL(RBASIC(obj)->klass) && index < ROBJECT_NUMIV(obj) && (val = ROBJECT_IVPTR(obj)[index]) != Qundef)) {\n"
            src << "        stack[#{stack_size}] = val;\n"
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
      elsif insn_name == :getinstancevariable && !status.compile_info.disable_exivar_cache && ic_copy.entry
        # JIT: optimize away motion of sp and pc. This path does not call rb_warning() and so it's always leaf and not `handles_sp`.
        # compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

        # JIT: prepare vm_getivar's arguments and variables
        src << "{\n"
        src << "    VALUE obj = GET_SELF();\n"
        src << "    const rb_serial_t ic_serial = (rb_serial_t)#{ic_copy.entry.class_serial};\n"
        src << "    const uint32_t index = #{ic_copy.entry.index};\n"
        # JIT: cache hit path of vm_getivar, or cancel JIT (recompile it without any ivar optimization)
        src << "    struct gen_ivtbl *ivtbl;\n"
        src << "    VALUE val;\n"
        src << "    if (LIKELY(FL_TEST_RAW(obj, FL_EXIVAR) && ic_serial == RCLASS_SERIAL(RBASIC(obj)->klass) && rb_ivar_generic_ivtbl_lookup(obj, &ivtbl) && index < ivtbl->numiv && (val = ivtbl->ivptr[index]) != Qundef)) {\n"
        src << "        stack[#{stack_size}] = val;\n"
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

    # _mjit_compile_invokebulitin.erb
    def compile_invokebuiltin(f, insn, stack_size, sp_inc, body, operands)
      bf = C.RB_BUILTIN.new(operands[0])
      if bf.compiler > 0
        C.fprintf(f, "{\n")
        C.fprintf(f, "    VALUE val;\n")
        C.builtin_compiler(f, bf, operands[1], stack_size, body.builtin_inline_p)
        C.fprintf(f, "    stack[#{stack_size + sp_inc - 1}] = val;\n")
        C.fprintf(f, "}\n")
        return true
      else
        return false
      end
    end

    # _mjit_compile_getconstant_path.erb
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

    # _mjit_compile_insn.erb
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
        src << "        RB_DEBUG_COUNTER_INC(mjit_cancel_invalidate_all);\n"
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

    # _mjit_compile_insn_body.erb
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
            src << "                    RB_DEBUG_COUNTER_INC(mjit_cancel_invalidate_all);\n"
            src << "                    goto cancel;\n"
            src << "                }\n"
            src << "            }\n"
          else
            src << to_cstr(line)
          end
        when /\A\s+JUMP\((?<dest>[^)]+)\);\s+\z/
          dest = Regexp.last_match[:dest]
          if insn.name == :opt_case_dispatch # special case... TODO: use another macro to avoid checking name
            else_offset = cast_offset(operands[1])
            cdhash = C.cdhash_to_hash(operands[0])
            base_pos = pos + insn_len

            src << "    switch (#{dest}) {\n"
            cdhash.each do |_key, offset|
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
          src << "            RB_DEBUG_COUNTER_INC(mjit_cancel_opt_insn);\n"
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

    # _mjit_compile_pc_and_sp.erb
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
    def compile_inlined_cancel_handler(f, body, inline_context)
      src = +"\ncancel:\n"
      src << "    RB_DEBUG_COUNTER_INC(mjit_cancel);\n"
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
      C.fprintf(f, src)
    end

    # Print the block to cancel JIT execution.
    def compile_cancel_handler(f, body, status)
      if status.inlined_iseqs.nil? # the current ISeq is being inlined
        compile_inlined_cancel_handler(f, body, status.inline_context)
        return
      end

      src = +"\nsend_cancel:\n"
      src << "    RB_DEBUG_COUNTER_INC(mjit_cancel_send_inline);\n"
      src << "    rb_mjit_recompile_send(original_iseq);\n"
      src << "    goto cancel;\n"

      src << "\nivar_cancel:\n"
      src << "    RB_DEBUG_COUNTER_INC(mjit_cancel_ivar_inline);\n"
      src << "    rb_mjit_recompile_ivar(original_iseq);\n"
      src << "    goto cancel;\n"

      src << "\nexivar_cancel:\n"
      src << "    RB_DEBUG_COUNTER_INC(mjit_cancel_exivar_inline);\n"
      src << "    rb_mjit_recompile_exivar(original_iseq);\n"
      src << "    goto cancel;\n"

      src << "\nconst_cancel:\n"
      src << "    rb_mjit_recompile_const(original_iseq);\n"
      src << "    goto cancel;\n"

      src << "\ncancel:\n"
      src << "    RB_DEBUG_COUNTER_INC(mjit_cancel);\n"
      if status.local_stack_p
        (0...body.stack_max).each do |i|
          src << "    *(vm_base_ptr(reg_cfp) + #{i}) = stack[#{i}];\n"
        end
      end
      src << "    return Qundef;\n"
      C.fprintf(f, src)
    end

    def precompile_inlinable_child_iseq(f, child_iseq, status, ci, cc, pos)
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
      init_ivar_compile_status(child_iseq.body, child_status)

      src = +"ALWAYS_INLINE(static VALUE _mjit#{status.compiled_id}_inlined_#{pos}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE orig_self, const rb_iseq_t *original_iseq));\n"
      src << "static inline VALUE\n_mjit#{status.compiled_id}_inlined_#{pos}(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE orig_self, const rb_iseq_t *original_iseq)\n{\n"
      src << "    const VALUE *orig_pc = reg_cfp->pc;\n"
      src << "    VALUE *orig_sp = reg_cfp->sp;\n"
      C.fprintf(f, src)

      success = compile_body(f, child_iseq, child_status)

      C.fprintf(f, "\n} /* end of _mjit#{status.compiled_id}_inlined_#{pos} */\n\n")

      return success;
    end

    def precompile_inlinable_iseqs(f, iseq, status)
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
            if !precompile_inlinable_child_iseq(f, child_iseq, status, ci, cc, pos)
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
      if ISEQ_IS_SIZE(body) > 0
        status.is_entries = Fiddle.malloc(C.iseq_inline_storage_entry.sizeof * ISEQ_IS_SIZE(body))
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

    def init_ivar_compile_status(body, status)
      C.mjit_capture_is_entries(body, status.is_entries)

      num_ivars = 0
      pos = 0
      status.max_ivar_index = 0
      status.ivar_serial = 0

      while pos < body.iseq_size
        insn = INSNS.fetch(C.rb_vm_insn_decode(body.iseq_encoded[pos]))
        if insn.name == :getinstancevariable || insn.name == :setinstancevariable
          ic = body.iseq_encoded[pos+2]
          ic_copy = (status.is_entries + (C.iseq_inline_storage_entry.new(ic) - body.is_entries)).iv_cache
          if ic_copy.entry # Only initialized (ic_serial > 0) IVCs are optimized
            num_ivars += 1

            if status.max_ivar_index < ic_copy.entry.index
              status.max_ivar_index = ic_copy.entry.index
            end

            if status.ivar_serial == 0
              status.ivar_serial = ic_copy.entry.class_serial
            elsif status.ivar_serial != ic_copy.entry.class_serial
              # Multiple classes have used this ISeq. Give up assuming one serial.
              status.merge_ivar_guards_p = false
              return
            end
          end
        end
        pos += insn.len
      end
      status.merge_ivar_guards_p = status.ivar_serial > 0 && num_ivars >= 2
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
      bits = "%0#{8 * Fiddle::SIZEOF_VOIDP}d" % offset.to_s(2)
      if bits[0] == '1' # negative
        offset = -bits.chars.map { |i| i == '0' ? '1' : '0' }.join.to_i(2) - 1
      end
      offset
    end

    def captured_cc_entries(status)
      status.compiled_iseq.jit_unit.cc_entries + status.cc_entries_index
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
      body.jit_unit.compile_info
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
  end

  private_constant(*constants)
end
