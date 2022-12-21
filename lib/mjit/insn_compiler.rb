module RubyVM::MJIT
  #  ec: rdi
  # cfp: rsi
  #  sp: rbx
  # scratch regs: rax
  class InsnCompiler
    # Ruby constants
    Qnil = Fiddle::Qnil

    def putnil(asm)
      asm.mov([:rbx], Qnil)
      KeepCompiling
    end

    def leave(asm)
      # pop the current frame (ec->cfp++)
      asm.add(:rsi, C.rb_control_frame_t.size) # rsi = cfp + 1
      asm.mov([:rdi, C.rb_execution_context_t.offsetof(:cfp)], :rsi) # ec->cfp = rsi

      # return a value
      asm.mov(:rax, [:rbx])
      asm.ret
      EndBlock
    end
  end
end
