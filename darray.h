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
// TODO: replace this with rb_darray_append_with_gc when YJIT moves to Rust.
//
#define rb_darray_append(ptr_to_ary, element) do {  \
    rb_darray_ensure_space((ptr_to_ary), sizeof(**(ptr_to_ary)), \
                           sizeof((*(ptr_to_ary))->data[0]), realloc); \
    rb_darray_set(*(ptr_to_ary), \
                  (*(ptr_to_ary))->meta.size, \
                  (element)); \
    (*(ptr_to_ary))->meta.size++; \
} while (0)

#define rb_darray_append_with_gc(ptr_to_ary, element) do {  \
    rb_darray_ensure_space((ptr_to_ary), sizeof(**(ptr_to_ary)), \
                           sizeof((*(ptr_to_ary))->data[0]), ruby_xrealloc); \
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
// Return 1 on success and 0 on failure.
//
// Note that NULL is a valid empty dynamic array.
//
// void rb_darray_make(rb_darray(T) *ptr_to_ary, size_t size);
//
// TODO: replace this with rb_darray_make_with_gc with YJIT moves to Rust.
//
#define rb_darray_make(ptr_to_ary, size) \
    rb_darray_make_impl((ptr_to_ary), size, sizeof(**(ptr_to_ary)), \
                        sizeof((*(ptr_to_ary))->data[0]), calloc)


#define rb_darray_make_with_gc(ptr_to_ary, size) \
    rb_darray_make_impl((ptr_to_ary), size, sizeof(**(ptr_to_ary)), \
                         sizeof((*(ptr_to_ary))->data[0]), ruby_xcalloc)

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
// TODO: replace this with rb_darray_free_with_gc when YJIT moves to Rust.
//
static inline void
rb_darray_free(void *ary)
{
    free(ary);
}

static inline void
rb_darray_free_with_gc(void *ary)
{
    rb_darray_meta_t *meta = ary;
    ruby_sized_xfree(ary, meta->capa);
}

// Internal function. Calculate buffer size on malloc heap.
static inline size_t
rb_darray_buffer_size(size_t capacity, size_t header_size, size_t element_size)
{
    if (capacity == 0) return 0;
    return header_size + capacity * element_size;
}

// Internal function
// Ensure there is space for one more element.
// Note: header_size can be bigger than sizeof(rb_darray_meta_t) when T is __int128_t, for example.
static inline void
rb_darray_ensure_space(void *ptr_to_ary, size_t header_size, size_t element_size, void *(*realloc_impl)(void *, size_t))
{
    rb_darray_meta_t **ptr_to_ptr_to_meta = ptr_to_ary;
    rb_darray_meta_t *meta = *ptr_to_ptr_to_meta;
    size_t current_capa = rb_darray_capa(meta);
    if (rb_darray_size(meta) < current_capa) return;

    // Double the capacity
    size_t new_capa = current_capa == 0 ? 1 : current_capa * 2;

    // Calculate new buffer size
    size_t current_buffer_size = rb_darray_buffer_size(current_capa, header_size, element_size);
    size_t new_buffer_size = rb_darray_buffer_size(new_capa, header_size, element_size);
    if (new_buffer_size <= current_buffer_size) {
        rb_bug("rb_darray_ensure_space: overflow");
    }

    // TODO: replace with rb_xrealloc_mul_add(meta, new_capa, element_size, header_size);
    rb_darray_meta_t *doubled_ary = realloc_impl(meta, new_buffer_size);
    if (!doubled_ary) {
        rb_bug("rb_darray_ensure_space: failed");
    }

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
rb_darray_make_impl(void *ptr_to_ary, size_t array_size, size_t header_size, size_t element_size, void *(*calloc_impl)(size_t, size_t))
{
    rb_darray_meta_t **ptr_to_ptr_to_meta = ptr_to_ary;
    if (array_size == 0) {
        *ptr_to_ptr_to_meta = NULL;
        return;
    }

    // TODO: replace with rb_xcalloc_mul_add(array_size, element_size, header_size)
    size_t buffer_size = rb_darray_buffer_size(array_size, header_size, element_size);
    rb_darray_meta_t *meta = calloc_impl(buffer_size, 1);
    if (!meta) {
        rb_bug("rb_darray_make_impl: failed");
    }

    meta->size = array_size;
    meta->capa = array_size;

    // We don't have access to the type of the dynamic array in function context.
    // Write out result with memcpy to avoid strict aliasing issue.
    memcpy(ptr_to_ary, &meta, sizeof(meta));
}

#endif /* RUBY_DARRAY_H */
