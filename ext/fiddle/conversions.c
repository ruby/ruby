#include <fiddle.h>

ffi_type *
int_to_ffi_type(int type)
{
    int signed_p = 1;

    if (type < 0) {
	type = -1 * type;
	signed_p = 0;
    }

#define rb_ffi_type_of(t) (signed_p ? &ffi_type_s##t : &ffi_type_u##t)

    switch (type) {
      case TYPE_VOID:
	return &ffi_type_void;
      case TYPE_VOIDP:
	return &ffi_type_pointer;
      case TYPE_CHAR:
	return rb_ffi_type_of(char);
      case TYPE_SHORT:
	return rb_ffi_type_of(short);
      case TYPE_INT:
	return rb_ffi_type_of(int);
      case TYPE_LONG:
	return rb_ffi_type_of(long);
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	return rb_ffi_type_of(int64);
#endif
      case TYPE_FLOAT:
	return &ffi_type_float;
      case TYPE_DOUBLE:
	return &ffi_type_double;
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", type);
    }
    return &ffi_type_pointer;
}

void
value_to_generic(int type, VALUE src, fiddle_generic * dst)
{
    int signed_p = 1;

    if (type < 0) {
	type = -1 * type;
	signed_p = 0;
    }

    switch (type) {
      case TYPE_VOID:
	break;
      case TYPE_VOIDP:
	dst->pointer = NUM2PTR(rb_Integer(src));
	break;
      case TYPE_CHAR:
      case TYPE_SHORT:
      case TYPE_INT:
	dst->sint = NUM2INT(src);
	break;
      case TYPE_LONG:
	if (signed_p)
	    dst->slong = NUM2LONG(src);
	else
	    dst->ulong = NUM2LONG(src);
	break;
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	dst->long_long = rb_big2ull(src);
	break;
#endif
      case TYPE_FLOAT:
	dst->ffloat = (float)NUM2DBL(src);
	break;
      case TYPE_DOUBLE:
	dst->ddouble = NUM2DBL(src);
	break;
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", type);
    }
}

VALUE
generic_to_value(VALUE rettype, fiddle_generic retval)
{
    int signed_p = 1;
    int type = NUM2INT(rettype);
    VALUE cPointer;

    cPointer = rb_const_get(mFiddle, rb_intern("Pointer"));

    if (type < 0) {
	type = -1 * type;
	signed_p = 0;
    }

    switch (type) {
      case TYPE_VOID:
	return Qnil;
      case TYPE_VOIDP:
        return rb_funcall(cPointer, rb_intern("[]"), 1,
          PTR2NUM((void *)retval.pointer));
      case TYPE_CHAR:
      case TYPE_SHORT:
      case TYPE_INT:
	return INT2NUM(retval.sint);
      case TYPE_LONG:
	if (signed_p) return LONG2NUM(retval.slong);
	return ULONG2NUM(retval.ulong);
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	return rb_ll2inum(retval.long_long);
	break;
#endif
      case TYPE_FLOAT:
	return rb_float_new(retval.ffloat);
      case TYPE_DOUBLE:
	return rb_float_new(retval.ddouble);
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", type);
    }
}

/* vim: set noet sw=4 sts=4 */
