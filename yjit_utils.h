#ifndef YJIT_UTILS_H
#define YJIT_UTILS_H 1

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "yjit_asm.h"

void push_regs(codeblock_t *cb);
void pop_regs(codeblock_t *cb);
void print_int(codeblock_t *cb, x86opnd_t opnd);
void print_ptr(codeblock_t *cb, x86opnd_t opnd);
void print_str(codeblock_t *cb, const char *str);

#endif // #ifndef YJIT_UTILS_H
