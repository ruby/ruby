#ifndef WIN32OLE_VARIANT_H
#define WIN32OLE_VARIANT_H 1

struct olevariantdata {
    VARIANT realvar;
    VARIANT var;
};

VALUE cWIN32OLE_VARIANT;
void Init_win32ole_variant(void);

#endif

