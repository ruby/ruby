//! Upcalls from MMTk to the Ruby VM.
//!
//! The upcalls are implemented in C (`gc/mmtk/mmtk.c`) and declared here as
//! `extern "C"` functions.  Since `libmmtk_ruby.a` is statically linked into
//! `librubygc` together with the C code, the linker resolves these symbols
//! directly.  There is no function pointer indirection, and calls can be
//! inlined when building with cross-language LTO.

use libc::c_int;
use libc::c_void;

use mmtk::util::ObjectReference;
use mmtk::util::VMMutatorThread;

use crate::abi::GCThreadTLS;
use crate::api::RubyMutator;

// The C functions must have external linkage (i.e. not `static`) so that the
// linker can resolve these symbols.
unsafe extern "C" {
    fn rb_mmtk_init_gc_worker_thread(gc_worker_tls: *mut GCThreadTLS);
    fn rb_mmtk_is_mutator() -> bool;
    fn rb_mmtk_stop_the_world();
    fn rb_mmtk_resume_mutators(gc_may_move: bool);
    fn rb_mmtk_block_for_gc(tls: VMMutatorThread);
    fn rb_mmtk_before_updating_jit_code();
    fn rb_mmtk_after_updating_jit_code();
    fn rb_mmtk_number_of_mutators() -> usize;
    fn rb_mmtk_get_mutators(
        visit_mutator: extern "C" fn(*mut RubyMutator, *mut c_void),
        data: *mut c_void,
    );
    fn rb_mmtk_scan_gc_roots();
    fn rb_mmtk_scan_objspace();
    fn rb_mmtk_move_obj_during_marking(from: ObjectReference, to: ObjectReference);
    fn rb_mmtk_obj_optimal_size(object: ObjectReference) -> usize;
    fn rb_mmtk_update_object_references(object: ObjectReference);
    fn rb_mmtk_call_gc_mark_children(object: ObjectReference);
    fn rb_mmtk_handle_weak_references(object: ObjectReference, moving: bool);
    fn rb_mmtk_call_obj_free(object: ObjectReference);
    fn rb_mmtk_vm_live_bytes() -> usize;
    fn rb_mmtk_update_global_tables(tbl_idx: c_int, moving: bool);
    fn rb_mmtk_global_tables_count() -> c_int;
    fn rb_mmtk_update_finalizer_table();
    fn rb_mmtk_mutator_thread_panic_handler() -> !;
    fn rb_mmtk_gc_thread_panic_handler() -> !;
}

// `gc_worker_tls` comes from a Box::into_raw'd GCThreadTLS and is valid.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
#[inline]
pub fn init_gc_worker_thread(gc_worker_tls: *mut GCThreadTLS) {
    unsafe { rb_mmtk_init_gc_worker_thread(gc_worker_tls) }
}

#[inline]
pub fn is_mutator() -> bool {
    unsafe { rb_mmtk_is_mutator() }
}

#[inline]
pub fn stop_the_world() {
    unsafe { rb_mmtk_stop_the_world() }
}

#[inline]
pub fn resume_mutators(gc_may_move: bool) {
    unsafe { rb_mmtk_resume_mutators(gc_may_move) }
}

#[inline]
pub fn block_for_gc(tls: VMMutatorThread) {
    unsafe { rb_mmtk_block_for_gc(tls) }
}

#[inline]
pub fn before_updating_jit_code() {
    unsafe { rb_mmtk_before_updating_jit_code() }
}

#[inline]
pub fn after_updating_jit_code() {
    unsafe { rb_mmtk_after_updating_jit_code() }
}

#[inline]
pub fn number_of_mutators() -> usize {
    unsafe { rb_mmtk_number_of_mutators() }
}

// `data` is an opaque pointer passed through to `visit_mutator`; the caller
// guarantees it is valid for the duration of the call.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
#[inline]
pub fn get_mutators(
    visit_mutator: extern "C" fn(*mut RubyMutator, *mut c_void),
    data: *mut c_void,
) {
    unsafe { rb_mmtk_get_mutators(visit_mutator, data) }
}

#[inline]
pub fn scan_gc_roots() {
    unsafe { rb_mmtk_scan_gc_roots() }
}

#[inline]
pub fn scan_objspace() {
    unsafe { rb_mmtk_scan_objspace() }
}

#[inline]
pub fn move_obj_during_marking(from: ObjectReference, to: ObjectReference) {
    unsafe { rb_mmtk_move_obj_during_marking(from, to) }
}

#[inline]
pub fn obj_optimal_size(object: ObjectReference) -> usize {
    unsafe { rb_mmtk_obj_optimal_size(object) }
}

#[inline]
pub fn update_object_references(object: ObjectReference) {
    unsafe { rb_mmtk_update_object_references(object) }
}

#[inline]
pub fn call_gc_mark_children(object: ObjectReference) {
    unsafe { rb_mmtk_call_gc_mark_children(object) }
}

#[inline]
pub fn handle_weak_references(object: ObjectReference, moving: bool) {
    unsafe { rb_mmtk_handle_weak_references(object, moving) }
}

#[inline]
pub fn call_obj_free(object: ObjectReference) {
    unsafe { rb_mmtk_call_obj_free(object) }
}

#[inline]
pub fn vm_live_bytes() -> usize {
    unsafe { rb_mmtk_vm_live_bytes() }
}

#[inline]
pub fn update_global_tables(tbl_idx: c_int, moving: bool) {
    unsafe { rb_mmtk_update_global_tables(tbl_idx, moving) }
}

#[inline]
pub fn global_tables_count() -> c_int {
    unsafe { rb_mmtk_global_tables_count() }
}

#[inline]
pub fn update_finalizer_table() {
    unsafe { rb_mmtk_update_finalizer_table() }
}

#[inline]
pub fn mutator_thread_panic_handler() -> ! {
    unsafe { rb_mmtk_mutator_thread_panic_handler() }
}

#[inline]
pub fn gc_thread_panic_handler() -> ! {
    unsafe { rb_mmtk_gc_thread_panic_handler() }
}
