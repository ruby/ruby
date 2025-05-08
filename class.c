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
 * 2:    RCLASS_SUPERCLASSES_INCLUDE_SELF
 *           The RCLASS_SUPERCLASSES contains the class as the last element.
 *           This means that this class owns the RCLASS_SUPERCLASSES list.
 * if !SHAPE_IN_BASIC_FLAGS
 * 4-19: SHAPE_FLAG_MASK
 *           Shape ID for the class.
 * endif
 */

/* Flags of T_ICLASS
 *
 * 0:    RICLASS_IS_ORIGIN
 * 3:    RICLASS_ORIGIN_SHARED_MTBL
 *           The T_ICLASS does not own the method table.
 * if !SHAPE_IN_BASIC_FLAGS
 * 4-19: SHAPE_FLAG_MASK
 *           Shape ID. This is set but not used.
 * endif
 */

/* Flags of T_MODULE
 *
 * 0:    RCLASS_IS_ROOT
 *           The class has been added to the VM roots. Will always be marked and pinned.
 *           This is done for classes defined from C to allow storing them in global variables.
 * 1:    RMODULE_ALLOCATED_BUT_NOT_INITIALIZED
 *           Module has not been initialized.
 * 2:    RCLASS_SUPERCLASSES_INCLUDE_SELF
 *           See RCLASS_SUPERCLASSES_INCLUDE_SELF in T_CLASS.
 * 3:    RMODULE_IS_REFINEMENT
 *           Module is used for refinements.
 * if !SHAPE_IN_BASIC_FLAGS
 * 4-19: SHAPE_FLAG_MASK
 *           Shape ID for the module.
 * endif
 */

#define METACLASS_OF(k) RBASIC(k)->klass
#define SET_METACLASS_OF(k, cls) RBASIC_SET_CLASS(k, cls)

RUBY_EXTERN rb_serial_t ruby_vm_global_cvar_state;

static rb_subclass_entry_t *
push_subclass_entry_to_list(VALUE super, VALUE klass)
{
    rb_subclass_entry_t *entry = ZALLOC(rb_subclass_entry_t);
    entry->klass = klass;

    RB_VM_LOCK_ENTER();
    {
        rb_subclass_entry_t *head = RCLASS_SUBCLASSES(super);
        if (!head) {
            head = ZALLOC(rb_subclass_entry_t);
            RCLASS_SUBCLASSES(super) = head;
        }
        entry->next = head->next;
        entry->prev = head;

        if (head->next) {
            head->next->prev = entry;
        }
        head->next = entry;
    }
    RB_VM_LOCK_LEAVE();

    return entry;
}

void
rb_class_subclass_add(VALUE super, VALUE klass)
{
    if (super && !UNDEF_P(super)) {
        rb_subclass_entry_t *entry = push_subclass_entry_to_list(super, klass);
        RCLASS_SUBCLASS_ENTRY(klass) = entry;
    }
}

static void
rb_module_add_to_subclasses_list(VALUE module, VALUE iclass)
{
    rb_subclass_entry_t *entry = push_subclass_entry_to_list(module, iclass);
    RCLASS_MODULE_SUBCLASS_ENTRY(iclass) = entry;
}

void
rb_class_remove_subclass_head(VALUE klass)
{
    rb_subclass_entry_t *head = RCLASS_SUBCLASSES(klass);

    if (head) {
        if (head->next) {
            head->next->prev = NULL;
        }
        RCLASS_SUBCLASSES(klass) = NULL;
        xfree(head);
    }
}

void
rb_class_remove_from_super_subclasses(VALUE klass)
{
    rb_subclass_entry_t *entry = RCLASS_SUBCLASS_ENTRY(klass);

    if (entry) {
        rb_subclass_entry_t *prev = entry->prev, *next = entry->next;

        if (prev) {
            prev->next = next;
        }
        if (next) {
            next->prev = prev;
        }

        xfree(entry);
    }

    RCLASS_SUBCLASS_ENTRY(klass) = NULL;
}

void
rb_class_remove_from_module_subclasses(VALUE klass)
{
    rb_subclass_entry_t *entry = RCLASS_MODULE_SUBCLASS_ENTRY(klass);

    if (entry) {
        rb_subclass_entry_t *prev = entry->prev, *next = entry->next;

        if (prev) {
            prev->next = next;
        }
        if (next) {
            next->prev = prev;
        }

        xfree(entry);
    }

    RCLASS_MODULE_SUBCLASS_ENTRY(klass) = NULL;
}

void
rb_class_foreach_subclass(VALUE klass, void (*f)(VALUE, VALUE), VALUE arg)
{
    // RCLASS_SUBCLASSES should always point to our head element which has NULL klass
    rb_subclass_entry_t *cur = RCLASS_SUBCLASSES(klass);
    // if we have a subclasses list, then the head is a placeholder with no valid
    // class. So ignore it and use the next element in the list (if one exists)
    if (cur) {
        RUBY_ASSERT(!cur->klass);
        cur = cur->next;
    }

    /* do not be tempted to simplify this loop into a for loop, the order of
       operations is important here if `f` modifies the linked list */
    while (cur) {
        VALUE curklass = cur->klass;
        cur = cur->next;
        // do not trigger GC during f, otherwise the cur will become
        // a dangling pointer if the subclass is collected
        f(curklass, arg);
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

/**
 * Allocates a struct RClass for a new class.
 *
 * @param flags     initial value for basic.flags of the returned class.
 * @param klass     the class of the returned class.
 * @return          an uninitialized Class object.
 * @pre  `klass` must refer `Class` class or an ancestor of Class.
 * @pre  `(flags | T_CLASS) != 0`
 * @post the returned class can safely be `#initialize` 'd.
 *
 * @note this function is not Class#allocate.
 */
static VALUE
class_alloc(VALUE flags, VALUE klass)
{
    size_t alloc_size = sizeof(struct RClass) + sizeof(rb_classext_t);

    flags &= T_MASK;
    if (RGENGC_WB_PROTECTED_CLASS) flags |= FL_WB_PROTECTED;
    NEWOBJ_OF(obj, struct RClass, klass, flags, alloc_size, 0);

    memset(RCLASS_EXT(obj), 0, sizeof(rb_classext_t));

    /* ZALLOC
      RCLASS_CONST_TBL(obj) = 0;
      RCLASS_M_TBL(obj) = 0;
      RCLASS_FIELDS(obj) = 0;
      RCLASS_SET_SUPER((VALUE)obj, 0);
      RCLASS_SUBCLASSES(obj) = NULL;
      RCLASS_PARENT_SUBCLASSES(obj) = NULL;
      RCLASS_MODULE_SUBCLASSES(obj) = NULL;
     */
    RCLASS_SET_ORIGIN((VALUE)obj, (VALUE)obj);
    RB_OBJ_WRITE(obj, &RCLASS_REFINED_CLASS(obj), Qnil);
    RCLASS_SET_ALLOCATOR((VALUE)obj, 0);

    return (VALUE)obj;
}

static void
RCLASS_M_TBL_INIT(VALUE c)
{
    RCLASS_M_TBL(c) = rb_id_table_create(0);
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

    RCLASS_SET_SUPER(klass, super);
    RCLASS_M_TBL_INIT(klass);

    return (VALUE)klass;
}

static VALUE *
class_superclasses_including_self(VALUE klass)
{
    if (FL_TEST_RAW(klass, RCLASS_SUPERCLASSES_INCLUDE_SELF))
        return RCLASS_SUPERCLASSES(klass);

    size_t depth = RCLASS_SUPERCLASS_DEPTH(klass);
    VALUE *superclasses = xmalloc(sizeof(VALUE) * (depth + 1));
    if (depth > 0)
        memcpy(superclasses, RCLASS_SUPERCLASSES(klass), sizeof(VALUE) * depth);
    superclasses[depth] = klass;

    RCLASS_SUPERCLASSES(klass) = superclasses;
    FL_SET_RAW(klass, RCLASS_SUPERCLASSES_INCLUDE_SELF);
    return superclasses;
}

void
rb_class_update_superclasses(VALUE klass)
{
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

    RCLASS_SUPERCLASSES(klass) = class_superclasses_including_self(super);
    RCLASS_SUPERCLASS_DEPTH(klass) = RCLASS_SUPERCLASS_DEPTH(super) + 1;
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
        RCLASS_EXT(klass)->max_iv_count = RCLASS_EXT(super)->max_iv_count;
    }

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
        rb_cref_t *new_cref;
        rb_vm_rewrite_cref(me->def->body.iseq.cref, old_klass, new_klass, &new_cref);
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
    if (RCLASS_SUPER(clone) != 0 || clone == rb_cBasicObject) {
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
        RCLASS_CONST_TBL(clone) = 0;
    }
    if (RCLASS_CVC_TBL(orig)) {
        struct rb_id_table *rb_cvc_tbl = RCLASS_CVC_TBL(orig);
        struct rb_id_table *rb_cvc_tbl_dup = rb_id_table_create(rb_id_table_size(rb_cvc_tbl));

        struct cvc_table_copy_ctx ctx;
        ctx.clone = clone;
        ctx.new_table = rb_cvc_tbl_dup;
        rb_id_table_foreach(rb_cvc_tbl, cvc_table_copy, &ctx);
        RCLASS_CVC_TBL(clone) = rb_cvc_tbl_dup;
    }
    rb_id_table_free(RCLASS_M_TBL(clone));
    RCLASS_M_TBL(clone) = 0;
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

        arg.tbl = RCLASS_CONST_TBL(clone) = rb_id_table_create(0);
        arg.klass = clone;
        rb_id_table_foreach(RCLASS_CONST_TBL(orig), clone_const_i, &arg);
    }
}

static bool ensure_origin(VALUE klass);

/**
 * If this flag is set, that module is allocated but not initialized yet.
 */
enum {RMODULE_ALLOCATED_BUT_NOT_INITIALIZED = RUBY_FL_USER1};

static inline bool
RMODULE_UNINITIALIZED(VALUE module)
{
    return FL_TEST_RAW(module, RMODULE_ALLOCATED_BUT_NOT_INITIALIZED);
}

void
rb_module_set_initialized(VALUE mod)
{
    FL_UNSET_RAW(mod, RMODULE_ALLOCATED_BUT_NOT_INITIALIZED);
    /* no more re-initialization */
}

void
rb_module_check_initializable(VALUE mod)
{
    if (!RMODULE_UNINITIALIZED(mod)) {
        rb_raise(rb_eTypeError, "already initialized module");
    }
}

/* :nodoc: */
VALUE
rb_mod_init_copy(VALUE clone, VALUE orig)
{
    switch (BUILTIN_TYPE(clone)) {
      case T_CLASS:
      case T_ICLASS:
        class_init_copy_check(clone, orig);
        break;
      case T_MODULE:
        rb_module_check_initializable(clone);
        break;
      default:
        break;
    }
    if (!OBJ_INIT_COPY(clone, orig)) return clone;

    /* cloned flag is refer at constant inline cache
     * see vm_get_const_key_cref() in vm_insnhelper.c
     */
    RCLASS_EXT(clone)->cloned = true;
    RCLASS_EXT(orig)->cloned = true;

    if (!RCLASS_SINGLETON_P(CLASS_OF(clone))) {
        RBASIC_SET_CLASS(clone, rb_singleton_class_clone(orig));
        rb_singleton_class_attached(METACLASS_OF(clone), (VALUE)clone);
    }
    RCLASS_SET_ALLOCATOR(clone, RCLASS_ALLOCATOR(orig));
    copy_tables(clone, orig);
    if (RCLASS_M_TBL(orig)) {
        struct clone_method_arg arg;
        arg.old_klass = orig;
        arg.new_klass = clone;
        RCLASS_M_TBL_INIT(clone);
        rb_id_table_foreach(RCLASS_M_TBL(orig), clone_method_i, &arg);
    }

    if (RCLASS_ORIGIN(orig) == orig) {
        RCLASS_SET_SUPER(clone, RCLASS_SUPER(orig));
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
            clone_p = class_alloc(RBASIC(p)->flags, METACLASS_OF(p));
            /* We should set the m_tbl right after allocation before anything
             * that can trigger GC to avoid clone_p from becoming old and
             * needing to fire write barriers. */
            RCLASS_SET_M_TBL(clone_p, RCLASS_M_TBL(p));
            RCLASS_SET_SUPER(prev_clone_p, clone_p);
            prev_clone_p = clone_p;
            RCLASS_CONST_TBL(clone_p) = RCLASS_CONST_TBL(p);
            RCLASS_SET_ALLOCATOR(clone_p, RCLASS_ALLOCATOR(p));
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
                RCLASS_SET_ORIGIN(RARRAY_AREF(origin_stack, (origin_len -= 2)), clone_p);
                RICLASS_SET_ORIGIN_SHARED_MTBL(clone_p);
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
                RCLASS_SET_SUPER(clone_p, clone_origin);
                RCLASS_SET_SUPER(clone_origin, RCLASS_SUPER(orig_origin));
            }
            copy_tables(clone_origin, orig_origin);
            if (RCLASS_M_TBL(orig_origin)) {
                struct clone_method_arg arg;
                arg.old_klass = orig;
                arg.new_klass = clone;
                RCLASS_M_TBL_INIT(clone_origin);
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
        VALUE clone = class_alloc(RBASIC(klass)->flags, 0);

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

        RCLASS_SET_SUPER(clone, RCLASS_SUPER(klass));
        rb_fields_tbl_copy(clone, klass);
        if (RCLASS_CONST_TBL(klass)) {
            struct clone_const_arg arg;
            arg.tbl = RCLASS_CONST_TBL(clone) = rb_id_table_create(0);
            arg.klass = clone;
            rb_id_table_foreach(RCLASS_CONST_TBL(klass), clone_const_i, &arg);
        }
        if (!UNDEF_P(attach)) {
            rb_singleton_class_attached(clone, attach);
        }
        RCLASS_M_TBL_INIT(clone);
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
    RCLASS_SET_SUPER(metaclass, super ? ENSURE_EIGENCLASS(super) : rb_cClass);

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

    id = rb_intern(name);
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
    RCLASS_M_TBL_INIT(mod);
    FL_SET(mod, RMODULE_ALLOCATED_BUT_NOT_INITIALIZED);
    return mod;
}

static inline VALUE
module_new(VALUE klass)
{
    VALUE mdl = class_alloc(T_MODULE, klass);
    RCLASS_M_TBL_INIT(mdl);
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

    id = rb_intern(name);
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

    RCLASS_SET_M_TBL(klass, RCLASS_M_TBL(module));

    RCLASS_SET_ORIGIN(klass, klass);
    if (BUILTIN_TYPE(module) == T_ICLASS) {
        module = METACLASS_OF(module);
    }
    RUBY_ASSERT(!RB_TYPE_P(module, T_ICLASS));
    if (!RCLASS_CONST_TBL(module)) {
        RCLASS_CONST_TBL(module) = rb_id_table_create(0);
    }

    RCLASS_CVC_TBL(klass) = RCLASS_CVC_TBL(module);
    RCLASS_CONST_TBL(klass) = RCLASS_CONST_TBL(module);

    RCLASS_SET_SUPER(klass, super);
    RBASIC_SET_CLASS(klass, module);

    return (VALUE)klass;
}

static int include_modules_at(const VALUE klass, VALUE c, VALUE module, int search_super);

static void
ensure_includable(VALUE klass, VALUE module)
{
    rb_class_modify_check(klass);
    Check_Type(module, T_MODULE);
    rb_module_set_initialized(module);
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
        rb_subclass_entry_t *iclass = RCLASS_SUBCLASSES(klass);
        // skip the placeholder subclass entry at the head of the list
        if (iclass) {
            RUBY_ASSERT(!iclass->klass);
            iclass = iclass->next;
        }

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
        c = RCLASS_SET_SUPER(c, iclass);
        RCLASS_SET_INCLUDER(iclass, klass);
        if (module != RCLASS_ORIGIN(module)) {
            if (!origin_stack) origin_stack = rb_ary_hidden_new(2);
            VALUE origin[2] = {iclass, RCLASS_ORIGIN(module)};
            rb_ary_cat(origin_stack, origin, 2);
        }
        else if (origin_stack && (origin_len = RARRAY_LEN(origin_stack)) > 1 &&
                 RARRAY_AREF(origin_stack, origin_len - 1) == module) {
            RCLASS_SET_ORIGIN(RARRAY_AREF(origin_stack, (origin_len -= 2)), iclass);
            RICLASS_SET_ORIGIN_SHARED_MTBL(iclass);
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
        struct rb_id_table *tbl = RCLASS_M_TBL(klass);

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
        RCLASS_SET_SUPER(origin, RCLASS_SUPER(klass));
        RCLASS_SET_SUPER(klass, origin);
        RCLASS_SET_ORIGIN(klass, origin);
        RCLASS_M_TBL_INIT(klass);
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
        rb_subclass_entry_t *iclass = RCLASS_SUBCLASSES(klass);
        // skip the placeholder subclass entry at the head of the list if it exists
        if (iclass) {
            RUBY_ASSERT(!iclass->klass);
            iclass = iclass->next;
        }

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
                    RCLASS_M_TBL(subclass) = klass_m_tbl;
                    VALUE origin = rb_include_class_new(klass_origin, RCLASS_SUPER(subclass));
                    RCLASS_SET_SUPER(subclass, origin);
                    RCLASS_SET_INCLUDER(origin, RCLASS_INCLUDER(subclass));
                    RCLASS_SET_ORIGIN(subclass, origin);
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
        if (BUILTIN_TYPE(p) == T_ICLASS && !FL_TEST(p, RICLASS_IS_ORIGIN)) {
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
