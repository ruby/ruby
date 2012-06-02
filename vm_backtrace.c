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
static VALUE rb_cFrameInfo;

extern VALUE ruby_engine_name;

inline static int
calc_line_no(const rb_iseq_t *iseq, const VALUE *pc)
{
    return rb_iseq_line_no(iseq, pc - iseq->iseq_encoded);
}

int
rb_vm_get_sourceline(const rb_control_frame_t *cfp)
{
    int line_no = 0;
    const rb_iseq_t *iseq = cfp->iseq;

    if (RUBY_VM_NORMAL_ISEQ_P(iseq)) {
	line_no = calc_line_no(cfp->iseq, cfp->pc);
    }
    return line_no;
}

typedef struct rb_frame_info_struct {
    enum FRAME_INFO_TYPE {
	FRAME_INFO_TYPE_ISEQ = 1,
	FRAME_INFO_TYPE_ISEQ_CALCED,
	FRAME_INFO_TYPE_CFUNC,
	FRAME_INFO_TYPE_IFUNC,
    } type;

    union {
	struct {
	    const rb_iseq_t *iseq;
	    union {
		const VALUE *pc;
		int line_no;
	    } line_no;
	} iseq;
	struct {
	    ID mid;
	    struct rb_frame_info_struct *prev_fi;
	} cfunc;
    } body;
} rb_frame_info_t;

struct valued_frame_info {
    rb_frame_info_t *fi;
    VALUE btobj;
};

static void
frame_info_mark(void *ptr)
{
    if (ptr) {
	struct valued_frame_info *vfi = (struct valued_frame_info *)ptr;
	rb_gc_mark(vfi->btobj);
    }
}

static void
frame_info_mark_entry(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	rb_gc_mark(fi->body.iseq.iseq->self);
	break;
      case FRAME_INFO_TYPE_CFUNC:
      case FRAME_INFO_TYPE_IFUNC:
      default:
	break;
    }
}

static void
frame_info_free(void *ptr)
{
    if (ptr) {
	rb_frame_info_t *fi = (rb_frame_info_t *)ptr;
	ruby_xfree(fi);
    }
}

static size_t
frame_info_memsize(const void *ptr)
{
    /* rb_frame_info_t *fi = (rb_frame_info_t *)ptr; */
    return sizeof(rb_frame_info_t);
}

static const rb_data_type_t frame_info_data_type = {
    "frame_info",
    {frame_info_mark, frame_info_free, frame_info_memsize,},
};

static inline rb_frame_info_t *
frame_info_ptr(VALUE fiobj)
{
    struct valued_frame_info *vfi;
    GetCoreDataFromValue(fiobj, struct valued_frame_info, vfi);
    return vfi->fi;
}

static int
frame_info_line_no(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
	fi->type = FRAME_INFO_TYPE_ISEQ_CALCED;
	return (fi->body.iseq.line_no.line_no = calc_line_no(fi->body.iseq.iseq, fi->body.iseq.line_no.pc));
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	return fi->body.iseq.line_no.line_no;
      case FRAME_INFO_TYPE_CFUNC:
	if (fi->body.cfunc.prev_fi) {
	    return frame_info_line_no(fi->body.cfunc.prev_fi);
	}
	return 0;
      default:
	rb_bug("frame_info_line_no: unreachable");
	UNREACHABLE;
    }
}

static VALUE
frame_info_line_no_m(VALUE self)
{
    return INT2FIX(frame_info_line_no(frame_info_ptr(self)));
}

static VALUE
frame_info_name(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	return fi->body.iseq.iseq->location.name;
      case FRAME_INFO_TYPE_CFUNC:
	return rb_id2str(fi->body.cfunc.mid);
      case FRAME_INFO_TYPE_IFUNC:
      default:
	rb_bug("frame_info_name: unreachable");
	UNREACHABLE;
    }
}

static VALUE
frame_info_name_m(VALUE self)
{
    return frame_info_name(frame_info_ptr(self));
}

static VALUE
frame_info_basename(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	return fi->body.iseq.iseq->location.basename;
      case FRAME_INFO_TYPE_CFUNC:
	return rb_sym_to_s(ID2SYM(fi->body.cfunc.mid));
      case FRAME_INFO_TYPE_IFUNC:
      default:
	rb_bug("frame_info_basename: unreachable");
	UNREACHABLE;
    }
}

static VALUE
frame_info_basename_m(VALUE self)
{
    return frame_info_basename(frame_info_ptr(self));
}

static VALUE
frame_info_filename(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	return fi->body.iseq.iseq->location.filename;
      case FRAME_INFO_TYPE_CFUNC:
	if (fi->body.cfunc.prev_fi) {
	    return frame_info_filename(fi->body.cfunc.prev_fi);
	}
	return Qnil;
      case FRAME_INFO_TYPE_IFUNC:
      default:
	rb_bug("frame_info_filename: unreachable");
	UNREACHABLE;
    }
}

static VALUE
frame_info_filename_m(VALUE self)
{
    return frame_info_filename(frame_info_ptr(self));
}

static VALUE
frame_info_filepath(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	return fi->body.iseq.iseq->location.filepath;
      case FRAME_INFO_TYPE_CFUNC:
	if (fi->body.cfunc.prev_fi) {
	    return frame_info_filepath(fi->body.cfunc.prev_fi);
	}
	return Qnil;
      case FRAME_INFO_TYPE_IFUNC:
      default:
	rb_bug("frame_info_filepath: unreachable");
	UNREACHABLE;
    }
}

static VALUE
frame_info_filepath_m(VALUE self)
{
    return frame_info_filepath(frame_info_ptr(self));
}

static VALUE
frame_info_iseq(rb_frame_info_t *fi)
{
    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	return fi->body.iseq.iseq->self;
      default:
	return Qnil;
    }
}

static VALUE
frame_info_iseq_m(VALUE self)
{
    return frame_info_iseq(frame_info_ptr(self));
}

static VALUE
frame_info_format(VALUE file, int line_no, VALUE name)
{
    if (line_no != 0) {
	return rb_enc_sprintf(rb_enc_compatible(file, name), "%s:%d:in `%s'",
			      RSTRING_PTR(file), line_no, RSTRING_PTR(name));
    }
    else {
	return rb_enc_sprintf(rb_enc_compatible(file, name), "%s:in `%s'",
			      RSTRING_PTR(file), RSTRING_PTR(name));
    }
}

static VALUE
frame_info_to_str(rb_frame_info_t *fi)
{
    VALUE file, name;
    int line_no;

    switch (fi->type) {
      case FRAME_INFO_TYPE_ISEQ:
	file = fi->body.iseq.iseq->location.filename;
	name = fi->body.iseq.iseq->location.name;

	line_no = fi->body.iseq.line_no.line_no = calc_line_no(fi->body.iseq.iseq, fi->body.iseq.line_no.pc);
	fi->type = FRAME_INFO_TYPE_ISEQ_CALCED;
	break;
      case FRAME_INFO_TYPE_ISEQ_CALCED:
	file = fi->body.iseq.iseq->location.filename;
	line_no = fi->body.iseq.line_no.line_no;
	name = fi->body.iseq.iseq->location.name;
	break;
      case FRAME_INFO_TYPE_CFUNC:
	if (fi->body.cfunc.prev_fi) {
	    file = fi->body.cfunc.prev_fi->body.iseq.iseq->location.filename;
	    line_no = frame_info_line_no(fi->body.cfunc.prev_fi);
	}
	else {
	    rb_thread_t *th = GET_THREAD();
	    file = th->vm->progname ? th->vm->progname : ruby_engine_name;
	    line_no = INT2FIX(0);
	}
	name = rb_id2str(fi->body.cfunc.mid);
	break;
      case FRAME_INFO_TYPE_IFUNC:
      default:
	rb_bug("frame_info_to_str: unreachable");
    }

    return frame_info_format(file, line_no, name);
}

static VALUE
frame_info_to_str_m(VALUE self)
{
    return frame_info_to_str(frame_info_ptr(self));
}

typedef struct rb_backtrace_struct {
    rb_frame_info_t *backtrace;
    rb_frame_info_t *backtrace_base;
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
	    frame_info_mark_entry(&bt->backtrace[i]);
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
    return sizeof(rb_backtrace_t) + sizeof(rb_frame_info_t) * bt->backtrace_size;
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
	  RUBY_VM_NEXT_CONTROL_FRAME(
	      RUBY_VM_NEXT_CONTROL_FRAME(start_cfp))); /* skip top frames */

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

	    if (mid != ID_ALLOCATOR) {
		iter_cfunc(arg, mid);
	    }
	}
    }
}

struct bt_iter_arg {
    rb_backtrace_t *bt;
    VALUE btobj;
    rb_frame_info_t *prev_fi;
};

static void
bt_init(void *ptr, size_t size)
{
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    arg->btobj = backtrace_alloc(rb_cBacktrace);
    GetCoreDataFromValue(arg->btobj, rb_backtrace_t, arg->bt);
    arg->bt->backtrace_base = arg->bt->backtrace = ruby_xmalloc(sizeof(rb_frame_info_t) * size);
    arg->bt->backtrace_size = 0;
}

static void
bt_iter_iseq(void *ptr, const rb_iseq_t *iseq, const VALUE *pc)
{
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    rb_frame_info_t *fi = &arg->bt->backtrace[arg->bt->backtrace_size++];
    fi->type = FRAME_INFO_TYPE_ISEQ;
    fi->body.iseq.iseq = iseq;
    fi->body.iseq.line_no.pc = pc;
    arg->prev_fi = fi;
}

static void
bt_iter_cfunc(void *ptr, ID mid)
{
    struct bt_iter_arg *arg = (struct bt_iter_arg *)ptr;
    rb_frame_info_t *fi = &arg->bt->backtrace[arg->bt->backtrace_size++];
    fi->type = FRAME_INFO_TYPE_CFUNC;
    fi->body.cfunc.mid = mid;
    fi->body.cfunc.prev_fi = arg->prev_fi;
}

static VALUE
backtrace_object(rb_thread_t *th)
{
    struct bt_iter_arg arg;
    arg.prev_fi = 0;

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
backtreace_collect(rb_backtrace_t *bt, int lev, int n, VALUE (*func)(rb_frame_info_t *, void *arg), void *arg)
{
    VALUE btary;
    int i;

    if (UNLIKELY(lev < 0 || n < 0)) {
	rb_bug("backtreace_collect: unreachable");
    }

    btary = rb_ary_new();

    for (i=0; i+lev<bt->backtrace_size && i<n; i++) {
	rb_frame_info_t *fi = &bt->backtrace[bt->backtrace_size - 1 - (lev+i)];
	rb_ary_push(btary, func(fi, arg));
    }

    return btary;
}

static VALUE
frame_info_to_str_dmyarg(rb_frame_info_t *fi, void *dmy)
{
    return frame_info_to_str(fi);
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
	bt->strary = backtreace_collect(bt, 0, bt->backtrace_size, frame_info_to_str_dmyarg, 0);
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

    return backtreace_collect(bt, lev, n, frame_info_to_str_dmyarg, 0);
}

static VALUE
frame_info_create(rb_frame_info_t *srcfi, void *btobj)
{
    VALUE obj;
    struct valued_frame_info *vfi;
    obj = TypedData_Make_Struct(rb_cFrameInfo, struct valued_frame_info, &frame_info_data_type, vfi);

    vfi->fi = srcfi;
    vfi->btobj = (VALUE)btobj;

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

    return backtreace_collect(bt, lev, n, frame_info_create, (void *)self);
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

/* old style backtrace directly */

struct oldbt_arg {
    VALUE filename;
    int line_no;
    void (*func)(void *data, VALUE file, int line_no, VALUE name);
    void *data; /* result */
};

static void
oldbt_init(void *ptr, size_t dmy)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    rb_thread_t *th = GET_THREAD();

    arg->filename = th->vm->progname ? th->vm->progname : ruby_engine_name;;
    arg->line_no = 0;
}

static void
oldbt_iter_iseq(void *ptr, const rb_iseq_t *iseq, const VALUE *pc)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename = iseq->location.filename;
    VALUE name = iseq->location.name;
    int line_no = arg->line_no = calc_line_no(iseq, pc);

    (arg->func)(arg->data, file, line_no, name);
}

static void
oldbt_iter_cfunc(void *ptr, ID mid)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename;
    VALUE name = rb_id2str(mid);
    int line_no = arg->line_no;

    (arg->func)(arg->data, file, line_no, name);
}

static void
oldbt_print(void *data, VALUE file, int line_no, VALUE name)
{
    FILE *fp = (FILE *)data;

    if (NIL_P(name)) {
	fprintf(fp, "\tfrom %s:%d:in unknown method\n",
		RSTRING_PTR(file), line_no);
    }
    else {
	fprintf(fp, "\tfrom %s:%d:in `%s'\n",
		RSTRING_PTR(file), line_no, RSTRING_PTR(name));
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

VALUE
rb_thread_backtrace(VALUE thval)
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

    return vm_backtrace_str_ary(th, 0, 0);
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
    VALUE level, vn;
    int lev, n;

    rb_scan_args(argc, argv, "02", &level, &vn);

    lev = NIL_P(level) ? 1 : NUM2INT(level);

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

    return vm_backtrace_str_ary(GET_THREAD(), lev+1, n);
}

static VALUE
rb_f_caller_frame_info(int argc, VALUE *argv)
{
    VALUE level, vn;
    int lev, n;

    rb_scan_args(argc, argv, "02", &level, &vn);

    lev = NIL_P(level) ? 1 : NUM2INT(level);

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

    return vm_backtrace_frame_ary(GET_THREAD(), lev+1, n);
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

    /* ::RubyVM::FrameInfo */
    rb_cFrameInfo = rb_define_class_under(rb_cRubyVM, "FrameInfo", rb_cObject);
    rb_undef_alloc_func(rb_cFrameInfo);
    rb_undef_method(CLASS_OF(rb_cFrameInfo), "new");
    rb_define_method(rb_cFrameInfo, "line_no", frame_info_line_no_m, 0);
    rb_define_method(rb_cFrameInfo, "name", frame_info_name_m, 0);
    rb_define_method(rb_cFrameInfo, "basename", frame_info_basename_m, 0);
    rb_define_method(rb_cFrameInfo, "filename", frame_info_filename_m, 0);
    rb_define_method(rb_cFrameInfo, "filepath", frame_info_filepath_m, 0);
    rb_define_method(rb_cFrameInfo, "iseq", frame_info_iseq_m, 0);
    rb_define_method(rb_cFrameInfo, "to_s", frame_info_to_str_m, 0);
    rb_define_singleton_method(rb_cFrameInfo, "caller", rb_f_caller_frame_info, -1);

    rb_define_global_function("caller", rb_f_caller, -1);
}
