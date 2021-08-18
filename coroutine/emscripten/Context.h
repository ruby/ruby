#ifndef COROUTINE_EMSCRIPTEN_CONTEXT_H
#define COROUTINE_EMSCRIPTEN_CONTEXT_H 1

/* An experimental coroutine wrapper for emscripten
 * Contact on Yusuke Endoh if you encounter any problem about this
 */

#pragma once

#include <assert.h>
#include <stddef.h>
#include <emscripten/fiber.h>

#define COROUTINE __attribute__((noreturn)) void

#if INTPTR_MAX <= INT32_MAX
#define COROUTINE_LIMITED_ADDRESS_SPACE
#endif

struct coroutine_context;

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

struct coroutine_context
{
    emscripten_fiber_t state;
    coroutine_start entry_func;
    struct coroutine_context * from;
    void *argument;
};

COROUTINE coroutine_trampoline(void * _context);

#define MAIN_ASYNCIFY_STACK_SIZE 65536
static inline void coroutine_initialize_main(struct coroutine_context * context) {
    static char asyncify_stack[MAIN_ASYNCIFY_STACK_SIZE];
    emscripten_fiber_init_from_current_context(&context->state, asyncify_stack, MAIN_ASYNCIFY_STACK_SIZE);
}
#undef MAIN_ASYNCIFY_STACK_SIZE

static inline void coroutine_initialize(
    struct coroutine_context *context,
    coroutine_start start,
    void *stack,
    size_t size
) {
    assert(start && stack && size >= 1024);

    uintptr_t addr = (uintptr_t)stack;
    size_t offset = addr & 0xF;
    void *c_stack = (void*)((addr + 0xF) & ~0xF);
    size -= offset;
    size_t c_stack_size = (size / 2) & ~0xF;
    void *asyncify_stack = (void*)((uintptr_t)c_stack + c_stack_size);
    size_t asyncify_stack_size = size - c_stack_size;
    context->entry_func = start;

    emscripten_fiber_init(&context->state, coroutine_trampoline, context, c_stack, c_stack_size, asyncify_stack, asyncify_stack_size);
}

static inline struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target)
{
    struct coroutine_context * previous = target->from;

    target->from = current;
    emscripten_fiber_swap(&current->state, &target->state);
    target->from = previous;

    return target;
}

static inline void coroutine_destroy(struct coroutine_context * context)
{
    context->from = NULL;
}

#endif /* COROUTINE_EMSCRIPTEN_CONTEXT_H */
