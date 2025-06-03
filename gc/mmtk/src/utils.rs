use std::sync::atomic::{AtomicUsize, Ordering};

use atomic_refcell::AtomicRefCell;
use mmtk::scheduler::{GCWork, GCWorker, WorkBucketStage};

use crate::Ruby;
use sysinfo::System;

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

pub fn default_heap_max() -> usize {
    let mut s = System::new();
    s.refresh_memory();
    s.total_memory()
        .checked_mul(80)
        .and_then(|v| v.checked_div(100))
        .expect("Invalid Memory size") as usize
}

pub fn parse_capacity(input: &str) -> Option<usize> {
    let trimmed = input.trim();

    const KIBIBYTE: usize = 1024;
    const MEBIBYTE: usize = 1024 * KIBIBYTE;
    const GIBIBYTE: usize = 1024 * MEBIBYTE;

    let (number, suffix) = if let Some(pos) = trimmed.find(|c: char| !c.is_numeric()) {
        trimmed.split_at(pos)
    } else {
        (trimmed, "")
    };

    let Ok(v) = number.parse::<usize>() else {
        return None;
    };

    match suffix {
        "GiB" => Some(v * GIBIBYTE),
        "MiB" => Some(v * MEBIBYTE),
        "KiB" => Some(v * KIBIBYTE),
        "" => Some(v),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_capacity_parses_bare_bytes() {
        assert_eq!(Some(1234), parse_capacity("1234"));
    }

    #[test]
    fn test_parse_capacity_parses_kibibytes() {
        assert_eq!(Some(10240), parse_capacity("10KiB"));
    }

    #[test]
    fn test_parse_capacity_parses_mebibytes() {
        assert_eq!(Some(10485760), parse_capacity("10MiB"))
    }

    #[test]
    fn test_parse_capacity_parses_gibibytes() {
        assert_eq!(Some(10737418240), parse_capacity("10GiB"))
    }

    #[test]
    fn test_parse_capacity_parses_nonsense_values() {
        assert_eq!(None, parse_capacity("notanumber"));
        assert_eq!(None, parse_capacity("5tartswithanumber"));
        assert_eq!(None, parse_capacity("number1nthemiddle"));
        assert_eq!(None, parse_capacity("numberattheend111"));
        assert_eq!(None, parse_capacity("mult1pl3numb3r5"));
    }
}
