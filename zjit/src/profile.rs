//! Profiler for runtime information.

// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use std::collections::HashMap;
use crate::{cruby::*, payload::get_or_create_iseq_payload, options::{get_option, NumProfiles}};
use crate::distribution::{Distribution, DistributionSummary};
use crate::stats::Counter::profile_time_ns;
use crate::stats::with_time_stat;

/// Ephemeral state for profiling runtime information
struct Profiler {
    cfp: CfpPtr,
    iseq: IseqPtr,
    insn_idx: YarvInsnIdx,
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
        YARVINSN_getblockparamproxy => profile_getblockparamproxy(profiler, profile),
        YARVINSN_invokesuper   => profile_invokesuper(profiler, profile),
        YARVINSN_opt_send_without_block | YARVINSN_send => {
            let cd: *const rb_call_data = profiler.insn_opnd(0).as_ptr();
            let argc = unsafe { vm_ci_argc((*cd).ci) };
            // Profile all the arguments and self (+1).
            profile_operands(profiler, profile, (argc + 1) as usize);
        }
        YARVINSN_splatkw => profile_operands(profiler, profile, 2),
        _ => {}
    }

    // Once we profile the instruction enough times, we stop profiling it.
    let entry = profile.entry_mut(profiler.insn_idx);
    entry.profiles_remaining = entry.profiles_remaining.saturating_sub(1);
    if entry.profiles_remaining == 0 {
        unsafe { rb_zjit_iseq_insn_set(profiler.iseq, profiler.insn_idx as u32, bare_opcode); }
    }
}

const DISTRIBUTION_SIZE: usize = 4;

pub type TypeDistribution = Distribution<ProfiledType, DISTRIBUTION_SIZE>;

pub type TypeDistributionSummary = DistributionSummary<ProfiledType, DISTRIBUTION_SIZE>;

/// Profile the Type of top-`n` stack operands
fn profile_operands(profiler: &mut Profiler, profile: &mut IseqProfile, n: usize) {
    let entry = profile.entry_mut(profiler.insn_idx);
    if entry.opnd_types.is_empty() {
        entry.opnd_types.resize(n, TypeDistribution::new());
    }

    for (i, profile_type) in entry.opnd_types.iter_mut().enumerate() {
        let obj = profiler.peek_at_stack((n - i - 1) as isize);
        // TODO(max): Handle GC-hidden classes like Array, Hash, etc and make them look normal or
        // drop them or something
        let ty = ProfiledType::new(obj);
        VALUE::from(profiler.iseq).write_barrier(ty.class());
        profile_type.observe(ty);
    }
}

fn profile_self(profiler: &mut Profiler, profile: &mut IseqProfile) {
    let entry = profile.entry_mut(profiler.insn_idx);
    if entry.opnd_types.is_empty() {
        entry.opnd_types.resize(1, TypeDistribution::new());
    }
    let obj = profiler.peek_at_self();
    // TODO(max): Handle GC-hidden classes like Array, Hash, etc and make them look normal or
    // drop them or something
    let ty = ProfiledType::new(obj);
    VALUE::from(profiler.iseq).write_barrier(ty.class());
    entry.opnd_types[0].observe(ty);
}

fn profile_block_handler(profiler: &mut Profiler, profile: &mut IseqProfile) {
    let entry = profile.entry_mut(profiler.insn_idx);
    if entry.opnd_types.is_empty() {
        entry.opnd_types.resize(1, TypeDistribution::new());
    }
    let obj = profiler.peek_at_block_handler();
    let ty = ProfiledType::object(obj);
    VALUE::from(profiler.iseq).write_barrier(ty.class());
    entry.opnd_types[0].observe(ty);
}

fn profile_getblockparamproxy(profiler: &mut Profiler, profile: &mut IseqProfile) {
    let entry = profile.entry_mut(profiler.insn_idx);
    if entry.opnd_types.is_empty() {
        entry.opnd_types.resize(1, TypeDistribution::new());
    }

    let level = profiler.insn_opnd(1).as_u32();
    let ep = unsafe { get_cfp_ep_level(profiler.cfp, level) };
    let block_handler = unsafe { *ep.offset(VM_ENV_DATA_INDEX_SPECVAL as isize) };
    let untagged = unsafe { rb_vm_untag_block_handler(block_handler) };

    let ty = ProfiledType::object(untagged);
    VALUE::from(profiler.iseq).write_barrier(ty.class());
    entry.opnd_types[0].observe(ty);
}

fn profile_invokesuper(profiler: &mut Profiler, profile: &mut IseqProfile) {
    let cme = unsafe { rb_vm_frame_method_entry(profiler.cfp) };
    let cme_value = VALUE(cme as usize);  // CME is a T_IMEMO, which is a VALUE

    profile.super_cme.entry(profiler.insn_idx)
        .or_insert_with(|| TypeDistribution::new()).observe(ProfiledType::object(cme_value));

    unsafe { rb_gc_writebarrier(profiler.iseq.into(), cme_value) };

    let cd: *const rb_call_data = profiler.insn_opnd(0).as_ptr();
    let argc = unsafe { vm_ci_argc((*cd).ci) };

    // Profile all the arguments and self (+1).
    profile_operands(profiler, profile, (argc + 1) as usize);
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
    /// Class/module fields_obj is embedded (or absent)
    const IS_FIELDS_EMBEDDED: u32 = 1 << 5;
    /// Object is a T_CLASS
    const IS_T_CLASS: u32 = 1 << 6;
    /// Object is a T_MODULE
    const IS_T_MODULE: u32 = 1 << 7;
    /// Object is a typed T_DATA (RTYPEDDATA_P)
    const IS_TYPED_DATA: u32 = 1 << 8;

    pub fn none() -> Self { Self(Self::NONE) }

    pub fn immediate() -> Self { Self(Self::IS_IMMEDIATE) }
    pub fn is_immediate(self) -> bool { (self.0 & Self::IS_IMMEDIATE) != 0 }
    pub fn is_embedded(self) -> bool { (self.0 & Self::IS_EMBEDDED) != 0 }
    pub fn is_t_object(self) -> bool { (self.0 & Self::IS_T_OBJECT) != 0 }
    pub fn is_struct_embedded(self) -> bool { (self.0 & Self::IS_STRUCT_EMBEDDED) != 0 }
    pub fn is_object_profiling(self) -> bool { (self.0 & Self::IS_OBJECT_PROFILING) != 0 }
    pub fn is_fields_embedded(self) -> bool { (self.0 & Self::IS_FIELDS_EMBEDDED) != 0 }
    pub fn is_t_class(self) -> bool { (self.0 & Self::IS_T_CLASS) != 0 }
    pub fn is_t_module(self) -> bool { (self.0 & Self::IS_T_MODULE) != 0 }
    pub fn is_typed_data(self) -> bool { (self.0 & Self::IS_TYPED_DATA) != 0 }
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
        if unsafe { RB_TYPE_P(obj, RUBY_T_CLASS) } {
            flags.0 |= Flags::IS_T_CLASS;
            if obj.class_fields_embedded_p() {
                flags.0 |= Flags::IS_FIELDS_EMBEDDED;
            }
        }
        if unsafe { RB_TYPE_P(obj, RUBY_T_MODULE) } {
            flags.0 |= Flags::IS_T_MODULE;
            if obj.class_fields_embedded_p() {
                flags.0 |= Flags::IS_FIELDS_EMBEDDED;
            }
        }
        if obj.typed_data_p() {
            flags.0 |= Flags::IS_TYPED_DATA;
            if obj.typed_data_fields_embedded_p() {
                flags.0 |= Flags::IS_FIELDS_EMBEDDED;
            }
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

    /// For ivar access, you need to know the index in the fields array (described by the shape)
    /// and the way to get the fields array (described by the builtin type). Both pieces of
    /// information are on the `RBasic::flags` field. This method returns expected masked flags
    /// for guarding.
    pub fn rbasic_flags_and_mask(&self) -> (u64, u64) {
        let shape_flag_shift = u64::from(RB_SHAPE_FLAG_SHIFT);
        let (shape, shape_mask) = (u64::from(self.shape().0) << shape_flag_shift, !0 << shape_flag_shift);
        let (builtin_type, type_mask) = if self.flags().is_t_object() {
            (RUBY_T_OBJECT, RUBY_T_MASK)
        } else if self.flags().is_t_class() {
            // Check class first since `Class < Module`
            (RUBY_T_CLASS, RUBY_T_MASK)
        } else if self.flags().is_t_module() {
            (RUBY_T_MODULE, RUBY_T_MASK)
        } else if self.flags().is_typed_data() {
            (RUBY_T_DATA | RUBY_TYPED_FL_IS_TYPED_DATA, RUBY_T_MASK | RUBY_TYPED_FL_IS_TYPED_DATA)
        } else {
            (0, 0)
        };
        (shape | u64::from(builtin_type), shape_mask | u64::from(type_mask))
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

/// Per-instruction profile entry, stored sparsely in a sorted Vec.
#[derive(Debug)]
struct ProfileEntry {
    /// YARV instruction index
    insn_idx: u32,
    /// Type information of YARV instruction operands
    opnd_types: Vec<TypeDistribution>,
    /// Number of profiles remaining before recompilation. Counts down from --zjit-num-profiles.
    profiles_remaining: NumProfiles,
}

#[derive(Debug)]
pub struct IseqProfile {
    /// Sparse storage of per-instruction profile data, sorted by instruction index.
    /// Only instructions that have actually been profiled have entries here.
    entries: Vec<ProfileEntry>,

    /// Method entries for `super` calls (stored as VALUE to be GC-safe)
    super_cme: HashMap<YarvInsnIdx, TypeDistribution>
}

impl IseqProfile {
    pub fn new() -> Self {
        Self {
            entries: Vec::new(),
            super_cme: HashMap::new(),
        }
    }

    /// Get or create a mutable profile entry for the given instruction index.
    fn entry_mut(&mut self, insn_idx: YarvInsnIdx) -> &mut ProfileEntry {
        let idx = insn_idx as u32;
        match self.entries.binary_search_by_key(&idx, |e| e.insn_idx) {
            Ok(i) => &mut self.entries[i],
            Err(i) => {
                self.entries.insert(i, ProfileEntry {
                    insn_idx: idx,
                    opnd_types: Vec::new(),
                    profiles_remaining: get_option!(num_profiles),
                });
                &mut self.entries[i]
            }
        }
    }

    /// Get a profile entry for the given instruction index (read-only).
    fn entry(&self, insn_idx: YarvInsnIdx) -> Option<&ProfileEntry> {
        let idx = insn_idx as u32;
        self.entries.binary_search_by_key(&idx, |e| e.insn_idx)
            .ok().map(|i| &self.entries[i])
    }

    /// Check if enough profiles have been gathered for this instruction.
    pub fn done_profiling_at(&self, insn_idx: YarvInsnIdx) -> bool {
        self.entry(insn_idx).map_or(false, |e| e.profiles_remaining == 0)
    }

    /// Profile send operands from the stack at runtime.
    /// `sp` is the current stack pointer (after the args and receiver).
    /// `argc` is the number of arguments (not counting receiver).
    /// Returns true if enough profiles have been gathered and the ISEQ should be recompiled.
    pub fn profile_send_at(&mut self, iseq: IseqPtr, insn_idx: YarvInsnIdx, sp: *const VALUE, argc: usize) -> bool {
        let n = argc + 1; // args + receiver
        let entry = self.entry_mut(insn_idx);
        if entry.opnd_types.is_empty() {
            entry.opnd_types.resize(n, TypeDistribution::new());
        }
        for i in 0..n {
            let obj = unsafe { *sp.offset(i as isize - n as isize) };
            let ty = ProfiledType::new(obj);
            VALUE::from(iseq).write_barrier(ty.class());
            entry.opnd_types[i].observe(ty);
        }
        entry.profiles_remaining = entry.profiles_remaining.saturating_sub(1);
        entry.profiles_remaining == 0
    }

    /// Profile self for a shape guard exit at runtime.
    /// This may be called on an instruction that was already profiled by YARV,
    /// so we reset the counter to re-profile with the new shapes seen at runtime.
    /// Returns true if enough profiles have been gathered and the ISEQ should be recompiled.
    pub fn profile_self_at(&mut self, iseq: IseqPtr, insn_idx: YarvInsnIdx, self_val: VALUE) -> bool {
        let entry = self.entry_mut(insn_idx);
        // Reset profiling if the previous round already finished (stale YARV profiles).
        // This ensures we collect num_profiles samples of the new shapes before recompiling.
        if entry.profiles_remaining == 0 {
            entry.profiles_remaining = get_option!(num_profiles);
        }
        if entry.opnd_types.is_empty() {
            entry.opnd_types.resize(1, TypeDistribution::new());
        }
        let ty = ProfiledType::new(self_val);
        VALUE::from(iseq).write_barrier(ty.class());
        entry.opnd_types[0].observe(ty);
        entry.profiles_remaining = entry.profiles_remaining.saturating_sub(1);
        entry.profiles_remaining == 0
    }

    /// Get profiled operand types for a given instruction index
    pub fn get_operand_types(&self, insn_idx: YarvInsnIdx) -> Option<&[TypeDistribution]> {
        self.entry(insn_idx).map(|e| e.opnd_types.as_slice()).filter(|s| !s.is_empty())
    }

    pub fn get_super_method_entry(&self, insn_idx: YarvInsnIdx) -> Option<*const rb_callable_method_entry_t> {
        let Some(entry) = self.super_cme.get(&insn_idx) else { return None };
        let summary = TypeDistributionSummary::new(entry);

        if summary.is_monomorphic() {
            Some(summary.bucket(0).class.0 as *const rb_callable_method_entry_t)
        } else {
            None
        }
    }

    /// Run a given callback with every object in IseqProfile
    pub fn each_object(&self, callback: impl Fn(VALUE)) {
        for entry in &self.entries {
            for distribution in &entry.opnd_types {
                for profiled_type in distribution.each_item() {
                    // If the type is a GC object, call the callback
                    callback(profiled_type.class);
                }
            }
        }

        for super_cme_values in self.super_cme.values() {
            for profiled_type in super_cme_values.each_item() {
                callback(profiled_type.class)
            }
        }
    }

    /// Run a given callback with a mutable reference to every object in IseqProfile.
    pub fn each_object_mut(&mut self, callback: impl Fn(&mut VALUE)) {
        for entry in &mut self.entries {
            for distribution in &mut entry.opnd_types {
                for ref mut profiled_type in distribution.each_item_mut() {
                    // If the type is a GC object, call the callback
                    callback(&mut profiled_type.class);
                }
            }
        }

        // Update CME references if they move during compaction.
        for super_cme_values in self.super_cme.values_mut() {
            for ref mut profiled_type in super_cme_values.each_item_mut() {
                callback(&mut profiled_type.class)
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
