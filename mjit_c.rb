# frozen_string_literal: true
# Part of this file is generated by tool/mjit/bindgen.rb.
# Run `make mjit-bindgen` to update code between "MJIT bindgen begin" and "MJIT bindgen end".
module RubyVM::MJIT
  C = Object.new

  class << C
    def ROBJECT_EMBED_LEN_MAX
      Primitive.cexpr! 'INT2NUM(RBIMPL_EMBED_LEN_MAX_OF(VALUE))'
    end

    def cdhash_to_hash(cdhash_addr)
      Primitive.cdhash_to_hash(cdhash_addr)
    end

    def builtin_compiler(f, bf, index, stack_size, builtin_inline_p)
      Primitive.builtin_compile(f, bf.to_i, index, stack_size, builtin_inline_p)
    end

    def has_cache_for_send(cc, insn)
      Primitive.has_cache_for_send(cc.to_i, insn)
    end

    def rb_iseq_check(iseq)
      _iseq_addr = iseq.to_i
      iseq_addr = Primitive.cexpr! 'PTR2NUM((VALUE)rb_iseq_check((rb_iseq_t *)NUM2PTR(_iseq_addr)))'
      rb_iseq_t.new(iseq_addr)
    end

    def rb_iseq_path(iseq)
      _iseq_addr = iseq.to_i
      Primitive.cexpr! 'rb_iseq_path((rb_iseq_t *)NUM2PTR(_iseq_addr))'
    end

    def vm_ci_argc(ci)
      _ci_addr = ci.to_i
      Primitive.cexpr! 'UINT2NUM(vm_ci_argc((CALL_INFO)NUM2PTR(_ci_addr)))'
    end

    def vm_ci_flag(ci)
      _ci_addr = ci.to_i
      Primitive.cexpr! 'UINT2NUM(vm_ci_flag((CALL_INFO)NUM2PTR(_ci_addr)))'
    end

    def rb_splat_or_kwargs_p(ci)
      _ci_addr = ci.to_i
      Primitive.cexpr! 'RBOOL(rb_splat_or_kwargs_p((CALL_INFO)NUM2PTR(_ci_addr)))'
    end

    def fastpath_applied_iseq_p(ci, cc, iseq)
      _ci_addr = ci.to_i
      _cc_addr = cc.to_i
      _iseq_addr = iseq.to_i
      Primitive.cexpr! 'RBOOL(fastpath_applied_iseq_p((CALL_INFO)NUM2PTR(_ci_addr), (CALL_CACHE)NUM2PTR(_cc_addr), (rb_iseq_t *)NUM2PTR(_iseq_addr)))'
    end

    def mjit_opts
      addr = Primitive.cexpr! 'PTR2NUM((VALUE)&mjit_opts)'
      mjit_options.new(addr)
    end

    def mjit_call_attribute_sp_inc(insn, operands)
      _operands_addr = operands.to_i
      Primitive.cexpr! 'LONG2NUM(mjit_call_attribute_sp_inc(NUM2INT(insn), (VALUE *)NUM2PTR(_operands_addr)))'
    end

    def mjit_capture_cc_entries(compiled_body, captured_body)
      _compiled_body_addr = compiled_body.to_i
      _captured_body_addr = captured_body.to_i
      Primitive.cexpr! 'INT2NUM(mjit_capture_cc_entries((struct rb_iseq_constant_body *)NUM2PTR(_compiled_body_addr), (struct rb_iseq_constant_body *)NUM2PTR(_captured_body_addr)))'
    end

    #const struct rb_iseq_constant_body *body, union iseq_inline_storage_entry *is_entries
    def mjit_capture_is_entries(body, is_entries)
      _body_addr = body.to_i
      _is_entries_addr = is_entries.to_i
      Primitive.cstmt! %{
        mjit_capture_is_entries((struct rb_iseq_constant_body *)NUM2PTR(_body_addr), (union iseq_inline_storage_entry *)NUM2PTR(_is_entries_addr));
        return Qnil;
      }
    end

    # Convert encoded VM pointers to insn BINs.
    def rb_vm_insn_decode(encoded)
      Primitive.cexpr! 'INT2NUM(rb_vm_insn_decode(NUM2PTR(encoded)))'
    end

    # Convert insn BINs to encoded VM pointers. This one is not used by the compiler, but useful for debugging.
    def rb_vm_insn_encode(bin)
      Primitive.cexpr! 'PTR2NUM((VALUE)rb_vm_get_insns_address_table()[NUM2INT(bin)])'
    end

    def insn_may_depend_on_sp_or_pc(insn, opes)
      _opes_addr = opes.to_i
      Primitive.cexpr! 'RBOOL(insn_may_depend_on_sp_or_pc(NUM2INT(insn), (VALUE *)NUM2PTR(_opes_addr)))'
    end

    # Convert Integer VALUE to an actual Ruby object
    def to_ruby(value)
      Primitive.cexpr! '(VALUE)NUM2PTR(value)'
    end

    # Convert RubyVM::InstructionSequence to C.rb_iseq_t. Not used by the compiler, but useful for debugging.
    def rb_iseqw_to_iseq(iseqw)
      iseq_addr = Primitive.cexpr! 'PTR2NUM((VALUE)rb_iseqw_to_iseq(iseqw))'
      rb_iseq_t.new(iseq_addr)
    end

    # TODO: remove this after migration
    def fprintf(f, str)
      Primitive.cstmt! %{
        fprintf((FILE *)NUM2PTR(f), "%s", RSTRING_PTR(str));
        return Qnil;
      }
    end

    def rb_cFalseClass; Primitive.cexpr! 'PTR2NUM(rb_cFalseClass)' end
    def rb_cNilClass;   Primitive.cexpr! 'PTR2NUM(rb_cNilClass)'   end
    def rb_cTrueClass;  Primitive.cexpr! 'PTR2NUM(rb_cTrueClass)'  end
    def rb_cInteger;    Primitive.cexpr! 'PTR2NUM(rb_cInteger)'    end
    def rb_cSymbol;     Primitive.cexpr! 'PTR2NUM(rb_cSymbol)'     end
    def rb_cFloat;      Primitive.cexpr! 'PTR2NUM(rb_cFloat)'      end
  end

  ### MJIT bindgen begin ###

  def C.USE_LAZY_LOAD
    Primitive.cexpr! %q{ RBOOL(USE_LAZY_LOAD != 0) }
  end

  def C.USE_RVARGC
    Primitive.cexpr! %q{ RBOOL(USE_RVARGC != 0) }
  end

  def C.NOT_COMPILED_STACK_SIZE
    Primitive.cexpr! %q{ INT2NUM(NOT_COMPILED_STACK_SIZE) }
  end

  def C.VM_CALL_KW_SPLAT
    Primitive.cexpr! %q{ INT2NUM(VM_CALL_KW_SPLAT) }
  end

  def C.VM_CALL_KW_SPLAT_bit
    Primitive.cexpr! %q{ INT2NUM(VM_CALL_KW_SPLAT_bit) }
  end

  def C.VM_CALL_TAILCALL
    Primitive.cexpr! %q{ INT2NUM(VM_CALL_TAILCALL) }
  end

  def C.VM_CALL_TAILCALL_bit
    Primitive.cexpr! %q{ INT2NUM(VM_CALL_TAILCALL_bit) }
  end

  def C.VM_METHOD_TYPE_CFUNC
    Primitive.cexpr! %q{ INT2NUM(VM_METHOD_TYPE_CFUNC) }
  end

  def C.VM_METHOD_TYPE_ISEQ
    Primitive.cexpr! %q{ INT2NUM(VM_METHOD_TYPE_ISEQ) }
  end

  def C.CALL_DATA
    @CALL_DATA ||= self.rb_call_data
  end

  def C.IC
    @IC ||= self.iseq_inline_constant_cache
  end

  def C.IVC
    @IVC ||= self.iseq_inline_iv_cache_entry
  end

  def C.RB_BUILTIN
    @RB_BUILTIN ||= self.rb_builtin_function
  end

  def C.compile_branch
    @compile_branch ||= CType::Struct.new(
      "compile_branch", Primitive.cexpr!("SIZEOF(struct compile_branch)"),
      stack_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct compile_branch *)NULL)), stack_size)")],
      finish_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct compile_branch *)NULL)), finish_p)")],
    )
  end

  def C.compile_status
    @compile_status ||= CType::Struct.new(
      "compile_status", Primitive.cexpr!("SIZEOF(struct compile_status)"),
      success: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), success)")],
      stack_size_for_pos: [CType::Pointer.new { CType::Immediate.parse("int") }, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), stack_size_for_pos)")],
      local_stack_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), local_stack_p)")],
      is_entries: [CType::Pointer.new { self.iseq_inline_storage_entry }, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), is_entries)")],
      cc_entries_index: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), cc_entries_index)")],
      compiled_iseq: [CType::Pointer.new { self.rb_iseq_constant_body }, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), compiled_iseq)")],
      compiled_id: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), compiled_id)")],
      compile_info: [CType::Pointer.new { self.rb_mjit_compile_info }, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), compile_info)")],
      merge_ivar_guards_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), merge_ivar_guards_p)")],
      ivar_serial: [self.rb_serial_t, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), ivar_serial)")],
      max_ivar_index: [CType::Immediate.parse("size_t"), Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), max_ivar_index)")],
      inlined_iseqs: [CType::Pointer.new { CType::Pointer.new { self.rb_iseq_constant_body } }, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), inlined_iseqs)")],
      inline_context: [self.inlined_call_context, Primitive.cexpr!("OFFSETOF((*((struct compile_status *)NULL)), inline_context)")],
    )
  end

  def C.inlined_call_context
    @inlined_call_context ||= CType::Struct.new(
      "inlined_call_context", Primitive.cexpr!("SIZEOF(struct inlined_call_context)"),
      orig_argc: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct inlined_call_context *)NULL)), orig_argc)")],
      me: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct inlined_call_context *)NULL)), me)")],
      param_size: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct inlined_call_context *)NULL)), param_size)")],
      local_size: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct inlined_call_context *)NULL)), local_size)")],
    )
  end

  def C.iseq_inline_constant_cache
    @iseq_inline_constant_cache ||= CType::Struct.new(
      "iseq_inline_constant_cache", Primitive.cexpr!("SIZEOF(struct iseq_inline_constant_cache)"),
      entry: [CType::Pointer.new { self.iseq_inline_constant_cache_entry }, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache *)NULL)), entry)")],
      segments: [CType::Pointer.new { self.ID }, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache *)NULL)), segments)")],
    )
  end

  def C.iseq_inline_constant_cache_entry
    @iseq_inline_constant_cache_entry ||= CType::Struct.new(
      "iseq_inline_constant_cache_entry", Primitive.cexpr!("SIZEOF(struct iseq_inline_constant_cache_entry)"),
      flags: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache_entry *)NULL)), flags)")],
      value: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache_entry *)NULL)), value)")],
      _unused1: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache_entry *)NULL)), _unused1)")],
      _unused2: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache_entry *)NULL)), _unused2)")],
      ic_cref: [CType::Pointer.new { self.rb_cref_t }, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_constant_cache_entry *)NULL)), ic_cref)")],
    )
  end

  def C.iseq_inline_iv_cache_entry
    @iseq_inline_iv_cache_entry ||= CType::Struct.new(
      "iseq_inline_iv_cache_entry", Primitive.cexpr!("SIZEOF(struct iseq_inline_iv_cache_entry)"),
      entry: [CType::Pointer.new { self.rb_iv_index_tbl_entry }, Primitive.cexpr!("OFFSETOF((*((struct iseq_inline_iv_cache_entry *)NULL)), entry)")],
    )
  end

  def C.iseq_inline_storage_entry
    @iseq_inline_storage_entry ||= CType::Union.new(
      "iseq_inline_storage_entry", Primitive.cexpr!("SIZEOF(union iseq_inline_storage_entry)"),
      once: CType::Struct.new(
        "", Primitive.cexpr!("SIZEOF(((union iseq_inline_storage_entry *)NULL)->once)"),
        running_thread: [CType::Pointer.new { self.rb_thread_struct }, Primitive.cexpr!("OFFSETOF(((union iseq_inline_storage_entry *)NULL)->once, running_thread)")],
        value: [self.VALUE, Primitive.cexpr!("OFFSETOF(((union iseq_inline_storage_entry *)NULL)->once, value)")],
      ),
      ic_cache: self.iseq_inline_constant_cache,
      iv_cache: self.iseq_inline_iv_cache_entry,
    )
  end

  def C.mjit_options
    @mjit_options ||= CType::Struct.new(
      "mjit_options", Primitive.cexpr!("SIZEOF(struct mjit_options)"),
      on: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), on)")],
      save_temps: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), save_temps)")],
      warnings: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), warnings)")],
      debug: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), debug)")],
      debug_flags: [CType::Pointer.new { CType::Immediate.parse("char") }, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), debug_flags)")],
      wait: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), wait)")],
      min_calls: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), min_calls)")],
      verbose: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), verbose)")],
      max_cache_size: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), max_cache_size)")],
      pause: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), pause)")],
      custom: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct mjit_options *)NULL)), custom)")],
    )
  end

  def C.rb_builtin_function
    @rb_builtin_function ||= CType::Struct.new(
      "rb_builtin_function", Primitive.cexpr!("SIZEOF(struct rb_builtin_function)"),
      func_ptr: [CType::Pointer.new { CType::Immediate.parse("void") }, Primitive.cexpr!("OFFSETOF((*((struct rb_builtin_function *)NULL)), func_ptr)")],
      argc: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct rb_builtin_function *)NULL)), argc)")],
      index: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct rb_builtin_function *)NULL)), index)")],
      name: [CType::Pointer.new { CType::Immediate.parse("char") }, Primitive.cexpr!("OFFSETOF((*((struct rb_builtin_function *)NULL)), name)")],
      compiler: [CType::Immediate.parse("void *"), Primitive.cexpr!("OFFSETOF((*((struct rb_builtin_function *)NULL)), compiler)")],
    )
  end

  def C.rb_call_data
    @rb_call_data ||= CType::Struct.new(
      "rb_call_data", Primitive.cexpr!("SIZEOF(struct rb_call_data)"),
      ci: [CType::Pointer.new { self.rb_callinfo }, Primitive.cexpr!("OFFSETOF((*((struct rb_call_data *)NULL)), ci)")],
      cc: [CType::Pointer.new { self.rb_callcache }, Primitive.cexpr!("OFFSETOF((*((struct rb_call_data *)NULL)), cc)")],
    )
  end

  def C.rb_callable_method_entry_struct
    @rb_callable_method_entry_struct ||= CType::Struct.new(
      "rb_callable_method_entry_struct", Primitive.cexpr!("SIZEOF(struct rb_callable_method_entry_struct)"),
      flags: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callable_method_entry_struct *)NULL)), flags)")],
      defined_class: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callable_method_entry_struct *)NULL)), defined_class)")],
      def: [CType::Pointer.new { self.rb_method_definition_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_callable_method_entry_struct *)NULL)), def)")],
      called_id: [self.ID, Primitive.cexpr!("OFFSETOF((*((struct rb_callable_method_entry_struct *)NULL)), called_id)")],
      owner: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callable_method_entry_struct *)NULL)), owner)")],
    )
  end

  def C.rb_callcache
    @rb_callcache ||= CType::Struct.new(
      "rb_callcache", Primitive.cexpr!("SIZEOF(struct rb_callcache)"),
      flags: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callcache *)NULL)), flags)")],
      klass: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callcache *)NULL)), klass)")],
      cme_: [CType::Pointer.new { self.rb_callable_method_entry_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_callcache *)NULL)), cme_)")],
      call_: [self.vm_call_handler, Primitive.cexpr!("OFFSETOF((*((struct rb_callcache *)NULL)), call_)")],
      aux_: [CType::Union.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_callcache *)NULL)->aux_)"),
        attr_index: CType::Immediate.parse("unsigned int"),
        method_missing_reason: self.method_missing_reason,
        v: self.VALUE,
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_callcache *)NULL)), aux_)")],
    )
  end

  def C.rb_callinfo
    @rb_callinfo ||= CType::Struct.new(
      "rb_callinfo", Primitive.cexpr!("SIZEOF(struct rb_callinfo)"),
      flags: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callinfo *)NULL)), flags)")],
      kwarg: [CType::Pointer.new { self.rb_callinfo_kwarg }, Primitive.cexpr!("OFFSETOF((*((struct rb_callinfo *)NULL)), kwarg)")],
      mid: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callinfo *)NULL)), mid)")],
      flag: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callinfo *)NULL)), flag)")],
      argc: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_callinfo *)NULL)), argc)")],
    )
  end

  def C.rb_control_frame_t
    @rb_control_frame_t ||= CType::Struct.new(
      "rb_control_frame_struct", Primitive.cexpr!("SIZEOF(struct rb_control_frame_struct)"),
      pc: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), pc)")],
      sp: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), sp)")],
      iseq: [CType::Pointer.new { self.rb_iseq_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), iseq)")],
      self: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), self)")],
      ep: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), ep)")],
      block_code: [CType::Pointer.new { CType::Immediate.parse("void") }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), block_code)")],
      __bp__: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), __bp__)")],
      jit_return: [CType::Pointer.new { CType::Immediate.parse("void") }, Primitive.cexpr!("OFFSETOF((*((struct rb_control_frame_struct *)NULL)), jit_return)")],
    )
  end

  def C.rb_cref_t
    @rb_cref_t ||= CType::Struct.new(
      "rb_cref_struct", Primitive.cexpr!("SIZEOF(struct rb_cref_struct)"),
      flags: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_cref_struct *)NULL)), flags)")],
      refinements: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_cref_struct *)NULL)), refinements)")],
      klass_or_self: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_cref_struct *)NULL)), klass_or_self)")],
      next: [CType::Pointer.new { self.rb_cref_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_cref_struct *)NULL)), next)")],
      scope_visi: [self.rb_scope_visibility_t, Primitive.cexpr!("OFFSETOF((*((struct rb_cref_struct *)NULL)), scope_visi)")],
    )
  end

  def C.rb_execution_context_struct
    @rb_execution_context_struct ||= CType::Struct.new(
      "rb_execution_context_struct", Primitive.cexpr!("SIZEOF(struct rb_execution_context_struct)"),
      vm_stack: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), vm_stack)")],
      vm_stack_size: [CType::Immediate.parse("size_t"), Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), vm_stack_size)")],
      cfp: [CType::Pointer.new { self.rb_control_frame_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), cfp)")],
      tag: [CType::Pointer.new { self.rb_vm_tag }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), tag)")],
      interrupt_flag: [self.rb_atomic_t, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), interrupt_flag)")],
      interrupt_mask: [self.rb_atomic_t, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), interrupt_mask)")],
      fiber_ptr: [CType::Pointer.new { self.rb_fiber_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), fiber_ptr)")],
      thread_ptr: [CType::Pointer.new { self.rb_thread_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), thread_ptr)")],
      local_storage: [CType::Pointer.new { self.rb_id_table }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), local_storage)")],
      local_storage_recursive_hash: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), local_storage_recursive_hash)")],
      local_storage_recursive_hash_for_trace: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), local_storage_recursive_hash_for_trace)")],
      root_lep: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), root_lep)")],
      root_svar: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), root_svar)")],
      ensure_list: [CType::Pointer.new { self.rb_ensure_list_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), ensure_list)")],
      trace_arg: [CType::Pointer.new { self.rb_trace_arg_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), trace_arg)")],
      errinfo: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), errinfo)")],
      passed_block_handler: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), passed_block_handler)")],
      raised_flag: [CType::Immediate.parse("uint8_t"), Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), raised_flag)")],
      method_missing_reason: [self.method_missing_reason, nil],
      private_const_reference: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), private_const_reference)")],
      machine: [CType::Struct.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_execution_context_struct *)NULL)->machine)"),
        stack_start: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF(((struct rb_execution_context_struct *)NULL)->machine, stack_start)")],
        stack_end: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF(((struct rb_execution_context_struct *)NULL)->machine, stack_end)")],
        stack_maxsize: [CType::Immediate.parse("size_t"), Primitive.cexpr!("OFFSETOF(((struct rb_execution_context_struct *)NULL)->machine, stack_maxsize)")],
        regs: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_execution_context_struct *)NULL)->machine, regs)")],
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_execution_context_struct *)NULL)), machine)")],
    )
  end

  def C.rb_execution_context_t
    @rb_execution_context_t ||= self.rb_execution_context_struct
  end

  def C.rb_iseq_constant_body
    @rb_iseq_constant_body ||= CType::Struct.new(
      "rb_iseq_constant_body", Primitive.cexpr!("SIZEOF(struct rb_iseq_constant_body)"),
      type: [self.rb_iseq_type, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), type)")],
      iseq_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), iseq_size)")],
      iseq_encoded: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), iseq_encoded)")],
      param: [CType::Struct.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_constant_body *)NULL)->param)"),
        flags: [CType::Struct.new(
          "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_constant_body *)NULL)->param.flags)"),
          has_lead: [CType::BitField.new(1, 0), 0],
          has_opt: [CType::BitField.new(1, 1), 1],
          has_rest: [CType::BitField.new(1, 2), 2],
          has_post: [CType::BitField.new(1, 3), 3],
          has_kw: [CType::BitField.new(1, 4), 4],
          has_kwrest: [CType::BitField.new(1, 5), 5],
          has_block: [CType::BitField.new(1, 6), 6],
          ambiguous_param0: [CType::BitField.new(1, 7), 7],
          accepts_no_kwarg: [CType::BitField.new(1, 0), 8],
          ruby2_keywords: [CType::BitField.new(1, 1), 9],
        ), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, flags)")],
        size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, size)")],
        lead_num: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, lead_num)")],
        opt_num: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, opt_num)")],
        rest_start: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, rest_start)")],
        post_start: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, post_start)")],
        post_num: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, post_num)")],
        block_start: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, block_start)")],
        opt_table: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, opt_table)")],
        keyword: [CType::Pointer.new { self.rb_iseq_param_keyword }, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->param, keyword)")],
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), param)")],
      location: [self.rb_iseq_location_t, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), location)")],
      insns_info: [self.iseq_insn_info, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), insns_info)")],
      local_table: [CType::Pointer.new { self.ID }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), local_table)")],
      catch_table: [CType::Pointer.new { self.iseq_catch_table }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), catch_table)")],
      parent_iseq: [CType::Pointer.new { self.rb_iseq_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), parent_iseq)")],
      local_iseq: [CType::Pointer.new { self.rb_iseq_struct }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), local_iseq)")],
      is_entries: [CType::Pointer.new { self.iseq_inline_storage_entry }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), is_entries)")],
      call_data: [CType::Pointer.new { self.rb_call_data }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), call_data)")],
      variable: [CType::Struct.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_constant_body *)NULL)->variable)"),
        flip_count: [self.rb_snum_t, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->variable, flip_count)")],
        script_lines: [self.VALUE, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->variable, script_lines)")],
        coverage: [self.VALUE, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->variable, coverage)")],
        pc2branchindex: [self.VALUE, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->variable, pc2branchindex)")],
        original_iseq: [CType::Pointer.new { self.VALUE }, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_constant_body *)NULL)->variable, original_iseq)")],
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), variable)")],
      local_table_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), local_table_size)")],
      ic_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), ic_size)")],
      ise_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), ise_size)")],
      ivc_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), ivc_size)")],
      icvarc_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), icvarc_size)")],
      ci_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), ci_size)")],
      stack_max: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), stack_max)")],
      mark_bits: [CType::Union.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_constant_body *)NULL)->mark_bits)"),
        list: CType::Pointer.new { self.iseq_bits_t },
        single: self.iseq_bits_t,
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), mark_bits)")],
      catch_except_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), catch_except_p)")],
      builtin_inline_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), builtin_inline_p)")],
      outer_variables: [CType::Pointer.new { self.rb_id_table }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), outer_variables)")],
      mandatory_only_iseq: [CType::Pointer.new { self.rb_iseq_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), mandatory_only_iseq)")],
      jit_func: [CType::Immediate.parse("void *"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), jit_func)")],
      total_calls: [CType::Immediate.parse("unsigned long"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), total_calls)")],
      jit_unit: [CType::Pointer.new { self.rb_mjit_unit }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), jit_unit)")],
      yjit_payload: [CType::Pointer.new { CType::Immediate.parse("void") }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_constant_body *)NULL)), yjit_payload)")],
    )
  end

  def C.rb_iseq_location_t
    @rb_iseq_location_t ||= CType::Struct.new(
      "rb_iseq_location_struct", Primitive.cexpr!("SIZEOF(struct rb_iseq_location_struct)"),
      pathobj: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_location_struct *)NULL)), pathobj)"), true],
      base_label: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_location_struct *)NULL)), base_label)"), true],
      label: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_location_struct *)NULL)), label)"), true],
      first_lineno: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_location_struct *)NULL)), first_lineno)"), true],
      node_id: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_location_struct *)NULL)), node_id)")],
      code_location: [self.rb_code_location_t, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_location_struct *)NULL)), code_location)")],
    )
  end

  def C.rb_iseq_struct
    @rb_iseq_struct ||= CType::Struct.new(
      "rb_iseq_struct", Primitive.cexpr!("SIZEOF(struct rb_iseq_struct)"),
      flags: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_struct *)NULL)), flags)")],
      wrapper: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_struct *)NULL)), wrapper)")],
      body: [CType::Pointer.new { self.rb_iseq_constant_body }, Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_struct *)NULL)), body)")],
      aux: [CType::Union.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_struct *)NULL)->aux)"),
        compile_data: CType::Pointer.new { self.iseq_compile_data },
        loader: CType::Struct.new(
          "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_struct *)NULL)->aux.loader)"),
          obj: [self.VALUE, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_struct *)NULL)->aux.loader, obj)")],
          index: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF(((struct rb_iseq_struct *)NULL)->aux.loader, index)")],
        ),
        exec: CType::Struct.new(
          "", Primitive.cexpr!("SIZEOF(((struct rb_iseq_struct *)NULL)->aux.exec)"),
          local_hooks: [CType::Pointer.new { self.rb_hook_list_struct }, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_struct *)NULL)->aux.exec, local_hooks)")],
          global_trace_events: [self.rb_event_flag_t, Primitive.cexpr!("OFFSETOF(((struct rb_iseq_struct *)NULL)->aux.exec, global_trace_events)")],
        ),
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_iseq_struct *)NULL)), aux)")],
    )
  end

  def C.rb_iseq_t
    @rb_iseq_t ||= self.rb_iseq_struct
  end

  def C.rb_iv_index_tbl_entry
    @rb_iv_index_tbl_entry ||= CType::Struct.new(
      "rb_iv_index_tbl_entry", Primitive.cexpr!("SIZEOF(struct rb_iv_index_tbl_entry)"),
      index: [CType::Immediate.parse("uint32_t"), Primitive.cexpr!("OFFSETOF((*((struct rb_iv_index_tbl_entry *)NULL)), index)")],
      class_serial: [self.rb_serial_t, Primitive.cexpr!("OFFSETOF((*((struct rb_iv_index_tbl_entry *)NULL)), class_serial)")],
      class_value: [self.VALUE, Primitive.cexpr!("OFFSETOF((*((struct rb_iv_index_tbl_entry *)NULL)), class_value)")],
    )
  end

  def C.rb_method_definition_struct
    @rb_method_definition_struct ||= CType::Struct.new(
      "rb_method_definition_struct", Primitive.cexpr!("SIZEOF(struct rb_method_definition_struct)"),
      type: [self.rb_method_type_t, 0],
      iseq_overload: [CType::BitField.new(1, 4), 4],
      alias_count: [CType::BitField.new(27, 5), 5],
      complemented_count: [CType::BitField.new(28, 0), 32],
      no_redef_warning: [CType::BitField.new(1, 4), 60],
      body: [CType::Union.new(
        "", Primitive.cexpr!("SIZEOF(((struct rb_method_definition_struct *)NULL)->body)"),
        iseq: self.rb_method_iseq_t,
        cfunc: self.rb_method_cfunc_t,
        attr: self.rb_method_attr_t,
        alias: self.rb_method_alias_t,
        refined: self.rb_method_refined_t,
        bmethod: self.rb_method_bmethod_t,
        optimized: self.rb_method_optimized_t,
      ), Primitive.cexpr!("OFFSETOF((*((struct rb_method_definition_struct *)NULL)), body)")],
      original_id: [self.ID, Primitive.cexpr!("OFFSETOF((*((struct rb_method_definition_struct *)NULL)), original_id)")],
      method_serial: [CType::Immediate.parse("uintptr_t"), Primitive.cexpr!("OFFSETOF((*((struct rb_method_definition_struct *)NULL)), method_serial)")],
    )
  end

  def C.rb_method_iseq_t
    @rb_method_iseq_t ||= CType::Struct.new(
      "rb_method_iseq_struct", Primitive.cexpr!("SIZEOF(struct rb_method_iseq_struct)"),
      iseqptr: [CType::Pointer.new { self.rb_iseq_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_method_iseq_struct *)NULL)), iseqptr)")],
      cref: [CType::Pointer.new { self.rb_cref_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_method_iseq_struct *)NULL)), cref)")],
    )
  end

  def C.rb_method_type_t
    @rb_method_type_t ||= CType::Immediate.parse("int")
  end

  def C.rb_mjit_compile_info
    @rb_mjit_compile_info ||= CType::Struct.new(
      "rb_mjit_compile_info", Primitive.cexpr!("SIZEOF(struct rb_mjit_compile_info)"),
      disable_ivar_cache: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_compile_info *)NULL)), disable_ivar_cache)")],
      disable_exivar_cache: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_compile_info *)NULL)), disable_exivar_cache)")],
      disable_send_cache: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_compile_info *)NULL)), disable_send_cache)")],
      disable_inlining: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_compile_info *)NULL)), disable_inlining)")],
      disable_const_cache: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_compile_info *)NULL)), disable_const_cache)")],
    )
  end

  def C.rb_mjit_unit
    @rb_mjit_unit ||= CType::Struct.new(
      "rb_mjit_unit", Primitive.cexpr!("SIZEOF(struct rb_mjit_unit)"),
      unode: [self.ccan_list_node, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), unode)")],
      id: [CType::Immediate.parse("int"), Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), id)")],
      handle: [CType::Pointer.new { CType::Immediate.parse("void") }, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), handle)")],
      iseq: [CType::Pointer.new { self.rb_iseq_t }, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), iseq)")],
      used_code_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), used_code_p)")],
      compact_p: [self._Bool, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), compact_p)")],
      compile_info: [self.rb_mjit_compile_info, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), compile_info)")],
      cc_entries: [CType::Pointer.new { CType::Pointer.new { self.rb_callcache } }, Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), cc_entries)")],
      cc_entries_size: [CType::Immediate.parse("unsigned int"), Primitive.cexpr!("OFFSETOF((*((struct rb_mjit_unit *)NULL)), cc_entries_size)")],
    )
  end

  def C.rb_serial_t
    @rb_serial_t ||= CType::Immediate.parse("unsigned long long")
  end

  def C.VALUE
    @VALUE ||= CType::Immediate.find(Primitive.cexpr!("SIZEOF(VALUE)"), Primitive.cexpr!("SIGNED_TYPE_P(VALUE)"))
  end

  def C._Bool
    CType::Bool.new
  end

  def C.ID
    CType::Stub.new(:ID)
  end

  def C.rb_thread_struct
    CType::Stub.new(:rb_thread_struct)
  end

  def C.vm_call_handler
    CType::Stub.new(:vm_call_handler)
  end

  def C.method_missing_reason
    CType::Stub.new(:method_missing_reason)
  end

  def C.rb_callinfo_kwarg
    CType::Stub.new(:rb_callinfo_kwarg)
  end

  def C.rb_cref_struct
    CType::Stub.new(:rb_cref_struct)
  end

  def C.rb_scope_visibility_t
    CType::Stub.new(:rb_scope_visibility_t)
  end

  def C.rb_vm_tag
    CType::Stub.new(:rb_vm_tag)
  end

  def C.rb_atomic_t
    CType::Stub.new(:rb_atomic_t)
  end

  def C.rb_fiber_t
    CType::Stub.new(:rb_fiber_t)
  end

  def C.rb_id_table
    CType::Stub.new(:rb_id_table)
  end

  def C.rb_ensure_list_t
    CType::Stub.new(:rb_ensure_list_t)
  end

  def C.rb_trace_arg_struct
    CType::Stub.new(:rb_trace_arg_struct)
  end

  def C.rb_iseq_type
    CType::Stub.new(:rb_iseq_type)
  end

  def C.rb_iseq_param_keyword
    CType::Stub.new(:rb_iseq_param_keyword)
  end

  def C.iseq_insn_info
    CType::Stub.new(:iseq_insn_info)
  end

  def C.iseq_catch_table
    CType::Stub.new(:iseq_catch_table)
  end

  def C.rb_snum_t
    CType::Stub.new(:rb_snum_t)
  end

  def C.iseq_bits_t
    CType::Stub.new(:iseq_bits_t)
  end

  def C.rb_code_location_t
    CType::Stub.new(:rb_code_location_t)
  end

  def C.iseq_compile_data
    CType::Stub.new(:iseq_compile_data)
  end

  def C.rb_hook_list_struct
    CType::Stub.new(:rb_hook_list_struct)
  end

  def C.rb_event_flag_t
    CType::Stub.new(:rb_event_flag_t)
  end

  def C.rb_method_cfunc_t
    CType::Stub.new(:rb_method_cfunc_t)
  end

  def C.rb_method_attr_t
    CType::Stub.new(:rb_method_attr_t)
  end

  def C.rb_method_alias_t
    CType::Stub.new(:rb_method_alias_t)
  end

  def C.rb_method_refined_t
    CType::Stub.new(:rb_method_refined_t)
  end

  def C.rb_method_bmethod_t
    CType::Stub.new(:rb_method_bmethod_t)
  end

  def C.rb_method_optimized_t
    CType::Stub.new(:rb_method_optimized_t)
  end

  def C.ccan_list_node
    CType::Stub.new(:ccan_list_node)
  end

  ### MJIT bindgen end ###
end if RubyVM::MJIT.enabled?
