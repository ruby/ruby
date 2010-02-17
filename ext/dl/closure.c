/* -*- C -*-
 * $Id$
 */

#include <ruby.h>
#include "dl.h"
#include <sys/mman.h>
#include <dl_conversions.h>

VALUE rb_cDLClosure;

typedef struct {
    void * code;
    ffi_closure *pcl;
    ffi_cif * cif;
    int argc;
    ffi_type **argv;
} dl_closure;

static void
dlclosure_free(void * ptr)
{
    dl_closure * cls = (dl_closure *)ptr;
#ifdef USE_NEW_CLOSURE_API
    ffi_closure_free(cls->pcl);
#else
    munmap(cls->pcl, sizeof(cls->pcl));
#endif
    xfree(cls->cif);
    if (cls->argv) xfree(cls->argv);
    xfree(cls);
}

static size_t
dlclosure_memsize(const void * ptr)
{
    dl_closure * cls = (dl_closure *)ptr;
    size_t size = 0;

    if (ptr) {
	size += sizeof(*cls);
	size += ffi_raw_size(cls->cif);
	size += sizeof(*cls->argv);
	size += sizeof(ffi_closure);
    }
    return size;
}

const rb_data_type_t dlclosure_data_type = {
    "dl/closure",
    0, dlclosure_free, dlclosure_memsize,
};

void
dlc_callback(ffi_cif *cif, void *resp, void **args, void *ctx)
{
    VALUE self      = (VALUE)ctx;
    VALUE rbargs    = rb_iv_get(self, "@args");
    VALUE ctype     = rb_iv_get(self, "@ctype");
    int argc        = RARRAY_LENINT(rbargs);
    VALUE *params   = xcalloc(argc, sizeof(VALUE *));
    VALUE ret;
    int i, dl_type;

    for (i = 0; i < argc; i++) {
        dl_type = NUM2INT(RARRAY_PTR(rbargs)[i]);
        switch (dl_type) {
	  case DLTYPE_VOID:
	    argc = 0;
	    break;
	  case DLTYPE_INT:
	    params[i] = INT2NUM(*(int *)args[i]);
	    break;
	  case DLTYPE_VOIDP:
	    params[i] = rb_dlptr_new(*(void **)args[i], 0, NULL);
	    break;
	  case DLTYPE_LONG:
	    params[i] = LONG2NUM(*(long *)args[i]);
	    break;
	  case DLTYPE_CHAR:
	    params[i] = INT2NUM(*(char *)args[i]);
	    break;
	  case DLTYPE_DOUBLE:
	    params[i] = rb_float_new(*(double *)args[i]);
	    break;
	  case DLTYPE_FLOAT:
	    params[i] = rb_float_new(*(float *)args[i]);
	    break;
#if HAVE_LONG_LONG
	  case DLTYPE_LONG_LONG:
	    params[i] = rb_ull2inum(*(unsigned LONG_LONG *)args[i]);
	    break;
#endif
	  default:
	    rb_raise(rb_eRuntimeError, "closure args: %d", dl_type);
        }
    }

    ret = rb_funcall2(self, rb_intern("call"), argc, params);

    dl_type = NUM2INT(ctype);
    switch (dl_type) {
      case DLTYPE_VOID:
	break;
      case DLTYPE_LONG:
	*(long *)resp = NUM2LONG(ret);
	break;
      case DLTYPE_CHAR:
	*(char *)resp = NUM2INT(ret);
	break;
      case DLTYPE_VOIDP:
	*(void **)resp = NUM2PTR(ret);
	break;
      case DLTYPE_INT:
	*(int *)resp = NUM2INT(ret);
	break;
      case DLTYPE_DOUBLE:
	*(double *)resp = NUM2DBL(ret);
	break;
      case DLTYPE_FLOAT:
	*(float *)resp = (float)NUM2DBL(ret);
	break;
#if HAVE_LONG_LONG
      case DLTYPE_LONG_LONG:
	*(unsigned LONG_LONG *)resp = rb_big2ull(ret);
	break;
#endif
      default:
	rb_raise(rb_eRuntimeError, "closure retval: %d", dl_type);
    }
    xfree(params);
}

static VALUE
rb_dlclosure_allocate(VALUE klass)
{
    dl_closure * closure;

    VALUE i = TypedData_Make_Struct(klass, dl_closure,
	    &dlclosure_data_type, closure);

#ifdef USE_NEW_CLOSURE_API
    closure->pcl = ffi_closure_alloc(sizeof(ffi_closure), &closure->code);
#else
    closure->pcl = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE,
        MAP_ANON | MAP_PRIVATE, -1, 0);
#endif
    closure->cif = xmalloc(sizeof(ffi_cif));

    return i;
}

static VALUE
rb_dlclosure_init(int rbargc, VALUE argv[], VALUE self)
{
    VALUE ret;
    VALUE args;
    VALUE abi;
    dl_closure * cl;
    ffi_cif * cif;
    ffi_closure *pcl;
    ffi_status result;
    int i, argc;

    if (2 == rb_scan_args(rbargc, argv, "21", &ret, &args, &abi))
	abi = INT2NUM(FFI_DEFAULT_ABI);

    argc = RARRAY_LENINT(args);

    TypedData_Get_Struct(self, dl_closure, &dlclosure_data_type, cl);

    cl->argv = (ffi_type **)xcalloc(argc + 1, sizeof(ffi_type *));

    for (i = 0; i < argc; i++) {
        int dltype = NUM2INT(RARRAY_PTR(args)[i]);
        cl->argv[i] = DL2FFI_TYPE(dltype);
    }
    cl->argv[argc] = NULL;

    rb_iv_set(self, "@ctype", ret);
    rb_iv_set(self, "@args", args);

    cif = cl->cif;
    pcl = cl->pcl;

    result = ffi_prep_cif(cif, NUM2INT(abi), argc,
                DL2FFI_TYPE(NUM2INT(ret)),
		cl->argv);

    if (FFI_OK != result)
	rb_raise(rb_eRuntimeError, "error prepping CIF %d", result);

#ifdef USE_NEW_CLOSURE_API
    result = ffi_prep_closure_loc(pcl, cif, dlc_callback,
		(void *)self, cl->code);
#else
    result = ffi_prep_closure(pcl, cif, dlc_callback, (void *)self);
    cl->code = (void *)pcl;
    mprotect(pcl, sizeof(pcl), PROT_READ | PROT_EXEC);
#endif

    if (FFI_OK != result)
	rb_raise(rb_eRuntimeError, "error prepping closure %d", result);

    return self;
}

static VALUE
rb_dlclosure_to_i(VALUE self)
{
    dl_closure * cl;
    void *code;

    TypedData_Get_Struct(self, dl_closure, &dlclosure_data_type, cl);

    code = cl->code;

    return PTR2NUM(code);
}

void
Init_dlclosure(void)
{
    rb_cDLClosure = rb_define_class_under(rb_mDL, "Closure", rb_cObject);
    rb_define_alloc_func(rb_cDLClosure, rb_dlclosure_allocate);

    rb_define_method(rb_cDLClosure, "initialize", rb_dlclosure_init, -1);
    rb_define_method(rb_cDLClosure, "to_i", rb_dlclosure_to_i, 0);
}
/* vim: set noet sw=4 sts=4 */
