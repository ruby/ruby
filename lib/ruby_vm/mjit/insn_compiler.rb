module RubyVM::MJIT
  #  ec: rdi
  # cfp: rsi
  #  sp: rbx
  # scratch regs: rax
  class InsnCompiler
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def putnil(jit, ctx, asm)
      asm.mov([SP, C.VALUE.size * ctx.stack_size], Qnil)
      ctx.stack_size += 1
      KeepCompiling
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def leave(jit, ctx, asm)
      assert_eq!(ctx.stack_size, 1)

      asm.comment('RUBY_VM_CHECK_INTS(ec)')
      asm.mov(:eax, [EC, C.rb_execution_context_t.offsetof(:interrupt_flag)])
      asm.test(:eax, :eax)
      asm.jz(not_interrupted = asm.new_label(:not_interrupted))
      Compiler.compile_exit(jit, ctx, asm) # TODO: use ocb
      asm.write_label(not_interrupted)

      asm.comment('pop stack frame')
      asm.add(CFP, C.rb_control_frame_t.size) # cfp = cfp + 1
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], CFP) # ec->cfp = cfp

      # Return a value
      asm.mov(:rax, [SP])

      # Restore callee-saved registers
      asm.pop(SP)

      asm.ret
      EndBlock
    end

    private

    def assert_eq!(left, right)
      if left != right
        raise "'#{left.inspect}' was not '#{right.inspect}'"
      end
    end
  end
end
