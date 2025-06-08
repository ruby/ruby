/**********************************************************************

  class.c -

  $Author$
  created at: Tue Aug 10 15:05:44 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

/*!
 * \addtogroup class
 * \{
 */

#include "ruby/internal/config.h"
#include <ctype.h>

#include "constant.h"
#include "debug_counter.h"
#include "id_table.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/eval.h"
#include "internal/hash.h"
#include "internal/namespace.h"
#include "internal/object.h"
#include "internal/string.h"
#include "internal/variable.h"
#include "ruby/st.h"
#include "vm_core.h"
#include "yjit.h"

/* Flags of T_CLASS
 *
 * 0:    RCLASS_IS_ROOT
 *           The class has been added to the VM roots. Will always be marked and pinned.
 *           This is done for classes defined from C to allow storing them in global variables.
 * 1:    RUBY_FL_SINGLETON
 *           This class is a singleton class.
 * 2:    RCLASS_PRIME_CLASSEXT_PRIME_WRITABLE
 *           This class's prime classext is the only classext and writable from any namespaces.
 *           If unset, the prime classext is writable only from the root namespace.
 * 3:    RCLASS_IS_INITIALIZED
 *           Class has been initialized.
 */

/* Flags of T_ICLASS
 *
 * 2:    RCLASS_PRIME_CLASSEXT_PRIME_WRITABLE
 *           This module's prime classext is the only classext and writable from any namespaces.
 *           If unset, the prime classext is writable only from the root namespace.
 */

/* Flags of T_MODULE
 *
 * 0:    RCLASS_IS_ROOT
 *           The class has been added to the VM roots. Will always be marked and pinned.
 *           This is done for classes defined from C to allow storing them in global variables.
 * 1:    RMODULE_IS_REFINEMENT
 *           Module is used for refinements.
 * 2:    RCLASS_PRIME_CLASSEXT_PRIME_WRITABLE
 *           This module's prime classext is the only classext and writable from any namespaces.
 *           If unset, the prime classext is writable only from the root namespace.
 * 3:    RCLASS_IS_INITIALIZED
 *           Module has been initialized.
 */

#define METACLASS_OF(k) RBASIC(k)->klass
#define SET_METACLASS_OF(k, cls) RBASIC_SET_CLASS(k, cls)

RUBY_EXTERN rb_serial_t ruby_vm_global_cvar_state;

struct duplicate_id_tbl_data {
    struct rb_id_table *tbl;
    VALUE klass;
};

static enum rb_id_table_iterator_result
duplicate_classext_id_table_i(ID key, VALUE value, void *data)
{
    struct rb_id_table *tbl = (struct rb_id_table *)data;
    rb_id_table_insert(tbl, key, value);
    return ID_TABLE_CONTINUE;
}

static enum rb_id_table_iterator_result
duplicate_classext_m_tbl_i(ID key, VALUE value, void *data)
{
    struct duplicate_id_tbl_data *arg = (struct duplicate_id_tbl_data *)data;
    rb_method_entry_t *me = (rb_method_entry_t *)value;
    rb_method_table_insert0(arg->klass, arg->tbl, key, me, false);
    return ID_TABLE_CONTINUE;
}

static struct rb_id_table *
duplicate_classext_m_tbl(struct rb_id_table *orig, VALUE klass, bool init_missing)
{
    struct rb_id_table *tbl;
    if (!orig) {
        if (init_missing)
            return rb_id_table_create(0);
        else
            return NULL;
    }
    tbl = rb_id_table_create(rb_id_table_size(orig));
    struct duplicate_id_tbl_data data = {
        .tbl = tbl,
        .klass = klass,
    };
    rb_id_table_foreach(orig, duplicate_classext_m_tbl_i, &data);
    return tbl;
}

static struct rb_id_table *
duplicate_classext_id_table(struct rb_id_table *orig, bool init_missing)
{
    struct rb_id_table *tbl;

    if (!orig) {
        if (init_missing)
            return rb_id_table_create(0);
        else
            return NULL;
    }
    tbl = rb_id_table_create(rb_id_table_size(orig));
    rb_id_table_foreach(orig, duplicate_classext_id_table_i, tbl);
    return tbl;
}

static rb_const_entry_t *
duplicate_classext_const_entry(rb_const_entry_t *src, VALUE klass)
{
    // See also: setup_const_entry (variable.c)
    rb_const_entry_t *dst = ZALLOC(rb_const_entry_t);

    dst->flag = src->flag;
    dst->line = src->line;
    RB_OBJ_WRITE(klass, &dst->value, src->value);
    RB_OBJ_WRITE(klass, &dst->file, src->file);

    return dst;
}

static enum rb_id_table_iterator_result
duplicate_classext_const_tbl_i(ID key, VALUE value, void *data)
{
    struct duplicate_id_tbl_data *arg = (struct duplicate_id_tbl_data *)data;
    rb_const_entry_t *entry = duplicate_classext_const_entry((rb_const_entry_t *)value, arg->klass);

    rb_id_table_insert(arg->tbl, key, (VALUE)entry);

    return ID_TABLE_CONTINUE;
}

static struct rb_id_table *
duplicate_classext_const_tbl(struct rb_id_table *src, VALUE klass)
{
    struct rb_id_table *dst;

    if (!src)
        return NULL;

    dst = rb_id_table_create(rb_id_table_size(src));

    struct duplicate_id_tbl_data data = {
        .tbl = dst,
        .klass = klass,
    };
    rb_id_table_foreach(src, duplicate_classext_const_tbl_i, (void *)&data);

    return dst;
}

static VALUE
namespace_subclasses_tbl_key(const rb_namespace_t *ns)
{
    if (!ns){
        return 0;
    }
    return (VALUE)ns->ns_id;
}

static void
duplicate_classext_subclasses(rb_classext_t *orig, rb_classext_t *copy)
{
    rb_subclass_anchor_t *anchor, *orig_anchor;
    rb_subclass_entry_t *head, *cur, *cdr, *entry, *first = NULL;
    rb_ns_subclasses_t *ns_subclasses;
    struct st_table *tbl;

    if (RCLASSEXT_SUBCLASSES(orig)) {
        orig_anchor = RCLASSEXT_SUBCLASSES(orig);
        ns_subclasses = orig_anchor->ns_subclasses;
        tbl = ((rb_ns_subclasses_t *)ns_subclasses)->tbl;

        anchor = ZALLOC(rb_subclass_anchor_t);
        anchor->ns_subclasses = rb_ns_subclasses_ref_inc(ns_subclasses);

        head = ZALLOC(rb_subclass_entry_t);
        anchor->head = head;

        RCLASSEXT_SUBCLASSES(copy) = anchor;

        cur = head;
        entry = orig_anchor->head;
        RUBY_ASSERT(!entry->klass);
        // The head entry has NULL klass always. See rb_class_foreach_subclass().
        entry = entry->next;
        while (entry) {
            if (rb_objspace_garbage_object_p(entry->klass)) {
                entry = entry->next;
                continue;
            }
            cdr = ZALLOC(rb_subclass_entry_t);
            cdr->klass = entry->klass;
            cdr->prev = cur;
            cur->next = cdr;
            if (!first) {
                VALUE ns_id = namespace_subclasses_tbl_key(RCLASSEXT_NS(copy));
                first = cdr;
                st_insert(tbl, ns_id, (st_data_t)first);
            }
            cur = cdr;
            entry = entry->next;
        }
    }

    if (RCLASSEXT_NS_SUPER_SUBCLASSES(orig))
        RCLASSEXT_NS_SUPER_SUBCLASSES(copy) = rb_ns_subclasses_ref_inc(RCLASSEXT_NS_SUPER_SUBCLASSES(orig));
    if (RCLASSEXT_NS_MODULE_SUBCLASSES(orig))
        RCLASSEXT_NS_MODULE_SUBCLASSES(copy) = rb_ns_subclasses_ref_inc(RCLASSEXT_NS_MODULE_SUBCLASSES(orig));
}

static void
class_duplicate_iclass_classext(VALUE iclass, rb_classext_t *mod_ext, const rb_namespace_t *ns)
{
    RUBY_ASSERT(RB_TYPE_P(iclass, T_ICLASS));

    rb_classext_t *src = RCLASS_EXT_PRIME(iclass);
    rb_classext_t *ext = RCLASS_EXT_TABLE_LOOKUP_INTERNAL(iclass, ns);
    int first_set = 0;

    if (ext) {
        // iclass classext for the ns is only for cc/callable_m_tbl if it's created earlier than module's one
        rb_invalidate_method_caches(RCLASSEXT_CALLABLE_M_TBL(ext), RCLASSEXT_CC_TBL(ext));
    }

    ext = ZALLOC(rb_classext_t);

    RCLASSEXT_NS(ext) = ns;

    RCLASSEXT_SUPER(ext) = RCLASSEXT_SUPER(src);

    // See also: rb_include_class_new()
    if (RCLASSEXT_ICLASS_IS_ORIGIN(src) && !RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(src)) {
        RCLASSEXT_M_TBL(ext) = duplicate_classext_m_tbl(RCLASSEXT_M_TBL(src), iclass, true);
    }
    else {
        RCLASSEXT_M_TBL(ext) = RCLASSEXT_M_TBL(mod_ext);
    }

    RCLASSEXT_CONST_TBL(ext) = RCLASSEXT_CONST_TBL(mod_ext);
    RCLASSEXT_CVC_TBL(ext) = RCLASSEXT_CVC_TBL(mod_ext);

    // Those are cache and should be recreated when methods are called
    // RCLASSEXT_CALLABLE_M_TBL(ext) = NULL;
    // RCLASSEXT_CC_TBL(ext) = NULL;

    // subclasses, namespace_super_subclasses_tbl, namespace_module_subclasses_tbl
    duplicate_classext_subclasses(src, ext);

    RCLASSEXT_SET_ORIGIN(ext, iclass, RCLASSEXT_ORIGIN(src));
    RCLASSEXT_ICLASS_IS_ORIGIN(ext) = RCLASSEXT_ICLASS_IS_ORIGIN(src);
    RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(ext) = RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(src);

    RCLASSEXT_SET_INCLUDER(ext, iclass, RCLASSEXT_INCLUDER(src));

    first_set = RCLASS_SET_NAMESPACE_CLASSEXT(iclass, ns, ext);
    if (first_set) {
        RCLASS_SET_PRIME_CLASSEXT_WRITABLE(iclass, false);
    }
}

rb_classext_t *
rb_class_duplicate_classext(rb_classext_t *orig, VALUE klass, const rb_namespace_t *ns)
{
    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_MODULE) || RB_TYPE_P(klass, T_ICLASS));

    rb_classext_t *ext = ZALLOC(rb_classext_t);
    bool dup_iclass = RB_TYPE_P(klass, T_MODULE) ? true : false;

    RCLASSEXT_NS(ext) = ns;

    RCLASSEXT_SUPER(ext) = RCLASSEXT_SUPER(orig);

    RCLASSEXT_M_TBL(ext) = duplicate_classext_m_tbl(RCLASSEXT_M_TBL(orig), klass, dup_iclass);

    if (orig->fields_obj) {
        RB_OBJ_WRITE(klass, &ext->fields_obj, rb_imemo_fields_clone(orig->fields_obj));
    }

    if (RCLASSEXT_SHARED_CONST_TBL(orig)) {
        RCLASSEXT_CONST_TBL(ext) = RCLASSEXT_CONST_TBL(orig);
        RCLASSEXT_SHARED_CONST_TBL(ext) = true;
    }
    else {
        RCLASSEXT_CONST_TBL(ext) = duplicate_classext_const_tbl(RCLASSEXT_CONST_TBL(orig), klass);
        RCLASSEXT_SHARED_CONST_TBL(ext) = false;
    }
    /*
     * callable_m_tbl is for `super` chain, and entries will be created when the super chain is called.
     * so initially, it can be NULL and let it be created lazily.
     * RCLASSEXT_CALLABLE_M_TBL(ext) = NULL;
     *
     * cc_tbl is for method inline cache, and method calls from different namespaces never occur on
     * the same code, so the copied classext should have a different cc_tbl from the prime one.
     * RCLASSEXT_CC_TBL(copy) = NULL
     */

    RCLASSEXT_CVC_TBL(ext) = duplicate_classext_id_table(RCLASSEXT_CVC_TBL(orig), dup_iclass);

    // subclasses, subclasses_index
    duplicate_classext_subclasses(orig, ext);

    RCLASSEXT_SET_ORIGIN(ext, klass, RCLASSEXT_ORIGIN(orig));
    /*
     * Members not copied to namespace classext values
     * * refined_class
     * * as.class.allocator / as.singleton_class.attached_object
     * * includer
     * * max IV count
     * * variation count
     */
    RCLASSEXT_PERMANENT_CLASSPATH(ext) = RCLASSEXT_PERMANENT_CLASSPATH(orig);
    RCLASSEXT_CLONED(ext) = RCLASSEXT_CLONED(orig);
    RCLASSEXT_CLASSPATH(ext) = RCLASSEXT_CLASSPATH(orig);

    /* For the usual T_CLASS/T_MODULE, iclass flags are always false */

    if (dup_iclass) {
        VALUE iclass;
        /*
         * ICLASS has the same m_tbl/const_tbl/cvc_tbl with the included module.
         * So the module's classext is copied, its tables should be also referred
         * by the ICLASS's classext for the namespace.
         */
        rb_subclass_anchor_t *anchor = RCLASSEXT_SUBCLASSES(ext);
        rb_subclass_entry_t *subclass_entry = anchor->head;
        while (subclass_entry) {
            if (subclass_entry->klass && RB_TYPE_P(subclass_entry->klass, T_ICLASS)) {
                iclass = subclass_entry->klass;
                if (RBASIC_CLASS(iclass) == klass) {
                    // Is the subclass an ICLASS including this module into another class
                    // If so we need to re-associate it under our namespace with the new ext
                    class_duplicate_iclass_classext(iclass, ext, ns);
                }
            }
            subclass_entry = subclass_entry->next;
        }
    }

    return ext;
}

void
rb_class_ensure_writable(VALUE klass)
{
    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_MODULE) || RB_TYPE_P(klass, T_ICLASS));
    RCLASS_EXT_WRITABLE(klass);
}

struct class_classext_foreach_arg {
    rb_class_classext_foreach_callback_func *func;
    void * callback_arg;
};

static int
class_classext_foreach_i(st_data_t key, st_data_t value, st_data_t arg)
{
    struct class_classext_foreach_arg *foreach_arg = (struct class_classext_foreach_arg *)arg;
    rb_class_classext_foreach_callback_func *func = foreach_arg->func;
    func((rb_classext_t *)value, false, (VALUE)key, foreach_arg->callback_arg);
    return ST_CONTINUE;
}

void
rb_class_classext_foreach(VALUE klass, rb_class_classext_foreach_callback_func *func, void *arg)
{
    st_table *tbl = RCLASS(klass)->ns_classext_tbl;
    struct class_classext_foreach_arg foreach_arg;
    if (tbl) {
        foreach_arg.func = func;
        foreach_arg.callback_arg = arg;
        rb_st_foreach(tbl, class_classext_foreach_i, (st_data_t)&foreach_arg);
    }
    func(RCLASS_EXT_PRIME(klass), true, (VALUE)NULL, arg);
}

VALUE
rb_class_super_of(VALUE klass)
{
    return RCLASS_SUPER(klass);
}

VALUE
rb_class_singleton_p(VALUE klass)
{
    return RCLASS_SINGLETON_P(klass);
}

unsigned char
rb_class_variation_count(VALUE klass)
{
    return RCLASS_VARIATION_COUNT(klass);
}

static void
push_subclass_entry_to_list(VALUE super, VALUE klass, bool is_module)
{
    rb_subclass_entry_t *entry, *head;
    rb_subclass_anchor_t *anchor;
    rb_ns_subclasses_t *ns_subclasses;
    struct st_table *tbl;
    const rb_namespace_t *ns = rb_current_namespace();

    entry = ZALLOC(rb_subclass_entry_t);
    entry->klass = klass;

    RB_VM_LOCKING() {
        anchor = RCLASS_WRITABLE_SUBCLASSES(super);
        VM_ASSERT(anchor);
        ns_subclasses = (rb_ns_subclasses_t *)anchor->ns_subclasses;
        VM_ASSERT(ns_subclasses);
        tbl = ns_subclasses->tbl;
        VM_ASSERT(tbl);

        head = anchor->head;
        if (head->next) {
            head->next->prev = entry;
            entry->next = head->next;
        }
        head->next = entry;
        entry->prev = head;
        st_insert(tbl, namespace_subclasses_tbl_key(ns), (st_data_t)entry);
    }

    if (is_module) {
        RCLASS_WRITE_NS_MODULE_SUBCLASSES(klass, anchor->ns_subclasses);
    }
    else {
        RCLASS_WRITE_NS_SUPER_SUBCLASSES(klass, anchor->ns_subclasses);
    }
}

void
rb_class_subclass_add(VALUE super, VALUE klass)
{
    if (super && !UNDEF_P(super)) {
        push_subclass_entry_to_list(super, klass, false);
    }
}

static void
rb_module_add_to_subclasses_list(VALUE module, VALUE iclass)
{
    if (module && !UNDEF_P(module)) {
        push_subclass_entry_to_list(module, iclass, true);
    }
}

void
rb_class_remove_subclass_head(VALUE klass) // TODO: check this is still used and required
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    rb_class_classext_free_subclasses(ext, klass);
}

static struct rb_subclass_entry *
class_get_subclasses_for_ns(struct st_table *tbl, VALUE ns_id)
{
    st_data_t value;
    if (st_lookup(tbl, (st_data_t)ns_id, &value)) {
        return (struct rb_subclass_entry *)value;
    }
    return NULL;
}

static void
remove_class_from_subclasses(struct st_table *tbl, VALUE ns_id, VALUE klass)
{
    rb_subclass_entry_t *entry = class_get_subclasses_for_ns(tbl, ns_id);
    bool first_entry = true;
    while (entry) {
        if (entry->klass == klass) {
            rb_subclass_entry_t *prev = entry->prev, *next = entry->next;

            if (prev) {
                prev->next = next;
            }
            if (next) {
                next->prev = prev;
            }

            xfree(entry);

            if (first_entry) {
                if (next) {
                    st_insert(tbl, ns_id, (st_data_t)next);
                }
                else {
                    // no subclass entries in this ns
                    st_delete(tbl, &ns_id, NULL);
                }
            }
            break;
        }
        else if (first_entry) {
            first_entry = false;
        }
        entry = entry->next;
    }
}

void
rb_class_remove_from_super_subclasses(VALUE klass)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    rb_ns_subclasses_t *ns_subclasses = RCLASSEXT_NS_SUPER_SUBCLASSES(ext);

    if (!ns_subclasses) return;
    remove_class_from_subclasses(ns_subclasses->tbl, namespace_subclasses_tbl_key(RCLASSEXT_NS(ext)), klass);
    rb_ns_subclasses_ref_dec(ns_subclasses);
    RCLASSEXT_NS_SUPER_SUBCLASSES(ext) = 0;
}

void
rb_class_remove_from_module_subclasses(VALUE klass)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    rb_ns_subclasses_t *ns_subclasses = RCLASSEXT_NS_MODULE_SUBCLASSES(ext);

    if (!ns_subclasses) return;
    remove_class_from_subclasses(ns_subclasses->tbl, namespace_subclasses_tbl_key(RCLASSEXT_NS(ext)), klass);
    rb_ns_subclasses_ref_dec(ns_subclasses);
    RCLASSEXT_NS_MODULE_SUBCLASSES(ext) = 0;
}

void
rb_class_classext_free_subclasses(rb_classext_t *ext, VALUE klass)
{
    rb_subclass_anchor_t *anchor = RCLASSEXT_SUBCLASSES(ext);
    struct st_table *tbl = anchor->ns_subclasses->tbl;
    VALUE ns_id = namespace_subclasses_tbl_key(RCLASSEXT_NS(ext));
    rb_subclass_entry_t *next, *entry = anchor->head;

    while (entry) {
        next = entry->next;
        xfree(entry);
        entry = next;
    }
    VM_ASSERT(
        rb_ns_subclasses_ref_count(anchor->ns_subclasses) > 0,
        "ns_subclasses refcount (%p) %ld", anchor->ns_subclasses, rb_ns_subclasses_ref_count(anchor->ns_subclasses));
    st_delete(tbl, &ns_id, NULL);
    rb_ns_subclasses_ref_dec(anchor->ns_subclasses);
    xfree(anchor);

    if (RCLASSEXT_NS_SUPER_SUBCLASSES(ext)) {
        rb_ns_subclasses_t *ns_sub = RCLASSEXT_NS_SUPER_SUBCLASSES(ext);
        remove_class_from_subclasses(ns_sub->tbl, ns_id, klass);
        rb_ns_subclasses_ref_dec(ns_sub);
    }
    if (RCLASSEXT_NS_MODULE_SUBCLASSES(ext)) {
        rb_ns_subclasses_t *ns_sub = RCLASSEXT_NS_MODULE_SUBCLASSES(ext);
        remove_class_from_subclasses(ns_sub->tbl, ns_id, klass);
        rb_ns_subclasses_ref_dec(ns_sub);
    }
}

void
rb_class_foreach_subclass(VALUE klass, void (*f)(VALUE, VALUE), VALUE arg)
{
    rb_subclass_entry_t *tmp;
    rb_subclass_entry_t *cur = RCLASS_SUBCLASSES_FIRST(klass);
    /* do not be tempted to simplify this loop into a for loop, the order of
       operations is important here if `f` modifies the linked list */
    while (cur) {
        VALUE curklass = cur->klass;
        tmp = cur->next;
        // do not trigger GC during f, otherwise the cur will become
        // a dangling pointer if the subclass is collected
        f(curklass, arg);
        cur = tmp;
    }
}

static void
class_detach_subclasses(VALUE klass, VALUE arg)
{
    rb_class_remove_from_super_subclasses(klass);
}

void
rb_class_detach_subclasses(VALUE klass)
{
    rb_class_foreach_subclass(klass, class_detach_subclasses, Qnil);
}

static void
class_detach_module_subclasses(VALUE klass, VALUE arg)
{
    rb_class_remove_from_module_subclasses(klass);
}

void
rb_class_detach_module_subclasses(VALUE klass)
{
    rb_class_foreach_subclass(klass, class_detach_module_subclasses, Qnil);
}

static void
class_switch_superclass(VALUE super, VALUE klass)
{
    class_detach_subclasses(klass, Qnil);
    rb_class_subclass_add(super, klass);
}

/**
 * Allocates a struct RClass for a new class, iclass, or module.
 *
 * @param type      The type of the RClass (T_CLASS, T_ICLASS, or T_MODULE)
 * @param klass     value for basic.klass of the returned object.
 * @return          an uninitialized Class/IClass/Module object.
 * @pre  `klass` must refer to a class or module
 *
 * @note this function is not Class#allocate.
 */
static VALUE
class_alloc(enum ruby_value_type type, VALUE klass)
{
    rb_ns_subclasses_t *ns_subclasses;
    rb_subclass_anchor_t *anchor;
    const rb_namespace_t *ns = rb_definition_namespace();
    size_t alloc_size = sizeof(struct RClass) + sizeof(rb_classext_t);

    // class_alloc is supposed to return a new object that is not promoted yet.
    // So, we need to avoid GC after NEWOBJ_OF.
    // To achieve that, we allocate subclass lists before NEWOBJ_OF.
    //
    // TODO: Note that this could cause memory leak.
    // If NEWOBJ_OF fails with out of memory, these buffers will leak.
    ns_subclasses = ZALLOC(rb_ns_subclasses_t);
    ns_subclasses->refcount = 1;
    ns_subclasses->tbl = st_init_numtable();
    anchor = ZALLOC(rb_subclass_anchor_t);
    anchor->ns_subclasses = ns_subclasses;
    anchor->head = ZALLOC(rb_subclass_entry_t);

    RUBY_ASSERT(type == T_CLASS || type == T_ICLASS || type == T_MODULE);

    VALUE flags = type;
    if (RGENGC_WB_PROTECTED_CLASS) flags |= FL_WB_PROTECTED;
    NEWOBJ_OF(obj, struct RClass, klass, flags, alloc_size, 0);

    memset(RCLASS_EXT_PRIME(obj), 0, sizeof(rb_classext_t));

    /* ZALLOC
      RCLASS_CONST_TBL(obj) = 0;
      RCLASS_M_TBL(obj) = 0;
      RCLASS_FIELDS(obj) = 0;
      RCLASS_SET_SUPER((VALUE)obj, 0);
     */

    RCLASS_PRIME_NS((VALUE)obj) = ns;
    // Classes/Modules defined in user namespaces are
    // writable directly because it exists only in a namespace.
    RCLASS_SET_PRIME_CLASSEXT_WRITABLE((VALUE)obj, !rb_namespace_available() || NAMESPACE_USER_P(ns) ? true : false);

    RCLASS_SET_ORIGIN((VALUE)obj, (VALUE)obj);
    RCLASS_SET_REFINED_CLASS((VALUE)obj, Qnil);

    RCLASS_SET_SUBCLASSES((VALUE)obj, anchor);

    return (VALUE)obj;
}

static VALUE
class_associate_super(VALUE klass, VALUE super, bool init)
{
    if (super && !UNDEF_P(super)) {
        class_switch_superclass(super, klass);
    }
    if (init) {
        RCLASS_SET_SUPER(klass, super);
    }
    else {
        RCLASS_WRITE_SUPER(klass, super);
    }
    rb_class_update_superclasses(klass);
    return super;
}

VALUE
rb_class_set_super(VALUE klass, VALUE super)
{
    return class_associate_super(klass, super, false);
}

static void
class_initialize_method_table(VALUE c)
{
    // initialize the prime classext m_tbl
    RCLASS_SET_M_TBL_EVEN_WHEN_PROMOTED(c, rb_id_table_create(0));
}

static void
class_clear_method_table(VALUE c)
{
    RCLASS_WRITE_M_TBL_EVEN_WHEN_PROMOTED(c, rb_id_table_create(0));
}

/**
 * A utility function that wraps class_alloc.
 *
 * allocates a class and initializes safely.
 * @param super     a class from which the new class derives.
 * @return          a class object.
 * @pre  `super` must be a class.
 * @post the metaclass of the new class is Class.
 */
VALUE
rb_class_boot(VALUE super)
{
    VALUE klass = class_alloc(T_CLASS, rb_cClass);

    // initialize method table prior to class_associate_super()
    // because class_associate_super() may cause GC and promote klass
    class_initialize_method_table(klass);

    class_associate_super(klass, super, true);
    if (super && !UNDEF_P(super)) {
        rb_class_set_initialized(klass);
    }

    return (VALUE)klass;
}

static VALUE *
class_superclasses_including_self(VALUE klass)
{
    if (RCLASS_SUPERCLASSES_WITH_SELF_P(klass))
        return RCLASS_SUPERCLASSES(klass);

    size_t depth = RCLASS_SUPERCLASS_DEPTH(klass);
    VALUE *superclasses = xmalloc(sizeof(VALUE) * (depth + 1));
    if (depth > 0)
        memcpy(superclasses, RCLASS_SUPERCLASSES(klass), sizeof(VALUE) * depth);
    superclasses[depth] = klass;

    return superclasses;
}

void
rb_class_update_superclasses(VALUE klass)
{
    VALUE *superclasses;
    size_t super_depth;
    VALUE super = RCLASS_SUPER(klass);

    if (!RB_TYPE_P(klass, T_CLASS)) return;
    if (UNDEF_P(super)) return;

    // If the superclass array is already built
    if (RCLASS_SUPERCLASSES(klass))
        return;

    // find the proper superclass
    while (super != Qfalse && !RB_TYPE_P(super, T_CLASS)) {
        super = RCLASS_SUPER(super);
    }

    // For BasicObject and uninitialized classes, depth=0 and ary=NULL
    if (super == Qfalse)
        return;

    // Sometimes superclasses are set before the full ancestry tree is built
    // This happens during metaclass construction
    if (super != rb_cBasicObject && !RCLASS_SUPERCLASS_DEPTH(super)) {
        rb_class_update_superclasses(super);

        // If it is still unset we need to try later
        if (!RCLASS_SUPERCLASS_DEPTH(super))
            return;
    }

    super_depth = RCLASS_SUPERCLASS_DEPTH(super);
    if (RCLASS_SUPERCLASSES_WITH_SELF_P(super)) {
        superclasses = RCLASS_SUPERCLASSES(super);
    }
    else {
        superclasses = class_superclasses_including_self(super);
        RCLASS_WRITE_SUPERCLASSES(super, super_depth, superclasses, true);
    }

    size_t depth = super_depth == RCLASS_MAX_SUPERCLASS_DEPTH ? super_depth : super_depth + 1;
    RCLASS_WRITE_SUPERCLASSES(klass, depth, superclasses, false);
}

void
rb_check_inheritable(VALUE super)
{
    if (!RB_TYPE_P(super, T_CLASS)) {
        rb_raise(rb_eTypeError, "superclass must be an instance of Class (given an instance of %"PRIsVALUE")",
                 rb_obj_class(super));
    }
    if (RCLASS_SINGLETON_P(super)) {
        rb_raise(rb_eTypeError, "can't make subclass of singleton class");
    }
    if (super == rb_cClass) {
        rb_raise(rb_eTypeError, "can't make subclass of Class");
    }
}

VALUE
rb_class_new(VALUE super)
{
    Check_Type(super, T_CLASS);
    rb_check_inheritable(super);
    VALUE klass = rb_class_boot(super);

    if (super != rb_cObject && super != rb_cBasicObject) {
        RCLASS_SET_MAX_IV_COUNT(klass, RCLASS_MAX_IV_COUNT(super));
    }

    RUBY_ASSERT(getenv("RUBY_NAMESPACE") || RCLASS_PRIME_CLASSEXT_WRITABLE_P(klass));

    return klass;
}

VALUE
rb_class_s_alloc(VALUE klass)
{
    return rb_class_boot(0);
}

static void
clone_method(VALUE old_klass, VALUE new_klass, ID mid, const rb_method_entry_t *me)
{
    if (me->def->type == VM_METHOD_TYPE_ISEQ) {
        rb_cref_t *new_cref = rb_vm_rewrite_cref(me->def->body.iseq.cref, old_klass, new_klass);
        rb_add_method_iseq(new_klass, mid, me->def->body.iseq.iseqptr, new_cref, METHOD_ENTRY_VISI(me));
    }
    else {
        rb_method_entry_set(new_klass, mid, me, METHOD_ENTRY_VISI(me));
    }
}

struct clone_method_arg {
    VALUE new_klass;
    VALUE old_klass;
};

static enum rb_id_table_iterator_result
clone_method_i(ID key, VALUE value, void *data)
{
    const struct clone_method_arg *arg = (struct clone_method_arg *)data;
    clone_method(arg->old_klass, arg->new_klass, key, (const rb_method_entry_t *)value);
    return ID_TABLE_CONTINUE;
}

struct clone_const_arg {
    VALUE klass;
    struct rb_id_table *tbl;
};

static int
clone_const(ID key, const rb_const_entry_t *ce, struct clone_const_arg *arg)
{
    rb_const_entry_t *nce = ALLOC(rb_const_entry_t);
    MEMCPY(nce, ce, rb_const_entry_t, 1);
    RB_OBJ_WRITTEN(arg->klass, Qundef, ce->value);
    RB_OBJ_WRITTEN(arg->klass, Qundef, ce->file);

    rb_id_table_insert(arg->tbl, key, (VALUE)nce);
    return ID_TABLE_CONTINUE;
}

static enum rb_id_table_iterator_result
clone_const_i(ID key, VALUE value, void *data)
{
    return clone_const(key, (const rb_const_entry_t *)value, data);
}

static void
class_init_copy_check(VALUE clone, VALUE orig)
{
    if (orig == rb_cBasicObject) {
        rb_raise(rb_eTypeError, "can't copy the root class");
    }
    if (RCLASS_INITIALIZED_P(clone)) {
        rb_raise(rb_eTypeError, "already initialized class");
    }
    if (RCLASS_SINGLETON_P(orig)) {
        rb_raise(rb_eTypeError, "can't copy singleton class");
    }
}

struct cvc_table_copy_ctx {
    VALUE clone;
    struct rb_id_table * new_table;
};

static enum rb_id_table_iterator_result
cvc_table_copy(ID id, VALUE val, void *data)
{
    struct cvc_table_copy_ctx *ctx = (struct cvc_table_copy_ctx *)data;
    struct rb_cvar_class_tbl_entry * orig_entry;
    orig_entry = (struct rb_cvar_class_tbl_entry *)val;

    struct rb_cvar_class_tbl_entry *ent;

    ent = ALLOC(struct rb_cvar_class_tbl_entry);
    ent->class_value = ctx->clone;
    ent->cref = orig_entry->cref;
    ent->global_cvar_state = orig_entry->global_cvar_state;
    rb_id_table_insert(ctx->new_table, id, (VALUE)ent);

    RB_OBJ_WRITTEN(ctx->clone, Qundef, ent->cref);

    return ID_TABLE_CONTINUE;
}

static void
copy_tables(VALUE clone, VALUE orig)
{
    if (RCLASS_CONST_TBL(clone)) {
        rb_free_const_table(RCLASS_CONST_TBL(clone));
        RCLASS_WRITE_CONST_TBL(clone, 0, false);
    }
    if (RCLASS_CVC_TBL(orig)) {
        struct rb_id_table *rb_cvc_tbl = RCLASS_CVC_TBL(orig);
        struct rb_id_table *rb_cvc_tbl_dup = rb_id_table_create(rb_id_table_size(rb_cvc_tbl));

        struct cvc_table_copy_ctx ctx;
        ctx.clone = clone;
        ctx.new_table = rb_cvc_tbl_dup;
        rb_id_table_foreach(rb_cvc_tbl, cvc_table_copy, &ctx);
        RCLASS_WRITE_CVC_TBL(clone, rb_cvc_tbl_dup);
    }
    rb_id_table_free(RCLASS_M_TBL(clone));
    RCLASS_WRITE_M_TBL_EVEN_WHEN_PROMOTED(clone, 0);
    if (!RB_TYPE_P(clone, T_ICLASS)) {
        st_data_t id;

        rb_fields_tbl_copy(clone, orig);
        CONST_ID(id, "__tmp_classpath__");
        rb_attr_delete(clone, id);
        CONST_ID(id, "__classpath__");
        rb_attr_delete(clone, id);
    }
    if (RCLASS_CONST_TBL(orig)) {
        struct clone_const_arg arg;
        struct rb_id_table *const_tbl;
        arg.tbl = const_tbl = rb_id_table_create(0);
        arg.klass = clone;
        rb_id_table_foreach(RCLASS_CONST_TBL(orig), clone_const_i, &arg);
        RCLASS_WRITE_CONST_TBL(clone, const_tbl, false);
    }
}

static bool ensure_origin(VALUE klass);

void
rb_class_set_initialized(VALUE klass)
{
    RUBY_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_MODULE));
    FL_SET_RAW(klass, RCLASS_IS_INITIALIZED);
    /* no more re-initialization */
}

void
rb_module_check_initializable(VALUE mod)
{
    if (RCLASS_INITIALIZED_P(mod)) {
        rb_raise(rb_eTypeError, "already initialized module");
    }
}

/* :nodoc: */
VALUE
rb_mod_init_copy(VALUE clone, VALUE orig)
{
    /* Only class or module is valid here, but other classes may enter here and
     * only hit an exception on the OBJ_INIT_COPY checks
     */
    switch (BUILTIN_TYPE(clone)) {
      case T_CLASS:
        class_init_copy_check(clone, orig);
        break;
      case T_MODULE:
        rb_module_check_initializable(clone);
        break;
      default:
        break;
    }
    if (!OBJ_INIT_COPY(clone, orig)) return clone;

    RUBY_ASSERT(RB_TYPE_P(orig, T_CLASS) || RB_TYPE_P(orig, T_MODULE));
    RUBY_ASSERT(BUILTIN_TYPE(clone) == BUILTIN_TYPE(orig));

    rb_class_set_initialized(clone);

    /* cloned flag is refer at constant inline cache
     * see vm_get_const_key_cref() in vm_insnhelper.c
     */
    RCLASS_SET_CLONED(clone, true);
    RCLASS_SET_CLONED(orig, true);

    if (!RCLASS_SINGLETON_P(CLASS_OF(clone))) {
        RBASIC_SET_CLASS(clone, rb_singleton_class_clone(orig));
        rb_singleton_class_attached(METACLASS_OF(clone), (VALUE)clone);
    }
    if (BUILTIN_TYPE(clone) == T_CLASS) {
        RCLASS_SET_ALLOCATOR(clone, RCLASS_ALLOCATOR(orig));
    }
    copy_tables(clone, orig);
    if (RCLASS_M_TBL(orig)) {
        struct clone_method_arg arg;
        arg.old_klass = orig;
        arg.new_klass = clone;
        // TODO: use class_initialize_method_table() instead of RCLASS_SET_M_TBL_*
        //       after RCLASS_SET_M_TBL is protected by write barrier
        RCLASS_SET_M_TBL_EVEN_WHEN_PROMOTED(clone, rb_id_table_create(0));
        rb_id_table_foreach(RCLASS_M_TBL(orig), clone_method_i, &arg);
    }

    if (RCLASS_ORIGIN(orig) == orig) {
        rb_class_set_super(clone, RCLASS_SUPER(orig));
    }
    else {
        VALUE p = RCLASS_SUPER(orig);
        VALUE orig_origin = RCLASS_ORIGIN(orig);
        VALUE prev_clone_p = clone;
        VALUE origin_stack = rb_ary_hidden_new(2);
        VALUE origin[2];
        VALUE clone_p = 0;
        long origin_len;
        int add_subclass;
        VALUE clone_origin;

        ensure_origin(clone);
        clone_origin = RCLASS_ORIGIN(clone);

        while (p && p != orig_origin) {
            if (BUILTIN_TYPE(p) != T_ICLASS) {
                rb_bug("non iclass between module/class and origin");
            }
            clone_p = class_alloc(T_ICLASS, METACLASS_OF(p));
            /* We should set the m_tbl right after allocation before anything
             * that can trigger GC to avoid clone_p from becoming old and
             * needing to fire write barriers. */
            RCLASS_SET_M_TBL(clone_p, RCLASS_M_TBL(p));
            rb_class_set_super(prev_clone_p, clone_p);
            prev_clone_p = clone_p;
            RCLASS_SET_CONST_TBL(clone_p, RCLASS_CONST_TBL(p), false);
            if (RB_TYPE_P(clone, T_CLASS)) {
                RCLASS_SET_INCLUDER(clone_p, clone);
            }
            add_subclass = TRUE;
            if (p != RCLASS_ORIGIN(p)) {
                origin[0] = clone_p;
                origin[1] = RCLASS_ORIGIN(p);
                rb_ary_cat(origin_stack, origin, 2);
            }
            else if ((origin_len = RARRAY_LEN(origin_stack)) > 1 &&
                     RARRAY_AREF(origin_stack, origin_len - 1) == p) {
                RCLASS_WRITE_ORIGIN(RARRAY_AREF(origin_stack, (origin_len -= 2)), clone_p);
                RICLASS_WRITE_ORIGIN_SHARED_MTBL(clone_p);
                rb_ary_resize(origin_stack, origin_len);
                add_subclass = FALSE;
            }
            if (add_subclass) {
                rb_module_add_to_subclasses_list(METACLASS_OF(p), clone_p);
            }
            p = RCLASS_SUPER(p);
        }

        if (p == orig_origin) {
            if (clone_p) {
                rb_class_set_super(clone_p, clone_origin);
                rb_class_set_super(clone_origin, RCLASS_SUPER(orig_origin));
            }
            copy_tables(clone_origin, orig_origin);
            if (RCLASS_M_TBL(orig_origin)) {
                struct clone_method_arg arg;
                arg.old_klass = orig;
                arg.new_klass = clone;
                class_initialize_method_table(clone_origin);
                rb_id_table_foreach(RCLASS_M_TBL(orig_origin), clone_method_i, &arg);
            }
        }
        else {
            rb_bug("no origin for class that has origin");
        }

        rb_class_update_superclasses(clone);
    }

    return clone;
}

VALUE
rb_singleton_class_clone(VALUE obj)
{
    return rb_singleton_class_clone_and_attach(obj, Qundef);
}

// Clone and return the singleton class of `obj` if it has been created and is attached to `obj`.
VALUE
rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach)
{
    const VALUE klass = METACLASS_OF(obj);

    // Note that `rb_singleton_class()` can create situations where `klass` is
    // attached to an object other than `obj`. In which case `obj` does not have
    // a material singleton class attached yet and there is no singleton class
    // to clone.
    if (!(RCLASS_SINGLETON_P(klass) && RCLASS_ATTACHED_OBJECT(klass) == obj)) {
        // nothing to clone
        return klass;
    }
    else {
        /* copy singleton(unnamed) class */
        bool klass_of_clone_is_new;
        RUBY_ASSERT(RB_TYPE_P(klass, T_CLASS));
        VALUE clone = class_alloc(T_CLASS, 0);

        if (BUILTIN_TYPE(obj) == T_CLASS) {
            klass_of_clone_is_new = true;
            RBASIC_SET_CLASS(clone, clone);
        }
        else {
            VALUE klass_metaclass_clone = rb_singleton_class_clone(klass);
            // When `METACLASS_OF(klass) == klass_metaclass_clone`, it means the
            // recursive call did not clone `METACLASS_OF(klass)`.
            klass_of_clone_is_new = (METACLASS_OF(klass) != klass_metaclass_clone);
            RBASIC_SET_CLASS(clone, klass_metaclass_clone);
        }

        // initialize method table before any GC chance
        class_initialize_method_table(clone);

        rb_class_set_super(clone, RCLASS_SUPER(klass));
        rb_fields_tbl_copy(clone, klass);
        if (RCLASS_CONST_TBL(klass)) {
            struct clone_const_arg arg;
            struct rb_id_table *table;
            arg.tbl = table = rb_id_table_create(0);
            arg.klass = clone;
            rb_id_table_foreach(RCLASS_CONST_TBL(klass), clone_const_i, &arg);
            RCLASS_SET_CONST_TBL(clone, table, false);
        }
        if (!UNDEF_P(attach)) {
            rb_singleton_class_attached(clone, attach);
        }
        {
            struct clone_method_arg arg;
            arg.old_klass = klass;
            arg.new_klass = clone;
            rb_id_table_foreach(RCLASS_M_TBL(klass), clone_method_i, &arg);
        }
        if (klass_of_clone_is_new) {
            rb_singleton_class_attached(METACLASS_OF(clone), clone);
        }
        FL_SET(clone, FL_SINGLETON);

        return clone;
    }
}

void
rb_singleton_class_attached(VALUE klass, VALUE obj)
{
    if (RCLASS_SINGLETON_P(klass)) {
        RCLASS_SET_ATTACHED_OBJECT(klass, obj);
    }
}

/*!
 * whether k is a meta^(n)-class of Class class
 * @retval 1 if \a k is a meta^(n)-class of Class class (n >= 0)
 * @retval 0 otherwise
 */
#define META_CLASS_OF_CLASS_CLASS_P(k)  (METACLASS_OF(k) == (k))

static int
rb_singleton_class_has_metaclass_p(VALUE sklass)
{
    return RCLASS_ATTACHED_OBJECT(METACLASS_OF(sklass)) == sklass;
}

int
rb_singleton_class_internal_p(VALUE sklass)
{
    return (RB_TYPE_P(RCLASS_ATTACHED_OBJECT(sklass), T_CLASS) &&
            !rb_singleton_class_has_metaclass_p(sklass));
}

/**
 * whether k has a metaclass
 * @retval 1 if \a k has a metaclass
 * @retval 0 otherwise
 */
#define HAVE_METACLASS_P(k) \
    (FL_TEST(METACLASS_OF(k), FL_SINGLETON) && \
     rb_singleton_class_has_metaclass_p(k))

/**
 * ensures `klass` belongs to its own eigenclass.
 * @return the eigenclass of `klass`
 * @post `klass` belongs to the returned eigenclass.
 *       i.e. the attached object of the eigenclass is `klass`.
 * @note this macro creates a new eigenclass if necessary.
 */
#define ENSURE_EIGENCLASS(klass) \
    (HAVE_METACLASS_P(klass) ? METACLASS_OF(klass) : make_metaclass(klass))


/**
 * Creates a metaclass of `klass`
 * @param klass     a class
 * @return          created metaclass for the class
 * @pre `klass` is a Class object
 * @pre `klass` has no singleton class.
 * @post the class of `klass` is the returned class.
 * @post the returned class is meta^(n+1)-class when `klass` is a meta^(n)-klass for n >= 0
 */
static inline VALUE
make_metaclass(VALUE klass)
{
    VALUE super;
    VALUE metaclass = rb_class_boot(Qundef);

    FL_SET(metaclass, FL_SINGLETON);
    rb_singleton_class_attached(metaclass, klass);

    if (META_CLASS_OF_CLASS_CLASS_P(klass)) {
        SET_METACLASS_OF(klass, metaclass);
        SET_METACLASS_OF(metaclass, metaclass);
    }
    else {
        VALUE tmp = METACLASS_OF(klass); /* for a meta^(n)-class klass, tmp is meta^(n)-class of Class class */
        SET_METACLASS_OF(klass, metaclass);
        SET_METACLASS_OF(metaclass, ENSURE_EIGENCLASS(tmp));
    }

    super = RCLASS_SUPER(klass);
    while (RB_TYPE_P(super, T_ICLASS)) super = RCLASS_SUPER(super);
    class_associate_super(metaclass, super ? ENSURE_EIGENCLASS(super) : rb_cClass, true);
    rb_class_set_initialized(klass);

    // Full class ancestry may not have been filled until we reach here.
    rb_class_update_superclasses(METACLASS_OF(metaclass));

    return metaclass;
}

/**
 * Creates a singleton class for `obj`.
 * @pre `obj` must not be an immediate nor a special const.
 * @pre `obj` must not be a Class object.
 * @pre `obj` has no singleton class.
 */
static inline VALUE
make_singleton_class(VALUE obj)
{
    VALUE orig_class = METACLASS_OF(obj);
    VALUE klass = rb_class_boot(orig_class);

    FL_SET(klass, FL_SINGLETON);
    RBASIC_SET_CLASS(obj, klass);
    rb_singleton_class_attached(klass, obj);
    rb_yjit_invalidate_no_singleton_class(orig_class);

    SET_METACLASS_OF(klass, METACLASS_OF(rb_class_real(orig_class)));
    return klass;
}


static VALUE
boot_defclass(const char *name, VALUE super)
{
    VALUE obj = rb_class_boot(super);
    ID id = rb_intern(name);

    rb_const_set((rb_cObject ? rb_cObject : obj), id, obj);
    rb_vm_register_global_object(obj);
    return obj;
}

/***********************************************************************
 *
 * Document-class: Refinement
 *
 *  Refinement is a class of the +self+ (current context) inside +refine+
 *  statement. It allows to import methods from other modules, see #import_methods.
 */

#if 0 /* for RDoc */
/*
 * Document-method: Refinement#import_methods
 *
 *  call-seq:
 *     import_methods(module, ...)    -> self
 *
 *  Imports methods from modules. Unlike Module#include,
 *  Refinement#import_methods copies methods and adds them into the refinement,
 *  so the refinement is activated in the imported methods.
 *
 *  Note that due to method copying, only methods defined in Ruby code can be imported.
 *
 *     module StrUtils
 *       def indent(level)
 *         ' ' * level + self
 *       end
 *     end
 *
 *     module M
 *       refine String do
 *         import_methods StrUtils
 *       end
 *     end
 *
 *     using M
 *     "foo".indent(3)
 *     #=> "   foo"
 *
 *     module M
 *       refine String do
 *         import_methods Enumerable
 *         # Can't import method which is not defined with Ruby code: Enumerable#drop
 *       end
 *     end
 *
 */

static VALUE
refinement_import_methods(int argc, VALUE *argv, VALUE refinement)
{
}
# endif

/*!
 *--
 * \private
 * Initializes the world of objects and classes.
 *
 * At first, the function bootstraps the class hierarchy.
 * It initializes the most fundamental classes and their metaclasses.
 * - \c BasicObject
 * - \c Object
 * - \c Module
 * - \c Class
 * After the bootstrap step, the class hierarchy becomes as the following
 * diagram.
 *
 * \image html boottime-classes.png
 *
 * Then, the function defines classes, modules and methods as usual.
 * \ingroup class
 *++
 */

void
Init_class_hierarchy(void)
{
    rb_cBasicObject = boot_defclass("BasicObject", 0);
    rb_cObject = boot_defclass("Object", rb_cBasicObject);
    rb_vm_register_global_object(rb_cObject);

    /* resolve class name ASAP for order-independence */
    rb_set_class_path_string(rb_cObject, rb_cObject, rb_fstring_lit("Object"));

    rb_cModule = boot_defclass("Module", rb_cObject);
    rb_cClass =  boot_defclass("Class",  rb_cModule);
    rb_cRefinement =  boot_defclass("Refinement",  rb_cModule);

#if 0 /* for RDoc */
    // we pretend it to be public, otherwise RDoc will ignore it
    rb_define_method(rb_cRefinement, "import_methods", refinement_import_methods, -1);
#endif

    rb_const_set(rb_cObject, rb_intern_const("BasicObject"), rb_cBasicObject);
    RBASIC_SET_CLASS(rb_cClass, rb_cClass);
    RBASIC_SET_CLASS(rb_cModule, rb_cClass);
    RBASIC_SET_CLASS(rb_cObject, rb_cClass);
    RBASIC_SET_CLASS(rb_cRefinement, rb_cClass);
    RBASIC_SET_CLASS(rb_cBasicObject, rb_cClass);

    ENSURE_EIGENCLASS(rb_cRefinement);
}


/**
 * @internal
 * Creates a new *singleton class* for an object.
 *
 * @pre `obj` has no singleton class.
 * @note DO NOT USE the function in an extension libraries. Use @ref rb_singleton_class.
 * @param obj     An object.
 * @param unused  ignored.
 * @return        The singleton class of the object.
 */
VALUE
rb_make_metaclass(VALUE obj, VALUE unused)
{
    if (BUILTIN_TYPE(obj) == T_CLASS) {
        return make_metaclass(obj);
    }
    else {
        return make_singleton_class(obj);
    }
}

VALUE
rb_define_class_id(ID id, VALUE super)
{
    VALUE klass;

    if (!super) super = rb_cObject;
    klass = rb_class_new(super);
    rb_make_metaclass(klass, METACLASS_OF(super));

    return klass;
}


/**
 * Calls Class#inherited.
 * @param super  A class which will be called #inherited.
 *               NULL means Object class.
 * @param klass  A Class object which derived from `super`
 * @return the value `Class#inherited` returns
 * @pre Each of `super` and `klass` must be a `Class` object.
 */
VALUE
rb_class_inherited(VALUE super, VALUE klass)
{
    ID inherited;
    if (!super) super = rb_cObject;
    CONST_ID(inherited, "inherited");
    return rb_funcall(super, inherited, 1, klass);
}

VALUE
rb_define_class(const char *name, VALUE super)
{
    VALUE klass;
    ID id;
    const rb_namespace_t *ns = rb_current_namespace();

    id = rb_intern(name);
    if (NAMESPACE_OPTIONAL_P(ns)) {
        return rb_define_class_id_under(ns->ns_object, id, super);
    }
    if (rb_const_defined(rb_cObject, id)) {
        klass = rb_const_get(rb_cObject, id);
        if (!RB_TYPE_P(klass, T_CLASS)) {
            rb_raise(rb_eTypeError, "%s is not a class (%"PRIsVALUE")",
                     name, rb_obj_class(klass));
        }
        if (rb_class_real(RCLASS_SUPER(klass)) != super) {
            rb_raise(rb_eTypeError, "superclass mismatch for class %s", name);
        }

        /* Class may have been defined in Ruby and not pin-rooted */
        rb_vm_register_global_object(klass);
        return klass;
    }
    if (!super) {
        rb_raise(rb_eArgError, "no super class for '%s'", name);
    }
    klass = rb_define_class_id(id, super);
    rb_vm_register_global_object(klass);
    rb_const_set(rb_cObject, id, klass);
    rb_class_inherited(super, klass);

    return klass;
}

VALUE
rb_define_class_under(VALUE outer, const char *name, VALUE super)
{
    return rb_define_class_id_under(outer, rb_intern(name), super);
}

VALUE
rb_define_class_id_under_no_pin(VALUE outer, ID id, VALUE super)
{
    VALUE klass;

    if (rb_const_defined_at(outer, id)) {
        klass = rb_const_get_at(outer, id);
        if (!RB_TYPE_P(klass, T_CLASS)) {
            rb_raise(rb_eTypeError, "%"PRIsVALUE"::%"PRIsVALUE" is not a class"
                     " (%"PRIsVALUE")",
                     outer, rb_id2str(id), rb_obj_class(klass));
        }
        if (rb_class_real(RCLASS_SUPER(klass)) != super) {
            rb_raise(rb_eTypeError, "superclass mismatch for class "
                     "%"PRIsVALUE"::%"PRIsVALUE""
                     " (%"PRIsVALUE" is given but was %"PRIsVALUE")",
                     outer, rb_id2str(id), RCLASS_SUPER(klass), super);
        }

        return klass;
    }
    if (!super) {
        rb_raise(rb_eArgError, "no super class for '%"PRIsVALUE"::%"PRIsVALUE"'",
                 rb_class_path(outer), rb_id2str(id));
    }
    klass = rb_define_class_id(id, super);
    rb_set_class_path_string(klass, outer, rb_id2str(id));
    rb_const_set(outer, id, klass);
    rb_class_inherited(super, klass);

    return klass;
}

VALUE
rb_define_class_id_under(VALUE outer, ID id, VALUE super)
{
    VALUE klass = rb_define_class_id_under_no_pin(outer, id, super);
    rb_vm_register_global_object(klass);
    return klass;
}

VALUE
rb_module_s_alloc(VALUE klass)
{
    VALUE mod = class_alloc(T_MODULE, klass);
    class_initialize_method_table(mod);
    return mod;
}

static inline VALUE
module_new(VALUE klass)
{
    VALUE mdl = class_alloc(T_MODULE, klass);
    class_initialize_method_table(mdl);
    return (VALUE)mdl;
}

VALUE
rb_module_new(void)
{
    return module_new(rb_cModule);
}

VALUE
rb_refinement_new(void)
{
    return module_new(rb_cRefinement);
}

// Kept for compatibility. Use rb_module_new() instead.
VALUE
rb_define_module_id(ID id)
{
    return rb_module_new();
}

VALUE
rb_define_module(const char *name)
{
    VALUE module;
    ID id;
    const rb_namespace_t *ns = rb_current_namespace();

    id = rb_intern(name);
    if (NAMESPACE_OPTIONAL_P(ns)) {
        return rb_define_module_id_under(ns->ns_object, id);
    }
    if (rb_const_defined(rb_cObject, id)) {
        module = rb_const_get(rb_cObject, id);
        if (!RB_TYPE_P(module, T_MODULE)) {
            rb_raise(rb_eTypeError, "%s is not a module (%"PRIsVALUE")",
                     name, rb_obj_class(module));
        }
        /* Module may have been defined in Ruby and not pin-rooted */
        rb_vm_register_global_object(module);
        return module;
    }
    module = rb_module_new();
    rb_vm_register_global_object(module);
    rb_const_set(rb_cObject, id, module);

    return module;
}

VALUE
rb_define_module_under(VALUE outer, const char *name)
{
    return rb_define_module_id_under(outer, rb_intern(name));
}

VALUE
rb_define_module_id_under(VALUE outer, ID id)
{
    VALUE module;

    if (rb_const_defined_at(outer, id)) {
        module = rb_const_get_at(outer, id);
        if (!RB_TYPE_P(module, T_MODULE)) {
            rb_raise(rb_eTypeError, "%"PRIsVALUE"::%"PRIsVALUE" is not a module"
                     " (%"PRIsVALUE")",
                     outer, rb_id2str(id), rb_obj_class(module));
        }
        /* Module may have been defined in Ruby and not pin-rooted */
        rb_vm_register_global_object(module);
        return module;
    }
    module = rb_module_new();
    rb_const_set(outer, id, module);
    rb_set_class_path_string(module, outer, rb_id2str(id));
    rb_vm_register_global_object(module);

    return module;
}

VALUE
rb_include_class_new(VALUE module, VALUE super)
{
    VALUE klass = class_alloc(T_ICLASS, rb_cClass);

    RCLASS_SET_M_TBL(klass, RCLASS_WRITABLE_M_TBL(module));

    RCLASS_SET_ORIGIN(klass, klass);
    if (BUILTIN_TYPE(module) == T_ICLASS) {
        module = METACLASS_OF(module);
    }
    RUBY_ASSERT(!RB_TYPE_P(module, T_ICLASS));
    if (RCLASS_WRITABLE_CONST_TBL(module)) {
        RCLASS_SET_CONST_TBL(klass, RCLASS_WRITABLE_CONST_TBL(module), true);
    }
    else {
        RCLASS_WRITE_CONST_TBL(module, rb_id_table_create(0), false);
        RCLASS_SET_CONST_TBL(klass, RCLASS_WRITABLE_CONST_TBL(module), true);
    }

    RCLASS_SET_CVC_TBL(klass, RCLASS_WRITABLE_CVC_TBL(module));

    class_associate_super(klass, super, true);
    RBASIC_SET_CLASS(klass, module);

    return (VALUE)klass;
}

static int include_modules_at(const VALUE klass, VALUE c, VALUE module, int search_super);

static void
ensure_includable(VALUE klass, VALUE module)
{
    rb_class_modify_check(klass);
    Check_Type(module, T_MODULE);
    rb_class_set_initialized(module);
    if (!NIL_P(rb_refinement_module_get_refined_class(module))) {
        rb_raise(rb_eArgError, "refinement module is not allowed");
    }
}

void
rb_include_module(VALUE klass, VALUE module)
{
    int changed = 0;

    ensure_includable(klass, module);

    changed = include_modules_at(klass, RCLASS_ORIGIN(klass), module, TRUE);
    if (changed < 0)
        rb_raise(rb_eArgError, "cyclic include detected");

    if (RB_TYPE_P(klass, T_MODULE)) {
        rb_subclass_entry_t *iclass = RCLASS_SUBCLASSES_FIRST(klass);
        while (iclass) {
            int do_include = 1;
            VALUE check_class = iclass->klass;
            /* During lazy sweeping, iclass->klass could be a dead object that
             * has not yet been swept. */
            if (!rb_objspace_garbage_object_p(check_class)) {
                while (check_class) {
                    RUBY_ASSERT(!rb_objspace_garbage_object_p(check_class));

                    if (RB_TYPE_P(check_class, T_ICLASS) &&
                            (METACLASS_OF(check_class) == module)) {
                        do_include = 0;
                    }
                    check_class = RCLASS_SUPER(check_class);
                }

                if (do_include) {
                    include_modules_at(iclass->klass, RCLASS_ORIGIN(iclass->klass), module, TRUE);
                }
            }

            iclass = iclass->next;
        }
    }
}

static enum rb_id_table_iterator_result
add_refined_method_entry_i(ID key, VALUE value, void *data)
{
    rb_add_refined_method_entry((VALUE)data, key);
    return ID_TABLE_CONTINUE;
}

static enum rb_id_table_iterator_result
clear_module_cache_i(ID id, VALUE val, void *data)
{
    VALUE klass = (VALUE)data;
    rb_clear_method_cache(klass, id);
    return ID_TABLE_CONTINUE;
}

static bool
module_in_super_chain(const VALUE klass, VALUE module)
{
    struct rb_id_table *const klass_m_tbl = RCLASS_M_TBL(RCLASS_ORIGIN(klass));
    if (klass_m_tbl) {
        while (module) {
            if (klass_m_tbl == RCLASS_M_TBL(module))
                return true;
            module = RCLASS_SUPER(module);
        }
    }
    return false;
}

// For each ID key in the class constant table, we're going to clear the VM's
// inline constant caches associated with it.
static enum rb_id_table_iterator_result
clear_constant_cache_i(ID id, VALUE value, void *data)
{
    rb_clear_constant_cache_for_id(id);
    return ID_TABLE_CONTINUE;
}

static int
do_include_modules_at(const VALUE klass, VALUE c, VALUE module, int search_super, bool check_cyclic)
{
    VALUE p, iclass, origin_stack = 0;
    int method_changed = 0;
    long origin_len;
    VALUE klass_origin = RCLASS_ORIGIN(klass);
    VALUE original_klass = klass;

    if (check_cyclic && module_in_super_chain(klass, module))
        return -1;

    while (module) {
        int c_seen = FALSE;
        int superclass_seen = FALSE;
        struct rb_id_table *tbl;

        if (klass == c) {
            c_seen = TRUE;
        }
        if (klass_origin != c || search_super) {
            /* ignore if the module included already in superclasses for include,
             * ignore if the module included before origin class for prepend
             */
            for (p = RCLASS_SUPER(klass); p; p = RCLASS_SUPER(p)) {
                int type = BUILTIN_TYPE(p);
                if (klass_origin == p && !search_super)
                    break;
                if (c == p)
                    c_seen = TRUE;
                if (type == T_ICLASS) {
                    if (RCLASS_M_TBL(p) == RCLASS_M_TBL(module)) {
                        if (!superclass_seen && c_seen) {
                            c = p;  /* move insertion point */
                        }
                        goto skip;
                    }
                }
                else if (type == T_CLASS) {
                    superclass_seen = TRUE;
                }
            }
        }

        VALUE super_class = RCLASS_SUPER(c);

        // invalidate inline method cache
        RB_DEBUG_COUNTER_INC(cvar_include_invalidate);
        ruby_vm_global_cvar_state++;
        tbl = RCLASS_M_TBL(module);
        if (tbl && rb_id_table_size(tbl)) {
            if (search_super) { // include
                if (super_class && !RB_TYPE_P(super_class, T_MODULE)) {
                    rb_id_table_foreach(tbl, clear_module_cache_i, (void *)super_class);
                }
            }
            else { // prepend
                if (!RB_TYPE_P(original_klass, T_MODULE)) {
                    rb_id_table_foreach(tbl, clear_module_cache_i, (void *)original_klass);
                }
            }
            method_changed = 1;
        }

        // setup T_ICLASS for the include/prepend module
        iclass = rb_include_class_new(module, super_class);
        c = rb_class_set_super(c, iclass);
        RCLASS_SET_INCLUDER(iclass, klass);
        if (module != RCLASS_ORIGIN(module)) {
            if (!origin_stack) origin_stack = rb_ary_hidden_new(2);
            VALUE origin[2] = {iclass, RCLASS_ORIGIN(module)};
            rb_ary_cat(origin_stack, origin, 2);
        }
        else if (origin_stack && (origin_len = RARRAY_LEN(origin_stack)) > 1 &&
                 RARRAY_AREF(origin_stack, origin_len - 1) == module) {
            RCLASS_WRITE_ORIGIN(RARRAY_AREF(origin_stack, (origin_len -= 2)), iclass);
            RICLASS_WRITE_ORIGIN_SHARED_MTBL(iclass);
            rb_ary_resize(origin_stack, origin_len);
        }

        VALUE m = module;
        if (BUILTIN_TYPE(m) == T_ICLASS) m = METACLASS_OF(m);
        rb_module_add_to_subclasses_list(m, iclass);

        if (BUILTIN_TYPE(klass) == T_MODULE && FL_TEST(klass, RMODULE_IS_REFINEMENT)) {
            VALUE refined_class =
                rb_refinement_module_get_refined_class(klass);

            rb_id_table_foreach(RCLASS_M_TBL(module), add_refined_method_entry_i, (void *)refined_class);
            RUBY_ASSERT(BUILTIN_TYPE(c) == T_MODULE);
        }

        tbl = RCLASS_CONST_TBL(module);
        if (tbl && rb_id_table_size(tbl))
            rb_id_table_foreach(tbl, clear_constant_cache_i, NULL);
      skip:
        module = RCLASS_SUPER(module);
    }

    return method_changed;
}

static int
include_modules_at(const VALUE klass, VALUE c, VALUE module, int search_super)
{
    return do_include_modules_at(klass, c, module, search_super, true);
}

static enum rb_id_table_iterator_result
move_refined_method(ID key, VALUE value, void *data)
{
    rb_method_entry_t *me = (rb_method_entry_t *)value;

    if (me->def->type == VM_METHOD_TYPE_REFINED) {
        VALUE klass = (VALUE)data;
        struct rb_id_table *tbl = RCLASS_WRITABLE_M_TBL(klass);

        if (me->def->body.refined.orig_me) {
            const rb_method_entry_t *orig_me = me->def->body.refined.orig_me, *new_me;
            RB_OBJ_WRITE(me, &me->def->body.refined.orig_me, NULL);
            new_me = rb_method_entry_clone(me);
            rb_method_table_insert(klass, tbl, key, new_me);
            rb_method_entry_copy(me, orig_me);
            return ID_TABLE_CONTINUE;
        }
        else {
            rb_method_table_insert(klass, tbl, key, me);
            return ID_TABLE_DELETE;
        }
    }
    else {
        return ID_TABLE_CONTINUE;
    }
}

static enum rb_id_table_iterator_result
cache_clear_refined_method(ID key, VALUE value, void *data)
{
    rb_method_entry_t *me = (rb_method_entry_t *) value;

    if (me->def->type == VM_METHOD_TYPE_REFINED && me->def->body.refined.orig_me) {
        VALUE klass = (VALUE)data;
        rb_clear_method_cache(klass, me->called_id);
    }
    // Refined method entries without an orig_me is going to stay in the method
    // table of klass, like before the move, so no need to clear the cache.

    return ID_TABLE_CONTINUE;
}

static bool
ensure_origin(VALUE klass)
{
    VALUE origin = RCLASS_ORIGIN(klass);
    if (origin == klass) {
        origin = class_alloc(T_ICLASS, klass);
        RCLASS_SET_M_TBL(origin, RCLASS_M_TBL(klass));
        rb_class_set_super(origin, RCLASS_SUPER(klass));
        rb_class_set_super(klass, origin); // writes origin into RCLASS_SUPER(klass)
        RCLASS_WRITE_ORIGIN(klass, origin);
        class_clear_method_table(klass);
        rb_id_table_foreach(RCLASS_M_TBL(origin), cache_clear_refined_method, (void *)klass);
        rb_id_table_foreach(RCLASS_M_TBL(origin), move_refined_method, (void *)klass);
        return true;
    }
    return false;
}

void
rb_prepend_module(VALUE klass, VALUE module)
{
    int changed;
    bool klass_had_no_origin;

    ensure_includable(klass, module);
    if (module_in_super_chain(klass, module))
        rb_raise(rb_eArgError, "cyclic prepend detected");

    klass_had_no_origin = ensure_origin(klass);
    changed = do_include_modules_at(klass, klass, module, FALSE, false);
    RUBY_ASSERT(changed >= 0); // already checked for cyclic prepend above
    if (changed) {
        rb_vm_check_redefinition_by_prepend(klass);
    }
    if (RB_TYPE_P(klass, T_MODULE)) {
        rb_subclass_entry_t *iclass = RCLASS_SUBCLASSES_FIRST(klass);
        VALUE klass_origin = RCLASS_ORIGIN(klass);
        struct rb_id_table *klass_m_tbl = RCLASS_M_TBL(klass);
        struct rb_id_table *klass_origin_m_tbl = RCLASS_M_TBL(klass_origin);
        while (iclass) {
            /* During lazy sweeping, iclass->klass could be a dead object that
             * has not yet been swept. */
            if (!rb_objspace_garbage_object_p(iclass->klass)) {
                const VALUE subclass = iclass->klass;
                if (klass_had_no_origin && klass_origin_m_tbl == RCLASS_M_TBL(subclass)) {
                    // backfill an origin iclass to handle refinements and future prepends
                    rb_id_table_foreach(RCLASS_M_TBL(subclass), clear_module_cache_i, (void *)subclass);
                    RCLASS_WRITE_M_TBL_EVEN_WHEN_PROMOTED(subclass, klass_m_tbl);
                    VALUE origin = rb_include_class_new(klass_origin, RCLASS_SUPER(subclass));
                    rb_class_set_super(subclass, origin);
                    RCLASS_SET_INCLUDER(origin, RCLASS_INCLUDER(subclass));
                    RCLASS_WRITE_ORIGIN(subclass, origin);
                    RICLASS_SET_ORIGIN_SHARED_MTBL(origin);
                }
                include_modules_at(subclass, subclass, module, FALSE);
            }

            iclass = iclass->next;
        }
    }
}

/*
 *  call-seq:
 *     mod.included_modules -> array
 *
 *  Returns the list of modules included or prepended in <i>mod</i>
 *  or one of <i>mod</i>'s ancestors.
 *
 *     module Sub
 *     end
 *
 *     module Mixin
 *       prepend Sub
 *     end
 *
 *     module Outer
 *       include Mixin
 *     end
 *
 *     Mixin.included_modules   #=> [Sub]
 *     Outer.included_modules   #=> [Sub, Mixin]
 */

VALUE
rb_mod_included_modules(VALUE mod)
{
    VALUE ary = rb_ary_new();
    VALUE p;
    VALUE origin = RCLASS_ORIGIN(mod);

    for (p = RCLASS_SUPER(mod); p; p = RCLASS_SUPER(p)) {
        if (p != origin && RCLASS_ORIGIN(p) == p && BUILTIN_TYPE(p) == T_ICLASS) {
            VALUE m = METACLASS_OF(p);
            if (RB_TYPE_P(m, T_MODULE))
                rb_ary_push(ary, m);
        }
    }
    return ary;
}

/*
 *  call-seq:
 *     mod.include?(module)    -> true or false
 *
 *  Returns <code>true</code> if <i>module</i> is included
 *  or prepended in <i>mod</i> or one of <i>mod</i>'s ancestors.
 *
 *     module A
 *     end
 *     class B
 *       include A
 *     end
 *     class C < B
 *     end
 *     B.include?(A)   #=> true
 *     C.include?(A)   #=> true
 *     A.include?(A)   #=> false
 */

VALUE
rb_mod_include_p(VALUE mod, VALUE mod2)
{
    VALUE p;

    Check_Type(mod2, T_MODULE);
    for (p = RCLASS_SUPER(mod); p; p = RCLASS_SUPER(p)) {
        if (BUILTIN_TYPE(p) == T_ICLASS && !RICLASS_IS_ORIGIN_P(p)) {
            if (METACLASS_OF(p) == mod2) return Qtrue;
        }
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.ancestors -> array
 *
 *  Returns a list of modules included/prepended in <i>mod</i>
 *  (including <i>mod</i> itself).
 *
 *     module Mod
 *       include Math
 *       include Comparable
 *       prepend Enumerable
 *     end
 *
 *     Mod.ancestors        #=> [Enumerable, Mod, Comparable, Math]
 *     Math.ancestors       #=> [Math]
 *     Enumerable.ancestors #=> [Enumerable]
 */

VALUE
rb_mod_ancestors(VALUE mod)
{
    VALUE p, ary = rb_ary_new();
    VALUE refined_class = Qnil;
    if (BUILTIN_TYPE(mod) == T_MODULE && FL_TEST(mod, RMODULE_IS_REFINEMENT)) {
        refined_class = rb_refinement_module_get_refined_class(mod);
    }

    for (p = mod; p; p = RCLASS_SUPER(p)) {
        if (p == refined_class) break;
        if (p != RCLASS_ORIGIN(p)) continue;
        if (BUILTIN_TYPE(p) == T_ICLASS) {
            rb_ary_push(ary, METACLASS_OF(p));
        }
        else {
            rb_ary_push(ary, p);
        }
    }
    return ary;
}

struct subclass_traverse_data
{
    VALUE buffer;
    long count;
    long maxcount;
    bool immediate_only;
};

static void
class_descendants_recursive(VALUE klass, VALUE v)
{
    struct subclass_traverse_data *data = (struct subclass_traverse_data *) v;

    if (BUILTIN_TYPE(klass) == T_CLASS && !RCLASS_SINGLETON_P(klass)) {
        if (data->buffer && data->count < data->maxcount && !rb_objspace_garbage_object_p(klass)) {
            // assumes that this does not cause GC as long as the length does not exceed the capacity
            rb_ary_push(data->buffer, klass);
        }
        data->count++;
        if (!data->immediate_only) {
            rb_class_foreach_subclass(klass, class_descendants_recursive, v);
        }
    }
    else {
        rb_class_foreach_subclass(klass, class_descendants_recursive, v);
    }
}

static VALUE
class_descendants(VALUE klass, bool immediate_only)
{
    struct subclass_traverse_data data = { Qfalse, 0, -1, immediate_only };

    // estimate the count of subclasses
    rb_class_foreach_subclass(klass, class_descendants_recursive, (VALUE) &data);

    // the following allocation may cause GC which may change the number of subclasses
    data.buffer = rb_ary_new_capa(data.count);
    data.maxcount = data.count;
    data.count = 0;

    size_t gc_count = rb_gc_count();

    // enumerate subclasses
    rb_class_foreach_subclass(klass, class_descendants_recursive, (VALUE) &data);

    if (gc_count != rb_gc_count()) {
        rb_bug("GC must not occur during the subclass iteration of Class#descendants");
    }

    return data.buffer;
}

/*
 *  call-seq:
 *     subclasses -> array
 *
 *  Returns an array of classes where the receiver is the
 *  direct superclass of the class, excluding singleton classes.
 *  The order of the returned array is not defined.
 *
 *     class A; end
 *     class B < A; end
 *     class C < B; end
 *     class D < A; end
 *
 *     A.subclasses        #=> [D, B]
 *     B.subclasses        #=> [C]
 *     C.subclasses        #=> []
 *
 *  Anonymous subclasses (not associated with a constant) are
 *  returned, too:
 *
 *     c = Class.new(A)
 *     A.subclasses        # => [#<Class:0x00007f003c77bd78>, D, B]
 *
 *  Note that the parent does not hold references to subclasses
 *  and doesn't prevent them from being garbage collected. This
 *  means that the subclass might disappear when all references
 *  to it are dropped:
 *
 *     # drop the reference to subclass, it can be garbage-collected now
 *     c = nil
 *
 *     A.subclasses
 *     # It can be
 *     #  => [#<Class:0x00007f003c77bd78>, D, B]
 *     # ...or just
 *     #  => [D, B]
 *     # ...depending on whether garbage collector was run
 */

VALUE
rb_class_subclasses(VALUE klass)
{
    return class_descendants(klass, true);
}

/*
 *  call-seq:
 *     attached_object -> object
 *
 *  Returns the object for which the receiver is the singleton class.
 *
 *  Raises an TypeError if the class is not a singleton class.
 *
 *     class Foo; end
 *
 *     Foo.singleton_class.attached_object        #=> Foo
 *     Foo.attached_object                        #=> TypeError: `Foo' is not a singleton class
 *     Foo.new.singleton_class.attached_object    #=> #<Foo:0x000000010491a370>
 *     TrueClass.attached_object                  #=> TypeError: `TrueClass' is not a singleton class
 *     NilClass.attached_object                   #=> TypeError: `NilClass' is not a singleton class
 */

VALUE
rb_class_attached_object(VALUE klass)
{
    if (!RCLASS_SINGLETON_P(klass)) {
        rb_raise(rb_eTypeError, "'%"PRIsVALUE"' is not a singleton class", klass);
    }

    return RCLASS_ATTACHED_OBJECT(klass);
}

static void
ins_methods_push(st_data_t name, st_data_t ary)
{
    rb_ary_push((VALUE)ary, ID2SYM((ID)name));
}

static int
ins_methods_i(st_data_t name, st_data_t type, st_data_t ary)
{
    switch ((rb_method_visibility_t)type) {
      case METHOD_VISI_UNDEF:
      case METHOD_VISI_PRIVATE:
        break;
      default: /* everything but private */
        ins_methods_push(name, ary);
        break;
    }
    return ST_CONTINUE;
}

static int
ins_methods_type_i(st_data_t name, st_data_t type, st_data_t ary, rb_method_visibility_t visi)
{
    if ((rb_method_visibility_t)type == visi) {
        ins_methods_push(name, ary);
    }
    return ST_CONTINUE;
}

static int
ins_methods_prot_i(st_data_t name, st_data_t type, st_data_t ary)
{
    return ins_methods_type_i(name, type, ary, METHOD_VISI_PROTECTED);
}

static int
ins_methods_priv_i(st_data_t name, st_data_t type, st_data_t ary)
{
    return ins_methods_type_i(name, type, ary, METHOD_VISI_PRIVATE);
}

static int
ins_methods_pub_i(st_data_t name, st_data_t type, st_data_t ary)
{
    return ins_methods_type_i(name, type, ary, METHOD_VISI_PUBLIC);
}

static int
ins_methods_undef_i(st_data_t name, st_data_t type, st_data_t ary)
{
    return ins_methods_type_i(name, type, ary, METHOD_VISI_UNDEF);
}

struct method_entry_arg {
    st_table *list;
    int recur;
};

static enum rb_id_table_iterator_result
method_entry_i(ID key, VALUE value, void *data)
{
    const rb_method_entry_t *me = (const rb_method_entry_t *)value;
    struct method_entry_arg *arg = (struct method_entry_arg *)data;
    rb_method_visibility_t type;

    if (me->def->type == VM_METHOD_TYPE_REFINED) {
        VALUE owner = me->owner;
        me = rb_resolve_refined_method(Qnil, me);
        if (!me) return ID_TABLE_CONTINUE;
        if (!arg->recur && me->owner != owner) return ID_TABLE_CONTINUE;
    }
    if (!st_is_member(arg->list, key)) {
        if (UNDEFINED_METHOD_ENTRY_P(me)) {
            type = METHOD_VISI_UNDEF; /* none */
        }
        else {
            type = METHOD_ENTRY_VISI(me);
            RUBY_ASSERT(type != METHOD_VISI_UNDEF);
        }
        st_add_direct(arg->list, key, (st_data_t)type);
    }
    return ID_TABLE_CONTINUE;
}

static void
add_instance_method_list(VALUE mod, struct method_entry_arg *me_arg)
{
    struct rb_id_table *m_tbl = RCLASS_M_TBL(mod);
    if (!m_tbl) return;
    rb_id_table_foreach(m_tbl, method_entry_i, me_arg);
}

static bool
particular_class_p(VALUE mod)
{
    if (!mod) return false;
    if (RCLASS_SINGLETON_P(mod)) return true;
    if (BUILTIN_TYPE(mod) == T_ICLASS) return true;
    return false;
}

static VALUE
class_instance_method_list(int argc, const VALUE *argv, VALUE mod, int obj, int (*func) (st_data_t, st_data_t, st_data_t))
{
    VALUE ary;
    int recur = TRUE, prepended = 0;
    struct method_entry_arg me_arg;

    if (rb_check_arity(argc, 0, 1)) recur = RTEST(argv[0]);

    me_arg.list = st_init_numtable();
    me_arg.recur = recur;

    if (obj) {
        for (; particular_class_p(mod); mod = RCLASS_SUPER(mod)) {
            add_instance_method_list(mod, &me_arg);
        }
    }

    if (!recur && RCLASS_ORIGIN(mod) != mod) {
        mod = RCLASS_ORIGIN(mod);
        prepended = 1;
    }

    for (; mod; mod = RCLASS_SUPER(mod)) {
        add_instance_method_list(mod, &me_arg);
        if (BUILTIN_TYPE(mod) == T_ICLASS && !prepended) continue;
        if (!recur) break;
    }
    ary = rb_ary_new2(me_arg.list->num_entries);
    st_foreach(me_arg.list, func, ary);
    st_free_table(me_arg.list);

    return ary;
}

/*
 *  call-seq:
 *     mod.instance_methods(include_super=true)   -> array
 *
 *  Returns an array containing the names of the public and protected instance
 *  methods in the receiver. For a module, these are the public and protected methods;
 *  for a class, they are the instance (not singleton) methods. If the optional
 *  parameter is <code>false</code>, the methods of any ancestors are not included.
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       include A
 *       def method2()  end
 *     end
 *     class C < B
 *       def method3()  end
 *     end
 *
 *     A.instance_methods(false)                   #=> [:method1]
 *     B.instance_methods(false)                   #=> [:method2]
 *     B.instance_methods(true).include?(:method1) #=> true
 *     C.instance_methods(false)                   #=> [:method3]
 *     C.instance_methods.include?(:method2)       #=> true
 *
 *  Note that method visibility changes in the current class, as well as aliases,
 *  are considered as methods of the current class by this method:
 *
 *     class C < B
 *       alias method4 method2
 *       protected :method2
 *     end
 *     C.instance_methods(false).sort               #=> [:method2, :method3, :method4]
 */

VALUE
rb_class_instance_methods(int argc, const VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, 0, ins_methods_i);
}

/*
 *  call-seq:
 *     mod.protected_instance_methods(include_super=true)   -> array
 *
 *  Returns a list of the protected instance methods defined in
 *  <i>mod</i>. If the optional parameter is <code>false</code>, the
 *  methods of any ancestors are not included.
 */

VALUE
rb_class_protected_instance_methods(int argc, const VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, 0, ins_methods_prot_i);
}

/*
 *  call-seq:
 *     mod.private_instance_methods(include_super=true)    -> array
 *
 *  Returns a list of the private instance methods defined in
 *  <i>mod</i>. If the optional parameter is <code>false</code>, the
 *  methods of any ancestors are not included.
 *
 *     module Mod
 *       def method1()  end
 *       private :method1
 *       def method2()  end
 *     end
 *     Mod.instance_methods           #=> [:method2]
 *     Mod.private_instance_methods   #=> [:method1]
 */

VALUE
rb_class_private_instance_methods(int argc, const VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, 0, ins_methods_priv_i);
}

/*
 *  call-seq:
 *     mod.public_instance_methods(include_super=true)   -> array
 *
 *  Returns a list of the public instance methods defined in <i>mod</i>.
 *  If the optional parameter is <code>false</code>, the methods of
 *  any ancestors are not included.
 */

VALUE
rb_class_public_instance_methods(int argc, const VALUE *argv, VALUE mod)
{
    return class_instance_method_list(argc, argv, mod, 0, ins_methods_pub_i);
}

/*
 *  call-seq:
 *     mod.undefined_instance_methods   -> array
 *
 *  Returns a list of the undefined instance methods defined in <i>mod</i>.
 *  The undefined methods of any ancestors are not included.
 */

VALUE
rb_class_undefined_instance_methods(VALUE mod)
{
    VALUE include_super = Qfalse;
    return class_instance_method_list(1, &include_super, mod, 0, ins_methods_undef_i);
}

/*
 *  call-seq:
 *     obj.methods(regular=true)    -> array
 *
 *  Returns a list of the names of public and protected methods of
 *  <i>obj</i>. This will include all the methods accessible in
 *  <i>obj</i>'s ancestors.
 *  If the optional parameter is <code>false</code>, it
 *  returns an array of <i>obj</i>'s public and protected singleton methods,
 *  the array will not include methods in modules included in <i>obj</i>.
 *
 *     class Klass
 *       def klass_method()
 *       end
 *     end
 *     k = Klass.new
 *     k.methods[0..9]    #=> [:klass_method, :nil?, :===,
 *                        #    :==~, :!, :eql?
 *                        #    :hash, :<=>, :class, :singleton_class]
 *     k.methods.length   #=> 56
 *
 *     k.methods(false)   #=> []
 *     def k.singleton_method; end
 *     k.methods(false)   #=> [:singleton_method]
 *
 *     module M123; def m123; end end
 *     k.extend M123
 *     k.methods(false)   #=> [:singleton_method]
 */

VALUE
rb_obj_methods(int argc, const VALUE *argv, VALUE obj)
{
    rb_check_arity(argc, 0, 1);
    if (argc > 0 && !RTEST(argv[0])) {
        return rb_obj_singleton_methods(argc, argv, obj);
    }
    return class_instance_method_list(argc, argv, CLASS_OF(obj), 1, ins_methods_i);
}

/*
 *  call-seq:
 *     obj.protected_methods(all=true)   -> array
 *
 *  Returns the list of protected methods accessible to <i>obj</i>. If
 *  the <i>all</i> parameter is set to <code>false</code>, only those methods
 *  in the receiver will be listed.
 */

VALUE
rb_obj_protected_methods(int argc, const VALUE *argv, VALUE obj)
{
    return class_instance_method_list(argc, argv, CLASS_OF(obj), 1, ins_methods_prot_i);
}

/*
 *  call-seq:
 *     obj.private_methods(all=true)   -> array
 *
 *  Returns the list of private methods accessible to <i>obj</i>. If
 *  the <i>all</i> parameter is set to <code>false</code>, only those methods
 *  in the receiver will be listed.
 */

VALUE
rb_obj_private_methods(int argc, const VALUE *argv, VALUE obj)
{
    return class_instance_method_list(argc, argv, CLASS_OF(obj), 1, ins_methods_priv_i);
}

/*
 *  call-seq:
 *     obj.public_methods(all=true)   -> array
 *
 *  Returns the list of public methods accessible to <i>obj</i>. If
 *  the <i>all</i> parameter is set to <code>false</code>, only those methods
 *  in the receiver will be listed.
 */

VALUE
rb_obj_public_methods(int argc, const VALUE *argv, VALUE obj)
{
    return class_instance_method_list(argc, argv, CLASS_OF(obj), 1, ins_methods_pub_i);
}

/*
 *  call-seq:
 *     obj.singleton_methods(all=true)    -> array
 *
 *  Returns an array of the names of singleton methods for <i>obj</i>.
 *  If the optional <i>all</i> parameter is true, the list will include
 *  methods in modules included in <i>obj</i>.
 *  Only public and protected singleton methods are returned.
 *
 *     module Other
 *       def three() end
 *     end
 *
 *     class Single
 *       def Single.four() end
 *     end
 *
 *     a = Single.new
 *
 *     def a.one()
 *     end
 *
 *     class << a
 *       include Other
 *       def two()
 *       end
 *     end
 *
 *     Single.singleton_methods    #=> [:four]
 *     a.singleton_methods(false)  #=> [:two, :one]
 *     a.singleton_methods         #=> [:two, :one, :three]
 */

VALUE
rb_obj_singleton_methods(int argc, const VALUE *argv, VALUE obj)
{
    VALUE ary, klass, origin;
    struct method_entry_arg me_arg;
    struct rb_id_table *mtbl;
    int recur = TRUE;

    if (rb_check_arity(argc, 0, 1)) recur = RTEST(argv[0]);
    if (RCLASS_SINGLETON_P(obj)) {
        rb_singleton_class(obj);
    }
    klass = CLASS_OF(obj);
    origin = RCLASS_ORIGIN(klass);
    me_arg.list = st_init_numtable();
    me_arg.recur = recur;
    if (klass && RCLASS_SINGLETON_P(klass)) {
        if ((mtbl = RCLASS_M_TBL(origin)) != 0) rb_id_table_foreach(mtbl, method_entry_i, &me_arg);
        klass = RCLASS_SUPER(klass);
    }
    if (recur) {
        while (klass && (RCLASS_SINGLETON_P(klass) || RB_TYPE_P(klass, T_ICLASS))) {
            if (klass != origin && (mtbl = RCLASS_M_TBL(klass)) != 0) rb_id_table_foreach(mtbl, method_entry_i, &me_arg);
            klass = RCLASS_SUPER(klass);
        }
    }
    ary = rb_ary_new2(me_arg.list->num_entries);
    st_foreach(me_arg.list, ins_methods_i, ary);
    st_free_table(me_arg.list);

    return ary;
}

/*!
 * \}
 */
/*!
 * \addtogroup defmethod
 * \{
 */

#ifdef rb_define_method_id
#undef rb_define_method_id
#endif
void
rb_define_method_id(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method_cfunc(klass, mid, func, argc, METHOD_VISI_PUBLIC);
}

#ifdef rb_define_method
#undef rb_define_method
#endif
void
rb_define_method(VALUE klass, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method_cfunc(klass, rb_intern(name), func, argc, METHOD_VISI_PUBLIC);
}

#ifdef rb_define_protected_method
#undef rb_define_protected_method
#endif
void
rb_define_protected_method(VALUE klass, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method_cfunc(klass, rb_intern(name), func, argc, METHOD_VISI_PROTECTED);
}

#ifdef rb_define_private_method
#undef rb_define_private_method
#endif
void
rb_define_private_method(VALUE klass, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_add_method_cfunc(klass, rb_intern(name), func, argc, METHOD_VISI_PRIVATE);
}

void
rb_undef_method(VALUE klass, const char *name)
{
    rb_add_method(klass, rb_intern(name), VM_METHOD_TYPE_UNDEF, 0, METHOD_VISI_UNDEF);
}

static enum rb_id_table_iterator_result
undef_method_i(ID name, VALUE value, void *data)
{
    VALUE klass = (VALUE)data;
    rb_add_method(klass, name, VM_METHOD_TYPE_UNDEF, 0, METHOD_VISI_UNDEF);
    return ID_TABLE_CONTINUE;
}

void
rb_undef_methods_from(VALUE klass, VALUE super)
{
    struct rb_id_table *mtbl = RCLASS_M_TBL(super);
    if (mtbl) {
        rb_id_table_foreach(mtbl, undef_method_i, (void *)klass);
    }
}

/*!
 * \}
 */
/*!
 * \addtogroup class
 * \{
 */

static inline VALUE
special_singleton_class_of(VALUE obj)
{
    switch (obj) {
      case Qnil:   return rb_cNilClass;
      case Qfalse: return rb_cFalseClass;
      case Qtrue:  return rb_cTrueClass;
      default:     return Qnil;
    }
}

VALUE
rb_special_singleton_class(VALUE obj)
{
    return special_singleton_class_of(obj);
}

/**
 * @internal
 * Returns the singleton class of `obj`. Creates it if necessary.
 *
 * @note DO NOT expose the returned singleton class to
 *       outside of class.c.
 *       Use @ref rb_singleton_class instead for
 *       consistency of the metaclass hierarchy.
 */
static VALUE
singleton_class_of(VALUE obj)
{
    VALUE klass;

    switch (TYPE(obj)) {
      case T_FIXNUM:
      case T_BIGNUM:
      case T_FLOAT:
      case T_SYMBOL:
        rb_raise(rb_eTypeError, "can't define singleton");

      case T_FALSE:
      case T_TRUE:
      case T_NIL:
        klass = special_singleton_class_of(obj);
        if (NIL_P(klass))
            rb_bug("unknown immediate %p", (void *)obj);
        return klass;

      case T_STRING:
        if (CHILLED_STRING_P(obj)) {
            CHILLED_STRING_MUTATED(obj);
        }
        else if (FL_TEST_RAW(obj, RSTRING_FSTR)) {
            rb_raise(rb_eTypeError, "can't define singleton");
        }
    }

    klass = METACLASS_OF(obj);
    if (!(RCLASS_SINGLETON_P(klass) &&
          RCLASS_ATTACHED_OBJECT(klass) == obj)) {
        klass = rb_make_metaclass(obj, klass);
    }

    RB_FL_SET_RAW(klass, RB_OBJ_FROZEN_RAW(obj));

    return klass;
}

void
rb_freeze_singleton_class(VALUE x)
{
    /* should not propagate to meta-meta-class, and so on */
    if (!RCLASS_SINGLETON_P(x)) {
        VALUE klass = RBASIC_CLASS(x);
        if (klass && // no class when hidden from ObjectSpace
            FL_TEST(klass, (FL_SINGLETON|FL_FREEZE)) == FL_SINGLETON) {
            OBJ_FREEZE(klass);
        }
    }
}

/**
 * Returns the singleton class of `obj`, or nil if obj is not a
 * singleton object.
 *
 * @param obj an arbitrary object.
 * @return the singleton class or nil.
 */
VALUE
rb_singleton_class_get(VALUE obj)
{
    VALUE klass;

    if (SPECIAL_CONST_P(obj)) {
        return rb_special_singleton_class(obj);
    }
    klass = METACLASS_OF(obj);
    if (!RCLASS_SINGLETON_P(klass)) return Qnil;
    if (RCLASS_ATTACHED_OBJECT(klass) != obj) return Qnil;
    return klass;
}

VALUE
rb_singleton_class(VALUE obj)
{
    VALUE klass = singleton_class_of(obj);

    /* ensures an exposed class belongs to its own eigenclass */
    if (RB_TYPE_P(obj, T_CLASS)) (void)ENSURE_EIGENCLASS(klass);

    return klass;
}

/*!
 * \}
 */

/*!
 * \addtogroup defmethod
 * \{
 */

#ifdef rb_define_singleton_method
#undef rb_define_singleton_method
#endif
void
rb_define_singleton_method(VALUE obj, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_method(singleton_class_of(obj), name, func, argc);
}

#ifdef rb_define_module_function
#undef rb_define_module_function
#endif
void
rb_define_module_function(VALUE module, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_private_method(module, name, func, argc);
    rb_define_singleton_method(module, name, func, argc);
}

#ifdef rb_define_global_function
#undef rb_define_global_function
#endif
void
rb_define_global_function(const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_module_function(rb_mKernel, name, func, argc);
}

void
rb_define_alias(VALUE klass, const char *name1, const char *name2)
{
    rb_alias(klass, rb_intern(name1), rb_intern(name2));
}

void
rb_define_attr(VALUE klass, const char *name, int read, int write)
{
    rb_attr(klass, rb_intern(name), read, write, FALSE);
}

VALUE
rb_keyword_error_new(const char *error, VALUE keys)
{
    long i = 0, len = RARRAY_LEN(keys);
    VALUE error_message = rb_sprintf("%s keyword%.*s", error, len > 1, "s");

    if (len > 0) {
        rb_str_cat_cstr(error_message, ": ");
        while (1) {
            const VALUE k = RARRAY_AREF(keys, i);
            rb_str_append(error_message, rb_inspect(k));
            if (++i >= len) break;
            rb_str_cat_cstr(error_message, ", ");
        }
    }

    return rb_exc_new_str(rb_eArgError, error_message);
}

NORETURN(static void rb_keyword_error(const char *error, VALUE keys));
static void
rb_keyword_error(const char *error, VALUE keys)
{
    rb_exc_raise(rb_keyword_error_new(error, keys));
}

NORETURN(static void unknown_keyword_error(VALUE hash, const ID *table, int keywords));
static void
unknown_keyword_error(VALUE hash, const ID *table, int keywords)
{
    int i;
    for (i = 0; i < keywords; i++) {
        st_data_t key = ID2SYM(table[i]);
        rb_hash_stlike_delete(hash, &key, NULL);
    }
    rb_keyword_error("unknown", rb_hash_keys(hash));
}


static int
separate_symbol(st_data_t key, st_data_t value, st_data_t arg)
{
    VALUE *kwdhash = (VALUE *)arg;
    if (!SYMBOL_P(key)) kwdhash++;
    if (!*kwdhash) *kwdhash = rb_hash_new();
    rb_hash_aset(*kwdhash, (VALUE)key, (VALUE)value);
    return ST_CONTINUE;
}

VALUE
rb_extract_keywords(VALUE *orighash)
{
    VALUE parthash[2] = {0, 0};
    VALUE hash = *orighash;

    if (RHASH_EMPTY_P(hash)) {
        *orighash = 0;
        return hash;
    }
    rb_hash_foreach(hash, separate_symbol, (st_data_t)&parthash);
    *orighash = parthash[1];
    if (parthash[1] && RBASIC_CLASS(hash) != rb_cHash) {
        RBASIC_SET_CLASS(parthash[1], RBASIC_CLASS(hash));
    }
    return parthash[0];
}

int
rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *values)
{
    int i = 0, j;
    int rest = 0;
    VALUE missing = Qnil;
    st_data_t key;

#define extract_kwarg(keyword, val) \
    (key = (st_data_t)(keyword), values ? \
     (rb_hash_stlike_delete(keyword_hash, &key, &(val)) || ((val) = Qundef, 0)) : \
     rb_hash_stlike_lookup(keyword_hash, key, NULL))

    if (NIL_P(keyword_hash)) keyword_hash = 0;

    if (optional < 0) {
        rest = 1;
        optional = -1-optional;
    }
    if (required) {
        for (; i < required; i++) {
            VALUE keyword = ID2SYM(table[i]);
            if (keyword_hash) {
                if (extract_kwarg(keyword, values[i])) {
                    continue;
                }
            }
            if (NIL_P(missing)) missing = rb_ary_hidden_new(1);
            rb_ary_push(missing, keyword);
        }
        if (!NIL_P(missing)) {
            rb_keyword_error("missing", missing);
        }
    }
    j = i;
    if (optional && keyword_hash) {
        for (i = 0; i < optional; i++) {
            if (extract_kwarg(ID2SYM(table[required+i]), values[required+i])) {
                j++;
            }
        }
    }
    if (!rest && keyword_hash) {
        if (RHASH_SIZE(keyword_hash) > (unsigned int)(values ? 0 : j)) {
            unknown_keyword_error(keyword_hash, table, required+optional);
        }
    }
    if (values && !keyword_hash) {
        for (i = 0; i < required + optional; i++) {
            values[i] = Qundef;
        }
    }
    return j;
#undef extract_kwarg
}

struct rb_scan_args_t {
    int kw_flag;
    int n_lead;
    int n_opt;
    int n_trail;
    bool f_var;
    bool f_hash;
    bool f_block;
};

static void
rb_scan_args_parse(int kw_flag, const char *fmt, struct rb_scan_args_t *arg)
{
    const char *p = fmt;

    memset(arg, 0, sizeof(*arg));
    arg->kw_flag = kw_flag;

    if (ISDIGIT(*p)) {
        arg->n_lead = *p - '0';
        p++;
        if (ISDIGIT(*p)) {
            arg->n_opt = *p - '0';
            p++;
        }
    }
    if (*p == '*') {
        arg->f_var = 1;
        p++;
    }
    if (ISDIGIT(*p)) {
        arg->n_trail = *p - '0';
        p++;
    }
    if (*p == ':') {
        arg->f_hash = 1;
        p++;
    }
    if (*p == '&') {
        arg->f_block = 1;
        p++;
    }
    if (*p != '\0') {
        rb_fatal("bad scan arg format: %s", fmt);
    }
}

static int
rb_scan_args_assign(const struct rb_scan_args_t *arg, int argc, const VALUE *const argv, va_list vargs)
{
    int i, argi = 0;
    VALUE *var, hash = Qnil;
#define rb_scan_args_next_param() va_arg(vargs, VALUE *)
    const int kw_flag = arg->kw_flag;
    const int n_lead = arg->n_lead;
    const int n_opt = arg->n_opt;
    const int n_trail = arg->n_trail;
    const int n_mand = n_lead + n_trail;
    const bool f_var = arg->f_var;
    const bool f_hash = arg->f_hash;
    const bool f_block = arg->f_block;

    /* capture an option hash - phase 1: pop from the argv */
    if (f_hash && argc > 0) {
        VALUE last = argv[argc - 1];
        if (rb_scan_args_keyword_p(kw_flag, last)) {
            hash = rb_hash_dup(last);
            argc--;
        }
    }

    if (argc < n_mand) {
        goto argc_error;
    }

    /* capture leading mandatory arguments */
    for (i = 0; i < n_lead; i++) {
        var = rb_scan_args_next_param();
        if (var) *var = argv[argi];
        argi++;
    }
    /* capture optional arguments */
    for (i = 0; i < n_opt; i++) {
        var = rb_scan_args_next_param();
        if (argi < argc - n_trail) {
            if (var) *var = argv[argi];
            argi++;
        }
        else {
            if (var) *var = Qnil;
        }
    }
    /* capture variable length arguments */
    if (f_var) {
        int n_var = argc - argi - n_trail;

        var = rb_scan_args_next_param();
        if (0 < n_var) {
            if (var) *var = rb_ary_new_from_values(n_var, &argv[argi]);
            argi += n_var;
        }
        else {
            if (var) *var = rb_ary_new();
        }
    }
    /* capture trailing mandatory arguments */
    for (i = 0; i < n_trail; i++) {
        var = rb_scan_args_next_param();
        if (var) *var = argv[argi];
        argi++;
    }
    /* capture an option hash - phase 2: assignment */
    if (f_hash) {
        var = rb_scan_args_next_param();
        if (var) *var = hash;
    }
    /* capture iterator block */
    if (f_block) {
        var = rb_scan_args_next_param();
        if (rb_block_given_p()) {
            *var = rb_block_proc();
        }
        else {
            *var = Qnil;
        }
    }

    if (argi == argc) {
        return argc;
    }

  argc_error:
    return -(argc + 1);
#undef rb_scan_args_next_param
}

static int
rb_scan_args_result(const struct rb_scan_args_t *const arg, int argc)
{
    const int n_lead = arg->n_lead;
    const int n_opt = arg->n_opt;
    const int n_trail = arg->n_trail;
    const int n_mand = n_lead + n_trail;
    const bool f_var = arg->f_var;

    if (argc >= 0) {
        return argc;
    }

    argc = -argc - 1;
    rb_error_arity(argc, n_mand, f_var ? UNLIMITED_ARGUMENTS : n_mand + n_opt);
    UNREACHABLE_RETURN(-1);
}

#undef rb_scan_args
int
rb_scan_args(int argc, const VALUE *argv, const char *fmt, ...)
{
    va_list vargs;
    struct rb_scan_args_t arg;
    rb_scan_args_parse(RB_SCAN_ARGS_PASS_CALLED_KEYWORDS, fmt, &arg);
    va_start(vargs,fmt);
    argc = rb_scan_args_assign(&arg, argc, argv, vargs);
    va_end(vargs);
    return rb_scan_args_result(&arg, argc);
}

#undef rb_scan_args_kw
int
rb_scan_args_kw(int kw_flag, int argc, const VALUE *argv, const char *fmt, ...)
{
    va_list vargs;
    struct rb_scan_args_t arg;
    rb_scan_args_parse(kw_flag, fmt, &arg);
    va_start(vargs,fmt);
    argc = rb_scan_args_assign(&arg, argc, argv, vargs);
    va_end(vargs);
    return rb_scan_args_result(&arg, argc);
}

/*!
 * \}
 */
