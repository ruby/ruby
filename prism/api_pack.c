#include "yarp/extension.h"

static VALUE rb_cYARP;
static VALUE rb_cYARPPack;
static VALUE rb_cYARPPackDirective;
static VALUE rb_cYARPPackFormat;

static VALUE v3_2_0_symbol;
static VALUE pack_symbol;
static VALUE unpack_symbol;

#if SIZEOF_UINT64_T == SIZEOF_LONG_LONG
# define UINT64T2NUM(x) ULL2NUM(x)
# define NUM2UINT64T(x) (uint64_t)NUM2ULL(x)
#elif SIZEOF_UINT64_T == SIZEOF_LONG
# define UINT64T2NUM(x) ULONG2NUM(x)
# define NUM2UINT64T(x) (uint64_t)NUM2ULONG(x)
#else
// error No uint64_t conversion
#endif

static VALUE
pack_type_to_symbol(yp_pack_type type) {
    switch (type) {
        case YP_PACK_SPACE:
            return ID2SYM(rb_intern("SPACE"));
        case YP_PACK_COMMENT:
            return ID2SYM(rb_intern("COMMENT"));
        case YP_PACK_INTEGER:
            return ID2SYM(rb_intern("INTEGER"));
        case YP_PACK_UTF8:
            return ID2SYM(rb_intern("UTF8"));
        case YP_PACK_BER:
            return ID2SYM(rb_intern("BER"));
        case YP_PACK_FLOAT:
            return ID2SYM(rb_intern("FLOAT"));
        case YP_PACK_STRING_SPACE_PADDED:
            return ID2SYM(rb_intern("STRING_SPACE_PADDED"));
        case YP_PACK_STRING_NULL_PADDED:
            return ID2SYM(rb_intern("STRING_NULL_PADDED"));
        case YP_PACK_STRING_NULL_TERMINATED:
            return ID2SYM(rb_intern("STRING_NULL_TERMINATED"));
        case YP_PACK_STRING_MSB:
            return ID2SYM(rb_intern("STRING_MSB"));
        case YP_PACK_STRING_LSB:
            return ID2SYM(rb_intern("STRING_LSB"));
        case YP_PACK_STRING_HEX_HIGH:
            return ID2SYM(rb_intern("STRING_HEX_HIGH"));
        case YP_PACK_STRING_HEX_LOW:
            return ID2SYM(rb_intern("STRING_HEX_LOW"));
        case YP_PACK_STRING_UU:
            return ID2SYM(rb_intern("STRING_UU"));
        case YP_PACK_STRING_MIME:
            return ID2SYM(rb_intern("STRING_MIME"));
        case YP_PACK_STRING_BASE64:
            return ID2SYM(rb_intern("STRING_BASE64"));
        case YP_PACK_STRING_FIXED:
            return ID2SYM(rb_intern("STRING_FIXED"));
        case YP_PACK_STRING_POINTER:
            return ID2SYM(rb_intern("STRING_POINTER"));
        case YP_PACK_MOVE:
            return ID2SYM(rb_intern("MOVE"));
        case YP_PACK_BACK:
            return ID2SYM(rb_intern("BACK"));
        case YP_PACK_NULL:
            return ID2SYM(rb_intern("NULL"));
        default:
            return Qnil;
    }
}

static VALUE
pack_signed_to_symbol(yp_pack_signed signed_type) {
    switch (signed_type) {
        case YP_PACK_UNSIGNED:
            return ID2SYM(rb_intern("UNSIGNED"));
        case YP_PACK_SIGNED:
            return ID2SYM(rb_intern("SIGNED"));
        case YP_PACK_SIGNED_NA:
            return ID2SYM(rb_intern("SIGNED_NA"));
        default:
            return Qnil;
    }
}

static VALUE
pack_endian_to_symbol(yp_pack_endian endian) {
    switch (endian) {
        case YP_PACK_AGNOSTIC_ENDIAN:
            return ID2SYM(rb_intern("AGNOSTIC_ENDIAN"));
        case YP_PACK_LITTLE_ENDIAN:
            return ID2SYM(rb_intern("LITTLE_ENDIAN"));
        case YP_PACK_BIG_ENDIAN:
            return ID2SYM(rb_intern("BIG_ENDIAN"));
        case YP_PACK_NATIVE_ENDIAN:
            return ID2SYM(rb_intern("NATIVE_ENDIAN"));
        case YP_PACK_ENDIAN_NA:
            return ID2SYM(rb_intern("ENDIAN_NA"));
        default:
            return Qnil;
    }
}

static VALUE
pack_size_to_symbol(yp_pack_size size) {
    switch (size) {
        case YP_PACK_SIZE_SHORT:
            return ID2SYM(rb_intern("SIZE_SHORT"));
        case YP_PACK_SIZE_INT:
            return ID2SYM(rb_intern("SIZE_INT"));
        case YP_PACK_SIZE_LONG:
            return ID2SYM(rb_intern("SIZE_LONG"));
        case YP_PACK_SIZE_LONG_LONG:
            return ID2SYM(rb_intern("SIZE_LONG_LONG"));
        case YP_PACK_SIZE_8:
            return ID2SYM(rb_intern("SIZE_8"));
        case YP_PACK_SIZE_16:
            return ID2SYM(rb_intern("SIZE_16"));
        case YP_PACK_SIZE_32:
            return ID2SYM(rb_intern("SIZE_32"));
        case YP_PACK_SIZE_64:
            return ID2SYM(rb_intern("SIZE_64"));
        case YP_PACK_SIZE_P:
            return ID2SYM(rb_intern("SIZE_P"));
        case YP_PACK_SIZE_NA:
            return ID2SYM(rb_intern("SIZE_NA"));
        default:
            return Qnil;
    }
}

static VALUE
pack_length_type_to_symbol(yp_pack_length_type length_type) {
    switch (length_type) {
        case YP_PACK_LENGTH_FIXED:
            return ID2SYM(rb_intern("LENGTH_FIXED"));
        case YP_PACK_LENGTH_MAX:
            return ID2SYM(rb_intern("LENGTH_MAX"));
        case YP_PACK_LENGTH_RELATIVE:
            return ID2SYM(rb_intern("LENGTH_RELATIVE"));
        case YP_PACK_LENGTH_NA:
            return ID2SYM(rb_intern("LENGTH_NA"));
        default:
            return Qnil;
    }
}

static VALUE
pack_encoding_to_ruby(yp_pack_encoding encoding) {
    int index;
    switch (encoding) {
        case YP_PACK_ENCODING_ASCII_8BIT:
            index = rb_ascii8bit_encindex();
            break;
        case YP_PACK_ENCODING_US_ASCII:
            index = rb_usascii_encindex();
            break;
        case YP_PACK_ENCODING_UTF_8:
            index = rb_utf8_encindex();
            break;
        default:
            return Qnil;
    }
    return rb_enc_from_encoding(rb_enc_from_index(index));
}

static VALUE
pack_parse(VALUE self, VALUE version_symbol, VALUE variant_symbol, VALUE format_string) {
    if (version_symbol != v3_2_0_symbol) {
        rb_raise(rb_eArgError, "invalid version");
    }

    yp_pack_variant variant;
    if (variant_symbol == pack_symbol) {
        variant = YP_PACK_VARIANT_PACK;
    } else if (variant_symbol == unpack_symbol) {
        variant = YP_PACK_VARIANT_UNPACK;
    } else {
        rb_raise(rb_eArgError, "invalid variant");
    }

    StringValue(format_string);

    const char *format = RSTRING_PTR(format_string);
    const char *format_end = format + RSTRING_LEN(format_string);
    yp_pack_encoding encoding = YP_PACK_ENCODING_START;

    VALUE directives_array = rb_ary_new();

    while (format < format_end) {
        yp_pack_type type;
        yp_pack_signed signed_type;
        yp_pack_endian endian;
        yp_pack_size size;
        yp_pack_length_type length_type;
        uint64_t length;

        const char *directive_start = format;

        yp_pack_result parse_result = yp_pack_parse(variant, &format, format_end, &type, &signed_type, &endian,
                                                    &size, &length_type, &length, &encoding);

        const char *directive_end = format;

        switch (parse_result) {
            case YP_PACK_OK:
                break;
            case YP_PACK_ERROR_UNSUPPORTED_DIRECTIVE:
                rb_raise(rb_eArgError, "unsupported directive");
            case YP_PACK_ERROR_UNKNOWN_DIRECTIVE:
                rb_raise(rb_eArgError, "unsupported directive");
            case YP_PACK_ERROR_LENGTH_TOO_BIG:
                rb_raise(rb_eRangeError, "pack length too big");
            case YP_PACK_ERROR_BANG_NOT_ALLOWED:
                rb_raise(rb_eRangeError, "bang not allowed");
            case YP_PACK_ERROR_DOUBLE_ENDIAN:
                rb_raise(rb_eRangeError, "double endian");
            default:
                rb_bug("parse result");
        }

        if (type == YP_PACK_END) {
            break;
        }

        VALUE directive_args[9] = { version_symbol,
                                    variant_symbol,
                                    rb_usascii_str_new(directive_start, directive_end - directive_start),
                                    pack_type_to_symbol(type),
                                    pack_signed_to_symbol(signed_type),
                                    pack_endian_to_symbol(endian),
                                    pack_size_to_symbol(size),
                                    pack_length_type_to_symbol(length_type),
                                    UINT64T2NUM(length) };

        rb_ary_push(directives_array, rb_class_new_instance(9, directive_args, rb_cYARPPackDirective));
    }

    VALUE format_args[2];
    format_args[0] = directives_array;
    format_args[1] = pack_encoding_to_ruby(encoding);
    return rb_class_new_instance(2, format_args, rb_cYARPPackFormat);
}

void
Init_yarp_pack(void) {
    rb_cYARP = rb_define_module("YARP");
    rb_cYARPPack = rb_define_module_under(rb_cYARP, "Pack");
    rb_cYARPPackDirective = rb_define_class_under(rb_cYARPPack, "Directive", rb_cObject);
    rb_cYARPPackFormat = rb_define_class_under(rb_cYARPPack, "Format", rb_cObject);
    rb_define_singleton_method(rb_cYARPPack, "parse", pack_parse, 3);

    v3_2_0_symbol = ID2SYM(rb_intern("v3_2_0"));
    pack_symbol = ID2SYM(rb_intern("pack"));
    unpack_symbol = ID2SYM(rb_intern("unpack"));
}
