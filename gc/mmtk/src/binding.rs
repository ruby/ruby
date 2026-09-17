use std::collections::HashSet;
use std::ffi::CString;
use std::sync::Mutex;
use std::thread::JoinHandle;

use mmtk::util::ObjectReference;
use mmtk::vm::ObjectModel;
use mmtk::MMTK;

use crate::abi;
use crate::abi::RubyBindingOptions;
use crate::pinning_registry::PinningRegistry;
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

pub struct RubyBinding {
    pub mmtk: &'static MMTK<Ruby>,
    pub options: RubyBindingOptions,
    pub upcalls: *const abi::RubyUpcalls,
    pub plan_name: Mutex<Option<CString>>,
    pub weak_proc: WeakProcessor,
    pub pinning_registry: PinningRegistry,
    pub gc_thread_join_handles: Mutex<Vec<JoinHandle<()>>>,
    pub wb_unprotected_objects: Mutex<HashSet<ObjectReference>>,
}

unsafe impl Sync for RubyBinding {}
unsafe impl Send for RubyBinding {}

impl RubyBinding {
    pub fn new(
        mmtk: &'static MMTK<Ruby>,
        binding_options: &RubyBindingOptions,
        upcalls: *const abi::RubyUpcalls,
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
            pinning_registry: PinningRegistry::new(),
            gc_thread_join_handles: Default::default(),
            wb_unprotected_objects: Default::default(),
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
        debug!("Registering WB-unprotected object: {object}");
        let mut objects = self.wb_unprotected_objects.lock().unwrap();
        objects.insert(object);
    }

    pub fn object_wb_unprotected_p(&self, object: ObjectReference) -> bool {
        let objects = self.wb_unprotected_objects.lock().unwrap();
        objects.contains(&object)
    }
}

pub(crate) fn object_survives_current_gc(object: ObjectReference) -> bool {
    let plan = crate::mmtk().get_plan();

    let is_nursery_gc = plan
        .generational()
        .is_some_and(|gen| gen.is_current_gc_nursery());

    if !is_nursery_gc {
        return object.is_reachable();
    }

    if !object.is_reachable() {
        return false;
    }

    if !is_los_object(object) {
        return true;
    }

    let byte = crate::object_model::VMObjectModel::LOCAL_LOS_MARK_NURSERY_SPEC
        .load_atomic::<Ruby, u8>(object, None, std::sync::atomic::Ordering::SeqCst);
    const NURSERY_BIT: u8 = 0b10;
    byte & NURSERY_BIT == 0
}

fn is_los_object(object: ObjectReference) -> bool {
    let access = abi::RubyObjectAccess::from_objref(object);
    access.payload_size() + abi::OBJREF_OFFSET
        > crate::mmtk()
            .get_plan()
            .constraints()
            .max_non_los_default_alloc_bytes
}
