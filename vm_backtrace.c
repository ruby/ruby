/**********************************************************************

  vm_backtrace.c -

  $Author: ko1 $
  created at: Sun Jun 03 00:14:20 2012

  Copyright (C) 1993-2012 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"
#include "ruby/debug.h"

#include "vm_core.h"
#include "eval_intern.h"
#include "iseq.h"

static VALUE rb_cBacktrace;
static VALUE rb_cBacktraceLocation;

static VALUE
id2str(ID id)
{
    VALUE str = rb_id2str(id);
    if (!str) return Qnil;
    return str;
}
#define rb_id2str(id) id2str(id)

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
    struct valued_frame_info *vfi = (struct valued_frame_info *)ptr;
    rb_gc_mark(vfi->btobj);
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

static size_t
location_memsize(const void *ptr)
{
    /* rb_backtrace_location_t *fi = (rb_backtrace_location_t *)ptr; */
    return sizeof(rb_backtrace_location_t);
}

static const rb_data_type_t location_data_type = {
    "frame_info",
    {location_mark, RUBY_TYPED_DEFAULT_FREE, location_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
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

/*
 * Returns the line number of this frame.
 *
 * For example, using +caller_locations.rb+ from Thread::Backtrace::Location
 *
 *	loc = c(0..1).first
 *	loc.lineno #=> 2
 */
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

/*
 * Returns the label of this frame.
 *
 * Usually consists of method, class, module, etc names with decoration.
 *
 * Consider the following example:
 *
 *	def foo
 *	  puts caller_locations(0).first.label
 *
 *	  1.times do
 *	    puts caller_locations(0).first.label
 *
 *	    1.times do
 *	      puts caller_locations(0).first.label
 *	    end
 *
 *	  end
 *	end
 *
 * The result of calling +foo+ is this:
 *
 *	label: foo
 *	label: block in foo
 *	label: block (2 levels) in foo
 *
 */
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

/*
 * Returns the base label of this frame.
 *
 * Usually same as #label, without decoration.
 */
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

/*
 * Returns the file name of this frame.
 *
 * For example, using +caller_locations.rb+ from Thread::Backtrace::Location
 *
 *	loc = c(0..1).first
 *	loc.path #=> caller_locations.rb
 */
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

/*
 * Returns the full file path of this frame.
 *
 * Same as #path, but includes the absolute path.
 */
static VALUE
location_absolute_path_m(VALUE self)
{
    return location_absolute_path(location_ptr(self));
}

static VALUE
location_format(VALUE file, int lineno, VALUE name)
{
    VALUE s = rb_enc_sprintf(rb_enc_compatible(file, name), "%s", RSTRING_PTR(file));
    if (lineno != 0) {
	rb_str_catf(s, ":%d", lineno);
    }
    rb_str_cat_cstr(s, ":in ");
    if (NIL_P(name)) {
	rb_str_cat_cstr(s, "unknown method");
    }
    else {
	rb_str_catf(s, "`%s'", RSTRING_PTR(name));
    }
    return s;
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

/*
 * Returns a Kernel#caller style string representing this frame.
 */
static VALUE
location_to_str_m(VALUE self)
{
    return location_to_str(location_ptr(self));
}

/*
 * Returns the same as calling +inspect+ on the string representation of
 * #to_str
 */
static VALUE
location_inspect_m(VALUE self)
{
    return rb_str_inspect(location_to_str(location_ptr(self)));
}

typedef struct rb_backtrace_struct {
    rb_backtrace_location_t *backtrace;
    rb_backtrace_location_t *backtrace_base;
    int backtrace_size;
    VALUE strary;
    VALUE locary;
} rb_backtrace_t;

static void
backtrace_mark(void *ptr)
{
    rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
    size_t i, s = bt->backtrace_size;

    for (i=0; i<s; i++) {
	location_mark_entry(&bt->backtrace[i]);
    }
    rb_gc_mark(bt->strary);
    rb_gc_mark(bt->locary);
}

static void
backtrace_free(void *ptr)
{
   rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
   if (bt->backtrace) ruby_xfree(bt->backtrace_base);
   ruby_xfree(bt);
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
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
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
	       void (*iter_iseq)(void *arg, const rb_control_frame_t *cfp),
	       void (*iter_cfunc)(void *arg, const rb_control_frame_t *cfp, ID mid),
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
		iter_iseq(arg, cfp);
	    }
	}
	else if (RUBYVM_CFUNC_FRAME_P(cfp)) {
	    ID mid = cfp->me->def ? cfp->me->def->original_id : cfp->me->called_id;

	    iter_cfunc(arg, cfp, mid);
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
bt_iter_iseq(void *ptr, const rb_control_frame_t *cfp)
{
    const rb_iseq_t *iseq = cfp->iseq;
    const VALUE *pc = cfp->pc;
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    rb_backtrace_location_t *loc = &arg->bt->backtrace[arg->bt->backtrace_size++];
    loc->type = LOCATION_TYPE_ISEQ;
    loc->body.iseq.iseq = iseq;
    loc->body.iseq.lineno.pc = pc;
    arg->prev_loc = loc;
}

static void
bt_iter_cfunc(void *ptr, const rb_control_frame_t *cfp, ID mid)
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
backtrace_collect(rb_backtrace_t *bt, long lev, long n, VALUE (*func)(rb_backtrace_location_t *, void *arg), void *arg)
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

static VALUE
backtrace_to_str_ary(VALUE self, long lev, long n)
{
    rb_backtrace_t *bt;
    int size;
    VALUE r;

    GetCoreDataFromValue(self, rb_backtrace_t, bt);
    size = bt->backtrace_size;

    if (n == 0) {
	n = size;
    }
    if (lev > size) {
	return Qnil;
    }

    r = backtrace_collect(bt, lev, n, location_to_str_dmyarg, 0);
    RB_GC_GUARD(self);
    return r;
}

VALUE
rb_backtrace_to_str_ary(VALUE self)
{
    rb_backtrace_t *bt;
    GetCoreDataFromValue(self, rb_backtrace_t, bt);

    if (!bt->strary) {
	bt->strary = backtrace_to_str_ary(self, 0, bt->backtrace_size);
    }
    return bt->strary;
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
backtrace_to_location_ary(VALUE self, long lev, long n)
{
    rb_backtrace_t *bt;
    int size;
    VALUE r;

    GetCoreDataFromValue(self, rb_backtrace_t, bt);
    size = bt->backtrace_size;

    if (n == 0) {
	n = size;
    }
    if (lev > size) {
	return Qnil;
    }

    r = backtrace_collect(bt, lev, n, location_create, (void *)self);
    RB_GC_GUARD(self);
    return r;
}

VALUE
rb_backtrace_to_location_ary(VALUE self)
{
    rb_backtrace_t *bt;
    GetCoreDataFromValue(self, rb_backtrace_t, bt);

    if (!bt->locary) {
	bt->locary = backtrace_to_location_ary(self, 0, 0);
    }
    return bt->locary;
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
rb_vm_backtrace_str_ary(rb_thread_t *th, long lev, long n)
{
    return backtrace_to_str_ary(backtrace_object(th), lev, n);
}

VALUE
rb_vm_backtrace_location_ary(rb_thread_t *th, long lev, long n)
{
    return backtrace_to_location_ary(backtrace_object(th), lev, n);
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
oldbt_iter_iseq(void *ptr, const rb_control_frame_t *cfp)
{
    const rb_iseq_t *iseq = cfp->iseq;
    const VALUE *pc = cfp->pc;
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename = iseq->location.path;
    VALUE name = iseq->location.label;
    int lineno = arg->lineno = calc_lineno(iseq, pc);

    (arg->func)(arg->data, file, lineno, name);
}

static void
oldbt_iter_cfunc(void *ptr, const rb_control_frame_t *cfp, ID mid)
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
    int i = 0;

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

static void
oldbt_print_to(void *data, VALUE file, int lineno, VALUE name)
{
    VALUE output = (VALUE)data;
    VALUE str = rb_sprintf("\tfrom %"PRIsVALUE":%d:in ", file, lineno);

    if (NIL_P(name)) {
	rb_str_cat2(str, "unknown method\n");
    }
    else {
	rb_str_catf(str, " `%"PRIsVALUE"'\n", name);
    }
    rb_io_write(output, str);
}

void
rb_backtrace_print_to(VALUE output)
{
    struct oldbt_arg arg;

    arg.func = oldbt_print_to;
    arg.data = (void *)output;
    backtrace_each(GET_THREAD(),
		   oldbt_init,
		   oldbt_iter_iseq,
		   oldbt_iter_cfunc,
		   &arg);
}

VALUE
rb_make_backtrace(void)
{
    return rb_vm_backtrace_str_ary(GET_THREAD(), 0, 0);
}

static VALUE
vm_backtrace_to_ary(rb_thread_t *th, int argc, const VALUE *argv, int lev_default, int lev_plus, int to_str)
{
    VALUE level, vn;
    long lev, n;
    VALUE btval = backtrace_object(th);
    VALUE r;
    rb_backtrace_t *bt;

    GetCoreDataFromValue(btval, rb_backtrace_t, bt);

    rb_scan_args(argc, argv, "02", &level, &vn);

    if (argc == 2 && NIL_P(vn)) argc--;

    switch (argc) {
      case 0:
	lev = lev_default + lev_plus;
	n = bt->backtrace_size - lev;
	break;
      case 1:
	{
	    long beg, len;
	    switch (rb_range_beg_len(level, &beg, &len, bt->backtrace_size - lev_plus, 0)) {
	      case Qfalse:
		lev = NUM2LONG(level);
		if (lev < 0) {
		    rb_raise(rb_eArgError, "negative level (%ld)", lev);
		}
		lev += lev_plus;
		n = bt->backtrace_size - lev;
		break;
	      case Qnil:
		return Qnil;
	      default:
		lev = beg + lev_plus;
		n = len;
		break;
	    }
	    break;
	}
      case 2:
	lev = NUM2LONG(level);
	n = NUM2LONG(vn);
	if (lev < 0) {
	    rb_raise(rb_eArgError, "negative level (%ld)", lev);
	}
	if (n < 0) {
	    rb_raise(rb_eArgError, "negative size (%ld)", n);
	}
	lev += lev_plus;
	break;
      default:
	lev = n = 0; /* to avoid warning */
	break;
    }

    if (n == 0) {
	return rb_ary_new();
    }

    if (to_str) {
	r = backtrace_to_str_ary(btval, lev, n);
    }
    else {
	r = backtrace_to_location_ary(btval, lev, n);
    }
    RB_GC_GUARD(btval);
    return r;
}

static VALUE
thread_backtrace_to_ary(int argc, const VALUE *argv, VALUE thval, int to_str)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);

    if (th->to_kill || th->status == THREAD_KILLED)
	return Qnil;

    return vm_backtrace_to_ary(th, argc, argv, 0, 0, to_str);
}

VALUE
rb_vm_thread_backtrace(int argc, const VALUE *argv, VALUE thval)
{
    return thread_backtrace_to_ary(argc, argv, thval, 1);
}

VALUE
rb_vm_thread_backtrace_locations(int argc, const VALUE *argv, VALUE thval)
{
    return thread_backtrace_to_ary(argc, argv, thval, 0);
}

/*
 *  call-seq:
 *     caller(start=1, length=nil)  -> array or nil
 *     caller(range)		    -> array or nil
 *
 *  Returns the current execution stack---an array containing strings in
 *  the form <code>file:line</code> or <code>file:line: in
 *  `method'</code>.
 *
 *  The optional _start_ parameter determines the number of initial stack
 *  entries to omit from the top of the stack.
 *
 *  A second optional +length+ parameter can be used to limit how many entries
 *  are returned from the stack.
 *
 *  Returns +nil+ if _start_ is greater than the size of
 *  current execution stack.
 *
 *  Optionally you can pass a range, which will return an array containing the
 *  entries within the specified range.
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

/*
 *  call-seq:
 *     caller_locations(start=1, length=nil)	-> array or nil
 *     caller_locations(range)			-> array or nil
 *
 *  Returns the current execution stack---an array containing
 *  backtrace location objects.
 *
 *  See Thread::Backtrace::Location for more information.
 *
 *  The optional _start_ parameter determines the number of initial stack
 *  entries to omit from the top of the stack.
 *
 *  A second optional +length+ parameter can be used to limit how many entries
 *  are returned from the stack.
 *
 *  Returns +nil+ if _start_ is greater than the size of
 *  current execution stack.
 *
 *  Optionally you can pass a range, which will return an array containing the
 *  entries within the specified range.
 */
static VALUE
rb_f_caller_locations(int argc, VALUE *argv)
{
    return vm_backtrace_to_ary(GET_THREAD(), argc, argv, 1, 1, 0);
}

/* called from Init_vm() in vm.c */
void
Init_vm_backtrace(void)
{
    /* :nodoc: */
    rb_cBacktrace = rb_define_class_under(rb_cThread, "Backtrace", rb_cObject);
    rb_define_alloc_func(rb_cBacktrace, backtrace_alloc);
    rb_undef_method(CLASS_OF(rb_cBacktrace), "new");
    rb_marshal_define_compat(rb_cBacktrace, rb_cArray, backtrace_dump_data, backtrace_load_data);

    /*
     *	An object representation of a stack frame, initialized by
     *	Kernel#caller_locations.
     *
     *	For example:
     *
     *		# caller_locations.rb
     *		def a(skip)
     *		  caller_locations(skip)
     *		end
     *		def b(skip)
     *		  a(skip)
     *		end
     *		def c(skip)
     *		  b(skip)
     *		end
     *
     *		c(0..2).map do |call|
     *		  puts call.to_s
     *		end
     *
     *	Running <code>ruby caller_locations.rb</code> will produce:
     *
     *		caller_locations.rb:2:in `a'
     *		caller_locations.rb:5:in `b'
     *		caller_locations.rb:8:in `c'
     *
     *	Here's another example with a slightly different result:
     *
     *		# foo.rb
     *		class Foo
     *		  attr_accessor :locations
     *		  def initialize(skip)
     *		    @locations = caller_locations(skip)
     *		  end
     *		end
     *
     *		Foo.new(0..2).locations.map do |call|
     *		  puts call.to_s
     *		end
     *
     *	Now run <code>ruby foo.rb</code> and you should see:
     *
     *		init.rb:4:in `initialize'
     *		init.rb:8:in `new'
     *		init.rb:8:in `<main>'
     */
    rb_cBacktraceLocation = rb_define_class_under(rb_cBacktrace, "Location", rb_cObject);
    rb_undef_alloc_func(rb_cBacktraceLocation);
    rb_undef_method(CLASS_OF(rb_cBacktraceLocation), "new");
    rb_define_method(rb_cBacktraceLocation, "lineno", location_lineno_m, 0);
    rb_define_method(rb_cBacktraceLocation, "label", location_label_m, 0);
    rb_define_method(rb_cBacktraceLocation, "base_label", location_base_label_m, 0);
    rb_define_method(rb_cBacktraceLocation, "path", location_path_m, 0);
    rb_define_method(rb_cBacktraceLocation, "absolute_path", location_absolute_path_m, 0);
    rb_define_method(rb_cBacktraceLocation, "to_s", location_to_str_m, 0);
    rb_define_method(rb_cBacktraceLocation, "inspect", location_inspect_m, 0);

    rb_define_global_function("caller", rb_f_caller, -1);
    rb_define_global_function("caller_locations", rb_f_caller_locations, -1);
}

/* debugger API */

RUBY_SYMBOL_EXPORT_BEGIN

RUBY_SYMBOL_EXPORT_END

struct rb_debug_inspector_struct {
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    VALUE backtrace;
    VALUE contexts; /* [[klass, binding, iseq, cfp], ...] */
    long backtrace_size;
};

enum {
    CALLER_BINDING_SELF,
    CALLER_BINDING_CLASS,
    CALLER_BINDING_BINDING,
    CALLER_BINDING_ISEQ,
    CALLER_BINDING_CFP
};

struct collect_caller_bindings_data {
    VALUE ary;
};

static void
collect_caller_bindings_init(void *arg, size_t size)
{
    /* */
}

static VALUE
get_klass(const rb_control_frame_t *cfp)
{
    VALUE klass;
    if (rb_vm_control_frame_id_and_class(cfp, 0, &klass)) {
	if (RB_TYPE_P(klass, T_ICLASS)) {
	    return RBASIC(klass)->klass;
	}
	else {
	    return klass;
	}
    }
    else {
	return Qnil;
    }
}

static void
collect_caller_bindings_iseq(void *arg, const rb_control_frame_t *cfp)
{
    struct collect_caller_bindings_data *data = (struct collect_caller_bindings_data *)arg;
    VALUE frame = rb_ary_new2(5);

    rb_ary_store(frame, CALLER_BINDING_SELF, cfp->self);
    rb_ary_store(frame, CALLER_BINDING_CLASS, get_klass(cfp));
    rb_ary_store(frame, CALLER_BINDING_BINDING, GC_GUARDED_PTR(cfp)); /* create later */
    rb_ary_store(frame, CALLER_BINDING_ISEQ, cfp->iseq ? cfp->iseq->self : Qnil);
    rb_ary_store(frame, CALLER_BINDING_CFP, GC_GUARDED_PTR(cfp));

    rb_ary_push(data->ary, frame);
}

static void
collect_caller_bindings_cfunc(void *arg, const rb_control_frame_t *cfp, ID mid)
{
    struct collect_caller_bindings_data *data = (struct collect_caller_bindings_data *)arg;
    VALUE frame = rb_ary_new2(5);

    rb_ary_store(frame, CALLER_BINDING_SELF, cfp->self);
    rb_ary_store(frame, CALLER_BINDING_CLASS, get_klass(cfp));
    rb_ary_store(frame, CALLER_BINDING_BINDING, Qnil); /* not available */
    rb_ary_store(frame, CALLER_BINDING_ISEQ, Qnil); /* not available */
    rb_ary_store(frame, CALLER_BINDING_CFP, GC_GUARDED_PTR(cfp));

    rb_ary_push(data->ary, frame);
}

static VALUE
collect_caller_bindings(rb_thread_t *th)
{
    struct collect_caller_bindings_data data;
    VALUE result;
    int i;

    data.ary = rb_ary_new();

    backtrace_each(th,
		   collect_caller_bindings_init,
		   collect_caller_bindings_iseq,
		   collect_caller_bindings_cfunc,
		   &data);

    result = rb_ary_reverse(data.ary);

    /* bindings should be created from top of frame */
    for (i=0; i<RARRAY_LEN(result); i++) {
	VALUE entry = rb_ary_entry(result, i);
	VALUE cfp_val = rb_ary_entry(entry, CALLER_BINDING_BINDING);

	if (!NIL_P(cfp_val)) {
	    rb_control_frame_t *cfp = GC_GUARDED_PTR_REF(cfp_val);
	    rb_ary_store(entry, CALLER_BINDING_BINDING, rb_vm_make_binding(th, cfp));
	}
    }

    return result;
}

/*
 * Note that the passed `rb_debug_inspector_t' will be disabled
 * after `rb_debug_inspector_open'.
 */

VALUE
rb_debug_inspector_open(rb_debug_inspector_func_t func, void *data)
{
    rb_debug_inspector_t dbg_context;
    rb_thread_t *th = GET_THREAD();
    int state;
    volatile VALUE UNINITIALIZED_VAR(result);

    dbg_context.th = th;
    dbg_context.cfp = dbg_context.th->cfp;
    dbg_context.backtrace = rb_vm_backtrace_location_ary(th, 0, 0);
    dbg_context.backtrace_size = RARRAY_LEN(dbg_context.backtrace);
    dbg_context.contexts = collect_caller_bindings(th);

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	result = (*func)(&dbg_context, data);
    }
    TH_POP_TAG();

    /* invalidate bindings? */

    if (state) {
	JUMP_TAG(state);
    }

    return result;
}

static VALUE
frame_get(const rb_debug_inspector_t *dc, long index)
{
    if (index < 0 || index >= dc->backtrace_size) {
	rb_raise(rb_eArgError, "no such frame");
    }
    return rb_ary_entry(dc->contexts, index);
}

VALUE
rb_debug_inspector_frame_self_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_SELF);
}

VALUE
rb_debug_inspector_frame_class_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_CLASS);
}

VALUE
rb_debug_inspector_frame_binding_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_BINDING);
}

VALUE
rb_debug_inspector_frame_iseq_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_ISEQ);
}

VALUE
rb_debug_inspector_backtrace_locations(const rb_debug_inspector_t *dc)
{
    return dc->backtrace;
}

int
rb_profile_frames(int start, int limit, VALUE *buff, int *lines)
{
    int i;
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp, *end_cfp = RUBY_VM_END_CONTROL_FRAME(th);

    for (i=0; i<limit && cfp != end_cfp;) {
	if (cfp->iseq && cfp->pc) { /* should be NORMAL_ISEQ */
	    if (start > 0) {
		start--;
		continue;
	    }

	    /* record frame info */
	    buff[i] = cfp->iseq->self;
	    if (lines) lines[i] = calc_lineno(cfp->iseq, cfp->pc);
	    i++;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }

    return i;
}

#define frame2iseq(frame) frame

VALUE
rb_profile_frame_path(VALUE frame)
{
    return rb_iseq_path(frame2iseq(frame));
}

VALUE
rb_profile_frame_absolute_path(VALUE frame)
{
    return rb_iseq_absolute_path(frame2iseq(frame));
}

VALUE
rb_profile_frame_label(VALUE frame)
{
    return rb_iseq_label(frame2iseq(frame));
}

VALUE
rb_profile_frame_base_label(VALUE frame)
{
    return rb_iseq_base_label(frame2iseq(frame));
}

VALUE
rb_profile_frame_first_lineno(VALUE frame)
{
    return rb_iseq_first_lineno(frame2iseq(frame));
}

VALUE
rb_profile_frame_classpath(VALUE frame)
{
    VALUE klass = rb_iseq_klass(frame2iseq(frame));

    if (klass && !NIL_P(klass)) {
	if (RB_TYPE_P(klass, T_ICLASS)) {
	    klass = RBASIC(klass)->klass;
	}
	else if (FL_TEST(klass, FL_SINGLETON)) {
	    klass = rb_ivar_get(klass, id__attached__);
	    if (!RB_TYPE_P(klass, T_CLASS))
		return rb_sprintf("#<%s:%p>", rb_class2name(rb_obj_class(klass)), (void*)klass);
	}
	return rb_class_path(klass);
    }
    else {
	return Qnil;
    }
}

VALUE
rb_profile_frame_singleton_method_p(VALUE frame)
{
    VALUE klass = rb_iseq_klass(frame2iseq(frame));
    if (klass && !NIL_P(klass) && FL_TEST(klass, FL_SINGLETON)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

VALUE
rb_profile_frame_method_name(VALUE frame)
{
    return rb_iseq_method_name(frame2iseq(frame));
}

VALUE
rb_profile_frame_qualified_method_name(VALUE frame)
{
    VALUE method_name = rb_iseq_method_name(frame2iseq(frame));
    if (method_name != Qnil) {
	VALUE classpath = rb_profile_frame_classpath(frame);
	VALUE singleton_p = rb_profile_frame_singleton_method_p(frame);

	if (classpath != Qnil) {
	    return rb_sprintf("%"PRIsVALUE"%s%"PRIsVALUE,
			      classpath, singleton_p == Qtrue ? "." : "#", method_name);
	}
	else {
	    return method_name;
	}
    }
    else {
	return Qnil;
    }
}

VALUE
rb_profile_frame_full_label(VALUE frame)
{
    VALUE label = rb_profile_frame_label(frame);
    VALUE base_label = rb_profile_frame_base_label(frame);
    VALUE qualified_method_name = rb_profile_frame_qualified_method_name(frame);

    if (NIL_P(qualified_method_name) || base_label == qualified_method_name) {
	return label;
    }
    else {
	long label_length = RSTRING_LEN(label);
	long base_label_length = RSTRING_LEN(base_label);
	int prefix_len = rb_long2int(label_length - base_label_length);

	return rb_sprintf("%.*s%"PRIsVALUE, prefix_len, RSTRING_PTR(label), qualified_method_name);
    }
}
