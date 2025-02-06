mod zjit;

extern "C" fn zjit_init() {
    println!("zjit_init");
}

#[no_mangle]
pub extern "C" fn rb_zjit_parse_option() -> bool {
    false
}
