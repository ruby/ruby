use std::collections::HashMap;
use std::fmt;
use std::convert::From;
use std::mem::take;
use crate::codegen::{gen_outlined_exit, gen_counted_exit};
use crate::cruby::{vm_stack_canary, SIZEOF_VALUE_I32, VALUE};
use crate::virtualmem::CodePtr;
use crate::asm::{CodeBlock, OutlinedCb};
use crate::core::{Context, RegTemps, MAX_REG_TEMPS};
use crate::options::*;
use crate::stats::*;

use crate::backend::current::*;

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
    InsnOut(usize),
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

    /// C argument register. The alloc_regs resolves its register dependencies.
    CArg(Reg),

    // Output of a preceding instruction in this block
    InsnOut{ idx: usize, num_bits: u8 },

    /// Pointer to a slot on the VM stack
    Stack {
        /// Index from stack top. Used for conversion to StackOpnd.
        idx: i32,
        /// Number of bits for Opnd::Reg and Opnd::Mem.
        num_bits: u8,
        /// ctx.stack_size when this operand is made. Used with idx for Opnd::Reg.
        stack_size: u8,
        /// ctx.sp_offset when this operand is made. Used with idx for Opnd::Mem.
        sp_offset: i8,
        /// ctx.reg_temps when this operand is read. Used for register allocation.
        reg_temps: Option<RegTemps>
    },

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
            CArg(reg) => write!(fmt, "CArg({reg:?})"),
            Stack { idx, sp_offset, .. } => write!(fmt, "SP[{}]", *sp_offset as i32 - idx - 1),
            InsnOut { idx, num_bits } => write!(fmt, "Out{num_bits}({idx})"),
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

            Opnd::InsnOut{idx, num_bits: out_num_bits } => {
                assert!(num_bits <= out_num_bits);
                Opnd::Mem(Mem {
                    base: MemBase::InsnOut(idx),
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

    /// Constructor for a C argument operand
    pub fn c_arg(reg_opnd: Opnd) -> Self {
        match reg_opnd {
            Opnd::Reg(reg) => Opnd::CArg(reg),
            _ => unreachable!(),
        }
    }

    /// Unwrap a register operand
    pub fn unwrap_reg(&self) -> Reg {
        match self {
            Opnd::Reg(reg) => *reg,
            _ => unreachable!("trying to unwrap {:?} into reg", self)
        }
    }

    /// Get the size in bits for this operand if there is one.
    pub fn num_bits(&self) -> Option<u8> {
        match *self {
            Opnd::Reg(Reg { num_bits, .. }) => Some(num_bits),
            Opnd::Mem(Mem { num_bits, .. }) => Some(num_bits),
            Opnd::InsnOut { num_bits, .. } => Some(num_bits),
            _ => None
        }
    }

    pub fn with_num_bits(&self, num_bits: u8) -> Option<Opnd> {
        assert!(num_bits == 8 || num_bits == 16 || num_bits == 32 || num_bits == 64);
        match *self {
            Opnd::Reg(reg) => Some(Opnd::Reg(reg.with_num_bits(num_bits))),
            Opnd::Mem(Mem { base, disp, .. }) => Some(Opnd::Mem(Mem { base, disp, num_bits })),
            Opnd::InsnOut { idx, .. } => Some(Opnd::InsnOut { idx, num_bits }),
            Opnd::Stack { idx, stack_size, sp_offset, reg_temps, .. } => Some(Opnd::Stack { idx, num_bits, stack_size, sp_offset, reg_temps }),
            _ => None,
        }
    }

    /// Get the size in bits for register/memory operands.
    pub fn rm_num_bits(&self) -> u8 {
        self.num_bits().unwrap()
    }

    /// Maps the indices from a previous list of instructions to a new list of
    /// instructions.
    pub fn map_index(self, indices: &Vec<usize>) -> Opnd {
        match self {
            Opnd::InsnOut { idx, num_bits } => {
                Opnd::InsnOut { idx: indices[idx], num_bits }
            }
            Opnd::Mem(Mem { base: MemBase::InsnOut(idx), disp, num_bits }) => {
                Opnd::Mem(Mem { base: MemBase::InsnOut(indices[idx]), disp, num_bits })
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

    /// Calculate Opnd::Stack's index from the stack bottom.
    pub fn stack_idx(&self) -> u8 {
        self.get_stack_idx().unwrap()
    }

    /// Calculate Opnd::Stack's index from the stack bottom if it's Opnd::Stack.
    pub fn get_stack_idx(&self) -> Option<u8> {
        match self {
            Opnd::Stack { idx, stack_size, .. } => {
                Some((*stack_size as isize - *idx as isize - 1) as u8)
            },
            _ => None
        }
    }

    /// Get the index for stack temp registers.
    pub fn reg_idx(&self) -> usize {
        match self {
            Opnd::Stack { .. } => {
                self.stack_idx() as usize % get_option!(num_temp_regs)
            },
            _ => unreachable!(),
        }
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
        Opnd::Imm(value.try_into().unwrap())
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
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Target
{
    /// Pointer to a piece of YJIT-generated code
    CodePtr(CodePtr),
    /// Side exit with a counter
    SideExit { counter: Counter, context: Option<SideExitContext> },
    /// Pointer to a side exit code
    SideExitPtr(CodePtr),
    /// A label within the generated code
    Label(usize),
}

impl Target
{
    pub fn side_exit(counter: Counter) -> Target {
        Target::SideExit { counter, context: None }
    }

    pub fn unwrap_label_idx(&self) -> usize {
        match self {
            Target::Label(idx) => *idx,
            _ => unreachable!("trying to unwrap {:?} into label", self)
        }
    }

    pub fn unwrap_code_ptr(&self) -> CodePtr {
        match self {
            Target::CodePtr(ptr) => *ptr,
            Target::SideExitPtr(ptr) => *ptr,
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

/// YJIT IR instruction
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
    CCall { opnds: Vec<Opnd>, fptr: *const u8, out: Opnd },

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
            Insn::Jz(target) |
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
            Insn::Label(_) => "Label",
            Insn::LeaJumpTarget { .. } => "LeaJumpTarget",
            Insn::Lea { .. } => "Lea",
            Insn::LiveReg { .. } => "LiveReg",
            Insn::Load { .. } => "Load",
            Insn::LoadInto { .. } => "LoadInto",
            Insn::LoadSExt { .. } => "LoadSExt",
            Insn::LShift { .. } => "LShift",
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
            Insn::Jz(target) |
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
            Insn::BakeString(_) |
            Insn::Breakpoint |
            Insn::Comment(_) |
            Insn::CPop { .. } |
            Insn::CPopAll |
            Insn::CPushAll |
            Insn::FrameSetup |
            Insn::FrameTeardown |
            Insn::Jbe(_) |
            Insn::Jb(_) |
            Insn::Je(_) |
            Insn::Jl(_) |
            Insn::Jg(_) |
            Insn::Jge(_) |
            Insn::Jmp(_) |
            Insn::Jne(_) |
            Insn::Jnz(_) |
            Insn::Jo(_) |
            Insn::JoMul(_) |
            Insn::Jz(_) |
            Insn::Label(_) |
            Insn::LeaJumpTarget { .. } |
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
                        Some(&opnd)
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
                        Some(&opnd0)
                    }
                    1 => {
                        self.idx += 1;
                        Some(&opnd1)
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
            Insn::BakeString(_) |
            Insn::Breakpoint |
            Insn::Comment(_) |
            Insn::CPop { .. } |
            Insn::CPopAll |
            Insn::CPushAll |
            Insn::FrameSetup |
            Insn::FrameTeardown |
            Insn::Jbe(_) |
            Insn::Jb(_) |
            Insn::Je(_) |
            Insn::Jl(_) |
            Insn::Jg(_) |
            Insn::Jge(_) |
            Insn::Jmp(_) |
            Insn::Jne(_) |
            Insn::Jnz(_) |
            Insn::Jo(_) |
            Insn::JoMul(_) |
            Insn::Jz(_) |
            Insn::Label(_) |
            Insn::LeaJumpTarget { .. } |
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
            }
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

/// Set of variables used for generating side exits
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct SideExitContext {
    /// PC of the instruction being compiled
    pub pc: *mut VALUE,

    /// Context fields used by get_generic_ctx()
    pub stack_size: u8,
    pub sp_offset: i8,
    pub reg_temps: RegTemps,
    pub is_return_landing: bool,
    pub is_deferred: bool,
}

impl SideExitContext {
    /// Convert PC and Context into SideExitContext
    pub fn new(pc: *mut VALUE, ctx: Context) -> Self {
        let exit_ctx = SideExitContext {
            pc,
            stack_size: ctx.get_stack_size(),
            sp_offset: ctx.get_sp_offset(),
            reg_temps: ctx.get_reg_temps(),
            is_return_landing: ctx.is_return_landing(),
            is_deferred: ctx.is_deferred(),
        };
        if cfg!(debug_assertions) {
            // Assert that we're not losing any mandatory metadata
            assert_eq!(exit_ctx.get_ctx(), ctx.get_generic_ctx());
        }
        exit_ctx
    }

    /// Convert SideExitContext to Context
    fn get_ctx(&self) -> Context {
        let mut ctx = Context::default();
        ctx.set_stack_size(self.stack_size);
        ctx.set_sp_offset(self.sp_offset);
        ctx.set_reg_temps(self.reg_temps);
        if self.is_return_landing {
            ctx.set_as_return_landing();
        }
        if self.is_deferred {
            ctx.mark_as_deferred();
        }
        ctx
    }
}

/// Initial capacity for asm.insns vector
const ASSEMBLER_INSNS_CAPACITY: usize = 256;

/// Object into which we assemble instructions to be
/// optimized and lowered
pub struct Assembler {
    pub(super) insns: Vec<Insn>,

    /// Parallel vec with insns
    /// Index of the last insn using the output of this insn
    pub(super) live_ranges: Vec<usize>,

    /// Names of labels
    pub(super) label_names: Vec<String>,

    /// Context for generating the current insn
    pub ctx: Context,

    /// Side exit caches for each SideExitContext
    pub(super) side_exits: HashMap<SideExitContext, CodePtr>,

    /// PC for Target::SideExit
    side_exit_pc: Option<*mut VALUE>,

    /// Stack size for Target::SideExit
    side_exit_stack_size: Option<u8>,

    /// If true, the next ccall() should verify its leafness
    leaf_ccall: bool,
}

impl Assembler
{
    pub fn new() -> Self {
        Self::new_with_label_names(Vec::default(), HashMap::default())
    }

    pub fn new_with_label_names(label_names: Vec<String>, side_exits: HashMap<SideExitContext, CodePtr>) -> Self {
        Self {
            insns: Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY),
            live_ranges: Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY),
            label_names,
            ctx: Context::default(),
            side_exits,
            side_exit_pc: None,
            side_exit_stack_size: None,
            leaf_ccall: false,
        }
    }

    /// Get the list of registers that can be used for stack temps.
    pub fn get_temp_regs() -> &'static [Reg] {
        let num_regs = get_option!(num_temp_regs);
        &TEMP_REGS[0..num_regs]
    }

    /// Set a context for generating side exits
    pub fn set_side_exit_context(&mut self, pc: *mut VALUE, stack_size: u8) {
        self.side_exit_pc = Some(pc);
        self.side_exit_stack_size = Some(stack_size);
    }

    /// Build an Opnd::InsnOut from the current index of the assembler and the
    /// given number of bits.
    pub(super) fn next_opnd_out(&self, num_bits: u8) -> Opnd {
        Opnd::InsnOut { idx: self.insns.len(), num_bits }
    }

    /// Append an instruction onto the current list of instructions and update
    /// the live ranges of any instructions whose outputs are being used as
    /// operands to this instruction.
    pub fn push_insn(&mut self, mut insn: Insn) {
        // Index of this instruction
        let insn_idx = self.insns.len();

        let mut opnd_iter = insn.opnd_iter_mut();
        while let Some(opnd) = opnd_iter.next() {
            match opnd {
                // If we find any InsnOut from previous instructions, we're going to update
                // the live range of the previous instruction to point to this one.
                Opnd::InsnOut { idx, .. } => {
                    assert!(*idx < self.insns.len());
                    self.live_ranges[*idx] = insn_idx;
                }
                Opnd::Mem(Mem { base: MemBase::InsnOut(idx), .. }) => {
                    assert!(*idx < self.insns.len());
                    self.live_ranges[*idx] = insn_idx;
                }
                // Set current ctx.reg_temps to Opnd::Stack.
                Opnd::Stack { idx, num_bits, stack_size, sp_offset, reg_temps: None } => {
                    assert_eq!(
                        self.ctx.get_stack_size() as i16 - self.ctx.get_sp_offset() as i16,
                        *stack_size as i16 - *sp_offset as i16,
                        "Opnd::Stack (stack_size: {}, sp_offset: {}) expects a different SP position from asm.ctx (stack_size: {}, sp_offset: {})",
                        *stack_size, *sp_offset, self.ctx.get_stack_size(), self.ctx.get_sp_offset(),
                    );
                    *opnd = Opnd::Stack {
                        idx: *idx,
                        num_bits: *num_bits,
                        stack_size: *stack_size,
                        sp_offset: *sp_offset,
                        reg_temps: Some(self.ctx.get_reg_temps()),
                    };
                }
                _ => {}
            }
        }

        // Set a side exit context to Target::SideExit
        if let Some(Target::SideExit { context, .. }) = insn.target_mut() {
            // We should skip this when this instruction is being copied from another Assembler.
            if context.is_none() {
                *context = Some(SideExitContext::new(
                    self.side_exit_pc.unwrap(),
                    self.ctx.with_stack_size(self.side_exit_stack_size.unwrap()),
                ));
            }
        }

        self.insns.push(insn);
        self.live_ranges.push(insn_idx);
    }

    /// Get a cached side exit, wrapping a counter if specified
    pub fn get_side_exit(&mut self, side_exit_context: &SideExitContext, counter: Option<Counter>, ocb: &mut OutlinedCb) -> Option<CodePtr> {
        // Get a cached side exit
        let side_exit = match self.side_exits.get(&side_exit_context) {
            None => {
                let exit_code = gen_outlined_exit(side_exit_context.pc, &side_exit_context.get_ctx(), ocb)?;
                self.side_exits.insert(*side_exit_context, exit_code);
                exit_code
            }
            Some(code_ptr) => *code_ptr,
        };

        // Wrap a counter if needed
        gen_counted_exit(side_exit_context.pc, side_exit, ocb, counter)
    }

    /// Create a new label instance that we can jump to
    pub fn new_label(&mut self, name: &str) -> Target
    {
        assert!(!name.contains(' '), "use underscores in label names, not spaces");

        let label_idx = self.label_names.len();
        self.label_names.push(name.to_string());
        Target::Label(label_idx)
    }

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
        fn reg_opnd(opnd: &Opnd) -> Opnd {
            let regs = Assembler::get_temp_regs();
            if let Opnd::Stack { num_bits, .. } = *opnd {
                incr_counter!(temp_reg_opnd);
                Opnd::Reg(regs[opnd.reg_idx()]).with_num_bits(num_bits).unwrap()
            } else {
                unreachable!()
            }
        }

        match opnd {
            Opnd::Stack { reg_temps, .. } => {
                if opnd.stack_idx() < MAX_REG_TEMPS && reg_temps.unwrap().get(opnd.stack_idx()) {
                    reg_opnd(opnd)
                } else {
                    mem_opnd(opnd)
                }
            }
            _ => unreachable!(),
        }
    }

    /// Allocate a register to a stack temp if available.
    pub fn alloc_temp_reg(&mut self, stack_idx: u8) {
        if get_option!(num_temp_regs) == 0 {
            return;
        }

        // Allocate a register if there's no conflict.
        let mut reg_temps = self.ctx.get_reg_temps();
        if reg_temps.conflicts_with(stack_idx) {
            assert!(!reg_temps.get(stack_idx));
        } else {
            reg_temps.set(stack_idx, true);
            self.set_reg_temps(reg_temps);
        }
    }

    /// Erase local variable type information
    /// eg: because of a call we can't track
    pub fn clear_local_types(&mut self) {
        asm_comment!(self, "clear local variable types");
        self.ctx.clear_local_types();
    }

    /// Spill all live stack temps from registers to the stack
    pub fn spill_temps(&mut self) {
        // Forget registers above the stack top
        let mut reg_temps = self.ctx.get_reg_temps();
        for stack_idx in self.ctx.get_stack_size()..MAX_REG_TEMPS {
            reg_temps.set(stack_idx, false);
        }
        self.set_reg_temps(reg_temps);

        // Spill live stack temps
        if self.ctx.get_reg_temps() != RegTemps::default() {
            asm_comment!(self, "spill_temps: {:08b} -> {:08b}", self.ctx.get_reg_temps().as_u8(), RegTemps::default().as_u8());
            for stack_idx in 0..u8::min(MAX_REG_TEMPS, self.ctx.get_stack_size()) {
                if self.ctx.get_reg_temps().get(stack_idx) {
                    let idx = self.ctx.get_stack_size() - 1 - stack_idx;
                    self.spill_temp(self.stack_opnd(idx.into()));
                    reg_temps.set(stack_idx, false);
                }
            }
            self.ctx.set_reg_temps(reg_temps);
        }

        // Every stack temp should have been spilled
        assert_eq!(self.ctx.get_reg_temps(), RegTemps::default());
    }

    /// Spill a stack temp from a register to the stack
    fn spill_temp(&mut self, opnd: Opnd) {
        assert!(self.ctx.get_reg_temps().get(opnd.stack_idx()));

        // Use different RegTemps for dest and src operands
        let reg_temps = self.ctx.get_reg_temps();
        let mut mem_temps = reg_temps;
        mem_temps.set(opnd.stack_idx(), false);

        // Move the stack operand from a register to memory
        match opnd {
            Opnd::Stack { idx, num_bits, stack_size, sp_offset, .. } => {
                self.mov(
                    Opnd::Stack { idx, num_bits, stack_size, sp_offset, reg_temps: Some(mem_temps) },
                    Opnd::Stack { idx, num_bits, stack_size, sp_offset, reg_temps: Some(reg_temps) },
                );
            }
            _ => unreachable!(),
        }
        incr_counter!(temp_spill);
    }

    /// Update which stack temps are in a register
    pub fn set_reg_temps(&mut self, reg_temps: RegTemps) {
        if self.ctx.get_reg_temps() != reg_temps {
            asm_comment!(self, "reg_temps: {:08b} -> {:08b}", self.ctx.get_reg_temps().as_u8(), reg_temps.as_u8());
            self.ctx.set_reg_temps(reg_temps);
            self.verify_reg_temps();
        }
    }

    /// Assert there's no conflict in stack temp register allocation
    fn verify_reg_temps(&self) {
        for stack_idx in 0..MAX_REG_TEMPS {
            if self.ctx.get_reg_temps().get(stack_idx) {
                assert!(!self.ctx.get_reg_temps().conflicts_with(stack_idx));
            }
        }
    }

    /// Sets the out field on the various instructions that require allocated
    /// registers because their output is used as the operand on a subsequent
    /// instruction. This is our implementation of the linear scan algorithm.
    pub(super) fn alloc_regs(mut self, regs: Vec<Reg>) -> Assembler
    {
        //dbg!(&self);

        // First, create the pool of registers.
        let mut pool: u32 = 0;

        // Mutate the pool bitmap to indicate that the register at that index
        // has been allocated and is live.
        fn alloc_reg(pool: &mut u32, regs: &Vec<Reg>) -> Option<Reg> {
            for (index, reg) in regs.iter().enumerate() {
                if (*pool & (1 << index)) == 0 {
                    *pool |= 1 << index;
                    return Some(*reg);
                }
            }
            None
        }

        // Allocate a specific register
        fn take_reg(pool: &mut u32, regs: &Vec<Reg>, reg: &Reg) -> Reg {
            let reg_index = regs.iter().position(|elem| elem.reg_no == reg.reg_no);

            if let Some(reg_index) = reg_index {
                assert_eq!(*pool & (1 << reg_index), 0, "register already allocated");
                *pool |= 1 << reg_index;
            }

            return *reg;
        }

        // Mutate the pool bitmap to indicate that the given register is being
        // returned as it is no longer used by the instruction that previously
        // held it.
        fn dealloc_reg(pool: &mut u32, regs: &Vec<Reg>, reg: &Reg) {
            let reg_index = regs.iter().position(|elem| elem.reg_no == reg.reg_no);

            if let Some(reg_index) = reg_index {
                *pool &= !(1 << reg_index);
            }
        }

        // Reorder C argument moves, sometimes adding extra moves using SCRATCH_REG,
        // so that they will not rewrite each other before they are used.
        fn reorder_c_args(c_args: &Vec<(Reg, Opnd)>) -> Vec<(Reg, Opnd)> {
            // Return the index of a move whose destination is not used as a source if any.
            fn find_safe_arg(c_args: &Vec<(Reg, Opnd)>) -> Option<usize> {
                c_args.iter().enumerate().find(|(_, &(dest_reg, _))| {
                    c_args.iter().all(|&(_, src_opnd)| src_opnd != Opnd::Reg(dest_reg))
                }).map(|(index, _)| index)
            }

            // Remove moves whose source and destination are the same
            let mut c_args: Vec<(Reg, Opnd)> = c_args.clone().into_iter()
                .filter(|&(reg, opnd)| Opnd::Reg(reg) != opnd).collect();

            let mut moves = vec![];
            while c_args.len() > 0 {
                // Keep taking safe moves
                while let Some(index) = find_safe_arg(&c_args) {
                    moves.push(c_args.remove(index));
                }

                // No safe move. Load the source of one move into SCRATCH_REG, and
                // then load SCRATCH_REG into the destination when it's safe.
                if c_args.len() > 0 {
                    // Make sure it's safe to use SCRATCH_REG
                    assert!(c_args.iter().all(|&(_, opnd)| opnd != Opnd::Reg(Assembler::SCRATCH_REG)));

                    // Move SCRATCH <- opnd, and delay reg <- SCRATCH
                    let (reg, opnd) = c_args.remove(0);
                    moves.push((Assembler::SCRATCH_REG, opnd));
                    c_args.push((reg, Opnd::Reg(Assembler::SCRATCH_REG)));
                }
            }
            moves
        }

        // Adjust the number of entries in live_ranges so that it can be indexed by mapped indexes.
        fn shift_live_ranges(live_ranges: &mut Vec<usize>, start_index: usize, shift_offset: isize) {
            if shift_offset >= 0 {
                for index in 0..(shift_offset as usize) {
                    live_ranges.insert(start_index + index, start_index + index);
                }
            } else {
                for _ in 0..-shift_offset {
                    live_ranges.remove(start_index);
                }
            }
        }

        // Dump live registers for register spill debugging.
        fn dump_live_regs(insns: Vec<Insn>, live_ranges: Vec<usize>, num_regs: usize, spill_index: usize) {
            // Convert live_ranges to live_regs: the number of live registers at each index
            let mut live_regs: Vec<usize> = vec![];
            let mut end_idxs: Vec<usize> = vec![];
            for (cur_idx, &end_idx) in live_ranges.iter().enumerate() {
                end_idxs.push(end_idx);
                while let Some(end_idx) = end_idxs.iter().position(|&end_idx| cur_idx == end_idx) {
                    end_idxs.remove(end_idx);
                }
                live_regs.push(end_idxs.len());
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

        // We may need to reorder LoadInto instructions with a C argument operand.
        // This buffers the operands of such instructions to process them in batches.
        let mut c_args: Vec<(Reg, Opnd)> = vec![];

        // live_ranges is indexed by original `index` given by the iterator.
        let live_ranges: Vec<usize> = take(&mut self.live_ranges);
        // shifted_live_ranges is indexed by mapped indexes in insn operands.
        let mut shifted_live_ranges: Vec<usize> = live_ranges.clone();
        let mut asm = Assembler::new_with_label_names(take(&mut self.label_names), take(&mut self.side_exits));
        let mut iterator = self.into_draining_iter();

        while let Some((index, mut insn)) = iterator.next_mapped() {
            // Check if this is the last instruction that uses an operand that
            // spans more than one instruction. In that case, return the
            // allocated register to the pool.
            for opnd in insn.opnd_iter() {
                match opnd {
                    Opnd::InsnOut { idx, .. } |
                    Opnd::Mem(Mem { base: MemBase::InsnOut(idx), .. }) => {
                        // Since we have an InsnOut, we know it spans more that one
                        // instruction.
                        let start_index = *idx;

                        // We're going to check if this is the last instruction that
                        // uses this operand. If it is, we can return the allocated
                        // register to the pool.
                        if shifted_live_ranges[start_index] == index {
                            if let Some(Opnd::Reg(reg)) = asm.insns[start_index].out_opnd() {
                                dealloc_reg(&mut pool, &regs, reg);
                            } else {
                                unreachable!("no register allocated for insn {:?}", insn);
                            }
                        }
                    }
                    _ => {}
                }
            }

            // C return values need to be mapped to the C return register
            if matches!(insn, Insn::CCall { .. }) {
                assert_eq!(pool, 0, "register lives past C function call");
            }

            // If this instruction is used by another instruction,
            // we need to allocate a register to it
            if live_ranges[index] != index {
                // If we get to this point where the end of the live range is
                // not equal to the index of the instruction, then it must be
                // true that we set an output operand for this instruction. If
                // it's not true, something has gone wrong.
                assert!(
                    !matches!(insn.out_opnd(), None),
                    "Instruction output reused but no output operand set"
                );

                // This is going to be the output operand that we will set on
                // the instruction.
                let mut out_reg: Option<Reg> = None;

                // C return values need to be mapped to the C return register
                if matches!(insn, Insn::CCall { .. }) {
                    out_reg = Some(take_reg(&mut pool, &regs, &C_RET_REG));
                }

                // If this instruction's first operand maps to a register and
                // this is the last use of the register, reuse the register
                // We do this to improve register allocation on x86
                // e.g. out  = add(reg0, reg1)
                //      reg0 = add(reg0, reg1)
                if out_reg.is_none() {
                    let mut opnd_iter = insn.opnd_iter();

                    if let Some(Opnd::InsnOut{ idx, .. }) = opnd_iter.next() {
                        if shifted_live_ranges[*idx] == index {
                            if let Some(Opnd::Reg(reg)) = asm.insns[*idx].out_opnd() {
                                out_reg = Some(take_reg(&mut pool, &regs, reg));
                            }
                        }
                    }
                }

                // Allocate a new register for this instruction if one is not
                // already allocated.
                if out_reg.is_none() {
                    out_reg = match &insn {
                        Insn::LiveReg { opnd, .. } => {
                            // Allocate a specific register
                            let reg = opnd.unwrap_reg();
                            Some(take_reg(&mut pool, &regs, &reg))
                        },
                        _ => match alloc_reg(&mut pool, &regs) {
                            Some(reg) => Some(reg),
                            None => {
                                let mut insns = asm.insns;
                                insns.push(insn);
                                for insn in iterator.insns {
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
                *out = Opnd::Reg(out_reg.unwrap().with_num_bits(out_num_bits));
            }

            // Replace InsnOut operands by their corresponding register
            let mut opnd_iter = insn.opnd_iter_mut();
            while let Some(opnd) = opnd_iter.next() {
                match *opnd {
                    Opnd::InsnOut { idx, num_bits } => {
                        *opnd = (*asm.insns[idx].out_opnd().unwrap()).with_num_bits(num_bits).unwrap();
                    },
                    Opnd::Mem(Mem { base: MemBase::InsnOut(idx), disp, num_bits }) => {
                        let base = MemBase::Reg(asm.insns[idx].out_opnd().unwrap().unwrap_reg().reg_no);
                        *opnd = Opnd::Mem(Mem { base, disp, num_bits });
                    }
                    _ => {},
                }
            }

            // Push instruction(s). Batch and reorder C argument operations if needed.
            if let Insn::LoadInto { dest: Opnd::CArg(reg), opnd } = insn {
                // Buffer C arguments
                c_args.push((reg, opnd));
            } else {
                // C arguments are buffered until CCall
                if c_args.len() > 0 {
                    // Resolve C argument dependencies
                    let c_args_len = c_args.len() as isize;
                    let moves = reorder_c_args(&c_args.drain(..).into_iter().collect());
                    shift_live_ranges(&mut shifted_live_ranges, asm.insns.len(), moves.len() as isize - c_args_len);

                    // Push batched C arguments
                    for (reg, opnd) in moves {
                        asm.load_into(Opnd::Reg(reg), opnd);
                    }
                }
                // Other instructions are pushed as is
                asm.push_insn(insn);
            }
            iterator.map_insn_index(&mut asm);
        }

        assert_eq!(pool, 0, "Expected all registers to be returned to the pool");
        asm
    }

    /// Compile the instructions down to machine code.
    /// Can fail due to lack of code memory and inopportune code placement, among other reasons.
    #[must_use]
    pub fn compile(self, cb: &mut CodeBlock, ocb: Option<&mut OutlinedCb>) -> Option<(CodePtr, Vec<u32>)>
    {
        #[cfg(feature = "disasm")]
        let start_addr = cb.get_write_ptr();

        let alloc_regs = Self::get_alloc_regs();
        let ret = self.compile_with_regs(cb, ocb, alloc_regs);

        #[cfg(feature = "disasm")]
        if let Some(dump_disasm) = get_option_ref!(dump_disasm) {
            use crate::disasm::dump_disasm_addr_range;
            let end_addr = cb.get_write_ptr();
            dump_disasm_addr_range(cb, start_addr, end_addr, dump_disasm)
        }
        ret
    }

    /// Compile with a limited number of registers. Used only for unit tests.
    #[cfg(test)]
    pub fn compile_with_num_regs(self, cb: &mut CodeBlock, num_regs: usize) -> (CodePtr, Vec<u32>)
    {
        let mut alloc_regs = Self::get_alloc_regs();
        let alloc_regs = alloc_regs.drain(0..num_regs).collect();
        self.compile_with_regs(cb, None, alloc_regs).unwrap()
    }

    /// Consume the assembler by creating a new draining iterator.
    pub fn into_draining_iter(self) -> AssemblerDrainingIterator {
        AssemblerDrainingIterator::new(self)
    }

    /// Return true if the next ccall() is expected to be leaf.
    pub fn get_leaf_ccall(&mut self) -> bool {
        self.leaf_ccall
    }

    /// Assert that the next ccall() is going to be leaf.
    pub fn expect_leaf_ccall(&mut self) {
        self.leaf_ccall = true;
    }
}

/// A struct that allows iterating through an assembler's instructions and
/// consuming them as it iterates.
pub struct AssemblerDrainingIterator {
    insns: std::iter::Peekable<std::vec::IntoIter<Insn>>,
    index: usize,
    indices: Vec<usize>
}

impl AssemblerDrainingIterator {
    fn new(asm: Assembler) -> Self {
        Self {
            insns: asm.insns.into_iter().peekable(),
            index: 0,
            indices: Vec::with_capacity(ASSEMBLER_INSNS_CAPACITY),
        }
    }

    /// When you're working with two lists of instructions, you need to make
    /// sure you do some bookkeeping to align the indices contained within the
    /// operands of the two lists.
    ///
    /// This function accepts the assembler that is being built and tracks the
    /// end of the current list of instructions in order to maintain that
    /// alignment.
    pub fn map_insn_index(&mut self, asm: &mut Assembler) {
        self.indices.push(asm.insns.len().saturating_sub(1));
    }

    /// Map an operand by using this iterator's list of mapped indices.
    #[cfg(target_arch = "x86_64")]
    pub fn map_opnd(&self, opnd: Opnd) -> Opnd {
        opnd.map_index(&self.indices)
    }

    /// Returns the next instruction in the list with the indices corresponding
    /// to the next list of instructions.
    pub fn next_mapped(&mut self) -> Option<(usize, Insn)> {
        self.next_unmapped().map(|(index, mut insn)| {
            let mut opnd_iter = insn.opnd_iter_mut();
            while let Some(opnd) = opnd_iter.next() {
                *opnd = opnd.map_index(&self.indices);
            }

            (index, insn)
        })
    }

    /// Returns the next instruction in the list with the indices corresponding
    /// to the previous list of instructions.
    pub fn next_unmapped(&mut self) -> Option<(usize, Insn)> {
        let index = self.index;
        self.index += 1;
        self.insns.next().map(|insn| (index, insn))
    }

    /// Returns the next instruction without incrementing the iterator's index.
    pub fn peek(&mut self) -> Option<&Insn> {
        self.insns.peek()
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
        let out = self.next_opnd_out(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Add { left, right, out });
        out
    }

    #[must_use]
    pub fn and(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[left, right]));
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

    pub fn ccall(&mut self, fptr: *const u8, opnds: Vec<Opnd>) -> Opnd {
        // Let vm_check_canary() assert this ccall's leafness if leaf_ccall is set
        let canary_opnd = self.set_stack_canary(&opnds);

        let old_temps = self.ctx.get_reg_temps(); // with registers
        // Spill stack temp registers since they are caller-saved registers.
        // Note that this doesn't spill stack temps that are already popped
        // but may still be used in the C arguments.
        self.spill_temps();
        let new_temps = self.ctx.get_reg_temps(); // all spilled

        // Temporarily manipulate RegTemps so that we can use registers
        // to pass stack operands that are already spilled above.
        self.ctx.set_reg_temps(old_temps);

        // Call a C function
        let out = self.next_opnd_out(Opnd::match_num_bits(&opnds));
        self.push_insn(Insn::CCall { fptr, opnds, out });

        // Registers in old_temps may be clobbered by the above C call,
        // so rollback the manipulated RegTemps to a spilled version.
        self.ctx.set_reg_temps(new_temps);

        // Clear the canary after use
        if let Some(canary_opnd) = canary_opnd {
            self.mov(canary_opnd, 0.into());
        }

        out
    }

    /// Let vm_check_canary() assert the leafness of this ccall if leaf_ccall is set
    fn set_stack_canary(&mut self, opnds: &Vec<Opnd>) -> Option<Opnd> {
        // Use the slot right above the stack top for verifying leafness.
        let canary_opnd = self.stack_opnd(-1);

        // If the slot is already used, which is a valid optimization to avoid spills,
        // give up the verification.
        let canary_opnd = if cfg!(debug_assertions) && self.leaf_ccall && opnds.iter().all(|opnd|
            opnd.get_stack_idx() != canary_opnd.get_stack_idx()
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

    pub fn cmp(&mut self, left: Opnd, right: Opnd) {
        self.push_insn(Insn::Cmp { left, right });
    }

    #[must_use]
    pub fn cpop(&mut self) -> Opnd {
        let out = self.next_opnd_out(Opnd::DEFAULT_NUM_BITS);
        self.push_insn(Insn::CPop { out });
        out
    }

    pub fn cpop_all(&mut self) {
        self.push_insn(Insn::CPopAll);

        // Re-enable ccall's RegTemps assertion disabled by cpush_all.
        // cpush_all + cpop_all preserve all stack temp registers, so it's safe.
        self.set_reg_temps(self.ctx.get_reg_temps());
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
        // that don't require spill_temps for GC.
        self.set_reg_temps(RegTemps::default());
    }

    pub fn cret(&mut self, opnd: Opnd) {
        self.push_insn(Insn::CRet(opnd));
    }

    #[must_use]
    pub fn csel_e(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_g(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelG { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_ge(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelGE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_l(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelL { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_le(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelLE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_ne(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelNE { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_nz(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
        self.push_insn(Insn::CSelNZ { truthy, falsy, out });
        out
    }

    #[must_use]
    pub fn csel_z(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[truthy, falsy]));
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
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::Lea { opnd, out });
        out
    }

    #[must_use]
    pub fn lea_jump_target(&mut self, target: Target) -> Opnd {
        let out = self.next_opnd_out(Opnd::DEFAULT_NUM_BITS);
        self.push_insn(Insn::LeaJumpTarget { target, out });
        out
    }

    #[must_use]
    pub fn live_reg_opnd(&mut self, opnd: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::LiveReg { opnd, out });
        out
    }

    #[must_use]
    pub fn load(&mut self, opnd: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd]));
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
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::LoadSExt { opnd, out });
        out
    }

    #[must_use]
    pub fn lshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::LShift { opnd, shift, out });
        out
    }

    pub fn mov(&mut self, dest: Opnd, src: Opnd) {
        self.push_insn(Insn::Mov { dest, src });
    }

    #[must_use]
    pub fn not(&mut self, opnd: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd]));
        self.push_insn(Insn::Not { opnd, out });
        out
    }

    #[must_use]
    pub fn or(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[left, right]));
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
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::RShift { opnd, shift, out });
        out
    }

    pub fn store(&mut self, dest: Opnd, src: Opnd) {
        self.push_insn(Insn::Store { dest, src });
    }

    #[must_use]
    pub fn sub(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Sub { left, right, out });
        out
    }

    #[must_use]
    pub fn mul(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Mul { left, right, out });
        out
    }

    pub fn test(&mut self, left: Opnd, right: Opnd) {
        self.push_insn(Insn::Test { left, right });
    }

    #[must_use]
    #[allow(dead_code)]
    pub fn urshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[opnd, shift]));
        self.push_insn(Insn::URShift { opnd, shift, out });
        out
    }

    /// Verify the leafness of the given block
    pub fn with_leaf_ccall<F, R>(&mut self, mut block: F) -> R
    where F: FnMut(&mut Self) -> R {
        let old_leaf_ccall = self.leaf_ccall;
        self.leaf_ccall = true;
        let ret = block(self);
        self.leaf_ccall = old_leaf_ccall;
        ret
    }

    /// Add a label at the current position
    pub fn write_label(&mut self, target: Target) {
        assert!(target.unwrap_label_idx() < self.label_names.len());
        self.push_insn(Insn::Label(target));
    }

    #[must_use]
    pub fn xor(&mut self, left: Opnd, right: Opnd) -> Opnd {
        let out = self.next_opnd_out(Opnd::match_num_bits(&[left, right]));
        self.push_insn(Insn::Xor { left, right, out });
        out
    }
}

/// Macro to use format! for Insn::Comment, which skips a format! call
/// when disasm is not supported.
macro_rules! asm_comment {
    ($asm:expr, $($fmt:tt)*) => {
        if cfg!(feature = "disasm") {
            $asm.push_insn(Insn::Comment(format!($($fmt)*)));
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
