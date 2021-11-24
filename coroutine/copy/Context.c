/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 24/6/2019.
 *  Copyright, 2019, by Samuel Williams.
*/

#include "Context.h"

#include <stdint.h>

// http://gcc.gnu.org/onlinedocs/gcc/Alternate-Keywords.html
#ifndef __GNUC__
#define __asm__ asm
#endif

#if defined(__sparc)
__attribute__((noinline))
// https://marc.info/?l=linux-sparc&m=131914569320660&w=2
static void coroutine_flush_register_windows() {
    __asm__
#ifdef __GNUC__
    __volatile__
#endif
#if defined(__sparcv9) || defined(__sparc_v9__) || defined(__arch64__)
#ifdef __GNUC__
    ("flushw" : : : "%o7")
#else
    ("flushw")
#endif
#else
    ("ta 0x03")
#endif
    ;
}
#else
static void coroutine_flush_register_windows() {}
#endif

__attribute__((noinline))
void *coroutine_stack_pointer() {
    return (void*)(
        (char*)__builtin_frame_address(0)
    );
}

// Save the current stack to a private area. It is likely that when restoring the stack, this stack frame will be incomplete. But that is acceptable since the previous stack frame which called `setjmp` should be correctly restored.
__attribute__((noinline))
int coroutine_save_stack_1(struct coroutine_context * context) {
    assert(context->stack);
    assert(context->base);

    void *stack_pointer = coroutine_stack_pointer();

    // At this point, you may need to ensure on architectures that use register windows, that all registers are flushed to the stack, otherwise the copy of the stack will not contain the valid registers:
    coroutine_flush_register_windows();

    // Save stack to private area:
    if (stack_pointer < context->base) {
        size_t size = (char*)context->base - (char*)stack_pointer;
        assert(size <= context->size);

        memcpy(context->stack, stack_pointer, size);
        context->used = size;
    } else {
        size_t size = (char*)stack_pointer - (char*)context->base;
        assert(size <= context->size);

        memcpy(context->stack, context->base, size);
        context->used = size;
    }

    // Initialized:
    return 0;
}

// Copy the current stack to a private memory buffer.
int coroutine_save_stack(struct coroutine_context * context) {
    if (_setjmp(context->state)) {
        // Restored.
        return 1;
    }

    // We need to invoke the memory copy from one stack frame deeper than the one that calls setjmp. That is because if you don't do this, the setjmp might be restored into an invalid stack frame (truncated, etc):
    return coroutine_save_stack_1(context);
}

__attribute__((noreturn, noinline))
void coroutine_restore_stack_padded(struct coroutine_context *context, void * buffer) {
    void *stack_pointer = coroutine_stack_pointer();

    assert(context->base);

    // At this point, you may need to ensure on architectures that use register windows, that all registers are flushed to the stack, otherwise when we copy in the new stack, the registers would not be updated:
    coroutine_flush_register_windows();

    // Restore stack from private area:
    if (stack_pointer < context->base) {
        void * bottom = (char*)context->base - context->used;
        assert(bottom > stack_pointer);

        memcpy(bottom, context->stack, context->used);
    } else {
        void * top = (char*)context->base + context->used;
        assert(top < stack_pointer);

        memcpy(context->base, context->stack, context->used);
    }

    // Restore registers. The `buffer` is to force the compiler NOT to elide he buffer and `alloca`:
    _longjmp(context->state, (int)(1 | (intptr_t)buffer));
}

// In order to swap between coroutines, we need to swap the stack and registers.
// `setjmp` and `longjmp` are able to swap registers, but what about swapping stacks? You can use `memcpy` to copy the current stack to a private area and `memcpy` to copy the private stack of the next coroutine to the main stack.
// But if the stack yop are copying in to the main stack is bigger than the currently executing stack, the `memcpy` will clobber the current stack frame (including the context argument). So we use `alloca` to push the current stack frame *beyond* the stack we are about to copy in. This ensures the current stack frame in `coroutine_restore_stack_padded` remains valid for calling `longjmp`.
__attribute__((noreturn))
void coroutine_restore_stack(struct coroutine_context *context) {
    void *stack_pointer = coroutine_stack_pointer();
    void *buffer = NULL;

    // We must ensure that the next stack frame is BEYOND the stack we are restoring:
    if (stack_pointer < context->base) {
        intptr_t offset = (intptr_t)stack_pointer - ((intptr_t)context->base - context->used);
        if (offset > 0) buffer = alloca(offset);
    } else {
        intptr_t offset = ((intptr_t)context->base + context->used) - (intptr_t)stack_pointer;
        if (offset > 0) buffer = alloca(offset);
    }

    assert(context->used > 0);

    coroutine_restore_stack_padded(context, buffer);
}

struct coroutine_context *coroutine_transfer(struct coroutine_context *current, struct coroutine_context *target)
{
    struct coroutine_context *previous = target->from;

    // In theory, either this condition holds true, or we should assign the base address to target:
    assert(current->base == target->base);
    // If you are trying to copy the coroutine to a different thread
    // target->base = current->base

    target->from = current;

    assert(current != target);

    // It's possible to come here, even thought the current fiber has been terminated. We are never going to return so we don't bother saving the stack.

    if (current->stack) {
        if (coroutine_save_stack(current) == 0) {
            coroutine_restore_stack(target);
        }
    } else {
        coroutine_restore_stack(target);
    }

    target->from = previous;

    return target;
}
