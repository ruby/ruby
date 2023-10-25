#ifndef WIN32OLE_TYPELIB_H
#define WIN32OLE_TYPELIB_H 1

extern VALUE cWIN32OLE_TYPELIB;

void Init_win32ole_typelib(void);
ITypeLib * itypelib(VALUE self);
VALUE typelib_file(VALUE ole);
VALUE create_win32ole_typelib(ITypeLib *pTypeLib);
VALUE ole_typelib_from_itypeinfo(ITypeInfo *pTypeInfo);
#endif
