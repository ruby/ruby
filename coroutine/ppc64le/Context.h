#pragma once

#include <assert.h>
#include <string.h>

#if __cplusplus
extern "C" {
#endif

#define COROUTINE __attribute__((noreturn)) void

enum {
  COROUTINE_REGISTERS =
  19  /* 18 general purpose registers (r14-r31) and 1 return address */
  + 4  /* space for fiber_entry() to store the link register */
};

typedef struct
{
    void **stack_pointer;
} coroutine_context;

typedef COROUTINE(* coroutine_start)(coroutine_context *from, coroutine_context *self);

static inline void coroutine_initialize(
    coroutine_context *context,
    coroutine_start start,
    void *stack_pointer,
    size_t stack_size
) {
    /* Force 16-byte alignment */
    context->stack_pointer = (void**)((uintptr_t)stack_pointer & ~0xF);

    if (!start) {
        assert(!context->stack_pointer);
        /* We are main coroutine for this thread */
        return;
    }

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);

    /* Skip a global prologue that sets the TOC register */
    context->stack_pointer[18] = ((char*)start) + 8;
}

coroutine_context * coroutine_transfer(coroutine_context * current, coroutine_context * target);

static inline void coroutine_destroy(coroutine_context * context)
{
    context->stack_pointer = NULL;
}

#if __cplusplus
}
#endif
