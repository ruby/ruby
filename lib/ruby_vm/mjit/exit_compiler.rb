module RubyVM::MJIT
  class ExitCompiler
    def initialize
      # TODO: Use GC offsets
      @gc_refs = []
    end

    # Used for invalidating a block on entry.
    # @param pc [Integer]
    # @param asm [RubyVM::MJIT::Assembler]
    def compile_entry_exit(pc, asm, cause:)
      # Increment per-insn exit counter
      incr_insn_exit(pc)

      # TODO: Saving pc and sp may be needed later

      # Restore callee-saved registers
      asm.comment("#{cause}: entry exit")
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.mov(:rax, Qundef)
      asm.ret
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def compile_side_exit(jit, ctx, asm)
      # Increment per-insn exit counter
      incr_insn_exit(jit.pc)

      # Fix pc/sp offsets for the interpreter
      save_pc_and_sp(jit, ctx.dup, asm) # dup to avoid sp_offset update

      # Restore callee-saved registers
      asm.comment("exit to interpreter on #{pc_to_insn(jit.pc).name}")
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.mov(:rax, Qundef)
      asm.ret
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param stub [RubyVM::MJIT::BlockStub]
    def compile_jump_stub(jit, asm, stub)
      case stub
      when BlockStub
        asm.comment("block stub hit: #{stub.iseq.body.location.label}@#{C.rb_iseq_path(stub.iseq)}:#{stub.iseq.body.location.first_lineno}")
      else
        raise "unexpected stub object: #{stub.inspect}"
      end

      # Call rb_mjit_stub_hit
      asm.mov(:rdi, to_value(stub))
      asm.call(C.rb_mjit_stub_hit)

      # Jump to the address returned by rb_mjit_stub_hit
      asm.jmp(:rax)
    end

    private

    def pc_to_insn(pc)
      Compiler.decode_insn(C.VALUE.new(pc).*)
    end

    # @param pc [Integer]
    def incr_insn_exit(pc)
      if C.mjit_opts.stats
        insn = decode_insn(C.VALUE.new(pc).*)
        asm.comment("increment insn exit: #{insn.name}")
        asm.mov(:rax, (C.mjit_insn_exits + insn.bin).to_i)
        asm.add([:rax], 1) # TODO: lock
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def save_pc_and_sp(jit, ctx, asm)
      # Update pc (TODO: manage PC offset?)
      asm.comment("save pc #{'and sp' if ctx.sp_offset != 0}")
      asm.mov(:rax, jit.pc) # rax = jit.pc
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # Update sp
      if ctx.sp_offset != 0
        asm.add(SP, C.VALUE.size * ctx.sp_offset) # sp += stack_size
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP) # cfp->sp = sp
        ctx.sp_offset = 0
      end
    end

    def to_value(obj)
      @gc_refs << obj
      C.to_value(obj)
    end
  end
end
