/************************************************

  node.h -

  $Author$
  $Date$
  created at: Fri May 28 15:14:02 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

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
    NODE_OPT_N,
    NODE_WHILE,
    NODE_UNTIL,
    NODE_ITER,
    NODE_FOR,
    NODE_BREAK,
    NODE_NEXT,
    NODE_REDO,
    NODE_RETRY,
    NODE_BEGIN,
    NODE_RESCUE,
    NODE_RESBODY,
    NODE_ENSURE,
    NODE_AND,
    NODE_OR,
    NODE_NOT,
    NODE_MASGN,
    NODE_LASGN,
    NODE_DASGN,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CASGN,
    NODE_OP_ASGN1,
    NODE_OP_ASGN2,
    NODE_CALL,
    NODE_FCALL,
    NODE_VCALL,
    NODE_SUPER,
    NODE_ZSUPER,
    NODE_ARRAY,
    NODE_ZARRAY,
    NODE_HASH,
    NODE_RETURN,
    NODE_YIELD,
    NODE_LVAR,
    NODE_DVAR,
    NODE_GVAR,
    NODE_IVAR,
    NODE_CVAR,
    NODE_NTH_REF,
    NODE_BACK_REF,
    NODE_MATCH_REF,
    NODE_LASTLINE,
    NODE_MATCH,
    NODE_MATCH2,
    NODE_MATCH3,
    NODE_LIT,
    NODE_STR,
    NODE_DSTR,
    NODE_XSTR,
    NODE_DXSTR,
    NODE_EVSTR,
    NODE_DREGX,
    NODE_DREGX_ONCE,
    NODE_ARGS,
    NODE_BLOCK_ARG,
    NODE_BLOCK_PASS,
    NODE_DEFN,
    NODE_DEFS,
    NODE_ALIAS,
    NODE_VALIAS,
    NODE_UNDEF,
    NODE_CLASS,
    NODE_MODULE,
    NODE_SCLASS,
    NODE_COLON2,
    NODE_COLON3,
    NODE_CNAME,
    NODE_CREF,
    NODE_DOT2,
    NODE_DOT3,
    NODE_FLIP2,
    NODE_FLIP3,
    NODE_ATTRSET,
    NODE_SELF,
    NODE_NIL,
    NODE_TRUE,
    NODE_FALSE,
    NODE_DEFINED,
    NODE_TAG,
    NODE_NEWLINE,
    NODE_POSTEXE,
#ifdef C_ALLOCA
    NODE_ALLOCA,
#endif
};

typedef struct RNode {
    UINT flags;
    char *nd_file;
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
	INT argc;
	VALUE value;
    } u2;
    union {
	struct RNode *node;
	ID id;
	INT state;
	struct global_entry *entry;
	INT cnt;
	VALUE value;
    } u3;
} NODE;

#define RNODE(obj)  (R_CAST(RNode)(obj))

#define nd_type(n) (((RNODE(n))->flags>>FL_USHIFT)&0xff)
#define nd_set_type(n,t) \
    RNODE(n)->flags=((RNODE(n)->flags&~FL_UMASK)|(((t)<<FL_USHIFT)&FL_UMASK))

#define nd_line(n) (((RNODE(n))->flags>>18)&0x3fff)
#define nd_set_line(n,l) \
    RNODE(n)->flags=((RNODE(n)->flags&~(-1<<18))|(((l)&0x7fff)<<18))

#define nd_head  u1.node
#define nd_alen  u2.argc
#define nd_next  u3.node

#define nd_cond  u1.node
#define nd_body  u2.node
#define nd_else  u3.node

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
#define nd_opt   u1.node

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
#define nd_super u3.node

#define nd_modl  u1.id
#define nd_clss  u1.value

#define nd_beg   u1.node
#define nd_end   u2.node
#define nd_state u3.state
#define nd_rval  u3.value

#define nd_nth   u2.argc

#define nd_tag   u1.id
#define nd_tlev  u3.cnt
#define nd_tval  u2.value

#define NEW_METHOD(n,x) node_newnode(NODE_METHOD,x,n,0)
#define NEW_FBODY(n,i,o) node_newnode(NODE_FBODY,n,i,o)
#define NEW_DEFN(i,a,d,p) node_newnode(NODE_DEFN,p,i,NEW_RFUNC(a,d))
#define NEW_DEFS(r,i,a,d) node_newnode(NODE_DEFS,r,i,NEW_RFUNC(a,d))
#define NEW_CFUNC(f,c) node_newnode(NODE_CFUNC,f,c,0)
#define NEW_RFUNC(b1,b2) NEW_SCOPE(block_append(b1,b2))
#define NEW_SCOPE(b) node_newnode(NODE_SCOPE,local_tbl(),(b),cur_cref)
#define NEW_BLOCK(a) node_newnode(NODE_BLOCK,a,0,0)
#define NEW_IF(c,t,e) node_newnode(NODE_IF,c,t,e)
#define NEW_UNLESS(c,t,e) node_newnode(NODE_IF,c,e,t)
#define NEW_CASE(h,b) node_newnode(NODE_CASE,h,b,0)
#define NEW_WHEN(c,t,e) node_newnode(NODE_WHEN,c,t,e)
#define NEW_OPT_N(b) node_newnode(NODE_OPT_N,0,b,0)
#define NEW_WHILE(c,b,n) node_newnode(NODE_WHILE,c,b,n)
#define NEW_UNTIL(c,b,n) node_newnode(NODE_UNTIL,c,b,n)
#define NEW_FOR(v,i,b) node_newnode(NODE_FOR,v,b,i)
#define NEW_ITER(v,i,b) node_newnode(NODE_ITER,v,b,i)
#define NEW_BREAK() node_newnode(NODE_BREAK,0,0,0)
#define NEW_NEXT() node_newnode(NODE_NEXT,0,0,0)
#define NEW_REDO() node_newnode(NODE_REDO,0,0,0)
#define NEW_RETRY() node_newnode(NODE_RETRY,0,0,0)
#define NEW_BEGIN(b) node_newnode(NODE_BEGIN,0,b,0)
#define NEW_RESCUE(b,res) node_newnode(NODE_RESCUE,b,res,0)
#define NEW_RESBODY(a,ex,n) node_newnode(NODE_RESBODY,n,ex,a)
#define NEW_ENSURE(b,en) node_newnode(NODE_ENSURE,b,0,en)
#define NEW_RET(s)   node_newnode(NODE_RETURN,s,0,0)
#define NEW_YIELD(a) node_newnode(NODE_YIELD,a,0,0)
#define NEW_LIST(a)  NEW_ARRAY(a)
#define NEW_ARRAY(a) node_newnode(NODE_ARRAY,a,1,0)
#define NEW_ZARRAY() node_newnode(NODE_ZARRAY,0,0,0)
#define NEW_HASH(a)  node_newnode(NODE_HASH,a,0,0)
#define NEW_NOT(a)   node_newnode(NODE_NOT,0,a,0)
#define NEW_MASGN(l,r)   node_newnode(NODE_MASGN,l,0,r)
#define NEW_GASGN(v,val) node_newnode(NODE_GASGN,v,val,rb_global_entry(v))
#define NEW_LASGN(v,val) node_newnode(NODE_LASGN,v,val,local_cnt(v))
#define NEW_DASGN(v,val) node_newnode(NODE_DASGN,v,val,0);
#define NEW_IASGN(v,val) node_newnode(NODE_IASGN,v,val,0)
#define NEW_CASGN(v,val) node_newnode(NODE_CASGN,v,val,0)
#define NEW_OP_ASGN1(p,id,a) node_newnode(NODE_OP_ASGN1,p,id,a)
#define NEW_OP_ASGN2(r,i,o,val) node_newnode(NODE_OP_ASGN2,r,val,NEW_OP_ASGN3(i,o))
#define NEW_OP_ASGN3(i,o) node_newnode(NODE_OP_ASGN2,i,o,0)
#define NEW_GVAR(v) node_newnode(NODE_GVAR,v,0,rb_global_entry(v))
#define NEW_LVAR(v) node_newnode(NODE_LVAR,v,0,local_cnt(v))
#define NEW_DVAR(v) node_newnode(NODE_DVAR,v,0,0);
#define NEW_IVAR(v) node_newnode(NODE_IVAR,v,0,0)
#define NEW_CVAR(v) node_newnode(NODE_CVAR,v,0,0)
#define NEW_NTH_REF(n)  node_newnode(NODE_NTH_REF,0,n,local_cnt('~'))
#define NEW_BACK_REF(n) node_newnode(NODE_BACK_REF,0,n,local_cnt('~'))
#define NEW_MATCH(c) node_newnode(NODE_MATCH,c,0,0)
#define NEW_MATCH2(n1,n2) node_newnode(NODE_MATCH2,n1,n2,0)
#define NEW_MATCH3(r,n2) node_newnode(NODE_MATCH3,r,n2,0)
#define NEW_LIT(l) node_newnode(NODE_LIT,l,0,0)
#define NEW_STR(s) node_newnode(NODE_STR,s,0,0)
#define NEW_DSTR(s) node_newnode(NODE_DSTR,s,0,0)
#define NEW_XSTR(s) node_newnode(NODE_XSTR,s,0,0)
#define NEW_DXSTR(s) node_newnode(NODE_DXSTR,s,0,0)
#define NEW_EVSTR(s,l) node_newnode(NODE_EVSTR,str_new(s,l),0,0)
#define NEW_CALL(r,m,a) node_newnode(NODE_CALL,r,m,a)
#define NEW_FCALL(m,a) node_newnode(NODE_FCALL,0,m,a)
#define NEW_VCALL(m) node_newnode(NODE_VCALL,0,m,0)
#define NEW_SUPER(a) node_newnode(NODE_SUPER,0,0,a)
#define NEW_ZSUPER() node_newnode(NODE_ZSUPER,0,0,0)
#define NEW_ARGS(f,o,r) node_newnode(NODE_ARGS,o,r,f)
#define NEW_BLOCK_ARG(v) node_newnode(NODE_BLOCK_ARG,v,0,local_cnt(v))
#define NEW_BLOCK_PASS(b) node_newnode(NODE_BLOCK_PASS,0,b,0)
#define NEW_ALIAS(n,o) node_newnode(NODE_ALIAS,0,n,o)
#define NEW_VALIAS(n,o) node_newnode(NODE_VALIAS,0,n,o)
#define NEW_UNDEF(i) node_newnode(NODE_UNDEF,0,i,0)
#define NEW_CLASS(n,b,s) node_newnode(NODE_CLASS,n,NEW_CBODY(b),s)
#define NEW_SCLASS(r,b) node_newnode(NODE_SCLASS,r,NEW_CBODY(b),0)
#define NEW_MODULE(n,b) node_newnode(NODE_MODULE,n,NEW_CBODY(b),0)
#define NEW_COLON2(c,i) node_newnode(NODE_COLON2,c,i,0)
#define NEW_COLON3(i) node_newnode(NODE_COLON3,0,i,0)
#define NEW_CREF0() (cur_cref=node_newnode(NODE_CREF,RNODE(the_frame->cbase)->nd_clss,0,0))
#define NEW_CREF() (cur_cref=node_newnode(NODE_CREF,0,0,cur_cref))
#define NEW_CBODY(b) (cur_cref->nd_body=NEW_SCOPE(b),cur_cref)
#define NEW_DOT2(b,e) node_newnode(NODE_DOT2,b,e,0)
#define NEW_DOT3(b,e) node_newnode(NODE_DOT3,b,e,0)
#define NEW_ATTRSET(a) node_newnode(NODE_ATTRSET,a,0,0)
#define NEW_SELF() node_newnode(NODE_SELF,0,0,0)
#define NEW_NIL() node_newnode(NODE_NIL,0,0,0)
#define NEW_TRUE() node_newnode(NODE_TRUE,0,0,0)
#define NEW_FALSE() node_newnode(NODE_FALSE,0,0,0)
#define NEW_DEFINED(e) node_newnode(NODE_DEFINED,e,0,0)
#define NEW_NEWLINE(n) node_newnode(NODE_NEWLINE,0,0,n)
#define NEW_PREEXE(b) NEW_SCOPE(b)
#define NEW_POSTEXE() node_newnode(NODE_POSTEXE,0,0,0)

NODE *node_newnode();
VALUE rb_method_booundp();

#define NOEX_PUBLIC  0
#define NOEX_PRIVATE 1

NODE *compile_string _((char *, char *, int));
NODE *compile_file _((char *, VALUE, int));

void rb_add_method _((VALUE, ID, NODE *, int));
void rb_remove_method _((VALUE, ID));
NODE *node_newnode();

enum node_type nodetype _((NODE *));
int nodeline _((NODE *));

struct global_entry *rb_global_entry _((ID));
VALUE rb_gvar_get _((struct global_entry *));
VALUE rb_gvar_set _((struct global_entry *, VALUE));
VALUE rb_gvar_defined _((struct global_entry *));

#endif
