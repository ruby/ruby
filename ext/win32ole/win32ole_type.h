#ifndef WIN32OLE_TYPE_H
#define WIN32OLE_TYPE_H 1
extern VALUE cWIN32OLE_TYPE;
VALUE create_win32ole_type(ITypeInfo *pTypeInfo, VALUE name);
ITypeInfo *itypeinfo(VALUE self);
VALUE ole_type_from_itypeinfo(ITypeInfo *pTypeInfo);
void Init_win32ole_type(void);
#endif
