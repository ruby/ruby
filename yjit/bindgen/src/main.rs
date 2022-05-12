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

    // Remove this flag so rust-bindgen generates bindings
    // that are internal functions not public in libruby
    let filtered_clang_args = env::args().filter(|arg| arg != "-fvisibility=hidden");

    let bindings = bindgen::builder()
        .clang_args(filtered_clang_args)
        .header("encindex.h")
        .header("internal.h")
        .header("internal/re.h")
        .header("include/ruby/ruby.h")
        .header("vm_core.h")
        .header("vm_callinfo.h")

        // Our C file for glue code
        .header(src_root.join("yjit.c").to_str().unwrap())

        // Don't want to copy over C comment
        .generate_comments(false)

        // Don't want layout tests as they are platform dependent
        .layout_tests(false)

        // Block for stability since output is different on Darwin and Linux
        .blocklist_type("size_t")
        .blocklist_type("fpos_t")

        // Prune these types since they are system dependant and we don't use them
        .blocklist_type("__.*")

        // From include/ruby/internal/intern/string.h
        .allowlist_function("rb_utf8_str_new")
        .allowlist_function("rb_str_append")

        // This struct is public to Ruby C extensions
        // From include/ruby/internal/core/rbasic.h
        .allowlist_type("RBasic")

        // From internal.h
        // This function prints info about a value and is useful for debugging
        .allowlist_function("rb_obj_info_dump")

        // From ruby/internal/intern/object.h
        .allowlist_function("rb_obj_is_kind_of")

        // From ruby/internal/encoding/encoding.h
        .allowlist_type("ruby_encoding_consts")

        // From include/hash.h
        .allowlist_function("rb_hash_new")

        // From internal/hash.h
        .allowlist_function("rb_hash_new_with_size")
        .allowlist_function("rb_hash_resurrect")

        // From include/ruby/internal/intern/hash.h
        .allowlist_function("rb_hash_aset")
        .allowlist_function("rb_hash_aref")
        .allowlist_function("rb_hash_bulk_insert")

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

        // From ruby/internal/globals.h
        .allowlist_var("rb_mKernel")

        // From vm_callinfo.h
        .allowlist_type("VM_CALL.*")         // This doesn't work, possibly due to the odd structure of the #defines
        .allowlist_type("vm_call_flag_bits") // So instead we include the other enum and do the bit-shift ourselves.
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

        // From yjit.c
        .allowlist_function("rb_iseq_(get|set)_yjit_payload")
        .allowlist_function("rb_iseq_pc_at_idx")
        .allowlist_function("rb_iseq_opcode_at_pc")
        .allowlist_function("rb_yjit_mark_writable")
        .allowlist_function("rb_yjit_mark_executable")
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
        .allowlist_function("rb_ENCODING_GET")

        // from vm_sync.h
        .allowlist_function("rb_vm_barrier")

        // Not sure why it's picking these up, but don't.
        .blocklist_type("FILE")
        .blocklist_type("_IO_.*")

        // From internal/compile.h
        .allowlist_function("rb_vm_insn_decode")

        // From iseq.h
        .allowlist_function("rb_vm_insn_addr2opcode")
        .allowlist_function("rb_iseqw_to_iseq")
        .allowlist_function("rb_iseq_each")

        // From builtin.h
        .allowlist_type("rb_builtin_function.*")

        // From internal/variable.h
        .allowlist_function("rb_gvar_(get|set)")
        .allowlist_function("rb_obj_ensure_iv_index_mapping")

        // From include/ruby/internal/intern/variable.h
        .allowlist_function("rb_attr_get")
        .allowlist_function("rb_ivar_get")

        // From include/ruby/internal/intern/vm.h
        .allowlist_function("rb_get_alloc_func")

        // From gc.h and internal/gc.h
        .allowlist_function("rb_class_allocate_instance")
        .allowlist_function("rb_obj_info")

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
