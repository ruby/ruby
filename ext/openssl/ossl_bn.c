/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Technorama team <oss-ruby@technorama.net>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
/* modified by Michal Rokos <m.rokos@sh.cvut.cz> */
#include "ossl.h"

#define NewBN(klass) \
  TypedData_Wrap_Struct((klass), &ossl_bn_type, 0)
#define SetBN(obj, bn) do { \
  if (!(bn)) { \
    ossl_raise(rb_eRuntimeError, "BN wasn't initialized!"); \
  } \
  RTYPEDDATA_DATA(obj) = (bn); \
} while (0)

#define GetBN(obj, bn) do { \
  TypedData_Get_Struct((obj), BIGNUM, &ossl_bn_type, (bn)); \
  if (!(bn)) { \
    ossl_raise(rb_eRuntimeError, "BN wasn't initialized!"); \
  } \
} while (0)

#define SafeGetBN(obj, bn) do { \
  OSSL_Check_Kind((obj), cBN); \
  GetBN((obj), (bn)); \
} while (0)

static void
ossl_bn_free(void *ptr)
{
    BN_clear_free(ptr);
}

static size_t
ossl_bn_size(const void *ptr)
{
    return sizeof(BIGNUM);
}

static const rb_data_type_t ossl_bn_type = {
    "OpenSSL/BN",
    {0, ossl_bn_free, ossl_bn_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

/*
 * Classes
 */
VALUE cBN;

/* Document-class: OpenSSL::BNError
 *
 * BNError < OpenSSLError
 *
 * Generic Error for all of OpenSSL::BN (big num)
 */
VALUE eBNError;

/*
 * Public
 */
VALUE
ossl_bn_new(const BIGNUM *bn)
{
    BIGNUM *newbn;
    VALUE obj;

    obj = NewBN(cBN);
    newbn = bn ? BN_dup(bn) : BN_new();
    if (!newbn) {
	ossl_raise(eBNError, NULL);
    }
    SetBN(obj, newbn);

    return obj;
}

BIGNUM *
GetBNPtr(VALUE obj)
{
    BIGNUM *bn = NULL;
    VALUE newobj;

    if (RTEST(rb_obj_is_kind_of(obj, cBN))) {
	GetBN(obj, bn);
    } else switch (TYPE(obj)) {
    case T_FIXNUM:
    case T_BIGNUM:
	obj = rb_String(obj);
	newobj = NewBN(cBN);	/* GC bug */
	if (!BN_dec2bn(&bn, StringValuePtr(obj))) {
	    ossl_raise(eBNError, NULL);
	}
	SetBN(newobj, bn); /* Handle potencial mem leaks */
	break;
    case T_NIL:
	break;
    default:
	ossl_raise(rb_eTypeError, "Cannot convert into OpenSSL::BN");
    }
    return bn;
}

/*
 * Private
 */
/*
 * BN_CTX - is used in more difficult math. ops
 * (Why just 1? Because Ruby itself isn't thread safe,
 *  we don't need to care about threads)
 */
BN_CTX *ossl_bn_ctx;

static VALUE
ossl_bn_alloc(VALUE klass)
{
    BIGNUM *bn;
    VALUE obj = NewBN(klass);

    if (!(bn = BN_new())) {
	ossl_raise(eBNError, NULL);
    }
    SetBN(obj, bn);

    return obj;
}

/* Document-method: OpenSSL::BN.new
 *
 *    OpenSSL::BN.new => aBN
 *    OpenSSL::BN.new(bn) => aBN
 *    OpenSSL::BN.new(integer) => aBN
 *    OpenSSL::BN.new(string) => aBN
 *    OpenSSL::BN.new(string, 0 | 2 | 10 | 16) => aBN
 *
 * Construct a new OpenSSL BigNum object.
 */
static VALUE
ossl_bn_initialize(int argc, VALUE *argv, VALUE self)
{
    BIGNUM *bn;
    VALUE str, bs;
    int base = 10;

    if (rb_scan_args(argc, argv, "11", &str, &bs) == 2) {
	base = NUM2INT(bs);
    }

    if (RB_TYPE_P(str, T_FIXNUM)) {
	long i;
	unsigned char bin[sizeof(long)];
	long n = FIX2LONG(str);
	unsigned long un = labs(n);

	for (i = sizeof(long) - 1; 0 <= i; i--) {
	    bin[i] = un&0xff;
	    un >>= 8;
	}

	GetBN(self, bn);
	if (!BN_bin2bn(bin, sizeof(bin), bn)) {
	    ossl_raise(eBNError, NULL);
	}
	if (n < 0) BN_set_negative(bn, 1);
	return self;
    }
    else if (RB_TYPE_P(str, T_BIGNUM)) {
        size_t len = rb_absint_size(str, NULL);
	unsigned char *bin;
	VALUE buf;
        int sign;

        if (INT_MAX < len) {
            rb_raise(eBNError, "bignum too long");
        }
        bin = (unsigned char*)ALLOCV_N(unsigned char, buf, len);
        sign = rb_integer_pack(str, bin, len, 1, 0, INTEGER_PACK_BIG_ENDIAN);

	GetBN(self, bn);
	if (!BN_bin2bn(bin, (int)len, bn)) {
	    ALLOCV_END(buf);
	    ossl_raise(eBNError, NULL);
	}
	ALLOCV_END(buf);
	if (sign < 0) BN_set_negative(bn, 1);
	return self;
    }
    if (RTEST(rb_obj_is_kind_of(str, cBN))) {
	BIGNUM *other;

	GetBN(self, bn);
	GetBN(str, other); /* Safe - we checked kind_of? above */
	if (!BN_copy(bn, other)) {
	    ossl_raise(eBNError, NULL);
	}
	return self;
    }

    StringValue(str);
    GetBN(self, bn);
    switch (base) {
    case 0:
	if (!BN_mpi2bn((unsigned char *)RSTRING_PTR(str), RSTRING_LENINT(str), bn)) {
	    ossl_raise(eBNError, NULL);
	}
	break;
    case 2:
	if (!BN_bin2bn((unsigned char *)RSTRING_PTR(str), RSTRING_LENINT(str), bn)) {
	    ossl_raise(eBNError, NULL);
	}
	break;
    case 10:
	if (!BN_dec2bn(&bn, RSTRING_PTR(str))) {
	    ossl_raise(eBNError, NULL);
	}
	break;
    case 16:
	if (!BN_hex2bn(&bn, RSTRING_PTR(str))) {
	    ossl_raise(eBNError, NULL);
	}
	break;
    default:
	ossl_raise(rb_eArgError, "invalid radix %d", base);
    }
    return self;
}

/*
 * call-seq:
 *    bn.to_s => string
 *    bn.to_s(base) => string
 *
 * === Parameters
 * * +base+ - integer
 * * * Valid values:
 * * * * 0 - MPI
 * * * * 2 - binary
 * * * * 10 - the default
 * * * * 16 - hex
 */
static VALUE
ossl_bn_to_s(int argc, VALUE *argv, VALUE self)
{
    BIGNUM *bn;
    VALUE str, bs;
    int base = 10, len;
    char *buf;

    if (rb_scan_args(argc, argv, "01", &bs) == 1) {
	base = NUM2INT(bs);
    }
    GetBN(self, bn);
    switch (base) {
    case 0:
	len = BN_bn2mpi(bn, NULL);
        str = rb_str_new(0, len);
	if (BN_bn2mpi(bn, (unsigned char *)RSTRING_PTR(str)) != len)
	    ossl_raise(eBNError, NULL);
	break;
    case 2:
	len = BN_num_bytes(bn);
        str = rb_str_new(0, len);
	if (BN_bn2bin(bn, (unsigned char *)RSTRING_PTR(str)) != len)
	    ossl_raise(eBNError, NULL);
	break;
    case 10:
	if (!(buf = BN_bn2dec(bn))) ossl_raise(eBNError, NULL);
	str = ossl_buf2str(buf, rb_long2int(strlen(buf)));
	break;
    case 16:
	if (!(buf = BN_bn2hex(bn))) ossl_raise(eBNError, NULL);
	str = ossl_buf2str(buf, rb_long2int(strlen(buf)));
	break;
    default:
	ossl_raise(rb_eArgError, "invalid radix %d", base);
    }

    return str;
}

/*
 * call-seq:
 *    bn.to_i => integer
 */
static VALUE
ossl_bn_to_i(VALUE self)
{
    BIGNUM *bn;
    char *txt;
    VALUE num;

    GetBN(self, bn);

    if (!(txt = BN_bn2hex(bn))) {
	ossl_raise(eBNError, NULL);
    }
    num = rb_cstr_to_inum(txt, 16, Qtrue);
    OPENSSL_free(txt);

    return num;
}

static VALUE
ossl_bn_to_bn(VALUE self)
{
    return self;
}

static VALUE
ossl_bn_coerce(VALUE self, VALUE other)
{
    switch(TYPE(other)) {
    case T_STRING:
	self = ossl_bn_to_s(0, NULL, self);
	break;
    case T_FIXNUM:
    case T_BIGNUM:
	self = ossl_bn_to_i(self);
	break;
    default:
	if (!RTEST(rb_obj_is_kind_of(other, cBN))) {
	    ossl_raise(rb_eTypeError, "Don't know how to coerce");
	}
    }
    return rb_assoc_new(other, self);
}

#define BIGNUM_BOOL1(func)				\
    static VALUE					\
    ossl_bn_##func(VALUE self)				\
    {							\
	BIGNUM *bn;					\
	GetBN(self, bn);				\
	if (BN_##func(bn)) {				\
	    return Qtrue;				\
	}						\
	return Qfalse;					\
    }

/*
 * Document-method: OpenSSL::BN#zero?
 *   bn.zero? => true | false
 */
BIGNUM_BOOL1(is_zero)

/*
 * Document-method: OpenSSL::BN#one?
 *   bn.one? => true | false
 */
BIGNUM_BOOL1(is_one)

/*
 * Document-method: OpenSSL::BN#odd?
 *   bn.odd? => true | false
 */
BIGNUM_BOOL1(is_odd)

#define BIGNUM_1c(func)					\
    static VALUE					\
    ossl_bn_##func(VALUE self)				\
    {							\
	BIGNUM *bn, *result;				\
	VALUE obj;					\
	GetBN(self, bn);				\
	obj = NewBN(CLASS_OF(self));			\
	if (!(result = BN_new())) {			\
	    ossl_raise(eBNError, NULL);			\
	}						\
	if (!BN_##func(result, bn, ossl_bn_ctx)) {	\
	    BN_free(result);				\
	    ossl_raise(eBNError, NULL);			\
	}						\
	SetBN(obj, result);				\
	return obj;					\
    }

/*
 * Document-method: OpenSSL::BN#sqr
 *   bn.sqr => aBN
 */
BIGNUM_1c(sqr)

#define BIGNUM_2(func)					\
    static VALUE					\
    ossl_bn_##func(VALUE self, VALUE other)		\
    {							\
	BIGNUM *bn1, *bn2 = GetBNPtr(other), *result;	\
	VALUE obj;					\
	GetBN(self, bn1);				\
	obj = NewBN(CLASS_OF(self));			\
	if (!(result = BN_new())) {			\
	    ossl_raise(eBNError, NULL);			\
	}						\
	if (!BN_##func(result, bn1, bn2)) {		\
	    BN_free(result);				\
	    ossl_raise(eBNError, NULL);			\
	}						\
	SetBN(obj, result);				\
	return obj;					\
    }

/*
 * Document-method: OpenSSL::BN#+
 *   bn + bn2 => aBN
 */
BIGNUM_2(add)

/*
 * Document-method: OpenSSL::BN#-
 *   bn - bn2 => aBN
 */
BIGNUM_2(sub)

#define BIGNUM_2c(func)						\
    static VALUE						\
    ossl_bn_##func(VALUE self, VALUE other)			\
    {								\
	BIGNUM *bn1, *bn2 = GetBNPtr(other), *result;		\
	VALUE obj;						\
	GetBN(self, bn1);					\
	obj = NewBN(CLASS_OF(self));				\
	if (!(result = BN_new())) {				\
	    ossl_raise(eBNError, NULL);				\
	}							\
	if (!BN_##func(result, bn1, bn2, ossl_bn_ctx)) {	\
	    BN_free(result);					\
	    ossl_raise(eBNError, NULL);				\
	}							\
	SetBN(obj, result);					\
	return obj;						\
    }

/*
 * Document-method: OpenSSL::BN#*
 *   bn * bn2 => aBN
 */
BIGNUM_2c(mul)

/*
 * Document-method: OpenSSL::BN#%
 *   bn % bn2 => aBN
 */
BIGNUM_2c(mod)

/*
 * Document-method: OpenSSL::BN#**
 *   bn ** bn2 => aBN
 */
BIGNUM_2c(exp)

/*
 * Document-method: OpenSSL::BN#gcd
 *   bn.gcd(bn2) => aBN
 */
BIGNUM_2c(gcd)

/*
 * Document-method: OpenSSL::BN#mod_sqr
 *   bn.mod_sqr(bn2) => aBN
 */
BIGNUM_2c(mod_sqr)

/*
 * Document-method: OpenSSL::BN#mod_inverse
 *   bn.mod_inverse(bn2) => aBN
 */
BIGNUM_2c(mod_inverse)

/*
 * Document-method: OpenSSL::BN#/
 *    bn1 / bn2 => [result, remainder]
 *
 * Division of OpenSSL::BN instances
 */
static VALUE
ossl_bn_div(VALUE self, VALUE other)
{
    BIGNUM *bn1, *bn2 = GetBNPtr(other), *r1, *r2;
    VALUE obj1, obj2;

    GetBN(self, bn1);

    obj1 = NewBN(CLASS_OF(self));
    obj2 = NewBN(CLASS_OF(self));
    if (!(r1 = BN_new())) {
	ossl_raise(eBNError, NULL);
    }
    if (!(r2 = BN_new())) {
	BN_free(r1);
	ossl_raise(eBNError, NULL);
    }
    if (!BN_div(r1, r2, bn1, bn2, ossl_bn_ctx)) {
	BN_free(r1);
	BN_free(r2);
	ossl_raise(eBNError, NULL);
    }
    SetBN(obj1, r1);
    SetBN(obj2, r2);

    return rb_ary_new3(2, obj1, obj2);
}

#define BIGNUM_3c(func)						\
    static VALUE						\
    ossl_bn_##func(VALUE self, VALUE other1, VALUE other2)	\
    {								\
	BIGNUM *bn1, *bn2 = GetBNPtr(other1);			\
	BIGNUM *bn3 = GetBNPtr(other2), *result;		\
	VALUE obj;						\
	GetBN(self, bn1);					\
	obj = NewBN(CLASS_OF(self));				\
	if (!(result = BN_new())) {				\
	    ossl_raise(eBNError, NULL);				\
	}							\
	if (!BN_##func(result, bn1, bn2, bn3, ossl_bn_ctx)) {	\
	    BN_free(result);					\
	    ossl_raise(eBNError, NULL);				\
	}							\
	SetBN(obj, result);					\
	return obj;						\
    }

/*
 * Document-method: OpenSSL::BN#mod_add
 *   bn.mod_add(bn1, bn2) -> aBN
 */
BIGNUM_3c(mod_add)

/*
 * Document-method: OpenSSL::BN#mod_sub
 *   bn.mod_sub(bn1, bn2) -> aBN
 */
BIGNUM_3c(mod_sub)

/*
 * Document-method: OpenSSL::BN#mod_mul
 *   bn.mod_mul(bn1, bn2) -> aBN
 */
BIGNUM_3c(mod_mul)

/*
 * Document-method: OpenSSL::BN#mod_exp
 *   bn.mod_exp(bn1, bn2) -> aBN
 */
BIGNUM_3c(mod_exp)

#define BIGNUM_BIT(func)				\
    static VALUE					\
    ossl_bn_##func(VALUE self, VALUE bit)		\
    {							\
	BIGNUM *bn;					\
	GetBN(self, bn);				\
	if (!BN_##func(bn, NUM2INT(bit))) {		\
	    ossl_raise(eBNError, NULL);			\
	}						\
	return self;					\
    }

/*
 * Document-method: OpenSSL::BN#set_bit!
 *   bn.set_bit!(bit) -> self
 */
BIGNUM_BIT(set_bit)

/*
 * Document-method: OpenSSL::BN#clear_bit!
 *   bn.clear_bit!(bit) -> self
 */
BIGNUM_BIT(clear_bit)

/*
 * Document-method: OpenSSL::BN#mask_bit!
 *   bn.mask_bit!(bit) -> self
 */
BIGNUM_BIT(mask_bits)

/* Document-method: OpenSSL::BN#bit_set?
 *
 * Returns boolean of whether +bit+ is set.
 * Bitwise operations for openssl BIGNUMs.
 *
 *    bn.bit_set?(bit) => true | false
 *
 */
static VALUE
ossl_bn_is_bit_set(VALUE self, VALUE bit)
{
    int b;
    BIGNUM *bn;

    b = NUM2INT(bit);
    GetBN(self, bn);
    if (BN_is_bit_set(bn, b)) {
	return Qtrue;
    }
    return Qfalse;
}

#define BIGNUM_SHIFT(func)				\
    static VALUE					\
    ossl_bn_##func(VALUE self, VALUE bits)		\
    {							\
	BIGNUM *bn, *result;				\
	int b;						\
	VALUE obj;					\
	b = NUM2INT(bits);				\
	GetBN(self, bn);				\
	obj = NewBN(CLASS_OF(self));			\
	if (!(result = BN_new())) {			\
		ossl_raise(eBNError, NULL);		\
	}						\
	if (!BN_##func(result, bn, b)) {		\
		BN_free(result);			\
		ossl_raise(eBNError, NULL);		\
	}						\
	SetBN(obj, result);				\
	return obj;					\
    }

/*
 * Document-method: OpenSSL::BN#<<
 * call-seq:
 *   bn << bits -> aBN
 */
BIGNUM_SHIFT(lshift)

/*
 * Document-method: OpenSSL::BN#>>
 * call-seq:
 *   bn >> bits -> aBN
 */
BIGNUM_SHIFT(rshift)

#define BIGNUM_SELF_SHIFT(func)				\
    static VALUE					\
    ossl_bn_self_##func(VALUE self, VALUE bits)		\
    {							\
	BIGNUM *bn;					\
	int b;						\
	b = NUM2INT(bits);				\
	GetBN(self, bn);				\
	if (!BN_##func(bn, bn, b))			\
		ossl_raise(eBNError, NULL);		\
	return self;					\
    }

/*
 * Document-method: OpenSSL::BN#lshift!
 *   bn.lshift!(bits) -> self
 */
BIGNUM_SELF_SHIFT(lshift)

/*
 * Document-method: OpenSSL::BN#rshift!
 *   bn.rshift!(bits) -> self
 */
BIGNUM_SELF_SHIFT(rshift)

#define BIGNUM_RAND(func)					\
    static VALUE						\
    ossl_bn_s_##func(int argc, VALUE *argv, VALUE klass)	\
    {								\
	BIGNUM *result;						\
	int bottom = 0, top = 0, b;				\
	VALUE bits, fill, odd, obj;				\
								\
	switch (rb_scan_args(argc, argv, "12", &bits, &fill, &odd)) {	\
	case 3:							\
	    bottom = (odd == Qtrue) ? 1 : 0;			\
	    /* FALLTHROUGH */					\
	case 2:							\
	    top = NUM2INT(fill);				\
	}							\
	b = NUM2INT(bits);					\
	obj = NewBN(klass);					\
	if (!(result = BN_new())) {				\
	    ossl_raise(eBNError, NULL);				\
	}							\
	if (!BN_##func(result, b, top, bottom)) {		\
	    BN_free(result);					\
	    ossl_raise(eBNError, NULL);				\
	}							\
	SetBN(obj, result);					\
	return obj;						\
    }

/*
 * Document-method: OpenSSL::BN.rand
 *   BN.rand(bits [, fill [, odd]]) -> aBN
 */
BIGNUM_RAND(rand)

/*
 * Document-method: OpenSSL::BN.pseudo_rand
 *   BN.pseudo_rand(bits [, fill [, odd]]) -> aBN
 */
BIGNUM_RAND(pseudo_rand)

#define BIGNUM_RAND_RANGE(func)					\
    static VALUE						\
    ossl_bn_s_##func##_range(VALUE klass, VALUE range)		\
    {								\
	BIGNUM *bn = GetBNPtr(range), *result;			\
	VALUE obj = NewBN(klass);				\
	if (!(result = BN_new())) {				\
	    ossl_raise(eBNError, NULL);				\
	}							\
	if (!BN_##func##_range(result, bn)) {			\
	    BN_free(result);					\
	    ossl_raise(eBNError, NULL);				\
	}							\
	SetBN(obj, result);					\
	return obj;						\
    }

/*
 * Document-method: OpenSSL::BN.rand_range
 *   BN.rand_range(range) -> aBN
 *
 */
BIGNUM_RAND_RANGE(rand)

/*
 * Document-method: OpenSSL::BN.pseudo_rand_range
 *   BN.pseudo_rand_range(range) -> aBN
 *
 */
BIGNUM_RAND_RANGE(pseudo_rand)

/*
 * call-seq:
 *    BN.generate_prime(bits, [, safe [, add [, rem]]]) => bn
 *
 * === Parameters
 * * +bits+ - integer
 * * +safe+ - boolean
 * * +add+ - BN
 * * +rem+ - BN
 */
static VALUE
ossl_bn_s_generate_prime(int argc, VALUE *argv, VALUE klass)
{
    BIGNUM *add = NULL, *rem = NULL, *result;
    int safe = 1, num;
    VALUE vnum, vsafe, vadd, vrem, obj;

    rb_scan_args(argc, argv, "13", &vnum, &vsafe, &vadd, &vrem);

    num = NUM2INT(vnum);

    if (vsafe == Qfalse) {
	safe = 0;
    }
    if (!NIL_P(vadd)) {
	add = GetBNPtr(vadd);
	rem = NIL_P(vrem) ? NULL : GetBNPtr(vrem);
    }
    obj = NewBN(klass);
    if (!(result = BN_new())) {
	ossl_raise(eBNError, NULL);
    }
    if (!BN_generate_prime(result, num, safe, add, rem, NULL, NULL)) {
	BN_free(result);
	ossl_raise(eBNError, NULL);
    }
    SetBN(obj, result);

    return obj;
}

#define BIGNUM_NUM(func)			\
    static VALUE 				\
    ossl_bn_##func(VALUE self)			\
    {						\
	BIGNUM *bn;				\
	GetBN(self, bn);			\
	return INT2FIX(BN_##func(bn));		\
    }

/*
 * Document-method: OpenSSL::BN#num_bytes
 *   bn.num_bytes => integer
 */
BIGNUM_NUM(num_bytes)

/*
 * Document-method: OpenSSL::BN#num_bits
 *   bn.num_bits => integer
 */
BIGNUM_NUM(num_bits)

static VALUE
ossl_bn_copy(VALUE self, VALUE other)
{
    BIGNUM *bn1, *bn2;

    rb_check_frozen(self);

    if (self == other) return self;

    GetBN(self, bn1);
    bn2 = GetBNPtr(other);

    if (!BN_copy(bn1, bn2)) {
	ossl_raise(eBNError, NULL);
    }
    return self;
}

#define BIGNUM_CMP(func)				\
    static VALUE					\
    ossl_bn_##func(VALUE self, VALUE other)		\
    {							\
	BIGNUM *bn1, *bn2 = GetBNPtr(other);		\
	GetBN(self, bn1);				\
	return INT2FIX(BN_##func(bn1, bn2));		\
    }

/*
 * Document-method: OpenSSL::BN#cmp
 *   bn.cmp(bn2) => integer
 */
/*
 * Document-method: OpenSSL::BN#<=>
 *   bn <=> bn2 => integer
 */
BIGNUM_CMP(cmp)

/*
 * Document-method: OpenSSL::BN#ucmp
 *   bn.ucmp(bn2) => integer
 */
BIGNUM_CMP(ucmp)

/*
 *  call-seq:
 *     big.eql?(obj) => true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> is a
 *  <code>Bignum</code> with the same value as <i>big</i>. Contrast this
 */
static VALUE
ossl_bn_eql(VALUE self, VALUE other)
{
    if (ossl_bn_cmp(self, other) == INT2FIX(0)) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 * call-seq:
 *    bn.prime? => true | false
 *    bn.prime?(checks) => true | false
 *
 * === Parameters
 * * +checks+ - integer
 */
static VALUE
ossl_bn_is_prime(int argc, VALUE *argv, VALUE self)
{
    BIGNUM *bn;
    VALUE vchecks;
    int checks = BN_prime_checks;

    if (rb_scan_args(argc, argv, "01", &vchecks) == 1) {
	checks = NUM2INT(vchecks);
    }
    GetBN(self, bn);
    switch (BN_is_prime(bn, checks, NULL, ossl_bn_ctx, NULL)) {
    case 1:
	return Qtrue;
    case 0:
	return Qfalse;
    default:
	ossl_raise(eBNError, NULL);
    }
    /* not reachable */
    return Qnil;
}

/*
 * call-seq:
 *    bn.prime_fasttest? => true | false
 *    bn.prime_fasttest?(checks) => true | false
 *    bn.prime_fasttest?(checks, trial_div) => true | false
 *
 * === Parameters
 * * +checks+ - integer
 * * +trial_div+ - boolean
 */
static VALUE
ossl_bn_is_prime_fasttest(int argc, VALUE *argv, VALUE self)
{
    BIGNUM *bn;
    VALUE vchecks, vtrivdiv;
    int checks = BN_prime_checks, do_trial_division = 1;

    rb_scan_args(argc, argv, "02", &vchecks, &vtrivdiv);

    if (!NIL_P(vchecks)) {
	checks = NUM2INT(vchecks);
    }
    GetBN(self, bn);
    /* handle true/false */
    if (vtrivdiv == Qfalse) {
	do_trial_division = 0;
    }
    switch (BN_is_prime_fasttest(bn, checks, NULL, ossl_bn_ctx, NULL, do_trial_division)) {
    case 1:
	return Qtrue;
    case 0:
	return Qfalse;
    default:
	ossl_raise(eBNError, NULL);
    }
    /* not reachable */
    return Qnil;
}

/*
 * INIT
 * (NOTE: ordering of methods is the same as in 'man bn')
 */
void
Init_ossl_bn(void)
{
#if 0
    mOSSL = rb_define_module("OpenSSL"); /* let rdoc know about mOSSL */
#endif

    if (!(ossl_bn_ctx = BN_CTX_new())) {
	ossl_raise(rb_eRuntimeError, "Cannot init BN_CTX");
    }

    eBNError = rb_define_class_under(mOSSL, "BNError", eOSSLError);

    cBN = rb_define_class_under(mOSSL, "BN", rb_cObject);

    rb_define_alloc_func(cBN, ossl_bn_alloc);
    rb_define_method(cBN, "initialize", ossl_bn_initialize, -1);

    rb_define_copy_func(cBN, ossl_bn_copy);
    rb_define_method(cBN, "copy", ossl_bn_copy, 1);

    /* swap (=coerce?) */

    rb_define_method(cBN, "num_bytes", ossl_bn_num_bytes, 0);
    rb_define_method(cBN, "num_bits", ossl_bn_num_bits, 0);
    /* num_bits_word */

    rb_define_method(cBN, "+", ossl_bn_add, 1);
    rb_define_method(cBN, "-", ossl_bn_sub, 1);
    rb_define_method(cBN, "*", ossl_bn_mul, 1);
    rb_define_method(cBN, "sqr", ossl_bn_sqr, 0);
    rb_define_method(cBN, "/", ossl_bn_div, 1);
    rb_define_method(cBN, "%", ossl_bn_mod, 1);
    /* nnmod */

    rb_define_method(cBN, "mod_add", ossl_bn_mod_add, 2);
    rb_define_method(cBN, "mod_sub", ossl_bn_mod_sub, 2);
    rb_define_method(cBN, "mod_mul", ossl_bn_mod_mul, 2);
    rb_define_method(cBN, "mod_sqr", ossl_bn_mod_sqr, 1);
    rb_define_method(cBN, "**", ossl_bn_exp, 1);
    rb_define_method(cBN, "mod_exp", ossl_bn_mod_exp, 2);
    rb_define_method(cBN, "gcd", ossl_bn_gcd, 1);

    /* add_word
     * sub_word
     * mul_word
     * div_word
     * mod_word */

    rb_define_method(cBN, "cmp", ossl_bn_cmp, 1);
    rb_define_alias(cBN, "<=>", "cmp");
    rb_define_method(cBN, "ucmp", ossl_bn_ucmp, 1);
    rb_define_method(cBN, "eql?", ossl_bn_eql, 1);
    rb_define_alias(cBN, "==", "eql?");
    rb_define_alias(cBN, "===", "eql?");
    rb_define_method(cBN, "zero?", ossl_bn_is_zero, 0);
    rb_define_method(cBN, "one?", ossl_bn_is_one, 0);
    /* is_word */
    rb_define_method(cBN, "odd?", ossl_bn_is_odd, 0);

    /* zero
     * one
     * value_one - DON'T IMPL.
     * set_word
     * get_word */

    rb_define_singleton_method(cBN, "rand", ossl_bn_s_rand, -1);
    rb_define_singleton_method(cBN, "pseudo_rand", ossl_bn_s_pseudo_rand, -1);
    rb_define_singleton_method(cBN, "rand_range", ossl_bn_s_rand_range, 1);
    rb_define_singleton_method(cBN, "pseudo_rand_range", ossl_bn_s_pseudo_rand_range, 1);

    rb_define_singleton_method(cBN, "generate_prime", ossl_bn_s_generate_prime, -1);
    rb_define_method(cBN, "prime?", ossl_bn_is_prime, -1);

    rb_define_method(cBN, "set_bit!", ossl_bn_set_bit, 1);
    rb_define_method(cBN, "clear_bit!", ossl_bn_clear_bit, 1);
    rb_define_method(cBN, "bit_set?", ossl_bn_is_bit_set, 1);
    rb_define_method(cBN, "mask_bits!", ossl_bn_mask_bits, 1);
    rb_define_method(cBN, "<<", ossl_bn_lshift, 1);
    rb_define_method(cBN, ">>", ossl_bn_rshift, 1);
    rb_define_method(cBN, "lshift!", ossl_bn_self_lshift, 1);
    rb_define_method(cBN, "rshift!", ossl_bn_self_rshift, 1);
    /* lshift1 - DON'T IMPL. */
    /* rshift1 - DON'T IMPL. */

    /*
     * bn2bin
     * bin2bn
     * bn2hex
     * bn2dec
     * hex2bn
     * dec2bn - all these are implemented in ossl_bn_initialize, and ossl_bn_to_s
     * print - NOT IMPL.
     * print_fp - NOT IMPL.
     * bn2mpi
     * mpi2bn
     */
    rb_define_method(cBN, "to_s", ossl_bn_to_s, -1);
    rb_define_method(cBN, "to_i", ossl_bn_to_i, 0);
    rb_define_alias(cBN, "to_int", "to_i");
    rb_define_method(cBN, "to_bn", ossl_bn_to_bn, 0);
    rb_define_method(cBN, "coerce", ossl_bn_coerce, 1);

    /*
     * TODO:
     * But how to: from_bin, from_mpi? PACK?
     * to_bin
     * to_mpi
     */

    rb_define_method(cBN, "mod_inverse", ossl_bn_mod_inverse, 1);

    /* RECiProcal
     * MONTgomery */

    /*
     * TODO:
     * Where to belong these?
     */
    rb_define_method(cBN, "prime_fasttest?", ossl_bn_is_prime_fasttest, -1);
}
