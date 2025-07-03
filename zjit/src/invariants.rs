use std::collections::{HashMap, HashSet};

use crate::{cruby::{ruby_basic_operators, IseqPtr, RedefinitionFlag}, state::{zjit_enabled_p, ZJITState}, virtualmem::CodePtr};

/// Used to track all of the various block references that contain assumptions
/// about the state of the virtual machine.
#[derive(Default)]
pub struct Invariants {
    /// Set of ISEQs that are known to escape EP
    ep_escape_iseqs: HashSet<IseqPtr>,

    /// Set of ISEQs whose JIT code assumes that it doesn't escape EP
    no_ep_escape_iseqs: HashSet<IseqPtr>,

    /// Map from a class and its associated basic operator to a set of patch points
    bop_patch_points: HashMap<(RedefinitionFlag, ruby_basic_operators), HashSet<CodePtr>>,
}

/// Called when a basic operator is redefined. Note that all the blocks assuming
/// the stability of different operators are invalidated together and we don't
/// do fine-grained tracking.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_bop_redefined(klass: RedefinitionFlag, bop: ruby_basic_operators) {
    // If ZJIT isn't enabled, do nothing
    if !zjit_enabled_p() {
        return;
    }

    let invariants = ZJITState::get_invariants();
    if let Some(code_ptrs) = invariants.bop_patch_points.get(&(klass, bop)) {
        // Invalidate all patch points for this BOP
        for &ptr in code_ptrs {
            unimplemented!("Invalidation on BOP redefinition is not implemented yet: {ptr:?}");
        }
    }
}

/// Invalidate blocks for a given ISEQ that assumes environment pointer is
/// equal to base pointer.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_invalidate_ep_is_bp(iseq: IseqPtr) {
    // Skip tracking EP escapes on boot. We don't need to invalidate anything during boot.
    if !ZJITState::has_instance() {
        return;
    }

    // Remember that this ISEQ may escape EP
    let invariants = ZJITState::get_invariants();
    invariants.ep_escape_iseqs.insert(iseq);

    // If the ISEQ has been compiled assuming it doesn't escape EP, invalidate the JIT code.
    // Note: Nobody calls track_no_ep_escape_assumption() for now, so this is always false.
    // TODO: Add a PatchPoint that assumes EP == BP in HIR and invalidate it here.
    if invariants.no_ep_escape_iseqs.contains(&iseq) {
        unimplemented!("Invalidation on EP escape is not implemented yet");
    }
}

/// Track that JIT code for a ISEQ will assume that base pointer is equal to environment pointer.
pub fn track_no_ep_escape_assumption(iseq: IseqPtr) {
    let invariants = ZJITState::get_invariants();
    invariants.no_ep_escape_iseqs.insert(iseq);
}

/// Returns true if a given ISEQ has previously escaped environment pointer.
pub fn iseq_escapes_ep(iseq: IseqPtr) -> bool {
    ZJITState::get_invariants().ep_escape_iseqs.contains(&iseq)
}

/// Track a patch point for a basic operator in a given class.
pub fn track_bop_assumption(klass: RedefinitionFlag, bop: ruby_basic_operators, code_ptr: CodePtr) {
    let invariants = ZJITState::get_invariants();
    invariants.bop_patch_points.entry((klass, bop)).or_default().insert(code_ptr);
}
