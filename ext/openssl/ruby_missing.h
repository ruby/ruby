/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2003  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_RUBY_MISSING_H_)
#define _OSSL_RUBY_MISSING_H_

/* Ruby 2.4 */
#ifndef RB_INTEGER_TYPE_P
# define RB_INTEGER_TYPE_P(obj) (RB_FIXNUM_P(obj) || RB_TYPE_P(obj, T_BIGNUM))
#endif

/* Ruby 2.5 */
#ifndef ST2FIX
# define RB_ST2FIX(h) LONG2FIX((long)(h))
# define ST2FIX(h) RB_ST2FIX(h)
#endif

#endif /* _OSSL_RUBY_MISSING_H_ */
