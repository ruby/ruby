# Research: Splitting Object Allocation from Initialization

## Goal

Split `newobj_of` into two distinct phases:
1. **Allocation** — obtain raw memory from the heap page (returns a slot with no flags/klass)
2. **Initialization** — set flags, klass, shape_id, and all other RBasic fields

Currently these are mixed together: `newobj_alloc` returns raw memory, then
`newobj_init` sets flags+klass, but the caller (`newobj_of`) also sets shape_id
and fires event hooks. The flags/klass/shape setting is entangled across layers.

## Current Flow

```
NEWOBJ_OF_WITH_SHAPE (internal/gc.h:123)
  strips FL_WB_PROTECTED, selects wb_protected/wb_unprotected path
  ↓
rb_wb_protected_newobj_of / rb_wb_unprotected_newobj_of (gc.c:1049-1060)
  ↓
newobj_of (gc.c:1006)
  → rb_gc_impl_new_obj (gc/default/default.c:2506)
      fast path: newobj_alloc() → newobj_init(klass, flags, ...)
      slow path: lock → newobj_alloc() → newobj_init(klass, flags, ...)
  → RBASIC_SET_SHAPE_ID_NO_CHECKS(obj, shape_id)    ← gc.c:1009
  → NEWOBJ event hook (fires with flags+klass SET)   ← gc.c:1013-1031
  ↓
caller receives fully initialized object
```

### What `newobj_init` does (gc/default/default.c:2161-2224)

1. Asserts `BUILTIN_TYPE(obj) == T_NONE` (raw memory from freelist)
2. Sets `RBASIC(obj)->flags = flags` (type tag + FL_* bits, NOT FL_WB_PROTECTED)
3. Sets `RBASIC(obj)->klass = klass` (casts away const)
4. Sets `shape_id = 0` on 32-bit (overwritten by caller)
5. Marks T_CLASS/T_MODULE/T_ICLASS as age candidates
6. Marks wb_unprotected objects in per-page bitmap
7. Various debug/profiling bookkeeping

### What `newobj_of` does after `rb_gc_impl_new_obj` returns

1. Sets shape_id via `RBASIC_SET_SHAPE_ID_NO_CHECKS`
2. If NEWOBJ tracepoint registered: zeroes body, disables GC, fires hook
3. In RGENGC_CHECK_MODE: fills body with 0xFF debug pattern

---

## Problems With Deferring Flags/Klass

### 1. NEWOBJ Event Hook — fires inside `newobj_of` (CRITICAL)

**Location**: gc.c:1013-1031

The NEWOBJ tracepoint fires **inside** `newobj_of`, BEFORE the object is returned
to the caller. Callbacks receive the object via `rb_tracearg_object(tparg)` and
can:

- Store the VALUE (ext/objspace/object_tracing.c:98 — `st_lookup(arg->object_table, obj, &v)`)
- Read klass via `rb_tracearg_defined_class` (object_tracing.c:91)
- **Set instance variables** on the object (object.c:127-128 comment confirms this)

The comment at object.c:127-128 is explicit:
```c
// There might be a NEWOBJ tracepoint callback, and it may set fields.
// So the shape must be passed to `NEWOBJ_OF`.
```

**Impact**: If allocation returns an object without flags/klass, the NEWOBJ hook
fires on an uninitialized object. Callbacks that inspect klass or set fields will
crash or corrupt memory.

**Mitigation**: The hook must fire AFTER initialization. This is already the case
today, but it means the hook cannot move into the "allocation-only" phase.

### 2. FL_SET_RAW / FL_UNSET_RAW After Allocation (CRITICAL)

Many callers use `FL_SET_RAW`/`FL_UNSET_RAW` immediately after `NEWOBJ_OF` to set
additional flags. These macros do bitwise OR/AND on `RBASIC(obj)->flags`, which
means flags must already contain the type tag.

**Affected callers**:

| File:Line | Type | Operation |
|-----------|------|-----------|
| bignum.c:3078 | T_BIGNUM | `BIGNUM_SET_SIGN` → `FL_SET_RAW/FL_UNSET_RAW` |
| bignum.c:3086 | T_BIGNUM | `BIGNUM_SET_LEN` reads+modifies flags for embedded |
| symbol.c:316 | T_SYMBOL | `rb_enc_set_index` → `RB_ENCODING_SET_INLINED` → `FL_UNSET_RAW + FL_SET_RAW` |
| numeric.c:913 | T_FLOAT | `OBJ_FREEZE` → `FL_SET_RAW` |
| rational.c:423 | T_RATIONAL | `OBJ_FREEZE` → `FL_SET_RAW` |
| complex.c:396 | T_COMPLEX | `OBJ_FREEZE` → `FL_SET_RAW` |
| struct.c:832 | T_STRUCT | `FL_UNSET_RAW(st, RSTRUCT_GEN_FIELDS)` |

**Impact**: If flags are 0 (T_NONE), `FL_SET_RAW(obj, BIGNUM_SIGN_BIT)` produces
flags without the type tag → object appears as T_NONE with random bits set.

**Mitigation**: All these callers would need to be updated to set flags BEFORE
doing bitwise operations. Or, the initialization function sets flags before
returning to the caller.

### 3. Write Barrier Assertions (MODERATE)

**Location**: gc/default/default.c:6110-6116

```c
GC_ASSERT(RB_BUILTIN_TYPE(a) != T_NONE);
GC_ASSERT(RB_BUILTIN_TYPE(a) != T_MOVED);
GC_ASSERT(RB_BUILTIN_TYPE(a) != T_ZOMBIE);
```

Write barriers (`RB_OBJ_WRITE`, `RBASIC_SET_CLASS`) check that both the parent
and child are valid typed objects. If called on an object without flags set,
debug builds crash on these assertions.

**Affected paths**:
- `RBASIC_SET_CLASS(obj, klass)` (internal/object.h:57-62) — always triggers
  `RB_OBJ_WRITTEN`, which calls `rb_gc_writebarrier`
- `RB_OBJ_WRITE(obj, &field, val)` — used by `RCOMPLEX_SET_REAL`,
  `RATIONAL_SET_NUM`, etc.

**Impact**: If flags aren't set, any write-barrier-protected store to the object
triggers an assertion failure in debug builds. In release builds, the barrier
might skip the object (thinking it's T_NONE), breaking generational GC invariants.

**Mitigation**: If initialization sets flags before the caller does WB-protected
stores, this is fine. The issue only arises if there's a window where the caller
has the object but flags aren't set yet.

### 4. `rb_obj_class()` in Debug Assertions (LOW — debug only)

**Location**: object.c:140

```c
#if RUBY_DEBUG
if (rb_obj_class(obj) != rb_class_real(klass)) {
    rb_bug("Expected rb_class_allocate_instance to set the class correctly");
}
#endif
```

Reads `RBASIC_CLASS(obj)` immediately after allocation. Only in debug builds.

**Impact**: Debug assertion failure if klass not set.

**Mitigation**: Trivial — the assertion just needs to come after init.

### 5. `rb_shape_obj_has_fields()` in struct.c (MODERATE)

**Location**: struct.c:830

```c
if (!rb_shape_obj_has_fields((VALUE)st)
        && embedded_size < rb_gc_obj_slot_size((VALUE)st)) {
    FL_UNSET_RAW((VALUE)st, RSTRUCT_GEN_FIELDS);
```

`rb_shape_obj_has_fields` reads `RBASIC_SHAPE_ID(obj)` (shape.h:437). Shape_id
is set in `newobj_of` at gc.c:1009, AFTER `rb_gc_impl_new_obj` returns.

**Impact**: If shape_id isn't set, this reads stale/zero shape_id. Currently
`newobj_init` sets `shape_id = 0` (root shape), and `newobj_of` overwrites it.
The struct code runs after both, so it works today.

**Mitigation**: Shape_id must be set before the caller gets the object.

### 6. Ractor Move Path (LOW)

**Location**: ractor.c:2019

```c
NEWOBJ_OF(moved, struct RBasic, 0, type, slot_size, 0);
MEMZERO(&moved[1], char, slot_size - sizeof(*moved));
```

Allocates shell objects for ractor moves. Passes `klass=0`. The flags are later
overwritten completely at ractor.c:2031:

```c
RBASIC(data->replacement)->flags = (RBASIC(obj)->flags & ~ignored_flags) | ...;
```

**Impact**: Low. The initial allocation is a placeholder. Flags are overwritten.

**Mitigation**: This pattern actually WANTS the split — allocate then fully
overwrite.

### 7. `rb_data_object_zalloc` → `xcalloc` → possible GC (MODERATE)

**Location**: gc.c:1099-1103

```c
VALUE obj = rb_data_object_wrap(klass, 0, dmark, dfree);
DATA_PTR(obj) = xcalloc(1, size);  // can trigger GC!
```

After allocation, `xcalloc` can call `objspace_malloc_increase` which may trigger
GC (gc/default/default.c:8130). At this point flags/klass ARE set, but the
object's data pointer is still NULL and `dmark`/`dfree` haven't been called.

**Impact**: This is an existing issue unrelated to our refactoring, but it
constrains the design — GC must be able to see the object as valid (with
correct type tag) at any point after allocation returns to the caller.

**Mitigation**: Flags must be set before returning to any caller that might
trigger GC.

### 8. MMTk GC Implementation (MODERATE)

**Location**: gc/mmtk/mmtk.c:833-834

```c
alloc_obj[0] = flags;   // sets flags directly on raw memory
alloc_obj[1] = klass;
```

MMTk doesn't use `newobj_init` — it writes flags/klass directly. Then calls
`mmtk_post_alloc` and `mmtk_add_obj_free_candidate`.

**Impact**: Both GC implementations need to agree on the contract. If default GC
splits alloc from init, MMTk must follow the same split.

**Mitigation**: The `rb_gc_impl_new_obj` interface needs to change for both
implementations simultaneously.

### 9. `newobj_init` GC-Bitmap Operations (MODERATE)

**Location**: gc/default/default.c:2171-2197

```c
int t = flags & RUBY_T_MASK;
if (t == T_CLASS || t == T_MODULE || t == T_ICLASS) {
    RVALUE_AGE_SET_CANDIDATE(objspace, obj);
}
...
if (RB_UNLIKELY(wb_protected == FALSE)) {
    MARK_IN_BITMAP(GET_HEAP_WB_UNPROTECTED_BITS(obj), obj);
}
```

These bitmap operations happen inside `newobj_init`, which currently lives inside
the GC implementation. If initialization moves out of the GC, these
GC-implementation-specific operations need a new home.

**Impact**: The age candidate and wb_unprotected bitmap settings are
GC-implementation details that can't live in generic initialization code.

**Mitigation**: Either keep a "GC-side init" step, or expose these as a
post-allocation hook.

---

## YJIT / ZJIT Impact

**YJIT**: Does NOT inline object allocation. Calls `rb_obj_alloc` →
`rb_class_allocate_instance` → `newobj_of` → standard path. Treats returned
object as opaque `Type::UnknownHeap`. **No changes needed in YJIT.**

**ZJIT**: No allocation inlining found. Uses standard C paths.

---

## Summary of Risk by Severity

| Severity | Issue | Key Constraint |
|----------|-------|----------------|
| CRITICAL | NEWOBJ event hook | Must fire with flags+klass+shape set |
| CRITICAL | FL_SET_RAW after alloc | 7+ callers do bitwise ops on flags immediately |
| MODERATE | Write barrier assertions | WB checks BUILTIN_TYPE != T_NONE |
| MODERATE | GC bitmap ops in newobj_init | Age candidate + WB-unprotect are GC-specific |
| MODERATE | MMTk parity | Both GCs must agree on new interface |
| MODERATE | xcalloc-triggered GC | Object must look valid when GC can see it |
| LOW | Debug assertions reading klass | object.c:140 |
| LOW | Ractor move | Already uses alloc-then-overwrite pattern |

## Recommended Approach

The split is feasible but the boundary should be drawn carefully:

1. **`rb_gc_impl_new_obj` returns raw memory** (T_NONE, no flags/klass)
2. **New `newobj_init_basic(obj, klass, flags, shape_id, wb_protected)`** in gc.c
   sets RBasic fields + calls a GC-specific hook for bitmap ops
3. **`newobj_of` calls both** — alloc then init — and fires NEWOBJ hook after init
4. **Callers of NEWOBJ_OF unchanged** — they still get fully initialized objects
5. The value is in making the GC interface cleaner: `rb_gc_impl_new_obj` becomes
   a pure allocator, the initialization logic lives in gc.c

The 7+ callers that do `FL_SET_RAW` after allocation don't need changes because
they run after `NEWOBJ_OF` returns, at which point init has already happened.

The real constraint is that `newobj_init` currently lives inside
`gc/default/default.c` (the GC implementation) but does both generic work
(set flags/klass) and GC-specific work (bitmap ops, age tracking). The split
should extract the generic part into gc.c while keeping GC-specific ops behind
the `rb_gc_impl_*` interface.
