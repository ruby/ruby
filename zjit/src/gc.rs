// This module is responsible for marking/moving objects on GC.

use std::ffi::c_void;
use crate::{cruby::*, profile::IseqProfile, state::ZJITState, virtualmem::CodePtr};

/// This is all the data ZJIT stores on an ISEQ. We mark objects in this struct on GC.
#[derive(Debug)]
pub struct IseqPayload {
    /// Type information of YARV instruction operands
    pub profile: IseqProfile,

    /// JIT code address of the first block
    pub start_ptr: Option<CodePtr>,

    /// GC offsets of the JIT code. These are the addresses of objects that need to be marked.
    pub gc_offsets: Vec<CodePtr>,
}

impl IseqPayload {
    fn new(iseq_size: u32) -> Self {
        Self {
            profile: IseqProfile::new(iseq_size),
            start_ptr: None,
            gc_offsets: vec![],
        }
    }
}

/// Get the payload object associated with an iseq. Create one if none exists.
pub fn get_or_create_iseq_payload(iseq: IseqPtr) -> &'static mut IseqPayload {
    type VoidPtr = *mut c_void;

    let payload_non_null = unsafe {
        let payload = rb_iseq_get_zjit_payload(iseq);
        if payload.is_null() {
            // Allocate a new payload with Box and transfer ownership to the GC.
            // We drop the payload with Box::from_raw when the GC frees the iseq and calls us.
            // NOTE(alan): Sometimes we read from an iseq without ever writing to it.
            // We allocate in those cases anyways.
            let iseq_size = get_iseq_encoded_size(iseq);
            let new_payload = IseqPayload::new(iseq_size);
            let new_payload = Box::into_raw(Box::new(new_payload));
            rb_iseq_set_zjit_payload(iseq, new_payload as VoidPtr);

            new_payload
        } else {
            payload as *mut IseqPayload
        }
    };

    // SAFETY: we should have the VM lock and all other Ruby threads should be asleep. So we have
    // exclusive mutable access.
    // Hmm, nothing seems to stop calling this on the same
    // iseq twice, though, which violates aliasing rules.
    unsafe { payload_non_null.as_mut() }.unwrap()
}

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

/// GC callback for updating GC objects in the per-iseq payload.
/// This is a mirror of [rb_zjit_iseq_mark].
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_update_references(payload: *mut c_void) {
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
            &mut *(payload as *mut IseqPayload)
        }
    };

    // Move objects retained by profiling instructions
    payload.profile.each_object_mut(|object| {
        *object = unsafe { rb_gc_location(*object) };
    });

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
