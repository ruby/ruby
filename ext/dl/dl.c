/*
 * $Id$
 */

#include <ruby.h>
#include <rubyio.h>
#include "dl.h"

VALUE rb_mDL;
VALUE rb_eDLError;
VALUE rb_eDLTypeError;

static VALUE DLFuncTable;
static void *rb_dl_func_table[MAX_CALLBACK_TYPE][MAX_CALLBACK];
static ID id_call;

#include "callback.func"

static void
init_dl_func_table(){
#include "cbtable.func"
}

void *
dlmalloc(size_t size)
{
  DEBUG_CODE2({
    void *ptr;

    printf("dlmalloc(%d)",size);
    ptr = xmalloc(size);
    printf(":0x%x\n",ptr);
    return ptr;
  },
  {
    return xmalloc(size);
  });
}

void *
dlrealloc(void *ptr, size_t size)
{
  DEBUG_CODE({
    printf("dlrealloc(0x%x,%d)\n",ptr,size);
  });
  return xrealloc(ptr, size);
}

void
dlfree(void *ptr)
{
  DEBUG_CODE({
    printf("dlfree(0x%x)\n",ptr);
  });
  xfree(ptr);
}

char*
dlstrdup(const char *str)
{
  char *newstr;

  newstr = (char*)dlmalloc(strlen(str));
  strcpy(newstr,str);

  return newstr;
}

size_t
dlsizeof(const char *cstr)
{
  size_t size;
  int i, len, n, dlen;
  char *d;

  len  = strlen(cstr);
  size = 0;
  for( i=0; i<len; i++ ){
    n = 1;
    if( isdigit(cstr[i+1]) ){
      dlen = 1;
      while( isdigit(cstr[i+dlen]) ){ dlen ++; };
      dlen --;
      d = ALLOCA_N(char, dlen + 1);
      strncpy(d, cstr + i + 1, dlen);
      d[dlen] = '\0';
      n = atoi(d);
    }
    else{
      dlen = 0;
    };

    switch( cstr[i] ){
    case 'I':
      DLALIGN(0,size,INT_ALIGN);
    case 'i':
      size += sizeof(int) * n;
      break;
    case 'L':
      DLALIGN(0,size,LONG_ALIGN);
    case 'l':
      size += sizeof(long) * n;
      break;
    case 'F':
      DLALIGN(0,size,FLOAT_ALIGN);
    case 'f':
      size += sizeof(float) * n;
      break;
    case 'D':
      DLALIGN(0,size,DOUBLE_ALIGN);
    case 'd':
      size += sizeof(double) * n;
      break;
    case 'C':
    case 'c':
      size += sizeof(char) * n;
      break;
    case 'H':
      DLALIGN(0,size,SHORT_ALIGN);
    case 'h':
      size += sizeof(short) * n;
      break;
    case 'P':
      DLALIGN(0,size,VOIDP_ALIGN);
    case 'p':
      size += sizeof(void*) * n;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type '%c'", cstr[i]);
      break;
    };
    i += dlen;
  };

  return size;
}

static float *
c_farray(VALUE v, long *size)
{
  int i, len;
  float *ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(float) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_FLOAT:
      ary[i] = (float)(RFLOAT(e)->value);
      break;
    case T_NIL:
      ary[i] = 0.0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

static double *
c_darray(VALUE v, long *size)
{
  int i, len;
  double *ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(double) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_FLOAT:
      ary[i] = (double)(RFLOAT(e)->value);
      break;
    case T_NIL:
      ary[i] = 0.0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

static long *
c_larray(VALUE v, long *size)
{
  int i, len;
  long *ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(long) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_FIXNUM:
    case T_BIGNUM:
      ary[i] = (long)(NUM2INT(e));
      break;
    case T_NIL:
      ary[i] = 0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

static int *
c_iarray(VALUE v, long *size)
{
  int i, len;
  int *ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(int) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_FIXNUM:
    case T_BIGNUM:
      ary[i] = (int)(NUM2INT(e));
      break;
    case T_NIL:
      ary[i] = 0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

static short *
c_harray(VALUE v, long *size)
{
  int i, len;
  short *ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(short) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_FIXNUM:
    case T_BIGNUM:
      ary[i] = (short)(NUM2INT(e));
      break;
    case T_NIL:
      ary[i] = 0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

static char *
c_carray(VALUE v, long *size)
{
  int i, len;
  char *ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(char) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_FIXNUM:
    case T_BIGNUM:
      ary[i] = (char)(NUM2INT(e));
      break;
    case T_NIL:
      ary[i] = 0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

static void *
c_parray(VALUE v, long *size)
{
  int i, len;
  void **ary;
  VALUE e;

  len = RARRAY(v)->len;
  *size = sizeof(void*) * len;
  ary = dlmalloc(*size);
  for( i=0; i < len; i++ ){
    e = rb_ary_entry(v, i);
    switch( TYPE(e) ){
    case T_STRING:
      {
	char *str, *src;
	src = StringValuePtr(e);
	str = dlstrdup(src);
	ary[i] = (void*)str;
      };
      break;
    case T_NIL:
      ary[i] = NULL;
      break;
    case T_DATA:
      if( rb_obj_is_kind_of(e, rb_cDLPtrData) ){
	struct ptr_data *pdata;
	Data_Get_Struct(e, struct ptr_data, pdata);
	ary[i] = (void*)(pdata->ptr);
      }
      else{
	rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      };
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    };
  };

  return ary;
}

void *
rb_ary2cary(char t, VALUE v, long *size)
{
  int len;
  VALUE val0;

  if( TYPE(v) != T_ARRAY ){
    rb_raise(rb_eDLTypeError, "an array is expected.");
  };

  len = RARRAY(v)->len;
  if( len == 0 ){
    return NULL;
  };

  if( !size ){
    size = ALLOCA_N(long,1);
  };

  val0 = rb_ary_entry(v,0);
  switch( TYPE(val0) ){
  case T_FIXNUM:
  case T_BIGNUM:
    switch( t ){
    case 'C': case 'c':
      return (void*)c_carray(v,size);
    case 'H': case 'h':
      return (void*)c_harray(v,size);
    case 'I': case 'i':
      return (void*)c_iarray(v,size);
    case 'L': case 'l': case 0:
      return (void*)c_larray(v,size);
    default:
      rb_raise(rb_eDLTypeError, "type mismatch");
    };
  case T_STRING:
    return (void*)c_parray(v,size);
  case T_FLOAT:
    switch( t ){
    case 'F': case 'f':
      return (void*)c_farray(v,size);
    case 'D': case 'd': case 0:
      return (void*)c_darray(v,size);
    };
    rb_raise(rb_eDLTypeError, "type mismatch");
  case T_DATA:
    if( rb_obj_is_kind_of(val0, rb_cDLPtrData) ){
      return (void*)c_parray(v,size);
    };
    rb_raise(rb_eDLTypeError, "type mismatch");
  default:
    rb_raise(rb_eDLTypeError, "unsupported type");
  };
}

VALUE
rb_str_to_ptr(VALUE self)
{
  char *ptr;
  int  len;

  len = RSTRING(self)->len;
  ptr = (char*)dlmalloc(len + 1);
  memcpy(ptr, RSTRING(self)->ptr, len);
  ptr[len] = '\0';
  return rb_dlptr_new((void*)ptr,len,dlfree);
}

VALUE
rb_ary_to_ptr(int argc, VALUE argv[], VALUE self)
{
  void *ptr;
  VALUE t;
  long size;

  switch( rb_scan_args(argc, argv, "01", &t) ){
  case 1:
    ptr = rb_ary2cary(StringValuePtr(t)[0], self, &size);
    break;
  case 0:
    ptr = rb_ary2cary(0, self, &size);
    break;
  };
  return ptr ? rb_dlptr_new(ptr, size, dlfree) : Qnil;
}

VALUE
rb_io_to_ptr(VALUE self)
{
  OpenFile *fptr;
  FILE     *fp;

  GetOpenFile(self, fptr);
  fp = fptr->f;

  return fp ? rb_dlptr_new(fp, sizeof(FILE), 0) : Qnil;
};

VALUE
rb_dl_dlopen(int argc, VALUE argv[], VALUE self)
{
  return rb_dlhandle_s_new(argc, argv, rb_cDLHandle);
}

VALUE
rb_dl_malloc(VALUE self, VALUE size)
{
  void *ptr;
  long s;

  s = DLNUM2LONG(size);
  ptr = dlmalloc((size_t)s);
  memset(ptr,0,(size_t)s);
  return rb_dlptr_new(ptr, s, dlfree);
}

VALUE
rb_dl_strdup(VALUE self, VALUE str)
{
  void *p;

  str = rb_String(str);
  return rb_dlptr_new(strdup(StringValuePtr(str)), RSTRING(str)->len, dlfree);
}

static VALUE
rb_dl_sizeof(VALUE self, VALUE str)
{
  return INT2NUM(dlsizeof(StringValuePtr(str)));
}

static VALUE
rb_dl_callback_type(VALUE str)
{
  char *type;
  int len;
  int i;
  long ftype;

  ftype = 0;
  type = StringValuePtr(str);
  len  = RSTRING(str)->len;

  if( len - 1 > MAX_CBARG ){
    rb_raise(rb_eDLError, "maximum number of the argument is %d.", MAX_CBARG);
  };

  for( i = len - 1; i > 0; i-- ){
    switch( type[i] ){
    case 'P':
      CBPUSH_P(ftype);
      break;
    case 'I':
      CBPUSH_I(ftype);
      break;
    case 'L':
      CBPUSH_L(ftype);
      break;
    case 'F':
      CBPUSH_F(ftype);
      break;
    case 'D':
      CBPUSH_D(ftype);
    default:
      rb_raise(rb_eDLError, "unsupported type `%c'", type[i]);
      break;
    };
  }

  switch( type[0] ){
  case '0':
    CBPUSH_0(ftype);
    break;
  case 'P':
    CBPUSH_P(ftype);
    break;
  case 'I':
    CBPUSH_I(ftype);
    break;
  case 'L':
    CBPUSH_L(ftype);
    break;
  case 'F':
    CBPUSH_F(ftype);
    break;
  case 'D':
    CBPUSH_D(ftype);
    break;
  default:
    rb_raise(rb_eDLError, "unsupported type `%c'", type[i]);
    break;
  };

  return INT2NUM(ftype);
}

VALUE
rb_dl_set_callback(int argc, VALUE argv[], VALUE self)
{
  VALUE types, num, proc;
  VALUE key;
  VALUE entry;
  void *func;

  char func_name[1024];
  extern dln_sym();

  switch( rb_scan_args(argc, argv, "21", &types, &num, &proc) ){
  case 2:
    proc = rb_f_lambda();
    break;
  case 3:
    break;
  default:
    rb_bug("rb_dl_set_callback");
  };

  key = rb_dl_callback_type(types);
  entry = rb_hash_aref(DLFuncTable, key);
  if( entry == Qnil ){
    entry = rb_hash_new();
    rb_hash_aset(DLFuncTable, key, entry);
  };

  func = rb_dl_func_table[NUM2INT(key)][NUM2INT(num)];
  if( func ){
    rb_hash_aset(entry, num, proc);
    snprintf(func_name, 1023, "rb_dl_func%d_%d", NUM2INT(key), NUM2INT(num));
    return rb_dlsym_new(func, func_name, StringValuePtr(types));
  }
  else{
    return Qnil;
  };
}

VALUE
rb_dl_get_callback(VALUE self, VALUE types, VALUE num)
{
  VALUE key;
  VALUE entry;

  key = rb_dl_callback_type(types);
  entry = rb_hash_aref(DLFuncTable, key);
  if( entry == Qnil ){
    return Qnil;
  };
  return rb_hash_aref(entry, num);
}

void
Init_dl()
{
  void Init_dlptr();
  void Init_dlsym();
  void Init_dlhandle();

  id_call = rb_intern("call");

  rb_mDL = rb_define_module("DL");

  rb_eDLError = rb_define_class_under(rb_mDL, "DLError", rb_eStandardError);
  rb_eDLTypeError = rb_define_class_under(rb_mDL, "DLTypeError", rb_eDLError);

  DLFuncTable = rb_hash_new();
  init_dl_func_table();
  rb_define_const(rb_mDL, "FuncTable", DLFuncTable);

  rb_define_const(rb_mDL, "RTLD_GLOBAL", INT2NUM(RTLD_GLOBAL));
  rb_define_const(rb_mDL, "RTLD_LAZY",   INT2NUM(RTLD_LAZY));
  rb_define_const(rb_mDL, "RTLD_NOW",    INT2NUM(RTLD_NOW));

  rb_define_const(rb_mDL, "ALIGN_INT",   INT2NUM(ALIGN_INT));
  rb_define_const(rb_mDL, "ALIGN_LONG",  INT2NUM(ALIGN_LONG));
  rb_define_const(rb_mDL, "ALIGN_FLOAT", INT2NUM(ALIGN_FLOAT));
  rb_define_const(rb_mDL, "ALIGN_SHORT", INT2NUM(ALIGN_SHORT));
  rb_define_const(rb_mDL, "ALIGN_DOUBLE",INT2NUM(ALIGN_DOUBLE));
  rb_define_const(rb_mDL, "ALIGN_VOIDP", INT2NUM(ALIGN_VOIDP));

  rb_define_const(rb_mDL, "VERSION",     rb_tainted_str_new2(DL_VERSION));
  rb_define_const(rb_mDL, "MAJOR_VERSION", INT2NUM(DL_MAJOR_VERSION));
  rb_define_const(rb_mDL, "MINOR_VERSION", INT2NUM(DL_MINOR_VERSION));
  rb_define_const(rb_mDL, "PATCH_VERSION", INT2NUM(DL_PATCH_VERSION));
  rb_define_const(rb_mDL, "MAX_ARG", INT2NUM(MAX_ARG));
  rb_define_const(rb_mDL, "MAX_CBARG", INT2NUM(MAX_CBARG));
  rb_define_const(rb_mDL, "MAX_CBENT", INT2NUM(MAX_CBENT));

  rb_define_module_function(rb_mDL, "dlopen", rb_dl_dlopen, -1);
  rb_define_module_function(rb_mDL, "set_callback", rb_dl_set_callback, -1);
  rb_define_module_function(rb_mDL, "get_callback", rb_dl_get_callback, 2);
  rb_define_module_function(rb_mDL, "malloc", rb_dl_malloc, 1);
  rb_define_module_function(rb_mDL, "strdup", rb_dl_strdup, 1);
  rb_define_module_function(rb_mDL, "sizeof", rb_dl_sizeof, 1);

  Init_dlptr();
  Init_dlsym();
  Init_dlhandle();

  rb_define_const(rb_mDL, "FREE", rb_dlsym_new(dlfree, "free", "0P"));

  rb_define_method(rb_cString, "to_ptr", rb_str_to_ptr, 0);
  rb_define_method(rb_cArray, "to_ptr", rb_ary_to_ptr, -1);
  rb_define_method(rb_cIO, "to_ptr", rb_io_to_ptr, 0);
}
