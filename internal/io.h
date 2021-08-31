#ifndef INTERNAL_IO_H                                    /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_IO_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for IO.
 */
#include "ruby/ruby.h"          /* for VALUE */
#include "ruby/io.h"            /* for rb_io_t */

/* io.c */
void ruby_set_inplace_mode(const char *);
void rb_stdio_set_default_encoding(void);
VALUE rb_io_flush_raw(VALUE, int);
size_t rb_io_memsize(const rb_io_t *);
int rb_stderr_tty_p(void);
void rb_io_fptr_finalize_internal(void *ptr);
#ifdef rb_io_fptr_finalize
# undef rb_io_fptr_finalize
#endif
#define rb_io_fptr_finalize rb_io_fptr_finalize_internal
VALUE rb_io_popen(VALUE pname, VALUE pmode, VALUE env, VALUE opt);

RUBY_SYMBOL_EXPORT_BEGIN
/* io.c (export) */
void rb_maygvl_fd_fix_cloexec(int fd);
int rb_gc_for_fd(int err);
void rb_write_error_str(VALUE mesg);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_IO_H */
