// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::cruby::*;

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(usize);

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(usize);

/// Instruction operand
#[derive(Debug, PartialEq, Clone, Copy)]
enum Opnd {
    Const(VALUE),
    Insn(InsnId),
}

#[derive(Debug, PartialEq)]
struct BranchEdge {
    target: BlockId,
    args: Vec<Opnd>,
}

#[derive(Debug, PartialEq)]
enum Insn {
    // SSA block parameter. Also used for function parameters in the function's entry block.
    Param { idx: usize },

    StringCopy { val: Opnd },
    StringIntern { val: Opnd },

    NewArray { count: usize },
    ArraySet { idx: usize, val: Opnd },

    //NewObject?
    //SetIvar {},
    //GetIvar {},

    // Control flow instructions
    Return { val: Opnd },

    // Unconditional jump
    Jump(BranchEdge),

    // Operators
    Add { v0: Opnd, v1: Opnd },

    // Conditional branch instructions
    IfTrue { val: Opnd, branch: BranchEdge },
    IfFalse { val: Opnd, target: BranchEdge },
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
    // TODO:
    // ISEQ this function refers to
    //iseq: *const iseqptr_t,

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

struct FrameState {
    // Ruby bytecode instruction pointer
    pc: *mut VALUE,

    stack: Vec<Opnd>,
    locals: Vec<Opnd>,
}

impl FrameState {
    fn new() -> FrameState {
        FrameState { pc: 0 as *mut VALUE, stack: vec![], locals: vec![] }
    }

    fn push(&mut self, opnd: Opnd) {
        self.stack.push(opnd);
    }

    fn top(&self) -> Opnd {
        *self.stack.last().unwrap()
    }

    fn pop(&mut self) -> Opnd {
        self.stack.pop().expect("Bytecode stack mismatch (underflow)")
    }

    fn setlocal(&mut self, idx: usize, opnd: Opnd) {
        if idx >= self.locals.len() {
            self.locals.resize(idx+1, Opnd::Const(Qnil));
        }
        self.locals[idx] = opnd;
    }

    fn getlocal(&mut self, idx: usize) -> Opnd {
        if idx >= self.locals.len() {
            self.locals.resize(idx+1, Opnd::Const(Qnil));
        }
        self.locals[idx]
    }
}

// TODO: get rid of this, currently used for testing only
enum RubyOpcode {
    Putnil,
    Putobject(VALUE),
    Putstring(VALUE),
    Intern,
    Setlocal(usize),
    Getlocal(usize),
    Newarray(usize),
    Leave,
}
fn to_ssa(opcodes: &Vec<RubyOpcode>) -> Function {
    let mut result = Function::new();
    let mut state = FrameState::new();
    let block = result.entry_block;
    for opcode in opcodes {
        match opcode {
            RubyOpcode::Putnil => { state.push(Opnd::Const(Qnil)); },
            RubyOpcode::Putobject(val) => { state.push(Opnd::Const(*val)); },
            RubyOpcode::Putstring(val) => {
                let insn_id = result.push_insn(block, Insn::StringCopy { val: Opnd::Const(*val) });
                state.push(Opnd::Insn(insn_id));
            }
            RubyOpcode::Intern => {
                let val = state.pop();
                let insn_id = result.push_insn(block, Insn::StringIntern { val });
                state.push(Opnd::Insn(insn_id));
            }
            RubyOpcode::Newarray(count) => {
                let insn_id = result.push_insn(block, Insn::NewArray { count: *count });
                for idx in (0..*count).rev() {
                    result.push_insn(block, Insn::ArraySet { idx, val: state.pop() });
                }
                state.push(Opnd::Insn(insn_id));
            }
            RubyOpcode::Setlocal(idx) => {
                let val = state.pop();
                state.setlocal(*idx, val);
            }
            RubyOpcode::Getlocal(idx) => {
                let val = state.getlocal(*idx);
                state.push(val);
            }
            RubyOpcode::Leave => {
                result.push_insn(block, Insn::Return { val: state.pop() });
            },
        }
    }
    result
}

pub fn iseq_to_ssa(iseq: *const rb_iseq_t) {
    let mut result = Function::new();
    let mut state = FrameState::new();
    let block = result.entry_block;

    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx = 0;

    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
        state.pc = pc;

        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();

        match opcode {
            YARVINSN_nop => {},
            YARVINSN_putnil => { state.push(Opnd::Const(Qnil)); },
            YARVINSN_putobject => { state.push(Opnd::Const(get_arg(pc, 0))); },
            YARVINSN_putstring => {
                let val = Opnd::Const(get_arg(pc, 0));
                let insn_id = result.push_insn(block, Insn::StringCopy { val });
                state.push(Opnd::Insn(insn_id));
            }
            YARVINSN_intern => {
                let val = state.pop();
                let insn_id = result.push_insn(block, Insn::StringIntern { val });
                state.push(Opnd::Insn(insn_id));
            }
            YARVINSN_newarray => {
                let count = get_arg(pc, 0).as_usize();
                let insn_id = result.push_insn(block, Insn::NewArray { count });
                for idx in (0..count).rev() {
                    result.push_insn(block, Insn::ArraySet { idx, val: state.pop() });
                }
                state.push(Opnd::Insn(insn_id));
            }
            YARVINSN_putobject_INT2FIX_0_ => {
                state.push(Opnd::Const(VALUE::fixnum_from_usize(0)));
            }
            YARVINSN_putobject_INT2FIX_1_ => {
                state.push(Opnd::Const(VALUE::fixnum_from_usize(1)));
            }
            YARVINSN_setlocal_WC_0 => {
                let val = state.pop();
                state.setlocal(0, val);
            }
            YARVINSN_getlocal_WC_0 => {
                let val = state.getlocal(0);
                state.push(val);
            }
            YARVINSN_pop => { state.pop(); }
            YARVINSN_dup => { state.push(state.top()); }
            YARVINSN_swap => {
                let right = state.pop();
                let left = state.pop();
                state.push(right);
                state.push(left);
            }

            YARVINSN_opt_plus => {
                // TODO: we need to add a BOP not redefined check here
                let v0 = state.pop();
                let v1 = state.pop();
                let add_id = result.push_insn(block, Insn::Add { v0, v1 });
                state.push(Opnd::Insn(add_id));
            }

            YARVINSN_leave => {
                result.push_insn(block, Insn::Return { val: state.pop() });
            }
            _ => eprintln!("zjit: unknown opcode `{}'", insn_name(opcode as usize)),
        }

        // Move to the next instruction to compile
        insn_idx += insn_len(opcode as usize);
    }
    dbg!(result);
    return;

    fn get_arg(pc: *const VALUE, arg_idx: isize) -> VALUE {
        unsafe { *(pc.offset(arg_idx + 1)) }

    }
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

    #[test]
    fn test_intern() {
        let opcodes = vec![
            RubyOpcode::Putstring(Qnil),
            RubyOpcode::Intern,
            RubyOpcode::Leave,
        ];
        let function = to_ssa(&opcodes);
        assert_eq!(function, Function {
            entry_block: BlockId(0),
            insns: vec![
                Insn::StringCopy { val: Opnd::Const(Qnil) },
                Insn::StringIntern { val: Opnd::Insn(InsnId(0)) },
                Insn::Return { val: Opnd::Insn(InsnId(1)) }
            ],
            blocks: vec![
                Block { params: vec![], insns: vec![InsnId(0), InsnId(1), InsnId(2)] }
            ],
        });
    }

    #[test]
    fn test_newarray0() {
        let opcodes = vec![
            RubyOpcode::Newarray(0),
            RubyOpcode::Leave,
        ];
        let function = to_ssa(&opcodes);
        assert_eq!(function, Function {
            entry_block: BlockId(0),
            insns: vec![
                Insn::NewArray { count: 0 },
                Insn::Return { val: Opnd::Insn(InsnId(0)) }
            ],
            blocks: vec![
                Block { params: vec![], insns: vec![InsnId(0), InsnId(1)] }
            ],
        });
    }

    #[test]
    fn test_newarray1() {
        let opcodes = vec![
            RubyOpcode::Putnil,
            RubyOpcode::Newarray(1),
            RubyOpcode::Leave,
        ];
        let function = to_ssa(&opcodes);
        assert_eq!(function, Function {
            entry_block: BlockId(0),
            insns: vec![
                Insn::NewArray { count: 1 },
                Insn::ArraySet { idx: 0, val: Opnd::Const(Qnil) },
                Insn::Return { val: Opnd::Insn(InsnId(0)) }
            ],
            blocks: vec![
                Block { params: vec![], insns: vec![InsnId(0), InsnId(1), InsnId(2)] }
            ],
        });
    }

    #[test]
    fn test_newarray2() {
        let three: VALUE = VALUE::fixnum_from_usize(3);
        let four: VALUE = VALUE::fixnum_from_usize(4);
        let opcodes = vec![
            RubyOpcode::Putobject(three),
            RubyOpcode::Putobject(four),
            RubyOpcode::Newarray(2),
            RubyOpcode::Leave,
        ];
        let function = to_ssa(&opcodes);
        assert_eq!(function, Function {
            entry_block: BlockId(0),
            insns: vec![
                Insn::NewArray { count: 2 },
                Insn::ArraySet { idx: 1, val: Opnd::Const(four) },
                Insn::ArraySet { idx: 0, val: Opnd::Const(three) },
                Insn::Return { val: Opnd::Insn(InsnId(0)) }
            ],
            blocks: vec![
                Block { params: vec![], insns: vec![InsnId(0), InsnId(1), InsnId(2), InsnId(3)] }
            ],
        });
    }
}
