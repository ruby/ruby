use crate::abi::GCThreadTLS;

use crate::api::RubyMutator;
use crate::heap::RubyHeapTrigger;
use crate::mmtk;
use crate::upcalls;
use crate::Ruby;
use mmtk::memory_manager;
use mmtk::scheduler::*;
use mmtk::util::heap::GCTriggerPolicy;
use mmtk::util::VMMutatorThread;
use mmtk::util::VMThread;
use mmtk::util::VMWorkerThread;
use mmtk::vm::Collection;
use mmtk::vm::GCThreadContext;
use std::sync::atomic::AtomicBool;
use std::sync::atomic::Ordering;
use std::thread;

static CURRENT_GC_MAY_MOVE: AtomicBool = AtomicBool::new(false);

pub struct VMCollection {}

impl Collection<Ruby> for VMCollection {
    fn is_collection_enabled() -> bool {
        crate::CONFIGURATION.gc_enabled.load(Ordering::Relaxed)
    }

    fn stop_all_mutators<F>(tls: VMWorkerThread, mut mutator_visitor: F)
    where
        F: FnMut(&'static mut mmtk::Mutator<Ruby>),
    {
        (upcalls().stop_the_world)();

        if crate::mmtk().get_plan().current_gc_may_move_object() {
            CURRENT_GC_MAY_MOVE.store(true, Ordering::Relaxed);
            (upcalls().before_updating_jit_code)();
        } else {
            CURRENT_GC_MAY_MOVE.store(false, Ordering::Relaxed);
        }

        crate::binding().pinning_registry.pin_children(tls);

        (upcalls().get_mutators)(
            Self::notify_mutator_ready::<F>,
            &mut mutator_visitor as *mut F as *mut _,
        );
    }

    fn resume_mutators(_tls: VMWorkerThread) {
        if CURRENT_GC_MAY_MOVE.load(Ordering::Relaxed) {
            (upcalls().after_updating_jit_code)();
        }

        (upcalls().resume_mutators)();
    }

    fn block_for_gc(tls: VMMutatorThread) {
        (upcalls().block_for_gc)(tls);
    }

    fn spawn_gc_thread(_tls: VMThread, ctx: GCThreadContext<Ruby>) {
        let join_handle = match ctx {
            GCThreadContext::Worker(mut worker) => thread::Builder::new()
                .name("MMTk Worker Thread".to_string())
                .spawn(move || {
                    let ordinal = worker.ordinal;
                    debug!("Hello! This is MMTk Worker Thread running! ordinal: {ordinal}");
                    crate::register_gc_thread(thread::current().id());
                    let ptr_worker = &mut *worker as *mut GCWorker<Ruby>;
                    let gc_thread_tls =
                        Box::into_raw(Box::new(GCThreadTLS::for_worker(ptr_worker)));
                    (upcalls().init_gc_worker_thread)(gc_thread_tls);
                    memory_manager::start_worker(
                        mmtk(),
                        GCThreadTLS::to_vwt(gc_thread_tls),
                        worker,
                    );
                    debug!("An MMTk Worker Thread is quitting. Good bye! ordinal: {ordinal}");
                    crate::unregister_gc_thread(thread::current().id());
                })
                .unwrap(),
        };

        {
            let mut handles = crate::binding().gc_thread_join_handles.lock().unwrap();
            handles.push(join_handle);
        }
    }

    fn vm_live_bytes() -> usize {
        (upcalls().vm_live_bytes)()
    }

    fn create_gc_trigger() -> Box<dyn GCTriggerPolicy<Ruby>> {
        Box::new(RubyHeapTrigger::default())
    }
}

impl VMCollection {
    extern "C" fn notify_mutator_ready<F>(mutator_ptr: *mut RubyMutator, data: *mut libc::c_void)
    where
        F: FnMut(&'static mut mmtk::Mutator<Ruby>),
    {
        let mutator = unsafe { &mut *mutator_ptr };
        let mutator_visitor = unsafe { &mut *(data as *mut F) };
        mutator_visitor(mutator);
    }
}
