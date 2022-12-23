module RubyVM::MJIT
  #  ec: rdi
  # cfp: rsi
  #  sp: rbx
  # scratch regs: rax
  class Codegen
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def putnil(ctx, asm)
      asm.mov([:rbx], Qnil)
      ctx.stack_size += 1
      KeepCompiling
    end

    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def leave(ctx, asm)
      assert_eq!(ctx.stack_size, 1)

      # pop the current frame (ec->cfp++)
      asm.add(:rsi, C.rb_control_frame_t.size) # rsi = cfp + 1
      asm.mov([:rdi, C.rb_execution_context_t.offsetof(:cfp)], :rsi) # ec->cfp = rsi

      # return a value
      asm.mov(:rax, [:rbx])
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
