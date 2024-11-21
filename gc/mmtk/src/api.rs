use crate::abi::RawVecOfObjRef;
use crate::abi::RubyBindingOptions;
use crate::abi::RubyUpcalls;
use crate::binding;
use crate::binding::RubyBinding;
use crate::mmtk;
use crate::Ruby;
use mmtk::memory_manager;
use mmtk::memory_manager::mmtk_init;
use mmtk::util::constants::MIN_OBJECT_SIZE;
use mmtk::util::options::PlanSelector;
use mmtk::util::Address;
use mmtk::util::ObjectReference;
use mmtk::util::VMMutatorThread;
use mmtk::AllocationSemantics;
use mmtk::MMTKBuilder;
use mmtk::Mutator;

pub type RubyMutator = Mutator<Ruby>;

// =============== Bootup ===============

#[no_mangle]
pub extern "C" fn mmtk_builder_default() -> *mut MMTKBuilder {
    let mut builder = MMTKBuilder::new_no_env_vars();
    builder.options.no_finalizer.set(true);

    // Hard code NoGC for now
    let plan_selector = "NoGC".parse::<PlanSelector>().unwrap();
    builder.options.plan.set(plan_selector);

    Box::into_raw(Box::new(builder))
}

#[no_mangle]
pub extern "C" fn mmtk_init_binding(
    builder: *mut MMTKBuilder,
    _binding_options: *const RubyBindingOptions,
    upcalls: *const RubyUpcalls,
) {
    crate::set_panic_hook();

    let builder = unsafe { Box::from_raw(builder) };
    let binding_options = RubyBindingOptions {ractor_check_mode: false, suffix_size: 0};
    let mmtk_boxed = mmtk_init(&builder);
    let mmtk_static = Box::leak(Box::new(mmtk_boxed));

    let binding = RubyBinding::new(mmtk_static, &binding_options, upcalls);

    crate::BINDING
        .set(binding)
        .unwrap_or_else(|_| panic!("Binding is already initialized"));
}

#[no_mangle]
pub extern "C" fn mmtk_bind_mutator(tls: VMMutatorThread) -> *mut RubyMutator {
    Box::into_raw(memory_manager::bind_mutator(mmtk(), tls))
}

// =============== Object allocation ===============

#[no_mangle]
pub extern "C" fn mmtk_alloc(
    mutator: *mut RubyMutator,
    size: usize,
    align: usize,
    offset: usize,
    semantics: AllocationSemantics,
) -> Address {
    let clamped_size = size.max(MIN_OBJECT_SIZE);
    memory_manager::alloc::<Ruby>(
        unsafe { &mut *mutator },
        clamped_size,
        align,
        offset,
        semantics,
    )
}

#[no_mangle]
pub extern "C" fn mmtk_post_alloc(
    mutator: *mut RubyMutator,
    refer: ObjectReference,
    bytes: usize,
    semantics: AllocationSemantics,
) {
    memory_manager::post_alloc::<Ruby>(unsafe { &mut *mutator }, refer, bytes, semantics)
}

// TODO: Replace with buffered mmtk_add_obj_free_candidates
#[no_mangle]
pub extern "C" fn mmtk_add_obj_free_candidate(object: ObjectReference) {
    binding().weak_proc.add_obj_free_candidate(object)
}

// =============== Heap walking ===============

#[no_mangle]
pub extern "C" fn mmtk_enumerate_objects(
    callback: extern "C" fn(ObjectReference, *mut libc::c_void),
    data: *mut libc::c_void,
) {
    crate::mmtk().enumerate_objects(|object| {
        callback(object, data);
    })
}

// =============== Finalizers ===============

#[no_mangle]
pub extern "C" fn mmtk_get_all_obj_free_candidates() -> RawVecOfObjRef {
    let vec = binding().weak_proc.get_all_obj_free_candidates();
    RawVecOfObjRef::from_vec(vec)
}

#[no_mangle]
pub extern "C" fn mmtk_free_raw_vec_of_obj_ref(raw_vec: RawVecOfObjRef) {
    unsafe { raw_vec.into_vec() };
}
