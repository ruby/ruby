use std::{ffi::CStr, os::raw::c_char};

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Dump all compiled instructions of target cb.
    pub dump_disasm: bool,
}

/// Macro to get an option value by name
#[cfg(feature = "disasm")]
macro_rules! get_option {
    // Unsafe is ok here because options are initialized
    // once before any Ruby code executes
    ($option_name:ident) => {
        {
            use crate::codegen::ZJITState;
            ZJITState::get_options().$option_name
        }
    };
}
#[cfg(feature = "disasm")]
pub(crate) use get_option;

/// Allocate Options on the heap, initialize it, and return the address of it.
/// The return value will be modified by rb_zjit_parse_option() and then
/// passed to rb_zjit_init() for initialization.
#[no_mangle]
pub extern "C" fn rb_zjit_init_options() -> *const u8 {
    let options = Options {
        dump_disasm: false,
    };
    Box::into_raw(Box::new(options)) as *const u8
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

        ("dump-disasm", "") => options.dump_disasm = true,

        // Option name not recognized
        _ => {
            return None;
        }
    }

    // Option successfully parsed
    return Some(());
}
