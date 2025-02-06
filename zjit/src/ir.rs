use crate::cruby::{VALUE, Qnil};

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(usize);

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(usize);

/// Instruction operand
#[derive(Debug, PartialEq)]
enum Opnd {
    Const(VALUE),
    Insn(InsnId),
}

#[derive(Debug, PartialEq)]
enum Insn {
    // SSA block parameter
    Param { idx: usize },
    Return { val: Opnd },
}

#[derive(Default, Debug, PartialEq)]
struct Block {
    params: Vec<InsnId>,
    insns: Vec<InsnId>,
}

impl Block {
}

#[derive(Debug, PartialEq)]
struct Function {
    entry_block: BlockId,
    insns: Vec<Insn>,
    blocks: Vec<Block>,
}

impl Function {
    fn new() -> Function {
        Function { blocks: vec![Block::default()], insns: vec![], entry_block: BlockId(0) }
    }

    // Add an instruction to an SSA block
    fn push_insn(&mut self, block: BlockId, insn: Insn) -> InsnId {
        let id = InsnId(self.insns.len());
        self.insns.push(insn);
        self.blocks[block.0].insns.push(id);
        id
    }
}

enum RubyOpcode {
    Putnil,
    Putobject(VALUE),
    Leave,
}

struct FrameState {
    // TODO:
    // Ruby bytecode instruction pointer
    // pc:

    stack: Vec<Opnd>,
}

impl FrameState {
    fn new() -> FrameState {
        FrameState { stack: vec![] }
    }

    fn push(&mut self, opnd: Opnd) {
        self.stack.push(opnd);
    }

    fn pop(&mut self) -> Opnd {
        self.stack.pop().expect("Bytecode stack mismatch")
    }
}

fn to_ssa(opcodes: &Vec<RubyOpcode>) -> Function {
    let mut result = Function::new();
    let mut state = FrameState::new();
    let block = result.entry_block;
    for opcode in opcodes {
        match opcode {
            RubyOpcode::Putnil => { state.push(Opnd::Const(Qnil)); },
            RubyOpcode::Putobject(val) => { state.push(Opnd::Const(*val)); },
            RubyOpcode::Leave => {
                result.push_insn(block, Insn::Return { val: state.pop() });
            },
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test() {
        let opcodes = vec![
            RubyOpcode::Putnil,
            RubyOpcode::Leave,
        ];
        let function = to_ssa(&opcodes);
        assert_eq!(function, Function {
            entry_block: BlockId(0),
            insns: vec![
                Insn::Return { val: Opnd::Const(Qnil) }
            ],
            blocks: vec![
                Block { params: vec![], insns: vec![InsnId(0)] }
            ],
        });
    }
}
