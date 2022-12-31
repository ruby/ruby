module RubyVM::MJIT
  class ExitCompiler
    def initialize = freeze

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def compile_exit(jit, ctx, asm)
      if C.mjit_opts.stats
        insn = decode_insn(C.VALUE.new(jit.pc).*)
        asm.comment("increment insn exit: #{insn.name}")
        asm.mov(:rax, (C.mjit_insn_exits + insn.bin).to_i)
        asm.add([:rax], 1) # TODO: lock
      end
      asm.comment("exit to interpreter")

      # Update pc
      asm.mov(:rax, jit.pc) # rax = jit.pc
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # Update sp
      if ctx.stack_size > 0
        asm.add(SP, C.VALUE.size * ctx.stack_size) # rbx += stack_size
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP) # cfp->sp = rbx
      end

      # Restore callee-saved registers
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.mov(:rax, Qundef)
      asm.ret
    end
  end
end
