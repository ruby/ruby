/*
  Win32API - Ruby Win32 API Import Facility
*/

#if !defined _MSC_VER && !defined _WIN32
#define  WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#endif

#define _T_VOID     0
#define _T_NUMBER   1
#define _T_POINTER  2
#define _T_INTEGER  3

#include "ruby.h"

typedef struct {
    HANDLE dll;
    HANDLE proc;
    VALUE dllname;
    VALUE import;
    VALUE export;
} Win32API;

static void
Win32API_FreeLibrary(hdll)
    HINSTANCE hdll;
{
    FreeLibrary(hdll);
}

static VALUE
Win32API_initialize(self, dllname, proc, import, export)
    VALUE self;
    VALUE dllname;
    VALUE proc;
    VALUE import;
    VALUE export;
{
    HANDLE hproc;
    HINSTANCE hdll;
    VALUE str;
    VALUE a_import;
    VALUE *ptr;
    char *s;
    int i;
    int len;
    int ex = _T_VOID;

    SafeStringValue(dllname);
    SafeStringValue(proc);
    hdll = LoadLibrary(RSTRING(dllname)->ptr);
    if (!hdll)
	rb_raise(rb_eRuntimeError, "LoadLibrary: %s\n", RSTRING(dllname)->ptr);
    rb_iv_set(self, "__hdll__", Data_Wrap_Struct(rb_cData, 0, Win32API_FreeLibrary, hdll));
    hproc = GetProcAddress(hdll, RSTRING(proc)->ptr);
    if (!hproc) {
	str = rb_str_new3(proc);
	str = rb_str_cat(str, "A", 1);
	hproc = GetProcAddress(hdll, RSTRING(str)->ptr);
	if (!hproc)
	    rb_raise(rb_eRuntimeError, "GetProcAddress: %s or %s\n",
		RSTRING(proc)->ptr, RSTRING(str)->ptr);
    }
    rb_iv_set(self, "__dll__", UINT2NUM((unsigned long)hdll));
    rb_iv_set(self, "__dllname__", dllname);
    rb_iv_set(self, "__proc__", UINT2NUM((unsigned long)hproc));

    a_import = rb_ary_new();
    switch (TYPE(import)) {
    case T_NIL:
	break;
    case T_ARRAY:
	ptr = RARRAY(import)->ptr;
	for (i = 0, len = RARRAY(import)->len; i < len; i++) {
	    SafeStringValue(ptr[i]);
	    switch (*(char *)RSTRING(ptr[i])->ptr) {
	    case 'N': case 'n': case 'L': case 'l':
		rb_ary_push(a_import, INT2FIX(_T_NUMBER));
		break;
	    case 'P': case 'p':
		rb_ary_push(a_import, INT2FIX(_T_POINTER));
		break;
	    case 'I': case 'i':
		rb_ary_push(a_import, INT2FIX(_T_INTEGER));
		break;
	    }
	}
        break;
    default:
	SafeStringValue(import);
	s = RSTRING(import)->ptr;
	for (i = 0, len = RSTRING(import)->len; i < len; i++) {
	    switch (*s++) {
	    case 'N': case 'n': case 'L': case 'l':
		rb_ary_push(a_import, INT2FIX(_T_NUMBER));
		break;
	    case 'P': case 'p':
		rb_ary_push(a_import, INT2FIX(_T_POINTER));
		break;
	    case 'I': case 'i':
		rb_ary_push(a_import, INT2FIX(_T_INTEGER));
		break;
	    }
	}
        break;
    }

    if (16 < RARRAY(a_import)->len) {
	rb_raise(rb_eRuntimeError, "too many parameters: %d\n", RARRAY(a_import)->len);
    }

    rb_iv_set(self, "__import__", a_import);

    if (NIL_P(export)) {
	ex = _T_VOID;
    } else {
	SafeStringValue(export);
	switch (*RSTRING(export)->ptr) {
        case 'V': case 'v':
	    ex = _T_VOID;
	    break;
	case 'N': case 'n': case 'L': case 'l':
	    ex = _T_NUMBER;
	    break;
	case 'P': case 'p':
	    ex = _T_POINTER;
	    break;
	case 'I': case 'i':
	    ex = _T_INTEGER;
	    break;
	}
    }
    rb_iv_set(self, "__export__", INT2FIX(ex));

    return Qnil;
}

static VALUE
Win32API_Call(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE args;
    unsigned long ret;
    int i;
    struct {
	unsigned long params[16];
    } param;
#define params param.params

    VALUE obj_proc = rb_iv_get(obj, "__proc__");
    VALUE obj_import = rb_iv_get(obj, "__import__");
    VALUE obj_export = rb_iv_get(obj, "__export__");
    FARPROC ApiFunction = (FARPROC)NUM2ULONG(obj_proc);
    int items = rb_scan_args(argc, argv, "0*", &args);
    int nimport = RARRAY(obj_import)->len;


    if (items != nimport)
	rb_raise(rb_eRuntimeError, "Wrong number of parameters: expected %d, got %d.\n",
	    nimport, items);

    for (i = 0; i < nimport; i++) {
	unsigned long lParam = 0;
	switch (FIX2INT(rb_ary_entry(obj_import, i))) {
	    VALUE str;
	case _T_NUMBER:
	case _T_INTEGER:
	default:
	    lParam = NUM2ULONG(rb_ary_entry(args, i));
	    break;
	case _T_POINTER:
	    str = rb_ary_entry(args, i);
	    if (NIL_P(str)) {
		lParam = 0;
	    } else if (FIXNUM_P(str)) {
		lParam = NUM2ULONG(str);
	    } else {
		StringValue(str);
		rb_str_modify(str);
		lParam = (unsigned long)StringValuePtr(str);
	    }
	    break;
	}
	params[i] = lParam;
    }

    ret = ApiFunction(param);

    switch (FIX2INT(obj_export)) {
    case _T_NUMBER:
    case _T_INTEGER:
	return INT2NUM(ret);
    case _T_POINTER:
	return rb_str_new2((char *)ret);
    case _T_VOID:
    default:
	return INT2NUM(0);
    }
}

void
Init_Win32API()
{
    VALUE cWin32API = rb_define_class("Win32API", rb_cObject);
    rb_define_method(cWin32API, "initialize", Win32API_initialize, 4);
    rb_define_method(cWin32API, "call", Win32API_Call, -1);
    rb_define_alias(cWin32API,  "Call", "call");
}
