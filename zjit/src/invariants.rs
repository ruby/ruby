use std::{collections::{HashMap, HashSet}, mem};

use crate::{backend::lir::{asm_comment, Assembler}, cruby::{rb_callable_method_entry_t, ruby_basic_operators, src_loc, with_vm_lock, IseqPtr, RedefinitionFlag, ID}, gc::IseqPayload, hir::Invariant, options::debug, state::{zjit_enabled_p, ZJITState}, virtualmem::CodePtr};
use crate::stats::with_time_stat;
use crate::stats::Counter::invalidation_time_ns;
use crate::gc::remove_gc_offsets;

macro_rules! compile_patch_points {
    ($cb:expr, $patch_points:expr, $($comment_args:tt)*) => {
        with_time_stat(invalidation_time_ns, || {
            for patch_point in $patch_points {
                let written_range = $cb.with_write_ptr(patch_point.patch_point_ptr, |cb| {
                    let mut asm = Assembler::new();
                    asm_comment!(asm, $($comment_args)*);
                    asm.jmp(patch_point.side_exit_ptr.into());
                    asm.compile(cb).expect("can write existing code");
                });
                // Stop marking GC offsets corrupted by the jump instruction
                remove_gc_offsets(patch_point.payload_ptr, &written_range);
            }
        });
    };
}

/// When a PatchPoint is invalidated, it generates a jump instruction from `from` to `to`.
#[derive(Debug, Eq, Hash, PartialEq)]
struct PatchPoint {
    /// Code pointer to be invalidated
    patch_point_ptr: CodePtr,
    /// Code pointer to a side exit
    side_exit_ptr: CodePtr,
    /// Raw pointer to the ISEQ payload
    payload_ptr: *mut IseqPayload,
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
    bop_patch_points: HashMap<(RedefinitionFlag, ruby_basic_operators), HashSet<PatchPoint>>,

    /// Map from CME to patch points that assume the method hasn't been redefined
    cme_patch_points: HashMap<*const rb_callable_method_entry_t, HashSet<PatchPoint>>,

    /// Map from constant ID to patch points that assume the constant hasn't been redefined
    constant_state_patch_points: HashMap<ID, HashSet<PatchPoint>>,

    /// Set of patch points that assume that the interpreter is running with only one ractor
    single_ractor_patch_points: HashSet<PatchPoint>,
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
        if let Some(patch_points) = invariants.bop_patch_points.get(&(klass, bop)) {
            let cb = ZJITState::get_code_block();
            let bop = Invariant::BOPRedefined { klass, bop };
            debug!("BOP is redefined: {}", bop);

            // Invalidate all patch points for this BOP
            compile_patch_points!(cb, patch_points, "BOP is redefined: {}", bop);

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
    side_exit_ptr: CodePtr,
    payload_ptr: *mut IseqPayload,
) {
    let invariants = ZJITState::get_invariants();
    invariants.bop_patch_points.entry((klass, bop)).or_default().insert(PatchPoint {
        patch_point_ptr,
        side_exit_ptr,
        payload_ptr,
    });
}

/// Track a patch point for a callable method entry (CME).
pub fn track_cme_assumption(
    cme: *const rb_callable_method_entry_t,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    payload_ptr: *mut IseqPayload,
) {
    let invariants = ZJITState::get_invariants();
    invariants.cme_patch_points.entry(cme).or_default().insert(PatchPoint {
        patch_point_ptr,
        side_exit_ptr,
        payload_ptr,
    });
}

/// Track a patch point for each constant name in a constant path assumption.
pub fn track_stable_constant_names_assumption(
    idlist: *const ID,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    payload_ptr: *mut IseqPayload,
) {
    let invariants = ZJITState::get_invariants();

    let mut idx = 0;
    loop {
        let id = unsafe { *idlist.wrapping_add(idx) };
        if id.0 == 0 {
            break;
        }

        invariants.constant_state_patch_points.entry(id).or_default().insert(PatchPoint {
            patch_point_ptr,
            side_exit_ptr,
            payload_ptr,
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
        if let Some(patch_points) = invariants.cme_patch_points.remove(&cme) {
            let cb = ZJITState::get_code_block();
            debug!("CME is invalidated: {:?}", cme);

            // Invalidate all patch points for this CME
            compile_patch_points!(cb, patch_points, "CME is invalidated: {:?}", cme);

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
        if let Some(patch_points) = invariants.constant_state_patch_points.get(&id) {
            let cb = ZJITState::get_code_block();
            debug!("Constant state changed: {:?}", id);

            // Invalidate all patch points for this constant ID
            compile_patch_points!(cb, patch_points, "Constant state changed: {:?}", id);

            cb.mark_all_executable();
        }
    });
}

/// Track the JIT code that assumes that the interpreter is running with only one ractor
pub fn track_single_ractor_assumption(patch_point_ptr: CodePtr, side_exit_ptr: CodePtr, payload_ptr: *mut IseqPayload) {
    let invariants = ZJITState::get_invariants();
    invariants.single_ractor_patch_points.insert(PatchPoint {
        patch_point_ptr,
        side_exit_ptr,
        payload_ptr,
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
        let patch_points = mem::take(&mut ZJITState::get_invariants().single_ractor_patch_points);

        // Invalidate all patch points for single ractor mode
        compile_patch_points!(cb, patch_points, "Another ractor spawned, invalidating single ractor mode assumption");

        cb.mark_all_executable();
    });
}
