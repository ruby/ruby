/************************************************

  env.h -

  $Author: matz $
  $Revision: 1.5 $
  $Date: 1994/11/01 08:27:51 $
  created at: Mon Jul 11 11:53:03 JST 1994

************************************************/
#ifndef ENV_H
#define ENV_H

extern struct ENVIRON {
    VALUE self;
    int argc;
    VALUE *argv;
    ID last_func;
    struct RClass *last_class;
    struct ENVIRON *prev;
} *the_env;

#undef  Qself
#define Qself the_env->self

extern struct SCOPE {
    ID *local_tbl;
    VALUE *local_vars;
    VALUE block;
    int flags;
    struct SCOPE *prev;
} *the_scope;

#define VARS_MALLOCED  (1<<2)

extern int rb_in_eval;

#endif /* ENV_H */
