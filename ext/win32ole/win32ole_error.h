#ifndef WIN32OLE_ERROR_H
#define WIN32OLE_ERROR_H 1

VALUE eWIN32OLERuntimeError;
VALUE eWIN32OLEQueryInterfaceError;
NORETURN(PRINTF_ARGS(void ole_raise(HRESULT hr, VALUE ecs, const char *fmt, ...), 3, 4));
void Init_win32ole_error(void);

#endif
