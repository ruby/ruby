/* -*- C -*-
 * $Id$
 */

#include <ruby.h>
#include <errno.h>
#include "dl.h"
#include <dl_conversions.h>

VALUE rb_cDLMethod;

typedef union
{
    unsigned char uchar;   /* ffi_type_uchar */
    signed char   schar;   /* ffi_type_schar */
    unsigned short ushort; /* ffi_type_sshort */
    signed short sshort;   /* ffi_type_ushort */
    unsigned int uint;     /* ffi_type_uint */
    signed int sint;       /* ffi_type_sint */
    unsigned long ulong;   /* ffi_type_ulong */
    signed long slong;     /* ffi_type_slong */
    float ffloat;          /* ffi_type_float */
    double ddouble;        /* ffi_type_double */
#if HAVE_LONG_LONG
    unsigned LONG_LONG long_long; /* ffi_type_uint64 */
#endif
    void * pointer;        /* ffi_type_pointer */
} dl_generic;

static void
dlfunction_free(void *p)
{
    ffi_cif *ptr = p;
    if (ptr->arg_types) xfree(ptr->arg_types);
    xfree(ptr);
}

static size_t
dlfunction_memsize(const void *p)
{
    /* const */ffi_cif *ptr = (ffi_cif *)p;
    size_t size = 0;

    if (ptr) {
	size += sizeof(*ptr);
	size += ffi_raw_size(ptr);
    }
    return size;
}

const rb_data_type_t dlfunction_data_type = {
    "dl/method",
    0, dlfunction_free, dlfunction_memsize,
};

static VALUE
rb_dlfunc_allocate(VALUE klass)
{
    ffi_cif * cif;

    return TypedData_Make_Struct(klass, ffi_cif, &dlfunction_data_type, cif);
}

static VALUE
rb_dlfunction_initialize(int argc, VALUE argv[], VALUE self)
{
    ffi_cif * cif;
    ffi_type **arg_types;
    ffi_status result;
    VALUE ptr, args, ret_type, abi;
    int i;

    rb_scan_args(argc, argv, "31", &ptr, &args, &ret_type, &abi);
    if(NIL_P(abi)) abi = INT2NUM(FFI_DEFAULT_ABI);

    rb_iv_set(self, "@ptr", ptr);
    rb_iv_set(self, "@args", args);
    rb_iv_set(self, "@return_type", ret_type);
    rb_iv_set(self, "@abi", abi);

    TypedData_Get_Struct(self, ffi_cif, &dlfunction_data_type, cif);

    arg_types = xcalloc(RARRAY_LEN(args) + 1, sizeof(ffi_type *));

    for (i = 0; i < RARRAY_LEN(args); i++) {
	int type = NUM2INT(RARRAY_PTR(args)[i]);
	arg_types[i] = DL2FFI_TYPE(type);
    }
    arg_types[RARRAY_LEN(args)] = NULL;

    result = ffi_prep_cif (
	    cif,
	    NUM2INT(abi),
	    RARRAY_LENINT(args),
	    DL2FFI_TYPE(NUM2INT(ret_type)),
	    arg_types);

    if (result)
	rb_raise(rb_eRuntimeError, "error creating CIF %d", result);

    return self;
}

static void
dl2generic(int dl_type, VALUE src, dl_generic * dst)
{
    int signed_p = 1;

    if (dl_type < 0) {
	dl_type = -1 * dl_type;
	signed_p = 0;
    }

    switch (dl_type) {
      case DLTYPE_VOID:
	break;
      case DLTYPE_VOIDP:
	dst->pointer = NUM2PTR(rb_Integer(src));
	break;
      case DLTYPE_CHAR:
      case DLTYPE_SHORT:
      case DLTYPE_INT:
	dst->sint = NUM2INT(src);
	break;
      case DLTYPE_LONG:
	if (signed_p)
	    dst->slong = NUM2LONG(src);
	else
	    dst->ulong = NUM2LONG(src);
	break;
#if HAVE_LONG_LONG
      case DLTYPE_LONG_LONG:
	dst->long_long = rb_big2ull(src);
	break;
#endif
      case DLTYPE_FLOAT:
	dst->ffloat = (float)NUM2DBL(src);
	break;
      case DLTYPE_DOUBLE:
	dst->ddouble = NUM2DBL(src);
	break;
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", dl_type);
    }
}

static VALUE
unwrap_ffi(VALUE rettype, dl_generic retval)
{
    int signed_p = 1;
    int dl_type = NUM2INT(rettype);

    if (dl_type < 0) {
	dl_type = -1 * dl_type;
	signed_p = 0;
    }

    switch (dl_type) {
      case DLTYPE_VOID:
	return Qnil;
      case DLTYPE_VOIDP:
	return rb_dlptr_new((void *)retval.pointer, 0, NULL);
      case DLTYPE_CHAR:
      case DLTYPE_SHORT:
      case DLTYPE_INT:
	return INT2NUM(retval.sint);
      case DLTYPE_LONG:
	if (signed_p) return LONG2NUM(retval.slong);
	return ULONG2NUM(retval.ulong);
#if HAVE_LONG_LONG
      case DLTYPE_LONG_LONG:
	return rb_ll2inum(retval.long_long);
	break;
#endif
      case DLTYPE_FLOAT:
	return rb_float_new(retval.ffloat);
      case DLTYPE_DOUBLE:
	return rb_float_new(retval.ddouble);
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", dl_type);
    }
}

static VALUE
rb_dlfunction_call(int argc, VALUE argv[], VALUE self)
{
    ffi_cif * cif;
    dl_generic retval;
    dl_generic *generic_args;
    void **values;
    void * fun_ptr;
    VALUE cfunc, types;
    int i;

    TypedData_Get_Struct(self, ffi_cif, &dlfunction_data_type, cif);

    values = xcalloc((size_t)argc + 1, (size_t)sizeof(void *));
    generic_args = xcalloc((size_t)argc, (size_t)sizeof(dl_generic));

    cfunc = rb_iv_get(self, "@ptr");
    types = rb_iv_get(self, "@args");

    for (i = 0; i < argc; i++) {
	VALUE dl_type = RARRAY_PTR(types)[i];
	VALUE src = argv[i];

	if(NUM2INT(dl_type) == DLTYPE_VOIDP) {
	    if(NIL_P(src)) {
		src = INT2NUM(0);
	    } else if(rb_cDLCPtr != CLASS_OF(src)) {
	        src = rb_funcall(rb_cDLCPtr, rb_intern("[]"), 1, src);
	    }
	    src = rb_Integer(src);
	}

	dl2generic(NUM2INT(dl_type), src, &generic_args[i]);
	values[i] = (void *)&generic_args[i];
    }
    values[argc] = NULL;

    ffi_call(cif, NUM2PTR(rb_Integer(cfunc)), &retval, values);

    rb_dl_set_last_error(self, INT2NUM(errno));
#if defined(HAVE_WINDOWS_H)
    rb_dl_set_win32_last_error(self, INT2NUM(GetLastError()));
#endif

    xfree(values);
    xfree(generic_args);

    return unwrap_ffi(rb_iv_get(self, "@return_type"), retval);
}

void
Init_dlfunction(void)
{
    rb_cDLMethod = rb_define_class_under(rb_mDL, "Method", rb_cObject);

    rb_define_const(rb_cDLMethod, "DEFAULT", INT2NUM(FFI_DEFAULT_ABI));

#ifdef FFI_STDCALL
    rb_define_const(rb_cDLMethod, "STDCALL", INT2NUM(FFI_STDCALL));
#endif

    rb_define_alloc_func(rb_cDLMethod, rb_dlfunc_allocate);

    rb_define_method(rb_cDLMethod, "call", rb_dlfunction_call, -1);

    rb_define_method(rb_cDLMethod, "initialize", rb_dlfunction_initialize, -1);
}
/* vim: set noet sw=4 sts=4 */
