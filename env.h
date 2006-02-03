/**********************************************************************

  env.h -

  $Author$
  $Date$
  created at: Mon Jul 11 11:53:03 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#ifndef ENV_H
#define ENV_H

RUBY_EXTERN struct FRAME {
    VALUE self;
    int argc;
    ID callee;
    ID this_func;
    VALUE this_class;
    struct FRAME *prev;
    struct FRAME *tmp;
    struct RNode *node;
    struct BLOCK *block;
    int flags;
    unsigned long uniq;
} *ruby_frame;

void rb_gc_mark_frame(struct FRAME *);

#define FRAME_DMETH  1
#define FRAME_FUNC   2

RUBY_EXTERN struct SCOPE {
    struct RBasic super;
    ID *local_tbl;
    VALUE *local_vars;
    int flags;
} *ruby_scope;

#define SCOPE_ALLOCA  0
#define SCOPE_MALLOC  1
#define SCOPE_NOSTACK 2
#define SCOPE_DONT_RECYCLE 4

RUBY_EXTERN int ruby_in_eval;
VALUE ruby_current_class_object(void);
#define ruby_class ruby_current_class_object()

struct RVarmap {
    struct RBasic super;
    ID id;
    VALUE val;
    struct RVarmap *next;
};
RUBY_EXTERN struct RVarmap *ruby_dyna_vars;

struct METHOD {
    VALUE klass, rklass;
    VALUE recv;
    ID id, oid;
    int safe_level;
    struct RNode *body;
};

struct BLOCK {
    struct RNode *var;
    struct RNode *body;
    VALUE self;
    struct FRAME frame;
    struct SCOPE *scope;
    VALUE klass;
    struct RNode *cref;
    int vmode;
    int flags;
    int uniq;
    struct RVarmap *dyna_vars;
    VALUE orig_thread;
    VALUE wrapper;
    VALUE block_obj;
};

#define BLOCK_D_SCOPE 1
#define BLOCK_LAMBDA  2
#define BLOCK_FROM_METHOD  4

#endif /* ENV_H */
