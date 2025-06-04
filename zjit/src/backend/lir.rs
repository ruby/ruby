use std::collections::HashMap;
use std::fmt;
use std::mem::take;
use crate::cruby::{Qundef, RUBY_OFFSET_CFP_PC, RUBY_OFFSET_CFP_SP, SIZEOF_VALUE_I32, VM_ENV_DATA_SIZE};
use crate::state::ZJITState;
use crate::{cruby::VALUE};
use crate::backend::current::*;
use crate::virtualmem::CodePtr;
use crate::asm::{CodeBlock, Label};
#[cfg(feature = "disasm")]
use crate::options::*;

pub const EC: Opnd = _EC;
pub const CFP: Opnd = _CFP;
pub const SP: Opnd = _SP;

pub const C_ARG_OPNDS: [Opnd; 6] = _C_ARG_OPNDS;
pub const C_RET_OPND: Opnd = _C_RET_OPND;
pub use crate::backend::current::{Reg, C_RET_REG};

// Memory operand base
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MemBase
{
    Reg(u8),
    VReg(usize),
}

// Memory location
#[derive(Copy, Clone, PartialEq, Eq)]
pub struct Mem
{
    // Base register number or instruction index
    pub(super) base: MemBase,

    // Offset relative to the base pointer
    pub(super) disp: i32,

    // Size in bits
    pub(super) num_bits: u8,
}

impl fmt::Debug for Mem {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "Mem{}[{:?}", self.num_bits, self.base)?;
        if self.disp != 0 {
            let sign = if self.disp > 0 { '+' } else { '-' };
            write!(fmt, " {sign} {}", self.disp)?;
        }

        write!(fmt, "]")
    }
}

/// Operand to an IR instruction
#[derive(Clone, Copy, PartialEq, Eq)]
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

impl fmt::Debug for Opnd {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        use Opnd::*;
        match self {
            Self::None => write!(fmt, "None"),
            Value(val) => write!(fmt, "Value({val:?})"),
            VReg { idx, num_bits } => write!(fmt, "Out{num_bits}({idx})"),
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
                    disp: disp,
                    num_bits: num_bits,
                })
            },

            Opnd::VReg{idx, num_bits: out_num_bits } => {
                assert!(num_bits <= out_num_bits);
                Opnd::Mem(Mem {
                    base: MemBase::VReg(idx),
                    disp: disp,
                    num_bits: num_bits,
                })
            },

            _ => unreachable!("memory operand with non-register base")
        }
    }

    /// Constructor for constant pointer operand
    pub fn const_ptr(ptr: *const u8) -> Self {
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

    pub fn with_num_bits(&self, num_bits: u8) -> Option<Opnd> {
        assert!(num_bits == 8 || num_bits == 16 || num_bits == 32 || num_bits == 64);
        match *self {
            Opnd::Reg(reg) => Some(Opnd::Reg(reg.with_num_bits(num_bits))),
            Opnd::Mem(Mem { base, disp, .. }) => Some(Opnd::Mem(Mem { base, disp, num_bits })),
            Opnd::VReg { idx, .. } => Some(Opnd::VReg { idx, num_bits }),
            //Opnd::Stack { idx, stack_size, num_locals, sp_offset, reg_mapping, .. } => Some(Opnd::Stack { idx, num_bits, stack_size, num_locals, sp_offset, reg_mapping }),
            _ => None,
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

    /*
    /// Convert Opnd::Stack into RegMapping
    pub fn reg_opnd(&self) -> RegOpnd {
        self.get_reg_opnd().unwrap()
    }

    /// Convert an operand into RegMapping if it's Opnd::Stack
    pub fn get_reg_opnd(&self) -> Option<RegOpnd> {
        match *self {
            Opnd::Stack { idx, stack_size, num_locals, .. } => Some(
                if let Some(num_locals) = num_locals {
                    let last_idx = stack_size as i32 + VM_ENV_DATA_SIZE as i32 - 1;
                    assert!(last_idx <= idx, "Local index {} must be >= last local index {}", idx, last_idx);
                    assert!(idx <= last_idx + num_locals as i32, "Local index {} must be < last local index {} + local size {}", idx, last_idx, num_locals);
                    RegOpnd::Local((last_idx + num_locals as i32 - idx) as u8)
                } else {
                    assert!(idx < stack_size as i32);
                    RegOpnd::Stack((stack_size as i32 - idx - 1) as u8)
                }
            ),
            _ => None,
        }
    }
    */
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

/// Branch target (something that we can jump to)
/// for branch instructions
#[derive(Clone, Debug)]
pub enum Target
{
    /// Pointer to a piece of ZJIT-generated code
    CodePtr(CodePtr),
    // Side exit with a counter
    SideExit { pc: *const VALUE, stack: Vec<Opnd>, locals: Vec<Opnd> },
    /// A label within the generated code
    Label(Label),
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

type PosMarkerFn = Box<dyn Fn(CodePtr, &CodeBlock)>;

/// ZJIT Low-level IR instruction
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
        fptr: *const u8,
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
    FrameSetup,

    /// Tear down the frame stack as necessary per the architecture.
    FrameTeardown,

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

    /// A set of parallel moves into registers.
    /// The backend breaks cycles if there are any cycles between moves.
    ParallelMov { moves: Vec<(Reg, Opnd)> },

    // A low-level mov instruction. It accepts two operands.
    Mov { dest: Opnd, src: Opnd },

    // Perform the NOT operation on an individual operand, and return the result
    // as a new operand. This operand can then be used as the operand on another
    // instruction.
    Not { opnd: Opnd, out: Opnd },

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary OR operation.
    Or { left: Opnd, right: Opnd, out: Opnd },

    /// Pad nop instructions to accommodate Op::Jmp in case the block or the insn
    /// is invalidated.
    PadInvalPatch,

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
    pub(super) fn opnd_iter(&self) -> InsnOpndIterator {
        InsnOpndIterator::new(self)
    }

    /// Create an iterator that will yield a mutable reference to each operand
    /// in turn for this instruction.
    pub(super) fn opnd_iter_mut(&mut self) -> InsnOpndMutIterator {
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
            Insn::LeaJumpTarget { target, .. } => {
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
            Insn::FrameSetup => "FrameSetup",
            Insn::FrameTeardown => "FrameTeardown",
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
            Insn::PadInvalPatch => "PadEntryExit",
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
            Insn::LeaJumpTarget { target, .. } => Some(target),
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
            Insn::LeaJumpTarget { target, .. } => {
                if let Target::SideExit { stack, locals, .. } = target {
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

                if let Target::SideExit { stack, locals, .. } = target {
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
            Insn::FrameSetup |
            Insn::FrameTeardown |
            Insn::PadInvalPatch |
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
                if self.idx < moves.len() {
                    let opnd = &moves[self.idx].1;
                    self.idx += 1;
                    Some(opnd)
                } else {
                    None
                }
            },
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
            Insn::LeaJumpTarget { target, .. } => {
                if let Target::SideExit { stack, locals, .. } = target {
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

                if let Target::SideExit { stack, locals, .. } = target {
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
            Insn::FrameSetup |
            Insn::FrameTeardown |
            Insn::PadInvalPatch |
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
                if self.idx < moves.len() {
                    let opnd = &mut moves[self.idx].1;
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
}

impl RegisterPool {
    /// Initialize a register pool
    fn new(regs: Vec<Reg>) -> Self {
        let pool = vec![None; regs.len()];
        RegisterPool {
            regs,
            pool,
            live_regs: 0,
        }
    }

    /// Mutate the pool to indicate that the register at the index
    /// has been allocated and is live.
    fn alloc_reg(&mut self, vreg_idx: usize) -> Option<Reg> {
        for (reg_idx, reg) in self.regs.iter().enumerate() {
            if self.pool[reg_idx].is_none() {
                self.pool[reg_idx] = Some(vreg_idx);
                self.live_regs += 1;
                return Some(*reg);
            }
        }
        None
    }

    /// Allocate a specific register
    fn take_reg(&mut self, reg: &Reg, vreg_idx: usize) -> Reg {
        let reg_idx = self.regs.iter().position(|elem| elem.reg_no == reg.reg_no)
            .unwrap_or_else(|| panic!("Unable to find register: {}", reg.reg_no));
        assert_eq!(self.pool[reg_idx], None, "register already allocated");
        self.pool[reg_idx] = Some(vreg_idx);
        self.live_regs += 1;
        *reg
    }

    // Mutate the pool to indicate that the given register is being returned
    // as it is no longer used by the instruction that previously held it.
    fn dealloc_reg(&mut self, reg: &Reg) {
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
pub struct Assembler {
    pub(super) insns: Vec<Insn>,

    /// Live range for each VReg indexed by its `idx``
    pub(super) live_ranges: Vec<LiveRange>,

    /// Names of labels
    pub(super) label_names: Vec<String>,

    /*
    /// Context for generating the current insn
    pub ctx: Context,

    /// The current ISEQ's local table size. asm.local_opnd() uses this, and it's
    /// sometimes hard to pass this value, e.g. asm.spill_regs() in asm.ccall().
    ///
    /// `None` means we're not assembling for an ISEQ, or that the local size is
    /// not relevant.
    pub(super) num_locals: Option<u32>,

    /// Side exit caches for each SideExitContext
    pub(super) side_exits: HashMap<SideExitContext, CodePtr>,

    /// PC for Target::SideExit
    side_exit_pc: Option<*mut VALUE>,

    /// Stack size for Target::SideExit
    side_exit_stack_size: Option<u8>,

    /// If true, the next ccall() should verify its leafness
    leaf_ccall: bool,
    */
}

impl Assembler
{
    /// Create an Assembler
    pub fn new() -> Self {
        Self::new_with_label_names(Vec::default(), 0)
    }

    /*
    /// Create an Assembler for ISEQ-specific code.
    /// It includes all inline code and some outlined code like side exits and stubs.
    pub fn new(num_locals: u32) -> Self {
        Self::new_with_label_names(Vec::default(), HashMap::default(), Some(num_locals))
    }

    /// Create an Assembler for outlined code that are not specific to any ISEQ,
    /// e.g. trampolines that are shared globally.
    pub fn new_without_iseq() -> Self {
        Self::new_with_label_names(Vec::default(), HashMap::default(), None)
    }
    */

    /// Create an Assembler with parameters that are populated by another Assembler instance.
    /// This API is used for copying an Assembler for the next compiler pass.
    pub fn new_with_label_names(label_names: Vec<String>, num_vregs: usize) -> Self {
        let mut live_ranges = Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY);
        live_ranges.resize(num_vregs, LiveRange { start: None, end: None });

        Self {
            insns: Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY),
            live_ranges,
            label_names,
        }
    }

    /*
    /// Get the list of registers that can be used for stack temps.
    pub fn get_temp_regs2() -> &'static [Reg] {
        let num_regs = get_option!(num_temp_regs);
        &TEMP_REGS[0..num_regs]
    }

    /// Get the number of locals for the ISEQ being compiled
    pub fn get_num_locals(&self) -> Option<u32> {
        self.num_locals
    }

    /// Set a context for generating side exits
    pub fn set_side_exit_context(&mut self, pc: *mut VALUE, stack_size: u8) {
        self.side_exit_pc = Some(pc);
        self.side_exit_stack_size = Some(stack_size);
    }
    */

    /// Build an Opnd::VReg and initialize its LiveRange
    pub(super) fn new_vreg(&mut self, num_bits: u8) -> Opnd {
        let vreg = Opnd::VReg { idx: self.live_ranges.len(), num_bits };
        self.live_ranges.push(LiveRange { start: None, end: None });
        vreg
    }

    /// Append an instruction onto the current list of instructions and update
    /// the live ranges of any instructions whose outputs are being used as
    /// operands to this instruction.
    pub fn push_insn(&mut self, mut insn: Insn) {
        // Index of this instruction
        let insn_idx = self.insns.len();

        // Initialize the live range of the output VReg to insn_idx..=insn_idx
        if let Some(Opnd::VReg { idx, .. }) = insn.out_opnd() {
            assert!(*idx < self.live_ranges.len());
            assert_eq!(self.live_ranges[*idx], LiveRange { start: None, end: None });
            self.live_ranges[*idx] = LiveRange { start: Some(insn_idx), end: Some(insn_idx) };
        }

        // If we find any VReg from previous instructions, extend the live range to insn_idx
        let mut opnd_iter = insn.opnd_iter_mut();
        while let Some(opnd) = opnd_iter.next() {
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

        self.insns.push(insn);
    }

    /*
    /// Get a cached side exit, wrapping a counter if specified
    pub fn get_side_exit(&mut self, side_exit_context: &SideExitContext, counter: Option<Counter>, ocb: &mut OutlinedCb) -> Option<CodePtr> {
        // Get a cached side exit
        let side_exit = match self.side_exits.get(&side_exit_context) {
            None => {
                let exit_code = gen_outlined_exit(side_exit_context.pc, self.num_locals.unwrap(), &side_exit_context.get_ctx(), ocb)?;
                self.side_exits.insert(*side_exit_context, exit_code);
                exit_code
            }
            Some(code_ptr) => *code_ptr,
        };

        // Wrap a counter if needed
        gen_counted_exit(side_exit_context.pc, side_exit, ocb, counter)
    }
    */

    /// Create a new label instance that we can jump to
    pub fn new_label(&mut self, name: &str) -> Target
    {
        assert!(!name.contains(' '), "use underscores in label names, not spaces");

        let label = Label(self.label_names.len());
        self.label_names.push(name.to_string());
        Target::Label(label)
    }

    /*
    /// Convert Opnd::Stack to Opnd::Mem or Opnd::Reg
    pub fn lower_stack_opnd(&self, opnd: &Opnd) -> Opnd {
        // Convert Opnd::Stack to Opnd::Mem
        fn mem_opnd(opnd: &Opnd) -> Opnd {
            if let Opnd::Stack { idx, sp_offset, num_bits, .. } = *opnd {
                incr_counter!(temp_mem_opnd);
                Opnd::mem(num_bits, SP, (sp_offset as i32 - idx - 1) * SIZEOF_VALUE_I32)
            } else {
                unreachable!()
            }
        }

        // Convert Opnd::Stack to Opnd::Reg
        fn reg_opnd(opnd: &Opnd, reg_idx: usize) -> Opnd {
            let regs = Assembler::get_temp_regs2();
            if let Opnd::Stack { num_bits, .. } = *opnd {
                incr_counter!(temp_reg_opnd);
                Opnd::Reg(regs[reg_idx]).with_num_bits(num_bits).unwrap()
            } else {
                unreachable!()
            }
        }

        match opnd {
            Opnd::Stack { reg_mapping, .. } => {
                if let Some(reg_idx) = reg_mapping.unwrap().get_reg(opnd.reg_opnd()) {
                    reg_opnd(opnd, reg_idx)
                } else {
                    mem_opnd(opnd)
                }
            }
            _ => unreachable!(),
        }
    }

    /// Allocate a register to a stack temp if available.
    pub fn alloc_reg(&mut self, mapping: RegOpnd) {
        // Allocate a register if there's no conflict.
        let mut reg_mapping = self.ctx.get_reg_mapping();
        if reg_mapping.alloc_reg(mapping) {
            self.set_reg_mapping(reg_mapping);
        }
    }

    /// Erase local variable type information
    /// eg: because of a call we can't track
    pub fn clear_local_types(&mut self) {
        asm_comment!(self, "clear local variable types");
        self.ctx.clear_local_types();
    }

    /// Repurpose stack temp registers to the corresponding locals for arguments
    pub fn map_temp_regs_to_args(&mut self, callee_ctx: &mut Context, argc: i32) -> Vec<RegOpnd> {
        let mut callee_reg_mapping = callee_ctx.get_reg_mapping();
        let mut mapped_temps = vec![];

        for arg_idx in 0..argc {
            let stack_idx: u8 = (self.ctx.get_stack_size() as i32 - argc + arg_idx).try_into().unwrap();
            let temp_opnd = RegOpnd::Stack(stack_idx);

            // For each argument, if the stack temp for it has a register,
            // let the callee use the register for the local variable.
            if let Some(reg_idx) = self.ctx.get_reg_mapping().get_reg(temp_opnd) {
                let local_opnd = RegOpnd::Local(arg_idx.try_into().unwrap());
                callee_reg_mapping.set_reg(local_opnd, reg_idx);
                mapped_temps.push(temp_opnd);
            }
        }

        asm_comment!(self, "local maps: {:?}", callee_reg_mapping);
        callee_ctx.set_reg_mapping(callee_reg_mapping);
        mapped_temps
    }

    /// Spill all live registers to the stack
    pub fn spill_regs(&mut self) {
        self.spill_regs_except(&vec![]);
    }

    /// Spill all live registers except `ignored_temps` to the stack
    pub fn spill_regs_except(&mut self, ignored_temps: &Vec<RegOpnd>) {
        // Forget registers above the stack top
        let mut reg_mapping = self.ctx.get_reg_mapping();
        for stack_idx in self.ctx.get_stack_size()..MAX_CTX_TEMPS as u8 {
            reg_mapping.dealloc_reg(RegOpnd::Stack(stack_idx));
        }
        self.set_reg_mapping(reg_mapping);

        // If no registers are in use, skip all checks
        if self.ctx.get_reg_mapping() == RegMapping::default() {
            return;
        }

        // Collect stack temps to be spilled
        let mut spilled_opnds = vec![];
        for stack_idx in 0..u8::min(MAX_CTX_TEMPS as u8, self.ctx.get_stack_size()) {
            let reg_opnd = RegOpnd::Stack(stack_idx);
            if !ignored_temps.contains(&reg_opnd) && reg_mapping.dealloc_reg(reg_opnd) {
                let idx = self.ctx.get_stack_size() - 1 - stack_idx;
                let spilled_opnd = self.stack_opnd(idx.into());
                spilled_opnds.push(spilled_opnd);
                reg_mapping.dealloc_reg(spilled_opnd.reg_opnd());
            }
        }

        // Collect locals to be spilled
        for local_idx in 0..MAX_CTX_TEMPS as u8 {
            if reg_mapping.dealloc_reg(RegOpnd::Local(local_idx)) {
                let first_local_ep_offset = self.num_locals.unwrap() + VM_ENV_DATA_SIZE - 1;
                let ep_offset = first_local_ep_offset - local_idx as u32;
                let spilled_opnd = self.local_opnd(ep_offset);
                spilled_opnds.push(spilled_opnd);
                reg_mapping.dealloc_reg(spilled_opnd.reg_opnd());
            }
        }

        // Spill stack temps and locals
        if !spilled_opnds.is_empty() {
            asm_comment!(self, "spill_regs: {:?} -> {:?}", self.ctx.get_reg_mapping(), reg_mapping);
            for &spilled_opnd in spilled_opnds.iter() {
                self.spill_reg(spilled_opnd);
            }
            self.ctx.set_reg_mapping(reg_mapping);
        }
    }

    /// Spill a stack temp from a register to the stack
    pub fn spill_reg(&mut self, opnd: Opnd) {
        assert_ne!(self.ctx.get_reg_mapping().get_reg(opnd.reg_opnd()), None);

        // Use different RegMappings for dest and src operands
        let reg_mapping = self.ctx.get_reg_mapping();
        let mut mem_mappings = reg_mapping;
        mem_mappings.dealloc_reg(opnd.reg_opnd());

        // Move the stack operand from a register to memory
        match opnd {
            Opnd::Stack { idx, num_bits, stack_size, num_locals, sp_offset, .. } => {
                self.mov(
                    Opnd::Stack { idx, num_bits, stack_size, num_locals, sp_offset, reg_mapping: Some(mem_mappings) },
                    Opnd::Stack { idx, num_bits, stack_size, num_locals, sp_offset, reg_mapping: Some(reg_mapping) },
                );
            }
            _ => unreachable!(),
        }
        incr_counter!(temp_spill);
    }

    /// Update which stack temps are in a register
    pub fn set_reg_mapping(&mut self, reg_mapping: RegMapping) {
        if self.ctx.get_reg_mapping() != reg_mapping {
            asm_comment!(self, "reg_mapping: {:?} -> {:?}", self.ctx.get_reg_mapping(), reg_mapping);
            self.ctx.set_reg_mapping(reg_mapping);
        }
    }
    */

    // Shuffle register moves, sometimes adding extra moves using SCRATCH_REG,
    // so that they will not rewrite each other before they are used.
    pub fn resolve_parallel_moves(old_moves: &Vec<(Reg, Opnd)>) -> Vec<(Reg, Opnd)> {
        // Return the index of a move whose destination is not used as a source if any.
        fn find_safe_move(moves: &Vec<(Reg, Opnd)>) -> Option<usize> {
            moves.iter().enumerate().find(|&(_, &(dest_reg, _))| {
                moves.iter().all(|&(_, src_opnd)| src_opnd != Opnd::Reg(dest_reg))
            }).map(|(index, _)| index)
        }

        // Remove moves whose source and destination are the same
        let mut old_moves: Vec<(Reg, Opnd)> = old_moves.clone().into_iter()
            .filter(|&(reg, opnd)| Opnd::Reg(reg) != opnd).collect();

        let mut new_moves = vec![];
        while !old_moves.is_empty() {
            // Keep taking safe moves
            while let Some(index) = find_safe_move(&old_moves) {
                new_moves.push(old_moves.remove(index));
            }

            // No safe move. Load the source of one move into SCRATCH_REG, and
            // then load SCRATCH_REG into the destination when it's safe.
            if !old_moves.is_empty() {
                // Make sure it's safe to use SCRATCH_REG
                assert!(old_moves.iter().all(|&(_, opnd)| opnd != Opnd::Reg(Assembler::SCRATCH_REG)));

                // Move SCRATCH <- opnd, and delay reg <- SCRATCH
                let (reg, opnd) = old_moves.remove(0);
                new_moves.push((Assembler::SCRATCH_REG, opnd));
                old_moves.push((reg, Opnd::Reg(Assembler::SCRATCH_REG)));
            }
        }
        new_moves
    }

    /// Sets the out field on the various instructions that require allocated
    /// registers because their output is used as the operand on a subsequent
    /// instruction. This is our implementation of the linear scan algorithm.
    pub(super) fn alloc_regs(mut self, regs: Vec<Reg>) -> Assembler {
        // Dump live registers for register spill debugging.
        fn dump_live_regs(insns: Vec<Insn>, live_ranges: Vec<LiveRange>, num_regs: usize, spill_index: usize) {
            // Convert live_ranges to live_regs: the number of live registers at each index
            let mut live_regs: Vec<usize> = vec![];
            for insn_idx in 0..insns.len() {
                let live_count = live_ranges.iter().filter(|range| range.start() <= insn_idx && insn_idx <= range.end()).count();
                live_regs.push(live_count);
            }

            // Dump insns along with live registers
            for (insn_idx, insn) in insns.iter().enumerate() {
                eprint!("{:3} ", if spill_index == insn_idx { "==>" } else { "" });
                for reg in 0..=num_regs {
                    eprint!("{:1}", if reg < live_regs[insn_idx] { "|" } else { "" });
                }
                eprintln!(" [{:3}] {:?}", insn_idx, insn);
            }
        }

        // First, create the pool of registers.
        let mut pool = RegisterPool::new(regs.clone());

        // Mapping between VReg and allocated VReg for each VReg index.
        // None if no register has been allocated for the VReg.
        let mut reg_mapping: Vec<Option<Reg>> = vec![None; self.live_ranges.len()];

        // List of registers saved before a C call, paired with the VReg index.
        let mut saved_regs: Vec<(Reg, usize)> = vec![];

        // live_ranges is indexed by original `index` given by the iterator.
        let live_ranges: Vec<LiveRange> = take(&mut self.live_ranges);
        let mut iterator = self.insns.into_iter().enumerate().peekable();
        let mut asm = Assembler::new_with_label_names(take(&mut self.label_names), live_ranges.len());

        while let Some((index, mut insn)) = iterator.next() {
            let before_ccall = match (&insn, iterator.peek().map(|(_, insn)| insn)) {
                (Insn::ParallelMov { .. }, Some(Insn::CCall { .. })) |
                (Insn::CCall { .. }, _) if !pool.is_empty() => {
                    // If C_RET_REG is in use, move it to another register.
                    // This must happen before last-use registers are deallocated.
                    if let Some(vreg_idx) = pool.vreg_for(&C_RET_REG) {
                        let new_reg = pool.alloc_reg(vreg_idx).unwrap(); // TODO: support spill
                        asm.mov(Opnd::Reg(new_reg), C_RET_OPND);
                        pool.dealloc_reg(&C_RET_REG);
                        reg_mapping[vreg_idx] = Some(new_reg);
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
                            if let Some(reg) = reg_mapping[idx] {
                                pool.dealloc_reg(&reg);
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
                    pool.dealloc_reg(&reg);
                }
                // On x86_64, maintain 16-byte stack alignment
                if cfg!(target_arch = "x86_64") && saved_regs.len() % 2 == 1 {
                    asm.cpush(Opnd::Reg(saved_regs.last().unwrap().0));
                }
            }

            // If the output VReg of this instruction is used by another instruction,
            // we need to allocate a register to it
            let vreg_idx = match insn.out_opnd() {
                Some(Opnd::VReg { idx, .. }) => Some(*idx),
                _ => None,
            };
            if vreg_idx.is_some() && live_ranges[vreg_idx.unwrap()].end() != index {
                // This is going to be the output operand that we will set on the
                // instruction. CCall and LiveReg need to use a specific register.
                let mut out_reg = match insn {
                    Insn::CCall { .. } => {
                        Some(pool.take_reg(&C_RET_REG, vreg_idx.unwrap()))
                    }
                    Insn::LiveReg { opnd, .. } => {
                        let reg = opnd.unwrap_reg();
                        Some(pool.take_reg(&reg, vreg_idx.unwrap()))
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
                            if let Some(reg) = reg_mapping[*idx] {
                                out_reg = Some(pool.take_reg(&reg, vreg_idx.unwrap()));
                            }
                        }
                    }
                }

                // Allocate a new register for this instruction if one is not
                // already allocated.
                if out_reg.is_none() {
                    out_reg = match &insn {
                        _ => match pool.alloc_reg(vreg_idx.unwrap()) {
                            Some(reg) => Some(reg),
                            None => {
                                let mut insns = asm.insns;
                                insns.push(insn);
                                while let Some((_, insn)) = iterator.next() {
                                    insns.push(insn);
                                }
                                dump_live_regs(insns, live_ranges, regs.len(), index);
                                unreachable!("Register spill not supported");
                            }
                        }
                    };
                }

                // Set the output operand on the instruction
                let out_num_bits = Opnd::match_num_bits_iter(insn.opnd_iter());

                // If we have gotten to this point, then we're sure we have an
                // output operand on this instruction because the live range
                // extends beyond the index of the instruction.
                let out = insn.out_opnd_mut().unwrap();
                let reg = out_reg.unwrap().with_num_bits(out_num_bits);
                reg_mapping[out.vreg_idx()] = Some(reg);
                *out = Opnd::Reg(reg);
            }

            // Replace VReg and Param operands by their corresponding register
            let mut opnd_iter = insn.opnd_iter_mut();
            while let Some(opnd) = opnd_iter.next() {
                match *opnd {
                    Opnd::VReg { idx, num_bits } => {
                        *opnd = Opnd::Reg(reg_mapping[idx].unwrap()).with_num_bits(num_bits).unwrap();
                    },
                    Opnd::Mem(Mem { base: MemBase::VReg(idx), disp, num_bits }) => {
                        let base = MemBase::Reg(reg_mapping[idx].unwrap().reg_no);
                        *opnd = Opnd::Mem(Mem { base, disp, num_bits });
                    }
                    _ => {},
                }
            }

            // Push instruction(s)
            let is_ccall = matches!(insn, Insn::CCall { .. });
            match insn {
                Insn::ParallelMov { moves } => {
                    // Now that register allocation is done, it's ready to resolve parallel moves.
                    for (reg, opnd) in Self::resolve_parallel_moves(&moves) {
                        asm.load_into(Opnd::Reg(reg), opnd);
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
                _ => asm.push_insn(insn),
            }

            // After a C call, restore caller-saved registers
            if is_ccall {
                // On x86_64, maintain 16-byte stack alignment
                if cfg!(target_arch = "x86_64") && saved_regs.len() % 2 == 1 {
                    asm.cpop_into(Opnd::Reg(saved_regs.last().unwrap().0.clone()));
                }
                // Restore saved registers
                for &(reg, vreg_idx) in saved_regs.iter().rev() {
                    asm.cpop_into(Opnd::Reg(reg));
                    pool.take_reg(&reg, vreg_idx);
                }
                saved_regs.clear();
            }
        }

        assert!(pool.is_empty(), "Expected all registers to be returned to the pool");
        asm
    }

    /// Compile the instructions down to machine code.
    /// Can fail due to lack of code memory and inopportune code placement, among other reasons.
    #[must_use]
    pub fn compile(self, cb: &mut CodeBlock) -> Option<(CodePtr, Vec<u32>)>
    {
        #[cfg(feature = "disasm")]
        let start_addr = cb.get_write_ptr();
        let alloc_regs = Self::get_alloc_regs();
        let ret = self.compile_with_regs(cb, alloc_regs);

        #[cfg(feature = "disasm")]
        if get_option!(dump_disasm) {
            let end_addr = cb.get_write_ptr();
            let disasm = crate::disasm::disasm_addr_range(cb, start_addr.raw_ptr(cb) as usize, end_addr.raw_ptr(cb) as usize);
            println!("{}", disasm);
        }
        ret
    }

    /// Compile Target::SideExit and convert it into Target::CodePtr for all instructions
    #[must_use]
    pub fn compile_side_exits(&mut self) -> Option<()> {
        let mut targets = HashMap::new();
        for (idx, insn) in self.insns.iter().enumerate() {
            if let Some(target @ Target::SideExit { .. }) = insn.target() {
                targets.insert(idx, target.clone());
            }
        }

        for (idx, target) in targets {
            // Compile a side exit. Note that this is past the split pass and alloc_regs(),
            // so you can't use a VReg or an instruction that needs to be split.
            if let Target::SideExit { pc, stack, locals } = target {
                let side_exit_label = self.new_label("side_exit".into());
                self.write_label(side_exit_label.clone());

                // Load an operand that cannot be used as a source of Insn::Store
                fn split_store_source(asm: &mut Assembler, opnd: Opnd) -> Opnd {
                    if matches!(opnd, Opnd::Mem(_) | Opnd::Value(_)) ||
                        (cfg!(target_arch = "aarch64") && matches!(opnd, Opnd::UImm(_))) {
                        asm.load_into(Opnd::Reg(Assembler::SCRATCH_REG), opnd);
                        Opnd::Reg(Assembler::SCRATCH_REG)
                    } else {
                        opnd
                    }
                }

                asm_comment!(self, "write stack slots: {stack:?}");
                for (idx, &opnd) in stack.iter().enumerate() {
                    let opnd = split_store_source(self, opnd);
                    self.store(Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32), opnd);
                }

                asm_comment!(self, "write locals: {locals:?}");
                for (idx, &opnd) in locals.iter().enumerate() {
                    let opnd = split_store_source(self, opnd);
                    self.store(Opnd::mem(64, SP, (-(VM_ENV_DATA_SIZE as i32) - locals.len() as i32 + idx as i32) * SIZEOF_VALUE_I32), opnd);
                }

                asm_comment!(self, "save cfp->pc");
                self.load_into(Opnd::Reg(Assembler::SCRATCH_REG), Opnd::const_ptr(pc as *const u8));
                self.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::Reg(Assembler::SCRATCH_REG));

                asm_comment!(self, "save cfp->sp");
                self.lea_into(Opnd::Reg(Assembler::SCRATCH_REG), Opnd::mem(64, SP, stack.len() as i32 * SIZEOF_VALUE_I32));
                let cfp_sp = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
                self.store(cfp_sp, Opnd::Reg(Assembler::SCRATCH_REG));

                asm_comment!(self, "rewind caller frames");
                self.mov(C_ARG_OPNDS[0], Assembler::return_addr_opnd());
                self.ccall(Self::rewind_caller_frames as *const u8, vec![]);

                asm_comment!(self, "exit to the interpreter");
                self.frame_teardown();
                self.mov(C_RET_OPND, Opnd::UImm(Qundef.as_u64()));
                self.cret(C_RET_OPND);

                *self.insns[idx].target_mut().unwrap() = side_exit_label;
            }
        }
        Some(())
    }

    #[unsafe(no_mangle)]
    extern "C" fn rewind_caller_frames(addr: *const u8) {
        if ZJITState::is_iseq_return_addr(addr) {
            unimplemented!("Can't side-exit from JIT-JIT call: rewind_caller_frames is not implemented yet");
        }
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

impl Assembler {
    #[must_use]
    pub fn add(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Add { left, right, out });
        out
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
        let out = self.new_vreg(Opnd::match_num_bits(&opnds));
        self.push_insn(Insn::CCall { fptr, opnds, start_marker: None, end_marker: None, out });
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
            fptr,
            opnds,
            start_marker: Some(Box::new(start_marker)),
            end_marker: Some(Box::new(end_marker)),
            out,
        });
        out
    }

    /*
    /// Let vm_check_canary() assert the leafness of this ccall if leaf_ccall is set
    fn set_stack_canary(&mut self, opnds: &Vec<Opnd>) -> Option<Opnd> {
        // Use the slot right above the stack top for verifying leafness.
        let canary_opnd = self.stack_opnd(-1);

        // If the slot is already used, which is a valid optimization to avoid spills,
        // give up the verification.
        let canary_opnd = if cfg!(feature = "runtime_checks") && self.leaf_ccall && opnds.iter().all(|opnd|
            opnd.get_reg_opnd() != canary_opnd.get_reg_opnd()
        ) {
            asm_comment!(self, "set stack canary");
            self.mov(canary_opnd, vm_stack_canary().into());
            Some(canary_opnd)
        } else {
            None
        };

        // Avoid carrying the flag to the next instruction whether we verified it or not.
        self.leaf_ccall = false;

        canary_opnd
    }
    */

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

        // Re-enable ccall's RegMappings assertion disabled by cpush_all.
        // cpush_all + cpop_all preserve all stack temp registers, so it's safe.
        //self.set_reg_mapping(self.ctx.get_reg_mapping());
    }

    pub fn cpop_into(&mut self, opnd: Opnd) {
        self.push_insn(Insn::CPopInto(opnd));
    }

    pub fn cpush(&mut self, opnd: Opnd) {
        self.push_insn(Insn::CPush(opnd));
    }

    pub fn cpush_all(&mut self) {
        self.push_insn(Insn::CPushAll);

        // Mark all temps as not being in registers.
        // Temps will be marked back as being in registers by cpop_all.
        // We assume that cpush_all + cpop_all are used for C functions in utils.rs
        // that don't require spill_regs for GC.
        //self.set_reg_mapping(RegMapping::default());
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

    pub fn frame_setup(&mut self) {
        self.push_insn(Insn::FrameSetup);
    }

    pub fn frame_teardown(&mut self) {
        self.push_insn(Insn::FrameTeardown);
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

    pub fn parallel_mov(&mut self, moves: Vec<(Reg, Opnd)>) {
        self.push_insn(Insn::ParallelMov { moves });
    }

    pub fn mov(&mut self, dest: Opnd, src: Opnd) {
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

    pub fn pad_inval_patch(&mut self) {
        self.push_insn(Insn::PadInvalPatch);
    }

    //pub fn pos_marker<F: FnMut(CodePtr)>(&mut self, marker_fn: F)
    pub fn pos_marker(&mut self, marker_fn: impl Fn(CodePtr, &CodeBlock) + 'static) {
        self.push_insn(Insn::PosMarker(Box::new(marker_fn)));
    }

    #[must_use]
    pub fn rshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::RShift { opnd, shift, out });
        out
    }

    pub fn store(&mut self, dest: Opnd, src: Opnd) {
        self.push_insn(Insn::Store { dest, src });
    }

    #[must_use]
    pub fn sub(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.new_vreg(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Sub { left, right, out });
        out
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

    /*
    /// Verify the leafness of the given block
    pub fn with_leaf_ccall<F, R>(&mut self, mut block: F) -> R
    where F: FnMut(&mut Self) -> R {
        let old_leaf_ccall = self.leaf_ccall;
        self.leaf_ccall = true;
        let ret = block(self);
        self.leaf_ccall = old_leaf_ccall;
        ret
    }
    */

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
        if $crate::options::get_option!(dump_disasm) {
            $asm.push_insn(crate::backend::lir::Insn::Comment(format!($($fmt)*)));
        }
    };
}
pub(crate) use asm_comment;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_opnd_iter() {
        let insn = Insn::Add { left: Opnd::None, right: Opnd::None, out: Opnd::None };

        let mut opnd_iter = insn.opnd_iter();
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));

        assert!(matches!(opnd_iter.next(), None));
    }

    #[test]
    fn test_opnd_iter_mut() {
        let mut insn = Insn::Add { left: Opnd::None, right: Opnd::None, out: Opnd::None };

        let mut opnd_iter = insn.opnd_iter_mut();
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));
        assert!(matches!(opnd_iter.next(), Some(Opnd::None)));

        assert!(matches!(opnd_iter.next(), None));
    }
}

