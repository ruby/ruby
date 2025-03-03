// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use core::ffi::c_void;
use std::collections::HashMap;

use crate::cruby::*;

/// Ephemeral state for profiling runtime information
struct Profiler {
    cfp: CfpPtr,
    iseq: IseqPtr,
    insn_idx: usize,
}

impl Profiler {
    fn new(ec: EcPtr) -> Self {
        let cfp = unsafe { get_ec_cfp(ec) };
        let iseq = unsafe { get_cfp_iseq(cfp) };
        Profiler {
            cfp,
            iseq,
            insn_idx: unsafe { get_cfp_pc(cfp).offset_from(get_iseq_body_iseq_encoded(iseq)) as usize },
        }
    }

    // Peek at the nth topmost value on the Ruby stack.
    // Returns the topmost value when n == 0.
    fn peek_at_stack(&self, n: isize) -> VALUE {
        unsafe {
            let sp: *mut VALUE = get_cfp_sp(self.cfp);
            *(sp.offset(-1 - n))
        }
    }
}

/// API called from zjit_* instruction. opcode is the bare (non-zjit_*) instruction.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_profile_insn(opcode: ruby_vminsn_type, ec: EcPtr) {
    with_vm_lock(src_loc!(), || {
        let mut profiler = Profiler::new(ec);
        profile_insn(&mut profiler, opcode);
    });
}

/// Profile a YARV instruction
fn profile_insn(profiler: &mut Profiler, opcode: ruby_vminsn_type) {
    match opcode {
        YARVINSN_opt_plus => profile_opt_plus(profiler),
        _ => {}
    }
}

/// Profile opt_plus instruction
fn profile_opt_plus(profiler: &mut Profiler) {
    let recv = profiler.peek_at_stack(1);
    let obj = profiler.peek_at_stack(0);

    let payload = get_or_create_iseq_payload(profiler.iseq);
    payload.insns.insert(profiler.insn_idx, InsnProfile::OptPlus {
        // TODO: profile the type and union it with past results
        recv_is_fixnum: recv.fixnum_p(),
        obj_is_fixnum: obj.fixnum_p(),
    });
}

/// Profiling information for each YARV instruction
pub enum InsnProfile {
    // TODO: Change it to { recv: Type, obj: Type } once the type lattice is merged
    OptPlus { recv_is_fixnum: bool, obj_is_fixnum: bool },
}

/// This is all the data YJIT stores on an iseq. This will be dynamically allocated by C code
/// C code should pass an &mut IseqPayload to us when calling into ZJIT.
#[derive(Default)]
pub struct IseqPayload {
    /// Profiling information for each YARV instruction, indexed by the instruction index
    insns: HashMap<usize, InsnProfile>,
}

impl IseqPayload {
    /// Get the instruction profile for a given instruction index
    pub fn get_insn_profile(&self, insn_idx: usize) -> Option<&InsnProfile> {
        self.insns.get(&insn_idx)
    }
}

/// Get the payload for an iseq. For safety it's up to the caller to ensure the returned `&mut`
/// upholds aliasing rules and that the argument is a valid iseq.
pub fn get_iseq_payload(iseq: IseqPtr) -> Option<&'static mut IseqPayload> {
    let payload = unsafe { rb_iseq_get_zjit_payload(iseq) };
    let payload: *mut IseqPayload = payload.cast();
    unsafe { payload.as_mut() }
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
            let new_payload = IseqPayload::default();
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
