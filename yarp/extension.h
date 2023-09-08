#ifndef YARP_EXT_NODE_H
#define YARP_EXT_NODE_H

#define EXPECTED_YARP_VERSION "0.11.0"

#include <ruby.h>
#include <ruby/encoding.h>
#include "yarp.h"

VALUE yp_source_new(yp_parser_t *parser, rb_encoding *encoding);
VALUE yp_token_new(yp_parser_t *parser, yp_token_t *token, rb_encoding *encoding, VALUE source);
VALUE yp_ast_new(yp_parser_t *parser, yp_node_t *node, rb_encoding *encoding);

void Init_yarp_api_node(void);
void Init_yarp_pack(void);
YP_EXPORTED_FUNCTION void Init_yarp(void);

#endif
