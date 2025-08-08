// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{cruby::*, gc::get_or_create_iseq_payload, options::get_option};
use crate::distribution::{Distribution, DistributionSummary};

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
pub extern "C" fn rb_zjit_profile_insn(bare_opcode: u32, ec: EcPtr) {
    with_vm_lock(src_loc!(), || {
        let mut profiler = Profiler::new(ec);
        profile_insn(&mut profiler, bare_opcode as ruby_vminsn_type);
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

const DISTRIBUTION_SIZE: usize = 4;

pub type TypeDistribution = Distribution<ProfiledType, DISTRIBUTION_SIZE>;

pub type TypeDistributionSummary = DistributionSummary<ProfiledType, DISTRIBUTION_SIZE>;

/// Profile the Type of top-`n` stack operands
fn profile_operands(profiler: &mut Profiler, profile: &mut IseqProfile, n: usize) {
    let types = &mut profile.opnd_types[profiler.insn_idx];
    if types.is_empty() {
        types.resize(n, TypeDistribution::new());
    }
    for i in 0..n {
        let obj = profiler.peek_at_stack((n - i - 1) as isize);
        // TODO(max): Handle GC-hidden classes like Array, Hash, etc and make them look normal or
        // drop them or something
        let ty = ProfiledType::new(obj.class_of(), obj.shape_id_of());
        unsafe { rb_gc_writebarrier(profiler.iseq.into(), ty.class()) };
        types[i].observe(ty);
    }
}

/// opt_send_without_block/opt_plus/... should store:
/// * the class of the receiver, so we can do method lookup
/// * the shape of the receiver, so we can optimize ivar lookup
///
/// with those two, pieces of information, we can also determine when an object is an immediate:
/// * Integer + SPECIAL_CONST_SHAPE_ID == Fixnum
/// * Float + SPECIAL_CONST_SHAPE_ID == Flonum
/// * Symbol + SPECIAL_CONST_SHAPE_ID == StaticSymbol
/// * NilClass == Nil
/// * TrueClass == True
/// * FalseClass == False
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProfiledType {
    class: VALUE,
    shape: ShapeId,
}

impl Default for ProfiledType {
    fn default() -> Self {
        Self::empty()
    }
}

impl ProfiledType {
    fn new(class: VALUE, shape: ShapeId) -> Self {
        Self { class, shape }
    }

    pub fn empty() -> Self {
        Self { class: VALUE(0), shape: INVALID_SHAPE_ID }
    }

    pub fn is_empty(&self) -> bool {
        self.class == VALUE(0)
    }

    pub fn class(&self) -> VALUE {
        self.class
    }

    pub fn shape(&self) -> ShapeId {
        self.shape
    }

    pub fn is_fixnum(&self) -> bool {
        self.class == unsafe { rb_cInteger } && self.shape == SPECIAL_CONST_SHAPE_ID
    }

    pub fn is_flonum(&self) -> bool {
        self.class == unsafe { rb_cFloat } && self.shape == SPECIAL_CONST_SHAPE_ID
    }

    pub fn is_static_symbol(&self) -> bool {
        self.class == unsafe { rb_cSymbol } && self.shape == SPECIAL_CONST_SHAPE_ID
    }

    pub fn is_nil(&self) -> bool {
        self.class == unsafe { rb_cNilClass } && self.shape == SPECIAL_CONST_SHAPE_ID
    }

    pub fn is_true(&self) -> bool {
        self.class == unsafe { rb_cTrueClass } && self.shape == SPECIAL_CONST_SHAPE_ID
    }

    pub fn is_false(&self) -> bool {
        self.class == unsafe { rb_cFalseClass } && self.shape == SPECIAL_CONST_SHAPE_ID
    }
}

#[derive(Debug)]
pub struct IseqProfile {
    /// Type information of YARV instruction operands, indexed by the instruction index
    opnd_types: Vec<Vec<TypeDistribution>>,

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
    pub fn get_operand_types(&self, insn_idx: usize) -> Option<&[TypeDistribution]> {
        self.opnd_types.get(insn_idx).map(|v| &**v)
    }

    /// Run a given callback with every object in IseqProfile
    pub fn each_object(&self, callback: impl Fn(VALUE)) {
        for operands in &self.opnd_types {
            for distribution in operands {
                for profiled_type in distribution.each_item() {
                    // If the type is a GC object, call the callback
                    callback(profiled_type.class);
                }
            }
        }
    }

    /// Run a given callback with a mutable reference to every object in IseqProfile
    pub fn each_object_mut(&mut self, callback: impl Fn(&mut VALUE)) {
        for operands in &mut self.opnd_types {
            for distribution in operands {
                for ref mut profiled_type in distribution.each_item_mut() {
                    // If the type is a GC object, call the callback
                    callback(&mut profiled_type.class);
                }
            }
        }
    }
}
