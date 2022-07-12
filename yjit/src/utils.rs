#![allow(dead_code)] // Some functions for print debugging in here

use crate::asm::x86_64::*;
use crate::asm::*;
use crate::cruby::*;
use std::slice;

/// Trait for casting to [usize] that allows you to say `.as_usize()`.
/// Implementation conditional on the the cast preserving the numeric value on
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

#[cfg(test)]
mod tests {
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
    (fn $f:ident $args:tt -> $ret:ty $body:block) => { fn $f $args -> $ret $body };
    (fn $f:ident $args:tt $body:block) => { fn $f $args $body };
}

#[cfg(target_arch = "x86_64")]
macro_rules! c_callable {
    (fn $f:ident $args:tt -> $ret:ty $body:block) => { extern "sysv64" fn $f $args -> $ret $body };
    (fn $f:ident $args:tt $body:block) => { extern "sysv64" fn $f $args $body };
}
pub(crate) use c_callable;

// Save caller-save registers on the stack before a C call
fn push_regs(cb: &mut CodeBlock) {
    push(cb, RAX);
    push(cb, RCX);
    push(cb, RDX);
    push(cb, RSI);
    push(cb, RDI);
    push(cb, R8);
    push(cb, R9);
    push(cb, R10);
    push(cb, R11);
    pushfq(cb);
}

// Restore caller-save registers from the after a C call
fn pop_regs(cb: &mut CodeBlock) {
    popfq(cb);
    pop(cb, R11);
    pop(cb, R10);
    pop(cb, R9);
    pop(cb, R8);
    pop(cb, RDI);
    pop(cb, RSI);
    pop(cb, RDX);
    pop(cb, RCX);
    pop(cb, RAX);
}

pub fn print_int(cb: &mut CodeBlock, opnd: X86Opnd) {
    c_callable!{
        fn print_int_fn(val: i64) {
            println!("{}", val);
        }
    }

    push_regs(cb);

    match opnd {
        X86Opnd::Mem(_) | X86Opnd::Reg(_) => {
            // Sign-extend the value if necessary
            if opnd.num_bits() < 64 {
                movsx(cb, C_ARG_REGS[0], opnd);
            } else {
                mov(cb, C_ARG_REGS[0], opnd);
            }
        }
        X86Opnd::Imm(_) | X86Opnd::UImm(_) => {
            mov(cb, C_ARG_REGS[0], opnd);
        }
        _ => unreachable!(),
    }

    mov(cb, RAX, const_ptr_opnd(print_int_fn as *const u8));
    call(cb, RAX);
    pop_regs(cb);
}

/// Generate code to print a pointer
pub fn print_ptr(cb: &mut CodeBlock, opnd: X86Opnd) {
    c_callable!{
        fn print_ptr_fn(ptr: *const u8) {
            println!("{:p}", ptr);
        }
    }

    assert!(opnd.num_bits() == 64);

    push_regs(cb);
    mov(cb, C_ARG_REGS[0], opnd);
    mov(cb, RAX, const_ptr_opnd(print_ptr_fn as *const u8));
    call(cb, RAX);
    pop_regs(cb);
}

/// Generate code to print a value
pub fn print_value(cb: &mut CodeBlock, opnd: X86Opnd) {
    c_callable!{
        fn print_value_fn(val: VALUE) {
            unsafe { rb_obj_info_dump(val) }
        }
    }

    assert!(opnd.num_bits() == 64);

    push_regs(cb);

    mov(cb, RDI, opnd);
    mov(cb, RAX, const_ptr_opnd(print_value_fn as *const u8));
    call(cb, RAX);

    pop_regs(cb);
}

/// Generate code to print constant string to stdout
pub fn print_str(cb: &mut CodeBlock, str: &str) {
    c_callable!{
        fn print_str_cfun(ptr: *const u8, num_bytes: usize) {
            unsafe {
                let slice = slice::from_raw_parts(ptr, num_bytes);
                let str = std::str::from_utf8(slice).unwrap();
                println!("{}", str);
            }
        }
    }

    let bytes = str.as_ptr();
    let num_bytes = str.len();

    push_regs(cb);

    // Load the string address and jump over the string data
    lea(cb, C_ARG_REGS[0], mem_opnd(8, RIP, 5));
    jmp32(cb, num_bytes as i32);

    // Write the string chars and a null terminator
    for i in 0..num_bytes {
        cb.write_byte(unsafe { *bytes.add(i) });
    }

    // Pass the string length as an argument
    mov(cb, C_ARG_REGS[1], uimm_opnd(num_bytes as u64));

    // Call the print function
    mov(cb, RAX, const_ptr_opnd(print_str_cfun as *const u8));
    call(cb, RAX);

    pop_regs(cb);
}
