#![cfg(test)]

use insta::assert_snapshot;

#[cfg(feature = "disasm")]
use crate::disasms;
use crate::{asm::x86_64::*, hexdumps, assert_disasm_snapshot};

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

    assert_disasm_snapshot!(disasms!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16), @r"
    0x0: add cl, 3
    0x0: add cl, bl
    0x0: add cl, spl
    0x0: add cx, bx
    0x0: add rax, rbx
    0x0: add ecx, edx
    0x0: add rdx, r14
    0x0: add qword ptr [rax], rdx
    0x0: add rdx, qword ptr [rax]
    0x0: add rdx, qword ptr [rax + 8]
    0x0: add rdx, qword ptr [rax + 0xff]
    0x0: add qword ptr [rax + 0x7f], 0xff
    0x0: add dword ptr [rax], edx
    0x0: add rsp, 8
    0x0: add ecx, 8
    0x0: add ecx, 0xff
    ");

    assert_snapshot!(hexdumps!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16), @r"
    80c103
    00d9
    4000e1
    6601d9
    4801d8
    01d1
    4c01f2
    480110
    480310
    48035008
    480390ff000000
    4881407fff000000
    0110
    4883c408
    83c108
    81c1ff000000
    ");
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

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8), @r"
    0x0: add r8b, 1
    0x0: add r8b, 0x7f
    0x0: add r8w, 1
    0x0: add r8w, 0x7fff
    0x0: add r8d, 1
    0x0: add r8d, 0x7fffffff
    0x0: add r8, 1
    0x0: add r8, 0x7fffffff
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8), @r"
    4180c001
    4180c07f
    664183c001
    664181c0ff7f
    4183c001
    4181c0ffffff7f
    4983c001
    4981c0ffffff7f
    ");
}

#[test]
fn test_and() {
    let cb1 = compile(|cb| and(cb, EBP, R12D));
    let cb2 = compile(|cb| and(cb, mem_opnd(64, RAX, 0), imm_opnd(0x08)));

    assert_disasm_snapshot!(disasms!(cb1, cb2), @r"
    0x0: and ebp, r12d
    0x0: and qword ptr [rax], 8
    ");

    assert_snapshot!(hexdumps!(cb1, cb2), @r"
    4421e5
    48832008
    ");
}

#[test]
fn test_call_label() {
    let cb = compile(|cb| {
        let label_idx = cb.new_label("fn".to_owned());
        call_label(cb, label_idx);
        cb.link_labels();
    });
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: call 0");
    assert_snapshot!(cb.hexdump(), @"e8fbffffff");
}

#[test]
fn test_call_ptr() {
    // calling a lower address
    let cb = compile(|cb| {
        let ptr = cb.get_write_ptr();
        call_ptr(cb, RAX, ptr.raw_ptr(cb));
    });
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: call 0");
    assert_snapshot!(cb.hexdump(), @"e8fbffffff");
}

#[test]
fn test_call_reg() {
    let cb = compile(|cb| call(cb, RAX));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: call rax");
    assert_snapshot!(cb.hexdump(), @"ffd0");
}

#[test]
fn test_call_mem() {
    let cb = compile(|cb| call(cb, mem_opnd(64, RSP, 8)));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: call qword ptr [rsp + 8]");
    assert_snapshot!(cb.hexdump(), @"ff542408");
}

#[test]
fn test_cmovcc() {
    let cb1 = compile(|cb| cmovg(cb, ESI, EDI));
    let cb2 = compile(|cb| cmovg(cb, ESI, mem_opnd(32, RBP, 12)));
    let cb3 = compile(|cb| cmovl(cb, EAX, ECX));
    let cb4 = compile(|cb| cmovl(cb, RBX, RBP));
    let cb5 = compile(|cb| cmovle(cb, ESI, mem_opnd(32, RSP, 4)));

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5), @r"
    0x0: cmovg esi, edi
    0x0: cmovg esi, dword ptr [rbp + 0xc]
    0x0: cmovl eax, ecx
    0x0: cmovl rbx, rbp
    0x0: cmovle esi, dword ptr [rsp + 4]
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5), @r"
    0f4ff7
    0f4f750c
    0f4cc1
    480f4cdd
    0f4e742404
    ");
}

#[test]
fn test_cmp() {
    let cb1 = compile(|cb| cmp(cb, CL, DL));
    let cb2 = compile(|cb| cmp(cb, ECX, EDI));
    let cb3 = compile(|cb| cmp(cb, RDX, mem_opnd(64, R12, 0)));
    let cb4 = compile(|cb| cmp(cb, RAX, imm_opnd(2)));
    let cb5 = compile(|cb| cmp(cb, ECX, uimm_opnd(0x8000_0000)));

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5), @r"
    0x0: cmp cl, dl
    0x0: cmp ecx, edi
    0x0: cmp rdx, qword ptr [r12]
    0x0: cmp rax, 2
    0x0: cmp ecx, 0x80000000
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5), @r"
    38d1
    39f9
    493b1424
    4883f802
    81f900000080
    ");
}

#[test]
fn test_cqo() {
    let cb = compile(cqo);
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: cqo");
    assert_snapshot!(cb.hexdump(), @"4899");
}

#[test]
fn test_imul() {
    let cb1 = compile(|cb| imul(cb, RAX, RBX));
    let cb2 = compile(|cb| imul(cb, RDX, mem_opnd(64, RAX, 0)));

    assert_disasm_snapshot!(disasms!(cb1, cb2), @r"
    0x0: imul rax, rbx
    0x0: imul rdx, qword ptr [rax]
    ");

    assert_snapshot!(hexdumps!(cb1, cb2), @r"
    480fafc3
    480faf10
    ");
}

#[test]
#[should_panic]
fn test_imul_mem_reg() {
    // imul doesn't have (Mem, Reg) encoding. Since multiplication is communicative, imul() could
    // swap operands. However, x86_scratch_split may need to move the result to the output operand,
    // which can be complicated if the assembler may sometimes change the result operand.
    // So x86_scratch_split should be responsible for that swap, not the assembler.
    compile(|cb| imul(cb, mem_opnd(64, RAX, 0), RDX));
}

#[test]
fn test_jge_label() {
    let cb = compile(|cb| {
        let label_idx = cb.new_label("loop".to_owned());
        jge_label(cb, label_idx);
        cb.link_labels();
    });
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: jge 0");
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

    assert_disasm_snapshot!(disasms!(cb1, cb2), @r"
    0x0: jmp 5
    0x0: jmp 0
    ");

    assert_snapshot!(hexdumps!(cb1, cb2), @r"
    e900000000
    e9fbffffff
    ");
}

#[test]
fn test_jmp_rm() {
    let cb = compile(|cb| jmp_rm(cb, R12));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: jmp r12");
    assert_snapshot!(cb.hexdump(), @"41ffe4");
}

#[test]
fn test_jo_label() {
    let cb = compile(|cb| {
        let label_idx = cb.new_label("loop".to_owned());
        jo_label(cb, label_idx);
        cb.link_labels();
    });

    assert_disasm_snapshot!(cb.disasm(), @"  0x0: jo 0");
    assert_snapshot!(cb.hexdump(), @"0f80faffffff");
}

#[test]
fn test_lea() {
    let cb1 = compile(|cb| lea(cb, RDX, mem_opnd(64, RCX, 8)));
    let cb2 = compile(|cb| lea(cb, RAX, mem_opnd(8, RIP, 0)));
    let cb3 = compile(|cb| lea(cb, RAX, mem_opnd(8, RIP, 5)));
    let cb4 = compile(|cb| lea(cb, RDI, mem_opnd(8, RIP, 5)));

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4), @r"
    0x0: lea rdx, [rcx + 8]
    0x0: lea rax, [rip]
    0x0: lea rax, [rip + 5]
    0x0: lea rdi, [rip + 5]
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4), @r"
    488d5108
    488d0500000000
    488d0505000000
    488d3d05000000
    ");
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

    assert_disasm_snapshot!(disasms!(
        cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13,
        cb14, cb15, cb16, cb17, cb18, cb19, cb20, cb21, cb22, cb23, cb24, cb25, cb26,
    ), @r"
    0x0: mov eax, 7
    0x0: mov eax, 0xfffffffd
    0x0: mov r15d, 3
    0x0: mov eax, ebx
    0x0: mov eax, ecx
    0x0: mov edx, dword ptr [rbx + 0x80]
    0x0: mov rax, qword ptr [rsp + 4]
    0x0: mov r8d, 0x34
    0x0: movabs r8, 0x80000000
    0x0: movabs r8, 0xffffffffffffffff
    0x0: mov eax, 0x34
    0x0: movabs rax, 0xffc0000000000002
    0x0: movabs rax, 0x80000000
    0x0: movabs rax, 0xffffffffffffffcc
    0x0: movabs rax, 0xffffffffffffffff
    0x0: mov cl, r9b
    0x0: mov rbx, rax
    0x0: mov rdi, rbx
    0x0: mov sil, 0xb
    0x0: mov byte ptr [rsp], 0xfd
    0x0: mov qword ptr [rdi + 8], 1
    0x0: mov dword ptr [rax + 4], 0x11
    0x0: mov dword ptr [rax + 4], 0x80000001
    0x0: mov dword ptr [r8 + 0x14], ebx
    0x0: mov qword ptr [r11], r10
    0x0: mov qword ptr [rdx - 8], 0xfffffffffffffff4
    ");

    assert_snapshot!(hexdumps!(
        cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13,
        cb14, cb15, cb16, cb17, cb18, cb19, cb20, cb21, cb22, cb23, cb24, cb25, cb26
    ), @r"
    b807000000
    b8fdffffff
    41bf03000000
    89d8
    89c8
    8b9380000000
    488b442404
    41b834000000
    49b80000008000000000
    49b8ffffffffffffffff
    b834000000
    48b8020000000000c0ff
    48b80000008000000000
    48b8ccffffffffffffff
    48b8ffffffffffffffff
    4488c9
    4889c3
    4889df
    40b60b
    c60424fd
    48c7470801000000
    c7400411000000
    c7400401000080
    41895814
    4d8913
    48c742f8f4ffffff
    ");
}

#[test]
fn test_movabs() {
    let cb1 = compile(|cb| movabs(cb, R8, 0x34));
    let cb2 = compile(|cb| movabs(cb, R8, 0x80000000));

    assert_disasm_snapshot!(disasms!(cb1, cb2), @r"
    0x0: movabs r8, 0x34
    0x0: movabs r8, 0x80000000
    ");

    assert_snapshot!(hexdumps!(cb1, cb2), @r"
    49b83400000000000000
    49b80000008000000000
    ");
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

    assert_disasm_snapshot!(disasms!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16, cb17, cb18, cb19, cb20, cb21), @r"
    0x0: mov al, 1
    0x0: mov al, 0xff
    0x0: mov ax, 1
    0x0: mov ax, 0xffff
    0x0: mov eax, 1
    0x0: mov eax, 0xffffffff
    0x0: mov r8d, 0
    0x0: mov r8d, 0xffffffff
    0x0: mov eax, 1
    0x0: mov eax, 0xffffffff
    0x0: movabs rax, 0x100000000
    0x0: movabs rax, 0xffffffffffffffff
    0x0: movabs r8, 0xffffffffffffffff
    0x0: mov r8b, 1
    0x0: mov r8b, 0xff
    0x0: mov r8w, 1
    0x0: mov r8w, 0xffff
    0x0: mov r8d, 1
    0x0: mov r8d, 0xffffffff
    0x0: mov r8d, 1
    0x0: movabs r8, 0xffffffffffffffff
    ");

    assert_snapshot!(hexdumps!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16, cb17, cb18, cb19, cb20, cb21), @r"
    b001
    b0ff
    66b80100
    66b8ffff
    b801000000
    b8ffffffff
    41b800000000
    41b8ffffffff
    b801000000
    b8ffffffff
    48b80000000001000000
    48b8ffffffffffffffff
    49b8ffffffffffffffff
    41b001
    41b0ff
    6641b80100
    6641b8ffff
    41b801000000
    41b8ffffffff
    41b801000000
    49b8ffffffffffffffff
    ");
}

#[test]
fn test_mov_iprel() {
    let cb1 = compile(|cb| mov(cb, EAX, mem_opnd(32, RIP, 0)));
    let cb2 = compile(|cb| mov(cb, EAX, mem_opnd(32, RIP, 5)));
    let cb3 = compile(|cb| mov(cb, RAX, mem_opnd(64, RIP, 0)));
    let cb4 = compile(|cb| mov(cb, RAX, mem_opnd(64, RIP, 5)));
    let cb5 = compile(|cb| mov(cb, RDI, mem_opnd(64, RIP, 5)));

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5), @r"
    0x0: mov eax, dword ptr [rip]
    0x0: mov eax, dword ptr [rip + 5]
    0x0: mov rax, qword ptr [rip]
    0x0: mov rax, qword ptr [rip + 5]
    0x0: mov rdi, qword ptr [rip + 5]
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5), @r"
    8b0500000000
    8b0505000000
    488b0500000000
    488b0505000000
    488b3d05000000
    ");
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

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8), @r"
    0x0: movsx ax, al
    0x0: movsx edx, al
    0x0: movsx rax, bl
    0x0: movsx ecx, ax
    0x0: movsx r11, cl
    0x0: movsxd r10, dword ptr [rsp + 0xc]
    0x0: movsx rax, byte ptr [rsp]
    0x0: movsx rdx, word ptr [r13 + 4]
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8), @r"
    660fbec0
    0fbed0
    480fbec3
    0fbfc8
    4c0fbed9
    4c6354240c
    480fbe0424
    490fbf5504
    ");
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

    assert_disasm_snapshot!(disasms!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12), @r"
    0x0: nop
    0x0: nop
    0x0: nop dword ptr [rax]
    0x0: nop dword ptr [rax]
    0x0: nop dword ptr [rax + rax]
    0x0: nop word ptr [rax + rax]
    0x0: nop dword ptr [rax]
    0x0: nop dword ptr [rax + rax]
    0x0: nop word ptr [rax + rax]
    0x0: nop word ptr [rax + rax]
    0x9: nop
    0x0: nop word ptr [rax + rax]
    0x9: nop
    0x0: nop word ptr [rax + rax]
    0x9: nop dword ptr [rax]
    ");

    assert_snapshot!(hexdumps!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12), @r"
    90
    6690
    0f1f00
    0f1f4000
    0f1f440000
    660f1f440000
    0f1f8000000000
    0f1f840000000000
    660f1f840000000000
    660f1f84000000000090
    660f1f8400000000006690
    660f1f8400000000000f1f00
    ");
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

    assert_disasm_snapshot!(disasms!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16, cb17), @r"
    0x0: not ax
    0x0: not eax
    0x0: not qword ptr [r12]
    0x0: not dword ptr [rsp + 0x12d]
    0x0: not dword ptr [rsp]
    0x0: not dword ptr [rsp + 3]
    0x0: not dword ptr [rbp]
    0x0: not dword ptr [rbp + 0xd]
    0x0: not rax
    0x0: not r11
    0x0: not dword ptr [rax]
    0x0: not dword ptr [rsi]
    0x0: not dword ptr [rdi]
    0x0: not dword ptr [rdx + 0x37]
    0x0: not dword ptr [rdx + 0x539]
    0x0: not dword ptr [rdx - 0x37]
    0x0: not dword ptr [rdx - 0x22b]
    ");

    assert_snapshot!(hexdumps!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16, cb17), @r"
    66f7d0
    f7d0
    49f71424
    f794242d010000
    f71424
    f7542403
    f75500
    f7550d
    48f7d0
    49f7d3
    f710
    f716
    f717
    f75237
    f79239050000
    f752c9
    f792d5fdffff
    ");
}

#[test]
fn test_or() {
    let cb = compile(|cb| or(cb, EDX, ESI));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: or edx, esi");
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

    assert_disasm_snapshot!(disasms!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10), @r"
    0x0: pop rax
    0x0: pop rbx
    0x0: pop rsp
    0x0: pop rbp
    0x0: pop r12
    0x0: pop qword ptr [rax]
    0x0: pop qword ptr [r8]
    0x0: pop qword ptr [r8 + 3]
    0x0: pop qword ptr [rax + rcx*8 + 3]
    0x0: pop qword ptr [r8 + rcx*8 + 3]
    ");

    assert_snapshot!(hexdumps!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10), @r"
    58
    5b
    5c
    5d
    415c
    8f00
    418f00
    418f4003
    8f44c803
    418f44c803
    ");
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

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8), @r"
    0x0: push rax
    0x0: push rbx
    0x0: push r12
    0x0: push qword ptr [rax]
    0x0: push qword ptr [r8]
    0x0: push qword ptr [r8 + 3]
    0x0: push qword ptr [rax + rcx*8 + 3]
    0x0: push qword ptr [r8 + rcx*8 + 3]
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8), @r"
    50
    53
    4154
    ff30
    41ff30
    41ff7003
    ff74c803
    41ff74c803
    ");
}

#[test]
fn test_ret() {
    let cb = compile(ret);
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: ret");
    assert_snapshot!(cb.hexdump(), @"c3");
}

#[test]
fn test_sal() {
    let cb1 = compile(|cb| sal(cb, CX, uimm_opnd(1)));
    let cb2 = compile(|cb| sal(cb, ECX, uimm_opnd(1)));
    let cb3 = compile(|cb| sal(cb, EBP, uimm_opnd(5)));
    let cb4 = compile(|cb| sal(cb, mem_opnd(32, RSP, 68), uimm_opnd(1)));
    let cb5 = compile(|cb| sal(cb, RCX, CL));

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4, cb5), @r"
    0x0: shl cx, 1
    0x0: shl ecx, 1
    0x0: shl ebp, 5
    0x0: shl dword ptr [rsp + 0x44], 1
    0x0: shl rcx, cl
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4, cb5), @r"
    66d1e1
    d1e1
    c1e505
    d1642444
    48d3e1
    ");
}

#[test]
fn test_sar() {
    let cb = compile(|cb| sar(cb, EDX, uimm_opnd(1)));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: sar edx, 1");
    assert_snapshot!(cb.hexdump(), @"d1fa");
}

#[test]
fn test_shr() {
    let cb = compile(|cb| shr(cb, R14, uimm_opnd(7)));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: shr r14, 7");
    assert_snapshot!(cb.hexdump(), @"49c1ee07");
}

#[test]
fn test_sub() {
    let cb1 = compile(|cb| sub(cb, EAX, imm_opnd(1)));
    let cb2 = compile(|cb| sub(cb, RAX, imm_opnd(2)));

    assert_disasm_snapshot!(disasms!(cb1, cb2), @r"
    0x0: sub eax, 1
    0x0: sub rax, 2
    ");

    assert_snapshot!(hexdumps!(cb1, cb2), @r"
    83e801
    4883e802
    ");
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

    assert_disasm_snapshot!(disasms!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16, cb17, cb18, cb19), @r"
    0x0: test al, al
    0x0: test ax, ax
    0x0: test cl, 8
    0x0: test dl, 7
    0x0: test cl, 8
    0x0: test byte ptr [rdx + 8], 8
    0x0: test byte ptr [rdx + 8], 0xff
    0x0: test dx, 0xffff
    0x0: test word ptr [rdx + 8], 0xffff
    0x0: test byte ptr [rsi], 1
    0x0: test byte ptr [rsi + 0x10], 1
    0x0: test byte ptr [rsi - 0x10], 1
    0x0: test dword ptr [rsi + 0x40], eax
    0x0: test qword ptr [rdi + 0x2a], rax
    0x0: test rax, rax
    0x0: test rax, rsi
    0x0: test qword ptr [rsi + 0x40], -9
    0x0: test qword ptr [rsi + 0x40], 8
    0x0: test rcx, 8
    ");

    assert_snapshot!(hexdumps!(cb01, cb02, cb03, cb04, cb05, cb06, cb07, cb08, cb09, cb10, cb11, cb12, cb13, cb14, cb15, cb16, cb17, cb18, cb19), @r"
    84c0
    6685c0
    f6c108
    f6c207
    f6c108
    f6420808
    f64208ff
    66f7c2ffff
    66f74208ffff
    f60601
    f6461001
    f646f001
    854640
    4885472a
    4885c0
    4885f0
    48f74640f7ffffff
    48f7464008000000
    48f7c108000000
    ");
}

#[test]
fn test_xchg() {
    let cb1 = compile(|cb| xchg(cb, RAX, RCX));
    let cb2 = compile(|cb| xchg(cb, RAX, R13));
    let cb3 = compile(|cb| xchg(cb, RCX, RBX));
    let cb4 = compile(|cb| xchg(cb, R9, R15));

    assert_disasm_snapshot!(disasms!(cb1, cb2, cb3, cb4), @r"
    0x0: xchg rcx, rax
    0x0: xchg r13, rax
    0x0: xchg rcx, rbx
    0x0: xchg r9, r15
    ");

    assert_snapshot!(hexdumps!(cb1, cb2, cb3, cb4), @r"
    4891
    4995
    4887d9
    4d87f9
    ");
}

#[test]
fn test_xor() {
    let cb = compile(|cb| xor(cb, EAX, EAX));
    assert_disasm_snapshot!(cb.disasm(), @"  0x0: xor eax, eax");
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
