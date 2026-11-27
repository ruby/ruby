#include "ruby/internal/config.h"

#include COROUTINE_H

#include "stack.h"
#include "test_initialize_destroy.h"

#include <stdio.h>
#include <stdlib.h>

#define STACK_SIZE (1024 * 1024)

static COROUTINE
never_started(struct coroutine_context *from, struct coroutine_context *self)
{
    (void)from;
    (void)self;
    abort();
}

int
test_initialize_destroy(void)
{
    struct coroutine_stack stack = {0};
    struct coroutine_context main_context;
    struct coroutine_context context;

    if (coroutine_stack_allocate(&stack, STACK_SIZE) != 0) {
        fprintf(stderr, "failed to allocate coroutine stack\n");
        return EXIT_FAILURE;
    }

    coroutine_initialize_main(&main_context);
    coroutine_initialize(&context, never_started, stack.base, stack.size);

    coroutine_destroy(&context);
    coroutine_destroy(&main_context);
    coroutine_stack_free(&stack);

    return EXIT_SUCCESS;
}
