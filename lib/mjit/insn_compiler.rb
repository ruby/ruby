module RubyVM::MJIT
  class InsnCompiler
    def putnil(_asm)
      # TODO
      KeepCompiling
    end

    def leave(asm)
      # pop the current frame (ec->cfp++)
      asm.add(:rsi, C.rb_control_frame_t.size)
      asm.mov([:rdi, C.rb_execution_context_t.offsetof(:cfp)], :rsi)

      # return a value
      asm.mov(:rax, 1001)
      asm.ret
      EndBlock
    end
  end
end
