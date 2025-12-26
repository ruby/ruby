use std::sync::Mutex;

use mmtk::{
    scheduler::{GCWork, GCWorker, WorkBucketStage},
    util::ObjectReference,
    vm::ObjectTracerContext,
};

use crate::{abi::GCThreadTLS, upcalls, Ruby};

pub struct WeakProcessor {
    /// Objects that needs `obj_free` called when dying.
    /// If it is a bottleneck, replace it with a lock-free data structure,
    /// or add candidates in batch.
    obj_free_candidates: Mutex<Vec<ObjectReference>>,
    weak_references: Mutex<Vec<ObjectReference>>,
}

impl Default for WeakProcessor {
    fn default() -> Self {
        Self::new()
    }
}

impl WeakProcessor {
    pub fn new() -> Self {
        Self {
            obj_free_candidates: Mutex::new(Vec::new()),
            weak_references: Mutex::new(Vec::new()),
        }
    }

    /// Add an object as a candidate for `obj_free`.
    ///
    /// Multiple mutators can call it concurrently, so it has `&self`.
    pub fn add_obj_free_candidate(&self, object: ObjectReference) {
        let mut obj_free_candidates = self.obj_free_candidates.lock().unwrap();
        obj_free_candidates.push(object);
    }

    /// Add many objects as candidates for `obj_free`.
    ///
    /// Multiple mutators can call it concurrently, so it has `&self`.
    pub fn add_obj_free_candidates(&self, objects: &[ObjectReference]) {
        let mut obj_free_candidates = self.obj_free_candidates.lock().unwrap();
        for object in objects.iter().copied() {
            obj_free_candidates.push(object);
        }
    }

    pub fn get_all_obj_free_candidates(&self) -> Vec<ObjectReference> {
        let mut obj_free_candidates = self.obj_free_candidates.lock().unwrap();
        std::mem::take(obj_free_candidates.as_mut())
    }

    pub fn add_weak_reference(&self, object: ObjectReference) {
        let mut weak_references = self.weak_references.lock().unwrap();
        weak_references.push(object);
    }

    pub fn process_weak_stuff(
        &self,
        worker: &mut GCWorker<Ruby>,
        _tracer_context: impl ObjectTracerContext<Ruby>,
    ) {
        worker.add_work(WorkBucketStage::VMRefClosure, ProcessObjFreeCandidates);
        worker.add_work(WorkBucketStage::VMRefClosure, ProcessWeakReferences);

        worker.add_work(WorkBucketStage::Prepare, UpdateFinalizerObjIdTables);

        let global_tables_count = (crate::upcalls().global_tables_count)();
        let work_packets = (0..global_tables_count)
            .map(|i| Box::new(UpdateGlobalTables { idx: i }) as _)
            .collect();

        worker.scheduler().work_buckets[WorkBucketStage::VMRefClosure].bulk_add(work_packets);

        worker.scheduler().work_buckets[WorkBucketStage::VMRefClosure]
            .bulk_add(vec![Box::new(UpdateWbUnprotectedObjectsList) as _]);
    }
}

struct ProcessObjFreeCandidates;

impl GCWork<Ruby> for ProcessObjFreeCandidates {
    fn do_work(&mut self, _worker: &mut GCWorker<Ruby>, _mmtk: &'static mmtk::MMTK<Ruby>) {
        // If it blocks, it is a bug.
        let mut obj_free_candidates = crate::binding()
            .weak_proc
            .obj_free_candidates
            .try_lock()
            .expect("It's GC time.  No mutators should hold this lock at this time.");

        let n_cands = obj_free_candidates.len();

        debug!("Total: {n_cands} candidates");

        // Process obj_free
        let mut new_candidates = Vec::new();

        for object in obj_free_candidates.iter().copied() {
            if object.is_reachable() {
                // Forward and add back to the candidate list.
                let new_object = object.forward();
                trace!("Forwarding obj_free candidate: {object} -> {new_object}");
                new_candidates.push(new_object);
            } else {
                (upcalls().call_obj_free)(object);
            }
        }

        *obj_free_candidates = new_candidates;
    }
}

struct ProcessWeakReferences;

impl GCWork<Ruby> for ProcessWeakReferences {
    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, _mmtk: &'static mmtk::MMTK<Ruby>) {
        if crate::mmtk().get_plan().current_gc_may_move_object() {
            let gc_tls: &mut GCThreadTLS = unsafe { GCThreadTLS::from_vwt_check(worker.tls) };

            let visit_object = |_worker, target_object: ObjectReference, _pin| {
                debug_assert!(
                    mmtk::memory_manager::is_mmtk_object(target_object.to_raw_address()).is_some(),
                    "Destination is not an MMTk object"
                );

                target_object
                    .get_forwarded_object()
                    .unwrap_or(target_object)
            };

            gc_tls
                .object_closure
                .set_temporarily_and_run_code(visit_object, || {
                    self.process_weak_references(true);
                })
        } else {
            self.process_weak_references(false);
        }
    }
}

impl ProcessWeakReferences {
    fn process_weak_references(&mut self, moving_gc: bool) {
        let mut weak_references = crate::binding()
            .weak_proc
            .weak_references
            .try_lock()
            .expect("Mutators should not be holding the lock.");

        weak_references.retain_mut(|object_ptr| {
            let object = object_ptr.get_forwarded_object().unwrap_or(*object_ptr);

            if object != *object_ptr {
                *object_ptr = object;
            }

            if object.is_reachable() {
                (upcalls().handle_weak_references)(object, moving_gc);

                true
            } else {
                false
            }
        });
    }
}

trait GlobalTableProcessingWork {
    fn process_table(&mut self);

    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, _mmtk: &'static mmtk::MMTK<Ruby>) {
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(worker.tls) };

        // `hash_foreach_replace` depends on `gb_object_moved_p` which has to have the semantics
        // of `trace_object` due to the way it is used in `UPDATE_IF_MOVED`.
        let forward_object = |_worker, object: ObjectReference, _pin| {
            debug_assert!(
                mmtk::memory_manager::is_mmtk_object(object.to_raw_address()).is_some(),
                "{object} is not an MMTk object"
            );
            let result = object.forward();
            trace!("Forwarding reference: {object} -> {result}");
            result
        };

        gc_tls
            .object_closure
            .set_temporarily_and_run_code(forward_object, || {
                self.process_table();
            });
    }
}

struct UpdateFinalizerObjIdTables;
impl GlobalTableProcessingWork for UpdateFinalizerObjIdTables {
    fn process_table(&mut self) {
        (crate::upcalls().update_finalizer_table)();
    }
}
impl GCWork<Ruby> for UpdateFinalizerObjIdTables {
    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, mmtk: &'static mmtk::MMTK<Ruby>) {
        GlobalTableProcessingWork::do_work(self, worker, mmtk);
    }
}

struct UpdateGlobalTables {
    idx: i32,
}
impl GlobalTableProcessingWork for UpdateGlobalTables {
    fn process_table(&mut self) {
        (crate::upcalls().update_global_tables)(self.idx)
    }
}
impl GCWork<Ruby> for UpdateGlobalTables {
    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, mmtk: &'static mmtk::MMTK<Ruby>) {
        GlobalTableProcessingWork::do_work(self, worker, mmtk);
    }
}

struct UpdateWbUnprotectedObjectsList;

impl GCWork<Ruby> for UpdateWbUnprotectedObjectsList {
    fn do_work(&mut self, _worker: &mut GCWorker<Ruby>, _mmtk: &'static mmtk::MMTK<Ruby>) {
        let mut objects = crate::binding().wb_unprotected_objects.try_lock().expect(
            "Someone is holding the lock of wb_unprotected_objects during weak processing phase?",
        );

        let old_objects = std::mem::take(&mut *objects);

        debug!("Updating {} WB-unprotected objects", old_objects.len());

        for object in old_objects {
            if object.is_reachable() {
                // Forward and add back to the candidate list.
                let new_object = object.forward();
                trace!("Forwarding WB-unprotected object: {object} -> {new_object}");
                objects.insert(new_object);
            } else {
                trace!("Removing WB-unprotected object from list: {object}");
            }
        }

        debug!("Retained {} live WB-unprotected objects.", objects.len());
    }
}

// Provide a shorthand `object.forward()`.
trait Forwardable {
    fn forward(&self) -> Self;
}

impl Forwardable for ObjectReference {
    fn forward(&self) -> Self {
        self.get_forwarded_object().unwrap_or(*self)
    }
}
