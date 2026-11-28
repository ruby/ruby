//! The functions of enc/utf_8.c that matching calls for every character,
//! in Rust, so that a UTF-8 subject needs no call into C for them. Each
//! returns what its C counterpart returns, broken sequences included.

use crate::enc::CodePoint;

const INVALID: i32 = -1; /* ONIGENC_CONSTRUCT_MBCLEN_INVALID() */

/// `ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(n)`
const fn need_more(n: i32) -> i32 {
    -1 - n
}

/// `EncLen_UTF8`: the length announced by the first byte of a character.
const fn announced_len(b: u8) -> i32 {
    match b {
        0xc0..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => 1,
    }
}

const ACCEPT: i8 = -1;
const FAILURE: i8 = -2;

/// `trans`: the state after a byte in each of the states S0 to S7.
static TRANS: [[i8; 256]; 8] = {
    let mut t = [[FAILURE; 256]; 8];
    let mut i = 0;
    while i < 256 {
        let b = i as u8;
        t[0][i] = match b {
            0x00..=0x7f => ACCEPT,
            0xc2..=0xdf => 1,
            0xe0 => 2,
            0xe1..=0xec | 0xee..=0xef => 3,
            0xed => 4,
            0xf0 => 5,
            0xf1..=0xf3 => 6,
            0xf4 => 7,
            _ => FAILURE,
        };
        if matches!(b, 0x80..=0xbf) {
            t[1][i] = ACCEPT;
            t[3][i] = 1;
            t[6][i] = 3;
        }
        if matches!(b, 0xa0..=0xbf) {
            t[2][i] = 1;
        }
        if matches!(b, 0x80..=0x9f) {
            t[4][i] = 1;
        }
        if matches!(b, 0x90..=0xbf) {
            t[5][i] = 3;
        }
        if matches!(b, 0x80..=0x8f) {
            t[7][i] = 3;
        }
        i += 1;
    }
    t
};

/// `mbc_enc_len`: the `ONIGENC_MBCLEN_*` result for the character at `p`,
/// which must lie before `end`.
#[inline]
pub fn precise_len(s: &[u8], p: usize, end: usize) -> i32 {
    let b0 = s[p];
    let mut state = TRANS[0][b0 as usize];
    for n in 1..5 {
        match state {
            ACCEPT => return n,
            FAILURE => return INVALID,
            _ if n == 4 => return INVALID,
            _ if p + n as usize == end => return need_more(announced_len(b0) - n),
            _ => state = TRANS[state as usize][s[p + n as usize] as usize],
        }
    }
    INVALID
}

/// `mbc_to_code` for the character at `p`, which must lie before `end`.
#[inline]
pub fn to_code(s: &[u8], p: usize, end: usize) -> CodePoint {
    decode(s, p, end).0
}

/// `mbc_to_code` and `mbc_enc_len` together, reading the bytes once.
#[inline]
pub fn decode(s: &[u8], p: usize, end: usize) -> (CodePoint, i32) {
    let len = precise_len(s, p, end);
    (code_of(s, p, len), len)
}

#[inline]
fn code_of(s: &[u8], p: usize, len: i32) -> CodePoint {
    let c = CodePoint::from(s[p]);
    if len > 1 {
        let len = len as usize;
        let mut n = c & ((1 << (7 - len)) - 1);
        for &b in &s[p + 1..p + len] {
            n = (n << 6) | CodePoint::from(b & 0x3f);
        }
        n
    } else if c > 0xfd {
        /* USE_INVALID_CODE_SCHEME */
        if c == 0xfe { 0xffff_fffe } else { 0xffff_ffff }
    } else {
        c
    }
}

/// `left_adjust_char_head` for `start < p < s.len()`.
#[inline]
pub fn left_adjust_char_head(s: &[u8], start: usize, p: usize) -> usize {
    let mut q = p;
    while q > start && s[q] & 0xc0 == 0x80 {
        q -= 1;
    }
    q
}
