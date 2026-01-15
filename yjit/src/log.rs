use crate::core::BlockId;
use crate::cruby::*;
use crate::options::*;
use crate::yjit::yjit_enabled_p;

use std::fmt::{Display, Formatter};
use std::os::raw::c_long;
use crate::utils::iseq_get_location;

type Timestamp = f64;

#[derive(Clone, Debug)]
pub struct LogEntry {
    /// The time when the block was compiled.
    pub timestamp: Timestamp,

    /// The log message.
    pub message: String,
}

impl Display for LogEntry {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:15.6}: {}", self.timestamp, self.message)
    }
}

pub type Log = CircularBuffer<LogEntry, 1024>;
static mut LOG: Option<Log> = None;

impl Log {
    pub fn init() {
        unsafe {
            LOG = Some(Log::new());
        }
    }

    pub fn get_instance() -> &'static mut Log {
        unsafe {
            LOG.as_mut().unwrap()
        }
    }

    pub fn has_instance() -> bool {
        unsafe {
            LOG.as_mut().is_some()
        }
    }

    pub fn add_block_with_chain_depth(block_id: BlockId, chain_depth: u8) {
        if !Self::has_instance() {
            return;
        }

        let print_log = get_option!(log);
        let timestamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64();

        let location = iseq_get_location(block_id.iseq, block_id.idx);
        let index = block_id.idx;
        let message = if chain_depth > 0 {
            format!("{} (index: {}, chain_depth: {})", location, index, chain_depth)
        } else {
            format!("{} (index: {})", location, index)
        };

        let entry = LogEntry {
            timestamp,
            message
        };

        if let Some(output) = print_log {
            match output {
                LogOutput::Stderr => {
                    eprintln!("{}", entry);
                }

                LogOutput::File(fd) => {
                    use std::os::unix::io::{FromRawFd, IntoRawFd};
                    use std::io::Write;

                    // Write with the fd opened during boot
                    let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
                    writeln!(file, "{}", entry).unwrap();
                    file.flush().unwrap();
                    let _ = file.into_raw_fd(); // keep the fd open
                }

                LogOutput::MemoryOnly => () // Don't print or write anything
            }
        }

        Self::get_instance().push(entry);
    }
}

pub struct CircularBuffer<T, const N: usize> {
    buffer: Vec<Option<T>>,
    head: usize,
    tail: usize,
    size: usize
}

impl<T: Clone, const N: usize> CircularBuffer<T, N> {
    pub fn new() -> Self {
        Self {
            buffer: vec![None; N],
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
}


//===========================================================================

/// Primitive called in yjit.rb
/// Check if log generation is enabled
#[no_mangle]
pub extern "C" fn rb_yjit_log_enabled_p(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    if get_option!(log).is_some() {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/// Primitive called in yjit.rb.
/// Export all YJIT log entries as a Ruby array.
#[no_mangle]
pub extern "C" fn rb_yjit_get_log(_ec: EcPtr, _ruby_self: VALUE) -> VALUE {
    with_vm_lock(src_loc!(), || rb_yjit_get_log_array())
}

fn rb_yjit_get_log_array() -> VALUE {
    if !yjit_enabled_p() || get_option!(log).is_none() {
        return Qnil;
    }

    let log = Log::get_instance();
    let array = unsafe { rb_ary_new_capa(log.len() as c_long) };

    while log.len() > 0 {
        let entry = log.pop().unwrap();

        unsafe {
            let entry_array = rb_ary_new_capa(2);
            rb_ary_push(entry_array, rb_float_new(entry.timestamp));
            rb_ary_push(entry_array, entry.message.into());
            rb_ary_push(array, entry_array);
        }
    }

    return array;
}
