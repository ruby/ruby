use std::sync::Mutex;

use mmtk::{
    memory_manager,
    scheduler::{GCWork, WorkBucketStage},
    util::{ObjectReference, VMWorkerThread},
};

use crate::{abi::GCThreadTLS, upcalls, Ruby};

pub struct PPPRegistry {
    ppps: Mutex<Vec<ObjectReference>>,
    pinned_ppp_children: Mutex<Vec<ObjectReference>>,
}

impl PPPRegistry {
    pub fn new() -> Self {
        Self {
            ppps: Default::default(),
            pinned_ppp_children: Default::default(),
        }
    }

    pub fn register(&self, object: ObjectReference) {
        let mut ppps = self.ppps.lock().unwrap();
        ppps.push(object);
    }

    pub fn register_many(&self, objects: &[ObjectReference]) {
        let mut ppps = self.ppps.lock().unwrap();
        for object in objects.iter().copied() {
            ppps.push(object);
        }
    }

    pub fn pin_ppp_children(&self, tls: VMWorkerThread) {
        log::debug!("Pin children of PPPs...");

        if !crate::mmtk().get_plan().current_gc_may_move_object() {
            log::debug!("The current GC is non-moving.  Skipped pinning PPP children.");
            return;
        }

        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(tls) };
        let worker = gc_tls.worker();

        {
            let ppps = self
                .ppps
                .try_lock()
                .expect("PPPRegistry should not have races during GC.");

            // I tried several packet sizes and 512 works pretty well.  It should be adjustable.
            let packet_size = 512;
            let work_packets = ppps
                .chunks(packet_size)
                .map(|chunk| {
                    Box::new(PinPPPChildren {
                        ppps: chunk.to_vec(),
                    }) as _
                })
                .collect();

            worker.scheduler().work_buckets[WorkBucketStage::Prepare].bulk_add(work_packets);
        }
    }

    pub fn cleanup_ppps(&self) {
        log::debug!("Removing dead PPPs...");
        {
            let mut ppps = self
                .ppps
                .try_lock()
                .expect("PPPRegistry::ppps should not have races during GC.");

            probe!(mmtk_ruby, remove_dead_ppps_start, ppps.len());
            ppps.retain_mut(|obj| {
                if obj.is_live::<Ruby>() {
                    *obj = obj.get_forwarded_object::<Ruby>().unwrap_or(*obj);
                    true
                } else {
                    log::trace!("  PPP removed: {}", *obj);
                    false
                }
            });
            probe!(mmtk_ruby, remove_dead_ppps_end);
        }

        log::debug!("Unpinning pinned PPP children...");

        if !crate::mmtk().get_plan().current_gc_may_move_object() {
            log::debug!("The current GC is non-moving.  Skipped unpinning PPP children.");
        } else {
            let mut pinned_ppps = self
                .pinned_ppp_children
                .try_lock()
                .expect("PPPRegistry::pinned_ppp_children should not have races during GC.");
            probe!(mmtk_ruby, unpin_ppp_children_start, pinned_ppps.len());
            for obj in pinned_ppps.drain(..) {
                let unpinned = memory_manager::unpin_object::<Ruby>(obj);
                debug_assert!(unpinned);
            }
            probe!(mmtk_ruby, unpin_ppp_children_end);
        }
    }
}

impl Default for PPPRegistry {
    fn default() -> Self {
        Self::new()
    }
}

struct PinPPPChildren {
    ppps: Vec<ObjectReference>,
}

impl GCWork<Ruby> for PinPPPChildren {
    fn do_work(
        &mut self,
        worker: &mut mmtk::scheduler::GCWorker<Ruby>,
        _mmtk: &'static mmtk::MMTK<Ruby>,
    ) {
        let gc_tls = unsafe { GCThreadTLS::from_vwt_check(worker.tls) };
        let mut ppp_children = vec![];
        let mut newly_pinned_ppp_children = vec![];

        let visit_object = |_worker, target_object: ObjectReference, pin| {
            log::trace!(
                "    -> {} {}",
                if pin { "(pin)" } else { "     " },
                target_object
            );
            if pin {
                ppp_children.push(target_object);
            }
            target_object
        };

        gc_tls
            .object_closure
            .set_temporarily_and_run_code(visit_object, || {
                for obj in self.ppps.iter().cloned() {
                    log::trace!("  PPP: {}", obj);
                    (upcalls().call_gc_mark_children)(obj);
                }
            });

        for target_object in ppp_children {
            if memory_manager::pin_object::<Ruby>(target_object) {
                newly_pinned_ppp_children.push(target_object);
            }
        }

        {
            let mut pinned_ppp_children = crate::binding()
                .ppp_registry
                .pinned_ppp_children
                .lock()
                .unwrap();
            pinned_ppp_children.append(&mut newly_pinned_ppp_children);
        }
    }
}
