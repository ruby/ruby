use std::{ffi::{CStr, CString}, ptr::null};
use std::os::raw::{c_char, c_int, c_uint};
use crate::cruby::*;
use std::collections::HashSet;

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

/// ZJIT command-line options. This is set before rb_zjit_init() sets
/// ZJITState so that we can query some options while loading builtins.
pub static mut OPTIONS: Option<Options> = None;

#[derive(Clone, Debug)]
pub struct Options {
    /// Number of times YARV instructions should be profiled.
    pub num_profiles: u8,

    /// Enable YJIT statsitics
    pub stats: bool,

    /// Enable debug logging
    pub debug: bool,

    /// Turn off the HIR optimizer
    pub disable_hir_opt: bool,

    /// Dump initial High-level IR before optimization
    pub dump_hir_init: Option<DumpHIR>,

    /// Dump High-level IR after optimization, right before codegen.
    pub dump_hir_opt: Option<DumpHIR>,

    pub dump_hir_graphviz: bool,

    /// Dump low-level IR
    pub dump_lir: bool,

    /// Dump all compiled machine code.
    pub dump_disasm: bool,

    /// Dump code map to /tmp for performance profilers.
    pub perf: bool,

    /// List of ISEQs that can be compiled, identified by their iseq_get_location()
    pub allowed_iseqs: Option<HashSet<String>>,

    /// Path to a file where compiled ISEQs will be saved.
    pub log_compiled_iseqs: Option<String>,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            num_profiles: 1,
            stats: false,
            debug: false,
            disable_hir_opt: false,
            dump_hir_init: None,
            dump_hir_opt: None,
            dump_hir_graphviz: false,
            dump_lir: false,
            dump_disasm: false,
            perf: false,
            allowed_iseqs: None,
            log_compiled_iseqs: None,
        }
    }
}

/// `ruby --help` descriptions for user-facing options. Do not add options for ZJIT developers.
/// Note that --help allows only 80 chars per line, including indentation.    80-char limit --> |
pub const ZJIT_OPTIONS: &'static [(&str, &str)] = &[
    ("--zjit-call-threshold=num", "Number of calls to trigger JIT (default: 2)."),
    ("--zjit-num-profiles=num",   "Number of profiled calls before JIT (default: 1, max: 255)."),
    ("--zjit-stats",              "Enable collecting ZJIT statistics."),
    ("--zjit-perf",               "Dump ISEQ symbols into /tmp/perf-{}.map for Linux perf."),
    ("--zjit-log-compiled-iseqs=path",
                     "Log compiled ISEQs to the file. The file will be truncated."),
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
        eprintln!("Failed to read JIT list from '{}'", path_like);
    }
    eprintln!("JIT list:");
    for item in &result {
        eprintln!("  {}", item);
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

        ("stats", "") => {
            options.stats = true;
        }

        ("debug", "") => options.debug = true,

        ("disable-hir-opt", "") => options.disable_hir_opt = true,

        // --zjit-dump-hir dumps the actual input to the codegen, which is currently the same as --zjit-dump-hir-opt.
        ("dump-hir" | "dump-hir-opt", "") => options.dump_hir_opt = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir" | "dump-hir-opt", "all") => options.dump_hir_opt = Some(DumpHIR::All),
        ("dump-hir" | "dump-hir-opt", "debug") => options.dump_hir_opt = Some(DumpHIR::Debug),
        ("dump-hir-graphviz", "") => options.dump_hir_graphviz = true,

        ("dump-hir-init", "") => options.dump_hir_init = Some(DumpHIR::WithoutSnapshot),
        ("dump-hir-init", "all") => options.dump_hir_init = Some(DumpHIR::All),
        ("dump-hir-init", "debug") => options.dump_hir_init = Some(DumpHIR::Debug),

        ("dump-lir", "") => options.dump_lir = true,

        ("dump-disasm", "") => options.dump_disasm = true,

        ("perf", "") => options.perf = true,

        ("allowed-iseqs", _) if opt_val != "" => options.allowed_iseqs = Some(parse_jit_list(opt_val)),
        ("log-compiled-iseqs", _) if opt_val != "" => {
            // Truncate the file if it exists
            std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(opt_val)
                .map_err(|e| eprintln!("Failed to open file '{}': {}", opt_val, e))
                .ok();
            options.log_compiled_iseqs = Some(opt_val.into());
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
        let num_profiles = get_option!(num_profiles) as u64;
        unsafe { rb_zjit_profile_threshold = rb_zjit_call_threshold.saturating_sub(num_profiles).max(1) };
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

/// Return Qtrue if --zjit* has been specified. For the `#with_jit` hook,
/// this becomes Qtrue before ZJIT is actually initialized and enabled.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_option_enabled_p(_ec: EcPtr, _self: VALUE) -> VALUE {
    // If any --zjit* option is specified, OPTIONS becomes Some.
    if unsafe { OPTIONS.is_some() } {
        Qtrue
    } else {
        Qfalse
    }
}

/// Return Qtrue if --zjit-stats has been specified.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_stats_enabled_p(_ec: EcPtr, _self: VALUE) -> VALUE {
    // Builtin zjit.rb calls this even if ZJIT is disabled, so OPTIONS may not be set.
    if unsafe { OPTIONS.as_ref() }.map_or(false, |opts| opts.stats) {
        Qtrue
    } else {
        Qfalse
    }
}
