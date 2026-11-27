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

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

struct coroutine_context
{
    /* NULL for a main context; otherwise the worker pthread entry point. */
    coroutine_start start;
    void *argument;

    void *stack;
    size_t size;

    /* The current caller for a main context, or the context's worker pthread. */
    pthread_t id;

    /* Whether the lazily created worker pthread must be cancelled and joined.
     * This remains false for a main context, whose id is the caller's pthread. */
    int thread_created;

    /* Serializes updates to suspended and from, and is paired with schedule. */
    pthread_mutex_t guard;

    /* Wakes this context when another context transfers control to it. */
    pthread_cond_t schedule;

    /* Whether this context is inactive and can be resumed. This is also the
     * predicate protected by guard and checked when waiting on schedule. */
    int suspended;

    /* Whether guard and schedule have been initialized and remain valid. */
    int initialized;

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
