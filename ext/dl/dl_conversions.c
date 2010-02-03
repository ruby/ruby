#include <dl_conversions.h>

ffi_type * rb_dl_type_to_ffi_type(int dl_type)
{
    int signed_p = 1;

    if(dl_type < 0) {
	dl_type = -1 * dl_type;
	signed_p = 0;
    }

    switch(dl_type) {
	case DLTYPE_VOID:
	    return &ffi_type_void;
	case DLTYPE_VOIDP:
	    return &ffi_type_pointer;
	case DLTYPE_CHAR:
	    return signed_p ? &ffi_type_schar : &ffi_type_uchar;
	case DLTYPE_SHORT:
	    return signed_p ? &ffi_type_sshort : &ffi_type_ushort;
	case DLTYPE_INT:
	    return signed_p ? &ffi_type_sint : &ffi_type_uint;
	case DLTYPE_LONG:
	    return signed_p ? &ffi_type_slong : &ffi_type_ulong;
#if HAVE_LONG_LONG
	case DLTYPE_LONG_LONG:
            return &ffi_type_uint64;
	    break;
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
