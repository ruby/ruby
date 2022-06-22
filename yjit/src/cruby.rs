//! This module deals with making relevant C functions available to Rust YJIT.
//! Some C functions we use we maintain, some are public C extension APIs,
//! some are internal CRuby APIs.
//!
//! ## General notes about linking
//!
//! The YJIT crate compiles to a native static library, which for our purposes
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
//!  - the YJIT static lib that links with miniruby and friends will not need bindgen
//!    as a dependency at all. This is an important property so Ruby end users can
//!    build a YJIT enabled Ruby with no internet connection using a release tarball
//!  - Less hand-typed boilerplate
//!  - Helps reduce risk of C definitions and Rust declaration going out of sync since
//!    CI verifies synchronicity
//!
//! Downsides and known unknowns:
//!  - Using rust-bindgen this way seems unusual. We might be depending on parts
//!    that the project is not committed to maintaining
//!  - This setup assumes rust-bindgen gives deterministic output, which can't be taken
//!    for granted
//!  - YJIT contributors will need to install libclang on their system to get rust-bindgen
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

use std::convert::From;
use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_long, c_uint};
use std::panic::{catch_unwind, UnwindSafe};

// We check that we can do this with the configure script and a couple of
// static asserts. u64 and not usize to play nice with lowering to x86.
pub type size_t = u64;

/// A type alias for the redefinition flags coming from CRuby. These are just
/// shifted 1s but not explicitly an enum.
pub type RedefinitionFlag = u32;

#[allow(dead_code)]
mod autogened {
    use super::*;
    // Textually include output from rust-bindgen as suggested by its user guide.
    include!("cruby_bindings.inc.rs");
}
pub use autogened::*;

// TODO: For #defines that affect memory layout, we need to check for them
// on build and fail if they're wrong. e.g. USE_FLONUM *must* be true.

// TODO:
// Temporary, these external bindings will likely be auto-generated
// and textually included in this file
#[cfg_attr(test, allow(unused))] // We don't link against C code when testing
extern "C" {
    #[link_name = "rb_insn_name"]
    pub fn raw_insn_name(insn: VALUE) -> *const c_char;

    #[link_name = "rb_insn_len"]
    pub fn raw_insn_len(v: VALUE) -> c_int;

    #[link_name = "rb_yarv_class_of"]
    pub fn CLASS_OF(v: VALUE) -> VALUE;

    #[link_name = "rb_get_ec_cfp"]
    pub fn get_ec_cfp(ec: EcPtr) -> CfpPtr;

    #[link_name = "rb_get_cfp_pc"]
    pub fn get_cfp_pc(cfp: CfpPtr) -> *mut VALUE;

    #[link_name = "rb_get_cfp_sp"]
    pub fn get_cfp_sp(cfp: CfpPtr) -> *mut VALUE;

    #[link_name = "rb_get_cfp_self"]
    pub fn get_cfp_self(cfp: CfpPtr) -> VALUE;

    #[link_name = "rb_get_cfp_ep"]
    pub fn get_cfp_ep(cfp: CfpPtr) -> *mut VALUE;

    #[link_name = "rb_get_cme_def_type"]
    pub fn get_cme_def_type(cme: *const rb_callable_method_entry_t) -> rb_method_type_t;

    #[link_name = "rb_get_cme_def_body_attr_id"]
    pub fn get_cme_def_body_attr_id(cme: *const rb_callable_method_entry_t) -> ID;

    #[link_name = "rb_get_cme_def_body_optimized_type"]
    pub fn get_cme_def_body_optimized_type(
        cme: *const rb_callable_method_entry_t,
    ) -> method_optimized_type;

    #[link_name = "rb_get_cme_def_body_optimized_index"]
    pub fn get_cme_def_body_optimized_index(cme: *const rb_callable_method_entry_t) -> c_uint;

    #[link_name = "rb_get_cme_def_body_cfunc"]
    pub fn get_cme_def_body_cfunc(cme: *const rb_callable_method_entry_t)
        -> *mut rb_method_cfunc_t;

    #[link_name = "rb_get_def_method_serial"]
    /// While this returns a uintptr_t in C, we always use it as a Rust u64
    pub fn get_def_method_serial(def: *const rb_method_definition_t) -> u64;

    #[link_name = "rb_get_def_original_id"]
    pub fn get_def_original_id(def: *const rb_method_definition_t) -> ID;

    #[link_name = "rb_get_mct_argc"]
    pub fn get_mct_argc(mct: *const rb_method_cfunc_t) -> c_int;

    #[link_name = "rb_get_mct_func"]
    pub fn get_mct_func(mct: *const rb_method_cfunc_t) -> *const u8;

    #[link_name = "rb_get_def_iseq_ptr"]
    pub fn get_def_iseq_ptr(def: *const rb_method_definition_t) -> IseqPtr;

    #[link_name = "rb_iseq_encoded_size"]
    pub fn get_iseq_encoded_size(iseq: IseqPtr) -> c_uint;

    #[link_name = "rb_get_iseq_body_local_iseq"]
    pub fn get_iseq_body_local_iseq(iseq: IseqPtr) -> IseqPtr;

    #[link_name = "rb_get_iseq_body_iseq_encoded"]
    pub fn get_iseq_body_iseq_encoded(iseq: IseqPtr) -> *mut VALUE;

    #[link_name = "rb_get_iseq_body_stack_max"]
    pub fn get_iseq_body_stack_max(iseq: IseqPtr) -> c_uint;

    #[link_name = "rb_get_iseq_flags_has_opt"]
    pub fn get_iseq_flags_has_opt(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_flags_has_kw"]
    pub fn get_iseq_flags_has_kw(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_flags_has_rest"]
    pub fn get_iseq_flags_has_rest(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_flags_has_post"]
    pub fn get_iseq_flags_has_post(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_flags_has_kwrest"]
    pub fn get_iseq_flags_has_kwrest(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_flags_has_block"]
    pub fn get_iseq_flags_has_block(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_flags_has_accepts_no_kwarg"]
    pub fn get_iseq_flags_has_accepts_no_kwarg(iseq: IseqPtr) -> bool;

    #[link_name = "rb_get_iseq_body_local_table_size"]
    pub fn get_iseq_body_local_table_size(iseq: IseqPtr) -> c_uint;

    #[link_name = "rb_get_iseq_body_param_keyword"]
    pub fn get_iseq_body_param_keyword(iseq: IseqPtr) -> *const rb_seq_param_keyword_struct;

    #[link_name = "rb_get_iseq_body_param_size"]
    pub fn get_iseq_body_param_size(iseq: IseqPtr) -> c_uint;

    #[link_name = "rb_get_iseq_body_param_lead_num"]
    pub fn get_iseq_body_param_lead_num(iseq: IseqPtr) -> c_int;

    #[link_name = "rb_get_iseq_body_param_opt_num"]
    pub fn get_iseq_body_param_opt_num(iseq: IseqPtr) -> c_int;

    #[link_name = "rb_get_iseq_body_param_opt_table"]
    pub fn get_iseq_body_param_opt_table(iseq: IseqPtr) -> *const VALUE;

    #[link_name = "rb_get_cikw_keyword_len"]
    pub fn get_cikw_keyword_len(cikw: *const rb_callinfo_kwarg) -> c_int;

    #[link_name = "rb_get_cikw_keywords_idx"]
    pub fn get_cikw_keywords_idx(cikw: *const rb_callinfo_kwarg, idx: c_int) -> VALUE;

    #[link_name = "rb_get_call_data_ci"]
    pub fn get_call_data_ci(cd: *const rb_call_data) -> *const rb_callinfo;

    #[link_name = "rb_yarv_str_eql_internal"]
    pub fn rb_str_eql_internal(str1: VALUE, str2: VALUE) -> VALUE;

    #[link_name = "rb_yarv_ary_entry_internal"]
    pub fn rb_ary_entry_internal(ary: VALUE, offset: c_long) -> VALUE;

    #[link_name = "rb_FL_TEST"]
    pub fn FL_TEST(obj: VALUE, flags: VALUE) -> VALUE;

    #[link_name = "rb_FL_TEST_RAW"]
    pub fn FL_TEST_RAW(obj: VALUE, flags: VALUE) -> VALUE;

    #[link_name = "rb_RB_TYPE_P"]
    pub fn RB_TYPE_P(obj: VALUE, t: ruby_value_type) -> bool;

    #[link_name = "rb_BASIC_OP_UNREDEFINED_P"]
    pub fn BASIC_OP_UNREDEFINED_P(bop: ruby_basic_operators, klass: RedefinitionFlag) -> bool;

    #[link_name = "rb_RSTRUCT_LEN"]
    pub fn RSTRUCT_LEN(st: VALUE) -> c_long;

    #[link_name = "rb_RSTRUCT_SET"]
    pub fn RSTRUCT_SET(st: VALUE, k: c_int, v: VALUE);

    // Ruby only defines these in vm_insnhelper.c, not in any header.
    // Parsing it would result in a lot of duplicate definitions.
    pub fn rb_vm_opt_mod(recv: VALUE, obj: VALUE) -> VALUE;
    pub fn rb_vm_splat_array(flag: VALUE, ary: VALUE) -> VALUE;
    pub fn rb_vm_defined(
        ec: EcPtr,
        reg_cfp: CfpPtr,
        op_type: rb_num_t,
        obj: VALUE,
        v: VALUE,
    ) -> bool;
    pub fn rb_vm_set_ivar_idx(obj: VALUE, idx: u32, val: VALUE) -> VALUE;
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

    #[link_name = "rb_vm_ci_argc"]
    pub fn vm_ci_argc(ci: *const rb_callinfo) -> c_int;

    #[link_name = "rb_vm_ci_mid"]
    pub fn vm_ci_mid(ci: *const rb_callinfo) -> ID;

    #[link_name = "rb_vm_ci_flag"]
    pub fn vm_ci_flag(ci: *const rb_callinfo) -> c_uint;

    #[link_name = "rb_vm_ci_kwarg"]
    pub fn vm_ci_kwarg(ci: *const rb_callinfo) -> *const rb_callinfo_kwarg;

    #[link_name = "rb_METHOD_ENTRY_VISI"]
    pub fn METHOD_ENTRY_VISI(me: *const rb_callable_method_entry_t) -> rb_method_visibility_t;

    pub fn rb_str_bytesize(str: VALUE) -> VALUE;

    #[link_name = "rb_RCLASS_ORIGIN"]
    pub fn RCLASS_ORIGIN(v: VALUE) -> VALUE;
}

/// Helper so we can get a Rust string for insn_name()
pub fn insn_name(opcode: usize) -> String {
    use std::ffi::CStr;

    unsafe {
        // Look up Ruby's NULL-terminated insn name string
        let op_name = raw_insn_name(VALUE(opcode));

        // Convert the op name C string to a Rust string and concat
        let op_name = CStr::from_ptr(op_name).to_str().unwrap();

        // Convert into an owned string
        op_name.to_string()
    }
}

#[allow(unused_variables)]
pub fn insn_len(opcode: usize) -> u32 {
    #[cfg(test)]
    panic!("insn_len is a CRuby function, and we don't link against CRuby for Rust testing!");

    #[cfg(not(test))]
    unsafe {
        raw_insn_len(VALUE(opcode)).try_into().unwrap()
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

/// Pointer to an ISEQ
pub type IseqPtr = *const rb_iseq_t;

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

/// Opaque FILE type from the C standard library
#[repr(C)]
pub struct FILE {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

/// Opaque call-cache type from vm_callinfo.h
#[repr(C)]
pub struct rb_callcache {
    _data: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

/// Opaque call-info type from vm_callinfo.h
#[repr(C)]
pub struct rb_callinfo_kwarg {
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
        (cval & 7) != 0
    }

    /// Return true if the value is a Ruby immediate integer, flonum, static symbol, nil or false
    pub fn special_const_p(self) -> bool {
        self.immediate_p() || !self.test()
    }

    /// Return true if the value is a Ruby Fixnum (immediate-size integer)
    pub fn fixnum_p(self) -> bool {
        let VALUE(cval) = self;
        (cval & 1) == 1
    }

    /// Return true if the value is an immediate Ruby floating-point number (flonum)
    pub fn flonum_p(self) -> bool {
        let VALUE(cval) = self;
        (cval & 3) == 2
    }

    /// Return true for a static (non-heap) Ruby symbol
    pub fn static_sym_p(self) -> bool {
        let VALUE(cval) = self;
        (cval & 0xff) == RUBY_SYMBOL_FLAG
    }

    /// Returns true or false depending on whether the value is nil
    pub fn nil_p(self) -> bool {
        self == Qnil
    }

    /// Read the flags bits from the RBasic object, then return a Ruby type enum (e.g. RUBY_T_ARRAY)
    pub fn builtin_type(self) -> ruby_value_type {
        assert!(!self.special_const_p());

        let VALUE(cval) = self;
        let rbasic_ptr = cval as *const RBasic;
        let flags_bits: usize = unsafe { (*rbasic_ptr).flags }.as_usize();
        (flags_bits & (RUBY_T_MASK as usize)) as ruby_value_type
    }

    pub fn class_of(self) -> VALUE {
        unsafe { CLASS_OF(self) }
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
        us as usize
    }

    pub fn as_ptr<T>(self) -> *const T {
        let VALUE(us) = self;
        us as *const T
    }

    pub fn as_mut_ptr<T>(self) -> *mut T {
        let VALUE(us) = self;
        us as *mut T
    }

    /// For working with opague pointers and encoding null check.
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

    /// Assert that `self` is a method entry in debug builds
    pub fn as_cme(self) -> *const rb_callable_method_entry_t {
        let ptr: *const rb_callable_method_entry_t = self.as_ptr();

        #[cfg(debug_assertions)]
        if !ptr.is_null() {
            unsafe { rb_assert_cme_handle(self) }
        }

        ptr
    }
}

impl VALUE {
    pub fn fixnum_from_usize(item: usize) -> Self {
        assert!(item <= (RUBY_FIXNUM_MAX as usize)); // An unsigned will always be greater than RUBY_FIXNUM_MIN
        let k: usize = item.wrapping_add(item.wrapping_add(1));
        VALUE(k)
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
        uimm as i32
    }
}

/// Produce a Ruby string from a Rust string slice
#[cfg(feature = "asm_comments")]
pub fn rust_str_to_ruby(str: &str) -> VALUE {
    unsafe { rb_utf8_str_new(str.as_ptr() as *const i8, str.len() as i64) }
}

/// Produce a Ruby symbol from a Rust string slice
pub fn rust_str_to_sym(str: &str) -> VALUE {
    let c_str = CString::new(str).unwrap();
    let c_ptr: *const c_char = c_str.as_ptr();

    unsafe { rb_id2sym(rb_intern(c_ptr)) }
}

/// A location in Rust code for integrating with debugging facilities defined in C.
/// Use the [src_loc!] macro to crate an instance.
pub struct SourceLocation {
    pub file: CString,
    pub line: c_int,
}

/// Make a [SourceLocation] at the current spot.
macro_rules! src_loc {
    () => {
        // NOTE(alan): `CString::new` allocates so we might want to limit this to debug builds.
        $crate::cruby::SourceLocation {
            file: std::ffi::CString::new(file!()).unwrap(), // ASCII source file paths
            line: line!().try_into().unwrap(),              // not that many lines
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

    unsafe { rb_yjit_vm_lock_then_barrier(&mut recursive_lock_level, file, line) };

    let ret = match catch_unwind(func) {
        Ok(result) => result,
        Err(_) => {
            // Theoretically we can recover from some of these panics,
            // but it's too late if the unwind reaches here.
            use std::{process, str};

            let _ = catch_unwind(|| {
                // IO functions can panic too.
                eprintln!(
                    "YJIT panicked while holding VM lock acquired at {}:{}. Aborting...",
                    str::from_utf8(loc.file.as_bytes()).unwrap_or("<not utf8>"),
                    line,
                );
            });
            process::abort();
        }
    };

    unsafe { rb_yjit_vm_unlock(&mut recursive_lock_level, file, line) };

    ret
}

// Non-idiomatic capitalization for consistency with CRuby code
#[allow(non_upper_case_globals)]
pub const Qfalse: VALUE = VALUE(0);
#[allow(non_upper_case_globals)]
pub const Qnil: VALUE = VALUE(8);
#[allow(non_upper_case_globals)]
pub const Qtrue: VALUE = VALUE(20);
#[allow(non_upper_case_globals)]
pub const Qundef: VALUE = VALUE(52);

#[allow(unused)]
mod manual_defs {
    use super::*;

    pub const SIZEOF_VALUE: usize = 8;
    pub const SIZEOF_VALUE_I32: i32 = SIZEOF_VALUE as i32;

    pub const RUBY_LONG_MIN: isize = std::os::raw::c_long::MIN as isize;
    pub const RUBY_LONG_MAX: isize = std::os::raw::c_long::MAX as isize;

    pub const RUBY_FIXNUM_MIN: isize = RUBY_LONG_MIN / 2;
    pub const RUBY_FIXNUM_MAX: isize = RUBY_LONG_MAX / 2;
    pub const RUBY_FIXNUM_FLAG: usize = 0x1;

    // All these are defined in include/ruby/internal/special_consts.h,
    // in the same enum as RUBY_Qfalse, etc.
    // Do we want to switch to using Ruby's definition of Qnil, Qfalse, etc?
    pub const RUBY_SYMBOL_FLAG: usize = 0x0c;
    pub const RUBY_FLONUM_FLAG: usize = 0x2;
    pub const RUBY_FLONUM_MASK: usize = 0x3;
    pub const RUBY_SPECIAL_SHIFT: usize = 8;
    pub const RUBY_IMMEDIATE_MASK: usize = 0x7;

    // From vm_callinfo.h - uses calculation that seems to confuse bindgen
    pub const VM_CALL_ARGS_SPLAT: u32 = 1 << VM_CALL_ARGS_SPLAT_bit;
    pub const VM_CALL_ARGS_BLOCKARG: u32 = 1 << VM_CALL_ARGS_BLOCKARG_bit;
    pub const VM_CALL_FCALL: u32 = 1 << VM_CALL_FCALL_bit;
    pub const VM_CALL_KWARG: u32 = 1 << VM_CALL_KWARG_bit;
    pub const VM_CALL_KW_SPLAT: u32 = 1 << VM_CALL_KW_SPLAT_bit;
    pub const VM_CALL_TAILCALL: u32 = 1 << VM_CALL_TAILCALL_bit;

    // From internal/struct.h - in anonymous enum, so we can't easily import it
    pub const RSTRUCT_EMBED_LEN_MASK: usize = (RUBY_FL_USER2 | RUBY_FL_USER1) as usize;

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

    pub const RUBY_OFFSET_ROBJECT_AS_ARY: i32 = 16; // struct RObject, subfield "as.ary"
    pub const RUBY_OFFSET_ROBJECT_AS_HEAP_NUMIV: i32 = 16; // struct RObject, subfield "as.heap.numiv"
    pub const RUBY_OFFSET_ROBJECT_AS_HEAP_IVPTR: i32 = 24; // struct RObject, subfield "as.heap.ivptr"

    // Constants from rb_control_frame_t vm_core.h
    pub const RUBY_OFFSET_CFP_PC: i32 = 0;
    pub const RUBY_OFFSET_CFP_SP: i32 = 8;
    pub const RUBY_OFFSET_CFP_ISEQ: i32 = 16;
    pub const RUBY_OFFSET_CFP_SELF: i32 = 24;
    pub const RUBY_OFFSET_CFP_EP: i32 = 32;
    pub const RUBY_OFFSET_CFP_BLOCK_CODE: i32 = 40;
    pub const RUBY_OFFSET_CFP_BP: i32 = 48; // field __bp__
    pub const RUBY_OFFSET_CFP_JIT_RETURN: i32 = 56;
    pub const RUBY_SIZEOF_CONTROL_FRAME: usize = 64;

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
