/*
  Win32API - Ruby Win32 API Import Facility
*/

#if !defined _MSC_VER && !defined NT
#define  WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#endif

#if defined(_MSC_VER)
#if defined(_M_ALPHA)
#ifdef __cplusplus
extern "C" { long __asm(char *,...); };
#else
long __asm(char *,...);
#endif
#pragma intrinsic(__asm)
#endif
#endif

#define _T_VOID     0
#define _T_NUMBER   1
#define _T_POINTER  2
#define _T_INTEGER  3

typedef char *ApiPointer(void);
typedef long  ApiNumber(void);
typedef void  ApiVoid(void);
typedef int   ApiInteger(void);

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
    int ex;

    Check_SafeStr(dllname);
    Check_SafeStr(proc);
    hdll = LoadLibrary(RSTRING(dllname)->ptr);
    if (!hdll)
	rb_raise(rb_eRuntimeError, "LoadLibrary: %s\n", RSTRING(dllname)->ptr);
    rb_iv_set(self, "__hdll__", Data_Wrap_Struct(self, 0, Win32API_FreeLibrary, hdll));
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
	    Check_SafeStr(ptr[i]);
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
	Check_SafeStr(import);
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
    rb_iv_set(self, "__import__", a_import);

    if (NIL_P(export)) {
	ex = _T_VOID;
    } else {
	Check_SafeStr(export);
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

    FARPROC ApiFunction;

    ApiPointer  *ApiFunctionPointer;
    ApiNumber   *ApiFunctionNumber;
    ApiVoid     *ApiFunctionVoid;
    ApiInteger  *ApiFunctionInteger;

    long  lParam;
    char *pParam;

    VALUE Return;

    VALUE obj_proc;
    VALUE obj_import;
    VALUE obj_export;
    VALUE import_type;
    int nimport, timport, texport, i;
    int items;
    int ret;

    items = rb_scan_args(argc, argv, "0*", &args);

    obj_proc = rb_iv_get(obj, "__proc__");

    ApiFunction = (FARPROC)NUM2ULONG(obj_proc);

    obj_import = rb_iv_get(obj, "__import__");
    obj_export = rb_iv_get(obj, "__export__");
    nimport = RARRAY(obj_import)->len;
    texport = FIX2INT(obj_export);

    if (items != nimport)
	rb_raise(rb_eRuntimeError, "Wrong number of parameters: expected %d, got %d.\n",
	    nimport, items);

    if (0 < nimport) {
	for (i = nimport - 1; 0 <= i; i--) {
	    VALUE str;
	    import_type = rb_ary_entry(obj_import, i);
	    timport = FIX2INT(import_type);
	    switch (timport) {
	    case _T_NUMBER:
	    case _T_INTEGER:
		lParam = NUM2ULONG(rb_ary_entry(args, i));
#if defined(_MSC_VER) || defined(__LCC__)
#if defined(_M_IX86)
		_asm {
		    mov     eax, lParam
		    push    eax
		}
#elif defined(_M_ALPHA)
		__asm(
			"ldl r0, 0(%0);"
			"stq r0, -(sp);"
			, lParam
		);
#else
#error
#endif
#elif defined __GNUC__
		asm volatile ("pushl %0" :: "g" (lParam));
#else
#error
#endif
		break;
	    case _T_POINTER:
		str = rb_ary_entry(args, i);
		if (NIL_P(str)) {
		    pParam = 0;
		} else if (FIXNUM_P(str)){
		    pParam = (char *)NUM2ULONG(str);
		} else {
		    Check_Type(str, T_STRING);
		    rb_str_modify(str);
		    pParam = RSTRING(str)->ptr;
		}
#if defined(_MSC_VER) || defined(__LCC__)
#if defined(_M_IX86)
		_asm {
		    mov     eax, pParam
		    push    eax
		}
#elif defined(_M_ALPHA)
		__asm(
			"ldl r0, 0(%0);"
			"stq r0, -(sp);"
			, pParam
		);
#else
#error
#endif
#elif defined __GNUC__
		asm volatile ("pushl %0" :: "g" (pParam));
#else
#error
#endif
		break;
	    }
	}
    }

#if defined __GNUC__
    asm volatile ("call *%1" : "=r" (ret) : "g" (ApiFunction));
    switch (texport) {
    case _T_NUMBER:
    case _T_INTEGER:
	Return = INT2NUM(ret);
	break;
    case _T_POINTER:
	Return = rb_str_new2((char *)ret);
	break;
    case _T_VOID:
    default:
	Return = INT2NUM(0);
	break;
    }
#else
    switch (texport) {
    case _T_NUMBER:
	ApiFunctionNumber = (ApiNumber *) ApiFunction;
	Return = INT2NUM(ApiFunctionNumber());
	break;
    case _T_POINTER:
	ApiFunctionPointer = (ApiPointer *) ApiFunction;
	Return = rb_str_new2((char *)ApiFunctionPointer());
	break;
    case _T_INTEGER:
	ApiFunctionInteger = (ApiInteger *) ApiFunction;
	Return = INT2NUM(ApiFunctionInteger());
	break;
    case _T_VOID:
    default:
	ApiFunctionVoid = (ApiVoid *) ApiFunction;
	ApiFunctionVoid();
	Return = INT2NUM(0);
	break;
    }
#endif
    return Return;
}

void
Init_Win32API()
{
    VALUE cWin32API = rb_define_class("Win32API", rb_cObject);
    rb_define_method(cWin32API, "initialize", Win32API_initialize, 4);
    rb_define_method(cWin32API, "call", Win32API_Call, -1);
    rb_define_alias(cWin32API,  "Call", "call");
}
