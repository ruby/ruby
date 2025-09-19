#![cfg(test)]

use insta::assert_snapshot;

use crate::asm::x86_64::*;

/// Check that the bytes for an instruction sequence match a hex string
fn check_bytes<R>(bytes: &str, run: R) where R: FnOnce(&mut super::CodeBlock) {
    let mut cb = super::CodeBlock::new_dummy();
    run(&mut cb);
    assert_eq!(format!("{:x}", cb), bytes);
}

fn compile<R>(run: R) -> CodeBlock where R: FnOnce(&mut super::CodeBlock) {
    let mut cb = super::CodeBlock::new_dummy();
    run(&mut cb);
    cb
}

#[test]
fn test_add() {
    let cb01 = compile(|cb| add(cb, CL, imm_opnd(3)));
    let cb02 = compile(|cb| add(cb, CL, BL));
    let cb03 = compile(|cb| add(cb, CL, SPL));
    let cb04 = compile(|cb| add(cb, CX, BX));
    let cb05 = compile(|cb| add(cb, RAX, RBX));
    let cb06 = compile(|cb| add(cb, ECX, EDX));
    let cb07 = compile(|cb| add(cb, RDX, R14));
    let cb08 = compile(|cb| add(cb, mem_opnd(64, RAX, 0), RDX));
    let cb09 = compile(|cb| add(cb, RDX, mem_opnd(64, RAX, 0)));
    let cb10 = compile(|cb| add(cb, RDX, mem_opnd(64, RAX, 8)));
    let cb11 = compile(|cb| add(cb, RDX, mem_opnd(64, RAX, 255)));
    let cb12 = compile(|cb| add(cb, mem_opnd(64, RAX, 127), imm_opnd(255)));
    let cb13 = compile(|cb| add(cb, mem_opnd(32, RAX, 0), EDX));
    let cb14 = compile(|cb| add(cb, RSP, imm_opnd(8)));
    let cb15 = compile(|cb| add(cb, ECX, imm_opnd(8)));
    let cb16 = compile(|cb| add(cb, ECX, imm_opnd(255)));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add cl, 3"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add cl, bl"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add cl, spl"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add cx, bx"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add rax, rbx"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add ecx, edx"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add rdx, r14"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add qword ptr [rax], rdx"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add rdx, qword ptr [rax]"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add rdx, qword ptr [rax + 8]"));
    cb11.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add rdx, qword ptr [rax + 0xff]"));
    cb12.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add qword ptr [rax + 0x7f], 0xff"));
    cb13.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add dword ptr [rax], edx"));
    cb14.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add rsp, 8"));
    cb15.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add ecx, 8"));
    cb16.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add ecx, 0xff"));

    assert_snapshot!(cb01.hexdump(), @"80c103");
    assert_snapshot!(cb02.hexdump(), @"00d9");
    assert_snapshot!(cb03.hexdump(), @"4000e1");
    assert_snapshot!(cb04.hexdump(), @"6601d9");
    assert_snapshot!(cb05.hexdump(), @"4801d8");
    assert_snapshot!(cb06.hexdump(), @"01d1");
    assert_snapshot!(cb07.hexdump(), @"4c01f2");
    assert_snapshot!(cb08.hexdump(), @"480110");
    assert_snapshot!(cb09.hexdump(), @"480310");
    assert_snapshot!(cb10.hexdump(), @"48035008");
    assert_snapshot!(cb11.hexdump(), @"480390ff000000");
    assert_snapshot!(cb12.hexdump(), @"4881407fff000000");
    assert_snapshot!(cb13.hexdump(), @"0110");
    assert_snapshot!(cb14.hexdump(), @"4883c408");
    assert_snapshot!(cb15.hexdump(), @"83c108");
    assert_snapshot!(cb16.hexdump(), @"81c1ff000000");
}

#[test]
fn test_add_unsigned() {
    // ADD r/m8, imm8
    let cb1 = compile(|cb| add(cb, R8B, uimm_opnd(1)));
    let cb2 = compile(|cb| add(cb, R8B, imm_opnd(i8::MAX.into())));
    // ADD r/m16, imm16
    let cb3 = compile(|cb| add(cb, R8W, uimm_opnd(1)));
    let cb4 = compile(|cb| add(cb, R8W, uimm_opnd(i16::MAX.try_into().unwrap())));
    // ADD r/m32, imm32
    let cb5 = compile(|cb| add(cb, R8D, uimm_opnd(1)));
    let cb6 = compile(|cb| add(cb, R8D, uimm_opnd(i32::MAX.try_into().unwrap())));
    // ADD r/m64, imm32
    let cb7 = compile(|cb| add(cb, R8, uimm_opnd(1)));
    let cb8 = compile(|cb| add(cb, R8, uimm_opnd(i32::MAX.try_into().unwrap())));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8b, 1"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8b, 0x7f"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8w, 1"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8w, 0x7fff"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8d, 1"));
    cb6.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8d, 0x7fffffff"));
    cb7.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8, 1"));
    cb8.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: add r8, 0x7fffffff"));

    assert_snapshot!(cb1.hexdump(), @"4180c001");
    assert_snapshot!(cb2.hexdump(), @"4180c07f");
    assert_snapshot!(cb3.hexdump(), @"664183c001");
    assert_snapshot!(cb4.hexdump(), @"664181c0ff7f");
    assert_snapshot!(cb5.hexdump(), @"4183c001");
    assert_snapshot!(cb6.hexdump(), @"4181c0ffffff7f");
    assert_snapshot!(cb7.hexdump(), @"4983c001");
    assert_snapshot!(cb8.hexdump(), @"4981c0ffffff7f");
}

#[test]
fn test_and() {
    let cb1 = compile(|cb| and(cb, EBP, R12D));
    let cb2 = compile(|cb| and(cb, mem_opnd(64, RAX, 0), imm_opnd(0x08)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: and ebp, r12d"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: and qword ptr [rax], 8"));

    assert_snapshot!(cb1.hexdump(), @"4421e5");
    assert_snapshot!(cb2.hexdump(), @"48832008");
}

#[test]
fn test_call_label() {
    let cb = compile(|cb| {
        let label_idx = cb.new_label("fn".to_owned());
        call_label(cb, label_idx);
        cb.link_labels();
    });
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: call 0"));
    assert_snapshot!(cb.hexdump(), @"e8fbffffff");
}

#[test]
fn test_call_ptr() {
    // calling a lower address
    let cb = compile(|cb| {
        let ptr = cb.get_write_ptr();
        call_ptr(cb, RAX, ptr.raw_ptr(cb));
    });
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: call 0"));
    assert_snapshot!(cb.hexdump(), @"e8fbffffff");
}

#[test]
fn test_call_reg() {
    let cb = compile(|cb| call(cb, RAX));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: call rax"));
    assert_snapshot!(cb.hexdump(), @"ffd0");
}

#[test]
fn test_call_mem() {
    let cb = compile(|cb| call(cb, mem_opnd(64, RSP, 8)));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: call qword ptr [rsp + 8]"));
    assert_snapshot!(cb.hexdump(), @"ff542408");
}

#[test]
fn test_cmovcc() {
    let cb1 = compile(|cb| cmovg(cb, ESI, EDI));
    let cb2 = compile(|cb| cmovg(cb, ESI, mem_opnd(32, RBP, 12)));
    let cb3 = compile(|cb| cmovl(cb, EAX, ECX));
    let cb4 = compile(|cb| cmovl(cb, RBX, RBP));
    let cb5 = compile(|cb| cmovle(cb, ESI, mem_opnd(32, RSP, 4)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmovg esi, edi"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmovg esi, dword ptr [rbp + 0xc]"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmovl eax, ecx"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmovl rbx, rbp"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmovle esi, dword ptr [rsp + 4]"));

    assert_snapshot!(cb1.hexdump(), @"0f4ff7");
    assert_snapshot!(cb2.hexdump(), @"0f4f750c");
    assert_snapshot!(cb3.hexdump(), @"0f4cc1");
    assert_snapshot!(cb4.hexdump(), @"480f4cdd");
    assert_snapshot!(cb5.hexdump(), @"0f4e742404");
}

#[test]
fn test_cmp() {
    let cb1 = compile(|cb| cmp(cb, CL, DL));
    let cb2 = compile(|cb| cmp(cb, ECX, EDI));
    let cb3 = compile(|cb| cmp(cb, RDX, mem_opnd(64, R12, 0)));
    let cb4 = compile(|cb| cmp(cb, RAX, imm_opnd(2)));
    let cb5 = compile(|cb| cmp(cb, ECX, uimm_opnd(0x8000_0000)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmp cl, dl"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmp ecx, edi"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmp rdx, qword ptr [r12]"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmp rax, 2"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cmp ecx, 0x80000000"));

    assert_snapshot!(cb1.hexdump(), @"38d1");
    assert_snapshot!(cb2.hexdump(), @"39f9");
    assert_snapshot!(cb3.hexdump(), @"493b1424");
    assert_snapshot!(cb4.hexdump(), @"4883f802");
    assert_snapshot!(cb5.hexdump(), @"81f900000080");
}

#[test]
fn test_cqo() {
    let cb = compile(cqo);
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: cqo"));
    assert_snapshot!(cb.hexdump(), @"4899");
}

#[test]
fn test_imul() {
    let cb1 = compile(|cb| imul(cb, RAX, RBX));
    let cb2 = compile(|cb| imul(cb, RDX, mem_opnd(64, RAX, 0)));
    // Operands flipped for encoding since multiplication is commutative
    let cb3 = compile(|cb| imul(cb, mem_opnd(64, RAX, 0), RDX));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: imul rax, rbx"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: imul rdx, qword ptr [rax]"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: imul rdx, qword ptr [rax]"));

    assert_snapshot!(cb1.hexdump(), @"480fafc3");
    assert_snapshot!(cb2.hexdump(), @"480faf10");
    assert_snapshot!(cb3.hexdump(), @"480faf10");
}

#[test]
fn test_jge_label() {
    let cb = compile(|cb| {
        let label_idx = cb.new_label("loop".to_owned());
        jge_label(cb, label_idx);
        cb.link_labels();
    });
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: jge 0"));
    assert_snapshot!(cb.hexdump(), @"0f8dfaffffff");
}

#[test]
fn test_jmp_label() {
    // Forward jump
    let cb1 = compile(|cb| {
        let label_idx = cb.new_label("next".to_owned());
        jmp_label(cb, label_idx);
        cb.write_label(label_idx);
        cb.link_labels();
    });
    // Backwards jump
    let cb2 = compile(|cb| {
        let label_idx = cb.new_label("loop".to_owned());
        cb.write_label(label_idx);
        jmp_label(cb, label_idx);
        cb.link_labels();
    });

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: jmp 5"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: jmp 0"));

    assert_snapshot!(cb1.hexdump(), @"e900000000");
    assert_snapshot!(cb2.hexdump(), @"e9fbffffff");
}

#[test]
fn test_jmp_rm() {
    let cb = compile(|cb| jmp_rm(cb, R12));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: jmp r12"));
    assert_snapshot!(cb.hexdump(), @"41ffe4");
}

#[test]
fn test_jo_label() {
    let cb = compile(|cb| {
        let label_idx = cb.new_label("loop".to_owned());
        jo_label(cb, label_idx);
        cb.link_labels();
    });
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: jo 0"));
    assert_snapshot!(cb.hexdump(), @"0f80faffffff");
}

#[test]
fn test_lea() {
    let cb1 = compile(|cb| lea(cb, RDX, mem_opnd(64, RCX, 8)));
    let cb2 = compile(|cb| lea(cb, RAX, mem_opnd(8, RIP, 0)));
    let cb3 = compile(|cb| lea(cb, RAX, mem_opnd(8, RIP, 5)));
    let cb4 = compile(|cb| lea(cb, RDI, mem_opnd(8, RIP, 5)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: lea rdx, [rcx + 8]"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: lea rax, [rip]"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: lea rax, [rip + 5]"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: lea rdi, [rip + 5]"));

    assert_snapshot!(cb1.hexdump(), @"488d5108");
    assert_snapshot!(cb2.hexdump(), @"488d0500000000");
    assert_snapshot!(cb3.hexdump(), @"488d0505000000");
    assert_snapshot!(cb4.hexdump(), @"488d3d05000000");
}

#[test]
fn test_mov() {
    let cb01 = compile(|cb| mov(cb, EAX, imm_opnd(7)));
    let cb02 = compile(|cb| mov(cb, EAX, imm_opnd(-3)));
    let cb03 = compile(|cb| mov(cb, R15, imm_opnd(3)));
    let cb04 = compile(|cb| mov(cb, EAX, EBX));
    let cb05 = compile(|cb| mov(cb, EAX, ECX));
    let cb06 = compile(|cb| mov(cb, EDX, mem_opnd(32, RBX, 128)));
    let cb07 = compile(|cb| mov(cb, RAX, mem_opnd(64, RSP, 4)));
    // Test `mov rax, 3` => `mov eax, 3` optimization
    let cb08 = compile(|cb| mov(cb, R8, imm_opnd(0x34)));
    let cb09 = compile(|cb| mov(cb, R8, imm_opnd(0x80000000)));
    let cb10 = compile(|cb| mov(cb, R8, imm_opnd(-1)));
    let cb11 = compile(|cb| mov(cb, RAX, imm_opnd(0x34)));
    let cb12 = compile(|cb| mov(cb, RAX, imm_opnd(-18014398509481982)));
    let cb13 = compile(|cb| mov(cb, RAX, imm_opnd(0x80000000)));
    let cb14 = compile(|cb| mov(cb, RAX, imm_opnd(-52))); // yasm thinks this could use a dword immediate instead of qword
    let cb15 = compile(|cb| mov(cb, RAX, imm_opnd(-1))); // yasm thinks this could use a dword immediate instead of qword
    let cb16 = compile(|cb| mov(cb, CL, R9B));
    let cb17 = compile(|cb| mov(cb, RBX, RAX));
    let cb18 = compile(|cb| mov(cb, RDI, RBX));
    let cb19 = compile(|cb| mov(cb, SIL, imm_opnd(11)));
    let cb20 = compile(|cb| mov(cb, mem_opnd(8, RSP, 0), imm_opnd(-3)));
    let cb21 = compile(|cb| mov(cb, mem_opnd(64, RDI, 8), imm_opnd(1)));
    //let cb = compile(|cb| mov(cb, mem_opnd(32, EAX, 4), imm_opnd(0x34))); // We don't distinguish between EAX and RAX here - that's probably fine?
    let cb22 = compile(|cb| mov(cb, mem_opnd(32, RAX, 4), imm_opnd(17)));
    let cb23 = compile(|cb| mov(cb, mem_opnd(32, RAX, 4), uimm_opnd(0x80000001)));
    let cb24 = compile(|cb| mov(cb, mem_opnd(32, R8, 20), EBX));
    let cb25 = compile(|cb| mov(cb, mem_opnd(64, R11, 0), R10));
    let cb26 = compile(|cb| mov(cb, mem_opnd(64, RDX, -8), imm_opnd(-12)));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 7"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 0xfffffffd"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r15d, 3"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, ebx"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, ecx"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov edx, dword ptr [rbx + 0x80]"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov rax, qword ptr [rsp + 4]"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8d, 0x34"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs r8, 0x80000000"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs r8, 0xffffffffffffffff"));
    cb11.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 0x34"));
    cb12.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs rax, 0xffc0000000000002"));
    cb13.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs rax, 0x80000000"));
    cb14.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs rax, 0xffffffffffffffcc"));
    cb15.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs rax, 0xffffffffffffffff"));
    cb16.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov cl, r9b"));
    cb17.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov rbx, rax"));
    cb18.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov rdi, rbx"));
    cb19.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov sil, 0xb"));
    cb20.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov byte ptr [rsp], 0xfd"));
    cb21.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov qword ptr [rdi + 8], 1"));
    cb22.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov dword ptr [rax + 4], 0x11"));
    cb23.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov dword ptr [rax + 4], 0x80000001"));
    cb24.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov dword ptr [r8 + 0x14], ebx"));
    cb25.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov qword ptr [r11], r10"));
    cb26.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov qword ptr [rdx - 8], 0xfffffffffffffff4"));

    assert_snapshot!(cb01.hexdump(), @"b807000000");
    assert_snapshot!(cb02.hexdump(), @"b8fdffffff");
    assert_snapshot!(cb03.hexdump(), @"41bf03000000");
    assert_snapshot!(cb04.hexdump(), @"89d8");
    assert_snapshot!(cb05.hexdump(), @"89c8");
    assert_snapshot!(cb06.hexdump(), @"8b9380000000");
    assert_snapshot!(cb07.hexdump(), @"488b442404");
    assert_snapshot!(cb08.hexdump(), @"41b834000000");
    assert_snapshot!(cb09.hexdump(), @"49b80000008000000000");
    assert_snapshot!(cb10.hexdump(), @"49b8ffffffffffffffff");
    assert_snapshot!(cb11.hexdump(), @"b834000000");
    assert_snapshot!(cb12.hexdump(), @"48b8020000000000c0ff");
    assert_snapshot!(cb13.hexdump(), @"48b80000008000000000");
    assert_snapshot!(cb14.hexdump(), @"48b8ccffffffffffffff");
    assert_snapshot!(cb15.hexdump(), @"48b8ffffffffffffffff");
    assert_snapshot!(cb16.hexdump(), @"4488c9");
    assert_snapshot!(cb17.hexdump(), @"4889c3");
    assert_snapshot!(cb18.hexdump(), @"4889df");
    assert_snapshot!(cb19.hexdump(), @"40b60b");
    assert_snapshot!(cb20.hexdump(), @"c60424fd");
    assert_snapshot!(cb21.hexdump(), @"48c7470801000000");
    assert_snapshot!(cb22.hexdump(), @"c7400411000000");
    assert_snapshot!(cb23.hexdump(), @"c7400401000080");
    assert_snapshot!(cb24.hexdump(), @"41895814");
    assert_snapshot!(cb25.hexdump(), @"4d8913");
    assert_snapshot!(cb26.hexdump(), @"48c742f8f4ffffff");
}

#[test]
fn test_movabs() {
    let cb1 = compile(|cb| movabs(cb, R8, 0x34));
    let cb2 = compile(|cb| movabs(cb, R8, 0x80000000));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs r8, 0x34"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs r8, 0x80000000"));

    assert_snapshot!(cb1.hexdump(), @"49b83400000000000000");
    assert_snapshot!(cb2.hexdump(), @"49b80000008000000000");
}

#[test]
fn test_mov_unsigned() {
    // MOV AL, imm8
    let cb01 = compile(|cb| mov(cb, AL, uimm_opnd(1)));
    let cb02 = compile(|cb| mov(cb, AL, uimm_opnd(u8::MAX.into())));
    // MOV AX, imm16
    let cb03 = compile(|cb| mov(cb, AX, uimm_opnd(1)));
    let cb04 = compile(|cb| mov(cb, AX, uimm_opnd(u16::MAX.into())));
    // MOV EAX, imm32
    let cb05 = compile(|cb| mov(cb, EAX, uimm_opnd(1)));
    let cb06 = compile(|cb| mov(cb, EAX, uimm_opnd(u32::MAX.into())));
    let cb07 = compile(|cb| mov(cb, R8, uimm_opnd(0)));
    let cb08 = compile(|cb| mov(cb, R8, uimm_opnd(0xFF_FF_FF_FF)));
    // MOV RAX, imm64, will move down into EAX since it fits into 32 bits
    let cb09 = compile(|cb| mov(cb, RAX, uimm_opnd(1)));
    let cb10 = compile(|cb| mov(cb, RAX, uimm_opnd(u32::MAX.into())));
    // MOV RAX, imm64, will not move down into EAX since it does not fit into 32 bits
    let cb11 = compile(|cb| mov(cb, RAX, uimm_opnd(u32::MAX as u64 + 1)));
    let cb12 = compile(|cb| mov(cb, RAX, uimm_opnd(u64::MAX)));
    let cb13 = compile(|cb| mov(cb, R8, uimm_opnd(u64::MAX)));
    // MOV r8, imm8
    let cb14 = compile(|cb| mov(cb, R8B, uimm_opnd(1)));
    let cb15 = compile(|cb| mov(cb, R8B, uimm_opnd(u8::MAX.into())));
    // MOV r16, imm16
    let cb16 = compile(|cb| mov(cb, R8W, uimm_opnd(1)));
    let cb17 = compile(|cb| mov(cb, R8W, uimm_opnd(u16::MAX.into())));
    // MOV r32, imm32
    let cb18 = compile(|cb| mov(cb, R8D, uimm_opnd(1)));
    let cb19 = compile(|cb| mov(cb, R8D, uimm_opnd(u32::MAX.into())));
    // MOV r64, imm64, will move down into 32 bit since it fits into 32 bits
    let cb20 = compile(|cb| mov(cb, R8, uimm_opnd(1)));
    // MOV r64, imm64, will not move down into 32 bit since it does not fit into 32 bits
    let cb21 = compile(|cb| mov(cb, R8, uimm_opnd(u64::MAX)));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov al, 1"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov al, 0xff"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov ax, 1"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov ax, 0xffff"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 1"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 0xffffffff"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8d, 0"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8d, 0xffffffff"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 1"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, 0xffffffff"));
    cb11.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs rax, 0x100000000"));
    cb12.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs rax, 0xffffffffffffffff"));
    cb13.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs r8, 0xffffffffffffffff"));
    cb14.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8b, 1"));
    cb15.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8b, 0xff"));
    cb16.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8w, 1"));
    cb17.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8w, 0xffff"));
    cb18.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8d, 1"));
    cb19.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8d, 0xffffffff"));
    cb20.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov r8d, 1"));
    cb21.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movabs r8, 0xffffffffffffffff"));

    assert_snapshot!(cb01.hexdump(), @"b001");
    assert_snapshot!(cb02.hexdump(), @"b0ff");
    assert_snapshot!(cb03.hexdump(), @"66b80100");
    assert_snapshot!(cb04.hexdump(), @"66b8ffff");
    assert_snapshot!(cb05.hexdump(), @"b801000000");
    assert_snapshot!(cb06.hexdump(), @"b8ffffffff");
    assert_snapshot!(cb07.hexdump(), @"41b800000000");
    assert_snapshot!(cb08.hexdump(), @"41b8ffffffff");
    assert_snapshot!(cb09.hexdump(), @"b801000000");
    assert_snapshot!(cb10.hexdump(), @"b8ffffffff");
    assert_snapshot!(cb11.hexdump(), @"48b80000000001000000");
    assert_snapshot!(cb12.hexdump(), @"48b8ffffffffffffffff");
    assert_snapshot!(cb13.hexdump(), @"49b8ffffffffffffffff");
    assert_snapshot!(cb14.hexdump(), @"41b001");
    assert_snapshot!(cb15.hexdump(), @"41b0ff");
    assert_snapshot!(cb16.hexdump(), @"6641b80100");
    assert_snapshot!(cb17.hexdump(), @"6641b8ffff");
    assert_snapshot!(cb18.hexdump(), @"41b801000000");
    assert_snapshot!(cb19.hexdump(), @"41b8ffffffff");
    assert_snapshot!(cb20.hexdump(), @"41b801000000");
    assert_snapshot!(cb21.hexdump(), @"49b8ffffffffffffffff");
}

#[test]
fn test_mov_iprel() {
    let cb1 = compile(|cb| mov(cb, EAX, mem_opnd(32, RIP, 0)));
    let cb2 = compile(|cb| mov(cb, EAX, mem_opnd(32, RIP, 5)));
    let cb3 = compile(|cb| mov(cb, RAX, mem_opnd(64, RIP, 0)));
    let cb4 = compile(|cb| mov(cb, RAX, mem_opnd(64, RIP, 5)));
    let cb5 = compile(|cb| mov(cb, RDI, mem_opnd(64, RIP, 5)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, dword ptr [rip]"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov eax, dword ptr [rip + 5]"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov rax, qword ptr [rip]"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov rax, qword ptr [rip + 5]"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: mov rdi, qword ptr [rip + 5]"));

    assert_snapshot!(cb1.hexdump(), @"8b0500000000");
    assert_snapshot!(cb2.hexdump(), @"8b0505000000");
    assert_snapshot!(cb3.hexdump(), @"488b0500000000");
    assert_snapshot!(cb4.hexdump(), @"488b0505000000");
    assert_snapshot!(cb5.hexdump(), @"488b3d05000000");
}

#[test]
fn test_movsx() {
    let cb1 = compile(|cb| movsx(cb, AX, AL));
    let cb2 = compile(|cb| movsx(cb, EDX, AL));
    let cb3 = compile(|cb| movsx(cb, RAX, BL));
    let cb4 = compile(|cb| movsx(cb, ECX, AX));
    let cb5 = compile(|cb| movsx(cb, R11, CL));
    let cb6 = compile(|cb| movsx(cb, R10, mem_opnd(32, RSP, 12)));
    let cb7 = compile(|cb| movsx(cb, RAX, mem_opnd(8, RSP, 0)));
    let cb8 = compile(|cb| movsx(cb, RDX, mem_opnd(16, R13, 4)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx ax, al"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx edx, al"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx rax, bl"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx ecx, ax"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx r11, cl"));
    cb6.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsxd r10, dword ptr [rsp + 0xc]"));
    cb7.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx rax, byte ptr [rsp]"));
    cb8.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: movsx rdx, word ptr [r13 + 4]"));

    assert_snapshot!(cb1.hexdump(), @"660fbec0");
    assert_snapshot!(cb2.hexdump(), @"0fbed0");
    assert_snapshot!(cb3.hexdump(), @"480fbec3");
    assert_snapshot!(cb4.hexdump(), @"0fbfc8");
    assert_snapshot!(cb5.hexdump(), @"4c0fbed9");
    assert_snapshot!(cb6.hexdump(), @"4c6354240c");
    assert_snapshot!(cb7.hexdump(), @"480fbe0424");
    assert_snapshot!(cb8.hexdump(), @"490fbf5504");
}

#[test]
fn test_nop() {
    let cb01 = compile(|cb| nop(cb, 1));
    let cb02 = compile(|cb| nop(cb, 2));
    let cb03 = compile(|cb| nop(cb, 3));
    let cb04 = compile(|cb| nop(cb, 4));
    let cb05 = compile(|cb| nop(cb, 5));
    let cb06 = compile(|cb| nop(cb, 6));
    let cb07 = compile(|cb| nop(cb, 7));
    let cb08 = compile(|cb| nop(cb, 8));
    let cb09 = compile(|cb| nop(cb, 9));
    let cb10 = compile(|cb| nop(cb, 10));
    let cb11 = compile(|cb| nop(cb, 11));
    let cb12 = compile(|cb| nop(cb, 12));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop dword ptr [rax]"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop dword ptr [rax]"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop dword ptr [rax + rax]"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop word ptr [rax + rax]"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop dword ptr [rax]"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop dword ptr [rax + rax]"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: nop word ptr [rax + rax]"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @r"
    0x0: nop word ptr [rax + rax]
    0x9: nop
    "));
    cb11.with_disasm(|disasm| assert_snapshot!(disasm, @r"
    0x0: nop word ptr [rax + rax]
    0x9: nop
    "));
    cb12.with_disasm(|disasm| assert_snapshot!(disasm, @r"
    0x0: nop word ptr [rax + rax]
    0x9: nop dword ptr [rax]
    "));

    assert_snapshot!(cb01.hexdump(), @"90");
    assert_snapshot!(cb02.hexdump(), @"6690");
    assert_snapshot!(cb03.hexdump(), @"0f1f00");
    assert_snapshot!(cb04.hexdump(), @"0f1f4000");
    assert_snapshot!(cb05.hexdump(), @"0f1f440000");
    assert_snapshot!(cb06.hexdump(), @"660f1f440000");
    assert_snapshot!(cb07.hexdump(), @"0f1f8000000000");
    assert_snapshot!(cb08.hexdump(), @"0f1f840000000000");
    assert_snapshot!(cb09.hexdump(), @"660f1f840000000000");
    assert_snapshot!(cb10.hexdump(), @"660f1f84000000000090");
    assert_snapshot!(cb11.hexdump(), @"660f1f8400000000006690");
    assert_snapshot!(cb12.hexdump(), @"660f1f8400000000000f1f00");
}

#[test]
fn test_not() {
    let cb01 = compile(|cb| not(cb, AX));
    let cb02 = compile(|cb| not(cb, EAX));
    let cb03 = compile(|cb| not(cb, mem_opnd(64, R12, 0)));
    let cb04 = compile(|cb| not(cb, mem_opnd(32, RSP, 301)));
    let cb05 = compile(|cb| not(cb, mem_opnd(32, RSP, 0)));
    let cb06 = compile(|cb| not(cb, mem_opnd(32, RSP, 3)));
    let cb07 = compile(|cb| not(cb, mem_opnd(32, RBP, 0)));
    let cb08 = compile(|cb| not(cb, mem_opnd(32, RBP, 13)));
    let cb09 = compile(|cb| not(cb, RAX));
    let cb10 = compile(|cb| not(cb, R11));
    let cb11 = compile(|cb| not(cb, mem_opnd(32, RAX, 0)));
    let cb12 = compile(|cb| not(cb, mem_opnd(32, RSI, 0)));
    let cb13 = compile(|cb| not(cb, mem_opnd(32, RDI, 0)));
    let cb14 = compile(|cb| not(cb, mem_opnd(32, RDX, 55)));
    let cb15 = compile(|cb| not(cb, mem_opnd(32, RDX, 1337)));
    let cb16 = compile(|cb| not(cb, mem_opnd(32, RDX, -55)));
    let cb17 = compile(|cb| not(cb, mem_opnd(32, RDX, -555)));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not ax"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not eax"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not qword ptr [r12]"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rsp + 0x12d]"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rsp]"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rsp + 3]"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rbp]"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rbp + 0xd]"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not rax"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not r11"));
    cb11.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rax]"));
    cb12.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rsi]"));
    cb13.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rdi]"));
    cb14.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rdx + 0x37]"));
    cb15.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rdx + 0x539]"));
    cb16.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rdx - 0x37]"));
    cb17.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: not dword ptr [rdx - 0x22b]"));

    assert_snapshot!(cb01.hexdump(), @"66f7d0");
    assert_snapshot!(cb02.hexdump(), @"f7d0");
    assert_snapshot!(cb03.hexdump(), @"49f71424");
    assert_snapshot!(cb04.hexdump(), @"f794242d010000");
    assert_snapshot!(cb05.hexdump(), @"f71424");
    assert_snapshot!(cb06.hexdump(), @"f7542403");
    assert_snapshot!(cb07.hexdump(), @"f75500");
    assert_snapshot!(cb08.hexdump(), @"f7550d");
    assert_snapshot!(cb09.hexdump(), @"48f7d0");
    assert_snapshot!(cb10.hexdump(), @"49f7d3");
    assert_snapshot!(cb11.hexdump(), @"f710");
    assert_snapshot!(cb12.hexdump(), @"f716");
    assert_snapshot!(cb13.hexdump(), @"f717");
    assert_snapshot!(cb14.hexdump(), @"f75237");
    assert_snapshot!(cb15.hexdump(), @"f79239050000");
    assert_snapshot!(cb16.hexdump(), @"f752c9");
    assert_snapshot!(cb17.hexdump(), @"f792d5fdffff");
}

#[test]
fn test_or() {
    let cb = compile(|cb| or(cb, EDX, ESI));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: or edx, esi"));
    assert_snapshot!(cb.hexdump(), @"09f2");
}

#[test]
fn test_pop() {
    let cb01 = compile(|cb| pop(cb, RAX));
    let cb02 = compile(|cb| pop(cb, RBX));
    let cb03 = compile(|cb| pop(cb, RSP));
    let cb04 = compile(|cb| pop(cb, RBP));
    let cb05 = compile(|cb| pop(cb, R12));
    let cb06 = compile(|cb| pop(cb, mem_opnd(64, RAX, 0)));
    let cb07 = compile(|cb| pop(cb, mem_opnd(64, R8, 0)));
    let cb08 = compile(|cb| pop(cb, mem_opnd(64, R8, 3)));
    let cb09 = compile(|cb| pop(cb, mem_opnd_sib(64, RAX, RCX, 8, 3)));
    let cb10 = compile(|cb| pop(cb, mem_opnd_sib(64, R8, RCX, 8, 3)));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop rax"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop rbx"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop rsp"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop rbp"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop r12"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop qword ptr [rax]"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop qword ptr [r8]"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop qword ptr [r8 + 3]"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop qword ptr [rax + rcx*8 + 3]"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: pop qword ptr [r8 + rcx*8 + 3]"));

    assert_snapshot!(cb01.hexdump(), @"58");
    assert_snapshot!(cb02.hexdump(), @"5b");
    assert_snapshot!(cb03.hexdump(), @"5c");
    assert_snapshot!(cb04.hexdump(), @"5d");
    assert_snapshot!(cb05.hexdump(), @"415c");
    assert_snapshot!(cb06.hexdump(), @"8f00");
    assert_snapshot!(cb07.hexdump(), @"418f00");
    assert_snapshot!(cb08.hexdump(), @"418f4003");
    assert_snapshot!(cb09.hexdump(), @"8f44c803");
    assert_snapshot!(cb10.hexdump(), @"418f44c803");
}

#[test]
fn test_push() {
    let cb1 = compile(|cb| push(cb, RAX));
    let cb2 = compile(|cb| push(cb, RBX));
    let cb3 = compile(|cb| push(cb, R12));
    let cb4 = compile(|cb| push(cb, mem_opnd(64, RAX, 0)));
    let cb5 = compile(|cb| push(cb, mem_opnd(64, R8, 0)));
    let cb6 = compile(|cb| push(cb, mem_opnd(64, R8, 3)));
    let cb7 = compile(|cb| push(cb, mem_opnd_sib(64, RAX, RCX, 8, 3)));
    let cb8 = compile(|cb| push(cb, mem_opnd_sib(64, R8, RCX, 8, 3)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push rax"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push rbx"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push r12"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push qword ptr [rax]"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push qword ptr [r8]"));
    cb6.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push qword ptr [r8 + 3]"));
    cb7.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push qword ptr [rax + rcx*8 + 3]"));
    cb8.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: push qword ptr [r8 + rcx*8 + 3]"));

    assert_snapshot!(cb1.hexdump(), @"50");
    assert_snapshot!(cb2.hexdump(), @"53");
    assert_snapshot!(cb3.hexdump(), @"4154");
    assert_snapshot!(cb4.hexdump(), @"ff30");
    assert_snapshot!(cb5.hexdump(), @"41ff30");
    assert_snapshot!(cb6.hexdump(), @"41ff7003");
    assert_snapshot!(cb7.hexdump(), @"ff74c803");
    assert_snapshot!(cb8.hexdump(), @"41ff74c803");
}

#[test]
fn test_ret() {
    let cb = compile(ret);
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: ret"));
    assert_snapshot!(cb.hexdump(), @"c3");
}

#[test]
fn test_sal() {
    let cb1 = compile(|cb| sal(cb, CX, uimm_opnd(1)));
    let cb2 = compile(|cb| sal(cb, ECX, uimm_opnd(1)));
    let cb3 = compile(|cb| sal(cb, EBP, uimm_opnd(5)));
    let cb4 = compile(|cb| sal(cb, mem_opnd(32, RSP, 68), uimm_opnd(1)));
    let cb5 = compile(|cb| sal(cb, RCX, CL));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: shl cx, 1"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: shl ecx, 1"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: shl ebp, 5"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: shl dword ptr [rsp + 0x44], 1"));
    cb5.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: shl rcx, cl"));

    assert_snapshot!(cb1.hexdump(), @"66d1e1");
    assert_snapshot!(cb2.hexdump(), @"d1e1");
    assert_snapshot!(cb3.hexdump(), @"c1e505");
    assert_snapshot!(cb4.hexdump(), @"d1642444");
    assert_snapshot!(cb5.hexdump(), @"48d3e1");
}

#[test]
fn test_sar() {
    let cb = compile(|cb| sar(cb, EDX, uimm_opnd(1)));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: sar edx, 1"));
    assert_snapshot!(cb.hexdump(), @"d1fa");
}

#[test]
fn test_shr() {
    let cb = compile(|cb| shr(cb, R14, uimm_opnd(7)));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: shr r14, 7"));
    assert_snapshot!(cb.hexdump(), @"49c1ee07");
}

#[test]
fn test_sub() {
    let cb1 = compile(|cb| sub(cb, EAX, imm_opnd(1)));
    let cb2 = compile(|cb| sub(cb, RAX, imm_opnd(2)));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: sub eax, 1"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: sub rax, 2"));

    assert_snapshot!(cb1.hexdump(), @"83e801");
    assert_snapshot!(cb2.hexdump(), @"4883e802");
}

#[test]
#[should_panic]
fn test_sub_uimm_too_large() {
    // This immediate becomes a different value after
    // sign extension, so not safe to encode.
    compile(|cb| sub(cb, RCX, uimm_opnd(0x8000_0000)));
}

#[test]
fn test_test() {
    let cb01 = compile(|cb| test(cb, AL, AL));
    let cb02 = compile(|cb| test(cb, AX, AX));
    let cb03 = compile(|cb| test(cb, CL, uimm_opnd(8)));
    let cb04 = compile(|cb| test(cb, DL, uimm_opnd(7)));
    let cb05 = compile(|cb| test(cb, RCX, uimm_opnd(8)));
    let cb06 = compile(|cb| test(cb, mem_opnd(8, RDX, 8), uimm_opnd(8)));
    let cb07 = compile(|cb| test(cb, mem_opnd(8, RDX, 8), uimm_opnd(255)));
    let cb08 = compile(|cb| test(cb, DX, uimm_opnd(0xffff)));
    let cb09 = compile(|cb| test(cb, mem_opnd(16, RDX, 8), uimm_opnd(0xffff)));
    let cb10 = compile(|cb| test(cb, mem_opnd(8, RSI, 0), uimm_opnd(1)));
    let cb11 = compile(|cb| test(cb, mem_opnd(8, RSI, 16), uimm_opnd(1)));
    let cb12 = compile(|cb| test(cb, mem_opnd(8, RSI, -16), uimm_opnd(1)));
    let cb13 = compile(|cb| test(cb, mem_opnd(32, RSI, 64), EAX));
    let cb14 = compile(|cb| test(cb, mem_opnd(64, RDI, 42), RAX));
    let cb15 = compile(|cb| test(cb, RAX, RAX));
    let cb16 = compile(|cb| test(cb, RAX, RSI));
    let cb17 = compile(|cb| test(cb, mem_opnd(64, RSI, 64), imm_opnd(!0x08)));
    let cb18 = compile(|cb| test(cb, mem_opnd(64, RSI, 64), imm_opnd(0x08)));
    let cb19 = compile(|cb| test(cb, RCX, imm_opnd(0x08)));

    cb01.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test al, al"));
    cb02.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test ax, ax"));
    cb03.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test cl, 8"));
    cb04.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test dl, 7"));
    cb05.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test cl, 8"));
    cb06.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test byte ptr [rdx + 8], 8"));
    cb07.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test byte ptr [rdx + 8], 0xff"));
    cb08.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test dx, 0xffff"));
    cb09.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test word ptr [rdx + 8], 0xffff"));
    cb10.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test byte ptr [rsi], 1"));
    cb11.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test byte ptr [rsi + 0x10], 1"));
    cb12.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test byte ptr [rsi - 0x10], 1"));
    cb13.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test dword ptr [rsi + 0x40], eax"));
    cb14.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test qword ptr [rdi + 0x2a], rax"));
    cb15.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test rax, rax"));
    cb16.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test rax, rsi"));
    cb17.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test qword ptr [rsi + 0x40], -9"));
    cb18.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test qword ptr [rsi + 0x40], 8"));
    cb19.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: test rcx, 8"));

    assert_snapshot!(cb01.hexdump(), @"84c0");
    assert_snapshot!(cb02.hexdump(), @"6685c0");
    assert_snapshot!(cb03.hexdump(), @"f6c108");
    assert_snapshot!(cb04.hexdump(), @"f6c207");
    assert_snapshot!(cb05.hexdump(), @"f6c108");
    assert_snapshot!(cb06.hexdump(), @"f6420808");
    assert_snapshot!(cb07.hexdump(), @"f64208ff");
    assert_snapshot!(cb08.hexdump(), @"66f7c2ffff");
    assert_snapshot!(cb09.hexdump(), @"66f74208ffff");
    assert_snapshot!(cb10.hexdump(), @"f60601");
    assert_snapshot!(cb11.hexdump(), @"f6461001");
    assert_snapshot!(cb12.hexdump(), @"f646f001");
    assert_snapshot!(cb13.hexdump(), @"854640");
    assert_snapshot!(cb14.hexdump(), @"4885472a");
    assert_snapshot!(cb15.hexdump(), @"4885c0");
    assert_snapshot!(cb16.hexdump(), @"4885f0");
    assert_snapshot!(cb17.hexdump(), @"48f74640f7ffffff");
    assert_snapshot!(cb18.hexdump(), @"48f7464008000000");
    assert_snapshot!(cb19.hexdump(), @"48f7c108000000");
}

#[test]
fn test_xchg() {
    let cb1 = compile(|cb| xchg(cb, RAX, RCX));
    let cb2 = compile(|cb| xchg(cb, RAX, R13));
    let cb3 = compile(|cb| xchg(cb, RCX, RBX));
    let cb4 = compile(|cb| xchg(cb, R9, R15));

    cb1.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: xchg rcx, rax"));
    cb2.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: xchg r13, rax"));
    cb3.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: xchg rcx, rbx"));
    cb4.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: xchg r9, r15"));

    assert_snapshot!(cb1.hexdump(), @"4891");
    assert_snapshot!(cb2.hexdump(), @"4995");
    assert_snapshot!(cb3.hexdump(), @"4887d9");
    assert_snapshot!(cb4.hexdump(), @"4d87f9");
}

#[test]
fn test_xor() {
    let cb = compile(|cb| xor(cb, EAX, EAX));
    cb.with_disasm(|disasm| assert_snapshot!(disasm, @"  0x0: xor eax, eax"));
    assert_snapshot!(cb.hexdump(), @"31c0");
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
