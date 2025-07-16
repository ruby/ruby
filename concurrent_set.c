#include "internal.h"
#include "internal/gc.h"
#include "internal/concurrent_set.h"
#include "ruby_atomic.h"
#include "ruby/atomic.h"
#include "vm_sync.h"

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

static const rb_data_type_t concurrent_set_type = {
    .wrap_struct_name = "VM/concurrent_set",
    .function = {
        .dmark = NULL,
        .dfree = concurrent_set_free,
        .dsize = concurrent_set_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
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
    if (RUBY_ATOMIC_VALUE_LOAD(*set_obj_ptr) != old_set_obj) {
        return;
    }

    struct concurrent_set *old_set = RTYPEDDATA_GET_DATA(old_set_obj);

    // This may overcount by up to the number of threads concurrently attempting to insert
    // GC may also happen between now and the set being rebuilt
    int expected_size = RUBY_ATOMIC_LOAD(old_set->size) - old_set->deleted_entries;

    struct concurrent_set_entry *old_entries = old_set->entries;
    int old_capacity = old_set->capacity;
    int new_capacity = old_capacity * 2;
    if (new_capacity > expected_size * 8) {
        new_capacity = old_capacity / 2;
    }
    else if (new_capacity > expected_size * 4) {
        new_capacity = old_capacity;
    }

    // May cause GC and therefore deletes, so must hapen first.
    VALUE new_set_obj = rb_concurrent_set_new(old_set->funcs, new_capacity);
    struct concurrent_set *new_set = RTYPEDDATA_GET_DATA(new_set_obj);

    for (int i = 0; i < old_capacity; i++) {
        struct concurrent_set_entry *entry = &old_entries[i];
        VALUE key = RUBY_ATOMIC_VALUE_EXCHANGE(entry->key, CONCURRENT_SET_MOVED);
        RUBY_ASSERT(key != CONCURRENT_SET_MOVED);

        if (key < CONCURRENT_SET_SPECIAL_VALUE_COUNT) continue;
        if (!RB_SPECIAL_CONST_P(key) && rb_objspace_garbage_object_p(key)) continue;

        VALUE hash = RUBY_ATOMIC_VALUE_LOAD(entry->hash);
        if (hash == 0) {
            // Either in-progress insert or extremely unlikely 0 hash.
            // Re-calculate the hash.
            hash = old_set->funcs->hash(key);
        }
        RUBY_ASSERT(hash == old_set->funcs->hash(key));

        // Insert key into new_set.
        struct concurrent_set_probe probe;
        int idx = concurrent_set_probe_start(&probe, new_set, hash);

        while (true) {
            struct concurrent_set_entry *entry = &new_set->entries[idx];

            if (entry->key == CONCURRENT_SET_EMPTY) {
                new_set->size++;

                RUBY_ASSERT(new_set->size <= new_set->capacity / 2);
                RUBY_ASSERT(entry->hash == 0);

                entry->key = key;
                entry->hash = hash;
                break;
            }
            else {
                RUBY_ASSERT(entry->key >= CONCURRENT_SET_SPECIAL_VALUE_COUNT);
            }

            idx = concurrent_set_probe_next(&probe);
        }
    }

    RUBY_ATOMIC_VALUE_SET(*set_obj_ptr, new_set_obj);

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

  retry:
    set_obj = RUBY_ATOMIC_VALUE_LOAD(*set_obj_ptr);
    RUBY_ASSERT(set_obj);
    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    struct concurrent_set_probe probe;
    VALUE hash = set->funcs->hash(key);
    int idx = concurrent_set_probe_start(&probe, set, hash);

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE curr_key = RUBY_ATOMIC_VALUE_LOAD(entry->key);

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY:
            return 0;
          case CONCURRENT_SET_DELETED:
            break;
          case CONCURRENT_SET_MOVED:
            // Wait
            RB_VM_LOCKING();

            goto retry;
          default: {
            VALUE curr_hash = RUBY_ATOMIC_VALUE_LOAD(entry->hash);
            if (curr_hash != 0 && curr_hash != hash) break;

            if (UNLIKELY(!RB_SPECIAL_CONST_P(curr_key) && rb_objspace_garbage_object_p(curr_key))) {
                // This is a weakref set, so after marking but before sweeping is complete we may find a matching garbage object.
                // Skip it and mark it as deleted.
                RUBY_ATOMIC_VALUE_CAS(entry->key, curr_key, CONCURRENT_SET_DELETED);
                break;
            }

            if (set->funcs->cmp(key, curr_key)) {
                // We've found a match.
                RB_GC_GUARD(set_obj);
                return curr_key;
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

    bool inserting = false;
    VALUE set_obj;

  retry:
    set_obj = RUBY_ATOMIC_VALUE_LOAD(*set_obj_ptr);
    RUBY_ASSERT(set_obj);
    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    struct concurrent_set_probe probe;
    VALUE hash = set->funcs->hash(key);
    int idx = concurrent_set_probe_start(&probe, set, hash);

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE curr_key = RUBY_ATOMIC_VALUE_LOAD(entry->key);

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY: {
            // Not in set
            if (!inserting) {
                key = set->funcs->create(key, data);
                RUBY_ASSERT(hash == set->funcs->hash(key));
                inserting = true;
            }

            rb_atomic_t prev_size = RUBY_ATOMIC_FETCH_ADD(set->size, 1);

            if (UNLIKELY(prev_size > set->capacity / 2)) {
                concurrent_set_try_resize(set_obj, set_obj_ptr);

                goto retry;
            }

            curr_key = RUBY_ATOMIC_VALUE_CAS(entry->key, CONCURRENT_SET_EMPTY, key);
            if (curr_key == CONCURRENT_SET_EMPTY) {
                RUBY_ATOMIC_VALUE_SET(entry->hash, hash);

                RB_GC_GUARD(set_obj);
                return key;
            }
            else {
                // Entry was not inserted.
                RUBY_ATOMIC_DEC(set->size);

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
          default: {
            VALUE curr_hash = RUBY_ATOMIC_VALUE_LOAD(entry->hash);
            if (curr_hash != 0 && curr_hash != hash) break;

            if (UNLIKELY(!RB_SPECIAL_CONST_P(curr_key) && rb_objspace_garbage_object_p(curr_key))) {
                // This is a weakref set, so after marking but before sweeping is complete we may find a matching garbage object.
                // Skip it and mark it as deleted.
                RUBY_ATOMIC_VALUE_CAS(entry->key, curr_key, CONCURRENT_SET_DELETED);
                break;
            }

            if (set->funcs->cmp(key, curr_key)) {
                // We've found a match.
                RB_GC_GUARD(set_obj);
                return curr_key;
            }

            break;
          }
        }

        idx = concurrent_set_probe_next(&probe);
    }
}

VALUE
rb_concurrent_set_delete_by_identity(VALUE set_obj, VALUE key)
{
    // Assume locking and barrier (which there is no assert for).
    ASSERT_vm_locking();

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    VALUE hash = set->funcs->hash(key);

    struct concurrent_set_probe probe;
    int idx = concurrent_set_probe_start(&probe, set, hash);

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE curr_key = RUBY_ATOMIC_VALUE_LOAD(entry->key);

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
                entry->key = CONCURRENT_SET_DELETED;
                set->deleted_entries++;
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
    // Assume locking and barrier (which there is no assert for).
    ASSERT_vm_locking();

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    for (unsigned int i = 0; i < set->capacity; i++) {
        struct concurrent_set_entry *entry = &set->entries[i];
        VALUE key = set->entries[i].key;

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
                set->entries[i].key = CONCURRENT_SET_DELETED;
                break;
            }
            break;
          }
        }
    }
}
