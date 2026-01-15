use std::sync::Mutex;

use mmtk::memory_manager;
use mmtk::scheduler::GCWork;
use mmtk::scheduler::GCWorker;
use mmtk::scheduler::WorkBucketStage;
use mmtk::util::ObjectReference;
use mmtk::util::VMWorkerThread;
use mmtk::MMTK;

use crate::abi::GCThreadTLS;
use crate::upcalls;
use crate::Ruby;

pub struct PinningRegistry {
    pinning_objs: Mutex<Vec<ObjectReference>>,
    pinned_objs: Mutex<Vec<ObjectReference>>,
}

impl PinningRegistry {
    pub fn new() -> Self {
        Self {
            pinning_objs: Default::default(),
            pinned_objs: Default::default(),
        }
    }

    pub fn register(&self, object: ObjectReference) {
        let mut pinning_objs = self.pinning_objs.lock().unwrap();
        pinning_objs.push(object);
    }

    pub fn pin_children(&self, tls: VMWorkerThread) {
        if !crate::mmtk().get_plan().current_gc_may_move_object() {
            log::debug!("The current GC is non-moving, skipping pinning children.");
            return;
        }

        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(tls) };
        let worker = gc_tls.worker();

        let pinning_objs = self
            .pinning_objs
            .try_lock()
            .expect("PinningRegistry should not have races during GC.");

        let packet_size = 512;
        let work_packets = pinning_objs
            .chunks(packet_size)
            .map(|chunk| {
                Box::new(PinPinningChildren {
                    pinning_objs: chunk.to_vec(),
                }) as _
            })
            .collect();

        worker.scheduler().work_buckets[WorkBucketStage::Prepare].bulk_add(work_packets);
    }

    pub fn cleanup(&self, worker: &mut GCWorker<Ruby>) {
        worker.scheduler().work_buckets[WorkBucketStage::VMRefClosure].add(RemoveDeadPinnings);
        if crate::mmtk().get_plan().current_gc_may_move_object() {
            let packet = {
                let mut pinned_objs = self
                    .pinned_objs
                    .try_lock()
                    .expect("Unexpected contention on pinned_objs");
                UnpinPinnedObjects {
                    objs: std::mem::take(&mut pinned_objs),
                }
            };

            worker.scheduler().work_buckets[WorkBucketStage::VMRefClosure].add(packet);
        } else {
            debug!("The current GC is non-moving, skipping unpinning objects.");
            debug_assert_eq!(
                {
                    let pinned_objs = self
                        .pinned_objs
                        .try_lock()
                        .expect("Unexpected contention on pinned_objs");
                    pinned_objs.len()
                },
                0
            );
        }
    }
}

impl Default for PinningRegistry {
    fn default() -> Self {
        Self::new()
    }
}

struct PinPinningChildren {
    pinning_objs: Vec<ObjectReference>,
}

impl GCWork<Ruby> for PinPinningChildren {
    fn do_work(&mut self, worker: &mut GCWorker<Ruby>, _mmtk: &'static MMTK<Ruby>) {
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(worker.tls) };
        let mut pinned_objs = vec![];
        let mut newly_pinned_objs = vec![];

        let visit_object = |_worker, target_object: ObjectReference, pin| {
            log::trace!(
                "    -> {} {}",
                if pin { "(pin)" } else { "     " },
                target_object
            );
            if pin {
                debug_assert!(
                    target_object.get_forwarded_object().is_none(),
                    "Trying to pin {target_object} but has been moved"
                );

                pinned_objs.push(target_object);
            }
            target_object
        };

        gc_tls
            .object_closure
            .set_temporarily_and_run_code(visit_object, || {
                for obj in self.pinning_objs.iter().cloned() {
                    log::trace!("  Pinning: {}", obj);
                    (upcalls().call_gc_mark_children)(obj);
                }
            });

        for target_object in pinned_objs {
            if memory_manager::pin_object(target_object) {
                newly_pinned_objs.push(target_object);
            }
        }

        let mut pinned_objs = crate::binding()
            .pinning_registry
            .pinned_objs
            .lock()
            .unwrap();
        pinned_objs.append(&mut newly_pinned_objs);
    }
}

struct RemoveDeadPinnings;

impl GCWork<Ruby> for RemoveDeadPinnings {
    fn do_work(&mut self, _worker: &mut GCWorker<Ruby>, _mmtk: &'static MMTK<Ruby>) {
        log::debug!("Removing dead Pinnings...");

        let registry = &crate::binding().pinning_registry;
        {
            let mut pinning_objs = registry
                .pinning_objs
                .try_lock()
                .expect("PinningRegistry should not have races during GC.");

            pinning_objs.retain_mut(|obj| {
                if obj.is_live() {
                    let new_obj = obj.get_forwarded_object().unwrap_or(*obj);
                    *obj = new_obj;
                    true
                } else {
                    log::trace!("  Dead Pinning removed: {}", *obj);
                    false
                }
            });
        }
    }
}

struct UnpinPinnedObjects {
    objs: Vec<ObjectReference>,
}

impl GCWork<Ruby> for UnpinPinnedObjects {
    fn do_work(&mut self, _worker: &mut GCWorker<Ruby>, _mmtk: &'static MMTK<Ruby>) {
        log::debug!("Unpinning pinned objects...");

        for obj in self.objs.iter() {
            let unpinned = memory_manager::unpin_object(*obj);
            debug_assert!(unpinned);
        }
    }
}
