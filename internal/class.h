#ifndef INTERNAL_CLASS_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_CLASS_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Class.
 */
#include "id.h"
#include "id_table.h"           /* for struct rb_id_table */
#include "internal/namespace.h" /* for rb_current_namespace */
#include "internal/serial.h"    /* for rb_serial_t */
#include "internal/static_assert.h"
#include "internal/variable.h"  /* for rb_class_ivar_set */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/intern.h"        /* for rb_alloc_func_t */
#include "ruby/ruby.h"          /* for struct RBasic */
#include "shape.h"
#include "ruby_assert.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "method.h"             /* for rb_cref_t */

#ifdef RCLASS_SUPER
# undef RCLASS_SUPER
#endif

struct rb_ns_subclasses {
    long refcount;
    struct st_table *tbl;
};
typedef struct rb_ns_subclasses rb_ns_subclasses_t;

static inline long
rb_ns_subclasses_ref_count(rb_ns_subclasses_t *ns_sub)
{
    return ns_sub->refcount;
}

static inline rb_ns_subclasses_t *
rb_ns_subclasses_ref_inc(rb_ns_subclasses_t *ns_sub)
{
    ns_sub->refcount++;
    return ns_sub;
}

static inline void
rb_ns_subclasses_ref_dec(rb_ns_subclasses_t *ns_sub)
{
    ns_sub->refcount--;
    if (ns_sub->refcount == 0) {
        st_free_table(ns_sub->tbl);
        xfree(ns_sub);
    }
}

struct rb_subclass_anchor {
    rb_ns_subclasses_t *ns_subclasses;
    struct rb_subclass_entry *head;
};
typedef struct rb_subclass_anchor rb_subclass_anchor_t;

struct rb_subclass_entry {
    VALUE klass;
    struct rb_subclass_entry *next;
    struct rb_subclass_entry *prev;
};
typedef struct rb_subclass_entry rb_subclass_entry_t;

struct rb_cvar_class_tbl_entry {
    uint32_t index;
    rb_serial_t global_cvar_state;
    const rb_cref_t * cref;
    VALUE class_value;
};

struct rb_classext_struct {
    const rb_namespace_t *ns;
    VALUE super;
    VALUE *iv_ptr;
    struct rb_id_table *m_tbl;
    struct rb_id_table *const_tbl;
    struct rb_id_table *callable_m_tbl;
    struct rb_id_table *cc_tbl; /* ID -> [[ci1, cc1], [ci2, cc2] ...] */
    struct rb_id_table *cvc_tbl;
    size_t superclass_depth;
    VALUE *superclasses;
    /**
     * The head of subclasses is a blank (w/o klass) entry to be referred from anchor (and be never deleted).
     * (anchor -> head -> 1st-entry)
     */
    struct rb_subclass_anchor *subclasses;
    /**
     * The `ns_super_subclasses` points the `ns_subclasses` struct to retreive the subclasses
     * of the super class in a specific namespace.
     * In compaction GCs, collecting a classext should trigger the deletion of a rb_subclass_entry
     * from the super's subclasses. But it may be prevented by the read barrier.
     * Fetching the super's subclasses for a ns is to avoid the read barrier in that process.
     */
    rb_ns_subclasses_t *ns_super_subclasses;
    /**
     * In the case that this is an `ICLASS`, `ns_module_subclasses` points to the link
     * in the module's `subclasses` list that indicates that the klass has been
     * included. Hopefully that makes sense.
     */
    rb_ns_subclasses_t *ns_module_subclasses;

    const VALUE origin_;
    const VALUE refined_class;
    union {
        struct {
            rb_alloc_func_t allocator;
        } class;
        struct {
            VALUE attached_object;
        } singleton_class;
    } as;
    const VALUE includer;
    attr_index_t max_iv_count;
    unsigned char variation_count;
    bool permanent_classpath : 1;
    bool cloned : 1;
    bool shared_const_tbl : 1;
    bool iclass_is_origin : 1;
    bool iclass_origin_shared_mtbl : 1;
    bool superclasses_owner : 1;
    bool superclasses_with_self : 1;
    VALUE classpath;
};
typedef struct rb_classext_struct rb_classext_t;

STATIC_ASSERT(shape_max_variations, SHAPE_MAX_VARIATIONS < (1 << (sizeof(((rb_classext_t *)0)->variation_count) * CHAR_BIT)));

struct RClass {
    struct RBasic basic;
    st_table *ns_classext_tbl; // ns_object -> (rb_classext_t *)
    bool prime_classext_readable : 1;
    bool prime_classext_writable : 1;
};

/** TODO: Update or remove this assertion
 * // Assert that classes can be embedded in heaps[2] (which has 160B slot size)
 * STATIC_ASSERT(sizeof_rb_classext_t, sizeof(struct RClass) + sizeof(rb_classext_t) <= 4 * RVALUE_SIZE);
 */

struct RClass_and_rb_classext_t {
    struct RClass rclass;
    rb_classext_t classext;
};

#define RCLASS_PRIME_READABLE_P(obj) (RCLASS(obj)->prime_classext_readable)
#define RCLASS_PRIME_WRITABLE_P(obj) (RCLASS(obj)->prime_classext_writable)

static inline bool RCLASS_SINGLETON_P(VALUE klass);

static inline void RCLASS_SET_CLASSEXT_TABLE(VALUE obj, st_table *tbl);
static inline void RCLASS_SET_PRIME_CLASSEXT_READWRITE(VALUE obj, bool readable, bool writable);

#define RCLASS_EXT(c) (&((struct RClass_and_rb_classext_t*)(c))->classext)
#define RCLASS_EXT_PRIME_P(ext, c) (&((struct RClass_and_rb_classext_t*)(c))->classext == ext)

static inline rb_classext_t * RCLASS_EXT_READABLE_IN_NS(VALUE obj, const rb_namespace_t *ns);
static inline rb_classext_t * RCLASS_EXT_READABLE(VALUE obj);
static inline rb_classext_t * RCLASS_EXT_WRITABLE_IN_NS(VALUE obj, const rb_namespace_t *ns);
static inline rb_classext_t * RCLASS_EXT_WRITABLE(VALUE obj);

// Raw accessor
#define RCLASS_CLASSEXT_TBL(klass) (RCLASS(klass)->ns_classext_tbl)

#define RCLASSEXT_NS(ext) (ext->ns)
#define RCLASSEXT_SUPER(ext) (ext->super)
#define RCLASSEXT_IV_PTR(ext) (ext->iv_ptr)
#define RCLASSEXT_M_TBL(ext) (ext->m_tbl)
#define RCLASSEXT_CONST_TBL(ext) (ext->const_tbl)
#define RCLASSEXT_CALLABLE_M_TBL(ext) (ext->callable_m_tbl)
#define RCLASSEXT_CC_TBL(ext) (ext->cc_tbl)
#define RCLASSEXT_CVC_TBL(ext) (ext->cvc_tbl)
#define RCLASSEXT_SUPERCLASS_DEPTH(ext) (ext->superclass_depth)
#define RCLASSEXT_SUPERCLASSES(ext) (ext->superclasses)
#define RCLASSEXT_SUBCLASSES(ext) (ext->subclasses)
#define RCLASSEXT_NS_SUPER_SUBCLASSES(ext) (ext->ns_super_subclasses)
#define RCLASSEXT_NS_MODULE_SUBCLASSES(ext) (ext->ns_module_subclasses)
#define RCLASSEXT_ORIGIN(ext) (ext->origin_)
#define RCLASSEXT_REFINED_CLASS(ext) (ext->refined_class)
// class.allocator/singleton_class.attached_object are not accessed directly via RCLASSEXT_*
#define RCLASSEXT_INCLUDER(ext) (ext->includer)
#define RCLASSEXT_MAX_IV_COUNT(ext) (ext->max_iv_count)
#define RCLASSEXT_VARIATION_COUNT(ext) (ext->variation_count)
#define RCLASSEXT_PERMANENT_CLASSPATH(ext) (ext->permanent_classpath)
#define RCLASSEXT_CLONED(ext) (ext->cloned)
#define RCLASSEXT_SHARED_CONST_TBL(ext) (ext->shared_const_tbl)
#define RCLASSEXT_ICLASS_IS_ORIGIN(ext) (ext->iclass_is_origin)
#define RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(ext) (ext->iclass_origin_shared_mtbl)
#define RCLASSEXT_SUPERCLASSES_OWNER(ext) (ext->superclasses_owner)
#define RCLASSEXT_SUPERCLASSES_WITH_SELF(ext) (ext->superclasses_with_self)
#define RCLASSEXT_CLASSPATH(ext) (ext->classpath)

static inline void RCLASSEXT_SET_ORIGIN(rb_classext_t *ext, VALUE klass, VALUE origin);
static inline void RCLASSEXT_SET_INCLUDER(rb_classext_t *ext, VALUE klass, VALUE includer);

/* Prime classext entry accessor for very specific reason */
#define RCLASS_PRIME_NS(c) (RCLASS_EXT(c)->ns)
// To invalidate CC by inserting&invalidating method entry into tables containing the target cme
// See clear_method_cache_by_id_in_class()
#define RCLASS_PRIME_M_TBL(c) (RCLASS_EXT(c)->m_tbl)
#define RCLASS_PRIME_CALLABLE_M_TBL(c) (RCLASS_EXT(c)->callable_m_tbl)
#define RCLASS_PRIME_CC_TBL(c) (RCLASS_EXT(c)->cc_tbl)
#define RCLASS_M_TBL_NOT_PRIME_P(c, tbl) (RCLASS_EXT(c)->m_tbl != tbl)
#define RCLASS_CALLABLE_M_TBL_NOT_PRIME_P(c, tbl) (RCLASS_EXT(c)->callable_m_tbl != tbl)
#define RCLASS_CC_TBL_NOT_PRIME_P(c, tbl) (RCLASS_EXT(c)->cc_tbl != tbl)

// Read accessor, regarding namespaces
#define RCLASS_SUPER(c) (RCLASS_EXT_READABLE(c)->super)
#define RCLASS_IVPTR(c) (RCLASS_EXT_READABLE(c)->iv_ptr)
#define RCLASS_M_TBL(c) (RCLASS_EXT_READABLE(c)->m_tbl)
#define RCLASS_CONST_TBL(c) (RCLASS_EXT_READABLE(c)->const_tbl)
/*
 * Both cc_tbl/callable_m_tbl are cache and always be changed when referreed,
 * so always should be writable.
 */
// #define RCLASS_CALLABLE_M_TBL(c) (RCLASS_EXT_READABLE(c)->callable_m_tbl)
// #define RCLASS_CC_TBL(c) (RCLASS_EXT_READABLE(c)->cc_tbl)
#define RCLASS_CVC_TBL(c) (RCLASS_EXT_READABLE(c)->cvc_tbl)
#define RCLASS_SUPERCLASS_DEPTH(c) (RCLASS_EXT_READABLE(c)->superclass_depth)
#define RCLASS_SUPERCLASSES(c) (RCLASS_EXT_READABLE(c)->superclasses)
#define RCLASS_SUPERCLASSES_WITH_SELF_P(c) (RCLASS_EXT_READABLE(c)->superclasses_with_self)
#define RCLASS_SUBCLASSES_X(c) (RCLASS_EXT_READABLE(c)->subclasses)
#define RCLASS_SUBCLASSES_FIRST(c) (RCLASS_EXT_READABLE(c)->subclasses->head->next)
#define RCLASS_ORIGIN(c) (RCLASS_EXT_READABLE(c)->origin_)
#define RICLASS_IS_ORIGIN_P(c) (RCLASS_EXT_READABLE(c)->iclass_is_origin)
#define RCLASS_MAX_IV_COUNT(c) (RCLASS_EXT_READABLE(c)->max_iv_count)
#define RCLASS_VARIATION_COUNT(c) (RCLASS_EXT_READABLE(c)->variation_count)
#define RCLASS_PERMANENT_CLASSPATH_P(c) (RCLASS_EXT_READABLE(c)->permanent_classpath)
#define RCLASS_CLONED_P(c) (RCLASS_EXT_READABLE(c)->cloned)
#define RCLASS_CLASSPATH(c) (RCLASS_EXT_READABLE(c)->classpath)

// namespaces don't make changes on these refined_class/attached_object/includer
#define RCLASS_REFINED_CLASS(c) (RCLASS_EXT(c)->refined_class)
#define RCLASS_ATTACHED_OBJECT(c) (RCLASS_EXT(c)->as.singleton_class.attached_object)
#define RCLASS_INCLUDER(c) (RCLASS_EXT(c)->includer)

// Writable classext entries (instead of RCLASS_SET_*) because member data will be operated directly
#define RCLASS_WRITABLE_M_TBL(c) (RCLASS_EXT_WRITABLE(c)->m_tbl)
#define RCLASS_WRITABLE_CONST_TBL(c) (RCLASS_EXT_WRITABLE(c)->const_tbl)
#define RCLASS_WRITABLE_CALLABLE_M_TBL(c) (RCLASS_EXT_WRITABLE(c)->callable_m_tbl)
#define RCLASS_WRITABLE_CC_TBL(c) (RCLASS_EXT_WRITABLE(c)->cc_tbl)
#define RCLASS_WRITABLE_CVC_TBL(c) (RCLASS_EXT_WRITABLE(c)->cvc_tbl)
#define RCLASS_WRITABLE_SUBCLASSES(c) (RCLASS_EXT_WRITABLE(c)->subclasses)

static inline void RCLASS_SET_SUPER(VALUE klass, VALUE super);
static inline void RCLASS_WRITE_SUPER(VALUE klass, VALUE super);
static inline st_table * RCLASS_IV_HASH(VALUE obj);
static inline st_table * RCLASS_WRITABLE_IV_HASH(VALUE obj);
static inline uint32_t RCLASS_IV_COUNT(VALUE obj);
static inline void RCLASS_SET_IV_HASH(VALUE obj, const st_table *table);
static inline void RCLASS_WRITE_IV_HASH(VALUE obj, const st_table *table);
static inline void RCLASS_SET_M_TBL(VALUE klass, struct rb_id_table *table);
static inline void RCLASS_WRITE_M_TBL(VALUE klass, struct rb_id_table *table);
static inline void RCLASS_SET_CONST_TBL(VALUE klass, struct rb_id_table *table, bool shared);
static inline void RCLASS_WRITE_CONST_TBL(VALUE klass, struct rb_id_table *table, bool shared);
static inline void RCLASS_WRITE_CALLABLE_M_TBL(VALUE klass, struct rb_id_table *table);
static inline void RCLASS_WRITE_CC_TBL(VALUE klass, struct rb_id_table *table);
static inline void RCLASS_SET_CVC_TBL(VALUE klass, struct rb_id_table *table);
static inline void RCLASS_WRITE_CVC_TBL(VALUE klass, struct rb_id_table *table);

static inline void RCLASS_WRITE_SUPERCLASSES(VALUE klass, size_t depth, VALUE *superclasses, bool owns_it, bool with_self);
static inline void RCLASS_SET_SUBCLASSES(VALUE klass, rb_subclass_anchor_t *anchor);
static inline void RCLASS_WRITE_SUBCLASSES(VALUE klass, rb_subclass_anchor_t *anchor);
static inline void RCLASS_WRITE_NS_SUPER_SUBCLASSES(VALUE klass, rb_ns_subclasses_t *ns_subclasses);
static inline void RCLASS_WRITE_NS_MODULE_SUBCLASSES(VALUE klass, rb_ns_subclasses_t *ns_subclasses);

static inline void RCLASS_SET_ORIGIN(VALUE klass, VALUE origin);
static inline void RCLASS_WRITE_ORIGIN(VALUE klass, VALUE origin);
static inline void RICLASS_SET_ORIGIN_SHARED_MTBL(VALUE iclass);
static inline void RICLASS_WRITE_ORIGIN_SHARED_MTBL(VALUE iclass);
static inline bool RICLASS_OWNS_M_TBL_P(VALUE iclass);

static inline void RCLASS_SET_REFINED_CLASS(VALUE klass, VALUE refined);
static inline rb_alloc_func_t RCLASS_ALLOCATOR(VALUE klass);
static inline void RCLASS_SET_ALLOCATOR(VALUE klass, rb_alloc_func_t allocator);
static inline VALUE RCLASS_SET_ATTACHED_OBJECT(VALUE klass, VALUE attached_object);

static inline void RCLASS_SET_INCLUDER(VALUE iclass, VALUE klass);
static inline void RCLASS_SET_MAX_IV_COUNT(VALUE klass, attr_index_t count);
static inline void RCLASS_WRITE_MAX_IV_COUNT(VALUE klass, attr_index_t count);
static inline void RCLASS_SET_CLONED(VALUE klass, bool cloned);
static inline void RCLASS_SET_CLASSPATH(VALUE klass, VALUE classpath, bool permanent);
static inline void RCLASS_WRITE_CLASSPATH(VALUE klass, VALUE classpath, bool permanent);

#define RCLASS_IS_ROOT FL_USER0
// #define RICLASS_IS_ORIGIN FL_USER0 // TODO: Delete this
// #define RCLASS_SUPERCLASSES_INCLUD_SELF FL_USER2 // TODO: Delete this
// #define RICLASS_ORIGIN_SHARED_MTBL FL_USER3 // TODO: Delete this

VALUE rb_class_debug_duplicate_classext(VALUE klass, VALUE namespace); // TODO: only for development
VALUE rb_class_debug_dump_all_classext(VALUE klass);                   // TODO: only for development
VALUE rb_class_debug_dump_all_classext_super(VALUE klass, VALUE upto); // TODO: only for development
void rb_class_debug_print_classext(const char *label, const char *opt, VALUE klass);

/* class.c */
rb_classext_t * rb_class_duplicate_classext(rb_classext_t *orig, VALUE obj, const rb_namespace_t *ns);
void rb_class_ensure_writable(VALUE obj);

static inline int
RCLASS_SET_NAMESPACE_CLASSEXT(VALUE obj, const rb_namespace_t *ns, rb_classext_t *ext)
{
    int tbl_created = 0;
    st_table *tbl = RCLASS_CLASSEXT_TBL(obj);
    VM_ASSERT(NAMESPACE_USER_P(ns)); // non-prime classext is only for user namespace, with ns_object
    VM_ASSERT(RCLASSEXT_NS(ext) == ns);
    if (!tbl) {
        RCLASS_CLASSEXT_TBL(obj) = tbl = st_init_numtable_with_size(1);
        tbl_created = 1;
    }
    rb_st_insert(tbl, (st_data_t)ns->ns_object, (st_data_t)ext);
    return tbl_created;
}

static inline void
RCLASS_SET_PRIME_CLASSEXT_READWRITE(VALUE obj, bool readable, bool writable)
{
    RCLASS(obj)->prime_classext_readable = readable;
    RCLASS(obj)->prime_classext_writable = writable;
}

static inline rb_classext_t *
RCLASS_EXT_TABLE_LOOKUP_INTERNAL(VALUE obj, const rb_namespace_t *ns)
{
    st_data_t classext_ptr;
    st_table *classext_tbl = RCLASS_CLASSEXT_TBL(obj);
    if (classext_tbl) {
        if (rb_st_lookup(classext_tbl, (st_data_t)ns->ns_object, &classext_ptr)) {
            return (rb_classext_t *)classext_ptr;
        }
    }
    return NULL;
}

static inline rb_classext_t *
RCLASS_EXT_READABLE_LOOKUP(VALUE obj, const rb_namespace_t *ns)
{
    rb_classext_t *ext = RCLASS_EXT_TABLE_LOOKUP_INTERNAL(obj, ns);
    if (ext)
        return ext;
    // Classext for the ns not found. Refer the prime one instead.
    return RCLASS_EXT(obj);
}

static inline rb_classext_t *
RCLASS_EXT_READABLE_IN_NS(VALUE obj, const rb_namespace_t *ns)
{
    if (!ns
        || NAMESPACE_BUILTIN_P(ns)
        || RCLASS(obj)->prime_classext_readable) {
        return RCLASS_EXT(obj);
    }
    return RCLASS_EXT_READABLE_LOOKUP(obj, ns);
}

static inline rb_classext_t *
RCLASS_EXT_READABLE(VALUE obj)
{
    const rb_namespace_t *ns;
    if (RCLASS(obj)->prime_classext_readable) {
        return RCLASS_EXT(obj);
    }
    // delay namespace loading to optimize for unmodified classes
    ns = rb_current_namespace();
    if (!ns || NAMESPACE_BUILTIN_P(ns)) {
        return RCLASS_EXT(obj);
    }
    return RCLASS_EXT_READABLE_LOOKUP(obj, ns);
}

static inline rb_classext_t *
RCLASS_EXT_WRITABLE_LOOKUP(VALUE obj, const rb_namespace_t *ns)
{
    rb_classext_t *ext;
    int table_created = 0;

    ext = RCLASS_EXT_TABLE_LOOKUP_INTERNAL(obj, ns);
    if (ext)
        return ext;

    if (!rb_shape_obj_too_complex(obj)) {
        // TODO: Handle object shapes properly
        rb_evict_ivars_to_hash(obj); // fallback to ivptr for ivars from shapes
    }

    RB_VM_LOCK_ENTER();
    {
        // re-check the classext is not created to avoid the multi-thread race
        ext = RCLASS_EXT_TABLE_LOOKUP_INTERNAL(obj, ns);
        if (!ext) {
            ext = rb_class_duplicate_classext(RCLASS_EXT(obj), obj, ns);
            table_created = RCLASS_SET_NAMESPACE_CLASSEXT(obj, ns, ext);
            if (table_created) {
                RCLASS_SET_PRIME_CLASSEXT_READWRITE(obj, false, false);
            }
        }
    }
    RB_VM_LOCK_LEAVE();
    return ext;
}

static inline rb_classext_t *
RCLASS_EXT_WRITABLE_IN_NS(VALUE obj, const rb_namespace_t *ns)
{
    if (!ns
        || NAMESPACE_BUILTIN_P(ns)
        || RCLASS(obj)->prime_classext_writable) {
        return RCLASS_EXT(obj);
    }
    return RCLASS_EXT_WRITABLE_LOOKUP(obj, ns);
}

static inline rb_classext_t *
RCLASS_EXT_WRITABLE(VALUE obj)
{
    const rb_namespace_t *ns;
    if (RCLASS(obj)->prime_classext_writable) {
        return RCLASS_EXT(obj);
    }
    // delay namespace loading to optimize for unmodified classes
    ns = rb_current_namespace();
    if (!ns || NAMESPACE_BUILTIN_P(ns)) {
        // If no namespace is specified, Ruby VM is in bootstrap
        // and the clean class definition is under construction.
        return RCLASS_EXT(obj);
    }
    return RCLASS_EXT_WRITABLE_LOOKUP(obj, ns);
}

static inline void
RCLASSEXT_SET_ORIGIN(rb_classext_t *ext, VALUE klass, VALUE origin)
{
    RB_OBJ_WRITE(klass, &(RCLASSEXT_ORIGIN(ext)), origin);
}

static inline void
RCLASSEXT_SET_INCLUDER(rb_classext_t *ext, VALUE klass, VALUE includer)
{
    RB_OBJ_WRITE(klass, &(RCLASSEXT_INCLUDER(ext)), includer);
}

/* class.c */
typedef void rb_class_classext_foreach_callback_func(rb_classext_t *classext, bool is_prime, VALUE namespace, void *arg);
void rb_class_classext_foreach(VALUE klass, rb_class_classext_foreach_callback_func *func, void *arg);
void rb_class_subclass_add(VALUE super, VALUE klass);
void rb_class_remove_from_super_subclasses(VALUE);
void rb_class_remove_from_module_subclasses(VALUE);
void rb_class_classext_free_subclasses(rb_classext_t *, VALUE);
void rb_class_foreach_subclass(VALUE klass, void (*f)(VALUE, VALUE), VALUE);
void rb_class_detach_subclasses(VALUE);
void rb_class_detach_module_subclasses(VALUE);
void rb_class_update_superclasses(VALUE);
size_t rb_class_superclasses_memsize(VALUE);
void rb_class_remove_subclass_head(VALUE);
int rb_singleton_class_internal_p(VALUE sklass);
VALUE rb_class_set_super(VALUE klass, VALUE super);
VALUE rb_class_boot(VALUE);
VALUE rb_class_s_alloc(VALUE klass);
VALUE rb_module_s_alloc(VALUE klass);
void rb_module_set_initialized(VALUE module);
void rb_module_check_initializable(VALUE module);
VALUE rb_make_metaclass(VALUE, VALUE);
VALUE rb_include_class_new(VALUE, VALUE);
VALUE rb_define_class_id_under_no_pin(VALUE outer, ID id, VALUE super);
VALUE rb_obj_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_protected_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_private_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_public_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_class_undefined_instance_methods(VALUE mod);
VALUE rb_special_singleton_class(VALUE);
VALUE rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach);
VALUE rb_singleton_class_get(VALUE obj);
void rb_undef_methods_from(VALUE klass, VALUE super);
VALUE rb_class_inherited(VALUE, VALUE);
VALUE rb_keyword_error_new(const char *, VALUE);

RUBY_SYMBOL_EXPORT_BEGIN

/* for objspace */
VALUE rb_class_super_of(VALUE klass);
VALUE rb_class_singleton_p(VALUE klass);
unsigned char rb_class_variation_count(VALUE klass);

RUBY_SYMBOL_EXPORT_END

static inline bool
RCLASS_SINGLETON_P(VALUE klass)
{
    return RB_TYPE_P(klass, T_CLASS) && FL_TEST_RAW(klass, FL_SINGLETON);
}

static inline void
RCLASS_SET_SUPER(VALUE klass, VALUE super)
{
    RB_OBJ_WRITE(klass, &RCLASSEXT_SUPER(RCLASS_EXT(klass)), super);
}

static inline void
RCLASS_WRITE_SUPER(VALUE klass, VALUE super)
{
    RB_OBJ_WRITE(klass, &RCLASSEXT_SUPER(RCLASS_EXT_WRITABLE(klass)), super);
}

static inline st_table *
RCLASS_IV_HASH(VALUE obj)
{
    RUBY_ASSERT(RB_TYPE_P(obj, RUBY_T_CLASS) || RB_TYPE_P(obj, RUBY_T_MODULE));
    RUBY_ASSERT(rb_shape_obj_too_complex(obj));
    return (st_table *)RCLASS_IVPTR(obj);
}

static inline st_table *
RCLASS_WRITABLE_IV_HASH(VALUE obj)
{
    RUBY_ASSERT(RB_TYPE_P(obj, RUBY_T_CLASS) || RB_TYPE_P(obj, RUBY_T_MODULE));
    RUBY_ASSERT(rb_shape_obj_too_complex(obj));
    return (st_table *)RCLASSEXT_IV_PTR(RCLASS_EXT_WRITABLE(obj));
}

static inline void
RCLASS_SET_IV_HASH(VALUE obj, const st_table *tbl)
{
    RUBY_ASSERT(RB_TYPE_P(obj, RUBY_T_CLASS) || RB_TYPE_P(obj, RUBY_T_MODULE));
    RUBY_ASSERT(rb_shape_obj_too_complex(obj));
    RCLASSEXT_IV_PTR(RCLASS_EXT(obj)) = (VALUE *)tbl;
}

static inline void
RCLASS_WRITE_IV_HASH(VALUE obj, const st_table *tbl)
{
    RUBY_ASSERT(RB_TYPE_P(obj, RUBY_T_CLASS) || RB_TYPE_P(obj, RUBY_T_MODULE));
    RUBY_ASSERT(rb_shape_obj_too_complex(obj));
    RCLASSEXT_IV_PTR(RCLASS_EXT_WRITABLE(obj)) = (VALUE *)tbl;
}

static inline uint32_t
RCLASS_IV_COUNT(VALUE obj)
{
    RUBY_ASSERT(RB_TYPE_P(obj, RUBY_T_CLASS) || RB_TYPE_P(obj, RUBY_T_MODULE));
    if (rb_shape_obj_too_complex(obj)) {
        uint32_t count;

        // "Too complex" classes could have their IV hash mutated in
        // parallel, so lets lock around getting the hash size.
        RB_VM_LOCK_ENTER();
        {
            count = (uint32_t)rb_st_table_size(RCLASS_IV_HASH(obj));
        }
        RB_VM_LOCK_LEAVE();

        return count;
    }
    else {
        return rb_shape_get_shape_by_id(RCLASS_SHAPE_ID(obj))->next_iv_index;
    }
}

static inline void
RCLASS_SET_M_TBL(VALUE klass, struct rb_id_table *table)
{
    RUBY_ASSERT(!RB_OBJ_PROMOTED(klass));
    RCLASSEXT_M_TBL(RCLASS_EXT(klass)) = table;
}

static inline void
RCLASS_WRITE_M_TBL(VALUE klass, struct rb_id_table *table)
{
    RUBY_ASSERT(!RB_OBJ_PROMOTED(klass));
    RCLASSEXT_M_TBL(RCLASS_EXT_WRITABLE(klass)) = table;
}

static inline void
RCLASS_SET_CONST_TBL(VALUE klass, struct rb_id_table *table, bool shared)
{
    rb_classext_t *ext = RCLASS_EXT(klass);
    RCLASSEXT_CONST_TBL(ext) = table;
    if (shared)
        RCLASSEXT_SHARED_CONST_TBL(ext) = true;
}

static inline void
RCLASS_WRITE_CONST_TBL(VALUE klass, struct rb_id_table *table, bool shared)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    RCLASSEXT_CONST_TBL(ext) = table;
    if (shared)
        RCLASSEXT_SHARED_CONST_TBL(ext) = true;
}

static inline void
RCLASS_WRITE_CALLABLE_M_TBL(VALUE klass, struct rb_id_table *table)
{
    RCLASSEXT_CALLABLE_M_TBL(RCLASS_EXT_WRITABLE(klass)) = table;
}

static inline void
RCLASS_WRITE_CC_TBL(VALUE klass, struct rb_id_table *table)
{
    RCLASSEXT_CC_TBL(RCLASS_EXT_WRITABLE(klass)) = table;
}

static inline void
RCLASS_SET_CVC_TBL(VALUE klass, struct rb_id_table *table)
{
    RCLASSEXT_CVC_TBL(RCLASS_EXT(klass)) = table;
}

static inline void
RCLASS_WRITE_CVC_TBL(VALUE klass, struct rb_id_table *table)
{
    RCLASSEXT_CVC_TBL(RCLASS_EXT_WRITABLE(klass)) = table;
}

static inline void
RCLASS_SET_REFINED_CLASS(VALUE klass, VALUE refined)
{
    RB_OBJ_WRITE(klass, &RCLASSEXT_REFINED_CLASS(RCLASS_EXT(klass)), refined);
}

static inline rb_alloc_func_t
RCLASS_ALLOCATOR(VALUE klass)
{
    if (RCLASS_SINGLETON_P(klass)) {
        return 0;
    }
    return RCLASS_EXT(klass)->as.class.allocator;
}

static inline void
RCLASS_SET_ALLOCATOR(VALUE klass, rb_alloc_func_t allocator)
{
    assert(!RCLASS_SINGLETON_P(klass));
    RCLASS_EXT(klass)->as.class.allocator = allocator; // Allocator is set only on the initial definition
}

static inline void
RCLASS_SET_ORIGIN(VALUE klass, VALUE origin)
{
    rb_classext_t *ext = RCLASS_EXT(klass);
    RB_OBJ_WRITE(klass, &RCLASSEXT_ORIGIN(ext), origin);
    if (klass != origin) RCLASSEXT_ICLASS_IS_ORIGIN(RCLASS_EXT_WRITABLE(origin)) = true;
}

static inline void
RCLASS_WRITE_ORIGIN(VALUE klass, VALUE origin)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    RB_OBJ_WRITE(klass, &RCLASSEXT_ORIGIN(ext), origin);
    if (klass != origin) RCLASSEXT_ICLASS_IS_ORIGIN(RCLASS_EXT_WRITABLE(origin)) = true;
}

static inline void
RICLASS_SET_ORIGIN_SHARED_MTBL(VALUE iclass)
{
    RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(RCLASS_EXT(iclass)) = true;
}

static inline void
RICLASS_WRITE_ORIGIN_SHARED_MTBL(VALUE iclass)
{
    RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(RCLASS_EXT_WRITABLE(iclass)) = true;
}

static inline bool
RICLASS_OWNS_M_TBL_P(VALUE iclass)
{
    rb_classext_t *ext = RCLASS_EXT_READABLE(iclass);
    return RCLASSEXT_ICLASS_IS_ORIGIN(ext) && !RCLASSEXT_ICLASS_ORIGIN_SHARED_MTBL(ext);
}

static inline void
RCLASS_SET_INCLUDER(VALUE iclass, VALUE klass)
{
    RB_OBJ_WRITE(iclass, &RCLASS_INCLUDER(iclass), klass);
}

static inline void
RCLASS_WRITE_SUPERCLASSES(VALUE klass, size_t depth, VALUE *superclasses, bool owns_it, bool with_self)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    RCLASSEXT_SUPERCLASS_DEPTH(ext) = depth;
    RCLASSEXT_SUPERCLASSES(ext) = superclasses;
    RCLASSEXT_SUPERCLASSES_OWNER(ext) = owns_it;
    RCLASSEXT_SUPERCLASSES_WITH_SELF(ext) = with_self;
}

static inline void
RCLASS_SET_SUBCLASSES(VALUE klass, struct rb_subclass_anchor *anchor)
{
    rb_classext_t *ext = RCLASS_EXT(klass);
    RCLASSEXT_SUBCLASSES(ext) = anchor;
}

static inline void
RCLASS_WRITE_NS_SUPER_SUBCLASSES(VALUE klass, rb_ns_subclasses_t *ns_subclasses)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    if (RCLASSEXT_NS_SUPER_SUBCLASSES(ext))
        rb_ns_subclasses_ref_dec(RCLASSEXT_NS_SUPER_SUBCLASSES(ext));
    RCLASSEXT_NS_SUPER_SUBCLASSES(ext) = rb_ns_subclasses_ref_inc(ns_subclasses);
}

static inline void
RCLASS_WRITE_NS_MODULE_SUBCLASSES(VALUE klass, rb_ns_subclasses_t *ns_subclasses)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    if (RCLASSEXT_NS_MODULE_SUBCLASSES(ext))
        rb_ns_subclasses_ref_dec(RCLASSEXT_NS_MODULE_SUBCLASSES(ext));
    RCLASSEXT_NS_MODULE_SUBCLASSES(ext) = rb_ns_subclasses_ref_inc(ns_subclasses);
}

static inline void
RCLASS_SET_CLASSPATH(VALUE klass, VALUE classpath, bool permanent)
{
    rb_classext_t *ext = RCLASS_EXT_READABLE(klass);
    assert(BUILTIN_TYPE(klass) == T_CLASS || BUILTIN_TYPE(klass) == T_MODULE);
    assert(classpath == 0 || BUILTIN_TYPE(classpath) == T_STRING);

    RB_OBJ_WRITE(klass, &(RCLASSEXT_CLASSPATH(ext)), classpath);
    RCLASSEXT_PERMANENT_CLASSPATH(ext) = permanent;
}

static inline void
RCLASS_WRITE_CLASSPATH(VALUE klass, VALUE classpath, bool permanent)
{
    rb_classext_t *ext = RCLASS_EXT_WRITABLE(klass);
    assert(BUILTIN_TYPE(klass) == T_CLASS || BUILTIN_TYPE(klass) == T_MODULE);
    assert(classpath == 0 || BUILTIN_TYPE(classpath) == T_STRING);

    RB_OBJ_WRITE(klass, &(RCLASSEXT_CLASSPATH(ext)), classpath);
    RCLASSEXT_PERMANENT_CLASSPATH(ext) = permanent;
}

static inline VALUE
RCLASS_SET_ATTACHED_OBJECT(VALUE klass, VALUE attached_object)
{
    assert(RCLASS_SINGLETON_P(klass));

    RB_OBJ_WRITE(klass, &RCLASS_EXT(klass)->as.singleton_class.attached_object, attached_object);
    return attached_object;
}

static inline void
RCLASS_SET_MAX_IV_COUNT(VALUE klass, attr_index_t count)
{
    RCLASSEXT_MAX_IV_COUNT(RCLASS_EXT(klass)) = count;
}

static inline void
RCLASS_WRITE_MAX_IV_COUNT(VALUE klass, attr_index_t count)
{
    RCLASSEXT_MAX_IV_COUNT(RCLASS_EXT_WRITABLE(klass)) = count;
}

static inline void
RCLASS_SET_CLONED(VALUE klass, bool cloned)
{
    RCLASSEXT_CLONED(RCLASS_EXT(klass)) = cloned;
}

#endif /* INTERNAL_CLASS_H */
