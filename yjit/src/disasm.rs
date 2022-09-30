use crate::core::*;
use crate::cruby::*;
use crate::yjit::yjit_enabled_p;
use crate::asm::CodeBlock;

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
        // TODO:
        //if unsafe { CLASS_OF(iseqw) != rb_cISeq } {
        //    return Qnil;
        //}

        if !yjit_enabled_p() {
            return Qnil;
        }

        // Get the iseq pointer from the wrapper
        let iseq = unsafe { rb_iseqw_to_iseq(iseqw) };

        // This will truncate disassembly of methods with 10k+ bytecodes.
        // That's a good thing - this prints to console.
        let out_string = disasm_iseq_insn_range(iseq, 0, 9999);

        return rust_str_to_ruby(&out_string);
    }
}

#[cfg(feature = "disasm")]
pub fn disasm_iseq_insn_range(iseq: IseqPtr, start_idx: u32, end_idx: u32) -> String {
    let mut out = String::from("");

    // Get a list of block versions generated for this iseq
    let mut block_list = get_iseq_block_list(iseq);

    // Get a list of codeblocks relevant to this iseq
    let global_cb = crate::codegen::CodegenGlobals::get_inline_cb();

    // Sort the blocks by increasing start addresses
    block_list.sort_by(|a, b| {
        use std::cmp::Ordering;

        // Get the start addresses for each block
        let addr_a = a.borrow().get_start_addr().unwrap().raw_ptr();
        let addr_b = b.borrow().get_start_addr().unwrap().raw_ptr();

        if addr_a < addr_b {
            Ordering::Less
        } else if addr_a == addr_b {
            Ordering::Equal
        } else {
            Ordering::Greater
        }
    });

    // Compute total code size in bytes for all blocks in the function
    let mut total_code_size = 0;
    for blockref in &block_list {
        total_code_size += blockref.borrow().code_size();
    }

    out.push_str(&format!("NUM BLOCK VERSIONS: {}\n", block_list.len()));
    out.push_str(&format!(
        "TOTAL INLINE CODE SIZE: {} bytes\n",
        total_code_size
    ));

    // For each block, sorted by increasing start address
    for block_idx in 0..block_list.len() {
        let block = block_list[block_idx].borrow();
        let blockid = block.get_blockid();
        if blockid.idx >= start_idx && blockid.idx < end_idx {
            let end_idx = block.get_end_idx();
            let start_addr = block.get_start_addr().unwrap().raw_ptr();
            let end_addr = block.get_end_addr().unwrap().raw_ptr();
            let code_size = block.code_size();

            // Write some info about the current block
            let block_ident = format!(
                "BLOCK {}/{}, ISEQ RANGE [{},{}), {} bytes ",
                block_idx + 1,
                block_list.len(),
                blockid.idx,
                end_idx,
                code_size
            );
            out.push_str(&format!("== {:=<60}\n", block_ident));

            // Disassemble the instructions
            out.push_str(&disasm_addr_range(global_cb, start_addr, code_size));

            // If this is not the last block
            if block_idx < block_list.len() - 1 {
                // Compute the size of the gap between this block and the next
                let next_block = block_list[block_idx + 1].borrow();
                let next_start_addr = next_block.get_start_addr().unwrap().raw_ptr();
                let gap_size = (next_start_addr as usize) - (end_addr as usize);

                // Log the size of the gap between the blocks if nonzero
                if gap_size > 0 {
                    out.push_str(&format!("... {} byte gap ...\n", gap_size));
                }
            }
        }
    }

    return out;
}


#[cfg(feature = "disasm")]
pub fn disasm_addr_range(cb: &CodeBlock, start_addr: *const u8, code_size: usize) -> String {
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
    cs.set_skipdata(true);

    // Disassemble the instructions
    let code_slice = unsafe { std::slice::from_raw_parts(start_addr, code_size) };
    let insns = cs.disasm_all(code_slice, start_addr as u64).unwrap();

    // For each instruction in this block
    for insn in insns.as_ref() {
        // Comments for this block
        if let Some(comment_list) = cb.comments_at(insn.address() as usize) {
            for comment in comment_list {
                writeln!(&mut out, "  \x1b[1m# {}\x1b[0m", comment).unwrap();
            }
        }
        writeln!(&mut out, "  {}", insn).unwrap();
    }

    return out;
}

/// Primitive called in yjit.rb
/// Produce a list of instructions compiled for an isew
#[no_mangle]
pub extern "C" fn rb_yjit_insns_compiled(_ec: EcPtr, _ruby_self: VALUE, iseqw: VALUE) -> VALUE {
    {
        // TODO:
        //if unsafe { CLASS_OF(iseqw) != rb_cISeq } {
        //    return Qnil;
        //}

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
}

fn insns_compiled(iseq: IseqPtr) -> Vec<(String, u32)> {
    let mut insn_vec = Vec::new();

    // Get a list of block versions generated for this iseq
    let block_list = get_iseq_block_list(iseq);

    // For each block associated with this iseq
    for blockref in &block_list {
        let block = blockref.borrow();
        let start_idx = block.get_blockid().idx;
        let end_idx = block.get_end_idx();
        assert!(end_idx <= unsafe { get_iseq_encoded_size(iseq) });

        // For each YARV instruction in the block
        let mut insn_idx = start_idx;
        while insn_idx < end_idx {
            // Get the current pc and opcode
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
            // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
            let opcode: usize = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
                .try_into()
                .unwrap();

            // Get the mnemonic for this opcode
            let op_name = insn_name(opcode);

            // Add the instruction to the list
            insn_vec.push((op_name, insn_idx));

            // Move to the next instruction
            insn_idx += insn_len(opcode);
        }
    }

    return insn_vec;
}
