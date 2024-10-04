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

// AMD/Intel CET Support.
#ifdef COROUTINE_CONTROL_FLOW_PROTECTION
#include <asm/prctl.h>
#include <sys/prctl.h>

int arch_prctl(int code, unsigned long address);

static inline void* coroutine_current_shadow_stack(void)
{
    uint64_t shadow_stack_pointer = 0;
    asm("rdsspq %0\n" : "=r" (shadow_stack_pointer));
    return (void *)shadow_stack_pointer;
}

static inline void* coroutine_allocate_shadow_stack(size_t size)
{
    #ifndef ARCH_X86_CET_ALLOC_SHSTK
    #define ARCH_X86_CET_ALLOC_SHSTK 0x3004
    #endif

    uint64_t argument = size;
    if (arch_prctl(ARCH_X86_CET_ALLOC_SHSTK, (unsigned long) &size) < 0) {
        return NULL;
    }

    return (void *)argument;
}
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

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
    void *shadow_stack;
    size_t shadow_stack_size;
#endif
};

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

static inline void coroutine_initialize_main(struct coroutine_context * context) {
    context->stack_pointer = NULL;

#if defined(COROUTINE_SANITIZE_ADDRESS)
    context->fake_stack = NULL;
    context->stack_base = NULL;
    context->stack_size = 0;
#endif

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
    context->shadow_stack = NULL;
    context->shadow_stack_size = 0;
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

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
    if (coroutine_current_shadow_stack()) {
        // Assume a ratio of 8:1 stack usage:
        size_t shadow_stack_size = size;

        context->shadow_stack = coroutine_allocate_shadow_stack(shadow_stack_size);
        context->shadow_stack_size = shadow_stack_size;
    } else {
        context->shadow_stack = NULL;
        context->shadow_stack_size = 0;
    }
#endif

    // Stack grows down. Force 16-byte alignment.
    char * top = (char*)stack + size;
    context->stack_pointer = (void**)((uintptr_t)top & ~0xF);

    // Preserve alignment with optionally added shadow stack value:
    *--context->stack_pointer = NULL;
    *--context->stack_pointer = (void*)start;

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
    // Set up the shadow stack pointer.
    *--context->stack_pointer = (char*)context->shadow_stack + context->shadow_stack_size;
#endif
}

struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target);

static inline void coroutine_destroy(struct coroutine_context * context)
{
    context->stack_pointer = NULL;

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
    if (context->shadow_stack) {
        munmap(context->shadow_stack, context->shadow_stack_size);
        context->shadow_stack = NULL;
    }
#endif
}

#endif /* COROUTINE_AMD64_CONTEXT_H */
