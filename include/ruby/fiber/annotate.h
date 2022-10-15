#ifndef RUBY_FIBER_ANNOTATE_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_FIBER_ANNOTATE_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Scheduler APIs.
 */
#include "ruby/internal/config.h"

#include "ruby/ruby.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 *  Attach an annotation to the currently executing fiber. Will discard any
 *  previous annotation.
 *
 *  @retval  VALUE      The previous annotation.
 */
VALUE rb_fiber_annotate(VALUE annotation);

/**
 *  Set the annotation of the specified fiber. Will discard any previous
 *  annotation.
 * 
 *  @param  fiber       The receiver.
 *  @param  annotation  The annotation to assign.
 *  @retval VALUE       The previous annotation.
 */
VALUE rb_fiber_annotation_set(VALUE fiber, VALUE annotation);

/**
 *  Retrieves the annotation attached to the given fiber.
 * 
 *  @param  fiber       The receiver.
 *  @retval VALUE       The annotation.
 */
VALUE rb_fiber_annotation_get(VALUE fiber);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_FIBER_ANNOTATE_H */
