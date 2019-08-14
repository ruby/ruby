#ifndef WIN32OLE_PARAM_H
#define WIN32OLE_PARAM_H

VALUE create_win32ole_param(ITypeInfo *pTypeInfo, UINT method_index, UINT index, VALUE name);
void Init_win32ole_param(void);

#endif

