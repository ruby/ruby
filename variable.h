#ifndef RUBY_TOPLEVEL_VARIABLE_H                         /*-*-C-*-vi:se ft=c:*/
#define RUBY_TOPLEVEL_VARIABLE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* per-object */

#include "shape.h"
#include "internal/struct.h"

static inline bool
rb_obj_exivar_p(VALUE obj)
{
    switch (TYPE(obj)) {
        case T_NONE:
        case T_OBJECT:
        case T_CLASS:
        case T_MODULE:
        case T_IMEMO:
          return false;
        case T_STRUCT:
          if (!FL_TEST_RAW(obj, RSTRUCT_FL_GENIVAR)) {
              return false;
          }
          break;
        default:
          break;
    }
    return rb_shape_obj_has_fields(obj);
}

int rb_ivar_generic_fields_tbl_lookup(VALUE obj, VALUE *);
void rb_copy_complex_ivars(VALUE dest, VALUE obj, shape_id_t src_shape_id, st_table *fields_table);
void rb_copy_struct_ivar(VALUE dest, VALUE obj);

void rb_free_rb_global_tbl(void);
void rb_free_generic_fields_tbl_(void);

#endif /* RUBY_TOPLEVEL_VARIABLE_H */
