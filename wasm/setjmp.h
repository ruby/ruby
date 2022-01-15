#ifndef RB_WASM_SUPPORT_SETJMP_H
#define RB_WASM_SUPPORT_SETJMP_H

#include "ruby/internal/config.h"
#include <stdbool.h>

#ifndef WASM_SETJMP_STACK_BUFFER_SIZE
# define WASM_SETJMP_STACK_BUFFER_SIZE 6144
#endif

struct __rb_wasm_asyncify_jmp_buf {
    void* top;
    void* end;
    char buffer[WASM_SETJMP_STACK_BUFFER_SIZE];
};

typedef struct {
    // Internal Asyncify buffer space to save execution context
    struct __rb_wasm_asyncify_jmp_buf setjmp_buf;
    // Internal Asyncify buffer space used while unwinding from longjmp
    // but never used for rewinding.
    struct __rb_wasm_asyncify_jmp_buf longjmp_buf;
    // Used to save top address of Asyncify stack `setjmp_buf`, which is
    // overwritten during first rewind.
    void *dst_buf_top;
    // A payload value given by longjmp and returned by setjmp for the second time
    int payload;
    // Internal state field
    int state;
} rb_wasm_jmp_buf;

// noinline to avoid breaking Asyncify assumption
NOINLINE(int _rb_wasm_setjmp(rb_wasm_jmp_buf *env));
NOINLINE(void _rb_wasm_longjmp(rb_wasm_jmp_buf *env, int payload));

#define rb_wasm_setjmp(env) ((env).state = 0, _rb_wasm_setjmp(&(env)))

// NOTE: Why is `_rb_wasm_longjmp` not `noreturn`? Why put `unreachable` in the call site?
// Asyncify expects that `_rb_wasm_longjmp` returns its control, and Asyncify inserts a return
// for unwinding after the call. This means that "`_rb_wasm_longjmp` returns its control but the
// next line in the caller (C level) won't be executed".
// On the other hand, `noreturn` means the callee won't return its control to the caller,
// so compiler can assume that a function with the attribute won't reach the end of the function.
// Therefore `_rb_wasm_longjmp`'s semantics is not exactly same as `noreturn`.
#define rb_wasm_longjmp(env, payload) (_rb_wasm_longjmp(&env, payload), __builtin_unreachable())

// Returns the Asyncify buffer of next rewinding if unwound for setjmp capturing or longjmp.
// Used by the top level Asyncify handling in wasm/runtime.c
void *rb_wasm_handle_jmp_unwind(void);


//
// POSIX-compatible declarations
//

typedef rb_wasm_jmp_buf jmp_buf;

#define setjmp(env) rb_wasm_setjmp(env)
#define longjmp(env, payload) rb_wasm_longjmp(env, payload)

#endif
