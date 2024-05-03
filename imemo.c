
#include "constant.h"
#include "id_table.h"
#include "internal.h"
#include "internal/imemo.h"
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
#undef IMEMO_NAME
      default:
        rb_bug("unreachable");
    }
}

/* =========================================================================
 * allocation
 * ========================================================================= */

VALUE
rb_imemo_new(enum imemo_type type, VALUE v0)
{
    size_t size = RVALUE_SIZE;
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

#if IMEMO_DEBUG
VALUE
rb_imemo_new_debug(enum imemo_type type, VALUE v0, const char *file, int line)
{
    VALUE memo = rb_imemo_new(type, v0);
    fprintf(stderr, "memo %p (type: %d) @ %s:%d\n", (void *)memo, imemo_type(memo), file, line);
    return memo;
}
#endif

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
      default:
        rb_bug("unreachable");
    }

    return size;
}

/* =========================================================================
 * mark
 * ========================================================================= */

static enum rb_id_table_iterator_result
cc_table_mark_i(ID id, VALUE ccs_ptr, void *data)
{
    struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_ptr;
    VM_ASSERT(vm_ccs_p(ccs));
    VM_ASSERT(id == ccs->cme->called_id);

    if (METHOD_ENTRY_INVALIDATED(ccs->cme)) {
        rb_vm_ccs_free(ccs);
        return ID_TABLE_DELETE;
    }
    else {
        rb_gc_mark_movable((VALUE)ccs->cme);

        for (int i=0; i<ccs->len; i++) {
            VM_ASSERT((VALUE)data == ccs->entries[i].cc->klass);
            VM_ASSERT(vm_cc_check_cme(ccs->entries[i].cc, ccs->cme));

            rb_gc_mark_movable((VALUE)ccs->entries[i].cc);
        }
        return ID_TABLE_CONTINUE;
    }
}

void
rb_cc_table_mark(VALUE klass)
{
    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
    if (cc_tbl) {
        rb_id_table_foreach(cc_tbl, cc_table_mark_i, (void *)klass);
    }
}

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
            if (vm_cc_super_p(cc) || vm_cc_refinement_p(cc)) {
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
                void *ptr = asan_unpoison_object_temporary((VALUE)cc);
                // ccs can be free'ed.
                if (!rb_objspace_garbage_object_p((VALUE)cc) &&
                    IMEMO_TYPE_P(cc, imemo_callcache) &&
                    cc->klass == klass) {
                    // OK. maybe target cc.
                }
                else {
                    if (ptr) {
                        asan_poison_object((VALUE)cc);
                    }
                    continue;
                }
                if (ptr) {
                    asan_poison_object((VALUE)cc);
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
    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);

    if (cc_tbl) {
        rb_id_table_foreach_values(cc_tbl, cc_table_free_i, (void *)klass);
        rb_id_table_free(cc_tbl);
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

        rb_vm_ci_free(ci);
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
      default:
        rb_bug("unreachable");
    }
}
