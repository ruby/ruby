require_relative 'c_type'

module RubyVM::MJIT
  def C.NOT_COMPILED_STACK_SIZE = -1

  def C.USE_LAZY_LOAD = false

  def C.USE_RVARGC = true

  def C.VM_CALL_KW_SPLAT = (0x01 << self.VM_CALL_KW_SPLAT_bit)

  def C.VM_CALL_TAILCALL = (0x01 << self.VM_CALL_TAILCALL_bit)

  def C.VM_METHOD_TYPE_CFUNC = 1

  def C.VM_METHOD_TYPE_ISEQ = 0

  def C.VM_CALL_KW_SPLAT_bit = 7

  def C.VM_CALL_TAILCALL_bit = 8

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

  def C.VALUE
    @VALUE ||= CType::Immediate.new(-5)
  end

  def C.compile_branch
    @compile_branch ||= CType::Struct.new(
      "compile_branch", 8,
      stack_size: [0, CType::Immediate.new(-4)],
      finish_p: [32, self._Bool],
    )
  end

  def C.compile_status
    @compile_status ||= CType::Struct.new(
      "compile_status", 120,
      success: [0, self._Bool],
      stack_size_for_pos: [64, CType::Pointer.new { CType::Immediate.new(4) }],
      local_stack_p: [128, self._Bool],
      is_entries: [192, CType::Pointer.new { self.iseq_inline_storage_entry }],
      cc_entries_index: [256, CType::Immediate.new(4)],
      compiled_iseq: [320, CType::Pointer.new { self.rb_iseq_constant_body }],
      compiled_id: [384, CType::Immediate.new(4)],
      compile_info: [448, CType::Pointer.new { self.rb_mjit_compile_info }],
      merge_ivar_guards_p: [512, self._Bool],
      ivar_serial: [576, self.rb_serial_t],
      max_ivar_index: [640, CType::Immediate.new(-5)],
      inlined_iseqs: [704, CType::Pointer.new { CType::Pointer.new { self.rb_iseq_constant_body } }],
      inline_context: [768, self.inlined_call_context],
    )
  end

  def C.inlined_call_context
    @inlined_call_context ||= CType::Struct.new(
      "inlined_call_context", 24,
      orig_argc: [0, CType::Immediate.new(4)],
      me: [64, self.VALUE],
      param_size: [128, CType::Immediate.new(4)],
      local_size: [160, CType::Immediate.new(4)],
    )
  end

  def C.iseq_inline_constant_cache
    @iseq_inline_constant_cache ||= CType::Struct.new(
      "iseq_inline_constant_cache", 16,
      entry: [0, CType::Pointer.new { self.iseq_inline_constant_cache_entry }],
      segments: [64, CType::Pointer.new { self.ID }],
    )
  end

  def C.iseq_inline_constant_cache_entry
    @iseq_inline_constant_cache_entry ||= CType::Struct.new(
      "iseq_inline_constant_cache_entry", 40,
      flags: [0, self.VALUE],
      value: [64, self.VALUE],
      _unused1: [128, self.VALUE],
      _unused2: [192, self.VALUE],
      ic_cref: [256, CType::Pointer.new { self.rb_cref_t }],
    )
  end

  def C.iseq_inline_iv_cache_entry
    @iseq_inline_iv_cache_entry ||= CType::Struct.new(
      "iseq_inline_iv_cache_entry", 8,
      entry: [0, CType::Pointer.new { self.rb_iv_index_tbl_entry }],
    )
  end

  def C.iseq_inline_storage_entry
    @iseq_inline_storage_entry ||= CType::Union.new(
      "iseq_inline_storage_entry", 16,
      once: CType::Struct.new(
        "", 16,
        running_thread: [0, CType::Pointer.new { self.rb_thread_struct }],
        value: [64, self.VALUE],
      ),
      ic_cache: self.iseq_inline_constant_cache,
      iv_cache: self.iseq_inline_iv_cache_entry,
    )
  end

  def C.mjit_options
    @mjit_options ||= CType::Struct.new(
      "mjit_options", 40,
      on: [0, self._Bool],
      save_temps: [8, self._Bool],
      warnings: [16, self._Bool],
      debug: [24, self._Bool],
      debug_flags: [64, CType::Pointer.new { CType::Immediate.new(2) }],
      wait: [128, self._Bool],
      min_calls: [160, CType::Immediate.new(-4)],
      verbose: [192, CType::Immediate.new(4)],
      max_cache_size: [224, CType::Immediate.new(4)],
      pause: [256, self._Bool],
      custom: [264, self._Bool],
    )
  end

  def C.rb_builtin_function
    @rb_builtin_function ||= CType::Struct.new(
      "rb_builtin_function", 32,
      func_ptr: [0, CType::Pointer.new { CType::Immediate.new(0) }],
      argc: [64, CType::Immediate.new(4)],
      index: [96, CType::Immediate.new(4)],
      name: [128, CType::Pointer.new { CType::Immediate.new(2) }],
      compiler: [192, CType::Immediate.new(1)],
    )
  end

  def C.rb_call_data
    @rb_call_data ||= CType::Struct.new(
      "rb_call_data", 16,
      ci: [0, CType::Pointer.new { self.rb_callinfo }],
      cc: [64, CType::Pointer.new { self.rb_callcache }],
    )
  end

  def C.rb_callable_method_entry_struct
    @rb_callable_method_entry_struct ||= CType::Struct.new(
      "rb_callable_method_entry_struct", 40,
      flags: [0, self.VALUE],
      defined_class: [64, self.VALUE],
      def: [128, CType::Pointer.new { self.rb_method_definition_struct }],
      called_id: [192, self.ID],
      owner: [256, self.VALUE],
    )
  end

  def C.rb_callcache
    @rb_callcache ||= CType::Struct.new(
      "rb_callcache", 40,
      flags: [0, self.VALUE],
      klass: [64, self.VALUE],
      cme_: [128, CType::Pointer.new { self.rb_callable_method_entry_struct }],
      call_: [192, self.vm_call_handler],
      aux_: [256, CType::Union.new(
        "", 8,
        attr_index: CType::Immediate.new(-4),
        method_missing_reason: self.method_missing_reason,
        v: self.VALUE,
      )],
    )
  end

  def C.rb_callinfo
    @rb_callinfo ||= CType::Struct.new(
      "rb_callinfo", 40,
      flags: [0, self.VALUE],
      kwarg: [64, CType::Pointer.new { self.rb_callinfo_kwarg }],
      mid: [128, self.VALUE],
      flag: [192, self.VALUE],
      argc: [256, self.VALUE],
    )
  end

  def C.rb_control_frame_t
    @rb_control_frame_t ||= CType::Struct.new(
      "rb_control_frame_struct", 64,
      pc: [0, CType::Pointer.new { self.VALUE }],
      sp: [64, CType::Pointer.new { self.VALUE }],
      iseq: [128, CType::Pointer.new { self.rb_iseq_t }],
      self: [192, self.VALUE],
      ep: [256, CType::Pointer.new { self.VALUE }],
      block_code: [320, CType::Pointer.new { CType::Immediate.new(0) }],
      __bp__: [384, CType::Pointer.new { self.VALUE }],
      jit_return: [448, CType::Pointer.new { CType::Immediate.new(0) }],
    )
  end

  def C.rb_cref_t
    @rb_cref_t ||= CType::Struct.new(
      "rb_cref_struct", 40,
      flags: [0, self.VALUE],
      refinements: [64, self.VALUE],
      klass_or_self: [128, self.VALUE],
      next: [192, CType::Pointer.new { self.rb_cref_struct }],
      scope_visi: [256, self.rb_scope_visibility_t],
    )
  end

  def C.rb_execution_context_struct
    @rb_execution_context_struct ||= CType::Struct.new(
      "rb_execution_context_struct", 368,
      vm_stack: [0, CType::Pointer.new { self.VALUE }],
      vm_stack_size: [64, CType::Immediate.new(-5)],
      cfp: [128, CType::Pointer.new { self.rb_control_frame_t }],
      tag: [192, CType::Pointer.new { self.rb_vm_tag }],
      interrupt_flag: [256, self.rb_atomic_t],
      interrupt_mask: [288, self.rb_atomic_t],
      fiber_ptr: [320, CType::Pointer.new { self.rb_fiber_t }],
      thread_ptr: [384, CType::Pointer.new { self.rb_thread_struct }],
      local_storage: [448, CType::Pointer.new { self.rb_id_table }],
      local_storage_recursive_hash: [512, self.VALUE],
      local_storage_recursive_hash_for_trace: [576, self.VALUE],
      root_lep: [640, CType::Pointer.new { self.VALUE }],
      root_svar: [704, self.VALUE],
      ensure_list: [768, CType::Pointer.new { self.rb_ensure_list_t }],
      trace_arg: [832, CType::Pointer.new { self.rb_trace_arg_struct }],
      errinfo: [896, self.VALUE],
      passed_block_handler: [960, self.VALUE],
      raised_flag: [1024, CType::Immediate.new(-2)],
      method_missing_reason: [1032, self.method_missing_reason],
      private_const_reference: [1088, self.VALUE],
      machine: [1152, CType::Struct.new(
        "", 224,
        stack_start: [0, CType::Pointer.new { self.VALUE }],
        stack_end: [64, CType::Pointer.new { self.VALUE }],
        stack_maxsize: [128, CType::Immediate.new(-5)],
        regs: [192, self.jmp_buf],
      )],
    )
  end

  def C.rb_execution_context_t
    @rb_execution_context_t ||= self.rb_execution_context_struct
  end

  def C.rb_iseq_constant_body
    @rb_iseq_constant_body ||= CType::Struct.new(
      "rb_iseq_constant_body", 336,
      type: [0, self.rb_iseq_type],
      iseq_size: [32, CType::Immediate.new(-4)],
      iseq_encoded: [64, CType::Pointer.new { self.VALUE }],
      param: [128, CType::Struct.new(
        "", 48,
        flags: [0, CType::Struct.new(
          "", 4,
          has_lead: [0, CType::BitField.new(1, 0)],
          has_opt: [1, CType::BitField.new(1, 1)],
          has_rest: [2, CType::BitField.new(1, 2)],
          has_post: [3, CType::BitField.new(1, 3)],
          has_kw: [4, CType::BitField.new(1, 4)],
          has_kwrest: [5, CType::BitField.new(1, 5)],
          has_block: [6, CType::BitField.new(1, 6)],
          ambiguous_param0: [7, CType::BitField.new(1, 7)],
          accepts_no_kwarg: [8, CType::BitField.new(1, 0)],
          ruby2_keywords: [9, CType::BitField.new(1, 1)],
        )],
        size: [32, CType::Immediate.new(-4)],
        lead_num: [64, CType::Immediate.new(4)],
        opt_num: [96, CType::Immediate.new(4)],
        rest_start: [128, CType::Immediate.new(4)],
        post_start: [160, CType::Immediate.new(4)],
        post_num: [192, CType::Immediate.new(4)],
        block_start: [224, CType::Immediate.new(4)],
        opt_table: [256, CType::Pointer.new { self.VALUE }],
        keyword: [320, CType::Pointer.new { self.rb_iseq_param_keyword }],
      )],
      location: [512, self.rb_iseq_location_t],
      insns_info: [960, self.iseq_insn_info],
      local_table: [1216, CType::Pointer.new { self.ID }],
      catch_table: [1280, CType::Pointer.new { self.iseq_catch_table }],
      parent_iseq: [1344, CType::Pointer.new { self.rb_iseq_struct }],
      local_iseq: [1408, CType::Pointer.new { self.rb_iseq_struct }],
      is_entries: [1472, CType::Pointer.new { self.iseq_inline_storage_entry }],
      call_data: [1536, CType::Pointer.new { self.rb_call_data }],
      variable: [1600, CType::Struct.new(
        "", 40,
        flip_count: [0, self.rb_snum_t],
        script_lines: [64, self.VALUE],
        coverage: [128, self.VALUE],
        pc2branchindex: [192, self.VALUE],
        original_iseq: [256, CType::Pointer.new { self.VALUE }],
      )],
      local_table_size: [1920, CType::Immediate.new(-4)],
      ic_size: [1952, CType::Immediate.new(-4)],
      ise_size: [1984, CType::Immediate.new(-4)],
      ivc_size: [2016, CType::Immediate.new(-4)],
      icvarc_size: [2048, CType::Immediate.new(-4)],
      ci_size: [2080, CType::Immediate.new(-4)],
      stack_max: [2112, CType::Immediate.new(-4)],
      mark_bits: [2176, CType::Union.new(
        "", 8,
        list: CType::Pointer.new { self.iseq_bits_t },
        single: self.iseq_bits_t,
      )],
      catch_except_p: [2240, self._Bool],
      builtin_inline_p: [2248, self._Bool],
      outer_variables: [2304, CType::Pointer.new { self.rb_id_table }],
      mandatory_only_iseq: [2368, CType::Pointer.new { self.rb_iseq_t }],
      jit_func: [2432, CType::Immediate.new(1)],
      total_calls: [2496, CType::Immediate.new(-5)],
      jit_unit: [2560, CType::Pointer.new { self.rb_mjit_unit }],
      yjit_payload: [2624, CType::Pointer.new { CType::Immediate.new(0) }],
    )
  end

  def C.rb_iseq_location_t
    @rb_iseq_location_t ||= CType::Struct.new(
      "rb_iseq_location_struct", 56,
      pathobj: [0, self.VALUE, true],
      base_label: [64, self.VALUE, true],
      label: [128, self.VALUE, true],
      first_lineno: [192, self.VALUE, true],
      node_id: [256, CType::Immediate.new(4)],
      code_location: [288, self.rb_code_location_t],
    )
  end

  def C.rb_iseq_struct
    @rb_iseq_struct ||= CType::Struct.new(
      "rb_iseq_struct", 40,
      flags: [0, self.VALUE],
      wrapper: [64, self.VALUE],
      body: [128, CType::Pointer.new { self.rb_iseq_constant_body }],
      aux: [192, CType::Union.new(
        "", 16,
        compile_data: CType::Pointer.new { self.iseq_compile_data },
        loader: CType::Struct.new(
          "", 16,
          obj: [0, self.VALUE],
          index: [64, CType::Immediate.new(4)],
        ),
        exec: CType::Struct.new(
          "", 16,
          local_hooks: [0, CType::Pointer.new { self.rb_hook_list_struct }],
          global_trace_events: [64, self.rb_event_flag_t],
        ),
      )],
    )
  end

  def C.rb_iseq_t
    @rb_iseq_t ||= self.rb_iseq_struct
  end

  def C.rb_iv_index_tbl_entry
    @rb_iv_index_tbl_entry ||= CType::Struct.new(
      "rb_iv_index_tbl_entry", 24,
      index: [0, CType::Immediate.new(-4)],
      class_serial: [64, self.rb_serial_t],
      class_value: [128, self.VALUE],
    )
  end

  def C.rb_method_definition_struct
    @rb_method_definition_struct ||= CType::Struct.new(
      "rb_method_definition_struct", 48,
      type: [0, self.rb_method_type_t],
      iseq_overload: [4, CType::BitField.new(1, 4)],
      alias_count: [5, CType::BitField.new(27, 5)],
      complemented_count: [32, CType::BitField.new(28, 0)],
      no_redef_warning: [60, CType::BitField.new(1, 4)],
      body: [64, CType::Union.new(
        "", 24,
        iseq: self.rb_method_iseq_t,
        cfunc: self.rb_method_cfunc_t,
        attr: self.rb_method_attr_t,
        alias: self.rb_method_alias_t,
        refined: self.rb_method_refined_t,
        bmethod: self.rb_method_bmethod_t,
        optimized: self.rb_method_optimized_t,
      )],
      original_id: [256, self.ID],
      method_serial: [320, CType::Immediate.new(-5)],
    )
  end

  def C.rb_method_iseq_t
    @rb_method_iseq_t ||= CType::Struct.new(
      "rb_method_iseq_struct", 16,
      iseqptr: [0, CType::Pointer.new { self.rb_iseq_t }],
      cref: [64, CType::Pointer.new { self.rb_cref_t }],
    )
  end

  def C.rb_method_type_t
    @rb_method_type_t ||= CType::Immediate.new(4)
  end

  def C.rb_mjit_compile_info
    @rb_mjit_compile_info ||= CType::Struct.new(
      "rb_mjit_compile_info", 5,
      disable_ivar_cache: [0, self._Bool],
      disable_exivar_cache: [8, self._Bool],
      disable_send_cache: [16, self._Bool],
      disable_inlining: [24, self._Bool],
      disable_const_cache: [32, self._Bool],
    )
  end

  def C.rb_mjit_unit
    @rb_mjit_unit ||= CType::Struct.new(
      "rb_mjit_unit", 64,
      unode: [0, self.ccan_list_node],
      id: [128, CType::Immediate.new(4)],
      handle: [192, CType::Pointer.new { CType::Immediate.new(0) }],
      iseq: [256, CType::Pointer.new { self.rb_iseq_t }],
      used_code_p: [320, self._Bool],
      compact_p: [328, self._Bool],
      compile_info: [336, self.rb_mjit_compile_info],
      cc_entries: [384, CType::Pointer.new { CType::Pointer.new { self.rb_callcache } }],
      cc_entries_size: [448, CType::Immediate.new(-4)],
    )
  end

  def C.rb_serial_t
    @rb_serial_t ||= CType::Immediate.new(-6)
  end

  def C._Bool = CType::Bool.new

  def C.ID = CType::Stub.new(:ID)

  def C.rb_thread_struct = CType::Stub.new(:rb_thread_struct)

  def C.vm_call_handler = CType::Stub.new(:vm_call_handler)

  def C.method_missing_reason = CType::Stub.new(:method_missing_reason)

  def C.rb_callinfo_kwarg = CType::Stub.new(:rb_callinfo_kwarg)

  def C.rb_cref_struct = CType::Stub.new(:rb_cref_struct)

  def C.rb_scope_visibility_t = CType::Stub.new(:rb_scope_visibility_t)

  def C.rb_vm_tag = CType::Stub.new(:rb_vm_tag)

  def C.rb_atomic_t = CType::Stub.new(:rb_atomic_t)

  def C.rb_fiber_t = CType::Stub.new(:rb_fiber_t)

  def C.rb_id_table = CType::Stub.new(:rb_id_table)

  def C.rb_ensure_list_t = CType::Stub.new(:rb_ensure_list_t)

  def C.rb_trace_arg_struct = CType::Stub.new(:rb_trace_arg_struct)

  def C.jmp_buf = CType::Stub.new(:jmp_buf)

  def C.rb_iseq_type = CType::Stub.new(:rb_iseq_type)

  def C.rb_iseq_param_keyword = CType::Stub.new(:rb_iseq_param_keyword)

  def C.iseq_insn_info = CType::Stub.new(:iseq_insn_info)

  def C.iseq_catch_table = CType::Stub.new(:iseq_catch_table)

  def C.rb_snum_t = CType::Stub.new(:rb_snum_t)

  def C.iseq_bits_t = CType::Stub.new(:iseq_bits_t)

  def C.rb_code_location_t = CType::Stub.new(:rb_code_location_t)

  def C.iseq_compile_data = CType::Stub.new(:iseq_compile_data)

  def C.rb_hook_list_struct = CType::Stub.new(:rb_hook_list_struct)

  def C.rb_event_flag_t = CType::Stub.new(:rb_event_flag_t)

  def C.rb_method_cfunc_t = CType::Stub.new(:rb_method_cfunc_t)

  def C.rb_method_attr_t = CType::Stub.new(:rb_method_attr_t)

  def C.rb_method_alias_t = CType::Stub.new(:rb_method_alias_t)

  def C.rb_method_refined_t = CType::Stub.new(:rb_method_refined_t)

  def C.rb_method_bmethod_t = CType::Stub.new(:rb_method_bmethod_t)

  def C.rb_method_optimized_t = CType::Stub.new(:rb_method_optimized_t)

  def C.ccan_list_node = CType::Stub.new(:ccan_list_node)
end
