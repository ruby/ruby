#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use std::fmt;
use std::convert::From;
use crate::cruby::{VALUE};
use crate::asm::{CodeBlock, CodePtr};
use crate::asm::x86_64::{X86Opnd, X86Imm, X86UImm, X86Reg, X86Mem, RegType};
use crate::core::{Context, Type, TempMapping};

#[cfg(target_arch = "x86_64")]
use crate::backend::x86_64::*;

//#[cfg(target_arch = "aarch64")]
//use crate::backend:aarch64::*

/// Instruction opcodes
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Op
{
    // Add a comment into the IR at the point that this instruction is added.
    // It won't have any impact on that actual compiled code.
    Comment,

    // Add a label into the IR at the point that this instruction is added.
    Label,

    // Add two operands together, and return the result as a new operand. This
    // operand can then be used as the operand on another instruction. It
    // accepts two operands, which can be of any type
    //
    // Under the hood when allocating registers, the IR will determine the most
    // efficient way to get these values into memory. For example, if both
    // operands are immediates, then it will load the first one into a register
    // first with a mov instruction and then add them together. If one of them
    // is a register, however, it will just perform a single add instruction.
    Add,

    // This is the same as the OP_ADD instruction, except for subtraction.
    Sub,

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary AND operation.
    And,

    // Perform the NOT operation on an individual operand, and return the result
    // as a new operand. This operand can then be used as the operand on another
    // instruction.
    Not,

    //
    // Low-level instructions
    //

    // A low-level instruction that loads a value into a register.
    Load,

    // Low-level instruction to store a value to memory.
    Store,

    // A low-level mov instruction. It accepts two operands.
    Mov,

    // Bitwise AND test instruction
    Test,

    // Compare two operands
    Cmp,

    // Low-level conditional jump instructions
    Jnz,
    Jbe,

    /*
    // The following are conditional jump instructions. They all accept as their
    // first operand an EIR_LABEL_NAME, which is used as the target of the jump.
    //
    // The OP_JUMP_EQ instruction accepts two additional operands, to be
    // compared for equality. If they're equal, then the generated code jumps to
    // the target label. If they're not, then it continues on to the next
    // instruction.
    JumpEq,

    // The OP_JUMP_NE instruction is very similar to the OP_JUMP_EQ instruction,
    // except it compares for inequality instead.
    JumpNe,

    // Checks the overflow flag and conditionally jumps to the target if it is
    // currently set.
    JumpOvf,

    // A low-level call instruction for calling a function by a pointer. It
    // accepts one operand of type EIR_IMM that should be a pointer to the
    // function. Usually this is done by first casting the function to a void*,
    // as in: ir_const_ptr((void *)&my_function)).
    Call,

    // Calls a function by a pointer and returns an operand that contains the
    // result of the function. Accepts as its operands a pointer to a function
    // of type EIR_IMM (usually generated from ir_const_ptr) and a variable
    // number of arguments to the function being called.
    //
    // This is the higher-level instruction that should be used when you want to
    // call a function with arguments, as opposed to OP_CALL which is
    // lower-level and just calls a function without moving arguments into
    // registers for you.
    CCall,

    // Returns from the function being generated immediately. This is different
    // from OP_RETVAL in that it does nothing with the return value register
    // (whatever is in there is what will get returned). Accepts no operands.
    Ret,

    // First, moves a value into the return value register. Then, returns from
    // the generated function. Accepts as its only operand the value that should
    // be returned from the generated function.
    RetVal,

    // A conditional move instruction that should be preceeded at some point by
    // an OP_CMP instruction that would have set the requisite comparison flags.
    // Accepts 2 operands, both of which are expected to be of the EIR_REG type.
    //
    // If the comparison indicates the left compared value is greater than or
    // equal to the right compared value, then the conditional move is executed,
    // otherwise we just continue on to the next instruction.
    //
    // This is considered a low-level instruction, and the OP_SELECT_* variants
    // should be preferred if possible.
    CMovGE,

    // The same as OP_CMOV_GE, except the comparison is greater than.
    CMovGT,

    // The same as OP_CMOV_GE, except the comparison is less than or equal.
    CMovLE,

    // The same as OP_CMOV_GE, except the comparison is less than.
    CMovLT,

    // Selects between two different values based on a comparison of two other
    // values. Accepts 4 operands. The first two are the basis of the
    // comparison. The second two are the "then" case and the "else" case. You
    // can effectively think of this instruction as a ternary operation, where
    // the first two values are being compared.
    //
    // OP_SELECT_GE performs the described ternary using a greater than or equal
    // comparison, that is if the first operand is greater than or equal to the
    // second operand.
    SelectGE,

    // The same as OP_SELECT_GE, except the comparison is greater than.
    SelectGT,

    // The same as OP_SELECT_GE, except the comparison is less than or equal.
    SelectLE,

    // The same as OP_SELECT_GE, except the comparison is less than.
    SelectLT,

    // For later:
    // These encode Ruby true/false semantics
    // Can be used to enable op fusion of Ruby compare + branch.
    // OP_JUMP_TRUE, // (opnd, target)
    // OP_JUMP_FALSE, // (opnd, target)

    // For later:
    // OP_GUARD_HEAP, // (opnd, target)
    // OP_GUARD_IMM, // (opnd, target)
    // OP_GUARD_FIXNUM, // (opnd, target)

    // For later:
    // OP_COUNTER_INC, (counter_name)

    // For later:
    // OP_LEA,
    // OP_TEST,
    */
}

// Memory location
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Mem
{
    // Base register
    pub(super) base_reg: Reg,

    // Offset relative to the base pointer
    pub(super) disp: i32,

    // Size in bits
    pub(super) num_bits: u8,
}

/// Operand to an IR instruction
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Opnd
{
    None,               // For insns with no output

    // NOTE: for now Context directly returns memory operands,
    // but eventually we'd like to have Stack and Local operand types
    //Stack(u16),         // Value on the temp stack (idx)
    //Local(u16),         // Local variable (idx, do we need depth too?)

    Value(VALUE),       // Immediate Ruby value, may be GC'd, movable
    InsnOut(usize),     // Output of a preceding instruction in this block

    // Low-level operands, for lowering
    Imm(i64),           // Raw signed immediate
    UImm(u64),          // Raw unsigned immediate
    Mem(Mem),           // Memory location (num_bits, base_ptr, const_offset)
    Reg(Reg),           // Machine register (num_bits, idx)
}

impl Opnd
{
    // Convenience constructor for memory operands
    pub fn mem(num_bits: u8, base: Opnd, disp: i32) -> Self {
        match base {
            Opnd::Reg(base_reg) => {
                assert!(base_reg.num_bits == 64);
                Opnd::Mem(Mem {
                    num_bits: num_bits,
                    base_reg: base_reg,
                    disp: disp,
                })
            },
            _ => unreachable!()
        }
    }
}

/// NOTE: this is useful during the port but can probably be removed once
/// Context returns ir::Opnd instead of X86Opnd
///
/// Method to convert from an X86Opnd to an IR Opnd
impl From<X86Opnd> for Opnd {
    fn from(opnd: X86Opnd) -> Self {
        match opnd {
            X86Opnd::None => Opnd::None,
            X86Opnd::UImm(X86UImm{ value, .. }) => Opnd::UImm(value),
            X86Opnd::Imm(X86Imm{ value, .. }) => Opnd::Imm(value),

            // General-purpose register
            X86Opnd::Reg(reg) => {
                Opnd::Reg(reg)
            }

            // Memory operand with displacement
            X86Opnd::Mem(X86Mem{ num_bits, base_reg_no, disp, idx_reg_no: None, scale_exp: 0 }) => {
                let base_reg = Reg { num_bits: 64, reg_no: base_reg_no, reg_type: RegType::GP };

                Opnd::Mem(Mem {
                    base_reg: base_reg,
                    disp,
                    num_bits
                })
            }

            _ => panic!("unsupported x86 operand type")
        }
    }
}

/// Branch target (something that we can jump to)
/// for branch instructions
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Target
{
    CodePtr(CodePtr),   // Pointer to a piece of code (e.g. side-exit)
    LabelName(String),  // A label without an index in the output
    LabelIdx(usize),      // A label that has been indexed
}

/// YJIT IR instruction
#[derive(Clone, Debug)]
pub struct Insn
{
    // Opcode for the instruction
    pub(super) op: Op,

    // Optional string for comments and labels
    pub(super) text: Option<String>,

    // List of input operands/values
    pub(super) opnds: Vec<Opnd>,

    // Output operand for this instruction
    pub(super) out: Opnd,

    // List of branch targets (branch instructions only)
    pub(super) target: Option<Target>,

    // Position in the generated machine code
    // Useful for comments and for patching jumps
    pub(super) pos: Option<CodePtr>,
}

/// Object into which we assemble instructions to be
/// optimized and lowered
pub struct Assembler
{
    pub(super) insns: Vec<Insn>,

    /// Parallel vec with insns
    /// Index of the last insn using the output of this insn
    pub(super) live_ranges: Vec<usize>
}

impl Assembler
{
    pub fn new() -> Assembler {
        Assembler {
            insns: Vec::default(),
            live_ranges: Vec::default()
        }
    }

    /// Append an instruction to the list
    pub(super) fn push_insn(&mut self, op: Op, opnds: Vec<Opnd>, target: Option<Target>) -> Opnd
    {
        // If we find any InsnOut from previous instructions, we're going to
        // update the live range of the previous instruction to point to this
        // one.
        let insn_idx = self.insns.len();
        for opnd in &opnds {
            if let Opnd::InsnOut(idx) = opnd {
                self.live_ranges[*idx] = insn_idx;
            }
        }

        let insn = Insn {
            op: op,
            text: None,
            opnds: opnds,
            out: Opnd::None,
            target: target,
            pos: None
        };

        self.insns.push(insn);
        self.live_ranges.push(insn_idx);

        // Return an operand for the output of this instruction
        Opnd::InsnOut(insn_idx)
    }

    /// Add a comment at the current position
    pub fn comment(&mut self, text: &str)
    {
        let insn = Insn {
            op: Op::Comment,
            text: Some(text.to_owned()),
            opnds: vec![],
            out: Opnd::None,
            target: None,
            pos: None
        };
        self.insns.push(insn);
        self.live_ranges.push(self.insns.len());
    }

    /// Add a label at the current position
    pub fn label(&mut self, name: &str) -> Target
    {
        let insn_idx = self.insns.len();

        let insn = Insn {
            op: Op::Label,
            text: Some(name.to_owned()),
            opnds: vec![],
            out: Opnd::None,
            target: None,
            pos: None
        };
        self.insns.push(insn);
        self.live_ranges.push(self.insns.len());

        Target::LabelIdx(insn_idx)
    }

    /// Transform input instructions, consumes the input assembler
    pub(super) fn transform_insns<F>(mut self, mut map_insn: F) -> Assembler
        where F: FnMut(&mut Assembler, usize, Op, Vec<Opnd>, Option<Target>)
    {
        let mut asm = Assembler::new();

        // indices maps from the old instruction index to the new instruction
        // index.
        let mut indices: Vec<usize> = Vec::default();

        // Map an operand to the next set of instructions by correcting previous
        // InsnOut indices.
        fn map_opnd(opnd: Opnd, indices: &mut Vec<usize>) -> Opnd {
            if let Opnd::InsnOut(index) = opnd {
                Opnd::InsnOut(indices[index])
            } else {
                opnd
            }
        }

        for (index, insn) in self.insns.drain(..).enumerate() {
            let opnds: Vec<Opnd> = insn.opnds.into_iter().map(|opnd| map_opnd(opnd, &mut indices)).collect();

            // For each instruction, either handle it here or allow the map_insn
            // callback to handle it.
            match insn.op {
                Op::Comment => {
                    asm.comment(insn.text.unwrap().as_str());
                },
                Op::Label => {
                    asm.label(insn.text.unwrap().as_str());
                },
                _ => {
                    map_insn(&mut asm, index, insn.op, opnds, insn.target);
                }
            };

            // Here we're assuming that if we've pushed multiple instructions,
            // the output that we're using is still the final instruction that
            // was pushed.
            indices.push(asm.insns.len() - 1);
        }

        asm
    }

    /// Transforms the instructions by splitting instructions that cannot be
    /// represented in the final architecture into multiple instructions that
    /// can.
    pub(super) fn split_loads(self) -> Assembler
    {
        self.transform_insns(|asm, _, op, opnds, target| {
            match op {
                // Check for Add, Sub, And, Mov, with two memory operands.
                // Load one operand into memory.
                Op::Add | Op::Sub | Op::And | Op::Mov => {
                    match opnds.as_slice() {
                        [Opnd::Mem(_), Opnd::Mem(_)] => {
                            // We load opnd1 because for mov, opnd0 is the output
                            let opnd1 = asm.load(opnds[1]);
                            asm.push_insn(op, vec![opnds[0], opnd1], None);
                        },
                        _ => {
                            asm.push_insn(op, opnds, target);
                        }
                    }
                },
                _ => {
                    asm.push_insn(op, opnds, target);
                }
            };
        })
    }

    /// Sets the out field on the various instructions that require allocated
    /// registers because their output is used as the operand on a subsequent
    /// instruction. This is our implementation of the linear scan algorithm.
    pub(super) fn alloc_regs(mut self, regs: Vec<Reg>) -> Assembler
    {
        // First, create the pool of registers.
        let mut pool: u32 = 0;

        // Mutate the pool bitmap to indicate that the register at that index
        // has been allocated and is live.
        fn alloc_reg(pool: &mut u32, regs: &Vec<Reg>) -> Reg {
            for index in 0..regs.len() {
                if (*pool & (1 << index)) == 0 {
                    *pool |= 1 << index;
                    return regs[index];
                }
            }

            unreachable!("Register spill not supported");
        }

        // Mutate the pool bitmap to indicate that the given register is being
        // returned as it is no longer used by the instruction that previously
        // held it.
        fn dealloc_reg(pool: &mut u32, regs: &Vec<Reg>, reg: &Reg) {
            let reg_index = regs.iter().position(|elem| elem == reg).unwrap();
            *pool &= !(1 << reg_index);
        }

        let live_ranges: Vec<usize> = std::mem::take(&mut self.live_ranges);

        let asm = self.transform_insns(|asm, index, op, opnds, target| {
            // Check if this is the last instruction that uses an operand that
            // spans more than one instruction. In that case, return the
            // allocated register to the pool.
            for opnd in &opnds {
                if let Opnd::InsnOut(idx) = opnd {
                    // Since we have an InsnOut, we know it spans more that one
                    // instruction.
                    let start_index = *idx;
                    assert!(start_index < index);

                    // We're going to check if this is the last instruction that
                    // uses this operand. If it is, we can return the allocated
                    // register to the pool.
                    if live_ranges[start_index] == index {
                        if let Opnd::Reg(reg) = asm.insns[start_index].out {
                            dealloc_reg(&mut pool, &regs, &reg);
                        } else {
                            unreachable!("no register allocated for insn");
                        }
                    }
                }
            }

            // If this instruction is used by another instruction,
            // we need to allocate a register to it
            let mut out_reg = Opnd::None;
            if live_ranges[index] != index {
                // If this instruction's first operand maps to a register and
                // this is the last use of the register, reuse the register
                // We do this to improve register allocation on x86
                // e.g. out  = add(reg0, reg1)
                //      reg0 = add(reg0, reg1)
                if opnds.len() > 0 {
                    if let Opnd::InsnOut(idx) = opnds[0] {
                        if live_ranges[idx] == index {
                            if let Opnd::Reg(reg) = asm.insns[idx].out {
                                out_reg = Opnd::Reg(alloc_reg(&mut pool, &vec![reg]))
                            }
                        }
                    }
                }

                // Allocate a new register for this instruction
                if out_reg == Opnd::None {
                    out_reg = Opnd::Reg(alloc_reg(&mut pool, &regs))
                }
            }

            // Replace InsnOut operands by their corresponding register
            let reg_opnds = opnds.into_iter().map(|opnd|
                match opnd {
                     Opnd::InsnOut(idx) => asm.insns[idx].out,
                     _ => opnd,
                }
            ).collect();

            asm.push_insn(op, reg_opnds, target);

            // Set the output register for this instruction
            let num_insns = asm.insns.len();
            asm.insns[num_insns - 1].out = out_reg;
        });

        assert_eq!(pool, 0, "Expected all registers to be returned to the pool");
        asm
    }

    /// Compile the instructions down to machine code
    pub fn compile(self, cb: &mut CodeBlock)
    {
        let scratch_regs = Self::get_scratch_regs();
        self.compile_with_regs(cb, scratch_regs);
    }
}

impl fmt::Debug for Assembler {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        fmt.debug_list().entries(self.insns.iter()).finish()
    }
}

impl Assembler
{
    // Jump if not zero
    pub fn jnz(&mut self, target: Target)
    {
        self.push_insn(Op::Jnz, vec![], Some(target));
    }

    pub fn jbe(&mut self, target: Target)
    {
        self.push_insn(Op::Jbe, vec![], Some(target));
    }
}

macro_rules! def_push_1_opnd {
    ($op_name:ident, $opcode:expr) => {
        impl Assembler
        {
            pub fn $op_name(&mut self, opnd0: Opnd) -> Opnd
            {
                self.push_insn($opcode, vec![opnd0], None)
            }
        }
    };
}

macro_rules! def_push_2_opnd {
    ($op_name:ident, $opcode:expr) => {
        impl Assembler
        {
            pub fn $op_name(&mut self, opnd0: Opnd, opnd1: Opnd) -> Opnd
            {
                self.push_insn($opcode, vec![opnd0, opnd1], None)
            }
        }
    };
}

macro_rules! def_push_2_opnd_no_out {
    ($op_name:ident, $opcode:expr) => {
        impl Assembler
        {
            pub fn $op_name(&mut self, opnd0: Opnd, opnd1: Opnd)
            {
                self.push_insn($opcode, vec![opnd0, opnd1], None);
            }
        }
    };
}

def_push_2_opnd!(add, Op::Add);
def_push_2_opnd!(sub, Op::Sub);
def_push_2_opnd!(and, Op::And);
def_push_1_opnd!(load, Op::Load);
def_push_2_opnd_no_out!(mov, Op::Mov);
def_push_2_opnd_no_out!(cmp, Op::Cmp);
def_push_2_opnd_no_out!(test, Op::Test);

// NOTE: these methods are temporary and will likely move
// to context.rs later
// They are just wrappers to convert from X86Opnd into the IR Opnd type
impl Context
{
    pub fn ir_stack_pop(&mut self, n: usize) -> Opnd {
        self.stack_pop(n).into()
    }

    pub fn ir_stack_push(&mut self, val_type: Type) -> Opnd {
        self.stack_push(val_type).into()
    }

    pub fn ir_stack_push_mapping(&mut self, (mapping, temp_type): (TempMapping, Type)) -> Opnd {
        self.stack_push_mapping((mapping, temp_type)).into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cruby::*;
    use crate::core::*;
    use InsnOpnd::*;

    // Test that this function type checks
    fn gen_dup(
        ctx: &mut Context,
        asm: &mut Assembler,
    ) {
        let dup_val = ctx.ir_stack_pop(0);
        let (mapping, tmp_type) = ctx.get_opnd_mapping(StackOpnd(0));

        let loc0 = ctx.ir_stack_push_mapping((mapping, tmp_type));
        asm.mov(loc0, dup_val);
    }

    fn guard_object_is_heap(
        asm: &mut Assembler,
        object_opnd: Opnd,
        ctx: &mut Context,
        side_exit: CodePtr,
    ) {
        asm.comment("guard object is heap");

        // Test that the object is not an immediate
        asm.test(object_opnd.clone(), Opnd::UImm(RUBY_IMMEDIATE_MASK as u64));
        asm.jnz(Target::CodePtr(side_exit));

        // Test that the object is not false or nil
        asm.cmp(object_opnd.clone(), Opnd::UImm(Qnil.into()));
        asm.jbe(Target::CodePtr(side_exit));
    }

    #[test]
    fn test_add() {
        let mut asm = Assembler::new();
        let out = asm.add(SP, Opnd::UImm(1));
        asm.add(out, Opnd::UImm(2));
    }

    #[test]
    fn test_split_loads() {
        let mut asm = Assembler::new();

        let regs = Assembler::get_scratch_regs();

        asm.add(
            Opnd::mem(64, Opnd::Reg(regs[0]), 0),
            Opnd::mem(64, Opnd::Reg(regs[1]), 0)
        );

        let result = asm.split_loads();
        assert_eq!(result.insns.len(), 2);
        assert_eq!(result.insns[0].op, Op::Load);
    }

    #[test]
    fn test_alloc_regs() {
        let mut asm = Assembler::new();

        // Get the first output that we're going to reuse later.
        let out1 = asm.add(EC, Opnd::UImm(1));

        // Pad some instructions in to make sure it can handle that.
        asm.add(EC, Opnd::UImm(2));

        // Get the second output we're going to reuse.
        let out2 = asm.add(EC, Opnd::UImm(3));

        // Pad another instruction.
        asm.add(EC, Opnd::UImm(4));

        // Reuse both the previously captured outputs.
        asm.add(out1, out2);

        // Now get a third output to make sure that the pool has registers to
        // allocate now that the previous ones have been returned.
        let out3 = asm.add(EC, Opnd::UImm(5));
        asm.add(out3, Opnd::UImm(6));

        // Here we're going to allocate the registers.
        let result = asm.alloc_regs(Assembler::get_scratch_regs());

        // Now we're going to verify that the out field has been appropriately
        // updated for each of the instructions that needs it.
        let regs = Assembler::get_scratch_regs();
        assert_eq!(result.insns[0].out, Opnd::Reg(regs[0]));
        assert_eq!(result.insns[2].out, Opnd::Reg(regs[1]));
        assert_eq!(result.insns[5].out, Opnd::Reg(regs[0]));
    }

    // Test full codegen pipeline
    #[test]
    fn test_compile()
    {
        let mut asm = Assembler::new();
        let mut cb = CodeBlock::new_dummy(1024);
        let regs = Assembler::get_scratch_regs();

        let out = asm.add(Opnd::Reg(regs[0]), Opnd::UImm(2));
        asm.add(out, Opnd::UImm(2));

        asm.compile(&mut cb);
    }

    // Test memory-to-memory move
    #[test]
    fn test_mov_mem2mem()
    {
        let mut asm = Assembler::new();
        let mut cb = CodeBlock::new_dummy(1024);
        let regs = Assembler::get_scratch_regs();

        asm.comment("check that comments work too");
        asm.mov(Opnd::mem(64, SP, 0), Opnd::mem(64, SP, 8));

        asm.compile_with_regs(&mut cb, vec![regs[0]]);
    }

    // Test load of register into new register
    #[test]
    fn test_load_reg()
    {
        let mut asm = Assembler::new();
        let mut cb = CodeBlock::new_dummy(1024);
        let regs = Assembler::get_scratch_regs();

        let out = asm.load(SP);
        asm.mov(Opnd::mem(64, SP, 0), out);

        asm.compile_with_regs(&mut cb, vec![regs[0]]);
    }

    // Multiple registers needed and register reuse
    #[test]
    fn test_reuse_reg()
    {
        let mut asm = Assembler::new();
        let mut cb = CodeBlock::new_dummy(1024);
        let regs = Assembler::get_scratch_regs();

        let v0 = asm.add(Opnd::mem(64, SP, 0), Opnd::UImm(1));
        let v1 = asm.add(Opnd::mem(64, SP, 8), Opnd::UImm(1));
        let v2 = asm.add(v0, Opnd::UImm(1));
        asm.add(v0, v2);

        asm.compile_with_regs(&mut cb, vec![regs[0], regs[1]]);
    }
}
