#[macro_use]
extern crate rb_sys;

use rb_sys::{
    rb_define_module, rb_define_module_function, rb_string_value_cstr, rb_utf8_str_new, VALUE,
};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_long};

ruby_extension!();

#[inline]
unsafe fn cstr_to_string(str: *const c_char) -> String {
    CStr::from_ptr(str).to_string_lossy().into_owned()
}

#[no_mangle]
unsafe extern "C" fn pub_reverse(_klass: VALUE, mut input: VALUE) -> VALUE {
    let ruby_string = cstr_to_string(rb_string_value_cstr(&mut input));
    let reversed = ruby_string.to_string().chars().rev().collect::<String>();
    let reversed_cstring = CString::new(reversed).unwrap();
    let size = ruby_string.len() as c_long;

    rb_utf8_str_new(reversed_cstring.as_ptr(), size)
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "C" fn Init_rust_ruby_example() {
    let name = CString::new("RustRubyExample").unwrap();
    let function_name = CString::new("reverse").unwrap();
    // bindgen does not properly detect the arity of the ruby callback function, so we have to transmute
    let callback = unsafe {
        std::mem::transmute::<
            unsafe extern "C" fn(VALUE, VALUE) -> VALUE,
            unsafe extern "C" fn() -> VALUE,
        >(pub_reverse)
    };
    let klass = unsafe { rb_define_module(name.as_ptr()) };

    unsafe { rb_define_module_function(klass, function_name.as_ptr(), Some(callback), 1) }
}
