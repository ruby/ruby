/************************************************

  node.h -

  $Author$
  $Date$
  created at: Fri May 28 15:14:02 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

************************************************/

#ifndef NODE_H
#define NODE_H

#if defined(__cplusplus)
extern "C" {
#endif

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
    NODE_DASGN_PUSH,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CASGN,
    NODE_OP_ASGN1,
    NODE_OP_ASGN2,
    NODE_OP_ASGN_AND,
    NODE_OP_ASGN_OR,
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
    NODE_ARGSCAT,
    NODE_RESTARGS,
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
    NODE_NEWLINE,
    NODE_POSTEXE,
#ifdef C_ALLOCA
    NODE_ALLOCA,
#endif
};

typedef struct RNode {
    unsigned long flags;
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
	int argc;
	VALUE value;
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

#define nd_type(n) (((RNODE(n))->flags>>FL_USHIFT)&0xff)
#define nd_set_type(n,t) \
    RNODE(n)->flags=((RNODE(n)->flags&~FL_UMASK)|(((t)<<FL_USHIFT)&FL_UMASK))

#define NODE_LSHIFT (FL_USHIFT+8)
#define NODE_LMASK  (((long)1<<(sizeof(NODE*)*CHAR_BIT-NODE_LSHIFT))-1)
#define nd_line(n) (((RNODE(n))->flags>>NODE_LSHIFT)&NODE_LMASK)
#define nd_set_line(n,l) \
    RNODE(n)->flags=((RNODE(n)->flags&~(-1<<NODE_LSHIFT))|(((l)&NODE_LMASK)<<NODE_LSHIFT))

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

#define nd_old   u1.id
#define nd_new   u2.id

#define nd_cfnc  u1.cfunc
#define nd_argc  u2.argc

#define nd_cname u1.id
#define nd_super u3.node

#define nd_modl  u1.id
#define nd_clss  u1.value

#define nd_beg   u1.node
#define nd_end   u2.node
#define nd_state u3.state
#define nd_rval  u2.value

#define nd_nth   u2.argc

#define nd_tag   u1.id
#define nd_tval  u2.value

#define NEW_METHOD(n,x) rb_node_newnode(NODE_METHOD,x,n,0)
#define NEW_FBODY(n,i,o) rb_node_newnode(NODE_FBODY,n,i,o)
#define NEW_DEFN(i,a,d,p) rb_node_newnode(NODE_DEFN,p,i,NEW_RFUNC(a,d))
#define NEW_DEFS(r,i,a,d) rb_node_newnode(NODE_DEFS,r,i,NEW_RFUNC(a,d))
#define NEW_CFUNC(f,c) rb_node_newnode(NODE_CFUNC,f,c,0)
#define NEW_RFUNC(b1,b2) NEW_SCOPE(block_append(b1,b2))
#define NEW_SCOPE(b) rb_node_newnode(NODE_SCOPE,local_tbl(),cur_cref,(b))
#define NEW_BLOCK(a) rb_node_newnode(NODE_BLOCK,a,0,0)
#define NEW_IF(c,t,e) rb_node_newnode(NODE_IF,c,t,e)
#define NEW_UNLESS(c,t,e) NEW_IF(c,e,t)
#define NEW_CASE(h,b) rb_node_newnode(NODE_CASE,h,b,0)
#define NEW_WHEN(c,t,e) rb_node_newnode(NODE_WHEN,c,t,e)
#define NEW_OPT_N(b) rb_node_newnode(NODE_OPT_N,0,b,0)
#define NEW_WHILE(c,b,n) rb_node_newnode(NODE_WHILE,c,b,n)
#define NEW_UNTIL(c,b,n) rb_node_newnode(NODE_UNTIL,c,b,n)
#define NEW_FOR(v,i,b) rb_node_newnode(NODE_FOR,v,b,i)
#define NEW_ITER(v,i,b) rb_node_newnode(NODE_ITER,v,b,i)
#define NEW_BREAK() rb_node_newnode(NODE_BREAK,0,0,0)
#define NEW_NEXT() rb_node_newnode(NODE_NEXT,0,0,0)
#define NEW_REDO() rb_node_newnode(NODE_REDO,0,0,0)
#define NEW_RETRY() rb_node_newnode(NODE_RETRY,0,0,0)
#define NEW_BEGIN(b) rb_node_newnode(NODE_BEGIN,0,b,0)
#define NEW_RESCUE(b,res,e) rb_node_newnode(NODE_RESCUE,b,res,e)
#define NEW_RESBODY(a,ex,n) rb_node_newnode(NODE_RESBODY,n,ex,a)
#define NEW_ENSURE(b,en) rb_node_newnode(NODE_ENSURE,b,0,en)
#define NEW_RETURN(s) rb_node_newnode(NODE_RETURN,s,0,0)
#define NEW_YIELD(a) rb_node_newnode(NODE_YIELD,a,0,0)
#define NEW_LIST(a)  NEW_ARRAY(a)
#define NEW_ARRAY(a) rb_node_newnode(NODE_ARRAY,a,1,0)
#define NEW_ZARRAY() rb_node_newnode(NODE_ZARRAY,0,0,0)
#define NEW_HASH(a)  rb_node_newnode(NODE_HASH,a,0,0)
#define NEW_NOT(a)   rb_node_newnode(NODE_NOT,0,a,0)
#define NEW_MASGN(l,r)   rb_node_newnode(NODE_MASGN,l,0,r)
#define NEW_GASGN(v,val) rb_node_newnode(NODE_GASGN,v,val,rb_global_entry(v))
#define NEW_LASGN(v,val) rb_node_newnode(NODE_LASGN,v,val,local_cnt(v))
#define NEW_DASGN(v,val) rb_node_newnode(NODE_DASGN,v,val,0);
#define NEW_DASGN_PUSH(v,val) rb_node_newnode(NODE_DASGN_PUSH,v,val,0);
#define NEW_IASGN(v,val) rb_node_newnode(NODE_IASGN,v,val,0)
#define NEW_CASGN(v,val) rb_node_newnode(NODE_CASGN,v,val,0)
#define NEW_OP_ASGN1(p,id,a) rb_node_newnode(NODE_OP_ASGN1,p,id,a)
#define NEW_OP_ASGN2(r,i,o,val) rb_node_newnode(NODE_OP_ASGN2,r,val,NEW_OP_ASGN22(i,o))
#define NEW_OP_ASGN22(i,o) rb_node_newnode(NODE_OP_ASGN2,i,o,rb_id_attrset(i))
#define NEW_OP_ASGN_OR(i,val) rb_node_newnode(NODE_OP_ASGN_OR,i,val,0)
#define NEW_OP_ASGN_AND(i,val) rb_node_newnode(NODE_OP_ASGN_AND,i,val,0)
#define NEW_GVAR(v) rb_node_newnode(NODE_GVAR,v,0,rb_global_entry(v))
#define NEW_LVAR(v) rb_node_newnode(NODE_LVAR,v,0,local_cnt(v))
#define NEW_DVAR(v) rb_node_newnode(NODE_DVAR,v,0,0);
#define NEW_IVAR(v) rb_node_newnode(NODE_IVAR,v,0,0)
#define NEW_CVAR(v) rb_node_newnode(NODE_CVAR,v,0,0)
#define NEW_NTH_REF(n)  rb_node_newnode(NODE_NTH_REF,0,n,local_cnt('~'))
#define NEW_BACK_REF(n) rb_node_newnode(NODE_BACK_REF,0,n,local_cnt('~'))
#define NEW_MATCH(c) rb_node_newnode(NODE_MATCH,c,0,0)
#define NEW_MATCH2(n1,n2) rb_node_newnode(NODE_MATCH2,n1,n2,0)
#define NEW_MATCH3(r,n2) rb_node_newnode(NODE_MATCH3,r,n2,0)
#define NEW_LIT(l) rb_node_newnode(NODE_LIT,l,0,0)
#define NEW_STR(s) rb_node_newnode(NODE_STR,s,0,0)
#define NEW_DSTR(s) rb_node_newnode(NODE_DSTR,s,0,0)
#define NEW_XSTR(s) rb_node_newnode(NODE_XSTR,s,0,0)
#define NEW_DXSTR(s) rb_node_newnode(NODE_DXSTR,s,0,0)
#define NEW_EVSTR(s,l) rb_node_newnode(NODE_EVSTR,rb_str_new(s,l),0,0)
#define NEW_CALL(r,m,a) rb_node_newnode(NODE_CALL,r,m,a)
#define NEW_FCALL(m,a) rb_node_newnode(NODE_FCALL,0,m,a)
#define NEW_VCALL(m) rb_node_newnode(NODE_VCALL,0,m,0)
#define NEW_SUPER(a) rb_node_newnode(NODE_SUPER,0,0,a)
#define NEW_ZSUPER() rb_node_newnode(NODE_ZSUPER,0,0,0)
#define NEW_ARGS(f,o,r) rb_node_newnode(NODE_ARGS,o,r,f)
#define NEW_ARGSCAT(a,b) rb_node_newnode(NODE_ARGSCAT,a,b,0)
#define NEW_RESTARGS(a) rb_node_newnode(NODE_RESTARGS,a,0,0)
#define NEW_BLOCK_ARG(v) rb_node_newnode(NODE_BLOCK_ARG,v,0,local_cnt(v))
#define NEW_BLOCK_PASS(b) rb_node_newnode(NODE_BLOCK_PASS,0,b,0)
#define NEW_ALIAS(n,o) rb_node_newnode(NODE_ALIAS,o,n,0)
#define NEW_VALIAS(n,o) rb_node_newnode(NODE_VALIAS,o,n,0)
#define NEW_UNDEF(i) rb_node_newnode(NODE_UNDEF,0,i,0)
#define NEW_CLASS(n,b,s) rb_node_newnode(NODE_CLASS,n,NEW_CBODY(b),(s))
#define NEW_SCLASS(r,b) rb_node_newnode(NODE_SCLASS,r,NEW_CBODY(b),0)
#define NEW_MODULE(n,b) rb_node_newnode(NODE_MODULE,n,NEW_CBODY(b),0)
#define NEW_COLON2(c,i) rb_node_newnode(NODE_COLON2,c,i,0)
#define NEW_COLON3(i) rb_node_newnode(NODE_COLON3,0,i,0)
#define NEW_CREF0() (cur_cref=RNODE(ruby_frame->cbase))
#define NEW_CREF() (cur_cref=rb_node_newnode(NODE_CREF,0,0,cur_cref))
#define NEW_CBODY(b) (cur_cref->nd_body=NEW_SCOPE(b),cur_cref)
#define NEW_DOT2(b,e) rb_node_newnode(NODE_DOT2,b,e,0)
#define NEW_DOT3(b,e) rb_node_newnode(NODE_DOT3,b,e,0)
#define NEW_ATTRSET(a) rb_node_newnode(NODE_ATTRSET,a,0,0)
#define NEW_SELF() rb_node_newnode(NODE_SELF,0,0,0)
#define NEW_NIL() rb_node_newnode(NODE_NIL,0,0,0)
#define NEW_TRUE() rb_node_newnode(NODE_TRUE,0,0,0)
#define NEW_FALSE() rb_node_newnode(NODE_FALSE,0,0,0)
#define NEW_DEFINED(e) rb_node_newnode(NODE_DEFINED,e,0,0)
#define NEW_NEWLINE(n) rb_node_newnode(NODE_NEWLINE,0,0,n)
#define NEW_PREEXE(b) NEW_SCOPE(b)
#define NEW_POSTEXE() rb_node_newnode(NODE_POSTEXE,0,0,0)

#define NOEX_PUBLIC    0
#define NOEX_UNDEF     1
#define NOEX_CFUNC     1
#define NOEX_PRIVATE   2
#define NOEX_PROTECTED 4 

NODE *rb_compile_cstr _((const char*, const char*, int, int));
NODE *rb_compile_string _((const char*, VALUE, int));
NODE *rb_compile_file _((const char*, VALUE, int));

void rb_add_method _((VALUE, ID, NODE *, int));
NODE *rb_node_newnode();

struct global_entry *rb_global_entry _((ID));
VALUE rb_gvar_get _((struct global_entry *));
VALUE rb_gvar_set _((struct global_entry *, VALUE));
VALUE rb_gvar_defined _((struct global_entry *));

#if defined(__cplusplus)
}  /* extern "C" { */
#endif

#endif
