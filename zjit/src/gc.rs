//! This module is responsible for marking/moving objects on GC.

use std::{ffi::c_void, ops::Range};
use crate::{cruby::*, state::ZJITState, stats::with_time_stat, virtualmem::CodePtr};
use crate::payload::{IseqPayload, get_or_create_iseq_payload, payload_ptr_as_mut};
use crate::stats::Counter::gc_time_ns;
use crate::state::gc_mark_raw_samples;

/// GC callback for marking GC objects in the per-ISEQ payload.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_mark(payload: *mut c_void) {
    let payload = if payload.is_null() {
        return; // nothing to mark
    } else {
        // SAFETY: The GC takes the VM lock while marking, which
        // we assert, so we should be synchronized and data race free.
        //
        // For aliasing, having the VM lock hopefully also implies that no one
        // else has an overlapping &mut IseqPayload.
        unsafe {
            rb_assert_holding_vm_lock();
            &*(payload as *const IseqPayload)
        }
    };
    with_time_stat(gc_time_ns, || iseq_mark(payload));
}

/// GC callback for updating GC objects in the per-ISEQ payload.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_update_references(payload: *mut c_void) {
    let payload = if payload.is_null() {
        return; // nothing to update
    } else {
        // SAFETY: The GC takes the VM lock while marking, which
        // we assert, so we should be synchronized and data race free.
        //
        // For aliasing, having the VM lock hopefully also implies that no one
        // else has an overlapping &mut IseqPayload.
        unsafe {
            rb_assert_holding_vm_lock();
            &mut *(payload as *mut IseqPayload)
        }
    };
    with_time_stat(gc_time_ns, || iseq_update_references(payload));
}

/// GC callback for finalizing an ISEQ
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_free(iseq: IseqPtr) {
    if !ZJITState::has_instance() {
        return;
    }
    // TODO(Shopify/ruby#682): Free `IseqPayload`
    let invariants = ZJITState::get_invariants();
    invariants.forget_iseq(iseq);
}

/// GC callback for finalizing a CME
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_cme_free(cme: *const rb_callable_method_entry_struct) {
    if !ZJITState::has_instance() {
        return;
    }
    let invariants = ZJITState::get_invariants();
    invariants.forget_cme(cme);
}

/// GC callback for finalizing a class
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_klass_free(klass: VALUE) {
    if !ZJITState::has_instance() {
        return;
    }
    let invariants = ZJITState::get_invariants();
    invariants.forget_klass(klass);
}

/// GC callback for updating object references after all object moves
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_root_update_references() {
    if !ZJITState::has_instance() {
        return;
    }
    let invariants = ZJITState::get_invariants();
    invariants.update_references();
}

fn iseq_mark(payload: &IseqPayload) {
    // Mark objects retained by profiling instructions
    payload.profile.each_object(|object| {
        unsafe { rb_gc_mark_movable(object); }
    });

    // Mark objects baked in JIT code
    let cb = ZJITState::get_code_block();
    for &offset in payload.gc_offsets.iter() {
        let value_ptr: *const u8 = offset.raw_ptr(cb);
        // Creating an unaligned pointer is well defined unlike in C.
        let value_ptr = value_ptr as *const VALUE;

        unsafe {
            let object = value_ptr.read_unaligned();
            rb_gc_mark_movable(object);
        }
    }
}

/// This is a mirror of [iseq_mark].
fn iseq_update_references(payload: &mut IseqPayload) {
    // Move objects retained by profiling instructions
    payload.profile.each_object_mut(|old_object| {
        let new_object = unsafe { rb_gc_location(*old_object) };
        if *old_object != new_object {
            *old_object = new_object;
        }
    });

    // Move ISEQ references in IseqCall
    for iseq_call in payload.iseq_calls.iter_mut() {
        let old_iseq = iseq_call.iseq.get();
        let new_iseq = unsafe { rb_gc_location(VALUE(old_iseq as usize)) }.0 as IseqPtr;
        if old_iseq != new_iseq {
            iseq_call.iseq.set(new_iseq);
        }
    }

    // Move objects baked in JIT code
    let cb = ZJITState::get_code_block();
    for &offset in payload.gc_offsets.iter() {
        let value_ptr: *const u8 = offset.raw_ptr(cb);
        // Creating an unaligned pointer is well defined unlike in C.
        let value_ptr = value_ptr as *const VALUE;

        let object = unsafe { value_ptr.read_unaligned() };
        let new_addr = unsafe { rb_gc_location(object) };

        // Only write when the VALUE moves, to be copy-on-write friendly.
        if new_addr != object {
            for (byte_idx, &byte) in new_addr.as_u64().to_le_bytes().iter().enumerate() {
                let byte_code_ptr = offset.add_bytes(byte_idx);
                cb.write_mem(byte_code_ptr, byte).expect("patching existing code should be within bounds");
            }
        }
    }
    cb.mark_all_executable();
}

/// Append a set of gc_offsets to the iseq's payload
pub fn append_gc_offsets(iseq: IseqPtr, offsets: &Vec<CodePtr>) {
    let payload = get_or_create_iseq_payload(iseq);
    payload.gc_offsets.extend(offsets);

    // Call writebarrier on each newly added value
    let cb = ZJITState::get_code_block();
    for &offset in offsets.iter() {
        let value_ptr: *const u8 = offset.raw_ptr(cb);
        let value_ptr = value_ptr as *const VALUE;
        unsafe {
            let object = value_ptr.read_unaligned();
            rb_gc_writebarrier(iseq.into(), object);
        }
    }
}

/// Remove GC offsets that overlap with a given removed_range.
/// We do this when invalidation rewrites some code with a jump instruction
/// and GC offsets are corrupted by the rewrite, assuming no on-stack code
/// will step into the instruction with the GC offsets after invalidation.
pub fn remove_gc_offsets(payload_ptr: *mut IseqPayload, removed_range: &Range<CodePtr>) {
    let payload = payload_ptr_as_mut(payload_ptr);
    payload.gc_offsets.retain(|&gc_offset| {
        let offset_range = gc_offset..(gc_offset.add_bytes(SIZEOF_VALUE));
        !ranges_overlap(&offset_range, removed_range)
    });
}

/// Return true if given `Range<CodePtr>` ranges overlap with each other
fn ranges_overlap<T>(left: &Range<T>, right: &Range<T>) -> bool where T: PartialOrd {
    left.start < right.end && right.start < left.end
}

/// Callback for marking GC objects inside [crate::invariants::Invariants].
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_root_mark() {
    gc_mark_raw_samples();
}
