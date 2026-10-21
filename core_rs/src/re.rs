//! Ports of re.c: byte-string search and ASCII case-insensitive compare,
//! and the Unicode range check of the regexp source unescaper (port unit
//! `re-A-02`).
//!
//! Public C API (include/ruby/internal/encoding/string.h and
//! include/ruby/internal/intern/re.h): `rb_memsearch`, `rb_memcicmp`.
//! `rb_memsearch` is behind String#index, #include?, #start_with?-style
//! scans, #split, #sub/#gsub with string patterns, and more.
//!
//! Faithfulness note.  The C Quick Search loops compute the next shift from
//! the byte *after* the current window even at the last window (reading the
//! string's terminator), and the UTF-8 variant hashes up to three further
//! bytes, which can lie past the end of either string when it ends in a
//! truncated multibyte character.  The ports below never read outside the
//! two strings: they stop at the last window (the shift could not change the
//! result there) and treat bytes past the end as 0, which is what C reads
//! when the strings are NUL-terminated.  Results are identical whenever the C
//! result does not depend on memory beyond the strings.

use core::ffi::{c_char, c_int, c_long, c_ulong, c_void};

/// The leading fields of `OnigEncodingTypeST` (include/ruby/onigmo.h), which
/// is public ABI.  Only `min_enc_len` is read.
#[repr(C)]
struct OnigEncodingHead {
    precise_mbc_enc_len: *const c_void,
    name: *const c_char,
    max_enc_len: c_int,
    min_enc_len: c_int,
}

unsafe extern "C" {
    fn rb_utf8_encoding() -> *const c_void;
    #[cfg(not(target_vendor = "apple"))]
    fn memmem(haystack: *const c_void, hlen: usize, needle: *const c_void, nlen: usize) -> *mut c_void;
}

const VALUE_BYTES: usize = core::mem::size_of::<usize>();

/// `casetable[b]` in re.c: ASCII upper case to lower case, all else
/// unchanged.  The C table is `const char[]`, so entries >= 0x80 are
/// negative where `char` is signed (x86) and positive where it is unsigned
/// (e.g. AArch64 Linux); `c_char` reproduces exactly that.
#[inline]
fn fold(b: u8) -> c_int {
    b.to_ascii_lowercase() as c_char as c_int
}

/// Safe core of `rb_memcicmp`.
pub fn memcicmp(x: &[u8], y: &[u8]) -> c_int {
    for (&a, &b) in x.iter().zip(y) {
        let d = fold(a) - fold(b);
        if d != 0 {
            return d;
        }
    }
    0
}

/// Port of `rb_memcicmp()` (re.c).
///
/// # Safety
/// `x` and `y` are readable for `len` bytes.  (C loops forever on a
/// negative `len`; this returns 0 instead.)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_memcicmp(x: *const c_void, y: *const c_void, len: c_long) -> c_int {
    if len <= 0 {
        return 0;
    }
    let len = len as usize;
    // SAFETY: readable for `len` bytes per the contract.
    let (x, y) = unsafe {
        (core::slice::from_raw_parts(x as *const u8, len), core::slice::from_raw_parts(y as *const u8, len))
    };
    memcicmp(x, y)
}

/// Byte `i` of `s`, or 0 past the end (see the module note).
#[inline]
fn at(s: &[u8], i: usize) -> u8 {
    s.get(i).copied().unwrap_or(0)
}

/// `rb_memsearch_ss` for platforms without a usable memmem (re.c uses it on
/// Apple): first byte via memchr, then a rolling hash of up to
/// `size_of::<VALUE>()` bytes.  Requires `2 <= x.len() <= VALUE_BYTES` and
/// `x.len() < y.len()`.
pub fn search_ss_rolling(x: &[u8], y: &[u8]) -> c_long {
    let (m, n) = (x.len(), y.len());
    debug_assert!((2..=VALUE_BYTES).contains(&m) && m < n);
    let mask = usize::MAX >> ((VALUE_BYTES - m) * 8);

    let Some(mut yi) = y[..n - m + 1].iter().position(|&b| b == x[0]) else {
        return -1;
    };
    let mut hx: usize = 0;
    let mut hy: usize = 0;
    for k in 0..m {
        hx = (hx << 8) | x[k] as usize;
        hy = (hy << 8) | y[yi + k] as usize;
    }
    yi += m;
    while hx != hy {
        if yi == n {
            return -1;
        }
        hy = ((hy << 8) | y[yi] as usize) & mask;
        yi += 1;
    }
    (yi - m) as c_long
}

/// `rb_memsearch_ss` where re.c uses the C library's memmem.
#[cfg(not(target_vendor = "apple"))]
fn search_ss(x: &[u8], y: &[u8]) -> c_long {
    // SAFETY: both slices are valid for their lengths.
    let p = unsafe { memmem(y.as_ptr() as *const c_void, y.len(), x.as_ptr() as *const c_void, x.len()) };
    if p.is_null() { -1 } else { (p as usize - y.as_ptr() as usize) as c_long }
}

#[cfg(target_vendor = "apple")]
fn search_ss(x: &[u8], y: &[u8]) -> c_long {
    search_ss_rolling(x, y)
}

/// `rb_memsearch_qs`: Quick Search (Sunday).  Requires `1 <= m < n`.
pub fn search_qs(x: &[u8], y: &[u8]) -> c_long {
    let (m, n) = (x.len(), y.len());
    let mut table = [m + 1; 256];
    for (i, &b) in x.iter().enumerate() {
        table[b as usize] = m - i;
    }
    let mut pos = 0;
    while pos + m <= n {
        if x[0] == y[pos] && x == &y[pos..pos + m] {
            return pos as c_long;
        }
        if pos + m == n {
            break;
        }
        pos += table[y[pos + m] as usize];
    }
    -1
}

/// `rb_memsearch_qs_utf8_hash`, reading bytes at `s[i..i+4]`.
pub fn qs_utf8_hash(s: &[u8], i: usize) -> usize {
    const MIX: u32 = 8353;
    let mut h = at(s, i) as u32;
    if h < 0xC0 {
        return h as usize + 256;
    } else if h < 0xE0 {
        h = h.wrapping_mul(MIX).wrapping_add(at(s, i + 1) as u32);
    } else if h < 0xF0 {
        h = h.wrapping_mul(MIX).wrapping_add(at(s, i + 1) as u32);
        h = h.wrapping_mul(MIX).wrapping_add(at(s, i + 2) as u32);
    } else if h < 0xF5 {
        h = h.wrapping_mul(MIX).wrapping_add(at(s, i + 1) as u32);
        h = h.wrapping_mul(MIX).wrapping_add(at(s, i + 2) as u32);
        h = h.wrapping_mul(MIX).wrapping_add(at(s, i + 3) as u32);
    } else {
        return h as usize + 256;
    }
    (h as u8) as usize
}

/// `rb_memsearch_qs_utf8`: Quick Search with a UTF-8 character hash.
/// Requires `1 <= m < n`.
pub fn search_qs_utf8(x: &[u8], y: &[u8]) -> c_long {
    let (m, n) = (x.len(), y.len());
    let mut table = [m + 1; 512];
    for i in 0..m {
        table[qs_utf8_hash(x, i)] = m - i;
    }
    let mut pos = 0;
    while pos + m <= n {
        if x[0] == y[pos] && x == &y[pos..pos + m] {
            return pos as c_long;
        }
        if pos + m == n {
            break;
        }
        pos += table[qs_utf8_hash(y, pos + m)];
    }
    -1
}

/// `rb_memsearch_with_char_size`: candidate positions are multiples of
/// `char_size` (UTF-16/UTF-32 code units).  Requires `1 <= m < n`.
pub fn search_char_size(x: &[u8], y: &[u8], char_size: usize) -> c_long {
    let (m, n) = (x.len(), y.len());
    let mut pos = 0;
    while pos + m <= n {
        if x[0] == y[pos] && x[1..] == y[pos + 1..pos + m] {
            return pos as c_long;
        }
        pos += char_size;
    }
    -1
}

/// Port of `rb_memsearch()` (re.c).
///
/// # Safety
/// `x0` is readable for `m` bytes and `y0` for `n` bytes; `enc` is a valid
/// encoding whenever `1 < m < n` (it is not read otherwise, as in C).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_memsearch(
    x0: *const c_void,
    m: c_long,
    y0: *const c_void,
    n: c_long,
    enc: *const c_void,
) -> c_long {
    if m > n {
        return -1;
    }
    if m == n {
        if m <= 0 {
            return 0; // memcmp of zero bytes
        }
        // SAFETY: both readable for m == n bytes.
        let (x, y) = unsafe {
            (
                core::slice::from_raw_parts(x0 as *const u8, m as usize),
                core::slice::from_raw_parts(y0 as *const u8, n as usize),
            )
        };
        return if x == y { 0 } else { -1 };
    }
    if m < 1 {
        return 0;
    }
    // Here 1 <= m < n.
    // SAFETY: readable for m and n bytes per the contract.
    let (x, y) = unsafe {
        (
            core::slice::from_raw_parts(x0 as *const u8, m as usize),
            core::slice::from_raw_parts(y0 as *const u8, n as usize),
        )
    };
    if m == 1 {
        return match y.iter().position(|&b| b == x[0]) {
            Some(i) => i as c_long,
            None => -1,
        };
    }
    // SAFETY: `enc` points to an encoding; only its public head is read.
    let mbminlen = unsafe { (*(enc as *const OnigEncodingHead)).min_enc_len };
    match mbminlen {
        1 => {
            if x.len() <= VALUE_BYTES {
                return search_ss(x, y);
            }
            // SAFETY: plain function call returning a static encoding.
            if enc == unsafe { rb_utf8_encoding() } {
                return search_qs_utf8(x, y);
            }
        }
        2 => return search_char_size(x, y, 2),
        4 => return search_char_size(x, y, 4),
        _ => {}
    }
    search_qs(x, y)
}

/// `ONIG_MAX_ERROR_MESSAGE_LEN` (include/ruby/onigmo.h): the size of re.c's
/// `onig_errmsg_buffer`.
pub const ONIG_MAX_ERROR_MESSAGE_LEN: usize = 90;

/// The message `check_unicode_range` copies with `errcpy`, NUL included.
const INVALID_UNICODE_RANGE: &[u8] = b"invalid Unicode range\0";

/// Safe core of re.c's `check_unicode_range`: -1 for a surrogate
/// (U+D800..U+DFFF) or a value above U+10FFFF, after copying
/// "invalid Unicode range" into `err` exactly as `errcpy` (`strlcpy` with
/// the buffer size) does: the message and its NUL, nothing after it.
/// Otherwise 0, and `err` is untouched.
pub fn check_unicode_range(code: c_ulong, err: &mut [u8; ONIG_MAX_ERROR_MESSAGE_LEN]) -> c_int {
    if (0xd800..=0xdfff).contains(&code) || 0x10ffff < code {
        err[..INVALID_UNICODE_RANGE.len()].copy_from_slice(INVALID_UNICODE_RANGE);
        return -1;
    }
    0
}

/// C boundary for re.c's `static int check_unicode_range(unsigned long code,
/// onig_errmsg_buffer err)`, called by `append_utf8` and
/// `unescape_unicode_list` through `#define check_unicode_range
/// rb_core_re_check_unicode_range` (declared hidden in internal/core_rs.h).
///
/// # Safety
///
/// `err` must point to a writable `onig_errmsg_buffer`
/// (`char[ONIG_MAX_ERROR_MESSAGE_LEN]`), as every caller in re.c passes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_re_check_unicode_range(code: c_ulong, err: *mut c_char) -> c_int {
    // SAFETY: per the contract `err` is a writable buffer of
    // ONIG_MAX_ERROR_MESSAGE_LEN bytes, so it can be viewed as that array.
    let err = unsafe { &mut *(err as *mut [u8; ONIG_MAX_ERROR_MESSAGE_LEN]) };
    check_unicode_range(code, err)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn naive(x: &[u8], y: &[u8]) -> c_long {
        y.windows(x.len()).position(|w| w == x).map_or(-1, |p| p as c_long)
    }

    fn lcg(seed: &mut u64) -> u64 {
        *seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        *seed >> 33
    }

    #[test]
    fn memcicmp_folds_ascii_only() {
        assert_eq!(memcicmp(b"Hello", b"hELLO"), 0);
        assert_eq!(memcicmp(b"a", b"b"), -1);
        assert_eq!(memcicmp(b"[", b"{"), b'[' as c_int - b'{' as c_int);
        // Non-ASCII bytes are not folded; they compare as C `char` values.
        let (c9, e9) = ("\u{c9}".as_bytes()[1], "\u{e9}".as_bytes()[1]);
        assert_eq!(memcicmp("\u{c9}".as_bytes(), "\u{e9}".as_bytes()), c9 as c_char as c_int - e9 as c_char as c_int);
        assert_eq!(memcicmp(b"\xff", b"a"), 0xffu8 as c_char as c_int - b'a' as c_int);
    }

    #[test]
    fn single_byte_searches_find_first_occurrence() {
        let mut seed = 42;
        for _ in 0..20000 {
            let n = 3 + (lcg(&mut seed) % 40) as usize;
            let m = 2 + (lcg(&mut seed) % (n as u64 - 1)) as usize;
            let m = m.min(n - 1);
            let alpha = b"abAB\0\xff";
            let y: Vec<u8> = (0..n).map(|_| alpha[(lcg(&mut seed) % 6) as usize]).collect();
            let x: Vec<u8> = if lcg(&mut seed) % 2 == 0 {
                let s = (lcg(&mut seed) % (n - m + 1) as u64) as usize;
                y[s..s + m].to_vec()
            } else {
                (0..m).map(|_| alpha[(lcg(&mut seed) % 6) as usize]).collect()
            };
            let want = naive(&x, &y);
            assert_eq!(search_qs(&x, &y), want);
            if m <= VALUE_BYTES {
                assert_eq!(search_ss_rolling(&x, &y), want, "rolling {x:?} in {y:?}");
            }
        }
    }

    #[test]
    fn utf8_search_matches_naive_on_valid_utf8() {
        let words = ["a", "\u{e9}", "\u{3042}", "\u{1F600}", "b", "\u{e8}"];
        let mut seed = 7;
        for _ in 0..20000 {
            let mut y = String::new();
            for _ in 0..(1 + lcg(&mut seed) % 12) {
                y.push_str(words[(lcg(&mut seed) % 6) as usize]);
            }
            let mut x = String::new();
            for _ in 0..(1 + lcg(&mut seed) % 4) {
                x.push_str(words[(lcg(&mut seed) % 6) as usize]);
            }
            if x.len() >= y.len() {
                continue;
            }
            assert_eq!(search_qs_utf8(x.as_bytes(), y.as_bytes()), naive(x.as_bytes(), y.as_bytes()));
        }
    }

    #[test]
    fn char_size_search_is_aligned() {
        // UTF-16LE "a b a" = 61 00 62 00 61 00: "b" is found at offset 2.
        assert_eq!(search_char_size(&[0x62, 0x00], &[0x61, 0x00, 0x62, 0x00, 0x61, 0x00], 2), 2);
        // 61 00 occurs only at the odd offset 1, which is not a code unit start.
        assert_eq!(search_char_size(&[0x61, 0x00], &[0x00, 0x61, 0x00, 0x62, 0x00, 0x00], 2), -1);
    }

    #[test]
    fn unicode_range_rejects_surrogates_and_beyond_max() {
        let msg = b"invalid Unicode range\0";
        for &code in &[0xd800, 0xdabc, 0xdfff, 0x110000, 0x7fff_ffff, c_ulong::MAX] {
            let mut err = [0xaau8; ONIG_MAX_ERROR_MESSAGE_LEN];
            assert_eq!(check_unicode_range(code, &mut err), -1, "{code:#x}");
            assert_eq!(&err[..msg.len()], msg);
            assert!(err[msg.len()..].iter().all(|&b| b == 0xaa), "nothing written after the NUL");
        }
        for &code in &[0, 0x41, 0xd7ff, 0xe000, 0xffff, 0x10ffff] {
            let mut err = [0xaau8; ONIG_MAX_ERROR_MESSAGE_LEN];
            assert_eq!(check_unicode_range(code, &mut err), 0, "{code:#x}");
            assert!(err.iter().all(|&b| b == 0xaa), "err untouched");
        }
    }
}
