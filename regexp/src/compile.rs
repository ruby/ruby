//! The compiler, ported from regcomp.c: the tree passes that run between
//! parsing and code generation (`setup_tree` and the subexpression call
//! checks), the bytecode emitter, and the optimizer that picks a search
//! strategy. Function names follow the C ones. Only the configuration Ruby
//! builds is kept (no combination explosion check, `USE_MATCH_CACHE` on,
//! `USE_OP_PUSH_OR_JUMP_EXACT` off, `IS_DYNAMIC_OPTION` always 0).

use crate::ast::*;
use crate::bytecode::*;
use crate::enc::*;
use crate::error::*;
use crate::names::NameTable;
use crate::parser::{
    BitStatus, ScanEnv, Warner, bit_status_at, bit_status_on_at, bit_status_on_at_simple, is_code_in_cc,
    parse_make_tree, reduce_nested_quantifier,
};
use crate::syntax::*;

type R<T> = Result<T, i32>;

/// `ONIG_INFINITE_DISTANCE`
pub const INF: usize = usize::MAX;

pub const ONIG_OPTIMIZE_NONE: i32 = 0;
pub const ONIG_OPTIMIZE_EXACT: i32 = 1;
pub const ONIG_OPTIMIZE_EXACT_BM: i32 = 2;
pub const ONIG_OPTIMIZE_EXACT_BM_NOT_REV: i32 = 3;
pub const ONIG_OPTIMIZE_EXACT_IC: i32 = 4;
pub const ONIG_OPTIMIZE_MAP: i32 = 5;
pub const ONIG_OPTIMIZE_EXACT_BM_IC: i32 = 6;
pub const ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC: i32 = 7;

pub const STACK_POP_LEVEL_FREE: i32 = 0;
pub const STACK_POP_LEVEL_MEM_START: i32 = 1;
pub const STACK_POP_LEVEL_ALL: i32 = 2;

pub const ONIG_CHAR_TABLE_SIZE: usize = 256;
const OPT_EXACT_MAXLEN: usize = 24;
const QUANTIFIER_EXPAND_LIMIT_SIZE: i64 = 50;
const EXPAND_STRING_MAX_LENGTH: usize = 100;
const THRESHOLD_CASE_FOLD_ALT_FOR_EXPANSION: usize = 8;
const MAX_NODE_OPT_INFO_REF_COUNT: i32 = 5;
const REPEAT_RANGE_ALLOC: usize = 4;

const IN_ALT: i32 = 1 << 0;
const IN_NOT: i32 = 1 << 1;
const IN_REPEAT: i32 = 1 << 2;
const IN_VAR_REPEAT: i32 = 1 << 3;
const IN_CALL: i32 = 1 << 4;
const IN_RECCALL: i32 = 1 << 5;
const IN_LOOK_BEHIND: i32 = 1 << 6;

const RECURSION_EXIST: i32 = 1;
const RECURSION_INFINITE: i32 = 2;
const FOUND_CALLED_NODE: i32 = 1;

const ALLOWED_TYPE_IN_LB: i32 = BIT_NT_LIST
    | BIT_NT_ALT
    | BIT_NT_STR
    | BIT_NT_CCLASS
    | BIT_NT_CTYPE
    | BIT_NT_CANY
    | BIT_NT_ANCHOR
    | BIT_NT_ENCLOSE
    | BIT_NT_QTFR
    | BIT_NT_CALL;
const ALLOWED_ENCLOSE_IN_LB: i32 = ENCLOSE_MEMORY | ENCLOSE_OPTION;
const ALLOWED_ENCLOSE_IN_LB_NOT: i32 = ENCLOSE_OPTION;
const ALLOWED_ANCHOR_IN_LB: i32 = ANCHOR_LOOK_BEHIND
    | ANCHOR_LOOK_BEHIND_NOT
    | ANCHOR_BEGIN_LINE
    | ANCHOR_END_LINE
    | ANCHOR_BEGIN_BUF
    | ANCHOR_BEGIN_POSITION
    | ANCHOR_KEEP
    | ANCHOR_WORD_BOUND
    | ANCHOR_NOT_WORD_BOUND
    | ANCHOR_WORD_BEGIN
    | ANCHOR_WORD_END;
const ALLOWED_ANCHOR_IN_LB_NOT: i32 = ALLOWED_ANCHOR_IN_LB;

#[inline]
fn is_node_type_simple(t: i32) -> bool {
    (ntype2bit(t) & (BIT_NT_STR | BIT_NT_CCLASS | BIT_NT_CTYPE | BIT_NT_CANY | BIT_NT_BREF)) != 0
}

#[inline]
fn is_expand_limit_ok(tlen: i64, n: i64) -> bool {
    n <= 0 || tlen <= QUANTIFIER_EXPAND_LIMIT_SIZE / n
}

#[inline]
pub fn distance_add(d1: usize, d2: usize) -> usize {
    d1.saturating_add(d2)
}

/// `d * m`, or `INF` when it does not fit or `m` is negative.
#[inline]
pub fn distance_multiply(d: usize, m: i32) -> usize {
    usize::try_from(m).map_or(INF, |m| d.saturating_mul(m))
}

/// Why `get_char_length_tree1` found no fixed character length.
enum CharLenError {
    /// The length varies.
    VarLen,
    /// Only the top-level alternatives differ in length.
    TopAltVarLen,
    Error(i32),
}

impl From<i32> for CharLenError {
    fn from(code: i32) -> Self {
        CharLenError::Error(code)
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RepeatRange {
    pub lower: i32,
    pub upper: i32,
}

/// A compiled pattern: the fields of `regex_t` the matcher reads.
#[derive(Clone, Debug)]
pub struct Regex {
    pub program: Vec<u8>,
    /// A bit per offset of `program`, set at the OP_PUSH of each loop that
    /// `exec::is_char_loop` accepts. Not part of `regex_t`.
    pub char_loops: Vec<u64>,
    pub num_mem: i32,
    pub num_repeat: i32,
    pub num_null_check: i32,
    pub num_call: i32,
    pub capture_history: u32,
    pub bt_mem_start: u32,
    pub bt_mem_end: u32,
    pub stack_pop_level: i32,
    pub repeat_range: Vec<RepeatRange>,
    pub repeat_range_alloc: usize,
    pub options: u32,
    pub enc: Enc,
    pub case_fold_flag: u32,
    pub names: NameTable,
    pub optimize: i32,
    pub threshold_len: i32,
    pub anchor: i32,
    pub anchor_dmin: usize,
    pub anchor_dmax: usize,
    pub sub_anchor: i32,
    pub exact: Bytes,
    pub map: [u8; ONIG_CHAR_TABLE_SIZE],
    pub dmin: usize,
    pub dmax: usize,
}

impl Regex {
    #[inline]
    pub fn is_char_loop(&self, at: usize) -> bool {
        self.char_loops.get(at / 64).is_some_and(|w| w >> (at % 64) & 1 != 0)
    }
}

#[derive(Debug)]
pub struct CompileError {
    pub code: i32,
    /// `einfo->par .. einfo->par_end`: the part of the pattern named in the message.
    pub par: Option<Vec<u8>>,
}

/// `onig_reg_init` followed by `onig_compile`, with the Ruby syntax.
pub fn compile(
    pattern: &[u8],
    option: u32,
    case_fold_flag: u32,
    enc: Enc,
    warner: &mut dyn Warner,
) -> Result<Regex, CompileError> {
    let both = ONIG_OPTION_DONT_CAPTURE_GROUP | ONIG_OPTION_CAPTURE_GROUP;
    if option & both == both {
        return Err(CompileError { code: ONIGERR_INVALID_COMBINATION_OF_OPTIONS, par: None });
    }
    let mut option = option;
    if option & ONIG_OPTION_NEGATE_SINGLELINE != 0 {
        option |= SYNTAX_RUBY.options;
        option &= !ONIG_OPTION_SINGLELINE;
    } else {
        option |= SYNTAX_RUBY.options;
    }

    let pr = parse_make_tree(pattern, option, case_fold_flag, enc, warner)
        .map_err(|(code, par)| CompileError { code, par })?;
    let mut c = Compiler {
        num_mem: pr.env.num_mem,
        ast: pr.ast,
        env: pr.env,
        names: pr.names,
        enc,
        options: option,
        case_fold_flag,
        num_repeat: 0,
        num_null_check: 0,
        num_call: 0,
        capture_history: 0,
        bt_mem_start: 0,
        bt_mem_end: 0,
        p: Vec::new(),
        repeat_range: Vec::new(),
        uslist: Vec::new(),
        opt: OptResult::default(),
        opt_pool: Vec::new(),
        loop_pushes: Vec::new(),
    };
    match c.run(pr.root) {
        Ok(()) => Ok(c.finish()),
        Err(code) => Err(CompileError { code, par: c.env.error.take() }),
    }
}

#[derive(Clone)]
struct OptResult {
    optimize: i32,
    threshold_len: i32,
    anchor: i32,
    anchor_dmin: usize,
    anchor_dmax: usize,
    sub_anchor: i32,
    exact: Bytes,
    map: [u8; ONIG_CHAR_TABLE_SIZE],
    dmin: usize,
    dmax: usize,
}

impl Default for OptResult {
    fn default() -> Self {
        OptResult {
            optimize: ONIG_OPTIMIZE_NONE,
            threshold_len: 0,
            anchor: 0,
            anchor_dmin: 0,
            anchor_dmax: 0,
            sub_anchor: 0,
            exact: Bytes::default(),
            map: [0; ONIG_CHAR_TABLE_SIZE],
            dmin: 0,
            dmax: 0,
        }
    }
}

struct Compiler {
    ast: Ast,
    env: ScanEnv,
    names: NameTable,
    enc: Enc,
    /// `reg->options`, changed while walking `(?imx)` groups.
    options: u32,
    case_fold_flag: u32,
    num_mem: i32,
    num_repeat: i32,
    num_null_check: i32,
    num_call: i32,
    capture_history: BitStatus,
    bt_mem_start: BitStatus,
    bt_mem_end: BitStatus,
    p: Vec<u8>,
    repeat_range: Vec<RepeatRange>,
    /// `UnsetAddrList`: operand offsets of `OP_CALL` and the called group.
    uslist: Vec<(usize, NodeId)>,
    opt: OptResult,
    /// The boxes `optimize_node_left` works in, reused instead of
    /// allocated per node. They stay boxed to keep its recursion's frames
    /// small.
    #[allow(clippy::vec_box)]
    opt_pool: Vec<Box<NodeOptInfo>>,
    /// Where the OP_PUSH of each greedy loop is, for `Regex::char_loops`.
    loop_pushes: Vec<usize>,
}

impl Compiler {
    fn take_opt(&mut self) -> Box<NodeOptInfo> {
        match self.opt_pool.pop() {
            Some(mut opt) => {
                opt.clear();
                opt
            }
            None => Box::new(NodeOptInfo::new()),
        }
    }

    fn run(&mut self, root: NodeId) -> R<()> {
        let mut root = root;
        if self.env.num_named > 0
            && SYNTAX_RUBY.bv(ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP)
            && self.options & ONIG_OPTION_CAPTURE_GROUP == 0
        {
            if self.env.num_named != self.env.num_mem {
                root = self.disable_noname_group_capture(root)?;
            } else {
                self.numbered_ref_check(root)?;
            }
        }

        if self.env.num_call > 0 {
            self.setup_subexp_call(root)?;
            self.subexp_recursive_check_trav(root)?;
            self.subexp_inf_recursive_check_trav(root)?;
            self.num_call = self.env.num_call;
        } else {
            self.num_call = 0;
        }

        self.setup_tree(root, 0)?;

        self.capture_history = self.env.capture_history;
        self.bt_mem_start = self.env.bt_mem_start | self.capture_history;
        if is_find_condition(self.options) {
            self.bt_mem_end = !0;
        } else {
            self.bt_mem_end = self.env.bt_mem_end | self.capture_history;
        }

        self.opt = OptResult::default();
        self.set_optimize_info_from_tree(root)?;

        // The program is allocated once, for the tree and OP_END.
        let len = usize::try_from(self.compile_length_tree(root)? + SIZE_OPCODE).map_err(|_| ONIGERR_TYPE_BUG)?;
        self.p.try_reserve_exact(len).map_err(|_| ONIGERR_MEMORY)?;
        self.compile_tree(root)?;
        self.add_opcode(OP_END)?;
        if self.env.num_call > 0 {
            self.unset_addr_list_fix()?;
        }
        Ok(())
    }

    fn finish(self) -> Regex {
        let stack_pop_level = if self.num_repeat != 0 || self.bt_mem_end != 0 {
            STACK_POP_LEVEL_ALL
        } else if self.bt_mem_start != 0 {
            STACK_POP_LEVEL_MEM_START
        } else {
            STACK_POP_LEVEL_FREE
        };
        let repeat_range_alloc = if self.repeat_range.is_empty() {
            0
        } else {
            self.repeat_range.len().div_ceil(REPEAT_RANGE_ALLOC) * REPEAT_RANGE_ALLOC
        };
        let mut program = self.p;
        program.shrink_to_fit();
        let mut char_loops = Vec::new();
        for &at in &self.loop_pushes {
            if crate::exec::is_char_loop(&program, at, is_find_condition(self.options)) {
                char_loops.resize(char_loops.len().max(at / 64 + 1), 0u64);
                char_loops[at / 64] |= 1 << (at % 64);
            }
        }
        Regex {
            program,
            char_loops,
            num_mem: self.num_mem,
            num_repeat: self.num_repeat,
            num_null_check: self.num_null_check,
            num_call: self.num_call,
            capture_history: self.capture_history,
            bt_mem_start: self.bt_mem_start,
            bt_mem_end: self.bt_mem_end,
            stack_pop_level,
            repeat_range: self.repeat_range,
            repeat_range_alloc,
            options: self.options,
            enc: self.enc,
            case_fold_flag: self.case_fold_flag,
            names: self.names,
            optimize: self.opt.optimize,
            threshold_len: self.opt.threshold_len,
            anchor: self.opt.anchor,
            anchor_dmin: self.opt.anchor_dmin,
            anchor_dmax: self.opt.anchor_dmax,
            sub_anchor: self.opt.sub_anchor,
            exact: self.opt.exact,
            map: self.opt.map,
            dmin: self.opt.dmin,
            dmax: self.opt.dmax,
        }
    }

    // ---- small accessors ----

    #[track_caller]
    fn target(&self, id: NodeId) -> R<NodeId> {
        self.ast.target(id).ok_or(ONIGERR_PARSER_BUG)
    }

    fn mem_node(&self, num: i32) -> R<NodeId> {
        self.env.mem_node(num).ok_or(ONIGERR_PARSER_BUG)
    }

    fn enclose_state(&self, id: NodeId) -> i32 {
        self.ast.enclose(id).state
    }

    fn set_enclose_status(&mut self, id: NodeId, f: i32) {
        self.ast.enclose_mut(id).state |= f;
    }

    fn clear_enclose_status(&mut self, id: NodeId, f: i32) {
        self.ast.enclose_mut(id).state &= !f;
    }

    fn set_error_string(&mut self, name: &[u8]) {
        self.env.error = Some(name.to_vec());
    }

    /// `onig_node_list_add`: appends a new cell holding `x` to the end of
    /// `list` and returns the new cell.
    fn list_add(&mut self, list: Option<NodeId>, x: NodeId) -> NodeId {
        let n = self.ast.new_list(x, None);
        if let Some(mut l) = list {
            while let Some(next) = self.ast.cdr(l) {
                l = next;
            }
            self.ast.set_cdr(l, Some(n));
        }
        n
    }

    /// The cars of a list or alternation, in order.
    fn cells(&self, mut node: NodeId) -> Cells {
        let mut v = Cells { inline: [0; 8], len: 0, more: Vec::new() };
        loop {
            v.push(node);
            match self.ast.cdr(node) {
                Some(n) => node = n,
                None => return v,
            }
        }
    }

    // ---- named groups (USE_NAMED_GROUP) ----

    fn noname_disable_map(&mut self, node: NodeId, map: &mut [i32], counter: &mut i32) -> R<NodeId> {
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    let car = self.ast.car(cell);
                    let n = self.noname_disable_map(car, map, counter)?;
                    self.ast.set_car(cell, n);
                }
            }
            NT_QTFR => {
                let old = self.target(node)?;
                let new = self.noname_disable_map(old, map, counter)?;
                self.ast.qtfr_mut(node).target = Some(new);
                if new != old && self.ast.ntype(new) == NT_QTFR {
                    reduce_nested_quantifier(&mut self.ast, node, new);
                }
            }
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                if en.typ == ENCLOSE_MEMORY {
                    if en.state & NST_NAMED_GROUP != 0 {
                        *counter += 1;
                        let regnum = en.regnum as usize;
                        map[regnum] = *counter;
                        self.ast.enclose_mut(node).regnum = *counter;
                    } else if en.regnum != 0 {
                        let t = en.target.ok_or(ONIGERR_PARSER_BUG)?;
                        self.ast.nodes[node] = Node::Freed;
                        return self.noname_disable_map(t, map, counter);
                    }
                }
                let t = self.target(node)?;
                let n = self.noname_disable_map(t, map, counter)?;
                self.ast.enclose_mut(node).target = Some(n);
            }
            NT_ANCHOR => {
                if let Some(t) = self.ast.anchor(node).target {
                    let n = self.noname_disable_map(t, map, counter)?;
                    self.ast.anchor_mut(node).target = Some(n);
                }
            }
            _ => {}
        }
        Ok(node)
    }

    fn renumber_node_backref(&mut self, node: NodeId, map: &[i32], num_mem: i32) -> R<()> {
        let bn = self.ast.bref(node);
        if bn.state & NST_NAME_REF == 0 {
            return Err(ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED);
        }
        let mut backs = Vec::with_capacity(bn.back.len());
        for &b in &bn.back {
            if b > num_mem {
                return Err(ONIGERR_INVALID_BACKREF);
            }
            let n = map[b as usize];
            if n > 0 {
                backs.push(n);
            }
        }
        self.ast.bref_mut(node).back = backs;
        Ok(())
    }

    fn renumber_by_map(&mut self, node: NodeId, map: &[i32], num_mem: i32) -> R<()> {
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    let car = self.ast.car(cell);
                    self.renumber_by_map(car, map, num_mem)?;
                }
            }
            NT_QTFR => {
                let t = self.target(node)?;
                self.renumber_by_map(t, map, num_mem)?;
            }
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                if en.typ == ENCLOSE_CONDITION {
                    if en.regnum > num_mem {
                        return Err(ONIGERR_INVALID_BACKREF);
                    }
                    let n = map[en.regnum as usize];
                    self.ast.enclose_mut(node).regnum = n;
                }
                let t = self.target(node)?;
                self.renumber_by_map(t, map, num_mem)?;
            }
            NT_BREF => self.renumber_node_backref(node, map, num_mem)?,
            NT_ANCHOR => {
                if let Some(t) = self.ast.anchor(node).target {
                    self.renumber_by_map(t, map, num_mem)?;
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn numbered_ref_check(&self, node: NodeId) -> R<()> {
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    self.numbered_ref_check(self.ast.car(cell))?;
                }
            }
            NT_QTFR | NT_ENCLOSE => self.numbered_ref_check(self.target(node)?)?,
            NT_BREF => {
                if self.ast.bref(node).state & NST_NAME_REF == 0 {
                    return Err(ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED);
                }
            }
            NT_ANCHOR => {
                if let Some(t) = self.ast.anchor(node).target {
                    self.numbered_ref_check(t)?;
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn disable_noname_group_capture(&mut self, root: NodeId) -> R<NodeId> {
        let num_mem = self.env.num_mem;
        let mut map = vec![0i32; num_mem as usize + 1];
        let mut counter = 0;
        let root = self.noname_disable_map(root, &mut map, &mut counter)?;
        self.renumber_by_map(root, &map, num_mem)?;

        let mut pos = 1;
        for i in 1..=num_mem as usize {
            if map[i] > 0 {
                let n = self.env.mem_nodes.get(i).copied().flatten();
                if pos < self.env.mem_nodes.len() {
                    self.env.mem_nodes[pos] = n;
                }
                pos += 1;
            }
        }

        let loc = self.env.capture_history;
        self.env.capture_history = 0;
        for i in 1..=31 {
            if bit_status_at(loc, i) {
                let n = map.get(i as usize).copied().unwrap_or(0);
                bit_status_on_at_simple(&mut self.env.capture_history, n);
            }
        }

        self.env.num_mem = self.env.num_named;
        self.num_mem = self.env.num_named;
        self.names.renumber(&map);
        Ok(root)
    }

    fn unset_addr_list_fix(&mut self) -> R<()> {
        for i in 0..self.uslist.len() {
            let (offset, target) = self.uslist[i];
            let en = self.ast.enclose(target);
            if en.state & NST_ADDR_FIXED == 0 {
                return Err(ONIGERR_PARSER_BUG);
            }
            let addr = en.call_addr.to_ne_bytes();
            self.p[offset..offset + 4].copy_from_slice(&addr);
        }
        Ok(())
    }

    // ---- length analysis ----

    fn quantifiers_memory_node_info(&self, node: NodeId) -> R<i32> {
        let mut r = 0;
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    let v = self.quantifiers_memory_node_info(self.ast.car(cell))?;
                    if v > r {
                        r = v;
                    }
                }
            }
            NT_CALL => {
                if self.ast.call(node).state & NST_RECURSION != 0 {
                    return Ok(NQ_TARGET_IS_EMPTY_REC);
                }
                r = self.quantifiers_memory_node_info(self.target(node)?)?;
            }
            NT_QTFR => {
                if self.ast.qtfr(node).upper != 0 {
                    r = self.quantifiers_memory_node_info(self.target(node)?)?;
                }
            }
            NT_ENCLOSE => match self.ast.enclose(node).typ {
                ENCLOSE_MEMORY => return Ok(NQ_TARGET_IS_EMPTY_MEM),
                ENCLOSE_OPTION | ENCLOSE_STOP_BACKTRACK | ENCLOSE_CONDITION | ENCLOSE_ABSENT => {
                    r = self.quantifiers_memory_node_info(self.target(node)?)?;
                }
                _ => {}
            },
            _ => {}
        }
        Ok(r)
    }

    fn get_min_match_length(&mut self, node: NodeId) -> R<usize> {
        let mut min = 0usize;
        match self.ast.ntype(node) {
            NT_BREF => {
                let br = self.ast.bref(node);
                if br.state & NST_RECURSION != 0 {
                    return Ok(0);
                }
                let backs = br.back.clone();
                let first = *backs.first().ok_or(ONIGERR_PARSER_BUG)?;
                if first > self.env.num_mem {
                    return Err(ONIGERR_INVALID_BACKREF);
                }
                min = self.get_min_match_length(self.mem_node(first)?)?;
                for &b in &backs[1..] {
                    if b > self.env.num_mem {
                        return Err(ONIGERR_INVALID_BACKREF);
                    }
                    let tmin = self.get_min_match_length(self.mem_node(b)?)?;
                    if min > tmin {
                        min = tmin;
                    }
                }
            }
            NT_CALL => {
                let t = self.target(node)?;
                if self.ast.call(node).state & NST_RECURSION != 0 {
                    let en = self.ast.enclose(t);
                    if en.state & NST_MIN_FIXED != 0 {
                        min = en.min_len;
                    }
                } else {
                    min = self.get_min_match_length(t)?;
                }
            }
            NT_LIST => {
                for cell in self.cells(node) {
                    let tmin = self.get_min_match_length(self.ast.car(cell))?;
                    min = distance_add(min, tmin);
                }
            }
            NT_ALT => {
                for (i, cell) in self.cells(node).into_iter().enumerate() {
                    let tmin = self.get_min_match_length(self.ast.car(cell))?;
                    if i == 0 || min > tmin {
                        min = tmin;
                    }
                }
            }
            NT_STR => min = self.ast.str(node).s.len(),
            NT_CTYPE | NT_CCLASS | NT_CANY => min = 1,
            NT_QTFR => {
                let (lower, t) = (self.ast.qtfr(node).lower, self.target(node)?);
                if lower > 0 {
                    min = self.get_min_match_length(t)?;
                    min = distance_multiply(min, lower);
                }
            }
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                match en.typ {
                    ENCLOSE_MEMORY => {
                        if en.state & NST_MIN_FIXED != 0 {
                            min = en.min_len;
                        } else if en.state & NST_MARK1 != 0 {
                            min = 0; /* recursive */
                        } else {
                            let t = self.target(node)?;
                            self.set_enclose_status(node, NST_MARK1);
                            let r = self.get_min_match_length(t);
                            self.clear_enclose_status(node, NST_MARK1);
                            min = r?;
                            let en = self.ast.enclose_mut(node);
                            en.min_len = min;
                            en.state |= NST_MIN_FIXED;
                        }
                    }
                    ENCLOSE_OPTION | ENCLOSE_STOP_BACKTRACK | ENCLOSE_CONDITION => {
                        min = self.get_min_match_length(self.target(node)?)?;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        Ok(min)
    }

    fn get_max_match_length(&mut self, node: NodeId) -> R<usize> {
        let mut max = 0usize;
        match self.ast.ntype(node) {
            NT_LIST => {
                for cell in self.cells(node) {
                    let tmax = self.get_max_match_length(self.ast.car(cell))?;
                    max = distance_add(max, tmax);
                }
            }
            NT_ALT => {
                for cell in self.cells(node) {
                    let tmax = self.get_max_match_length(self.ast.car(cell))?;
                    if max < tmax {
                        max = tmax;
                    }
                }
            }
            NT_STR => max = self.ast.str(node).s.len(),
            NT_CTYPE | NT_CCLASS | NT_CANY => max = self.enc.max_len(),
            NT_BREF => {
                let br = self.ast.bref(node);
                if br.state & NST_RECURSION != 0 {
                    return Ok(INF);
                }
                for b in br.back.clone() {
                    if b > self.env.num_mem {
                        return Err(ONIGERR_INVALID_BACKREF);
                    }
                    let tmax = self.get_max_match_length(self.mem_node(b)?)?;
                    if max < tmax {
                        max = tmax;
                    }
                }
            }
            NT_CALL => {
                if self.ast.call(node).state & NST_RECURSION == 0 {
                    max = self.get_max_match_length(self.target(node)?)?;
                } else {
                    max = INF;
                }
            }
            NT_QTFR => {
                let (upper, t) = (self.ast.qtfr(node).upper, self.target(node)?);
                if upper != 0 {
                    max = self.get_max_match_length(t)?;
                    if max != 0 {
                        max = if !is_repeat_infinite(upper) { distance_multiply(max, upper) } else { INF };
                    }
                }
            }
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                match en.typ {
                    ENCLOSE_MEMORY => {
                        if en.state & NST_MAX_FIXED != 0 {
                            max = en.max_len;
                        } else if en.state & NST_MARK1 != 0 {
                            max = INF;
                        } else {
                            let t = self.target(node)?;
                            self.set_enclose_status(node, NST_MARK1);
                            let r = self.get_max_match_length(t);
                            self.clear_enclose_status(node, NST_MARK1);
                            max = r?;
                            let en = self.ast.enclose_mut(node);
                            en.max_len = max;
                            en.state |= NST_MAX_FIXED;
                        }
                    }
                    ENCLOSE_OPTION | ENCLOSE_STOP_BACKTRACK | ENCLOSE_CONDITION => {
                        max = self.get_max_match_length(self.target(node)?)?;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        Ok(max)
    }

    /// `get_char_length_tree1`.
    fn get_char_length_tree1(&mut self, node: NodeId, level: i32) -> Result<i32, CharLenError> {
        let level = level + 1;
        let mut len: i32 = 0;
        match self.ast.ntype(node) {
            NT_LIST => {
                for cell in self.cells(node) {
                    let tlen = self.get_char_length_tree1(self.ast.car(cell), level)?;
                    len = len.checked_add(tlen).ok_or(ONIGERR_INVALID_LOOK_BEHIND_PATTERN)?;
                }
            }
            NT_ALT => {
                let cells = self.cells(node);
                let tlen = self.get_char_length_tree1(self.ast.car(cells[0]), level)?;
                let mut varlen = false;
                for &cell in &cells[1..] {
                    let tlen2 = self.get_char_length_tree1(self.ast.car(cell), level)?;
                    if tlen != tlen2 {
                        varlen = true;
                    }
                }
                if varlen {
                    return Err(if level == 1 { CharLenError::TopAltVarLen } else { CharLenError::VarLen });
                }
                len = tlen;
            }
            NT_STR => {
                let s = &self.ast.str(node).s;
                let mut p = 0;
                let mut n = 0usize;
                while p < s.len() {
                    p += self.enc.enclen(s, p, s.len());
                    n += 1;
                }
                len = i32::try_from(n).map_err(|_| ONIGERR_INVALID_LOOK_BEHIND_PATTERN)?;
            }
            NT_QTFR => {
                let qn = self.ast.qtfr(node);
                if qn.lower == qn.upper {
                    let lower = qn.lower;
                    let tlen = self.get_char_length_tree1(self.target(node)?, level)?;
                    len = tlen.checked_mul(lower).ok_or(ONIGERR_INVALID_LOOK_BEHIND_PATTERN)?;
                } else {
                    return Err(CharLenError::VarLen);
                }
            }
            NT_CALL => {
                if self.ast.call(node).state & NST_RECURSION == 0 {
                    len = self.get_char_length_tree1(self.target(node)?, level)?;
                } else {
                    return Err(CharLenError::VarLen);
                }
            }
            NT_CTYPE | NT_CCLASS | NT_CANY => len = 1,
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                match en.typ {
                    ENCLOSE_MEMORY => {
                        if en.state & NST_CLEN_FIXED != 0 {
                            len = en.char_len;
                        } else {
                            len = self.get_char_length_tree1(self.target(node)?, level)?;
                            let en = self.ast.enclose_mut(node);
                            en.char_len = len;
                            en.state |= NST_CLEN_FIXED;
                        }
                    }
                    ENCLOSE_OPTION | ENCLOSE_STOP_BACKTRACK | ENCLOSE_CONDITION => {
                        len = self.get_char_length_tree1(self.target(node)?, level)?;
                    }
                    _ => {}
                }
            }
            NT_ANCHOR => {}
            _ => return Err(CharLenError::VarLen),
        }
        Ok(len)
    }

    fn get_char_length_tree(&mut self, node: NodeId) -> Result<i32, CharLenError> {
        self.get_char_length_tree1(node, 0)
    }

    /// x is not included y ==> true
    fn is_not_included(&self, x: NodeId, y: NodeId) -> bool {
        let (mut x, mut y) = (x, y);
        loop {
            let ytype = self.ast.ntype(y);
            match self.ast.ntype(x) {
                NT_CTYPE => match ytype {
                    NT_CTYPE => {
                        let (xc, yc) = (self.ast.ctype(x), self.ast.ctype(y));
                        return yc.ctype == xc.ctype && yc.not != xc.not && yc.ascii_range == xc.ascii_range;
                    }
                    NT_CCLASS | NT_STR => {
                        std::mem::swap(&mut x, &mut y);
                        continue;
                    }
                    _ => return false,
                },
                NT_CCLASS => {
                    let xc = self.ast.cclass(x);
                    match ytype {
                        NT_CTYPE => {
                            let yt = self.ast.ctype(y);
                            if yt.ctype != CTYPE_WORD {
                                return false;
                            }
                            let is_word = |i: u32| {
                                if yt.ascii_range {
                                    i < 0x80 && self.enc.is_code_word(i)
                                } else {
                                    self.enc.is_code_word(i)
                                }
                            };
                            if !yt.not {
                                if xc.mbuf.is_none() && !xc.is_not() {
                                    for i in 0..SINGLE_BYTE_SIZE {
                                        if xc.bs.at(i) && is_word(i) {
                                            return false;
                                        }
                                    }
                                    return true;
                                }
                                return false;
                            } else {
                                if xc.mbuf.is_some() {
                                    return false;
                                }
                                for i in 0..SINGLE_BYTE_SIZE {
                                    if !is_word(i) {
                                        if !xc.is_not() {
                                            if xc.bs.at(i) {
                                                return false;
                                            }
                                        } else if !xc.bs.at(i) {
                                            return false;
                                        }
                                    }
                                }
                                return true;
                            }
                        }
                        NT_CCLASS => {
                            let yc = self.ast.cclass(y);
                            for i in 0..SINGLE_BYTE_SIZE {
                                let v = xc.bs.at(i);
                                if (v && !xc.is_not()) || (!v && xc.is_not()) {
                                    let v = yc.bs.at(i);
                                    if (v && !yc.is_not()) || (!v && yc.is_not()) {
                                        return false;
                                    }
                                }
                            }
                            return (xc.mbuf.is_none() && !xc.is_not()) || (yc.mbuf.is_none() && !yc.is_not());
                        }
                        NT_STR => {
                            std::mem::swap(&mut x, &mut y);
                            continue;
                        }
                        _ => return false,
                    }
                }
                NT_STR => {
                    let xs = self.ast.str(x);
                    if xs.s.is_empty() {
                        return false;
                    }
                    match ytype {
                        NT_CTYPE => {
                            let yt = self.ast.ctype(y);
                            if yt.ctype != CTYPE_WORD {
                                return false;
                            }
                            let code = self.enc.mbc_to_code(&xs.s, 0, xs.s.len());
                            let word = if yt.ascii_range {
                                Enc::ascii_is_code_ctype(code, CTYPE_WORD)
                            } else {
                                self.enc.is_code_word(code)
                            };
                            return if word { yt.not } else { !yt.not };
                        }
                        NT_CCLASS => {
                            let code = self.enc.mbc_to_code(&xs.s, 0, xs.s.len());
                            return !is_code_in_cc(self.enc, code, self.ast.cclass(y));
                        }
                        NT_STR => {
                            let ys = self.ast.str(y);
                            let len = xs.s.len().min(ys.s.len());
                            if xs.is_ambig() || ys.is_ambig() {
                                /* tiny version */
                                return false;
                            }
                            return xs.s[..len] != ys.s[..len];
                        }
                        _ => return false,
                    }
                }
                _ => return false,
            }
        }
    }

    fn get_head_value_node(&self, node: NodeId, exact: bool, options: u32) -> Option<NodeId> {
        match self.ast.ntype(node) {
            NT_CTYPE | NT_CCLASS => {
                if !exact {
                    return Some(node);
                }
                None
            }
            NT_LIST => self.get_head_value_node(self.ast.car(node), exact, options),
            NT_STR => {
                let sn = self.ast.str(node);
                if sn.s.is_empty() {
                    return None;
                }
                if !exact || sn.is_raw() || !is_ignorecase(options) {
                    return Some(node);
                }
                None
            }
            NT_QTFR => {
                let qn = self.ast.qtfr(node);
                if qn.lower > 0 {
                    return self.get_head_value_node(qn.target?, exact, options);
                }
                None
            }
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                match en.typ {
                    ENCLOSE_OPTION => self.get_head_value_node(en.target?, exact, en.option),
                    ENCLOSE_MEMORY | ENCLOSE_STOP_BACKTRACK | ENCLOSE_CONDITION => {
                        self.get_head_value_node(en.target?, exact, options)
                    }
                    _ => None,
                }
            }
            NT_ANCHOR => {
                let an = self.ast.anchor(node);
                if an.typ == ANCHOR_PREC_READ {
                    return self.get_head_value_node(an.target?, exact, options);
                }
                None
            }
            _ => None,
        }
    }

    fn check_type_tree(&self, node: NodeId, type_mask: i32, enclose_mask: i32, anchor_mask: i32) -> R<i32> {
        let typ = self.ast.ntype(node);
        if ntype2bit(typ) & type_mask == 0 {
            return Ok(1);
        }
        let mut r = 0;
        match typ {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    r = self.check_type_tree(self.ast.car(cell), type_mask, enclose_mask, anchor_mask)?;
                    if r != 0 {
                        break;
                    }
                }
            }
            NT_QTFR => r = self.check_type_tree(self.target(node)?, type_mask, enclose_mask, anchor_mask)?,
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                if en.typ & enclose_mask == 0 {
                    return Ok(1);
                }
                r = self.check_type_tree(self.target(node)?, type_mask, enclose_mask, anchor_mask)?;
            }
            NT_ANCHOR => {
                let an = self.ast.anchor(node);
                if an.typ & anchor_mask == 0 {
                    return Ok(1);
                }
                if let Some(t) = an.target {
                    r = self.check_type_tree(t, type_mask, enclose_mask, anchor_mask)?;
                }
            }
            _ => {}
        }
        Ok(r)
    }

    // ---- subexpression calls (USE_SUBEXP_CALL) ----

    fn is_lookaround(typ: i32) -> bool {
        matches!(typ, ANCHOR_PREC_READ | ANCHOR_PREC_READ_NOT | ANCHOR_LOOK_BEHIND | ANCHOR_LOOK_BEHIND_NOT)
    }

    fn subexp_inf_recursive_check(&mut self, node: NodeId, head: bool) -> R<i32> {
        let mut head = head;
        let mut r = 0;
        match self.ast.ntype(node) {
            NT_LIST => {
                for cell in self.cells(node) {
                    let car = self.ast.car(cell);
                    let ret = self.subexp_inf_recursive_check(car, head)?;
                    if ret == RECURSION_INFINITE {
                        return Ok(ret);
                    }
                    r |= ret;
                    if head {
                        let min = self.get_min_match_length(car)?;
                        if min != 0 {
                            head = false;
                        }
                    }
                }
            }
            NT_ALT => {
                r = RECURSION_EXIST;
                for cell in self.cells(node) {
                    let ret = self.subexp_inf_recursive_check(self.ast.car(cell), head)?;
                    if ret == RECURSION_INFINITE {
                        return Ok(ret);
                    }
                    r &= ret;
                }
            }
            NT_QTFR => {
                r = self.subexp_inf_recursive_check(self.target(node)?, head)?;
                if r == RECURSION_EXIST && self.ast.qtfr(node).lower == 0 {
                    r = 0;
                }
            }
            NT_ANCHOR => {
                if Self::is_lookaround(self.ast.anchor(node).typ) {
                    r = self.subexp_inf_recursive_check(self.target(node)?, head)?;
                }
            }
            NT_CALL => r = self.subexp_inf_recursive_check(self.target(node)?, head)?,
            NT_ENCLOSE => {
                let st = self.enclose_state(node);
                if st & NST_MARK2 != 0 {
                    return Ok(0);
                } else if st & NST_MARK1 != 0 {
                    return Ok(if !head { RECURSION_EXIST } else { RECURSION_INFINITE });
                } else {
                    let t = self.target(node)?;
                    self.set_enclose_status(node, NST_MARK2);
                    let ret = self.subexp_inf_recursive_check(t, head);
                    self.clear_enclose_status(node, NST_MARK2);
                    r = ret?;
                }
            }
            _ => {}
        }
        Ok(r)
    }

    fn subexp_inf_recursive_check_trav(&mut self, node: NodeId) -> R<()> {
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    self.subexp_inf_recursive_check_trav(self.ast.car(cell))?;
                }
            }
            NT_QTFR => self.subexp_inf_recursive_check_trav(self.target(node)?)?,
            NT_ANCHOR => {
                if Self::is_lookaround(self.ast.anchor(node).typ) {
                    self.subexp_inf_recursive_check_trav(self.target(node)?)?;
                }
            }
            NT_ENCLOSE => {
                let t = self.target(node)?;
                if self.enclose_state(node) & NST_RECURSION != 0 {
                    self.set_enclose_status(node, NST_MARK1);
                    if self.subexp_inf_recursive_check(t, true)? > 0 {
                        return Err(ONIGERR_NEVER_ENDING_RECURSION);
                    }
                    self.clear_enclose_status(node, NST_MARK1);
                }
                self.subexp_inf_recursive_check_trav(t)?;
            }
            _ => {}
        }
        Ok(())
    }

    fn subexp_recursive_check(&mut self, node: NodeId) -> R<i32> {
        let mut r = 0;
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    r |= self.subexp_recursive_check(self.ast.car(cell))?;
                }
            }
            NT_QTFR => r = self.subexp_recursive_check(self.target(node)?)?,
            NT_ANCHOR => {
                if Self::is_lookaround(self.ast.anchor(node).typ) {
                    r = self.subexp_recursive_check(self.target(node)?)?;
                }
            }
            NT_CALL => {
                r = self.subexp_recursive_check(self.target(node)?)?;
                if r != 0 {
                    self.ast.call_mut(node).state |= NST_RECURSION;
                }
            }
            NT_ENCLOSE => {
                let st = self.enclose_state(node);
                if st & NST_MARK2 != 0 {
                    return Ok(0);
                } else if st & NST_MARK1 != 0 {
                    return Ok(1); /* recursion */
                } else {
                    let t = self.target(node)?;
                    self.set_enclose_status(node, NST_MARK2);
                    let ret = self.subexp_recursive_check(t);
                    self.clear_enclose_status(node, NST_MARK2);
                    r = ret?;
                }
            }
            _ => {}
        }
        Ok(r)
    }

    fn subexp_recursive_check_trav(&mut self, node: NodeId) -> R<i32> {
        let mut r = 0;
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    let ret = self.subexp_recursive_check_trav(self.ast.car(cell))?;
                    if ret == FOUND_CALLED_NODE {
                        r = FOUND_CALLED_NODE;
                    }
                }
            }
            NT_QTFR => {
                r = self.subexp_recursive_check_trav(self.target(node)?)?;
                let qn = self.ast.qtfr_mut(node);
                if qn.upper == 0 && r == FOUND_CALLED_NODE {
                    qn.is_referred = true;
                }
            }
            NT_ANCHOR => {
                if Self::is_lookaround(self.ast.anchor(node).typ) {
                    r = self.subexp_recursive_check_trav(self.target(node)?)?;
                }
            }
            NT_ENCLOSE => {
                let t = self.target(node)?;
                let st = self.enclose_state(node);
                if st & NST_RECURSION == 0 && st & NST_CALLED != 0 {
                    self.set_enclose_status(node, NST_MARK1);
                    let ret = self.subexp_recursive_check(t);
                    self.clear_enclose_status(node, NST_MARK1);
                    if ret? != 0 {
                        self.set_enclose_status(node, NST_RECURSION);
                    }
                }
                r = self.subexp_recursive_check_trav(t)?;
                if self.enclose_state(node) & NST_CALLED != 0 {
                    r |= FOUND_CALLED_NODE;
                }
            }
            _ => {}
        }
        Ok(r)
    }

    fn setup_subexp_call(&mut self, node: NodeId) -> R<()> {
        match self.ast.ntype(node) {
            NT_LIST | NT_ALT => {
                for cell in self.cells(node) {
                    self.setup_subexp_call(self.ast.car(cell))?;
                }
            }
            NT_QTFR | NT_ENCLOSE => self.setup_subexp_call(self.target(node)?)?,
            NT_CALL => {
                let cn = self.ast.call(node);
                let name = cn.name.clone();
                let gnum = cn.group_num;
                let group_num = if gnum != 0 {
                    if self.env.num_named > 0
                        && SYNTAX_RUBY.bv(ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP)
                        && self.env.option & ONIG_OPTION_CAPTURE_GROUP == 0
                    {
                        return Err(ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED);
                    }
                    if gnum > self.env.num_mem {
                        self.set_error_string(&name);
                        return Err(ONIGERR_UNDEFINED_GROUP_REFERENCE);
                    }
                    gnum
                } else if name.is_empty() {
                    gnum
                } else {
                    let refs = match self.names.find(&name) {
                        Some(e) if !e.back_refs.is_empty() => e.back_refs.clone(),
                        _ => {
                            self.set_error_string(&name);
                            return Err(ONIGERR_UNDEFINED_NAME_REFERENCE);
                        }
                    };
                    if refs.len() > 1 && !SYNTAX_RUBY.bv(ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME_CALL) {
                        self.set_error_string(&name);
                        return Err(ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL);
                    }
                    refs[0]
                };
                let target = match self.env.mem_node(group_num) {
                    Some(t) => t,
                    None => {
                        self.set_error_string(&name);
                        return Err(ONIGERR_UNDEFINED_NAME_REFERENCE);
                    }
                };
                let cn = self.ast.call_mut(node);
                cn.group_num = group_num;
                cn.target = Some(target);
                self.set_enclose_status(target, NST_CALLED);
                bit_status_on_at(&mut self.env.bt_mem_start, group_num);
            }
            NT_ANCHOR => {
                if Self::is_lookaround(self.ast.anchor(node).typ) {
                    self.setup_subexp_call(self.target(node)?)?;
                }
            }
            _ => {}
        }
        Ok(())
    }

    // ---- setup_tree ----

    /// (?<=A|B) ==> (?<=A)|(?<=B)
    /// (?<!A|B) ==> (?<!A)(?<!B)
    fn divide_look_behind_alternatives(&mut self, node: NodeId) -> R<()> {
        let anc_type = self.ast.anchor(node).typ;
        let head = self.target(node)?;
        let np = self.ast.car(head);
        self.ast.swap(node, head);
        self.ast.set_car(node, head);
        self.ast.anchor_mut(head).target = Some(np);

        let mut np = node;
        while let Some(next) = self.ast.cdr(np) {
            np = next;
            let insert_node = self.ast.new_anchor(anc_type);
            let car = self.ast.car(np);
            self.ast.anchor_mut(insert_node).target = Some(car);
            self.ast.set_car(np, insert_node);
        }

        if anc_type == ANCHOR_LOOK_BEHIND_NOT {
            let mut np = Some(node);
            while let Some(n) = np {
                let (car, cdr) = (self.ast.car(n), self.ast.cdr(n));
                self.ast.nodes[n] = Node::List { car, cdr }; /* alt -> list */
                np = cdr;
            }
        }
        Ok(())
    }

    fn setup_look_behind(&mut self, node: NodeId) -> R<()> {
        let t = self.target(node)?;
        match self.get_char_length_tree(t) {
            Ok(len) => {
                self.ast.anchor_mut(node).char_len = len;
                Ok(())
            }
            Err(CharLenError::VarLen) => Err(ONIGERR_INVALID_LOOK_BEHIND_PATTERN),
            Err(CharLenError::TopAltVarLen) => {
                if SYNTAX_RUBY.bv(ONIG_SYN_DIFFERENT_LEN_ALT_LOOK_BEHIND) {
                    self.divide_look_behind_alternatives(node)
                } else {
                    Err(ONIGERR_INVALID_LOOK_BEHIND_PATTERN)
                }
            }
            Err(CharLenError::Error(e)) => Err(e),
        }
    }

    fn next_setup(&mut self, node: NodeId, next_node: NodeId) -> R<()> {
        let mut node = node;
        loop {
            match self.ast.ntype(node) {
                NT_QTFR => {
                    let qn = self.ast.qtfr(node);
                    if qn.greedy && is_repeat_infinite(qn.upper) {
                        let (lower, target) = (qn.lower, self.target(node)?);
                        if let Some(n) = self.get_head_value_node(next_node, true, self.options) {
                            /* '\0': for UTF-16BE etc... */
                            if self.ast.str(n).s[0] != 0 {
                                self.ast.qtfr_mut(node).next_head_exact = Some(n);
                            }
                        }
                        /* automatic possessification a*b ==> (?>a*)b */
                        if lower <= 1 && is_node_type_simple(self.ast.ntype(target)) {
                            if let Some(x) = self.get_head_value_node(target, false, self.options) {
                                if let Some(y) = self.get_head_value_node(next_node, false, self.options) {
                                    if self.is_not_included(x, y) {
                                        let en = self.ast.new_enclose(ENCLOSE_STOP_BACKTRACK);
                                        self.set_enclose_status(en, NST_STOP_BT_SIMPLE_REPEAT);
                                        self.ast.swap(node, en);
                                        self.ast.enclose_mut(node).target = Some(en);
                                    }
                                }
                            }
                        }
                    }
                    return Ok(());
                }
                NT_ENCLOSE => {
                    let en = self.ast.enclose(node);
                    if en.typ == ENCLOSE_MEMORY && en.state & NST_CALLED == 0 {
                        node = self.target(node)?;
                        continue;
                    }
                    return Ok(());
                }
                _ => return Ok(()),
            }
        }
    }

    fn update_string_node_case_fold(&mut self, node: NodeId) {
        let s = std::mem::take(&mut self.ast.str_mut(node).s);
        let mut out = Bytes::default();
        let mut buf = [0u8; ONIGENC_MBC_CASE_FOLD_MAXLEN];
        let mut p = 0;
        while p < s.len() {
            let n = self.enc.mbc_case_fold(self.case_fold_flag, &s, &mut p, s.len(), &mut buf);
            out.extend_from_slice(&buf[..n]);
        }
        // onig_node_str_set clears the flags too.
        let sn = self.ast.str_mut(node);
        sn.s = out;
        sn.flag = 0;
    }

    fn expand_case_fold_make_rem_string(&mut self, s: &[u8]) -> NodeId {
        let node = self.ast.new_str(s);
        self.update_string_node_case_fold(node);
        self.ast.str_mut(node).flag |= NSTR_AMBIG | NSTR_DONT_GET_OPT_INFO;
        node
    }

    fn expand_case_fold_string_alt(
        &mut self,
        items: &[CaseFoldCodeItem],
        s: &[u8],
        p: usize,
        slen: usize,
    ) -> R<(NodeId, bool)> {
        let end = s.len();
        let varlen = items.iter().any(|it| usize::try_from(it.byte_len) != Ok(slen));

        let snode = self.ast.new_str(&s[p..p + slen]);
        let mut anode = self.ast.new_alt(snode, None);
        let (rnode, mut var_anode) = if varlen {
            let xnode = self.ast.new_list(anode, None);
            let va = self.ast.new_alt(xnode, None);
            (va, Some(va))
        } else {
            (anode, None)
        };

        for item in items {
            let mut bytes = Vec::new();
            for &code in &item.code[..usize::try_from(item.code_len).unwrap_or(0)] {
                let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
                let len = self.enc.code_to_mbc(code, &mut buf);
                let len = usize::try_from(len).map_err(|_| len)?;
                bytes.extend_from_slice(&buf[..len]);
            }
            let snode = self.ast.new_str(&bytes);

            let byte_len = usize::try_from(item.byte_len).unwrap_or(0);
            if byte_len != slen {
                let q = p + byte_len;
                let car = if q < end {
                    let rem = self.expand_case_fold_make_rem_string(&s[q..end]);
                    let xnode = self.list_add(None, snode);
                    self.list_add(Some(xnode), rem);
                    xnode
                } else {
                    snode
                };
                let an = self.ast.new_alt(car, None);
                let va = var_anode.ok_or(ONIGERR_PARSER_BUG)?;
                self.ast.set_cdr(va, Some(an));
                var_anode = Some(an);
            } else {
                let an = self.ast.new_alt(snode, None);
                self.ast.set_cdr(anode, Some(an));
                anode = an;
            }
        }
        Ok((rnode, varlen))
    }

    fn expand_case_fold_string(&mut self, node: NodeId, state: i32) -> R<()> {
        let sn = self.ast.str(node);
        if sn.is_ambig() || sn.s.is_empty() {
            return Ok(());
        }
        let s = sn.s.clone();
        let end = s.len();
        let is_in_look_behind = state & IN_LOOK_BEHIND != 0;

        let mut top_root: Option<NodeId> = None;
        let mut root: Option<NodeId> = None;
        let mut prev_node: Option<NodeId> = None;
        let mut snode: Option<NodeId> = None;
        let mut alt_num: usize = 1;
        let mut p = 0;
        while p < end {
            let mut items = [CaseFoldCodeItem::default(); ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM];
            let n = self.enc.get_case_fold_codes_by_str(self.case_fold_flag, &s, p, end, &mut items);
            let n = usize::try_from(n).map_err(|_| n)?;
            let items = &items[..n];
            let len = self.enc.enclen(&s, p, end);

            let varlen = items.iter().any(|it| usize::try_from(it.byte_len) != Ok(len) || it.code_len != 1);
            if n == 0 || !varlen || is_in_look_behind {
                let sn = match snode {
                    Some(sn) => sn,
                    None => {
                        if root.is_none() {
                            if let Some(pn) = prev_node {
                                let l = self.list_add(None, pn);
                                top_root = Some(l);
                                root = Some(l);
                            }
                        }
                        let sn = self.ast.new_str(&[]);
                        prev_node = Some(sn);
                        snode = Some(sn);
                        if let Some(r) = root {
                            self.list_add(Some(r), sn);
                        }
                        sn
                    }
                };
                self.ast.str_mut(sn).s.extend_from_slice(&s[p..p + len]);
            } else {
                alt_num = alt_num.saturating_mul(n + 1);
                if alt_num > THRESHOLD_CASE_FOLD_ALT_FOR_EXPANSION {
                    break;
                }
                if let Some(sn) = snode {
                    self.update_string_node_case_fold(sn);
                    self.ast.str_mut(sn).flag |= NSTR_AMBIG;
                }
                if root.is_none() {
                    if let Some(pn) = prev_node {
                        let l = self.list_add(None, pn);
                        top_root = Some(l);
                        root = Some(l);
                    }
                }

                let (pn, varlen) = self.expand_case_fold_string_alt(items, &s, p, len)?;
                prev_node = Some(pn);
                if varlen {
                    match root {
                        None => top_root = Some(pn),
                        Some(r) => {
                            self.list_add(Some(r), pn);
                        }
                    }
                    root = Some(self.ast.car(pn));
                } else if let Some(r) = root {
                    self.list_add(Some(r), pn);
                }
                snode = None;
            }
            p += len;
        }
        if let Some(sn) = snode {
            self.update_string_node_case_fold(sn);
            self.ast.str_mut(sn).flag |= NSTR_AMBIG;
        }

        if p < end {
            let srem = self.expand_case_fold_make_rem_string(&s[p..end]);
            if root.is_none() {
                if let Some(pn) = prev_node {
                    let l = self.list_add(None, pn);
                    top_root = Some(l);
                    root = Some(l);
                }
            }
            match root {
                None => prev_node = Some(srem),
                Some(r) => {
                    self.list_add(Some(r), srem);
                }
            }
        }

        /* ending */
        let top = top_root.or(prev_node).ok_or(ONIGERR_PARSER_BUG)?;
        self.ast.swap(node, top);
        self.ast.nodes[top] = Node::Freed;
        Ok(())
    }

    /// setup_tree does the following work.
    ///  1. check empty loop. (set qn->target_empty_info)
    ///  2. expand ignore-case in char class.
    ///  3. set memory status bit flags. (reg->mem_stats)
    ///  4. set qn->head_exact for [push, exact] -> [push_or_jump_exact1, exact].
    ///  5. find invalid patterns in look-behind.
    ///  6. expand repeated string.
    fn setup_tree(&mut self, node: NodeId, state: i32) -> R<()> {
        match self.ast.ntype(node) {
            NT_LIST => {
                let mut prev: Option<NodeId> = None;
                for cell in self.cells(node) {
                    let car = self.ast.car(cell);
                    self.setup_tree(car, state)?;
                    if let Some(pv) = prev {
                        self.next_setup(pv, car)?;
                    }
                    prev = Some(car);
                }
            }
            NT_ALT => {
                for cell in self.cells(node) {
                    self.setup_tree(self.ast.car(cell), state | IN_ALT)?;
                }
            }
            NT_STR => {
                if is_ignorecase(self.options) && !self.ast.str(node).is_raw() {
                    self.expand_case_fold_string(node, state)?;
                }
            }
            NT_BREF => {
                let br = self.ast.bref(node);
                let nest = br.state & NST_NEST_LEVEL != 0;
                for p in br.back.clone() {
                    if p > self.env.num_mem {
                        return Err(ONIGERR_INVALID_BACKREF);
                    }
                    bit_status_on_at(&mut self.env.backrefed_mem, p);
                    bit_status_on_at(&mut self.env.bt_mem_start, p);
                    if nest {
                        bit_status_on_at(&mut self.env.bt_mem_end, p);
                    }
                    let m = self.mem_node(p)?;
                    self.set_enclose_status(m, NST_MEM_BACKREFED);
                }
            }
            NT_QTFR => return self.setup_qtfr(node, state),
            NT_ENCLOSE => {
                let en = self.ast.enclose(node);
                let t = en.target.ok_or(ONIGERR_PARSER_BUG)?;
                match en.typ {
                    ENCLOSE_OPTION => {
                        let options = self.options;
                        self.options = en.option;
                        let r = self.setup_tree(t, state);
                        self.options = options;
                        r?;
                    }
                    ENCLOSE_MEMORY => {
                        let mut state = state;
                        let (regnum, est) = (en.regnum, en.state);
                        if state & (IN_ALT | IN_NOT | IN_VAR_REPEAT | IN_CALL) != 0 {
                            bit_status_on_at(&mut self.env.bt_mem_start, regnum);
                        }
                        if est & NST_CALLED != 0 {
                            state |= IN_CALL;
                        }
                        if est & NST_RECURSION != 0 {
                            state |= IN_RECCALL;
                        } else if state & IN_RECCALL != 0 {
                            self.set_enclose_status(node, NST_RECURSION);
                        }
                        self.setup_tree(t, state)?;
                    }
                    ENCLOSE_STOP_BACKTRACK => {
                        self.setup_tree(t, state)?;
                        if self.ast.ntype(t) == NT_QTFR {
                            let tqn = self.ast.qtfr(t);
                            if is_repeat_infinite(tqn.upper) && tqn.lower <= 1 && tqn.greedy {
                                /* (?>a*), a*+ etc... */
                                let qt = tqn.target.ok_or(ONIGERR_PARSER_BUG)?;
                                if is_node_type_simple(self.ast.ntype(qt)) {
                                    self.set_enclose_status(node, NST_STOP_BT_SIMPLE_REPEAT);
                                }
                            }
                        }
                    }
                    ENCLOSE_CONDITION => {
                        if en.state & NST_NAME_REF == 0
                            && self.env.num_named > 0
                            && SYNTAX_RUBY.bv(ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP)
                            && self.env.option & ONIG_OPTION_CAPTURE_GROUP == 0
                        {
                            return Err(ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED);
                        }
                        if en.regnum > self.env.num_mem {
                            return Err(ONIGERR_INVALID_BACKREF);
                        }
                        self.setup_tree(t, state)?;
                    }
                    ENCLOSE_ABSENT => self.setup_tree(t, state)?,
                    _ => {}
                }
            }
            NT_ANCHOR => {
                let an = self.ast.anchor(node);
                match an.typ {
                    ANCHOR_PREC_READ => self.setup_tree(self.target(node)?, state)?,
                    ANCHOR_PREC_READ_NOT => self.setup_tree(self.target(node)?, state | IN_NOT)?,
                    ANCHOR_LOOK_BEHIND => {
                        let t = self.target(node)?;
                        let r = self.check_type_tree(t, ALLOWED_TYPE_IN_LB, ALLOWED_ENCLOSE_IN_LB, ALLOWED_ANCHOR_IN_LB)?;
                        if r > 0 {
                            return Err(ONIGERR_INVALID_LOOK_BEHIND_PATTERN);
                        }
                        self.setup_tree(t, state | IN_LOOK_BEHIND)?;
                        self.setup_look_behind(node)?;
                    }
                    ANCHOR_LOOK_BEHIND_NOT => {
                        let t = self.target(node)?;
                        let r = self.check_type_tree(
                            t,
                            ALLOWED_TYPE_IN_LB,
                            ALLOWED_ENCLOSE_IN_LB_NOT,
                            ALLOWED_ANCHOR_IN_LB_NOT,
                        )?;
                        if r > 0 {
                            return Err(ONIGERR_INVALID_LOOK_BEHIND_PATTERN);
                        }
                        self.setup_tree(t, state | IN_NOT | IN_LOOK_BEHIND)?;
                        self.setup_look_behind(node)?;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn setup_qtfr(&mut self, node: NodeId, state: i32) -> R<()> {
        let mut state = state;
        let target = self.target(node)?;
        if state & IN_REPEAT != 0 {
            self.ast.qtfr_mut(node).state |= NST_IN_REPEAT;
        }

        let qn = self.ast.qtfr(node);
        if is_repeat_infinite(qn.upper) || qn.upper >= 1 {
            let d = self.get_min_match_length(target)?;
            if d == 0 {
                self.ast.qtfr_mut(node).target_empty_info = NQ_TARGET_IS_EMPTY;
                let r = self.quantifiers_memory_node_info(target)?;
                if r > 0 {
                    self.ast.qtfr_mut(node).target_empty_info = r;
                }
            }
        }

        state |= IN_REPEAT;
        let qn = self.ast.qtfr(node);
        if qn.lower != qn.upper {
            state |= IN_VAR_REPEAT;
        }
        self.setup_tree(target, state)?;

        /* expand string */
        if self.ast.ntype(target) == NT_STR {
            let qn = self.ast.qtfr(node);
            if qn.lower > 1 {
                let n = qn.lower;
                let sn = self.ast.str(target).clone();
                let len = sn.s.len();
                let np = self.ast.new_str(&sn.s);
                self.ast.str_mut(np).flag = sn.flag;

                let mut i: i32 = 1;
                while i < n && (i as usize + 1) * len <= EXPAND_STRING_MAX_LENGTH {
                    self.ast.str_mut(np).s.extend_from_slice(&sn.s);
                    i += 1;
                }
                let qn = self.ast.qtfr(node);
                if i < qn.upper || is_repeat_infinite(qn.upper) {
                    let qn = self.ast.qtfr_mut(node);
                    qn.lower -= i;
                    if !is_repeat_infinite(qn.upper) {
                        qn.upper -= i;
                    }
                    let np1 = self.ast.new_list(np, None);
                    self.ast.swap(np1, node);
                    self.list_add(Some(node), np1);
                } else {
                    self.ast.swap(np, node);
                    self.ast.nodes[np] = Node::Freed;
                }
                return Ok(());
            }
        }
        Ok(())
    }

    // ---- code generation ----

    fn add_bytes(&mut self, b: &[u8]) -> R<()> {
        self.p.try_reserve(b.len()).map_err(|_| ONIGERR_MEMORY)?;
        self.p.extend_from_slice(b);
        Ok(())
    }

    /// Every instruction passes here, so this is where a program that would
    /// outgrow its offset type is stopped.
    fn add_opcode(&mut self, op: u8) -> R<()> {
        if self.p.len() > MAX_COMPILED_PROGRAM_SIZE {
            return Err(ONIGERR_TOO_BIG_COMPILED_PROGRAM);
        }
        self.add_bytes(&[op])
    }

    fn add_i32(&mut self, v: i64) -> R<()> {
        let v: i32 = v.try_into().map_err(|_| ONIGERR_TOO_BIG_COMPILED_PROGRAM)?;
        self.add_bytes(&v.to_ne_bytes())
    }

    fn add_rel_addr(&mut self, addr: i64) -> R<()> {
        self.add_i32(addr)
    }

    fn add_abs_addr(&mut self, addr: i64) -> R<()> {
        self.add_i32(addr)
    }

    fn add_length(&mut self, len: i64) -> R<()> {
        self.add_i32(len)
    }

    fn add_mem_num(&mut self, num: i32) -> R<()> {
        let num = i16::try_from(num).map_err(|_| ONIGERR_PARSER_BUG)?;
        self.add_bytes(&num.to_ne_bytes())
    }

    fn add_option(&mut self, option: u32) -> R<()> {
        self.add_bytes(&option.to_ne_bytes())
    }

    fn add_opcode_rel_addr(&mut self, op: u8, addr: i64) -> R<()> {
        self.add_opcode(op)?;
        self.add_rel_addr(addr)
    }

    fn add_bitset(&mut self, bs: &BitSet) -> R<()> {
        let mut b = [0u8; 32];
        for (i, w) in bs.0.iter().enumerate() {
            b[i * 4..i * 4 + 4].copy_from_slice(&w.to_ne_bytes());
        }
        self.add_bytes(&b)
    }

    fn compile_tree_empty_check(&mut self, node: NodeId, empty_info: i32) -> R<()> {
        let saved_num_null_check = self.num_null_check;
        if empty_info != 0 {
            self.add_opcode(OP_NULL_CHECK_START)?;
            self.add_mem_num(self.num_null_check)?; /* NULL CHECK ID */
            self.num_null_check += 1;
            if i16::try_from(self.num_null_check).is_err() {
                return Err(ONIGERR_TOO_MANY_NULL_CHECK);
            }
        }
        self.compile_tree(node)?;
        if empty_info != 0 {
            match empty_info {
                NQ_TARGET_IS_EMPTY => self.add_opcode(OP_NULL_CHECK_END)?,
                NQ_TARGET_IS_EMPTY_MEM => self.add_opcode(OP_NULL_CHECK_END_MEMST)?,
                NQ_TARGET_IS_EMPTY_REC => self.add_opcode(OP_NULL_CHECK_END_MEMST_PUSH)?,
                _ => {}
            }
            self.add_mem_num(saved_num_null_check)?; /* NULL CHECK ID */
        }
        Ok(())
    }

    fn compile_call(&mut self, node: NodeId) -> R<()> {
        self.add_opcode(OP_CALL)?;
        let target = self.target(node)?;
        self.uslist.push((self.p.len(), target));
        self.add_abs_addr(0) /* dummy addr. */
    }

    fn compile_tree_n_times(&mut self, node: NodeId, n: i32) -> R<()> {
        for _ in 0..n {
            self.compile_tree(node)?;
        }
        Ok(())
    }

    fn select_str_opcode(mb_len: usize, byte_len: usize, ignore_case: bool) -> u8 {
        let str_len = byte_len.div_ceil(mb_len);
        if ignore_case {
            match str_len {
                1 => OP_EXACT1_IC,
                _ => OP_EXACTN_IC,
            }
        } else {
            match mb_len {
                1 => match str_len {
                    1 => OP_EXACT1,
                    2 => OP_EXACT2,
                    3 => OP_EXACT3,
                    4 => OP_EXACT4,
                    5 => OP_EXACT5,
                    _ => OP_EXACTN,
                },
                2 => match str_len {
                    1 => OP_EXACTMB2N1,
                    2 => OP_EXACTMB2N2,
                    3 => OP_EXACTMB2N3,
                    _ => OP_EXACTMB2N,
                },
                3 => OP_EXACTMB3N,
                _ => OP_EXACTMBN,
            }
        }
    }

    #[inline]
    fn is_need_str_len_op_exact(op: u8) -> bool {
        matches!(op, OP_EXACTN | OP_EXACTMB2N | OP_EXACTMB3N | OP_EXACTMBN | OP_EXACTN_IC)
    }

    fn add_compile_string_length(mb_len: usize, byte_len: usize, ignore_case: bool) -> i64 {
        let op = Self::select_str_opcode(mb_len, byte_len, ignore_case);
        let mut len = SIZE_OPCODE;
        if op == OP_EXACTMBN {
            len += SIZE_LENGTH;
        }
        if Self::is_need_str_len_op_exact(op) {
            len += SIZE_LENGTH;
        }
        len + byte_len as i64
    }

    fn add_compile_string(&mut self, s: &[u8], mb_len: usize, ignore_case: bool) -> R<()> {
        let byte_len = s.len();
        let op = Self::select_str_opcode(mb_len, byte_len, ignore_case);
        self.add_opcode(op)?;
        if op == OP_EXACTMBN {
            self.add_length(mb_len as i64)?;
        }
        if Self::is_need_str_len_op_exact(op) {
            if op == OP_EXACTN_IC {
                self.add_length(byte_len as i64)?;
            } else {
                self.add_length((byte_len / mb_len) as i64)?;
            }
        }
        self.add_bytes(s)
    }

    fn compile_length_string_node(&self, node: NodeId) -> i64 {
        let sn = self.ast.str(node);
        if sn.s.is_empty() {
            return 0;
        }
        let ambig = sn.is_ambig();
        StringRuns::new(self.enc, &sn.s, ambig)
            .map(|(_, mb_len, blen)| Self::add_compile_string_length(mb_len, blen, ambig))
            .sum()
    }

    fn compile_string_node(&mut self, node: NodeId) -> R<()> {
        let sn = self.ast.str(node);
        if sn.s.is_empty() {
            return Ok(());
        }
        let ambig = sn.is_ambig();
        // Taken out of the tree while the program grows, and put back.
        let s = std::mem::take(&mut self.ast.str_mut(node).s);
        let r = StringRuns::new(self.enc, &s, ambig)
            .try_for_each(|(start, mb_len, blen)| self.add_compile_string(&s[start..start + blen], mb_len, ambig));
        self.ast.str_mut(node).s = s;
        r
    }

    fn compile_length_string_raw_node(&self, node: NodeId) -> i64 {
        let sn = self.ast.str(node);
        if sn.s.is_empty() {
            return 0;
        }
        Self::add_compile_string_length(1, sn.s.len(), false)
    }

    fn compile_string_raw_node(&mut self, node: NodeId) -> R<()> {
        let s = self.ast.str(node).s.clone();
        if s.is_empty() {
            return Ok(());
        }
        self.add_compile_string(&s, 1, false)
    }

    /// The `BBuf` layout of a code range list: the count, then the pairs.
    fn code_ranges_bytes(m: &CodeRanges) -> Vec<u8> {
        let mut b = Vec::with_capacity(4 + m.len() * 8);
        b.extend_from_slice(&(m.len() as u32).to_ne_bytes());
        for &(from, to) in m {
            b.extend_from_slice(&from.to_ne_bytes());
            b.extend_from_slice(&to.to_ne_bytes());
        }
        b
    }

    fn compile_length_cclass_node(&self, node: NodeId) -> i64 {
        let cc = self.ast.cclass(node);
        match &cc.mbuf {
            None => SIZE_OPCODE + SIZE_BITSET,
            Some(m) => {
                let mut len =
                    if self.enc.min_len() > 1 || cc.bs.is_empty() { SIZE_OPCODE } else { SIZE_OPCODE + SIZE_BITSET };
                len += SIZE_LENGTH + 4 + m.len() as i64 * 8;
                len
            }
        }
    }

    fn compile_cclass_node(&mut self, node: NodeId) -> R<()> {
        let cc = self.ast.cclass(node).clone();
        match &cc.mbuf {
            None => {
                self.add_opcode(if cc.is_not() { OP_CCLASS_NOT } else { OP_CCLASS })?;
                self.add_bitset(&cc.bs)
            }
            Some(m) => {
                let mb = Self::code_ranges_bytes(m);
                if self.enc.min_len() > 1 || cc.bs.is_empty() {
                    self.add_opcode(if cc.is_not() { OP_CCLASS_MB_NOT } else { OP_CCLASS_MB })?;
                } else {
                    self.add_opcode(if cc.is_not() { OP_CCLASS_MIX_NOT } else { OP_CCLASS_MIX })?;
                    self.add_bitset(&cc.bs)?;
                }
                self.add_length(mb.len() as i64)?;
                self.add_bytes(&mb)
            }
        }
    }

    fn entry_repeat_range(&mut self, id: i32, lower: i32, upper: i32) {
        let id = id as usize;
        if self.repeat_range.len() <= id {
            self.repeat_range.resize(id + 1, RepeatRange::default());
        }
        self.repeat_range[id] =
            RepeatRange { lower, upper: if is_repeat_infinite(upper) { 0x7fffffff } else { upper } };
    }

    fn compile_range_repeat_node(&mut self, node: NodeId, target_len: i64, empty_info: i32) -> R<()> {
        let qn = self.ast.qtfr(node);
        let (greedy, lower, upper, in_repeat) = (qn.greedy, qn.lower, qn.upper, qn.state & NST_IN_REPEAT != 0);
        let target = self.target(node)?;
        let num_repeat = self.num_repeat;

        self.add_opcode(if greedy { OP_REPEAT } else { OP_REPEAT_NG })?;
        self.add_mem_num(num_repeat)?; /* OP_REPEAT ID */
        self.num_repeat += 1;
        if i16::try_from(self.num_repeat).is_err() {
            return Err(ONIGERR_TOO_MANY_RANGE_REPEAT);
        }
        self.add_rel_addr(target_len + SIZE_OP_REPEAT_INC)?;
        self.entry_repeat_range(num_repeat, lower, upper);

        self.compile_tree_empty_check(target, empty_info)?;

        if self.num_call > 0 || in_repeat {
            self.add_opcode(if greedy { OP_REPEAT_INC_SG } else { OP_REPEAT_INC_NG_SG })?;
        } else {
            self.add_opcode(if greedy { OP_REPEAT_INC } else { OP_REPEAT_INC_NG })?;
        }
        self.add_mem_num(num_repeat) /* OP_REPEAT ID */
    }

    fn compile_length_quantifier_node(&mut self, node: NodeId) -> R<i64> {
        let qn = self.ast.qtfr(node).clone();
        let target = qn.target.ok_or(ONIGERR_PARSER_BUG)?;
        let infinite = is_repeat_infinite(qn.upper);
        let empty_info = qn.target_empty_info;
        let tlen = self.compile_length_tree(target)?;
        let (lower, upper) = (qn.lower as i64, qn.upper as i64);

        /* anychar repeat */
        if self.ast.ntype(target) == NT_CANY && qn.greedy && infinite {
            if qn.next_head_exact.is_some() {
                return Ok(SIZE_OP_ANYCHAR_STAR_PEEK_NEXT + tlen * lower);
            } else {
                return Ok(SIZE_OP_ANYCHAR_STAR + tlen * lower);
            }
        }

        let mod_tlen =
            if empty_info != 0 { tlen + (SIZE_OP_NULL_CHECK_START + SIZE_OP_NULL_CHECK_END) } else { tlen };

        let len = if infinite && (lower <= 1 || is_expand_limit_ok(tlen, lower)) {
            let mut len =
                if lower == 1 && tlen > QUANTIFIER_EXPAND_LIMIT_SIZE { SIZE_OP_JUMP } else { tlen * lower };
            if qn.greedy {
                if qn.next_head_exact.is_some() {
                    len += SIZE_OP_PUSH_IF_PEEK_NEXT + mod_tlen + SIZE_OP_JUMP;
                } else {
                    len += SIZE_OP_PUSH + mod_tlen + SIZE_OP_JUMP;
                }
            } else {
                len += SIZE_OP_JUMP + mod_tlen + SIZE_OP_PUSH;
            }
            len
        } else if upper == 0 && qn.is_referred {
            /* /(?<n>..){0}/ */
            SIZE_OP_JUMP + tlen
        } else if !infinite && qn.greedy && (upper == 1 || is_expand_limit_ok(tlen + SIZE_OP_PUSH, upper)) {
            tlen * lower + (SIZE_OP_PUSH + tlen) * (upper - lower)
        } else if !qn.greedy && upper == 1 && lower == 0 {
            /* '??' */
            SIZE_OP_PUSH + SIZE_OP_JUMP + tlen
        } else {
            SIZE_OP_REPEAT_INC + mod_tlen + SIZE_OPCODE + SIZE_RELADDR + SIZE_MEMNUM
        };
        Ok(len)
    }

    fn compile_quantifier_node(&mut self, node: NodeId) -> R<()> {
        let qn = self.ast.qtfr(node).clone();
        let target = qn.target.ok_or(ONIGERR_PARSER_BUG)?;
        let infinite = is_repeat_infinite(qn.upper);
        let empty_info = qn.target_empty_info;
        let tlen = self.compile_length_tree(target)?;
        let (lower, upper) = (qn.lower as i64, qn.upper as i64);

        if qn.greedy && infinite && self.ast.ntype(target) == NT_CANY {
            self.compile_tree_n_times(target, qn.lower)?;
            if let Some(nh) = qn.next_head_exact {
                let op = if is_multiline(self.options) { OP_ANYCHAR_ML_STAR_PEEK_NEXT } else { OP_ANYCHAR_STAR_PEEK_NEXT };
                self.add_opcode(op)?;
                let b = self.ast.str(nh).s[0];
                return self.add_bytes(&[b]);
            } else {
                let op = if is_multiline(self.options) { OP_ANYCHAR_ML_STAR } else { OP_ANYCHAR_STAR };
                return self.add_opcode(op);
            }
        }

        let mod_tlen =
            if empty_info != 0 { tlen + (SIZE_OP_NULL_CHECK_START + SIZE_OP_NULL_CHECK_END) } else { tlen };

        if infinite && (lower <= 1 || is_expand_limit_ok(tlen, lower)) {
            if lower == 1 && tlen > QUANTIFIER_EXPAND_LIMIT_SIZE {
                if qn.greedy {
                    if qn.next_head_exact.is_some() {
                        self.add_opcode_rel_addr(OP_JUMP, SIZE_OP_PUSH_IF_PEEK_NEXT)?;
                    } else {
                        self.add_opcode_rel_addr(OP_JUMP, SIZE_OP_PUSH)?;
                    }
                } else {
                    self.add_opcode_rel_addr(OP_JUMP, SIZE_OP_JUMP)?;
                }
            } else {
                self.compile_tree_n_times(target, qn.lower)?;
            }

            if qn.greedy {
                if let Some(nh) = qn.next_head_exact {
                    self.add_opcode_rel_addr(OP_PUSH_IF_PEEK_NEXT, mod_tlen + SIZE_OP_JUMP)?;
                    let b = self.ast.str(nh).s[0];
                    self.add_bytes(&[b])?;
                    self.compile_tree_empty_check(target, empty_info)?;
                    self.add_opcode_rel_addr(OP_JUMP, -(mod_tlen + SIZE_OP_JUMP + SIZE_OP_PUSH_IF_PEEK_NEXT))?;
                } else {
                    self.loop_pushes.push(self.p.len());
                    self.add_opcode_rel_addr(OP_PUSH, mod_tlen + SIZE_OP_JUMP)?;
                    self.compile_tree_empty_check(target, empty_info)?;
                    self.add_opcode_rel_addr(OP_JUMP, -(mod_tlen + SIZE_OP_JUMP + SIZE_OP_PUSH))?;
                }
            } else {
                self.add_opcode_rel_addr(OP_JUMP, mod_tlen)?;
                self.compile_tree_empty_check(target, empty_info)?;
                self.add_opcode_rel_addr(OP_PUSH, -(mod_tlen + SIZE_OP_PUSH))?;
            }
        } else if upper == 0 && qn.is_referred {
            /* /(?<n>..){0}/ */
            self.add_opcode_rel_addr(OP_JUMP, tlen)?;
            self.compile_tree(target)?;
        } else if !infinite && qn.greedy && (upper == 1 || is_expand_limit_ok(tlen + SIZE_OP_PUSH, upper)) {
            let n = upper - lower;
            self.compile_tree_n_times(target, qn.lower)?;
            for i in 0..n {
                self.add_opcode_rel_addr(OP_PUSH, (n - i) * tlen + (n - i - 1) * SIZE_OP_PUSH)?;
                self.compile_tree(target)?;
            }
        } else if !qn.greedy && upper == 1 && lower == 0 {
            /* '??' */
            self.add_opcode_rel_addr(OP_PUSH, SIZE_OP_JUMP)?;
            self.add_opcode_rel_addr(OP_JUMP, tlen)?;
            self.compile_tree(target)?;
        } else {
            self.compile_range_repeat_node(node, mod_tlen, empty_info)?;
        }
        Ok(())
    }

    fn compile_length_option_node(&mut self, node: NodeId) -> R<i64> {
        let en = self.ast.enclose(node);
        let (option, t) = (en.option, en.target.ok_or(ONIGERR_PARSER_BUG)?);
        let prev = self.options;
        self.options = option;
        let tlen = self.compile_length_tree(t);
        self.options = prev;
        tlen
    }

    fn compile_option_node(&mut self, node: NodeId) -> R<()> {
        let en = self.ast.enclose(node);
        let (option, t) = (en.option, en.target.ok_or(ONIGERR_PARSER_BUG)?);
        let prev = self.options;
        self.options = option;
        let r = self.compile_tree(t);
        self.options = prev;
        r
    }

    fn memory_end_len(&self, en: &EncloseNode) -> i64 {
        let rec = en.state & NST_RECURSION != 0;
        if bit_status_at(self.bt_mem_end, en.regnum) {
            if rec { SIZE_OP_MEMORY_END_PUSH_REC } else { SIZE_OP_MEMORY_END_PUSH }
        } else if rec {
            SIZE_OP_MEMORY_END_REC
        } else {
            SIZE_OP_MEMORY_END
        }
    }

    fn compile_length_enclose_node(&mut self, node: NodeId) -> R<i64> {
        let en = self.ast.enclose(node).clone();
        if en.typ == ENCLOSE_OPTION {
            return self.compile_length_option_node(node);
        }
        let tlen = match en.target {
            Some(t) => self.compile_length_tree(t)?,
            None => 0,
        };

        let len = match en.typ {
            ENCLOSE_MEMORY => {
                if en.state & NST_CALLED != 0 {
                    SIZE_OP_MEMORY_START_PUSH + tlen + SIZE_OP_CALL + SIZE_OP_JUMP + SIZE_OP_RETURN + self.memory_end_len(&en)
                } else if en.state & NST_RECURSION != 0 {
                    SIZE_OP_MEMORY_START_PUSH
                        + tlen
                        + if bit_status_at(self.bt_mem_end, en.regnum) {
                            SIZE_OP_MEMORY_END_PUSH_REC
                        } else {
                            SIZE_OP_MEMORY_END_REC
                        }
                } else {
                    let start = if bit_status_at(self.bt_mem_start, en.regnum) {
                        SIZE_OP_MEMORY_START_PUSH
                    } else {
                        SIZE_OP_MEMORY_START
                    };
                    start
                        + tlen
                        + if bit_status_at(self.bt_mem_end, en.regnum) {
                            SIZE_OP_MEMORY_END_PUSH
                        } else {
                            SIZE_OP_MEMORY_END
                        }
                }
            }
            ENCLOSE_STOP_BACKTRACK => SIZE_OP_PUSH_STOP_BT + tlen + SIZE_OP_POP_STOP_BT,
            ENCLOSE_CONDITION => {
                let mut len = SIZE_OP_CONDITION;
                let x = en.target.ok_or(ONIGERR_PARSER_BUG)?;
                if self.ast.ntype(x) != NT_ALT {
                    return Err(ONIGERR_PARSER_BUG);
                }
                len += self.compile_length_tree(self.ast.car(x))? + SIZE_OP_JUMP; /* yes-node */
                let x = self.ast.cdr(x).ok_or(ONIGERR_PARSER_BUG)?;
                len += self.compile_length_tree(self.ast.car(x))?; /* no-node */
                if self.ast.cdr(x).is_some() {
                    return Err(ONIGERR_INVALID_CONDITION_PATTERN);
                }
                len
            }
            ENCLOSE_ABSENT => SIZE_OP_PUSH_ABSENT_POS + SIZE_OP_ABSENT + tlen + SIZE_OP_ABSENT_END,
            _ => return Err(ONIGERR_TYPE_BUG),
        };
        Ok(len)
    }

    fn compile_enclose_node(&mut self, node: NodeId) -> R<()> {
        let en = self.ast.enclose(node).clone();
        if en.typ == ENCLOSE_OPTION {
            return self.compile_option_node(node);
        }
        let target = en.target.ok_or(ONIGERR_PARSER_BUG)?;
        match en.typ {
            ENCLOSE_MEMORY => {
                let called = en.state & NST_CALLED != 0;
                let rec = en.state & NST_RECURSION != 0;
                let bt_end = bit_status_at(self.bt_mem_end, en.regnum);
                if called {
                    self.add_opcode(OP_CALL)?;
                    let call_addr = self.p.len() as i64 + SIZE_ABSADDR + SIZE_OP_JUMP;
                    let call_addr32: i32 = call_addr.try_into().map_err(|_| ONIGERR_TOO_BIG_COMPILED_PROGRAM)?;
                    let e = self.ast.enclose_mut(node);
                    e.call_addr = call_addr32;
                    e.state |= NST_ADDR_FIXED;
                    self.add_abs_addr(call_addr)?;
                    let mut len = self.compile_length_tree(target)?;
                    len += SIZE_OP_MEMORY_START_PUSH + SIZE_OP_RETURN;
                    len += self.memory_end_len(&en);
                    self.add_opcode_rel_addr(OP_JUMP, len)?;
                }
                if bit_status_at(self.bt_mem_start, en.regnum) {
                    self.add_opcode(OP_MEMORY_START_PUSH)?;
                } else {
                    self.add_opcode(OP_MEMORY_START)?;
                }
                self.add_mem_num(en.regnum)?;
                self.compile_tree(target)?;
                if called {
                    let op = if bt_end {
                        if rec { OP_MEMORY_END_PUSH_REC } else { OP_MEMORY_END_PUSH }
                    } else if rec {
                        OP_MEMORY_END_REC
                    } else {
                        OP_MEMORY_END
                    };
                    self.add_opcode(op)?;
                    self.add_mem_num(en.regnum)?;
                    self.add_opcode(OP_RETURN)?;
                } else if rec {
                    self.add_opcode(if bt_end { OP_MEMORY_END_PUSH_REC } else { OP_MEMORY_END_REC })?;
                    self.add_mem_num(en.regnum)?;
                } else {
                    self.add_opcode(if bt_end { OP_MEMORY_END_PUSH } else { OP_MEMORY_END })?;
                    self.add_mem_num(en.regnum)?;
                }
            }
            ENCLOSE_STOP_BACKTRACK => {
                // The POP_STOP_BT shortcut for simple repeats is disabled
                // under USE_MATCH_CACHE: the cache pushes an extra stack item.
                self.add_opcode(OP_PUSH_STOP_BT)?;
                self.compile_tree(target)?;
                self.add_opcode(OP_POP_STOP_BT)?;
            }
            ENCLOSE_CONDITION => {
                self.add_opcode(OP_CONDITION)?;
                self.add_mem_num(en.regnum)?;
                let x = target;
                if self.ast.ntype(x) != NT_ALT {
                    return Err(ONIGERR_PARSER_BUG);
                }
                let yes = self.ast.car(x);
                let len = self.compile_length_tree(yes)?; /* yes-node */
                let x2 = self.ast.cdr(x).ok_or(ONIGERR_PARSER_BUG)?;
                let no = self.ast.car(x2);
                let len2 = self.compile_length_tree(no)?; /* no-node */
                if self.ast.cdr(x2).is_some() {
                    return Err(ONIGERR_INVALID_CONDITION_PATTERN);
                }
                self.add_rel_addr(len + SIZE_OP_JUMP)?;
                self.compile_tree(yes)?;
                self.add_opcode_rel_addr(OP_JUMP, len2)?;
                self.compile_tree(no)?;
            }
            ENCLOSE_ABSENT => {
                let len = self.compile_length_tree(target)?;
                self.add_opcode(OP_PUSH_ABSENT_POS)?;
                self.add_opcode_rel_addr(OP_ABSENT, len + SIZE_OP_ABSENT_END)?;
                self.compile_tree(target)?;
                self.add_opcode(OP_ABSENT_END)?;
            }
            _ => return Err(ONIGERR_TYPE_BUG),
        }
        Ok(())
    }

    fn compile_length_anchor_node(&mut self, node: NodeId) -> R<i64> {
        let an = self.ast.anchor(node).clone();
        let tlen = match an.target {
            Some(t) => self.compile_length_tree(t)?,
            None => 0,
        };
        Ok(match an.typ {
            ANCHOR_PREC_READ => SIZE_OP_PUSH_POS + tlen + SIZE_OP_POP_POS,
            ANCHOR_PREC_READ_NOT => SIZE_OP_PUSH_POS_NOT + tlen + SIZE_OP_FAIL_POS,
            ANCHOR_LOOK_BEHIND => SIZE_OP_LOOK_BEHIND + tlen,
            ANCHOR_LOOK_BEHIND_NOT => SIZE_OP_PUSH_LOOK_BEHIND_NOT + tlen + SIZE_OP_FAIL_LOOK_BEHIND_NOT,
            _ => SIZE_OPCODE,
        })
    }

    fn look_behind_char_len(&mut self, node: NodeId) -> R<i32> {
        let an = self.ast.anchor(node);
        if an.char_len < 0 {
            let t = self.target(node)?;
            self.get_char_length_tree(t).map_err(|_| ONIGERR_INVALID_LOOK_BEHIND_PATTERN)
        } else {
            Ok(an.char_len)
        }
    }

    fn compile_anchor_node(&mut self, node: NodeId) -> R<()> {
        let an = self.ast.anchor(node).clone();
        match an.typ {
            ANCHOR_BEGIN_BUF => self.add_opcode(OP_BEGIN_BUF),
            ANCHOR_END_BUF => self.add_opcode(OP_END_BUF),
            ANCHOR_BEGIN_LINE => self.add_opcode(OP_BEGIN_LINE),
            ANCHOR_END_LINE => self.add_opcode(OP_END_LINE),
            ANCHOR_SEMI_END_BUF => self.add_opcode(OP_SEMI_END_BUF),
            ANCHOR_BEGIN_POSITION => self.add_opcode(OP_BEGIN_POSITION),
            ANCHOR_WORD_BOUND => self.add_opcode(if an.ascii_range { OP_ASCII_WORD_BOUND } else { OP_WORD_BOUND }),
            ANCHOR_NOT_WORD_BOUND => {
                self.add_opcode(if an.ascii_range { OP_NOT_ASCII_WORD_BOUND } else { OP_NOT_WORD_BOUND })
            }
            ANCHOR_WORD_BEGIN => self.add_opcode(if an.ascii_range { OP_ASCII_WORD_BEGIN } else { OP_WORD_BEGIN }),
            ANCHOR_WORD_END => self.add_opcode(if an.ascii_range { OP_ASCII_WORD_END } else { OP_WORD_END }),
            ANCHOR_KEEP => self.add_opcode(OP_KEEP),
            ANCHOR_PREC_READ => {
                let t = an.target.ok_or(ONIGERR_PARSER_BUG)?;
                self.add_opcode(OP_PUSH_POS)?;
                self.compile_tree(t)?;
                self.add_opcode(OP_POP_POS)
            }
            ANCHOR_PREC_READ_NOT => {
                let t = an.target.ok_or(ONIGERR_PARSER_BUG)?;
                let len = self.compile_length_tree(t)?;
                self.add_opcode_rel_addr(OP_PUSH_POS_NOT, len + SIZE_OP_FAIL_POS)?;
                self.compile_tree(t)?;
                self.add_opcode(OP_FAIL_POS)
            }
            ANCHOR_LOOK_BEHIND => {
                let t = an.target.ok_or(ONIGERR_PARSER_BUG)?;
                self.add_opcode(OP_LOOK_BEHIND)?;
                let n = self.look_behind_char_len(node)?;
                self.add_length(n as i64)?;
                self.compile_tree(t)
            }
            ANCHOR_LOOK_BEHIND_NOT => {
                let t = an.target.ok_or(ONIGERR_PARSER_BUG)?;
                let len = self.compile_length_tree(t)?;
                self.add_opcode_rel_addr(OP_PUSH_LOOK_BEHIND_NOT, len + SIZE_OP_FAIL_LOOK_BEHIND_NOT)?;
                let n = self.look_behind_char_len(node)?;
                self.add_length(n as i64)?;
                self.compile_tree(t)?;
                self.add_opcode(OP_FAIL_LOOK_BEHIND_NOT)
            }
            _ => Err(ONIGERR_TYPE_BUG),
        }
    }

    fn compile_length_tree(&mut self, node: NodeId) -> R<i64> {
        let r = match self.ast.ntype(node) {
            NT_LIST => {
                let mut len = 0;
                for cell in self.cells(node) {
                    len += self.compile_length_tree(self.ast.car(cell))?;
                }
                len
            }
            NT_ALT => {
                let cells = self.cells(node);
                let mut len = 0;
                for &cell in &cells {
                    len += self.compile_length_tree(self.ast.car(cell))?;
                }
                len + (SIZE_OP_PUSH + SIZE_OP_JUMP) * (cells.len() as i64 - 1)
            }
            NT_STR => {
                if self.ast.str(node).is_raw() {
                    self.compile_length_string_raw_node(node)
                } else {
                    self.compile_length_string_node(node)
                }
            }
            NT_CCLASS => self.compile_length_cclass_node(node),
            NT_CTYPE | NT_CANY => SIZE_OPCODE,
            NT_BREF => {
                let br = self.ast.bref(node);
                let back_num = br.back.len() as i64;
                if br.state & NST_NEST_LEVEL != 0 {
                    SIZE_OPCODE + SIZE_OPTION + SIZE_LENGTH + SIZE_LENGTH + SIZE_MEMNUM * back_num
                } else if back_num == 1 {
                    if !is_ignorecase(self.options) && br.back[0] <= 2 {
                        SIZE_OPCODE
                    } else {
                        SIZE_OPCODE + SIZE_MEMNUM
                    }
                } else {
                    SIZE_OPCODE + SIZE_LENGTH + SIZE_MEMNUM * back_num
                }
            }
            NT_CALL => SIZE_OP_CALL,
            NT_QTFR => self.compile_length_quantifier_node(node)?,
            NT_ENCLOSE => self.compile_length_enclose_node(node)?,
            NT_ANCHOR => self.compile_length_anchor_node(node)?,
            _ => return Err(ONIGERR_TYPE_BUG),
        };
        Ok(r)
    }

    fn compile_tree(&mut self, node: NodeId) -> R<()> {
        match self.ast.ntype(node) {
            NT_LIST => {
                for cell in self.cells(node) {
                    self.compile_tree(self.ast.car(cell))?;
                }
            }
            NT_ALT => {
                let cells = self.cells(node);
                let mut len = 0;
                for (i, &cell) in cells.iter().enumerate() {
                    len += self.compile_length_tree(self.ast.car(cell))?;
                    if i + 1 < cells.len() {
                        len += SIZE_OP_PUSH + SIZE_OP_JUMP;
                    }
                }
                let pos = self.p.len() as i64 + len; /* goal position */

                for (i, &cell) in cells.iter().enumerate() {
                    let car = self.ast.car(cell);
                    let has_next = i + 1 < cells.len();
                    let len = self.compile_length_tree(car)?;
                    if has_next {
                        self.add_opcode_rel_addr(OP_PUSH, len + SIZE_OP_JUMP)?;
                    }
                    self.compile_tree(car)?;
                    if has_next {
                        let len = pos - (self.p.len() as i64 + SIZE_OP_JUMP);
                        self.add_opcode_rel_addr(OP_JUMP, len)?;
                    }
                }
            }
            NT_STR => {
                if self.ast.str(node).is_raw() {
                    self.compile_string_raw_node(node)?;
                } else {
                    self.compile_string_node(node)?;
                }
            }
            NT_CCLASS => self.compile_cclass_node(node)?,
            NT_CTYPE => {
                let ct = self.ast.ctype(node);
                let op = match ct.ctype {
                    CTYPE_WORD => {
                        if ct.ascii_range {
                            if ct.not { OP_NOT_ASCII_WORD } else { OP_ASCII_WORD }
                        } else if ct.not {
                            OP_NOT_WORD
                        } else {
                            OP_WORD
                        }
                    }
                    _ => return Err(ONIGERR_TYPE_BUG),
                };
                self.add_opcode(op)?;
            }
            NT_CANY => {
                self.add_opcode(if is_multiline(self.options) { OP_ANYCHAR_ML } else { OP_ANYCHAR })?;
            }
            NT_BREF => {
                let br = self.ast.bref(node).clone();
                if br.state & NST_NEST_LEVEL != 0 {
                    self.add_opcode(OP_BACKREF_WITH_LEVEL)?;
                    self.add_option(self.options & ONIG_OPTION_IGNORECASE)?;
                    self.add_length(br.nest_level as i64)?;
                    self.add_backref_mems(&br.back)?;
                } else if br.back.len() == 1 {
                    let n = br.back[0];
                    if is_ignorecase(self.options) {
                        self.add_opcode(OP_BACKREFN_IC)?;
                        self.add_mem_num(n)?;
                    } else {
                        match n {
                            1 => self.add_opcode(OP_BACKREF1)?,
                            2 => self.add_opcode(OP_BACKREF2)?,
                            _ => {
                                self.add_opcode(OP_BACKREFN)?;
                                self.add_mem_num(n)?;
                            }
                        }
                    }
                } else {
                    let op = if is_ignorecase(self.options) { OP_BACKREF_MULTI_IC } else { OP_BACKREF_MULTI };
                    self.add_opcode(op)?;
                    self.add_backref_mems(&br.back)?;
                }
            }
            NT_CALL => self.compile_call(node)?,
            NT_QTFR => self.compile_quantifier_node(node)?,
            NT_ENCLOSE => self.compile_enclose_node(node)?,
            NT_ANCHOR => self.compile_anchor_node(node)?,
            _ => {}
        }
        Ok(())
    }

    fn add_backref_mems(&mut self, backs: &[i32]) -> R<()> {
        self.add_length(backs.len() as i64)?;
        for &b in backs.iter().rev() {
            self.add_mem_num(b)?;
        }
        Ok(())
    }

    // ---- optimizer ----

    fn optimize_node_left(&mut self, node: NodeId, opt: &mut NodeOptInfo, env: &mut OptEnv) -> R<()> {
        opt.clear();
        opt.set_bound(&env.mmd);
        let enc = self.enc;

        match self.ast.ntype(node) {
            NT_LIST => {
                let mut nenv = *env;
                let mut nopt = self.take_opt();
                for cell in self.cells(node) {
                    self.optimize_node_left(self.ast.car(cell), &mut nopt, &mut nenv)?;
                    nenv.mmd.add(&nopt.len);
                    opt.concat_left(enc, &mut nopt);
                }
                self.opt_pool.push(nopt);
            }
            NT_ALT => {
                let mut nopt = self.take_opt();
                for (i, cell) in self.cells(node).into_iter().enumerate() {
                    self.optimize_node_left(self.ast.car(cell), &mut nopt, env)?;
                    if i == 0 {
                        *opt = (*nopt).clone();
                    } else {
                        opt.alt_merge(&nopt, enc);
                    }
                }
                self.opt_pool.push(nopt);
            }
            NT_STR => {
                let sn = self.ast.str(node);
                let slen = sn.s.len();
                if !sn.is_ambig() {
                    opt.exb.concat_str(&sn.s, enc);
                    opt.exb.ignore_case = 0;
                    if slen > 0 {
                        opt.map.add_char(sn.s[0], enc);
                    }
                    opt.len.set(slen, slen);
                } else {
                    let max;
                    if sn.is_dont_get_opt_info() {
                        let n = enc.strlen(&sn.s, 0, slen);
                        max = enc.max_len().wrapping_mul(n);
                    } else {
                        opt.exb.concat_str(&sn.s, enc);
                        opt.exb.ignore_case = 1;
                        if slen > 0 {
                            opt.map.add_char_amb(&sn.s, enc, self.case_fold_flag)?;
                        }
                        max = slen;
                    }
                    opt.len.set(slen, max);
                }
                if opt.exb.bytes().len() == slen {
                    opt.exb.reach_end = true;
                }
            }
            NT_CCLASS => {
                let cc = self.ast.cclass(node);
                /* no need to check ignore case. (set in setup_tree()) */
                if cc.mbuf.is_some() || cc.is_not() {
                    opt.len.set(enc.min_len(), enc.max_len());
                } else {
                    for i in 0..SINGLE_BYTE_SIZE {
                        let z = cc.bs.at(i);
                        if (z && !cc.is_not()) || (!z && cc.is_not()) {
                            opt.map.add_char(i as u8, enc);
                        }
                    }
                    opt.len.set(1, 1);
                }
            }
            NT_CTYPE => {
                let max = enc.max_len();
                let min;
                if max == 1 {
                    min = 1;
                    let ct = self.ast.ctype(node);
                    let maxcode = if ct.ascii_range { 0x80 } else { SINGLE_BYTE_SIZE };
                    if ct.ctype == CTYPE_WORD {
                        if ct.not {
                            for i in 0..SINGLE_BYTE_SIZE {
                                if !enc.is_code_word(i) || i >= maxcode {
                                    opt.map.add_char(i as u8, enc);
                                }
                            }
                        } else {
                            for i in 0..maxcode {
                                if enc.is_code_word(i) {
                                    opt.map.add_char(i as u8, enc);
                                }
                            }
                        }
                    }
                } else {
                    min = enc.min_len();
                }
                opt.len.set(min, max);
            }
            NT_CANY => opt.len.set(enc.min_len(), enc.max_len()),
            NT_ANCHOR => {
                let an = self.ast.anchor(node);
                match an.typ {
                    ANCHOR_BEGIN_BUF
                    | ANCHOR_BEGIN_POSITION
                    | ANCHOR_BEGIN_LINE
                    | ANCHOR_END_BUF
                    | ANCHOR_SEMI_END_BUF
                    | ANCHOR_END_LINE
                    | ANCHOR_LOOK_BEHIND /* just for (?<=x).* */
                    | ANCHOR_PREC_READ_NOT /* just for (?!x).* */ => opt.anc.add(an.typ),
                    ANCHOR_PREC_READ => {
                        let t = an.target.ok_or(ONIGERR_PARSER_BUG)?;
                        let mut nopt = self.take_opt();
                        self.optimize_node_left(t, &mut nopt, env)?;
                        if nopt.exb.len > 0 {
                            opt.expr = nopt.exb;
                        } else if nopt.exm.len > 0 {
                            opt.expr = nopt.exm;
                        }
                        opt.expr.reach_end = false;
                        if nopt.map.value > 0 {
                            opt.map = nopt.map.clone();
                        }
                        self.opt_pool.push(nopt);
                    }
                    _ => {}
                }
            }
            NT_BREF => {
                let br = self.ast.bref(node);
                if br.state & NST_RECURSION != 0 {
                    opt.len.set(0, INF);
                } else {
                    let backs = br.back.clone();
                    let first = *backs.first().ok_or(ONIGERR_PARSER_BUG)?;
                    let n0 = self.mem_node(first)?;
                    let mut min = self.get_min_match_length(n0)?;
                    let mut max = self.get_max_match_length(n0)?;
                    for &b in &backs[1..] {
                        let nb = self.mem_node(b)?;
                        let tmin = self.get_min_match_length(nb)?;
                        let tmax = self.get_max_match_length(nb)?;
                        if min > tmin {
                            min = tmin;
                        }
                        if max < tmax {
                            max = tmax;
                        }
                    }
                    opt.len.set(min, max);
                }
            }
            NT_CALL => {
                if self.ast.call(node).state & NST_RECURSION != 0 {
                    opt.len.set(0, INF);
                } else {
                    let t = self.target(node)?;
                    let save = env.options;
                    env.options = self.ast.enclose(t).option;
                    let r = self.optimize_node_left(t, opt, env);
                    env.options = save;
                    r?;
                }
            }
            NT_QTFR => {
                let qn = self.ast.qtfr(node).clone();
                let t = qn.target.ok_or(ONIGERR_PARSER_BUG)?;
                let mut nopt = self.take_opt();
                self.optimize_node_left(t, &mut nopt, env)?;

                if qn.lower == 0 && is_repeat_infinite(qn.upper) {
                    if env.mmd.max == 0 && self.ast.ntype(t) == NT_CANY && qn.greedy {
                        if is_multiline(env.options) {
                            /* implicit anchor: /.*a/ ==> /\A.*a/ */
                            opt.anc.add(ANCHOR_ANYCHAR_STAR_ML);
                        } else {
                            opt.anc.add(ANCHOR_ANYCHAR_STAR);
                        }
                    }
                } else if qn.lower > 0 {
                    *opt = (*nopt).clone();
                    if nopt.exb.len > 0 && nopt.exb.reach_end {
                        let mut i = 2;
                        while i <= qn.lower && !opt.exb.is_full() {
                            opt.exb.concat(&nopt.exb, enc);
                            i += 1;
                        }
                        if i < qn.lower {
                            opt.exb.reach_end = false;
                        }
                    }
                    if qn.lower != qn.upper {
                        opt.exb.reach_end = false;
                        opt.exm.reach_end = false;
                    }
                    if qn.lower > 1 {
                        opt.exm.reach_end = false;
                    }
                }

                let min = distance_multiply(nopt.len.min, qn.lower);
                let max = if is_repeat_infinite(qn.upper) {
                    if nopt.len.max > 0 { INF } else { 0 }
                } else {
                    distance_multiply(nopt.len.max, qn.upper)
                };
                opt.len.set(min, max);
                self.opt_pool.push(nopt);
            }
            NT_ENCLOSE => {
                let en = self.ast.enclose(node).clone();
                match en.typ {
                    ENCLOSE_OPTION => {
                        let save = env.options;
                        env.options = en.option;
                        let r = self.optimize_node_left(en.target.ok_or(ONIGERR_PARSER_BUG)?, opt, env);
                        env.options = save;
                        r?;
                    }
                    ENCLOSE_MEMORY => {
                        let count = {
                            let e = self.ast.enclose_mut(node);
                            e.opt_count += 1;
                            e.opt_count
                        };
                        if count > MAX_NODE_OPT_INFO_REF_COUNT {
                            let min = if en.state & NST_MIN_FIXED != 0 { en.min_len } else { 0 };
                            let max = if en.state & NST_MAX_FIXED != 0 { en.max_len } else { INF };
                            opt.len.set(min, max);
                        } else {
                            self.optimize_node_left(en.target.ok_or(ONIGERR_PARSER_BUG)?, opt, env)?;
                            if opt.anc.is_set(ANCHOR_ANYCHAR_STAR_MASK)
                                && bit_status_at(self.env.backrefed_mem, en.regnum)
                            {
                                opt.anc.remove(ANCHOR_ANYCHAR_STAR_MASK);
                            }
                        }
                    }
                    ENCLOSE_STOP_BACKTRACK | ENCLOSE_CONDITION => {
                        self.optimize_node_left(en.target.ok_or(ONIGERR_PARSER_BUG)?, opt, env)?;
                    }
                    ENCLOSE_ABSENT => opt.len.set(0, INF),
                    _ => {}
                }
            }
            _ => return Err(ONIGERR_TYPE_BUG),
        }
        Ok(())
    }

    /// set skip map for Sunday's quick search
    fn set_bm_skip(&mut self, s: &[u8], ignore_case: bool) -> R<usize> {
        let enc = self.enc;
        let mut end = s.len();
        // The skips, up to `end + 1`, are stored as bytes.
        if end >= usize::from(u8::MAX) {
            return Err(ONIGERR_TYPE_BUG);
        }
        let mut items = [CaseFoldCodeItem::default(); ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM];
        let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];

        if ignore_case {
            let mut i = 0;
            'outer: while i < end {
                let p = i;
                let n = enc.get_case_fold_codes_by_str(self.case_fold_flag, s, p, end, &mut items);
                let n = usize::try_from(n).map_err(|_| n)?;
                let clen = enc.enclen(s, p, end).min(end - p);
                for item in &items[..n] {
                    if item.code_len != 1 || usize::try_from(item.byte_len) != Ok(clen) {
                        /* Different length isn't supported. Stop optimization at here. */
                        end = p;
                        break 'outer;
                    }
                    let flen = enc.code_to_mbc(item.code[0], &mut buf);
                    if usize::try_from(flen) != Ok(clen) {
                        end = p;
                        break 'outer;
                    }
                }
                i += clen;
            }
        }
        let len = end;

        self.opt.map.fill((len + 1) as u8);
        let mut i = 0;
        while i < len {
            let p = i;
            let n = if ignore_case {
                let n = enc.get_case_fold_codes_by_str(self.case_fold_flag, s, p, end, &mut items);
                usize::try_from(n).map_err(|_| n)?
            } else {
                0
            };
            let clen = enc.enclen(s, p, end).min(end - p);
            for j in 0..clen {
                self.opt.map[s[i + j] as usize] = (len - i - j) as u8;
                for item in &items[..n] {
                    enc.code_to_mbc(item.code[0], &mut buf);
                    self.opt.map[buf[j] as usize] = (len - i - j) as u8;
                }
            }
            i += clen;
        }
        Ok(len)
    }

    fn set_optimize_exact_info(&mut self, e: &OptExactInfo) -> R<()> {
        let exact = e.bytes();
        if exact.is_empty() {
            return Ok(());
        }
        let allow_reverse = self.enc.is_allowed_reverse_match(exact, 0, exact.len());
        let mut exact_len = exact.len();

        if e.ignore_case > 0 {
            if e.len >= 3 || (e.len >= 2 && allow_reverse) {
                let len = self.set_bm_skip(exact, true)?;
                if len >= 3 {
                    exact_len = len;
                    self.opt.optimize =
                        if allow_reverse { ONIG_OPTIMIZE_EXACT_BM_IC } else { ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC };
                } else {
                    // Even if the BM skip table cannot be built (a pattern that
                    // starts with 's' or 'k', which have multi-byte case fold
                    // variants), EXACT_IC still applies. See [Bug #21824].
                    self.opt.optimize = ONIG_OPTIMIZE_EXACT_IC;
                }
            } else {
                self.opt.optimize = ONIG_OPTIMIZE_EXACT_IC;
            }
        } else if e.len >= 3 || (e.len >= 2 && allow_reverse) {
            self.set_bm_skip(exact, false)?;
            self.opt.optimize = if allow_reverse { ONIG_OPTIMIZE_EXACT_BM } else { ONIG_OPTIMIZE_EXACT_BM_NOT_REV };
        } else {
            self.opt.optimize = ONIG_OPTIMIZE_EXACT;
        }

        self.opt.dmin = e.mmd.min;
        self.opt.dmax = e.mmd.max;
        if self.opt.dmin != INF {
            self.opt.threshold_len = i32::try_from(self.opt.dmin.saturating_add(exact_len)).unwrap_or(i32::MAX);
        }
        self.opt.exact = exact[..exact_len].into();
        Ok(())
    }

    fn set_optimize_map_info(&mut self, m: &OptMapInfo) {
        self.opt.map = m.map;
        self.opt.optimize = ONIG_OPTIMIZE_MAP;
        self.opt.dmin = m.mmd.min;
        self.opt.dmax = m.mmd.max;
        if self.opt.dmin != INF {
            self.opt.threshold_len = i32::try_from(self.opt.dmin.saturating_add(1)).unwrap_or(i32::MAX);
        }
    }

    fn set_sub_anchor(&mut self, anc: &OptAncInfo) {
        self.opt.sub_anchor |= anc.left_anchor & ANCHOR_BEGIN_LINE;
        self.opt.sub_anchor |= anc.right_anchor & ANCHOR_END_LINE;
    }

    fn set_optimize_info_from_tree(&mut self, node: NodeId) -> R<()> {
        let mut env = OptEnv { mmd: MinMaxLen::default(), options: self.options };
        let mut opt = Box::new(NodeOptInfo::new());
        self.optimize_node_left(node, &mut opt, &mut env)?;

        self.opt.anchor = opt.anc.left_anchor
            & (ANCHOR_BEGIN_BUF
                | ANCHOR_BEGIN_POSITION
                | ANCHOR_ANYCHAR_STAR
                | ANCHOR_ANYCHAR_STAR_ML
                | ANCHOR_LOOK_BEHIND);
        if opt.anc.left_anchor & (ANCHOR_LOOK_BEHIND | ANCHOR_PREC_READ_NOT) != 0 {
            self.opt.anchor &= !ANCHOR_ANYCHAR_STAR_ML;
        }
        self.opt.anchor |= opt.anc.right_anchor & (ANCHOR_END_BUF | ANCHOR_SEMI_END_BUF | ANCHOR_PREC_READ_NOT);

        if self.opt.anchor & (ANCHOR_END_BUF | ANCHOR_SEMI_END_BUF) != 0 {
            self.opt.anchor_dmin = opt.len.min;
            self.opt.anchor_dmax = opt.len.max;
        }

        if opt.exb.len > 0 || opt.exm.len > 0 {
            let exm = opt.exm;
            opt.exb.select(&exm, self.enc);
            if opt.map.value > 0 && opt.exb.comp_with_map(&opt.map) > 0 {
                self.set_optimize_map_info(&opt.map);
                self.set_sub_anchor(&opt.map.anc);
            } else {
                self.set_optimize_exact_info(&opt.exb)?;
                self.set_sub_anchor(&opt.exb.anc);
            }
        } else if opt.map.value > 0 {
            self.set_optimize_map_info(&opt.map);
            self.set_sub_anchor(&opt.map.anc);
        } else {
            self.opt.sub_anchor |= opt.anc.left_anchor & ANCHOR_BEGIN_LINE;
            if opt.len.max == 0 {
                self.opt.sub_anchor |= opt.anc.right_anchor & ANCHOR_END_LINE;
            }
        }
        Ok(())
    }
}

// ---- optimizer data (regcomp.c 4294-4900) ----

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct MinMaxLen {
    /// min byte length
    min: usize,
    /// max byte length
    max: usize,
}

impl MinMaxLen {
    fn set(&mut self, min: usize, max: usize) {
        self.min = min;
        self.max = max;
    }
    fn add(&mut self, from: &MinMaxLen) {
        self.min = distance_add(self.min, from.min);
        self.max = distance_add(self.max, from.max);
    }
    fn alt_merge(&mut self, from: &MinMaxLen) {
        if self.min > from.min {
            self.min = from.min;
        }
        if self.max < from.max {
            self.max = from.max;
        }
    }
}

#[derive(Clone, Copy)]
struct OptEnv {
    mmd: MinMaxLen,
    options: u32,
}

#[derive(Clone, Copy, Debug, Default)]
struct OptAncInfo {
    left_anchor: i32,
    right_anchor: i32,
}

fn is_left_anchor(anc: i32) -> bool {
    !(anc == ANCHOR_END_BUF
        || anc == ANCHOR_SEMI_END_BUF
        || anc == ANCHOR_END_LINE
        || anc == ANCHOR_PREC_READ
        || anc == ANCHOR_PREC_READ_NOT)
}

impl OptAncInfo {
    fn concat(left: &OptAncInfo, right: &OptAncInfo, left_len: usize, right_len: usize) -> OptAncInfo {
        let mut to = OptAncInfo { left_anchor: left.left_anchor, right_anchor: right.right_anchor };
        if left_len == 0 {
            to.left_anchor |= right.left_anchor;
        }
        if right_len == 0 {
            to.right_anchor |= left.right_anchor;
        } else {
            to.right_anchor |= left.right_anchor & ANCHOR_PREC_READ_NOT;
        }
        to
    }
    fn is_set(&self, anc: i32) -> bool {
        (self.left_anchor & anc) != 0 || (self.right_anchor & anc) != 0
    }
    fn add(&mut self, anc: i32) {
        if is_left_anchor(anc) {
            self.left_anchor |= anc;
        } else {
            self.right_anchor |= anc;
        }
    }
    fn remove(&mut self, anc: i32) {
        if is_left_anchor(anc) {
            self.left_anchor &= !anc;
        } else {
            self.right_anchor &= !anc;
        }
    }
    fn alt_merge(&mut self, add: &OptAncInfo) {
        self.left_anchor &= add.left_anchor;
        self.right_anchor &= add.right_anchor;
    }
}

fn map_position_value(enc: Enc, i: usize) -> i32 {
    const BYTE_VAL_TABLE: [i16; 128] = [
        5, 1, 1, 1, 1, 1, 1, 1, 1, 10, 10, 1, 1, 10, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 12, 4, 7, 4,
        4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 7, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 6, 5, 5, 5, 5, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 1,
    ];
    if i < BYTE_VAL_TABLE.len() {
        if i == 0 && enc.min_len() > 1 { 20 } else { BYTE_VAL_TABLE[i] as i32 }
    } else {
        4 /* Take it easy. */
    }
}

fn distance_value(mm: &MinMaxLen) -> i32 {
    /* 1000 / (min-max-dist + 1) */
    const DIST_VALS: [i16; 100] = [
        1000, 500, 333, 250, 200, 167, 143, 125, 111, 100, 91, 83, 77, 71, 67, 63, 59, 56, 53, 50, 48, 45, 43, 42, 40,
        38, 37, 36, 34, 33, 32, 31, 30, 29, 29, 28, 27, 26, 26, 25, 24, 24, 23, 23, 22, 22, 21, 21, 20, 20, 20, 19, 19,
        19, 18, 18, 18, 17, 17, 17, 16, 16, 16, 16, 15, 15, 15, 15, 14, 14, 14, 14, 14, 14, 13, 13, 13, 13, 13, 13, 12,
        12, 12, 12, 12, 12, 11, 11, 11, 11, 11, 11, 11, 11, 11, 10, 10, 10, 10, 10,
    ];
    if mm.max == INF {
        return 0;
    }
    mm.max.checked_sub(mm.min).and_then(|d| DIST_VALS.get(d)).map_or(1, |&v| i32::from(v))
}

fn comp_distance_value(d1: &MinMaxLen, d2: &MinMaxLen, v1: i32, v2: i32) -> i32 {
    if v2 <= 0 {
        return -1;
    }
    if v1 <= 0 {
        return 1;
    }
    let v1 = v1 * distance_value(d1);
    let v2 = v2 * distance_value(d2);
    if v2 > v1 {
        return 1;
    }
    if v2 < v1 {
        return -1;
    }
    if d2.min < d1.min {
        return 1;
    }
    if d2.min > d1.min {
        return -1;
    }
    0
}

/// The cells of a list or an alternation. Most have a few, which are kept
/// inline rather than in a vector of their own.
struct Cells {
    inline: [NodeId; 8],
    len: usize,
    more: Vec<NodeId>,
}

impl Cells {
    fn push(&mut self, id: NodeId) {
        if self.more.is_empty() && self.len < self.inline.len() {
            self.inline[self.len] = id;
            self.len += 1;
        } else {
            if self.more.is_empty() {
                self.more.extend_from_slice(&self.inline[..self.len]);
            }
            self.more.push(id);
        }
    }
}

impl std::ops::Deref for Cells {
    type Target = [NodeId];

    fn deref(&self) -> &[NodeId] {
        if self.more.is_empty() { &self.inline[..self.len] } else { &self.more }
    }
}

impl<'a> IntoIterator for &'a Cells {
    type Item = &'a NodeId;
    type IntoIter = std::slice::Iter<'a, NodeId>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

impl IntoIterator for Cells {
    type Item = NodeId;
    type IntoIter = CellsIter;

    fn into_iter(self) -> CellsIter {
        CellsIter { cells: self, at: 0 }
    }
}

struct CellsIter {
    cells: Cells,
    at: usize,
}

impl Iterator for CellsIter {
    type Item = NodeId;

    fn next(&mut self) -> Option<NodeId> {
        let id = self.cells.get(self.at).copied();
        self.at += 1;
        id
    }
}

/// The runs of characters of the same length in the bytes of a string node,
/// as `(start, char_len, byte_len)`. With `ambig` the whole string is one run.
struct StringRuns<'a> {
    enc: Enc,
    s: &'a [u8],
    p: usize,
    ambig: bool,
}

impl<'a> StringRuns<'a> {
    fn new(enc: Enc, s: &'a [u8], ambig: bool) -> Self {
        StringRuns { enc, s, p: 0, ambig }
    }
}

impl Iterator for StringRuns<'_> {
    type Item = (usize, usize, usize);

    fn next(&mut self) -> Option<Self::Item> {
        let end = self.s.len();
        if self.p >= end {
            return None;
        }
        let start = self.p;
        let char_len = self.enc.enclen(self.s, start, end);
        let mut p = start + char_len;
        while p < end {
            let len = self.enc.enclen(self.s, p, end);
            if len != char_len && !self.ambig {
                break;
            }
            p += len;
        }
        self.p = p;
        Some((start, char_len, p - start))
    }
}

#[derive(Clone, Copy, Debug)]
struct OptExactInfo {
    /// info position
    mmd: MinMaxLen,
    anc: OptAncInfo,
    reach_end: bool,
    /// -1: unset, 0: case sensitive, 1: ignore case
    ignore_case: i32,
    /// Length of the string in `s`.
    len: i32,
    s: [u8; OPT_EXACT_MAXLEN],
}

impl OptExactInfo {
    fn new() -> Self {
        OptExactInfo {
            mmd: MinMaxLen::default(),
            anc: OptAncInfo::default(),
            reach_end: false,
            ignore_case: -1,
            len: 0,
            s: [0; OPT_EXACT_MAXLEN],
        }
    }

    fn clear(&mut self) {
        *self = OptExactInfo::new();
    }

    fn bytes(&self) -> &[u8] {
        &self.s[..usize::try_from(self.len).unwrap_or(0)]
    }

    fn is_full(&self) -> bool {
        self.len >= OPT_EXACT_MAXLEN as i32
    }

    fn concat(&mut self, add: &OptExactInfo, enc: Enc) {
        if self.ignore_case < 0 {
            self.ignore_case = add.ignore_case;
        } else if self.ignore_case != add.ignore_case {
            return; /* avoid */
        }
        let src = add.bytes();
        let end = src.len();
        let mut p = 0;
        let mut i = self.bytes().len();
        while p < end {
            let len = enc.enclen(src, p, end);
            if i + len > OPT_EXACT_MAXLEN {
                break;
            }
            let mut j = 0;
            while j < len && p < end {
                self.s[i] = src[p];
                i += 1;
                p += 1;
                j += 1;
            }
        }
        self.len = i as i32;
        self.reach_end = if p == end { add.reach_end } else { false };

        let mut tanc = OptAncInfo::concat(&self.anc, &add.anc, 1, 1);
        if !self.reach_end {
            tanc.right_anchor = 0;
        }
        self.anc = tanc;
    }

    fn concat_str(&mut self, s: &[u8], enc: Enc) {
        let end = s.len();
        let mut i = self.bytes().len();
        let mut p = 0;
        while p < end && i < OPT_EXACT_MAXLEN {
            let len = enc.enclen(s, p, end);
            if i + len > OPT_EXACT_MAXLEN {
                break;
            }
            let mut j = 0;
            while j < len && p < end {
                self.s[i] = s[p];
                i += 1;
                p += 1;
                j += 1;
            }
        }
        self.len = i as i32;
    }

    fn alt_merge(&mut self, add: &OptExactInfo, enc: Enc) {
        if add.len == 0 || self.len == 0 {
            self.clear();
            return;
        }
        if self.mmd != add.mmd {
            self.clear();
            return;
        }

        let (to_len, add_len) = (self.bytes().len(), add.bytes().len());
        let mut i = 0;
        while i < to_len && i < add_len {
            let len = enc.enclen(&self.s[..to_len], i, to_len);
            // Bytes past `add.len` count too: a length cut by `concat_left`
            // inside a character leaves the rest of it in `add.s`.
            if self.s[i..i + len] != add.s[i..i + len] {
                break;
            }
            i += len;
        }

        if !add.reach_end || i < add_len || i < to_len {
            self.reach_end = false;
        }
        self.len = i as i32;
        if self.ignore_case < 0 {
            self.ignore_case = add.ignore_case;
        } else if add.ignore_case >= 0 {
            self.ignore_case |= add.ignore_case;
        }

        self.anc.alt_merge(&add.anc);
        if !self.reach_end {
            self.anc.right_anchor = 0;
        }
    }

    /// `select_opt_exact_info(enc, self, alt)`
    fn select(&mut self, alt: &OptExactInfo, enc: Enc) {
        let mut v1 = self.len;
        let mut v2 = alt.len;
        if v2 == 0 {
            return;
        } else if v1 == 0 {
            *self = *alt;
            return;
        } else if v1 <= 2 && v2 <= 2 {
            /* ByteValTable[x] is big value --> low price */
            v2 = map_position_value(enc, self.s[0] as usize);
            v1 = map_position_value(enc, alt.s[0] as usize);
            if self.len > 1 {
                v1 += 5;
            }
            if alt.len > 1 {
                v2 += 5;
            }
        }
        if self.ignore_case <= 0 {
            v1 *= 2;
        }
        if alt.ignore_case <= 0 {
            v2 *= 2;
        }
        if comp_distance_value(&self.mmd, &alt.mmd, v1, v2) > 0 {
            *self = *alt;
        }
    }

    /// `comp_opt_exact_or_map_info`
    fn comp_with_map(&self, m: &OptMapInfo) -> i32 {
        const COMP_EM_BASE: i32 = 20;
        if m.value <= 0 {
            return -1;
        }
        let ve = COMP_EM_BASE * self.len * if self.ignore_case > 0 { 1 } else { 2 };
        let vm = COMP_EM_BASE * 5 * 2 / m.value;
        comp_distance_value(&self.mmd, &m.mmd, ve, vm)
    }
}

#[derive(Clone, Debug)]
struct OptMapInfo {
    /// info position
    mmd: MinMaxLen,
    anc: OptAncInfo,
    /// weighted value
    value: i32,
    map: [u8; ONIG_CHAR_TABLE_SIZE],
}

impl OptMapInfo {
    fn new() -> Self {
        OptMapInfo { mmd: MinMaxLen::default(), anc: OptAncInfo::default(), value: 0, map: [0; ONIG_CHAR_TABLE_SIZE] }
    }

    fn add_char(&mut self, c: u8, enc: Enc) {
        if self.map[c as usize] == 0 {
            self.map[c as usize] = 1;
            self.value += map_position_value(enc, c as usize);
        }
    }

    fn add_char_amb(&mut self, s: &[u8], enc: Enc, case_fold_flag: u32) -> R<()> {
        let mut items = [CaseFoldCodeItem::default(); ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM];
        let mut buf = [0u8; ONIGENC_CODE_TO_MBC_MAXLEN];
        self.add_char(s[0], enc);
        let flag = case_fold_flag & !INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR;
        let n = enc.get_case_fold_codes_by_str(flag, s, 0, s.len(), &mut items);
        let n = usize::try_from(n).map_err(|_| n)?;
        for item in &items[..n] {
            enc.code_to_mbc(item.code[0], &mut buf);
            self.add_char(buf[0], enc);
        }
        Ok(())
    }

    /// `select_opt_map_info(self, alt)`
    fn select(&mut self, alt: &OptMapInfo) {
        const Z: i32 = 1 << 15; /* 32768: something big value */
        if alt.value == 0 {
            return;
        }
        if self.value == 0 {
            *self = alt.clone();
            return;
        }
        let v1 = Z / self.value;
        let v2 = Z / alt.value;
        if comp_distance_value(&self.mmd, &alt.mmd, v1, v2) > 0 {
            *self = alt.clone();
        }
    }

    fn alt_merge(&mut self, add: &OptMapInfo, enc: Enc) {
        /* if (! is_equal_mml(&to->mmd, &add->mmd)) return ; */
        if self.value == 0 {
            return;
        }
        if add.value == 0 || self.mmd.max < add.mmd.min {
            *self = OptMapInfo::new();
            return;
        }
        self.mmd.alt_merge(&add.mmd);
        let mut val = 0;
        for i in 0..ONIG_CHAR_TABLE_SIZE {
            if add.map[i] != 0 {
                self.map[i] = 1;
            }
            if self.map[i] != 0 {
                val += map_position_value(enc, i);
            }
        }
        self.value = val;
        self.anc.alt_merge(&add.anc);
    }
}

#[derive(Clone, Debug)]
struct NodeOptInfo {
    len: MinMaxLen,
    anc: OptAncInfo,
    /// boundary
    exb: OptExactInfo,
    /// middle
    exm: OptExactInfo,
    /// prec read (?=...)
    expr: OptExactInfo,
    /// boundary
    map: OptMapInfo,
}

impl NodeOptInfo {
    fn new() -> Self {
        NodeOptInfo {
            len: MinMaxLen::default(),
            anc: OptAncInfo::default(),
            exb: OptExactInfo::new(),
            exm: OptExactInfo::new(),
            expr: OptExactInfo::new(),
            map: OptMapInfo::new(),
        }
    }

    fn clear(&mut self) {
        self.len = MinMaxLen::default();
        self.anc = OptAncInfo::default();
        self.exb.clear();
        self.exm.clear();
        self.expr.clear();
        self.map = OptMapInfo::new();
    }

    fn set_bound(&mut self, mmd: &MinMaxLen) {
        self.exb.mmd = *mmd;
        self.expr.mmd = *mmd;
        self.map.mmd = *mmd;
    }

    /// `concat_left_node_opt_info(enc, self, add)`
    fn concat_left(&mut self, enc: Enc, add: &mut NodeOptInfo) {
        self.anc = OptAncInfo::concat(&self.anc, &add.anc, self.len.max, add.len.max);

        if add.exb.len > 0 && self.len.max == 0 {
            add.exb.anc = OptAncInfo::concat(&self.anc, &add.exb.anc, self.len.max, add.len.max);
        }

        if add.map.value > 0 && self.len.max == 0 && add.map.mmd.max == 0 {
            add.map.anc.left_anchor |= self.anc.left_anchor;
        }

        let exb_reach = self.exb.reach_end;
        let exm_reach = self.exm.reach_end;

        if add.len.max != 0 {
            self.exb.reach_end = false;
            self.exm.reach_end = false;
        }

        if add.exb.len > 0 {
            if exb_reach {
                self.exb.concat(&add.exb, enc);
                add.exb.clear();
            } else if exm_reach {
                self.exm.concat(&add.exb, enc);
                add.exb.clear();
            }
        }
        self.exm.select(&add.exb, enc);
        self.exm.select(&add.exm, enc);

        if self.expr.len > 0 {
            if add.len.max > 0 {
                if self.expr.len as usize > add.len.max {
                    self.expr.len = add.len.max as i32;
                }
                let expr = self.expr;
                if self.expr.mmd.max == 0 {
                    self.exb.select(&expr, enc);
                } else {
                    self.exm.select(&expr, enc);
                }
            }
        } else if add.expr.len > 0 {
            self.expr = add.expr;
        }

        self.map.select(&add.map);
        self.len.add(&add.len);
    }

    fn alt_merge(&mut self, add: &NodeOptInfo, enc: Enc) {
        self.anc.alt_merge(&add.anc);
        self.exb.alt_merge(&add.exb, enc);
        self.exm.alt_merge(&add.exm, enc);
        self.expr.alt_merge(&add.expr, enc);
        self.map.alt_merge(&add.map, enc);
        self.len.alt_merge(&add.len);
    }
}
