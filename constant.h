/**********************************************************************

  constant.h -

  $Author$
  created at: Sun Nov 15 00:09:33 2009

  Copyright (C) 2009 Yusuke Endoh

**********************************************************************/
#ifndef CONSTANT_H
#define CONSTANT_H

typedef enum {
    CONST_PUBLIC    = 0x00,
    CONST_PRIVATE,
    CONST_VISIBILITY_MAX
} rb_const_flag_t;

#define RB_CONST_PRIVATE_P(ce) \
    ((ce)->flag == CONST_PRIVATE)
#define RB_CONST_PUBLIC_P(ce) \
    ((ce)->flag == CONST_PUBLIC)

typedef struct rb_const_entry_struct {
    rb_const_flag_t flag;
    int line;
    const VALUE value;            /* should be mark */
    const VALUE file;             /* should be mark */
} rb_const_entry_t;

VALUE rb_mod_private_constant(int argc, const VALUE *argv, VALUE obj);
VALUE rb_mod_public_constant(int argc, const VALUE *argv, VALUE obj);
void rb_free_const_table(st_table *tbl);
VALUE rb_public_const_get(VALUE klass, ID id);
VALUE rb_public_const_get_at(VALUE klass, ID id);
VALUE rb_public_const_get_from(VALUE klass, ID id);
int rb_public_const_defined(VALUE klass, ID id);
int rb_public_const_defined_at(VALUE klass, ID id);
int rb_public_const_defined_from(VALUE klass, ID id);
rb_const_entry_t *rb_const_lookup(VALUE klass, ID id);

#endif /* CONSTANT_H */
