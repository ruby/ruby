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
        fprintf(stderr, "incorrect encoding length %ld\n", cb->write_pos);
        exit(-1);
    }

    for (size_t i = 0; i < num_bytes; ++i)
    {
        char byte_str[] = {0, 0, 0, 0};
        strncpy(byte_str, bytes + (2 * i), 2);
        //printf("%ld: %s\n", i, byte_str);

        char* endptr;
        long int byte = strtol(byte_str, &endptr, 16);

        uint8_t cb_byte = cb->mem_block[i];

        if (cb_byte != byte)
        {
            fprintf(stderr, "incorrect encoding at position %ld\n", i);
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










    printf("Assembler tests done\n");
}

int main(int argc, char** argv)
{
    run_tests();

    return 0;
}
