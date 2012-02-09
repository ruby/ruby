#ifndef POOL_ALLOC_H
#define POOL_ALLOC_H

#define POOL_ALLOC_API
#ifdef POOL_ALLOC_API
void  ruby_xpool_free(void *ptr);
void *ruby_xpool_malloc_6p();
void *ruby_xpool_malloc_11p();
#endif

#endif
