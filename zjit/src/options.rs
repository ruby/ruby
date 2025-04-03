use std::{ffi::CStr, os::raw::c_char};

// This option is exposed to the C side in a global variable for performance, see vm.c
// Number of method calls after which to start generating code
// Threshold==1 means compile on first execution
#[unsafe(no_mangle)]
#[allow(non_upper_case_globals)]
pub static mut rb_zjit_call_threshold: u64 = 2;

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Enable debug logging
    pub debug: bool,

    /// Dump High-level IR generated from ISEQ.
    pub dump_hir: Option<DumpHIR>,

    /// Dump High-level IR after optimization, right before codegen.
    pub dump_hir_opt: Option<DumpHIR>,

    /// Dump all compiled machine code.
    pub dump_disasm: bool,
}

#[derive(Clone, Copy, Debug)]
pub enum DumpHIR {
    // Dump High-level IR without Snapshot
    WithoutSnapshot,
    // Dump High-level IR with Snapshot
    All,
    // Pretty-print bare High-level IR structs
    Debug,
}

/// Macro to get an option value by name
macro_rules! get_option {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        {
            use crate::state::ZJITState;
            ZJITState::get_options().$option_name
        }
    };
}
pub(crate) use get_option;

/// Allocate Options on the heap, initialize it, and return the address of it.
/// The return value will be modified by rb_zjit_parse_option() and then
/// passed to rb_zjit_init() for initialization.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init_options() -> *const u8 {
    let options = init_options();
    Box::into_raw(Box::new(options)) as *const u8
}

/// Return an Options with default values
pub fn init_options() -> Options {
    Options {
        debug: false,
        dump_hir: None,
        dump_hir_opt: None,
        dump_disasm: false,
    }
}

/// Parse a --zjit* command-line flag
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_parse_option(options: *const u8, str_ptr: *const c_char) -> bool {
    let options = unsafe { &mut *(options as *mut Options) };
    parse_option(options, str_ptr).is_some()
}

/// Expected to receive what comes after the third dash in "--zjit-*".
/// Empty string means user passed only "--zjit". C code rejects when
/// they pass exact "--zjit-".
fn parse_option(options: &mut Options, str_ptr: *const std::os::raw::c_char) -> Option<()> {
    let c_str: &CStr = unsafe { CStr::from_ptr(str_ptr) };
    let opt_str: &str = c_str.to_str().ok()?;

    // Split the option name and value strings
    // Note that some options do not contain an assignment
    let parts = opt_str.split_once('=');
    let (opt_name, opt_val) = match parts {
        Some((before_eq, after_eq)) => (before_eq, after_eq),
        None => (opt_str, ""),
    };

    // Match on the option name and value strings
    match (opt_name, opt_val) {
        ("", "") => {}, // Simply --zjit

        ("call-threshold", _) => match opt_val.parse() {
            Ok(n) => unsafe { rb_zjit_call_threshold = n },
            Err(_) => return None,
        },

        ("debug", "") => options.debug = true,

        ("dump-hir", "") => options.dump_hir = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir", "all") => options.dump_hir = Some(DumpHIR::All),
        ("dump-hir", "debug") => options.dump_hir = Some(DumpHIR::Debug),

        ("dump-hir-opt", "") => options.dump_hir_opt = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir-opt", "all") => options.dump_hir_opt = Some(DumpHIR::All),
        ("dump-hir-opt", "debug") => options.dump_hir_opt = Some(DumpHIR::Debug),

        ("dump-disasm", "") => options.dump_disasm = true,

        _ => return None, // Option name not recognized
    }

    // Option successfully parsed
    Some(())
}

/// Macro to print a message only when --zjit-debug is given
macro_rules! debug {
    ($($msg:tt)*) => {
        if $crate::options::get_option!(debug) {
            eprintln!($($msg)*);
        }
    };
}
pub(crate) use debug;
