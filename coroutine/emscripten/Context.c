#include "Context.h"

void coroutine_trampoline(void * _context)
{
    struct coroutine_context * context = _context;

    context->entry_func(context->from, context);
}
