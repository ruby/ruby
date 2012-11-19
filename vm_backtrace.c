/**********************************************************************

  vm_backtrace.c -

  $Author: ko1 $
  created at: Sun Jun 03 00:14:20 2012

  Copyright (C) 1993-2012 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"

#include "internal.h"
#include "vm_core.h"
#include "iseq.h"

static VALUE rb_cBacktrace;
static VALUE rb_cBacktraceLocation;

extern VALUE ruby_engine_name;

inline static int
calc_lineno(const rb_iseq_t *iseq, const VALUE *pc)
{
    return rb_iseq_line_no(iseq, pc - iseq->iseq_encoded);
}

int
rb_vm_get_sourceline(const rb_control_frame_t *cfp)
{
    int lineno = 0;
    const rb_iseq_t *iseq = cfp->iseq;

    if (RUBY_VM_NORMAL_ISEQ_P(iseq)) {
	lineno = calc_lineno(cfp->iseq, cfp->pc);
    }
    return lineno;
}

typedef struct rb_backtrace_location_struct {
    enum LOCATION_TYPE {
	LOCATION_TYPE_ISEQ = 1,
	LOCATION_TYPE_ISEQ_CALCED,
	LOCATION_TYPE_CFUNC,
	LOCATION_TYPE_IFUNC
    } type;

    union {
	struct {
	    const rb_iseq_t *iseq;
	    union {
		const VALUE *pc;
		int lineno;
	    } lineno;
	} iseq;
	struct {
	    ID mid;
	    struct rb_backtrace_location_struct *prev_loc;
	} cfunc;
    } body;
} rb_backtrace_location_t;

struct valued_frame_info {
    rb_backtrace_location_t *loc;
    VALUE btobj;
};

static void
location_mark(void *ptr)
{
    if (ptr) {
	struct valued_frame_info *vfi = (struct valued_frame_info *)ptr;
	rb_gc_mark(vfi->btobj);
    }
}

static void
location_mark_entry(rb_backtrace_location_t *fi)
{
    switch (fi->type) {
      case LOCATION_TYPE_ISEQ:
      case LOCATION_TYPE_ISEQ_CALCED:
	rb_gc_mark(fi->body.iseq.iseq->self);
	break;
      case LOCATION_TYPE_CFUNC:
      case LOCATION_TYPE_IFUNC:
      default:
	break;
    }
}

static void
location_free(void *ptr)
{
    if (ptr) {
	rb_backtrace_location_t *fi = (rb_backtrace_location_t *)ptr;
	ruby_xfree(fi);
    }
}

static size_t
location_memsize(const void *ptr)
{
    /* rb_backtrace_location_t *fi = (rb_backtrace_location_t *)ptr; */
    return sizeof(rb_backtrace_location_t);
}

static const rb_data_type_t location_data_type = {
    "frame_info",
    {location_mark, location_free, location_memsize,},
};

static inline rb_backtrace_location_t *
location_ptr(VALUE locobj)
{
    struct valued_frame_info *vloc;
    GetCoreDataFromValue(locobj, struct valued_frame_info, vloc);
    return vloc->loc;
}

static int
location_lineno(rb_backtrace_location_t *loc)
{
    switch (loc->type) {
      case LOCATION_TYPE_ISEQ:
	loc->type = LOCATION_TYPE_ISEQ_CALCED;
	return (loc->body.iseq.lineno.lineno = calc_lineno(loc->body.iseq.iseq, loc->body.iseq.lineno.pc));
      case LOCATION_TYPE_ISEQ_CALCED:
	return loc->body.iseq.lineno.lineno;
      case LOCATION_TYPE_CFUNC:
	if (loc->body.cfunc.prev_loc) {
	    return location_lineno(loc->body.cfunc.prev_loc);
	}
	return 0;
      default:
	rb_bug("location_lineno: unreachable");
	UNREACHABLE;
    }
}

static VALUE
location_lineno_m(VALUE self)
{
    return INT2FIX(location_lineno(location_ptr(self)));
}

static VALUE
location_label(rb_backtrace_location_t *loc)
{
    switch (loc->type) {
      case LOCATION_TYPE_ISEQ:
      case LOCATION_TYPE_ISEQ_CALCED:
	return loc->body.iseq.iseq->location.label;
      case LOCATION_TYPE_CFUNC:
	return rb_id2str(loc->body.cfunc.mid);
      case LOCATION_TYPE_IFUNC:
      default:
	rb_bug("location_label: unreachable");
	UNREACHABLE;
    }
}

static VALUE
location_label_m(VALUE self)
{
    return location_label(location_ptr(self));
}

static VALUE
location_base_label(rb_backtrace_location_t *loc)
{
    switch (loc->type) {
      case LOCATION_TYPE_ISEQ:
      case LOCATION_TYPE_ISEQ_CALCED:
	return loc->body.iseq.iseq->location.base_label;
      case LOCATION_TYPE_CFUNC:
	return rb_sym_to_s(ID2SYM(loc->body.cfunc.mid));
      case LOCATION_TYPE_IFUNC:
      default:
	rb_bug("location_base_label: unreachable");
	UNREACHABLE;
    }
}

static VALUE
location_base_label_m(VALUE self)
{
    return location_base_label(location_ptr(self));
}

static VALUE
location_path(rb_backtrace_location_t *loc)
{
    switch (loc->type) {
      case LOCATION_TYPE_ISEQ:
      case LOCATION_TYPE_ISEQ_CALCED:
	return loc->body.iseq.iseq->location.path;
      case LOCATION_TYPE_CFUNC:
	if (loc->body.cfunc.prev_loc) {
	    return location_path(loc->body.cfunc.prev_loc);
	}
	return Qnil;
      case LOCATION_TYPE_IFUNC:
      default:
	rb_bug("location_path: unreachable");
	UNREACHABLE;
    }
}

static VALUE
location_path_m(VALUE self)
{
    return location_path(location_ptr(self));
}

static VALUE
location_absolute_path(rb_backtrace_location_t *loc)
{
    switch (loc->type) {
      case LOCATION_TYPE_ISEQ:
      case LOCATION_TYPE_ISEQ_CALCED:
	return loc->body.iseq.iseq->location.absolute_path;
      case LOCATION_TYPE_CFUNC:
	if (loc->body.cfunc.prev_loc) {
	    return location_absolute_path(loc->body.cfunc.prev_loc);
	}
	return Qnil;
      case LOCATION_TYPE_IFUNC:
      default:
	rb_bug("location_absolute_path: unreachable");
	UNREACHABLE;
    }
}

static VALUE
location_absolute_path_m(VALUE self)
{
    return location_absolute_path(location_ptr(self));
}

static VALUE
location_format(VALUE file, int lineno, VALUE name)
{
    if (lineno != 0) {
	return rb_enc_sprintf(rb_enc_compatible(file, name), "%s:%d:in `%s'",
			      RSTRING_PTR(file), lineno, RSTRING_PTR(name));
    }
    else {
	return rb_enc_sprintf(rb_enc_compatible(file, name), "%s:in `%s'",
			      RSTRING_PTR(file), RSTRING_PTR(name));
    }
}

static VALUE
location_to_str(rb_backtrace_location_t *loc)
{
    VALUE file, name;
    int lineno;

    switch (loc->type) {
      case LOCATION_TYPE_ISEQ:
	file = loc->body.iseq.iseq->location.path;
	name = loc->body.iseq.iseq->location.label;

	lineno = loc->body.iseq.lineno.lineno = calc_lineno(loc->body.iseq.iseq, loc->body.iseq.lineno.pc);
	loc->type = LOCATION_TYPE_ISEQ_CALCED;
	break;
      case LOCATION_TYPE_ISEQ_CALCED:
	file = loc->body.iseq.iseq->location.path;
	lineno = loc->body.iseq.lineno.lineno;
	name = loc->body.iseq.iseq->location.label;
	break;
      case LOCATION_TYPE_CFUNC:
	if (loc->body.cfunc.prev_loc) {
	    file = loc->body.cfunc.prev_loc->body.iseq.iseq->location.path;
	    lineno = location_lineno(loc->body.cfunc.prev_loc);
	}
	else {
	    rb_thread_t *th = GET_THREAD();
	    file = th->vm->progname ? th->vm->progname : ruby_engine_name;
	    lineno = INT2FIX(0);
	}
	name = rb_id2str(loc->body.cfunc.mid);
	break;
      case LOCATION_TYPE_IFUNC:
      default:
	rb_bug("location_to_str: unreachable");
    }

    return location_format(file, lineno, name);
}

static VALUE
location_to_str_m(VALUE self)
{
    return location_to_str(location_ptr(self));
}

typedef struct rb_backtrace_struct {
    rb_backtrace_location_t *backtrace;
    rb_backtrace_location_t *backtrace_base;
    int backtrace_size;
    VALUE strary;
} rb_backtrace_t;

static void
backtrace_mark(void *ptr)
{
    if (ptr) {
	rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
	size_t i, s = bt->backtrace_size;

	for (i=0; i<s; i++) {
	    location_mark_entry(&bt->backtrace[i]);
	    rb_gc_mark(bt->strary);
	}
    }
}

static void
backtrace_free(void *ptr)
{
   if (ptr) {
       rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
       if (bt->backtrace) ruby_xfree(bt->backtrace_base);
       ruby_xfree(bt);
   }
}

static size_t
backtrace_memsize(const void *ptr)
{
    rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
    return sizeof(rb_backtrace_t) + sizeof(rb_backtrace_location_t) * bt->backtrace_size;
}

static const rb_data_type_t backtrace_data_type = {
    "backtrace",
    {backtrace_mark, backtrace_free, backtrace_memsize,},
};

int
rb_backtrace_p(VALUE obj)
{
    return rb_typeddata_is_kind_of(obj, &backtrace_data_type);
}

static VALUE
backtrace_alloc(VALUE klass)
{
    rb_backtrace_t *bt;
    VALUE obj = TypedData_Make_Struct(klass, rb_backtrace_t, &backtrace_data_type, bt);
    return obj;
}

static void
backtrace_each(rb_thread_t *th,
	       void (*init)(void *arg, size_t size),
	       void (*iter_iseq)(void *arg, const rb_iseq_t *iseq, const VALUE *pc),
	       void (*iter_cfunc)(void *arg, ID mid),
	       void *arg)
{
    rb_control_frame_t *last_cfp = th->cfp;
    rb_control_frame_t *start_cfp = RUBY_VM_END_CONTROL_FRAME(th);
    rb_control_frame_t *cfp;
    ptrdiff_t size, i;

    /*                <- start_cfp (end control frame)
     *  top frame (dummy)
     *  top frame (dummy)
     *  top frame     <- start_cfp
     *  top frame
     *  ...
     *  2nd frame     <- lev:0
     *  current frame <- th->cfp
     */

    start_cfp =
      RUBY_VM_NEXT_CONTROL_FRAME(
	  RUBY_VM_NEXT_CONTROL_FRAME(start_cfp)); /* skip top frames */

    if (start_cfp < last_cfp) {
	size = 0;
    }
    else {
	size = start_cfp - last_cfp + 1;
    }

    init(arg, size);

    /* SDR(); */
    for (i=0, cfp = start_cfp; i<size; i++, cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp)) {
	/* fprintf(stderr, "cfp: %d\n", (rb_control_frame_t *)(th->stack + th->stack_size) - cfp); */
	if (cfp->iseq) {
	    if (cfp->pc) {
		iter_iseq(arg, cfp->iseq, cfp->pc);
	    }
	}
	else if (RUBYVM_CFUNC_FRAME_P(cfp)) {
	    ID mid = cfp->me->def ? cfp->me->def->original_id : cfp->me->called_id;

	    iter_cfunc(arg, mid);
	}
    }
}

struct bt_iter_arg {
    rb_backtrace_t *bt;
    VALUE btobj;
    rb_backtrace_location_t *prev_loc;
};

static void
bt_init(void *ptr, size_t size)
{
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    arg->btobj = backtrace_alloc(rb_cBacktrace);
    GetCoreDataFromValue(arg->btobj, rb_backtrace_t, arg->bt);
    arg->bt->backtrace_base = arg->bt->backtrace = ruby_xmalloc(sizeof(rb_backtrace_location_t) * size);
    arg->bt->backtrace_size = 0;
}

static void
bt_iter_iseq(void *ptr, const rb_iseq_t *iseq, const VALUE *pc)
{
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    rb_backtrace_location_t *loc = &arg->bt->backtrace[arg->bt->backtrace_size++];
    loc->type = LOCATION_TYPE_ISEQ;
    loc->body.iseq.iseq = iseq;
    loc->body.iseq.lineno.pc = pc;
    arg->prev_loc = loc;
}

static void
bt_iter_cfunc(void *ptr, ID mid)
{
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    rb_backtrace_location_t *loc = &arg->bt->backtrace[arg->bt->backtrace_size++];
    loc->type = LOCATION_TYPE_CFUNC;
    loc->body.cfunc.mid = mid;
    loc->body.cfunc.prev_loc = arg->prev_loc;
}

static VALUE
backtrace_object(rb_thread_t *th)
{
    struct bt_iter_arg arg;
    arg.prev_loc = 0;

    backtrace_each(th,
		   bt_init,
		   bt_iter_iseq,
		   bt_iter_cfunc,
		   &arg);

    return arg.btobj;
}

VALUE
rb_vm_backtrace_object(void)
{
    return backtrace_object(GET_THREAD());
}

static VALUE
backtrace_collect(rb_backtrace_t *bt, int lev, int n, VALUE (*func)(rb_backtrace_location_t *, void *arg), void *arg)
{
    VALUE btary;
    int i;

    if (UNLIKELY(lev < 0 || n < 0)) {
	rb_bug("backtrace_collect: unreachable");
    }

    btary = rb_ary_new();

    for (i=0; i+lev<bt->backtrace_size && i<n; i++) {
	rb_backtrace_location_t *loc = &bt->backtrace[bt->backtrace_size - 1 - (lev+i)];
	rb_ary_push(btary, func(loc, arg));
    }

    return btary;
}

static VALUE
location_to_str_dmyarg(rb_backtrace_location_t *loc, void *dmy)
{
    return location_to_str(loc);
}

VALUE
rb_backtrace_to_str_ary(VALUE self)
{
    rb_backtrace_t *bt;
    GetCoreDataFromValue(self, rb_backtrace_t, bt);

    if (bt->strary) {
	return bt->strary;
    }
    else {
	bt->strary = backtrace_collect(bt, 0, bt->backtrace_size, location_to_str_dmyarg, 0);
	return bt->strary;
    }
}

static VALUE
backtrace_to_str_ary2(VALUE self, int lev, int n)
{
    rb_backtrace_t *bt;
    int size;
    GetCoreDataFromValue(self, rb_backtrace_t, bt);
    size = bt->backtrace_size;

    if (n == 0) {
	n = size;
    }
    if (lev > size) {
	return Qnil;
    }

    return backtrace_collect(bt, lev, n, location_to_str_dmyarg, 0);
}

static VALUE
location_create(rb_backtrace_location_t *srcloc, void *btobj)
{
    VALUE obj;
    struct valued_frame_info *vloc;
    obj = TypedData_Make_Struct(rb_cBacktraceLocation, struct valued_frame_info, &location_data_type, vloc);

    vloc->loc = srcloc;
    vloc->btobj = (VALUE)btobj;

    return obj;
}

static VALUE
backtrace_to_frame_ary(VALUE self, int lev, int n)
{
    rb_backtrace_t *bt;
    int size;
    GetCoreDataFromValue(self, rb_backtrace_t, bt);
    size = bt->backtrace_size;

    if (n == 0) {
	n = size;
    }
    if (lev > size) {
	return Qnil;
    }

    return backtrace_collect(bt, lev, n, location_create, (void *)self);
}

static VALUE
backtrace_dump_data(VALUE self)
{
    VALUE str = rb_backtrace_to_str_ary(self);
    return str;
}

static VALUE
backtrace_load_data(VALUE self, VALUE str)
{
    rb_backtrace_t *bt;
    GetCoreDataFromValue(self, rb_backtrace_t, bt);
    bt->strary = str;
    return self;
}

VALUE
vm_backtrace_str_ary(rb_thread_t *th, int lev, int n)
{
    return backtrace_to_str_ary2(backtrace_object(th), lev, n);
}

VALUE
vm_backtrace_frame_ary(rb_thread_t *th, int lev, int n)
{
    return backtrace_to_frame_ary(backtrace_object(th), lev, n);
}

/* make old style backtrace directly */

struct oldbt_arg {
    VALUE filename;
    int lineno;
    void (*func)(void *data, VALUE file, int lineno, VALUE name);
    void *data; /* result */
};

static void
oldbt_init(void *ptr, size_t dmy)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    rb_thread_t *th = GET_THREAD();

    arg->filename = th->vm->progname ? th->vm->progname : ruby_engine_name;;
    arg->lineno = 0;
}

static void
oldbt_iter_iseq(void *ptr, const rb_iseq_t *iseq, const VALUE *pc)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename = iseq->location.path;
    VALUE name = iseq->location.label;
    int lineno = arg->lineno = calc_lineno(iseq, pc);

    (arg->func)(arg->data, file, lineno, name);
}

static void
oldbt_iter_cfunc(void *ptr, ID mid)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename;
    VALUE name = rb_id2str(mid);
    int lineno = arg->lineno;

    (arg->func)(arg->data, file, lineno, name);
}

static void
oldbt_print(void *data, VALUE file, int lineno, VALUE name)
{
    FILE *fp = (FILE *)data;

    if (NIL_P(name)) {
	fprintf(fp, "\tfrom %s:%d:in unknown method\n",
		RSTRING_PTR(file), lineno);
    }
    else {
	fprintf(fp, "\tfrom %s:%d:in `%s'\n",
		RSTRING_PTR(file), lineno, RSTRING_PTR(name));
    }
}

static void
vm_backtrace_print(FILE *fp)
{
    struct oldbt_arg arg;

    arg.func = oldbt_print;
    arg.data = (void *)fp;
    backtrace_each(GET_THREAD(),
		   oldbt_init,
		   oldbt_iter_iseq,
		   oldbt_iter_cfunc,
		   &arg);
}

static void
oldbt_bugreport(void *arg, VALUE file, int line, VALUE method)
{
    const char *filename = NIL_P(file) ? "ruby" : RSTRING_PTR(file);
    if (!*(int *)arg) {
	fprintf(stderr, "-- Ruby level backtrace information "
		"----------------------------------------\n");
	*(int *)arg = 1;
    }
    if (NIL_P(method)) {
	fprintf(stderr, "%s:%d:in unknown method\n", filename, line);
    }
    else {
	fprintf(stderr, "%s:%d:in `%s'\n", filename, line, RSTRING_PTR(method));
    }
}

void
rb_backtrace_print_as_bugreport(void)
{
    struct oldbt_arg arg;
    int i;

    arg.func = oldbt_bugreport;
    arg.data = (int *)&i;

    backtrace_each(GET_THREAD(),
		   oldbt_init,
		   oldbt_iter_iseq,
		   oldbt_iter_cfunc,
		   &arg);
}

void
rb_backtrace(void)
{
    vm_backtrace_print(stderr);
}

VALUE
rb_make_backtrace(void)
{
    return vm_backtrace_str_ary(GET_THREAD(), 0, 0);
}

static VALUE
vm_backtrace_to_ary(rb_thread_t *th, int argc, VALUE *argv, int lev_deafult, int lev_plus, int to_str)
{
    VALUE level, vn;
    int lev, n;

    rb_scan_args(argc, argv, "02", &level, &vn);

    lev = NIL_P(level) ? lev_deafult : NUM2INT(level);

    if (NIL_P(vn)) {
	n = 0;
    }
    else {
	n = NUM2INT(vn);
	if (n == 0) {
	    return rb_ary_new();
	}
    }

    if (lev < 0) {
	rb_raise(rb_eArgError, "negative level (%d)", lev);
    }
    if (n < 0) {
	rb_raise(rb_eArgError, "negative n (%d)", n);
    }

    if (to_str) {
	return vm_backtrace_str_ary(th, lev+lev_plus, n);
    }
    else {
	return vm_backtrace_frame_ary(th, lev+lev_plus, n);
    }
}

static VALUE
thread_backtrace_to_ary(int argc, VALUE *argv, VALUE thval, int to_str)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);

    switch (th->status) {
      case THREAD_RUNNABLE:
      case THREAD_STOPPED:
      case THREAD_STOPPED_FOREVER:
	break;
      case THREAD_TO_KILL:
      case THREAD_KILLED:
	return Qnil;
    }

    return vm_backtrace_to_ary(th, argc, argv, 0, 0, to_str);
}

VALUE
vm_thread_backtrace(int argc, VALUE *argv, VALUE thval)
{
    return thread_backtrace_to_ary(argc, argv, thval, 1);
}

VALUE
vm_thread_backtrace_locations(int argc, VALUE *argv, VALUE thval)
{
    return thread_backtrace_to_ary(argc, argv, thval, 0);
}

/*
 *  call-seq:
 *     caller(start=1)    -> array or nil
 *
 *  Returns the current execution stack---an array containing strings in
 *  the form ``<em>file:line</em>'' or ``<em>file:line: in
 *  `method'</em>''. The optional _start_ parameter
 *  determines the number of initial stack entries to omit from the
 *  result.
 *
 *  Returns +nil+ if _start_ is greater than the size of
 *  current execution stack.
 *
 *     def a(skip)
 *       caller(skip)
 *     end
 *     def b(skip)
 *       a(skip)
 *     end
 *     def c(skip)
 *       b(skip)
 *     end
 *     c(0)   #=> ["prog:2:in `a'", "prog:5:in `b'", "prog:8:in `c'", "prog:10:in `<main>'"]
 *     c(1)   #=> ["prog:5:in `b'", "prog:8:in `c'", "prog:11:in `<main>'"]
 *     c(2)   #=> ["prog:8:in `c'", "prog:12:in `<main>'"]
 *     c(3)   #=> ["prog:13:in `<main>'"]
 *     c(4)   #=> []
 *     c(5)   #=> nil
 */

static VALUE
rb_f_caller(int argc, VALUE *argv)
{
    return vm_backtrace_to_ary(GET_THREAD(), argc, argv, 1, 1, 1);
}

static VALUE
rb_f_caller_locations(int argc, VALUE *argv)
{
    return vm_backtrace_to_ary(GET_THREAD(), argc, argv, 1, 1, 0);
}

/* called from Init_vm() in vm.c */
void
Init_vm_backtrace(void)
{
    /* ::RubyVM::Backtrace */
    rb_cBacktrace = rb_define_class_under(rb_cRubyVM, "Backtrace", rb_cObject);
    rb_define_alloc_func(rb_cBacktrace, backtrace_alloc);
    rb_undef_method(CLASS_OF(rb_cBacktrace), "new");
    rb_marshal_define_compat(rb_cBacktrace, rb_cArray, backtrace_dump_data, backtrace_load_data);

    /* ::RubyVM::Backtrace::Location */
    rb_cBacktraceLocation = rb_define_class_under(rb_cBacktrace, "Location", rb_cObject);
    rb_undef_alloc_func(rb_cBacktraceLocation);
    rb_undef_method(CLASS_OF(rb_cBacktraceLocation), "new");
    rb_define_method(rb_cBacktraceLocation, "lineno", location_lineno_m, 0);
    rb_define_method(rb_cBacktraceLocation, "label", location_label_m, 0);
    rb_define_method(rb_cBacktraceLocation, "base_label", location_base_label_m, 0);
    rb_define_method(rb_cBacktraceLocation, "path", location_path_m, 0);
    rb_define_method(rb_cBacktraceLocation, "absolute_path", location_absolute_path_m, 0);
    rb_define_method(rb_cBacktraceLocation, "to_s", location_to_str_m, 0);

    rb_define_global_function("caller", rb_f_caller, -1);
    rb_define_global_function("caller_locations", rb_f_caller_locations, -1);
}
