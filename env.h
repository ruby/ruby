/************************************************

  env.h -

  $Author: matz $
  $Revision: 1.7 $
  $Date: 1994/12/19 08:30:01 $
  created at: Mon Jul 11 11:53:03 JST 1994

************************************************/
#ifndef ENV_H
#define ENV_H

extern struct ENVIRON {
    int argc;
    VALUE *argv;
    VALUE arg_ary;
    ID last_func;
    struct RClass *last_class;
    struct ENVIRON *prev;
} *the_env;

extern struct SCOPE {
    ID *local_tbl;
    VALUE *local_vars;
    VALUE var_ary;
    struct SCOPE *prev;
} *the_scope;

extern int rb_in_eval;

#endif /* ENV_H */
