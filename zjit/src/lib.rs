#![allow(dead_code)]

mod codegen;
mod cruby;
mod ir;
mod stats;
mod utils;
mod virtualmem;
use crate::cruby::*;

#[allow(non_upper_case_globals)]
#[no_mangle]
pub static mut rb_zjit_enabled_p: bool = false;
mod asm;

#[no_mangle]
pub extern "C" fn rb_zjit_init() {
    assert!(unsafe{ !rb_zjit_enabled_p });
    unsafe { rb_zjit_enabled_p = true; }
}

#[no_mangle]
pub extern "C" fn rb_zjit_parse_option() -> bool {
    println!("parsing zjit options");
    false
}

#[no_mangle]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    ir::iseq_to_ssa(iseq);
    std::ptr::null()
}
