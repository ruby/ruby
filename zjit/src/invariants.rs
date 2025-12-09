//! Code invalidation and patching for speculative optimizations.

use std::{collections::{HashMap, HashSet}, mem};

use crate::{backend::lir::{Assembler, asm_comment}, cruby::{ID, IseqPtr, RedefinitionFlag, VALUE, iseq_name, rb_callable_method_entry_t, rb_gc_location, ruby_basic_operators, src_loc, with_vm_lock}, hir::Invariant, options::debug, state::{ZJITState, zjit_enabled_p}, virtualmem::CodePtr};
use crate::payload::{IseqVersionRef, IseqStatus, get_or_create_iseq_payload};
use crate::codegen::{MAX_ISEQ_VERSIONS, gen_iseq_call};
use crate::cruby::{rb_iseq_reset_jit_func, iseq_get_location};
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
                remove_gc_offsets(patch_point.version, &written_range);

                // If the ISEQ doesn't have max versions, invalidate this version.
                let mut version = patch_point.version;
                let iseq = unsafe { version.as_ref() }.iseq;
                if !iseq.is_null() {
                    let payload = get_or_create_iseq_payload(iseq);
                    if unsafe { version.as_ref() }.status != IseqStatus::Invalidated && payload.versions.len() < MAX_ISEQ_VERSIONS {
                        unsafe { version.as_mut() }.status = IseqStatus::Invalidated;
                        unsafe { rb_iseq_reset_jit_func(version.as_ref().iseq) };

                        // Recompile JIT-to-JIT calls into the invalidated ISEQ
                        for incoming in unsafe { version.as_ref() }.incoming.iter() {
                            if let Err(err) = gen_iseq_call($cb, incoming) {
                                debug!("{err:?}: gen_iseq_call failed on PatchPoint: {}", iseq_get_location(incoming.iseq.get(), 0));
                            }
                        }
                    }
                }
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
    /// ISEQ version to be invalidated
    version: IseqVersionRef,
}

impl PatchPoint {
    /// PatchPointer constructor
    fn new(patch_point_ptr: CodePtr, side_exit_ptr: CodePtr, version: IseqVersionRef) -> PatchPoint {
        Self {
            patch_point_ptr,
            side_exit_ptr,
            version,
        }
    }
}

/// Used to track all of the various block references that contain assumptions
/// about the state of the virtual machine.
#[derive(Default)]
pub struct Invariants {
    /// Set of ISEQs that are known to escape EP
    ep_escape_iseqs: HashSet<IseqPtr>,

    /// Map from ISEQ that's assumed to not escape EP to a set of patch points
    no_ep_escape_iseq_patch_points: HashMap<IseqPtr, HashSet<PatchPoint>>,

    /// Map from a class and its associated basic operator to a set of patch points
    bop_patch_points: HashMap<(RedefinitionFlag, ruby_basic_operators), HashSet<PatchPoint>>,

    /// Map from CME to patch points that assume the method hasn't been redefined
    cme_patch_points: HashMap<*const rb_callable_method_entry_t, HashSet<PatchPoint>>,

    /// Map from constant ID to patch points that assume the constant hasn't been redefined
    constant_state_patch_points: HashMap<ID, HashSet<PatchPoint>>,

    /// Set of patch points that assume that the TracePoint is not enabled
    no_trace_point_patch_points: HashSet<PatchPoint>,

    /// Set of patch points that assume that the interpreter is running with only one ractor
    single_ractor_patch_points: HashSet<PatchPoint>,

    /// Map from a class to a set of patch points that assume objects of the class
    /// will have no singleton class.
    no_singleton_class_patch_points: HashMap<VALUE, HashSet<PatchPoint>>,
}

impl Invariants {
    /// Update object references in Invariants
    pub fn update_references(&mut self) {
        self.update_ep_escape_iseqs();
        self.update_no_ep_escape_iseq_patch_points();
        self.update_cme_patch_points();
        self.update_no_singleton_class_patch_points();
    }

    /// Forget an ISEQ when freeing it. We need to because a) if the address is reused, we'd be
    /// tracking the wrong object b) dead VALUEs in the table can means we risk passing invalid
    /// VALUEs to `rb_gc_location()`.
    pub fn forget_iseq(&mut self, iseq: IseqPtr) {
        // Why not patch the patch points? If the ISEQ is dead then the GC also proved that all
        // generated code referencing the ISEQ are unreachable. We mark the ISEQs baked into
        // generated code.
        self.ep_escape_iseqs.remove(&iseq);
        self.no_ep_escape_iseq_patch_points.remove(&iseq);
    }

    /// Forget a CME when freeing it. See [Self::forget_iseq] for reasoning.
    pub fn forget_cme(&mut self, cme: *const rb_callable_method_entry_t) {
        self.cme_patch_points.remove(&cme);
    }

    /// Forget a class when freeing it. See [Self::forget_iseq] for reasoning.
    pub fn forget_klass(&mut self, klass: VALUE) {
        self.no_singleton_class_patch_points.remove(&klass);
    }

    /// Update ISEQ references in Invariants::ep_escape_iseqs
    fn update_ep_escape_iseqs(&mut self) {
        let updated = std::mem::take(&mut self.ep_escape_iseqs)
            .into_iter()
            .map(|iseq| unsafe { rb_gc_location(iseq.into()) }.as_iseq())
            .collect();
        self.ep_escape_iseqs = updated;
    }

    /// Update ISEQ references in Invariants::no_ep_escape_iseq_patch_points
    fn update_no_ep_escape_iseq_patch_points(&mut self) {
        let updated = std::mem::take(&mut self.no_ep_escape_iseq_patch_points)
            .into_iter()
            .map(|(iseq, patch_points)| {
                let new_iseq = unsafe { rb_gc_location(iseq.into()) };
                (new_iseq.as_iseq(), patch_points)
            })
            .collect();
        self.no_ep_escape_iseq_patch_points = updated;
    }

    fn update_cme_patch_points(&mut self) {
        let updated_cme_patch_points = std::mem::take(&mut self.cme_patch_points)
            .into_iter()
            .map(|(cme, patch_points)| {
                let new_cme = unsafe { rb_gc_location(cme.into()) };
                (new_cme.as_cme(), patch_points)
            })
            .collect();
        self.cme_patch_points = updated_cme_patch_points;
    }

    fn update_no_singleton_class_patch_points(&mut self) {
        let updated_no_singleton_class_patch_points = std::mem::take(&mut self.no_singleton_class_patch_points)
            .into_iter()
            .map(|(klass, patch_points)| {
                let new_klass = unsafe { rb_gc_location(klass) };
                (new_klass, patch_points)
            })
            .collect();
        self.no_singleton_class_patch_points = updated_no_singleton_class_patch_points;
    }
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
pub extern "C" fn rb_zjit_invalidate_no_ep_escape(iseq: IseqPtr) {
    // Skip tracking EP escapes on boot. We don't need to invalidate anything during boot.
    if !ZJITState::has_instance() {
        return;
    }

    // Remember that this ISEQ may escape EP
    let invariants = ZJITState::get_invariants();
    invariants.ep_escape_iseqs.insert(iseq);

    // If the ISEQ has been compiled assuming it doesn't escape EP, invalidate the JIT code.
    if let Some(patch_points) = invariants.no_ep_escape_iseq_patch_points.get(&iseq) {
        debug!("EP is escaped: {}", iseq_name(iseq));

        // Invalidate the patch points for this ISEQ
        let cb = ZJITState::get_code_block();
        compile_patch_points!(cb, patch_points, "EP is escaped: {}", iseq_name(iseq));

        cb.mark_all_executable();
    }
}

/// Track that JIT code for a ISEQ will assume that base pointer is equal to environment pointer.
pub fn track_no_ep_escape_assumption(
    iseq: IseqPtr,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();
    invariants.no_ep_escape_iseq_patch_points.entry(iseq).or_default().insert(PatchPoint::new(
        patch_point_ptr,
        side_exit_ptr,
        version,
    ));
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
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();
    invariants.bop_patch_points.entry((klass, bop)).or_default().insert(PatchPoint::new(
        patch_point_ptr,
        side_exit_ptr,
        version,
    ));
}

/// Track a patch point for a callable method entry (CME).
pub fn track_cme_assumption(
    cme: *const rb_callable_method_entry_t,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();
    invariants.cme_patch_points.entry(cme).or_default().insert(PatchPoint::new(
        patch_point_ptr,
        side_exit_ptr,
        version,
    ));
}

/// Track a patch point for each constant name in a constant path assumption.
pub fn track_stable_constant_names_assumption(
    idlist: *const ID,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();

    let mut idx = 0;
    loop {
        let id = unsafe { *idlist.wrapping_add(idx) };
        if id.0 == 0 {
            break;
        }

        invariants.constant_state_patch_points.entry(id).or_default().insert(PatchPoint::new(
            patch_point_ptr,
            side_exit_ptr,
            version,
        ));

        idx += 1;
    }
}

/// Track a patch point for objects of a given class will have no singleton class.
pub fn track_no_singleton_class_assumption(
    klass: VALUE,
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();
    invariants.no_singleton_class_patch_points.entry(klass).or_default().insert(PatchPoint::new(
        patch_point_ptr,
        side_exit_ptr,
        version,
    ));
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
pub fn track_single_ractor_assumption(
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();
    invariants.single_ractor_patch_points.insert(PatchPoint::new(
        patch_point_ptr,
        side_exit_ptr,
        version,
    ));
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

pub fn track_no_trace_point_assumption(
    patch_point_ptr: CodePtr,
    side_exit_ptr: CodePtr,
    version: IseqVersionRef,
) {
    let invariants = ZJITState::get_invariants();
    invariants.no_trace_point_patch_points.insert(PatchPoint::new(
        patch_point_ptr,
        side_exit_ptr,
        version,
    ));
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_tracing_invalidate_all() {
    use crate::payload::{get_or_create_iseq_payload, IseqStatus};
    use crate::cruby::for_each_iseq;

    if !zjit_enabled_p() {
        return;
    }

    // Stop other ractors since we are going to patch machine code.
    with_vm_lock(src_loc!(), || {
        debug!("Invalidating all ZJIT compiled code due to TracePoint");

        for_each_iseq(|iseq| {
            let payload = get_or_create_iseq_payload(iseq);

            if let Some(version) = payload.versions.last_mut() {
                unsafe { version.as_mut() }.status = IseqStatus::Invalidated;
            }
            unsafe { rb_iseq_reset_jit_func(iseq) };
        });

        let cb = ZJITState::get_code_block();
        let patch_points = mem::take(&mut ZJITState::get_invariants().no_trace_point_patch_points);

        compile_patch_points!(cb, patch_points, "TracePoint is enabled, invalidating no TracePoint assumption");

        cb.mark_all_executable();
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_invalidate_no_singleton_class(klass: VALUE) {
    if !zjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        let invariants = ZJITState::get_invariants();
        if let Some(patch_points) = invariants.no_singleton_class_patch_points.remove(&klass) {
            let cb = ZJITState::get_code_block();
            debug!("Singleton class created for {:?}", klass);
            compile_patch_points!(cb, patch_points, "Singleton class created for {:?}", klass);
            cb.mark_all_executable();
        }
    });
}
