// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{cruby::*, gc::get_or_create_iseq_payload, hir_type::{types::{Empty}, Type}, options::get_option};

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
pub extern "C" fn rb_zjit_profile_insn(bare_opcode: ruby_vminsn_type, ec: EcPtr) {
    with_vm_lock(src_loc!(), || {
        let mut profiler = Profiler::new(ec);
        profile_insn(&mut profiler, bare_opcode);
    });
}

/// Profile a YARV instruction
fn profile_insn(profiler: &mut Profiler, bare_opcode: ruby_vminsn_type) {
    let profile = &mut get_or_create_iseq_payload(profiler.iseq).profile;
    match bare_opcode {
        YARVINSN_opt_nil_p => profile_operands(profiler, profile, 1),
        YARVINSN_opt_plus  => profile_operands(profiler, profile, 2),
        YARVINSN_opt_minus => profile_operands(profiler, profile, 2),
        YARVINSN_opt_mult  => profile_operands(profiler, profile, 2),
        YARVINSN_opt_div   => profile_operands(profiler, profile, 2),
        YARVINSN_opt_mod   => profile_operands(profiler, profile, 2),
        YARVINSN_opt_eq    => profile_operands(profiler, profile, 2),
        YARVINSN_opt_neq   => profile_operands(profiler, profile, 2),
        YARVINSN_opt_lt    => profile_operands(profiler, profile, 2),
        YARVINSN_opt_le    => profile_operands(profiler, profile, 2),
        YARVINSN_opt_gt    => profile_operands(profiler, profile, 2),
        YARVINSN_opt_ge    => profile_operands(profiler, profile, 2),
        YARVINSN_opt_and   => profile_operands(profiler, profile, 2),
        YARVINSN_opt_or    => profile_operands(profiler, profile, 2),
        YARVINSN_opt_send_without_block => {
            let cd: *const rb_call_data = profiler.insn_opnd(0).as_ptr();
            let argc = unsafe { vm_ci_argc((*cd).ci) };
            // Profile all the arguments and self (+1).
            profile_operands(profiler, profile, (argc + 1) as usize);
        }
        _ => {}
    }

    // Once we profile the instruction num_profiles times, we stop profiling it.
    profile.num_profiles[profiler.insn_idx] = profile.num_profiles[profiler.insn_idx].saturating_add(1);
    if profile.num_profiles[profiler.insn_idx] == get_option!(num_profiles) {
        unsafe { rb_zjit_iseq_insn_set(profiler.iseq, profiler.insn_idx as u32, bare_opcode); }
    }
}

/// Profile the Type of top-`n` stack operands
fn profile_operands(profiler: &mut Profiler, profile: &mut IseqProfile, n: usize) {
    let types = &mut profile.opnd_types[profiler.insn_idx];
    if types.len() <= n {
        types.resize(n, Empty);
    }
    for i in 0..n {
        let opnd_type = Type::from_value(profiler.peek_at_stack((n - i - 1) as isize));
        types[i] = types[i].union(opnd_type);
    }
    // In the loop above, we probably added a new reference to the profile through
    // the VALUE in Type. It's messy and relatively slow to conditionally run a
    // write barrier for each Type, so just remember to re-mark the iseq.
    unsafe { rb_gc_writebarrier_remember(profiler.iseq.into()) };
}

#[derive(Debug)]
pub struct IseqProfile {
    /// Type information of YARV instruction operands, indexed by the instruction index
    opnd_types: Vec<Vec<Type>>,

    /// Number of profiled executions for each YARV instruction, indexed by the instruction index
    num_profiles: Vec<u8>,
}

impl IseqProfile {
    pub fn new(iseq_size: u32) -> Self {
        Self {
            opnd_types: vec![vec![]; iseq_size as usize],
            num_profiles: vec![0; iseq_size as usize],
        }
    }

    /// Get profiled operand types for a given instruction index
    pub fn get_operand_types(&self, insn_idx: usize) -> Option<&[Type]> {
        self.opnd_types.get(insn_idx).map(|v| &**v)
    }

    /// Run a given callback with every object in IseqProfile
    pub fn each_object(&self, callback: impl Fn(VALUE)) {
        for types in &self.opnd_types {
            for opnd_type in types {
                if let Some(object) = opnd_type.gc_object() {
                    callback(object);
                }
            }
        }
    }

    /// Run a given callback with a mutable reference to every object in IseqProfile
    pub fn each_object_mut(&mut self, callback: impl Fn(&mut VALUE)) {
        for types in self.opnd_types.iter_mut() {
            for opnd_type in types.iter_mut() {
                if let Some(object) = opnd_type.gc_object_mut() {
                    callback(object);
                }
            }
        }
    }
}
