/**********************************************************************

  node_dump.c - dump ruby node tree

  $Author: mame $
  created at: 09/12/06 21:23:44 JST

  Copyright (C) 2009 Yusuke Endoh

**********************************************************************/

#include "internal.h"
#include "internal/class.h"
#include "internal/variable.h"
#include "node.h"
#include "parser_prettyprint.h"

VALUE
rb_dump_literal(VALUE lit)
{
    if (!RB_SPECIAL_CONST_P(lit)) {
        VALUE str;
        switch (RB_BUILTIN_TYPE(lit)) {
          case T_CLASS: case T_MODULE: case T_ICLASS:
            str = rb_class_path(lit);
            if (RCLASS_SINGLETON_P(lit)) {
                str = rb_sprintf("<%"PRIsVALUE">", str);
            }
            return str;
          default:
            break;
        }
    }
    return rb_inspect(lit);
}

VALUE
rb_parser_dump_tree(const rb_node_t *node, int comment)
{
    if (!node) return rb_str_new_cstr("(null node)\n");
    pm_buffer_t *output = pm_buffer_new();
    rb_parser_prettyprint(output, node);
    VALUE tree = rb_str_new(pm_buffer_value(output), pm_buffer_length(output));
    pm_buffer_free(output);
    return tree;
}
