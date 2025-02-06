#![allow(dead_code)]

mod cruby;
mod stats;
mod ir;

#[no_mangle]
pub extern "C" fn rb_zjit_init() {
    println!("zjit init");
}

#[no_mangle]
pub extern "C" fn rb_zjit_parse_option() -> bool {
    println!("parsing zjit options");
    false
}
