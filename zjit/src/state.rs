//! Runtime state of ZJIT.

use crate::codegen::{gen_entry_trampoline, gen_exit_trampoline, gen_exit_trampoline_with_counter, gen_function_stub_hit_trampoline};
use crate::cruby::{self, rb_bug_panic_hook, rb_vm_insn_count, src_loc, EcPtr, Qnil, Qtrue, rb_profile_frames, rb_profile_frame_full_label, rb_profile_frame_absolute_path, rb_profile_frame_path, VALUE, VM_INSTRUCTION_SIZE, with_vm_lock, rust_str_to_id, rb_funcallv, rb_const_get, rb_cRubyVM};
use crate::cruby_methods;
use cruby::{ID, rb_callable_method_entry, get_def_method_serial, rb_gc_register_mark_object, ruby_str_to_rust_string_result};
use std::sync::atomic::Ordering;
use crate::invariants::Invariants;
use crate::asm::CodeBlock;
use crate::options::{get_option, rb_zjit_prepare_options};
use crate::jit_frame::JITFrame;
use crate::stats::{Counters, InsnCounters, PerfettoTracer};
use crate::virtualmem::CodePtr;
use std::sync::atomic::AtomicUsize;
use std::collections::HashMap;
use std::ptr::null;

/// Shared trampoline to enter ZJIT. Not null when ZJIT is enabled.
#[allow(non_upper_case_globals)]
#[unsafe(no_mangle)]
pub static mut rb_zjit_entry: *const u8 = null();

/// Like rb_zjit_enabled_p, but for Rust code.
pub fn zjit_enabled_p() -> bool {
    unsafe { rb_zjit_entry != null() }
}

/// Global state needed for code generation
pub struct ZJITState {
    /// Inline code block (fast path)
    code_block: CodeBlock,

    /// ZJIT statistics
    counters: Counters,

    /// Side-exit counters
    exit_counters: InsnCounters,

    /// Send fallback counters
    send_fallback_counters: InsnCounters,

    /// Assumptions that require invalidation
    invariants: Invariants,

    /// Assert successful compilation if set to true
    assert_compiles: bool,

    /// Properties of core library methods
    method_annotations: cruby_methods::Annotations,

    /// Trampoline to side-exit without restoring PC or the stack
    exit_trampoline: CodePtr,

    /// Trampoline to side-exit and increment exit_compilation_failure
    exit_trampoline_with_counter: CodePtr,

    /// Trampoline to call function_stub_hit
    function_stub_hit_trampoline: CodePtr,

    /// Counter pointers for full frame C functions
    full_frame_cfunc_counter_pointers: HashMap<String, Box<u64>>,

    /// Counter pointers for un-annotated C functions
    not_annotated_frame_cfunc_counter_pointers: HashMap<String, Box<u64>>,

    /// Counter pointers for all calls to any kind of C function from JIT code
    ccall_counter_pointers: HashMap<String, Box<u64>>,

    /// Counter pointers for access counts of ISEQs accessed by JIT code
    iseq_calls_count_pointers: HashMap<String, Box<u64>>,

    /// Perfetto tracer for --zjit-trace-exits
    perfetto_tracer: Option<PerfettoTracer>,

    /// Frame metadata for ISEQ and C calls that are known at compile time
    jit_frames: Vec<*mut JITFrame>,
}

/// Tracks the initialization progress
enum InitializationState {
    Uninitialized,

    /// At boot time, rb_zjit_init will be called regardless of whether
    /// ZJIT is enabled, in this phase we initialize any states that must
    /// be captured at during boot.
    Initialized(cruby_methods::Annotations),

    /// When ZJIT is enabled, either during boot with `--zjit`, or lazily
    /// at a later time with `RubyVM::ZJIT.enable`, we perform the rest
    /// of the initialization steps and produce the `ZJITState` instance.
    Enabled(ZJITState),

    /// Indicates that ZJITState::init has panicked. Should never be
    /// encountered in practice since we abort immediately when that
    /// happens.
    Panicked,
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: InitializationState = InitializationState::Uninitialized;

impl ZJITState {
    /// Initialize the ZJIT globals. Return the address of the JIT entry trampoline.
    pub fn init() -> *const u8 {
        use InitializationState::*;

        let initialization_state = unsafe {
            std::mem::replace(&mut ZJIT_STATE, Panicked)
        };

        let Initialized(method_annotations) = initialization_state else {
            panic!("rb_zjit_init was never called");
        };

        let mut cb = {
            use crate::options::*;
            use crate::virtualmem::*;
            use std::rc::Rc;
            use std::cell::RefCell;

            let mem_block = VirtualMem::alloc(get_option!(exec_mem_bytes), Some(get_option!(mem_bytes)));
            let mem_block = Rc::new(RefCell::new(mem_block));

            CodeBlock::new(mem_block.clone(), get_option_ref!(dump_disasm).is_some())
        };

        let entry_trampoline = gen_entry_trampoline(&mut cb).unwrap().raw_ptr(&cb);
        let exit_trampoline = gen_exit_trampoline(&mut cb).unwrap();
        let function_stub_hit_trampoline = gen_function_stub_hit_trampoline(&mut cb).unwrap();

        let perfetto_tracer = if get_option!(trace_side_exits).is_some() {
            Some(PerfettoTracer::new())
        } else {
            None
        };

        // Initialize the codegen globals instance
        let zjit_state = ZJITState {
            code_block: cb,
            counters: Counters::default(),
            exit_counters: [0; VM_INSTRUCTION_SIZE as usize],
            send_fallback_counters: [0; VM_INSTRUCTION_SIZE as usize],
            invariants: Invariants::default(),
            assert_compiles: false,
            method_annotations,
            exit_trampoline,
            function_stub_hit_trampoline,
            exit_trampoline_with_counter: exit_trampoline,
            full_frame_cfunc_counter_pointers: HashMap::new(),
            not_annotated_frame_cfunc_counter_pointers: HashMap::new(),
            ccall_counter_pointers: HashMap::new(),
            iseq_calls_count_pointers: HashMap::new(),
            perfetto_tracer,
            jit_frames: vec![],
        };
        unsafe { ZJIT_STATE = Enabled(zjit_state); }

        // With --zjit-stats, use a different trampoline on function stub exits
        // to count exit_compilation_failure. Note that the trampoline code depends
        // on the counter, so ZJIT_STATE needs to be initialized first.
        if get_option!(stats) {
            let cb = ZJITState::get_code_block();
            let code_ptr = gen_exit_trampoline_with_counter(cb, exit_trampoline).unwrap();
            ZJITState::get_instance().exit_trampoline_with_counter = code_ptr;
        }

        entry_trampoline
    }

    /// Return true if zjit_state has been initialized
    pub fn has_instance() -> bool {
        matches!(unsafe { &ZJIT_STATE }, InitializationState::Enabled(_))
    }

    /// Get a mutable reference to the codegen globals instance
    fn get_instance() -> &'static mut ZJITState {
        if let InitializationState::Enabled(instance) = unsafe { &mut ZJIT_STATE } {
            instance
        } else {
            panic!("ZJITState::get_instance called when ZJIT is not enabled")
        }
    }

    /// Get a mutable reference to the inline code block
    pub fn get_code_block() -> &'static mut CodeBlock {
        &mut ZJITState::get_instance().code_block
    }

    /// Get a mutable reference to the invariants
    pub fn get_invariants() -> &'static mut Invariants {
        &mut ZJITState::get_instance().invariants
    }

    pub fn get_jit_frames() -> &'static mut Vec<*mut JITFrame> {
        &mut ZJITState::get_instance().jit_frames
    }

    pub fn get_method_annotations() -> &'static cruby_methods::Annotations {
        &ZJITState::get_instance().method_annotations
    }

    /// Return true if successful compilation should be asserted
    pub fn assert_compiles_enabled() -> bool {
        ZJITState::get_instance().assert_compiles
    }

    /// Start asserting successful compilation
    pub fn enable_assert_compiles() {
        let instance = ZJITState::get_instance();
        instance.assert_compiles = true;
    }

    /// Stop asserting successful compilation
    pub fn disable_assert_compiles() {
        let instance = ZJITState::get_instance();
        instance.assert_compiles = false;
    }

    /// Get a mutable reference to counters for ZJIT stats
    pub fn get_counters() -> &'static mut Counters {
        &mut ZJITState::get_instance().counters
    }

    /// Get a mutable reference to side-exit counters
    pub fn get_exit_counters() -> &'static mut InsnCounters {
        &mut ZJITState::get_instance().exit_counters
    }

    /// Get a mutable reference to fallback counters
    pub fn get_send_fallback_counters() -> &'static mut InsnCounters {
        &mut ZJITState::get_instance().send_fallback_counters
    }

    /// Get a mutable reference to full frame cfunc counter pointers
    pub fn get_not_inlined_cfunc_counter_pointers() -> &'static mut HashMap<String, Box<u64>> {
        &mut ZJITState::get_instance().full_frame_cfunc_counter_pointers
    }

    /// Get a mutable reference to non-annotated cfunc counter pointers
    pub fn get_not_annotated_cfunc_counter_pointers() -> &'static mut HashMap<String, Box<u64>> {
        &mut ZJITState::get_instance().not_annotated_frame_cfunc_counter_pointers
    }

    /// Get a mutable reference to ccall counter pointers
    pub fn get_ccall_counter_pointers() -> &'static mut HashMap<String, Box<u64>> {
        &mut ZJITState::get_instance().ccall_counter_pointers
    }

    /// Get a mutable reference to iseq access count pointers
    pub fn get_iseq_calls_count_pointers() -> &'static mut HashMap<String, Box<u64>> {
        &mut ZJITState::get_instance().iseq_calls_count_pointers
    }

    /// Was --zjit-save-compiled-iseqs specified?
    pub fn should_log_compiled_iseqs() -> bool {
        get_option!(log_compiled_iseqs).is_some()
    }

    /// Log the name of a compiled ISEQ to the file specified in options.log_compiled_iseqs
    pub fn log_compile(iseq_name: String) {
        assert!(ZJITState::should_log_compiled_iseqs());
        let filename = get_option!(log_compiled_iseqs).as_ref().unwrap();
        use std::io::Write;
        let mut file = match std::fs::OpenOptions::new().create(true).append(true).open(filename) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("ZJIT: Failed to create file '{}': {}", filename.display(), e);
                return;
            }
        };
        if let Err(e) = writeln!(file, "{iseq_name}") {
            eprintln!("ZJIT: Failed to write to file '{}': {}", filename.display(), e);
        }
    }

    /// Check if we are allowed to compile a given ISEQ based on --zjit-allowed-iseqs
    pub fn can_compile_iseq(iseq: cruby::IseqPtr) -> bool {
        if let Some(ref allowed_iseqs) = get_option!(allowed_iseqs) {
            let name = cruby::iseq_get_location(iseq, 0);
            allowed_iseqs.contains(&name)
        } else {
            true // If no restrictions, allow all ISEQs
        }
    }

    /// Return a code pointer to the side-exit trampoline
    pub fn get_exit_trampoline() -> CodePtr {
        ZJITState::get_instance().exit_trampoline
    }

    /// Return a code pointer to the exit trampoline for function stubs
    pub fn get_exit_trampoline_with_counter() -> CodePtr {
        ZJITState::get_instance().exit_trampoline_with_counter
    }

    /// Return a code pointer to the function stub hit trampoline
    pub fn get_function_stub_hit_trampoline() -> CodePtr {
        ZJITState::get_instance().function_stub_hit_trampoline
    }

    /// Get a mutable reference to the Perfetto tracer
    pub fn get_tracer() -> Option<&'static mut PerfettoTracer> {
        ZJITState::get_instance().perfetto_tracer.as_mut()
    }
}

/// The `::RubyVM::ZJIT` module.
pub static ZJIT_MODULE: AtomicUsize = AtomicUsize::new(!0);
/// Serial of the canonical version of `induce_side_exit!` right after VM boot.
pub static INDUCE_SIDE_EXIT_SERIAL: AtomicUsize = AtomicUsize::new(!0);
/// Serial of the canonical version of `induce_compile_failure!` right after VM boot.
pub static INDUCE_COMPILE_FAILURE_SERIAL: AtomicUsize = AtomicUsize::new(!0);
/// Serial of the canonical version of `induce_breakpoint!` right after VM boot.
pub static INDUCE_BREAKPOINT_SERIAL: AtomicUsize = AtomicUsize::new(!0);

/// Check if a method, `method_id`, currently exists on `ZJIT.singleton_class` and has the `expected_serial`.
pub fn zjit_module_method_match_serial(method_id: ID, expected_serial: &AtomicUsize) -> bool {
    let zjit_module_singleton = VALUE(ZJIT_MODULE.load(Ordering::Relaxed)).class_of();
    let cme = unsafe { rb_callable_method_entry(zjit_module_singleton, method_id) };
    if cme.is_null() {
        false
    } else {
        let serial = unsafe { get_def_method_serial((*cme).def) };
        serial == expected_serial.load(std::sync::atomic::Ordering::Relaxed)
    }
}

/// Initialize IDs and annotate builtin C method entries.
/// Must be called at boot before ruby_init_prelude() since the prelude
/// could redefine core methods (e.g. Kernel.prepend via bundler).
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init_builtin_cmes() {
    use InitializationState::*;

    debug_assert!(
        matches!(unsafe { &ZJIT_STATE }, Uninitialized),
        "rb_zjit_init_builtin_cmes should only be called once during boot",
    );

    cruby::ids::init();

    let method_annotations = cruby_methods::init();

    unsafe { ZJIT_STATE = Initialized(method_annotations); }

    // Boot time setup for compiler directives
    unsafe {
        let zjit_module = rb_const_get(rb_cRubyVM, rust_str_to_id("ZJIT"));

        let cme = rb_callable_method_entry(zjit_module.class_of(), ID!(induce_side_exit_bang));
        assert!(! cme.is_null(), "RubyVM::ZJIT.induce_side_exit! should exist on boot");
        let serial = get_def_method_serial((*cme).def) ;
        INDUCE_SIDE_EXIT_SERIAL.store(serial, Ordering::Relaxed);

        let cme = rb_callable_method_entry(zjit_module.class_of(), ID!(induce_compile_failure_bang));
        assert!(! cme.is_null(), "RubyVM::ZJIT.induce_compile_failure! should exist on boot");
        let serial = get_def_method_serial((*cme).def) ;
        INDUCE_COMPILE_FAILURE_SERIAL.store(serial, Ordering::Relaxed);

        let cme = rb_callable_method_entry(zjit_module.class_of(), ID!(induce_breakpoint_bang));
        assert!(! cme.is_null(), "RubyVM::ZJIT.induce_breakpoint! should exist on boot");
        let serial = get_def_method_serial((*cme).def) ;
        INDUCE_BREAKPOINT_SERIAL.store(serial, Ordering::Relaxed);

        // Root and pin the module since we'll be doing object identity comparisons.
        ZJIT_MODULE.store(zjit_module.0, Ordering::Relaxed);
        rb_gc_register_mark_object(zjit_module);
    }
}

/// Initialize ZJIT at boot. This is called even if ZJIT is disabled.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init(zjit_enabled: bool) {
    // If --zjit, enable ZJIT immediately
    if zjit_enabled {
        zjit_enable();
    }
}

/// Enable ZJIT compilation.
fn zjit_enable() {
    // Call ZJIT hooks before enabling ZJIT to avoid compiling the hooks themselves
    unsafe {
        let zjit = rb_const_get(rb_cRubyVM, rust_str_to_id("ZJIT"));
        rb_funcallv(zjit, rust_str_to_id("call_jit_hooks"), 0, std::ptr::null());
    }

    // Catch panics to avoid UB for unwinding into C frames.
    // See https://doc.rust-lang.org/nomicon/exception-safety.html
    let result = std::panic::catch_unwind(|| {
        // Initialize ZJIT states
        let zjit_entry = ZJITState::init();

        // Install a panic hook for ZJIT
        rb_bug_panic_hook();

        // Discard the instruction count for boot which we never compile
        unsafe { rb_vm_insn_count = 0; }

        // ZJIT enabled and initialized successfully
        assert!(unsafe{ rb_zjit_entry == null() });
        unsafe { rb_zjit_entry = zjit_entry; }
    });

    if result.is_err() {
        println!("ZJIT: zjit_enable() panicked. Aborting.");
        std::process::abort();
    }
}

/// Enable ZJIT compilation, returning Qtrue if ZJIT was previously disabled
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_enable(_ec: EcPtr, _self: VALUE) -> VALUE {
    with_vm_lock(src_loc!(), || {
        // Options would not have been initialized during boot if no flags were specified
        rb_zjit_prepare_options();

        // Initialize and enable ZJIT
        zjit_enable();

        // Add "+ZJIT" to RUBY_DESCRIPTION
        unsafe {
            unsafe extern "C" {
                fn ruby_set_zjit_description();
            }
            ruby_set_zjit_description();
        }

        Qtrue
    })
}

/// Assert that any future ZJIT compilation will return a function pointer (not fail to compile)
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_assert_compiles(_ec: EcPtr, _self: VALUE) -> VALUE {
    ZJITState::enable_assert_compiles();
    Qnil
}

/// Resolve a profile frame VALUE to a human-readable "label (path)" string.
fn resolve_frame_label(frame: VALUE) -> String {
    unsafe {
        let label_str = ruby_str_to_rust_string_result(rb_profile_frame_full_label(frame)).unwrap_or("<unknown>".into());

        let path = rb_profile_frame_absolute_path(frame);
        let path = if path.nil_p() { rb_profile_frame_path(frame) } else { path };
        let path_str = ruby_str_to_rust_string_result(path).unwrap_or("<unknown>".into());

        format!("{label_str} ({path_str})")
    }
}

/// Record a backtrace with ZJIT side exits as a Perfetto trace event
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_record_exit_stack(reason: *const std::ffi::c_char) {
    if !zjit_enabled_p() || get_option!(trace_side_exits).is_none() {
        return;
    }

    let tracer = match ZJITState::get_tracer() {
        Some(t) => t,
        None => return,
    };

    // When `trace_side_exits_sample_interval` is non-zero, apply sampling.
    if get_option!(trace_side_exits_sample_interval) != 0 {
        if tracer.skipped_samples < get_option!(trace_side_exits_sample_interval) {
            tracer.skipped_samples += 1;
            return;
        } else {
            tracer.skipped_samples = 0;
        }
    }

    // Collect profile frames
    const BUFF_LEN: usize = 2048;
    let mut frames_buffer = vec![VALUE(0_usize); BUFF_LEN];
    let mut lines_buffer = vec![0i32; BUFF_LEN];

    let stack_length = unsafe {
        rb_profile_frames(
            0,
            BUFF_LEN as i32,
            frames_buffer.as_mut_ptr(),
            lines_buffer.as_mut_ptr(),
        )
    };

    // Resolve each frame to a human-readable string (top frame first)
    let frames: Vec<String> = (0..stack_length as usize)
        .map(|i| resolve_frame_label(frames_buffer[i]))
        .collect();

    // Get the reason string
    let reason_str = if reason.is_null() {
        "unknown"
    } else {
        unsafe { std::ffi::CStr::from_ptr(reason).to_str().unwrap_or("unknown") }
    };

    tracer.write_event(reason_str, &frames);
}
