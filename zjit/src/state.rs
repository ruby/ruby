use std::collections::HashSet;

use crate::cruby::{self, rb_bug_panic_hook, EcPtr, Qnil, VALUE};
use crate::cruby_methods;
use crate::invariants::Invariants;
use crate::options::Options;
use crate::asm::CodeBlock;

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

    /// ZJIT command-line options
    options: Options,

    /// Assumptions that require invalidation
    invariants: Invariants,

    /// Assert successful compilation if set to true
    assert_compiles: bool,

    /// Properties of core library methods
    method_annotations: cruby_methods::Annotations,

    /// The address of the instruction that JIT-to-JIT calls return to
    iseq_return_addrs: HashSet<*const u8>,
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: Option<ZJITState> = None;

impl ZJITState {
    /// Initialize the ZJIT globals, given options allocated by rb_zjit_init_options()
    pub fn init(options: Options) {
        #[cfg(not(test))]
        let cb = {
            use crate::cruby::*;

            let exec_mem_size: usize = 64 * 1024 * 1024; // TODO: implement the option
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
                exec_mem_size,
                64 * 1024 * 1024, // TODO: support the option
            );
            let mem_block = Rc::new(RefCell::new(mem_block));

            CodeBlock::new(mem_block.clone(), options.dump_disasm)
        };
        #[cfg(test)]
        let cb = CodeBlock::new_dummy();

        // Initialize the codegen globals instance
        let zjit_state = ZJITState {
            code_block: cb,
            options,
            invariants: Invariants::default(),
            assert_compiles: false,
            method_annotations: cruby_methods::init(),
            iseq_return_addrs: HashSet::new(),
        };
        unsafe { ZJIT_STATE = Some(zjit_state); }
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

    /// Get a mutable reference to the options
    pub fn get_options() -> &'static mut Options {
        &mut ZJITState::get_instance().options
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

    /// Record an address that a JIT-to-JIT call returns to
    pub fn add_iseq_return_addr(addr: *const u8) {
        ZJITState::get_instance().iseq_return_addrs.insert(addr);
    }

    /// Returns true if a JIT-to-JIT call returns to a given address
    pub fn is_iseq_return_addr(addr: *const u8) -> bool {
        ZJITState::get_instance().iseq_return_addrs.contains(&addr)
    }
}

/// Initialize ZJIT, given options allocated by rb_zjit_init_options()
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_init(options: *const u8) {
    // Catch panics to avoid UB for unwinding into C frames.
    // See https://doc.rust-lang.org/nomicon/exception-safety.html
    let result = std::panic::catch_unwind(|| {
        cruby::ids::init();

        let options = unsafe { Box::from_raw(options as *mut Options) };
        ZJITState::init(*options);
        std::mem::drop(options);

        rb_bug_panic_hook();

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
