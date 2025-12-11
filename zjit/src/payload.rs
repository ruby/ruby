use std::ffi::c_void;
use std::ptr::NonNull;
use crate::codegen::IseqCallRef;
use crate::stats::CompileError;
use crate::{cruby::*, profile::IseqProfile, virtualmem::CodePtr};

/// This is all the data ZJIT stores on an ISEQ. We mark objects in this struct on GC.
#[derive(Debug)]
pub struct IseqPayload {
    /// Type information of YARV instruction operands
    pub profile: IseqProfile,
    /// JIT code versions. Different versions should have different assumptions.
    pub versions: Vec<IseqVersionRef>,
}

impl IseqPayload {
    fn new(iseq_size: u32) -> Self {
        Self {
            profile: IseqProfile::new(iseq_size),
            versions: vec![],
        }
    }
}

/// JIT code version. When the same ISEQ is compiled with a different assumption, a new version is created.
#[derive(Debug)]
pub struct IseqVersion {
    /// ISEQ pointer. Stored here to minimize the size of PatchPoint.
    pub iseq: IseqPtr,

    /// Compilation status of the ISEQ. It has the JIT code address of the first block if Compiled.
    pub status: IseqStatus,

    /// GC offsets of the JIT code. These are the addresses of objects that need to be marked.
    pub gc_offsets: Vec<CodePtr>,

    /// JIT-to-JIT calls from the ISEQ. The IseqPayload's ISEQ is the caller of it.
    pub outgoing: Vec<IseqCallRef>,

    /// JIT-to-JIT calls to the ISEQ. The IseqPayload's ISEQ is the callee of it.
    pub incoming: Vec<IseqCallRef>,
}

/// We use a raw pointer instead of Rc to save space for refcount
pub type IseqVersionRef = NonNull<IseqVersion>;

impl IseqVersion {
    /// Allocate a new IseqVersion to be compiled
    pub fn new(iseq: IseqPtr) -> IseqVersionRef {
        let version = Self {
            iseq,
            status: IseqStatus::NotCompiled,
            gc_offsets: vec![],
            outgoing: vec![],
            incoming: vec![],
        };
        let version_ptr = Box::into_raw(Box::new(version));
        NonNull::new(version_ptr).expect("no null from Box")
    }
}

/// Set of CodePtrs for an ISEQ
#[derive(Clone, Debug, PartialEq)]
pub struct IseqCodePtrs {
    /// Entry for the interpreter
    pub start_ptr: CodePtr,
    /// Entries for JIT-to-JIT calls
    pub jit_entry_ptrs: Vec<CodePtr>,
}

#[derive(Debug, PartialEq)]
pub enum IseqStatus {
    Compiled(IseqCodePtrs),
    CantCompile(CompileError),
    NotCompiled,
    Invalidated,
}

/// Get a pointer to the payload object associated with an ISEQ. Create one if none exists.
pub fn get_or_create_iseq_payload_ptr(iseq: IseqPtr) -> *mut IseqPayload {
    type VoidPtr = *mut c_void;

    unsafe {
        let payload = rb_iseq_get_zjit_payload(iseq);
        if payload.is_null() {
            // Allocate a new payload with Box and transfer ownership to the GC.
            // We drop the payload with Box::from_raw when the GC frees the ISEQ and calls us.
            // NOTE(alan): Sometimes we read from an ISEQ without ever writing to it.
            // We allocate in those cases anyways.
            let iseq_size = get_iseq_encoded_size(iseq);
            let new_payload = IseqPayload::new(iseq_size);
            let new_payload = Box::into_raw(Box::new(new_payload));
            rb_iseq_set_zjit_payload(iseq, new_payload as VoidPtr);

            new_payload
        } else {
            payload as *mut IseqPayload
        }
    }
}

/// Get the payload object associated with an ISEQ. Create one if none exists.
pub fn get_or_create_iseq_payload(iseq: IseqPtr) -> &'static mut IseqPayload {
    let payload_non_null = get_or_create_iseq_payload_ptr(iseq);
    payload_ptr_as_mut(payload_non_null)
}

/// Convert an IseqPayload pointer to a mutable reference. Only one reference
/// should be kept at a time.
pub fn payload_ptr_as_mut(payload_ptr: *mut IseqPayload) -> &'static mut IseqPayload {
    // SAFETY: we should have the VM lock and all other Ruby threads should be asleep. So we have
    // exclusive mutable access.
    // Hmm, nothing seems to stop calling this on the same
    // iseq twice, though, which violates aliasing rules.
    unsafe { payload_ptr.as_mut() }.unwrap()
}
