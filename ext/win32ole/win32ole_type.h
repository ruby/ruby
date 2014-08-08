#ifndef WIN32OLE_TYPE_H
#define WIN32OLE_TYPE_H 1
VALUE cWIN32OLE_TYPE;
VALUE create_win32ole_type(ITypeInfo *pTypeInfo, VALUE name);
ITypeInfo *itypeinfo(VALUE self);
void Init_win32ole_type();
#endif
