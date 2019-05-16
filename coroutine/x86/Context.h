/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 3/11/2018.
 *  Copyright, 2018, by Samuel Williams. All rights reserved.
*/

#pragma once

#include <assert.h>
#include <string.h>

#if __cplusplus
extern "C" {
#endif

#define COROUTINE __attribute__((noreturn, fastcall)) void

enum {COROUTINE_REGISTERS = 4};

typedef struct
{
    void **stack_pointer;
} coroutine_context;

typedef COROUTINE(* coroutine_start)(coroutine_context *from, coroutine_context *self) __attribute__((fastcall));

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

    *--context->stack_pointer = NULL;
    *--context->stack_pointer = (void*)start;

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);
}

coroutine_context * coroutine_transfer(coroutine_context * current, coroutine_context * target) __attribute__((fastcall));

static inline void coroutine_destroy(coroutine_context * context)
{
    context->stack_pointer = NULL;
}

#if __cplusplus
}
#endif
