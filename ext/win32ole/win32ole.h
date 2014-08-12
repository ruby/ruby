#ifndef WIN32OLE_H
#define WIN32OLE_H 1
#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/encoding.h"

#define GNUC_OLDER_3_4_4 \
    ((__GNUC__ < 3) || \
     ((__GNUC__ <= 3) && (__GNUC_MINOR__ < 4)) || \
     ((__GNUC__ <= 3) && (__GNUC_MINOR__ <= 4) && (__GNUC_PATCHLEVEL__ <= 4)))

#if (defined(__GNUC__)) && (GNUC_OLDER_3_4_4)
#ifndef NONAMELESSUNION
#define NONAMELESSUNION 1
#endif
#endif

#include <ctype.h>

#include <windows.h>
#include <ocidl.h>
#include <olectl.h>
#include <ole2.h>
#if defined(HAVE_TYPE_IMULTILANGUAGE2) || defined(HAVE_TYPE_IMULTILANGUAGE)
#include <mlang.h>
#endif
#include <stdlib.h>
#include <math.h>
#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif
#include <objidl.h>

#define DOUT fprintf(stderr,"%s(%d)\n", __FILE__, __LINE__)
#define DOUTS(x) fprintf(stderr,"%s(%d):" #x "=%s\n",__FILE__, __LINE__,x)
#define DOUTMSG(x) fprintf(stderr, "%s(%d):" #x "\n",__FILE__, __LINE__)
#define DOUTI(x) fprintf(stderr, "%s(%d):" #x "=%d\n",__FILE__, __LINE__,x)
#define DOUTD(x) fprintf(stderr, "%s(%d):" #x "=%f\n",__FILE__, __LINE__,x)

#if (defined(__GNUC__)) && (GNUC_OLDER_3_4_4)
#define V_UNION1(X, Y) ((X)->u.Y)
#else
#define V_UNION1(X, Y) ((X)->Y)
#endif

#if (defined(__GNUC__)) && (GNUC_OLDER_3_4_4)
#undef V_UNION
#define V_UNION(X,Y) ((X)->n1.n2.n3.Y)

#undef V_VT
#define V_VT(X) ((X)->n1.n2.vt)

#undef V_BOOL
#define V_BOOL(X) V_UNION(X,boolVal)
#endif

#ifndef V_I1REF
#define V_I1REF(X) V_UNION(X, pcVal)
#endif

#ifndef V_UI2REF
#define V_UI2REF(X) V_UNION(X, puiVal)
#endif

#ifndef V_INT
#define V_INT(X) V_UNION(X, intVal)
#endif

#ifndef V_INTREF
#define V_INTREF(X) V_UNION(X, pintVal)
#endif

#ifndef V_UINT
#define V_UINT(X) V_UNION(X, uintVal)
#endif

#ifndef V_UINTREF
#define V_UINTREF(X) V_UNION(X, puintVal)
#endif

#define OLE_ADDREF(X) (X) ? ((X)->lpVtbl->AddRef(X)) : 0
#define OLE_RELEASE(X) (X) ? ((X)->lpVtbl->Release(X)) : 0
#define OLE_FREE(x) {\
    if(ole_initialized() == TRUE) {\
        if(x) {\
            OLE_RELEASE(x);\
            (x) = 0;\
        }\
    }\
}

#define OLE_GET_TYPEATTR(X, Y) ((X)->lpVtbl->GetTypeAttr((X), (Y)))
#define OLE_RELEASE_TYPEATTR(X, Y) ((X)->lpVtbl->ReleaseTypeAttr((X), (Y)))


VALUE cWIN32OLE;
LCID cWIN32OLE_lcid;

LPWSTR ole_vstr2wc(VALUE vstr);
LONG reg_open_key(HKEY hkey, const char *name, HKEY *phkey);
LONG reg_open_vkey(HKEY hkey, VALUE key, HKEY *phkey);
VALUE reg_enum_key(HKEY hkey, DWORD i);
VALUE reg_get_val(HKEY hkey, const char *subkey);
VALUE reg_get_val2(HKEY hkey, const char *subkey);
void ole_initialize(void);
VALUE default_inspect(VALUE self, const char *class_name);
VALUE ole_wc2vstr(LPWSTR pw, BOOL isfree);

#define WC2VSTR(x) ole_wc2vstr((x), TRUE)

BOOL ole_initialized();
HRESULT ole_docinfo_from_type(ITypeInfo *pTypeInfo, BSTR *name, BSTR *helpstr, DWORD *helpcontext, BSTR *helpfile);
VALUE ole_typedesc2val(ITypeInfo *pTypeInfo, TYPEDESC *pTypeDesc, VALUE typedetails);
VALUE make_inspect(const char *class_name, VALUE detail);
VALUE ole_variant2val(VARIANT *pvar);

#include "win32ole_variant_m.h"
#include "win32ole_typelib.h"
#include "win32ole_type.h"
#include "win32ole_variable.h"
#include "win32ole_method.h"
#include "win32ole_param.h"
#include "win32ole_error.h"

#endif
