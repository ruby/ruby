module RubyVM::MJIT
  class InsnCompiler
    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::MJIT::ExitCompiler]
    def initialize(ocb, exit_compiler)
      @ocb = ocb
      @exit_compiler = exit_compiler
      @invariants = Invariants.new(ocb, exit_compiler)
      # freeze # workaround a binding.irb issue. TODO: resurrect this
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param insn `RubyVM::MJIT::Instruction`
    def compile(jit, ctx, asm, insn)
      asm.incr_counter(:mjit_insns_count)
      asm.comment("Insn: #{insn.name}")

      # 11/101
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
      when :opt_send_without_block then opt_send_without_block(jit, ctx, asm)
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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param cd `RubyVM::MJIT::CPointer::Struct_rb_call_data`
    def opt_send_without_block(jit, ctx, asm)
      cd = C.rb_call_data.new(jit.operand(0))
      compile_send_general(jit, ctx, asm, cd)
    end

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

      compile_check_ints(jit, ctx, asm)

      asm.comment('pop stack frame')
      asm.lea(:rax, [CFP, C.rb_control_frame_t.size])
      asm.mov(CFP, :rax)
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], :rax)

      # Return a value (for compile_leave_exit)
      asm.mov(:rax, [SP])

      # Set caller's SP and push a value to its stack (for JIT)
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)])
      asm.mov([SP], :rax)

      # Jump to cfp->jit_return
      asm.jmp([CFP, -C.rb_control_frame_t.size + C.rb_control_frame_t.offsetof(:jit_return)])

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

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    def compile_check_ints(jit, ctx, asm)
      asm.comment('RUBY_VM_CHECK_INTS(ec)')
      asm.mov(:eax, [EC, C.rb_execution_context_t.offsetof(:interrupt_flag)])
      asm.test(:eax, :eax)
      asm.jnz(side_exit(jit, ctx))
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::Assembler]
    # @param cd `RubyVM::MJIT::CPointer::Struct_rb_call_data`
    def compile_send_general(jit, ctx, asm, cd)
      ci = cd.ci
      argc = C.vm_ci_argc(ci)
      mid = C.vm_ci_mid(ci)
      flags = C.vm_ci_flag(ci)

      if flags & C.VM_CALL_KW_SPLAT != 0
        return CantCompile
      end

      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
      recv_depth = argc + ((flags & C.VM_CALL_ARGS_BLOCKARG == 0) ? 0 : 1)
      recv_index = ctx.stack_size - 1 - recv_depth

      comptime_recv = jit.peek_at_stack(recv_depth)
      comptime_recv_klass = C.rb_class_of(comptime_recv)

      # Guard known class
      if comptime_recv_klass.singleton_class?
        asm.comment('guard known object with singleton class')
        asm.mov(:rax, C.to_value(comptime_recv))
        asm.cmp([SP, C.VALUE.size * recv_index], :rax)
        asm.jne(side_exit(jit, ctx))
      else
        return CantCompile
      end

      # Do method lookup
      cme = C.rb_callable_method_entry(comptime_recv_klass, mid)
      if cme.nil?
        return CantCompile
      end

      case C.METHOD_ENTRY_VISI(cme)
      when C.METHOD_VISI_PUBLIC
        # You can always call public methods
      when C.METHOD_VISI_PRIVATE
        if flags & C.VM_CALL_FCALL == 0
          # VM_CALL_FCALL: Callsites without a receiver of an explicit `self` receiver
          return CantCompile
        end
      when C.METHOD_VISI_PROTECTED
        return CantCompile # TODO: support this
      else
        raise 'cmes should always have a visibility'
      end

      # TODO: assume_method_lookup_stable

      if flags & C.VM_CALL_ARGS_SPLAT != 0 && cme.def.type != C.VM_METHOD_TYPE_ISEQ
        return CantCompile
      end

      case cme.def.type
      when C.VM_METHOD_TYPE_ISEQ
        iseq = def_iseq_ptr(cme.def)
        frame_type = C.VM_FRAME_MAGIC_METHOD | C.VM_ENV_FLAG_LOCAL
        compile_send_iseq(jit, ctx, asm, iseq, ci, frame_type, cme, flags, argc)
      else
        return CantCompile
      end
    end

    def compile_send_iseq(jit, ctx, asm, iseq, ci, frame_type, cme, flags, argc)
      # TODO: check a bunch of CantCompile cases

      compile_check_ints(jit, ctx, asm)

      # TODO: stack overflow check

      # TODO: more flag checks

      # Pop arguments and a receiver for the current caller frame
      raise 'sp_offset != stack_size' if ctx.sp_offset != ctx.stack_size # TODO: handle this
      sp_index = ctx.stack_size - argc - 1 # arguments and receiver
      asm.comment('save SP to caller CFP')
      asm.lea(:rax, [SP, sp_index])
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], :rax)
      # TODO: do something about ctx.sp_index

      asm.comment('save PC to CFP')
      next_pc = jit.pc + jit.insn.len * C.VALUE.size
      asm.mov(:rax, next_pc)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # TODO: push cme, specval, frame type
      # TODO: push callee control frame

      asm.comment('switch to new CFP')
      asm.lea(:rax, [CFP, -C.rb_control_frame_t.size])
      asm.mov(CFP, :rax);
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], :rax)

      asm.comment('save SP to callee CFP')
      num_locals = 0 # TODO
      sp_offset = C.VALUE.size * (3 + num_locals + ctx.stack_size)
      asm.add(SP, sp_offset)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)

      asm.comment('save ISEQ to callee CFP')
      asm.mov(:rax, iseq.to_i)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:iseq)], :rax)

      asm.comment('save EP to callee CFP')
      asm.lea(:rax, [SP, -C.VALUE.size])
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:ep)], :rax)

      asm.comment('set frame type')
      asm.mov([SP, C.VALUE.size * -1], C.VM_FRAME_MAGIC_METHOD | C.VM_ENV_FLAG_LOCAL)

      asm.comment('set specval')
      asm.mov([SP, C.VALUE.size * -2], C.VM_BLOCK_HANDLER_NONE)

      # Stub the return destination from the callee
      # TODO: set up return ctx correctly
      jit_return_stub = BlockStub.new(iseq: jit.iseq, pc: next_pc, ctx: ctx.dup)
      jit_return = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_block_stub(ctx, ocb_asm, jit_return_stub)
        @ocb.write(ocb_asm)
      end

      jit_return_stub.change_block = proc do |jump_asm, new_addr|
        jump_asm.comment('update cfp->jit_return')
        jump_asm.stub(jit_return_stub) do
          jump_asm.mov(:rax, new_addr)
          jump_asm.mov([CFP, C.rb_control_frame_t.offsetof(:jit_return)], :rax)
        end
      end
      jit_return_stub.change_block.call(asm, jit_return)

      callee_ctx = Context.new
      compile_block_stub(iseq, iseq.body.iseq_encoded.to_i, callee_ctx, asm)

      EndBlock
    end

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
      compile_block_stub(jit.iseq, jit.pc, ctx, asm, comment: 'defer_compilation: block stub')
    end

    def compile_block_stub(iseq, pc, ctx, asm, comment: 'block stub')
      block_stub = BlockStub.new(iseq:, pc:, ctx: ctx.dup)

      stub_hit = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_block_stub(ctx, ocb_asm, block_stub)
        @ocb.write(ocb_asm)
      end

      block_stub.change_block = proc do |jump_asm, new_addr|
        jump_asm.comment(comment)
        jump_asm.stub(block_stub) do
          jump_asm.jmp(new_addr)
        end
      end
      block_stub.change_block.call(asm, stub_hit)
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

    def def_iseq_ptr(cme_def)
      C.rb_iseq_check(cme_def.body.iseq.iseqptr)
    end
  end
end
