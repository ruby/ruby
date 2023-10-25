/*
 This is a ucontext-like userland context switching API for WebAssembly based on Binaryen's Asyncify.

 * NOTE:
 * This mechanism doesn't take care of stack state. Just save and restore program counter and
 * registers (rephrased as locals by Wasm term). So use-site need to save and restore the C stack pointer.
 * This Asyncify based implementation is not much efficient and will be replaced with future stack-switching feature.
 */

#include <stdlib.h>
#include "wasm/fiber.h"
#include "wasm/asyncify.h"

#ifdef RB_WASM_ENABLE_DEBUG_LOG
# include <stdio.h>
# define RB_WASM_DEBUG_LOG(...) fprintf(stderr, __VA_ARGS__)
#else
# define RB_WASM_DEBUG_LOG(...)
#endif

void
rb_wasm_init_context(rb_wasm_fiber_context *fcp, void (*func)(void *, void *), void *arg0, void *arg1)
{
    fcp->asyncify_buf.top = &fcp->asyncify_buf.buffer[0];
    fcp->asyncify_buf.end = &fcp->asyncify_buf.buffer[WASM_FIBER_STACK_BUFFER_SIZE];
    fcp->is_rewinding = false;
    fcp->is_started = false;
    fcp->entry_point = func;
    fcp->arg0 = arg0;
    fcp->arg1 = arg1;
    RB_WASM_DEBUG_LOG("[%s] fcp->asyncify_buf %p\n", __func__, &fcp->asyncify_buf);
}

static rb_wasm_fiber_context *_rb_wasm_active_next_fiber;

void
rb_wasm_swapcontext(rb_wasm_fiber_context *ofcp, rb_wasm_fiber_context *fcp)
{
    RB_WASM_DEBUG_LOG("[%s] enter ofcp = %p fcp = %p\n", __func__, ofcp, fcp);
    if (ofcp->is_rewinding) {
        asyncify_stop_rewind();
        ofcp->is_rewinding = false;
        return;
    }
    _rb_wasm_active_next_fiber = fcp;
    RB_WASM_DEBUG_LOG("[%s] start unwinding asyncify_buf = %p\n", __func__, &ofcp->asyncify_buf);
    asyncify_start_unwind(&ofcp->asyncify_buf);
}

void *
rb_wasm_handle_fiber_unwind(void (**new_fiber_entry)(void *, void *),
                            void **arg0, void **arg1, bool *is_new_fiber_started)
{
    rb_wasm_fiber_context *next_fiber;
    if (!_rb_wasm_active_next_fiber) {
        RB_WASM_DEBUG_LOG("[%s] no next fiber\n", __func__);
        *is_new_fiber_started = false;
        return NULL;
    }

    next_fiber = _rb_wasm_active_next_fiber;
    _rb_wasm_active_next_fiber = NULL;

    RB_WASM_DEBUG_LOG("[%s] next_fiber->asyncify_buf = %p\n", __func__, &next_fiber->asyncify_buf);

    *new_fiber_entry = next_fiber->entry_point;
    *arg0 = next_fiber->arg0;
    *arg1 = next_fiber->arg1;

    if (!next_fiber->is_started) {
        RB_WASM_DEBUG_LOG("[%s] new fiber started\n", __func__);
        // start a new fiber if not started yet.
        next_fiber->is_started = true;
        *is_new_fiber_started = true;
        return NULL;
    } else {
        RB_WASM_DEBUG_LOG("[%s] resume a fiber\n", __func__);
        // resume a fiber again
        next_fiber->is_rewinding = true;
        *is_new_fiber_started = false;
        return &next_fiber->asyncify_buf;
    }
}
