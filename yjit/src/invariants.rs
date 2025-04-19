//! Code to track assumptions made during code generation and invalidate
//! generated code if and when these assumptions are invalidated.

use crate::backend::ir::Assembler;
use crate::codegen::*;
use crate::core::*;
use crate::cruby::*;
use crate::stats::*;
use crate::utils::IntoUsize;
use crate::yjit::yjit_enabled_p;

use std::collections::{HashMap, HashSet};
use std::os::raw::c_void;
use std::mem;

// Invariants to track:
// assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
// assume_method_lookup_stable(comptime_recv_klass, cme, jit);
// assume_single_ractor_mode()
// track_stable_constant_names_assumption()

/// Used to track all of the various block references that contain assumptions
/// about the state of the virtual machine.
pub struct Invariants {
    /// Tracks block assumptions about callable method entry validity.
    cme_validity: HashMap<*const rb_callable_method_entry_t, HashSet<BlockRef>>,

    /// A map from a class and its associated basic operator to a set of blocks
    /// that are assuming that that operator is not redefined. This is used for
    /// quick access to all of the blocks that are making this assumption when
    /// the operator is redefined.
    basic_operator_blocks: HashMap<(RedefinitionFlag, ruby_basic_operators), HashSet<BlockRef>>,
    /// A map from a block to a set of classes and their associated basic
    /// operators that the block is assuming are not redefined. This is used for
    /// quick access to all of the assumptions that a block is making when it
    /// needs to be invalidated.
    block_basic_operators: HashMap<BlockRef, HashSet<(RedefinitionFlag, ruby_basic_operators)>>,

    /// Tracks the set of blocks that are assuming the interpreter is running
    /// with only one ractor. This is important for things like accessing
    /// constants which can have different semantics when multiple ractors are
    /// running.
    single_ractor: HashSet<BlockRef>,

    /// A map from an ID to the set of blocks that are assuming a constant with
    /// that ID as part of its name has not been redefined. For example, if
    /// a constant `A::B` is redefined, then all blocks that are assuming that
    /// `A` and `B` have not be redefined must be invalidated.
    constant_state_blocks: HashMap<ID, HashSet<BlockRef>>,
    /// A map from a block to a set of IDs that it is assuming have not been
    /// redefined.
    block_constant_states: HashMap<BlockRef, HashSet<ID>>,

    /// A map from a class to a set of blocks that assume objects of the class
    /// will have no singleton class. When the set is empty, it means that
    /// there has been a singleton class for the class after boot, so you cannot
    /// assume no singleton class going forward.
    /// For now, the key can be only Array, Hash, or String. Consider making
    /// an inverted HashMap if we start using this for user-defined classes
    /// to maintain the performance of block_assumptions_free().
    no_singleton_classes: HashMap<VALUE, HashSet<BlockRef>>,

    /// A map from an ISEQ to a set of blocks that assume base pointer is equal
    /// to environment pointer. When the set is empty, it means that EP has been
    /// escaped in the ISEQ.
    no_ep_escape_iseqs: HashMap<IseqPtr, HashSet<BlockRef>>,
}

/// Private singleton instance of the invariants global struct.
static mut INVARIANTS: Option<Invariants> = None;

impl Invariants {
    pub fn init() {
        // Wrapping this in unsafe to assign directly to a global.
        unsafe {
            INVARIANTS = Some(Invariants {
                cme_validity: HashMap::new(),
                basic_operator_blocks: HashMap::new(),
                block_basic_operators: HashMap::new(),
                single_ractor: HashSet::new(),
                constant_state_blocks: HashMap::new(),
                block_constant_states: HashMap::new(),
                no_singleton_classes: HashMap::new(),
                no_ep_escape_iseqs: HashMap::new(),
            });
        }
    }

    /// Get a mutable reference to the codegen globals instance
    pub fn get_instance() -> &'static mut Invariants {
        unsafe { INVARIANTS.as_mut().unwrap() }
    }
}

/// Mark the pending block as assuming that certain basic operators (e.g. Integer#==)
/// have not been redefined.
#[must_use]
pub fn assume_bop_not_redefined(
    jit: &mut JITState,
    asm: &mut Assembler,
    klass: RedefinitionFlag,
    bop: ruby_basic_operators,
) -> bool {
    if unsafe { BASIC_OP_UNREDEFINED_P(bop, klass) } {
        if jit_ensure_block_entry_exit(jit, asm).is_none() {
            return false;
        }
        jit.bop_assumptions.push((klass, bop));

        return true;
    } else {
        return false;
    }
}

/// Track that a block is only valid when a certain basic operator has not been redefined
/// since the block's inception.
pub fn track_bop_assumption(uninit_block: BlockRef, bop: (RedefinitionFlag, ruby_basic_operators)) {
    let invariants = Invariants::get_instance();
    invariants
        .basic_operator_blocks
        .entry(bop)
        .or_default()
        .insert(uninit_block);
    invariants
        .block_basic_operators
        .entry(uninit_block)
        .or_default()
        .insert(bop);
}

/// Track that a block will assume that `cme` is valid (false == METHOD_ENTRY_INVALIDATED(cme)).
/// [rb_yjit_cme_invalidate] invalidates the block when `cme` is invalidated.
pub fn track_method_lookup_stability_assumption(
    uninit_block: BlockRef,
    callee_cme: *const rb_callable_method_entry_t,
) {
    Invariants::get_instance()
        .cme_validity
        .entry(callee_cme)
        .or_default()
        .insert(uninit_block);
}

/// Track that a block will assume that `klass` objects will have no singleton class.
pub fn track_no_singleton_class_assumption(uninit_block: BlockRef, klass: VALUE) {
    Invariants::get_instance()
        .no_singleton_classes
        .entry(klass)
        .or_default()
        .insert(uninit_block);
}

/// Returns true if we've seen a singleton class of a given class since boot.
pub fn has_singleton_class_of(klass: VALUE) -> bool {
    Invariants::get_instance()
        .no_singleton_classes
        .get(&klass)
        .map_or(false, |blocks| blocks.is_empty())
}

/// Track that a block will assume that base pointer is equal to environment pointer.
pub fn track_no_ep_escape_assumption(uninit_block: BlockRef, iseq: IseqPtr) {
    Invariants::get_instance()
        .no_ep_escape_iseqs
        .entry(iseq)
        .or_default()
        .insert(uninit_block);
}

/// Returns true if a given ISEQ has previously escaped an environment.
pub fn iseq_escapes_ep(iseq: IseqPtr) -> bool {
    Invariants::get_instance()
        .no_ep_escape_iseqs
        .get(&iseq)
        .map_or(false, |blocks| blocks.is_empty())
}

/// Forget an ISEQ remembered in invariants
pub fn iseq_free_invariants(iseq: IseqPtr) {
    if unsafe { INVARIANTS.is_none() } {
        return;
    }
    Invariants::get_instance().no_ep_escape_iseqs.remove(&iseq);
}

// Checks rb_method_basic_definition_p and registers the current block for invalidation if method
// lookup changes.
// A "basic method" is one defined during VM boot, so we can use this to check assumptions based on
// default behavior.
pub fn assume_method_basic_definition(
    jit: &mut JITState,
    asm: &mut Assembler,
    klass: VALUE,
    mid: ID
) -> bool {
    if unsafe { rb_method_basic_definition_p(klass, mid) } != 0 {
        let cme = unsafe { rb_callable_method_entry(klass, mid) };
        jit.assume_method_lookup_stable(asm, cme);
        true
    } else {
        false
    }
}

/// Tracks that a block is assuming it is operating in single-ractor mode.
#[must_use]
pub fn assume_single_ractor_mode(jit: &mut JITState, asm: &mut Assembler) -> bool {
    if unsafe { rb_yjit_multi_ractor_p() } {
        false
    } else {
        if jit_ensure_block_entry_exit(jit, asm).is_none() {
            return false;
        }
        jit.block_assumes_single_ractor = true;

        true
    }
}

/// Track that the block will assume single ractor mode.
pub fn track_single_ractor_assumption(uninit_block: BlockRef) {
    Invariants::get_instance()
        .single_ractor
        .insert(uninit_block);
}

/// Track that a block will assume that the name components of a constant path expression
/// has not changed since the block's full initialization.
pub fn track_stable_constant_names_assumption(uninit_block: BlockRef, idlist: *const ID) {
    fn assume_stable_constant_name(
        uninit_block: BlockRef,
        id: ID,
    ) {
        if id == ID!(NULL) {
            // Used for :: prefix
            return;
        }

        let invariants = Invariants::get_instance();
        invariants
            .constant_state_blocks
            .entry(id)
            .or_default()
            .insert(uninit_block);
        invariants
            .block_constant_states
            .entry(uninit_block)
            .or_default()
            .insert(id);
    }


    for i in 0.. {
        match unsafe { *idlist.offset(i) } {
            0 => break, // End of NULL terminated list
            id => assume_stable_constant_name(uninit_block, id),
        }
    }
}

/// Called when a basic operator is redefined. Note that all the blocks assuming
/// the stability of different operators are invalidated together and we don't
/// do fine-grained tracking.
#[no_mangle]
pub extern "C" fn rb_yjit_bop_redefined(klass: RedefinitionFlag, bop: ruby_basic_operators) {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        // Loop through the blocks that are associated with this class and basic
        // operator and invalidate them.
        if let Some(blocks) = Invariants::get_instance()
            .basic_operator_blocks
            .remove(&(klass, bop))
        {
            for block in blocks.iter() {
                invalidate_block_version(block);
                incr_counter!(invalidate_bop_redefined);
            }
        }
    });
}

/// Callback for when a cme becomes invalid. Invalidate all blocks that depend
/// on the given cme being valid.
#[no_mangle]
pub extern "C" fn rb_yjit_cme_invalidate(callee_cme: *const rb_callable_method_entry_t) {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        if let Some(blocks) = Invariants::get_instance().cme_validity.remove(&callee_cme) {
            for block in blocks.iter() {
                invalidate_block_version(block);
                incr_counter!(invalidate_method_lookup);
            }
        }
    });
}

/// Callback for then Ruby is about to spawn a ractor. In that case we need to
/// invalidate every block that is assuming single ractor mode.
#[no_mangle]
pub extern "C" fn rb_yjit_before_ractor_spawn() {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        // Clear the set of blocks inside Invariants
        let blocks = mem::take(&mut Invariants::get_instance().single_ractor);

        // Invalidate the blocks
        for block in &blocks {
            invalidate_block_version(block);
            incr_counter!(invalidate_ractor_spawn);
        }
    });
}

/// Callback for when the global constant state changes.
#[no_mangle]
pub extern "C" fn rb_yjit_constant_state_changed(id: ID) {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        // Invalidate the blocks that are associated with the given ID.
        if let Some(blocks) = Invariants::get_instance().constant_state_blocks.remove(&id) {
            for block in &blocks {
                invalidate_block_version(block);
                incr_counter!(invalidate_constant_state_bump);
            }
        }
    });
}

/// Callback for marking GC objects inside [Invariants].
/// See `struct yjijt_root_struct` in C.
#[no_mangle]
pub extern "C" fn rb_yjit_root_mark() {
    // Call rb_gc_mark on exit location's raw_samples to
    // wrap frames in a GC allocated object. This needs to be called
    // at the same time as root mark.
    YjitExitLocations::gc_mark_raw_samples();

    // Comment from C YJIT:
    //
    // Why not let the GC move the cme keys in this table?
    // Because this is basically a compare_by_identity Hash.
    // If a key moves, we would need to reinsert it into the table so it is rehashed.
    // That is tricky to do, especially as it could trigger allocation which could
    // trigger GC. Not sure if it is okay to trigger GC while the GC is updating
    // references.
    //
    // NOTE(alan): since we are using Rust data structures that don't interact
    // with the Ruby GC now, it might be feasible to allow movement.

    let invariants = Invariants::get_instance();

    // Mark CME imemos
    for cme in invariants.cme_validity.keys() {
        let cme: VALUE = (*cme).into();

        unsafe { rb_gc_mark(cme) };
    }
}

#[no_mangle]
pub extern "C" fn rb_yjit_root_update_references() {
    if unsafe { INVARIANTS.is_none() } {
        return;
    }
    let no_ep_escape_iseqs = &mut Invariants::get_instance().no_ep_escape_iseqs;

    // Make a copy of the table with updated ISEQ keys
    let mut updated_copy = HashMap::with_capacity(no_ep_escape_iseqs.len());
    for (iseq, blocks) in mem::take(no_ep_escape_iseqs) {
        let new_iseq = unsafe { rb_gc_location(iseq.into()) }.as_iseq();
        updated_copy.insert(new_iseq, blocks);
    }

    *no_ep_escape_iseqs = updated_copy;
}

/// Remove all invariant assumptions made by the block by removing the block as
/// as a key in all of the relevant tables.
/// For safety, the block has to be initialized and the vm lock must be held.
/// However, outgoing/incoming references to the block does _not_ need to be valid.
pub fn block_assumptions_free(blockref: BlockRef) {
    let invariants = Invariants::get_instance();

    {
        // SAFETY: caller ensures that this reference is valid
        let block = unsafe { blockref.as_ref() };

        // For each method lookup dependency
        for dep in block.iter_cme_deps() {
            // Remove tracking for cme validity
            if let Some(blockset) = invariants.cme_validity.get_mut(&dep) {
                blockset.remove(&blockref);
                if blockset.is_empty() {
                    invariants.cme_validity.remove(&dep);
                }
            }
        }
        if invariants.cme_validity.is_empty() {
            invariants.cme_validity.shrink_to_fit();
        }
    }

    // Remove tracking for basic operators that the given block assumes have
    // not been redefined.
    if let Some(bops) = invariants.block_basic_operators.remove(&blockref) {
        // Remove tracking for the given block from the list of blocks associated
        // with the given basic operator.
        for key in &bops {
            if let Some(blocks) = invariants.basic_operator_blocks.get_mut(key) {
                blocks.remove(&blockref);
                if blocks.is_empty() {
                    invariants.basic_operator_blocks.remove(key);
                }
            }
        }
    }
    if invariants.block_basic_operators.is_empty() {
        invariants.block_basic_operators.shrink_to_fit();
    }
    if invariants.basic_operator_blocks.is_empty() {
        invariants.basic_operator_blocks.shrink_to_fit();
    }

    // Remove tracking for blocks assuming single ractor mode
    invariants.single_ractor.remove(&blockref);
    if invariants.single_ractor.is_empty() {
        invariants.single_ractor.shrink_to_fit();
    }

    // Remove tracking for constant state for a given ID.
    if let Some(ids) = invariants.block_constant_states.remove(&blockref) {
        for id in ids {
            if let Some(blocks) = invariants.constant_state_blocks.get_mut(&id) {
                blocks.remove(&blockref);
                if blocks.is_empty() {
                    invariants.constant_state_blocks.remove(&id);
                }
            }
        }
    }
    if invariants.block_constant_states.is_empty() {
        invariants.block_constant_states.shrink_to_fit();
    }
    if invariants.constant_state_blocks.is_empty() {
        invariants.constant_state_blocks.shrink_to_fit();
    }

    // Remove tracking for blocks assuming no singleton class
    // NOTE: no_singleton_class has up to 3 keys (Array, Hash, or String) for now.
    // This is effectively an O(1) access unless we start using it for more classes.
    for (_, blocks) in invariants.no_singleton_classes.iter_mut() {
        blocks.remove(&blockref);
    }

    // Remove tracking for blocks assuming EP doesn't escape
    let iseq = unsafe { blockref.as_ref() }.get_blockid().iseq;
    if let Some(blocks) = invariants.no_ep_escape_iseqs.get_mut(&iseq) {
        blocks.remove(&blockref);
    }
}

/// Callback from the opt_setinlinecache instruction in the interpreter.
/// Invalidate the block for the matching opt_getinlinecache so it could regenerate code
/// using the new value in the constant cache.
#[no_mangle]
pub extern "C" fn rb_yjit_constant_ic_update(iseq: *const rb_iseq_t, ic: IC, insn_idx: std::os::raw::c_uint) {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    // Try to downcast the iseq index
    let insn_idx: IseqIdx = if let Ok(idx) = insn_idx.try_into() {
        idx
    } else {
        // The index is too large, YJIT can't possibly have code for it,
        // so there is nothing to invalidate.
        return;
    };

    if !unsafe { rb_yjit_constcache_cref(ic) }.is_null() || unsafe { rb_yjit_multi_ractor_p() } {
        // We can't generate code in these situations, so no need to invalidate.
        // See gen_opt_getinlinecache.
        return;
    }

    with_vm_lock(src_loc!(), || {
        let code = unsafe { get_iseq_body_iseq_encoded(iseq) };

        // This should come from a running iseq, so direct threading translation
        // should have been done
        assert!(unsafe { FL_TEST(iseq.into(), VALUE(ISEQ_TRANSLATED)) } != VALUE(0));
        assert!(u32::from(insn_idx) < unsafe { get_iseq_encoded_size(iseq) });

        // Ensure that the instruction the insn_idx is pointing to is in
        // fact a opt_getconstant_path instruction.
        assert_eq!(
            unsafe {
                let opcode_pc = code.add(insn_idx.as_usize());
                let translated_opcode: VALUE = opcode_pc.read();
                rb_vm_insn_decode(translated_opcode)
            },
            YARVINSN_opt_getconstant_path.try_into().unwrap()
        );

        // Find the matching opt_getinlinecache and invalidate all the blocks there
        // RUBY_ASSERT(insn_op_type(BIN(opt_getinlinecache), 1) == TS_IC);

        let ic_pc = unsafe { code.add(insn_idx.as_usize() + 1) };
        let ic_operand: IC = unsafe { ic_pc.read() }.as_mut_ptr();

        if ic == ic_operand {
            for block in take_version_list(BlockId {
                iseq,
                idx: insn_idx,
            }) {
                invalidate_block_version(&block);
                incr_counter!(invalidate_constant_ic_fill);
            }
        } else {
            panic!("ic->get_insn_index not set properly");
        }
    });
}

/// Invalidate blocks that assume objects of a given class will have no singleton class.
#[no_mangle]
pub extern "C" fn rb_yjit_invalidate_no_singleton_class(klass: VALUE) {
    // Skip tracking singleton classes during boot. Such objects already have a singleton class
    // before entering JIT code, so they get rejected when they're checked for the first time.
    if unsafe { INVARIANTS.is_none() } {
        return;
    }

    // We apply this optimization only to Array, Hash, and String for now.
    if unsafe { [rb_cArray, rb_cHash, rb_cString].contains(&klass) } {
        with_vm_lock(src_loc!(), || {
            let no_singleton_classes = &mut Invariants::get_instance().no_singleton_classes;
            match no_singleton_classes.get_mut(&klass) {
                Some(blocks) => {
                    // Invalidate existing blocks and let has_singleton_class_of()
                    // return true when they are compiled again
                    for block in mem::take(blocks) {
                        invalidate_block_version(&block);
                        incr_counter!(invalidate_no_singleton_class);
                    }
                }
                None => {
                    // Let has_singleton_class_of() return true for this class
                    no_singleton_classes.insert(klass, HashSet::new());
                }
            }
        });
    }
}

/// Invalidate blocks for a given ISEQ that assumes environment pointer is
/// equal to base pointer.
#[no_mangle]
pub extern "C" fn rb_yjit_invalidate_ep_is_bp(iseq: IseqPtr) {
    // Skip tracking EP escapes on boot. We don't need to invalidate anything during boot.
    if unsafe { INVARIANTS.is_none() } {
        return;
    }

    with_vm_lock(src_loc!(), || {
        // If an EP escape for this ISEQ is detected for the first time, invalidate all blocks
        // associated to the ISEQ.
        let no_ep_escape_iseqs = &mut Invariants::get_instance().no_ep_escape_iseqs;
        match no_ep_escape_iseqs.get_mut(&iseq) {
            Some(blocks) => {
                // Invalidate existing blocks and make jit.ep_is_bp() return false
                for block in mem::take(blocks) {
                    invalidate_block_version(&block);
                    incr_counter!(invalidate_ep_escape);
                }
            }
            None => {
                // Let jit.ep_is_bp() return false for this ISEQ
                no_ep_escape_iseqs.insert(iseq, HashSet::new());
            }
        }
    });
}

// Invalidate all generated code and patch C method return code to contain
// logic for firing the c_return TracePoint event. Once rb_vm_barrier()
// returns, all other ractors are pausing inside RB_VM_LOCK_ENTER(), which
// means they are inside a C routine. If there are any generated code on-stack,
// they are waiting for a return from a C routine. For every routine call, we
// patch in an exit after the body of the containing VM instruction. This makes
// it so all the invalidated code exit as soon as execution logically reaches
// the next VM instruction. The interpreter takes care of firing the tracing
// event if it so happens that the next VM instruction has one attached.
//
// The c_return event needs special handling as our codegen never outputs code
// that contains tracing logic. If we let the normal output code run until the
// start of the next VM instruction by relying on the patching scheme above, we
// would fail to fire the c_return event. The interpreter doesn't fire the
// event at an instruction boundary, so simply exiting to the interpreter isn't
// enough. To handle it, we patch in the full logic at the return address. See
// full_cfunc_return().
//
// In addition to patching, we prevent future entries into invalidated code by
// removing all live blocks from their iseq.
#[no_mangle]
pub extern "C" fn rb_yjit_tracing_invalidate_all() {
    if !yjit_enabled_p() {
        return;
    }

    incr_counter!(invalidate_everything);

    // Stop other ractors since we are going to patch machine code.
    with_vm_lock(src_loc!(), || {
        // Make it so all live block versions are no longer valid branch targets
        let mut on_stack_iseqs = HashSet::new();
        for_each_on_stack_iseq(|iseq| {
            on_stack_iseqs.insert(iseq);
        });
        for_each_iseq(|iseq| {
            if let Some(payload) = get_iseq_payload(iseq) {
                let blocks = payload.take_all_blocks();

                if on_stack_iseqs.contains(&iseq) {
                    // This ISEQ is running, so we can't free blocks immediately
                    for block in blocks {
                        delayed_deallocation(block);
                    }
                    payload.dead_blocks.shrink_to_fit();
                } else {
                    // Safe to free dead blocks since the ISEQ isn't running
                    // Since we're freeing _all_ blocks, we don't need to keep the graph well formed
                    for block in blocks {
                        unsafe { free_block(block, false) };
                    }
                    mem::take(&mut payload.dead_blocks)
                        .into_iter()
                        .for_each(|block| unsafe { free_block(block, false) });
                }
            }

            // Reset output code entry point
            unsafe { rb_iseq_reset_jit_func(iseq) };
        });

        let cb = CodegenGlobals::get_inline_cb();

        // Prevent on-stack frames from jumping to the caller on jit_exec_exception
        extern "C" {
            fn rb_yjit_cancel_jit_return(leave_exit: *mut c_void, leave_exception: *mut c_void) -> VALUE;
        }
        unsafe {
            rb_yjit_cancel_jit_return(
                CodegenGlobals::get_leave_exit_code().raw_ptr(cb) as _,
                CodegenGlobals::get_leave_exception_code().raw_ptr(cb) as _,
            );
        }

        // Apply patches
        let old_pos = cb.get_write_pos();
        let old_dropped_bytes = cb.has_dropped_bytes();
        let mut patches = CodegenGlobals::take_global_inval_patches();
        patches.sort_by_cached_key(|patch| patch.inline_patch_pos.raw_ptr(cb));
        let mut last_patch_end = std::ptr::null();
        for patch in &patches {
            let patch_pos = patch.inline_patch_pos.raw_ptr(cb);
            assert!(
                last_patch_end <= patch_pos,
                "patches should not overlap (last_patch_end: {last_patch_end:?}, patch_pos: {patch_pos:?})",
            );

            cb.set_write_ptr(patch.inline_patch_pos);
            cb.set_dropped_bytes(false);
            cb.without_page_end_reserve(|cb| {
                let mut asm = crate::backend::ir::Assembler::new_without_iseq();
                asm.jmp(patch.outlined_target_pos.as_side_exit());
                if asm.compile(cb, None).is_none() {
                    panic!("Failed to apply patch at {:?}", patch.inline_patch_pos);
                }
            });
            last_patch_end = cb.get_write_ptr().raw_ptr(cb);
        }
        cb.set_pos(old_pos);
        cb.set_dropped_bytes(old_dropped_bytes);

        CodegenGlobals::get_outlined_cb()
            .unwrap()
            .mark_all_executable();
        cb.mark_all_executable();
    });
}
