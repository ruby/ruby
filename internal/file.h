#ifndef INTERNAL_FILE_H /* -*- C -*- */
#define INTERNAL_FILE_H
/**
 * @file
 * @brief      Internal header for File.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* file.c */
extern const char ruby_null_device[];
VALUE rb_home_dir_of(VALUE user, VALUE result);
VALUE rb_default_home_dir(VALUE result);
VALUE rb_realpath_internal(VALUE basedir, VALUE path, int strict);
#ifdef RUBY_ENCODING_H
VALUE rb_check_realpath(VALUE basedir, VALUE path, rb_encoding *origenc);
#endif
void rb_file_const(const char*, VALUE);
int rb_file_load_ok(const char *);
VALUE rb_file_expand_path_fast(VALUE, VALUE);
VALUE rb_file_expand_path_internal(VALUE, VALUE, int, int, VALUE);
VALUE rb_get_path_check_to_string(VALUE);
VALUE rb_get_path_check_convert(VALUE);
int ruby_is_fd_loadable(int fd);

#ifdef RUBY_FUNCTION_NAME_STRING
# if defined __GNUC__ && __GNUC__ >= 4
#   pragma GCC visibility push(default)
# endif
NORETURN(void rb_sys_fail_path_in(const char *func_name, VALUE path));
NORETURN(void rb_syserr_fail_path_in(const char *func_name, int err, VALUE path));
# if defined __GNUC__ && __GNUC__ >= 4
#   pragma GCC visibility pop
# endif
# define rb_sys_fail_path(path) rb_sys_fail_path_in(RUBY_FUNCTION_NAME_STRING, path)
# define rb_syserr_fail_path(err, path) rb_syserr_fail_path_in(RUBY_FUNCTION_NAME_STRING, (err), (path))
#else
# define rb_sys_fail_path(path) rb_sys_fail_str(path)
# define rb_syserr_fail_path(err, path) rb_syserr_fail_str((err), (path))
#endif

RUBY_SYMBOL_EXPORT_BEGIN
/* file.c (export) */
#if defined HAVE_READLINK && defined RUBY_ENCODING_H
VALUE rb_readlink(VALUE path, rb_encoding *enc);
#endif
#ifdef __APPLE__
VALUE rb_str_normalize_ospath(const char *ptr, long len);
#endif
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_FILE_H */
