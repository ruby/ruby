#ifndef COROUTINE_ARM64_CONTEXT_H
#define COROUTINE_ARM64_CONTEXT_H 1

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

enum {COROUTINE_REGISTERS = 0xa0 / 8};

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

struct coroutine_context
{
    void **stack_pointer;
    void *argument;

#if defined(COROUTINE_SANITIZE_ADDRESS)
    void *fake_stack;
    void *stack_base;
    size_t stack_size;
#endif
};

typedef COROUTINE(* coroutine_start)(struct coroutine_context *from, struct coroutine_context *self);

static inline void coroutine_initialize_main(struct coroutine_context * context) {
    context->stack_pointer = NULL;
}

static inline void *ptrauth_sign_instruction_addr(void *addr, void *modifier) {
#if defined(__ARM_FEATURE_PAC_DEFAULT) && __ARM_FEATURE_PAC_DEFAULT != 0
    // Sign the given instruction address with the given modifier and key A
    register void *r17 __asm("r17") = addr;
    register void *r16 __asm("r16") = modifier;
    // Use HINT mnemonic instead of PACIA1716 for compatibility with older assemblers.
    __asm ("hint #8;" : "+r"(r17) : "r"(r16));
    addr = r17;
#else
    // No-op if PAC is not enabled
#endif
    return addr;
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

    // Stack grows down. Force 16-byte alignment.
    char * top = (char*)stack + size;
    top = (char *)((uintptr_t)top & ~0xF);
    context->stack_pointer = (void**)top;

    context->stack_pointer -= COROUTINE_REGISTERS;
    memset(context->stack_pointer, 0, sizeof(void*) * COROUTINE_REGISTERS);

    context->stack_pointer[0x98 / 8] = ptrauth_sign_instruction_addr((void*)start, (void*)top);
}

struct coroutine_context * coroutine_transfer(struct coroutine_context * current, struct coroutine_context * target);

static inline void coroutine_destroy(struct coroutine_context * context)
{
}

#endif /* COROUTINE_ARM64_CONTEXT_H */
