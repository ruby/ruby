// For MAP_ANONYMOUS on GNU/Linux
#define _GNU_SOURCE 1

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// This test executable doesn't compile with the rest of Ruby
// so we need to define a rb_bug().
_Noreturn
static void rb_bug(const char *message, ...)
{
    va_list args;
    va_start(args, message);
    vfprintf(stderr, message, args);
    va_end(args);
    abort();
}

#include "yjit_asm.c"

// Print the bytes in a code block
void print_bytes(codeblock_t* cb)
{
    for (uint32_t i = 0; i < cb->write_pos; ++i)
    {
        printf("%02X", (int)*cb_get_ptr(cb, i));
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
        fprintf(stderr, "incorrect encoding length, expected %ld, got %d\n",
            num_bytes,
            cb->write_pos
        );
        printf("%s\n", bytes);
        print_bytes(cb);
        exit(-1);
    }

    for (uint32_t i = 0; i < num_bytes; ++i)
    {
        char byte_str[] = {0, 0, 0, 0};
        strncpy(byte_str, bytes + (2 * i), 2);
        char* endptr;
        long int byte = strtol(byte_str, &endptr, 16);

        uint8_t cb_byte = *cb_get_ptr(cb, i);

        if (cb_byte != byte)
        {
            fprintf(stderr, "incorrect encoding at position %d, expected %02X, got %02X\n",
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

void run_assembler_tests(void)
{
    printf("Running assembler tests\n");

    codeblock_t cb_obj;
    codeblock_t* cb = &cb_obj;
    uint8_t* mem_block = alloc_exec_mem(4096);
    cb_init(cb, mem_block, 4096);

    // add
    cb_set_pos(cb, 0); add(cb, CL, imm_opnd(3)); check_bytes(cb, "80C103");
    cb_set_pos(cb, 0); add(cb, CL, BL); check_bytes(cb, "00D9");
    cb_set_pos(cb, 0); add(cb, CL, SPL); check_bytes(cb, "4000E1");
    cb_set_pos(cb, 0); add(cb, CX, BX); check_bytes(cb, "6601D9");
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
    cb_set_pos(cb, 0); and(cb, mem_opnd(64, RAX, 0), imm_opnd(0x08)); check_bytes(cb, "48832008");

    // call
    {
        cb_set_pos(cb, 0);
        uint32_t fn_label = cb_new_label(cb, "foo");
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
    cb_set_pos(cb, 0); cmp(cb, CL, DL); check_bytes(cb, "38D1");
    cb_set_pos(cb, 0); cmp(cb, ECX, EDI); check_bytes(cb, "39F9");
    cb_set_pos(cb, 0); cmp(cb, RDX, mem_opnd(64, R12, 0)); check_bytes(cb, "493B1424");
    cb_set_pos(cb, 0); cmp(cb, RAX, imm_opnd(2)); check_bytes(cb, "4883F802");

    // cqo
    cb_set_pos(cb, 0); cqo(cb); check_bytes(cb, "4899");

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

    // jcc to label
    {
        cb_set_pos(cb, 0);
        uint32_t loop_label = cb_new_label(cb, "loop");
        jge_label(cb, loop_label);
        cb_link_labels(cb);
        check_bytes(cb, "0F8DFAFFFFFF");
    }
    {
        cb_set_pos(cb, 0);
        uint32_t loop_label = cb_new_label(cb, "loop");
        jo_label(cb, loop_label);
        cb_link_labels(cb);
        check_bytes(cb, "0F80FAFFFFFF");
    }

    // jmp to label
    {
        cb_set_pos(cb, 0);
        uint32_t loop_label = cb_new_label(cb, "loop");
        jmp_label(cb, loop_label);
        cb_link_labels(cb);
        check_bytes(cb, "E9FBFFFFFF");
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
    cb_set_pos(cb, 0); mov(cb, R15, imm_opnd(3)); check_bytes(cb, "41BF03000000");
    cb_set_pos(cb, 0); mov(cb, EAX, EBX); check_bytes(cb, "89D8");
    cb_set_pos(cb, 0); mov(cb, EAX, ECX); check_bytes(cb, "89C8");
    cb_set_pos(cb, 0); mov(cb, EDX, mem_opnd(32, RBX, 128)); check_bytes(cb, "8B9380000000");

    // Test `mov rax, 3` => `mov eax, 3` optimization
    cb_set_pos(cb, 0); mov(cb, R8, imm_opnd(0x34)); check_bytes(cb, "41B834000000");
    cb_set_pos(cb, 0); mov(cb, R8, imm_opnd(0x80000000)); check_bytes(cb, "49B80000008000000000");
    cb_set_pos(cb, 0); mov(cb, R8, imm_opnd(-1)); check_bytes(cb, "49B8FFFFFFFFFFFFFFFF");

    cb_set_pos(cb, 0); mov(cb, RAX, imm_opnd(0x34)); check_bytes(cb, "B834000000");
    cb_set_pos(cb, 0); mov(cb, RAX, imm_opnd(0x80000000)); check_bytes(cb, "48B80000008000000000");
    cb_set_pos(cb, 0); mov(cb, RAX, imm_opnd(-52)); check_bytes(cb, "48B8CCFFFFFFFFFFFFFF");
    cb_set_pos(cb, 0); mov(cb, RAX, imm_opnd(-1)); check_bytes(cb, "48B8FFFFFFFFFFFFFFFF");
    /*
    test(
        delegate void (CodeBlock cb) { cb.mov(X86Opnd(AL), X86Opnd(8, RCX, 0, 1, RDX)); },
        "8A0411"
    );
    */
    cb_set_pos(cb, 0); mov(cb, CL, R9B); check_bytes(cb, "4488C9");
    cb_set_pos(cb, 0); mov(cb, RBX, RAX); check_bytes(cb, "4889C3");
    cb_set_pos(cb, 0); mov(cb, RDI, RBX); check_bytes(cb, "4889DF");
    cb_set_pos(cb, 0); mov(cb, SIL, imm_opnd(11)); check_bytes(cb, "40B60B");
    cb_set_pos(cb, 0); mov(cb, mem_opnd(8, RSP, 0), imm_opnd(-3)); check_bytes(cb, "C60424FD");
    cb_set_pos(cb, 0); mov(cb, mem_opnd(64, RDI, 8), imm_opnd(1)); check_bytes(cb, "48C7470801000000");

    // movsx
    cb_set_pos(cb, 0); movsx(cb, AX, AL); check_bytes(cb, "660FBEC0");
    cb_set_pos(cb, 0); movsx(cb, EDX, AL); check_bytes(cb, "0FBED0");
    cb_set_pos(cb, 0); movsx(cb, RAX, BL); check_bytes(cb, "480FBEC3");
    cb_set_pos(cb, 0); movsx(cb, ECX, AX); check_bytes(cb, "0FBFC8");
    cb_set_pos(cb, 0); movsx(cb, R11, CL); check_bytes(cb, "4C0FBED9");
    cb_set_pos(cb, 0); movsx(cb, R10, mem_opnd(32, RSP, 12)); check_bytes(cb, "4C6354240C");
    cb_set_pos(cb, 0); movsx(cb, RAX, mem_opnd(8, RSP, 0)); check_bytes(cb, "480FBE0424");

    // neg
    cb_set_pos(cb, 0); neg(cb, RAX); check_bytes(cb, "48F7D8");

    // nop
    cb_set_pos(cb, 0); nop(cb, 1); check_bytes(cb, "90");

    // not
    cb_set_pos(cb, 0); not(cb, AX); check_bytes(cb, "66F7D0");
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
    cb_set_pos(cb, 0); pop(cb, mem_opnd(64, RAX, 0)); check_bytes(cb, "8F00");
    cb_set_pos(cb, 0); pop(cb, mem_opnd(64, R8, 0)); check_bytes(cb, "418F00");
    cb_set_pos(cb, 0); pop(cb, mem_opnd(64, R8, 3)); check_bytes(cb, "418F4003");
    cb_set_pos(cb, 0); pop(cb, mem_opnd_sib(64, RAX, RCX, 8, 3)); check_bytes(cb, "8F44C803");
    cb_set_pos(cb, 0); pop(cb, mem_opnd_sib(64, R8, RCX, 8, 3)); check_bytes(cb, "418F44C803");

    // push
    cb_set_pos(cb, 0); push(cb, RAX); check_bytes(cb, "50");
    cb_set_pos(cb, 0); push(cb, RBX); check_bytes(cb, "53");
    cb_set_pos(cb, 0); push(cb, R12); check_bytes(cb, "4154");
    cb_set_pos(cb, 0); push(cb, mem_opnd(64, RAX, 0)); check_bytes(cb, "FF30");
    cb_set_pos(cb, 0); push(cb, mem_opnd(64, R8, 0)); check_bytes(cb, "41FF30");
    cb_set_pos(cb, 0); push(cb, mem_opnd(64, R8, 3)); check_bytes(cb, "41FF7003");
    cb_set_pos(cb, 0); push(cb, mem_opnd_sib(64, RAX, RCX, 8, 3)); check_bytes(cb, "FF74C803");
    cb_set_pos(cb, 0); push(cb, mem_opnd_sib(64, R8, RCX, 8, 3)); check_bytes(cb, "41FF74C803");

    // ret
    cb_set_pos(cb, 0); ret(cb); check_bytes(cb, "C3");

    // sal
    cb_set_pos(cb, 0); sal(cb, CX, imm_opnd(1)); check_bytes(cb, "66D1E1");
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
    cb_set_pos(cb, 0); test(cb, AL, AL); check_bytes(cb, "84C0");
    cb_set_pos(cb, 0); test(cb, AX, AX); check_bytes(cb, "6685C0");
    cb_set_pos(cb, 0); test(cb, CL, imm_opnd(8)); check_bytes(cb, "F6C108");
    cb_set_pos(cb, 0); test(cb, DL, imm_opnd(7)); check_bytes(cb, "F6C207");
    cb_set_pos(cb, 0); test(cb, RCX, imm_opnd(8)); check_bytes(cb, "F6C108");
    cb_set_pos(cb, 0); test(cb, mem_opnd(8, RDX, 8), imm_opnd(8)); check_bytes(cb, "F6420808");
    cb_set_pos(cb, 0); test(cb, mem_opnd(8, RDX, 8), imm_opnd(255)); check_bytes(cb, "F64208FF");
    cb_set_pos(cb, 0); test(cb, DX, imm_opnd(0xFFFF)); check_bytes(cb, "66F7C2FFFF");
    cb_set_pos(cb, 0); test(cb, mem_opnd(16, RDX, 8), imm_opnd(0xFFFF)); check_bytes(cb, "66F74208FFFF");
    cb_set_pos(cb, 0); test(cb, mem_opnd(8, RSI, 0), imm_opnd(1)); check_bytes(cb, "F60601");
    cb_set_pos(cb, 0); test(cb, mem_opnd(8, RSI, 16), imm_opnd(1)); check_bytes(cb, "F6461001");
    cb_set_pos(cb, 0); test(cb, mem_opnd(8, RSI, -16), imm_opnd(1)); check_bytes(cb, "F646F001");
    cb_set_pos(cb, 0); test(cb, mem_opnd(32, RSI, 64), EAX); check_bytes(cb, "854640");
    cb_set_pos(cb, 0); test(cb, mem_opnd(64, RDI, 42), RAX); check_bytes(cb, "4885472A");
    cb_set_pos(cb, 0); test(cb, RAX, RAX); check_bytes(cb, "4885C0");
    cb_set_pos(cb, 0); test(cb, RAX, RSI); check_bytes(cb, "4885F0");
    cb_set_pos(cb, 0); test(cb, mem_opnd(64, RSI, 64), imm_opnd(~0x08)); check_bytes(cb, "48F74640F7FFFFFF");

    // xchg
    cb_set_pos(cb, 0); xchg(cb, RAX, RCX); check_bytes(cb, "4891");
    cb_set_pos(cb, 0); xchg(cb, RAX, R13); check_bytes(cb, "4995");
    cb_set_pos(cb, 0); xchg(cb, RCX, RBX); check_bytes(cb, "4887D9");
    cb_set_pos(cb, 0); xchg(cb, R9, R15); check_bytes(cb, "4D87F9");

    // xor
    cb_set_pos(cb, 0); xor(cb, EAX, EAX); check_bytes(cb, "31C0");

    printf("Assembler tests done\n");
}

void assert_equal(int expected, int actual)
{
    if (expected != actual) {
        fprintf(stderr, "expected %d, got %d\n", expected, actual);
        exit(-1);
    }
}

void run_runtime_tests(void)
{
    printf("Running runtime tests\n");

    codeblock_t codeblock;
    codeblock_t* cb = &codeblock;

    uint8_t* mem_block = alloc_exec_mem(4096);
    cb_init(cb, mem_block, 4096);

    int (*function)(void);
    function = (int (*)(void))mem_block;

    #define TEST(BODY) cb_set_pos(cb, 0); BODY ret(cb); cb_mark_all_executable(cb); assert_equal(7, function());

    // add
    TEST({ mov(cb, RAX, imm_opnd(0)); add(cb, RAX, imm_opnd(7)); })
    TEST({ mov(cb, RAX, imm_opnd(0)); mov(cb, RCX, imm_opnd(7)); add(cb, RAX, RCX); })

    // and
    TEST({ mov(cb, RAX, imm_opnd(31)); and(cb, RAX, imm_opnd(7)); })
    TEST({ mov(cb, RAX, imm_opnd(31)); mov(cb, RCX, imm_opnd(7)); and(cb, RAX, RCX); })

    // or
    TEST({ mov(cb, RAX, imm_opnd(3)); or(cb, RAX, imm_opnd(4)); })
    TEST({ mov(cb, RAX, imm_opnd(3)); mov(cb, RCX, imm_opnd(4)); or(cb, RAX, RCX); })

    // push/pop
    TEST({ mov(cb, RCX, imm_opnd(7)); push(cb, RCX); pop(cb, RAX); })

    // shr
    TEST({ mov(cb, RAX, imm_opnd(31)); shr(cb, RAX, imm_opnd(2)); })

    // sub
    TEST({ mov(cb, RAX, imm_opnd(12)); sub(cb, RAX, imm_opnd(5)); })
    TEST({ mov(cb, RAX, imm_opnd(12)); mov(cb, RCX, imm_opnd(5)); sub(cb, RAX, RCX); })

    // xor
    TEST({ mov(cb, RAX, imm_opnd(13)); xor(cb, RAX, imm_opnd(10)); })
    TEST({ mov(cb, RAX, imm_opnd(13)); mov(cb, RCX, imm_opnd(10)); xor(cb, RAX, RCX); })

    #undef TEST

    printf("Runtime tests done\n");
}

int main(int argc, char** argv)
{
    run_assembler_tests();
    run_runtime_tests();

    return 0;
}
