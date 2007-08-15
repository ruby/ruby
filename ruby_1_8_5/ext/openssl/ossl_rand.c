/*
 * $Id: ossl_rand.c,v 1.2 2003/09/17 09:05:02 gotoyuzo Exp $
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

/*
 * Classes
 */
VALUE mRandom;
VALUE eRandomError;

/*
 * Struct
 */

/*
 * Public
 */

/*
 * Private
 */
static VALUE
ossl_rand_seed(VALUE self, VALUE str)
{
    StringValue(str);
    RAND_seed(RSTRING(str)->ptr, RSTRING(str)->len);

    return str;
}

static VALUE
ossl_rand_load_file(VALUE self, VALUE filename)
{
    SafeStringValue(filename);
	
    if(!RAND_load_file(RSTRING(filename)->ptr, -1)) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

static VALUE
ossl_rand_write_file(VALUE self, VALUE filename)
{
    SafeStringValue(filename);
    if (RAND_write_file(RSTRING(filename)->ptr) == -1) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

static VALUE
ossl_rand_bytes(VALUE self, VALUE len)
{
    VALUE str;
	
    str = rb_str_new(0, FIX2INT(len));
    if (!RAND_bytes(RSTRING(str)->ptr, FIX2INT(len))) {
	ossl_raise(eRandomError, NULL);
    }

    return str;
}

static VALUE
ossl_rand_pseudo_bytes(VALUE self, VALUE len)
{
    VALUE str;

    str = rb_str_new(0, FIX2INT(len));
    if (!RAND_pseudo_bytes(RSTRING(str)->ptr, FIX2INT(len))) {
	ossl_raise(eRandomError, NULL);
    }

    return str;
}

static VALUE
ossl_rand_egd(VALUE self, VALUE filename)
{
    SafeStringValue(filename);
	
    if(!RAND_egd(RSTRING(filename)->ptr)) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

static VALUE
ossl_rand_egd_bytes(VALUE self, VALUE filename, VALUE len)
{
    SafeStringValue(filename);

    if (!RAND_egd_bytes(RSTRING(filename)->ptr, FIX2INT(len))) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

#define DEFMETH(class, name, func, argc) \
	rb_define_method(class, name, func, argc); \
	rb_define_singleton_method(class, name, func, argc);

/*
 * INIT
 */
void
Init_ossl_rand()
{
    mRandom = rb_define_module_under(mOSSL, "Random");
	
    eRandomError = rb_define_class_under(mRandom, "RandomError", eOSSLError);
	
    DEFMETH(mRandom, "seed", ossl_rand_seed, 1);
    DEFMETH(mRandom, "load_random_file", ossl_rand_load_file, 1);
    DEFMETH(mRandom, "write_random_file", ossl_rand_write_file, 1);
    DEFMETH(mRandom, "random_bytes", ossl_rand_bytes, 1);
    DEFMETH(mRandom, "pseudo_bytes", ossl_rand_pseudo_bytes, 1);
    DEFMETH(mRandom, "egd", ossl_rand_egd, 1);
    DEFMETH(mRandom, "egd_bytes", ossl_rand_egd_bytes, 2);	
}

