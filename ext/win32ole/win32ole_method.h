#ifndef WIN32OLE_METHOD_H
#define WIN32OLE_METHOD_H 1

struct olemethoddata {
    ITypeInfo *pOwnerTypeInfo;
    ITypeInfo *pTypeInfo;
    UINT index;
};

VALUE cWIN32OLE_METHOD;
VALUE folemethod_s_allocate(VALUE klass);
VALUE olemethod_from_typeinfo(VALUE self, ITypeInfo *pTypeInfo, VALUE name);
VALUE ole_methods_sub(ITypeInfo *pOwnerTypeInfo, ITypeInfo *pTypeInfo, VALUE methods, int mask);
void Init_win32ole_method();
#endif
