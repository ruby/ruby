// Warn about unsafe operations in functions that are already marked as unsafe.
// This will become default in Rust 2024 edition.
#![warn(unsafe_op_in_unsafe_fn)]

extern crate libc;
extern crate mmtk;
#[macro_use]
extern crate log;
extern crate probe;

use std::collections::HashSet;
use std::panic::PanicHookInfo;
use std::sync::Mutex;
use std::thread::ThreadId;

use abi::RubyUpcalls;
use binding::{RubyBinding, RubyBindingFast, RubyConfiguration};
use mmtk::vm::slot::{SimpleSlot, UnimplementedMemorySlice};
use mmtk::vm::VMBinding;
use mmtk::MMTK;
use once_cell::sync::OnceCell;

pub mod abi;
pub mod active_plan;
pub mod api;
pub mod binding;
pub mod collection;
pub mod object_model;
pub mod reference_glue;
pub mod scanning;
pub mod utils;
pub mod weak_proc;

#[derive(Default)]
pub struct Ruby;

/// Ruby slot type, i.e. a slot that holds a VALUE.
/// Currently we use SimpleSlot.
/// It doesn't matter, becaues we have not started using slot-enqueuing, yet.
pub type RubySlot = SimpleSlot;

/// Ruby memory slice, i.e. an array of VALUEs.
/// It is used by array-copy barriers which is supposed to perform bettern than copying array
/// elements one by one.  At this moment, we just leave it unimplemented.
pub type RubyMemorySlice = UnimplementedMemorySlice<RubySlot>;

impl VMBinding for Ruby {
    type VMObjectModel = object_model::VMObjectModel;
    type VMScanning = scanning::VMScanning;
    type VMCollection = collection::VMCollection;
    type VMActivePlan = active_plan::VMActivePlan;
    type VMReferenceGlue = reference_glue::VMReferenceGlue;

    type VMSlot = RubySlot;
    type VMMemorySlice = RubyMemorySlice;
}

/// The singleton object for the Ruby binding itself.
pub static BINDING: OnceCell<RubyBinding> = OnceCell::new();

/// Some data needs to be accessed fast.
/// We sacrifice safety for speed using unsynchronized global variables.
pub static mut BINDING_FAST: RubyBindingFast = RubyBindingFast::new();

/// Some data needs to be accessed fast.
pub static CONFIGURATION: RubyConfiguration = RubyConfiguration::new();

pub fn binding<'b>() -> &'b RubyBinding {
    BINDING
        .get()
        .expect("Attempt to use the binding before it is initialization")
}

pub fn mmtk() -> &'static MMTK<Ruby> {
    binding().mmtk
}

pub fn upcalls() -> &'static RubyUpcalls {
    binding().upcalls()
}

pub static GC_THREADS: OnceCell<Mutex<HashSet<ThreadId>>> = OnceCell::new();

pub(crate) fn register_gc_thread(thread_id: ThreadId) {
    let mut gc_threads = GC_THREADS.get().unwrap().lock().unwrap();
    gc_threads.insert(thread_id);
}

pub(crate) fn unregister_gc_thread(thread_id: ThreadId) {
    let mut gc_threads = GC_THREADS.get().unwrap().lock().unwrap();
    gc_threads.remove(&thread_id);
}

pub(crate) fn is_gc_thread(thread_id: ThreadId) -> bool {
    let gc_threads = GC_THREADS.get().unwrap().lock().unwrap();
    gc_threads.contains(&thread_id)
}

fn handle_gc_thread_panic(panic_info: &PanicHookInfo) {
    eprintln!("ERROR: An MMTk GC thread panicked.  This is a bug.");
    eprintln!("{panic_info}");

    let bt = std::backtrace::Backtrace::capture();
    match bt.status() {
        std::backtrace::BacktraceStatus::Unsupported => {
            eprintln!("Backtrace is unsupported.")
        }
        std::backtrace::BacktraceStatus::Disabled => {
            eprintln!("Backtrace is disabled.");
            eprintln!("run with `RUST_BACKTRACE=1` environment variable to display a backtrace");
        }
        std::backtrace::BacktraceStatus::Captured => {
            eprintln!("{bt}");
        }
        s => {
            eprintln!("Unknown backtrace status: {s:?}");
        }
    }

    std::process::abort();
}

pub(crate) fn set_panic_hook() {
    if GC_THREADS.set(Default::default()).is_err() {
        return;
    }

    let old_hook = std::panic::take_hook();

    std::panic::set_hook(Box::new(move |panic_info| {
        if is_gc_thread(std::thread::current().id()) {
            handle_gc_thread_panic(panic_info);
        } else {
            old_hook(panic_info);
        }
    }));
}

/// This kind of assertion is enabled if either building in debug mode or the
/// "extra_assert" feature is enabled.
#[macro_export]
macro_rules! extra_assert {
    ($($arg:tt)*) => {
        if std::cfg!(any(debug_assertions, feature = "extra_assert")) {
            std::assert!($($arg)*);
        }
    };
}
