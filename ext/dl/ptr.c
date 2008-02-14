/* -*- C -*-
 * $Id$
 */

#include <ruby.h>
#include <ctype.h>
#include "st.h"
#include "dl.h"

VALUE rb_cDLPtrData;
VALUE rb_mDLMemorySpace;
static st_table* st_memory_table;

#ifndef T_SYMBOL
# define T_SYMBOL T_FIXNUM
#endif

static void
rb_dlmem_delete(void *ptr)
{
  rb_secure(4);
  st_delete(st_memory_table, (st_data_t*)&ptr, NULL);
}

static void
rb_dlmem_aset(void *ptr, VALUE obj)
{
  if (obj == Qnil) {
    rb_dlmem_delete(ptr);
  }
  else{
    st_insert(st_memory_table, (st_data_t)ptr, (st_data_t)obj);
  }
}

static VALUE
rb_dlmem_aref(void *ptr)
{
  VALUE val;

  if(!st_lookup(st_memory_table, (st_data_t)ptr, &val)) return Qnil;
  return val == Qundef ? Qnil : val;
}

void
dlptr_free(struct ptr_data *data)
{
  if (data->ptr) {
    DEBUG_CODE({
      printf("dlptr_free(): removing the pointer `0x%x' from the MemorySpace\n",
	     data->ptr);
    });
    rb_dlmem_delete(data->ptr);
    if (data->free) {
      DEBUG_CODE({
	printf("dlptr_free(): 0x%x(data->ptr:0x%x)\n",data->free,data->ptr);
      });
      (*(data->free))(data->ptr);
    }
  }
  if (data->stype) dlfree(data->stype);
  if (data->ssize) dlfree(data->ssize);
  if (data->ids) dlfree(data->ids);
}

void
dlptr_init(VALUE val)
{
  struct ptr_data *data;

  Data_Get_Struct(val, struct ptr_data, data);
  DEBUG_CODE({
    printf("dlptr_init(): add the pointer `0x%x' to the MemorySpace\n",
	   data->ptr);
  });
  rb_dlmem_aset(data->ptr, val);
  OBJ_TAINT(val);
}

VALUE
rb_dlptr_new2(VALUE klass, void *ptr, long size, freefunc_t func)
{
  struct ptr_data *data;
  VALUE val;

  rb_secure(4);
  if (ptr) {
    val = rb_dlmem_aref(ptr);
    if (val == Qnil) {
      val = Data_Make_Struct(klass, struct ptr_data,
			     0, dlptr_free, data);
      data->ptr = ptr;
      data->free = func;
      data->ctype = DLPTR_CTYPE_UNKNOWN;
      data->stype = NULL;
      data->ssize = NULL;
      data->slen = 0;
      data->size = size;
      data->ids = NULL;
      data->ids_num = 0;
      dlptr_init(val);
    }
    else{
      if (func) {
	Data_Get_Struct(val, struct ptr_data, data);
	data->free = func;
      }
    }
  }
  else{
    val = Qnil;
  }

  return val;
}

VALUE
rb_dlptr_new(void *ptr, long size, freefunc_t func)
{
  return rb_dlptr_new2(rb_cDLPtrData, ptr, size, func);
}

VALUE
rb_dlptr_malloc(long size, freefunc_t func)
{
  void *ptr;

  rb_secure(4);
  ptr = dlmalloc((size_t)size);
  memset(ptr,0,(size_t)size);
  return rb_dlptr_new(ptr, size, func);
}

void *
rb_dlptr2cptr(VALUE val)
{
  struct ptr_data *data;
  void *ptr;

  if (rb_obj_is_kind_of(val, rb_cDLPtrData)) {
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
  obj = Data_Make_Struct(klass, struct ptr_data, 0, dlptr_free, data);
  data->ptr = 0;
  data->free = 0;
  data->ctype = DLPTR_CTYPE_UNKNOWN;
  data->stype = NULL;
  data->ssize = NULL;
  data->slen  = 0;
  data->size  = 0;
  data->ids   = NULL;
  data->ids_num = 0;

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
    p = (void*)(DLNUM2LONG(rb_Integer(ptr)));
    break;
  case 2:
    p = (void*)(DLNUM2LONG(rb_Integer(ptr)));
    s = DLNUM2LONG(size);
    break;
  case 3:
    p = (void*)(DLNUM2LONG(rb_Integer(ptr)));
    s = DLNUM2LONG(size);
    f = rb_dlsym2csym(sym);
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
  freefunc_t f = NULL;

  switch (rb_scan_args(argc, argv, "11", &size, &sym)) {
  case 1:
    s = NUM2INT(size);
    break;
  case 2:
    s = NUM2INT(size);
    f = rb_dlsym2csym(sym);
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
  return DLLONG2NUM(data->ptr);
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

  Data_Get_Struct(self, struct ptr_data, data);

  data->free = DLFREEFUNC(rb_dlsym2csym(val));

  return Qnil;
}

VALUE
rb_dlptr_free_get(VALUE self)
{
  struct ptr_data *pdata;

  Data_Get_Struct(self, struct ptr_data, pdata);

  return rb_dlsym_new(pdata->free,"(free)","0P");
}

VALUE
rb_dlptr_to_array(int argc, VALUE argv[], VALUE self)
{
  struct ptr_data *data;
  int n;
  int i;
  int t;
  VALUE ary;
  VALUE type, size;

  Data_Get_Struct(self, struct ptr_data, data);

  switch (rb_scan_args(argc, argv, "11", &type, &size)) {
  case 2:
    t = StringValuePtr(type)[0];
    n = NUM2INT(size);
    break;
  case 1:
    t = StringValuePtr(type)[0];
    switch (t) {
    case 'C':
      n = data->size;
      break;
    case 'H':
      n = data->size / sizeof(short);
      break;
    case 'I':
      n = data->size / sizeof(int);
      break;
    case 'L':
      n = data->size / sizeof(long);
      break;
    case 'F':
      n = data->size / sizeof(float);
      break;
    case 'D':
      n = data->size / sizeof(double);
      break;
    case  'P': case 'p':
      n = data->size / sizeof(void*);
      break;
    case 'S': case 's':
      n = data->size / sizeof(char*);
      break;
    default:
	n = 0;
    }
    break;
  default:
    rb_bug("rb_dlptr_to_array");
  }

  ary = rb_ary_new();

  for (i=0; i < n; i++) {
    switch (t) {
    case 'C':
      rb_ary_push(ary, INT2NUM(((char*)(data->ptr))[i]));
      break;
    case 'H':
      rb_ary_push(ary, INT2NUM(((short*)(data->ptr))[i]));
      break;
    case 'I':
      rb_ary_push(ary, INT2NUM(((int*)(data->ptr))[i]));
      break;
    case 'L':
      rb_ary_push(ary, DLLONG2NUM(((long*)(data->ptr))[i]));
      break;
    case 'D':
      rb_ary_push(ary, rb_float_new(((double*)(data->ptr))[i]));
      break;
    case 'F':
      rb_ary_push(ary, rb_float_new(((float*)(data->ptr))[i]));
      break;
    case 'S':
      {
	char *str = ((char**)(data->ptr))[i];
	if (str) {
	  rb_ary_push(ary, rb_tainted_str_new2(str));
	}
	else{
	  rb_ary_push(ary, Qnil);
	}
      }
      break;
    case 's':
      {
	char *str = ((char**)(data->ptr))[i];
	if (str) {
	  rb_ary_push(ary, rb_tainted_str_new2(str));
	  xfree(str);
	}
	else{
	  rb_ary_push(ary, Qnil);
	}
      }
      break;
    case 'P':
      rb_ary_push(ary, rb_dlptr_new(((void**)(data->ptr))[i],0,0));
      break;
    case 'p':
      rb_ary_push(ary,
		  rb_dlptr_new(((void**)(data->ptr))[i],0,dlfree));
      break;
    }
  }

  return ary;
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
  snprintf(str, 1023, "#<%s:0x%lx ptr=0x%lx size=%ld free=0x%lx>",
	   rb_class2name(CLASS_OF(self)), data, data->ptr, data->size,
	   (long)data->free);
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
  return DLLONG2NUM((long)ptr1 - (long)ptr2);
}

VALUE
rb_dlptr_plus(VALUE self, VALUE other)
{
  void *ptr;
  long num, size;

  ptr = rb_dlptr2cptr(self);
  size = RDLPTR(self)->size;
  num = DLNUM2LONG(other);
  return rb_dlptr_new((char *)ptr + num, size - num, 0);
}

VALUE
rb_dlptr_minus(VALUE self, VALUE other)
{
  void *ptr;
  long num, size;

  ptr = rb_dlptr2cptr(self);
  size = RDLPTR(self)->size;
  num = DLNUM2LONG(other);
  return rb_dlptr_new((char *)ptr - num, size + num, 0);
}

VALUE
rb_dlptr_define_data_type(int argc, VALUE argv[], VALUE self)
{
  VALUE data_type, type, rest, vid;
  struct ptr_data *data;
  int i, t, num;
  char *ctype;

  rb_scan_args(argc, argv, "11*", &data_type, &type, &rest);
  Data_Get_Struct(self, struct ptr_data, data);

  if (argc == 1 || (argc == 2 && type == Qnil)) {
    if (NUM2INT(data_type) == DLPTR_CTYPE_UNKNOWN) {
      data->ctype = DLPTR_CTYPE_UNKNOWN;
      data->slen = 0;
      data->ids_num  = 0;
      if (data->stype) {
	dlfree(data->stype);
	data->stype = NULL;
      }
      if (data->ids) {
	dlfree(data->ids);
	data->ids = NULL;
      }
      return Qnil;
    }
    else{
      rb_raise(rb_eArgError, "wrong arguments");
    }
  }

  t = NUM2INT(data_type);
  StringValue(type);
  Check_Type(rest, T_ARRAY);
  num = RARRAY(rest)->len;
  for (i=0; i<num; i++) {
    rb_to_id(rb_ary_entry(rest,i));
  }

  data->ctype = t;
  data->slen = num;
  data->ids_num  = num;
  if (data->stype) dlfree(data->stype);
  data->stype = (char*)dlmalloc(sizeof(char) * num);
  if (data->ssize) dlfree(data->ssize);
  data->ssize = (int*)dlmalloc(sizeof(int) * num);
  if (data->ids) dlfree(data->ids);
  data->ids  = (ID*)dlmalloc(sizeof(ID) * data->ids_num);

  ctype = StringValuePtr(type);
  for (i=0; i<num; i++) {
    vid = rb_ary_entry(rest,i);
    data->ids[i] = rb_to_id(vid);
    data->stype[i] = *ctype;
    ctype ++;
    if (isdigit(*ctype)) {
      char *p, *d;
      for (p=ctype; isdigit(*p); p++) ;
      d = ALLOCA_N(char, p - ctype + 1);
      strncpy(d, ctype, p - ctype);
      d[p - ctype] = '\0';
      data->ssize[i] = atoi(d);
      ctype = p;
    }
    else{
      data->ssize[i] = 1;
    }
  }

  if (*ctype) {
    rb_raise(rb_eArgError, "too few/many arguments");
  }

  if (!data->size)
    data->size = dlsizeof(RSTRING(type)->ptr);

  return Qnil;
}

VALUE
rb_dlptr_define_struct(int argc, VALUE argv[], VALUE self)
{
  VALUE *pass_argv;
  int pass_argc, i;

  pass_argc = argc + 1;
  pass_argv = ALLOCA_N(VALUE, pass_argc);
  pass_argv[0] = INT2FIX(DLPTR_CTYPE_STRUCT);
  for (i=1; i<pass_argc; i++) {
    pass_argv[i] = argv[i-1];
  }
  return rb_dlptr_define_data_type(pass_argc, pass_argv, self);
}

VALUE
rb_dlptr_define_union(int argc, VALUE argv[], VALUE self)
{
  VALUE *pass_argv;
  int pass_argc, i;

  pass_argc = argc + 1;
  pass_argv = ALLOCA_N(VALUE, pass_argc);
  pass_argv[0] = INT2FIX(DLPTR_CTYPE_UNION);
  for (i=1; i<pass_argc; i++) {
    pass_argv[i] = argv[i-1];
  }
  return rb_dlptr_define_data_type(pass_argc, pass_argv, self);
}

VALUE
rb_dlptr_get_data_type(VALUE self)
{
  struct ptr_data *data;

  Data_Get_Struct(self, struct ptr_data, data);
  if (data->stype)
    return rb_assoc_new(INT2FIX(data->ctype),
			rb_tainted_str_new(data->stype, data->slen));
  else
    return rb_assoc_new(INT2FIX(data->ctype), Qnil);
}

static VALUE
cary2ary(void *ptr, char t, int len)
{
  VALUE ary;
  VALUE elem;
  int i;

  if (len < 1)
    return Qnil;

  if (len == 1) {
    switch (t) {
    case 'I':
      elem = INT2NUM(*((int*)ptr));
      ptr = (char *)ptr + sizeof(int);
      break;
    case 'L':
      elem = DLLONG2NUM(*((long*)ptr));
      ptr = (char *)ptr + sizeof(long);
      break;
    case 'P':
    case 'S':
      elem = rb_dlptr_new(*((void**)ptr),0, 0);
      ptr = (char *)ptr + sizeof(void*);
      break;
    case 'F':
      elem = rb_float_new(*((float*)ptr));
      ptr = (char *)ptr + sizeof(float);
      break;
    case 'D':
      elem = rb_float_new(*((double*)ptr));
      ptr = (char *)ptr + sizeof(double);
      break;
    case 'C':
      elem = INT2NUM(*((char*)ptr));
      ptr = (char *)ptr + sizeof(char);
      break;
    case 'H':
      elem = INT2NUM(*((short*)ptr));
      ptr = (char *)ptr + sizeof(short);
      break;
    default:
      rb_raise(rb_eDLTypeError, "unsupported type '%c'", t);
    }
    return elem;
  }

  ary = rb_ary_new();
  for (i=0; i < len; i++) {
    switch (t) {
    case 'I':
      elem = INT2NUM(*((int*)ptr));
      ptr = (char *)ptr + sizeof(int);
      break;
    case 'L':
      elem = DLLONG2NUM(*((long*)ptr));
      ptr = (char *)ptr + sizeof(long);
      break;
    case 'P':
    case 'S':
      elem = rb_dlptr_new(*((void**)ptr), 0, 0);
      ptr = (char *)ptr + sizeof(void*);
      break;
    case 'F':
      elem = rb_float_new(*((float*)ptr));
      ptr = (char *)ptr + sizeof(float);
      break;
    case 'D':
      elem = rb_float_new(*((float*)ptr));
      ptr = (char *)ptr + sizeof(double);
      break;
    case 'C':
      elem = INT2NUM(*((char*)ptr));
      ptr = (char *)ptr + sizeof(char);
      break;
    case 'H':
      elem = INT2NUM(*((short*)ptr));
      ptr = (char *)ptr + sizeof(short);
      break;
    default:
      rb_raise(rb_eDLTypeError, "unsupported type '%c'", t);
    }
    rb_ary_push(ary, elem);
  }

  return ary;
}

VALUE
rb_dlptr_aref(int argc, VALUE argv[], VALUE self)
{
  VALUE key = Qnil, num = Qnil;
  ID id;
  struct ptr_data *data;
  int i;
  int offset;

  if (rb_scan_args(argc, argv, "11", &key, &num) == 1) {
    num = INT2NUM(0);
  }

  if (TYPE(key) == T_FIXNUM || TYPE(key) == T_BIGNUM) {
    VALUE pass[1];
    pass[0] = num;
    return rb_dlptr_to_str(1, pass, rb_dlptr_plus(self, key));
  }
  rb_to_id(key);
  if (! (TYPE(key) == T_STRING || TYPE(key) == T_SYMBOL)) {
    rb_raise(rb_eTypeError, "the key must be a string or symbol");
  }

  id = rb_to_id(key);
  Data_Get_Struct(self, struct ptr_data, data);
  offset = 0;
  switch (data->ctype) {
  case DLPTR_CTYPE_STRUCT:
    for (i=0; i < data->ids_num; i++) {
      switch (data->stype[i]) {
      case 'I':
        DLALIGN(data->ptr,offset,INT_ALIGN);
        break;
      case 'L':
        DLALIGN(data->ptr,offset,LONG_ALIGN);
        break;
      case 'P':
      case 'S':
        DLALIGN(data->ptr,offset,VOIDP_ALIGN);
        break;
      case 'F':
        DLALIGN(data->ptr,offset,FLOAT_ALIGN);
        break;
      case 'D':
        DLALIGN(data->ptr,offset,DOUBLE_ALIGN);
        break;
      case 'C':
        break;
      case 'H':
        DLALIGN(data->ptr,offset,SHORT_ALIGN);
        break;
      default:
        rb_raise(rb_eDLTypeError, "unsupported type '%c'", data->stype[i]);
      }
      if (data->ids[i] == id) {
	return cary2ary((char *)data->ptr + offset, data->stype[i], data->ssize[i]);
      }
      switch (data->stype[i]) {
      case 'I':
	offset += sizeof(int) * data->ssize[i];
	break;
      case 'L':
	offset += sizeof(long) * data->ssize[i];
	break;
      case 'P':
      case 'S':
	offset += sizeof(void*) * data->ssize[i];
	break;
      case 'F':
	offset += sizeof(float) * data->ssize[i];
	break;
      case 'D':
	offset += sizeof(double) * data->ssize[i];
	break;
      case 'C':
	offset += sizeof(char) * data->ssize[i];
	break;
      case 'H':
	offset += sizeof(short) * data->ssize[i];
	break;
      default:
	rb_raise(rb_eDLTypeError, "unsupported type '%c'", data->stype[i]);
      }
    }
    break;
  case DLPTR_CTYPE_UNION:
    for (i=0; i < data->ids_num; i++) {
      if (data->ids[i] == id) {
	return cary2ary((char *)data->ptr + offset, data->stype[i], data->ssize[i]);
      }
    }
    break;
  } /* end of switch */

  rb_raise(rb_eNameError, "undefined key `%s' for %s",
	   rb_id2name(id), rb_class2name(CLASS_OF(self)));

  return Qnil;
}

static void *
ary2cary(char t, VALUE val, long *size)
{
  void *ptr;

  if (TYPE(val) == T_ARRAY) {
    ptr = rb_ary2cary(t, val, size);
  }
  else{
    ptr = rb_ary2cary(t, rb_ary_new3(1, val), size);
  }
  return ptr;
}

VALUE
rb_dlptr_aset(int argc, VALUE argv[], VALUE self)
{
  VALUE key = Qnil, num = Qnil, val = Qnil;
  ID id;
  struct ptr_data *data;
  int i;
  int offset;
  long memsize;
  void *memimg;

  rb_secure(4);
  switch (rb_scan_args(argc, argv, "21", &key, &num, &val)) {
  case 2:
    val = num;
    num = Qnil;
    break;
  }

  if (TYPE(key) == T_FIXNUM || TYPE(key) == T_BIGNUM) {
    void *dst, *src;
    long len;

    StringValue(val);
    Data_Get_Struct(self, struct ptr_data, data);
    dst = (void*)((long)(data->ptr) + DLNUM2LONG(key));
    src = RSTRING(val)->ptr;
    len = RSTRING(val)->len;
    if (num == Qnil) {
      memcpy(dst, src, len);
    }
    else{
      long n = NUM2INT(num);
      memcpy(dst, src, n < len ? n : len);
      if (n > len) MEMZERO((char*)dst + len, char, n - len);
    }
    return val;
  }

  id = rb_to_id(key);
  Data_Get_Struct(self, struct ptr_data, data);
  switch (data->ctype) {
  case DLPTR_CTYPE_STRUCT:
    offset = 0;
    for (i=0; i < data->ids_num; i++) {
      switch (data->stype[i]) {
      case 'I':
        DLALIGN(data->ptr,offset,INT_ALIGN);
        break;
      case 'L':
        DLALIGN(data->ptr,offset,LONG_ALIGN);
        break;
      case 'P':
      case 'S':
        DLALIGN(data->ptr,offset,VOIDP_ALIGN);
        break;
      case 'D':
        DLALIGN(data->ptr,offset,DOUBLE_ALIGN);
        break;
      case 'F':
        DLALIGN(data->ptr,offset,FLOAT_ALIGN);
        break;
      case 'C':
        break;
      case 'H':
        DLALIGN(data->ptr,offset,SHORT_ALIGN);
        break;
      default:
        rb_raise(rb_eDLTypeError, "unsupported type '%c'", data->stype[i]);
      }
      if (data->ids[i] == id) {
	memimg = ary2cary(data->stype[i], val, &memsize);
	memcpy((char *)data->ptr + offset, memimg, memsize);
        dlfree(memimg);
	return val;
      }
      switch (data->stype[i]) {
      case 'I':
      case 'i':
	offset += sizeof(int) * data->ssize[i];
	break;
      case 'L':
      case 'l':
	offset += sizeof(long) * data->ssize[i];
	break;
      case 'P':
      case 'p':
      case 'S':
      case 's':
	offset += sizeof(void*) * data->ssize[i];
	break;
      case 'D':
      case 'd':
	offset += sizeof(double) * data->ssize[i];
	break;
      case 'F':
      case 'f':
	offset += sizeof(float) * data->ssize[i];
	break;
      case 'C':
      case 'c':
	offset += sizeof(char) * data->ssize[i];
	break;
      case 'H':
      case 'h':
	offset += sizeof(short) * data->ssize[i];
	break;
      default:
	rb_raise(rb_eDLTypeError, "unsupported type '%c'", data->stype[i]);
      }
    }
    return val;
    /* break; */
  case DLPTR_CTYPE_UNION:
    for (i=0; i < data->ids_num; i++) {
      if (data->ids[i] == id) {
	switch (data->stype[i]) {
	case 'I': case 'i':
	  memsize = sizeof(int) * data->ssize[i];
	  break;
	case 'L': case 'l':
	  memsize = sizeof(long) * data->ssize[i];
	  break;
	case 'P': case 'p':
	case 'S': case 's':
	  memsize = sizeof(void*) * data->ssize[i];
	  break;
	case 'F': case 'f':
	  memsize = sizeof(float) * data->ssize[i];
	  break;
	case 'D': case 'd':
	  memsize = sizeof(double) * data->ssize[i];
	  break;
	case 'C': case 'c':
	  memsize = sizeof(char) * data->ssize[i];
	  break;
	case 'H': case 'h':
	  memsize = sizeof(short) * data->ssize[i];
	  break;
	default:
	  rb_raise(rb_eDLTypeError, "unsupported type '%c'", data->stype[i]);
	}
	memimg = ary2cary(data->stype[i], val, NULL);
	memcpy(data->ptr, memimg, memsize);
        dlfree(memimg);
      }
    }
    return val;
    /* break; */
  }

  rb_raise(rb_eNameError, "undefined key `%s' for %s",
	   rb_id2name(id), rb_class2name(CLASS_OF(self)));

  return Qnil;
}

VALUE
rb_dlptr_size(int argc, VALUE argv[], VALUE self)
{
  VALUE size;

  if (rb_scan_args(argc, argv, "01", &size) == 0){
    return DLLONG2NUM(RDLPTR(self)->size);
  }
  else{
    RDLPTR(self)->size = DLNUM2LONG(size);
    return size;
  }
}

static int
dlmem_each_i(void* key, VALUE value, void* arg)
{
  VALUE vkey = DLLONG2NUM(key);
  rb_yield(rb_assoc_new(vkey, value));
  return Qnil;
}

VALUE
rb_dlmem_each(VALUE self)
{
  st_foreach(st_memory_table, dlmem_each_i, 0);
  return Qnil;
}

void
Init_dlptr()
{
  rb_cDLPtrData = rb_define_class_under(rb_mDL, "PtrData", rb_cObject);
  rb_define_alloc_func(rb_cDLPtrData, rb_dlptr_s_allocate);
  rb_define_singleton_method(rb_cDLPtrData, "malloc", rb_dlptr_s_malloc, -1);
  rb_define_method(rb_cDLPtrData, "initialize", rb_dlptr_initialize, -1);
  rb_define_method(rb_cDLPtrData, "free=", rb_dlptr_free_set, 1);
  rb_define_method(rb_cDLPtrData, "free",  rb_dlptr_free_get, 0);
  rb_define_method(rb_cDLPtrData, "to_i",  rb_dlptr_to_i, 0);
  rb_define_method(rb_cDLPtrData, "ptr",   rb_dlptr_ptr, 0);
  rb_define_method(rb_cDLPtrData, "+@", rb_dlptr_ptr, 0);
  rb_define_method(rb_cDLPtrData, "ref",   rb_dlptr_ref, 0);
  rb_define_method(rb_cDLPtrData, "-@", rb_dlptr_ref, 0);
  rb_define_method(rb_cDLPtrData, "null?", rb_dlptr_null_p, 0);
  rb_define_method(rb_cDLPtrData, "to_a", rb_dlptr_to_array, -1);
  rb_define_method(rb_cDLPtrData, "to_s", rb_dlptr_to_s, -1);
  rb_define_method(rb_cDLPtrData, "to_str", rb_dlptr_to_str, -1);
  rb_define_method(rb_cDLPtrData, "inspect", rb_dlptr_inspect, 0);
  rb_define_method(rb_cDLPtrData, "<=>", rb_dlptr_cmp, 1);
  rb_define_method(rb_cDLPtrData, "==", rb_dlptr_eql, 1);
  rb_define_method(rb_cDLPtrData, "eql?", rb_dlptr_eql, 1);
  rb_define_method(rb_cDLPtrData, "+", rb_dlptr_plus, 1);
  rb_define_method(rb_cDLPtrData, "-", rb_dlptr_minus, 1);
  rb_define_method(rb_cDLPtrData, "define_data_type",
		   rb_dlptr_define_data_type, -1);
  rb_define_method(rb_cDLPtrData, "struct!", rb_dlptr_define_struct, -1);
  rb_define_method(rb_cDLPtrData, "union!",  rb_dlptr_define_union,  -1);
  rb_define_method(rb_cDLPtrData, "data_type", rb_dlptr_get_data_type, 0);
  rb_define_method(rb_cDLPtrData, "[]", rb_dlptr_aref, -1);
  rb_define_method(rb_cDLPtrData, "[]=", rb_dlptr_aset, -1);
  rb_define_method(rb_cDLPtrData, "size", rb_dlptr_size, -1);
  rb_define_method(rb_cDLPtrData, "size=", rb_dlptr_size, -1);

  rb_mDLMemorySpace = rb_define_module_under(rb_mDL, "MemorySpace");
  st_memory_table = st_init_numtable();
  rb_define_const(rb_mDLMemorySpace, "MemoryTable", Qnil); /* historical */
  rb_define_module_function(rb_mDLMemorySpace, "each", rb_dlmem_each, 0);
}
