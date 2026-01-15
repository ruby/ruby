#ifndef RB_WASM_SUPPORT_FIBER_H
#define RB_WASM_SUPPORT_FIBER_H

#include <stdbool.h>

#ifndef WASM_FIBER_STACK_BUFFER_SIZE
# define WASM_FIBER_STACK_BUFFER_SIZE 6144
#endif

struct __rb_wasm_asyncify_fiber_ctx {
    void* top;
    void* end;
    char buffer[WASM_FIBER_STACK_BUFFER_SIZE];
};

// Fiber execution context needed to perform context switch
typedef struct {
    // Fiber entry point called when the fiber started for the first time.
    // NULL if the entry point is main
    void (*entry_point)(void *, void *);
    // Opaque argument pointers passed to the entry point function
    void *arg0, *arg1;

    // Internal asyncify buffer space
    struct __rb_wasm_asyncify_fiber_ctx asyncify_buf;

    bool is_rewinding;
    bool is_started;
} rb_wasm_fiber_context;

// Initialize a given fiber context to be ready to pass to `rb_wasm_swapcontext`
void rb_wasm_init_context(rb_wasm_fiber_context *fcp, void (*func)(void *, void *), void *arg0, void *arg1);

// Swap the execution control with `target_fiber` and save the current context in `old_fiber`
// NOTE: `old_fiber` must be the current executing fiber context
void rb_wasm_swapcontext(rb_wasm_fiber_context *old_fiber, rb_wasm_fiber_context *target_fiber);

// Returns the Asyncify buffer of next fiber if unwound for fiber context switch.
// Used by the top level Asyncify handling in wasm/runtime.c
void *rb_wasm_handle_fiber_unwind(void (**new_fiber_entry)(void *, void *),
                                  void **arg0, void **arg1, bool *is_new_fiber_started);

#endif
