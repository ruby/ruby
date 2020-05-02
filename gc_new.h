#ifndef RUBY_NEW_HEAP_H
#define RUBY_NEW_HEAP_H

/**********************************************************************

  new_gc.h

  Copyright (C) 2020 Jacob Matthews

**********************************************************************/

#include "internal.h"

#ifndef USE_NEW_HEAP
# define USE_NEW_HEAP 1
#endif

/* public API */

/* Allocate req_size bytes from the new heap */
void *rb_new_heap_alloc(VALUE obj, size_t req_size);

#endif
