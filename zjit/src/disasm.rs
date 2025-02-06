use std::fmt::Write;

#[cfg(feature = "disasm")]
pub fn disasm_addr_range(start_addr: usize, end_addr: usize) -> String {
    let mut out = String::from("");

    // Initialize capstone
    use capstone::prelude::*;

    // TODO: switch the architecture once we support Arm
    let mut cs = Capstone::new()
        .x86()
        .mode(arch::x86::ArchMode::Mode64)
        .syntax(arch::x86::ArchSyntax::Intel)
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
        // TODO: support comments
        writeln!(&mut out, "  {insn}").unwrap();
    }

    return out;
}
