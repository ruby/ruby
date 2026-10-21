//! Rust ports of the MT19937 generator in missing/mt19937.c (port unit
//! `mt19937-A-01`).  random.c compiles that file with
//! `#include "missing/mt19937.c"`; with the ports enabled it calls
//! `init_genrand`, `init_by_array` and `genrand_int32` through
//! `#define`s to the `rb_core_mt19937_*` exports below.  `next_state` is
//! only called by `genrand_int32` and stays private.
//!
//! The generator state is C's `struct MT`, mirrored by [`MT`].  The safe
//! cores work on the state array and represent `mt->next` as an index into
//! it (`next == state + pos`); the `extern "C"` wrappers convert between the
//! two.

use core::ffi::{c_int, c_uint};

/* Period parameters */
const N: usize = 624;
const M: usize = 397;
const MATRIX_A: u32 = 0x9908b0df; /* constant vector a */
const UMASK: u32 = 0x80000000; /* most significant w-r bits */
const LMASK: u32 = 0x7fffffff; /* least significant r bits */

/// `MIXBITS(u,v)`.
#[inline]
fn mixbits(u: u32, v: u32) -> u32 {
    (u & UMASK) | (v & LMASK)
}

/// `TWIST(u,v)`.
#[inline]
fn twist(u: u32, v: u32) -> u32 {
    (mixbits(u, v) >> 1) ^ (if v & 1 != 0 { MATRIX_A } else { 0 })
}

/// `struct MT` from missing/mt19937.c, field for field:
///
/// ```c
/// struct MT {
///     uint32_t state[N];
///     uint32_t *next;
///     int left;
/// };
/// ```
///
/// The layout is asserted below and, against the C definition, by the
/// `STATIC_ASSERT`s in the `#if USE_RUST_PORTS` branch of missing/mt19937.c.
#[repr(C)]
pub struct MT {
    pub state: [u32; N],
    pub next: *mut u32,
    pub left: c_int,
}

const _: () = {
    assert!(core::mem::offset_of!(MT, state) == 0);
    assert!(core::mem::offset_of!(MT, next) == N * core::mem::size_of::<u32>());
    assert!(
        core::mem::offset_of!(MT, left)
            == N * core::mem::size_of::<u32>() + core::mem::size_of::<*mut u32>()
    );
    assert!(core::mem::size_of::<c_int>() == 4);
    assert!(
        core::mem::size_of::<MT>()
            == N * core::mem::size_of::<u32>() + 2 * core::mem::size_of::<*mut u32>()
    );
};

/// `init_genrand`: initializes `state` with a seed.  Returns the new
/// `(next index, left)`, which the C sets to `(state + N, 1)`.
pub fn init_genrand_impl(state: &mut [u32; N], s: c_uint) -> (usize, c_int) {
    state[0] = s; /* s & 0xffffffffU */
    let mut j = 1;
    while j < N {
        let prev = state[j - 1];
        // 1812433253U * (prev ^ (prev >> 30)) + j, in unsigned (wrapping)
        // arithmetic; the `&= 0xffffffff` of the C is a no-op on u32.
        state[j] = 1812433253u32
            .wrapping_mul(prev ^ (prev >> 30))
            .wrapping_add(j as u32);
        j += 1;
    }
    (N, 1)
}

/// `init_by_array`: initializes `state` from `key`.  `key_length` is the C
/// argument; `key` must hold `key_length` words, or one word when
/// `key_length <= 0` (the C then reads `init_key[0]` on every step).
/// Returns `(next index, left)` as set by the inner `init_genrand`.
pub fn init_by_array_impl(state: &mut [u32; N], key: &[u32], key_length: c_int) -> (usize, c_int) {
    let ret = init_genrand_impl(state, 19650218);
    let mut i: usize = 1;
    let mut j: c_int = 0;
    let mut k: c_int = if (N as c_int) > key_length { N as c_int } else { key_length };
    while k != 0 {
        let prev = state[i - 1];
        // (state[i] ^ ((prev ^ (prev >> 30)) * 1664525U)) + init_key[j] + j
        // j is a non-negative int converted to unsigned by the C.
        state[i] = (state[i] ^ (prev ^ (prev >> 30)).wrapping_mul(1664525))
            .wrapping_add(key[j as usize])
            .wrapping_add(j as u32); /* non linear */
        i += 1;
        j += 1;
        if i >= N {
            state[0] = state[N - 1];
            i = 1;
        }
        if j >= key_length {
            j = 0;
        }
        k -= 1;
    }
    k = (N - 1) as c_int;
    while k != 0 {
        let prev = state[i - 1];
        // (state[i] ^ ((prev ^ (prev >> 30)) * 1566083941U)) - i
        state[i] = (state[i] ^ (prev ^ (prev >> 30)).wrapping_mul(1566083941))
            .wrapping_sub(i as u32); /* non linear */
        i += 1;
        if i >= N {
            state[0] = state[N - 1];
            i = 1;
        }
        k -= 1;
    }

    state[0] = 0x80000000; /* MSB is 1; assuring non-zero initial array */
    ret
}

/// `next_state`: regenerates the whole state.  Returns `(next index, left)`,
/// which the C sets to `(state, N)`.
fn next_state_impl(state: &mut [u32; N]) -> (usize, c_int) {
    let mut p = 0;
    // for (j=N-M+1; --j; p++) *p = p[M] ^ TWIST(p[0], p[1]);
    while p < N - M {
        state[p] = state[p + M] ^ twist(state[p], state[p + 1]);
        p += 1;
    }
    // for (j=M; --j; p++) *p = p[M-N] ^ TWIST(p[0], p[1]);
    while p < N - 1 {
        state[p] = state[p - (N - M)] ^ twist(state[p], state[p + 1]);
        p += 1;
    }
    // *p = p[M-N] ^ TWIST(p[0], mt->state[0]);
    state[N - 1] = state[M - 1] ^ twist(state[N - 1], state[0]);
    (0, N as c_int)
}

/// `genrand_int32`: the next number on [0,0xffffffff].
///
/// Precondition (as in C, "mt must be initialized"): when `left - 1 > 0`,
/// `pos` is the index of `next` and is below `N`.  Every state the C code
/// creates (init_genrand, next_state, random.c's marshal_load and
/// initialize_copy) keeps `pos == N - left + 1` with `1 <= left <= N`,
/// which satisfies it.  Where the C would read outside `state`, this
/// panics (rb_bug) instead.
pub fn genrand_int32_impl(state: &mut [u32; N], pos: &mut usize, left: &mut c_int) -> c_uint {
    // --mt->left; signed overflow is undefined in C, so wrap.
    *left = left.wrapping_sub(1);
    if *left <= 0 {
        let (p, l) = next_state_impl(state);
        *pos = p;
        *left = l;
    }
    let mut y = state[*pos];
    *pos += 1;

    /* Tempering */
    y ^= y >> 11;
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= y >> 18;

    y
}

/// Exported `init_genrand` for random.c.
///
/// # Safety
/// `mt` must point to a valid, writable `struct MT` that nothing else
/// accesses during the call (C precondition: a non-NULL `struct MT *`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_mt19937_init_genrand(mt: *mut MT, s: c_uint) {
    // SAFETY: the caller passes a valid, exclusive `struct MT *`.
    let mt = unsafe { &mut *mt };
    let (pos, left) = init_genrand_impl(&mut mt.state, s);
    mt.left = left;
    mt.next = mt.state.as_mut_ptr().wrapping_add(pos);
}

/// Exported `init_by_array` for random.c.
///
/// # Safety
/// `mt` must point to a valid, writable `struct MT` that nothing else
/// accesses during the call.  `init_key` must point to `key_length`
/// readable words, or to at least one word when `key_length <= 0` (the C
/// reads `init_key[0]` then; random.c's rand_init_default passes a
/// one-element array with length 0 for generators without seed bits).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_mt19937_init_by_array(
    mt: *mut MT,
    init_key: *const u32,
    key_length: c_int,
) {
    let len = if key_length > 0 { key_length as usize } else { 1 };
    // SAFETY: the caller guarantees `init_key` points to `len` words; the
    // C reads exactly init_key[0..len).
    let key = unsafe { core::slice::from_raw_parts(init_key, len) };
    // SAFETY: the caller passes a valid, exclusive `struct MT *`.
    let mt = unsafe { &mut *mt };
    let (pos, left) = init_by_array_impl(&mut mt.state, key, key_length);
    mt.left = left;
    mt.next = mt.state.as_mut_ptr().wrapping_add(pos);
}

/// Exported `genrand_int32` for random.c.
///
/// # Safety
/// `mt` must point to a valid, writable, initialized `struct MT` that
/// nothing else accesses during the call; `mt->next` must point into
/// `mt->state` whenever `mt->left > 1` (see [`genrand_int32_impl`]).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rb_core_mt19937_genrand_int32(mt: *mut MT) -> c_uint {
    // SAFETY: the caller passes a valid, exclusive `struct MT *`.
    let mt = unsafe { &mut *mt };
    // next == state + pos.  Address arithmetic only: `next` is never
    // dereferenced here, and `pos` is not used when next_state() resets it.
    let base = mt.state.as_ptr() as usize;
    let mut pos = (mt.next as usize).wrapping_sub(base) / core::mem::size_of::<u32>();
    let mut left = mt.left;
    let y = genrand_int32_impl(&mut mt.state, &mut pos, &mut left);
    mt.left = left;
    mt.next = mt.state.as_mut_ptr().wrapping_add(pos);
    y
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new_mt() -> MT {
        MT { state: [0; N], next: core::ptr::null_mut(), left: 0 }
    }

    fn next_offset(mt: &MT) -> usize {
        (mt.next as usize - mt.state.as_ptr() as usize) / 4
    }

    #[test]
    fn init_genrand_reference_values() {
        // Reference MT19937 output for init_genrand(5489).
        let mut mt = new_mt();
        unsafe { rb_core_mt19937_init_genrand(&mut mt, 5489) };
        assert_eq!(mt.left, 1);
        assert_eq!(next_offset(&mt), N);
        assert_eq!(mt.state[0], 5489);
        assert_eq!(mt.state[1], 1301868182);
        let first = unsafe { rb_core_mt19937_genrand_int32(&mut mt) };
        assert_eq!(first, 3499211612);
        assert_eq!(mt.left, N as c_int);
        assert_eq!(next_offset(&mt), 1);
        let mut last = first;
        for _ in 1..10000 {
            last = unsafe { rb_core_mt19937_genrand_int32(&mut mt) };
        }
        // The 10000th output of the reference generator (C++ std::mt19937).
        assert_eq!(last, 4123659995);
    }

    #[test]
    fn init_by_array_reference_values() {
        // mt19937ar.c's test: init_by_array({0x123, 0x234, 0x345, 0x456}, 4).
        let key = [0x123u32, 0x234, 0x345, 0x456];
        let mut mt = new_mt();
        unsafe { rb_core_mt19937_init_by_array(&mut mt, key.as_ptr(), 4) };
        assert_eq!(mt.state[0], 0x80000000);
        assert_eq!(mt.left, 1);
        let expected = [1067595299u32, 955945823, 477289528, 4107218783, 4228976476];
        for &e in &expected {
            assert_eq!(unsafe { rb_core_mt19937_genrand_int32(&mut mt) }, e);
        }
    }

    #[test]
    fn init_by_array_long_and_empty_keys() {
        // key_length > N: the first loop runs key_length times.
        let mut key = [0u32; 1000];
        for (i, k) in key.iter_mut().enumerate() {
            *k = (i as u32).wrapping_mul(2654435761);
        }
        let mut a = new_mt();
        let mut b = new_mt();
        unsafe { rb_core_mt19937_init_by_array(&mut a, key.as_ptr(), 1000) };
        unsafe { rb_core_mt19937_init_by_array(&mut b, key.as_ptr(), 999) };
        assert_ne!(a.state[..], b.state[..]);
        // key_length 0 and negative read init_key[0] only, like length 1
        // with the same first word... except that j stays 0.
        let one = [7u32];
        let mut c = new_mt();
        let mut d = new_mt();
        let mut e = new_mt();
        unsafe { rb_core_mt19937_init_by_array(&mut c, one.as_ptr(), 1) };
        unsafe { rb_core_mt19937_init_by_array(&mut d, one.as_ptr(), 0) };
        unsafe { rb_core_mt19937_init_by_array(&mut e, one.as_ptr(), -5) };
        assert_eq!(c.state[..], d.state[..]);
        assert_eq!(d.state[..], e.state[..]);
    }

    #[test]
    fn genrand_resumes_from_loaded_state() {
        // random.c's marshal_load sets next = state + N - left + 1.
        let mut mt = new_mt();
        unsafe { rb_core_mt19937_init_genrand(&mut mt, 42) };
        let mut seq = [0u32; 2000];
        for v in seq.iter_mut() {
            *v = unsafe { rb_core_mt19937_genrand_int32(&mut mt) };
        }
        let mut ref_mt = new_mt();
        unsafe { rb_core_mt19937_init_genrand(&mut ref_mt, 42) };
        for v in seq[..700].iter() {
            assert_eq!(unsafe { rb_core_mt19937_genrand_int32(&mut ref_mt) }, *v);
        }
        // Copy the state the way rand_mt_copy does.
        let mut copy = new_mt();
        copy.state = ref_mt.state;
        copy.left = ref_mt.left;
        copy.next = copy.state.as_mut_ptr().wrapping_add(N - copy.left as usize + 1);
        for v in seq[700..].iter() {
            assert_eq!(unsafe { rb_core_mt19937_genrand_int32(&mut copy) }, *v);
        }
    }

    #[test]
    fn genrand_regenerates_on_nonpositive_left() {
        // left <= 1 regenerates regardless of next.
        let mut a = new_mt();
        let mut b = new_mt();
        unsafe { rb_core_mt19937_init_genrand(&mut a, 1) };
        unsafe { rb_core_mt19937_init_genrand(&mut b, 1) };
        b.left = -3;
        b.next = core::ptr::null_mut();
        let x = unsafe { rb_core_mt19937_genrand_int32(&mut a) };
        let y = unsafe { rb_core_mt19937_genrand_int32(&mut b) };
        assert_eq!(x, y);
        assert_eq!(a.state[..], b.state[..]);
        assert_eq!(b.left, N as c_int);
        assert_eq!(next_offset(&b), 1);
    }
}
