// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::cruby::*;
use std::collections::HashMap;

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(usize);

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

/// Instruction operand
#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Opnd {
    Const(VALUE),
    Insn(InsnId),
}

impl std::fmt::Display for Opnd {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Opnd::Const(val) if val.fixnum_p() => write!(f, "Fixnum({})", val.as_fixnum()),
            Opnd::Const(val) => write!(f, "Const({:?})", val.as_ptr::<u8>()),
            Opnd::Insn(insn_id) => write!(f, "{insn_id}"),
        }
    }
}

#[derive(Debug, PartialEq)]
pub struct BranchEdge {
    target: BlockId,
    args: Vec<Opnd>,
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

#[derive(Debug, PartialEq)]
pub struct CallInfo {
    name: String,
}

#[derive(Debug, PartialEq)]
pub enum Insn {
    // SSA block parameter. Also used for function parameters in the function's entry block.
    Param { idx: usize },

    StringCopy { val: Opnd },
    StringIntern { val: Opnd },

    NewArray { count: usize },
    ArraySet { idx: usize, val: Opnd },
    Test { val: Opnd },
    Defined { op_type: usize, obj: VALUE, pushval: VALUE, v: Opnd },
    GetConstantPath { ic: *const u8 },

    //NewObject?
    //SetIvar {},
    //GetIvar {},

    // Unconditional jump
    Jump(BranchEdge),

    // Conditional branch instructions
    IfTrue { val: Opnd, branch: BranchEdge },
    IfFalse { val: Opnd, target: BranchEdge },

    // Call a C function
    // TODO: should we store the C function name?
    CCall { cfun: *const u8, args: Vec<Opnd> },

    // Send with dynamic dispatch
    // Ignoring keyword arguments etc for now
    Send { self_val: Opnd, call_info: CallInfo, args: Vec<Opnd> },

    // Control flow instructions
    Return { val: Opnd },
}

#[derive(Default, Debug, PartialEq)]
pub struct Block {
    params: Vec<InsnId>,
    insns: Vec<InsnId>,
}

impl Block {
}

#[derive(Debug, PartialEq)]
pub struct Function {
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

    fn new_block(&mut self) -> BlockId {
        let id = BlockId(self.blocks.len());
        self.blocks.push(Block::default());
        id
    }
}

impl std::fmt::Display for Function {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        for (block_id, block) in self.blocks.iter().enumerate() {
            let block_id = BlockId(block_id);
            writeln!(f, "{block_id}:")?;
            for insn_id in &block.insns {
                write!(f, "  {insn_id} = ")?;
                match &self.insns[insn_id.0] {
                    Insn::Param { idx } => { write!(f, "Param {idx}")?; }
                    Insn::IfFalse { val, target } => { write!(f, "IfFalse {val}, {target}")?; }
                    Insn::Return { val } => { write!(f, "Return {val}")?; }
                    Insn::Send { self_val, call_info, args } => {
                        write!(f, "Send {self_val}, {}", call_info.name)?;
                        for arg in args {
                            write!(f, ", {arg}")?;
                        }
                    }
                    Insn::Test { val } => { write!(f, "Test {val}")?; }
                    insn => { write!(f, "{insn:?}")?; }
                }
                writeln!(f, "")?;
            }
        }
        Ok(())
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

/// Get instruction argument
fn get_arg(pc: *const VALUE, arg_idx: isize) -> VALUE {
    unsafe { *(pc.offset(arg_idx + 1)) }
}

fn insn_idx_at_offset(idx: u32, offset: i64) -> u32 {
    ((idx as isize) + (offset as isize)) as u32
}

fn compute_jump_targets(iseq: *const rb_iseq_t) -> Vec<u32> {
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx = 0;
    let mut jump_targets = vec![];
    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };

        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();
        insn_idx += insn_len(opcode as usize);
        match opcode {
            YARVINSN_branchunless => {
                let offset = get_arg(pc, 0).as_i64();
                jump_targets.push(insn_idx_at_offset(insn_idx, offset));
            }
            _ => eprintln!("zjit: compute_jump_targets: unknown opcode `{}'", insn_name(opcode as usize)),
        }
    }
    jump_targets
}

pub fn iseq_to_ssa(iseq: *const rb_iseq_t) -> Function {
    let mut fun = Function::new();
    let mut state = FrameState::new();
    let mut block = fun.entry_block;

    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx = 0;

    // Compute a map of PC->Block by finding jump targets
    let jump_targets = compute_jump_targets(iseq);
    let mut insn_idx_to_block = HashMap::new();
    for insn_idx in jump_targets {
        if insn_idx == 0 {
            todo!("Separate entry block for param/self/...");
        }
        insn_idx_to_block.insert(insn_idx, fun.new_block());
    }

    while insn_idx < iseq_size {
        // Get the block id for this instruction
        if let Some(block_id) = insn_idx_to_block.get(&insn_idx) {
            block = *block_id;
        }

        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
        state.pc = pc;

        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: u32 = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();

        // Move to the next instruction to compile
        insn_idx += insn_len(opcode as usize);

        match opcode {
            YARVINSN_nop => {},
            YARVINSN_putnil => { state.push(Opnd::Const(Qnil)); },
            YARVINSN_putobject => { state.push(Opnd::Const(get_arg(pc, 0))); },
            YARVINSN_putstring => {
                let val = Opnd::Const(get_arg(pc, 0));
                let insn_id = fun.push_insn(block, Insn::StringCopy { val });
                state.push(Opnd::Insn(insn_id));
            }
            YARVINSN_intern => {
                let val = state.pop();
                let insn_id = fun.push_insn(block, Insn::StringIntern { val });
                state.push(Opnd::Insn(insn_id));
            }
            YARVINSN_newarray => {
                let count = get_arg(pc, 0).as_usize();
                let insn_id = fun.push_insn(block, Insn::NewArray { count });
                for idx in (0..count).rev() {
                    fun.push_insn(block, Insn::ArraySet { idx, val: state.pop() });
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
            YARVINSN_defined => {
                let op_type = get_arg(pc, 0).as_usize();
                let obj = get_arg(pc, 0);
                let pushval = get_arg(pc, 0);
                let v = state.pop();
                state.push(Opnd::Insn(fun.push_insn(block, Insn::Defined { op_type, obj, pushval, v })));
            }
            YARVINSN_opt_getconstant_path => {
                let ic = get_arg(pc, 0).as_ptr::<u8>();
                state.push(Opnd::Insn(fun.push_insn(block, Insn::GetConstantPath { ic })));
            }
            YARVINSN_branchunless => {
                let offset = get_arg(pc, 0).as_i64();
                let val = state.pop();
                let test_id = fun.push_insn(block, Insn::Test { val });
                // TODO(max): Check interrupts
                let _branch_id = fun.push_insn(block,
                    Insn::IfFalse {
                        val: Opnd::Insn(test_id),
                        target: BranchEdge {
                            target: insn_idx_to_block[&insn_idx_at_offset(insn_idx, offset)],
                            args: vec![],
                        }
                    });
            }
            YARVINSN_opt_nil_p => {
                let recv = state.pop();
                state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: "nil?".into() }, args: vec![] })));
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
                let v0 = state.pop();
                let v1 = state.pop();
                state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: v0, call_info: CallInfo { name: "+".into() }, args: vec![v1] })));
            }

            YARVINSN_opt_lt => {
                let v0 = state.pop();
                let v1 = state.pop();
                state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: v0, call_info: CallInfo { name: "<".into() }, args: vec![v1] })));
            }

            YARVINSN_leave => {
                fun.push_insn(block, Insn::Return { val: state.pop() });
            }

            YARVINSN_opt_send_without_block => {
                let cd: *const rb_call_data = get_arg(pc, 0).as_ptr();
                let call_info = unsafe { rb_get_call_data_ci(cd) };
                let argc = unsafe { vm_ci_argc((*cd).ci) };


                let method_name = unsafe {
                    let mid = rb_vm_ci_mid(call_info);
                    cstr_to_rust_string(rb_id2name(mid)).unwrap_or_else(|| "<unknown>".to_owned())
                };

                assert_eq!(0, argc, "really, it's pop(argc), and more, but idk how to do that yet");
                let recv = state.pop();
                state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: method_name }, args: vec![] })));
            }
            _ => eprintln!("zjit: to_ssa: unknown opcode `{}'", insn_name(opcode as usize)),
        }
    }

    print!("SSA:\n{fun}");
    return fun;
}

#[cfg(test)]
mod tests {
    use super::*;

    /*
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
    */
}
