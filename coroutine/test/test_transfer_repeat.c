#include "ruby/internal/config.h"

#include COROUTINE_H

#include "stack.h"
#include "test_transfer_repeat.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define STACK_SIZE (1024 * 1024)
#define TRANSFER_COUNT 1000

static struct coroutine_context main_context;
static struct coroutine_context worker_context;
static unsigned int yielded_iteration;
static uint32_t yielded_state;
static int completed;

static void
check_context(const char *message, struct coroutine_context *actual,
              struct coroutine_context *expected)
{
    if (actual != expected) {
        fprintf(stderr, "%s: expected %p, got %p\n",
                message, (void *)expected, (void *)actual);
        abort();
    }
}

static void
context_start(struct coroutine_context *from, struct coroutine_context *self)
{
#if defined(COROUTINE_SANITIZE_ADDRESS)
    __sanitizer_finish_switch_fiber(self->fake_stack,
                                    (const void **)&from->stack_base,
                                    &from->stack_size);
#else
    (void)from;
    (void)self;
#endif
}

static struct coroutine_context *
transfer(struct coroutine_context *current, struct coroutine_context *target)
{
#if defined(COROUTINE_SANITIZE_ADDRESS)
    __sanitizer_start_switch_fiber(&current->fake_stack,
                                   target->stack_base, target->stack_size);
#endif

#if defined(COROUTINE_SANITIZE_THREAD)
    __tsan_switch_to_fiber(target->tsan_fiber, 0);
#endif

    struct coroutine_context *from = coroutine_transfer(current, target);

#if defined(COROUTINE_SANITIZE_ADDRESS)
    __sanitizer_finish_switch_fiber(current->fake_stack, NULL, NULL);
#endif

    return from;
}

static COROUTINE
worker_entry(struct coroutine_context *from, struct coroutine_context *self)
{
    context_start(from, self);

    check_context("worker context was entered by", from, &main_context);
    check_context("worker context received self", self, &worker_context);

    uint32_t state = UINT32_C(0x12345678);

    for (unsigned int iteration = 1; iteration <= TRANSFER_COUNT; iteration++) {
        state = state * UINT32_C(1664525) + UINT32_C(1013904223);
        yielded_iteration = iteration;
        yielded_state = state;

        from = transfer(self, &main_context);
        check_context("worker context was resumed by", from, &main_context);

        if (yielded_iteration != iteration || yielded_state != state) {
            fprintf(stderr, "worker local state was not preserved\n");
            abort();
        }
    }

    completed = 1;
    transfer(self, &main_context);
    abort();
}

int
test_transfer_repeat(void)
{
    struct coroutine_stack stack = {0};
    int result = EXIT_FAILURE;

    if (coroutine_stack_allocate(&stack, STACK_SIZE) != 0) {
        fprintf(stderr, "failed to allocate coroutine stack\n");
        return EXIT_FAILURE;
    }

    yielded_iteration = 0;
    yielded_state = 0;
    completed = 0;

    coroutine_initialize_main(&main_context);
    coroutine_initialize(&worker_context, worker_entry, stack.base, stack.size);

    uint32_t expected_state = UINT32_C(0x12345678);

    for (unsigned int iteration = 1; iteration <= TRANSFER_COUNT; iteration++) {
        expected_state = expected_state * UINT32_C(1664525) + UINT32_C(1013904223);

        struct coroutine_context *from = transfer(&main_context, &worker_context);

        if (from != &worker_context || yielded_iteration != iteration ||
            yielded_state != expected_state || completed) {
            fprintf(stderr, "repeated coroutine transfer failed at iteration %u\n",
                    iteration);
            goto finish;
        }
    }

    if (transfer(&main_context, &worker_context) != &worker_context || !completed) {
        fprintf(stderr, "worker context did not complete repeated transfers\n");
        goto finish;
    }

    result = EXIT_SUCCESS;

finish:
    coroutine_destroy(&worker_context);
    coroutine_destroy(&main_context);
    coroutine_stack_free(&stack);

    return result;
}
