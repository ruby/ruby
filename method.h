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

typedef enum {
    NOEX_PUBLIC    = 0x00,
    NOEX_NOSUPER   = 0x01,
    NOEX_PRIVATE   = 0x02,
    NOEX_PROTECTED = 0x04,
    NOEX_MASK      = 0x06,
    NOEX_BASIC     = 0x08,
    NOEX_UNDEF     = NOEX_NOSUPER,
    NOEX_MODFUNC   = 0x12,
    NOEX_SUPER     = 0x20,
    NOEX_VCALL     = 0x40,
    NOEX_RESPONDS  = 0x80,

    NOEX_BIT_WIDTH = 8,
    NOEX_SAFE_SHIFT_OFFSET = ((NOEX_BIT_WIDTH+3)/4)*4 /* round up to nibble */
} rb_method_flag_t;

#define NOEX_SAFE(n) ((int)((n) >> NOEX_SAFE_SHIFT_OFFSET) & 0x0F)
#define NOEX_WITH(n, s) (((s) << NOEX_SAFE_SHIFT_OFFSET) | (n) | (ruby_running ? 0 : NOEX_BASIC))
#define NOEX_WITH_SAFE(n) NOEX_WITH((n), rb_safe_level())

/* method data type */

typedef enum {
    VM_METHOD_TYPE_ISEQ,
    VM_METHOD_TYPE_CFUNC,
    VM_METHOD_TYPE_ATTRSET,
    VM_METHOD_TYPE_IVAR,
    VM_METHOD_TYPE_BMETHOD,
    VM_METHOD_TYPE_ZSUPER,
    VM_METHOD_TYPE_UNDEF,
    VM_METHOD_TYPE_NOTIMPLEMENTED,
    VM_METHOD_TYPE_OPTIMIZED, /* Kernel#send, Proc#call, etc */
    VM_METHOD_TYPE_MISSING,   /* wrapper for method_missing(id) */
    VM_METHOD_TYPE_REFINED,

    END_OF_ENUMERATION(VM_METHOD_TYPE)
} rb_method_type_t;

struct rb_call_info_struct;

typedef struct rb_method_cfunc_struct {
    VALUE (*func)(ANYARGS);
    VALUE (*invoker)(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv);
    int argc;
} rb_method_cfunc_t;

typedef struct rb_method_attr_struct {
    ID id;
    const VALUE location;
} rb_method_attr_t;

typedef struct rb_iseq_struct rb_iseq_t;

typedef struct rb_method_definition_struct {
    rb_method_type_t type; /* method type */
    ID original_id;
    union {
	rb_iseq_t * const iseq;            /* should be mark */
	rb_method_cfunc_t cfunc;
	rb_method_attr_t attr;
	const VALUE proc;                 /* should be mark */
	enum method_optimized_type {
	    OPTIMIZED_METHOD_TYPE_SEND,
	    OPTIMIZED_METHOD_TYPE_CALL,

	    OPTIMIZED_METHOD_TYPE__MAX
	} optimize_type;
	struct rb_method_entry_struct *orig_me;
    } body;
    int alias_count;
} rb_method_definition_t;

typedef struct rb_method_entry_struct {
    rb_method_flag_t flag;
    char mark;
    rb_method_definition_t *def;
    ID called_id;
    VALUE klass;                    /* should be mark */
} rb_method_entry_t;

struct unlinked_method_entry_list_entry {
    struct unlinked_method_entry_list_entry *next;
    rb_method_entry_t *me;
};

#define UNDEFINED_METHOD_ENTRY_P(me) (!(me) || !(me)->def || (me)->def->type == VM_METHOD_TYPE_UNDEF)
#define UNDEFINED_REFINED_METHOD_P(def) \
    ((def)->type == VM_METHOD_TYPE_REFINED && \
     UNDEFINED_METHOD_ENTRY_P((def)->body.orig_me))

void rb_add_method_cfunc(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc, rb_method_flag_t noex);
rb_method_entry_t *rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *option, rb_method_flag_t noex);
rb_method_entry_t *rb_method_entry(VALUE klass, ID id, VALUE *define_class_ptr);
rb_method_entry_t *rb_method_entry_at(VALUE obj, ID id);
void rb_add_refined_method_entry(VALUE refined_class, ID mid);
rb_method_entry_t *rb_resolve_refined_method(VALUE refinements,
					     const rb_method_entry_t *me,
					     VALUE *defined_class_ptr);
rb_method_entry_t *rb_method_entry_with_refinements(VALUE klass, ID id,
						    VALUE *defined_class_ptr);
rb_method_entry_t *rb_method_entry_without_refinements(VALUE klass, ID id,
						       VALUE *defined_class_ptr);

rb_method_entry_t *rb_method_entry_get_without_cache(VALUE klass, ID id, VALUE *define_class_ptr);
rb_method_entry_t *rb_method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *, rb_method_flag_t noex);

int rb_method_entry_arity(const rb_method_entry_t *me);
int rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2);
st_index_t rb_hash_method_entry(st_index_t hash, const rb_method_entry_t *me);

VALUE rb_method_entry_location(rb_method_entry_t *me);
VALUE rb_mod_method_location(VALUE mod, ID id);
VALUE rb_obj_method_location(VALUE obj, ID id);

void rb_mark_method_entry(const rb_method_entry_t *me);
void rb_free_method_entry(rb_method_entry_t *me);
void rb_sweep_method_entry(void *vm);
void rb_free_m_tbl(st_table *tbl);
void rb_free_m_tbl_wrapper(struct method_table_wrapper *wrapper);

#endif /* METHOD_H */
