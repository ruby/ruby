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

typedef void pool_holder_alloc_f();
typedef void pool_holder_free_f(pool_holder_header *);
typedef struct pool_free_pointer {
    pool_entry_list     *free;
    pool_free_counter    count;
    pool_holder_alloc_f *alloc_holder;
    pool_holder_free_f  *free_holder;
} pool_free_pointer;

struct pool_holder_header {
    pool_holder_counter free, total;
    pool_holder_counter size;
    pool_free_pointer  *free_pointer;
};

struct pool_entry_list {
    pool_holder_header *holder;
    pool_entry_list *fore, *back;
};

static inline void
pool_free_entry(pool_entry_list *entry)
{
    pool_holder_header *holder = entry->holder;
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
        pointer->free_holder(holder);
    }
}

static inline pool_entry_list *
pool_alloc_entry(pool_free_pointer *pointer)
{
    pool_entry_list *result;
    if (pointer->free == NULL) {
        pointer->alloc_holder();
    }
    result = pointer->free;
    pointer->free = result->fore;
    pointer->count--;
    result->holder->free--;
    return result;
}

#endif

#define NAME_(prefix, kind) sta_##prefix##_##kind
#define NAME(prefix, kind) NAME_(prefix, kind)

#define holder_typename NAME(holder, ITEM_NAME)
#define entry_typename NAME(entry, ITEM_NAME)
#define union_typename NAME(union, ITEM_NAME)
#define item_type NAME(item, ITEM_NAME)

typedef ITEM_TYPEDEF(item_type);
typedef struct holder_typename holder_typename;
typedef struct entry_typename entry_typename;

struct entry_typename {
    pool_holder_header  *holder;
    item_type item;
};

typedef union union_typename {
    entry_typename  entry;
    pool_entry_list list;
} union_typename;

#define HOLDER_SIZE ((4096 - sizeof(void*) * 2 - sizeof(pool_holder_header)) / sizeof(union_typename) )
struct holder_typename {
    pool_holder_header  header;
    union_typename items[HOLDER_SIZE];
};

#define pool_pointer NAME(pool_pointer, ITEM_NAME)
#define holder_alloc NAME(holder_alloc, ITEM_NAME)
#define holder_free NAME(holder_free, ITEM_NAME)

static pool_holder_alloc_f holder_alloc;
static pool_holder_free_f  holder_free;
static pool_free_pointer pool_pointer = {NULL, 0, holder_alloc, holder_free};

static void
holder_alloc()
{
    holder_typename *holder;
    unsigned int i;
    register union_typename *ptr;
#ifdef xgc_prepare
    size_t sz = xgc_prepare(sizeof(holder_typename));
    if (pool_pointer.free != NULL) return;
    holder = (holder_typename*)xmalloc_prepared(sz);
#else
    holder = alloc(holder_typename);
#endif 
    ptr = holder->items;
    holder->header.free = HOLDER_SIZE;
    holder->header.total = HOLDER_SIZE;
    holder->header.size = sizeof(union_typename);
    holder->header.free_pointer = &pool_pointer;
    for(i = HOLDER_SIZE - 1; i; ptr++, i-- ) {
        ptr->list.holder = &holder->header;
        ptr->list.fore = &(ptr + 1)->list;
        (ptr + 1)->list.back = &ptr->list;
    }
    holder->items[0].list.back = NULL;
    holder->items[HOLDER_SIZE - 1].list.holder = &holder->header;
    holder->items[HOLDER_SIZE - 1].list.fore = pool_pointer.free;
    pool_pointer.free = &holder->items[0].list;
    pool_pointer.count += HOLDER_SIZE;
}

static void
holder_free(pool_holder_header *holder)
{
    unsigned int i;
    union_typename *ptr = ((holder_typename *)holder)->items;
    for(i = HOLDER_SIZE; i; i--, ptr++) {
	if (ptr->list.fore) {
	    ptr->list.fore->back = ptr->list.back;
	}
	if (ptr->list.back) {
	    ptr->list.back->fore = ptr->list.fore;
	} else {
	    pool_pointer.free = ptr->list.fore;
	}
    }
    pool_pointer.count-= HOLDER_SIZE;
    free(holder);
}

static void
free_entry(item_type *item)
{
    pool_entry_list *entry = (pool_entry_list *)(((char *)item) - offsetof(entry_typename, item));
    pool_free_entry(entry);
}

static item_type *
alloc_entry()
{
    pool_entry_list *result = pool_alloc_entry(&pool_pointer);
    return &((entry_typename *)result)->item;
}



#undef NAME_
#undef NAME
#undef holder_typename
#undef entry_typename
#undef union_typename
#undef item_type
#undef pool_pointer
#undef HOLDER_SIZE
#undef holder_alloc
#undef holdef_free
