
#include "constant.h"
#include "id_table.h"
#include "internal.h"
#include "internal/imemo.h"
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
        IMEMO_NAME(ast);
        IMEMO_NAME(callcache);
        IMEMO_NAME(callinfo);
        IMEMO_NAME(constcache);
        IMEMO_NAME(cref);
        IMEMO_NAME(env);
        IMEMO_NAME(ifunc);
        IMEMO_NAME(iseq);
        IMEMO_NAME(memo);
        IMEMO_NAME(ment);
        IMEMO_NAME(parser_strterm);
        IMEMO_NAME(svar);
        IMEMO_NAME(throw_data);
        IMEMO_NAME(tmpbuf);
        IMEMO_NAME(fields);
#undef IMEMO_NAME
    }
    rb_bug("unreachable");
}

/* =========================================================================
 * allocation
 * ========================================================================= */

VALUE
rb_imemo_new(enum imemo_type type, VALUE v0, size_t size)
{
    VALUE flags = T_IMEMO | FL_WB_PROTECTED | (type << FL_USHIFT);
    NEWOBJ_OF(obj, void, v0, flags, size, 0);

    return (VALUE)obj;
}

static rb_imemo_tmpbuf_t *
rb_imemo_tmpbuf_new(void)
{
    size_t size = sizeof(struct rb_imemo_tmpbuf_struct);
    VALUE flags = T_IMEMO | (imemo_tmpbuf << FL_USHIFT);
    NEWOBJ_OF(obj, struct rb_imemo_tmpbuf_struct, 0, flags, size, 0);

    return obj;
}

void *
rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t size, size_t cnt)
{
    void *ptr;
    rb_imemo_tmpbuf_t *tmpbuf;

    /* Keep the order; allocate an empty imemo first then xmalloc, to
     * get rid of potential memory leak */
    tmpbuf = rb_imemo_tmpbuf_new();
    *store = (VALUE)tmpbuf;
    ptr = ruby_xmalloc(size);
    tmpbuf->ptr = ptr;
    tmpbuf->cnt = cnt;

    return ptr;
}

void *
rb_alloc_tmp_buffer(volatile VALUE *store, long len)
{
    long cnt;

    if (len < 0 || (cnt = (long)roomof(len, sizeof(VALUE))) < 0) {
        rb_raise(rb_eArgError, "negative buffer size (or size too big)");
    }

    return rb_alloc_tmp_buffer_with_count(store, len, cnt);
}

void
rb_free_tmp_buffer(volatile VALUE *store)
{
    rb_imemo_tmpbuf_t *s = (rb_imemo_tmpbuf_t*)ATOMIC_VALUE_EXCHANGE(*store, 0);
    if (s) {
        void *ptr = ATOMIC_PTR_EXCHANGE(s->ptr, 0);
        s->cnt = 0;
        ruby_xfree(ptr);
    }
}

rb_imemo_tmpbuf_t *
rb_imemo_tmpbuf_parser_heap(void *buf, rb_imemo_tmpbuf_t *old_heap, size_t cnt)
{
    rb_imemo_tmpbuf_t *tmpbuf = rb_imemo_tmpbuf_new();
    tmpbuf->ptr = buf;
    tmpbuf->next = old_heap;
    tmpbuf->cnt = cnt;

    return tmpbuf;
}

static VALUE
imemo_fields_new(VALUE klass, size_t capa)
{
    size_t embedded_size = offsetof(struct rb_fields, as.embed) + capa * sizeof(VALUE);
    if (rb_gc_size_allocatable_p(embedded_size)) {
        VALUE fields = rb_imemo_new(imemo_fields, klass, embedded_size);
        RUBY_ASSERT(IMEMO_TYPE_P(fields, imemo_fields));
        return fields;
    }
    else {
        VALUE fields = rb_imemo_new(imemo_fields, klass, sizeof(struct rb_fields));
        FL_SET_RAW(fields, OBJ_FIELD_EXTERNAL);
        IMEMO_OBJ_FIELDS(fields)->as.external.ptr = ALLOC_N(VALUE, capa);
        return fields;
    }
}

VALUE
rb_imemo_fields_new(VALUE klass, size_t capa)
{
    return imemo_fields_new(klass, capa);
}

static VALUE
imemo_fields_new_complex(VALUE klass, size_t capa)
{
    VALUE fields = imemo_fields_new(klass, sizeof(struct rb_fields));
    IMEMO_OBJ_FIELDS(fields)->as.complex.table = st_init_numtable_with_size(capa);
    return fields;
}

VALUE
rb_imemo_fields_new_complex(VALUE klass, size_t capa)
{
    return imemo_fields_new_complex(klass, capa);
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
rb_imemo_fields_new_complex_tbl(VALUE klass, st_table *tbl)
{
    VALUE fields = imemo_fields_new(klass, sizeof(struct rb_fields));
    IMEMO_OBJ_FIELDS(fields)->as.complex.table = tbl;
    st_foreach(tbl, imemo_fields_trigger_wb_i, (st_data_t)fields);
    return fields;
}

VALUE
rb_imemo_fields_clone(VALUE fields_obj)
{
    shape_id_t shape_id = RBASIC_SHAPE_ID(fields_obj);
    VALUE clone;

    if (rb_shape_too_complex_p(shape_id)) {
        clone = rb_imemo_fields_new_complex(CLASS_OF(fields_obj), 0);
        RBASIC_SET_SHAPE_ID(clone, shape_id);
        st_table *src_table = rb_imemo_fields_complex_tbl(fields_obj);
        st_table *dest_table = rb_imemo_fields_complex_tbl(clone);
        st_replace(dest_table, src_table);
        st_foreach(dest_table, imemo_fields_complex_wb_i, (st_data_t)clone);
    }
    else {
        clone = imemo_fields_new(CLASS_OF(fields_obj), RSHAPE_CAPACITY(shape_id));
        RBASIC_SET_SHAPE_ID(clone, shape_id);
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
    if (rb_shape_obj_too_complex_p(fields_obj)) {
        RBASIC_SET_SHAPE_ID(fields_obj, ROOT_TOO_COMPLEX_SHAPE_ID);
    }
    else {
        RBASIC_SET_SHAPE_ID(fields_obj, ROOT_SHAPE_ID);
    }
}

/* =========================================================================
 * memsize
 * ========================================================================= */

size_t
rb_imemo_memsize(VALUE obj)
{
    size_t size = 0;
    switch (imemo_type(obj)) {
      case imemo_ast:
        rb_bug("imemo_ast is obsolete");

        break;
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
      case imemo_parser_strterm:
        break;
      case imemo_svar:
        break;
      case imemo_throw_data:
        break;
      case imemo_tmpbuf:
        size += ((rb_imemo_tmpbuf_t *)obj)->cnt * sizeof(VALUE);

        break;
      case imemo_fields:
        if (rb_shape_obj_too_complex_p(obj)) {
            size += st_memsize(IMEMO_OBJ_FIELDS(obj)->as.complex.table);
        }
        else if (FL_TEST_RAW(obj, OBJ_FIELD_EXTERNAL)) {
            size += RSHAPE_CAPACITY(RBASIC_SHAPE_ID(obj)) * sizeof(VALUE);
        }
        break;
      default:
        rb_bug("unreachable");
    }

    return size;
}

/* =========================================================================
 * mark
 * ========================================================================= */

static bool
moved_or_living_object_strictly_p(VALUE obj)
{
    return obj && (!rb_objspace_garbage_object_p(obj) || BUILTIN_TYPE(obj) == T_MOVED);
}

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
            rb_gc_mark_and_move(&def->body.bmethod.proc);
            if (!reference_updating) {
                if (def->body.bmethod.hooks) rb_hook_list_mark(def->body.bmethod.hooks);
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
      case imemo_ast:
        rb_bug("imemo_ast is obsolete");

        break;
      case imemo_callcache: {
        /* cc is callcache.
         *
         * cc->klass (klass) should not be marked because if the klass is
         * free'ed, the cc->klass will be cleared by `vm_cc_invalidate()`.
         *
         * cc->cme (cme) should not be marked because if cc is invalidated
         * when cme is free'ed.
         * - klass marks cme if klass uses cme.
         * - caller classe's ccs->cme marks cc->cme.
         * - if cc is invalidated (klass doesn't refer the cc),
         *   cc is invalidated by `vm_cc_invalidate()` and cc->cme is
         *   not be accessed.
         * - On the multi-Ractors, cme will be collected with global GC
         *   so that it is safe if GC is not interleaving while accessing
         *   cc and cme.
         * - However, cc_type_super and cc_type_refinement are not chained
         *   from ccs so cc->cme should be marked; the cme might be
         *   reachable only through cc in these cases.
         */
        struct rb_callcache *cc = (struct rb_callcache *)obj;
        if (reference_updating) {
            if (!cc->klass) {
                // already invalidated
            }
            else {
                if (moved_or_living_object_strictly_p(cc->klass) &&
                        moved_or_living_object_strictly_p((VALUE)cc->cme_)) {
                    *((VALUE *)&cc->klass) = rb_gc_location(cc->klass);
                    *((struct rb_callable_method_entry_struct **)&cc->cme_) =
                        (struct rb_callable_method_entry_struct *)rb_gc_location((VALUE)cc->cme_);
                }
                else {
                    vm_cc_invalidate(cc);
                }
            }
        }
        else {
            if (cc->klass && (vm_cc_super_p(cc) || vm_cc_refinement_p(cc))) {
                rb_gc_mark_movable((VALUE)cc->cme_);
                rb_gc_mark_movable((VALUE)cc->klass);
            }
        }

        break;
      }
      case imemo_callinfo:
        break;
      case imemo_constcache: {
        struct iseq_inline_constant_cache_entry *ice = (struct iseq_inline_constant_cache_entry *)obj;

        rb_gc_mark_and_move(&ice->value);

        break;
      }
      case imemo_cref: {
        rb_cref_t *cref = (rb_cref_t *)obj;

        rb_gc_mark_and_move(&cref->klass_or_self);
        rb_gc_mark_and_move_ptr(&cref->next);
        rb_gc_mark_and_move(&cref->refinements);

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
        if (!reference_updating) {
            rb_gc_mark_maybe(memo->u3.value);
        }

        break;
      }
      case imemo_ment:
        mark_and_move_method_entry((rb_method_entry_t *)obj, reference_updating);
        break;
      case imemo_parser_strterm:
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

        if (!reference_updating) {
            do {
                rb_gc_mark_locations(m->ptr, m->ptr + m->cnt);
            } while ((m = m->next) != NULL);
        }

        break;
      }
      case imemo_fields: {
        rb_gc_mark_and_move((VALUE *)&RBASIC(obj)->klass);

        if (rb_shape_obj_too_complex_p(obj)) {
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
    xfree(ce);
    return ID_TABLE_CONTINUE;
}

void
rb_free_const_table(struct rb_id_table *tbl)
{
    rb_id_table_foreach_values(tbl, free_const_entry_i, 0);
    rb_id_table_free(tbl);
}

// alive: if false, target pointers can be freed already.
static void
vm_ccs_free(struct rb_class_cc_entries *ccs, int alive, VALUE klass)
{
    if (ccs->entries) {
        for (int i=0; i<ccs->len; i++) {
            const struct rb_callcache *cc = ccs->entries[i].cc;
            if (!alive) {
                // ccs can be free'ed.
                if (rb_gc_pointer_to_heap_p((VALUE)cc) &&
                    !rb_objspace_garbage_object_p((VALUE)cc) &&
                    IMEMO_TYPE_P(cc, imemo_callcache) &&
                    cc->klass == klass) {
                    // OK. maybe target cc.
                }
                else {
                    continue;
                }
            }

            VM_ASSERT(!vm_cc_super_p(cc) && !vm_cc_refinement_p(cc));
            vm_cc_invalidate(cc);
        }
        ruby_xfree(ccs->entries);
    }
    ruby_xfree(ccs);
}

void
rb_vm_ccs_free(struct rb_class_cc_entries *ccs)
{
    RB_DEBUG_COUNTER_INC(ccs_free);
    vm_ccs_free(ccs, true, Qundef);
}

static enum rb_id_table_iterator_result
cc_table_free_i(VALUE ccs_ptr, void *data)
{
    struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_ptr;
    VALUE klass = (VALUE)data;
    VM_ASSERT(vm_ccs_p(ccs));

    vm_ccs_free(ccs, false, klass);

    return ID_TABLE_CONTINUE;
}

void
rb_cc_table_free(VALUE klass)
{
    // This can be called and work well only for IClass
    // And classext_iclass_free uses rb_cc_tbl_free now.
    // TODO: remove this if it's ok
    struct rb_id_table *cc_tbl = RCLASS_WRITABLE_CC_TBL(klass);

    if (cc_tbl) {
        rb_id_table_foreach_values(cc_tbl, cc_table_free_i, (void *)klass);
        rb_id_table_free(cc_tbl);
    }
}

void
rb_cc_tbl_free(struct rb_id_table *cc_tbl, VALUE klass)
{
    if (!cc_tbl) return;
    rb_id_table_foreach_values(cc_tbl, cc_table_free_i, (void *)klass);
    rb_id_table_free(cc_tbl);
}

static inline void
imemo_fields_free(struct rb_fields *fields)
{
    if (rb_shape_obj_too_complex_p((VALUE)fields)) {
        st_free_table(fields->as.complex.table);
    }
    else if (FL_TEST_RAW((VALUE)fields, OBJ_FIELD_EXTERNAL)) {
        xfree(fields->as.external.ptr);
    }
}

void
rb_imemo_free(VALUE obj)
{
    switch (imemo_type(obj)) {
      case imemo_ast:
        rb_bug("imemo_ast is obsolete");

        break;
      case imemo_callcache:
        RB_DEBUG_COUNTER_INC(obj_imemo_callcache);

        break;
      case imemo_callinfo:{
        const struct rb_callinfo *ci = ((const struct rb_callinfo *)obj);

        if (ci->kwarg) {
            ((struct rb_callinfo_kwarg *)ci->kwarg)->references--;
            if (ci->kwarg->references == 0) xfree((void *)ci->kwarg);
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
        xfree((VALUE *)env->env);
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
      case imemo_parser_strterm:
        RB_DEBUG_COUNTER_INC(obj_imemo_parser_strterm);

        break;
      case imemo_svar:
        RB_DEBUG_COUNTER_INC(obj_imemo_svar);

        break;
      case imemo_throw_data:
        RB_DEBUG_COUNTER_INC(obj_imemo_throw_data);

        break;
      case imemo_tmpbuf:
        xfree(((rb_imemo_tmpbuf_t *)obj)->ptr);
        RB_DEBUG_COUNTER_INC(obj_imemo_tmpbuf);

        break;
      case imemo_fields:
        imemo_fields_free(IMEMO_OBJ_FIELDS(obj));
        RB_DEBUG_COUNTER_INC(obj_imemo_fields);
        break;
      default:
        rb_bug("unreachable");
    }
}
