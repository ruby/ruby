#ifndef RB_WASM_SUPPORT_MACHINE_H
#define RB_WASM_SUPPORT_MACHINE_H

// Function pointer used as scan callbacks
typedef void (*rb_wasm_scan_func)(void*, void*);

// Scan WebAssembly locals in the all call stack (like registers) spilled by Asyncify
// Used by conservative GC
void rb_wasm_scan_locals(rb_wasm_scan_func scan);

// Scan userland C-stack memory space in WebAssembly. Used by conservative GC
#define rb_wasm_scan_stack(scan) _rb_wasm_scan_stack((scan), rb_wasm_get_stack_pointer())
void _rb_wasm_scan_stack(rb_wasm_scan_func scan, void *current);


// Get the current stack pointer
void *rb_wasm_get_stack_pointer(void);

// Set the current stack pointer
void rb_wasm_set_stack_pointer(void *sp);

// Returns the Asyncify buffer of next rewinding if unwound for spilling locals.
// Used by the top level Asyncify handling in wasm/runtime.c
void *rb_wasm_handle_scan_unwind(void);

#endif
