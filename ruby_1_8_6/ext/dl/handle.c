/* -*- C -*-
 * $Id$
 */

#include <ruby.h>
#include "dl.h"

VALUE rb_cDLHandle;

void
dlhandle_free(struct dl_handle *dlhandle)
{
  if (dlhandle->ptr && dlhandle->open && dlhandle->enable_close) {
    dlclose(dlhandle->ptr);
  }
}

VALUE
rb_dlhandle_close(VALUE self)
{
  struct dl_handle *dlhandle;

  Data_Get_Struct(self, struct dl_handle, dlhandle);
  dlhandle->open = 0;
  return INT2NUM(dlclose(dlhandle->ptr));
}

VALUE
rb_dlhandle_s_allocate(VALUE klass)
{
  VALUE obj;
  struct dl_handle *dlhandle;

  obj = Data_Make_Struct(rb_cDLHandle, struct dl_handle, 0,
			 dlhandle_free, dlhandle);
  dlhandle->ptr  = 0;
  dlhandle->open = 0;
  dlhandle->enable_close = 0;

  return obj;
}

VALUE
rb_dlhandle_initialize(int argc, VALUE argv[], VALUE self)
{
  void *ptr;
  struct dl_handle *dlhandle;
  VALUE lib, flag;
  char  *clib;
  int   cflag;
  const char *err;

  switch (rb_scan_args(argc, argv, "11", &lib, &flag)) {
  case 1:
    clib = NIL_P(lib) ? NULL : StringValuePtr(lib);
    cflag = RTLD_LAZY | RTLD_GLOBAL;
    break;
  case 2:
    clib = NIL_P(lib) ? NULL : StringValuePtr(lib);
    cflag = NUM2INT(flag);
    break;
  default:
    rb_bug("rb_dlhandle_new");
  }

  ptr = dlopen(clib, cflag);
#if defined(HAVE_DLERROR)
  if (!ptr && (err = dlerror())) {
    rb_raise(rb_eRuntimeError, "%s", err);
  }
#else
  if (!ptr) {
    err = dlerror();
    rb_raise(rb_eRuntimeError, "%s", err);
  }
#endif
  Data_Get_Struct(self, struct dl_handle, dlhandle);
  if (dlhandle->ptr && dlhandle->open && dlhandle->enable_close) {
    dlclose(dlhandle->ptr);
  }
  dlhandle->ptr = ptr;
  dlhandle->open = 1;
  dlhandle->enable_close = 0;

  if (rb_block_given_p()) {
    rb_ensure(rb_yield, self, rb_dlhandle_close, self);
  }

  return Qnil;
}

VALUE
rb_dlhandle_enable_close(VALUE self)
{
  struct dl_handle *dlhandle;

  Data_Get_Struct(self, struct dl_handle, dlhandle);
  dlhandle->enable_close = 1;
  return Qnil;
}

VALUE
rb_dlhandle_disable_close(VALUE self)
{
  struct dl_handle *dlhandle;

  Data_Get_Struct(self, struct dl_handle, dlhandle);
  dlhandle->enable_close = 0;
  return Qnil;
}

VALUE
rb_dlhandle_to_i(VALUE self)
{
  struct dl_handle *dlhandle;

  Data_Get_Struct(self, struct dl_handle, dlhandle);
  return DLLONG2NUM(dlhandle);
}

VALUE
rb_dlhandle_to_ptr(VALUE self)
{
  struct dl_handle *dlhandle;

  Data_Get_Struct(self, struct dl_handle, dlhandle);
  return rb_dlptr_new(dlhandle, sizeof(dlhandle), 0);
}

VALUE
rb_dlhandle_sym(int argc, VALUE argv[], VALUE self)
{
  VALUE sym, type;
  void (*func)();
  VALUE val;
  struct dl_handle *dlhandle;
  void *handle;
  const char *name, *stype;
  const char *err;

  rb_secure(2);
  if (rb_scan_args(argc, argv, "11", &sym, &type) == 2) {
    SafeStringValue(type);
    stype = StringValuePtr(type);
  }
  else{
    stype = NULL;
  }

  if (sym == Qnil) {
#if defined(RTLD_NEXT)
    name = RTLD_NEXT;
#else
    name = NULL;
#endif
  }
  else{
    SafeStringValue(sym);
    name = StringValuePtr(sym);
  }

  Data_Get_Struct(self, struct dl_handle, dlhandle);
  if (!dlhandle->open) {
    rb_raise(rb_eRuntimeError, "closed handle");
  }
  handle = dlhandle->ptr;

  func = dlsym(handle, name);
#if defined(HAVE_DLERROR)
  if (!func && (err = dlerror()))
#else
  if (!func)
#endif
  {
#if defined(__CYGWIN__) || defined(WIN32) || defined(__MINGW32__)
    {
      int  len = strlen(name);
      char *name_a = (char*)dlmalloc(len+2);
      strcpy(name_a, name);
      name_a[len]   = 'A';
      name_a[len+1] = '\0';
      func = dlsym(handle, name_a);
      dlfree(name_a);
#if defined(HAVE_DLERROR)
      if (!func && (err = dlerror()))
#else
      if (!func)
#endif
      {
	rb_raise(rb_eRuntimeError, "unknown symbol \"%sA\"", name);
      }
    }
#else
    rb_raise(rb_eRuntimeError, "unknown symbol \"%s\"", name);
#endif
  }
  val = rb_dlsym_new(func, name, stype);

  return val;
}

void
Init_dlhandle()
{
  rb_cDLHandle = rb_define_class_under(rb_mDL, "Handle", rb_cObject);
  rb_define_alloc_func(rb_cDLHandle, rb_dlhandle_s_allocate);
  rb_define_method(rb_cDLHandle, "initialize", rb_dlhandle_initialize, -1);
  rb_define_method(rb_cDLHandle, "to_i", rb_dlhandle_to_i, 0);
  rb_define_method(rb_cDLHandle, "to_ptr", rb_dlhandle_to_ptr, 0);
  rb_define_method(rb_cDLHandle, "close", rb_dlhandle_close, 0);
  rb_define_method(rb_cDLHandle, "sym",  rb_dlhandle_sym, -1);
  rb_define_method(rb_cDLHandle, "[]",  rb_dlhandle_sym, -1);
  rb_define_method(rb_cDLHandle, "disable_close", rb_dlhandle_disable_close, 0);
  rb_define_method(rb_cDLHandle, "enable_close", rb_dlhandle_enable_close, 0);
}
