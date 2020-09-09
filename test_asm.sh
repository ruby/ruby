# NOTE: I did not know what would be the sensible way to compile
# and run these tests from the Ruby makefile

clear

clang -std=gnu99 -Wall -Werror -Wshorten-64-to-32 ujit_asm.c ujit_asm_tests.c -o asm_test

./asm_test

rm asm_test
