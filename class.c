/**********************************************************************

  class.c -

  $Author$
  created at: Tue Aug 10 15:05:44 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

/*!
 * \defgroup class Classes and their hierarchy.
 * \par Terminology
 * - class: same as in Ruby.
 * - singleton class: class for a particular object
 * - eigenclass: = singleton class
 * - metaclass: class of a class. metaclass is a kind of singleton class.
 * - metametaclass: class of a metaclass.
 * - meta^(n)-class: class of a meta^(n-1)-class.
 * - attached object: A singleton class knows its unique instance.
 *   The instance is called the attached object for the singleton class.
 * \{
 */

#include "internal.h"
#include "ruby/st.h"
#include "constant.h"
#include "vm_core.h"
#include "id_table.h"
#include <ctype.h>

#define id_attached id__attached__

void
rb_class_subclass_add(VALUE super, VALUE klass)
{
    rb_subclass_entry_t *entry, *head;

    if (super && super != Qundef) {
	entry = ALLOC(rb_subclass_entry_t);
	entry->klass = klass;
	entry->next = NULL;

	head = RCLASS_EXT(super)->subclasses;
	if (head) {
	    entry->next = head;
	    RCLASS_EXT(head->klass)->parent_subclasses = &entry->next;
	}

	RCLASS_EXT(super)->subclasses = entry;
	RCLASS_EXT(klass)->parent_subclasses = &RCLASS_EXT(super)->subclasses;
    }
}

static void
rb_module_add_to_subclasses_list(VALUE module, VALUE iclass)
{
    rb_subclass_entry_t *entry, *head;

    entry = ALLOC(rb_subclass_entry_t);
    entry->klass = iclass;
    entry->next = NULL;

    head = RCLASS_EXT(module)->subclasses;
    if (head) {
	entry->next = head;
	RCLASS_EXT(head->klass)->module_subclasses = &entry->next;
    }

    RCLASS_EXT(module)->subclasses = entry;
    RCLASS_EXT(iclass)->module_subclasses = &RCLASS_EXT(module)->subclasses;
}

void
rb_class_remove_from_super_subclasses(VALUE klass)
{
    rb_subclass_entry_t *entry;

    if (RCLASS_EXT(klass)->parent_subclasses) {
	entry = *RCLASS_EXT(klass)->parent_subclasses;

	*RCLASS_EXT(klass)->parent_subclasses = entry->next;
	if (entry->next) {
	    RCLASS_EXT(entry->next->klass)->parent_subclasses = RCLASS_EXT(klass)->parent_subclasses;
	}
	xfree(entry);
    }

    RCLASS_EXT(klass)->parent_subclasses = NULL;
}

void
rb_class_remove_from_module_subclasses(VALUE klass)
{
    rb_subclass_entry_t *entry;

    if (RCLASS_EXT(klass)->module_subclasses) {
	entry = *RCLASS_EXT(klass)->module_subclasses;
	*RCLASS_EXT(klass)->module_subclasses = entry->next;

	if (entry->next) {
	    RCLASS_EXT(entry->next->klass)->module_subclasses = RCLASS_EXT(klass)->module_subclasses;
	}

	xfree(entry);
    }

    RCLASS_EXT(klass)->module_subclasses = NULL;
}

void
rb_class_foreach_subclass(VALUE klass, void (*f)(VALUE, VALUE), VALUE arg)
{
    rb_subclass_entry_t *cur = RCLASS_EXT(klass)->subclasses;

    /* do not be tempted to simplify this loop into a for loop, the order of
       operations is important here if `f` modifies the linked list */
    while (cur) {
	VALUE curklass = cur->klass;
	cur = cur->next;
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
 * \param flags     initial value for basic.flags of the returned class.
 * \param klass     the class of the returned class.
 * \return          an uninitialized Class object.
 * \pre  \p klass must refer \c Class class or an ancestor of Class.
 * \pre  \code (flags | T_CLASS) != 0  \endcode
 * \post the returned class can safely be \c #initialize 'd.
 *
 * \note this function is not Class#allocate.
 */
static VALUE
class_alloc(VALUE flags, VALUE klass)
{
    NEWOBJ_OF(obj, struct RClass, klass, (flags & T_MASK) | FL_PROMOTED1 /* start from age == 2 */ | (RGENGC_WB_PROTECTED_CLASS ? FL_WB_PROTECTED : 0));
    obj->ptr = ZALLOC(rb_classext_t);
    /* ZALLOC
      RCLASS_IV_TBL(obj) = 0;
      RCLASS_CONST_TBL(obj) = 0;
      RCLASS_M_TBL(obj) = 0;
      RCLASS_IV_INDEX_TBL(obj) = 0;
      RCLASS_SET_SUPER((VALUE)obj, 0);
      RCLASS_EXT(obj)->subclasses = NULL;
      RCLASS_EXT(obj)->parent_subclasses = NULL;
      RCLASS_EXT(obj)->module_subclasses = NULL;
     */
    RCLASS_SET_ORIGIN((VALUE)obj, (VALUE)obj);
    RCLASS_SERIAL(obj) = rb_next_class_serial();
    RB_OBJ_WRITE(obj, &RCLASS_REFINED_CLASS(obj), Qnil);
    RCLASS_EXT(obj)->allocator = 0;

    return (VALUE)obj;
}

static void
RCLASS_M_TBL_INIT(VALUE c)
{
    RCLASS_M_TBL(c) = rb_id_table_create(0);
}

/*!
 * A utility function that wraps class_alloc.
 *
 * allocates a class and initializes safely.
 * \param super     a class from which the new class derives.
 * \return          a class object.
 * \pre  \a super must be a class.
 * \post the metaclass of the new class is Class.
 */
VALUE
rb_class_boot(VALUE super)
{
    VALUE klass = class_alloc(T_CLASS, rb_cClass);

    RCLASS_SET_SUPER(klass, super);
    RCLASS_M_TBL_INIT(klass);

    OBJ_INFECT(klass, super);
    return (VALUE)klass;
}


/*!
 * Ensures a class can be derived from super.
 *
 * \param super a reference to an object.
 * \exception TypeError if \a super is not a Class or \a super is a singleton class.
 */
void
rb_check_inheritable(VALUE super)
{
    if (!RB_TYPE_P(super, T_CLASS)) {
	rb_raise(rb_eTypeError, "superclass must be a Class (%"PRIsVALUE" given)",
		 rb_obj_class(super));
    }
    if (RBASIC(super)->flags & FL_SINGLETON) {
	rb_raise(rb_eTypeError, "can't make subclass of singleton class");
    }
    if (super == rb_cClass) {
	rb_raise(rb_eTypeError, "can't make subclass of Class");
    }
}


/*!
 * Creates a new class.
 * \param super     a class from which the new class derives.
 * \exception TypeError \a super is not inheritable.
 * \exception TypeError \a super is the Class class.
 */
VALUE
rb_class_new(VALUE super)
{
    Check_Type(super, T_CLASS);
    rb_check_inheritable(super);
    return rb_class_boot(super);
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
    if (FL_TEST(orig, FL_SINGLETON)) {
	rb_raise(rb_eTypeError, "can't copy singleton class");
    }
}

/* :nodoc: */
VALUE
rb_mod_init_copy(VALUE clone, VALUE orig)
{
    /* cloned flag is refer at constant inline cache
     * see vm_get_const_key_cref() in vm_insnhelper.c
     */
    FL_SET(clone, RCLASS_CLONED);
    FL_SET(orig , RCLASS_CLONED);

    if (RB_TYPE_P(clone, T_CLASS)) {
	class_init_copy_check(clone, orig);
    }
    if (!OBJ_INIT_COPY(clone, orig)) return clone;
    if (!FL_TEST(CLASS_OF(clone), FL_SINGLETON)) {
	RBASIC_SET_CLASS(clone, rb_singleton_class_clone(orig));
	rb_singleton_class_attached(RBASIC(clone)->klass, (VALUE)clone);
    }
    RCLASS_SET_SUPER(clone, RCLASS_SUPER(orig));
    RCLASS_EXT(clone)->allocator = RCLASS_EXT(orig)->allocator;
    if (RCLASS_IV_TBL(clone)) {
	st_free_table(RCLASS_IV_TBL(clone));
	RCLASS_IV_TBL(clone) = 0;
    }
    if (RCLASS_CONST_TBL(clone)) {
	rb_free_const_table(RCLASS_CONST_TBL(clone));
	RCLASS_CONST_TBL(clone) = 0;
    }
    RCLASS_M_TBL(clone) = 0;
    if (RCLASS_IV_TBL(orig)) {
	st_data_t id;

	rb_iv_tbl_copy(clone, orig);
	CONST_ID(id, "__tmp_classpath__");
	st_delete(RCLASS_IV_TBL(clone), &id, 0);
	CONST_ID(id, "__classpath__");
	st_delete(RCLASS_IV_TBL(clone), &id, 0);
	CONST_ID(id, "__classid__");
	st_delete(RCLASS_IV_TBL(clone), &id, 0);
    }
    if (RCLASS_CONST_TBL(orig)) {
	struct clone_const_arg arg;

	arg.tbl = RCLASS_CONST_TBL(clone) = rb_id_table_create(0);
	arg.klass = clone;
	rb_id_table_foreach(RCLASS_CONST_TBL(orig), clone_const_i, &arg);
    }
    if (RCLASS_M_TBL(orig)) {
	struct clone_method_arg arg;
	arg.old_klass = orig;
	arg.new_klass = clone;
	RCLASS_M_TBL_INIT(clone);
	rb_id_table_foreach(RCLASS_M_TBL(orig), clone_method_i, &arg);
    }

    return clone;
}

VALUE
rb_singleton_class_clone(VALUE obj)
{
    return rb_singleton_class_clone_and_attach(obj, Qundef);
}

VALUE
rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach)
{
    const VALUE klass = RBASIC(obj)->klass;

    if (!FL_TEST(klass, FL_SINGLETON))
	return klass;
    else {
	/* copy singleton(unnamed) class */
	VALUE clone = class_alloc(RBASIC(klass)->flags, 0);

	if (BUILTIN_TYPE(obj) == T_CLASS) {
	    RBASIC_SET_CLASS(clone, clone);
	}
	else {
	    RBASIC_SET_CLASS(clone, rb_singleton_class_clone(klass));
	}

	RCLASS_SET_SUPER(clone, RCLASS_SUPER(klass));
	RCLASS_EXT(clone)->allocator = RCLASS_EXT(klass)->allocator;
	if (RCLASS_IV_TBL(klass)) {
	    rb_iv_tbl_copy(clone, klass);
	}
	if (RCLASS_CONST_TBL(klass)) {
	    struct clone_const_arg arg;
	    arg.tbl = RCLASS_CONST_TBL(clone) = rb_id_table_create(0);
	    arg.klass = clone;
	    rb_id_table_foreach(RCLASS_CONST_TBL(klass), clone_const_i, &arg);
	}
	if (attach != Qundef) {
	    rb_singleton_class_attached(clone, attach);
	}
	RCLASS_M_TBL_INIT(clone);
	{
	    struct clone_method_arg arg;
	    arg.old_klass = klass;
	    arg.new_klass = clone;
	    rb_id_table_foreach(RCLASS_M_TBL(klass), clone_method_i, &arg);
	}
	rb_singleton_class_attached(RBASIC(clone)->klass, clone);
	FL_SET(clone, FL_SINGLETON);

	return clone;
    }
}

/*!
 * Attach a object to a singleton class.
 * @pre \a klass is the singleton class of \a obj.
 */
void
rb_singleton_class_attached(VALUE klass, VALUE obj)
{
    if (FL_TEST(klass, FL_SINGLETON)) {
	if (!RCLASS_IV_TBL(klass)) {
	    RCLASS_IV_TBL(klass) = st_init_numtable();
	}
	rb_class_ivar_set(klass, id_attached, obj);
    }
}



#define METACLASS_OF(k) RBASIC(k)->klass
#define SET_METACLASS_OF(k, cls) RBASIC_SET_CLASS(k, cls)

/*!
 * whether k is a meta^(n)-class of Class class
 * @retval 1 if \a k is a meta^(n)-class of Class class (n >= 0)
 * @retval 0 otherwise
 */
#define META_CLASS_OF_CLASS_CLASS_P(k)  (METACLASS_OF(k) == (k))

static int
rb_singleton_class_has_metaclass_p(VALUE sklass)
{
    return rb_attr_get(METACLASS_OF(sklass), id_attached) == sklass;
}

int
rb_singleton_class_internal_p(VALUE sklass)
{
    return (RB_TYPE_P(rb_attr_get(sklass, id_attached), T_CLASS) &&
	    !rb_singleton_class_has_metaclass_p(sklass));
}

/*!
 * whether k has a metaclass
 * @retval 1 if \a k has a metaclass
 * @retval 0 otherwise
 */
#define HAVE_METACLASS_P(k) \
    (FL_TEST(METACLASS_OF(k), FL_SINGLETON) && \
     rb_singleton_class_has_metaclass_p(k))

/*!
 * ensures \a klass belongs to its own eigenclass.
 * @return the eigenclass of \a klass
 * @post \a klass belongs to the returned eigenclass.
 *       i.e. the attached object of the eigenclass is \a klass.
 * @note this macro creates a new eigenclass if necessary.
 */
#define ENSURE_EIGENCLASS(klass) \
    (HAVE_METACLASS_P(klass) ? METACLASS_OF(klass) : make_metaclass(klass))


/*!
 * Creates a metaclass of \a klass
 * \param klass     a class
 * \return          created metaclass for the class
 * \pre \a klass is a Class object
 * \pre \a klass has no singleton class.
 * \post the class of \a klass is the returned class.
 * \post the returned class is meta^(n+1)-class when \a klass is a meta^(n)-klass for n >= 0
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

    OBJ_INFECT(metaclass, RCLASS_SUPER(metaclass));

    return metaclass;
}

/*!
 * Creates a singleton class for \a obj.
 * \pre \a obj must not a immediate nor a special const.
 * \pre \a obj must not a Class object.
 * \pre \a obj has no singleton class.
 */
static inline VALUE
make_singleton_class(VALUE obj)
{
    VALUE orig_class = RBASIC(obj)->klass;
    VALUE klass = rb_class_boot(orig_class);

    FL_SET(klass, FL_SINGLETON);
    RBASIC_SET_CLASS(obj, klass);
    rb_singleton_class_attached(klass, obj);

    SET_METACLASS_OF(klass, METACLASS_OF(rb_class_real(orig_class)));
    return klass;
}


static VALUE
boot_defclass(const char *name, VALUE super)
{
    VALUE obj = rb_class_boot(super);
    ID id = rb_intern(name);

    rb_const_set((rb_cObject ? rb_cObject : obj), id, obj);
    rb_vm_add_root_module(id, obj);
    return obj;
}

void
Init_class_hierarchy(void)
{
    rb_cBasicObject = boot_defclass("BasicObject", 0);
    rb_cObject = boot_defclass("Object", rb_cBasicObject);
    rb_gc_register_mark_object(rb_cObject);

    /* resolve class name ASAP for order-independence */
    rb_set_class_path_string(rb_cObject, rb_cObject, rb_fstring_lit("Object"));

    rb_cModule = boot_defclass("Module", rb_cObject);
    rb_cClass =  boot_defclass("Class",  rb_cModule);

    rb_const_set(rb_cObject, rb_intern_const("BasicObject"), rb_cBasicObject);
    RBASIC_SET_CLASS(rb_cClass, rb_cClass);
    RBASIC_SET_CLASS(rb_cModule, rb_cClass);
    RBASIC_SET_CLASS(rb_cObject, rb_cClass);
    RBASIC_SET_CLASS(rb_cBasicObject, rb_cClass);
}


/*!
 * \internal
 * Creates a new *singleton class* for an object.
 *
 * \pre \a obj has no singleton class.
 * \note DO NOT USE the function in an extension libraries. Use \ref rb_singleton_class.
 * \param obj     An object.
 * \param unused  ignored.
 * \return        The singleton class of the object.
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


/*!
 * Defines a new class.
 * \param id     ignored
 * \param super  A class from which the new class will derive. NULL means \c Object class.
 * \return       the created class
 * \throw TypeError if super is not a \c Class object.
 *
 * \note the returned class will not be associated with \a id.
 *       You must explicitly set a class name if necessary.
 */
VALUE
rb_define_class_id(ID id, VALUE super)
{
    VALUE klass;

    if (!super) super = rb_cObject;
    klass = rb_class_new(super);
    rb_make_metaclass(klass, RBASIC(super)->klass);

    return klass;
}


/*!
 * Calls Class#inherited.
 * \param super  A class which will be called #inherited.
 *               NULL means Object class.
 * \param klass  A Class object which derived from \a super
 * \return the value \c Class#inherited's returns
 * \pre Each of \a super and \a klass must be a \c Class object.
 */
MJIT_FUNC_EXPORTED VALUE
rb_class_inherited(VALUE super, VALUE klass)
{
    ID inherited;
    if (!super) super = rb_cObject;
    CONST_ID(inherited, "inherited");
    return rb_funcall(super, inherited, 1, klass);
}



/*!
 * Defines a top-level class.
 * \param name   name of the class
 * \param super  a class from which the new class will derive.
 * \return the created class
 * \throw TypeError if the constant name \a name is already taken but
 *                  the constant is not a \c Class.
 * \throw TypeError if the class is already defined but the class can not
 *                  be reopened because its superclass is not \a super.
 * \throw ArgumentError if the \a super is NULL.
 * \post top-level constant named \a name refers the returned class.
 *
 * \note if a class named \a name is already defined and its superclass is
 *       \a super, the function just returns the defined class.
 */
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
        rb_vm_add_root_module(id, klass);
	return klass;
    }
    if (!super) {
	rb_raise(rb_eArgError, "no super class for `%s'", name);
    }
    klass = rb_define_class_id(id, super);
    rb_vm_add_root_module(id, klass);
    rb_const_set(rb_cObject, id, klass);
    rb_class_inherited(super, klass);

    return klass;
}


/*!
 * Defines a class under the namespace of \a outer.
 * \param outer  a class which contains the new class.
 * \param name   name of the new class
 * \param super  a class from which the new class will derive.
 *               NULL means \c Object class.
 * \return the created class
 * \throw TypeError if the constant name \a name is already taken but
 *                  the constant is not a \c Class.
 * \throw TypeError if the class is already defined but the class can not
 *                  be reopened because its superclass is not \a super.
 * \post top-level constant named \a name refers the returned class.
 *
 * \note if a class named \a name is already defined and its superclass is
 *       \a super, the function just returns the defined class.
 */
VALUE
rb_define_class_under(VALUE outer, const char *name, VALUE super)
{
    return rb_define_class_id_under(outer, rb_intern(name), super);
}


/*!
 * Defines a class under the namespace of \a outer.
 * \param outer  a class which contains the new class.
 * \param id     name of the new class
 * \param super  a class from which the new class will derive.
 *               NULL means \c Object class.
 * \return the created class
 * \throw TypeError if the constant name \a name is already taken but
 *                  the constant is not a \c Class.
 * \throw TypeError if the class is already defined but the class can not
 *                  be reopened because its superclass is not \a super.
 * \post top-level constant named \a name refers the returned class.
 *
 * \note if a class named \a name is already defined and its superclass is
 *       \a super, the function just returns the defined class.
 */
VALUE
rb_define_class_id_under(VALUE outer, ID id, VALUE super)
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
        /* Class may have been defined in Ruby and not pin-rooted */
        rb_vm_add_root_module(id, klass);

	return klass;
    }
    if (!super) {
	rb_raise(rb_eArgError, "no super class for `%"PRIsVALUE"::%"PRIsVALUE"'",
		 rb_class_path(outer), rb_id2str(id));
    }
    klass = rb_define_class_id(id, super);
    rb_set_class_path_string(klass, outer, rb_id2str(id));
    rb_const_set(outer, id, klass);
    rb_class_inherited(super, klass);
    rb_vm_add_root_module(id, klass);
    rb_gc_register_mark_object(klass);

    return klass;
}

VALUE
rb_module_new(void)
{
    VALUE mdl = class_alloc(T_MODULE, rb_cModule);
    RCLASS_M_TBL_INIT(mdl);
    return (VALUE)mdl;
}

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
        rb_vm_add_root_module(id, module);
	return module;
    }
    module = rb_define_module_id(id);
    rb_vm_add_root_module(id, module);
    rb_gc_register_mark_object(module);
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
	return module;
    }
    module = rb_define_module_id(id);
    rb_const_set(outer, id, module);
    rb_set_class_path_string(module, outer, rb_id2str(id));
    rb_gc_register_mark_object(module);

    return module;
}

VALUE
rb_include_class_new(VALUE module, VALUE super)
{
    VALUE klass = class_alloc(T_ICLASS, rb_cClass);

    if (BUILTIN_TYPE(module) == T_ICLASS) {
	module = RBASIC(module)->klass;
    }
    if (!RCLASS_IV_TBL(module)) {
	RCLASS_IV_TBL(module) = st_init_numtable();
    }
    if (!RCLASS_CONST_TBL(module)) {
	RCLASS_CONST_TBL(module) = rb_id_table_create(0);
    }
    RCLASS_IV_TBL(klass) = RCLASS_IV_TBL(module);
    RCLASS_CONST_TBL(klass) = RCLASS_CONST_TBL(module);

    RCLASS_M_TBL(OBJ_WB_UNPROTECT(klass)) =
      RCLASS_M_TBL(OBJ_WB_UNPROTECT(RCLASS_ORIGIN(module))); /* TODO: unprotected? */

    RCLASS_SET_SUPER(klass, super);
    if (RB_TYPE_P(module, T_ICLASS)) {
	RBASIC_SET_CLASS(klass, RBASIC(module)->klass);
    }
    else {
	RBASIC_SET_CLASS(klass, module);
    }
    OBJ_INFECT(klass, module);
    OBJ_INFECT(klass, super);

    return (VALUE)klass;
}

static int include_modules_at(const VALUE klass, VALUE c, VALUE module, int search_super);

static void
ensure_includable(VALUE klass, VALUE module)
{
    rb_class_modify_check(klass);
    Check_Type(module, T_MODULE);
    if (!NIL_P(rb_refinement_module_get_refined_class(module))) {
	rb_raise(rb_eArgError, "refinement module is not allowed");
    }
    OBJ_INFECT(klass, module);
}

void
rb_include_module(VALUE klass, VALUE module)
{
    int changed = 0;

    ensure_includable(klass, module);

    changed = include_modules_at(klass, RCLASS_ORIGIN(klass), module, TRUE);
    if (changed < 0)
	rb_raise(rb_eArgError, "cyclic include detected");
}

static enum rb_id_table_iterator_result
add_refined_method_entry_i(ID key, VALUE value, void *data)
{
    rb_add_refined_method_entry((VALUE)data, key);
    return ID_TABLE_CONTINUE;
}

static int
include_modules_at(const VALUE klass, VALUE c, VALUE module, int search_super)
{
    VALUE p, iclass;
    int method_changed = 0, constant_changed = 0;
    struct rb_id_table *const klass_m_tbl = RCLASS_M_TBL(RCLASS_ORIGIN(klass));

    while (module) {
	int superclass_seen = FALSE;
	struct rb_id_table *tbl;

	if (RCLASS_ORIGIN(module) != module)
	    goto skip;
	if (klass_m_tbl && klass_m_tbl == RCLASS_M_TBL(module))
	    return -1;
	/* ignore if the module included already in superclasses */
	for (p = RCLASS_SUPER(klass); p; p = RCLASS_SUPER(p)) {
	    int type = BUILTIN_TYPE(p);
	    if (type == T_ICLASS) {
		if (RCLASS_M_TBL(p) == RCLASS_M_TBL(module)) {
		    if (!superclass_seen) {
			c = p;  /* move insertion point */
		    }
		    goto skip;
		}
	    }
	    else if (type == T_CLASS) {
		if (!search_super) break;
		superclass_seen = TRUE;
	    }
	}
	iclass = rb_include_class_new(module, RCLASS_SUPER(c));
	c = RCLASS_SET_SUPER(c, iclass);

	{
	    VALUE m = module;
	    if (BUILTIN_TYPE(m) == T_ICLASS) m = RBASIC(m)->klass;
	    rb_module_add_to_subclasses_list(m, iclass);
	}

	if (FL_TEST(klass, RMODULE_IS_REFINEMENT)) {
	    VALUE refined_class =
		rb_refinement_module_get_refined_class(klass);

	    rb_id_table_foreach(RMODULE_M_TBL(module), add_refined_method_entry_i, (void *)refined_class);
	    FL_SET(c, RMODULE_INCLUDED_INTO_REFINEMENT);
	}

	tbl = RMODULE_M_TBL(module);
	if (tbl && rb_id_table_size(tbl)) method_changed = 1;

	tbl = RMODULE_CONST_TBL(module);
	if (tbl && rb_id_table_size(tbl)) constant_changed = 1;
      skip:
	module = RCLASS_SUPER(module);
    }

    if (method_changed) rb_clear_method_cache_by_class(klass);
    if (constant_changed) rb_clear_constant_cache();

    return method_changed;
}

static enum rb_id_table_iterator_result
move_refined_method(ID key, VALUE value, void *data)
{
    rb_method_entry_t *me = (rb_method_entry_t *) value;
    VALUE klass = (VALUE)data;
    struct rb_id_table *tbl = RCLASS_M_TBL(klass);

    if (me->def->type == VM_METHOD_TYPE_REFINED) {
	if (me->def->body.refined.orig_me) {
	    const rb_method_entry_t *orig_me = me->def->body.refined.orig_me, *new_me;
	    RB_OBJ_WRITE(me, &me->def->body.refined.orig_me, NULL);
	    new_me = rb_method_entry_clone(me);
	    rb_id_table_insert(tbl, key, (VALUE)new_me);
	    RB_OBJ_WRITTEN(klass, Qundef, new_me);
	    rb_method_entry_copy(me, orig_me);
	    return ID_TABLE_CONTINUE;
	}
	else {
	    rb_id_table_insert(tbl, key, (VALUE)me);
	    return ID_TABLE_DELETE;
	}
    }
    else {
	return ID_TABLE_CONTINUE;
    }
}

void
rb_prepend_module(VALUE klass, VALUE module)
{
    VALUE origin;
    int changed = 0;

    ensure_includable(klass, module);

    origin = RCLASS_ORIGIN(klass);
    if (origin == klass) {
	origin = class_alloc(T_ICLASS, klass);
	OBJ_WB_UNPROTECT(origin); /* TODO: conservative shading. Need more survey. */
	RCLASS_SET_SUPER(origin, RCLASS_SUPER(klass));
	RCLASS_SET_SUPER(klass, origin);
	RCLASS_SET_ORIGIN(klass, origin);
	RCLASS_M_TBL(origin) = RCLASS_M_TBL(klass);
	RCLASS_M_TBL_INIT(klass);
	rb_id_table_foreach(RCLASS_M_TBL(origin), move_refined_method, (void *)klass);
    }
    changed = include_modules_at(klass, klass, module, FALSE);
    if (changed < 0)
	rb_raise(rb_eArgError, "cyclic prepend detected");
    if (changed) {
	rb_vm_check_redefinition_by_prepend(klass);
    }
}

/*
 *  call-seq:
 *     mod.included_modules -> array
 *
 *  Returns the list of modules included in <i>mod</i>.
 *
 *     module Mixin
 *     end
 *
 *     module Outer
 *       include Mixin
 *     end
 *
 *     Mixin.included_modules   #=> []
 *     Outer.included_modules   #=> [Mixin]
 */

VALUE
rb_mod_included_modules(VALUE mod)
{
    VALUE ary = rb_ary_new();
    VALUE p;
    VALUE origin = RCLASS_ORIGIN(mod);

    for (p = RCLASS_SUPER(mod); p; p = RCLASS_SUPER(p)) {
	if (p != origin && BUILTIN_TYPE(p) == T_ICLASS) {
	    VALUE m = RBASIC(p)->klass;
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
 *  Returns <code>true</code> if <i>module</i> is included in
 *  <i>mod</i> or one of <i>mod</i>'s ancestors.
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
	if (BUILTIN_TYPE(p) == T_ICLASS) {
	    if (RBASIC(p)->klass == mod2) return Qtrue;
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

    for (p = mod; p; p = RCLASS_SUPER(p)) {
	if (BUILTIN_TYPE(p) == T_ICLASS) {
	    rb_ary_push(ary, RBASIC(p)->klass);
	}
	else if (p == RCLASS_ORIGIN(p)) {
	    rb_ary_push(ary, p);
	}
    }
    return ary;
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
ins_methods_prot_i(st_data_t name, st_data_t type, st_data_t ary)
{
    if ((rb_method_visibility_t)type == METHOD_VISI_PROTECTED) {
	ins_methods_push(name, ary);
    }
    return ST_CONTINUE;
}

static int
ins_methods_priv_i(st_data_t name, st_data_t type, st_data_t ary)
{
    if ((rb_method_visibility_t)type == METHOD_VISI_PRIVATE) {
	ins_methods_push(name, ary);
    }
    return ST_CONTINUE;
}

static int
ins_methods_pub_i(st_data_t name, st_data_t type, st_data_t ary)
{
    if ((rb_method_visibility_t)type == METHOD_VISI_PUBLIC) {
	ins_methods_push(name, ary);
    }
    return ST_CONTINUE;
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
    if (FL_TEST(mod, FL_SINGLETON)) return true;
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
    ary = rb_ary_new();
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
    if (RB_TYPE_P(obj, T_CLASS) && FL_TEST(obj, FL_SINGLETON)) {
        rb_singleton_class(obj);
    }
    klass = CLASS_OF(obj);
    origin = RCLASS_ORIGIN(klass);
    me_arg.list = st_init_numtable();
    me_arg.recur = recur;
    if (klass && FL_TEST(klass, FL_SINGLETON)) {
	if ((mtbl = RCLASS_M_TBL(origin)) != 0) rb_id_table_foreach(mtbl, method_entry_i, &me_arg);
	klass = RCLASS_SUPER(klass);
    }
    if (recur) {
	while (klass && (FL_TEST(klass, FL_SINGLETON) || RB_TYPE_P(klass, T_ICLASS))) {
	    if (klass != origin && (mtbl = RCLASS_M_TBL(klass)) != 0) rb_id_table_foreach(mtbl, method_entry_i, &me_arg);
	    klass = RCLASS_SUPER(klass);
	}
    }
    ary = rb_ary_new();
    st_foreach(me_arg.list, ins_methods_i, ary);
    st_free_table(me_arg.list);

    return ary;
}

/*!
 * \}
 */
/*!
 * \defgroup defmethod Defining methods
 * There are some APIs to define a method from C.
 * These API takes a C function as a method body.
 *
 * \par Method body functions
 * Method body functions must return a VALUE and
 * can be one of the following form:
 * <dl>
 * <dt>Fixed number of parameters</dt>
 * <dd>
 *     This form is a normal C function, excepting it takes
 *     a receiver object as the first argument.
 *
 *     \code
 *     static VALUE my_method(VALUE self, VALUE x, VALUE y);
 *     \endcode
 * </dd>
 * <dt>argc and argv style</dt>
 * <dd>
 *     This form takes three parameters: \a argc, \a argv and \a self.
 *     \a self is the receiver. \a argc is the number of arguments.
 *     \a argv is a pointer to an array of the arguments.
 *
 *     \code
 *     static VALUE my_method(int argc, VALUE *argv, VALUE self);
 *     \endcode
 * </dd>
 * <dt>Ruby array style</dt>
 * <dd>
 *     This form takes two parameters: self and args.
 *     \a self is the receiver. \a args is an Array object which
 *     contains the arguments.
 *
 *     \code
 *     static VALUE my_method(VALUE self, VALUE args);
 *     \endcode
 * </dd>
 *
 * \par Number of parameters
 * Method defining APIs takes the number of parameters which the
 * method will takes. This number is called \a argc.
 * \a argc can be:
 * <dl>
 * <dt>zero or positive number</dt>
 * <dd>This means the method body function takes a fixed number of parameters</dd>
 * <dt>-1</dt>
 * <dd>This means the method body function is "argc and argv" style.</dd>
 * <dt>-2</dt>
 * <dd>This means the method body function is "self and args" style.</dd>
 * </dl>
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

#define SPECIAL_SINGLETON(x,c) do {\
    if (obj == (x)) {\
	return (c);\
    }\
} while (0)

static inline VALUE
special_singleton_class_of(VALUE obj)
{
    SPECIAL_SINGLETON(Qnil, rb_cNilClass);
    SPECIAL_SINGLETON(Qfalse, rb_cFalseClass);
    SPECIAL_SINGLETON(Qtrue, rb_cTrueClass);
    return Qnil;
}

VALUE
rb_special_singleton_class(VALUE obj)
{
    return special_singleton_class_of(obj);
}

/*!
 * \internal
 * Returns the singleton class of \a obj. Creates it if necessary.
 *
 * \note DO NOT expose the returned singleton class to
 *       outside of class.c.
 *       Use \ref rb_singleton_class instead for
 *       consistency of the metaclass hierarchy.
 */
static VALUE
singleton_class_of(VALUE obj)
{
    VALUE klass;

    if (FIXNUM_P(obj) || FLONUM_P(obj) || STATIC_SYM_P(obj)) {
      no_singleton:
	rb_raise(rb_eTypeError, "can't define singleton");
    }
    if (SPECIAL_CONST_P(obj)) {
	klass = special_singleton_class_of(obj);
	if (NIL_P(klass))
	    rb_bug("unknown immediate %p", (void *)obj);
	return klass;
    }
    else {
	switch (BUILTIN_TYPE(obj)) {
	  case T_FLOAT: case T_BIGNUM: case T_SYMBOL:
	    goto no_singleton;
	  case T_STRING:
	    if (FL_TEST_RAW(obj, RSTRING_FSTR)) goto no_singleton;
	    break;
	}
    }

    klass = RBASIC(obj)->klass;
    if (!(FL_TEST(klass, FL_SINGLETON) &&
	  rb_ivar_get(klass, id_attached) == obj)) {
	rb_serial_t serial = RCLASS_SERIAL(klass);
	klass = rb_make_metaclass(obj, klass);
	RCLASS_SERIAL(klass) = serial;
    }

    if (OBJ_TAINTED(obj)) {
	OBJ_TAINT(klass);
    }
    else {
	FL_UNSET(klass, FL_TAINT);
    }
    RB_FL_SET_RAW(klass, RB_OBJ_FROZEN_RAW(obj));

    return klass;
}

void
rb_freeze_singleton_class(VALUE x)
{
    /* should not propagate to meta-meta-class, and so on */
    if (!(RBASIC(x)->flags & FL_SINGLETON)) {
	VALUE klass = RBASIC_CLASS(x);
	if (klass && (klass = RCLASS_ORIGIN(klass)) != 0 &&
	    FL_TEST(klass, (FL_SINGLETON|FL_FREEZE)) == FL_SINGLETON) {
	    OBJ_FREEZE_RAW(klass);
	}
    }
}

/*!
 * Returns the singleton class of \a obj, or nil if obj is not a
 * singleton object.
 *
 * \param obj an arbitrary object.
 * \return the singleton class or nil.
 */
VALUE
rb_singleton_class_get(VALUE obj)
{
    VALUE klass;

    if (SPECIAL_CONST_P(obj)) {
	return rb_special_singleton_class(obj);
    }
    klass = RBASIC(obj)->klass;
    if (!FL_TEST(klass, FL_SINGLETON)) return Qnil;
    if (rb_ivar_get(klass, id_attached) != obj) return Qnil;
    return klass;
}

/*!
 * Returns the singleton class of \a obj. Creates it if necessary.
 *
 * \param obj an arbitrary object.
 * \throw TypeError if \a obj is a Integer or a Symbol.
 * \return the singleton class.
 *
 * \post \a obj has its own singleton class.
 * \post if \a obj is a class,
 *       the returned singleton class also has its own
 *       singleton class in order to keep consistency of the
 *       inheritance structure of metaclasses.
 * \note a new singleton class will be created
 *       if \a obj does not have it.
 * \note the singleton classes for nil, true and false are:
 *       NilClass, TrueClass and FalseClass.
 */
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
/*!
 * Defines a singleton method for \a obj.
 * \param obj    an arbitrary object
 * \param name   name of the singleton method
 * \param func   the method body
 * \param argc   the number of parameters, or -1 or -2. see \ref defmethod.
 */
void
rb_define_singleton_method(VALUE obj, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_method(singleton_class_of(obj), name, func, argc);
}

#ifdef rb_define_module_function
#undef rb_define_module_function
#endif
/*!
 * Defines a module function for \a module.
 * \param module  an module or a class.
 * \param name    name of the function
 * \param func    the method body
 * \param argc    the number of parameters, or -1 or -2. see \ref defmethod.
 */
void
rb_define_module_function(VALUE module, const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_private_method(module, name, func, argc);
    rb_define_singleton_method(module, name, func, argc);
}

#ifdef rb_define_global_function
#undef rb_define_global_function
#endif
/*!
 * Defines a global function
 * \param name    name of the function
 * \param func    the method body
 * \param argc    the number of parameters, or -1 or -2. see \ref defmethod.
 */
void
rb_define_global_function(const char *name, VALUE (*func)(ANYARGS), int argc)
{
    rb_define_module_function(rb_mKernel, name, func, argc);
}


/*!
 * Defines an alias of a method.
 * \param klass  the class which the original method belongs to
 * \param name1  a new name for the method
 * \param name2  the original name of the method
 */
void
rb_define_alias(VALUE klass, const char *name1, const char *name2)
{
    rb_alias(klass, rb_intern(name1), rb_intern(name2));
}

/*!
 * Defines (a) public accessor method(s) for an attribute.
 * \param klass  the class which the attribute will belongs to
 * \param name   name of the attribute
 * \param read   a getter method for the attribute will be defined if \a read is non-zero.
 * \param write  a setter method for the attribute will be defined if \a write is non-zero.
 */
void
rb_define_attr(VALUE klass, const char *name, int read, int write)
{
    rb_attr(klass, rb_intern(name), read, write, FALSE);
}

MJIT_FUNC_EXPORTED VALUE
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
	    if (NIL_P(missing)) missing = rb_ary_tmp_new(1);
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
    int argc;
    const VALUE *argv;
    va_list vargs;
    int f_var;
    int f_hash;
    int f_block;
    int n_lead;
    int n_opt;
    int n_trail;
    int n_mand;
    int argi;
    int last_idx;
    VALUE hash;
    VALUE last_hash;
    VALUE *tmp_buffer;
};

static void
rb_scan_args_parse(int kw_flag, int argc, const VALUE *argv, const char *fmt, struct rb_scan_args_t *arg)
{
    const char *p = fmt;
    VALUE *tmp_buffer = arg->tmp_buffer;
    int keyword_given = 0;
    int empty_keyword_given = 0;
    int last_hash_keyword = 0;

    memset(arg, 0, sizeof(*arg));
    arg->last_idx = -1;
    arg->hash = Qnil;

    switch (kw_flag) {
      case RB_SCAN_ARGS_PASS_CALLED_KEYWORDS:
        if (!(keyword_given = rb_keyword_given_p())) {
            empty_keyword_given = rb_empty_keyword_given_p();
        }
        break;
      case RB_SCAN_ARGS_KEYWORDS:
        keyword_given = 1;
        break;
      case RB_SCAN_ARGS_EMPTY_KEYWORDS:
        empty_keyword_given = 1;
        break;
      case RB_SCAN_ARGS_LAST_HASH_KEYWORDS:
        last_hash_keyword = 1;
        break;
    }

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
    arg->n_mand = arg->n_lead + arg->n_trail;

    /* capture an option hash - phase 1: pop */
    /* Ignore final positional hash if empty keywords given */
    if (argc > 0 && !(arg->f_hash && empty_keyword_given)) {
        VALUE last = argv[argc - 1];

        if (arg->f_hash && arg->n_mand < argc) {
            if (keyword_given) {
                if (!RB_TYPE_P(last, T_HASH)) {
                    rb_warn("Keyword flag set when calling rb_scan_args, but last entry is not a hash");
                }
                else {
                    arg->hash = last;
                }
            }
            else if (NIL_P(last)) {
                /* For backwards compatibility, nil is taken as an empty
                   option hash only if it is not ambiguous; i.e. '*' is
                   not specified and arguments are given more than sufficient.
                   This will be removed in Ruby 3. */
                if (!arg->f_var && arg->n_mand + arg->n_opt < argc) {
                    rb_warn("The last argument is nil, treating as empty keywords");
                    argc--;
                }
            }
            else {
                arg->hash = rb_check_hash_type(last);
            }

            /* Ruby 3: Remove if branch, as it will not attempt to split hashes */
            if (!NIL_P(arg->hash)) {
                VALUE opts = rb_extract_keywords(&arg->hash);

                if (!(arg->last_hash = arg->hash)) {
                    if (!keyword_given && !last_hash_keyword) {
                        /* Warn if treating positional as keyword, as in Ruby 3,
                           this will be an error */
                        rb_warn("The last argument is used as the keyword parameter");
                    }
                    argc--;
                }
                else {
                    /* Warn if splitting either positional hash to keywords or keywords
                       to positional hash, as in Ruby 3, no splitting will be done */
                    rb_warn("The last argument is split into positional and keyword parameters");
                    arg->last_idx = argc - 1;
                }
                arg->hash = opts ? opts : Qnil;
            }
        }
        else if (arg->f_hash && keyword_given && arg->n_mand == argc) {
            /* Warn if treating keywords as positional, as in Ruby 3, this will be an error */
            rb_warn("The keyword argument is passed as the last hash parameter");
        }
    }
    if (arg->f_hash && arg->n_mand == argc+1 && empty_keyword_given) {
        VALUE *ptr = rb_alloc_tmp_buffer2(tmp_buffer, argc+1, sizeof(VALUE));
        memcpy(ptr, argv, sizeof(VALUE)*argc);
        ptr[argc] = rb_hash_new();
        argc++;
        *(&argv) = ptr;
        rb_warn("The keyword argument is passed as the last hash parameter");
    }

    arg->argc = argc;
    arg->argv = argv;
}

static int
rb_scan_args_assign(struct rb_scan_args_t *arg, va_list vargs)
{
    int argi = 0;
    int i;
    VALUE *var;

    if (arg->argc < arg->n_mand) {
        return 1;
    }

    /* capture leading mandatory arguments */
    for (i = arg->n_lead; i-- > 0; ) {
	var = va_arg(vargs, VALUE *);
        if (var) *var = (argi == arg->last_idx) ? arg->last_hash : arg->argv[argi];
	argi++;
    }
    /* capture optional arguments */
    for (i = arg->n_opt; i-- > 0; ) {
	var = va_arg(vargs, VALUE *);
        if (argi < arg->argc - arg->n_trail) {
            if (var) *var = (argi == arg->last_idx) ? arg->last_hash : arg->argv[argi];
	    argi++;
	}
	else {
	    if (var) *var = Qnil;
	}
    }
    /* capture variable length arguments */
    if (arg->f_var) {
        int n_var = arg->argc - argi - arg->n_trail;

	var = va_arg(vargs, VALUE *);
	if (0 < n_var) {
	    if (var) {
                int f_last = (arg->last_idx + 1 == arg->argc - arg->n_trail);
                *var = rb_ary_new4(n_var - f_last, &arg->argv[argi]);
                if (f_last) rb_ary_push(*var, arg->last_hash);
	    }
	    argi += n_var;
	}
	else {
	    if (var) *var = rb_ary_new();
	}
    }
    /* capture trailing mandatory arguments */
    for (i = arg->n_trail; i-- > 0; ) {
	var = va_arg(vargs, VALUE *);
        if (var) *var = (argi == arg->last_idx) ? arg->last_hash : arg->argv[argi];
	argi++;
    }
    /* capture an option hash - phase 2: assignment */
    if (arg->f_hash) {
	var = va_arg(vargs, VALUE *);
        if (var) *var = arg->hash;
    }
    /* capture iterator block */
    if (arg->f_block) {
	var = va_arg(vargs, VALUE *);
	if (rb_block_given_p()) {
	    *var = rb_block_proc();
	}
	else {
	    *var = Qnil;
	}
    }

    if (argi < arg->argc) return 1;

    return 0;
}

#undef rb_scan_args
int
rb_scan_args(int argc, const VALUE *argv, const char *fmt, ...)
{
    int error;
    va_list vargs;
    VALUE tmp_buffer = 0;
    struct rb_scan_args_t arg;
    arg.tmp_buffer = &tmp_buffer;
    rb_scan_args_parse(RB_SCAN_ARGS_PASS_CALLED_KEYWORDS, argc, argv, fmt, &arg);
    va_start(vargs,fmt);
    error = rb_scan_args_assign(&arg, vargs);
    va_end(vargs);
    if (tmp_buffer) {
        rb_free_tmp_buffer(&tmp_buffer);
    }
    if (error) {
        rb_error_arity(arg.argc, arg.n_mand, arg.f_var ? UNLIMITED_ARGUMENTS : arg.n_mand + arg.n_opt);
    }
    return arg.argc;
}

int
rb_scan_args_kw(int kw_flag, int argc, const VALUE *argv, const char *fmt, ...)
{
    int error;
    va_list vargs;
    VALUE tmp_buffer = 0;
    struct rb_scan_args_t arg;
    arg.tmp_buffer = &tmp_buffer;
    rb_scan_args_parse(kw_flag, argc, argv, fmt, &arg);
    va_start(vargs,fmt);
    error = rb_scan_args_assign(&arg, vargs);
    va_end(vargs);
    if (tmp_buffer) {
        rb_free_tmp_buffer(&tmp_buffer);
    }
    if (error) {
        rb_error_arity(arg.argc, arg.n_mand, arg.f_var ? UNLIMITED_ARGUMENTS : arg.n_mand + arg.n_opt);
    }
    return arg.argc;
}

int
rb_class_has_methods(VALUE c)
{
    return rb_id_table_size(RCLASS_M_TBL(c)) == 0 ? FALSE : TRUE;
}

/*!
 * \}
 */
