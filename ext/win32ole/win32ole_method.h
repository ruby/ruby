#ifndef WIN32OLE_METHOD_H
#define WIN32OLE_METHOD_H 1

struct olemethoddata {
    ITypeInfo *pOwnerTypeInfo;
    ITypeInfo *pTypeInfo;
    UINT index;
};

extern VALUE cWIN32OLE_METHOD;
VALUE folemethod_s_allocate(VALUE klass);
VALUE ole_methods_from_typeinfo(ITypeInfo *pTypeInfo, int mask);
VALUE create_win32ole_method(ITypeInfo *pTypeInfo, VALUE name);
struct olemethoddata *olemethod_data_get_struct(VALUE obj);
void Init_win32ole_method(void);
#endif
