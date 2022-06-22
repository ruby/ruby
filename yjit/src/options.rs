use std::ffi::CStr;

// Command-line options
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(C)]
pub struct Options {
    // Size of the executable memory block to allocate in MiB
    pub exec_mem_size: usize,

    // Number of method calls after which to start generating code
    // Threshold==1 means compile on first execution
    pub call_threshold: usize,

    // Generate versions greedily until the limit is hit
    pub greedy_versioning: bool,

    // Disable the propagation of type information
    pub no_type_prop: bool,

    // Maximum number of versions per block
    // 1 means always create generic versions
    pub max_versions: usize,

    // Capture and print out stats
    pub gen_stats: bool,

    // Trace locations of exits
    pub gen_trace_exits: bool,

    /// Dump compiled and executed instructions for debugging
    pub dump_insns: bool,

    /// Verify context objects (debug mode only)
    pub verify_ctx: bool,

    /// Whether or not to assume a global constant state (and therefore
    /// invalidating code whenever any constant changes) versus assuming
    /// constant name components (and therefore invalidating code whenever a
    /// matching name component changes)
    pub global_constant_state: bool,
}

// Initialize the options to default values
pub static mut OPTIONS: Options = Options {
    exec_mem_size: 256,
    call_threshold: 10,
    greedy_versioning: false,
    no_type_prop: false,
    max_versions: 4,
    gen_stats: false,
    gen_trace_exits: false,
    dump_insns: false,
    verify_ctx: false,
    global_constant_state: false,
};

/// Macro to get an option value by name
macro_rules! get_option {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        unsafe { OPTIONS.$option_name }
    };
}
pub(crate) use get_option;

/// Expected to receive what comes after the third dash in "--yjit-*".
/// Empty string means user passed only "--yjit". C code rejects when
/// they pass exact "--yjit-".
pub fn parse_option(str_ptr: *const std::os::raw::c_char) -> Option<()> {
    let c_str: &CStr = unsafe { CStr::from_ptr(str_ptr) };
    let opt_str: &str = c_str.to_str().ok()?;
    //println!("{}", opt_str);

    // Split the option name and value strings
    // Note that some options do not contain an assignment
    let parts = opt_str.split_once('=');
    let (opt_name, opt_val) = match parts {
        Some((before_eq, after_eq)) => (before_eq, after_eq),
        None => (opt_str, ""),
    };

    // Match on the option name and value strings
    match (opt_name, opt_val) {
        ("", "") => (), // Simply --yjit

        ("exec-mem-size", _) => match opt_val.parse() {
            Ok(n) => unsafe { OPTIONS.exec_mem_size = n },
            Err(_) => {
                return None;
            }
        },

        ("call-threshold", _) => match opt_val.parse() {
            Ok(n) => unsafe { OPTIONS.call_threshold = n },
            Err(_) => {
                return None;
            }
        },

        ("max-versions", _) => match opt_val.parse() {
            Ok(n) => unsafe { OPTIONS.max_versions = n },
            Err(_) => {
                return None;
            }
        },

        ("greedy-versioning", "") => unsafe { OPTIONS.greedy_versioning = true },
        ("no-type-prop", "") => unsafe { OPTIONS.no_type_prop = true },
        ("stats", "") => unsafe { OPTIONS.gen_stats = true },
        ("trace-exits", "") => unsafe { OPTIONS.gen_trace_exits = true; OPTIONS.gen_stats = true },
        ("dump-insns", "") => unsafe { OPTIONS.dump_insns = true },
        ("verify-ctx", "") => unsafe { OPTIONS.verify_ctx = true },
        ("global-constant-state", "") => unsafe { OPTIONS.global_constant_state = true },

        // Option name not recognized
        _ => {
            return None;
        }
    }

    // dbg!(unsafe {OPTIONS});

    // Option successfully parsed
    return Some(());
}
