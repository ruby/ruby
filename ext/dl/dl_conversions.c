#include <dl_conversions.h>

ffi_type *
rb_dl_type_to_ffi_type(int dl_type)
{
    int signed_p = 1;

    if (dl_type < 0) {
	dl_type = -1 * dl_type;
	signed_p = 0;
    }

#define rb_ffi_type_of(t) (signed_p ? &ffi_type_s##t : &ffi_type_u##t)

    switch (dl_type) {
      case DLTYPE_VOID:
	return &ffi_type_void;
      case DLTYPE_VOIDP:
	return &ffi_type_pointer;
      case DLTYPE_CHAR:
	return rb_ffi_type_of(char);
      case DLTYPE_SHORT:
	return rb_ffi_type_of(short);
      case DLTYPE_INT:
	return rb_ffi_type_of(int);
      case DLTYPE_LONG:
	return rb_ffi_type_of(long);
#if HAVE_LONG_LONG
      case DLTYPE_LONG_LONG:
	return rb_ffi_type_of(int64);
#endif
      case DLTYPE_FLOAT:
	return &ffi_type_float;
      case DLTYPE_DOUBLE:
	return &ffi_type_double;
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", dl_type);
    }
    return &ffi_type_pointer;
}
