/************************************************

  variable.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:51 $
  created at: Tue Apr 19 23:55:15 JST 1994

************************************************/

#include "ruby.h"
#include "env.h"
#include "node.h"
#include "ident.h"
#include "st.h"

st_table *rb_global_tbl;
st_table *rb_class_tbl;
#define global_tbl rb_global_tbl
#define class_tbl rb_class_tbl
#define instance_tbl (RBASIC(Qself)->iv_tbl)

st_table *new_idhash()
{
    return st_init_table(ST_NUMCMP, ST_NUMHASH);
}

void
Init_var_tables()
{
    global_tbl = new_idhash();
    class_tbl = new_idhash();
}

void
rb_name_class(class, id)
    VALUE class;
    ID id;
{
    VALUE body;

    if (st_lookup(class_tbl, id, &body)) {
	Bug("%s %s already exists",
	    TYPE(body)==T_CLASS?"class":"module", rb_id2name(id));
    }
    st_add_direct(class_tbl, id, class);
}

struct global_entry {
    enum { GLOBAL_VAL, GLOBAL_VAR, GLOBAL_UNDEF } mode;
    ID id;
    union {
	VALUE val;
	VALUE *var;
    } v;
    VALUE (*get_hook)();
    VALUE (*set_hook)();
};

static mark_global_entry(key, entry)
    ID key;
    struct global_entry *entry;
{
    switch (entry->mode) {
	case GLOBAL_VAL:
	mark(entry->v.val);	/* normal global value */
	break;
      case GLOBAL_VAR:
	if (entry->v.var)
	    mark(*entry->v.var); /* c variable pointer */
	break;
      default:
	break;
    }
    return ST_CONTINUE;
}

mark_global_tbl()
{
    st_foreach(global_tbl, mark_global_entry, 0);
}

struct global_entry*
rb_global_entry(id)
    ID id;
{
    struct global_entry *entry;

    if (!st_lookup(global_tbl, id, &entry)) {
	entry = ALLOC(struct global_entry);
	st_insert(global_tbl, id, entry);
	entry->id = id;
	entry->mode = GLOBAL_UNDEF;
	entry->v.var = Qnil;
	entry->get_hook = entry->set_hook = Qnil;
    }
    return entry;
}

void
rb_define_variable(name, var, get_hook, set_hook)
    char  *name;
    VALUE *var;
    VALUE (*get_hook)();
    VALUE (*set_hook)();
{
    struct global_entry *entry;
    ID id;

    if (name[0] == '$') id = rb_intern(name);
    else {
	char *buf = (char*)alloca(strlen(name)+2);
	buf[0] = '$';
	strcpy(buf+1, name);
	id = rb_intern(buf);
    }

    if (!st_lookup(global_tbl, id, &entry)) {
	entry = rb_global_entry(id);
    }
    entry->mode = GLOBAL_VAR;
    entry->v.var = var;
    entry->get_hook = get_hook;
    entry->set_hook = set_hook;
}

void
rb_define_varhook(name, get_hook, set_hook)
    char  *name;
    VALUE (*get_hook)();
    VALUE (*set_hook)();
{
    struct global_entry *entry;
    ID id;

    if (name[0] == '$') id = rb_intern(name);
    else {
	char *buf = (char*)alloca(strlen(name)+2);
	buf[0] = '$';
	strcpy(buf+1, name);
	id = rb_intern(buf);
    }

    if (!st_lookup(global_tbl, id, &entry)) {
	entry = ALLOC(struct global_entry);
	entry->id = id;
	entry->mode = GLOBAL_VAL;
	st_insert(global_tbl, id, entry);
    }
    else if (entry->mode == GLOBAL_UNDEF) {
	entry->mode = GLOBAL_VAL;
    }
    entry->v.val = Qnil;
    entry->get_hook = get_hook;
    entry->set_hook = set_hook;
}

VALUE
rb_readonly_hook(val, id)
    VALUE val;
    ID id;
{
    Fail("Can't set variable %s", rb_id2name(id));
    /* not reached */
}

VALUE
rb_id2class(id)
    ID id;
{
    VALUE class;

    if (st_lookup(class_tbl, id, &class))
	return class;
    return Qnil;
}

VALUE
rb_gvar_get(entry)
    struct global_entry *entry;
{
    VALUE val;

    if (entry->get_hook)
	val = (*entry->get_hook)(entry->id);
    switch (entry->mode) {
      case GLOBAL_VAL:
	return entry->v.val;

      case GLOBAL_VAR:
	if (entry->v.var == Qnil) return val;
	return *entry->v.var;

      default:
	break;
    }
    return Qnil;
}

rb_ivar_get_1(obj, id)
    struct RBasic *obj;
    ID id;
{
    VALUE val;

    if (obj->iv_tbl == Qnil)
	return Qnil;
    if (st_lookup(obj->iv_tbl, id, &val))
	return val;
    return Qnil;
}

VALUE
rb_ivar_get(id)
    ID id;
{
    return rb_ivar_get_1(Qself, id);
}

VALUE
rb_mvar_get(id)
    ID id;
{
    VALUE val;

    if (st_lookup(class_tbl, id, &val)) return val;
    return Qnil;
}

VALUE
rb_const_get(id)
    ID id;
{
    struct RClass *class = (struct RClass*)CLASS_OF(Qself);
    VALUE value;

    while (class) {
	if (class->c_tbl && st_lookup(class->c_tbl, id, &value)) {
	    return value;
	}
	class = class->super;
    }
    Fail("Uninitialized constant %s", rb_id2name(id));
    /* not reached */
}

VALUE
rb_gvar_set(entry, val)
    struct global_entry *entry;
    VALUE val;
{
    if (entry->set_hook)
	(*entry->set_hook)(val, entry->id);

    if (entry->mode == GLOBAL_VAR && entry->v.var != Qnil)
	return *entry->v.var = val;
    else {
	if (entry->mode == GLOBAL_UNDEF)
	    entry->mode = GLOBAL_VAL;
	return entry->v.val = val;
    }
}

VALUE
rb_gvar_set2(name, val)
    char *name;
    VALUE val;
{
    struct global_entry *entry;
    ID id;

    id = rb_intern(name);
    if (!st_lookup(global_tbl, id, &entry)) {
	entry = rb_global_entry(id);
    }
    rb_gvar_set(entry, val);

    return val;
}

rb_ivar_set_1(obj, id, val)
    struct RBasic *obj;
    ID id;
    VALUE val;
{
    if (obj->iv_tbl == Qnil) obj->iv_tbl = new_idhash();
    st_insert(obj->iv_tbl, id, val);
    return val;
}

VALUE
rb_ivar_set(id, val)
    ID id;
    VALUE val;
{
    return rb_ivar_set_1(Qself, id, val);
}

static VALUE
const_bound(id)
    ID id;
{
    struct RClass *class = (struct RClass*)CLASS_OF(Qself);

    while (class) {
	if (class->c_tbl && st_lookup(class->c_tbl, id, Qnil)) {
	    return TRUE;
	}
	class = class->super;
    }
    return FALSE;
}

static void
rb_const_set_1(class, id, val)
    struct RClass *class;
    ID id;
    VALUE val;
{
    if (const_bound(id))
	Fail("already initialized constnant");

    if (class->c_tbl == Qnil)
	class->c_tbl = new_idhash();

    st_insert(class->c_tbl, id, val);
}

VALUE
rb_const_set(id, val)
    ID id;
    VALUE val;
{
    rb_const_set_1(the_class, id, val);
    return val;
}

void
rb_define_const(class, name, val)
    struct RClass *class;
    char *name;
    VALUE val;
{
    rb_const_set_1(class, rb_intern(name), val);
}

VALUE
rb_iv_get(obj, name)
    VALUE obj;
    char *name;
{
    ID id = rb_intern(name);

    return rb_ivar_get_1(obj, id);
}

VALUE
rb_iv_set(obj, name, val)
    VALUE obj;
    char *name;
    VALUE val;
{
    ID id = rb_intern(name);

    return rb_ivar_set_1(obj, id, val);
}

VALUE
Fdefined(obj, name)
    VALUE obj;
    struct RString *name;
{
    ID id;
    struct global_entry *entry;

    if (FIXNUM_P(name)) {
	id = FIX2INT(name);
    }
    else {
	Check_Type(name, T_STRING);
	id = rb_intern(name->ptr);
    }

    if (id == rb_intern("nil") || id == rb_intern("self")) return TRUE;

    switch (id & ID_SCOPE_MASK) {
      case ID_GLOBAL:
	if (st_lookup(global_tbl, id, &entry) && entry->mode != GLOBAL_UNDEF)
	    return TRUE;
	break;

      case ID_INSTANCE:
	if (TYPE(Qself) != T_OBJECT || instance_tbl == Qnil) break;
	if (st_lookup(instance_tbl, id, Qnil)) return TRUE;
	break;

      case ID_CONST:
	return const_bound(id);
	break;

      default:
	{
	    int i, max;

	    if (the_env->local_tbl) {
		for (i=1, max=the_env->local_tbl[0]+1; i<max; i++) {
		    if (the_env->local_tbl[i] == id) return TRUE;
		}
	    }
	}
	if (st_lookup(class_tbl, id, Qnil)) return TRUE;
	break;
    }
    return FALSE;
}

