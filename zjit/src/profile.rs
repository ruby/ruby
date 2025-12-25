//! Profiler for runtime information.

// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::{cruby::*, payload::get_or_create_iseq_payload, options::{get_option, NumProfiles}};
use crate::distribution::{Distribution, DistributionSummary};
use crate::stats::Counter::profile_time_ns;
use crate::stats::with_time_stat;

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

    fn peek_at_self(&self) -> VALUE {
        unsafe { rb_get_cfp_self(self.cfp) }
    }

    fn peek_at_block_handler(&self) -> VALUE {
        unsafe { rb_vm_get_untagged_block_handler(self.cfp) }
    }
}

/// API called from zjit_* instruction. opcode is the bare (non-zjit_*) instruction.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_profile_insn(bare_opcode: u32, ec: EcPtr) {
    with_vm_lock(src_loc!(), || {
        with_time_stat(profile_time_ns, || profile_insn(bare_opcode as ruby_vminsn_type, ec));
    });
}

/// Profile a YARV instruction
fn profile_insn(bare_opcode: ruby_vminsn_type, ec: EcPtr) {
    let profiler = &mut Profiler::new(ec);
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
        YARVINSN_opt_empty_p => profile_operands(profiler, profile, 1),
        YARVINSN_opt_aref  => profile_operands(profiler, profile, 2),
        YARVINSN_opt_ltlt  => profile_operands(profiler, profile, 2),
        YARVINSN_opt_aset  => profile_operands(profiler, profile, 3),
        YARVINSN_opt_not   => profile_operands(profiler, profile, 1),
        YARVINSN_getinstancevariable => profile_self(profiler, profile),
        YARVINSN_setinstancevariable => profile_self(profiler, profile),
        YARVINSN_definedivar   => profile_self(profiler, profile),
        YARVINSN_opt_regexpmatch2    => profile_operands(profiler, profile, 2),
        YARVINSN_objtostring   => profile_operands(profiler, profile, 1),
        YARVINSN_opt_length    => profile_operands(profiler, profile, 1),
        YARVINSN_opt_size      => profile_operands(profiler, profile, 1),
        YARVINSN_opt_succ      => profile_operands(profiler, profile, 1),
        YARVINSN_invokeblock   => profile_block_handler(profiler, profile),
        YARVINSN_opt_send_without_block | YARVINSN_send => {
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

    for (i, profile_type) in types.iter_mut().enumerate() {
        let obj = profiler.peek_at_stack((n - i - 1) as isize);
        // TODO(max): Handle GC-hidden classes like Array, Hash, etc and make them look normal or
        // drop them or something
        let ty = ProfiledType::new(obj);
        VALUE::from(profiler.iseq).write_barrier(ty.class());
        profile_type.observe(ty);
    }
}

fn profile_self(profiler: &mut Profiler, profile: &mut IseqProfile) {
    let types = &mut profile.opnd_types[profiler.insn_idx];
    if types.is_empty() {
        types.resize(1, TypeDistribution::new());
    }
    let obj = profiler.peek_at_self();
    // TODO(max): Handle GC-hidden classes like Array, Hash, etc and make them look normal or
    // drop them or something
    let ty = ProfiledType::new(obj);
    VALUE::from(profiler.iseq).write_barrier(ty.class());
    types[0].observe(ty);
}

fn profile_block_handler(profiler: &mut Profiler, profile: &mut IseqProfile) {
    let types = &mut profile.opnd_types[profiler.insn_idx];
    if types.is_empty() {
        types.resize(1, TypeDistribution::new());
    }
    let obj = profiler.peek_at_block_handler();
    let ty = ProfiledType::object(obj);
    VALUE::from(profiler.iseq).write_barrier(ty.class());
    types[0].observe(ty);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Flags(u32);

impl Flags {
    const NONE: u32 = 0;
    const IS_IMMEDIATE: u32 = 1 << 0;
    /// Object is embedded and the ivar index lands within the object
    const IS_EMBEDDED: u32 = 1 << 1;
    /// Object is a T_OBJECT
    const IS_T_OBJECT: u32 = 1 << 2;
    /// Object is a struct with embedded fields
    const IS_STRUCT_EMBEDDED: u32 = 1 << 3;
    /// Set if the ProfiledType is used for profiling specific objects, not just classes/shapes
    const IS_OBJECT_PROFILING: u32 = 1 << 4;

    pub fn none() -> Self { Self(Self::NONE) }

    pub fn immediate() -> Self { Self(Self::IS_IMMEDIATE) }
    pub fn is_immediate(self) -> bool { (self.0 & Self::IS_IMMEDIATE) != 0 }
    pub fn is_embedded(self) -> bool { (self.0 & Self::IS_EMBEDDED) != 0 }
    pub fn is_t_object(self) -> bool { (self.0 & Self::IS_T_OBJECT) != 0 }
    pub fn is_struct_embedded(self) -> bool { (self.0 & Self::IS_STRUCT_EMBEDDED) != 0 }
    pub fn is_object_profiling(self) -> bool { (self.0 & Self::IS_OBJECT_PROFILING) != 0 }
}

/// opt_send_without_block/opt_plus/... should store:
/// * the class of the receiver, so we can do method lookup
/// * the shape of the receiver, so we can optimize ivar lookup
///
/// with those two, pieces of information, we can also determine when an object is an immediate:
/// * Integer + IS_IMMEDIATE == Fixnum
/// * Float + IS_IMMEDIATE == Flonum
/// * Symbol + IS_IMMEDIATE == StaticSymbol
/// * NilClass == Nil
/// * TrueClass == True
/// * FalseClass == False
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProfiledType {
    class: VALUE,
    shape: ShapeId,
    flags: Flags,
}

impl Default for ProfiledType {
    fn default() -> Self {
        Self::empty()
    }
}

impl ProfiledType {
    /// Profile the object itself
    fn object(obj: VALUE) -> Self {
        let mut flags = Flags::none();
        flags.0 |= Flags::IS_OBJECT_PROFILING;
        Self { class: obj, shape: INVALID_SHAPE_ID, flags }
    }

    /// Profile the class and shape of the given object
    fn new(obj: VALUE) -> Self {
        if obj == Qfalse {
            return Self { class: unsafe { rb_cFalseClass },
                          shape: INVALID_SHAPE_ID,
                          flags: Flags::immediate() };
        }
        if obj == Qtrue {
            return Self { class: unsafe { rb_cTrueClass },
                          shape: INVALID_SHAPE_ID,
                          flags: Flags::immediate() };
        }
        if obj == Qnil {
            return Self { class: unsafe { rb_cNilClass },
                          shape: INVALID_SHAPE_ID,
                          flags: Flags::immediate() };
        }
        if obj.fixnum_p() {
            return Self { class: unsafe { rb_cInteger },
                          shape: INVALID_SHAPE_ID,
                          flags: Flags::immediate() };
        }
        if obj.flonum_p() {
            return Self { class: unsafe { rb_cFloat },
                          shape: INVALID_SHAPE_ID,
                          flags: Flags::immediate() };
        }
        if obj.static_sym_p() {
            return Self { class: unsafe { rb_cSymbol },
                          shape: INVALID_SHAPE_ID,
                          flags: Flags::immediate() };
        }
        let mut flags = Flags::none();
        if obj.embedded_p() {
            flags.0 |= Flags::IS_EMBEDDED;
        }
        if obj.struct_embedded_p() {
            flags.0 |= Flags::IS_STRUCT_EMBEDDED;
        }
        if unsafe { RB_TYPE_P(obj, RUBY_T_OBJECT) } {
            flags.0 |= Flags::IS_T_OBJECT;
        }
        Self { class: obj.class_of(), shape: obj.shape_id_of(), flags }
    }

    pub fn empty() -> Self {
        Self { class: VALUE(0), shape: INVALID_SHAPE_ID, flags: Flags::none() }
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

    pub fn flags(&self) -> Flags {
        self.flags
    }

    pub fn is_fixnum(&self) -> bool {
        self.class == unsafe { rb_cInteger } && self.flags.is_immediate()
    }

    pub fn is_string(&self) -> bool {
        if self.flags.is_object_profiling() {
            panic!("should not call is_string on object-profiled ProfiledType");
        }
        // Fast paths for immediates and exact-class
        if self.flags.is_immediate() {
            return false;
        }

        let string = unsafe { rb_cString };
        if self.class == string{
            return true;
        }

        self.class.is_subclass_of(string) == ClassRelationship::Subclass
    }

    pub fn is_flonum(&self) -> bool {
        self.class == unsafe { rb_cFloat } && self.flags.is_immediate()
    }

    pub fn is_static_symbol(&self) -> bool {
        self.class == unsafe { rb_cSymbol } && self.flags.is_immediate()
    }

    pub fn is_nil(&self) -> bool {
        self.class == unsafe { rb_cNilClass } && self.flags.is_immediate()
    }

    pub fn is_true(&self) -> bool {
        self.class == unsafe { rb_cTrueClass } && self.flags.is_immediate()
    }

    pub fn is_false(&self) -> bool {
        self.class == unsafe { rb_cFalseClass } && self.flags.is_immediate()
    }
}

#[derive(Debug)]
pub struct IseqProfile {
    /// Type information of YARV instruction operands, indexed by the instruction index
    opnd_types: Vec<Vec<TypeDistribution>>,

    /// Number of profiled executions for each YARV instruction, indexed by the instruction index
    num_profiles: Vec<NumProfiles>,
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

#[cfg(test)]
mod tests {
    use crate::cruby::*;

    #[test]
    fn can_profile_block_handler() {
        with_rubyvm(|| eval("
            def foo = yield
            foo rescue 0
            foo rescue 0
        "));
    }
}
