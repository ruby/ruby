// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{
    cruby::*, get_option, hir_type::types::Fixnum, options::DumpHIR, profile::get_or_create_iseq_payload
};
use std::collections::{HashMap, HashSet};

use crate::hir_type::Type;

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(pub usize);

impl Into<usize> for InsnId {
    fn into(self) -> usize {
        self.0
    }
}

impl std::fmt::Display for InsnId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "v{}", self.0)
    }
}

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(usize);

impl std::fmt::Display for BlockId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "bb{}", self.0)
    }
}

fn write_vec<T: std::fmt::Display>(f: &mut std::fmt::Formatter, objs: &Vec<T>) -> std::fmt::Result {
    write!(f, "[")?;
    let mut prefix = "";
    for obj in objs {
        write!(f, "{prefix}{obj}")?;
        prefix = ", ";
    }
    write!(f, "]")
}

impl std::fmt::Display for VALUE {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            val if val.fixnum_p() => write!(f, "{}", val.as_fixnum()),
            &Qnil => write!(f, "nil"),
            &Qtrue => write!(f, "true"),
            &Qfalse => write!(f, "false"),
            val => write!(f, "VALUE({:#X?})", val.as_ptr::<u8>()),
        }
    }
}

#[derive(Debug, PartialEq, Clone)]
pub struct BranchEdge {
    target: BlockId,
    args: Vec<InsnId>,
}

impl std::fmt::Display for BranchEdge {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}(", self.target)?;
        let mut prefix = "";
        for arg in &self.args {
            write!(f, "{prefix}{arg}")?;
            prefix = ", ";
        }
        write!(f, ")")
    }
}

#[derive(Debug, PartialEq, Clone)]
pub struct CallInfo {
    name: String,
}

/// Invalidation reasons
#[derive(Debug, Clone)]
pub enum Invariant {
    /// Basic operation is redefined
    BOPRedefined {
        /// {klass}_REDEFINED_OP_FLAG
        klass: RedefinitionFlag,
        /// BOP_{bop}
        bop: ruby_basic_operators,
    },
}

impl std::fmt::Display for Invariant {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Self::BOPRedefined { klass, bop } => {
                write!(f, "BOPRedefined(")?;
                match *klass {
                    INTEGER_REDEFINED_OP_FLAG => write!(f, "INTEGER_REDEFINED_OP_FLAG")?,
                    _ => write!(f, "{klass}")?,
                }
                write!(f, ", ")?;
                match *bop {
                    BOP_PLUS  => write!(f, "BOP_PLUS")?,
                    BOP_MINUS => write!(f, "BOP_MINUS")?,
                    BOP_MULT  => write!(f, "BOP_MULT")?,
                    BOP_DIV   => write!(f, "BOP_DIV")?,
                    BOP_MOD   => write!(f, "BOP_MOD")?,
                    BOP_EQ    => write!(f, "BOP_EQ")?,
                    BOP_NEQ   => write!(f, "BOP_NEQ")?,
                    BOP_LT    => write!(f, "BOP_LT")?,
                    BOP_LE    => write!(f, "BOP_LE")?,
                    BOP_GT    => write!(f, "BOP_GT")?,
                    BOP_GE    => write!(f, "BOP_GE")?,
                    _ => write!(f, "{bop}")?,
                }
                write!(f, ")")
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Const {
    Value(VALUE),
    CInt8(i8),
    CInt16(i16),
    CInt32(i32),
    CInt64(i64),
    CUInt8(u8),
    CUInt16(u16),
    CUInt32(u32),
    CUInt64(u64),
    CPtr(*mut u8),
    CDouble(f64),
}

impl std::fmt::Display for Const {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Const::Value(val) => write!(f, "Value({val})"),
            _ => write!(f, "{self:?}"),
        }
    }
}

#[derive(Debug, Clone)]
pub enum Insn {
    PutSelf,
    Const { val: Const },
    // SSA block parameter. Also used for function parameters in the function's entry block.
    Param { idx: usize },

    StringCopy { val: InsnId },
    StringIntern { val: InsnId },

    NewArray { count: usize },
    ArraySet { idx: usize, val: InsnId },
    ArrayDup { val: InsnId },

    // Check if the value is truthy and "return" a C boolean. In reality, we will likely fuse this
    // with IfTrue/IfFalse in the backend to generate jcc.
    Test { val: InsnId },
    Defined { op_type: usize, obj: VALUE, pushval: VALUE, v: InsnId },
    GetConstantPath { ic: *const u8 },

    //NewObject?
    //SetIvar {},
    //GetIvar {},

    // Own a FrameStateId so that instructions can look up their dominating FrameStateId when
    // generating deopt side-exits and frame reconstruction metadata. Does not directly generate
    // any code.
    Snapshot { state: FrameStateId },

    // Unconditional jump
    Jump(BranchEdge),

    // Conditional branch instructions
    IfTrue { val: InsnId, target: BranchEdge },
    IfFalse { val: InsnId, target: BranchEdge },

    // Call a C function
    // NOTE: should we store the C function name for pretty-printing?
    //       or can we backtranslate the function pointer into a name string?
    CCall { cfun: *const u8, args: Vec<InsnId> },

    // Send with dynamic dispatch
    // Ignoring keyword arguments etc for now
    Send { self_val: InsnId, call_info: CallInfo, args: Vec<InsnId> },

    // Control flow instructions
    Return { val: InsnId },

    /// Fixnum +, -, *, /, %, ==, !=, <, <=, >, >=
    FixnumAdd  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumSub  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumMult { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumDiv  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumMod  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumEq   { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumNeq  { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumLt   { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumLe   { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumGt   { left: InsnId, right: InsnId, state: FrameStateId },
    FixnumGe   { left: InsnId, right: InsnId, state: FrameStateId },

    /// Side-exist if val doesn't have the expected type.
    // TODO: Replace is_fixnum with the type lattice
    GuardType { val: InsnId, guard_type: Type, state: FrameStateId },

    /// Generate no code (or padding if necessary) and insert a patch point
    /// that can be rewritten to a side exit when the Invariant is broken.
    PatchPoint(Invariant),
}

#[derive(Default, Debug)]
pub struct Block {
    params: Vec<InsnId>,
    insns: Vec<InsnId>,
}

impl Block {
}

struct FunctionPrinter<'a> {
    fun: &'a Function,
    display_snapshot: bool,
}

impl<'a> FunctionPrinter<'a> {
    fn without_snapshot(fun: &'a Function) -> FunctionPrinter<'a> {
        FunctionPrinter { fun, display_snapshot: false }
    }

    fn with_snapshot(fun: &'a Function) -> FunctionPrinter<'a> {
        FunctionPrinter { fun, display_snapshot: true }
    }
}

/// Union-Find (Disjoint-Set) is a data structure for managing disjoint sets that has an interface
/// of two operations:
///
/// * find (what set is this item part of?)
/// * union (join these two sets)
///
/// Union-Find identifies sets by their *representative*, which is some chosen element of the set.
/// This is implemented by structuring each set as its own graph component with the representative
/// pointing at nothing. For example:
///
/// * A -> B -> C
/// * D -> E
///
/// This represents two sets `C` and `E`, with three and two members, respectively. In this
/// example, `find(A)=C`, `find(C)=C`, `find(D)=E`, and so on.
///
/// To union sets, call `make_equal_to` on any set element. That is, `make_equal_to(A, D)` and
/// `make_equal_to(B, E)` have the same result: the two sets are joined into the same graph
/// component. After this operation, calling `find` on any element will return `E`.
///
/// This is a useful data structure in compilers because it allows in-place rewriting without
/// linking/unlinking instructions and without replacing all uses. When calling `make_equal_to` on
/// any instruction, all of its uses now implicitly point to the replacement.
///
/// This does mean that pattern matching and analysis of the instruction graph must be careful to
/// call `find` whenever it is inspecting an instruction (or its operands). If not, this may result
/// in missing optimizations.
#[derive(Debug)]
struct UnionFind<T: Copy + Into<usize>> {
    forwarded: Vec<Option<T>>,
}

impl<T: Copy + Into<usize> + PartialEq> UnionFind<T> {
    fn new() -> UnionFind<T> {
        UnionFind { forwarded: vec![] }
    }

    /// Private. Return the internal representation of the forwarding pointer for a given element.
    fn at(&self, idx: T) -> Option<T> {
        self.forwarded.get(idx.into()).map(|x| *x).flatten()
    }

    /// Private. Set the internal representation of the forwarding pointer for the given element
    /// `idx`. Extend the internal vector if necessary.
    fn set(&mut self, idx: T, value: T) {
        if idx.into() >= self.forwarded.len() {
            self.forwarded.resize(idx.into()+1, None);
        }
        self.forwarded[idx.into()] = Some(value);
    }

    /// Find the set representative for `insn`. Perform path compression at the same time to speed
    /// up further find operations. For example, before:
    ///
    /// `A -> B -> C`
    ///
    /// and after `find(A)`:
    ///
    /// ```
    /// A -> C
    /// B ---^
    /// ```
    pub fn find(&mut self, insn: T) -> T {
        let result = self.find_const(insn);
        if result != insn {
            // Path compression
            self.set(insn, result);
        }
        result
    }

    /// Find the set representative for `insn` without doing path compression.
    pub fn find_const(&self, insn: T) -> T {
        let mut result = insn;
        loop {
            match self.at(result) {
                None => return result,
                Some(insn) => result = insn,
            }
        }
    }

    /// Union the two sets containing `insn` and `target` such that every element in `insn`s set is
    /// now part of `target`'s. Neither argument must be the representative in its set.
    pub fn make_equal_to(&mut self, insn: T, target: T) {
        let found = self.find(insn);
        self.set(found, target);
    }
}

#[derive(Debug)]
pub struct Function {
    // ISEQ this function refers to
    iseq: *const rb_iseq_t,

    // TODO: get method name and source location from the ISEQ

    pub insns: Vec<Insn>,
    union_find: UnionFind<InsnId>,
    blocks: Vec<Block>,
    entry_block: BlockId,
    frame_states: Vec<FrameState>,
}

impl Function {
    fn new(iseq: *const rb_iseq_t) -> Function {
        Function {
            iseq,
            insns: vec![],
            union_find: UnionFind::new(),
            blocks: vec![Block::default()],
            entry_block: BlockId(0),
            frame_states: vec![],
        }
    }

    // Add an instruction to an SSA block
    fn push_insn(&mut self, block: BlockId, insn: Insn) -> InsnId {
        let id = InsnId(self.insns.len());
        if let Insn::Param { .. } = &insn {
            self.blocks[block.0].params.push(id);
        } else {
            self.blocks[block.0].insns.push(id);
        }
        self.insns.push(insn);
        id
    }

    /// Store the given FrameState on the Function so that it can be cheaply referenced by
    /// instructions.
    fn push_frame_state(&mut self, state: FrameState) -> FrameStateId {
        let id = FrameStateId(self.frame_states.len());
        self.frame_states.push(state);
        id
    }

    /// Return a reference to the FrameState at the given index.
    pub fn frame_state(&self, id: FrameStateId) -> &FrameState {
        &self.frame_states[id.0]
    }

    fn new_block(&mut self) -> BlockId {
        let id = BlockId(self.blocks.len());
        self.blocks.push(Block::default());
        id
    }

    /// Use for pattern matching over instructions in a union-find-safe way. For example:
    /// ```rust
    /// match func.find(insn_id) {
    ///   IfTrue { val, target } if func.is_truthy(val) => {
    ///     func.make_equal_to(insn_id, block, Insn::Jump(target));
    ///   }
    ///   _ => {}
    /// }
    /// ```
    fn find(&mut self, insn_id: InsnId) -> Insn {
        let insn_id = self.union_find.find(insn_id);
        use Insn::*;
        match &self.insns[insn_id.0] {
            result@(PutSelf | Const {..} | Param {..} | NewArray {..} | GetConstantPath {..}) => result.clone(),
            StringCopy { val } => StringCopy { val: self.union_find.find(*val) },
            StringIntern { val } => StringIntern { val: self.union_find.find(*val) },
            Test { val } => Test { val: self.union_find.find(*val) },
            insn => todo!("find({insn:?})"),
        }
    }

    /// Replace `insn` with the new instruction `replacement`, which will get appended to `insns`.
    fn make_equal_to(&mut self, insn: InsnId, block: BlockId, replacement: Insn) {
        let new_insn = self.push_insn(block, replacement);
        self.union_find.make_equal_to(insn, new_insn);
    }
}

impl<'a> std::fmt::Display for FunctionPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let fun = &self.fun;
        for (block_id, block) in fun.blocks.iter().enumerate() {
            let block_id = BlockId(block_id);
            write!(f, "{block_id}(")?;
            if !block.params.is_empty() {
                let mut sep = "";
                for param in &block.params {
                    write!(f, "{sep}{param}")?;
                    sep = ", ";
                }
            }
            writeln!(f, "):")?;
            for insn_id in &block.insns {
                if !self.display_snapshot && matches!(fun.insns[insn_id.0], Insn::Snapshot {..}) {
                    continue;
                }
                write!(f, "  {insn_id} = ")?;
                match &fun.insns[insn_id.0] {
                    Insn::Const { val } => { write!(f, "Const {val}")?; }
                    Insn::Param { idx } => { write!(f, "Param {idx}")?; }
                    Insn::NewArray { count } => { write!(f, "NewArray {count}")?; }
                    Insn::ArraySet { idx, val } => { write!(f, "ArraySet {idx}, {val}")?; }
                    Insn::ArrayDup { val } => { write!(f, "ArrayDup {val}")?; }
                    Insn::Test { val } => { write!(f, "Test {val}")?; }
                    Insn::Snapshot { state } => { write!(f, "Snapshot {}", fun.frame_state(*state))?; }
                    Insn::Jump(target) => { write!(f, "Jump {target}")?; }
                    Insn::IfTrue { val, target } => { write!(f, "IfTrue {val}, {target}")?; }
                    Insn::IfFalse { val, target } => { write!(f, "IfFalse {val}, {target}")?; }
                    Insn::Send { self_val, call_info, args } => {
                        write!(f, "Send {self_val}, :{}", call_info.name)?;
                        for arg in args {
                            write!(f, ", {arg}")?;
                        }
                    }
                    Insn::Return { val } => { write!(f, "Return {val}")?; }
                    Insn::FixnumAdd  { left, right, .. } => { write!(f, "FixnumAdd {left}, {right}")?; },
                    Insn::FixnumSub  { left, right, .. } => { write!(f, "FixnumSub {left}, {right}")?; },
                    Insn::FixnumMult { left, right, .. } => { write!(f, "FixnumMult {left}, {right}")?; },
                    Insn::FixnumDiv  { left, right, .. } => { write!(f, "FixnumDiv {left}, {right}")?; },
                    Insn::FixnumMod  { left, right, .. } => { write!(f, "FixnumMod {left}, {right}")?; },
                    Insn::FixnumEq   { left, right, .. } => { write!(f, "FixnumEq {left}, {right}")?; },
                    Insn::FixnumNeq  { left, right, .. } => { write!(f, "FixnumNeq {left}, {right}")?; },
                    Insn::FixnumLt   { left, right, .. } => { write!(f, "FixnumLt {left}, {right}")?; },
                    Insn::FixnumLe   { left, right, .. } => { write!(f, "FixnumLe {left}, {right}")?; },
                    Insn::FixnumGt   { left, right, .. } => { write!(f, "FixnumGt {left}, {right}")?; },
                    Insn::FixnumGe   { left, right, .. } => { write!(f, "FixnumGe {left}, {right}")?; },
                    Insn::GuardType { val, guard_type, .. } => { write!(f, "GuardType {val}, {guard_type}")?; },
                    Insn::PatchPoint(invariant) => { write!(f, "PatchPoint {invariant:}")?; },
                    insn => { write!(f, "{insn:?}")?; }
                }
                writeln!(f, "")?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct FrameState {
    iseq: IseqPtr,
    // Ruby bytecode instruction pointer
    pub pc: VALUE,

    stack: Vec<InsnId>,
    locals: Vec<InsnId>,
}

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct FrameStateId(pub usize);

/// Compute the index of a local variable from its slot index
fn ep_offset_to_local_idx(iseq: IseqPtr, ep_offset: u32) -> usize {
    // Layout illustration
    // This is an array of VALUE
    //                                           | VM_ENV_DATA_SIZE |
    //                                           v                  v
    // low addr <+-------+-------+-------+-------+------------------+
    //           |local 0|local 1|  ...  |local n|       ....       |
    //           +-------+-------+-------+-------+------------------+
    //           ^       ^                       ^                  ^
    //           +-------+---local_table_size----+         cfp->ep--+
    //                   |                                          |
    //                   +------------------ep_offset---------------+
    //
    // See usages of local_var_name() from iseq.c for similar calculation.

    // Equivalent of iseq->body->local_table_size
    let local_table_size: i32 = unsafe { get_iseq_body_local_table_size(iseq) }
        .try_into()
        .unwrap();
    let op = (ep_offset - VM_ENV_DATA_SIZE) as i32;
    let local_idx = local_table_size - op - 1;
    assert!(local_idx >= 0 && local_idx < local_table_size);
    local_idx.try_into().unwrap()
}

impl FrameState {
    fn new(iseq: IseqPtr) -> FrameState {
        FrameState { iseq, pc: VALUE(0), stack: vec![], locals: vec![] }
    }

    fn push(&mut self, opnd: InsnId) {
        self.stack.push(opnd);
    }

    fn top(&self) -> Result<InsnId, ParseError> {
        self.stack.last().ok_or_else(|| ParseError::StackUnderflow(self.clone())).copied()
    }

    fn stack_opnd(&self, idx: usize) -> Result<InsnId, ParseError> {
        match self.stack.get(self.stack.len() - idx - 1) {
            Some(&opnd) => Ok(opnd),
            _ => Err(ParseError::StackUnderflow(self.clone())),
        }
    }

    fn pop(&mut self) -> Result<InsnId, ParseError> {
        self.stack.pop().ok_or_else(|| ParseError::StackUnderflow(self.clone()))
    }

    fn setn(&mut self, n: usize, opnd: InsnId) {
        let idx = self.stack.len() - n - 1;
        self.stack[idx] = opnd;
    }

    fn setlocal(&mut self, ep_offset: u32, opnd: InsnId) {
        let idx = ep_offset_to_local_idx(self.iseq, ep_offset);
        self.locals[idx] = opnd;
    }

    fn getlocal(&mut self, ep_offset: u32) -> InsnId {
        let idx = ep_offset_to_local_idx(self.iseq, ep_offset);
        self.locals[idx]
    }

    fn as_args(&self) -> Vec<InsnId> {
        self.locals.iter().chain(self.stack.iter()).map(|op| op.clone()).collect()
    }
}

impl std::fmt::Display for FrameState {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "FrameState {{ pc: {:?}, stack: ", self.pc.as_ptr::<u8>())?;
        write_vec(f, &self.stack)?;
        write!(f, ", locals: ")?;
        write_vec(f, &self.locals)?;
        write!(f, " }}")
    }
}

/// Get YARV instruction argument
fn get_arg(pc: *const VALUE, arg_idx: isize) -> VALUE {
    unsafe { *(pc.offset(arg_idx + 1)) }
}

/// Compute YARV instruction index at relative offset
fn insn_idx_at_offset(idx: u32, offset: i64) -> u32 {
    ((idx as isize) + (offset as isize)) as u32
}

fn compute_jump_targets(iseq: *const rb_iseq_t) -> Vec<u32> {
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx = 0;
    let mut jump_targets = HashSet::new();
    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };

        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();
        insn_idx += insn_len(opcode as usize);
        match opcode {
            YARVINSN_branchunless | YARVINSN_jump | YARVINSN_branchif | YARVINSN_branchnil => {
                let offset = get_arg(pc, 0).as_i64();
                jump_targets.insert(insn_idx_at_offset(insn_idx, offset));
            }
            YARVINSN_leave | YARVINSN_opt_invokebuiltin_delegate_leave => {
                if insn_idx < iseq_size {
                    jump_targets.insert(insn_idx);
                }
            }
            _ => {}
        }
    }
    let mut result = jump_targets.into_iter().collect::<Vec<_>>();
    result.sort();
    result
}

#[derive(Debug)]
pub enum ParseError {
    StackUnderflow(FrameState),
    UnknownOpcode(String),
}

fn num_lead_params(iseq: *const rb_iseq_t) -> usize {
    let result = unsafe { rb_get_iseq_body_param_lead_num(iseq) };
    assert!(result >= 0, "Can't have negative # of parameters");
    result as usize
}

/// Return the number of locals in the current ISEQ (includes parameters)
fn num_locals(iseq: *const rb_iseq_t) -> usize {
    (unsafe { get_iseq_body_local_table_size(iseq) }) as usize
}

/// Compile ISEQ into High-level IR
pub fn iseq_to_hir(iseq: *const rb_iseq_t) -> Result<Function, ParseError> {
    let mut fun = Function::new(iseq);
    // Compute a map of PC->Block by finding jump targets
    let jump_targets = compute_jump_targets(iseq);
    let mut insn_idx_to_block = HashMap::new();
    for insn_idx in jump_targets {
        if insn_idx == 0 {
            todo!("Separate entry block for param/self/...");
        }
        insn_idx_to_block.insert(insn_idx, fun.new_block());
    }

    // Iteratively fill out basic blocks using a queue
    // TODO(max): Basic block arguments at edges
    let mut queue = std::collections::VecDeque::new();
    let mut entry_state = FrameState::new(iseq);
    for idx in 0..num_locals(iseq) {
        if idx < num_lead_params(iseq) {
            entry_state.locals.push(fun.push_insn(fun.entry_block, Insn::Param { idx }));
        } else {
            entry_state.locals.push(fun.push_insn(fun.entry_block, Insn::Const { val: Const::Value(Qnil) }));
        }
    }
    queue.push_back((entry_state, fun.entry_block, /*insn_idx=*/0 as u32));

    let mut visited = HashSet::new();

    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let payload = get_or_create_iseq_payload(iseq);
    while let Some((incoming_state, block, mut insn_idx)) = queue.pop_front() {
        if visited.contains(&block) { continue; }
        visited.insert(block);
        let mut state = if insn_idx == 0 { incoming_state.clone() } else {
            let mut result = FrameState::new(iseq);
            let mut idx = 0;
            for _ in 0..incoming_state.locals.len() {
                result.locals.push(fun.push_insn(block, Insn::Param { idx }));
                idx += 1;
            }
            for _ in incoming_state.stack {
                result.stack.push(fun.push_insn(block, Insn::Param { idx }));
                idx += 1;
            }
            result
        };
        while insn_idx < iseq_size {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
            state.pc = unsafe { *pc };
            let exit_state = fun.push_frame_state(state.clone());
            fun.push_insn(block, Insn::Snapshot { state: exit_state });

            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();
            // Preserve the actual index for the instruction being compiled
            let current_insn_idx = insn_idx;
            // Move to the next instruction to compile
            insn_idx += insn_len(opcode as usize);

            match opcode {
                YARVINSN_nop => {},
                YARVINSN_putnil => { state.push(fun.push_insn(block, Insn::Const { val: Const::Value(Qnil) })); },
                YARVINSN_putobject => { state.push(fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) })); },
                YARVINSN_putstring | YARVINSN_putchilledstring => {
                    // TODO(max): Do something different for chilled string
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::StringCopy { val });
                    state.push(insn_id);
                }
                YARVINSN_putself => { state.push(fun.push_insn(block, Insn::PutSelf)); }
                YARVINSN_intern => {
                    let val = state.pop()?;
                    let insn_id = fun.push_insn(block, Insn::StringIntern { val });
                    state.push(insn_id);
                }
                YARVINSN_newarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let insn_id = fun.push_insn(block, Insn::NewArray { count });
                    for idx in (0..count).rev() {
                        fun.push_insn(block, Insn::ArraySet { idx, val: state.pop()? });
                    }
                    state.push(insn_id);
                }
                YARVINSN_duparray => {
                    let val = fun.push_insn(block, Insn::Const { val: Const::Value(get_arg(pc, 0)) });
                    let insn_id = fun.push_insn(block, Insn::ArrayDup { val });
                    state.push(insn_id);
                }
                YARVINSN_putobject_INT2FIX_0_ => {
                    state.push(fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(0)) }));
                }
                YARVINSN_putobject_INT2FIX_1_ => {
                    state.push(fun.push_insn(block, Insn::Const { val: Const::Value(VALUE::fixnum_from_usize(1)) }));
                }
                YARVINSN_defined => {
                    let op_type = get_arg(pc, 0).as_usize();
                    let obj = get_arg(pc, 0);
                    let pushval = get_arg(pc, 0);
                    let v = state.pop()?;
                    state.push(fun.push_insn(block, Insn::Defined { op_type, obj, pushval, v }));
                }
                YARVINSN_opt_getconstant_path => {
                    let ic = get_arg(pc, 0).as_ptr::<u8>();
                    state.push(fun.push_insn(block, Insn::GetConstantPath { ic }));
                }
                YARVINSN_branchunless => {
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.pop()?;
                    let test_id = fun.push_insn(block, Insn::Test { val });
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    // TODO(max): Merge locals/stack for bb arguments
                    let _branch_id = fun.push_insn(block, Insn::IfFalse {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args() }
                    });
                    queue.push_back((state.clone(), target, target_idx));
                }
                YARVINSN_branchif => {
                    let offset = get_arg(pc, 0).as_i64();
                    let val = state.pop()?;
                    let test_id = fun.push_insn(block, Insn::Test { val });
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    // TODO(max): Merge locals/stack for bb arguments
                    let _branch_id = fun.push_insn(block, Insn::IfTrue {
                        val: test_id,
                        target: BranchEdge { target, args: state.as_args() }
                    });
                    queue.push_back((state.clone(), target, target_idx));
                }
                YARVINSN_jump => {
                    let offset = get_arg(pc, 0).as_i64();
                    // TODO(max): Check interrupts
                    let target_idx = insn_idx_at_offset(insn_idx, offset);
                    let target = insn_idx_to_block[&target_idx];
                    let _branch_id = fun.push_insn(block, Insn::Jump(
                        BranchEdge { target, args: state.as_args() }
                    ));
                    queue.push_back((state.clone(), target, target_idx));
                    break;  // Don't enqueue the next block as a successor
                }
                YARVINSN_opt_nil_p => {
                    let recv = state.pop()?;
                    state.push(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: "nil?".into() }, args: vec![] }));
                }
                YARVINSN_getlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let val = state.getlocal(ep_offset);
                    state.push(val);
                }
                YARVINSN_setlocal_WC_0 => {
                    let ep_offset = get_arg(pc, 0).as_u32();
                    let val = state.pop()?;
                    state.setlocal(ep_offset, val);
                }
                YARVINSN_pop => { state.pop()?; }
                YARVINSN_dup => { state.push(state.top()?); }
                YARVINSN_swap => {
                    let right = state.pop()?;
                    let left = state.pop()?;
                    state.push(right);
                    state.push(left);
                }
                YARVINSN_setn => {
                    let n = get_arg(pc, 0).as_usize();
                    let top = state.top()?;
                    state.setn(n, top);
                }

                YARVINSN_opt_plus | YARVINSN_zjit_opt_plus => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_PLUS }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumAdd { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "+".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_minus | YARVINSN_zjit_opt_minus => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_MINUS }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumSub { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "-".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_mult | YARVINSN_zjit_opt_mult => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_MULT }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumMult { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "*".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_div | YARVINSN_zjit_opt_div => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_DIV }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumDiv { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "/".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_mod | YARVINSN_zjit_opt_mod => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_MOD }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumMod { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "%".into() }, args: vec![right] }));
                    }
                }

                YARVINSN_opt_eq | YARVINSN_zjit_opt_eq => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_EQ }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumEq { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "==".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_neq | YARVINSN_zjit_opt_neq => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_NEQ }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumNeq { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "!=".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_lt | YARVINSN_zjit_opt_lt => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_LT }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumLt { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "<".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_le | YARVINSN_zjit_opt_le => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_LE }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumLe { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "<=".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_gt | YARVINSN_zjit_opt_gt => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_GT }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumGt { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "<".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_ge | YARVINSN_zjit_opt_ge => {
                    if payload.have_two_fixnums(current_insn_idx as usize) {
                        fun.push_insn(block, Insn::PatchPoint(Invariant::BOPRedefined { klass: INTEGER_REDEFINED_OP_FLAG, bop: BOP_GE }));
                        let (left, right) = guard_two_fixnums(&mut state, exit_state, &mut fun, block)?;
                        state.push(fun.push_insn(block, Insn::FixnumGe { left, right, state: exit_state }));
                    } else {
                        let right = state.pop()?;
                        let left = state.pop()?;
                        state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "<=".into() }, args: vec![right] }));
                    }
                }
                YARVINSN_opt_ltlt => {
                    let right = state.pop()?;
                    let left = state.pop()?;
                    state.push(fun.push_insn(block, Insn::Send { self_val: left, call_info: CallInfo { name: "<<".into() }, args: vec![right] }));
                }
                YARVINSN_opt_aset => {
                    let set = state.pop()?;
                    let obj = state.pop()?;
                    let recv = state.pop()?;
                    fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: "[]=".into() }, args: vec![obj, set] });
                    state.push(set);
                }

                YARVINSN_leave => {
                    fun.push_insn(block, Insn::Return { val: state.pop()? });
                    break;  // Don't enqueue the next block as a successor
                }

                YARVINSN_opt_send_without_block => {
                    let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                    let call_info = unsafe { rb_get_call_data_ci(cd) };
                    let argc = unsafe { vm_ci_argc((*cd).ci) };


                    let method_name = unsafe {
                        let mid = rb_vm_ci_mid(call_info);
                        cstr_to_rust_string(rb_id2name(mid)).unwrap_or_else(|| "<unknown>".to_owned())
                    };
                    let mut args = vec![];
                    for _ in 0..argc {
                        args.push(state.pop()?);
                    }
                    args.reverse();

                    let recv = state.pop()?;
                    state.push(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: method_name }, args }));
                }
                _ => return Err(ParseError::UnknownOpcode(insn_name(opcode as usize))),
            }

            if insn_idx_to_block.contains_key(&insn_idx) {
                let target = insn_idx_to_block[&insn_idx];
                fun.push_insn(block, Insn::Jump(BranchEdge { target, args: state.as_args() }));
                queue.push_back((state, target, insn_idx));
                break;  // End the block
            }
        }
    }

    match get_option!(dump_hir) {
        Some(DumpHIR::WithoutSnapshot) => println!("HIR:\n{}", FunctionPrinter::without_snapshot(&fun)),
        Some(DumpHIR::All) => println!("HIR:\n{}", FunctionPrinter::with_snapshot(&fun)),
        Some(DumpHIR::Raw) => println!("HIR:\n{:#?}", &fun),
        None => {},
    }

    Ok(fun)
}

/// Generate guards for two fixnum outputs
fn guard_two_fixnums(state: &mut FrameState, exit_state: FrameStateId, fun: &mut Function, block: BlockId) -> Result<(InsnId, InsnId), ParseError> {
    let left = fun.push_insn(block, Insn::GuardType { val: state.stack_opnd(1)?, guard_type: Fixnum, state: exit_state });
    let right = fun.push_insn(block, Insn::GuardType { val: state.stack_opnd(0)?, guard_type: Fixnum, state: exit_state });

    // Pop operands after guards for side exits
    state.pop()?;
    state.pop()?;

    Ok((left, right))
}

#[cfg(test)]
mod union_find_tests {
    use super::UnionFind;

    #[test]
    fn test_find_returns_self() {
        let mut uf = UnionFind::new();
        assert_eq!(uf.find(3usize), 3);
    }

    #[test]
    fn test_find_const_returns_target() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        assert_eq!(uf.find_const(3usize), 4);
    }

    #[test]
    fn test_find_const_returns_transitive_target() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        uf.make_equal_to(4, 5);
        assert_eq!(uf.find_const(3usize), 5);
        assert_eq!(uf.find_const(4usize), 5);
    }

    #[test]
    fn test_find_compresses_path() {
        let mut uf = UnionFind::new();
        uf.make_equal_to(3, 4);
        uf.make_equal_to(4, 5);
        assert_eq!(uf.at(3usize), Some(4));
        assert_eq!(uf.find(3usize), 5);
        assert_eq!(uf.at(3usize), Some(5));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[macro_export]
    macro_rules! assert_matches {
        ( $x:expr, $pat:pat ) => {
            {
                let val = $x;
                if (!matches!(val, $pat)) {
                    eprintln!("{} ({:?}) does not match pattern {}", stringify!($x), val, stringify!($pat));
                    assert!(false);
                }
            }
        };
    }


    #[track_caller]
    fn assert_matches_value(insn: Option<&Insn>, val: VALUE) {
        match insn {
            Some(Insn::Const { val: Const::Value(spec) }) => {
                assert_eq!(*spec, val);
            }
            _ => assert!(false, "Expected Const {val}, found {insn:?}"),
        }
    }

    #[track_caller]
    fn assert_matches_const(insn: Option<&Insn>, expected: Const) {
        match insn {
            Some(Insn::Const { val }) => {
                assert_eq!(*val, expected, "{val:?} does not match {expected:?}");
            }
            _ => assert!(false, "Expected Const {expected:?}, found {insn:?}"),
        }
    }

    #[track_caller]
    fn assert_method_hir(method: &str, hir: &str) {
        let iseq = get_method_iseq(method);
        let function = iseq_to_hir(iseq).unwrap();
        assert_function_hir(function, hir);
    }

    #[track_caller]
    fn assert_function_hir(function: Function, hir: &str) {
        let actual_hir = format!("{}", FunctionPrinter::without_snapshot(&function));
        let expected_hir = unindent(hir, true);
        assert_eq!(actual_hir, expected_hir);
    }

    #[test]
    fn boot_vm() {
        crate::cruby::with_rubyvm(|| {
            let program = "nil.itself";
            let iseq = compile_to_iseq(program);
            assert!(iseq_to_hir(iseq).is_ok());
        });
    }

    #[test]
    fn test_putobject() {
        crate::cruby::with_rubyvm(|| {
            let program = "123";
            let iseq = compile_to_iseq(program);
            let function = iseq_to_hir(iseq).unwrap();
            assert_function_hir(function, "
                bb0():
                  v1 = Const Value(123)
                  v3 = Return v1
            ");
        });
    }

    #[test]
    fn test_opt_plus() {
        crate::cruby::with_rubyvm(|| {
            let program = "1+2";
            let iseq = compile_to_iseq(program);
            let function = iseq_to_hir(iseq).unwrap();
            assert_function_hir(function, "
                bb0():
                  v1 = Const Value(1)
                  v3 = Const Value(2)
                  v5 = Send v1, :+, v3
                  v7 = Return v5
            ");
        });
    }

    #[test]
    fn test_setlocal_getlocal() {
        crate::cruby::with_rubyvm(|| {
            let program = "a = 1; a";
            let iseq = compile_to_iseq(program);
            let function = iseq_to_hir(iseq).unwrap();
            assert_function_hir(function, "
                bb0():
                  v0 = Const Value(nil)
                  v2 = Const Value(1)
                  v6 = Return v2
            ");
        });
    }

    #[test]
    fn test_merge_const() {
        crate::cruby::with_rubyvm(|| {
            let program = "cond = true; if cond; 3; else; 4; end";
            let iseq = compile_to_iseq(program);
            let function = iseq_to_hir(iseq).unwrap();
            assert_function_hir(function, "
                bb0():
                  v0 = Const Value(nil)
                  v2 = Const Value(true)
                  v6 = Test v2
                  v7 = IfFalse v6, bb1(v2)
                  v9 = Const Value(3)
                  v11 = Return v9
                bb1(v12):
                  v14 = Const Value(4)
                  v16 = Return v14
            ");
        });
    }

    #[test]
    fn test_opt_plus_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a + b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumAdd v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_minus_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a - b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumSub v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_mult_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a * b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MULT)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumMult v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_div_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a / b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_DIV)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumDiv v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_mod_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a % b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_MOD)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumMod v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_eq_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a == b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_EQ)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumEq v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_neq_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a != b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_NEQ)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumNeq v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_lt_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a < b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LT)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumLt v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_le_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a <= b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_LE)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumLe v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_gt_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a > b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GT)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumGt v6, v7
                  v10 = Return v8
            ");
        });
    }

    #[test]
    fn test_opt_ge_fixnum() {
        crate::cruby::with_rubyvm(|| {
            eval("
                def test(a, b) = a >= b
                test(1, 2); test(1, 2)
            ");
            assert_method_hir("test", "
                bb0(v0, v1):
                  v5 = PatchPoint BOPRedefined(INTEGER_REDEFINED_OP_FLAG, BOP_GE)
                  v6 = GuardType v0, Fixnum
                  v7 = GuardType v1, Fixnum
                  v8 = FixnumGe v6, v7
                  v10 = Return v8
            ");
        });
    }
}
