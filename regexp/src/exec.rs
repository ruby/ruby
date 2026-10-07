//! The matcher, ported from regexec.c: the backtracking VM (`match_at`),
//! the match cache that makes `Regexp.linear_time?` patterns run in linear
//! time, and the search loop (`onig_search`) with its string-search
//! shortcuts. Names follow the C code.
//!
//! The search loops hold positions as `usize` offsets into the subject. The
//! VM holds them as `Pos` so that they fit the words of the stack entries,
//! with `NULL_POS` for no position, which compares below every position.
//! Every read of the subject and of the program is bounds checked.

use std::sync::atomic::{AtomicU32, Ordering};

use crate::ast::*;
use crate::bytecode::*;
use crate::compile::*;
use crate::enc::*;
use crate::error::*;
use crate::parser::bit_status_at;
use crate::syntax::*;

pub type Pos = isize;
pub const NULL_POS: Pos = -1;
pub const ONIG_REGION_NOTPOS: isize = -1;

/// An offset or a length within the subject as a `Pos`. A slice never
/// holds more than `isize::MAX` bytes, so it fits.
#[inline]
fn pos(p: usize) -> Pos {
    p as Pos
}

/// The address of the `OP_FINISH` at the bottom of the stack (`FinishCode`).
const FINISH_CODE: isize = isize::MAX;
const INVALID_STACK_INDEX: isize = -1;
const INIT_MATCH_STACK_SIZE: usize = 160;

static MATCH_STACK_LIMIT_SIZE: AtomicU32 = AtomicU32::new(0);

pub fn get_match_stack_limit_size() -> u32 {
    MATCH_STACK_LIMIT_SIZE.load(Ordering::Relaxed)
}

pub fn set_match_stack_limit_size(size: u32) {
    MATCH_STACK_LIMIT_SIZE.store(size, Ordering::Relaxed);
}

/* stack type */
/* used by normal-POP */
const STK_ALT: u32 = 0x0001;
const STK_LOOK_BEHIND_NOT: u32 = 0x0002;
const STK_POS_NOT: u32 = 0x0003;
/* handled by normal-POP */
const STK_MEM_START: u32 = 0x0100;
const STK_MEM_END: u32 = 0x8200;
const STK_REPEAT_INC: u32 = 0x0300;
/* avoided by normal-POP */
const STK_NULL_CHECK_START: u32 = 0x3000;
const STK_NULL_CHECK_END: u32 = 0x5000; /* for recursive call */
const STK_MEM_END_MARK: u32 = 0x8400;
const STK_POS: u32 = 0x0500; /* used when POP-POS */
const STK_STOP_BT: u32 = 0x0600; /* mark for "(?>...)" */
const STK_REPEAT: u32 = 0x0700;
const STK_CALL_FRAME: u32 = 0x0800;
const STK_RETURN: u32 = 0x0900;
const STK_VOID: u32 = 0x0a00; /* for fill a blank */
const STK_ABSENT_POS: u32 = 0x0b00; /* for absent */
const STK_ABSENT: u32 = 0x0c00; /* absent inner loop marker */
const STK_MATCH_CACHE_POINT: u32 = 0x0d00; /* for the match cache optimization */
const STK_ATOMIC_MATCH_CACHE_POINT: u32 = 0x0e00;

/* stack type check mask */
const STK_MASK_POP_USED: u32 = 0x00ff;
const STK_MASK_TO_VOID_TARGET: u32 = 0x10ff;
const STK_MASK_MEM_END_OR_MARK: u32 = 0x8000; /* MEM_END or MEM_END_MARK */

/// The state of the match cache of a search.
#[derive(Clone, Copy, PartialEq, Eq)]
enum MatchCache {
    /// The program is not looked at yet.
    Uninit,
    /// The program has this many cache opcodes. The cache is set up when
    /// the failures reach this many per byte of the subject.
    Counted(i64),
    Enabled,
    Disabled,
}

/// `OnigStackType`. The union of C is laid over four words:
///
/// | type          | w[0]       | w[1]   | w[2]      | w[3]  | num   |
/// |---------------|------------|--------|-----------|-------|-------|
/// | state         | pcode      | pstr   | pstr_prev | pkeep |       |
/// | repeat        | pcode      | count  |           |       | id    |
/// | repeat_inc    | si         |        |           |       |       |
/// | mem           |            | pstr   | start     | end   | mem   |
/// | null_check    |            | pstr   |           |       | id    |
/// | call_frame    | ret_addr   |        |           |       |       |
/// | absent_pos    | abs_pstr   | end    |           |       |       |
/// | cache point   | index      |        |           |       | mask  |
#[derive(Clone, Copy, Default, Debug)]
struct Stk {
    typ: u32,
    num: i32,
    null_check: isize,
    w: [isize; 4],
}

#[derive(Clone, Copy, Debug)]
struct CacheOpcode {
    addr: usize,
    cache_point: i64,
    outer_repeat_mem: Option<i32>,
    num_cache_points_at_outer_repeat: i64,
    num_cache_points_in_outer_repeat: i64,
    lookaround_nesting: i32,
    match_addr: Option<usize>,
}

/// The registers of a match: `struct re_registers` seen from Rust.
pub struct Region<'a> {
    pub beg: &'a mut [isize],
    pub end: &'a mut [isize],
}

impl Region<'_> {
    pub fn clear(&mut self) {
        for v in self.beg.iter_mut() {
            *v = ONIG_REGION_NOTPOS;
        }
        for v in self.end.iter_mut() {
            *v = ONIG_REGION_NOTPOS;
        }
    }
}

/// `OnigMatchArg`: state shared by the `match_at` calls of one search.
pub struct MatchArg<'c> {
    options: u32,
    gpos: Pos,
    best_len: isize,
    best_s: Pos,
    counter: i32,
    /// Called every 128 steps (`CHECK_INTERRUPT_IN_MATCH_AT`). Returns 0 to
    /// go on, or the code to stop with (ONIGERR_TIMEOUT, RB_REGEXP_INTERRUPTED).
    check: &'c mut dyn FnMut() -> i32,
    match_cache: MatchCache,
    num_fails: i64,
    cache_opcodes: Vec<CacheOpcode>,
    num_cache_points: i64,
    match_cache_buf: Vec<u8>,
}

impl<'c> MatchArg<'c> {
    fn new(options: u32, gpos: Pos, check: &'c mut dyn FnMut() -> i32) -> Self {
        MatchArg {
            options,
            gpos,
            best_len: ONIG_MISMATCH as isize,
            best_s: 0,
            counter: 0,
            check,
            match_cache: MatchCache::Uninit,
            num_fails: 0,
            cache_opcodes: Vec::new(),
            num_cache_points: 0,
            match_cache_buf: Vec::new(),
        }
    }
}

/// The working memory of a search, kept per thread for the next one: C
/// puts it on the machine stack with alloca, so a search costs no malloc.
/// The VM borrows it for all the start positions of the search.
#[derive(Default)]
struct Spare {
    stack: Vec<Stk>,
    repeat_stk: Vec<isize>,
    mem_start_stk: Vec<isize>,
    mem_end_stk: Vec<isize>,
}

thread_local! {
    static SPARE: std::cell::Cell<Option<Box<Spare>>> = const { std::cell::Cell::new(None) };
}

/// Runs `f` with the working memory of this thread. It is boxed so that
/// taking and returning it moves one pointer: moving the arrays themselves
/// took a sixth of the time of a short search. The thread-local is not held
/// during the search, as the interrupt check may switch Ruby threads, and a
/// search nested there gets memory of its own.
fn with_spare<R>(f: impl FnOnce(&mut Spare) -> R) -> R {
    let mut work = SPARE.take().unwrap_or_default();
    let r = f(&mut work);
    if work.stack.capacity() <= 4096 {
        SPARE.set(Some(work));
    }
    r
}

// ---- match cache: which opcodes can be memoized (regexec.c 234-880) ----

struct Prog<'a> {
    reg: &'a Regex,
    p: &'a [u8],
}

/// Why a program cannot use the match cache.
enum NoCache {
    /// It has an opcode the match cache does not support.
    Impossible,
    /// It does not decode.
    Malformed,
}

impl Prog<'_> {
    #[inline]
    fn len_at(&self, p: usize) -> i32 {
        Reader { p: self.p }.i32(p)
    }
    #[inline]
    fn memnum_at(&self, p: usize) -> i32 {
        Reader { p: self.p }.i16(p) as i32
    }
    /// The program is ours, so a negative operand is a compiler bug.
    #[inline]
    fn adv(p: usize, n: i64) -> usize {
        usize::try_from(p as i64 + n).expect("bad operand in compiled program")
    }

    fn skip_simple(&self, op: u8, p: &mut usize) -> Option<()> {
        let pend = self.p.len();
        match op {
            OP_FINISH | OP_END => {}
            OP_EXACT1 => *p += 1,
            OP_EXACT2 => *p += 2,
            OP_EXACT3 => *p += 3,
            OP_EXACT4 => *p += 4,
            OP_EXACT5 => *p += 5,
            OP_EXACTN => {
                let len = self.len_at(*p);
                *p = Self::adv(*p + 4, len as i64);
            }
            OP_EXACTMB2N1 => *p += 2,
            OP_EXACTMB2N2 => *p += 4,
            OP_EXACTMB2N3 => *p += 6,
            OP_EXACTMB2N => {
                let len = self.len_at(*p);
                *p = Self::adv(*p + 4, len as i64 * 2);
            }
            OP_EXACTMB3N => {
                let len = self.len_at(*p);
                *p = Self::adv(*p + 4, len as i64 * 3);
            }
            OP_EXACTMBN => {
                let mb_len = self.len_at(*p);
                let len = self.len_at(*p + 4);
                *p = Self::adv(*p + 8, mb_len as i64 * len as i64);
            }
            OP_EXACT1_IC => {
                let len = self.reg.enc.enclen(self.p, *p, pend);
                *p += len;
            }
            OP_EXACTN_IC => {
                let len = self.len_at(*p);
                *p = Self::adv(*p + 4, len as i64);
            }
            OP_CCLASS | OP_CCLASS_NOT => *p += SIZE_BITSET as usize,
            OP_CCLASS_MB | OP_CCLASS_MB_NOT => {
                let len = self.len_at(*p);
                *p = Self::adv(*p + 4, len as i64);
            }
            OP_CCLASS_MIX | OP_CCLASS_MIX_NOT => {
                *p += SIZE_BITSET as usize;
                let len = self.len_at(*p);
                *p = Self::adv(*p + 4, len as i64);
            }
            OP_ANYCHAR | OP_ANYCHAR_ML => {}
            OP_WORD | OP_NOT_WORD | OP_WORD_BOUND | OP_NOT_WORD_BOUND | OP_WORD_BEGIN | OP_WORD_END => {}
            OP_ASCII_WORD
            | OP_NOT_ASCII_WORD
            | OP_ASCII_WORD_BOUND
            | OP_NOT_ASCII_WORD_BOUND
            | OP_ASCII_WORD_BEGIN
            | OP_ASCII_WORD_END => {}
            OP_BEGIN_BUF | OP_END_BUF | OP_BEGIN_LINE | OP_END_LINE | OP_SEMI_END_BUF | OP_BEGIN_POSITION => {}
            OP_KEEP | OP_FAIL | OP_POP => {}
            OP_JUMP => *p += SIZE_RELADDR as usize,
            OP_NULL_CHECK_START | OP_NULL_CHECK_END | OP_NULL_CHECK_END_MEMST_PUSH | OP_NULL_CHECK_END_MEMST => {
                *p += SIZE_MEMNUM as usize
            }
            OP_LOOK_BEHIND => *p += SIZE_LENGTH as usize,
            OP_SET_OPTION_PUSH | OP_SET_OPTION => *p += SIZE_OPTION as usize,
            _ => return None,
        }
        Some(())
    }

    /// `count_num_cache_opcodes_inner`: the cache opcodes up to the end of
    /// the current repeat or look-around.
    fn count_num_cache_opcodes_inner(
        &self,
        current_repeat_mem: Option<i32>,
        lookaround_nesting: i32,
        pp: &mut usize,
    ) -> Result<i64, NoCache> {
        let mut p = *pp;
        let pend = self.p.len();
        let mut num_cache_opcodes = 0i64;

        macro_rules! impossible {
            () => {
                return Err(NoCache::Impossible)
            };
        }

        while p < pend {
            let op = self.p[p];
            p += 1;
            match op {
                OP_ANYCHAR_STAR | OP_ANYCHAR_ML_STAR => num_cache_opcodes += 1,
                OP_ANYCHAR_STAR_PEEK_NEXT | OP_ANYCHAR_ML_STAR_PEEK_NEXT => {
                    p += 1;
                    num_cache_opcodes += 1;
                }
                OP_BACKREF1 | OP_BACKREF2 | OP_BACKREFN | OP_BACKREFN_IC | OP_BACKREF_MULTI | OP_BACKREF_MULTI_IC
                | OP_BACKREF_WITH_LEVEL => impossible!(),
                OP_MEMORY_START | OP_MEMORY_START_PUSH | OP_MEMORY_END_PUSH | OP_MEMORY_END_PUSH_REC | OP_MEMORY_END
                | OP_MEMORY_END_REC => {
                    p += SIZE_MEMNUM as usize;
                    // A memory (capture) in look-around is found.
                    if lookaround_nesting != 0 {
                        impossible!();
                    }
                }
                OP_PUSH => {
                    p += SIZE_RELADDR as usize;
                    num_cache_opcodes += 1;
                }
                OP_PUSH_OR_JUMP_EXACT1 | OP_PUSH_IF_PEEK_NEXT => {
                    p += SIZE_RELADDR as usize + 1;
                    num_cache_opcodes += 1;
                }
                OP_REPEAT | OP_REPEAT_NG => {
                    if current_repeat_mem.is_some() {
                        // A nested OP_REPEAT is not yet supported.
                        impossible!();
                    }
                    let repeat_mem = self.memnum_at(p);
                    p += SIZE_MEMNUM as usize + SIZE_RELADDR as usize;
                    let range = self.reg.repeat_range[repeat_mem as usize];
                    let body = self.count_num_cache_opcodes_inner(Some(repeat_mem), lookaround_nesting, &mut p)?;
                    if range.lower != 0 || range.upper != 0 {
                        if range.lower == 0 {
                            num_cache_opcodes += 1;
                        }
                        num_cache_opcodes += body;
                        if range.lower < range.upper {
                            num_cache_opcodes += 1;
                        }
                    }
                }
                OP_REPEAT_INC | OP_REPEAT_INC_NG => {
                    let repeat_mem = self.memnum_at(p);
                    p += SIZE_MEMNUM as usize;
                    if Some(repeat_mem) != current_repeat_mem {
                        // A lone or invalid OP_REPEAT_INC is found.
                        impossible!();
                    }
                    break;
                }
                OP_REPEAT_INC_SG | OP_REPEAT_INC_NG_SG => impossible!(),
                OP_PUSH_POS | OP_PUSH_POS_NOT | OP_PUSH_LOOK_BEHIND_NOT => {
                    if lookaround_nesting < 0 {
                        // A look-around nested in a atomic grouping is found.
                        impossible!();
                    }
                    if op == OP_PUSH_POS_NOT {
                        p += SIZE_RELADDR as usize;
                    } else if op == OP_PUSH_LOOK_BEHIND_NOT {
                        p += SIZE_RELADDR as usize + SIZE_LENGTH as usize;
                    }
                    num_cache_opcodes +=
                        self.count_num_cache_opcodes_inner(current_repeat_mem, lookaround_nesting + 1, &mut p)?;
                }
                OP_PUSH_STOP_BT => {
                    if lookaround_nesting != 0 {
                        // A nested atomic grouping is found.
                        impossible!();
                    }
                    num_cache_opcodes += self.count_num_cache_opcodes_inner(current_repeat_mem, -1, &mut p)?;
                }
                OP_POP_POS | OP_FAIL_POS | OP_FAIL_LOOK_BEHIND_NOT | OP_POP_STOP_BT => break,
                OP_PUSH_ABSENT_POS | OP_ABSENT_END | OP_ABSENT => impossible!(),
                OP_CALL | OP_RETURN => impossible!(),
                OP_CONDITION => impossible!(),
                OP_STATE_CHECK_PUSH
                | OP_STATE_CHECK_PUSH_OR_JUMP
                | OP_STATE_CHECK
                | OP_STATE_CHECK_ANYCHAR_STAR
                | OP_STATE_CHECK_ANYCHAR_ML_STAR => impossible!(),
                _ => self.skip_simple(op, &mut p).ok_or(NoCache::Malformed)?,
            }
        }

        *pp = p;
        Ok(num_cache_opcodes)
    }

    /// count the total number of cache opcodes for allocating a match cache buffer.
    fn count_num_cache_opcodes(&self) -> Result<i64, NoCache> {
        let mut p = 0usize;
        let num = self.count_num_cache_opcodes_inner(None, 0, &mut p)?;
        if p != self.p.len() {
            return Err(NoCache::Malformed);
        }
        Ok(num)
    }

    /// `init_cache_opcodes_inner`: numbers the cache opcodes up to the end
    /// of the current repeat or look-around from `cache_point` on, and
    /// returns the cache point after them. `cache_opcodes` is `None` for the
    /// dry run over a `{0}` repeat, where C passes a NULL array.
    fn init_cache_opcodes_inner(
        &self,
        current_repeat_mem: Option<i32>,
        lookaround_nesting: i32,
        cache_opcodes: &mut Option<&mut Vec<CacheOpcode>>,
        pp: &mut usize,
        mut cache_point: i64,
    ) -> Result<i64, NoCache> {
        let mut p = *pp;
        let pend = self.p.len();
        let step = if lookaround_nesting != 0 { 2 } else { 1 };

        macro_rules! inc_cache_opcodes {
            ($pbegin:expr) => {
                if let Some(v) = cache_opcodes.as_deref_mut() {
                    v.push(CacheOpcode {
                        addr: $pbegin,
                        cache_point,
                        outer_repeat_mem: current_repeat_mem,
                        num_cache_points_at_outer_repeat: 0,
                        num_cache_points_in_outer_repeat: 0,
                        lookaround_nesting,
                        match_addr: None,
                    });
                    cache_point += step;
                }
            };
        }
        macro_rules! unexpected {
            () => {
                return Err(NoCache::Impossible)
            };
        }

        while p < pend {
            let pbegin = p;
            let op = self.p[p];
            p += 1;
            match op {
                OP_ANYCHAR_STAR | OP_ANYCHAR_ML_STAR => inc_cache_opcodes!(pbegin),
                OP_ANYCHAR_STAR_PEEK_NEXT | OP_ANYCHAR_ML_STAR_PEEK_NEXT => {
                    p += 1;
                    inc_cache_opcodes!(pbegin);
                }
                OP_BACKREF1 | OP_BACKREF2 | OP_BACKREFN | OP_BACKREFN_IC | OP_BACKREF_MULTI | OP_BACKREF_MULTI_IC
                | OP_BACKREF_WITH_LEVEL => unexpected!(),
                OP_MEMORY_START | OP_MEMORY_START_PUSH | OP_MEMORY_END_PUSH | OP_MEMORY_END_PUSH_REC | OP_MEMORY_END
                | OP_MEMORY_END_REC => {
                    p += SIZE_MEMNUM as usize;
                    if lookaround_nesting != 0 {
                        unexpected!();
                    }
                }
                OP_PUSH => {
                    p += SIZE_RELADDR as usize;
                    inc_cache_opcodes!(pbegin);
                }
                OP_PUSH_OR_JUMP_EXACT1 | OP_PUSH_IF_PEEK_NEXT => {
                    p += SIZE_RELADDR as usize + 1;
                    inc_cache_opcodes!(pbegin);
                }
                OP_REPEAT | OP_REPEAT_NG => {
                    let repeat_mem = self.memnum_at(p);
                    p += SIZE_MEMNUM as usize + SIZE_RELADDR as usize;
                    let range = self.reg.repeat_range[repeat_mem as usize];
                    if range.lower == 0 && range.upper == 0 {
                        self.init_cache_opcodes_inner(Some(repeat_mem), lookaround_nesting, &mut None, &mut p, 0)?;
                    } else {
                        if range.lower == 0 {
                            inc_cache_opcodes!(pbegin);
                        }
                        let num_cache_points_at_repeat = cache_point;
                        let first_in_repeat = cache_opcodes.as_deref().map(|v| v.len()).unwrap_or(0);
                        let num_cache_points_in_repeat = self.init_cache_opcodes_inner(
                            Some(repeat_mem),
                            lookaround_nesting,
                            cache_opcodes,
                            &mut p,
                            0,
                        )?;
                        if range.lower < range.upper {
                            inc_cache_opcodes!(pbegin);
                            if cache_opcodes.is_some() {
                                cache_point -= step;
                            }
                        }
                        let repeat_bounds =
                            if range.upper == 0x7fffffff { 1 } else { i64::from(range.upper - range.lower) };
                        cache_point += num_cache_points_in_repeat * i64::from(range.lower)
                            + (num_cache_points_in_repeat + step) * repeat_bounds;
                        if let Some(v) = cache_opcodes.as_deref_mut() {
                            for co in &mut v[first_in_repeat..] {
                                co.num_cache_points_at_outer_repeat = num_cache_points_at_repeat;
                                co.num_cache_points_in_outer_repeat = num_cache_points_in_repeat;
                            }
                        }
                    }
                }
                OP_REPEAT_INC | OP_REPEAT_INC_NG => {
                    p += SIZE_MEMNUM as usize;
                    break;
                }
                OP_REPEAT_INC_SG | OP_REPEAT_INC_NG_SG => unexpected!(),
                OP_PUSH_POS | OP_PUSH_POS_NOT | OP_PUSH_LOOK_BEHIND_NOT | OP_PUSH_STOP_BT => {
                    if op == OP_PUSH_POS_NOT {
                        p += SIZE_RELADDR as usize;
                    } else if op == OP_PUSH_LOOK_BEHIND_NOT {
                        p += SIZE_RELADDR as usize + SIZE_LENGTH as usize;
                    }
                    let nesting = if op == OP_PUSH_STOP_BT { -1 } else { lookaround_nesting + 1 };
                    let first = cache_opcodes.as_deref().map(|v| v.len()).unwrap_or(0);
                    cache_point =
                        self.init_cache_opcodes_inner(current_repeat_mem, nesting, cache_opcodes, &mut p, cache_point)?;
                    let match_addr = p - 1;
                    if let Some(v) = cache_opcodes.as_deref_mut() {
                        for co in &mut v[first..] {
                            if co.match_addr.is_none() {
                                co.match_addr = Some(match_addr);
                            }
                        }
                    }
                }
                OP_POP_POS | OP_FAIL_POS | OP_FAIL_LOOK_BEHIND_NOT | OP_POP_STOP_BT => break,
                OP_ABSENT_END | OP_ABSENT => unexpected!(),
                OP_CALL | OP_RETURN => unexpected!(),
                OP_CONDITION => unexpected!(),
                OP_STATE_CHECK_PUSH
                | OP_STATE_CHECK_PUSH_OR_JUMP
                | OP_STATE_CHECK
                | OP_STATE_CHECK_ANYCHAR_STAR
                | OP_STATE_CHECK_ANYCHAR_ML_STAR => unexpected!(),
                _ => self.skip_simple(op, &mut p).ok_or(NoCache::Malformed)?,
            }
        }

        *pp = p;
        Ok(cache_point)
    }

    /// collect cache opcodes from the given regex program, and compute the total number of cache points.
    fn init_cache_opcodes(&self, cache_opcodes: &mut Vec<CacheOpcode>) -> Result<i64, NoCache> {
        let mut p = 0usize;
        let num_cache_points = self.init_cache_opcodes_inner(None, 0, &mut Some(cache_opcodes), &mut p, 0)?;
        if p != self.p.len() {
            return Err(NoCache::Malformed);
        }
        Ok(num_cache_points)
    }
}

/// `onig_check_linear_time`
pub fn check_linear_time(reg: &Regex) -> bool {
    let prog = Prog { reg, p: &reg.program };
    !matches!(prog.count_num_cache_opcodes(), Err(NoCache::Impossible))
}

fn check_extended_match_cache_point(buf: &[u8], index: usize, mask: u8) -> bool {
    if mask & 0x80 != 0 { (buf[index + 1] & 0x01) > 0 } else { (buf[index] & (mask << 1)) > 0 }
}

fn memoize_extended_match_cache_point(buf: &mut [u8], index: usize, mask: u8) {
    buf[index] |= mask;
    if mask & 0x80 != 0 {
        buf[index + 1] |= 0x01;
    } else {
        buf[index] |= mask << 1;
    }
}

enum CacheCheck {
    Miss,
    Fail,
    StopBtFail,
    Jump(usize),
}

/// What `STACK_NULL_CHECK*` finds about the iteration that just ended.
enum NullCheck {
    NotEmpty,
    Empty,
    /// It was empty, but a capture in it ends elsewhere.
    EmptyMoved,
}

// ---- the VM ----

#[derive(PartialEq, Eq)]
enum Flow {
    /// The instruction consumed a character: `sprev` becomes its start.
    Next,
    /// `sprev` stays as the instruction left it.
    Jump,
    Fail,
    Finish,
}

struct Vm<'a, 'm, 'c> {
    reg: &'a Regex,
    prog: Reader<'a>,
    plen: usize,
    sb: &'a [u8],
    end: Pos,
    enc: Enc,
    option: u32,
    case_fold_flag: u32,
    num_mem: i32,
    pop_level: i32,
    msa: &'m mut MatchArg<'c>,
    stk: &'m mut Vec<Stk>,
    repeat_stk: &'m mut Vec<isize>,
    mem_start_stk: &'m mut Vec<isize>,
    mem_end_stk: &'m mut Vec<isize>,
}

type VmResult<T> = Result<T, isize>;

impl Vm<'_, '_, '_> {
    #[inline]
    fn ch(&self, s: Pos) -> u8 {
        self.sb[s as usize]
    }

    #[inline]
    fn u(&self, s: Pos) -> usize {
        debug_assert!(s >= 0);
        s as usize
    }

    #[inline]
    fn enclen(&self, s: Pos) -> isize {
        self.enc.enclen(self.sb, self.u(s), self.end as usize) as isize
    }

    #[inline]
    fn enclen_approx(&self, s: Pos) -> isize {
        self.enc.enclen_approx(self.sb, self.u(s), self.end as usize) as isize
    }

    #[inline]
    fn mbc_to_code(&self, s: Pos, end: Pos) -> CodePoint {
        self.enc.mbc_to_code(self.sb, self.u(s), end.min(self.end) as usize)
    }

    #[inline]
    fn is_mbc_word(&self, s: Pos) -> bool {
        self.enc.is_mbc_word(self.sb, self.u(s), self.end as usize)
    }

    #[inline]
    fn is_mbc_ascii_word(&self, s: Pos) -> bool {
        if s >= self.end {
            return false;
        }
        self.enc.is_mbc_ascii_word(self.sb, self.u(s), self.end as usize)
    }

    #[inline]
    fn is_mbc_newline(&self, s: Pos) -> bool {
        s >= 0 && self.enc.is_mbc_newline(self.sb, self.u(s), self.end as usize)
    }

    /// `ONIGENC_IS_MBC_CRNL`
    fn is_mbc_crnl(&self, p: Pos) -> bool {
        self.mbc_to_code(p, self.end) == 13 && {
            let next = p + self.enclen(p);
            next < self.end && self.mbc_to_code(next, self.end) == 10
        }
    }

    /// `is_mbc_newline_ex`
    fn is_mbc_newline_ex(&self, p: Pos, check_prev: bool) -> bool {
        is_mbc_newline_ex(self.enc, self.sb, self.u(p), self.u(self.end), self.option, check_prev)
    }

    /// The head of the character before `s`, or `NULL_POS` at the start.
    fn prev_char_head(&self, s: Pos) -> Pos {
        self.enc.get_prev_char_head(self.sb, 0, self.u(s), self.u(self.end)).map_or(NULL_POS, pos)
    }

    // -- program operands --

    #[inline]
    fn get_length(&self, p: &mut usize) -> i32 {
        let v = self.prog.i32(*p);
        *p += 4;
        v
    }
    /// A length operand. The program is ours, so a negative one is a
    /// compiler bug.
    #[inline]
    fn get_len(&self, p: &mut usize) -> usize {
        usize::try_from(self.get_length(p)).expect("bad operand in compiled program")
    }
    #[inline]
    fn get_memnum(&self, p: &mut usize) -> i32 {
        let v = self.prog.i16(*p) as i32;
        *p += 2;
        v
    }
    #[inline]
    fn get_reladdr(&self, p: &mut usize) -> i32 {
        let v = self.prog.i32(*p);
        *p += 4;
        v
    }
    #[inline]
    fn get_option(&self, p: &mut usize) -> u32 {
        let v = self.prog.u32(*p);
        *p += 4;
        v
    }
    #[inline]
    fn jump_target(p: usize, addr: i32) -> usize {
        usize::try_from(p as i64 + addr as i64).expect("jump out of program")
    }

    #[inline]
    fn bitset_at(&self, p: usize, c: u8) -> bool {
        let w = self.prog.u32(p + (c as usize / 32) * 4);
        w & (1u32 << (c as u32 % 32)) != 0
    }

    /// `onig_is_in_code_range` over the `BBuf` layout of the operand `ranges`.
    fn in_code_range(ranges: &[u8], code: CodePoint) -> bool {
        let r = Reader { p: ranges };
        let n = r.u32(0) as usize;
        let at = |i: usize| r.u32(4 + i * 4);
        let (mut low, mut high) = (0usize, n);
        while low < high {
            let x = (low + high) >> 1;
            if code > at(x * 2 + 1) {
                low = x + 1;
            } else {
                high = x;
            }
        }
        low < n && code >= at(low * 2)
    }

    /// Matches the `n` bytes of the program at `p` at `s`. Returns where the
    /// match ends.
    #[inline]
    fn match_exact(&self, p: usize, s: Pos, n: usize) -> Option<Pos> {
        let su = self.u(s);
        let text = self.sb[..self.u(self.end)].get(su..su + n)?;
        (text == self.prog.bytes(p, n)).then_some(pos(su + n))
    }

    // -- loops of one character (see is_char_loop) --

    /// Where the character that the one-character instruction `op` with
    /// operands at `p` matches at `s` ends.
    #[inline]
    fn char_step(&self, op: u8, mut p: usize, s: Pos) -> Option<Pos> {
        if s >= self.end {
            return None;
        }
        match op {
            OP_EXACT1 => (self.prog.u8(p) == self.ch(s)).then_some(s + 1),
            OP_CCLASS | OP_CCLASS_NOT => {
                (self.bitset_at(p, self.ch(s)) == (op == OP_CCLASS)).then(|| s + self.enclen(s))
            }
            OP_CCLASS_MB | OP_CCLASS_MIX => {
                if !self.enc.is_mbc_head(self.sb, self.u(s), self.end as usize) {
                    return (op == OP_CCLASS_MIX && self.bitset_at(p, self.ch(s))).then_some(s + 1);
                }
                if op == OP_CCLASS_MIX {
                    p += SIZE_BITSET as usize;
                }
                let tlen = usize::try_from(self.prog.i32(p)).ok()?;
                let mb_len = self.enclen_approx(s);
                if s + mb_len > self.end {
                    return None;
                }
                let code = self.mbc_to_code(s, s + mb_len);
                Self::in_code_range(self.prog.bytes(p + 4, tlen), code).then_some(s + mb_len)
            }
            OP_CCLASS_MB_NOT | OP_CCLASS_MIX_NOT => {
                if !self.enc.is_mbc_head(self.sb, self.u(s), self.end as usize) {
                    return (op == OP_CCLASS_MB_NOT || !self.bitset_at(p, self.ch(s))).then_some(s + 1);
                }
                if op == OP_CCLASS_MIX_NOT {
                    p += SIZE_BITSET as usize;
                }
                let tlen = usize::try_from(self.prog.i32(p)).ok()?;
                let next = s + self.enclen(s);
                let code = self.mbc_to_code(s, next);
                (!Self::in_code_range(self.prog.bytes(p + 4, tlen), code)).then_some(next)
            }
            OP_ANYCHAR | OP_ANYCHAR_ML => {
                let n = self.enclen_approx(s);
                if s + n > self.end || (op == OP_ANYCHAR && self.is_mbc_newline_ex(s, false)) {
                    return None;
                }
                Some(s + n)
            }
            OP_WORD | OP_NOT_WORD => (self.is_mbc_word(s) == (op == OP_WORD)).then(|| s + self.enclen(s)),
            OP_ASCII_WORD | OP_NOT_ASCII_WORD => {
                (self.is_mbc_ascii_word(s) == (op == OP_ASCII_WORD)).then(|| s + self.enclen(s))
            }
            _ => None,
        }
    }

    /// For `char_step` of `op` in a single-byte encoding, where it looks at
    /// one byte: what `byte_matches` gives for a byte the loop takes.
    #[inline]
    fn byte_class(&self, op: u8) -> Option<bool> {
        if !self.enc.is_single_byte() {
            return None;
        }
        match op {
            OP_EXACT1 | OP_CCLASS => Some(true),
            OP_CCLASS_NOT => Some(false),
            _ => None,
        }
    }

    #[inline]
    fn byte_matches(&self, op: u8, p: usize, c: u8) -> bool {
        if op == OP_EXACT1 { self.prog.u8(p) == c } else { self.bitset_at(p, c) }
    }

    /// For OP_PUSH at `push` whose operand ends at `x`: the instruction of
    /// its one-character loop and the start of its operands, unless the
    /// match cache needs the states it pushes.
    #[inline]
    fn char_loop(&self, push: usize, x: usize) -> Option<(u8, usize)> {
        (self.reg.is_char_loop(push) && self.msa.match_cache != MatchCache::Enabled)
            .then(|| (self.prog.u8(x), x + 1))
    }

    /// For OP_REPEAT `mem` whose operands end at `x` and whose loop ends at
    /// `end`: the instruction of `x: X; REPEAT_INC mem; end:`, the start of
    /// its operands and the count, when the count is fixed. Such a repeat
    /// pushes no state to come back to, only its counter.
    fn char_repeat(&self, mem: i32, x: usize, end: usize) -> Option<(u8, usize, usize)> {
        if self.msa.match_cache == MatchCache::Enabled {
            return None;
        }
        let range = *self.reg.repeat_range.get(usize::try_from(mem).ok()?)?;
        if range.lower != range.upper || range.lower < 1 {
            return None;
        }
        let op = self.prog.u8(x);
        let inc = x + 1 + char_op_len(self.prog, op, x + 1)?;
        if inc + SIZE_OP_REPEAT_INC as usize != end
            || self.prog.u8(inc) != OP_REPEAT_INC
            || i32::from(self.prog.i16(inc + 1)) != mem
        {
            return None;
        }
        Some((op, x + 1, usize::try_from(range.lower).ok()?))
    }

    /// Counts `n` interrupt checks the loops replaced, and makes the check
    /// once if any of them would have.
    fn count_checks(&mut self, n: usize) -> VmResult<()> {
        let total = usize::try_from(self.msa.counter).unwrap_or(0) + n;
        self.msa.counter = (total % 128) as i32;
        if total < 128 {
            return Ok(());
        }
        match (self.msa.check)() {
            0 => Ok(()),
            r => Err(r as isize),
        }
    }

    // -- stack --

    fn grow(&mut self) -> VmResult<()> {
        let n = self.stk.capacity().max(INIT_MATCH_STACK_SIZE);
        let mut want = n * 2;
        let limit = get_match_stack_limit_size() as usize;
        if limit != 0 && want > limit {
            if self.stk.len() >= limit {
                return Err(ONIGERR_MATCH_STACK_LIMIT_OVER as isize);
            }
            want = limit;
        }
        let extra = want.saturating_sub(self.stk.len());
        self.stk.try_reserve_exact(extra).map_err(|_| ONIGERR_MEMORY as isize)
    }

    #[inline]
    fn push(&mut self, typ: u32, num: i32, w: [isize; 4]) -> VmResult<()> {
        if self.stk.len() == self.stk.capacity() {
            self.grow()?;
        }
        let null_check = match self.stk.last() {
            Some(l) => l.null_check,
            None => 0,
        };
        self.stk.push(Stk { typ, num, null_check, w });
        Ok(())
    }

    #[inline]
    fn push_state(&mut self, typ: u32, pcode: isize, s: Pos, sprev: Pos, keep: Pos) -> VmResult<()> {
        self.push(typ, 0, [pcode, s, sprev, keep])
    }

    #[inline]
    fn top(&self) -> isize {
        self.stk.len() as isize
    }

    fn push_mem_start(&mut self, mnum: i32, s: Pos) -> VmResult<()> {
        let m = mnum as usize;
        let (start, end) = (self.mem_start_stk[m], self.mem_end_stk[m]);
        let idx = self.top();
        self.push(STK_MEM_START, mnum, [0, s, start, end])?;
        self.mem_start_stk[m] = idx;
        self.mem_end_stk[m] = INVALID_STACK_INDEX;
        Ok(())
    }

    fn push_mem_end(&mut self, mnum: i32, s: Pos) -> VmResult<()> {
        let m = mnum as usize;
        let (start, end) = (self.mem_start_stk[m], self.mem_end_stk[m]);
        let idx = self.top();
        self.push(STK_MEM_END, mnum, [0, s, start, end])?;
        self.mem_end_stk[m] = idx;
        Ok(())
    }

    fn push_null_check(&mut self, typ: u32, cnum: i32, s: Pos) -> VmResult<()> {
        if self.stk.len() == self.stk.capacity() {
            self.grow()?;
        }
        let idx = self.top();
        self.stk.push(Stk { typ, num: cnum, null_check: idx, w: [0, s, 0, 0] });
        Ok(())
    }

    #[inline]
    fn restore_mem(&mut self, e: &Stk) {
        let m = e.num as usize;
        self.mem_start_stk[m] = e.w[2];
        self.mem_end_stk[m] = e.w[3];
    }

    #[inline]
    fn memoize_match_cache_point(&mut self, e: &Stk) {
        if e.typ == STK_MATCH_CACHE_POINT {
            self.msa.match_cache_buf[e.w[0] as usize] |= e.num as u8;
        } else if e.typ == STK_ATOMIC_MATCH_CACHE_POINT {
            memoize_extended_match_cache_point(&mut self.msa.match_cache_buf, e.w[0] as usize, e.num as u8);
        }
    }

    #[inline]
    fn pop_entry(&mut self) -> Stk {
        self.stk.pop().expect("match stack underflow")
    }

    /// `STACK_POP` on a failure: the words of the entry that stopped the
    /// pop. They are read in place, as copying the whole entry out stalls on
    /// the narrower stores that pushed it.
    #[inline]
    fn stack_pop_state(&mut self) -> [isize; 4] {
        let i = self.stk.len().checked_sub(1).expect("match stack underflow");
        let top = &self.stk[i];
        if top.typ & STK_MASK_POP_USED != 0 {
            let w = [top.w[0], top.w[1], top.w[2], top.w[3]];
            self.stk.truncate(i);
            return w;
        }
        self.stack_pop().w
    }

    /// `STACK_POP`: returns the entry that stopped the pop.
    #[inline(never)]
    fn stack_pop(&mut self) -> Stk {
        loop {
            let e = self.pop_entry();
            if e.typ & STK_MASK_POP_USED != 0 {
                return e;
            }
            match self.pop_level {
                STACK_POP_LEVEL_FREE => {}
                STACK_POP_LEVEL_MEM_START => {
                    if e.typ == STK_MEM_START {
                        self.restore_mem(&e);
                    }
                }
                _ => {
                    if e.typ == STK_MEM_START || e.typ == STK_MEM_END {
                        self.restore_mem(&e);
                    } else if e.typ == STK_REPEAT_INC {
                        self.stk[e.w[0] as usize].w[1] -= 1;
                    }
                }
            }
            self.memoize_match_cache_point(&e);
        }
    }

    fn memoize_lookaround(&mut self, e: &mut Stk) {
        if e.typ == STK_MATCH_CACHE_POINT {
            e.typ = STK_VOID;
            memoize_extended_match_cache_point(&mut self.msa.match_cache_buf, e.w[0] as usize, e.num as u8);
        }
    }

    /// `STACK_POP_TIL_POS_NOT`, `STACK_POP_TIL_LOOK_BEHIND_NOT`,
    /// `STACK_POP_TIL_ABSENT`.
    fn pop_til(&mut self, til: u32) {
        loop {
            let mut e = self.pop_entry();
            if e.typ == til {
                break;
            } else if e.typ == STK_MEM_START || e.typ == STK_MEM_END {
                self.restore_mem(&e);
            } else if e.typ == STK_REPEAT_INC {
                self.stk[e.w[0] as usize].w[1] -= 1;
            } else if til == STK_POS_NOT && e.typ & STK_MASK_TO_VOID_TARGET != 0 {
                self.msa.num_fails += 1;
            }
            if til == STK_POS_NOT {
                self.memoize_lookaround(&mut e);
            }
        }
    }

    /// `STACK_POS_END`: returns the index of the STK_POS entry.
    fn stack_pos_end(&mut self) -> usize {
        let mut k = self.stk.len();
        loop {
            k -= 1;
            let typ = self.stk[k].typ;
            if typ & STK_MASK_TO_VOID_TARGET != 0 {
                self.msa.num_fails += 1;
                self.stk[k].typ = STK_VOID;
            } else if typ == STK_POS {
                self.stk[k].typ = STK_VOID;
                return k;
            }
            let mut e = self.stk[k];
            self.memoize_lookaround(&mut e);
            self.stk[k].typ = e.typ;
        }
    }

    fn stack_stop_bt_end(&mut self) {
        let mut k = self.stk.len();
        loop {
            k -= 1;
            let typ = self.stk[k].typ;
            if typ & STK_MASK_TO_VOID_TARGET != 0 {
                self.msa.num_fails += 1;
                self.stk[k].typ = STK_VOID;
            } else if typ == STK_STOP_BT {
                self.stk[k].typ = STK_VOID;
                return;
            } else if typ == STK_MATCH_CACHE_POINT {
                self.stk[k].typ = STK_ATOMIC_MATCH_CACHE_POINT;
            }
        }
    }

    fn stack_stop_bt_fail(&mut self) {
        loop {
            let e = self.pop_entry();
            if e.typ == STK_STOP_BT {
                // C sets the type to VOID on the entry it leaves behind the top.
                return;
            }
            if e.typ == STK_MATCH_CACHE_POINT {
                memoize_extended_match_cache_point(&mut self.msa.match_cache_buf, e.w[0] as usize, e.num as u8);
            }
        }
    }

    /// `STACK_GET_MEM_START`: index of the matching MEM_START (or 0).
    fn stack_get_mem_start(&self, mnum: i32) -> usize {
        let mut level = 0;
        let mut k = self.stk.len();
        while k > 0 {
            k -= 1;
            let e = &self.stk[k];
            if e.typ & STK_MASK_MEM_END_OR_MARK != 0 && e.num == mnum {
                level += 1;
            } else if e.typ == STK_MEM_START && e.num == mnum {
                if level == 0 {
                    break;
                }
                level -= 1;
            }
        }
        k
    }

    /// `STACK_NULL_CHECK*`
    fn stack_null_check(&self, id: i32, s: Pos, rec: bool, memst: bool) -> NullCheck {
        let top_nc = self.stk.last().expect("match stack underflow").null_check;
        let mut k = top_nc as usize + 1;
        let mut level = 0;
        loop {
            k -= 1;
            let e = &self.stk[k];
            if e.typ == STK_NULL_CHECK_START {
                if e.num == id {
                    if !rec || level == 0 {
                        if e.w[1] != s {
                            return NullCheck::NotEmpty;
                        }
                        if !memst {
                            return NullCheck::Empty;
                        }
                        let mut isnull = NullCheck::Empty;
                        let mut j = k;
                        while j < self.stk.len() {
                            let m = &self.stk[j];
                            if m.typ == STK_MEM_START {
                                if m.w[3] == INVALID_STACK_INDEX {
                                    return NullCheck::NotEmpty;
                                }
                                let endp = if bit_status_at(self.reg.bt_mem_end, m.num) {
                                    self.stk[m.w[3] as usize].w[1]
                                } else {
                                    m.w[3]
                                };
                                if self.stk[m.w[2] as usize].w[1] != endp {
                                    return NullCheck::NotEmpty;
                                } else if endp != s {
                                    isnull = NullCheck::EmptyMoved;
                                }
                            }
                            j += 1;
                        }
                        return isnull;
                    } else {
                        level -= 1;
                    }
                }
            } else if rec && e.typ == STK_NULL_CHECK_END && (!memst || e.num == id) {
                level += 1;
            }
        }
    }

    /// `STACK_GET_REPEAT`
    fn stack_get_repeat(&self, id: i32) -> usize {
        let mut level = 0;
        let mut k = self.stk.len();
        loop {
            k -= 1;
            let e = &self.stk[k];
            if e.typ == STK_REPEAT {
                if level == 0 && e.num == id {
                    return k;
                }
            } else if e.typ == STK_CALL_FRAME {
                level -= 1;
            } else if e.typ == STK_RETURN {
                level += 1;
            }
        }
    }

    /// `STACK_RETURN`
    fn stack_return(&self) -> usize {
        let mut level = 0;
        let mut k = self.stk.len();
        loop {
            k -= 1;
            let e = &self.stk[k];
            if e.typ == STK_CALL_FRAME {
                if level == 0 {
                    return e.w[0] as usize;
                }
                level -= 1;
            } else if e.typ == STK_RETURN {
                level += 1;
            }
        }
    }

    // -- captures --

    fn mem_pos(&self, mem: i32, start: bool) -> Pos {
        let m = mem as usize;
        if start {
            if bit_status_at(self.reg.bt_mem_start, mem) {
                self.stk[self.mem_start_stk[m] as usize].w[1]
            } else {
                self.mem_start_stk[m]
            }
        } else if bit_status_at(self.reg.bt_mem_end, mem) {
            self.stk[self.mem_end_stk[m] as usize].w[1]
        } else {
            self.mem_end_stk[m]
        }
    }

    /// `string_cmp_ic`: the folded text of `s1..end1` against the subject
    /// at `s2`. Returns where the match at `s2` ends.
    fn string_cmp_ic(&self, s1: Pos, end1: Pos, s2: Pos) -> Option<Pos> {
        let mut buf1 = [0u8; ONIGENC_MBC_CASE_FOLD_MAXLEN];
        let mut buf2 = [0u8; ONIGENC_MBC_CASE_FOLD_MAXLEN];
        let te = self.u(self.end);
        let (mut s1, end1, mut s2) = (self.u(s1), self.u(end1), self.u(s2));
        while s1 < end1 {
            if s1 >= te || s2 >= te {
                return None;
            }
            let len1 = self.enc.mbc_case_fold(self.case_fold_flag, self.sb, &mut s1, te, &mut buf1);
            let len2 = self.enc.mbc_case_fold(self.case_fold_flag, self.sb, &mut s2, te, &mut buf2);
            if buf1[..len1] != buf2[..len2] {
                return None;
            }
        }
        Some(pos(s2))
    }

    /// Matches the captured text `pstart..pend` at `s`, folding case when
    /// `ignore_case`. Returns where the match ends.
    fn match_capture(&self, pstart: Pos, pend: Pos, s: Pos, ignore_case: bool) -> Option<Pos> {
        if s + (pend - pstart) > self.end {
            return None;
        }
        if ignore_case {
            return self.string_cmp_ic(pstart, pend, s);
        }
        let cap = self.sb.get(self.u(pstart)..self.u(pend)).unwrap_or_default();
        let su = self.u(s);
        (self.sb[su..su + cap.len()] == *cap).then_some(pos(su + cap.len()))
    }

    /// The head of the last character of `from..to`, or `from` when it is
    /// empty.
    fn last_char_head(&self, from: Pos, to: Pos) -> Pos {
        self.enc.get_prev_char_head(self.sb, self.u(from), self.u(to), self.u(self.end)).map_or(from, pos)
    }

    fn backref_match_at_nested_level(&self, ignore_case: bool, nest: i32, mems: &[u8], s: Pos) -> Option<Pos> {
        let mut pend = None;
        let mut level = 0;
        for e in self.stk.iter().rev() {
            if e.typ == STK_CALL_FRAME {
                level -= 1;
            } else if e.typ == STK_RETURN {
                level += 1;
            } else if level == nest {
                if e.typ == STK_MEM_START {
                    if memnums(mems).any(|m| m == e.num) {
                        if let Some(pend) = pend {
                            return self.match_capture(e.w[1], pend, s, ignore_case); /* or goto next_mem; */
                        }
                    }
                } else if e.typ == STK_MEM_END && memnums(mems).any(|m| m == e.num) {
                    pend = Some(e.w[1]);
                }
            }
        }
        None
    }

    // -- match cache --

    fn find_cache_point(&self, p: usize) -> Option<(i64, usize)> {
        let ops = &self.msa.cache_opcodes;
        let num = ops.len() as i64;
        let op = self.prog.u8(p);
        let is_inc = op == OP_REPEAT_INC || op == OP_REPEAT_INC_NG;

        // bsearch_cache_opcodes
        let (mut l, mut r, mut m) = (0i64, num - 1, 0i64);
        while l <= r {
            m = (l + r) / 2;
            let a = ops[m as usize].addr;
            if a == p {
                break;
            }
            if a < p {
                l = m + 1;
            } else {
                r = m - 1;
            }
        }
        if !(0 <= m && m < num && ops[m as usize].addr == p) {
            return None;
        }
        let co = &ops[m as usize];
        let cache_point = co.cache_point;
        let Some(outer_repeat_mem) = co.outer_repeat_mem else {
            return Some((cache_point, m as usize));
        };
        let at = co.num_cache_points_at_outer_repeat;
        let inr = co.num_cache_points_in_outer_repeat;
        let range = self.reg.repeat_range[outer_repeat_mem as usize];
        let stkp = &self.stk[self.repeat_stk[outer_repeat_mem as usize] as usize];
        let count = if is_inc { stkp.w[1] - 1 } else { stkp.w[1] } as i64;
        let (lower, upper) = (range.lower as i64, range.upper as i64);
        let v = if count < lower {
            at + inr * count + cache_point
        } else if upper == 0x7fffffff {
            at + inr * (lower - if is_inc { 1 } else { 0 }) + if is_inc { 0 } else { 1 } + cache_point
        } else {
            at + inr * (lower - 1) + (inr + 1) * (count - lower + 1) + cache_point
        };
        Some((v, m as usize))
    }

    #[inline]
    fn check_match_cache(&mut self, pbegin: usize, s: Pos) -> VmResult<CacheCheck> {
        if self.msa.match_cache != MatchCache::Enabled {
            return Ok(CacheCheck::Miss);
        }
        self.check_enabled_match_cache(pbegin, s)
    }

    #[inline(never)]
    fn check_enabled_match_cache(&mut self, pbegin: usize, s: Pos) -> VmResult<CacheCheck> {
        if let Some((cache_point, idx)) = self.find_cache_point(pbegin) {
            let mcp = self.msa.num_cache_points * s as i64 + cache_point;
            let index = (mcp >> 3) as usize;
            let mask = 1u8 << (mcp & 7);
            if self.msa.match_cache_buf[index] & mask != 0 {
                let co = self.msa.cache_opcodes[idx];
                return Ok(if co.lookaround_nesting == 0 {
                    CacheCheck::Fail
                } else if co.lookaround_nesting < 0 {
                    if check_extended_match_cache_point(&self.msa.match_cache_buf, index, mask) {
                        CacheCheck::StopBtFail
                    } else {
                        CacheCheck::Fail
                    }
                } else if check_extended_match_cache_point(&self.msa.match_cache_buf, index, mask) {
                    CacheCheck::Jump(co.match_addr.expect("match cache point without match address"))
                } else {
                    CacheCheck::Fail
                });
            }
            self.push(STK_MATCH_CACHE_POINT, mask as i32, [index as isize, 0, 0, 0])?;
        }
        Ok(CacheCheck::Miss)
    }

    /// The match cache bookkeeping done on every failure.
    #[inline]
    fn on_fail_match_cache(&mut self) -> VmResult<()> {
        let msa = &mut *self.msa;
        match msa.match_cache {
            MatchCache::Enabled | MatchCache::Disabled => return Ok(()),
            MatchCache::Uninit if msa.num_fails + 1 < self.sb.len() as i64 => {
                msa.num_fails += 1;
                return Ok(());
            }
            _ => {}
        }
        self.count_fail_for_match_cache()
    }

    #[inline(never)]
    fn count_fail_for_match_cache(&mut self) -> VmResult<()> {
        let msa = &mut *self.msa;
        let len = i64::try_from(self.sb.len()).unwrap_or(i64::MAX);
        let prog = Prog { reg: self.reg, p: &self.reg.program };
        let num_cache_opcodes = match msa.match_cache {
            MatchCache::Uninit => {
                msa.num_fails += 1;
                if msa.num_fails < len {
                    return Ok(());
                }
                match prog.count_num_cache_opcodes() {
                    Ok(0) | Err(NoCache::Impossible) => {
                        msa.match_cache = MatchCache::Disabled;
                        return Ok(());
                    }
                    Ok(n) => {
                        msa.match_cache = MatchCache::Counted(n);
                        n
                    }
                    Err(NoCache::Malformed) => return Err(ONIGERR_UNDEFINED_BYTECODE as isize),
                }
            }
            MatchCache::Counted(n) => {
                msa.num_fails += 1;
                n
            }
            MatchCache::Enabled | MatchCache::Disabled => return Ok(()),
        };
        if msa.num_fails < len.saturating_mul(num_cache_opcodes) {
            return Ok(());
        }

        let mut ops = Vec::new();
        ops.try_reserve(usize::try_from(num_cache_opcodes).unwrap_or(0)).map_err(|_| ONIGERR_MEMORY as isize)?;
        msa.num_cache_points = prog.init_cache_opcodes(&mut ops).map_err(|e| match e {
            NoCache::Impossible => ONIGERR_UNEXPECTED_BYTECODE as isize,
            NoCache::Malformed => ONIGERR_UNDEFINED_BYTECODE as isize,
        })?;
        msa.cache_opcodes = ops;

        let points = usize::try_from(msa.num_cache_points)
            .ok()
            .and_then(|n| n.checked_mul(self.sb.len() + 1))
            .ok_or(ONIGERR_MEMORY as isize)?;
        let buf_len = points.div_ceil(8) + 1;
        let mut buf = Vec::new();
        buf.try_reserve_exact(buf_len).map_err(|_| ONIGERR_MEMORY as isize)?;
        buf.resize(buf_len, 0);
        msa.match_cache_buf = buf;
        msa.match_cache = MatchCache::Enabled;
        Ok(())
    }

    #[inline]
    fn check_interrupt(&mut self) -> VmResult<()> {
        self.msa.counter += 1;
        if self.msa.counter >= 128 { self.call_check() } else { Ok(()) }
    }

    #[cold]
    #[inline(never)]
    fn call_check(&mut self) -> VmResult<()> {
        self.msa.counter = 0;
        match (self.msa.check)() {
            0 => Ok(()),
            r => Err(r as isize),
        }
    }

    /// `match_at`: match data(str - end) from position (sstart).
    /// if sstart == str then set sprev to NULL.
    /// Returns the length of the match, if any.
    fn run(&mut self, sstart: Pos, sprev_in: Pos, region: &mut Option<Region<'_>>) -> VmResult<Option<isize>> {
        let option = self.option;
        let mut p: usize = 0;
        let mut s: Pos = sstart;
        let mut sprev: Pos = sprev_in;
        let mut pkeep: Pos = sstart;
        let mut best_len: isize = ONIG_MISMATCH as isize;

        self.stk.clear();
        if self.stk.capacity() < INIT_MATCH_STACK_SIZE {
            self.stk.try_reserve(INIT_MATCH_STACK_SIZE).map_err(|_| ONIGERR_MEMORY as isize)?;
        }
        self.push_state(STK_ALT, FINISH_CODE, 0, 0, 0)?; /* bottom stack */

        macro_rules! data_ensure {
            ($l:lifetime, $n:expr) => {
                if s + ($n) > self.end {
                    break $l Flow::Fail;
                }
            };
        }
        macro_rules! cache_check {
            ($l:lifetime, $pbegin:expr) => {
                match self.check_match_cache($pbegin, s)? {
                    CacheCheck::Miss => {}
                    CacheCheck::Fail => break $l Flow::Fail,
                    CacheCheck::StopBtFail => {
                        self.stack_stop_bt_fail();
                        break $l Flow::Fail;
                    }
                    CacheCheck::Jump(a) => {
                        p = a;
                        break $l Flow::Jump;
                    }
                }
            };
        }
        macro_rules! exact {
            ($l:lifetime, $n:expr) => {
                let n = $n;
                match self.match_exact(p, s, n) {
                    Some(e) => {
                        p += n;
                        s = e;
                    }
                    None => break $l Flow::Fail,
                }
            };
        }

        loop {
            if p == FINISH_CODE as usize {
                break;
            }
            let pbegin = p;
            let sbegin = s;
            let op = self.prog.u8(p);
            p += 1;

            let flow = 'op: {
                match op {
                    OP_END => {
                        let n = s - sstart;
                        let mut record = n > best_len;
                        if record && is_find_longest(option) {
                            if n > self.msa.best_len {
                                self.msa.best_len = n;
                                self.msa.best_s = sstart;
                            } else {
                                record = false;
                            }
                        }
                        if record {
                            best_len = n;
                            if let Some(region) = region.as_mut() {
                                region.beg[0] = if pkeep > s { s } else { pkeep };
                                region.end[0] = s;
                                for i in 1..=self.num_mem {
                                    let iu = i as usize;
                                    if self.mem_end_stk[iu] != INVALID_STACK_INDEX {
                                        region.beg[iu] = self.mem_pos(i, true);
                                        region.end[iu] = self.mem_pos(i, false);
                                    } else {
                                        region.beg[iu] = ONIG_REGION_NOTPOS;
                                        region.end[iu] = ONIG_REGION_NOTPOS;
                                    }
                                }
                            }
                        }
                        if is_find_condition(option) {
                            if is_find_not_empty(option) && s == sstart {
                                best_len = ONIG_MISMATCH as isize;
                                break 'op Flow::Fail; /* for retry */
                            }
                            if is_find_longest(option) && s < self.end {
                                break 'op Flow::Fail; /* for retry */
                            }
                        }
                        /* default behavior: return first-matching result. */
                        Flow::Finish
                    }

                    OP_EXACT1 => {
                        data_ensure!('op, 1);
                        if self.prog.u8(p) != self.ch(s) {
                            break 'op Flow::Fail;
                        }
                        p += 1;
                        s += 1;
                        Flow::Next
                    }

                    OP_EXACT1_IC => {
                        let mut lowbuf = [0u8; ONIGENC_MBC_CASE_FOLD_MAXLEN];
                        let prog = self.prog.p;
                        let pat = &prog[p..p + self.enc.enclen(prog, p, prog.len())];
                        data_ensure!('op, 1);
                        let mut su = self.u(s);
                        let len = self.enc.mbc_case_fold(self.case_fold_flag, self.sb, &mut su, self.end as usize, &mut lowbuf);
                        s = pos(su);
                        data_ensure!('op, 0);
                        if lowbuf[..len] != *pat {
                            break 'op Flow::Fail;
                        }
                        p += pat.len();
                        Flow::Next
                    }

                    OP_EXACT2 | OP_EXACT3 | OP_EXACT4 | OP_EXACT5 => {
                        exact!('op, usize::from(op - OP_EXACT1) + 1);
                        sprev = s - 1;
                        Flow::Jump
                    }

                    OP_EXACTN => {
                        let tlen = self.get_len(&mut p);
                        exact!('op, tlen);
                        sprev = s - 1;
                        Flow::Jump
                    }

                    OP_EXACTN_IC => {
                        let mut lowbuf = [0u8; ONIGENC_MBC_CASE_FOLD_MAXLEN];
                        let tlen = self.get_len(&mut p);
                        let pat = &self.prog.p[p..p + tlen];
                        p += tlen;
                        let mut q = 0;
                        while q < pat.len() {
                            sprev = s;
                            data_ensure!('op, 1);
                            let mut su = self.u(s);
                            let len =
                                self.enc.mbc_case_fold(self.case_fold_flag, self.sb, &mut su, self.end as usize, &mut lowbuf);
                            s = pos(su);
                            data_ensure!('op, 0);
                            match pat.get(q..q + len) {
                                Some(part) if part == &lowbuf[..len] => q += len,
                                _ => break 'op Flow::Fail,
                            }
                        }
                        Flow::Jump
                    }

                    OP_EXACTMB2N1 => {
                        exact!('op, 2);
                        Flow::Next
                    }

                    OP_EXACTMB2N2 | OP_EXACTMB2N3 => {
                        let chars = if op == OP_EXACTMB2N2 { 2 } else { 3 };
                        exact!('op, chars * 2);
                        sprev = s - 2;
                        Flow::Jump
                    }

                    OP_EXACTMB2N | OP_EXACTMB3N => {
                        let w = if op == OP_EXACTMB2N { 2 } else { 3 };
                        let tlen = self.get_len(&mut p);
                        exact!('op, tlen * w);
                        sprev = s - pos(w);
                        Flow::Jump
                    }

                    OP_EXACTMBN => {
                        let tlen = self.get_len(&mut p); /* mb-len */
                        let tlen2 = self.get_len(&mut p) * tlen; /* string len */
                        exact!('op, tlen2);
                        sprev = s - pos(tlen);
                        Flow::Jump
                    }

                    OP_CCLASS | OP_CCLASS_NOT => {
                        data_ensure!('op, 1);
                        let hit = self.bitset_at(p, self.ch(s));
                        if hit != (op == OP_CCLASS) {
                            break 'op Flow::Fail;
                        }
                        p += SIZE_BITSET as usize;
                        s += self.enclen(s); /* OP_CCLASS can match mb-code. \D, \S */
                        Flow::Next
                    }

                    OP_CCLASS_MB | OP_CCLASS_MIX => {
                        if op == OP_CCLASS_MB {
                            if !self.enc.is_mbc_head(self.sb, self.u(s), self.end as usize) {
                                break 'op Flow::Fail;
                            }
                        } else {
                            data_ensure!('op, 1);
                            if !self.enc.is_mbc_head(self.sb, self.u(s), self.end as usize) {
                                if !self.bitset_at(p, self.ch(s)) {
                                    break 'op Flow::Fail;
                                }
                                p += SIZE_BITSET as usize;
                                let tlen = self.get_len(&mut p);
                                p += tlen;
                                s += 1;
                                break 'op Flow::Next;
                            }
                            p += SIZE_BITSET as usize;
                        }
                        // cclass_mb:
                        let tlen = self.get_len(&mut p);
                        data_ensure!('op, 1);
                        let mb_len = self.enclen_approx(s);
                        data_ensure!('op, mb_len);
                        let ss = s;
                        s += mb_len;
                        let code = self.mbc_to_code(ss, s);
                        if !Self::in_code_range(self.prog.bytes(p, tlen), code) {
                            break 'op Flow::Fail;
                        }
                        p += tlen;
                        Flow::Next
                    }

                    OP_CCLASS_MB_NOT | OP_CCLASS_MIX_NOT => {
                        data_ensure!('op, 1);
                        if op == OP_CCLASS_MB_NOT {
                            if !self.enc.is_mbc_head(self.sb, self.u(s), self.end as usize) {
                                s += 1;
                                let tlen = self.get_len(&mut p);
                                p += tlen;
                                break 'op Flow::Next; /* cc_mb_not_success */
                            }
                        } else if self.enc.is_mbc_head(self.sb, self.u(s), self.end as usize) {
                            p += SIZE_BITSET as usize;
                        } else {
                            if self.bitset_at(p, self.ch(s)) {
                                break 'op Flow::Fail;
                            }
                            p += SIZE_BITSET as usize;
                            let tlen = self.get_len(&mut p);
                            p += tlen;
                            s += 1;
                            break 'op Flow::Next;
                        }
                        // cclass_mb_not:
                        let tlen = self.get_len(&mut p);
                        let ss = s;
                        s += self.enclen(s);
                        let code = self.mbc_to_code(ss, s);
                        if Self::in_code_range(self.prog.bytes(p, tlen), code) {
                            break 'op Flow::Fail;
                        }
                        p += tlen;
                        Flow::Next
                    }

                    OP_ANYCHAR => {
                        data_ensure!('op, 1);
                        let n = self.enclen_approx(s);
                        data_ensure!('op, n);
                        if self.is_mbc_newline_ex(s, false) {
                            break 'op Flow::Fail;
                        }
                        s += n;
                        Flow::Next
                    }

                    OP_ANYCHAR_ML => {
                        data_ensure!('op, 1);
                        let n = self.enclen_approx(s);
                        data_ensure!('op, n);
                        s += n;
                        Flow::Next
                    }

                    OP_ANYCHAR_STAR | OP_ANYCHAR_ML_STAR => {
                        let ml = op == OP_ANYCHAR_ML_STAR;
                        while s < self.end {
                            cache_check!('op, pbegin);
                            self.push_state(STK_ALT, p as isize, s, sprev, pkeep)?;
                            let n = self.enclen_approx(s);
                            if ml {
                                if n > 1 {
                                    data_ensure!('op, n);
                                    sprev = s;
                                    s += n;
                                } else {
                                    sprev = s;
                                    s += 1;
                                }
                            } else {
                                data_ensure!('op, n);
                                if self.is_mbc_newline_ex(s, false) {
                                    break 'op Flow::Fail;
                                }
                                sprev = s;
                                s += n;
                            }
                        }
                        Flow::Jump
                    }

                    OP_ANYCHAR_STAR_PEEK_NEXT | OP_ANYCHAR_ML_STAR_PEEK_NEXT => {
                        let ml = op == OP_ANYCHAR_ML_STAR_PEEK_NEXT;
                        let c = self.prog.u8(p);
                        while s < self.end {
                            cache_check!('op, pbegin);
                            if c == self.ch(s) {
                                self.push_state(STK_ALT, p as isize + 1, s, sprev, pkeep)?;
                            } else {
                                // num_fails counts this case too, for invoking
                                // the cache optimization correctly.
                                self.msa.num_fails += 1;
                            }
                            let n = self.enclen_approx(s);
                            if ml {
                                if n > 1 {
                                    data_ensure!('op, n);
                                    sprev = s;
                                    s += n;
                                } else {
                                    sprev = s;
                                    s += 1;
                                }
                            } else {
                                data_ensure!('op, n);
                                if self.is_mbc_newline_ex(s, false) {
                                    break 'op Flow::Fail;
                                }
                                sprev = s;
                                s += n;
                            }
                        }
                        p += 1;
                        Flow::Next
                    }

                    OP_WORD | OP_NOT_WORD => {
                        data_ensure!('op, 1);
                        if self.is_mbc_word(s) != (op == OP_WORD) {
                            break 'op Flow::Fail;
                        }
                        s += self.enclen(s);
                        Flow::Next
                    }

                    OP_ASCII_WORD | OP_NOT_ASCII_WORD => {
                        data_ensure!('op, 1);
                        if self.is_mbc_ascii_word(s) != (op == OP_ASCII_WORD) {
                            break 'op Flow::Fail;
                        }
                        s += self.enclen(s);
                        Flow::Next
                    }

                    OP_WORD_BOUND | OP_ASCII_WORD_BOUND | OP_NOT_WORD_BOUND | OP_NOT_ASCII_WORD_BOUND => {
                        let ascii = op == OP_ASCII_WORD_BOUND || op == OP_NOT_ASCII_WORD_BOUND;
                        let not = op == OP_NOT_WORD_BOUND || op == OP_NOT_ASCII_WORD_BOUND;
                        let word = |vm: &Self, x: Pos| if ascii { vm.is_mbc_ascii_word(x) } else { vm.is_mbc_word(x) };
                        if s == 0 {
                            if !not {
                                data_ensure!('op, 1);
                                if !word(self, s) {
                                    break 'op Flow::Fail;
                                }
                            } else if s < self.end && word(self, s) {
                                break 'op Flow::Fail;
                            }
                        } else if s == self.end {
                            if word(self, sprev) == not {
                                break 'op Flow::Fail;
                            }
                        } else if (word(self, s) == word(self, sprev)) != not {
                            break 'op Flow::Fail;
                        }
                        Flow::Jump
                    }

                    OP_WORD_BEGIN | OP_ASCII_WORD_BEGIN => {
                        let ascii = op == OP_ASCII_WORD_BEGIN;
                        let word = |vm: &Self, x: Pos| if ascii { vm.is_mbc_ascii_word(x) } else { vm.is_mbc_word(x) };
                        if s < self.end && word(self, s) && (s == 0 || !word(self, sprev)) {
                            break 'op Flow::Jump;
                        }
                        Flow::Fail
                    }

                    OP_WORD_END | OP_ASCII_WORD_END => {
                        let ascii = op == OP_ASCII_WORD_END;
                        let word = |vm: &Self, x: Pos| if ascii { vm.is_mbc_ascii_word(x) } else { vm.is_mbc_word(x) };
                        if s != 0 && word(self, sprev) && (s == self.end || !word(self, s)) {
                            break 'op Flow::Jump;
                        }
                        Flow::Fail
                    }

                    OP_BEGIN_BUF => {
                        if s != 0 || is_notbos(self.msa.options) {
                            break 'op Flow::Fail;
                        }
                        Flow::Jump
                    }

                    OP_END_BUF => {
                        if s != self.end || is_noteos(self.msa.options) {
                            break 'op Flow::Fail;
                        }
                        Flow::Jump
                    }

                    OP_BEGIN_LINE => {
                        if s == 0 {
                            if is_notbol(self.msa.options) {
                                break 'op Flow::Fail;
                            }
                            break 'op Flow::Jump;
                        } else if self.is_mbc_newline(sprev)
                            && !(is_newline_crlf(option) && self.is_mbc_crnl(sprev))
                            && s != self.end
                        {
                            break 'op Flow::Jump;
                        }
                        Flow::Fail
                    }

                    OP_END_LINE => {
                        if s == self.end {
                            if is_noteol(self.msa.options) {
                                break 'op Flow::Fail;
                            }
                            break 'op Flow::Jump;
                        } else if self.is_mbc_newline_ex(s, true) {
                            break 'op Flow::Jump;
                        }
                        Flow::Fail
                    }

                    OP_SEMI_END_BUF => {
                        if s == self.end {
                            if is_noteol(self.msa.options) {
                                break 'op Flow::Fail;
                            }
                            break 'op Flow::Jump;
                        } else if self.is_mbc_newline_ex(s, true) {
                            let mut ss = s + self.enclen(s);
                            if ss == self.end {
                                break 'op Flow::Jump;
                            } else if is_newline_crlf(option) && self.is_mbc_crnl(s) {
                                ss += self.enclen(ss);
                                if ss == self.end {
                                    break 'op Flow::Jump;
                                }
                            }
                        }
                        Flow::Fail
                    }

                    OP_BEGIN_POSITION => {
                        if s != self.msa.gpos {
                            break 'op Flow::Fail;
                        }
                        Flow::Jump
                    }

                    OP_MEMORY_START_PUSH => {
                        let mem = self.get_memnum(&mut p);
                        self.push_mem_start(mem, s)?;
                        Flow::Jump
                    }

                    OP_MEMORY_START => {
                        let mem = self.get_memnum(&mut p) as usize;
                        self.mem_start_stk[mem] = s;
                        self.mem_end_stk[mem] = INVALID_STACK_INDEX;
                        Flow::Jump
                    }

                    OP_MEMORY_END_PUSH => {
                        let mem = self.get_memnum(&mut p);
                        self.push_mem_end(mem, s)?;
                        Flow::Jump
                    }

                    OP_MEMORY_END => {
                        let mem = self.get_memnum(&mut p) as usize;
                        self.mem_end_stk[mem] = s;
                        Flow::Jump
                    }

                    OP_KEEP => {
                        pkeep = s;
                        Flow::Jump
                    }

                    OP_MEMORY_END_PUSH_REC => {
                        let mem = self.get_memnum(&mut p);
                        let k = self.stack_get_mem_start(mem); /* should be before push mem-self.end. */
                        self.mem_start_stk[mem as usize] = k as isize;
                        self.push_mem_end(mem, s)?;
                        Flow::Jump
                    }

                    OP_MEMORY_END_REC => {
                        let mem = self.get_memnum(&mut p);
                        self.mem_end_stk[mem as usize] = s;
                        let k = self.stack_get_mem_start(mem);
                        self.mem_start_stk[mem as usize] =
                            if bit_status_at(self.reg.bt_mem_start, mem) { k as isize } else { self.stk[k].w[1] };
                        self.push(STK_MEM_END_MARK, mem, [0; 4])?;
                        Flow::Jump
                    }

                    OP_BACKREF1 | OP_BACKREF2 | OP_BACKREFN | OP_BACKREFN_IC => {
                        let mem = match op {
                            OP_BACKREF1 => 1,
                            OP_BACKREF2 => 2,
                            _ => self.get_memnum(&mut p),
                        };
                        /* if you want to remove following line,
                           you should check in parse and compile time. */
                        if mem > self.num_mem
                            || mem < 0
                            || self.mem_end_stk[mem as usize] == INVALID_STACK_INDEX
                            || self.mem_start_stk[mem as usize] == INVALID_STACK_INDEX
                        {
                            break 'op Flow::Fail;
                        }
                        let pstart = self.mem_pos(mem, true);
                        let pend = self.mem_pos(mem, false);
                        let Some(e) = self.match_capture(pstart, pend, s, op == OP_BACKREFN_IC) else {
                            break 'op Flow::Fail;
                        };
                        sprev = self.last_char_head(s, e);
                        s = e;
                        Flow::Jump
                    }

                    OP_BACKREF_MULTI | OP_BACKREF_MULTI_IC => {
                        let ic = op == OP_BACKREF_MULTI_IC;
                        let tlen = self.get_len(&mut p);
                        let mems = self.prog.bytes(p, tlen * SIZE_MEMNUM as usize);
                        p += mems.len();
                        let found = memnums(mems).find_map(|mem| {
                            let mu = mem as usize;
                            if self.mem_end_stk[mu] == INVALID_STACK_INDEX || self.mem_start_stk[mu] == INVALID_STACK_INDEX {
                                return None;
                            }
                            self.match_capture(self.mem_pos(mem, true), self.mem_pos(mem, false), s, ic)
                        });
                        let Some(e) = found else {
                            break 'op Flow::Fail;
                        };
                        sprev = self.last_char_head(s, e);
                        s = e;
                        Flow::Jump
                    }

                    OP_BACKREF_WITH_LEVEL => {
                        let ic = self.get_option(&mut p);
                        let level = self.get_length(&mut p);
                        let tlen = self.get_len(&mut p);
                        let mems = self.prog.bytes(p, tlen * SIZE_MEMNUM as usize);
                        p += mems.len();
                        let Some(e) = self.backref_match_at_nested_level(ic != 0, level, mems, s) else {
                            break 'op Flow::Fail;
                        };
                        sprev = self.last_char_head(s, e);
                        s = e;
                        Flow::Jump
                    }

                    OP_NULL_CHECK_START => {
                        let mem = self.get_memnum(&mut p); /* mem: null check id */
                        self.push_null_check(STK_NULL_CHECK_START, mem, s)?;
                        Flow::Jump
                    }

                    OP_NULL_CHECK_END | OP_NULL_CHECK_END_MEMST | OP_NULL_CHECK_END_MEMST_PUSH => {
                        let mem = self.get_memnum(&mut p); /* mem: null check id */
                        let isnull = match op {
                            OP_NULL_CHECK_END => self.stack_null_check(mem, s, false, false),
                            OP_NULL_CHECK_END_MEMST => self.stack_null_check(mem, s, false, true),
                            _ => self.stack_null_check(mem, s, true, true),
                        };
                        match isnull {
                            NullCheck::EmptyMoved => break 'op Flow::Fail,
                            NullCheck::Empty => {
                                // null_check_found: empty loop founded, skip next instruction
                                let next = self.prog.u8(p);
                                p += 1;
                                match next {
                                    OP_JUMP | OP_PUSH => p += SIZE_RELADDR as usize,
                                    OP_REPEAT_INC | OP_REPEAT_INC_NG | OP_REPEAT_INC_SG | OP_REPEAT_INC_NG_SG => {
                                        p += SIZE_MEMNUM as usize
                                    }
                                    _ => return Err(ONIGERR_UNEXPECTED_BYTECODE as isize),
                                }
                            }
                            NullCheck::NotEmpty => {
                                if op == OP_NULL_CHECK_END_MEMST_PUSH {
                                    self.push_null_check(STK_NULL_CHECK_END, mem, s)?;
                                }
                            }
                        }
                        Flow::Jump
                    }

                    OP_JUMP => {
                        let addr = self.get_reladdr(&mut p);
                        p = Self::jump_target(p, addr);
                        self.check_interrupt()?;
                        Flow::Jump
                    }

                    OP_PUSH => {
                        let addr = self.get_reladdr(&mut p);
                        let target = Self::jump_target(p, addr);
                        if let Some((x, operands)) = self.char_loop(pbegin, p) {
                            let mut n = 0;
                            if let Some(want) = self.byte_class(x) {
                                // One byte per character, compared here
                                // rather than with a call per character.
                                while s < self.end && self.byte_matches(x, operands, self.ch(s)) == want {
                                    sprev = s;
                                    s += 1;
                                    n += 1;
                                }
                            } else {
                                while let Some(next) = self.char_step(x, operands, s) {
                                    sprev = s;
                                    s = next;
                                    n += 1;
                                }
                            }
                            // The JUMPs taken, then the step that fails and
                            // pops the last state.
                            self.count_checks(n)?;
                            self.on_fail_match_cache()?;
                            self.check_interrupt()?;
                            if self.prog.u8(target) == OP_POP_STOP_BT {
                                // The other states, which stack_stop_bt_end
                                // would void and count as failures.
                                self.msa.num_fails += n as i64;
                            }
                            p = target;
                            break 'op Flow::Jump;
                        }
                        cache_check!('op, pbegin);
                        self.push_state(STK_ALT, target as isize, s, sprev, pkeep)?;
                        Flow::Jump
                    }

                    OP_POP => {
                        self.pop_entry();
                        // Onigmo makes a loop that is pairwise disjoint to what
                        // follows atomic; count it as a failure for the cache.
                        self.msa.num_fails += 1;
                        Flow::Jump
                    }

                    OP_PUSH_IF_PEEK_NEXT => {
                        let addr = self.get_reladdr(&mut p);
                        cache_check!('op, pbegin);
                        if s < self.end && self.prog.u8(p) == self.ch(s) {
                            p += 1;
                            self.push_state(STK_ALT, Self::jump_target(p, addr) as isize, s, sprev, pkeep)?;
                            break 'op Flow::Jump;
                        }
                        p += 1;
                        self.msa.num_fails += 1;
                        Flow::Jump
                    }

                    OP_REPEAT | OP_REPEAT_NG => {
                        let mem = self.get_memnum(&mut p); /* mem: OP_REPEAT ID */
                        let addr = self.get_reladdr(&mut p);
                        if let Some((x, operands, n)) = self.char_repeat(mem, p, Self::jump_target(p, addr)) {
                            for i in 0..n {
                                let Some(next) = self.char_step(x, operands, s) else {
                                    self.count_checks(i)?;
                                    break 'op Flow::Fail;
                                };
                                sprev = s;
                                s = next;
                            }
                            self.count_checks(n)?;
                            p = Self::jump_target(p, addr);
                            break 'op Flow::Jump;
                        }
                        if self.stk.len() == self.stk.capacity() {
                            self.grow()?;
                        }
                        self.repeat_stk[mem as usize] = self.top();
                        self.push(STK_REPEAT, mem, [p as isize, 0, 0, 0])?;
                        if self.reg.repeat_range[mem as usize].lower == 0 {
                            cache_check!('op, pbegin);
                            if op == OP_REPEAT {
                                self.push_state(STK_ALT, Self::jump_target(p, addr) as isize, s, sprev, pkeep)?;
                            } else {
                                self.push_state(STK_ALT, p as isize, s, sprev, pkeep)?;
                                p = Self::jump_target(p, addr);
                            }
                        }
                        Flow::Jump
                    }

                    OP_REPEAT_INC | OP_REPEAT_INC_SG => {
                        let mem = self.get_memnum(&mut p); /* mem: OP_REPEAT ID */
                        let si = if op == OP_REPEAT_INC {
                            self.repeat_stk[mem as usize] as usize
                        } else {
                            self.stack_get_repeat(mem)
                        };
                        // repeat_inc:
                        self.stk[si].w[1] += 1;
                        let count = self.stk[si].w[1];
                        let range = self.reg.repeat_range[mem as usize];
                        if count >= range.upper as isize {
                            /* self.end of repeat. Nothing to do. */
                        } else if count >= range.lower as isize {
                            if op == OP_REPEAT_INC {
                                let r = self.check_match_cache(pbegin, s)?;
                                if !matches!(r, CacheCheck::Miss) {
                                    self.stk[si].w[1] -= 1;
                                }
                                match r {
                                    CacheCheck::Miss => {}
                                    CacheCheck::Fail => break 'op Flow::Fail,
                                    CacheCheck::StopBtFail => {
                                        self.stack_stop_bt_fail();
                                        break 'op Flow::Fail;
                                    }
                                    CacheCheck::Jump(a) => {
                                        p = a;
                                        break 'op Flow::Jump;
                                    }
                                }
                            }
                            self.push_state(STK_ALT, p as isize, s, sprev, pkeep)?;
                            p = self.stk[si].w[0] as usize; /* Don't use stkp after PUSH. */
                        } else {
                            p = self.stk[si].w[0] as usize;
                        }
                        self.push(STK_REPEAT_INC, 0, [si as isize, 0, 0, 0])?;
                        self.check_interrupt()?;
                        Flow::Jump
                    }

                    OP_REPEAT_INC_NG | OP_REPEAT_INC_NG_SG => {
                        let mem = self.get_memnum(&mut p); /* mem: OP_REPEAT ID */
                        let si = if op == OP_REPEAT_INC_NG {
                            self.repeat_stk[mem as usize] as usize
                        } else {
                            self.stack_get_repeat(mem)
                        };
                        // repeat_inc_ng:
                        self.stk[si].w[1] += 1;
                        let count = self.stk[si].w[1];
                        let range = self.reg.repeat_range[mem as usize];
                        if count < range.upper as isize {
                            if count >= range.lower as isize {
                                let pcode = self.stk[si].w[0];
                                self.push(STK_REPEAT_INC, 0, [si as isize, 0, 0, 0])?;
                                if op == OP_REPEAT_INC_NG {
                                    cache_check!('op, pbegin);
                                }
                                self.push_state(STK_ALT, pcode, s, sprev, pkeep)?;
                            } else {
                                p = self.stk[si].w[0] as usize;
                                self.push(STK_REPEAT_INC, 0, [si as isize, 0, 0, 0])?;
                            }
                        } else if count == range.upper as isize {
                            self.push(STK_REPEAT_INC, 0, [si as isize, 0, 0, 0])?;
                        }
                        self.check_interrupt()?;
                        Flow::Jump
                    }

                    OP_PUSH_POS => {
                        self.push_state(STK_POS, 0, s, sprev, pkeep)?;
                        Flow::Jump
                    }

                    OP_POP_POS => {
                        let k = self.stack_pos_end();
                        s = self.stk[k].w[1];
                        sprev = self.stk[k].w[2];
                        Flow::Jump
                    }

                    OP_PUSH_POS_NOT => {
                        let addr = self.get_reladdr(&mut p);
                        self.push_state(STK_POS_NOT, Self::jump_target(p, addr) as isize, s, sprev, pkeep)?;
                        Flow::Jump
                    }

                    OP_FAIL_POS => {
                        self.pop_til(STK_POS_NOT);
                        Flow::Fail
                    }

                    OP_PUSH_STOP_BT => {
                        self.push(STK_STOP_BT, 0, [0; 4])?;
                        Flow::Jump
                    }

                    OP_POP_STOP_BT => {
                        self.stack_stop_bt_end();
                        Flow::Jump
                    }

                    OP_LOOK_BEHIND => {
                        let tlen = self.get_len(&mut p);
                        match self.enc.step_back(self.sb, 0, self.u(s), self.end as usize, tlen) {
                            None => break 'op Flow::Fail,
                            Some(q) => s = pos(q),
                        }
                        sprev = self.prev_char_head(s);
                        Flow::Jump
                    }

                    OP_PUSH_LOOK_BEHIND_NOT => {
                        let addr = self.get_reladdr(&mut p);
                        let tlen = self.get_len(&mut p);
                        match self.enc.step_back(self.sb, 0, self.u(s), self.end as usize, tlen) {
                            None => {
                                /* too short case -> success. ex. /(?<!XXX)a/.match("a")
                                   If you want to change to fail, replace following line. */
                                p = Self::jump_target(p, addr);
                            }
                            Some(q) => {
                                self.push_state(
                                    STK_LOOK_BEHIND_NOT,
                                    Self::jump_target(p, addr) as isize,
                                    s,
                                    sprev,
                                    pkeep,
                                )?;
                                s = pos(q);
                                sprev = self.prev_char_head(s);
                            }
                        }
                        Flow::Jump
                    }

                    OP_FAIL_LOOK_BEHIND_NOT => {
                        self.pop_til(STK_LOOK_BEHIND_NOT);
                        Flow::Fail
                    }

                    OP_PUSH_ABSENT_POS => {
                        /* Save the absent-start-pos and the original self.end-pos. */
                        self.push(STK_ABSENT_POS, 0, [s, self.end, 0, 0])?;
                        Flow::Jump
                    }

                    OP_ABSENT => {
                        let aend = self.end;
                        let selfp = p - 1;
                        let e = self.pop_entry(); /* STACK_POP_ABSENT_POS: restore self.end-pos. */
                        let absent = e.w[0];
                        self.end = e.w[1];
                        let addr = self.get_reladdr(&mut p);
                        if absent > aend && s > absent {
                            /* An empty match occurred in (?~...) at the start point.
                             * Never match. */
                            self.stack_pop();
                            break 'op Flow::Fail;
                        } else if s >= aend && s > absent {
                            if s > aend {
                                /* Only one (or less) character matched in the last iteration.
                                 * This is not a possible point. */
                                break 'op Flow::Fail;
                            }
                            /* All possible points were found. Try matching after (?~...). */
                            if s > self.end {
                                break 'op Flow::Fail;
                            }
                            p = Self::jump_target(p, addr);
                        } else if s == self.end {
                            /* At the self.end of the string, just match with it */
                            p = Self::jump_target(p, addr);
                        } else {
                            self.push_state(STK_ALT, Self::jump_target(p, addr) as isize, s, sprev, pkeep)?; /* Push possible point. */
                            let n = self.enclen(s);
                            self.push(STK_ABSENT_POS, 0, [absent, self.end, 0, 0])?; /* Save the original pos. */
                            self.push_state(STK_ALT, selfp as isize, s + n, s, pkeep)?; /* Next iteration. */
                            self.push(STK_ABSENT, 0, [0; 4])?;
                            self.end = aend;
                        }
                        Flow::Jump
                    }

                    OP_ABSENT_END => {
                        /* The pattern inside (?~...) was matched.
                         * Set the self.end-pos temporary and go to next iteration. */
                        if sprev < self.end {
                            self.end = sprev;
                        }
                        self.pop_til(STK_ABSENT);
                        Flow::Fail
                    }

                    OP_CALL => {
                        let addr = self.prog.i32(p);
                        p += 4;
                        self.push(STK_CALL_FRAME, 0, [p as isize, 0, 0, 0])?;
                        p = usize::try_from(addr).expect("bad call address");
                        Flow::Jump
                    }

                    OP_RETURN => {
                        p = self.stack_return();
                        self.push(STK_RETURN, 0, [0; 4])?;
                        Flow::Jump
                    }

                    OP_CONDITION => {
                        let mem = self.get_memnum(&mut p);
                        let addr = self.get_reladdr(&mut p);
                        if mem > self.num_mem
                            || mem < 0
                            || self.mem_end_stk[mem as usize] == INVALID_STACK_INDEX
                            || self.mem_start_stk[mem as usize] == INVALID_STACK_INDEX
                        {
                            p = Self::jump_target(p, addr);
                        }
                        Flow::Jump
                    }

                    OP_FINISH => Flow::Finish,

                    OP_FAIL => Flow::Fail,

                    _ => return Err(ONIGERR_UNDEFINED_BYTECODE as isize),
                }
            };

            match flow {
                Flow::Next => sprev = sbegin,
                Flow::Jump => {}
                Flow::Finish => break,
                Flow::Fail => {
                    let [pcode, pstr, pstr_prev, keep] = self.stack_pop_state();
                    p = if pcode == FINISH_CODE { FINISH_CODE as usize } else { pcode as usize };
                    s = pstr;
                    sprev = pstr_prev;
                    pkeep = keep;
                    self.on_fail_match_cache()?;
                    self.check_interrupt()?;
                }
            }
        }
        Ok((best_len >= 0).then_some(best_len))
    }
}

/// The length of the operands at `p` of `op` when it matches exactly one
/// character.
fn char_op_len(prog: Reader, op: u8, p: usize) -> Option<usize> {
    Some(match op {
        OP_EXACT1 => 1,
        OP_CCLASS | OP_CCLASS_NOT => SIZE_BITSET as usize,
        OP_CCLASS_MB | OP_CCLASS_MB_NOT => 4 + usize::try_from(prog.i32(p)).ok()?,
        OP_CCLASS_MIX | OP_CCLASS_MIX_NOT => {
            SIZE_BITSET as usize + 4 + usize::try_from(prog.i32(p + SIZE_BITSET as usize)).ok()?
        }
        OP_ANYCHAR | OP_ANYCHAR_ML | OP_WORD | OP_NOT_WORD | OP_ASCII_WORD | OP_NOT_ASCII_WORD => 0,
        _ => return None,
    })
}

/// Whether the OP_PUSH at `push` starts `push: PUSH target; X; JUMP push;
/// target:` over a one-character instruction X, followed by OP_END or by the
/// end of an atomic group. Such a loop pushes a state for every character
/// it takes, which is then discarded unused, so the VM runs it without them
/// (`Vm::char_step`, which matches X as its arm in `run` does).
pub(crate) fn is_char_loop(program: &[u8], push: usize, find_condition: bool) -> bool {
    let prog = Reader { p: program };
    let x = push + SIZE_OP_PUSH as usize;
    let Some(len) = program.get(x).and_then(|&op| char_op_len(prog, op, x + 1)) else {
        return false;
    };
    let jump = x + 1 + len;
    let target = jump + SIZE_OP_JUMP as usize;
    program.get(target).is_some_and(|&op| op == OP_POP_STOP_BT || (op == OP_END && !find_condition))
        && program[jump] == OP_JUMP
        && Vm::jump_target(target, prog.i32(jump + 1)) == push
        && Vm::jump_target(x, prog.i32(push + 1)) == target
}

/// The memory numbers in a backref operand.
fn memnums(mems: &[u8]) -> impl Iterator<Item = i32> + '_ {
    mems.chunks_exact(2).map(|m| i32::from(i16::from_ne_bytes([m[0], m[1]])))
}

/// `is_mbc_newline_ex` (USE_CRNL_AS_LINE_TERMINATOR)
fn is_mbc_newline_ex(enc: Enc, sb: &[u8], p: usize, end: usize, option: u32, check_prev: bool) -> bool {
    if p >= end {
        return false;
    }
    if is_newline_crlf(option) {
        if enc.mbc_to_code(sb, p, end) == 0x0a {
            !(check_prev
                && enc.get_prev_char_head(sb, 0, p, end).is_some_and(|prev| enc.mbc_to_code(sb, prev, end) == 0x0d))
        } else {
            let pnext = p + enc.enclen(sb, p, end);
            if pnext < end && enc.mbc_to_code(sb, p, end) == 0x0d && enc.mbc_to_code(sb, pnext, end) == 0x0a {
                return true;
            }
            enc.is_mbc_newline(sb, p, end)
        }
    } else {
        enc.is_mbc_newline(sb, p, end)
    }
}

impl<'a, 'm, 'c> Vm<'a, 'm, 'c> {
    /// The VM for the `match_at` calls of one search. `str` is position 0
    /// and `end` is `sb.len()`.
    fn new(reg: &'a Regex, sb: &'a [u8], msa: &'m mut MatchArg<'c>, work: &'m mut Spare) -> Self {
        let Spare { stack, repeat_stk, mem_start_stk, mem_end_stk } = work;
        Vm {
            reg,
            prog: Reader { p: &reg.program },
            plen: reg.program.len(),
            sb,
            end: pos(sb.len()),
            enc: reg.enc,
            option: reg.options,
            case_fold_flag: reg.case_fold_flag,
            num_mem: reg.num_mem,
            pop_level: reg.stack_pop_level,
            stk: stack,
            repeat_stk,
            mem_start_stk,
            mem_end_stk,
            msa,
        }
    }

    /// `match_at` for one start position: the length of the match, if any.
    fn match_at(&mut self, sstart: usize, sprev: Option<usize>, region: &mut Option<Region<'_>>) -> VmResult<Option<isize>> {
        let n_mem = self.reg.num_mem as usize + 1; /* ADD_NUMMEM: #0 is the whole pattern for \g<0> */
        refill(self.repeat_stk, self.reg.num_repeat as usize);
        refill(self.mem_start_stk, n_mem);
        refill(self.mem_end_stk, n_mem);
        let _ = self.plen;
        self.run(pos(sstart), sprev.map_or(NULL_POS, pos), region)
    }
}

fn refill(v: &mut Vec<isize>, n: usize) {
    v.clear();
    v.resize(n, INVALID_STACK_INDEX);
}

// ---- string search used by the optimizer ----

const LO: u64 = 0x0101_0101_0101_0101;
const HI: u64 = 0x8080_8080_8080_8080;

#[inline]
fn load8(s: &[u8], p: usize) -> u64 {
    let mut b = [0; 8];
    b.copy_from_slice(&s[p..p + 8]);
    u64::from_le_bytes(b)
}

/// The high bit of each zero byte of `v`, and nothing else.
#[inline]
fn zero_bytes(v: u64) -> u64 {
    !(((v & !HI) + !HI) | v | !HI)
}

/// The first `p` in `start..end` where `target`, of two bytes or more,
/// occurs in `hay`, testing its first and last bytes at eight positions at a
/// time. The last candidate must leave room for `target`.
#[inline]
fn find_str(hay: &[u8], target: &[u8], start: usize, end: usize) -> Option<usize> {
    let last = target.len() - 1;
    let first = LO * u64::from(target[0]);
    let tail = LO * u64::from(target[last]);
    let mut p = start;
    while p + 8 <= end {
        let mut m = zero_bytes(load8(hay, p) ^ first) & zero_bytes(load8(hay, p + last) ^ tail);
        while m != 0 {
            let at = p + (m.trailing_zeros() / 8) as usize;
            if hay[at + 1..at + last] == target[1..last] {
                return Some(at);
            }
            m &= m - 1;
        }
        p += 8;
    }
    (p..end).find(|&at| hay[at..at + target.len()] == *target)
}

/// The first `b` in `hay`, reading eight bytes at a time.
#[inline]
fn find_byte(hay: &[u8], b: u8) -> Option<usize> {
    let pattern = LO * u64::from(b);
    let mut chunks = hay.chunks_exact(8);
    let mut at = 0;
    for c in &mut chunks {
        let v = u64::from_le_bytes([c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]) ^ pattern;
        // The lowest set bit marks the first zero byte of v.
        let zero = v.wrapping_sub(LO) & !v & HI;
        if zero != 0 {
            return Some(at + (zero.trailing_zeros() / 8) as usize);
        }
        at += 8;
    }
    chunks.remainder().iter().position(|&x| x == b).map(|i| at + i)
}

#[inline(never)]
fn slow_search(enc: Enc, target: &[u8], sb: &[u8], text: usize, text_end: usize, text_range: usize) -> Option<usize> {
    let tlen = target.len();
    let end = (text_end + 1).saturating_sub(tlen).min(text_range);
    let mut s = text;
    if enc.is_self_synchronizing() {
        while s < end {
            s += find_byte(&sb[s..end], target[0])?;
            if sb[s + 1..s + tlen] == target[1..] {
                return Some(s);
            }
            s += 1;
        }
        return None;
    }
    let fixed = enc.min_len() == enc.max_len();
    while s < end {
        if sb[s] == target[0] && sb[s + 1..s + tlen] == target[1..] {
            return Some(s);
        }
        s += if fixed { enc.max_len() } else { enc.enclen(sb, s, text_end) };
    }
    None
}

/// `str_lower_case_match`: `t` against the folded text of `p..end`.
#[inline]
fn str_lower_case_match(enc: Enc, case_fold_flag: u32, t: &[u8], sb: &[u8], p: usize, end: usize) -> bool {
    // Most candidates of a search fail at an ASCII first character, so
    // that one is compared here without a call.
    if let (Some(&t0), true) = (t.first(), p < end) {
        if enc.is_ascii_compatible() && sb[p] < 0x80 && sb[p].to_ascii_lowercase() != t0 {
            return false;
        }
    }
    fold_match(enc, case_fold_flag, t, sb, p, end)
}

#[inline(never)]
fn fold_match(enc: Enc, case_fold_flag: u32, t: &[u8], sb: &[u8], p: usize, end: usize) -> bool {
    let ascii = enc.is_ascii_compatible();
    let mut lowbuf = [0u8; ONIGENC_MBC_CASE_FOLD_MAXLEN];
    let mut ti = 0;
    let mut p = p;
    while ti < t.len() {
        if p >= end {
            return false;
        }
        if ascii && sb[p] < 0x80 {
            if t[ti] != sb[p].to_ascii_lowercase() {
                return false;
            }
            p += 1;
            ti += 1;
            continue;
        }
        if let Some(len) = enc.unfolded_len(sb, p, end) {
            // It folds to itself, so it is compared in place.
            if t.get(ti..ti + len) != Some(&sb[p..p + len]) {
                return false;
            }
            p += len;
            ti += len;
            continue;
        }
        let lowlen = enc.mbc_case_fold(case_fold_flag, sb, &mut p, end, &mut lowbuf);
        for &c in &lowbuf[..lowlen] {
            if ti >= t.len() || t[ti] != c {
                return false;
            }
            ti += 1;
        }
    }
    true
}

fn slow_search_ic(
    enc: Enc,
    case_fold_flag: u32,
    target: &[u8],
    sb: &[u8],
    text: usize,
    text_end: usize,
    text_range: usize,
) -> Option<usize> {
    let end = (text_end + 1).saturating_sub(target.len()).min(text_range);
    let mut s = text;
    while s < end {
        if str_lower_case_match(enc, case_fold_flag, target, sb, s, text_end) {
            return Some(s);
        }
        s += enc.enclen(sb, s, text_end);
    }
    None
}

/// Where a backward search for `target` starts: `text_start`, or the last
/// character head where `target` fits before `text_end`.
fn backward_search_start(
    enc: Enc,
    target: &[u8],
    sb: &[u8],
    adjust_text: usize,
    text_end: usize,
    text_start: usize,
) -> Option<usize> {
    let s = text_end.checked_sub(target.len())?;
    Some(if s > text_start { text_start } else { enc.left_adjust_char_head(sb, adjust_text, s, text_end) })
}

fn slow_search_backward(
    enc: Enc,
    target: &[u8],
    sb: &[u8],
    text: usize,
    adjust_text: usize,
    text_end: usize,
    text_start: usize,
) -> Option<usize> {
    let mut s = backward_search_start(enc, target, sb, adjust_text, text_end, text_start)?;
    while s >= text {
        if sb[s] == target[0] && sb[s + 1..s + target.len()] == target[1..] {
            return Some(s);
        }
        s = enc.get_prev_char_head(sb, adjust_text, s, text_end)?;
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn slow_search_backward_ic(
    enc: Enc,
    case_fold_flag: u32,
    target: &[u8],
    sb: &[u8],
    text: usize,
    adjust_text: usize,
    text_end: usize,
    text_start: usize,
) -> Option<usize> {
    let mut s = backward_search_start(enc, target, sb, adjust_text, text_end, text_start)?;
    while s >= text {
        if str_lower_case_match(enc, case_fold_flag, target, sb, s, text_end) {
            return Some(s);
        }
        s = enc.get_prev_char_head(sb, adjust_text, s, text_end)?;
    }
    None
}

/// Sunday's quick search applied to a multibyte string
fn bm_search_notrev(
    reg: &Regex,
    target: &[u8],
    sb: &[u8],
    text: usize,
    text_end: usize,
    text_range: usize,
) -> Option<usize> {
    let enc = reg.enc;
    let tlen1 = target.len() - 1;
    let end = text_range.min(text_end.saturating_sub(tlen1));
    let mut s = text;
    while s < end {
        let se = s + tlen1;
        if sb[se] == target[tlen1] && sb[s..se] == target[..tlen1] {
            return Some(s);
        }
        if s + 1 >= end {
            break;
        }
        let skip = usize::from(reg.map[usize::from(sb[se + 1])]);
        let t0 = s;
        loop {
            s += enc.enclen(sb, s, end);
            if !(s - t0 < skip && s < end) {
                break;
            }
        }
    }
    None
}

/// The first occurrence of `target` from `text`, which the encoding allows
/// to be found without regard to character heads.
fn bm_search(target: &[u8], sb: &[u8], text: usize, text_end: usize, text_range: usize) -> Option<usize> {
    let end = text_range.min((text_end + 1).saturating_sub(target.len()));
    find_str(sb, target, text, end)
}

/// Sunday's quick search applied to a multibyte string (ignore case)
fn bm_search_notrev_ic(
    reg: &Regex,
    target: &[u8],
    sb: &[u8],
    text: usize,
    text_end: usize,
    text_range: usize,
) -> Option<usize> {
    let enc = reg.enc;
    let tlen1 = target.len() - 1;
    let end = text_range.min(text_end.saturating_sub(tlen1));
    let mut s = text;
    while s < end {
        let se = s + tlen1;
        if str_lower_case_match(enc, reg.case_fold_flag, target, sb, s, se + 1) {
            return Some(s);
        }
        if s + 1 >= end {
            break;
        }
        let skip = usize::from(reg.map[usize::from(sb[se + 1])]);
        let t0 = s;
        loop {
            s += enc.enclen(sb, s, end);
            if !(s - t0 < skip && s < end) {
                break;
            }
        }
    }
    None
}

/// Sunday's quick search (ignore case)
fn bm_search_ic(
    reg: &Regex,
    target: &[u8],
    sb: &[u8],
    text: usize,
    text_end: usize,
    text_range: usize,
) -> Option<usize> {
    let tlen1 = target.len() - 1;
    let end = (text_range + tlen1).min(text_end);
    let mut s = text + tlen1;
    while s < end {
        let p = s - tlen1;
        if str_lower_case_match(reg.enc, reg.case_fold_flag, target, sb, p, s + 1) {
            return Some(p);
        }
        if s + 1 >= end {
            break;
        }
        s += usize::from(reg.map[usize::from(sb[s + 1])]);
    }
    None
}

fn map_search(
    enc: Enc,
    map: &[u8; ONIG_CHAR_TABLE_SIZE],
    sb: &[u8],
    text: usize,
    text_range: usize,
    text_end: usize,
) -> Option<usize> {
    if enc.is_single_byte() {
        let found = sb.get(text..text_range)?.iter().position(|&b| map[usize::from(b)] != 0);
        return found.map(|i| text + i);
    }
    let mut s = text;
    while s < text_range {
        if map[usize::from(sb[s])] != 0 {
            return Some(s);
        }
        s += enc.enclen(sb, s, text_end);
    }
    None
}

fn map_search_backward(
    enc: Enc,
    map: &[u8; ONIG_CHAR_TABLE_SIZE],
    sb: &[u8],
    text: usize,
    adjust_text: usize,
    text_start: usize,
    text_end: usize,
) -> Option<usize> {
    let mut s = text_start;
    while s >= text {
        if s < text_end && map[usize::from(sb[s])] != 0 {
            return Some(s);
        }
        s = enc.get_prev_char_head(sb, adjust_text, s, text_end)?;
    }
    None
}

struct SearchRange {
    low: usize,
    high: usize,
    low_prev: Option<usize>,
}

fn forward_search_range(reg: &Regex, sb: &[u8], s: usize, range: usize, want_low_prev: bool) -> Option<SearchRange> {
    let enc = reg.enc;
    let end = sb.len();
    let mut pprev = None;
    let mut low_prev = None;

    if reg.dmin > end {
        return None;
    }
    let mut p = s;
    if reg.dmin != 0 {
        if end - p <= reg.dmin {
            return None; /* fail */
        }
        if enc.max_len() == 1 {
            p += reg.dmin;
        } else {
            let q = p + reg.dmin;
            while p < q {
                p += enc.enclen(sb, p, end);
            }
        }
    }

    loop {
        // retry:
        let found = match reg.optimize {
            ONIG_OPTIMIZE_EXACT => slow_search(enc, &reg.exact, sb, p, end, range),
            ONIG_OPTIMIZE_EXACT_IC => slow_search_ic(enc, reg.case_fold_flag, &reg.exact, sb, p, end, range),
            ONIG_OPTIMIZE_EXACT_BM => bm_search(&reg.exact, sb, p, end, range),
            ONIG_OPTIMIZE_EXACT_BM_NOT_REV => bm_search_notrev(reg, &reg.exact, sb, p, end, range),
            ONIG_OPTIMIZE_EXACT_BM_IC => bm_search_ic(reg, &reg.exact, sb, p, end, range),
            ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC => bm_search_notrev_ic(reg, &reg.exact, sb, p, end, range),
            ONIG_OPTIMIZE_MAP => map_search(enc, &reg.map, sb, p, range, end),
            _ => None,
        };
        let Some(fp) = found else { return None };
        p = fp;
        if p >= range {
            return None;
        }

        let mut retry = p - s < reg.dmin;
        if !retry && reg.sub_anchor != 0 {
            match reg.sub_anchor {
                ANCHOR_BEGIN_LINE => {
                    if p != 0 {
                        let prev = enc.get_prev_char_head(sb, pprev.unwrap_or(0), p, end);
                        if !prev.is_some_and(|q| is_mbc_newline_ex(enc, sb, q, end, reg.options, false)) {
                            retry = true;
                        }
                    }
                }
                ANCHOR_END_LINE => {
                    if p == end {
                        /* USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE */
                    } else if !is_mbc_newline_ex(enc, sb, p, end, reg.options, true) {
                        retry = true;
                    }
                }
                _ => {}
            }
        }
        if retry {
            // retry_gate:
            pprev = Some(p);
            p += enc.enclen(sb, p, end);
            continue;
        }

        let (low, high);
        if reg.dmax == 0 {
            low = p;
            if want_low_prev {
                low_prev = if low > s {
                    enc.get_prev_char_head(sb, s, p, end)
                } else {
                    enc.get_prev_char_head(sb, pprev.unwrap_or(0), p, end)
                };
            }
            high = p;
        } else {
            if reg.dmax != INF {
                if p < reg.dmax {
                    low = 0;
                    if want_low_prev {
                        low_prev = enc.get_prev_char_head(sb, 0, low, end);
                    }
                } else {
                    let mut l = p - reg.dmax;
                    if l > s {
                        let (q, prev) = enc.get_right_adjust_char_head_with_prev(sb, s, l, end);
                        l = q;
                        if want_low_prev {
                            low_prev = prev.or_else(|| enc.get_prev_char_head(sb, pprev.unwrap_or(s), l, end));
                        }
                    } else if want_low_prev {
                        low_prev = enc.get_prev_char_head(sb, pprev.unwrap_or(0), l, end);
                    }
                    low = l;
                }
            } else {
                low = 0; /* unused: the caller only checks the range */
            }
            /* no needs to adjust *high, *high is used as range check only */
            high = p.saturating_sub(reg.dmin);
        }
        return Some(SearchRange { low, high, low_prev });
    }
}

fn backward_search_range(reg: &Regex, sb: &[u8], s: usize, range: usize, adjrange: usize) -> Option<(usize, usize)> {
    let enc = reg.enc;
    let end = sb.len();
    if reg.dmin > end {
        return None;
    }
    let mut p = s;
    loop {
        // retry:
        let found = match reg.optimize {
            ONIG_OPTIMIZE_EXACT | ONIG_OPTIMIZE_EXACT_BM | ONIG_OPTIMIZE_EXACT_BM_NOT_REV => {
                slow_search_backward(enc, &reg.exact, sb, range, adjrange, end, p)
            }
            ONIG_OPTIMIZE_EXACT_IC | ONIG_OPTIMIZE_EXACT_BM_IC | ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC => {
                slow_search_backward_ic(enc, reg.case_fold_flag, &reg.exact, sb, range, adjrange, end, p)
            }
            ONIG_OPTIMIZE_MAP => map_search_backward(enc, &reg.map, sb, range, adjrange, p, end),
            _ => None,
        };
        p = found?;

        if reg.sub_anchor != 0 {
            match reg.sub_anchor {
                ANCHOR_BEGIN_LINE => {
                    if let Some(prev) = enc.get_prev_char_head(sb, 0, p, end) {
                        if !is_mbc_newline_ex(enc, sb, prev, end, reg.options, false) {
                            p = prev;
                            continue;
                        }
                    }
                }
                ANCHOR_END_LINE => {
                    if p == end {
                        /* USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE */
                    } else if !is_mbc_newline_ex(enc, sb, p, end, reg.options, true) {
                        p = enc.get_prev_char_head(sb, adjrange, p, end)?;
                        continue;
                    }
                }
                _ => {}
            }
        }

        let (mut low, mut high) = (0, 0);
        if reg.dmax != INF {
            low = p.saturating_sub(reg.dmax);
            high = enc.get_right_adjust_char_head(sb, adjrange, p.saturating_sub(reg.dmin), end);
        }
        return Some((low, high));
    }
}

/// The outcome of a search: a position, ONIG_MISMATCH or an error code
/// (`OnigPosition` of C).
pub type SearchResult = isize;

/// `onig_search_gpos`: positions are offsets into `sb`. The caller clears
/// `region` first, as `onig_region_resize_clear` does in C. A `range`
/// outside `sb` is cut at its ends.
pub fn search(
    reg: &Regex,
    sb: &[u8],
    global_pos: Pos,
    start: Pos,
    range: Pos,
    mut region: Option<Region<'_>>,
    option: u32,
    check: &mut dyn FnMut() -> i32,
) -> SearchResult {
    let enc = reg.enc;
    let end = sb.len();
    let Some(mut start) = usize::try_from(start).ok().filter(|&s| s <= end) else {
        return ONIG_MISMATCH as isize;
    };
    let mut range = usize::try_from(range).map_or(0, |r| r.min(end));

    /* anchor optimize: resume search range */
    if reg.anchor != 0 && end > 0 {
        let mut min_semi_end = end;
        let mut max_semi_end = end;
        let mut do_end_buf = false;
        if reg.anchor & ANCHOR_BEGIN_POSITION != 0 {
            /* search start-position only */
            range = begin_position(start, range, global_pos);
        } else if reg.anchor & ANCHOR_BEGIN_BUF != 0 {
            /* search str-position only */
            if range > start {
                if start != 0 {
                    return ONIG_MISMATCH as isize;
                }
                range = 1;
            } else if range == 0 {
                start = 0;
                range = 0;
            } else {
                return ONIG_MISMATCH as isize;
            }
        } else if reg.anchor & ANCHOR_END_BUF != 0 {
            do_end_buf = true;
        } else if reg.anchor & ANCHOR_SEMI_END_BUF != 0 {
            max_semi_end = end;
            match enc.step_back(sb, 0, end, end, 1).filter(|&q| enc.is_mbc_newline(sb, q, end)) {
                Some(pre_end) => {
                    min_semi_end = pre_end;
                    /* USE_CRNL_AS_LINE_TERMINATOR */
                    let pre_end2 = enc.step_back(sb, 0, pre_end, end, 1);
                    if let Some(q) = pre_end2.filter(|_| is_newline_crlf(reg.options)) {
                        let nx = q + enc.enclen(sb, q, end);
                        if enc.mbc_to_code(sb, q, end) == 13 && enc.mbc_to_code(sb, nx, end) == 10 {
                            min_semi_end = q;
                        }
                    }
                    if min_semi_end > 0 && start <= min_semi_end {
                        do_end_buf = true;
                    }
                }
                None => {
                    min_semi_end = end;
                    do_end_buf = true;
                }
            }
        } else if reg.anchor & ANCHOR_ANYCHAR_STAR_ML != 0 {
            range = begin_position(start, range, global_pos);
        }

        if do_end_buf {
            // end_buf:
            if max_semi_end < reg.anchor_dmin {
                return ONIG_MISMATCH as isize;
            }
            if range > start {
                if min_semi_end - start > reg.anchor_dmax {
                    start = min_semi_end - reg.anchor_dmax;
                    if start < end {
                        start = enc.get_right_adjust_char_head(sb, 0, start, end);
                    }
                }
                if max_semi_end - (range - 1) < reg.anchor_dmin {
                    if max_semi_end + 1 < reg.anchor_dmin {
                        return ONIG_MISMATCH as isize;
                    } else {
                        range = max_semi_end + 1 - reg.anchor_dmin;
                    }
                }
                if start > range {
                    return ONIG_MISMATCH as isize;
                }
                /* If start == range, match with empty at end.
                   Backward search is used. */
            } else {
                if min_semi_end - range > reg.anchor_dmax {
                    range = min_semi_end - reg.anchor_dmax;
                }
                if max_semi_end - start < reg.anchor_dmin {
                    if max_semi_end < reg.anchor_dmin {
                        return ONIG_MISMATCH as isize;
                    } else {
                        start = enc.left_adjust_char_head(sb, 0, max_semi_end - reg.anchor_dmin, end);
                    }
                }
                if range > start {
                    return ONIG_MISMATCH as isize;
                }
            }
        }
    } else if end == 0 {
        /* empty string */
        if reg.threshold_len == 0 {
            return with_spare(|work| {
                let mut msa = MatchArg::new(option, 0, check);
                let r = try_match_at(&mut Vm::new(reg, sb, &mut msa, work), 0, None, &mut region);
                finish_result(reg, r, &msa, &mut region)
            });
        }
        return ONIG_MISMATCH as isize;
    }

    // The threshold check of search_body, before the working memory is taken.
    if reg.optimize != ONIG_OPTIMIZE_NONE {
        let left = if range > start { end - start } else { end - range };
        if left < usize::try_from(reg.threshold_len).unwrap_or(0) {
            return mismatch(reg, &mut region);
        }
    }

    with_spare(|work| {
        let mut msa = MatchArg::new(option, global_pos, check);
        let r = search_body(reg, sb, start, range, &mut msa, work, &mut region);
        finish_result(reg, r, &msa, &mut region)
    })
}

fn begin_position(start: usize, range: usize, global_pos: Pos) -> usize {
    if range <= start {
        return start;
    }
    match usize::try_from(global_pos) {
        Ok(g) if g > start => {
            if g < range {
                g + 1
            } else {
                range
            }
        }
        _ => start + 1,
    }
}

/// The common tail of `onig_search`: `r` is the start of the match, if
/// any, or an error.
fn finish_result(
    reg: &Regex,
    r: VmResult<Option<usize>>,
    msa: &MatchArg,
    region: &mut Option<Region<'_>>,
) -> SearchResult {
    let r = match r {
        Ok(Some(s)) => return pos(s),
        /* USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE */
        Ok(None) if is_find_longest(reg.options) && msa.best_len >= 0 => return msa.best_s,
        Ok(None) => return mismatch(reg, region),
        Err(e) => e,
    };
    if r != ONIGERR_TIMEOUT as isize && is_find_not_empty(reg.options) {
        if let Some(rg) = region.as_mut() {
            rg.clear();
        }
    }
    r
}

fn mismatch(reg: &Regex, region: &mut Option<Region<'_>>) -> SearchResult {
    if is_find_not_empty(reg.options) {
        if let Some(rg) = region.as_mut() {
            rg.clear();
        }
    }
    ONIG_MISMATCH as isize
}

/// The search loops of `onig_search_gpos`. Returns the start of the match,
/// if any.
fn search_body(
    reg: &Regex,
    sb: &[u8],
    start: usize,
    range: usize,
    msa: &mut MatchArg,
    work: &mut Spare,
    region: &mut Option<Region<'_>>,
) -> VmResult<Option<usize>> {
    let enc = reg.enc;
    let end = sb.len();
    let threshold_len = usize::try_from(reg.threshold_len).unwrap_or(0);
    let mut s = start;
    let mut prev: Option<usize>;
    let mut vm = Vm::new(reg, sb, msa, work);

    // MATCH_AND_RETURN_CHECK
    macro_rules! try_match {
        () => {
            if let Some(p) = try_match_at(&mut vm, s, prev, region)? {
                return Ok(Some(p));
            }
        };
    }

    if range > start {
        /* forward search */
        prev = enc.get_prev_char_head(sb, 0, s, end);

        if reg.optimize != ONIG_OPTIMIZE_NONE {
            let sch_range = if reg.dmax != 0 {
                if reg.dmax == INF {
                    end
                } else if end - range < reg.dmax {
                    end
                } else {
                    range + reg.dmax
                }
            } else {
                range
            };

            if end - start < threshold_len {
                return Ok(None);
            }

            if reg.dmax != INF {
                loop {
                    let Some(sr) = forward_search_range(reg, sb, s, sch_range, true) else {
                        return Ok(None);
                    };
                    if s < sr.low {
                        s = sr.low;
                        prev = sr.low_prev;
                    }
                    while s <= sr.high {
                        try_match!();
                        prev = Some(s);
                        s += enc.enclen(sb, s, end);
                    }
                    if s >= range {
                        break;
                    }
                }
                return Ok(None);
            } else {
                /* check only. */
                if forward_search_range(reg, sb, s, sch_range, false).is_none() {
                    return Ok(None);
                }
                if reg.anchor & ANCHOR_ANYCHAR_STAR != 0 {
                    loop {
                        try_match!();
                        let mut q = s;
                        s += enc.enclen(sb, s, end);
                        if reg.anchor & (ANCHOR_LOOK_BEHIND | ANCHOR_PREC_READ_NOT) == 0 {
                            while !is_mbc_newline_ex(enc, sb, q, end, reg.options, false) && s < range {
                                q = s;
                                s += enc.enclen(sb, s, end);
                            }
                        }
                        prev = Some(q);
                        if s >= range {
                            break;
                        }
                    }
                    return Ok(None);
                }
            }
        }

        loop {
            try_match!();
            prev = Some(s);
            s += enc.enclen(sb, s, end);
            if s >= range {
                break;
            }
        }
        if s == range {
            /* because empty match with /$/. */
            try_match!();
        }
    } else {
        /* backward search */
        if reg.optimize != ONIG_OPTIMIZE_NONE {
            let adjrange = if range < end { enc.left_adjust_char_head(sb, 0, range, end) } else { end };
            let min_range = if end - range > reg.dmin { range + reg.dmin } else { end };

            if reg.dmax != INF && end - range >= threshold_len {
                loop {
                    let sch_start = if end - s > reg.dmax { s + reg.dmax } else { end };
                    let Some((low, high)) = backward_search_range(reg, sb, sch_start, min_range, adjrange) else {
                        return Ok(None);
                    };
                    if s > high {
                        s = high;
                    }
                    while s >= low {
                        prev = enc.get_prev_char_head(sb, 0, s, end);
                        try_match!();
                        let Some(q) = prev else {
                            return Ok(None);
                        };
                        s = q;
                    }
                    if s < range {
                        break;
                    }
                }
                return Ok(None);
            } else {
                /* check only. */
                if end - range < threshold_len {
                    return Ok(None);
                }
                let sch_start = if reg.dmax != 0 {
                    if reg.dmax == INF {
                        end
                    } else if end - s > reg.dmax {
                        enc.left_adjust_char_head(sb, start, s + reg.dmax, end)
                    } else {
                        end
                    }
                } else {
                    s
                };
                if backward_search_range(reg, sb, sch_start, min_range, adjrange).is_none() {
                    return Ok(None);
                }
            }
        }

        loop {
            prev = enc.get_prev_char_head(sb, 0, s, end);
            try_match!();
            match prev {
                Some(q) if q >= range => s = q,
                _ => break,
            }
        }
    }
    Ok(None)
}

/// `match_at` at `s` for the search: the start of the match, if it is the
/// one to return.
fn try_match_at(vm: &mut Vm, s: usize, prev: Option<usize>, region: &mut Option<Region<'_>>) -> VmResult<Option<usize>> {
    Ok(match vm.match_at(s, prev, region)? {
        Some(_) if !is_find_longest(vm.reg.options) => Some(s),
        _ => None,
    })
}

/// `onig_match`: match at `at` only. Returns the match length.
pub fn match_at_pos(
    reg: &Regex,
    sb: &[u8],
    at: Pos,
    mut region: Option<Region<'_>>,
    option: u32,
    check: &mut dyn FnMut() -> i32,
) -> isize {
    let Some(at) = usize::try_from(at).ok().filter(|&a| a <= sb.len()) else {
        return ONIG_MISMATCH as isize;
    };
    let prev = reg.enc.get_prev_char_head(sb, 0, at, sb.len());
    with_spare(|work| {
        let mut msa = MatchArg::new(option, pos(at), check);
        match Vm::new(reg, sb, &mut msa, work).match_at(at, prev, &mut region) {
            Ok(len) => len.unwrap_or(ONIG_MISMATCH as isize),
            Err(e) => e,
        }
    })
}
