#ifndef WIN32OLE_VARIANT_H
#define WIN32OLE_VARIANT_H 1

extern VALUE cWIN32OLE_VARIANT;
void ole_variant2variant(VALUE val, VARIANT *var);
void Init_win32ole_variant(void);

#endif

