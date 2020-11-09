/*
 *  This file is part of the "Coroutine" project and released under the MIT License.
 *
 *  Created by Samuel Williams on 10/11/2020.
 *  Copyright, 2020, by Samuel Williams.
*/

#include COROUTINE_H

#ifdef COROUTINE_PRIVATE_STACK
#define COROUTINE_STACK_LOCAL(type, name) type *name = ruby_xmalloc(sizeof(type))
#define COROUTINE_STACK_FREE(name) ruby_xfree(name)
#else
#define COROUTINE_STACK_LOCAL(type, name) type name##_local; type * name = &name##_local
#define COROUTINE_STACK_FREE(name)
#endif
