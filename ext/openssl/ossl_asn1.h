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

/*
 * ASN1 module
 */
VALUE mASN1;
VALUE eASN1Error;  

VALUE cASN1Data;
VALUE cASN1Primitive;
VALUE cASN1Constructive;
 
VALUE cASN1Boolean;                           /* BOOLEAN           */
VALUE cASN1Integer, cASN1Enumerated;          /* INTEGER           */
VALUE cASN1BitString;                         /* BIT STRING        */
VALUE cASN1OctetString, cASN1UTF8String;      /* STRINGs           */
VALUE cASN1NumericString, cASN1PrintableString;
VALUE cASN1T61String, cASN1VideotexString;
VALUE cASN1IA5String, cASN1GraphicString;
VALUE cASN1ISO64String, cASN1GeneralString;
VALUE cASN1UniversalString, cASN1BMPString;
VALUE cASN1Null;                              /* NULL              */
VALUE cASN1ObjectId;                          /* OBJECT IDENTIFIER */
VALUE cASN1UTCTime, cASN1GeneralizedTime;     /* TIME              */
VALUE cASN1Sequence, cASN1Set;                /* CONSTRUCTIVE      */

ASN1_TYPE *ossl_asn1_get_asn1type(VALUE);

void Init_ossl_asn1(void);

#endif
