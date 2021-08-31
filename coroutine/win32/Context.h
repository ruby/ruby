#ifndef COROUTINE_WIN32_CONTEXT_H
#define COROUTINE_WIN32_CONTEXT_H 1

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

#define COROUTINE __declspec(noreturn) void __fastcall
#define COROUTINE_LIMITED_ADDRESS_SPACE

/* This doesn't include thread information block */
enum {COROUTINE_REGISTERS = 4};

struct coroutine_context
{
    void **stack_pointer;
    void *argument;
};

typedef void(__fastcall * coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

static inline void coroutine_initialize_main(struct coroutine_context * context) {
    context->stack_pointer = NULL;
}

static inline void coroutine_initialize(
    struct coroutine_context *context,
    coroutine_start start,
    void *stack,
    size_t size
) {
    assert(start && stack && size >= 1024);

    // Stack grows down. Force 16-byte alignment.
    char * top = (char*)stack + size;
    context->stack_pointer = (void**)((uintptr_t)top & ~0xF);

    *--context->stack_pointer = (void*)start;

    /* Windows Thread Information Block */
    *--context->stack_pointer = (void*)0xFFFFFFFF; /* fs:[0] */
    *--context->stack_pointer = (void*)top; /* fs:[4] */
    *--context->stack_pointer = (void*)stack;  /* fs:[8] */

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);
}

struct coroutine_context * __fastcall coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target);

static inline void coroutine_destroy(struct coroutine_context * context)
{
}

#endif /* COROUTINE_WIN32_CONTEXT_H */
