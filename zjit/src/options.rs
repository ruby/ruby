use std::{ffi::{CStr, CString}, ptr::null};
use std::os::raw::{c_char, c_int, c_uint};

/// Number of calls to start profiling YARV instructions.
/// They are profiled `rb_zjit_call_threshold - rb_zjit_profile_threshold` times,
/// which is equal to --zjit-num-profiles.
#[unsafe(no_mangle)]
#[allow(non_upper_case_globals)]
pub static mut rb_zjit_profile_threshold: u64 = 1;

/// Number of calls to compile ISEQ with ZJIT at jit_compile() in vm.c.
/// --zjit-call-threshold=1 compiles on first execution without profiling information.
#[unsafe(no_mangle)]
#[allow(non_upper_case_globals)]
pub static mut rb_zjit_call_threshold: u64 = 2;

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Number of times YARV instructions should be profiled.
    pub num_profiles: u64,

    /// Enable debug logging
    pub debug: bool,

    /// Dump initial High-level IR before optimization
    pub dump_hir_init: Option<DumpHIR>,

    /// Dump High-level IR after optimization, right before codegen.
    pub dump_hir_opt: Option<DumpHIR>,

    /// Dump low-level IR
    pub dump_lir: bool,

    /// Dump all compiled machine code.
    pub dump_disasm: bool,
}

/// Return an Options with default values
pub fn init_options() -> Options {
    Options {
        num_profiles: 1,
        debug: false,
        dump_hir_init: None,
        dump_hir_opt: None,
        dump_lir: false,
        dump_disasm: false,
    }
}

/// `ruby --help` descriptions for user-facing options. Do not add options for ZJIT developers.
/// Note that --help allows only 80 chars per line, including indentation.    80-char limit --> |
pub const ZJIT_OPTIONS: &'static [(&str, &str)] = &[
    ("--zjit-call-threshold=num", "Number of calls to trigger JIT (default: 2)."),
    ("--zjit-num-profiles=num",   "Number of profiled calls before JIT (default: 1)."),
];

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
            Ok(n) => {
                unsafe { rb_zjit_call_threshold = n; }
                update_profile_threshold(options);
            },
            Err(_) => return None,
        },

        ("num-profiles", _) => match opt_val.parse() {
            Ok(n) => {
                options.num_profiles = n;
                update_profile_threshold(options);
            },
            Err(_) => return None,
        },

        ("debug", "") => options.debug = true,

        // --zjit-dump-hir dumps the actual input to the codegen, which is currently the same as --zjit-dump-hir-opt.
        ("dump-hir" | "dump-hir-opt", "") => options.dump_hir_opt = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir" | "dump-hir-opt", "all") => options.dump_hir_opt = Some(DumpHIR::All),
        ("dump-hir" | "dump-hir-opt", "debug") => options.dump_hir_opt = Some(DumpHIR::Debug),

        ("dump-hir-init", "") => options.dump_hir_init = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir-init", "all") => options.dump_hir_init = Some(DumpHIR::All),
        ("dump-hir-init", "debug") => options.dump_hir_init = Some(DumpHIR::Debug),

        ("dump-lir", "") => options.dump_lir = true,

        ("dump-disasm", "") => options.dump_disasm = true,

        _ => return None, // Option name not recognized
    }

    // Option successfully parsed
    Some(())
}

/// Update rb_zjit_profile_threshold based on rb_zjit_call_threshold and options.num_profiles
fn update_profile_threshold(options: &Options) {
    unsafe {
        if rb_zjit_call_threshold == 1 {
            // If --zjit-call-threshold=1, never rewrite ISEQs to profile instructions.
            rb_zjit_profile_threshold = 0;
        } else {
            // Otherwise, profile instructions at least once.
            rb_zjit_profile_threshold = rb_zjit_call_threshold.saturating_sub(options.num_profiles).max(1);
        }
    }
}

/// Print YJIT options for `ruby --help`. `width` is width of option parts, and
/// `columns` is indent width of descriptions.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_show_usage(help: c_int, highlight: c_int, width: c_uint, columns: c_int) {
    for &(name, description) in ZJIT_OPTIONS.iter() {
        unsafe extern "C" {
            fn ruby_show_usage_line(name: *const c_char, secondary: *const c_char, description: *const c_char,
                                    help: c_int, highlight: c_int, width: c_uint, columns: c_int);
        }
        let name = CString::new(name).unwrap();
        let description = CString::new(description).unwrap();
        unsafe { ruby_show_usage_line(name.as_ptr(), null(), description.as_ptr(), help, highlight, width, columns) }
    }
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
