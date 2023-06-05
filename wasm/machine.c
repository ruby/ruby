#include <stdlib.h>
#include "wasm/machine.h"
#include "wasm/asyncify.h"

#ifndef WASM_SCAN_STACK_BUFFER_SIZE
# define WASM_SCAN_STACK_BUFFER_SIZE 6144
#endif

struct asyncify_buf {
    void *top;
    void *end;
    uint8_t buffer[WASM_SCAN_STACK_BUFFER_SIZE];
};

static void
init_asyncify_buf(struct asyncify_buf* buf)
{
    buf->top = &buf->buffer[0];
    buf->end = &buf->buffer[WASM_SCAN_STACK_BUFFER_SIZE];
}

static void *_rb_wasm_active_scan_buf = NULL;

void
rb_wasm_scan_locals(rb_wasm_scan_func scan)
{
    static struct asyncify_buf buf;
    static int spilling = 0;
    if (!spilling) {
        spilling = 1;
        init_asyncify_buf(&buf);
        _rb_wasm_active_scan_buf = &buf;
        asyncify_start_unwind(&buf);
    } else {
        asyncify_stop_rewind();
        spilling = 0;
        _rb_wasm_active_scan_buf = NULL;
        scan(buf.top, buf.end);
    }
}

static void *rb_wasm_stack_base = NULL;

__attribute__((constructor))
int
rb_wasm_record_stack_base(void)
{
    rb_wasm_stack_base = rb_wasm_get_stack_pointer();
    return 0;
}

void *
rb_wasm_stack_get_base(void)
{
    return rb_wasm_stack_base;
}

void *
rb_wasm_handle_scan_unwind(void)
{
    return _rb_wasm_active_scan_buf;
}
