#ifndef COROUTINE_ASYNCIFY_CONTEXT_H
#define COROUTINE_ASYNCIFY_CONTEXT_H

/*
 This is a coroutine implementation based on Binaryen's Asyncify transformation for WebAssembly.

 This implementation is built on low-level ucontext-like API in wasm/fiber.c
 This file is an adapter for the common coroutine interface and for stack manipulation.
 wasm/fiber.c doesn't take care of stack to avoid duplicate management with this adapter.

 * See also: wasm/fiber.c
*/

#include <stddef.h>
#include <stdio.h>
#include <stdint.h>
#include "wasm/asyncify.h"
#include "wasm/machine.h"
#include "wasm/fiber.h"

#define COROUTINE void __attribute__((__noreturn__))

static const int ASYNCIFY_CORO_DEBUG = 0;

struct coroutine_context
{
    rb_wasm_fiber_context fc;
    void *argument;
    struct coroutine_context *from;

    void *current_sp;
    void *stack_base;
    size_t size;
};

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

COROUTINE coroutine_trampoline(void * _start, void * _context);

static inline void coroutine_initialize_main(struct coroutine_context * context)
{
    if (ASYNCIFY_CORO_DEBUG) fprintf(stderr, "[%s] entry (context = %p)\n", __func__, context);
    // NULL fiber entry means it's the main fiber, and handled specially.
    rb_wasm_init_context(&context->fc, NULL, NULL, NULL);
    // mark the main fiber has already started
    context->fc.is_started = true;
}

static inline void coroutine_initialize(struct coroutine_context *context, coroutine_start start, void *stack, size_t size)
{
    // Linear stack pointer must be always aligned down to 16 bytes.
    // https://github.com/WebAssembly/tool-conventions/blob/c74267a5897c1bdc9aa60adeaf41816387d3cd12/BasicCABI.md#the-linear-stack
    uintptr_t sp = ((uintptr_t)stack + size) & ~0xF;
    if (ASYNCIFY_CORO_DEBUG) fprintf(stderr, "[%s] entry (context = %p, stack = %p ... %p)\n", __func__, context, stack, (char *)sp);
    rb_wasm_init_context(&context->fc, coroutine_trampoline, start, context);
    // record the initial stack pointer position to restore it after resumption
    context->current_sp = (char *)sp;
    context->stack_base = stack;
    context->size = size;
}

static inline struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target)
{
    if (ASYNCIFY_CORO_DEBUG) fprintf(stderr, "[%s] entry (current = %p, target = %p)\n", __func__, current, target);
    struct coroutine_context * previous = target->from;

    target->from = current;
    if (ASYNCIFY_CORO_DEBUG) fprintf(stderr, "[%s] current->current_sp = %p -> %p\n", __func__, current->current_sp, rb_wasm_get_stack_pointer());
    // record the current stack pointer position to restore it after resumption
    current->current_sp = rb_wasm_get_stack_pointer();

    // suspend the current coroutine and resume another coroutine

    rb_wasm_swapcontext(&current->fc, &target->fc);

    // after the original coroutine resumed

    rb_wasm_set_stack_pointer(current->current_sp);

    target->from = previous;

    return target;
}

static inline void coroutine_destroy(struct coroutine_context * context)
{
    if (ASYNCIFY_CORO_DEBUG) fprintf(stderr, "[%s] entry (context = %p)\n", __func__, context);
    context->stack_base = NULL;
    context->size = 0;
    context->from = NULL;
}

#endif /* COROUTINE_ASYNCIFY_CONTEXT_H */
