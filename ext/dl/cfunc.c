/* -*- C -*-
 * $Id$
 */

#include <ruby.h>
#include <errno.h>
#include "dl.h"

VALUE rb_cDLCFunc;

static ID id_last_error;

static VALUE
rb_dl_get_last_error(VALUE self)
{
    return rb_thread_local_aref(rb_thread_current(), id_last_error);
}

static VALUE
rb_dl_set_last_error(VALUE self, VALUE val)
{
    rb_thread_local_aset(rb_thread_current(), id_last_error, val);
    return Qnil;
}

#if defined(HAVE_WINDOWS_H)
#include <windows.h>
static ID id_win32_last_error;

static VALUE
rb_dl_get_win32_last_error(VALUE self)
{
    return rb_thread_local_aref(rb_thread_current(), id_win32_last_error);
}

static VALUE
rb_dl_set_win32_last_error(VALUE self, VALUE val)
{
    rb_thread_local_aset(rb_thread_current(), id_win32_last_error, val);
    return Qnil;
}
#endif


void
dlcfunc_free(void *ptr)
{
    struct cfunc_data *data = ptr;
  if( data->name ){
      xfree(data->name);
  }
  xfree(data);
}

VALUE
rb_dlcfunc_new(void (*func)(), int type, const char *name, ID calltype)
{
  VALUE val;
  struct cfunc_data *data;

  rb_secure(4);
  if( func ){
    val = Data_Make_Struct(rb_cDLCFunc, struct cfunc_data, 0, dlcfunc_free, data);
    data->ptr  = func;
    data->name = name ? strdup(name) : NULL;
    data->type = type;
    data->calltype = calltype;
  }
  else{
    val = Qnil;
  }

  return val;
}

void *
rb_dlcfunc2ptr(VALUE val)
{
  struct cfunc_data *data;
  void * func;

  if( rb_obj_is_kind_of(val, rb_cDLCFunc) ){
    Data_Get_Struct(val, struct cfunc_data, data);
    func = data->ptr;
  }
  else if( val == Qnil ){
    func = NULL;
  }
  else{
    rb_raise(rb_eTypeError, "DL::CFunc was expected");
  }

  return func;
}

VALUE
rb_dlcfunc_s_allocate(VALUE klass)
{
  VALUE obj;
  struct cfunc_data *data;

  obj = Data_Make_Struct(klass, struct cfunc_data, 0, dlcfunc_free, data);
  data->ptr  = 0;
  data->name = 0;
  data->type = 0;
  data->calltype = CFUNC_CDECL;

  return obj;
}

int
rb_dlcfunc_kind_p(VALUE func)
{
    if (TYPE(func) == T_DATA) return 0;
    return RDATA(func)->dfree == dlcfunc_free;
}

VALUE
rb_dlcfunc_initialize(int argc, VALUE argv[], VALUE self)
{
    VALUE addr, name, type, calltype;
    struct cfunc_data *data;
    void *saddr;
    const char *sname;
    
    rb_scan_args(argc, argv, "13", &addr, &type, &name, &calltype);
    
    saddr = (void*)(NUM2PTR(rb_Integer(addr)));
    sname = NIL_P(name) ? NULL : StringValuePtr(name);
    
    Data_Get_Struct(self, struct cfunc_data, data);
    if( data->name ) xfree(data->name);
    data->ptr  = saddr;
    data->name = sname ? strdup(sname) : 0;
    data->type = (type == Qnil) ? DLTYPE_VOID : NUM2INT(type);
    data->calltype = (calltype == Qnil) ? CFUNC_CDECL : SYM2ID(calltype);

    return Qnil;
}

VALUE
rb_dlcfunc_name(VALUE self)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    return cfunc->name ? rb_tainted_str_new2(cfunc->name) : Qnil;
}

VALUE
rb_dlcfunc_ctype(VALUE self)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    return INT2NUM(cfunc->type);
}

VALUE
rb_dlcfunc_set_ctype(VALUE self, VALUE ctype)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    cfunc->type = NUM2INT(ctype);
    return ctype;
}

VALUE
rb_dlcfunc_calltype(VALUE self)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    return ID2SYM(cfunc->calltype);
}

VALUE
rb_dlcfunc_set_calltype(VALUE self, VALUE sym)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    cfunc->calltype = SYM2ID(sym);
    return sym;
}


VALUE
rb_dlcfunc_ptr(VALUE self)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    return PTR2NUM(cfunc->ptr);
}

VALUE
rb_dlcfunc_set_ptr(VALUE self, VALUE addr)
{
    struct cfunc_data *cfunc;

    Data_Get_Struct(self, struct cfunc_data, cfunc);
    cfunc->ptr = NUM2PTR(addr);

    return Qnil;
}

VALUE
rb_dlcfunc_inspect(VALUE self)
{
    VALUE val;
    char  *str;
    int str_size;
    struct cfunc_data *cfunc;
    
    Data_Get_Struct(self, struct cfunc_data, cfunc);
    
    str_size = (cfunc->name ? strlen(cfunc->name) : 0) + 100;
    str = ruby_xmalloc(str_size);
    snprintf(str, str_size - 1,
	     "#<DL::CFunc:%p ptr=%p type=%d name='%s'>",
	     cfunc,
	     cfunc->ptr,
	     cfunc->type,
	     cfunc->name ? cfunc->name : "");
    val = rb_tainted_str_new2(str);
    ruby_xfree(str);

    return val;
}


# define DECL_FUNC_CDECL(f,ret,args)  ret (FUNC_CDECL(*f))(args)
#ifdef FUNC_STDCALL
# define DECL_FUNC_STDCALL(f,ret,args)  ret (FUNC_STDCALL(*f))(args)
#endif

#define CALL_CASE switch( RARRAY_LEN(ary) ){ \
  CASE(0); break; \
  CASE(1); break; CASE(2); break; CASE(3); break; CASE(4); break; CASE(5); break; \
  CASE(6); break; CASE(7); break; CASE(8); break; CASE(9); break; CASE(10);break; \
  CASE(11);break; CASE(12);break; CASE(13);break; CASE(14);break; CASE(15);break; \
  CASE(16);break; CASE(17);break; CASE(18);break; CASE(19);break; CASE(20);break; \
  default: rb_raise(rb_eArgError, "too many arguments"); \
}


VALUE
rb_dlcfunc_call(VALUE self, VALUE ary)
{
    struct cfunc_data *cfunc;
    int i;
    DLSTACK_TYPE stack[DLSTACK_SIZE];
    VALUE result = Qnil;

    rb_secure_update(self);

    memset(stack, 0, sizeof(DLSTACK_TYPE) * DLSTACK_SIZE);
    Check_Type(ary, T_ARRAY);
    
    Data_Get_Struct(self, struct cfunc_data, cfunc);

    if( cfunc->ptr == 0 ){
	rb_raise(rb_eDLError, "can't call null-function");
	return Qnil;
    }
    
    for( i = 0; i < RARRAY_LEN(ary); i++ ){
	if( i >= DLSTACK_SIZE ){
	    rb_raise(rb_eDLError, "too many arguments (stack overflow)");
	}
	rb_check_safe_obj(RARRAY_PTR(ary)[i]);
	stack[i] = NUM2LONG(RARRAY_PTR(ary)[i]);
    }
    
    /* calltype == CFUNC_CDECL */
    if( cfunc->calltype == CFUNC_CDECL
#ifndef FUNC_STDCALL
	|| cfunc->calltype == CFUNC_STDCALL
#endif
	){
	switch( cfunc->type ){
	case DLTYPE_VOID:
#define CASE(n) case n: { \
            DECL_FUNC_CDECL(f,void,DLSTACK_PROTO##n) = cfunc->ptr; \
	    f(DLSTACK_ARGS##n(stack)); \
	    result = Qnil; \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_VOIDP:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,void*,DLSTACK_PROTO##n) = cfunc->ptr; \
	    void * ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = PTR2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_CHAR:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,char,DLSTACK_PROTO##n) = cfunc->ptr; \
	    char ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = CHR2FIX(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_SHORT:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,short,DLSTACK_PROTO##n) = cfunc->ptr; \
	    short ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = INT2NUM((int)ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_INT:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,int,DLSTACK_PROTO##n) = cfunc->ptr; \
	    int ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = INT2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_LONG:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,long,DLSTACK_PROTO##n) = cfunc->ptr; \
	    long ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = LONG2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
#if HAVE_LONG_LONG  /* used in ruby.h */
	case DLTYPE_LONG_LONG:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,LONG_LONG,DLSTACK_PROTO##n) = cfunc->ptr; \
	    LONG_LONG ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = LL2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
#endif
	case DLTYPE_FLOAT:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,float,DLSTACK_PROTO##n) = cfunc->ptr; \
	    float ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = rb_float_new(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_DOUBLE:
#define CASE(n) case n: { \
	    DECL_FUNC_CDECL(f,double,DLSTACK_PROTO##n) = cfunc->ptr; \
	    double ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = rb_float_new(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	default:
	    rb_raise(rb_eDLTypeError, "unknown type %d", cfunc->type);
	}
    }
#ifdef FUNC_STDCALL
    else if( cfunc->calltype == CFUNC_STDCALL ){
	/* calltype == CFUNC_STDCALL */
	switch( cfunc->type ){
	case DLTYPE_VOID:
#define CASE(n) case n: { \
            DECL_FUNC_STDCALL(f,void,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    f(DLSTACK_ARGS##n(stack)); \
	    result = Qnil; \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_VOIDP:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,void*,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    void * ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = PTR2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_CHAR:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,char,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    char ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = CHR2FIX(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_SHORT:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,short,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    short ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = INT2NUM((int)ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_INT:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,int,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    int ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = INT2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_LONG:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,long,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    long ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = LONG2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
#if HAVE_LONG_LONG  /* used in ruby.h */
	case DLTYPE_LONG_LONG:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,LONG_LONG,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    LONG_LONG ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = LL2NUM(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
#endif
	case DLTYPE_FLOAT:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,float,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    float ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = rb_float_new(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	case DLTYPE_DOUBLE:
#define CASE(n) case n: { \
	    DECL_FUNC_STDCALL(f,double,DLSTACK_PROTO##n##_) = cfunc->ptr; \
	    double ret; \
	    ret = f(DLSTACK_ARGS##n(stack)); \
	    result = rb_float_new(ret); \
}
	    CALL_CASE;
#undef CASE
	    break;
	default:
	    rb_raise(rb_eDLTypeError, "unknown type %d", cfunc->type);
	}
    }
#endif
    else{
	rb_raise(rb_eDLError,
#ifndef LONG_LONG_VALUE
		 "unsupported call type: %lx",
#else
		 "unsupported call type: %llx",
#endif
		 cfunc->calltype);
    }

    rb_dl_set_last_error(self, INT2NUM(errno));
#if defined(HAVE_WINDOWS_H)
    rb_dl_set_win32_last_error(self, INT2NUM(GetLastError()));
#endif

    return result;
}

VALUE
rb_dlcfunc_to_i(VALUE self)
{
  struct cfunc_data *cfunc;

  Data_Get_Struct(self, struct cfunc_data, cfunc);
  return PTR2NUM(cfunc->ptr);
}

void
Init_dlcfunc()
{
    id_last_error = rb_intern("__DL2_LAST_ERROR__");
#if defined(HAVE_WINDOWS_H)
    id_win32_last_error = rb_intern("__DL2_WIN32_LAST_ERROR__");
#endif
    rb_cDLCFunc = rb_define_class_under(rb_mDL, "CFunc", rb_cObject);
    rb_define_alloc_func(rb_cDLCFunc, rb_dlcfunc_s_allocate);
    rb_define_module_function(rb_cDLCFunc, "last_error", rb_dl_get_last_error, 0);
#if defined(HAVE_WINDOWS_H)
    rb_define_module_function(rb_cDLCFunc, "win32_last_error", rb_dl_get_win32_last_error, 0);
#endif
    rb_define_method(rb_cDLCFunc, "initialize", rb_dlcfunc_initialize, -1);
    rb_define_method(rb_cDLCFunc, "call", rb_dlcfunc_call, 1);
    rb_define_method(rb_cDLCFunc, "[]",   rb_dlcfunc_call, 1);
    rb_define_method(rb_cDLCFunc, "name", rb_dlcfunc_name, 0);
    rb_define_method(rb_cDLCFunc, "ctype", rb_dlcfunc_ctype, 0);
    rb_define_method(rb_cDLCFunc, "ctype=", rb_dlcfunc_set_ctype, 1);
    rb_define_method(rb_cDLCFunc, "calltype", rb_dlcfunc_calltype, 0);
    rb_define_method(rb_cDLCFunc, "calltype=", rb_dlcfunc_set_calltype, 1);
    rb_define_method(rb_cDLCFunc, "ptr",  rb_dlcfunc_ptr, 0);
    rb_define_method(rb_cDLCFunc, "ptr=", rb_dlcfunc_set_ptr, 1);
    rb_define_method(rb_cDLCFunc, "inspect", rb_dlcfunc_inspect, 0);
    rb_define_method(rb_cDLCFunc, "to_s", rb_dlcfunc_inspect, 0);
    rb_define_method(rb_cDLCFunc, "to_i", rb_dlcfunc_to_i, 0);
}
