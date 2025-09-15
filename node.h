#ifndef RUBY_NODE_H
#define RUBY_NODE_H 1
/**********************************************************************

  node.h -

  $Author$
  created at: Fri May 28 15:14:02 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include <stdbool.h>
#include "rubyparser.h"
#include "ruby/backward/2/attributes.h"

typedef void (*bug_report_func)(const char *fmt, ...) RUBYPARSER_ATTRIBUTE_FORMAT(1, 2);
typedef struct node_buffer_elem_struct {
    struct node_buffer_elem_struct *next;
    long len; /* Length of nodes */
    size_t allocated; /* Total memory size of allocated buf */
    size_t used; /* Current usage of buf */
    NODE **nodes; /* Array of node pointers */
    NODE *buf[FLEX_ARY_LEN];
} node_buffer_elem_t;

typedef struct {
    node_buffer_elem_t *head;
    node_buffer_elem_t *last;
} node_buffer_list_t;

struct node_buffer_struct {
    node_buffer_list_t buffer_list;
    struct rb_ast_local_table_link *local_tables;
    // - id (sequence number)
    // - token_type
    // - text of token
    // - location info
    // Array, whose entry is array
    rb_parser_ary_t *tokens;
};


typedef struct rb_node_buffer_elem_struct {
    struct rb_node_buffer_elem_struct *next;
    long len; /* Length of nodes */
    size_t allocated; /* Total memory size of allocated buf */
    size_t used; /* Current usage of buf */
    rb_node_t **nodes; /* Array of node pointers */
    rb_node_t *buf[FLEX_ARY_LEN];
} rb_node_buffer_elem_t;

typedef struct {
    rb_node_buffer_elem_t *head;
    rb_node_buffer_elem_t *last;
} rb_node_buffer_list_t;

struct rb_node_buffer_struct {
    rb_node_buffer_list_t buffer_list;
    struct rb_ast_local_table_link *local_tables;
    // - id (sequence number)
    // - token_type
    // - text of token
    // - location info
    // Array, whose entry is array
    rb_parser_ary_t *tokens;
};
RUBY_SYMBOL_EXPORT_BEGIN

#ifdef UNIVERSAL_PARSER
rb_ast_t *rb_ast_new(const rb_parser_config_t *config);
#else
rb_ast_t *rb_ast_new(void);
#endif
size_t rb_ast_memsize(const rb_ast_t*);
void rb_ast_dispose(rb_ast_t*);
const char *ruby_node_name(int node);
void rb_node_init(NODE *n, enum node_type type);
void rb_rb_node_init(rb_node_t *n, enum rb_node_type type);

void rb_ast_update_references(rb_ast_t*);
void rb_ast_free(rb_ast_t*);
NODE *rb_ast_newnode(rb_ast_t*, enum node_type type, size_t size, size_t alignment);
rb_node_t *rb_ast_rb_newnode(rb_ast_t*, enum rb_node_type type, size_t size, size_t alignment);
void rb_ast_delete_node(rb_ast_t*, NODE *n);
rb_ast_id_table_t *rb_ast_new_local_table(rb_ast_t*, int);
rb_ast_id_table_t *rb_ast_resize_latest_local_table(rb_ast_t*, int);

VALUE rb_parser_dump_tree(const NODE *node, int comment);

const struct kwtable *rb_reserved_word(const char *, unsigned int);

struct parser_params;
PRINTF_ARGS(void rb_parser_printf(struct parser_params *parser, const char *fmt, ...), 2, 3);
VALUE rb_node_set_type(NODE *n, enum node_type t);
enum node_type rb_node_get_type(const NODE *n);

RUBY_SYMBOL_EXPORT_END

#define NODE_LSHIFT (NODE_TYPESHIFT+7)
#define NODE_LMASK  (((SIGNED_VALUE)1<<(sizeof(VALUE)*CHAR_BIT-NODE_LSHIFT))-1)

static inline int
nd_line(const NODE *n)
{
    if (!n) return -1;
    SIGNED_VALUE flags = (SIGNED_VALUE)n->flags;
    return (int)(flags >> NODE_LSHIFT);
}

static inline void
nd_set_line(NODE *n, SIGNED_VALUE l)
{
    n->flags &= ~(~(VALUE)0 << NODE_LSHIFT);
    n->flags |= ((VALUE)(l & NODE_LMASK) << NODE_LSHIFT);
}

/*
 * rb_node_t version of `nd_line`
 */
static inline int
rb_nd_line(const rb_node_t *n)
{
    if (!n) return -1;
    return n->line;
}
/*
 * rb_node_t version of `nd_set_line`
 */
static inline void
rb_nd_set_line(rb_node_t *n, int l)
{
	n->line = l;
}

#define NODE_SPECIAL_REQUIRED_KEYWORD ((NODE *)-1)
#define NODE_REQUIRED_KEYWORD_P(node) ((node) == NODE_SPECIAL_REQUIRED_KEYWORD)
#define NODE_SPECIAL_NO_NAME_REST     ((NODE *)-1)
#define NODE_NAMED_REST_P(node) ((node) != NODE_SPECIAL_NO_NAME_REST)
#define NODE_SPECIAL_EXCESSIVE_COMMA   ((ID)1)
#define NODE_SPECIAL_NO_REST_KEYWORD   ((NODE *)-1)

#define nd_code_loc(n) (&RNODE(n)->nd_loc)
#define nd_first_column(n) ((int)(RNODE(n)->nd_loc.beg_pos.column))
#define nd_set_first_column(n, v) (RNODE(n)->nd_loc.beg_pos.column = (v))
#define nd_first_lineno(n) ((int)(RNODE(n)->nd_loc.beg_pos.lineno))
#define nd_set_first_lineno(n, v) (RNODE(n)->nd_loc.beg_pos.lineno = (v))
#define nd_first_loc(n) (RNODE(n)->nd_loc.beg_pos)
#define nd_set_first_loc(n, v) (nd_first_loc(n) = (v))

#define nd_last_column(n) ((int)(RNODE(n)->nd_loc.end_pos.column))
#define nd_set_last_column(n, v) (RNODE(n)->nd_loc.end_pos.column = (v))
#define nd_last_lineno(n) ((int)(RNODE(n)->nd_loc.end_pos.lineno))
#define nd_set_last_lineno(n, v) (RNODE(n)->nd_loc.end_pos.lineno = (v))
#define nd_last_loc(n) (RNODE(n)->nd_loc.end_pos)
#define nd_set_last_loc(n, v) (nd_last_loc(n) = (v))
#define nd_node_id(n) (RNODE(n)->node_id)
#define nd_set_node_id(n,id) (RNODE(n)->node_id = (id))

#define rb_nd_code_loc(n) (n->location)
#define rb_nd_first_loc(n) (n->location.beg_pos)
#define rb_nd_last_loc(n) (n->location.end_pos)
#define rb_nd_first_column(n) ((int)(n->location.beg_pos.column))
#define rb_nd_first_lineno(n) ((int)(n->location.beg_pos.lineno))
#define rb_nd_last_column(n) ((int)(n->location.end_pos.column))
#define rb_nd_last_lineno(n) ((int)(n->location.end_pos.lineno))
#define rb_nd_set_node_id(n,id) (n->node_id = (id))
#define rb_nd_node_id(n) (n->node_id)

static inline bool
nd_type_p(const NODE *n, enum node_type t)
{
    return (enum node_type)nd_type(n) == t;
}

#endif /* RUBY_NODE_H */
