/*
 * 'OpenSSL for Ruby' team members
 * Copyright (C) 2003
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#if !defined(_OSSL_ASN1_H_)
#define _OSSL_ASN1_H_

/*
 * ASN1_DATE conversions
 */
VALUE asn1time_to_time(const ASN1_TIME *);
/* Splits VALUE to seconds and offset days. VALUE is typically a Time or an
 * Integer. This is used when updating ASN1_*TIME with ASN1_TIME_adj() or
 * X509_time_adj_ex(). We can't use ASN1_TIME_set() and X509_time_adj() because
 * they have the Year 2038 issue on sizeof(time_t) == 4 environment */
void ossl_time_split(VALUE, time_t *, int *);

/*
 * ASN1_STRING conversions
 */
VALUE asn1str_to_str(const ASN1_STRING *);

/*
 * ASN1_INTEGER conversions
 */
VALUE asn1integer_to_num(const ASN1_INTEGER *);
ASN1_INTEGER *num_to_asn1integer(VALUE, ASN1_INTEGER *);

/*
 * ASN1 module
 */
extern VALUE mASN1;
extern VALUE eASN1Error;

extern VALUE cASN1Data;

void Init_ossl_asn1(void);

#endif
