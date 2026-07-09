#ifndef COROUTINE_AMD64_CONTEXT_H
#define COROUTINE_AMD64_CONTEXT_H 1

/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 10/5/2018.
 *  Copyright, 2018, by Samuel Williams.
*/

#pragma once

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define COROUTINE __attribute__((noreturn)) void

enum {COROUTINE_REGISTERS = 6};

#if defined(__SANITIZE_ADDRESS__)
    #define COROUTINE_SANITIZE_ADDRESS
#elif defined(__has_feature)
    #if __has_feature(address_sanitizer)
        #define COROUTINE_SANITIZE_ADDRESS
    #endif
#endif

#if defined(COROUTINE_SANITIZE_ADDRESS)
#include <sanitizer/common_interface_defs.h>
#include <sanitizer/asan_interface.h>
#endif

#if defined(__SANITIZE_THREAD__)
    #define COROUTINE_SANITIZE_THREAD
#elif defined(__has_feature)
    #if __has_feature(thread_sanitizer)
        #define COROUTINE_SANITIZE_THREAD
    #endif
#endif

#if defined(COROUTINE_SANITIZE_THREAD)
/* ThreadSanitizer cannot follow a userspace stack switch on its own: its
 * per-OS-thread shadow stack must be handed to the destination fiber on every
 * coroutine switch via the fiber API, otherwise it leaks the shadow stack
 * across switches and eventually faults inside libtsan. */
#include <sanitizer/tsan_interface.h>
#endif

struct coroutine_context
{
    void **stack_pointer;
    void *argument;

#if defined(COROUTINE_SANITIZE_ADDRESS)
    void *fake_stack;
    void *stack_base;
    size_t stack_size;
#endif

#if defined(COROUTINE_SANITIZE_THREAD)
    void *tsan_fiber;
    /* Whether we created tsan_fiber (via __tsan_create_fiber, must be
     * destroyed) or borrowed it from __tsan_get_current_fiber (the OS thread's
     * implicit fiber, owned by TSan; must not be destroyed). */
    int tsan_fiber_owned;
#endif
};

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

static inline void coroutine_initialize_main(struct coroutine_context * context) {
    context->stack_pointer = NULL;

#if defined(COROUTINE_SANITIZE_THREAD)
    /* The OS thread's implicit (already running) fiber, owned by TSan. */
    context->tsan_fiber = __tsan_get_current_fiber();
    context->tsan_fiber_owned = 0;
#endif
}

static inline void coroutine_initialize(
    struct coroutine_context *context,
    coroutine_start start,
    void *stack,
    size_t size
) {
    assert(start && stack && size >= 1024);

#if defined(COROUTINE_SANITIZE_ADDRESS)
    context->fake_stack = NULL;
    context->stack_base = stack;
    context->stack_size = size;
#endif

#if defined(COROUTINE_SANITIZE_THREAD)
    context->tsan_fiber = __tsan_create_fiber(0);
    context->tsan_fiber_owned = 1;
#endif

    // Stack grows down. Force 16-byte alignment.
    char * top = (char*)stack + size;
    context->stack_pointer = (void**)((uintptr_t)top & ~0xF);

    *--context->stack_pointer = NULL;
    *--context->stack_pointer = (void*)(uintptr_t)start;

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);
}

struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target);

static inline void coroutine_destroy(struct coroutine_context * context)
{
    context->stack_pointer = NULL;

#if defined(COROUTINE_SANITIZE_THREAD)
    /* Only destroy fibers we created. The borrowed __tsan_get_current_fiber()
     * handle (the OS thread's implicit fiber) is owned by TSan; destroying it
     * aborts libtsan (FiberDestroy -> ProcWire CheckFailed). */
    if (context->tsan_fiber && context->tsan_fiber_owned) {
        __tsan_destroy_fiber(context->tsan_fiber);
        context->tsan_fiber = NULL;
        context->tsan_fiber_owned = 0;
    }
#endif
}

#endif /* COROUTINE_AMD64_CONTEXT_H */
