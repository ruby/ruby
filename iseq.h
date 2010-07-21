/**********************************************************************

  iseq.h -

  $Author$
  created at: 04/01/01 23:36:57 JST

  Copyright (C) 2004-2008 Koichi Sasada

**********************************************************************/

#ifndef RUBY_COMPILE_H
#define RUBY_COMPILE_H

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility push(default)
#endif

/* compile.c */
VALUE rb_iseq_compile_node(VALUE self, NODE *node);
int rb_iseq_translate_threaded_code(rb_iseq_t *iseq);
VALUE rb_iseq_build_from_ary(rb_iseq_t *iseq, VALUE locals, VALUE args,
			     VALUE exception, VALUE body);

/* iseq.c */
VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);
struct st_table *ruby_insn_make_insn_table(void);

#define ISEQ_TYPE_TOP    INT2FIX(1)
#define ISEQ_TYPE_METHOD INT2FIX(2)
#define ISEQ_TYPE_BLOCK  INT2FIX(3)
#define ISEQ_TYPE_CLASS  INT2FIX(4)
#define ISEQ_TYPE_RESCUE INT2FIX(5)
#define ISEQ_TYPE_ENSURE INT2FIX(6)
#define ISEQ_TYPE_EVAL   INT2FIX(7)
#define ISEQ_TYPE_MAIN   INT2FIX(8)
#define ISEQ_TYPE_DEFINED_GUARD INT2FIX(9)

#define CATCH_TYPE_RESCUE ((int)INT2FIX(1))
#define CATCH_TYPE_ENSURE ((int)INT2FIX(2))
#define CATCH_TYPE_RETRY  ((int)INT2FIX(3))
#define CATCH_TYPE_BREAK  ((int)INT2FIX(4))
#define CATCH_TYPE_REDO   ((int)INT2FIX(5))
#define CATCH_TYPE_NEXT   ((int)INT2FIX(6))

struct iseq_insn_info_entry {
    unsigned short position;
    unsigned short line_no;
    unsigned short sp;
};

struct iseq_catch_table_entry {
    VALUE type;
    VALUE iseq;
    unsigned long start;
    unsigned long end;
    unsigned long cont;
    unsigned long sp;
};

#define INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE (512)

struct iseq_compile_data_storage {
    struct iseq_compile_data_storage *next;
    unsigned long pos;
    unsigned long size;
    char *buff;
};

struct iseq_compile_data {
    /* GC is needed */
    VALUE err_info;
    VALUE mark_ary;
    VALUE catch_table_ary;	/* Array */

    /* GC is not needed */
    struct iseq_label_data *start_label;
    struct iseq_label_data *end_label;
    struct iseq_label_data *redo_label;
    VALUE current_block;
    VALUE ensure_node;
    VALUE for_iseq;
    struct iseq_compile_data_ensure_node_stack *ensure_node_stack;
    int loopval_popped;	/* used by NODE_BREAK */
    int cached_const;
    struct iseq_compile_data_storage *storage_head;
    struct iseq_compile_data_storage *storage_current;
    int last_line;
    int last_coverable_line;
    int flip_cnt;
    int label_no;
    int node_level;
    const rb_compile_option_t *option;
};

/* defined? */
#define DEFINED_IVAR   INT2FIX(1)
#define DEFINED_IVAR2  INT2FIX(2)
#define DEFINED_GVAR   INT2FIX(3)
#define DEFINED_CVAR   INT2FIX(4)
#define DEFINED_CONST  INT2FIX(5)
#define DEFINED_METHOD INT2FIX(6)
#define DEFINED_YIELD  INT2FIX(7)
#define DEFINED_REF    INT2FIX(8)
#define DEFINED_ZSUPER INT2FIX(9)
#define DEFINED_FUNC   INT2FIX(10)

#if defined __GNUC__ && __GNUC__ >= 4
#pragma GCC visibility pop
#endif

#endif /* RUBY_COMPILE_H */
