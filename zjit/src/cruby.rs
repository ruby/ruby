//! This module deals with making relevant C functions available to Rust ZJIT.
//! Some C functions we use we maintain, some are public C extension APIs,
//! some are internal CRuby APIs.
//!
//! ## General notes about linking
//!
//! The ZJIT crate compiles to a native static library, which for our purposes
//! we can understand as a collection of object files. On ELF platforms at least,
//! object files can refer to "external symbols" which we could take some
//! liberty and understand as assembly labels that refer to code defined in other
//! object files resolved when linking. When we are linking, say to produce miniruby,
//! the linker resolves and put concrete addresses for each usage of C function in
//! the Rust static library.
//!
//! By declaring external functions and using them, we are asserting the symbols
//! we use have definition in one of the object files we pass to the linker. Declaring
//! a function here that has no definition anywhere causes a linking error.
//!
//! There are more things going on during linking and this section makes a lot of
//! simplifications but hopefully this gives a good enough working mental model.
//!
//! ## Difference from example in the Rustonomicon
//!
//! You might be wondering about why this is different from the [FFI example]
//! in the Nomicon, an official book about Unsafe Rust.
//!
//! There is no `#[link]` attribute because we are not linking against an external
//! library, but rather implicitly asserting that we'll supply a concrete definition
//! for all C functions we call, similar to how pure C projects put functions
//! across different compilation units and link them together.
//!
//! TODO(alan): is the model different enough on Windows that this setup is unworkable?
//!             Seems prudent to at least learn more about Windows binary tooling before
//!             committing to a design.
//!
//! Alan recommends reading the Nomicon cover to cover as he thinks the book is
//! not very long in general and especially for something that can save hours of
//! debugging Undefined Behavior (UB) down the road.
//!
//! UBs can cause Safe Rust to crash, at which point it's hard to tell which
//! usage of `unsafe` in the codebase invokes UB. Providing safe Rust interface
//! wrapping `unsafe` Rust is a good technique, but requires practice and knowledge
//! about what's well defined and what's undefined.
//!
//! For an extremely advanced example of building safe primitives using Unsafe Rust,
//! see the [GhostCell] paper. Some parts of the paper assume less background knowledge
//! than other parts, so there should be learning opportunities in it for all experience
//! levels.
//!
//! ## Binding generation
//!
//! For the moment declarations on the Rust side are hand written. The code is boilerplate
//! and could be generated automatically with a custom tooling that depend on
//! rust-lang/rust-bindgen. The output Rust code could be checked in to version control
//! and verified on CI like `make update-deps`.
//!
//! Upsides for this design:
//!  - the ZJIT static lib that links with miniruby and friends will not need bindgen
//!    as a dependency at all. This is an important property so Ruby end users can
//!    build a ZJIT enabled Ruby with no internet connection using a release tarball
//!  - Less hand-typed boilerplate
//!  - Helps reduce risk of C definitions and Rust declaration going out of sync since
//!    CI verifies synchronicity
//!
//! Downsides and known unknowns:
//!  - Using rust-bindgen this way seems unusual. We might be depending on parts
//!    that the project is not committed to maintaining
//!  - This setup assumes rust-bindgen gives deterministic output, which can't be taken
//!    for granted
//!  - ZJIT contributors will need to install libclang on their system to get rust-bindgen
//!    to work if they want to run the generation tool locally
//!
//! The elephant in the room is that we'll still need to use Unsafe Rust to call C functions,
//! and the binding generation can't magically save us from learning Unsafe Rust.
//!
//!
//! [FFI example]: https://doc.rust-lang.org/nomicon/ffi.html
//! [GhostCell]: http://plv.mpi-sws.org/rustbelt/ghostcell/

// CRuby types use snake_case. Allow them so we use one name across languages.
#![allow(non_camel_case_types)]
// A lot of imported CRuby globals aren't all-caps
#![allow(non_upper_case_globals)]

// Some of this code may not be used yet
#![allow(dead_code)]
#![allow(unused_macros)]
#![allow(unused_imports)]

use std::convert::From;
use std::ffi::{CString, CStr};
use std::fmt::{Debug, Formatter};
use std::os::raw::{c_char, c_int, c_uint};
use std::panic::{catch_unwind, UnwindSafe};

// We check that we can do this with the configure script and a couple of
// static asserts. u64 and not usize to play nice with lowering to x86.
pub type size_t = u64;

/// A type alias for the redefinition flags coming from CRuby. These are just
/// shifted 1s but not explicitly an enum.
pub type RedefinitionFlag = u32;

#[allow(unsafe_op_in_unsafe_fn)]
#[allow(dead_code)]
#[allow(clippy::all)] // warning meant to help with reading; not useful for generated code
mod autogened {
    use super::*;
    // Textually include output from rust-bindgen as suggested by its user guide.
    include!("cruby_bindings.inc.rs");
}
pub use autogened::*;

// TODO: For #defines that affect memory layout, we need to check for them
// on build and fail if they're wrong. e.g. USE_FLONUM *must* be true.

// These are functions we expose from C files, not in any header.
// Parsing it would result in a lot of duplicate definitions.
// Use bindgen for functions that are defined in headers or in zjit.c.
#[cfg_attr(test, allow(unused))] // We don't link against C code when testing
unsafe extern "C" {
    pub fn rb_check_overloaded_cme(
        me: *const rb_callable_method_entry_t,
        ci: *const rb_callinfo,
    ) -> *const rb_callable_method_entry_t;

    // Floats within range will be encoded without creating objects in the heap.
    // (Range is 0x3000000000000001 to 0x4fffffffffffffff (1.7272337110188893E-77 to 2.3158417847463237E+77).
    pub fn rb_float_new(d: f64) -> VALUE;

    pub fn rb_hash_empty_p(hash: VALUE) -> VALUE;
    pub fn rb_yjit_str_concat_codepoint(str: VALUE, codepoint: VALUE);
    pub fn rb_str_setbyte(str: VALUE, index: VALUE, value: VALUE) -> VALUE;
    pub fn rb_vm_splat_array(flag: VALUE, ary: VALUE) -> VALUE;
    pub fn rb_vm_concat_array(ary1: VALUE, ary2st: VALUE) -> VALUE;
    pub fn rb_vm_get_special_object(reg_ep: *const VALUE, value_type: vm_special_object_type) -> VALUE;
    pub fn rb_vm_concat_to_array(ary1: VALUE, ary2st: VALUE) -> VALUE;
    pub fn rb_vm_defined(
        ec: EcPtr,
        reg_cfp: CfpPtr,
        op_type: rb_num_t,
        obj: VALUE,
        v: VALUE,
    ) -> bool;
    pub fn rb_vm_set_ivar_id(obj: VALUE, idx: u32, val: VALUE) -> VALUE;
    pub fn rb_vm_setinstancevariable(iseq: IseqPtr, obj: VALUE, id: ID, val: VALUE, ic: IVC);
    pub fn rb_aliased_callable_method_entry(
        me: *const rb_callable_method_entry_t,
    ) -> *const rb_callable_method_entry_t;
    pub fn rb_vm_getclassvariable(iseq: IseqPtr, cfp: CfpPtr, id: ID, ic: ICVARC) -> VALUE;
    pub fn rb_vm_setclassvariable(
        iseq: IseqPtr,
        cfp: CfpPtr,
        id: ID,
        val: VALUE,
        ic: ICVARC,
    ) -> VALUE;
    pub fn rb_vm_ic_hit_p(ic: IC, reg_ep: *const VALUE) -> bool;
    pub fn rb_vm_stack_canary() -> VALUE;
    pub fn rb_vm_push_cfunc_frame(cme: *const rb_callable_method_entry_t, recv_idx: c_int);
}

// Renames
pub use rb_insn_name as raw_insn_name;
pub use rb_get_ec_cfp as get_ec_cfp;
pub use rb_get_cfp_iseq as get_cfp_iseq;
pub use rb_get_cfp_pc as get_cfp_pc;
pub use rb_get_cfp_sp as get_cfp_sp;
pub use rb_get_cfp_self as get_cfp_self;
pub use rb_get_cfp_ep as get_cfp_ep;
pub use rb_get_cfp_ep_level as get_cfp_ep_level;
pub use rb_vm_base_ptr as get_cfp_bp;
pub use rb_get_cme_def_type as get_cme_def_type;
pub use rb_get_cme_def_body_attr_id as get_cme_def_body_attr_id;
pub use rb_get_cme_def_body_optimized_type as get_cme_def_body_optimized_type;
pub use rb_get_cme_def_body_optimized_index as get_cme_def_body_optimized_index;
pub use rb_get_cme_def_body_cfunc as get_cme_def_body_cfunc;
pub use rb_get_def_method_serial as get_def_method_serial;
pub use rb_get_def_original_id as get_def_original_id;
pub use rb_get_mct_argc as get_mct_argc;
pub use rb_get_mct_func as get_mct_func;
pub use rb_get_def_iseq_ptr as get_def_iseq_ptr;
pub use rb_iseq_encoded_size as get_iseq_encoded_size;
pub use rb_get_iseq_body_local_iseq as get_iseq_body_local_iseq;
pub use rb_get_iseq_body_iseq_encoded as get_iseq_body_iseq_encoded;
pub use rb_get_iseq_body_stack_max as get_iseq_body_stack_max;
pub use rb_get_iseq_body_type as get_iseq_body_type;
pub use rb_get_iseq_flags_has_lead as get_iseq_flags_has_lead;
pub use rb_get_iseq_flags_has_opt as get_iseq_flags_has_opt;
pub use rb_get_iseq_flags_has_kw as get_iseq_flags_has_kw;
pub use rb_get_iseq_flags_has_rest as get_iseq_flags_has_rest;
pub use rb_get_iseq_flags_has_post as get_iseq_flags_has_post;
pub use rb_get_iseq_flags_has_kwrest as get_iseq_flags_has_kwrest;
pub use rb_get_iseq_flags_has_block as get_iseq_flags_has_block;
pub use rb_get_iseq_flags_ambiguous_param0 as get_iseq_flags_ambiguous_param0;
pub use rb_get_iseq_flags_accepts_no_kwarg as get_iseq_flags_accepts_no_kwarg;
pub use rb_get_iseq_body_local_table_size as get_iseq_body_local_table_size;
pub use rb_get_iseq_body_param_keyword as get_iseq_body_param_keyword;
pub use rb_get_iseq_body_param_size as get_iseq_body_param_size;
pub use rb_get_iseq_body_param_lead_num as get_iseq_body_param_lead_num;
pub use rb_get_iseq_body_param_opt_num as get_iseq_body_param_opt_num;
pub use rb_get_iseq_body_param_opt_table as get_iseq_body_param_opt_table;
pub use rb_get_cikw_keyword_len as get_cikw_keyword_len;
pub use rb_get_cikw_keywords_idx as get_cikw_keywords_idx;
pub use rb_get_call_data_ci as get_call_data_ci;
pub use rb_FL_TEST as FL_TEST;
pub use rb_FL_TEST_RAW as FL_TEST_RAW;
pub use rb_RB_TYPE_P as RB_TYPE_P;
pub use rb_BASIC_OP_UNREDEFINED_P as BASIC_OP_UNREDEFINED_P;
pub use rb_RSTRUCT_LEN as RSTRUCT_LEN;
pub use rb_vm_ci_argc as vm_ci_argc;
pub use rb_vm_ci_mid as vm_ci_mid;
pub use rb_vm_ci_flag as vm_ci_flag;
pub use rb_vm_ci_kwarg as vm_ci_kwarg;
pub use rb_METHOD_ENTRY_VISI as METHOD_ENTRY_VISI;
pub use rb_RCLASS_ORIGIN as RCLASS_ORIGIN;
pub use rb_vm_get_special_object as vm_get_special_object;

/// Helper so we can get a Rust string for insn_name()
pub fn insn_name(opcode: usize) -> String {
    unsafe {
        // Look up Ruby's NULL-terminated insn name string
        let op_name = raw_insn_name(VALUE(opcode));

        // Convert the op name C string to a Rust string and concat
        let op_name = CStr::from_ptr(op_name).to_str().unwrap();

        // Convert into an owned string
        op_name.to_string()
    }
}

pub fn insn_len(opcode: usize) -> u32 {
    unsafe {
        rb_insn_len(VALUE(opcode)).try_into().unwrap()
    }
}

/// Opaque iseq type for opaque iseq pointers from vm_core.h
/// See: <https://doc.rust-lang.org/nomicon/ffi.html#representing-opaque-structs>
#[repr(C)]
pub struct rb_iseq_t {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

/// An object handle similar to VALUE in the C code. Our methods assume
/// that this is a handle. Sometimes the C code briefly uses VALUE as
/// an unsigned integer type and don't necessarily store valid handles but
/// thankfully those cases are rare and don't cross the FFI boundary.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(transparent)] // same size and alignment as simply `usize`
pub struct VALUE(pub usize);

/// An interned string. See [ids] and methods this type.
/// `0` is a sentinal value for IDs.
#[repr(transparent)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct ID(pub ::std::os::raw::c_ulong);

/// Pointer to an ISEQ
pub type IseqPtr = *const rb_iseq_t;

// Given an ISEQ pointer, convert PC to insn_idx
pub fn iseq_pc_to_insn_idx(iseq: IseqPtr, pc: *mut VALUE) -> Option<u16> {
    let pc_zero = unsafe { rb_iseq_pc_at_idx(iseq, 0) };
    unsafe { pc.offset_from(pc_zero) }.try_into().ok()
}

/// Given an ISEQ pointer and an instruction index, return an opcode.
pub fn iseq_opcode_at_idx(iseq: IseqPtr, insn_idx: u32) -> u32 {
    let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
    unsafe { rb_iseq_opcode_at_pc(iseq, pc) as u32 }
}

/// Return a poison value to be set above the stack top to verify leafness.
#[cfg(not(test))]
pub fn vm_stack_canary() -> u64 {
    unsafe { rb_vm_stack_canary() }.as_u64()
}

/// Avoid linking the C function in `cargo test`
#[cfg(test)]
pub fn vm_stack_canary() -> u64 {
    0
}

/// Opaque execution-context type from vm_core.h
#[repr(C)]
pub struct rb_execution_context_struct {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}
/// Alias for rb_execution_context_struct used by CRuby sometimes
pub type rb_execution_context_t = rb_execution_context_struct;

/// Pointer to an execution context (rb_execution_context_struct)
pub type EcPtr = *const rb_execution_context_struct;

// From method.h
#[repr(C)]
pub struct rb_method_definition_t {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}
type rb_method_definition_struct = rb_method_definition_t;

/// Opaque cfunc type from method.h
#[repr(C)]
pub struct rb_method_cfunc_t {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

/// Opaque call-cache type from vm_callinfo.h
#[repr(C)]
pub struct rb_callcache {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

/// Opaque control_frame (CFP) struct from vm_core.h
#[repr(C)]
pub struct rb_control_frame_struct {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

/// Pointer to a control frame pointer (CFP)
pub type CfpPtr = *mut rb_control_frame_struct;

/// Opaque struct from vm_core.h
#[repr(C)]
pub struct rb_cref_t {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

#[derive(PartialEq)]
pub enum ClassRelationship {
    Subclass,
    Superclass,
    NoRelation,
}

impl VALUE {
    /// Dump info about the value to the console similarly to rp(VALUE)
    pub fn dump_info(self) {
        unsafe { rb_obj_info_dump(self) }
    }

    /// Return whether the value is truthy or falsy in Ruby -- only nil and false are falsy.
    pub fn test(self) -> bool {
        let VALUE(cval) = self;
        let VALUE(qnilval) = Qnil;
        (cval & !qnilval) != 0
    }

    /// Return true if the number is an immediate integer, flonum or static symbol
    fn immediate_p(self) -> bool {
        let VALUE(cval) = self;
        let mask = RUBY_IMMEDIATE_MASK as usize;
        (cval & mask) != 0
    }

    /// Return true if the value is a Ruby immediate integer, flonum, static symbol, nil or false
    pub fn special_const_p(self) -> bool {
        self.immediate_p() || !self.test()
    }

    /// Return true if the value is a heap object
    pub fn heap_object_p(self) -> bool {
        !self.special_const_p()
    }

    /// Return true if the value is a Ruby Fixnum (immediate-size integer)
    pub fn fixnum_p(self) -> bool {
        let VALUE(cval) = self;
        let flag = RUBY_FIXNUM_FLAG as usize;
        (cval & flag) == flag
    }

    /// Return true if the value is an immediate Ruby floating-point number (flonum)
    pub fn flonum_p(self) -> bool {
        let VALUE(cval) = self;
        let mask = RUBY_FLONUM_MASK as usize;
        let flag = RUBY_FLONUM_FLAG as usize;
        (cval & mask) == flag
    }

    /// Return true if the value is a Ruby symbol (RB_SYMBOL_P)
    pub fn symbol_p(self) -> bool {
        self.static_sym_p() || self.dynamic_sym_p()
    }

    /// Return true for a static (non-heap) Ruby symbol (RB_STATIC_SYM_P)
    pub fn static_sym_p(self) -> bool {
        let VALUE(cval) = self;
        let flag = RUBY_SYMBOL_FLAG as usize;
        (cval & 0xff) == flag
    }

    /// Return true for a dynamic Ruby symbol (RB_DYNAMIC_SYM_P)
    fn dynamic_sym_p(self) -> bool {
        if self.special_const_p() {
            false
        } else {
            self.builtin_type() == RUBY_T_SYMBOL
        }
    }

    /// Returns true if the value is T_HASH
    pub fn hash_p(self) -> bool {
        !self.special_const_p() && self.builtin_type() == RUBY_T_HASH
    }

    /// Returns true or false depending on whether the value is nil
    pub fn nil_p(self) -> bool {
        self == Qnil
    }

    pub fn string_p(self) -> bool {
        self.class_of() == unsafe { rb_cString }
    }

    /// Read the flags bits from the RBasic object, then return a Ruby type enum (e.g. RUBY_T_ARRAY)
    pub fn builtin_type(self) -> ruby_value_type {
        (self.builtin_flags() & (RUBY_T_MASK as usize)) as ruby_value_type
    }

    pub fn builtin_flags(self) -> usize {
        assert!(!self.special_const_p());

        let VALUE(cval) = self;
        let rbasic_ptr = cval as *const RBasic;
        let flags_bits: usize = unsafe { (*rbasic_ptr).flags }.as_usize();
        flags_bits
    }

    pub fn class_of(self) -> VALUE {
        if !self.special_const_p() {
            let builtin_type = self.builtin_type();
            assert_ne!(builtin_type, RUBY_T_NONE, "ZJIT should only see live objects");
            assert_ne!(builtin_type, RUBY_T_MOVED, "ZJIT should only see live objects");
        }

        unsafe { rb_yarv_class_of(self) }
    }

    /// Check if `self` is a subclass of `other`. Assumes both `self` and `other` are class
    /// objects. Returns [`ClassRelationship::Subclass`] if `self <= other`,
    /// [`ClassRelationship::Superclass`] if `other < self`, and [`ClassRelationship::NoRelation`]
    /// otherwise.
    pub fn is_subclass_of(self, other: VALUE) -> ClassRelationship {
        assert!(unsafe { RB_TYPE_P(self, RUBY_T_CLASS) });
        assert!(unsafe { RB_TYPE_P(other, RUBY_T_CLASS) });
        match unsafe { rb_class_inherited_p(self, other) } {
            Qtrue => ClassRelationship::Subclass,
            Qfalse => ClassRelationship::Superclass,
            Qnil => ClassRelationship::NoRelation,
            // The API specifies that it will return Qnil in this case
            _ => panic!("Unexpected return value from rb_class_inherited_p"),
        }
    }

    /// Borrow the string contents of `self`. Rust unsafe because of possible mutation and GC
    /// interactions.
    pub unsafe fn as_rstring_byte_slice<'a>(self) -> Option<&'a [u8]> {
        if !unsafe { RB_TYPE_P(self, RUBY_T_STRING) } {
            None
        } else {
            let str_ptr = unsafe { rb_RSTRING_PTR(self) } as *const u8;
            let str_len: usize = unsafe { rb_RSTRING_LEN(self) }.try_into().ok()?;
            Some(unsafe { std::slice::from_raw_parts(str_ptr, str_len) })
        }
    }

    pub fn is_frozen(self) -> bool {
        unsafe { rb_obj_frozen_p(self) != VALUE(0) }
    }

    pub fn shape_too_complex(self) -> bool {
        unsafe { rb_zjit_shape_obj_too_complex_p(self) }
    }

    pub fn shape_id_of(self) -> u32 {
        unsafe { rb_obj_shape_id(self) }
    }

    pub fn embedded_p(self) -> bool {
        unsafe {
            FL_TEST_RAW(self, VALUE(ROBJECT_EMBED as usize)) != VALUE(0)
        }
    }

    pub fn as_fixnum(self) -> i64 {
        assert!(self.fixnum_p());
        (self.0 as i64) >> 1
    }

    pub fn as_isize(self) -> isize {
        let VALUE(is) = self;
        is as isize
    }

    pub fn as_i32(self) -> i32 {
        self.as_i64().try_into().unwrap()
    }

    pub fn as_u32(self) -> u32 {
        let VALUE(i) = self;
        i.try_into().unwrap()
    }

    pub fn as_i64(self) -> i64 {
        let VALUE(i) = self;
        i as i64
    }

    pub fn as_u64(self) -> u64 {
        let VALUE(i) = self;
        i.try_into().unwrap()
    }

    pub fn as_usize(self) -> usize {
        let VALUE(us) = self;
        us
    }

    pub fn as_ptr<T>(self) -> *const T {
        let VALUE(us) = self;
        us as *const T
    }

    pub fn as_mut_ptr<T>(self) -> *mut T {
        let VALUE(us) = self;
        us as *mut T
    }

    /// For working with opaque pointers and encoding null check.
    /// Similar to [std::ptr::NonNull], but for `*const T`. `NonNull<T>`
    /// is for `*mut T` while our C functions are setup to use `*const T`.
    /// Casting from `NonNull<T>` to `*const T` is too noisy.
    pub fn as_optional_ptr<T>(self) -> Option<*const T> {
        let ptr: *const T = self.as_ptr();

        if ptr.is_null() {
            None
        } else {
            Some(ptr)
        }
    }

    /// Assert that `self` is an iseq in debug builds
    pub fn as_iseq(self) -> IseqPtr {
        let ptr: IseqPtr = self.as_ptr();

        #[cfg(debug_assertions)]
        if !ptr.is_null() {
            unsafe { rb_assert_iseq_handle(self) }
        }

        ptr
    }

    pub fn cme_p(self) -> bool {
        if self == VALUE(0) { return false; }
        unsafe { rb_IMEMO_TYPE_P(self, imemo_ment) == 1 }
    }

    /// Assert that `self` is a method entry in debug builds
    pub fn as_cme(self) -> *const rb_callable_method_entry_t {
        let ptr: *const rb_callable_method_entry_t = self.as_ptr();

        #[cfg(debug_assertions)]
        if !ptr.is_null() {
            unsafe { rb_assert_cme_handle(self) }
        }

        ptr
    }

    pub const fn fixnum_from_usize(item: usize) -> Self {
        assert!(item <= (RUBY_FIXNUM_MAX as usize)); // An unsigned will always be greater than RUBY_FIXNUM_MIN
        let k: usize = item.wrapping_add(item.wrapping_add(1));
        VALUE(k)
    }

    pub const fn fixnum_from_isize(item: isize) -> Self {
        assert!(item >= RUBY_FIXNUM_MIN);
        assert!(item <= RUBY_FIXNUM_MAX);
        let k: isize = item.wrapping_add(item.wrapping_add(1));
        VALUE(k as usize)
    }
}

impl From<IseqPtr> for VALUE {
    /// For `.into()` convenience
    fn from(iseq: IseqPtr) -> Self {
        VALUE(iseq as usize)
    }
}

impl From<*const rb_callable_method_entry_t> for VALUE {
    /// For `.into()` convenience
    fn from(cme: *const rb_callable_method_entry_t) -> Self {
        VALUE(cme as usize)
    }
}

impl From<&str> for VALUE {
    fn from(value: &str) -> Self {
        rust_str_to_ruby(value)
    }
}

impl From<String> for VALUE {
    fn from(value: String) -> Self {
        rust_str_to_ruby(&value)
    }
}

impl From<VALUE> for u64 {
    fn from(value: VALUE) -> Self {
        let VALUE(uimm) = value;
        uimm as u64
    }
}

impl From<VALUE> for i64 {
    fn from(value: VALUE) -> Self {
        let VALUE(uimm) = value;
        assert!(uimm <= (i64::MAX as usize));
        uimm as i64
    }
}

impl From<VALUE> for i32 {
    fn from(value: VALUE) -> Self {
        let VALUE(uimm) = value;
        assert!(uimm <= (i32::MAX as usize));
        uimm.try_into().unwrap()
    }
}

impl From<VALUE> for u16 {
    fn from(value: VALUE) -> Self {
        let VALUE(uimm) = value;
        uimm.try_into().unwrap()
    }
}

impl ID {
    // Get a debug representation of the contents of the ID. Since `str` is UTF-8
    // and IDs have encodings that are not, this is a lossy representation.
    pub fn contents_lossy(&self) -> std::borrow::Cow<'_, str> {
        use std::borrow::Cow;
        if self.0 == 0 {
            Cow::Borrowed("ID(0)")
        } else {
            // Get the contents as a byte slice. IDs can have internal NUL bytes so rb_id2name,
            // which returns a C string is more lossy than this approach.
            let contents = unsafe { rb_id2str(*self) };
            if contents == Qfalse {
                Cow::Borrowed("ID(0)")
            } else {
                let slice = unsafe { contents.as_rstring_byte_slice() }
                    .expect("rb_id2str() returned truthy non-string");
                String::from_utf8_lossy(slice)
            }
        }
    }
}

/// Produce a Ruby string from a Rust string slice
pub fn rust_str_to_ruby(str: &str) -> VALUE {
    unsafe { rb_utf8_str_new(str.as_ptr() as *const _, str.len() as i64) }
}

/// Produce a Ruby symbol from a Rust string slice
pub fn rust_str_to_sym(str: &str) -> VALUE {
    let c_str = CString::new(str).unwrap();
    let c_ptr: *const c_char = c_str.as_ptr();
    unsafe { rb_id2sym(rb_intern(c_ptr)) }
}

/// Produce an owned Rust String from a C char pointer
pub fn cstr_to_rust_string(c_char_ptr: *const c_char) -> Option<String> {
    assert!(c_char_ptr != std::ptr::null());

    let c_str: &CStr = unsafe { CStr::from_ptr(c_char_ptr) };

    match c_str.to_str() {
        Ok(rust_str) => Some(rust_str.to_string()),
        Err(_) => None
    }
}

pub fn iseq_name(iseq: IseqPtr) -> String {
    let iseq_label = unsafe { rb_iseq_label(iseq) };
    if iseq_label == Qnil {
        "None".to_string()
    } else {
        ruby_str_to_rust(iseq_label)
    }
}

// Location is the file defining the method, colon, method name.
// Filenames are sometimes internal strings supplied to eval,
// so be careful with them.
pub fn iseq_get_location(iseq: IseqPtr, pos: u16) -> String {
    let iseq_path = unsafe { rb_iseq_path(iseq) };
    let iseq_lineno = unsafe { rb_iseq_line_no(iseq, pos as usize) };

    let mut s = iseq_name(iseq);
    s.push_str("@");
    if iseq_path == Qnil {
        s.push_str("None");
    } else {
        s.push_str(&ruby_str_to_rust(iseq_path));
    }
    s.push_str(":");
    s.push_str(&iseq_lineno.to_string());
    s
}


// Convert a CRuby UTF-8-encoded RSTRING into a Rust string.
// This should work fine on ASCII strings and anything else
// that is considered legal UTF-8, including embedded nulls.
fn ruby_str_to_rust(v: VALUE) -> String {
    let str_ptr = unsafe { rb_RSTRING_PTR(v) } as *mut u8;
    let str_len: usize = unsafe { rb_RSTRING_LEN(v) }.try_into().unwrap();
    let str_slice: &[u8] = unsafe { std::slice::from_raw_parts(str_ptr, str_len) };
    match String::from_utf8(str_slice.to_vec()) {
        Ok(utf8) => utf8,
        Err(_) => String::new(),
    }
}

/// A location in Rust code for integrating with debugging facilities defined in C.
/// Use the [src_loc!] macro to crate an instance.
pub struct SourceLocation {
    pub file: &'static CStr,
    pub line: c_int,
}

impl Debug for SourceLocation {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.write_fmt(format_args!("{}:{}", self.file.to_string_lossy(), self.line))
    }
}

/// Make a [SourceLocation] at the current spot.
macro_rules! src_loc {
    () => {
        {
            // Nul-terminated string with static lifetime, make a CStr out of it safely.
            let file: &'static str = concat!(file!(), '\0');
            $crate::cruby::SourceLocation {
                file: unsafe { std::ffi::CStr::from_ptr(file.as_ptr().cast()) },
                line: line!().try_into().unwrap(),
            }
        }
    };
}

pub(crate) use src_loc;

/// Run GC write barrier. Required after making a new edge in the object reference
/// graph from `old` to `young`.
macro_rules! obj_written {
    ($old: expr, $young: expr) => {
        let (old, young): (VALUE, VALUE) = ($old, $young);
        let src_loc = $crate::cruby::src_loc!();
        unsafe { rb_yjit_obj_written(old, young, src_loc.file.as_ptr(), src_loc.line) };
    };
}
pub(crate) use obj_written;

/// Acquire the VM lock, make sure all other Ruby threads are asleep then run
/// some code while holding the lock. Returns whatever `func` returns.
/// Use with [src_loc!].
///
/// Required for code patching in the presence of ractors.
pub fn with_vm_lock<F, R>(loc: SourceLocation, func: F) -> R
where
    F: FnOnce() -> R + UnwindSafe,
{
    let file = loc.file.as_ptr();
    let line = loc.line;
    let mut recursive_lock_level: c_uint = 0;

    unsafe { rb_zjit_vm_lock_then_barrier(&mut recursive_lock_level, file, line) };

    let ret = match catch_unwind(func) {
        Ok(result) => result,
        Err(_) => {
            // Theoretically we can recover from some of these panics,
            // but it's too late if the unwind reaches here.

            let _ = catch_unwind(|| {
                // IO functions can panic too.
                eprintln!(
                    "ZJIT panicked while holding VM lock acquired at {}:{}. Aborting...",
                    loc.file.to_string_lossy(),
                    line,
                );
            });
            std::process::abort();
        }
    };

    unsafe { rb_zjit_vm_unlock(&mut recursive_lock_level, file, line) };

    ret
}

/// At the moment, we abort in all cases we panic.
/// To aid with getting diagnostics in the wild without requiring people to set
/// RUST_BACKTRACE=1, register a panic hook that crash using rb_bug() for release builds.
/// rb_bug() might not be as good at printing a call trace as Rust's stdlib, but
/// it dumps some other info that might be relevant.
///
/// In case we want to start doing fancier exception handling with panic=unwind,
/// we can revisit this later. For now, this helps to get us good bug reports.
pub fn rb_bug_panic_hook() {
    use std::env;
    use std::panic;
    use std::io::{stderr, Write};

    // Probably the default hook. We do this very early during process boot.
    let previous_hook = panic::take_hook();

    panic::set_hook(Box::new(move |panic_info| {
        // Not using `eprintln` to avoid double panic.
        let _ = stderr().write_all(b"ruby: ZJIT has panicked. More info to follow...\n");

        // Always show a Rust backtrace for release builds.
        // You should set RUST_BACKTRACE=1 for dev builds.
        let release_build = cfg!(not(debug_assertions));
        if release_build {
            unsafe { env::set_var("RUST_BACKTRACE", "1"); }
        }
        previous_hook(panic_info);

        // Dump information about the interpreter for release builds.
        // You may also use ZJIT_RB_BUG=1 to trigger this on dev builds.
        if release_build || env::var("ZJIT_RB_BUG").is_ok() {
            // Abort with rb_bug(). It has a length limit on the message.
            let panic_message = &format!("{}", panic_info)[..];
            let len = std::cmp::min(0x100, panic_message.len()) as c_int;
            unsafe { rb_bug(b"ZJIT: %*s\0".as_ref().as_ptr() as *const c_char, len, panic_message.as_ptr()); }
        }
    }));
}

// Non-idiomatic capitalization for consistency with CRuby code
#[allow(non_upper_case_globals)]
pub const Qfalse: VALUE = VALUE(RUBY_Qfalse as usize);
#[allow(non_upper_case_globals)]
pub const Qnil: VALUE = VALUE(RUBY_Qnil as usize);
#[allow(non_upper_case_globals)]
pub const Qtrue: VALUE = VALUE(RUBY_Qtrue as usize);
#[allow(non_upper_case_globals)]
pub const Qundef: VALUE = VALUE(RUBY_Qundef as usize);

#[allow(unused)]
mod manual_defs {
    use super::*;

    pub const SIZEOF_VALUE: usize = 8;
    pub const SIZEOF_VALUE_I32: i32 = SIZEOF_VALUE as i32;
    pub const VALUE_BITS: u8 = 8 * SIZEOF_VALUE as u8;

    pub const RUBY_LONG_MIN: isize = std::os::raw::c_long::MIN as isize;
    pub const RUBY_LONG_MAX: isize = std::os::raw::c_long::MAX as isize;

    pub const RUBY_FIXNUM_MIN: isize = RUBY_LONG_MIN / 2;
    pub const RUBY_FIXNUM_MAX: isize = RUBY_LONG_MAX / 2;

    // From vm_callinfo.h - uses calculation that seems to confuse bindgen
    pub const VM_CALL_ARGS_SIMPLE: u32 = 1 << VM_CALL_ARGS_SIMPLE_bit;
    pub const VM_CALL_ARGS_SPLAT: u32 = 1 << VM_CALL_ARGS_SPLAT_bit;
    pub const VM_CALL_ARGS_SPLAT_MUT: u32 = 1 << VM_CALL_ARGS_SPLAT_MUT_bit;
    pub const VM_CALL_ARGS_BLOCKARG: u32 = 1 << VM_CALL_ARGS_BLOCKARG_bit;
    pub const VM_CALL_FORWARDING: u32 = 1 << VM_CALL_FORWARDING_bit;
    pub const VM_CALL_FCALL: u32 = 1 << VM_CALL_FCALL_bit;
    pub const VM_CALL_KWARG: u32 = 1 << VM_CALL_KWARG_bit;
    pub const VM_CALL_KW_SPLAT: u32 = 1 << VM_CALL_KW_SPLAT_bit;
    pub const VM_CALL_KW_SPLAT_MUT: u32 = 1 << VM_CALL_KW_SPLAT_MUT_bit;
    pub const VM_CALL_TAILCALL: u32 = 1 << VM_CALL_TAILCALL_bit;
    pub const VM_CALL_SUPER : u32 = 1 << VM_CALL_SUPER_bit;
    pub const VM_CALL_ZSUPER : u32 = 1 << VM_CALL_ZSUPER_bit;
    pub const VM_CALL_OPT_SEND : u32 = 1 << VM_CALL_OPT_SEND_bit;

    // From internal/struct.h - in anonymous enum, so we can't easily import it
    pub const RSTRUCT_EMBED_LEN_MASK: usize = (RUBY_FL_USER7 | RUBY_FL_USER6 | RUBY_FL_USER5 | RUBY_FL_USER4 | RUBY_FL_USER3 |RUBY_FL_USER2 | RUBY_FL_USER1) as usize;

    // From iseq.h - via a different constant, which seems to confuse bindgen
    pub const ISEQ_TRANSLATED: usize = RUBY_FL_USER7 as usize;

    // We'll need to encode a lot of Ruby struct/field offsets as constants unless we want to
    // redeclare all the Ruby C structs and write our own offsetof macro. For now, we use constants.
    pub const RUBY_OFFSET_RBASIC_FLAGS: i32 = 0; // struct RBasic, field "flags"
    pub const RUBY_OFFSET_RBASIC_KLASS: i32 = 8; // struct RBasic, field "klass"
    pub const RUBY_OFFSET_RARRAY_AS_HEAP_LEN: i32 = 16; // struct RArray, subfield "as.heap.len"
    pub const RUBY_OFFSET_RARRAY_AS_HEAP_PTR: i32 = 32; // struct RArray, subfield "as.heap.ptr"
    pub const RUBY_OFFSET_RARRAY_AS_ARY: i32 = 16; // struct RArray, subfield "as.ary"

    pub const RUBY_OFFSET_RSTRUCT_AS_HEAP_PTR: i32 = 24; // struct RStruct, subfield "as.heap.ptr"
    pub const RUBY_OFFSET_RSTRUCT_AS_ARY: i32 = 16; // struct RStruct, subfield "as.ary"

    pub const RUBY_OFFSET_RSTRING_AS_HEAP_PTR: i32 = 24; // struct RString, subfield "as.heap.ptr"
    pub const RUBY_OFFSET_RSTRING_AS_ARY: i32 = 24; // struct RString, subfield "as.embed.ary"

    // Constants from rb_control_frame_t vm_core.h
    pub const RUBY_OFFSET_CFP_PC: i32 = 0;
    pub const RUBY_OFFSET_CFP_SP: i32 = 8;
    pub const RUBY_OFFSET_CFP_ISEQ: i32 = 16;
    pub const RUBY_OFFSET_CFP_SELF: i32 = 24;
    pub const RUBY_OFFSET_CFP_EP: i32 = 32;
    pub const RUBY_OFFSET_CFP_BLOCK_CODE: i32 = 40;
    pub const RUBY_OFFSET_CFP_JIT_RETURN: i32 = 48;
    pub const RUBY_SIZEOF_CONTROL_FRAME: usize = 56;

    // Constants from rb_execution_context_t vm_core.h
    pub const RUBY_OFFSET_EC_CFP: i32 = 16;
    pub const RUBY_OFFSET_EC_INTERRUPT_FLAG: i32 = 32; // rb_atomic_t (u32)
    pub const RUBY_OFFSET_EC_INTERRUPT_MASK: i32 = 36; // rb_atomic_t (u32)
    pub const RUBY_OFFSET_EC_THREAD_PTR: i32 = 48;

    // Constants from rb_thread_t in vm_core.h
    pub const RUBY_OFFSET_THREAD_SELF: i32 = 16;

    // Constants from iseq_inline_constant_cache (IC) and iseq_inline_constant_cache_entry (ICE) in vm_core.h
    pub const RUBY_OFFSET_IC_ENTRY: i32 = 0;
    pub const RUBY_OFFSET_ICE_VALUE: i32 = 8;
}
pub use manual_defs::*;

#[cfg(test)]
pub mod test_utils {
    use std::{ptr::null, sync::Once};

    use crate::{options::init_options, state::rb_zjit_enabled_p, state::ZJITState};

    use super::*;

    static RUBY_VM_INIT: Once = Once::new();

    /// Boot and initialize the Ruby VM for Rust testing
    fn boot_rubyvm() {
        // Boot the VM
        unsafe {
            // TODO(alan): this init_stack call is incorrect. It sets the stack bottom, but
            // when we return from this function will be be deeper in the stack.
            // The callback for with_rubyvm() should run on a frame higher than this frame
            // so the GC scans all the VALUEs on the stack.
            // Consequently with_rubyvm() can only be used once per process, i.e. you can't
            // boot and then run a few callbacks, because that risks putting VALUE outside
            // the marked stack memory range.
            //
            // Need to also address the ergnomic issues addressed by
            // <https://github.com/Shopify/zjit/pull/37>, though
            let mut var: VALUE = Qnil;
            ruby_init_stack(&mut var as *mut VALUE as *mut _);
            ruby_init();

            // Pass command line options so the VM loads core library methods defined in
            // ruby such as from `kernel.rb`.
            // We drive ZJIT manually in tests, so disable heuristic compilation triggers.
            // (Also, pass this in case we offer a -DFORCE_ENABLE_ZJIT option which turns
            // ZJIT on by default.)
            let cmdline = [c"--disable-all".as_ptr().cast_mut(), c"-e0".as_ptr().cast_mut()];
            let options_ret = ruby_options(2, cmdline.as_ptr().cast_mut());
            assert_ne!(0, ruby_executable_node(options_ret, std::ptr::null_mut()), "command-line parsing failed");

            crate::cruby::ids::init(); // for ID! usages in tests
        }

        // Set up globals for convenience
        ZJITState::init(init_options());

        // Enable zjit_* instructions
        unsafe { rb_zjit_enabled_p = true; }
    }

    /// Make sure the Ruby VM is set up and run a given callback with rb_protect()
    pub fn with_rubyvm<T>(mut func: impl FnMut() -> T) -> T {
        RUBY_VM_INIT.call_once(|| boot_rubyvm());

        // Set up a callback wrapper to store a return value
        let mut result: Option<T> = None;
        let mut data: &mut dyn FnMut() = &mut || {
            // Store the result externally
            result.replace(func());
        };

        // Invoke callback through rb_protect() so exceptions don't crash the process.
        // "Fun" double pointer dance to get a thin function pointer to pass through C
        unsafe extern "C" fn callback_wrapper(data: VALUE) -> VALUE {
            // SAFETY: shorter lifetime than the data local in the caller frame
            let callback: &mut &mut dyn FnMut() = unsafe { std::mem::transmute(data) };
            callback();
            Qnil
        }

        let mut state: c_int = 0;
        unsafe { super::rb_protect(Some(callback_wrapper), VALUE((&mut data) as *mut _ as usize), &mut state) };
        if state != 0 {
            unsafe { rb_zjit_print_exception(); }
            assert_eq!(0, state, "Exceptional unwind in callback. Ruby exception?");
        }

        result.expect("Callback did not set result")
    }

    /// Compile an ISeq via `RubyVM::InstructionSequence.compile`.
    pub fn compile_to_iseq(program: &str) -> *const rb_iseq_t {
        with_rubyvm(|| {
            let wrapped_iseq = compile_to_wrapped_iseq(program);
            unsafe { rb_iseqw_to_iseq(wrapped_iseq) }
        })
    }

    pub fn define_class(name: &str, superclass: VALUE) -> VALUE {
        let name = CString::new(name).unwrap();
        unsafe { rb_define_class(name.as_ptr(), superclass) }
    }

    /// Evaluate a given Ruby program
    pub fn eval(program: &str) -> VALUE {
        with_rubyvm(|| {
            let wrapped_iseq = compile_to_wrapped_iseq(&unindent(program, false));
            unsafe { rb_funcallv(wrapped_iseq, ID!(eval), 0, null()) }
        })
    }

    /// Get the ISeq of a specified method
    pub fn get_method_iseq(recv: &str, name: &str) -> *const rb_iseq_t {
        let wrapped_iseq = eval(&format!("RubyVM::InstructionSequence.of({}.method(:{}))", recv, name));
        unsafe { rb_iseqw_to_iseq(wrapped_iseq) }
    }

    /// Remove the minimum indent from every line, skipping the first and last lines if `trim_lines`.
    pub fn unindent(string: &str, trim_lines: bool) -> String {
        // Break up a string into multiple lines
        let mut lines: Vec<String> = string.split_inclusive("\n").map(|s| s.to_string()).collect();
        if trim_lines { // raw string literals come with extra lines
            lines.remove(0);
            lines.remove(lines.len() - 1);
        }

        // Count the minimum number of spaces
        let spaces = lines.iter().filter_map(|line| {
            for (i, ch) in line.as_bytes().iter().enumerate() {
                if *ch != b' ' {
                    return Some(i);
                }
            }
            None
        }).min().unwrap_or(0);

        // Join lines, removing spaces
        let mut unindented: Vec<u8> = vec![];
        for line in lines.iter() {
            if line.len() > spaces {
                unindented.extend_from_slice(&line.as_bytes()[spaces..]);
            } else {
                unindented.extend_from_slice(&line.as_bytes());
            }
        }
        String::from_utf8(unindented).unwrap()
    }

    /// Compile a program into a RubyVM::InstructionSequence object
    fn compile_to_wrapped_iseq(program: &str) -> VALUE {
        let bytes = program.as_bytes().as_ptr() as *const c_char;
        unsafe {
            let program_str = rb_utf8_str_new(bytes, program.len().try_into().unwrap());
            rb_funcallv(rb_cISeq, ID!(compile), 1, &program_str)
        }
    }

    #[test]
    fn boot_vm() {
        // Test that we loaded kernel.rb and have Kernel#class
        eval("1.class");
    }

    #[test]
    #[should_panic]
    fn ruby_exception_causes_panic() {
        eval("raise");
    }

    #[test]
    fn value_from_fixnum_in_range() {
        assert_eq!(VALUE::fixnum_from_usize(2), VALUE(5));
        assert_eq!(VALUE::fixnum_from_usize(0), VALUE(1));
        assert_eq!(VALUE::fixnum_from_isize(-1), VALUE(0xffffffffffffffff));
        assert_eq!(VALUE::fixnum_from_isize(-2), VALUE(0xfffffffffffffffd));
        assert_eq!(VALUE::fixnum_from_usize(RUBY_FIXNUM_MAX as usize), VALUE(0x7fffffffffffffff));
        assert_eq!(VALUE::fixnum_from_isize(RUBY_FIXNUM_MAX), VALUE(0x7fffffffffffffff));
        assert_eq!(VALUE::fixnum_from_isize(RUBY_FIXNUM_MIN), VALUE(0x8000000000000001));
    }

    #[test]
    fn value_as_fixnum() {
        assert_eq!(VALUE::fixnum_from_usize(2).as_fixnum(), 2);
        assert_eq!(VALUE::fixnum_from_usize(0).as_fixnum(), 0);
        assert_eq!(VALUE::fixnum_from_isize(-1).as_fixnum(), -1);
        assert_eq!(VALUE::fixnum_from_isize(-2).as_fixnum(), -2);
        assert_eq!(VALUE::fixnum_from_usize(RUBY_FIXNUM_MAX as usize).as_fixnum(), RUBY_FIXNUM_MAX.try_into().unwrap());
        assert_eq!(VALUE::fixnum_from_isize(RUBY_FIXNUM_MAX).as_fixnum(), RUBY_FIXNUM_MAX.try_into().unwrap());
        assert_eq!(VALUE::fixnum_from_isize(RUBY_FIXNUM_MIN).as_fixnum(), RUBY_FIXNUM_MIN.try_into().unwrap());
    }

    #[test]
    #[should_panic]
    fn value_from_fixnum_too_big_usize() {
        assert_eq!(VALUE::fixnum_from_usize((RUBY_FIXNUM_MAX+1) as usize), VALUE(1));
    }

    #[test]
    #[should_panic]
    fn value_from_fixnum_too_big_isize() {
        assert_eq!(VALUE::fixnum_from_isize(RUBY_FIXNUM_MAX+1), VALUE(1));
    }

    #[test]
    #[should_panic]
    fn value_from_fixnum_too_small_usize() {
        assert_eq!(VALUE::fixnum_from_usize((RUBY_FIXNUM_MIN-1) as usize), VALUE(1));
    }

    #[test]
    #[should_panic]
    fn value_from_fixnum_too_small_isize() {
        assert_eq!(VALUE::fixnum_from_isize(RUBY_FIXNUM_MIN-1), VALUE(1));
    }
}
#[cfg(test)]
pub use test_utils::*;

/// Get class name from a class pointer.
pub fn get_class_name(class: VALUE) -> String {
    // type checks for rb_class2name()
    if unsafe { RB_TYPE_P(class, RUBY_T_MODULE) || RB_TYPE_P(class, RUBY_T_CLASS) } {
        Some(class)
    } else {
        None
    }.and_then(|class| unsafe {
        cstr_to_rust_string(rb_class2name(class))
    }).unwrap_or_else(|| "Unknown".to_string())
}

/// Interned ID values for Ruby symbols and method names.
/// See [type@crate::cruby::ID] and usages outside of ZJIT.
pub(crate) mod ids {
    use std::sync::atomic::AtomicU64;
    /// Globals to cache IDs on boot. Atomic to use with relaxed ordering
    /// so reads can happen without `unsafe`. Synchronization done through
    /// the VM lock.
    macro_rules! def_ids {
        ($(name: $name:ident $(content: $content:literal)?)*) => {
            $(
                pub static $name: AtomicU64 = AtomicU64::new(0);
            )*

            pub(crate) fn init() {
                $(
                    let content = stringify!($name);
                    _ = content;
                    $(let content = &$content;)?
                    let ptr: *const u8 = content.as_ptr();

                    // Lookup and cache each ID
                    $name.store(
                        unsafe { $crate::cruby::rb_intern2(ptr.cast(), content.len() as _) }.0,
                        std::sync::atomic::Ordering::Relaxed
                    );
                )*

            }
        }
    }

    def_ids! {
        name: NULL               content: b""
        name: respond_to_missing content: b"respond_to_missing?"
        name: eq                 content: b"=="
        name: include_p          content: b"include?"
        name: to_ary
        name: to_s
        name: compile
        name: eval
    }

    /// Get an CRuby `ID` to an interned string, e.g. a particular method name.
    macro_rules! ID {
        ($id_name:ident) => {{
            let id = $crate::cruby::ids::$id_name.load(std::sync::atomic::Ordering::Relaxed);
            debug_assert_ne!(0, id, "ids module should be initialized");
            ID(id)
        }}
    }
    pub(crate) use ID;
}
pub(crate) use ids::ID;
