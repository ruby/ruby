/*
 * $Id: ruby_missing.h,v 1.3 2003/09/06 08:56:57 gotoyuzo Exp $
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2003  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_RUBY_MISSING_H_)
#define _OSS_RUBY_MISSING_H_

#define rb_define_copy_func(klass, func) \
	rb_define_method(klass, "initialize_copy", func, 1)

#endif /* _OSS_RUBY_MISSING_H_ */

