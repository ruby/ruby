# frozen_string_literal: true
module RubyVM::MJIT
  class << Compiler = Module.new
    # _mjit_compile_insn.erb
    def compile_insn(insn_name, stack_size, sp_inc)
      case insn_name
      when :putnil#, :leave
        insn = INSTRUCTIONS.fetch(insn_name)

        src = +''
        src << "{\n"

        # JIT: Declare stack_size to be used in some macro of _mjit_compile_insn_body.erb
        # if local_stack_p # TODO
        src << "    MAYBE_UNUSED(unsigned int) stack_size = #{stack_size};\n"
        # end

        # JIT: Declare variables for operands, popped values and return values
        insn.declarations.each do |decl|
          src << "    #{decl};\n"
        end

        # JIT: Set const expressions for `RubyVM::OperandsUnifications` insn
        # TODO

        # JIT: Initialize operands
        # TODO

        # JIT: Initialize popped values
        insn.pops.reverse_each.with_index.reverse_each do |pop, i|
          src << "    #{pop.fetch(:name)} = stack[#{stack_size - (i + 1)}];\n"
        end

        # JIT: move sp and pc if necessary
        # TODO

        # JIT: Print insn body in insns.def
        src << indent(expand_simple_macros(insn.expr))

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
        # TODO

        return src
      else
        nil
      end
    end

    private

    # Expand simple macro that doesn't require dynamic C code.
    def expand_simple_macros(arg_expr)
      expr = arg_expr.dup
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
      expr
    end

    def indent(expr)
      expr.gsub(/^(?!#)/, '    ') # indent everything but preprocessor lines
    end
  end
end
