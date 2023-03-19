module RubyVM::RJIT
  class InsnCompiler
    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::RJIT::ExitCompiler]
    def initialize(cb, ocb, exit_compiler)
      @ocb = ocb
      @exit_compiler = exit_compiler

      @cfunc_codegen_table = {}
      register_cfunc_codegen_funcs
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    # @param insn `RubyVM::RJIT::Instruction`
    def compile(jit, ctx, asm, insn)
      asm.incr_counter(:rjit_insns_count)
      asm.comment("Insn: #{insn.name}")

      # 78/102
      case insn.name
      when :nop then nop(jit, ctx, asm)
      when :getlocal then getlocal(jit, ctx, asm)
      when :setlocal then setlocal(jit, ctx, asm)
      when :getblockparam then getblockparam(jit, ctx, asm)
      # setblockparam
      when :getblockparamproxy then getblockparamproxy(jit, ctx, asm)
      when :getspecial then getspecial(jit, ctx, asm)
      # setspecial
      when :getinstancevariable then getinstancevariable(jit, ctx, asm)
      when :setinstancevariable then setinstancevariable(jit, ctx, asm)
      when :getclassvariable then getclassvariable(jit, ctx, asm)
      # setclassvariable
      when :opt_getconstant_path then opt_getconstant_path(jit, ctx, asm)
      when :getconstant then getconstant(jit, ctx, asm)
      # setconstant
      # getglobal
      # setglobal
      when :putnil then putnil(jit, ctx, asm)
      when :putself then putself(jit, ctx, asm)
      when :putobject then putobject(jit, ctx, asm)
      when :putspecialobject then putspecialobject(jit, ctx, asm)
      when :putstring then putstring(jit, ctx, asm)
      when :concatstrings then concatstrings(jit, ctx, asm)
      when :anytostring then anytostring(jit, ctx, asm)
      # toregexp
      # intern
      when :newarray then newarray(jit, ctx, asm)
      # newarraykwsplat
      when :duparray then duparray(jit, ctx, asm)
      # duphash
      when :expandarray then expandarray(jit, ctx, asm)
      when :concatarray then concatarray(jit, ctx, asm)
      when :splatarray then splatarray(jit, ctx, asm)
      when :newhash then newhash(jit, ctx, asm)
      # newrange
      when :pop then pop(jit, ctx, asm)
      when :dup then dup(jit, ctx, asm)
      when :dupn then dupn(jit, ctx, asm)
      when :swap then swap(jit, ctx, asm)
      # opt_reverse
      when :topn then topn(jit, ctx, asm)
      when :setn then setn(jit, ctx, asm)
      when :adjuststack then adjuststack(jit, ctx, asm)
      when :defined then defined(jit, ctx, asm)
      when :definedivar then definedivar(jit, ctx, asm)
      # checkmatch
      when :checkkeyword then checkkeyword(jit, ctx, asm)
      # checktype
      # defineclass
      # definemethod
      # definesmethod
      when :send then send(jit, ctx, asm)
      when :opt_send_without_block then opt_send_without_block(jit, ctx, asm)
      when :objtostring then objtostring(jit, ctx, asm)
      when :opt_str_freeze then opt_str_freeze(jit, ctx, asm)
      when :opt_nil_p then opt_nil_p(jit, ctx, asm)
      # opt_str_uminus
      # opt_newarray_max
      when :opt_newarray_min then opt_newarray_min(jit, ctx, asm)
      when :invokesuper then invokesuper(jit, ctx, asm)
      when :invokeblock then invokeblock(jit, ctx, asm)
      when :leave then leave(jit, ctx, asm)
      when :throw then throw(jit, ctx, asm)
      when :jump then jump(jit, ctx, asm)
      when :branchif then branchif(jit, ctx, asm)
      when :branchunless then branchunless(jit, ctx, asm)
      when :branchnil then branchnil(jit, ctx, asm)
      # once
      when :opt_case_dispatch then opt_case_dispatch(jit, ctx, asm)
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
      when :opt_aset then opt_aset(jit, ctx, asm)
      # opt_aset_with
      # opt_aref_with
      when :opt_length then opt_length(jit, ctx, asm)
      when :opt_size then opt_size(jit, ctx, asm)
      when :opt_empty_p then opt_empty_p(jit, ctx, asm)
      when :opt_succ then opt_succ(jit, ctx, asm)
      when :opt_not then opt_not(jit, ctx, asm)
      when :opt_regexpmatch2 then opt_regexpmatch2(jit, ctx, asm)
      # invokebuiltin
      when :opt_invokebuiltin_delegate then opt_invokebuiltin_delegate(jit, ctx, asm)
      when :opt_invokebuiltin_delegate_leave then opt_invokebuiltin_delegate_leave(jit, ctx, asm)
      when :getlocal_WC_0 then getlocal_WC_0(jit, ctx, asm)
      when :getlocal_WC_1 then getlocal_WC_1(jit, ctx, asm)
      when :setlocal_WC_0 then setlocal_WC_0(jit, ctx, asm)
      when :setlocal_WC_1 then setlocal_WC_1(jit, ctx, asm)
      when :putobject_INT2FIX_0_ then putobject_INT2FIX_0_(jit, ctx, asm)
      when :putobject_INT2FIX_1_ then putobject_INT2FIX_1_(jit, ctx, asm)
      else CantCompile
      end
    end

    private

    #
    # Insns
    #

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def nop(jit, ctx, asm)
      # Do nothing
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getlocal(jit, ctx, asm)
      idx = jit.operand(0)
      level = jit.operand(1)
      jit_getlocal_generic(jit, ctx, asm, idx:, level:)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setlocal(jit, ctx, asm)
      idx = jit.operand(0)
      level = jit.operand(1)
      jit_setlocal_generic(jit, ctx, asm, idx:, level:)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getblockparam(jit, ctx, asm)
      # EP level
      level = jit.operand(1)

      # Save the PC and SP because we might allocate
      jit_prepare_routine_call(jit, ctx, asm)

      # A mirror of the interpreter code. Checking for the case
      # where it's pushing rb_block_param_proxy.
      side_exit = side_exit(jit, ctx)

      # Load environment pointer EP from CFP
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
      # FIXME: This is testing bits in the same place that the WB check is testing.
      # We should combine these at some point
      asm.test([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], C::VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)

      # If the frame flag has been modified, then the actual proc value is
      # already in the EP and we should just use the value.
      frame_flag_modified = asm.new_label('frame_flag_modified')
      asm.jnz(frame_flag_modified)

      # This instruction writes the block handler to the EP.  If we need to
      # fire a write barrier for the write, then exit (we'll let the
      # interpreter handle it so it can fire the write barrier).
      # flags & VM_ENV_FLAG_WB_REQUIRED
      asm.test([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], C::VM_ENV_FLAG_WB_REQUIRED)

      # if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
      asm.jnz(side_exit)

      # Convert the block handler in to a proc
      # call rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
      asm.mov(C_ARGS[0], EC)
      # The block handler for the current frame
      # note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
      asm.mov(C_ARGS[1], [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL])
      asm.call(C.rb_vm_bh_to_procval)

      # Load environment pointer EP from CFP (again)
      ep_reg = :rcx
      jit_get_ep(asm, level, reg: ep_reg)

      # Write the value at the environment pointer
      idx = jit.operand(0)
      offs = -(C.VALUE.size * idx)
      asm.mov([ep_reg, offs], C_RET);

      # Set the frame modified flag
      asm.mov(:rax, [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS]) # flag_check
      asm.or(:rax, C::VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) # modified_flag
      asm.mov([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], :rax)

      asm.write_label(frame_flag_modified)

      # Push the proc on the stack
      stack_ret = ctx.stack_push
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)
      asm.mov(:rax, [ep_reg, offs])
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # setblockparam

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getblockparamproxy(jit, ctx, asm)
      # To get block_handler
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      starting_context = ctx.dup # make a copy for use with jit_chain_guard

      # A mirror of the interpreter code. Checking for the case
      # where it's pushing rb_block_param_proxy.
      side_exit = side_exit(jit, ctx)

      # EP level
      level = jit.operand(1)

      # Peek at the block handler so we can check whether it's nil
      comptime_handler = jit.peek_at_block_handler(level)

      # When a block handler is present, it should always be a GC-guarded
      # pointer (VM_BH_ISEQ_BLOCK_P)
      if comptime_handler != 0 && comptime_handler & 0x3 != 0x1
        asm.incr_counter(:getblockpp_not_gc_guarded)
        return CantCompile
      end

      # Load environment pointer EP from CFP
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
      asm.test([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], C::VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)
      asm.jnz(counted_exit(side_exit, :getblockpp_block_param_modified))

      # Load the block handler for the current frame
      # note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
      block_handler = :rax
      asm.mov(block_handler, [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL])

      # Specialize compilation for the case where no block handler is present
      if comptime_handler == 0
        # Bail if there is a block handler
        asm.cmp(block_handler, 0)

        jit_chain_guard(:jnz, jit, starting_context, asm, counted_exit(side_exit, :getblockpp_block_handler_none))

        putobject(jit, ctx, asm, val: Qnil)
      else
        # Block handler is a tagged pointer. Look at the tag. 0x03 is from VM_BH_ISEQ_BLOCK_P().
        asm.and(block_handler, 0x3)

        # Bail unless VM_BH_ISEQ_BLOCK_P(bh). This also checks for null.
        asm.cmp(block_handler, 0x1)

        jit_chain_guard(:jnz, jit, starting_context, asm, counted_exit(side_exit, :getblockpp_not_iseq_block))

        # Push rb_block_param_proxy. It's a root, so no need to use jit_mov_gc_ptr.
        top = ctx.stack_push
        asm.mov(:rax, C.rb_block_param_proxy)
        asm.mov(top, :rax)
      end

      jump_to_next_insn(jit, ctx, asm)

      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getspecial(jit, ctx, asm)
      # This takes two arguments, key and type
      # key is only used when type == 0
      # A non-zero type determines which type of backref to fetch
      #rb_num_t key = jit.jit_get_arg(0);
      rtype = jit.operand(1)

      if rtype == 0
        # not yet implemented
        return CantCompile;
      elsif rtype & 0x01 != 0
        # Fetch a "special" backref based on a char encoded by shifting by 1

        # Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, asm)

        # call rb_backref_get()
        asm.comment('rb_backref_get')
        asm.call(C.rb_backref_get)

        asm.mov(C_ARGS[0], C_RET) # backref
        case [rtype >> 1].pack('c')
        in ?&
          asm.comment("rb_reg_last_match")
          asm.call(C.rb_reg_last_match)
        in ?`
          asm.comment("rb_reg_match_pre")
          asm.call(C.rb_reg_match_pre)
        in ?'
          asm.comment("rb_reg_match_post")
          asm.call(C.rb_reg_match_post)
        in ?+
          asm.comment("rb_reg_match_last")
          asm.call(C.rb_reg_match_last)
        end

        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)

        KeepCompiling
      else
        # Fetch the N-th match from the last backref based on type shifted by 1

        # Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, asm)

        # call rb_backref_get()
        asm.comment('rb_backref_get')
        asm.call(C.rb_backref_get)

        # rb_reg_nth_match((int)(type >> 1), backref);
        asm.comment('rb_reg_nth_match')
        asm.mov(C_ARGS[0], rtype >> 1)
        asm.mov(C_ARGS[1], C_RET) # backref
        asm.call(C.rb_reg_nth_match)

        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)

        KeepCompiling
      end
    end

    # setspecial

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setinstancevariable(jit, ctx, asm)
      starting_context = ctx.dup # make a copy for use with jit_chain_guard

      # Defer compilation so we can specialize on a runtime `self`
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      ivar_name = jit.operand(0)
      comptime_receiver = jit.peek_at_self

      # If the comptime receiver is frozen, writing an IV will raise an exception
      # and we don't want to JIT code to deal with that situation.
      if C.rb_obj_frozen_p(comptime_receiver)
        asm.incr_counter(:setivar_frozen)
        return CantCompile
      end

      # Check if the comptime receiver is a T_OBJECT
      receiver_t_object = C::BUILTIN_TYPE(comptime_receiver) == C::T_OBJECT

      # If the receiver isn't a T_OBJECT, or uses a custom allocator,
      # then just write out the IV write as a function call.
      # too-complex shapes can't use index access, so we use rb_ivar_get for them too.
      if !receiver_t_object || shape_too_complex?(comptime_receiver) || ctx.chain_depth >= 10
        asm.comment('call rb_vm_setinstancevariable')

        ic = jit.operand(1)

        # The function could raise exceptions.
        # Note that this modifies REG_SP, which is why we do it first
        jit_prepare_routine_call(jit, ctx, asm)

        # Get the operands from the stack
        val_opnd = ctx.stack_pop(1)

        # Call rb_vm_setinstancevariable(iseq, obj, id, val, ic);
        asm.mov(:rdi, jit.iseq.to_i)
        asm.mov(:rsi, [CFP, C.rb_control_frame_t.offsetof(:self)])
        asm.mov(:rdx, ivar_name)
        asm.mov(:rcx, val_opnd)
        asm.mov(:r8, ic)
        asm.call(C.rb_vm_setinstancevariable)
      else
        # Get the iv index
        shape_id = C.rb_shape_get_shape_id(comptime_receiver)
        ivar_index = C.rb_shape_get_iv_index(shape_id, ivar_name)

        # Get the receiver
        asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])

        # Generate a side exit
        side_exit = side_exit(jit, ctx)

        # Upgrade type
        guard_object_is_heap(asm, :rax, counted_exit(side_exit, :setivar_not_heap))

        asm.comment('guard shape')
        asm.cmp(DwordPtr[:rax, C.rb_shape_id_offset], shape_id)
        megamorphic_side_exit = counted_exit(side_exit, :setivar_megamorphic)
        jit_chain_guard(:jne, jit, starting_context, asm, megamorphic_side_exit)

        # If we don't have an instance variable index, then we need to
        # transition out of the current shape.
        if ivar_index.nil?
          shape = C.rb_shape_get_shape_by_id(shape_id)

          current_capacity = shape.capacity
          new_capacity = current_capacity * 2

          # If the object doesn't have the capacity to store the IV,
          # then we'll need to allocate it.
          needs_extension = shape.next_iv_index >= current_capacity

          # We can write to the object, but we need to transition the shape
          ivar_index = shape.next_iv_index

          capa_shape =
            if needs_extension
              # We need to add an extended table to the object
              # First, create an outgoing transition that increases the capacity
              C.rb_shape_transition_shape_capa(shape, new_capacity)
            else
              nil
            end

          dest_shape =
            if capa_shape
              C.rb_shape_get_next(capa_shape, comptime_receiver, ivar_name)
            else
              C.rb_shape_get_next(shape, comptime_receiver, ivar_name)
            end
          new_shape_id = C.rb_shape_id(dest_shape)

          if new_shape_id == C::OBJ_TOO_COMPLEX_SHAPE_ID
            asm.incr_counter(:setivar_too_complex)
            return CantCompile
          end

          if needs_extension
            # Generate the C call so that runtime code will increase
            # the capacity and set the buffer.
            asm.mov(C_ARGS[0], :rax)
            asm.mov(C_ARGS[1], current_capacity)
            asm.mov(C_ARGS[2], new_capacity)
            asm.call(C.rb_ensure_iv_list_size)

            # Load the receiver again after the function call
            asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
          end

          write_val = ctx.stack_pop(1)
          jit_write_iv(asm, comptime_receiver, :rax, :rcx, ivar_index, write_val, needs_extension)

          # Store the new shape
          asm.comment('write shape')
          asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)]) # reload after jit_write_iv
          asm.mov(DwordPtr[:rax, C.rb_shape_id_offset], new_shape_id)
        else
          # If the iv index already exists, then we don't need to
          # transition to a new shape.  The reason is because we find
          # the iv index by searching up the shape tree.  If we've
          # made the transition already, then there's no reason to
          # update the shape on the object.  Just set the IV.
          write_val = ctx.stack_pop(1)
          jit_write_iv(asm, comptime_receiver, :rax, :rcx, ivar_index, write_val, false)
        end

        skip_wb = asm.new_label('skip_wb')
        # If the value we're writing is an immediate, we don't need to WB
        asm.test(write_val, C::RUBY_IMMEDIATE_MASK)
        asm.jnz(skip_wb)

        # If the value we're writing is nil or false, we don't need to WB
        asm.cmp(write_val, Qnil)
        asm.jbe(skip_wb)

        asm.comment('write barrier')
        asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:self)]) # reload after jit_write_iv
        asm.mov(C_ARGS[1], write_val)
        asm.call(C.rb_gc_writebarrier)

        asm.write_label(skip_wb)
      end

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getclassvariable(jit, ctx, asm)
      # rb_vm_getclassvariable can raise exceptions.
      jit_prepare_routine_call(jit, ctx, asm)

      asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:iseq)])
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], jit.operand(0))
      asm.mov(C_ARGS[3], jit.operand(1))
      asm.call(C.rb_vm_getclassvariable)

      top = ctx.stack_push
      asm.mov(top, C_RET)

      KeepCompiling
    end

    # setclassvariable

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_getconstant_path(jit, ctx, asm)
      # Cut the block for invalidation
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      ic = C.iseq_inline_constant_cache.new(jit.operand(0))
      idlist = ic.segments

      # Make sure there is an exit for this block as the interpreter might want
      # to invalidate this block from rb_rjit_constant_ic_update().
      # For now, we always take an entry exit even if it was a side exit.
      Invariants.ensure_block_entry_exit(jit, cause: 'opt_getconstant_path')

      # See vm_ic_hit_p(). The same conditions are checked in yjit_constant_ic_update().
      ice = ic.entry
      if ice.nil?
        # In this case, leave a block that unconditionally side exits
        # for the interpreter to invalidate.
        asm.incr_counter(:optgetconst_not_cached)
        return CantCompile
      end

      if ice.ic_cref # with cref
        # Cache is keyed on a certain lexical scope. Use the interpreter's cache.
        side_exit = side_exit(jit, ctx)

        # Call function to verify the cache. It doesn't allocate or call methods.
        asm.mov(C_ARGS[0], ic.to_i)
        asm.mov(C_ARGS[1], [CFP, C.rb_control_frame_t.offsetof(:ep)])
        asm.call(C.rb_vm_ic_hit_p)

        # Check the result. SysV only specifies one byte for _Bool return values,
        # so it's important we only check one bit to ignore the higher bits in the register.
        asm.test(C_RET, 1)
        asm.jz(counted_exit(side_exit, :optgetconst_cache_miss))

        asm.mov(:rax, ic.to_i) # inline_cache
        asm.mov(:rax, [:rax, C.iseq_inline_constant_cache.offsetof(:entry)]) # ic_entry
        asm.mov(:rax, [:rax, C.iseq_inline_constant_cache_entry.offsetof(:value)]) # ic_entry_val

        # Push ic->entry->value
        stack_top = ctx.stack_push
        asm.mov(stack_top, :rax)
      else # without cref
        # TODO: implement this
        # Optimize for single ractor mode.
        # if !assume_single_ractor_mode(jit, ocb)
        #   return CantCompile
        # end

        # Invalidate output code on any constant writes associated with
        # constants referenced within the current block.
        Invariants.assume_stable_constant_names(jit, idlist)

        putobject(jit, ctx, asm, val: ice.value)
      end

      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getconstant(jit, ctx, asm)
      id = jit.operand(0)

      # vm_get_ev_const can raise exceptions.
      jit_prepare_routine_call(jit, ctx, asm)

      allow_nil_opnd = ctx.stack_pop(1)
      klass_opnd = ctx.stack_pop(1)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], klass_opnd)
      asm.mov(C_ARGS[2], id)
      asm.mov(C_ARGS[3], allow_nil_opnd)
      asm.call(C.rb_vm_get_ev_const)

      top = ctx.stack_push
      asm.mov(top, C_RET)

      KeepCompiling
    end

    # setconstant
    # getglobal
    # setglobal

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putnil(jit, ctx, asm)
      putobject(jit, ctx, asm, val: Qnil)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putself(jit, ctx, asm)
      stack_top = ctx.stack_push
      asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putspecialobject(jit, ctx, asm)
      object_type = jit.operand(0)
      if object_type == C::VM_SPECIAL_OBJECT_VMCORE
        stack_top = ctx.stack_push
        asm.mov(:rax, C.rb_mRubyVMFrozenCore)
        asm.mov(stack_top, :rax)
        KeepCompiling
      else
        # TODO: implement for VM_SPECIAL_OBJECT_CBASE and
        # VM_SPECIAL_OBJECT_CONST_BASE
        CantCompile
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putstring(jit, ctx, asm)
      put_val = jit.operand(0, ruby: true)

      # Save the PC and SP because the callee will allocate
      jit_prepare_routine_call(jit, ctx, asm)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], to_value(put_val))
      asm.call(C.rb_ec_str_resurrect)

      stack_top = ctx.stack_push
      asm.mov(stack_top, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def concatstrings(jit, ctx, asm)
      n = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      asm.lea(:rax, ctx.sp_opnd(-C.VALUE.size * n))

      # call rb_str_concat_literals(size_t n, const VALUE *strings);
      asm.mov(C_ARGS[0], n)
      asm.mov(C_ARGS[1], :rax)
      asm.call(C.rb_str_concat_literals)

      ctx.stack_pop(n)
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def anytostring(jit, ctx, asm)
      # Save the PC and SP since we might call #to_s
      jit_prepare_routine_call(jit, ctx, asm)

      str = ctx.stack_pop(1)
      val = ctx.stack_pop(1)

      asm.mov(C_ARGS[0], str)
      asm.mov(C_ARGS[1], val)
      asm.call(C.rb_obj_as_string_result)

      # Push the return value
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # toregexp
    # intern

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def newarray(jit, ctx, asm)
      n = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      # If n is 0, then elts is never going to be read, so we can just pass null
      if n == 0
        values_ptr = 0
      else
        asm.comment('load pointer to array elts')
        offset_magnitude = C.VALUE.size * n
        values_opnd = ctx.sp_opnd(-(offset_magnitude))
        asm.lea(:rax, values_opnd)
        values_ptr = :rax
      end

      # call rb_ec_ary_new_from_values(struct rb_execution_context_struct *ec, long n, const VALUE *elts);
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], n)
      asm.mov(C_ARGS[2], values_ptr)
      asm.call(C.rb_ec_ary_new_from_values)

      ctx.stack_pop(n)
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # newarraykwsplat

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def duparray(jit, ctx, asm)
      ary = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      # call rb_ary_resurrect(VALUE ary);
      asm.comment('call rb_ary_resurrect')
      asm.mov(C_ARGS[0], ary)
      asm.call(C.rb_ary_resurrect)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # duphash

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def expandarray(jit, ctx, asm)
      # Both arguments are rb_num_t which is unsigned
      num = jit.operand(0)
      flag = jit.operand(1)

      # If this instruction has the splat flag, then bail out.
      if flag & 0x01 != 0
        asm.incr_counter(:expandarray_splat)
        return CantCompile
      end

      # If this instruction has the postarg flag, then bail out.
      if flag & 0x02 != 0
        asm.incr_counter(:expandarray_postarg)
        return CantCompile
      end

      side_exit = side_exit(jit, ctx)

      array_opnd = ctx.stack_pop(1)

      # num is the number of requested values. If there aren't enough in the
      # array then we're going to push on nils.
      # TODO: implement this

      # Move the array from the stack and check that it's an array.
      asm.mov(:rax, array_opnd)
      guard_object_is_heap(asm, :rax, counted_exit(side_exit, :expandarray_not_array))
      guard_object_is_array(asm, :rax, :rcx, counted_exit(side_exit, :expandarray_not_array))

      # If we don't actually want any values, then just return.
      if num == 0
        return KeepCompiling
      end

      jit_array_len(asm, :rax, :rcx)

      # Only handle the case where the number of values in the array is greater
      # than or equal to the number of values requested.
      asm.cmp(:rcx, num)
      asm.jl(counted_exit(side_exit, :expandarray_rhs_too_small))

      # Conditionally load the address of the heap array into REG1.
      # (struct RArray *)(obj)->as.heap.ptr
      #asm.mov(:rax, array_opnd)
      asm.mov(:rcx, [:rax, C.RBasic.offsetof(:flags)])
      asm.test(:rcx, C::RARRAY_EMBED_FLAG);
      asm.mov(:rcx, [:rax, C.RArray.offsetof(:as, :heap, :ptr)])

      # Load the address of the embedded array into REG1.
      # (struct RArray *)(obj)->as.ary
      asm.lea(:rax, [:rax, C.RArray.offsetof(:as, :ary)])

      asm.cmovnz(:rcx, :rax)

      # Loop backward through the array and push each element onto the stack.
      (num - 1).downto(0).each do |i|
        top = ctx.stack_push
        asm.mov(:rax, [:rcx, i * C.VALUE.size])
        asm.mov(top, :rax)
      end

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def concatarray(jit, ctx, asm)
      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      ary2st_opnd = ctx.stack_pop(1)
      ary1_opnd = ctx.stack_pop(1)

      # Call rb_vm_concat_array(ary1, ary2st)
      asm.mov(C_ARGS[0], ary1_opnd)
      asm.mov(C_ARGS[1], ary2st_opnd)
      asm.call(C.rb_vm_concat_array)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def splatarray(jit, ctx, asm)
      flag = jit.operand(0)

      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      ary_opnd = ctx.stack_pop(1)

      # Call rb_vm_splat_array(flag, ary)
      asm.mov(C_ARGS[0], flag)
      asm.mov(C_ARGS[1], ary_opnd)
      asm.call(C.rb_vm_splat_array)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def newhash(jit, ctx, asm)
      num = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      if num != 0
        # val = rb_hash_new_with_size(num / 2);
        asm.mov(C_ARGS[0], num / 2)
        asm.call(C.rb_hash_new_with_size)

        # Save the allocated hash as we want to push it after insertion
        asm.push(C_RET)
        asm.push(C_RET) # x86 alignment

        # Get a pointer to the values to insert into the hash
        asm.lea(:rcx, ctx.stack_opnd(num - 1))

        # rb_hash_bulk_insert(num, STACK_ADDR_FROM_TOP(num), val);
        asm.mov(C_ARGS[0], num)
        asm.mov(C_ARGS[1], :rcx)
        asm.mov(C_ARGS[2], C_RET)
        asm.call(C.rb_hash_bulk_insert)

        asm.pop(:rax)
        asm.pop(:rax)

        ctx.stack_pop(num)
        stack_ret = ctx.stack_push
        asm.mov(stack_ret, :rax)
      else
        # val = rb_hash_new();
        asm.call(C.rb_hash_new)
        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)
      end

      KeepCompiling
    end

    # newrange

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def pop(jit, ctx, asm)
      ctx.stack_pop
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def dup(jit, ctx, asm)
      val1 = ctx.stack_opnd(0)
      val2 = ctx.stack_push
      asm.mov(:rax, val1)
      asm.mov(val2, :rax)
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def dupn(jit, ctx, asm)
      n = jit.operand(0)

      # In practice, seems to be only used for n==2
      if n != 2
        return CantCompile
      end

      opnd1 = ctx.stack_opnd(1)
      opnd0 = ctx.stack_opnd(0)

      dst1 = ctx.stack_push
      asm.mov(:rax, opnd1)
      asm.mov(dst1, :rax)

      dst0 = ctx.stack_push
      asm.mov(:rax, opnd0)
      asm.mov(dst0, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def swap(jit, ctx, asm)
      stack0_mem = ctx.stack_opnd(0)
      stack1_mem = ctx.stack_opnd(1)

      asm.mov(:rax, stack0_mem)
      asm.mov(:rcx, stack1_mem)
      asm.mov(stack0_mem, :rcx)
      asm.mov(stack1_mem, :rax)

      KeepCompiling
    end

    # opt_reverse

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def topn(jit, ctx, asm)
      n = jit.operand(0)

      top_n_val = ctx.stack_opnd(n)
      loc0 = ctx.stack_push
      asm.mov(:rax, top_n_val)
      asm.mov(loc0, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setn(jit, ctx, asm)
      n = jit.operand(0)

      top_val = ctx.stack_pop(0)
      dst_opnd = ctx.stack_opnd(n)
      asm.mov(:rax, top_val)
      asm.mov(dst_opnd, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def adjuststack(jit, ctx, asm)
      n = jit.operand(0)
      ctx.stack_pop(n)
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def defined(jit, ctx, asm)
      op_type = jit.operand(0)
      obj = jit.operand(1, ruby: true)
      pushval = jit.operand(2, ruby: true)

      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      v_opnd = ctx.stack_pop(1)

      # Call vm_defined(ec, reg_cfp, op_type, obj, v)
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], op_type)
      asm.mov(C_ARGS[3], to_value(obj))
      asm.mov(C_ARGS[4], v_opnd)
      asm.call(C.rb_vm_defined)

      asm.test(C_RET, 255)
      asm.mov(:rax, Qnil)
      asm.mov(:rcx, to_value(pushval))
      asm.cmovnz(:rax, :rcx)

      # Push the return value onto the stack
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def definedivar(jit, ctx, asm)
      ivar_name = jit.operand(0)
      pushval = jit.operand(2)

      # Get the receiver
      asm.mov(:rcx, [CFP, C.rb_control_frame_t.offsetof(:self)])

      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm) # clobbers :rax

      # Call rb_ivar_defined(recv, ivar_name)
      asm.mov(C_ARGS[0], :rcx)
      asm.mov(C_ARGS[1], ivar_name)
      asm.call(C.rb_ivar_defined)

      # if (rb_ivar_defined(recv, ivar_name)) {
      #  val = pushval;
      # }
      asm.test(C_RET, 255)
      asm.mov(:rax, Qnil)
      asm.mov(:rcx, pushval)
      asm.cmovnz(:rax, :rcx)

      # Push the return value onto the stack
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # checkmatch

    def checkkeyword(jit, ctx, asm)
      # When a keyword is unspecified past index 32, a hash will be used
      # instead. This can only happen in iseqs taking more than 32 keywords.
      if jit.iseq.body.param.keyword.num >= 32
        return CantCompile
      end

      # The EP offset to the undefined bits local
      bits_offset = jit.operand(0)

      # The index of the keyword we want to check
      index = jit.operand(1, signed: true)

      # Load environment pointer EP
      ep_reg = :rax
      jit_get_ep(asm, 0, reg: ep_reg)

      # VALUE kw_bits = *(ep - bits)
      bits_opnd = [ep_reg, C.VALUE.size * -bits_offset]

      # unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
      # if ((b & (0x01 << idx))) {
      #
      # We can skip the FIX2ULONG conversion by shifting the bit we test
      bit_test = 0x01 << (index + 1)
      asm.test(bits_opnd, bit_test)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmovz(:rax, :rcx)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # checktype
    # defineclass
    # definemethod
    # definesmethod

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def send(jit, ctx, asm)
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      cd = C.rb_call_data.new(jit.operand(0))
      blockiseq = jit.operand(1)

      block_handler = jit_caller_setup_arg_block(jit, ctx, asm, cd.ci, blockiseq, false)
      if block_handler == CantCompile
        return CantCompile
      end

      # calling->ci
      mid = C.vm_ci_mid(cd.ci)
      argc = C.vm_ci_argc(cd.ci)
      flags = C.vm_ci_flag(cd.ci)

      # vm_sendish
      cme, comptime_recv_klass = jit_search_method(jit, ctx, asm, mid, argc, flags)
      if cme == CantCompile
        return CantCompile
      end
      jit_call_general(jit, ctx, asm, mid, argc, flags, cme, block_handler, comptime_recv_klass)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_send_without_block(jit, ctx, asm, cd: C.rb_call_data.new(jit.operand(0)))
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      # calling->ci
      mid = C.vm_ci_mid(cd.ci)
      argc = C.vm_ci_argc(cd.ci)
      flags = C.vm_ci_flag(cd.ci)

      # vm_sendish
      cme, comptime_recv_klass = jit_search_method(jit, ctx, asm, mid, argc, flags)
      if cme == CantCompile
        return CantCompile
      end
      jit_call_general(jit, ctx, asm, mid, argc, flags, cme, C::VM_BLOCK_HANDLER_NONE, comptime_recv_klass)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def objtostring(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      recv = ctx.stack_opnd(0)
      comptime_recv = jit.peek_at_stack(0)

      if C::RB_TYPE_P(comptime_recv, C::RUBY_T_STRING)
        side_exit = side_exit(jit, ctx)

        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv, comptime_recv, side_exit)
        # No work needed. The string value is already on the top of the stack.
        KeepCompiling
      else
        cd = C.rb_call_data.new(jit.operand(0))
        opt_send_without_block(jit, ctx, asm, cd:)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_str_freeze(jit, ctx, asm)
      unless Invariants.assume_bop_not_redefined(jit, C::STRING_REDEFINED_OP_FLAG, C::BOP_FREEZE)
        return CantCompile;
      end

      str = jit.operand(0, ruby: true)

      # Push the return value onto the stack
      stack_ret = ctx.stack_push
      asm.mov(:rax, to_value(str))
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_nil_p(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # opt_str_uminus
    # opt_newarray_max

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_newarray_min(jit, ctx, asm)
      num = jit.operand(0)

      # Save the PC and SP because we may allocate
      jit_prepare_routine_call(jit, ctx, asm)

      offset_magnitude = C.VALUE.size * num
      values_opnd = ctx.sp_opnd(-offset_magnitude)
      asm.lea(:rax, values_opnd)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], num)
      asm.mov(C_ARGS[2], :rax)
      asm.call(C.rb_vm_opt_newarray_min)

      ctx.stack_pop(num)
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def invokesuper(jit, ctx, asm)
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      cd = C.rb_call_data.new(jit.operand(0))
      blockiseq = jit.operand(1)

      block_handler = jit_caller_setup_arg_block(jit, ctx, asm, cd.ci, blockiseq, true)
      if block_handler == CantCompile
        return CantCompile
      end

      # calling->ci
      mid = C.vm_ci_mid(cd.ci)
      argc = C.vm_ci_argc(cd.ci)
      flags = C.vm_ci_flag(cd.ci)

      # vm_sendish
      cme = jit_search_super_method(jit, ctx, asm, mid, argc, flags)
      if cme == CantCompile
        return CantCompile
      end
      jit_call_general(jit, ctx, asm, mid, argc, flags, cme, block_handler, nil)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def invokeblock(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      # Get call info
      cd = C.rb_call_data.new(jit.operand(0))
      ci = cd.ci
      _argc = C.vm_ci_argc(ci)
      _flags = C.vm_ci_flag(ci)

      # Get block_handler
      cfp = jit.cfp
      lep = C.rb_vm_ep_local_ep(cfp.ep)
      comptime_handler = lep[C::VM_ENV_DATA_INDEX_SPECVAL]

      # Handle each block_handler type
      if comptime_handler == C::VM_BLOCK_HANDLER_NONE # no block given
        asm.incr_counter(:invokeblock_none)
        CantCompile
      elsif comptime_handler & 0x3 == 0x1 # VM_BH_ISEQ_BLOCK_P
        asm.incr_counter(:invokeblock_iseq)
        CantCompile
      elsif comptime_handler & 0x3 == 0x3 # VM_BH_IFUNC_P
        asm.incr_counter(:invokeblock_ifunc)
        CantCompile
      elsif symbol?(comptime_handler)
        asm.incr_counter(:invokeblock_symbol)
        CantCompile
      else # Proc
        asm.incr_counter(:invokeblock_proc)
        CantCompile
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def throw(jit, ctx, asm)
      throw_state = jit.operand(0)
      asm.mov(:rcx, ctx.stack_pop(1)) # throwobj

      # THROW_DATA_NEW allocates. Save SP for GC and PC for allocation tracing as
      # well as handling the catch table. However, not using jit_prepare_routine_call
      # since we don't need a patch point for this implementation.
      jit_save_pc(jit, asm) # clobbers rax
      jit_save_sp(ctx, asm)

      # rb_vm_throw verifies it's a valid throw, sets ec->tag->state, and returns throw
      # data, which is throwobj or a vm_throw_data wrapping it. When ec->tag->state is
      # set, JIT code callers will handle the throw with vm_exec_handle_exception.
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], throw_state)
      # asm.mov(C_ARGS[3], :rcx) # same reg
      asm.call(C.rb_vm_throw)

      asm.comment('exit from throw')
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      # return C_RET as C_RET
      asm.ret
      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jump(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      pc = jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)
      jit_direct_jump(jit.iseq, pc, ctx, asm)
      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def branchnil(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      # TODO: skip check for known truthy

      val = ctx.stack_pop
      asm.cmp(val, Qnil)

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

      # Jump to target0 on je
      branch_stub.compile = proc do |branch_asm|
        branch_asm.comment("branchnil #{branch_stub.shape}")
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.je(branch_stub.target0.address)
            branch_asm.jmp(branch_stub.target1.address)
          in Next0
            branch_asm.jne(branch_stub.target1.address)
          in Next1
            branch_asm.je(branch_stub.target0.address)
          end
        end
      end
      branch_stub.compile.call(asm)

      EndBlock
    end

    # once

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_case_dispatch(jit, ctx, asm)
      # Just go to === branches for now
      ctx.stack_pop
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_PLUS)
          return CantCompile
        end

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test(recv_opnd, C::RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test(obj_opnd, C::RUBY_FIXNUM_FLAG)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_MINUS)
          return CantCompile
        end

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test(recv_opnd, C::RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test(obj_opnd, C::RUBY_FIXNUM_FLAG)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_mult(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_div(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_mod(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        # Create a side-exit to fall back to the interpreter
        # Note: we generate the side-exit before popping operands from the stack
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_MOD)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_eq(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if jit_equality_specialized(jit, ctx, asm, true)
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_neq(jit, ctx, asm)
      # opt_neq is passed two rb_call_data as arguments:
      # first for ==, second for !=
      neq_cd = C.rb_call_data.new(jit.operand(1))
      opt_send_without_block(jit, ctx, asm, cd: neq_cd)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_lt(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovl, bop: C::BOP_LT)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_le(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovle, bop: C::BOP_LE)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_gt(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovg, bop: C::BOP_GT)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_ge(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovge, bop: C::BOP_GE)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_ltlt(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_and(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        # Create a side-exit to fall back to the interpreter
        # Note: we generate the side-exit before popping operands from the stack
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_AND)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_or(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        # Create a side-exit to fall back to the interpreter
        # Note: we generate the side-exit before popping operands from the stack
        side_exit = side_exit(jit, ctx)

        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_OR)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

      if C.rb_class_of(comptime_recv) == Array && fixnum?(comptime_obj)
        unless Invariants.assume_bop_not_redefined(jit, C::ARRAY_REDEFINED_OP_FLAG, C::BOP_AREF)
          return CantCompile
        end

        idx_opnd = ctx.stack_opnd(0)
        recv_opnd = ctx.stack_opnd(1)

        not_array_exit = counted_exit(side_exit, :optaref_recv_not_array)
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv_opnd, comptime_recv, not_array_exit)

        # Bail if idx is not a FIXNUM
        asm.mov(:rax, idx_opnd)
        asm.test(:rax, C::RUBY_FIXNUM_FLAG)
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
      elsif C.rb_class_of(comptime_recv) == Hash
        unless Invariants.assume_bop_not_redefined(jit, C::HASH_REDEFINED_OP_FLAG, C::BOP_AREF)
          return CantCompile
        end

        recv_opnd = ctx.stack_opnd(1)

        # Guard that the receiver is a Hash
        not_hash_exit = counted_exit(side_exit, :optaref_recv_not_hash)
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv_opnd, comptime_recv, not_hash_exit)

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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_aset(jit, ctx, asm)
      # Defer compilation so we can specialize on a runtime `self`
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(2)
      comptime_key = jit.peek_at_stack(1)

      # Get the operands from the stack
      recv = ctx.stack_opnd(2)
      key = ctx.stack_opnd(1)
      _val = ctx.stack_opnd(0)

      if C.rb_class_of(comptime_recv) == Array && fixnum?(comptime_key)
        side_exit = side_exit(jit, ctx)

        # Guard receiver is an Array
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv, comptime_recv, side_exit)

        # Guard key is a fixnum
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_key), key, comptime_key, side_exit)

        # We might allocate or raise
        jit_prepare_routine_call(jit, ctx, asm)

        asm.comment('call rb_ary_store')
        recv = ctx.stack_opnd(2)
        key = ctx.stack_opnd(1)
        val = ctx.stack_opnd(0)
        asm.mov(:rax, key)
        asm.sar(:rax, 1) # FIX2LONG(key)
        asm.mov(C_ARGS[0], recv)
        asm.mov(C_ARGS[1], :rax)
        asm.mov(C_ARGS[2], val)
        asm.call(C.rb_ary_store)

        # rb_ary_store returns void
        # stored value should still be on stack
        val = ctx.stack_opnd(0)

        # Push the return value onto the stack
        ctx.stack_pop(3)
        stack_ret = ctx.stack_push
        asm.mov(:rax, val)
        asm.mov(stack_ret, :rax)

        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      elsif C.rb_class_of(comptime_recv) == Hash
        side_exit = side_exit(jit, ctx)

        # Guard receiver is a Hash
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv, comptime_recv, side_exit)

        # We might allocate or raise
        jit_prepare_routine_call(jit, ctx, asm)

        # Call rb_hash_aset
        recv = ctx.stack_opnd(2)
        key = ctx.stack_opnd(1)
        val = ctx.stack_opnd(0)
        asm.mov(C_ARGS[0], recv)
        asm.mov(C_ARGS[1], key)
        asm.mov(C_ARGS[2], val)
        asm.call(C.rb_hash_aset)

        # Push the return value onto the stack
        ctx.stack_pop(3)
        stack_ret = ctx.stack_push
        asm.mov(stack_ret, C_RET)

        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # opt_aset_with
    # opt_aref_with

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_length(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_size(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_empty_p(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_succ(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_not(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_regexpmatch2(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # invokebuiltin

    def opt_invokebuiltin_delegate(jit, ctx, asm)
      bf = C.rb_builtin_function.new(jit.operand(0))
      bf_argc = bf.argc
      start_index = jit.operand(1)

      # ec, self, and arguments
      if bf_argc + 2 > C_ARGS.size
        return CantCompile
      end

      # If the calls don't allocate, do they need up to date PC, SP?
      jit_prepare_routine_call(jit, ctx, asm)

      # Call the builtin func (ec, recv, arg1, arg2, ...)
      asm.comment('call builtin func')
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], [CFP, C.rb_control_frame_t.offsetof(:self)])

      # Copy arguments from locals
      if bf_argc > 0
        # Load environment pointer EP from CFP
        asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:ep)])

        bf_argc.times do |i|
          table_size = jit.iseq.body.local_table_size
          offs = -table_size - C::VM_ENV_DATA_SIZE + 1 + start_index + i
          asm.mov(C_ARGS[2 + i], [:rax, offs * C.VALUE.size])
        end
      end
      asm.call(bf.func_ptr)

      # Push the return value
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_invokebuiltin_delegate_leave(jit, ctx, asm)
      opt_invokebuiltin_delegate(jit, ctx, asm)
      # opt_invokebuiltin_delegate is always followed by leave insn
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getlocal_WC_0(jit, ctx, asm)
      # Get operands
      idx = jit.operand(0)

      # Get EP
      asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:ep)])

      # Get a local variable
      asm.mov(:rax, [:rax, -idx * C.VALUE.size])

      # Push it to the stack
      stack_top = ctx.stack_push
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getlocal_WC_1(jit, ctx, asm)
      idx = jit.operand(0)
      jit_getlocal_generic(jit, ctx, asm, idx:, level: 1)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setlocal_WC_0(jit, ctx, asm)
      slot_idx = jit.operand(0)

      # Load environment pointer EP (level 0) from CFP
      ep_reg = :rax
      jit_get_ep(asm, 0, reg: ep_reg)

      # Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
      # only affect heap objects being written. If we know an immediate value is being written we
      # can skip this check.

      # flags & VM_ENV_FLAG_WB_REQUIRED
      flags_opnd = [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS]
      asm.test(flags_opnd, C::VM_ENV_FLAG_WB_REQUIRED)

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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setlocal_WC_1(jit, ctx, asm)
      idx = jit.operand(0)
      jit_setlocal_generic(jit, ctx, asm, idx:, level: 1)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putobject_INT2FIX_0_(jit, ctx, asm)
      putobject(jit, ctx, asm, val: C.to_value(0))
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putobject_INT2FIX_1_(jit, ctx, asm)
      putobject(jit, ctx, asm, val: C.to_value(1))
    end

    #
    # C func
    #

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_true(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('nil? == true');
      ctx.stack_pop(1)
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, Qtrue)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_false(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('nil? == false');
      ctx.stack_pop(1)
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, Qfalse)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_obj_not(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('rb_obj_not')

      recv = ctx.stack_pop
      # This `test` sets ZF only for Qnil and Qfalse, which let cmovz set.
      asm.test(recv, ~Qnil)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmovz(:rax, :rcx)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_obj_equal(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      asm.comment('equal?')
      obj1 = ctx.stack_pop(1)
      obj2 = ctx.stack_pop(1)

      asm.mov(:rax, obj1)
      asm.mov(:rcx, obj2)
      asm.cmp(:rax, :rcx)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmove(:rax, :rcx)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_obj_not_equal(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      jit_equality_specialized(jit, ctx, asm, false)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_mod_eqq(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1

      asm.comment('Module#===')
      # By being here, we know that the receiver is a T_MODULE or a T_CLASS, because Module#=== can
      # only live on these objects. With that, we can call rb_obj_is_kind_of() without
      # jit_prepare_routine_call() or a control frame push because it can't raise, allocate, or call
      # Ruby methods with these inputs.
      # Note the difference in approach from Kernel#is_a? because we don't get a free guard for the
      # right hand side.
      lhs = ctx.stack_opnd(1) # the module
      rhs = ctx.stack_opnd(0)
      asm.mov(C_ARGS[0], rhs);
      asm.mov(C_ARGS[1], lhs);
      asm.call(C.rb_obj_is_kind_of)

      # Return the result
      ctx.stack_pop(2)
      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)

      return true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_int_equal(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      side_exit = side_exit(jit, ctx)
      guard_two_fixnums(jit, ctx, asm, side_exit)

      # Compare the arguments
      asm.comment('rb_int_equal')
      arg1 = ctx.stack_pop(1)
      arg0 = ctx.stack_pop(1)
      asm.mov(:rax, arg1)
      asm.cmp(arg0, :rax)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmove(:rax, :rcx)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_int_mul(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      side_exit = side_exit(jit, ctx)
      guard_two_fixnums(jit, ctx, asm, side_exit)

      asm.comment('rb_int_mul')
      y_opnd = ctx.stack_pop
      x_opnd = ctx.stack_pop
      asm.mov(C_ARGS[0], x_opnd)
      asm.mov(C_ARGS[1], y_opnd)
      asm.call(C.rb_fix_mul_fix)

      ret_opnd = ctx.stack_push
      asm.mov(ret_opnd, C_RET)
      true
    end

    def jit_rb_int_div(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      side_exit = side_exit(jit, ctx)
      guard_two_fixnums(jit, ctx, asm, side_exit)

      asm.comment('rb_int_div')
      y_opnd = ctx.stack_pop
      x_opnd = ctx.stack_pop
      asm.mov(:rax, y_opnd)
      asm.cmp(:rax, C.to_value(0))
      asm.je(side_exit)

      asm.mov(C_ARGS[0], x_opnd)
      asm.mov(C_ARGS[1], :rax)
      asm.call(C.rb_fix_div_fix)

      ret_opnd = ctx.stack_push
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_int_aref(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      side_exit = side_exit(jit, ctx)
      guard_two_fixnums(jit, ctx, asm, side_exit)

      asm.comment('rb_int_aref')
      y_opnd = ctx.stack_pop
      x_opnd = ctx.stack_pop

      asm.mov(C_ARGS[0], x_opnd)
      asm.mov(C_ARGS[1], y_opnd)
      asm.call(C.rb_fix_aref)

      ret_opnd = ctx.stack_push
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_to_s(jit, ctx, asm, argc, known_recv_class)
      return false if argc != 0
      if known_recv_class == String
        asm.comment('to_s on plain string')
        # The method returns the receiver, which is already on the stack.
        # No stack movement.
        return true
      end
      false
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_getbyte(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      asm.comment('rb_str_getbyte')

      index_opnd = ctx.stack_pop
      str_opnd = ctx.stack_pop
      asm.mov(C_ARGS[0], str_opnd)
      asm.mov(C_ARGS[1], index_opnd)
      asm.call(C.rb_str_getbyte)

      ret_opnd = ctx.stack_push
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_ary_push(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      asm.comment('rb_ary_push')

      jit_prepare_routine_call(jit, ctx, asm)

      item_opnd = ctx.stack_pop
      ary_opnd = ctx.stack_pop
      asm.mov(C_ARGS[0], ary_opnd)
      asm.mov(C_ARGS[1], item_opnd)
      asm.call(C.rb_ary_push)

      ret_opnd = ctx.stack_push
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_thread_s_current(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('Thread.current')
      ctx.stack_pop(1)

      # ec->thread_ptr
      asm.mov(:rax, [EC, C.rb_execution_context_t.offsetof(:thread_ptr)])

      # thread->self
      asm.mov(:rax, [:rax, C.rb_thread_struct.offsetof(:self)])

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, :rax)
      true
    end

    #
    # Helpers
    #

    def register_cfunc_codegen_funcs
      # Specialization for C methods. See register_cfunc_method for details.
      register_cfunc_method(BasicObject, :!, :jit_rb_obj_not)

      register_cfunc_method(NilClass, :nil?, :jit_rb_true)
      register_cfunc_method(Kernel, :nil?, :jit_rb_false)
      #register_cfunc_method(Kernel, :is_a?, :jit_rb_kernel_is_a)
      #register_cfunc_method(Kernel, :kind_of?, :jit_rb_kernel_is_a)
      #register_cfunc_method(Kernel, :instance_of?, :jit_rb_kernel_instance_of)

      register_cfunc_method(BasicObject, :==, :jit_rb_obj_equal)
      register_cfunc_method(BasicObject, :equal?, :jit_rb_obj_equal)
      register_cfunc_method(BasicObject, :!=, :jit_rb_obj_not_equal)
      register_cfunc_method(Kernel, :eql?, :jit_rb_obj_equal)
      register_cfunc_method(Module, :==, :jit_rb_obj_equal)
      register_cfunc_method(Module, :===, :jit_rb_mod_eqq)
      register_cfunc_method(Symbol, :==, :jit_rb_obj_equal)
      register_cfunc_method(Symbol, :===, :jit_rb_obj_equal)
      register_cfunc_method(Integer, :==, :jit_rb_int_equal)
      register_cfunc_method(Integer, :===, :jit_rb_int_equal)

      # rb_str_to_s() methods in string.c
      #register_cfunc_method(String, :empty?, :jit_rb_str_empty_p)
      register_cfunc_method(String, :to_s, :jit_rb_str_to_s)
      register_cfunc_method(String, :to_str, :jit_rb_str_to_s)
      #register_cfunc_method(String, :bytesize, :jit_rb_str_bytesize)
      #register_cfunc_method(String, :<<, :jit_rb_str_concat)
      #register_cfunc_method(String, :+@, :jit_rb_str_uplus)

      # rb_ary_empty_p() method in array.c
      #register_cfunc_method(Array, :empty?, :jit_rb_ary_empty_p)

      #register_cfunc_method(Kernel, :respond_to?, :jit_obj_respond_to)
      #register_cfunc_method(Kernel, :block_given?, :jit_rb_f_block_given_p)

      # Thread.current
      register_cfunc_method(C.rb_singleton_class(Thread), :current, :jit_thread_s_current)

      #---
      register_cfunc_method(Array, :<<, :jit_rb_ary_push)
      register_cfunc_method(Integer, :*, :jit_rb_int_mul)
      register_cfunc_method(Integer, :/, :jit_rb_int_div)
      register_cfunc_method(Integer, :[], :jit_rb_int_aref)
      register_cfunc_method(String, :getbyte, :jit_rb_str_getbyte)
    end

    def register_cfunc_method(klass, mid_sym, func)
      mid = C.rb_intern(mid_sym.to_s)
      me = C.rb_method_entry_at(klass, mid)

      assert_equal(false, me.nil?)

      # Only cfuncs are supported
      method_serial = me.def.method_serial

      @cfunc_codegen_table[method_serial] = method(func)
    end

    def lookup_cfunc_codegen(cme_def)
      @cfunc_codegen_table[cme_def.method_serial]
    end

    def jit_getlocal_generic(jit, ctx, asm, idx:, level:)
      # Load environment pointer EP at level
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Get a local variable
      asm.mov(:rax, [ep_reg, -idx * C.VALUE.size])

      # Push it to the stack
      stack_top = ctx.stack_push
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    def jit_setlocal_generic(jit, ctx, asm, idx:, level:)
      # Load environment pointer EP at level
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
      # only affect heap objects being written. If we know an immediate value is being written we
      # can skip this check.

      # flags & VM_ENV_FLAG_WB_REQUIRED
      flags_opnd = [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS]
      asm.test(flags_opnd, C::VM_ENV_FLAG_WB_REQUIRED)

      # Create a side-exit to fall back to the interpreter
      side_exit = side_exit(jit, ctx)

      # if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
      asm.jnz(side_exit)

      # Pop the value to write from the stack
      stack_top = ctx.stack_pop(1)

      # Write the value at the environment pointer
      asm.mov(:rcx, stack_top)
      asm.mov([ep_reg, -(C.VALUE.size * idx)], :rcx)

      KeepCompiling
    end

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
      op = slot_idx - C::VM_ENV_DATA_SIZE
      local_table_size - op - 1
    end

    # @param asm [RubyVM::RJIT::Assembler]
    def guard_object_is_heap(asm, object_opnd, side_exit)
      asm.comment('guard object is heap')
      # Test that the object is not an immediate
      asm.test(object_opnd, C::RUBY_IMMEDIATE_MASK)
      asm.jnz(side_exit)

      # Test that the object is not false
      asm.cmp(object_opnd, Qfalse)
      asm.je(side_exit)
    end

    # @param asm [RubyVM::RJIT::Assembler]
    def guard_object_is_array(asm, object_reg, flags_reg, side_exit)
      asm.comment('guard object is array')
      # Pull out the type mask
      asm.mov(flags_reg, [object_reg, C.RBasic.offsetof(:flags)])
      asm.and(flags_reg, C::RUBY_T_MASK)

      # Compare the result with T_ARRAY
      asm.cmp(flags_reg, C::RUBY_T_ARRAY)
      asm.jne(side_exit)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_chain_guard(opcode, jit, ctx, asm, side_exit, limit: 20)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_guard_known_klass(jit, ctx, asm, known_klass, obj_opnd, comptime_obj, side_exit, limit: 10)
      # Only memory operand is supported for now
      assert_equal(true, obj_opnd.is_a?(Array))

      # Touching this as Ruby could crash for FrozenCore
      known_klass = C.to_value(known_klass)
      if known_klass == C.rb_cNilClass
        asm.comment('guard object is nil')
        asm.cmp(obj_opnd, Qnil)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == C.rb_cTrueClass
        asm.comment('guard object is true')
        asm.cmp(obj_opnd, Qtrue)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == C.rb_cFalseClass
        asm.comment('guard object is false')
        asm.cmp(obj_opnd, Qfalse)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == C.rb_cInteger && fixnum?(comptime_obj)
        asm.comment('guard object is fixnum')
        asm.test(obj_opnd, C::RUBY_FIXNUM_FLAG)
        jit_chain_guard(:jz, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == C.rb_cSymbol && static_symbol?(comptime_obj)
        # We will guard STATIC vs DYNAMIC as though they were separate classes
        # DYNAMIC symbols can be handled by the general else case below
        asm.comment('guard object is static symbol')
        assert_equal(8, C::RUBY_SPECIAL_SHIFT)
        asm.cmp(BytePtr[*obj_opnd], C::RUBY_SYMBOL_FLAG)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif known_klass == C.rb_cFloat && flonum?(comptime_obj)
        # We will guard flonum vs heap float as though they were separate classes
        asm.comment('guard object is flonum')
        asm.mov(:rax, obj_opnd)
        asm.and(:rax, C::RUBY_FLONUM_MASK)
        asm.cmp(:rax, C::RUBY_FLONUM_FLAG)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif C.FL_TEST(known_klass, C::RUBY_FL_SINGLETON) && comptime_obj == C.rb_class_attached_object(known_klass)
        asm.comment('guard known object with singleton class')
        asm.mov(:rax, to_value(comptime_obj))
        asm.cmp(obj_opnd, :rax)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      else
        # Load memory to a register
        asm.mov(:rax, obj_opnd)
        obj_opnd = :rax

        # Check that the receiver is a heap object
        # Note: if we get here, the class doesn't have immediate instances.
        asm.comment('guard not immediate')
        asm.test(obj_opnd, C::RUBY_IMMEDIATE_MASK)
        jit_chain_guard(:jnz, jit, ctx, asm, side_exit, limit:)
        asm.cmp(obj_opnd, Qfalse)
        jit_chain_guard(:je, jit, ctx, asm, side_exit, limit:)

        # Bail if receiver class is different from known_klass
        klass_opnd = [obj_opnd, C.RBasic.offsetof(:klass)]
        asm.comment("guard known class #{known_klass}")
        asm.mov(:rcx, known_klass)
        asm.cmp(klass_opnd, :rcx)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    def two_fixnums_on_stack?(jit)
      comptime_recv = jit.peek_at_stack(1)
      comptime_arg = jit.peek_at_stack(0)
      return fixnum?(comptime_recv) && fixnum?(comptime_arg)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def guard_two_fixnums(jit, ctx, asm, side_exit)
      # Get stack operands without popping them
      arg1 = ctx.stack_opnd(0)
      arg0 = ctx.stack_opnd(1)

      asm.comment('guard arg0 fixnum')
      asm.test(arg0, C::RUBY_FIXNUM_FLAG)
      jit_chain_guard(:jz, jit, ctx, asm, side_exit)
      # TODO: upgrade type, and skip the check when possible

      asm.comment('guard arg1 fixnum')
      asm.test(arg1, C::RUBY_FIXNUM_FLAG)
      jit_chain_guard(:jz, jit, ctx, asm, side_exit)
      # TODO: upgrade type, and skip the check when possible
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
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

        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, bop)
          return CantCompile
        end

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.comment('guard recv is fixnum') # TODO: skip this with type information
        asm.test(recv_opnd, C::RUBY_FIXNUM_FLAG)
        asm.jz(side_exit)

        asm.comment('guard obj is fixnum') # TODO: skip this with type information
        asm.test(obj_opnd, C::RUBY_FIXNUM_FLAG)
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_equality_specialized(jit, ctx, asm, gen_eq)
      # Create a side-exit to fall back to the interpreter
      side_exit = side_exit(jit, ctx)

      a_opnd = ctx.stack_opnd(1)
      b_opnd = ctx.stack_opnd(0)

      comptime_a = jit.peek_at_stack(1)
      comptime_b = jit.peek_at_stack(0)

      if two_fixnums_on_stack?(jit)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_EQ)
          return false
        end

        guard_two_fixnums(jit, ctx, asm, side_exit)

        asm.comment('check fixnum equality')
        asm.mov(:rax, a_opnd)
        asm.mov(:rcx, b_opnd)
        asm.cmp(:rax, :rcx)
        asm.mov(:rax, gen_eq ? Qfalse : Qtrue)
        asm.mov(:rcx, gen_eq ? Qtrue  : Qfalse)
        asm.cmove(:rax, :rcx)

        # Push the output on the stack
        ctx.stack_pop(2)
        dst = ctx.stack_push
        asm.mov(dst, :rax)

        true
      elsif C.rb_class_of(comptime_a) == String && C.rb_class_of(comptime_b) == String
        unless Invariants.assume_bop_not_redefined(jit, C::STRING_REDEFINED_OP_FLAG, C::BOP_EQ)
          # if overridden, emit the generic version
          return false
        end

        # Guard that a is a String
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_a), a_opnd, comptime_a, side_exit)

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
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_b), b_opnd, comptime_b, side_exit)

        asm.comment('call rb_str_eql_internal')
        asm.mov(C_ARGS[0], a_opnd)
        asm.mov(C_ARGS[1], b_opnd)
        asm.call(gen_eq ? C.rb_str_eql_internal : C.rjit_str_neq_internal)

        # Push the output on the stack
        ctx.stack_pop(2)
        dst = ctx.stack_push
        asm.mov(dst, C_RET)
        asm.jmp(ret_label)

        asm.write_label(equal_label)
        asm.mov(dst, gen_eq ? Qtrue : Qfalse)

        asm.write_label(ret_label)

        true
      else
        false
      end
    end

    # NOTE: This clobbers :rax
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_prepare_routine_call(jit, ctx, asm)
      jit.record_boundary_patch_point = true
      jit_save_pc(jit, asm)
      jit_save_sp(ctx, asm)
    end

    # NOTE: This clobbers :rax
    # @param jit [RubyVM::RJIT::JITState]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_save_pc(jit, asm, comment: 'save PC to CFP')
      next_pc = jit.pc + jit.insn.len * C.VALUE.size # Use the next one for backtrace and side exits
      asm.comment(comment)
      asm.mov(:rax, next_pc)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax)
    end

    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_save_sp(ctx, asm)
      if ctx.sp_offset != 0
        asm.comment('save SP to CFP')
        asm.lea(SP, ctx.sp_opnd)
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)
        ctx.sp_offset = 0
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jump_to_next_insn(jit, ctx, asm)
      reset_depth = ctx.dup
      reset_depth.chain_depth = 0

      next_pc = jit.pc + jit.insn.len * C.VALUE.size

      # We are at the end of the current instruction. Record the boundary.
      if jit.record_boundary_patch_point
        exit_pos = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_side_exit(next_pc, ctx, ocb_asm)
          @ocb.write(ocb_asm)
        end
        Invariants.record_global_inval_patch(asm, exit_pos)
        jit.record_boundary_patch_point = false
      end

      jit_direct_jump(jit.iseq, next_pc, reset_depth, asm, comment: 'jump_to_next_insn')
    end

    # rb_vm_check_ints
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_check_ints(jit, ctx, asm)
      asm.comment('RUBY_VM_CHECK_INTS(ec)')
      asm.mov(:eax, DwordPtr[EC, C.rb_execution_context_t.offsetof(:interrupt_flag)])
      asm.test(:eax, :eax)
      asm.jnz(side_exit(jit, ctx))
    end

    # See get_lvar_level in compile.c
    def get_lvar_level(iseq)
      level = 0
      while iseq.to_i != iseq.body.local_iseq.to_i
        level += 1
        iseq = iseq.body.parent_iseq
      end
      return level
    end

    # GET_LEP
    # @param jit [RubyVM::RJIT::JITState]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_get_lep(jit, asm, reg:)
      level = get_lvar_level(jit.iseq)
      jit_get_ep(asm, level, reg:)
    end

    # vm_get_ep
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_get_ep(asm, level, reg:)
      asm.mov(reg, [CFP, C.rb_control_frame_t.offsetof(:ep)])
      level.times do
        # GET_PREV_EP: ep[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03
        asm.mov(reg, [reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL])
        asm.and(reg, ~0x03)
      end
    end

    # vm_getivar
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_getivar(jit, ctx, asm, comptime_obj, ivar_id, obj_opnd = nil)
      side_exit = side_exit(jit, ctx)
      starting_ctx = ctx.dup # copy for jit_chain_guard

      # Guard not special const
      if C::SPECIAL_CONST_P(comptime_obj)
        asm.incr_counter(:getivar_special_const)
        return CantCompile
      end

      case C::BUILTIN_TYPE(comptime_obj)
      when C::T_OBJECT
        # This is the only supported case for now (ROBJECT_IVPTR)
      else
        # General case. Call rb_ivar_get().
        # VALUE rb_ivar_get(VALUE obj, ID id)
        asm.comment('call rb_ivar_get()')
        asm.mov(C_ARGS[0], obj_opnd ? obj_opnd : [CFP, C.rb_control_frame_t.offsetof(:self)])
        asm.mov(C_ARGS[1], ivar_id)

        # The function could raise exceptions.
        jit_prepare_routine_call(jit, ctx, asm) # clobbers obj_opnd and :rax

        asm.call(C.rb_ivar_get)

        if obj_opnd # attr_reader
          ctx.stack_pop
        end

        # Push the ivar on the stack
        out_opnd = ctx.stack_push
        asm.mov(out_opnd, C_RET)

        # Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, asm)
        return EndBlock
      end

      asm.mov(:rax, obj_opnd ? obj_opnd : [CFP, C.rb_control_frame_t.offsetof(:self)])
      guard_object_is_heap(asm, :rax, counted_exit(side_exit, :getivar_not_heap))

      shape_id = C.rb_shape_get_shape_id(comptime_obj)
      if shape_id == C::OBJ_TOO_COMPLEX_SHAPE_ID
        asm.incr_counter(:getivar_too_complex)
        return CantCompile
      end

      asm.comment('guard shape')
      asm.cmp(DwordPtr[:rax, C.rb_shape_id_offset], shape_id)
      jit_chain_guard(:jne, jit, starting_ctx, asm, counted_exit(side_exit, :getivar_megamorphic))

      index = C.rb_shape_get_iv_index(shape_id, ivar_id)
      if index
        asm.comment('ROBJECT_IVPTR')
        if C::FL_TEST_RAW(comptime_obj, C::ROBJECT_EMBED)
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

    def jit_write_iv(asm, comptime_receiver, recv_reg, temp_reg, ivar_index, set_value, needs_extension)
      # Compile time self is embedded and the ivar index lands within the object
      embed_test_result = C::FL_TEST_RAW(comptime_receiver, C::ROBJECT_EMBED) && !needs_extension

      if embed_test_result
        # Find the IV offset
        offs = C.RObject.offsetof(:as, :ary) + ivar_index * C.VALUE.size

        # Write the IV
        asm.comment('write IV')
        asm.mov(temp_reg, set_value)
        asm.mov([recv_reg, offs], temp_reg)
      else
        # Compile time value is *not* embedded.

        # Get a pointer to the extended table
        asm.mov(recv_reg, [recv_reg, C.RObject.offsetof(:as, :heap, :ivptr)])

        # Write the ivar in to the extended table
        asm.comment("write IV");
        asm.mov(temp_reg, set_value)
        asm.mov([recv_reg, C.VALUE.size * ivar_index], temp_reg)
      end
    end

    # vm_caller_setup_arg_block
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_caller_setup_arg_block(jit, ctx, asm, ci, blockiseq, is_super)
      side_exit = side_exit(jit, ctx)
      if C.vm_ci_flag(ci) & C::VM_CALL_ARGS_BLOCKARG != 0
        # TODO: Skip cmp + jne using Context?
        block_code = jit.peek_at_stack(0)
        block_opnd = ctx.stack_opnd(0) # to be popped after eliminating side exit possibility
        if block_code.nil?
          asm.cmp(block_opnd, Qnil)
          jit_chain_guard(:jne, jit, ctx, asm, counted_exit(side_exit, :send_block_not_nil))
          return C::VM_BLOCK_HANDLER_NONE
        elsif C.to_value(block_code) == C.rb_block_param_proxy
          asm.mov(:rax, C.rb_block_param_proxy)
          asm.cmp(block_opnd, :rax)
          jit_chain_guard(:jne, jit, ctx, asm, counted_exit(side_exit, :send_block_not_proxy))
          return C.rb_block_param_proxy
        else
          asm.incr_counter(:send_blockarg_not_nil_or_proxy)
          return CantCompile
        end
      elsif blockiseq != 0
        return blockiseq
      else
        if is_super
          # GET_BLOCK_HANDLER();
          # Guard no block passed. Only handle that case for now.
          asm.comment('guard no block given')
          jit_get_lep(jit, asm, reg: :rax)
          asm.cmp([:rax, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL], C::VM_BLOCK_HANDLER_NONE)
          asm.jne(counted_exit(side_exit, :send_block_handler))
          return C::VM_BLOCK_HANDLER_NONE
        else
          # Not implemented yet. Is this even necessary?
          asm.incr_counter(:send_block_setup)
          return CantCompile
        end
      end
    end

    # vm_search_method
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_search_method(jit, ctx, asm, mid, argc, flags, send_shift: 0)
      assert_equal(true, jit.at_current_insn?)

      # Generate a side exit
      side_exit = side_exit(jit, ctx)

      # kw_splat is not supported yet
      if flags & C::VM_CALL_KW_SPLAT != 0
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end

      # Get a compile-time receiver and its class
      recv_idx = argc + (flags & C::VM_CALL_ARGS_BLOCKARG != 0 ? 1 : 0) # blockarg is not popped yet
      recv_idx += send_shift
      comptime_recv = jit.peek_at_stack(recv_idx)
      comptime_recv_klass = C.rb_class_of(comptime_recv)

      # Guard the receiver class (part of vm_search_method_fastpath)
      recv_opnd = ctx.stack_opnd(recv_idx)
      megamorphic_exit = counted_exit(side_exit, :send_klass_megamorphic)
      jit_guard_known_klass(jit, ctx, asm, comptime_recv_klass, recv_opnd, comptime_recv, megamorphic_exit)

      # Do method lookup (vm_cc_cme(cc) != NULL)
      cme = C.rb_callable_method_entry(comptime_recv_klass, mid)
      if cme.nil?
        asm.incr_counter(:send_missing_cme)
        return CantCompile # We don't support vm_call_method_name
      end

      # Invalidate on redefinition (part of vm_search_method_fastpath)
      Invariants.assume_method_lookup_stable(jit, cme)

      return cme, comptime_recv_klass
    end

    def jit_search_super_method(jit, ctx, asm, mid, argc, flags)
      assert_equal(true, jit.at_current_insn?)

      me = C.rb_vm_frame_method_entry(jit.cfp)
      if me.nil?
        return CantCompile
      end

      # FIXME: We should track and invalidate this block when this cme is invalidated
      current_defined_class = me.defined_class
      mid = me.def.original_id

      if me.to_i != C.rb_callable_method_entry(current_defined_class, me.called_id).to_i
        # Though we likely could generate this call, as we are only concerned
        # with the method entry remaining valid, assume_method_lookup_stable
        # below requires that the method lookup matches as well
        return CantCompile
      end

      # vm_search_normal_superclass
      rbasic_klass = C.to_ruby(C.RBasic.new(C.to_value(current_defined_class)).klass)
      if C::BUILTIN_TYPE(current_defined_class) == C::RUBY_T_ICLASS && C::BUILTIN_TYPE(rbasic_klass) == C::RUBY_T_MODULE && \
          C::FL_TEST_RAW(rbasic_klass, C::RMODULE_IS_REFINEMENT) != 0
        return CantCompile
      end
      comptime_superclass = C.rb_class_get_superclass(current_defined_class)

      # Don't JIT calls that aren't simple
      # Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.

      if flags & C::VM_CALL_KWARG != 0
        asm.incr_counter(:send_kwarg)
        return CantCompile
      end
      if flags & C::VM_CALL_KW_SPLAT != 0
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end

      # Ensure we haven't rebound this method onto an incompatible class.
      # In the interpreter we try to avoid making this check by performing some
      # cheaper calculations first, but since we specialize on the method entry
      # and so only have to do this once at compile time this is fine to always
      # check and side exit.
      comptime_recv = jit.peek_at_stack(argc)
      unless C.obj_is_kind_of(comptime_recv, current_defined_class)
        return CantCompile
      end

      # Do method lookup
      cme = C.rb_callable_method_entry(comptime_superclass, mid)

      if cme.nil?
        return CantCompile
      end

      # workaround -- TODO: Why does this happen?
      if me.to_i == cme.to_i
        asm.incr_counter(:invokesuper_same_me)
        return CantCompile
      end

      # Check that we'll be able to write this method dispatch before generating checks
      cme_def_type = cme.def.type
      if cme_def_type != C::VM_METHOD_TYPE_ISEQ && cme_def_type != C::VM_METHOD_TYPE_CFUNC
        # others unimplemented
        return CantCompile
      end

      # Guard that the receiver has the same class as the one from compile time
      side_exit = side_exit(jit, ctx)

      asm.comment('guard known me')
      jit_get_lep(jit, asm, reg: :rax)

      asm.mov(:rcx, me.to_i)
      asm.cmp([:rax, C.VALUE.size * C::VM_ENV_DATA_INDEX_ME_CREF], :rcx)
      asm.jne(counted_exit(side_exit, :invokesuper_me_changed))

      # We need to assume that both our current method entry and the super
      # method entry we invoke remain stable
      Invariants.assume_method_lookup_stable(jit, me)
      Invariants.assume_method_lookup_stable(jit, cme)

      return cme
    end

    # vm_call_general
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_general(jit, ctx, asm, mid, argc, flags, cme, block_handler, known_recv_class)
      jit_call_method(jit, ctx, asm, mid, argc, flags, cme, block_handler, known_recv_class)
    end

    # vm_call_method
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    # @param send_shift [Integer] The number of shifts needed for VM_CALL_OPT_SEND
    def jit_call_method(jit, ctx, asm, mid, argc, flags, cme, block_handler, known_recv_class, send_shift: 0)
      # The main check of vm_call_method before vm_call_method_each_type
      case C::METHOD_ENTRY_VISI(cme)
      in C::METHOD_VISI_PUBLIC
        # You can always call public methods
      in C::METHOD_VISI_PRIVATE
        # Allow only callsites without a receiver
        if flags & C::VM_CALL_FCALL == 0
          asm.incr_counter(:send_private)
          return CantCompile
        end
      in C::METHOD_VISI_PROTECTED
        # If the method call is an FCALL, it is always valid
        if flags & C::VM_CALL_FCALL == 0
          # otherwise we need an ancestry check to ensure the receiver is valid to be called as protected
          jit_protected_callee_ancestry_guard(asm, cme, side_exit(jit, ctx))
        end
      end

      # Get a compile-time receiver
      recv_idx = argc + (flags & C::VM_CALL_ARGS_BLOCKARG != 0 ? 1 : 0) # blockarg is not popped yet
      recv_idx += send_shift
      comptime_recv = jit.peek_at_stack(recv_idx)
      recv_opnd = ctx.stack_opnd(recv_idx)

      jit_call_method_each_type(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
    end

    # Generate ancestry guard for protected callee.
    # Calls to protected callees only go through when self.is_a?(klass_that_defines_the_callee).
    def jit_protected_callee_ancestry_guard(asm, cme, side_exit)
      # See vm_call_method().
      def_class = cme.defined_class
      # Note: PC isn't written to current control frame as rb_is_kind_of() shouldn't raise.
      # VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);

      asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov(C_ARGS[1], to_value(def_class))
      asm.call(C.rb_obj_is_kind_of)
      asm.test(C_RET, C_RET)
      asm.jz(counted_exit(side_exit, :send_protected_check_failed))
    end

    # vm_call_method_each_type
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_method_each_type(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
      case cme.def.type
      in C::VM_METHOD_TYPE_ISEQ
        iseq = def_iseq_ptr(cme.def)
        jit_call_iseq_setup(jit, ctx, asm, cme, flags, argc, iseq, block_handler, send_shift:)
      in C::VM_METHOD_TYPE_NOTIMPLEMENTED
        asm.incr_counter(:send_notimplemented)
        return CantCompile
      in C::VM_METHOD_TYPE_CFUNC
        jit_call_cfunc(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      in C::VM_METHOD_TYPE_ATTRSET
        asm.incr_counter(:send_attrset)
        return CantCompile
      in C::VM_METHOD_TYPE_IVAR
        jit_call_ivar(jit, ctx, asm, cme, flags, argc, comptime_recv, recv_opnd, send_shift:)
      in C::VM_METHOD_TYPE_MISSING
        asm.incr_counter(:send_missing)
        return CantCompile
      in C::VM_METHOD_TYPE_BMETHOD
        jit_call_bmethod(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
      in C::VM_METHOD_TYPE_ALIAS
        jit_call_alias(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
      in C::VM_METHOD_TYPE_OPTIMIZED
        jit_call_optimized(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      in C::VM_METHOD_TYPE_UNDEF
        asm.incr_counter(:send_undef)
        return CantCompile
      in C::VM_METHOD_TYPE_ZSUPER
        asm.incr_counter(:send_zsuper)
        return CantCompile
      in C::VM_METHOD_TYPE_REFINED
        asm.incr_counter(:send_refined)
        return CantCompile
      end
    end

    # vm_call_iseq_setup
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_iseq_setup(jit, ctx, asm, cme, flags, argc, iseq, block_handler, send_shift:, frame_type: nil, prev_ep: nil)
      opt_pc = jit_callee_setup_arg(jit, ctx, asm, flags, argc, iseq)
      if opt_pc == CantCompile
        return CantCompile
      end

      if flags & C::VM_CALL_TAILCALL != 0
        # We don't support vm_call_iseq_setup_tailcall
        asm.incr_counter(:send_tailcall)
        return CantCompile
      end
      jit_call_iseq_setup_normal(jit, ctx, asm, cme, flags, argc, iseq, block_handler, opt_pc, send_shift:, frame_type:, prev_ep:)
    end

    # vm_call_iseq_setup_normal (vm_call_iseq_setup_2 -> vm_call_iseq_setup_normal)
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_iseq_setup_normal(jit, ctx, asm, cme, flags, argc, iseq, block_handler, opt_pc, send_shift:, frame_type:, prev_ep:)
      # We will not have side exits from here. Adjust the stack.
      if flags & C::VM_CALL_OPT_SEND != 0
        jit_call_opt_send_shift_stack(ctx, asm, argc, send_shift:)
      end

      # Save caller SP and PC before pushing a callee frame for backtrace and side exits
      asm.comment('save SP to caller CFP')
      recv_idx = argc + (flags & C::VM_CALL_ARGS_BLOCKARG != 0 ? 1 : 0) # blockarg is not popped yet
      # Skip setting this to SP register. This cfp->sp will be copied to SP on leave insn.
      asm.lea(:rax, ctx.sp_opnd(C.VALUE.size * -(1 + recv_idx))) # Pop receiver and arguments to prepare for side exits
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], :rax)
      jit_save_pc(jit, asm, comment: 'save PC to caller CFP')

      frame_type ||= C::VM_FRAME_MAGIC_METHOD | C::VM_ENV_FLAG_LOCAL
      jit_push_frame(
        jit, ctx, asm, cme, flags, argc, frame_type, block_handler,
        iseq:       iseq,
        local_size: iseq.body.local_table_size - iseq.body.param.size,
        stack_max:  iseq.body.stack_max,
        prev_ep:,
      )

      # Jump to a stub for the callee ISEQ
      callee_ctx = Context.new
      pc = (iseq.body.iseq_encoded + opt_pc).to_i
      jit_direct_jump(iseq, pc, callee_ctx, asm)

      EndBlock
    end

    # vm_call_cfunc
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_cfunc(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if jit_caller_setup_arg(jit, ctx, asm, flags) == CantCompile
        return CantCompile
      end
      if jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags) == CantCompile
        return CantCompile
      end

      jit_call_cfunc_with_frame(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
    end

    # jit_call_cfunc_with_frame
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_cfunc_with_frame(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      cfunc = cme.def.body.cfunc

      if argc + 1 > 6
        asm.incr_counter(:send_cfunc_too_many_args)
        return CantCompile
      end

      frame_type = C::VM_FRAME_MAGIC_CFUNC | C::VM_FRAME_FLAG_CFRAME | C::VM_ENV_FLAG_LOCAL
      if flags & C::VM_CALL_KW_SPLAT != 0
        frame_type |= C::VM_FRAME_FLAG_CFRAME_KW
      end

      # EXEC_EVENT_HOOK: RUBY_EVENT_C_CALL and RUBY_EVENT_C_RETURN
      if C.rb_rjit_global_events & (C::RUBY_EVENT_C_CALL | C::RUBY_EVENT_C_RETURN) != 0
        asm.incr_counter(:send_c_tracing)
        return CantCompile
      end

      # rb_check_arity
      if cfunc.argc >= 0 && argc != cfunc.argc
        asm.incr_counter(:send_arity)
        return CantCompile
      end
      if cfunc.argc == -2
        asm.incr_counter(:send_cfunc_ruby_array_varg)
        return CantCompile
      end

      # Delegate to codegen for C methods if we have it.
      if flags & C::VM_CALL_KWARG == 0 && flags & C::VM_CALL_OPT_SEND == 0
        known_cfunc_codegen = lookup_cfunc_codegen(cme.def)
        if known_cfunc_codegen&.call(jit, ctx, asm, argc, known_recv_class)
          # cfunc codegen generated code. Terminate the block so
          # there isn't multiple calls in the same block.
          jump_to_next_insn(jit, ctx, asm)
          return EndBlock
        end
      end

      # We will not have side exits from here. Adjust the stack.
      if flags & C::VM_CALL_OPT_SEND != 0
        jit_call_opt_send_shift_stack(ctx, asm, argc, send_shift:)
      end

      # Check interrupts before SP motion to safely side-exit with the original SP.
      jit_check_ints(jit, ctx, asm)

      # Save caller SP and PC before pushing a callee frame for backtrace and side exits
      asm.comment('save SP to caller CFP')
      sp_index = -(1 + argc + (flags & C::VM_CALL_ARGS_BLOCKARG != 0 ? 1 : 0)) # Pop receiver and arguments for side exits. blockarg is not popped yet
      asm.lea(SP, ctx.sp_opnd(C.VALUE.size * sp_index))
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)
      ctx.sp_offset = -sp_index
      jit_save_pc(jit, asm, comment: 'save PC to caller CFP')

      # Push a callee frame. SP register and ctx are not modified inside this.
      jit_push_frame(jit, ctx, asm, cme, flags, argc, frame_type, block_handler)

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

      Invariants.record_global_inval_patch(asm, full_cfunc_return)

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

    # vm_call_ivar (+ part of vm_call_method_each_type)
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_ivar(jit, ctx, asm, cme, flags, argc, comptime_recv, recv_opnd, send_shift:)
      if flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_ivar_splat)
        return CantCompile
      end

      if argc != 0
        asm.incr_counter(:send_arity)
        return CantCompile
      end

      # We don't support jit_call_opt_send_shift_stack for this yet.
      if flags & C::VM_CALL_OPT_SEND != 0
        asm.incr_counter(:send_ivar_opt_send)
        return CantCompile
      end

      ivar_id = cme.def.body.attr.id

      # Not handling block_handler
      if flags & C::VM_CALL_ARGS_BLOCKARG != 0
        asm.incr_counter(:send_ivar_blockarg)
        return CantCompile
      end

      jit_getivar(jit, ctx, asm, comptime_recv, ivar_id, recv_opnd)
    end

    # vm_call_bmethod
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_bmethod(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
      proc_addr = cme.def.body.bmethod.proc

      proc_t = C.rb_yjit_get_proc_ptr(proc_addr)
      proc_block = proc_t.block

      if proc_block.type != C.block_type_iseq
        asm.incr_counter(:send_bmethod_not_iseq)
        return CantCompile
      end

      capture = proc_block.as.captured
      iseq = capture.code.iseq

      # TODO: implement this
      # Optimize for single ractor mode and avoid runtime check for
      # "defined with an un-shareable Proc in a different Ractor"
      # if !assume_single_ractor_mode(jit, ocb)
      #     return CantCompile;
      # end

      # Passing a block to a block needs logic different from passing
      # a block to a method and sometimes requires allocation. Bail for now.
      if block_handler != C::VM_BLOCK_HANDLER_NONE
        asm.incr_counter(:send_bmethod_blockarg)
        return CantCompile
      end

      frame_type = C::VM_FRAME_MAGIC_BLOCK | C::VM_FRAME_FLAG_BMETHOD | C::VM_FRAME_FLAG_LAMBDA
      prev_ep = capture.ep
      jit_call_iseq_setup(jit, ctx, asm, cme, flags, argc, iseq, block_handler, send_shift:, frame_type:, prev_ep:)
    end

    # vm_call_alias
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_alias(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
      cme = C.rb_aliased_callable_method_entry(cme)
      jit_call_method_each_type(jit, ctx, asm, argc, flags, cme, comptime_recv, recv_opnd, block_handler, known_recv_class, send_shift:)
    end

    # vm_call_optimized
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_optimized(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if flags & C::VM_CALL_ARGS_BLOCKARG != 0
        # Not working yet
        asm.incr_counter(:send_optimized_blockarg)
        return CantCompile
      end

      case cme.def.body.optimized.type
      in C::OPTIMIZED_METHOD_TYPE_SEND
        jit_call_opt_send(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      in C::OPTIMIZED_METHOD_TYPE_CALL
        jit_call_opt_call(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      in C::OPTIMIZED_METHOD_TYPE_BLOCK_CALL
        asm.incr_counter(:send_optimized_block_call)
        return CantCompile
      in C::OPTIMIZED_METHOD_TYPE_STRUCT_AREF
        jit_call_opt_struct_aref(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      in C::OPTIMIZED_METHOD_TYPE_STRUCT_ASET
        asm.incr_counter(:send_optimized_struct_aset)
        return CantCompile
      end
    end

    # vm_call_opt_send
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_send(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if jit_caller_setup_arg(jit, ctx, asm, flags) == CantCompile
        return CantCompile
      end

      if argc == 0
        asm.incr_counter(:send_optimized_send_no_args)
        return CantCompile
      end

      argc -= 1
      # We aren't handling `send(:send, ...)` yet. This might work, but not tested yet.
      if send_shift > 0
        asm.incr_counter(:send_optimized_send_send)
        return CantCompile
      end
      # Ideally, we want to shift the stack here, but it's not safe until you reach the point
      # where you never exit. `send_shift` signals to lazily shift the stack by this amount.
      send_shift += 1

      kw_splat = flags & C::VM_CALL_KW_SPLAT != 0
      jit_call_symbol(jit, ctx, asm, cme, C::VM_CALL_FCALL, argc, kw_splat, block_handler, known_recv_class, send_shift:)
    end

    # vm_call_opt_call
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_call(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if block_handler != C::VM_BLOCK_HANDLER_NONE
        asm.incr_counter(:send_optimized_call_block)
        return CantCompile
      end

      if flags & C::VM_CALL_KWARG != 0
        asm.incr_counter(:send_optimized_call_kwarg)
        return CantCompile
      end

      if flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_optimized_call_splat)
        return CantCompile
      end

      # TODO: implement this
      # Optimize for single ractor mode and avoid runtime check for
      # "defined with an un-shareable Proc in a different Ractor"
      # if !assume_single_ractor_mode(jit, ocb)
      #   return CantCompile
      # end

      # If this is a .send call we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        jit_call_opt_send_shift_stack(ctx, asm, argc, send_shift:)
      end

      # About to reset the SP, need to load this here
      recv_idx = argc # blockarg is not supported. send_shift is already handled.
      asm.mov(:rcx, ctx.stack_opnd(recv_idx)) # recv

      # Save the PC and SP because the callee can make Ruby calls
      jit_prepare_routine_call(jit, ctx, asm) # NOTE: clobbers rax

      asm.lea(:rax, ctx.sp_opnd(0)) # sp

      kw_splat = flags & C::VM_CALL_KW_SPLAT

      asm.mov(C_ARGS[0], :rcx)
      asm.mov(C_ARGS[1], EC)
      asm.mov(C_ARGS[2], argc)
      asm.lea(C_ARGS[3], [:rax, -argc * C.VALUE.size]) # stack_argument_pointer. NOTE: C_ARGS[3] is rcx
      asm.mov(C_ARGS[4], kw_splat)
      asm.mov(C_ARGS[5], C::VM_BLOCK_HANDLER_NONE)
      asm.call(C.rjit_optimized_call)

      ctx.stack_pop(argc + 1)

      stack_ret = ctx.stack_push
      asm.mov(stack_ret, C_RET)
      return KeepCompiling
    end

    # vm_call_opt_struct_aref
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_struct_aref(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if argc != 0
        asm.incr_counter(:send_optimized_struct_aref_error)
        return CantCompile
      end

      off = cme.def.body.optimized.index

      recv_idx = argc # blockarg is not supported
      recv_idx += send_shift
      comptime_recv = jit.peek_at_stack(recv_idx)

      # This is a .send call and we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        jit_call_opt_send_shift_stack(ctx, asm, argc, send_shift:)
      end

      # All structs from the same Struct class should have the same
      # length. So if our comptime_recv is embedded all runtime
      # structs of the same class should be as well, and the same is
      # true of the converse.
      embedded = C::FL_TEST_RAW(comptime_recv, C::RSTRUCT_EMBED_LEN_MASK)

      asm.comment('struct aref')
      asm.mov(:rax, ctx.stack_pop(1)) # recv

      if embedded
        asm.mov(:rax, [:rax, C.RStruct.offsetof(:as, :ary) + (C.VALUE.size * off)])
      else
        asm.mov(:rax, [:rax, C.RStruct.offsetof(:as, :heap, :ptr)])
        asm.mov(:rax, [:rax, C.VALUE.size * off])
      end

      ret = ctx.stack_push
      asm.mov(ret, :rax)

      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_send_shift_stack(ctx, asm, argc, send_shift:)
      # We don't support `send(:send, ...)` for now.
      assert_equal(1, send_shift)

      asm.comment('shift stack')
      (0...argc).reverse_each do |i|
        opnd = ctx.stack_opnd(i)
        opnd2 = ctx.stack_opnd(i + 1)
        asm.mov(:rax, opnd)
        asm.mov(opnd2, :rax)
      end

      ctx.stack_pop(1)
    end

    # vm_call_symbol
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_symbol(jit, ctx, asm, cme, flags, argc, kw_splat, block_handler, known_recv_class, send_shift:)
      flags |= C::VM_CALL_OPT_SEND | (kw_splat ? C::VM_CALL_KW_SPLAT : 0)

      comptime_symbol = jit.peek_at_stack(argc)
      if comptime_symbol.class != String && !static_symbol?(comptime_symbol)
        asm.incr_counter(:send_optimized_send_not_sym_or_str)
        return CantCompile
      end

      mid = C.get_symbol_id(comptime_symbol)
      if mid == 0
        asm.incr_counter(:send_optimized_send_null_mid)
        return CantCompile
      end

      asm.comment("Guard #{comptime_symbol.inspect} is on stack")
      class_changed_exit = counted_exit(side_exit(jit, ctx), :send_optimized_send_mid_class_changed)
      jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_symbol), ctx.stack_opnd(argc), comptime_symbol, class_changed_exit)
      asm.mov(C_ARGS[0], ctx.stack_opnd(argc))
      asm.call(C.rb_get_symbol_id)
      asm.cmp(C_RET, mid)
      id_changed_exit = counted_exit(side_exit(jit, ctx), :send_optimized_send_mid_id_changed)
      jit_chain_guard(:jne, jit, ctx, asm, id_changed_exit)

      # rb_callable_method_entry_with_refinements
      cme, _ = jit_search_method(jit, ctx, asm, mid, argc, flags, send_shift:)
      if cme == CantCompile
        return CantCompile
      end

      if flags & C::VM_CALL_FCALL != 0
        return jit_call_method(jit, ctx, asm, mid, argc, flags, cme, block_handler, known_recv_class, send_shift:)
      end

      raise NotImplementedError # unreachable for now
    end

    # vm_push_frame
    #
    # Frame structure:
    # | args | locals | cme/cref | block_handler/prev EP | frame type (EP here) | stack bottom (SP here)
    #
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_push_frame(jit, ctx, asm, cme, flags, argc, frame_type, block_handler, iseq: nil, local_size: 0, stack_max: 0, prev_ep: nil)
      # CHECK_VM_STACK_OVERFLOW0: next_cfp <= sp + (local_size + stack_max)
      asm.comment('stack overflow check')
      asm.lea(:rax, ctx.sp_opnd(C.rb_control_frame_t.size + C.VALUE.size * (local_size + stack_max)))
      asm.cmp(CFP, :rax)
      asm.jbe(counted_exit(side_exit(jit, ctx), :send_stackoverflow))

      # Pop blockarg after all side exits
      if flags & C::VM_CALL_ARGS_BLOCKARG != 0
        ctx.stack_pop(1)
      end

      if iseq
        # This was not handled in jit_callee_setup_arg
        opts_filled = argc - iseq.body.param.lead_num # TODO: kwarg
        opts_missing = iseq.body.param.opt_num - opts_filled
        local_size += opts_missing
      end
      local_size.times do |i|
        asm.comment('set local variables') if i == 0
        local_index = ctx.sp_offset + i
        asm.mov([SP, C.VALUE.size * local_index], Qnil)
      end

      asm.comment('set up EP with managing data')
      ep_offset = ctx.sp_offset + local_size + 2
      # ep[-2]: cref_or_me
      asm.mov(:rax, cme.to_i)
      asm.mov([SP, C.VALUE.size * (ep_offset - 2)], :rax)
      # ep[-1]: block handler or prev env ptr (specval)
      if prev_ep
        asm.mov(:rax, prev_ep.to_i | 1) # tagged prev ep
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax)
      elsif block_handler == C::VM_BLOCK_HANDLER_NONE
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], C::VM_BLOCK_HANDLER_NONE)
      elsif block_handler == C.rb_block_param_proxy
        # vm_caller_setup_arg_block: block_code == rb_block_param_proxy
        jit_get_lep(jit, asm, reg: :rax) # VM_CF_BLOCK_HANDLER: VM_CF_LEP
        asm.mov(:rax, [:rax, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]) # VM_CF_BLOCK_HANDLER: VM_ENV_BLOCK_HANDLER
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:block_code)], :rax) # reg_cfp->block_code = handler
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax) # return handler;
      else # assume blockiseq
        asm.mov(:rax, block_handler)
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:block_code)], :rax)
        asm.lea(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)]) # VM_CFP_TO_CAPTURED_BLOCK
        asm.or(:rax, 1) # VM_BH_FROM_ISEQ_BLOCK
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax)
      end
      # ep[-0]: ENV_FLAGS
      asm.mov([SP, C.VALUE.size * (ep_offset - 0)], frame_type)

      asm.comment('set up new frame')
      cfp_offset = -C.rb_control_frame_t.size # callee CFP
      # For ISEQ, JIT code will set it as needed. However, C func needs 0 there for svar frame detection.
      if iseq.nil?
        asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:pc)], 0)
      end
      asm.mov(:rax, iseq.to_i)
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:iseq)], :rax)
      self_index = ctx.sp_offset - (1 + argc) # blockarg has been popped
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
        return_ctx.stack_size -= argc # Pop args. blockarg has been popped
        return_ctx.sp_offset = 1 # SP is in the position after popping a receiver and arguments
        return_ctx.chain_depth = 0
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
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_callee_setup_arg(jit, ctx, asm, flags, argc, iseq)
      if flags & C::VM_CALL_KW_SPLAT == 0
        if C.rb_simple_iseq_p(iseq)
          if jit_caller_setup_arg(jit, ctx, asm, flags) == CantCompile
            return CantCompile
          end
          if jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags) == CantCompile
            return CantCompile
          end

          if argc != iseq.body.param.lead_num
            # argument_arity_error
            return CantCompile
          end

          return 0
        elsif C.rb_iseq_only_optparam_p(iseq)
          if jit_caller_setup_arg(jit, ctx, asm, flags) == CantCompile
            return CantCompile
          end
          if jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags) == CantCompile
            return CantCompile
          end

          lead_num = iseq.body.param.lead_num
          opt_num = iseq.body.param.opt_num
          opt = argc - lead_num

          if opt < 0 || opt > opt_num
            asm.incr_counter(:send_arity)
            return CantCompile
          end

          # Qnil push is handled in jit_push_frame

          return iseq.body.param.opt_table[opt]
        elsif C.rb_iseq_only_kwparam_p(iseq) && (flags & C::VM_CALL_ARGS_SPLAT) == 0
          asm.incr_counter(:send_iseq_kwparam)
          return CantCompile
        end
      end

      return jit_setup_parameters_complex(jit, ctx, asm, flags, argc, iseq)
    end

    # setup_parameters_complex
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_setup_parameters_complex(jit, ctx, asm, flags, argc, iseq)
      # We don't support setup_parameters_complex
      asm.incr_counter(:send_iseq_complex)
      return CantCompile
    end

    # CALLER_SETUP_ARG: Return CantCompile if not supported
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_caller_setup_arg(jit, ctx, asm, flags)
      if flags & C::VM_CALL_ARGS_SPLAT != 0
        # We don't support vm_caller_setup_arg_splat
        asm.incr_counter(:send_args_splat)
        return CantCompile
      end
      if flags & (C::VM_CALL_KWARG | C::VM_CALL_KW_SPLAT) != 0
        # We don't support keyword args either
        asm.incr_counter(:send_kwarg)
        return CantCompile
      end
    end

    # CALLER_REMOVE_EMPTY_KW_SPLAT: Return CantCompile if not supported
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_caller_remove_empty_kw_splat(jit, ctx, asm, flags)
      if (flags & C::VM_CALL_KW_SPLAT) > 0
        # We don't support removing the last Hash argument
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end
    end

    # Generate RARRAY_LEN. For array_opnd, use Opnd::Reg to reduce memory access,
    # and use Opnd::Mem to save registers.
    def jit_array_len(asm, array_reg, len_reg)
      asm.comment('get array length for embedded or heap')

      # Pull out the embed flag to check if it's an embedded array.
      asm.mov(len_reg, [array_reg, C.RBasic.offsetof(:flags)])

      # Get the length of the array
      asm.and(len_reg, C::RARRAY_EMBED_LEN_MASK)
      asm.sar(len_reg, C::RARRAY_EMBED_LEN_SHIFT)

      # Conditionally move the length of the heap array
      asm.test([array_reg, C.RBasic.offsetof(:flags)], C::RARRAY_EMBED_FLAG)

      # Select the array length value
      asm.cmovz(len_reg, [array_reg, C.RArray.offsetof(:as, :heap, :len)])
    end

    def assert_equal(left, right)
      if left != right
        raise "'#{left.inspect}' was not '#{right.inspect}'"
      end
    end

    def fixnum?(obj)
      (C.to_value(obj) & C::RUBY_FIXNUM_FLAG) == C::RUBY_FIXNUM_FLAG
    end

    def flonum?(obj)
      (C.to_value(obj) & C::RUBY_FLONUM_MASK) == C::RUBY_FLONUM_FLAG
    end

    def symbol?(obj)
      static_symbol?(obj) || dynamic_symbol?(obj)
    end

    def static_symbol?(obj)
      (C.to_value(obj) & 0xff) == C::RUBY_SYMBOL_FLAG
    end

    def dynamic_symbol?(obj)
      return false if C::SPECIAL_CONST_P(obj)
      C::RB_TYPE_P(obj, C::RUBY_T_SYMBOL)
    end

    def shape_too_complex?(obj)
      C.rb_shape_get_shape_id(obj) == C::OBJ_TOO_COMPLEX_SHAPE_ID
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def defer_compilation(jit, ctx, asm)
      # Make a stub to compile the current insn
      if ctx.chain_depth != 0
        raise "double defer!"
      end
      ctx.chain_depth += 1
      jit_direct_jump(jit.iseq, jit.pc, ctx, asm, comment: 'defer_compilation')
    end

    def jit_direct_jump(iseq, pc, ctx, asm, comment: 'jit_direct_jump')
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

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    def side_exit(jit, ctx)
      if side_exit = jit.side_exits[jit.pc]
        return side_exit
      end
      asm = Assembler.new
      @exit_compiler.compile_side_exit(jit.pc, ctx, asm)
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
      GC_REFS << obj
      C.to_value(obj)
    end

    def full_cfunc_return
      @full_cfunc_return ||= Assembler.new.then do |asm|
        @exit_compiler.compile_full_cfunc_return(asm)
        @ocb.write(asm)
      end
    end
  end
end
