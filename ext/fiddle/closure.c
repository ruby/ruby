#include <fiddle.h>

VALUE cFiddleClosure;

typedef struct {
    void * code;
    ffi_closure *pcl;
    ffi_cif * cif;
    int argc;
    ffi_type **argv;
} fiddle_closure;

static void
dealloc(void * ptr)
{
    fiddle_closure * cls = (fiddle_closure *)ptr;
    /*
#ifndef MACOSX
    ffi_closure_free(cls->pcl);
#else
    */
    munmap(cls->pcl, sizeof(cls->pcl));
    /*
#endif
    */
    xfree(cls->cif);
    if (cls->argv) xfree(cls->argv);
    xfree(cls);
}

static size_t
closure_memsize(const void * ptr)
{
    fiddle_closure * cls = (fiddle_closure *)ptr;
    size_t size = 0;

    if (ptr) {
	size += sizeof(*cls);
#if !defined(FFI_NO_RAW_API) || !FFI_NO_RAW_API
	size += ffi_raw_size(cls->cif);
#endif
	size += sizeof(*cls->argv);
	size += sizeof(ffi_closure);
    }
    return size;
}

const rb_data_type_t closure_data_type = {
    "fiddle/closure",
    0, dealloc, closure_memsize,
};

void
callback(ffi_cif *cif, void *resp, void **args, void *ctx)
{
    VALUE self      = (VALUE)ctx;
    VALUE rbargs    = rb_iv_get(self, "@args");
    VALUE ctype     = rb_iv_get(self, "@ctype");
    int argc        = RARRAY_LENINT(rbargs);
    VALUE *params   = xcalloc(argc, sizeof(VALUE *));
    VALUE ret;
    VALUE cPointer;
    int i, type;

    cPointer = rb_const_get(mFiddle, rb_intern("Pointer"));

    for (i = 0; i < argc; i++) {
        type = NUM2INT(RARRAY_PTR(rbargs)[i]);
        switch (type) {
	  case TYPE_VOID:
	    argc = 0;
	    break;
	  case TYPE_INT:
	    params[i] = INT2NUM(*(int *)args[i]);
	    break;
	  case TYPE_VOIDP:
            params[i] = rb_funcall(cPointer, rb_intern("[]"), 1,
              PTR2NUM(*(void **)args[i]));
	    break;
	  case TYPE_LONG:
	    params[i] = LONG2NUM(*(long *)args[i]);
	    break;
	  case TYPE_CHAR:
	    params[i] = INT2NUM(*(char *)args[i]);
	    break;
	  case TYPE_DOUBLE:
	    params[i] = rb_float_new(*(double *)args[i]);
	    break;
	  case TYPE_FLOAT:
	    params[i] = rb_float_new(*(float *)args[i]);
	    break;
#if HAVE_LONG_LONG
	  case TYPE_LONG_LONG:
	    params[i] = rb_ull2inum(*(unsigned LONG_LONG *)args[i]);
	    break;
#endif
	  default:
	    rb_raise(rb_eRuntimeError, "closure args: %d", type);
        }
    }

    ret = rb_funcall2(self, rb_intern("call"), argc, params);

    type = NUM2INT(ctype);
    switch (type) {
      case TYPE_VOID:
	break;
      case TYPE_LONG:
	*(long *)resp = NUM2LONG(ret);
	break;
      case TYPE_CHAR:
	*(char *)resp = NUM2INT(ret);
	break;
      case TYPE_VOIDP:
	*(void **)resp = NUM2PTR(ret);
	break;
      case TYPE_INT:
	*(int *)resp = NUM2INT(ret);
	break;
      case TYPE_DOUBLE:
	*(double *)resp = NUM2DBL(ret);
	break;
      case TYPE_FLOAT:
	*(float *)resp = (float)NUM2DBL(ret);
	break;
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	*(unsigned LONG_LONG *)resp = rb_big2ull(ret);
	break;
#endif
      default:
	rb_raise(rb_eRuntimeError, "closure retval: %d", type);
    }
    xfree(params);
}

static VALUE
allocate(VALUE klass)
{
    fiddle_closure * closure;

    VALUE i = TypedData_Make_Struct(klass, fiddle_closure,
	    &closure_data_type, closure);

#ifndef MACOSX
    closure->pcl = ffi_closure_alloc(sizeof(ffi_closure), &closure->code);
#else
    closure->pcl = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE,
        MAP_ANON | MAP_PRIVATE, -1, 0);
#endif
    closure->cif = xmalloc(sizeof(ffi_cif));

    return i;
}

static VALUE
initialize(int rbargc, VALUE argv[], VALUE self)
{
    VALUE ret;
    VALUE args;
    VALUE abi;
    fiddle_closure * cl;
    ffi_cif * cif;
    ffi_closure *pcl;
    ffi_status result;
    int i, argc;

    if (2 == rb_scan_args(rbargc, argv, "21", &ret, &args, &abi))
	abi = INT2NUM(FFI_DEFAULT_ABI);

    Check_Type(args, T_ARRAY);

    argc = RARRAY_LENINT(args);

    TypedData_Get_Struct(self, fiddle_closure, &closure_data_type, cl);

    cl->argv = (ffi_type **)xcalloc(argc + 1, sizeof(ffi_type *));

    for (i = 0; i < argc; i++) {
        int type = NUM2INT(RARRAY_PTR(args)[i]);
        cl->argv[i] = INT2FFI_TYPE(type);
    }
    cl->argv[argc] = NULL;

    rb_iv_set(self, "@ctype", ret);
    rb_iv_set(self, "@args", args);

    cif = cl->cif;
    pcl = cl->pcl;

    result = ffi_prep_cif(cif, NUM2INT(abi), argc,
                INT2FFI_TYPE(NUM2INT(ret)),
		cl->argv);

    if (FFI_OK != result)
	rb_raise(rb_eRuntimeError, "error prepping CIF %d", result);

#ifndef MACOSX
    result = ffi_prep_closure_loc(pcl, cif, callback,
		(void *)self, cl->code);
#else
    result = ffi_prep_closure(pcl, cif, callback, (void *)self);
    cl->code = (void *)pcl;
    mprotect(pcl, sizeof(pcl), PROT_READ | PROT_EXEC);
#endif

    if (FFI_OK != result)
	rb_raise(rb_eRuntimeError, "error prepping closure %d", result);

    return self;
}

static VALUE
to_i(VALUE self)
{
    fiddle_closure * cl;
    void *code;

    TypedData_Get_Struct(self, fiddle_closure, &closure_data_type, cl);

    code = cl->code;

    return PTR2NUM(code);
}

void
Init_fiddle_closure()
{
    cFiddleClosure = rb_define_class_under(mFiddle, "Closure", rb_cObject);

    rb_define_alloc_func(cFiddleClosure, allocate);

    rb_define_method(cFiddleClosure, "initialize", initialize, -1);
    rb_define_method(cFiddleClosure, "to_i", to_i, 0);
}
/* vim: set noet sw=4 sts=4 */
