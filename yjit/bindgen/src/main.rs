//! See https://docs.rs/bindgen/0.59.2/bindgen/struct.Builder.html
//! This is the binding generation tool that the YJIT cruby module talks about.
//! More docs later once we have more experience with this, for now, check
//! the output to make sure it looks reasonable and allowlist things you want
//! to use in Rust.

use std::env;
use std::path::PathBuf;

const SRC_ROOT_ENV: &str = "YJIT_SRC_ROOT_PATH";

fn main() {
    // Path to repo is a required input for supporting running `configure`
    // in a directory away from the code.
    let src_root = env::var(SRC_ROOT_ENV).expect(
        format!(
            r#"The "{}" env var must be a path to the root of the Ruby repo"#,
            SRC_ROOT_ENV
        )
        .as_ref(),
    );
    let src_root = PathBuf::from(src_root);

    assert!(
        src_root.is_dir(),
        "{} must be set to a path to a directory",
        SRC_ROOT_ENV
    );

    // We want Bindgen warnings printed to console
    env_logger::init();

    // Remove this flag so rust-bindgen generates bindings
    // that are internal functions not public in libruby
    let filtered_clang_args = env::args().filter(|arg| arg != "-fvisibility=hidden");

    let bindings = bindgen::builder()
        .clang_args(filtered_clang_args)
        .header("encindex.h")
        .header("internal.h")
        .header("internal/re.h")
        .header("include/ruby/ruby.h")
        .header("shape.h")
        .header("vm_core.h")
        .header("vm_callinfo.h")

        // Our C file for glue code
        .header(src_root.join("yjit.c").to_str().unwrap())

        // Don't want to copy over C comment
        .generate_comments(false)

        // Makes the output more compact
        .merge_extern_blocks(true)

        // Don't want layout tests as they are platform dependent
        .layout_tests(false)

        // Block for stability since output is different on Darwin and Linux
        .blocklist_type("size_t")
        .blocklist_type("fpos_t")

        // Prune these types since they are system dependant and we don't use them
        .blocklist_type("__.*")

        // Import YARV bytecode instruction constants
        .allowlist_type("ruby_vminsn_type")

        // From include/ruby/internal/special_consts.h
        .allowlist_type("ruby_special_consts")

        // From include/ruby/internal/intern/string.h
        .allowlist_function("rb_utf8_str_new")
        .allowlist_function("rb_str_buf_append")
        .allowlist_function("rb_str_dup")

        // From encindex.h
        .allowlist_type("ruby_preserved_encindex")

        // This struct is public to Ruby C extensions
        // From include/ruby/internal/core/rbasic.h
        .allowlist_type("RBasic")

        // From internal.h
        // This function prints info about a value and is useful for debugging
        .allowlist_function("rb_obj_info_dump")

        // From shape.h
        .allowlist_function("rb_shape_get_shape_id")
        .allowlist_function("rb_shape_get_shape_by_id")
        .allowlist_function("rb_shape_id_offset")
        .allowlist_function("rb_shape_get_iv_index")
        .allowlist_function("rb_shape_get_next")
        .allowlist_function("rb_shape_id")
        .allowlist_function("rb_shape_transition_shape_capa")
        .allowlist_function("rb_shape_obj_too_complex")
        .allowlist_var("SHAPE_ID_NUM_BITS")
        .allowlist_var("OBJ_TOO_COMPLEX_SHAPE_ID")

        // From ruby/internal/intern/object.h
        .allowlist_function("rb_obj_is_kind_of")
        .allowlist_function("rb_obj_frozen_p")

        // From ruby/internal/encoding/encoding.h
        .allowlist_type("ruby_encoding_consts")

        // From include/hash.h
        .allowlist_function("rb_hash_new")

        // From internal/hash.h
        .allowlist_function("rb_hash_new_with_size")
        .allowlist_function("rb_hash_resurrect")
        .allowlist_function("rb_hash_stlike_foreach")

        // From include/ruby/st.h
        .allowlist_type("st_retval")

        // From include/ruby/internal/intern/hash.h
        .allowlist_function("rb_hash_aset")
        .allowlist_function("rb_hash_aref")
        .allowlist_function("rb_hash_bulk_insert")
        .allowlist_function("rb_hash_stlike_lookup")

        // From include/ruby/internal/intern/array.h
        .allowlist_function("rb_ary_new_capa")
        .allowlist_function("rb_ary_store")
        .allowlist_function("rb_ary_resurrect")
        .allowlist_function("rb_ary_clear")

        // From internal/array.h
        .allowlist_function("rb_ec_ary_new_from_values")
        .allowlist_function("rb_ary_tmp_new_from_values")

        // From include/ruby/internal/intern/class.h
        .allowlist_function("rb_singleton_class")

        // From include/ruby/internal/core/rclass.h
        .allowlist_function("rb_class_get_superclass")

        // From include/ruby/internal/intern/gc.h
        .allowlist_function("rb_gc_mark")
        .allowlist_function("rb_gc_mark_movable")
        .allowlist_function("rb_gc_location")
        .allowlist_function("rb_gc_writebarrier")

        // VALUE variables for Ruby class objects
        // From include/ruby/internal/globals.h
        .allowlist_var("rb_cBasicObject")
        .allowlist_var("rb_cModule")
        .allowlist_var("rb_cNilClass")
        .allowlist_var("rb_cTrueClass")
        .allowlist_var("rb_cFalseClass")
        .allowlist_var("rb_cInteger")
        .allowlist_var("rb_cSymbol")
        .allowlist_var("rb_cFloat")
        .allowlist_var("rb_cString")
        .allowlist_var("rb_cThread")
        .allowlist_var("rb_cArray")
        .allowlist_var("rb_cHash")

        // From include/ruby/internal/fl_type.h
        .allowlist_type("ruby_fl_type")
        .allowlist_type("ruby_fl_ushift")

        // From include/ruby/internal/core/robject.h
        .allowlist_type("ruby_robject_flags")
        // .allowlist_type("ruby_robject_consts") // Removed when USE_RVARGC
        .allowlist_var("ROBJECT_OFFSET_.*")

        // From include/ruby/internal/core/rarray.h
        .allowlist_type("ruby_rarray_flags")
        .allowlist_type("ruby_rarray_consts")

        // From include/ruby/internal/core/rclass.h
        .allowlist_type("ruby_rmodule_flags")

        // From ruby/internal/globals.h
        .allowlist_var("rb_mKernel")

        // From vm_callinfo.h
        .allowlist_type("vm_call_flag_bits")
        .allowlist_type("rb_call_data")
        .blocklist_type("rb_callcache.*")      // Not used yet - opaque to make it easy to import rb_call_data
        .opaque_type("rb_callcache.*")
        .blocklist_type("rb_callinfo_kwarg") // Contains a VALUE[] array of undefined size, so we don't import
        .opaque_type("rb_callinfo_kwarg")
        .allowlist_type("rb_callinfo")

        // From vm_insnhelper.h
        .allowlist_var("VM_ENV_DATA_INDEX_ME_CREF")
        .allowlist_var("rb_block_param_proxy")

        // From include/ruby/internal/intern/range.h
        .allowlist_function("rb_range_new")

        // From include/ruby/internal/symbol.h
        .allowlist_function("rb_intern")
        .allowlist_function("rb_id2sym")
        .allowlist_function("rb_sym2id")
        .allowlist_function("rb_str_intern")

        // From internal/string.h
        .allowlist_function("rb_ec_str_resurrect")
        .allowlist_function("rb_str_concat_literals")
        .allowlist_function("rb_obj_as_string_result")

        // From include/ruby/internal/intern/parse.h
        .allowlist_function("rb_backref_get")

        // From include/ruby/internal/intern/re.h
        .allowlist_function("rb_reg_last_match")
        .allowlist_function("rb_reg_match_pre")
        .allowlist_function("rb_reg_match_post")
        .allowlist_function("rb_reg_match_last")
        .allowlist_function("rb_reg_nth_match")

        // From internal/re.h
        .allowlist_function("rb_reg_new_ary")

        // `ruby_value_type` is a C enum and this stops it from
        // prefixing all the members with the name of the type
        .prepend_enum_name(false)
        .translate_enum_integer_types(true) // so we get fixed width Rust types for members
        // From include/ruby/internal/value_type.h
        .allowlist_type("ruby_value_type") // really old C extension API

        // Autogenerated into id.h
        .allowlist_type("ruby_method_ids")

        // From method.h
        .allowlist_type("rb_method_visibility_t")
        .allowlist_type("rb_method_type_t")
        .allowlist_type("method_optimized_type")
        .allowlist_type("rb_callable_method_entry_t")
        .allowlist_type("rb_callable_method_entry_struct")
        .allowlist_function("rb_method_entry_at")
        .allowlist_type("rb_method_entry_t")
        .blocklist_type("rb_method_cfunc_t")
        .blocklist_type("rb_method_definition_.*") // Large struct with a bitfield and union of many types - don't import (yet?)
        .opaque_type("rb_method_definition_.*")

        // From vm_core.h
        .allowlist_var("rb_mRubyVMFrozenCore")
        .allowlist_var("VM_BLOCK_HANDLER_NONE")
        .allowlist_type("vm_frame_env_flags")
        .allowlist_type("rb_seq_param_keyword_struct")
        .allowlist_type("ruby_basic_operators")
        .allowlist_var(".*_REDEFINED_OP_FLAG")
        .allowlist_type("rb_num_t")
        .allowlist_function("rb_callable_method_entry")
        .allowlist_function("rb_callable_method_entry_or_negative")
        .allowlist_function("rb_vm_frame_method_entry")
        .allowlist_type("IVC") // pointer to iseq_inline_iv_cache_entry
        .allowlist_type("IC")  // pointer to iseq_inline_constant_cache
        .allowlist_type("iseq_inline_constant_cache_entry")
        .blocklist_type("rb_cref_t")         // don't need this directly, opaqued to allow IC import
        .opaque_type("rb_cref_t")
        .allowlist_type("iseq_inline_iv_cache_entry")
        .allowlist_type("ICVARC") // pointer to iseq_inline_cvar_cache_entry
        .allowlist_type("iseq_inline_cvar_cache_entry")
        .blocklist_type("rb_execution_context_.*") // Large struct with various-type fields and an ifdef, so we don't import
        .opaque_type("rb_execution_context_.*")
        .blocklist_type("rb_control_frame_struct")
        .opaque_type("rb_control_frame_struct")
        .allowlist_function("rb_vm_bh_to_procval")
        .allowlist_function("rb_vm_ep_local_ep")
        .allowlist_type("vm_special_object_type")
        .allowlist_var("VM_ENV_DATA_INDEX_SPECVAL")
        .allowlist_var("VM_ENV_DATA_INDEX_FLAGS")
        .allowlist_var("VM_ENV_DATA_SIZE")
        .allowlist_function("rb_iseq_path")

        // From yjit.c
        .allowlist_function("rb_iseq_(get|set)_yjit_payload")
        .allowlist_function("rb_iseq_pc_at_idx")
        .allowlist_function("rb_iseq_opcode_at_pc")
        .allowlist_function("rb_yjit_reserve_addr_space")
        .allowlist_function("rb_yjit_mark_writable")
        .allowlist_function("rb_yjit_mark_executable")
        .allowlist_function("rb_yjit_mark_unused")
        .allowlist_function("rb_yjit_get_page_size")
        .allowlist_function("rb_leaf_invokebuiltin_iseq_p")
        .allowlist_function("rb_leaf_builtin_function")
        .allowlist_function("rb_set_cfp_(pc|sp)")
        .allowlist_function("rb_cfp_get_iseq")
        .allowlist_function("rb_yjit_multi_ractor_p")
        .allowlist_function("rb_c_method_tracing_currently_enabled")
        .allowlist_function("rb_full_cfunc_return")
        .allowlist_function("rb_yjit_vm_lock_then_barrier")
        .allowlist_function("rb_yjit_vm_unlock")
        .allowlist_function("rb_assert_(iseq|cme)_handle")
        .allowlist_function("rb_IMEMO_TYPE_P")
        .allowlist_function("rb_iseq_reset_jit_func")
        .allowlist_function("rb_yjit_dump_iseq_loc")
        .allowlist_function("rb_yjit_for_each_iseq")
        .allowlist_function("rb_yjit_obj_written")
        .allowlist_function("rb_yjit_str_simple_append")
        .allowlist_function("rb_RSTRING_PTR")
        .allowlist_function("rb_RSTRING_LEN")
        .allowlist_function("rb_ENCODING_GET")
        .allowlist_function("rb_yjit_get_proc_ptr")
        .allowlist_function("rb_yjit_exit_locations_dict")
        .allowlist_function("rb_yjit_icache_invalidate")
        .allowlist_function("rb_optimized_call")
        // from vm_sync.h
        .allowlist_function("rb_vm_barrier")

        // Not sure why it's picking these up, but don't.
        .blocklist_type("FILE")
        .blocklist_type("_IO_.*")

        // From internal/compile.h
        .allowlist_function("rb_vm_insn_decode")

        // from internal/cont.h
        .allowlist_function("rb_jit_cont_each_iseq")

        // From iseq.h
        .allowlist_function("rb_vm_insn_addr2opcode")
        .allowlist_function("rb_iseqw_to_iseq")
        .allowlist_function("rb_iseq_method_name")

        // From builtin.h
        .allowlist_type("rb_builtin_function.*")

        // From internal/variable.h
        .allowlist_function("rb_gvar_(get|set)")
        .allowlist_function("rb_ensure_iv_list_size")

        // From include/ruby/internal/intern/variable.h
        .allowlist_function("rb_attr_get")
        .allowlist_function("rb_ivar_get")

        // From include/ruby/internal/intern/vm.h
        .allowlist_function("rb_get_alloc_func")

        // From gc.h and internal/gc.h
        .allowlist_function("rb_class_allocate_instance")
        .allowlist_function("rb_obj_info")

        // From include/ruby/debug.h
        .allowlist_function("rb_profile_frames")

        // Functions used for code generation
        .allowlist_function("rb_insn_name")
        .allowlist_function("rb_insn_len")
        .allowlist_function("rb_yarv_class_of")
        .allowlist_function("rb_get_ec_cfp")
        .allowlist_function("rb_get_cfp_pc")
        .allowlist_function("rb_get_cfp_sp")
        .allowlist_function("rb_get_cfp_self")
        .allowlist_function("rb_get_cfp_ep")
        .allowlist_function("rb_get_cfp_ep_level")
        .allowlist_function("rb_get_cme_def_type")
        .allowlist_function("rb_get_cme_def_body_attr_id")
        .allowlist_function("rb_get_symbol_id")
        .allowlist_function("rb_get_cme_def_body_optimized_type")
        .allowlist_function("rb_get_cme_def_body_optimized_index")
        .allowlist_function("rb_get_cme_def_body_cfunc")
        .allowlist_function("rb_get_def_method_serial")
        .allowlist_function("rb_get_def_original_id")
        .allowlist_function("rb_get_mct_argc")
        .allowlist_function("rb_get_mct_func")
        .allowlist_function("rb_get_def_iseq_ptr")
        .allowlist_function("rb_get_def_bmethod_proc")
        .allowlist_function("rb_iseq_encoded_size")
        .allowlist_function("rb_get_iseq_body_local_iseq")
        .allowlist_function("rb_get_iseq_body_parent_iseq")
        .allowlist_function("rb_get_iseq_body_iseq_encoded")
        .allowlist_function("rb_get_iseq_body_stack_max")
        .allowlist_function("rb_get_iseq_flags_has_lead")
        .allowlist_function("rb_get_iseq_flags_has_opt")
        .allowlist_function("rb_get_iseq_flags_has_kw")
        .allowlist_function("rb_get_iseq_flags_has_rest")
        .allowlist_function("rb_get_iseq_flags_has_post")
        .allowlist_function("rb_get_iseq_flags_has_kwrest")
        .allowlist_function("rb_get_iseq_flags_has_block")
        .allowlist_function("rb_get_iseq_flags_ambiguous_param0")
        .allowlist_function("rb_get_iseq_flags_accepts_no_kwarg")
        .allowlist_function("rb_get_iseq_flags_ruby2_keywords")
        .allowlist_function("rb_get_iseq_body_local_table_size")
        .allowlist_function("rb_get_iseq_body_param_keyword")
        .allowlist_function("rb_get_iseq_body_param_size")
        .allowlist_function("rb_get_iseq_body_param_lead_num")
        .allowlist_function("rb_get_iseq_body_param_opt_num")
        .allowlist_function("rb_get_iseq_body_param_opt_table")
        .allowlist_function("rb_get_cikw_keyword_len")
        .allowlist_function("rb_get_cikw_keywords_idx")
        .allowlist_function("rb_get_call_data_ci")
        .allowlist_function("rb_yarv_str_eql_internal")
        .allowlist_function("rb_yarv_ary_entry_internal")
        .allowlist_function("rb_yarv_fix_mod_fix")
        .allowlist_function("rb_FL_TEST")
        .allowlist_function("rb_FL_TEST_RAW")
        .allowlist_function("rb_RB_TYPE_P")
        .allowlist_function("rb_BASIC_OP_UNREDEFINED_P")
        .allowlist_function("rb_RSTRUCT_LEN")
        .allowlist_function("rb_RSTRUCT_SET")
        .allowlist_function("rb_vm_ci_argc")
        .allowlist_function("rb_vm_ci_mid")
        .allowlist_function("rb_vm_ci_flag")
        .allowlist_function("rb_vm_ci_kwarg")
        .allowlist_function("rb_METHOD_ENTRY_VISI")
        .allowlist_function("rb_RCLASS_ORIGIN")
        .allowlist_function("rb_method_basic_definition_p")

        // We define VALUE manually, don't import it
        .blocklist_type("VALUE")

        // From iseq.h
        .opaque_type("rb_iseq_t")
        .blocklist_type("rb_iseq_t")

        // Finish the builder and generate the bindings.
        .generate()
        // Unwrap the Result and panic on failure.
        .expect("Unable to generate bindings");

    let mut out_path: PathBuf = src_root;
    out_path.push("yjit");
    out_path.push("src");
    out_path.push("cruby_bindings.inc.rs");

    bindings
        .write_to_file(out_path)
        .expect("Couldn't write bindings!");
}
