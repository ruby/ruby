#include "win32ole.h"

void Init_win32ole_variant_m(void)
{
    /*
     * Document-module: WIN32OLE::VARIANT
     *
     * The WIN32OLE::VARIANT module includes constants of VARIANT type constants.
     * The constants is used when creating WIN32OLE_VARIANT object.
     *
     *   obj = WIN32OLE_VARIANT.new("2e3", WIN32OLE::VARIANT::VT_R4)
     *   obj.value # => 2000.0
     *
     */
    mWIN32OLE_VARIANT = rb_define_module_under(cWIN32OLE, "VARIANT");

    /*
     * represents VT_EMPTY type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_EMPTY", INT2FIX(VT_EMPTY));

    /*
     * represents VT_NULL type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_NULL", INT2FIX(VT_NULL));

    /*
     * represents VT_I2 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_I2", INT2FIX(VT_I2));

    /*
     * represents VT_I4 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_I4", INT2FIX(VT_I4));

    /*
     * represents VT_R4 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_R4", INT2FIX(VT_R4));

    /*
     * represents VT_R8 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_R8", INT2FIX(VT_R8));

    /*
     * represents VT_CY type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_CY", INT2FIX(VT_CY));

    /*
     * represents VT_DATE type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_DATE", INT2FIX(VT_DATE));

    /*
     * represents VT_BSTR type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_BSTR", INT2FIX(VT_BSTR));

    /*
     * represents VT_USERDEFINED type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_USERDEFINED", INT2FIX(VT_USERDEFINED));

    /*
     * represents VT_PTR type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_PTR", INT2FIX(VT_PTR));

    /*
     * represents VT_DISPATCH type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_DISPATCH", INT2FIX(VT_DISPATCH));

    /*
     * represents VT_ERROR type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_ERROR", INT2FIX(VT_ERROR));

    /*
     * represents VT_BOOL type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_BOOL", INT2FIX(VT_BOOL));

    /*
     * represents VT_VARIANT type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_VARIANT", INT2FIX(VT_VARIANT));

    /*
     * represents VT_UNKNOWN type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_UNKNOWN", INT2FIX(VT_UNKNOWN));

    /*
     * represents VT_I1 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_I1", INT2FIX(VT_I1));

    /*
     * represents VT_UI1 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI1", INT2FIX(VT_UI1));

    /*
     * represents VT_UI2 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI2", INT2FIX(VT_UI2));

    /*
     * represents VT_UI4 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI4", INT2FIX(VT_UI4));

#if (_MSC_VER >= 1300) || defined(__CYGWIN__) || defined(__MINGW32__)
    /*
     * represents VT_I8 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_I8", INT2FIX(VT_I8));

    /*
     * represents VT_UI8 type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI8", INT2FIX(VT_UI8));
#endif

    /*
     * represents VT_INT type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_INT", INT2FIX(VT_INT));

    /*
     * represents VT_UINT type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_UINT", INT2FIX(VT_UINT));

    /*
     * represents VT_ARRAY type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_ARRAY", INT2FIX(VT_ARRAY));

    /*
     * represents VT_BYREF type constant.
     */
    rb_define_const(mWIN32OLE_VARIANT, "VT_BYREF", INT2FIX(VT_BYREF));

}
