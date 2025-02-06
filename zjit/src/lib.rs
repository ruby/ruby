#![allow(dead_code)]

mod cruby;
mod stats;

extern "C" fn zjit_init() {
    println!("zjit_init");
}

#[no_mangle]
pub extern "C" fn rb_zjit_parse_option() -> bool {
    false
}

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(usize);

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(usize);

// TODO: replace with VALUE
#[derive(Debug, PartialEq)]
enum RubyValue {
    Nil,
}

#[derive(Debug, PartialEq)]
enum Insn {
    Param { idx: usize },
    Const { val: RubyValue },
    Return { val: InsnId },
}

#[derive(Debug, PartialEq)]
struct Block {
    params: Vec<InsnId>,
    insns: Vec<InsnId>,
}

impl Block {
    fn new() -> Block {
        Block { params: vec![], insns: vec![] }
    }
}

#[derive(Debug, PartialEq)]
struct Function {
    entry_block: BlockId,
    insns: Vec<Insn>,
    blocks: Vec<Block>,
}

impl Function {
    fn new() -> Function {
        Function { blocks: vec![Block::new()], insns: vec![], entry_block: BlockId(0) }
    }

    fn push_insn(&mut self, block: BlockId, insn: Insn) -> InsnId {
        let id = InsnId(self.insns.len());
        self.insns.push(insn);
        // Add the insn to the block
        self.blocks[block.0].insns.push(id);
        id
    }
}

enum RubyOpcode {
    Putnil,
    Leave,
}

struct FrameState {
    stack: Vec<InsnId>,
}

impl FrameState {
    fn new() -> FrameState {
        FrameState { stack: vec![] }
    }

    fn push(&mut self, val: InsnId) {
        self.stack.push(val);
    }

    fn pop(&mut self) -> InsnId {
        self.stack.pop().expect("Bytecode stack mismatch")
    }
}

fn to_ssa(opcodes: &Vec<RubyOpcode>) -> Function {
    let mut result = Function::new();
    let mut state = FrameState::new();
    let block = result.entry_block;
    for opcode in opcodes {
        match opcode {
            RubyOpcode::Putnil => {
                state.push(result.push_insn(block, Insn::Const { val: RubyValue::Nil }));
            },
            RubyOpcode::Leave => {
                result.push_insn(block, Insn::Return { val: state.pop() });
            },
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use crate::*;

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
                Insn::Const { val: RubyValue::Nil },
                Insn::Return { val: InsnId(0) }],
            blocks: vec![
                Block { params: vec![], insns: vec![InsnId(0), InsnId(1)] }
            ],
        });
    }
}
