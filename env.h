/************************************************

  env.h -

  $Author$
  $Date$
  created at: Mon Jul 11 11:53:03 JST 1994

************************************************/
#ifndef ENV_H
#define ENV_H

extern struct FRAME {
    VALUE self;
    int argc;
    VALUE *argv;
    ID last_func;
    VALUE last_class;
    VALUE cbase;
    struct FRAME *prev;
    struct FRAME *tmp;
    char *file;
    int line;
    int iter;
    int flags;
} *ruby_frame;

void rb_gc_mark_frame _((struct FRAME *));

#define FRAME_ALLOCA 0
#define FRAME_MALLOC 1

extern struct SCOPE {
    struct RBasic super;
    ID *local_tbl;
    VALUE *local_vars;
    int flag;
} *ruby_scope;

#define SCOPE_ALLOCA  0
#define SCOPE_MALLOC  1
#define SCOPE_NOSTACK 2

extern int ruby_in_eval;

extern VALUE ruby_class;

struct RVarmap {
    struct RBasic super;
    ID id;
    VALUE val;
    struct RVarmap *next;
};
extern struct RVarmap *ruby_dyna_vars;

#endif /* ENV_H */
