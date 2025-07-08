// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use core::ffi::c_void;
use std::collections::HashMap;

use crate::{cruby::*, hir_type::{types::{Empty, Fixnum}, Type}, virtualmem::CodePtr};

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

    // Get an instruction operand that sits next to the opcode at PC.
    fn insn_opnd(&self, idx: usize) -> VALUE {
        unsafe { get_cfp_pc(self.cfp).add(1 + idx).read() }
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
        YARVINSN_opt_nil_p => profile_operands(profiler, 1),
        YARVINSN_opt_plus  => profile_operands(profiler, 2),
        YARVINSN_opt_minus => profile_operands(profiler, 2),
        YARVINSN_opt_mult  => profile_operands(profiler, 2),
        YARVINSN_opt_div   => profile_operands(profiler, 2),
        YARVINSN_opt_mod   => profile_operands(profiler, 2),
        YARVINSN_opt_eq    => profile_operands(profiler, 2),
        YARVINSN_opt_neq   => profile_operands(profiler, 2),
        YARVINSN_opt_lt    => profile_operands(profiler, 2),
        YARVINSN_opt_le    => profile_operands(profiler, 2),
        YARVINSN_opt_gt    => profile_operands(profiler, 2),
        YARVINSN_opt_ge    => profile_operands(profiler, 2),
        YARVINSN_opt_send_without_block => {
            let cd: *const rb_call_data = profiler.insn_opnd(0).as_ptr();
            let argc = unsafe { vm_ci_argc((*cd).ci) };
            // Profile all the arguments and self (+1).
            profile_operands(profiler, (argc + 1) as usize);
        }
        _ => {}
    }
}

/// Profile the Type of top-`n` stack operands
fn profile_operands(profiler: &mut Profiler, n: usize) {
    let payload = get_or_create_iseq_payload(profiler.iseq);
    let mut types = if let Some(types) = payload.opnd_types.get(&profiler.insn_idx) {
        types.clone()
    } else {
        vec![Empty; n]
    };

    for i in 0..n {
        let opnd_type = Type::from_value(profiler.peek_at_stack((n - i - 1) as isize));
        types[i] = types[i].union(opnd_type);
    }

    payload.opnd_types.insert(profiler.insn_idx, types);
}

/// This is all the data ZJIT stores on an iseq. This will be dynamically allocated by C code
/// C code should pass an &mut IseqPayload to us when calling into ZJIT.
#[derive(Default, Debug)]
pub struct IseqPayload {
    /// Type information of YARV instruction operands, indexed by the instruction index
    opnd_types: HashMap<usize, Vec<Type>>,

    /// JIT code address of the first block
    pub start_ptr: Option<CodePtr>,
}

impl IseqPayload {
    /// Get profiled operand types for a given instruction index
    pub fn get_operand_types(&self, insn_idx: usize) -> Option<&[Type]> {
        self.opnd_types.get(&insn_idx).map(|types| types.as_slice())
    }

    /// Return true if top-two stack operands are Fixnums
    pub fn have_two_fixnums(&self, insn_idx: usize) -> bool {
        match self.get_operand_types(insn_idx) {
            Some([left, right]) => left.is_subtype(Fixnum) && right.is_subtype(Fixnum),
            _ => false,
        }
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
