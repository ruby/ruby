/************************************************

  env.h -

  $Author: matz $
  $Revision: 1.8 $
  $Date: 1995/01/10 10:42:30 $
  created at: Mon Jul 11 11:53:03 JST 1994

************************************************/
#ifndef ENV_H
#define ENV_H

extern struct ENVIRON {
    int argc;
    VALUE *argv;
    ID last_func;
    struct RClass *last_class;
    struct ENVIRON *prev;
} *the_env;

struct SCOPE {
    struct RBasic super;
    ID *local_tbl;
    VALUE *local_vars;
    int flags;
} *the_scope;

#define SCOPE_MALLOCED (1<<0)

extern int rb_in_eval;

extern struct RClass *the_class;

#endif /* ENV_H */
