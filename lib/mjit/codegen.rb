module RubyVM::MJIT
  #  ec: rdi
  # cfp: rsi
  #  sp: rbx
  # scratch regs: rax
  class Codegen
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def putnil(ctx, asm)
      asm.mov([SP], Qnil)
      ctx.stack_size += 1
      KeepCompiling
    end

    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def leave(ctx, asm)
      assert_eq!(ctx.stack_size, 1)
      # TODO: Check interrupts

      # Pop the current frame (ec->cfp++)
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
