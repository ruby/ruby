#![allow(dead_code)]

mod cruby;
mod stats;
mod ir;

extern "C" fn zjit_init() {
    println!("zjit_init");
}

#[no_mangle]
pub extern "C" fn rb_zjit_parse_option() -> bool {
    println!("parsing zjit");
    false
}
