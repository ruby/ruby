//! No-op stubs for YJIT symbols referenced by the Ruby VM's C code.
//!
//! When running `make zjit-test`, we strip `libruby.o` from `libminiruby.a`
//! to avoid linking a second copy of ZJIT (which would create duplicate
//! global state). Removing `libruby.o` also removes all YJIT definitions,
//! so we provide these trivial stubs to satisfy the linker. They are safe
//! because YJIT is never enabled during ZJIT tests.

#![allow(non_upper_case_globals)]
#![allow(unused_variables)]

use std::ffi::c_void;
use std::os::raw::{c_char, c_int, c_uint};
use std::ptr::null;

use crate::cruby::*;

// ---------------------------------------------------------------------------
// Static variables
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub static mut rb_yjit_call_threshold: u64 = 0;

#[unsafe(no_mangle)]
pub static mut rb_yjit_cold_threshold: u64 = 0;

#[unsafe(no_mangle)]
pub static mut rb_yjit_live_iseq_count: u64 = 0;

#[unsafe(no_mangle)]
pub static mut rb_yjit_iseq_alloc_count: u64 = 0;

#[unsafe(no_mangle)]
pub static mut rb_yjit_enabled_p: bool = false;

// ---------------------------------------------------------------------------
// Lifecycle and initialization
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_init(yjit_enabled: bool) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_init_builtin_cmes() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_free_at_exit() {}

#[unsafe(no_mangle)]
pub extern "C" fn Init_builtin_yjit() {}

// ---------------------------------------------------------------------------
// Option parsing
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_parse_option(str_ptr: *const c_char) -> bool {
    false
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_option_disable() -> bool {
    false
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_show_usage(help: c_int, highlight: c_int, width: c_uint, columns: c_int) {}

// ---------------------------------------------------------------------------
// Compilation entry points
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_compile_iseq(iseq: IseqPtr, ec: EcPtr, jit_exception: bool) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_iseq_gen_entry_point(iseq: IseqPtr, ec: EcPtr, jit_exception: bool) -> *const u8 {
    null()
}

// ---------------------------------------------------------------------------
// Invalidation callbacks
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_bop_redefined(klass: RedefinitionFlag, bop: ruby_basic_operators) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_cme_invalidate(callee_cme: *const rb_callable_method_entry_t) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_constant_state_changed(id: ID) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_constant_ic_update(iseq: *const rb_iseq_t, ic: IC, insn_idx: c_uint) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_invalidate_all_method_lookup_assumptions() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_invalidate_no_singleton_class(klass: VALUE) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_invalidate_ep_is_bp(iseq: IseqPtr) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_tracing_invalidate_all() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_before_ractor_spawn() {}

// ---------------------------------------------------------------------------
// ISEQ lifetime callbacks
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_iseq_mark(payload: *mut c_void) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_iseq_update_references(iseq: IseqPtr) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_iseq_free(iseq: IseqPtr) {}

// ---------------------------------------------------------------------------
// GC integration
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_root_mark() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_root_update_references() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_mark_all_writeable() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_mark_all_executable() {}

// ---------------------------------------------------------------------------
// Stats and diagnostics
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_incr_counter(counter_name: *const c_char) {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_collect_binding_alloc() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_collect_binding_set() {}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_lazy_push_frame(pc: *const VALUE) {}

// ---------------------------------------------------------------------------
// Ruby-callable method stubs (ec, self) -> VALUE
//
// These are registered as Ruby builtins and called via the Ruby method
// dispatch. They return Qnil since YJIT is not active during ZJIT tests.
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_enable(
    _ec: EcPtr,
    _ruby_self: VALUE,
    _gen_stats: VALUE,
    _print_stats: VALUE,
    _gen_log: VALUE,
    _print_log: VALUE,
    _mem_size: VALUE,
    _call_threshold: VALUE,
) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_stats_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_print_stats_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_log_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_trace_exit_locations_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_get_stats(_ec: EcPtr, _ruby_self: VALUE, _key: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_get_exit_locations(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_get_log(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_reset_stats_bang(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_disasm_iseq(_ec: EcPtr, _ruby_self: VALUE, _iseqw: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_insns_compiled(_ec: EcPtr, _ruby_self: VALUE, _iseqw: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_simulate_oom_bang(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_code_gc(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_yjit_c_builtin_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    Qnil
}
