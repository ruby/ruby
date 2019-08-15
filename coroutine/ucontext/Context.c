/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 24/6/2019.
 *  Copyright, 2019, by Samuel Williams. All rights reserved.
*/

#include "Context.h"

void coroutine_trampoline(void * _start, void * _context)
{
    coroutine_start start = _start;
    struct coroutine_context * context = _context;

    start(context->from, context);
}
