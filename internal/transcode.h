#ifndef INTERNAL_TRANSCODE_H /* -*- C -*- */
#define INTERNAL_TRANSCODE_H
/**
 * @file
 * @brief      Internal header for Encoding::Converter.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/config.h"
#include <stddef.h>             /* for size_t */
#include "ruby/ruby.h"          /* for VALUE */
#include "ruby/encoding.h"      /* for rb_econv_t */

/* transcode.c */
extern VALUE rb_cEncodingConverter;
size_t rb_econv_memsize(rb_econv_t *);

#endif /* INTERNAL_TRANSCODE_H */
