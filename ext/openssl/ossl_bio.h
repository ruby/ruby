/*
 * 'OpenSSL for Ruby' team members
 * Copyright (C) 2003
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#if !defined(_OSSL_BIO_H_)
#define _OSSL_BIO_H_

BIO *ossl_obj2bio(volatile VALUE *);
VALUE ossl_membio2str(BIO*);

#endif
