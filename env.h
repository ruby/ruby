/************************************************

  env.h -

  $Author$
  $Revision$
  $Date$
  created at: Mon Jul 11 11:53:03 JST 1994

************************************************/
#ifndef ENV_H
#define ENV_H

extern struct FRAME {
    int argc;
    VALUE *argv;
    ID last_func;
    VALUE last_class;
    VALUE cbase;
    struct FRAME *prev;
    char *file;
    int line;
    int iter;
} *the_frame;

void gc_mark_frame _((struct FRAME *));

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

extern VALUE the_class;

struct RVarmap {
    struct RBasic super;
    ID id;
    VALUE val;
    struct RVarmap *next;
};
extern struct RVarmap *the_dyna_vars;

#endif /* ENV_H */
