/************************************************

  env.h -

  $Author: matz $
  $Revision: 1.8 $
  $Date: 1996/12/25 10:42:30 $
  created at: Mon Jul 11 11:53:03 JST 1994

************************************************/
#ifndef ENV_H
#define ENV_H

extern struct FRAME {
    int argc;
    VALUE *argv;
    ID last_func;
    struct RClass *last_class;
    VALUE cbase;
    struct FRAME *prev;
    char *file;
    int line;
    int iter;
} *the_frame;

extern struct SCOPE {
    struct RBasic super;
    ID *local_tbl;
    VALUE *local_vars;
    int flag;
} *the_scope;

#define SCOPE_ALLOCA  0
#define SCOPE_MALLOC  1
#define SCOPE_NOSTACK 2

extern int rb_in_eval;

extern struct RClass *the_class;

struct RVarmap {
    struct RBasic super;
    ID id;
    VALUE val;
    struct RVarmap *next;
};
extern struct RVarmap *the_dyna_vars;

#endif /* ENV_H */
