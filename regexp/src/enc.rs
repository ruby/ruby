//! Safe access to Onigmo's encoding layer (`OnigEncodingType` in
//! include/ruby/onigmo.h), which stays in C. Every call into C goes through
//! the methods of [`Enc`], which take slices and indices so that the rest of
//! the engine never handles raw pointers. The helpers ported from regenc.c
//! live here too.

#![allow(unsafe_code)]

use std::cmp::Ordering;
use std::ffi::{c_char, c_int, c_uint, c_void};
use std::panic::{self, AssertUnwindSafe};

pub type CodePoint = u32;

pub const ONIGENC_CODE_TO_MBC_MAXLEN: usize = 7;
pub const ONIGENC_MBC_CASE_FOLD_MAXLEN: usize = 18;
pub const ONIGENC_MAX_COMP_CASE_FOLD_CODE_LEN: usize = 3;
pub const ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM: usize = 13;

pub const ONIGENC_FLAG_UNICODE: c_uint = 1;
/* see regexec.c: ENC_DUMMY_FLAG mirrors encoding.c */
const ENC_DUMMY_FLAG: c_int = 1 << 24;

pub const CTYPE_NEWLINE: u32 = 0;
pub const CTYPE_ALPHA: u32 = 1;
pub const CTYPE_BLANK: u32 = 2;
pub const CTYPE_CNTRL: u32 = 3;
pub const CTYPE_DIGIT: u32 = 4;
pub const CTYPE_GRAPH: u32 = 5;
pub const CTYPE_LOWER: u32 = 6;
pub const CTYPE_PRINT: u32 = 7;
pub const CTYPE_PUNCT: u32 = 8;
pub const CTYPE_SPACE: u32 = 9;
pub const CTYPE_UPPER: u32 = 10;
pub const CTYPE_XDIGIT: u32 = 11;
pub const CTYPE_WORD: u32 = 12;
pub const CTYPE_ALNUM: u32 = 13;
pub const CTYPE_ASCII: u32 = 14;

pub const INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR: u32 = 1 << 30;
pub const ONIGENC_CASE_FOLD_MIN: u32 = INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR;

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct CaseFoldCodeItem {
    pub byte_len: c_int,
    pub code_len: c_int,
    pub code: [CodePoint; ONIGENC_MAX_COMP_CASE_FOLD_CODE_LEN],
}

pub type ApplyAllCaseFoldFunc =
    unsafe extern "C" fn(from: CodePoint, to: *mut CodePoint, to_len: c_int, arg: *mut c_void) -> c_int;

/// Layout of `struct OnigEncodingTypeST`.
#[repr(C)]
pub struct OnigEncodingType {
    pub precise_mbc_enc_len: Option<unsafe extern "C" fn(*const u8, *const u8, *const OnigEncodingType) -> c_int>,
    pub name: *const c_char,
    pub max_enc_len: c_int,
    pub min_enc_len: c_int,
    pub is_mbc_newline: Option<unsafe extern "C" fn(*const u8, *const u8, *const OnigEncodingType) -> c_int>,
    pub mbc_to_code: Option<unsafe extern "C" fn(*const u8, *const u8, *const OnigEncodingType) -> CodePoint>,
    pub code_to_mbclen: Option<unsafe extern "C" fn(CodePoint, *const OnigEncodingType) -> c_int>,
    pub code_to_mbc: Option<unsafe extern "C" fn(CodePoint, *mut u8, *const OnigEncodingType) -> c_int>,
    pub mbc_case_fold:
        Option<unsafe extern "C" fn(c_uint, *mut *const u8, *const u8, *mut u8, *const OnigEncodingType) -> c_int>,
    pub apply_all_case_fold:
        Option<unsafe extern "C" fn(c_uint, ApplyAllCaseFoldFunc, *mut c_void, *const OnigEncodingType) -> c_int>,
    pub get_case_fold_codes_by_str: Option<
        unsafe extern "C" fn(c_uint, *const u8, *const u8, *mut CaseFoldCodeItem, *const OnigEncodingType) -> c_int,
    >,
    pub property_name_to_ctype: Option<unsafe extern "C" fn(*const OnigEncodingType, *const u8, *const u8) -> c_int>,
    pub is_code_ctype: Option<unsafe extern "C" fn(CodePoint, c_uint, *const OnigEncodingType) -> c_int>,
    pub get_ctype_code_range:
        Option<unsafe extern "C" fn(c_uint, *mut CodePoint, *mut *const CodePoint, *const OnigEncodingType) -> c_int>,
    pub left_adjust_char_head:
        Option<unsafe extern "C" fn(*const u8, *const u8, *const u8, *const OnigEncodingType) -> *mut u8>,
    pub is_allowed_reverse_match: Option<unsafe extern "C" fn(*const u8, *const u8, *const OnigEncodingType) -> c_int>,
    pub case_map: *const c_void,
    pub ruby_encoding_index: c_int,
    pub flags: c_uint,
}

// The tables are immutable C statics shared by every thread.
unsafe impl Sync for OnigEncodingType {}

/// An encoding of the C layer. Encodings are static in Ruby and never freed.
#[derive(Clone, Copy)]
pub struct Enc {
    t: &'static OnigEncodingType,
}

impl PartialEq for Enc {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(self.t, other.t)
    }
}
impl Eq for Enc {}

impl std::fmt::Debug for Enc {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Enc({:p})", self.t)
    }
}

static ASCII: std::sync::OnceLock<Enc> = std::sync::OnceLock::new();

/// Sets the ASCII encoding (`OnigEncodingASCII`), needed to look up the
/// property names used by `\X` the same way regparse.c does.
pub fn set_ascii(enc: Enc) {
    let _ = ASCII.set(enc);
}

fn ascii() -> Enc {
    *ASCII.get().expect("ASCII encoding is not registered")
}

#[inline]
fn range(s: &[u8], p: usize, end: usize) -> (*const u8, *const u8) {
    assert!(p <= end && end <= s.len(), "position out of range");
    let base = s.as_ptr();
    // In bounds by the assertion above.
    unsafe { (base.add(p), base.add(end)) }
}

/// A result of `precise_mbc_enc_len`, decoded from the `ONIGENC_MBCLEN_*`
/// encoding of onigmo.h.
enum MbcLen {
    /// A whole character of this many bytes.
    CharFound(usize),
    /// A character cut short by `end`.
    NeedMore,
    Invalid,
}

impl Enc {
    /// # Safety
    /// `t` must point to an encoding table that lives for the whole process.
    pub unsafe fn from_ptr(t: *const OnigEncodingType) -> Enc {
        Enc { t: unsafe { &*t } }
    }

    pub fn as_ptr(self) -> *const OnigEncodingType {
        self.t
    }

    #[inline]
    pub fn min_len(self) -> usize {
        self.t.min_enc_len as usize
    }

    #[inline]
    pub fn max_len(self) -> usize {
        self.t.max_enc_len as usize
    }

    #[inline]
    pub fn is_single_byte(self) -> bool {
        self.t.max_enc_len == 1
    }

    #[inline]
    pub fn is_unicode(self) -> bool {
        (self.t.flags & ONIGENC_FLAG_UNICODE) != 0
    }

    /// Whether every byte that can start a character starts one wherever it
    /// occurs, so that scanning bytes finds only character heads: the
    /// single-byte encodings, UTF-8 and CESU-8.
    #[inline]
    pub fn is_self_synchronizing(self) -> bool {
        self.is_single_byte() || (self.is_unicode() && self.t.min_enc_len == 1)
    }

    #[inline]
    pub fn is_dummy(self) -> bool {
        (self.t.ruby_encoding_index & ENC_DUMMY_FLAG) != 0
    }

    /// `ONIGENC_PRECISE_MBC_ENC_LEN`.
    pub fn precise_mbc_enc_len(self, s: &[u8], p: usize, end: usize) -> i32 {
        let (pp, pe) = range(s, p, end);
        unsafe { (self.t.precise_mbc_enc_len.expect("precise_mbc_enc_len"))(pp, pe, self.t) }
    }

    #[inline]
    fn mbclen(self, s: &[u8], p: usize, end: usize) -> MbcLen {
        match self.precise_mbc_enc_len(s, p, end) {
            n @ 1.. => MbcLen::CharFound(n as usize),
            ..=-2 => MbcLen::NeedMore,
            _ => MbcLen::Invalid,
        }
    }

    /// `onigenc_mbclen`: the length of the character at `p`, never beyond `end`.
    #[inline]
    pub fn mbc_enc_len(self, s: &[u8], p: usize, end: usize) -> usize {
        if p >= end {
            return 0;
        }
        match self.mbclen(s, p, end) {
            MbcLen::CharFound(n) => n.min(end - p),
            MbcLen::NeedMore => end - p,
            MbcLen::Invalid => 1,
        }
    }

    /// The `enclen()` macro of regenc.h: the length of the character at `p`,
    /// never beyond `end`.
    #[inline]
    pub fn enclen(self, s: &[u8], p: usize, end: usize) -> usize {
        if self.t.max_enc_len == self.t.min_enc_len {
            if p < end { (self.t.min_enc_len as usize).min(end - p) } else { 0 }
        } else {
            self.mbc_enc_len(s, p, end)
        }
    }

    /// `ONIGENC_MBC_TO_CODE`. Returns 0 at the end of the buffer.
    pub fn mbc_to_code(self, s: &[u8], p: usize, end: usize) -> CodePoint {
        if p >= end {
            return 0;
        }
        let (pp, pe) = range(s, p, end);
        unsafe { (self.t.mbc_to_code.expect("mbc_to_code"))(pp, pe, self.t) }
    }

    pub fn is_mbc_newline(self, s: &[u8], p: usize, end: usize) -> bool {
        if p >= end {
            return false;
        }
        let (pp, pe) = range(s, p, end);
        unsafe { (self.t.is_mbc_newline.expect("is_mbc_newline"))(pp, pe, self.t) != 0 }
    }

    pub fn code_to_mbclen(self, code: CodePoint) -> i32 {
        unsafe { (self.t.code_to_mbclen.expect("code_to_mbclen"))(code, self.t) }
    }

    /// Writes the bytes of `code` to `buf`. Returns the length or an error code.
    pub fn code_to_mbc(self, code: CodePoint, buf: &mut [u8; ONIGENC_CODE_TO_MBC_MAXLEN]) -> i32 {
        let n = unsafe { (self.t.code_to_mbc.expect("code_to_mbc"))(code, buf.as_mut_ptr(), self.t) };
        assert!(n <= ONIGENC_CODE_TO_MBC_MAXLEN as i32, "code_to_mbc overflow");
        n
    }

    /// `ONIGENC_MBC_CASE_FOLD`: folds the character at `*p` into `out`,
    /// advances `*p` and returns the number of bytes written.
    #[inline]
    pub fn mbc_case_fold(
        self,
        flag: u32,
        s: &[u8],
        p: &mut usize,
        end: usize,
        out: &mut [u8; ONIGENC_MBC_CASE_FOLD_MAXLEN],
    ) -> usize {
        let (pp, pe) = range(s, *p, end);
        let mut cur = pp;
        let n = unsafe { (self.t.mbc_case_fold.expect("mbc_case_fold"))(flag, &mut cur, pe, out.as_mut_ptr(), self.t) };
        let adv = cur.addr().checked_sub(pp.addr()).unwrap_or(usize::MAX);
        assert!(0 < adv && adv <= end - *p, "mbc_case_fold moved out of range");
        let n = usize::try_from(n).unwrap_or(usize::MAX);
        assert!(n <= ONIGENC_MBC_CASE_FOLD_MAXLEN, "mbc_case_fold overflow");
        *p += adv;
        n
    }

    /// `ONIGENC_APPLY_ALL_CASE_FOLD`. `f` returns 0 to continue.
    pub fn apply_all_case_fold(self, flag: u32, f: &mut dyn FnMut(CodePoint, &[CodePoint]) -> i32) -> i32 {
        struct Ctx<'a> {
            f: &'a mut dyn FnMut(CodePoint, &[CodePoint]) -> i32,
            panic: Option<Box<dyn std::any::Any + Send>>,
        }
        unsafe extern "C" fn tramp(from: CodePoint, to: *mut CodePoint, to_len: c_int, arg: *mut c_void) -> c_int {
            let ctx = unsafe { &mut *(arg as *mut Ctx) };
            let to = unsafe { std::slice::from_raw_parts(to, usize::try_from(to_len).unwrap_or(0)) };
            match panic::catch_unwind(AssertUnwindSafe(|| (ctx.f)(from, to))) {
                Ok(r) => r,
                Err(payload) => {
                    ctx.panic = Some(payload);
                    crate::error::ONIGERR_PARSER_BUG
                }
            }
        }
        let mut ctx = Ctx { f, panic: None };
        let r = unsafe {
            (self.t.apply_all_case_fold.expect("apply_all_case_fold"))(
                flag,
                tramp,
                &mut ctx as *mut Ctx as *mut c_void,
                self.t,
            )
        };
        if let Some(payload) = ctx.panic.take() {
            panic::resume_unwind(payload);
        }
        r
    }

    /// `ONIGENC_GET_CASE_FOLD_CODES_BY_STR`.
    pub fn get_case_fold_codes_by_str(
        self,
        flag: u32,
        s: &[u8],
        p: usize,
        end: usize,
        items: &mut [CaseFoldCodeItem; ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM],
    ) -> i32 {
        let (pp, pe) = range(s, p, end);
        let n = unsafe {
            (self.t.get_case_fold_codes_by_str.expect("get_case_fold_codes_by_str"))(
                flag,
                pp,
                pe,
                items.as_mut_ptr(),
                self.t,
            )
        };
        assert!(n <= ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM as i32, "too many case fold codes");
        n
    }

    pub fn property_name_to_ctype(self, name: &[u8]) -> i32 {
        let (pp, pe) = range(name, 0, name.len());
        unsafe { (self.t.property_name_to_ctype.expect("property_name_to_ctype"))(self.t, pp, pe) }
    }

    /// `env->enc->property_name_to_ctype(ONIG_ENCODING_ASCII, ...)`, used for
    /// the ASCII property names built into the parser.
    pub fn property_name_to_ctype_ascii(self, name: &[u8]) -> i32 {
        let (pp, pe) = range(name, 0, name.len());
        unsafe { (self.t.property_name_to_ctype.expect("property_name_to_ctype"))(ascii().t, pp, pe) }
    }

    #[inline]
    pub fn is_code_ctype(self, code: CodePoint, ctype: u32) -> bool {
        unsafe { (self.t.is_code_ctype.expect("is_code_ctype"))(code, ctype, self.t) != 0 }
    }

    /// `ONIGENC_GET_CTYPE_CODE_RANGE`. On success returns `sb_out` and the
    /// static range table `[n, from1, to1, ...]`.
    pub fn get_ctype_code_range(self, ctype: u32) -> Result<(CodePoint, &'static [CodePoint]), i32> {
        let mut sb_out: CodePoint = 0;
        let mut ranges: *const CodePoint = std::ptr::null();
        let r = unsafe {
            (self.t.get_ctype_code_range.expect("get_ctype_code_range"))(ctype, &mut sb_out, &mut ranges, self.t)
        };
        if r != 0 {
            return Err(r);
        }
        assert!(!ranges.is_null(), "get_ctype_code_range returned no table");
        // The tables in enc/ are static arrays of 1 + 2n code points.
        let n = unsafe { *ranges } as usize;
        Ok((sb_out, unsafe { std::slice::from_raw_parts(ranges, 1 + 2 * n) }))
    }

    /// `ONIGENC_LEFT_ADJUST_CHAR_HEAD`: the head of the character containing `p`.
    pub fn left_adjust_char_head(self, s: &[u8], start: usize, p: usize, end: usize) -> usize {
        assert!(start <= p && p <= end && end <= s.len(), "position out of range");
        if p == start {
            return p;
        }
        let base = s.as_ptr();
        let r = unsafe {
            (self.t.left_adjust_char_head.expect("left_adjust_char_head"))(base.add(start), base.add(p), base.add(end), self.t)
        };
        r.addr()
            .checked_sub(base.addr())
            .filter(|off| (start..=p).contains(off))
            .expect("left_adjust_char_head out of range")
    }

    pub fn is_allowed_reverse_match(self, s: &[u8], p: usize, end: usize) -> bool {
        let (pp, pe) = range(s, p, end);
        unsafe { (self.t.is_allowed_reverse_match.expect("is_allowed_reverse_match"))(pp, pe, self.t) != 0 }
    }

    // Shorthands of regenc.h

    #[inline]
    pub fn is_code_word(self, code: CodePoint) -> bool {
        self.is_code_ctype(code, CTYPE_WORD)
    }

    #[inline]
    pub fn is_code_digit(self, code: CodePoint) -> bool {
        self.is_code_ctype(code, CTYPE_DIGIT)
    }

    #[inline]
    pub fn is_code_xdigit(self, code: CodePoint) -> bool {
        self.is_code_ctype(code, CTYPE_XDIGIT)
    }

    #[inline]
    pub fn is_code_upper(self, code: CodePoint) -> bool {
        self.is_code_ctype(code, CTYPE_UPPER)
    }

    #[inline]
    pub fn is_code_newline(self, code: CodePoint) -> bool {
        self.is_code_ctype(code, CTYPE_NEWLINE)
    }

    #[inline]
    pub fn is_mbc_head(self, s: &[u8], p: usize, end: usize) -> bool {
        self.mbc_enc_len(s, p, end) != 1
    }

    /// `ONIGENC_IS_MBC_WORD`.
    #[inline]
    pub fn is_mbc_word(self, s: &[u8], p: usize, end: usize) -> bool {
        self.is_code_word(self.mbc_to_code(s, p, end))
    }

    // regenc.c

    /// `onigenc_get_prev_char_head`.
    #[inline]
    pub fn get_prev_char_head(self, s: &[u8], start: usize, p: usize, end: usize) -> Option<usize> {
        if p <= start {
            return None;
        }
        Some(self.left_adjust_char_head(s, start, p - 1, end))
    }

    /// `onigenc_get_right_adjust_char_head`.
    pub fn get_right_adjust_char_head(self, s: &[u8], start: usize, p: usize, end: usize) -> usize {
        let q = self.left_adjust_char_head(s, start, p, end);
        if q < p { q + self.enclen(s, q, end) } else { q }
    }

    /// `onigenc_get_right_adjust_char_head_with_prev`.
    pub fn get_right_adjust_char_head_with_prev(
        self,
        s: &[u8],
        start: usize,
        p: usize,
        end: usize,
    ) -> (usize, Option<usize>) {
        let q = self.left_adjust_char_head(s, start, p, end);
        if q < p { (q + self.enclen(s, q, end), Some(q)) } else { (q, None) }
    }

    /// `onigenc_step_back`.
    pub fn step_back(self, s: &[u8], start: usize, p: usize, end: usize, n: usize) -> Option<usize> {
        let mut p = p;
        for _ in 0..n {
            if p <= start {
                return None;
            }
            p = self.left_adjust_char_head(s, start, p - 1, end);
        }
        Some(p)
    }

    /// `onigenc_step`: the position `n` characters after `p`, or `None` when
    /// fewer than `n` characters lie before `end`.
    pub fn step(self, s: &[u8], p: usize, end: usize, n: usize) -> Option<usize> {
        let mut q = p;
        for _ in 0..n {
            if q >= end {
                return None;
            }
            q += self.mbc_enc_len(s, q, end);
        }
        Some(q)
    }

    /// `onigenc_strlen`.
    pub fn strlen(self, s: &[u8], p: usize, end: usize) -> usize {
        let mut n = 0;
        let mut q = p;
        while q < end {
            let l = self.mbc_enc_len(s, q, end);
            q += l.max(1);
            n += 1;
        }
        n
    }

    /// `onigenc_with_ascii_strncmp`: the sign of the first difference of
    /// `ascii` from the characters at `p`, or 0 when they agree.
    pub fn with_ascii_strncmp(self, s: &[u8], p: usize, end: usize, ascii: &[u8]) -> i32 {
        let mut p = p;
        for &a in ascii {
            if p >= end {
                return Ordering::Greater as i32;
            }
            match CodePoint::from(a).cmp(&self.mbc_to_code(s, p, end)) {
                Ordering::Equal => p += self.enclen(s, p, end),
                o => return o as i32,
            }
        }
        0
    }

    /// `onigenc_ascii_is_code_ctype`.
    #[inline]
    pub fn ascii_is_code_ctype(code: CodePoint, ctype: u32) -> bool {
        code < 128 && (ASCII_CTYPE_TABLE[code as usize] & (1 << ctype)) != 0
    }
}

/// `OnigEncAsciiCtypeTable` of regenc.c.
pub static ASCII_CTYPE_TABLE: [u16; 256] = {
    let head: [u16; 128] = [
        0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x420c, 0x4209, 0x4208, 0x4208, 0x4208,
        0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008, 0x4008,
        0x4008, 0x4008, 0x4008, 0x4008, 0x4284, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0,
        0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0, 0x78b0,
        0x78b0, 0x78b0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x7ca2, 0x7ca2, 0x7ca2, 0x7ca2, 0x7ca2,
        0x7ca2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2,
        0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x74a2, 0x41a0, 0x41a0, 0x41a0, 0x41a0, 0x51a0, 0x41a0, 0x78e2,
        0x78e2, 0x78e2, 0x78e2, 0x78e2, 0x78e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2,
        0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x70e2, 0x41a0, 0x41a0, 0x41a0,
        0x41a0, 0x4008,
    ];
    let mut t = [0u16; 256];
    let mut i = 0;
    while i < 128 {
        t[i] = head[i];
        i += 1;
    }
    t
};

/// `ONIGENC_ASCII_CODE_TO_LOWER_CASE`.
#[inline]
pub fn ascii_to_lower(c: u8) -> u8 {
    c.to_ascii_lowercase()
}
