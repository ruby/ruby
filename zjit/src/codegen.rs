use crate::state::ZJITState;
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::invariants::{iseq_escapes_ep, track_no_ep_escape_assumption};
use crate::backend::lir::{self, asm_comment, Assembler, Opnd, Target, CFP, C_ARG_OPNDS, C_RET_OPND, EC, SP};
use crate::hir::{self, Block, BlockId, BranchEdge, CallInfo};
use crate::hir::{Const, FrameState, Function, Insn, InsnId};
use crate::hir_type::{types::Fixnum, Type};

/// Ephemeral code generation state
struct JITState {
    /// Instruction sequence for the method being compiled
    iseq: IseqPtr,

    /// Low-level IR Operands indexed by High-level IR's Instruction ID
    opnds: Vec<Option<Opnd>>,

    /// Labels for each basic block indexed by the BlockId
    labels: Vec<Option<Target>>,
}

impl JITState {
    /// Create a new JITState instance
    fn new(iseq: IseqPtr, num_insns: usize, num_blocks: usize) -> Self {
        JITState {
            iseq,
            opnds: vec![None; num_insns],
            labels: vec![None; num_blocks],
        }
    }

    /// Retrieve the output of a given instruction that has been compiled
    fn get_opnd(&self, insn_id: InsnId) -> Option<lir::Opnd> {
        let opnd = self.opnds[insn_id.0];
        if opnd.is_none() {
            debug!("Failed to get_opnd({insn_id})");
        }
        opnd
    }

    /// Find or create a label for a given BlockId
    fn get_label(&mut self, asm: &mut Assembler, block_id: BlockId) -> Target {
        match &self.labels[block_id.0] {
            Some(label) => label.clone(),
            None => {
                let label = asm.new_label(&format!("{block_id}"));
                self.labels[block_id.0] = Some(label.clone());
                label
            }
        }
    }

    /// Assume that this ISEQ doesn't escape EP. Return false if it's known to escape EP.
    fn assume_no_ep_escape(&mut self) -> bool {
        if iseq_escapes_ep(self.iseq) {
            return false;
        }
        track_no_ep_escape_assumption(self.iseq);
        true
    }
}

/// Generate JIT code for a given ISEQ, which takes EC and CFP as its arguments.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    let code_ptr = iseq_gen_entry_point(iseq);
    if ZJITState::assert_compiles_enabled() && code_ptr == std::ptr::null() {
        let iseq_location = iseq_get_location(iseq, 0);
        panic!("Failed to compile: {iseq_location}");
    }
    code_ptr
}

fn iseq_gen_entry_point(iseq: IseqPtr) -> *const u8 {
    // Do not test the JIT code in HIR tests
    if cfg!(test) {
        return std::ptr::null();
    }

    // Take a lock to avoid writing to ISEQ in parallel with Ractors.
    // with_vm_lock() does nothing if the program doesn't use Ractors.
    with_vm_lock(src_loc!(), || {
        // Compile ISEQ into High-level IR
        let ssa = match hir::iseq_to_hir(iseq) {
            Ok(ssa) => ssa,
            Err(err) => {
                debug!("ZJIT: iseq_to_hir: {:?}", err);
                return std::ptr::null();
            }
        };

        // Compile High-level IR into machine code
        let cb = ZJITState::get_code_block();
        match gen_function(cb, &ssa, iseq) {
            Some(start_ptr) => start_ptr.raw_ptr(cb),

            // Compilation failed, continue executing in the interpreter only
            None => std::ptr::null(),
        }
    })
}

/// Compile High-level IR into machine code
fn gen_function(cb: &mut CodeBlock, function: &Function, iseq: IseqPtr) -> Option<CodePtr> {
    // Set up special registers
    let mut jit = JITState::new(iseq, function.num_insns(), function.num_blocks());
    let mut asm = Assembler::new();
    gen_entry_prologue(&jit, &mut asm);

    // Set method arguments to the arguments of the first basic block
    gen_method_params(&mut jit, &mut asm, function.block(BlockId(0)));

    // Compile each basic block
    let reverse_post_order = function.rpo();
    for &block_id in reverse_post_order.iter() {
        let block = function.block(block_id);
        asm_comment!(asm, "Block: {block_id}");

        // Write a label to jump to the basic block
        let label = jit.get_label(&mut asm, block_id);
        asm.write_label(label);

        // Compile all parameters
        for &insn_id in block.params() {
            match function.find(insn_id) {
                Insn::Param { idx } => {
                    jit.opnds[insn_id.0] = Some(gen_param(idx));
                },
                insn => unreachable!("Non-param insn found in block.params: {insn:?}"),
            }
        }

        // Compile all instructions
        for &insn_id in block.insns() {
            let insn = function.find(insn_id);
            if gen_insn(&mut jit, &mut asm, function, &block, insn_id, &insn).is_none() {
                debug!("Failed to compile insn: {insn_id} {insn:?}");
                return None;
            }
        }
    }

    // Generate code if everything can be compiled
    let start_ptr = asm.compile(cb).map(|(start_ptr, _)| start_ptr);
    cb.mark_all_executable();

    start_ptr
}

/// Compile an instruction
fn gen_insn(jit: &mut JITState, asm: &mut Assembler, function: &Function, block: &Block, insn_id: InsnId, insn: &Insn) -> Option<()> {
    // Convert InsnId to lir::Opnd
    macro_rules! opnd {
        ($insn_id:ident) => {
            jit.get_opnd(*$insn_id)?
        };
    }

    if !matches!(*insn, Insn::Snapshot { .. }) {
        asm_comment!(asm, "Insn: {insn_id} {insn:?}");
    }

    let out_opnd = match insn {
        Insn::PutSelf => gen_putself(),
        Insn::Const { val: Const::Value(val) } => gen_const(*val),
        Insn::Param { idx } => gen_param(*idx),
        Insn::Snapshot { .. } => return Some(()), // we don't need to do anything for this instruction at the moment
        Insn::Jump(branch) => return gen_jump(jit, asm, branch),
        Insn::IfTrue { val, target } => return gen_if_true(jit, asm, opnd!(val), target),
        Insn::IfFalse { val, target } => return gen_if_false(jit, asm, opnd!(val), target),
        Insn::SendWithoutBlock { call_info, cd, state, .. } => gen_send_without_block(jit, asm, call_info, *cd, block, function.frame_state(*state))?,
        Insn::Return { val } => return Some(gen_return(asm, opnd!(val))?),
        Insn::FixnumAdd { left, right, state } => gen_fixnum_add(asm, opnd!(left), opnd!(right), function.frame_state(*state))?,
        Insn::FixnumSub { left, right, state } => gen_fixnum_sub(asm, opnd!(left), opnd!(right), function.frame_state(*state))?,
        Insn::FixnumMult { left, right, state } => gen_fixnum_mult(asm, opnd!(left), opnd!(right), function.frame_state(*state))?,
        Insn::FixnumEq { left, right } => gen_fixnum_eq(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumNeq { left, right } => gen_fixnum_neq(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumLt { left, right } => gen_fixnum_lt(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumLe { left, right } => gen_fixnum_le(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumGt { left, right } => gen_fixnum_gt(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumGe { left, right } => gen_fixnum_ge(asm, opnd!(left), opnd!(right))?,
        Insn::Test { val } => gen_test(asm, opnd!(val))?,
        Insn::GuardType { val, guard_type, state } => gen_guard_type(asm, opnd!(val), *guard_type, function.frame_state(*state))?,
        Insn::PatchPoint(_) => return Some(()), // For now, rb_zjit_bop_redefined() panics. TODO: leave a patch point and fix rb_zjit_bop_redefined()
        _ => {
            debug!("ZJIT: gen_function: unexpected insn {:?}", insn);
            return None;
        }
    };

    // If the instruction has an output, remember it in jit.opnds
    jit.opnds[insn_id.0] = Some(out_opnd);

    Some(())
}

/// Compile an interpreter entry block to be inserted into an ISEQ
fn gen_entry_prologue(jit: &JITState, asm: &mut Assembler) {
    asm_comment!(asm, "ZJIT entry point: {}", iseq_get_location(jit.iseq, 0));
    asm.frame_setup();

    // Save the registers we'll use for CFP, EP, SP
    asm.cpush(CFP);
    asm.cpush(EC);
    asm.cpush(SP);

    // EC and CFP are pased as arguments
    asm.mov(EC, C_ARG_OPNDS[0]);
    asm.mov(CFP, C_ARG_OPNDS[1]);

    // Load the current SP from the CFP into REG_SP
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));

    // TODO: Support entry chain guard when ISEQ has_opt
}

/// Assign method arguments to basic block arguments at JIT entry
fn gen_method_params(jit: &mut JITState, asm: &mut Assembler, entry_block: &Block) {
    let num_params = entry_block.params().len();
    if num_params > 0 {
        asm_comment!(asm, "method params: {num_params}");
        for idx in 0..num_params {
            let local = gen_getlocal(jit, asm, idx);
            asm.load_into(gen_param(idx), local);
        }
    }
}

/// Get the local variable at the given index
fn gen_getlocal(jit: &mut JITState, asm: &mut Assembler, local_idx: usize) -> lir::Opnd {
    let ep_offset = local_idx_to_ep_offset(jit.iseq, local_idx);

    if jit.assume_no_ep_escape() {
        // Create a reference to the local variable using the SP register. We assume EP == BP.
        // TODO: Implement the invalidation in rb_zjit_invalidate_ep_is_bp()
        let offs = -(SIZEOF_VALUE_I32 * (ep_offset + 1));
        Opnd::mem(64, SP, offs)
    } else {
        // Get the EP of the current CFP
        let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
        let ep_reg = asm.load(ep_opnd);

        // Create a reference to the local variable using cfp->ep
        let offs = -(SIZEOF_VALUE_I32 * ep_offset);
        Opnd::mem(64, ep_reg, offs)
    }
}

/// Compile self in the current frame
fn gen_putself() -> lir::Opnd {
    Opnd::mem(VALUE_BITS, CFP, RUBY_OFFSET_CFP_SELF)
}

/// Compile a constant
fn gen_const(val: VALUE) -> lir::Opnd {
    // Just propagate the constant value and generate nothing
    Opnd::Value(val)
}

/// Compile a basic block argument
fn gen_param(idx: usize) -> lir::Opnd {
    Opnd::Param { idx }
}

/// Compile a jump to a basic block
fn gen_jump(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) -> Option<()> {
    // Set basic block arguments
    asm_comment!(asm, "basic block args: {}", branch.args.len());
    for (idx, &arg) in branch.args.iter().enumerate() {
        let param = Opnd::param(idx);
        asm.load_into(param, jit.get_opnd(arg)?);
    }

    // Jump to the basic block
    let target = jit.get_label(asm, branch.target);
    asm.jmp(target);
    Some(())
}

/// Compile a conditional branch to a basic block
fn gen_if_true(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, branch: &BranchEdge) -> Option<()> {
    // If val is zero, move on to the next instruction.
    let if_false = asm.new_label("if_false");
    asm.test(val, val);
    asm.jz(if_false.clone());

    asm_comment!(asm, "basic block args: {}", branch.args.len());
    // If val is not zero, set basic block arguments and jump to the branch target.
    // TODO: Consider generating the loads out-of-line
    let if_true = jit.get_label(asm, branch.target);
    for (idx, &arg) in branch.args.iter().enumerate() {
        let param = Opnd::param(idx);
        asm.load_into(param, jit.get_opnd(arg)?);
    }
    asm.jmp(if_true);

    asm.write_label(if_false);

    Some(())
}

/// Compile a conditional branch to a basic block
fn gen_if_false(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, branch: &BranchEdge) -> Option<()> {
    // If val is not zero, move on to the next instruction.
    let if_true = asm.new_label("if_true");
    asm.test(val, val);
    asm.jnz(if_true.clone());

    asm_comment!(asm, "basic block args: {}", branch.args.len());
    // If val is zero, set basic block arguments and jump to the branch target.
    // TODO: Consider generating the loads out-of-line
    let if_false = jit.get_label(asm, branch.target);
    for (idx, &arg) in branch.args.iter().enumerate() {
        let param = Opnd::param(idx);
        asm.load_into(param, jit.get_opnd(arg)?);
    }
    asm.jmp(if_false);

    asm.write_label(if_true);

    Some(())
}

/// Compile a dynamic dispatch without block
fn gen_send_without_block(
    jit: &mut JITState,
    asm: &mut Assembler,
    call_info: &CallInfo,
    cd: *const rb_call_data,
    block: &Block,
    state: &FrameState,
) -> Option<lir::Opnd> {
    // Spill the virtual stack onto the stack. They need to be marked by GC and may be caller-saved registers.
    // TODO: Avoid spilling operands that have been spilled before.
    for (idx, &insn_id) in state.stack().enumerate() {
        // Currently, we don't move the SP register. So it's equal to the base pointer.
        let stack_opnd = Opnd::mem(64, SP, idx as i32  * SIZEOF_VALUE_I32);
        asm.mov(stack_opnd, jit.get_opnd(insn_id)?);
    }

    // Save PC and SP
    gen_save_pc(asm, state);
    gen_save_sp(asm, state);

    // Preserve basic block arguments
    let params = caller_saved_params(block);
    for &param in params.iter() {
        asm.cpush(param);
    }

    asm_comment!(asm, "call #{} with dynamic dispatch", call_info.method_name);
    unsafe extern "C" {
        fn rb_vm_opt_send_without_block(ec: EcPtr, cfp: CfpPtr, cd: VALUE) -> VALUE;
    }
    let ret = asm.ccall(
        rb_vm_opt_send_without_block as *const u8,
        vec![EC, CFP, (cd as usize).into()],
    );

    // Restore basic block arguments
    for &param in params.iter().rev() {
        asm.cpop_into(param);
    }

    Some(ret)
}

/// Compile code that exits from JIT code with a return value
fn gen_return(asm: &mut Assembler, val: lir::Opnd) -> Option<()> {
    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm_comment!(asm, "pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Set a return value to the register. We do this before popping SP, EC,
    // and CFP registers because ret_val may depend on them.
    asm.mov(C_RET_OPND, val);

    asm_comment!(asm, "exit from leave");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);
    asm.frame_teardown();
    asm.cret(C_RET_OPND);

    Some(())
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Add left + right and test for overflow
    let left_untag = asm.sub(left, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right);
    asm.jo(Target::SideExit(state.clone()));

    Some(out_val)
}

/// Compile Fixnum - Fixnum
fn gen_fixnum_sub(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Subtract left - right and test for overflow
    let val_untag = asm.sub(left, right);
    asm.jo(Target::SideExit(state.clone()));
    let out_val = asm.add(val_untag, Opnd::Imm(1));

    Some(out_val)
}

/// Compile Fixnum * Fixnum
fn gen_fixnum_mult(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Do some bitwise gymnastics to handle tag bits
    // x * y is translated to (x >> 1) * (y - 1) + 1
    let left_untag = asm.rshift(left, Opnd::UImm(1));
    let right_untag = asm.sub(right, Opnd::UImm(1));
    let out_val = asm.mul(left_untag, right_untag);

    // Test for overflow
    asm.jo_mul(Target::SideExit(state.clone()));
    let out_val = asm.add(out_val, Opnd::UImm(1));

    Some(out_val)
}

/// Compile Fixnum == Fixnum
fn gen_fixnum_eq(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_e(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum != Fixnum
fn gen_fixnum_neq(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_ne(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum < Fixnum
fn gen_fixnum_lt(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_l(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum <= Fixnum
fn gen_fixnum_le(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_le(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum > Fixnum
fn gen_fixnum_gt(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_g(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum >= Fixnum
fn gen_fixnum_ge(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_ge(Qtrue.into(), Qfalse.into()))
}

/// Evaluate if a value is truthy
/// Produces a CBool type (0 or 1)
/// In Ruby, only nil and false are falsy
/// Everything else evaluates to true
fn gen_test(asm: &mut Assembler, val: lir::Opnd) -> Option<lir::Opnd> {
    // Test if any bit (outside of the Qnil bit) is on
    // See RB_TEST(), include/ruby/internal/special_consts.h
    asm.test(val, Opnd::Imm(!Qnil.as_i64()));
    Some(asm.csel_e(0.into(), 1.into()))
}

/// Compile a type check with a side exit
fn gen_guard_type(asm: &mut Assembler, val: lir::Opnd, guard_type: Type, state: &FrameState) -> Option<lir::Opnd> {
    if guard_type.is_subtype(Fixnum) {
        // Check if opnd is Fixnum
        asm.test(val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(Target::SideExit(state.clone()));
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    Some(val)
}

/// Save the incremented PC on the CFP.
/// This is necessary when callees can raise or allocate.
fn gen_save_pc(asm: &mut Assembler, state: &FrameState) {
    let opcode: usize = state.get_opcode().try_into().unwrap();
    let next_pc: *const VALUE = unsafe { state.pc.offset(insn_len(opcode) as isize) };

    asm_comment!(asm, "save PC to CFP");
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(next_pc as *const u8));
}

/// Save the current SP on the CFP
fn gen_save_sp(asm: &mut Assembler, state: &FrameState) {
    // Update cfp->sp which will be read by the interpreter. We also have the SP register in JIT
    // code, and ZJIT's codegen currently assumes the SP register doesn't move, e.g. gen_param().
    // So we don't update the SP register here. We could update the SP register to avoid using
    // an extra register for asm.lea(), but you'll need to manage the SP offset like YJIT does.
    asm_comment!(asm, "save SP to CFP: {}", state.stack_size());
    let sp_addr = asm.lea(Opnd::mem(64, SP, state.stack_size() as i32 * SIZEOF_VALUE_I32));
    let cfp_sp = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
    asm.mov(cfp_sp, sp_addr);
}

/// Return a list of basic block arguments to be preserved during a C call.
/// They use registers that can be used for C calls.
fn caller_saved_params(block: &Block) -> Vec<Opnd> {
    let mut params: Vec<_> = (0..block.params().len()).map(|idx| Opnd::Param { idx }).collect();
    // On x86_64, maintain 16-byte stack alignment
    if cfg!(target_arch = "x86_64") && params.len() % 2 == 1 {
        params.push(params.last().unwrap().clone());
    }
    params
}

/// Inverse of ep_offset_to_local_idx(). See ep_offset_to_local_idx() for details.
fn local_idx_to_ep_offset(iseq: IseqPtr, local_idx: usize) -> i32 {
    let local_table_size: i32 = unsafe { get_iseq_body_local_table_size(iseq) }
        .try_into()
        .unwrap();
    local_table_size - local_idx as i32 - 1 + VM_ENV_DATA_SIZE as i32
}
