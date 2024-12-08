# MemoryView

MemoryView provides the features to share multidimensional homogeneous arrays of
fixed-size element on memory among extension libraries.

## Disclaimer

* This feature is still experimental.  The specification described here can be changed in the future.

* This document is under construction.  Please refer the master branch of ruby for the latest version of this document.

## Overview

We sometimes deal with certain kinds of objects that have arrays of the same typed fixed-size elements on a contiguous memory area as its internal representation.
Numo::NArray in numo-narray and Magick::Image in rmagick are typical examples of such objects.
MemoryView plays the role of the hub to share the internal data of such objects without copy among such libraries.

Copy-less sharing of data is very important in some field such as data analysis, machine learning, and image processing.  In these field, people need to handle large amount of on-memory data with several libraries.  If we are forced to copy to exchange large data among libraries, a large amount of the data processing time must be occupied by copying data.  You can avoid such wasting time by using MemoryView.

MemoryView has two categories of APIs:

1. Producer API

    Classes can register own MemoryView entry which allows objects of that classes to expose their MemoryView

2. Consumer API

    Consumer API allows us to obtain and manage the MemoryView of an object

## MemoryView structure

A MemoryView structure, `rb_memory_view_t`, is used for exporting objects' MemoryView.
This structure contains the reference of the object, which is the owner of the MemoryView, the pointer to the head of exported memory, and the metadata that describes the structure of the memory.  The metadata can describe multidimensional arrays with strides.

### The member of MemoryView structure

The MemoryView structure consists of the following members.

- `VALUE obj`

    The reference to the original object that has the memory exported via the MemoryView.

    RubyVM manages the reference count of the MemoryView-exported objects to guard them from the garbage collection.  The consumers do not have to struggle to guard this object from GC.

- `void *data`

    The pointer to the head of the exported memory.

- `ssize_t byte_size`

    The number of bytes in the memory pointed by `data`.

- `bool readonly`

    `true` for readonly memory, `false` for writable memory.

- `const char *format`

    A string to describe the format of an element, or NULL for unsigned byte.

- `ssize_t item_size`

    The number of bytes in each element.

- `const rb_memory_view_item_component_t *item_desc.components`

    The array of the metadata of the component in an element.

- `size_t item_desc.length`

    The number of items in `item_desc.components`.

- `ssize_t ndim`

    The number of dimensions.

- `const ssize_t *shape`

    A `ndim` size array indicating the number of elements in each dimension.
    This can be `NULL` when `ndim` is 1.

- `const ssize_t *strides`

    A `ndim` size array indicating the number of bytes to skip to go to the next element in each dimension.
    This can be `NULL` when `ndim` is 1.

- `const ssize_t *sub_offsets`

    A `ndim` size array consisting of the offsets in each dimension when the MemoryView exposes a nested array.
    This can be `NULL` when the MemoryView exposes a flat array.

- `void *private_data`

    The private data that MemoryView provider uses internally.
    This can be `NULL` when any private data is unnecessary.

## MemoryView APIs

### For consumers

- `bool rb_memory_view_available_p(VALUE obj)`

    Return `true` if `obj` supports to export a MemoryView.  Return `false` otherwise.

    If this function returns `true`, it doesn't mean the function `rb_memory_view_get` will succeed.

- `bool rb_memory_view_get(VALUE obj, rb_memory_view_t *view, int flags)`

    If the given `obj` supports to export a MemoryView that conforms the given `flags`, this function fills `view` by the information of the MemoryView and returns `true`.  In this case, the reference count of `obj` is increased.

    If the given combination of `obj` and `flags` cannot export a MemoryView, this function returns `false`. The content of `view` is not touched in this case.

    The exported MemoryView must be released by `rb_memory_view_release` when the MemoryView is no longer needed.

- `bool rb_memory_view_release(rb_memory_view_t *view)`

    Release the given MemoryView `view` and decrement the reference count of `view->obj`.

    Consumers must call this function when the MemoryView is no longer needed.  Missing to call this function leads memory leak.

- `ssize_t rb_memory_view_item_size_from_format(const char *format, const char **err)`

    Calculate the number of bytes occupied by an element.

    When the calculation fails, the failed location in `format` is stored into `err`, and returns `-1`.

- `void *rb_memory_view_get_item_pointer(rb_memory_view_t *view, const ssize_t *indices)`

    Calculate the location of the item indicated by the given `indices`.
    The length of `indices` must equal to `view->ndim`.
    This function initializes `view->item_desc` if needed.

- `VALUE rb_memory_view_get_item(rb_memory_view_t *view, const ssize_t *indices)`

    Return the Ruby object representation of the item indicated by the given `indices`.
    The length of `indices` must equal to `view->ndim`.
    This function uses `rb_memory_view_get_item_pointer`.

- `rb_memory_view_init_as_byte_array(rb_memory_view_t *view, VALUE obj, void *data, const ssize_t len, const bool readonly)`

  Fill the members of `view` as an 1-dimensional byte array.

- `void rb_memory_view_fill_contiguous_strides(const ssize_t ndim, const ssize_t item_size, const ssize_t *const shape, const bool row_major_p, ssize_t *const strides)`

  Fill the `strides` array with byte-Strides of a contiguous array of the given shape with the given element size.

- `void rb_memory_view_prepare_item_desc(rb_memory_view_t *view)`

  Fill the `item_desc` member of `view`.

- `bool rb_memory_view_is_contiguous(const rb_memory_view_t *view)`

  Return `true` if the data in the MemoryView `view` is row-major or column-major contiguous.

  Return `false` otherwise.

- `bool rb_memory_view_is_row_major_contiguous(const rb_memory_view_t *view)`

  Return `true` if the data in the MemoryView `view` is row-major contiguous.

  Return `false` otherwise.

- `bool rb_memory_view_is_column_major_contiguous(const rb_memory_view_t *view)`

  Return `true` if the data in the MemoryView `view` is column-major contiguous.

  Return `false` otherwise.
