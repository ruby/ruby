#include <stdbool.h>

#include <fiddle.h>

VALUE
rb_fiddle_type_ensure(VALUE type)
{
    VALUE original_type = type;

    if (!RB_SYMBOL_P(type)) {
        VALUE type_string = rb_check_string_type(type);
        if (!NIL_P(type_string)) {
            type = rb_to_symbol(type_string);
        }
    }

    if (RB_SYMBOL_P(type)) {
        ID type_id = rb_sym2id(type);
        ID void_id;
        ID voidp_id;
        ID char_id;
        ID short_id;
        ID int_id;
        ID long_id;
#ifdef TYPE_LONG_LONG
        ID long_long_id;
#endif
#ifdef TYPE_INT8_T
        ID int8_t_id;
#endif
#ifdef TYPE_INT16_T
        ID int16_t_id;
#endif
#ifdef TYPE_INT32_T
        ID int32_t_id;
#endif
#ifdef TYPE_INT64_T
        ID int64_t_id;
#endif
        ID float_id;
        ID double_id;
        ID variadic_id;
        ID const_string_id;
        ID size_t_id;
        ID ssize_t_id;
        ID ptrdiff_t_id;
        ID intptr_t_id;
        ID uintptr_t_id;
        ID bool_id;
        RUBY_CONST_ID(void_id, "void");
        RUBY_CONST_ID(voidp_id, "voidp");
        RUBY_CONST_ID(char_id, "char");
        RUBY_CONST_ID(short_id, "short");
        RUBY_CONST_ID(int_id, "int");
        RUBY_CONST_ID(long_id, "long");
#ifdef TYPE_LONG_LONG
        RUBY_CONST_ID(long_long_id, "long_long");
#endif
#ifdef TYPE_INT8_T
        RUBY_CONST_ID(int8_t_id, "int8_t");
#endif
#ifdef TYPE_INT16_T
        RUBY_CONST_ID(int16_t_id, "int16_t");
#endif
#ifdef TYPE_INT32_T
        RUBY_CONST_ID(int32_t_id, "int32_t");
#endif
#ifdef TYPE_INT64_T
        RUBY_CONST_ID(int64_t_id, "int64_t");
#endif
        RUBY_CONST_ID(float_id, "float");
        RUBY_CONST_ID(double_id, "double");
        RUBY_CONST_ID(variadic_id, "variadic");
        RUBY_CONST_ID(const_string_id, "const_string");
        RUBY_CONST_ID(size_t_id, "size_t");
        RUBY_CONST_ID(ssize_t_id, "ssize_t");
        RUBY_CONST_ID(ptrdiff_t_id, "ptrdiff_t");
        RUBY_CONST_ID(intptr_t_id, "intptr_t");
        RUBY_CONST_ID(uintptr_t_id, "uintptr_t");
        RUBY_CONST_ID(bool_id, "bool");
        if (type_id == void_id) {
            return INT2NUM(TYPE_VOID);
        }
        else if (type_id == voidp_id) {
            return INT2NUM(TYPE_VOIDP);
        }
        else if (type_id == char_id) {
            return INT2NUM(TYPE_CHAR);
        }
        else if (type_id == short_id) {
            return INT2NUM(TYPE_SHORT);
        }
        else if (type_id == int_id) {
            return INT2NUM(TYPE_INT);
        }
        else if (type_id == long_id) {
            return INT2NUM(TYPE_LONG);
        }
#ifdef TYPE_LONG_LONG
        else if (type_id == long_long_id) {
            return INT2NUM(TYPE_LONG_LONG);
        }
#endif
#ifdef TYPE_INT8_T
        else if (type_id == int8_t_id) {
            return INT2NUM(TYPE_INT8_T);
        }
#endif
#ifdef TYPE_INT16_T
        else if (type_id == int16_t_id) {
            return INT2NUM(TYPE_INT16_T);
        }
#endif
#ifdef TYPE_INT32_T
        else if (type_id == int32_t_id) {
            return INT2NUM(TYPE_INT32_T);
        }
#endif
#ifdef TYPE_INT64_T
        else if (type_id == int64_t_id) {
            return INT2NUM(TYPE_INT64_T);
        }
#endif
        else if (type_id == float_id) {
            return INT2NUM(TYPE_FLOAT);
        }
        else if (type_id == double_id) {
            return INT2NUM(TYPE_DOUBLE);
        }
        else if (type_id == variadic_id) {
            return INT2NUM(TYPE_VARIADIC);
        }
        else if (type_id == const_string_id) {
            return INT2NUM(TYPE_CONST_STRING);
        }
        else if (type_id == size_t_id) {
            return INT2NUM(TYPE_SIZE_T);
        }
        else if (type_id == ssize_t_id) {
            return INT2NUM(TYPE_SSIZE_T);
        }
        else if (type_id == ptrdiff_t_id) {
            return INT2NUM(TYPE_PTRDIFF_T);
        }
        else if (type_id == intptr_t_id) {
            return INT2NUM(TYPE_INTPTR_T);
        }
        else if (type_id == uintptr_t_id) {
            return INT2NUM(TYPE_UINTPTR_T);
        }
        else if (type_id == bool_id) {
            return INT2NUM(TYPE_BOOL);
        }
        else {
            type = original_type;
        }
    }

    return rb_to_int(type);
}

ffi_type *
rb_fiddle_int_to_ffi_type(int type)
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
	return rb_ffi_type_of(long_long);
#endif
      case TYPE_FLOAT:
	return &ffi_type_float;
      case TYPE_DOUBLE:
	return &ffi_type_double;
      case TYPE_CONST_STRING:
	return &ffi_type_pointer;
      case TYPE_BOOL:
	signed_p = 0;
        if (sizeof(bool) == sizeof(char)) {
            return rb_ffi_type_of(char);
        } else if (sizeof(bool) == sizeof(short)) {
            return rb_ffi_type_of(short);
        } else if (sizeof(bool) == sizeof(int)) {
            return rb_ffi_type_of(int);
        } else if (sizeof(bool) == sizeof(long)) {
            return rb_ffi_type_of(long);
        } else {
            rb_raise(rb_eNotImpError, "bool isn't supported: %u",
                     (unsigned int)sizeof(bool));
        }
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", type);
    }
    return &ffi_type_pointer;
}

ffi_type *
int_to_ffi_type(int type)
{
    return rb_fiddle_int_to_ffi_type(type);
}

void
rb_fiddle_value_to_generic(int type, VALUE *src, fiddle_generic *dst)
{
    switch (type) {
      case TYPE_VOID:
	break;
      case TYPE_VOIDP:
	dst->pointer = NUM2PTR(rb_Integer(*src));
	break;
      case TYPE_CHAR:
        if (RB_TYPE_P(*src, RUBY_T_STRING) && RSTRING_LEN(*src) == 1) {
            dst->schar = RSTRING_PTR(*src)[0];
        } else {
            dst->schar = (signed char)NUM2INT(*src);
        }
	break;
      case TYPE_UCHAR:
	dst->uchar = (unsigned char)NUM2UINT(*src);
	break;
      case TYPE_SHORT:
	dst->sshort = (unsigned short)NUM2INT(*src);
	break;
      case TYPE_USHORT:
	dst->sshort = (signed short)NUM2UINT(*src);
	break;
      case TYPE_INT:
	dst->sint = NUM2INT(*src);
	break;
      case TYPE_UINT:
	dst->uint = NUM2UINT(*src);
	break;
      case TYPE_LONG:
	dst->slong = NUM2LONG(*src);
	break;
      case TYPE_ULONG:
	dst->ulong = NUM2ULONG(*src);
	break;
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	dst->slong_long = NUM2LL(*src);
	break;
      case TYPE_ULONG_LONG:
	dst->ulong_long = NUM2ULL(*src);
	break;
#endif
      case TYPE_FLOAT:
	dst->ffloat = (float)NUM2DBL(*src);
	break;
      case TYPE_DOUBLE:
	dst->ddouble = NUM2DBL(*src);
	break;
      case TYPE_CONST_STRING:
        if (NIL_P(*src)) {
            dst->pointer = NULL;
        }
        else {
            dst->pointer = rb_string_value_cstr(src);
        }
	break;
      case TYPE_BOOL:
        if (sizeof(bool) == sizeof(char)) {
            dst->uchar = RB_TEST(*src);
        } else if (sizeof(bool) == sizeof(short)) {
            dst->ushort = RB_TEST(*src);
        } else if (sizeof(bool) == sizeof(int)) {
            dst->uint = RB_TEST(*src);
        } else if (sizeof(bool) == sizeof(long)) {
            dst->ulong = RB_TEST(*src);
        } else {
            rb_raise(rb_eNotImpError, "bool isn't supported: %u",
                     (unsigned int)sizeof(bool));
        }
        break;
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", type);
        break;
    }
}

void
value_to_generic(int type, VALUE src, fiddle_generic *dst)
{
    /* src isn't safe from GC when type is TYPE_CONST_STRING and src
     * isn't String. */
    rb_fiddle_value_to_generic(type, &src, dst);
}

VALUE
rb_fiddle_generic_to_value(VALUE rettype, fiddle_generic retval)
{
    int type = NUM2INT(rettype);
    VALUE cPointer;

    cPointer = rb_const_get(mFiddle, rb_intern("Pointer"));

    switch (type) {
      case TYPE_VOID:
	return Qnil;
      case TYPE_VOIDP:
        return rb_funcall(cPointer, rb_intern("[]"), 1,
          PTR2NUM((void *)retval.pointer));
      case TYPE_CHAR:
	return INT2NUM((signed char)retval.fffi_sarg);
      case TYPE_UCHAR:
	return INT2NUM((unsigned char)retval.fffi_arg);
      case TYPE_SHORT:
	return INT2NUM((signed short)retval.fffi_sarg);
      case TYPE_USHORT:
	return INT2NUM((unsigned short)retval.fffi_arg);
      case TYPE_INT:
	return INT2NUM((signed int)retval.fffi_sarg);
      case TYPE_UINT:
	return UINT2NUM((unsigned int)retval.fffi_arg);
      case TYPE_LONG:
	return LONG2NUM(retval.slong);
      case TYPE_ULONG:
	return ULONG2NUM(retval.ulong);
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	return LL2NUM(retval.slong_long);
      case TYPE_ULONG_LONG:
	return ULL2NUM(retval.ulong_long);
#endif
      case TYPE_FLOAT:
	return rb_float_new(retval.ffloat);
      case TYPE_DOUBLE:
	return rb_float_new(retval.ddouble);
      case TYPE_CONST_STRING:
        if (retval.pointer) {
            return rb_str_new_cstr(retval.pointer);
        }
        else {
            return Qnil;
        }
      case TYPE_BOOL:
        if (sizeof(bool) == sizeof(char)) {
            return CBOOL2RBBOOL((unsigned char)retval.fffi_arg);
        } else if (sizeof(bool) == sizeof(short)) {
            return CBOOL2RBBOOL((unsigned short)retval.fffi_arg);
        } else if (sizeof(bool) == sizeof(int)) {
            return CBOOL2RBBOOL((unsigned int)retval.fffi_arg);
        } else if (sizeof(bool) == sizeof(long)) {
            return CBOOL2RBBOOL(retval.ulong);
        } else {
            rb_raise(rb_eNotImpError, "bool isn't supported: %u",
                     (unsigned int)sizeof(bool));
        }
      default:
	rb_raise(rb_eRuntimeError, "unknown type %d", type);
    }

    UNREACHABLE;
}

VALUE
generic_to_value(VALUE rettype, fiddle_generic retval)
{
    return rb_fiddle_generic_to_value(rettype, retval);
}
