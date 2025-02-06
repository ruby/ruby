use std::rc::Rc;
use std::cell::RefCell;

use crate::virtualmem::VirtualMem;

/// Block of memory into which instructions can be assembled
pub struct CodeBlock {
    // Memory for storing the encoded instructions
    mem_block: Rc<RefCell<VirtualMem>>,
}

/// Global state needed for code generation
pub struct ZJITState {
    /// Inline code block (fast path)
    inline_cb: CodeBlock,
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: Option<ZJITState> = None;
