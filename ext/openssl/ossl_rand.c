/*
 * $Id$
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

/*
 *  call-seq:
 *     seed(str) -> str
 *
 * ::seed is equivalent to ::add where +entropy+ is length of +str+.
 */
static VALUE
ossl_rand_seed(VALUE self, VALUE str)
{
    StringValue(str);
    RAND_seed(RSTRING_PTR(str), RSTRING_LENINT(str));

    return str;
}

/*
 *  call-seq:
 *     add(str, entropy) -> self
 *
 * Mixes the bytes from +str+ into the Pseudo Random Number Generator(PRNG) state.
 * Thus, if the data from +str+ are unpredictable to an adversary, this increases the uncertainty about the state
 * and makes the PRNG output less predictable.
 * The +entropy+ argument is (the lower bound of) an estimate of how much randomness is contained in +str+,
 * measured in bytes.
 *
 *  Example:
 *
 *    pid = $$
 *    now = Time.now
 *    ary = [now.to_i, now.nsec, 1000, pid]
 *    OpenSSL::Random.add(ary.join("").to_s, 0.0)
 *    OpenSSL::Random.seed(ary.join("").to_s)
 */
static VALUE
ossl_rand_add(VALUE self, VALUE str, VALUE entropy)
{
    StringValue(str);
    RAND_add(RSTRING_PTR(str), RSTRING_LENINT(str), NUM2DBL(entropy));

    return self;
}

/*
 *  call-seq:
 *     load_random_file(filename) -> true
 *
 * Reads bytes from +filename+ and adds them to the PRNG.
 */
static VALUE
ossl_rand_load_file(VALUE self, VALUE filename)
{
    SafeStringValue(filename);

    if(!RAND_load_file(RSTRING_PTR(filename), -1)) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     write_random_file(filename) -> true
 *
 * Writes a number of random generated bytes (currently 1024) to +filename+ which can be used to initialize the PRNG by
 * calling ::load_random_file in a later session.
 */
static VALUE
ossl_rand_write_file(VALUE self, VALUE filename)
{
    SafeStringValue(filename);
    if (RAND_write_file(RSTRING_PTR(filename)) == -1) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     -> string
 *
 * Generates +string+ with +length+ number of cryptographically strong pseudo-random bytes.
 *
 *  Example:
 *
 *    OpenSSL::Random.random_bytes(12)
 *    => "..."
 */
static VALUE
ossl_rand_bytes(VALUE self, VALUE len)
{
    VALUE str;
    int n = NUM2INT(len);

    str = rb_str_new(0, n);
    if (!RAND_bytes((unsigned char *)RSTRING_PTR(str), n)) {
	ossl_raise(eRandomError, NULL);
    }

    return str;
}

/*
 *  call-seq:
 *     -> string
 *
 * Generates +string+ with +length+ number of pseudo-random bytes.
 *
 * Pseudo-random byte sequences generated by ::pseudo_bytes will be unique if they are of sufficient length,
 * but are not necessarily unpredictable.
 *
 *  Example:
 *
 *    OpenSSL::Random.pseudo_bytes(12)
 *    => "..."
 */
static VALUE
ossl_rand_pseudo_bytes(VALUE self, VALUE len)
{
    VALUE str;
    int n = NUM2INT(len);

    str = rb_str_new(0, n);
    if (!RAND_pseudo_bytes((unsigned char *)RSTRING_PTR(str), n)) {
	ossl_raise(eRandomError, NULL);
    }

    return str;
}

/*
 *  call-seq:
 *     egd(filename) -> true
 *
 * Same as ::egd_bytes but queries 255 bytes by default.
 */
static VALUE
ossl_rand_egd(VALUE self, VALUE filename)
{
    SafeStringValue(filename);

    if(!RAND_egd(RSTRING_PTR(filename))) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     egd_bytes(filename, length) -> true
 *
 * Queries the entropy gathering daemon EGD on socket path given by +filename+.
 * Fetches +length+ number of bytes and uses ::add to seed the OpenSSL built-in PRNG.
 */
static VALUE
ossl_rand_egd_bytes(VALUE self, VALUE filename, VALUE len)
{
    int n = NUM2INT(len);

    SafeStringValue(filename);

    if (!RAND_egd_bytes(RSTRING_PTR(filename), n)) {
	ossl_raise(eRandomError, NULL);
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     status? => true | false
 *
 * Return true if the PRNG has been seeded with enough data, false otherwise.
 */
static VALUE
ossl_rand_status(VALUE self)
{
    return RAND_status() ? Qtrue : Qfalse;
}

/*
 * INIT
 */
void
Init_ossl_rand(void)
{
#if 0
    mOSSL = rb_define_module("OpenSSL"); /* let rdoc know about mOSSL */
#endif

    mRandom = rb_define_module_under(mOSSL, "Random");

    eRandomError = rb_define_class_under(mRandom, "RandomError", eOSSLError);

    rb_define_module_function(mRandom, "seed", ossl_rand_seed, 1);
    rb_define_module_function(mRandom, "random_add", ossl_rand_add, 2);
    rb_define_module_function(mRandom, "load_random_file", ossl_rand_load_file, 1);
    rb_define_module_function(mRandom, "write_random_file", ossl_rand_write_file, 1);
    rb_define_module_function(mRandom, "random_bytes", ossl_rand_bytes, 1);
    rb_define_module_function(mRandom, "pseudo_bytes", ossl_rand_pseudo_bytes, 1);
    rb_define_module_function(mRandom, "egd", ossl_rand_egd, 1);
    rb_define_module_function(mRandom, "egd_bytes", ossl_rand_egd_bytes, 2);
    rb_define_module_function(mRandom, "status?", ossl_rand_status, 0);
}

