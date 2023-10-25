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

struct coroutine_shared
{
    pthread_mutex_t guard;
    struct coroutine_context * main;

    size_t count;
};

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

struct coroutine_context
{
    struct coroutine_shared * shared;

    coroutine_start start;
    void *argument;

    void *stack;
    size_t size;

    pthread_t id;
    pthread_cond_t schedule;
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
