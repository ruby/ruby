/**********************************************************************

  method.h -

  $Author$
  created at: Wed Jul 15 20:02:33 2009

  Copyright (C) 2009 Koichi Sasada

**********************************************************************/
#ifndef METHOD_H
#define METHOD_H

#include "internal.h"

#ifndef END_OF_ENUMERATION
# if defined(__GNUC__) &&! defined(__STRICT_ANSI__)
#   define END_OF_ENUMERATION(key)
# else
#   define END_OF_ENUMERATION(key) END_OF_##key##_PLACEHOLDER = 0
# endif
#endif

/* cref */

typedef enum {
    METHOD_VISI_UNDEF     = 0x00,
    METHOD_VISI_PUBLIC    = 0x01,
    METHOD_VISI_PRIVATE   = 0x02,
    METHOD_VISI_PROTECTED = 0x03
} rb_method_visibility_t;

typedef struct rb_scope_visi_struct {
    rb_method_visibility_t method_visi : 3;
    unsigned int module_func : 1;
} rb_scope_visibility_t;

typedef struct rb_cref_struct {
    VALUE flags;
    const VALUE refinements;
    const VALUE klass;
    struct rb_cref_struct * const next;
    rb_scope_visibility_t scope_visi;
} rb_cref_t;

/* method data type */

typedef struct rb_method_entry_struct {
    VALUE flags;
    VALUE reserved;
    struct rb_method_definition_struct * const def;
    ID called_id;
    const VALUE klass;    /* should be marked */
} rb_method_entry_t;

typedef enum {
    VM_METHOD_TYPE_ISEQ,
    VM_METHOD_TYPE_CFUNC,
    VM_METHOD_TYPE_ATTRSET,
    VM_METHOD_TYPE_IVAR,
    VM_METHOD_TYPE_BMETHOD,
    VM_METHOD_TYPE_ZSUPER,
    VM_METHOD_TYPE_ALIAS,
    VM_METHOD_TYPE_UNDEF,
    VM_METHOD_TYPE_NOTIMPLEMENTED,
    VM_METHOD_TYPE_OPTIMIZED, /* Kernel#send, Proc#call, etc */
    VM_METHOD_TYPE_MISSING,   /* wrapper for method_missing(id) */
    VM_METHOD_TYPE_REFINED,

    END_OF_ENUMERATION(VM_METHOD_TYPE)
} rb_method_type_t;

typedef struct rb_iseq_struct rb_iseq_t;

typedef struct rb_method_iseq_struct {
    rb_iseq_t * const iseqptr;                    /* should be separated from iseqval */
    rb_cref_t * const cref;                       /* shoudl be marked */
} rb_method_iseq_t; /* check rb_add_method_iseq() when modify the fields */

typedef struct rb_method_cfunc_struct {
    VALUE (*func)(ANYARGS);
    VALUE (*invoker)(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv);
    int argc;
} rb_method_cfunc_t;

typedef struct rb_method_attr_struct {
    ID id;
    const VALUE location; /* sould be marked */
} rb_method_attr_t;

typedef struct rb_method_alias_struct {
    const struct rb_method_entry_struct *original_me; /* original_me->klass is original owner */
} rb_method_alias_t;

typedef struct rb_method_refined_struct {
    const struct rb_method_entry_struct *orig_me;
} rb_method_refined_t;

typedef struct rb_method_definition_struct {
    struct {
	rb_method_visibility_t visi: 3;
	unsigned int safe: 3;
	unsigned int basic: 1;
    } flags;
    rb_method_type_t type; /* method type */

    union {
	rb_method_iseq_t iseq;
	rb_method_cfunc_t cfunc;
	rb_method_attr_t attr;
	rb_method_alias_t alias;
	rb_method_refined_t refined;

	const VALUE proc;                 /* should be marked */
	enum method_optimized_type {
	    OPTIMIZED_METHOD_TYPE_SEND,
	    OPTIMIZED_METHOD_TYPE_CALL,

	    OPTIMIZED_METHOD_TYPE__MAX
	} optimize_type;
    } body;

    int *alias_count_ptr;
    ID original_id;
} rb_method_definition_t;

#define UNDEFINED_METHOD_ENTRY_P(me) (!(me) || !(me)->def || (me)->def->type == VM_METHOD_TYPE_UNDEF)
#define UNDEFINED_REFINED_METHOD_P(def) \
    ((def)->type == VM_METHOD_TYPE_REFINED && \
     UNDEFINED_METHOD_ENTRY_P((def)->body.refined.orig_me))

void rb_add_method_cfunc(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc, rb_method_visibility_t visi);
void rb_add_method_iseq(VALUE klass, ID mid, VALUE iseqval, rb_cref_t *cref, rb_method_visibility_t visi);
rb_method_entry_t *rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *option, rb_method_visibility_t visi);
rb_method_entry_t *rb_method_entry(VALUE klass, ID id, VALUE *define_class_ptr);
rb_method_entry_t *rb_method_entry_at(VALUE obj, ID id);
void rb_add_refined_method_entry(VALUE refined_class, ID mid);
const rb_method_entry_t *rb_resolve_refined_method(VALUE refinements,
						   const rb_method_entry_t *me,
						   VALUE *defined_class_ptr);
const rb_method_entry_t *rb_method_entry_with_refinements(VALUE klass, ID id,
							  VALUE *defined_class_ptr);
const rb_method_entry_t *rb_method_entry_without_refinements(VALUE klass, ID id,
							     VALUE *defined_class_ptr);

rb_method_entry_t *rb_method_entry_get_without_cache(VALUE klass, ID id, VALUE *define_class_ptr);
rb_method_entry_t *rb_method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *, rb_method_visibility_t noex);

int rb_method_entry_arity(const rb_method_entry_t *me);
int rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2);
st_index_t rb_hash_method_entry(st_index_t hash, const rb_method_entry_t *me);

VALUE rb_method_entry_location(const rb_method_entry_t *me);
VALUE rb_mod_method_location(VALUE mod, ID id);
VALUE rb_obj_method_location(VALUE obj, ID id);

void rb_free_method_entry(const rb_method_entry_t *me);
void rb_sweep_method_entry(void *vm);

rb_method_entry_t *rb_method_entry_create(ID called_id, VALUE klass, rb_method_definition_t *def);
rb_method_entry_t *rb_method_entry_clone(const rb_method_entry_t *me);
void rb_method_entry_copy(rb_method_entry_t *dst, const rb_method_entry_t *src);

void rb_scope_visibility_set(rb_method_visibility_t);

#endif /* METHOD_H */
