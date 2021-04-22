set -e
set -x

clang -std=gnu99 -Wall -Werror -Wshorten-64-to-32 yjit_asm.c yjit_asm_tests.c -o asm_test

./asm_test

rm asm_test
