#[macro_use]
extern crate rb_sys;

use rb_sys::{rb_define_module, rb_define_module_function, rb_utf8_str_new, VALUE};
use std::ffi::CString;

ruby_extension!();

#[no_mangle]
unsafe extern "C" fn say_hello(_klass: VALUE) -> VALUE {
    let cstr = CString::new("Hello world!").unwrap();

    rb_utf8_str_new(cstr.as_ptr(), 12)
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "C" fn Init_custom_name() {
    let name = CString::new("CustomName").unwrap();
    let function_name = CString::new("say_hello").unwrap();
    // bindgen does not properly detect the arity of the ruby callback function, so we have to transmute
    let callback = unsafe {
        std::mem::transmute::<unsafe extern "C" fn(VALUE) -> VALUE, unsafe extern "C" fn() -> VALUE>(
            say_hello,
        )
    };
    let klass = unsafe { rb_define_module(name.as_ptr()) };

    unsafe { rb_define_module_function(klass, function_name.as_ptr(), Some(callback), 0) }
}
