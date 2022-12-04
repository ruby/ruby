/**********************************************************************

  object_tracing.c - Object Tracing mechanism/ObjectSpace extender for MRI.

  $Author$
  created at: Mon May 27 16:27:44 2013

  NOTE: This extension library is not expected to exist except C Ruby.
  NOTE: This feature is an example usage of internal event tracing APIs.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "internal.h"
#include "ruby/debug.h"
#include "objspace.h"

struct traceobj_arg {
    int running;
    int keep_remains;
    VALUE newobj_trace;
    VALUE freeobj_trace;
    st_table *object_table; /* obj (VALUE) -> allocation_info */
    st_table *str_table;    /* cstr -> refcount */
    struct traceobj_arg *prev_traceobj_arg;
};

static const char *
make_unique_str(st_table *tbl, const char *str, long len)
{
    if (!str) {
        return NULL;
    }
    else {
        st_data_t n;
        char *result;

        if (st_lookup(tbl, (st_data_t)str, &n)) {
            st_insert(tbl, (st_data_t)str, n+1);
            st_get_key(tbl, (st_data_t)str, &n);
            result = (char *)n;
        }
        else {
            result = (char *)ruby_xmalloc(len+1);
            strncpy(result, str, len);
            result[len] = 0;
            st_add_direct(tbl, (st_data_t)result, 1);
        }
        return result;
    }
}

static void
delete_unique_str(st_table *tbl, const char *str)
{
    if (str) {
        st_data_t n;

        st_lookup(tbl, (st_data_t)str, &n);
        if (n == 1) {
            n = (st_data_t)str;
            st_delete(tbl, &n, 0);
            ruby_xfree((char *)n);
        }
        else {
            st_insert(tbl, (st_data_t)str, n-1);
        }
    }
}

static void
newobj_i(VALUE tpval, void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    VALUE obj = rb_tracearg_object(tparg);
    VALUE path = rb_tracearg_path(tparg);
    VALUE line = rb_tracearg_lineno(tparg);
    VALUE mid = rb_tracearg_method_id(tparg);
    VALUE klass = rb_tracearg_defined_class(tparg);
    struct allocation_info *info;
    const char *path_cstr = RTEST(path) ? make_unique_str(arg->str_table, RSTRING_PTR(path), RSTRING_LEN(path)) : 0;
    VALUE class_path = (RTEST(klass) && !OBJ_FROZEN(klass)) ? rb_class_path_cached(klass) : Qnil;
    const char *class_path_cstr = RTEST(class_path) ? make_unique_str(arg->str_table, RSTRING_PTR(class_path), RSTRING_LEN(class_path)) : 0;
    st_data_t v;

    if (st_lookup(arg->object_table, (st_data_t)obj, &v)) {
        info = (struct allocation_info *)v;
        if (arg->keep_remains) {
            if (info->living) {
                /* do nothing. there is possibility to keep living if FREEOBJ events while suppressing tracing */
            }
        }
        /* reuse info */
        delete_unique_str(arg->str_table, info->path);
        delete_unique_str(arg->str_table, info->class_path);
    }
    else {
        info = (struct allocation_info *)ruby_xmalloc(sizeof(struct allocation_info));
    }
    info->living = 1;
    info->flags = RBASIC(obj)->flags;
    info->klass = RBASIC_CLASS(obj);

    info->path = path_cstr;
    info->line = NUM2INT(line);
    info->mid = mid;
    info->class_path = class_path_cstr;
    info->generation = rb_gc_count();
    st_insert(arg->object_table, (st_data_t)obj, (st_data_t)info);
}

static void
freeobj_i(VALUE tpval, void *data)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)data;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    st_data_t obj = (st_data_t)rb_tracearg_object(tparg);
    st_data_t v;
    struct allocation_info *info;

    if (arg->keep_remains) {
        if (st_lookup(arg->object_table, obj, &v)) {
            info = (struct allocation_info *)v;
            info->living = 0;
        }
    }
    else {
        if (st_delete(arg->object_table, &obj, &v)) {
            info = (struct allocation_info *)v;
            delete_unique_str(arg->str_table, info->path);
            delete_unique_str(arg->str_table, info->class_path);
            ruby_xfree(info);
        }
    }
}

static int
free_keys_i(st_data_t key, st_data_t value, st_data_t data)
{
    ruby_xfree((void *)key);
    return ST_CONTINUE;
}

static int
free_values_i(st_data_t key, st_data_t value, st_data_t data)
{
    ruby_xfree((void *)value);
    return ST_CONTINUE;
}

static void
allocation_info_tracer_mark(void *ptr)
{
    struct traceobj_arg *trace_arg = (struct traceobj_arg *)ptr;
    rb_gc_mark(trace_arg->newobj_trace);
    rb_gc_mark(trace_arg->freeobj_trace);
}

static void
allocation_info_tracer_free(void *ptr)
{
    struct traceobj_arg *arg = (struct traceobj_arg *)ptr;
    /* clear tables */
    st_foreach(arg->object_table, free_values_i, 0);
    st_free_table(arg->object_table);
    st_foreach(arg->str_table, free_keys_i, 0);
    st_free_table(arg->str_table);
    xfree(arg);
}

static size_t
allocation_info_tracer_memsize(const void *ptr)
{
    size_t size;
    struct traceobj_arg *trace_arg = (struct traceobj_arg *)ptr;
    size = sizeof(*trace_arg);
    size += st_memsize(trace_arg->object_table);
    size += st_memsize(trace_arg->str_table);
    return size;
}

static int
hash_foreach_should_replace_key(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    VALUE allocated_object;

    allocated_object = (VALUE)value;
    if (allocated_object != rb_gc_location(allocated_object)) {
        return ST_REPLACE;
    }

    return ST_CONTINUE;
}

static int
hash_replace_key(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    *key = rb_gc_location((VALUE)*key);

    return ST_CONTINUE;
}

static void
allocation_info_tracer_compact(void *ptr)
{
    struct traceobj_arg *trace_arg = (struct traceobj_arg *)ptr;

    if (trace_arg->object_table &&
            st_foreach_with_replace(trace_arg->object_table, hash_foreach_should_replace_key, hash_replace_key, 0)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

static const rb_data_type_t allocation_info_tracer_type = {
    "ObjectTracing/allocation_info_tracer",
    {
        allocation_info_tracer_mark,
        allocation_info_tracer_free, /* Never called because global */
        allocation_info_tracer_memsize,
        allocation_info_tracer_compact,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE traceobj_arg;
static struct traceobj_arg *tmp_trace_arg; /* TODO: Do not use global variables */
static int tmp_keep_remains;               /* TODO: Do not use global variables */

static struct traceobj_arg *
get_traceobj_arg(void)
{
    if (tmp_trace_arg == 0) {
        VALUE obj = TypedData_Make_Struct(rb_cObject, struct traceobj_arg, &allocation_info_tracer_type, tmp_trace_arg);
        traceobj_arg = obj;
        rb_gc_register_mark_object(traceobj_arg);
        tmp_trace_arg->running = 0;
        tmp_trace_arg->keep_remains = tmp_keep_remains;
        tmp_trace_arg->newobj_trace = 0;
        tmp_trace_arg->freeobj_trace = 0;
        tmp_trace_arg->object_table = st_init_numtable();
        tmp_trace_arg->str_table = st_init_strtable();
    }
    return tmp_trace_arg;
}

/*
 * call-seq: trace_object_allocations_start
 *
 * Starts tracing object allocations.
 *
 */
static VALUE
trace_object_allocations_start(VALUE self)
{
    struct traceobj_arg *arg = get_traceobj_arg();

    if (arg->running++ > 0) {
        /* do nothing */
    }
    else {
        if (arg->newobj_trace == 0) {
            arg->newobj_trace = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ, newobj_i, arg);
            arg->freeobj_trace = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_FREEOBJ, freeobj_i, arg);
        }
        rb_tracepoint_enable(arg->newobj_trace);
        rb_tracepoint_enable(arg->freeobj_trace);
    }

    return Qnil;
}

/*
 * call-seq: trace_object_allocations_stop
 *
 * Stop tracing object allocations.
 *
 * Note that if ::trace_object_allocations_start is called n-times, then
 * tracing will stop after calling ::trace_object_allocations_stop n-times.
 *
 */
static VALUE
trace_object_allocations_stop(VALUE self)
{
    struct traceobj_arg *arg = get_traceobj_arg();

    if (arg->running > 0) {
        arg->running--;
    }

    if (arg->running == 0) {
        if (arg->newobj_trace != 0) {
            rb_tracepoint_disable(arg->newobj_trace);
        }
        if (arg->freeobj_trace != 0) {
            rb_tracepoint_disable(arg->freeobj_trace);
        }
    }

    return Qnil;
}

/*
 * call-seq: trace_object_allocations_clear
 *
 * Clear recorded tracing information.
 *
 */
static VALUE
trace_object_allocations_clear(VALUE self)
{
    struct traceobj_arg *arg = get_traceobj_arg();

    /* clear tables */
    st_foreach(arg->object_table, free_values_i, 0);
    st_clear(arg->object_table);
    st_foreach(arg->str_table, free_keys_i, 0);
    st_clear(arg->str_table);

    /* do not touch TracePoints */

    return Qnil;
}

/*
 * call-seq: trace_object_allocations { block }
 *
 * Starts tracing object allocations from the ObjectSpace extension module.
 *
 * For example:
 *
 *	require 'objspace'
 *
 *	class C
 *	  include ObjectSpace
 *
 *	  def foo
 *	    trace_object_allocations do
 *	      obj = Object.new
 *	      p "#{allocation_sourcefile(obj)}:#{allocation_sourceline(obj)}"
 *	    end
 *	  end
 *	end
 *
 *	C.new.foo #=> "objtrace.rb:8"
 *
 * This example has included the ObjectSpace module to make it easier to read,
 * but you can also use the ::trace_object_allocations notation (recommended).
 *
 * Note that this feature introduces a huge performance decrease and huge
 * memory consumption.
 */
static VALUE
trace_object_allocations(VALUE self)
{
    trace_object_allocations_start(self);
    return rb_ensure(rb_yield, Qnil, trace_object_allocations_stop, self);
}

int rb_bug_reporter_add(void (*func)(FILE *, void *), void *data);
static int object_allocations_reporter_registered = 0;

static int
object_allocations_reporter_i(st_data_t key, st_data_t val, st_data_t ptr)
{
    FILE *out = (FILE *)ptr;
    VALUE obj = (VALUE)key;
    struct allocation_info *info = (struct allocation_info *)val;

    fprintf(out, "-- %p (%s F: %p, ", (void *)obj, info->living ? "live" : "dead", (void *)info->flags);
    if (info->class_path) fprintf(out, "C: %s", info->class_path);
    else                  fprintf(out, "C: %p", (void *)info->klass);
    fprintf(out, "@%s:%lu", info->path ? info->path : "", info->line);
    if (!NIL_P(info->mid)) {
        VALUE m = rb_sym2str(info->mid);
        fprintf(out, " (%s)", RSTRING_PTR(m));
    }
    fprintf(out, ")\n");

    return ST_CONTINUE;
}

static void
object_allocations_reporter(FILE *out, void *ptr)
{
    fprintf(out, "== object_allocations_reporter: START\n");
    if (tmp_trace_arg) {
        st_foreach(tmp_trace_arg->object_table, object_allocations_reporter_i, (st_data_t)out);
    }
    fprintf(out, "== object_allocations_reporter: END\n");
}

static VALUE
trace_object_allocations_debug_start(VALUE self)
{
    tmp_keep_remains = 1;
    if (object_allocations_reporter_registered == 0) {
        object_allocations_reporter_registered = 1;
        rb_bug_reporter_add(object_allocations_reporter, 0);
    }

    return trace_object_allocations_start(self);
}

static struct allocation_info *
lookup_allocation_info(VALUE obj)
{
    if (tmp_trace_arg) {
        st_data_t info;
        if (st_lookup(tmp_trace_arg->object_table, obj, &info)) {
            return (struct allocation_info *)info;
        }
    }
    return NULL;
}

struct allocation_info *
objspace_lookup_allocation_info(VALUE obj)
{
    return lookup_allocation_info(obj);
}

/*
 * call-seq: allocation_sourcefile(object) -> string
 *
 * Returns the source file origin from the given +object+.
 *
 * See ::trace_object_allocations for more information and examples.
 */
static VALUE
allocation_sourcefile(VALUE self, VALUE obj)
{
    struct allocation_info *info = lookup_allocation_info(obj);

    if (info && info->path) {
        return rb_str_new2(info->path);
    }
    else {
        return Qnil;
    }
}

/*
 * call-seq: allocation_sourceline(object) -> integer
 *
 * Returns the original line from source for from the given +object+.
 *
 * See ::trace_object_allocations for more information and examples.
 */
static VALUE
allocation_sourceline(VALUE self, VALUE obj)
{
    struct allocation_info *info = lookup_allocation_info(obj);

    if (info) {
        return INT2FIX(info->line);
    }
    else {
        return Qnil;
    }
}

/*
 * call-seq: allocation_class_path(object) -> string
 *
 * Returns the class for the given +object+.
 *
 *	class A
 *	  def foo
 *	    ObjectSpace::trace_object_allocations do
 *	      obj = Object.new
 *	      p "#{ObjectSpace::allocation_class_path(obj)}"
 *	    end
 *	  end
 *	end
 *
 *	A.new.foo #=> "Class"
 *
 * See ::trace_object_allocations for more information and examples.
 */
static VALUE
allocation_class_path(VALUE self, VALUE obj)
{
    struct allocation_info *info = lookup_allocation_info(obj);

    if (info && info->class_path) {
        return rb_str_new2(info->class_path);
    }
    else {
        return Qnil;
    }
}

/*
 * call-seq: allocation_method_id(object) -> string
 *
 * Returns the method identifier for the given +object+.
 *
 *	class A
 *	  include ObjectSpace
 *
 *	  def foo
 *	    trace_object_allocations do
 *	      obj = Object.new
 *	      p "#{allocation_class_path(obj)}##{allocation_method_id(obj)}"
 *	    end
 *	  end
 *	end
 *
 *	A.new.foo #=> "Class#new"
 *
 * See ::trace_object_allocations for more information and examples.
 */
static VALUE
allocation_method_id(VALUE self, VALUE obj)
{
    struct allocation_info *info = lookup_allocation_info(obj);
    if (info) {
        return info->mid;
    }
    else {
        return Qnil;
    }
}

/*
 * call-seq: allocation_generation(object) -> integer or nil
 *
 * Returns garbage collector generation for the given +object+.
 *
 *	class B
 *	  include ObjectSpace
 *
 *	  def foo
 *	    trace_object_allocations do
 *	      obj = Object.new
 *	      p "Generation is #{allocation_generation(obj)}"
 *	    end
 *	  end
 *	end
 *
 *	B.new.foo #=> "Generation is 3"
 *
 * See ::trace_object_allocations for more information and examples.
 */
static VALUE
allocation_generation(VALUE self, VALUE obj)
{
    struct allocation_info *info = lookup_allocation_info(obj);
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
#if 0
    rb_mObjSpace = rb_define_module("ObjectSpace"); /* let rdoc know */
#endif

    rb_define_module_function(rb_mObjSpace, "trace_object_allocations", trace_object_allocations, 0);
    rb_define_module_function(rb_mObjSpace, "trace_object_allocations_start", trace_object_allocations_start, 0);
    rb_define_module_function(rb_mObjSpace, "trace_object_allocations_stop", trace_object_allocations_stop, 0);
    rb_define_module_function(rb_mObjSpace, "trace_object_allocations_clear", trace_object_allocations_clear, 0);

    rb_define_module_function(rb_mObjSpace, "trace_object_allocations_debug_start", trace_object_allocations_debug_start, 0);

    rb_define_module_function(rb_mObjSpace, "allocation_sourcefile", allocation_sourcefile, 1);
    rb_define_module_function(rb_mObjSpace, "allocation_sourceline", allocation_sourceline, 1);
    rb_define_module_function(rb_mObjSpace, "allocation_class_path", allocation_class_path, 1);
    rb_define_module_function(rb_mObjSpace, "allocation_method_id", allocation_method_id, 1);
    rb_define_module_function(rb_mObjSpace, "allocation_generation", allocation_generation, 1);
}
