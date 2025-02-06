use std::rc::Rc;
use std::cell::RefCell;
use crate::cruby::*;
use crate::virtualmem::*;
use crate::{utils::IntoUsize};

/// Block of memory into which instructions can be assembled
pub struct CodeBlock {
    // Memory for storing the encoded instructions
    mem_block: Rc<RefCell<VirtualMem>>,
}

impl CodeBlock {
    /// Make a new CodeBlock
    pub fn new(mem_block: Rc<RefCell<VirtualMem>>) -> Self {
        Self { mem_block }
    }
}

/// Global state needed for code generation
pub struct ZJITState {
    /// Inline code block (fast path)
    inline_cb: CodeBlock,
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: Option<ZJITState> = None;

impl ZJITState {
    /// Initialize the ZJIT globals
    pub fn init() {
        let exec_mem_size: usize = 64 * 1024 * 1024; // TODO: support the option

        #[cfg(not(test))]
        let cb = {
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
                virt_block as usize % page_size.as_usize(), 0,
                "Start of virtual address block should be page-aligned",
            );

            use crate::virtualmem::*;
            use std::ptr::NonNull;

            let mem_block = VirtualMem::new(
                crate::virtualmem::sys::SystemAllocator {},
                page_size,
                NonNull::new(virt_block).unwrap(),
                exec_mem_size,
                64 * 1024 * 1024, // TODO: support the option
            );
            let mem_block = Rc::new(RefCell::new(mem_block));

            CodeBlock::new(mem_block.clone())
        };
    }
}
