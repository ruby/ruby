/************************************************

  variable.c -

  $Author: matz $
  $Date: 1995/01/12 08:54:53 $
  created at: Tue Apr 19 23:55:15 JST 1994

************************************************/

#include "ruby.h"
#include "env.h"
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

    rb_ivar_set_1(class, rb_intern("__classname__"), INT2FIX(id));
}

char *
rb_class2name(class)
    struct RClass *class;
{
    int name;

    switch (TYPE(class)) {
      case T_ICLASS:
        class = (struct RClass*)RBASIC(class)->class;
	break;
      case T_CLASS:
      case T_MODULE:
	break;
      default:
	Fail("0x%x is not a class/module", class);
    }

    while (FL_TEST(class, FL_SINGLE)) {
	class = (struct RClass*)class->super;
    }

    while (TYPE(class) == T_ICLASS) {
        class = (struct RClass*)class->super;
    }

    name = rb_ivar_get_1(class, rb_intern("__classname__"));
    if (name) {
	name = FIX2INT(name);
	return rb_id2name((ID)name);
    }
    Bug("class 0x%x not named", class);
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
    void *data;
};

static
mark_global_entry(key, entry)
    ID key;
    struct global_entry *entry;
{
    switch (entry->mode) {
	case GLOBAL_VAL:
	gc_mark(entry->v.val);	/* normal global value */
	break;
      case GLOBAL_VAR:
	if (entry->v.var)
	    gc_mark(*entry->v.var); /* c variable pointer */
	break;
      default:
	break;
    }
    if (entry->data) {
	gc_mark_maybe(entry->data);
    }
    return ST_CONTINUE;
}

void
gc_mark_global_tbl()
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
rb_define_variable(name, var, get_hook, set_hook, data)
    char  *name;
    VALUE *var;
    VALUE (*get_hook)();
    VALUE (*set_hook)();
    void *data;
{
    struct global_entry *entry;
    ID id;

    if (name[0] == '$') id = rb_intern(name);
    else {
	char *buf = ALLOCA_N(char, strlen(name)+2);
	buf[0] = '$';
	strcpy(buf+1, name);
	id = rb_intern(buf);
    }

    entry = rb_global_entry(id);
    entry->mode = GLOBAL_VAR;
    entry->v.var = var;
    entry->get_hook = get_hook;
    entry->set_hook = set_hook;
    entry->data = data;
}

void
rb_define_varhook(name, get_hook, set_hook, data)
    char  *name;
    VALUE (*get_hook)();
    VALUE (*set_hook)();
    void *data;
{
    struct global_entry *entry;
    ID id;

    if (name[0] == '$') id = rb_intern(name);
    else {
	char *buf = ALLOCA_N(char, strlen(name)+2);
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
    if (data) {
	entry->data = data;
    }
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
rb_gvar_get(entry)
    struct global_entry *entry;
{
    VALUE val;

    if (entry->get_hook)
	val = (*entry->get_hook)(entry->id, entry->data);
    switch (entry->mode) {
      case GLOBAL_VAL:
	return entry->v.val;

      case GLOBAL_VAR:
	if (entry->v.var == Qnil) return val;
	return *entry->v.var;

      default:
	break;
    }
    Warning("global var %s not initialized", rb_id2name(entry->id));
    return Qnil;
}

VALUE
rb_gvar_set(entry, val)
    struct global_entry *entry;
    VALUE val;
{
    if (entry->set_hook)
	(*entry->set_hook)(val, entry->id, entry->data);

    if (entry->mode == GLOBAL_VAR) {
	if (entry->v.var) {
	    *entry->v.var = val;
	}
    }
    else {
	if (entry->mode == GLOBAL_UNDEF) {
	    entry->mode = GLOBAL_VAL;
	}
	entry->v.val = val;
    }
    return val;
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

VALUE
rb_ivar_get_1(obj, id)
    struct RObject *obj;
    ID id;
{
    VALUE val;

    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (obj->iv_tbl && st_lookup(obj->iv_tbl, id, &val))
	    return val;
	return Qnil;
      default:
	Fail("class %s can not have instance variables",
	     rb_class2name(CLASS_OF(obj)));
	break;
    }
    Warning("instance var %s not initialized", rb_id2name(id));
    return Qnil;
}

VALUE
rb_ivar_get(id)
    ID id;
{
    return rb_ivar_get_1(Qself, id);
}

VALUE
rb_ivar_set_1(obj, id, val)
    struct RObject *obj;
    ID id;
    VALUE val;
{
    switch (TYPE(obj)) {
      case T_OBJECT:
      case T_CLASS:
      case T_MODULE:
	if (obj->iv_tbl == Qnil) obj->iv_tbl = new_idhash();
	st_insert(obj->iv_tbl, id, val);
	break;
      default:
	Fail("class %s can not have instance variables",
	     rb_class2name(CLASS_OF(obj)));
	break;
    }
    return val;
}

VALUE
rb_ivar_set(id, val)
    ID id;
    VALUE val;
{
    return rb_ivar_set_1(Qself, id, val);
}

VALUE
rb_const_get(class, id)
    struct RClass *class;
    ID id;
{
    VALUE value;

    while (class) {
	if (class->iv_tbl && st_lookup(class->iv_tbl, id, &value)) {
	    return value;
	}
	if (BUILTIN_TYPE(class) == T_MODULE) {
	    class = RCLASS(C_Object);
	}
	else {
	    class = class->super;
	}
    }

    /* pre-defined class */
    if (st_lookup(class_tbl, id, &value)) return value;

    /* here comes autoload code in the future. */

    Fail("Uninitialized constant %s", rb_id2name(id));
    /* not reached */
}

VALUE
rb_const_bound(class, id)
    struct RClass *class;
    ID id;
{
    while (class) {
	if (class->iv_tbl && st_lookup(class->iv_tbl, id, Qnil)) {
	    return TRUE;
	}
	class = class->super;
    }
    if (st_lookup(class_tbl, id, Qnil))
	return TRUE;
    return FALSE;
}

void
rb_const_set(class, id, val)
    struct RClass *class;
    ID id;
    VALUE val;
{
    if (rb_const_bound(class, id))
	Fail("already initialized constnant");

    if (class->iv_tbl == Qnil) class->iv_tbl = new_idhash();
    st_insert(class->iv_tbl, id, val);
}

void
rb_define_const(class, name, val)
    struct RClass *class;
    char *name;
    VALUE val;
{
    rb_const_set(class, rb_intern(name), val);
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
