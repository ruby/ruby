use std::ffi::CStr;
use crate::backend::ir::Assembler;

// Command-line options
#[derive(Clone, PartialEq, Eq, Debug)]
#[repr(C)]
pub struct Options {
    // Size of the executable memory block to allocate in bytes
    // Note that the command line argument is expressed in MiB and not bytes
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

    // The number of registers allocated for stack temps
    pub num_temp_regs: usize,

    // Capture and print out stats
    pub gen_stats: bool,

    // Trace locations of exits
    pub gen_trace_exits: bool,

    // how often to sample exit trace data
    pub trace_exits_sample_rate: usize,

    // Whether to start YJIT in paused state (initialize YJIT but don't
    // compile anything)
    pub pause: bool,

    /// Dump compiled and executed instructions for debugging
    pub dump_insns: bool,

    /// Dump all compiled instructions of target cbs.
    pub dump_disasm: Option<DumpDisasm>,

    /// Print when specific ISEQ items are compiled or invalidated
    pub dump_iseq_disasm: Option<String>,

    /// Verify context objects (debug mode only)
    pub verify_ctx: bool,
}

// Initialize the options to default values
pub static mut OPTIONS: Options = Options {
    exec_mem_size: 128 * 1024 * 1024,
    call_threshold: 30,
    greedy_versioning: false,
    no_type_prop: false,
    max_versions: 4,
    num_temp_regs: 5,
    gen_stats: false,
    gen_trace_exits: false,
    trace_exits_sample_rate: 0,
    pause: false,
    dump_insns: false,
    dump_disasm: None,
    verify_ctx: false,
    dump_iseq_disasm: None,
};

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum DumpDisasm {
    // Dump to stdout
    Stdout,
    // Dump to "yjit_{pid}.log" file under the specified directory
    File(String),
}

/// Macro to get an option value by name
macro_rules! get_option {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        unsafe { OPTIONS.$option_name }
    };
}
pub(crate) use get_option;

/// Macro to reference an option value by name; we assume it's a cloneable type like String or an Option of same.
macro_rules! get_option_ref {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        unsafe { &($crate::options::OPTIONS.$option_name) }
    };
}
pub(crate) use get_option_ref;

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

        ("exec-mem-size", _) => match opt_val.parse::<usize>() {
            Ok(n) => {
                if n == 0 || n > 2 * 1024 * 1024 {
                    return None
                }

                // Convert from MiB to bytes internally for convenience
                unsafe { OPTIONS.exec_mem_size = n * 1024 * 1024 }
            }
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

        ("pause", "") => unsafe {
            OPTIONS.pause = true;
        },

        ("temp-regs", _) => match opt_val.parse() {
            Ok(n) => {
                assert!(n <= Assembler::TEMP_REGS.len(), "--yjit-temp-regs must be <= {}", Assembler::TEMP_REGS.len());
                unsafe { OPTIONS.num_temp_regs = n }
            }
            Err(_) => {
                return None;
            }
        },

        ("dump-disasm", _) => match opt_val.to_string().as_str() {
            "" => unsafe { OPTIONS.dump_disasm = Some(DumpDisasm::Stdout) },
            directory => {
                let pid = std::process::id();
                let path = format!("{directory}/yjit_{pid}.log");
                println!("YJIT disasm dump: {path}");
                unsafe { OPTIONS.dump_disasm = Some(DumpDisasm::File(path)) }
            }
         },

        ("dump-iseq-disasm", _) => unsafe {
            OPTIONS.dump_iseq_disasm = Some(opt_val.to_string());
        },

        ("greedy-versioning", "") => unsafe { OPTIONS.greedy_versioning = true },
        ("no-type-prop", "") => unsafe { OPTIONS.no_type_prop = true },
        ("stats", "") => unsafe { OPTIONS.gen_stats = true },
        ("trace-exits", "") => unsafe { OPTIONS.gen_trace_exits = true; OPTIONS.gen_stats = true; OPTIONS.trace_exits_sample_rate = 0 },
        ("trace-exits-sample-rate", sample_rate) => unsafe { OPTIONS.gen_trace_exits = true; OPTIONS.gen_stats = true; OPTIONS.trace_exits_sample_rate = sample_rate.parse().unwrap(); },
        ("dump-insns", "") => unsafe { OPTIONS.dump_insns = true },
        ("verify-ctx", "") => unsafe { OPTIONS.verify_ctx = true },

        // Option name not recognized
        _ => {
            return None;
        }
    }

    // before we continue, check that sample_rate is either 0 or a prime number
    let trace_sample_rate = unsafe { OPTIONS.trace_exits_sample_rate };
    if trace_sample_rate > 1 {
        let mut i = 2;
        while i*i <= trace_sample_rate {
            if trace_sample_rate % i == 0 {
                println!("Warning: using a non-prime number as your sampling rate can result in less accurate sampling data");
                return Some(());
            }
            i += 1;
        }
    }

    // dbg!(unsafe {OPTIONS});

    // Option successfully parsed
    return Some(());
}
