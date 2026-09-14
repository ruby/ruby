/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 24/6/2021.
 *  Copyright, 2021, by Samuel Williams.
*/

#include "Context.h"
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
    context->start = NULL;

    check("coroutine_initialize_main:pthread_mutex_init",
        pthread_mutex_init(&context->guard, NULL)
    );

    check("coroutine_initialize_main:pthread_cond_init",
        pthread_cond_init(&context->schedule, NULL)
    );

    context->suspended = 0;
    context->initialized = 1;
    context->thread_created = 0;
    context->from = NULL;
}

void coroutine_initialize(
    struct coroutine_context *context,
    coroutine_start start,
    void *stack,
    size_t size
) {
    assert(start && stack && size >= 1024);

    // We will create the thread when we first transfer, but save the details now:
    context->start = start;
    context->stack = stack;
    context->size = size;

    check("coroutine_initialize:pthread_mutex_init",
        pthread_mutex_init(&context->guard, NULL)
    );

    check("coroutine_initialize:pthread_cond_init",
        pthread_cond_init(&context->schedule, NULL)
    );

    /* A worker is initially resumable even though its pthread is created
     * lazily by the first transfer. */
    context->suspended = 1;
    context->initialized = 1;
    context->thread_created = 0;
    context->from = NULL;
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
        pthread_mutex_unlock(&context->guard)
    );
}

void * coroutine_trampoline(void * _context)
{
    struct coroutine_context * context = _context;

    context->start(context->from, context);

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

    result = pthread_create(&context->id, &attr, coroutine_trampoline, context);
    pthread_attr_destroy(&attr);

    if (result != 0) {
        return result;
    }

    context->thread_created = 1;

    return result;
}

static
void coroutine_lock_pair(struct coroutine_context *current, struct coroutine_context *target)
{
    /* A valid transfer targets a suspended context, so it cannot be trying to
     * acquire current->guard while we acquire target->guard. */
    check("coroutine_transfer:pthread_mutex_lock(current)",
        pthread_mutex_lock(&current->guard)
    );

    check("coroutine_transfer:pthread_mutex_lock(target)",
        pthread_mutex_lock(&target->guard)
    );
}

static
void coroutine_unlock_pair(struct coroutine_context *current, struct coroutine_context *target)
{
    check("coroutine_transfer:pthread_mutex_unlock(target)",
        pthread_mutex_unlock(&target->guard)
    );

    check("coroutine_transfer:pthread_mutex_unlock(current)",
        pthread_mutex_unlock(&current->guard)
    );
}

struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target)
{
    assert(current->initialized);
    assert(target->initialized);
    assert(current != target);

    int result = 0;

    coroutine_lock_pair(current, target);

    if (current->start == NULL) {
        /* A main context follows its caller, which may change when Ruby's M:N
         * scheduler moves a Ruby thread to another native thread. */
        current->id = pthread_self();
    }
    else {
        assert(current->thread_created);
        assert(pthread_equal(current->id, pthread_self()));
    }
    assert(!current->suspended);
    assert(target->suspended);

    struct coroutine_context * previous = target->from;

    current->suspended = 1;
    target->suspended = 0;
    target->from = current;

    // First transfer:
    if (target->start != NULL && !target->thread_created) {
        if (DEBUG) fprintf(stderr, "coroutine_transfer:coroutine_create_thread...\n");
        result = coroutine_create_thread(target);
        if (result != 0) {
            if (DEBUG) fprintf(stderr, "coroutine_transfer:coroutine_create_thread failed\n");
        }
    } else {
        if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_cond_signal(target)\n");
        result = pthread_cond_signal(&target->schedule);
    }

    if (result != 0) {
        target->from = previous;
        target->suspended = 1;
        current->suspended = 0;
        coroutine_unlock_pair(current, target);
        errno = result;
        return NULL;
    }

    check("coroutine_transfer:pthread_mutex_unlock(target)",
        pthread_mutex_unlock(&target->guard)
    );

    pthread_cleanup_push(coroutine_guard_unlock, current);

    while (current->suspended) {
        // A side effect of acting upon a cancellation request while in a condition wait is that the mutex is (in effect) re-acquired before calling the first cancellation cleanup handler. If cancelled, pthread_cond_wait immediately invokes cleanup handlers.
        if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_cond_wait(schedule=%p, guard=%p, is_locked=%d)\n", &current->schedule, &current->guard, is_locked(&current->guard));
        check("coroutine_transfer:pthread_cond_wait",
            pthread_cond_wait(&current->schedule, &current->guard)
        );
    }

    if (DEBUG) fprintf(stderr, "coroutine_transfer:pthread_cleanup_pop\n");
    pthread_cleanup_pop(1);

#ifdef __FreeBSD__
    // Apparently required for FreeBSD:
    pthread_testcancel();
#endif

    /* current may have been resumed by a context other than target. */
    return current->from;
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

    if (!context->initialized) return;

    if (context->thread_created) {
        coroutine_join(context);
        context->thread_created = 0;
    }

    if (DEBUG) fprintf(stderr, "coroutine_destroy:pthread_cond_destroy(%p)\n", &context->schedule);
    pthread_cond_destroy(&context->schedule);
    pthread_mutex_destroy(&context->guard);
    context->initialized = 0;
}
