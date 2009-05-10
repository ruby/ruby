/* -*- C -*-
 * $Id$
 */

#include <ruby/ruby.h>
#include <ruby/io.h>
#include <ctype.h>
#include "dl.h"

VALUE rb_cDLCPtr;

static ID id_to_ptr;

static void
dlptr_free(struct ptr_data *data)
{
    if (data->ptr) {
	if (data->free) {
	    (*(data->free))(data->ptr);
	}
    }
}

static void
dlptr_mark(struct ptr_data *data)
{
}

void
dlptr_init(VALUE val)
{
    struct ptr_data *data;

    Data_Get_Struct(val, struct ptr_data, data);
    OBJ_TAINT(val);
}

VALUE
rb_dlptr_new2(VALUE klass, void *ptr, long size, freefunc_t func)
{
    struct ptr_data *data;
    VALUE val;

    rb_secure(4);
    val = Data_Make_Struct(klass, struct ptr_data,
			   0, dlptr_free, data);
    data->ptr = ptr;
    data->free = func;
    data->size = size;
    dlptr_init(val);

    return val;
}

VALUE
rb_dlptr_new(void *ptr, long size, freefunc_t func)
{
    return rb_dlptr_new2(rb_cDLCPtr, ptr, size, func);
}

VALUE
rb_dlptr_malloc(long size, freefunc_t func)
{
    void *ptr;

    rb_secure(4);
    ptr = ruby_xmalloc((size_t)size);
    memset(ptr,0,(size_t)size);
    return rb_dlptr_new(ptr, size, func);
}

void *
rb_dlptr2cptr(VALUE val)
{
    struct ptr_data *data;
    void *ptr;

    if (rb_obj_is_kind_of(val, rb_cDLCPtr)) {
	Data_Get_Struct(val, struct ptr_data, data);
	ptr = data->ptr;
    }
    else if (val == Qnil) {
	ptr = NULL;
    }
    else{
	rb_raise(rb_eTypeError, "DL::PtrData was expected");
    }
    
    return ptr;
}

static VALUE
rb_dlptr_s_allocate(VALUE klass)
{
    VALUE obj;
    struct ptr_data *data;

    rb_secure(4);
    obj = Data_Make_Struct(klass, struct ptr_data, dlptr_mark, dlptr_free, data);
    data->ptr = 0;
    data->size = 0;
    data->free = 0;

    return obj;
}

static VALUE
rb_dlptr_initialize(int argc, VALUE argv[], VALUE self)
{
    VALUE ptr, sym, size;
    struct ptr_data *data;
    void *p = NULL;
    freefunc_t f = NULL;
    long s = 0;

    switch (rb_scan_args(argc, argv, "12", &ptr, &size, &sym)) {
      case 1:
	p = (void*)(NUM2PTR(rb_Integer(ptr)));
	break;
      case 2:
	p = (void*)(NUM2PTR(rb_Integer(ptr)));
	s = NUM2LONG(size);
	break;
      case 3:
	p = (void*)(NUM2PTR(rb_Integer(ptr)));
	s = NUM2LONG(size);
	f = NIL_P(sym) ? NULL : RCFUNC_DATA(sym)->ptr;
	break;
      default:
	rb_bug("rb_dlptr_initialize");
    }

    if (p) {
	Data_Get_Struct(self, struct ptr_data, data);
	if (data->ptr && data->free) {
	    /* Free previous memory. Use of inappropriate initialize may cause SEGV. */
	    (*(data->free))(data->ptr);
	}
	data->ptr  = p;
	data->size = s;
	data->free = f;
    }

    return Qnil;
}

static VALUE
rb_dlptr_s_malloc(int argc, VALUE argv[], VALUE klass)
{
    VALUE size, sym, obj;
    int   s;
    freefunc_t f;

    switch (rb_scan_args(argc, argv, "11", &size, &sym)) {
      case 1:
	s = NUM2LONG(size);
	f = NULL;
	break;
      case 2:
	s = NUM2LONG(size);
	f = RCFUNC_DATA(sym)->ptr;
	break;
      default:
	rb_bug("rb_dlptr_s_malloc");
    }

    obj = rb_dlptr_malloc(s,f);

    return obj;
}

VALUE
rb_dlptr_to_i(VALUE self)
{
    struct ptr_data *data;

    Data_Get_Struct(self, struct ptr_data, data);
    return PTR2NUM(data->ptr);
}

VALUE
rb_dlptr_to_value(VALUE self)
{
    struct ptr_data *data;
    Data_Get_Struct(self, struct ptr_data, data);
    return (VALUE)(data->ptr);
}

VALUE
rb_dlptr_ptr(VALUE self)
{
    struct ptr_data *data;

    Data_Get_Struct(self, struct ptr_data, data);
    return rb_dlptr_new(*((void**)(data->ptr)),0,0);
}

VALUE
rb_dlptr_ref(VALUE self)
{
    struct ptr_data *data;

    Data_Get_Struct(self, struct ptr_data, data);
    return rb_dlptr_new(&(data->ptr),0,0);
}

VALUE
rb_dlptr_null_p(VALUE self)
{
    struct ptr_data *data;

    Data_Get_Struct(self, struct ptr_data, data);
    return data->ptr ? Qfalse : Qtrue;
}

VALUE
rb_dlptr_free_set(VALUE self, VALUE val)
{
    struct ptr_data *data;
    extern VALUE rb_cDLCFunc;

    Data_Get_Struct(self, struct ptr_data, data);
    if( rb_obj_is_kind_of(val, rb_cDLCFunc) == Qtrue ){
	data->free = RCFUNC_DATA(val)->ptr;
    }
    else{
	data->free = NUM2PTR(rb_Integer(val));
    }

    return Qnil;
}

VALUE
rb_dlptr_free_get(VALUE self)
{
    struct ptr_data *pdata;

    Data_Get_Struct(self, struct ptr_data, pdata);

    return rb_dlcfunc_new(pdata->free, DLTYPE_VOID, "free<anonymous>", CFUNC_CDECL);
}

VALUE
rb_dlptr_to_s(int argc, VALUE argv[], VALUE self)
{
    struct ptr_data *data;
    VALUE arg1, val;
    int len;

    Data_Get_Struct(self, struct ptr_data, data);
    switch (rb_scan_args(argc, argv, "01", &arg1)) {
      case 0:
	val = rb_tainted_str_new2((char*)(data->ptr));
	break;
      case 1:
	len = NUM2INT(arg1);
	val = rb_tainted_str_new((char*)(data->ptr), len);
	break;
      default:
	rb_bug("rb_dlptr_to_s");
    }

    return val;
}

VALUE
rb_dlptr_to_str(int argc, VALUE argv[], VALUE self)
{
    struct ptr_data *data;
    VALUE arg1, val;
    int len;

    Data_Get_Struct(self, struct ptr_data, data);
    switch (rb_scan_args(argc, argv, "01", &arg1)) {
      case 0:
	val = rb_tainted_str_new((char*)(data->ptr),data->size);
	break;
      case 1:
	len = NUM2INT(arg1);
	val = rb_tainted_str_new((char*)(data->ptr), len);
	break;
      default:
	rb_bug("rb_dlptr_to_str");
    }

    return val;
}

VALUE
rb_dlptr_inspect(VALUE self)
{
    struct ptr_data *data;
    char str[1024];

    Data_Get_Struct(self, struct ptr_data, data);
    snprintf(str, 1023, "#<%s:%p ptr=%p size=%ld free=%p>",
	     rb_class2name(CLASS_OF(self)), data, data->ptr, data->size, data->free);
    return rb_str_new2(str);
}

VALUE
rb_dlptr_eql(VALUE self, VALUE other)
{
    void *ptr1, *ptr2;
    ptr1 = rb_dlptr2cptr(self);
    ptr2 = rb_dlptr2cptr(other);

    return ptr1 == ptr2 ? Qtrue : Qfalse;
}

VALUE
rb_dlptr_cmp(VALUE self, VALUE other)
{
    void *ptr1, *ptr2;
    ptr1 = rb_dlptr2cptr(self);
    ptr2 = rb_dlptr2cptr(other);
    return PTR2NUM((long)ptr1 - (long)ptr2);
}

VALUE
rb_dlptr_plus(VALUE self, VALUE other)
{
    void *ptr;
    long num, size;

    ptr = rb_dlptr2cptr(self);
    size = RPTR_DATA(self)->size;
    num = NUM2LONG(other);
    return rb_dlptr_new((char *)ptr + num, size - num, 0);
}

VALUE
rb_dlptr_minus(VALUE self, VALUE other)
{
    void *ptr;
    long num, size;

    ptr = rb_dlptr2cptr(self);
    size = RPTR_DATA(self)->size;
    num = NUM2LONG(other);
    return rb_dlptr_new((char *)ptr - num, size + num, 0);
}

VALUE
rb_dlptr_aref(int argc, VALUE argv[], VALUE self)
{
    VALUE arg0, arg1;
    VALUE retval = Qnil;
    size_t offset, len;

    switch( rb_scan_args(argc, argv, "11", &arg0, &arg1) ){
      case 1:
	offset = NUM2ULONG(arg0);
	retval = INT2NUM(*((char*)RPTR_DATA(self)->ptr + offset));
	break;
      case 2:
	offset = NUM2ULONG(arg0);
	len    = NUM2ULONG(arg1);
	retval = rb_tainted_str_new((char *)RPTR_DATA(self)->ptr + offset, len);
	break;
      default:
	rb_bug("rb_dlptr_aref()");
    }
    return retval;
}

VALUE
rb_dlptr_aset(int argc, VALUE argv[], VALUE self)
{
    VALUE arg0, arg1, arg2;
    VALUE retval = Qnil;
    size_t offset, len;
    void *mem;

    switch( rb_scan_args(argc, argv, "21", &arg0, &arg1, &arg2) ){
      case 2:
	offset = NUM2ULONG(arg0);
	((char*)RPTR_DATA(self)->ptr)[offset] = NUM2UINT(arg1);
	retval = arg1;
	break;
      case 3:
	offset = NUM2ULONG(arg0);
	len    = NUM2ULONG(arg1);
	if( TYPE(arg2) == T_STRING ){
	    mem = StringValuePtr(arg2);
	}
	else if( rb_obj_is_kind_of(arg2, rb_cDLCPtr) ){
	    mem = rb_dlptr2cptr(arg2);
	}
	else{
	    mem    = NUM2PTR(arg2);
	}
	memcpy((char *)RPTR_DATA(self)->ptr + offset, mem, len);
	retval = arg2;
	break;
      default:
	rb_bug("rb_dlptr_aset()");
    }
    return retval;
}

VALUE
rb_dlptr_size(int argc, VALUE argv[], VALUE self)
{
    VALUE size;

    if (rb_scan_args(argc, argv, "01", &size) == 0){
	return LONG2NUM(RPTR_DATA(self)->size);
    }
    else{
	RPTR_DATA(self)->size = NUM2LONG(size);
	return size;
    }
}

VALUE
rb_dlptr_s_to_ptr(VALUE self, VALUE val)
{
    VALUE ptr;

    if (rb_obj_is_kind_of(val, rb_cIO) == Qtrue){
	rb_io_t *fptr;
	FILE *fp;
	GetOpenFile(val, fptr);
	fp = rb_io_stdio_file(fptr);
	ptr = rb_dlptr_new(fp, 0, NULL);
    }
    else if (rb_obj_is_kind_of(val, rb_cString) == Qtrue){
        char *str = StringValuePtr(val);
        ptr = rb_dlptr_new(str, RSTRING_LEN(val), NULL); 
    }
    else if (rb_respond_to(val, id_to_ptr)){
	VALUE vptr = rb_funcall(val, id_to_ptr, 0);
	if (rb_obj_is_kind_of(vptr, rb_cDLCPtr)){
	    ptr = vptr;
	}
	else{
	    rb_raise(rb_eDLError, "to_ptr should return a CPtr object");
	}
    }
    else{
	ptr = rb_dlptr_new(NUM2PTR(rb_Integer(val)), 0, NULL);
    }
    OBJ_INFECT(ptr, val);
    return ptr;
}

void
Init_dlptr(void)
{
    id_to_ptr = rb_intern("to_ptr");

    rb_cDLCPtr = rb_define_class_under(rb_mDL, "CPtr", rb_cObject);
    rb_define_alloc_func(rb_cDLCPtr, rb_dlptr_s_allocate);
    rb_define_singleton_method(rb_cDLCPtr, "malloc", rb_dlptr_s_malloc, -1);
    rb_define_singleton_method(rb_cDLCPtr, "to_ptr", rb_dlptr_s_to_ptr, 1);
    rb_define_singleton_method(rb_cDLCPtr, "[]", rb_dlptr_s_to_ptr, 1);
    rb_define_method(rb_cDLCPtr, "initialize", rb_dlptr_initialize, -1);
    rb_define_method(rb_cDLCPtr, "free=", rb_dlptr_free_set, 1);
    rb_define_method(rb_cDLCPtr, "free",  rb_dlptr_free_get, 0);
    rb_define_method(rb_cDLCPtr, "to_i",  rb_dlptr_to_i, 0);
    rb_define_method(rb_cDLCPtr, "to_value",  rb_dlptr_to_value, 0);
    rb_define_method(rb_cDLCPtr, "ptr",   rb_dlptr_ptr, 0);
    rb_define_method(rb_cDLCPtr, "+@", rb_dlptr_ptr, 0);
    rb_define_method(rb_cDLCPtr, "ref",   rb_dlptr_ref, 0);
    rb_define_method(rb_cDLCPtr, "-@", rb_dlptr_ref, 0);
    rb_define_method(rb_cDLCPtr, "null?", rb_dlptr_null_p, 0);
    rb_define_method(rb_cDLCPtr, "to_s", rb_dlptr_to_s, -1);
    rb_define_method(rb_cDLCPtr, "to_str", rb_dlptr_to_str, -1);
    rb_define_method(rb_cDLCPtr, "inspect", rb_dlptr_inspect, 0);
    rb_define_method(rb_cDLCPtr, "<=>", rb_dlptr_cmp, 1);
    rb_define_method(rb_cDLCPtr, "==", rb_dlptr_eql, 1);
    rb_define_method(rb_cDLCPtr, "eql?", rb_dlptr_eql, 1);
    rb_define_method(rb_cDLCPtr, "+", rb_dlptr_plus, 1);
    rb_define_method(rb_cDLCPtr, "-", rb_dlptr_minus, 1);
    rb_define_method(rb_cDLCPtr, "[]", rb_dlptr_aref, -1);
    rb_define_method(rb_cDLCPtr, "[]=", rb_dlptr_aset, -1);
    rb_define_method(rb_cDLCPtr, "size", rb_dlptr_size, -1);
    rb_define_method(rb_cDLCPtr, "size=", rb_dlptr_size, -1);

    rb_define_const(rb_mDL, "NULL", rb_dlptr_new(0, 0, 0));
}
