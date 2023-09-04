#ifndef RUBY_PARSER_NODE_H
#define RUBY_PARSER_NODE_H 1
/*
 * This is a header file used by only "parse.y"
 */
#include "rubyparser.h"
#include "internal/compilers.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

static inline rb_code_location_t
code_loc_gen(const rb_code_location_t *loc1, const rb_code_location_t *loc2)
{
    rb_code_location_t loc;
    loc.beg_pos = loc1->beg_pos;
    loc.end_pos = loc2->end_pos;
    return loc;
}

#define RNODE(obj)  ((struct RNode *)(obj))


#define NEW_NODE(t,a0,a1,a2,loc) rb_node_newnode((t),(VALUE)(a0),(VALUE)(a1),(VALUE)(a2),loc)
#define NEW_NODE_WITH_LOCALS(t,a1,a2,loc) node_newnode_with_locals(p, (t),(VALUE)(a1),(VALUE)(a2),loc)

#define NEW_DEFN(i,a,d,loc) NEW_NODE(NODE_DEFN,0,i,NEW_SCOPE(a,d,loc),loc)
#define NEW_DEFS(r,i,a,d,loc) NEW_NODE(NODE_DEFS,r,i,NEW_SCOPE(a,d,loc),loc)
#define NEW_SCOPE(a,b,loc) NEW_NODE_WITH_LOCALS(NODE_SCOPE,b,a,loc)
#define NEW_BLOCK(a,loc) NEW_NODE(NODE_BLOCK,a,0,0,loc)
#define NEW_IF(c,t,e,loc) NEW_NODE(NODE_IF,c,t,e,loc)
#define NEW_UNLESS(c,t,e,loc) NEW_NODE(NODE_UNLESS,c,t,e,loc)
#define NEW_CASE(h,b,loc) NEW_NODE(NODE_CASE,h,b,0,loc)
#define NEW_CASE2(b,loc) NEW_NODE(NODE_CASE2,0,b,0,loc)
#define NEW_CASE3(h,b,loc) NEW_NODE(NODE_CASE3,h,b,0,loc)
#define NEW_WHEN(c,t,e,loc) NEW_NODE(NODE_WHEN,c,t,e,loc)
#define NEW_IN(c,t,e,loc) NEW_NODE(NODE_IN,c,t,e,loc)
#define NEW_WHILE(c,b,n,loc) NEW_NODE(NODE_WHILE,c,b,n,loc)
#define NEW_UNTIL(c,b,n,loc) NEW_NODE(NODE_UNTIL,c,b,n,loc)
#define NEW_FOR(i,b,loc) NEW_NODE(NODE_FOR,0,b,i,loc)
#define NEW_FOR_MASGN(v,loc) NEW_NODE(NODE_FOR_MASGN,v,0,0,loc)
#define NEW_ITER(a,b,loc) NEW_NODE(NODE_ITER,0,NEW_SCOPE(a,b,loc),0,loc)
#define NEW_LAMBDA(a,b,loc) NEW_NODE(NODE_LAMBDA,0,NEW_SCOPE(a,b,loc),0,loc)
#define NEW_BREAK(s,loc) NEW_NODE(NODE_BREAK,s,0,0,loc)
#define NEW_NEXT(s,loc) NEW_NODE(NODE_NEXT,s,0,0,loc)
#define NEW_REDO(loc) NEW_NODE(NODE_REDO,0,0,0,loc)
#define NEW_RETRY(loc) NEW_NODE(NODE_RETRY,0,0,0,loc)
#define NEW_BEGIN(b,loc) NEW_NODE(NODE_BEGIN,0,b,0,loc)
#define NEW_RESCUE(b,res,e,loc) NEW_NODE(NODE_RESCUE,b,res,e,loc)
#define NEW_RESBODY(a,ex,n,loc) NEW_NODE(NODE_RESBODY,n,ex,a,loc)
#define NEW_ENSURE(b,en,loc) NEW_NODE(NODE_ENSURE,b,0,en,loc)
#define NEW_RETURN(s,loc) NEW_NODE(NODE_RETURN,s,0,0,loc)
#define NEW_YIELD(a,loc) NEW_NODE(NODE_YIELD,a,0,0,loc)
#define NEW_LIST(a,loc) NEW_NODE(NODE_LIST,a,1,0,loc)
#define NEW_ZLIST(loc) NEW_NODE(NODE_ZLIST,0,0,0,loc)
#define NEW_HASH(a,loc)  NEW_NODE(NODE_HASH,a,0,0,loc)
#define NEW_MASGN(l,r,loc)   NEW_NODE(NODE_MASGN,l,0,r,loc)
#define NEW_GASGN(v,val,loc) NEW_NODE(NODE_GASGN,v,val,0,loc)
#define NEW_LASGN(v,val,loc) NEW_NODE(NODE_LASGN,v,val,0,loc)
#define NEW_DASGN(v,val,loc) NEW_NODE(NODE_DASGN,v,val,0,loc)
#define NEW_IASGN(v,val,loc) NEW_NODE(NODE_IASGN,v,val,0,loc)
#define NEW_CDECL(v,val,path,loc) NEW_NODE(NODE_CDECL,v,val,path,loc)
#define NEW_CVASGN(v,val,loc) NEW_NODE(NODE_CVASGN,v,val,0,loc)
#define NEW_OP_ASGN1(p,id,a,loc) NEW_NODE(NODE_OP_ASGN1,p,id,a,loc)
#define NEW_OP_ASGN2(r,t,i,o,val,loc) NEW_NODE(NODE_OP_ASGN2,r,val,NEW_OP_ASGN22(i,o,t,loc),loc)
#define NEW_OP_ASGN22(i,o,t,loc) NEW_NODE(NODE_OP_ASGN2,i,o,t,loc)
#define NEW_OP_ASGN_OR(i,val,loc) NEW_NODE(NODE_OP_ASGN_OR,i,val,0,loc)
#define NEW_OP_ASGN_AND(i,val,loc) NEW_NODE(NODE_OP_ASGN_AND,i,val,0,loc)
#define NEW_OP_CDECL(v,op,val,loc) NEW_NODE(NODE_OP_CDECL,v,val,op,loc)
#define NEW_GVAR(v,loc) NEW_NODE(NODE_GVAR,v,0,0,loc)
#define NEW_LVAR(v,loc) NEW_NODE(NODE_LVAR,v,0,0,loc)
#define NEW_DVAR(v,loc) NEW_NODE(NODE_DVAR,v,0,0,loc)
#define NEW_IVAR(v,loc) NEW_NODE(NODE_IVAR,v,0,0,loc)
#define NEW_CONST(v,loc) NEW_NODE(NODE_CONST,v,0,0,loc)
#define NEW_CVAR(v,loc) NEW_NODE(NODE_CVAR,v,0,0,loc)
#define NEW_NTH_REF(n,loc)  NEW_NODE(NODE_NTH_REF,0,n,0,loc)
#define NEW_BACK_REF(n,loc) NEW_NODE(NODE_BACK_REF,0,n,0,loc)
#define NEW_MATCH(c,loc) NEW_NODE(NODE_MATCH,c,0,0,loc)
#define NEW_MATCH2(n1,n2,loc) NEW_NODE(NODE_MATCH2,n1,n2,0,loc)
#define NEW_MATCH3(r,n2,loc) NEW_NODE(NODE_MATCH3,r,n2,0,loc)
#define NEW_LIT(l,loc) NEW_NODE(NODE_LIT,l,0,0,loc)
#define NEW_STR(s,loc) NEW_NODE(NODE_STR,s,0,0,loc)
#define NEW_DSTR(s,loc) NEW_NODE(NODE_DSTR,s,1,0,loc)
#define NEW_XSTR(s,loc) NEW_NODE(NODE_XSTR,s,0,0,loc)
#define NEW_DXSTR(s,loc) NEW_NODE(NODE_DXSTR,s,0,0,loc)
#define NEW_DSYM(s,loc) NEW_NODE(NODE_DSYM,s,0,0,loc)
#define NEW_EVSTR(n,loc) NEW_NODE(NODE_EVSTR,0,(n),0,loc)
#define NEW_CALL(r,m,a,loc) NEW_NODE(NODE_CALL,r,m,a,loc)
#define NEW_OPCALL(r,m,a,loc) NEW_NODE(NODE_OPCALL,r,m,a,loc)
#define NEW_FCALL(m,a,loc) NEW_NODE(NODE_FCALL,0,m,a,loc)
#define NEW_VCALL(m,loc) NEW_NODE(NODE_VCALL,0,m,0,loc)
#define NEW_SUPER(a,loc) NEW_NODE(NODE_SUPER,0,0,a,loc)
#define NEW_ZSUPER(loc) NEW_NODE(NODE_ZSUPER,0,0,0,loc)
#define NEW_ARGS_AUX(r,b,loc) NEW_NODE(NODE_ARGS_AUX,r,b,0,loc)
#define NEW_OPT_ARG(i,v,loc) NEW_NODE(NODE_OPT_ARG,i,v,0,loc)
#define NEW_KW_ARG(v,loc) NEW_NODE(NODE_KW_ARG,0,v,0,loc)
#define NEW_POSTARG(i,v,loc) NEW_NODE(NODE_POSTARG,i,v,0,loc)
#define NEW_ARGSCAT(a,b,loc) NEW_NODE(NODE_ARGSCAT,a,b,0,loc)
#define NEW_ARGSPUSH(a,b,loc) NEW_NODE(NODE_ARGSPUSH,a,b,0,loc)
#define NEW_SPLAT(a,loc) NEW_NODE(NODE_SPLAT,a,0,0,loc)
#define NEW_BLOCK_PASS(b,loc) NEW_NODE(NODE_BLOCK_PASS,0,b,0,loc)
#define NEW_ALIAS(n,o,loc) NEW_NODE(NODE_ALIAS,n,o,0,loc)
#define NEW_VALIAS(n,o,loc) NEW_NODE(NODE_VALIAS,n,o,0,loc)
#define NEW_UNDEF(i,loc) NEW_NODE(NODE_UNDEF,0,i,0,loc)
#define NEW_CLASS(n,b,s,loc) NEW_NODE(NODE_CLASS,n,NEW_SCOPE(0,b,loc),(s),loc)
#define NEW_SCLASS(r,b,loc) NEW_NODE(NODE_SCLASS,r,NEW_SCOPE(0,b,loc),0,loc)
#define NEW_MODULE(n,b,loc) NEW_NODE(NODE_MODULE,n,NEW_SCOPE(0,b,loc),0,loc)
#define NEW_COLON2(c,i,loc) NEW_NODE(NODE_COLON2,c,i,0,loc)
#define NEW_COLON3(i,loc) NEW_NODE(NODE_COLON3,0,i,0,loc)
#define NEW_DOT2(b,e,loc) NEW_NODE(NODE_DOT2,b,e,0,loc)
#define NEW_DOT3(b,e,loc) NEW_NODE(NODE_DOT3,b,e,0,loc)
#define NEW_SELF(loc) NEW_NODE(NODE_SELF,0,0,1,loc)
#define NEW_NIL(loc) NEW_NODE(NODE_NIL,0,0,0,loc)
#define NEW_TRUE(loc) NEW_NODE(NODE_TRUE,0,0,0,loc)
#define NEW_FALSE(loc) NEW_NODE(NODE_FALSE,0,0,0,loc)
#define NEW_ERRINFO(loc) NEW_NODE(NODE_ERRINFO,0,0,0,loc)
#define NEW_DEFINED(e,loc) NEW_NODE(NODE_DEFINED,e,0,0,loc)
#define NEW_POSTEXE(b,loc) NEW_NODE(NODE_POSTEXE,0,b,0,loc)
#define NEW_ATTRASGN(r,m,a,loc) NEW_NODE(NODE_ATTRASGN,r,m,a,loc)
#define NEW_ERROR(loc) NEW_NODE(NODE_ERROR,0,0,0,loc)

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_PARSER_NODE_H */
