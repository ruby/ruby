#ifndef WIN32OLE_ERROR_H
#define WIN32OLE_ERROR_H 1

VALUE eWIN32OLERuntimeError;
void ole_raise(HRESULT hr, VALUE ecs, const char *fmt, ...);
void Init_win32ole_error(void);

#endif
