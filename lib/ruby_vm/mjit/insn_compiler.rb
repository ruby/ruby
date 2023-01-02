module RubyVM::MJIT
  # scratch regs: rax
  #
  # 5/101
  class InsnCompiler
    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::MJIT::ExitCompiler]
    def initialize(ocb, exit_compiler)
      @ocb = ocb
      @exit_compiler = exit_compiler
      @invariants = Invariants.new(ocb, exit_compiler)
      freeze
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param insn `RubyVM::MJIT::Instruction`
    def compile(jit, ctx, asm, insn)
      asm.incr_counter(:mjit_insns_count)
      asm.comment("Insn: #{insn.name}")

      case insn.name
      # nop
      # getlocal
      # setlocal
      # getblockparam
      # setblockparam
      # getblockparamproxy
      # getspecial
      # setspecial
      # getinstancevariable
      # setinstancevariable
      # getclassvariable
      # setclassvariable
      # opt_getconstant_path
      # getconstant
      # setconstant
      # getglobal
      # setglobal
      when :putnil then putnil(jit, ctx, asm)
      # putself
      when :putobject then putobject(jit, ctx, asm)
      # putspecialobject
      # putstring
      # concatstrings
      # anytostring
      # toregexp
      # intern
      # newarray
      # newarraykwsplat
      # duparray
      # duphash
      # expandarray
      # concatarray
      # splatarray
      # newhash
      # newrange
      # pop
      # dup
      # dupn
      # swap
      # opt_reverse
      # topn
      # setn
      # adjuststack
      # defined
      # checkmatch
      # checkkeyword
      # checktype
      # defineclass
      # definemethod
      # definesmethod
      # send
      # opt_send_without_block
      # objtostring
      # opt_str_freeze
      # opt_nil_p
      # opt_str_uminus
      # opt_newarray_max
      # opt_newarray_min
      # invokesuper
      # invokeblock
      when :leave then leave(jit, ctx, asm)
      # throw
      # jump
      # branchif
      # branchunless
      # branchnil
      # once
      # opt_case_dispatch
      # opt_plus
      # opt_minus
      # opt_mult
      # opt_div
      # opt_mod
      # opt_eq
      # opt_neq
      when :opt_lt then opt_lt(jit, ctx, asm)
      # opt_le
      # opt_gt
      # opt_ge
      # opt_ltlt
      # opt_and
      # opt_or
      # opt_aref
      # opt_aset
      # opt_aset_with
      # opt_aref_with
      # opt_length
      # opt_size
      # opt_empty_p
      # opt_succ
      # opt_not
      # opt_regexpmatch2
      # invokebuiltin
      # opt_invokebuiltin_delegate
      # opt_invokebuiltin_delegate_leave
      when :getlocal_WC_0 then getlocal_WC_0(jit, ctx, asm)
      else CantCompile
      end
    end

    private

    #
    # Insns
    #

    # nop
    # getlocal
    # setlocal
    # getblockparam
    # setblockparam
    # getblockparamproxy
    # getspecial
    # setspecial
    # getinstancevariable
    # setinstancevariable
    # getclassvariable
    # setclassvariable
    # opt_getconstant_path
    # getconstant
    # setconstant
    # getglobal
    # setglobal

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putnil(jit, ctx, asm)
      asm.mov([SP, C.VALUE.size * ctx.stack_size], Qnil)
      ctx.stack_push(1)
      KeepCompiling
    end

    # putself

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putobject(jit, ctx, asm)
      # Get operands
      val = jit.operand(0)

      # Push it to the stack
      # TODO: GC offsets
      if asm.imm32?(val)
        asm.mov([SP, C.VALUE.size * ctx.stack_size], val)
      else # 64-bit immediates can't be directly written to memory
        asm.mov(:rax, val)
        asm.mov([SP, C.VALUE.size * ctx.stack_size], :rax)
      end

      ctx.stack_push(1)
      KeepCompiling
    end

    # putspecialobject
    # putstring
    # concatstrings
    # anytostring
    # toregexp
    # intern
    # newarray
    # newarraykwsplat
    # duparray
    # duphash
    # expandarray
    # concatarray
    # splatarray
    # newhash
    # newrange
    # pop
    # dup
    # dupn
    # swap
    # opt_reverse
    # topn
    # setn
    # adjuststack
    # defined
    # checkmatch
    # checkkeyword
    # checktype
    # defineclass
    # definemethod
    # definesmethod
    # send
    # opt_send_without_block
    # objtostring
    # opt_str_freeze
    # opt_nil_p
    # opt_str_uminus
    # opt_newarray_max
    # opt_newarray_min
    # invokesuper
    # invokeblock

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def leave(jit, ctx, asm)
      assert_eq!(ctx.stack_size, 1)

      asm.comment('RUBY_VM_CHECK_INTS(ec)')
      asm.mov(:eax, [EC, C.rb_execution_context_t.offsetof(:interrupt_flag)])
      asm.test(:eax, :eax)
      asm.jnz(compile_side_exit(jit, ctx))

      asm.comment('pop stack frame')
      asm.add(CFP, C.rb_control_frame_t.size) # cfp = cfp + 1
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], CFP) # ec->cfp = cfp

      # Return a value
      asm.mov(:rax, [SP])

      # Restore callee-saved registers
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.ret
      EndBlock
    end

    # throw
    # jump
    # branchif
    # branchunless
    # branchnil
    # once
    # opt_case_dispatch
    # opt_plus
    # opt_minus
    # opt_mult
    # opt_div
    # opt_mod
    # opt_eq
    # opt_neq

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_lt(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      unless @invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_LT)
        return CantCompile
      end
      CantCompile
    end

    # opt_le
    # opt_gt
    # opt_ge
    # opt_ltlt
    # opt_and
    # opt_or
    # opt_aref
    # opt_aset
    # opt_aset_with
    # opt_aref_with
    # opt_length
    # opt_size
    # opt_empty_p
    # opt_succ
    # opt_not
    # opt_regexpmatch2
    # invokebuiltin
    # opt_invokebuiltin_delegate
    # opt_invokebuiltin_delegate_leave

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def getlocal_WC_0(jit, ctx, asm)
      # Get operands
      idx = jit.operand(0)
      level = 0

      # Get EP
      asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:ep)])

      # Get a local variable
      asm.mov(:rax, [:rax, -idx * C.VALUE.size])

      # Push it to the stack
      asm.mov([SP, C.VALUE.size * ctx.stack_size], :rax)
      ctx.stack_push(1)
      KeepCompiling
    end

    # getlocal_WC_1
    # setlocal_WC_0
    # setlocal_WC_1
    # putobject_INT2FIX_0_
    # putobject_INT2FIX_1_

    #
    # Helpers
    #

    def assert_eq!(left, right)
      if left != right
        raise "'#{left.inspect}' was not '#{right.inspect}'"
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def defer_compilation(jit, ctx, asm)
      # Make a stub to compile the current insn
      block_stub = BlockStub.new(
        iseq: jit.iseq,
        pc:   jit.pc,
        ctx:  ctx.dup,
      )

      stub_hit = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_jump_stub(jit, ocb_asm, block_stub)
        @ocb.write(ocb_asm)
      end

      asm.comment('defer_compilation: block stub')
      asm.stub(block_stub) do
        asm.jmp(stub_hit)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    def compile_side_exit(jit, ctx)
      asm = Assembler.new
      @exit_compiler.compile_side_exit(jit, ctx, asm)
      @ocb.write(asm)
    end
  end
end
