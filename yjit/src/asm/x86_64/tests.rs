#![cfg(test)]

use crate::asm::x86_64::*;

/// Check that the bytes for an instruction sequence match a hex string
fn check_bytes<R>(bytes: &str, run: R) where R: FnOnce(&mut super::CodeBlock) {
    let mut cb = super::CodeBlock::new_dummy(4096);
    run(&mut cb);
    assert_eq!(format!("{:x}", cb), bytes);
}

#[test]
fn test_add() {
    check_bytes("80c103", |cb| add(cb, CL, imm_opnd(3)));
    check_bytes("00d9", |cb| add(cb, CL, BL));
    check_bytes("4000e1", |cb| add(cb, CL, SPL));
    check_bytes("6601d9", |cb| add(cb, CX, BX));
    check_bytes("4801d8", |cb| add(cb, RAX, RBX));
    check_bytes("01d1", |cb| add(cb, ECX, EDX));
    check_bytes("4c01f2", |cb| add(cb, RDX, R14));
    check_bytes("480110", |cb| add(cb, mem_opnd(64, RAX, 0), RDX));
    check_bytes("480310", |cb| add(cb, RDX, mem_opnd(64, RAX, 0)));
    check_bytes("48035008", |cb| add(cb, RDX, mem_opnd(64, RAX, 8)));
    check_bytes("480390ff000000", |cb| add(cb, RDX, mem_opnd(64, RAX, 255)));
    check_bytes("4881407fff000000", |cb| add(cb, mem_opnd(64, RAX, 127), imm_opnd(255)));
    check_bytes("0110", |cb| add(cb, mem_opnd(32, RAX, 0), EDX));
    check_bytes("4883c408", |cb| add(cb, RSP, imm_opnd(8)));
    check_bytes("83c108", |cb| add(cb, ECX, imm_opnd(8)));
    check_bytes("81c1ff000000", |cb| add(cb, ECX, imm_opnd(255)));
}

#[test]
fn test_add_unsigned() {
    // ADD r/m8, imm8
    check_bytes("4180c001", |cb| add(cb, R8B, uimm_opnd(1)));
    check_bytes("4180c07f", |cb| add(cb, R8B, imm_opnd(i8::MAX.try_into().unwrap())));

    // ADD r/m16, imm16
    check_bytes("664183c001", |cb| add(cb, R8W, uimm_opnd(1)));
    check_bytes("664181c0ff7f", |cb| add(cb, R8W, uimm_opnd(i16::MAX.try_into().unwrap())));

    // ADD r/m32, imm32
    check_bytes("4183c001", |cb| add(cb, R8D, uimm_opnd(1)));
    check_bytes("4181c0ffffff7f", |cb| add(cb, R8D, uimm_opnd(i32::MAX.try_into().unwrap())));

    // ADD r/m64, imm32
    check_bytes("4983c001", |cb| add(cb, R8, uimm_opnd(1)));
    check_bytes("4981c0ffffff7f", |cb| add(cb, R8, uimm_opnd(i32::MAX.try_into().unwrap())));
}

#[test]
fn test_and() {
    check_bytes("4421e5", |cb| and(cb, EBP, R12D));
    check_bytes("48832008", |cb| and(cb, mem_opnd(64, RAX, 0), imm_opnd(0x08)));
}

#[test]
fn test_call_label() {
    check_bytes("e8fbffffff", |cb| {
        let label_idx = cb.new_label("fn".to_owned());
        call_label(cb, label_idx);
        cb.link_labels();
    });
}

#[test]
fn test_call_ptr() {
    // calling a lower address
    check_bytes("e8fbffffff", |cb| {
        let ptr = cb.get_write_ptr();
        call_ptr(cb, RAX, ptr.raw_ptr(cb));
    });
}

#[test]
fn test_call_reg() {
    check_bytes("ffd0", |cb| call(cb, RAX));
}

#[test]
fn test_call_mem() {
    check_bytes("ff542408", |cb| call(cb, mem_opnd(64, RSP, 8)));
}

#[test]
fn test_cmovcc() {
    check_bytes("0f4ff7", |cb| cmovg(cb, ESI, EDI));
    check_bytes("0f4f750c", |cb| cmovg(cb, ESI, mem_opnd(32, RBP, 12)));
    check_bytes("0f4cc1", |cb| cmovl(cb, EAX, ECX));
    check_bytes("480f4cdd", |cb| cmovl(cb, RBX, RBP));
    check_bytes("0f4e742404", |cb| cmovle(cb, ESI, mem_opnd(32, RSP, 4)));
}

#[test]
fn test_cmp() {
    check_bytes("38d1", |cb| cmp(cb, CL, DL));
    check_bytes("39f9", |cb| cmp(cb, ECX, EDI));
    check_bytes("493b1424", |cb| cmp(cb, RDX, mem_opnd(64, R12, 0)));
    check_bytes("4883f802", |cb| cmp(cb, RAX, imm_opnd(2)));
    check_bytes("81f900000080", |cb| cmp(cb, ECX, uimm_opnd(0x8000_0000)));
}

#[test]
fn test_cqo() {
    check_bytes("4899", |cb| cqo(cb));
}

#[test]
fn test_imul() {
    check_bytes("480fafc3", |cb| imul(cb, RAX, RBX));
    check_bytes("480faf10", |cb| imul(cb, RDX, mem_opnd(64, RAX, 0)));

    // Operands flipped for encoding since multiplication is commutative
    check_bytes("480faf10", |cb| imul(cb, mem_opnd(64, RAX, 0), RDX));
}

#[test]
fn test_jge_label() {
    check_bytes("0f8dfaffffff", |cb| {
        let label_idx = cb.new_label("loop".to_owned());
        jge_label(cb, label_idx);
        cb.link_labels();
    });
}

#[test]
fn test_jmp_label() {
    // Forward jump
    check_bytes("e900000000", |cb| {
        let label_idx = cb.new_label("next".to_owned());
        jmp_label(cb, label_idx);
        cb.write_label(label_idx);
        cb.link_labels();
    });

    // Backwards jump
    check_bytes("e9fbffffff", |cb| {
        let label_idx = cb.new_label("loop".to_owned());
        cb.write_label(label_idx);
        jmp_label(cb, label_idx);
        cb.link_labels();
    });
}

#[test]
fn test_jmp_rm() {
    check_bytes("41ffe4", |cb| jmp_rm(cb, R12));
}

#[test]
fn test_jo_label() {
    check_bytes("0f80faffffff", |cb| {
        let label_idx = cb.new_label("loop".to_owned());
        jo_label(cb, label_idx);
        cb.link_labels();
    });
}

#[test]
fn test_lea() {
    check_bytes("488d5108", |cb| lea(cb, RDX, mem_opnd(64, RCX, 8)));
    check_bytes("488d0500000000", |cb| lea(cb, RAX, mem_opnd(8, RIP, 0)));
    check_bytes("488d0505000000", |cb| lea(cb, RAX, mem_opnd(8, RIP, 5)));
    check_bytes("488d3d05000000", |cb| lea(cb, RDI, mem_opnd(8, RIP, 5)));
}

#[test]
fn test_mov() {
    check_bytes("b807000000", |cb| mov(cb, EAX, imm_opnd(7)));
    check_bytes("b8fdffffff", |cb| mov(cb, EAX, imm_opnd(-3)));
    check_bytes("41bf03000000", |cb| mov(cb, R15, imm_opnd(3)));
    check_bytes("89d8", |cb| mov(cb, EAX, EBX));
    check_bytes("89c8", |cb| mov(cb, EAX, ECX));
    check_bytes("8b9380000000", |cb| mov(cb, EDX, mem_opnd(32, RBX, 128)));
    check_bytes("488b442404", |cb| mov(cb, RAX, mem_opnd(64, RSP, 4)));

    // Test `mov rax, 3` => `mov eax, 3` optimization
    check_bytes("41b834000000", |cb| mov(cb, R8, imm_opnd(0x34)));
    check_bytes("49b80000008000000000", |cb| mov(cb, R8, imm_opnd(0x80000000)));
    check_bytes("49b8ffffffffffffffff", |cb| mov(cb, R8, imm_opnd(-1)));

    check_bytes("b834000000", |cb| mov(cb, RAX, imm_opnd(0x34)));
    check_bytes("48b8020000000000c0ff", |cb| mov(cb, RAX, imm_opnd(-18014398509481982)));
    check_bytes("48b80000008000000000", |cb| mov(cb, RAX, imm_opnd(0x80000000)));
    check_bytes("48b8ccffffffffffffff", |cb| mov(cb, RAX, imm_opnd(-52))); // yasm thinks this could use a dword immediate instead of qword
    check_bytes("48b8ffffffffffffffff", |cb| mov(cb, RAX, imm_opnd(-1))); // yasm thinks this could use a dword immediate instead of qword
    check_bytes("4488c9", |cb| mov(cb, CL, R9B));
    check_bytes("4889c3", |cb| mov(cb, RBX, RAX));
    check_bytes("4889df", |cb| mov(cb, RDI, RBX));
    check_bytes("40b60b", |cb| mov(cb, SIL, imm_opnd(11)));

    check_bytes("c60424fd", |cb| mov(cb, mem_opnd(8, RSP, 0), imm_opnd(-3)));
    check_bytes("48c7470801000000", |cb| mov(cb, mem_opnd(64, RDI, 8), imm_opnd(1)));
    //check_bytes("67c7400411000000", |cb| mov(cb, mem_opnd(32, EAX, 4), imm_opnd(0x34))); // We don't distinguish between EAX and RAX here - that's probably fine?
    check_bytes("c7400411000000", |cb| mov(cb, mem_opnd(32, RAX, 4), imm_opnd(17)));
    check_bytes("41895814", |cb| mov(cb, mem_opnd(32, R8, 20), EBX));
    check_bytes("4d8913", |cb| mov(cb, mem_opnd(64, R11, 0), R10));
    check_bytes("48c742f8f4ffffff", |cb| mov(cb, mem_opnd(64, RDX, -8), imm_opnd(-12)));
}

#[test]
fn test_movabs() {
    check_bytes("49b83400000000000000", |cb| movabs(cb, R8, 0x34));
    check_bytes("49b80000008000000000", |cb| movabs(cb, R8, 0x80000000));
}

#[test]
fn test_mov_unsigned() {
    // MOV AL, imm8
    check_bytes("b001", |cb| mov(cb, AL, uimm_opnd(1)));
    check_bytes("b0ff", |cb| mov(cb, AL, uimm_opnd(u8::MAX.into())));

    // MOV AX, imm16
    check_bytes("66b80100", |cb| mov(cb, AX, uimm_opnd(1)));
    check_bytes("66b8ffff", |cb| mov(cb, AX, uimm_opnd(u16::MAX.into())));

    // MOV EAX, imm32
    check_bytes("b801000000", |cb| mov(cb, EAX, uimm_opnd(1)));
    check_bytes("b8ffffffff", |cb| mov(cb, EAX, uimm_opnd(u32::MAX.into())));
    check_bytes("41b800000000", |cb| mov(cb, R8, uimm_opnd(0)));
    check_bytes("41b8ffffffff", |cb| mov(cb, R8, uimm_opnd(0xFF_FF_FF_FF)));

    // MOV RAX, imm64, will move down into EAX since it fits into 32 bits
    check_bytes("b801000000", |cb| mov(cb, RAX, uimm_opnd(1)));
    check_bytes("b8ffffffff", |cb| mov(cb, RAX, uimm_opnd(u32::MAX.into())));

    // MOV RAX, imm64, will not move down into EAX since it does not fit into 32 bits
    check_bytes("48b80000000001000000", |cb| mov(cb, RAX, uimm_opnd(u32::MAX as u64 + 1)));
    check_bytes("48b8ffffffffffffffff", |cb| mov(cb, RAX, uimm_opnd(u64::MAX)));
    check_bytes("49b8ffffffffffffffff", |cb| mov(cb, R8, uimm_opnd(u64::MAX)));

    // MOV r8, imm8
    check_bytes("41b001", |cb| mov(cb, R8B, uimm_opnd(1)));
    check_bytes("41b0ff", |cb| mov(cb, R8B, uimm_opnd(u8::MAX.into())));

    // MOV r16, imm16
    check_bytes("6641b80100", |cb| mov(cb, R8W, uimm_opnd(1)));
    check_bytes("6641b8ffff", |cb| mov(cb, R8W, uimm_opnd(u16::MAX.into())));

    // MOV r32, imm32
    check_bytes("41b801000000", |cb| mov(cb, R8D, uimm_opnd(1)));
    check_bytes("41b8ffffffff", |cb| mov(cb, R8D, uimm_opnd(u32::MAX.into())));

    // MOV r64, imm64, will move down into 32 bit since it fits into 32 bits
    check_bytes("41b801000000", |cb| mov(cb, R8, uimm_opnd(1)));

    // MOV r64, imm64, will not move down into 32 bit since it does not fit into 32 bits
    check_bytes("49b8ffffffffffffffff", |cb| mov(cb, R8, uimm_opnd(u64::MAX)));
}

#[test]
fn test_mov_iprel() {
    check_bytes("8b0500000000", |cb| mov(cb, EAX, mem_opnd(32, RIP, 0)));
    check_bytes("8b0505000000", |cb| mov(cb, EAX, mem_opnd(32, RIP, 5)));

    check_bytes("488b0500000000", |cb| mov(cb, RAX, mem_opnd(64, RIP, 0)));
    check_bytes("488b0505000000", |cb| mov(cb, RAX, mem_opnd(64, RIP, 5)));
    check_bytes("488b3d05000000", |cb| mov(cb, RDI, mem_opnd(64, RIP, 5)));
}

#[test]
fn test_movsx() {
    check_bytes("660fbec0", |cb| movsx(cb, AX, AL));
    check_bytes("0fbed0", |cb| movsx(cb, EDX, AL));
    check_bytes("480fbec3", |cb| movsx(cb, RAX, BL));
    check_bytes("0fbfc8", |cb| movsx(cb, ECX, AX));
    check_bytes("4c0fbed9", |cb| movsx(cb, R11, CL));
    check_bytes("4c6354240c", |cb| movsx(cb, R10, mem_opnd(32, RSP, 12)));
    check_bytes("480fbe0424", |cb| movsx(cb, RAX, mem_opnd(8, RSP, 0)));
    check_bytes("490fbf5504", |cb| movsx(cb, RDX, mem_opnd(16, R13, 4)));
}

#[test]
fn test_nop() {
    check_bytes("90", |cb| nop(cb, 1));
    check_bytes("6690", |cb| nop(cb, 2));
    check_bytes("0f1f00", |cb| nop(cb, 3));
    check_bytes("0f1f4000", |cb| nop(cb, 4));
    check_bytes("0f1f440000", |cb| nop(cb, 5));
    check_bytes("660f1f440000", |cb| nop(cb, 6));
    check_bytes("0f1f8000000000", |cb| nop(cb, 7));
    check_bytes("0f1f840000000000", |cb| nop(cb, 8));
    check_bytes("660f1f840000000000", |cb| nop(cb, 9));
    check_bytes("660f1f84000000000090", |cb| nop(cb, 10));
    check_bytes("660f1f8400000000006690", |cb| nop(cb, 11));
    check_bytes("660f1f8400000000000f1f00", |cb| nop(cb, 12));
}

#[test]
fn test_not() {
    check_bytes("66f7d0", |cb| not(cb, AX));
    check_bytes("f7d0", |cb| not(cb, EAX));
    check_bytes("49f71424", |cb| not(cb, mem_opnd(64, R12, 0)));
    check_bytes("f794242d010000", |cb| not(cb, mem_opnd(32, RSP, 301)));
    check_bytes("f71424", |cb| not(cb, mem_opnd(32, RSP, 0)));
    check_bytes("f7542403", |cb| not(cb, mem_opnd(32, RSP, 3)));
    check_bytes("f75500", |cb| not(cb, mem_opnd(32, RBP, 0)));
    check_bytes("f7550d", |cb| not(cb, mem_opnd(32, RBP, 13)));
    check_bytes("48f7d0", |cb| not(cb, RAX));
    check_bytes("49f7d3", |cb| not(cb, R11));
    check_bytes("f710", |cb| not(cb, mem_opnd(32, RAX, 0)));
    check_bytes("f716", |cb| not(cb, mem_opnd(32, RSI, 0)));
    check_bytes("f717", |cb| not(cb, mem_opnd(32, RDI, 0)));
    check_bytes("f75237", |cb| not(cb, mem_opnd(32, RDX, 55)));
    check_bytes("f79239050000", |cb| not(cb, mem_opnd(32, RDX, 1337)));
    check_bytes("f752c9", |cb| not(cb, mem_opnd(32, RDX, -55)));
    check_bytes("f792d5fdffff", |cb| not(cb, mem_opnd(32, RDX, -555)));
}

#[test]
fn test_or() {
    check_bytes("09f2", |cb| or(cb, EDX, ESI));
}

#[test]
fn test_pop() {
    check_bytes("58", |cb| pop(cb, RAX));
    check_bytes("5b", |cb| pop(cb, RBX));
    check_bytes("5c", |cb| pop(cb, RSP));
    check_bytes("5d", |cb| pop(cb, RBP));
    check_bytes("415c", |cb| pop(cb, R12));
    check_bytes("8f00", |cb| pop(cb, mem_opnd(64, RAX, 0)));
    check_bytes("418f00", |cb| pop(cb, mem_opnd(64, R8, 0)));
    check_bytes("418f4003", |cb| pop(cb, mem_opnd(64, R8, 3)));
    check_bytes("8f44c803", |cb| pop(cb, mem_opnd_sib(64, RAX, RCX, 8, 3)));
    check_bytes("418f44c803", |cb| pop(cb, mem_opnd_sib(64, R8, RCX, 8, 3)));
}

#[test]
fn test_push() {
    check_bytes("50", |cb| push(cb, RAX));
    check_bytes("53", |cb| push(cb, RBX));
    check_bytes("4154", |cb| push(cb, R12));
    check_bytes("ff30", |cb| push(cb, mem_opnd(64, RAX, 0)));
    check_bytes("41ff30", |cb| push(cb, mem_opnd(64, R8, 0)));
    check_bytes("41ff7003", |cb| push(cb, mem_opnd(64, R8, 3)));
    check_bytes("ff74c803", |cb| push(cb, mem_opnd_sib(64, RAX, RCX, 8, 3)));
    check_bytes("41ff74c803", |cb| push(cb, mem_opnd_sib(64, R8, RCX, 8, 3)));
}

#[test]
fn test_ret() {
    check_bytes("c3", |cb| ret(cb));
}

#[test]
fn test_sal() {
    check_bytes("66d1e1", |cb| sal(cb, CX, uimm_opnd(1)));
    check_bytes("d1e1", |cb| sal(cb, ECX, uimm_opnd(1)));
    check_bytes("c1e505", |cb| sal(cb, EBP, uimm_opnd(5)));
    check_bytes("d1642444", |cb| sal(cb, mem_opnd(32, RSP, 68), uimm_opnd(1)));
    check_bytes("48d3e1", |cb| sal(cb, RCX, CL));
}

#[test]
fn test_sar() {
    check_bytes("d1fa", |cb| sar(cb, EDX, uimm_opnd(1)));
}

#[test]
fn test_shr() {
    check_bytes("49c1ee07", |cb| shr(cb, R14, uimm_opnd(7)));
}

#[test]
fn test_sub() {
    check_bytes("83e801", |cb| sub(cb, EAX, imm_opnd(1)));
    check_bytes("4883e802", |cb| sub(cb, RAX, imm_opnd(2)));
}

#[test]
#[should_panic]
fn test_sub_uimm_too_large() {
    // This immediate becomes a different value after
    // sign extension, so not safe to encode.
    check_bytes("ff", |cb| sub(cb, RCX, uimm_opnd(0x8000_0000)));
}

#[test]
fn test_test() {
    check_bytes("84c0", |cb| test(cb, AL, AL));
    check_bytes("6685c0", |cb| test(cb, AX, AX));
    check_bytes("f6c108", |cb| test(cb, CL, uimm_opnd(8)));
    check_bytes("f6c207", |cb| test(cb, DL, uimm_opnd(7)));
    check_bytes("f6c108", |cb| test(cb, RCX, uimm_opnd(8)));
    check_bytes("f6420808", |cb| test(cb, mem_opnd(8, RDX, 8), uimm_opnd(8)));
    check_bytes("f64208ff", |cb| test(cb, mem_opnd(8, RDX, 8), uimm_opnd(255)));
    check_bytes("66f7c2ffff", |cb| test(cb, DX, uimm_opnd(0xffff)));
    check_bytes("66f74208ffff", |cb| test(cb, mem_opnd(16, RDX, 8), uimm_opnd(0xffff)));
    check_bytes("f60601", |cb| test(cb, mem_opnd(8, RSI, 0), uimm_opnd(1)));
    check_bytes("f6461001", |cb| test(cb, mem_opnd(8, RSI, 16), uimm_opnd(1)));
    check_bytes("f646f001", |cb| test(cb, mem_opnd(8, RSI, -16), uimm_opnd(1)));
    check_bytes("854640", |cb| test(cb, mem_opnd(32, RSI, 64), EAX));
    check_bytes("4885472a", |cb| test(cb, mem_opnd(64, RDI, 42), RAX));
    check_bytes("4885c0", |cb| test(cb, RAX, RAX));
    check_bytes("4885f0", |cb| test(cb, RAX, RSI));
    check_bytes("48f74640f7ffffff", |cb| test(cb, mem_opnd(64, RSI, 64), imm_opnd(!0x08)));
    check_bytes("48f7464008000000", |cb| test(cb, mem_opnd(64, RSI, 64), imm_opnd(0x08)));
    check_bytes("48f7c108000000", |cb| test(cb, RCX, imm_opnd(0x08)));
    //check_bytes("48a9f7ffff0f", |cb| test(cb, RAX, imm_opnd(0x0FFFFFF7)));
}

#[test]
fn test_xchg() {
    check_bytes("4891", |cb| xchg(cb, RAX, RCX));
    check_bytes("4995", |cb| xchg(cb, RAX, R13));
    check_bytes("4887d9", |cb| xchg(cb, RCX, RBX));
    check_bytes("4d87f9", |cb| xchg(cb, R9, R15));
}

#[test]
fn test_xor() {
    check_bytes("31c0", |cb| xor(cb, EAX, EAX));
}

#[test]
#[cfg(feature = "disasm")]
fn basic_capstone_usage() -> std::result::Result<(), capstone::Error> {
    // Test drive Capstone with simple input
    use capstone::prelude::*;
    let cs = Capstone::new()
        .x86()
        .mode(arch::x86::ArchMode::Mode64)
        .syntax(arch::x86::ArchSyntax::Intel)
        .build()?;

    let insns = cs.disasm_all(&[0xCC], 0x1000)?;

    match insns.as_ref() {
        [insn] => {
            assert_eq!(Some("int3"), insn.mnemonic());
            Ok(())
        }
        _ => Err(capstone::Error::CustomError(
            "expected to disassemble to int3",
        )),
    }
}

#[test]
#[cfg(feature = "disasm")]
fn block_comments() {
    let mut cb = super::CodeBlock::new_dummy(4096);

    let first_write_ptr = cb.get_write_ptr().raw_addr(&cb);
    cb.add_comment("Beginning");
    xor(&mut cb, EAX, EAX); // 2 bytes long
    let second_write_ptr = cb.get_write_ptr().raw_addr(&cb);
    cb.add_comment("Two bytes in");
    cb.add_comment("Still two bytes in");
    cb.add_comment("Still two bytes in"); // Duplicate, should be ignored
    test(&mut cb, mem_opnd(64, RSI, 64), imm_opnd(!0x08)); // 8 bytes long
    let third_write_ptr = cb.get_write_ptr().raw_addr(&cb);
    cb.add_comment("Ten bytes in");

    assert_eq!(&vec!( "Beginning".to_string() ), cb.comments_at(first_write_ptr).unwrap());
    assert_eq!(&vec!( "Two bytes in".to_string(), "Still two bytes in".to_string() ), cb.comments_at(second_write_ptr).unwrap());
    assert_eq!(&vec!( "Ten bytes in".to_string() ), cb.comments_at(third_write_ptr).unwrap());
}
