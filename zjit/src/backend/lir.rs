use std::collections::HashMap;
use std::fmt;
use std::mem::take;
use std::panic;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use crate::codegen::local_size_and_idx_to_ep_offset;
use crate::cruby::{Qundef, RUBY_OFFSET_CFP_PC, RUBY_OFFSET_CFP_SP, SIZEOF_VALUE_I32, vm_stack_canary};
use crate::hir::{Invariant, SideExitReason};
use crate::options::{TraceExits, debug, get_option};
use crate::cruby::VALUE;
use crate::payload::IseqVersionRef;
use crate::stats::{exit_counter_ptr, exit_counter_ptr_for_opcode, side_exit_counter, CompileError};
use crate::virtualmem::CodePtr;
use crate::asm::{CodeBlock, Label};
use crate::state::rb_zjit_record_exit_stack;

pub use crate::backend::current::{
    mem_base_reg,
    Reg,
    EC, CFP, SP,
    NATIVE_STACK_PTR, NATIVE_BASE_PTR,
    C_ARG_OPNDS, C_RET_REG, C_RET_OPND,
};

pub static JIT_PRESERVED_REGS: &[Opnd] = &[CFP, SP, EC];

// Memory operand base
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum MemBase
{
    /// Register: Every Opnd::Mem should have MemBase::Reg as of emit.
    Reg(u8),
    /// Virtual register: Lowered to MemBase::Reg or MemBase::Stack in alloc_regs.
    VReg(usize),
    /// Stack slot: Lowered to MemBase::Reg in scratch_split.
    Stack { stack_idx: usize, num_bits: u8 },
}

// Memory location
#[derive(Copy, Clone, PartialEq, Eq, Hash)]
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
            MemBase::VReg(idx) => write!(f, "v{idx}")?,
            MemBase::Stack { stack_idx, num_bits } if num_bits == 64 => write!(f, "Stack[{stack_idx}]")?,
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

    /// Virtual register. Lowered to Reg or Mem in Assembler::alloc_regs().
    VReg{ idx: usize, num_bits: u8 },

    // Low-level operands, for lowering
    Imm(i64),           // Raw signed immediate
    UImm(u64),          // Raw unsigned immediate
    Mem(Mem),           // Memory location
    Reg(Reg),           // Machine register
}

impl fmt::Display for Opnd {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use Opnd::*;
        match self {
            None => write!(f, "None"),
            Value(VALUE(value)) if *value < 10 => write!(f, "Value({value:x})"),
            Value(VALUE(value)) => write!(f, "Value(0x{value:x})"),
            VReg { idx, num_bits } if *num_bits == 64 => write!(f, "v{idx}"),
            VReg { idx, num_bits } => write!(f, "VReg{num_bits}(v{idx})"),
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
            VReg { idx, num_bits } if *num_bits == 64 => write!(fmt, "VReg({idx})"),
            VReg { idx, num_bits } => write!(fmt, "VReg{num_bits}({idx})"),
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
    pub fn vreg_idx(&self) -> usize {
        match self {
            Opnd::VReg { idx, .. } => *idx,
            _ => unreachable!("trying to unwrap {self:?} into VReg"),
        }
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
                Opnd::VReg { idx: indices[idx], num_bits }
            }
            Opnd::Mem(Mem { base: MemBase::VReg(idx), disp, num_bits }) => {
                Opnd::Mem(Mem { base: MemBase::VReg(indices[idx]), disp, num_bits })
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
}

/// Branch target (something that we can jump to)
/// for branch instructions
#[derive(Clone, Debug)]
pub enum Target
{
    /// Pointer to a piece of ZJIT-generated code
    CodePtr(CodePtr),
    /// A label within the generated code
    Label(Label),
    /// Side exit to the interpreter
    SideExit {
        /// Context used for compiling the side exit
        exit: SideExit,
        /// We use this to increment exit counters
        reason: SideExitReason,
    },
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

    /// Add a comment into the IR at the point that this instruction is added.
    /// It won't have any impact on that actual compiled code.
    Comment(String),

    /// Compare two operands
    Cmp { left: Opnd, right: Opnd },

    /// Pop a register from the C stack
    CPop { out: Opnd },

    /// Pop all of the caller-save registers and the flags from the C stack
    CPopAll,

    /// Pop a register from the C stack and store it into another register
    CPopInto(Opnd),

    /// Push a register onto the C stack
    CPush(Opnd),

    /// Push all of the caller-save registers and the flags to the C stack
    CPushAll,

    // C function call with N arguments (variadic)
    CCall {
        opnds: Vec<Opnd>,
        /// The function pointer to be called. This should be Opnd::const_ptr
        /// (Opnd::UImm) in most cases. gen_entry_trampoline() uses Opnd::Reg.
        fptr: Opnd,
        /// Optional PosMarker to remember the start address of the C call.
        /// It's embedded here to insert the PosMarker after push instructions
        /// that are split from this CCall on alloc_regs().
        start_marker: Option<PosMarkerFn>,
        /// Optional PosMarker to remember the end address of the C call.
        /// It's embedded here to insert the PosMarker before pop instructions
        /// that are split from this CCall on alloc_regs().
        end_marker: Option<PosMarkerFn>,
        out: Opnd,
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

    /// Take a specific register. Signal the register allocator to not use it.
    LiveReg { opnd: Opnd, out: Opnd },

    // A low-level instruction that loads a value into a register.
    Load { opnd: Opnd, out: Opnd },

    // A low-level instruction that loads a value into a specified register.
    LoadInto { dest: Opnd, opnd: Opnd },

    // A low-level instruction that loads a value into a register and
    // sign-extends it to a 64-bit value.
    LoadSExt { opnd: Opnd, out: Opnd },

    /// Shift a value left by a certain amount.
    LShift { opnd: Opnd, shift: Opnd, out: Opnd },

    /// A set of parallel moves into registers or memory.
    /// The backend breaks cycles if there are any cycles between moves.
    ParallelMov { moves: Vec<(Opnd, Opnd)> },

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
    PatchPoint { target: Target, invariant: Invariant, version: IseqVersionRef },

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

impl Insn {
    /// Create an iterator that will yield a non-mutable reference to each
    /// operand in turn for this instruction.
    pub(super) fn opnd_iter(&self) -> InsnOpndIterator<'_> {
        InsnOpndIterator::new(self)
    }

    /// Create an iterator that will yield a mutable reference to each operand
    /// in turn for this instruction.
    pub(super) fn opnd_iter_mut(&mut self) -> InsnOpndMutIterator<'_> {
        InsnOpndMutIterator::new(self)
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
            Insn::LeaJumpTarget { target, .. } |
            Insn::PatchPoint { target, .. } => {
                Some(target)
            }
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
            Insn::Comment(_) => "Comment",
            Insn::Cmp { .. } => "Cmp",
            Insn::CPop { .. } => "CPop",
            Insn::CPopAll => "CPopAll",
            Insn::CPopInto(_) => "CPopInto",
            Insn::CPush(_) => "CPush",
            Insn::CPushAll => "CPushAll",
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
            Insn::LiveReg { .. } => "LiveReg",
            Insn::Load { .. } => "Load",
            Insn::LoadInto { .. } => "LoadInto",
            Insn::LoadSExt { .. } => "LoadSExt",
            Insn::LShift { .. } => "LShift",
            Insn::ParallelMov { .. } => "ParallelMov",
            Insn::Mov { .. } => "Mov",
            Insn::Not { .. } => "Not",
            Insn::Or { .. } => "Or",
            Insn::PatchPoint { .. } => "PatchPoint",
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
            Insn::CCall { out, .. } |
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
            Insn::LiveReg { out, .. } |
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
            _ => None
        }
    }

    /// Return a mutable reference to the out operand for this instruction if it
    /// has one.
    pub fn out_opnd_mut(&mut self) -> Option<&mut Opnd> {
        match self {
            Insn::Add { out, .. } |
            Insn::And { out, .. } |
            Insn::CCall { out, .. } |
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
            Insn::LiveReg { out, .. } |
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
            Insn::LeaJumpTarget { target, .. } |
            Insn::PatchPoint { target, .. } => Some(target),
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
}

/// An iterator that will yield a non-mutable reference to each operand in turn
/// for the given instruction.
pub(super) struct InsnOpndIterator<'a> {
    insn: &'a Insn,
    idx: usize,
}

impl<'a> InsnOpndIterator<'a> {
    fn new(insn: &'a Insn) -> Self {
        Self { insn, idx: 0 }
    }
}

impl<'a> Iterator for InsnOpndIterator<'a> {
    type Item = &'a Opnd;

    fn next(&mut self) -> Option<Self::Item> {
        match self.insn {
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
            Insn::LeaJumpTarget { target, .. } |
            Insn::PatchPoint { target, .. } => {
                if let Target::SideExit { exit: SideExit { stack, locals, .. }, .. } = target {
                    let stack_idx = self.idx;
                    if stack_idx < stack.len() {
                        let opnd = &stack[stack_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }

                    let local_idx = self.idx - stack.len();
                    if local_idx < locals.len() {
                        let opnd = &locals[local_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }
                }
                None
            }

            Insn::Joz(opnd, target) |
            Insn::Jonz(opnd, target) => {
                if self.idx == 0 {
                    self.idx += 1;
                    return Some(opnd);
                }

                if let Target::SideExit { exit: SideExit { stack, locals, .. }, .. } = target {
                    let stack_idx = self.idx - 1;
                    if stack_idx < stack.len() {
                        let opnd = &stack[stack_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }

                    let local_idx = stack_idx - stack.len();
                    if local_idx < locals.len() {
                        let opnd = &locals[local_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }
                }
                None
            }

            Insn::BakeString(_) |
            Insn::Breakpoint |
            Insn::Comment(_) |
            Insn::CPop { .. } |
            Insn::CPopAll |
            Insn::CPushAll |
            Insn::PadPatchPoint |
            Insn::PosMarker(_) => None,

            Insn::CPopInto(opnd) |
            Insn::CPush(opnd) |
            Insn::CRet(opnd) |
            Insn::JmpOpnd(opnd) |
            Insn::Lea { opnd, .. } |
            Insn::LiveReg { opnd, .. } |
            Insn::Load { opnd, .. } |
            Insn::LoadSExt { opnd, .. } |
            Insn::Not { opnd, .. } => {
                match self.idx {
                    0 => {
                        self.idx += 1;
                        Some(opnd)
                    },
                    _ => None
                }
            },
            Insn::Add { left: opnd0, right: opnd1, .. } |
            Insn::And { left: opnd0, right: opnd1, .. } |
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
                match self.idx {
                    0 => {
                        self.idx += 1;
                        Some(opnd0)
                    }
                    1 => {
                        self.idx += 1;
                        Some(opnd1)
                    }
                    _ => None
                }
            },
            Insn::CCall { opnds, .. } => {
                if self.idx < opnds.len() {
                    let opnd = &opnds[self.idx];
                    self.idx += 1;
                    Some(opnd)
                } else {
                    None
                }
            },
            Insn::ParallelMov { moves } => {
                if self.idx < moves.len() * 2 {
                    let move_idx = self.idx / 2;
                    let opnd = if self.idx % 2 == 0 {
                        &moves[move_idx].0
                    } else {
                        &moves[move_idx].1
                    };
                    self.idx += 1;
                    Some(opnd)
                } else {
                    None
                }
            },
            Insn::FrameSetup { preserved, .. } |
            Insn::FrameTeardown { preserved } => {
                if self.idx < preserved.len() {
                    let opnd = &preserved[self.idx];
                    self.idx += 1;
                    Some(opnd)
                } else {
                    None
                }
            }
        }
    }
}

/// An iterator that will yield each operand in turn for the given instruction.
pub(super) struct InsnOpndMutIterator<'a> {
    insn: &'a mut Insn,
    idx: usize,
}

impl<'a> InsnOpndMutIterator<'a> {
    fn new(insn: &'a mut Insn) -> Self {
        Self { insn, idx: 0 }
    }

    pub(super) fn next(&mut self) -> Option<&mut Opnd> {
        match self.insn {
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
            Insn::LeaJumpTarget { target, .. } |
            Insn::PatchPoint { target, .. } => {
                if let Target::SideExit { exit: SideExit { stack, locals, .. }, .. } = target {
                    let stack_idx = self.idx;
                    if stack_idx < stack.len() {
                        let opnd = &mut stack[stack_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }

                    let local_idx = self.idx - stack.len();
                    if local_idx < locals.len() {
                        let opnd = &mut locals[local_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }
                }
                None
            }

            Insn::Joz(opnd, target) |
            Insn::Jonz(opnd, target) => {
                if self.idx == 0 {
                    self.idx += 1;
                    return Some(opnd);
                }

                if let Target::SideExit { exit: SideExit { stack, locals, .. }, .. } = target {
                    let stack_idx = self.idx - 1;
                    if stack_idx < stack.len() {
                        let opnd = &mut stack[stack_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }

                    let local_idx = stack_idx - stack.len();
                    if local_idx < locals.len() {
                        let opnd = &mut locals[local_idx];
                        self.idx += 1;
                        return Some(opnd);
                    }
                }
                None
            }

            Insn::BakeString(_) |
            Insn::Breakpoint |
            Insn::Comment(_) |
            Insn::CPop { .. } |
            Insn::CPopAll |
            Insn::CPushAll |
            Insn::FrameSetup { .. } |
            Insn::FrameTeardown { .. } |
            Insn::PadPatchPoint |
            Insn::PosMarker(_) => None,

            Insn::CPopInto(opnd) |
            Insn::CPush(opnd) |
            Insn::CRet(opnd) |
            Insn::JmpOpnd(opnd) |
            Insn::Lea { opnd, .. } |
            Insn::LiveReg { opnd, .. } |
            Insn::Load { opnd, .. } |
            Insn::LoadSExt { opnd, .. } |
            Insn::Not { opnd, .. } => {
                match self.idx {
                    0 => {
                        self.idx += 1;
                        Some(opnd)
                    },
                    _ => None
                }
            },
            Insn::Add { left: opnd0, right: opnd1, .. } |
            Insn::And { left: opnd0, right: opnd1, .. } |
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
                match self.idx {
                    0 => {
                        self.idx += 1;
                        Some(opnd0)
                    }
                    1 => {
                        self.idx += 1;
                        Some(opnd1)
                    }
                    _ => None
                }
            },
            Insn::CCall { opnds, .. } => {
                if self.idx < opnds.len() {
                    let opnd = &mut opnds[self.idx];
                    self.idx += 1;
                    Some(opnd)
                } else {
                    None
                }
            },
            Insn::ParallelMov { moves } => {
                if self.idx < moves.len() * 2 {
                    let move_idx = self.idx / 2;
                    let opnd = if self.idx % 2 == 0 {
                        &mut moves[move_idx].0
                    } else {
                        &mut moves[move_idx].1
                    };
                    self.idx += 1;
                    Some(opnd)
                } else {
                    None
                }
            },
        }
    }
}

impl fmt::Debug for Insn {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "{}(", self.op())?;

        // Print list of operands
        let mut opnd_iter = self.opnd_iter();
        if let Insn::FrameSetup { slot_count, .. } = self {
            write!(fmt, "{slot_count}")?;
        }
        if let Some(first_opnd) = opnd_iter.next() {
            write!(fmt, "{first_opnd:?}")?;
        }
        for opnd in opnd_iter {
            write!(fmt, ", {opnd:?}")?;
        }
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
    /// Index of the first instruction that used the VReg (inclusive)
    pub start: Option<usize>,
    /// Index of the last instruction that used the VReg (inclusive)
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

/// StackState manages which stack slots are used by which VReg
pub struct StackState {
    /// The maximum number of spilled VRegs at a time
    stack_size: usize,
    /// Map from index at the C stack for spilled VRegs to Some(vreg_idx) if allocated
    stack_slots: Vec<Option<usize>>,
    /// Copy of Assembler::stack_base_idx. Used for calculating stack slot offsets.
    stack_base_idx: usize,
}

impl StackState {
    /// Initialize a stack allocator
    pub(super) fn new(stack_base_idx: usize) -> Self {
        StackState {
            stack_size: 0,
            stack_slots: vec![],
            stack_base_idx,
        }
    }

    /// Allocate a stack slot for a given vreg_idx
    fn alloc_stack(&mut self, vreg_idx: usize) -> Opnd {
        for stack_idx in 0..self.stack_size {
            if self.stack_slots[stack_idx].is_none() {
                self.stack_slots[stack_idx] = Some(vreg_idx);
                return Opnd::mem(64, NATIVE_BASE_PTR, self.stack_idx_to_disp(stack_idx));
            }
        }
        // Every stack slot is in use. Allocate a new stack slot.
        self.stack_size += 1;
        self.stack_slots.push(Some(vreg_idx));
        Opnd::mem(64, NATIVE_BASE_PTR, self.stack_idx_to_disp(self.stack_slots.len() - 1))
    }

    /// Deallocate a stack slot for a given disp
    fn dealloc_stack(&mut self, disp: i32) {
        let stack_idx = self.disp_to_stack_idx(disp);
        if self.stack_slots[stack_idx].is_some() {
            self.stack_slots[stack_idx] = None;
        }
    }

    /// Convert the `disp` of a stack slot operand to the stack index
    fn disp_to_stack_idx(&self, disp: i32) -> usize {
        (-disp / SIZEOF_VALUE_I32) as usize - self.stack_base_idx - 1
    }

    /// Convert a stack index to the `disp` of the stack slot
    fn stack_idx_to_disp(&self, stack_idx: usize) -> i32 {
        (self.stack_base_idx + stack_idx + 1) as i32 * -SIZEOF_VALUE_I32
    }

    /// Convert Mem to MemBase::Stack
    fn mem_to_stack_membase(&self, mem: Mem) -> MemBase {
        match mem {
            Mem { base: MemBase::Reg(reg_no), disp, num_bits } if NATIVE_BASE_PTR.unwrap_reg().reg_no == reg_no => {
                let stack_idx = self.disp_to_stack_idx(disp);
                MemBase::Stack { stack_idx, num_bits }
            }
            _ => unreachable!(),
        }
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

/// RegisterPool manages which registers are used by which VReg
struct RegisterPool {
    /// List of registers that can be allocated
    regs: Vec<Reg>,

    /// Some(vreg_idx) if the register at the index in `pool` is used by the VReg.
    /// None if the register is not in use.
    pool: Vec<Option<usize>>,

    /// The number of live registers.
    /// Provides a quick way to query `pool.filter(|r| r.is_some()).count()`
    live_regs: usize,

    /// Fallback to let StackState allocate stack slots when RegisterPool runs out of registers.
    stack_state: StackState,
}

impl RegisterPool {
    /// Initialize a register pool
    fn new(regs: Vec<Reg>, stack_base_idx: usize) -> Self {
        let pool = vec![None; regs.len()];
        RegisterPool {
            regs,
            pool,
            live_regs: 0,
            stack_state: StackState::new(stack_base_idx),
        }
    }

    /// Mutate the pool to indicate that the register at the index
    /// has been allocated and is live.
    fn alloc_opnd(&mut self, vreg_idx: usize) -> Opnd {
        for (reg_idx, reg) in self.regs.iter().enumerate() {
            if self.pool[reg_idx].is_none() {
                self.pool[reg_idx] = Some(vreg_idx);
                self.live_regs += 1;
                return Opnd::Reg(*reg);
            }
        }
        self.stack_state.alloc_stack(vreg_idx)
    }

    /// Allocate a specific register
    fn take_reg(&mut self, reg: &Reg, vreg_idx: usize) -> Opnd {
        let reg_idx = self.regs.iter().position(|elem| elem.reg_no == reg.reg_no)
            .unwrap_or_else(|| panic!("Unable to find register: {}", reg.reg_no));
        assert_eq!(self.pool[reg_idx], None, "register already allocated for VReg({:?})", self.pool[reg_idx]);
        self.pool[reg_idx] = Some(vreg_idx);
        self.live_regs += 1;
        Opnd::Reg(*reg)
    }

    // Mutate the pool to indicate that the given register is being returned
    // as it is no longer used by the instruction that previously held it.
    fn dealloc_opnd(&mut self, opnd: &Opnd) {
        if let Opnd::Mem(Mem { disp, .. }) = *opnd {
            return self.stack_state.dealloc_stack(disp);
        }

        let reg = opnd.unwrap_reg();
        let reg_idx = self.regs.iter().position(|elem| elem.reg_no == reg.reg_no)
            .unwrap_or_else(|| panic!("Unable to find register: {}", reg.reg_no));
        if self.pool[reg_idx].is_some() {
            self.pool[reg_idx] = None;
            self.live_regs -= 1;
        }
    }

    /// Return a list of (Reg, vreg_idx) tuples for all live registers
    fn live_regs(&self) -> Vec<(Reg, usize)> {
        let mut live_regs = Vec::with_capacity(self.live_regs);
        for (reg_idx, &reg) in self.regs.iter().enumerate() {
            if let Some(vreg_idx) = self.pool[reg_idx] {
                live_regs.push((reg, vreg_idx));
            }
        }
        live_regs
    }

    /// Return vreg_idx if a given register is already in use
    fn vreg_for(&self, reg: &Reg) -> Option<usize> {
        let reg_idx = self.regs.iter().position(|elem| elem.reg_no == reg.reg_no).unwrap();
        self.pool[reg_idx]
    }

    /// Return true if no register is in use
    fn is_empty(&self) -> bool {
        self.live_regs == 0
    }
}

/// Initial capacity for asm.insns vector
const ASSEMBLER_INSNS_CAPACITY: usize = 256;

/// Object into which we assemble instructions to be
/// optimized and lowered
#[derive(Clone)]
pub struct Assembler {
    pub(super) insns: Vec<Insn>,

    /// Live range for each VReg indexed by its `idx``
    pub(super) live_ranges: Vec<LiveRange>,

    /// Names of labels
    pub(super) label_names: Vec<String>,

    /// If true, `push_insn` is allowed to use scratch registers.
    /// On `compile`, it also disables the backend's use of them.
    pub(super) accept_scratch_reg: bool,

    /// The Assembler can use NATIVE_BASE_PTR + stack_base_idx as the
    /// first stack slot in case it needs to allocate memory. This is
    /// equal to the number of spilled basic block arguments.
    pub(super) stack_base_idx: usize,

    /// If Some, the next ccall should verify its leafness
    leaf_ccall_stack_size: Option<usize>
}

impl Assembler
{
    /// Create an Assembler with defaults
    pub fn new() -> Self {
        Self {
            insns: Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY),
            live_ranges: Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY),
            label_names: Vec::default(),
            accept_scratch_reg: false,
            stack_base_idx: 0,
            leaf_ccall_stack_size: None,
        }
    }

    /// Create an Assembler, reserving a specified number of stack slots
    pub fn new_with_stack_slots(stack_base_idx: usize) -> Self {
        Self { stack_base_idx, ..Self::new() }
    }

    /// Create an Assembler that allows the use of scratch registers.
    /// This should be called only through [`Self::new_with_scratch_reg`].
    pub(super) fn new_with_accept_scratch_reg(accept_scratch_reg: bool) -> Self {
        Self { accept_scratch_reg, ..Self::new() }
    }

    /// Create an Assembler with parameters of another Assembler and empty instructions.
    /// Compiler passes build a next Assembler with this API and insert new instructions to it.
    pub(super) fn new_with_asm(old_asm: &Assembler) -> Self {
        let mut asm = Self {
            label_names: old_asm.label_names.clone(),
            accept_scratch_reg: old_asm.accept_scratch_reg,
            stack_base_idx: old_asm.stack_base_idx,
            ..Self::new()
        };
        // Bump the initial VReg index to allow the use of the VRegs for the old Assembler
        asm.live_ranges.resize(old_asm.live_ranges.len(), LiveRange { start: None, end: None });
        asm
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
        let insns = take(&mut self.insns);
        InsnIter {
            old_insns_iter: insns.into_iter(),
            peeked: None,
            index: 0,
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

    /// Build an Opnd::VReg and initialize its LiveRange
    pub(super) fn new_vreg(&mut self, num_bits: u8) -> Opnd {
        let vreg = Opnd::VReg { idx: self.live_ranges.len(), num_bits };
        self.live_ranges.push(LiveRange { start: None, end: None });
        vreg
    }

    /// Append an instruction onto the current list of instructions and update
    /// the live ranges of any instructions whose outputs are being used as
    /// operands to this instruction.
    pub fn push_insn(&mut self, insn: Insn) {
        // Index of this instruction
        let insn_idx = self.insns.len();

        // Initialize the live range of the output VReg to insn_idx..=insn_idx
        if let Some(Opnd::VReg { idx, .. }) = insn.out_opnd() {
            assert!(*idx < self.live_ranges.len());
            assert_eq!(self.live_ranges[*idx], LiveRange { start: None, end: None });
            self.live_ranges[*idx] = LiveRange { start: Some(insn_idx), end: Some(insn_idx) };
        }

        // If we find any VReg from previous instructions, extend the live range to insn_idx
        let opnd_iter = insn.opnd_iter();
        for opnd in opnd_iter {
            match *opnd {
                Opnd::VReg { idx, .. } |
                Opnd::Mem(Mem { base: MemBase::VReg(idx), .. }) => {
                    assert!(idx < self.live_ranges.len());
                    assert_ne!(self.live_ranges[idx].end, None);
                    self.live_ranges[idx].end = Some(self.live_ranges[idx].end().max(insn_idx));
                }
                _ => {}
            }
        }

        // If this Assembler should not accept scratch registers, assert no use of them.
        if !self.accept_scratch_reg {
            let opnd_iter = insn.opnd_iter();
            for opnd in opnd_iter {
                assert!(!Self::has_scratch_reg(*opnd), "should not use scratch register: {opnd:?}");
            }
        }

        self.insns.push(insn);
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

    /// Sets the out field on the various instructions that require allocated
    /// registers because their output is used as the operand on a subsequent
    /// instruction. This is our implementation of the linear scan algorithm.
    pub(super) fn alloc_regs(mut self, regs: Vec<Reg>) -> Result<Assembler, CompileError> {
        // First, create the pool of registers.
        let mut pool = RegisterPool::new(regs.clone(), self.stack_base_idx);

        // Mapping between VReg and register or stack slot for each VReg index.
        // None if no register or stack slot has been allocated for the VReg.
        let mut vreg_opnd: Vec<Option<Opnd>> = vec![None; self.live_ranges.len()];

        // List of registers saved before a C call, paired with the VReg index.
        let mut saved_regs: Vec<(Reg, usize)> = vec![];

        // Remember the indexes of Insn::FrameSetup to update the stack size later
        let mut frame_setup_idxs: Vec<usize> = vec![];

        // live_ranges is indexed by original `index` given by the iterator.
        let mut asm = Assembler::new_with_asm(&self);
        let live_ranges: Vec<LiveRange> = take(&mut self.live_ranges);
        let mut iterator = self.insns.into_iter().enumerate().peekable();

        while let Some((index, mut insn)) = iterator.next() {
            // Remember the index of FrameSetup to bump slot_count when we know the max number of spilled VRegs.
            if let Insn::FrameSetup { .. } = insn {
                frame_setup_idxs.push(asm.insns.len());
            }

            let before_ccall = match (&insn, iterator.peek().map(|(_, insn)| insn)) {
                (Insn::ParallelMov { .. }, Some(Insn::CCall { .. })) |
                (Insn::CCall { .. }, _) if !pool.is_empty() => {
                    // If C_RET_REG is in use, move it to another register.
                    // This must happen before last-use registers are deallocated.
                    if let Some(vreg_idx) = pool.vreg_for(&C_RET_REG) {
                        let new_opnd = pool.alloc_opnd(vreg_idx);
                        asm.mov(new_opnd, C_RET_OPND);
                        pool.dealloc_opnd(&Opnd::Reg(C_RET_REG));
                        vreg_opnd[vreg_idx] = Some(new_opnd);
                    }

                    true
                },
                _ => false,
            };

            // Check if this is the last instruction that uses an operand that
            // spans more than one instruction. In that case, return the
            // allocated register to the pool.
            for opnd in insn.opnd_iter() {
                match *opnd {
                    Opnd::VReg { idx, .. } |
                    Opnd::Mem(Mem { base: MemBase::VReg(idx), .. }) => {
                        // We're going to check if this is the last instruction that
                        // uses this operand. If it is, we can return the allocated
                        // register to the pool.
                        if live_ranges[idx].end() == index {
                            if let Some(opnd) = vreg_opnd[idx] {
                                pool.dealloc_opnd(&opnd);
                            } else {
                                unreachable!("no register allocated for insn {:?}", insn);
                            }
                        }
                    }
                    _ => {}
                }
            }

            // Save caller-saved registers on a C call.
            if before_ccall {
                // Find all live registers
                saved_regs = pool.live_regs();

                // Save live registers
                for &(reg, _) in saved_regs.iter() {
                    asm.cpush(Opnd::Reg(reg));
                    pool.dealloc_opnd(&Opnd::Reg(reg));
                }
                // On x86_64, maintain 16-byte stack alignment
                if cfg!(target_arch = "x86_64") && saved_regs.len() % 2 == 1 {
                    asm.cpush(Opnd::Reg(saved_regs.last().unwrap().0));
                }
            }

            // Allocate a register for the output operand if it exists
            let vreg_idx = match insn.out_opnd() {
                Some(Opnd::VReg { idx, .. }) => Some(*idx),
                _ => None,
            };
            if let Some(vreg_idx) = vreg_idx {
                if live_ranges[vreg_idx].end() == index {
                    debug!("Allocating a register for VReg({}) at instruction index {} even though it does not live past this index", vreg_idx, index);
                }
                // This is going to be the output operand that we will set on the
                // instruction. CCall and LiveReg need to use a specific register.
                let mut out_reg = match insn {
                    Insn::CCall { .. } => {
                        Some(pool.take_reg(&C_RET_REG, vreg_idx))
                    }
                    Insn::LiveReg { opnd, .. } => {
                        let reg = opnd.unwrap_reg();
                        Some(pool.take_reg(&reg, vreg_idx))
                    }
                    _ => None
                };

                // If this instruction's first operand maps to a register and
                // this is the last use of the register, reuse the register
                // We do this to improve register allocation on x86
                // e.g. out  = add(reg0, reg1)
                //      reg0 = add(reg0, reg1)
                if out_reg.is_none() {
                    let mut opnd_iter = insn.opnd_iter();

                    if let Some(Opnd::VReg{ idx, .. }) = opnd_iter.next() {
                        if live_ranges[*idx].end() == index {
                            if let Some(Opnd::Reg(reg)) = vreg_opnd[*idx] {
                                out_reg = Some(pool.take_reg(&reg, vreg_idx));
                            }
                        }
                    }
                }

                // Allocate a new register for this instruction if one is not
                // already allocated.
                let out_opnd = out_reg.unwrap_or_else(|| pool.alloc_opnd(vreg_idx));

                // Set the output operand on the instruction
                let out_num_bits = Opnd::match_num_bits_iter(insn.opnd_iter());

                // If we have gotten to this point, then we're sure we have an
                // output operand on this instruction because the live range
                // extends beyond the index of the instruction.
                let out = insn.out_opnd_mut().unwrap();
                let out_opnd = out_opnd.with_num_bits(out_num_bits);
                vreg_opnd[out.vreg_idx()] = Some(out_opnd);
                *out = out_opnd;
            }

            // Replace VReg and Param operands by their corresponding register
            let mut opnd_iter = insn.opnd_iter_mut();
            while let Some(opnd) = opnd_iter.next() {
                match *opnd {
                    Opnd::VReg { idx, num_bits } => {
                        *opnd = vreg_opnd[idx].unwrap().with_num_bits(num_bits);
                    },
                    Opnd::Mem(Mem { base: MemBase::VReg(idx), disp, num_bits }) => {
                        *opnd = match vreg_opnd[idx].unwrap() {
                            Opnd::Reg(reg) => Opnd::Mem(Mem { base: MemBase::Reg(reg.reg_no), disp, num_bits }),
                            // If the base is spilled, lower it to MemBase::Stack, which scratch_split will lower to MemBase::Reg.
                            Opnd::Mem(mem) => Opnd::Mem(Mem { base: pool.stack_state.mem_to_stack_membase(mem), disp, num_bits }),
                            _ => unreachable!(),
                        }
                    }
                    _ => {},
                }
            }

            // If we have an output that dies at its definition (it is unused), free up the
            // register
            if let Some(idx) = vreg_idx {
                if live_ranges[idx].end() == index {
                    if let Some(opnd) = vreg_opnd[idx] {
                        pool.dealloc_opnd(&opnd);
                    } else {
                        unreachable!("no register allocated for insn {:?}", insn);
                    }
                }
            }

            // Push instruction(s)
            let is_ccall = matches!(insn, Insn::CCall { .. });
            match insn {
                Insn::ParallelMov { moves } => {
                    // For trampolines that use scratch registers, attempt to lower ParallelMov without scratch_reg.
                    if let Some(moves) = Self::resolve_parallel_moves(&moves, None) {
                        for (dst, src) in moves {
                            asm.mov(dst, src);
                        }
                    } else {
                        // If it needs a scratch_reg, leave it to *_split_with_scratch_regs to handle it.
                        asm.push_insn(Insn::ParallelMov { moves });
                    }
                }
                Insn::CCall { opnds, fptr, start_marker, end_marker, out } => {
                    // Split start_marker and end_marker here to avoid inserting push/pop between them.
                    if let Some(start_marker) = start_marker {
                        asm.push_insn(Insn::PosMarker(start_marker));
                    }
                    asm.push_insn(Insn::CCall { opnds, fptr, start_marker: None, end_marker: None, out });
                    if let Some(end_marker) = end_marker {
                        asm.push_insn(Insn::PosMarker(end_marker));
                    }
                }
                Insn::Mov { src, dest } | Insn::LoadInto { dest, opnd: src } if src == dest => {
                    // Remove no-op move now that VReg are resolved to physical Reg
                }
                _ => asm.push_insn(insn),
            }

            // After a C call, restore caller-saved registers
            if is_ccall {
                // On x86_64, maintain 16-byte stack alignment
                if cfg!(target_arch = "x86_64") && saved_regs.len() % 2 == 1 {
                    asm.cpop_into(Opnd::Reg(saved_regs.last().unwrap().0));
                }
                // Restore saved registers
                for &(reg, vreg_idx) in saved_regs.iter().rev() {
                    asm.cpop_into(Opnd::Reg(reg));
                    pool.take_reg(&reg, vreg_idx);
                }
                saved_regs.clear();
            }
        }

        // Extend the stack space for spilled operands
        for frame_setup_idx in frame_setup_idxs {
            match &mut asm.insns[frame_setup_idx] {
                Insn::FrameSetup { slot_count, .. } => {
                    *slot_count += pool.stack_state.stack_size;
                }
                _ => unreachable!(),
            }
        }

        assert!(pool.is_empty(), "Expected all registers to be returned to the pool");
        Ok(asm)
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
        if get_option!(dump_disasm) {
            let end_addr = cb.get_write_ptr();
            let disasm = crate::disasm::disasm_addr_range(cb, start_addr.raw_ptr(cb) as usize, end_addr.raw_ptr(cb) as usize);
            println!("{}", disasm);
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

    /// Compile Target::SideExit and convert it into Target::CodePtr for all instructions
    pub fn compile_exits(&mut self) {
        /// Compile the main side-exit code. This function takes only SideExit so
        /// that it can be safely deduplicated by using SideExit as a dedup key.
        fn compile_exit(asm: &mut Assembler, exit: &SideExit) {
            let SideExit { pc, stack, locals } = exit;

            asm_comment!(asm, "save cfp->pc");
            asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), *pc);

            asm_comment!(asm, "save cfp->sp");
            asm.lea_into(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP), Opnd::mem(64, SP, stack.len() as i32 * SIZEOF_VALUE_I32));

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

            asm_comment!(asm, "exit to the interpreter");
            asm.frame_teardown(&[]); // matching the setup in gen_entry_point()
            asm.cret(Opnd::UImm(Qundef.as_u64()));
        }

        fn join_opnds(opnds: &Vec<Opnd>, delimiter: &str) -> String {
            opnds.iter().map(|opnd| format!("{opnd}")).collect::<Vec<_>>().join(delimiter)
        }

        // Extract targets first so that we can update instructions while referencing part of them.
        let mut targets = HashMap::new();
        for (idx, insn) in self.insns.iter().enumerate() {
            if let Some(target @ Target::SideExit { .. }) = insn.target() {
                targets.insert(idx, target.clone());
            }
        }

        // Map from SideExit to compiled Label. This table is used to deduplicate side exit code.
        let mut compiled_exits: HashMap<SideExit, Label> = HashMap::new();

        for (idx, target) in targets {
            // Compile a side exit. Note that this is past the split pass and alloc_regs(),
            // so you can't use an instruction that returns a VReg.
            if let Target::SideExit { exit: exit @ SideExit { pc, .. }, reason } = target {
                // Only record the exit if `trace_side_exits` is defined and the counter is either the one specified
                let should_record_exit = get_option!(trace_side_exits).map(|trace| match trace {
                    TraceExits::All => true,
                    TraceExits::Counter(counter) if counter == side_exit_counter(reason) => true,
                    _ => false,
                }).unwrap_or(false);

                // If enabled, instrument exits first, and then jump to a shared exit.
                let counted_exit = if get_option!(stats) || should_record_exit {
                    let counted_exit = self.new_label("counted_exit");
                    self.write_label(counted_exit.clone());
                    asm_comment!(self, "Counted Exit: {reason}");

                    if get_option!(stats) {
                        asm_comment!(self, "increment a side exit counter");
                        self.incr_counter(Opnd::const_ptr(exit_counter_ptr(reason)), 1.into());

                        if let SideExitReason::UnhandledYARVInsn(opcode) = reason {
                            asm_comment!(self, "increment an unhandled YARV insn counter");
                            self.incr_counter(Opnd::const_ptr(exit_counter_ptr_for_opcode(opcode)), 1.into());
                        }
                    }

                    if should_record_exit {
                        // Preserve caller-saved registers that may be used in the shared exit.
                        self.cpush_all();
                        asm_ccall!(self, rb_zjit_record_exit_stack, pc);
                        self.cpop_all();
                    }

                    // If the side exit has already been compiled, jump to it.
                    // Otherwise, let it fall through and compile the exit next.
                    if let Some(&exit_label) = compiled_exits.get(&exit) {
                        self.jmp(Target::Label(exit_label));
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
                    asm_comment!(self, "Exit: {pc}");
                    compile_exit(self, &exit);
                    compiled_exits.insert(exit, new_exit.unwrap_label());
                    new_exit
                };

                *self.insns[idx].target_mut().unwrap() = counted_exit.unwrap_or(compiled_exit);
            }
        }
    }
}

const BOLD_BEGIN: &str = "\x1b[1m";
const BOLD_END: &str = "\x1b[22m";

/// Return a result of fmt::Display for Assembler without escape sequence
pub fn lir_string(asm: &Assembler) -> String {
    format!("{asm}").replace(BOLD_BEGIN, "").replace(BOLD_END, "")
}

impl fmt::Display for Assembler {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        // Count the number of duplicated label names to disambiguate them if needed
        let mut label_counts: HashMap<&String, usize> = HashMap::new();
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

        for insn in self.insns.iter() {
            match insn {
                Insn::Comment(comment) => {
                    writeln!(f, "    {BOLD_BEGIN}# {comment}{BOLD_END}")?;
                }
                Insn::Label(target) => {
                    let &Target::Label(Label(label_idx)) = target else {
                        panic!("unexpected target for Insn::Label: {target:?}");
                    };
                    writeln!(f, "  {}:", label_name(self, label_idx, &label_counts))?;
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
                    } else if let Insn::ParallelMov { moves } = insn {
                        // Print operands with a special syntax for ParallelMov
                        moves.iter().try_fold(" ", |prefix, (dst, src)| write!(f, "{prefix}{dst} <- {src}").and(Ok(", ")))?;
                    } else if insn.opnd_iter().count() > 0 {
                        insn.opnd_iter().try_fold(" ", |prefix, opnd| write!(f, "{prefix}{opnd}").and(Ok(", ")))?;
                    }

                    write!(f, "\n")?;
                }
            }
        }
        Ok(())
    }
}

impl fmt::Debug for Assembler {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        writeln!(fmt, "Assembler")?;

        for (idx, insn) in self.insns.iter().enumerate() {
            writeln!(fmt, "    {idx:03} {insn:?}")?;
        }

        Ok(())
    }
}

pub struct InsnIter {
    old_insns_iter: std::vec::IntoIter<Insn>,
    peeked: Option<(usize, Insn)>,
    index: usize,
}

impl InsnIter {
    // We're implementing our own peek() because we don't want peek to
    // cross basic blocks as we're iterating.
    pub fn peek(&mut self) -> Option<&(usize, Insn)> {
        // If we don't have a peeked value, get one
        if self.peeked.is_none() {
            let insn = self.old_insns_iter.next()?;
            let idx = self.index;
            self.index += 1;
            self.peeked = Some((idx, insn));
        }
        // Return a reference to the peeked value
        self.peeked.as_ref()
    }

    // Get the next instruction.  Right now we're passing the "new" assembler
    // (the assembler we're copying in to) as a parameter.  Once we've
    // introduced basic blocks to LIR, we'll use the to set the correct BB
    // on the new assembler, but for now it is unused.
    pub fn next(&mut self, _new_asm: &mut Assembler) -> Option<(usize, Insn)> {
        // If we have a peeked value, return it
        if let Some(item) = self.peeked.take() {
            return Some(item);
        }
        // Otherwise get the next from underlying iterator
        let insn = self.old_insns_iter.next()?;
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

    #[allow(dead_code)]
    pub fn breakpoint(&mut self) {
        self.push_insn(Insn::Breakpoint);
    }

    /// Call a C function without PosMarkers
    pub fn ccall(&mut self, fptr: *const u8, opnds: Vec<Opnd>) -> Opnd {
        let canary_opnd = self.set_stack_canary();
        let out = self.new_vreg(Opnd::match_num_bits(&opnds));
        let fptr = Opnd::const_ptr(fptr);
        self.push_insn(Insn::CCall { fptr, opnds, start_marker: None, end_marker: None, out });
        self.clear_stack_canary(canary_opnd);
        out
    }

    /// Call a C function stored in a register
    pub fn ccall_reg(&mut self, fptr: Opnd, num_bits: u8) -> Opnd {
        assert!(matches!(fptr, Opnd::Reg(_)), "ccall_reg must be called with Opnd::Reg: {fptr:?}");
        let out = self.new_vreg(num_bits);
        self.push_insn(Insn::CCall { fptr, opnds: vec![], start_marker: None, end_marker: None, out });
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
        self.push_insn(Insn::CCall {
            fptr: Opnd::const_ptr(fptr),
            opnds,
            start_marker: Some(Rc::new(start_marker)),
            end_marker: Some(Rc::new(end_marker)),
            out,
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

    pub fn cpop_all(&mut self) {
        self.push_insn(Insn::CPopAll);
    }

    pub fn cpop_into(&mut self, opnd: Opnd) {
        assert!(matches!(opnd, Opnd::Reg(_)), "Destination of cpop_into must be a register, got: {opnd:?}");
        self.push_insn(Insn::CPopInto(opnd));
    }

    pub fn cpush(&mut self, opnd: Opnd) {
        self.push_insn(Insn::CPush(opnd));
    }

    pub fn cpush_all(&mut self) {
        self.push_insn(Insn::CPushAll);
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
        let slot_count = self.stack_base_idx;
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

    pub fn jbe(&mut self, target: Target) {
        self.push_insn(Insn::Jbe(target));
    }

    pub fn jb(&mut self, target: Target) {
        self.push_insn(Insn::Jb(target));
    }

    pub fn je(&mut self, target: Target) {
        self.push_insn(Insn::Je(target));
    }

    pub fn jl(&mut self, target: Target) {
        self.push_insn(Insn::Jl(target));
    }

    #[allow(dead_code)]
    pub fn jg(&mut self, target: Target) {
        self.push_insn(Insn::Jg(target));
    }

    #[allow(dead_code)]
    pub fn jge(&mut self, target: Target) {
        self.push_insn(Insn::Jge(target));
    }

    pub fn jmp(&mut self, target: Target) {
        self.push_insn(Insn::Jmp(target));
    }

    pub fn jmp_opnd(&mut self, opnd: Opnd) {
        self.push_insn(Insn::JmpOpnd(opnd));
    }

    pub fn jne(&mut self, target: Target) {
        self.push_insn(Insn::Jne(target));
    }

    pub fn jnz(&mut self, target: Target) {
        self.push_insn(Insn::Jnz(target));
    }

    pub fn jo(&mut self, target: Target) {
        self.push_insn(Insn::Jo(target));
    }

    pub fn jo_mul(&mut self, target: Target) {
        self.push_insn(Insn::JoMul(target));
    }

    pub fn jz(&mut self, target: Target) {
        self.push_insn(Insn::Jz(target));
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
    pub fn live_reg_opnd(&mut self, opnd: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::LiveReg { opnd, out });
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

    pub fn parallel_mov(&mut self, moves: Vec<(Opnd, Opnd)>) {
        self.push_insn(Insn::ParallelMov { moves });
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
        self.push_insn(Insn::PatchPoint { target, invariant, version });
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
}

/// Macro to use format! for Insn::Comment, which skips a format! call
/// when not dumping disassembly.
macro_rules! asm_comment {
    ($asm:expr, $($fmt:tt)*) => {
        // If --zjit-dump-disasm or --zjit-dump-lir is given, enrich them with comments.
        // Also allow --zjit-debug on dev builds to enable comments since dev builds dump LIR on panic.
        let enable_comment = $crate::options::get_option!(dump_disasm) ||
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

// Allow moving Assembler to panic hooks. Since we take the VM lock on compilation,
// no other threads should reference the same Assembler instance.
unsafe impl Send for Insn {}
unsafe impl Sync for Insn {}

/// Dump Assembler with insn_idx on panic. Restore the original panic hook on drop.
pub struct AssemblerPanicHook {
    /// Original panic hook before AssemblerPanicHook is installed.
    prev_hook: Box<dyn Fn(&panic::PanicHookInfo<'_>) + Sync + Send + 'static>,
}

impl AssemblerPanicHook {
    /// Maximum number of lines [`Self::dump_asm`] is allowed to dump by default.
    /// When --zjit-dump-lir is given, this limit is ignored.
    const MAX_DUMP_LINES: usize = 10;

    /// Install a panic hook to dump Assembler with insn_idx on dev builds.
    /// This returns shared references to the previous hook and insn_idx.
    /// It takes insn_idx as an argument so that you can manually use it
    /// on non-emit passes that keep mutating the Assembler to be dumped.
    pub fn new(asm: &Assembler, insn_idx: usize) -> (Option<Arc<Self>>, Option<Arc<Mutex<usize>>>) {
        if cfg!(debug_assertions) {
            // Wrap prev_hook with Arc to share it among the new hook and Self to be dropped.
            let prev_hook = panic::take_hook();
            let panic_hook_ref = Arc::new(Self { prev_hook });
            let weak_hook = Arc::downgrade(&panic_hook_ref);

            // Wrap insn_idx with Arc to share it among the new hook and the caller mutating it.
            let insn_idx = Arc::new(Mutex::new(insn_idx));
            let insn_idx_ref = insn_idx.clone();

            // Install a new hook to dump Assembler with insn_idx
            let asm = asm.clone();
            panic::set_hook(Box::new(move |panic_info| {
                if let Some(panic_hook) = weak_hook.upgrade() {
                    if let Ok(insn_idx) = insn_idx_ref.lock() {
                        // Dump Assembler, highlighting the insn_idx line
                        Self::dump_asm(&asm, *insn_idx);
                    }

                    // Call the previous panic hook
                    (panic_hook.prev_hook)(panic_info);
                }
            }));

            (Some(panic_hook_ref), Some(insn_idx))
        } else {
            (None, None)
        }
    }

    /// Dump Assembler, highlighting the insn_idx line
    fn dump_asm(asm: &Assembler, insn_idx: usize) {
        let lir_string = lir_string(asm);
        let lines: Vec<&str> = lir_string.split('\n').collect();

        // By default, dump only MAX_DUMP_LINES lines.
        // Ignore it if --zjit-dump-lir is given.
        let (min_idx, max_idx) = if get_option!(dump_lir).is_some() {
            (0, lines.len())
        } else {
            (insn_idx.saturating_sub(Self::MAX_DUMP_LINES / 2), insn_idx.saturating_add(Self::MAX_DUMP_LINES / 2))
        };

        eprintln!("Failed to compile LIR at insn_idx={insn_idx}:");
        for (idx, line) in lines.iter().enumerate().filter(|(idx, _)| (min_idx..=max_idx).contains(idx)) {
            if idx == insn_idx && line.starts_with("  ") {
                eprintln!("{BOLD_BEGIN}=>{}{BOLD_END}", &line["  ".len()..]);
            } else {
                eprintln!("{line}");
            }
        }
    }
}

impl Drop for AssemblerPanicHook {
    fn drop(&mut self) {
        // Restore the original hook
        panic::set_hook(std::mem::replace(&mut self.prev_hook, Box::new(|_| {})));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch_reg() -> Opnd {
        Assembler::new_with_scratch_reg().1
    }

    #[test]
    fn test_opnd_iter() {
        let insn = Insn::Add { left: Opnd::None, right: Opnd::None, out: Opnd::None };

        let mut opnd_iter = insn.opnd_iter();
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));

        assert!(opnd_iter.next().is_none());
    }

    #[test]
    fn test_opnd_iter_mut() {
        let mut insn = Insn::Add { left: Opnd::None, right: Opnd::None, out: Opnd::None };

        let mut opnd_iter = insn.opnd_iter_mut();
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));

        assert!(opnd_iter.next().is_none());
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
}
