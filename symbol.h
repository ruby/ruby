#ifndef RUBY_SYMBOL_H
#define RUBY_SYMBOL_H 1
/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#include "id.h"
#include "ruby/encoding.h"

#define DYNAMIC_ID_P(id) (!(id&ID_STATIC_SYM)&&id>tLAST_OP_ID)
#define STATIC_ID2SYM(id)  (((VALUE)(id)<<RUBY_SPECIAL_SHIFT)|SYMBOL_FLAG)

#ifdef HAVE_BUILTIN___BUILTIN_CONSTANT_P
#define rb_id2sym(id) \
    RB_GNUC_EXTENSION_BLOCK(__builtin_constant_p(id) && !DYNAMIC_ID_P(id) ? \
                            STATIC_ID2SYM(id) : rb_id2sym(id))
#endif

struct RSymbol {
    struct RBasic basic;
    st_index_t hashval;
    VALUE fstr;
    ID id;
};

#define RSYMBOL(obj) ((struct RSymbol *)(obj))

#define is_notop_id(id) ((id)>tLAST_OP_ID)
#define is_local_id(id) (id_type(id)==ID_LOCAL)
#define is_global_id(id) (id_type(id)==ID_GLOBAL)
#define is_instance_id(id) (id_type(id)==ID_INSTANCE)
#define is_attrset_id(id) ((id)==idASET||id_type(id)==ID_ATTRSET)
#define is_const_id(id) (id_type(id)==ID_CONST)
#define is_class_id(id) (id_type(id)==ID_CLASS)
#define is_internal_id(id) (id_type(id)==ID_INTERNAL)

static inline int
id_type(ID id)
{
    if (is_notop_id(id)) {
        return (int)(id&ID_SCOPE_MASK);
    }
    else {
        return -1;
    }
}

typedef uint32_t rb_id_serial_t;
static const uint32_t RB_ID_SERIAL_MAX = /* 256M on LP32 */
    UINT32_MAX >>
    ((sizeof(ID)-sizeof(rb_id_serial_t))*CHAR_BIT < RUBY_ID_SCOPE_SHIFT ?
     RUBY_ID_SCOPE_SHIFT : 0);

static inline rb_id_serial_t
rb_id_to_serial(ID id)
{
    if (is_notop_id(id)) {
        return (rb_id_serial_t)(id >> ID_SCOPE_SHIFT);
    }
    else {
        return (rb_id_serial_t)id;
    }
}

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

#define is_local_sym(sym) (sym_type(sym)==ID_LOCAL)
#define is_global_sym(sym) (sym_type(sym)==ID_GLOBAL)
#define is_instance_sym(sym) (sym_type(sym)==ID_INSTANCE)
#define is_attrset_sym(sym) (sym_type(sym)==ID_ATTRSET)
#define is_const_sym(sym) (sym_type(sym)==ID_CONST)
#define is_class_sym(sym) (sym_type(sym)==ID_CLASS)
#define is_internal_sym(sym) (sym_type(sym)==ID_INTERNAL)

#ifndef RIPPER
RUBY_FUNC_EXPORTED
#else
RUBY_EXTERN
#endif
const uint_least32_t ruby_global_name_punct_bits[(0x7e - 0x20 + 31) / 32];

static inline int
is_global_name_punct(const int c)
{
    if (c <= 0x20 || 0x7e < c) return 0;
    return (ruby_global_name_punct_bits[(c - 0x20) / 32] >> (c % 32)) & 1;
}

RUBY_SYMBOL_EXPORT_BEGIN

int rb_enc_symname_type(const char *name, long len, rb_encoding *enc, unsigned int allowed_attrset);
size_t rb_sym_immortal_count(void);

RUBY_SYMBOL_EXPORT_END
#endif
