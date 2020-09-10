#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "ujit_asm.h"

// Check that the code block contains the given sequence of bytes
void check_bytes(codeblock_t* cb, const char* bytes)
{
    printf("checking encoding: %s\n", bytes);

    size_t len = strlen(bytes);
    assert (len % 2 == 0);
    size_t num_bytes = len / 2;

    if (cb->write_pos != num_bytes)
    {
        fprintf(stderr, "incorrect encoding length %ld, expected %ld\n", cb->write_pos, num_bytes);
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
            fprintf(stderr, "incorrect encoding at position %ld, got %X, expected %X\n",
                i,
                (int)cb_byte,
                (int)byte
            );
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
    cb_write_prologue(cb);
    cb_write_epilogue(cb);

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

    // call
    /*
    test(
        delegate void (CodeBlock cb) { auto l = cb.label("foo"); cb.instr(CALL, l); },
        "E8FBFFFFFF"
    );
    */
    cb_set_pos(cb, 0); call(cb, RAX); check_bytes(cb, "FFD0");
    cb_set_pos(cb, 0); call(cb, mem_opnd(64, RSP, 8)); check_bytes(cb, "FF542408");

    /*
    // jcc
    test(
        delegate void (CodeBlock cb) { auto l = cb.label(Label.LOOP); cb.jge(l); },
        "0F8DFAFFFFFF"
    );
    test(
        delegate void (CodeBlock cb) { cb.label(Label.LOOP); cb.jo(Label.LOOP); },
        "0F80FAFFFFFF"
    );
    */

    // jmp
    cb_set_pos(cb, 0); jmp(cb, R12); check_bytes(cb, "41FFE4");

    // lea
    //cb_set_pos(cb, 0); lea(cb, EBX, mem_opnd(32, RSP, 4)); check_bytes(cb, "8D5C2404");
    cb_set_pos(cb, 0); lea(cb, RDX, mem_opnd(64, RCX, 8)); check_bytes(cb, "488D5108");

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

    // nop
    cb_set_pos(cb, 0); nop(cb, 1); check_bytes(cb, "90");

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

    printf("Assembler tests done\n");
}

int main(int argc, char** argv)
{
    run_tests();

    return 0;
}
