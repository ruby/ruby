/*
 * 'OpenSSL for Ruby' team members
 * Copyright (C) 2003
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

BIO *
ossl_obj2bio(volatile VALUE *pobj)
{
    VALUE obj = *pobj;
    BIO *bio;

    if (RB_TYPE_P(obj, T_FILE))
	obj = rb_funcallv(obj, rb_intern("read"), 0, NULL);
    StringValue(obj);
    bio = BIO_new_mem_buf(RSTRING_PTR(obj), RSTRING_LENINT(obj));
    if (!bio)
	ossl_raise(eOSSLError, "BIO_new_mem_buf");
    *pobj = obj;
    return bio;
}

VALUE
ossl_membio2str0(BIO *bio)
{
    VALUE ret;
    BUF_MEM *buf;

    BIO_get_mem_ptr(bio, &buf);
    ret = rb_str_new(buf->data, buf->length);

    return ret;
}

VALUE
ossl_protect_membio2str(BIO *bio, int *status)
{
    return rb_protect((VALUE (*)(VALUE))ossl_membio2str0, (VALUE)bio, status);
}

VALUE
ossl_membio2str(BIO *bio)
{
    VALUE ret;
    int status = 0;

    ret = ossl_protect_membio2str(bio, &status);
    BIO_free(bio);
    if(status) rb_jump_tag(status);

    return ret;
}
