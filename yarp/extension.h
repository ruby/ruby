#ifndef YARP_EXT_NODE_H
#define YARP_EXT_NODE_H

#include <ruby.h>
#include <ruby/encoding.h>
#include "yarp.h"

#include <fcntl.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#define EXPECTED_YARP_VERSION "0.4.0"

VALUE yp_token_new(yp_parser_t *parser, yp_token_t *token, rb_encoding *encoding);

VALUE yp_ast_new(yp_parser_t *parser, yp_node_t *node, rb_encoding *encoding);

VALUE yp_compile(yp_node_t *node);

void Init_yarp_pack(void);

YP_EXPORTED_FUNCTION void Init_yarp(void);

#define DISCARD_CONST_QUAL(t, v) ((t)(uintptr_t)(v))

#endif // YARP_EXT_NODE_H
