/**********************************************************************

  new_gc.c - Implement New GC

  Copyright (C) 2020 Jacob Matthews

**********************************************************************/

struct new_heap {
  int total_blocks;
};

static struct new_heap global_new_heap;

static struct new_heap*
new_heap_get(void)
{
    struct new_heap* heap = &global_new_heap;
    //new_heap_verify(heap);
    return heap;
}

void
Init_NewHeap(void)
{
    struct new_heap* heap = new_heap_get();
}
