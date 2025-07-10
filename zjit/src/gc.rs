// This module is responsible for marking/moving objects on GC.

use std::ffi::c_void;
use crate::{cruby::*, profile::IseqProfile, virtualmem::CodePtr};

/// This is all the data ZJIT stores on an ISEQ. We mark objects in this struct on GC.
#[derive(Debug)]
pub struct IseqPayload {
    /// Type information of YARV instruction operands
    pub profile: IseqProfile,

    /// JIT code address of the first block
    pub start_ptr: Option<CodePtr>,

    // TODO: Add references to GC offsets in JIT code
}

impl IseqPayload {
    fn new(iseq: IseqPtr) -> Self {
        Self { profile: IseqProfile::new(iseq), start_ptr: None }
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
            let new_payload = IseqPayload::new(iseq);
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

    payload.profile.each_object(|object| {
        // TODO: Implement `rb_zjit_iseq_update_references` and use `rb_gc_mark_movable`
        unsafe { rb_gc_mark(object); }
    });

    // TODO: Mark objects in JIT code
}

/// GC callback for updating GC objects in the per-iseq payload.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_update_references(_payload: *mut c_void) {
    // TODO: let `rb_zjit_iseq_mark` use `rb_gc_mark_movable`
    // and update references using `rb_gc_location` here.
}
