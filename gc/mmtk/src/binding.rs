use std::collections::HashSet;
use std::ffi::CString;
use std::sync::atomic::AtomicBool;
use std::sync::Mutex;
use std::thread::JoinHandle;

use mmtk::util::ObjectReference;
use mmtk::MMTK;

use crate::abi;
use crate::abi::RubyBindingOptions;
use crate::weak_proc::WeakProcessor;
use crate::Ruby;

pub struct RubyBindingFast {
    pub suffix_size: usize,
}

impl Default for RubyBindingFast {
    fn default() -> Self {
        Self::new()
    }
}

impl RubyBindingFast {
    pub const fn new() -> Self {
        Self { suffix_size: 0 }
    }
}

pub struct RubyConfiguration {
    pub gc_enabled: AtomicBool,
}

impl Default for RubyConfiguration {
    fn default() -> Self {
        Self::new()
    }
}

impl RubyConfiguration {
    pub const fn new() -> Self {
        Self {
            // Mimic the old behavior when the gc_enabled flag was in mmtk-core.
            // We may refactor it so that it is false by default.
            gc_enabled: AtomicBool::new(true),
        }
    }
}

pub struct RubyBinding {
    pub mmtk: &'static MMTK<Ruby>,
    pub options: RubyBindingOptions,
    pub upcalls: *const abi::RubyUpcalls,
    pub plan_name: Mutex<Option<CString>>,
    pub weak_proc: WeakProcessor,
    pub gc_thread_join_handles: Mutex<Vec<JoinHandle<()>>>,
    pub wb_unprotected_objects: Mutex<HashSet<ObjectReference>>,

    pub weak_reference_dead_value: ObjectReference,
}

unsafe impl Sync for RubyBinding {}
unsafe impl Send for RubyBinding {}

impl RubyBinding {
    pub fn new(
        mmtk: &'static MMTK<Ruby>,
        binding_options: &RubyBindingOptions,
        upcalls: *const abi::RubyUpcalls,
        weak_reference_dead_value: ObjectReference,
    ) -> Self {
        unsafe {
            crate::BINDING_FAST.suffix_size = binding_options.suffix_size;
        }

        Self {
            mmtk,
            options: binding_options.clone(),
            upcalls,
            plan_name: Mutex::new(None),
            weak_proc: WeakProcessor::new(),
            gc_thread_join_handles: Default::default(),
            wb_unprotected_objects: Default::default(),

            weak_reference_dead_value
        }
    }

    pub fn upcalls(&self) -> &'static abi::RubyUpcalls {
        unsafe { &*self.upcalls as &'static abi::RubyUpcalls }
    }

    pub fn get_plan_name_c(&self) -> *const libc::c_char {
        let mut plan_name = self.plan_name.lock().unwrap();
        if plan_name.is_none() {
            let name_string = format!("{:?}", *self.mmtk.get_options().plan);
            let c_string = CString::new(name_string)
                .unwrap_or_else(|e| panic!("Failed converting plan name to CString: {e}"));
            *plan_name = Some(c_string);
        }
        plan_name.as_deref().unwrap().as_ptr()
    }

    pub fn join_all_gc_threads(&self) {
        let handles = {
            let mut guard = self.gc_thread_join_handles.lock().unwrap();
            std::mem::take(&mut *guard)
        };

        debug!("Joining GC threads...");
        let total = handles.len();
        let mut joined = 0;
        for handle in handles {
            handle.join().unwrap();
            joined += 1;
            debug!("{joined}/{total} GC threads joined.");
        }
    }

    pub fn register_wb_unprotected_object(&self, object: ObjectReference) {
        debug!("Registering WB-unprotected object: {}", object);
        let mut objects = self.wb_unprotected_objects.lock().unwrap();
        objects.insert(object);
    }

    pub fn object_wb_unprotected_p(&self, object: ObjectReference) -> bool {
        let objects = self.wb_unprotected_objects.lock().unwrap();
        objects.contains(&object)
    }
}
