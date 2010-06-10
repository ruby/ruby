/*
 * $Id$
 */

#include <ruby.h>
#include <rubyio.h>
#include <ctype.h>
#include "dl.h"

VALUE rb_mDL;
VALUE rb_eDLError;
VALUE rb_eDLTypeError;

static VALUE DLFuncTable;
static void *rb_dl_callback_table[CALLBACK_TYPES][MAX_CALLBACK];
static ID id_call;

static int
rb_dl_scan_callback_args(long stack[], const char *proto,
			 int *argc, VALUE argv[])
{
  int i;
  long *sp;
  VALUE val;

  sp = stack;
  for (i=1; proto[i]; i++) {
    switch (proto[i]) {
    case 'C':
      {
	char v;
	v = (char)(*sp);
	sp++;
	val = INT2NUM(v);
      }
      break;
    case 'H':
      {
	short v;
	v = (short)(*sp);
	sp++;
	val = INT2NUM(v);
      }
      break;
    case 'I':
      {
	int v;
	v = (int)(*sp);
	sp++;
	val = INT2NUM(v);
      }
      break;
    case 'L':
      {
	long v;
	v = (long)(*sp);
	sp++;
	val = INT2NUM(v);
      }
      break;
    case 'F':
      {
	float v;
	memcpy(&v, sp, sizeof(float));
	sp += sizeof(float)/sizeof(long);
	val = rb_float_new(v);
      }
      break;
    case 'D':
      {
	double v;
	memcpy(&v, sp, sizeof(double));
	sp += sizeof(double)/sizeof(long);
	val = rb_float_new(v);
      }
      break;
    case 'P':
      {
	void *v;
	memcpy(&v, sp, sizeof(void*));
	sp++;
	val = rb_dlptr_new(v, 0, 0);
      }
      break;
    case 'S':
      {
	char *v;
	memcpy(&v, sp, sizeof(void*));
	sp++;
	val = rb_tainted_str_new2(v);
      }
      break;
    default:
      rb_raise(rb_eDLTypeError, "unsupported type `%c'", proto[i]);
      break;
    }
    argv[i-1] = val;
  }
  *argc = (i - 1);

  return (*argc);
}

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

  newstr = (char*)dlmalloc(strlen(str)+1);
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
  for (i=0; i<len; i++) {
    n = 1;
    if (isdigit(cstr[i+1])) {
      dlen = 1;
      while (isdigit(cstr[i+dlen])) { dlen ++; };
      dlen --;
      d = ALLOCA_N(char, dlen + 1);
      strncpy(d, cstr + i + 1, dlen);
      d[dlen] = '\0';
      n = atoi(d);
    }
    else{
      dlen = 0;
    }

    switch (cstr[i]) {
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
    case 'S':
      DLALIGN(0,size,VOIDP_ALIGN);
    case 'p':
    case 's':
      size += sizeof(void*) * n;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type '%c'", cstr[i]);
      break;
    }
    i += dlen;
  }

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
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
    case T_FLOAT:
      ary[i] = (float)(RFLOAT(e)->value);
      break;
    case T_NIL:
      ary[i] = 0.0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    }
  }

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
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
    case T_FLOAT:
      ary[i] = (double)(RFLOAT(e)->value);
      break;
    case T_NIL:
      ary[i] = 0.0;
      break;
    default:
      rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      break;
    }
  }

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
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
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
    }
  }

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
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
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
    }
  }

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
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
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
    }
  }

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
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
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
    }
  }

  return ary;
}

static void *
c_parray(VALUE v, long *size)
{
  int i, len;
  void **ary;
  VALUE e, tmp;

  len = RARRAY(v)->len;
  *size = sizeof(void*) * len;
  ary = dlmalloc(*size);
  for (i=0; i < len; i++) {
    e = rb_ary_entry(v, i);
    switch (TYPE(e)) {
    default:
      tmp = rb_check_string_type(e);
      if (NIL_P(tmp)) {
	  rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
      }
      e = tmp;
      /* fall through */
    case T_STRING:
      SafeStringValue(e);
      {
	char *str, *src;
	src = RSTRING(e)->ptr;
	str = dlstrdup(src);
	ary[i] = (void*)str;
      }
      break;
    case T_NIL:
      ary[i] = NULL;
      break;
    case T_DATA:
      if (rb_obj_is_kind_of(e, rb_cDLPtrData)) {
	struct ptr_data *pdata;
	Data_Get_Struct(e, struct ptr_data, pdata);
	ary[i] = (void*)(pdata->ptr);
      }
      else{
        e = rb_funcall(e, rb_intern("to_ptr"), 0);
        if (rb_obj_is_kind_of(e, rb_cDLPtrData)) {
	  struct ptr_data *pdata;
	  Data_Get_Struct(e, struct ptr_data, pdata);
	  ary[i] = (void*)(pdata->ptr);
	}
	else{
	  rb_raise(rb_eDLTypeError, "unexpected type of the element #%d", i);
	}
      }
      break;
    }
  }

  return ary;
}

void *
rb_ary2cary(char t, VALUE v, long *size)
{
  int len;
  VALUE val0;

  val0 = rb_check_array_type(v);
  if(NIL_P(val0)) {
    rb_raise(rb_eDLTypeError, "an array is expected.");
  }
  v = val0;

  len = RARRAY(v)->len;
  if (len == 0) {
    return NULL;
  }

  if (!size) {
    size = ALLOCA_N(long,1);
  }

  val0 = rb_ary_entry(v,0);
  switch (TYPE(val0)) {
  case T_FIXNUM:
  case T_BIGNUM:
    switch (t) {
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
    }
  case T_STRING:
    return (void*)c_parray(v,size);
  case T_FLOAT:
    switch (t) {
    case 'F': case 'f':
      return (void*)c_farray(v,size);
    case 'D': case 'd': case 0:
      return (void*)c_darray(v,size);
    }
    rb_raise(rb_eDLTypeError, "type mismatch");
  case T_DATA:
    if (rb_obj_is_kind_of(val0, rb_cDLPtrData)) {
      return (void*)c_parray(v,size);
    }
    else{
      val0 = rb_funcall(val0, rb_intern("to_ptr"), 0);
      if (rb_obj_is_kind_of(val0, rb_cDLPtrData)) {
        return (void*)c_parray(v,size);
      }
    }
    rb_raise(rb_eDLTypeError, "type mismatch");
  case T_NIL:
    return (void*)c_parray(v, size);
  default:
    rb_raise(rb_eDLTypeError, "unsupported type");
  }
}

VALUE
rb_str_to_ptr(VALUE self)
{
  char *ptr;
  int  len;
  VALUE p;

  len = RSTRING(self)->len;
  ptr = (char*)dlmalloc(len + 1);
  memcpy(ptr, RSTRING(self)->ptr, len);
  ptr[len] = '\0';
  p = rb_dlptr_new((void*)ptr,len,dlfree);
  OBJ_INFECT(p, self);
  return p;
}

VALUE
rb_ary_to_ptr(int argc, VALUE argv[], VALUE self)
{
  void *ptr;
  VALUE t;
  long size;

  switch (rb_scan_args(argc, argv, "01", &t)) {
  case 1:
    ptr = rb_ary2cary(StringValuePtr(t)[0], self, &size);
    break;
  case 0:
    ptr = rb_ary2cary(0, self, &size);
    break;
  default:
    return Qnil;
  }
  if (ptr) {
      VALUE p = rb_dlptr_new(ptr, size, dlfree);
      OBJ_INFECT(p, self);
      return p;
  }
  return Qnil;
}

VALUE
rb_io_to_ptr(VALUE self)
{
  rb_io_t *fptr;
  FILE     *fp;

  GetOpenFile(self, fptr);
  fp = fptr->f;

  return fp ? rb_dlptr_new(fp, 0, 0) : Qnil;
}

VALUE
rb_dl_dlopen(int argc, VALUE argv[], VALUE self)
{
  rb_secure(2);
  return rb_class_new_instance(argc, argv, rb_cDLHandle);
}

VALUE
rb_dl_malloc(VALUE self, VALUE size)
{
  rb_secure(4);
  return rb_dlptr_malloc(DLNUM2LONG(size), dlfree);
}

VALUE
rb_dl_strdup(VALUE self, VALUE str)
{
  SafeStringValue(str);
  return rb_dlptr_new(strdup(RSTRING(str)->ptr), strlen(RSTRING(str)->ptr)+1, dlfree);
}

static VALUE
rb_dl_sizeof(VALUE self, VALUE str)
{
  return INT2NUM(dlsizeof(StringValuePtr(str)));
}

static VALUE
rb_dl_callback(int argc, VALUE argv[], VALUE self)
{
  VALUE type, proc;
  int rettype, entry, i;
  char fname[127];

  rb_secure(4);
  proc = Qnil;
  switch (rb_scan_args(argc, argv, "11", &type, &proc)) {
  case 1:
    if (rb_block_given_p()) {
      proc = rb_block_proc();
    }
    else{
      proc = Qnil;
    }
  default:
    break;
  }

  StringValue(type);
  switch (RSTRING(type)->ptr[0]) {
  case '0':
    rettype = 0x00;
    break;
  case 'C':
    rettype = 0x01;
    break;
  case 'H':
    rettype = 0x02;
    break;
  case 'I':
    rettype = 0x03;
    break;
  case 'L':
    rettype = 0x04;
    break;
  case 'F':
    rettype = 0x05;
    break;
  case 'D':
    rettype = 0x06;
    break;
  case 'P':
    rettype = 0x07;
    break;
  default:
    rb_raise(rb_eDLTypeError, "unsupported type `%c'", RSTRING(type)->ptr[0]);
  }

  entry = -1;
  for (i=0; i < MAX_CALLBACK; i++) {
    if (rb_hash_aref(DLFuncTable, rb_assoc_new(INT2NUM(rettype), INT2NUM(i))) == Qnil) {
      entry = i;
      break;
    }
  }
  if (entry < 0) {
    rb_raise(rb_eDLError, "too many callbacks are defined.");
  }

  rb_hash_aset(DLFuncTable,
	       rb_assoc_new(INT2NUM(rettype),INT2NUM(entry)),
	       rb_assoc_new(type,proc));
  sprintf(fname, "rb_dl_callback_func_%d_%d", rettype, entry);
  return rb_dlsym_new((void (*)())rb_dl_callback_table[rettype][entry],
		      fname, RSTRING(type)->ptr);
}

static VALUE
rb_dl_remove_callback(VALUE mod, VALUE sym)
{
  freefunc_t f;
  int i, j;

  rb_secure(4);
  f = rb_dlsym2csym(sym);
  for (i=0; i < CALLBACK_TYPES; i++) {
    for (j=0; j < MAX_CALLBACK; j++) {
      if (rb_dl_callback_table[i][j] == f) {
	rb_hash_aset(DLFuncTable, rb_assoc_new(INT2NUM(i),INT2NUM(j)),Qnil);
	break;
      }
    }
  }
  return Qnil;
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

  rb_define_const(rb_mDL, "MAX_ARG", INT2NUM(MAX_ARG));
  rb_define_const(rb_mDL, "DLSTACK", rb_tainted_str_new2(DLSTACK_METHOD));

  rb_define_module_function(rb_mDL, "dlopen", rb_dl_dlopen, -1);
  rb_define_module_function(rb_mDL, "callback", rb_dl_callback, -1);
  rb_define_module_function(rb_mDL, "define_callback", rb_dl_callback, -1);
  rb_define_module_function(rb_mDL, "remove_callback", rb_dl_remove_callback, 1);
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
