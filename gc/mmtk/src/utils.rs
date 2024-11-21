use std::sync::atomic::{AtomicUsize, Ordering};

use atomic_refcell::AtomicRefCell;
use mmtk::scheduler::{GCWork, GCWorker, WorkBucketStage};

use crate::Ruby;

pub struct ChunkedVecCollector<T> {
    vecs: Vec<Vec<T>>,
    current_vec: Vec<T>,
    chunk_size: usize,
}

impl<T> ChunkedVecCollector<T> {
    pub fn new(chunk_size: usize) -> Self {
        Self {
            vecs: vec![],
            current_vec: Vec::with_capacity(chunk_size),
            chunk_size,
        }
    }

    pub fn add(&mut self, item: T) {
        self.current_vec.push(item);
        if self.current_vec.len() == self.chunk_size {
            self.flush();
        }
    }

    fn flush(&mut self) {
        let new_vec = Vec::with_capacity(self.chunk_size);
        let old_vec = std::mem::replace(&mut self.current_vec, new_vec);
        self.vecs.push(old_vec);
    }

    pub fn into_vecs(mut self) -> Vec<Vec<T>> {
        if !self.current_vec.is_empty() {
            self.flush();
        }
        self.vecs
    }
}

impl<A> Extend<A> for ChunkedVecCollector<A> {
    fn extend<T: IntoIterator<Item = A>>(&mut self, iter: T) {
        for item in iter {
            self.add(item);
        }
    }
}

pub struct AfterAll {
    counter: AtomicUsize,
    stage: WorkBucketStage,
    packets: AtomicRefCell<Vec<Box<dyn GCWork<Ruby>>>>,
}

unsafe impl Sync for AfterAll {}

impl AfterAll {
    pub fn new(stage: WorkBucketStage) -> Self {
        Self {
            counter: AtomicUsize::new(0),
            stage,
            packets: AtomicRefCell::new(vec![]),
        }
    }

    pub fn add_packets(&self, mut packets: Vec<Box<dyn GCWork<Ruby>>>) {
        let mut borrow = self.packets.borrow_mut();
        borrow.append(&mut packets);
    }

    pub fn count_up(&self, n: usize) {
        self.counter.fetch_add(n, Ordering::SeqCst);
    }

    pub fn count_down(&self, worker: &mut GCWorker<Ruby>) {
        let old = self.counter.fetch_sub(1, Ordering::SeqCst);
        if old == 1 {
            let packets = {
                let mut borrow = self.packets.borrow_mut();
                std::mem::take(borrow.as_mut())
            };
            worker.scheduler().work_buckets[self.stage].bulk_add(packets);
        }
    }
}
