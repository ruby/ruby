#include "ruby/internal/config.h"

#include COROUTINE_H

#include "stack.h"
#include "test_transfer_return.h"

#include <stdio.h>
#include <stdlib.h>

#define STACK_SIZE (1024 * 1024)

static struct coroutine_context main_context;
static struct coroutine_context first_context;
static struct coroutine_context second_context;

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
second_entry(struct coroutine_context *from, struct coroutine_context *self)
{
    context_start(from, self);

    check_context("second context was entered by", from, &first_context);
    check_context("second context received self", self, &second_context);

    from = transfer(self, &main_context);
    check_context("second context was resumed by", from, &main_context);

    transfer(self, &first_context);
    abort();
}

static COROUTINE
first_entry(struct coroutine_context *from, struct coroutine_context *self)
{
    context_start(from, self);

    check_context("first context was entered by", from, &main_context);
    check_context("first context received self", self, &first_context);

    from = transfer(self, &second_context);
    check_context("first context was resumed by", from, &second_context);

    transfer(self, &main_context);
    abort();
}

int
test_transfer_return(void)
{
    struct coroutine_stack first_stack = {0};
    struct coroutine_stack second_stack = {0};
    int result = EXIT_FAILURE;

    if (coroutine_stack_allocate(&first_stack, STACK_SIZE) != 0 ||
        coroutine_stack_allocate(&second_stack, STACK_SIZE) != 0) {
        fprintf(stderr, "failed to allocate coroutine stacks\n");
        goto finish;
    }

    coroutine_initialize_main(&main_context);
    coroutine_initialize(&first_context, first_entry,
                         first_stack.base, first_stack.size);
    coroutine_initialize(&second_context, second_entry,
                         second_stack.base, second_stack.size);

    result = EXIT_SUCCESS;

    /* The original target is first_context, but second_context resumes us. */
    struct coroutine_context *from = transfer(&main_context, &first_context);

    if (from != &second_context) {
        fprintf(stderr,
                "coroutine_transfer returned %p, expected actual resumer %p\n",
                (void *)from, (void *)&second_context);
        result = EXIT_FAILURE;
    }

    /* Resume second_context, which resumes first_context, which resumes us. */
    from = transfer(&main_context, &second_context);

    if (from != &first_context) {
        fprintf(stderr,
                "coroutine_transfer returned %p, expected actual resumer %p\n",
                (void *)from, (void *)&first_context);
        result = EXIT_FAILURE;
    }

    coroutine_destroy(&first_context);
    coroutine_destroy(&second_context);
    coroutine_destroy(&main_context);

finish:
    coroutine_stack_free(&first_stack);
    coroutine_stack_free(&second_stack);

    return result;
}
