# frozen_string_literal: true
module RubyVM::MJIT
  SUPPORTED_INSTRUCTIONS = [
    :nop,
    :getlocal,
    :setlocal,
    :getblockparam,
    :setblockparam,
    :getblockparamproxy,
    :getspecial,
    :setspecial,
    #:getinstancevariable,
    #:setinstancevariable,
    #:getclassvariable,
    #:setclassvariable,
    #:getconstant,
    #:setconstant,
    #:getglobal,
    #:setglobal,
    :putnil,
    #:putself,
    :putobject,
    #:putspecialobject,
    :putstring,
    #:concatstrings,
    #:anytostring,
    #:toregexp,
    #:intern,
    #:newarray,
    #:newarraykwsplat,
    #:duparray,
    #:duphash,
    #:expandarray,
    #:concatarray,
    #:splatarray,
    #:newhash,
    #:newrange,
    :pop,
    #:dup,
    #:dupn,
    #:swap,
    #:topn,
    #:setn,
    #:adjuststack,
    #:defined,
    #:checkmatch,
    #:checkkeyword,
    #:checktype,
    #:defineclass, # not supported
    #:definemethod,
    #:definesmethod,
    #:send,
    #:opt_send_without_block,
    #:objtostring,
    #:opt_str_freeze,
    #:opt_nil_p,
    #:opt_str_uminus,
    #:opt_newarray_max,
    #:opt_newarray_min,
    #:invokesuper,
    #:invokeblock,
    :leave,
    #:throw,
    #:jump,
    #:branchif,
    #:branchunless,
    #:branchnil,
    #:opt_getinlinecache,
    #:opt_setinlinecache,
    :once,
    #:opt_case_dispatch,
    #:opt_plus,
    #:opt_minus,
    #:opt_mult,
    #:opt_div,
    #:opt_mod,
    #:opt_eq,
    #:opt_neq,
    #:opt_lt,
    #:opt_le,
    #:opt_gt,
    #:opt_ge,
    #:opt_ltlt,
    #:opt_and,
    #:opt_or,
    #:opt_aref,
    #:opt_aset,
    #:opt_aset_with,
    #:opt_aref_with,
    #:opt_length,
    #:opt_size,
    #:opt_empty_p,
    #:opt_succ,
    #:opt_not,
    #:opt_regexpmatch2,
    #:invokebuiltin,
    #:opt_invokebuiltin_delegate,
    #:opt_invokebuiltin_delegate_leave,
    #:getlocal_WC_0,
    #:getlocal_WC_1,
    #:setlocal_WC_0,
    #:setlocal_WC_1,
    :putobject_INT2FIX_0_,
    :putobject_INT2FIX_1_,
  ]

  class << Compiler = Module.new
    # mjit_comiple.inc.erb
    def compile(insn_name, stack_size, sp_inc, local_stack_p, pos, next_pos, inlined_iseq_p, operands)
      insn = INSTRUCTIONS.fetch(insn_name)

      case insn_name
      when :leave
        src = +''

        # opt_invokebuiltin_delegate_leave also implements leave insn. We need to handle it here for inlining.
        if insn_name == :opt_invokebuiltin_delegate_leave
          # <%=     render 'mjit_compile_invokebuiltin', locals: { insn: insn } -%> # TODO
        else
          if stack_size != 1
            $stderr.puts "MJIT warning: Unexpected JIT stack_size on leave: #{stack_size}"
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
        return src, true
      when *SUPPORTED_INSTRUCTIONS
        return compile_insn(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, inlined_iseq_p, operands)
      else
        nil
      end
    rescue => e
      puts e.full_message
      nil
    end

    private

    # _mjit_compile_insn.erb
    def compile_insn(insn, stack_size, sp_inc, local_stack_p, pos, next_pos, inlined_iseq_p, operands)
      src = +''
      finish_p = false

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
        src << "    #{ope.fetch(:name)} = (#{ope.fetch(:type)})#{'0x%x' % operands[i]};\n"
        # TODO: resurrect comment_id
      end

      # JIT: Initialize popped values
      insn.pops.reverse_each.with_index.reverse_each do |pop, i|
        src << "    #{pop.fetch(:name)} = stack[#{stack_size - (i + 1)}];\n"
      end

      # JIT: move sp and pc if necessary
      pc_moved_p = compile_pc_and_sp(src, insn, stack_size, sp_inc, local_stack_p, next_pos)

      # JIT: Print insn body in insns.def
      compile_insn_body(src, insn, pos, local_stack_p)

      # JIT: Set return values
      insn.rets.reverse_each.with_index do |ret, i|
        # TOPN(n) = ...
        src << "    stack[#{stack_size + sp_inc - (i + 1)}] = #{ret.fetch(:name)};\n"
      end

      # JIT: We should evaluate ISeq modified for TracePoint if it's enabled. Note: This is slow.
      #      leaf insn may not cancel JIT. leaf_without_check_ints is covered in RUBY_VM_CHECK_INTS of _mjit_compile_insn_body.erb.
      # TODO

      # compiler: Move JIT compiler's internal stack pointer
      # TODO
      src << "}\n"

      # compiler: If insn has conditional JUMP, the code should go to the branch not targeted by JUMP next.
      # TODO

      # compiler: If insn returns (leave) or does longjmp (throw), the branch should no longer be compiled. TODO: create attr for it?
      if insn.expr.match?(/\sTHROW_EXCEPTION\([^)]+\);/) || insn.expr.match?(/\bvm_pop_frame\(/)
        finish_p = true
      end

      return src, finish_p
    end

    # _mjit_compile_insn_body.erb
    def compile_insn_body(src, insn, pos, local_stack_p)
      # Print a body of insn, but with macro expansion.
      expand_simple_macros(insn.expr).each_line do |line|
        # Expand dynamic macro here (only JUMP for now)
        # TODO: support combination of following macros in the same line
        case line
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
            #when /\bGET_SP\(\)/
            #  # reg_cfp->sp
            #fprintf(f, <%= to_cstr.call(line.sub(/\bGET_SP\(\)/, '%s')) %>, (status->local_stack_p ? "(stack + stack_size)" : "GET_SP()"));
            #when /\bSTACK_ADDR_FROM_TOP\((?<num>[^)]+)\)/
            #  # #define STACK_ADDR_FROM_TOP(n) (GET_SP()-(n))
            #  num = Regexp.last_match[:num]
            #fprintf(f, <%= to_cstr.call(line.sub(/\bSTACK_ADDR_FROM_TOP\(([^)]+)\)/, '%s')) %>,
            #        (status->local_stack_p ? "(stack + (stack_size - (<%= num %>)))" : "STACK_ADDR_FROM_TOP(<%= num %>)"));
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
  end
end if RubyVM::MJIT.enabled?
