use std::{collections::{HashMap, HashSet}, mem};

use crate::{backend::lir::{asm_comment, Assembler}, cruby::{rb_callable_method_entry_t, ruby_basic_operators, src_loc, with_vm_lock, IseqPtr, RedefinitionFlag, ID}, hir::Invariant, options::debug, state::{zjit_enabled_p, ZJITState}, virtualmem::CodePtr};

#[derive(Debug, Eq, Hash, PartialEq)]
struct Jump {
    from: CodePtr,
    to: CodePtr,
}

/// Used to track all of the various block references that contain assumptions
/// about the state of the virtual machine.
#[derive(Default)]
pub struct Invariants {
    /// Set of ISEQs that are known to escape EP
    ep_escape_iseqs: HashSet<IseqPtr>,

    /// Set of ISEQs whose JIT code assumes that it doesn't escape EP
    no_ep_escape_iseqs: HashSet<IseqPtr>,

    /// Map from a class and its associated basic operator to a set of patch points
    bop_patch_points: HashMap<(RedefinitionFlag, ruby_basic_operators), HashSet<Jump>>,

    /// Map from CME to patch points that assume the method hasn't been redefined
    cme_patch_points: HashMap<*const rb_callable_method_entry_t, HashSet<Jump>>,

    /// Map from constant ID to patch points that assume the constant hasn't been redefined
    constant_state_patch_points: HashMap<ID, HashSet<Jump>>,

    /// Set of patch points that assume that the interpreter is running with only one ractor
    single_ractor_patch_points: HashSet<Jump>,
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

    with_vm_lock(src_loc!(), || {
        let invariants = ZJITState::get_invariants();
        if let Some(jumps) = invariants.bop_patch_points.get(&(klass, bop)) {
            let cb = ZJITState::get_code_block();
            let bop = Invariant::BOPRedefined { klass, bop };
            debug!("BOP is redefined: {}", bop);

            // Invalidate all patch points for this BOP
            for jump in jumps {
                cb.with_write_ptr(jump.from, |cb| {
                    let mut asm = Assembler::new();
                    asm_comment!(asm, "BOP is redefined: {}", bop);
                    asm.jmp(jump.to.into());
                    asm.compile(cb).expect("can write existing code");
                });
            }

            cb.mark_all_executable();
        }
    });
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
pub fn track_bop_assumption(
    klass: RedefinitionFlag,
    bop: ruby_basic_operators,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr
) {
    let invariants = ZJITState::get_invariants();
    invariants.bop_patch_points.entry((klass, bop)).or_default().insert(Jump {
        from: patch_point_ptr,
        to: side_exit_ptr,
    });
}

/// Track a patch point for a callable method entry (CME).
pub fn track_cme_assumption(
    cme: *const rb_callable_method_entry_t,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr
) {
    let invariants = ZJITState::get_invariants();
    invariants.cme_patch_points.entry(cme).or_default().insert(Jump {
        from: patch_point_ptr,
        to: side_exit_ptr,
    });
}

/// Track a patch point for each constant name in a constant path assumption.
pub fn track_stable_constant_names_assumption(
    idlist: *const ID,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr
) {
    let invariants = ZJITState::get_invariants();

    let mut idx = 0;
    loop {
        let id = unsafe { *idlist.wrapping_add(idx) };
        if id.0 == 0 {
            break;
        }

        invariants.constant_state_patch_points.entry(id).or_default().insert(Jump {
            from: patch_point_ptr,
            to: side_exit_ptr,
        });

        idx += 1;
    }
}

/// Called when a method is redefined. Invalidates all JIT code that depends on the CME.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_cme_invalidate(cme: *const rb_callable_method_entry_t) {
    // If ZJIT isn't enabled, do nothing
    if !zjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        let invariants = ZJITState::get_invariants();
        // Get the CMD's jumps and remove the entry from the map as it has been invalidated
        if let Some(jumps) = invariants.cme_patch_points.remove(&cme) {
            let cb = ZJITState::get_code_block();
            debug!("CME is invalidated: {:?}", cme);

            // Invalidate all patch points for this CME
            for jump in jumps {
                cb.with_write_ptr(jump.from, |cb| {
                    let mut asm = Assembler::new();
                    asm_comment!(asm, "CME is invalidated: {:?}", cme);
                    asm.jmp(jump.to.into());
                    asm.compile(cb).expect("can write existing code");
                });
            }
            cb.mark_all_executable();
        }
    });
}

/// Called when a constant is redefined. Invalidates all JIT code that depends on the constant.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_constant_state_changed(id: ID) {
    // If ZJIT isn't enabled, do nothing
    if !zjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        let invariants = ZJITState::get_invariants();
        if let Some(jumps) = invariants.constant_state_patch_points.get(&id) {
            let cb = ZJITState::get_code_block();
            debug!("Constant state changed: {:?}", id);

            // Invalidate all patch points for this constant ID
            for jump in jumps {
                cb.with_write_ptr(jump.from, |cb| {
                    let mut asm = Assembler::new();
                    asm_comment!(asm, "Constant state changed: {:?}", id);
                    asm.jmp(jump.to.into());
                    asm.compile(cb).expect("can write existing code");
                });
            }

            cb.mark_all_executable();
        }
    });
}

/// Track the JIT code that assumes that the interpreter is running with only one ractor
pub fn track_single_ractor_assumption(patch_point_ptr: CodePtr, side_exit_ptr: CodePtr) {
    let invariants = ZJITState::get_invariants();
    invariants.single_ractor_patch_points.insert(Jump {
        from: patch_point_ptr,
        to: side_exit_ptr,
    });
}

/// Callback for when Ruby is about to spawn a ractor. In that case we need to
/// invalidate every block that is assuming single ractor mode.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_before_ractor_spawn() {
    // If ZJIT isn't enabled, do nothing
    if !zjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        let cb = ZJITState::get_code_block();

        let jumps = mem::take(&mut ZJITState::get_invariants().single_ractor_patch_points);
        for jump in jumps {
            cb.with_write_ptr(jump.from, |cb| {
                let mut asm = Assembler::new();
                asm_comment!(asm, "Another ractor spawned, invalidating single ractor mode assumption");
                asm.jmp(jump.to.into());
                asm.compile(cb).expect("can write existing code");
            });
        }

        cb.mark_all_executable();
    });
}
