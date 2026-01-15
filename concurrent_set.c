#include "internal.h"
#include "internal/gc.h"
#include "internal/concurrent_set.h"
#include "ruby/atomic.h"
#include "vm_sync.h"

#define CONCURRENT_SET_CONTINUATION_BIT ((VALUE)1 << (sizeof(VALUE) * CHAR_BIT - 1))
#define CONCURRENT_SET_HASH_MASK (~CONCURRENT_SET_CONTINUATION_BIT)

enum concurrent_set_special_values {
    CONCURRENT_SET_EMPTY,
    CONCURRENT_SET_DELETED,
    CONCURRENT_SET_MOVED,
    CONCURRENT_SET_SPECIAL_VALUE_COUNT
};

struct concurrent_set_entry {
    VALUE hash;
    VALUE key;
};

struct concurrent_set {
    rb_atomic_t size;
    unsigned int capacity;
    unsigned int deleted_entries;
    const struct rb_concurrent_set_funcs *funcs;
    struct concurrent_set_entry *entries;
};

static void
concurrent_set_mark_continuation(struct concurrent_set_entry *entry, VALUE curr_hash_and_flags)
{
    if (curr_hash_and_flags & CONCURRENT_SET_CONTINUATION_BIT) return;

    RUBY_ASSERT((curr_hash_and_flags & CONCURRENT_SET_HASH_MASK) != 0);

    VALUE new_hash = curr_hash_and_flags | CONCURRENT_SET_CONTINUATION_BIT;
    VALUE prev_hash = rbimpl_atomic_value_cas(&entry->hash, curr_hash_and_flags, new_hash, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);

    // At the moment we only expect to be racing concurrently against another
    // thread also setting the continuation bit.
    // In the future if deletion is concurrent this will need adjusting
    RUBY_ASSERT(prev_hash == curr_hash_and_flags || prev_hash == new_hash);
    (void)prev_hash;
}

static VALUE
concurrent_set_hash(const struct concurrent_set *set, VALUE key)
{
    VALUE hash = set->funcs->hash(key);
    hash &= CONCURRENT_SET_HASH_MASK;
    if (hash == 0) {
        hash ^= CONCURRENT_SET_HASH_MASK;
    }
    RUBY_ASSERT(hash != 0);
    RUBY_ASSERT(!(hash & CONCURRENT_SET_CONTINUATION_BIT));
    return hash;
}

static void
concurrent_set_free(void *ptr)
{
    struct concurrent_set *set = ptr;
    xfree(set->entries);
}

static size_t
concurrent_set_size(const void *ptr)
{
    const struct concurrent_set *set = ptr;
    return sizeof(struct concurrent_set) +
        (set->capacity * sizeof(struct concurrent_set_entry));
}

/* Hack: Though it would be trivial, we're intentionally avoiding WB-protecting
 * this object. This prevents the object from aging and ensures it can always be
 * collected in a minor GC.
 * Longer term this deserves a better way to reclaim memory promptly.
 */
static void
concurrent_set_mark(void *ptr)
{
    (void)ptr;
}

static const rb_data_type_t concurrent_set_type = {
    .wrap_struct_name = "VM/concurrent_set",
    .function = {
        .dmark = concurrent_set_mark,
        .dfree = concurrent_set_free,
        .dsize = concurrent_set_size,
    },
    /* Hack: NOT WB_PROTECTED on purpose (see above) */
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_EMBEDDABLE
};

VALUE
rb_concurrent_set_new(const struct rb_concurrent_set_funcs *funcs, int capacity)
{
    struct concurrent_set *set;
    VALUE obj = TypedData_Make_Struct(0, struct concurrent_set, &concurrent_set_type, set);
    set->funcs = funcs;
    set->entries = ZALLOC_N(struct concurrent_set_entry, capacity);
    set->capacity = capacity;
    return obj;
}

rb_atomic_t
rb_concurrent_set_size(VALUE set_obj)
{
    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    return RUBY_ATOMIC_LOAD(set->size);
}

struct concurrent_set_probe {
    int idx;
    int d;
    int mask;
};

static int
concurrent_set_probe_start(struct concurrent_set_probe *probe, struct concurrent_set *set, VALUE hash)
{
    RUBY_ASSERT((set->capacity & (set->capacity - 1)) == 0);
    probe->d = 0;
    probe->mask = set->capacity - 1;
    probe->idx = hash & probe->mask;
    return probe->idx;
}

static int
concurrent_set_probe_next(struct concurrent_set_probe *probe)
{
    probe->d++;
    probe->idx = (probe->idx + probe->d) & probe->mask;
    return probe->idx;
}

static void
concurrent_set_try_resize_without_locking(VALUE old_set_obj, VALUE *set_obj_ptr)
{
    // Check if another thread has already resized.
    if (rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE) != old_set_obj) {
        return;
    }

    struct concurrent_set *old_set = RTYPEDDATA_GET_DATA(old_set_obj);

    // This may overcount by up to the number of threads concurrently attempting to insert
    // GC may also happen between now and the set being rebuilt
    int expected_size = rbimpl_atomic_load(&old_set->size, RBIMPL_ATOMIC_RELAXED) - old_set->deleted_entries;

    // NOTE: new capacity must make sense with load factor, don't change one without checking the other.
    struct concurrent_set_entry *old_entries = old_set->entries;
    int old_capacity = old_set->capacity;
    int new_capacity = old_capacity * 2;
    if (new_capacity > expected_size * 8) {
        new_capacity = old_capacity / 2;
    }
    else if (new_capacity > expected_size * 4) {
        new_capacity = old_capacity;
    }

    // May cause GC and therefore deletes, so must happen first.
    VALUE new_set_obj = rb_concurrent_set_new(old_set->funcs, new_capacity);
    struct concurrent_set *new_set = RTYPEDDATA_GET_DATA(new_set_obj);

    for (int i = 0; i < old_capacity; i++) {
        struct concurrent_set_entry *old_entry = &old_entries[i];
        VALUE key = rbimpl_atomic_value_exchange(&old_entry->key, CONCURRENT_SET_MOVED, RBIMPL_ATOMIC_ACQUIRE);
        RUBY_ASSERT(key != CONCURRENT_SET_MOVED);

        if (key < CONCURRENT_SET_SPECIAL_VALUE_COUNT) continue;
        if (!RB_SPECIAL_CONST_P(key) && rb_objspace_garbage_object_p(key)) continue;

        VALUE hash = rbimpl_atomic_value_load(&old_entry->hash, RBIMPL_ATOMIC_RELAXED) & CONCURRENT_SET_HASH_MASK;
        RUBY_ASSERT(hash != 0);
        RUBY_ASSERT(hash == concurrent_set_hash(old_set, key));

        // Insert key into new_set.
        struct concurrent_set_probe probe;
        int idx = concurrent_set_probe_start(&probe, new_set, hash);

        while (true) {
            struct concurrent_set_entry *entry = &new_set->entries[idx];

            if (entry->hash == CONCURRENT_SET_EMPTY) {
                RUBY_ASSERT(entry->key == CONCURRENT_SET_EMPTY);

                new_set->size++;
                RUBY_ASSERT(new_set->size <= new_set->capacity / 2);

                entry->key = key;
                entry->hash = hash;
                break;
            }

            RUBY_ASSERT(entry->key >= CONCURRENT_SET_SPECIAL_VALUE_COUNT);
            entry->hash |= CONCURRENT_SET_CONTINUATION_BIT;
            idx = concurrent_set_probe_next(&probe);
        }
    }

    rbimpl_atomic_value_store(set_obj_ptr, new_set_obj, RBIMPL_ATOMIC_RELEASE);

    RB_GC_GUARD(old_set_obj);
}

static void
concurrent_set_try_resize(VALUE old_set_obj, VALUE *set_obj_ptr)
{
    RB_VM_LOCKING() {
        concurrent_set_try_resize_without_locking(old_set_obj, set_obj_ptr);
    }
}

VALUE
rb_concurrent_set_find(VALUE *set_obj_ptr, VALUE key)
{
    RUBY_ASSERT(key >= CONCURRENT_SET_SPECIAL_VALUE_COUNT);

    VALUE set_obj;
    VALUE hash = 0;
    struct concurrent_set *set;
    struct concurrent_set_probe probe;
    int idx;

  retry:
    set_obj = rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE);
    RUBY_ASSERT(set_obj);
    set = RTYPEDDATA_GET_DATA(set_obj);

    if (hash == 0) {
        // We don't need to recompute the hash on every retry because it should
        // never change.
        hash = concurrent_set_hash(set, key);
    }
    RUBY_ASSERT(hash == concurrent_set_hash(set, key));

    idx = concurrent_set_probe_start(&probe, set, hash);

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE curr_hash_and_flags = rbimpl_atomic_value_load(&entry->hash, RBIMPL_ATOMIC_ACQUIRE);
        VALUE curr_hash = curr_hash_and_flags & CONCURRENT_SET_HASH_MASK;
        bool continuation = curr_hash_and_flags & CONCURRENT_SET_CONTINUATION_BIT;

        if (curr_hash_and_flags == CONCURRENT_SET_EMPTY) {
            return 0;
        }

        if (curr_hash != hash) {
            if (!continuation) {
                return 0;
            }
            idx = concurrent_set_probe_next(&probe);
            continue;
        }

        VALUE curr_key = rbimpl_atomic_value_load(&entry->key, RBIMPL_ATOMIC_ACQUIRE);

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY:
            // In-progress insert: hash written but key not yet
            break;
          case CONCURRENT_SET_DELETED:
            break;
          case CONCURRENT_SET_MOVED:
            // Wait
            RB_VM_LOCKING();

            goto retry;
          default: {
            if (UNLIKELY(!RB_SPECIAL_CONST_P(curr_key) && rb_objspace_garbage_object_p(curr_key))) {
                // This is a weakref set, so after marking but before sweeping is complete we may find a matching garbage object.
                // Skip it and let the GC pass clean it up
                break;
            }

            if (set->funcs->cmp(key, curr_key)) {
                // We've found a match.
                RB_GC_GUARD(set_obj);
                return curr_key;
            }

            if (!continuation) {
                return 0;
            }

            break;
          }
        }

        idx = concurrent_set_probe_next(&probe);
    }
}

VALUE
rb_concurrent_set_find_or_insert(VALUE *set_obj_ptr, VALUE key, void *data)
{
    RUBY_ASSERT(key >= CONCURRENT_SET_SPECIAL_VALUE_COUNT);

    // First attempt to find
    {
        VALUE result = rb_concurrent_set_find(set_obj_ptr, key);
        if (result) return result;
    }

    // First time we need to call create, and store the hash
    VALUE set_obj = rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE);
    RUBY_ASSERT(set_obj);

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);
    key = set->funcs->create(key, data);
    VALUE hash = concurrent_set_hash(set, key);

    struct concurrent_set_probe probe;
    int idx;

    goto start_search;

retry:
    // On retries we only need to load the hash object
    set_obj = rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE);
    RUBY_ASSERT(set_obj);
    set = RTYPEDDATA_GET_DATA(set_obj);

    RUBY_ASSERT(hash == concurrent_set_hash(set, key));

start_search:
    idx = concurrent_set_probe_start(&probe, set, hash);

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE curr_hash_and_flags = rbimpl_atomic_value_load(&entry->hash, RBIMPL_ATOMIC_ACQUIRE);
        VALUE curr_hash = curr_hash_and_flags & CONCURRENT_SET_HASH_MASK;
        bool continuation = curr_hash_and_flags & CONCURRENT_SET_CONTINUATION_BIT;

        if (curr_hash_and_flags == CONCURRENT_SET_EMPTY) {
            // Reserve this slot for our hash value
            curr_hash_and_flags = rbimpl_atomic_value_cas(&entry->hash, CONCURRENT_SET_EMPTY, hash, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
            if (curr_hash_and_flags != CONCURRENT_SET_EMPTY) {
                // Lost race, retry same slot to check winner's hash
                continue;
            }

            // CAS succeeded, so these are the values stored
            curr_hash_and_flags = hash;
            curr_hash = hash;

            // Fall through to try to claim key
        }

        if (curr_hash != hash) {
            goto probe_next;
        }

        VALUE curr_key = rbimpl_atomic_value_load(&entry->key, RBIMPL_ATOMIC_ACQUIRE);

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY: {
            rb_atomic_t prev_size = rbimpl_atomic_fetch_add(&set->size, 1, RBIMPL_ATOMIC_RELAXED);

            // Load_factor reached at 75% full. ex: prev_size: 32, capacity: 64, load_factor: 50%.
            bool load_factor_reached = (uint64_t)(prev_size * 4) >= (uint64_t)(set->capacity * 3);

            if (UNLIKELY(load_factor_reached)) {
                concurrent_set_try_resize(set_obj, set_obj_ptr);
                goto retry;
            }

            VALUE prev_key = rbimpl_atomic_value_cas(&entry->key, CONCURRENT_SET_EMPTY, key, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
            if (prev_key == CONCURRENT_SET_EMPTY) {
                RUBY_ASSERT(rb_concurrent_set_find(set_obj_ptr, key) == key);
                RB_GC_GUARD(set_obj);
                return key;
            }
            else {
                // Entry was not inserted.
                rbimpl_atomic_sub(&set->size, 1, RBIMPL_ATOMIC_RELAXED);

                // Another thread won the race, try again at the same location.
                continue;
            }
          }
          case CONCURRENT_SET_DELETED:
            break;
          case CONCURRENT_SET_MOVED:
            // Wait
            RB_VM_LOCKING();
            goto retry;
          default:
            // We're never GC during our search
            // If the continuation bit wasn't set at the start of our search,
            // any concurrent find with the same hash value would also look at
            // this location and try to swap curr_key
            if (UNLIKELY(!RB_SPECIAL_CONST_P(curr_key) && rb_objspace_garbage_object_p(curr_key))) {
                if (continuation) {
                    goto probe_next;
                }
                rbimpl_atomic_value_cas(&entry->key, curr_key, CONCURRENT_SET_EMPTY, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
                continue;
            }

            if (set->funcs->cmp(key, curr_key)) {
                // We've found a live match.
                RB_GC_GUARD(set_obj);

                // We created key using set->funcs->create, but we didn't end
                // up inserting it into the set. Free it here to prevent memory
                // leaks.
                if (set->funcs->free) set->funcs->free(key);

                return curr_key;
            }
            break;
        }

      probe_next:
        RUBY_ASSERT(curr_hash_and_flags != CONCURRENT_SET_EMPTY);
        concurrent_set_mark_continuation(entry, curr_hash_and_flags);
        idx = concurrent_set_probe_next(&probe);
    }
}

static void
concurrent_set_delete_entry_locked(struct concurrent_set *set, struct concurrent_set_entry *entry)
{
    ASSERT_vm_locking_with_barrier();

    if (entry->hash & CONCURRENT_SET_CONTINUATION_BIT) {
        entry->hash = CONCURRENT_SET_CONTINUATION_BIT;
        entry->key = CONCURRENT_SET_DELETED;
        set->deleted_entries++;
    }
    else {
        entry->hash = CONCURRENT_SET_EMPTY;
        entry->key = CONCURRENT_SET_EMPTY;
        set->size--;
    }
}

VALUE
rb_concurrent_set_delete_by_identity(VALUE set_obj, VALUE key)
{
    ASSERT_vm_locking_with_barrier();

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    VALUE hash = concurrent_set_hash(set, key);

    struct concurrent_set_probe probe;
    int idx = concurrent_set_probe_start(&probe, set, hash);

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE curr_key = entry->key;

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY:
            // We didn't find our entry to delete.
            return 0;
          case CONCURRENT_SET_DELETED:
            break;
          case CONCURRENT_SET_MOVED:
            rb_bug("rb_concurrent_set_delete_by_identity: moved entry");
            break;
          default:
            if (key == curr_key) {
                RUBY_ASSERT((entry->hash & CONCURRENT_SET_HASH_MASK) == hash);
                concurrent_set_delete_entry_locked(set, entry);
                return curr_key;
            }
            break;
        }

        idx = concurrent_set_probe_next(&probe);
    }
}

void
rb_concurrent_set_foreach_with_replace(VALUE set_obj, int (*callback)(VALUE *key, void *data), void *data)
{
    ASSERT_vm_locking_with_barrier();

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    for (unsigned int i = 0; i < set->capacity; i++) {
        struct concurrent_set_entry *entry = &set->entries[i];
        VALUE key = entry->key;

        switch (key) {
          case CONCURRENT_SET_EMPTY:
          case CONCURRENT_SET_DELETED:
            continue;
          case CONCURRENT_SET_MOVED:
            rb_bug("rb_concurrent_set_foreach_with_replace: moved entry");
            break;
          default: {
            int ret = callback(&entry->key, data);
            switch (ret) {
              case ST_STOP:
                return;
              case ST_DELETE:
                concurrent_set_delete_entry_locked(set, entry);
                break;
            }
            break;
          }
        }
    }
}
