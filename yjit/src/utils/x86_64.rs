#![allow(dead_code)] // Some functions for print debugging in here

use crate::asm::*;
use crate::cruby::*;
use std::slice;

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

pub fn print_int(cb: &mut CodeBlock, opnd: YJitOpnd) {
    extern "C" fn print_int_fn(val: i64) {
        println!("{}", val);
    }

    push_regs(cb);

    match opnd {
        YJitOpnd::Mem(_) | YJitOpnd::Reg(_) => {
            // Sign-extend the value if necessary
            if opnd.num_bits() < 64 {
                movsx(cb, C_ARG_REGS[0], opnd);
            } else {
                mov(cb, C_ARG_REGS[0], opnd);
            }
        }
        YJitOpnd::Imm(_) | YJitOpnd::UImm(_) => {
            mov(cb, C_ARG_REGS[0], opnd);
        }
        _ => unreachable!(),
    }

    mov(cb, RAX, const_ptr_opnd(print_int_fn as *const u8));
    call(cb, RAX);
    pop_regs(cb);
}

/// Generate code to print a pointer
pub fn print_ptr(cb: &mut CodeBlock, opnd: YJitOpnd) {
    extern "C" fn print_ptr_fn(ptr: *const u8) {
        println!("{:p}", ptr);
    }

    assert!(opnd.num_bits() == 64);

    push_regs(cb);
    mov(cb, C_ARG_REGS[0], opnd);
    mov(cb, RAX, const_ptr_opnd(print_ptr_fn as *const u8));
    call(cb, RAX);
    pop_regs(cb);
}

/// Generate code to print a value
pub fn print_value(cb: &mut CodeBlock, opnd: YJitOpnd) {
    extern "C" fn print_value_fn(val: VALUE) {
        unsafe { rb_obj_info_dump(val) }
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
    extern "C" fn print_str_cfun(ptr: *const u8, num_bytes: usize) {
        unsafe {
            let slice = slice::from_raw_parts(ptr, num_bytes);
            let str = std::str::from_utf8(slice).unwrap();
            println!("{}", str);
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
