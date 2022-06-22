//! Code to track assumptions made during code generation and invalidate
//! generated code if and when these assumptions are invalidated.

use crate::asm::OutlinedCb;
use crate::codegen::*;
use crate::core::*;
use crate::cruby::*;
use crate::options::*;
use crate::stats::*;
use crate::utils::IntoUsize;
use crate::yjit::yjit_enabled_p;

use std::collections::{HashMap, HashSet};
use std::mem;
use std::os::raw::c_void;

// Invariants to track:
// assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)
// assume_method_lookup_stable(comptime_recv_klass, cme, jit);
// assume_single_ractor_mode(jit)
// assume_stable_global_constant_state(jit);

/// Used to track all of the various block references that contain assumptions
/// about the state of the virtual machine.
pub struct Invariants {
    /// Tracks block assumptions about callable method entry validity.
    cme_validity: HashMap<*const rb_callable_method_entry_t, HashSet<BlockRef>>,

    /// Tracks block assumptions about method lookup. Maps a class to a table of
    /// method ID points to a set of blocks. While a block `b` is in the table,
    /// b->callee_cme == rb_callable_method_entry(klass, mid).
    method_lookup: HashMap<VALUE, HashMap<ID, HashSet<BlockRef>>>,

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
}

/// Private singleton instance of the invariants global struct.
static mut INVARIANTS: Option<Invariants> = None;

impl Invariants {
    pub fn init() {
        // Wrapping this in unsafe to assign directly to a global.
        unsafe {
            INVARIANTS = Some(Invariants {
                cme_validity: HashMap::new(),
                method_lookup: HashMap::new(),
                basic_operator_blocks: HashMap::new(),
                block_basic_operators: HashMap::new(),
                single_ractor: HashSet::new(),
                constant_state_blocks: HashMap::new(),
                block_constant_states: HashMap::new(),
            });
        }
    }

    /// Get a mutable reference to the codegen globals instance
    pub fn get_instance() -> &'static mut Invariants {
        unsafe { INVARIANTS.as_mut().unwrap() }
    }
}

/// A public function that can be called from within the code generation
/// functions to ensure that the block being generated is invalidated when the
/// basic operator is redefined.
pub fn assume_bop_not_redefined(
    jit: &mut JITState,
    ocb: &mut OutlinedCb,
    klass: RedefinitionFlag,
    bop: ruby_basic_operators,
) -> bool {
    if unsafe { BASIC_OP_UNREDEFINED_P(bop, klass) } {
        jit_ensure_block_entry_exit(jit, ocb);

        let invariants = Invariants::get_instance();
        invariants
            .basic_operator_blocks
            .entry((klass, bop))
            .or_default()
            .insert(jit.get_block());
        invariants
            .block_basic_operators
            .entry(jit.get_block())
            .or_default()
            .insert((klass, bop));

        return true;
    } else {
        return false;
    }
}

// Remember that a block assumes that
// `rb_callable_method_entry(receiver_klass, cme->called_id) == cme` and that
// `cme` is valid.
// When either of these assumptions becomes invalid, rb_yjit_method_lookup_change() or
// rb_yjit_cme_invalidate() invalidates the block.
//
// @raise NoMemoryError
pub fn assume_method_lookup_stable(
    jit: &mut JITState,
    ocb: &mut OutlinedCb,
    receiver_klass: VALUE,
    callee_cme: *const rb_callable_method_entry_t,
) {
    // RUBY_ASSERT(rb_callable_method_entry(receiver_klass, cme->called_id) == cme);
    // RUBY_ASSERT_ALWAYS(RB_TYPE_P(receiver_klass, T_CLASS) || RB_TYPE_P(receiver_klass, T_ICLASS));
    // RUBY_ASSERT_ALWAYS(!rb_objspace_garbage_object_p(receiver_klass));

    jit_ensure_block_entry_exit(jit, ocb);

    let block = jit.get_block();
    block
        .borrow_mut()
        .add_cme_dependency(receiver_klass, callee_cme);

    Invariants::get_instance()
        .cme_validity
        .entry(callee_cme)
        .or_default()
        .insert(block.clone());

    let mid = unsafe { (*callee_cme).called_id };
    Invariants::get_instance()
        .method_lookup
        .entry(receiver_klass)
        .or_default()
        .entry(mid)
        .or_default()
        .insert(block);
}

/// Tracks that a block is assuming it is operating in single-ractor mode.
#[must_use]
pub fn assume_single_ractor_mode(jit: &mut JITState, ocb: &mut OutlinedCb) -> bool {
    if unsafe { rb_yjit_multi_ractor_p() } {
        false
    } else {
        jit_ensure_block_entry_exit(jit, ocb);
        Invariants::get_instance()
            .single_ractor
            .insert(jit.get_block());
        true
    }
}

/// Walk through the ISEQ to go from the current opt_getinlinecache to the
/// subsequent opt_setinlinecache and find all of the name components that are
/// associated with this constant (which correspond to the getconstant
/// arguments).
pub fn assume_stable_constant_names(jit: &mut JITState, ocb: &mut OutlinedCb) {
    /// Tracks that a block is assuming that the name component of a constant
    /// has not changed since the last call to this function.
    unsafe extern "C" fn assume_stable_constant_name(
        code: *mut VALUE,
        insn: VALUE,
        index: u64,
        data: *mut c_void,
    ) -> bool {
        if insn.as_u32() == YARVINSN_opt_setinlinecache {
            return false;
        }

        if insn.as_u32() == YARVINSN_getconstant {
            let jit = &mut *(data as *mut JITState);

            // The first operand to GETCONSTANT is always the ID associated with
            // the constant lookup. We are grabbing this out in order to
            // associate this block with the stability of this constant name.
            let id = code.add(index.as_usize() + 1).read().as_u64() as ID;

            let invariants = Invariants::get_instance();
            invariants
                .constant_state_blocks
                .entry(id)
                .or_default()
                .insert(jit.get_block());
            invariants
                .block_constant_states
                .entry(jit.get_block())
                .or_default()
                .insert(id);
        }

        true
    }

    jit_ensure_block_entry_exit(jit, ocb);

    unsafe {
        let iseq = jit.get_iseq();
        let encoded = get_iseq_body_iseq_encoded(iseq);
        let start_index = jit.get_pc().offset_from(encoded);

        rb_iseq_each(
            iseq,
            start_index.try_into().unwrap(),
            Some(assume_stable_constant_name),
            jit as *mut _ as *mut c_void,
        );
    };
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

/// Callback for when rb_callable_method_entry(klass, mid) is going to change.
/// Invalidate blocks that assume stable method lookup of `mid` in `klass` when this happens.
/// This needs to be wrapped on the C side with RB_VM_LOCK_ENTER().
#[no_mangle]
pub extern "C" fn rb_yjit_method_lookup_change(klass: VALUE, mid: ID) {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    with_vm_lock(src_loc!(), || {
        Invariants::get_instance()
            .method_lookup
            .entry(klass)
            .and_modify(|deps| {
                if let Some(deps) = deps.remove(&mid) {
                    for block in &deps {
                        invalidate_block_version(block);
                        incr_counter!(invalidate_method_lookup);
                    }
                }
            });
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
        if get_option!(global_constant_state) {
            // If the global-constant-state option is set, then we're going to
            // invalidate every block that depends on any constant.

            Invariants::get_instance()
                .constant_state_blocks
                .keys()
                .for_each(|id| {
                    if let Some(blocks) =
                        Invariants::get_instance().constant_state_blocks.remove(&id)
                    {
                        for block in &blocks {
                            invalidate_block_version(block);
                            incr_counter!(invalidate_constant_state_bump);
                        }
                    }
                });
        } else {
            // If the global-constant-state option is not set, then we're only going
            // to invalidate the blocks that are associated with the given ID.

            if let Some(blocks) = Invariants::get_instance().constant_state_blocks.remove(&id) {
                for block in &blocks {
                    invalidate_block_version(block);
                    incr_counter!(invalidate_constant_state_bump);
                }
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
    // That is tricky to do, espcially as it could trigger allocation which could
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

    // Mark class and iclass objects
    for klass in invariants.method_lookup.keys() {
        // TODO: This is a leak. Unused blocks linger in the table forever, preventing the
        // callee class they speculate on from being collected.
        // We could do a bespoke weak reference scheme on classes similar to
        // the interpreter's call cache. See finalizer for T_CLASS and cc_table_free().

        unsafe { rb_gc_mark(*klass) };
    }
}

/// Remove all invariant assumptions made by the block by removing the block as
/// as a key in all of the relevant tables.
pub fn block_assumptions_free(blockref: &BlockRef) {
    let invariants = Invariants::get_instance();

    {
        let block = blockref.borrow();

        // For each method lookup dependency
        for dep in block.iter_cme_deps() {
            // Remove tracking for cme validity
            if let Some(blockset) = invariants.cme_validity.get_mut(&dep.callee_cme) {
                blockset.remove(blockref);
            }

            // Remove tracking for lookup stability
            if let Some(id_to_block_set) = invariants.method_lookup.get_mut(&dep.receiver_klass) {
                let mid = unsafe { (*dep.callee_cme).called_id };
                if let Some(block_set) = id_to_block_set.get_mut(&mid) {
                    block_set.remove(&blockref);
                }
            }
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
            }
        }
    }

    invariants.single_ractor.remove(&blockref);

    // Remove tracking for constant state for a given ID.
    if let Some(ids) = invariants.block_constant_states.remove(&blockref) {
        for id in ids {
            if let Some(blocks) = invariants.constant_state_blocks.get_mut(&id) {
                blocks.remove(&blockref);
            }
        }
    }
}

/// Callback from the opt_setinlinecache instruction in the interpreter.
/// Invalidate the block for the matching opt_getinlinecache so it could regenerate code
/// using the new value in the constant cache.
#[no_mangle]
pub extern "C" fn rb_yjit_constant_ic_update(iseq: *const rb_iseq_t, ic: IC) {
    // If YJIT isn't enabled, do nothing
    if !yjit_enabled_p() {
        return;
    }

    if !unsafe { (*(*ic).entry).ic_cref }.is_null() || unsafe { rb_yjit_multi_ractor_p() } {
        // We can't generate code in these situations, so no need to invalidate.
        // See gen_opt_getinlinecache.
        return;
    }

    with_vm_lock(src_loc!(), || {
        let code = unsafe { get_iseq_body_iseq_encoded(iseq) };
        let get_insn_idx = unsafe { (*ic).get_insn_idx };

        // This should come from a running iseq, so direct threading translation
        // should have been done
        assert!(unsafe { FL_TEST(iseq.into(), VALUE(ISEQ_TRANSLATED as usize)) } != VALUE(0));
        assert!(get_insn_idx < unsafe { get_iseq_encoded_size(iseq) });

        // Ensure that the instruction the get_insn_idx is pointing to is in
        // fact a opt_getinlinecache instruction.
        assert_eq!(
            unsafe {
                let opcode_pc = code.add(get_insn_idx.as_usize());
                let translated_opcode: VALUE = opcode_pc.read();
                rb_vm_insn_decode(translated_opcode)
            },
            YARVINSN_opt_getinlinecache.try_into().unwrap()
        );

        // Find the matching opt_getinlinecache and invalidate all the blocks there
        // RUBY_ASSERT(insn_op_type(BIN(opt_getinlinecache), 1) == TS_IC);

        let ic_pc = unsafe { code.add(get_insn_idx.as_usize() + 2) };
        let ic_operand: IC = unsafe { ic_pc.read() }.as_mut_ptr();

        if ic == ic_operand {
            for block in take_version_list(BlockId {
                iseq,
                idx: get_insn_idx,
            }) {
                invalidate_block_version(&block);
                incr_counter!(invalidate_constant_ic_fill);
            }
        } else {
            panic!("ic->get_insn_index not set properly");
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

    use crate::asm::x86_64::jmp_ptr;

    // Stop other ractors since we are going to patch machine code.
    with_vm_lock(src_loc!(), || {
        // Make it so all live block versions are no longer valid branch targets
        unsafe { rb_yjit_for_each_iseq(Some(invalidate_all_blocks_for_tracing)) };

        extern "C" fn invalidate_all_blocks_for_tracing(iseq: IseqPtr) {
            if let Some(payload) = unsafe { load_iseq_payload(iseq) } {
                // C comment:
                //   Leaking the blocks for now since we might have situations where
                //   a different ractor is waiting for the VM lock in branch_stub_hit().
                //   If we free the block that ractor can wake up with a dangling block.
                //
                // Deviation: since we ref count the the blocks now, we might be deallocating and
                //   not leak the block.
                //
                // Empty all blocks on the iseq so we don't compile new blocks that jump to the
                // invalidated region.
                let blocks = payload.take_all_blocks();
                for blockref in blocks {
                    block_assumptions_free(&blockref);
                }
            }

            // Reset output code entry point
            unsafe { rb_iseq_reset_jit_func(iseq) };
        }

        let cb = CodegenGlobals::get_inline_cb();

        // Apply patches
        let old_pos = cb.get_write_pos();
        let patches = CodegenGlobals::take_global_inval_patches();
        for patch in &patches {
            cb.set_write_ptr(patch.inline_patch_pos);
            jmp_ptr(cb, patch.outlined_target_pos);

            // FIXME: Can't easily check we actually wrote out the JMP at the moment.
            // assert!(!cb.has_dropped_bytes(), "patches should have space and jump offsets should fit in JMP rel32");
        }
        cb.set_pos(old_pos);

        // Freeze invalidated part of the codepage. We only want to wait for
        // running instances of the code to exit from now on, so we shouldn't
        // change the code. There could be other ractors sleeping in
        // branch_stub_hit(), for example. We could harden this by changing memory
        // protection on the frozen range.
        assert!(
            CodegenGlobals::get_inline_frozen_bytes() <= old_pos,
            "frozen bytes should increase monotonically"
        );
        CodegenGlobals::set_inline_frozen_bytes(old_pos);

        CodegenGlobals::get_outlined_cb()
            .unwrap()
            .mark_all_executable();
        cb.mark_all_executable();
    });
}
