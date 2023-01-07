module RubyVM::MJIT
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

      # 10/101
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
      when :putself then putself(jit, ctx, asm)
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
      when :branchunless then branchunless(jit, ctx, asm)
      # branchnil
      # once
      # opt_case_dispatch
      # opt_plus
      when :opt_minus then opt_minus(jit, ctx, asm)
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
      # setlocal_WC_0
      # setlocal_WC_1
      when :putobject_INT2FIX_0_ then putobject_INT2FIX_0_(jit, ctx, asm)
      when :putobject_INT2FIX_1_ then putobject_INT2FIX_1_(jit, ctx, asm)
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
      raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
      asm.mov([SP, C.VALUE.size * ctx.stack_size], Qnil)
      ctx.stack_push(1)
      KeepCompiling
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putself(jit, ctx, asm)
      raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
      asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov([SP, C.VALUE.size * ctx.stack_size], :rax)
      ctx.stack_push(1)
      KeepCompiling
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putobject(jit, ctx, asm, val: jit.operand(0))
      # Push it to the stack
      # TODO: GC offsets
      raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
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
      asm.jnz(side_exit(jit, ctx))

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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def branchunless(jit, ctx, asm)
      # TODO: check ints for backward branches
      # TODO: skip check for known truthy

      # This `test` sets ZF only for Qnil and Qfalse, which let jz jump.
      asm.test([SP, C.VALUE.size * (ctx.stack_size - 1)], ~Qnil)
      ctx.stack_pop(1)

      # Set stubs
      # TODO: reuse already-compiled blocks jumped from different blocks
      branch_stub = BranchStub.new(
        iseq: jit.iseq,
        ctx:  ctx.dup,
        branch_target_pc: jit.pc + (jit.insn.len + jit.operand(0)) * C.VALUE.size,
        fallthrough_pc:   jit.pc + jit.insn.len * C.VALUE.size,
      )
      branch_stub.branch_target_addr = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(jit, ctx, ocb_asm, branch_stub, true)
        @ocb.write(ocb_asm)
      end
      branch_stub.fallthrough_addr = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(jit, ctx, ocb_asm, branch_stub, false)
        @ocb.write(ocb_asm)
      end

      # Prepare codegen for all cases
      branch_stub.branch_target_next = proc do |branch_asm|
        branch_asm.stub(branch_stub) do
          branch_asm.comment('branch_target_next')
          branch_asm.jnz(branch_stub.fallthrough_addr)
        end
      end
      branch_stub.fallthrough_next = proc do |branch_asm|
        branch_asm.stub(branch_stub) do
          branch_asm.comment('fallthrough_next')
          branch_asm.jz(branch_stub.branch_target_addr)
        end
      end
      branch_stub.neither_next = proc do |branch_asm|
        branch_asm.stub(branch_stub) do
          branch_asm.comment('neither_next')
          branch_asm.jz(branch_stub.branch_target_addr)
          branch_asm.jmp(branch_stub.fallthrough_addr)
        end
      end

      # Just jump to stubs
      branch_stub.neither_next.call(asm)
      EndBlock
    end

    # branchnil
    # once
    # opt_case_dispatch
    # opt_plus

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_minus(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        unless @invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_MINUS)
          return CantCompile
        end

        raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
        recv_index = ctx.stack_size - 2
        obj_index  = ctx.stack_size - 1

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test([SP, C.VALUE.size * recv_index], C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit(jit, ctx))

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test([SP, C.VALUE.size * obj_index], C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit(jit, ctx))

        asm.mov(:rax, [SP, C.VALUE.size * recv_index])
        asm.mov(:rcx, [SP, C.VALUE.size * obj_index])
        asm.sub(:rax, :rcx)
        asm.jo(side_exit(jit, ctx))
        asm.add(:rax, 1)
        asm.mov([SP, C.VALUE.size * recv_index], :rax)

        ctx.stack_pop(1)
        KeepCompiling
      else
        CantCompile # TODO: delegate to send
      end
    end

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

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        unless @invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_LT)
          return CantCompile
        end

        raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
        recv_index = ctx.stack_size - 2
        obj_index  = ctx.stack_size - 1

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test([SP, C.VALUE.size * recv_index], C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit(jit, ctx))

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test([SP, C.VALUE.size * obj_index], C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit(jit, ctx))

        asm.mov(:rax, [SP, C.VALUE.size * obj_index])
        asm.cmp([SP, C.VALUE.size * recv_index], :rax)
        asm.mov(:rax, Qfalse)
        asm.mov(:rcx, Qtrue)
        asm.cmovl(:rax, :rcx)
        asm.mov([SP, C.VALUE.size * recv_index], :rax)

        ctx.stack_pop(1)
        KeepCompiling
      else
        CantCompile # TODO: delegate to send
      end
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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putobject_INT2FIX_0_(jit, ctx, asm)
      putobject(jit, ctx, asm, val: C.to_value(0))
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putobject_INT2FIX_1_(jit, ctx, asm)
      putobject(jit, ctx, asm, val: C.to_value(1))
    end

    #
    # Helpers
    #

    def assert_eq!(left, right)
      if left != right
        raise "'#{left.inspect}' was not '#{right.inspect}'"
      end
    end

    def fixnum?(obj)
      flag = C.RUBY_FIXNUM_FLAG
      (C.to_value(obj) & flag) == flag
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def defer_compilation(jit, ctx, asm)
      # Make a stub to compile the current insn
      block_stub = BlockStub.new(
        iseq: jit.iseq,
        ctx:  ctx.dup,
        pc:   jit.pc,
      )

      stub_hit = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_block_stub(jit, ctx, ocb_asm, block_stub)
        @ocb.write(ocb_asm)
      end

      asm.comment('defer_compilation: block stub')
      asm.stub(block_stub) do
        asm.jmp(stub_hit)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    def side_exit(jit, ctx)
      if side_exit = jit.side_exits[jit.pc]
        return side_exit
      end
      asm = Assembler.new
      @exit_compiler.compile_side_exit(jit, ctx, asm)
      jit.side_exits[jit.pc] = @ocb.write(asm)
    end
  end
end
