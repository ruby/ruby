/************************************************

  md5init.c -

  $Author$
  created at: Fri Aug  2 09:24:12 JST 1996

  Copyright (C) 1995 Yukihiro Matsumoto

************************************************/
/* This module provides an interface to the RSA Data Security,
   Inc. MD5 Message-Digest Algorithm, described in RFC 1321.
   It requires the files md5c.c and md5.h (which are slightly changed
   from the versions in the RFC to avoid the "global.h" file.) */

#include "ruby.h"
#include "md5.h"

static VALUE cMD5;

static VALUE
md5_update(obj, str)
    VALUE obj;
    struct RString *str;
{
    MD5_CTX *md5;

    Check_Type(str, T_STRING);
    Data_Get_Struct(obj, MD5_CTX, md5);
    MD5Update(md5, str->ptr, str->len);

    return Qnil;
}
static VALUE
md5_digest(obj)
    VALUE obj;
{
    MD5_CTX *md5, ctx;
    unsigned char digest[16];

    Data_Get_Struct(obj, MD5_CTX, md5);
    ctx = *md5;
    MD5Final(digest, &ctx);

    return str_new(digest, 16);
}

static VALUE
md5_clone(obj)
    VALUE obj;
{
    VALUE clone;
    MD5_CTX *md5, *md5_new;

    Data_Get_Struct(obj, MD5_CTX, md5);
    obj = Data_Make_Struct(CLASS_OF(obj), MD5_CTX, 0, 0, md5_new);
    *md5_new = *md5;

    return obj;
}

static VALUE
md5_new(argc, argv, class)
{
    int i;
    VALUE arg, obj;
    MD5_CTX *md5;

    rb_scan_args(argc, argv, "01", &arg);
    if (!NIL_P(arg)) Check_Type(arg, T_STRING);

    obj = Data_Make_Struct(class, MD5_CTX, 0, 0, md5);
    MD5Init(md5);
    if (!NIL_P(arg)) {
	md5_update(obj, arg);
    }

    return obj;
}

Init_md5()
{
    cMD5 = rb_define_class("MD5", cObject);

    rb_define_singleton_method(cMD5, "new", md5_new, -1);

    rb_define_method(cMD5, "update", md5_update, 1);
    rb_define_method(cMD5, "digest", md5_digest, 0);
    rb_define_method(cMD5, "clone",  md5_clone, 0);
}
