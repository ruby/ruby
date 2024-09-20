#include "Context.h"

void coroutine_trampoline(void * _start, void * _context)
{
    coroutine_start start = (coroutine_start)_start;
    struct coroutine_context * context = _context;
    rb_wasm_set_stack_pointer(context->current_sp);

    start(context->from, context);
}
