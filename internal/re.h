#ifndef INTERNAL_RE_H /* -*- C -*- */
#define INTERNAL_RE_H
/**
 * @file
 * @brief      Internal header for Regexp.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* re.c */
VALUE rb_reg_compile(VALUE str, int options, const char *sourcefile, int sourceline);
VALUE rb_reg_check_preprocess(VALUE);
long rb_reg_search0(VALUE, VALUE, long, int, int);
VALUE rb_reg_match_p(VALUE re, VALUE str, long pos);
bool rb_reg_start_with_p(VALUE re, VALUE str);
void rb_backref_set_string(VALUE string, long pos, long len);
void rb_match_unbusy(VALUE);
int rb_match_count(VALUE match);
int rb_match_nth_defined(int nth, VALUE match);
VALUE rb_reg_new_ary(VALUE ary, int options);

#endif /* INTERNAL_RE_H */
