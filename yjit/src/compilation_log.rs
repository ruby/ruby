use crate::cruby::{EcPtr, Qfalse, Qtrue, VALUE};
use crate::options::*;
use crate::yjit::yjit_enabled_p;

/// Primitive called in yjit.rb
/// Check if compilation log generation is enabled
#[no_mangle]
pub extern "C" fn rb_yjit_compilation_log_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if get_option!(gen_compilation_log) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/// Primitive called in yjit.rb
/// Check if the compilation log should print at exit
#[no_mangle]
pub extern "C" fn rb_yjit_print_compilation_log_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if yjit_enabled_p() && get_option!(print_compilation_log) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}
