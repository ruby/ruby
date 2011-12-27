/*
 * this is generic pool allocator
 * you should define following macroses:
 * ITEM_NAME - unique identifier, which allows to hold functions in a namespace
 * ITEM_TYPEDEF(name) - passed to typedef to localize item type
 * free_entry - desired name of function for free entry
 * alloc_entry - defired name of function for allocate entry
 */

#define NAME_(prefix, kind) sta_##prefix##_##kind
#define NAME(prefix, kind) NAME_(prefix, kind)

#define holder_typename NAME(holder, ITEM_NAME)
#define entry_typename NAME(entry, ITEM_NAME)
#define list_typename NAME(list, ITEM_NAME)
#define union_typename NAME(union, ITEM_NAME)
#define item_type NAME(item, ITEM_NAME)

typedef ITEM_TYPEDEF(item_type);
typedef struct holder_typename holder_typename;
typedef struct entry_typename entry_typename;

typedef struct list_typename {
    entry_typename *fore, *back;
} list_typename;

typedef union union_typename {
    list_typename l;
    item_type item;
} union_typename;

struct entry_typename {
    union_typename p;
    holder_typename *holder;
};

#define HOLDER_SIZE (4096 / sizeof(entry_typename) - 1)
struct holder_typename {
    unsigned int free;
    entry_typename items[HOLDER_SIZE];
};

#define free_entry_p NAME(free_pointer, ITEM_NAME)
#define free_entry_count NAME(count, ITEM_NAME)
static entry_typename *free_entry_p = NULL;
static unsigned long free_entry_count = 0;

#define entry_chain NAME(chain, ITEM_NAME)
#define holder_alloc NAME(holder_alloc, ITEM_NAME)
#define holder_free NAME(holder_free, ITEM_NAME)
#define fore p.l.fore
#define back p.l.back

static inline void
entry_chain(entry_typename *entry)
{
    entry->fore = free_entry_p;
    entry->back = NULL;
    if (free_entry_p) {
	free_entry_p->back = entry;
    }
    free_entry_p = entry;
}

static void
holder_alloc()
{
    holder_typename *holder = alloc(holder_typename);
    unsigned int i;
    holder->free = HOLDER_SIZE;
    for(i = 0; i < HOLDER_SIZE; i++) {
	holder->items[i].holder = holder;
	entry_chain(&holder->items[i]);
    }
    free_entry_count+= HOLDER_SIZE;
}

static void
holder_free(holder_typename *holder)
{
    unsigned int i;
    entry_typename *ptr;
    for(i = 0; i < HOLDER_SIZE; i++) {
	ptr = &holder->items[i];
	if (ptr->fore) {
	    ptr->fore->back = ptr->back;
	}
	if (ptr->back) {
	    ptr->back->fore = ptr->fore;
	} else {
	    free_entry_p = ptr->fore;
	}
    }
    free_entry_count-= HOLDER_SIZE;
    free(holder);
}

static void
free_entry(item_type *entry)
{
    holder_typename *holder = ((entry_typename *)entry)->holder;
    entry_chain((entry_typename *)entry);
    holder->free++;
    free_entry_count++;
    if (holder->free == HOLDER_SIZE && free_entry_count > HOLDER_SIZE) {
	holder_free(holder);
    }
}

static item_type *
alloc_entry()
{
    entry_typename *result;
    if (!free_entry_p) {
	holder_alloc();
    }
    result = free_entry_p;
    free_entry_p = result->fore;
    result->holder->free--;
    free_entry_count--;
    return (item_type *)result;
}



#undef NAME_
#undef NAME
#undef holder_typename
#undef entry_typename
#undef list_typename
#undef union_typename
#undef item_type
#undef free_entry_p
#undef free_entry_count
#undef HOLDER_SIZE
#undef entry_chain
#undef holder_alloc
#undef holdef_free
#undef fore
#undef back
