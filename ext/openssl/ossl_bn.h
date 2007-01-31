/*
 * $Id: ossl_bn.h,v 1.1 2003/07/23 16:11:29 gotoyuzo Exp $
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_BN_H_)
#define _OSSL_BN_H_

extern VALUE cBN;
extern VALUE eBNError;

VALUE ossl_bn_new(BIGNUM *);
BIGNUM *GetBNPtr(VALUE);
void Init_ossl_bn(void);

#endif /* _OSS_BN_H_ */

