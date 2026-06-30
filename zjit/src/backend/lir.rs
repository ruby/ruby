use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap, HashSet};
use std::fmt;
use std::mem::take;
use std::rc::Rc;
use crate::bitset::BitSet;
use crate::codegen::{local_size_and_idx_to_ep_offset, perf_symbol_range_start, perf_symbol_range_end, register_with_perf};
use crate::cruby::{IseqPtr, RUBY_OFFSET_CFP_ISEQ, RUBY_OFFSET_CFP_JIT_RETURN, RUBY_OFFSET_CFP_PC, RUBY_OFFSET_CFP_SP, SIZEOF_VALUE_I32, VALUE, ZJIT_STACK_MAP_SHIFT, ZJIT_STACK_MAP_VREG_TAG, vm_stack_canary, YarvInsnIdx, zjit_jit_frame};
use crate::hir::{Invariant, SideExitReason};
use crate::hir;
use crate::options::{TraceExits, PerfMap, get_option};
use crate::payload::{IseqVersionRef, get_or_create_iseq_payload};
use crate::stats::{exit_counter_ptr, exit_counter_ptr_for_opcode, side_exit_counter, CompileError};
use crate::virtualmem::CodePtr;
use crate::asm::{CodeBlock, Label};
use crate::state::{ZJITState, rb_zjit_record_exit_stack};
use crate::cast::IntoUsize;

/// LIR Block ID. Unique ID for each block, and also defined in LIR so
/// we can differentiate it from HIR block ids.
#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug, PartialOrd, Ord)]
pub struct BlockId(pub usize);

/// Underlying integer width of a virtual-register id. Narrow to keep `Opnd`/`Mem` small.
pub type VRegIdBase = u32;
/// Width of a stack-slot index inside `MemBase`. Separate id space from `VRegId`.
pub type StackIdx = u32;

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug, PartialOrd, Ord)]
pub struct VRegId(pub VRegIdBase);

impl IntoUsize for VRegId {
    fn to_usize(self) -> usize {
        self.0.to_usize()
    }
}

impl From<usize> for VRegId {
    fn from(val: usize) -> Self {
        VRegId(val.try_into().unwrap())
    }
}

impl From<BlockId> for usize {
    fn from(val: BlockId) -> Self {
        val.0
    }
}

impl<T> std::ops::Index<VRegId> for [T] {
    type Output = T;
    #[inline]
    fn index(&self, i: VRegId) -> &T { &self[i.to_usize()] }
}
impl<T> std::ops::IndexMut<VRegId> for [T] {
    #[inline]
    fn index_mut(&mut self, i: VRegId) -> &mut T { &mut self[i.to_usize()] }
}
impl<T> std::ops::Index<VRegId> for Vec<T> {
    type Output = T;
    #[inline]
    fn index(&self, i: VRegId) -> &T { &self[i.to_usize()] }
}
impl<T> std::ops::IndexMut<VRegId> for Vec<T> {
    #[inline]
    fn index_mut(&mut self, i: VRegId) -> &mut T { &mut self[i.to_usize()] }
}

impl std::fmt::Display for BlockId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "l{}", self.0)
    }
}

impl std::fmt::Display for VRegId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "v{}", self.0)
    }
}

/// Dummy HIR block ID used when creating test or invalid LIR blocks
const DUMMY_HIR_BLOCK_ID: usize = usize::MAX;
/// Dummy RPO index used when creating test or invalid LIR blocks
const DUMMY_RPO_INDEX: usize = usize::MAX;

/// LIR Instruction ID. Unique ID for each instruction in the LIR.
#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug, PartialOrd, Ord)]
pub struct InsnId(pub usize);

impl From<InsnId> for usize {
    fn from(val: InsnId) -> Self {
        val.0
    }
}

impl std::fmt::Display for InsnId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "i{}", self.0)
    }
}

#[derive(Debug, PartialEq, Clone)]
pub struct BranchEdge {
    pub target: BlockId,
    pub args: Vec<Opnd>,
}

#[derive(Clone, Debug)]
pub struct BasicBlock {
    // Unique id for this block
    pub id: BlockId,

    // HIR block this LIR block was lowered from. Not injective: multiple LIR blocks may share
    // the same hir_block_id because we split HIR blocks into multiple LIR blocks during lowering.
    pub hir_block_id: hir::BlockId,

    pub is_entry: bool,

    // Instructions in this basic block
    pub insns: Vec<Insn>,

    // Instruction IDs for each instruction (same length as insns)
    pub insn_ids: Vec<Option<InsnId>>,

    // Input parameters for this block
    pub parameters: Vec<Opnd>,

    // RPO position of the source HIR block
    pub rpo_index: usize,

    // Range of instruction IDs in this block
    pub from: InsnId,
    pub to: InsnId,
}

pub struct EdgePair(Option<BranchEdge>, Option<BranchEdge>);

impl BasicBlock {
    fn new(id: BlockId, hir_block_id: hir::BlockId, is_entry: bool, rpo_index: usize) -> Self {
        Self {
            id,
            hir_block_id,
            is_entry,
            insns: vec![],
            insn_ids: vec![],
            parameters: vec![],
            rpo_index,
            from: InsnId(0),
            to: InsnId(0),
        }
    }

    pub fn is_dummy(&self) -> bool {
        self.hir_block_id == hir::BlockId(DUMMY_HIR_BLOCK_ID)
    }

    pub fn add_parameter(&mut self, param: Opnd) {
        self.parameters.push(param);
    }

    pub fn push_insn(&mut self, insn: Insn) {
        self.insns.push(insn);
        self.insn_ids.push(None);
    }

    pub fn edges(&self) -> EdgePair {
        // Stub blocks (from new_block_without_id) have no real CFG structure.
        if self.rpo_index == DUMMY_RPO_INDEX {
            return EdgePair(None, None);
        }
        assert!(self.insns.last().unwrap().is_terminator());
        let extract_edge = |insn: &Insn| -> Option<BranchEdge> {
            if let Some(Target::Block(edge)) = insn.target() {
                Some(edge.clone())
            } else {
                None
            }
        };

        match self.insns.as_slice() {
            [] => panic!("empty block"),
            [.., second_last, last] => {
                EdgePair(extract_edge(second_last), extract_edge(last))
            },
            [.., last] => {
                EdgePair(extract_edge(last), None)
            }
        }
    }

    /// Sort key for scheduling blocks in code layout order
    pub fn sort_key(&self) -> (usize, usize) {
        (self.rpo_index, self.id.0)
    }

    pub fn successors(&self) -> Vec<BlockId> {
        let EdgePair(edge1, edge2) = self.edges();
        let mut succs = Vec::new();
        if let Some(edge) = edge1 {
            succs.push(edge.target);
        }
        if let Some(edge) = edge2 {
            succs.push(edge.target);
        }
        succs
    }

    /// Get the output VRegs for this block.
    /// These are VRegs referenced by operands passed to successor blocks via block edges.
    /// This function is used for live range calculations and should _not_
    /// be used for parallel moves between blocks
    pub fn out_vregs(&self) -> Vec<VRegId> {
        let EdgePair(edge1, edge2) = self.edges();
        let mut out_vregs = Vec::new();
        if let Some(edge) = edge1 {
            for arg in &edge.args {
                for idx in arg.vreg_ids() {
                    out_vregs.push(idx);
                }
            }
        }
        if let Some(edge) = edge2 {
            for arg in &edge.args {
                for idx in arg.vreg_ids() {
                    out_vregs.push(idx);
                }
            }
        }
        out_vregs
    }
}

pub use crate::backend::current::{
    mem_base_reg,
    Reg,
    EC, CFP, SP,
    NATIVE_BASE_PTR,
    C_ARG_OPNDS, C_RET_OPND,
};

pub static JIT_PRESERVED_REGS: &[Opnd] = &[CFP, SP, EC];

// Memory operand base
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, Ord, PartialOrd)]
pub enum MemBase
{
    /// Register: Every Opnd::Mem should have MemBase::Reg as of emit.
    Reg(u8),
    /// Virtual register: Lowered to MemBase::Reg or MemBase::Stack during register assignment.
    VReg(VRegId),
    /// Stack slot: a direct stack access. `stack_membase_to_mem()` turns this
    /// into `[NATIVE_BASE_PTR + disp]`, so scratch splitting can use it as a
    /// normal memory operand without first loading a pointer from the stack.
    Stack { stack_idx: StackIdx, num_bits: u8 },
    /// A pointer stored in a stack slot, used as a memory base.
    /// Unlike Stack, this first loads the pointer value from the stack slot
    /// into a scratch register, then uses that register as the base for the
    /// memory access with the Mem's displacement.
    /// Created when a VReg used as MemBase is spilled to the stack.
    StackIndirect { stack_idx: StackIdx },
}

// Memory location
#[derive(Copy, Clone, PartialEq, Eq, Hash, Ord, PartialOrd)]
pub struct Mem
{
    // Base register number or instruction index
    pub base: MemBase,

    // Offset relative to the base pointer
    pub disp: i32,

    // Size in bits
    pub num_bits: u8,
}

impl fmt::Display for Mem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.num_bits != 64 {
            write!(f, "Mem{}", self.num_bits)?;
        }
        write!(f, "[")?;
        match self.base {
            MemBase::Reg(reg_no) => write!(f, "{}", mem_base_reg(reg_no))?,
            MemBase::VReg(idx) => write!(f, "{idx}")?,
            MemBase::Stack { stack_idx, num_bits } if num_bits == 64 => write!(f, "Stack[{stack_idx}]")?,
            MemBase::StackIndirect { stack_idx } => write!(f, "*Stack[{stack_idx}]")?,
            MemBase::Stack { stack_idx, num_bits } => write!(f, "Stack{num_bits}[{stack_idx}]")?,
        }
        if self.disp != 0 {
            let sign = if self.disp > 0 { '+' } else { '-' };
            write!(f, " {sign} ")?;
            if self.disp.abs() >= 10 {
                write!(f, "0x")?;
            }
            write!(f, "{:x}", self.disp.abs())?;
        }
        write!(f, "]")
    }
}

impl fmt::Debug for Mem {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "Mem{}[{:?}", self.num_bits, self.base)?;
        if self.disp != 0 {
            let sign = if self.disp > 0 { '+' } else { '-' };
            write!(fmt, " {sign} {}", self.disp.abs())?;
        }

        write!(fmt, "]")
    }
}

/// Operand to an IR instruction
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum Opnd
{
    None,               // For insns with no output

    // Immediate Ruby value, may be GC'd, movable
    Value(VALUE),

    /// Virtual register. Lowered to Reg or Mem during register assignment.
    VReg{ idx: VRegId, num_bits: u8 },

    // Low-level operands, for lowering
    Imm(i64),           // Raw signed immediate
    UImm(u64),          // Raw unsigned immediate
    Mem(Mem),           // Memory location
    Reg(Reg),           // Machine register
}

impl PartialOrd for Opnd {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Opnd {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        fn case_order(opnd: &Opnd) -> u8 {
            match opnd {
                Opnd::None => 0,
                Opnd::Value(_) => 1,
                Opnd::VReg { .. } => 2,
                Opnd::Imm(_) => 3,
                Opnd::UImm(_) => 4,
                Opnd::Mem(_) => 5,
                Opnd::Reg(_) => 6,
            }
        }
        match (self, other) {
            (Opnd::None, Opnd::None) => std::cmp::Ordering::Equal,
            (Opnd::Value(l), Opnd::Value(r)) => l.0.cmp(&r.0),
            (Opnd::VReg { idx: lidx, num_bits: lnum_bits }, Opnd::VReg { idx: ridx, num_bits: rnum_bits }) => (lidx, lnum_bits).cmp(&(ridx, rnum_bits)),
            (Opnd::Imm(l), Opnd::Imm(r)) => l.cmp(&r),
            (Opnd::UImm(l), Opnd::UImm(r)) => l.cmp(&r),
            (Opnd::Mem(l), Opnd::Mem(r)) => l.cmp(&r),
            (Opnd::Reg(l), Opnd::Reg(r)) => l.cmp(&r),
            (l, r) => {
                case_order(l).cmp(&case_order(r))
            }
        }
    }
}

impl fmt::Display for Opnd {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use Opnd::*;
        match self {
            None => write!(f, "None"),
            Value(VALUE(value)) if *value < 10 => write!(f, "Value({value:x})"),
            Value(VALUE(value)) => write!(f, "Value(0x{value:x})"),
            VReg { idx, num_bits } if *num_bits == 64 => write!(f, "{idx}"),
            VReg { idx, num_bits } => write!(f, "VReg{num_bits}({idx})"),
            Imm(value) if value.abs() < 10 => write!(f, "Imm({value:x})"),
            Imm(value) => write!(f, "Imm(0x{value:x})"),
            UImm(value) if *value < 10 => write!(f, "{value:x}"),
            UImm(value) => write!(f, "0x{value:x}"),
            Mem(mem) => write!(f, "{mem}"),
            Reg(reg) => write!(f, "{reg}"),
        }
    }
}

impl fmt::Debug for Opnd {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        use Opnd::*;
        match self {
            Self::None => write!(fmt, "None"),
            Value(val) => write!(fmt, "Value({val:?})"),
            VReg { idx, num_bits } if *num_bits == 64 => write!(fmt, "VReg({})", idx.0),
            VReg { idx, num_bits } => write!(fmt, "VReg{num_bits}({})", idx.0),
            Imm(signed) => write!(fmt, "{signed:x}_i64"),
            UImm(unsigned) => write!(fmt, "{unsigned:x}_u64"),
            // Say Mem and Reg only once
            Mem(mem) => write!(fmt, "{mem:?}"),
            Reg(reg) => write!(fmt, "{reg:?}"),
        }
    }
}

impl Opnd
{
    /// Returns true if this operand is a virtual register
    pub fn is_vreg(&self) -> bool {
        matches!(self, Opnd::VReg { .. })
    }

    /// Convenience constructor for memory operands
    pub fn mem(num_bits: u8, base: Opnd, disp: i32) -> Self {
        match base {
            Opnd::Reg(base_reg) => {
                assert!(base_reg.num_bits == 64);
                Opnd::Mem(Mem {
                    base: MemBase::Reg(base_reg.reg_no),
                    disp,
                    num_bits,
                })
            },

            Opnd::VReg{idx, num_bits: out_num_bits } => {
                assert!(num_bits <= out_num_bits);
                Opnd::Mem(Mem {
                    base: MemBase::VReg(idx),
                    disp,
                    num_bits,
                })
            },

            _ => unreachable!("memory operand with non-register base: {base:?}")
        }
    }

    /// Constructor for constant pointer operand
    pub fn const_ptr<T>(ptr: *const T) -> Self {
        Opnd::UImm(ptr as u64)
    }

    /// Unwrap a register operand
    pub fn unwrap_reg(&self) -> Reg {
        match self {
            Opnd::Reg(reg) => *reg,
            _ => unreachable!("trying to unwrap {:?} into reg", self)
        }
    }

    /// Unwrap the index of a VReg
    pub fn vreg_idx(&self) -> VRegId {
        match self {
            Opnd::VReg { idx, .. } => *idx,
            _ => unreachable!("trying to unwrap {self:?} into VReg"),
        }
    }

    /// Unwrap the index of a VReg as a `usize`, for raw-`usize` APIs (bitsets, etc.).
    pub fn vreg_idx_usize(&self) -> usize {
        self.vreg_idx().to_usize()
    }

    /// Extract VReg indices from this operand, including memory base VRegs.
    /// Returns an iterator over all VRegIds referenced by this operand.
    pub fn vreg_ids(&self) -> impl Iterator<Item = VRegId> {
        let mut ids = [None, None];
        match self {
            Opnd::VReg { idx, .. } => { ids[0] = Some(*idx); }
            Opnd::Mem(Mem { base: MemBase::VReg(idx), .. }) => { ids[0] = Some(*idx); }
            _ => {}
        }
        ids.into_iter().flatten()
    }

    /// Get the size in bits for this operand if there is one.
    pub fn num_bits(&self) -> Option<u8> {
        match *self {
            Opnd::Reg(Reg { num_bits, .. }) => Some(num_bits),
            Opnd::Mem(Mem { num_bits, .. }) => Some(num_bits),
            Opnd::VReg { num_bits, .. } => Some(num_bits),
            _ => None
        }
    }

    /// Return Opnd with a given num_bits if self has num_bits. Panic otherwise.
    #[track_caller]
    pub fn with_num_bits(&self, num_bits: u8) -> Opnd {
        assert!(num_bits == 8 || num_bits == 16 || num_bits == 32 || num_bits == 64);
        match *self {
            Opnd::Reg(reg) => Opnd::Reg(reg.with_num_bits(num_bits)),
            Opnd::Mem(Mem { base, disp, .. }) => Opnd::Mem(Mem { base, disp, num_bits }),
            Opnd::VReg { idx, .. } => Opnd::VReg { idx, num_bits },
            _ => unreachable!("with_num_bits should not be used for: {self:?}"),
        }
    }

    /// Get the size in bits for register/memory operands.
    pub fn rm_num_bits(&self) -> u8 {
        self.num_bits().unwrap()
    }

    /// Maps the indices from a previous list of instructions to a new list of
    /// instructions.
    pub fn map_index(self, indices: &[usize]) -> Opnd {
        match self {
            Opnd::VReg { idx, num_bits } => {
                Opnd::VReg { idx: indices[idx].into(), num_bits }
            }
            Opnd::Mem(Mem { base: MemBase::VReg(idx), disp, num_bits }) => {
                Opnd::Mem(Mem { base: MemBase::VReg(indices[idx].into()), disp, num_bits })
            },
            _ => self
        }
    }

    /// When there aren't any operands to check against, this is the number of
    /// bits that should be used for any given output variable.
    const DEFAULT_NUM_BITS: u8 = 64;

    /// Determine the size in bits from the iterator of operands. If any of them
    /// are different sizes this will panic.
    pub fn match_num_bits_iter<'a>(opnds: impl Iterator<Item = &'a Opnd>) -> u8 {
        let mut value: Option<u8> = None;

        for opnd in opnds {
            if let Some(num_bits) = opnd.num_bits() {
                match value {
                    None => {
                        value = Some(num_bits);
                    },
                    Some(value) => {
                        assert_eq!(value, num_bits, "operands of incompatible sizes");
                    }
                };
            }
        }

        value.unwrap_or(Self::DEFAULT_NUM_BITS)
    }

    /// Determine the size in bits of the slice of the given operands. If any of
    /// them are different sizes this will panic.
    pub fn match_num_bits(opnds: &[Opnd]) -> u8 {
        Self::match_num_bits_iter(opnds.iter())
    }
}

impl From<usize> for Opnd {
    fn from(value: usize) -> Self {
        Opnd::UImm(value.try_into().unwrap())
    }
}

impl From<u64> for Opnd {
    fn from(value: u64) -> Self {
        Opnd::UImm(value)
    }
}

impl From<i64> for Opnd {
    fn from(value: i64) -> Self {
        Opnd::Imm(value)
    }
}

impl From<i32> for Opnd {
    fn from(value: i32) -> Self {
        Opnd::Imm(value.into())
    }
}

impl From<u32> for Opnd {
    fn from(value: u32) -> Self {
        Opnd::UImm(value as u64)
    }
}

impl From<VALUE> for Opnd {
    fn from(value: VALUE) -> Self {
        Opnd::Value(value)
    }
}

/// Context for a side exit. If `SideExit` matches, it reuses the same code.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct SideExit {
    pub pc: Opnd,
    pub stack: Vec<Opnd>,
    pub locals: Vec<Opnd>,
    pub iseq: IseqPtr,
    /// If set, the side exit will profile the current instruction and invalidate
    /// the compiled ISEQ for recompilation.
    pub recompile: Option<SideExitRecompile>,
}

/// Metadata for the recompile callback on side exit.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct SideExitRecompile {
    /// The compiled unit whose version must be invalidated to force a recompile. For inlined
    /// methods, this will be the outer function it was inlined into.
    pub compiled_iseq: Opnd,
    pub insn_idx: u32,
}

/// Branch target (something that we can jump to)
/// for branch instructions
#[derive(Clone)]
pub enum Target
{
    /// Pointer to a piece of ZJIT-generated code
    CodePtr(CodePtr),
    /// A label within the generated code
    Label(Label),
    /// An LIR branch edge
    Block(BranchEdge),
    /// Side exit to the interpreter
    SideExit {
        /// Context used for compiling the side exit. Boxed to keep `Target`
        /// (and every `Insn` variant that embeds it) small.
        exit: Box<SideExit>,
        /// We use this to increment exit counters
        reason: SideExitReason,
    },
}

impl fmt::Debug for Target {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Target::CodePtr(ptr) => write!(f, "CodePtr({:?})", ptr),
            Target::Label(label) => write!(f, "Label({:?})", label),
            Target::Block(edge) => {
                if edge.args.is_empty() {
                    write!(f, "Block({:?})", edge.target)
                } else {
                    write!(f, "Block({:?}(", edge.target)?;
                    for (i, arg) in edge.args.iter().enumerate() {
                        if i > 0 {
                            write!(f, ", ")?;
                        }
                        write!(f, "{:?}", arg)?;
                    }
                    write!(f, "))")
                }
            }
            Target::SideExit { exit, reason } => {
                write!(f, "SideExit {{ exit: {:?}, reason: {:?} }}", exit, reason)
            }
        }
    }
}

impl Target
{
    pub fn unwrap_label(&self) -> Label {
        match self {
            Target::Label(label) => *label,
            _ => unreachable!("trying to unwrap {:?} into label", self)
        }
    }

    pub fn unwrap_code_ptr(&self) -> CodePtr {
        match self {
            Target::CodePtr(ptr) => *ptr,
            _ => unreachable!("trying to unwrap {:?} into code ptr", self)
        }
    }
}

impl From<CodePtr> for Target {
    fn from(code_ptr: CodePtr) -> Self {
        Target::CodePtr(code_ptr)
    }
}

type PosMarkerFn = Rc<dyn Fn(CodePtr, &CodeBlock)>;

/// Cold fields of `Insn::CCall`, boxed to keep `Insn` small. The operand-bearing
/// fields (`opnds`, `stack_map`) stay inline on the variant so the operand
/// iteration macros can reach them by reference.
#[derive(Clone)]
pub struct CCallData {
    /// The function pointer to be called. This should be Opnd::const_ptr
    /// (Opnd::UImm) in most cases. gen_entry_trampoline() uses Opnd::Reg.
    pub fptr: Opnd,
    /// Optional PosMarker to remember the start address of the C call.
    /// It's embedded here to insert the PosMarker after push instructions
    /// that are split from this CCall during register assignment.
    pub start_marker: Option<PosMarkerFn>,
    /// Optional PosMarker to remember the end address of the C call.
    /// It's embedded here to insert the PosMarker before pop instructions
    /// that are split from this CCall during register assignment.
    pub end_marker: Option<PosMarkerFn>,
    pub out: Opnd,
}

/// Cold fields of `Insn::PatchPoint`, boxed to keep `Insn` small. `target` is
/// operand-bearing (it's a `Target::SideExit` until `compile_exits` lowers it to
/// a `Target::Label`), so the operand-iteration macros reach it through the box
/// via a per-iterator reborrow -- the same idea as `CCallData` and the HIR
/// `CCallWithFrame` pattern.
#[derive(Clone)]
pub struct PatchPointData {
    /// Patch point target. Rewritten to a jump to a side exit on invalidation.
    pub target: Target,
    /// The invariant whose violation triggers invalidation of this patch point.
    pub invariant: Invariant,
    /// ISEQ version invalidated to force a recompile when the invariant breaks.
    pub version: IseqVersionRef,
}

/// ZJIT Low-level IR instruction
#[derive(Clone)]
pub enum Insn {
    /// Add two operands together, and return the result as a new operand.
    Add { left: Opnd, right: Opnd, out: Opnd },

    /// This is the same as the OP_ADD instruction, except that it performs the
    /// binary AND operation.
    And { left: Opnd, right: Opnd, out: Opnd },

    /// Bake a string directly into the instruction stream.
    BakeString(String),

    // Trigger a debugger breakpoint
    #[allow(dead_code)]
    Breakpoint,

    // Abort the process
    Abort,

    /// Add a comment into the IR at the point that this instruction is added.
    /// It won't have any impact on that actual compiled code.
    Comment(String),

    /// Compare two operands
    Cmp { left: Opnd, right: Opnd },

    /// Pop a register from the C stack
    CPop { out: Opnd },

    /// Pop a register from the C stack and store it into another register
    CPopInto(Opnd),

    /// Pop a pair of registers from the C stack and store it into a pair of registers.
    /// The registers are popped from left to right.
    CPopPairInto(Opnd, Opnd),

    /// Push a register onto the C stack
    CPush(Opnd),

    /// Push a pair of registers onto the C stack.
    /// The registers are pushed from left to right.
    CPushPair(Opnd, Opnd),

    // C function call with N arguments (variadic)
    CCall {
        opnds: Vec<Opnd>,
        stack_map: Option<StackMap>,
        /// Cold fields (fptr, markers, out), boxed to keep `Insn` small.
        data: Box<CCallData>,
    },

    // C function return
    CRet(Opnd),

    /// Conditionally select if equal
    CSelE { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if greater
    CSelG { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if greater or equal
    CSelGE { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if less
    CSelL { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if less or equal
    CSelLE { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if not equal
    CSelNE { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if not zero
    CSelNZ { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Conditionally select if zero
    CSelZ { truthy: Opnd, falsy: Opnd, out: Opnd },

    /// Set up the frame stack as necessary per the architecture.
    FrameSetup { preserved: &'static [Opnd], slot_count: usize },

    /// Tear down the frame stack as necessary per the architecture.
    FrameTeardown { preserved: &'static [Opnd], },

    // Atomically increment a counter
    // Input: memory operand, increment value
    // Produces no output
    IncrCounter { mem: Opnd, value: Opnd },

    /// Jump if below or equal (unsigned)
    Jbe(Target),

    /// Jump if below (unsigned)
    Jb(Target),

    /// Jump if equal
    Je(Target),

    /// Jump if lower
    Jl(Target),

    /// Jump if greater
    Jg(Target),

    /// Jump if greater or equal
    Jge(Target),

    // Unconditional jump to a branch target
    Jmp(Target),

    // Unconditional jump which takes a reg/mem address operand
    JmpOpnd(Opnd),

    /// Jump if not equal
    Jne(Target),

    /// Jump if not zero
    Jnz(Target),

    /// Jump if overflow
    Jo(Target),

    /// Jump if overflow in multiplication
    JoMul(Target),

    /// Jump if zero
    Jz(Target),

    /// Jump if operand is zero (only used during lowering at the moment)
    Joz(Opnd, Target),

    /// Jump if operand is non-zero (only used during lowering at the moment)
    Jonz(Opnd, Target),

    // Add a label into the IR at the point that this instruction is added.
    Label(Target),

    /// Get the code address of a jump target
    LeaJumpTarget { target: Target, out: Opnd },

    // Load effective address
    Lea { opnd: Opnd, out: Opnd },

    // A low-level instruction that loads a value into a register.
    Load { opnd: Opnd, out: Opnd },

    // A low-level instruction that loads a value into a specified register.
    LoadInto { dest: Opnd, opnd: Opnd },

    // A low-level instruction that loads a value into a register and
    // sign-extends it to a 64-bit value.
    LoadSExt { opnd: Opnd, out: Opnd },

    /// Shift a value left by a certain amount.
    LShift { opnd: Opnd, shift: Opnd, out: Opnd },

    // A low-level mov instruction. It accepts two operands.
    Mov { dest: Opnd, src: Opnd },

    // Perform the NOT operation on an individual operand, and return the result
    // as a new operand. This operand can then be used as the operand on another
    // instruction.
    Not { opnd: Opnd, out: Opnd },

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary OR operation.
    Or { left: Opnd, right: Opnd, out: Opnd },

    /// Patch point that will be rewritten to a jump to a side exit on invalidation.
    /// Cold fields are boxed (see `PatchPointData`) to keep `Insn` small.
    PatchPoint(Box<PatchPointData>),

    /// Make sure the last PatchPoint has enough space to insert a jump.
    /// We insert this instruction at the end of each block so that the jump
    /// will not overwrite the next block or a side exit.
    PadPatchPoint,

    // Mark a position in the generated code
    PosMarker(PosMarkerFn),

    /// Shift a value right by a certain amount (signed).
    RShift { opnd: Opnd, shift: Opnd, out: Opnd },

    // Low-level instruction to store a value to memory.
    Store { dest: Opnd, src: Opnd },

    // This is the same as the add instruction, except for subtraction.
    Sub { left: Opnd, right: Opnd, out: Opnd },

    // Integer multiplication
    Mul { left: Opnd, right: Opnd, out: Opnd },

    // Bitwise AND test instruction
    Test { left: Opnd, right: Opnd },

    /// Shift a value right by a certain amount (unsigned).
    URShift { opnd: Opnd, shift: Opnd, out: Opnd },

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary XOR operation.
    Xor { left: Opnd, right: Opnd, out: Opnd }
}

macro_rules! target_for_each_operand_impl {
    ($self:expr, $visit_many:ident) => {
        match $self {
            Target::SideExit { exit, .. } => {
                visit_many!(exit.stack);
                visit_many!(exit.locals);
            }
            Target::Block(edge) => {
                visit_many!(edge.args);
            }
            Target::CodePtr(_) | Target::Label(_) => {}
        }
    }
}

/// Macro that enumerates all operands of an Insn, dispatching to caller-provided `$visit_one`
/// macro for a single `Opnd` field and `$visit_many` macro for a slice/`Vec` of `Opnd`s. Used by
/// both `for_each_operand` and `for_each_operand_mut`.
macro_rules! for_each_operand_impl {
    ($self:expr, $visit_one:ident, $visit_many:ident, $reborrow:ident $(, $const:expr)?) => {
        match $self {
            Insn::Jbe(target) |
            Insn::Jb(target) |
            Insn::Je(target) |
            Insn::Jl(target) |
            Insn::Jg(target) |
            Insn::Jge(target) |
            Insn::Jmp(target) |
            Insn::Jne(target) |
            Insn::Jnz(target) |
            Insn::Jo(target) |
            Insn::JoMul(target) |
            Insn::Jz(target) |
            Insn::Label(target) |
            Insn::LeaJumpTarget { target, .. } => {
                target_for_each_operand_impl!(target, $visit_many);
            }
            // `target` is behind a Box. `$reborrow` turns the box field into a `&`/`&mut Target`
            // matching the iterator, so the same operand-walk works for both.
            Insn::PatchPoint(data) => {
                target_for_each_operand_impl!($reborrow!(data.target), $visit_many);
            }
            Insn::Joz(opnd, target) |
            Insn::Jonz(opnd, target) => {
                visit_one!(opnd);
                target_for_each_operand_impl!(target, $visit_many);
            }

            Insn::BakeString(_) |
            Insn::Breakpoint | Insn::Abort |
            Insn::Comment(_) |
            Insn::CPop { .. } |
            Insn::PadPatchPoint |
            Insn::PosMarker(_) => {},

            Insn::CPopInto(opnd) |
            Insn::CPush(opnd) |
            Insn::CRet(opnd) |
            Insn::JmpOpnd(opnd) |
            Insn::Lea { opnd, .. } |
            Insn::Load { opnd, .. } |
            Insn::LoadSExt { opnd, .. } |
            Insn::Not { opnd, .. } => {
                visit_one!(opnd);
            }
            Insn::Add { left: opnd0, right: opnd1, .. } |
            Insn::And { left: opnd0, right: opnd1, .. } |
            Insn::CPushPair(opnd0, opnd1) |
            Insn::CPopPairInto(opnd0, opnd1) |
            Insn::Cmp { left: opnd0, right: opnd1 } |
            Insn::CSelE { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelG { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelGE { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelL { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelLE { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelNE { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelNZ { truthy: opnd0, falsy: opnd1, .. } |
            Insn::CSelZ { truthy: opnd0, falsy: opnd1, .. } |
            Insn::IncrCounter { mem: opnd0, value: opnd1, .. } |
            Insn::LoadInto { dest: opnd0, opnd: opnd1 } |
            Insn::LShift { opnd: opnd0, shift: opnd1, .. } |
            Insn::Mov { dest: opnd0, src: opnd1 } |
            Insn::Or { left: opnd0, right: opnd1, .. } |
            Insn::RShift { opnd: opnd0, shift: opnd1, .. } |
            Insn::Store { dest: opnd0, src: opnd1 } |
            Insn::Sub { left: opnd0, right: opnd1, .. } |
            Insn::Mul { left: opnd0, right: opnd1, .. } |
            Insn::Test { left: opnd0, right: opnd1 } |
            Insn::URShift { opnd: opnd0, shift: opnd1, .. } |
            Insn::Xor { left: opnd0, right: opnd1, .. } => {
                visit_one!(opnd0);
                visit_one!(opnd1);
            }
            Insn::CCall { opnds, stack_map, .. } => {
                visit_many!(opnds);
                if let Some(StackMap { stack, .. }) = stack_map {
                    visit_many!(stack);
                }
            }
            // only iterate over preserved in the const iterator
            #[allow(unused_variables)]
            Insn::FrameSetup { preserved, .. } |
            Insn::FrameTeardown { preserved } => {
            $(
                visit_many!(preserved);
                $const;
            )?
            }
        }
    }
}

impl Insn {
    pub fn opnd_count(&self) -> usize {
        let mut count = 0;
        self.for_each_operand(|_| count += 1);
        count
    }

    /// Call `f` on each operand (Opnd) of this instruction.
    pub fn for_each_operand(&self, mut f: impl FnMut(Opnd)) {
        macro_rules! visit_one { ($id:expr) => { f(*$id) }; }
        macro_rules! visit_many { ($s:expr) => { for id in ($s).iter() { f(*id) } }; }
        macro_rules! reborrow { ($e:expr) => { & $e }; }
        // Extra () is a throw-away parameter to avoid iterating over FrameSetup/FrameTeardown
        // preserved in the mutable iterator.
        for_each_operand_impl!(self, visit_one, visit_many, reborrow, ());
    }

    /// Call `f` on a mutable reference to each operand (Opnd) of this instruction.
    pub fn for_each_operand_mut(&mut self, mut f: impl FnMut(&mut Opnd)) {
        macro_rules! visit_one { ($id:expr) => { f($id) }; }
        macro_rules! visit_many { ($s:expr) => { for id in ($s).iter_mut() { f(id) } }; }
        macro_rules! reborrow { ($e:expr) => { &mut $e }; }
        for_each_operand_impl!(self, visit_one, visit_many, reborrow);
    }

    /// Call `f` on each operand, short-circuiting on the first error.
    pub fn try_for_each_operand<E>(&self, mut f: impl FnMut(Opnd) -> Result<(), E>) -> Result<(), E> {
        macro_rules! visit_one { ($id:expr) => { f(*$id)? }; }
        macro_rules! visit_many { ($s:expr) => { for id in ($s).iter() { f(*id)? } }; }
        macro_rules! reborrow { ($e:expr) => { & $e }; }
        for_each_operand_impl!(self, visit_one, visit_many, reborrow, ());
        Ok(())
    }

    /// Get a mutable reference to a Target if it exists.
    pub(super) fn target_mut(&mut self) -> Option<&mut Target> {
        match self {
            Insn::Jbe(target) |
            Insn::Jb(target) |
            Insn::Je(target) |
            Insn::Jl(target) |
            Insn::Jg(target) |
            Insn::Jge(target) |
            Insn::Jmp(target) |
            Insn::Jne(target) |
            Insn::Jnz(target) |
            Insn::Jo(target) |
            Insn::JoMul(target) |
            Insn::Jz(target) |
            Insn::Joz(_, target) |
            Insn::Jonz(_, target) |
            Insn::Label(target) |
            Insn::LeaJumpTarget { target, .. } => {
                Some(target)
            }
            Insn::PatchPoint(data) => Some(&mut data.target),
            _ => None,
        }
    }

    /// Returns a string that describes which operation this instruction is
    /// performing. This is used for debugging.
    fn op(&self) -> &'static str {
        match self {
            Insn::Add { .. } => "Add",
            Insn::And { .. } => "And",
            Insn::BakeString(_) => "BakeString",
            Insn::Breakpoint => "Breakpoint",
            Insn::Abort => "Abort",
            Insn::Comment(_) => "Comment",
            Insn::Cmp { .. } => "Cmp",
            Insn::CPop { .. } => "CPop",
            Insn::CPopInto(_) => "CPopInto",
            Insn::CPopPairInto(_, _) => "CPopPairInto",
            Insn::CPush(_) => "CPush",
            Insn::CPushPair(_, _) => "CPushPair",
            Insn::CCall { .. } => "CCall",
            Insn::CRet(_) => "CRet",
            Insn::CSelE { .. } => "CSelE",
            Insn::CSelG { .. } => "CSelG",
            Insn::CSelGE { .. } => "CSelGE",
            Insn::CSelL { .. } => "CSelL",
            Insn::CSelLE { .. } => "CSelLE",
            Insn::CSelNE { .. } => "CSelNE",
            Insn::CSelNZ { .. } => "CSelNZ",
            Insn::CSelZ { .. } => "CSelZ",
            Insn::FrameSetup { .. } => "FrameSetup",
            Insn::FrameTeardown { .. } => "FrameTeardown",
            Insn::IncrCounter { .. } => "IncrCounter",
            Insn::Jbe(_) => "Jbe",
            Insn::Jb(_) => "Jb",
            Insn::Je(_) => "Je",
            Insn::Jl(_) => "Jl",
            Insn::Jg(_) => "Jg",
            Insn::Jge(_) => "Jge",
            Insn::Jmp(_) => "Jmp",
            Insn::JmpOpnd(_) => "JmpOpnd",
            Insn::Jne(_) => "Jne",
            Insn::Jnz(_) => "Jnz",
            Insn::Jo(_) => "Jo",
            Insn::JoMul(_) => "JoMul",
            Insn::Jz(_) => "Jz",
            Insn::Joz(..) => "Joz",
            Insn::Jonz(..) => "Jonz",
            Insn::Label(_) => "Label",
            Insn::LeaJumpTarget { .. } => "LeaJumpTarget",
            Insn::Lea { .. } => "Lea",
            Insn::Load { .. } => "Load",
            Insn::LoadInto { .. } => "LoadInto",
            Insn::LoadSExt { .. } => "LoadSExt",
            Insn::LShift { .. } => "LShift",
            Insn::Mov { .. } => "Mov",
            Insn::Not { .. } => "Not",
            Insn::Or { .. } => "Or",
            Insn::PatchPoint(..) => "PatchPoint",
            Insn::PadPatchPoint => "PadPatchPoint",
            Insn::PosMarker(_) => "PosMarker",
            Insn::RShift { .. } => "RShift",
            Insn::Store { .. } => "Store",
            Insn::Sub { .. } => "Sub",
            Insn::Mul { .. } => "Mul",
            Insn::Test { .. } => "Test",
            Insn::URShift { .. } => "URShift",
            Insn::Xor { .. } => "Xor"
        }
    }

    /// Return a non-mutable reference to the out operand for this instruction
    /// if it has one.
    pub fn out_opnd(&self) -> Option<&Opnd> {
        match self {
            Insn::Add { out, .. } |
            Insn::And { out, .. } |
            Insn::CPop { out, .. } |
            Insn::CSelE { out, .. } |
            Insn::CSelG { out, .. } |
            Insn::CSelGE { out, .. } |
            Insn::CSelL { out, .. } |
            Insn::CSelLE { out, .. } |
            Insn::CSelNE { out, .. } |
            Insn::CSelNZ { out, .. } |
            Insn::CSelZ { out, .. } |
            Insn::Lea { out, .. } |
            Insn::LeaJumpTarget { out, .. } |
            Insn::Load { out, .. } |
            Insn::LoadSExt { out, .. } |
            Insn::LShift { out, .. } |
            Insn::Not { out, .. } |
            Insn::Or { out, .. } |
            Insn::RShift { out, .. } |
            Insn::Sub { out, .. } |
            Insn::Mul { out, .. } |
            Insn::URShift { out, .. } |
            Insn::Xor { out, .. } => Some(out),
            Insn::CCall { data, .. } => Some(&data.out),
            _ => None
        }
    }

    /// Return a mutable reference to the out operand for this instruction if it
    /// has one.
    pub fn out_opnd_mut(&mut self) -> Option<&mut Opnd> {
        match self {
            Insn::Add { out, .. } |
            Insn::And { out, .. } |
            Insn::CPop { out, .. } |
            Insn::CSelE { out, .. } |
            Insn::CSelG { out, .. } |
            Insn::CSelGE { out, .. } |
            Insn::CSelL { out, .. } |
            Insn::CSelLE { out, .. } |
            Insn::CSelNE { out, .. } |
            Insn::CSelNZ { out, .. } |
            Insn::CSelZ { out, .. } |
            Insn::Lea { out, .. } |
            Insn::LeaJumpTarget { out, .. } |
            Insn::Load { out, .. } |
            Insn::LoadSExt { out, .. } |
            Insn::LShift { out, .. } |
            Insn::Not { out, .. } |
            Insn::Or { out, .. } |
            Insn::RShift { out, .. } |
            Insn::Sub { out, .. } |
            Insn::Mul { out, .. } |
            Insn::URShift { out, .. } |
            Insn::Xor { out, .. } => Some(out),
            Insn::CCall { data, .. } => Some(&mut data.out),
            _ => None
        }
    }

    /// Returns the target for this instruction if there is one.
    pub fn target(&self) -> Option<&Target> {
        match self {
            Insn::Jbe(target) |
            Insn::Jb(target) |
            Insn::Je(target) |
            Insn::Jl(target) |
            Insn::Jg(target) |
            Insn::Jge(target) |
            Insn::Jmp(target) |
            Insn::Jne(target) |
            Insn::Jnz(target) |
            Insn::Jo(target) |
            Insn::JoMul(target) |
            Insn::Jz(target) |
            Insn::Joz(_, target) |
            Insn::Jonz(_, target) |
            Insn::Label(target) |
            Insn::LeaJumpTarget { target, .. } => Some(target),
            Insn::PatchPoint(data) => Some(&data.target),
            _ => None
        }
    }

    /// Returns the text associated with this instruction if there is some.
    pub fn text(&self) -> Option<&String> {
        match self {
            Insn::BakeString(text) |
            Insn::Comment(text) => Some(text),
            _ => None
        }
    }

    /// Returns true if this instruction is a terminator (ends a basic block).
    pub fn is_terminator(&self) -> bool {
        self.is_jump() ||
            match self {
                Insn::CRet(_) => true,
                _ => false
            }
    }

    /// Returns true if this instruction is a jump.
    pub fn is_jump(&self) -> bool {
        match self {
            Insn::Jbe(_) |
            Insn::Jb(_) |
            Insn::Je(_) |
            Insn::Jl(_) |
            Insn::Jg(_) |
            Insn::Jge(_) |
            Insn::Jmp(_) |
            Insn::JmpOpnd(_) |
            Insn::Jne(_) |
            Insn::Jnz(_) |
            Insn::Jo(_) |
            Insn::JoMul(_) |
            Insn::Jz(_) |
            Insn::Joz(..) |
            Insn::Jonz(..) => true,
            _ => false
        }
    }
}

impl fmt::Debug for Insn {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "{}(", self.op())?;

        if let Insn::FrameSetup { slot_count, .. } = self {
            write!(fmt, "{slot_count}")?;
        }
        // Print list of operands
        let mut sep = "";
        self.for_each_operand(|opnd| {
             write!(fmt, "{sep}{opnd:?}").unwrap();
             sep = ", ";
        });
        write!(fmt, ")")?;

        // Print text, target, and pos if they are present
        if let Some(text) = self.text() {
            write!(fmt, " {text:?}")?
        }
        if let Some(target) = self.target() {
            write!(fmt, " target={target:?}")?;
        }

        write!(fmt, " -> {:?}", self.out_opnd().unwrap_or(&Opnd::None))
    }
}

/// Live range of a VReg
/// TODO: Consider supporting lifetime holes
#[derive(Clone, Debug, PartialEq)]
pub struct LiveRange {
    /// Index of the first instruction that used the VReg
    pub start: Option<usize>,
    /// Index of the last instruction that used the VReg
    pub end: Option<usize>,
}

impl LiveRange {
    /// Shorthand for self.start.unwrap()
    pub fn start(&self) -> usize {
        self.start.unwrap()
    }

    /// Shorthand for self.end.unwrap()
    pub fn end(&self) -> usize {
        self.end.unwrap()
    }
}

/// Live Interval of a VReg
#[derive(Clone)]
pub struct Interval {
    pub range: LiveRange,
    pub id: VRegId,
}

impl Interval {
    /// Create a new Interval with no range
    pub fn new(i: VRegId) -> Self {
        Self {
            range: LiveRange {
                start: None,
                end: None,
            },
            id: i,
        }
    }

    /// Check if the interval is alive at position x
    /// Panics if the range is not set
    pub fn survives(&self, x: usize) -> bool {
        assert!(self.range.start.is_some() && self.range.end.is_some(), "survives called on interval with no range");
        let start = self.range.start.unwrap();
        let end = self.range.end.unwrap();
        start < x && end > x
    }

    pub fn born_at(&self, x:usize) -> bool {
        let start = self.range.start.unwrap();
        start == x
    }

    pub fn dies_at(&self, x:usize) -> bool {
        let end = self.range.end.unwrap();
        end == x
    }

    pub fn has_bounds(&self) -> bool {
        self.range.start.is_some() && self.range.end.is_some()
    }

    /// Add a range to the interval, extending it if necessary
    pub fn add_range(&mut self, from: usize, to: usize) {
        if to <= from {
            panic!("Invalid range: {} to {}", from, to);
        }

        if self.range.start.is_none() {
            self.range.start = Some(from);
            self.range.end = Some(to);
            return;
        }

        // Extend the range to cover both the existing range and the new range
        self.range.start = Some(self.range.start.unwrap().min(from));
        self.range.end = Some(self.range.end.unwrap().max(to));
    }

    /// Set the start of the range
    pub fn set_from(&mut self, from: usize) {
        let end = self.range.end.unwrap_or(from);
        self.range.start = Some(from);
        self.range.end = Some(end);
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Allocation {
    Reg(usize),
    Fixed(Reg),
    Stack(usize),
}

impl Allocation {
    fn assigned_reg(self) -> Option<Reg> {
        use crate::backend::current::ALLOC_REGS;

        match self {
            Allocation::Reg(n) => Some(ALLOC_REGS[n]),
            Allocation::Fixed(reg) => Some(reg),
            Allocation::Stack(_) => None,
        }
    }

    fn alloc_pool_index(self, num_registers: usize) -> Option<usize> {
        match self {
            Allocation::Reg(n) => Some(n),
            Allocation::Fixed(reg) => {
                use crate::backend::current::ALLOC_REGS;

                ALLOC_REGS
                    .iter()
                    .take(num_registers)
                    .position(|candidate| candidate.reg_no == reg.reg_no)
            }
            Allocation::Stack(_) => None,
        }
    }
}

/// We save NATIVE_BASE_PTR as cfp->jit_return for depth-0 JITFrame (the most
/// common case: inlining root or non-inlined ISEQ) because it's faster to read
/// the NATIVE_BASE_PTR register as is than calculating `NATIVE_BASE_PTR - 1`.
///
/// For that reason, every CFP needs to read JITFrame from cfp->jit_return[-1].
/// This constant is used when we subtract the offset.
///
/// See also: cfp_jit_return_for_depth(), CFP_ZJIT_FRAME()
const JIT_FRAME_OFFSET_FROM_JIT_RETURN: usize = 1;

/// StackState tracks the native stack layout and converts abstract stack slots
/// into concrete stack addresses.
///
/// Native stack layout:
///
/// ```text
///                                          high addr
///                                  +-------------------------+
///                                  | return address          |
///                                  +-------------------------+
///              NATIVE_BASE_PTR --> | previous frame pointer  |   <-- depth-0 cfp->jit_return ^
///                                  +-------------------------+                               | JIT_FRAME_OFFSET_FROM_JIT_RETURN
///                              ^ ^ | JITFrame slot depth 0   | ^ <-- depth-0 cfp's JITFrame  v
///                              | | +-------------------------+ |
///                              | | |          ...            | |
/// frame_depth for "depth N" in | | +-------------------------+ |
///  stack_map_index_for_spill() | | | JITFrame slot depth N-1 | | <-- depth-N cfp->jit_return ^
///                              | | +-------------------------+ |                             | JIT_FRAME_OFFSET_FROM_JIT_RETURN
///                              v | | JITFrame slot depth N   | | <-- depth-N cfp's JITFrame  v
///                                | +-------------------------+ |
///                                | |          ...            | | JITState::jit_frame_size
///                 stack_base_idx | +-------------------------+ |
///                                | | JITFrame slot depth X   | v
///                                | +-------------------------+
///                                | | opnds.last()            | ^
///                                | +-------------------------+ |
///                                | |          ...            | | stack_size in StackState::reserve_stack_slots
///                                | +-------------------------+ |
///                                v | opnds.first()           | v
///                                  +-------------------------+
///                                ^ | register spill slot 0   | ^
///                                | +-------------------------+ |
///                                | |          ...            | | stack_idx for "slot N" in StackState::stack_map_index_for_spill
///                                | +-------------------------+ |
///                num_spill_slots | | register spill slot N   | v
///                                | +-------------------------+
///                                | |          ...            |
///                                | +-------------------------+
///                                v | register spill slot X   |
///                                  +-------------------------+
///                                  | FrameSetup align slot   | if needed
///                                  +-------------------------+
///                                           low addr
/// ```
#[derive(Clone)]
pub struct StackState {
    /// The number of stack slots reserved before register allocator spills.
    pub(crate) stack_base_idx: usize,

    /// The number of stack slots needed by register allocator spills.
    pub(crate) num_spill_slots: usize,
}

impl StackState {
    /// Initialize an empty stack state.
    fn new() -> Self {
        StackState { stack_base_idx: 0, num_spill_slots: 0 }
    }

    /// Initialize a stack state with a fixed number of reserved stack slots.
    fn new_with_stack_slots(stack_base_idx: usize) -> Self {
        StackState { stack_base_idx, num_spill_slots: 0 }
    }

    /// Reserve native stack slots for JITFrame storage and stack-allocated operands.
    /// Returns the total number of reserved slots for the current allocation.
    pub(crate) fn reserve_stack_slots(&mut self, jit_frame_size: usize, stack_size: usize) -> usize {
        let total_stack_size = jit_frame_size + stack_size;
        self.stack_base_idx = self.stack_base_idx.max(total_stack_size);
        total_stack_size
    }

    /// Return the total number of native stack slots used for the frame's
    /// reserved data and register allocator spills.
    pub(crate) fn stack_slot_count(&self) -> usize {
        self.stack_base_idx + self.num_spill_slots
    }

    /// Return the stack-map index for a VReg stored below StackState-managed
    /// slots. `stack_idx` is relative to the first allocator spill slot.
    /// rb_zjit_materialize_frames() reads this as cfp->jit_return[-index].
    fn stack_map_index_for_spill(&self, stack_idx: usize, frame_depth: usize) -> usize {
        // Calculate the offset from NATIVE_BASE_PTR to the stack slot first
        let index_from_native_base_ptr = self.stack_base_idx
            .checked_add(stack_idx) // "register spill slot" index
            .and_then(|index| index.checked_add(JIT_FRAME_OFFSET_FROM_JIT_RETURN))
            .expect("StackMap index overflow");

        // Then convert it to the offset from cfp->jit_return to the stack slot
        index_from_native_base_ptr
            .checked_sub(frame_depth)
            .expect("StackMap slot must be below this frame's cfp->jit_return")
    }

    /// Return a stack index for a register saved by handle_caller_saved_regs().
    fn stack_idx_for_caller_saved_reg(&self, caller_saved_reg_idx: usize) -> usize {
        let frame_alignment_slots = self.stack_slot_count() % 2;
        self.num_spill_slots + frame_alignment_slots + caller_saved_reg_idx
    }

    /// Convert a stack index to the `disp` of the stack slot
    fn stack_idx_to_disp(&self, stack_idx: StackIdx) -> i32 {
        (self.stack_base_idx + stack_idx.to_usize() + 1) as i32 * -SIZEOF_VALUE_I32
    }

    /// Convert MemBase::Stack to Mem
    pub(super) fn stack_membase_to_mem(&self, membase: MemBase) -> Mem {
        match membase {
            MemBase::Stack { stack_idx, num_bits } => {
                let disp = self.stack_idx_to_disp(stack_idx);
                Mem { base: MemBase::Reg(NATIVE_BASE_PTR.unwrap_reg().reg_no), disp, num_bits }
            }
            _ => unreachable!(),
        }
    }
}

/// Stack map to materialize Ruby stack slots from JIT-kept values.
#[derive(Clone, Debug)]
pub struct StackMap {
    /// Ruby stack slots to reconstruct if this frame is materialized.
    /// Each operand must be either an immediate Ruby VALUE or a VReg whose
    /// final register/spill location will be encoded after register allocation.
    stack: Vec<Opnd>,
    /// Heap-allocated JITFrame whose trailing stack map storage receives the
    /// encoded entries once this CCall's register allocation is known.
    jit_frame: *const zjit_jit_frame,
    /// Inlining depth of the frame whose stack is described by this map.
    /// Stack-map indexes are decoded from that frame's cfp->jit_return.
    frame_depth: usize,
}

/// Initial capacity for asm.insns vector
const ASSEMBLER_INSNS_CAPACITY: usize = 256;

/// Object into which we assemble instructions to be
/// optimized and lowered
#[derive(Clone)]
pub struct Assembler {
    pub basic_blocks: Vec<BasicBlock>,

    /// The block to which new instructions are added. Used during HIR to LIR lowering to
    /// determine which LIR block we should add instructions to. Set by `set_current_block()`
    /// and automatically set to new entry blocks created by `new_block()`.
    current_block_id: BlockId,

    /// Number of VRegs allocated
    pub(super) num_vregs: usize,

    /// Names of labels
    pub(super) label_names: Vec<String>,

    /// If true, `push_insn` is allowed to use scratch registers.
    /// On `compile`, it also disables the backend's use of them.
    pub(super) accept_scratch_reg: bool,

    /// Native stack layout state.
    pub(crate) stack_state: StackState,

    /// If Some, the next ccall should verify its leafness
    leaf_ccall_stack_size: Option<usize>,

    /// Current instruction index, incremented for each instruction pushed
    idx: usize,

    /// Pending stack map to attach to the next CCall. The register allocator
    /// consumes this through Insn::CCall, after it knows whether each live VReg
    /// is in a saved register or an allocator spill slot.
    stack_map: Option<StackMap>,
}

impl Assembler
{
    /// Create an Assembler with defaults
    pub fn new() -> Self {
        Self {
            label_names: Vec::default(),
            accept_scratch_reg: false,
            stack_state: StackState::new(),
            leaf_ccall_stack_size: None,
            basic_blocks: Vec::default(),
            current_block_id: BlockId(0),
            num_vregs: 0,
            idx: 0,
            stack_map: None,
        }
    }

    /// Create an Assembler, reserving a specified number of stack slots
    pub fn new_with_stack_slots(stack_base_idx: usize) -> Self {
        Self { stack_state: StackState::new_with_stack_slots(stack_base_idx), ..Self::new() }
    }

    /// Create an Assembler that allows the use of scratch registers.
    /// This should be called only through [`Self::new_with_scratch_reg`].
    pub(super) fn new_with_accept_scratch_reg(accept_scratch_reg: bool) -> Self {
        Self { accept_scratch_reg, ..Self::new() }
    }

    /// Create an Assembler with parameters of another Assembler and empty instructions.
    /// Compiler passes build a next Assembler with this API and insert new instructions to it.
    pub(super) fn new_with_asm(old_asm: &Assembler) -> Self {
        let mut asm = Self::new_with_asm_without_blocks(old_asm);

        // Initialize basic blocks from the old assembler, preserving hir_block_id and entry flag
        // but with empty instruction lists
        for old_block in &old_asm.basic_blocks {
            asm.new_block_from_old_block(&old_block);
        }

        asm
    }

    /// Create an Assembler with parameters of another Assembler, but without basic blocks.
    pub(super) fn new_with_asm_without_blocks(old_asm: &Assembler) -> Self {
        let mut asm = Self {
            label_names: old_asm.label_names.clone(),
            accept_scratch_reg: old_asm.accept_scratch_reg,
            stack_state: old_asm.stack_state.clone(),
            ..Self::new()
        };

        // Initialize num_vregs to match the old assembler's size
        // This allows reusing VRegs from the old assembler
        asm.num_vregs = old_asm.num_vregs;

        asm
    }

    // Create a new LIR basic block.  Returns the newly created block ID
    pub fn new_block(&mut self, hir_block_id: hir::BlockId, is_entry: bool, rpo_index: usize) -> BlockId {
        let bb_id = BlockId(self.basic_blocks.len());
        let lir_bb = BasicBlock::new(bb_id, hir_block_id, is_entry, rpo_index);
        self.basic_blocks.push(lir_bb);
        if is_entry {
            self.set_current_block(bb_id);
        }
        bb_id
    }

    // Create a new LIR basic block from an old one.  This should only be used
    // when creating new assemblers during passes when we want to translate
    // one assembler to a new one.
    pub fn new_block_from_old_block(&mut self, old_block: &BasicBlock) -> BlockId {
        let bb_id = BlockId(self.basic_blocks.len());
        let mut lir_bb = BasicBlock::new(bb_id, old_block.hir_block_id, old_block.is_entry, old_block.rpo_index);
        lir_bb.parameters = old_block.parameters.clone();
        self.basic_blocks.push(lir_bb);
        bb_id
    }

    // Create a LIR basic block without a valid HIR block ID (for testing or internal use).
    pub fn new_block_without_id(&mut self, name: &str) -> BlockId {
        let bb_id = self.new_block(hir::BlockId(DUMMY_HIR_BLOCK_ID), true, DUMMY_RPO_INDEX);
        let label = self.new_label(name);
        self.write_label(label);
        bb_id
    }

    pub fn set_current_block(&mut self, block_id: BlockId) {
        self.current_block_id = block_id;
    }

    pub fn current_block(&mut self) -> &mut BasicBlock {
        &mut self.basic_blocks[self.current_block_id.0]
    }

    /// Return basic blocks sorted by RPO index, then by block ID.
    /// TODO: Use a more advanced scheduling algorithm
    pub fn sorted_blocks(&self) -> Vec<&BasicBlock> {
        let mut sorted: Vec<&BasicBlock> = self.basic_blocks.iter().collect();
        sorted.sort_by_key(|block| block.sort_key());
        sorted
    }

    /// Validate that jump instructions only appear as the last two instructions in each block.
    /// This is a CFG invariant that ensures proper control flow structure.
    /// Only active in debug builds.
    pub fn validate_jump_positions(&self) {
        for block in &self.basic_blocks {
            let insns = &block.insns;
            let len = insns.len();

            // Check all instructions except the last two
            for (i, insn) in insns.iter().enumerate() {
                debug_assert!(
                    !insn.is_terminator() || i >= len.saturating_sub(2),
                    "Invalid jump position in block {:?}: {:?} at position {} (block has {} instructions). \
                     Jumps must only appear in the last two positions.",
                    block.id, insn.op(), i, len
                );
            }
        }
    }

    /// Return true if `opnd` is or depends on `reg`
    pub fn has_reg(opnd: Opnd, reg: Reg) -> bool {
        match opnd {
            Opnd::Reg(opnd_reg) => opnd_reg == reg,
            Opnd::Mem(Mem { base: MemBase::Reg(reg_no), .. }) => reg_no == reg.reg_no,
            _ => false,
        }
    }

    pub fn instruction_iterator(&mut self) -> InsnIter {
        let mut blocks = take(&mut self.basic_blocks);
        blocks.sort_by_key(|block| block.sort_key());

        let mut iter = InsnIter {
            blocks,
            current_block_idx: 0,
            current_insn_iter: vec![].into_iter(), // Will be replaced immediately
            peeked: None,
            index: 0,
        };

        // Set up first block's iterator
        if !iter.blocks.is_empty() {
            iter.current_insn_iter = take(&mut iter.blocks[0].insns).into_iter();
        }

        iter
    }

    pub fn linearize_instructions(&self) -> Vec<Insn> {
        // Wrap instructions emitted by `push_insns` with PosMarkers and record
        // the emitted byte range under `symbol_name` in the perf map.
        fn push_insns_with_perf_symbol(
            insns: &mut Vec<Insn>,
            symbol_name: &str,
            push_insns: impl FnOnce(&mut Vec<Insn>),
        ) {
            // ISEQ perf symbols cover the whole compiled ISEQ, including this
            // padding. HIR perf needs a separate symbol because the padding
            // doesn't belong to any HIR instruction.
            if get_option!(perf) != Some(PerfMap::HIR) {
                push_insns(insns);
                return;
            }

            let symbol_name = symbol_name.to_string();
            let start = Rc::new(RefCell::new(None));
            let current = start.clone();
            insns.push(Insn::PosMarker(Rc::new(move |code_ptr, _| {
                let mut current = current.borrow_mut();
                assert!(current.is_none(), "perf symbol range already open");
                *current = Some(code_ptr);
            })));

            push_insns(insns);

            insns.push(Insn::PosMarker(Rc::new(move |end, cb| {
                if let Some(start) = start.borrow_mut().take() {
                    let start_addr = start.raw_addr(cb);
                    let end_addr = end.raw_addr(cb);
                    if start_addr < end_addr {
                        register_with_perf(symbol_name.clone(), start_addr, end_addr - start_addr);
                    }
                }
            })));
        }

        // Emit instructions with labels, expanding branch parameters
        let mut insns = Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY);

        let block_ids = self.block_order();
        let num_blocks = block_ids.len();

        for (i, block_id) in block_ids.iter().enumerate() {
            let block = &self.basic_blocks[block_id.0];
            // Entry blocks shouldn't ever be preceded by something that can
            // stomp on this block.
            if !block.is_entry {
                push_insns_with_perf_symbol(&mut insns, "PadPatchPoint", |insns| {
                    insns.push(Insn::PadPatchPoint);
                });
            }

            // Process each instruction, expanding branch params if needed
            for insn in &block.insns {
                self.expand_branch_insn(insn, &mut insns);
            }

            // Eliminate redundant jumps: if the last instruction is an
            // unconditional jump to the next block in the linear order,
            // remove it and let execution fall through.
            if let Some(next_block_id) = block_ids.get(i + 1) {
                let next_label = self.block_label(*next_block_id);
                if let Some(Insn::Jmp(Target::Label(label))) = insns.last() {
                    if *label == next_label {
                        insns.pop();
                    }
                }
            }

            // Make sure we don't stomp on the next function
            if block_id.0 == num_blocks - 1 {
                push_insns_with_perf_symbol(&mut insns, "PadPatchPoint", |insns| {
                    insns.push(Insn::PadPatchPoint);
                });
            }
        }
        insns
    }

    /// Expand and linearize a branch instruction:
    /// 1. If the branch has Target::Block with arguments, insert a ParallelMov first
    /// 2. Convert Target::Block to Target::Label
    /// 3. Push the converted instruction
    fn expand_branch_insn(&self, insn: &Insn, insns: &mut Vec<Insn>) {
        // Helper to process branch arguments and return the label target
        let process_edge = |edge: &BranchEdge| -> Label {
            self.block_label(edge.target)
        };

        // Convert Target::Block to Target::Label, processing args if needed
        let stripped_insn = match insn {
            Insn::Jmp(Target::Block(edge)) => Insn::Jmp(Target::Label(process_edge(edge))),
            Insn::Jz(Target::Block(edge)) => Insn::Jz(Target::Label(process_edge(edge))),
            Insn::Jnz(Target::Block(edge)) => Insn::Jnz(Target::Label(process_edge(edge))),
            Insn::Je(Target::Block(edge)) => Insn::Je(Target::Label(process_edge(edge))),
            Insn::Jne(Target::Block(edge)) => Insn::Jne(Target::Label(process_edge(edge))),
            Insn::Jl(Target::Block(edge)) => Insn::Jl(Target::Label(process_edge(edge))),
            Insn::Jg(Target::Block(edge)) => Insn::Jg(Target::Label(process_edge(edge))),
            Insn::Jge(Target::Block(edge)) => Insn::Jge(Target::Label(process_edge(edge))),
            Insn::Jbe(Target::Block(edge)) => Insn::Jbe(Target::Label(process_edge(edge))),
            Insn::Jb(Target::Block(edge)) => Insn::Jb(Target::Label(process_edge(edge))),
            Insn::Jo(Target::Block(edge)) => Insn::Jo(Target::Label(process_edge(edge))),
            Insn::JoMul(Target::Block(edge)) => Insn::JoMul(Target::Label(process_edge(edge))),
            Insn::Joz(opnd, Target::Block(edge)) => Insn::Joz(*opnd, Target::Label(process_edge(edge))),
            Insn::Jonz(opnd, Target::Block(edge)) => Insn::Jonz(*opnd, Target::Label(process_edge(edge))),
            _ => insn.clone()
        };

        // Push the stripped instruction
        insns.push(stripped_insn);
    }

    // Get the label for a given block by extracting it from the first instruction.
    pub(super) fn block_label(&self, block_id: BlockId) -> Label {
        let block = &self.basic_blocks[block_id.0];
        match block.insns.first() {
            Some(Insn::Label(Target::Label(label))) => *label,
            other => panic!("Expected first instruction of block {:?} to be a Label, but found: {:?}", block_id, other),
        }
    }

    pub fn expect_leaf_ccall(&mut self, stack_size: usize) {
        self.leaf_ccall_stack_size = Some(stack_size);
    }

    fn set_stack_canary(&mut self) -> Option<Opnd> {
        if cfg!(feature = "runtime_checks") {
            if let Some(stack_size) = self.leaf_ccall_stack_size.take() {
                let canary_addr = self.lea(Opnd::mem(64, SP, (stack_size as i32) * SIZEOF_VALUE_I32));
                let canary_opnd = Opnd::mem(64, canary_addr, 0);
                self.mov(canary_opnd, vm_stack_canary().into());
                return Some(canary_opnd)
            }
        }
        None
    }

    fn clear_stack_canary(&mut self, canary_opnd: Option<Opnd>){
        if let Some(canary_opnd) = canary_opnd {
            self.store(canary_opnd, 0.into());
        };
    }

    /// Build an Opnd::VReg
    pub fn new_vreg(&mut self, num_bits: u8) -> Opnd {
        let vreg = Opnd::VReg { idx: self.num_vregs.into(), num_bits };
        self.num_vregs += 1;
        vreg
    }

    /// Build an Opnd::VReg for use as a block parameter.
    pub fn new_block_param(&mut self, num_bits: u8) -> Opnd {
        self.new_vreg(num_bits)
    }

    /// Append an instruction onto the current list of instructions and update
    /// the live ranges of any instructions whose outputs are being used as
    /// operands to this instruction.
    pub fn push_insn(&mut self, insn: Insn) {
        // If this Assembler should not accept scratch registers, assert no use of them.
        if !self.accept_scratch_reg {
            insn.for_each_operand(|opnd| {
                assert!(!Self::has_scratch_reg(opnd), "should not use scratch register: {opnd:?}");
            });
        }

        self.idx += 1;

        self.current_block().push_insn(insn);
    }

    /// Create a new label instance that we can jump to
    pub fn new_label(&mut self, name: &str) -> Target
    {
        assert!(!name.contains(' '), "use underscores in label names, not spaces");

        let label = Label(self.label_names.len());
        self.label_names.push(name.to_string());
        Target::Label(label)
    }

    // Shuffle register moves, sometimes adding extra moves using scratch_reg,
    // so that they will not rewrite each other before they are used.
    pub fn resolve_parallel_moves(old_moves: &[(Opnd, Opnd)], scratch_opnd: Option<Opnd>) -> Option<Vec<(Opnd, Opnd)>> {
        // Return the index of a move whose destination is not used as a source if any.
        fn find_safe_move(moves: &[(Opnd, Opnd)]) -> Option<usize> {
            moves.iter().enumerate().find(|&(_, &(dst, src))| {
                // Check if `dst` is used in other moves. If `dst` is not used elsewhere, it's safe to write into `dst` now.
                moves.iter().filter(|&&other_move| other_move != (dst, src)).all(|&(other_dst, other_src)|
                    match dst {
                        Opnd::Reg(reg) => !Assembler::has_reg(other_dst, reg) && !Assembler::has_reg(other_src, reg),
                        _ => other_dst != dst && other_src != dst,
                    }
                )
            }).map(|(index, _)| index)
        }

        // Remove moves whose source and destination are the same
        let mut old_moves: Vec<(Opnd, Opnd)> = old_moves.iter().copied()
            .filter(|&(dst, src)| dst != src).collect();

        let mut new_moves = vec![];
        while !old_moves.is_empty() {
            // Keep taking safe moves
            while let Some(index) = find_safe_move(&old_moves) {
                new_moves.push(old_moves.remove(index));
            }

            // No safe move. Load the source of one move into scratch_opnd, and
            // then load scratch_opnd into the destination when it's safe.
            if !old_moves.is_empty() {
                // If scratch_opnd is None, return None and leave it to *_split_with_scratch_regs to resolve it.
                let scratch_opnd = scratch_opnd?;
                let scratch_reg = scratch_opnd.unwrap_reg();
                // Make sure it's safe to use scratch_reg
                assert!(old_moves.iter().all(|&(dst, src)| !Self::has_reg(dst, scratch_reg) && !Self::has_reg(src, scratch_reg)));

                // Move scratch_opnd <- src, and delay dst <- scratch_opnd
                let (dst, src) = old_moves.remove(0);
                new_moves.push((scratch_opnd, src));
                old_moves.push((dst, scratch_opnd));
            }
        }
        Some(new_moves)
    }

    /// Discover vregs that should preferentially reuse a physical register,
    /// such as a newborn vreg immediately moved into a preg in the next instruction.
    pub fn preferred_register_assignments(&self, intervals: &[Interval]) -> Vec<Option<Reg>> {
        let mut preferred = vec![None; self.num_vregs];

        for block in &self.basic_blocks {
            let mut prev_insn: Option<(InsnId, &Insn)> = None;

            for (insn, insn_id) in block.insns.iter().zip(block.insn_ids.iter()) {
                let Some(insn_id) = insn_id else { continue; };

                if !matches!(insn, Insn::Label(_)) {
                    if let (
                        Some((prev_id, prev)),
                        Insn::Mov {
                            dest: Opnd::Reg(dest_reg),
                            src: Opnd::VReg { idx, .. },
                        },
                    ) = (prev_insn, insn)
                    {
                        if let Some(Opnd::VReg { idx: out_idx, .. }) = prev.out_opnd() {
                            if out_idx == idx
                                && intervals[*idx].born_at(prev_id.0)
                                && intervals[*idx].dies_at(insn_id.0)
                            {
                                preferred[*idx].get_or_insert(*dest_reg);
                            }
                        }
                    }

                    prev_insn = Some((*insn_id, insn));
                }
            }
        }

        preferred
    }

    // TODO: We want to make the following refactoring so that we DON'T have
    // to parcopy in to entry blocks
    //
    // * Move Allocation to Interval
    // * Pre-allocate pinned regs
    // * Update linear scan to handle pinned LRs
    //
    pub fn linear_scan(
        &self,
        intervals: Vec<Interval>,
        num_registers: usize,
        preferred_registers: &[Option<Reg>],
    ) -> (Vec<Option<Allocation>>, usize) {
        assert_eq!(preferred_registers.len(), intervals.len());

        let mut free_registers: BTreeSet<usize> = (0..num_registers).collect();
        let mut active: Vec<&Interval> = Vec::new(); // vreg indices sorted by increasing end point
        let mut assignment: Vec<Option<Allocation>> = vec![None; intervals.len()];
        let mut num_stack_slots: usize = 0;

        // Collect vreg indices that have valid ranges, sorted by start point
        let mut sorted_intervals: Vec<Interval> = intervals.iter()
            .filter(|i| i.range.start.is_some() && i.range.end.is_some())
            .cloned()
            .collect();
        sorted_intervals.sort_by_key(|i| i.range.start.unwrap());

        for interval in &sorted_intervals {
            // Expire old intervals
            active.retain(|&active_interval| {
                if active_interval.range.end.unwrap() > interval.range.start.unwrap() {
                    true
                } else {
                    if let Some(allocation) = assignment[active_interval.id] {
                        if let Some(reg) = allocation.alloc_pool_index(num_registers) {
                            assert!(
                                free_registers.insert(reg),
                                "attempted to return allocator register {:?} to the free pool more than once",
                                allocation.assigned_reg().unwrap(),
                            );
                        } else {
                            assert!(
                                allocation.assigned_reg().is_none_or(|reg| {
                                    crate::backend::current::ALLOC_REGS
                                        .iter()
                                        .take(num_registers)
                                        .all(|candidate| candidate.reg_no != reg.reg_no)
                                }),
                                "attempted to return non-allocatable register {:?} to the allocator pool",
                                allocation.assigned_reg().unwrap(),
                            );
                        }
                    }
                    false
                }
            });

            let preferred_reg = preferred_registers[interval.id];
            let preferred_taken = preferred_reg.is_some_and(|reg| {
                active.iter().any(|active_interval| {
                    assignment[active_interval.id]
                        .and_then(|alloc| alloc.assigned_reg())
                        .is_some_and(|active_reg| active_reg.reg_no == reg.reg_no)
                })
            });

            if let Some(preferred_reg) = preferred_reg.filter(|_| !preferred_taken) {
                if let Some(reg_idx) = Allocation::Fixed(preferred_reg).alloc_pool_index(num_registers) {
                    if free_registers.remove(&reg_idx) {
                        assignment[interval.id] = Some(Allocation::Fixed(preferred_reg));
                        let insert_idx = active.partition_point(|&i| i.range.end.unwrap() < interval.range.end.unwrap());
                        active.insert(insert_idx, &interval);
                        continue;
                    }
                } else {
                    assignment[interval.id] = Some(Allocation::Fixed(preferred_reg));
                    let insert_idx = active.partition_point(|&i| i.range.end.unwrap() < interval.range.end.unwrap());
                    active.insert(insert_idx, &interval);
                    continue;
                }
            }

            if free_registers.is_empty() {
                // Spill: pick the longest-lived active interval (last in sorted active)
                // but only from the allocatable register pool. Fixed register
                // assignments represent preferred/pinned physical registers
                // (for example SP) and should not be selected as spill victims.
                let spill = active.iter().rev().copied().find(|active_interval| {
                    matches!(assignment[active_interval.id], Some(Allocation::Reg(_)))
                });
                let slot = Allocation::Stack(num_stack_slots);
                num_stack_slots += 1;

                if let Some(spill) = spill.filter(|spill| spill.range.end.unwrap() > interval.range.end.unwrap()) {
                    // Spill the last active interval; give its register to current
                    assignment[interval.id] = assignment[spill.id];
                    assignment[spill.id] = Some(slot);
                    let spill_idx = active.iter().position(|active_interval| active_interval.id == spill.id).unwrap();
                    active.remove(spill_idx);
                    // Insert current into sorted active
                    let insert_idx = active.partition_point(|&i| i.range.end.unwrap() < interval.range.end.unwrap());
                    active.insert(insert_idx, &interval);
                } else {
                    // Spill the current interval
                    assignment[interval.id] = Some(slot);
                }
            } else {
                // Allocate lowest free register
                let reg = *free_registers.iter().min().unwrap();
                free_registers.remove(&reg);
                assignment[interval.id] = Some(Allocation::Reg(reg));
                // Insert into sorted active
                let insert_idx = active.partition_point(|&i| i.range.end.unwrap() < interval.range.end.unwrap());
                active.insert(insert_idx, &interval);
            }
        }

        (assignment, num_stack_slots)
    }

    /// Resolve SSA block parameters by inserting sequentialized move instructions
    /// at block boundaries. This is SSA deconstruction: after linear_scan assigns
    /// registers/stack slots, we lower block parameter passing to explicit moves.
    pub fn resolve_ssa(&mut self, _intervals: &[Interval], assignments: &[Option<Allocation>]) {
        use crate::backend::parcopy;
        use crate::backend::current::SCRATCH_REG;

        // Count predecessors for each block
        let mut num_predecessors: HashMap<BlockId, usize> = HashMap::new();
        for block_id in self.block_order() {
            for succ in self.basic_blocks[block_id.0].successors() {
                *num_predecessors.entry(succ).or_insert(0) += 1;
            }
        }

        // Collect block order upfront so we don't borrow self while mutating
        let block_order = self.block_order();

        // This code is iterating over each block in our CFG and inserting
        // copy instructions at each edge.
        for &pred_id in &block_order {
            let pred_hir_block_id = self.basic_blocks[pred_id.0].hir_block_id;
            let pred_rpo_index = self.basic_blocks[pred_id.0].rpo_index;
            let EdgePair(edge1, edge2) = self.basic_blocks[pred_id.0].edges();

            let edges: Vec<BranchEdge> = [edge1, edge2].into_iter().flatten().collect();
            let num_successors = edges.len();

            for edge in edges {
                let successor = edge.target;
                let params = self.basic_blocks[successor.0].parameters.clone();

                // Build the list of register-to-register copies and immediate moves.
                // Rewrite VRegs to physical registers BEFORE sequentialization so
                // the parcopy algorithm can see real physical register conflicts.
                let reg_copies: Vec<parcopy::RegisterCopy<Opnd>> = edge.args
                    .iter()
                    .zip(params.iter())
                    .filter(|(_arg, param)| assignments[param.vreg_idx()].is_some() )
                    .map(|(arg, param)| parcopy::RegisterCopy::<Opnd> {
                        destination: Self::rewritten_opnd(*param, assignments),
                        source: Self::rewritten_opnd(*arg, assignments),
                    })
                    .filter(|copy| copy.source != copy.destination)
                    .collect();

                // Sequentialize register copies.
                // Copies must use physical registers, not VRegs, so the
                // parcopy algorithm can detect physical register conflicts.
                debug_assert!(reg_copies.iter().all(|c| !c.source.is_vreg() && !c.destination.is_vreg()),
                    "parcopy must operate on physical registers, not VRegs");
                let sequentialized = parcopy::sequentialize_register(&reg_copies, Opnd::Reg(SCRATCH_REG));
                let moves: Vec<Insn> = sequentialized
                    .iter()
                    .map(|copy| match copy.source {
                        Opnd::Value(_) => Insn::LoadInto { dest: copy.destination, opnd: copy.source },
                        _ => Insn::Mov { dest: copy.destination, src: copy.source },
                    })
                    .collect();

                if moves.is_empty() {
                    continue;
                }

                let num_preds = *num_predecessors.get(&successor).unwrap_or(&0);
                if num_preds > 1 && num_successors > 1 {
                    // Critical edge: create interstitial block
                    let new_block_id = self.new_block(pred_hir_block_id, false, pred_rpo_index);
                    let label = self.new_label("split");
                    self.basic_blocks[new_block_id.0].push_insn(Insn::Label(label));
                    for mov in moves {
                        self.basic_blocks[new_block_id.0].push_insn(mov);
                    }
                    self.basic_blocks[new_block_id.0].push_insn(Insn::Jmp(Target::Block(BranchEdge {
                        target: successor,
                        args: vec![],
                    })));

                    // Redirect predecessor's branch to the new block
                    let pred_insns = &mut self.basic_blocks[pred_id.0].insns;
                    for insn in pred_insns.iter_mut() {
                        if let Some(target) = insn.target_mut() {
                            if let Target::Block(e) = target {
                                if e.target == successor {
                                    e.target = new_block_id;
                                    e.args = vec![];
                                    break;
                                }
                            }
                        }
                    }
                } else if num_successors > 1 {
                    // Multi-succ: insert at start of successor (after Label)
                    for (i, mov) in moves.into_iter().enumerate() {
                        self.basic_blocks[successor.0].insns.insert(1 + i, mov);
                        self.basic_blocks[successor.0].insn_ids.insert(1 + i, None);
                    }
                } else {
                    assert_eq!(num_successors, 1);
                    // Single-succ: insert at end of predecessor before terminator
                    let len = self.basic_blocks[pred_id.0].insns.len();
                    for (i, mov) in moves.into_iter().enumerate() {
                        self.basic_blocks[pred_id.0].insns.insert(len - 1 + i, mov);
                        self.basic_blocks[pred_id.0].insn_ids.insert(len - 1 + i, None);
                    }
                }
            }
        }

        // Handle entry block parameters: move from calling-convention registers
        // to their allocated locations, just like inter-block edge moves above.
        for &block_id in &block_order {
            if !self.basic_blocks[block_id.0].is_entry { continue; }
            if self.basic_blocks[block_id.0].is_dummy() { continue; }
            let params = self.basic_blocks[block_id.0].parameters.clone();

            // JIT-to-JIT entries that would need more argument registers should
            // be unreachable because can_direct_send() refuses to call them.
            // Keep compiling the function body, but make the unsupported entry
            // abort if control ever reaches it. TODO: Remove this (Shopify/ruby#916)
            if params.len() > C_ARG_OPNDS.len() {
                let insert_pos = self.basic_blocks[block_id.0].insns.iter()
                    .position(|insn| matches!(insn, Insn::FrameSetup { .. }))
                    .or_else(|| self.basic_blocks[block_id.0].insns.iter().position(|insn| matches!(insn, Insn::Label(_))).map(|idx| idx + 1))
                    .unwrap_or(0);
                self.basic_blocks[block_id.0].insns.insert(insert_pos, Insn::Abort);
                self.basic_blocks[block_id.0].insn_ids.insert(insert_pos, None);
                continue;
            }

            // Rewrite VRegs to physical registers before sequentialization
            // so the parcopy algorithm can detect physical register conflicts.
            let reg_copies: Vec<parcopy::RegisterCopy<Opnd>> = params.iter().enumerate()
                .map(|(i, param)| parcopy::RegisterCopy::<Opnd> {
                    source: C_ARG_OPNDS[i],
                    destination: Self::rewritten_opnd(*param, assignments),
                })
                .filter(|copy| copy.source != copy.destination)
                .collect();

            debug_assert!(reg_copies.iter().all(|c| !c.source.is_vreg() && !c.destination.is_vreg()),
                "parcopy must operate on physical registers, not VRegs");
            let sequentialized = parcopy::sequentialize_register(&reg_copies, Opnd::Reg(SCRATCH_REG));
            let moves: Vec<Insn> = sequentialized
                .iter()
                .map(|copy| match copy.source {
                    Opnd::Value(_) => Insn::LoadInto {
                        dest: copy.destination,
                        opnd: copy.source,
                    },
                    _ => Insn::Mov {
                        dest: copy.destination,
                        src: copy.source,
                    },
                })
                .collect();

            // Find the position after FrameSetup to insert moves
            let insert_pos = self.basic_blocks[block_id.0].insns.iter()
                .position(|insn| matches!(insn, Insn::FrameSetup { .. }))
                .or_else(|| self.basic_blocks[block_id.0].insns.iter().position(|insn| matches!(insn, Insn::Label(_))).map(|idx| idx + 1))
                .unwrap_or(0);

            for (i, mov) in moves.into_iter().enumerate() {
                self.basic_blocks[block_id.0].insns.insert(insert_pos + i, mov);
                self.basic_blocks[block_id.0].insn_ids.insert(insert_pos + i, None);
            }
        }

        // Clear edge args on all branch instructions since the moves have been
        // materialized as explicit Mov instructions. This prevents
        // linearize_instructions from generating redundant ParallelMov instructions.
        for block_id in &block_order {
            for insn in &mut self.basic_blocks[block_id.0].insns {
                if let Some(Target::Block(edge)) = insn.target_mut() {
                    edge.args.clear();
                }
            }
        }

        self.rewrite_instructions(assignments);
    }

    /// Handle caller-saved registers around CCall instructions.
    /// For each CCall, push live caller-saved registers, set up arguments
    /// in C calling convention registers, and pop saved registers after.
    pub fn handle_caller_saved_regs(
        &mut self,
        intervals: &[Interval],
        assignments: &[Option<Allocation>],
        regs: &[Reg],
    ) {
        use crate::backend::parcopy;
        use crate::backend::current::{C_RET_OPND, SCRATCH_REG, ALLOC_REGS};

        for block_id in self.block_order() {
            let block = &mut self.basic_blocks[block_id.0];
            let old_insns = take(&mut block.insns);
            let old_ids = take(&mut block.insn_ids);

            let mut new_insns = Vec::with_capacity(old_insns.len());
            let mut new_ids = Vec::with_capacity(old_ids.len());

            for (insn, insn_id) in old_insns.into_iter().zip(old_ids.into_iter()) {
                if let Insn::CCall { opnds, stack_map, data } = insn {
                    let CCallData { out, start_marker, end_marker, fptr } = *data;
                    let insn_number = insn_id.map(|id| id.0).unwrap_or(0);
                    // Do we have a case where a ccall is emitted, but nobody
                    // uses the result?
                    let call_result_live = out.is_vreg()
                        && intervals[out.vreg_idx()]
                            .range
                            .end
                            .is_some_and(|end| end > insn_number);

                    // Build a set of VRegIds that can be referenced by JITFrame for materializing the VM stack
                    let stack_vreg_ids: HashSet<VRegId> = if let Some(StackMap { stack, .. }) = &stack_map {
                        stack.iter().filter_map(|opnd| match opnd {
                            Opnd::VReg { idx, .. } => Some(*idx),
                            _ => None,
                        }).collect()
                    } else {
                        HashSet::default()
                    };

                    // Find survivors: intervals that survive this Call instruction
                    // We need to preserve the "surviving" registers past the ccall,
                    // so we're going to push them all on the stack, then pop
                    // after we make the ccall
                    let survivors: Vec<VRegId> = intervals.iter()
                        .filter(|interval| {
                            // We need to spill register intervals on this CCall in two cases:
                            // 1) The VReg is referenced in an instruction after the CCall
                            let survives_call = interval.has_bounds() && interval.survives(insn_number);
                            // 2) The VReg is referenced by the stack map for the CCall
                            let stack_map_reg = stack_vreg_ids.contains(&interval.id);
                            let is_register = assignments[interval.id].and_then(|alloc| alloc.alloc_pool_index(ALLOC_REGS.len())).is_some();
                            is_register && (survives_call || stack_map_reg)
                        })
                        .map(|interval| interval.id)
                        .collect();

                    let survivor_regs: Vec<Opnd> = survivors.iter()
                        .map(|&s| match assignments[s].unwrap() {
                            Allocation::Reg(n) => Opnd::Reg(ALLOC_REGS[n]),
                            Allocation::Fixed(reg) => Opnd::Reg(reg),
                            _ => unreachable!(),
                        })
                        .collect();

                    // Push all survivors on the stack, pairing adjacent pushes when possible.
                    for group in survivor_regs.chunks(2) {
                        match group {
                            &[left, right] => new_insns.push(Insn::CPushPair(left, right)),
                            &[reg]         => new_insns.push(Insn::CPushPair(reg, 0.into())),
                            _ => unreachable!(),
                        }
                        new_ids.push(None);
                    }

                    if let Some(StackMap { stack, jit_frame, frame_depth }) = stack_map {
                        assert_eq!(unsafe { (*jit_frame).stack_size } as usize, stack.len());
                        for (idx, stack_opnd) in stack.iter().enumerate() {
                            let entry = match stack_opnd {
                                Opnd::UImm(value) => {
                                    let value = VALUE(*value as usize);
                                    // TODO: Investigate using a constant pool to track any value reference in the stack map
                                    assert!(value.special_const_p(), "StackMap should only materialize immediate VALUEs, but got: {value:?}");
                                    value
                                }
                                Opnd::VReg { idx: vreg, .. } => {
                                    let vreg_stack_index = match assignments[*vreg].expect("StackMap VReg should have an allocation") {
                                        Allocation::Reg(_) | Allocation::Fixed(_) => {
                                            let caller_saved_reg_idx = survivors.iter().position(|&survivor_id| survivor_id == *vreg).unwrap();
                                            let stack_idx = self.stack_state.stack_idx_for_caller_saved_reg(caller_saved_reg_idx);
                                            self.stack_state.stack_map_index_for_spill(stack_idx, frame_depth)
                                        }
                                        Allocation::Stack(stack_idx) => {
                                            self.stack_state.stack_map_index_for_spill(stack_idx, frame_depth)
                                        }
                                    };

                                    // Encode the offset as a shifted-and-tagged integer.
                                    let encoded = (vreg_stack_index << ZJIT_STACK_MAP_SHIFT) | ZJIT_STACK_MAP_VREG_TAG as usize;
                                    debug_assert!(!VALUE(encoded).special_const_p(), "encoded StackMap VReg should not look like an immediate VALUE");
                                    VALUE(encoded)
                                }
                                _ => unreachable!("unexpected operand in StackMap: {stack_opnd:?}"),
                            };
                            unsafe { (*jit_frame.cast_mut()).stack.as_mut_ptr().add(idx).write(entry); }
                        }
                    }

                    // Extract arguments from CCall, clear opnds

                    assert!(opnds.len() <= regs.len());

                    // Sequentialize argument moves: each arg goes to regs[i]
                    let reg_copies: Vec<parcopy::RegisterCopy<Opnd>> = opnds
                        .iter()
                        .zip(regs.iter())
                        .map(|(arg, param)| parcopy::RegisterCopy::<Opnd> {
                            destination: Opnd::Reg(*param),
                            source: Self::rewritten_opnd(*arg, assignments),
                        })
                        .filter(|copy| copy.source != copy.destination)
                        .collect();

                    debug_assert!(reg_copies.iter().all(|c| !c.source.is_vreg() && !c.destination.is_vreg()),
                        "parcopy must operate on physical registers, not VRegs");
                    let sequentialized = parcopy::sequentialize_register(&reg_copies, Opnd::Reg(SCRATCH_REG));

                    for copy in sequentialized {
                        new_insns.push(match copy.source {
                            Opnd::Value(_) => Insn::LoadInto { dest: copy.destination, opnd: copy.source },
                            _ => Insn::Mov { dest: copy.destination, src: copy.source },
                        });
                        new_ids.push(None);
                    }

                    // Extract PosMarkers from the CCall so they get emitted
                    // as separate instructions at the right code positions.
                    // Emit start_marker PosMarker before the CCall
                    if let Some(marker) = start_marker {
                        new_insns.push(Insn::PosMarker(marker));
                        new_ids.push(None);
                    }

                    // The CCall itself
                    new_insns.push(Insn::CCall {
                        opnds: vec![],  // We've moved everything in to ccall regs, so this should
                                        // be empty now
                        stack_map: None,
                        data: Box::new(CCallData {
                            out: C_RET_OPND,
                            start_marker: None,
                            end_marker: None,
                            fptr,
                        }),
                    });
                    new_ids.push(insn_id);

                    // Emit end_marker PosMarker after the CCall
                    if let Some(marker) = end_marker {
                        new_insns.push(Insn::PosMarker(marker));
                        new_ids.push(None);
                    }

                    if survivors.is_empty() {
                        if call_result_live {
                            // No survivors to restore -- move result directly to output.
                            let out = Self::rewritten_opnd(out, assignments);
                            new_insns.push(Insn::Mov { dest: out, src: C_RET_OPND });
                            new_ids.push(None);
                        }
                    } else {
                        if call_result_live {
                            // Save CCall result to scratch immediately, before pops
                            // can clobber either C_RET or the output register.
                            new_insns.push(Insn::Mov { dest: Opnd::Reg(SCRATCH_REG), src: C_RET_OPND });
                            new_ids.push(None);
                        }

                        // Restore all survivors in reverse stack order, pairing adjacent pops when possible.
                        for group in survivor_regs.chunks(2).rev() {
                            match group {
                                &[reg]         => new_insns.push(Insn::CPopPairInto(reg, reg)),
                                &[left, right] => new_insns.push(Insn::CPopPairInto(right, left)),
                                _ => unreachable!(),
                            }
                            new_ids.push(None);
                        }

                        if call_result_live {
                            // Move result from scratch to output AFTER all pops.
                            let out = Self::rewritten_opnd(out, assignments);
                            new_insns.push(Insn::Mov { dest: out, src: Opnd::Reg(SCRATCH_REG) });
                            new_ids.push(None);
                        }
                    }
                } else {
                    new_insns.push(insn);
                    new_ids.push(insn_id);
                }
            }

            let block = &mut self.basic_blocks[block_id.0];
            block.insns = new_insns;
            block.insn_ids = new_ids;
        }
    }

    /// Walk every instruction and replace VReg operands with the physical
    /// register (or stack slot) from the allocation assignments.
    fn rewrite_instructions(&mut self, assignments: &[Option<Allocation>]) {
        for block_id in self.block_order() {
            for insn in self.basic_blocks[block_id.0].insns.iter_mut() {
                insn.for_each_operand_mut(|opnd| {
                    Self::rewrite_opnd(opnd, assignments);
                });
                if let Some(out) = insn.out_opnd_mut() {
                    Self::rewrite_opnd(out, assignments);
                }
            }
        }
    }

    fn rewritten_opnd(mut opnd: Opnd, assignments: &[Option<Allocation>]) -> Opnd {
        Self::rewrite_opnd(&mut opnd, assignments);
        opnd
    }

    fn rewrite_opnd(opnd: &mut Opnd, assignments: &[Option<Allocation>]) {
        use crate::backend::current::ALLOC_REGS;
        let regs = &ALLOC_REGS;

        match opnd {
            Opnd::VReg { idx, num_bits } => {
                if let Some(assignment) = assignments[*idx] {
                    match assignment {
                        Allocation::Reg(n) => {
                            let mut reg = regs[n];
                            reg.num_bits = *num_bits;
                            *opnd = Opnd::Reg(reg);
                        }
                        Allocation::Fixed(mut reg) => {
                            reg.num_bits = *num_bits;
                            *opnd = Opnd::Reg(reg);
                        }
                        Allocation::Stack(n) => {
                            let num_bits = *num_bits;
                            *opnd = Opnd::Mem(Mem {
                                base: MemBase::Stack { stack_idx: n.try_into().unwrap(), num_bits },
                                disp: 0,
                                num_bits,
                            });
                        }
                    }
                } else {
                    panic!("Expected assignment for {opnd}");
                }
            }
            Opnd::Mem(Mem { base: MemBase::VReg(idx), .. }) => {
                match assignments[*idx].unwrap() {
                    Allocation::Reg(n) => {
                        if let Opnd::Mem(mem) = opnd {
                            mem.base = MemBase::Reg(regs[n].reg_no);
                        }
                    }
                    Allocation::Fixed(reg) => {
                        if let Opnd::Mem(mem) = opnd {
                            mem.base = MemBase::Reg(reg.reg_no);
                        }
                    }
                    Allocation::Stack(n) => {
                        // The VReg used as a memory base was spilled to a stack slot.
                        // Mark it as StackIndirect so arm64_scratch_split can load
                        // the pointer from the stack into a scratch register.
                        if let Opnd::Mem(mem) = opnd {
                            mem.base = MemBase::StackIndirect { stack_idx: n.try_into().unwrap() };
                        }
                    }
                }
            }
            _ => {}
        }
    }

    /// Compile the instructions down to machine code.
    /// Can fail due to lack of code memory and inopportune code placement, among other reasons.
    pub fn compile(self, cb: &mut CodeBlock) -> Result<(CodePtr, Vec<CodePtr>), CompileError> {
        #[cfg(feature = "disasm")]
        let start_addr = cb.get_write_ptr();
        let alloc_regs = Self::get_alloc_regs();
        let had_dropped_bytes = cb.has_dropped_bytes();
        let ret = self.compile_with_regs(cb, alloc_regs).inspect_err(|err| {
            // If we use too much memory to compile the Assembler, it would set cb.dropped_bytes = true.
            // To avoid failing future compilation by cb.has_dropped_bytes(), attempt to reset dropped_bytes with
            // the current zjit_alloc_bytes() which may be decreased after self is dropped in compile_with_regs().
            if *err == CompileError::OutOfMemory && !had_dropped_bytes {
                cb.update_dropped_bytes();
            }
        });

        #[cfg(feature = "disasm")]
        if let Some(dump_disasm) = crate::options::get_option_ref!(dump_disasm).filter(|_| ret.is_ok()) {
            let end_addr = cb.get_write_ptr();
            crate::disasm::dump_disasm_addr_range(cb, start_addr, end_addr, dump_disasm);
        }
        ret
    }

    /// Compile with a limited number of registers. Used only for unit tests.
    #[cfg(test)]
    pub fn compile_with_num_regs(self, cb: &mut CodeBlock, num_regs: usize) -> (CodePtr, Vec<CodePtr>) {
        let mut alloc_regs = Self::get_alloc_regs();
        let alloc_regs = alloc_regs.drain(0..num_regs).collect();
        self.compile_with_regs(cb, alloc_regs).unwrap()
    }

    /// Compile Target::SideExit and convert it into Target::Label for all instructions.
    /// Returns the exit code as a list of instructions to be appended after the main
    /// code is linearized and split.
    pub fn compile_exits(&mut self) -> Vec<Insn> {
        /// Restore VM state (cfp->pc, cfp->sp, stack, locals) for the side exit.
        fn compile_exit_save_state(asm: &mut Assembler, exit: &SideExit) {
            let SideExit { pc, stack, locals, iseq, .. } = exit;

            // Side exit blocks are not part of the CFG at the moment,
            // so we need to manually ensure that patchpoints get padded
            // so that nobody stomps on us
            asm.pad_patch_point();

            asm_comment!(asm, "save cfp->pc");
            asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), *pc);

            asm_comment!(asm, "save cfp->sp");
            asm.lea_into(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP), Opnd::mem(64, SP, stack.len() as i32 * SIZEOF_VALUE_I32));

            asm_comment!(asm, "save cfp->iseq");
            asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_ISEQ), VALUE::from(*iseq).into());

            // cfp->block_code and cfp->jit_return are cleared by the materialize_exit trampoline

            if !stack.is_empty() {
                asm_comment!(asm, "write stack slots: {}", join_opnds(&stack, ", "));
                for (idx, &opnd) in stack.iter().enumerate() {
                    asm.store(Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32), opnd);
                }
            }

            if !locals.is_empty() {
                asm_comment!(asm, "write locals: {}", join_opnds(&locals, ", "));
                for (idx, &opnd) in locals.iter().enumerate() {
                    asm.store(Opnd::mem(64, SP, (-local_size_and_idx_to_ep_offset(locals.len(), idx) - 1) * SIZEOF_VALUE_I32), opnd);
                }
            }
        }

        /// Tear down the JIT frame and return to the interpreter.
        fn compile_exit_return(asm: &mut Assembler) {
            asm_comment!(asm, "exit to the interpreter");
            asm.jmp(Target::CodePtr(ZJITState::get_materialize_exit_trampoline()));
        }

        fn compile_exit_recompile(asm: &mut Assembler, exit: &SideExit) {
            if let Some(recompile) = &exit.recompile {
                let payload = get_or_create_iseq_payload(exit.iseq);
                payload.reset_profiles_remaining(recompile.insn_idx as YarvInsnIdx);
                use crate::codegen::exit_recompile;
                asm_comment!(asm, "profile and maybe recompile");
                asm_ccall!(asm, exit_recompile,
                    EC,
                    recompile.compiled_iseq
                );
            }
        }

        /// Compile the main side-exit code.  The side exit will optionally record a traced exit
        /// stack, optionally trigger recompilation, and then return to the interpreter. Shared
        /// exits pass no trace reason so they can still be deduplicated by SideExit.
        /// IOW, we should never pass a trace reason if we expect the exit to be
        /// deduplicated.
        fn compile_exit(asm: &mut Assembler, exit: &SideExit, trace_reason: Option<SideExitReason>) {
            // Save VM state before the ccall so that
            // rb_profile_frames sees valid cfp->pc and the
            // ccall doesn't clobber caller-saved registers
            // holding stack/local operands.
            compile_exit_save_state(asm, exit);
            if trace_reason.is_some() || exit.recompile.is_some() {
                // Clear cfp->jit_return to prepare for a C call. Normally, cfp->jit_return
                // is cleared by the materialize_exit trampoline, but if we're about to
                // make a C call, we need to clear any stale JITFrame.
                asm_comment!(asm, "clear cfp->jit_return");
                asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_JIT_RETURN), 0.into());
            }
            if let Some(reason) = trace_reason {
                // Leak a CString with the reason so it's available at runtime
                let reason_cstr = std::ffi::CString::new(reason.to_string())
                    .unwrap_or_else(|_| std::ffi::CString::new("unknown").unwrap());
                let reason_ptr = reason_cstr.into_raw() as *const u8;
                asm_ccall!(asm, rb_zjit_record_exit_stack, Opnd::const_ptr(reason_ptr));
            }
            compile_exit_recompile(asm, exit);
            compile_exit_return(asm);
        }

        fn join_opnds(opnds: &Vec<Opnd>, delimiter: &str) -> String {
            opnds.iter().map(|opnd| format!("{opnd}")).collect::<Vec<_>>().join(delimiter)
        }

        // Extract targets first so that we can update instructions while referencing part of them.
        let mut targets = HashMap::new();

        for block_id in self.block_order() {
            let block = &self.basic_blocks[block_id.0];
            for (idx, insn) in block.insns.iter().enumerate() {
                if let Some(target @ Target::SideExit { .. }) = insn.target() {
                    targets.insert((block_id.0, idx), target.clone());
                }
            }
        }

        // Create a dedicated block for exit code. This block is not part of the
        // CFG (DUMMY_RPO_INDEX), so it won't be included in block_order() or
        // linearize_instructions(). Its instructions are returned to the caller
        // for appending after scratch_split.
        let saved_block = self.current_block_id;
        let exit_block = self.new_block_without_id("side_exits");

        // Map from SideExit to compiled Label. This table is used to deduplicate side exit code.
        let mut compiled_exits: HashMap<SideExit, Label> = HashMap::new();

        // Start a new perf range for side exits
        let perf_symbol = if get_option!(perf) == Some(PerfMap::HIR) {
            Some(perf_symbol_range_start(self, "side exit"))
        } else {
            None
        };

        // Mark the start of side-exit code so we can measure its size
        if !targets.is_empty() {
            self.pos_marker(move |start_pos, cb| {
                let end_pos = cb.get_write_ptr();
                let size = end_pos.as_offset() - start_pos.as_offset();
                crate::stats::incr_counter_by(crate::stats::Counter::side_exit_size, size as u64);
            });
        }

        // Measure time spent compiling side-exit LIR
        let side_exit_start = std::time::Instant::now();

        for ((block_id, idx), target) in targets {
            // Compile a side exit. Note that this is past register assignment,
            // so you can't use an instruction that returns a VReg.
            if let Target::SideExit { exit, reason } = target {
                // Only record the exit if `trace_side_exits` is defined and the counter is either the one specified
                let should_record_exit = get_option!(trace_side_exits).map(|trace| match trace {
                    TraceExits::All => true,
                    TraceExits::Counter(counter) if counter == side_exit_counter(reason) => true,
                    _ => false,
                }).unwrap_or(false);

                // If enabled, instrument exits first, and then jump to a shared exit.
                let counted_exit = if get_option!(stats) || should_record_exit || cfg!(test) {
                    let counted_exit = self.new_label("counted_exit");
                    self.write_label(counted_exit.clone());
                    asm_comment!(self, "Counted Exit: {reason}");

                    if get_option!(stats) || cfg!(test) {
                        asm_comment!(self, "increment a side exit counter");
                        self.incr_counter(Opnd::const_ptr(exit_counter_ptr(reason)), 1.into());

                        if let SideExitReason::UnhandledYARVInsn(opcode) = reason {
                            asm_comment!(self, "increment an unhandled YARV insn counter");
                            self.incr_counter(Opnd::const_ptr(exit_counter_ptr_for_opcode(opcode)), 1.into());
                        }
                    }

                    if should_record_exit {
                        compile_exit(self, &exit, Some(reason));
                    } else {
                        // If the side exit has already been compiled, jump to it.
                        // Otherwise, let it fall through and compile the exit next.
                        if let Some(&exit_label) = compiled_exits.get(&exit) {
                            self.jmp(Target::Label(exit_label));
                        }
                    }
                    Some(counted_exit)
                } else {
                    None
                };

                // Compile the shared side exit if not compiled yet
                let compiled_exit = if let Some(&compiled_exit) = compiled_exits.get(&exit) {
                    Target::Label(compiled_exit)
                } else {
                    let new_exit = self.new_label("side_exit");
                    self.write_label(new_exit.clone());
                    asm_comment!(self, "Exit: {}", exit.pc);
                    compile_exit(self, &exit, None);
                    compiled_exits.insert(*exit, new_exit.unwrap_label());
                    new_exit
                };

                *self.basic_blocks[block_id].insns[idx].target_mut().unwrap() = counted_exit.unwrap_or(compiled_exit);
            }
        }

        // Measure time spent compiling side-exit LIR
        if !compiled_exits.is_empty() {
            let nanos = side_exit_start.elapsed().as_nanos();
            crate::stats::incr_counter_by(crate::stats::Counter::compile_side_exit_time_ns, nanos as u64);
            crate::stats::incr_counter_by(crate::stats::Counter::compiled_side_exit_count, compiled_exits.len() as u64);
        }

        // Close the current perf range for side exits
        if let Some(perf_symbol) = &perf_symbol {
            perf_symbol_range_end(self, perf_symbol);
        }

        // Extract exit instructions and restore the previous current block
        let exit_insns = take(&mut self.basic_blocks[exit_block.0].insns);
        self.set_current_block(saved_block);
        exit_insns
    }

    /// Return a traversal of the block graph in reverse post-order.
    pub fn reverse_post_order(&self) -> Vec<BlockId> {
        let entry_blocks: Vec<BlockId> = self.basic_blocks.iter()
            .filter(|block| block.is_entry)
            .map(|block| block.id)
            .collect();
        let mut result = self.po_from(entry_blocks);
        result.reverse();
        result
    }

    /// Compute postorder traversal starting from the given blocks.
    /// Outbound edges are extracted from the last 0, 1, or 2 instructions (jumps).
    fn po_from(&self, starts: Vec<BlockId>) -> Vec<BlockId> {
        #[derive(PartialEq)]
        enum Action {
            VisitEdges,
            VisitSelf,
        }
        let mut result = vec![];
        let mut seen = HashSet::with_capacity(self.basic_blocks.len());
        let mut stack: Vec<_> = starts.iter().map(|&start| (start, Action::VisitEdges)).collect();
        while let Some((block, action)) = stack.pop() {
            if action == Action::VisitSelf {
                result.push(block);
                continue;
            }
            if !seen.insert(block) { continue; }
            stack.push((block, Action::VisitSelf));
            let EdgePair(edge1, edge2) = self.basic_blocks[block.0].edges();
            // Push edge2 before edge1 so that edge1 is popped first from the
            // LIFO stack, matching the visit order of a recursive DFS.
            if let Some(edge) = edge2 {
                stack.push((edge.target, Action::VisitEdges));
            }
            if let Some(edge) = edge1 {
                stack.push((edge.target, Action::VisitEdges));
            }
        }
        result
    }

    /// Number all instructions in the LIR in reverse postorder.
    /// This assigns a unique InsnId to each instruction across all blocks, skipping labels.
    /// Also sets the from/to range on each block.
    /// Returns the next available instruction ID after numbering.
    pub fn number_instructions(&mut self, start: usize) -> usize {
        let block_ids = self.block_order();
        let mut insn_id = start;
        for block_id in block_ids {
            let block = &mut self.basic_blocks[block_id.0];
            let block_start = insn_id;
            insn_id += 2;
            for (insn, id_slot) in block.insns.iter().zip(block.insn_ids.iter_mut()) {
                if matches!(insn, Insn::Label(_)) {
                    *id_slot = Some(InsnId(block_start));
                } else {
                    *id_slot = Some(InsnId(insn_id));
                    insn_id += 2;
                }
            }
            block.from = InsnId(block_start);
            block.to = InsnId(insn_id);
        }
        insn_id
    }

    /// Iterate over all instructions mutably with their block ID, instruction ID, and instruction index within the block.
    /// Returns an iterator of (BlockId, `Option<InsnId>`, usize, &mut Insn).
    pub fn iter_insns_mut(&mut self) -> impl Iterator<Item = (BlockId, Option<InsnId>, usize, &mut Insn)> {
        self.basic_blocks.iter_mut().flat_map(|block| {
            let block_id = block.id;
            block.insns.iter_mut()
                .zip(block.insn_ids.iter().copied())
                .enumerate()
                .map(move |(idx, (insn, insn_id))| (block_id, insn_id, idx, insn))
        })
    }

    /// Compute initial liveness sets (kill and gen) for the given blocks.
    /// Returns (kill_sets, gen_sets) where each is indexed by block ID.
    /// - kill: VRegs defined (written) in the block
    /// - gen: VRegs used (read) in the block before being defined
    pub fn compute_initial_liveness_sets(&self, block_ids: &[BlockId]) -> (Vec<BitSet<usize>>, Vec<BitSet<usize>>) {
        let num_blocks = self.basic_blocks.len();
        let num_vregs = self.num_vregs;

        let mut kill_sets: Vec<BitSet<usize>> = vec![BitSet::with_capacity(num_vregs); num_blocks];
        let mut gen_sets: Vec<BitSet<usize>> = vec![BitSet::with_capacity(num_vregs); num_blocks];

        for &block_id in block_ids {
            let block = &self.basic_blocks[block_id.0];
            let kill_set = &mut kill_sets[block_id.0];
            let gen_set = &mut gen_sets[block_id.0];

            // Iterate over instructions in reverse
            for insn in block.insns.iter().rev() {
                // If the instruction has an output that is a VReg, add to kill set
                if let Some(out) = insn.out_opnd() {
                    if let Opnd::VReg { idx, .. } = out {
                        kill_set.insert(idx.to_usize());
                    }
                }

                // For all input operands that are VRegs (including memory base VRegs), add to gen set
                insn.for_each_operand(|opnd| {
                    for idx in opnd.vreg_ids() {
                        assert!(!kill_set.get(idx.to_usize()));
                        gen_set.insert(idx.to_usize());
                    }
                });
            }

            // Add block parameters to kill set
            for param in &block.parameters {
                if let Opnd::VReg { idx, .. } = param {
                    kill_set.insert(idx.to_usize());
                }
            }

        }

        (kill_sets, gen_sets)
    }

    pub fn block_order(&self) -> Vec<BlockId> {
        self.reverse_post_order()
    }

    /// Calculate live intervals for each VReg.
    pub fn build_intervals(&self, live_in: Vec<BitSet<usize>>) -> Vec<Interval> {
        let num_vregs = self.num_vregs;
        let mut intervals: Vec<Interval> = (0..num_vregs)
            .map(|i| Interval::new(i.into()))
            .collect();

        let blocks = self.block_order();

        for block_id in blocks {
            let block = &self.basic_blocks[block_id.0];

            // live = union of successor.liveIn for each successor
            let mut live = BitSet::with_capacity(num_vregs);
            for succ_id in block.successors() {
                live.union_with(&live_in[succ_id.0]);
            }

            // Add out_vregs to live set
            for idx in block.out_vregs() {
                live.insert(idx.to_usize());
            }

            // For each live vreg, add entire block range
            // block.to is the first instruction of the next block
            for idx in live.iter_set_bits() {
                intervals[idx].add_range(block.from.0, block.to.0);
            }

            // Iterate instructions in reverse
            for (insn_id, insn) in block.insn_ids.iter().zip(&block.insns).rev() {
                // TODO(max): Remove labels, which are not numbered, in favor of blocks
                let Some(insn_id) = insn_id else { continue; };
                // If instruction has VReg output, set_from
                if let Some(out) = insn.out_opnd() {
                    if let Opnd::VReg { idx, .. } = out {
                        intervals[*idx].set_from(insn_id.0);
                    }
                }

                // For each VReg input (including memory base VRegs), add_range from block start to insn
                insn.for_each_operand(|opnd| {
                    for idx in opnd.vreg_ids() {
                        intervals[idx].add_range(block.from.0, insn_id.0);
                    }
                });
            }
        }

        intervals
    }

    /// Analyze liveness for all blocks using a fixed-point algorithm.
    /// Returns live_in sets for each block, indexed by block ID.
    /// A VReg is live-in to a block if it may be used before being defined.
    pub fn analyze_liveness(&self) -> Vec<BitSet<usize>> {
        // Get blocks in postorder
        let po_blocks = {
            let entry_blocks: Vec<BlockId> = self.basic_blocks.iter()
                .filter(|block| block.is_entry)
                .map(|block| block.id)
                .collect();
            self.po_from(entry_blocks)
        };

        // Compute initial gen/kill sets
        let (kill_sets, gen_sets) = self.compute_initial_liveness_sets(&po_blocks);

        let num_blocks = self.basic_blocks.len();
        let num_vregs = self.num_vregs;

        // Initialize live_in sets
        let mut live_in: Vec<BitSet<usize>> = vec![BitSet::with_capacity(num_vregs); num_blocks];

        // Fixed-point iteration
        let mut changed = true;
        while changed {
            changed = false;

            // Iterate over blocks in postorder
            for &block_id in &po_blocks {
                let block = &self.basic_blocks[block_id.0];

                // block_live = union of live_in[succ] for all successors
                let mut block_live = BitSet::with_capacity(num_vregs);
                for succ_id in block.successors() {
                    block_live.union_with(&live_in[succ_id.0]);
                }

                // block_live |= gen[block]
                block_live.union_with(&gen_sets[block_id.0]);

                // block_live &= ~kill[block]
                block_live.difference_with(&kill_sets[block_id.0]);

                // Update live_in if changed
                if !live_in[block_id.0].equals(&block_live) {
                    live_in[block_id.0] = block_live;
                    changed = true;
                }
            }
        }

        live_in
    }
}

/// Return a result of fmt::Display for Assembler without escape sequence
pub fn lir_string(asm: &Assembler) -> String {
    use crate::ttycolors::TTY_TERMINAL_COLOR;
    format!("{asm}").replace(TTY_TERMINAL_COLOR.bold_begin, "").replace(TTY_TERMINAL_COLOR.bold_end, "")
}

/// Format live intervals as a grid showing which VRegs are alive at each instruction
pub fn lir_intervals_string(asm: &Assembler, intervals: &[Interval]) -> String {
    let mut output = String::new();
    let num_vregs = intervals.len();

    let vreg_header = |output: &mut String| {
        output.push_str("         ");
        for i in 0..num_vregs {
            output.push_str(&format!(" v{:<2}", i));
        }
        output.push('\n');

        output.push_str("         ");
        for _ in 0..num_vregs {
            output.push_str(" ---");
        }
        output.push('\n');
    };

    // Collect all numbered instruction positions in RPO order
    let mut first = true;
    for block_id in asm.block_order() {
        let block = &asm.basic_blocks[block_id.0];

        // Print VReg header before each block
        if !first { output.push('\n'); }
        first = false;
        vreg_header(&mut output);

        // Print basic block label header with parameters
        let label = asm.block_label(block_id);
        if block.parameters.is_empty() {
            output.push_str(&format!("{}():\n", asm.label_names[label.0]));
        } else {
            output.push_str(&format!("{}(", asm.label_names[label.0]));
            for (idx, param) in block.parameters.iter().enumerate() {
                if idx > 0 {
                    output.push_str(", ");
                }
                output.push_str(&format!("{param}"));
            }
            output.push_str("):\n");
        }

        for (insn, insn_id) in block.insns.iter().zip(&block.insn_ids) {
            // Skip labels (they're not numbered)
            let Some(insn_id) = insn_id else { panic!("{insn:?}"); };

            // Print instruction ID
            output.push_str(&format!("i{:<6}: ", insn_id.0));

            // For each VReg, check if it's alive at this position
            for vreg_idx in 0..num_vregs {
                let is_alive = intervals[vreg_idx].range.start.is_some() &&
                               intervals[vreg_idx].range.end.is_some() &&
                               intervals[vreg_idx].survives(insn_id.0);

                let has_range = intervals[vreg_idx].range.start.is_some();
                if has_range && intervals[vreg_idx].born_at(insn_id.0) {
                    output.push_str("  v ");
                } else if has_range && intervals[vreg_idx].dies_at(insn_id.0) {
                    output.push_str("  ^ ");
                } else if is_alive {
                    output.push_str("  █ ");
                } else {
                    output.push_str("  . ");
                }
            }

            if let Insn::Label(_) = insn {
                output.push('\n');
                continue;
            }

            // Show the instruction text using compact formatting
            output.push_str(" ");

            if let Insn::Comment(comment) = insn {
                output.push_str(&format!("# {}", comment));
            } else {
                // Print output operand if any
                if let Some(out) = insn.out_opnd() {
                    output.push_str(&format!("{out} = "));
                }

                // Use the helper function to format instruction (reuses Display logic)
                output.push_str(&format_insn_compact(asm, insn));
            }

            output.push('\n');
        }
    }

    output
}

/// Format live intervals as a grid showing which VRegs are alive at each instruction
pub fn debug_intervals(asm: &Assembler, intervals: &[Interval]) -> String {
    lir_intervals_string(asm, intervals)
}

/// Helper function to format a single instruction (without the output part, which is already printed)
/// Returns a string formatted like: "OpName target operand1, operand2, ..."
fn format_insn_compact(asm: &Assembler, insn: &Insn) -> String {
    let mut output = String::new();

    // Print the instruction name
    output.push_str(insn.op());

    // Print target (before operands, to match --zjit-dump-lir format)
    if let Some(target) = insn.target() {
        match target {
            Target::CodePtr(code_ptr) => output.push_str(&format!(" {code_ptr:?}")),
            Target::Label(Label(label_idx)) => output.push_str(&format!(" {}", asm.label_names[*label_idx])),
            Target::SideExit { reason, .. } => output.push_str(&format!(" Exit({reason})")),
            Target::Block(edge) => {
                let label = asm.block_label(edge.target);
                let name = &asm.label_names[label.0];
                if edge.args.is_empty() {
                    output.push_str(&format!(" {name}"));
                } else {
                    output.push_str(&format!(" {name}("));
                    for (i, arg) in edge.args.iter().enumerate() {
                        if i > 0 {
                            output.push_str(", ");
                        }
                        output.push_str(&format!("{}", arg));
                    }
                    output.push_str(")");
                }
            }
        }
    }

    // Print operands (but skip branch args since they're already printed with target)
    if let Some(Target::SideExit { .. }) = insn.target() {
        match insn {
            Insn::Joz(opnd, _) |
            Insn::Jonz(opnd, _) |
            Insn::LeaJumpTarget { out: opnd, target: _ } => {
                output.push_str(&format!(", {opnd}"));
            }
            _ => {}
        }
    } else if let Some(Target::Block(_)) = insn.target() {
        match insn {
            Insn::Joz(opnd, _) |
            Insn::Jonz(opnd, _) |
            Insn::LeaJumpTarget { out: opnd, target: _ } => {
                output.push_str(&format!(", {opnd}"));
            }
            _ => {}
        }
    } else if insn.opnd_count() > 0 {
        let mut sep = "";
        insn.for_each_operand(|opnd| {
            output.push_str(&format!("{sep}{opnd}"));
            sep = ", ";
        });
    }

    output
}

impl fmt::Display for Assembler {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        // Count the number of duplicated label names to disambiguate them if needed
        let mut label_counts: HashMap<&String, usize> = HashMap::new();
        let colors = crate::ttycolors::get_colors();
        let bold_begin = colors.bold_begin;
        let bold_end = colors.bold_end;
        for label_name in self.label_names.iter() {
            let counter = label_counts.entry(label_name).or_insert(0);
            *counter += 1;
        }

        /// Return a label name String. Suffix "_{label_idx}" if the label name is used multiple times.
        fn label_name(asm: &Assembler, label_idx: usize, label_counts: &HashMap<&String, usize>) -> String {
            let label_name = &asm.label_names[label_idx];
            let label_count = label_counts.get(&label_name).unwrap_or(&0);
            if *label_count > 1 {
                format!("{label_name}_{label_idx}")
            } else {
                label_name.to_string()
            }
        }

        // Use sorted_blocks() instead of block_order() because block_order()
        // calls rpo() -> edges() which requires all blocks end with terminators.
        // After arm64_scratch_split, blocks may not have terminators.
        for bb in self.sorted_blocks() {
            let params = &bb.parameters;
            for (insn_id, insn) in bb.insn_ids.iter().zip(&bb.insns) {
                if let Some(id) = insn_id {
                    write!(f, "{id}: ")?;
                } else {
                    write!(f, "    ")?;
                }
                match insn {
                    Insn::Comment(comment) => {
                        writeln!(f, "    {bold_begin}# {comment}{bold_end}")?;
                    }
                    Insn::Label(target) => {
                        let Target::Label(Label(label_idx)) = target else {
                            panic!("unexpected target for Insn::Label: {target:?}");
                        };
                        write!(f, "  {}(", label_name(self, *label_idx, &label_counts))?;
                        for (idx, param) in params.iter().enumerate() {
                            if idx > 0 {
                                write!(f, ", ")?;
                            }
                            write!(f, "{param}")?;
                        }
                        writeln!(f, "):")?;
                    }
                    _ => {
                        write!(f, "    ")?;

                        // Print output operand if any
                        if let Some(out) = insn.out_opnd() {
                            write!(f, "{out} = ")?;
                        }

                        // Print the instruction name
                        write!(f, "{}", insn.op())?;

                        // Show slot_count for FrameSetup
                        if let Insn::FrameSetup { slot_count, preserved } = insn {
                            write!(f, " {slot_count}")?;
                            if !preserved.is_empty() {
                                write!(f, ",")?;
                            }
                        }

                        // Print target
                        if let Some(target) = insn.target() {
                            match target {
                                Target::CodePtr(code_ptr) => write!(f, " {code_ptr:?}")?,
                                Target::Label(Label(label_idx)) => write!(f, " {}", label_name(self, *label_idx, &label_counts))?,
                                Target::SideExit { reason, .. } => write!(f, " Exit({reason})")?,
                                Target::Block(edge) => {
                                    let label = self.block_label(edge.target);
                                    let name = label_name(self, label.0, &label_counts);
                                    if edge.args.is_empty() {
                                        write!(f, " {name}")?;
                                    } else {
                                        write!(f, " {name}(")?;
                                        for (i, arg) in edge.args.iter().enumerate() {
                                            if i > 0 {
                                                write!(f, ", ")?;
                                            }
                                            write!(f, "{}", arg)?;
                                        }
                                        write!(f, ")")?;
                                    }
                                }
                            }
                        }

                        // Print list of operands
                        if let Some(Target::SideExit { .. }) = insn.target() {
                            // If the instruction has a SideExit, avoid using opnd_iter(), which has stack/locals.
                            // Here, only handle instructions that have both Opnd and Target.
                            match insn {
                                Insn::Joz(opnd, _) |
                                Insn::Jonz(opnd, _) |
                                Insn::LeaJumpTarget { out: opnd, target: _ } => {
                                    write!(f, ", {opnd}")?;
                                }
                                _ => {}
                            }
                        } else if let Some(Target::Block(_)) = insn.target() {
                            // If the instruction has a Block target, avoid using opnd_iter() for branch args
                            // since they're already printed inline with the target. Only print non-target operands.
                            match insn {
                                Insn::Joz(opnd, _) |
                                Insn::Jonz(opnd, _) |
                                Insn::LeaJumpTarget { out: opnd, target: _ } => {
                                    write!(f, ", {opnd}")?;
                                }
                                _ => {}
                            }
                        } else if insn.opnd_count() > 0 {
                            let mut sep = " ";
                            insn.try_for_each_operand(|opnd| {
                                let result = write!(f, "{sep}{opnd}");
                                sep = ", ";
                                result
                            })?;
                        }

                        write!(f, "\n")?;
                    }
                }
            }
        }
        Ok(())
    }
}

impl fmt::Debug for Assembler {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        writeln!(fmt, "Assembler")?;

        for (idx, insn) in self.linearize_instructions().iter().enumerate() {
            writeln!(fmt, "    {idx:03} {insn:?}")?;
        }

        Ok(())
    }
}

pub struct InsnIter {
    blocks: Vec<BasicBlock>,
    current_block_idx: usize,
    current_insn_iter: std::vec::IntoIter<Insn>,
    peeked: Option<(usize, Insn)>,
    index: usize,
}

impl InsnIter {
    // We're implementing our own peek() because we don't want peek to
    // cross basic blocks as we're iterating.
    pub fn peek(&mut self) -> Option<&(usize, Insn)> {
        // If we don't have a peeked value, get one
        if self.peeked.is_none() {
            let insn = self.current_insn_iter.next()?;
            let idx = self.index;
            self.index += 1;
            self.peeked = Some((idx, insn));
        }
        // Return a reference to the peeked value
        self.peeked.as_ref()
    }

    // Get the next instruction, advancing to the next block when current block is exhausted.
    // Sets the current block on new_asm when moving to a new block.
    pub fn next(&mut self, new_asm: &mut Assembler) -> Option<(usize, Insn)> {
        // If we have a peeked value, return it
        if let Some(item) = self.peeked.take() {
            return Some(item);
        }

        // Try to get the next instruction from current block
        if let Some(insn) = self.current_insn_iter.next() {
            let idx = self.index;
            self.index += 1;
            return Some((idx, insn));
        }

        // Current block is exhausted, move to next block
        self.current_block_idx += 1;
        if self.current_block_idx >= self.blocks.len() {
            return None;
        }

        // Set up the next block
        let next_block = &mut self.blocks[self.current_block_idx];
        new_asm.set_current_block(next_block.id);

        self.current_insn_iter = take(&mut next_block.insns).into_iter();

        // Get first instruction from the new block
        let insn = self.current_insn_iter.next()?;
        let idx = self.index;
        self.index += 1;
        Some((idx, insn))
    }
}

impl Assembler {
    #[must_use]
    pub fn add(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Add { left, right, out });
        out
    }

    pub fn add_into(&mut self, left: Opnd, right: Opnd) {
        assert!(matches!(left, Opnd::Reg(_)), "Destination of add_into must be Opnd::Reg, but got: {left:?}");
        self.push_insn(Insn::Add { left, right, out: left });
    }

    #[must_use]
    pub fn and(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::And { left, right, out });
        out
    }

    pub fn bake_string(&mut self, text: &str) {
        self.push_insn(Insn::BakeString(text.to_string()));
    }

    pub fn is_ruby_code(&self) -> bool {
        self.basic_blocks.len() > 1 || !self.basic_blocks[0].is_dummy()
    }

    #[allow(dead_code)]
    pub fn breakpoint(&mut self) {
        self.push_insn(Insn::Breakpoint);
    }

    #[allow(dead_code)]
    pub fn abort(&mut self) {
        self.push_insn(Insn::Abort);
    }

    /// Call a C function without PosMarkers
    pub fn ccall(&mut self, fptr: *const u8, opnds: Vec<Opnd>) -> Opnd {
        let canary_opnd = self.set_stack_canary();
        let out = self.new_vreg(Opnd::match_num_bits(&opnds));
        let fptr = Opnd::const_ptr(fptr);
        let stack_map = self.stack_map.take();
        self.push_insn(Insn::CCall { opnds, stack_map, data: Box::new(CCallData { fptr, start_marker: None, end_marker: None, out }) });
        self.clear_stack_canary(canary_opnd);
        out
    }

    /// Call a C function into an explicit output operand without allocating a
    /// new vreg for the result.
    pub fn ccall_into(&mut self, out: Opnd, fptr: *const u8, opnds: Vec<Opnd>) {
        let fptr = Opnd::const_ptr(fptr);
        let stack_map = self.stack_map.take();
        self.push_insn(Insn::CCall { opnds, stack_map, data: Box::new(CCallData { fptr, start_marker: None, end_marker: None, out }) });
    }

    /// Call a C function stored in a register
    pub fn ccall_reg(&mut self, fptr: Opnd, num_bits: u8) -> Opnd {
        assert!(matches!(fptr, Opnd::Reg(_)), "ccall_reg must be called with Opnd::Reg: {fptr:?}");
        let out = self.new_vreg(num_bits);
        let stack_map = self.stack_map.take();
        self.push_insn(Insn::CCall { opnds: vec![], stack_map, data: Box::new(CCallData { fptr, start_marker: None, end_marker: None, out }) });
        out
    }

    /// Call a C function with PosMarkers. This is used for recording the start and end
    /// addresses of the C call and rewriting it with a different function address later.
    pub fn ccall_with_pos_markers(
        &mut self,
        fptr: *const u8,
        opnds: Vec<Opnd>,
        start_marker: impl Fn(CodePtr, &CodeBlock) + 'static,
        end_marker: impl Fn(CodePtr, &CodeBlock) + 'static,
    ) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&opnds));
        let stack_map = self.stack_map.take();
        self.push_insn(Insn::CCall {
            opnds,
            stack_map,
            data: Box::new(CCallData {
                fptr: Opnd::const_ptr(fptr),
                start_marker: Some(Rc::new(start_marker)),
                end_marker: Some(Rc::new(end_marker)),
                out,
            }),
        });
        out
    }

    pub fn count_call_to(&mut self, fn_name: &str) {
        // We emit ccalls while initializing the JIT. Unfortunately, we skip those because
        // otherwise we have no counter pointers to read.
        if crate::state::ZJITState::has_instance() && get_option!(stats) {
            let ccall_counter_pointers = crate::state::ZJITState::get_ccall_counter_pointers();
            let counter_ptr = ccall_counter_pointers.entry(fn_name.to_string()).or_insert_with(|| Box::new(0));
            let counter_ptr: &mut u64 = counter_ptr.as_mut();
            self.incr_counter(Opnd::const_ptr(counter_ptr), 1.into());
        }
    }

    pub fn cmp(&mut self, left: Opnd, right: Opnd) {
        self.push_insn(Insn::Cmp { left, right });
    }

    #[must_use]
    pub fn cpop(&mut self) -> Opnd {
        let out = self.new_vreg(Opnd::DEFAULT_NUM_BITS);
        self.push_insn(Insn::CPop { out });
        out
    }

    pub fn cpop_into(&mut self, opnd: Opnd) {
        assert!(matches!(opnd, Opnd::Reg(_)), "Destination of cpop_into must be a register, got: {opnd:?}");
        self.push_insn(Insn::CPopInto(opnd));
    }

    #[track_caller]
    pub fn cpop_pair_into(&mut self, opnd0: Opnd, opnd1: Opnd) {
        assert!(matches!(opnd0, Opnd::Reg(_) | Opnd::VReg{ .. }), "Destination of cpop_pair_into must be a register, got: {opnd0:?}");
        assert!(matches!(opnd1, Opnd::Reg(_) | Opnd::VReg{ .. }), "Destination of cpop_pair_into must be a register, got: {opnd1:?}");
        self.push_insn(Insn::CPopPairInto(opnd0, opnd1));
    }

    pub fn cpush(&mut self, opnd: Opnd) {
        self.push_insn(Insn::CPush(opnd));
    }

    #[track_caller]
    pub fn cpush_pair(&mut self, opnd0: Opnd, opnd1: Opnd) {
        assert!(matches!(opnd0, Opnd::Reg(_) | Opnd::VReg{ .. }), "Destination of cpush_pair must be a register, got: {opnd0:?}");
        assert!(matches!(opnd1, Opnd::Reg(_) | Opnd::VReg{ .. }), "Destination of cpush_pair must be a register, got: {opnd1:?}");
        self.push_insn(Insn::CPushPair(opnd0, opnd1));
    }

    pub fn cret(&mut self, opnd: Opnd) {
        self.push_insn(Insn::CRet(opnd));
    }

    #[must_use]
    pub fn csel_e(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_g(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelG { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_ge(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelGE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_l(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelL { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_le(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelLE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_ne(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelNE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_nz(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelNZ { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_z(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelZ { truthy, falsy, out });
        out
    }

    pub fn frame_setup(&mut self, preserved_regs: &'static [Opnd]) {
        let slot_count = self.stack_state.stack_slot_count();
        self.push_insn(Insn::FrameSetup { preserved: preserved_regs, slot_count });
    }

    /// The inverse of [Self::frame_setup] used before return. `reserve_bytes`
    /// not necessary since we use a base pointer register.
    pub fn frame_teardown(&mut self, preserved_regs: &'static [Opnd]) {
        self.push_insn(Insn::FrameTeardown { preserved: preserved_regs });
    }

    pub fn incr_counter(&mut self, mem: Opnd, value: Opnd) {
        self.push_insn(Insn::IncrCounter { mem, value });
    }

    pub fn jb(&mut self, target: Target) {
        self.push_insn(Insn::Jb(target));
    }

    #[allow(dead_code)]
    pub fn jg(&mut self, target: Target) {
        self.push_insn(Insn::Jg(target));
    }

    pub fn jmp(&mut self, target: Target) {
        self.push_insn(Insn::Jmp(target));
    }

    pub fn jmp_opnd(&mut self, opnd: Opnd) {
        self.push_insn(Insn::JmpOpnd(opnd));
    }


    #[must_use]
    pub fn lea(&mut self, opnd: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::Lea { opnd, out });
        out
    }

    pub fn lea_into(&mut self, out: Opnd, opnd: Opnd) {
        assert!(matches!(out, Opnd::Reg(_) | Opnd::Mem(_)), "Destination of lea_into must be a register or memory, got: {out:?}");
        self.push_insn(Insn::Lea { opnd, out });
    }

    #[must_use]
    pub fn lea_jump_target(&mut self, target: Target) -> Opnd {
        let out = self.new_vreg(Opnd::DEFAULT_NUM_BITS);
        self.push_insn(Insn::LeaJumpTarget { target, out });
        out
    }

    #[must_use]
    pub fn load(&mut self, opnd: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::Load { opnd, out });
        out
    }

    pub fn load_into(&mut self, dest: Opnd, opnd: Opnd) {
        assert!(matches!(dest, Opnd::Reg(_)), "Destination of load_into must be a register, got: {dest:?}");
        match (dest, opnd) {
            (Opnd::Reg(dest), Opnd::Reg(opnd)) if dest == opnd => {}, // skip if noop
            _ => self.push_insn(Insn::LoadInto { dest, opnd }),
        }
    }

    #[must_use]
    pub fn load_sext(&mut self, opnd: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::LoadSExt { opnd, out });
        out
    }

    #[must_use]
    pub fn lshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::LShift { opnd, shift, out });
        out
    }

    pub fn mov(&mut self, dest: Opnd, src: Opnd) {
        assert!(!matches!(dest, Opnd::VReg { .. }), "Destination of mov must not be Opnd::VReg, got: {dest:?}");
        self.push_insn(Insn::Mov { dest, src });
    }

    #[must_use]
    pub fn not(&mut self, opnd: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::Not { opnd, out });
        out
    }

    #[must_use]
    pub fn or(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Or { left, right, out });
        out
    }

    pub fn patch_point(&mut self, target: Target, invariant: Invariant, version: IseqVersionRef) {
        self.push_insn(Insn::PatchPoint(Box::new(PatchPointData { target, invariant, version })));
    }

    pub fn pad_patch_point(&mut self) {
        self.push_insn(Insn::PadPatchPoint);
    }

    pub fn pos_marker(&mut self, marker_fn: impl Fn(CodePtr, &CodeBlock) + 'static) {
        self.push_insn(Insn::PosMarker(Rc::new(marker_fn)));
    }

    #[must_use]
    pub fn rshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::RShift { opnd, shift, out });
        out
    }

    /// Attach a stack map to the next CCall emitted by this Assembler.
    /// The map is queued here because gen_stack_map() runs before the CCall is
    /// emitted, but the map is filled only after register allocation assigns
    /// locations to the VRegs it references.
    ///
    /// `frame_depth` is temporary plumbing for inlined HIR functions. Since one
    /// HIR function currently reserves multiple native JITFrame slots, one per
    /// inlining depth, stack-map indexes must be encoded relative to the target
    /// frame's own cfp->jit_return.
    pub fn stack_map(&mut self, stack: Vec<Opnd>, jit_frame: *const zjit_jit_frame, frame_depth: usize) {
        assert!(self.stack_map.is_none());
        self.stack_map = Some(StackMap { stack, jit_frame, frame_depth });
    }

    pub fn store(&mut self, dest: Opnd, src: Opnd) {
        assert!(!matches!(dest, Opnd::VReg { .. }), "Destination of store must not be Opnd::VReg, got: {dest:?}");
        self.push_insn(Insn::Store { dest, src });
    }

    #[must_use]
    pub fn sub(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Sub { left, right, out });
        out
    }

    pub fn sub_into(&mut self, left: Opnd, right: Opnd) {
        assert!(matches!(left, Opnd::Reg(_)), "Destination of sub_into must be Opnd::Reg, but got: {left:?}");
        self.push_insn(Insn::Sub { left, right, out: left });
    }

    #[must_use]
    pub fn mul(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Mul { left, right, out });
        out
    }

    pub fn test(&mut self, left: Opnd, right: Opnd) {
        self.push_insn(Insn::Test { left, right });
    }

    #[must_use]
    #[allow(dead_code)]
    pub fn urshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::URShift { opnd, shift, out });
        out
    }

    /// Add a label at the current position
    pub fn write_label(&mut self, target: Target) {
        assert!(target.unwrap_label().0 < self.label_names.len());
        self.push_insn(Insn::Label(target));
    }

    #[must_use]
    pub fn xor(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Xor { left, right, out });
        out
    }

    /// This is used for trampolines that don't allow scratch registers.
    /// Linearizes all blocks into a single giant block.
    pub fn resolve_parallel_mov_pass(self) -> Assembler {
        let mut asm_local = Assembler::new_with_asm_without_blocks(&self);

        // Create one giant block to linearize everything into
        asm_local.new_block_without_id("linearized");

        // Get linearized instructions with branch parameters expanded into ParallelMov
        let linearized_insns = self.linearize_instructions();

        // TODO: Aaron, this could be better. We don't need to do this, FIXME
        // Process each linearized instruction
        for insn in linearized_insns {
            match insn {
                Insn::Mov { dest, src } => {
                    if src != dest {
                        asm_local.push_insn(insn);
                    }
                },
                _ => {
                    asm_local.push_insn(insn);
                }
            }
        }

        asm_local
    }
}

/// Macro to use format! for Insn::Comment, which skips a format! call
/// when not dumping disassembly.
macro_rules! asm_comment {
    ($asm:expr, $($fmt:tt)*) => {
        // If --zjit-dump-disasm or --zjit-dump-lir is given, enrich them with comments.
        // Also allow --zjit-debug on dev builds to enable comments since dev builds dump LIR on panic.
        let enable_comment = $crate::options::get_option_ref!(dump_disasm).is_some() ||
            $crate::options::get_option!(dump_lir).is_some() ||
            (cfg!(debug_assertions) && $crate::options::get_option!(debug));
        if enable_comment {
            $asm.push_insn(crate::backend::lir::Insn::Comment(format!($($fmt)*)));
        }
    };
}
pub(crate) use asm_comment;

/// Convenience macro over [`Assembler::ccall`] that also adds a comment with the function name.
macro_rules! asm_ccall {
    [$asm: ident, $fn_name:ident, $($args:expr),* ] => {{
        $crate::backend::lir::asm_comment!($asm, concat!("call ", stringify!($fn_name)));
        $asm.count_call_to(stringify!($fn_name));
        $asm.ccall($fn_name as *const u8, vec![$($args),*])
    }};
}
pub(crate) use asm_ccall;

#[cfg(test)]
mod tests {
    use super::*;
    use insta::assert_snapshot;
    use crate::backend::current::NATIVE_STACK_PTR;

    fn scratch_reg() -> Opnd {
        Assembler::new_with_scratch_reg().1
    }

    #[test]
    fn test_size_of_insn() {
        // PatchPoint's cold fields are boxed (see `PatchPointData`), so it no longer
        // dominates the enum size.
        assert_eq!(std::mem::size_of::<Insn>(), 72);
    }

    #[test]
    fn test_size_of_opnd() {
        assert_eq!(std::mem::size_of::<VRegId>(), 4);
        assert_eq!(std::mem::size_of::<MemBase>(), 8);
        assert_eq!(std::mem::size_of::<Mem>(), 16);
        assert_eq!(std::mem::size_of::<Opnd>(), 16);
    }

    #[test]
    fn test_for_each_operand() {
        let insn = Insn::Add { left: Opnd::None, right: Opnd::None, out: Opnd::None };

        let mut result = vec![];
        insn.for_each_operand(|opnd| result.push(opnd));
        assert_eq!(result, vec![Opnd::None, Opnd::None]);
    }

    #[test]
    fn test_for_each_operand_mut() {
        let mut insn = Insn::Add { left: Opnd::None, right: Opnd::None, out: Opnd::None };

        let mut counter = 0;
        insn.for_each_operand_mut(|opnd| {
            *opnd = Opnd::Imm(counter);
            counter += 1;
        });
        assert!(matches!(insn, Insn::Add { left: Opnd::Imm(0), right: Opnd::Imm(1), out: Opnd::None }));
        let mut result = vec![];
        insn.for_each_operand(|opnd| result.push(opnd));
        assert_eq!(result, vec![Opnd::Imm(0), Opnd::Imm(1)]);
    }

    #[test]
    #[should_panic]
    fn load_into_memory_is_invalid() {
        let mut asm = Assembler::new();
        let mem = Opnd::mem(64, SP, 0);
        asm.load_into(mem, mem);
    }

    #[test]
    fn test_resolve_parallel_moves_reorder_registers() {
        let result = Assembler::resolve_parallel_moves(&[
            (C_ARG_OPNDS[0], SP),
            (C_ARG_OPNDS[1], C_ARG_OPNDS[0]),
        ], None);
        assert_eq!(result, Some(vec![
            (C_ARG_OPNDS[1], C_ARG_OPNDS[0]),
            (C_ARG_OPNDS[0], SP),
        ]));
    }

    #[test]
    fn test_resolve_parallel_moves_give_up_register_cycle() {
        // If scratch_opnd is not given, it cannot break cycles.
        let result = Assembler::resolve_parallel_moves(&[
            (C_ARG_OPNDS[0], C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], C_ARG_OPNDS[0]),
        ], None);
        assert_eq!(result, None);
    }

    #[test]
    fn test_resolve_parallel_moves_break_register_cycle() {
        let scratch_reg = scratch_reg();
        let result = Assembler::resolve_parallel_moves(&[
            (C_ARG_OPNDS[0], C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], C_ARG_OPNDS[0]),
        ], Some(scratch_reg));
        assert_eq!(result, Some(vec![
            (scratch_reg, C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], C_ARG_OPNDS[0]),
            (C_ARG_OPNDS[0], scratch_reg),
        ]));
    }

    #[test]
    fn test_resolve_parallel_moves_break_memory_memory_cycle() {
        let scratch_reg = scratch_reg();
        let result = Assembler::resolve_parallel_moves(&[
            (Opnd::mem(64, C_ARG_OPNDS[0], 0), C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], Opnd::mem(64, C_ARG_OPNDS[0], 0)),
        ], Some(scratch_reg));
        assert_eq!(result, Some(vec![
            (scratch_reg, C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], Opnd::mem(64, C_ARG_OPNDS[0], 0)),
            (Opnd::mem(64, C_ARG_OPNDS[0], 0), scratch_reg),
        ]));
    }

    #[test]
    fn test_resolve_parallel_moves_break_register_memory_cycle() {
        let scratch_reg = scratch_reg();
        let result = Assembler::resolve_parallel_moves(&[
            (C_ARG_OPNDS[0], C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], Opnd::mem(64, C_ARG_OPNDS[0], 0)),
        ], Some(scratch_reg));
        assert_eq!(result, Some(vec![
            (scratch_reg, C_ARG_OPNDS[1]),
            (C_ARG_OPNDS[1], Opnd::mem(64, C_ARG_OPNDS[0], 0)),
            (C_ARG_OPNDS[0], scratch_reg),
        ]));
    }

    #[test]
    fn test_resolve_parallel_moves_reorder_memory_destination() {
        let scratch_reg = scratch_reg();
        let result = Assembler::resolve_parallel_moves(&[
            (C_ARG_OPNDS[0], SP),
            (Opnd::mem(64, C_ARG_OPNDS[0], 0), CFP),
        ], Some(scratch_reg));
        assert_eq!(result, Some(vec![
            (Opnd::mem(64, C_ARG_OPNDS[0], 0), CFP),
            (C_ARG_OPNDS[0], SP),
        ]));
    }

    #[test]
    #[should_panic]
    fn test_resolve_parallel_moves_into_same_register() {
        Assembler::resolve_parallel_moves(&[
            (C_ARG_OPNDS[0], SP),
            (C_ARG_OPNDS[0], CFP),
        ], Some(scratch_reg()));
    }

    #[test]
    #[should_panic]
    fn test_resolve_parallel_moves_into_same_memory() {
        Assembler::resolve_parallel_moves(&[
            (Opnd::mem(64, C_ARG_OPNDS[0], 0), SP),
            (Opnd::mem(64, C_ARG_OPNDS[0], 0), CFP),
        ], Some(scratch_reg()));
    }

    // Helper function to convert a BitSet to a list of vreg indices
    fn bitset_to_vreg_indices(bitset: &BitSet<usize>, num_vregs: usize) -> Vec<usize> {
        (0..num_vregs)
            .filter(|&idx| bitset.get(idx))
            .collect()
    }

    struct TestFunc {
        asm: Assembler,
        r10: Opnd,
        r11: Opnd,
        r12: Opnd,
        r13: Opnd,
        r14: Opnd,
        r15: Opnd,
        b1: BlockId,
        b2: BlockId,
        b3: BlockId,
        b4: BlockId,
    }

    fn build_func() -> TestFunc {
        let mut asm = Assembler::new();

        // Create virtual registers - these will be parameters
        let r10 = asm.new_vreg(64);
        let r11 = asm.new_vreg(64);
        let r12 = asm.new_vreg(64);
        let r13 = asm.new_vreg(64);

        // Create blocks
        let b1 = asm.new_block(hir::BlockId(0), true, 0);
        let b2 = asm.new_block(hir::BlockId(1), false, 1);
        let b3 = asm.new_block(hir::BlockId(2), false, 2);
        let b4 = asm.new_block(hir::BlockId(3), false, 3);

        // Build b1: define(r10, r11) { jump(edge(b2, [imm(1), r11])) }
        asm.set_current_block(b1);
        let label_b1 = asm.new_label("bb0");
        asm.write_label(label_b1);
        asm.basic_blocks[b1.0].add_parameter(r10);
        asm.basic_blocks[b1.0].add_parameter(r11);
        asm.basic_blocks[b1.0].push_insn(Insn::Jmp(Target::Block(BranchEdge {
            target: b2,
            args: vec![Opnd::UImm(1), r11],
        })));

        // Build b2: define(r12, r13) { cmp(r13, imm(1)); blt(...) }
        asm.set_current_block(b2);
        let label_b2 = asm.new_label("bb1");
        asm.write_label(label_b2);
        asm.basic_blocks[b2.0].add_parameter(r12);
        asm.basic_blocks[b2.0].add_parameter(r13);
        asm.basic_blocks[b2.0].push_insn(Insn::Cmp { left: r13, right: Opnd::UImm(1) });
        asm.basic_blocks[b2.0].push_insn(Insn::Jl(Target::Block(BranchEdge { target: b4, args: vec![] })));
        asm.basic_blocks[b2.0].push_insn(Insn::Jmp(Target::Block(BranchEdge { target: b3, args: vec![] })));

        // Build b3: r14 = mul(r12, r13); r15 = sub(r13, imm(1)); jump(edge(b2, [r14, r15]))
        asm.set_current_block(b3);
        let label_b3 = asm.new_label("bb2");
        asm.write_label(label_b3);
        let r14 = asm.new_vreg(64);
        let r15 = asm.new_vreg(64);
        asm.basic_blocks[b3.0].push_insn(Insn::Mul { left: r12, right: r13, out: r14 });
        asm.basic_blocks[b3.0].push_insn(Insn::Sub { left: r13, right: Opnd::UImm(1), out: r15 });
        asm.basic_blocks[b3.0].push_insn(Insn::Jmp(Target::Block(BranchEdge {
            target: b2,
            args: vec![r14, r15],
        })));

        // Build b4: out = add(r10, r12); ret out
        asm.set_current_block(b4);
        let label_b4 = asm.new_label("bb3");
        asm.write_label(label_b4);
        let out = asm.new_vreg(64);
        asm.basic_blocks[b4.0].push_insn(Insn::Add { left: r10, right: r12, out });
        asm.basic_blocks[b4.0].push_insn(Insn::CRet(out));

        TestFunc { asm, r10, r11, r12, r13, r14, r15, b1, b2, b3, b4 }
    }

    #[test]
    fn test_live_in() {
        let TestFunc { asm, r10, r12, r13, b1, b2, b3, b4, .. } = build_func();

        let num_vregs = asm.num_vregs;
        let live_in = asm.analyze_liveness();

        // b1: [] - entry block, no variables are live-in
        assert_eq!(bitset_to_vreg_indices(&live_in[b1.0], num_vregs), vec![]);

        // b2: [r10] - r10 is live-in (used in b4 which is reachable)
        assert_eq!(bitset_to_vreg_indices(&live_in[b2.0], num_vregs), vec![r10.vreg_idx_usize()]);

        // b3: [r10, r12, r13] - all are live-in
        assert_eq!(
            bitset_to_vreg_indices(&live_in[b3.0], num_vregs),
            vec![r10.vreg_idx_usize(), r12.vreg_idx_usize(), r13.vreg_idx_usize()]
        );

        // b4: [r10, r12] - both are live-in
        assert_eq!(
            bitset_to_vreg_indices(&live_in[b4.0], num_vregs),
            vec![r10.vreg_idx_usize(), r12.vreg_idx_usize()]
        );
    }

    #[test]
    fn test_lir_debug_output() {
        let TestFunc { asm, .. } = build_func();

        // Test the LIR string output
        let output = lir_string(&asm);

        assert_snapshot!(output, @"
        bb0(v0, v1):
          Jmp bb1(1, v1)
        bb1(v2, v3):
          Cmp v3, 1
          Jl bb3
          Jmp bb2
        bb2():
          v4 = Mul v2, v3
          v5 = Sub v3, 1
          Jmp bb1(v4, v5)
        bb3():
          v6 = Add v0, v2
          CRet v6
        ");
    }

    #[test]
    fn test_out_vregs() {
        let TestFunc { asm, r11, r14, r15, b1, b2, b3, b4, .. } = build_func();

        // b1 has one edge to b2 with args [imm(1), r11]
        // Only r11 is a VReg, so we should only get that
        let out_b1 = asm.basic_blocks[b1.0].out_vregs();
        assert_eq!(out_b1.len(), 1);
        assert_eq!(out_b1[0], r11.vreg_idx());

        // b2 has two edges: one to b4 (no args) and one to b3 (no args)
        let out_b2 = asm.basic_blocks[b2.0].out_vregs();
        assert_eq!(out_b2.len(), 0);

        // b3 has one edge to b2 with args [r14, r15]
        let out_b3 = asm.basic_blocks[b3.0].out_vregs();
        assert_eq!(out_b3.len(), 2);
        assert_eq!(out_b3[0], r14.vreg_idx());
        assert_eq!(out_b3[1], r15.vreg_idx());

        // b4 has no edges (terminates with CRet)
        let out_b4 = asm.basic_blocks[b4.0].out_vregs();
        assert_eq!(out_b4.len(), 0);
    }

    #[test]
    fn test_out_vregs_includes_memory_base_vregs() {
        let mut asm = Assembler::new();

        let base = asm.new_vreg(64);
        let b1 = asm.new_block(hir::BlockId(0), true, 0);
        let b2 = asm.new_block(hir::BlockId(1), false, 1);

        asm.set_current_block(b1);
        let label_b1 = asm.new_label("bb0");
        asm.write_label(label_b1);
        asm.basic_blocks[b1.0].push_insn(Insn::Jmp(Target::Block(BranchEdge {
            target: b2,
            args: vec![Opnd::mem(64, base, 8)],
        })));

        let out_vregs = asm.basic_blocks[b1.0].out_vregs();
        assert_eq!(out_vregs, vec![base.vreg_idx()]);
    }

    #[test]
    fn test_interval_add_range() {
        let mut interval = Interval::new(VRegId(1));

        // Add range to empty interval
        interval.add_range(5, 10);
        assert_eq!(interval.range.start, Some(5));
        assert_eq!(interval.range.end, Some(10));

        // Extend range backward
        interval.add_range(3, 7);
        assert_eq!(interval.range.start, Some(3));
        assert_eq!(interval.range.end, Some(10));

        // Extend range forward
        interval.add_range(8, 15);
        assert_eq!(interval.range.start, Some(3));
        assert_eq!(interval.range.end, Some(15));
    }

    #[test]
    fn test_interval_survives() {
        let mut interval = Interval::new(VRegId(1));
        interval.add_range(3, 10);

        assert!(!interval.survives(2));  // Before range
        assert!(!interval.survives(3));  // At start (exclusive)
        assert!(interval.survives(5));   // Inside range
        assert!(!interval.survives(10)); // At end (exclusive)
        assert!(!interval.survives(11)); // After range
    }

    #[test]
    fn test_interval_set_from() {
        let mut interval = Interval::new(VRegId(1));

        // With no range, sets both start and end
        interval.set_from(10);
        assert_eq!(interval.range.start, Some(10));
        assert_eq!(interval.range.end, Some(10));

        // With existing range, updates start but keeps end
        interval.add_range(5, 20);
        interval.set_from(3);
        assert_eq!(interval.range.start, Some(3));
        assert_eq!(interval.range.end, Some(20));
    }

    #[test]
    #[should_panic(expected = "Invalid range")]
    fn test_interval_add_range_invalid() {
        let mut interval = Interval::new(VRegId(1));
        interval.add_range(10, 5);
    }

    #[test]
    #[should_panic(expected = "survives called on interval with no range")]
    fn test_interval_survives_panics_without_range() {
        let interval = Interval::new(VRegId(1));
        interval.survives(5);
    }

    #[test]
    fn test_build_intervals() {
        let TestFunc { mut asm, r10, r11, r12, r13, r14, r15, .. } = build_func();

        // Analyze liveness
        let live_in = asm.analyze_liveness();

        // Number instructions (starting from 16 to match Ruby test)
        asm.number_instructions(16);

        // Build intervals
        let intervals = asm.build_intervals(live_in);

        // Extract vreg indices
        let r10_idx = if let Opnd::VReg { idx, .. } = r10 { idx } else { panic!() };
        let r11_idx = if let Opnd::VReg { idx, .. } = r11 { idx } else { panic!() };
        let r12_idx = if let Opnd::VReg { idx, .. } = r12 { idx } else { panic!() };
        let r13_idx = if let Opnd::VReg { idx, .. } = r13 { idx } else { panic!() };
        let r14_idx = if let Opnd::VReg { idx, .. } = r14 { idx } else { panic!() };
        let r15_idx = if let Opnd::VReg { idx, .. } = r15 { idx } else { panic!() };

        // Assert expected ranges
        // Note: Rust CFG differs from Ruby due to conditional branches requiring two instructions (Jl + Jmp)
        assert_eq!(intervals[r10_idx].range.start, Some(16));
        assert_eq!(intervals[r10_idx].range.end, Some(38));

        assert_eq!(intervals[r11_idx].range.start, Some(16));
        assert_eq!(intervals[r11_idx].range.end, Some(20));

        assert_eq!(intervals[r12_idx].range.start, Some(20));
        assert_eq!(intervals[r12_idx].range.end, Some(38));

        assert_eq!(intervals[r13_idx].range.start, Some(20));
        assert_eq!(intervals[r13_idx].range.end, Some(32));

        assert_eq!(intervals[r14_idx].range.start, Some(30));
        assert_eq!(intervals[r14_idx].range.end, Some(36));

        assert_eq!(intervals[r15_idx].range.start, Some(32));
        assert_eq!(intervals[r15_idx].range.end, Some(36));
    }

    #[test]
    fn test_linear_scan_no_spill() {
        let TestFunc { mut asm, r10, r11, r12, r13, r14, r15, .. } = build_func();

        // Analyze liveness
        let live_in = asm.analyze_liveness();

        // Number instructions (starting from 16 to match Ruby test)
        asm.number_instructions(16);

        // Build intervals
        let intervals = asm.build_intervals(live_in);

        println!("LIR live_intervals:\n{}", crate::backend::lir::debug_intervals(&asm, &intervals));

        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, num_stack_slots) = asm.linear_scan(intervals, 5, &preferred_registers);

        // Extract vreg indices
        let r10_idx = if let Opnd::VReg { idx, .. } = r10 { idx } else { panic!() };
        let r11_idx = if let Opnd::VReg { idx, .. } = r11 { idx } else { panic!() };
        let r12_idx = if let Opnd::VReg { idx, .. } = r12 { idx } else { panic!() };
        let r13_idx = if let Opnd::VReg { idx, .. } = r13 { idx } else { panic!() };
        let r14_idx = if let Opnd::VReg { idx, .. } = r14 { idx } else { panic!() };
        let r15_idx = if let Opnd::VReg { idx, .. } = r15 { idx } else { panic!() };

        // 5 registers is enough for all intervals, no spills needed
        assert_eq!(num_stack_slots, 0);

        // Verify register assignments
        // r10: [16,42) gets Reg(0) (first allocated)
        // r11: [16,20) gets Reg(1)
        // r12: [20,36) gets Reg(1) (r11 expired, reuses its register)
        // r13: [20,38) gets Reg(2)
        // r14: [36,42) gets Reg(1) (r12 expired, reuses its register)
        // r15: [38,42) gets Reg(2) (r13 expired, reuses its register)
        assert_eq!(assignments[r10_idx], Some(Allocation::Reg(0)));
        assert_eq!(assignments[r11_idx], Some(Allocation::Reg(1)));
        assert_eq!(assignments[r12_idx], Some(Allocation::Reg(1)));
        assert_eq!(assignments[r13_idx], Some(Allocation::Reg(2)));
        assert_eq!(assignments[r14_idx], Some(Allocation::Reg(3)));
        assert_eq!(assignments[r15_idx], Some(Allocation::Reg(2)));
    }

    #[test]
    fn test_linear_scan_spill_less() {
        let TestFunc { mut asm, r10, r11, r12, r13, r14, r15, .. } = build_func();

        let live_in = asm.analyze_liveness();
        asm.number_instructions(16);
        let intervals = asm.build_intervals(live_in);

        // 3 registers -- only r10 needs to spill
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, num_stack_slots) = asm.linear_scan(intervals, 3, &preferred_registers);

        let r10_idx = if let Opnd::VReg { idx, .. } = r10 { idx } else { panic!() };
        let r11_idx = if let Opnd::VReg { idx, .. } = r11 { idx } else { panic!() };
        let r12_idx = if let Opnd::VReg { idx, .. } = r12 { idx } else { panic!() };
        let r13_idx = if let Opnd::VReg { idx, .. } = r13 { idx } else { panic!() };
        let r14_idx = if let Opnd::VReg { idx, .. } = r14 { idx } else { panic!() };
        let r15_idx = if let Opnd::VReg { idx, .. } = r15 { idx } else { panic!() };

        assert_eq!(num_stack_slots, 1);
        assert_eq!(assignments[r10_idx], Some(Allocation::Stack(0)));
        assert_eq!(assignments[r11_idx], Some(Allocation::Reg(1)));
        assert_eq!(assignments[r12_idx], Some(Allocation::Reg(1)));
        assert_eq!(assignments[r13_idx], Some(Allocation::Reg(2)));
        assert_eq!(assignments[r14_idx], Some(Allocation::Reg(0)));
        assert_eq!(assignments[r15_idx], Some(Allocation::Reg(2)));
    }

    #[test]
    fn test_linear_scan_spill() {
        let TestFunc { mut asm, r10, r11, r12, r13, r14, r15, .. } = build_func();

        let live_in = asm.analyze_liveness();
        asm.number_instructions(16);
        let intervals = asm.build_intervals(live_in);

        // Only 1 register available -- forces spills
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, num_stack_slots) = asm.linear_scan(intervals, 1, &preferred_registers);

        let r10_idx = if let Opnd::VReg { idx, .. } = r10 { idx } else { panic!() };
        let r11_idx = if let Opnd::VReg { idx, .. } = r11 { idx } else { panic!() };
        let r12_idx = if let Opnd::VReg { idx, .. } = r12 { idx } else { panic!() };
        let r13_idx = if let Opnd::VReg { idx, .. } = r13 { idx } else { panic!() };
        let r14_idx = if let Opnd::VReg { idx, .. } = r14 { idx } else { panic!() };
        let r15_idx = if let Opnd::VReg { idx, .. } = r15 { idx } else { panic!() };

        assert_eq!(num_stack_slots, 3);
        assert_eq!(assignments[r10_idx], Some(Allocation::Stack(0)));
        assert_eq!(assignments[r11_idx], Some(Allocation::Reg(0)));
        assert_eq!(assignments[r12_idx], Some(Allocation::Stack(1)));
        assert_eq!(assignments[r13_idx], Some(Allocation::Reg(0)));
        assert_eq!(assignments[r14_idx], Some(Allocation::Stack(2)));
        assert_eq!(assignments[r15_idx], Some(Allocation::Reg(0)));
    }

    #[test]
    fn test_preferred_register_assignment_for_newborn_mov_source() {
        let mut asm = Assembler::new();
        let block = asm.new_block(hir::BlockId(0), true, 0);
        asm.set_current_block(block);
        let label = asm.new_label("bb0");
        asm.write_label(label);

        let sp = NATIVE_STACK_PTR;
        let new_sp = asm.add(sp, 0x20.into());
        asm.mov(sp, new_sp);
        asm.cret(sp);

        asm.number_instructions(0);
        let live_in = asm.analyze_liveness();
        let intervals = asm.build_intervals(live_in);
        let preferred_registers = asm.preferred_register_assignments(&intervals);

        let vreg_idx = new_sp.vreg_idx();
        assert_eq!(preferred_registers[vreg_idx], Some(sp.unwrap_reg()));

        let (assignments, num_stack_slots) = asm.linear_scan(intervals, 0, &preferred_registers);
        assert_eq!(num_stack_slots, 0);
        assert_eq!(assignments[vreg_idx], Some(Allocation::Fixed(sp.unwrap_reg())));
    }

    #[test]
    fn test_debug_intervals() {
        let TestFunc { mut asm, .. } = build_func();

        // Number instructions
        asm.number_instructions(16);

        // Get the debug output
        let live_in = asm.analyze_liveness();
        let intervals = asm.build_intervals(live_in);
        let output = debug_intervals(&asm, &intervals);

        // Verify it contains the grid structure
        assert!(output.contains("v0"));  // Header with vreg names
        assert!(output.contains("---"));  // Separator
        assert!(output.contains("█"));    // Live marker
        assert!(output.contains("."));    // Dead marker
    }

    #[test]
    fn test_resolve_ssa() {
        let TestFunc { mut asm, b1, b3, .. } = build_func();

        let live_in = asm.analyze_liveness();
        asm.number_instructions(16);
        let intervals = asm.build_intervals(live_in);
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, _) = asm.linear_scan(intervals.clone(), 5, &preferred_registers);

        asm.resolve_ssa(&intervals, &assignments);

        use crate::backend::current::ALLOC_REGS;
        let regs = &ALLOC_REGS[..5];

        // Edge b1->b2 (single succ): args=[UImm(1), v1], params=[v2, v3]
        // v1->Reg(1), v2->Reg(1), v3->Reg(2)
        // Reg copy: Reg(1)->Reg(2) -> Mov(regs[2], regs[1])
        // Imm move: Mov(regs[1], UImm(1))
        // Inserted in b1 before Jmp: [Label, Mov, Mov, Jmp]
        let b1_insns = &asm.basic_blocks[b1.0].insns;
        assert_eq!(b1_insns.len(), 4);
        assert!(matches!(&b1_insns[1], Insn::Mov { dest, src }
            if *dest == Opnd::Reg(regs[2]) && *src == Opnd::Reg(regs[1])));
        assert!(matches!(&b1_insns[2], Insn::Mov { dest, src }
            if *dest == Opnd::Reg(regs[1]) && *src == Opnd::UImm(1)));

        // Edge b3->b2 (single succ): args=[v4, v5], params=[v2, v3]
        // v4->Reg(3), v5->Reg(2), v2->Reg(1), v3->Reg(2)
        // Reg copy: Reg(3)->Reg(1) -> Mov(regs[1], regs[3])
        // Reg(2)->Reg(2) is self-move, filtered
        // Inserted in b3 before Jmp: [Label, Mul, Sub, Mov, Jmp]
        let b3_insns = &asm.basic_blocks[b3.0].insns;
        assert_eq!(b3_insns.len(), 5);
        assert!(matches!(&b3_insns[3], Insn::Mov { dest, src }
            if *dest == Opnd::Reg(regs[1]) && *src == Opnd::Reg(regs[3])));

        // Verify original instructions in b3 are rewritten to physical registers.
        // b3: Mul { left: r12, right: r13, out: r14 }, Sub { left: r13, right: UImm(1), out: r15 }
        // r12->Reg(1), r13->Reg(2), r14->Reg(3), r15->Reg(2)
        assert!(matches!(&b3_insns[1], Insn::Mul { left, right, out }
            if *left == Opnd::Reg(regs[1]) && *right == Opnd::Reg(regs[2]) && *out == Opnd::Reg(regs[3])));
        assert!(matches!(&b3_insns[2], Insn::Sub { left, right, out }
            if *left == Opnd::Reg(regs[2]) && *right == Opnd::UImm(1) && *out == Opnd::Reg(regs[2])));
    }

    #[test]
    fn test_resolve_ssa_entry_params() {
        let TestFunc { mut asm, b1, .. } = build_func();

        let live_in = asm.analyze_liveness();
        asm.number_instructions(16);
        let intervals = asm.build_intervals(live_in);
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, _) = asm.linear_scan(intervals.clone(), 5, &preferred_registers);

        // Entry block b1 has parameters [v0, v1].
        // With 5 registers: v0 -> Reg(0) = regs[0], arrival = C_ARG_OPNDS[0] = regs[0] -> self-move, filtered
        //                    v1 -> Reg(1) = regs[1], arrival = C_ARG_OPNDS[1] = regs[1] -> self-move, filtered
        // Before resolve_ssa, b1 has: [Label, Jmp] = 2 insns
        assert_eq!(asm.basic_blocks[b1.0].insns.len(), 2);

        asm.resolve_ssa(&intervals, &assignments);

        // After resolve_ssa, b1 should still have the same number of insns
        // (plus any edge moves, but no entry param moves since they're all self-moves).
        // Edge b1->b2 inserts 2 moves before Jmp: [Label, Mov, Mov, Jmp] = 4 insns
        // No additional entry param moves.
        let b1_insns = &asm.basic_blocks[b1.0].insns;
        assert_eq!(b1_insns.len(), 4);
        // Verify the moves are edge moves (not entry param moves)
        assert!(matches!(&b1_insns[1], Insn::Mov { .. }));
        assert!(matches!(&b1_insns[2], Insn::Mov { .. }));

        // After resolve_ssa, edge args are cleared since the moves have been
        // materialized as explicit Mov instructions.
        if let Insn::Jmp(Target::Block(edge)) = &b1_insns[3] {
            assert!(edge.args.is_empty(), "Edge args should be cleared after resolve_ssa");
        } else {
            panic!("Expected Jmp at end of b1");
        }
    }

    #[test]
    fn test_resolve_ssa_entry_params_too_many_abort() {
        let mut asm = Assembler::new();
        let block = asm.new_block(hir::BlockId(0), true, 0);
        asm.set_current_block(block);
        let label = asm.new_label("bb0");
        asm.write_label(label);

        for _ in 0..=C_ARG_OPNDS.len() {
            let param = asm.new_vreg(64);
            asm.basic_blocks[block.0].add_parameter(param);
        }
        asm.basic_blocks[block.0].push_insn(Insn::CRet(Opnd::UImm(0)));

        let live_in = asm.analyze_liveness();
        asm.number_instructions(0);
        let intervals = asm.build_intervals(live_in);
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, _) = asm.linear_scan(intervals.clone(), 5, &preferred_registers);

        asm.resolve_ssa(&intervals, &assignments);

        assert!(matches!(asm.basic_blocks[block.0].insns[1], Insn::Abort));
    }

    fn build_critical_edge() -> (Assembler, Opnd, Opnd, Opnd, Opnd, Opnd, BlockId, BlockId, BlockId) {
        let mut asm = Assembler::new();

        // Create blocks
        let b1 = asm.new_block(hir::BlockId(0), true, 0);
        let b2 = asm.new_block(hir::BlockId(1), false, 1);
        let b3 = asm.new_block(hir::BlockId(2), false, 2);

        // b1: v0 = Add(123, 0), v1 = Add(v0, 456), Cmp(v1, 0), Jl(b2, [v0]), Jmp(b3, [v1])
        // v0 is live across b1->b2 edge AND v1 is live across b1->b3 edge
        // This forces v0 and v1 to have overlapping live ranges -> different registers
        asm.set_current_block(b1);
        let label_b1 = asm.new_label("bb0");
        asm.write_label(label_b1);
        let v0 = asm.new_vreg(64);
        let v1 = asm.new_vreg(64);
        asm.basic_blocks[b1.0].push_insn(Insn::Add { left: Opnd::UImm(123), right: Opnd::UImm(0), out: v0 });
        asm.basic_blocks[b1.0].push_insn(Insn::Add { left: v0, right: Opnd::UImm(456), out: v1 });
        asm.basic_blocks[b1.0].push_insn(Insn::Cmp { left: v1, right: Opnd::UImm(0) });
        asm.basic_blocks[b1.0].push_insn(Insn::Jl(Target::Block(BranchEdge { target: b2, args: vec![v0] })));
        asm.basic_blocks[b1.0].push_insn(Insn::Jmp(Target::Block(BranchEdge { target: b3, args: vec![v1] })));

        // b2(v2): v3 = Add(v2, 789), Jmp(b3, [v3])
        asm.set_current_block(b2);
        let label_b2 = asm.new_label("bb1");
        asm.write_label(label_b2);
        let v2 = asm.new_block_param(64);
        asm.basic_blocks[b2.0].add_parameter(v2);
        let v3 = asm.new_vreg(64);
        asm.basic_blocks[b2.0].push_insn(Insn::Add { left: v2, right: Opnd::UImm(789), out: v3 });
        asm.basic_blocks[b2.0].push_insn(Insn::Jmp(Target::Block(BranchEdge { target: b3, args: vec![v3] })));

        // b3(v4): CRet(v4)
        asm.set_current_block(b3);
        let label_b3 = asm.new_label("bb2");
        asm.write_label(label_b3);
        let v4 = asm.new_block_param(64);
        asm.basic_blocks[b3.0].add_parameter(v4);
        asm.basic_blocks[b3.0].push_insn(Insn::CRet(v4));

        (asm, v0, v1, v2, v3, v4, b1, b2, b3)
    }

    #[test]
    fn test_resolve_critical_edge() {
        let (mut asm, _v0, v1, _v2, v3, v4, b1, b2, b3) = build_critical_edge();

        let live_in = asm.analyze_liveness();
        asm.number_instructions(16);
        let intervals = asm.build_intervals(live_in);
        let num_regs = 5;
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, _) = asm.linear_scan(intervals.clone(), num_regs, &preferred_registers);

        assert_eq!(asm.basic_blocks.len(), 3);

        // Verify v1 and v4 have different allocations (so moves are needed)
        let v1_alloc = assignments[v1.vreg_idx()].unwrap();
        let v4_alloc = assignments[v4.vreg_idx()].unwrap();
        assert_ne!(v1_alloc, v4_alloc, "Test setup: v1 and v4 should have different allocations");

        asm.resolve_ssa(&intervals, &assignments);

        // A new interstitial block should have been created for the critical edge b1->b3
        // b1->b3 is critical because b1 has 2 successors and b3 has 2 predecessors
        assert_eq!(asm.basic_blocks.len(), 4);
        let split_block_id = BlockId(3);

        // b1's Jmp should now target the split block instead of b3
        let b1_insns = &asm.basic_blocks[b1.0].insns;
        let last_insn = b1_insns.last().unwrap();
        if let Insn::Jmp(Target::Block(edge)) = last_insn {
            assert_eq!(edge.target, split_block_id);
        } else {
            panic!("Expected Jmp at end of b1");
        }

        // The split block should contain: Label, Mov(s), Jmp(b3)
        let split_insns = &asm.basic_blocks[split_block_id.0].insns;
        assert!(matches!(&split_insns[0], Insn::Label(_)));
        let split_last = split_insns.last().unwrap();
        if let Insn::Jmp(Target::Block(edge)) = split_last {
            assert_eq!(edge.target, b3);
            assert!(edge.args.is_empty());
        } else {
            panic!("Expected Jmp(b3) at end of split block");
        }

        // The split block should have a Mov for v1->v4
        let has_mov = split_insns.iter().any(|insn| matches!(insn, Insn::Mov { .. }));
        assert!(has_mov, "Expected Mov in split block for v1->v4");

        // b2->b3 is not a critical edge (b2 has single succ), so moves go before Jmp in b2
        let v3_alloc = assignments[v3.vreg_idx()].unwrap();
        let b2_insns = &asm.basic_blocks[b2.0].insns;
        if v3_alloc != v4_alloc {
            // Check that a Mov was inserted before the Jmp in b2
            let second_last = &b2_insns[b2_insns.len() - 2];
            assert!(matches!(second_last, Insn::Mov { .. }), "Expected Mov before Jmp in b2");
        }
    }

    #[test]
    fn test_call() {
        use crate::backend::current::ALLOC_REGS;

        let mut asm = Assembler::new();

        // Single entry block
        let b1 = asm.new_block(hir::BlockId(0), true, 0);
        asm.set_current_block(b1);
        let label = asm.new_label("bb0");
        asm.write_label(label);

        // v0 = param (entry block parameter)
        let v0 = asm.new_block_param(64);
        asm.basic_blocks[b1.0].add_parameter(v0);

        // v1 = Load(UImm(5))
        let v1 = asm.new_vreg(64);
        asm.basic_blocks[b1.0].push_insn(Insn::Load { opnd: Opnd::UImm(5), out: v1 });

        // v2 = Add(v1, UImm(1))
        let v2 = asm.new_vreg(64);
        asm.basic_blocks[b1.0].push_insn(Insn::Add { left: v1, right: Opnd::UImm(1), out: v2 });

        // v3 = CCall { fptr: UImm(0xF00), opnds: [v2] }
        let v3 = asm.new_vreg(64);
        asm.basic_blocks[b1.0].push_insn(Insn::CCall {
            opnds: vec![v2],
            stack_map: None,
            data: Box::new(CCallData {
                fptr: Opnd::UImm(0xF00),
                start_marker: None,
                end_marker: None,
                out: v3,
            }),
        });

        // v4 = Add(v3, v1)
        let v4 = asm.new_vreg(64);
        asm.basic_blocks[b1.0].push_insn(Insn::Add { left: v3, right: v1, out: v4 });

        // v5 = Add(v0, v4)
        let v5 = asm.new_vreg(64);
        asm.basic_blocks[b1.0].push_insn(Insn::Add { left: v0, right: v4, out: v5 });

        // CRet(v5)
        asm.basic_blocks[b1.0].push_insn(Insn::CRet(v5));

        // Run liveness + numbering + intervals + linear scan with 2 registers
        let live_in = asm.analyze_liveness();
        asm.number_instructions(0);
        let intervals = asm.build_intervals(live_in);
        let num_regs = 2;
        let preferred_registers = asm.preferred_register_assignments(&intervals);
        let (assignments, num_stack_slots) = asm.linear_scan(intervals.clone(), num_regs, &preferred_registers);
        asm.stack_state.num_spill_slots = num_stack_slots;

        let regs = &ALLOC_REGS[..num_regs];

        // v0 should be spilled (long-lived, only 2 regs)
        assert!(matches!(assignments[v0.vreg_idx()], Some(Allocation::Stack(_))),
            "v0 should be spilled to stack");
        // v1 should be in a register
        assert!(matches!(assignments[v1.vreg_idx()], Some(Allocation::Reg(_))),
            "v1 should be in a register");

        // Run the pipeline: handle_caller_saved_regs then resolve_ssa
        asm.handle_caller_saved_regs(&intervals, &assignments, regs);
        asm.resolve_ssa(&intervals, &assignments);

        let insns = &asm.basic_blocks[b1.0].insns;

        // Find CPush and CPopInto - they should be balanced.
        let pushes: Vec<_> = insns.iter().filter(|i| matches!(i, Insn::CPushPair(..))).collect();
        let pops: Vec<_> = insns.iter().filter(|i| matches!(i, Insn::CPopPairInto(..))).collect();
        assert_eq!(pushes.len(), pops.len(), "CPush/CPopInto should be balanced");
        assert!(!pushes.is_empty(), "Expected at least one saved register across CCall");

        // The survivor register should match v1's allocation
        let v1_reg = match assignments[v1.vreg_idx()].unwrap() {
            Allocation::Reg(n) => Opnd::Reg(regs[n]),
            Allocation::Fixed(reg) => Opnd::Reg(reg),
            _ => unreachable!(),
        };
        let pushed_v1 = pushes.iter().any(|insn| matches!(**insn, Insn::CPushPair(first, second) if first == v1_reg || second == v1_reg));
        let popped_v1 = pops.iter().any(|insn| matches!(**insn, Insn::CPopPairInto(first, second) if first == v1_reg || second == v1_reg));
        assert!(pushed_v1, "CPushPair should save v1's register");
        assert!(popped_v1, "CPopPairInto should restore v1's register");

        // The CCall should have empty opnds and out = C_RET_OPND (rewritten to regs[0])
        let ccall = insns.iter().find(|i| matches!(i, Insn::CCall { .. })).unwrap();
        if let Insn::CCall { opnds, .. } = ccall {
            assert!(opnds.is_empty(), "CCall opnds should be empty after handle_caller_saved_regs");
        }

        // v0 should be rewritten to a Stack operand
        // Find an Add that uses a Stack operand (the v0+v4 add)
        let has_stack_opnd = insns.iter().any(|i| {
            if let Insn::Add { left: Opnd::Mem(Mem { base: MemBase::Stack { .. }, .. }), .. } = i {
                true
            } else {
                false
            }
        });
        assert!(has_stack_opnd, "v0 should be rewritten to a Stack memory operand");
    }
}
