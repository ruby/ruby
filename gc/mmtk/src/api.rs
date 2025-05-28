// Functions in this module are unsafe for one reason:
// They are called by C functions and they need to pass raw pointers to Rust.
#![allow(clippy::missing_safety_doc)]

use mmtk::util::options::PlanSelector;
use std::sync::atomic::Ordering;

use crate::abi::RawVecOfObjRef;
use crate::abi::RubyBindingOptions;
use crate::abi::RubyUpcalls;
use crate::binding;
use crate::binding::RubyBinding;
use crate::mmtk;
use crate::utils::default_heap_max;
use crate::utils::parse_capacity;
use crate::Ruby;
use crate::RubySlot;
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

fn mmtk_builder_default_parse_threads() -> usize {
    let threads_str = std::env::var("MMTK_THREADS").unwrap_or("0".to_string());

    threads_str.parse::<usize>().unwrap_or_else(|_err| {
        eprintln!("[FATAL] Invalid MMTK_THREADS {}", threads_str);
        std::process::exit(1);
    })
}

fn mmtk_builder_default_parse_heap_min() -> usize {
    const DEFAULT_HEAP_MIN: usize = 1 << 20;

    let heap_min_str = std::env::var("MMTK_HEAP_MIN").unwrap_or(DEFAULT_HEAP_MIN.to_string());

    let size = parse_capacity(&heap_min_str, 0);
    if size == 0 {
        eprintln!("[FATAL] Invalid MMTK_HEAP_MIN {}", heap_min_str);
        std::process::exit(1);
    }

    size
}

fn mmtk_builder_default_parse_heap_max() -> usize {
    let heap_max_str = std::env::var("MMTK_HEAP_MAX").unwrap_or(default_heap_max().to_string());

    let size = parse_capacity(&heap_max_str, 0);
    if size == 0 {
        eprintln!("[FATAL] Invalid MMTK_HEAP_MAX {}", heap_max_str);
        std::process::exit(1);
    }

    size
}

fn mmtk_builder_default_parse_heap_mode(heap_min: usize, heap_max: usize) -> GCTriggerSelector {
    let heap_mode_str = std::env::var("MMTK_HEAP_MODE").unwrap_or("dynamic".to_string());

    match heap_mode_str.as_str() {
        "fixed" => GCTriggerSelector::FixedHeapSize(heap_max),
        "dynamic" => GCTriggerSelector::DynamicHeapSize(heap_min, heap_max),
        _ => {
            eprintln!("[FATAL] Invalid MMTK_HEAP_MODE {}", heap_mode_str);
            std::process::exit(1);
        }
    }
}

fn mmtk_builder_default_parse_plan() -> PlanSelector {
    let plan_str = std::env::var("MMTK_PLAN").unwrap_or("Immix".to_string());

    match plan_str.as_str() {
        "NoGC" => PlanSelector::NoGC,
        "MarkSweep" => PlanSelector::MarkSweep,
        "Immix" => PlanSelector::Immix,
        _ => {
            eprintln!("[FATAL] Invalid MMTK_PLAN {}", plan_str);
            std::process::exit(1);
        }
    }
}

#[no_mangle]
pub extern "C" fn mmtk_builder_default() -> *mut MMTKBuilder {
    let mut builder = MMTKBuilder::new_no_env_vars();
    builder.options.no_finalizer.set(true);

    let threads = mmtk_builder_default_parse_threads();
    if threads > 0 {
        builder.options.threads.set(threads);
    }

    let heap_min = mmtk_builder_default_parse_heap_min();

    let heap_max = mmtk_builder_default_parse_heap_max();

    if heap_min >= heap_max {
        eprintln!(
            "[FATAL] MMTK_HEAP_MIN({}) >= MMTK_HEAP_MAX({})",
            heap_min, heap_max
        );
        std::process::exit(1);
    }

    builder
        .options
        .gc_trigger
        .set(mmtk_builder_default_parse_heap_mode(heap_min, heap_max));

    builder.options.plan.set(mmtk_builder_default_parse_plan());

    Box::into_raw(Box::new(builder))
}

#[no_mangle]
pub unsafe extern "C" fn mmtk_init_binding(
    builder: *mut MMTKBuilder,
    _binding_options: *const RubyBindingOptions,
    upcalls: *const RubyUpcalls,
    weak_reference_dead_value: ObjectReference,
) {
    crate::set_panic_hook();

    let builder = unsafe { Box::from_raw(builder) };
    let binding_options = RubyBindingOptions {
        ractor_check_mode: false,
        suffix_size: 0,
    };
    let mmtk_boxed = mmtk_init(&builder);
    let mmtk_static = Box::leak(Box::new(mmtk_boxed));

    let binding = RubyBinding::new(
        mmtk_static,
        &binding_options,
        upcalls,
        weak_reference_dead_value,
    );

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
pub unsafe extern "C" fn mmtk_destroy_mutator(mutator: *mut RubyMutator) {
    // notify mmtk-core about destroyed mutator
    memory_manager::destroy_mutator(unsafe { &mut *mutator });
    // turn the ptr back to a box, and let Rust properly reclaim it
    let _ = unsafe { Box::from_raw(mutator) };
}

// =============== GC ===============

#[no_mangle]
pub extern "C" fn mmtk_handle_user_collection_request(
    tls: VMMutatorThread,
    force: bool,
    exhaustive: bool,
) {
    crate::mmtk().handle_user_collection_request(tls, force, exhaustive);
}

#[no_mangle]
pub extern "C" fn mmtk_set_gc_enabled(enable: bool) {
    crate::CONFIGURATION
        .gc_enabled
        .store(enable, Ordering::Relaxed);
}

#[no_mangle]
pub extern "C" fn mmtk_gc_enabled_p() -> bool {
    crate::CONFIGURATION.gc_enabled.load(Ordering::Relaxed)
}

// =============== Object allocation ===============

#[no_mangle]
pub unsafe extern "C" fn mmtk_alloc(
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
pub unsafe extern "C" fn mmtk_post_alloc(
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
pub unsafe extern "C" fn mmtk_object_reference_write_post(
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

#[no_mangle]
pub extern "C" fn mmtk_worker_count() -> usize {
    memory_manager::num_of_workers(mmtk())
}

#[no_mangle]
pub extern "C" fn mmtk_plan() -> *const u8 {
    static NO_GC: &[u8] = b"NoGC\0";
    static MARK_SWEEP: &[u8] = b"MarkSweep\0";
    static IMMIX: &[u8] = b"Immix\0";

    match *crate::BINDING.get().unwrap().mmtk.get_options().plan {
        PlanSelector::NoGC => NO_GC.as_ptr(),
        PlanSelector::MarkSweep => MARK_SWEEP.as_ptr(),
        PlanSelector::Immix => IMMIX.as_ptr(),
        _ => panic!("Unknown plan"),
    }
}

#[no_mangle]
pub extern "C" fn mmtk_heap_mode() -> *const u8 {
    static FIXED_HEAP: &[u8] = b"fixed\0";
    static DYNAMIC_HEAP: &[u8] = b"dynamic\0";

    match *crate::BINDING.get().unwrap().mmtk.get_options().gc_trigger {
        GCTriggerSelector::FixedHeapSize(_) => FIXED_HEAP.as_ptr(),
        GCTriggerSelector::DynamicHeapSize(_, _) => DYNAMIC_HEAP.as_ptr(),
        _ => panic!("Unknown heap mode"),
    }
}

#[no_mangle]
pub extern "C" fn mmtk_heap_min() -> usize {
    match *crate::BINDING.get().unwrap().mmtk.get_options().gc_trigger {
        GCTriggerSelector::FixedHeapSize(_) => 0,
        GCTriggerSelector::DynamicHeapSize(min_size, _) => min_size,
        _ => panic!("Unknown heap mode"),
    }
}

#[no_mangle]
pub extern "C" fn mmtk_heap_max() -> usize {
    match *crate::BINDING.get().unwrap().mmtk.get_options().gc_trigger {
        GCTriggerSelector::FixedHeapSize(max_size) => max_size,
        GCTriggerSelector::DynamicHeapSize(_, max_size) => max_size,
        _ => panic!("Unknown heap mode"),
    }
}

// =============== Miscellaneous ===============

#[no_mangle]
pub extern "C" fn mmtk_is_mmtk_object(addr: Address) -> bool {
    debug_assert!(!addr.is_zero());
    debug_assert!(addr.is_aligned_to(mmtk::util::is_mmtk_object::VO_BIT_REGION_SIZE));
    memory_manager::is_mmtk_object(addr).is_some()
}
