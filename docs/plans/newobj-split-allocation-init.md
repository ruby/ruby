# Plan: Split Object Allocation from Initialization

## Summary

Separate `rb_gc_impl_new_obj` into a pure allocator (returns T_NONE raw memory)
and move RBasic initialization into `newobj_of` in gc.c. GC-specific bitmap
operations move to a new `rb_gc_impl_post_alloc_init` callback.

**Research**: `docs/research/newobj-split-allocation-init.md`

## Design Decisions

### Interface

```c
// Pure allocator — returns raw T_NONE memory
GC_IMPL_FN VALUE rb_gc_impl_new_obj(void *objspace_ptr, void *cache_ptr, bool wb_protected, size_t alloc_size);

// GC-specific post-init — called after gc.c sets flags/klass/shape_id
GC_IMPL_FN void rb_gc_impl_post_alloc_init(void *objspace_ptr, VALUE obj, VALUE flags, bool wb_protected);
```

`wb_protected` stays in the allocator — the default GC uses it for fast/slow
path lock routing, which is a GC-internal concern.

`klass` and `flags` are removed from the allocator. `flags` is passed to
`post_alloc_init` to avoid a redundant memory read.

### `stress_to_class` relocation

The debug-only `stress_to_class` check (currently inside `rb_gc_impl_new_obj`,
reads `klass`) is separate from `GC.stress` — it's `GC.add_stress_to_class`,
stored as a Hash in `objspace->stress_to_class` (default GC line 648). Since
it lives in objspace, it can't be directly accessed from gc.c.

Add a new predicate to the interface:
```c
GC_IMPL_FN bool rb_gc_impl_stress_to_class_p(void *objspace_ptr, VALUE klass);
```

The default GC implements this by checking
`stress_to_class && rb_hash_lookup2(stress_to_class, klass, Qundef) != Qundef`.
MMTk returns false (no support). This is gated behind `GC_DEBUG_STRESS_TO_CLASS`
which is only defined in debug builds.

### MMTk `mmtk_add_obj_free_candidate`

This calls `obj_can_parallel_free_p` which reads `BUILTIN_TYPE(obj)` — needs
flags set. Moves from `rb_gc_impl_new_obj` to `rb_gc_impl_post_alloc_init`.

`mmtk_post_alloc` stays in `rb_gc_impl_new_obj` — it's allocation finalization
(tells MMTk the bump pointer advanced), not object initialization.

### Locking

The default GC slow path lock (`RB_GC_CR_LOCK`) currently covers alloc + init.
After the split, it covers only alloc. This is safe:
- Flag/klass writes go to ractor-exclusive memory (just popped from freelist)
- Bitmap writes go to ractor-cached pages; GC isn't active post-slowpath
- No concurrent marker reads bitmaps while we're writing

### New `newobj_of` flow

```
newobj_of(cr, klass, flags, shape_id, wb_protected, size)
  [stress_to_class check — debug only]
  Phase 1: obj = rb_gc_impl_new_obj(objspace, cache, wb_protected, size)  // T_NONE
  Phase 2: RBASIC(obj)->flags = flags                                     // generic init
           RBASIC(obj)->klass = klass
           RBASIC_SET_SHAPE_ID_NO_CHECKS(obj, shape_id)
  Phase 3: rb_gc_impl_post_alloc_init(objspace, obj, flags, wb_protected) // GC bitmaps
  Phase 4: gc_validate_pc + NEWOBJ event hook                             // unchanged
  return obj
```

Flags MUST be set before shape_id — on 64-bit, shape_id is packed in the upper
bits of flags via `RBASIC_SET_SHAPE_ID_NO_CHECKS`.

---

## Implementation Steps

### Step 1: Add `rb_gc_impl_post_alloc_init` to interface

**File**: `gc/gc_impl.h:58`

Add after the existing `rb_gc_impl_new_obj` declaration:

```c
GC_IMPL_FN void rb_gc_impl_post_alloc_init(void *objspace_ptr, VALUE obj, VALUE flags, bool wb_protected);
GC_IMPL_FN bool rb_gc_impl_stress_to_class_p(void *objspace_ptr, VALUE klass);
```

**No behavioral change yet** — just declaring the new functions.

### Step 2: Implement `rb_gc_impl_post_alloc_init` in default GC

**File**: `gc/default/default.c`

Extract from `newobj_init` (lines 2171-2220) into a new function. Everything
that reads GC-internal state (bitmaps, age bits, profiling counters) moves here.
What stays out: the `RBASIC(obj)->flags = flags` and `klass` assignments (those
move to gc.c in step 4).

```c
void
rb_gc_impl_post_alloc_init(void *objspace_ptr, VALUE obj, VALUE flags, bool wb_protected)
{
    rb_objspace_t *objspace = objspace_ptr;

    GC_ASSERT(BUILTIN_TYPE(obj) != T_NONE);

    int t = flags & RUBY_T_MASK;
    if (t == T_CLASS || t == T_MODULE || t == T_ICLASS) {
        RVALUE_AGE_SET_CANDIDATE(objspace, obj);
    }

#if RACTOR_CHECK_MODE
    void rb_ractor_setup_belonging(VALUE obj);
    rb_ractor_setup_belonging(obj);
#endif

#if RGENGC_CHECK_MODE
    int lev = RB_GC_VM_LOCK_NO_BARRIER();
    {
        check_rvalue_consistency(objspace, obj);
        GC_ASSERT(RVALUE_MARKED(objspace, obj) == FALSE);
        GC_ASSERT(RVALUE_MARKING(objspace, obj) == FALSE);
        GC_ASSERT(RVALUE_OLD_P(objspace, obj) == FALSE);
        GC_ASSERT(RVALUE_WB_UNPROTECTED(objspace, obj) == FALSE);
        if (RVALUE_REMEMBERED(objspace, obj)) rb_bug("newobj: %s is remembered.", rb_obj_info(obj));
    }
    RB_GC_VM_UNLOCK_NO_BARRIER(lev);
#endif

    if (RB_UNLIKELY(wb_protected == FALSE)) {
        MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), obj);
    }

#if RGENGC_PROFILE
    if (wb_protected) {
        objspace->profile.total_generated_normal_object_count++;
#if RGENGC_PROFILE >= 2
        objspace->profile.generated_normal_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
    else {
        objspace->profile.total_generated_shady_object_count++;
#if RGENGC_PROFILE >= 2
        objspace->profile.generated_shady_object_count_types[BUILTIN_TYPE(obj)]++;
#endif
    }
#endif

#if GC_DEBUG
    GET_RVALUE_OVERHEAD(obj)->file = rb_gc_impl_source_location_cstr(&GET_RVALUE_OVERHEAD(obj)->line);
    GC_ASSERT(!SPECIAL_CONST_P(obj));
#endif

    gc_report(5, objspace, "newobj: %s\n", rb_obj_info(obj));
}
```

### Step 3: Implement `rb_gc_impl_post_alloc_init` in MMTk

**File**: `gc/mmtk/mmtk.c`

```c
void
rb_gc_impl_post_alloc_init(void *objspace_ptr, VALUE obj, VALUE flags, bool wb_protected)
{
    mmtk_add_obj_free_candidate((VALUE *)obj, obj_can_parallel_free_p(obj));
}
```

Moved from `rb_gc_impl_new_obj` because `obj_can_parallel_free_p` reads
`BUILTIN_TYPE(obj)` which requires flags to be set.

### Step 4: Restructure `newobj_of` in gc.c

**File**: `gc.c:1005-1046`

Replace the current `newobj_of` with the 4-phase version:

```c
static inline VALUE
newobj_of(rb_ractor_t *cr, VALUE klass, VALUE flags, shape_id_t shape_id, bool wb_protected, size_t size)
{
    void *objspace = rb_gc_get_objspace();

    // Phase 1: Pure allocation
    VALUE obj = rb_gc_impl_new_obj(objspace, cr->newobj_cache, wb_protected, size);

    // Phase 2: Generic init — set RBasic fields
    RBASIC(obj)->flags = flags;
    *((VALUE *)&RBASIC(obj)->klass) = klass;
    RBASIC_SET_SHAPE_ID_NO_CHECKS(obj, shape_id);

    // Phase 3: GC-specific post-init
    rb_gc_impl_post_alloc_init(objspace, obj, flags, wb_protected);

    gc_validate_pc(obj);

    if (UNLIKELY(rb_gc_event_hook_required_p(RUBY_INTERNAL_EVENT_NEWOBJ))) {
        int lev = RB_GC_VM_LOCK_NO_BARRIER();
        {
            size_t slot_size = rb_gc_obj_slot_size(obj);
            memset((char *)obj + sizeof(struct RBasic), 0, slot_size - sizeof(struct RBasic));

            bool gc_disabled = RTEST(rb_gc_disable_no_rest());
            {
                rb_gc_event_hook(obj, RUBY_INTERNAL_EVENT_NEWOBJ);
            }
            if (!gc_disabled) rb_gc_enable();
        }
        RB_GC_VM_UNLOCK_NO_BARRIER(lev);
    }

#if RGENGC_CHECK_MODE
    memset(
        (void *)(obj + sizeof(struct RBasic)),
        GC_DEBUG_SLOT_FILL_SPECIAL_VALUE,
        rb_gc_obj_slot_size(obj) - sizeof(struct RBasic)
    );
#endif

    return obj;
}
```

### Step 5: Slim down default GC `rb_gc_impl_new_obj`

**File**: `gc/default/default.c`

Remove `klass` and `flags` params. Remove `newobj_init` calls from both fast
and slow paths. Remove `stress_to_class` check (moves to gc.c step 6).

Changes to `rb_gc_impl_new_obj` (line 2506):
- Remove `VALUE klass, VALUE flags` from signature
- Remove `stress_to_class` block (lines 2514-2518)
- Fast path (line 2526-2527): remove `newobj_init(klass, flags, ...)`, keep
  only `newobj_alloc`
- Slow path: call slimmed `newobj_slowpath` variants

Changes to `newobj_slowpath` (line 2456):
- Remove `VALUE klass, VALUE flags` from signature
- Remove `newobj_init` call (line 2481)
- Keep lock acquisition, `during_gc` check, stress GC, `newobj_alloc`

Changes to `newobj_slowpath_wb_protected` / `_wb_unprotected` (lines 2494-2503):
- Remove `klass` and `flags` forwarding

Delete `newobj_init` entirely — its generic part is in gc.c (step 4), its
GC-specific part is in `rb_gc_impl_post_alloc_init` (step 2).

### Step 6: Move `stress_to_class` to gc.c

**File**: `gc/gc_impl.h` — add declaration:
```c
GC_IMPL_FN bool rb_gc_impl_stress_to_class_p(void *objspace_ptr, VALUE klass);
```

**File**: `gc/default/default.c` — implement:
```c
bool
rb_gc_impl_stress_to_class_p(void *objspace_ptr, VALUE klass)
{
#if GC_DEBUG_STRESS_TO_CLASS
    rb_objspace_t *objspace = objspace_ptr;
    if (RB_UNLIKELY(stress_to_class)) {
        return rb_hash_lookup2(stress_to_class, klass, Qundef) != Qundef;
    }
#endif
    return false;
}
```

**File**: `gc/mmtk/mmtk.c` — implement as:
```c
bool
rb_gc_impl_stress_to_class_p(void *objspace_ptr, VALUE klass)
{
    return false;
}
```

**File**: `gc.c`, inside `newobj_of` — add before Phase 1:
```c
    if (RB_UNLIKELY(rb_gc_impl_stress_to_class_p(objspace, klass))) {
        rb_memerror();
    }
```

`stress_to_class` is a Hash stored in `objspace->stress_to_class`
(default GC line 648), set via `GC.add_stress_to_class(klass)`. It's separate
from `GC.stress` / `ruby_gc_stressful`. Only defined when
`GC_DEBUG_STRESS_TO_CLASS` is set (debug builds).

### Step 7: Slim down MMTk `rb_gc_impl_new_obj`

**File**: `gc/mmtk/mmtk.c`

Remove `VALUE klass, VALUE flags` from signature. Remove lines 833-834
(`alloc_obj[0] = flags; alloc_obj[1] = klass`). Remove line 840
(`mmtk_add_obj_free_candidate`) — moved to step 3. Keep `mmtk_post_alloc`
(allocation finalization).

---

## Step Ordering for Green Tree

1. **Steps 1-3**: Add `rb_gc_impl_post_alloc_init` (interface + both impls).
   At this point `newobj_init` still exists and is still called — tree stays
   green. The new function is declared but not yet called.

2. **Steps 4-5**: Restructure `newobj_of` AND slim down default GC's
   `rb_gc_impl_new_obj` simultaneously. These must be a single commit —
   `newobj_of` calls the new signature, and the GC provides it. Delete
   `newobj_init`.

3. **Step 6**: Move `stress_to_class`. Can be part of the step 4-5 commit or
   separate.

4. **Step 7**: Slim down MMTk. Can be same commit as steps 4-5 since the
   interface change affects both GCs simultaneously.

**Realistically steps 4-7 are one atomic commit** — the interface signature
change requires both callers and both implementations to change together.

## Suggested Commit Structure

**Commit 1** (preparatory): Add `rb_gc_impl_post_alloc_init` and
`rb_gc_impl_stress_to_class_p` to both GC implementations. The default GC
`post_alloc_init` duplicates the bitmap ops from `newobj_init`. MMTk version
duplicates the `obj_free_candidate` call. Both GCs still call `newobj_init`/set
flags in `new_obj` — behavior is duplicated but correct. All tests pass.

**Commit 2** (the split): Change `rb_gc_impl_new_obj` signature (remove klass,
flags). Update `newobj_of` to do generic init + call `post_alloc_init`. Remove
`newobj_init` from default GC. Remove flag/klass writes from MMTk. Remove
`mmtk_add_obj_free_candidate` from MMTk `new_obj`. Move `stress_to_class`
check to `newobj_of` using `rb_gc_impl_stress_to_class_p`.

This two-commit approach means commit 1 is a pure addition (safe to revert) and
commit 2 is the behavioral change.

## Test Strategy

**Existing coverage**: The allocation path is exercised by virtually every Ruby
test. Key test files:

- `test/ruby/test_gc.rb` — GC stress, object allocation
- `test/ruby/test_gc_compact.rb` — compaction (exercises object moves)
- `test/-ext-/tracepoint/test_tracepoint.rb` — NEWOBJ event hook
- `test/-ext-/bug-14834/test_bug14834.rb` — NEWOBJ tracepoint edge case
- `test/ruby/test_ractor.rb` — ractor moves (shell object allocation)
- `bootstraptest/test_ractor.rb` — more ractor tests

**Debug build verification**: Run the full test suite with `RGENGC_CHECK_MODE=1`
to exercise bitmap consistency assertions. The new
`GC_ASSERT(BUILTIN_TYPE(obj) != T_NONE)` in `post_alloc_init` catches the most
dangerous failure mode.

**No new tests needed** — this is a refactoring that preserves behavior. The
existing test suite with debug assertions enabled is the right verification.

## Files Changed

| File | Nature of Change |
|------|-----------------|
| `gc/gc_impl.h` | Change `rb_gc_impl_new_obj` signature, add `rb_gc_impl_post_alloc_init`, add `rb_gc_impl_stress_to_class_p` |
| `gc.c` | Restructure `newobj_of`, add `stress_to_class` check |
| `gc/default/default.c` | Slim `rb_gc_impl_new_obj`, delete `newobj_init`, add `rb_gc_impl_post_alloc_init`, slim `newobj_slowpath*` |
| `gc/mmtk/mmtk.c` | Slim `rb_gc_impl_new_obj`, add `rb_gc_impl_post_alloc_init` |

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Bitmap race on slow path | Low | Analyzed as safe; TSAN in CI catches races |
| `stress_to_class` relocation breaks stress tests | Low | Test with `GC.add_stress_to_class(SomeClass)` |
| MMTk `mmtk_post_alloc` ordering issue | Low | `mmtk_post_alloc` is about bump pointer, type-independent |
| Performance regression from extra function call | Low | `post_alloc_init` inlines in non-modular builds (`GC_IMPL_FN static`) |
| NEWOBJ hook sees different state | None | Hook fires at same point, after all init |
