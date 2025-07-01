use std::collections::HashSet;

use crate::{cruby::{ruby_basic_operators, IseqPtr, RedefinitionFlag}, state::ZJITState, state::zjit_enabled_p};

/// Used to track all of the various block references that contain assumptions
/// about the state of the virtual machine.
#[derive(Default)]
pub struct Invariants {
    /// Set of ISEQs that are known to escape EP
    ep_escape_iseqs: HashSet<IseqPtr>,

    /// Set of ISEQs whose JIT code assumes that it doesn't escape EP
    no_ep_escape_iseqs: HashSet<IseqPtr>,
}

/// Called when a basic operator is redefined. Note that all the blocks assuming
/// the stability of different operators are invalidated together and we don't
/// do fine-grained tracking.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_bop_redefined(_klass: RedefinitionFlag, _bop: ruby_basic_operators) {
    // If ZJIT isn't enabled, do nothing
    if !zjit_enabled_p() {
        return;
    }

    unimplemented!("Invalidation on BOP redefinition is not implemented yet");
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
