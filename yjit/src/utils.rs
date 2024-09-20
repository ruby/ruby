#![allow(dead_code)] // Some functions for print debugging in here

use crate::backend::ir::*;
use crate::cruby::*;
use std::slice;

/// Trait for casting to [usize] that allows you to say `.as_usize()`.
/// Implementation conditional on the cast preserving the numeric value on
/// all inputs and being inexpensive.
///
/// [usize] is only guaranteed to be more than 16-bit wide, so we can't use
/// `.into()` to cast an `u32` or an `u64` to a `usize` even though in all
/// the platforms YJIT supports these two casts are pretty much no-ops.
/// We could say `as usize` or `.try_convert().unwrap()` everywhere
/// for those casts but they both have undesirable consequences if and when
/// we decide to support 32-bit platforms. Unfortunately we can't implement
/// [::core::convert::From] for [usize] since both the trait and the type are
/// external. Naming the method `into()` also runs into naming conflicts.
pub(crate) trait IntoUsize {
    /// Convert to usize. Implementation conditional on width of [usize].
    fn as_usize(self) -> usize;
}

#[cfg(target_pointer_width = "64")]
impl IntoUsize for u64 {
    fn as_usize(self) -> usize {
        self as usize
    }
}

#[cfg(target_pointer_width = "64")]
impl IntoUsize for u32 {
    fn as_usize(self) -> usize {
        self as usize
    }
}

impl IntoUsize for u16 {
    /// Alias for `.into()`. For convenience so you could use the trait for
    /// all unsgined types.
    fn as_usize(self) -> usize {
        self.into()
    }
}

impl IntoUsize for u8 {
    /// Alias for `.into()`. For convenience so you could use the trait for
    /// all unsgined types.
    fn as_usize(self) -> usize {
        self.into()
    }
}

/// The `Into<u64>` Rust does not provide.
/// Convert to u64 with assurance that the value is preserved.
/// Currently, `usize::BITS == 64` holds for all platforms we support.
pub(crate) trait IntoU64 {
    fn as_u64(self) -> u64;
}

#[cfg(target_pointer_width = "64")]
impl IntoU64 for usize {
    fn as_u64(self) -> u64 {
        self as u64
    }
}

/// Compute an offset in bytes of a given struct field
#[allow(unused)]
macro_rules! offset_of {
    ($struct_type:ty, $field_name:tt) => {{
        // This is basically the exact example for
        // "creating a pointer to uninitialized data" from `std::ptr::addr_of_mut`.
        // We make a dummy local that hopefully is optimized away because we never
        // read or write its contents. Doing this dance to avoid UB.
        let mut instance = std::mem::MaybeUninit::<$struct_type>::uninit();

        let base_ptr = instance.as_mut_ptr();
        let field_ptr = unsafe { std::ptr::addr_of_mut!((*base_ptr).$field_name) };

        (field_ptr as usize) - (base_ptr as usize)
    }};
}
#[allow(unused)]
pub(crate) use offset_of;

// Convert a CRuby UTF-8-encoded RSTRING into a Rust string.
// This should work fine on ASCII strings and anything else
// that is considered legal UTF-8, including embedded nulls.
pub fn ruby_str_to_rust(v: VALUE) -> String {
    let str_ptr = unsafe { rb_RSTRING_PTR(v) } as *mut u8;
    let str_len: usize = unsafe { rb_RSTRING_LEN(v) }.try_into().unwrap();
    let str_slice: &[u8] = unsafe { slice::from_raw_parts(str_ptr, str_len) };
    match String::from_utf8(str_slice.to_vec()) {
        Ok(utf8) => utf8,
        Err(_) => String::new(),
    }
}

// Location is the file defining the method, colon, method name.
// Filenames are sometimes internal strings supplied to eval,
// so be careful with them.
pub fn iseq_get_location(iseq: IseqPtr, pos: u16) -> String {
    let iseq_label = unsafe { rb_iseq_label(iseq) };
    let iseq_path = unsafe { rb_iseq_path(iseq) };
    let iseq_lineno = unsafe { rb_iseq_line_no(iseq, pos as usize) };

    let mut s = if iseq_label == Qnil {
        "None".to_string()
    } else {
        ruby_str_to_rust(iseq_label)
    };
    s.push_str("@");
    if iseq_path == Qnil {
        s.push_str("None");
    } else {
        s.push_str(&ruby_str_to_rust(iseq_path));
    }
    s.push_str(":");
    s.push_str(&iseq_lineno.to_string());
    s
}

// TODO: we may want to move this function into yjit.c, maybe add a convenient Rust-side wrapper
/*
// For debugging. Print the bytecode for an iseq.
RBIMPL_ATTR_MAYBE_UNUSED()
static void
yjit_print_iseq(const rb_iseq_t *iseq)
{
    char *ptr;
    long len;
    VALUE disassembly = rb_iseq_disasm(iseq);
    RSTRING_GETMEM(disassembly, ptr, len);
    fprintf(stderr, "%.*s\n", (int)len, ptr);
}
*/

#[cfg(target_arch = "aarch64")]
macro_rules! c_callable {
    ($(#[$outer:meta])*
    fn $f:ident $args:tt $(-> $ret:ty)? $body:block) => {
        $(#[$outer])*
        extern "C" fn $f $args $(-> $ret)? $body
    };
}

#[cfg(target_arch = "x86_64")]
macro_rules! c_callable {
    ($(#[$outer:meta])*
    fn $f:ident $args:tt $(-> $ret:ty)? $body:block) => {
        $(#[$outer])*
        extern "sysv64" fn $f $args $(-> $ret)? $body
    };
}
pub(crate) use c_callable;

pub fn print_int(asm: &mut Assembler, opnd: Opnd) {
    c_callable!{
        fn print_int_fn(val: i64) {
            println!("{}", val);
        }
    }

    asm.cpush_all();

    let argument = match opnd {
        Opnd::Mem(_) | Opnd::Reg(_) | Opnd::InsnOut { .. } => {
            // Sign-extend the value if necessary
            if opnd.rm_num_bits() < 64 {
                asm.load_sext(opnd)
            } else {
                opnd
            }
        },
        Opnd::Imm(_) | Opnd::UImm(_) => opnd,
        _ => unreachable!(),
    };

    asm.ccall(print_int_fn as *const u8, vec![argument]);
    asm.cpop_all();
}

/// Generate code to print a pointer
pub fn print_ptr(asm: &mut Assembler, opnd: Opnd) {
    c_callable!{
        fn print_ptr_fn(ptr: *const u8) {
            println!("{:p}", ptr);
        }
    }

    assert!(opnd.rm_num_bits() == 64);

    asm.cpush_all();
    asm.ccall(print_ptr_fn as *const u8, vec![opnd]);
    asm.cpop_all();
}

/// Generate code to print a value
pub fn print_value(asm: &mut Assembler, opnd: Opnd) {
    c_callable!{
        fn print_value_fn(val: VALUE) {
            unsafe { rb_obj_info_dump(val) }
        }
    }

    assert!(matches!(opnd, Opnd::Value(_)));

    asm.cpush_all();
    asm.ccall(print_value_fn as *const u8, vec![opnd]);
    asm.cpop_all();
}

/// Generate code to print constant string to stdout
pub fn print_str(asm: &mut Assembler, str: &str) {
    c_callable!{
        fn print_str_cfun(ptr: *const u8, num_bytes: usize) {
            unsafe {
                let slice = slice::from_raw_parts(ptr, num_bytes);
                let str = std::str::from_utf8(slice).unwrap();
                println!("{}", str);
            }
        }
    }

    asm.cpush_all();

    let string_data = asm.new_label("string_data");
    let after_string = asm.new_label("after_string");

    asm.jmp(after_string);
    asm.write_label(string_data);
    asm.bake_string(str);
    asm.write_label(after_string);

    let opnd = asm.lea_jump_target(string_data);
    asm.ccall(print_str_cfun as *const u8, vec![opnd, Opnd::UImm(str.len() as u64)]);

    asm.cpop_all();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::asm::CodeBlock;

    #[test]
    fn min_max_preserved_after_cast_to_usize() {
        use crate::utils::IntoUsize;

        let min: usize = u64::MIN.as_usize();
        assert_eq!(min, u64::MIN.try_into().unwrap());
        let max: usize = u64::MAX.as_usize();
        assert_eq!(max, u64::MAX.try_into().unwrap());

        let min: usize = u32::MIN.as_usize();
        assert_eq!(min, u32::MIN.try_into().unwrap());
        let max: usize = u32::MAX.as_usize();
        assert_eq!(max, u32::MAX.try_into().unwrap());
    }

    #[test]
    fn test_offset_of() {
        #[repr(C)]
        struct Foo {
            a: u8,
            b: u64,
        }

        assert_eq!(0, offset_of!(Foo, a), "C99 6.7.2.1p13 says no padding at the front");
        assert_eq!(8, offset_of!(Foo, b), "ABI dependent, but should hold");
    }

    #[test]
    fn test_print_int() {
        let mut asm = Assembler::new_without_iseq();
        let mut cb = CodeBlock::new_dummy(1024);

        print_int(&mut asm, Opnd::Imm(42));
        asm.compile(&mut cb, None).unwrap();
    }

    #[test]
    fn test_print_str() {
        let mut asm = Assembler::new_without_iseq();
        let mut cb = CodeBlock::new_dummy(1024);

        print_str(&mut asm, "Hello, world!");
        asm.compile(&mut cb, None).unwrap();
    }
}
