/**                                                         \noop-*-C-*-vi:ft=c
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header to suppres / mandate warnings.
 */
#ifndef INTERNAL_WARNINGS_H
#define INTERNAL_WARNINGS_H
#include "ruby/3/warning_push.h"
#define COMPILER_WARNING_PUSH          RUBY3_WARNING_PUSH()
#define COMPILER_WARNING_POP           RUBY3_WARNING_POP()
#define COMPILER_WARNING_ERROR(flag)   RUBY3_WARNING_ERROR(flag)
#define COMPILER_WARNING_IGNORED(flag) RUBY3_WARNING_IGNORED(flag)
#endif /* INTERNAL_WARNINGS_H */
