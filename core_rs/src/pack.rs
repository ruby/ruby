//! Rust ports of functions from pack.c (port unit `pack-A-01`).

use core::ffi::{c_char, c_int, c_long, c_short};

/// Checks endianness of the target platform.
pub fn is_bigendian_impl() -> c_int {
    if cfg!(target_endian = "big") { 1 } else { 0 }
}

/// Exported wrapper for `is_bigendian`.
#[unsafe(no_mangle)]
pub extern "C" fn rb_core_pack_is_bigendian() -> c_int {
    is_bigendian_impl()
}

/// Safe slice implementation of `skip_to_eol`.
pub fn skip_to_eol_impl(slice: &[u8]) -> usize {
    match slice.iter().position(|&b| b == b'\n') {
        Some(pos) => pos + 1,
        None => slice.len(),
    }
}

unsafe extern "C" {
    fn memchr(s: *const core::ffi::c_void, c: c_int, n: usize) -> *mut core::ffi::c_void;
}

/// Exported wrapper for `skip_to_eol`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_pack_skip_to_eol(
    p: *const c_char,
    pend: *const c_char,
) -> *mut c_char {
    // SAFETY: The caller guarantees that `p` and `pend` point to valid memory regions with `p <= pend`.
    if p.is_null() || pend <= p {
        return pend as *mut c_char;
    }
    let len = pend as usize - p as usize;
    let ptr = unsafe { memchr(p as *const _, b'\n' as c_int, len) };
    if ptr.is_null() {
        pend as *mut c_char
    } else {
        unsafe { (ptr as *mut c_char).add(1) }
    }
}

/// Returns alignment requirement for packing directives.
pub fn pack_alignof_impl(type_: c_char, natint: c_int) -> usize {
    let byte = type_ as u8;
    match byte {
        b'c' | b'C' => core::mem::align_of::<c_char>(),
        b's' | b'S' => {
            if natint != 0 {
                core::mem::align_of::<c_short>()
            } else {
                2
            }
        }
        b'i' | b'I' => core::mem::align_of::<c_int>(),
        b'l' | b'L' => {
            if natint != 0 {
                core::mem::align_of::<c_long>()
            } else {
                4
            }
        }
        b'q' | b'Q' => core::mem::align_of::<i64>(),
        b'j' => core::mem::align_of::<isize>(),
        b'J' => core::mem::align_of::<usize>(),
        b'n' | b'v' => core::mem::align_of::<u16>(),
        b'N' | b'V' => core::mem::align_of::<u32>(),
        b'f' | b'F' | b'e' | b'g' => core::mem::align_of::<f32>(),
        b'd' | b'D' | b'E' | b'G' => core::mem::align_of::<f64>(),
        b'p' | b'P' => core::mem::align_of::<*mut c_char>(),
        _ => 0,
    }
}

/// Exported wrapper for `pack_alignof`.
#[unsafe(no_mangle)]
pub extern "C" fn rb_core_pack_pack_alignof(type_: c_char, natint: c_int) -> usize {
    pack_alignof_impl(type_, natint)
}

/// Converts a hex character to its numeric value (0..15) or -1 if invalid.
pub fn hex2num_impl(c: c_char) -> c_int {
    let byte = c as u8;
    match byte {
        b'0'..=b'9' => (byte - b'0') as c_int,
        b'a'..=b'f' => (byte - b'a' + 10) as c_int,
        b'A'..=b'F' => (byte - b'A' + 10) as c_int,
        _ => -1,
    }
}

/// Exported wrapper for `hex2num`.
#[unsafe(no_mangle)]
pub extern "C" fn rb_core_pack_hex2num(c: c_char) -> c_int {
    hex2num_impl(c)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_bigendian() {
        let res = rb_core_pack_is_bigendian();
        assert!(res == 0 || res == 1);
    }

    #[test]
    fn test_skip_to_eol() {
        let s = b"hello\nworld\n";
        let pend = unsafe { s.as_ptr().add(s.len()) as *const c_char };
        let p1 = s.as_ptr() as *const c_char;
        let p2 = unsafe { rb_core_pack_skip_to_eol(p1, pend) };
        assert_eq!(unsafe { p2.offset_from(p1) }, 6);

        let p3 = unsafe { rb_core_pack_skip_to_eol(p2, pend) };
        assert_eq!(unsafe { p3.offset_from(p1) }, 12);

        let no_newline = b"no_newline";
        let pend2 = unsafe { no_newline.as_ptr().add(no_newline.len()) as *const c_char };
        let p4 = unsafe { rb_core_pack_skip_to_eol(no_newline.as_ptr() as *const c_char, pend2) };
        assert_eq!(p4 as *const c_char, pend2);
    }

    #[test]
    fn test_pack_alignof() {
        assert_eq!(rb_core_pack_pack_alignof(b'c' as c_char, 0), core::mem::align_of::<c_char>());
        assert_eq!(rb_core_pack_pack_alignof(b'C' as c_char, 0), core::mem::align_of::<c_char>());
        assert_eq!(rb_core_pack_pack_alignof(b's' as c_char, 0), 2);
        assert_eq!(rb_core_pack_pack_alignof(b's' as c_char, 1), core::mem::align_of::<c_short>());
        assert_eq!(rb_core_pack_pack_alignof(b'l' as c_char, 0), 4);
        assert_eq!(rb_core_pack_pack_alignof(b'l' as c_char, 1), core::mem::align_of::<c_long>());
        assert_eq!(rb_core_pack_pack_alignof(b'q' as c_char, 0), core::mem::align_of::<i64>());
        assert_eq!(rb_core_pack_pack_alignof(b'j' as c_char, 0), core::mem::align_of::<isize>());
        assert_eq!(rb_core_pack_pack_alignof(b'J' as c_char, 0), core::mem::align_of::<usize>());
        assert_eq!(rb_core_pack_pack_alignof(b'f' as c_char, 0), core::mem::align_of::<f32>());
        assert_eq!(rb_core_pack_pack_alignof(b'd' as c_char, 0), core::mem::align_of::<f64>());
        assert_eq!(rb_core_pack_pack_alignof(b'p' as c_char, 0), core::mem::align_of::<*mut c_char>());
        assert_eq!(rb_core_pack_pack_alignof(b'x' as c_char, 0), 0);
    }

    #[test]
    fn test_hex2num() {
        for c in b'0'..=b'9' {
            assert_eq!(rb_core_pack_hex2num(c as c_char), (c - b'0') as c_int);
        }
        for c in b'a'..=b'f' {
            assert_eq!(rb_core_pack_hex2num(c as c_char), (c - b'a' + 10) as c_int);
        }
        for c in b'A'..=b'F' {
            assert_eq!(rb_core_pack_hex2num(c as c_char), (c - b'A' + 10) as c_int);
        }
        assert_eq!(rb_core_pack_hex2num(b'g' as c_char), -1);
        assert_eq!(rb_core_pack_hex2num(b'G' as c_char), -1);
        assert_eq!(rb_core_pack_hex2num(b'x' as c_char), -1);
        assert_eq!(rb_core_pack_hex2num(b' ' as c_char), -1);
    }
}
