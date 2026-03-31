use crate::abi::GCThreadTLS;

use crate::upcalls;
use crate::utils::ChunkedVecCollector;
use crate::Ruby;
use crate::RubySlot;
use mmtk::memory_manager;
use mmtk::scheduler::GCWork;
use mmtk::scheduler::GCWorker;
use mmtk::scheduler::WorkBucketStage;
use mmtk::util::ObjectReference;
use mmtk::util::VMWorkerThread;
use mmtk::vm::ObjectTracer;
use mmtk::vm::RootsWorkFactory;
use mmtk::vm::Scanning;
use mmtk::vm::SlotVisitor;
use mmtk::Mutator;

pub struct VMScanning {}

impl Scanning<Ruby> for VMScanning {
    const UNIQUE_OBJECT_ENQUEUING: bool = true;

    fn support_slot_enqueuing(_tls: VMWorkerThread, _object: ObjectReference) -> bool {
        false
    }

    fn scan_object<EV: SlotVisitor<RubySlot>>(
        _tls: VMWorkerThread,
        _object: ObjectReference,
        _slot_visitor: &mut EV,
    ) {
        unreachable!("We have not enabled slot enqueuing for any types, yet.");
    }

    fn scan_object_and_trace_edges<OT: ObjectTracer>(
        tls: VMWorkerThread,
        object: ObjectReference,
        object_tracer: &mut OT,
    ) {
        debug_assert!(
            mmtk::memory_manager::is_mmtk_object(object.to_raw_address()).is_some(),
            "Not an MMTk object: {object}",
        );
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(tls) };
        let visit_object = |_worker, target_object: ObjectReference, pin| {
            trace!(
                "Tracing edge: {} -> {}{}",
                object,
                target_object,
                if pin { " pin" } else { "" }
            );
            debug_assert!(
                mmtk::memory_manager::is_mmtk_object(target_object.to_raw_address()).is_some(),
                "Destination is not an MMTk object. Src: {object} dst: {target_object}"
            );

            debug_assert!(
                // If we are in a moving GC, all objects should be pinned by PinningRegistry.
                // If it is requested that target_object be pinned but it is not pinned, then
                // it is a bug because it could be moved.
                if crate::mmtk().get_plan().current_gc_may_move_object() && pin {
                    memory_manager::is_pinned(target_object)
                } else {
                    true
                },
                "Object {object} is trying to pin {target_object}"
            );

            let forwarded_target = object_tracer.trace_object(target_object);
            if forwarded_target != target_object {
                trace!("  Forwarded target {target_object} -> {forwarded_target}");
            }
            forwarded_target
        };
        gc_tls
            .object_closure
            .set_temporarily_and_run_code(visit_object, || {
                (upcalls().call_gc_mark_children)(object);

                if crate::mmtk().get_plan().current_gc_may_move_object() {
                    (upcalls().update_object_references)(object);
                }
            });
    }

    fn notify_initial_thread_scan_complete(_partial_scan: bool, _tls: VMWorkerThread) {
        // Do nothing
    }

    fn scan_roots_in_mutator_thread(
        _tls: VMWorkerThread,
        _mutator: &'static mut Mutator<Ruby>,
        mut _factory: impl RootsWorkFactory<RubySlot>,
    ) {
        // Do nothing.  All stacks (including Ruby stacks and machine stacks) are reachable from
        // `rb_vm_t` -> ractor -> thread -> fiber -> stacks.  It is part of `ScanGCRoots` which
        // calls `rb_gc_mark_roots` -> `rb_vm_mark`.
    }

    fn scan_vm_specific_roots(tls: VMWorkerThread, factory: impl RootsWorkFactory<RubySlot>) {
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(tls) };
        let root_scanning_work_packets: Vec<Box<dyn GCWork<Ruby>>> = vec![
            Box::new(ScanGCRoots::new(factory.clone())),
            Box::new(ScanObjspace::new(factory.clone())),
        ];
        gc_tls.worker().scheduler().work_buckets[WorkBucketStage::Prepare]
            .bulk_add(root_scanning_work_packets);

        // Generate WB-unprotected roots scanning work packets

        'gen_wb_unprotected_work: {
            let is_nursery_gc = (crate::mmtk().get_plan().generational())
                .is_some_and(|gen| gen.is_current_gc_nursery());
            if !is_nursery_gc {
                break 'gen_wb_unprotected_work;
            }

            let vecs = {
                let guard = crate::binding()
                    .wb_unprotected_objects
                    .try_lock()
                    .expect("Someone is holding the lock of wb_unprotected_objects?");
                if guard.is_empty() {
                    break 'gen_wb_unprotected_work;
                }

                let mut collector = ChunkedVecCollector::new(128);
                collector.extend(guard.iter().copied());
                collector.into_vecs()
            };

            let packets = vecs
                .into_iter()
                .map(|objects| {
                    let factory = factory.clone();
                    Box::new(ScanWbUnprotectedRoots { factory, objects }) as _
                })
                .collect::<Vec<_>>();

            gc_tls.worker().scheduler().work_buckets[WorkBucketStage::Prepare].bulk_add(packets);
        }
    }

    fn supports_return_barrier() -> bool {
        false
    }

    fn prepare_for_roots_re_scanning() {
        todo!()
    }

    fn process_weak_refs(
        worker: &mut GCWorker<Ruby>,
        tracer_context: impl mmtk::vm::ObjectTracerContext<Ruby>,
    ) -> bool {
        crate::binding()
            .weak_proc
            .process_weak_stuff(worker, tracer_context);
        crate::binding().pinning_registry.cleanup(worker);
        false
    }

    fn forward_weak_refs(
        _worker: &mut GCWorker<Ruby>,
        _tracer_context: impl mmtk::vm::ObjectTracerContext<Ruby>,
    ) {
        panic!("We can't use MarkCompact in Ruby.");
    }
}

impl VMScanning {
    const OBJECT_BUFFER_SIZE: usize = 4096;

    fn collect_object_roots_in<F: FnOnce()>(
        root_scan_kind: &str,
        gc_tls: &mut GCThreadTLS,
        factory: &mut impl RootsWorkFactory<RubySlot>,
        callback: F,
    ) {
        let mut buffer: Vec<ObjectReference> = Vec::new();
        let visit_object = |_, object: ObjectReference, pin| {
            debug!(
                "[{}] Visiting object: {}{}",
                root_scan_kind,
                object,
                if pin {
                    "(unmovable root)"
                } else {
                    "(movable, but we pin it anyway)"
                }
            );
            debug_assert!(
                mmtk::memory_manager::is_mmtk_object(object.to_raw_address()).is_some(),
                "Root does not point to MMTk object.  object: {object}"
            );
            buffer.push(object);
            if buffer.len() >= Self::OBJECT_BUFFER_SIZE {
                factory.create_process_pinning_roots_work(std::mem::take(&mut buffer));
            }
            object
        };
        gc_tls
            .object_closure
            .set_temporarily_and_run_code(visit_object, callback);

        if !buffer.is_empty() {
            factory.create_process_pinning_roots_work(buffer);
        }
    }
}

trait GlobaRootScanningWork {
    type F: RootsWorkFactory<RubySlot>;
    const NAME: &'static str;

    fn new(factory: Self::F) -> Self;
    fn scan_roots();
    fn roots_work_factory(&mut self) -> &mut Self::F;

    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, _mmtk: &'static mmtk::MMTK<Ruby>) {
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(worker.tls) };

        let factory = self.roots_work_factory();

        VMScanning::collect_object_roots_in(Self::NAME, gc_tls, factory, || {
            Self::scan_roots();
        });
    }
}

macro_rules! define_global_root_scanner {
    ($name: ident, $code: expr) => {
        struct $name<F: RootsWorkFactory<RubySlot>> {
            factory: F,
        }
        impl<F: RootsWorkFactory<RubySlot>> GlobaRootScanningWork for $name<F> {
            type F = F;
            const NAME: &'static str = stringify!($name);
            fn new(factory: Self::F) -> Self {
                Self { factory }
            }
            fn scan_roots() {
                $code
            }
            fn roots_work_factory(&mut self) -> &mut Self::F {
                &mut self.factory
            }
        }
        impl<F: RootsWorkFactory<RubySlot>> GCWork<Ruby> for $name<F> {
            fn do_work(&mut self, worker: &mut GCWorker<Ruby>, mmtk: &'static mmtk::MMTK<Ruby>) {
                GlobaRootScanningWork::do_work(self, worker, mmtk);
            }
        }
    };
}

define_global_root_scanner!(ScanGCRoots, {
    (crate::upcalls().scan_gc_roots)();
});

define_global_root_scanner!(ScanObjspace, {
    (crate::upcalls().scan_objspace)();
});

struct ScanWbUnprotectedRoots<F: RootsWorkFactory<RubySlot>> {
    factory: F,
    objects: Vec<ObjectReference>,
}

impl<F: RootsWorkFactory<RubySlot>> GCWork<Ruby> for ScanWbUnprotectedRoots<F> {
    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, _mmtk: &'static mmtk::MMTK<Ruby>) {
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(worker.tls) };
        VMScanning::collect_object_roots_in("wb_unprot_roots", gc_tls, &mut self.factory, || {
            for object in self.objects.iter().copied() {
                if object.is_reachable() {
                    debug!("[wb_unprot_roots] Visiting WB-unprotected object (parent): {object}");
                    (upcalls().call_gc_mark_children)(object);

                    if crate::mmtk().get_plan().current_gc_may_move_object() {
                        (upcalls().update_object_references)(object);
                    }
                } else {
                    debug!(
                        "[wb_unprot_roots] Skipping young WB-unprotected object (parent): {object}"
                    );
                }
            }
        });
    }
}
