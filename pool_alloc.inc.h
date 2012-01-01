/*
 * this is generic pool allocator
 * you should define following macroses:
 * ITEM_NAME - unique identifier, which allows to hold functions in a namespace
 * ITEM_TYPEDEF(name) - passed to typedef to localize item type
 * free_entry - desired name of function for free entry
 * alloc_entry - defired name of function for allocate entry
 */

#ifndef COMMON_POOL_TYPES
#define COMMON_POOL_TYPES 1

typedef unsigned int pool_free_counter;
typedef unsigned int pool_holder_counter;

typedef struct pool_entry_list pool_entry_list;
typedef struct pool_holder_header pool_holder_header;
typedef struct pool_holder pool_holder;

typedef struct pool_free_pointer {
    pool_entry_list     *free;
    pool_free_counter    count;
    pool_holder_counter  size; // size of entry in sizeof(void*) items
    pool_holder_counter  total; // size of entry in sizeof(void*) items
} pool_free_pointer;

struct pool_holder_header {
    pool_holder_counter free, total;
    pool_holder_counter size;
    pool_free_pointer  *free_pointer;
};

struct pool_entry_list {
    pool_holder *holder;
    pool_entry_list *fore, *back;
};
#define ENTRY(ptr) ((pool_entry_list*)(ptr))
#define ENTRY_DATA_OFFSET offsetof(pool_entry_list, fore)
#define VOID2ENTRY(ptr) ENTRY((char*)(ptr) - ENTRY_DATA_OFFSET)
#define ENTRY2VOID(ptr) ((void*)((char*)(ptr) + ENTRY_DATA_OFFSET))

struct pool_holder {
    pool_holder_header header;
    void *data[1];
};
#define POOL_DATA_SIZE ((4096 - sizeof(void*) * 3 - offsetof(pool_holder, data))/sizeof(void*))
#define POOL_HOLDER_SIZE (offsetof(pool_holder, data) + pointer->size*pointer->total*sizeof(void*)) 
#define POOL_ENTRY_SIZE(item_type) (((sizeof(item_type)+ENTRY_DATA_OFFSET-1)/sizeof(void*)+1))
#define POOL_HOLDER_COUNT(item_type) (POOL_DATA_SIZE/POOL_ENTRY_SIZE(item_type))
#define INIT_POOL(item_type) {NULL, 0, POOL_ENTRY_SIZE(item_type), POOL_HOLDER_COUNT(item_type)}

static void
pool_holder_alloc(pool_free_pointer *pointer)
{
    pool_holder *holder;
    pool_holder_counter i, size, count;
    register void **ptr;
#ifdef xgc_prepare
    size_t sz = xgc_prepare(POOL_HOLDER_SIZE);
    if (pointer->free != NULL) return;
    holder = (pool_holder*)xmalloc_prepared(sz);
#else
    holder = (pool_holder*)malloc(POOL_HOLDER_SIZE);
#endif 
    size = pointer->size;
    count = pointer->total;
    holder->header.free = count;
    holder->header.total = count;
    holder->header.size = size;
    holder->header.free_pointer = pointer;
    ptr = holder->data;
    ENTRY(ptr)->back = NULL;
    for(i = count - 1; i; i-- ) {
        ENTRY(ptr)->holder = holder;
        ENTRY(ptr)->fore = ENTRY(ptr + size);
        ENTRY(ptr + size)->back = ENTRY(ptr);
	ptr += size;
    }
    ENTRY(ptr)->holder = holder;
    ENTRY(ptr)->fore = pointer->free;
    pointer->free = ENTRY(holder->data);
    pointer->count += count;
}

static void
pool_holder_free(pool_holder *holder)
{
    pool_holder_counter i, size;
    void **ptr = holder->data;
    pool_free_pointer *pointer = holder->header.free_pointer;
    size = holder->header.size;
    
    for(i = holder->header.total; i; i--) {
	if (ENTRY(ptr)->fore) {
	    ENTRY(ptr)->fore->back = ENTRY(ptr)->back;
	}
	if (ENTRY(ptr)->back) {
	    ENTRY(ptr)->back->fore = ENTRY(ptr)->fore;
	} else {
	    pointer->free = ENTRY(ptr)->fore;
	}
	ptr += size;
    }
    pointer->count-= holder->header.total;
    free(holder);
}

static inline void
pool_free_entry(pool_entry_list *entry)
{
    pool_holder_header *holder = &entry->holder->header;
    pool_free_pointer *pointer = holder->free_pointer;
    entry->fore = pointer->free;
    entry->back = NULL;
    if (pointer->free) {
	pointer->free->back = entry;
    }
    pointer->free = entry;
    pointer->count++;
    holder->free++;
    if (holder->free == holder->total && pointer->count > holder->total * 16) {
        pool_holder_free(entry->holder);
    }
}

static inline pool_entry_list *
pool_alloc_entry(pool_free_pointer *pointer)
{
    pool_entry_list *result;
    if (pointer->free == NULL) {
        pool_holder_alloc(pointer);
    }
    result = pointer->free;
    pointer->free = result->fore;
    pointer->count--;
    result->holder->header.free--;
    return result;
}

static inline void
pool_free(void *p)
{
    pool_free_entry(VOID2ENTRY(p));
}

static inline void*
pool_alloc(pool_free_pointer *pointer)
{
    return ENTRY2VOID(pool_alloc_entry(pointer));
}

#undef ENTRY
#undef ENTRY2VOID
#undef VOID2ENTRY
#endif
