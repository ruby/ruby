#ifndef UJIT_UTILS_H
#define UJIT_UTILS_H 1

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "ujit_asm.h"

void push_regs(codeblock_t* cb);
void pop_regs(codeblock_t* cb);
void print_str(codeblock_t* cb, const char* str);

#endif // #ifndef UJIT_UTILS_H
