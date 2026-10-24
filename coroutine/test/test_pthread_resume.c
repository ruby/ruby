#include "ruby/internal/config.h"

#include COROUTINE_H

#include "stack.h"
#include "test_pthread_resume.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef COROUTINE_PTHREAD_CONTEXT

#include <pthread.h>

#define STACK_SIZE (1024 * 1024)
#define RESUME_COUNT 100

static struct coroutine_context main_context;
static struct coroutine_context worker_context;
static struct coroutine_context *expected_resumer;
static pthread_t main_thread;
static pthread_t worker_thread;
static unsigned int iteration;
static int completed;
static int resumer_result;

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

static struct coroutine_context *
transfer(struct coroutine_context *current, struct coroutine_context *target)
{
    struct coroutine_context *from = coroutine_transfer(current, target);

    if (from == NULL) {
        perror("coroutine_transfer");
        abort();
    }

    return from;
}

static COROUTINE
worker_entry(struct coroutine_context *from, struct coroutine_context *self)
{
    check_context("worker context was entered by", from, &main_context);
    check_context("worker context received self", self, &worker_context);
    worker_thread = pthread_self();

    for (iteration = 0; iteration < RESUME_COUNT; iteration++) {
        from = transfer(self, from);
        check_context("worker context was resumed by another pthread", from,
                      expected_resumer);

        if (!pthread_equal(worker_thread, pthread_self())) {
            fprintf(stderr, "worker coroutine migrated between pthreads\n");
            abort();
        }

        from = transfer(self, from);
        check_context("worker context was resumed by the main pthread", from,
                      &main_context);

        if (!pthread_equal(worker_thread, pthread_self())) {
            fprintf(stderr, "worker coroutine migrated between pthreads\n");
            abort();
        }
    }

    completed = 1;
    transfer(self, from);
    abort();
}

static void *
resume_worker(void *argument)
{
    (void)argument;

    struct coroutine_context resumer_context;
    coroutine_initialize_main(&resumer_context);
    expected_resumer = &resumer_context;

    if (pthread_equal(main_thread, pthread_self()) ||
        pthread_equal(worker_thread, pthread_self())) {
        fprintf(stderr, "pthread resumer did not run on a distinct pthread\n");
        resumer_result = EXIT_FAILURE;
        coroutine_destroy(&resumer_context);
        return NULL;
    }

    struct coroutine_context *from = transfer(&resumer_context, &worker_context);
    if (from != &worker_context) {
        fprintf(stderr, "pthread resumer was resumed by an unexpected context\n");
        resumer_result = EXIT_FAILURE;
    }

    coroutine_destroy(&resumer_context);
    return NULL;
}

int
test_pthread_resume(void)
{
    struct coroutine_stack stack = {0};
    int result = EXIT_FAILURE;

    if (coroutine_stack_allocate(&stack, STACK_SIZE) != 0) {
        fprintf(stderr, "failed to allocate coroutine stack\n");
        return EXIT_FAILURE;
    }

    iteration = 0;
    completed = 0;
    resumer_result = EXIT_SUCCESS;
    main_thread = pthread_self();

    coroutine_initialize_main(&main_context);
    coroutine_initialize(&worker_context, worker_entry, stack.base, stack.size);

    if (transfer(&main_context, &worker_context) != &worker_context || iteration != 0) {
        fprintf(stderr, "worker did not initially yield to the main pthread\n");
        goto finish;
    }

    for (unsigned int expected_iteration = 0;
         expected_iteration < RESUME_COUNT;
         expected_iteration++) {
        pthread_t resumer;
        int error = pthread_create(&resumer, NULL, resume_worker, NULL);
        if (error != 0) {
            fprintf(stderr, "failed to create pthread resumer: %d\n", error);
            goto finish;
        }

        error = pthread_join(resumer, NULL);
        if (error != 0 || resumer_result != EXIT_SUCCESS) {
            fprintf(stderr, "pthread resumer failed: %d\n", error);
            goto finish;
        }

        if (transfer(&main_context, &worker_context) != &worker_context) {
            fprintf(stderr, "worker did not yield after changing pthread resumer\n");
            goto finish;
        }

        if (expected_iteration + 1 < RESUME_COUNT) {
            if (iteration != expected_iteration + 1 || completed) {
                fprintf(stderr, "worker resumed at an unexpected iteration\n");
                goto finish;
            }
        }
        else if (!completed) {
            fprintf(stderr, "worker did not complete pthread resume test\n");
            goto finish;
        }
    }

    result = EXIT_SUCCESS;

finish:
    coroutine_destroy(&worker_context);
    coroutine_destroy(&main_context);
    coroutine_stack_free(&stack);

    return result;
}

#else

int
test_pthread_resume(void)
{
    return EXIT_SUCCESS;
}

#endif
