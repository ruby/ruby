/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_SYMBOL_H
#define RUBY_SYMBOL_H 1

#include "id.h"

#define ID_DYNAMIC_SYM_P(id) (!(id&ID_STATIC_SYM)&&id>tLAST_TOKEN)
#define STATIC_SYM2ID(sym) RSHIFT((unsigned long)(sym), RUBY_SPECIAL_SHIFT)
#define STATIC_ID2SYM(id)  (((VALUE)(id)<<RUBY_SPECIAL_SHIFT)|SYMBOL_FLAG)

static inline int
id_type(ID id)
{
    if (id<=tLAST_OP_ID) {
	return -1;
    }
    if (id&ID_STATIC_SYM) {
	return (int)((id)&ID_SCOPE_MASK);
    }
    else {
	VALUE dsym = (VALUE)id;
	return (int)(RSYMBOL(dsym)->type);
    }
}

#define is_notop_id(id) ((id)>tLAST_OP_ID)
#define is_local_id(id) (id_type(id)==ID_LOCAL)
#define is_global_id(id) (id_type(id)==ID_GLOBAL)
#define is_instance_id(id) (id_type(id)==ID_INSTANCE)
#define is_attrset_id(id) (id_type(id)==ID_ATTRSET)
#define is_const_id(id) (id_type(id)==ID_CONST)
#define is_class_id(id) (id_type(id)==ID_CLASS)
#define is_junk_id(id) (id_type(id)==ID_JUNK)

RUBY_FUNC_EXPORTED const unsigned int ruby_global_name_punct_bits[(0x7e - 0x20 + 31) / 32];

static inline int
is_global_name_punct(const int c)
{
    if (c <= 0x20 || 0x7e < c) return 0;
    return (ruby_global_name_punct_bits[(c - 0x20) / 32] >> (c % 32)) & 1;
}

ID rb_intern_cstr_without_pindown(const char *, long, rb_encoding *);

#endif
