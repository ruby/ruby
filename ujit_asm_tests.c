#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "ujit_asm.h"

// Print the bytes in a code block
void print_bytes(codeblock_t* cb)
{
    for (size_t i = 0; i < cb->write_pos; ++i)
    {
        printf("%02X", (int)cb->mem_block[i]);
    }

    printf("\n");
}

// Check that the code block contains the given sequence of bytes
void check_bytes(codeblock_t* cb, const char* bytes)
{
    printf("checking encoding: %s\n", bytes);

    size_t len = strlen(bytes);
    assert (len % 2 == 0);
    size_t num_bytes = len / 2;

    if (cb->write_pos != num_bytes)
    {
        fprintf(stderr, "incorrect encoding length, expected %ld, got %ld\n",
            num_bytes,
            cb->write_pos
        );
        printf("%s\n", bytes);
        print_bytes(cb);
        exit(-1);
    }

    for (size_t i = 0; i < num_bytes; ++i)
    {
        char byte_str[] = {0, 0, 0, 0};
        strncpy(byte_str, bytes + (2 * i), 2);
        char* endptr;
        long int byte = strtol(byte_str, &endptr, 16);

        uint8_t cb_byte = cb->mem_block[i];

        if (cb_byte != byte)
        {
            fprintf(stderr, "incorrect encoding at position %ld, expected %02X, got %02X\n",
                i,
                (int)byte,
                (int)cb_byte
            );
            printf("%s\n", bytes);
            print_bytes(cb);
            exit(-1);
        }
    }
}

void run_tests()
{
    printf("Running assembler tests\n");

    codeblock_t cb_obj;
    codeblock_t* cb = &cb_obj;
    cb_init(cb, 4096);

    // add
    /*
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CL), X86Opnd(3)); },
        "80C103"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CL), X86Opnd(BL)); },
        "00D9"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CL), X86Opnd(SPL)); },
        "4000E1"
    );
    test(
        delegate void (CodeBlock cb) { cb.add(X86Opnd(CX), X86Opnd(BX)); },
        "6601D9"
    );
    */
    cb_set_pos(cb, 0); add(cb, RAX, RBX); check_bytes(cb, "4801D8");
    cb_set_pos(cb, 0); add(cb, ECX, EDX); check_bytes(cb, "01D1");
    cb_set_pos(cb, 0); add(cb, RDX, R14); check_bytes(cb, "4C01F2");
    cb_set_pos(cb, 0); add(cb, mem_opnd(64, RAX, 0), RDX); check_bytes(cb, "480110");
    cb_set_pos(cb, 0); add(cb, RDX, mem_opnd(64, RAX, 0)); check_bytes(cb, "480310");
    cb_set_pos(cb, 0); add(cb, RDX, mem_opnd(64, RAX, 8)); check_bytes(cb, "48035008");
    cb_set_pos(cb, 0); add(cb, RDX, mem_opnd(64, RAX, 255)); check_bytes(cb, "480390FF000000");
    cb_set_pos(cb, 0); add(cb, mem_opnd(64, RAX, 127), imm_opnd(255)); check_bytes(cb, "4881407FFF000000");
    cb_set_pos(cb, 0); add(cb, mem_opnd(32, RAX, 0), EDX); check_bytes(cb, "0110");
    cb_set_pos(cb, 0); add(cb, RSP, imm_opnd(8)); check_bytes(cb, "4883C408");
    cb_set_pos(cb, 0); add(cb, ECX, imm_opnd(8)); check_bytes(cb, "83C108");
    cb_set_pos(cb, 0); add(cb, ECX, imm_opnd(255)); check_bytes(cb, "81C1FF000000");

    // and
    cb_set_pos(cb, 0); and(cb, EBP, R12D); check_bytes(cb, "4421E5");

    // call
    {
        cb_set_pos(cb, 0);
        size_t fn_label = cb_new_label(cb, "foo");
        call_label(cb, fn_label);
        cb_link_labels(cb);
        check_bytes(cb, "E8FBFFFFFF");
    }
    cb_set_pos(cb, 0); call(cb, RAX); check_bytes(cb, "FFD0");
    cb_set_pos(cb, 0); call(cb, mem_opnd(64, RSP, 8)); check_bytes(cb, "FF542408");

    // cmovcc
    cb_set_pos(cb, 0); cmovg(cb, ESI, EDI); check_bytes(cb, "0F4FF7");
    cb_set_pos(cb, 0); cmovg(cb, ESI, mem_opnd(32, RBP, 12)); check_bytes(cb, "0F4F750C");
    cb_set_pos(cb, 0); cmovl(cb, EAX, ECX); check_bytes(cb, "0F4CC1");
    cb_set_pos(cb, 0); cmovl(cb, RBX, RBP); check_bytes(cb, "480F4CDD");
    cb_set_pos(cb, 0); cmovle(cb, ESI, mem_opnd(32, RSP, 4)); check_bytes(cb, "0F4E742404");

    // cmp
    /*
    test(
        delegate void (CodeBlock cb) { cb.cmp(X86Opnd(CL), X86Opnd(DL)); },
        "38D1"
    );
    */
    cb_set_pos(cb, 0); cmp(cb, ECX, EDI); check_bytes(cb, "39F9");
    cb_set_pos(cb, 0); cmp(cb, RDX, mem_opnd(64, R12, 0)); check_bytes(cb, "493B1424");
    cb_set_pos(cb, 0); cmp(cb, RAX, imm_opnd(2)); check_bytes(cb, "4883F802");

    // cqo
    cb_set_pos(cb, 0); cqo(cb); check_bytes(cb, "4899");

    // dec
    /*
    test(
        delegate void (CodeBlock cb) { cb.dec(X86Opnd(CX)); },
        "66FFC9"
    );
    */
    cb_set_pos(cb, 0); dec(cb, EDX); check_bytes(cb, "FFCA");

    // div
    /*
    test(
        delegate void (CodeBlock cb) { cb.div(X86Opnd(EDX)); },
        "F7F2"
    );
    test(
        delegate void (CodeBlock cb) { cb.div(X86Opnd(32, RSP, -12)); },
        "F77424F4"
    );
    */

    // inc
    /*
    test(
        delegate void (CodeBlock cb) { cb.inc(X86Opnd(BL)); },
        "FEC3"
    );
    */
    cb_set_pos(cb, 0); inc(cb, ESP); check_bytes(cb, "FFC4");
    cb_set_pos(cb, 0); inc(cb, mem_opnd(32, RSP, 0)); check_bytes(cb, "FF0424");
    cb_set_pos(cb, 0); inc(cb, mem_opnd(64, RSP, 4)); check_bytes(cb, "48FF442404");

    // jcc
    {
        cb_set_pos(cb, 0);
        size_t loop_label = cb_new_label(cb, "loop");
        jge(cb, loop_label);
        cb_link_labels(cb);
        check_bytes(cb, "0F8DFAFFFFFF");
    }
    {
        cb_set_pos(cb, 0);
        size_t loop_label = cb_new_label(cb, "loop");
        jo(cb, loop_label);
        cb_link_labels(cb);
        check_bytes(cb, "0F80FAFFFFFF");
    }

    // jmp with RM operand
    cb_set_pos(cb, 0); jmp_rm(cb, R12); check_bytes(cb, "41FFE4");

    // lea
    cb_set_pos(cb, 0); lea(cb, RDX, mem_opnd(64, RCX, 8)); check_bytes(cb, "488D5108");
    cb_set_pos(cb, 0); lea(cb, RAX, mem_opnd(8, RIP, 0)); check_bytes(cb, "488D0500000000");
    cb_set_pos(cb, 0); lea(cb, RAX, mem_opnd(8, RIP, 5)); check_bytes(cb, "488D0505000000");
    cb_set_pos(cb, 0); lea(cb, RDI, mem_opnd(8, RIP, 5)); check_bytes(cb, "488D3D05000000");

    // mov
    cb_set_pos(cb, 0); mov(cb, EAX, imm_opnd(7)); check_bytes(cb, "B807000000");
    cb_set_pos(cb, 0); mov(cb, EAX, imm_opnd(-3)); check_bytes(cb, "B8FDFFFFFF");
    cb_set_pos(cb, 0); mov(cb, R15, imm_opnd(3)); check_bytes(cb, "49BF0300000000000000");
    cb_set_pos(cb, 0); mov(cb, EAX, EBX); check_bytes(cb, "89D8");
    cb_set_pos(cb, 0); mov(cb, EAX, ECX); check_bytes(cb, "89C8");
    cb_set_pos(cb, 0); mov(cb, EDX, mem_opnd(32, RBX, 128)); check_bytes(cb, "8B9380000000");
    /*
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(AL), X86Opnd(8, RCX, 0, 1, RDX)); },
        "8A0411"
    );
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(CL), X86Opnd(R9L)); },
        "4488C9"
    );
    */
    cb_set_pos(cb, 0); mov(cb, RBX, RAX); check_bytes(cb, "4889C3");
    cb_set_pos(cb, 0); mov(cb, RDI, RBX); check_bytes(cb, "4889DF");
    /*
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(SIL), X86Opnd(11)); },
        "40B60B"
    );
    */
    cb_set_pos(cb, 0); mov(cb, mem_opnd(8, RSP, 0), imm_opnd(-3)); check_bytes(cb, "C60424FD");
    cb_set_pos(cb, 0); mov(cb, mem_opnd(64, RDI, 8), imm_opnd(1)); check_bytes(cb, "48C7470801000000");

    // movsx
    /*
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(AX), X86Opnd(AL)); },
        "660FBEC0"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(EDX), X86Opnd(AL)); },
        "0FBED0"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(RAX), X86Opnd(BL)); },
        "480FBEC3"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(ECX), X86Opnd(AX)); },
        "0FBFC8"
    );
    test(
        delegate void (CodeBlock cb) { cb.movsx(X86Opnd(R11), X86Opnd(CL)); },
        "4C0FBED9"
    );
    */
    cb_set_pos(cb, 0); movsx(cb, R10, mem_opnd(32, RSP, 12)); check_bytes(cb, "4C6354240C");
    cb_set_pos(cb, 0); movsx(cb, RAX, mem_opnd(8, RSP, 0)); check_bytes(cb, "480FBE0424");

    // neg
    cb_set_pos(cb, 0); neg(cb, RAX); check_bytes(cb, "48F7D8");

    // nop
    cb_set_pos(cb, 0); nop(cb, 1); check_bytes(cb, "90");

    // not
    /*
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(AX)); },
        "66F7D0"
    );
    */
    cb_set_pos(cb, 0); not(cb, EAX); check_bytes(cb, "F7D0");
    cb_set_pos(cb, 0); not(cb, mem_opnd(64, R12, 0)); check_bytes(cb, "49F71424");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RSP, 301)); check_bytes(cb, "F794242D010000");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RSP, 0)); check_bytes(cb, "F71424");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RSP, 3)); check_bytes(cb, "F7542403");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RBP, 0)); check_bytes(cb, "F75500");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RBP, 13)); check_bytes(cb, "F7550D");
    cb_set_pos(cb, 0); not(cb, RAX); check_bytes(cb, "48F7D0");
    cb_set_pos(cb, 0); not(cb, R11); check_bytes(cb, "49F7D3");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RAX, 0)); check_bytes(cb, "F710");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RSI, 0)); check_bytes(cb, "F716");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RDI, 0)); check_bytes(cb, "F717");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RDX, 55)); check_bytes(cb, "F75237");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RDX, 1337)); check_bytes(cb, "F79239050000");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RDX, -55)); check_bytes(cb, "F752C9");
    cb_set_pos(cb, 0); not(cb, mem_opnd(32, RDX, -555)); check_bytes(cb, "F792D5FDFFFF");
    /*
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX, 0, 1, RBX)); },
        "F71418"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX, 0, 1, R12)); },
        "42F71420"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 0, 1, R12)); },
        "43F71427"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 5, 1, R12)); },
        "43F7542705"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 5, 8, R12)); },
        "43F754E705"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R15, 5, 8, R13)); },
        "43F754EF05"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R12, 5, 4, R9)); },
        "43F7548C05"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, R12, 301, 4, R9)); },
        "43F7948C2D010000"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RAX, 5, 4, RDX)); },
        "F7549005"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(64, RAX, 0, 2, RDX)); },
        "48F71450"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP, 0, 1, RBX)); },
        "F7141C"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RSP, 3, 1, RBX)); },
        "F7541C03"
    );
    test(
        delegate void (CodeBlock cb) { cb.not(X86Opnd(32, RBP, 13, 1, RDX)); },
        "F754150D"
    );
    */

    // or
    cb_set_pos(cb, 0); or(cb, EDX, ESI); check_bytes(cb, "09F2");

    // pop
    cb_set_pos(cb, 0); pop(cb, RAX); check_bytes(cb, "58");
    cb_set_pos(cb, 0); pop(cb, RBX); check_bytes(cb, "5B");
    cb_set_pos(cb, 0); pop(cb, RSP); check_bytes(cb, "5C");
    cb_set_pos(cb, 0); pop(cb, RBP); check_bytes(cb, "5D");
    cb_set_pos(cb, 0); pop(cb, R12); check_bytes(cb, "415C");

    // push
    cb_set_pos(cb, 0); push(cb, RAX); check_bytes(cb, "50");
    cb_set_pos(cb, 0); push(cb, RBX); check_bytes(cb, "53");
    cb_set_pos(cb, 0); push(cb, R12); check_bytes(cb, "4154");

    // ret
    cb_set_pos(cb, 0); ret(cb); check_bytes(cb, "C3");

    // sal
    /*
    test(
        delegate void (CodeBlock cb) { cb.sal(X86Opnd(CX), X86Opnd(1)); },
        "66D1E1"
    );
    */
    cb_set_pos(cb, 0); sal(cb, ECX, imm_opnd(1)); check_bytes(cb, "D1E1");
    cb_set_pos(cb, 0); sal(cb, EBP, imm_opnd(5)); check_bytes(cb, "C1E505");
    cb_set_pos(cb, 0); sal(cb, mem_opnd(32, RSP, 68), imm_opnd(1)); check_bytes(cb, "D1642444");

    // sar
    cb_set_pos(cb, 0); sar(cb, EDX, imm_opnd(1)); check_bytes(cb, "D1FA");

    // shr
    cb_set_pos(cb, 0); shr(cb, R14, imm_opnd(7)); check_bytes(cb, "49C1EE07");

    /*
    // sqrtsd
    test(
        delegate void (CodeBlock cb) { cb.sqrtsd(X86Opnd(XMM2), X86Opnd(XMM6)); },
        "F20F51D6"
    );
    */

    // sub
    cb_set_pos(cb, 0); sub(cb, EAX, imm_opnd(1)); check_bytes(cb, "83E801");
    cb_set_pos(cb, 0); sub(cb, RAX, imm_opnd(2)); check_bytes(cb, "4883E802");

    // test
    /*
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, AL, 4); },
        "A804"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, CL, 255); },
        "F6C1FF"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, DL, 7); },
        "F6C207"
    );
    test(
        delegate void (CodeBlock cb) { cb.instr(TEST, DIL, 9); },
        "",
        "40F6C709"
    );
    */

    // xor
    cb_set_pos(cb, 0); xor(cb, EAX, EAX); check_bytes(cb, "31C0");

    printf("Assembler tests done\n");
}

int main(int argc, char** argv)
{
    run_tests();

    return 0;
}
