require_relative 'c_type'

module RubyVM::MJIT
  C = Object.new

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
      "compile_status", 68,
      success: [0, self._Bool],
      stack_size_for_pos: [32, CType::Pointer.new { CType::Immediate.new(4) }],
      local_stack_p: [64, self._Bool],
      is_entries: [96, CType::Pointer.new { self.iseq_inline_storage_entry }],
      cc_entries_index: [128, CType::Immediate.new(4)],
      compiled_iseq: [160, CType::Pointer.new { self.rb_iseq_constant_body }],
      compiled_id: [192, CType::Immediate.new(4)],
      compile_info: [224, CType::Pointer.new { self.rb_mjit_compile_info }],
      merge_ivar_guards_p: [256, self._Bool],
      ivar_serial: [288, self.rb_serial_t],
      max_ivar_index: [352, CType::Immediate.new(-4)],
      inlined_iseqs: [384, CType::Pointer.new { CType::Pointer.new { self.rb_iseq_constant_body } }],
      inline_context: [416, self.inlined_call_context],
    )
  end

  def C.inlined_call_context
    @inlined_call_context ||= CType::Struct.new(
      "inlined_call_context", 16,
      orig_argc: [0, CType::Immediate.new(4)],
      me: [32, self.VALUE],
      param_size: [64, CType::Immediate.new(4)],
      local_size: [96, CType::Immediate.new(4)],
    )
  end

  def C.iseq_inline_constant_cache
    @iseq_inline_constant_cache ||= CType::Struct.new(
      "iseq_inline_constant_cache", 8,
      entry: [0, CType::Pointer.new { self.iseq_inline_constant_cache_entry }],
      segments: [32, CType::Pointer.new { self.ID }],
    )
  end

  def C.iseq_inline_constant_cache_entry
    @iseq_inline_constant_cache_entry ||= CType::Struct.new(
      "iseq_inline_constant_cache_entry", 20,
      flags: [0, self.VALUE],
      value: [32, self.VALUE],
      _unused1: [64, self.VALUE],
      _unused2: [96, self.VALUE],
      ic_cref: [128, CType::Pointer.new { self.rb_cref_t }],
    )
  end

  def C.iseq_inline_iv_cache_entry
    @iseq_inline_iv_cache_entry ||= CType::Struct.new(
      "iseq_inline_iv_cache_entry", 4,
      entry: [0, CType::Pointer.new { self.rb_iv_index_tbl_entry }],
    )
  end

  def C.iseq_inline_storage_entry
    @iseq_inline_storage_entry ||= CType::Union.new(
      "iseq_inline_storage_entry", 8,
      once: CType::Struct.new(
        "", 8,
        running_thread: [0, CType::Pointer.new { self.rb_thread_struct }],
        value: [32, self.VALUE],
      ),
      ic_cache: self.iseq_inline_constant_cache,
      iv_cache: self.iseq_inline_iv_cache_entry,
    )
  end

  def C.mjit_options
    @mjit_options ||= CType::Struct.new(
      "mjit_options", 28,
      on: [0, self._Bool],
      save_temps: [8, self._Bool],
      warnings: [16, self._Bool],
      debug: [24, self._Bool],
      debug_flags: [32, CType::Pointer.new { CType::Immediate.new(2) }],
      wait: [64, self._Bool],
      min_calls: [96, CType::Immediate.new(-4)],
      verbose: [128, CType::Immediate.new(4)],
      max_cache_size: [160, CType::Immediate.new(4)],
      pause: [192, self._Bool],
      custom: [200, self._Bool],
    )
  end

  def C.rb_builtin_function
    @rb_builtin_function ||= CType::Struct.new(
      "rb_builtin_function", 20,
      func_ptr: [0, CType::Pointer.new { CType::Immediate.new(0) }],
      argc: [32, CType::Immediate.new(4)],
      index: [64, CType::Immediate.new(4)],
      name: [96, CType::Pointer.new { CType::Immediate.new(2) }],
      compiler: [128, CType::Immediate.new(1)],
    )
  end

  def C.rb_call_data
    @rb_call_data ||= CType::Struct.new(
      "rb_call_data", 8,
      ci: [0, CType::Pointer.new { self.rb_callinfo }],
      cc: [32, CType::Pointer.new { self.rb_callcache }],
    )
  end

  def C.rb_callable_method_entry_struct
    @rb_callable_method_entry_struct ||= CType::Struct.new(
      "rb_callable_method_entry_struct", 20,
      flags: [0, self.VALUE],
      defined_class: [32, self.VALUE],
      def: [64, CType::Pointer.new { self.rb_method_definition_struct }],
      called_id: [96, self.ID],
      owner: [128, self.VALUE],
    )
  end

  def C.rb_callcache
    @rb_callcache ||= CType::Struct.new(
      "rb_callcache", 20,
      flags: [0, self.VALUE],
      klass: [32, self.VALUE],
      cme_: [64, CType::Pointer.new { self.rb_callable_method_entry_struct }],
      call_: [96, self.vm_call_handler],
      aux_: [128, CType::Union.new(
        "", 4,
        attr_index: CType::Immediate.new(-4),
        method_missing_reason: self.method_missing_reason,
        v: self.VALUE,
      )],
    )
  end

  def C.rb_callinfo
    @rb_callinfo ||= CType::Struct.new(
      "rb_callinfo", 20,
      flags: [0, self.VALUE],
      kwarg: [32, CType::Pointer.new { self.rb_callinfo_kwarg }],
      mid: [64, self.VALUE],
      flag: [96, self.VALUE],
      argc: [128, self.VALUE],
    )
  end

  def C.rb_cref_t
    @rb_cref_t ||= CType::Struct.new(
      "rb_cref_struct", 20,
      flags: [0, self.VALUE],
      refinements: [32, self.VALUE],
      klass_or_self: [64, self.VALUE],
      next: [96, CType::Pointer.new { self.rb_cref_struct }],
      scope_visi: [128, self.rb_scope_visibility_t],
    )
  end

  def C.rb_iseq_constant_body
    @rb_iseq_constant_body ||= CType::Struct.new(
      "rb_iseq_constant_body", 204,
      type: [0, self.rb_iseq_type],
      iseq_size: [32, CType::Immediate.new(-4)],
      iseq_encoded: [64, CType::Pointer.new { self.VALUE }],
      param: [96, CType::Struct.new(
        "", 40,
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
        keyword: [288, CType::Pointer.new { self.rb_iseq_param_keyword }],
      )],
      location: [416, self.rb_iseq_location_t],
      insns_info: [704, self.iseq_insn_info],
      local_table: [832, CType::Pointer.new { self.ID }],
      catch_table: [864, CType::Pointer.new { self.iseq_catch_table }],
      parent_iseq: [896, CType::Pointer.new { self.rb_iseq_struct }],
      local_iseq: [928, CType::Pointer.new { self.rb_iseq_struct }],
      is_entries: [960, CType::Pointer.new { self.iseq_inline_storage_entry }],
      call_data: [992, CType::Pointer.new { self.rb_call_data }],
      variable: [1024, CType::Struct.new(
        "", 20,
        flip_count: [0, self.rb_snum_t],
        script_lines: [32, self.VALUE],
        coverage: [64, self.VALUE],
        pc2branchindex: [96, self.VALUE],
        original_iseq: [128, CType::Pointer.new { self.VALUE }],
      )],
      local_table_size: [1184, CType::Immediate.new(-4)],
      ic_size: [1216, CType::Immediate.new(-4)],
      ise_size: [1248, CType::Immediate.new(-4)],
      ivc_size: [1280, CType::Immediate.new(-4)],
      icvarc_size: [1312, CType::Immediate.new(-4)],
      ci_size: [1344, CType::Immediate.new(-4)],
      stack_max: [1376, CType::Immediate.new(-4)],
      mark_bits: [1408, CType::Union.new(
        "", 4,
        list: CType::Pointer.new { self.iseq_bits_t },
        single: self.iseq_bits_t,
      )],
      catch_except_p: [1440, self._Bool],
      builtin_inline_p: [1448, self._Bool],
      outer_variables: [1472, CType::Pointer.new { self.rb_id_table }],
      mandatory_only_iseq: [1504, CType::Pointer.new { self.rb_iseq_t }],
      jit_func: [1536, CType::Immediate.new(1)],
      total_calls: [1568, CType::Immediate.new(-5)],
      jit_unit: [1600, CType::Pointer.new { self.rb_mjit_unit }],
    )
  end

  def C.rb_iseq_location_t
    @rb_iseq_location_t ||= CType::Struct.new(
      "rb_iseq_location_struct", 36,
      pathobj: [0, self.VALUE, true],
      base_label: [32, self.VALUE, true],
      label: [64, self.VALUE, true],
      first_lineno: [96, self.VALUE, true],
      node_id: [128, CType::Immediate.new(4)],
      code_location: [160, self.rb_code_location_t],
    )
  end

  def C.rb_iseq_struct
    @rb_iseq_struct ||= CType::Struct.new(
      "rb_iseq_struct", 20,
      flags: [0, self.VALUE],
      wrapper: [32, self.VALUE],
      body: [64, CType::Pointer.new { self.rb_iseq_constant_body }],
      aux: [96, CType::Union.new(
        "", 8,
        compile_data: CType::Pointer.new { self.iseq_compile_data },
        loader: CType::Struct.new(
          "", 8,
          obj: [0, self.VALUE],
          index: [32, CType::Immediate.new(4)],
        ),
        exec: CType::Struct.new(
          "", 8,
          local_hooks: [0, CType::Pointer.new { self.rb_hook_list_struct }],
          global_trace_events: [32, self.rb_event_flag_t],
        ),
      )],
    )
  end

  def C.rb_iseq_t
    @rb_iseq_t ||= self.rb_iseq_struct
  end

  def C.rb_iv_index_tbl_entry
    @rb_iv_index_tbl_entry ||= CType::Struct.new(
      "rb_iv_index_tbl_entry", 16,
      index: [0, CType::Immediate.new(-4)],
      class_serial: [32, self.rb_serial_t],
      class_value: [96, self.VALUE],
    )
  end

  def C.rb_method_definition_struct
    @rb_method_definition_struct ||= CType::Struct.new(
      "rb_method_definition_struct", 28,
      type: [0, self.rb_method_type_t],
      iseq_overload: [4, CType::BitField.new(1, 4)],
      alias_count: [5, CType::BitField.new(27, 5)],
      complemented_count: [32, CType::BitField.new(28, 0)],
      no_redef_warning: [60, CType::BitField.new(1, 4)],
      body: [64, CType::Union.new(
        "", 12,
        iseq: self.rb_method_iseq_t,
        cfunc: self.rb_method_cfunc_t,
        attr: self.rb_method_attr_t,
        alias: self.rb_method_alias_t,
        refined: self.rb_method_refined_t,
        bmethod: self.rb_method_bmethod_t,
        optimized: self.rb_method_optimized_t,
      )],
      original_id: [160, self.ID],
      method_serial: [192, CType::Immediate.new(-4)],
    )
  end

  def C.rb_method_iseq_t
    @rb_method_iseq_t ||= CType::Struct.new(
      "rb_method_iseq_struct", 8,
      iseqptr: [0, CType::Pointer.new { self.rb_iseq_t }],
      cref: [32, CType::Pointer.new { self.rb_cref_t }],
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
      "rb_mjit_unit", 36,
      unode: [0, self.ccan_list_node],
      id: [64, CType::Immediate.new(4)],
      handle: [96, CType::Pointer.new { CType::Immediate.new(0) }],
      iseq: [128, CType::Pointer.new { self.rb_iseq_t }],
      used_code_p: [160, self._Bool],
      compact_p: [168, self._Bool],
      compile_info: [176, self.rb_mjit_compile_info],
      cc_entries: [224, CType::Pointer.new { CType::Pointer.new { self.rb_callcache } }],
      cc_entries_size: [256, CType::Immediate.new(-4)],
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

  def C.rb_iseq_type = CType::Stub.new(:rb_iseq_type)

  def C.rb_iseq_param_keyword = CType::Stub.new(:rb_iseq_param_keyword)

  def C.iseq_insn_info = CType::Stub.new(:iseq_insn_info)

  def C.iseq_catch_table = CType::Stub.new(:iseq_catch_table)

  def C.rb_snum_t = CType::Stub.new(:rb_snum_t)

  def C.iseq_bits_t = CType::Stub.new(:iseq_bits_t)

  def C.rb_id_table = CType::Stub.new(:rb_id_table)

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
