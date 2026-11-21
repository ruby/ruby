#ifndef INTERNAL_OBJSPACE_H                         /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_OBJSPACE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Objspace.
 */

RUBY_SYMBOL_EXPORT_BEGIN

/* from intern/class.h */
RUBY_EXTERN VALUE rb_class_super_of(VALUE klass);
RUBY_EXTERN VALUE rb_class_singleton_p(VALUE klass);
RUBY_EXTERN unsigned char rb_class_variation_count(VALUE klass);

/* from vm_sync.h */
RUBY_EXTERN VALUE rb_vm_lock_with_barrier(VALUE (*func)(void *args), void *args);

RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_OBJSPACE_H */
