#include <stdio.h>
#include <stdlib.h>
#include "ujit_asm.h"

//fprintf(stderr, format);
//exit(-1)

// TODO: make a macro to test encoding sequences
// ***You can use sizeof to know the length***
// CHECK_BYTES(cb, {})





void run_tests()
{
    printf("Running assembler tests\n");

    codeblock_t cb;
    cb_init(&cb, 4096);

    cb_write_prologue(&cb);
    cb_write_epilogue(&cb);









    printf("Assembler tests done\n");
}

int main(int argc, char** argv)
{
    run_tests();

    return 0;
}
