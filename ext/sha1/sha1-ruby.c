#include "ruby.h"
#include "sha1.h"

static VALUE cSHA1;

static VALUE
sha1_update(obj, str)
    VALUE obj;
    struct RString *str;
{
    SHA1_CTX *sha1;

    Check_Type(str, T_STRING);
    Data_Get_Struct(obj, SHA1_CTX, sha1);
    SHA1Update(sha1, str->ptr, str->len);

    return obj;
}

static VALUE
sha1_digest(obj)
    VALUE obj;
{
    SHA1_CTX *sha1, ctx;
    unsigned char digest[20];

    Data_Get_Struct(obj, SHA1_CTX, sha1);
    ctx = *sha1;
    SHA1Final(digest, &ctx);

    return rb_str_new(digest, 20);
}

static VALUE
sha1_hexdigest(obj)
    VALUE obj;
{
    SHA1_CTX *sha1, ctx;
    unsigned char digest[20];
    char buf[33];
    int i;

    Data_Get_Struct(obj, SHA1_CTX, sha1);
    ctx = *sha1;
    SHA1Final(digest, &ctx);

    for (i=0; i<20; i++) {
	sprintf(buf+i*2, "%02x", digest[i]);
    }
    return rb_str_new(buf, 40);
}

static VALUE
sha1_clone(obj)
    VALUE obj;
{
    SHA1_CTX *sha1, *sha1_new;

    Data_Get_Struct(obj, SHA1_CTX, sha1);
    obj = Data_Make_Struct(CLASS_OF(obj), SHA1_CTX, 0, free, sha1_new);
    *sha1_new = *sha1;

    return obj;
}

static VALUE
sha1_new(argc, argv, class)
    int argc;
    VALUE* argv;
    VALUE class;
{
    VALUE arg, obj;
    SHA1_CTX *sha1;

    rb_scan_args(argc, argv, "01", &arg);
    if (!NIL_P(arg)) Check_Type(arg, T_STRING);

    obj = Data_Make_Struct(class, SHA1_CTX, 0, free, sha1);
    rb_obj_call_init(obj, argc, argv);
    SHA1Init(sha1);
    if (!NIL_P(arg)) {
	sha1_update(obj, arg);
    }

    return obj;
}

void
Init_sha1()
{
    cSHA1 = rb_define_class("SHA1", rb_cObject);

    rb_define_singleton_method(cSHA1, "new", sha1_new, -1);
    rb_define_singleton_method(cSHA1, "sha1", sha1_new, -1);

    rb_define_method(cSHA1, "update", sha1_update, 1);
    rb_define_method(cSHA1, "<<", sha1_update, 1);
    rb_define_method(cSHA1, "digest", sha1_digest, 0);
    rb_define_method(cSHA1, "hexdigest", sha1_hexdigest, 0);
    rb_define_method(cSHA1, "clone",  sha1_clone, 0);
}
