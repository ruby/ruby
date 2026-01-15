//! Configurable options for ZJIT.

use std::{ffi::{CStr, CString}, ptr::null};
use std::os::raw::{c_char, c_int, c_uint};
use crate::cruby::*;
use crate::stats::Counter;
use std::collections::HashSet;

/// Default --zjit-num-profiles
const DEFAULT_NUM_PROFILES: NumProfiles = 5;
pub type NumProfiles = u32;

/// Default --zjit-call-threshold. This should be large enough to avoid compiling
/// warmup code, but small enough to perform well on micro-benchmarks.
pub const DEFAULT_CALL_THRESHOLD: CallThreshold = 30;
pub type CallThreshold = u64;

/// Number of calls to start profiling YARV instructions.
/// They are profiled `rb_zjit_call_threshold - rb_zjit_profile_threshold` times,
/// which is equal to --zjit-num-profiles.
#[unsafe(no_mangle)]
#[allow(non_upper_case_globals)]
pub static mut rb_zjit_profile_threshold: CallThreshold = DEFAULT_CALL_THRESHOLD - DEFAULT_NUM_PROFILES as CallThreshold;

/// Number of calls to compile ISEQ with ZJIT at jit_compile() in vm.c.
/// --zjit-call-threshold=1 compiles on first execution without profiling information.
#[unsafe(no_mangle)]
#[allow(non_upper_case_globals)]
pub static mut rb_zjit_call_threshold: CallThreshold = DEFAULT_CALL_THRESHOLD;

/// ZJIT command-line options. This is set before rb_zjit_init() sets
/// ZJITState so that we can query some options while loading builtins.
pub static mut OPTIONS: Option<Options> = None;

#[derive(Clone, Debug)]
pub struct Options {
    /// Hard limit of the executable memory block to allocate in bytes.
    /// Note that the command line argument is expressed in MiB and not bytes.
    pub exec_mem_bytes: usize,

    /// Hard limit of ZJIT's total memory usage.
    /// Note that the command line argument is expressed in MiB and not bytes.
    pub mem_bytes: usize,

    /// Number of times YARV instructions should be profiled.
    pub num_profiles: NumProfiles,

    /// Enable ZJIT statistics
    pub stats: bool,

    /// Print stats on exit (when stats is also true)
    pub print_stats: bool,

    /// Print stats to file on exit (when stats is also true)
    pub print_stats_file: Option<std::path::PathBuf>,

    /// Enable debug logging
    pub debug: bool,

    // Whether to enable JIT at boot. This option prevents other
    // ZJIT tuning options from enabling ZJIT at boot.
    pub disable: bool,

    /// Turn off the HIR optimizer
    pub disable_hir_opt: bool,

    /// Dump initial High-level IR before optimization
    pub dump_hir_init: Option<DumpHIR>,

    /// Dump High-level IR after optimization, right before codegen.
    pub dump_hir_opt: Option<DumpHIR>,

    /// Dump High-level IR to the given file in Graphviz format after optimization
    pub dump_hir_graphviz: Option<std::path::PathBuf>,

    /// Dump High-level IR in Iongraph JSON format after optimization to /tmp/zjit-iongraph-{$PID}
    pub dump_hir_iongraph: bool,

    /// Dump low-level IR
    pub dump_lir: Option<HashSet<DumpLIR>>,

    /// Dump all compiled machine code.
    pub dump_disasm: bool,

    /// Trace and write side exit source maps to /tmp for stackprof.
    pub trace_side_exits: Option<TraceExits>,

    /// Frequency of tracing side exits.
    pub trace_side_exits_sample_interval: usize,

    /// Dump code map to /tmp for performance profilers.
    pub perf: bool,

    /// List of ISEQs that can be compiled, identified by their iseq_get_location()
    pub allowed_iseqs: Option<HashSet<String>>,

    /// Path to a file where compiled ISEQs will be saved.
    pub log_compiled_iseqs: Option<std::path::PathBuf>,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            exec_mem_bytes: 64 * 1024 * 1024,
            mem_bytes: 128 * 1024 * 1024,
            num_profiles: DEFAULT_NUM_PROFILES,
            stats: false,
            print_stats: false,
            print_stats_file: None,
            debug: false,
            disable: false,
            disable_hir_opt: false,
            dump_hir_init: None,
            dump_hir_opt: None,
            dump_hir_graphviz: None,
            dump_hir_iongraph: false,
            dump_lir: None,
            dump_disasm: false,
            trace_side_exits: None,
            trace_side_exits_sample_interval: 0,
            perf: false,
            allowed_iseqs: None,
            log_compiled_iseqs: None,
        }
    }
}

/// `ruby --help` descriptions for user-facing options. Do not add options for ZJIT developers.
/// Note that --help allows only 80 chars per line, including indentation, and it also puts the
/// description in a separate line if the option name is too long.  80-char limit --> | (any character beyond this `|` column fails the test)
pub const ZJIT_OPTIONS: &[(&str, &str)] = &[
    ("--zjit-mem-size=num",
                     "Max amount of memory that ZJIT can use in MiB (default: 128)."),
    ("--zjit-call-threshold=num",
                     "Number of calls to trigger JIT (default: 30)."),
    ("--zjit-num-profiles=num",
                     "Number of profiled calls before JIT (default: 5)."),
    ("--zjit-stats-quiet",
                     "Collect ZJIT stats and suppress output."),
    ("--zjit-stats[=file]",
                     "Collect ZJIT stats (=file to write to a file)."),
    ("--zjit-disable",
                     "Disable ZJIT for lazily enabling it with RubyVM::ZJIT.enable."),
    ("--zjit-perf",  "Dump ISEQ symbols into /tmp/perf-{}.map for Linux perf."),
    ("--zjit-log-compiled-iseqs=path",
                     "Log compiled ISEQs to the file. The file will be truncated."),
    ("--zjit-trace-exits[=counter]",
                     "Record source on side-exit. `Counter` picks specific counter."),
    ("--zjit-trace-exits-sample-rate=num",
                     "Frequency at which to record side exits. Must be `usize`.")
];

#[derive(Copy, Clone, Debug)]
pub enum TraceExits {
    // Trace all exits
    All,
    // Trace exits for a specific `Counter`
    Counter(Counter),
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

/// --zjit-dump-lir values. Using snake_case to stringify the exact filter value.
#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
pub enum DumpLIR {
    /// Dump the initial LIR
    init,
    /// Dump LIR after {arch}_split
    split,
    /// Dump LIR after alloc_regs
    alloc_regs,
    /// Dump LIR after compile_exits
    compile_exits,
    /// Dump LIR after {arch}_scratch_split
    scratch_split,
}

/// All compiler stages for --zjit-dump-lir=all.
const DUMP_LIR_ALL: &[DumpLIR] = &[
    DumpLIR::init,
    DumpLIR::split,
    DumpLIR::alloc_regs,
    DumpLIR::compile_exits,
    DumpLIR::scratch_split,
];

/// Maximum value for --zjit-mem-size/--zjit-exec-mem-size in MiB.
/// We set 1TiB just to avoid overflow. We could make it smaller.
const MAX_MEM_MIB: usize = 1024 * 1024;

/// Macro to dump LIR if --zjit-dump-lir is specified
macro_rules! asm_dump {
    ($asm:expr, $target:ident) => {
        if let Some(crate::options::Options { dump_lir: Some(dump_lirs), .. }) = unsafe { crate::options::OPTIONS.as_ref() } {
            if dump_lirs.contains(&crate::options::DumpLIR::$target) {
                println!("LIR {}:\n{}", stringify!($target), $asm);
            }
        }
    };
}
pub(crate) use asm_dump;

/// Macro to get an option value by name
macro_rules! get_option {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        unsafe { crate::options::OPTIONS.as_ref() }.unwrap().$option_name
    };
}
pub(crate) use get_option;

/// Set default values to ZJIT options. Setting Some to OPTIONS will make `#with_jit`
/// enable the JIT hook while not enabling compilation yet.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_prepare_options() {
    // rb_zjit_prepare_options() could be called for feature flags or $RUBY_ZJIT_ENABLE
    // after rb_zjit_parse_option() is called, so we need to handle the already-initialized case.
    if unsafe { OPTIONS.is_none() } {
        unsafe { OPTIONS = Some(Options::default()); }
    }
}

/// Parse a --zjit* command-line flag
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_parse_option(str_ptr: *const c_char) -> bool {
    parse_option(str_ptr).is_some()
}

fn parse_jit_list(path_like: &str) -> HashSet<String> {
    // Read lines from the file
    let mut result = HashSet::new();
    if let Ok(lines) = std::fs::read_to_string(path_like) {
        for line in lines.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                result.insert(trimmed.to_string());
            }
        }
    } else {
        eprintln!("Failed to read JIT list from '{path_like}'");
    }
    eprintln!("JIT list:");
    for item in &result {
        eprintln!("  {item}");
    }
    result
}

/// Expected to receive what comes after the third dash in "--zjit-*".
/// Empty string means user passed only "--zjit". C code rejects when
/// they pass exact "--zjit-".
fn parse_option(str_ptr: *const std::os::raw::c_char) -> Option<()> {
    rb_zjit_prepare_options();
    let options = unsafe { OPTIONS.as_mut().unwrap() };

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

        ("mem-size", _) => match opt_val.parse::<usize>() {
            Ok(n) if (1..=MAX_MEM_MIB).contains(&n) => {
                // Convert from MiB to bytes internally for convenience
                options.mem_bytes = n * 1024 * 1024;
            }
            _ => return None,
        },

        ("exec-mem-size", _) => match opt_val.parse::<usize>() {
            Ok(n) if (1..=MAX_MEM_MIB).contains(&n) => {
                // Convert from MiB to bytes internally for convenience
                options.exec_mem_bytes = n * 1024 * 1024;
            }
            _ => return None,
        },

        ("call-threshold", _) => match opt_val.parse() {
            Ok(n) => {
                unsafe { rb_zjit_call_threshold = n; }
                update_profile_threshold();
            },
            Err(_) => return None,
        },

        ("num-profiles", _) => match opt_val.parse() {
            Ok(n) => {
                options.num_profiles = n;
                update_profile_threshold();
            },
            Err(_) => return None,
        },


        ("stats-quiet", _) => {
            options.stats = true;
            options.print_stats = false;
        }

        ("stats", "") => {
            options.stats = true;
            options.print_stats = true;
        }
        ("stats", path) => {
            // Truncate the file if it exists
            std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(path)
                .map_err(|e| eprintln!("Failed to open file '{}': {}", path, e))
                .ok();
            let canonical_path = std::fs::canonicalize(opt_val).unwrap_or_else(|_| opt_val.into());
            options.stats = true;
            options.print_stats_file = Some(canonical_path);
        }

        ("trace-exits", exits) => {
            options.trace_side_exits = match exits {
                "" => Some(TraceExits::All),
                name => Some(Counter::get(name).map(TraceExits::Counter)?),
            }
        }

        ("trace-exits-sample-rate", sample_interval) => {
            // If not already set, then set it to `TraceExits::All` by default.
            if options.trace_side_exits.is_none() {
                options.trace_side_exits = Some(TraceExits::All);
            }
            // `sample_interval ` must provide a string that can be validly parsed to a `usize`.
            options.trace_side_exits_sample_interval = sample_interval.parse::<usize>().ok()?;
        }

        ("debug", "") => options.debug = true,

        ("disable", "") => options.disable = true,

        ("disable-hir-opt", "") => options.disable_hir_opt = true,

        // --zjit-dump-hir dumps the actual input to the codegen, which is currently the same as --zjit-dump-hir-opt.
        ("dump-hir" | "dump-hir-opt", "") => options.dump_hir_opt = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir" | "dump-hir-opt", "all") => options.dump_hir_opt = Some(DumpHIR::All),
        ("dump-hir" | "dump-hir-opt", "debug") => options.dump_hir_opt = Some(DumpHIR::Debug),

        ("dump-hir-init", "") => options.dump_hir_init = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir-init", "all") => options.dump_hir_init = Some(DumpHIR::All),
        ("dump-hir-init", "debug") => options.dump_hir_init = Some(DumpHIR::Debug),

        ("dump-hir-graphviz", "") => options.dump_hir_graphviz = Some("/dev/stderr".into()),
        ("dump-hir-graphviz", _) => {
            // Truncate the file if it exists
            std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(opt_val)
                .map_err(|e| eprintln!("Failed to open file '{opt_val}': {e}"))
                .ok();
            let opt_val = std::fs::canonicalize(opt_val).unwrap_or_else(|_| opt_val.into());
            options.dump_hir_graphviz = Some(opt_val);
        }

        ("dump-hir-iongraph", "") => options.dump_hir_iongraph = true,

        ("dump-lir", "") => options.dump_lir = Some(HashSet::from([DumpLIR::init])),
        ("dump-lir", filters) => {
            let mut dump_lirs = HashSet::new();
            for filter in filters.split(',') {
                let dump_lir = match filter {
                    "all" => {
                        for &dump_lir in DUMP_LIR_ALL {
                            dump_lirs.insert(dump_lir);
                        }
                        continue;
                    }
                    "init" => DumpLIR::init,
                    "split" => DumpLIR::split,
                    "alloc_regs" => DumpLIR::alloc_regs,
                    "compile_exits" => DumpLIR::compile_exits,
                    "scratch_split" => DumpLIR::scratch_split,
                    _ => {
                        let valid_options = DUMP_LIR_ALL.iter().map(|opt| format!("{opt:?}")).collect::<Vec<_>>().join(", ");
                        eprintln!("invalid --zjit-dump-lir option: '{filter}'");
                        eprintln!("valid --zjit-dump-lir options: all, {valid_options}");
                        return None;
                    }
                };
                dump_lirs.insert(dump_lir);
            }
            options.dump_lir = Some(dump_lirs);
        }

        ("dump-disasm", "") => options.dump_disasm = true,

        ("perf", "") => options.perf = true,

        ("allowed-iseqs", _) if !opt_val.is_empty() => options.allowed_iseqs = Some(parse_jit_list(opt_val)),
        ("log-compiled-iseqs", _) if !opt_val.is_empty() => {
            // Truncate the file if it exists
            std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(opt_val)
                .map_err(|e| eprintln!("Failed to open file '{opt_val}': {e}"))
                .ok();
            let opt_val = std::fs::canonicalize(opt_val).unwrap_or_else(|_| opt_val.into());
            options.log_compiled_iseqs = Some(opt_val);
        }

        _ => return None, // Option name not recognized
    }

    // Option successfully parsed
    Some(())
}

/// Update rb_zjit_profile_threshold based on rb_zjit_call_threshold and options.num_profiles
fn update_profile_threshold() {
    if unsafe { rb_zjit_call_threshold == 1 } {
        // If --zjit-call-threshold=1, never rewrite ISEQs to profile instructions.
        unsafe { rb_zjit_profile_threshold = 0; }
    } else {
        // Otherwise, profile instructions at least once.
        let num_profiles = get_option!(num_profiles);
        unsafe { rb_zjit_profile_threshold = rb_zjit_call_threshold.saturating_sub(num_profiles.into()).max(1) };
    }
}

/// Update --zjit-call-threshold for testing
#[cfg(test)]
pub fn set_call_threshold(call_threshold: CallThreshold) {
    unsafe { rb_zjit_call_threshold = call_threshold; }
    rb_zjit_prepare_options();
    update_profile_threshold();
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

/// Return true if ZJIT should be enabled at boot.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_option_enable() -> bool {
    if unsafe { OPTIONS.as_ref() }.is_some_and(|opts| !opts.disable) {
        true
    } else {
        false
    }
}

/// Return Qtrue if --zjit-stats has been specified.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_stats_enabled_p(_ec: EcPtr, _self: VALUE) -> VALUE {
    // Builtin zjit.rb calls this even if ZJIT is disabled, so OPTIONS may not be set.
    if unsafe { OPTIONS.as_ref() }.is_some_and(|opts| opts.stats) {
        Qtrue
    } else {
        Qfalse
    }
}

/// Return Qtrue if stats should be printed at exit.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_print_stats_p(_ec: EcPtr, _self: VALUE) -> VALUE {
    // Builtin zjit.rb calls this even if ZJIT is disabled, so OPTIONS may not be set.
    if unsafe { OPTIONS.as_ref() }.is_some_and(|opts| opts.stats && opts.print_stats) {
        Qtrue
    } else {
        Qfalse
    }
}

/// Return path if stats should be printed at exit to a specified file, else Qnil.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_get_stats_file_path_p(_ec: EcPtr, _self: VALUE) -> VALUE {
    if let Some(opts) = unsafe { OPTIONS.as_ref() } {
        if let Some(ref path) = opts.print_stats_file {
            return rust_str_to_ruby(path.as_os_str().to_str().unwrap());
        }
    }
    Qnil
}
