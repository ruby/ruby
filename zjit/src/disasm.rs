use crate::asm::CodeBlock;

pub const BOLD_BEGIN: &str = "\x1b[1m";
pub const BOLD_END: &str = "\x1b[22m";

pub fn disasm_addr_range(cb: &CodeBlock, start_addr: usize, end_addr: usize) -> String {
    use std::fmt::Write;

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
                writeln!(&mut out, "  {BOLD_BEGIN}# {comment}{BOLD_END}").unwrap();
            }
        }
        writeln!(&mut out, "  {insn}").unwrap();
    }

    return out;
}
