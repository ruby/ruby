use std::mem;
use std::rc::Rc;
use std::cell::RefCell;
use crate::cruby::*;
use crate::virtualmem::*;
use crate::options::Options;

/// Block of memory into which instructions can be assembled
pub struct CodeBlock {
    // Memory for storing the encoded instructions
    mem_block: Rc<RefCell<VirtualMem>>,

    // Current writing position
    write_pos: usize,

    // Set if the CodeBlock is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    dropped_bytes: bool,
}


impl CodeBlock {
    /// Make a new CodeBlock
    pub fn new(mem_block: Rc<RefCell<VirtualMem>>) -> Self {
        Self {
            mem_block,
            write_pos: 0,
            dropped_bytes: false,
        }
    }

    /// Get a (possibly dangling) direct pointer to the current write position
    pub fn get_write_ptr(&self) -> CodePtr {
        self.get_ptr(self.write_pos)
    }

    /// Get a (possibly dangling) direct pointer into the executable memory block
    pub fn get_ptr(&self, offset: usize) -> CodePtr {
        self.mem_block.borrow().start_ptr().add_bytes(offset)
    }

    /// Write a single byte at the current position.
    pub fn write_byte(&mut self, byte: u8) {
        let write_ptr = self.get_write_ptr();
        // TODO: check has_capacity()
        if self.mem_block.borrow_mut().write_byte(write_ptr, byte).is_ok() {
            self.write_pos += 1;
        } else {
            self.dropped_bytes = true;
        }
    }

    /// Write multiple bytes starting from the current position.
    pub fn write_bytes(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.write_byte(*byte);
        }
    }

    /// Write an integer over the given number of bits at the current position.
    pub fn write_int(&mut self, val: u64, num_bits: u32) {
        assert!(num_bits > 0);
        assert!(num_bits % 8 == 0);

        // Switch on the number of bits
        match num_bits {
            8 => self.write_byte(val as u8),
            16 => self.write_bytes(&[(val & 0xff) as u8, ((val >> 8) & 0xff) as u8]),
            32 => self.write_bytes(&[
                (val & 0xff) as u8,
                ((val >> 8) & 0xff) as u8,
                ((val >> 16) & 0xff) as u8,
                ((val >> 24) & 0xff) as u8,
            ]),
            _ => {
                let mut cur = val;

                // Write out the bytes
                for _byte in 0..(num_bits / 8) {
                    self.write_byte((cur & 0xff) as u8);
                    cur >>= 8;
                }
            }
        }
    }

    // Add a label reference at the current write position
    pub fn label_ref(&mut self, _label_idx: usize, _num_bytes: usize, _encode: fn(&mut CodeBlock, i64, i64)) {
        // TODO: copy labels

        //assert!(label_idx < self.label_addrs.len());

        //// Keep track of the reference
        //self.label_refs.push(LabelRef { pos: self.write_pos, label_idx, num_bytes, encode });

        //// Move past however many bytes the instruction takes up
        //if self.has_capacity(num_bytes) {
        //    self.write_pos += num_bytes;
        //} else {
        //    self.dropped_bytes = true; // retry emitting the Insn after next_page
        //}
    }
}

impl crate::virtualmem::CodePtrBase for CodeBlock {
    fn base_ptr(&self) -> std::ptr::NonNull<u8> {
        self.mem_block.borrow().base_ptr()
    }
}

/// Global state needed for code generation
pub struct ZJITState {
    /// Inline code block (fast path)
    code_block: CodeBlock,

    /// ZJIT command-line options
    options: Options,
}

/// Private singleton instance of the codegen globals
static mut ZJIT_STATE: Option<ZJITState> = None;

impl ZJITState {
    /// Initialize the ZJIT globals, given options allocated by rb_zjit_init_options()
    pub fn init(options: *const u8) {
        #[cfg(not(test))]
        let cb = {
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

        let options = unsafe { Box::from_raw(options as *mut Options) };
        #[cfg(not(test))] // TODO: can we get rid of this #[cfg]?
        {
            let zjit_state = ZJITState {
                code_block: cb,
                options: *options,
            };

            // Initialize the codegen globals instance
            unsafe { ZJIT_STATE = Some(zjit_state); }
        }
        mem::drop(options);
    }

    /// Get a mutable reference to the codegen globals instance
    fn get_instance() -> &'static mut ZJITState {
        unsafe { ZJIT_STATE.as_mut().unwrap() }
    }

    /// Get a mutable reference to the inline code block
    pub fn get_code_block() -> &'static mut CodeBlock {
        &mut ZJITState::get_instance().code_block
    }

    // Get a mutable reference to the options
    pub fn get_options() -> &'static mut Options {
        &mut ZJITState::get_instance().options
    }
}
