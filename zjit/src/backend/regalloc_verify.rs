//! Abstract interpretation of post-allocation LIR.
//!
//! Based on Chris Fallin's writeup of the Cranelift regalloc checker:
//! <https://cfallin.org/blog/2021/03/15/cranelift-isel-3/>
//!
//! # How it works
//!
//! This code basically follows the blog post, but we perform abstract
//! interpretation over LIR after registers have been allocated and all
//! moves have been inserted (so like moves between blocks or spills to the
//! stack).
//!
//! We combine block parameters via union find so that we can propagate values
//! between edges.
//!
//! Values in the abstract interpretation move monotonically on a lattice
//! where the top of the lattice is "unknown", the middle is "some virtual
//! register", and the bottom is "conflicted". "unknown" meets with anything
//! to produce anything. "vreg" meets with "vreg" to produce conflicted iff
//! they are different vregs (otherwise vreg).  "conflicted" meets with
//! anything to produce "conflicted".
//!
//! Each location (physical register, allocator spill slot, or incoming stack
//! argument slot) is represented by a lattice, and the lattice moves based on
//! what vregs flowed through it.
//!
//! Entry slots start with whatever the C calling convention gives them, and
//! all other slots start as "unknown".
//!
//! Each block has a list of lattice elements (`states`), that is equal to
//! the number of locations.  When we walk a block, we step through each
//! instruction processing the effects of the instruction on the list of
//! states.
//!
//! When we transfer between blocks, we propagate values along the edge to
//! the successor block via "meets" on the lattice.  Blocks whose state changes
//! get re-queued for work.
//!
//! Once block state stops changing, we quit iterating and check.
//! The check does one more pass, but this time when a value is read we'll
//! throw an error if it reads anything but the expected value (whether that
//! is Conflicted or just some other value).

use std::collections::HashMap;

use crate::backend::lir::*;
use crate::cast::IntoUsize;
use crate::hir::UnionFind;
use crate::cruby::SIZEOF_VALUE_I32;

/// Number of physical registers.  This doesn't need to be exactly what the
/// architecture targets.  arm64 has 32 regs and x86_64 uses 15, so we'll just
/// set this to 32 to cover both platforms.
const NUM_PHYS_REGS: usize = 32;

type ClassId = usize;

/// A location's symbolic contents.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Sym {
    Unknown,
    Val(ClassId),
    Conflicted,
}

impl Sym {
    fn meet(a: Sym, b: Sym) -> Sym {
        match (a, b) {
            (Sym::Unknown, other) | (other, Sym::Unknown) => other,
            (Sym::Val(x), Sym::Val(y)) if x == y => Sym::Val(x),
            _ => Sym::Conflicted,
        }
    }

    fn describe(self) -> String {
        match self {
            Sym::Unknown => "nothing".to_string(),
            Sym::Conflicted => "two different values".to_string(),
            Sym::Val(class) => format!("the value of v{class}"),
        }
    }
}

/// Union-find over value classes.  We need this for unifying block params.
pub struct Congruence {
    classes: UnionFind<ClassId>,
    num_vregs: usize,

    /// One past the highest class
    next_class: ClassId,

    /// Synthetic class for each immediate operand that appears as an edge
    immediates: HashMap<Opnd, ClassId>,
}

impl Congruence {
    /// Build the congruence relation from the block-parameter edges.
    pub fn build(asm: &Assembler) -> Self {
        let mut cg = Congruence {
            classes: UnionFind::new(),
            num_vregs: asm.num_vregs,
            next_class: asm.num_vregs,
            immediates: HashMap::new(),
        };

        for block in asm.basic_blocks.iter() {
            for insn in block.insns.iter() {
                let Some(Target::Block(edge)) = insn.target() else { continue };
                let params = &asm.basic_blocks[edge.target.0].parameters;
                for (arg, param) in edge.args.iter().zip(params.iter()) {
                    let Opnd::VReg { idx: param_idx, .. } = param else { continue };

                    // The parameter goes second so the class ends up named after
                    // it rather than after whichever argument arrived first.
                    let param_class = param_idx.to_usize();
                    let arg_class = match *arg {
                        Opnd::VReg { idx, .. } => idx.to_usize(),
                        Opnd::Value(_) | Opnd::UImm(_) | Opnd::Imm(_) => cg.intern_immediate(*arg),
                        // Anything else is not a value we can follow, so it
                        // contributes nothing to the relation.
                        _ => continue,
                    };
                    cg.classes.make_equal_to(arg_class, param_class);
                }
            }
        }

        cg.compress();
        cg
    }

    /// Find or create a class for an immediate edge argument
    fn intern_immediate(&mut self, opnd: Opnd) -> ClassId {
        if let Some(&class) = self.immediates.get(&opnd) {
            return class;
        }
        // `UnionFind` treats an element it has never seen as its own
        // representative, so a fresh class needs no initialization.
        let class = self.next_class;
        self.next_class += 1;
        self.immediates.insert(opnd, class);
        class
    }

    /// The class an immediate belongs to, if it ever fed a block parameter. One
    /// that did not is not something any read depends on, so it stays `Unknown`
    /// rather than getting a class of its own.
    fn immediate_class(&self, opnd: Opnd) -> Option<ClassId> {
        self.immediates.get(&opnd).map(|&class| self.classes.find_const(class))
    }

    /// Collapse every chain, so `class_of` stops walking one.
    fn compress(&mut self) {
        for class in 0..self.next_class {
            self.classes.find(class);
        }
    }

    fn class_of(&self, vreg: VRegId) -> ClassId {
        debug_assert!(vreg.to_usize() < self.num_vregs, "VReg out of range: {vreg}");
        self.classes.find_const(vreg.to_usize())
    }
}

/// A read failure found by the verifier
pub struct Failure {
    pub block: BlockId,
    pub insn: Option<String>,
    pub message: String,
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}: ", self.block)?;
        if let Some(insn) = &self.insn {
            write!(f, "{insn}: ")?;
        }
        write!(f, "{}", self.message)
    }
}

/// What one instruction does to the abstract state.
enum Effect {
    /// Check `reads`, then write `out`. A `VReg` out *defines* its value class;
    /// any other out becomes `Unknown`. `clobbers_volatile` is set for calls,
    /// which destroy every register the JIT ABI does not preserve.
    Op { reads: Vec<VRegId>, out: Option<Opnd>, clobbers_volatile: bool },

    /// Check `reads`, then copy whatever `src` holds into `dst`.
    Move { reads: Vec<VRegId>, dst: Opnd, src: Opnd },

    /// Push a 16-byte pair onto the native stack. `hi` goes to the higher
    /// address and `lo` to the lower; `None` for `hi` reserves the slot without
    /// writing it.
    Push { hi: Option<Opnd>, lo: Opnd, reads: Vec<VRegId> },

    /// Pop a 16-byte pair.
    Pop { lo: Opnd, hi: Opnd },

    /// The native stack pointer moved by a whole number of slots.
    DropSlots(usize),

    /// The native stack moved in a way we do not model. CPUSH/CPOP differ
    /// depending on the back end.  `clobber` is the thing we'll make `Unknown`
    StackReset { clobber: Option<Opnd> },

    /// Nothing observable.
    Nop,
}

struct Checker<'a> {
    asm: &'a Assembler,
    intervals: &'a [Interval],
    regs: &'a RegPool,
    congruence: &'a Congruence,

    /// `blocks * width` wide list. The abstract state on entry to each block.
    states: Vec<Sym>,

    /// Number of locations in one state.
    width: usize,

    /// First location index of the allocator spill slots, and how many there are.
    slots_base: usize,
    num_slots: usize,

    /// First location index of the incoming stack-argument slots, and the
    /// `NATIVE_BASE_PTR` displacement each one lives at.
    incoming_base: usize,
    incoming_disps: Vec<i32>,

    /// Whether a block has ever been queued. Doubles as reachability once the
    /// fixpoint has settled: a block that was never queued has a meaningless
    /// entry state and must not be blamed for anything.
    queued: Vec<bool>,

    /// Whether reads are being checked. Off while the fixpoint is still moving.
    checking: bool,

    failures: Vec<Failure>,
}

/// Verify the register allocator's assignment against the values the LIR says
/// each instruction reads. Returns all read errors
pub fn check_allocation(
    asm: &Assembler,
    congruence: &Congruence,
    intervals: &[Interval],
    regs: &RegPool,
) -> Result<(), Vec<Failure>> {
    let max_params = asm.basic_blocks.iter()
        .filter(|block| block.is_entry)
        .map(|block| block.parameters.len())
        .max()
        .unwrap_or(0);

    let incoming_disps: Vec<i32> = (0..max_params)
        .filter_map(|i| match c_arg_location(i) {
            CArgLocation::StackSlot(slot) => {
                Some(Assembler::frame_size() + slot as i32 * SIZEOF_VALUE_I32)
            }
            CArgLocation::Reg(_) => None,
        })
        .collect();

    let num_slots = asm.stack_state.num_spill_slots;
    let slots_base = NUM_PHYS_REGS;
    let incoming_base = slots_base + num_slots;
    let width = incoming_base + incoming_disps.len();
    let num_blocks = asm.basic_blocks.len();

    let mut checker = Checker {
        asm,
        intervals,
        regs,
        congruence,
        states: vec![Sym::Unknown; num_blocks * width],
        width,
        slots_base,
        num_slots,
        incoming_base,
        incoming_disps,
        queued: vec![false; num_blocks],
        checking: false,
        failures: Vec::new(),
    };

    checker.run();

    if checker.failures.is_empty() {
        Ok(())
    } else {
        Err(checker.failures)
    }
}

impl Checker<'_> {
    fn run(&mut self) {
        let mut work: Vec<BlockId> = Vec::new();

        // Seed every entry block from the calling convention: on entry,
        // parameter `i` lives wherever the C ABI put it.
        let entries: Vec<BlockId> = self.asm.basic_blocks.iter()
            .filter(|block| block.is_entry)
            .map(|block| block.id)
            .collect();

        for block_id in entries {
            let params = self.asm.basic_blocks[block_id.0].parameters.clone();
            for (i, param) in params.iter().enumerate() {
                let Opnd::VReg { idx, .. } = param else { continue };
                let sym = Sym::Val(self.congruence.class_of(*idx));
                let home = match c_arg_location(i) {
                    CArgLocation::Reg(reg) => reg,
                    CArgLocation::StackSlot(slot) => Opnd::mem(
                        64,
                        NATIVE_BASE_PTR,
                        Assembler::frame_size() + slot as i32 * SIZEOF_VALUE_I32,
                    ),
                };
                if let Some(loc) = self.loc_of_opnd(home) {
                    self.states[block_id.0 * self.width + loc] = sym;
                }
            }
            if !self.queued[block_id.0] {
                self.queued[block_id.0] = true;
                work.push(block_id);
            }
        }

        // Fixpoint: walk a block from its entry state, meet its exit state into
        // each successor, re-queue whatever moved.
        while let Some(block_id) = work.pop() {
            self.walk(block_id, Some(&mut work));
        }

        // Entry states are final now, so walk all blocks one last time
        // looking for errors
        self.checking = true;
        let reached: Vec<BlockId> = self.asm.basic_blocks.iter()
            .map(|block| block.id)
            .filter(|id| self.queued[id.0])
            .collect();
        for block_id in reached {
            self.walk(block_id, None);
        }
    }

    /// Walk one block
    fn walk(&mut self, block_id: BlockId, work: Option<&mut Vec<BlockId>>) {
        let base = block_id.0 * self.width;
        let mut state: Vec<Sym> = self.states[base..base + self.width].to_vec();

        // The symbolic native stack
        let mut stack: Vec<Sym> = Vec::new();

        let insns = &self.asm.basic_blocks[block_id.0].insns;
        for i in 0..insns.len() {
            // Re-borrow each time: `step` needs `&mut self` for `failures`.
            let insn = self.asm.basic_blocks[block_id.0].insns[i].clone();
            self.step(block_id, &insn, &mut state, &mut stack);
        }

        let Some(work) = work else { return };
        let succs: Vec<BlockId> = self.asm.basic_blocks[block_id.0].successors().collect();
        for succ in succs {
            // Propagate state to successors
            self.propagate(succ, &state, work);
        }
    }

    /// Meet `state` into `target`'s entry state. If the state changes, queue
    /// up the block (mark it true in queued, and push it on the worklist)
    fn propagate(&mut self, target: BlockId, state: &[Sym], work: &mut Vec<BlockId>) {
        let base = target.0 * self.width;
        // A block reached for the first time is walked even if the meet
        // establishes nothing, so that its successors get visited.
        let mut moved = !self.queued[target.0];
        for i in 0..self.width {
            let merged = Sym::meet(self.states[base + i], state[i]);
            if merged != self.states[base + i] {
                self.states[base + i] = merged;
                moved = true;
            }
        }
        if moved {
            self.queued[target.0] = true;
            work.push(target);
        }
    }

    /// Step through each insn in a block processing the effect.
    fn step(&mut self, block_id: BlockId, insn: &Insn, state: &mut [Sym], stack: &mut Vec<Sym>) {
        match self.effect_of(insn) {
            Effect::Nop => {}

            Effect::Op { reads, out, clobbers_volatile } => {
                // Every read before any write: an instruction whose result lands
                // in one of its own operand registers still read the operand.
                for vreg in reads {
                    self.check_read(block_id, insn, vreg, state);
                }
                if clobbers_volatile {
                    self.clobber_volatile(state);
                }
                if let Some(out) = out {
                    self.write(out, self.definition_of(out), state);
                }
            }

            Effect::Move { reads, dst, src } => {
                for vreg in reads {
                    self.check_read(block_id, insn, vreg, state);
                }
                // A VReg destination is a definition; a physical one is a
                // transfer of whatever the source happens to hold.
                let value = match dst {
                    Opnd::VReg { .. } => self.definition_of(dst),
                    _ => self.content_of(src, state),
                };
                self.write(dst, value, state);
            }

            Effect::Push { hi, lo, reads } => {
                for vreg in reads {
                    self.check_read(block_id, insn, vreg, state);
                }
                // `hi` goes to the higher address and `lo` to the lower, so `lo`
                // ends up on top of the model.
                stack.push(hi.map_or(Sym::Unknown, |opnd| self.content_of(opnd, state)));
                stack.push(self.content_of(lo, state));
            }

            Effect::Pop { lo, hi } => {
                // A pop with nothing modelled beneath it is a value this
                // function did not push -- a trampoline collecting what its
                // caller left, say. Yield Unknown rather than complain.
                let lo_sym = stack.pop().unwrap_or(Sym::Unknown);
                let hi_sym = stack.pop().unwrap_or(Sym::Unknown);
                self.write(lo, lo_sym, state);
                self.write(hi, hi_sym, state);
            }

            Effect::DropSlots(n) => {
                let keep = stack.len().saturating_sub(n);
                stack.truncate(keep);
            }

            Effect::StackReset { clobber } => {
                stack.clear();
                if let Some(dst) = clobber {
                    self.write(dst, Sym::Unknown, state);
                }
            }
        }
    }

    /// Classify an instruction.
    ///
    /// This function converts an insn in to a "general effect" that we can
    /// use for abstract interpretation.
    fn effect_of(&self, insn: &Insn) -> Effect {
        // Anything that moves the native stack pointer has to come first, so a
        // general Mov/Add arm below cannot swallow it.
        if let Some(out) = stack_ptr_write(insn) {
            return out;
        }

        match insn {
            // A call destroys every register the JIT ABI does not preserve. Its
            // own `out` is C_RET by this point (handle_caller_saved_regs
            // rewrote it), and the result gets named by the `Mov` that follows.
            Insn::CCall { .. } => Effect::Op {
                reads: Vec::new(),
                out: None,
                clobbers_volatile: true,
            },

            Insn::Mov { dest, src } |
            Insn::LoadInto { dest, opnd: src } |
            Insn::Store { dest, src } => {
                let mut reads = Vec::new();
                push_reads(*src, &mut reads);
                push_membase_reads(*dest, &mut reads);
                Effect::Move { reads, dst: *dest, src: *src }
            }

            Insn::CPopPairInto(lo, hi) => Effect::Pop { lo: *lo, hi: *hi },
            Insn::CPushPair(hi, lo) => {
                let mut reads = Vec::new();
                if let Some(hi) = hi { push_reads(*hi, &mut reads); }
                push_reads(*lo, &mut reads);
                Effect::Push { hi: *hi, lo: *lo, reads }
            }

            // A bare CPush/CPop moves the native SP by an amount that differs
            // between backends, and the trampolines pair them across function
            // boundaries. Forget the model instead of guessing at it.
            Insn::CPush(_) => Effect::StackReset { clobber: None },
            Insn::CPop { out } => Effect::StackReset { clobber: Some(*out) },
            Insn::CPopInto(dest) => Effect::StackReset { clobber: Some(*dest) },

            // Everything else: the operands are reads and `out_opnd` is the write.
            _ => {
                let mut reads = Vec::new();
                insn.for_each_operand(|opnd| push_reads(opnd, &mut reads));
                let out = insn.out_opnd().copied();
                // An out operand is a write, so drop it from the reads that
                // `for_each_operand` may also have collected. A VReg used as its
                // memory base really is read, and stays.
                if let Some(Opnd::VReg { idx, .. }) = out {
                    reads.retain(|&read| read != idx);
                }
                Effect::Op { reads, out, clobbers_volatile: false }
            }
        }
    }

    /// Check that `vreg`'s home holds `vreg`'s value.
    fn check_read(&mut self, block_id: BlockId, insn: &Insn, vreg: VRegId, state: &[Sym]) {
        if !self.checking { return; }
        let Some(loc) = self.loc_of_vreg(vreg) else { return };

        let want = Sym::Val(self.congruence.class_of(vreg));
        let got = state[loc];
        if got == want { return; }

        let home = self.home_of_vreg(vreg)
            .map(|opnd| format!("{opnd}"))
            .unwrap_or_else(|| "?".to_string());
        self.fail(block_id, Some(insn), format!(
            "reads {vreg} out of {home}, which should hold {} but holds {}",
            want.describe(),
            got.describe(),
        ));
    }

    /// The symbol a VReg output establishes.
    fn definition_of(&self, opnd: Opnd) -> Sym {
        match opnd {
            Opnd::VReg { idx, .. } => Sym::Val(self.congruence.class_of(idx)),
            _ => Sym::Unknown,
        }
    }

    /// What a source operand supplies: whatever its location holds, the class of
    /// an immediate that feeds a block parameter, or `Unknown`.
    fn content_of(&self, opnd: Opnd, state: &[Sym]) -> Sym {
        match opnd {
            Opnd::Value(_) | Opnd::UImm(_) | Opnd::Imm(_) => {
                self.congruence.immediate_class(opnd).map_or(Sym::Unknown, Sym::Val)
            }
            _ => self.loc_of_opnd(opnd).map_or(Sym::Unknown, |loc| state[loc]),
        }
    }

    /// Write `sym` to `opnd`'s location, if we track it.
    fn write(&self, opnd: Opnd, sym: Sym, state: &mut [Sym]) {
        if let Some(loc) = self.loc_of_opnd(opnd) {
            state[loc] = sym;
        }
    }

    /// Set every register a C call may destroy to `Unknown`. A value that
    /// survives a call does so through the explicit save/restore run,
    /// so it comes back from the symbolic stack rather than from here.
    fn clobber_volatile(&self, state: &mut [Sym]) {
        for reg_no in 0..NUM_PHYS_REGS {
            if !is_call_preserved(reg_no as u8) {
                state[reg_no] = Sym::Unknown;
            }
        }
    }

    /// The physical location a VReg was assigned, as an `Opnd`.
    fn home_of_vreg(&self, vreg: VRegId) -> Option<Opnd> {
        // An unassigned VReg is one `rewrite_instructions` would panic on, so
        // there is nothing useful for the verifier to say about it.
        self.intervals[vreg].assigned.get()?;
        let opnd = Opnd::VReg { idx: vreg, num_bits: 64 };
        Some(Assembler::rewritten_opnd(opnd, self.intervals, self.regs))
    }

    fn loc_of_vreg(&self, vreg: VRegId) -> Option<usize> {
        self.loc_of_opnd(self.home_of_vreg(vreg)?)
    }

    /// Map an operand to a state index, or `None` if we do not track it.
    fn loc_of_opnd(&self, opnd: Opnd) -> Option<usize> {
        match opnd {
            Opnd::Reg(reg) => {
                debug_assert!((reg.reg_no as usize) < NUM_PHYS_REGS, "reg_no out of range: {reg:?}");
                Some(reg.reg_no as usize)
            }
            Opnd::VReg { idx, .. } => self.loc_of_vreg(idx),
            Opnd::Mem(Mem { base: MemBase::Stack { stack_idx, .. }, disp: 0, .. }) => {
                let slot = stack_idx.to_usize();
                (slot < self.num_slots).then_some(self.slots_base + slot)
            }
            // A pointer held in a VReg or in a stack slot addresses memory we do
            // not model. The base VReg is still checked as a read.
            Opnd::Mem(Mem { base: MemBase::VReg(_) | MemBase::StackIndirect { .. }, .. }) => None,
            Opnd::Mem(Mem { base: MemBase::Reg(reg_no), disp, .. })
                if Some(reg_no) == reg_no_of(NATIVE_BASE_PTR) => {
                self.incoming_disps.iter()
                    .position(|&d| d == disp)
                    .map(|i| self.incoming_base + i)
            }
            _ => None,
        }
    }

    fn fail(&mut self, block: BlockId, insn: Option<&Insn>, message: String) {
        self.failures.push(Failure {
            block,
            insn: insn.map(|insn| format!("{insn:?}")),
            message,
        });
    }
}

/// Collect the VRegs an operand reads, including a VReg used as a memory base.
fn push_reads(opnd: Opnd, out: &mut Vec<VRegId>) {
    out.extend(opnd.vreg_ids());
}

/// Collect only the VRegs a *destination* operand reads: a bare VReg destination
/// is a pure write, but `[vreg + disp]` reads the base.
fn push_membase_reads(opnd: Opnd, out: &mut Vec<VRegId>) {
    if matches!(opnd, Opnd::Mem(_)) {
        out.extend(opnd.vreg_ids());
    }
}

fn reg_no_of(opnd: Opnd) -> Option<u8> {
    match opnd {
        Opnd::Reg(reg) => Some(reg.reg_no),
        _ => None,
    }
}

/// Whether a register survives a C call. These are the registers the JIT's own
/// ABI keeps live across a ccall; everything else has to be saved explicitly by
/// `handle_caller_saved_regs`, which is exactly what we want to verify.
fn is_call_preserved(reg_no: u8) -> bool {
    JIT_PRESERVED_REGS.iter()
        .chain([&NATIVE_BASE_PTR, &NATIVE_STACK_PTR])
        .filter_map(|&opnd| reg_no_of(opnd))
        .any(|preserved| preserved == reg_no)
}

/// Classify an instruction that moves the native stack pointer, so the symbolic
/// stack model stays in step with it.
fn stack_ptr_write(insn: &Insn) -> Option<Effect> {
    match insn {
        // FrameSetup reserves the whole frame and FrameTeardown releases it.
        Insn::FrameSetup { .. } | Insn::FrameTeardown { .. } => {
            Some(Effect::StackReset { clobber: None })
        }

        // The outgoing-argument-area teardown after a call with more arguments
        // than there are argument registers.
        Insn::Add { left, right, out }
            if *left == NATIVE_STACK_PTR && *out == NATIVE_STACK_PTR =>
        {
            let bytes = match *right {
                Opnd::Imm(bytes) if bytes >= 0 => bytes as u64,
                Opnd::UImm(bytes) => bytes,
                _ => return Some(Effect::StackReset { clobber: None }),
            };
            let slot_bytes = SIZEOF_VALUE_I32 as u64;
            if bytes % slot_bytes == 0 {
                Some(Effect::DropSlots((bytes / slot_bytes) as usize))
            } else {
                Some(Effect::StackReset { clobber: None })
            }
        }

        // Any other write to the native stack pointer.
        Insn::Add { out, .. } | Insn::Sub { out, .. } if *out == NATIVE_STACK_PTR => {
            Some(Effect::StackReset { clobber: None })
        }
        Insn::Mov { dest, .. } | Insn::LoadInto { dest, .. } if *dest == NATIVE_STACK_PTR => {
            Some(Effect::StackReset { clobber: None })
        }

        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hir;

    /// A single entry block:
    ///
    ///     v0, v1 = params
    ///     v2 = add v0, v1
    ///     v3 = add v2, v0
    ///     cret v3
    ///
    /// `v0` is live across `v2`'s definition, so handing `v2` the register `v0`
    /// lives in is an interference bug.
    fn allocate() -> (Assembler, Vec<Interval>, RegPool, VRegId, VRegId) {
        let mut asm = Assembler::new();
        let v0 = asm.new_vreg(64);
        let v1 = asm.new_vreg(64);
        let b0 = asm.new_block(hir::BlockId(0), true, 0);
        let label = asm.new_label("bb0");
        asm.write_label(label);
        asm.basic_blocks[b0.0].add_parameter(v0);
        asm.basic_blocks[b0.0].add_parameter(v1);
        let v2 = asm.add(v0, v1);
        let v3 = asm.add(v2, v0);
        asm.cret(v3);

        let live_in = asm.analyze_liveness();
        asm.number_instructions(16);
        let mut intervals = asm.build_intervals(live_in);
        let mut regs = RegPool::with_allocatable(crate::backend::current::ALLOC_REGS.to_vec(), 5);
        asm.preferred_register_assignments(&mut intervals, &mut regs);
        asm.linear_scan(&intervals, &regs);
        (asm, intervals, regs, v0.vreg_idx(), v2.vreg_idx())
    }

    fn interval_of(intervals: &[Interval], vreg: VRegId) -> &Interval {
        intervals.iter().find(|interval| interval.vreg_id == vreg).unwrap()
    }

    #[test]
    fn accepts_a_correct_allocation() {
        let (mut asm, intervals, regs, ..) = allocate();
        // resolve_ssa runs the checker itself in a debug build.
        asm.resolve_ssa(&intervals, &regs);
    }

    #[test]
    #[should_panic(expected = "register allocation is not correct")]
    fn rejects_two_live_vregs_sharing_a_register() {
        let (mut asm, intervals, regs, v0, v2) = allocate();
        let home = interval_of(&intervals, v0).assigned.get().unwrap();
        interval_of(&intervals, v2).assigned.set(Some(home));
        asm.resolve_ssa(&intervals, &regs);
    }
}
