/**********************************************************************

  object_traceing.c - Object Tracing mechanism/ObjectSpace extender for MRI.

  $Author$
  created at: Mon May 27 16:27:44 2013

  NOTE: This extension library is not expected to exist except C Ruby.
  NOTE: This feature is an example usage of internal event tracing APIs.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/debug.h"

size_t rb_gc_count(void); /* from gc.c */

struct traceobj_arg {
    VALUE newobj_trace;
    VALUE freeobj_trace;
    st_table *object_table;
    st_table *path_table;
    struct traceobj_arg *prev_traceobj_arg;
};

struct traceobj_arg *traceobj_arg; /* TODO: do not use GLOBAL VARIABLE!!! */

struct allocation_info {
    char *path;
    unsigned long line;
    size_t generation;
};

static void
newobj_i(VALUE tpval, void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    VALUE obj = rb_tracearg_object(tparg);
    VALUE path = rb_tracearg_path(tparg);
    VALUE line = rb_tracearg_lineno(tparg);
    long path_len = RSTRING_LEN(path);
    struct allocation_info *info = (struct allocation_info *)ruby_xmalloc(sizeof(struct allocation_info));
    char *path_cstr = ruby_xmalloc(path_len + 1);
    char *path_stored_cstr;

    strncpy(path_cstr, RSTRING_PTR(path), path_len);
    path_cstr[path_len] = 0;

    if (st_get_key(arg->path_table, (st_data_t)path_cstr, (st_data_t *)&path_stored_cstr)) {
	st_data_t n;
	st_lookup(arg->path_table, (st_data_t)path_stored_cstr, &n);
	st_insert(arg->path_table, (st_data_t)path_stored_cstr, n+1);
	ruby_xfree(path_cstr);
	path_cstr = path_stored_cstr;
    }
    else {
	st_add_direct(arg->path_table, (st_data_t)path_cstr, 1);
    }

    info->path = path_cstr;
    info->line = NUM2INT(line);
    info->generation = rb_gc_count();
    st_insert(arg->path_table, (st_data_t)path_cstr, 0);
    st_insert(arg->object_table, (st_data_t)obj, (st_data_t)info);
}

static void
freeobj_i(VALUE tpval, void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    VALUE obj = rb_tracearg_object(tparg);
    struct allocation_info *info;
    st_data_t n;
    if (st_delete(arg->object_table, (st_data_t *)&obj, (st_data_t *)&info)) {
	st_lookup(arg->path_table, (st_data_t)info->path, &n);
	if (n == 1) {
	    st_delete(arg->path_table, (st_data_t *)&info->path, 0);
	    ruby_xfree(info->path);
	}
	else {
	    st_insert(arg->path_table, (st_data_t)info->path, n-1);
	}

	ruby_xfree(info);
    }
}

static int
free_keys_i(st_data_t key, st_data_t value, void *data)
{
    ruby_xfree((void *)key);
    return ST_CONTINUE;
}

static int
free_values_i(st_data_t key, st_data_t value, void *data)
{
    ruby_xfree((void *)value);
    return ST_CONTINUE;
}

static VALUE
stop_trace_object_allocations(void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    rb_tracepoint_disable(arg->newobj_trace);
    rb_tracepoint_disable(arg->freeobj_trace);
    st_foreach(arg->object_table, free_values_i, 0);
    st_foreach(arg->path_table, free_keys_i, 0);
    st_free_table(arg->object_table);
    st_free_table(arg->path_table);
    traceobj_arg = arg->prev_traceobj_arg;

    return Qnil;
}

static VALUE
trace_object_allocations(VALUE objspace)
{
    struct traceobj_arg arg;

    arg.newobj_trace = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ, newobj_i, &arg);
    arg.freeobj_trace = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_FREEOBJ, freeobj_i, &arg);
    arg.object_table = st_init_numtable();
    arg.path_table = st_init_strtable();

    arg.prev_traceobj_arg = traceobj_arg;
    traceobj_arg = &arg;

    rb_tracepoint_enable(arg.newobj_trace);
    rb_tracepoint_enable(arg.freeobj_trace);

    return rb_ensure(rb_yield, Qnil, stop_trace_object_allocations, (VALUE)&arg);
}

struct allocation_info *
allocation_info(VALUE obj)
{
    if (traceobj_arg) {
	struct allocation_info *info;
	if (st_lookup(traceobj_arg->object_table, obj, (st_data_t *)&info)) {
	    return info;
	}
    }
    return NULL;
}

static VALUE
allocation_sourcefile(VALUE objspace, VALUE obj)
{
    struct allocation_info *info = allocation_info(obj);
    if (info) {
	return rb_str_new2(info->path);
    }
    else {
	return Qnil;
    }
}

static VALUE
allocation_sourceline(VALUE objspace, VALUE obj)
{
    struct allocation_info *info = allocation_info(obj);
    if (info) {
	return INT2FIX(info->line);
    }
    else {
	return Qnil;
    }
}

static VALUE
allocation_generation(VALUE objspace, VALUE obj)
{
    struct allocation_info *info = allocation_info(obj);
    if (info) {
	return SIZET2NUM(info->generation);
    }
    else {
	return Qnil;
    }
}

void
Init_object_tracing(VALUE rb_mObjSpace)
{
    rb_define_module_function(rb_mObjSpace, "trace_object_allocations", trace_object_allocations, 0);
    rb_define_module_function(rb_mObjSpace, "allocation_sourcefile", allocation_sourcefile, 1);
    rb_define_module_function(rb_mObjSpace, "allocation_sourceline", allocation_sourceline, 1);
    rb_define_module_function(rb_mObjSpace, "allocation_generation", allocation_generation, 1);
}
