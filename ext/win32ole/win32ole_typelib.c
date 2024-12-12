#include "win32ole.h"

struct oletypelibdata {
    ITypeLib *pTypeLib;
};

static VALUE reg_get_typelib_file_path(HKEY hkey);
static VALUE oletypelib_path(VALUE guid, VALUE version);
static HRESULT oletypelib_from_guid(VALUE guid, VALUE version, ITypeLib **ppTypeLib);
static VALUE foletypelib_s_typelibs(VALUE self);
static VALUE oletypelib_set_member(VALUE self, ITypeLib *pTypeLib);
static void oletypelib_free(void *ptr);
static size_t oletypelib_size(const void *ptr);
static VALUE foletypelib_s_allocate(VALUE klass);
static VALUE oletypelib_search_registry(VALUE self, VALUE typelib);
static void oletypelib_get_libattr(ITypeLib *pTypeLib, TLIBATTR **ppTLibAttr);
static VALUE oletypelib_search_registry2(VALUE self, VALUE args);
static VALUE foletypelib_initialize(VALUE self, VALUE args);
static VALUE foletypelib_guid(VALUE self);
static VALUE foletypelib_name(VALUE self);
static VALUE make_version_str(VALUE major, VALUE minor);
static VALUE foletypelib_version(VALUE self);
static VALUE foletypelib_major_version(VALUE self);
static VALUE foletypelib_minor_version(VALUE self);
static VALUE foletypelib_path(VALUE self);
static VALUE foletypelib_visible(VALUE self);
static VALUE foletypelib_library_name(VALUE self);
static VALUE ole_types_from_typelib(ITypeLib *pTypeLib, VALUE classes);
static VALUE typelib_file_from_typelib(VALUE ole);
static VALUE typelib_file_from_clsid(VALUE ole);
static VALUE foletypelib_ole_types(VALUE self);
static VALUE foletypelib_inspect(VALUE self);

static const rb_data_type_t oletypelib_datatype = {
    "win32ole_typelib",
    {NULL, oletypelib_free, oletypelib_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
reg_get_typelib_file_path(HKEY hkey)
{
    VALUE path = Qnil;
    path = reg_get_val2(hkey, "win64");
    if (path != Qnil) {
        return path;
    }
    path = reg_get_val2(hkey, "win32");
    if (path != Qnil) {
        return path;
    }
    path = reg_get_val2(hkey, "win16");
    return path;
}

static VALUE
oletypelib_path(VALUE guid, VALUE version)
{
    int k;
    LONG err;
    HKEY hkey;
    HKEY hlang;
    VALUE lang;
    VALUE path = Qnil;

    VALUE key = rb_str_new2("TypeLib\\");
    rb_str_concat(key, guid);
    rb_str_cat2(key, "\\");
    rb_str_concat(key, version);

    err = reg_open_vkey(HKEY_CLASSES_ROOT, key, &hkey);
    if (err != ERROR_SUCCESS) {
        return Qnil;
    }
    for(k = 0; path == Qnil; k++) {
        lang = reg_enum_key(hkey, k);
        if (lang == Qnil)
            break;
        err = reg_open_vkey(hkey, lang, &hlang);
        if (err == ERROR_SUCCESS) {
            path = reg_get_typelib_file_path(hlang);
            RegCloseKey(hlang);
        }
    }
    RegCloseKey(hkey);
    return path;
}

static HRESULT
oletypelib_from_guid(VALUE guid, VALUE version, ITypeLib **ppTypeLib)
{
    VALUE path;
    OLECHAR *pBuf;
    HRESULT hr;
    path = oletypelib_path(guid, version);
    if (path == Qnil) {
        return E_UNEXPECTED;
    }
    pBuf = ole_vstr2wc(path);
    hr = LoadTypeLibEx(pBuf, REGKIND_NONE, ppTypeLib);
    SysFreeString(pBuf);
    return hr;
}

ITypeLib *
itypelib(VALUE self)
{
    struct oletypelibdata *ptlib;
    TypedData_Get_Struct(self, struct oletypelibdata, &oletypelib_datatype, ptlib);
    return ptlib->pTypeLib;
}

VALUE
ole_typelib_from_itypeinfo(ITypeInfo *pTypeInfo)
{
    HRESULT hr;
    ITypeLib *pTypeLib;
    unsigned int index;
    VALUE retval = Qnil;

    hr = pTypeInfo->lpVtbl->GetContainingTypeLib(pTypeInfo, &pTypeLib, &index);
    if(FAILED(hr)) {
        return Qnil;
    }
    retval = create_win32ole_typelib(pTypeLib);
    return retval;
}

/*
 * Document-class: WIN32OLE::TypeLib
 *
 *   +WIN32OLE::TypeLib+ objects represent OLE tyblib information.
 */

/*
 *  call-seq:
 *
 *     typelibs
 *
 *  Returns the array of WIN32OLE::TypeLib object.
 *
 *     tlibs = WIN32OLE::TypeLib.typelibs
 *
 */
static VALUE
foletypelib_s_typelibs(VALUE self)
{
    HKEY htypelib, hguid;
    DWORD i, j;
    LONG err;
    VALUE guid;
    VALUE version;
    VALUE name = Qnil;
    VALUE typelibs = rb_ary_new();
    VALUE typelib = Qnil;
    HRESULT hr;
    ITypeLib *pTypeLib;

    err = reg_open_key(HKEY_CLASSES_ROOT, "TypeLib", &htypelib);
    if(err != ERROR_SUCCESS) {
        return typelibs;
    }
    for(i = 0; ; i++) {
        guid = reg_enum_key(htypelib, i);
        if (guid == Qnil)
            break;
        err = reg_open_vkey(htypelib, guid, &hguid);
        if (err != ERROR_SUCCESS)
            continue;
        for(j = 0; ; j++) {
            version = reg_enum_key(hguid, j);
            if (version == Qnil)
                break;
            if ( (name = reg_get_val2(hguid, StringValuePtr(version))) != Qnil ) {
                hr = oletypelib_from_guid(guid, version, &pTypeLib);
                if (SUCCEEDED(hr)) {
                    typelib = create_win32ole_typelib(pTypeLib);
                    rb_ary_push(typelibs, typelib);
                }
            }
        }
        RegCloseKey(hguid);
    }
    RegCloseKey(htypelib);
    return typelibs;
}

static VALUE
oletypelib_set_member(VALUE self, ITypeLib *pTypeLib)
{
    struct oletypelibdata *ptlib;
    TypedData_Get_Struct(self, struct oletypelibdata, &oletypelib_datatype, ptlib);
    ptlib->pTypeLib = pTypeLib;
    return self;
}

static void
oletypelib_free(void *ptr)
{
    struct oletypelibdata *poletypelib = ptr;
    OLE_FREE(poletypelib->pTypeLib);
    free(poletypelib);
}

static size_t
oletypelib_size(const void *ptr)
{
    return ptr ? sizeof(struct oletypelibdata) : 0;
}

static VALUE
foletypelib_s_allocate(VALUE klass)
{
    struct oletypelibdata *poletypelib;
    VALUE obj;
    ole_initialize();
    obj = TypedData_Make_Struct(klass, struct oletypelibdata, &oletypelib_datatype, poletypelib);
    poletypelib->pTypeLib = NULL;
    return obj;
}

VALUE
create_win32ole_typelib(ITypeLib *pTypeLib)
{
    VALUE obj = foletypelib_s_allocate(cWIN32OLE_TYPELIB);
    oletypelib_set_member(obj, pTypeLib);
    return obj;
}

static VALUE
oletypelib_search_registry(VALUE self, VALUE typelib)
{
    HKEY htypelib, hguid, hversion;
    DWORD i, j;
    LONG err;
    VALUE found = Qfalse;
    VALUE tlib;
    VALUE guid;
    VALUE ver;
    HRESULT hr;
    ITypeLib *pTypeLib;

    err = reg_open_key(HKEY_CLASSES_ROOT, "TypeLib", &htypelib);
    if(err != ERROR_SUCCESS) {
        return Qfalse;
    }
    for(i = 0; !found; i++) {
        guid = reg_enum_key(htypelib, i);
        if (guid == Qnil)
            break;
        err = reg_open_vkey(htypelib, guid, &hguid);
        if (err != ERROR_SUCCESS)
            continue;
        for(j = 0; found == Qfalse; j++) {
            ver = reg_enum_key(hguid, j);
            if (ver == Qnil)
                break;
            err = reg_open_vkey(hguid, ver, &hversion);
            if (err != ERROR_SUCCESS)
                continue;
            tlib = reg_get_val(hversion, NULL);
            if (tlib == Qnil) {
                RegCloseKey(hversion);
                continue;
            }
            if (rb_str_cmp(typelib, tlib) == 0) {
                hr = oletypelib_from_guid(guid, ver, &pTypeLib);
                if (SUCCEEDED(hr)) {
                    oletypelib_set_member(self, pTypeLib);
                    found = Qtrue;
                }
            }
            RegCloseKey(hversion);
        }
        RegCloseKey(hguid);
    }
    RegCloseKey(htypelib);
    return  found;
}

static void
oletypelib_get_libattr(ITypeLib *pTypeLib, TLIBATTR **ppTLibAttr)
{
    HRESULT hr;
    hr = pTypeLib->lpVtbl->GetLibAttr(pTypeLib, ppTLibAttr);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLERuntimeError,
                  "failed to get library attribute(TLIBATTR) from ITypeLib");
    }
}

static VALUE
oletypelib_search_registry2(VALUE self, VALUE args)
{
    HKEY htypelib, hguid, hversion;
    double fver;
    DWORD j;
    LONG err;
    VALUE found = Qfalse;
    VALUE tlib;
    VALUE ver;
    VALUE version_str;
    VALUE version = Qnil;
    VALUE typelib = Qnil;
    HRESULT hr;
    ITypeLib *pTypeLib;

    VALUE guid = rb_ary_entry(args, 0);
    version_str = make_version_str(rb_ary_entry(args, 1), rb_ary_entry(args, 2));

    err = reg_open_key(HKEY_CLASSES_ROOT, "TypeLib", &htypelib);
    if(err != ERROR_SUCCESS) {
        return Qfalse;
    }
    err = reg_open_vkey(htypelib, guid, &hguid);
    if (err != ERROR_SUCCESS) {
        RegCloseKey(htypelib);
        return Qfalse;
    }
    if (version_str != Qnil) {
        err = reg_open_vkey(hguid, version_str, &hversion);
        if (err == ERROR_SUCCESS) {
            tlib = reg_get_val(hversion, NULL);
            if (tlib != Qnil) {
                typelib = tlib;
                version = version_str;
            }
        }
        RegCloseKey(hversion);
    } else {
        fver = 0.0;
        for(j = 0; ;j++) {
            ver = reg_enum_key(hguid, j);
            if (ver == Qnil)
                break;
            err = reg_open_vkey(hguid, ver, &hversion);
            if (err != ERROR_SUCCESS)
                continue;
            tlib = reg_get_val(hversion, NULL);
            if (tlib == Qnil) {
                RegCloseKey(hversion);
                continue;
            }
            if (fver < atof(StringValuePtr(ver))) {
                fver = atof(StringValuePtr(ver));
                version = ver;
                typelib = tlib;
            }
            RegCloseKey(hversion);
        }
    }
    RegCloseKey(hguid);
    RegCloseKey(htypelib);
    if (typelib != Qnil) {
        hr = oletypelib_from_guid(guid, version, &pTypeLib);
        if (SUCCEEDED(hr)) {
            found = Qtrue;
            oletypelib_set_member(self, pTypeLib);
        }
    }
    return found;
}


/*
 * call-seq:
 *    new(typelib [, version1, version2]) -> WIN32OLE::TypeLib object
 *
 * Returns a new WIN32OLE::TypeLib object.
 *
 * The first argument <i>typelib</i>  specifies OLE type library name or GUID or
 * OLE library file.
 * The second argument is major version or version of the type library.
 * The third argument is minor version.
 * The second argument and third argument are optional.
 * If the first argument is type library name, then the second and third argument
 * are ignored.
 *
 *     tlib1 = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     tlib2 = WIN32OLE::TypeLib.new('{00020813-0000-0000-C000-000000000046}')
 *     tlib3 = WIN32OLE::TypeLib.new('{00020813-0000-0000-C000-000000000046}', 1.3)
 *     tlib4 = WIN32OLE::TypeLib.new('{00020813-0000-0000-C000-000000000046}', 1, 3)
 *     tlib5 = WIN32OLE::TypeLib.new("C:\\WINNT\\SYSTEM32\\SHELL32.DLL")
 *     puts tlib1.name  # -> 'Microsoft Excel 9.0 Object Library'
 *     puts tlib2.name  # -> 'Microsoft Excel 9.0 Object Library'
 *     puts tlib3.name  # -> 'Microsoft Excel 9.0 Object Library'
 *     puts tlib4.name  # -> 'Microsoft Excel 9.0 Object Library'
 *     puts tlib5.name  # -> 'Microsoft Shell Controls And Automation'
 *
 */
static VALUE
foletypelib_initialize(VALUE self, VALUE args)
{
    VALUE found = Qfalse;
    VALUE typelib = Qnil;
    int len = 0;
    OLECHAR * pbuf;
    ITypeLib *pTypeLib;
    HRESULT hr = S_OK;

    len = RARRAY_LEN(args);
    rb_check_arity(len, 1, 3);

    typelib = rb_ary_entry(args, 0);

    SafeStringValue(typelib);

    found = oletypelib_search_registry(self, typelib);
    if (found == Qfalse) {
        found = oletypelib_search_registry2(self, args);
    }
    if (found == Qfalse) {
        pbuf = ole_vstr2wc(typelib);
        hr = LoadTypeLibEx(pbuf, REGKIND_NONE, &pTypeLib);
        SysFreeString(pbuf);
        if (SUCCEEDED(hr)) {
            found = Qtrue;
            oletypelib_set_member(self, pTypeLib);
        }
    }

    if (found == Qfalse) {
        rb_raise(eWIN32OLERuntimeError, "not found type library `%s`",
                 StringValuePtr(typelib));
    }
    return self;
}

/*
 *  call-seq:
 *     guid -> The guid string.
 *
 *  Returns guid string which specifies type library.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     guid = tlib.guid # -> '{00020813-0000-0000-C000-000000000046}'
 */
static VALUE
foletypelib_guid(VALUE self)
{
    ITypeLib *pTypeLib;
    OLECHAR bstr[80];
    VALUE guid = Qnil;
    int len;
    TLIBATTR *pTLibAttr;

    pTypeLib = itypelib(self);
    oletypelib_get_libattr(pTypeLib, &pTLibAttr);
    len = StringFromGUID2(&pTLibAttr->guid, bstr, sizeof(bstr)/sizeof(OLECHAR));
    if (len > 3) {
        guid = ole_wc2vstr(bstr, FALSE);
    }
    pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
    return guid;
}

/*
 *  call-seq:
 *     name -> The type library name
 *
 *  Returns the type library name.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     name = tlib.name # -> 'Microsoft Excel 9.0 Object Library'
 */
static VALUE
foletypelib_name(VALUE self)
{
    ITypeLib *pTypeLib;
    HRESULT hr;
    BSTR bstr;
    VALUE name;
    pTypeLib = itypelib(self);
    hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, -1,
                                            NULL, &bstr, NULL, NULL);

    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLERuntimeError, "failed to get name from ITypeLib");
    }
    name = WC2VSTR(bstr);
    return name;
}

static VALUE
make_version_str(VALUE major, VALUE minor)
{
    VALUE version_str = Qnil;
    VALUE minor_str = Qnil;
    if (major == Qnil) {
        return Qnil;
    }
    version_str = rb_String(major);
    if (minor != Qnil) {
        minor_str = rb_String(minor);
        rb_str_cat2(version_str, ".");
        rb_str_append(version_str, minor_str);
    }
    return version_str;
}

/*
 *  call-seq:
 *     version -> The type library version String object.
 *
 *  Returns the type library version.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     puts tlib.version #-> "1.3"
 */
static VALUE
foletypelib_version(VALUE self)
{
    TLIBATTR *pTLibAttr;
    ITypeLib *pTypeLib;
    VALUE version;

    pTypeLib = itypelib(self);
    oletypelib_get_libattr(pTypeLib, &pTLibAttr);
    version = rb_sprintf("%d.%d", pTLibAttr->wMajorVerNum, pTLibAttr->wMinorVerNum);
    pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
    return version;
}

/*
 *  call-seq:
 *     major_version -> The type library major version.
 *
 *  Returns the type library major version.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     puts tlib.major_version # -> 1
 */
static VALUE
foletypelib_major_version(VALUE self)
{
    TLIBATTR *pTLibAttr;
    VALUE major;
    ITypeLib *pTypeLib;
    pTypeLib = itypelib(self);
    oletypelib_get_libattr(pTypeLib, &pTLibAttr);

    major =  RB_INT2NUM(pTLibAttr->wMajorVerNum);
    pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
    return major;
}

/*
 *  call-seq:
 *     minor_version -> The type library minor version.
 *
 *  Returns the type library minor version.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     puts tlib.minor_version # -> 3
 */
static VALUE
foletypelib_minor_version(VALUE self)
{
    TLIBATTR *pTLibAttr;
    VALUE minor;
    ITypeLib *pTypeLib;
    pTypeLib = itypelib(self);
    oletypelib_get_libattr(pTypeLib, &pTLibAttr);
    minor =  RB_INT2NUM(pTLibAttr->wMinorVerNum);
    pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
    return minor;
}

/*
 *  call-seq:
 *     path -> The type library file path.
 *
 *  Returns the type library file path.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     puts tlib.path #-> 'C:\...\EXCEL9.OLB'
 */
static VALUE
foletypelib_path(VALUE self)
{
    TLIBATTR *pTLibAttr;
    HRESULT hr = S_OK;
    BSTR bstr;
    LCID lcid = cWIN32OLE_lcid;
    VALUE path;
    ITypeLib *pTypeLib;

    pTypeLib = itypelib(self);
    oletypelib_get_libattr(pTypeLib, &pTLibAttr);
    hr = QueryPathOfRegTypeLib(&pTLibAttr->guid,
                               pTLibAttr->wMajorVerNum,
                               pTLibAttr->wMinorVerNum,
                               lcid,
                               &bstr);
    if (FAILED(hr)) {
        pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
        ole_raise(hr, eWIN32OLERuntimeError, "failed to QueryPathOfRegTypeTypeLib");
    }

    pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
    path = WC2VSTR(bstr);
    return path;
}

/*
 *  call-seq:
 *     visible?
 *
 *  Returns true if the type library information is not hidden.
 *  If wLibFlags of TLIBATTR is 0 or LIBFLAG_FRESTRICTED or LIBFLAG_FHIDDEN,
 *  the method returns false, otherwise, returns true.
 *  If the method fails to access the TLIBATTR information, then
 *  WIN32OLE::RuntimeError is raised.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     tlib.visible? # => true
 */
static VALUE
foletypelib_visible(VALUE self)
{
    ITypeLib *pTypeLib = NULL;
    VALUE visible = Qtrue;
    TLIBATTR *pTLibAttr;

    pTypeLib = itypelib(self);
    oletypelib_get_libattr(pTypeLib, &pTLibAttr);

    if ((pTLibAttr->wLibFlags == 0) ||
        (pTLibAttr->wLibFlags & LIBFLAG_FRESTRICTED) ||
        (pTLibAttr->wLibFlags & LIBFLAG_FHIDDEN)) {
        visible = Qfalse;
    }
    pTypeLib->lpVtbl->ReleaseTLibAttr(pTypeLib, pTLibAttr);
    return visible;
}

/*
 *  call-seq:
 *     library_name
 *
 *  Returns library name.
 *  If the method fails to access library name, WIN32OLE::RuntimeError is raised.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     tlib.library_name # => Excel
 */
static VALUE
foletypelib_library_name(VALUE self)
{
    HRESULT hr;
    ITypeLib *pTypeLib = NULL;
    VALUE libname = Qnil;
    BSTR bstr;

    pTypeLib = itypelib(self);
    hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, -1,
                                            &bstr, NULL, NULL, NULL);
    if (FAILED(hr)) {
        ole_raise(hr, eWIN32OLERuntimeError, "failed to get library name");
    }
    libname = WC2VSTR(bstr);
    return libname;
}

static VALUE
ole_types_from_typelib(ITypeLib *pTypeLib, VALUE classes)
{
    long count;
    int i;
    HRESULT hr;
    BSTR bstr;
    ITypeInfo *pTypeInfo;
    VALUE type;

    count = pTypeLib->lpVtbl->GetTypeInfoCount(pTypeLib);
    for (i = 0; i < count; i++) {
        hr = pTypeLib->lpVtbl->GetDocumentation(pTypeLib, i,
                                                &bstr, NULL, NULL, NULL);
        if (FAILED(hr))
            continue;

        hr = pTypeLib->lpVtbl->GetTypeInfo(pTypeLib, i, &pTypeInfo);
        if (FAILED(hr))
            continue;

        type = create_win32ole_type(pTypeInfo, WC2VSTR(bstr));

        rb_ary_push(classes, type);
        OLE_RELEASE(pTypeInfo);
    }
    return classes;
}

static VALUE
typelib_file_from_typelib(VALUE ole)
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
                        if ((file = reg_get_typelib_file_path(hlang)) != Qnil)
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
typelib_file_from_clsid(VALUE ole)
{
    HKEY hroot, hclsid;
    LONG err;
    VALUE typelib;
    char path[MAX_PATH + 1];

    err = reg_open_key(HKEY_CLASSES_ROOT, "CLSID", &hroot);
    if (err != ERROR_SUCCESS) {
        return Qnil;
    }
    err = reg_open_key(hroot, StringValuePtr(ole), &hclsid);
    if (err != ERROR_SUCCESS) {
        RegCloseKey(hroot);
        return Qnil;
    }
    typelib = reg_get_val2(hclsid, "InprocServer32");
    RegCloseKey(hroot);
    RegCloseKey(hclsid);
    if (typelib != Qnil) {
        ExpandEnvironmentStrings(StringValuePtr(typelib), path, sizeof(path));
        path[MAX_PATH] = '\0';
        typelib = rb_str_new2(path);
    }
    return typelib;
}

VALUE
typelib_file(VALUE ole)
{
    VALUE file = typelib_file_from_clsid(ole);
    if (file != Qnil) {
        return file;
    }
    return typelib_file_from_typelib(ole);
}


/*
 *  call-seq:
 *     ole_types -> The array of WIN32OLE::Type object included the type library.
 *
 *  Returns the type library file path.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     classes = tlib.ole_types.collect{|k| k.name} # -> ['AddIn', 'AddIns' ...]
 */
static VALUE
foletypelib_ole_types(VALUE self)
{
    ITypeLib *pTypeLib = NULL;
    VALUE classes = rb_ary_new();
    pTypeLib = itypelib(self);
    ole_types_from_typelib(pTypeLib, classes);
    return classes;
}

/*
 *  call-seq:
 *     inspect -> String
 *
 *  Returns the type library name with class name.
 *
 *     tlib = WIN32OLE::TypeLib.new('Microsoft Excel 9.0 Object Library')
 *     tlib.inspect # => "<#WIN32OLE::TypeLib:Microsoft Excel 9.0 Object Library>"
 */
static VALUE
foletypelib_inspect(VALUE self)
{
    return default_inspect(self, "WIN32OLE::TypeLib");
}

VALUE cWIN32OLE_TYPELIB;

void
Init_win32ole_typelib(void)
{
    cWIN32OLE_TYPELIB = rb_define_class_under(cWIN32OLE, "TypeLib", rb_cObject);
    /* Alias of WIN32OLE::TypeLib, for the backward compatibility */
    rb_define_const(rb_cObject, "WIN32OLE" "_TYPELIB", cWIN32OLE_TYPELIB);
    rb_deprecate_constant(rb_cObject, "WIN32OLE" "_TYPELIB");
    rb_define_singleton_method(cWIN32OLE_TYPELIB, "typelibs", foletypelib_s_typelibs, 0);
    rb_define_alloc_func(cWIN32OLE_TYPELIB, foletypelib_s_allocate);
    rb_define_method(cWIN32OLE_TYPELIB, "initialize", foletypelib_initialize, -2);
    rb_define_method(cWIN32OLE_TYPELIB, "guid", foletypelib_guid, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "name", foletypelib_name, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "version", foletypelib_version, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "major_version", foletypelib_major_version, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "minor_version", foletypelib_minor_version, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "path", foletypelib_path, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "ole_types", foletypelib_ole_types, 0);
    rb_define_alias(cWIN32OLE_TYPELIB, "ole_classes", "ole_types");
    rb_define_method(cWIN32OLE_TYPELIB, "visible?", foletypelib_visible, 0);
    rb_define_method(cWIN32OLE_TYPELIB, "library_name", foletypelib_library_name, 0);
    rb_define_alias(cWIN32OLE_TYPELIB, "to_s", "name");
    rb_define_method(cWIN32OLE_TYPELIB, "inspect", foletypelib_inspect, 0);
}
