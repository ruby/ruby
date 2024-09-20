use crate::core::*;
use crate::cruby::*;
use crate::yjit::yjit_enabled_p;
use crate::asm::CodeBlock;
use crate::codegen::CodePtr;
use crate::options::DumpDisasm;

use std::fmt::Write;

/// Primitive called in yjit.rb
/// Produce a string representing the disassembly for an ISEQ
#[no_mangle]
pub extern "C" fn rb_yjit_disasm_iseq(_ec: EcPtr, _ruby_self: VALUE, iseqw: VALUE) -> VALUE {
    #[cfg(not(feature = "disasm"))]
    {
        let _ = iseqw;
        return Qnil;
    }

    #[cfg(feature = "disasm")]
    {
        if !yjit_enabled_p() {
            return Qnil;
        }

        // Get the iseq pointer from the wrapper
        let iseq = unsafe { rb_iseqw_to_iseq(iseqw) };

        // This will truncate disassembly of methods with 10k+ bytecodes.
        // That's a good thing - this prints to console.
        let out_string = with_vm_lock(src_loc!(), || disasm_iseq_insn_range(iseq, 0, 9999));

        return rust_str_to_ruby(&out_string);
    }
}

/// Only call while holding the VM lock.
#[cfg(feature = "disasm")]
pub fn disasm_iseq_insn_range(iseq: IseqPtr, start_idx: u16, end_idx: u16) -> String {
    let mut out = String::from("");

    // Get a list of block versions generated for this iseq
    let block_list = get_or_create_iseq_block_list(iseq);
    let mut block_list: Vec<&Block> = block_list.into_iter().map(|blockref| {
        // SAFETY: We have the VM lock here and all the blocks on iseqs are valid.
        unsafe { blockref.as_ref() }
    }).collect();

    // Get a list of codeblocks relevant to this iseq
    let global_cb = crate::codegen::CodegenGlobals::get_inline_cb();

    // Sort the blocks by increasing start addresses
    block_list.sort_by_key(|block| block.get_start_addr().as_offset());

    // Compute total code size in bytes for all blocks in the function
    let mut total_code_size = 0;
    for blockref in &block_list {
        total_code_size += blockref.code_size();
    }

    writeln!(out, "NUM BLOCK VERSIONS: {}", block_list.len()).unwrap();
    writeln!(out,  "TOTAL INLINE CODE SIZE: {} bytes", total_code_size).unwrap();

    // For each block, sorted by increasing start address
    for (block_idx, block) in block_list.iter().enumerate() {
        let blockid = block.get_blockid();
        if blockid.idx >= start_idx && blockid.idx < end_idx {
            let end_idx = block.get_end_idx();
            let start_addr = block.get_start_addr();
            let end_addr = block.get_end_addr();
            let code_size = block.code_size();

            // Write some info about the current block
            let blockid_idx = blockid.idx;
            let block_ident = format!(
                "BLOCK {}/{}, ISEQ RANGE [{},{}), {} bytes ",
                block_idx + 1,
                block_list.len(),
                blockid_idx,
                end_idx,
                code_size
            );
            writeln!(out, "== {:=<60}", block_ident).unwrap();

            // Disassemble the instructions
            for (start_addr, end_addr) in global_cb.writable_addrs(start_addr, end_addr) {
                out.push_str(&disasm_addr_range(global_cb, start_addr, end_addr));
                writeln!(out).unwrap();
            }

            // If this is not the last block
            if block_idx < block_list.len() - 1 {
                // Compute the size of the gap between this block and the next
                let next_block = block_list[block_idx + 1];
                let next_start_addr = next_block.get_start_addr();
                let gap_size = next_start_addr.as_offset() - end_addr.as_offset();

                // Log the size of the gap between the blocks if nonzero
                if gap_size > 0 {
                    writeln!(out, "... {} byte gap ...", gap_size).unwrap();
                }
            }
        }
    }

    return out;
}

/// Dump dissassembly for a range in a [CodeBlock]. VM lock required.
pub fn dump_disasm_addr_range(cb: &CodeBlock, start_addr: CodePtr, end_addr: CodePtr, dump_disasm: &DumpDisasm) {
    for (start_addr, end_addr) in cb.writable_addrs(start_addr, end_addr) {
        let disasm = disasm_addr_range(cb, start_addr, end_addr);
        if disasm.len() > 0 {
            match dump_disasm {
                DumpDisasm::Stdout => println!("{disasm}"),
                DumpDisasm::File(fd) => {
                    use std::os::unix::io::{FromRawFd, IntoRawFd};
                    use std::io::Write;

                    // Write with the fd opened during boot
                    let mut file = unsafe { std::fs::File::from_raw_fd(*fd) };
                    file.write_all(disasm.as_bytes()).unwrap();
                    file.into_raw_fd(); // keep the fd open
                }
            };
        }
    }
}

#[cfg(feature = "disasm")]
pub fn disasm_addr_range(cb: &CodeBlock, start_addr: usize, end_addr: usize) -> String {
    let mut out = String::from("");

    // Initialize capstone
    use capstone::prelude::*;

    #[cfg(target_arch = "x86_64")]
    let mut cs = Capstone::new()
        .x86()
        .mode(arch::x86::ArchMode::Mode64)
        .syntax(arch::x86::ArchSyntax::Intel)
        .build()
        .unwrap();

    #[cfg(target_arch = "aarch64")]
    let mut cs = Capstone::new()
        .arm64()
        .mode(arch::arm64::ArchMode::Arm)
        .detail(true)
        .build()
        .unwrap();
    cs.set_skipdata(true).unwrap();

    // Disassemble the instructions
    let code_size = end_addr - start_addr;
    let code_slice = unsafe { std::slice::from_raw_parts(start_addr as _, code_size) };
    // Stabilize output for cargo test
    #[cfg(test)]
    let start_addr = 0;
    let insns = cs.disasm_all(code_slice, start_addr as u64).unwrap();

    // For each instruction in this block
    for insn in insns.as_ref() {
        // Comments for this block
        if let Some(comment_list) = cb.comments_at(insn.address() as usize) {
            for comment in comment_list {
                if cb.outlined {
                    write!(&mut out, "\x1b[34m").unwrap(); // Make outlined code blue
                }
                writeln!(&mut out, "  \x1b[1m# {comment}\x1b[22m").unwrap(); // Make comments bold
            }
        }
        if cb.outlined {
            write!(&mut out, "\x1b[34m").unwrap(); // Make outlined code blue
        }
        writeln!(&mut out, "  {insn}").unwrap();
        if cb.outlined {
            write!(&mut out, "\x1b[0m").unwrap(); // Disable blue
        }
    }

    return out;
}

/// Fallback version without dependency on a disassembler which prints just bytes and comments.
#[cfg(not(feature = "disasm"))]
pub fn disasm_addr_range(cb: &CodeBlock, start_addr: usize, end_addr: usize) -> String {
    let mut out = String::new();
    let mut line_byte_idx = 0;
    const MAX_BYTES_PER_LINE: usize = 16;

    for addr in start_addr..end_addr {
        if let Some(comment_list) = cb.comments_at(addr) {
            // Start a new line if we're in the middle of one
            if line_byte_idx != 0 {
                writeln!(&mut out).unwrap();
                line_byte_idx = 0;
            }
            for comment in comment_list {
                writeln!(&mut out, "  \x1b[1m# {comment}\x1b[22m").unwrap(); // Make comments bold
            }
        }
        if line_byte_idx == 0 {
            write!(&mut out, "  0x{addr:x}: ").unwrap();
        } else {
            write!(&mut out, " ").unwrap();
        }
        let byte = unsafe { (addr as *const u8).read() };
        write!(&mut out, "{byte:02x}").unwrap();
        line_byte_idx += 1;
        if line_byte_idx == MAX_BYTES_PER_LINE - 1 {
            writeln!(&mut out).unwrap();
            line_byte_idx = 0;
        }
    }

    if !out.is_empty() {
        writeln!(&mut out).unwrap();
    }

    out
}

/// Assert that CodeBlock has the code specified with hex. In addition, if tested with
/// `cargo test --all-features`, it also checks it generates the specified disasm.
#[cfg(test)]
macro_rules! assert_disasm {
    ($cb:expr, $hex:expr, $disasm:expr) => {
        #[cfg(feature = "disasm")]
        {
            let disasm = disasm_addr_range(
                &$cb,
                $cb.get_ptr(0).raw_addr(&$cb),
                $cb.get_write_ptr().raw_addr(&$cb),
            );
            assert_eq!(unindent(&disasm, false), unindent(&$disasm, true));
        }
        assert_eq!(format!("{:x}", $cb), $hex);
    };
}
#[cfg(test)]
pub(crate) use assert_disasm;

/// Remove the minimum indent from every line, skipping the first line if `skip_first`.
#[cfg(all(feature = "disasm", test))]
pub fn unindent(string: &str, trim_lines: bool) -> String {
    fn split_lines(string: &str) -> Vec<String> {
        let mut result: Vec<String> = vec![];
        let mut buf: Vec<u8> = vec![];
        for byte in string.as_bytes().iter() {
            buf.push(*byte);
            if *byte == b'\n' {
                result.push(String::from_utf8(buf).unwrap());
                buf = vec![];
            }
        }
        if !buf.is_empty() {
            result.push(String::from_utf8(buf).unwrap());
        }
        result
    }

    // Break up a string into multiple lines
    let mut lines = split_lines(string);
    if trim_lines { // raw string literals come with extra lines
        lines.remove(0);
        lines.remove(lines.len() - 1);
    }

    // Count the minimum number of spaces
    let spaces = lines.iter().filter_map(|line| {
        for (i, ch) in line.as_bytes().iter().enumerate() {
            if *ch != b' ' {
                return Some(i);
            }
        }
        None
    }).min().unwrap_or(0);

    // Join lines, removing spaces
    let mut unindented: Vec<u8> = vec![];
    for line in lines.iter() {
        if line.len() > spaces {
            unindented.extend_from_slice(&line.as_bytes()[spaces..]);
        } else {
            unindented.extend_from_slice(&line.as_bytes());
        }
    }
    String::from_utf8(unindented).unwrap()
}

/// Primitive called in yjit.rb
/// Produce a list of instructions compiled for an isew
#[no_mangle]
pub extern "C" fn rb_yjit_insns_compiled(_ec: EcPtr, _ruby_self: VALUE, iseqw: VALUE) -> VALUE {
    if !yjit_enabled_p() {
        return Qnil;
    }

    // Get the iseq pointer from the wrapper
    let iseq = unsafe { rb_iseqw_to_iseq(iseqw) };

    // Get the list of instructions compiled
    let insn_vec = insns_compiled(iseq);

    unsafe {
        let insn_ary = rb_ary_new_capa((insn_vec.len() * 2) as i64);

        // For each instruction compiled
        for idx in 0..insn_vec.len() {
            let op_name = &insn_vec[idx].0;
            let insn_idx = insn_vec[idx].1;

            let op_sym = rust_str_to_sym(&op_name);

            // Store the instruction index and opcode symbol
            rb_ary_store(
                insn_ary,
                (2 * idx + 0) as i64,
                VALUE::fixnum_from_usize(insn_idx as usize),
            );
            rb_ary_store(insn_ary, (2 * idx + 1) as i64, op_sym);
        }

        insn_ary
    }
}

fn insns_compiled(iseq: IseqPtr) -> Vec<(String, u16)> {
    let mut insn_vec = Vec::new();

    // Get a list of block versions generated for this iseq
    let block_list = get_or_create_iseq_block_list(iseq);

    // For each block associated with this iseq
    for blockref in &block_list {
        // SAFETY: Called as part of a Ruby method, which ensures the graph is
        // well connected for the given iseq.
        let block = unsafe { blockref.as_ref() };
        let start_idx = block.get_blockid().idx;
        let end_idx = block.get_end_idx();
        assert!(u32::from(end_idx) <= unsafe { get_iseq_encoded_size(iseq) });

        // For each YARV instruction in the block
        let mut insn_idx = start_idx;
        while insn_idx < end_idx {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: usize = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();

            // Get the mnemonic for this opcode
            let op_name = insn_name(opcode);

            // Add the instruction to the list
            insn_vec.push((op_name, insn_idx));

            // Move to the next instruction
            insn_idx += insn_len(opcode) as u16;
        }
    }

    return insn_vec;
}
