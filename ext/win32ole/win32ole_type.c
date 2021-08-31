#include "win32ole.h"

struct oletypedata {
    ITypeInfo *pTypeInfo;
};

static void oletype_free(void *ptr);
static size_t oletype_size(const void *ptr);
static VALUE foletype_s_ole_classes(VALUE self, VALUE typelib);
static VALUE foletype_s_typelibs(VALUE self);
static VALUE foletype_s_progids(VALUE self);
static VALUE oletype_set_member(VALUE self, ITypeInfo *pTypeInfo, VALUE name);
static VALUE foletype_s_allocate(VALUE klass);
static VALUE oleclass_from_typelib(VALUE self, ITypeLib *pTypeLib, VALUE oleclass);
static VALUE foletype_initialize(VALUE self, VALUE typelib, VALUE oleclass);
static VALUE foletype_name(VALUE self);
static VALUE ole_ole_type(ITypeInfo *pTypeInfo);
static VALUE foletype_ole_type(VALUE self);
static VALUE ole_type_guid(ITypeInfo *pTypeInfo);
static VALUE foletype_guid(VALUE self);
static VALUE ole_type_progid(ITypeInfo *pTypeInfo);
static VALUE foletype_progid(VALUE self);
static VALUE ole_type_visible(ITypeInfo *pTypeInfo);
static VALUE foletype_visible(VALUE self);
static VALUE ole_type_major_version(ITypeInfo *pTypeInfo);
static VALUE foletype_major_version(VALUE self);
static VALUE ole_type_minor_version(ITypeInfo *pTypeInfo);
static VALUE foletype_minor_version(VALUE self);
static VALUE ole_type_typekind(ITypeInfo *pTypeInfo);
static VALUE foletype_typekind(VALUE self);
static VALUE ole_type_helpstring(ITypeInfo *pTypeInfo);
static VALUE foletype_helpstring(VALUE self);
static VALUE ole_type_src_type(ITypeInfo *pTypeInfo);
static VALUE foletype_src_type(VALUE self);
static VALUE ole_type_helpfile(ITypeInfo *pTypeInfo);
static VALUE foletype_helpfile(VALUE self);
static VALUE ole_type_helpcontext(ITypeInfo *pTypeInfo);
static VALUE foletype_helpcontext(VALUE self);
static VALUE ole_variables(ITypeInfo *pTypeInfo);
static VALUE foletype_variables(VALUE self);
static VALUE foletype_methods(VALUE self);
static VALUE foletype_ole_typelib(VALUE self);
static VALUE ole_type_impl_ole_types(ITypeInfo *pTypeInfo, int implflags);
static VALUE foletype_impl_ole_types(VALUE self);
static VALUE foletype_source_ole_types(VALUE self);
static VALUE foletype_default_event_sources(VALUE self);
static VALUE foletype_default_ole_types(VALUE self);
static VALUE foletype_inspect(VALUE self);

static const rb_data_type_t oletype_datatype = {
    "win32ole_type",
    {NULL, oletype_free, oletype_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

/*
 * Document-class: WIN32OLE_TYPE
 *
 *   <code>WIN32OLE_TYPE</code> objects represent OLE type library information.
 */

static void
oletype_free(void *ptr)
{
    struct oletypedata *poletype = ptr;
    OLE_FREE(poletype->pTypeInfo);
    free(poletype);
}

static size_t
oletype_size(const void *ptr)
{
    return ptr ? sizeof(struct oletypedata) : 0;
}

ITypeInfo *itypeinfo(VALUE self)
{
    struct oletypedata *ptype;
    TypedData_Get_Struct(self, struct oletypedata, &oletype_datatype, ptype);
    return ptype->pTypeInfo;
}

VALUE
ole_type_from_itypeinfo(ITypeInfo *pTypeInfo)
{
    ITypeLib *pTypeLib;
    VALUE type = Qnil;
    HRESULT hr;
    unsigned int index;
    BSTR bstr;

    hr = pTypeInfo->lpVtbl->GetContainingTypeLib( pTypeInfo, &pTypeLib, &index );
    if(FAILED(hr)) {
        return Qnil;
    }
    hr = pTypeLib->lpVtbl->GetDocumentation( pTypeLib, index,
                                             &bstr, NULL, NULL, NULL);
    OLE_RELEASE(pTypeLib);
    if (FAILED(hr)) {
        return Qnil;
    }
    type = create_win32ole_type(pTypeInfo, WC2VSTR(bstr));
    return type;
}


/*
 *   call-seq:
 *      WIN32OLE_TYPE.ole_classes(typelib)
 *
 *   Returns array of WIN32OLE_TYPE objects defined by the <i>typelib</i> type library.
 *   This method will be OBSOLETE. Use WIN32OLE_TYPELIB.new(typelib).ole_classes instead.
 */
static VALUE
foletype_s_ole_classes(VALUE self, VALUE typelib)
{
    VALUE obj;

    /*
    rb_warn("%s is obsolete; use %s instead.",
            "WIN32OLE_TYPE.ole_classes",
            "WIN32OLE_TYPELIB.new(typelib).ole_types");
    */
    obj = rb_funcall(cWIN32OLE_TYPELIB, rb_intern("new"), 1, typelib);
    return rb_funcall(obj, rb_intern("ole_types"), 0);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE.typelibs
 *
 *  Returns array of type libraries.
 *  This method will be OBSOLETE. Use WIN32OLE_TYPELIB.typelibs.collect{|t| t.name} instead.
 *
 */
static VALUE
foletype_s_typelibs(VALUE self)
{
    /*
    rb_warn("%s is obsolete. use %s instead.",
            "WIN32OLE_TYPE.typelibs",
            "WIN32OLE_TYPELIB.typelibs.collect{t|t.name}");
    */
    return rb_eval_string("WIN32OLE_TYPELIB.typelibs.collect{|t|t.name}");
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE.progids
 *
 *  Returns array of ProgID.
 */
static VALUE
foletype_s_progids(VALUE self)
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
        if ((v = reg_get_val2(hclsid, "ProgID")) != Qnil)
            rb_ary_push(progids, v);
        if ((v = reg_get_val2(hclsid, "VersionIndependentProgID")) != Qnil)
            rb_ary_push(progids, v);
        RegCloseKey(hclsid);
    }
    RegCloseKey(hclsids);
    return progids;
}

static VALUE
oletype_set_member(VALUE self, ITypeInfo *pTypeInfo, VALUE name)
{
    struct oletypedata *ptype;
    TypedData_Get_Struct(self, struct oletypedata, &oletype_datatype, ptype);
    rb_ivar_set(self, rb_intern("name"), name);
    ptype->pTypeInfo = pTypeInfo;
    OLE_ADDREF(pTypeInfo);
    return self;
}

static VALUE
foletype_s_allocate(VALUE klass)
{
    struct oletypedata *poletype;
    VALUE obj;
    ole_initialize();
    obj = TypedData_Make_Struct(klass,struct oletypedata, &oletype_datatype, poletype);
    poletype->pTypeInfo = NULL;
    return obj;
}

VALUE
create_win32ole_type(ITypeInfo *pTypeInfo, VALUE name)
{
    VALUE obj = foletype_s_allocate(cWIN32OLE_TYPE);
    oletype_set_member(obj, pTypeInfo, name);
    return obj;
}

static VALUE
oleclass_from_typelib(VALUE self, ITypeLib *pTypeLib, VALUE oleclass)
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
foletype_initialize(VALUE self, VALUE typelib, VALUE oleclass)
{
    VALUE file;
    OLECHAR * pbuf;
    ITypeLib *pTypeLib;
    HRESULT hr;

    SafeStringValue(oleclass);
    SafeStringValue(typelib);
    file = typelib_file(typelib);
    if (file == Qnil) {
        file = typelib;
    }
    pbuf = ole_vstr2wc(file);
    hr = LoadTypeLibEx(pbuf, REGKIND_NONE, &pTypeLib);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLERuntimeError, "failed to LoadTypeLibEx");
    SysFreeString(pbuf);
    if (oleclass_from_typelib(self, pTypeLib, oleclass) == Qfalse) {
        OLE_RELEASE(pTypeLib);
        rb_raise(eWIN32OLERuntimeError, "not found `%s` in `%s`",
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
foletype_name(VALUE self)
{
    return rb_ivar_get(self, rb_intern("name"));
}

static VALUE
ole_ole_type(ITypeInfo *pTypeInfo)
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
foletype_ole_type(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_ole_type(pTypeInfo);
}

static VALUE
ole_type_guid(ITypeInfo *pTypeInfo)
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
foletype_guid(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_guid(pTypeInfo);
}

static VALUE
ole_type_progid(ITypeInfo *pTypeInfo)
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
foletype_progid(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_progid(pTypeInfo);
}


static VALUE
ole_type_visible(ITypeInfo *pTypeInfo)
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
 *    WIN32OLE_TYPE#visible?  #=> true or false
 *
 *  Returns true if the OLE class is public.
 *    tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Application')
 *    puts tobj.visible  # => true
 */
static VALUE
foletype_visible(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_visible(pTypeInfo);
}

static VALUE
ole_type_major_version(ITypeInfo *pTypeInfo)
{
    VALUE ver;
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLERuntimeError, "failed to GetTypeAttr");
    ver = RB_INT2FIX(pTypeAttr->wMajorVerNum);
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
foletype_major_version(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_major_version(pTypeInfo);
}

static VALUE
ole_type_minor_version(ITypeInfo *pTypeInfo)
{
    VALUE ver;
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLERuntimeError, "failed to GetTypeAttr");
    ver = RB_INT2FIX(pTypeAttr->wMinorVerNum);
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
foletype_minor_version(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_minor_version(pTypeInfo);
}

static VALUE
ole_type_typekind(ITypeInfo *pTypeInfo)
{
    VALUE typekind;
    TYPEATTR *pTypeAttr;
    HRESULT hr;
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr))
        ole_raise(hr, eWIN32OLERuntimeError, "failed to GetTypeAttr");
    typekind = RB_INT2FIX(pTypeAttr->typekind);
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
foletype_typekind(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_typekind(pTypeInfo);
}

static VALUE
ole_type_helpstring(ITypeInfo *pTypeInfo)
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
foletype_helpstring(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_helpstring(pTypeInfo);
}

static VALUE
ole_type_src_type(ITypeInfo *pTypeInfo)
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
foletype_src_type(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_src_type(pTypeInfo);
}

static VALUE
ole_type_helpfile(ITypeInfo *pTypeInfo)
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
foletype_helpfile(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_helpfile(pTypeInfo);
}

static VALUE
ole_type_helpcontext(ITypeInfo *pTypeInfo)
{
    HRESULT hr;
    DWORD helpcontext;
    hr = ole_docinfo_from_type(pTypeInfo, NULL, NULL,
                               &helpcontext, NULL);
    if(FAILED(hr))
        return Qnil;
    return RB_INT2FIX(helpcontext);
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
foletype_helpcontext(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_helpcontext(pTypeInfo);
}

static VALUE
ole_variables(ITypeInfo *pTypeInfo)
{
    HRESULT hr;
    TYPEATTR *pTypeAttr;
    WORD i;
    UINT len;
    BSTR bstr;
    VARDESC *pVarDesc;
    VALUE var;
    VALUE variables = rb_ary_new();
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLERuntimeError, "failed to GetTypeAttr");
    }

    for(i = 0; i < pTypeAttr->cVars; i++) {
        hr = pTypeInfo->lpVtbl->GetVarDesc(pTypeInfo, i, &pVarDesc);
        if(FAILED(hr))
            continue;
        len = 0;
        hr = pTypeInfo->lpVtbl->GetNames(pTypeInfo, pVarDesc->memid, &bstr,
                                         1, &len);
        if(FAILED(hr) || len == 0 || !bstr)
            continue;

        var = create_win32ole_variable(pTypeInfo, i, WC2VSTR(bstr));
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
foletype_variables(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_variables(pTypeInfo);
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
foletype_methods(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_methods_from_typeinfo(pTypeInfo, INVOKE_FUNC | INVOKE_PROPERTYGET | INVOKE_PROPERTYPUT | INVOKE_PROPERTYPUTREF);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#ole_typelib
 *
 *  Returns the WIN32OLE_TYPELIB object which is including the WIN32OLE_TYPE
 *  object. If it is not found, then returns nil.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Worksheet')
 *     puts tobj.ole_typelib # => 'Microsoft Excel 9.0 Object Library'
 */
static VALUE
foletype_ole_typelib(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_typelib_from_itypeinfo(pTypeInfo);
}

static VALUE
ole_type_impl_ole_types(ITypeInfo *pTypeInfo, int implflags)
{
    HRESULT hr;
    ITypeInfo *pRefTypeInfo;
    HREFTYPE href;
    WORD i;
    VALUE type;
    TYPEATTR *pTypeAttr;
    int flags;

    VALUE types = rb_ary_new();
    hr = OLE_GET_TYPEATTR(pTypeInfo, &pTypeAttr);
    if (FAILED(hr)) {
        return types;
    }
    for (i = 0; i < pTypeAttr->cImplTypes; i++) {
        hr = pTypeInfo->lpVtbl->GetImplTypeFlags(pTypeInfo, i, &flags);
        if (FAILED(hr))
            continue;

        hr = pTypeInfo->lpVtbl->GetRefTypeOfImplType(pTypeInfo, i, &href);
        if (FAILED(hr))
            continue;
        hr = pTypeInfo->lpVtbl->GetRefTypeInfo(pTypeInfo, href, &pRefTypeInfo);
        if (FAILED(hr))
            continue;

        if ((flags & implflags) == implflags) {
            type = ole_type_from_itypeinfo(pRefTypeInfo);
            if (type != Qnil) {
                rb_ary_push(types, type);
            }
        }

        OLE_RELEASE(pRefTypeInfo);
    }
    OLE_RELEASE_TYPEATTR(pTypeInfo, pTypeAttr);
    return types;
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#implemented_ole_types
 *
 *  Returns the array of WIN32OLE_TYPE object which is implemented by the WIN32OLE_TYPE
 *  object.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Excel 9.0 Object Library', 'Worksheet')
 *     p tobj.implemented_ole_types # => [_Worksheet, DocEvents]
 */
static VALUE
foletype_impl_ole_types(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_impl_ole_types(pTypeInfo, 0);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#source_ole_types
 *
 *  Returns the array of WIN32OLE_TYPE object which is implemented by the WIN32OLE_TYPE
 *  object and having IMPLTYPEFLAG_FSOURCE.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Internet Controls', "InternetExplorer")
 *     p tobj.source_ole_types
 *     # => [#<WIN32OLE_TYPE:DWebBrowserEvents2>, #<WIN32OLE_TYPE:DWebBrowserEvents>]
 */
static VALUE
foletype_source_ole_types(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_impl_ole_types(pTypeInfo, IMPLTYPEFLAG_FSOURCE);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#default_event_sources
 *
 *  Returns the array of WIN32OLE_TYPE object which is implemented by the WIN32OLE_TYPE
 *  object and having IMPLTYPEFLAG_FSOURCE and IMPLTYPEFLAG_FDEFAULT.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Internet Controls', "InternetExplorer")
 *     p tobj.default_event_sources  # => [#<WIN32OLE_TYPE:DWebBrowserEvents2>]
 */
static VALUE
foletype_default_event_sources(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_impl_ole_types(pTypeInfo, IMPLTYPEFLAG_FSOURCE|IMPLTYPEFLAG_FDEFAULT);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#default_ole_types
 *
 *  Returns the array of WIN32OLE_TYPE object which is implemented by the WIN32OLE_TYPE
 *  object and having IMPLTYPEFLAG_FDEFAULT.
 *     tobj = WIN32OLE_TYPE.new('Microsoft Internet Controls', "InternetExplorer")
 *     p tobj.default_ole_types
 *     # => [#<WIN32OLE_TYPE:IWebBrowser2>, #<WIN32OLE_TYPE:DWebBrowserEvents2>]
 */
static VALUE
foletype_default_ole_types(VALUE self)
{
    ITypeInfo *pTypeInfo = itypeinfo(self);
    return ole_type_impl_ole_types(pTypeInfo, IMPLTYPEFLAG_FDEFAULT);
}

/*
 *  call-seq:
 *     WIN32OLE_TYPE#inspect -> String
 *
 *  Returns the type name with class name.
 *
 *     ie = WIN32OLE.new('InternetExplorer.Application')
 *     ie.ole_type.inspect => #<WIN32OLE_TYPE:IWebBrowser2>
 */
static VALUE
foletype_inspect(VALUE self)
{
    return default_inspect(self, "WIN32OLE_TYPE");
}

VALUE cWIN32OLE_TYPE;

void Init_win32ole_type(void)
{
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
    rb_define_method(cWIN32OLE_TYPE, "ole_methods", foletype_methods, 0);
    rb_define_method(cWIN32OLE_TYPE, "ole_typelib", foletype_ole_typelib, 0);
    rb_define_method(cWIN32OLE_TYPE, "implemented_ole_types", foletype_impl_ole_types, 0);
    rb_define_method(cWIN32OLE_TYPE, "source_ole_types", foletype_source_ole_types, 0);
    rb_define_method(cWIN32OLE_TYPE, "default_event_sources", foletype_default_event_sources, 0);
    rb_define_method(cWIN32OLE_TYPE, "default_ole_types", foletype_default_ole_types, 0);
    rb_define_method(cWIN32OLE_TYPE, "inspect", foletype_inspect, 0);
}
