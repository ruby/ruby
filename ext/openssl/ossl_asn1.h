/*
 * $Id$
 * 'OpenSSL for Ruby' team members
 * Copyright (C) 2003
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_ASN1_H_)
#define _OSSL_ASN1_H_

/*
 * ASN1_DATE conversions
 */
VALUE asn1time_to_time(ASN1_TIME *);
time_t time_to_time_t(VALUE);

/*
 * ASN1_INTEGER conversions
 */
VALUE asn1integer_to_num(ASN1_INTEGER *);
ASN1_INTEGER *num_to_asn1integer(VALUE, ASN1_INTEGER *);

#endif

