//! Ports of rational.c: the fixnum GCD and the scanner helpers that
//! `String#to_r` and `Rational("...")` use (port unit `rational-A-01` of
//! `tool/core_rs/inventory.rb`).
//!
//! These are `static` functions in C, so they are not public API.  The ones
//! that the remaining C (`f_gcd_normal`, `f_addsub`, `f_muldiv`, `read_num`,
//! `parse_rat`) still calls are exported as `rb_core_rational_<name>` and
//! declared hidden in `internal/core_rs.h`, which keeps them out of
//! libruby's dynamic symbol table.  `issign` is only called by `read_sign`
//! and stays private to this module.
//!
//! Unlike complex.c's scanner, rational.c's walks a counted string: the
//! functions take an end pointer `e` and never read at or past it.  The safe
//! core below works on the slice `[s, e)`.

use core::ffi::{c_char, c_int, c_long, c_ulong};

unsafe extern "C" {
    // The C library's isspace(), called exactly as the C code does (it
    // depends on the LC_CTYPE locale Ruby sets).
    fn isspace(c: c_int) -> c_int;
}

/// `i_gcd()`: binary GCD of `|x|` and `|y|`.
///
/// Precondition (as in C): neither argument is `LONG_MIN`; `-x` would be
/// signed overflow, which is undefined behaviour in C.  Every C caller
/// passes `FIX2LONG()` values, which are far inside the range.  The
/// negation wraps here so that no input can panic; for `LONG_MIN` this
/// gives the two's-complement result an unoptimised C build computes.
pub fn i_gcd(mut x: c_long, mut y: c_long) -> c_long {
    if x < 0 {
        x = x.wrapping_neg();
    }
    if y < 0 {
        y = y.wrapping_neg();
    }

    if x == 0 {
        return y;
    }
    if y == 0 {
        return x;
    }

    let mut u = x as c_ulong;
    let mut v = y as c_ulong;
    // u and v are both non-zero here, so shift stays below the bit width.
    let mut shift: u32 = 0;
    while ((u | v) & 1) == 0 {
        u >>= 1;
        v >>= 1;
        shift += 1;
    }

    while (u & 1) == 0 {
        u >>= 1;
    }

    loop {
        while (v & 1) == 0 {
            v >>= 1;
        }

        if u > v {
            core::mem::swap(&mut u, &mut v);
        }
        // u <= v after the swap, so this never underflows.
        v -= u;
        if v == 0 {
            break;
        }
    }

    // `(long)(u << shift)`: the conversion wraps, as in C.
    (u << shift) as c_long
}

/// `issign()`.
fn issign(c: c_int) -> bool {
    c == b'-' as c_int || c == b'+' as c_int
}

/// `islettere()`.
pub fn islettere(c: c_int) -> bool {
    c == b'e' as c_int || c == b'E' as c_int
}

/// `isletterr()`.
pub fn isletterr(c: c_int) -> bool {
    c == b'r' as c_int || c == b'R' as c_int
}

/// `read_sign()` over `rest` = `[*s, e)`: returns the sign character and
/// the number of bytes consumed (0 or 1).  The sign is `'?'` when there is
/// no leading `+`/`-`.
pub fn read_sign(rest: &[u8]) -> (c_int, usize) {
    match rest.first() {
        // `issign(**s)` and `sign = **s` promote a C `char`; for '+'/'-'
        // the value is the same whatever the signedness of `char`.
        Some(&b) if issign(b as c_char as c_int) => (b as c_char as c_int, 1),
        _ => (b'?' as c_int, 0),
    }
}

/// `skip_ws()` over `rest` = `[s, e)`: the number of leading bytes for
/// which `isspace((unsigned char)c)` is true.
pub fn skip_ws(rest: &[u8]) -> usize {
    let mut n = 0;
    // SAFETY: isspace() accepts any unsigned char value.
    while n < rest.len() && unsafe { isspace(rest[n] as c_int) } != 0 {
        n += 1;
    }
    n
}

// ---- C ABI ------------------------------------------------------------------

/// The bytes `[s, e)`, or an empty slice when `s >= e` (the C loops test
/// `s < e` first and so read nothing in that case).
///
/// # Safety
/// `s` and `e` point into (or one past) the same object, and when `s < e`
/// every byte of `[s, e)` is readable.
unsafe fn range<'a>(s: *const c_char, e: *const c_char) -> &'a [u8] {
    if s < e {
        // SAFETY: per the contract; s < e, so the length is positive.
        unsafe { core::slice::from_raw_parts(s as *const u8, e as usize - s as usize) }
    } else {
        &[]
    }
}

/// Port of `i_gcd()` (rational.c).  See [`i_gcd`] for the precondition.
#[unsafe(no_mangle)]
pub extern "C" fn rb_core_rational_i_gcd(x: c_long, y: c_long) -> c_long {
    i_gcd(x, y)
}

/// Port of `read_sign()` (rational.c).
///
/// # Safety
/// `s` is valid; `*s` and `e` satisfy the contract of [`range`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_rational_read_sign(s: *mut *const c_char, e: *const c_char) -> c_int {
    // SAFETY: per the contract.
    let start = unsafe { *s };
    // SAFETY: per the contract.
    let (sign, n) = read_sign(unsafe { range(start, e) });
    if n != 0 {
        // SAFETY: n <= e - *s, so the pointer stays within [*s, e].
        unsafe { *s = start.add(n) };
    }
    sign
}

/// Port of `islettere()` (rational.c).
#[unsafe(no_mangle)]
pub extern "C" fn rb_core_rational_islettere(c: c_int) -> c_int {
    islettere(c) as c_int
}

/// Port of `isletterr()` (rational.c).
#[unsafe(no_mangle)]
pub extern "C" fn rb_core_rational_isletterr(c: c_int) -> c_int {
    isletterr(c) as c_int
}

/// Port of `skip_ws()` (rational.c).
///
/// # Safety
/// `s` and `e` satisfy the contract of [`range`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_rational_skip_ws(s: *const c_char, e: *const c_char) -> *const c_char {
    // SAFETY: per the contract.
    let n = skip_ws(unsafe { range(s, e) });
    // SAFETY: n <= e - s (or 0), so the pointer stays within [s, e].
    unsafe { s.add(n) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gcd() {
        assert_eq!(i_gcd(0, 0), 0);
        assert_eq!(i_gcd(0, -7), 7);
        assert_eq!(i_gcd(-9, 0), 9);
        assert_eq!(i_gcd(12, 18), 6);
        assert_eq!(i_gcd(-12, 18), 6);
        assert_eq!(i_gcd(12, -18), 6);
        assert_eq!(i_gcd(17, 5), 1);
        assert_eq!(i_gcd(1 << 40, 1 << 20), 1 << 20);
        assert_eq!(i_gcd(c_long::MAX, c_long::MAX), c_long::MAX);
        assert_eq!(i_gcd((1 << 62) - 1, 3), 3);
        assert_eq!(rb_core_rational_i_gcd(-(1 << 62), 6), 2);
    }

    #[test]
    fn predicates() {
        assert!(islettere(b'e' as c_int) && islettere(b'E' as c_int) && !islettere(b'r' as c_int));
        assert!(isletterr(b'r' as c_int) && isletterr(b'R' as c_int) && !isletterr(b'e' as c_int));
        assert!(issign(b'+' as c_int) && issign(b'-' as c_int) && !issign(b'*' as c_int));
        assert_eq!(rb_core_rational_islettere(b'E' as c_int), 1);
        assert_eq!(rb_core_rational_isletterr(-0x72), 0);
    }

    #[test]
    fn sign_and_ws() {
        assert_eq!(read_sign(b"-1"), (b'-' as c_int, 1));
        assert_eq!(read_sign(b"+"), (b'+' as c_int, 1));
        assert_eq!(read_sign(b"1"), (b'?' as c_int, 0));
        assert_eq!(read_sign(b""), (b'?' as c_int, 0));
        assert_eq!(skip_ws(b" \t\n\x0b\x0c\r1 "), 6);
        assert_eq!(skip_ws(b"   "), 3);
        assert_eq!(skip_ws(b""), 0);

        let buf = b"  -5";
        let p = buf.as_ptr() as *const c_char;
        // SAFETY: all pointers are within buf.
        unsafe {
            let e = p.add(buf.len());
            let mut s = rb_core_rational_skip_ws(p, e);
            assert_eq!(s.offset_from(p), 2);
            assert_eq!(rb_core_rational_read_sign(&mut s, e), b'-' as c_int);
            assert_eq!(s.offset_from(p), 3);
            // The end pointer bounds the scan.
            let mut s2 = p.add(2);
            assert_eq!(rb_core_rational_read_sign(&mut s2, p.add(2)), b'?' as c_int);
            assert_eq!(s2, p.add(2));
            assert_eq!(rb_core_rational_skip_ws(p, p.add(1)), p.add(1));
            // s > e reads nothing.
            assert_eq!(rb_core_rational_skip_ws(p.add(1), p), p.add(1));
        }
    }
}
