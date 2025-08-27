use crate::codegen::{gen_exit_trampoline, gen_exit_trampoline_with_counter, gen_function_stub_hit_trampoline};
use crate::cruby::{self, rb_bug_panic_hook, rb_vm_insn_count, EcPtr, Qnil, VALUE, VM_INSTRUCTION_SIZE};
use crate::cruby_methods;
use crate::invariants::Invariants;
use crate::asm::CodeBlock;
use crate::options::get_option;
use crate::stats::{Counters, ExitCounters};
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
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: Option<ZJITState> = None;

impl ZJITState {
    /// Initialize the ZJIT globals
    pub fn init() {
        #[cfg(not(test))]
        let mut cb = {
            use crate::cruby::*;
            use crate::options::*;

            let exec_mem_bytes: usize = get_option!(exec_mem_bytes);
            let virt_block: *mut u8 = unsafe { rb_zjit_reserve_addr_space(64 * 1024 * 1024) };

            // Memory protection syscalls need page-aligned addresses, so check it here. Assuming
            // `virt_block` is page-aligned, `second_half` should be page-aligned as long as the
            // page size in bytes is a power of two 2¹⁹ or smaller. This is because the user
            // requested size is half of mem_option × 2²⁰ as it's in MiB.
            //
            // Basically, we don't support x86-64 2MiB and 1GiB pages. ARMv8 can do up to 64KiB
            // (2¹⁶ bytes) pages, which should be fine. 4KiB pages seem to be the most popular though.
            let page_size = unsafe { rb_zjit_get_page_size() };
            assert_eq!(
                virt_block as usize % page_size as usize, 0,
                "Start of virtual address block should be page-aligned",
            );

            use crate::virtualmem::*;
            use std::ptr::NonNull;
            use std::rc::Rc;
            use std::cell::RefCell;

            let mem_block = VirtualMem::new(
                crate::virtualmem::sys::SystemAllocator {},
                page_size,
                NonNull::new(virt_block).unwrap(),
                exec_mem_bytes,
                exec_mem_bytes, // TODO: change this to --zjit-mem-size (Shopify/ruby#686)
            );
            let mem_block = Rc::new(RefCell::new(mem_block));

            CodeBlock::new(mem_block.clone(), get_option!(dump_disasm))
        };
        #[cfg(test)]
        let mut cb = CodeBlock::new_dummy();

        let exit_trampoline = gen_exit_trampoline(&mut cb).unwrap();
        let function_stub_hit_trampoline = gen_function_stub_hit_trampoline(&mut cb).unwrap();

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
