/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 10/5/2018.
 *  Copyright, 2018, by Samuel Williams. All rights reserved.
*/

#pragma once

#include <assert.h>
#include <string.h>

#if __cplusplus
extern "C" {
#endif

#define COROUTINE __declspec(noreturn) void

enum {
    COROUTINE_REGISTERS = 8,
    COROUTINE_XMM_REGISTERS = 1+10*2,
};

typedef struct
{
    void **stack_pointer;
} coroutine_context;

typedef void(* coroutine_start)(coroutine_context *from, coroutine_context *self);

void coroutine_trampoline();

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

    /* Win64 ABI requires space for arguments */
    context->stack_pointer -= 4;

    /* Return address */
    *--context->stack_pointer = 0;
    *--context->stack_pointer = (void*)start;
    *--context->stack_pointer = (void*)coroutine_trampoline;

    /* Windows Thread Information Block */
    /* *--context->stack_pointer = 0; */ /* gs:[0x00] is not used */
    *--context->stack_pointer = (void*)stack_pointer; /* gs:[0x08] */
    *--context->stack_pointer = (void*)((char *)stack_pointer - stack_size);  /* gs:[0x10] */

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);
    memset(context->stack_pointer - COROUTINE_XMM_REGISTERS, 0, sizeof(void*) * COROUTINE_XMM_REGISTERS);
}

coroutine_context * coroutine_transfer(coroutine_context * current, coroutine_context * target);

static inline void coroutine_destroy(coroutine_context * context)
{
}

#if __cplusplus
}
#endif
