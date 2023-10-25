#ifndef WIN32OLE_VARIABLE_H
#define WIN32OLE_VARIABLE_H 1

extern VALUE cWIN32OLE_VARIABLE;
VALUE create_win32ole_variable(ITypeInfo *pTypeInfo, UINT index, VALUE name);
void Init_win32ole_variable(void);

#endif
