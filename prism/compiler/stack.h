/**
 * @file compiler/stack.h
 */
#ifndef PRISM_COMPILER_STACK_H
#define PRISM_COMPILER_STACK_H

#include "prism/compiler/inline.h"

#include <stdint.h>

#if defined(__has_builtin)
    #if __has_builtin(__builtin_stack_address)
        #define PRISM_HAS_BUILTIN_STACK_ADDRESS
    #endif
#endif

#if defined(_MSC_VER)
    #include <intrin.h>
#endif

/**
 * Returns the current position of the C stack, for measuring how much of it has
 * been consumed since an earlier call. The stack pointer is read directly where
 * the compiler or architecture allows it. Unlike __builtin_frame_address, that
 * does not force the calling function to set up a frame pointer, which costs a
 * register on targets that omit frame pointers by default (x86-64 at -O2), and
 * unlike the address of a local it does not add a slot to the frame.
 */
static PRISM_INLINE uintptr_t
pm_stack_address(void) {
#if defined(PRISM_HAS_BUILTIN_STACK_ADDRESS)
    return (uintptr_t) __builtin_stack_address();
#elif defined(_MSC_VER) && defined(_M_ARM64)
    return (uintptr_t) __getReg(31);
#elif defined(_MSC_VER)
    return (uintptr_t) _AddressOfReturnAddress();
#elif defined(__GNUC__) && defined(__x86_64__)
    uintptr_t sp;
    __asm__ ("{movq %%rsp, %0|mov %0, rsp}" : "=r" (sp));
    return sp;
#elif defined(__GNUC__) && defined(__aarch64__)
    /* The register is 64 bits even where pointers are 32 (arm64_32). */
    uint64_t sp;
    __asm__ ("mov %0, sp" : "=r" (sp));
    return (uintptr_t) sp;
#elif defined(__GNUC__)
    return (uintptr_t) __builtin_frame_address(0);
#else
    volatile char marker = 0;
    return (uintptr_t) &marker;
#endif
}

#endif
