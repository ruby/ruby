use crate::core::BlockId;
use crate::cruby::*;
use crate::options::*;
use crate::yjit::yjit_enabled_p;

use std::os::raw::c_long;

#[derive(Copy, Clone)]
pub struct CompilationLogEntry {
    /// The compiled block.
    pub block_id: BlockId,

    /// The time when the block was compiled.
    pub timestamp: f64,
}

pub type CompilationLog = CircularBuffer<CompilationLogEntry, 1024>;
static mut COMPILATION_LOG : Option<CompilationLog> = None;

impl CompilationLog {
    pub fn init() {
        unsafe {
            COMPILATION_LOG = Some(CompilationLog::new());
        }
    }

    pub fn get_instance() -> &'static mut CompilationLog {
        unsafe {
            COMPILATION_LOG.as_mut().unwrap()
        }
    }

    pub fn has_instance() -> bool {
        unsafe {
            COMPILATION_LOG.as_mut().is_some()
        }
    }

    pub fn add_entry(block_id: BlockId) {
        if !Self::has_instance() {
            return;
        }

        Self::get_instance().push(CompilationLogEntry {
            block_id: block_id,
            timestamp: std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()
        });
    }

    pub fn clear() {
        unsafe {
            COMPILATION_LOG.as_mut().unwrap().reset()
        }
    }
}

pub struct CircularBuffer<T, const N: usize> {
    buffer: [Option<T>; N],
    head: usize,
    tail: usize,
    size: usize
}

impl<T: Copy, const N: usize> CircularBuffer<T, N> {
    pub fn new() -> Self {
        Self {
            buffer: [None; N],
            head: 0,
            tail: 0,
            size: 0
        }
    }

    pub fn push(&mut self, value: T) {
        self.buffer[self.head] = Some(value);
        self.head = (self.head + 1) % N;
        if self.size == N {
            self.tail = (self.tail + 1) % N;
        } else {
            self.size += 1;
        }
    }

    pub fn pop(&mut self) -> Option<T> {
        if self.size == 0 {
            return None;
        }

        let value = self.buffer[self.tail].take();
        self.tail = (self.tail + 1) % N;
        self.size -= 1;
        value
    }

    pub fn len(&self) -> usize {
        self.size
    }

    pub fn iter(&self) -> CircularBufferIterator<T, N> {
        CircularBufferIterator {
            buffer: self,
            current: 0,
            count: 0,
        }
    }

    pub fn reset(&mut self) {
        self.head = 0;
        self.tail = 0;
        self.size = 0;
    }
}

pub struct CircularBufferIterator<'a, T: Copy, const N: usize> {
    buffer: &'a CircularBuffer<T, N>,
    current: usize,
    count: usize,
}

impl<'a, T: Copy, const N: usize> Iterator for CircularBufferIterator<'a, T, N> {
    type Item = T;

    fn next(&mut self) -> Option<Self::Item> {
        if self.count >= self.buffer.size {
            return None;
        }

        let index = (self.buffer.tail + self.current) % N;
        let item = self.buffer.buffer[index];
        self.current = (self.current + 1) % N;
        self.count += 1;

        item
    }
}


//===========================================================================

/// Primitive called in yjit.rb
/// Check if compilation log generation is enabled
#[no_mangle]
pub extern "C" fn rb_yjit_compilation_log_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if get_option!(gen_compilation_log) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/// Primitive called in yjit.rb
/// Check if the compilation log should print at exit
#[no_mangle]
pub extern "C" fn rb_yjit_print_compilation_log_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if yjit_enabled_p() && get_option!(print_compilation_log) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/// Primitive called in yjit.rb.
/// Export all YJIT compilation log entries as a Ruby array.
#[no_mangle]
pub extern "C" fn rb_yjit_get_compilation_log(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    with_vm_lock(src_loc!(), || rb_yjit_get_compilation_log_array())
}

fn rb_yjit_get_compilation_log_array() -> VALUE {
    if !yjit_enabled_p() {
        return Qnil;
    }

    let log = CompilationLog::get_instance();
    let array = unsafe { rb_ary_new_capa(log.len() as c_long) };

    for entry in log.iter() {
        unsafe {
            let entry_array = rb_ary_new_capa(2);
            rb_ary_push(entry_array, entry.block_id.iseq_name());
            rb_ary_push(entry_array, rb_float_new(entry.timestamp));
            rb_ary_push(array, entry_array);
        }
    }

    CompilationLog::clear();

    return array;
}
