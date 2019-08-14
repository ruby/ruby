#include "win32ole.h"

/*
 * Document-class: WIN32OLE_EVENT
 *
 *   <code>WIN32OLE_EVENT</code> objects controls OLE event.
 */

RUBY_EXTERN void rb_write_error_str(VALUE mesg);

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
    const IEventSinkVtbl *lpVtbl;
    DWORD m_cRef;
    IID m_iid;
    long  m_event_id;
    ITypeInfo *pTypeInfo;
}IEVENTSINKOBJ, *PIEVENTSINKOBJ;

struct oleeventdata {
    DWORD dwCookie;
    IConnectionPoint *pConnectionPoint;
    IDispatch *pDispatch;
    long event_id;
};

static VALUE ary_ole_event;
static ID id_events;

VALUE cWIN32OLE_EVENT;

STDMETHODIMP EVENTSINK_QueryInterface(PEVENTSINK, REFIID, LPVOID*);
STDMETHODIMP_(ULONG) EVENTSINK_AddRef(PEVENTSINK);
STDMETHODIMP_(ULONG) EVENTSINK_Release(PEVENTSINK);
STDMETHODIMP EVENTSINK_GetTypeInfoCount(PEVENTSINK, UINT*);
STDMETHODIMP EVENTSINK_GetTypeInfo(PEVENTSINK, UINT, LCID, ITypeInfo**);
STDMETHODIMP EVENTSINK_GetIDsOfNames(PEVENTSINK, REFIID, OLECHAR**, UINT, LCID, DISPID*);
STDMETHODIMP EVENTSINK_Invoke(PEVENTSINK, DISPID, REFIID, LCID, WORD, DISPPARAMS*, VARIANT*, EXCEPINFO*, UINT*);

static const IEventSinkVtbl vtEventSink = {
    EVENTSINK_QueryInterface,
    EVENTSINK_AddRef,
    EVENTSINK_Release,
    EVENTSINK_GetTypeInfoCount,
    EVENTSINK_GetTypeInfo,
    EVENTSINK_GetIDsOfNames,
    EVENTSINK_Invoke,
};

void EVENTSINK_Destructor(PIEVENTSINKOBJ);
static void ole_val2ptr_variant(VALUE val, VARIANT *var);
static void hash2ptr_dispparams(VALUE hash, ITypeInfo *pTypeInfo, DISPID dispid, DISPPARAMS *pdispparams);
static VALUE hash2result(VALUE hash);
static void ary2ptr_dispparams(VALUE ary, DISPPARAMS *pdispparams);
static VALUE exec_callback(VALUE arg);
static VALUE rescue_callback(VALUE arg);
static HRESULT find_iid(VALUE ole, char *pitf, IID *piid, ITypeInfo **ppTypeInfo);
static HRESULT find_coclass(ITypeInfo *pTypeInfo, TYPEATTR *pTypeAttr, ITypeInfo **pTypeInfo2, TYPEATTR **pTypeAttr2);
static HRESULT find_default_source_from_typeinfo(ITypeInfo *pTypeInfo, TYPEATTR *pTypeAttr, ITypeInfo **ppTypeInfo);
static HRESULT find_default_source(VALUE ole, IID *piid, ITypeInfo **ppTypeInfo);
static long ole_search_event_at(VALUE ary, VALUE ev);
static VALUE ole_search_event(VALUE ary, VALUE ev, BOOL  *is_default);
static VALUE ole_search_handler_method(VALUE handler, VALUE ev, BOOL *is_default_handler);
static void ole_delete_event(VALUE ary, VALUE ev);
static void oleevent_free(void *ptr);
static size_t oleevent_size(const void *ptr);
static VALUE fev_s_allocate(VALUE klass);
static VALUE ev_advise(int argc, VALUE *argv, VALUE self);
static VALUE fev_initialize(int argc, VALUE *argv, VALUE self);
static void ole_msg_loop(void);
static VALUE fev_s_msg_loop(VALUE klass);
static void add_event_call_back(VALUE obj, VALUE event, VALUE data);
static VALUE ev_on_event(int argc, VALUE *argv, VALUE self, VALUE is_ary_arg);
static VALUE fev_on_event(int argc, VALUE *argv, VALUE self);
static VALUE fev_on_event_with_outargs(int argc, VALUE *argv, VALUE self);
static VALUE fev_off_event(int argc, VALUE *argv, VALUE self);
static VALUE fev_unadvise(VALUE self);
static VALUE fev_set_handler(VALUE self, VALUE val);
static VALUE fev_get_handler(VALUE self);
static VALUE evs_push(VALUE ev);
static VALUE evs_delete(long i);
static VALUE evs_entry(long i);
static long  evs_length(void);


static const rb_data_type_t oleevent_datatype = {
    "win32ole_event",
    {NULL, oleevent_free, oleevent_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

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
    VALUE ary, obj, event, args, outargv, ev, result;
    VALUE handler = Qnil;
    VALUE arg[3];
    VALUE mid;
    VALUE is_outarg = Qfalse;
    BOOL is_default_handler = FALSE;
    int state;

    PIEVENTSINKOBJ pEV = (PIEVENTSINKOBJ)pEventSink;
    pTypeInfo = pEV->pTypeInfo;
    obj = evs_entry(pEV->m_event_id);
    if (!rb_obj_is_kind_of(obj, cWIN32OLE_EVENT)) {
        return NOERROR;
    }

    ary = rb_ivar_get(obj, id_events);
    if (NIL_P(ary) || !RB_TYPE_P(ary, T_ARRAY)) {
        return NOERROR;
    }
    hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, dispid,
                                     &bstr, 1, &count);
    if (FAILED(hr)) {
        return NOERROR;
    }
    ev = WC2VSTR(bstr);
    event = ole_search_event(ary, ev, &is_default_handler);
    if (RB_TYPE_P(event, T_ARRAY)) {
        handler = rb_ary_entry(event, 0);
        mid = rb_intern("call");
        is_outarg = rb_ary_entry(event, 3);
    } else {
        handler = rb_ivar_get(obj, rb_intern("handler"));
        if (handler == Qnil) {
            return NOERROR;
        }
        mid = ole_search_handler_method(handler, ev, &is_default_handler);
    }
    if (handler == Qnil || mid == Qnil) {
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
    outargv = Qnil;
    if (is_outarg == Qtrue) {
	outargv = rb_ary_new();
        rb_ary_push(args, outargv);
    }

    /*
     * if exception raised in event callback,
     * then you receive cfp consistency error.
     * to avoid this error we use begin rescue end.
     * and the exception raised then error message print
     * and exit ruby process by Win32OLE itself.
     */
    arg[0] = handler;
    arg[1] = mid;
    arg[2] = args;
    result = rb_protect(exec_callback, (VALUE)arg, &state);
    if (state != 0) {
        rescue_callback(Qnil);
    }
    if(RB_TYPE_P(result, T_HASH)) {
        hash2ptr_dispparams(result, pTypeInfo, dispid, pdispparams);
        result = hash2result(result);
    }else if (is_outarg == Qtrue && RB_TYPE_P(outargv, T_ARRAY)) {
        ary2ptr_dispparams(outargv, pdispparams);
    }

    if (pvarResult) {
        VariantInit(pvarResult);
        ole_val2variant(result, pvarResult);
    }

    return NOERROR;
}

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
    PEVENTSINK pEventSink,
    REFIID riid,
    OLECHAR **szNames,
    UINT cNames,
    LCID lcid,
    DISPID *pDispID
    ) {
    ITypeInfo *pTypeInfo;
    PIEVENTSINKOBJ pEV = (PIEVENTSINKOBJ)pEventSink;
    pTypeInfo = pEV->pTypeInfo;
    if (pTypeInfo) {
        return pTypeInfo->lpVtbl->GetIDsOfNames(pTypeInfo, szNames, cNames, pDispID);
    }
    return DISP_E_UNKNOWNNAME;
}

PIEVENTSINKOBJ
EVENTSINK_Constructor(void)
{
    PIEVENTSINKOBJ pEv;
    pEv = ALLOC_N(IEVENTSINKOBJ, 1);
    if(pEv == NULL) return NULL;
    pEv->lpVtbl = &vtEventSink;
    pEv->m_cRef = 0;
    pEv->m_event_id = 0;
    pEv->pTypeInfo = NULL;
    return pEv;
}

void
EVENTSINK_Destructor(
    PIEVENTSINKOBJ pEVObj
    ) {
    if(pEVObj != NULL) {
        OLE_RELEASE(pEVObj->pTypeInfo);
        free(pEVObj);
        pEVObj = NULL;
    }
}

static void
ole_val2ptr_variant(VALUE val, VARIANT *var)
{
    switch (TYPE(val)) {
    case T_STRING:
        if (V_VT(var) == (VT_BSTR | VT_BYREF)) {
            *V_BSTRREF(var) = ole_vstr2wc(val);
        }
        break;
    case T_FIXNUM:
        switch(V_VT(var)) {
        case (VT_UI1 | VT_BYREF) :
            *V_UI1REF(var) = RB_NUM2CHR(val);
            break;
        case (VT_I2 | VT_BYREF) :
            *V_I2REF(var) = (short)RB_NUM2INT(val);
            break;
        case (VT_I4 | VT_BYREF) :
            *V_I4REF(var) = RB_NUM2INT(val);
            break;
        case (VT_R4 | VT_BYREF) :
            *V_R4REF(var) = (float)RB_NUM2INT(val);
            break;
        case (VT_R8 | VT_BYREF) :
            *V_R8REF(var) = RB_NUM2INT(val);
            break;
        default:
            break;
        }
        break;
    case T_FLOAT:
        switch(V_VT(var)) {
        case (VT_I2 | VT_BYREF) :
            *V_I2REF(var) = (short)RB_NUM2INT(val);
            break;
        case (VT_I4 | VT_BYREF) :
            *V_I4REF(var) = RB_NUM2INT(val);
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
hash2ptr_dispparams(VALUE hash, ITypeInfo *pTypeInfo, DISPID dispid, DISPPARAMS *pdispparams)
{
    BSTR *bstrs;
    HRESULT hr;
    UINT len, i;
    VARIANT *pvar;
    VALUE val;
    VALUE key;
    len = 0;
    bstrs = ALLOCA_N(BSTR, pdispparams->cArgs + 1);
    hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, dispid,
                                     bstrs, pdispparams->cArgs + 1,
                                     &len);
    if (FAILED(hr))
	return;

    for (i = 0; i < len - 1; i++) {
	key = WC2VSTR(bstrs[i + 1]);
        val = rb_hash_aref(hash, RB_UINT2NUM(i));
	if (val == Qnil)
	    val = rb_hash_aref(hash, key);
	if (val == Qnil)
	    val = rb_hash_aref(hash, rb_str_intern(key));
        pvar = &pdispparams->rgvarg[pdispparams->cArgs-i-1];
        ole_val2ptr_variant(val, pvar);
    }
}

static VALUE
hash2result(VALUE hash)
{
    VALUE ret = Qnil;
    ret = rb_hash_aref(hash, rb_str_new2("return"));
    if (ret == Qnil)
	ret = rb_hash_aref(hash, rb_str_intern(rb_str_new2("return")));
    return ret;
}

static void
ary2ptr_dispparams(VALUE ary, DISPPARAMS *pdispparams)
{
    int i;
    VALUE v;
    VARIANT *pvar;
    for(i = 0; i < RARRAY_LEN(ary) && (unsigned int) i < pdispparams->cArgs; i++) {
        v = rb_ary_entry(ary, i);
        pvar = &pdispparams->rgvarg[pdispparams->cArgs-i-1];
        ole_val2ptr_variant(v, pvar);
    }
}

static VALUE
exec_callback(VALUE arg)
{
    VALUE *parg = (VALUE *)arg;
    VALUE handler = parg[0];
    VALUE mid = parg[1];
    VALUE args = parg[2];
    return rb_apply(handler, mid, args);
}

static VALUE
rescue_callback(VALUE arg)
{

    VALUE error;
    VALUE e = rb_errinfo();
    VALUE bt = rb_funcall(e, rb_intern("backtrace"), 0);
    VALUE msg = rb_funcall(e, rb_intern("message"), 0);
    bt = rb_ary_entry(bt, 0);
    error = rb_sprintf("%"PRIsVALUE": %"PRIsVALUE" (%s)\n", bt, msg, rb_obj_classname(e));
    rb_write_error_str(error);
    rb_backtrace();
    ruby_finalize();
    exit(-1);

    return Qnil;
}

static HRESULT
find_iid(VALUE ole, char *pitf, IID *piid, ITypeInfo **ppTypeInfo)
{
    HRESULT hr;
    IDispatch *pDispatch;
    ITypeInfo *pTypeInfo;
    ITypeLib *pTypeLib;
    TYPEATTR *pTypeAttr;
    HREFTYPE RefType;
    ITypeInfo *pImplTypeInfo;
    TYPEATTR *pImplTypeAttr;

    struct oledata *pole = NULL;
    unsigned int index;
    unsigned int count;
    int type;
    BSTR bstr;
    char *pstr;

    BOOL is_found = FALSE;
    LCID    lcid = cWIN32OLE_lcid;

    pole = oledata_get_struct(ole);

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
find_coclass(
    ITypeInfo *pTypeInfo,
    TYPEATTR *pTypeAttr,
    ITypeInfo **pCOTypeInfo,
    TYPEATTR **pCOTypeAttr)
{
    HRESULT hr = E_NOINTERFACE;
    ITypeLib *pTypeLib;
    int count;
    BOOL found = FALSE;
    ITypeInfo *pTypeInfo2;
    TYPEATTR *pTypeAttr2;
    int flags;
    int i,j;
    HREFTYPE href;
    ITypeInfo *pRefTypeInfo;
    TYPEATTR *pRefTypeAttr;

    hr = pTypeInfo->lpVtbl->GetContainingTypeLib(pTypeInfo, &pTypeLib, NULL);
    if (FAILED(hr)) {
	return hr;
    }
    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (i = 0; i < count && !found; i++) {
        hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib, i, &pTypeInfo2);
        if (FAILED(hr))
            continue;
        hr = OLE_GET_TYPEATTR(pTypeInfo2, &pTypeAttr2);
        if (FAILED(hr)) {
            OLE_RELEASE(pTypeInfo2);
            continue;
        }
        if (pTypeAttr2->typekind != TKIND_COCLASS) {
            OLE_RELEASE_TYPEATTR(pTypeInfo2, pTypeAttr2);
            OLE_RELEASE(pTypeInfo2);
            continue;
        }
        for (j = 0; j < pTypeAttr2->cImplTypes && !found; j++) {
            hr = pTypeInfo2->lpVtbl->GetImplTypeFlags(pTypeInfo2, j, &flags);
            if (FAILED(hr))
                continue;
            if (!(flags & IMPLTYPEFLAG_FDEFAULT))
                continue;
            hr = pTypeInfo2->lpVtbl->GetRefTypeOfImplType(pTypeInfo2, j, &href);
            if (FAILED(hr))
                continue;
            hr = pTypeInfo2->lpVtbl->GetRefTypeInfo(pTypeInfo2, href, &pRefTypeInfo);
            if (FAILED(hr))
                continue;
            hr = OLE_GET_TYPEATTR(pRefTypeInfo, &pRefTypeAttr);
            if (FAILED(hr))  {
                OLE_RELEASE(pRefTypeInfo);
                continue;
            }
            if (IsEqualGUID(&(pTypeAttr->guid), &(pRefTypeAttr->guid))) {
                found = TRUE;
            }
        }
        if (!found) {
            OLE_RELEASE_TYPEATTR(pTypeInfo2, pTypeAttr2);
            OLE_RELEASE(pTypeInfo2);
        }
    }
    OLE_RELEASE(pTypeLib);
    if (found) {
        *pCOTypeInfo = pTypeInfo2;
        *pCOTypeAttr = pTypeAttr2;
        hr = S_OK;
    } else {
        hr = E_NOINTERFACE;
    }
    return hr;
}

static HRESULT
find_default_source_from_typeinfo(
    ITypeInfo *pTypeInfo,
    TYPEATTR *pTypeAttr,
    ITypeInfo **ppTypeInfo)
{
    int i = 0;
    HRESULT hr = E_NOINTERFACE;
    int flags;
    HREFTYPE hRefType;
    /* Enumerate all implemented types of the COCLASS */
    for (i = 0; i < pTypeAttr->cImplTypes; i++) {
        hr = pTypeInfo->lpVtbl->GetImplTypeFlags(pTypeInfo, i, &flags);
        if (FAILED(hr))
            continue;

        /*
           looking for the [default] [source]
           we just hope that it is a dispinterface :-)
        */
        if ((flags & IMPLTYPEFLAG_FDEFAULT) &&
            (flags & IMPLTYPEFLAG_FSOURCE)) {

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
    return hr;
}

static HRESULT
find_default_source(VALUE ole, IID *piid, ITypeInfo **ppTypeInfo)
{
    HRESULT hr;
    IProvideClassInfo2 *pProvideClassInfo2;
    IProvideClassInfo *pProvideClassInfo;
    void *p;

    IDispatch *pDispatch;
    ITypeInfo *pTypeInfo;
    ITypeInfo *pTypeInfo2 = NULL;
    TYPEATTR *pTypeAttr;
    TYPEATTR *pTypeAttr2 = NULL;

    struct oledata *pole = NULL;

    pole = oledata_get_struct(ole);
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
        if (SUCCEEDED(hr)) {
            hr = find_iid(ole, NULL, piid, ppTypeInfo);
        }
    }
    if (SUCCEEDED(hr)) {
        return hr;
    }
    hr = pDispatch->lpVtbl->QueryInterface(pDispatch,
            &IID_IProvideClassInfo,
            &p);
    if (SUCCEEDED(hr)) {
        pProvideClassInfo = p;
        hr = pProvideClassInfo->lpVtbl->GetClassInfo(pProvideClassInfo,
                                                     &pTypeInfo);
        OLE_RELEASE(pProvideClassInfo);
    }
    if (FAILED(hr)) {
        hr = pDispatch->lpVtbl->GetTypeInfo(pDispatch, 0, cWIN32OLE_lcid, &pTypeInfo );
    }
    if (FAILED(hr))
        return hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        return hr;
    }

    *ppTypeInfo = 0;
    hr = find_default_source_from_typeinfo(pTypeInfo, pTypeAttr, ppTypeInfo);
    if (!*ppTypeInfo) {
        hr = find_coclass(pTypeInfo, pTypeAttr, &pTypeInfo2, &pTypeAttr2);
        if (SUCCEEDED(hr)) {
            hr = find_default_source_from_typeinfo(pTypeInfo2, pTypeAttr2, ppTypeInfo);
            OLE_RELEASE_TYPEATTR(pTypeInfo2, pTypeAttr2);
            OLE_RELEASE(pTypeInfo2);
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

static long
ole_search_event_at(VALUE ary, VALUE ev)
{
    VALUE event;
    VALUE event_name;
    long i, len;
    long ret = -1;
    len = RARRAY_LEN(ary);
    for(i = 0; i < len; i++) {
        event = rb_ary_entry(ary, i);
        event_name = rb_ary_entry(event, 1);
        if(NIL_P(event_name) && NIL_P(ev)) {
            ret = i;
            break;
        }
        else if (RB_TYPE_P(ev, T_STRING) &&
                 RB_TYPE_P(event_name, T_STRING) &&
                 rb_str_cmp(ev, event_name) == 0) {
            ret = i;
            break;
        }
    }
    return ret;
}

static VALUE
ole_search_event(VALUE ary, VALUE ev, BOOL  *is_default)
{
    VALUE event;
    VALUE def_event;
    VALUE event_name;
    int i, len;
    *is_default = FALSE;
    def_event = Qnil;
    len = RARRAY_LEN(ary);
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

static VALUE
ole_search_handler_method(VALUE handler, VALUE ev, BOOL *is_default_handler)
{
    VALUE mid;

    *is_default_handler = FALSE;
    mid = rb_to_id(rb_sprintf("on%"PRIsVALUE, ev));
    if (rb_respond_to(handler, mid)) {
        return mid;
    }
    mid = rb_intern("method_missing");
    if (rb_respond_to(handler, mid)) {
        *is_default_handler = TRUE;
        return mid;
    }
    return Qnil;
}

static void
ole_delete_event(VALUE ary, VALUE ev)
{
    long at = -1;
    at = ole_search_event_at(ary, ev);
    if (at >= 0) {
        rb_ary_delete_at(ary, at);
    }
}


static void
oleevent_free(void *ptr)
{
    struct oleeventdata *poleev = ptr;
    if (poleev->pConnectionPoint) {
        poleev->pConnectionPoint->lpVtbl->Unadvise(poleev->pConnectionPoint, poleev->dwCookie);
        OLE_RELEASE(poleev->pConnectionPoint);
        poleev->pConnectionPoint = NULL;
    }
    OLE_RELEASE(poleev->pDispatch);
    free(poleev);
}

static size_t
oleevent_size(const void *ptr)
{
    return ptr ? sizeof(struct oleeventdata) : 0;
}

static VALUE
fev_s_allocate(VALUE klass)
{
    VALUE obj;
    struct oleeventdata *poleev;
    obj = TypedData_Make_Struct(klass, struct oleeventdata, &oleevent_datatype, poleev);
    poleev->dwCookie = 0;
    poleev->pConnectionPoint = NULL;
    poleev->event_id = 0;
    poleev->pDispatch = NULL;
    return obj;
}

static VALUE
ev_advise(int argc, VALUE *argv, VALUE self)
{

    VALUE ole, itf;
    struct oledata *pole = NULL;
    char *pitf;
    HRESULT hr;
    IID iid;
    ITypeInfo *pTypeInfo = 0;
    IDispatch *pDispatch;
    IConnectionPointContainer *pContainer;
    IConnectionPoint *pConnectionPoint;
    IEVENTSINKOBJ *pIEV;
    DWORD dwCookie;
    struct oleeventdata *poleev;
    void *p;

    rb_scan_args(argc, argv, "11", &ole, &itf);

    if (!rb_obj_is_kind_of(ole, cWIN32OLE)) {
        rb_raise(rb_eTypeError, "1st parameter must be WIN32OLE object");
    }

    if(!RB_TYPE_P(itf, T_NIL)) {
        pitf = StringValuePtr(itf);
        if (rb_safe_level() > 0 && OBJ_TAINTED(itf)) {
            rb_raise(rb_eSecurityError, "insecure event creation - `%s'",
                     StringValuePtr(itf));
        }
        hr = find_iid(ole, pitf, &iid, &pTypeInfo);
    }
    else {
        hr = find_default_source(ole, &iid, &pTypeInfo);
    }
    if (FAILED(hr)) {
        ole_raise(hr, rb_eRuntimeError, "interface not found");
    }

    pole = oledata_get_struct(ole);
    pDispatch = pole->pDispatch;
    hr = pDispatch->lpVtbl->QueryInterface(pDispatch,
                                           &IID_IConnectionPointContainer,
                                           &p);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        ole_raise(hr, eWIN32OLEQueryInterfaceError,
                  "failed to query IConnectionPointContainer");
    }
    pContainer = p;

    hr = pContainer->lpVtbl->FindConnectionPoint(pContainer,
                                                 &iid,
                                                 &pConnectionPoint);
    OLE_RELEASE(pContainer);
    if (FAILED(hr)) {
        OLE_RELEASE(pTypeInfo);
        ole_raise(hr, eWIN32OLEQueryInterfaceError, "failed to query IConnectionPoint");
    }
    pIEV = EVENTSINK_Constructor();
    pIEV->m_iid = iid;
    hr = pConnectionPoint->lpVtbl->Advise(pConnectionPoint,
                                          (IUnknown*)pIEV,
                                          &dwCookie);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLEQueryInterfaceError, "Advise Error");
    }

    TypedData_Get_Struct(self, struct oleeventdata, &oleevent_datatype, poleev);
    pIEV->m_event_id = evs_length();
    pIEV->pTypeInfo = pTypeInfo;
    poleev->dwCookie = dwCookie;
    poleev->pConnectionPoint = pConnectionPoint;
    poleev->event_id = pIEV->m_event_id;
    poleev->pDispatch = pDispatch;
    OLE_ADDREF(pDispatch);

    return self;
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
fev_initialize(int argc, VALUE *argv, VALUE self)
{
    ev_advise(argc, argv, self);
    evs_push(self);
    rb_ivar_set(self, id_events, rb_ary_new());
    fev_set_handler(self, Qnil);
    return self;
}

static void
ole_msg_loop(void)
{
    MSG msg;
    while(PeekMessage(&msg,NULL,0,0,PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT.message_loop
 *
 *  Translates and dispatches Windows message.
 */
static VALUE
fev_s_msg_loop(VALUE klass)
{
    ole_msg_loop();
    return Qnil;
}

static void
add_event_call_back(VALUE obj, VALUE event, VALUE data)
{
    VALUE events = rb_ivar_get(obj, id_events);
    if (NIL_P(events) || !RB_TYPE_P(events, T_ARRAY)) {
        events = rb_ary_new();
        rb_ivar_set(obj, id_events, events);
    }
    ole_delete_event(events, event);
    rb_ary_push(events, data);
}

static VALUE
ev_on_event(int argc, VALUE *argv, VALUE self, VALUE is_ary_arg)
{
    struct oleeventdata *poleev;
    VALUE event, args, data;
    TypedData_Get_Struct(self, struct oleeventdata, &oleevent_datatype, poleev);
    if (poleev->pConnectionPoint == NULL) {
        rb_raise(eWIN32OLERuntimeError, "IConnectionPoint not found. You must call advise at first.");
    }
    rb_scan_args(argc, argv, "01*", &event, &args);
    if(!NIL_P(event)) {
        if(!RB_TYPE_P(event, T_STRING) && !RB_TYPE_P(event, T_SYMBOL)) {
            rb_raise(rb_eTypeError, "wrong argument type (expected String or Symbol)");
        }
        if (RB_TYPE_P(event, T_SYMBOL)) {
            event = rb_sym2str(event);
        }
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
 *  If you want to modify reference argument in callback, return hash in
 *  callback. If you want to return value to OLE server as result of callback
 *  use `return' or :return.
 *
 *    ie = WIN32OLE.new('InternetExplorer.Application')
 *    ev = WIN32OLE_EVENT.new(ie)
 *    ev.on_event("NavigateComplete") {|url| puts url}
 *    ev.on_event() {|ev, *args| puts "#{ev} fired"}
 *
 *    ev.on_event("BeforeNavigate2") {|*args|
 *      ...
 *      # set true to BeforeNavigate reference argument `Cancel'.
 *      # Cancel is 7-th argument of BeforeNavigate,
 *      # so you can use 6 as key of hash instead of 'Cancel'.
 *      # The argument is counted from 0.
 *      # The hash key of 0 means first argument.)
 *      {:Cancel => true}  # or {'Cancel' => true} or {6 => true}
 *    }
 *
 *    ev.on_event(...) {|*args|
 *      {:return => 1, :xxx => yyy}
 *    }
 */
static VALUE
fev_on_event(int argc, VALUE *argv, VALUE self)
{
    return ev_on_event(argc, argv, self, Qfalse);
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#on_event_with_outargs([event]){...}
 *
 *  Defines the callback of event.
 *  If you want modify argument in callback,
 *  you could use this method instead of WIN32OLE_EVENT#on_event.
 *
 *    ie = WIN32OLE.new('InternetExplorer.Application')
 *    ev = WIN32OLE_EVENT.new(ie)
 *    ev.on_event_with_outargs('BeforeNavigate2') {|*args|
 *      args.last[6] = true
 *    }
 */
static VALUE
fev_on_event_with_outargs(int argc, VALUE *argv, VALUE self)
{
    return ev_on_event(argc, argv, self, Qtrue);
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#off_event([event])
 *
 *  removes the callback of event.
 *
 *    ie = WIN32OLE.new('InternetExplorer.Application')
 *    ev = WIN32OLE_EVENT.new(ie)
 *    ev.on_event('BeforeNavigate2') {|*args|
 *      args.last[6] = true
 *    }
 *      ...
 *    ev.off_event('BeforeNavigate2')
 *      ...
 */
static VALUE
fev_off_event(int argc, VALUE *argv, VALUE self)
{
    VALUE event = Qnil;
    VALUE events;

    rb_scan_args(argc, argv, "01", &event);
    if(!NIL_P(event)) {
        if(!RB_TYPE_P(event, T_STRING) && !RB_TYPE_P(event, T_SYMBOL)) {
            rb_raise(rb_eTypeError, "wrong argument type (expected String or Symbol)");
        }
        if (RB_TYPE_P(event, T_SYMBOL)) {
            event = rb_sym2str(event);
        }
    }
    events = rb_ivar_get(self, id_events);
    if (NIL_P(events)) {
        return Qnil;
    }
    ole_delete_event(events, event);
    return Qnil;
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#unadvise -> nil
 *
 *  disconnects OLE server. If this method called, then the WIN32OLE_EVENT object
 *  does not receive the OLE server event any more.
 *  This method is trial implementation.
 *
 *      ie = WIN32OLE.new('InternetExplorer.Application')
 *      ev = WIN32OLE_EVENT.new(ie)
 *      ev.on_event() {...}
 *         ...
 *      ev.unadvise
 *
 */
static VALUE
fev_unadvise(VALUE self)
{
    struct oleeventdata *poleev;
    TypedData_Get_Struct(self, struct oleeventdata, &oleevent_datatype, poleev);
    if (poleev->pConnectionPoint) {
        ole_msg_loop();
        evs_delete(poleev->event_id);
        poleev->pConnectionPoint->lpVtbl->Unadvise(poleev->pConnectionPoint, poleev->dwCookie);
        OLE_RELEASE(poleev->pConnectionPoint);
        poleev->pConnectionPoint = NULL;
    }
    OLE_FREE(poleev->pDispatch);
    return Qnil;
}

static VALUE
evs_push(VALUE ev)
{
    return rb_ary_push(ary_ole_event, ev);
}

static VALUE
evs_delete(long i)
{
    rb_ary_store(ary_ole_event, i, Qnil);
    return Qnil;
}

static VALUE
evs_entry(long i)
{
    return rb_ary_entry(ary_ole_event, i);
}

static long
evs_length(void)
{
    return RARRAY_LEN(ary_ole_event);
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#handler=
 *
 *  sets event handler object. If handler object has onXXX
 *  method according to XXX event, then onXXX method is called
 *  when XXX event occurs.
 *
 *  If handler object has method_missing and there is no
 *  method according to the event, then method_missing
 *  called and 1-st argument is event name.
 *
 *  If handler object has onXXX method and there is block
 *  defined by WIN32OLE_EVENT#on_event('XXX'){},
 *  then block is executed but handler object method is not called
 *  when XXX event occurs.
 *
 *      class Handler
 *        def onStatusTextChange(text)
 *          puts "StatusTextChanged"
 *        end
 *        def onPropertyChange(prop)
 *          puts "PropertyChanged"
 *        end
 *        def method_missing(ev, *arg)
 *          puts "other event #{ev}"
 *        end
 *      end
 *
 *      handler = Handler.new
 *      ie = WIN32OLE.new('InternetExplorer.Application')
 *      ev = WIN32OLE_EVENT.new(ie)
 *      ev.on_event("StatusTextChange") {|*args|
 *        puts "this block executed."
 *        puts "handler.onStatusTextChange method is not called."
 *      }
 *      ev.handler = handler
 *
 */
static VALUE
fev_set_handler(VALUE self, VALUE val)
{
    return rb_ivar_set(self, rb_intern("handler"), val);
}

/*
 *  call-seq:
 *     WIN32OLE_EVENT#handler
 *
 *  returns handler object.
 *
 */
static VALUE
fev_get_handler(VALUE self)
{
    return rb_ivar_get(self, rb_intern("handler"));
}

void
Init_win32ole_event(void)
{
#undef rb_intern
    ary_ole_event = rb_ary_new();
    rb_gc_register_mark_object(ary_ole_event);
    id_events = rb_intern("events");
    cWIN32OLE_EVENT = rb_define_class("WIN32OLE_EVENT", rb_cObject);
    rb_define_singleton_method(cWIN32OLE_EVENT, "message_loop", fev_s_msg_loop, 0);
    rb_define_alloc_func(cWIN32OLE_EVENT, fev_s_allocate);
    rb_define_method(cWIN32OLE_EVENT, "initialize", fev_initialize, -1);
    rb_define_method(cWIN32OLE_EVENT, "on_event", fev_on_event, -1);
    rb_define_method(cWIN32OLE_EVENT, "on_event_with_outargs", fev_on_event_with_outargs, -1);
    rb_define_method(cWIN32OLE_EVENT, "off_event", fev_off_event, -1);
    rb_define_method(cWIN32OLE_EVENT, "unadvise", fev_unadvise, 0);
    rb_define_method(cWIN32OLE_EVENT, "handler=", fev_set_handler, 1);
    rb_define_method(cWIN32OLE_EVENT, "handler", fev_get_handler, 0);
}
