#include "internal.h"
#include "internal/gc.h"
#include "internal/ractor_safe_set.h"
#include "ruby_atomic.h"
#include "ruby/atomic.h"
#include "vm_sync.h"

enum ractor_safe_set_special_values {
    RACTOR_SAFE_TABLE_EMPTY,
    RACTOR_SAFE_TABLE_DELETED,
    RACTOR_SAFE_TABLE_MOVED,
    RACTOR_SAFE_TABLE_SPECIAL_VALUE_COUNT
};

struct ractor_safe_set_entry {
    VALUE hash;
    VALUE key;
};

struct ractor_safe_set {
    rb_atomic_t size;
    unsigned int capacity;
    unsigned int deleted_entries;
    struct rb_ractor_safe_set_funcs *funcs;
    struct ractor_safe_set_entry *entries;
};

static void
ractor_safe_set_free(void *ptr)
{
    struct ractor_safe_set *set = ptr;
    xfree(set->entries);
}

static size_t
ractor_safe_set_size(const void *ptr)
{
    const struct ractor_safe_set *set = ptr;
    return sizeof(struct ractor_safe_set) +
        (set->capacity * sizeof(struct ractor_safe_set_entry));
}

static const rb_data_type_t ractor_safe_set_type = {
    .wrap_struct_name = "VM/ractor_safe_set",
    .function = {
        .dmark = NULL,
        .dfree = ractor_safe_set_free,
        .dsize = ractor_safe_set_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

VALUE
rb_ractor_safe_set_new(struct rb_ractor_safe_set_funcs *funcs, int capacity)
{
    struct ractor_safe_set *set;
    VALUE obj = TypedData_Make_Struct(0, struct ractor_safe_set, &ractor_safe_set_type, set);
    set->funcs = funcs;
    set->entries = ZALLOC_N(struct ractor_safe_set_entry, capacity);
    set->capacity = capacity;
    return obj;
}

struct ractor_safe_set_probe {
    int idx;
    int d;
    int mask;
};

static int
ractor_safe_set_probe_start(struct ractor_safe_set_probe *probe, struct ractor_safe_set *set, VALUE hash)
{
    RUBY_ASSERT((set->capacity & (set->capacity - 1)) == 0);
    probe->d = 0;
    probe->mask = set->capacity - 1;
    probe->idx = hash & probe->mask;
    return probe->idx;
}

static int
ractor_safe_set_probe_next(struct ractor_safe_set_probe *probe)
{
    probe->d++;
    probe->idx = (probe->idx + probe->d) & probe->mask;
    return probe->idx;
}

static void
ractor_safe_set_try_resize_without_locking(VALUE old_set_obj, VALUE *set_obj_ptr)
{
    // Check if another thread has already resized.
    if (RUBY_ATOMIC_VALUE_LOAD(*set_obj_ptr) != old_set_obj) {
        return;
    }

    struct ractor_safe_set *old_set = RTYPEDDATA_GET_DATA(old_set_obj);

    // This may overcount by up to the number of threads concurrently attempting to insert
    // GC may also happen between now and the set being rebuilt
    int expected_size = RUBY_ATOMIC_LOAD(old_set->size) - old_set->deleted_entries;

    struct ractor_safe_set_entry *old_entries = old_set->entries;
    int old_capacity = old_set->capacity;
    int new_capacity = old_capacity * 2;
    if (new_capacity > expected_size * 8) {
        new_capacity = old_capacity / 2;
    }
    else if (new_capacity > expected_size * 4) {
        new_capacity = old_capacity;
    }

    // May cause GC and therefore deletes, so must hapen first.
    VALUE new_set_obj = rb_ractor_safe_set_new(old_set->funcs, new_capacity);
    struct ractor_safe_set *new_set = RTYPEDDATA_GET_DATA(new_set_obj);

    for (int i = 0; i < old_capacity; i++) {
        struct ractor_safe_set_entry *entry = &old_entries[i];
        VALUE key = RUBY_ATOMIC_VALUE_EXCHANGE(entry->key, RACTOR_SAFE_TABLE_MOVED);
        RUBY_ASSERT(key != RACTOR_SAFE_TABLE_MOVED);

        if (key < RACTOR_SAFE_TABLE_SPECIAL_VALUE_COUNT) continue;
        if (rb_objspace_garbage_object_p(key)) continue;

        VALUE hash = RUBY_ATOMIC_VALUE_LOAD(entry->hash);
        if (hash == 0) {
            // Either in-progress insert or extremely unlikely 0 hash.
            // Re-calculate the hash.
            hash = old_set->funcs->hash(key);
        }
        RUBY_ASSERT(hash == old_set->funcs->hash(key));

        // Insert key into new_set.
        struct ractor_safe_set_probe probe;
        int idx = ractor_safe_set_probe_start(&probe, new_set, hash);

        while (true) {
            struct ractor_safe_set_entry *entry = &new_set->entries[idx];

            if (entry->key == RACTOR_SAFE_TABLE_EMPTY) {
                new_set->size++;

                RUBY_ASSERT(new_set->size < new_set->capacity / 2);
                RUBY_ASSERT(entry->hash == 0);

                entry->key = key;
                entry->hash = hash;
                break;
            }
            else {
                RUBY_ASSERT(entry->key >= RACTOR_SAFE_TABLE_SPECIAL_VALUE_COUNT);
            }

            idx = ractor_safe_set_probe_next(&probe);
        }
    }

    RUBY_ATOMIC_VALUE_SET(*set_obj_ptr, new_set_obj);

    RB_GC_GUARD(old_set_obj);
}

static void
ractor_safe_set_try_resize(VALUE old_set_obj, VALUE *set_obj_ptr)
{
    RB_VM_LOCKING() {
        ractor_safe_set_try_resize_without_locking(old_set_obj, set_obj_ptr);
    }
}

VALUE
rb_ractor_safe_set_find_or_insert(VALUE *set_obj_ptr, VALUE key, void *data)
{
    RUBY_ASSERT(key >= RACTOR_SAFE_TABLE_SPECIAL_VALUE_COUNT);

    bool inserting = false;
    VALUE set_obj;

  retry:
    set_obj = RUBY_ATOMIC_VALUE_LOAD(*set_obj_ptr);
    RUBY_ASSERT(set_obj);
    struct ractor_safe_set *set = RTYPEDDATA_GET_DATA(set_obj);

    struct ractor_safe_set_probe probe;
    VALUE hash = set->funcs->hash(key);
    int idx = ractor_safe_set_probe_start(&probe, set, hash);

    while (true) {
        struct ractor_safe_set_entry *entry = &set->entries[idx];
        VALUE curr_key = RUBY_ATOMIC_VALUE_LOAD(entry->key);

        switch (curr_key) {
          case RACTOR_SAFE_TABLE_EMPTY: {
            // Not in set
            if (!inserting) {
                key = set->funcs->create(key, data);
                RUBY_ASSERT(hash == set->funcs->hash(key));
                inserting = true;
            }

            rb_atomic_t prev_size = RUBY_ATOMIC_FETCH_ADD(set->size, 1);

            if (UNLIKELY(prev_size > set->capacity / 2)) {
                ractor_safe_set_try_resize(set_obj, set_obj_ptr);

                goto retry;
            }

            curr_key = RUBY_ATOMIC_VALUE_CAS(entry->key, RACTOR_SAFE_TABLE_EMPTY, key);
            if (curr_key == RACTOR_SAFE_TABLE_EMPTY) {
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
          case RACTOR_SAFE_TABLE_DELETED:
            break;
          case RACTOR_SAFE_TABLE_MOVED:
            // Wait
            RB_VM_LOCKING();

            goto retry;
          default: {
            VALUE curr_hash = RUBY_ATOMIC_VALUE_LOAD(entry->hash);
            if ((curr_hash == hash || curr_hash == 0) && set->funcs->cmp(key, curr_key)) {
                // We've found a match.
                if (UNLIKELY(rb_objspace_garbage_object_p(curr_key))) {
                    // This is a weakref set, so after marking but before sweeping is complete we may find a matching garbage object.
                    // Skip it and mark it as deleted.
                    RUBY_ATOMIC_VALUE_CAS(entry->key, curr_key, RACTOR_SAFE_TABLE_DELETED);

                    // Fall through and continue our search.
                }
                else {
                    RB_GC_GUARD(set_obj);
                    return curr_key;
                }
            }

            break;
          }
        }

        idx = ractor_safe_set_probe_next(&probe);
    }
}

VALUE
rb_ractor_safe_set_delete_by_identity(VALUE set_obj, VALUE key)
{
    // Assume locking and barrier (which there is no assert for).
    ASSERT_vm_locking();

    struct ractor_safe_set *set = RTYPEDDATA_GET_DATA(set_obj);

    VALUE hash = set->funcs->hash(key);

    struct ractor_safe_set_probe probe;
    int idx = ractor_safe_set_probe_start(&probe, set, hash);

    while (true) {
        struct ractor_safe_set_entry *entry = &set->entries[idx];
        VALUE curr_key = RUBY_ATOMIC_VALUE_LOAD(entry->key);

        switch (curr_key) {
          case RACTOR_SAFE_TABLE_EMPTY:
            // We didn't find our entry to delete.
            return 0;
          case RACTOR_SAFE_TABLE_DELETED:
            break;
          case RACTOR_SAFE_TABLE_MOVED:
            rb_bug("rb_ractor_safe_set_delete_by_identity: moved entry");
            break;
          default:
            if (key == curr_key) {
                entry->key = RACTOR_SAFE_TABLE_DELETED;
                set->deleted_entries++;
                return curr_key;
            }
            break;
        }

        idx = ractor_safe_set_probe_next(&probe);
    }
}

void
rb_ractor_safe_set_foreach_with_replace(VALUE set_obj, int (*callback)(VALUE *key, void *data), void *data)
{
    // Assume locking and barrier (which there is no assert for).
    ASSERT_vm_locking();

    struct ractor_safe_set *set = RTYPEDDATA_GET_DATA(set_obj);

    for (unsigned int i = 0; i < set->capacity; i++) {
        VALUE key = set->entries[i].key;

        switch (key) {
          case RACTOR_SAFE_TABLE_EMPTY:
          case RACTOR_SAFE_TABLE_DELETED:
            continue;
          case RACTOR_SAFE_TABLE_MOVED:
            rb_bug("rb_ractor_safe_set_foreach_with_replace: moved entry");
            break;
          default: {
            int ret = callback(&set->entries[i].key, data);
            switch (ret) {
              case ST_STOP:
                return;
              case ST_DELETE:
                set->entries[i].key = RACTOR_SAFE_TABLE_DELETED;
                break;
            }
            break;
          }
        }
    }
}
