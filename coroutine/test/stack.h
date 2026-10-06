#pragma once

#include <stddef.h>

struct coroutine_stack {
    void *base;
    size_t size;
};

int coroutine_stack_allocate(struct coroutine_stack *stack, size_t size);
void coroutine_stack_free(struct coroutine_stack *stack);
