/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001 Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_PKEY_H_)
#define _OSSL_PKEY_H_

extern VALUE mPKey;
extern VALUE cPKey;
extern VALUE ePKeyError;
extern const rb_data_type_t ossl_evp_pkey_type;

#define OSSL_PKEY_SET_PRIVATE(obj) rb_iv_set((obj), "private", Qtrue)
#define OSSL_PKEY_SET_PUBLIC(obj)  rb_iv_set((obj), "private", Qfalse)
#define OSSL_PKEY_IS_PRIVATE(obj)  (rb_iv_get((obj), "private") == Qtrue)

#define NewPKey(klass) \
    TypedData_Wrap_Struct((klass), &ossl_evp_pkey_type, 0)
#define SetPKey(obj, pkey) do { \
    if (!(pkey)) { \
	rb_raise(rb_eRuntimeError, "PKEY wasn't initialized!"); \
    } \
    RTYPEDDATA_DATA(obj) = (pkey); \
    OSSL_PKEY_SET_PUBLIC(obj); \
} while (0)
#define GetPKey(obj, pkey) do {\
    TypedData_Get_Struct((obj), EVP_PKEY, &ossl_evp_pkey_type, (pkey)); \
    if (!(pkey)) { \
	rb_raise(rb_eRuntimeError, "PKEY wasn't initialized!");\
    } \
} while (0)

struct ossl_generate_cb_arg {
    int yield;
    int stop;
    int state;
};
int ossl_generate_cb_2(int p, int n, BN_GENCB *cb);
void ossl_generate_cb_stop(void *ptr);

VALUE ossl_pkey_new(EVP_PKEY *);
EVP_PKEY *GetPKeyPtr(VALUE);
EVP_PKEY *DupPKeyPtr(VALUE);
EVP_PKEY *GetPrivPKeyPtr(VALUE);
void Init_ossl_pkey(void);

/*
 * RSA
 */
extern VALUE cRSA;
extern VALUE eRSAError;

VALUE ossl_rsa_new(EVP_PKEY *);
void Init_ossl_rsa(void);

/*
 * DSA
 */
extern VALUE cDSA;
extern VALUE eDSAError;

VALUE ossl_dsa_new(EVP_PKEY *);
void Init_ossl_dsa(void);

/*
 * DH
 */
extern VALUE cDH;
extern VALUE eDHError;

VALUE ossl_dh_new(EVP_PKEY *);
void Init_ossl_dh(void);

/*
 * EC
 */
extern VALUE cEC;
extern VALUE eECError;
extern VALUE cEC_GROUP;
extern VALUE eEC_GROUP;
extern VALUE cEC_POINT;
extern VALUE eEC_POINT;
VALUE ossl_ec_new(EVP_PKEY *);
void Init_ossl_ec(void);

#define OSSL_PKEY_BN_DEF_GETTER0(_keytype, _type, _name, _get)		\
/*									\
 *  call-seq:								\
 *     _keytype##.##_name -> aBN					\
 */									\
static VALUE ossl_##_keytype##_get_##_name(VALUE self)			\
{									\
	_type *obj;							\
	const BIGNUM *bn;						\
									\
	Get##_type(self, obj);						\
	_get;								\
	if (bn == NULL)							\
		return Qnil;						\
	return ossl_bn_new(bn);						\
}

#define OSSL_PKEY_BN_DEF_GETTER3(_keytype, _type, _group, a1, a2, a3)	\
	OSSL_PKEY_BN_DEF_GETTER0(_keytype, _type, a1,			\
		_type##_get0_##_group(obj, &bn, NULL, NULL))		\
	OSSL_PKEY_BN_DEF_GETTER0(_keytype, _type, a2,			\
		_type##_get0_##_group(obj, NULL, &bn, NULL))		\
	OSSL_PKEY_BN_DEF_GETTER0(_keytype, _type, a3,			\
		_type##_get0_##_group(obj, NULL, NULL, &bn))

#define OSSL_PKEY_BN_DEF_GETTER2(_keytype, _type, _group, a1, a2)	\
	OSSL_PKEY_BN_DEF_GETTER0(_keytype, _type, a1,			\
		_type##_get0_##_group(obj, &bn, NULL))			\
	OSSL_PKEY_BN_DEF_GETTER0(_keytype, _type, a2,			\
		_type##_get0_##_group(obj, NULL, &bn))

#define OSSL_PKEY_BN_DEF_SETTER3(_keytype, _type, _group, a1, a2, a3)	\
/*									\
 *  call-seq:								\
 *     _keytype##.set_##_group(a1, a2, a3) -> self			\
 */									\
static VALUE ossl_##_keytype##_set_##_group(VALUE self, VALUE v1, VALUE v2, VALUE v3) \
{									\
	_type *obj;							\
	BIGNUM *bn1 = NULL, *orig_bn1 = NIL_P(v1) ? NULL : GetBNPtr(v1);\
	BIGNUM *bn2 = NULL, *orig_bn2 = NIL_P(v2) ? NULL : GetBNPtr(v2);\
	BIGNUM *bn3 = NULL, *orig_bn3 = NIL_P(v3) ? NULL : GetBNPtr(v3);\
									\
	Get##_type(self, obj);						\
	if (orig_bn1 && !(bn1 = BN_dup(orig_bn1)) ||			\
	    orig_bn2 && !(bn2 = BN_dup(orig_bn2)) ||			\
	    orig_bn3 && !(bn3 = BN_dup(orig_bn3))) {			\
		BN_clear_free(bn1);					\
		BN_clear_free(bn2);					\
		BN_clear_free(bn3);					\
		ossl_raise(eBNError, NULL);				\
	}								\
									\
	if (!_type##_set0_##_group(obj, bn1, bn2, bn3)) {		\
		BN_clear_free(bn1);					\
		BN_clear_free(bn2);					\
		BN_clear_free(bn3);					\
		ossl_raise(ePKeyError, #_type"_set0_"#_group);		\
	}								\
	return self;							\
}

#define OSSL_PKEY_BN_DEF_SETTER2(_keytype, _type, _group, a1, a2)	\
/*									\
 *  call-seq:								\
 *     _keytype##.set_##_group(a1, a2) -> self				\
 */									\
static VALUE ossl_##_keytype##_set_##_group(VALUE self, VALUE v1, VALUE v2) \
{									\
	_type *obj;							\
	BIGNUM *bn1 = NULL, *orig_bn1 = NIL_P(v1) ? NULL : GetBNPtr(v1);\
	BIGNUM *bn2 = NULL, *orig_bn2 = NIL_P(v2) ? NULL : GetBNPtr(v2);\
									\
	Get##_type(self, obj);						\
	if (orig_bn1 && !(bn1 = BN_dup(orig_bn1)) ||			\
	    orig_bn2 && !(bn2 = BN_dup(orig_bn2))) {			\
		BN_clear_free(bn1);					\
		BN_clear_free(bn2);					\
		ossl_raise(eBNError, NULL);				\
	}								\
									\
	if (!_type##_set0_##_group(obj, bn1, bn2)) {			\
		BN_clear_free(bn1);					\
		BN_clear_free(bn2);					\
		ossl_raise(ePKeyError, #_type"_set0_"#_group);		\
	}								\
	return self;							\
}

#define OSSL_PKEY_BN_DEF_SETTER_OLD(_keytype, _type, _group, _name)	\
/*									\
 *  call-seq:								\
 *     _keytype##.##_name = bn -> bn					\
 */									\
static VALUE ossl_##_keytype##_set_##_name(VALUE self, VALUE bignum)	\
{									\
	_type *obj;							\
	BIGNUM *bn;							\
									\
	rb_warning("#"#_name"= is deprecated; use #set_"#_group);	\
	Get##_type(self, obj);						\
	if (NIL_P(bignum)) {						\
		BN_clear_free(obj->_name);				\
		obj->_name = NULL;					\
		return Qnil;						\
	}								\
									\
	bn = GetBNPtr(bignum);						\
	if (obj->_name == NULL)						\
		obj->_name = BN_new();					\
	if (obj->_name == NULL)						\
		ossl_raise(eBNError, NULL);				\
	if (BN_copy(obj->_name, bn) == NULL)				\
		ossl_raise(eBNError, NULL);				\
	return bignum;							\
}

#if defined(HAVE_OPAQUE_OPENSSL) /* OpenSSL 1.1.0 */
#define OSSL_PKEY_BN_DEF3(_keytype, _type, _group, a1, a2, a3)		\
	OSSL_PKEY_BN_DEF_GETTER3(_keytype, _type, _group, a1, a2, a3)	\
	OSSL_PKEY_BN_DEF_SETTER3(_keytype, _type, _group, a1, a2, a3)

#define OSSL_PKEY_BN_DEF2(_keytype, _type, _group, a1, a2)		\
	OSSL_PKEY_BN_DEF_GETTER2(_keytype, _type, _group, a1, a2)	\
	OSSL_PKEY_BN_DEF_SETTER2(_keytype, _type, _group, a1, a2)

#define DEF_OSSL_PKEY_BN(class, keytype, name)				\
	rb_define_method((class), #name, ossl_##keytype##_get_##name, 0)

#else
#define OSSL_PKEY_BN_DEF3(_keytype, _type, _group, a1, a2, a3)		\
	OSSL_PKEY_BN_DEF_GETTER3(_keytype, _type, _group, a1, a2, a3)	\
	OSSL_PKEY_BN_DEF_SETTER3(_keytype, _type, _group, a1, a2, a3)	\
	OSSL_PKEY_BN_DEF_SETTER_OLD(_keytype, _type, _group, a1)	\
	OSSL_PKEY_BN_DEF_SETTER_OLD(_keytype, _type, _group, a2)	\
	OSSL_PKEY_BN_DEF_SETTER_OLD(_keytype, _type, _group, a3)

#define OSSL_PKEY_BN_DEF2(_keytype, _type, _group, a1, a2)		\
	OSSL_PKEY_BN_DEF_GETTER2(_keytype, _type, _group, a1, a2)	\
	OSSL_PKEY_BN_DEF_SETTER2(_keytype, _type, _group, a1, a2)	\
	OSSL_PKEY_BN_DEF_SETTER_OLD(_keytype, _type, _group, a1)	\
	OSSL_PKEY_BN_DEF_SETTER_OLD(_keytype, _type, _group, a2)

#define DEF_OSSL_PKEY_BN(class, keytype, name) do {			\
	rb_define_method((class), #name, ossl_##keytype##_get_##name, 0);\
	rb_define_method((class), #name "=", ossl_##keytype##_set_##name, 1);\
} while (0)
#endif /* HAVE_OPAQUE_OPENSSL */

#endif /* _OSSL_PKEY_H_ */
