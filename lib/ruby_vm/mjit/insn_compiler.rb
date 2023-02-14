module RubyVM::MJIT
  class InsnCompiler
    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::MJIT::ExitCompiler]
    def initialize(cb, ocb, exit_compiler)
      @ocb = ocb
      @exit_compiler = exit_compiler
      @gc_refs = [] # TODO: GC offsets?

      @full_cfunc_return = Assembler.new.then do |asm|
        @exit_compiler.compile_full_cfunc_return(asm)
        @ocb.write(asm)
      end

      # freeze # workaround a binding.irb issue. TODO: resurrect this
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param insn `RubyVM::MJIT::Instruction`
    def compile(jit, ctx, asm, insn)
      asm.incr_counter(:mjit_insns_count)
      asm.comment("Insn: #{insn.name}")

      # 40/101
      case insn.name
      when :nop then nop(jit, ctx, asm)
      # getlocal
      # setlocal
      # getblockparam
      # setblockparam
      # getblockparamproxy
      # getspecial
      # setspecial
      when :getinstancevariable then getinstancevariable(jit, ctx, asm)
      when :setinstancevariable then setinstancevariable(jit, ctx, asm)
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
      when :pop then pop(jit, ctx, asm)
      when :dup then dup(jit, ctx, asm)
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
      when :opt_send_without_block then opt_send_without_block(jit, ctx, asm)
      # objtostring
      # opt_str_freeze
      when :opt_nil_p then opt_nil_p(jit, ctx, asm)
      # opt_str_uminus
      # opt_newarray_max
      # opt_newarray_min
      # invokesuper
      # invokeblock
      when :leave then leave(jit, ctx, asm)
      # throw
      when :jump then jump(jit, ctx, asm)
      when :branchif then branchif(jit, ctx, asm)
      when :branchunless then branchunless(jit, ctx, asm)
      # branchnil
      # once
      # opt_case_dispatch
      when :opt_plus then opt_plus(jit, ctx, asm)
      when :opt_minus then opt_minus(jit, ctx, asm)
      when :opt_mult then opt_mult(jit, ctx, asm)
      when :opt_div then opt_div(jit, ctx, asm)
      when :opt_mod then opt_mod(jit, ctx, asm)
      when :opt_eq then opt_eq(jit, ctx, asm)
      when :opt_neq then opt_neq(jit, ctx, asm)
      when :opt_lt then opt_lt(jit, ctx, asm)
      when :opt_le then opt_le(jit, ctx, asm)
      when :opt_gt then opt_gt(jit, ctx, asm)
      when :opt_ge then opt_ge(jit, ctx, asm)
      when :opt_ltlt then opt_ltlt(jit, ctx, asm)
      when :opt_and then opt_and(jit, ctx, asm)
      when :opt_or then opt_or(jit, ctx, asm)
      when :opt_aref then opt_aref(jit, ctx, asm)
      # opt_aset
      # opt_aset_with
      # opt_aref_with
      when :opt_length then opt_length(jit, ctx, asm)
      when :opt_size then opt_size(jit, ctx, asm)
      when :opt_empty_p then opt_empty_p(jit, ctx, asm)
      when :opt_succ then opt_succ(jit, ctx, asm)
      when :opt_not then opt_not(jit, ctx, asm)
      when :opt_regexpmatch2 then opt_regexpmatch2(jit, ctx, asm)
      # invokebuiltin
      # opt_invokebuiltin_delegate
      # opt_invokebuiltin_delegate_leave
      when :getlocal_WC_0 then getlocal_WC_0(jit, ctx, asm)
      when :getlocal_WC_1 then getlocal_WC_1(jit, ctx, asm)
      when :setlocal_WC_0 then setlocal_WC_0(jit, ctx, asm)
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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def nop(jit, ctx, asm)
      # Do nothing
      KeepCompiling
    end

    # getlocal
    # setlocal
    # getblockparam
    # setblockparam
    # getblockparamproxy
    # getspecial
    # setspecial

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def getinstancevariable(jit, ctx, asm)
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      id = jit.operand(0)
      comptime_obj = jit.peek_at_self

      jit_getivar(jit, ctx, asm, comptime_obj, id)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def setinstancevariable(jit, ctx, asm)
      id = jit.operand(0)
      ivc = jit.operand(1)

      # rb_vm_setinstancevariable could raise exceptions
      jit_prepare_routine_call(jit, ctx, asm)

      val_opnd = ctx.stack_pop

      asm.comment('rb_vm_setinstancevariable')
      asm.mov(:rdi, jit.iseq.to_i)
      asm.mov(:rsi, [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov(:rdx, id)
      asm.mov(:rcx, val_opnd)
      asm.mov(:r8, ivc)
      asm.call(C.rb_vm_setinstancevariable)

      KeepCompiling
    end

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
      putobject(jit, ctx, asm, val: Qnil)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putself(jit, ctx, asm)
      stack_top = ctx.stack_push
      asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def putobject(jit, ctx, asm, val: jit.operand(0))
      # Push it to the stack
      stack_top = ctx.stack_push
      if asm.imm32?(val)
        asm.mov(stack_top, val)
      else # 64-bit immediates can't be directly written to memory
        asm.mov(:rax, val)
        asm.mov(stack_top, :rax)
      end
      # TODO: GC offsets?

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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def pop(jit, ctx, asm)
      ctx.stack_pop
      KeepCompiling
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def dup(jit, ctx, asm)
      val1 = ctx.stack_opnd(0)
      val2 = ctx.stack_push
      asm.mov(:rax, val1)
      asm.mov(val2, :rax)
      KeepCompiling
    end

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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param cd `RubyVM::MJIT::CPointer::Struct_rb_call_data`
    def opt_send_without_block(jit, ctx, asm)
      cd = C.rb_call_data.new(jit.operand(0))
      jit_call_method(jit, ctx, asm, cd)
    end

    # objtostring
    # opt_str_freeze

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_nil_p(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # opt_str_uminus
    # opt_newarray_max
    # opt_newarray_min
    # invokesuper
    # invokeblock

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def leave(jit, ctx, asm)
      assert_equal(ctx.stack_size, 1)

      jit_check_ints(jit, ctx, asm)

      asm.comment('pop stack frame')
      asm.lea(:rax, [CFP, C.rb_control_frame_t.size])
      asm.mov(CFP, :rax)
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], :rax)

      # Return a value (for compile_leave_exit)
      ret_opnd = ctx.stack_pop
      asm.mov(:rax, ret_opnd)

      # Set caller's SP and push a value to its stack (for JIT)
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)]) # Note: SP is in the position after popping a receiver and arguments
      asm.mov([SP], :rax)

      # Jump to cfp->jit_return
      asm.jmp([CFP, -C.rb_control_frame_t.size + C.rb_control_frame_t.offsetof(:jit_return)])

      EndBlock
    end

    # throw

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jump(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      pc = jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)
      stub_next_block(jit.iseq, pc, ctx, asm)
      EndBlock
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def branchif(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      # TODO: skip check for known truthy

      # This `test` sets ZF only for Qnil and Qfalse, which let jz jump.
      val = ctx.stack_pop
      asm.test(val, ~Qnil)

      # Set stubs
      branch_stub = BranchStub.new(
        iseq: jit.iseq,
        shape: Default,
        target0: BranchTarget.new(ctx:, pc: jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)), # branch target
        target1: BranchTarget.new(ctx:, pc: jit.pc + C.VALUE.size * jit.insn.len),                 # fallthrough
      )
      branch_stub.target0.address = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
        @ocb.write(ocb_asm)
      end
      branch_stub.target1.address = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, false)
        @ocb.write(ocb_asm)
      end

      # Jump to target0 on jnz
      branch_stub.compile = proc do |branch_asm|
        branch_asm.comment("branchif #{branch_stub.shape}")
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.jnz(branch_stub.target0.address)
            branch_asm.jmp(branch_stub.target1.address)
          in Next0
            branch_asm.jz(branch_stub.target1.address)
          in Next1
            branch_asm.jnz(branch_stub.target0.address)
          end
        end
      end
      branch_stub.compile.call(asm)

      EndBlock
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def branchunless(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      # TODO: skip check for known truthy

      # This `test` sets ZF only for Qnil and Qfalse, which let jz jump.
      val = ctx.stack_pop
      asm.test(val, ~Qnil)

      # Set stubs
      branch_stub = BranchStub.new(
        iseq: jit.iseq,
        shape: Default,
        target0: BranchTarget.new(ctx:, pc: jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)), # branch target
        target1: BranchTarget.new(ctx:, pc: jit.pc + C.VALUE.size * jit.insn.len),                 # fallthrough
      )
      branch_stub.target0.address = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
        @ocb.write(ocb_asm)
      end
      branch_stub.target1.address = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, false)
        @ocb.write(ocb_asm)
      end

      # Jump to target0 on jz
      branch_stub.compile = proc do |branch_asm|
        branch_asm.comment("branchunless #{branch_stub.shape}")
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.jz(branch_stub.target0.address)
            branch_asm.jmp(branch_stub.target1.address)
          in Next0
            branch_asm.jnz(branch_stub.target1.address)
          in Next1
            branch_asm.jz(branch_stub.target0.address)
          end
        end
      end
      branch_stub.compile.call(asm)

      EndBlock
    end

    # branchnil
    # once
    # opt_case_dispatch

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_plus(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        # Generate a side exit before popping operands
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_PLUS)
          return CantCompile
        end

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test(recv_opnd, C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test(obj_opnd, C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.mov(:rax, recv_opnd)
        asm.sub(:rax, 1) # untag
        asm.mov(:rcx, obj_opnd)
        asm.add(:rax, :rcx)
        asm.jo(side_exit)

        dst_opnd = ctx.stack_push
        asm.mov(dst_opnd, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

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
        # Generate a side exit before popping operands
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_MINUS)
          return CantCompile
        end

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test(recv_opnd, C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test(obj_opnd, C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.mov(:rax, recv_opnd)
        asm.mov(:rcx, obj_opnd)
        asm.sub(:rax, :rcx)
        asm.jo(side_exit)
        asm.add(:rax, 1) # re-tag

        dst_opnd = ctx.stack_push
        asm.mov(dst_opnd, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_mult(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_div(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_mod(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        # Create a side-exit to fall back to the interpreter
        # Note: we generate the side-exit before popping operands from the stack
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_MOD)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm, side_exit)

        # Get the operands and destination from the stack
        arg1 = ctx.stack_pop(1)
        arg0 = ctx.stack_pop(1)

        # Check for arg0 % 0
        asm.cmp(arg1, 0)
        asm.je(side_exit)

        # Call rb_fix_mod_fix(VALUE recv, VALUE obj)
        asm.mov(C_ARGS[0], arg0)
        asm.mov(C_ARGS[1], arg1)
        asm.call(C.rb_fix_mod_fix)

        # Push the return value onto the stack
        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_eq(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if jit_equality_specialized(jit, ctx, asm)
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_neq(jit, ctx, asm)
      # opt_neq is passed two rb_call_data as arguments:
      # first for ==, second for !=
      neq_cd = C.rb_call_data.new(jit.operand(1))
      jit_call_method(jit, ctx, asm, neq_cd)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_lt(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovl, bop: C.BOP_LT)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_le(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovle, bop: C.BOP_LE)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_gt(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovg, bop: C.BOP_GT)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_ge(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovge, bop: C.BOP_GE)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_ltlt(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_and(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        # Create a side-exit to fall back to the interpreter
        # Note: we generate the side-exit before popping operands from the stack
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_AND)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm, side_exit)

        # Get the operands and destination from the stack
        arg1 = ctx.stack_pop(1)
        arg0 = ctx.stack_pop(1)

        asm.comment('bitwise and')
        asm.mov(:rax, arg0)
        asm.and(:rax, arg1)

        # Push the return value onto the stack
        dst = ctx.stack_push
        asm.mov(dst, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_or(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        # Create a side-exit to fall back to the interpreter
        # Note: we generate the side-exit before popping operands from the stack
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_OR)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm, side_exit)

        # Get the operands and destination from the stack
        asm.comment('bitwise or')
        arg1 = ctx.stack_pop(1)
        arg0 = ctx.stack_pop(1)

        # Do the bitwise or arg0 | arg1
        asm.mov(:rax, arg0)
        asm.or(:rax, arg1)

        # Push the return value onto the stack
        dst = ctx.stack_push
        asm.mov(dst, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_aref(jit, ctx, asm)
      cd = C.rb_call_data.new(jit.operand(0))
      argc = C.vm_ci_argc(cd.ci)

      if argc != 1
        asm.incr_counter(:optaref_argc_not_one)
        return CantCompile
      end

      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      side_exit = side_exit(jit, ctx)

      if comptime_recv.class == Array && fixnum?(comptime_obj)
        unless Invariants.assume_bop_not_redefined(jit, C.ARRAY_REDEFINED_OP_FLAG, C.BOP_AREF)
          return CantCompile
        end

        idx_opnd = ctx.stack_opnd(0)
        recv_opnd = ctx.stack_opnd(1)

        not_array_exit = counted_exit(side_exit, :optaref_recv_not_array)
        if jit_guard_known_class(jit, ctx, asm, comptime_recv.class, recv_opnd, comptime_recv, not_array_exit) == CantCompile
          return CantCompile
        end

        # Bail if idx is not a FIXNUM
        asm.mov(:rax, idx_opnd)
        asm.test(:rax, C.RUBY_FIXNUM_FLAG)
        asm.jz(counted_exit(side_exit, :optaref_arg_not_fixnum))

        # Call VALUE rb_ary_entry_internal(VALUE ary, long offset).
        # It never raises or allocates, so we don't need to write to cfp->pc.
        asm.sar(:rax, 1) # Convert fixnum to int
        asm.mov(C_ARGS[0], recv_opnd)
        asm.mov(C_ARGS[1], :rax)
        asm.call(C.rb_ary_entry_internal)

        # Pop the argument and the receiver
        ctx.stack_pop(2)

        # Push the return value onto the stack
        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)

        # Let guard chains share the same successor
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      elsif comptime_recv.class == Hash
        unless Invariants.assume_bop_not_redefined(jit, C.HASH_REDEFINED_OP_FLAG, C.BOP_AREF)
          return CantCompile
        end

        recv_opnd = ctx.stack_opnd(1)

        # Guard that the receiver is a Hash
        not_hash_exit = counted_exit(side_exit, :optaref_recv_not_hash)
        if jit_guard_known_class(jit, ctx, asm, comptime_recv.class, recv_opnd, comptime_recv, not_hash_exit) == CantCompile
          return CantCompile
        end

        # Prepare to call rb_hash_aref(). It might call #hash on the key.
        jit_prepare_routine_call(jit, ctx, asm)

        asm.comment('call rb_hash_aref')
        key_opnd = ctx.stack_opnd(0)
        recv_opnd = ctx.stack_opnd(1)
        asm.mov(:rdi, recv_opnd)
        asm.mov(:rsi, key_opnd)
        asm.call(C.rb_hash_aref)

        # Pop the key and the receiver
        ctx.stack_pop(2)

        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)

        # Let guard chains share the same successor
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # opt_aset
    # opt_aset_with
    # opt_aref_with

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_length(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_size(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_empty_p(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_succ(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_not(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def opt_regexpmatch2(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

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
      stack_top = ctx.stack_push
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def getlocal_WC_1(jit, ctx, asm)
      # Get operands
      idx = jit.operand(0)
      level = 1

      # Get EP
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Get a local variable
      asm.mov(:rax, [ep_reg, -idx * C.VALUE.size])

      # Push it to the stack
      stack_top = ctx.stack_push
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    # setlocal_WC_0
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def setlocal_WC_0(jit, ctx, asm)
      slot_idx = jit.operand(0)
      local_idx = slot_to_local_idx(jit.iseq, slot_idx)

      # Load environment pointer EP (level 0) from CFP
      ep_reg = :rax
      jit_get_ep(asm, 0, reg: ep_reg)

      # Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
      # only affect heap objects being written. If we know an immediate value is being written we
      # can skip this check.

      # flags & VM_ENV_FLAG_WB_REQUIRED
      flags_opnd = [ep_reg, C.VALUE.size * C.VM_ENV_DATA_INDEX_FLAGS]
      asm.test(flags_opnd, C.VM_ENV_FLAG_WB_REQUIRED)

      # Create a side-exit to fall back to the interpreter
      side_exit = side_exit(jit, ctx)

      # if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
      asm.jnz(side_exit)

      # Pop the value to write from the stack
      stack_top = ctx.stack_pop(1)

      # Write the value at the environment pointer
      asm.mov(:rcx, stack_top)
      asm.mov([ep_reg, -8 * slot_idx], :rcx)

      KeepCompiling
    end

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

    # Compute the index of a local variable from its slot index
    def slot_to_local_idx(iseq, slot_idx)
      # Layout illustration
      # This is an array of VALUE
      #                                           | VM_ENV_DATA_SIZE |
      #                                           v                  v
      # low addr <+-------+-------+-------+-------+------------------+
      #           |local 0|local 1|  ...  |local n|       ....       |
      #           +-------+-------+-------+-------+------------------+
      #           ^       ^                       ^                  ^
      #           +-------+---local_table_size----+         cfp->ep--+
      #                   |                                          |
      #                   +------------------slot_idx----------------+
      #
      # See usages of local_var_name() from iseq.c for similar calculation.

      local_table_size = iseq.body.local_table_size
      op = slot_idx - C.VM_ENV_DATA_SIZE
      local_table_size - op - 1
    end

    # @param asm [RubyVM::MJIT::Assembler]
    def guard_object_is_heap(asm, object_opnd, side_exit)
      asm.comment('guard object is heap')
      # Test that the object is not an immediate
      asm.test(object_opnd, C.RUBY_IMMEDIATE_MASK)
      asm.jnz(side_exit)

      # Test that the object is not false
      asm.cmp(object_opnd, Qfalse)
      asm.je(side_exit)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_chain_guard(opcode, jit, ctx, asm, side_exit, limit: 10)
      opcode => :je | :jne | :jnz | :jz

      if ctx.chain_depth < limit
        deeper = ctx.dup
        deeper.chain_depth += 1

        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx: deeper, pc: jit.pc),
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(deeper, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.compile = proc do |branch_asm|
          # Not using `asm.comment` here since it's usually put before cmp/test before this.
          branch_asm.stub(branch_stub) do
            case branch_stub.shape
            in Default
              branch_asm.public_send(opcode, branch_stub.target0.address)
            end
          end
        end
        branch_stub.compile.call(asm)
      else
        asm.public_send(opcode, side_exit)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_guard_known_class(jit, ctx, asm, known_klass, obj_opnd, comptime_obj, side_exit, limit: 5)
      # Only memory operand is supported for now
      assert_equal(true, obj_opnd.is_a?(Array))

      if known_klass == NilClass
        asm.comment('guard object is nil')
        asm.cmp(obj_opnd, Qnil)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == TrueClass
        asm.comment('guard object is true')
        asm.cmp(obj_opnd, Qtrue)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == FalseClass
        asm.comment('guard object is false')
        asm.cmp(obj_opnd, Qfalse)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == Integer && fixnum?(comptime_obj)
        asm.comment('guard object is fixnum')
        asm.test(obj_opnd, C.RUBY_FIXNUM_FLAG)
        jit_chain_guard(:jz, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == Symbol
        asm.incr_counter(:send_guard_symbol)
        return CantCompile
      elsif known_klass == Float
        asm.incr_counter(:send_guard_float)
        return CantCompile
      elsif known_klass.singleton_class?
        asm.comment('guard known object with singleton class')
        asm.mov(:rax, C.to_value(comptime_obj))
        asm.cmp(obj_opnd, :rax)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      else
        # Load memory to a register
        asm.mov(:rax, obj_opnd)
        obj_opnd = :rax

        # Check that the receiver is a heap object
        # Note: if we get here, the class doesn't have immediate instances.
        asm.comment('guard not immediate')
        asm.test(obj_opnd, C.RUBY_IMMEDIATE_MASK)
        jit_chain_guard(:jnz, jit, ctx, asm, side_exit, limit:)
        asm.cmp(obj_opnd, Qfalse)
        jit_chain_guard(:je, jit, ctx, asm, side_exit, limit:)

        # Bail if receiver class is different from known_klass
        klass_opnd = [obj_opnd, C.RBasic.offsetof(:klass)]
        asm.comment('guard known class')
        asm.mov(:rcx, to_value(known_klass))
        asm.cmp(klass_opnd, :rcx)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    def two_fixnums_on_stack?(jit)
      comptime_recv = jit.peek_at_stack(1)
      comptime_arg = jit.peek_at_stack(0)
      return fixnum?(comptime_recv) && fixnum?(comptime_arg)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def guard_two_fixnums(jit, ctx, asm, side_exit)
      # Get stack operands without popping them
      arg1 = ctx.stack_opnd(0)
      arg0 = ctx.stack_opnd(1)

      asm.comment('guard arg0 fixnum')
      asm.test(arg0, C.RUBY_FIXNUM_FLAG)
      jit_chain_guard(:jz, jit, ctx, asm, side_exit)
      # TODO: upgrade type, and skip the check when possible

      asm.comment('guard arg1 fixnum')
      asm.test(arg1, C.RUBY_FIXNUM_FLAG)
      jit_chain_guard(:jz, jit, ctx, asm, side_exit)
      # TODO: upgrade type, and skip the check when possible
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_fixnum_cmp(jit, ctx, asm, opcode:, bop:)
      opcode => :cmovl | :cmovle | :cmovg | :cmovge

      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        # Generate a side exit before popping operands
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, bop)
          return CantCompile
        end

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test(recv_opnd, C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test(obj_opnd, C.RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.mov(:rax, obj_opnd)
        asm.cmp(recv_opnd, :rax)
        asm.mov(:rax, Qfalse)
        asm.mov(:rcx, Qtrue)
        asm.public_send(opcode, :rax, :rcx)

        dst_opnd = ctx.stack_push
        asm.mov(dst_opnd, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_equality_specialized(jit, ctx, asm)
      # Create a side-exit to fall back to the interpreter
      side_exit = side_exit(jit, ctx)

      a_opnd = ctx.stack_opnd(1)
      b_opnd = ctx.stack_opnd(0)

      comptime_a = jit.peek_at_stack(1)
      comptime_b = jit.peek_at_stack(0)

      if two_fixnums_on_stack?(jit)
        unless Invariants.assume_bop_not_redefined(jit, C.INTEGER_REDEFINED_OP_FLAG, C.BOP_EQ)
          return false
        end

        guard_two_fixnums(jit, ctx, asm, side_exit)

        asm.comment('check fixnum equality')
        asm.mov(:rax, a_opnd)
        asm.mov(:rcx, b_opnd)
        asm.cmp(:rax, :rcx)
        asm.mov(:rax, Qfalse)
        asm.mov(:rcx, Qtrue)
        asm.cmove(:rax, :rcx)

        # Push the output on the stack
        ctx.stack_pop(2)
        dst = ctx.stack_push
        asm.mov(dst, :rax)

        true
      elsif comptime_a.class == String && comptime_b.class == String
        unless Invariants.assume_bop_not_redefined(jit, C.STRING_REDEFINED_OP_FLAG, C.BOP_EQ)
          # if overridden, emit the generic version
          return false
        end

        # Guard that a is a String
        if jit_guard_known_class(jit, ctx, asm, comptime_a.class, a_opnd, comptime_a, side_exit) == CantCompile
          return false
        end

        equal_label = asm.new_label(:equal)
        ret_label = asm.new_label(:ret)

        # If they are equal by identity, return true
        asm.mov(:rax, a_opnd)
        asm.mov(:rcx, b_opnd)
        asm.cmp(:rax, :rcx)
        asm.je(equal_label)

        # Otherwise guard that b is a T_STRING (from type info) or String (from runtime guard)
        # Note: any T_STRING is valid here, but we check for a ::String for simplicity
        # To pass a mutable static variable (rb_cString) requires an unsafe block
        if jit_guard_known_class(jit, ctx, asm, comptime_b.class, b_opnd, comptime_b, side_exit) == CantCompile
          return false
        end

        asm.comment('call rb_str_eql_internal')
        asm.mov(C_ARGS[0], a_opnd)
        asm.mov(C_ARGS[1], b_opnd)
        asm.call(C.rb_str_eql_internal)

        # Push the output on the stack
        ctx.stack_pop(2)
        dst = ctx.stack_push
        asm.mov(dst, C_RET)
        asm.jmp(ret_label)

        asm.write_label(equal_label)
        asm.mov(dst, Qtrue)

        asm.write_label(ret_label)

        true
      else
        false
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_prepare_routine_call(jit, ctx, asm)
      jit_save_pc(jit, asm)
      jit_save_sp(jit, ctx, asm)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_save_pc(jit, asm, comment: 'save PC to CFP')
      next_pc = jit.pc + jit.insn.len * C.VALUE.size # Use the next one for backtrace and side exits
      asm.comment(comment)
      asm.mov(:rax, next_pc)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax)
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_save_sp(jit, ctx, asm)
      if ctx.sp_offset != 0
        asm.comment('save SP to CFP')
        asm.lea(SP, ctx.sp_opnd)
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)
        ctx.sp_offset = 0
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jump_to_next_insn(jit, ctx, asm)
      reset_depth = ctx.dup
      reset_depth.chain_depth = 0

      next_pc = jit.pc + jit.insn.len * C.VALUE.size
      stub_next_block(jit.iseq, next_pc, reset_depth, asm, comment: 'jump_to_next_insn')
    end

    # rb_vm_check_ints
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_check_ints(jit, ctx, asm)
      asm.comment('RUBY_VM_CHECK_INTS(ec)')
      asm.mov(:eax, [EC, C.rb_execution_context_t.offsetof(:interrupt_flag)])
      asm.test(:eax, :eax)
      asm.jnz(side_exit(jit, ctx))
    end

    # vm_get_ep
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_get_ep(asm, level, reg:)
      asm.mov(reg, [CFP, C.rb_control_frame_t.offsetof(:ep)])
      level.times do
        # GET_PREV_EP: ep[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03
        asm.mov(reg, [reg, C.VALUE.size * C.VM_ENV_DATA_INDEX_SPECVAL])
        asm.and(reg, ~0x03)
      end
    end

    # vm_getivar
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_getivar(jit, ctx, asm, comptime_obj, ivar_id, obj_opnd = nil)
      side_exit = side_exit(jit, ctx)
      starting_ctx = ctx.dup # copy for jit_chain_guard

      # Guard not special const
      if C.SPECIAL_CONST_P(comptime_obj)
        asm.incr_counter(:getivar_special_const)
        return CantCompile
      end
      if obj_opnd.nil? # getivar
        asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
      else # attr_reader
        asm.mov(:rax, obj_opnd)
      end
      guard_object_is_heap(asm, :rax, counted_exit(side_exit, :getivar_not_heap))

      case C.BUILTIN_TYPE(comptime_obj)
      when C.T_OBJECT
        # This is the only supported case for now (ROBJECT_IVPTR)
      else
        asm.incr_counter(:getivar_not_t_object)
        return CantCompile
      end

      shape_id = C.rb_shape_get_shape_id(comptime_obj)
      if shape_id == C.OBJ_TOO_COMPLEX_SHAPE_ID
        asm.incr_counter(:getivar_too_complex)
        return CantCompile
      end

      asm.comment('guard shape')
      asm.cmp(DwordPtr[:rax, C.rb_shape_id_offset], shape_id)
      jit_chain_guard(:jne, jit, starting_ctx, asm, counted_exit(side_exit, :getivar_megamorphic))

      index = C.rb_shape_get_iv_index(shape_id, ivar_id)
      if index
        asm.comment('ROBJECT_IVPTR')
        if C.FL_TEST_RAW(comptime_obj, C.ROBJECT_EMBED)
          # Access embedded array
          asm.mov(:rax, [:rax, C.RObject.offsetof(:as, :ary) + (index * C.VALUE.size)])
        else
          # Pull out an ivar table on heap
          asm.mov(:rax, [:rax, C.RObject.offsetof(:as, :heap, :ivptr)])
          # Read the table
          asm.mov(:rax, [:rax, index * C.VALUE.size])
        end
        val_opnd = :rax
      else
        val_opnd = Qnil
      end

      if obj_opnd
        ctx.stack_pop # pop receiver for attr_reader
      end
      stack_opnd = ctx.stack_push
      asm.mov(stack_opnd, val_opnd)

      # Let guard chains share the same successor
      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # vm_call_method (vm_sendish -> vm_call_general -> vm_call_method)
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param cd `RubyVM::MJIT::CPointer::Struct_rb_call_data`
    def jit_call_method(jit, ctx, asm, cd)
      ci = cd.ci
      argc = C.vm_ci_argc(ci)
      mid = C.vm_ci_mid(ci)
      flags = C.vm_ci_flag(ci)

      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      # Generate a side exit
      side_exit = side_exit(jit, ctx)

      # Calculate a receiver index
      if flags & C.VM_CALL_KW_SPLAT != 0
        # recv_index calculation may not work for this
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end
      recv_index = argc # TODO: +1 for VM_CALL_ARGS_BLOCKARG

      # Get a compile-time receiver and its class
      comptime_recv = jit.peek_at_stack(recv_index)
      comptime_recv_klass = C.rb_class_of(comptime_recv)

      # Guard the receiver class (part of vm_search_method_fastpath)
      recv_opnd = ctx.stack_opnd(recv_index)
      megamorphic_exit = counted_exit(side_exit, :send_klass_megamorphic)
      if jit_guard_known_class(jit, ctx, asm, comptime_recv_klass, recv_opnd, comptime_recv, megamorphic_exit) == CantCompile
        return CantCompile
      end

      # Do method lookup (vm_cc_cme(cc) != NULL)
      cme = C.rb_callable_method_entry(comptime_recv_klass, mid)
      if cme.nil?
        asm.incr_counter(:send_missing_cme)
        return CantCompile # We don't support vm_call_method_name
      end

      # The main check of vm_call_method before vm_call_method_each_type
      case C.METHOD_ENTRY_VISI(cme)
      when C.METHOD_VISI_PUBLIC
        # You can always call public methods
      when C.METHOD_VISI_PRIVATE
        # Allow only callsites without a receiver
        if flags & C.VM_CALL_FCALL == 0
          asm.incr_counter(:send_private)
          return CantCompile
        end
      when C.METHOD_VISI_PROTECTED
        asm.incr_counter(:send_protected)
        return CantCompile # TODO: support this
      else
        # TODO: Change them to a constant and use case-in instead
        raise 'unreachable'
      end

      # Invalidate on redefinition (part of vm_search_method_fastpath)
      Invariants.assume_method_lookup_stable(jit, cme)

      jit_call_method_each_type(jit, ctx, asm, ci, argc, flags, cme, comptime_recv, recv_opnd)
    end

    # vm_call_method_each_type
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_call_method_each_type(jit, ctx, asm, ci, argc, flags, cme, comptime_recv, recv_opnd)
      case cme.def.type
      when C.VM_METHOD_TYPE_ISEQ
        jit_call_iseq_setup(jit, ctx, asm, ci, cme, flags, argc)
      # when C.VM_METHOD_TYPE_NOTIMPLEMENTED
      when C.VM_METHOD_TYPE_CFUNC
        jit_call_cfunc(jit, ctx, asm, ci, cme, flags, argc)
      when C.VM_METHOD_TYPE_ATTRSET
        asm.incr_counter(:send_attrset)
        return CantCompile
      when C.VM_METHOD_TYPE_IVAR
        jit_call_ivar(jit, ctx, asm, ci, cme, flags, argc, comptime_recv, recv_opnd)
      # when C.VM_METHOD_TYPE_MISSING
      when C.VM_METHOD_TYPE_BMETHOD
        asm.incr_counter(:send_bmethod)
        return CantCompile
      when C.VM_METHOD_TYPE_ALIAS
        asm.incr_counter(:send_alias)
        return CantCompile
      when C.VM_METHOD_TYPE_OPTIMIZED
        asm.incr_counter(:send_optimized)
        return CantCompile
      # when C.VM_METHOD_TYPE_UNDEF
      when C.VM_METHOD_TYPE_ZSUPER
        asm.incr_counter(:send_zsuper)
        return CantCompile
      when C.VM_METHOD_TYPE_REFINED
        asm.incr_counter(:send_refined)
        return CantCompile
      else
        asm.incr_counter(:send_not_implemented_type)
        return CantCompile
      end
    end

    # vm_call_iseq_setup
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_call_iseq_setup(jit, ctx, asm, ci, cme, flags, argc)
      iseq = def_iseq_ptr(cme.def)
      opt_pc = jit_callee_setup_arg(jit, ctx, asm, ci, flags, iseq)
      if opt_pc == CantCompile
        # We hit some unsupported path of vm_callee_setup_arg
        return CantCompile
      end

      if flags & C.VM_CALL_TAILCALL != 0
        # We don't support vm_call_iseq_setup_tailcall
        asm.incr_counter(:send_tailcall)
        return CantCompile
      end
      jit_call_iseq_setup_normal(jit, ctx, asm, ci, cme, flags, argc, iseq)
    end

    # vm_call_iseq_setup_normal (vm_call_iseq_setup_2 -> vm_call_iseq_setup_normal)
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_call_iseq_setup_normal(jit, ctx, asm, ci, cme, flags, argc, iseq)
      # Save caller SP and PC before pushing a callee frame for backtrace and side exits
      asm.comment('save SP to caller CFP')
      # Not setting this to SP register. This cfp->sp will be copied to SP on leave insn.
      sp_index = -(1 + argc) # Pop receiver and arguments for side exits # TODO: subtract one more for VM_CALL_ARGS_BLOCKARG
      asm.lea(:rax, ctx.sp_opnd(C.VALUE.size * sp_index))
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], :rax)
      jit_save_pc(jit, asm, comment: 'save PC to caller CFP')

      frame_type = C.VM_FRAME_MAGIC_METHOD | C.VM_ENV_FLAG_LOCAL
      jit_push_frame(
        jit, ctx, asm, ci, cme, flags, argc, frame_type,
        iseq:       iseq,
        local_size: iseq.body.local_table_size - iseq.body.param.size,
        stack_max:  iseq.body.stack_max,
      )

      # Jump to a stub for the callee ISEQ
      callee_ctx = Context.new
      stub_next_block(iseq, iseq.body.iseq_encoded.to_i, callee_ctx, asm)

      EndBlock
    end

    # vm_call_cfunc
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_call_cfunc(jit, ctx, asm, ci, cme, flags, argc)
      if jit_caller_setup_arg(jit, ctx, asm, flags) == CantCompile
        return CantCompile
      end
      if jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags) == CantCompile
        return CantCompile
      end

      jit_call_cfunc_with_frame(jit, ctx, asm, ci, cme, flags, argc)
    end

    # jit_call_cfunc_with_frame
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_call_cfunc_with_frame(jit, ctx, asm, ci, cme, flags, argc)
      cfunc = cme.def.body.cfunc

      if argc + 1 > 6
        asm.incr_counter(:send_cfunc_too_many_args)
        return CantCompile
      end

      frame_type = C.VM_FRAME_MAGIC_CFUNC | C.VM_FRAME_FLAG_CFRAME | C.VM_ENV_FLAG_LOCAL
      if flags & C.VM_CALL_KW_SPLAT != 0
        frame_type |= C.VM_FRAME_FLAG_CFRAME_KW
      end

      # EXEC_EVENT_HOOK: RUBY_EVENT_C_CALL and RUBY_EVENT_C_RETURN
      if C.rb_mjit_global_events & (C.RUBY_EVENT_C_CALL | C.RUBY_EVENT_C_RETURN) != 0
        asm.incr_counter(:send_c_tracing)
        return CantCompile
      end

      # rb_check_arity
      if cfunc.argc >= 0 && argc != cfunc.argc
        asm.incr_counter(:send_arity)
        return CantCompile
      end

      # Check interrupts before SP motion to safely side-exit with the original SP.
      jit_check_ints(jit, ctx, asm)

      # Save caller SP and PC before pushing a callee frame for backtrace and side exits
      asm.comment('save SP to caller CFP')
      sp_index = -(1 + argc) # Pop receiver and arguments for side exits # TODO: subtract one more for VM_CALL_ARGS_BLOCKARG
      asm.lea(SP, ctx.sp_opnd(C.VALUE.size * sp_index))
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)
      ctx.sp_offset = -sp_index
      jit_save_pc(jit, asm, comment: 'save PC to caller CFP')

      # Push a callee frame. SP register and ctx are not modified inside this.
      jit_push_frame(jit, ctx, asm, ci, cme, flags, argc, frame_type)

      asm.comment('call C function')
      case cfunc.argc
      in (0..) # Non-variadic method
        # Push receiver and args
        (1 + argc).times do |i|
          asm.mov(C_ARGS[i], ctx.stack_opnd(argc - i)) # TODO: +1 for VM_CALL_ARGS_BLOCKARG
        end
      in -1 # Variadic method: rb_f_puts(int argc, VALUE *argv, VALUE recv)
        asm.mov(C_ARGS[0], argc)
        asm.lea(C_ARGS[1], ctx.stack_opnd(argc - 1)) # argv
        asm.mov(C_ARGS[2], ctx.stack_opnd(argc)) # recv
      end
      asm.mov(:rax, cfunc.func)
      asm.call(:rax) # TODO: use rel32 if close enough
      ctx.stack_pop(1 + argc)

      Invariants.record_global_inval_patch(asm, @full_cfunc_return)

      asm.comment('push the return value')
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      asm.comment('pop the stack frame')
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], CFP)

      # Let guard chains share the same successor (ctx.sp_offset == 1)
      assert_equal(1, ctx.sp_offset)
      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # vm_call_ivar
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_call_ivar(jit, ctx, asm, ci, cme, flags, argc, comptime_recv, recv_opnd)
      if flags & C.VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_ivar_splat)
        return CantCompile
      end

      if argc != 0
        asm.incr_counter(:send_arity)
        return CantCompile
      end

      if flags & C.VM_CALL_OPT_SEND != 0
        asm.incr_counter(:send_ivar_opt_send)
        return CantCompile
      end

      ivar_id = cme.def.body.attr.id

      if flags & C.VM_CALL_OPT_SEND != 0
        asm.incr_counter(:send_ivar_blockarg)
        return CantCompile
      end

      jit_getivar(jit, ctx, asm, comptime_recv, ivar_id, recv_opnd)
    end

    # vm_push_frame
    #
    # Frame structure:
    # | args | locals | cme/cref | block_handler/prev EP | frame type (EP here) | stack bottom (SP here)
    #
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_push_frame(jit, ctx, asm, ci, cme, flags, argc, frame_type, iseq: nil, local_size: 0, stack_max: 0)
      # CHECK_VM_STACK_OVERFLOW0: next_cfp <= sp + (local_size + stack_max)
      asm.comment('stack overflow check')
      asm.lea(:rax, ctx.sp_opnd(C.rb_control_frame_t.size + C.VALUE.size * (local_size + stack_max)))
      asm.cmp(CFP, :rax)
      asm.jbe(counted_exit(side_exit(jit, ctx), :send_stackoverflow))

      local_size.times do |i|
        asm.comment('set local variables') if i == 0
        local_index = ctx.sp_offset + i
        asm.mov([SP, C.VALUE.size * local_index], Qnil)
      end

      asm.comment('set up EP with managing data')
      ep_offset = ctx.sp_offset + local_size + 2
      asm.mov(:rax, cme.to_i)
      asm.mov([SP, C.VALUE.size * (ep_offset - 2)], :rax)
      asm.mov([SP, C.VALUE.size * (ep_offset - 1)], C.VM_BLOCK_HANDLER_NONE)
      asm.mov([SP, C.VALUE.size * (ep_offset - 0)], frame_type)

      asm.comment('set up new frame')
      cfp_offset = -C.rb_control_frame_t.size # callee CFP
      # For ISEQ, JIT code will set it as needed. However, C func needs 0 there for svar frame detection.
      if iseq.nil?
        asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:pc)], 0)
      end
      asm.mov(:rax, iseq.to_i)
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:iseq)], :rax)
      self_index = ctx.sp_offset - (1 + argc) # TODO: +1 for VM_CALL_ARGS_BLOCKARG
      asm.mov(:rax, [SP, C.VALUE.size * self_index])
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:self)], :rax)
      asm.lea(:rax, [SP, C.VALUE.size * ep_offset])
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:ep)], :rax)
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:block_code)], 0)
      # Update SP register only for ISEQ calls. SP-relative operations should be done above this.
      sp_reg = iseq ? SP : :rax
      asm.lea(sp_reg, [SP, C.VALUE.size * (ctx.sp_offset + local_size + 3)])
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:sp)], sp_reg)
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:__bp__)], sp_reg) # TODO: get rid of this!!

      # cfp->jit_return is used only for ISEQs
      if iseq
        # Stub cfp->jit_return
        return_ctx = ctx.dup
        return_ctx.stack_size -= argc # Pop args # TODO: subtract 1 more for VM_CALL_ARGS_BLOCKARG
        return_ctx.sp_offset = 1 # SP is in the position after popping a receiver and arguments
        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx: return_ctx, pc: jit.pc + jit.insn.len * C.VALUE.size),
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(return_ctx, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.compile = proc do |branch_asm|
          branch_asm.comment('set jit_return to callee CFP')
          branch_asm.stub(branch_stub) do
            case branch_stub.shape
            in Default
              branch_asm.mov(:rax, branch_stub.target0.address)
              branch_asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:jit_return)], :rax)
            end
          end
        end
        branch_stub.compile.call(asm)
      end

      asm.comment('switch to callee CFP')
      # Update CFP register only for ISEQ calls
      cfp_reg = iseq ? CFP : :rax
      asm.lea(cfp_reg, [CFP, cfp_offset])
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], cfp_reg)
    end

    # vm_callee_setup_arg: Set up args and return opt_pc (or CantCompile)
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_callee_setup_arg(jit, ctx, asm, ci, flags, iseq)
      if flags & C.VM_CALL_KW_SPLAT == 0
        if C.rb_simple_iseq_p(iseq)
          if jit_caller_setup_arg(jit, ctx, asm, flags) == CantCompile
            return CantCompile
          end
          if jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags) == CantCompile
            return CantCompile
          end

          if C.vm_ci_argc(ci) != iseq.body.param.lead_num
            # argument_arity_error
            return CantCompile
          end

          return 0
        else
          # We don't support the remaining `else if`s yet.
          asm.incr_counter(:send_iseq_not_simple)
          return CantCompile
        end
      end

      # We don't support setup_parameters_complex
      asm.incr_counter(:send_iseq_kw_splat)
      return CantCompile
    end

    # CALLER_SETUP_ARG: Return CantCompile if not supported
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_caller_setup_arg(jit, ctx, asm, flags)
      if flags & C.VM_CALL_ARGS_SPLAT != 0
        # We don't support vm_caller_setup_arg_splat
        asm.incr_counter(:send_args_splat)
        return CantCompile
      end
      if flags & (C.VM_CALL_KWARG | C.VM_CALL_KW_SPLAT) != 0
        # We don't support keyword args either
        asm.incr_counter(:send_kwarg)
        return CantCompile
      end
    end

    # CALLER_REMOVE_EMPTY_KW_SPLAT: Return CantCompile if not supported
    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags)
      if (flags & C.VM_CALL_KW_SPLAT) > 0
        # We don't support removing the last Hash argument
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end
    end

    def assert_equal(left, right)
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
      stub_next_block(jit.iseq, jit.pc, ctx, asm, comment: 'defer_compilation')
    end

    def stub_next_block(iseq, pc, ctx, asm, comment: 'stub_next_block')
      branch_stub = BranchStub.new(
        iseq:,
        shape: Default,
        target0: BranchTarget.new(ctx:, pc:),
      )
      branch_stub.target0.address = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
        @ocb.write(ocb_asm)
      end
      branch_stub.compile = proc do |branch_asm|
        branch_asm.comment(comment)
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.jmp(branch_stub.target0.address)
          in Next0
            # Just write the block without a jump
          end
        end
      end
      branch_stub.compile.call(asm)
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

    def counted_exit(side_exit, name)
      asm = Assembler.new
      asm.incr_counter(name)
      asm.jmp(side_exit)
      @ocb.write(asm)
    end

    def def_iseq_ptr(cme_def)
      C.rb_iseq_check(cme_def.body.iseq.iseqptr)
    end

    def to_value(obj)
      @gc_refs << obj
      C.to_value(obj)
    end
  end
end
