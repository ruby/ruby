# Tips for updating Ruby C extensions for efficiently using Ruby 4 VM APIs

## Why?

The Ruby VM has evolved a lot from Ruby 2 to Ruby 4. While this evolution was reflected in Ruby's C APIs, great care was taken to provide backwards compatibility. Old gems work with little change on Ruby 4, ensuring apps don't get stuck on old versions just because some dependency has not been updated.

Yet, C extensions that keep using old APIs and design patterns are leaving performance and safety advances "on the table" not only for the extensions themselves, but also silently disabling or hindering major Ruby VM optimizations, getting in the way of GC, Ractors, observability, etc.

As much as possible, C extensions should have "mechanical sympathy" for the Ruby VM.
When C extensions use old APIs or do things incorrectly, Ruby needs to fall back to safer behaviors, which means the whole application runs more slowly because of those C extensions.

## The "elephant" in the room

### Tip: 🟧 _Avoid native extensions if you can_

Can you avoid doing the thing in native code at all? See <https://railsatscale.com/2023-08-29-ruby-outperforms-c/> and <https://jpcamara.com/2024/12/01/speeding-up-ruby.html>. Can you use [ffi](https://github.com/ffi/ffi) instead?

## Arrays

### Tip: 🟥 _Never use `RARRAY_PTR`_

Impact: _Slows down GC forever (while the object lives)_

Why:
1. It "wb unprotects" the object forever. Aka object is permanently in young generation, GC always needs to scan it forever even if it's not changing
2. Plus "wb unprotecting" is expensive, needs special "GC VM lock" to do
3. The impact applies even if you only read from the array once; Ruby doesn't know it and is conservative forever
4. You can accidentally write to a frozen array
5. No bounds checking, you can accidentally corrupt memory

Do instead:
1. Use `rb_ary_entry` to read
2. Use `rb_ary_store` to write
3. If an API requires a contiguous `VALUE` pointer, use `RARRAY_PTR_USE` to keep raw-pointer access scoped

### Tip: 🟧 _Avoid using `RARRAY_AREF` to read an array_

Impact: _No bounds checking (unsafe)_

Why:
1. Using `RARRAY_AREF(array, 12345)` will always try to read, even if array is not that long, potentially leading to subtle bugs
2. If you call back into Ruby code while operating on an array, it's possible a different thread will get to run and update the array, so the length may change unexpectedly

Do instead:
1. Use `rb_ary_entry`, it checks the array is long enough to contain the entry requested

### Tip: 🟩 _Use `rb_ary_store` to write to an array_

Impact: _GC faster, and respects frozen_

Why:
1. It checks if an array is frozen before writing to it
2. It does not "write barrier unprotect" the object
3. It correctly implements the (very cheap) write barrier only if needed -- and this only affects the next GC, not all GC forever

## Hashes

### Tip: 🟥 _Never use `RHASH_TBL`_

Impact: _Slows down GC forever (while the object lives), no bounds/frozen checking_

Why:
1. It "wb unprotects" the object forever. Aka object is permanently in young generation, GC always needs to scan it forever even if it's not changing
2. Plus "wb unprotecting" is expensive, needs special "GC VM lock" to do
3. The impact applies even if you only read from the hash once; Ruby doesn't know it and is conservative forever

(You might recognize points 1-3 as "same downsides as `RARRAY_PTR`", but for hashes)

4. Forces "ar table" to "st table" conversion => Ruby has a special compact representation for small hashes and this forces the non-compact representation always

Do instead:
* Use `rb_hash_...` functions

## Strings

### Tip: 🟩 _Use fstrings for repeated/long-lived strings_

Impact: _Lower app memory use, faster hash lookups, slightly slower creation_

Quick detour: What are fstrings?
* TL;DR Global deduplicated frozen strings
* Same as `String#dedup`/`String#-@` but directly from C

```
VALUE v1 = rb_interned_str_cstr("hello");
VALUE v2 = rb_interned_str_cstr("hello");
```

`v1 == v2` in C (same object!)

(Very similar behavior to symbols!)

Why:
1. It lowers memory use since only one copy of string data is kept
2. It speeds up hash inserts with string keys, since a non-frozen String key gets fstring-deduplicated on insert anyway -- passing an fstring avoids that extra work

## Memory

### Tip: 🟩 _Use `ruby_xmalloc`/`ruby_xfree`/`ruby_x`... to manage memory_

Impact: _Improved low memory handling, improved GC behavior, safer_

Why:
1. Ruby will automatically GC if the app runs out of memory to try to recover
2. Ruby will trigger GC after some amount of allocations to avoid fragmentation and high memory usage
3. No need to error check -- it always returns memory or raises an exception directly
4. Maybe MMTk will be able to optimize it further in the future? ;)

(mmtk.c)

```c
// Malloc
void *
rb_gc_impl_malloc(void *objspace_ptr, size_t size, bool gc_allowed)
{
    // TODO: don't use system malloc
    return malloc(size);
}
```

### Tip: 🟧 _Be careful about making objects "immortal"_

Impact: _Higher memory use_

Why:
1. APIs such as `rb_gc_register_mark_object` and `rb_define_class`/`rb_define_module` cause objects to become immortal -- they can never be garbage collected nor can the garbage collector move them during compaction

Do instead (*sometimes?):
1. `rb_global_variable` prevents an object referenced from being garbage collected and moved, but once the variable stops pointing at the object the effect disappears

### Tip: 🟩 _Use sized/bulk APIs to avoid unnecessary resizing of Arrays, Hashes, Strings_

When creating Arrays, Hashes, and Strings, you can often provide sizes and perform operations in bulk.

Look for APIs such as:

* Arrays: `rb_ary_new_capa(size)` / `rb_ary_new_from_args(size, ...)` / `rb_ary_new_from_values(size, ...)` / `rb_ary_cat(...)`
* Hashes: `rb_hash_new_capa` / `rb_hash_bulk_insert`
* Strings: `rb_str_buf_new(capa)`

Impact: _Faster performance, reduced memory usage_

Why:
1. When Ruby knows the size of objects, it can take advantage of Variable Width Allocation to find a size pool that can contain the entire object, keeping all the data together in memory and saving the overhead of extra allocations
2. When performing mutations in bulk, Ruby can resize the object once to fit all the changes, rather than needing to incrementally grow
3. Calling into Ruby once with all the changes is often faster than calling many times to feed each change (as there are checks that need to be done on every call, for instance)

## Ractors

### Tip: 🟩 _If your extension is Ractor-safe, remember to tell Ruby about it with `rb_ext_ractor_safe`_

Impact: _Faster performance! (Even very slightly with a single Ractor)_

Why:
1. Allow Ruby app to take advantage of true parallelism
2. When an extension doesn't declare itself Ractor-safe, Ruby wraps every method call with the equivalent of

```c
VALUE call_cfunc(...) {
    if (!rb_ractor_main_p()) {
        rb_raise(rb_eRactorUnsafeError, "ractor unsafe method called from not main ractor");
    }
    return call_original_function(...)
}
```

Note: `rb_ext_ractor_safe(true)` must be called **before** the `rb_define_method` calls for the methods you want optimized.
It changes the invoker used for methods defined *afterward*; calling it later does not retrofit already-defined methods.
Whenever possible, consider doing it in the extension's `Init_...` function.

## TypedData

What is TypedData? It allows a Ruby object to wrap a C struct or similar native memory.

```c
struct SimpleSomeStruct {
    int internal_info;
};
VALUE obj = TypedData_Make_Struct(klass, struct SimpleSomeStruct, &some_typed_data_type, ptr); // <-- Wraps struct with Ruby object
```

But a TypedData object has one key very powerful feature -- it can hold **references** to Ruby objects. That is, you can use it to implement your own custom instance variables, arrays, hashes, etc that reference Ruby objects.

```c
struct SomeStruct {
    int internal_info;
    VALUE some_reference; // <-- Here we can keep a reference to another ruby object! Like a C "instance variable"
};
VALUE obj = ...;
```

BUT holding references to Ruby objects means TypedData must coordinate with the Ruby garbage collector.
And the Ruby garbage collector has evolved quite a bit from Ruby 2 to 4 to get the most performance out of your applications, and this evolution often cannot be hidden/abstracted away from TypedData objects.
TypedData + Ruby references is the ultimate in "mechanical sympathy".

**Running example.** We'll use this `SomeStruct` as the basis for a `SomeClass` that we'll carry through the rest of the section.

```c
static void some_struct_mark(void *ptr) {
    struct SomeStruct *data = ptr;
    rb_gc_mark(data->some_reference);   // pins the reference, see tip on `dcompact` below
}

static const rb_data_type_t some_typed_data_type = {
    .wrap_struct_name = "SomeStruct",
    .function = {
        .dmark = some_struct_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE,   // = ruby_xfree
        // .dsize omitted -- see tip on `dsize` below
        // .dcompact omitted -- see tip on `dcompact` below
    },
    // .flags omitted -- see tips below
};

static VALUE some_class_set_some_reference(VALUE self, VALUE reference) {
    struct SomeStruct *data;
    TypedData_Get_Struct(self, struct SomeStruct, &some_typed_data_type, data);
    data->some_reference = reference;    // no write barrier -- see tip on it below
    return reference;
}
```

### Tip: 🟧 _Avoid using TypedData, especially for referencing Ruby objects if you can!_

Impact: _Simplicity and correctness (sanity?)_

Why:
1. As we'll see, implementing all of the TypedData features is quite complex
2. If you can store your extension's data in a regular Ruby array or Ruby hash, consider doing that! Those are extremely optimized already!
3. You'll be able to ignore ALL of the tips that follow!

### Tip: 🟩 _Use declarative marking_

Impact: _Lower memory usage, and easier to maintain_

Why:
1. GC compaction enables Ruby to move objects together, improving performance and reducing memory usage (including across forks)
2. Declarative marking avoids having separate mark and compact functions that need to be kept in-sync

Applied to the running example -- delete the hand-written `some_struct_mark`, declare the offsets, flip the flag:

```c
RUBY_REFERENCES(some_struct_refs) = {
    RUBY_REF_EDGE(struct SomeStruct, some_reference),
    RUBY_REF_END,
};

static const rb_data_type_t some_typed_data_type = {
    .wrap_struct_name = "SomeStruct",
    .function = {
        .dmark = RUBY_REFS_LIST_PTR(some_struct_refs), // refs go in dmark, not data!
        .dfree = RUBY_TYPED_DEFAULT_FREE,
    },
    .flags = RUBY_TYPED_DECL_MARKING,
};
```

No `dmark` function, no `dcompact` function -- the GC walks the offset list for both marking and compaction.
If you later add a new `VALUE` member to `struct SomeStruct`, remember to add a matching `RUBY_REF_EDGE` and that's it!

### Tip: 🟥 _Always provide a dcompact function when referencing Ruby objects_

(*UNLESS you're using declarative marking)

Impact: _Pins referenced objects, preventing them from being compacted_

Why:
1. A dcompact allows Ruby to still do GC compaction, even when not using declarative marking
2. Without it, objects referenced by a TypedData object are "pinned" in place, unable to ever move

Applied to the running example -- change `rb_gc_mark` to `rb_gc_mark_movable` and add a compact callback:

```c
static void some_struct_mark(void *ptr) {
    struct SomeStruct *data = ptr;
    rb_gc_mark_movable(data->some_reference);   // was rb_gc_mark -> pinned
}

static void some_struct_compact(void *ptr) {
    struct SomeStruct *data = ptr;
    data->some_reference = rb_gc_location(data->some_reference);
}

static const rb_data_type_t some_typed_data_type = {
    .wrap_struct_name = "SomeStruct",
    .function = {
        .dmark    = some_struct_mark,
        .dfree    = RUBY_TYPED_DEFAULT_FREE,
        .dcompact = some_struct_compact,        // NEW
    },
};
```

`rb_gc_location` returns the (possibly new) address of an object that was marked movable.
If the object wasn't moved, it returns the same `VALUE` unchanged -- so it's always safe to assign back.

### Tip: 🟥 _Do not use TypedData without `RUBY_TYPED_WB_PROTECTED`_

Impact: _Slows down GC_

Why:
1. It "wb unprotects" the object forever. Aka object is permanently in young generation, GC always needs to scan it forever even if it's not changing

Do instead:
1. Declare TypedData as `RUBY_TYPED_WB_PROTECTED`
2. Whenever a reference is written, you must use `RB_OBJ_WRITE` -- don't forget!

Applied to the running example -- set the flag AND route every `VALUE` store through `RB_OBJ_WRITE`:

```c
static VALUE some_class_set_some_reference(VALUE self, VALUE reference) {
    struct SomeStruct *data;
    TypedData_Get_Struct(self, struct SomeStruct, &some_typed_data_type, data);
    RB_OBJ_WRITE(self, &data->some_reference, reference);   // was: data->some_reference = reference;
    return reference;
}

static const rb_data_type_t some_typed_data_type = {
    .wrap_struct_name = "SomeStruct",
    .function = { ... },
    .flags = RUBY_TYPED_WB_PROTECTED,   // NEW
};
```

### Tip: 🟩 _Implement dsize_

Impact: _Accurate memory information_

Why:
1. This exposes correct memory accounting to `ObjectSpace` APIs (`memsize_of`, `count_objects_size`, `dump`, `dump_all`)
2. Otherwise Ruby will only count the Ruby size of the object, not the C size

Do:
1. Write a dsize! ;)

Applied to the running example -- add a size reporter:

```c
static size_t some_struct_dsize(const void *ptr) {
    return sizeof(struct SomeStruct);
}

static const rb_data_type_t some_typed_data_type = {
    .wrap_struct_name = "SomeStruct",
    .function = {
        .dmark = some_struct_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE,
        .dsize = some_struct_dsize,   // NEW
    },
    ...
};
```

If `struct SomeStruct` later owns heap-allocated memory (e.g. malloc and the like), include their sizes in the return value too.

### Tip: 🟧 _If possible, use `RUBY_TYPED_FREE_IMMEDIATELY`_

Impact: _Faster garbage collection and earlier memory reclamation_

Why:
1. When `RUBY_TYPED_FREE_IMMEDIATELY` is set, you are "promising" to Ruby that it's safe to call dfree immediately, during GC. To make your function safe, you should never call into Ruby APIs (like trying to release the GVL) and ideally avoid any kind of blocking or I/O. A function that just calls xfree/free on things is one example of something free to call immediately. With this "promise", Ruby is able to call the dfree immediately during object sweeping, thus freeing up the memory immediately.
2. Without it -- that is, for a custom `dfree` callback that hasn't opted in -- Ruby keeps the object as a "zombie", then needs to add it to a list of pages to finalize, then needs to do extra work to go through the page, etc... Hard to avoid in some situations. This deferred handling applies specifically to custom `dfree` functions; `RUBY_TYPED_DEFAULT_FREE` (used in our example) is already recognized and safely executed immediately during sweeping regardless of this flag, since Ruby knows in advance that it's just a plain `xfree`.

Applied to the running example -- our `dfree` is just `ruby_xfree` (never touches the GVL, never blocks), so the flag is safe to add:

```c
static const rb_data_type_t some_typed_data_type = {
    ...
    .flags = RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY,   // + FREE_IMMEDIATELY
};
```

### Tip: 🟧 _Consider using `RUBY_TYPED_EMBEDDABLE`_

Impact: _Faster GC, fewer memory allocations, better code performance (trade off with complexity)_

Why:
1. By embedding the struct directly inside the Ruby object, we avoid having the classic split of TypedData objects into two parts
2. Which means the second part does not need a separate malloc -> less work AND means the second part does not need a separate free -> less work
3. Which means less pointer chasing by the cpu, and better cache use (reading the object will bring the rest into the cache)
4. Proven track record of improving performance for core types

But be careful -- see the latest Ruby docs on <https://docs.ruby-lang.org/en/master/extension_rdoc.html#appendix-g-embedded-typeddata> and the discussion on <https://bugs.ruby-lang.org/issues/21853>, especially around the use of `RB_GC_GUARD`, not storing pointers to/into the C structure, how `dfree`/`dsize` need to be changed, and `RUBY_TYPED_FREE_IMMEDIATELY` being required.

This is kind-of an advanced use case, so I recommend it only as an optimization for objects accessed very often, or created in large numbers. "With great power comes great responsibility" kinda feature.

As per <https://bugs.ruby-lang.org/issues/21853>, this is a Ruby 4.1+ feature "officially", but you can use it as far back as Ruby 3.3...
I think? I didn't find any reason _not_ to use it, do let me know if I missed it.

Applied to the running example -- `struct SomeStruct` is tiny (one int + one `VALUE`), so it's a strong candidate for embedding directly in the Ruby object slot:

```c
static size_t some_struct_dsize(const void *ptr) {
    return 0; // struct now embedded in the Ruby object slot, so Ruby
              // already accounts for its size -- report only auxiliary
              // heap allocations here
}

static const rb_data_type_t some_typed_data_type = {
    ...
    .function = {
        ...
        .dsize = some_struct_dsize,   // CHANGED: no longer counts sizeof(struct SomeStruct)
    },
    .flags = RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_EMBEDDABLE,
};
```

Note that it requires `RUBY_TYPED_FREE_IMMEDIATELY`.

Also note that `dsize` must be revisited: once the struct is embedded, its memory is already part of the Ruby object slot, so `dsize` returning `sizeof(struct SomeStruct)` (as in the earlier tip) would double-count it in `ObjectSpace` accounting. `dsize` should report only auxiliary heap allocations owned by the struct (e.g. malloc'd buffers) -- zero if there are none, as here.

### Tip: 🟧 _Consider using mass marking/compacting functions_

Ruby provides a number of "mark all/compact all" reference functions:

* `rb_gc_mark_locations(const VALUE *start, const VALUE *end)`
    * Conservatively (maybe) mark + pin everything between two pointers
* `rb_mark_hash(struct st_table *tbl)`
    * For an `st_table` with `VALUE` keys and values
    * Exact mark + pin every key and value
* `rb_mark_set(struct st_table *tbl)`
    * For an `st_table` with `VALUE` keys
    * Exact mark + pin every key
* `rb_mark_tbl(struct st_table *tbl)`
    * For an `st_table` with `VALUE` values
    * Exact mark + pin every value
    * (Doesn't do anything with the keys)
* `rb_mark_tbl_no_pin(struct st_table *tbl)`
    * For an `st_table` with `VALUE` values
    * Exact mark + **does not pin** every value
    * (Doesn't do anything with the keys)
    * During `dcompact`, you need to update values with `rb_gc_location`
    * I advise against using `rb_gc_update_tbl_refs` as the documentation is incorrect -- see <https://bugs.ruby-lang.org/issues/21993>

And there's a few more variants that are available but hidden:
* `rb_gc_mark_values(long n, const VALUE *values)`
    * Similar in spirit to `rb_gc_mark_locations` but exact mark + **no pin**
    * `rb_gc_update_values(long n, VALUE *values)` should be used in `dcompact`
* `rb_gc_mark_vm_stack_values(long n, const VALUE *values)`
    * Similar in spirit to `rb_gc_mark_locations` but exact mark + **pin**

In practice, there's a combination of:
* Kind/shape of data structure (st_table, begin/end pointers, beginning + length)
* Conservative (maybe) mark vs exact mark
* Pin vs no-pin
* Availability of `dcompact` counterpart

that aren't available. Would it be useful for gems to support more?

Impact: _Maybe (?) faster GC, simplification_

Why:
1. As with any low-level vs high-level API, it's much better if you can tell Ruby "I want to mark all of this" vs going one by one
2. ...Although Ruby right now maps this to "one-by-one" so... the gain is more on expressiveness than speed (and maybe future MMTk optimization?)

### Tip: 🟩 _Prefer `TypedData_Make_Struct` over `TypedData_Wrap_Struct`_

Impact: _Avoids memory leaks on the error path_

Why:
1. `TypedData_Wrap_Struct` takes a struct pointer you allocated yourself. If wrapping raises (e.g. out-of-memory when allocating the Ruby object), the struct leaks.
2. `TypedData_Make_Struct` allocates both the Ruby object and the struct as a single operation -- nothing to clean up on failure.

Sharp edge: if struct allocation inside `Make_Struct` fails, you can end up with a Ruby object whose data pointer is `NULL`. Still usually better than the leak. Reach for `Wrap_Struct` only when you already have a pre-existing struct pointer you can't recreate.

### Tip: 🟧 _Set `RUBY_TYPED_FROZEN_SHAREABLE` if you want frozen TypedData to cross Ractors_

Impact: _Allows frozen instances to be shared across Ractors without copying_

Why:
1. Without the flag, `Ractor.make_shareable(obj)` raises for your type.
2. With the flag (plus freezing + `Ractor.make_shareable`), the object can be read from any Ractor.

Do make sure that your object and C code are able to correctly run across many Ractors with no thread safety issues.
