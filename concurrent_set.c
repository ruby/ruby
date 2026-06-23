#include "internal.h"
#include "internal/gc.h"
#include "internal/concurrent_set.h"
#include "ruby/atomic.h"
#include "vm_sync.h"

// insertion probes have gone past this slot
#define CONCURRENT_SET_CONTINUATION_BIT ((VALUE)0x2)
#define CONCURRENT_SET_KEY_MASK (~CONCURRENT_SET_CONTINUATION_BIT)
// This slot's hash can be reclaimed if and only if the key is EMPTY and it doesn't have a continuation bit. If the key is something
// else, this bit on the hash has no meaning and is ignored.
#define CONCURRENT_SET_HASH_RECLAIMABLE_BIT ((VALUE)1 << (sizeof(VALUE) * CHAR_BIT - 1))
#define CONCURRENT_SET_HASH_MASK (~CONCURRENT_SET_HASH_RECLAIMABLE_BIT)

#define CONCURRENT_SET_DEBUG 0
#define CONCURRENT_SET_DEBUG_STATS 0
#define CONCURRENT_SET_DEBUG_DUPLICATES 0
#define CONCURRENT_SET_DEBUG_BAD_HASH_FN 0

enum concurrent_set_special_values {
    CONCURRENT_SET_EMPTY = 0,
    CONCURRENT_SET_TOMBSTONE = 1,
    CONCURRENT_SET_MOVED = 5, // continuation bit is 0x02, so 0x05 doesn't have bits in conflict with it
    CONCURRENT_SET_SPECIAL_VALUE_COUNT = 6
};

struct concurrent_set_entry {
    VALUE hash;
    VALUE key;
};

struct concurrent_set {
    rb_atomic_t size;
    unsigned int capacity;
    rb_atomic_t deleted_entries;
    const struct rb_concurrent_set_funcs *funcs;
    struct concurrent_set_entry *entries;
    int key_type;
#if CONCURRENT_SET_DEBUG_STATS
    rb_atomic_t find_count;
    rb_atomic_t find_probe_total;
    rb_atomic_t find_probe_max;
    rb_atomic_t insert_count;
    rb_atomic_t insert_probe_total;
    rb_atomic_t insert_probe_max;
#endif
};

static bool
concurrent_set_mark_continuation(struct concurrent_set_entry *entry, VALUE raw_key)
{
    if (raw_key & CONCURRENT_SET_CONTINUATION_BIT) return true;

    VALUE new_key = raw_key | CONCURRENT_SET_CONTINUATION_BIT; // NOTE: raw_key can be CONCURRENT_SET_EMPTY
    VALUE prev_key = rbimpl_atomic_value_cas(&entry->key, raw_key, new_key, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_ACQUIRE);

    if (prev_key == raw_key || prev_key == new_key) {
        return true;
    }
    else if ((prev_key & CONCURRENT_SET_KEY_MASK) == CONCURRENT_SET_TOMBSTONE) {
        return true;
    }
    else {
        // * key could have been made EMPTY, and anything could have happened to this slot since then. Need to retry.
        // * key could have been moved during resize
        return false;
    }
}

static VALUE
concurrent_set_hash(const struct concurrent_set *set, VALUE key)
{
    VALUE hash = set->funcs->hash(key);
#if CONCURRENT_SET_DEBUG_BAD_HASH_FN
    hash = hash % 1024;
    if (hash == 0) hash = 1;
#endif
    hash &= CONCURRENT_SET_HASH_MASK;
    if (hash == 0) hash = ~(VALUE)0 & CONCURRENT_SET_HASH_MASK;
    RUBY_ASSERT(hash != 0);
    RUBY_ASSERT(!(hash & CONCURRENT_SET_HASH_RECLAIMABLE_BIT));
    return hash;
}

static void
concurrent_set_free(void *ptr)
{
    struct concurrent_set *set = ptr;
    SIZED_FREE_N(set->entries, set->capacity);
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
    /* NOTE: don't make embedded due to compaction */
    .flags = RUBY_TYPED_THREAD_SAFE_FREE
};

VALUE
rb_concurrent_set_new(const struct rb_concurrent_set_funcs *funcs, int capacity, int key_type)
{
    struct concurrent_set *set;
    VALUE obj = TypedData_Make_Struct(0, struct concurrent_set, &concurrent_set_type, set);
    set->funcs = funcs;
    set->entries = ZALLOC_N(struct concurrent_set_entry, capacity);
    set->capacity = capacity;
    (void)key_type;
#if CONCURRENT_SET_DEBUG
    set->key_type = key_type;
#endif
    return obj;
}

void *
rb_concurrent_set_get_data(VALUE set_obj)
{
    return RTYPEDDATA_GET_DATA(set_obj);
}

rb_atomic_t
rb_concurrent_set_size(VALUE set_obj)
{
    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    return RUBY_ATOMIC_LOAD(set->size);
}

unsigned int
rb_concurrent_set_capacity(VALUE set_obj)
{
    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    return set->capacity;
}

void
rb_concurrent_set_probe_stats(VALUE set_obj,
                              rb_atomic_t *find_count, rb_atomic_t *find_probe_total, rb_atomic_t *find_probe_max,
                              rb_atomic_t *insert_count, rb_atomic_t *insert_probe_total, rb_atomic_t *insert_probe_max)
{
#if CONCURRENT_SET_DEBUG_STATS
    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);
    *find_count = RUBY_ATOMIC_LOAD(set->find_count);
    *find_probe_total = RUBY_ATOMIC_LOAD(set->find_probe_total);
    *find_probe_max = RUBY_ATOMIC_LOAD(set->find_probe_max);
    *insert_count = RUBY_ATOMIC_LOAD(set->insert_count);
    *insert_probe_total = RUBY_ATOMIC_LOAD(set->insert_probe_total);
    *insert_probe_max = RUBY_ATOMIC_LOAD(set->insert_probe_max);
#else
    *find_count = 0;
    *find_probe_total = 0;
    *find_probe_max = 0;
    *insert_count = 0;
    *insert_probe_total = 0;
    *insert_probe_max = 0;
#endif
}

#if CONCURRENT_SET_DEBUG_STATS
static void
concurrent_set_atomic_max(rb_atomic_t *target, rb_atomic_t val)
{
    rb_atomic_t cur = RUBY_ATOMIC_LOAD(*target);
    while (val > cur) {
        rb_atomic_t prev = rbimpl_atomic_cas(target, cur, val, RBIMPL_ATOMIC_RELAXED, RBIMPL_ATOMIC_RELAXED);
        if (prev == cur) break;
        cur = prev;
    }
}
#endif

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

// NOTE: must not allocate or cause GC
static void
concurrent_set_try_resize_locked(VALUE old_set_obj, VALUE *set_obj_ptr, VALUE new_set_obj, int old_capacity)
{
    struct concurrent_set *old_set = RTYPEDDATA_GET_DATA(old_set_obj);
    struct concurrent_set_entry *old_entries = old_set->entries;
    struct concurrent_set *new_set = RTYPEDDATA_GET_DATA(new_set_obj);

    for (int i = 0; i < old_capacity; i++) {
        struct concurrent_set_entry *old_entry = &old_entries[i];
        VALUE prev_key_raw = rbimpl_atomic_value_exchange(&old_entry->key, CONCURRENT_SET_MOVED, RBIMPL_ATOMIC_ACQUIRE);
        VALUE prev_key = prev_key_raw & CONCURRENT_SET_KEY_MASK;
        RUBY_ASSERT(prev_key != CONCURRENT_SET_MOVED);

        if (prev_key < CONCURRENT_SET_SPECIAL_VALUE_COUNT) continue;

        if (!RB_SPECIAL_CONST_P(prev_key) && rb_objspace_garbage_object_p(prev_key)) continue;

#if CONCURRENT_SET_DEBUG
        if (new_set->key_type == T_STRING) {
            RUBY_ASSERT(BUILTIN_TYPE(prev_key) == T_STRING);
            RUBY_ASSERT(FL_TEST(prev_key, RSTRING_FSTR));
        }
        else {
            RUBY_ASSERT(STATIC_SYM_P(prev_key));
        }
#endif

        VALUE hash = rbimpl_atomic_value_load(&old_entry->hash, RBIMPL_ATOMIC_ACQUIRE) & CONCURRENT_SET_HASH_MASK;
        if (hash == 0) continue;
        RUBY_ASSERT(concurrent_set_hash(old_set, prev_key) == hash);

        // Insert key into new_set.
        struct concurrent_set_probe probe;
        int idx = concurrent_set_probe_start(&probe, new_set, hash);
        MAYBE_UNUSED(int start_idx) = idx;

        while (true) {
            struct concurrent_set_entry *entry = &new_set->entries[idx];

            if (entry->hash == 0) {
                RUBY_ASSERT(entry->key == CONCURRENT_SET_EMPTY);

                new_set->size++;
                RUBY_ASSERT(new_set->size <= new_set->capacity / 2);

                entry->key = prev_key; // no continuation bit
                entry->hash = hash;
                break;
            }

            RUBY_ASSERT(entry->key >= CONCURRENT_SET_SPECIAL_VALUE_COUNT);
            entry->key |= CONCURRENT_SET_CONTINUATION_BIT;
            idx = concurrent_set_probe_next(&probe);
            RUBY_ASSERT(idx != start_idx);
        }
    }

    rbimpl_atomic_value_store(set_obj_ptr, new_set_obj, RBIMPL_ATOMIC_RELEASE);

    RB_GC_GUARD(old_set_obj);
}

#if USE_PARALLEL_SWEEP
static pthread_mutex_t resize_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t resize_lock_owner;

static inline void
resize_lock_lock(void)
{
    int r;
#if VM_CHECK_MODE > 0
    RUBY_ASSERT(resize_lock_owner != pthread_self());
#endif
    if ((r = pthread_mutex_lock(&resize_lock))) {
        rb_bug_errno("pthread_mute_lock", r);
    }
#if VM_CHECK_MODE > 0
    resize_lock_owner = pthread_self();
#endif
}

static inline void
resize_lock_unlock(void)
{
    int r;
#if VM_CHECK_MODE > 0
    RUBY_ASSERT(resize_lock_owner == pthread_self());
    resize_lock_owner = 0;
#endif
    if ((r = pthread_mutex_unlock(&resize_lock))) {
        rb_bug_errno("pthread_mutex_unlock", r);
    }
}

#else
#define resize_lock_lock() (void)0
#define resize_lock_unlock() (void)0
#endif // USE_PARALLEL_SWEEP

static void
concurrent_set_try_resize(VALUE old_set_obj, VALUE *set_obj_ptr)
{
    unsigned int lev;
    RB_VM_LOCK_ENTER_LEV(&lev);
    {
        // Check if another thread has already resized.
        if (rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE) != old_set_obj) {
            RB_VM_LOCK_LEAVE_LEV(&lev);
            return;
        }
        struct concurrent_set *old_set = RTYPEDDATA_GET_DATA(old_set_obj);

        // This may overcount by up to the number of threads concurrently attempting to insert
        // GC may also happen between now and the set being rebuilt
        int expected_size = rbimpl_atomic_load(&old_set->size, RBIMPL_ATOMIC_RELAXED) - old_set->deleted_entries;

        // NOTE: new capacity must make sense with load factor, don't change one without checking the other.
        int old_capacity = old_set->capacity;
        int new_capacity = old_capacity * 2;
        if (new_capacity > expected_size * 8) {
            new_capacity = old_capacity / 2;
        }
        else if (new_capacity > expected_size * 4) {
            new_capacity = old_capacity;
        }

        // May cause GC and therefore deletes, so must happen first.
        VALUE new_set_obj = rb_concurrent_set_new(old_set->funcs, new_capacity, old_set->key_type);
        // deletes from sweep thread must not happen during resize and sweep thread can't take VM lock so it takes the resize lock
        resize_lock_lock();
        {
            concurrent_set_try_resize_locked(old_set_obj, set_obj_ptr, new_set_obj, old_capacity);
        }
        resize_lock_unlock();
    }
    RB_VM_LOCK_LEAVE_LEV(&lev);
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
        VALUE curr_hash = rbimpl_atomic_value_load(&entry->hash, RBIMPL_ATOMIC_ACQUIRE) & CONCURRENT_SET_HASH_MASK;

        if (curr_hash == 0) {
#if CONCURRENT_SET_DEBUG_STATS
            rbimpl_atomic_fetch_add(&set->find_count, 1, RBIMPL_ATOMIC_RELAXED);
            rbimpl_atomic_fetch_add(&set->find_probe_total, probe.d, RBIMPL_ATOMIC_RELAXED);
            concurrent_set_atomic_max(&set->find_probe_max, probe.d);
#endif
            return 0;
        }

        VALUE raw_key = rbimpl_atomic_value_load(&entry->key, RBIMPL_ATOMIC_ACQUIRE);
        VALUE curr_key = raw_key & CONCURRENT_SET_KEY_MASK;
        bool continuation = raw_key & CONCURRENT_SET_CONTINUATION_BIT;

        if (curr_hash != hash) {
            if (!continuation) {
#if CONCURRENT_SET_DEBUG_STATS
                rbimpl_atomic_fetch_add(&set->find_count, 1, RBIMPL_ATOMIC_RELAXED);
                rbimpl_atomic_fetch_add(&set->find_probe_total, probe.d, RBIMPL_ATOMIC_RELAXED);
                concurrent_set_atomic_max(&set->find_probe_max, probe.d);
#endif
                return 0;
            }
            idx = concurrent_set_probe_next(&probe);
            continue;
        }

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY:
            // In-progress insert: hash written but key not yet.
            break;
          case CONCURRENT_SET_TOMBSTONE:
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
#if CONCURRENT_SET_DEBUG_STATS
                rbimpl_atomic_fetch_add(&set->find_count, 1, RBIMPL_ATOMIC_RELAXED);
                rbimpl_atomic_fetch_add(&set->find_probe_total, probe.d, RBIMPL_ATOMIC_RELAXED);
                concurrent_set_atomic_max(&set->find_probe_max, probe.d);
#endif
                RB_GC_GUARD(set_obj);
                return curr_key;
            }

            if (!continuation) {
#if CONCURRENT_SET_DEBUG_STATS
                rbimpl_atomic_fetch_add(&set->find_count, 1, RBIMPL_ATOMIC_RELAXED);
                rbimpl_atomic_fetch_add(&set->find_probe_total, probe.d, RBIMPL_ATOMIC_RELAXED);
                concurrent_set_atomic_max(&set->find_probe_max, probe.d);
#endif
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
    key = set->funcs->create(key, data); // this can join GC (takes VM Lock)
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
        bool can_continue_probing;
        VALUE raw_hash = rbimpl_atomic_value_load(&entry->hash, RBIMPL_ATOMIC_ACQUIRE);
        VALUE curr_hash = raw_hash & CONCURRENT_SET_HASH_MASK;
        if (raw_hash == 0) {
            // Reserve this slot for our hash value
            raw_hash = rbimpl_atomic_value_cas(&entry->hash, 0, hash, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
            if (raw_hash != 0) {
                // Lost race, retry same slot to check winner's hash
                continue;
            }
            raw_hash = hash;
            curr_hash = hash;
            // Fall through to try to claim key
        }

        VALUE raw_key = rbimpl_atomic_value_load(&entry->key, RBIMPL_ATOMIC_ACQUIRE);
        VALUE curr_key = raw_key & CONCURRENT_SET_KEY_MASK;
        bool continuation = raw_key & CONCURRENT_SET_CONTINUATION_BIT;

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY: {
            if ((raw_hash & CONCURRENT_SET_HASH_RECLAIMABLE_BIT) && !continuation) {
                // Reclaim this reclaimable slot by clearing the reclaimable bit
                VALUE prev_hash = rbimpl_atomic_value_cas(&entry->hash, raw_hash, hash, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
                if (prev_hash != raw_hash) {
                    // Lost race, retry same slot
                    continue;
                }
                curr_hash = hash;
                raw_hash = hash;
            }
            if (curr_hash != hash) {
                goto probe_next;
            }
            rb_atomic_t prev_size = rbimpl_atomic_fetch_add(&set->size, 1, RBIMPL_ATOMIC_RELAXED);

            // Load_factor reached at 75% full. ex: prev_size: 32, capacity: 64, load_factor: 50%.
            bool load_factor_reached = (uint64_t)(prev_size * 4) >= (uint64_t)(set->capacity * 3);

            if (UNLIKELY(load_factor_reached)) {
                concurrent_set_try_resize(set_obj, set_obj_ptr);
                goto retry;
            }

            VALUE prev_raw_key = rbimpl_atomic_value_cas(&entry->key, raw_key, key | (continuation ? CONCURRENT_SET_CONTINUATION_BIT : 0), RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
            if (prev_raw_key == raw_key) {
#if CONCURRENT_SET_DEBUG_STATS
                rbimpl_atomic_fetch_add(&set->insert_count, 1, RBIMPL_ATOMIC_RELAXED);
                rbimpl_atomic_fetch_add(&set->insert_probe_total, probe.d, RBIMPL_ATOMIC_RELAXED);
                concurrent_set_atomic_max(&set->insert_probe_max, probe.d);
#endif
#if CONCURRENT_SET_DEBUG_DUPLICATES
                {
                    // Probe further to verify no duplicate of our key exists
                    struct concurrent_set_probe dup_probe = probe;
                    int dup_idx = concurrent_set_probe_next(&dup_probe);
                    int dup_idx_start = dup_idx;
                    while (true) {
                        struct concurrent_set_entry *dup_entry = &set->entries[dup_idx];
                        VALUE dup_raw_key = rbimpl_atomic_value_load(&dup_entry->key, RBIMPL_ATOMIC_ACQUIRE);
                        VALUE dup_key = dup_raw_key & CONCURRENT_SET_KEY_MASK;

                        if (dup_key == CONCURRENT_SET_EMPTY) break;
                        if (dup_key == CONCURRENT_SET_MOVED) break;

                        if (dup_key >= CONCURRENT_SET_SPECIAL_VALUE_COUNT && dup_key == key) {
                            rb_bug("concurrent_set_find_or_insert: duplicate key %p found at index %d after inserting at index %d",
                                   (void *)key, dup_idx, idx);
                        }
                        int next_dup_idx = concurrent_set_probe_next(&dup_probe);
                        if (dup_idx < dup_idx_start && next_dup_idx >= dup_idx_start) break;
                        if (next_dup_idx == dup_idx_start) break;
                        dup_idx = next_dup_idx;
                    }
                }
#endif
                RB_GC_GUARD(set_obj);
                return key;
            }
            else {
                // Entry was not inserted.
                rbimpl_atomic_sub(&set->size, 1, RBIMPL_ATOMIC_RELAXED);

                // * Another thread with the same hash could have won the race, try again at the same location, we might find it.
                // * A resize could also be underway, and `prev_raw_key` could be CONCURRENT_SET_MOVED.
                // * The continuation bit could also have been set on the key just now, in which case we'll retry
                continue;
            }
          }
          case CONCURRENT_SET_TOMBSTONE:
            break;
          case CONCURRENT_SET_MOVED:
            // Wait
            RB_VM_LOCKING();
            goto retry;
          default:
            if (curr_hash != hash) {
                goto probe_next;
            }
            // If the continuation bit wasn't set at the start of our search,
            // any concurrent find_or_insert with the same hash value would also look at
            // this location and try to swap curr_key
            if (UNLIKELY(!RB_SPECIAL_CONST_P(curr_key) && rb_objspace_garbage_object_p(curr_key))) {
                if (continuation) {
                    goto probe_next;
                }
                {
                    VALUE prev = rbimpl_atomic_value_cas(&entry->key, raw_key, CONCURRENT_SET_EMPTY, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
                    if (prev == raw_key) {
                        rbimpl_atomic_sub(&set->size, 1, RBIMPL_ATOMIC_RELAXED);
                    }
                }
                continue; // try to reclaim same slot, because the hash is the same and it's now EMPTY
            }

            if (set->funcs->cmp(key, curr_key)) {
                // We've found a live match.
#if CONCURRENT_SET_DEBUG_STATS
                rbimpl_atomic_fetch_add(&set->insert_count, 1, RBIMPL_ATOMIC_RELAXED);
                rbimpl_atomic_fetch_add(&set->insert_probe_total, probe.d, RBIMPL_ATOMIC_RELAXED);
                concurrent_set_atomic_max(&set->insert_probe_max, probe.d);
#endif
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
        can_continue_probing =  concurrent_set_mark_continuation(entry, raw_key);
        if (!can_continue_probing) {
            continue;
        }
        idx = concurrent_set_probe_next(&probe);
    }
}

static void
concurrent_set_delete_entry_locked(struct concurrent_set *set, struct concurrent_set_entry *entry)
{
    ASSERT_vm_locking_with_barrier();

    if (entry->key & CONCURRENT_SET_CONTINUATION_BIT) {
        entry->key = CONCURRENT_SET_TOMBSTONE | CONCURRENT_SET_CONTINUATION_BIT;
        set->deleted_entries++;
    }
    else {
        entry->hash = 0;
        entry->key = CONCURRENT_SET_EMPTY;
        set->size--;
    }
}


static VALUE
rb_concurrent_set_delete_by_identity_locked(VALUE set_obj, VALUE key)
{

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    VALUE hash = concurrent_set_hash(set, key);

    struct concurrent_set_probe probe;
    int idx = concurrent_set_probe_start(&probe, set, hash);
    bool hash_cleared = false;
    MAYBE_UNUSED(VALUE prev_hash) = 0;

    while (true) {
        struct concurrent_set_entry *entry = &set->entries[idx];
        VALUE raw_key = rbimpl_atomic_value_load(&entry->key, RBIMPL_ATOMIC_ACQUIRE);
        VALUE loaded_hash_raw = rbimpl_atomic_value_load(&entry->hash, RBIMPL_ATOMIC_ACQUIRE);
        MAYBE_UNUSED(VALUE loaded_hash) = loaded_hash_raw & CONCURRENT_SET_HASH_MASK;
        bool continuation = raw_key & CONCURRENT_SET_CONTINUATION_BIT;
        VALUE curr_key = raw_key & CONCURRENT_SET_KEY_MASK;

        switch (curr_key) {
          case CONCURRENT_SET_EMPTY:
            if (!continuation) {
                return 0;
            }
            break;
          case CONCURRENT_SET_TOMBSTONE:
            break;
          case CONCURRENT_SET_MOVED:
            rb_bug("rb_concurrent_set_delete_by_identity: moved entry");
            break;
          default:
            if (key == curr_key) {
                VALUE new_key;
                RUBY_ASSERT(hash_cleared || loaded_hash == hash);
                if (continuation) {
                    new_key = CONCURRENT_SET_TOMBSTONE | CONCURRENT_SET_CONTINUATION_BIT;
                }
                else {
                    new_key = CONCURRENT_SET_EMPTY;
                }

                if (!hash_cleared) {
                    // Hashes only change here and they get reclaimed in find_or_insert
                    prev_hash = rbimpl_atomic_value_cas(&entry->hash, loaded_hash_raw, hash | CONCURRENT_SET_HASH_RECLAIMABLE_BIT, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_RELAXED);
                    RUBY_ASSERT(prev_hash == hash || prev_hash == (hash | CONCURRENT_SET_HASH_RECLAIMABLE_BIT));
                    hash_cleared = true;
                }
                VALUE prev_key = rbimpl_atomic_value_cas(&entry->key, raw_key, new_key, RBIMPL_ATOMIC_RELEASE, RBIMPL_ATOMIC_ACQUIRE);
                if (prev_key == raw_key) {
                    if (continuation) {
                        rbimpl_atomic_add(&set->deleted_entries, 1, RBIMPL_ATOMIC_RELAXED);
                    }
                    else {
                        rbimpl_atomic_sub(&set->size, 1, RBIMPL_ATOMIC_RELAXED);
                    }
                    return curr_key;
                }
                else if (!continuation && prev_key == (raw_key | CONCURRENT_SET_CONTINUATION_BIT)) {
                    continue; // try again, the continuation bit was just set on this key so we can tombstone it
                }
                else if ((prev_key & CONCURRENT_SET_KEY_MASK) == CONCURRENT_SET_EMPTY || (prev_key & CONCURRENT_SET_KEY_MASK) == CONCURRENT_SET_TOMBSTONE) {
                    return curr_key; // the key was deleted by another thread
                }
                else {
                    // the key was changed to EMPTY by being garbage during find_or_insert and then a new key was put at the same slot. It's okay
                    // that the hash was marked reclaimable above.
                    RUBY_ASSERT(prev_hash != 0);
                    return curr_key;
                }
            }
            else if (!continuation) {
                return 0;
            }
            break;
        }

        idx = concurrent_set_probe_next(&probe);
    }
}

// This can be called concurrently by a ruby GC thread and the sweep thread.
VALUE
rb_concurrent_set_delete_by_identity(VALUE *set_obj_ptr, VALUE key)
{
    VALUE result;

    VALUE set_obj = rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE);

#if USE_PARALLEL_SWEEP
    if (is_sweep_thread_p()) {
        while (1) {
            resize_lock_lock();
            {
                VALUE current_set_obj = rbimpl_atomic_value_load(set_obj_ptr, RBIMPL_ATOMIC_ACQUIRE);
                if (current_set_obj != set_obj) {
                    set_obj = current_set_obj;
                    // retry - resize happened
                }
                else {
                    result = rb_concurrent_set_delete_by_identity_locked(set_obj, key);
                    resize_lock_unlock();
                    break;
                }
            }
            resize_lock_unlock();
        }
    }
    else
#endif
    {
        result = rb_concurrent_set_delete_by_identity_locked(set_obj, key);
    }
    return result;
}

static void
rb_concurrent_set_foreach_with_replace_locked(VALUE set_obj, int (*callback)(VALUE *key, void *data), void *data)
{
    ASSERT_vm_locking_with_barrier();

    struct concurrent_set *set = RTYPEDDATA_GET_DATA(set_obj);

    for (unsigned int i = 0; i < set->capacity; i++) {
        struct concurrent_set_entry *entry = &set->entries[i];
        VALUE raw_key = entry->key;
        bool continuation = raw_key & CONCURRENT_SET_CONTINUATION_BIT;
        VALUE key = raw_key & CONCURRENT_SET_KEY_MASK;

        switch (key) {
          case CONCURRENT_SET_EMPTY:
          case CONCURRENT_SET_TOMBSTONE:
            continue;
          case CONCURRENT_SET_MOVED:
            rb_bug("rb_concurrent_set_foreach_with_replace: moved entry");
            break;
          default: {
            VALUE cb_key = key;
            int ret = callback(&cb_key, data);
            switch (ret) {
              case ST_STOP:
                return;
              case ST_DELETE:
                concurrent_set_delete_entry_locked(set, entry);
                break;
              case ST_CONTINUE:
                if (cb_key != key) {
                    // Key was replaced by callback
                    entry->key = cb_key | (continuation ? CONCURRENT_SET_CONTINUATION_BIT : 0);
                }
                break;
              case ST_REPLACE:
                rb_bug("unexpected concurrent_set callback return value: ST_REPLACE");
            }
            break;
          }
        }
    }
}

// NOTE: `callback` must not cause GC
void
rb_concurrent_set_foreach_with_replace(VALUE set_obj, int (*callback)(VALUE *key, void *data), void *data)
{
    RB_VM_LOCKING() {
        // Don't allow concurrent deletes from sweep thread during this time.
        resize_lock_lock();
        {
            rb_concurrent_set_foreach_with_replace_locked(set_obj, callback, data);
        }
        resize_lock_unlock();
    }
}
