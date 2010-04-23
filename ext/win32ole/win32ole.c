/*
 *  (c) 1995 Microsoft Corporation. All rights reserved.
 *  Developed by ActiveWare Internet Corp., http://www.ActiveWare.com
 *
 *  Other modifications Copyright (c) 1997, 1998 by Gurusamy Sarathy
 *  <gsar@umich.edu> and Jan Dubois <jan.dubois@ibm.net>
 *
 *  You may distribute under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the README file
 *  of the Perl distribution.
 *
 */

/*
  modified for win32ole (ruby) by Masaki.Suketa <masaki.suketa@nifty.ne.jp>
 */

#include "ruby.h"
#include "st.h"
#include <windows.h>
#include <ocidl.h>
#include <olectl.h>
#include <ole2.h>
#include <math.h>
#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif
#include <objidl.h>

#define DOUT fprintf(stderr,"[%d]\n",__LINE__)
#define DOUTS(x) fprintf(stderr,"[%d]:" #x "=%s\n",__LINE__,x)
#define DOUTMSG(x) fprintf(stderr, "[%d]:" #x "\n",__LINE__)
#define DOUTI(x) fprintf(stderr, "[%ld]:" #x "=%d\n",__LINE__,x)
#define DOUTD(x) fprintf(stderr, "[%d]:" #x "=%f\n",__LINE__,x)

#if defined NONAMELESSUNION && __GNUC__
#define V_UNION1(X, Y) ((X)->u.Y)
#else
#define V_UNION1(X, Y) ((X)->Y)
#endif

#if defined NONAMELESSUNION && __GNUC__
#undef V_UNION
#define V_UNION(X,Y) ((X)->n1.n2.n3.Y)

#undef V_VT
#define V_VT(X) ((X)->n1.n2.vt)

#undef V_BOOL
#define V_BOOL(X) V_UNION(X,boolVal)
#endif

#define OLE_RELEASE(X) (X) ? ((X)->lpVtbl->Release(X)) : 0

#define OLE_ADDREF(X) (X) ? ((X)->lpVtbl->AddRef(X)) : 0

#define OLE_GET_TYPEATTR(X, Y) ((X)->lpVtbl->GetTypeAttr((X), (Y)))
#define OLE_RELEASE_TYPEATTR(X, Y) ((X)->lpVtbl->ReleaseTypeAttr((X), (Y)))

#define OLE_FREE(x) {\
    if(gOLEInitialized == Qtrue) {\
        if(x) {\
            OLE_RELEASE(x);\
            (x) = 0;\
        }\
    }\
}

#define OLEData_Get_Struct(obj, pole) {\
    Data_Get_Struct(obj, struct oledata, pole);\
    if(!pole->pDispatch) {\
        rb_raise(rb_eRuntimeError, "failed to get Dispatch Interface");\
    }\
}

#define WC2VSTR(x) ole_wc2vstr((x), TRUE)

#define WIN32OLE_VERSION "0.7.8"

typedef HRESULT (STDAPICALLTYPE FNCOCREATEINSTANCEEX)
    (REFCLSID, IUnknown*, DWORD, COSERVERINFO*, DWORD, MULTI_QI*);

typedef HWND (WINAPI FNHTMLHELP)(HWND hwndCaller, LPCSTR pszFile,
                                 UINT uCommand, DWORD dwData);
typedef struct {
    struct IEventSinkVtbl * lpVtbl;
} IEventSink, *PEVENTSINK;

typedef struct IEventSinkVtbl IEventSinkVtbl;

struct IEventSinkVtbl {
    STDMETHOD(QueryInterface)(
        PEVENTSINK,
        REFIID,
        LPVOID *);
    STDMETHOD_(ULONG, AddRef)(PEVENTSINK);
    STDMETHOD_(ULONG, Release)(PEVENTSINK);

    STDMETHOD(GetTypeInfoCount)(
        PEVENTSINK,
        UINT *);
    STDMETHOD(GetTypeInfo)(
        PEVENTSINK,
        UINT,
        LCID,
        ITypeInfo **);
    STDMETHOD(GetIDsOfNames)(
        PEVENTSINK,
        REFIID,
        OLECHAR **,
        UINT,
        LCID,
        DISPID *);
    STDMETHOD(Invoke)(
        PEVENTSINK,
        DISPID,
        REFIID,
        LCID,
        WORD,
        DISPPARAMS *,
        VARIANT *,
        EXCEPINFO *,
        UINT *);
};

typedef struct tagIEVENTSINKOBJ {
    IEventSinkVtbl *lpVtbl;
    DWORD m_cRef;
    IID m_iid;
    int m_event_id;
    DWORD m_dwCookie;
    IConnectionPoint *pConnectionPoint;
    ITypeInfo *pTypeInfo;
    int *ptr_freed;
}IEVENTSINKOBJ, *PIEVENTSINKOBJ;

VALUE cWIN32OLE;
VALUE cWIN32OLE_TYPE;
VALUE cWIN32OLE_VARIABLE;
VALUE cWIN32OLE_METHOD;
VALUE cWIN32OLE_PARAM;
VALUE cWIN32OLE_EVENT;
VALUE eWIN32OLE_RUNTIME_ERROR;
VALUE mWIN32OLE_VARIANT;

static VALUE ary_ole_event;
static ID id_events;
static BOOL gOLEInitialized = Qfalse;
static HINSTANCE ghhctrl = NULL;
static HINSTANCE gole32 = NULL;
static FNCOCREATEINSTANCEEX *gCoCreateInstanceEx = NULL;
static VALUE com_hash;
static IDispatchVtbl com_vtbl;
static UINT  cWIN32OLE_cp = CP_ACP;
static VARTYPE g_nil_to = VT_ERROR;
static IMessageFilterVtbl message_filter;
static IMessageFilter imessage_filter = { &message_filter };
static IMessageFilter* previous_filter;

struct oledata {
    IDispatch *pDispatch;
};

struct oletypedata {
    ITypeInfo *pTypeInfo;
};

struct olemethoddata {
    ITypeInfo *pOwnerTypeInfo;
    ITypeInfo *pTypeInfo;
    UINT index;
};

struct olevariabledata {
    ITypeInfo *pTypeInfo;
    UINT index;
};

struct oleparamdata {
    ITypeInfo *pTypeInfo;
    UINT method_index;
    UINT index;
};

struct oleeventdata {
    IEVENTSINKOBJ *pEvent;
    int freed;
};

struct oleparam {
    DISPPARAMS dp;
    OLECHAR** pNamedArgs;
};

static VALUE folemethod_s_allocate _((VALUE));
static VALUE olemethod_set_member _((VALUE, ITypeInfo *, ITypeInfo *, int, VALUE));
static VALUE foletype_s_allocate _((VALUE));
static VALUE oletype_set_member  _((VALUE, ITypeInfo *, VALUE));
static VALUE olemethod_from_typeinfo _((VALUE, ITypeInfo *, VALUE));
static HRESULT ole_docinfo_from_type _((ITypeInfo *, BSTR *, BSTR *, DWORD *, BSTR *));
static char *ole_wc2mb(LPWSTR);
static VALUE ole_variant2val(VARIANT*);
static void ole_val2variant(VALUE, VARIANT*);
  
static HRESULT (STDMETHODCALLTYPE mf_QueryInterface)(
    IMessageFilter __RPC_FAR * This,
    /* [in] */ REFIID riid,
    /* [iid_is][out] */ void __RPC_FAR *__RPC_FAR *ppvObject)
{
    if (MEMCMP(riid, &IID_IUnknown, GUID, 1) == 0
        || MEMCMP(riid, &IID_IMessageFilter, GUID, 1) == 0)
    {
        *ppvObject = &message_filter;
        return S_OK;
    }
    return E_NOINTERFACE;
}

static ULONG (STDMETHODCALLTYPE mf_AddRef)( 
    IMessageFilter __RPC_FAR * This)
{
    return 1;
}
        
static ULONG (STDMETHODCALLTYPE mf_Release)( 
    IMessageFilter __RPC_FAR * This)
{
    return 1;
}

static DWORD (STDMETHODCALLTYPE mf_HandleInComingCall)(
    IMessageFilter __RPC_FAR * pThis,
    DWORD dwCallType,      //Type of incoming call
    HTASK threadIDCaller,  //Task handle calling this task
    DWORD dwTickCount,     //Elapsed tick count
    LPINTERFACEINFO lpInterfaceInfo //Pointer to INTERFACEINFO structure
    )
{
#ifdef DEBUG_MESSAGEFILTER
    printf("incoming %08X, %08X, %d\n", dwCallType, threadIDCaller, dwTickCount);
    fflush(stdout);
#endif
    switch (dwCallType)
    {
    case CALLTYPE_ASYNC:
    case CALLTYPE_TOPLEVEL_CALLPENDING:
    case CALLTYPE_ASYNC_CALLPENDING:
        if (rb_during_gc()) {
            return SERVERCALL_RETRYLATER;
        }
        break;
    default:
        break;
    }
    if (previous_filter) {
        return previous_filter->lpVtbl->HandleInComingCall(previous_filter,
                                                   dwCallType,
                                                   threadIDCaller,
                                                   dwTickCount,
                                                   lpInterfaceInfo);
    }
    return SERVERCALL_ISHANDLED;
}

static DWORD (STDMETHODCALLTYPE mf_RetryRejectedCall)(
    IMessageFilter* pThis,
    HTASK threadIDCallee,  //Server task handle
    DWORD dwTickCount,     //Elapsed tick count
    DWORD dwRejectType     //Returned rejection message
    )
{
    if (previous_filter) {
        return previous_filter->lpVtbl->RetryRejectedCall(previous_filter,
                                                  threadIDCallee,
                                                  dwTickCount,
                                                  dwRejectType);
    }
    return 1000;
}

static DWORD (STDMETHODCALLTYPE mf_MessagePending)(
    IMessageFilter* pThis,
    HTASK threadIDCallee,  //Called applications task handle
    DWORD dwTickCount,     //Elapsed tick count
    DWORD dwPendingType    //Call type
    )
{
    if (rb_during_gc()) {
        return PENDINGMSG_WAITNOPROCESS;
    }
    if (previous_filter) {
        return previous_filter->lpVtbl->MessagePending(previous_filter,
                                               threadIDCallee,
                                               dwTickCount,
                                               dwPendingType);
    }
    return PENDINGMSG_WAITNOPROCESS;
}
    
typedef struct _Win32OLEIDispatch
{
    IDispatch dispatch;
    ULONG refcount;
    VALUE obj;
} Win32OLEIDispatch;

static HRESULT ( STDMETHODCALLTYPE QueryInterface )( 
    IDispatch __RPC_FAR * This,
    /* [in] */ REFIID riid,
    /* [iid_is][out] */ void __RPC_FAR *__RPC_FAR *ppvObject)
{
    if (MEMCMP(riid, &IID_IUnknown, GUID, 1) == 0
        || MEMCMP(riid, &IID_IDispatch, GUID, 1) == 0)
    {
        Win32OLEIDispatch* p = (Win32OLEIDispatch*)This;
        p->refcount++;
        *ppvObject = This;
        return S_OK;
    }
    return E_NOINTERFACE;
}
        
static ULONG ( STDMETHODCALLTYPE AddRef )( 
    IDispatch __RPC_FAR * This)
{
    Win32OLEIDispatch* p = (Win32OLEIDispatch*)This;
    return ++(p->refcount);
}
        
static ULONG ( STDMETHODCALLTYPE Release )( 
    IDispatch __RPC_FAR * This)
{
    Win32OLEIDispatch* p = (Win32OLEIDispatch*)This;
    ULONG u = --(p->refcount);
    if (u == 0) {
        st_data_t key = p->obj;
        st_delete(DATA_PTR(com_hash), &key, 0);
        free(p);
    }
    return u;
}
        
static HRESULT ( STDMETHODCALLTYPE GetTypeInfoCount )( 
    IDispatch __RPC_FAR * This,
    /* [out] */ UINT __RPC_FAR *pctinfo)
{
    return E_NOTIMPL;
}
        
static HRESULT ( STDMETHODCALLTYPE GetTypeInfo )( 
    IDispatch __RPC_FAR * This,
    /* [in] */ UINT iTInfo,
    /* [in] */ LCID lcid,
    /* [out] */ ITypeInfo __RPC_FAR *__RPC_FAR *ppTInfo)
{
    return E_NOTIMPL;
}

        
static HRESULT ( STDMETHODCALLTYPE GetIDsOfNames )( 
    IDispatch __RPC_FAR * This,
    /* [in] */ REFIID riid,
    /* [size_is][in] */ LPOLESTR __RPC_FAR *rgszNames,
    /* [in] */ UINT cNames,
    /* [in] */ LCID lcid,
    /* [size_is][out] */ DISPID __RPC_FAR *rgDispId)
{
    Win32OLEIDispatch* p = (Win32OLEIDispatch*)This;
    char* psz = ole_wc2mb(*rgszNames); // support only one method
    *rgDispId = rb_intern(psz);
    free(psz);
    return S_OK;
}
        
static /* [local] */ HRESULT ( STDMETHODCALLTYPE Invoke )( 
    IDispatch __RPC_FAR * This,
    /* [in] */ DISPID dispIdMember,
    /* [in] */ REFIID riid,
    /* [in] */ LCID lcid,
    /* [in] */ WORD wFlags,
    /* [out][in] */ DISPPARAMS __RPC_FAR *pDispParams,
    /* [out] */ VARIANT __RPC_FAR *pVarResult,
    /* [out] */ EXCEPINFO __RPC_FAR *pExcepInfo,
    /* [out] */ UINT __RPC_FAR *puArgErr)
{
    VALUE v;
    int i;
    int args = pDispParams->cArgs;
    Win32OLEIDispatch* p = (Win32OLEIDispatch*)This;
    VALUE* parg = ALLOCA_N(VALUE, args);
    for (i = 0; i < args; i++) {
        *(parg + i) = ole_variant2val(&pDispParams->rgvarg[args - i - 1]);
    }
    if (dispIdMember == DISPID_VALUE) {
        if (wFlags == DISPATCH_METHOD) {
            dispIdMember = rb_intern("call");
        } else if (wFlags & DISPATCH_PROPERTYGET) {
            dispIdMember = rb_intern("value");
        }
    }
    v = rb_funcall2(p->obj, dispIdMember, args, parg);
    ole_val2variant(v, pVarResult);
    return S_OK;
}

static IDispatch*
val2dispatch(val)
    VALUE val;
{
    struct st_table *tbl = DATA_PTR(com_hash);
    Win32OLEIDispatch* pdisp;
    st_data_t data;

    if (st_lookup(tbl, val, &data)) {
        pdisp = (Win32OLEIDispatch *)(data & ~FIXNUM_FLAG);
        pdisp->refcount++;
    }
    else {
        pdisp = ALLOC(Win32OLEIDispatch);
        pdisp->dispatch.lpVtbl = &com_vtbl;
        pdisp->refcount = 1;
        pdisp->obj = val;
        st_insert(tbl, val, (VALUE)pdisp | FIXNUM_FLAG);
    }
    return &pdisp->dispatch;
}

static void
time2d(hh, mm, ss, pv)
    int hh, mm, ss;
    double *pv;
{
    *pv =  (hh * 60.0 * 60.0 + mm * 60.0 + ss) / 86400.0;
}

static void
d2time(v, hh, mm, ss)
    double v;
    int *hh, *mm, *ss;
{
    double d_hh, d_mm, d_ss;
    int    i_hh, i_mm, i_ss;

    double d = fabs(v * 86400.0);

    d_hh = d / 3600.0;
    i_hh = (int)d_hh;

    d = d - i_hh * 3600.0;

    d_mm = d / 60.0;
    i_mm = (int)d_mm;

    d = d - i_mm * 60.0;

    d_ss = d * 10.0 + 5;
    
    i_ss = (int)d_ss / 10;

    if(i_ss == 60) {
        i_mm += 1;
        i_ss = 0;
    }

    if (i_mm == 60) {
        i_hh += 1;
        i_mm = 0;
    }
    if (i_hh == 24) {
        i_hh = 0;
    }
    
    *hh = i_hh;
    *mm = i_mm;
    *ss = i_ss;
}

static void
civil2jd(y, m, d, jd)
    int y, m, d;
    long *jd;
{
    long a, b;
    if (m <= 2) {
        y -= 1;
        m += 12;
    }
    a = (long)(y / 100.0);
    b = 2 - a + (long)(a / 4.0);
    *jd = (long)(365.25 * (double)(y + 4716))
         + (long)(30.6001 * (m + 1))
         + d + b - 1524;
}

static void
jd2civil(day, yy, mm, dd)
    long day;
    int *yy, *mm, *dd;
{
    long x, a, b, c, d, e;
    x = (long)(((double)day - 1867216.25) / 36524.25);
    a = day + 1 + x - (long)(x / 4.0);
    b = a + 1524;
    c = (long)(((double)b -122.1) /365.25);
    d = (long)(365.25 * c);
    e = (long)((double)(b - d) / 30.6001);
    *dd = b - d - (long)(30.6001 * e);
    if (e <= 13) {
        *mm = e - 1;
        *yy = c - 4716;
    }
    else {
        *mm = e - 13;
        *yy = c - 4715;
    }
}

static void
double2time(v, y, m, d, hh, mm, ss)
    double v;
    int *y, *m, *d, *hh, *mm, *ss;
{
    long day;
    double t;

    day = (long)v;
    t = v - day;
    jd2civil(2415019 + day, y, m, d);

    d2time(t, hh, mm, ss);
}

static double
time_object2date(tmobj)
    VALUE tmobj;
{
    long y, m, d, hh, mm, ss;
    long day;
    double t;
    y = FIX2INT(rb_funcall(tmobj, rb_intern("year"), 0));
    m = FIX2INT(rb_funcall(tmobj, rb_intern("month"), 0));
    d = FIX2INT(rb_funcall(tmobj, rb_intern("mday"), 0));
    hh = FIX2INT(rb_funcall(tmobj, rb_intern("hour"), 0));
    mm = FIX2INT(rb_funcall(tmobj, rb_intern("min"), 0));
    ss = FIX2INT(rb_funcall(tmobj, rb_intern("sec"), 0));
    civil2jd(y, m, d, &day);
    time2d(hh, mm, ss, &t);
    return t + day - 2415019;
}

static VALUE
date2time_str(date)
    double date;
{
    int y, m, d, hh, mm, ss;
    char szTime[40];
    double2time(date, &y, &m, &d, &hh, &mm, &ss);
    sprintf(szTime,
            "%4.4d/%02.2d/%02.2d %02.2d:%02.2d:%02.2d",
            y, m, d, hh, mm, ss);
    return rb_str_new2(szTime);
}

static void ole_val2variant();

static char *
ole_wc2mb(pw)
    LPWSTR pw;
{
    int size;
    LPSTR pm;
    size = WideCharToMultiByte(cWIN32OLE_cp, 0, pw, -1, NULL, 0, NULL, NULL);
    if (size) {
        pm = ALLOC_N(char, size + 1);    
        WideCharToMultiByte(cWIN32OLE_cp, 0, pw, -1, pm, size, NULL, NULL);
        pm[size] = '\0';
    }
    else {
        pm = ALLOC_N(char, 1);
        *pm = '\0';
    }
    return pm;
} 

static VALUE
ole_hresult2msg(hr)
    HRESULT hr;
{
    VALUE msg = Qnil;
    char *p_msg = NULL;
    char *term = NULL;
    DWORD dwCount;

    char strhr[100];
    sprintf(strhr, "    HRESULT error code:0x%08lx\n      ", hr);
    msg = rb_str_new2(strhr);

    dwCount = FormatMessage(FORMAT_MESSAGE_ALLOCATE_BUFFER |
                            FORMAT_MESSAGE_FROM_SYSTEM |
                            FORMAT_MESSAGE_IGNORE_INSERTS,
                            NULL, hr, LOCALE_SYSTEM_DEFAULT,
                            (LPTSTR)&p_msg, 0, NULL);
    if (dwCount > 0) {
	term = p_msg + strlen(p_msg);
	while (p_msg < term) {
	    term--;
	    if (*term == '\r' || *term == '\n')
	        *term = '\0';
	    else break;
	}
        if (p_msg[0] != '\0') {
            rb_str_cat2(msg, p_msg);
        }
    }
    LocalFree(p_msg);
    return msg;
}

static void
ole_freeexceptinfo(pExInfo)
    EXCEPINFO *pExInfo;
{
    SysFreeString(pExInfo->bstrDescription);
    SysFreeString(pExInfo->bstrSource);
    SysFreeString(pExInfo->bstrHelpFile);
}

static VALUE
ole_excepinfo2msg(pExInfo)
    EXCEPINFO *pExInfo;
{
    char error_code[40];
    char *pSource = NULL;
    char *pDescription = NULL;
    VALUE error_msg;
    if(pExInfo->pfnDeferredFillIn != NULL) {
        (*pExInfo->pfnDeferredFillIn)(pExInfo);
    }
    if (pExInfo->bstrSource != NULL) {
        pSource = ole_wc2mb(pExInfo->bstrSource);
    }
    if (pExInfo->bstrDescription != NULL) {
        pDescription = ole_wc2mb(pExInfo->bstrDescription);
    }
    if(pExInfo->wCode == 0) {
        sprintf(error_code, "\n    OLE error code:%lX in ", pExInfo->scode);
    }
    else{
        sprintf(error_code, "\n    OLE error code:%u in ", pExInfo->wCode);
    }
    error_msg = rb_str_new2(error_code);
    if(pSource != NULL) {
        rb_str_cat(error_msg, pSource, strlen(pSource));
    }
    else {
        rb_str_cat(error_msg, "<Unknown>", 9);
    }
    rb_str_cat2(error_msg, "\n      ");
    if(pDescription != NULL) {
        rb_str_cat2(error_msg, pDescription);
    }
    else {
        rb_str_cat2(error_msg, "<No Description>");
    }
    if(pSource) free(pSource);
    if(pDescription) free(pDescription);
    ole_freeexceptinfo(pExInfo);
    return error_msg;
}

static void
#ifdef HAVE_STDARG_PROTOTYPES
ole_raise(HRESULT hr, VALUE ecs, const char *fmt, ...)
#else
ole_raise(hr, exc, fmt, va_alist)
    HRESULT hr;
    VALUE exc;
    const char *fmt;
    va_dcl
#endif
{
    va_list args;
    char buf[BUFSIZ];
    VALUE err_msg;
    va_init_list(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);

    err_msg = ole_hresult2msg(hr);
    if(err_msg != Qnil) {
        rb_raise(ecs, "%s\n%s", buf, StringValuePtr(err_msg));
    }
    else {
        rb_raise(ecs, "%s", buf);
    }
}

void
ole_uninitialize()
{
    OleUninitialize();
    gOLEInitialized = Qfalse;
}

static void
ole_initialize() 
{
    HRESULT hr;
    
    if(gOLEInitialized == Qfalse) {
        hr = OleInitialize(NULL);
        if(FAILED(hr)) {
            ole_raise(hr, rb_eRuntimeError, "fail: OLE initialize");
        }
        gOLEInitialized = Qtrue;
        /*
         * In some situation, OleUninitialize does not work fine. ;-<
         */
        /*
        atexit((void (*)(void))ole_uninitialize);
        */
        hr = CoRegisterMessageFilter(&imessage_filter, &previous_filter);
        if(FAILED(hr)) {
            previous_filter = NULL;
            ole_raise(hr, rb_eRuntimeError, "fail: install OLE MessageFilter");
        }
    }
}

static void
ole_msg_loop() {
    MSG msg;
    while(PeekMessage(&msg,NULL,0,0,PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
}

static void
ole_free(pole)
    struct oledata *pole;
{
    OLE_FREE(pole->pDispatch);
    free(pole);
}

static void
oletype_free(poletype)
    struct oletypedata *poletype;
{
    OLE_FREE(poletype->pTypeInfo);
    free(poletype);
}

static void
olemethod_free(polemethod)
    struct olemethoddata *polemethod;
{
    OLE_FREE(polemethod->pTypeInfo);
    OLE_FREE(polemethod->pOwnerTypeInfo);
    free(polemethod);
}

static void
olevariable_free(polevar)
    struct olevariabledata *polevar;
{
    OLE_FREE(polevar->pTypeInfo);
    free(polevar);
}

static void
oleparam_free(pole)
    struct oleparamdata *pole;
{
    OLE_FREE(pole->pTypeInfo);
    free(pole);
}

static LPWSTR
ole_mb2wc(pm, len)
    char *pm;
    int  len;
{
    int size;
    LPWSTR pw;
    size = MultiByteToWideChar(cWIN32OLE_cp, 0, pm, len, NULL, 0);
    pw = SysAllocStringLen(NULL, size - 1);
    MultiByteToWideChar(cWIN32OLE_cp, 0, pm, len, pw, size);
    return pw;
}

static VALUE
ole_wc2vstr(pw, isfree)
    LPWSTR pw;
    BOOL isfree;
{
    char *p = ole_wc2mb(pw);
    VALUE vstr = rb_str_new2(p);
    if(isfree)
        SysFreeString(pw);
    free(p);
    return vstr;
}

static VALUE
ole_ary_m_entry(val, pid)
    VALUE val;
    long *pid;
{
    VALUE obj = Qnil;
    int i = 0;
    obj = val;
    while(TYPE(obj) == T_ARRAY) {
        obj = rb_ary_entry(obj, pid[i]);
        i++;
    }
    return obj;
}

static VALUE
is_all_index_under(pid, pub, dim)
    long *pid; 
    long *pub; 
    long dim; 
{
    long i = 0;
    for (i = 0; i < dim; i++) {
        if (pid[i] > pub[i]) {
            return Qfalse;
        }
    }
    return Qtrue;
}

static long
dimension(val) 
    VALUE val;
{
    long dim = 0;
    long dim1 = 0;
    long len = 0;
    long i = 0;
    if (TYPE(val) == T_ARRAY) {
        len = RARRAY(val)->len;
        for (i = 0; i < len; i++) {
            dim1 = dimension(rb_ary_entry(val, i));
            if (dim < dim1) {
                dim = dim1;
            }
        }
        dim += 1;
    }
    return dim;
}

static long 
ary_len_of_dim(ary, dim) 
    VALUE ary;
    long dim;
{
    long ary_len = 0;
    long ary_len1 = 0;
    long len = 0;
    long i = 0;
    VALUE val;
    if (dim == 0) {
        if (TYPE(ary) == T_ARRAY) {
            ary_len = RARRAY(ary)->len;
        }
    } else {
        if (TYPE(ary) == T_ARRAY) {
            len = RARRAY(ary)->len;
            for (i = 0; i < len; i++) {
                val = rb_ary_entry(ary, i);
                ary_len1 = ary_len_of_dim(val, dim-1);
                if (ary_len < ary_len1) {
                    ary_len = ary_len1;
                }
            }
        }
    }
    return ary_len;
}

static void
ole_set_safe_array(n, psa, pid, pub, val, dim)
    long n;
    SAFEARRAY *psa;
    long *pid;
    long *pub;
    VALUE val;
    long dim;
{
    VALUE val1;
    HRESULT hr = S_OK;
    VARIANT var;
    VOID *p = NULL;
    long i = n;
    while(i >= 0) {
        val1 = ole_ary_m_entry(val, pid);
        VariantInit(&var);
        ole_val2variant(val1, &var);
        if (is_all_index_under(pid, pub, dim) == Qtrue) {
            if ((V_VT(&var) == VT_DISPATCH && V_DISPATCH(&var) == NULL) ||
                (V_VT(&var) == VT_UNKNOWN && V_UNKNOWN(&var) == NULL)) {
                rb_raise(eWIN32OLE_RUNTIME_ERROR, "element of array does not have IDispatch or IUnknown Interface");
            }
            hr = SafeArrayPutElement(psa, pid, &var);
        }
        if (FAILED(hr)) {
            ole_raise(hr, rb_eRuntimeError, "failed to SafeArrayPutElement");
        }
        pid[i] += 1;
        if (pid[i] > pub[i]) {
            pid[i] = 0;
            i -= 1;
        } else {
            i = dim - 1;
        }
    }
}

static HRESULT
ole_val_ary2variant_ary(val, var, vt)
    VALUE val;
    VARIANT *var;
    VARTYPE vt;
{
    long dim = 0;
    int  i = 0;
    HRESULT hr = S_OK;

    SAFEARRAYBOUND *psab = NULL;
    SAFEARRAY *psa = NULL;
    long      *pub, *pid;

    Check_Type(val, T_ARRAY);

    dim = dimension(val);

    psab = ALLOC_N(SAFEARRAYBOUND, dim);
    pub  = ALLOC_N(long, dim);
    pid  = ALLOC_N(long, dim);

    if(!psab || !pub || !pid) {
        if(pub) free(pub);
        if(psab) free(psab);
        if(pid) free(pid);
        rb_raise(rb_eRuntimeError, "memory allocation error");
    }

    for (i = 0; i < dim; i++) {
        psab[i].cElements = ary_len_of_dim(val, i);
        psab[i].lLbound = 0;
        pub[i] = psab[i].cElements - 1;
        pid[i] = 0;
    }
    /* Create and fill VARIANT array */
    if ((vt & ~VT_BYREF) == VT_ARRAY) {
        vt = (vt | VT_VARIANT);
    }
    psa = SafeArrayCreate(VT_VARIANT, dim, psab);
    if (psa == NULL)
        hr = E_OUTOFMEMORY;
    else
        hr = SafeArrayLock(psa);
    if (SUCCEEDED(hr)) {
        ole_set_safe_array(dim-1, psa, pid, pub, val, dim);
        hr = SafeArrayUnlock(psa);
    }

    if(pub) free(pub);
    if(psab) free(psab);
    if(pid) free(pid);

    if (SUCCEEDED(hr)) {
        V_VT(var) = vt;
        V_ARRAY(var) = psa;
    }
    else {
        if (psa != NULL)
            SafeArrayDestroy(psa);
    }
    return hr;
}

static void
ole_val2variant(val, var)
    VALUE val;
    VARIANT *var;
{
    struct oledata *pole;
    if(rb_obj_is_kind_of(val, cWIN32OLE)) {
        Data_Get_Struct(val, struct oledata, pole);
        OLE_ADDREF(pole->pDispatch);
        V_VT(var) = VT_DISPATCH;
        V_DISPATCH(var) = pole->pDispatch;
        return;
    }
    if (rb_obj_is_kind_of(val, rb_cTime)) {
        V_VT(var) = VT_DATE;
        V_DATE(var) = time_object2date(val);
        return;
    }
    switch (TYPE(val)) {
    case T_ARRAY:
        ole_val_ary2variant_ary(val, var, VT_VARIANT|VT_ARRAY);
        break;
    case T_STRING:
        V_VT(var) = VT_BSTR;
        V_BSTR(var) = ole_mb2wc(StringValuePtr(val), -1);
        break;
    case T_FIXNUM:
        V_VT(var) = VT_I4;
        V_I4(var) = NUM2INT(val);
        break;
    case T_BIGNUM:
        V_VT(var) = VT_R8;
        V_R8(var) = rb_big2dbl(val);
        break;
    case T_FLOAT:
        V_VT(var) = VT_R8;
        V_R8(var) = NUM2DBL(val);
        break;
    case T_TRUE:
        V_VT(var) = VT_BOOL;
        V_BOOL(var) = VARIANT_TRUE;
        break;
    case T_FALSE:
        V_VT(var) = VT_BOOL;
        V_BOOL(var) = VARIANT_FALSE;
        break;
    case T_NIL:
        if (g_nil_to == VT_ERROR) {
            V_VT(var) = VT_ERROR;
            V_ERROR(var) = DISP_E_PARAMNOTFOUND;
        }else {
            V_VT(var) = VT_EMPTY;
        }
        break;
    default:
        V_VT(var) = VT_DISPATCH;
        V_DISPATCH(var) = val2dispatch(val);
        break;
    }
}

static void
ole_val2variant2(val, var)
    VALUE val;
    VARIANT *var;
{
    g_nil_to = VT_EMPTY;
    ole_val2variant(val, var);
    g_nil_to = VT_ERROR;
}

static VALUE
ole_set_member(self, dispatch)
    VALUE self;
    IDispatch * dispatch;
{
    struct oledata *pole;
    Data_Get_Struct(self, struct oledata, pole);
    if (pole->pDispatch) {
        OLE_RELEASE(pole->pDispatch);
        pole->pDispatch = NULL;
    }
    pole->pDispatch = dispatch;
    return self;
}

static VALUE fole_s_allocate _((VALUE));
static VALUE
fole_s_allocate(klass)
    VALUE klass;
{
    struct oledata *pole;
    VALUE obj;
    ole_initialize();
    obj = Data_Make_Struct(klass,struct oledata,0,ole_free,pole);
    pole->pDispatch = NULL;
    return obj;
}

static VALUE
create_win32ole_object(klass, pDispatch, argc, argv)
    VALUE klass;
    IDispatch *pDispatch;
    int argc;
    VALUE *argv;
{
    VALUE obj = fole_s_allocate(klass);
    ole_set_member(obj, pDispatch);
    return obj;
}

static VALUE
ole_variant2val(pvar)
    VARIANT *pvar;
{
    VALUE obj = Qnil;
    HRESULT hr;
    while ( V_VT(pvar) == (VT_BYREF | VT_VARIANT) )
        pvar = V_VARIANTREF(pvar);

    if(V_ISARRAY(pvar)) {
        SAFEARRAY *psa = V_ISBYREF(pvar) ? *V_ARRAYREF(pvar) : V_ARRAY(pvar);
        long i;
        long *pID, *pLB, *pUB;
        VARIANT variant;
        VALUE val;
        VALUE val2;
        int dim = 0;

        if (!psa) {
            return obj;
        }
        dim = SafeArrayGetDim(psa);

        VariantInit(&variant);
        V_VT(&variant) = (V_VT(pvar) & ~VT_ARRAY) | VT_BYREF;

        pID = ALLOC_N(long, dim);
        pLB = ALLOC_N(long, dim);
        pUB = ALLOC_N(long, dim);

        if(!pID || !pLB || !pUB) {
            if(pID) free(pID);
            if(pLB) free(pLB);
            if(pUB) free(pUB);
            rb_raise(rb_eRuntimeError, "memory allocation error");
        }

        obj = Qnil;

        for(i = 0; i < dim; ++i) {
            SafeArrayGetLBound(psa, i+1, &pLB[i]);
            SafeArrayGetLBound(psa, i+1, &pID[i]);
            SafeArrayGetUBound(psa, i+1, &pUB[i]);
        }

        hr = SafeArrayLock(psa);
        if (SUCCEEDED(hr)) {
            val2 = rb_ary_new();
            while (i >= 0) {
                hr = SafeArrayPtrOfIndex(psa, pID, &V_BYREF(&variant));
                if (FAILED(hr))
                    break;

                val = ole_variant2val(&variant);
                rb_ary_push(val2, val);
                for (i = dim-1 ; i >= 0 ; --i) {
                    if (++pID[i] <= pUB[i])
                        break;

                    pID[i] = pLB[i];
                    if (i > 0) {
                        if (obj == Qnil)
                            obj = rb_ary_new();
                        rb_ary_push(obj, val2);
                        val2 = rb_ary_new();
                    }
                }
            }
            SafeArrayUnlock(psa);
        }
        if(pID) free(pID);
        if(pLB) free(pLB);
        if(pUB) free(pUB);
        return (obj == Qnil) ? val2 : obj;
    }
    switch(V_VT(pvar) & ~VT_BYREF){
    case VT_EMPTY:
        break;
    case VT_NULL:
        break;
    case VT_UI1:
        if(V_ISBYREF(pvar)) 
            obj = INT2NUM((long)*V_UI1REF(pvar));
        else 
            obj = INT2NUM((long)V_UI1(pvar));
        break;

    case VT_I2:
        if(V_ISBYREF(pvar))
            obj = INT2NUM((long)*V_I2REF(pvar));
        else 
            obj = INT2NUM((long)V_I2(pvar));
        break;

    case VT_I4:
        if(V_ISBYREF(pvar))
            obj = INT2NUM((long)*V_I4REF(pvar));
        else 
            obj = INT2NUM((long)V_I4(pvar));
        break;

    case VT_R4:
        if(V_ISBYREF(pvar))
            obj = rb_float_new(*V_R4REF(pvar));
        else
            obj = rb_float_new(V_R4(pvar));
        break;

    case VT_R8:
        if(V_ISBYREF(pvar))
            obj = rb_float_new(*V_R8REF(pvar));
        else
            obj = rb_float_new(V_R8(pvar));
        break;

    case VT_BSTR:
    {
        char *p;
        if(V_ISBYREF(pvar))
            p = ole_wc2mb(*V_BSTRREF(pvar));
        else
            p = ole_wc2mb(V_BSTR(pvar));
        obj = rb_str_new2(p);
        if(p) free(p);
        break;
    }

    case VT_ERROR:
        if(V_ISBYREF(pvar))
            obj = INT2NUM(*V_ERRORREF(pvar));
        else
            obj = INT2NUM(V_ERROR(pvar));
        break;

    case VT_BOOL:
        if (V_ISBYREF(pvar))
            obj = (*V_BOOLREF(pvar) ? Qtrue : Qfalse);
        else
            obj = (V_BOOL(pvar) ? Qtrue : Qfalse);
        break;

    case VT_DISPATCH:
    {
        IDispatch *pDispatch;

        if (V_ISBYREF(pvar))
            pDispatch = *V_DISPATCHREF(pvar);
        else
            pDispatch = V_DISPATCH(pvar);

        if (pDispatch != NULL ) {
            OLE_ADDREF(pDispatch);
            obj = create_win32ole_object(cWIN32OLE, pDispatch, 0, 0);
        }
        break;
    }

    case VT_UNKNOWN:
    {
        /* get IDispatch interface from IUnknown interface */
        IUnknown *punk;
        IDispatch *pDispatch;
        void *p;
        HRESULT hr;

        if (V_ISBYREF(pvar))
            punk = *V_UNKNOWNREF(pvar);
        else
            punk = V_UNKNOWN(pvar);

        if(punk != NULL) {
           hr = punk->lpVtbl->QueryInterface(punk, &IID_IDispatch, &p);
           if(SUCCEEDED(hr)) {
               pDispatch = p;
               obj = create_win32ole_object(cWIN32OLE, pDispatch, 0, 0);
           }
        }
        break;
    }

    case VT_DATE:
    {
        DATE date;
        if(V_ISBYREF(pvar))
            date = *V_DATEREF(pvar);
        else
            date = V_DATE(pvar);

        obj =  date2time_str(date);
        break;
    }
    case VT_CY:
    default:
        {
        HRESULT hr;
        VARIANT variant;
        VariantInit(&variant);
        hr = VariantChangeTypeEx(&variant, pvar, 
                                  LOCALE_SYSTEM_DEFAULT, 0, VT_BSTR);
        if (SUCCEEDED(hr) && V_VT(&variant) == VT_BSTR) {
            char *p = ole_wc2mb(V_BSTR(&variant));
            obj = rb_str_new2(p);
            if(p) free(p);
        }
        VariantClear(&variant);
        break;
        }
    }
    return obj;
}


static LONG reg_open_key(hkey, name, phkey)
    HKEY hkey;
    const char *name;
    HKEY *phkey;
{
    return RegOpenKeyEx(hkey, name, 0, KEY_READ, phkey);
}

static LONG reg_open_vkey(hkey, key, phkey)
    HKEY hkey;
    VALUE key;
    HKEY *phkey;
{
    return reg_open_key(hkey, StringValuePtr(key), phkey);
}

static VALUE
reg_enum_key(hkey, i)
    HKEY hkey;
    DWORD i;
{
    char buf[BUFSIZ + 1];
    DWORD size_buf = sizeof(buf) - 1;
    FILETIME ft;
    LONG err = RegEnumKeyEx(hkey, i, buf, &size_buf,
                            NULL, NULL, NULL, &ft);
    if(err == ERROR_SUCCESS) {
        buf[BUFSIZ] = '\0';
        return rb_str_new2(buf);
    }
    return Qnil;
}

static VALUE
reg_get_val(hkey, subkey)
    HKEY hkey;
    const char *subkey;
{
    char buf[BUFSIZ + 1];
    LONG size_buf = sizeof(buf) - 1;
    LONG err = RegQueryValue(hkey, subkey, buf, &size_buf);
    if (err == ERROR_SUCCESS) {
        buf[BUFSIZ] = '\0';
        return rb_str_new2(buf);
    }
    return Qnil;
}

static VALUE
typelib_file_from_clsid(ole)
    VALUE ole;
{
    OLECHAR *pbuf;
    CLSID clsid;
    HRESULT hr;
    HKEY hroot, hclsid;
    LONG err;
    VALUE typelib;
    VALUE vclsid;
    char *pclsid = NULL;

    pbuf  = ole_mb2wc(StringValuePtr(ole), -1);
    hr = CLSIDFromProgID(pbuf, &clsid);
    SysFreeString(pbuf);
    if (FAILED(hr)) {
        return Qnil;
    }
    StringFromCLSID(&clsid, &pbuf);
    vclsid = WC2VSTR(pbuf);
    err = reg_open_key(HKEY_CLASSES_ROOT, "CLSID", &hroot);
    if (err != ERROR_SUCCESS) {
        return Qnil;
    }
    err = reg_open_key(hroot, StringValuePtr(vclsid), &hclsid);
    if (err != ERROR_SUCCESS) {
        RegCloseKey(hroot);
        return Qnil;
    }
    typelib = reg_get_val(hclsid, "InprocServer32");
    RegCloseKey(hroot);
    RegCloseKey(hclsid);
    return typelib;
}

static VALUE
typelib_file_from_typelib(ole)
    VALUE ole;
{
    HKEY htypelib, hclsid, hversion, hlang;
    double fver;
    DWORD i, j, k;
    LONG err;
    BOOL found = FALSE;
    VALUE typelib;
    VALUE file = Qnil;
    VALUE clsid;
    VALUE ver;
    VALUE lang;

    err = reg_open_key(HKEY_CLASSES_ROOT, "TypeLib", &htypelib);
    if(err != ERROR_SUCCESS) {
        return Qnil;
    }
    for(i = 0; !found; i++) {
        clsid = reg_enum_key(htypelib, i);
        if (clsid == Qnil)
            break;
        err = reg_open_vkey(htypelib, clsid, &hclsid);
        if (err != ERROR_SUCCESS)
            continue;
        fver = 0;
        for(j = 0; !found; j++) {
            ver = reg_enum_key(hclsid, j);
            if (ver == Qnil)
                break;
            err = reg_open_vkey(hclsid, ver, &hversion);
            if (err != ERROR_SUCCESS || fver > atof(StringValuePtr(ver)))
                continue;
            fver = atof(StringValuePtr(ver));
            typelib = reg_get_val(hversion, NULL);
            if (typelib == Qnil)
                continue;
            if (rb_str_cmp(typelib, ole) == 0) {
                for(k = 0; !found; k++) {
                    lang = reg_enum_key(hversion, k);
                    if (lang == Qnil)
                        break;
                    err = reg_open_vkey(hversion, lang, &hlang);
                    if (err == ERROR_SUCCESS) {
                        if ((file = reg_get_val(hlang, "win32")) != Qnil) 
                            found = TRUE;
                        RegCloseKey(hlang);
                    }
                }
            }
            RegCloseKey(hversion);
        }
        RegCloseKey(hclsid);
    }
    RegCloseKey(htypelib);
    return  file;
}

static VALUE
typelib_file(ole)
    VALUE ole;
{
    VALUE file = typelib_file_from_clsid(ole);
    if (file != Qnil) {
        return file;
    }
    return typelib_file_from_typelib(ole);
}

static void
ole_const_load(pTypeLib, klass, self)
    ITypeLib *pTypeLib;
    VALUE klass;
    VALUE self;
{
    unsigned int count;
    unsigned int index;
    int iVar;
    ITypeInfo *pTypeInfo;
    TYPEATTR  *pTypeAttr;
    VARDESC   *pVarDesc;
    HRESULT hr;
    unsigned int len;
    BSTR bstr;
    char *pName = NULL;
    VALUE val;
    VALUE constant;
    ID id;
    constant = rb_hash_new();
    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (index = 0; index < count; index++) {
        hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib, index, &pTypeInfo);
        if (FAILED(hr))
            continue;
        hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
        if(FAILED(hr)) {
            OLE_RELEASE(pTypeInfo);
            continue;
        }
        for(iVar = 0; iVar < pTypeAttr->cVars; iVar++) {
            hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, iVar, &pVarDesc);
            if(FAILED(hr))
                continue;
            if(pVarDesc->varkind == VAR_CONST &&
               !(pVarDesc->wVarFlags & (VARFLAG_FHIDDEN |
                                        VARFLAG_FRESTRICTED |
                                        VARFLAG_FNONBROWSABLE))) {
                hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, pVarDesc->memid, &bstr,
                                                 1, &len);
                if(FAILED(hr) || len == 0 || !bstr)
                    continue;
                pName = ole_wc2mb(bstr);
                val = ole_variant2val(V_UNION1(pVarDesc, lpvarValue));
                *pName = toupper(*pName);
                id = rb_intern(pName);
                if (rb_is_const_id(id)) {
                    rb_define_const(klass, pName, val);
                }
                else {
                    rb_hash_aset(constant, rb_str_new2(pName), val);
                }
                SysFreeString(bstr);
                if(pName) {
                    free(pName);
                    pName = NULL;
                }
            }
            pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
        }
        pTypeInfo->lpVtbl->ReleaseTypeAttr(pTypeInfo, pTypeAttr);
        OLE_RELEASE(pTypeInfo);
    }
    rb_define_const(klass, "CONSTANTS", constant);
}

static HRESULT
clsid_from_remote(host, com, pclsid)
    VALUE host;
    VALUE com;
    CLSID *pclsid;
{
    HKEY hlm;
    HKEY hpid;
    VALUE subkey;
    LONG err;
    char clsid[100];
    OLECHAR *pbuf;
    DWORD len;
    DWORD dwtype;
    HRESULT hr = S_OK;
    err = RegConnectRegistry(StringValuePtr(host), HKEY_LOCAL_MACHINE, &hlm);
    if (err != ERROR_SUCCESS)
        return HRESULT_FROM_WIN32(err);
    subkey = rb_str_new2("SOFTWARE\\Classes\\");
    rb_str_concat(subkey, com);
    rb_str_cat2(subkey, "\\CLSID");
    err = RegOpenKeyEx(hlm, StringValuePtr(subkey), 0, KEY_READ, &hpid);
    if (err != ERROR_SUCCESS)
        hr = HRESULT_FROM_WIN32(err);
    else {
        len = sizeof(clsid);
        err = RegQueryValueEx(hpid, "", NULL, &dwtype, clsid, &len);
        if (err == ERROR_SUCCESS && dwtype == REG_SZ) {
            pbuf  = ole_mb2wc(clsid, -1);
            hr = CLSIDFromString(pbuf, pclsid);
            SysFreeString(pbuf);
        }
        else {
            hr = HRESULT_FROM_WIN32(err);
        }
        RegCloseKey(hpid);
    }
    RegCloseKey(hlm);
    return hr;
}

static VALUE
ole_create_dcom(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE ole, host, others;
    HRESULT hr;
    CLSID   clsid;
    OLECHAR *pbuf;

    COSERVERINFO serverinfo;
    MULTI_QI multi_qi;
    DWORD clsctx = CLSCTX_REMOTE_SERVER;

    if (!gole32)
        gole32 = LoadLibrary("OLE32");
    if (!gole32)
        rb_raise(rb_eRuntimeError, "failed to load OLE32");
    if (!gCoCreateInstanceEx)
        gCoCreateInstanceEx = (FNCOCREATEINSTANCEEX*)
            GetProcAddress(gole32, "CoCreateInstanceEx");
    if (!gCoCreateInstanceEx)
        rb_raise(rb_eRuntimeError, "CoCreateInstanceEx is not supported in this environment");
    rb_scan_args(argc, argv, "2*", &ole, &host, &others);

    pbuf  = ole_mb2wc(StringValuePtr(ole), -1);
    hr = CLSIDFromProgID(pbuf, &clsid);
    if (FAILED(hr))
        hr = clsid_from_remote(host, ole, &clsid);
    if (FAILED(hr))
        hr = CLSIDFromString(pbuf, &clsid);
    SysFreeString(pbuf);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "unknown OLE server: `%s'",
                  StringValuePtr(ole));
    memset(&serverinfo, 0, sizeof(COSERVERINFO));    
    serverinfo.pwszName = ole_mb2wc(StringValuePtr(host), -1);
    memset(&multi_qi, 0, sizeof(MULTI_QI));
    multi_qi.pIID = &IID_IDispatch;
    hr = gCoCreateInstanceEx(&clsid, NULL, clsctx, &serverinfo, 1, &multi_qi);
    SysFreeString(serverinfo.pwszName);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "failed to create DCOM server `%s' in `%s'",
                  StringValuePtr(ole),
                  StringValuePtr(host));

    ole_set_member(self, (IDispatch*)multi_qi.pItf);
    return self;
}

static VALUE
ole_bind_obj(moniker, argc, argv, self)
    VALUE moniker;
    int argc;
    VALUE *argv;
    VALUE self;
{
    IBindCtx *pBindCtx;
    IMoniker *pMoniker;
    IDispatch *pDispatch;
    void *p;
    HRESULT hr;
    OLECHAR *pbuf;
    ULONG eaten = 0;
    
    ole_initialize();

    hr = CreateBindCtx(0, &pBindCtx);
    if(FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "failed to create bind context");
    }

    pbuf  = ole_mb2wc(StringValuePtr(moniker), -1);
    hr = MkParseDisplayName(pBindCtx, pbuf, &eaten, &pMoniker);
    SysFreeString(pbuf);
    if(FAILED(hr)) {
        OLE_RELEASE(pBindCtx);
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR,
                  "failed to parse display name of moniker `%s'",
                  StringValuePtr(moniker));
    }
    hr = pMoniker->lpVtbl->BindToObject(pMoniker, pBindCtx, NULL, 
                                        &IID_IDispatch, &p);
    pDispatch = p;
    OLE_RELEASE(pMoniker);
    OLE_RELEASE(pBindCtx);

    if(FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR,
                  "failed to bind moniker `%s'",
                  StringValuePtr(moniker));
    }
    return create_win32ole_object(self, pDispatch, argc, argv);
}

/*
 *  call-seq:
 *     WIN32OLE.connect( ole ) --> aWIN32OLE
 * 
 *  Returns running OLE Automation object or WIN32OLE object from moniker.
 *  1st argument should be OLE program id or class id or moniker.
 *     
 *     WIN32OLE.connect('Excel.Application') # => WIN32OLE object which represents running Excel.
 */
static VALUE
fole_s_connect(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE svr_name;
    VALUE others;
    HRESULT hr;
    CLSID   clsid;
    OLECHAR *pBuf;
    IDispatch *pDispatch;
    void *p;
    IUnknown *pUnknown;

    rb_secure(4);
    /* initialize to use OLE */
    ole_initialize();

    rb_scan_args(argc, argv, "1*", &svr_name, &others);
    if (ruby_safe_level > 0 && OBJ_TAINTED(svr_name)) {
        rb_raise(rb_eSecurityError, "Insecure Object Connection - %s",
                 StringValuePtr(svr_name));
    }

    /* get CLSID from OLE server name */
    pBuf  = ole_mb2wc(StringValuePtr(svr_name), -1);
    hr = CLSIDFromProgID(pBuf, &clsid);
    if(FAILED(hr)) {
        hr = CLSIDFromString(pBuf, &clsid);
    }
    SysFreeString(pBuf);
    if(FAILED(hr)) {
        return ole_bind_obj(svr_name, argc, argv, self);
    }

    hr = GetActiveObject(&clsid, 0, &pUnknown);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "OLE server `%s' not running", StringValuePtr(svr_name));
    }
    hr = pUnknown->lpVtbl->QueryInterface(pUnknown, &IID_IDispatch, &p);
    pDispatch = p;
    if(FAILED(hr)) {
        OLE_RELEASE(pUnknown);
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "failed to create WIN32OLE server `%s'", 
                  StringValuePtr(svr_name));
    }

    OLE_RELEASE(pUnknown);

    return create_win32ole_object(self, pDispatch, argc, argv);
}

/* 
 *  call-seq:
 *     WIN32OLE.const_load( ole, mod = WIN32OLE)
 * 
 *  Defines the constants of OLE Automation server as mod's constants.
 *  The first argument is WIN32OLE object or type library name.
 *  If 2nd argument is omitted, the default is WIN32OLE.
 *  The first letter of Ruby's constant variable name is upper case,
 *  so constant variable name of WIN32OLE object is capitalized.
 *  For example, the 'xlTop' constant of Excel is changed to 'XlTop' 
 *  in WIN32OLE.
 *  If the first letter of constant variabl is not [A-Z], then
 *  the constant is defined as CONSTANTS hash element.
 *
 *     module EXCEL_CONST
 *     end
 *     excel = WIN32OLE.new('Excel.Application')
 *     WIN32OLE.const_load(excel, EXCEL_CONST)
 *     puts EXCEL_CONST::XlTop # => -4160
 *     puts EXCEL_CONST::CONSTANTS['_xlDialogChartSourceData'] # => 541
 *     
 *     WIN32OLE.const_load(excel)
 *     puts WIN32OLE::XlTop # => -4160
 *
 *     module MSO
 *     end
 *     WIN32OLE.const_load('Microsoft Office 9.0 Object Library', MSO)
 *     puts MSO::MsoLineSingle # => 1
 */
static VALUE
fole_s_const_load(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE ole;
    VALUE klass;
    struct oledata *pole;
    ITypeInfo *pTypeInfo;
    ITypeLib *pTypeLib;
    unsigned int index;
    HRESULT hr;
    OLECHAR *pBuf;
    VALUE file;
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;
    
    rb_secure(4);
    rb_scan_args(argc, argv, "11", &ole, &klass);
    if (TYPE(klass) != T_CLASS &&
        TYPE(klass) != T_MODULE &&
        TYPE(klass) != T_NIL) {
        rb_raise(rb_eTypeError, "2nd parameter must be Class or Module");
    }
    if (rb_obj_is_kind_of(ole, cWIN32OLE)) {
        OLEData_Get_Struct(ole, pole);
        hr = pole->pDispatch->lpVtbl->GetTypeInfo(pole->pDispatch,
                                                  0, lcid, &pTypeInfo);
        if(FAILED(hr)) {
            ole_raise(hr, rb_eRuntimeError, "failed to GetTypeInfo");
        }
        hr = pTypeInfo->lpVtbl->GetContainingTypeLib(pTypeInfo, &pTypeLib, &index);
        if(FAILED(hr)) {
            OLE_RELEASE(pTypeInfo);
            ole_raise(hr, rb_eRuntimeError, "failed to GetContainingTypeLib");
        }
        OLE_RELEASE(pTypeInfo);
        if(TYPE(klass) != T_NIL) {
            ole_const_load(pTypeLib, klass, self);
        }
        else {
            ole_const_load(pTypeLib, cWIN32OLE, self);
        }
        OLE_RELEASE(pTypeLib);
    }
    else if(TYPE(ole) == T_STRING) {
        file = typelib_file(ole);
        if (file == Qnil) {
            file = ole;
        }
        pBuf = ole_mb2wc(StringValuePtr(file), -1);
        hr = LoadTypeLibEx(pBuf, REGKIND_NONE, &pTypeLib);
        SysFreeString(pBuf);
        if (FAILED(hr))
            ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to LoadTypeLibEx");
        if(TYPE(klass) != T_NIL) {
            ole_const_load(pTypeLib, klass, self);
        }
        else {
            ole_const_load(pTypeLib, cWIN32OLE, self);
        }
        OLE_RELEASE(pTypeLib);
    }
    else {
        rb_raise(rb_eTypeError, "1st parameter must be WIN32OLE instance");
    }
    return Qnil;
}

static VALUE
ole_classes_from_typelib(pTypeLib, classes)
    ITypeLib *pTypeLib;
    VALUE classes;
{
    
    long count;
    int i;
    HRESULT hr;
    BSTR bstr;
    ITypeInfo *pTypeInfo;
    VALUE type;
  
    rb_secure(4);
    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (i = 0; i < count; i++) {
        hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, i,
                                                &bstr, NULL, NULL, NULL);
        if (FAILED(hr)) 
            continue;

        hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib, i, &pTypeInfo);
        if (FAILED(hr))
            continue;

        type = foletype_s_allocate(cWIN32OLE_TYPE);
        oletype_set_member(type, pTypeInfo, WC2VSTR(bstr));

        rb_ary_push(classes, type);
        OLE_RELEASE(pTypeInfo);
    }
    return classes;
}

static ULONG
reference_count(pole)
    struct oledata * pole;
{
    ULONG n = 0;
    if(pole->pDispatch) {
        OLE_ADDREF(pole->pDispatch);
        n = OLE_RELEASE(pole->pDispatch);
    }
    return n;
}

/*
 *  call-seq:
 *     WIN32OLE.ole_reference_count(aWIN32OLE) --> number
 * 
 *  Returns reference counter of Dispatch interface of WIN32OLE object. 
 *  You should not use this method because this method
 *  exists only for debugging WIN32OLE.
 */
static VALUE
fole_s_reference_count(self, obj)
    VALUE self;
    VALUE obj;
{
    struct oledata * pole;
    OLEData_Get_Struct(obj, pole);
    return INT2NUM(reference_count(pole));
}

/*
 *  call-seq:
 *     WIN32OLE.ole_free(aWIN32OLE) --> number
 * 
 *  Invokes Release method of Dispatch interface of WIN32OLE object. 
 *  You should not use this method because this method
 *  exists only for debugging WIN32OLE.
 *  The return value is reference counter of OLE object.
 */
static VALUE
fole_s_free(self, obj)
    VALUE self;
    VALUE obj;
{
    ULONG n = 0;
    struct oledata * pole;
    OLEData_Get_Struct(obj, pole);
    if(pole->pDispatch) {
        if (reference_count(pole) > 0) {
            n = OLE_RELEASE(pole->pDispatch);
        }
    }
    return INT2NUM(n);
}

static HWND
ole_show_help(helpfile, helpcontext)
    VALUE helpfile;
    VALUE helpcontext;
{
    FNHTMLHELP *pfnHtmlHelp;
    HWND hwnd = 0;

    if(!ghhctrl)
        ghhctrl = LoadLibrary("HHCTRL.OCX");
    if (!ghhctrl)
        return hwnd;
    pfnHtmlHelp = (FNHTMLHELP*)GetProcAddress(ghhctrl, "HtmlHelpA");
    if (!pfnHtmlHelp)
        return hwnd;
    hwnd = pfnHtmlHelp(GetDesktopWindow(), StringValuePtr(helpfile), 
                    0x0f, NUM2INT(helpcontext));
    if (hwnd == 0)
        hwnd = pfnHtmlHelp(GetDesktopWindow(), StringValuePtr(helpfile), 
                 0,  NUM2INT(helpcontext));
    return hwnd;
}

/*
 *  call-seq:
 *     WIN32OLE.ole_show_help(obj [,helpcontext])
 * 
 *  Displays helpfile. The 1st argument specifies WIN32OLE_TYPE
 *  object or WIN32OLE_METHOD object or helpfile.
 *
 *     typeobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application')
 *     WIN32OLE.ole_show_help(typeobj)
 */
static VALUE
fole_s_show_help(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE target;
    VALUE helpcontext;
    VALUE helpfile;
    VALUE name;
    HWND  hwnd;
    rb_scan_args(argc, argv, "11", &target, &helpcontext);
    if (rb_obj_is_kind_of(target, cWIN32OLE_TYPE) ||
        rb_obj_is_kind_of(target, cWIN32OLE_METHOD)) {
        helpfile = rb_funcall(target, rb_intern("helpfile"), 0);
        if(strlen(StringValuePtr(helpfile)) == 0) {
            name = rb_ivar_get(target, rb_intern("name"));
            rb_raise(rb_eRuntimeError, "no helpfile of `%s'",
                     StringValuePtr(name));
        }
        helpcontext = rb_funcall(target, rb_intern("helpcontext"), 0);
    } else {
        helpfile = target;
    }
    if (TYPE(helpfile) != T_STRING) {
        rb_raise(rb_eTypeError, "1st parameter must be (String|WIN32OLE_TYPE|WIN32OLE_METHOD)");
    }
    hwnd = ole_show_help(helpfile, helpcontext);
    if(hwnd == 0) {
        rb_raise(rb_eRuntimeError, "failed to open help file `%s'",
                 StringValuePtr(helpfile));
    }
    return Qnil;
}

/* 
 *  call-seq:
 *     WIN32OLE.codepage
 * 
 *  Returns current codepage.
 *     WIN32OLE.codepage # => WIN32OLE::CP_ACP
 */
static VALUE
fole_s_get_code_page(self)
    VALUE self;
{
    return INT2FIX(cWIN32OLE_cp);
}

/* 
 *  call-seq:
 *     WIN32OLE.codepage = CP
 * 
 *  Sets current codepage.
 *     WIN32OLE.codepage = WIN32OLE::CP_UTF8
 */
static VALUE
fole_s_set_code_page(self, vcp)
    VALUE self;
    VALUE vcp;
{
    UINT cp = FIX2INT(vcp);

    switch(cp) {
    case CP_ACP:
    case CP_OEMCP:
    case CP_MACCP:
    case CP_THREAD_ACP:
    case CP_SYMBOL:
    case CP_UTF7:
    case CP_UTF8:
        cWIN32OLE_cp = cp;
        break;
    default:
        rb_raise(eWIN32OLE_RUNTIME_ERROR, "codepage should be WIN32OLE::CP_ACP, WIN32OLE::CP_OEMCP, WIN32OLE::CP_MACCP, WIN32OLE::CP_THREAD_ACP, WIN32OLE::CP_SYMBOL, WIN32OLE::CP_UTF7, WIN32OLE::CP_UTF8");
        break;
    }

    /*
     * Should this method return old codepage?
     */
    return Qnil;
}

/*
 * Document-class: WIN32OLE
 *
 *   <code>WIN32OLE</code> objects represent OLE Automation object in Ruby.
 */

/*
 *  call-seq:
 *     WIN32OLE.new(server, [host]) -> WIN32OLE object
 * 
 *  Returns a new WIN32OLE object(OLE Automation object).
 *  The first argument server specifies OLE Automation server.
 *  The first argument should be CLSID or PROGID.
 *  If second argument host specified, then returns OLE Automation 
 *  object on host. 
 *
 *      WIN32OLE.new('Excel.Application') # => Excel OLE Automation WIN32OLE object.
 *      WIN32OLE.new('{00024500-0000-0000-C000-000000000046}') # => Excel OLE Automation WIN32OLE object.
 */
static VALUE
fole_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE svr_name;
    VALUE host;
    VALUE others;
    HRESULT hr;
    CLSID   clsid;
    OLECHAR *pBuf;
    IDispatch *pDispatch;
    void *p;

    rb_secure(4);
    rb_call_super(0, 0);
    rb_scan_args(argc, argv, "11*", &svr_name, &host, &others);

    if (ruby_safe_level > 0 && OBJ_TAINTED(svr_name)) {
        rb_raise(rb_eSecurityError, "Insecure Object Creation - %s",
                 StringValuePtr(svr_name));
    }
    if (!NIL_P(host)) {
        if (ruby_safe_level > 0 && OBJ_TAINTED(host)) {
            rb_raise(rb_eSecurityError, "Insecure Object Creation - %s",
                     StringValuePtr(svr_name));
        }
        return ole_create_dcom(argc, argv, self);
    }

    /* get CLSID from OLE server name */
    pBuf  = ole_mb2wc(StringValuePtr(svr_name), -1);
    hr = CLSIDFromProgID(pBuf, &clsid);
    if(FAILED(hr)) {
        hr = CLSIDFromString(pBuf, &clsid);
    }
    SysFreeString(pBuf);
    if(FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "unknown OLE server: `%s'",
                  StringValuePtr(svr_name));
    }

    /* get IDispatch interface */
    hr = CoCreateInstance(&clsid, NULL, CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER,
                          &IID_IDispatch, &p);
    pDispatch = p;
    if(FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR,
                  "failed to create WIN32OLE object from `%s'",
                  StringValuePtr(svr_name));
    }

    ole_set_member(self, pDispatch);
    return self;
}

static VALUE
hash2named_arg(pair, pOp)
    VALUE pair;
    struct oleparam* pOp;
{
    unsigned int index, i;
    VALUE key, value;
    index = pOp->dp.cNamedArgs;

    /*-------------------------------------
      the data-type of key must be String
    ---------------------------------------*/
    key = rb_ary_entry(pair, 0);
    if(TYPE(key) != T_STRING) {
        /* clear name of dispatch parameters */
        for(i = 1; i < index + 1; i++) {
            SysFreeString(pOp->pNamedArgs[i]);
        }
        /* clear dispatch parameters */
        for(i = 0; i < index; i++ ) {
            VariantClear(&(pOp->dp.rgvarg[i]));
        }
        /* raise an exception */
        Check_Type(key, T_STRING);
    }

    /* pNamedArgs[0] is <method name>, so "index + 1" */
    pOp->pNamedArgs[index + 1] = ole_mb2wc(StringValuePtr(key), -1);

    value = rb_ary_entry(pair, 1);
    VariantInit(&(pOp->dp.rgvarg[index]));
    ole_val2variant(value, &(pOp->dp.rgvarg[index]));

    pOp->dp.cNamedArgs += 1;
    return Qnil;
}

static VALUE
set_argv(realargs, beg, end)
    VARIANTARG* realargs;
    unsigned int beg, end;
{
    VALUE argv = rb_const_get(cWIN32OLE, rb_intern("ARGV"));

    Check_Type(argv, T_ARRAY);
    rb_ary_clear(argv);
    while (end-- > beg) {
        rb_ary_push(argv, ole_variant2val(&realargs[end]));
        VariantClear(&realargs[end]);
    }
    return argv;
}

static VALUE
ole_invoke(argc, argv, self, wFlags)
    int argc;
    VALUE *argv;
    VALUE self;
    USHORT wFlags;
{
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;
    struct oledata *pole;
    HRESULT hr;
    VALUE cmd;
    VALUE paramS;
    VALUE param;
    VALUE obj;
    VALUE v;

    BSTR wcmdname;

    DISPID DispID;
    DISPID* pDispID;
    EXCEPINFO excepinfo;
    VARIANT result;
    VARIANTARG* realargs = NULL;
    unsigned int argErr = 0;
    unsigned int i;
    unsigned int cNamedArgs;
    int n;
    struct oleparam op;
    memset(&excepinfo, 0, sizeof(EXCEPINFO));

    VariantInit(&result);

    op.dp.rgvarg = NULL;
    op.dp.rgdispidNamedArgs = NULL;
    op.dp.cNamedArgs = 0;
    op.dp.cArgs = 0;

    rb_scan_args(argc, argv, "1*", &cmd, &paramS);
    OLEData_Get_Struct(self, pole);
    if(!pole->pDispatch) {
        rb_raise(rb_eRuntimeError, "failed to get dispatch interface");
    }
    wcmdname = ole_mb2wc(StringValuePtr(cmd), -1);
    hr = pole->pDispatch->lpVtbl->GetIDsOfNames( pole->pDispatch, &IID_NULL,
                                                 &wcmdname, 1, lcid, &DispID);
    SysFreeString(wcmdname);
    if(FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "unknown property or method `%s'",
                  StringValuePtr(cmd));
    }

    /* pick up last argument of method */
    param = rb_ary_entry(paramS, argc-2);

    op.dp.cNamedArgs = 0;

    /* if last arg is hash object */
    if(TYPE(param) == T_HASH) {
        /*------------------------------------------ 
          hash object ==> named dispatch parameters 
        --------------------------------------------*/
        cNamedArgs = NUM2INT(rb_funcall(param, rb_intern("length"), 0));
        op.dp.cArgs = cNamedArgs + argc - 2;
        op.pNamedArgs = ALLOCA_N(OLECHAR*, cNamedArgs + 1);
        op.dp.rgvarg = ALLOCA_N(VARIANTARG, op.dp.cArgs);
        rb_iterate(rb_each, param, hash2named_arg, (VALUE)&op);

        pDispID = ALLOCA_N(DISPID, cNamedArgs + 1);
        op.pNamedArgs[0] = ole_mb2wc(StringValuePtr(cmd), -1);
        hr = pole->pDispatch->lpVtbl->GetIDsOfNames(pole->pDispatch,
                                                    &IID_NULL,
                                                    op.pNamedArgs,
                                                    op.dp.cNamedArgs + 1,
                                                    lcid, pDispID);
        for(i = 0; i < op.dp.cNamedArgs + 1; i++) {
            SysFreeString(op.pNamedArgs[i]);
            op.pNamedArgs[i] = NULL;
        }
        if(FAILED(hr)) {
            /* clear dispatch parameters */
            for(i = 0; i < op.dp.cArgs; i++ ) {
                VariantClear(&op.dp.rgvarg[i]);
            }
            ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                      "failed to get named argument info: `%s'",
                      StringValuePtr(cmd));
        }
        op.dp.rgdispidNamedArgs = &(pDispID[1]);
    }
    else {
        cNamedArgs = 0;
        op.dp.cArgs = argc - 1;
        op.pNamedArgs = ALLOCA_N(OLECHAR*, cNamedArgs + 1);
        if (op.dp.cArgs > 0) {
            op.dp.rgvarg  = ALLOCA_N(VARIANTARG, op.dp.cArgs);
        }
    }
    /*--------------------------------------
      non hash args ==> dispatch parameters 
     ----------------------------------------*/
    if(op.dp.cArgs > cNamedArgs) {
        realargs = ALLOCA_N(VARIANTARG, op.dp.cArgs-cNamedArgs+1);
        for(i = cNamedArgs; i < op.dp.cArgs; i++) {
            n = op.dp.cArgs - i + cNamedArgs - 1;
            VariantInit(&realargs[n]);
            VariantInit(&op.dp.rgvarg[n]);
            param = rb_ary_entry(paramS, i-cNamedArgs);
            
             ole_val2variant(param, &realargs[n]);
            V_VT(&op.dp.rgvarg[n]) = VT_VARIANT | VT_BYREF;
             V_VARIANTREF(&op.dp.rgvarg[n]) = &realargs[n];

        }
    }
    /* apparent you need to call propput, you need this */
    if (wFlags & DISPATCH_PROPERTYPUT) {
        if (op.dp.cArgs == 0)
            return ResultFromScode(E_INVALIDARG);

        op.dp.cNamedArgs = 1;
        op.dp.rgdispidNamedArgs = ALLOCA_N( DISPID, 1 );
        op.dp.rgdispidNamedArgs[0] = DISPID_PROPERTYPUT;
    }
    
    hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, DispID, 
                                         &IID_NULL, lcid, wFlags, &op.dp, 
                                         &result, &excepinfo, &argErr);
    if (FAILED(hr)) {
        /* retry to call args by value */
        if(op.dp.cArgs >= cNamedArgs) {
            for(i = cNamedArgs; i < op.dp.cArgs; i++) {
                n = op.dp.cArgs - i + cNamedArgs - 1;
                param = rb_ary_entry(paramS, i-cNamedArgs);
                ole_val2variant(param, &op.dp.rgvarg[n]);
            }
            if (hr == DISP_E_EXCEPTION) {
                ole_freeexceptinfo(&excepinfo);
            }
            memset(&excepinfo, 0, sizeof(EXCEPINFO));
            VariantInit(&result);
            hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, DispID, 
                                                 &IID_NULL, lcid, wFlags,
                                                 &op.dp, &result,
                                                 &excepinfo, &argErr);

            /* mega kludge. if a method in WORD is called and we ask
             * for a result when one is not returned then
             * hResult == DISP_E_EXCEPTION. this only happens on
             * functions whose DISPID > 0x8000 */
            if ((hr == DISP_E_EXCEPTION || hr == DISP_E_MEMBERNOTFOUND) && DispID > 0x8000) {
                if (hr == DISP_E_EXCEPTION) {
                    ole_freeexceptinfo(&excepinfo);
                }
                memset(&excepinfo, 0, sizeof(EXCEPINFO));
                hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, DispID, 
                        &IID_NULL, lcid, wFlags,
                        &op.dp, NULL,
                        &excepinfo, &argErr);
            }
            for(i = cNamedArgs; i < op.dp.cArgs; i++) {
                n = op.dp.cArgs - i + cNamedArgs - 1;
                VariantClear(&op.dp.rgvarg[n]);
            }
        }
        if (FAILED(hr)) {
            /* retry after converting nil to VT_EMPTY */
            if (op.dp.cArgs > cNamedArgs) {
                for(i = cNamedArgs; i < op.dp.cArgs; i++) {
                    n = op.dp.cArgs - i + cNamedArgs - 1;
                    param = rb_ary_entry(paramS, i-cNamedArgs);
                    ole_val2variant2(param, &op.dp.rgvarg[n]);
                }
                if (hr == DISP_E_EXCEPTION) {
                    ole_freeexceptinfo(&excepinfo);
                }
                memset(&excepinfo, 0, sizeof(EXCEPINFO));
                VariantInit(&result);
                hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, DispID, 
                        &IID_NULL, lcid, wFlags,
                        &op.dp, &result,
                        &excepinfo, &argErr);
                for(i = cNamedArgs; i < op.dp.cArgs; i++) {
                    n = op.dp.cArgs - i + cNamedArgs - 1;
                    VariantClear(&op.dp.rgvarg[n]);
                }
            }
        }

    }
    /* clear dispatch parameter */
    if(op.dp.cArgs > cNamedArgs) {
        set_argv(realargs, cNamedArgs, op.dp.cArgs);
    }
    else {
        for(i = 0; i < op.dp.cArgs; i++) {
            VariantClear(&op.dp.rgvarg[i]);
        }
    }

    if (FAILED(hr)) {
        v = ole_excepinfo2msg(&excepinfo);
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "%s%s",
                  StringValuePtr(cmd), StringValuePtr(v));
    }
    obj = ole_variant2val(&result);
    VariantClear(&result);
    return obj;
}

/*
 *  call-seq:
 *     WIN32OLE#invoke(method, [arg1,...])  => return value of method.
 *
 *  Runs OLE method. 
 *  The first argument specifies the method name of OLE Automation object.
 *  The others specify argument of the <i>method</i>.
 *  If you can not execute <i>method</i> directly, then use this method instead.
 *
 *    excel = WIN32OLE.new('Excel.Application')
 *    excel.invoke('Quit')  # => same as excel.Quit
 *
 */
static VALUE
fole_invoke(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    return ole_invoke(argc, argv, self, DISPATCH_METHOD|DISPATCH_PROPERTYGET);
}

static VALUE
ole_invoke2(self, dispid, args, types, dispkind)
    VALUE self;
    VALUE dispid;
    VALUE args;
    VALUE types;
    USHORT dispkind;
{
    HRESULT hr;
    struct oledata *pole;
    unsigned int argErr = 0;
    EXCEPINFO excepinfo;
    VARIANT result;
    DISPPARAMS dispParams;
    VARIANTARG* realargs = NULL;
    int i, j;
    VALUE obj = Qnil;
    VALUE tp, param;
    VALUE v;
    VARTYPE vt;

    Check_Type(args, T_ARRAY);
    Check_Type(types, T_ARRAY);
    
    memset(&excepinfo, 0, sizeof(EXCEPINFO));
    memset(&dispParams, 0, sizeof(DISPPARAMS));
    VariantInit(&result);
    OLEData_Get_Struct(self, pole);

    dispParams.cArgs = RARRAY(args)->len;
    dispParams.rgvarg = ALLOCA_N(VARIANTARG, dispParams.cArgs);
    realargs = ALLOCA_N(VARIANTARG, dispParams.cArgs);
    for (i = 0, j = dispParams.cArgs - 1; i < (int)dispParams.cArgs; i++, j--)
    {
        VariantInit(&realargs[i]);
        VariantInit(&dispParams.rgvarg[i]);
        tp = rb_ary_entry(types, j);
        vt = (VARTYPE)FIX2INT(tp);
        V_VT(&dispParams.rgvarg[i]) = vt;
        param = rb_ary_entry(args, j);
        if (param == Qnil)
        {

            V_VT(&dispParams.rgvarg[i]) = V_VT(&realargs[i]) = VT_ERROR;
            V_ERROR(&dispParams.rgvarg[i]) = V_ERROR(&realargs[i]) = DISP_E_PARAMNOTFOUND;
        }
        else
        {
            if (vt & VT_ARRAY)
            {
                int ent;
                LPBYTE pb;
                short* ps;
                LPLONG pl;
                VARIANT* pv;
                CY *py;
                VARTYPE v;
                SAFEARRAYBOUND rgsabound[1];
                Check_Type(param, T_ARRAY);
                rgsabound[0].lLbound = 0;
                rgsabound[0].cElements = RARRAY(param)->len;
                v = vt & ~(VT_ARRAY | VT_BYREF);
                V_ARRAY(&realargs[i]) = SafeArrayCreate(v, 1, rgsabound);
                V_VT(&realargs[i]) = VT_ARRAY | v;
                SafeArrayLock(V_ARRAY(&realargs[i]));
                pb = V_ARRAY(&realargs[i])->pvData;
                ps = V_ARRAY(&realargs[i])->pvData;
                pl = V_ARRAY(&realargs[i])->pvData;
                py = V_ARRAY(&realargs[i])->pvData;
                pv = V_ARRAY(&realargs[i])->pvData;
                for (ent = 0; ent < (int)rgsabound[0].cElements; ent++)
                {
                    VARIANT velem;
                    VALUE elem = rb_ary_entry(param, ent);
                    ole_val2variant(elem, &velem);
                    if (v != VT_VARIANT)
                    {
                        VariantChangeTypeEx(&velem, &velem,
                            LOCALE_SYSTEM_DEFAULT, 0, v);
                    }
                    switch (v)
                    {
                    /* 128 bits */
                    case VT_VARIANT:
                        *pv++ = velem;
                        break;
                    /* 64 bits */
                    case VT_R8:
                    case VT_CY:
                    case VT_DATE:
                        *py++ = V_CY(&velem);
                        break;
                    /* 16 bits */
                    case VT_BOOL:
                    case VT_I2:
                    case VT_UI2:
                        *ps++ = V_I2(&velem);
                        break;
                    /* 8 bites */
                    case VT_UI1:
                    case VT_I1:
                        *pb++ = V_UI1(&velem);
                        break;
                    /* 32 bits */
                    default:
                        *pl++ = V_I4(&velem);
                        break;
                    }
                }
                SafeArrayUnlock(V_ARRAY(&realargs[i]));
            }
            else
            {
                ole_val2variant(param, &realargs[i]);
                if ((vt & (~VT_BYREF)) != VT_VARIANT)
                {
                    hr = VariantChangeTypeEx(&realargs[i], &realargs[i],
                                             LOCALE_SYSTEM_DEFAULT, 0,
                                             (VARTYPE)(vt & (~VT_BYREF)));
                    if (hr != S_OK)
                    {
                        rb_raise(rb_eTypeError, "not valid value");
                    }
                }
            }
            if ((vt & VT_BYREF) || vt == VT_VARIANT)
            {
                if (vt == VT_VARIANT)
                    V_VT(&dispParams.rgvarg[i]) = VT_VARIANT | VT_BYREF;
                switch (vt & (~VT_BYREF))
                {
                /* 128 bits */
                case VT_VARIANT:
                    V_VARIANTREF(&dispParams.rgvarg[i]) = &realargs[i];
                    break;
                /* 64 bits */
                case VT_R8:
                case VT_CY:
                case VT_DATE:
                    V_CYREF(&dispParams.rgvarg[i]) = &V_CY(&realargs[i]);
                    break;
                /* 16 bits */
                case VT_BOOL:
                case VT_I2:
                case VT_UI2:
                    V_I2REF(&dispParams.rgvarg[i]) = &V_I2(&realargs[i]);
                    break;
                /* 8 bites */
                case VT_UI1:
                case VT_I1:
                    V_UI1REF(&dispParams.rgvarg[i]) = &V_UI1(&realargs[i]);
                    break;
                /* 32 bits */
                default:
                    V_I4REF(&dispParams.rgvarg[i]) = &V_I4(&realargs[i]);
                    break;
                }
            }
            else
            {
                /* copy 64 bits of data */
                V_CY(&dispParams.rgvarg[i]) = V_CY(&realargs[i]);
            }
        }
    }

    if (dispkind & DISPATCH_PROPERTYPUT) {
        dispParams.cNamedArgs = 1;
        dispParams.rgdispidNamedArgs = ALLOCA_N( DISPID, 1 );
        dispParams.rgdispidNamedArgs[0] = DISPID_PROPERTYPUT;
    }

    hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, NUM2INT(dispid),
                                         &IID_NULL, LOCALE_SYSTEM_DEFAULT,
                                         dispkind,
                                         &dispParams, &result,
                                         &excepinfo, &argErr);

    if (FAILED(hr)) {
        v = ole_excepinfo2msg(&excepinfo);
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "_invoke %s",
                  StringValuePtr(v));
    }

    /* clear dispatch parameter */
    if(dispParams.cArgs > 0) {
        set_argv(realargs, 0, dispParams.cArgs);
    }

    obj = ole_variant2val(&result);
    VariantClear(&result);
    return obj;
}

/*
 *   call-seq:
 *      WIN32OLE#_invoke(dispid, args, types)
 * 
 *   Runs the early binding method.
 *   The 1st argument specifies dispatch ID, 
 *   the 2nd argument specifies the array of arguments,
 *   the 3rd argument specifies the array of the type of arguments.
 *
 *      excel = WIN32OLE.new('Excel.Application')
 *      excel._invoke(302, [], []) #  same effect as excel.Quit
 */
static VALUE
fole_invoke2(self, dispid, args, types)
    VALUE self;
    VALUE dispid;
    VALUE args;
    VALUE types;
{
    return ole_invoke2(self, dispid, args, types, DISPATCH_METHOD);
}

/*
 *  call-seq:
 *     WIN32OLE#_getproperty(dispid, args, types)
 * 
 *  Runs the early binding method to get property.
 *  The 1st argument specifies dispatch ID, 
 *  the 2nd argument specifies the array of arguments,
 *  the 3rd argument specifies the array of the type of arguments.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     puts excel._getproperty(558, [], []) # same effect as puts excel.visible
 */
static VALUE
fole_getproperty2(self, dispid, args, types)
    VALUE self;
    VALUE dispid;
    VALUE args;
    VALUE types;
{
    return ole_invoke2(self, dispid, args, types, DISPATCH_PROPERTYGET);
}

/*
 *   call-seq:
 *      WIN32OLE#_setproperty(dispid, args, types)
 * 
 *   Runs the early binding method to set property.
 *   The 1st argument specifies dispatch ID, 
 *   the 2nd argument specifies the array of arguments,
 *   the 3rd argument specifies the array of the type of arguments.
 *
 *      excel = WIN32OLE.new('Excel.Application')
 *      excel._setproperty(558, [true], [WIN32OLE::VARIANT::VT_BOOL]) # same effect as excel.visible = true
 */
static VALUE
fole_setproperty2(self, dispid, args, types)
    VALUE self;
    VALUE dispid;
    VALUE args;
    VALUE types;
{
    return ole_invoke2(self, dispid, args, types, DISPATCH_PROPERTYPUT);
}

/*
 *  call-seq:
 *     WIN32OLE['property']=val 
 *     WIN32OLE.setproperty('property', [arg1, arg2,...] val)
 * 
 *  Sets property of OLE object.
 *  When you want to set property with argument, you can use this method.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     excel['Visible'] = true
 *     book = excel.workbooks.add
 *     sheet = book.worksheets(1)
 *     sheet.setproperty('Cells', 1, 2, 10) # => The B1 cell value is 10.
 */
static VALUE
fole_setproperty(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    return ole_invoke(argc, argv, self, DISPATCH_PROPERTYPUT);
}

/*
 *  call-seq:
 *     WIN32OLE['property'] 
 * 
 *  Returns property of OLE object.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     puts excel['Visible'] # => false
 */
static VALUE
fole_getproperty(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    return ole_invoke(argc, argv, self, DISPATCH_PROPERTYGET);
}

static VALUE
ole_propertyput(self, property, value)
    VALUE self, property, value;
{
    struct oledata *pole;
    unsigned argErr;
    unsigned int index;
    HRESULT hr;
    EXCEPINFO excepinfo;
    DISPID dispID = DISPID_VALUE;
    DISPID dispIDParam = DISPID_PROPERTYPUT;
    USHORT wFlags = DISPATCH_PROPERTYPUT|DISPATCH_PROPERTYPUTREF;
    DISPPARAMS dispParams;
    VARIANTARG propertyValue[2];
    OLECHAR* pBuf[1];
    VALUE v;
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;
    dispParams.rgdispidNamedArgs = &dispIDParam;
    dispParams.rgvarg = propertyValue;
    dispParams.cNamedArgs = 1;
    dispParams.cArgs = 1;

    VariantInit(&propertyValue[0]);
    VariantInit(&propertyValue[1]);
    memset(&excepinfo, 0, sizeof(excepinfo));

    OLEData_Get_Struct(self, pole);

    /* get ID from property name */
    pBuf[0]  = ole_mb2wc(StringValuePtr(property), -1);
    hr = pole->pDispatch->lpVtbl->GetIDsOfNames(pole->pDispatch, &IID_NULL,
                                                pBuf, 1, lcid, &dispID);
    SysFreeString(pBuf[0]);
    pBuf[0] = NULL;

    if(FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, 
                  "unknown property or method: `%s'",
                  StringValuePtr(property));
    }
    /* set property value */
    ole_val2variant(value, &propertyValue[0]);
    hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, dispID, &IID_NULL, 
                                         lcid, wFlags, &dispParams,
                                         NULL, &excepinfo, &argErr);

    for(index = 0; index < dispParams.cArgs; ++index) {
        VariantClear(&propertyValue[index]);
    }
    if (FAILED(hr)) {
        v = ole_excepinfo2msg(&excepinfo);
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, StringValuePtr(v));
    }
    return Qnil;
}

/*
 *  call-seq:
 *     WIN32OLE#ole_free
 *
 *  invokes Release method of Dispatch interface of WIN32OLE object.
 *  Usually, you do not need to call this method because Release method
 *  called automatically when WIN32OLE object garbaged.
 *
 */
static VALUE
fole_free(self)
    VALUE self;
{
    struct oledata *pole;
    rb_secure(4);
    OLEData_Get_Struct(self, pole);
    OLE_FREE(pole->pDispatch);
    pole->pDispatch = NULL;
    return Qnil;
}

static VALUE
ole_each_sub(pEnumV)
    VALUE pEnumV;
{
    VARIANT variant;
    VALUE obj = Qnil;
    IEnumVARIANT *pEnum = (IEnumVARIANT *)pEnumV;
    VariantInit(&variant);
    while(pEnum->lpVtbl->Next(pEnum, 1, &variant, NULL) == S_OK) {
        obj = ole_variant2val(&variant);
        VariantClear(&variant);
        VariantInit(&variant);
        rb_yield(obj);
    }
    return Qnil;
}

static VALUE
ole_ienum_free(pEnumV)
    VALUE pEnumV;
{
    IEnumVARIANT *pEnum = (IEnumVARIANT *)pEnumV;
    OLE_RELEASE(pEnum);
    return Qnil;
}

/*
 *  call-seq:
 *     WIN32OLE#each {|i|...}
 * 
 *  Iterates over each item of OLE collection which has IEnumVARIANT interface.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     book = excel.workbooks.add
 *     sheets = book.worksheets(1)
 *     cells = sheets.cells("A1:A5")
 *     cells.each do |cell|
 *       cell.value = 10
 *     end
 */
static VALUE
fole_each(self)
    VALUE self;
{
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;

    struct oledata *pole;

    unsigned int argErr;
    EXCEPINFO excepinfo;
    DISPPARAMS dispParams;
    VARIANT result;
    HRESULT hr;
    IEnumVARIANT *pEnum = NULL;
    void *p;

    VariantInit(&result);
    dispParams.rgvarg = NULL;
    dispParams.rgdispidNamedArgs = NULL;
    dispParams.cNamedArgs = 0;
    dispParams.cArgs = 0;
    memset(&excepinfo, 0, sizeof(excepinfo));
    
    OLEData_Get_Struct(self, pole);
    hr = pole->pDispatch->lpVtbl->Invoke(pole->pDispatch, DISPID_NEWENUM,
                                         &IID_NULL, lcid,
                                         DISPATCH_METHOD | DISPATCH_PROPERTYGET,
                                         &dispParams, &result,
                                         &excepinfo, &argErr);

    if (FAILED(hr)) {
        VariantClear(&result);
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to get IEnum Interface");
    }

    if (V_VT(&result) == VT_UNKNOWN) {
        hr = V_UNKNOWN(&result)->lpVtbl->QueryInterface(V_UNKNOWN(&result),
                                                        &IID_IEnumVARIANT,
                                                        &p);
        pEnum = p;
    } else if (V_VT(&result) == VT_DISPATCH) {
        hr = V_DISPATCH(&result)->lpVtbl->QueryInterface(V_DISPATCH(&result),
                                                         &IID_IEnumVARIANT,
                                                         &p);
        pEnum = p;
    }
    if (FAILED(hr) || !pEnum) {
        VariantClear(&result);
        ole_raise(hr, rb_eRuntimeError, "failed to get IEnum Interface");
    }

    VariantClear(&result);
    rb_ensure(ole_each_sub, (VALUE)pEnum, ole_ienum_free, (VALUE)pEnum);
    return Qnil;
}

/*
 *  call-seq:
 *     WIN32OLE#method_missing(id [,arg1, arg2, ...])
 * 
 *  Calls WIN32OLE#invoke method.
 */
static VALUE
fole_missing(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    ID id;
    char* mname;
    int n;
    id = rb_to_id(argv[0]);
    mname = rb_id2name(id);
    if(!mname) {
        rb_raise(rb_eRuntimeError, "fail: unknown method or property");
    }
    n = strlen(mname);
    if(mname[n-1] == '=') {
        argv[0] = rb_str_new(mname, n-1);

        return ole_propertyput(self, argv[0], argv[1]);
    }
    else {
        argv[0] = rb_str_new2(mname);
        return ole_invoke(argc, argv, self, DISPATCH_METHOD|DISPATCH_PROPERTYGET);
    }
}

static VALUE
ole_method_sub(self, pOwnerTypeInfo, pTypeInfo, name)
    VALUE self;
    ITypeInfo *pOwnerTypeInfo;
    ITypeInfo *pTypeInfo;
    VALUE name;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    BSTR bstr;
    FUNCDESC *pFuncDesc;
    WORD i;
    VALUE fname;
    VALUE method = Qnil;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    }
    for(i = 0; i < pTypeAttr->cFuncs && method == Qnil; i++) {
        hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, i, &pFuncDesc);
        if (FAILED(hr))
             continue;

        hr = pTypeInfo->lpVtbl->GetDocumentation(pTypeInfo, pFuncDesc->memid,
                                                 &bstr, NULL, NULL, NULL);
        if (FAILED(hr)) {
            pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
            continue;
        }
        fname = WC2VSTR(bstr);
        if (strcasecmp(StringValuePtr(name), StringValuePtr(fname)) == 0) {
            olemethod_set_member(self, pTypeInfo, pOwnerTypeInfo, i, fname);
            method = self;
        }
        pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
        pFuncDesc=NULL;
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return method;
}

static VALUE
olemethod_from_typeinfo(self, pTypeInfo, name)
    VALUE self;
    ITypeInfo *pTypeInfo;
    VALUE name;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    WORD i;
    HREFTYPE href;
    ITypeInfo *pRefTypeInfo;
    VALUE method = Qnil;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    }
    method = ole_method_sub(self, 0, pTypeInfo, name);
    if (method != Qnil) {
       return method;
    }
    for(i=0; i < pTypeAttr->cImplTypes && method == Qnil; i++){
       hr = pTypeInfo->lpVtbl->GetRefTypeOfImplType(pTypeInfo, i, &href);
       if(FAILED(hr))
           continue;
       hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo, href, &pRefTypeInfo);
       if (FAILED(hr))
           continue;
       method = ole_method_sub(self, pTypeInfo, pRefTypeInfo, name);
       OLE_RELEASE(pRefTypeInfo);
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return method;
}

static VALUE
ole_methods_sub(pOwnerTypeInfo, pTypeInfo, methods, mask)
    ITypeInfo *pOwnerTypeInfo;
    ITypeInfo *pTypeInfo;
    VALUE     methods;
    int       mask;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    BSTR bstr;
    char *pstr;
    FUNCDESC *pFuncDesc;
    VALUE method;
    WORD i;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    }
    for(i = 0; i < pTypeAttr->cFuncs; i++) {
        pstr = NULL;
        hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, i, &pFuncDesc);
        if (FAILED(hr))
             continue;
                 
        hr = pTypeInfo->lpVtbl->GetDocumentation(pTypeInfo, pFuncDesc->memid,
                                                 &bstr, NULL, NULL, NULL);
        if (FAILED(hr)) {
            pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
            continue;
        }
        if(pFuncDesc->invkind & mask) {
            method = folemethod_s_allocate(cWIN32OLE_METHOD);
            olemethod_set_member(method, pTypeInfo, pOwnerTypeInfo, 
                                 i, WC2VSTR(bstr));
            rb_ary_push(methods, method);
        }
        pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
        pFuncDesc=NULL;
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);

    return methods;
}

static VALUE
ole_methods_from_typeinfo(pTypeInfo, mask)
    ITypeInfo *pTypeInfo;
    int mask;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    WORD i;
    HREFTYPE href;
    ITypeInfo *pRefTypeInfo;
    VALUE methods = rb_ary_new();
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    }

    ole_methods_sub(0, pTypeInfo, methods, mask);
    for(i=0; i < pTypeAttr->cImplTypes; i++){
       hr = pTypeInfo->lpVtbl->GetRefTypeOfImplType(pTypeInfo, i, &href);
       if(FAILED(hr))
           continue;
       hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo, href, &pRefTypeInfo);
       if (FAILED(hr))
           continue;
       ole_methods_sub(pTypeInfo, pRefTypeInfo, methods, mask);
       OLE_RELEASE(pRefTypeInfo);
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return methods;
}

static HRESULT
typeinfo_from_ole(pole, ppti)
    struct oledata *pole;
    ITypeInfo **ppti;
{
    ITypeInfo *pTypeInfo;
    ITypeLib *pTypeLib;
    BSTR bstr;
    VALUE type;
    UINT i;
    UINT count;
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;
    HRESULT hr = pole->pDispatch->lpVtbl->GetTypeInfo(pole->pDispatch,
                                                      0, lcid, &pTypeInfo);
    if(FAILED(hr)) {
        ole_raise(hr, rb_eRuntimeError, "failed to GetTypeInfo");
    }
    hr = pTypeInfo->lpVtbl->GetDocumentation(pTypeInfo,
                                             -1,
                                             &bstr,
                                             NULL, NULL, NULL);
    type = WC2VSTR(bstr);
    hr = pTypeInfo->lpVtbl->GetContainingTypeLib(pTypeInfo, &pTypeLib, &i);
    OLE_RELEASE(pTypeInfo);
    if (FAILED(hr)) {
        ole_raise(hr, rb_eRuntimeError, "failed to GetContainingTypeLib");
    }
    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (i = 0; i < count; i++) {
        hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, i,
                                                &bstr, NULL, NULL, NULL);
        if (SUCCEEDED(hr) && rb_str_cmp(WC2VSTR(bstr), type) == 0) {
            hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib, i, &pTypeInfo);
            if (SUCCEEDED(hr)) {
                *ppti = pTypeInfo;
                break;
            }
        }
    }
    OLE_RELEASE(pTypeLib);
    return hr;
}

static VALUE
ole_methods(self,mask)
    VALUE self;
    int mask;
{
    ITypeInfo *pTypeInfo;
    HRESULT hr;
    VALUE methods;
    struct oledata *pole;

    OLEData_Get_Struct(self, pole);
    methods = rb_ary_new();

    hr = typeinfo_from_ole(pole, &pTypeInfo);
    if(FAILED(hr))
        return methods;
    rb_ary_concat(methods, ole_methods_from_typeinfo(pTypeInfo, mask));
    OLE_RELEASE(pTypeInfo);
    return methods;
}

/*
 *  call-seq:
 *     WIN32OLE#ole_methods
 * 
 *  Returns the array of WIN32OLE_METHOD object. 
 *  The element is OLE method of WIN32OLE object.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     methods = excel.ole_methods
 *     
 */
static VALUE
fole_methods( self )
    VALUE self;
{
    return ole_methods( self, INVOKE_FUNC | INVOKE_PROPERTYGET | INVOKE_PROPERTYPUT | INVOKE_PROPERTYPUTREF);
}

/*
 *  call-seq:
 *     WIN32OLE#ole_get_methods
 * 
 *  Returns the array of WIN32OLE_METHOD object .
 *  The element of the array is property (gettable) of WIN32OLE object.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     properties = excel.ole_get_methods
 */
static VALUE
fole_get_methods( self )
    VALUE self;
{
    return ole_methods( self, INVOKE_PROPERTYGET);
}

/*
 *  call-seq:
 *     WIN32OLE#ole_put_methods
 * 
 *  Returns the array of WIN32OLE_METHOD object .
 *  The element of the array is property (settable) of WIN32OLE object.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     properties = excel.ole_put_methods
 */
static VALUE
fole_put_methods( self )
    VALUE self;
{
    return ole_methods( self, INVOKE_PROPERTYPUT | INVOKE_PROPERTYPUTREF);
}

/*
 *  call-seq:
 *     WIN32OLE#ole_func_methods
 * 
 *  Returns the array of WIN32OLE_METHOD object .
 *  The element of the array is functional method of WIN32OLE object.
 *
 *     excel = WIN32OLE.new('Excel.Application')
 *     properties = excel.ole_func_methods
 *
 */
static VALUE
fole_func_methods( self )
    VALUE self;
{
    return ole_methods( self, INVOKE_FUNC);
}

/*
 *   call-seq:
 *      WIN32OLE#ole_obj_help
 * 
 *   Returns WIN32OLE_TYPE object.
 *
 *      excel = WIN32OLE.new('Excel.Application')
 *      tobj = excel.ole_obj_help
 */
static VALUE
fole_obj_help( self )
    VALUE self;
{
    unsigned int index;
    ITypeInfo *pTypeInfo;
    ITypeLib *pTypeLib;
    HRESULT hr;
    struct oledata *pole;
    BSTR bstr;
    LCID  lcid = LOCALE_SYSTEM_DEFAULT;
    VALUE type = Qnil;

    OLEData_Get_Struct(self, pole);

    hr = pole->pDispatch->lpVtbl->GetTypeInfo( pole->pDispatch, 0, lcid, &pTypeInfo );
    if(FAILED(hr)) {
        ole_raise(hr, rb_eRuntimeError, "failed to GetTypeInfo");
    }
    hr = pTypeInfo->lpVtbl->GetContainingTypeLib( pTypeInfo, &pTypeLib, &index );
    if(FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        ole_raise(hr, rb_eRuntimeError, "failed to GetContainingTypeLib");
    }
    hr = pTypeLib->lpVtbl->GetDocumentation( pTypeLib, index,
                                             &bstr, NULL, NULL, NULL);
    if (SUCCEEDED(hr)) {
        type = foletype_s_allocate(cWIN32OLE_TYPE);
        oletype_set_member(type, pTypeInfo, WC2VSTR(bstr));
    }
    OLE_RELEASE(pTypeLib);
    OLE_RELEASE(pTypeInfo);

    return type;
}

static HRESULT
ole_docinfo_from_type(pTypeInfo, name, helpstr, helpcontext, helpfile)
    ITypeInfo *pTypeInfo;
    BSTR *name;
    BSTR *helpstr; 
    DWORD *helpcontext;
    BSTR *helpfile;
{
    HRESULT hr;
    ITypeLib *pTypeLib;
    UINT i;

    hr = pTypeInfo->lpVtbl->GetContainingTypeLib(pTypeInfo, &pTypeLib, &i);
    if (FAILED(hr)) {
        return hr;
    }
    
    hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, i,
                                            name, helpstr, 
                                            helpcontext, helpfile);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeLib);
        return hr;
    }
    OLE_RELEASE(pTypeLib);
    return hr;
}

static VALUE
ole_usertype2val(pTypeInfo, pTypeDesc, typedetails)
    ITypeInfo *pTypeInfo;
    TYPEDESC *pTypeDesc;
    VALUE typedetails;
{
    HRESULT hr;
    BSTR bstr;
    ITypeInfo *pRefTypeInfo;
    VALUE type = Qnil;

    hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo, 
                                           V_UNION1(pTypeDesc, hreftype),
                                           &pRefTypeInfo);
    if(FAILED(hr))
        return Qnil;
    hr = ole_docinfo_from_type(pRefTypeInfo, &bstr, NULL, NULL, NULL);
    if(FAILED(hr)) {
        OLE_RELEASE(pRefTypeInfo);
        return Qnil;
    }
    OLE_RELEASE(pRefTypeInfo);
    type = WC2VSTR(bstr);
    if(typedetails != Qnil)
        rb_ary_push(typedetails, type);
    return type;
}

static VALUE ole_typedesc2val();
static VALUE
ole_ptrtype2val(pTypeInfo, pTypeDesc, typedetails) 
    ITypeInfo *pTypeInfo;
    TYPEDESC *pTypeDesc;
    VALUE typedetails;
{    
    TYPEDESC *p = pTypeDesc;
    VALUE type = rb_str_new2("");
    while(p->vt == VT_PTR || p->vt == VT_SAFEARRAY) {
        p = V_UNION1(p, lptdesc);
        if(strlen(StringValuePtr(type)) == 0) {
           type = ole_typedesc2val(pTypeInfo, p, typedetails);
        } else {
           rb_str_cat(type, ",", 1);
           rb_str_concat(type, ole_typedesc2val(pTypeInfo, p, typedetails));
        }
    }
    return type;
}

static VALUE
ole_typedesc2val(pTypeInfo, pTypeDesc, typedetails)
    ITypeInfo *pTypeInfo;
    TYPEDESC *pTypeDesc;
    VALUE typedetails;
{
    VALUE str;
    switch(pTypeDesc->vt) {
    case VT_I2:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("I2"));
        return rb_str_new2("I2");
    case VT_I4:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("I4"));
        return rb_str_new2("I4");
    case VT_R4:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("R4"));
        return rb_str_new2("R4");
    case VT_R8:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("R8"));
        return rb_str_new2("R8");
    case VT_CY:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("CY"));
        return rb_str_new2("CY");
    case VT_DATE:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("DATE"));
        return rb_str_new2("DATE");
    case VT_BSTR:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("BSTR"));
        return rb_str_new2("BSTR");
    case VT_BOOL:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("BOOL"));
        return rb_str_new2("BOOL");
    case VT_VARIANT:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("VARIANT"));
        return rb_str_new2("VARIANT");
    case VT_DECIMAL:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("DECIMAL"));
        return rb_str_new2("DECIMAL");
    case VT_I1:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("I1"));
        return rb_str_new2("I1");
    case VT_UI1:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("UI1"));
        return rb_str_new2("UI1");
    case VT_UI2:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("UI2"));
        return rb_str_new2("UI2");
    case VT_UI4:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("UI4"));
        return rb_str_new2("UI4");
    case VT_I8:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("I8"));
        return rb_str_new2("I8");
    case VT_UI8:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("UI8"));
        return rb_str_new2("UI8");
    case VT_INT:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("INT"));
        return rb_str_new2("INT");
    case VT_UINT:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("UINT"));
        return rb_str_new2("UINT");
    case VT_VOID:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("VOID"));
        return rb_str_new2("VOID");
    case VT_HRESULT:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("HRESULT"));
        return rb_str_new2("HRESULT");
    case VT_PTR:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("PTR"));
        return ole_ptrtype2val(pTypeInfo, pTypeDesc, typedetails);
    case VT_SAFEARRAY:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("SAFEARRAY"));
        return ole_ptrtype2val(pTypeInfo, pTypeDesc, typedetails);
    case VT_CARRAY:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("CARRAY"));
        return rb_str_new2("CARRAY");
    case VT_USERDEFINED:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("USERDEFINED"));
        str = ole_usertype2val(pTypeInfo, pTypeDesc, typedetails);
        if (str != Qnil) {
            return str;
        }
        return rb_str_new2("USERDEFINED");
    case VT_UNKNOWN:
        return rb_str_new2("UNKNOWN");
    case VT_DISPATCH:
        if(typedetails != Qnil)
            rb_ary_push(typedetails, rb_str_new2("DISPATCH"));
        return rb_str_new2("DISPATCH");
    default:
        str = rb_str_new2("Unknown Type ");
        rb_str_concat(str, rb_fix2str(INT2FIX(pTypeDesc->vt), 10));
        return str;
    }
}

/*
 *   call-seq:
 *      WIN32OLE#ole_method_help(method)
 * 
 *   Returns WIN32OLE_METHOD object corresponding with method 
 *   specified by 1st argument.
 *
 *      excel = WIN32OLE.new('Excel.Application')
 *      method = excel.ole_method_help('Quit')
 *
 */
static VALUE
fole_method_help( self, cmdname )
    VALUE self;
    VALUE cmdname;
{
    ITypeInfo *pTypeInfo;
    HRESULT hr;
    struct oledata *pole;
    VALUE method, obj;
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;

    Check_SafeStr(cmdname);
    OLEData_Get_Struct(self, pole);
    hr = typeinfo_from_ole(pole, &pTypeInfo);
    if(FAILED(hr))
        ole_raise(hr, rb_eRuntimeError, "failed to get ITypeInfo");
    method = folemethod_s_allocate(cWIN32OLE_METHOD);
    obj = olemethod_from_typeinfo(method, pTypeInfo, cmdname);
    OLE_RELEASE(pTypeInfo);
    if (obj == Qnil)
        rb_raise(eWIN32OLE_RUNTIME_ERROR, "not found %s",
                 StringValuePtr(cmdname));
    return obj;
}

/*
 *  call-seq:
 *     WIN32OLE#ole_activex_initialize() -> Qnil
 *
 *  Initialize WIN32OLE object(ActiveX Control) by calling 
 *  IPersistMemory::InitNew.
 *
 *  Before calling OLE method, some kind of the ActiveX controls 
 *  created with MFC should be initialized by calling 
 *  IPersistXXX::InitNew.
 *
 *  If and only if you recieved the exception "HRESULT error code:
 *  0x8000ffff catastrophic failure", try this method before
 *  invoking any ole_method.
 *
 *     obj = WIN32OLE.new("ProgID_or_GUID_of_ActiveX_Control")
 *     obj.ole_activex_initialize
 *     obj.method(...)
 *  
 */ 
static VALUE
fole_activex_initialize(self)
    VALUE self; 
{
    struct oledata *pole;
    IPersistMemory *pPersistMemory;
    void *p;

    HRESULT hr = S_OK;

    OLEData_Get_Struct(self, pole);

    hr = pole->pDispatch->lpVtbl->QueryInterface(pole->pDispatch, &IID_IPersistMemory, &p);
    pPersistMemory = p;
    if (SUCCEEDED(hr)) {
        hr = pPersistMemory->lpVtbl->InitNew(pPersistMemory);
        OLE_RELEASE(pPersistMemory);
        if (SUCCEEDED(hr)) {
            return Qnil;
        }
    }

    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "fail to initialize ActiveX control");
    }

    return Qnil;
}

/*
 *   call-seq:
 *      WIN32OLE_TYPE.ole_classes(typelib)
 * 
 *   Returns array of WIN32OLE_TYPE objects defined by the <i>typelib</i> type library.
 */
static VALUE
foletype_s_ole_classes(self, typelib)
    VALUE self;
    VALUE typelib;
{
    VALUE file, classes;
    OLECHAR * pbuf;
    ITypeLib *pTypeLib;
    HRESULT hr;

    rb_secure(4);
    classes = rb_ary_new();
    if(TYPE(typelib) == T_STRING) {
        file = typelib_file(typelib);
        if (file == Qnil) {
            file = typelib;
        }
        pbuf = ole_mb2wc(StringValuePtr(file), -1);
        hr = LoadTypeLibEx(pbuf, REGKIND_NONE, &pTypeLib);
        if (FAILED(hr))
          ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to LoadTypeLibEx");
        SysFreeString(pbuf);
        ole_classes_from_typelib(pTypeLib, classes);
        OLE_RELEASE(pTypeLib);
    } else {
        rb_raise(rb_eTypeError, "1st argument should be TypeLib string");
    }
    return classes;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE.typelibs
 * 
 *  Returns array of type libraries.
 *
 */
static VALUE
foletype_s_typelibs(self)
    VALUE self;
{
    HKEY htypelib, hclsid;
    double fversion;
    DWORD i, j;
    LONG err;
    VALUE clsid;
    VALUE ver;
    VALUE v = Qnil;
    VALUE typelibs = rb_ary_new();

    err = reg_open_key(HKEY_CLASSES_ROOT, "TypeLib", &htypelib);
    if(err != ERROR_SUCCESS) {
        return typelibs;
    }
    for(i = 0; ; i++) {
        clsid = reg_enum_key(htypelib, i);
        if (clsid == Qnil)
            break;
        err = reg_open_vkey(htypelib, clsid, &hclsid);
        if (err != ERROR_SUCCESS)
            continue;
        fversion = 0;
        for(j = 0; ; j++) {
            ver = reg_enum_key(hclsid, j);
            if (ver == Qnil)
                break;
            if (fversion > atof(StringValuePtr(ver)))
                continue;
            fversion = atof(StringValuePtr(ver));
            if ( (v = reg_get_val(hclsid, StringValuePtr(ver))) != Qnil ) {
                rb_ary_push(typelibs, v);
            }
        }
        RegCloseKey(hclsid);
    }
    RegCloseKey(htypelib);
    return typelibs;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE.progids
 * 
 *  Returns array of ProgID.
 */
static VALUE
foletype_s_progids(self)
    VALUE self;
{
    HKEY hclsids, hclsid;
    DWORD i;
    LONG err;
    VALUE clsid;
    VALUE v = rb_str_new2("");
    VALUE progids = rb_ary_new();

    err = reg_open_key(HKEY_CLASSES_ROOT, "CLSID", &hclsids);
    if(err != ERROR_SUCCESS) {
        return progids;
    }
    for(i = 0; ; i++) {
        clsid = reg_enum_key(hclsids, i);
        if (clsid == Qnil)
            break;
        err = reg_open_vkey(hclsids, clsid, &hclsid);
        if (err != ERROR_SUCCESS)
            continue;
        if ((v = reg_get_val(hclsid, "ProgID")) != Qnil) 
            rb_ary_push(progids, v);
        if ((v = reg_get_val(hclsid, "VersionIndependentProgID")) != Qnil)
            rb_ary_push(progids, v);
        RegCloseKey(hclsid);
    }
    RegCloseKey(hclsids);
    return progids;
}

static VALUE
foletype_s_allocate(klass)
    VALUE klass;
{
    struct oletypedata *poletype;
    VALUE obj;
    ole_initialize();
    obj = Data_Make_Struct(klass,struct oletypedata,0,oletype_free,poletype);
    poletype->pTypeInfo = NULL;
    return obj;
}

static VALUE
oletype_set_member(self, pTypeInfo, name)
    VALUE self;
    ITypeInfo *pTypeInfo;
    VALUE name;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    rb_ivar_set(self, rb_intern("name"), name);
    ptype->pTypeInfo = pTypeInfo;
    if(pTypeInfo) OLE_ADDREF(pTypeInfo);
    return self;
}

static VALUE
oleclass_from_typelib(self, pTypeLib, oleclass)
    VALUE self;
    ITypeLib *pTypeLib;
    VALUE oleclass;
{
    
    long count;
    int i;
    HRESULT hr;
    BSTR bstr;
    VALUE typelib;
    ITypeInfo *pTypeInfo;

    VALUE found = Qfalse;
  
    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (i = 0; i < count && found == Qfalse; i++) {
        hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib, i, &pTypeInfo);
        if (FAILED(hr))
            continue;
        hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, i,
                                                &bstr, NULL, NULL, NULL);
        if (FAILED(hr)) 
            continue;
        typelib = WC2VSTR(bstr);
        if (rb_str_cmp(oleclass, typelib) == 0) {
            oletype_set_member(self, pTypeInfo, typelib);
            found = Qtrue;
        }
        OLE_RELEASE(pTypeInfo);
    }
    return found;
}

/*
 * Document-class: WIN32OLE_TYPE
 *
 *   <code>WIN32OLE_TYPE</code> objects represent OLE type libarary information.
 */

/*
 *  call-seq:
 *     WIN32OLE_TYPE.new(typelib, ole_class) -> WIN32OLE_TYPE object
 *
 *  Returns a new WIN32OLE_TYPE object.
 *  The first argument <i>typelib</i> specifies OLE type library name.
 *  The second argument specifies OLE class name.
 *
 *      WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application') 
 *          # => WIN32OLE_TYPE object of Application class of Excel. 
 */
static VALUE
foletype_initialize(self, typelib, oleclass)
    VALUE self;
    VALUE typelib;
    VALUE oleclass;
{
    VALUE file;
    OLECHAR * pbuf;
    ITypeLib *pTypeLib;
    HRESULT hr;

    Check_SafeStr(oleclass);
    Check_SafeStr(typelib);
    file = typelib_file(typelib);
    if (file == Qnil) {
        file = typelib;
    }
    pbuf = ole_mb2wc(StringValuePtr(file), -1);
    hr = LoadTypeLibEx(pbuf, REGKIND_NONE, &pTypeLib);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to LoadTypeLibEx");
    SysFreeString(pbuf);
    if (oleclass_from_typelib(self, pTypeLib, oleclass) == Qfalse) {
        OLE_RELEASE(pTypeLib);
        rb_raise(eWIN32OLE_RUNTIME_ERROR, "not found `%s` in `%s`",
                 StringValuePtr(oleclass), StringValuePtr(typelib));
    }
    OLE_RELEASE(pTypeLib);
    return self;
}

/*
 * call-seq:
 *    WIN32OLE_TYPE#name #=> OLE type name
 *
 * Returns OLE type name.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application') 
 *    puts tobj.name  # => Application
 */
static VALUE
foletype_name(self)
    VALUE self;
{
    return rb_ivar_get(self, rb_intern("name"));
}

static VALUE
ole_ole_type(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    VALUE type = Qnil;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if(FAILED(hr)){
        return type;
    }
    switch(pTypeAttr->typekind) {
    case TKIND_ENUM:
        type = rb_str_new2("Enum");
        break;
    case TKIND_RECORD:
        type = rb_str_new2("Record");
        break;
    case TKIND_MODULE:
        type = rb_str_new2("Module");
        break;
    case TKIND_INTERFACE:
        type = rb_str_new2("Interface");
        break;
    case TKIND_DISPATCH:
        type = rb_str_new2("Dispatch");
        break;
    case TKIND_COCLASS:
        type = rb_str_new2("Class");
        break;
    case TKIND_ALIAS:
        type = rb_str_new2("Alias");
        break;
    case TKIND_UNION:
        type = rb_str_new2("Union");
        break;
    case TKIND_MAX:
        type = rb_str_new2("Max");
        break;
    default:
        type = Qnil;
        break;
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return type;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#ole_type #=> OLE type string.
 * 
 *  returns type of OLE class.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application') 
 *    puts tobj.ole_type  # => Class
 */
static VALUE
foletype_ole_type(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_ole_type(ptype->pTypeInfo);
}

static VALUE
ole_type_guid(pTypeInfo) 
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    int len;
    OLECHAR bstr[80];
    VALUE guid = Qnil;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) 
        return guid;
    len = StringFromGUID2(&pTypeAttr->guid, bstr, sizeof(bstr)/sizeof(OLECHAR));
    if (len > 3) {
        guid = ole_wc2vstr(bstr, FALSE);
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return guid;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#guid  #=> GUID
 * 
 *  Returns GUID.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application') 
 *    puts tobj.guid  # => {00024500-0000-0000-C000-000000000046}
 */
static VALUE
foletype_guid(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_guid(ptype->pTypeInfo);
}

static VALUE
ole_type_progid(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    OLECHAR *pbuf;
    VALUE progid = Qnil;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) 
        return progid;
    hr = ProgIDFromCLSID(&pTypeAttr->guid, &pbuf);
    if (SUCCEEDED(hr)) { 
        progid = ole_wc2vstr(pbuf, FALSE);
        CoTaskMemFree(pbuf);
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return progid;
}

/*
 * call-seq:
 *    WIN32OLE_TYPE#progid  #=> ProgID
 * 
 * Returns ProgID if it exists. If not found, then returns nil.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application')
 *    puts tobj.progid  # =>   Excel.Application.9
 */
static VALUE
foletype_progid(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_progid(ptype->pTypeInfo);
}


static VALUE
ole_type_visible(pTypeInfo) 
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    VALUE visible;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) 
        return Qtrue;
    if (pTypeAttr->wTypeFlags & (TYPEFLAG_FHIDDEN | TYPEFLAG_FRESTRICTED)) {
        visible = Qfalse;
    } else {
        visible = Qtrue;
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return visible;
}

/*
 *  call-seq:
 *    WIN32OLE_TYPE#visible  #=> true or false
 * 
 *  Returns true if the OLE class is public.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application')
 *    puts tobj.visible  # => true
 */
static VALUE
foletype_visible(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_visible(ptype->pTypeInfo);
}

static VALUE
ole_type_major_version(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    VALUE ver;
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    ver = INT2FIX(pTypeAttr->wMajorVerNum);
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return ver;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#major_version
 * 
 *  Returns major version.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Word 10.0 Object Library', 'Documents')
 *     puts tobj.major_version # => 8
 */
static VALUE
foletype_major_version(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_major_version(ptype->pTypeInfo);
}

static VALUE
ole_type_minor_version(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    VALUE ver;
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    ver = INT2FIX(pTypeAttr->wMinorVerNum);
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return ver;
}

/*
 *  call-seq:
 *    WIN32OLE_TYPE#minor_version #=> OLE minor version
 * 
 *  Returns minor version.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Word 10.0 Object Library', 'Documents')
 *     puts tobj.minor_version # => 2
 */
static VALUE
foletype_minor_version(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_minor_version(ptype->pTypeInfo);
}

static VALUE
ole_type_typekind(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    VALUE typekind;
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    typekind = INT2FIX(pTypeAttr->typekind);
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return typekind;
}

/*
 *  call-seq:
 *    WIN32OLE_TYPE#typekind #=> number of type.
 * 
 *  Returns number which represents type.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Word 10.0 Object Library', 'Documents')
 *    puts tobj.typekind # => 4
 *
 */
static VALUE 
foletype_typekind(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_typekind(ptype->pTypeInfo);
}

static VALUE
ole_type_helpstring(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    BSTR bhelpstr;
    hr = ole_docinfo_from_type(pTypeInfo, NULL, &bhelpstr, NULL, NULL);
    if(FAILED(hr)) {
        return Qnil;
    }
    return WC2VSTR(bhelpstr);
}

/*
 *  call-seq:
 *    WIN32OLE_TYPE#helpstring #=> help string.
 * 
 *  Returns help string.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Internet Controls', 'IWebBrowser')
 *    puts tobj.helpstring # => Web Browser interface
 */
static VALUE 
foletype_helpstring(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_helpstring(ptype->pTypeInfo);
}

static VALUE
ole_type_src_type(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    VALUE alias = Qnil;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        return alias;
    if(pTypeAttr->typekind != TKIND_ALIAS) {
        OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
        return alias;
    }
    alias = ole_typedesc2val(pTypeInfo, &(pTypeAttr->tdescAlias), Qnil);
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return alias;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#src_type #=> OLE source class
 * 
 *  Returns source class when the OLE class is 'Alias'.
 *     tobj =  WIN32OLE_TYPE.new('Microsoft Office 9.0 Object Library', 'MsoRGBType')
 *     puts tobj.src_type # => I4
 *
 */
static VALUE
foletype_src_type(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_src_type(ptype->pTypeInfo);
}

static VALUE
ole_type_helpfile(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    BSTR bhelpfile;
    hr = ole_docinfo_from_type(pTypeInfo, NULL, NULL, NULL, &bhelpfile);
    if(FAILED(hr)) {
        return Qnil;
    }
    return WC2VSTR(bhelpfile);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#helpfile
 * 
 *  Returns helpfile path. If helpfile is not found, then returns nil.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Worksheet')
 *     puts tobj.helpfile # => C:\...\VBAXL9.CHM
 *
 */
static VALUE
foletype_helpfile(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_helpfile(ptype->pTypeInfo);
}

static VALUE
ole_type_helpcontext(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    DWORD helpcontext;
    hr = ole_docinfo_from_type(pTypeInfo, NULL, NULL, 
                               &helpcontext, NULL);
    if(FAILED(hr))
        return Qnil;
    return INT2FIX(helpcontext);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#helpcontext
 * 
 *  Returns helpcontext. If helpcontext is not found, then returns nil.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Worksheet')
 *     puts tobj.helpfile # => 131185
 */
static VALUE
foletype_helpcontext(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_type_helpcontext(ptype->pTypeInfo);
}

static VALUE
ole_variables(pTypeInfo)
    ITypeInfo *pTypeInfo;
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    WORD i;
    UINT len;
    BSTR bstr;
    char *pstr;
    VARDESC *pVarDesc;
    struct olevariabledata *pvar;
    VALUE var;
    VALUE variables = rb_ary_new();
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetTypeAttr");
    }
    
    for(i = 0; i < pTypeAttr->cVars; i++) {
        hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, i, &pVarDesc);
        if(FAILED(hr))
            continue;
        len = 0;
        pstr = NULL;
        hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, pVarDesc->memid, &bstr,
                                         1, &len);
        if(FAILED(hr) || len == 0 || !bstr)
            continue;

        var = Data_Make_Struct(cWIN32OLE_VARIABLE, struct olevariabledata,
                               0,olevariable_free,pvar);
        pvar->pTypeInfo = pTypeInfo;
        OLE_ADDREF(pTypeInfo);
        pvar->index = i;
        rb_ivar_set(var, rb_intern("name"), WC2VSTR(bstr));
        rb_ary_push(variables, var);

        pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
        pVarDesc = NULL;
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return variables;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#variables
 * 
 *  Returns array of WIN32OLE_VARIABLE objects which represent variables 
 *  defined in OLE class.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *     vars = tobj.variables
 *     vars.each do |v|
 *       puts "#{v.name} = #{v.value}"
 *     end
 *     
 *     The result of above sample script is follows:
 *       xlChart = -4109
 *       xlDialogSheet = -4116
 *       xlExcel4IntlMacroSheet = 4
 *       xlExcel4MacroSheet = 3
 *       xlWorksheet = -4167
 *
 */
static VALUE
foletype_variables(self)
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_variables(ptype->pTypeInfo);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#ole_methods # the array of WIN32OLE_METHOD objects.
 * 
 *  Returns array of WIN32OLE_METHOD objects which represent OLE method defined in 
 *  OLE type library.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Worksheet')
 *    methods = tobj.ole_methods.collect{|m|
 *      m.name
 *    }                                       
 *    # => ['Activate', 'Copy', 'Delete',....]
 */
static VALUE
foletype_methods(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct oletypedata *ptype;
    Data_Get_Struct(self, struct oletypedata, ptype);
    return ole_methods_from_typeinfo(ptype->pTypeInfo, INVOKE_FUNC | INVOKE_PROPERTYGET | INVOKE_PROPERTYPUT | INVOKE_PROPERTYPUTREF);
}

/*
 * Document-class: WIN32OLE_VARIABLE
 *
 *   <code>WIN32OLE_VARIABLE</code> objects represent OLE variable information.
 */

/*
 *  call-seq:
 *     WIN32OLE_VARIABLE#name
 * 
 *  Returns the name of variable.
 *
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *     variables = tobj.variables
 *     variables.each do |variable|
 *       puts "#{variable.name}"
 *     end
 *
 *     The result of above script is following:
 *       xlChart
 *       xlDialogSheet
 *       xlExcel4IntlMacroSheet
 *       xlExcel4MacroSheet
 *       xlWorksheet
 *
 */
static VALUE
folevariable_name(self)
    VALUE self;
{
    return rb_ivar_get(self, rb_intern("name"));
}

static VALUE
ole_variable_ole_type(pTypeInfo, var_index)
    ITypeInfo *pTypeInfo;
    UINT var_index;
{
    VARDESC *pVarDesc;
    HRESULT hr;
    VALUE type;
    hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, var_index, &pVarDesc);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetVarDesc");
    type = ole_typedesc2val(pTypeInfo, &(pVarDesc->elemdescVar.tdesc), Qnil);
    pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
    return type;
}

/*
 *   call-seq:
 *      WIN32OLE_VARIABLE#ole_type
 * 
 *   Returns OLE type string.
 *
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *     variables = tobj.variables
 *     variables.each do |variable|
 *       puts "#{variable.ole_type} #{variable.name}"
 *     end
 *
 *     The result of above script is following:
 *       INT xlChart
 *       INT xlDialogSheet
 *       INT xlExcel4IntlMacroSheet
 *       INT xlExcel4MacroSheet
 *       INT xlWorksheet
 *
 */
static VALUE
folevariable_ole_type(self)
    VALUE self;
{
    struct olevariabledata *pvar;
    Data_Get_Struct(self, struct olevariabledata, pvar);
    return ole_variable_ole_type(pvar->pTypeInfo, pvar->index);
}

static VALUE
ole_variable_ole_type_detail(pTypeInfo, var_index)
    ITypeInfo *pTypeInfo;
    UINT var_index;
{
    VARDESC *pVarDesc;
    HRESULT hr;
    VALUE type = rb_ary_new();
    hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, var_index, &pVarDesc);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetVarDesc");
    ole_typedesc2val(pTypeInfo, &(pVarDesc->elemdescVar.tdesc), type);
    pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
    return type;
}

/*
 *  call-seq:
 *     WIN32OLE_VARIABLE#ole_type_detail
 * 
 *  Returns detail information of type. The information is array of type.
 *
 *     tobj = WIN32OLE_TYPE.new('DirectX 7 for Visual Basic Type Library', 'D3DCLIPSTATUS')
 *     variable = tobj.variables.find {|variable| variable.name == 'lFlags'}
 *     tdetail  = variable.ole_type_detail
 *     p tdetail # => ["USERDEFINED", "CONST_D3DCLIPSTATUSFLAGS"]
 *
 */
static VALUE
folevariable_ole_type_detail(self)
    VALUE self;
{
    struct olevariabledata *pvar;
    Data_Get_Struct(self, struct olevariabledata, pvar);
    return ole_variable_ole_type_detail(pvar->pTypeInfo, pvar->index);
}

static VALUE
ole_variable_value(pTypeInfo, var_index)
    ITypeInfo *pTypeInfo;
    UINT var_index;
{
    VARDESC *pVarDesc;
    HRESULT hr;
    VALUE val = Qnil;
    hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, var_index, &pVarDesc);
    if (FAILED(hr))
        return Qnil;
    if(pVarDesc->varkind == VAR_CONST)
        val = ole_variant2val(V_UNION1(pVarDesc, lpvarValue));
    pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
    return val;
}

/*
 *  call-seq:
 *     WIN32OLE_VARIABLE#value
 * 
 *  Returns value if value is exists. If the value does not exist, 
 *  this method returns nil.
 *
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *     variables = tobj.variables
 *     variables.each do |variable|
 *       puts "#{variable.name} = #{variable.value}"
 *     end
 *
 *     The result of above script is following:
 *       xlChart = -4109
 *       xlDialogSheet = -4116
 *       xlExcel4IntlMacroSheet = 4
 *       xlExcel4MacroSheet = 3
 *       xlWorksheet = -4167
 *
 */    
static VALUE
folevariable_value(self)
    VALUE self;
{
    struct olevariabledata *pvar;
    Data_Get_Struct(self, struct olevariabledata, pvar);
    return ole_variable_value(pvar->pTypeInfo, pvar->index);
}

static VALUE
ole_variable_visible(pTypeInfo, var_index)
    ITypeInfo *pTypeInfo;
    UINT var_index;
{
    VARDESC *pVarDesc;
    HRESULT hr;
    VALUE visible = Qfalse;
    hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, var_index, &pVarDesc);
    if (FAILED(hr))
        return visible;
    if (!(pVarDesc->wVarFlags & (VARFLAG_FHIDDEN |
                                 VARFLAG_FRESTRICTED |
                                 VARFLAG_FNONBROWSABLE))) {
        visible = Qtrue;
    }
    pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
    return visible;
}

/*
 *  call-seq:
 *     WIN32OLE_VARIABLE#visible?
 * 
 *  Returns true if the variable is public.
 *
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *     variables = tobj.variables
 *     variables.each do |variable|
 *       puts "#{variable.name} #{variable.visible?}"
 *     end
 *
 *     The result of above script is following:
 *       xlChart true
 *       xlDialogSheet true
 *       xlExcel4IntlMacroSheet true
 *       xlExcel4MacroSheet true
 *       xlWorksheet true
 *       
 */
static VALUE
folevariable_visible(self)
    VALUE self;
{
    struct olevariabledata *pvar;
    Data_Get_Struct(self, struct olevariabledata, pvar);
    return ole_variable_visible(pvar->pTypeInfo, pvar->index);
}

static VALUE
ole_variable_kind(pTypeInfo, var_index)
    ITypeInfo *pTypeInfo;
    UINT var_index;
{
    VARDESC *pVarDesc;
    HRESULT hr;
    VALUE kind = rb_str_new2("UNKNOWN");
    hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, var_index, &pVarDesc);
    if (FAILED(hr))
        return kind;
    switch(pVarDesc->varkind) {
    case VAR_PERINSTANCE:
        kind = rb_str_new2("PERINSTANCE");
        break;
    case VAR_STATIC:
        kind = rb_str_new2("STATIC");
        break;
    case VAR_CONST:
        kind = rb_str_new2("CONSTANT");
        break;
    case VAR_DISPATCH:
        kind = rb_str_new2("DISPATCH");
        break;
    default:
        break;
    }
    pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
    return kind;
}

/*
 * call-seq:
 *   WIN32OLE_VARIABLE#variable_kind
 * 
 * Returns variable kind string.
 *
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *    variables = tobj.variables
 *    variables.each do |variable|
 *      puts "#{variable.name} #{variable.variable_kind}"
 *    end
 *
 *    The result of above script is following:
 *      xlChart CONSTANT
 *      xlDialogSheet CONSTANT
 *      xlExcel4IntlMacroSheet CONSTANT
 *      xlExcel4MacroSheet CONSTANT
 *      xlWorksheet CONSTANT
 */
static VALUE
folevariable_variable_kind(self)
    VALUE self;
{
    struct olevariabledata *pvar;
    Data_Get_Struct(self, struct olevariabledata, pvar);
    return ole_variable_kind(pvar->pTypeInfo, pvar->index);
}

static VALUE
ole_variable_varkind(pTypeInfo, var_index)
    ITypeInfo *pTypeInfo;
    UINT var_index;
{
    VARDESC *pVarDesc;
    HRESULT hr;
    VALUE kind = Qnil;
    hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, var_index, &pVarDesc);
    if (FAILED(hr))
        return kind;
    pTypeInfo->lpVtbl->ReleaseVarDesc(pTypeInfo, pVarDesc);
    kind = INT2FIX(pVarDesc->varkind);    
    return kind;
}

/*
 *  call-seq:
 *     WIN32OLE_VARIABLE#varkind
 * 
 *  Returns the number which represents variable kind.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'XlSheetType')
 *    variables = tobj.variables
 *    variables.each do |variable|
 *      puts "#{variable.name} #{variable.varkind}"
 *    end
 *
 *    The result of above script is following:
 *       xlChart 2
 *       xlDialogSheet 2
 *       xlExcel4IntlMacroSheet 2
 *       xlExcel4MacroSheet 2
 *       xlWorksheet 2
 */
static VALUE
folevariable_varkind(self)
    VALUE self;
{
    struct olevariabledata *pvar;
    Data_Get_Struct(self, struct olevariabledata, pvar);
    return ole_variable_varkind(pvar->pTypeInfo, pvar->index);
}

/*
 * Document-class: WIN32OLE_METHOD
 *
 *   <code>WIN32OLE_METHOD</code> objects represent OLE method information.
 */

static VALUE
olemethod_set_member(self, pTypeInfo, pOwnerTypeInfo, index, name)
    VALUE self;
    ITypeInfo *pTypeInfo;
    ITypeInfo *pOwnerTypeInfo;
    int index;
    VALUE name;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    pmethod->pTypeInfo = pTypeInfo;
    OLE_ADDREF(pTypeInfo);
    pmethod->pOwnerTypeInfo = pOwnerTypeInfo;
    if(pOwnerTypeInfo) OLE_ADDREF(pOwnerTypeInfo);
    pmethod->index = index;
    rb_ivar_set(self, rb_intern("name"), name);
    return self;
}

static VALUE
folemethod_s_allocate(klass)
    VALUE klass;
{
    struct olemethoddata *pmethod;
    VALUE obj;
    obj = Data_Make_Struct(klass, 
                           struct olemethoddata,
                           0, olemethod_free, pmethod);
    pmethod->pTypeInfo = NULL;
    pmethod->pOwnerTypeInfo = NULL;
    pmethod->index = 0;
    return obj;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD.new(ole_type,  method) -> WIN32OLE_METHOD object
 * 
 *  Returns a new WIN32OLE_METHOD object which represents the information
 *  about OLE method.
 *  The first argument <i>ole_type</i> specifies WIN32OLE_TYPE object.
 *  The second argument <i>method</i> specifies OLE method name defined OLE class
 *  which represents WIN32OLE_TYPE object.
 *
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 */
static VALUE
folemethod_initialize(self, oletype, method)
    VALUE self;
    VALUE oletype;
    VALUE method;
{
    struct oletypedata *ptype;
    VALUE obj = Qnil;
    if (rb_obj_is_kind_of(oletype, cWIN32OLE_TYPE)) {
        Check_SafeStr(method);
        Data_Get_Struct(oletype, struct oletypedata, ptype);
        obj = olemethod_from_typeinfo(self, ptype->pTypeInfo, method);
        if (obj == Qnil) {
            rb_raise(eWIN32OLE_RUNTIME_ERROR, "not found %s",
                     StringValuePtr(method));
        }
    }
    else {
        rb_raise(rb_eTypeError, "1st argument should be WIN32OLE_TYPE object");
    }
    return obj;
}

/*
 *  call-seq
 *     WIN32OLE_METHOD#name
 *
 *  Returns the name of the method.
 *
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     puts method.name # => SaveAs
 *     
 */
static VALUE
folemethod_name(self)
    VALUE self;
{
    return rb_ivar_get(self, rb_intern("name"));
}

static VALUE
ole_method_return_type(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE type;

    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr)) 
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetFuncDesc");
    
    type = ole_typedesc2val(pTypeInfo, &(pFuncDesc->elemdescFunc.tdesc), Qnil);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return type;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#return_type
 * 
 *  Returns string of return value type of method.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.return_type # => Workbook
 *
 */
static VALUE
folemethod_return_type(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_return_type(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_return_vtype(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE vt;

    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr)) 
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetFuncDesc");
    
    vt = INT2FIX(pFuncDesc->elemdescFunc.tdesc.vt);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return vt;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#return_vtype
 * 
 *  Returns number of return value type of method.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.return_vtype # => 26
 *
 */
static VALUE
folemethod_return_vtype(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_return_vtype(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_return_type_detail(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE type = rb_ary_new();

    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr)) 
        return type;
    
    ole_typedesc2val(pTypeInfo, &(pFuncDesc->elemdescFunc.tdesc), type);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return type;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#return_type_detail
 * 
 *  Returns detail information of return value type of method.
 *  The information is array.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     p method.return_type_detail # => ["PTR", "USERDEFINED", "Workbook"]
 */
static VALUE
folemethod_return_type_detail(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_return_type_detail(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_invkind(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE invkind;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if(FAILED(hr)) 
        ole_raise(hr, eWIN32OLE_RUNTIME_ERROR, "failed to GetFuncDesc");
    invkind = INT2FIX(pFuncDesc->invkind);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return invkind;
}

static VALUE
ole_method_invoke_kind(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    WORD method_index;
{
    VALUE type = rb_str_new2("UNKNOWN");
    VALUE invkind = ole_method_invkind(pTypeInfo, method_index);
    if((FIX2INT(invkind) & INVOKE_PROPERTYGET) &&
       (FIX2INT(invkind) & INVOKE_PROPERTYPUT) ) {
        type = rb_str_new2("PROPERTY");
    } else if(FIX2INT(invkind) & INVOKE_PROPERTYGET) {
        type =  rb_str_new2("PROPERTYGET");
    } else if(FIX2INT(invkind) & INVOKE_PROPERTYPUT) {
        type = rb_str_new2("PROPERTYPUT");
    } else if(FIX2INT(invkind) & INVOKE_PROPERTYPUTREF) {
        type = rb_str_new2("PROPERTYPUTREF");
    } else if(FIX2INT(invkind) & INVOKE_FUNC) {
        type = rb_str_new2("FUNC");
    }
    return type;
}

/*
 *   call-seq:
 *      WIN32OLE_MTHOD#invkind
 * 
 *   Returns the method invoke kind. 
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.invkind # => 1
 *
 */
static VALUE
folemethod_invkind(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_invkind(pmethod->pTypeInfo, pmethod->index);
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#invoke_kind
 * 
 *  Returns the method kind string. The string is "UNKNOWN" or "PROPERTY" 
 *  or "PROPERTY" or "PROPERTYGET" or "PROPERTYPUT" or "PROPERTYPPUTREF" 
 *  or "FUNC".
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.invoke_kind # => "FUNC"
 */
static VALUE
folemethod_invoke_kind(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_invoke_kind(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_visible(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE visible;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if(FAILED(hr))
        return Qfalse;
    if (pFuncDesc->wFuncFlags & (FUNCFLAG_FRESTRICTED |
                                 FUNCFLAG_FHIDDEN |
                                 FUNCFLAG_FNONBROWSABLE)) {
        visible = Qfalse;
    } else {
        visible = Qtrue;
    }
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return visible;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#visible?
 * 
 *  Returns true if the method is public.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.visible? # => true
 */
static VALUE
folemethod_visible(self) 
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_visible(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_event(pTypeInfo, method_index, method_name)
    ITypeInfo *pTypeInfo;
    WORD method_index;
    VALUE method_name;
{
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    WORD i;
    int flags;
    HREFTYPE href;
    ITypeInfo *pRefTypeInfo;
    FUNCDESC *pFuncDesc;
    BSTR bstr;
    VALUE name;
    VALUE event = Qfalse;
    
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) 
        return event;
    if(pTypeAttr->typekind != TKIND_COCLASS) {
        pTypeInfo->lpVtbl->ReleaseTypeAttr(pTypeInfo, pTypeAttr);
        return event;
    }
    for (i = 0; i < pTypeAttr->cImplTypes; i++) {
        hr = pTypeInfo->lpVtbl->GetImplTypeFlags(pTypeInfo, i, &flags);
        if (FAILED(hr))
            continue;

        if (flags & IMPLTYPEFLAG_FSOURCE) {
            hr = pTypeInfo->lpVtbl->GetRefTypeOfImplType(pTypeInfo,
                                                         i, &href);
            if (FAILED(hr))
                continue;
            hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo,
                                                   href, &pRefTypeInfo);
            if (FAILED(hr))
                continue;
            hr = pRefTypeInfo->lpVtbl->GetFuncDesc(pRefTypeInfo, method_index, 
                                                   &pFuncDesc);
            if (FAILED(hr)) {
                OLE_RELEASE(pRefTypeInfo);
                continue;
            }

            hr = pRefTypeInfo->lpVtbl->GetDocumentation(pRefTypeInfo, 
                                                        pFuncDesc->memid,
                                                        &bstr, NULL, NULL, NULL);
            if (FAILED(hr)) {
                pRefTypeInfo->lpVtbl->ReleaseFuncDesc(pRefTypeInfo, pFuncDesc);
                OLE_RELEASE(pRefTypeInfo);
                continue;
            }

            name = WC2VSTR(bstr);
            pRefTypeInfo->lpVtbl->ReleaseFuncDesc(pRefTypeInfo, pFuncDesc);
            OLE_RELEASE(pRefTypeInfo);
            if (rb_str_cmp(method_name, name) == 0) {
                event = Qtrue;
                break;
            }
        }
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return event;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#event?
 * 
 *  Returns true if the method is event.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SheetActivate')
 *     puts method.event? # => true
 *
 */
static VALUE
folemethod_event(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    if (!pmethod->pOwnerTypeInfo)
        return Qfalse;
    return ole_method_event(pmethod->pOwnerTypeInfo, 
                            pmethod->index,
                            rb_ivar_get(self, rb_intern("name")));
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#event_interface
 *
 *  Returns event interface name if the method is event.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *    method = WIN32OLE_METHOD.new(tobj, 'SheetActivate')
 *    puts method.event_interface # =>  WorkbookEvents
 */
static VALUE
folemethod_event_interface(self)
    VALUE self;
{
    BSTR name;
    struct olemethoddata *pmethod;
    HRESULT hr;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    if(folemethod_event(self) == Qtrue) {
        hr = ole_docinfo_from_type(pmethod->pTypeInfo, &name, NULL, NULL, NULL);
        if(SUCCEEDED(hr))
            return WC2VSTR(name);
    }
    return Qnil;
}

static VALUE
ole_method_docinfo_from_type(pTypeInfo, method_index, name, helpstr,
                             helpcontext, helpfile)
    ITypeInfo *pTypeInfo;
    UINT method_index;
    BSTR *name;
    BSTR *helpstr;
    DWORD *helpcontext;
    BSTR *helpfile;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return hr;
    hr = pTypeInfo->lpVtbl->GetDocumentation(pTypeInfo, pFuncDesc->memid,
                                             name, helpstr,
                                             helpcontext, helpfile);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return hr;
}

static VALUE
ole_method_helpstring(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    HRESULT hr;
    BSTR bhelpstring;
    hr = ole_method_docinfo_from_type(pTypeInfo, method_index, NULL, &bhelpstring,
                                      NULL, NULL); 
    if (FAILED(hr))
        return Qnil;
    return WC2VSTR(bhelpstring);
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#helpstring
 *
 *  Returns help string of OLE method. If the help string is not found, 
 *  then the method returns nil.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Internet Controls', 'IWebBrowser')
 *     method = WIN32OLE_METHOD.new(tobj, 'Navigate')
 *     puts method.helpstring # => Navigates to a URL or file.
 *
 */
static VALUE
folemethod_helpstring(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_helpstring(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_helpfile(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    HRESULT hr;
    BSTR bhelpfile;
    hr = ole_method_docinfo_from_type(pTypeInfo, method_index, NULL, NULL,
                                      NULL, &bhelpfile); 
    if (FAILED(hr))
        return Qnil;
    return WC2VSTR(bhelpfile);
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#helpfile
 * 
 *  Returns help file. If help file is not found, then 
 *  the method returns nil.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.helpfile # => C:\...\VBAXL9.CHM
 */
static VALUE
folemethod_helpfile(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);

    return ole_method_helpfile(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_helpcontext(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    HRESULT hr;
    DWORD helpcontext = 0;
    hr = ole_method_docinfo_from_type(pTypeInfo, method_index, NULL, NULL,
                                      &helpcontext, NULL); 
    if (FAILED(hr))
        return Qnil;
    return INT2FIX(helpcontext);
}

/* 
 *  call-seq:
 *     WIN32OLE_METHOD#helpcontext
 * 
 *  Returns help context.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.helpcontext # => 65717
 */
static VALUE
folemethod_helpcontext(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_helpcontext(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_dispid(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE dispid = Qnil;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return dispid;
    dispid = INT2NUM(pFuncDesc->memid); 
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return dispid;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#dispid
 * 
 *  Returns dispatch ID.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.dispid # => 181
 */
static VALUE
folemethod_dispid(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_dispid(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_offset_vtbl(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE offset_vtbl = Qnil;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return offset_vtbl;
    offset_vtbl = INT2FIX(pFuncDesc->oVft); 
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return offset_vtbl;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#offset_vtbl
 * 
 *  Returns the offset ov VTBL.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbooks')
 *     method = WIN32OLE_METHOD.new(tobj, 'Add')
 *     puts method.offset_vtbl # => 40
 */
static VALUE
folemethod_offset_vtbl(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_offset_vtbl(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_size_params(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE size_params = Qnil;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return size_params;
    size_params = INT2FIX(pFuncDesc->cParams);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return size_params;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#size_params
 * 
 *  Returns the size of arguments of the method.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     puts method.size_params # => 11
 *  
 */
static VALUE
folemethod_size_params(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_size_params(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_size_opt_params(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE size_opt_params = Qnil;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return size_opt_params;
    size_opt_params = INT2FIX(pFuncDesc->cParamsOpt);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return size_opt_params;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#size_opt_params
 * 
 *  Returns the size of optional parameters.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     puts method.size_opt_params # => 4
 */
static VALUE
folemethod_size_opt_params(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_size_opt_params(pmethod->pTypeInfo, pmethod->index);
}

static VALUE
ole_method_params(pTypeInfo, method_index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    BSTR *bstrs;
    UINT len, i;
    struct oleparamdata *pparam;
    VALUE param;
    VALUE params = rb_ary_new();
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr)) 
        return params;

    len = 0;
    bstrs = ALLOCA_N(BSTR, pFuncDesc->cParams + 1);
    hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, pFuncDesc->memid, 
                                     bstrs, pFuncDesc->cParams + 1,
                                     &len);
    if (FAILED(hr)) {
        pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
        return params;
    }
    SysFreeString(bstrs[0]);
    if (pFuncDesc->cParams > 0) {
        for(i = 1; i < len; i++) {
            param = Data_Make_Struct(cWIN32OLE_PARAM, struct oleparamdata, 0,
                                     oleparam_free, pparam);
            pparam->pTypeInfo = pTypeInfo;
            OLE_ADDREF(pTypeInfo);
            pparam->method_index = method_index;
            pparam->index = i - 1;
            rb_ivar_set(param, rb_intern("name"), WC2VSTR(bstrs[i]));
            rb_ary_push(params, param);
         }
     }
     pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
     return params;
}

/*
 *  call-seq:
 *     WIN32OLE_METHOD#params
 * 
 *  returns array of WIN32OLE_PARAM object corresponding with method parameters.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     p method.params # => [Filename, FileFormat, Password, WriteResPassword, 
 *                           ReadOnlyRecommended, CreateBackup, AccessMode, 
 *                           ConflictResolution, AddToMru, TextCodepage, 
 *                           TextVisualLayout]
 */
static VALUE
folemethod_params(self)
    VALUE self;
{
    struct olemethoddata *pmethod;
    Data_Get_Struct(self, struct olemethoddata, pmethod);
    return ole_method_params(pmethod->pTypeInfo, pmethod->index);
}

/*
 * Document-class: WIN32OLE_PARAM
 *
 *   <code>WIN32OLE_PARAM</code> objects represent param information of 
 *   the OLE method.
 */

/*
 *  call-seq:
 *     WIN32OLE_PARAM#name
 * 
 *  Returns name.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     param1 = method.params[0]
 *     puts param1.name # => Filename
 */
static VALUE
foleparam_name(self)
    VALUE self;
{
    return rb_ivar_get(self, rb_intern("name"));
}

static VALUE
ole_param_ole_type(pTypeInfo, method_index, index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
    UINT index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE type = rb_str_new2("UNKNOWN");
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return type;
    type = ole_typedesc2val(pTypeInfo, 
                            &(pFuncDesc->lprgelemdescParam[index].tdesc), Qnil);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return type;
}

/*
 *  call-seq:
 *     WIN32OLE_PARAM#ole_type
 *
 *  Returns OLE type of WIN32OLE_PARAM object(parameter of OLE method).
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     param1 = method.params[0]
 *     puts param1.ole_type # => VARIANT
 */
static VALUE 
foleparam_ole_type(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_ole_type(pparam->pTypeInfo, pparam->method_index, 
                              pparam->index);
}

static VALUE
ole_param_ole_type_detail(pTypeInfo, method_index, index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
    UINT index;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE typedetail = rb_ary_new();
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return typedetail;
    ole_typedesc2val(pTypeInfo, 
                     &(pFuncDesc->lprgelemdescParam[index].tdesc), typedetail);
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return typedetail;
}

/*
 *  call-seq:
 *     WIN32OLE_PARAM#ole_type_detail
 *
 *  Returns detail information of type of argument.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'IWorksheetFunction')
 *     method = WIN32OLE_METHOD.new(tobj, 'SumIf')
 *     param1 = method.params[0]
 *     p param1.ole_type_detail # => ["PTR", "USERDEFINED", "Range"]
 */
static VALUE 
foleparam_ole_type_detail(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_ole_type_detail(pparam->pTypeInfo, pparam->method_index, 
                                     pparam->index);
}

static VALUE
ole_param_flag_mask(pTypeInfo, method_index, index, mask)
    ITypeInfo *pTypeInfo;
    UINT method_index;
    UINT index;
    USHORT mask;
{
    FUNCDESC *pFuncDesc;
    HRESULT hr;
    VALUE ret = Qfalse;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if(FAILED(hr)) 
        return ret;
    if (V_UNION1((&(pFuncDesc->lprgelemdescParam[index])), paramdesc).wParamFlags &mask) 
        ret = Qtrue;
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return ret;
}

/*
 *  call-seq:
 *     WIN32OLE_PARAM#input?
 * 
 *  Returns true if the parameter is input.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     param1 = method.params[0]
 *     puts param1.input? # => true
 */
static VALUE foleparam_input(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_flag_mask(pparam->pTypeInfo, pparam->method_index, 
                               pparam->index, PARAMFLAG_FIN);
}

/*
 *  call-seq:
 *     WIN32OLE#output?
 * 
 *  Returns true if argument is output.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Internet Controls', 'DWebBrowserEvents')
 *     method = WIN32OLE_METHOD.new(tobj, 'NewWindow')
 *     method.params.each do |param|
 *       puts "#{param.name} #{param.output?}"
 *     end
 *
 *     The result of above script is following:
 *       URL false
 *       Flags false
 *       TargetFrameName false
 *       PostData false
 *       Headers false
 *       Processed true
 */
static VALUE foleparam_output(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_flag_mask(pparam->pTypeInfo, pparam->method_index, 
                               pparam->index, PARAMFLAG_FOUT);
}

/*
 *  call-seq:
 *     WIN32OLE_PARAM#optional?
 * 
 *  Returns true if argument is optional.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     param1 = method.params[0]
 *     puts "#{param1.name} #{param1.optional?}" # => Filename true
 */
static VALUE foleparam_optional(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_flag_mask(pparam->pTypeInfo, pparam->method_index, 
                               pparam->index, PARAMFLAG_FOPT);
}

/*
 *  call-seq:
 *     WIN32OLE_PARAM#retval?
 *
 *  Returns true if argument is return value.
 *     tobj = WIN32OLE_TYPE.new('DirectX 7 for Visual Basic Type Library', 
 *                              'DirectPlayLobbyConnection')
 *     method = WIN32OLE_METHOD.new(tobj, 'GetPlayerShortName')
 *     param = method.params[0]
 *     puts "#{param.name} #{param.retval?}"  # => name true
 */
static VALUE foleparam_retval(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_flag_mask(pparam->pTypeInfo, pparam->method_index, 
                               pparam->index, PARAMFLAG_FRETVAL);
}

static VALUE
ole_param_default(pTypeInfo, method_index, index)
    ITypeInfo *pTypeInfo;
    UINT method_index;
    UINT index;
{
    FUNCDESC *pFuncDesc;
    ELEMDESC *pElemDesc;
    PARAMDESCEX * pParamDescEx;
    HRESULT hr;
    USHORT wParamFlags;
    USHORT mask = PARAMFLAG_FOPT|PARAMFLAG_FHASDEFAULT;
    VALUE defval = Qnil;
    hr = pTypeInfo->lpVtbl->GetFuncDesc(pTypeInfo, method_index, &pFuncDesc);
    if (FAILED(hr))
        return defval;
    pElemDesc = &pFuncDesc->lprgelemdescParam[index]; 
    wParamFlags = V_UNION1(pElemDesc, paramdesc).wParamFlags;
    if ((wParamFlags & mask) == mask) {
         pParamDescEx = V_UNION1(pElemDesc, paramdesc).pparamdescex;
         defval = ole_variant2val(&pParamDescEx->varDefaultValue);
    }
    pTypeInfo->lpVtbl->ReleaseFuncDesc(pTypeInfo, pFuncDesc);
    return defval;
}

/*
 *  call-seq:
 *     WIN32OLE_PARAM#default
 * 
 *  Returns default value. If the default value does not exist, 
 *  this method returns nil.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Workbook')
 *     method = WIN32OLE_METHOD.new(tobj, 'SaveAs')
 *     method.params.each do |param|
 *       if param.default
 *         puts "#{param.name} (= #{param.default})"
 *       else
 *         puts "#{param}"
 *       end
 *     end
 *
 *     The above script result is following:
 *         Filename
 *         FileFormat
 *         Password
 *         WriteResPassword
 *         ReadOnlyRecommended
 *         CreateBackup
 *         AccessMode (= 1)
 *         ConflictResolution
 *         AddToMru
 *         TextCodepage
 *         TextVisualLayout
 */
static VALUE foleparam_default(self)
    VALUE self;
{
    struct oleparamdata *pparam;
    Data_Get_Struct(self, struct oleparamdata, pparam);
    return ole_param_default(pparam->pTypeInfo, pparam->method_index,
                             pparam->index);
}


/*
 * Document-class: WIN32OLE_EVENT
 *
 *   <code>WIN32OLE_EVENT</code> objects controls OLE event.
 */

static IEventSinkVtbl vtEventSink;
static BOOL g_IsEventSinkVtblInitialized = FALSE;

void EVENTSINK_Destructor(PIEVENTSINKOBJ);

STDMETHODIMP
EVENTSINK_QueryInterface(
    PEVENTSINK pEV,
    REFIID     iid,
    LPVOID*    ppv
    ) {
    if (IsEqualIID(iid, &IID_IUnknown) ||
        IsEqualIID(iid, &IID_IDispatch) ||
        IsEqualIID(iid, &((PIEVENTSINKOBJ)pEV)->m_iid)) {
        *ppv = pEV;
    }
    else {
        *ppv = NULL;
        return E_NOINTERFACE;
    }
    ((LPUNKNOWN)*ppv)->lpVtbl->AddRef((LPUNKNOWN)*ppv);
    return NOERROR;
}

STDMETHODIMP_(ULONG)
EVENTSINK_AddRef(
    PEVENTSINK pEV
    ){
    PIEVENTSINKOBJ pEVObj = (PIEVENTSINKOBJ)pEV;
    return ++pEVObj->m_cRef;
}

STDMETHODIMP_(ULONG) EVENTSINK_Release(
    PEVENTSINK pEV
    ) {
    PIEVENTSINKOBJ pEVObj = (PIEVENTSINKOBJ)pEV;
    --pEVObj->m_cRef;
    if(pEVObj->m_cRef != 0)
        return pEVObj->m_cRef;
    EVENTSINK_Destructor(pEVObj);
    return 0;
}

STDMETHODIMP EVENTSINK_GetTypeInfoCount(
    PEVENTSINK pEV,
    UINT *pct
    ) {
    *pct = 0;
    return NOERROR;
}

STDMETHODIMP EVENTSINK_GetTypeInfo(
    PEVENTSINK pEV,
    UINT info,
    LCID lcid,
    ITypeInfo **pInfo
    ) {
    *pInfo = NULL;
    return DISP_E_BADINDEX;
}

STDMETHODIMP EVENTSINK_GetIDsOfNames(
    PEVENTSINK pEV,
    REFIID riid,
    OLECHAR **szNames,
    UINT cNames,
    LCID lcid,
    DISPID *pDispID
    ) {
    return DISP_E_UNKNOWNNAME;
}

static long
ole_search_event_at(ary, ev)
    VALUE ary;
    VALUE ev;
{
    VALUE event;
    VALUE def_event;
    VALUE event_name;
    long i, len; 
    long ret = -1;
    def_event = Qnil;
    len = RARRAY(ary)->len;
    for(i = 0; i < len; i++) {
        event = rb_ary_entry(ary, i);
        event_name = rb_ary_entry(event, 1);
        if(NIL_P(event_name) && NIL_P(ev)) {
            ret = i;
            break;
        }
        else if (TYPE(ev) == T_STRING &&
                 TYPE(event_name) == T_STRING &&
                 rb_str_cmp(ev, event_name) == 0) {
            ret = i;
            break;
        }
    }
    return ret;
}

static VALUE
ole_search_event(ary, ev, is_default)
    VALUE ary;
    VALUE ev;
    BOOL  *is_default;
{
    VALUE event;
    VALUE def_event;
    VALUE event_name;
    long i, len;
    *is_default = FALSE;
    def_event = Qnil;
    len = RARRAY(ary)->len;
    for(i = 0; i < len; i++) {
        event = rb_ary_entry(ary, i);
        event_name = rb_ary_entry(event, 1);
        if(NIL_P(event_name)) {
            *is_default = TRUE;
            def_event = event;
        }
        else if (rb_str_cmp(ev, event_name) == 0) {
            *is_default = FALSE;
            return event;
        }
    }
    return def_event;
}

static void
val2ptr_variant(val, var)
    VALUE val;
    VARIANT *var;
{
    switch (TYPE(val)) {
    case T_STRING:
        if (V_VT(var) == (VT_BSTR | VT_BYREF)) {
            *V_BSTRREF(var) = ole_mb2wc(StringValuePtr(val), -1);
        }
        break;
    case T_FIXNUM:
        switch(V_VT(var)) {
        case (VT_UI1 | VT_BYREF) :
            *V_UI1REF(var) = NUM2CHR(val);
            break;
        case (VT_I2 | VT_BYREF) :
            *V_I2REF(var) = (short)NUM2INT(val);
            break;
        case (VT_I4 | VT_BYREF) :
            *V_I4REF(var) = NUM2INT(val);
            break;
        case (VT_R4 | VT_BYREF) :
            *V_R4REF(var) = (float)NUM2INT(val);
            break;
        case (VT_R8 | VT_BYREF) :
            *V_R8REF(var) = NUM2INT(val);
            break;
        default:
            break;
        }
        break;
    case T_FLOAT:
        switch(V_VT(var)) {
        case (VT_I2 | VT_BYREF) :
            *V_I2REF(var) = (short)NUM2INT(val);
            break;
        case (VT_I4 | VT_BYREF) :
            *V_I4REF(var) = NUM2INT(val);
            break;
        case (VT_R4 | VT_BYREF) :
            *V_R4REF(var) = (float)NUM2DBL(val);
            break;
        case (VT_R8 | VT_BYREF) :
            *V_R8REF(var) = NUM2DBL(val);
            break;
        default:
            break;
        }
        break;
    case T_BIGNUM:
        if (V_VT(var) == (VT_R8 | VT_BYREF)) {
            *V_R8REF(var) = rb_big2dbl(val);
        }
        break;
    case T_TRUE:
        if (V_VT(var) == (VT_BOOL | VT_BYREF)) {
            *V_BOOLREF(var) = VARIANT_TRUE;
        }
        break;
    case T_FALSE:
        if (V_VT(var) == (VT_BOOL | VT_BYREF)) {
            *V_BOOLREF(var) = VARIANT_FALSE;
        }
        break;
    default:
        break;
    }
}

static void
ary2ptr_dispparams(ary, pdispparams)
    VALUE ary;
    DISPPARAMS *pdispparams;
{
    int i;
    VALUE v;
    VARIANT *pvar;
    for(i = 0; i < RARRAY(ary)->len && (unsigned int) i < pdispparams->cArgs; i++) {
        v = rb_ary_entry(ary, i);
        pvar = &pdispparams->rgvarg[pdispparams->cArgs-i-1];
        val2ptr_variant(v, pvar);
    }
}

STDMETHODIMP EVENTSINK_Invoke(
    PEVENTSINK pEventSink,
    DISPID dispid,
    REFIID riid,
    LCID lcid,
    WORD wFlags,
    DISPPARAMS *pdispparams,
    VARIANT *pvarResult,
    EXCEPINFO *pexcepinfo,
    UINT *puArgErr
    ) {

    HRESULT hr;
    BSTR bstr;
    unsigned int count;
    unsigned int i;
    ITypeInfo *pTypeInfo;
    VARIANT *pvar;
    VALUE ary, obj, event, handler, args, argv, ev, result;
    BOOL is_default_handler = FALSE;

    PIEVENTSINKOBJ pEV = (PIEVENTSINKOBJ)pEventSink;
    pTypeInfo = pEV->pTypeInfo;

    obj = rb_ary_entry(ary_ole_event, pEV->m_event_id);
    if (!rb_obj_is_kind_of(obj, cWIN32OLE_EVENT)) {
        return NOERROR;
    }

    ary = rb_ivar_get(obj, id_events);
    if (NIL_P(ary) || TYPE(ary) != T_ARRAY) {
        return NOERROR;
    }
    hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, dispid,
                                     &bstr, 1, &count);
    if (FAILED(hr)) {
        return NOERROR;
    }
    ev = WC2VSTR(bstr);
    event = ole_search_event(ary, ev, &is_default_handler);
    if (NIL_P(event)) {
        return NOERROR;
    }
    args = rb_ary_new();
    if (is_default_handler) {
        rb_ary_push(args, ev);
    }

    /* make argument of event handler */
    for (i = 0; i < pdispparams->cArgs; ++i) {
        pvar = &pdispparams->rgvarg[pdispparams->cArgs-i-1];
        rb_ary_push(args, ole_variant2val(pvar));
    }
    handler = rb_ary_entry(event, 0);

    if (rb_ary_entry(event, 3) == Qtrue) {
        argv = rb_ary_new();
        rb_ary_push(args, argv);
        result = rb_apply(handler, rb_intern("call"), args);
        ary2ptr_dispparams(argv, pdispparams);
    }
    else {
        result = rb_apply(handler, rb_intern("call"), args);
    }

    if (pvarResult) {
	VariantInit(pvarResult);
        ole_val2variant(result, pvarResult);
    }
    
    return NOERROR;
}

PIEVENTSINKOBJ
EVENTSINK_Constructor() {
    PIEVENTSINKOBJ pEv;
    if (!g_IsEventSinkVtblInitialized) {
        vtEventSink.QueryInterface=EVENTSINK_QueryInterface;
        vtEventSink.AddRef = EVENTSINK_AddRef;
        vtEventSink.Release = EVENTSINK_Release;
        vtEventSink.Invoke = EVENTSINK_Invoke;
        vtEventSink.GetIDsOfNames = EVENTSINK_GetIDsOfNames;
        vtEventSink.GetTypeInfoCount = EVENTSINK_GetTypeInfoCount;
        vtEventSink.GetTypeInfo = EVENTSINK_GetTypeInfo;

        g_IsEventSinkVtblInitialized = TRUE;
    }
    pEv = ALLOC_N(IEVENTSINKOBJ, 1);
    if(pEv == NULL) return NULL;
    pEv->lpVtbl = &vtEventSink;
    pEv->m_cRef = 0;
    pEv->m_event_id = 0;
    pEv->m_dwCookie = 0;
    pEv->pConnectionPoint = NULL;
    pEv->pTypeInfo = NULL;
    pEv->ptr_freed = NULL;
    return pEv;
}

void EVENTSINK_Destructor(
    PIEVENTSINKOBJ pEVObj
    ) {
    if(pEVObj != NULL) {
        *(pEVObj->ptr_freed) = 1;
        free(pEVObj);
    }
}

static HRESULT
find_iid(ole, pitf, piid, ppTypeInfo)
    VALUE ole;
    char *pitf;
    IID *piid;
    ITypeInfo **ppTypeInfo;
{
    HRESULT hr;
    IDispatch *pDispatch;
    ITypeInfo *pTypeInfo;
    ITypeLib *pTypeLib;
    TYPEATTR *pTypeAttr;
    HREFTYPE RefType;
    ITypeInfo *pImplTypeInfo;
    TYPEATTR *pImplTypeAttr;

    struct oledata *pole;
    unsigned int index;
    unsigned int count;
    int type;
    BSTR bstr;
    char *pstr;

    BOOL is_found = FALSE;
    LCID    lcid = LOCALE_SYSTEM_DEFAULT;

    OLEData_Get_Struct(ole, pole);

    pDispatch = pole->pDispatch;

    hr = pDispatch->lpVtbl->GetTypeInfo(pDispatch, 0, lcid, &pTypeInfo);
    if (FAILED(hr))
        return hr;

    hr = pTypeInfo->lpVtbl->GetContainingTypeLib(pTypeInfo,
                                                 &pTypeLib,
                                                 &index);
    OLE_RELEASE(pTypeInfo);
    if (FAILED(hr))
        return hr;

    if (!pitf) {
        hr = pTypeLib->lpVtbl->GetTypeInfoOfGuid(pTypeLib,
                                                 piid,
                                                 ppTypeInfo);
        OLE_RELEASE(pTypeLib);
        return hr;
    }
    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (index = 0; index < count; index++) {
        hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib,
                                           index,
                                           &pTypeInfo);
        if (FAILED(hr))
            break;
        hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);

        if(FAILED(hr)) {
            OLE_RELEASE(pTypeInfo);
            break;
        }
        if(pTypeAttr->typekind == TKIND_COCLASS) {
            for (type = 0; type < pTypeAttr->cImplTypes; type++) {
                hr = pTypeInfo->lpVtbl->GetRefTypeOfImplType(pTypeInfo,
                                                             type,
                                                             &RefType);
                if (FAILED(hr))
                    break;
                hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo,
                                                       RefType,
                                                       &pImplTypeInfo);
                if (FAILED(hr))
                    break;

                hr = pImplTypeInfo->lpVtbl->GetDocumentation(pImplTypeInfo,
                                                             -1,
                                                             &bstr,
                                                             NULL, NULL, NULL);
                if (FAILED(hr)) {
                    OLE_RELEASE(pImplTypeInfo);
                    break;
                }
                pstr = ole_wc2mb(bstr);
                if (strcmp(pitf, pstr) == 0) {
                    hr = pImplTypeInfo->lpVtbl->GetTypeAttr(pImplTypeInfo,
                                                            &pImplTypeAttr);
                    if (SUCCEEDED(hr)) {
                        is_found = TRUE;
                        *piid = pImplTypeAttr->guid;
                        if (ppTypeInfo) {
                            *ppTypeInfo = pImplTypeInfo;
                            (*ppTypeInfo)->lpVtbl->AddRef((*ppTypeInfo));
                        }
                        pImplTypeInfo->lpVtbl->ReleaseTypeAttr(pImplTypeInfo,
                                                               pImplTypeAttr);
                    }
                }
                free(pstr);
                OLE_RELEASE(pImplTypeInfo);
                if (is_found || FAILED(hr))
                    break;
            }
        }

        OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
        OLE_RELEASE(pTypeInfo);
        if (is_found || FAILED(hr))
            break;
    }
    OLE_RELEASE(pTypeLib);
    if(!is_found)
        return E_NOINTERFACE;
    return hr;
}

static HRESULT
find_default_source(ole, piid, ppTypeInfo)
    VALUE ole;
    IID *piid;
    ITypeInfo **ppTypeInfo;
{
    HRESULT hr;
    IProvideClassInfo2 *pProvideClassInfo2;
    IProvideClassInfo *pProvideClassInfo;
    void *p;

    IDispatch *pDispatch;
    ITypeInfo *pTypeInfo;
    TYPEATTR *pTypeAttr;
    int i;
    int iFlags;
    HREFTYPE hRefType;

    struct oledata *pole;

    OLEData_Get_Struct(ole, pole);
    pDispatch = pole->pDispatch;
    hr = pDispatch->lpVtbl->QueryInterface(pDispatch,
                                           &IID_IProvideClassInfo2,
                                           &p);
    if (SUCCEEDED(hr)) {
        pProvideClassInfo2 = p;
        hr = pProvideClassInfo2->lpVtbl->GetGUID(pProvideClassInfo2,
                                                 GUIDKIND_DEFAULT_SOURCE_DISP_IID,
                                                 piid);
        OLE_RELEASE(pProvideClassInfo2);
        return find_iid(ole, NULL, piid, ppTypeInfo);
    }
    hr = pDispatch->lpVtbl->QueryInterface(pDispatch,
                                           &IID_IProvideClassInfo, &p);
    if (FAILED(hr))
        return hr;
    pProvideClassInfo = p;

    hr = pProvideClassInfo->lpVtbl->GetClassInfo(pProvideClassInfo,
                                                 &pTypeInfo);
    OLE_RELEASE(pProvideClassInfo);
    if (FAILED(hr))
        return hr;

    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        return hr;
    }
    /* Enumerate all implemented types of the COCLASS */
    for (i = 0; i < pTypeAttr->cImplTypes; i++) {
        hr = pTypeInfo->lpVtbl->GetImplTypeFlags(pTypeInfo, i, &iFlags);
        if (FAILED(hr))
            continue;

        /*
           looking for the [default] [source]
           we just hope that it is a dispinterface :-)
        */
        if ((iFlags & IMPLTYPEFLAG_FDEFAULT) &&
            (iFlags & IMPLTYPEFLAG_FSOURCE)) {

            hr = pTypeInfo->lpVtbl->GetRefTypeOfImplType(pTypeInfo,
                                                         i, &hRefType);
            if (FAILED(hr))
                continue;
            hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo,
                                                   hRefType, ppTypeInfo);
            if (SUCCEEDED(hr))
                break;
        }
    }

    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    OLE_RELEASE(pTypeInfo);

    /* Now that would be a bad surprise, if we didn't find it, wouldn't it? */
    if (!*ppTypeInfo) {
        if (SUCCEEDED(hr))
            hr = E_UNEXPECTED;
        return hr;
    }

    /* Determine IID of default source interface */
    hr = (*ppTypeInfo)->lpVtbl->GetTypeAttr(*ppTypeInfo, &pTypeAttr);
    if (SUCCEEDED(hr)) {
        *piid = pTypeAttr->guid;
        (*ppTypeInfo)->lpVtbl->ReleaseTypeAttr(*ppTypeInfo, pTypeAttr);
    }
    else
        OLE_RELEASE(*ppTypeInfo);

    return hr;

}

static void
ole_event_free(poleev)
    struct oleeventdata *poleev;
{
    ITypeInfo *pti = NULL;
    IConnectionPoint *pcp = NULL;

    if (poleev->freed == 1) {
        /* 
         * this return create memory leak.
         * but poleev->pEvent->pConnectionPoint shoul'd not be freed
         * until poleev-> freed == 0.
         */
        return;
    }
    if(poleev->pEvent) {
        pti = poleev->pEvent->pTypeInfo;
        if(pti) OLE_RELEASE(pti);
        pcp = poleev->pEvent->pConnectionPoint;
        if(pcp) {
            pcp->lpVtbl->Unadvise(pcp, poleev->pEvent->m_dwCookie);
            OLE_RELEASE(pcp);
        }
        free(poleev);
    }
}

static VALUE fev_s_allocate _((VALUE));
static VALUE
fev_s_allocate(klass)
    VALUE klass;
{
    VALUE obj;
    struct oleeventdata *poleev;
    obj = Data_Make_Struct(klass,struct oleeventdata,0,ole_event_free,poleev);
    poleev->pEvent = NULL;
    return obj;
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT.new(ole, event) #=> WIN32OLE_EVENT object.
 *
 *  Returns OLE event object.
 *  The first argument specifies WIN32OLE object.
 *  The second argument specifies OLE event name.
 *     ie = WIN32OLE.new('InternetExplorer.Application')
 *     ev = WIN32OLE_EVENT.new(ie, 'DWebBrowserEvents')
 */     
static VALUE
fev_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE ole, itf;
    struct oledata *pole;
    char *pitf;
    HRESULT hr;
    IID iid;
    ITypeInfo *pTypeInfo;
    IDispatch *pDispatch;
    IConnectionPointContainer *pContainer;
    IConnectionPoint *pConnectionPoint;
    IEVENTSINKOBJ *pIEV;
    DWORD dwCookie = 0;
    struct oleeventdata *poleev;
    void *p;

    rb_secure(4);
    rb_scan_args(argc, argv, "11", &ole, &itf);

    if (!rb_obj_is_kind_of(ole, cWIN32OLE)) {
        rb_raise(rb_eTypeError, "1st parameter must be WIN32OLE object");
    }

    if(TYPE(itf) != T_NIL) {
        if (ruby_safe_level > 0 && OBJ_TAINTED(itf)) {
            rb_raise(rb_eSecurityError, "Insecure Event Creation - %s",
                     StringValuePtr(itf));
        }
        Check_SafeStr(itf);
        pitf = StringValuePtr(itf);
        hr = find_iid(ole, pitf, &iid, &pTypeInfo);
    }
    else {
        hr = find_default_source(ole, &iid, &pTypeInfo);
    }
    if (FAILED(hr)) {
        ole_raise(hr, rb_eRuntimeError, "interface not found");
    }

    OLEData_Get_Struct(ole, pole);
    pDispatch = pole->pDispatch;
    hr = pDispatch->lpVtbl->QueryInterface(pDispatch,
                                           &IID_IConnectionPointContainer,
                                           &p);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        ole_raise(hr, rb_eRuntimeError,
                  "failed to query IConnectionPointContainer");
    }
    pContainer = p;

    hr = pContainer->lpVtbl->FindConnectionPoint(pContainer,
                                                 &iid,
                                                 &pConnectionPoint);
    OLE_RELEASE(pContainer);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        ole_raise(hr, rb_eRuntimeError, "failed to query IConnectionPoint");
    }
    pIEV = EVENTSINK_Constructor();
    pIEV->m_iid = iid;
    hr = pConnectionPoint->lpVtbl->Advise(pConnectionPoint,
                                          (IUnknown*)pIEV,
                                          &dwCookie);
    if (FAILED(hr)) {
        ole_raise(hr, rb_eRuntimeError, "Advise Error");
    }

    Data_Get_Struct(self, struct oleeventdata, poleev);
    poleev->pEvent = pIEV;
    poleev->pEvent->m_event_id
        = NUM2INT(rb_funcall(ary_ole_event, rb_intern("length"), 0));
    poleev->pEvent->pConnectionPoint = pConnectionPoint;
    poleev->pEvent->pTypeInfo = pTypeInfo;
    poleev->pEvent->m_dwCookie = dwCookie;
    poleev->freed = 0;
    poleev->pEvent->ptr_freed = &(poleev->freed);
    rb_ary_push(ary_ole_event, self);
    return self;
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT.message_loop
 * 
 *  Translates and dispatches Windows message.
 */
static VALUE
fev_s_msg_loop(klass)
    VALUE klass;
{
    ole_msg_loop();
    return Qnil;
}


static void
add_event_call_back(obj, event, data)
    VALUE obj;
    VALUE event;
    VALUE data;
{
    long at;
    VALUE events = rb_ivar_get(obj, id_events);
    if (NIL_P(events) || TYPE(events) != T_ARRAY) {
        events = rb_ary_new();
        rb_ivar_set(obj, id_events, events);
    }
    at = ole_search_event_at(events, event);
    if (at > -1) {
        rb_ary_delete_at(events, at);
    }
    rb_ary_push(events, data);
}

static VALUE
ev_on_event(argc, argv, self, is_ary_arg)
    int argc;
    VALUE *argv;
    VALUE self;
    VALUE is_ary_arg;
{
    VALUE event, args, data;
    rb_scan_args(argc, argv, "01*", &event, &args);
    if(!NIL_P(event)) {
        Check_SafeStr(event);
    }
    data = rb_ary_new3(4, rb_block_proc(), event, args, is_ary_arg);
    add_event_call_back(self, event, data);
    return Qnil;
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#on_event([event]){...}
 * 
 *  Defines the callback event.
 *  If argument is omitted, this method defines the callback of all events.
 *    ie = WIN32OLE.new('InternetExplorer.Application')
 *    ev = WIN32OLE_EVENT.new(ie, 'DWebBrowserEvents')
 *    ev.on_event("NavigateComplete") {|url| puts url}
 */
static VALUE
fev_on_event(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    return ev_on_event(argc, argv, self, Qfalse);
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#on_event_with_outargs([event]){...}
 * 
 *  Defines the callback of event.
 *  If you want modify argument in callback, 
 *  you should use this method instead of WIN32OLE_EVENT#on_event.
 */
static VALUE
fev_on_event_with_outargs(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    return ev_on_event(argc, argv, self, Qtrue);
}


void
Init_win32ole()
{
    rb_global_variable(&ary_ole_event);
    ary_ole_event = rb_ary_new();
    id_events = rb_intern("events");

    rb_global_variable(&com_hash);
    com_vtbl.QueryInterface = QueryInterface;
    com_vtbl.AddRef = AddRef;
    com_vtbl.Release = Release;
    com_vtbl.GetTypeInfoCount = GetTypeInfoCount;
    com_vtbl.GetTypeInfo = GetTypeInfo;
    com_vtbl.GetIDsOfNames = GetIDsOfNames;
    com_vtbl.Invoke = Invoke;

    message_filter.QueryInterface = mf_QueryInterface;
    message_filter.AddRef = mf_AddRef;
    message_filter.Release = mf_Release;
    message_filter.HandleInComingCall = mf_HandleInComingCall;
    message_filter.RetryRejectedCall = mf_RetryRejectedCall;
    message_filter.MessagePending = mf_MessagePending;

    com_hash = Data_Wrap_Struct(rb_cData, rb_mark_hash, st_free_table, st_init_numtable());

    cWIN32OLE = rb_define_class("WIN32OLE", rb_cObject);

    rb_define_alloc_func(cWIN32OLE, fole_s_allocate);

    rb_define_method(cWIN32OLE, "initialize", fole_initialize, -1);

    rb_define_singleton_method(cWIN32OLE, "connect", fole_s_connect, -1);
    rb_define_singleton_method(cWIN32OLE, "const_load", fole_s_const_load, -1);

    rb_define_singleton_method(cWIN32OLE, "ole_free", fole_s_free, 1);
    rb_define_singleton_method(cWIN32OLE, "ole_reference_count", fole_s_reference_count, 1);
    rb_define_singleton_method(cWIN32OLE, "ole_show_help", fole_s_show_help, -1);
    rb_define_singleton_method(cWIN32OLE, "codepage", fole_s_get_code_page, 0);
    rb_define_singleton_method(cWIN32OLE, "codepage=", fole_s_set_code_page, 1);


    rb_define_method(cWIN32OLE, "invoke", fole_invoke, -1);
    rb_define_method(cWIN32OLE, "[]", fole_getproperty, -1);
    rb_define_method(cWIN32OLE, "_invoke", fole_invoke2, 3);
    rb_define_method(cWIN32OLE, "_getproperty", fole_getproperty2, 3);
    rb_define_method(cWIN32OLE, "_setproperty", fole_setproperty2, 3);

    /* support propput method that takes an argument */
    rb_define_method(cWIN32OLE, "[]=", fole_setproperty, -1); 

    rb_define_method(cWIN32OLE, "ole_free", fole_free, 0);

    rb_define_method(cWIN32OLE, "each", fole_each, 0);
    rb_define_method(cWIN32OLE, "method_missing", fole_missing, -1);

    /* support setproperty method much like Perl ;-) */
    rb_define_method(cWIN32OLE, "setproperty", fole_setproperty, -1);

    rb_define_method(cWIN32OLE, "ole_methods", fole_methods, 0);
    rb_define_method(cWIN32OLE, "ole_get_methods", fole_get_methods, 0);
    rb_define_method(cWIN32OLE, "ole_put_methods", fole_put_methods, 0);
    rb_define_method(cWIN32OLE, "ole_func_methods", fole_func_methods, 0);

    rb_define_method(cWIN32OLE, "ole_method", fole_method_help, 1);
    rb_define_alias(cWIN32OLE, "ole_method_help", "ole_method");
    rb_define_method(cWIN32OLE, "ole_obj_help", fole_obj_help, 0);
    rb_define_method(cWIN32OLE, "ole_activex_initialize", fole_activex_initialize, 0);

    rb_define_const(cWIN32OLE, "VERSION", rb_str_new2(WIN32OLE_VERSION));
    rb_define_const(cWIN32OLE, "ARGV", rb_ary_new());
    rb_define_const(cWIN32OLE, "CP_ACP"       ,INT2FIX(CP_ACP));
    rb_define_const(cWIN32OLE, "CP_OEMCP"     ,INT2FIX(CP_OEMCP));
    rb_define_const(cWIN32OLE, "CP_MACCP"     ,INT2FIX(CP_MACCP));
    rb_define_const(cWIN32OLE, "CP_THREAD_ACP",INT2FIX(CP_THREAD_ACP));
    rb_define_const(cWIN32OLE, "CP_SYMBOL"    ,INT2FIX(CP_SYMBOL));
    rb_define_const(cWIN32OLE, "CP_UTF7"      ,INT2FIX(CP_UTF7));
    rb_define_const(cWIN32OLE, "CP_UTF8"      ,INT2FIX(CP_UTF8));

    mWIN32OLE_VARIANT = rb_define_module_under(cWIN32OLE, "VARIANT");
    rb_define_const(mWIN32OLE_VARIANT, "VT_I2", INT2FIX(VT_I2));
    rb_define_const(mWIN32OLE_VARIANT, "VT_I4", INT2FIX(VT_I4));
    rb_define_const(mWIN32OLE_VARIANT, "VT_R4", INT2FIX(VT_R4));
    rb_define_const(mWIN32OLE_VARIANT, "VT_R8", INT2FIX(VT_R8));
    rb_define_const(mWIN32OLE_VARIANT, "VT_CY", INT2FIX(VT_CY));
    rb_define_const(mWIN32OLE_VARIANT, "VT_DATE", INT2FIX(VT_DATE));
    rb_define_const(mWIN32OLE_VARIANT, "VT_BSTR", INT2FIX(VT_BSTR));
    rb_define_const(mWIN32OLE_VARIANT, "VT_USERDEFINED", INT2FIX(VT_USERDEFINED));
    rb_define_const(mWIN32OLE_VARIANT, "VT_PTR", INT2FIX(VT_PTR));
    rb_define_const(mWIN32OLE_VARIANT, "VT_DISPATCH", INT2FIX(VT_DISPATCH));
    rb_define_const(mWIN32OLE_VARIANT, "VT_ERROR", INT2FIX(VT_ERROR));
    rb_define_const(mWIN32OLE_VARIANT, "VT_BOOL", INT2FIX(VT_BOOL));
    rb_define_const(mWIN32OLE_VARIANT, "VT_VARIANT", INT2FIX(VT_VARIANT));
    rb_define_const(mWIN32OLE_VARIANT, "VT_UNKNOWN", INT2FIX(VT_UNKNOWN));
    rb_define_const(mWIN32OLE_VARIANT, "VT_I1", INT2FIX(VT_I1));
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI1", INT2FIX(VT_UI1));
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI2", INT2FIX(VT_UI2));
    rb_define_const(mWIN32OLE_VARIANT, "VT_UI4", INT2FIX(VT_UI4));
    rb_define_const(mWIN32OLE_VARIANT, "VT_INT", INT2FIX(VT_INT));
    rb_define_const(mWIN32OLE_VARIANT, "VT_UINT", INT2FIX(VT_UINT));
    rb_define_const(mWIN32OLE_VARIANT, "VT_ARRAY", INT2FIX(VT_ARRAY));
    rb_define_const(mWIN32OLE_VARIANT, "VT_BYREF", INT2FIX(VT_BYREF));
    
    cWIN32OLE_TYPE = rb_define_class("WIN32OLE_TYPE", rb_cObject);
    rb_define_singleton_method(cWIN32OLE_TYPE, "ole_classes", foletype_s_ole_classes, 1);
    rb_define_singleton_method(cWIN32OLE_TYPE, "typelibs", foletype_s_typelibs, 0);
    rb_define_singleton_method(cWIN32OLE_TYPE, "progids", foletype_s_progids, 0);
    rb_define_alloc_func(cWIN32OLE_TYPE, foletype_s_allocate);
    rb_define_method(cWIN32OLE_TYPE, "initialize", foletype_initialize, 2);
    rb_define_method(cWIN32OLE_TYPE, "name", foletype_name, 0);
    rb_define_method(cWIN32OLE_TYPE, "ole_type", foletype_ole_type, 0);
    rb_define_method(cWIN32OLE_TYPE, "guid", foletype_guid, 0);
    rb_define_method(cWIN32OLE_TYPE, "progid", foletype_progid, 0);
    rb_define_method(cWIN32OLE_TYPE, "visible?", foletype_visible, 0);
    rb_define_alias(cWIN32OLE_TYPE, "to_s", "name");

    rb_define_method(cWIN32OLE_TYPE, "major_version", foletype_major_version, 0);
    rb_define_method(cWIN32OLE_TYPE, "minor_version", foletype_minor_version, 0);
    rb_define_method(cWIN32OLE_TYPE, "typekind", foletype_typekind, 0);
    rb_define_method(cWIN32OLE_TYPE, "helpstring", foletype_helpstring, 0);
    rb_define_method(cWIN32OLE_TYPE, "src_type", foletype_src_type, 0);
    rb_define_method(cWIN32OLE_TYPE, "helpfile", foletype_helpfile, 0);
    rb_define_method(cWIN32OLE_TYPE, "helpcontext", foletype_helpcontext, 0);
    rb_define_method(cWIN32OLE_TYPE, "variables", foletype_variables, 0);
    rb_define_method(cWIN32OLE_TYPE, "ole_methods", foletype_methods, -1);

    cWIN32OLE_VARIABLE = rb_define_class("WIN32OLE_VARIABLE", rb_cObject);
    rb_define_method(cWIN32OLE_VARIABLE, "name", folevariable_name, 0);
    rb_define_method(cWIN32OLE_VARIABLE, "ole_type", folevariable_ole_type, 0);
    rb_define_method(cWIN32OLE_VARIABLE, "ole_type_detail", folevariable_ole_type_detail, 0);
    rb_define_method(cWIN32OLE_VARIABLE, "value", folevariable_value, 0);
    rb_define_method(cWIN32OLE_VARIABLE, "visible?", folevariable_visible, 0);
    rb_define_method(cWIN32OLE_VARIABLE, "variable_kind", folevariable_variable_kind, 0);
    rb_define_method(cWIN32OLE_VARIABLE, "varkind", folevariable_varkind, 0);
    rb_define_alias(cWIN32OLE_VARIABLE, "to_s", "name");

    cWIN32OLE_METHOD = rb_define_class("WIN32OLE_METHOD", rb_cObject);
    rb_define_alloc_func(cWIN32OLE_METHOD, folemethod_s_allocate);
    rb_define_method(cWIN32OLE_METHOD, "initialize", folemethod_initialize, 2);

    rb_define_method(cWIN32OLE_METHOD, "name", folemethod_name, 0);
    rb_define_method(cWIN32OLE_METHOD, "return_type", folemethod_return_type, 0);
    rb_define_method(cWIN32OLE_METHOD, "return_vtype", folemethod_return_vtype, 0);
    rb_define_method(cWIN32OLE_METHOD, "return_type_detail", folemethod_return_type_detail, 0);
    rb_define_method(cWIN32OLE_METHOD, "invoke_kind", folemethod_invoke_kind, 0);
    rb_define_method(cWIN32OLE_METHOD, "invkind", folemethod_invkind, 0);
    rb_define_method(cWIN32OLE_METHOD, "visible?", folemethod_visible, 0);
    rb_define_method(cWIN32OLE_METHOD, "event?", folemethod_event, 0);
    rb_define_method(cWIN32OLE_METHOD, "event_interface", folemethod_event_interface, 0);
    rb_define_method(cWIN32OLE_METHOD, "helpstring", folemethod_helpstring, 0);
    rb_define_method(cWIN32OLE_METHOD, "helpfile", folemethod_helpfile, 0);
    rb_define_method(cWIN32OLE_METHOD, "helpcontext", folemethod_helpcontext, 0);
    rb_define_method(cWIN32OLE_METHOD, "dispid", folemethod_dispid, 0);
    rb_define_method(cWIN32OLE_METHOD, "offset_vtbl", folemethod_offset_vtbl, 0);
    rb_define_method(cWIN32OLE_METHOD, "size_params", folemethod_size_params, 0);
    rb_define_method(cWIN32OLE_METHOD, "size_opt_params", folemethod_size_opt_params, 0);
    rb_define_method(cWIN32OLE_METHOD, "params", folemethod_params, 0);
    rb_define_alias(cWIN32OLE_METHOD, "to_s", "name");

    cWIN32OLE_PARAM = rb_define_class("WIN32OLE_PARAM", rb_cObject);
    rb_define_method(cWIN32OLE_PARAM, "name", foleparam_name, 0);
    rb_define_method(cWIN32OLE_PARAM, "ole_type", foleparam_ole_type, 0);
    rb_define_method(cWIN32OLE_PARAM, "ole_type_detail", foleparam_ole_type_detail, 0);
    rb_define_method(cWIN32OLE_PARAM, "input?", foleparam_input, 0);
    rb_define_method(cWIN32OLE_PARAM, "output?", foleparam_output, 0);
    rb_define_method(cWIN32OLE_PARAM, "optional?", foleparam_optional, 0);
    rb_define_method(cWIN32OLE_PARAM, "retval?", foleparam_retval, 0);
    rb_define_method(cWIN32OLE_PARAM, "default", foleparam_default, 0);
    rb_define_alias(cWIN32OLE_PARAM, "to_s", "name");
 
    cWIN32OLE_EVENT = rb_define_class("WIN32OLE_EVENT", rb_cObject);

    rb_define_alloc_func(cWIN32OLE_EVENT, fev_s_allocate);
    rb_define_method(cWIN32OLE_EVENT, "initialize", fev_initialize, -1);
    rb_define_singleton_method(cWIN32OLE_EVENT, "message_loop", fev_s_msg_loop, 0);

    rb_define_method(cWIN32OLE_EVENT, "on_event", fev_on_event, -1);
    rb_define_method(cWIN32OLE_EVENT, "on_event_with_outargs", fev_on_event_with_outargs, -1);
    eWIN32OLE_RUNTIME_ERROR = rb_define_class("WIN32OLERuntimeError", rb_eRuntimeError);
}
