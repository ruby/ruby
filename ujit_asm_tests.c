#include <stdio.h>
#include <stdlib.h>
#include "ujit_asm.h"

//fprintf(stderr, format);
//exit(-1)

void run_tests()
{
    printf("Running assembler tests\n");

    codeblock_t cb;
    cb_init(&cb, 4096);









    printf("Assembler tests done\n");
}

int main(int argc, char** argv)
{
    run_tests();

    return 0;
}
