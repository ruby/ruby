use crate::abi::GCThreadTLS;

use crate::api::RubyMutator;
use crate::{mmtk, upcalls, Ruby};
use mmtk::memory_manager;
use mmtk::scheduler::*;
use mmtk::util::{VMMutatorThread, VMThread, VMWorkerThread};
use mmtk::vm::{Collection, GCThreadContext};
use std::sync::atomic::Ordering;
use std::thread;

pub struct VMCollection {}

impl Collection<Ruby> for VMCollection {
    fn is_collection_enabled() -> bool {
        crate::CONFIGURATION.gc_enabled.load(Ordering::Relaxed)
    }

    fn stop_all_mutators<F>(_tls: VMWorkerThread, mut mutator_visitor: F)
    where
        F: FnMut(&'static mut mmtk::Mutator<Ruby>),
    {
        (upcalls().stop_the_world)();
        (upcalls().get_mutators)(
            Self::notify_mutator_ready::<F>,
            &mut mutator_visitor as *mut F as *mut _,
        );
    }

    fn resume_mutators(_tls: VMWorkerThread) {
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
