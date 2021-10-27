/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 24/6/2021.
 *  Copyright, 2021, by Samuel Williams.
*/

#include "Context.h"
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

static const int DEBUG = 0;

static
int check(const char * message, int result) {
    if (result) {
        switch (result) {
            case EDEADLK:
                if (DEBUG) fprintf(stderr, "deadlock detected result=%d errno=%d\n", result, errno);
                break;
            default:
                if (DEBUG) fprintf(stderr, "error detected result=%d errno=%d\n", result, errno);
                perror(message);
        }
    }

    assert(result == 0);

    return result;
}

void coroutine_initialize_main(struct coroutine_context * context) {
    context->id = pthread_self();

    check("coroutine_initialize_main:pthread_cond_init",
        pthread_cond_init(&context->schedule, NULL)
    );

    context->shared = (struct coroutine_shared*)malloc(sizeof(struct coroutine_shared));
    assert(context->shared);

    context->shared->main = context;
    context->shared->count = 1;

    if (DEBUG) {
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);

        check("coroutine_initialize_main:pthread_mutex_init",
            pthread_mutex_init(&context->shared->guard, &attr)
        );
    } else {
        check("coroutine_initialize_main:pthread_mutex_init",
            pthread_mutex_init(&context->shared->guard, NULL)
        );
    }
}

static
void coroutine_release(struct coroutine_context *context) {
    if (context->shared) {
        size_t count = (context->shared->count -= 1);

        if (count == 0) {
            if (DEBUG) fprintf(stderr, "coroutine_release:pthread_mutex_destroy(%p)\n", &context->shared->guard);
            pthread_mutex_destroy(&context->shared->guard);
            free(context->shared);
        }

        context->shared = NULL;

        if (DEBUG) fprintf(stderr, "coroutine_release:pthread_cond_destroy(%p)\n", &context->schedule);
        pthread_cond_destroy(&context->schedule);
    }
}

void coroutine_initialize(
    struct coroutine_context *context,
    coroutine_start start,
    void *stack,
    size_t size
) {
    assert(start && stack && size >= 1024);

    // We will create the thread when we first transfer, but save the details now:
    context->shared = NULL;
    context->start = start;
    context->stack = stack;
    context->size = size;
}

static
int is_locked(pthread_mutex_t * mutex) {
    int result = pthread_mutex_trylock(mutex);

    // If we could successfully lock the mutex:
    if (result == 0) {
        pthread_mutex_unlock(mutex);
        // We could lock the mutex, so it wasn't locked:
        return 0;
    } else {
        // Otherwise we couldn't lock it because it's already locked:
        return 1;
    }
}

static
void coroutine_guard_unlock(void * _context)
{
    struct coroutine_context * context = _context;

    if (DEBUG) fprintf(stderr, "coroutine_guard_unlock:pthread_mutex_unlock\n");

    check("coroutine_guard_unlock:pthread_mutex_unlock",
        pthread_mutex_unlock(&context->shared->guard)
    );
}

static
void coroutine_wait(struct coroutine_context *context)
{
    if (DEBUG) fprintf(stderr, "coroutine_wait:pthread_mutex_lock(guard=%p is_locked=%d)\n", &context->shared->guard, is_locked(&context->shared->guard));
    check("coroutine_wait:pthread_mutex_lock",
        pthread_mutex_lock(&context->shared->guard)
    );

    if (DEBUG) fprintf(stderr, "coroutine_wait:pthread_mutex_unlock(guard)\n");
    pthread_mutex_unlock(&context->shared->guard);
}

static
void coroutine_trampoline_cleanup(void *_context) {
    struct coroutine_context * context = _context;
    coroutine_release(context);
}

void * coroutine_trampoline(void * _context)
{
    struct coroutine_context * context = _context;
    assert(context->shared);

    pthread_cleanup_push(coroutine_trampoline_cleanup, context);

    coroutine_wait(context);

    context->start(context->from, context);

    pthread_cleanup_pop(1);

    return NULL;
}

static
int coroutine_create_thread(struct coroutine_context *context)
{
    int result;

    pthread_attr_t attr;
    result = pthread_attr_init(&attr);
    if (result != 0) {
        return result;
    }

    result = pthread_attr_setstack(&attr, context->stack, (size_t)context->size);
    if (result != 0) {
        pthread_attr_destroy(&attr);
        return result;
    }

    result = pthread_cond_init(&context->schedule, NULL);
    if (result != 0) {
        pthread_attr_destroy(&attr);
        return result;
    }

    result = pthread_create(&context->id, &attr, coroutine_trampoline, context);
    if (result != 0) {
        pthread_attr_destroy(&attr);
        if (DEBUG) fprintf(stderr, "coroutine_create_thread:pthread_cond_destroy(%p)\n", &context->schedule);
        pthread_cond_destroy(&context->schedule);
        return result;
    }

    context->shared->count += 1;

    return result;
}

struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target)
{
    assert(current->shared);

    struct coroutine_context * previous = target->from;
    target->from = current;

    if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_mutex_lock(guard=%p is_locked=%d)\n", &current->shared->guard, is_locked(&current->shared->guard));
    pthread_mutex_lock(&current->shared->guard);
    pthread_cleanup_push(coroutine_guard_unlock, current);

    // First transfer:
    if (target->shared == NULL) {
        target->shared = current->shared;

        if (DEBUG) fprintf(stderr, "coroutine_transfer:coroutine_create_thread...\n");
        if (coroutine_create_thread(target)) {
            if (DEBUG) fprintf(stderr, "coroutine_transfer:coroutine_create_thread failed\n");
            target->shared = NULL;
            target->from = previous;
            return NULL;
        }
    } else {
        if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_cond_signal(target)\n");
        pthread_cond_signal(&target->schedule);
    }

    // A side effect of acting upon a cancellation request while in a condition wait is that the mutex is (in effect) re-acquired before calling the first cancellation cleanup handler. If cancelled, pthread_cond_wait immediately invokes cleanup handlers.
    if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_cond_wait(schedule=%p, guard=%p, is_locked=%d)\n", &current->schedule, &current->shared->guard, is_locked(&current->shared->guard));
    check("coroutine_transfer:pthread_cond_wait",
        pthread_cond_wait(&current->schedule, &current->shared->guard)
    );

    if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_cleanup_pop\n");
    pthread_cleanup_pop(1);

#ifdef __FreeBSD__
    // Apparently required for FreeBSD:
    pthread_testcancel();
#endif

    target->from = previous;

    return target;
}

static
void coroutine_join(struct coroutine_context * context) {
    if (DEBUG) fprintf(stderr, "coroutine_join:pthread_cancel\n");
    int result = pthread_cancel(context->id);
    if (result == -1 && errno == ESRCH) {
        // The thread may be dead due to fork, so it cannot be joined and this doesn't represent a real error:
        return;
    }

    check("coroutine_join:pthread_cancel", result);

    if (DEBUG) fprintf(stderr, "coroutine_join:pthread_join\n");
    check("coroutine_join:pthread_join",
        pthread_join(context->id, NULL)
    );

    if (DEBUG) fprintf(stderr, "coroutine_join:pthread_join done\n");
}

void coroutine_destroy(struct coroutine_context * context)
{
    if (DEBUG) fprintf(stderr, "coroutine_destroy\n");

    assert(context);

    // We are already destroyed or never created:
    if (context->shared == NULL) return;

    if (context == context->shared->main) {
        context->shared->main = NULL;
        coroutine_release(context);
    } else {
        coroutine_join(context);
        assert(context->shared == NULL);
    }
}
