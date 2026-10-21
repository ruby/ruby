//! Rust ports of functions from io_buffer.c (port unit `io_buffer-A-03`).
//!
//! `memory_or_inplace`, `memory_xor_inplace` and `memory_not_inplace` are
//! the byte loops behind `IO::Buffer#or!`, `#xor!` and `#not!`;
//! `memory_bit_count` is the population count behind `IO::Buffer#bit_count`.
//! They are `static` in io_buffer.c and still called from its unported C,
//! so they are exported as `rb_core_io_buffer_<name>` (hidden, see
//! internal/core_rs.h).

use core::ffi::c_uchar;

/// `base[i] |= mask[i % mask.len()]` for every byte of `base`: the mask is
/// applied cyclically, starting again at `mask[0]` after its last byte.
///
/// Precondition (as in C): `mask` is non-empty when `base` is non-empty.
/// The C divides by `mask_size`; its only caller rejects an empty mask with
/// `io_buffer_check_mask_size()` before calling.
pub fn memory_or_inplace_impl(base: &mut [u8], mask: &[u8]) {
    for (offset, byte) in base.iter_mut().enumerate() {
        *byte |= mask[offset % mask.len()];
    }
}

/// `base[i] ^= mask[i % mask.len()]` for every byte of `base`; the mask is
/// applied cyclically.  Same precondition as [`memory_or_inplace_impl`].
pub fn memory_xor_inplace_impl(base: &mut [u8], mask: &[u8]) {
    for (offset, byte) in base.iter_mut().enumerate() {
        *byte ^= mask[offset % mask.len()];
    }
}

/// `base[i] = ~base[i]` for every byte of `base`.
pub fn memory_not_inplace_impl(base: &mut [u8]) {
    for byte in base.iter_mut() {
        *byte = !*byte;
    }
}

/// Number of set bits in `base`.
///
/// Like the C, whole 8-byte words are counted first (`rb_popcount64`) and
/// the remaining `len % 8` bytes one at a time (`rb_popcount32`).  Every
/// variant of those helpers (`__builtin_popcount*`, `__popcnt*`, the SWAR
/// fallback) returns the exact population count, as `count_ones` does, and
/// a word's popcount does not depend on byte order, so the result is the
/// same on every target.  The C reads the words through a possibly
/// unaligned `const uint64_t *`; this reads them with `from_ne_bytes`.
/// The sum uses `wrapping_add` as `size_t` arithmetic does in C.
pub fn memory_bit_count_impl(base: &[u8]) -> usize {
    let mut count: usize = 0;

    let words = base.chunks_exact(8);
    let tail = words.remainder();
    for word in words {
        let w = u64::from_ne_bytes([
            word[0], word[1], word[2], word[3], word[4], word[5], word[6], word[7],
        ]);
        count = count.wrapping_add(w.count_ones() as usize);
    }

    for &byte in tail {
        count = count.wrapping_add((byte as u32).count_ones() as usize);
    }

    count
}

/// Exported wrapper for `memory_or_inplace`.
///
/// # Safety
/// As in C: when `size > 0`, `base` points to `size` writable bytes,
/// `mask_size > 0` and `mask` points to `mask_size` readable bytes, and the
/// two ranges do not overlap (`restrict`; the caller checks this with
/// `io_buffer_check_overlaps()`).  With `size == 0` neither pointer is
/// dereferenced and either may be NULL.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_io_buffer_memory_or_inplace(
    base: *mut c_uchar,
    size: usize,
    mask: *const c_uchar,
    mask_size: usize,
) {
    if size == 0 {
        return;
    }
    // SAFETY: size > 0, so by the precondition `base` is valid for `size`
    // writes, `mask` for `mask_size` (> 0) reads, and they do not overlap.
    let (base, mask) = unsafe {
        (
            core::slice::from_raw_parts_mut(base, size),
            core::slice::from_raw_parts(mask, mask_size),
        )
    };
    memory_or_inplace_impl(base, mask);
}

/// Exported wrapper for `memory_xor_inplace`.
///
/// # Safety
/// Same as [`rb_core_io_buffer_memory_or_inplace`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_io_buffer_memory_xor_inplace(
    base: *mut c_uchar,
    size: usize,
    mask: *const c_uchar,
    mask_size: usize,
) {
    if size == 0 {
        return;
    }
    // SAFETY: size > 0, so by the precondition `base` is valid for `size`
    // writes, `mask` for `mask_size` (> 0) reads, and they do not overlap.
    let (base, mask) = unsafe {
        (
            core::slice::from_raw_parts_mut(base, size),
            core::slice::from_raw_parts(mask, mask_size),
        )
    };
    memory_xor_inplace_impl(base, mask);
}

/// Exported wrapper for `memory_not_inplace`.
///
/// # Safety
/// As in C: when `size > 0`, `base` points to `size` writable bytes.  With
/// `size == 0` it is not dereferenced and may be NULL.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_io_buffer_memory_not_inplace(base: *mut c_uchar, size: usize) {
    if size == 0 {
        return;
    }
    // SAFETY: size > 0, so by the precondition `base` is valid for `size`
    // reads and writes.
    let base = unsafe { core::slice::from_raw_parts_mut(base, size) };
    memory_not_inplace_impl(base);
}

/// Exported wrapper for `memory_bit_count`.
///
/// # Safety
/// As in C: when `size > 0`, `base` points to `size` readable bytes.  With
/// `size == 0` it is not dereferenced and may be NULL (the C caller returns
/// before calling in that case).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_io_buffer_memory_bit_count(base: *const c_uchar, size: usize) -> usize {
    if size == 0 {
        return 0;
    }
    // SAFETY: size > 0, so by the precondition `base` is valid for `size`
    // reads.
    let base = unsafe { core::slice::from_raw_parts(base, size) };
    memory_bit_count_impl(base)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn or_applies_mask_cyclically() {
        // The example from io_buffer.c's documentation of IO::Buffer#or!.
        let mut buf = *b"1234567890";
        memory_or_inplace_impl(&mut buf, b"\xFF\x00\x00\xFF");
        assert_eq!(&buf, b"\xff23\xff\xff67\xff\xff0");

        let mut buf = *b"1234123412";
        memory_or_inplace_impl(&mut buf, b"133\x00");
        assert_eq!(&buf, b"1334133413");
    }

    #[test]
    fn xor_applies_mask_cyclically() {
        let mut buf = *b"1234567890";
        memory_xor_inplace_impl(&mut buf, b"\xFF\x00\x00\xFF");
        assert_eq!(&buf, b"\xce23\xcb\xca67\xc7\xc60");

        let mut buf = *b"1234123412";
        memory_xor_inplace_impl(&mut buf, b"133\x00");
        assert_eq!(&buf, b"\x00\x01\x004\x00\x01\x004\x00\x01");
    }

    #[test]
    fn mask_longer_than_base_uses_prefix() {
        let mut buf = [0u8; 3];
        memory_or_inplace_impl(&mut buf, b"\x01\x02\x04\x08\x10");
        assert_eq!(buf, [1, 2, 4]);
        memory_xor_inplace_impl(&mut buf, b"\x01\x02\x04\x08\x10");
        assert_eq!(buf, [0, 0, 0]);
    }

    #[test]
    fn not_inverts_every_byte() {
        let mut buf = *b"1234567890";
        memory_not_inplace_impl(&mut buf);
        assert_eq!(&buf, b"\xce\xcd\xcc\xcb\xca\xc9\xc8\xc7\xc6\xcf");
        memory_not_inplace_impl(&mut buf);
        assert_eq!(&buf, b"1234567890");
    }

    #[test]
    fn bit_count_matches_naive_count() {
        let mut data = [0u8; 40];
        let mut x: u32 = 0x1234_5678;
        for b in data.iter_mut() {
            x = x.wrapping_mul(1_103_515_245).wrapping_add(12345);
            *b = (x >> 16) as u8;
        }
        for start in 0..data.len() {
            for end in start..=data.len() {
                let s = &data[start..end];
                let naive: usize = s.iter().map(|b| b.count_ones() as usize).sum();
                assert_eq!(memory_bit_count_impl(s), naive);
            }
        }
        assert_eq!(memory_bit_count_impl(b"\xFF\x00\x0F"), 12);
        assert_eq!(memory_bit_count_impl(&[0xFF; 9]), 72);
        assert_eq!(memory_bit_count_impl(&[]), 0);
    }

    #[test]
    fn wrappers_accept_null_with_zero_size() {
        // SAFETY: size 0, so no pointer is dereferenced.
        unsafe {
            rb_core_io_buffer_memory_or_inplace(core::ptr::null_mut(), 0, core::ptr::null(), 0);
            rb_core_io_buffer_memory_xor_inplace(core::ptr::null_mut(), 0, core::ptr::null(), 0);
            rb_core_io_buffer_memory_not_inplace(core::ptr::null_mut(), 0);
            assert_eq!(rb_core_io_buffer_memory_bit_count(core::ptr::null(), 0), 0);
        }
    }

    #[test]
    fn wrappers_operate_on_buffers() {
        let mut buf = *b"abcdefgh";
        let mask = *b"\x20\x00";
        // SAFETY: buf and mask are valid, disjoint, and sized as passed.
        unsafe {
            rb_core_io_buffer_memory_xor_inplace(buf.as_mut_ptr(), buf.len(), mask.as_ptr(), mask.len());
            assert_eq!(&buf, b"AbCdEfGh");
            rb_core_io_buffer_memory_or_inplace(buf.as_mut_ptr(), buf.len(), mask.as_ptr(), mask.len());
            assert_eq!(&buf, b"abcdefgh");
            rb_core_io_buffer_memory_not_inplace(buf.as_mut_ptr(), buf.len());
            assert_eq!(rb_core_io_buffer_memory_bit_count(buf.as_ptr(), buf.len()), 64 - 29);
        }
    }
}
