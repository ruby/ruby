#ifndef RUBY_DARRAY_H
#define RUBY_DARRAY_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>

// Type for a dynamic array. Use to declare a dynamic array.
// It is a pointer so it fits in st_table nicely. Designed
// to be fairly type-safe.
//
// NULL is a valid empty dynamic array.
//
// Example:
//      rb_darray(char) char_array = NULL;
//      rb_darray_append(&char_array, 'e');
//      printf("pushed %c\n", *rb_darray_ref(char_array, 0));
//      rb_darray_free(char_array);
//
#define rb_darray(T) struct { rb_darray_meta_t meta; T data[]; } *

// Copy an element out of the array. Warning: not bounds checked.
//
// T rb_darray_get(rb_darray(T) ary, size_t idx);
//
#define rb_darray_get(ary, idx) ((ary)->data[(idx)])

// Assign to an element. Warning: not bounds checked.
//
// void rb_darray_set(rb_darray(T) ary, size_t idx, T element);
//
#define rb_darray_set(ary, idx, element) ((ary)->data[(idx)] = (element))

// Get a pointer to an element. Warning: not bounds checked.
//
// T *rb_darray_ref(rb_darray(T) ary, size_t idx);
//
#define rb_darray_ref(ary, idx) (&((ary)->data[(idx)]))

// Copy a new element into the array. ptr_to_ary is evaluated multiple times.
//
// void rb_darray_append(rb_darray(T) *ptr_to_ary, T element);
//
#define rb_darray_append(ptr_to_ary, element) do {  \
    rb_darray_ensure_space((ptr_to_ary), sizeof(**(ptr_to_ary)), \
                           sizeof((*(ptr_to_ary))->data[0])); \
    rb_darray_set(*(ptr_to_ary), \
                  (*(ptr_to_ary))->meta.size, \
                  (element)); \
    (*(ptr_to_ary))->meta.size++; \
} while (0)


// Last element of the array
//
#define rb_darray_back(ary) ((ary)->data[(ary)->meta.size - 1])

// Remove the last element of the array.
//
#define rb_darray_pop_back(ary) ((ary)->meta.size--)

// Remove element at idx and replace it by the last element
#define rb_darray_remove_unordered(ary, idx) do {   \
    rb_darray_set(ary, idx, rb_darray_back(ary));   \
    rb_darray_pop_back(ary);                        \
} while (0);

// Iterate over items of the array in a for loop
//
#define rb_darray_foreach(ary, idx_name, elem_ptr_var) \
    for (size_t idx_name = 0; idx_name < rb_darray_size(ary) && ((elem_ptr_var) = rb_darray_ref(ary, idx_name)); ++idx_name)

// Iterate over valid indicies in the array in a for loop
//
#define rb_darray_for(ary, idx_name) \
    for (size_t idx_name = 0; idx_name < rb_darray_size(ary); ++idx_name)

// Make a dynamic array of a certain size. All bytes backing the elements are set to zero.
//
// Note that NULL is a valid empty dynamic array.
//
// void rb_darray_make(rb_darray(T) *ptr_to_ary, size_t size);
//
#define rb_darray_make(ptr_to_ary, size) \
    rb_darray_make_impl((ptr_to_ary), size, sizeof(**(ptr_to_ary)), \
                         sizeof((*(ptr_to_ary))->data[0]))

#define rb_darray_data_ptr(ary) ((ary)->data)

// Set the size of the array to zero without freeing the backing memory.
// Allows reusing the same array.
//
#define rb_darray_clear(ary) (ary->meta.size = 0)

typedef struct rb_darray_meta {
    size_t size;
    size_t capa;
} rb_darray_meta_t;

// Get the size of the dynamic array.
//
static inline size_t
rb_darray_size(const void *ary)
{
    const rb_darray_meta_t *meta = ary;
    return meta ? meta->size : 0;
}

// Get the capacity of the dynamic array.
//
static inline size_t
rb_darray_capa(const void *ary)
{
    const rb_darray_meta_t *meta = ary;
    return meta ? meta->capa : 0;
}

// Free the dynamic array.
//
static inline void
rb_darray_free(void *ary)
{
    rb_darray_meta_t *meta = ary;
    ruby_sized_xfree(ary, meta->capa);
}

// Internal function
// Ensure there is space for one more element.
// Note: header_size can be bigger than sizeof(rb_darray_meta_t) when T is __int128_t, for example.
static inline void
rb_darray_ensure_space(void *ptr_to_ary, size_t header_size, size_t element_size)
{
    rb_darray_meta_t **ptr_to_ptr_to_meta = ptr_to_ary;
    rb_darray_meta_t *meta = *ptr_to_ptr_to_meta;
    size_t current_capa = rb_darray_capa(meta);
    if (rb_darray_size(meta) < current_capa) return;

    // Double the capacity
    size_t new_capa = current_capa == 0 ? 1 : current_capa * 2;

    rb_darray_meta_t *doubled_ary = rb_xrealloc_mul_add(meta, new_capa, element_size, header_size);
    // rb_xrealloc functions guarantee that NULL is not returned
    assert(doubled_ary != NULL);

    if (meta == NULL) {
        // First allocation. Initialize size. On subsequence allocations
        // realloc takes care of carrying over the size.
        doubled_ary->size = 0;
    }

    doubled_ary->capa = new_capa;

    // We don't have access to the type of the dynamic array in function context.
    // Write out result with memcpy to avoid strict aliasing issue.
    memcpy(ptr_to_ary, &doubled_ary, sizeof(doubled_ary));
}

static inline void
rb_darray_make_impl(void *ptr_to_ary, size_t array_size, size_t header_size, size_t element_size)
{
    rb_darray_meta_t **ptr_to_ptr_to_meta = ptr_to_ary;
    if (array_size == 0) {
        *ptr_to_ptr_to_meta = NULL;
        return;
    }

    rb_darray_meta_t *meta = rb_xcalloc_mul_add(array_size, element_size, header_size);
    // rb_xcalloc functions guarantee that NULL is not returned
    assert(meta != NULL);

    meta->size = array_size;
    meta->capa = array_size;

    // We don't have access to the type of the dynamic array in function context.
    // Write out result with memcpy to avoid strict aliasing issue.
    memcpy(ptr_to_ary, &meta, sizeof(meta));
}

#endif /* RUBY_DARRAY_H */
