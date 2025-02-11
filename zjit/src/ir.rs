// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::cruby::*;
use std::collections::{HashMap, HashSet};

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

fn write_vec<T: std::fmt::Display>(f: &mut std::fmt::Formatter, objs: &Vec<T>) -> std::fmt::Result {
    write!(f, "[")?;
    let mut prefix = "";
    for obj in objs {
        write!(f, "{prefix}{obj}")?;
        prefix = ", ";
    }
    write!(f, "]")
}

impl std::fmt::Display for Opnd {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Opnd::Const(val) if val.fixnum_p() => write!(f, "Fixnum({})", val.as_fixnum()),
            Opnd::Const(val) if val.nil_p() => write!(f, "nil"),
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

#[derive(Debug)]
pub enum Insn {
    PutSelf,
    // SSA block parameter. Also used for function parameters in the function's entry block.
    Param { idx: usize },

    StringCopy { val: Opnd },
    StringIntern { val: Opnd },

    NewArray { count: usize },
    ArraySet { idx: usize, val: Opnd },
    ArrayDup { val: Opnd },
    Test { val: Opnd },
    Defined { op_type: usize, obj: VALUE, pushval: VALUE, v: Opnd },
    GetConstantPath { ic: *const u8 },

    //NewObject?
    //SetIvar {},
    //GetIvar {},

    Snapshot { state: FrameState },

    // Unconditional jump
    Jump(BranchEdge),

    // Conditional branch instructions
    IfTrue { val: Opnd, target: BranchEdge },
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
    fn from(fun: &'a Function) -> FunctionPrinter<'a> {
        FunctionPrinter { fun, display_snapshot: false }
    }

    fn with_snapshot(fun: &'a Function) -> FunctionPrinter<'a> {
        FunctionPrinter { fun, display_snapshot: true }
    }
}

#[derive(Debug)]
pub struct Function {
    // ISEQ this function refers to
    iseq: *const rb_iseq_t,

    // TODO: get method name and source location from the ISEQ

    insns: Vec<Insn>,
    blocks: Vec<Block>,
    entry_block: BlockId,
}

impl Function {
    fn new(iseq: *const rb_iseq_t) -> Function {
        Function {
            iseq,
            insns: vec![],
            blocks: vec![Block::default()],
            entry_block: BlockId(0)
        }
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

impl<'a> std::fmt::Display for FunctionPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let fun = &self.fun;
        for (block_id, block) in fun.blocks.iter().enumerate() {
            let block_id = BlockId(block_id);
            writeln!(f, "{block_id}:")?;
            for insn_id in &block.insns {
                if !self.display_snapshot && matches!(fun.insns[insn_id.0], Insn::Snapshot {..}) {
                    continue;
                }
                write!(f, "  {insn_id} = ")?;
                match &fun.insns[insn_id.0] {
                    Insn::Param { idx } => { write!(f, "Param {idx}")?; }
                    Insn::IfTrue { val, target } => { write!(f, "IfTrue {val}, {target}")?; }
                    Insn::IfFalse { val, target } => { write!(f, "IfFalse {val}, {target}")?; }
                    Insn::Jump(target) => { write!(f, "Jump {target}")?; }
                    Insn::Return { val } => { write!(f, "Return {val}")?; }
                    Insn::NewArray { count } => { write!(f, "NewArray {count}")?; }
                    Insn::ArraySet { idx, val } => { write!(f, "ArraySet {idx}, {val}")?; }
                    Insn::ArrayDup { val } => { write!(f, "ArrayDup {val}")?; }
                    Insn::Send { self_val, call_info, args } => {
                        write!(f, "Send {self_val}, :{}", call_info.name)?;
                        for arg in args {
                            write!(f, ", {arg}")?;
                        }
                    }
                    Insn::Test { val } => { write!(f, "Test {val}")?; }
                    Insn::Snapshot { state } => { write!(f, "Snapshot {state}")?; }
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
    // Ruby bytecode instruction pointer
    pc: VALUE,

    stack: Vec<Opnd>,
    locals: Vec<Opnd>,
}

impl FrameState {
    fn new() -> FrameState {
        FrameState { pc: VALUE(0), stack: vec![], locals: vec![] }
    }

    fn push(&mut self, opnd: Opnd) {
        self.stack.push(opnd);
    }

    fn top(&self) -> Result<Opnd, ParseError> {
        self.stack.last().ok_or_else(|| ParseError::StackUnderflow(self.clone())).copied()
    }

    fn pop(&mut self) -> Result<Opnd, ParseError> {
        self.stack.pop().ok_or_else(|| ParseError::StackUnderflow(self.clone()))
    }

    fn setn(&mut self, n: usize, opnd: Opnd) {
        let idx = self.stack.len() - n - 1;
        self.stack[idx] = opnd;
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

    fn as_args(&self) -> Vec<Opnd> {
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
}

/// Return the number of locals in the given ISEQ
fn num_locals(iseq: *const rb_iseq_t) -> u32 {
    unsafe { get_iseq_body_local_table_size(iseq) }
}

pub fn iseq_to_ssa(iseq: *const rb_iseq_t) -> Result<Function, ParseError> {
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
    queue.push_back((FrameState::new(), fun.entry_block, /*insn_idx=*/0 as u32));

    let mut visited = HashSet::new();

    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    while let Some((incoming_state, block, mut insn_idx)) = queue.pop_front() {
        if visited.contains(&block) { continue; }
        visited.insert(block);
        let mut state = {
            let mut result = FrameState::new();
            let mut idx = 0;
            for _ in 0..num_locals(iseq) {
                result.locals.push(Opnd::Insn(fun.push_insn(block, Insn::Param { idx })));
                idx += 1;
            }
            for _ in incoming_state.stack {
                result.stack.push(Opnd::Insn(fun.push_insn(block, Insn::Param { idx })));
                idx += 1;
            }
            result
        };
        while insn_idx < iseq_size {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
            state.pc = unsafe { *pc };
            fun.push_insn(block, Insn::Snapshot { state: state.clone() });

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
                YARVINSN_putself => { state.push(Opnd::Insn(fun.push_insn(block, Insn::PutSelf))); }
                YARVINSN_intern => {
                    let val = state.pop()?;
                    let insn_id = fun.push_insn(block, Insn::StringIntern { val });
                    state.push(Opnd::Insn(insn_id));
                }
                YARVINSN_newarray => {
                    let count = get_arg(pc, 0).as_usize();
                    let insn_id = fun.push_insn(block, Insn::NewArray { count });
                    for idx in (0..count).rev() {
                        fun.push_insn(block, Insn::ArraySet { idx, val: state.pop()? });
                    }
                    state.push(Opnd::Insn(insn_id));
                }
                YARVINSN_duparray => {
                    let val = Opnd::Const(get_arg(pc, 0));
                    let insn_id = fun.push_insn(block, Insn::ArrayDup { val });
                    state.push(Opnd::Insn(insn_id));
                }
                YARVINSN_putobject_INT2FIX_0_ => {
                    state.push(Opnd::Const(VALUE::fixnum_from_usize(0)));
                }
                YARVINSN_putobject_INT2FIX_1_ => {
                    state.push(Opnd::Const(VALUE::fixnum_from_usize(1)));
                }
                YARVINSN_defined => {
                    let op_type = get_arg(pc, 0).as_usize();
                    let obj = get_arg(pc, 0);
                    let pushval = get_arg(pc, 0);
                    let v = state.pop()?;
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::Defined { op_type, obj, pushval, v })));
                }
                YARVINSN_opt_getconstant_path => {
                    let ic = get_arg(pc, 0).as_ptr::<u8>();
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::GetConstantPath { ic })));
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
                        val: Opnd::Insn(test_id),
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
                        val: Opnd::Insn(test_id),
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
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: "nil?".into() }, args: vec![] })));
                }
                YARVINSN_getlocal_WC_0 => {
                    let idx = get_arg(pc, 0).as_usize();
                    let val = state.getlocal(idx);
                    state.push(val);
                }
                YARVINSN_setlocal_WC_0 => {
                    let idx = get_arg(pc, 0).as_usize();
                    let val = state.pop()?;
                    state.setlocal(idx, val);
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

                YARVINSN_opt_plus => {
                    let v0 = state.pop()?;
                    let v1 = state.pop()?;
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: v1, call_info: CallInfo { name: "+".into() }, args: vec![v0] })));
                }

                YARVINSN_opt_lt => {
                    let v0 = state.pop()?;
                    let v1 = state.pop()?;
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: v1, call_info: CallInfo { name: "<".into() }, args: vec![v0] })));
                }
                YARVINSN_opt_ltlt => {
                    let v0 = state.pop()?;
                    let v1 = state.pop()?;
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: v1, call_info: CallInfo { name: "<<".into() }, args: vec![v0] })));
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
                    state.push(Opnd::Insn(fun.push_insn(block, Insn::Send { self_val: recv, call_info: CallInfo { name: method_name }, args })));
                }
                _ => eprintln!("zjit: to_ssa: unknown opcode `{}'", insn_name(opcode as usize)),
            }

            if insn_idx_to_block.contains_key(&insn_idx) {
                let target = insn_idx_to_block[&insn_idx];
                fun.push_insn(block, Insn::Jump(BranchEdge { target, args: state.as_args() }));
                queue.push_back((state, target, insn_idx));
                break;  // End the block
            }
        }
    }

    let formatter = FunctionPrinter::from(&fun);
    print!("SSA:\n{formatter}");
    Ok(fun)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn boot_vm() {
        crate::cruby::with_rubyvm(|| {
            let program = "nil.itself";
            let iseq = compile_to_iseq(program);
            let function = iseq_to_ssa(iseq).unwrap();
            assert!(matches!(function.insns.get(0), Some(Insn::Snapshot { .. })));
        });
    }


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
