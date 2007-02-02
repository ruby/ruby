/**********************************************************************

  compile.h -

  $Author$
  $Date$
  created at: 04/01/01 23:36:57 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#ifndef _COMPILER_H_INCLUDED_
#define _COMPILER_H_INCLUDED_

#include "version.h"

#if YARVDEBUG > CPDEBUG
#undef  CPDEBUG
#define CPDEBUG YARVDEBUG
#endif

/*  */
/**
 * debug function(macro) interface depend on CPDEBUG
 *
 * debug level:
 *  0: no debug output
 *  1: show node type
 *  2: show node important parameters
 *  ...
 *  5: show other parameters
 * 10: show every AST array
 */

#if 0
#undef  CPDEBUG
#define CPDEBUG 2
#endif

#if CPDEBUG > 0

#define debugp(header, value)                   \
  (debug_indent(0, CPDEBUG, gl_node_level * 2), \
   debug_value(0, CPDEBUG, header, value))

#define debugi(header, id)                      \
  (debug_indent(0, CPDEBUG, gl_node_level * 2), \
   debug_id(0, CPDEBUG, header, id))

#define debugp_param(header, value)             \
  (debug_indent(1, CPDEBUG, gl_node_level * 2), \
   debug_value(1, CPDEBUG, header, value))

#define debugp_verbose(header, value)           \
  (debug_indent(2, CPDEBUG, gl_node_level * 2), \
   debug_value(2, CPDEBUG, header, value))

#define debugp_verbose_node(header, value)       \
  (debug_indent(10, CPDEBUG, gl_node_level * 2), \
   debug_value(10, CPDEBUG, header, value))

#define debug_nodeprint(node)                    \
  debug_indent(-1, CPDEBUG, gl_node_level*2);    \
  printf("node: %s (%d)\n", node_name(nd_type(node)), nd_line(node)); \
  gl_node_level ++;

#define debug_nodeprint_close()  gl_node_level --;

#else

static inline ID
r_id(ID id)
{
    return id;
}

static inline VALUE
r_value(VALUE value)
{
    return value;
}

#define debugi(header, id)                 r_id(id)
#define debugp(header, value)              r_value(value)
#define debugp_verbose(header, value)      r_value(value)
#define debugp_verbose_node(header, value) r_value(value)
#define debugp_param(header, value)        r_value(value)
#define debug_nodeprint(node)
#define debug_nodeprint_close()
#endif

#if CPDEBUG > 1
#define debugs debug_indent(-1, CPDEBUG, gl_node_level*2), printf
#define debug_compile(msg, v) (debug_indent(-1, CPDEBUG, gl_node_level*2), printf("%s", msg), (v))
#else
#define debugs                             if(0)printf
#define debug_compile(msg, v) (v)
#endif


/* create new label */
#define NEW_LABEL(l) new_label_body(iseq, l)

#define iseq_filename(iseq) \
  (((yarv_iseq_t*)DATA_PTR(iseq))->file_name)

#define NEW_ISEQVAL(node, name, type)       \
  new_child_iseq(iseq, node, name, 0, type)

#define NEW_CHILD_ISEQVAL(node, name, type)       \
  new_child_iseq(iseq, node, name, iseq->self, type)

#define NEW_SPECIAQL_BLOCK_ISEQVAL(iseq, sym) \
  new_child_iseq(iseq, iseq->node, iseq->name, iseq->parent_iseq, iseq->type, sym)

/* add instructions */
#define ADD_SEQ(seq1, seq2) \
  APPEND_LIST(seq1, seq2)

/* add an instruction */
#define ADD_INSN(seq, line, insn) \
  ADD_ELEM(seq, (LINK_ELEMENT *) new_insn_body(iseq, line, BIN(insn), 0))

/* add an instruction with label operand */
#define ADD_INSNL(seq, line, insn, label) \
  ADD_ELEM(seq, (LINK_ELEMENT *) \
           new_insn_body(iseq, line, BIN(insn), 1, (VALUE)label))

/* add an instruction with some operands (1, 2, 3, 5) */
#define ADD_INSN1(seq, line, insn, op1) \
  ADD_ELEM(seq, (LINK_ELEMENT *) \
           new_insn_body(iseq, line, BIN(insn), 1, (VALUE)op1))

#define ADD_INSN2(seq, line, insn, op1, op2) \
  ADD_ELEM(seq, (LINK_ELEMENT *) \
           new_insn_body(iseq, line, BIN(insn), 2, (VALUE)op1, (VALUE)op2))

#define ADD_INSN3(seq, line, insn, op1, op2, op3) \
  ADD_ELEM(seq, (LINK_ELEMENT *) \
           new_insn_body(iseq, line, BIN(insn), 3, (VALUE)op1, (VALUE)op2, (VALUE)op3))

/* Specific Insn factory */
#define ADD_SEND(seq, line, id, argc) \
  ADD_SEND_R(seq, line, id, argc, (VALUE)Qfalse, (VALUE)INT2FIX(0))

#define ADD_CALL_RECEIVER(seq, line) \
  ADD_INSN(seq, line, putnil)

#define ADD_CALL(seq, line, id, argc) \
  ADD_SEND_R(seq, line, id, argc, (VALUE)Qfalse, (VALUE)INT2FIX(VM_CALL_FCALL_BIT))

#define ADD_CALL_WITH_BLOCK(seq, line, id, argc, block) \
  ADD_SEND_R(seq, line, id, argc, block, (VALUE)INT2FIX(VM_CALL_FCALL_BIT))

#define ADD_SEND_R(seq, line, id, argc, block, flag) \
  ADD_ELEM(seq, (LINK_ELEMENT *) \
           new_insn_send(iseq, line, \
                         (VALUE)id, (VALUE)argc, (VALUE)block, (VALUE)flag))

/* add label */
#define ADD_LABEL(seq, label) \
  ADD_ELEM(seq, (LINK_ELEMENT *)label)

#define ADD_CATCH_ENTRY(type, ls, le, iseqv, lc) \
  (tmp = rb_ary_new(),                               \
   rb_ary_push(tmp, type),                           \
   rb_ary_push(tmp, (VALUE) ls | 1),                 \
   rb_ary_push(tmp, (VALUE) le | 1),                 \
   rb_ary_push(tmp, iseqv),                          \
   rb_ary_push(tmp, (VALUE) lc | 1),                 \
   rb_ary_push(iseq->compile_data->catch_table_ary, tmp))

/* compile node */
#define COMPILE(anchor, desc, node) \
  (debug_compile("== " desc "\n", \
                 iseq_compile_each(iseq, anchor, node, 0)))

/* compile node, this node's value will be poped */
#define COMPILE_POPED(anchor, desc, node)    \
  (debug_compile("== " desc "\n", \
                 iseq_compile_each(iseq, anchor, node, 1)))

/* compile node, which is poped when 'poped' is true */
#define COMPILE_(anchor, desc, node, poped)  \
  (debug_compile("== " desc "\n", \
                 iseq_compile_each(iseq, anchor, node, poped)))

#define OPERAND_AT(insn, idx) \
  (((INSN*)(insn))->operands[idx])

#define INSN_OF(insn) \
  (((INSN*)(insn))->insn_id)

/* error */
#define COMPILE_ERROR(strs)                        \
{                                                  \
  VALUE tmp = GET_THREAD()->errinfo;               \
  if(CPDEBUG)rb_bug strs;                          \
  GET_THREAD()->errinfo = iseq->compile_data->err_info;  \
  rb_compile_error strs;                           \
  iseq->compile_data->err_info = GET_THREAD()->errinfo; \
  GET_THREAD()->errinfo = tmp;                     \
  ret = 0;                                         \
  break;                                           \
}


#define COMPILE_OK 1
#define COMPILE_NG 0

#define DECL_ANCHOR(name) \
  LINK_ANCHOR  name##_body__ = {{0,}, &name##_body__.anchor}; \
  LINK_ANCHOR *name = & name##_body__

#endif /* _COMPILER_H_INCLUDED_ */
