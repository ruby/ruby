module RubyVM::MJIT
  class InsnCompiler
    def on_putnil(_asm)
      # TODO
      KeepCompiling
    end

    def on_leave(asm)
      # pop the current frame (ec->cfp++)
      asm.add(:rsi, C.rb_control_frame_t.size)
      asm.mov([:rdi, C.rb_execution_context_t.offsetof(:cfp)], :rsi)

      # return a value
      asm.mov(:rax, 7)
      asm.ret
      EndBlock
    end
  end
end
