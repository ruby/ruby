/************************************************

  node.h -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Fri May 28 15:14:02 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#ifndef NODE_H
#define NODE_H

enum node_type {
    NODE_CFUNC,
    NODE_SCOPE,
    NODE_BLOCK,
    NODE_IF,
    NODE_CASE,
    NODE_WHEN,
    NODE_UNLESS,
    NODE_WHILE,
    NODE_UNTIL,
    NODE_DO,
    NODE_FOR,
    NODE_PROT,
    NODE_AND,
    NODE_OR,
    NODE_MASGN,
    NODE_LASGN,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CASGN,
    NODE_CALL,
    NODE_CALL2,
    NODE_SUPER,
    NODE_ZSUPER,
    NODE_ARRAY,
    NODE_ZARRAY,
    NODE_HASH,
    NODE_REDO,
    NODE_BREAK,
    NODE_CONTINUE,
    NODE_RETURN,
    NODE_RETRY,
    NODE_YIELD,
    NODE_LVAR,
    NODE_GVAR,
    NODE_IVAR,
    NODE_MVAR,
    NODE_CVAR,
    NODE_CONST,
    NODE_LIT,
    NODE_STR,
    NODE_ARGS,
    NODE_DEFN,
    NODE_DEFS,
    NODE_ALIAS,
    NODE_UNDEF,
    NODE_CLASS,
    NODE_MODULE,
    NODE_INC,
    NODE_DOT3,
    NODE_ATTRSET,
    NODE_SELF,
    NODE_NIL,
};

typedef struct node {
    enum node_type type;
    char *src;
    unsigned int line;
    union {
	struct node *node;
	ID id;
	VALUE value;
	VALUE (*cfunc)();
	ID *tbl;
	enum mth_scope scope;
    } u1;
    union {
	struct node *node;
	ID id;
	int argc;
    } u2;
    union {
	struct node *node;
	ID id;
	int state;
	struct global_entry *entry;
	int cnt;
	VALUE value;
    } u3;
} NODE;

#define nd_head  u1.node
#define nd_last  u2.node
#define nd_next  u3.node

#define nd_cond  u1.node
#define nd_body  u2.node
#define nd_else  u3.node
#define nd_break u3.state

#define nd_resq  u2.node
#define nd_ensr  u3.node

#define nd_1st   u1.node
#define nd_2nd   u2.node

#define nd_stts  u1.node

#define nd_entry u3.entry
#define nd_vid   u1.id
#define nd_cflag u2.id
#define nd_cval  u3.value

#define nd_cnt   u3.cnt
#define nd_tbl   u1.tbl

#define nd_var   u1.node
#define nd_ibdy  u2.node
#define nd_iter  u3.node

#define nd_value u2.node

#define nd_lit   u1.value

#define nd_frml  u1.node
#define nd_rest  u2.argc

#define nd_recv  u1.node
#define nd_mid   u2.id
#define nd_args  u3.node

#define nd_scope u1.scope
#define nd_defn  u3.node

#define nd_new   u1.id
#define nd_old   u2.id

#define nd_cfnc  u1.cfunc
#define nd_argc  u2.argc

#define nd_cname u1.id
#define nd_super u3.id

#define nd_modl  u1.id

#define nd_beg   u1.node
#define nd_end   u2.node
#define nd_state u3.state

#define nd_rval  u3.node

#define NEW_DEFN(i,d,m) newnode(NODE_DEFN,m,i,d)
#define NEW_DEFS(r,i,d) newnode(NODE_DEFS,r,i,d)
#define NEW_CFUNC(f,c) newnode(NODE_CFUNC,f,c,Qnil)
#define NEW_RFUNC(b1,b2) NEW_SCOPE(block_append(b1,b2))
#define NEW_SCOPE(b) newnode(NODE_SCOPE, local_tbl(),(b),local_cnt(0))
#define NEW_BLOCK(a) newnode(NODE_BLOCK,a,Qnil,Qnil)
#define NEW_IF(c,t,e) newnode(NODE_IF,c,t,e)
#define NEW_UNLESS(c,t,e) newnode(NODE_UNLESS,c,t,e)
#define NEW_CASE(h,b) newnode(NODE_CASE,h,b,Qnil)
#define NEW_WHEN(c,t,e) newnode(NODE_WHEN,c,t,e)
#define NEW_WHILE(c,b) newnode(NODE_WHILE,c,b,Qnil)
#define NEW_UNTIL(c,b) newnode(NODE_UNTIL,c,b,Qnil)
#define NEW_FOR(v,i,b) newnode(NODE_FOR,v,b,i)
#define NEW_DO(v,i,b) newnode(NODE_DO,v,b,i)
#define NEW_PROT(b,ex,en) newnode(NODE_PROT,b,ex,en)
#define NEW_REDO() newnode(NODE_REDO,Qnil,Qnil,Qnil)
#define NEW_BREAK() newnode(NODE_BREAK,Qnil,Qnil,Qnil)
#define NEW_CONT()  newnode(NODE_CONTINUE,Qnil,Qnil,Qnil)
#define NEW_RETRY() newnode(NODE_RETRY,Qnil,Qnil,Qnil)
#define NEW_RET(s)  newnode(NODE_RETURN,s,Qnil,Qnil)
#define NEW_YIELD(a) newnode(NODE_YIELD,a,Qnil,Qnil)
#define NEW_LIST(a) NEW_ARRAY(a)
#define NEW_ARRAY(a) newnode(NODE_ARRAY,a,Qnil,Qnil)
#define NEW_ZARRAY() newnode(NODE_ZARRAY,Qnil,Qnil,Qnil)
#define NEW_HASH(a) newnode(NODE_HASH,a,Qnil,Qnil)
#define NEW_AND(a,b) newnode(NODE_AND,a,b,Qnil)
#define NEW_OR(a,b)  newnode(NODE_OR,a,b,Qnil)
#define NEW_MASGN(l,val) newnode(NODE_MASGN,l,val,Qnil)
#define NEW_GASGN(v,val) newnode(NODE_GASGN,v,val,rb_global_entry(v))
#define NEW_LASGN(v,val) newnode(NODE_LASGN,v,val,local_cnt(v))
#define NEW_IASGN(v,val) newnode(NODE_IASGN,v,val,Qnil)
#define NEW_CASGN(v,val) newnode(NODE_CASGN,v,val,Qnil)
#define NEW_GVAR(v) newnode(NODE_GVAR,v,Qnil,rb_global_entry(v))
#define NEW_LVAR(v) newnode(NODE_LVAR,v,Qnil,local_cnt(v))
#define NEW_IVAR(v) newnode(NODE_IVAR,v,Qnil,Qnil)
#define NEW_MVAR(v) newnode(NODE_MVAR,v,Qnil,Qnil)
#define NEW_CVAR(v) newnode(NODE_CVAR,v,Qnil,Qnil)
#define NEW_LIT(l) newnode(NODE_LIT,l,Qnil,Qnil)
#define NEW_STR(s) newnode(NODE_STR,s,Qnil,Qnil)
#define NEW_CALL(r,m,a) newnode(NODE_CALL,r,m,a)
#define NEW_CALL2(r,m,a) newnode(NODE_CALL2,r,m,a)
#define NEW_SUPER(a) newnode(NODE_SUPER,Qnil,Qnil,a)
#define NEW_ZSUPER() newnode(NODE_ZSUPER,Qnil,Qnil,Qnil)
#define NEW_ARGS(f,r) newnode(NODE_ARGS,f,r,Qnil)
#define NEW_ALIAS(n,o) newnode(NODE_ALIAS,n,o,Qnil)
#define NEW_UNDEF(i) newnode(NODE_UNDEF,Qnil,i,Qnil)
#define NEW_CLASS(n,b,s) newnode(NODE_CLASS,n,NEW_SCOPE(b),s)
#define NEW_MODULE(n,b) newnode(NODE_MODULE,n,NEW_SCOPE(b),Qnil)
#define NEW_INC(m) newnode(NODE_INC,m,Qnil,Qnil)
#define NEW_DOT3(b,e) newnode(NODE_DOT3,b,e,0)
#define NEW_ATTRSET(a) newnode(NODE_ATTRSET,a,Qnil,Qnil)
#define NEW_SELF() newnode(NODE_SELF,Qnil,Qnil,Qnil)
#define NEW_NIL() newnode(NODE_NIL,Qnil,Qnil,Qnil)

NODE *newnode();
NODE *rb_get_method_body();
void freenode();

#endif
