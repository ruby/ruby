use std::{ffi::{CStr, CString}, ptr::null, fs::File};
use crate::{backend::current::TEMP_REGS, stats::Counter};
use std::os::raw::{c_char, c_int, c_uint};

// Call threshold for small deployments and command-line apps
pub static SMALL_CALL_THRESHOLD: u64 = 30;

// Call threshold for larger deployments and production-sized applications
pub static LARGE_CALL_THRESHOLD: u64 = 120;

// Number of live ISEQs after which we consider an app to be large
pub static LARGE_ISEQ_COUNT: u64 = 40_000;

// This option is exposed to the C side in a global variable for performance, see vm.c
// Number of method calls after which to start generating code
// Threshold==1 means compile on first execution
#[no_mangle]
pub static mut rb_yjit_call_threshold: u64 = SMALL_CALL_THRESHOLD;

// This option is exposed to the C side in a global variable for performance, see vm.c
// Number of execution requests after which a method is no longer
// considered hot. Raising this results in more generated code.
#[no_mangle]
pub static mut rb_yjit_cold_threshold: u64 = 200_000;

// Command-line options
#[derive(Debug)]
#[repr(C)]
pub struct Options {
    // Size of the executable memory block to allocate in bytes
    // Note that the command line argument is expressed in MiB and not bytes
    pub exec_mem_size: usize,

    // Disable the propagation of type information
    pub no_type_prop: bool,

    // Maximum number of versions per block
    // 1 means always create generic versions
    pub max_versions: usize,

    // The number of registers allocated for stack temps
    pub num_temp_regs: usize,

    // Capture stats
    pub gen_stats: bool,

    // Print stats on exit (when gen_stats is also true)
    pub print_stats: bool,

    // Trace locations of exits
    pub trace_exits: Option<TraceExits>,

    // how often to sample exit trace data
    pub trace_exits_sample_rate: usize,

    // Whether to enable YJIT at boot. This option prevents other
    // YJIT tuning options from enabling YJIT at boot.
    pub disable: bool,

    /// Dump compiled and executed instructions for debugging
    pub dump_insns: bool,

    /// Dump all compiled instructions of target cbs.
    pub dump_disasm: Option<DumpDisasm>,

    /// Print when specific ISEQ items are compiled or invalidated
    pub dump_iseq_disasm: Option<String>,

    /// Verify context objects (debug mode only)
    pub verify_ctx: bool,

    /// Enable generating frame pointers (for x86. arm64 always does this)
    pub frame_pointer: bool,

    /// Run code GC when exec_mem_size is reached.
    pub code_gc: bool,

    /// Enable writing /tmp/perf-{pid}.map for Linux perf
    pub perf_map: Option<PerfMap>,
}

// Initialize the options to default values
pub static mut OPTIONS: Options = Options {
    exec_mem_size: 48 * 1024 * 1024,
    no_type_prop: false,
    max_versions: 4,
    num_temp_regs: 5,
    gen_stats: false,
    trace_exits: None,
    print_stats: true,
    trace_exits_sample_rate: 0,
    disable: false,
    dump_insns: false,
    dump_disasm: None,
    verify_ctx: false,
    dump_iseq_disasm: None,
    frame_pointer: false,
    code_gc: false,
    perf_map: None,
};

/// YJIT option descriptions for `ruby --help`.
static YJIT_OPTIONS: [(&str, &str); 9] = [
    ("--yjit-exec-mem-size=num",           "Size of executable memory block in MiB (default: 48)."),
    ("--yjit-call-threshold=num",          "Number of calls to trigger JIT."),
    ("--yjit-cold-threshold=num",          "Global calls after which ISEQs not compiled (default: 200K)."),
    ("--yjit-stats",                       "Enable collecting YJIT statistics."),
    ("--yjit-disable",                     "Disable YJIT for lazily enabling it with RubyVM::YJIT.enable."),
    ("--yjit-code-gc",                     "Run code GC when the code size reaches the limit."),
    ("--yjit-perf",                        "Enable frame pointers and perf profiling."),
    ("--yjit-trace-exits",                 "Record Ruby source location when exiting from generated code."),
    ("--yjit-trace-exits-sample-rate=num", "Trace exit locations only every Nth occurrence."),
];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TraceExits {
    // Trace all exits
    All,
    // Trace a specific counted exit
    CountedExit(Counter),
}

#[derive(Debug)]
pub enum DumpDisasm {
    // Dump to stdout
    Stdout,
    // Dump to "yjit_{pid}.log" file under the specified directory
    #[cfg_attr(not(feature = "disasm"), allow(dead_code))]
    File(std::os::unix::io::RawFd),
}

/// Type of symbols to dump into /tmp/perf-{pid}.map
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PerfMap {
    // Dump ISEQ symbols
    ISEQ,
    // Dump YJIT codegen symbols
    Codegen,
}

/// Macro to get an option value by name
macro_rules! get_option {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        {
            // Make this a statement since attributes on expressions are experimental
            #[allow(unused_unsafe)]
            let ret = unsafe { OPTIONS.$option_name };
            ret
        }
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
            Ok(n) => unsafe { rb_yjit_call_threshold = n },
            Err(_) => {
                return None;
            }
        },

        ("cold-threshold", _) => match opt_val.parse() {
            Ok(n) => unsafe { rb_yjit_cold_threshold = n },
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

        ("disable", "") => unsafe {
            OPTIONS.disable = true;
        },

        ("temp-regs", _) => match opt_val.parse() {
            Ok(n) => {
                assert!(n <= TEMP_REGS.len(), "--yjit-temp-regs must be <= {}", TEMP_REGS.len());
                unsafe { OPTIONS.num_temp_regs = n }
            }
            Err(_) => {
                return None;
            }
        },

        ("code-gc", _) => unsafe {
            OPTIONS.code_gc = true;
        },

        ("perf", _) => match opt_val {
            "" => unsafe {
                OPTIONS.frame_pointer = true;
                OPTIONS.perf_map = Some(PerfMap::ISEQ);
            },
            "fp" => unsafe { OPTIONS.frame_pointer = true },
            "iseq" => unsafe { OPTIONS.perf_map = Some(PerfMap::ISEQ) },
            // Accept --yjit-perf=map for backward compatibility
            "codegen" | "map" => unsafe { OPTIONS.perf_map = Some(PerfMap::Codegen) },
            _ => return None,
         },

        ("dump-disasm", _) => {
            if !cfg!(feature = "disasm") {
                eprintln!("WARNING: the {} option is only available when YJIT is built in dev mode, i.e. ./configure --enable-yjit=dev", opt_name);
            }

            match opt_val {
                "" => unsafe { OPTIONS.dump_disasm = Some(DumpDisasm::Stdout) },
                directory => {
                    let path = format!("{directory}/yjit_{}.log", std::process::id());
                    match File::options().create(true).append(true).open(&path) {
                        Ok(file) => {
                            use std::os::unix::io::IntoRawFd;
                            eprintln!("YJIT disasm dump: {path}");
                            unsafe { OPTIONS.dump_disasm = Some(DumpDisasm::File(file.into_raw_fd())) }
                        }
                        Err(err) => eprintln!("Failed to create {path}: {err}"),
                    }
                }
            }
        },

        ("dump-iseq-disasm", _) => unsafe {
            if !cfg!(feature = "disasm") {
                eprintln!("WARNING: the {} option is only available when YJIT is built in dev mode, i.e. ./configure --enable-yjit=dev", opt_name);
            }

            OPTIONS.dump_iseq_disasm = Some(opt_val.to_string());
        },

        ("no-type-prop", "") => unsafe { OPTIONS.no_type_prop = true },
        ("stats", _) => match opt_val {
            "" => unsafe { OPTIONS.gen_stats = true },
            "quiet" => unsafe {
                OPTIONS.gen_stats = true;
                OPTIONS.print_stats = false;
            },
            _ => {
                return None;
            }
        },
        ("trace-exits", _) => unsafe {
            OPTIONS.gen_stats = true;
            OPTIONS.trace_exits = match opt_val {
                "" => Some(TraceExits::All),
                name => match Counter::get(name) {
                    Some(counter) => Some(TraceExits::CountedExit(counter)),
                    None => return None,
                },
            };
        },
        ("trace-exits-sample-rate", sample_rate) => unsafe {
            OPTIONS.gen_stats = true;
            if OPTIONS.trace_exits.is_none() {
                OPTIONS.trace_exits = Some(TraceExits::All);
            }
            OPTIONS.trace_exits_sample_rate = sample_rate.parse().unwrap();
        },
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

/// Print YJIT options for `ruby --help`. `width` is width of option parts, and
/// `columns` is indent width of descriptions.
#[no_mangle]
pub extern "C" fn rb_yjit_show_usage(help: c_int, highlight: c_int, width: c_uint, columns: c_int) {
    for &(name, description) in YJIT_OPTIONS.iter() {
        extern "C" {
            fn ruby_show_usage_line(name: *const c_char, secondary: *const c_char, description: *const c_char,
                                    help: c_int, highlight: c_int, width: c_uint, columns: c_int);
        }
        let name = CString::new(name).unwrap();
        let description = CString::new(description).unwrap();
        unsafe { ruby_show_usage_line(name.as_ptr(), null(), description.as_ptr(), help, highlight, width, columns) }
    }
}
