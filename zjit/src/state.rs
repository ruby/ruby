//! Runtime state of ZJIT.

use crate::codegen::{gen_entry_trampoline, gen_exit_trampoline, gen_exit_trampoline_with_counter, gen_function_stub_hit_trampoline};
use crate::cruby::{self, rb_bug_panic_hook, rb_vm_insn_count, src_loc, EcPtr, Qnil, Qtrue, rb_vm_insn_addr2opcode, rb_profile_frames, VALUE, VM_INSTRUCTION_SIZE, size_t, rb_gc_mark, with_vm_lock};
use crate::cruby_methods;
use crate::invariants::Invariants;
use crate::asm::CodeBlock;
use crate::options::{get_option, rb_zjit_prepare_options};
use crate::stats::{Counters, InsnCounters, SideExitLocations};
use crate::virtualmem::CodePtr;
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

    /// Locations of side exists within generated code
    exit_locations: Option<SideExitLocations>,
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

            CodeBlock::new(mem_block.clone(), get_option!(dump_disasm))
        };

        let entry_trampoline = gen_entry_trampoline(&mut cb).unwrap().raw_ptr(&cb);
        let exit_trampoline = gen_exit_trampoline(&mut cb).unwrap();
        let function_stub_hit_trampoline = gen_function_stub_hit_trampoline(&mut cb).unwrap();

        let exit_locations = if get_option!(trace_side_exits).is_some() {
            Some(SideExitLocations::default())
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
            exit_locations,
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

    /// Get a mutable reference to the ZJIT raw samples Vec
    pub fn get_raw_samples() -> Option<&'static mut Vec<VALUE>> {
        ZJITState::get_instance().exit_locations.as_mut().map(|el| &mut el.raw_samples)
    }

    /// Get a mutable reference to the ZJIT line samples Vec.
    pub fn get_line_samples() -> Option<&'static mut Vec<i32>> {
        ZJITState::get_instance().exit_locations.as_mut().map(|el| &mut el.line_samples)
    }

    /// Get number of skipped samples.
    pub fn get_skipped_samples() -> Option<&'static mut usize> {
        ZJITState::get_instance().exit_locations.as_mut().map(|el| &mut el.skipped_samples)
    }

    /// Get number of skipped samples.
    pub fn set_skipped_samples(n: usize) -> Option<()> {
        ZJITState::get_instance().exit_locations.as_mut().map(|el| el.skipped_samples = n)
    }
}

/// Initialize ZJIT at boot. This is called even if ZJIT is disabled.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init(zjit_enabled: bool) {
    use InitializationState::*;

    debug_assert!(
        matches!(unsafe { &ZJIT_STATE }, Uninitialized),
        "rb_zjit_init should only be called once during boot",
    );

    // Initialize IDs and method annotations.
    // cruby_methods::init() must be called at boot,
    // as cmes could have been re-defined after boot.
    cruby::ids::init();

    let method_annotations = cruby_methods::init();

    unsafe { ZJIT_STATE = Initialized(method_annotations); }

    // If --zjit, enable ZJIT immediately
    if zjit_enabled {
        zjit_enable();
    }
}

/// Enable ZJIT compilation.
fn zjit_enable() {
    // TODO: call RubyVM::ZJIT::call_jit_hooks here

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

/// Call `rb_profile_frames` and write the result into buffers to be consumed by `rb_zjit_record_exit_stack`.
fn record_profiling_frames() -> (i32, Vec<VALUE>, Vec<i32>) {
    // Stackprof uses a buffer of length 2048 when collating the frames into statistics.
    // Since eventually the collected information will be used by Stackprof, collect only
    // 2048 frames at a time.
    // https://github.com/tmm1/stackprof/blob/5d832832e4afcb88521292d6dfad4a9af760ef7c/ext/stackprof/stackprof.c#L21
    const BUFF_LEN: usize = 2048;

    let mut frames_buffer = vec![VALUE(0_usize); BUFF_LEN];
    let mut lines_buffer = vec![0; BUFF_LEN];

    let stack_length = unsafe {
        rb_profile_frames(
            0,
            BUFF_LEN as i32,
            frames_buffer.as_mut_ptr(),
            lines_buffer.as_mut_ptr(),
        )
    };

    // Trim at `stack_length` since anything past it is redundant
    frames_buffer.truncate(stack_length as usize);
    lines_buffer.truncate(stack_length as usize);

    (stack_length, frames_buffer, lines_buffer)
}

/// Write samples in `frames_buffer` and `lines_buffer` from profiling into
/// `raw_samples` and `line_samples`. Also write opcode, number of frames,
/// and stack size to be consumed by Stackprof.
fn write_exit_stack_samples(
    raw_samples: &'static mut Vec<VALUE>,
    line_samples: &'static mut Vec<i32>,
    frames_buffer: &[VALUE],
    lines_buffer: &[i32],
    stack_length: i32,
    exit_pc: *const VALUE,
) {
    raw_samples.push(VALUE(stack_length as usize));
    line_samples.push(stack_length);

    // Push frames and their lines in reverse order.
    for i in (0..stack_length as usize).rev() {
        raw_samples.push(frames_buffer[i]);
        line_samples.push(lines_buffer[i]);
    }

    // Get the opcode from instruction handler at exit PC.
    let exit_opcode = unsafe { rb_vm_insn_addr2opcode((*exit_pc).as_ptr()) };
    raw_samples.push(VALUE(exit_opcode as usize));
    // Push a dummy line number since we don't know where this insn is from.
    line_samples.push(0);

    // Push number of times seen onto the stack.
    raw_samples.push(VALUE(1usize));
    line_samples.push(1);
}

fn try_increment_existing_stack(
    raw_samples: &mut [VALUE],
    line_samples: &mut [i32],
    frames_buffer: &[VALUE],
    stack_length: i32,
    samples_length: usize,
) -> bool {
    let prev_stack_len_index = raw_samples.len() - samples_length;
    let prev_stack_len = i64::from(raw_samples[prev_stack_len_index]);

    if prev_stack_len == stack_length as i64 {
        // Check if all stack lengths match and all frames are identical
        let frames_match = (0..stack_length).all(|i| {
            let current_frame = frames_buffer[stack_length as usize - 1 - i as usize];
            let prev_frame = raw_samples[prev_stack_len_index + i as usize + 1];
            current_frame == prev_frame
        });

        if frames_match {
            let counter_idx = raw_samples.len() - 1;
            let new_count = i64::from(raw_samples[counter_idx]) + 1;

            raw_samples[counter_idx] = VALUE(new_count as usize);
            line_samples[counter_idx] = new_count as i32;
            return true;
        }
    }
    false
}

/// Record a backtrace with ZJIT side exits
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_record_exit_stack(exit_pc: *const VALUE) {
    if !zjit_enabled_p() || get_option!(trace_side_exits).is_none() {
        return;
    }

    // When `trace_side_exits_sample_interval` is zero, then the feature is disabled.
    if get_option!(trace_side_exits_sample_interval) != 0 {
        // If `trace_side_exits_sample_interval` is set, then can safely unwrap
        // both `get_skipped_samples` and `set_skipped_samples`.
        let skipped_samples = *ZJITState::get_skipped_samples().unwrap();
        if skipped_samples < get_option!(trace_side_exits_sample_interval) {
            // Skip sample and increment counter.
            ZJITState::set_skipped_samples(skipped_samples + 1).unwrap();
            return;
        } else {
            ZJITState::set_skipped_samples(0).unwrap();
        }
    }

    let (stack_length, frames_buffer, lines_buffer) = record_profiling_frames();

    // Can safely unwrap since `trace_side_exits` must be true at this point
    let zjit_raw_samples = ZJITState::get_raw_samples().unwrap();
    let zjit_line_samples = ZJITState::get_line_samples().unwrap();
    assert_eq!(zjit_raw_samples.len(), zjit_line_samples.len());

    // Represents pushing the stack length, the instruction opcode, and the sample count.
    const SAMPLE_METADATA_SIZE: usize = 3;
    let samples_length = (stack_length as usize) + SAMPLE_METADATA_SIZE;

    // If zjit_raw_samples is greater than or equal to the current length of the samples
    // we might have seen this stack trace previously.
    if zjit_raw_samples.len() >= samples_length
        && try_increment_existing_stack(
            zjit_raw_samples,
            zjit_line_samples,
            &frames_buffer,
            stack_length,
            samples_length,
        )
    {
        return;
    }

    write_exit_stack_samples(
        zjit_raw_samples,
        zjit_line_samples,
        &frames_buffer,
        &lines_buffer,
        stack_length,
        exit_pc,
    );
}

/// Mark `raw_samples` so they can be used by rb_zjit_add_frame.
pub fn gc_mark_raw_samples() {
    // Return if ZJIT is not enabled
    if !zjit_enabled_p() || get_option!(trace_side_exits).is_none() {
        return;
    }

    let mut idx: size_t = 0;
    let zjit_raw_samples = ZJITState::get_raw_samples().unwrap();

    while idx < zjit_raw_samples.len() as size_t {
        let num = zjit_raw_samples[idx as usize];
        let mut i = 0;
        idx += 1;

        // Mark the zjit_raw_samples at the given index. These represent
        // the data that needs to be GC'd which are the current frames.
        while i < i32::from(num) {
            unsafe { rb_gc_mark(zjit_raw_samples[idx as usize]); }
            i += 1;
            idx += 1;
        }

        // Increase index for exit instruction.
        idx += 1;
        // Increase index for bookeeping value (number of times we've seen this
        // row in a stack).
        idx += 1;
    }
}
