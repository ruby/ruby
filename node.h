/************************************************

  node.h -

  $Author: matz $
  $Date: 1995/01/10 10:42:41 $
  created at: Fri May 28 15:14:02 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#ifndef NODE_H
#define NODE_H

enum node_type {
    NODE_METHOD,
    NODE_FBODY,
    NODE_CFUNC,
    NODE_SCOPE,
    NODE_BLOCK,
    NODE_IF,
    NODE_CASE,
    NODE_WHEN,
    NODE_WHILE,
    NODE_WHILE2,
    NODE_ITER,
    NODE_FOR,
    NODE_BEGIN,
    NODE_AND,
    NODE_OR,
    NODE_NOT,
    NODE_MASGN,
    NODE_LASGN,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CASGN,
    NODE_OP_ASGN1,
    NODE_OP_ASGN2,
    NODE_CALL,
    NODE_FCALL,
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
    NODE_FAIL,
    NODE_YIELD,
    NODE_LVAR,
    NODE_LVAR2,
    NODE_GVAR,
    NODE_IVAR,
    NODE_CVAR,
    NODE_CONST,
    NODE_NTH_REF,
    NODE_LIT,
    NODE_STR,
    NODE_STR2,
    NODE_XSTR,
    NODE_XSTR2,
    NODE_DREGX,
    NODE_ARGS,
    NODE_DEFN,
    NODE_DEFS,
    NODE_ALIAS,
    NODE_UNDEF,
    NODE_CLASS,
    NODE_MODULE,
    NODE_CREF,
    NODE_DOT3,
    NODE_ATTRSET,
    NODE_SELF,
    NODE_NIL,
};

typedef struct RNode {
    UINT flags;
    char *file;
    unsigned int line;
    union {
	struct RNode *node;
	ID id;
	VALUE value;
	VALUE (*cfunc)();
	ID *tbl;
    } u1;
    union {
	struct RNode *node;
	ID id;
	int argc;
    } u2;
    union {
	struct RNode *node;
	ID id;
	int state;
	struct global_entry *entry;
	int cnt;
	VALUE value;
    } u3;
} NODE;

#define RNODE(obj)  (R_CAST(RNode)(obj))

#define nd_type(n) (((RNODE(n))->flags>>10)&0xff)
#define nd_set_type(n,t) \
    RNODE(n)->flags=((RNODE(n)->flags&~FL_UMASK)|(((t)<<10)&FL_UMASK))

#define nd_head  u1.node
#define nd_alen  u2.argc
#define nd_next  u3.node

#define nd_cond  u1.node
#define nd_body  u2.node
#define nd_else  u3.node
#define nd_break u3.state

#define nd_orig  u3.value

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
#define nd_aid   u3.id

#define nd_lit   u1.value

#define nd_frml  u1.node
#define nd_rest  u2.argc

#define nd_recv  u1.node
#define nd_mid   u2.id
#define nd_args  u3.node

#define nd_noex  u1.id
#define nd_defn  u3.node

#define nd_new   u2.id
#define nd_old   u3.id

#define nd_cfnc  u1.cfunc
#define nd_argc  u2.argc

#define nd_cname u1.id
#define nd_super u3.id

#define nd_modl  u1.id
#define nd_clss  u1.value

#define nd_beg   u1.node
#define nd_end   u2.node
#define nd_state u3.state
#define nd_rval  u3.node

#define nd_nth   u2.argc

#define NEW_METHOD(n,x) newnode(NODE_METHOD,x,n,0)
#define NEW_FBODY(n,i,o) newnode(NODE_FBODY,n,i,o)
#define NEW_DEFN(i,a,d,p) newnode(NODE_DEFN,p,i,NEW_RFUNC(a,d))
#define NEW_DEFS(r,i,a,d) newnode(NODE_DEFS,r,i,NEW_RFUNC(a,d))
#define NEW_CFUNC(f,c) newnode(NODE_CFUNC,f,c,0)
#define NEW_RFUNC(b1,b2) NEW_SCOPE(block_append(b1,b2))
#define NEW_SCOPE(b) newnode(NODE_SCOPE,local_tbl(),(b),local_cnt(0))
#define NEW_BLOCK(a) newnode(NODE_BLOCK,a,1,0)
#define NEW_IF(c,t,e) newnode(NODE_IF,c,t,e)
#define NEW_EXNOT(c) newnode(NODE_EXNOT,c,0,0)
#define NEW_CASE(h,b) newnode(NODE_CASE,h,b,0)
#define NEW_WHEN(c,t,e) newnode(NODE_WHEN,c,t,e)
#define NEW_WHILE(c,b) newnode(NODE_WHILE,c,b,0)
#define NEW_WHILE2(c,b) newnode(NODE_WHILE2,c,b,0)
#define NEW_FOR(v,i,b) newnode(NODE_FOR,v,b,i)
#define NEW_ITER(v,i,b) newnode(NODE_ITER,v,b,i)
#define NEW_BEGIN(b,ex,en) newnode(NODE_BEGIN,b,ex,en)
#define NEW_REDO() newnode(NODE_REDO,0,0,0)
#define NEW_BREAK() newnode(NODE_BREAK,0,0,0)
#define NEW_CONT()  newnode(NODE_CONTINUE,0,0,0)
#define NEW_RETRY() newnode(NODE_RETRY,0,0,0)
#define NEW_RET(s)  newnode(NODE_RETURN,s,0,0)
#define NEW_FAIL(s)  newnode(NODE_FAIL,s,0,0)
#define NEW_YIELD(a) newnode(NODE_YIELD,a,0,0)
#define NEW_LIST(a) NEW_ARRAY(a)
#define NEW_ARRAY(a) newnode(NODE_ARRAY,a,1,0)
#define NEW_ZARRAY() newnode(NODE_ZARRAY,0,0,0)
#define NEW_HASH(a) newnode(NODE_HASH,a,0,0)
#define NEW_AND(a,b) newnode(NODE_AND,a,b,0)
#define NEW_OR(a,b)  newnode(NODE_OR,a,b,0)
#define NEW_NOT(a)   newnode(NODE_NOT,0,a,0)
#define NEW_MASGN(l,r) newnode(NODE_MASGN,l,r,0)
#define NEW_GASGN(v,val) newnode(NODE_GASGN,v,val,rb_global_entry(v))
#define NEW_LASGN(v,val) newnode(NODE_LASGN,v,val,local_cnt(v))
#define NEW_IASGN(v,val) newnode(NODE_IASGN,v,val,0)
#define NEW_CASGN(v,val) newnode(NODE_CASGN,v,val,0)
#define NEW_OP_ASGN1(p,id,a) newnode(NODE_OP_ASGN1,p,id,a)
#define NEW_OP_ASGN2(r,i,val) newnode(NODE_OP_ASGN1,r,val,i)
#define NEW_GVAR(v) newnode(NODE_GVAR,v,0,rb_global_entry(v))
#define NEW_LVAR(v) newnode(NODE_LVAR,v,0,local_cnt(v))
#define NEW_LVAR2(v) newnode(NODE_LVAR2,v,0,0)
#define NEW_IVAR(v) newnode(NODE_IVAR,v,0,0)
#define NEW_CVAR(v) newnode(NODE_CVAR,v,0,cref_list)
#define NEW_NTH_REF(n) newnode(NODE_NTH_REF,0,n,0)
#define NEW_LIT(l) newnode(NODE_LIT,l,0,0)
#define NEW_STR(s) newnode(NODE_STR,s,0,0)
#define NEW_STR2(s) newnode(NODE_STR2,s,0,0)
#define NEW_XSTR(s) newnode(NODE_XSTR,s,0,0)
#define NEW_XSTR2(s) newnode(NODE_XSTR2,s,0,0)
#define NEW_CALL(r,m,a) newnode(NODE_CALL,r,m,a)
#define NEW_FCALL(m,a) newnode(NODE_FCALL,0,m,a)
#define NEW_SUPER(a) newnode(NODE_SUPER,0,0,a)
#define NEW_ZSUPER() newnode(NODE_ZSUPER,0,0,0)
#define NEW_ARGS(f,r) newnode(NODE_ARGS,0,r,f)
#define NEW_ALIAS(n,o) newnode(NODE_ALIAS,0,n,o)
#define NEW_UNDEF(i) newnode(NODE_UNDEF,0,i,0)
#define NEW_CLASS(n,b,s) newnode(NODE_CLASS,n,NEW_CBODY(b),s)
#define NEW_MODULE(n,b) newnode(NODE_MODULE,n,NEW_CBODY(b),0)
#define NEW_CREF0() (cref_list=newnode(NODE_CREF,the_class,0,0))
#define NEW_CREF(b) (cref_list=newnode(NODE_CREF,0,0,cref_list))
#define NEW_CBODY(b) (cref_list->nd_body=NEW_SCOPE(b),cref_list)
#define NEW_DOT3(b,e) newnode(NODE_DOT3,b,e,0)
#define NEW_ATTRSET(a) newnode(NODE_ATTRSET,a,0,0)
#define NEW_SELF() newnode(NODE_SELF,0,0,0)
#define NEW_NIL() newnode(NODE_NIL,0,0,0)

NODE *newnode();
VALUE rb_method_booundp();

#endif
