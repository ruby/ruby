use std::{ffi::CStr, os::raw::c_char};

// This option is exposed to the C side in a global variable for performance, see vm.c
// Number of method calls after which to start generating code
// Threshold==1 means compile on first execution
#[no_mangle]
#[allow(non_upper_case_globals)]
pub static mut rb_zjit_call_threshold: u64 = 1;

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Enable debug logging
    pub debug: bool,

    /// Dump SSA IR generated from ISEQ.
    pub dump_ssa: Option<DumpSSA>,

    /// Dump all compiled machine code.
    pub dump_disasm: bool,
}

#[derive(Clone, Copy, Debug)]
pub enum DumpSSA {
    // Dump SSA without Snapshot
    WithoutSnapshot,
    // Dump SSA with Snapshot
    All,
    // Pretty-print bare SSA structs
    Raw,
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
#[no_mangle]
pub extern "C" fn rb_zjit_init_options() -> *const u8 {
    let options = init_options();
    Box::into_raw(Box::new(options)) as *const u8
}

/// Return an Options with default values
pub fn init_options() -> Options {
    Options {
        debug: false,
        dump_ssa: None,
        dump_disasm: false,
    }
}

/// Parse a --zjit* command-line flag
#[no_mangle]
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

        ("dump-ssa", "") => options.dump_ssa = Some(DumpSSA::WithoutSnapshot),
        ("dump-ssa", "all") => options.dump_ssa = Some(DumpSSA::All),
        ("dump-ssa", "raw") => options.dump_ssa = Some(DumpSSA::Raw),

        ("dump-disasm", "") => options.dump_disasm = true,

        _ => return None, // Option name not recognized
    }

    // Option successfully parsed
    return Some(());
}

/// Macro to print a message only when --zjit-debug is given
macro_rules! debug {
    ($($msg:tt)*) => {
        use crate::options::get_option;
        if get_option!(debug) {
            eprintln!($($msg)*);
        }
    };
}
pub(crate) use debug;
