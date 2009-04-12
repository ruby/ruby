/* -*- C -*-
 * $Id$
 */

#include <ruby.h>
#include "dl.h"

VALUE rb_cDLHandle;

void
dlhandle_free(struct dl_handle *dlhandle)
{
  if( dlhandle->ptr && dlhandle->open && dlhandle->enable_close ){
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

  switch( rb_scan_args(argc, argv, "02", &lib, &flag) ){
  case 0:
    clib = NULL;
    cflag = RTLD_LAZY | RTLD_GLOBAL;
    break;
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
  if( !ptr && (err = dlerror()) ){
    rb_raise(rb_eDLError, "%s", err);
  }
#else
  if( !ptr ){
    err = dlerror();
    rb_raise(rb_eDLError, "%s", err);
  }
#endif
  Data_Get_Struct(self, struct dl_handle, dlhandle);
  if( dlhandle->ptr && dlhandle->open && dlhandle->enable_close ){
    dlclose(dlhandle->ptr);
  }
  dlhandle->ptr = ptr;
  dlhandle->open = 1;
  dlhandle->enable_close = 0;

  if( rb_block_given_p() ){
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
  return PTR2NUM(dlhandle);
}

VALUE
rb_dlhandle_sym(VALUE self, VALUE sym)
{
    void (*func)();
    struct dl_handle *dlhandle;
    void *handle;
    const char *name;
    const char *err;
    int i;

#if defined(HAVE_DLERROR)
# define CHECK_DLERROR if( err = dlerror() ){ func = 0; }
#else
# define CHECK_DLERROR
#endif

    rb_secure(2);

    if( sym == Qnil ){
#if defined(RTLD_NEXT)
	name = RTLD_NEXT;
#else
	name = NULL;
#endif
    }
    else{
	name = StringValuePtr(sym);
    }


    Data_Get_Struct(self, struct dl_handle, dlhandle);
    if( ! dlhandle->open ){
	rb_raise(rb_eDLError, "closed handle");
    }
    handle = dlhandle->ptr;

    func = dlsym(handle, name);
    CHECK_DLERROR;
#if defined(FUNC_STDCALL)
    if( !func ){
	int  len = strlen(name);
	char *name_n;
#if defined(__CYGWIN__) || defined(_WIN32) || defined(__MINGW32__)
	{
	    char *name_a = (char*)xmalloc(len+2);
	    strcpy(name_a, name);
	    name_n = name_a;
	    name_a[len]   = 'A';
	    name_a[len+1] = '\0';
	    func = dlsym(handle, name_a);
	    CHECK_DLERROR;
	    if( func ) goto found;
	    name_n = xrealloc(name_a, len+6);
	}
#else
	name_n = (char*)xmalloc(len+6);
#endif
	memcpy(name_n, name, len);
	name_n[len++] = '@';
	for( i = 0; i < 256; i += 4 ){
	    sprintf(name_n + len, "%d", i);
	    func = dlsym(handle, name_n);
	    CHECK_DLERROR;
	    if( func ) break;
	}
	if( func ) goto found;
	name_n[len-1] = 'A';
	name_n[len++] = '@';
	for( i = 0; i < 256; i += 4 ){
	    sprintf(name_n + len, "%d", i);
	    func = dlsym(handle, name_n);
	    CHECK_DLERROR;
	    if( func ) break;
	}
      found:
	xfree(name_n);
    }
#endif
    if( !func ){
	rb_raise(rb_eDLError, "unknown symbol \"%s\"", name);
    }

    return PTR2NUM(func);
}

void
Init_dlhandle()
{
    rb_cDLHandle = rb_define_class_under(rb_mDL, "Handle", rb_cObject);
    rb_define_alloc_func(rb_cDLHandle, rb_dlhandle_s_allocate);
    rb_define_method(rb_cDLHandle, "initialize", rb_dlhandle_initialize, -1);
    rb_define_method(rb_cDLHandle, "to_i", rb_dlhandle_to_i, 0);
    rb_define_method(rb_cDLHandle, "close", rb_dlhandle_close, 0);
    rb_define_method(rb_cDLHandle, "sym",  rb_dlhandle_sym, 1);
    rb_define_method(rb_cDLHandle, "[]",  rb_dlhandle_sym,  1);
    rb_define_method(rb_cDLHandle, "disable_close", rb_dlhandle_disable_close, 0);
    rb_define_method(rb_cDLHandle, "enable_close", rb_dlhandle_enable_close, 0);
}
