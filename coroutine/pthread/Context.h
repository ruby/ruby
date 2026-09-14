/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 24/6/2021.
 *  Copyright, 2021, by Samuel Williams.
*/

#pragma once

#include <assert.h>
#include <stddef.h>
#include <pthread.h>

#define COROUTINE void

#define COROUTINE_PTHREAD_CONTEXT

#ifdef HAVE_STDINT_H
#include <stdint.h>
#if INTPTR_MAX <= INT32_MAX
#define COROUTINE_LIMITED_ADDRESS_SPACE
#endif
#endif

struct coroutine_context;

enum coroutine_state
{
    /* Initialized, but its worker pthread has not been started yet. */
    COROUTINE_CREATED,

    /* Currently executing and therefore not a valid transfer target. */
    COROUTINE_RUNNING,

    /* Waiting on schedule and ready to be resumed by another context. */
    COROUTINE_SUSPENDED,

    /* Its synchronization primitives have been destroyed. */
    COROUTINE_DESTROYED
};

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

struct coroutine_context
{
    coroutine_start start;
    void *argument;

    void *stack;
    size_t size;

    /* The caller pthread for a main context, or the context's worker pthread. */
    pthread_t id;

    /* Serializes updates to state and from, and is paired with schedule. */
    pthread_mutex_t guard;

    /* Wakes this context when another context transfers control to it. */
    pthread_cond_t schedule;

    /* The transfer lifecycle, read and updated while holding guard. */
    enum coroutine_state state;

    /* Whether guard and schedule have been initialized and remain valid. */
    int initialized;

    /* Whether the lazily created worker pthread must be cancelled and joined.
     * This remains false for a main context, whose id is the caller's pthread. */
    int thread_created;

    /* The context that most recently transferred control to this context. */
    struct coroutine_context * from;
};

void coroutine_initialize_main(struct coroutine_context * context);

void coroutine_initialize(
    struct coroutine_context *context,
    coroutine_start start,
    void *stack,
    size_t size
);

struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target);

void coroutine_destroy(struct coroutine_context * context);
