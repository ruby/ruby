#ifndef RUBY_RACTOR_H
#define RUBY_RACTOR_H 1

/**
 * @file
 * @author Koichi Sasada
 * @date Tue Nov 17 16:39:15 2020
 * @copyright Copyright (C) 2020 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN VALUE rb_cRactor;

VALUE rb_ractor_stdin(void);
VALUE rb_ractor_stdout(void);
VALUE rb_ractor_stderr(void);
void rb_ractor_stdin_set(VALUE);
void rb_ractor_stdout_set(VALUE);
void rb_ractor_stderr_set(VALUE);

RUBY_SYMBOL_EXPORT_END

#define RB_OBJ_SHAREABLE_P(obj) FL_TEST_RAW((obj), RUBY_FL_SHAREABLE)

static inline bool
rb_ractor_shareable_p(VALUE obj)
{
    bool rb_ractor_shareable_p_continue(VALUE obj);

    if (SPECIAL_CONST_P(obj)) {
        return true;
    }
    else if (RB_OBJ_SHAREABLE_P(obj)) {
        return true;
    }
    else {
        return rb_ractor_shareable_p_continue(obj);
    }
}

#endif /* RUBY_RACTOR_H */
