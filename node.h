/**********************************************************************

  node.h -

  $Author$
  created at: Fri May 28 15:14:02 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_NODE_H
#define RUBY_NODE_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

enum node_type {
    NODE_SCOPE,
    NODE_BLOCK,
    NODE_IF,
    NODE_UNLESS,
    NODE_CASE,
    NODE_CASE2,
    NODE_CASE3,
    NODE_WHEN,
    NODE_IN,
    NODE_WHILE,
    NODE_UNTIL,
    NODE_ITER,
    NODE_FOR,
    NODE_FOR_MASGN,
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
    NODE_MASGN,
    NODE_LASGN,
    NODE_DASGN,
    NODE_DASGN_CURR,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CDECL,
    NODE_CVASGN,
    NODE_OP_ASGN1,
    NODE_OP_ASGN2,
    NODE_OP_ASGN_AND,
    NODE_OP_ASGN_OR,
    NODE_OP_CDECL,
    NODE_CALL,
    NODE_OPCALL,
    NODE_FCALL,
    NODE_VCALL,
    NODE_QCALL,
    NODE_SUPER,
    NODE_ZSUPER,
    NODE_LIST,
    NODE_ZLIST,
    NODE_VALUES,
    NODE_HASH,
    NODE_RETURN,
    NODE_YIELD,
    NODE_LVAR,
    NODE_DVAR,
    NODE_GVAR,
    NODE_IVAR,
    NODE_CONST,
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
    NODE_ONCE,
    NODE_ARGS,
    NODE_ARGS_AUX,
    NODE_OPT_ARG,
    NODE_KW_ARG,
    NODE_POSTARG,
    NODE_ARGSCAT,
    NODE_ARGSPUSH,
    NODE_SPLAT,
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
    NODE_DOT2,
    NODE_DOT3,
    NODE_FLIP2,
    NODE_FLIP3,
    NODE_SELF,
    NODE_NIL,
    NODE_TRUE,
    NODE_FALSE,
    NODE_ERRINFO,
    NODE_DEFINED,
    NODE_POSTEXE,
    NODE_DSYM,
    NODE_ATTRASGN,
    NODE_LAMBDA,
    NODE_METHREF,
    NODE_ARYPTN,
    NODE_HSHPTN,
    NODE_LAST
};

typedef struct rb_code_position_struct {
    int lineno;
    int column;
} rb_code_position_t;

typedef struct rb_code_location_struct {
    rb_code_position_t beg_pos;
    rb_code_position_t end_pos;
} rb_code_location_t;

static inline rb_code_location_t
code_loc_gen(rb_code_location_t *loc1, rb_code_location_t *loc2)
{
    rb_code_location_t loc;
    loc.beg_pos = loc1->beg_pos;
    loc.end_pos = loc2->end_pos;
    return loc;
}

typedef struct RNode {
    VALUE flags;
    union {
	struct RNode *node;
	ID id;
	VALUE value;
	ID *tbl;
    } u1;
    union {
	struct RNode *node;
	ID id;
	long argc;
	VALUE value;
    } u2;
    union {
	struct RNode *node;
	ID id;
	long state;
	struct rb_global_entry *entry;
	struct rb_args_info *args;
        struct rb_ary_pattern_info *apinfo;
	VALUE value;
    } u3;
    rb_code_location_t nd_loc;
    int node_id;
} NODE;

#define RNODE(obj)  (R_CAST(RNode)(obj))

/* FL     : 0..4: T_TYPES, 5: KEEP_WB, 6: PROMOTED, 7: FINALIZE, 8: TAINT, 9: UNTRUSTED, 10: EXIVAR, 11: FREEZE */
/* NODE_FL: 0..4: T_TYPES, 5: KEEP_WB, 6: PROMOTED, 7: NODE_FL_NEWLINE,
 *          8..14: nd_type,
 *          15..: nd_line
 */
#define NODE_FL_NEWLINE              (((VALUE)1)<<7)

#define NODE_TYPESHIFT 8
#define NODE_TYPEMASK  (((VALUE)0x7f)<<NODE_TYPESHIFT)

#define nd_type(n) ((int) (((n)->flags & NODE_TYPEMASK)>>NODE_TYPESHIFT))
#define nd_set_type(n,t) \
    (n)->flags=(((n)->flags&~NODE_TYPEMASK)|((((unsigned long)(t))<<NODE_TYPESHIFT)&NODE_TYPEMASK))

#define NODE_LSHIFT (NODE_TYPESHIFT+7)
#define NODE_LMASK  (((SIGNED_VALUE)1<<(sizeof(VALUE)*CHAR_BIT-NODE_LSHIFT))-1)
#define nd_line(n) (int)(((SIGNED_VALUE)(n)->flags)>>NODE_LSHIFT)
#define nd_set_line(n,l) \
    (n)->flags=(((n)->flags&~((VALUE)(-1)<<NODE_LSHIFT))|((VALUE)((l)&NODE_LMASK)<<NODE_LSHIFT))

#define nd_first_column(n) ((int)((n)->nd_loc.beg_pos.column))
#define nd_set_first_column(n, v) ((n)->nd_loc.beg_pos.column = (v))
#define nd_first_lineno(n) ((int)((n)->nd_loc.beg_pos.lineno))
#define nd_set_first_lineno(n, v) ((n)->nd_loc.beg_pos.lineno = (v))
#define nd_first_loc(n) ((n)->nd_loc.beg_pos)
#define nd_set_first_loc(n, v) (nd_first_loc(n) = (v))

#define nd_last_column(n) ((int)((n)->nd_loc.end_pos.column))
#define nd_set_last_column(n, v) ((n)->nd_loc.end_pos.column = (v))
#define nd_last_lineno(n) ((int)((n)->nd_loc.end_pos.lineno))
#define nd_set_last_lineno(n, v) ((n)->nd_loc.end_pos.lineno = (v))
#define nd_last_loc(n) ((n)->nd_loc.end_pos)
#define nd_set_last_loc(n, v) (nd_last_loc(n) = (v))
#define nd_node_id(n) ((n)->node_id)
#define nd_set_node_id(n,id) ((n)->node_id = (id))

#define nd_head  u1.node
#define nd_alen  u2.argc
#define nd_next  u3.node

#define nd_cond  u1.node
#define nd_body  u2.node
#define nd_else  u3.node

#define nd_resq  u2.node
#define nd_ensr  u3.node

#define nd_1st   u1.node
#define nd_2nd   u2.node

#define nd_stts  u1.node

#define nd_entry u3.entry
#define nd_vid   u1.id
#define nd_cflag u2.id
#define nd_cval  u3.value

#define nd_oid   u1.id
#define nd_tbl   u1.tbl

#define nd_var   u1.node
#define nd_iter  u3.node

#define nd_value u2.node
#define nd_aid   u3.id

#define nd_lit   u1.value

#define nd_rest  u1.id
#define nd_opt   u1.node
#define nd_pid   u1.id
#define nd_plen  u2.argc

#define nd_recv  u1.node
#define nd_mid   u2.id
#define nd_args  u3.node
#define nd_ainfo u3.args

#define nd_defn  u3.node

#define nd_cpath u1.node
#define nd_super u3.node

#define nd_beg   u1.node
#define nd_end   u2.node
#define nd_state u3.state
#define nd_rval  u2.value

#define nd_nth   u2.argc

#define nd_tag   u1.id

#define nd_alias  u1.id
#define nd_orig   u2.id
#define nd_undef  u2.node

#define nd_brace u2.argc

#define nd_pconst     u1.node
#define nd_pkwargs    u2.node
#define nd_pkwrestarg u3.node

#define nd_apinfo u3.apinfo

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
#define NEW_GASGN(v,val,loc) NEW_NODE(NODE_GASGN,v,val,rb_global_entry(v),loc)
#define NEW_LASGN(v,val,loc) NEW_NODE(NODE_LASGN,v,val,0,loc)
#define NEW_DASGN(v,val,loc) NEW_NODE(NODE_DASGN,v,val,0,loc)
#define NEW_DASGN_CURR(v,val,loc) NEW_NODE(NODE_DASGN_CURR,v,val,0,loc)
#define NEW_IASGN(v,val,loc) NEW_NODE(NODE_IASGN,v,val,0,loc)
#define NEW_CDECL(v,val,path,loc) NEW_NODE(NODE_CDECL,v,val,path,loc)
#define NEW_CVASGN(v,val,loc) NEW_NODE(NODE_CVASGN,v,val,0,loc)
#define NEW_OP_ASGN1(p,id,a,loc) NEW_NODE(NODE_OP_ASGN1,p,id,a,loc)
#define NEW_OP_ASGN2(r,t,i,o,val,loc) NEW_NODE(NODE_OP_ASGN2,r,val,NEW_OP_ASGN22(i,o,t,loc),loc)
#define NEW_OP_ASGN22(i,o,t,loc) NEW_NODE(NODE_OP_ASGN2,i,o,t,loc)
#define NEW_OP_ASGN_OR(i,val,loc) NEW_NODE(NODE_OP_ASGN_OR,i,val,0,loc)
#define NEW_OP_ASGN_AND(i,val,loc) NEW_NODE(NODE_OP_ASGN_AND,i,val,0,loc)
#define NEW_OP_CDECL(v,op,val,loc) NEW_NODE(NODE_OP_CDECL,v,val,op,loc)
#define NEW_GVAR(v,loc) NEW_NODE(NODE_GVAR,v,0,rb_global_entry(v),loc)
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
#define NEW_KW_ARG(i,v,loc) NEW_NODE(NODE_KW_ARG,i,v,0,loc)
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
#define NEW_PREEXE(b,loc) NEW_SCOPE(b,loc)
#define NEW_POSTEXE(b,loc) NEW_NODE(NODE_POSTEXE,0,b,0,loc)
#define NEW_ATTRASGN(r,m,a,loc) NEW_NODE(NODE_ATTRASGN,r,m,a,loc)
#define NEW_METHREF(r,m,loc) NEW_NODE(NODE_METHREF,r,m,0,loc)

#define NODE_SPECIAL_REQUIRED_KEYWORD ((NODE *)-1)
#define NODE_REQUIRED_KEYWORD_P(node) ((node)->nd_value == NODE_SPECIAL_REQUIRED_KEYWORD)
#define NODE_SPECIAL_NO_NAME_REST     ((NODE *)-1)
#define NODE_NAMED_REST_P(node) ((node) != NODE_SPECIAL_NO_NAME_REST)
#define NODE_SPECIAL_EXCESSIVE_COMMA   ((ID)1)
#define NODE_SPECIAL_NO_REST_KEYWORD   ((NODE *)-1)

VALUE rb_node_case_when_optimizable_literal(const NODE *const node);

RUBY_SYMBOL_EXPORT_BEGIN

typedef struct node_buffer_struct node_buffer_t;
/* T_IMEMO/ast */
typedef struct rb_ast_body_struct {
    const NODE *root;
    VALUE compile_option;
    int line_count;
} rb_ast_body_t;
typedef struct rb_ast_struct {
    VALUE flags;
    node_buffer_t *node_buffer;
    rb_ast_body_t body;
} rb_ast_t;
rb_ast_t *rb_ast_new(void);
void rb_ast_mark(rb_ast_t*);
void rb_ast_update_references(rb_ast_t*);
void rb_ast_dispose(rb_ast_t*);
void rb_ast_free(rb_ast_t*);
size_t rb_ast_memsize(const rb_ast_t*);
void rb_ast_add_mark_object(rb_ast_t*, VALUE);
NODE *rb_ast_newnode(rb_ast_t*, enum node_type type);
void rb_ast_delete_node(rb_ast_t*, NODE *n);

VALUE rb_parser_new(void);
VALUE rb_parser_end_seen_p(VALUE);
VALUE rb_parser_encoding(VALUE);
VALUE rb_parser_get_yydebug(VALUE);
VALUE rb_parser_set_yydebug(VALUE, VALUE);
VALUE rb_parser_dump_tree(const NODE *node, int comment);
void rb_parser_set_options(VALUE, int, int, int, int);

rb_ast_t *rb_parser_compile_cstr(VALUE, const char*, const char*, int, int);
rb_ast_t *rb_parser_compile_string(VALUE, const char*, VALUE, int);
rb_ast_t *rb_parser_compile_file(VALUE, const char*, VALUE, int);
rb_ast_t *rb_parser_compile_string_path(VALUE vparser, VALUE fname, VALUE src, int line);
rb_ast_t *rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE input, int line);
rb_ast_t *rb_parser_compile_generic(VALUE vparser, VALUE (*lex_gets)(VALUE, int), VALUE fname, VALUE input, int line);

rb_ast_t *rb_compile_cstr(const char*, const char*, int, int);
rb_ast_t *rb_compile_string(const char*, VALUE, int);
rb_ast_t *rb_compile_file(const char*, VALUE, int);

void rb_node_init(NODE *n, enum node_type type, VALUE a0, VALUE a1, VALUE a2);
const char *ruby_node_name(int node);

const struct kwtable *rb_reserved_word(const char *, unsigned int);

struct rb_args_info {
    NODE *pre_init;
    NODE *post_init;

    int pre_args_num;  /* count of mandatory pre-arguments */
    int post_args_num; /* count of mandatory post-arguments */

    ID first_post_arg;

    ID rest_arg;
    ID block_arg;

    NODE *kw_args;
    NODE *kw_rest_arg;

    NODE *opt_args;
    int no_kwarg;
    VALUE imemo;
};

struct rb_ary_pattern_info {
    NODE *pre_args;
    NODE *rest_arg;
    NODE *post_args;
    VALUE imemo;
};

struct parser_params;
void *rb_parser_malloc(struct parser_params *, size_t);
void *rb_parser_realloc(struct parser_params *, void *, size_t);
void *rb_parser_calloc(struct parser_params *, size_t, size_t);
void rb_parser_free(struct parser_params *, void *);
PRINTF_ARGS(void rb_parser_printf(struct parser_params *parser, const char *fmt, ...), 2, 3);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_NODE_H */
