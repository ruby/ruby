use std::sync::atomic::Ordering;
use mmtk::util::options::PlanSelector;

use crate::abi::RawVecOfObjRef;
use crate::abi::RubyBindingOptions;
use crate::abi::RubyUpcalls;
use crate::binding;
use crate::binding::RubyBinding;
use crate::mmtk;
use crate::Ruby;
use crate::RubySlot;
use crate::utils::default_heap_max;
use crate::utils::parse_capacity;
use mmtk::memory_manager;
use mmtk::memory_manager::mmtk_init;
use mmtk::util::constants::MIN_OBJECT_SIZE;
use mmtk::util::options::GCTriggerSelector;
use mmtk::util::Address;
use mmtk::util::ObjectReference;
use mmtk::util::VMMutatorThread;
use mmtk::util::VMThread;
use mmtk::AllocationSemantics;
use mmtk::MMTKBuilder;
use mmtk::Mutator;

pub type RubyMutator = Mutator<Ruby>;

#[no_mangle]
pub extern "C" fn mmtk_is_live_object(object: ObjectReference) -> bool {
    memory_manager::is_live_object(object)
}

#[no_mangle]
pub extern "C" fn mmtk_is_reachable(object: ObjectReference) -> bool {
    object.is_reachable()
}

// =============== Bootup ===============

#[no_mangle]
pub extern "C" fn mmtk_builder_default() -> *mut MMTKBuilder {
    let mut builder = MMTKBuilder::new_no_env_vars();
    builder.options.no_finalizer.set(true);

    const DEFAULT_HEAP_MIN: usize = 1 << 20;

    let mmtk_threads: usize = std::env::var("MMTK_THREADS")
        .unwrap_or("0".to_string())
        .parse::<usize>()
        .unwrap_or(0);

    let mut mmtk_heap_min = match std::env::var("MMTK_HEAP_MIN") {
        Ok(min) => {
            let capa = parse_capacity(&min, DEFAULT_HEAP_MIN);
            if capa == DEFAULT_HEAP_MIN {
                eprintln!("MMTK_HEAP_MIN: value ({}) unusable, Using default.", min)
            };
            capa
        },
        Err(_) => DEFAULT_HEAP_MIN
    };

    let mut mmtk_heap_max = match std::env::var("MMTK_HEAP_MAX") {
        Ok(max) => {
            let capa = parse_capacity(&max, default_heap_max());
            if capa == default_heap_max() {
                eprintln!("MMTK_HEAP_MAX: value ({}) unusable, Using default.", max)
            };
            capa
        },
        Err(_) => default_heap_max()
    };

    if mmtk_heap_min >= mmtk_heap_max {
        println!("MMTK_HEAP_MIN({}) >= MMTK_HEAP_MAX({}). Using default values.", mmtk_heap_min, mmtk_heap_max);
        mmtk_heap_min = DEFAULT_HEAP_MIN;
        mmtk_heap_max = default_heap_max();
    }

    let mmtk_mode = match std::env::var("MMTK_HEAP_MODE") {
        Ok(mode) if (mode == "fixed") => GCTriggerSelector::FixedHeapSize(mmtk_heap_max),
        Ok(_) | Err(_) => GCTriggerSelector::DynamicHeapSize(mmtk_heap_min, mmtk_heap_max)
    };

    // Parse the env var, if it's not found set the plan name to MarkSweep
    let plan_name = std::env::var("MMTK_PLAN")
        .unwrap_or(String::from("MarkSweep"));

    // Parse the plan name into a valid MMTK Plan, if the name is not a valid plan use MarkSweep
    let plan_selector = plan_name.parse::<PlanSelector>()
        .unwrap_or("MarkSweep".parse::<PlanSelector>().unwrap());

    builder.options.plan.set(plan_selector);

    // Between 1MiB and 500MiB
    builder.options.gc_trigger.set(mmtk_mode);

    if mmtk_threads > 0 {
        builder.options.threads.set(mmtk_threads);
    }

    Box::into_raw(Box::new(builder))
}

#[no_mangle]
pub extern "C" fn mmtk_init_binding(
    builder: *mut MMTKBuilder,
    _binding_options: *const RubyBindingOptions,
    upcalls: *const RubyUpcalls,
    weak_reference_dead_value: ObjectReference,
) {
    crate::set_panic_hook();

    let builder = unsafe { Box::from_raw(builder) };
    let binding_options = RubyBindingOptions {ractor_check_mode: false, suffix_size: 0};
    let mmtk_boxed = mmtk_init(&builder);
    let mmtk_static = Box::leak(Box::new(mmtk_boxed));

    let binding = RubyBinding::new(mmtk_static, &binding_options, upcalls, weak_reference_dead_value);

    crate::BINDING
        .set(binding)
        .unwrap_or_else(|_| panic!("Binding is already initialized"));
}

#[no_mangle]
pub extern "C" fn mmtk_initialize_collection(tls: VMThread) {
    memory_manager::initialize_collection(mmtk(), tls)
}

#[no_mangle]
pub extern "C" fn mmtk_bind_mutator(tls: VMMutatorThread) -> *mut RubyMutator {
    Box::into_raw(memory_manager::bind_mutator(mmtk(), tls))
}

#[no_mangle]
pub extern "C" fn mmtk_destroy_mutator(mutator: *mut RubyMutator) {
    // notify mmtk-core about destroyed mutator
    memory_manager::destroy_mutator(unsafe { &mut *mutator });
    // turn the ptr back to a box, and let Rust properly reclaim it
    let _ = unsafe { Box::from_raw(mutator) };
}

// =============== GC ===============

#[no_mangle]
pub extern "C" fn mmtk_handle_user_collection_request(tls: VMMutatorThread) {
    memory_manager::handle_user_collection_request::<Ruby>(mmtk(), tls);
}

#[no_mangle]
pub extern "C" fn mmtk_set_gc_enabled(enable: bool) {
    crate::CONFIGURATION.gc_enabled.store(enable, Ordering::Relaxed);
}

#[no_mangle]
pub extern "C" fn mmtk_gc_enabled_p() -> bool {
    crate::CONFIGURATION.gc_enabled.load(Ordering::Relaxed)
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

// =============== Marking ===============

#[no_mangle]
pub extern "C" fn mmtk_mark_weak(ptr: &'static mut ObjectReference) {
    binding().weak_proc.add_weak_reference(ptr);
}

#[no_mangle]
pub extern "C" fn mmtk_remove_weak(ptr: &ObjectReference) {
    binding().weak_proc.remove_weak_reference(ptr);
}

// =============== Write barriers ===============

#[no_mangle]
pub extern "C" fn mmtk_object_reference_write_post(
    mutator: *mut RubyMutator,
    object: ObjectReference,
) {
    let ignored_slot = RubySlot::from_address(Address::ZERO);
    let ignored_target = ObjectReference::from_raw_address(Address::ZERO);
    mmtk::memory_manager::object_reference_write_post(
        unsafe { &mut *mutator },
        object,
        ignored_slot,
        ignored_target,
    )
}

#[no_mangle]
pub extern "C" fn mmtk_register_wb_unprotected_object(object: ObjectReference) {
    crate::binding().register_wb_unprotected_object(object)
}

#[no_mangle]
pub extern "C" fn mmtk_object_wb_unprotected_p(object: ObjectReference) -> bool {
    crate::binding().object_wb_unprotected_p(object)
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

// =============== Forking ===============

#[no_mangle]
pub extern "C" fn mmtk_before_fork() {
    mmtk().prepare_to_fork();
    binding().join_all_gc_threads();
}

#[no_mangle]
pub extern "C" fn mmtk_after_fork(tls: VMThread) {
    mmtk().after_fork(tls);
}

// =============== Statistics ===============

#[no_mangle]
pub extern "C" fn mmtk_total_bytes() -> usize {
    memory_manager::total_bytes(mmtk())
}

#[no_mangle]
pub extern "C" fn mmtk_used_bytes() -> usize {
    memory_manager::used_bytes(mmtk())
}

#[no_mangle]
pub extern "C" fn mmtk_free_bytes() -> usize {
    memory_manager::free_bytes(mmtk())
}

#[no_mangle]
pub extern "C" fn mmtk_starting_heap_address() -> Address {
    memory_manager::starting_heap_address()
}

#[no_mangle]
pub extern "C" fn mmtk_last_heap_address() -> Address {
    memory_manager::last_heap_address()
}

// =============== Miscellaneous ===============

#[no_mangle]
pub extern "C" fn mmtk_is_mmtk_object(addr: Address) -> bool {
    debug_assert!(!addr.is_zero());
    debug_assert!(addr.is_aligned_to(mmtk::util::is_mmtk_object::VO_BIT_REGION_SIZE));
    memory_manager::is_mmtk_object(addr).is_some()
}
