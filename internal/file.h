#ifndef INTERNAL_FILE_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_FILE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for File.
 */
#include "ruby/ruby.h"          /* for VALUE */
#include "ruby/encoding.h"      /* for rb_encodinng */

struct ruby_file_load_state {
    /* TODO: consider stuffing `VALUE fname' here */
    VALUE filev;
    unsigned int is_fifo:1;
    unsigned int is_nonblock:1;
    /* TODO: DOSISH / __CYGWIN__ maintainer may add xflag here */
};

/* file.c */
extern const char ruby_null_device[];
VALUE rb_home_dir_of(VALUE user, VALUE result);
VALUE rb_default_home_dir(VALUE result);
VALUE rb_realpath_internal(VALUE basedir, VALUE path, int strict);
VALUE rb_check_realpath(VALUE basedir, VALUE path, rb_encoding *origenc);
void rb_file_const(const char*, VALUE);
int rb_file_load_ok(const char *, struct ruby_file_load_state *);
VALUE rb_file_expand_path_fast(VALUE, VALUE);
VALUE rb_file_expand_path_internal(VALUE, VALUE, int, int, VALUE);
VALUE rb_get_path_check_to_string(VALUE);
VALUE rb_get_path_check_convert(VALUE);
int ruby_is_fd_loadable(int fd);
int ruby_disable_nonblock(int fd);
int ruby_find_file_ext(VALUE *filep, const char *const *ext,
                        struct ruby_file_load_state *);
VALUE ruby_find_file(VALUE path, struct ruby_file_load_state *);

RUBY_SYMBOL_EXPORT_BEGIN
/* file.c (export) */
#ifdef HAVE_READLINK
VALUE rb_readlink(VALUE path, rb_encoding *enc);
#endif
#ifdef __APPLE__
VALUE rb_str_normalize_ospath(const char *ptr, long len);
#endif
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_FILE_H */
