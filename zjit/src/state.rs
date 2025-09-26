//! Runtime state of ZJIT.

use crate::codegen::{gen_exit_trampoline, gen_exit_trampoline_with_counter, gen_function_stub_hit_trampoline};
use crate::cruby::{self, rb_bug_panic_hook, rb_vm_insn_count, EcPtr, Qnil, rb_vm_insn_addr2opcode, rb_profile_frames, VALUE, VM_INSTRUCTION_SIZE, size_t, rb_gc_mark};
use crate::cruby_methods;
use crate::invariants::Invariants;
use crate::asm::CodeBlock;
use crate::options::get_option;
use crate::stats::{Counters, ExitCounters, SideExitLocations};
use crate::virtualmem::CodePtr;

#[allow(non_upper_case_globals)]
#[unsafe(no_mangle)]
pub static mut rb_zjit_enabled_p: bool = false;

/// Like rb_zjit_enabled_p, but for Rust code.
pub fn zjit_enabled_p() -> bool {
    unsafe { rb_zjit_enabled_p }
}

/// Global state needed for code generation
pub struct ZJITState {
    /// Inline code block (fast path)
    code_block: CodeBlock,

    /// ZJIT statistics
    counters: Counters,

    /// Side-exit counters
    exit_counters: ExitCounters,

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

    /// Locations of side exists within generated code
    exit_locations: Option<SideExitLocations>,
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: Option<ZJITState> = None;

impl ZJITState {
    /// Initialize the ZJIT globals
    pub fn init() {
        let mut cb = {
            use crate::options::*;
            use crate::virtualmem::*;
            use std::rc::Rc;
            use std::cell::RefCell;

            let mem_block = VirtualMem::alloc(get_option!(exec_mem_bytes), Some(get_option!(mem_bytes)));
            let mem_block = Rc::new(RefCell::new(mem_block));

            CodeBlock::new(mem_block.clone(), get_option!(dump_disasm))
        };

        let exit_trampoline = gen_exit_trampoline(&mut cb).unwrap();
        let function_stub_hit_trampoline = gen_function_stub_hit_trampoline(&mut cb).unwrap();

        let exit_locations = if get_option!(dump_side_exits) {
            Some(SideExitLocations::default())
        } else {
            None
        };

        // Initialize the codegen globals instance
        let zjit_state = ZJITState {
            code_block: cb,
            counters: Counters::default(),
            exit_counters: [0; VM_INSTRUCTION_SIZE as usize],
            invariants: Invariants::default(),
            assert_compiles: false,
            method_annotations: cruby_methods::init(),
            exit_trampoline,
            function_stub_hit_trampoline,
            exit_trampoline_with_counter: exit_trampoline,
            exit_locations,
        };
        unsafe { ZJIT_STATE = Some(zjit_state); }

        // With --zjit-stats, use a different trampoline on function stub exits
        // to count exit_compilation_failure. Note that the trampoline code depends
        // on the counter, so ZJIT_STATE needs to be initialized first.
        if get_option!(stats) {
            let cb = ZJITState::get_code_block();
            let code_ptr = gen_exit_trampoline_with_counter(cb, exit_trampoline).unwrap();
            ZJITState::get_instance().exit_trampoline_with_counter = code_ptr;
        }
    }

    /// Return true if zjit_state has been initialized
    pub fn has_instance() -> bool {
        unsafe { ZJIT_STATE.as_mut().is_some() }
    }

    /// Get a mutable reference to the codegen globals instance
    fn get_instance() -> &'static mut ZJITState {
        unsafe { ZJIT_STATE.as_mut().unwrap() }
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
    pub fn get_exit_counters() -> &'static mut ExitCounters {
        &mut ZJITState::get_instance().exit_counters
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
        if let Err(e) = writeln!(file, "{}", iseq_name) {
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

    /// Get a mutable reference to the yjit raw samples Vec
    pub fn get_raw_samples() -> Option<&'static mut Vec<VALUE>> {
        ZJITState::get_instance().exit_locations.as_mut().map(|el| &mut el.raw_samples)
    }

    /// Get a mutable reference to yjit the line samples Vec.
    pub fn get_line_samples() -> Option<&'static mut Vec<i32>> {
        ZJITState::get_instance().exit_locations.as_mut().map(|el| &mut el.line_samples)
    }
}

/// Initialize ZJIT
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init() {
    // Catch panics to avoid UB for unwinding into C frames.
    // See https://doc.rust-lang.org/nomicon/exception-safety.html
    let result = std::panic::catch_unwind(|| {
        // Initialize ZJIT states
        cruby::ids::init();
        ZJITState::init();

        // Install a panic hook for ZJIT
        rb_bug_panic_hook();

        // Discard the instruction count for boot which we never compile
        unsafe { rb_vm_insn_count = 0; }

        // ZJIT enabled and initialized successfully
        assert!(unsafe{ !rb_zjit_enabled_p });
        unsafe { rb_zjit_enabled_p = true; }
    });

    if result.is_err() {
        println!("ZJIT: zjit_init() panicked. Aborting.");
        std::process::abort();
    }
}

/// Assert that any future ZJIT compilation will return a function pointer (not fail to compile)
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_assert_compiles(_ec: EcPtr, _self: VALUE) -> VALUE {
    ZJITState::enable_assert_compiles();
    Qnil
}

/// Call `rb_profile_frames` and format the result into buffers.
fn record_profiling_frames() -> (i32, Vec<VALUE>, Vec<i32>) {
    // Use the same buffer size as Stackprof.
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

/// Record a backtrace with ZJIT side exits
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_record_exit_stack(exit_pc: *const VALUE)
{
    if !zjit_enabled_p() || !get_option!(dump_side_exits) {
        return;
    }

    let (stack_length, frames_buffer, lines_buffer) = record_profiling_frames();

    // Can safely unwrap since `dump_side_exits` must be true at this point
    let zjit_raw_samples = ZJITState::get_raw_samples().unwrap();
    let zjit_lines_samples = ZJITState::get_line_samples().unwrap();
    assert_eq!(zjit_raw_samples.len(), zjit_lines_samples.len());

    // todo(aidenfoxivey): why is this +3 here
    let samples_length = (stack_length as usize) + 3;

    // If zjit_raw_samples is less than or equal to the current length of the samples
    // we might have seen this stack trace previously.
    if zjit_raw_samples.len() >= samples_length {
        let prev_stack_len_index = zjit_raw_samples.len() - samples_length;
        let prev_stack_len = i64::from(zjit_raw_samples[prev_stack_len_index]);
        let mut idx = stack_length - 1;
        let mut prev_frame_idx = 0;
        let mut seen_already = true;

        // If the previous stack length and current stack length are equal,
        // loop and compare the current frame to the previous frame. If they are
        // not equal, set seen_already to false and break out of the loop.
        if prev_stack_len == stack_length as i64 {
            while idx >= 0 {
                let current_frame = frames_buffer[idx as usize];
                let prev_frame = zjit_raw_samples[prev_stack_len_index + prev_frame_idx + 1];

                // If the current frame and previous frame are not equal, set
                // seen_already to false and break out of the loop.
                if current_frame != prev_frame {
                    seen_already = false;
                    break;
                }

                idx -= 1;
                prev_frame_idx += 1;
            }

            // If we know we've seen this stack before, increment the counter by 1.
            if seen_already {
                let prev_idx = zjit_raw_samples.len() - 1;
                let prev_count = i64::from(zjit_raw_samples[prev_idx]);
                let new_count = prev_count + 1;

                zjit_raw_samples[prev_idx] = VALUE(new_count as usize);
                zjit_lines_samples[prev_idx] = new_count as i32;

                return;
            }
        }
    }

    zjit_raw_samples.push(VALUE(stack_length as usize));
    zjit_lines_samples.push(stack_length);

    frames_buffer.iter().zip(lines_buffer.iter()).rev().for_each(|(frame, line)| {
        zjit_raw_samples.push(*frame);
        zjit_lines_samples.push(*line);
    });

    // Get the opcode from instruction handler at exit PC.
    let insn = unsafe { rb_vm_insn_addr2opcode((*exit_pc).as_ptr()) };
    zjit_raw_samples.push(VALUE(insn as usize));

    // We don't know the line that this instruction sits at
    zjit_lines_samples.push(0);

    // Push number of times seen onto the stack, which is 1
    // because it's the first time we've seen it.
    zjit_raw_samples.push(VALUE(1_usize));
    zjit_lines_samples.push(1);
}

/// Mark `raw_samples` so they can be used by rb_yjit_add_frame.
pub fn gc_mark_raw_samples() {
    // Return if YJIT is not enabled
    if !zjit_enabled_p() || !get_option!(stats) || !get_option!(dump_side_exits) {
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
