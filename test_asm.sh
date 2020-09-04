# NOTE: I did not know what would be the sensible way to compile
# and run these tests from the Ruby makefile

clang -std=c99 -Wall ujit_asm.c ujit_asm_tests.c -o asm_test

./asm_test
