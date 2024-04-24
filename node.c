/**********************************************************************

  node.c - ruby node tree

  $Author: mame $
  created at: 09/12/06 21:23:44 JST

  Copyright (C) 2009 Yusuke Endoh

**********************************************************************/

#ifdef UNIVERSAL_PARSER
#include <stddef.h>
#include "node.h"
#include "rubyparser.h"
#include "internal/parse.h"
#endif

#include "internal/variable.h"

#define NODE_BUF_DEFAULT_SIZE (sizeof(struct RNode) * 16)

static void
init_node_buffer_elem(node_buffer_elem_t *nbe, size_t allocated, void *xmalloc(size_t))
{
    nbe->allocated = allocated;
    nbe->used = 0;
    nbe->len = 0;
    nbe->nodes = xmalloc(allocated / sizeof(struct RNode) * sizeof(struct RNode *)); /* All node requires at least RNode */
}

static void
init_node_buffer_list(node_buffer_list_t *nb, node_buffer_elem_t *head, void *xmalloc(size_t))
{
    init_node_buffer_elem(head, NODE_BUF_DEFAULT_SIZE, xmalloc);
    nb->head = nb->last = head;
    nb->head->next = NULL;
}

#ifdef UNIVERSAL_PARSER
#define ruby_xmalloc config->malloc
#endif

#ifdef UNIVERSAL_PARSER
static node_buffer_t *
rb_node_buffer_new(const rb_parser_config_t *config)
#else
static node_buffer_t *
rb_node_buffer_new(void)
#endif
{
    const size_t bucket_size = offsetof(node_buffer_elem_t, buf) + NODE_BUF_DEFAULT_SIZE;
    const size_t alloc_size = sizeof(node_buffer_t) + (bucket_size);
    STATIC_ASSERT(
        integer_overflow,
        offsetof(node_buffer_elem_t, buf) + NODE_BUF_DEFAULT_SIZE
        > sizeof(node_buffer_t) + sizeof(node_buffer_elem_t));
    node_buffer_t *nb = ruby_xmalloc(alloc_size);
    init_node_buffer_list(&nb->buffer_list, (node_buffer_elem_t*)&nb[1], ruby_xmalloc);
    nb->local_tables = 0;
    nb->tokens = 0;
#ifdef UNIVERSAL_PARSER
    nb->config = config;
#endif
    return nb;
}

#ifdef UNIVERSAL_PARSER
#undef ruby_xmalloc
#define ruby_xmalloc ast->node_buffer->config->malloc
#undef xfree
#define xfree ast->node_buffer->config->free
#define rb_xmalloc_mul_add ast->node_buffer->config->xmalloc_mul_add
#define ruby_xrealloc(var,size) (ast->node_buffer->config->realloc_n((void *)var, 1, size))
#endif

typedef void node_itr_t(rb_ast_t *ast, void *ctx, NODE *node);
static void iterate_node_values(rb_ast_t *ast, node_buffer_list_t *nb, node_itr_t * func, void *ctx);

void
rb_node_init(NODE *n, enum node_type type)
{
    RNODE(n)->flags = 0;
    nd_init_type(RNODE(n), type);
    RNODE(n)->nd_loc.beg_pos.lineno = 0;
    RNODE(n)->nd_loc.beg_pos.column = 0;
    RNODE(n)->nd_loc.end_pos.lineno = 0;
    RNODE(n)->nd_loc.end_pos.column = 0;
    RNODE(n)->node_id = -1;
}

const char *
rb_node_name(int node)
{
    switch (node) {
#include "node_name.inc"
      default:
        return 0;
    }
}

#ifdef UNIVERSAL_PARSER
const char *
ruby_node_name(int node)
{
    return rb_node_name(node);
}
#else
const char *
ruby_node_name(int node)
{
    const char *name = rb_node_name(node);

    if (!name) rb_bug("unknown node: %d", node);
    return name;
}
#endif

static void
node_buffer_list_free(rb_ast_t *ast, node_buffer_list_t * nb)
{
    node_buffer_elem_t *nbe = nb->head;
    while (nbe != nb->last) {
        void *buf = nbe;
        xfree(nbe->nodes);
        nbe = nbe->next;
        xfree(buf);
    }

    /* The last node_buffer_elem_t is allocated in the node_buffer_t, so we
     * only need to free the nodes. */
    xfree(nbe->nodes);
}

struct rb_ast_local_table_link {
    struct rb_ast_local_table_link *next;
    // struct rb_ast_id_table {
    int size;
    ID ids[FLEX_ARY_LEN];
    // }
};

static void
parser_string_free(rb_ast_t *ast, rb_parser_string_t *str)
{
    if (!str) return;
    xfree(str->ptr);
    xfree(str);
}

static void
parser_ast_token_free(rb_ast_t *ast, rb_parser_ast_token_t *token)
{
    if (!token) return;
    parser_string_free(ast, token->str);
    xfree(token);
}

static void
parser_tokens_free(rb_ast_t *ast, rb_parser_ary_t *tokens)
{
    for (long i = 0; i < tokens->len; i++) {
        parser_ast_token_free(ast, tokens->data[i]);
    }
    xfree(tokens->data);
    xfree(tokens);
}

static void
free_ast_value(rb_ast_t *ast, void *ctx, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_STR:
        parser_string_free(ast, RNODE_STR(node)->string);
        break;
      case NODE_DSTR:
        parser_string_free(ast, RNODE_DSTR(node)->string);
        break;
      case NODE_XSTR:
        parser_string_free(ast, RNODE_XSTR(node)->string);
        break;
      case NODE_DXSTR:
        parser_string_free(ast, RNODE_DXSTR(node)->string);
        break;
      case NODE_SYM:
        parser_string_free(ast, RNODE_SYM(node)->string);
        break;
      case NODE_REGX:
      case NODE_MATCH:
        parser_string_free(ast, RNODE_REGX(node)->string);
        break;
      case NODE_DSYM:
        parser_string_free(ast, RNODE_DSYM(node)->string);
        break;
      case NODE_DREGX:
        parser_string_free(ast, RNODE_DREGX(node)->string);
        break;
      case NODE_FILE:
        parser_string_free(ast, RNODE_FILE(node)->path);
        break;
      case NODE_INTEGER:
        xfree(RNODE_INTEGER(node)->val);
        break;
      case NODE_FLOAT:
        xfree(RNODE_FLOAT(node)->val);
        break;
      case NODE_RATIONAL:
        xfree(RNODE_RATIONAL(node)->val);
        break;
      case NODE_IMAGINARY:
        xfree(RNODE_IMAGINARY(node)->val);
        break;
      default:
        break;
    }
}

static void
rb_node_buffer_free(rb_ast_t *ast, node_buffer_t *nb)
{
    if (ast->node_buffer && ast->node_buffer->tokens) {
        parser_tokens_free(ast, ast->node_buffer->tokens);
    }
    iterate_node_values(ast, &nb->buffer_list, free_ast_value, NULL);
    node_buffer_list_free(ast, &nb->buffer_list);
    struct rb_ast_local_table_link *local_table = nb->local_tables;
    while (local_table) {
        struct rb_ast_local_table_link *next_table = local_table->next;
        xfree(local_table);
        local_table = next_table;
    }
    xfree(nb);
}

#define buf_add_offset(nbe, offset) ((char *)(nbe->buf) + (offset))

static NODE *
ast_newnode_in_bucket(rb_ast_t *ast, node_buffer_list_t *nb, size_t size, size_t alignment)
{
    size_t padding;
    NODE *ptr;

    padding = alignment - (size_t)buf_add_offset(nb->head, nb->head->used) % alignment;
    padding = padding == alignment ? 0 : padding;

    if (nb->head->used + size + padding > nb->head->allocated) {
        size_t n = nb->head->allocated * 2;
        node_buffer_elem_t *nbe;
        nbe = rb_xmalloc_mul_add(n, sizeof(char *), offsetof(node_buffer_elem_t, buf));
        init_node_buffer_elem(nbe, n, ruby_xmalloc);
        nbe->next = nb->head;
        nb->head = nbe;
        padding = 0; /* malloc returns aligned address then no need to add padding */
    }

    ptr = (NODE *)buf_add_offset(nb->head, nb->head->used + padding);
    nb->head->used += (size + padding);
    nb->head->nodes[nb->head->len++] = ptr;
    return ptr;
}

NODE *
rb_ast_newnode(rb_ast_t *ast, enum node_type type, size_t size, size_t alignment)
{
    node_buffer_t *nb = ast->node_buffer;
    node_buffer_list_t *bucket = &nb->buffer_list;
    return ast_newnode_in_bucket(ast, bucket, size, alignment);
}

rb_ast_id_table_t *
rb_ast_new_local_table(rb_ast_t *ast, int size)
{
    size_t alloc_size = sizeof(struct rb_ast_local_table_link) + size * sizeof(ID);
    struct rb_ast_local_table_link *link = ruby_xmalloc(alloc_size);
    link->next = ast->node_buffer->local_tables;
    ast->node_buffer->local_tables = link;
    link->size = size;

    return (rb_ast_id_table_t *) &link->size;
}

rb_ast_id_table_t *
rb_ast_resize_latest_local_table(rb_ast_t *ast, int size)
{
    struct rb_ast_local_table_link *link = ast->node_buffer->local_tables;
    size_t alloc_size = sizeof(struct rb_ast_local_table_link) + size * sizeof(ID);
    link = ruby_xrealloc(link, alloc_size);
    ast->node_buffer->local_tables = link;
    link->size = size;

    return (rb_ast_id_table_t *) &link->size;
}

void
rb_ast_delete_node(rb_ast_t *ast, NODE *n)
{
    (void)ast;
    (void)n;
    /* should we implement freelist? */
}

#ifdef UNIVERSAL_PARSER
rb_ast_t *
rb_ast_new(const rb_parser_config_t *config)
{
    node_buffer_t *nb = rb_node_buffer_new(config);
    return config->ast_new((VALUE)nb);
}
#else
rb_ast_t *
rb_ast_new(void)
{
    node_buffer_t *nb = rb_node_buffer_new();
    return IMEMO_NEW(rb_ast_t, imemo_ast, (VALUE)nb);
}
#endif

static void
iterate_buffer_elements(rb_ast_t *ast, node_buffer_elem_t *nbe, long len, node_itr_t *func, void *ctx)
{
    long cursor;
    for (cursor = 0; cursor < len; cursor++) {
        func(ast, ctx, nbe->nodes[cursor]);
    }
}

static void
iterate_node_values(rb_ast_t *ast, node_buffer_list_t *nb, node_itr_t * func, void *ctx)
{
    node_buffer_elem_t *nbe = nb->head;

    while (nbe) {
        iterate_buffer_elements(ast, nbe, nbe->len, func, ctx);
        nbe = nbe->next;
    }
}

static void
script_lines_free(rb_ast_t *ast, rb_parser_ary_t *script_lines)
{
    for (long i = 0; i < script_lines->len; i++) {
        parser_string_free(ast, (rb_parser_string_t *)script_lines->data[i]);
    }
    xfree(script_lines->data);
    xfree(script_lines);
}

void
rb_ast_free(rb_ast_t *ast)
{
    if (ast->node_buffer) {
        if (ast->body.script_lines && !FIXNUM_P((VALUE)ast->body.script_lines)) {
            script_lines_free(ast, ast->body.script_lines);
            ast->body.script_lines = NULL;
        }
        rb_node_buffer_free(ast, ast->node_buffer);
        ast->node_buffer = 0;
    }
}

static size_t
buffer_list_size(node_buffer_list_t *nb)
{
    size_t size = 0;
    node_buffer_elem_t *nbe = nb->head;
    while (nbe != nb->last) {
        size += offsetof(node_buffer_elem_t, buf) + nbe->used;
        nbe = nbe->next;
    }
    return size;
}

size_t
rb_ast_memsize(const rb_ast_t *ast)
{
    size_t size = 0;
    node_buffer_t *nb = ast->node_buffer;

    if (nb) {
        size += sizeof(node_buffer_t);
        size += buffer_list_size(&nb->buffer_list);
    }
    return size;
}

void
rb_ast_dispose(rb_ast_t *ast)
{
    rb_ast_free(ast);
}

VALUE
rb_node_set_type(NODE *n, enum node_type t)
{
    return nd_init_type(n, t);
}
