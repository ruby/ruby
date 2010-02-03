#ifndef DL_CONVERSIONS
#define DL_CONVERSIONS

#include <dl.h>

#define DL2FFI_TYPE(a) rb_dl_type_to_ffi_type(a)

ffi_type * rb_dl_type_to_ffi_type(int dl_type);

#endif
