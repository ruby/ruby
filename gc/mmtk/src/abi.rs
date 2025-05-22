use crate::api::RubyMutator;
use crate::Ruby;
use libc::c_int;
use mmtk::scheduler::GCWorker;
use mmtk::util::{Address, ObjectReference, VMMutatorThread, VMWorkerThread};

// For the C binding
pub const OBJREF_OFFSET: usize = 8;
pub const MIN_OBJ_ALIGN: usize = 8; // Even on 32-bit machine.  A Ruby object is at least 40 bytes large.

pub const GC_THREAD_KIND_WORKER: libc::c_int = 1;

const HAS_MOVED_GFIELDSTBL: usize = 1 << 63;
const HIDDEN_SIZE_MASK: usize = 0x0000FFFFFFFFFFFF;

// Should keep in sync with C code.
const RUBY_FL_EXIVAR: usize = 1 << 10;

// An opaque type for the C counterpart.
#[allow(non_camel_case_types)]
pub struct st_table;

/// Provide convenient methods for accessing Ruby objects.
/// TODO: Wrap C functions in `RubyUpcalls` as Rust-friendly methods.
pub struct RubyObjectAccess {
    objref: ObjectReference,
}

impl RubyObjectAccess {
    pub fn from_objref(objref: ObjectReference) -> Self {
        Self { objref }
    }

    pub fn obj_start(&self) -> Address {
        self.objref.to_raw_address().sub(Self::prefix_size())
    }

    pub fn payload_addr(&self) -> Address {
        self.objref.to_raw_address()
    }

    pub fn suffix_addr(&self) -> Address {
        self.objref.to_raw_address().add(self.payload_size())
    }

    pub fn obj_end(&self) -> Address {
        self.suffix_addr() + Self::suffix_size()
    }

    fn hidden_field(&self) -> Address {
        self.obj_start()
    }

    fn load_hidden_field(&self) -> usize {
        unsafe { self.hidden_field().load::<usize>() }
    }

    fn update_hidden_field<F>(&self, f: F)
    where
        F: FnOnce(usize) -> usize,
    {
        let old_value = self.load_hidden_field();
        let new_value = f(old_value);
        unsafe {
            self.hidden_field().store(new_value);
        }
    }

    pub fn payload_size(&self) -> usize {
        self.load_hidden_field() & HIDDEN_SIZE_MASK
    }

    pub fn set_payload_size(&self, size: usize) {
        debug_assert!((size & HIDDEN_SIZE_MASK) == size);
        self.update_hidden_field(|old| old & !HIDDEN_SIZE_MASK | size & HIDDEN_SIZE_MASK);
    }

    fn flags_field(&self) -> Address {
        self.objref.to_raw_address()
    }

    pub fn load_flags(&self) -> usize {
        unsafe { self.flags_field().load::<usize>() }
    }

    pub fn has_exivar_flag(&self) -> bool {
        (self.load_flags() & RUBY_FL_EXIVAR) != 0
    }

    pub fn has_moved_gfields_tbl(&self) -> bool {
        (self.load_hidden_field() & HAS_MOVED_GFIELDSTBL) != 0
    }

    pub fn set_has_moved_gfields_tbl(&self) {
        self.update_hidden_field(|old| old | HAS_MOVED_GFIELDSTBL)
    }

    pub fn clear_has_moved_gfields_tbl(&self) {
        self.update_hidden_field(|old| old & !HAS_MOVED_GFIELDSTBL)
    }

    pub fn prefix_size() -> usize {
        // Currently, a hidden size field of word size is placed before each object.
        OBJREF_OFFSET
    }

    pub fn suffix_size() -> usize {
        // In RACTOR_CHECK_MODE, Ruby hides a field after each object to hold the Ractor ID.
        unsafe { crate::BINDING_FAST.suffix_size }
    }

    pub fn object_size(&self) -> usize {
        Self::prefix_size() + self.payload_size() + Self::suffix_size()
    }
}

type ObjectClosureFunction =
    extern "C" fn(*mut libc::c_void, *mut libc::c_void, ObjectReference, bool) -> ObjectReference;

#[repr(C)]
pub struct ObjectClosure {
    /// The function to be called from C.
    pub c_function: ObjectClosureFunction,
    /// The pointer to the Rust-level closure object.
    pub rust_closure: *mut libc::c_void,
}

impl Default for ObjectClosure {
    fn default() -> Self {
        Self {
            c_function: THE_UNREGISTERED_CLOSURE_FUNC,
            rust_closure: std::ptr::null_mut(),
        }
    }
}

/// Rust doesn't require function items to have a unique address.
/// We therefore force using this particular constant.
///
/// See: https://rust-lang.github.io/rust-clippy/master/index.html#fn_address_comparisons
const THE_UNREGISTERED_CLOSURE_FUNC: ObjectClosureFunction = ObjectClosure::c_function_unregistered;

impl ObjectClosure {
    /// Set this ObjectClosure temporarily to `visit_object`, and execute `f`.  During the execution of
    /// `f`, the Ruby VM may call this ObjectClosure.  When the Ruby VM calls this ObjectClosure,
    /// it effectively calls `visit_object`.
    ///
    /// This method is intended to run Ruby VM code in `f` with temporarily modified behavior of
    /// `rb_gc_mark`, `rb_gc_mark_movable` and `rb_gc_location`
    ///
    /// Both `f` and `visit_object` may access and modify local variables in the environment where
    /// `set_temporarily_and_run_code` called.
    ///
    /// Note that this function is not reentrant.  Don't call this function in either `callback` or
    /// `f`.
    pub fn set_temporarily_and_run_code<'env, T, F1, F2>(
        &mut self,
        mut visit_object: F1,
        f: F2,
    ) -> T
    where
        F1: 'env + FnMut(&'static mut GCWorker<Ruby>, ObjectReference, bool) -> ObjectReference,
        F2: 'env + FnOnce() -> T,
    {
        debug_assert!(
            std::ptr::fn_addr_eq(self.c_function, THE_UNREGISTERED_CLOSURE_FUNC),
            "set_temporarily_and_run_code is recursively called."
        );
        self.c_function = Self::c_function_registered::<F1>;
        self.rust_closure = &mut visit_object as *mut F1 as *mut libc::c_void;
        let result = f();
        *self = Default::default();
        result
    }

    extern "C" fn c_function_registered<F>(
        rust_closure: *mut libc::c_void,
        worker: *mut libc::c_void,
        object: ObjectReference,
        pin: bool,
    ) -> ObjectReference
    where
        F: FnMut(&'static mut GCWorker<Ruby>, ObjectReference, bool) -> ObjectReference,
    {
        let rust_closure = unsafe { &mut *(rust_closure as *mut F) };
        let worker = unsafe { &mut *(worker as *mut GCWorker<Ruby>) };
        rust_closure(worker, object, pin)
    }

    extern "C" fn c_function_unregistered(
        _rust_closure: *mut libc::c_void,
        worker: *mut libc::c_void,
        object: ObjectReference,
        pin: bool,
    ) -> ObjectReference {
        let worker = unsafe { &mut *(worker as *mut GCWorker<Ruby>) };
        panic!(
            "object_closure is not set.  worker ordinal: {}, object: {}, pin: {}",
            worker.ordinal, object, pin
        );
    }
}

#[repr(C)]
pub struct GCThreadTLS {
    pub kind: libc::c_int,
    pub gc_context: *mut libc::c_void,
    pub object_closure: ObjectClosure,
}

impl GCThreadTLS {
    fn new(kind: libc::c_int, gc_context: *mut libc::c_void) -> Self {
        Self {
            kind,
            gc_context,
            object_closure: Default::default(),
        }
    }

    pub fn for_worker(gc_context: *mut GCWorker<Ruby>) -> Self {
        Self::new(GC_THREAD_KIND_WORKER, gc_context as *mut libc::c_void)
    }

    pub fn from_vwt(vwt: VMWorkerThread) -> *mut GCThreadTLS {
        unsafe { std::mem::transmute(vwt) }
    }

    /// Cast a pointer to `GCThreadTLS` to a ref, with assertion for null pointer.
    ///
    /// # Safety
    ///
    /// Has undefined behavior if `ptr` is invalid.
    pub unsafe fn check_cast(ptr: *mut GCThreadTLS) -> &'static mut GCThreadTLS {
        assert!(!ptr.is_null());
        let result = &mut *ptr;
        debug_assert!({
            let kind = result.kind;
            kind == GC_THREAD_KIND_WORKER
        });
        result
    }

    /// Cast a pointer to `VMWorkerThread` to a ref, with assertion for null pointer.
    ///
    /// # Safety
    ///
    /// Has undefined behavior if `ptr` is invalid.
    pub unsafe fn from_vwt_check(vwt: VMWorkerThread) -> &'static mut GCThreadTLS {
        let ptr = Self::from_vwt(vwt);
        Self::check_cast(ptr)
    }

    #[allow(clippy::not_unsafe_ptr_arg_deref)] // `transmute` does not dereference pointer
    pub fn to_vwt(ptr: *mut Self) -> VMWorkerThread {
        unsafe { std::mem::transmute(ptr) }
    }

    pub fn worker<'w>(&mut self) -> &'w mut GCWorker<Ruby> {
        // NOTE: The returned ref points to the worker which does not have the same lifetime as self.
        assert!(self.kind == GC_THREAD_KIND_WORKER);
        unsafe { &mut *(self.gc_context as *mut GCWorker<Ruby>) }
    }
}

#[repr(C)]
#[derive(Clone)]
pub struct RawVecOfObjRef {
    pub ptr: *mut ObjectReference,
    pub len: usize,
    pub capa: usize,
}

impl RawVecOfObjRef {
    pub fn from_vec(vec: Vec<ObjectReference>) -> RawVecOfObjRef {
        // Note: Vec::into_raw_parts is unstable. We implement it manually.
        let mut vec = std::mem::ManuallyDrop::new(vec);
        let (ptr, len, capa) = (vec.as_mut_ptr(), vec.len(), vec.capacity());

        RawVecOfObjRef { ptr, len, capa }
    }

    /// # Safety
    ///
    /// This function turns raw pointer into a Vec without check.
    pub unsafe fn into_vec(self) -> Vec<ObjectReference> {
        Vec::from_raw_parts(self.ptr, self.len, self.capa)
    }
}

impl From<Vec<ObjectReference>> for RawVecOfObjRef {
    fn from(v: Vec<ObjectReference>) -> Self {
        Self::from_vec(v)
    }
}

#[repr(C)]
#[derive(Clone)]
pub struct RubyBindingOptions {
    pub ractor_check_mode: bool,
    pub suffix_size: usize,
}

#[repr(C)]
#[derive(Clone)]
pub struct RubyUpcalls {
    pub init_gc_worker_thread: extern "C" fn(gc_worker_tls: *mut GCThreadTLS),
    pub is_mutator: extern "C" fn() -> bool,
    pub stop_the_world: extern "C" fn(),
    pub resume_mutators: extern "C" fn(),
    pub block_for_gc: extern "C" fn(tls: VMMutatorThread),
    pub number_of_mutators: extern "C" fn() -> usize,
    pub get_mutators: extern "C" fn(
        visit_mutator: extern "C" fn(*mut RubyMutator, *mut libc::c_void),
        data: *mut libc::c_void,
    ),
    pub scan_gc_roots: extern "C" fn(),
    pub scan_objspace: extern "C" fn(),
    pub scan_object_ruby_style: extern "C" fn(object: ObjectReference),
    pub call_gc_mark_children: extern "C" fn(object: ObjectReference),
    pub call_obj_free: extern "C" fn(object: ObjectReference),
    pub vm_live_bytes: extern "C" fn() -> usize,
    pub update_global_tables: extern "C" fn(tbl_idx: c_int),
    pub global_tables_count: extern "C" fn() -> c_int,
    pub update_finalizer_table: extern "C" fn(),
}

unsafe impl Sync for RubyUpcalls {}

#[repr(C)]
#[derive(Clone)]
pub struct HeapBounds {
    pub start: *mut libc::c_void,
    pub end: *mut libc::c_void,
}
