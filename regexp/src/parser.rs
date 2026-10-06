//! The pattern parser, ported from regparse.c. Only the paths reachable with
//! the Ruby syntax are kept. Function names follow the C ones so that the
//! two can be read side by side.

use std::sync::atomic::{AtomicU32, Ordering};

use crate::ast::*;
use crate::enc::*;
use crate::error::*;
use crate::names::NameTable;
use crate::syntax::*;

pub type R<T> = Result<T, i32>;

pub const ONIG_MAX_CAPTURE_GROUP_NUM: i32 = 32767;
pub const ONIG_MAX_BACKREF_NUM: i32 = 1000;
pub const ONIG_MAX_REPEAT_NUM: i32 = 100000;
pub const ONIG_MAX_MULTI_BYTE_RANGES_NUM: usize = 10000;
pub const DEFAULT_PARSE_DEPTH_LIMIT: u32 = 4096;
const INT_MAX_LIMIT: u32 = i32::MAX as u32;

static PARSE_DEPTH_LIMIT: AtomicU32 = AtomicU32::new(DEFAULT_PARSE_DEPTH_LIMIT);

pub fn get_parse_depth_limit() -> u32 {
    PARSE_DEPTH_LIMIT.load(Ordering::Relaxed)
}

pub fn set_parse_depth_limit(depth: u32) {
    PARSE_DEPTH_LIMIT.store(if depth == 0 { DEFAULT_PARSE_DEPTH_LIMIT } else { depth }, Ordering::Relaxed);
}

/// Where warnings go. `enabled` corresponds to `onig_warn != onig_null_warn`
/// and `verbose` to `RTEST(ruby_verbose)`.
pub trait Warner {
    fn enabled(&self) -> bool;
    fn verbose(&self) -> bool;
    fn warn(&mut self, msg: &[u8]);
}

pub struct NullWarner;

impl Warner for NullWarner {
    fn enabled(&self) -> bool {
        false
    }
    fn verbose(&self) -> bool {
        false
    }
    fn warn(&mut self, _msg: &[u8]) {}
}

pub type BitStatus = u32;
pub const BIT_STATUS_BITS_NUM: i32 = 32;

/// The bit of group `n`, or `None` when `n` is outside the width.
#[inline]
fn bit_status_bit(n: i32) -> Option<BitStatus> {
    u32::try_from(n).ok().and_then(|n| BitStatus::checked_shl(1, n))
}

#[inline]
pub fn bit_status_at(stats: BitStatus, n: i32) -> bool {
    stats & bit_status_bit(n).unwrap_or(1) != 0
}

#[inline]
pub fn bit_status_on_at(stats: &mut BitStatus, n: i32) {
    *stats |= bit_status_bit(n).unwrap_or(1);
}

#[inline]
pub fn bit_status_on_at_simple(stats: &mut BitStatus, n: i32) {
    if let Some(bit) = bit_status_bit(n) {
        *stats |= bit;
    }
}

pub struct ScanEnv {
    pub option: u32,
    pub case_fold_flag: u32,
    pub enc: Enc,
    pub syntax: &'static Syntax,
    pub capture_history: BitStatus,
    pub bt_mem_start: BitStatus,
    pub bt_mem_end: BitStatus,
    pub backrefed_mem: BitStatus,
    /// `env->error .. env->error_end`, copied.
    pub error: Option<Vec<u8>>,
    pub num_call: i32,
    pub num_mem: i32,
    pub num_named: i32,
    /// `SCANENV_MEM_NODES`: index 0 is the whole pattern when it is called.
    pub mem_nodes: Vec<Option<NodeId>>,
    pub parse_depth: u32,
    pub warnings_flag: u32,
}

impl ScanEnv {
    pub fn mem_node(&self, num: i32) -> Option<NodeId> {
        let num = usize::try_from(num).ok()?;
        self.mem_nodes.get(num).copied().flatten()
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tk {
    Eot,
    RawByte,
    Char,
    String,
    CodePoint,
    AnyChar,
    CharType,
    Backref,
    Call,
    Anchor,
    OpRepeat,
    Interval,
    Alt,
    SubexpOpen,
    SubexpClose,
    CcOpen,
    CharProperty,
    Linebreak,
    ExtendedGraphemeCluster,
    Keep,
    CcClose,
    CcRange,
    PosixBracketOpen,
    CcAnd,
    CcCcOpen,
}

#[derive(Clone, Debug)]
struct Token {
    typ: Tk,
    escaped: bool,
    base: i32,
    backp: usize,
    /// `u.c` / `u.code`
    c: u32,
    anchor_subtype: i32,
    anchor_ascii_range: bool,
    repeat_lower: i32,
    repeat_upper: i32,
    repeat_greedy: bool,
    repeat_possessive: bool,
    backref_refs: Vec<i32>,
    backref_by_name: bool,
    backref_exist_level: bool,
    backref_level: i32,
    call_name: (usize, usize),
    call_gnum: i32,
    call_rel: bool,
    prop_ctype: u32,
    prop_not: bool,
}

impl Token {
    fn new() -> Token {
        Token {
            typ: Tk::Eot,
            escaped: false,
            base: 0,
            backp: 0,
            c: 0,
            anchor_subtype: 0,
            anchor_ascii_range: false,
            repeat_lower: 0,
            repeat_upper: 0,
            repeat_greedy: true,
            repeat_possessive: false,
            backref_refs: Vec::new(),
            backref_by_name: false,
            backref_exist_level: false,
            backref_level: 0,
            call_name: (0, 0),
            call_gnum: 0,
            call_rel: false,
            prop_ctype: 0,
            prop_not: false,
        }
    }
}

/// Reduction of nested quantifiers.
#[derive(Clone, Copy, PartialEq, Eq)]
enum ReduceType {
    Asis,
    Del,
    A,
    Aq,
    Qq,
    PQq,
}

use ReduceType::*;

/* '?', '*', '+', '??', '*?', '+?'  p / c */
const REDUCE_TYPE_TABLE: [[ReduceType; 6]; 6] = [
    [Del, A, A, Qq, Aq, Asis],   /* '?'  */
    [Del, Del, Del, PQq, PQq, Del], /* '*'  */
    [A, A, Del, Asis, PQq, Del],  /* '+'  */
    [Del, Aq, Aq, Del, Aq, Aq],   /* '??' */
    [Del, Del, Del, Del, Del, Del], /* '*?' */
    [Asis, Asis, Asis, Aq, Aq, Del], /* '+?' */
];

const POPULAR_Q_STR: [&str; 6] = ["?", "*", "+", "??", "*?", "+?"];
const REDUCE_Q_STR: [&str; 7] = ["", "", "*", "*?", "??", "+ and ??", "+? and ?"];

fn reduce_type_index(t: ReduceType) -> usize {
    match t {
        Asis => 0,
        Del => 1,
        A => 2,
        Aq => 3,
        Qq => 4,
        PQq => 5,
    }
}

/// ?:0, *:1, +:2, ??:3, *?:4, +?:5
pub fn popular_quantifier_num(q: &QtfrNode) -> Option<usize> {
    if q.greedy {
        if q.lower == 0 {
            if q.upper == 1 {
                return Some(0);
            } else if is_repeat_infinite(q.upper) {
                return Some(1);
            }
        } else if q.lower == 1 && is_repeat_infinite(q.upper) {
            return Some(2);
        }
    } else if q.lower == 0 {
        if q.upper == 1 {
            return Some(3);
        } else if is_repeat_infinite(q.upper) {
            return Some(4);
        }
    } else if q.lower == 1 && is_repeat_infinite(q.upper) {
        return Some(5);
    }
    None
}

/// `onig_reduce_nested_quantifier`
pub fn reduce_nested_quantifier(ast: &mut Ast, pnode: NodeId, cnode: NodeId) {
    let (Some(pnum), Some(cnum)) = (popular_quantifier_num(ast.qtfr(pnode)), popular_quantifier_num(ast.qtfr(cnode)))
    else {
        return;
    };
    let ctarget = ast.qtfr(cnode).target;
    match REDUCE_TYPE_TABLE[cnum][pnum] {
        Del => {
            ast.nodes[pnode] = ast.nodes[cnode].clone();
        }
        A => {
            let p = ast.qtfr_mut(pnode);
            p.target = ctarget;
            p.lower = 0;
            p.upper = REPEAT_INFINITE;
            p.greedy = true;
        }
        Aq => {
            let p = ast.qtfr_mut(pnode);
            p.target = ctarget;
            p.lower = 0;
            p.upper = REPEAT_INFINITE;
            p.greedy = false;
        }
        Qq => {
            let p = ast.qtfr_mut(pnode);
            p.target = ctarget;
            p.lower = 0;
            p.upper = 1;
            p.greedy = false;
        }
        PQq => {
            let p = ast.qtfr_mut(pnode);
            p.target = Some(cnode);
            p.lower = 0;
            p.upper = 1;
            p.greedy = false;
            let c = ast.qtfr_mut(cnode);
            c.lower = 1;
            c.upper = REPEAT_INFINITE;
            c.greedy = true;
            return;
        }
        Asis => {
            ast.qtfr_mut(pnode).target = Some(cnode);
            return;
        }
    }
    ast.nodes[cnode] = Node::Freed;
}

/// `onig_is_in_code_range` over a range list.
pub fn is_in_code_range(ranges: &CodeRanges, code: CodePoint) -> bool {
    let n = ranges.len();
    let (mut low, mut high) = (0usize, n);
    while low < high {
        let x = (low + high) >> 1;
        if code > ranges[x].1 {
            low = x + 1;
        } else {
            high = x;
        }
    }
    low < n && code >= ranges[low].0
}

/// `onig_is_code_in_cc_len`
pub fn is_code_in_cc_len(elen: i32, code: CodePoint, cc: &CClass) -> bool {
    let found = if elen > 1 || code >= SINGLE_BYTE_SIZE {
        match &cc.mbuf {
            None => false,
            Some(m) => is_in_code_range(m, code),
        }
    } else {
        cc.bs.at(code)
    };
    if cc.is_not() { !found } else { found }
}

/// `onig_is_code_in_cc`
pub fn is_code_in_cc(enc: Enc, code: CodePoint, cc: &CClass) -> bool {
    let len = if enc.min_len() > 1 { 2 } else { enc.code_to_mbclen(code) };
    is_code_in_cc_len(len, code, cc)
}

#[inline]
fn mbcode_start_pos(enc: Enc) -> CodePoint {
    if enc.min_len() > 1 { 0 } else { 0x80 }
}

/// The value of `c`, a digit of the encoding.
#[inline]
fn digitval(c: u32) -> u32 {
    c - b'0' as u32
}

fn get_name_end_code_point(start: u32) -> u32 {
    match start {
        0x3c => b'>' as u32,  /* < */
        0x27 => b'\'' as u32, /* ' */
        0x28 => b')' as u32,  /* ( */
        0x7b => b'}' as u32,  /* { */
        _ => 0,
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CcState {
    Value,
    Range,
    Complete,
    Start,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CcValType {
    Sb,
    CodePoint,
    Class,
}

/// The `asc_cc` argument of `cclass_case_fold`.
#[derive(Clone, Copy)]
enum AscCc<'c> {
    None,
    /// The class being folded is also the ASCII class.
    Same,
    Other(&'c CClass),
}

/// Where a quantifier attaches in `parse_exp` (`targetp` in C).
#[derive(Clone, Copy)]
enum Slot {
    Root,
    Car(NodeId),
}

pub struct Parser<'a> {
    pub pat: &'a [u8],
    end: usize,
    pub enc: Enc,
    syn: &'static Syntax,
    pub env: ScanEnv,
    pub ast: Ast,
    pub names: NameTable,
    warner: &'a mut dyn Warner,
}

pub struct ParseResult {
    pub root: NodeId,
    pub ast: Ast,
    pub env: ScanEnv,
    pub names: NameTable,
}

/// `onig_parse_make_tree`
pub fn parse_make_tree(
    pattern: &[u8],
    option: u32,
    case_fold_flag: u32,
    enc: Enc,
    warner: &mut dyn Warner,
) -> Result<ParseResult, (i32, Option<Vec<u8>>)> {
    let env = ScanEnv {
        option,
        case_fold_flag,
        enc,
        syntax: &SYNTAX_RUBY,
        capture_history: 0,
        bt_mem_start: 0,
        bt_mem_end: 0,
        backrefed_mem: 0,
        error: None,
        num_call: 0,
        num_mem: 0,
        num_named: 0,
        mem_nodes: vec![None],
        parse_depth: 0,
        warnings_flag: 0,
    };
    let mut p = Parser {
        pat: pattern,
        end: pattern.len(),
        enc,
        syn: &SYNTAX_RUBY,
        env,
        ast: Ast::default(),
        names: NameTable::default(),
        warner,
    };
    match p.parse_regexp() {
        Ok(root) => Ok(ParseResult { root, ast: p.ast, env: p.env, names: p.names }),
        Err(e) => Err((e, p.env.error.take())),
    }
}

impl<'a> Parser<'a> {
    // scanning helpers: PEND, PFETCH, PINC, PPEEK ...

    #[inline]
    fn pend(&self, p: usize) -> bool {
        p >= self.end
    }

    #[inline]
    fn enclen(&self, p: usize) -> usize {
        self.enc.enclen(self.pat, p, self.end)
    }

    #[inline]
    fn fetch(&self, p: &mut usize, prev: &mut usize) -> u32 {
        let c = self.code_at(*p);
        *prev = *p;
        *p += self.enclen(*p);
        c
    }

    #[inline]
    fn fetch_s(&self, p: &mut usize) -> u32 {
        let c = self.code_at(*p);
        *p += self.enclen(*p);
        c
    }

    #[inline]
    fn code_at(&self, p: usize) -> u32 {
        if self.enc.max_len() == 1 { self.pat[p] as u32 } else { self.enc.mbc_to_code(self.pat, p, self.end) }
    }

    #[inline]
    fn inc(&self, p: &mut usize, prev: &mut usize) {
        *prev = *p;
        *p += self.enclen(*p);
    }

    #[inline]
    fn inc_s(&self, p: &mut usize) {
        *p += self.enclen(*p);
    }

    #[inline]
    fn peek(&self, p: usize) -> Option<u32> {
        (p < self.end).then(|| self.enc.mbc_to_code(self.pat, p, self.end))
    }

    #[inline]
    fn peek_is(&self, p: usize, c: u8) -> bool {
        self.peek(p) == Some(c as u32)
    }

    #[inline]
    fn is_mc_esc_code(&self, code: u32) -> bool {
        code == self.syn.esc && !self.syn.op2(ONIG_SYN_OP2_INEFFECTIVE_ESCAPE)
    }

    fn set_error_string(&mut self, from: usize, to: usize) {
        let to = to.min(self.end);
        let from = from.min(to);
        self.env.error = Some(self.pat[from..to].to_vec());
    }

    // warnings

    fn syntax_warn(&mut self, msg: &str) {
        let m = message_with_pattern(self.enc, self.pat, msg.as_bytes());
        self.warner.warn(&m);
    }

    fn cc_esc_warn(&mut self, c: &str) {
        if !self.warner.enabled() {
            return;
        }
        if self.syn.bv(ONIG_SYN_WARN_CC_OP_NOT_ESCAPED) && self.syn.bv(ONIG_SYN_BACKSLASH_ESCAPE_IN_CC) {
            self.syntax_warn(&format!("character class has '{}' without escape", c));
        }
    }

    fn close_bracket_without_esc_warn(&mut self, c: &str) {
        if !self.warner.enabled() {
            return;
        }
        if self.syn.bv(ONIG_SYN_WARN_CC_OP_NOT_ESCAPED) {
            self.syntax_warn(&format!("regular expression has '{}' without escape", c));
        }
    }

    fn cc_dup_warn(&mut self) {
        if !self.warner.enabled() || !self.warner.verbose() {
            return;
        }
        if self.syn.bv(ONIG_SYN_WARN_CC_DUP) && (self.env.warnings_flag & ONIG_SYN_WARN_CC_DUP) == 0 {
            self.env.warnings_flag |= ONIG_SYN_WARN_CC_DUP;
            self.syntax_warn("character class has duplicated range");
        }
    }

    fn unknown_esc_warn(&mut self, c: char) {
        if !self.warner.enabled() || !self.warner.verbose() {
            return;
        }
        self.syntax_warn(&format!("Unknown escape \\{c} is ignored"));
    }

    // bitset and code ranges

    fn bitset_set_bit_chkdup(&mut self, bs: &mut BitSet, pos: u32) {
        if bs.at(pos) {
            self.cc_dup_warn();
        }
        bs.set(pos);
    }

    fn bitset_set_range(&mut self, bs: &mut BitSet, from: u32, to: u32) {
        let mut i = from;
        while i <= to && i < SINGLE_BYTE_SIZE {
            self.bitset_set_bit_chkdup(bs, i);
            i += 1;
        }
    }

    fn add_code_range_to_buf0(
        &mut self,
        pbuf: &mut Option<CodeRanges>,
        mut from: CodePoint,
        mut to: CodePoint,
        checkdup: bool,
    ) -> R<()> {
        if from > to {
            std::mem::swap(&mut from, &mut to);
        }
        let data = pbuf.get_or_insert_with(Vec::new);

        let low = data.partition_point(|&(_, t)| t.saturating_add(1) < from);
        let high = low + data[low..].partition_point(|&(f, _)| f <= to.saturating_add(1));
        /* data[(low-1)].to << from <= data[low].from
         * data[(high-1)].to <= to << data[high].from */

        if data.len() + 1 - (high - low) > ONIG_MAX_MULTI_BYTE_RANGES_NUM {
            return Err(ONIGERR_TOO_MANY_MULTI_BYTE_RANGES);
        }

        let mut dup = false;
        if high != low {
            if checkdup && from <= data[low].1 && (data[low].0 <= from || data[low].1 <= to) {
                dup = true;
            }
            from = from.min(data[low].0);
            to = to.max(data[high - 1].1);
        }
        data.splice(low..high, std::iter::once((from, to)));
        if dup {
            self.cc_dup_warn();
        }
        Ok(())
    }

    fn add_code_range_to_buf(&mut self, pbuf: &mut Option<CodeRanges>, from: CodePoint, to: CodePoint) -> R<()> {
        self.add_code_range_to_buf0(pbuf, from, to, true)
    }

    fn add_code_range0(&mut self, pbuf: &mut Option<CodeRanges>, from: CodePoint, to: CodePoint, checkdup: bool) -> R<()> {
        if from > to {
            if self.syn.bv(ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC) {
                return Ok(());
            }
            return Err(ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS);
        }
        self.add_code_range_to_buf0(pbuf, from, to, checkdup)
    }

    fn add_code_range(&mut self, pbuf: &mut Option<CodeRanges>, from: CodePoint, to: CodePoint) -> R<()> {
        self.add_code_range0(pbuf, from, to, true)
    }

    fn set_all_multi_byte_range(&mut self, pbuf: &mut Option<CodeRanges>) -> R<()> {
        let start = mbcode_start_pos(self.enc);
        self.add_code_range_to_buf(pbuf, start, ONIG_LAST_CODE_POINT)
    }

    fn add_all_multi_byte_range(&mut self, mbuf: &mut Option<CodeRanges>) -> R<()> {
        if !self.enc.is_single_byte() {
            self.set_all_multi_byte_range(mbuf)?;
        }
        Ok(())
    }

    fn not_code_range_buf(&mut self, bbuf: Option<&CodeRanges>) -> R<Option<CodeRanges>> {
        let mut pbuf = None;
        let data = match bbuf {
            Some(d) if !d.is_empty() => d.clone(),
            _ => {
                self.set_all_multi_byte_range(&mut pbuf)?;
                return Ok(pbuf);
            }
        };
        let mut pre = mbcode_start_pos(self.enc);
        let mut to: CodePoint = 0;
        for &(from, t) in data.iter() {
            to = t;
            if pre <= from.wrapping_sub(1) {
                self.add_code_range_to_buf(&mut pbuf, pre, from.wrapping_sub(1))?;
            }
            if to == ONIG_LAST_CODE_POINT {
                break;
            }
            pre = to + 1;
        }
        if to < ONIG_LAST_CODE_POINT {
            self.add_code_range_to_buf(&mut pbuf, to + 1, ONIG_LAST_CODE_POINT)?;
        }
        Ok(pbuf)
    }

    fn or_code_range_buf<'b>(
        &mut self,
        mut bbuf1: Option<&'b CodeRanges>,
        mut not1: bool,
        mut bbuf2: Option<&'b CodeRanges>,
        mut not2: bool,
    ) -> R<Option<CodeRanges>> {
        let mut pbuf = None;
        if bbuf1.is_none() && bbuf2.is_none() {
            if not1 || not2 {
                self.set_all_multi_byte_range(&mut pbuf)?;
            }
            return Ok(pbuf);
        }
        if bbuf2.is_none() {
            std::mem::swap(&mut bbuf1, &mut bbuf2);
            std::mem::swap(&mut not1, &mut not2);
        }
        let Some(b1) = bbuf1 else {
            if not1 {
                self.set_all_multi_byte_range(&mut pbuf)?;
                return Ok(pbuf);
            } else if !not2 {
                return Ok(bbuf2.cloned());
            } else {
                return self.not_code_range_buf(bbuf2);
            }
        };
        let (b1, b2) = if not1 { (bbuf2.unwrap(), b1) } else { (b1, bbuf2.unwrap()) };
        if not1 {
            std::mem::swap(&mut not1, &mut not2);
        }
        let data1 = b1.clone();
        if !not2 && !not1 {
            /* 1 OR 2 */
            pbuf = Some(b2.clone());
        } else if !not1 {
            /* 1 OR (not 2) */
            pbuf = self.not_code_range_buf(Some(b2))?;
        }
        for &(from, to) in data1.iter() {
            self.add_code_range_to_buf(&mut pbuf, from, to)?;
        }
        Ok(pbuf)
    }

    fn and_code_range1(
        &mut self,
        pbuf: &mut Option<CodeRanges>,
        mut from1: CodePoint,
        mut to1: CodePoint,
        data: &CodeRanges,
    ) -> R<()> {
        for &(from2, to2) in data.iter() {
            if from2 < from1 {
                if to2 < from1 {
                    continue;
                }
                let Some(next) = to2.checked_add(1) else {
                    return Ok(());
                };
                from1 = next;
            } else if from2 <= to1 {
                if to2 < to1 {
                    if from1 < from2 {
                        self.add_code_range_to_buf(pbuf, from1, from2 - 1)?;
                    }
                    from1 = to2 + 1;
                } else {
                    let Some(last) = from2.checked_sub(1) else {
                        return Ok(());
                    };
                    to1 = last;
                }
            } else {
                from1 = from2;
            }
            if from1 > to1 {
                break;
            }
        }
        if from1 <= to1 {
            self.add_code_range_to_buf(pbuf, from1, to1)?;
        }
        Ok(())
    }

    fn and_code_range_buf(
        &mut self,
        bbuf1: Option<&CodeRanges>,
        not1: bool,
        bbuf2: Option<&CodeRanges>,
        not2: bool,
    ) -> R<Option<CodeRanges>> {
        let mut pbuf = None;
        let (Some(b1), Some(b2)) = (bbuf1, bbuf2) else {
            if bbuf1.is_none() {
                if not1 && bbuf2.is_some() {
                    /* not1 != 0 -> not2 == 0 */
                    return Ok(bbuf2.cloned());
                }
                return Ok(None);
            }
            if not2 {
                return Ok(bbuf1.cloned());
            }
            return Ok(None);
        };
        let (b1, not1, b2, not2) = if not1 { (b2, not2, b1, not1) } else { (b1, not1, b2, not2) };
        if !not2 && !not1 {
            /* 1 AND 2 */
            for &(from1, to1) in b1.iter() {
                for &(from2, to2) in b2.iter() {
                    if from2 > to1 {
                        break;
                    }
                    if to2 < from1 {
                        continue;
                    }
                    let from = from1.max(from2);
                    let to = to1.min(to2);
                    self.add_code_range_to_buf(&mut pbuf, from, to)?;
                }
            }
        } else if !not1 {
            /* 1 AND (not 2) */
            for &(from1, to1) in b1.iter() {
                self.and_code_range1(&mut pbuf, from1, to1, b2)?;
            }
        }
        Ok(pbuf)
    }

    fn and_cclass(&mut self, dest: &mut CClass, cc: &CClass) -> R<()> {
        let not1 = dest.is_not();
        let not2 = cc.is_not();
        let mut bsr1 = if not1 { dest.bs.inverted() } else { dest.bs };
        let bsr2 = if not2 { cc.bs.inverted() } else { cc.bs };
        bsr1.and(&bsr2);
        dest.bs = bsr1;
        if not1 {
            dest.bs.invert();
        }

        if !self.enc.is_single_byte() {
            let buf1 = dest.mbuf.take();
            let pbuf = if not1 && not2 {
                self.or_code_range_buf(buf1.as_ref(), false, cc.mbuf.as_ref(), false)?
            } else {
                let p = self.and_code_range_buf(buf1.as_ref(), not1, cc.mbuf.as_ref(), not2)?;
                if not1 { self.not_code_range_buf(p.as_ref())? } else { p }
            };
            dest.mbuf = pbuf;
        }
        Ok(())
    }

    fn or_cclass(&mut self, dest: &mut CClass, cc: &CClass) -> R<()> {
        let not1 = dest.is_not();
        let not2 = cc.is_not();
        let mut bsr1 = if not1 { dest.bs.inverted() } else { dest.bs };
        let bsr2 = if not2 { cc.bs.inverted() } else { cc.bs };
        bsr1.or(&bsr2);
        dest.bs = bsr1;
        if not1 {
            dest.bs.invert();
        }

        if !self.enc.is_single_byte() {
            let buf1 = dest.mbuf.take();
            let pbuf = if not1 && not2 {
                self.and_code_range_buf(buf1.as_ref(), false, cc.mbuf.as_ref(), false)?
            } else {
                let p = self.or_code_range_buf(buf1.as_ref(), not1, cc.mbuf.as_ref(), not2)?;
                if not1 { self.not_code_range_buf(p.as_ref())? } else { p }
            };
            dest.mbuf = pbuf;
        }
        Ok(())
    }

    fn conv_backslash_value(&mut self, c: u32) -> u32 {
        if self.syn.op(ONIG_SYN_OP_ESC_CONTROL_CHARS) {
            match c {
                0x6e => return b'\n' as u32, /* n */
                0x74 => return b'\t' as u32, /* t */
                0x72 => return b'\r' as u32, /* r */
                0x66 => return 0x0c,         /* f */
                0x61 => return 0x07,         /* a */
                0x62 => return 0x08,         /* b */
                0x65 => return 0x1b,         /* e */
                0x76 => {
                    /* v */
                    if self.syn.op2(ONIG_SYN_OP2_ESC_V_VTAB) {
                        return 0x0b;
                    }
                }
                _ => {
                    if let Some(ch) = char::from_u32(c).filter(char::is_ascii_alphabetic) {
                        self.unknown_esc_warn(ch);
                    }
                }
            }
        }
        c
    }

    // numbers

    /// `onig_scan_unsigned_number`: `None` beyond `i32::MAX`.
    fn scan_unsigned_number(&self, src: &mut usize, end: usize) -> Option<i32> {
        let mut num: i32 = 0;
        let mut p = *src;
        while p < end {
            let c = self.code_at(p);
            if !self.enc.is_code_digit(c) {
                break;
            }
            num = num.checked_mul(10)?.checked_add(i32::try_from(digitval(c)).ok()?)?;
            p += self.enc.enclen(self.pat, p, end);
        }
        *src = p;
        Some(num)
    }

    /// Reads up to `maxlen` digits: `None` beyond `i32::MAX`.
    fn scan_unsigned_hexadecimal_number(&self, src: &mut usize, maxlen: usize) -> Option<u32> {
        let mut num: u32 = 0;
        let mut p = *src;
        let mut prev = p;
        for _ in 0..maxlen {
            if self.pend(p) {
                break;
            }
            let c = self.fetch(&mut p, &mut prev);
            if !self.enc.is_code_xdigit(c) {
                p = prev;
                break;
            }
            num = num.checked_mul(16)?.checked_add(self.xdigitval(c)).filter(|&n| n <= INT_MAX_LIMIT)?;
        }
        *src = p;
        Some(num)
    }

    /// The value of `c`, a hexadecimal digit of the encoding.
    fn xdigitval(&self, c: u32) -> u32 {
        if self.enc.is_code_digit(c) {
            digitval(c)
        } else if self.enc.is_code_upper(c) {
            c - b'A' as u32 + 10
        } else {
            c - b'a' as u32 + 10
        }
    }

    /// Reads up to `maxlen` digits: `None` beyond `i32::MAX`.
    fn scan_unsigned_octal_number(&self, src: &mut usize, maxlen: usize) -> Option<u32> {
        let mut num: u32 = 0;
        let mut p = *src;
        let mut prev = p;
        for _ in 0..maxlen {
            if self.pend(p) {
                break;
            }
            let c = self.fetch(&mut p, &mut prev);
            if !(self.enc.is_code_digit(c) && c < b'8' as u32) {
                p = prev;
                break;
            }
            num = num.checked_mul(8)?.checked_add(digitval(c)).filter(|&n| n <= INT_MAX_LIMIT)?;
        }
        *src = p;
        Some(num)
    }

    // scan env

    fn scan_env_add_mem_entry(&mut self) -> R<i32> {
        let need = self.env.num_mem + 1;
        if need > ONIG_MAX_CAPTURE_GROUP_NUM {
            return Err(ONIGERR_TOO_MANY_CAPTURE_GROUPS);
        }
        self.env.num_mem += 1;
        self.env.mem_nodes.push(None);
        Ok(self.env.num_mem)
    }

    fn scan_env_set_mem_node(&mut self, num: i32, node: NodeId) -> R<()> {
        match usize::try_from(num) {
            Ok(i) if num <= self.env.num_mem => {
                self.env.mem_nodes[i] = Some(node);
                Ok(())
            }
            _ => Err(ONIGERR_PARSER_BUG),
        }
    }

    fn name_add(&mut self, name: (usize, usize), backref: i32) -> R<()> {
        if name.1 <= name.0 {
            return Err(ONIGERR_EMPTY_GROUP_NAME);
        }
        let allow = self.syn.bv(ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME);
        if !self.names.add(&self.pat[name.0..name.1], backref, allow) {
            self.set_error_string(name.0, name.1);
            return Err(ONIGERR_MULTIPLEX_DEFINED_NAME);
        }
        Ok(())
    }

    fn node_new_backref(&mut self, backrefs: &[i32], by_name: bool, exist_level: bool, nest_level: i32) -> NodeId {
        let mut state = 0;
        if by_name {
            state |= NST_NAME_REF;
        }
        if exist_level {
            state |= NST_NEST_LEVEL;
        }
        for &b in backrefs {
            if b <= self.env.num_mem && self.env.mem_node(b).is_none() {
                state |= NST_RECURSION; /* /...(\1).../ */
                break;
            }
        }
        self.ast.add(Node::BRef(BRefNode {
            state,
            back: backrefs.to_vec(),
            nest_level: if exist_level { nest_level } else { 0 },
        }))
    }

    fn node_str_cat_codepoint(&mut self, node: NodeId, c: u32) -> R<()> {
        if self.enc.is_unicode() && char::from_u32(c).is_none() {
            return Err(ONIGERR_INVALID_CODE_POINT_VALUE);
        }
        let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
        let bytes = code_to_mbc(self.enc, c, &mut buf)?;
        self.ast.str_mut(node).s.extend_from_slice(bytes);
        Ok(())
    }

    fn str_node_can_be_split(&self, node: NodeId) -> bool {
        let s = &self.ast.str(node).s;
        if !s.is_empty() {
            return self.enc.enclen(s, 0, s.len()) < s.len();
        }
        false
    }

    fn str_node_split_last_char(&mut self, node: NodeId) -> Option<NodeId> {
        let sn = self.ast.str(node);
        if sn.s.is_empty() {
            return None;
        }
        let len = sn.s.len();
        let p = self.enc.get_prev_char_head(&sn.s, 0, len, len)?;
        if p > 0 {
            /* can be split. */
            let raw = sn.is_raw();
            let tail = sn.s[p..].to_vec();
            let n = self.ast.new_str(&tail);
            if raw {
                self.ast.str_mut(n).flag |= NSTR_RAW;
            }
            self.ast.str_mut(node).s.truncate(p);
            return Some(n);
        }
        None
    }

    // tokens

    /// Returns `None` when this is not an interval (a plain char), otherwise
    /// whether it is the fixed form {n}.
    fn fetch_range_quantifier(&mut self, src: &mut usize, tok: &mut Token) -> R<Option<bool>> {
        let mut p = *src;
        let mut prev = p;
        let syn_allow = self.syn.bv(ONIG_SYN_ALLOW_INVALID_INTERVAL);
        let mut non_low = false;
        let mut fixed = false;

        if self.pend(p) {
            if syn_allow {
                return Ok(None); /* "....{" : OK! */
            }
            return Err(ONIGERR_END_PATTERN_AT_LEFT_BRACE);
        }

        if !syn_allow && matches!(self.peek(p), Some(c) if c == b')' as u32 || c == b'(' as u32 || c == b'|' as u32) {
            return Err(ONIGERR_END_PATTERN_AT_LEFT_BRACE);
        }

        let invalid = |syn_allow: bool| if syn_allow { Ok(None) } else { Err(ONIGERR_INVALID_REPEAT_RANGE_PATTERN) };
        let repeat_num =
            |n: Option<i32>| n.filter(|&n| n <= ONIG_MAX_REPEAT_NUM).ok_or(ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE);

        let mut low = repeat_num(self.scan_unsigned_number(&mut p, self.end))?;

        if p == *src {
            /* can't read low */
            if self.syn.bv(ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV) {
                /* allow {,n} as {0,n} */
                low = 0;
                non_low = true;
            } else {
                return invalid(syn_allow);
            }
        }

        if self.pend(p) {
            return invalid(syn_allow);
        }
        let mut c = self.fetch(&mut p, &mut prev);
        let up;
        if c == b',' as u32 {
            let before = p;
            let u = repeat_num(self.scan_unsigned_number(&mut p, self.end))?;
            if p == before {
                if non_low {
                    return invalid(syn_allow);
                }
                up = REPEAT_INFINITE; /* {n,} : {n,infinite} */
            } else {
                up = u;
            }
        } else {
            if non_low {
                return invalid(syn_allow);
            }
            p = prev;
            up = low; /* {n} : exact n times */
            fixed = true;
        }

        if self.pend(p) {
            return invalid(syn_allow);
        }
        c = self.fetch(&mut p, &mut prev);
        if self.syn.op(ONIG_SYN_OP_ESC_BRACE_INTERVAL) {
            if c != self.syn.esc {
                return invalid(syn_allow);
            }
            if self.pend(p) {
                return invalid(syn_allow);
            }
            c = self.fetch(&mut p, &mut prev);
        }
        if c != b'}' as u32 {
            return invalid(syn_allow);
        }

        if !is_repeat_infinite(up) && low > up {
            return Err(ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE);
        }

        tok.typ = Tk::Interval;
        tok.repeat_lower = low;
        tok.repeat_upper = up;
        *src = p;
        Ok(Some(fixed))
    }

    /// \M-, \C-, \c, or \...
    fn fetch_escaped_value(&mut self, src: &mut usize) -> R<u32> {
        let mut p = *src;
        if self.pend(p) {
            return Err(ONIGERR_END_PATTERN_AT_ESCAPE);
        }
        let mut c = self.fetch_s(&mut p);
        let esc = self.syn.esc;
        match c {
            0x4d if self.syn.op2(ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META) => {
                /* M */
                if self.pend(p) {
                    return Err(ONIGERR_END_PATTERN_AT_META);
                }
                c = self.fetch_s(&mut p);
                if c != b'-' as u32 {
                    return Err(ONIGERR_META_CODE_SYNTAX);
                }
                if self.pend(p) {
                    return Err(ONIGERR_END_PATTERN_AT_META);
                }
                c = self.fetch_s(&mut p);
                if c == esc {
                    c = self.fetch_escaped_value(&mut p)?;
                }
                c = (c & 0xff) | 0x80;
            }
            0x43 if self.syn.op2(ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL) => {
                /* C */
                if self.pend(p) {
                    return Err(ONIGERR_END_PATTERN_AT_CONTROL);
                }
                c = self.fetch_s(&mut p);
                if c != b'-' as u32 {
                    return Err(ONIGERR_CONTROL_CODE_SYNTAX);
                }
                c = self.fetch_control(&mut p)?;
            }
            0x63 if self.syn.op(ONIG_SYN_OP_ESC_C_CONTROL) => {
                /* c */
                c = self.fetch_control(&mut p)?;
            }
            _ => {
                c = self.conv_backslash_value(c);
            }
        }
        *src = p;
        Ok(c)
    }

    fn fetch_control(&mut self, p: &mut usize) -> R<u32> {
        if self.pend(*p) {
            return Err(ONIGERR_END_PATTERN_AT_CONTROL);
        }
        let mut c = self.fetch_s(p);
        if c == b'?' as u32 {
            c = 0o177;
        } else {
            if c == self.syn.esc {
                c = self.fetch_escaped_value(p)?;
            }
            c &= 0x9f;
        }
        Ok(c)
    }

    /// \k<name+n>, \k<name-n>, \k<num+n>, \k<num-n>, \k<-num+n>, \k<-num-n>
    /// Returns (exist_level, back_num, level, name_end).
    fn fetch_name_with_level(&mut self, start_code: u32, src: &mut usize) -> R<(bool, i32, i32, usize)> {
        let mut p = *src;
        let mut prev = p;
        let mut back_num = 0i32;
        let mut is_num = 0;
        let mut exist_level = false;
        let mut sign = 1;
        let mut pnum_head = *src;
        let mut level = 0;
        let end_code = get_name_end_code_point(start_code);
        let mut name_end = self.end;
        let mut r = 0;
        let mut c: u32;

        if self.pend(p) {
            return Err(ONIGERR_EMPTY_GROUP_NAME);
        }
        c = self.fetch(&mut p, &mut prev);
        if c == end_code {
            return Err(ONIGERR_EMPTY_GROUP_NAME);
        }
        if self.enc.is_code_digit(c) {
            is_num = 1;
        } else if c == b'-' as u32 {
            is_num = 2;
            sign = -1;
            pnum_head = p;
        }
        /* ONIGENC_IS_CODE_NAME is TRUE under RUBY */

        while !self.pend(p) {
            name_end = p;
            c = self.fetch(&mut p, &mut prev);
            if c == end_code || c == b')' as u32 || c == b'+' as u32 || c == b'-' as u32 {
                if is_num == 2 {
                    r = ONIGERR_INVALID_GROUP_NAME;
                }
                break;
            }
            if is_num != 0 {
                if self.enc.is_code_digit(c) {
                    is_num = 1;
                } else {
                    r = ONIGERR_INVALID_GROUP_NAME;
                    is_num = 0;
                }
            }
        }

        let mut goto_err = false;
        if r == 0 && c != end_code {
            if c == b'+' as u32 || c == b'-' as u32 {
                let flag = if c == b'-' as u32 { -1 } else { 1 };
                if self.pend(p) {
                    r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
                } else {
                    c = self.fetch(&mut p, &mut prev);
                    if !self.enc.is_code_digit(c) {
                        goto_err = true;
                    } else {
                        p = prev;
                        let lv = self.scan_unsigned_number(&mut p, self.end).ok_or(ONIGERR_TOO_BIG_NUMBER)?;
                        level = lv * flag;
                        exist_level = true;
                        let mut ok = false;
                        if !self.pend(p) {
                            c = self.fetch(&mut p, &mut prev);
                            if c == end_code {
                                ok = true;
                            }
                        }
                        if !ok {
                            goto_err = true;
                        }
                    }
                }
            } else {
                goto_err = true;
            }
            if goto_err {
                r = ONIGERR_INVALID_GROUP_NAME;
                name_end = self.end;
            }
        }

        loop {
            if r == 0 {
                if is_num != 0 {
                    match self.scan_unsigned_number(&mut pnum_head, name_end) {
                        None => return Err(ONIGERR_TOO_BIG_NUMBER),
                        Some(0) => {
                            r = ONIGERR_INVALID_GROUP_NAME;
                            name_end = self.end;
                            continue;
                        }
                        Some(n) => back_num = n * sign,
                    }
                }
                *src = p;
                return Ok((exist_level, back_num, level, name_end));
            } else {
                self.set_error_string(*src, name_end);
                return Err(r);
            }
        }
    }

    /// ref: false -> define name (don't allow number name),
    ///      true  -> reference name (allow number name).
    /// Returns (back_num, name_end).
    fn fetch_name(&mut self, start_code: u32, src: &mut usize, refer: bool) -> R<(i32, usize)> {
        let mut p = *src;
        let end_code = get_name_end_code_point(start_code);
        let mut name_end = self.end;
        let mut pnum_head = *src;
        let mut r = 0;
        let mut is_num = 0;
        let mut sign = 1;
        let mut c: u32;

        if self.pend(p) {
            return Err(ONIGERR_EMPTY_GROUP_NAME);
        }
        c = self.fetch_s(&mut p);
        if c == end_code {
            return Err(ONIGERR_EMPTY_GROUP_NAME);
        }
        if self.enc.is_code_digit(c) {
            if refer {
                is_num = 1;
            } else {
                r = ONIGERR_INVALID_GROUP_NAME;
                is_num = 0;
            }
        } else if c == b'-' as u32 {
            if refer {
                is_num = 2;
                sign = -1;
                pnum_head = p;
            } else {
                r = ONIGERR_INVALID_GROUP_NAME;
                is_num = 0;
            }
        }

        enum Exit {
            Teardown,
            Err,
        }
        let exit: Exit = 'body: {
            if r == 0 {
                while !self.pend(p) {
                    name_end = p;
                    c = self.fetch_s(&mut p);
                    if c == end_code || c == b')' as u32 {
                        if is_num == 2 {
                            r = ONIGERR_INVALID_GROUP_NAME;
                            break 'body Exit::Teardown;
                        }
                        break;
                    }
                    if is_num != 0 {
                        if self.enc.is_code_digit(c) {
                            is_num = 1;
                        } else {
                            r = if !self.enc.is_code_word(c) {
                                ONIGERR_INVALID_CHAR_IN_GROUP_NAME
                            } else {
                                ONIGERR_INVALID_GROUP_NAME
                            };
                            break 'body Exit::Teardown;
                        }
                    }
                }

                if c != end_code {
                    r = ONIGERR_INVALID_GROUP_NAME;
                    name_end = self.end;
                    break 'body Exit::Err;
                }

                let mut back_num = 0;
                if is_num != 0 {
                    match self.scan_unsigned_number(&mut pnum_head, name_end) {
                        None => return Err(ONIGERR_TOO_BIG_NUMBER),
                        Some(0) => {
                            r = ONIGERR_INVALID_GROUP_NAME;
                            break 'body Exit::Err;
                        }
                        Some(n) => back_num = n * sign,
                    }
                }
                *src = p;
                return Ok((back_num, name_end));
            }
            Exit::Teardown
        };

        if let Exit::Teardown = exit {
            while !self.pend(p) {
                name_end = p;
                c = self.fetch_s(&mut p);
                if c == end_code || c == b')' as u32 {
                    break;
                }
            }
            if self.pend(p) {
                name_end = self.end;
            }
        }
        self.set_error_string(*src, name_end);
        Err(r)
    }

    fn str_exist_check_with_esc(&self, s: &[u32], from: usize, bad: u32) -> bool {
        let to = self.end;
        let mut p = from;
        let mut in_esc = false;
        while p < to {
            if in_esc {
                in_esc = false;
                p += self.enclen(p);
            } else {
                let mut x = self.enc.mbc_to_code(self.pat, p, to);
                let mut q = p + self.enclen(p);
                if x == s[0] {
                    let mut i = 1;
                    while i < s.len() && q < to {
                        x = self.enc.mbc_to_code(self.pat, q, to);
                        if x != s[i] {
                            break;
                        }
                        q += self.enclen(q);
                        i += 1;
                    }
                    if i >= s.len() {
                        return true;
                    }
                    p += self.enclen(p);
                } else {
                    x = self.enc.mbc_to_code(self.pat, p, to);
                    if x == bad {
                        return false;
                    } else if x == self.syn.esc {
                        in_esc = true;
                    }
                    p = q;
                }
            }
        }
        false
    }

    fn fetch_token_in_cc(&mut self, tok: &mut Token, src: &mut usize) -> R<Tk> {
        let mut p = *src;
        let mut prev = p;

        if self.pend(p) {
            tok.typ = Tk::Eot;
            return Ok(tok.typ);
        }

        let mut c = self.fetch(&mut p, &mut prev);
        tok.typ = Tk::Char;
        tok.base = 0;
        tok.c = c;
        tok.escaped = false;

        if c == b']' as u32 {
            tok.typ = Tk::CcClose;
        } else if c == b'-' as u32 {
            tok.typ = Tk::CcRange;
        } else if c == self.syn.esc {
            if !self.syn.bv(ONIG_SYN_BACKSLASH_ESCAPE_IN_CC) {
                *src = p;
                return Ok(tok.typ);
            }
            if self.pend(p) {
                return Err(ONIGERR_END_PATTERN_AT_ESCAPE);
            }
            c = self.fetch(&mut p, &mut prev);
            tok.escaped = true;
            tok.c = c;
            match c {
                0x77 /* w */ => self.set_char_type(tok, CTYPE_WORD, false),
                0x57 /* W */ => self.set_char_type(tok, CTYPE_WORD, true),
                0x64 /* d */ => self.set_char_type(tok, CTYPE_DIGIT, false),
                0x44 /* D */ => self.set_char_type(tok, CTYPE_DIGIT, true),
                0x73 /* s */ => self.set_char_type(tok, CTYPE_SPACE, false),
                0x53 /* S */ => self.set_char_type(tok, CTYPE_SPACE, true),
                0x68 /* h */ if self.syn.op2(ONIG_SYN_OP2_ESC_H_XDIGIT) => self.set_char_type(tok, CTYPE_XDIGIT, false),
                0x48 /* H */ if self.syn.op2(ONIG_SYN_OP2_ESC_H_XDIGIT) => self.set_char_type(tok, CTYPE_XDIGIT, true),
                0x68 | 0x48 => {}
                0x70 | 0x50 /* p P */ => {
                    if !self.pend(p) {
                        if self.peek_is(p, b'{') && self.syn.op2(ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY) {
                            self.inc(&mut p, &mut prev);
                            tok.typ = Tk::CharProperty;
                            tok.prop_not = c == b'P' as u32;
                            if !self.pend(p) && self.syn.op2(ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT) {
                                let c2 = self.fetch(&mut p, &mut prev);
                                if c2 == b'^' as u32 {
                                    tok.prop_not = !tok.prop_not;
                                } else {
                                    p = prev;
                                }
                            }
                        } else {
                            self.syntax_warn(&format!("invalid Unicode Property \\{}", (c as u8) as char));
                        }
                    }
                }
                0x78 /* x */ => {
                    if !self.pend(p) {
                        let before = p;
                        if self.peek_is(p, b'{') && self.syn.op(ONIG_SYN_OP_ESC_X_BRACE_HEX8) {
                            self.inc(&mut p, &mut prev);
                            let num =
                                self.scan_unsigned_hexadecimal_number(&mut p, 8).ok_or(ONIGERR_TOO_BIG_WIDE_CHAR_VALUE)?;
                            if self.peek(p).is_some_and(|c2| self.enc.is_code_xdigit(c2)) {
                                return Err(ONIGERR_TOO_LONG_WIDE_CHAR_VALUE);
                            }
                            if p > before + self.enclen(before) && !self.pend(p) && self.peek_is(p, b'}') {
                                self.inc(&mut p, &mut prev);
                                tok.typ = Tk::CodePoint;
                                tok.base = 16;
                                tok.c = num;
                            } else {
                                /* can't read nothing or invalid format */
                                p = before;
                            }
                        } else if self.syn.op(ONIG_SYN_OP_ESC_X_HEX2) {
                            let mut num =
                                self.scan_unsigned_hexadecimal_number(&mut p, 2).ok_or(ONIGERR_TOO_BIG_NUMBER)?;
                            if p == before {
                                /* can't read nothing. */
                                num = 0; /* but, it's not error */
                            }
                            tok.typ = Tk::RawByte;
                            tok.base = 16;
                            tok.c = num;
                        }
                    }
                }
                0x30..=0x37 /* 0-7 */ => {
                    if self.syn.op(ONIG_SYN_OP_ESC_OCTAL3) {
                        p = prev;
                        let before = p;
                        let mut num = self
                            .scan_unsigned_octal_number(&mut p, 3)
                            .filter(|&n| n <= 0xff)
                            .ok_or(ONIGERR_TOO_BIG_NUMBER)?;
                        if p == before {
                            /* can't read nothing. */
                            num = 0; /* but, it's not error */
                        }
                        tok.typ = Tk::RawByte;
                        tok.base = 8;
                        tok.c = num;
                    }
                }
                _ => {
                    p = prev;
                    let c2 = self.fetch_escaped_value(&mut p)?;
                    if tok.c != c2 {
                        tok.c = c2;
                        tok.typ = Tk::CodePoint;
                    }
                }
            }
        } else if c == b'[' as u32 {
            let mut cc_in_cc = true;
            if self.syn.op(ONIG_SYN_OP_POSIX_BRACKET) && self.peek_is(p, b':') {
                let send = [b':' as u32, b']' as u32];
                tok.backp = p; /* point at '[' is read */
                self.inc(&mut p, &mut prev);
                if self.str_exist_check_with_esc(&send, p, b']' as u32) {
                    tok.typ = Tk::PosixBracketOpen;
                    cc_in_cc = false;
                } else {
                    p = prev;
                }
            }
            if cc_in_cc {
                if self.syn.op2(ONIG_SYN_OP2_CCLASS_SET_OP) {
                    tok.typ = Tk::CcCcOpen;
                } else {
                    self.cc_esc_warn("[");
                }
            }
        } else if c == b'&' as u32
            && self.syn.op2(ONIG_SYN_OP2_CCLASS_SET_OP)
            && !self.pend(p)
            && self.peek_is(p, b'&')
        {
            self.inc(&mut p, &mut prev);
            tok.typ = Tk::CcAnd;
        }

        *src = p;
        Ok(tok.typ)
    }

    fn set_char_type(&self, tok: &mut Token, ctype: u32, not: bool) {
        tok.typ = Tk::CharType;
        tok.prop_ctype = ctype;
        tok.prop_not = not;
    }

    fn fetch_named_backref_token(&mut self, c: u32, tok: &mut Token, src: &mut usize) -> R<()> {
        let mut p = *src;
        let before = p;
        let (exist_level, mut back_num, level, name_end) = self.fetch_name_with_level(c, &mut p)?;
        tok.backref_exist_level = exist_level;
        tok.backref_level = level;

        if back_num != 0 {
            if back_num < 0 {
                back_num = self.env.num_mem + 1 + back_num;
                if back_num <= 0 {
                    return Err(ONIGERR_INVALID_BACKREF);
                }
            }
            tok.typ = Tk::Backref;
            tok.backref_by_name = false;
            tok.backref_refs = vec![back_num];
        } else {
            let backs = match self.names.find(&self.pat[before..name_end]) {
                Some(e) if !e.back_refs.is_empty() => e.back_refs.clone(),
                _ => {
                    self.set_error_string(before, name_end);
                    return Err(ONIGERR_UNDEFINED_NAME_REFERENCE);
                }
            };
            tok.typ = Tk::Backref;
            tok.backref_by_name = true;
            tok.backref_refs = backs;
        }
        *src = p;
        Ok(())
    }

    fn greedy_check(&self, tok: &mut Token, p: &mut usize, prev: &mut usize) {
        if !self.pend(*p) && self.peek_is(*p, b'?') && self.syn.op(ONIG_SYN_OP_QMARK_NON_GREEDY) {
            self.fetch(p, prev);
            tok.repeat_greedy = false;
            tok.repeat_possessive = false;
        } else {
            self.possessive_check(tok, p, prev);
        }
    }

    fn possessive_check(&self, tok: &mut Token, p: &mut usize, prev: &mut usize) {
        if !self.pend(*p)
            && self.peek_is(*p, b'+')
            && ((self.syn.op2(ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT) && tok.typ != Tk::Interval)
                || (self.syn.op2(ONIG_SYN_OP2_PLUS_POSSESSIVE_INTERVAL) && tok.typ == Tk::Interval))
        {
            self.fetch(p, prev);
            tok.repeat_greedy = true;
            tok.repeat_possessive = true;
        } else {
            tok.repeat_greedy = true;
            tok.repeat_possessive = false;
        }
    }

    fn set_repeat(&self, tok: &mut Token, lower: i32, upper: i32, p: &mut usize, prev: &mut usize) {
        tok.typ = Tk::OpRepeat;
        tok.repeat_lower = lower;
        tok.repeat_upper = upper;
        self.greedy_check(tok, p, prev);
    }

    fn fetch_token(&mut self, tok: &mut Token, src: &mut usize) -> R<Tk> {
        let syn = self.syn;
        let mut p = *src;
        let mut prev = p;

        'start: loop {
            if self.pend(p) {
                tok.typ = Tk::Eot;
                return Ok(tok.typ);
            }

            tok.typ = Tk::String;
            tok.base = 0;
            tok.backp = p;

            let mut c = self.fetch(&mut p, &mut prev);
            if self.is_mc_esc_code(c) {
                if self.pend(p) {
                    return Err(ONIGERR_END_PATTERN_AT_ESCAPE);
                }
                tok.backp = p;
                c = self.fetch(&mut p, &mut prev);
                tok.c = c;
                tok.escaped = true;
                match c {
                    0x77 /* w */ if syn.op(ONIG_SYN_OP_ESC_W_WORD) => self.set_char_type(tok, CTYPE_WORD, false),
                    0x57 /* W */ if syn.op(ONIG_SYN_OP_ESC_W_WORD) => self.set_char_type(tok, CTYPE_WORD, true),
                    0x62 | 0x42 /* b B */ if syn.op(ONIG_SYN_OP_ESC_B_WORD_BOUND) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype = if c == 0x62 { ANCHOR_WORD_BOUND } else { ANCHOR_NOT_WORD_BOUND };
                        tok.anchor_ascii_range =
                            is_ascii_range(self.env.option) && !is_word_bound_all_range(self.env.option);
                    }
                    0x73 /* s */ if syn.op(ONIG_SYN_OP_ESC_S_WHITE_SPACE) => self.set_char_type(tok, CTYPE_SPACE, false),
                    0x53 /* S */ if syn.op(ONIG_SYN_OP_ESC_S_WHITE_SPACE) => self.set_char_type(tok, CTYPE_SPACE, true),
                    0x64 /* d */ if syn.op(ONIG_SYN_OP_ESC_D_DIGIT) => self.set_char_type(tok, CTYPE_DIGIT, false),
                    0x44 /* D */ if syn.op(ONIG_SYN_OP_ESC_D_DIGIT) => self.set_char_type(tok, CTYPE_DIGIT, true),
                    0x68 /* h */ if syn.op2(ONIG_SYN_OP2_ESC_H_XDIGIT) => self.set_char_type(tok, CTYPE_XDIGIT, false),
                    0x48 /* H */ if syn.op2(ONIG_SYN_OP2_ESC_H_XDIGIT) => self.set_char_type(tok, CTYPE_XDIGIT, true),
                    0x41 /* A */ if syn.op(ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype = ANCHOR_BEGIN_BUF;
                    }
                    0x5a /* Z */ if syn.op(ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype = ANCHOR_SEMI_END_BUF;
                    }
                    0x7a /* z */ if syn.op(ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype = ANCHOR_END_BUF;
                    }
                    0x47 /* G */ if syn.op(ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype = ANCHOR_BEGIN_POSITION;
                    }
                    0x78 /* x */ => {
                        if !self.pend(p) {
                            let before = p;
                            if self.peek_is(p, b'{') && syn.op(ONIG_SYN_OP_ESC_X_BRACE_HEX8) {
                                self.inc(&mut p, &mut prev);
                                let num = self
                                    .scan_unsigned_hexadecimal_number(&mut p, 8)
                                    .ok_or(ONIGERR_TOO_BIG_WIDE_CHAR_VALUE)?;
                                if self.peek(p).is_some_and(|c2| self.enc.is_code_xdigit(c2)) {
                                    return Err(ONIGERR_TOO_LONG_WIDE_CHAR_VALUE);
                                }
                                if p > before + self.enclen(before) && !self.pend(p) && self.peek_is(p, b'}') {
                                    self.inc(&mut p, &mut prev);
                                    tok.typ = Tk::CodePoint;
                                    tok.c = num;
                                } else {
                                    /* can't read nothing or invalid format */
                                    p = before;
                                }
                            } else if syn.op(ONIG_SYN_OP_ESC_X_HEX2) {
                                let mut num =
                                    self.scan_unsigned_hexadecimal_number(&mut p, 2).ok_or(ONIGERR_TOO_BIG_NUMBER)?;
                                if p == before {
                                    /* can't read nothing. */
                                    num = 0; /* but, it's not error */
                                }
                                tok.typ = Tk::RawByte;
                                tok.base = 16;
                                tok.c = num;
                            }
                        }
                    }
                    0x31..=0x39 /* 1-9 */ => {
                        p = prev;
                        let before = p;
                        let backref = self.scan_unsigned_number(&mut p, self.end).filter(|&num| {
                            num <= ONIG_MAX_BACKREF_NUM
                                && syn.op(ONIG_SYN_OP_DECIMAL_BACKREF)
                                && (num <= self.env.num_mem || num <= 9)
                        });
                        if let Some(num) = backref {
                            /* This spec. from GNU regex */
                            tok.typ = Tk::Backref;
                            tok.backref_refs = vec![num];
                            tok.backref_by_name = false;
                            tok.backref_exist_level = false;
                        } else {
                            /* skip_backref: */
                            if c == b'8' as u32 || c == b'9' as u32 {
                                /* normal char */
                                p = before;
                                self.inc(&mut p, &mut prev);
                            } else {
                                p = before;
                                self.fetch_octal_escape(tok, &mut p, c)?;
                            }
                        }
                    }
                    0x30 /* 0 */ => {
                        self.fetch_octal_escape(tok, &mut p, c)?;
                    }
                    0x6b /* k */ => {
                        if !self.pend(p) && syn.op2(ONIG_SYN_OP2_ESC_K_NAMED_BACKREF) {
                            c = self.fetch(&mut p, &mut prev);
                            if c == b'<' as u32 || c == b'\'' as u32 {
                                self.fetch_named_backref_token(c, tok, &mut p)?;
                            } else {
                                p = prev;
                                self.syntax_warn("invalid back reference");
                            }
                        }
                    }
                    0x67 /* g */ => {
                        if !self.pend(p) && syn.op2(ONIG_SYN_OP2_ESC_G_SUBEXP_CALL) {
                            c = self.fetch(&mut p, &mut prev);
                            if c == b'<' as u32 || c == b'\'' as u32 {
                                let mut gnum = None;
                                let mut rel = false;
                                let mut name_end = p;
                                if self.peek_is(p, b'0') {
                                    self.inc(&mut p, &mut prev);
                                    if self.peek(p) == Some(get_name_end_code_point(c)) {
                                        /* \g<0>, \g'0' */
                                        self.inc(&mut p, &mut prev);
                                        name_end = p;
                                        gnum = Some(0);
                                    }
                                } else if self.peek_is(p, b'+') {
                                    self.inc(&mut p, &mut prev);
                                    rel = true;
                                }
                                let name = p;
                                let gnum = match gnum {
                                    Some(g) => g,
                                    None => {
                                        let (g, ne) = self.fetch_name(c, &mut p, true)?;
                                        name_end = ne;
                                        g
                                    }
                                };
                                tok.typ = Tk::Call;
                                tok.call_name = (name, name_end);
                                tok.call_gnum = gnum;
                                tok.call_rel = rel;
                            } else {
                                self.syntax_warn("invalid subexp call");
                                p = prev;
                            }
                        }
                    }
                    0x70 | 0x50 /* p P */ => {
                        if self.peek_is(p, b'{') && syn.op2(ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY) {
                            self.inc(&mut p, &mut prev);
                            tok.typ = Tk::CharProperty;
                            tok.prop_not = c == b'P' as u32;
                            if !self.pend(p) && syn.op2(ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT) {
                                let c2 = self.fetch(&mut p, &mut prev);
                                if c2 == b'^' as u32 {
                                    tok.prop_not = !tok.prop_not;
                                } else {
                                    p = prev;
                                }
                            }
                        } else {
                            self.syntax_warn(&format!("invalid Unicode Property \\{}", (c as u8) as char));
                        }
                    }
                    0x52 /* R */ if syn.op2(ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK) => tok.typ = Tk::Linebreak,
                    0x58 /* X */ if syn.op2(ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER) => {
                        tok.typ = Tk::ExtendedGraphemeCluster
                    }
                    0x4b /* K */ if syn.op2(ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP) => tok.typ = Tk::Keep,
                    /* escaped meta characters that the Ruby syntax leaves alone */
                    0x2a | 0x2b | 0x3f | 0x7b | 0x7c | 0x28 | 0x29 | 0x3c | 0x3e | 0x60 | 0x27 | 0x51 | 0x75 | 0x6f
                        if !self.default_escape_applies(c) => {}
                    _ => {
                        p = prev;
                        let c2 = self.fetch_escaped_value(&mut p)?;
                        /* set_raw: */
                        if tok.c != c2 {
                            tok.typ = Tk::CodePoint;
                            tok.c = c2;
                        } else {
                            /* string */
                            p = tok.backp + self.enclen(tok.backp);
                        }
                    }
                }
            } else {
                tok.c = c;
                tok.escaped = false;

                match c {
                    0x2e /* . */ if syn.op(ONIG_SYN_OP_DOT_ANYCHAR) => tok.typ = Tk::AnyChar,
                    0x2a /* * */ if syn.op(ONIG_SYN_OP_ASTERISK_ZERO_INF) => {
                        self.set_repeat(tok, 0, REPEAT_INFINITE, &mut p, &mut prev)
                    }
                    0x2b /* + */ if syn.op(ONIG_SYN_OP_PLUS_ONE_INF) => {
                        self.set_repeat(tok, 1, REPEAT_INFINITE, &mut p, &mut prev)
                    }
                    0x3f /* ? */ if syn.op(ONIG_SYN_OP_QMARK_ZERO_ONE) => self.set_repeat(tok, 0, 1, &mut p, &mut prev),
                    0x7b /* { */ if syn.op(ONIG_SYN_OP_BRACE_INTERVAL) => {
                        match self.fetch_range_quantifier(&mut p, tok)? {
                            Some(false) => self.greedy_check(tok, &mut p, &mut prev),
                            Some(true) => {
                                /* {n} */
                                if syn.bv(ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY) {
                                    self.possessive_check(tok, &mut p, &mut prev);
                                } else {
                                    self.greedy_check(tok, &mut p, &mut prev);
                                }
                            }
                            None => {} /* normal char */
                        }
                    }
                    0x7c /* | */ if syn.op(ONIG_SYN_OP_VBAR_ALT) => tok.typ = Tk::Alt,
                    0x28 /* ( */ => {
                        if self.peek_is(p, b'?') && syn.op2(ONIG_SYN_OP2_QMARK_GROUP_EFFECT) {
                            self.inc(&mut p, &mut prev);
                            if self.peek_is(p, b'#') {
                                self.fetch(&mut p, &mut prev);
                                loop {
                                    if self.pend(p) {
                                        return Err(ONIGERR_END_PATTERN_IN_GROUP);
                                    }
                                    c = self.fetch(&mut p, &mut prev);
                                    if c == syn.esc {
                                        if !self.pend(p) {
                                            self.fetch(&mut p, &mut prev);
                                        }
                                    } else if c == b')' as u32 {
                                        break;
                                    }
                                }
                                continue 'start;
                            }
                            p = prev;
                        }
                        if syn.op(ONIG_SYN_OP_LPAREN_SUBEXP) {
                            tok.typ = Tk::SubexpOpen;
                        }
                    }
                    0x29 /* ) */ if syn.op(ONIG_SYN_OP_LPAREN_SUBEXP) => tok.typ = Tk::SubexpClose,
                    0x5e /* ^ */ if syn.op(ONIG_SYN_OP_LINE_ANCHOR) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype =
                            if is_singleline(self.env.option) { ANCHOR_BEGIN_BUF } else { ANCHOR_BEGIN_LINE };
                    }
                    0x24 /* $ */ if syn.op(ONIG_SYN_OP_LINE_ANCHOR) => {
                        tok.typ = Tk::Anchor;
                        tok.anchor_subtype =
                            if is_singleline(self.env.option) { ANCHOR_SEMI_END_BUF } else { ANCHOR_END_LINE };
                    }
                    0x5b /* [ */ if syn.op(ONIG_SYN_OP_BRACKET_CC) => tok.typ = Tk::CcOpen,
                    0x5d /* ] */ => {
                        if *src > 0 {
                            /* /].../ is allowed. */
                            self.close_bracket_without_esc_warn("]");
                        }
                    }
                    0x23 /* # */ => {
                        if is_extend(self.env.option) {
                            while !self.pend(p) {
                                c = self.fetch(&mut p, &mut prev);
                                if self.enc.is_code_newline(c) {
                                    break;
                                }
                            }
                            continue 'start;
                        }
                    }
                    0x20 | 0x09 | 0x0a | 0x0d | 0x0c => {
                        if is_extend(self.env.option) {
                            continue 'start;
                        }
                    }
                    _ => {
                        /* string */
                    }
                }
            }
            break;
        }

        *src = p;
        Ok(tok.typ)
    }

    /// Escapes of regparse.c's `fetch_token` that fall to `default` with the
    /// Ruby syntax: the operator is disabled, so the character is literal.
    fn default_escape_applies(&self, c: u32) -> bool {
        let syn = self.syn;
        match c {
            0x2a => syn.op(ONIG_SYN_OP_ESC_ASTERISK_ZERO_INF),
            0x2b => syn.op(ONIG_SYN_OP_ESC_PLUS_ONE_INF),
            0x3f => syn.op(ONIG_SYN_OP_ESC_QMARK_ZERO_ONE),
            0x7b => syn.op(ONIG_SYN_OP_ESC_BRACE_INTERVAL),
            0x7c => syn.op(ONIG_SYN_OP_ESC_VBAR_ALT),
            0x28 | 0x29 => syn.op(ONIG_SYN_OP_ESC_LPAREN_SUBEXP),
            0x3c | 0x3e => syn.op(ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END),
            0x60 | 0x27 => syn.op2(ONIG_SYN_OP2_ESC_GNU_BUF_ANCHOR),
            0x51 => syn.op2(ONIG_SYN_OP2_ESC_CAPITAL_Q_QUOTE),
            0x75 => syn.op2(ONIG_SYN_OP2_ESC_U_HEX4),
            0x6f => syn.op(ONIG_SYN_OP_ESC_O_BRACE_OCTAL),
            _ => true,
        }
    }

    fn fetch_octal_escape(&mut self, tok: &mut Token, p: &mut usize, c: u32) -> R<()> {
        if self.syn.op(ONIG_SYN_OP_ESC_OCTAL3) {
            let before = *p;
            let mut num = self
                .scan_unsigned_octal_number(p, if c == b'0' as u32 { 2 } else { 3 })
                .filter(|&n| n <= 0xff)
                .ok_or(ONIGERR_TOO_BIG_NUMBER)?;
            if *p == before {
                /* can't read nothing. */
                num = 0; /* but, it's not error */
            }
            tok.typ = Tk::RawByte;
            tok.base = 8;
            tok.c = num;
        } else if c != b'0' as u32 {
            let mut prev = *p;
            self.inc(p, &mut prev);
        }
        Ok(())
    }

    // character classes

    fn add_ctype_to_cc_by_range(&mut self, cc: &mut CClass, not: bool, sb_out: CodePoint, mbr: &[CodePoint]) -> R<()> {
        let n = mbr[0] as usize;
        let from = |i: usize| mbr[i * 2 + 1];
        let to = |i: usize| mbr[i * 2 + 2];

        if !not {
            let mut i = 0;
            'outer: while i < n {
                for j in from(i)..=to(i) {
                    if j >= sb_out {
                        if j > from(i) {
                            self.add_code_range_to_buf(&mut cc.mbuf, j, to(i))?;
                            i += 1;
                        }
                        break 'outer;
                    }
                    self.bitset_set_bit_chkdup(&mut cc.bs, j);
                }
                i += 1;
            }
            /* sb_end: */
            while i < n {
                self.add_code_range_to_buf(&mut cc.mbuf, from(i), to(i))?;
                i += 1;
            }
        } else {
            let mut prev: CodePoint = 0;
            let mut reached_sb_out = false;
            'outer: for i in 0..n {
                let mut j = prev;
                while j < from(i) {
                    if j >= sb_out {
                        reached_sb_out = true;
                        break 'outer;
                    }
                    self.bitset_set_bit_chkdup(&mut cc.bs, j);
                    j += 1;
                }
                prev = to(i).saturating_add(1);
            }
            if !reached_sb_out {
                let mut j = prev;
                while j < sb_out {
                    self.bitset_set_bit_chkdup(&mut cc.bs, j);
                    j += 1;
                }
            }
            /* sb_end2: */
            prev = sb_out;
            for i in 0..n {
                if prev < from(i) {
                    self.add_code_range_to_buf(&mut cc.mbuf, prev, from(i) - 1)?;
                }
                prev = to(i).saturating_add(1);
            }
            if prev < 0x7fffffff {
                self.add_code_range_to_buf(&mut cc.mbuf, prev, 0x7fffffff)?;
            }
        }
        Ok(())
    }

    fn add_ctype_to_cc(&mut self, cc: &mut CClass, ctype: u32, not: bool, ascii_range: bool) -> R<()> {
        let enc = self.enc;
        match enc.get_ctype_code_range(ctype) {
            Ok((sb_out, ranges)) => {
                if ascii_range {
                    let mut ccwork = CClass::default();
                    self.add_ctype_to_cc_by_range(&mut ccwork, not, sb_out, ranges)?;
                    if not {
                        self.add_code_range_to_buf0(&mut ccwork.mbuf, 0x80, ONIG_LAST_CODE_POINT, false)?;
                    } else {
                        let mut ccascii = CClass::default();
                        if enc.min_len() > 1 {
                            self.add_code_range(&mut ccascii.mbuf, 0x00, 0x7F)?;
                        } else {
                            self.bitset_set_range(&mut ccascii.bs, 0x00, 0x7F);
                        }
                        self.and_cclass(&mut ccwork, &ccascii)?;
                    }
                    self.or_cclass(cc, &ccwork)?;
                } else {
                    self.add_ctype_to_cc_by_range(cc, not, sb_out, ranges)?;
                }
                return Ok(());
            }
            Err(r) if r != ONIG_NO_SUPPORT_CONFIG => return Err(r),
            Err(_) => {}
        }

        let maxcode: u32 = if ascii_range { 0x80 } else { SINGLE_BYTE_SIZE };
        match ctype {
            CTYPE_ALPHA | CTYPE_BLANK | CTYPE_CNTRL | CTYPE_DIGIT | CTYPE_LOWER | CTYPE_PUNCT | CTYPE_SPACE
            | CTYPE_UPPER | CTYPE_XDIGIT | CTYPE_ASCII | CTYPE_ALNUM => {
                if not {
                    for c in 0..SINGLE_BYTE_SIZE {
                        if !enc.is_code_ctype(c, ctype) {
                            self.bitset_set_bit_chkdup(&mut cc.bs, c);
                        }
                    }
                    self.add_all_multi_byte_range(&mut cc.mbuf)?;
                } else {
                    for c in 0..SINGLE_BYTE_SIZE {
                        if enc.is_code_ctype(c, ctype) {
                            self.bitset_set_bit_chkdup(&mut cc.bs, c);
                        }
                    }
                }
            }
            CTYPE_GRAPH | CTYPE_PRINT => {
                if not {
                    for c in 0..SINGLE_BYTE_SIZE {
                        if !enc.is_code_ctype(c, ctype) || c >= maxcode {
                            self.bitset_set_bit_chkdup(&mut cc.bs, c);
                        }
                    }
                    if ascii_range {
                        self.add_all_multi_byte_range(&mut cc.mbuf)?;
                    }
                } else {
                    for c in 0..maxcode {
                        if enc.is_code_ctype(c, ctype) {
                            self.bitset_set_bit_chkdup(&mut cc.bs, c);
                        }
                    }
                    if !ascii_range {
                        self.add_all_multi_byte_range(&mut cc.mbuf)?;
                    }
                }
            }
            CTYPE_WORD => {
                if !not {
                    for c in 0..maxcode {
                        if enc.is_code_word(c) {
                            self.bitset_set_bit_chkdup(&mut cc.bs, c);
                        }
                    }
                    if !ascii_range {
                        self.add_all_multi_byte_range(&mut cc.mbuf)?;
                    }
                } else {
                    for c in 0..SINGLE_BYTE_SIZE {
                        /* check invalid code point */
                        if enc.code_to_mbclen(c) > 0 && (!enc.is_code_word(c) || c >= maxcode) {
                            self.bitset_set_bit_chkdup(&mut cc.bs, c);
                        }
                    }
                    if ascii_range {
                        self.add_all_multi_byte_range(&mut cc.mbuf)?;
                    }
                }
            }
            _ => return Err(ONIGERR_PARSER_BUG),
        }
        Ok(())
    }

    /// Returns false when this is not a POSIX bracket (no error).
    fn parse_posix_bracket(&mut self, cc: &mut CClass, asc_cc: Option<&mut CClass>, src: &mut usize) -> R<bool> {
        const PBS: [(&[u8], u32); 14] = [
            (b"alnum", CTYPE_ALNUM),
            (b"alpha", CTYPE_ALPHA),
            (b"blank", CTYPE_BLANK),
            (b"cntrl", CTYPE_CNTRL),
            (b"digit", CTYPE_DIGIT),
            (b"graph", CTYPE_GRAPH),
            (b"lower", CTYPE_LOWER),
            (b"print", CTYPE_PRINT),
            (b"punct", CTYPE_PUNCT),
            (b"space", CTYPE_SPACE),
            (b"upper", CTYPE_UPPER),
            (b"xdigit", CTYPE_XDIGIT),
            (b"ascii", CTYPE_ASCII),
            (b"word", CTYPE_WORD),
        ];
        const POSIX_BRACKET_CHECK_LIMIT_LENGTH: i32 = 20;
        const POSIX_BRACKET_NAME_MIN_LEN: usize = 4;

        let enc = self.enc;
        let mut p = *src;
        let not = if self.peek_is(p, b'^') {
            self.inc_s(&mut p);
            true
        } else {
            false
        };

        if enc.strlen(self.pat, p, self.end) >= POSIX_BRACKET_NAME_MIN_LEN + 3 {
            let ascii_range = is_ascii_range(self.env.option) && !is_posix_bracket_all_range(self.env.option);
            for (name, ctype) in PBS {
                if enc.with_ascii_strncmp(self.pat, p, self.end, name) == 0 {
                    let Some(q) = enc.step(self.pat, p, self.end, name.len()) else {
                        return Err(ONIGERR_INVALID_POSIX_BRACKET_TYPE);
                    };
                    p = q;
                    if enc.with_ascii_strncmp(self.pat, p, self.end, b":]") != 0 {
                        return Err(ONIGERR_INVALID_POSIX_BRACKET_TYPE);
                    }
                    self.add_ctype_to_cc(cc, ctype, not, ascii_range)?;
                    if let Some(asc_cc) = asc_cc {
                        if ctype != CTYPE_WORD && ctype != CTYPE_ASCII && !ascii_range {
                            self.add_ctype_to_cc(asc_cc, ctype, not, ascii_range)?;
                        }
                    }
                    self.inc_s(&mut p);
                    self.inc_s(&mut p);
                    *src = p;
                    return Ok(true);
                }
            }
        }

        /* not_posix_bracket: */
        let mut c = None;
        let mut i = 0;
        while !self.pend(p) && {
            c = self.peek(p);
            c != Some(b':' as u32)
        } && c != Some(b']' as u32)
        {
            self.inc_s(&mut p);
            i += 1;
            if i > POSIX_BRACKET_CHECK_LIMIT_LENGTH {
                break;
            }
        }
        if c == Some(b':' as u32) && !self.pend(p) {
            self.inc_s(&mut p);
            if !self.pend(p) && self.fetch_s(&mut p) == b']' as u32 {
                return Err(ONIGERR_INVALID_POSIX_BRACKET_TYPE);
            }
        }
        Ok(false)
    }

    fn fetch_char_property_to_ctype(&mut self, src: &mut usize) -> R<u32> {
        let mut r = ONIGERR_INVALID_CHAR_PROPERTY_NAME;
        let mut p = *src;
        let start = p;
        let mut prev = p;
        while !self.pend(p) {
            prev = p;
            let c = self.fetch_s(&mut p);
            if c == b'}' as u32 {
                r = self.enc.property_name_to_ctype(&self.pat[start..prev]);
                let Ok(ctype) = u32::try_from(r) else {
                    break;
                };
                *src = p;
                return Ok(ctype);
            } else if c == b'(' as u32 || c == b')' as u32 || c == b'{' as u32 || c == b'|' as u32 {
                break;
            }
        }
        self.set_error_string(*src, prev);
        Err(r)
    }

    fn parse_char_property(&mut self, tok: &Token, src: &mut usize) -> R<NodeId> {
        let ctype = self.fetch_char_property_to_ctype(src)?;
        let mut cc = CClass::default();
        self.add_ctype_to_cc(&mut cc, ctype, false, false)?;
        if tok.prop_not {
            cc.set_not();
        }
        let ignorecase = is_ignorecase(self.env.option);
        let mut np = self.ast.add(Node::CClass(cc.clone()));
        if ignorecase && ctype != CTYPE_ASCII {
            /* regparse.c passes the class itself as the ASCII class */
            np = self.cclass_case_fold(np, cc, AscCc::Same)?;
        }
        Ok(np)
    }

    fn next_state_class(
        &mut self,
        cc: &mut CClass,
        asc_cc: &mut Option<CClass>,
        vs: &mut u32,
        typ: &mut CcValType,
        state: &mut CcState,
    ) -> R<()> {
        if *state == CcState::Range {
            return Err(ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE);
        }
        if *state == CcState::Value && *typ != CcValType::Class {
            if *typ == CcValType::Sb {
                self.bitset_set_bit_chkdup(&mut cc.bs, *vs);
                if let Some(a) = asc_cc {
                    a.bs.set(*vs);
                }
            } else if *typ == CcValType::CodePoint {
                self.add_code_range(&mut cc.mbuf, *vs, *vs)?;
                if let Some(a) = asc_cc {
                    self.add_code_range0(&mut a.mbuf, *vs, *vs, false)?;
                }
            }
        }
        *state = CcState::Value;
        *typ = CcValType::Class;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn next_state_val(
        &mut self,
        cc: &mut CClass,
        asc_cc: &mut Option<CClass>,
        from: &mut u32,
        to: u32,
        from_israw: &mut bool,
        to_israw: bool,
        intype: CcValType,
        typ: &mut CcValType,
        state: &mut CcState,
    ) -> R<()> {
        match *state {
            CcState::Value => {
                if *typ == CcValType::Sb {
                    self.bitset_set_bit_chkdup(&mut cc.bs, *from);
                    if let Some(a) = asc_cc {
                        a.bs.set(*from);
                    }
                } else if *typ == CcValType::CodePoint {
                    self.add_code_range(&mut cc.mbuf, *from, *from)?;
                    if let Some(a) = asc_cc {
                        self.add_code_range0(&mut a.mbuf, *from, *from, false)?;
                    }
                }
            }
            CcState::Range => {
                'ccs_range_end: {
                    if intype == *typ {
                        if intype == CcValType::Sb {
                            if *from > 0xff || to > 0xff {
                                return Err(ONIGERR_INVALID_CODE_POINT_VALUE);
                            }
                            if *from > to {
                                if self.syn.bv(ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC) {
                                    break 'ccs_range_end;
                                }
                                return Err(ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS);
                            }
                            self.bitset_set_range(&mut cc.bs, *from, to);
                            if let Some(a) = asc_cc {
                                self.bitset_set_range(&mut a.bs, *from, to);
                            }
                        } else {
                            self.add_code_range(&mut cc.mbuf, *from, to)?;
                            if let Some(a) = asc_cc {
                                self.add_code_range0(&mut a.mbuf, *from, to, false)?;
                            }
                        }
                    } else {
                        if *from > to {
                            if self.syn.bv(ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC) {
                                break 'ccs_range_end;
                            }
                            return Err(ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS);
                        }
                        let sbto = if to < 0xff { to } else { 0xff };
                        self.bitset_set_range(&mut cc.bs, *from, sbto);
                        self.add_code_range(&mut cc.mbuf, *from, to)?;
                        if let Some(a) = asc_cc {
                            self.bitset_set_range(&mut a.bs, *from, sbto);
                            self.add_code_range0(&mut a.mbuf, *from, to, false)?;
                        }
                    }
                }
                *state = CcState::Complete;
            }
            CcState::Complete | CcState::Start => {
                *state = CcState::Value;
            }
        }
        *from_israw = to_israw;
        *from = to;
        *typ = intype;
        Ok(())
    }

    fn code_exist_check(&self, c: u32, from: usize, ignore_escaped: bool) -> bool {
        let mut p = from;
        let mut in_esc = false;
        while !self.pend(p) {
            if ignore_escaped && in_esc {
                in_esc = false;
            } else {
                let code = self.fetch_s(&mut p);
                if code == c {
                    return true;
                }
                if code == self.syn.esc {
                    in_esc = true;
                }
            }
        }
        false
    }

    /// Returns the class and, under /i, the class of the ASCII-only members.
    fn parse_char_class(&mut self, tok: &mut Token, src: &mut usize) -> R<(CClass, Option<CClass>)> {
        self.env.parse_depth += 1;
        if self.env.parse_depth > get_parse_depth_limit() {
            return Err(ONIGERR_PARSE_DEPTH_LIMIT_OVER);
        }
        let mut prev_cc: Option<CClass> = None;
        let mut asc_prev_cc: Option<CClass> = None;
        let mut r = self.fetch_token_in_cc(tok, src)?;
        let neg = if r == Tk::Char && tok.c == b'^' as u32 && !tok.escaped {
            r = self.fetch_token_in_cc(tok, src)?;
            true
        } else {
            false
        };

        if r == Tk::CcClose {
            if !self.code_exist_check(b']' as u32, *src, true) {
                return Err(ONIGERR_EMPTY_CHAR_CLASS);
            }
            self.cc_esc_warn("]");
            tok.typ = Tk::Char; /* allow []...] */
            r = Tk::Char;
        }

        let mut cc = CClass::default();
        let mut asc_cc = if is_ignorecase(self.env.option) { Some(CClass::default()) } else { None };

        let mut and_start = false;
        let mut state = CcState::Start;
        let mut p = *src;
        let mut vs: u32 = 0;
        let mut val_type = CcValType::Sb;
        let mut val_israw = false;
        let mut in_israw;
        let mut v: u32;
        let mut in_type: CcValType;

        // The targets of the gotos inside the loop of the C function.
        enum Go {
            Next,
            ValEntry,
            ValEntry2,
            NextClass,
            SbChar,
        }

        while r != Tk::CcClose {
            let mut fetched = false;
            let mut go: Go;
            v = 0;
            in_type = CcValType::Sb;
            in_israw = false;
            match r {
                Tk::Char => {
                    let len = if tok.c >= SINGLE_BYTE_SIZE { 2 } else { self.enc.code_to_mbclen(tok.c) };
                    if tok.c >= SINGLE_BYTE_SIZE || len > 1 {
                        in_type = CcValType::CodePoint;
                    } else if len < 0 {
                        return Err(len);
                    } else {
                        in_type = CcValType::Sb;
                    }
                    v = tok.c;
                    in_israw = false;
                    go = Go::ValEntry2;
                }
                Tk::RawByte => {
                    /* tok.base != 0 : octal or hexadec. */
                    if !self.enc.is_single_byte() && tok.base != 0 {
                        let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
                        let psave = p;
                        let base = tok.base;
                        buf[0] = tok.c as u8;
                        let mut i = 1;
                        while i < self.enc.max_len() {
                            let rr = self.fetch_token_in_cc(tok, &mut p)?;
                            if rr != Tk::RawByte || tok.base != base {
                                fetched = true;
                                break;
                            }
                            buf[i] = tok.c as u8;
                            i += 1;
                        }
                        if i < self.enc.min_len() {
                            return Err(ONIGERR_TOO_SHORT_MULTI_BYTE_STRING);
                        }
                        let len = self.enc.enclen(&buf, 0, i);
                        if i < len {
                            return Err(ONIGERR_TOO_SHORT_MULTI_BYTE_STRING);
                        } else if i > len {
                            /* fetch back */
                            p = psave;
                            for _ in 1..len {
                                let _ = self.fetch_token_in_cc(tok, &mut p);
                                /* no need to check the return value (already checked above) */
                            }
                            fetched = false;
                            i = len;
                        }
                        if i == 1 {
                            v = buf[0] as u32;
                            in_type = CcValType::Sb;
                        } else {
                            v = self.enc.mbc_to_code(&buf, 0, ONIGENC_CODE_TO_MBC_MAXLEN);
                            in_type = CcValType::CodePoint;
                        }
                    } else {
                        v = tok.c;
                        in_type = CcValType::Sb;
                    }
                    in_israw = true;
                    go = Go::ValEntry2;
                }
                Tk::CodePoint => {
                    v = tok.c;
                    in_israw = true;
                    go = Go::ValEntry;
                }
                Tk::PosixBracketOpen => {
                    if self.parse_posix_bracket(&mut cc, asc_cc.as_mut(), &mut p)? {
                        go = Go::NextClass;
                    } else {
                        /* is not POSIX bracket */
                        self.cc_esc_warn("[");
                        p = tok.backp;
                        v = tok.c;
                        in_israw = false;
                        go = Go::ValEntry;
                    }
                }
                Tk::CharType => {
                    let ar = is_ascii_range(self.env.option);
                    self.add_ctype_to_cc(&mut cc, tok.prop_ctype, tok.prop_not, ar)?;
                    if let Some(a) = asc_cc.as_mut() {
                        if tok.prop_ctype != CTYPE_WORD {
                            self.add_ctype_to_cc(a, tok.prop_ctype, tok.prop_not, ar)?;
                        }
                    }
                    go = Go::NextClass;
                }
                Tk::CharProperty => {
                    let ctype = self.fetch_char_property_to_ctype(&mut p)?;
                    self.add_ctype_to_cc(&mut cc, ctype, tok.prop_not, false)?;
                    if let Some(a) = asc_cc.as_mut() {
                        if ctype != CTYPE_ASCII {
                            self.add_ctype_to_cc(a, ctype, tok.prop_not, false)?;
                        }
                    }
                    go = Go::NextClass;
                }
                Tk::CcRange => {
                    if state == CcState::Value {
                        let rr = self.fetch_token_in_cc(tok, &mut p)?;
                        fetched = true;
                        if rr == Tk::CcClose {
                            /* allow [x-] */
                            v = b'-' as u32;
                            in_israw = false;
                            go = Go::ValEntry;
                        } else if rr == Tk::CcAnd {
                            self.cc_esc_warn("-");
                            v = b'-' as u32;
                            in_israw = false;
                            go = Go::ValEntry;
                        } else {
                            if val_type == CcValType::Class {
                                return Err(ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS);
                            }
                            state = CcState::Range;
                            go = Go::Next;
                        }
                    } else if state == CcState::Start {
                        /* [-xa] is allowed */
                        v = tok.c;
                        in_israw = false;
                        let rr = self.fetch_token_in_cc(tok, &mut p)?;
                        fetched = true;
                        /* [--x] or [a&&-x] is warned. */
                        if rr == Tk::CcRange || and_start {
                            self.cc_esc_warn("-");
                        }
                        go = Go::ValEntry;
                    } else if state == CcState::Range {
                        self.cc_esc_warn("-");
                        go = Go::SbChar; /* [!--x] is allowed */
                    } else {
                        /* CCS_COMPLETE */
                        let rr = self.fetch_token_in_cc(tok, &mut p)?;
                        fetched = true;
                        if rr == Tk::CcClose {
                            /* allow [a-b-] */
                            v = b'-' as u32;
                            in_israw = false;
                            go = Go::ValEntry;
                        } else if rr == Tk::CcAnd {
                            self.cc_esc_warn("-");
                            v = b'-' as u32;
                            in_israw = false;
                            go = Go::ValEntry;
                        } else if self.syn.bv(ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC) {
                            self.cc_esc_warn("-");
                            /* [0-9-a] is allowed as [0-9\-a] */
                            v = b'-' as u32;
                            in_israw = false;
                            go = Go::ValEntry;
                        } else {
                            return Err(ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS);
                        }
                    }
                }
                Tk::CcCcOpen => {
                    /* [ */
                    let (acc, aasc) = self.parse_char_class(tok, &mut p)?;
                    self.or_cclass(&mut cc, &acc)?;
                    if let (Some(aasc), Some(a)) = (aasc, asc_cc.as_mut()) {
                        self.or_cclass(a, &aasc)?;
                    }
                    go = Go::Next;
                }
                Tk::CcAnd => {
                    /* && */
                    if state == CcState::Value {
                        let vt = val_type;
                        self.next_state_val(
                            &mut cc,
                            &mut asc_cc,
                            &mut vs,
                            0,
                            &mut val_israw,
                            false,
                            vt,
                            &mut val_type,
                            &mut state,
                        )?;
                    }
                    /* initialize local variables */
                    and_start = true;
                    state = CcState::Start;

                    if let Some(pc) = prev_cc.as_mut() {
                        let cur = std::mem::take(&mut cc);
                        self.and_cclass(pc, &cur)?;
                        if let (Some(apc), Some(a)) = (asc_prev_cc.as_mut(), asc_cc.as_mut()) {
                            let cur = std::mem::take(a);
                            self.and_cclass(apc, &cur)?;
                        }
                    } else {
                        prev_cc = Some(std::mem::take(&mut cc));
                        if let Some(a) = asc_cc.as_mut() {
                            asc_prev_cc = Some(std::mem::take(a));
                        }
                    }
                    cc = CClass::default();
                    if let Some(a) = asc_cc.as_mut() {
                        *a = CClass::default();
                    }
                    go = Go::Next;
                }
                Tk::Eot => return Err(ONIGERR_PREMATURE_END_OF_CHAR_CLASS),
                _ => return Err(ONIGERR_PARSER_BUG),
            }

            loop {
                match go {
                    Go::SbChar => {
                        v = tok.c;
                        in_type = CcValType::Sb;
                        in_israw = false;
                        go = Go::ValEntry2;
                    }
                    Go::ValEntry => {
                        let len = self.enc.code_to_mbclen(v);
                        if len < 0 {
                            return Err(len);
                        }
                        in_type = if len == 1 { CcValType::Sb } else { CcValType::CodePoint };
                        go = Go::ValEntry2;
                    }
                    Go::ValEntry2 => {
                        self.next_state_val(
                            &mut cc,
                            &mut asc_cc,
                            &mut vs,
                            v,
                            &mut val_israw,
                            in_israw,
                            in_type,
                            &mut val_type,
                            &mut state,
                        )?;
                        break;
                    }
                    Go::NextClass => {
                        self.next_state_class(&mut cc, &mut asc_cc, &mut vs, &mut val_type, &mut state)?;
                        break;
                    }
                    Go::Next => break,
                }
            }

            if fetched {
                r = tok.typ;
            } else {
                r = self.fetch_token_in_cc(tok, &mut p)?;
            }
        }

        if state == CcState::Value {
            let vt = val_type;
            self.next_state_val(&mut cc, &mut asc_cc, &mut vs, 0, &mut val_israw, false, vt, &mut val_type, &mut state)?;
        }

        if let Some(mut pc) = prev_cc {
            self.and_cclass(&mut pc, &cc)?;
            cc = pc;
            if let (Some(mut apc), Some(a)) = (asc_prev_cc, asc_cc.as_ref()) {
                self.and_cclass(&mut apc, a)?;
                asc_cc = Some(apc);
            }
        }

        if neg {
            cc.set_not();
            if let Some(a) = asc_cc.as_mut() {
                a.set_not();
            }
        } else {
            cc.clear_not();
            if let Some(a) = asc_cc.as_mut() {
                a.clear_not();
            }
        }
        *src = p;
        self.env.parse_depth -= 1;
        Ok((cc, asc_cc))
    }

    // groups

    /// Returns (0: enclose, 1: group, 2: option only, node).
    fn parse_enclose(&mut self, tok: &mut Token, term: Tk, src: &mut usize) -> R<(i32, NodeId)> {
        let enc = self.enc;
        let mut p = *src;
        let mut prev = p;

        if self.pend(p) {
            return Err(ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS);
        }

        let mut option = self.env.option;
        let np: NodeId;
        if self.peek_is(p, b'?') && self.syn.op2(ONIG_SYN_OP2_QMARK_GROUP_EFFECT) {
            self.inc(&mut p, &mut prev);
            if self.pend(p) {
                return Err(ONIGERR_END_PATTERN_IN_GROUP);
            }
            let mut c = self.fetch(&mut p, &mut prev);
            match c {
                0x3a /* : */ => {
                    /* (?:...) grouping only */
                    return self.parse_group(tok, term, &mut p, src);
                }
                0x3d /* = */ => np = self.ast.new_anchor(ANCHOR_PREC_READ),
                0x21 /* ! */ => np = self.ast.new_anchor(ANCHOR_PREC_READ_NOT),
                0x3e /* > */ => np = self.ast.new_enclose(ENCLOSE_STOP_BACKTRACK),
                0x7e /* ~ */ => {
                    if self.syn.op2(ONIG_SYN_OP2_QMARK_TILDE_ABSENT) {
                        np = self.ast.new_enclose(ENCLOSE_ABSENT);
                    } else {
                        return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                    }
                }
                0x27 /* ' */ => {
                    if self.syn.op2(ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP) {
                        np = self.parse_named_group(c, &mut p)?;
                    } else {
                        return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                    }
                }
                0x3c /* < */ => {
                    /* look behind (?<=...), (?<!...) */
                    if self.pend(p) {
                        return Err(ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS);
                    }
                    c = self.fetch(&mut p, &mut prev);
                    if c == b'=' as u32 {
                        np = self.ast.new_anchor(ANCHOR_LOOK_BEHIND);
                    } else if c == b'!' as u32 {
                        np = self.ast.new_anchor(ANCHOR_LOOK_BEHIND_NOT);
                    } else if self.syn.op2(ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP) {
                        /* (?<name>...) */
                        p = prev;
                        np = self.parse_named_group(b'<' as u32, &mut p)?;
                    } else {
                        return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                    }
                }
                0x28 /* ( */ => {
                    /* conditional expression: (?(cond)yes), (?(cond)yes|no) */
                    if !self.pend(p) && self.syn.op2(ONIG_SYN_OP2_QMARK_LPAREN_CONDITION) {
                        let num;
                        let mut by_name = false;
                        c = self.fetch(&mut p, &mut prev);
                        if enc.is_code_digit(c) {
                            /* (n) */
                            p = prev;
                            let (n, _) = self.fetch_name(b'(' as u32, &mut p, true)?;
                            num = n;
                        } else if c == b'<' as u32 || c == b'\'' as u32 {
                            /* (<name>), ('name') */
                            by_name = true;
                            self.fetch_named_backref_token(c, tok, &mut p)?;
                            if !self.peek_is(p, b')') {
                                return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                            }
                            self.inc(&mut p, &mut prev);
                            /* FIXME (regparse.c):
                             * Use left most named group for now. This is the same as Perl.
                             * However this should use the same strategy as normal back-
                             * references on Ruby syntax; search right to left. */
                            num = tok.backref_refs[0];
                        } else {
                            return Err(ONIGERR_INVALID_CONDITION_PATTERN);
                        }
                        np = self.ast.new_enclose(ENCLOSE_CONDITION);
                        let e = self.ast.enclose_mut(np);
                        e.regnum = num;
                        if by_name {
                            e.state |= NST_NAME_REF;
                        }
                    } else {
                        return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                    }
                }
                0x2d | 0x69 | 0x6d | 0x73 | 0x78 | 0x61 | 0x64 | 0x6c | 0x75 => {
                    /* - i m s x a d l u */
                    let mut neg = false;
                    loop {
                        match c {
                            0x3a | 0x29 => {}
                            0x2d => neg = true,
                            0x78 => onoff(&mut option, ONIG_OPTION_EXTEND, neg),
                            0x69 => onoff(&mut option, ONIG_OPTION_IGNORECASE, neg),
                            0x73 => {
                                if self.syn.op2(ONIG_SYN_OP2_OPTION_PERL) {
                                    onoff(&mut option, ONIG_OPTION_MULTILINE, neg);
                                } else {
                                    return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                                }
                            }
                            0x6d => {
                                if self.syn.op2(ONIG_SYN_OP2_OPTION_PERL) {
                                    onoff(&mut option, ONIG_OPTION_SINGLELINE, !neg);
                                } else if self.syn.op2(ONIG_SYN_OP2_OPTION_RUBY) {
                                    onoff(&mut option, ONIG_OPTION_MULTILINE, neg);
                                } else {
                                    return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                                }
                            }
                            0x61 => {
                                /* limits \d, \s, \w and POSIX brackets to ASCII range */
                                if (self.syn.op2(ONIG_SYN_OP2_OPTION_PERL) || self.syn.op2(ONIG_SYN_OP2_OPTION_RUBY))
                                    && !neg
                                {
                                    onoff(&mut option, ONIG_OPTION_ASCII_RANGE, false);
                                    onoff(&mut option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, true);
                                    onoff(&mut option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, true);
                                } else {
                                    return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                                }
                            }
                            0x75 => {
                                if (self.syn.op2(ONIG_SYN_OP2_OPTION_PERL) || self.syn.op2(ONIG_SYN_OP2_OPTION_RUBY))
                                    && !neg
                                {
                                    onoff(&mut option, ONIG_OPTION_ASCII_RANGE, true);
                                    onoff(&mut option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, true);
                                    onoff(&mut option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, true);
                                } else {
                                    return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                                }
                            }
                            0x64 => {
                                if self.syn.op2(ONIG_SYN_OP2_OPTION_PERL) && !neg {
                                    onoff(&mut option, ONIG_OPTION_ASCII_RANGE, true);
                                } else if self.syn.op2(ONIG_SYN_OP2_OPTION_RUBY) && !neg {
                                    onoff(&mut option, ONIG_OPTION_ASCII_RANGE, false);
                                    onoff(&mut option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, false);
                                    onoff(&mut option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, false);
                                } else {
                                    return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                                }
                            }
                            0x6c => {
                                if self.syn.op2(ONIG_SYN_OP2_OPTION_PERL) && !neg {
                                    onoff(&mut option, ONIG_OPTION_ASCII_RANGE, true);
                                } else {
                                    return Err(ONIGERR_UNDEFINED_GROUP_OPTION);
                                }
                            }
                            _ => return Err(ONIGERR_UNDEFINED_GROUP_OPTION),
                        }

                        if c == b')' as u32 {
                            let np = self.ast.new_option(option);
                            *src = p;
                            return Ok((2, np)); /* option only */
                        } else if c == b':' as u32 {
                            let prev_opt = self.env.option;
                            self.env.option = option;
                            let r = self.fetch_token(tok, &mut p);
                            let target = match r {
                                Ok(_) => self.parse_subexp(tok, term, &mut p),
                                Err(e) => Err(e),
                            };
                            self.env.option = prev_opt;
                            let (_, target) = target?;
                            let np = self.ast.new_option(option);
                            self.ast.enclose_mut(np).target = Some(target);
                            *src = p;
                            return Ok((0, np));
                        }

                        if self.pend(p) {
                            return Err(ONIGERR_END_PATTERN_IN_GROUP);
                        }
                        c = self.fetch(&mut p, &mut prev);
                    }
                }
                _ => return Err(ONIGERR_UNDEFINED_GROUP_OPTION),
            }
        } else {
            if (self.env.option & ONIG_OPTION_DONT_CAPTURE_GROUP) != 0 {
                return self.parse_group(tok, term, &mut p, src);
            }
            np = self.ast.new_enclose(ENCLOSE_MEMORY);
            self.ast.enclose_mut(np).option = self.env.option;
            let num = self.scan_env_add_mem_entry()?;
            self.ast.enclose_mut(np).regnum = num;
        }

        self.fetch_token(tok, &mut p)?;
        let (_, target) = self.parse_subexp(tok, term, &mut p)?;

        if let Node::Anchor(a) = &mut self.ast.nodes[np] {
            a.target = Some(target);
        } else {
            self.ast.enclose_mut(np).target = Some(target);
            let (typ, regnum) = {
                let e = self.ast.enclose(np);
                (e.typ, e.regnum)
            };
            if typ == ENCLOSE_MEMORY {
                /* Don't move this to previous of parse_subexp() */
                self.scan_env_set_mem_node(regnum, np)?;
            } else if typ == ENCLOSE_CONDITION && self.ast.ntype(target) != NT_ALT {
                /* convert (?(cond)yes) to (?(cond)yes|empty) */
                let work1 = self.ast.new_empty();
                let work2 = self.ast.new_alt(work1, None);
                let work1 = self.ast.new_alt(target, Some(work2));
                self.ast.enclose_mut(np).target = Some(work1);
            }
        }

        *src = p;
        Ok((0, np))
    }

    fn parse_group(&mut self, tok: &mut Token, term: Tk, p: &mut usize, src: &mut usize) -> R<(i32, NodeId)> {
        self.fetch_token(tok, p)?;
        let (_, np) = self.parse_subexp(tok, term, p)?;
        *src = *p;
        Ok((1, np)) /* group */
    }

    fn parse_named_group(&mut self, c: u32, p: &mut usize) -> R<NodeId> {
        let name = *p;
        let (_, name_end) = self.fetch_name(c, p, false)?;
        let num = self.scan_env_add_mem_entry()?;
        self.name_add((name, name_end), num)?;
        let np = self.ast.new_enclose(ENCLOSE_MEMORY);
        let e = self.ast.enclose_mut(np);
        e.state |= NST_NAMED_GROUP;
        e.option = self.env.option;
        e.regnum = num;
        self.env.num_named += 1;
        Ok(np)
    }

    /// Returns 0: attach the quantifier, 1: drop it ({1,1}), 2: the target
    /// string was split and the quantifier applies to its last character.
    fn set_quantifier(&mut self, qnode: NodeId, target: NodeId, group: bool) -> i32 {
        {
            let qn = self.ast.qtfr(qnode);
            if qn.lower == 1 && qn.upper == 1 {
                return 1;
            }
        }

        match self.ast.ntype(target) {
            NT_STR => {
                if !group && self.str_node_can_be_split(target) {
                    if let Some(n) = self.str_node_split_last_char(target) {
                        self.ast.qtfr_mut(qnode).target = Some(n);
                        return 2;
                    }
                }
            }
            NT_QTFR => {
                /* check redundant double repeat. */
                /* verbose warn (?:.?)? etc... but not warn (.?)? etc... */
                let nestq_num = popular_quantifier_num(self.ast.qtfr(qnode));
                let targetq_num = popular_quantifier_num(self.ast.qtfr(target));

                if let (Some(nestq), Some(targetq)) = (nestq_num, targetq_num) {
                    if self.syn.bv(ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT) {
                        let t = REDUCE_TYPE_TABLE[targetq][nestq];
                        match t {
                            Asis => {}
                            Del => {
                                if self.warner.enabled() {
                                    self.syntax_warn(&format!(
                                        "regular expression has redundant nested repeat operator '{}'",
                                        POPULAR_Q_STR[targetq]
                                    ));
                                }
                            }
                            _ => {
                                if self.warner.enabled() {
                                    self.syntax_warn(&format!(
                                        "nested repeat operator '{}' and '{}' was replaced with '{}' in regular expression",
                                        POPULAR_Q_STR[targetq],
                                        POPULAR_Q_STR[nestq],
                                        REDUCE_Q_STR[reduce_type_index(t)]
                                    ));
                                }
                            }
                        }
                    }
                }

                if let Some(targetq) = targetq_num {
                    if nestq_num.is_some() {
                        reduce_nested_quantifier(&mut self.ast, qnode, target);
                        return 0;
                    } else if targetq == 1 || targetq == 2 {
                        /* * or + */
                        /* (?:a*){n,m}, (?:a+){n,m} => (?:a*){n,n}, (?:a+){n,n} */
                        let qn = self.ast.qtfr_mut(qnode);
                        if !is_repeat_infinite(qn.upper) && qn.upper > 1 && qn.greedy {
                            qn.upper = if qn.lower == 0 { 1 } else { qn.lower };
                        }
                    }
                }
            }
            _ => {}
        }

        self.ast.qtfr_mut(qnode).target = Some(target);
        0
    }

    // case folding of classes

    fn is_singlebyte_range(&self, code: CodePoint) -> bool {
        /* single byte encoding */
        if self.enc.max_len() == 1 {
            return true;
        }
        /* wide char encoding */
        if self.enc.min_len() > 1 {
            return false;
        }
        code < 0x80
    }

    /// `cclass_case_fold`: `np` holds `cc`. Returns the new top node.
    fn cclass_case_fold(&mut self, np: NodeId, cc: CClass, asc_cc: AscCc) -> R<NodeId> {
        let enc = self.enc;
        let mut cc = cc;
        let mut alts: Vec<NodeId> = Vec::new();
        let mut err: Option<i32> = None;
        let flag = self.env.case_fold_flag;
        let r = {
            let this = &mut *self;
            enc.apply_all_case_fold(flag, &mut |from, to| {
                let r = this.i_apply_case_fold(from, to, &mut cc, asc_cc, &mut alts);
                match r {
                    Ok(()) => 0,
                    Err(e) => {
                        err = Some(e);
                        e
                    }
                }
            })
        };
        if let Some(e) = err {
            return Err(e);
        }
        if r != 0 {
            return Err(r);
        }
        *self.ast.cclass_mut(np) = cc;
        if alts.is_empty() {
            return Ok(np);
        }
        let mut tail = None;
        for &s in alts.iter().rev() {
            tail = Some(self.ast.new_alt(s, tail));
        }
        Ok(self.ast.new_alt(np, tail))
    }

    fn i_apply_case_fold(
        &mut self,
        from: CodePoint,
        to: &[CodePoint],
        cc: &mut CClass,
        asc_cc: AscCc,
        alts: &mut Vec<NodeId>,
    ) -> R<()> {
        let enc = self.enc;
        let add_flag = match asc_cc {
            AscCc::None => false,
            _ if (from < 0x80) == (to[0] < 0x80) => true,
            AscCc::Same => {
                let f = is_code_in_cc(enc, from, cc);
                if cc.is_not() { !f } else { f }
            }
            AscCc::Other(a) => {
                let f = is_code_in_cc(enc, from, a);
                if a.is_not() { !f } else { f }
            }
        };

        if to.len() == 1 {
            let is_in = is_code_in_cc(enc, from, cc);
            if ((is_in && !cc.is_not()) || (!is_in && cc.is_not())) && add_flag {
                if self.is_singlebyte_range(to[0]) {
                    cc.bs.set(to[0]);
                } else {
                    self.add_code_range0(&mut cc.mbuf, to[0], to[0], false)?;
                }
            }
        } else if is_code_in_cc(enc, from, cc) && !cc.is_not() {
            let mut s = Bytes::default();
            for &t in to {
                let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
                s.extend_from_slice(code_to_mbc(enc, t, &mut buf)?);
            }
            let snode = self.ast.add(Node::Str(StrNode { s, flag: NSTR_AMBIG }));
            /* char-class expanded multi-char only
               compare with string folded at match time. */
            alts.push(snode);
        }
        Ok(())
    }

    // \R and \X

    fn node_linebreak(&mut self) -> R<NodeId> {
        /* same as (?>\x0D\x0A|[\x0A-\x0D\x{85}\x{2028}\x{2029}]) */
        let enc = self.enc;
        let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
        let mut s = Vec::new();
        for code in [0x0D, 0x0A] {
            s.extend_from_slice(code_to_mbc(enc, code, &mut buf)?);
        }
        let left = self.ast.new_str_raw(&s);

        let mut cc = CClass::default();
        if enc.min_len() > 1 {
            self.add_code_range(&mut cc.mbuf, 0x0A, 0x0D)?;
        } else {
            self.bitset_set_range(&mut cc.bs, 0x0A, 0x0D);
        }
        if enc.is_unicode() {
            /* UTF-8, UTF-16BE/LE, UTF-32BE/LE */
            self.add_code_range(&mut cc.mbuf, 0x85, 0x85)?;
            self.add_code_range(&mut cc.mbuf, 0x2028, 0x2029)?;
        }
        let right = self.ast.add(Node::CClass(cc));

        let target1 = self.ast.new_alt(right, None);
        let target2 = self.ast.new_alt(left, Some(target1));
        let np = self.ast.new_enclose(ENCLOSE_STOP_BACKTRACK);
        self.ast.enclose_mut(np).target = Some(target2);
        Ok(np)
    }

    fn propname2ctype(&mut self, propname: &str) -> R<u32> {
        let ctype = self.enc.property_name_to_ctype_ascii(propname.as_bytes());
        u32::try_from(ctype).map_err(|_| {
            self.env.error = Some(propname.as_bytes().to_vec());
            ctype
        })
    }

    fn add_property_to_cc(&mut self, cc: &mut CClass, propname: &str, not: bool) -> R<()> {
        let ctype = self.propname2ctype(propname)?;
        self.add_ctype_to_cc(cc, ctype, not, false)
    }

    fn create_property_node(&mut self, propname: &str) -> R<NodeId> {
        let mut cc = CClass::default();
        self.add_property_to_cc(&mut cc, propname, false)?;
        Ok(self.ast.add(Node::CClass(cc)))
    }

    fn quantify_node(&mut self, np: NodeId, lower: i32, upper: i32) -> NodeId {
        let q = self.ast.new_quantifier(lower, upper, false);
        self.ast.qtfr_mut(q).target = Some(np);
        q
    }

    fn quantify_property_node(&mut self, propname: &str, repetitions: u8) -> R<NodeId> {
        let np = self.create_property_node(propname)?;
        let (lower, upper) = match repetitions {
            b'?' => (0, 1),
            b'+' => (1, REPEAT_INFINITE),
            b'*' => (0, REPEAT_INFINITE),
            b'2' => (2, 2),
            _ => return Err(ONIGERR_PARSER_BUG),
        };
        Ok(self.quantify_node(np, lower, upper))
    }

    fn create_list(&mut self, nodes: &[NodeId]) -> NodeId {
        let mut tmp = None;
        for &n in nodes.iter().rev() {
            tmp = Some(self.ast.new_list(n, tmp));
        }
        tmp.expect("empty list")
    }

    fn create_alt(&mut self, nodes: &[NodeId]) -> NodeId {
        let mut tmp = None;
        for &n in nodes.iter().rev() {
            tmp = Some(self.ast.new_alt(n, tmp));
        }
        tmp.expect("empty alternation")
    }

    fn node_extended_grapheme_cluster(&mut self) -> R<NodeId> {
        let enc = self.enc;
        let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
        let mut alts: Vec<NodeId> = Vec::new();

        /* CRLF, common for both Unicode and non-Unicode */
        let mut s = Vec::new();
        for code in [0x0D, 0x0A] {
            s.extend_from_slice(code_to_mbc(enc, code, &mut buf)?);
        }
        alts.push(self.ast.new_str_raw(&s));

        if enc.is_unicode() {
            /* UTF-8, UTF-16BE/LE, UTF-32BE/LE */
            self.propname2ctype("Grapheme_Cluster_Break=Extend")?;
            /* Unicode 11.0.0
             *   CRLF     (already done)
             * | [Control CR LF]
             * | precore* core postcore*
             * | .      (to catch invalid stuff, because this seems to be spec for String#grapheme_clusters) */

            /* [Control CR LF]    (CR and LF are not in the spec, but this is a conformed fix) */
            let mut cc = CClass::default();
            self.add_property_to_cc(&mut cc, "Grapheme_Cluster_Break=Control", false)?;
            if enc.min_len() > 1 {
                /* UTF-16/UTF-32 */
                self.add_code_range(&mut cc.mbuf, 0x000A, 0x000A)?; /* CR */
                self.add_code_range(&mut cc.mbuf, 0x000D, 0x000D)?; /* LF */
            } else {
                cc.bs.set(0x0a);
                cc.bs.set(0x0d);
            }
            alts.push(self.ast.add(Node::CClass(cc)));

            /* precore* core postcore* */
            /* precore*; precore := Prepend */
            let precore = self.quantify_property_node("Grapheme_Cluster_Break=Prepend", b'*')?;

            /* core := hangul-syllable | ri-sequence | xpicto-sequence | conjunctCluster | [^Control CR LF] */
            let mut core_alts: Vec<NodeId> = Vec::new();
            {
                /* hangul-syllable := L* (V+ | LV V* | LVT) T* | L+ | T+ */
                /* L* (V+ | LV V* | LVT) T* */
                let h0 = self.quantify_property_node("Grapheme_Cluster_Break=L", b'*')?;
                let a0 = self.quantify_property_node("Grapheme_Cluster_Break=V", b'+')?;
                let l0 = self.create_property_node("Grapheme_Cluster_Break=LV")?;
                let l1 = self.quantify_property_node("Grapheme_Cluster_Break=V", b'*')?;
                let a1 = self.create_list(&[l0, l1]);
                let a2 = self.create_property_node("Grapheme_Cluster_Break=LVT")?;
                let h1 = self.create_alt(&[a0, a1, a2]);
                let h2 = self.quantify_property_node("Grapheme_Cluster_Break=T", b'*')?;
                core_alts.push(self.create_list(&[h0, h1, h2]));
            }
            core_alts.push(self.quantify_property_node("Grapheme_Cluster_Break=L", b'+')?);
            core_alts.push(self.quantify_property_node("Grapheme_Cluster_Break=T", b'+')?);
            /* end of hangul-syllable */

            /* ri-sequence := RI RI */
            core_alts.push(self.quantify_property_node("Regional_Indicator", b'2')?);

            /* xpicto-sequence := \p{Extended_Pictographic} (Extend* ZWJ \p{Extended_Pictographic})* */
            {
                let xp0 = self.create_property_node("Extended_Pictographic")?;
                let ex0 = self.quantify_property_node("Grapheme_Cluster_Break=Extend", b'*')?;
                /* ZWJ (ZERO WIDTH JOINER) */
                let ex1 = self.ast.new_str_raw(code_to_mbc(enc, 0x200D, &mut buf)?);
                let ex2 = self.create_property_node("Extended_Pictographic")?;
                let xp1 = self.create_list(&[ex0, ex1, ex2]);
                let xp1 = self.quantify_node(xp1, 0, REPEAT_INFINITE);
                core_alts.push(self.create_list(&[xp0, xp1]));
            }

            /* conjunctCluster := \p{InCB=Consonant} ([\p{InCB=Extend} \p{InCB=Linker}]* \p{InCB=Linker} [\p{InCB=Extend} \p{InCB=Linker}]* \p{InCB=Consonant})+ */
            {
                let cc0 = self.create_property_node("InCB=Consonant")?;
                let mut inner = Vec::new();
                for which in 0..4 {
                    match which {
                        0 | 2 => {
                            let mut c = CClass::default();
                            self.add_property_to_cc(&mut c, "InCB=Extend", false)?;
                            self.add_property_to_cc(&mut c, "InCB=Linker", false)?;
                            let n = self.ast.add(Node::CClass(c));
                            inner.push(self.quantify_node(n, 0, REPEAT_INFINITE));
                        }
                        1 => inner.push(self.create_property_node("InCB=Linker")?),
                        _ => inner.push(self.create_property_node("InCB=Consonant")?),
                    }
                }
                let cc1 = self.create_list(&inner);
                let cc1 = self.quantify_node(cc1, 1, REPEAT_INFINITE);
                core_alts.push(self.create_list(&[cc0, cc1]));
            }

            /* [^Control CR LF] */
            {
                let mut cc = CClass::default();
                if enc.min_len() > 1 {
                    /* UTF-16/UTF-32 */
                    /* TODO (regparse.c): fix false warning */
                    let dup_not_warned = self.env.warnings_flag | !ONIG_SYN_WARN_CC_DUP;
                    self.env.warnings_flag |= ONIG_SYN_WARN_CC_DUP;

                    /* Start with a positive buffer and invert at the end.
                     * Otherwise, adding single-character ranges work the wrong way. */
                    self.add_property_to_cc(&mut cc, "Grapheme_Cluster_Break=Control", false)?;
                    self.add_code_range(&mut cc.mbuf, 0x000A, 0x000A)?; /* CR */
                    self.add_code_range(&mut cc.mbuf, 0x000D, 0x000D)?; /* LF */
                    let inverted = self.not_code_range_buf(cc.mbuf.as_ref())?;
                    cc.mbuf = inverted;

                    self.env.warnings_flag &= dup_not_warned;
                } else {
                    self.add_property_to_cc(&mut cc, "Grapheme_Cluster_Break=Control", true)?;
                    cc.bs.clear_bit(0x0a);
                    cc.bs.clear_bit(0x0d);
                }
                core_alts.push(self.ast.add(Node::CClass(cc)));
            }
            let core = self.create_alt(&core_alts);

            /* postcore*; postcore = [Extend ZWJ SpacingMark] */
            let mut cc = CClass::default();
            self.add_property_to_cc(&mut cc, "Grapheme_Cluster_Break=Extend", false)?;
            self.add_property_to_cc(&mut cc, "Grapheme_Cluster_Break=SpacingMark", false)?;
            self.add_code_range(&mut cc.mbuf, 0x200D, 0x200D)?;
            let postcore = self.ast.add(Node::CClass(cc));
            let postcore = self.quantify_node(postcore, 0, REPEAT_INFINITE);

            alts.push(self.create_list(&[precore, core, postcore]));
        }

        /* PerlSyntax: (?s:.), RubySyntax: (?m:.), common for both Unicode and non-Unicode */
        /* Not in Unicode spec (UAX #29), but added to catch invalid stuff,
         * because this is Ruby spec for String#grapheme_clusters. */
        let np1 = self.ast.new_anychar();
        let mut option = self.env.option;
        onoff(&mut option, ONIG_OPTION_MULTILINE, false);
        let tmp = self.ast.new_option(option);
        self.ast.enclose_mut(tmp).target = Some(np1);
        alts.push(tmp);

        let top_alt = self.create_alt(&alts);

        /* (?>): For efficiency, because there is no text piece
         *       that is not in a grapheme cluster, and there is only one way
         *       to split a string into grapheme clusters. */
        let np1 = self.ast.new_enclose(ENCLOSE_STOP_BACKTRACK);
        self.ast.enclose_mut(np1).target = Some(top_alt);

        if enc.is_unicode() {
            /* Don't ignore case. */
            let mut option = self.env.option;
            onoff(&mut option, ONIG_OPTION_IGNORECASE, true);
            let np = self.ast.new_option(option);
            self.ast.enclose_mut(np).target = Some(np1);
            Ok(np)
        } else {
            Ok(np1)
        }
    }

    // expressions

    fn parse_exp(&mut self, tok: &mut Token, term: Tk, src: &mut usize) -> R<(Tk, NodeId)> {
        if tok.typ == term {
            return Ok((tok.typ, self.ast.new_empty()));
        }

        let mut parse_depth = self.env.parse_depth;
        let mut group = false;

        enum Next {
            ReEntry,
            Repeat(Tk),
        }

        let (np, next) = match tok.typ {
            Tk::Alt | Tk::Eot => return Ok((tok.typ, self.ast.new_empty())),
            Tk::SubexpOpen => {
                let (r, np) = self.parse_enclose(tok, Tk::SubexpClose, src)?;
                if r == 1 {
                    group = true;
                } else if r == 2 {
                    /* option only */
                    let prev = self.env.option;
                    self.env.option = self.ast.enclose(np).option;
                    let res = match self.fetch_token(tok, src) {
                        Ok(_) => self.parse_subexp(tok, term, src),
                        Err(e) => Err(e),
                    };
                    self.env.option = prev;
                    let (_, target) = res?;
                    self.ast.enclose_mut(np).target = Some(target);
                    return Ok((tok.typ, np));
                }
                (np, Next::ReEntry)
            }
            Tk::SubexpClose => {
                /* ONIG_SYN_ALLOW_UNMATCHED_CLOSE_SUBEXP is off */
                return Err(ONIGERR_UNMATCHED_CLOSE_PARENTHESIS);
            }
            Tk::Linebreak => (self.node_linebreak()?, Next::ReEntry),
            Tk::ExtendedGraphemeCluster => (self.node_extended_grapheme_cluster()?, Next::ReEntry),
            Tk::Keep => (self.ast.new_anchor(ANCHOR_KEEP), Next::ReEntry),
            Tk::String => {
                let np = self.ast.new_str(&self.pat[tok.backp..*src]);
                let r = self.string_loop(np, tok, src)?;
                (np, Next::Repeat(r))
            }
            Tk::RawByte => {
                let np = self.ast.new_str_raw(&[tok.c as u8]);
                let mut len = 1;
                let r = loop {
                    if len >= self.enc.min_len() {
                        let s = &self.ast.str(np).s;
                        if len == self.enc.enclen(s, 0, s.len()) {
                            let r = self.fetch_token(tok, src)?;
                            self.ast.str_mut(np).flag &= !NSTR_RAW;
                            break r;
                        }
                    }
                    let r = self.fetch_token(tok, src)?;
                    if r != Tk::RawByte {
                        return Err(ONIGERR_TOO_SHORT_MULTI_BYTE_STRING);
                    }
                    self.ast.str_mut(np).s.push(tok.c as u8);
                    len += 1;
                };
                (np, Next::Repeat(r))
            }
            Tk::CodePoint => {
                let np = self.ast.new_empty();
                self.node_str_cat_codepoint(np, tok.c)?;
                let r = self.string_loop(np, tok, src)?;
                (np, Next::Repeat(r))
            }
            Tk::CharType => match tok.prop_ctype {
                CTYPE_WORD => {
                    let ar = is_ascii_range(self.env.option);
                    let np = self.ast.add(Node::CType(CTypeNode {
                        ctype: tok.prop_ctype,
                        not: tok.prop_not,
                        ascii_range: ar,
                    }));
                    (np, Next::ReEntry)
                }
                CTYPE_SPACE | CTYPE_DIGIT | CTYPE_XDIGIT => {
                    let mut cc = CClass::default();
                    let ar = is_ascii_range(self.env.option);
                    self.add_ctype_to_cc(&mut cc, tok.prop_ctype, false, ar)?;
                    if tok.prop_not {
                        cc.set_not();
                    }
                    (self.ast.add(Node::CClass(cc)), Next::ReEntry)
                }
                _ => return Err(ONIGERR_PARSER_BUG),
            },
            Tk::CharProperty => {
                let t = tok.clone();
                (self.parse_char_property(&t, src)?, Next::ReEntry)
            }
            Tk::CcOpen => {
                let (cc, asc_cc) = self.parse_char_class(tok, src)?;
                if let Some(code) = is_onechar_cclass(&cc) {
                    let np = self.ast.new_empty();
                    self.node_str_cat_codepoint(np, code)?;
                    let r = self.string_loop(np, tok, src)?;
                    (np, Next::Repeat(r))
                } else {
                    let np = self.ast.add(Node::CClass(cc.clone()));
                    let np = if is_ignorecase(self.env.option) {
                        let asc = match &asc_cc {
                            Some(a) => AscCc::Other(a),
                            None => AscCc::None,
                        };
                        self.cclass_case_fold(np, cc, asc)?
                    } else {
                        np
                    };
                    (np, Next::ReEntry)
                }
            }
            Tk::AnyChar => (self.ast.new_anychar(), Next::ReEntry),
            Tk::Backref => {
                let refs = tok.backref_refs.clone();
                let np = self.node_new_backref(&refs, tok.backref_by_name, tok.backref_exist_level, tok.backref_level);
                (np, Next::ReEntry)
            }
            Tk::Call => {
                let mut gnum = tok.call_gnum;
                if gnum < 0 || tok.call_rel {
                    if gnum > 0 {
                        gnum -= 1;
                    }
                    gnum = gnum
                        .checked_add(self.env.num_mem + 1)
                        .filter(|&n| n > 0)
                        .ok_or(ONIGERR_INVALID_BACKREF)?;
                }
                let name = self.pat[tok.call_name.0..tok.call_name.1].to_vec();
                let np = self.ast.add(Node::Call(CallNode { state: 0, group_num: gnum, name, target: None }));
                self.env.num_call += 1;
                (np, Next::ReEntry)
            }
            Tk::Anchor => {
                let np = self.ast.new_anchor(tok.anchor_subtype);
                self.ast.anchor_mut(np).ascii_range = tok.anchor_ascii_range;
                (np, Next::ReEntry)
            }
            Tk::OpRepeat | Tk::Interval => {
                if self.syn.bv(ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS) {
                    if self.syn.bv(ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS) {
                        return Err(ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED);
                    }
                    (self.ast.new_empty(), Next::ReEntry)
                } else {
                    return Err(ONIGERR_PARSER_BUG);
                }
            }
            _ => return Err(ONIGERR_PARSER_BUG),
        };

        let mut root = np;
        let mut slot = Slot::Root;
        let mut r = match next {
            Next::ReEntry => self.fetch_token(tok, src)?,
            Next::Repeat(r) => r,
        };

        while r == Tk::OpRepeat || r == Tk::Interval {
            parse_depth += 1;
            if parse_depth > get_parse_depth_limit() {
                return Err(ONIGERR_PARSE_DEPTH_LIMIT_OVER);
            }

            let mut qn = self.ast.new_quantifier(tok.repeat_lower, tok.repeat_upper, r == Tk::Interval);
            self.ast.qtfr_mut(qn).greedy = tok.repeat_greedy;
            let target = match slot {
                Slot::Root => root,
                Slot::Car(l) => self.ast.car(l),
            };
            let ret = self.set_quantifier(qn, target, group);

            if tok.repeat_possessive {
                let en = self.ast.new_enclose(ENCLOSE_STOP_BACKTRACK);
                self.ast.enclose_mut(en).target = Some(qn);
                qn = en;
            }

            match ret {
                0 => match slot {
                    Slot::Root => root = qn,
                    Slot::Car(l) => self.ast.set_car(l, qn),
                },
                1 => {}
                _ => {
                    /* split case: /abc+/ */
                    let cur = match slot {
                        Slot::Root => root,
                        Slot::Car(l) => self.ast.car(l),
                    };
                    let list = self.ast.new_list(cur, None);
                    match slot {
                        Slot::Root => root = list,
                        Slot::Car(l) => self.ast.set_car(l, list),
                    }
                    let tmp = self.ast.new_list(qn, None);
                    self.ast.set_cdr(list, Some(tmp));
                    slot = Slot::Car(tmp);
                }
            }
            r = self.fetch_token(tok, src)?;
        }

        Ok((r, root))
    }

    fn string_loop(&mut self, np: NodeId, tok: &mut Token, src: &mut usize) -> R<Tk> {
        loop {
            let r = self.fetch_token(tok, src)?;
            if r == Tk::String {
                let pat = self.pat;
                self.ast.str_mut(np).s.extend_from_slice(&pat[tok.backp..*src]);
            } else if r == Tk::CodePoint {
                self.node_str_cat_codepoint(np, tok.c)?;
            } else {
                return Ok(r);
            }
        }
    }

    fn parse_branch(&mut self, tok: &mut Token, term: Tk, src: &mut usize) -> R<(Tk, NodeId)> {
        let (mut r, node) = self.parse_exp(tok, term, src)?;
        if r == Tk::Eot || r == term || r == Tk::Alt {
            return Ok((r, node));
        }
        let top = self.ast.new_list(node, None);
        let mut head = top;
        while r != Tk::Eot && r != term && r != Tk::Alt {
            let (rr, node) = self.parse_exp(tok, term, src)?;
            r = rr;
            if self.ast.ntype(node) == NT_LIST {
                self.ast.set_cdr(head, Some(node));
                let mut n = node;
                while let Some(next) = self.ast.cdr(n) {
                    n = next;
                }
                head = n;
            } else {
                let l = self.ast.new_list(node, None);
                self.ast.set_cdr(head, Some(l));
                head = l;
            }
        }
        Ok((r, top))
    }

    /// term: Tk::Eot or Tk::SubexpClose
    fn parse_subexp(&mut self, tok: &mut Token, term: Tk, src: &mut usize) -> R<(Tk, NodeId)> {
        self.env.parse_depth += 1;
        if self.env.parse_depth > get_parse_depth_limit() {
            return Err(ONIGERR_PARSE_DEPTH_LIMIT_OVER);
        }
        let (mut r, node) = self.parse_branch(tok, term, src)?;
        let top;
        if r == term {
            top = node;
        } else if r == Tk::Alt {
            let topnode = self.ast.new_alt(node, None);
            let mut head = topnode;
            while r == Tk::Alt {
                self.fetch_token(tok, src)?;
                let (rr, node) = self.parse_branch(tok, term, src)?;
                r = rr;
                let a = self.ast.new_alt(node, None);
                self.ast.set_cdr(head, Some(a));
                head = a;
            }
            if tok.typ != term {
                return Err(if term == Tk::SubexpClose {
                    ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS
                } else {
                    ONIGERR_PARSER_BUG
                });
            }
            top = topnode;
        } else {
            return Err(if term == Tk::SubexpClose {
                ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS
            } else {
                ONIGERR_PARSER_BUG
            });
        }
        self.env.parse_depth -= 1;
        Ok((r, top))
    }

    fn parse_regexp(&mut self) -> R<NodeId> {
        let mut tok = Token::new();
        let mut p = 0;
        self.fetch_token(&mut tok, &mut p)?;
        let (_, mut top) = self.parse_subexp(&mut tok, Tk::Eot, &mut p)?;

        if self.env.num_call > 0 {
            /* Capture the pattern itself. It is used for (?R), (?0) and \g<0>. */
            let np = self.ast.new_enclose(ENCLOSE_MEMORY);
            let e = self.ast.enclose_mut(np);
            e.option = self.env.option;
            e.regnum = 0;
            e.target = Some(top);
            self.scan_env_set_mem_node(0, np)?;
            top = np;
        }
        Ok(top)
    }
}

#[inline]
fn onoff(v: &mut u32, f: u32, negative: bool) {
    if negative {
        *v &= !f;
    } else {
        *v |= f;
    }
}

/// The bytes of `code` in `enc`, written to `buf`.
fn code_to_mbc(enc: Enc, code: CodePoint, buf: &mut [u8; ONIGENC_CODE_TO_MBC_MAXLEN]) -> R<&[u8]> {
    let n = enc.code_to_mbc(code, buf);
    match usize::try_from(n) {
        Ok(len) => Ok(&buf[..len]),
        Err(_) => Err(n),
    }
}

/// `is_onechar_cclass`
fn is_onechar_cclass(cc: &CClass) -> Option<CodePoint> {
    let mut c = None;
    if cc.is_not() {
        return None;
    }
    /* check bbuf */
    if let Some(m) = &cc.mbuf {
        if m.len() == 1 && m[0].0 == m[0].1 {
            /* only one char found in the bbuf, save the code point. */
            let code = m[0].0;
            /* skip if c is included in the bitset */
            if code >= SINGLE_BYTE_SIZE || !cc.bs.at(code) {
                c = Some(code);
            }
        } else {
            return None; /* the bbuf contains multiple chars */
        }
    }
    /* check bitset */
    for i in 0..BITSET_SIZE {
        let b1 = cc.bs.0[i];
        if b1 != 0 {
            if b1.is_power_of_two() && c.is_none() {
                c = Some((BITS_IN_ROOM * i) as u32 + b1.trailing_zeros());
            } else {
                return None; /* the character class contains multiple chars */
            }
        }
    }
    c
}
