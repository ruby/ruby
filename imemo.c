
#include "constant.h"
#include "id_table.h"
#include "internal.h"
#include "internal/imemo.h"
#include "internal/object.h"
#include "internal/st.h"
#include "vm_callinfo.h"

size_t rb_iseq_memsize(const rb_iseq_t *iseq);
void rb_iseq_mark_and_move(rb_iseq_t *iseq, bool reference_updating);
void rb_iseq_free(const rb_iseq_t *iseq);

const char *
rb_imemo_name(enum imemo_type type)
{
    // put no default case to get a warning if an imemo type is missing
    switch (type) {
#define IMEMO_NAME(x) case imemo_##x: return #x;
        IMEMO_NAME(callcache);
        IMEMO_NAME(callinfo);
        IMEMO_NAME(constcache);
        IMEMO_NAME(cref);
        IMEMO_NAME(env);
        IMEMO_NAME(ifunc);
        IMEMO_NAME(iseq);
        IMEMO_NAME(memo);
        IMEMO_NAME(ment);
        IMEMO_NAME(svar);
        IMEMO_NAME(throw_data);
        IMEMO_NAME(tmpbuf);
        IMEMO_NAME(cvar_entry);
        IMEMO_NAME(fields);
        IMEMO_NAME(subclasses);
        IMEMO_NAME(cdhash);
#undef IMEMO_NAME
    }
    rb_bug("unreachable");
}

/* =========================================================================
 * allocation
 * ========================================================================= */

VALUE
rb_imemo_new(enum imemo_type type, VALUE v0, size_t size, bool is_shareable)
{
    VALUE flags = T_IMEMO | (type << FL_USHIFT) | (is_shareable ? FL_SHAREABLE : 0);
    return rb_newobj_of(v0, flags, size);
}

VALUE
rb_imemo_tmpbuf_new(void)
{
    VALUE flags = T_IMEMO | (imemo_tmpbuf << FL_USHIFT);
    UNPROTECTED_NEWOBJ_OF(obj, rb_imemo_tmpbuf_t, 0, flags, sizeof(rb_imemo_tmpbuf_t));

    rb_gc_register_pinning_obj((VALUE)obj);

    obj->marked = false;
    obj->ptr = NULL;
    obj->size = 0;

    return (VALUE)obj;
}

void *
rb_alloc_tmp_buffer(volatile VALUE *store, long len, bool marked)
{
    if (len < 0) {
        rb_raise(rb_eArgError, "negative buffer size (or size too big)");
    }

    /* Keep the order; allocate an empty imemo first then xmalloc, to
     * get rid of potential memory leak */
    rb_imemo_tmpbuf_t *tmpbuf = (rb_imemo_tmpbuf_t *)rb_imemo_tmpbuf_new();
    *store = (VALUE)tmpbuf;
    void *ptr = ruby_xmalloc(len);
    tmpbuf->marked = marked;
    tmpbuf->ptr = ptr;
    tmpbuf->size = len;

    return ptr;
}

void
rb_free_tmp_buffer(volatile VALUE *store)
{
    if (!*store) return;
    rb_imemo_tmpbuf_t *s = (rb_imemo_tmpbuf_t*)ATOMIC_VALUE_EXCHANGE(*store, 0);
    if (s) {
        void *ptr = ATOMIC_PTR_EXCHANGE(s->ptr, 0);
        long size = s->size;
        s->size = 0;
        ruby_xfree_sized(ptr, size);
    }
}

struct MEMO *
rb_imemo_memo_new(VALUE a, VALUE b, long c)
{
    struct MEMO *memo = IMEMO_NEW(struct MEMO, imemo_memo, 0);

    *((VALUE *)&memo->v1) = a;
    *((VALUE *)&memo->v2) = b;
    memo->u3.cnt = c;

    return memo;
}

struct MEMO *
rb_imemo_memo_new_value(VALUE a, VALUE b, VALUE c)
{
    struct MEMO *memo = IMEMO_NEW(struct MEMO, imemo_memo, 0);

    *((VALUE *)&memo->v1) = a;
    *((VALUE *)&memo->v2) = b;
    *((VALUE *)&memo->u3.value) = c;
    memo->flags |= MEMO_U3_IS_VALUE;

    return memo;
}

VALUE
rb_imemo_cdhash_new(size_t size, const struct st_hash_type *type)
{
    struct rb_imemo_cdhash *memo = IMEMO_NEW(struct rb_imemo_cdhash, imemo_cdhash, 0);
    memo->tbl.num_entries = 0;
    st_init_existing_table_with_size(&memo->tbl, type, size);
    return (VALUE)memo;
}

VALUE
rb_imemo_fields_new(VALUE owner, shape_id_t shape_id, bool shareable)
{
    size_t capa = RSHAPE_CAPACITY(shape_id);
    size_t embedded_size = offsetof(struct rb_fields, as.embed) + capa * sizeof(VALUE);
    RUBY_ASSERT(rb_gc_size_allocatable_p(embedded_size));
    VALUE fields = rb_imemo_new(imemo_fields, owner, embedded_size, shareable);
    // imemo fields objects should always have "RObject" layout.  The
    // layout in the shape describes the layout of the thing on which it is set.
    // Imemo fields have the same layout as robject, therefore the layout
    // should reflect that fact.
    RBASIC_SET_SHAPE_ID(fields, rb_shape_id_with_robject_layout(rb_shape_transition_embedded(shape_id)));
    RUBY_ASSERT(IMEMO_TYPE_P(fields, imemo_fields));
    return fields;
}

VALUE
rb_imemo_fields_new_complex(VALUE owner, shape_id_t shape_id, size_t capa, bool shareable)
{
    VALUE fields = rb_imemo_new(imemo_fields, owner, sizeof(struct rb_fields), shareable);
    IMEMO_OBJ_FIELDS(fields)->as.complex.table = st_init_numtable_with_size(capa);
    // imemo fields objects should always have "RObject" layout.  The
    // layout in the shape describes the layout of the thing on which it is set.
    // Imemo fields have the same layout as robject, therefore the layout
    // should reflect that fact.
    RBASIC_SET_SHAPE_ID(fields, rb_shape_id_with_robject_layout(rb_shape_transition_heap(shape_id)));
    return fields;
}

static int
imemo_fields_trigger_wb_i(st_data_t key, st_data_t value, st_data_t arg)
{
    VALUE field_obj = (VALUE)arg;
    RB_OBJ_WRITTEN(field_obj, Qundef, (VALUE)value);
    return ST_CONTINUE;
}

static int
imemo_fields_complex_wb_i(st_data_t key, st_data_t value, st_data_t arg)
{
    RB_OBJ_WRITTEN((VALUE)arg, Qundef, (VALUE)value);
    return ST_CONTINUE;
}

VALUE
rb_imemo_fields_new_complex_tbl(VALUE owner, shape_id_t shape_id, st_table *tbl, bool shareable)
{
    VALUE fields = rb_imemo_new(imemo_fields, owner, sizeof(struct rb_fields), shareable);
    IMEMO_OBJ_FIELDS(fields)->as.complex.table = tbl;
    // imemo fields objects should always have "RObject" layout.  The
    // layout in the shape describes the layout of the thing on which it is set.
    // Imemo fields have the same layout as robject, therefore the layout
    // should reflect that fact.
    RBASIC_SET_SHAPE_ID(fields, rb_shape_id_with_robject_layout(rb_shape_transition_heap(shape_id)));
    st_foreach(tbl, imemo_fields_trigger_wb_i, (st_data_t)fields);
    return fields;
}

VALUE
rb_imemo_fields_clone(VALUE fields_obj)
{
    shape_id_t shape_id = RBASIC_SHAPE_ID(fields_obj);
    VALUE clone;

    if (rb_shape_complex_p(shape_id)) {
        st_table *src_table = rb_imemo_fields_complex_tbl(fields_obj);

        st_table *dest_table = xcalloc(1, sizeof(st_table));
        clone = rb_imemo_fields_new_complex_tbl(rb_imemo_fields_owner(fields_obj), shape_id, dest_table, false /* TODO: check */);

        st_replace(dest_table, src_table);

        st_foreach(dest_table, imemo_fields_complex_wb_i, (st_data_t)clone);
    }
    else {
        clone = rb_imemo_fields_new(rb_imemo_fields_owner(fields_obj), shape_id, false /* TODO: check */);
        VALUE *fields = rb_imemo_fields_ptr(clone);
        attr_index_t fields_count = RSHAPE_LEN(shape_id);
        MEMCPY(fields, rb_imemo_fields_ptr(fields_obj), VALUE, fields_count);
        for (attr_index_t i = 0; i < fields_count; i++) {
            RB_OBJ_WRITTEN(clone, Qundef, fields[i]);
        }
    }

    return clone;
}

void
rb_imemo_fields_clear(VALUE fields_obj)
{
    // When replacing an imemo/fields by another one, we must clear
    // its shape so that gc.c:obj_free_object_id won't be called.
    if (rb_obj_shape_complex_p(fields_obj)) {
        RBASIC_SET_SHAPE_ID(fields_obj, ROOT_COMPLEX_SHAPE_ID);
    }
    else {
        RBASIC_SET_SHAPE_ID(fields_obj, ROOT_SHAPE_ID);
    }
    // Invalidate the ec->gen_fields_cache.
    RBASIC_CLEAR_CLASS(fields_obj);
}

VALUE
rb_imemo_subclasses_new(uint32_t capacity)
{
    size_t embed_size = offsetof(struct rb_subclasses, as) + capacity * sizeof(VALUE);
    struct rb_subclasses *subs;

    if (rb_gc_size_allocatable_p(embed_size)) {
        subs = (struct rb_subclasses *)rb_imemo_new(imemo_subclasses, 0, embed_size, true);
        subs->count = 0;
        subs->capacity = capacity;
        memset(subs->as.embed, 0, capacity * sizeof(VALUE));
        rb_gc_declare_weak_references((VALUE)subs);
    }
    else {
        subs = (struct rb_subclasses *)rb_imemo_new(imemo_subclasses, 0, sizeof(struct rb_subclasses), true);
        subs->as.external = NULL;
        subs->count = 0;
        subs->capacity = 0;
        FL_SET_RAW((VALUE)subs, IMEMO_SUBCLASSES_HEAP);
        rb_gc_declare_weak_references((VALUE)subs);
        subs->as.external = ZALLOC_N(VALUE, capacity);
        subs->capacity = capacity;
    }
    return (VALUE)subs;
}

/* =========================================================================
 * memsize
 * ========================================================================= */

size_t
rb_imemo_memsize(VALUE obj)
{
    size_t size = 0;
    switch (imemo_type(obj)) {
      case imemo_callcache:
        break;
      case imemo_callinfo:
        break;
      case imemo_constcache:
        break;
      case imemo_cref:
        break;
      case imemo_env:
        size += ((rb_env_t *)obj)->env_size * sizeof(VALUE);

        break;
      case imemo_ifunc:
        break;
      case imemo_iseq:
        size += rb_iseq_memsize((rb_iseq_t *)obj);

        break;
      case imemo_memo:
        break;
      case imemo_ment:
        size += sizeof(((rb_method_entry_t *)obj)->def);

        break;
      case imemo_svar:
        break;
      case imemo_throw_data:
        break;
      case imemo_tmpbuf:
        size += ((rb_imemo_tmpbuf_t *)obj)->size;

        break;
      case imemo_cvar_entry:
        break;
      case imemo_fields:
        if (rb_obj_shape_complex_p(obj)) {
            size += st_memsize(IMEMO_OBJ_FIELDS(obj)->as.complex.table);
        }

        break;
      case imemo_subclasses: {
        if (FL_TEST_RAW(obj, IMEMO_SUBCLASSES_HEAP)) {
            struct rb_subclasses *subs = (struct rb_subclasses *)obj;
            size += subs->capacity * sizeof(VALUE);
        }

        break;
      }
      case imemo_cdhash:
        size += st_memsize(rb_imemo_cdhash_tbl(obj)) - sizeof(st_table);

        break;
      default:
        rb_bug("unreachable");
    }

    return size;
}

/* =========================================================================
 * mark
 * ========================================================================= */

static void
mark_and_move_method_entry(rb_method_entry_t *ment, bool reference_updating)
{
    rb_method_definition_t *def = ment->def;

    rb_gc_mark_and_move(&ment->owner);
    rb_gc_mark_and_move(&ment->defined_class);

    if (def) {
        switch (def->type) {
          case VM_METHOD_TYPE_ISEQ:
            if (def->body.iseq.iseqptr) {
                rb_gc_mark_and_move_ptr(&def->body.iseq.iseqptr);
            }
            rb_gc_mark_and_move_ptr(&def->body.iseq.cref);

            if (!reference_updating) {
                if (def->iseq_overload && ment->defined_class) {
                    // it can be a key of "overloaded_cme" table
                    // so it should be pinned.
                    rb_gc_mark((VALUE)ment);
                }
            }
            break;
          case VM_METHOD_TYPE_ATTRSET:
          case VM_METHOD_TYPE_IVAR:
            rb_gc_mark_and_move(&def->body.attr.location);
            break;
          case VM_METHOD_TYPE_BMETHOD:
            if (!rb_gc_checking_shareable()) {
                rb_gc_mark_and_move(&def->body.bmethod.proc);
            }
            break;
          case VM_METHOD_TYPE_ALIAS:
            rb_gc_mark_and_move_ptr(&def->body.alias.original_me);
            return;
          case VM_METHOD_TYPE_REFINED:
            rb_gc_mark_and_move_ptr(&def->body.refined.orig_me);
            break;
          case VM_METHOD_TYPE_CFUNC:
          case VM_METHOD_TYPE_ZSUPER:
          case VM_METHOD_TYPE_MISSING:
          case VM_METHOD_TYPE_OPTIMIZED:
          case VM_METHOD_TYPE_UNDEF:
          case VM_METHOD_TYPE_NOTIMPLEMENTED:
            break;
        }
    }
}

void
rb_imemo_mark_and_move(VALUE obj, bool reference_updating)
{
    switch (imemo_type(obj)) {
      case imemo_callcache: {
        /* cc is callcache.
         *
         * cc->klass (klass) should not be marked because if the klass is
         * free'ed, the cc->klass will be cleared by `vm_cc_invalidate()`.
         *
         * For "normal" CCs cc->cme (cme) should not be marked because the cc is
         *   invalidated through the klass when the cme is free'd.
         * - klass marks cme if klass uses cme.
         * - caller class's ccs->cme marks cc->cme.
         * - if cc is invalidated (klass doesn't refer the cc), cc is
         *   invalidated by `vm_cc_invalidate()` after which cc->cme must not
         *   be accessed.
         * - With multi-Ractors, cme will be collected with global GC
         *   so that it is safe if GC is not interleaving while accessing
         *   cc and cme.
         *
         * However cc_type_super and cc_type_refinement are not chained
         *   from ccs so cc->cme should be marked as long as the cc is valid;
         *   the cme might be reachable only through cc in these cases.
         */
        struct rb_callcache *cc = (struct rb_callcache *)obj;
        if (UNDEF_P(cc->klass)) {
            /* If it's invalidated, we must not mark anything.
             * All fields should are considered invalid
             */
        }
        else if (reference_updating) {
            *((VALUE *)&cc->klass) = rb_gc_location(cc->klass);
            *((struct rb_callable_method_entry_struct **)&cc->cme_) =
                (struct rb_callable_method_entry_struct *)rb_gc_location((VALUE)cc->cme_);

            RUBY_ASSERT(RB_TYPE_P(cc->klass, T_CLASS) || RB_TYPE_P(cc->klass, T_ICLASS));
            RUBY_ASSERT(IMEMO_TYPE_P((VALUE)cc->cme_, imemo_ment));
        }
        else {
            RUBY_ASSERT(RB_TYPE_P(cc->klass, T_CLASS) || RB_TYPE_P(cc->klass, T_ICLASS));
            RUBY_ASSERT(IMEMO_TYPE_P((VALUE)cc->cme_, imemo_ment));

            if ((vm_cc_super_p(cc) || vm_cc_refinement_p(cc))) {
                rb_gc_mark_movable((VALUE)cc->cme_);
            }
        }

        break;
      }
      case imemo_callinfo:
        break;
      case imemo_constcache: {
        struct iseq_inline_constant_cache_entry *ice = (struct iseq_inline_constant_cache_entry *)obj;

        if ((ice->flags & IMEMO_CONST_CACHE_SHAREABLE) ||
            !rb_gc_checking_shareable()) {
            rb_gc_mark_and_move(&ice->value);
        }

        break;
      }
      case imemo_cref: {
        rb_cref_t *cref = (rb_cref_t *)obj;

        if (!rb_gc_checking_shareable()) {
            // cref->klass_or_self can be unshareable, but no way to access it from other ractors
            rb_gc_mark_and_move(&cref->klass_or_self);
        }

        rb_gc_mark_and_move_ptr(&cref->next);

        // TODO: Ractor and refeinements are not resolved yet
        if (!rb_gc_checking_shareable()) {
            rb_gc_mark_and_move(&cref->refinements);
        }

        break;
      }
      case imemo_env: {
        rb_env_t *env = (rb_env_t *)obj;

        if (LIKELY(env->ep)) {
            // just after newobj() can be NULL here.
            RUBY_ASSERT(rb_gc_location(env->ep[VM_ENV_DATA_INDEX_ENV]) == rb_gc_location(obj));
            RUBY_ASSERT(reference_updating || VM_ENV_ESCAPED_P(env->ep));

            for (unsigned int i = 0; i < env->env_size; i++) {
                rb_gc_mark_and_move((VALUE *)&env->env[i]);
            }

            rb_gc_mark_and_move_ptr(&env->iseq);

            if (VM_ENV_LOCAL_P(env->ep) && VM_ENV_BOXED_P(env->ep)) {
                const rb_box_t *box = VM_ENV_BOX(env->ep);
                if (BOX_USER_P(box)) {
                    rb_gc_mark_and_move((VALUE *)&box->box_object);
                }
            }

            if (reference_updating) {
                ((VALUE *)env->ep)[VM_ENV_DATA_INDEX_ENV] = rb_gc_location(env->ep[VM_ENV_DATA_INDEX_ENV]);
            }
            else {
                if (!VM_ENV_FLAGS(env->ep, VM_ENV_FLAG_WB_REQUIRED)) {
                    VM_ENV_FLAGS_SET(env->ep, VM_ENV_FLAG_WB_REQUIRED);
                }
                rb_gc_mark_movable( (VALUE)rb_vm_env_prev_env(env));
            }
        }

        break;
      }
      case imemo_ifunc: {
        struct vm_ifunc *ifunc = (struct vm_ifunc *)obj;

        if (!reference_updating) {
            rb_gc_mark_maybe((VALUE)ifunc->data);
        }

        break;
      }
      case imemo_iseq:
        rb_iseq_mark_and_move((rb_iseq_t *)obj, reference_updating);
        break;
      case imemo_memo: {
        struct MEMO *memo = (struct MEMO *)obj;

        rb_gc_mark_and_move((VALUE *)&memo->v1);
        rb_gc_mark_and_move((VALUE *)&memo->v2);
        if (FL_TEST_RAW(obj, MEMO_U3_IS_VALUE)) {
            rb_gc_mark_and_move((VALUE *)&memo->u3.value);
        }

        break;
      }
      case imemo_ment:
        mark_and_move_method_entry((rb_method_entry_t *)obj, reference_updating);
        break;
      case imemo_svar: {
        struct vm_svar *svar = (struct vm_svar *)obj;

        rb_gc_mark_and_move((VALUE *)&svar->cref_or_me);
        rb_gc_mark_and_move((VALUE *)&svar->lastline);
        rb_gc_mark_and_move((VALUE *)&svar->backref);
        rb_gc_mark_and_move((VALUE *)&svar->others);

        break;
      }
      case imemo_throw_data: {
        struct vm_throw_data *throw_data = (struct vm_throw_data *)obj;

        rb_gc_mark_and_move((VALUE *)&throw_data->throw_obj);

        break;
      }
      case imemo_tmpbuf: {
        const rb_imemo_tmpbuf_t *m = (const rb_imemo_tmpbuf_t *)obj;

        if (m->marked && !reference_updating) {
            rb_gc_mark_locations(m->ptr, m->ptr + (m->size / sizeof(VALUE)));
        }

        break;
      }
      case imemo_cvar_entry: {
          struct rb_cvar_class_tbl_entry *ent = (struct rb_cvar_class_tbl_entry *)obj;
          rb_gc_mark_and_move(&ent->class_value);
          rb_gc_mark_and_move((VALUE *)&ent->cref);
          break;
      }
      case imemo_subclasses: {
        if (reference_updating) {
            struct rb_subclasses *subs = (struct rb_subclasses *)obj;
            VALUE *entries = rb_imemo_subclasses_entries(obj);
            for (uint32_t i = 0; i < subs->count; i++) {
                if (entries[i]) {
                    entries[i] = rb_gc_location(entries[i]);
                }
            }
        }
        break;
      }
      case imemo_fields: {
        rb_gc_mark_and_move((VALUE *)&RBASIC(obj)->klass);

        if (!rb_gc_checking_shareable()) {
            // imemo_fields can refer unshareable objects
            // even if the imemo_fields is shareable.

            if (rb_obj_shape_complex_p(obj)) {
                st_table *tbl = rb_imemo_fields_complex_tbl(obj);
                if (reference_updating) {
                    rb_gc_ref_update_table_values_only(tbl);
                }
                else {
                    rb_mark_tbl_no_pin(tbl);
                }
            }
            else {
                VALUE *fields = rb_imemo_fields_ptr(obj);
                attr_index_t len = RSHAPE_LEN(RBASIC_SHAPE_ID(obj));
                for (attr_index_t i = 0; i < len; i++) {
                    rb_gc_mark_and_move(&fields[i]);
                }
            }
        }
        break;
      }
      case imemo_cdhash: {
        st_table *tbl = rb_imemo_cdhash_tbl(obj);
        if (reference_updating) {
            rb_gc_update_set_refs(tbl);
        }
        else {
            rb_gc_mark_set_no_pin(tbl);
        }
        break;
      }
      default:
        rb_bug("unreachable");
    }
}

/* =========================================================================
 * free
 * ========================================================================= */

static enum rb_id_table_iterator_result
free_const_entry_i(VALUE value, void *data)
{
    rb_const_entry_t *ce = (rb_const_entry_t *)value;
    SIZED_FREE(ce);
    return ID_TABLE_CONTINUE;
}

void
rb_free_const_table(struct rb_id_table *tbl)
{
    rb_id_table_foreach_values(tbl, free_const_entry_i, 0);
    rb_id_table_free(tbl);
}

static inline void
imemo_fields_free(struct rb_fields *fields)
{
    if (rb_obj_shape_heap_p((VALUE)fields)) {
        RUBY_ASSERT(rb_shape_complex_p(RBASIC_SHAPE_ID((VALUE)fields)));
        st_free_table(fields->as.complex.table);
    }
}

void
rb_imemo_free(VALUE obj)
{
    switch (imemo_type(obj)) {
      case imemo_callcache:
        RB_DEBUG_COUNTER_INC(obj_imemo_callcache);

        break;
      case imemo_callinfo:{
        const struct rb_callinfo *ci = ((const struct rb_callinfo *)obj);

        if (ci->kwarg) {
            if (RUBY_ATOMIC_FETCH_SUB(((struct rb_callinfo_kwarg *)ci->kwarg)->references, 1) == 1) {
                ruby_xfree_sized((void *)ci->kwarg, rb_callinfo_kwarg_bytes(ci->kwarg->keyword_len));
            }
        }
        RB_DEBUG_COUNTER_INC(obj_imemo_callinfo);

        break;
      }
      case imemo_constcache:
        RB_DEBUG_COUNTER_INC(obj_imemo_constcache);

        break;
      case imemo_cref:
        RB_DEBUG_COUNTER_INC(obj_imemo_cref);

        break;
      case imemo_env: {
        rb_env_t *env = (rb_env_t *)obj;

        RUBY_ASSERT(VM_ENV_ESCAPED_P(env->ep));
        SIZED_FREE_N(env->env, env->env_size);
        RB_DEBUG_COUNTER_INC(obj_imemo_env);

        break;
      }
      case imemo_ifunc:
        RB_DEBUG_COUNTER_INC(obj_imemo_ifunc);
        break;
      case imemo_iseq:
        rb_iseq_free((rb_iseq_t *)obj);
        RB_DEBUG_COUNTER_INC(obj_imemo_iseq);

        break;
      case imemo_memo:
        RB_DEBUG_COUNTER_INC(obj_imemo_memo);

        break;
      case imemo_ment:
        rb_free_method_entry((rb_method_entry_t *)obj);
        RB_DEBUG_COUNTER_INC(obj_imemo_ment);

        break;
      case imemo_svar:
        RB_DEBUG_COUNTER_INC(obj_imemo_svar);

        break;
      case imemo_throw_data:
        RB_DEBUG_COUNTER_INC(obj_imemo_throw_data);

        break;
      case imemo_tmpbuf:
        ruby_xfree_sized(((rb_imemo_tmpbuf_t *)obj)->ptr, ((rb_imemo_tmpbuf_t *)obj)->size);
        RB_DEBUG_COUNTER_INC(obj_imemo_tmpbuf);

        break;
      case imemo_cvar_entry:
        RB_DEBUG_COUNTER_INC(obj_imemo_cvar_entry);

        break;
      case imemo_fields:
        imemo_fields_free(IMEMO_OBJ_FIELDS(obj));
        RB_DEBUG_COUNTER_INC(obj_imemo_fields);

        break;
      case imemo_subclasses: {
        if (FL_TEST_RAW(obj, IMEMO_SUBCLASSES_HEAP)) {
            struct rb_subclasses *subs = (struct rb_subclasses *)obj;
            SIZED_FREE_N(subs->as.external, subs->capacity);
        }
        RB_DEBUG_COUNTER_INC(obj_imemo_subclasses);
        break;
      }
      case imemo_cdhash:
        st_free_embedded_table(rb_imemo_cdhash_tbl(obj));
        RB_DEBUG_COUNTER_INC(obj_imemo_cdhash);

        break;
      default:
        rb_bug("unreachable");
    }
}
