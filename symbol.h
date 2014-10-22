/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_SYMBOL_H
#define RUBY_SYMBOL_H 1

#include "id.h"

struct RSymbol {
    struct RBasic basic;
    VALUE fstr;
    ID id;
};

#define RSYMBOL(obj) (R_CAST(RSymbol)(obj))

static inline int
id_type(ID id)
{
    if (id<=tLAST_OP_ID) {
	return -1;
    }
    return (int)(id&ID_SCOPE_MASK);
}

#define is_notop_id(id) ((id)>tLAST_OP_ID)
#define is_local_id(id) (id_type(id)==ID_LOCAL)
#define is_global_id(id) (id_type(id)==ID_GLOBAL)
#define is_instance_id(id) (id_type(id)==ID_INSTANCE)
#define is_attrset_id(id) (id_type(id)==ID_ATTRSET)
#define is_const_id(id) (id_type(id)==ID_CONST)
#define is_class_id(id) (id_type(id)==ID_CLASS)
#define is_junk_id(id) (id_type(id)==ID_JUNK)

static inline int
sym_type(VALUE sym)
{
    ID id;
    if (STATIC_SYM_P(sym)) {
	id = RSHIFT(sym, RUBY_SPECIAL_SHIFT);
	if (id<=tLAST_OP_ID) {
	    return -1;
	}
    }
    else {
	id = RSYMBOL(sym)->id;
    }
    return (int)(id&ID_SCOPE_MASK);
}

#define is_local_sym(sym) (sym_type(sym)==SYM_LOCAL)
#define is_global_sym(sym) (sym_type(sym)==SYM_GLOBAL)
#define is_instance_sym(sym) (sym_type(sym)==SYM_INSTANCE)
#define is_attrset_sym(sym) (sym_type(sym)==SYM_ATTRSET)
#define is_const_sym(sym) (sym_type(sym)==SYM_CONST)
#define is_class_sym(sym) (sym_type(sym)==SYM_CLASS)
#define is_junk_sym(sym) (sym_type(sym)==SYM_JUNK)

RUBY_FUNC_EXPORTED const unsigned int ruby_global_name_punct_bits[(0x7e - 0x20 + 31) / 32];

static inline int
is_global_name_punct(const int c)
{
    if (c <= 0x20 || 0x7e < c) return 0;
    return (ruby_global_name_punct_bits[(c - 0x20) / 32] >> (c % 32)) & 1;
}

ID rb_intern_cstr_without_pindown(const char *, long, rb_encoding *);

#endif
