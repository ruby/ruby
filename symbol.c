/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/symbol.h"
#include "internal/vm.h"
#include "probes.h"
#include "ruby/encoding.h"
#include "ruby/st.h"
#include "symbol.h"
#include "vm_sync.h"
#include "builtin.h"

#if defined(USE_SYMBOL_GC) && !(USE_SYMBOL_GC+0)
# undef USE_SYMBOL_GC
# define USE_SYMBOL_GC 0
#else
# undef USE_SYMBOL_GC
# define USE_SYMBOL_GC 1
#endif
#if defined(SYMBOL_DEBUG) && (SYMBOL_DEBUG+0)
# undef SYMBOL_DEBUG
# define SYMBOL_DEBUG 1
#else
# undef SYMBOL_DEBUG
# define SYMBOL_DEBUG 0
#endif
#ifndef CHECK_ID_SERIAL
# define CHECK_ID_SERIAL SYMBOL_DEBUG
#endif

#define SYMBOL_PINNED_P(sym) (RSYMBOL(sym)->id&~ID_SCOPE_MASK)

#define STATIC_SYM2ID(sym) RSHIFT((VALUE)(sym), RUBY_SPECIAL_SHIFT)

static ID register_static_symid(ID, const char *, long, rb_encoding *);
static ID register_static_symid_str(ID, VALUE);
#define REGISTER_SYMID(id, name) register_static_symid((id), (name), strlen(name), enc)
#include "id.c"

#define is_identchar(p,e,enc) (ISALNUM((unsigned char)*(p)) || (*(p)) == '_' || !ISASCII(*(p)))

#define op_tbl_count numberof(op_tbl)
STATIC_ASSERT(op_tbl_name_size, sizeof(op_tbl[0].name) == 3);
#define op_tbl_len(i) (!op_tbl[i].name[1] ? 1 : !op_tbl[i].name[2] ? 2 : 3)

static void
Init_op_tbl(void)
{
    int i;
    rb_encoding *const enc = rb_usascii_encoding();

    for (i = '!'; i <= '~'; ++i) {
        if (!ISALNUM(i) && i != '_') {
            char c = (char)i;
            register_static_symid(i, &c, 1, enc);
        }
    }
    for (i = 0; i < op_tbl_count; ++i) {
        register_static_symid(op_tbl[i].token, op_tbl[i].name, op_tbl_len(i), enc);
    }
}

static const int ID_ENTRY_UNIT = 512;

enum id_entry_type {
    ID_ENTRY_STR,
    ID_ENTRY_SYM,
    ID_ENTRY_SIZE
};

rb_symbols_t ruby_global_symbols = {tNEXT_ID-1};

static const struct st_hash_type symhash = {
    rb_str_hash_cmp,
    rb_str_hash,
};

void
Init_sym(void)
{
    rb_symbols_t *symbols = &ruby_global_symbols;

    VALUE dsym_fstrs = rb_ident_hash_new();
    symbols->dsymbol_fstr_hash = dsym_fstrs;
    rb_vm_register_global_object(dsym_fstrs);
    rb_obj_hide(dsym_fstrs);

    symbols->str_sym = st_init_table_with_size(&symhash, 1000);
    symbols->ids = rb_ary_hidden_new(0);
    rb_vm_register_global_object(symbols->ids);

    Init_op_tbl();
    Init_id();
}

WARN_UNUSED_RESULT(static VALUE dsymbol_alloc(rb_symbols_t *symbols, const VALUE klass, const VALUE str, rb_encoding *const enc, const ID type));
WARN_UNUSED_RESULT(static VALUE dsymbol_check(rb_symbols_t *symbols, const VALUE sym));
WARN_UNUSED_RESULT(static ID lookup_str_id(VALUE str));
WARN_UNUSED_RESULT(static VALUE lookup_str_sym_with_lock(rb_symbols_t *symbols, const VALUE str));
WARN_UNUSED_RESULT(static VALUE lookup_str_sym(const VALUE str));
WARN_UNUSED_RESULT(static VALUE lookup_id_str(ID id));
WARN_UNUSED_RESULT(static ID intern_str(VALUE str, int mutable));

#define GLOBAL_SYMBOLS_ENTER(symbols) rb_symbols_t *symbols = &ruby_global_symbols; RB_VM_LOCK_ENTER()
#define GLOBAL_SYMBOLS_LEAVE()        RB_VM_LOCK_LEAVE()

ID
rb_id_attrset(ID id)
{
    VALUE str, sym;
    int scope;

    if (!is_notop_id(id)) {
        switch (id) {
          case tAREF: case tASET:
            return tASET;	/* only exception */
        }
        rb_name_error(id, "cannot make operator ID :%"PRIsVALUE" attrset",
                      rb_id2str(id));
    }
    else {
        scope = id_type(id);
        switch (scope) {
          case ID_LOCAL: case ID_INSTANCE: case ID_GLOBAL:
          case ID_CONST: case ID_CLASS: case ID_JUNK:
            break;
          case ID_ATTRSET:
            return id;
          default:
            {
                if ((str = lookup_id_str(id)) != 0) {
                    rb_name_error(id, "cannot make unknown type ID %d:%"PRIsVALUE" attrset",
                                  scope, str);
                }
                else {
                    rb_name_error_str(Qnil, "cannot make unknown type anonymous ID %d:%"PRIxVALUE" attrset",
                                      scope, (VALUE)id);
                }
            }
        }
    }

    /* make new symbol and ID */
    if (!(str = lookup_id_str(id))) {
        static const char id_types[][8] = {
            "local",
            "instance",
            "invalid",
            "global",
            "attrset",
            "const",
            "class",
            "junk",
        };
        rb_name_error(id, "cannot make anonymous %.*s ID %"PRIxVALUE" attrset",
                      (int)sizeof(id_types[0]), id_types[scope], (VALUE)id);
    }
    str = rb_str_dup(str);
    rb_str_cat(str, "=", 1);
    sym = lookup_str_sym(str);
    id = sym ? rb_sym2id(sym) : intern_str(str, 1);
    return id;
}

static int
is_special_global_name(const char *m, const char *e, rb_encoding *enc)
{
    int mb = 0;

    if (m >= e) return 0;
    if (is_global_name_punct(*m)) {
        ++m;
    }
    else if (*m == '-') {
        if (++m >= e) return 0;
        if (is_identchar(m, e, enc)) {
            if (!ISASCII(*m)) mb = 1;
            m += rb_enc_mbclen(m, e, enc);
        }
    }
    else {
        if (!ISDIGIT(*m)) return 0;
        do {
            if (!ISASCII(*m)) mb = 1;
            ++m;
        } while (m < e && ISDIGIT(*m));
    }
    return m == e ? mb + 1 : 0;
}

int
rb_symname_p(const char *name)
{
    return rb_enc_symname_p(name, rb_ascii8bit_encoding());
}

int
rb_enc_symname_p(const char *name, rb_encoding *enc)
{
    return rb_enc_symname2_p(name, strlen(name), enc);
}

static int
rb_sym_constant_char_p(const char *name, long nlen, rb_encoding *enc)
{
    int c, len;
    const char *end = name + nlen;

    if (nlen < 1) return FALSE;
    if (ISASCII(*name)) return ISUPPER(*name);
    c = rb_enc_precise_mbclen(name, end, enc);
    if (!MBCLEN_CHARFOUND_P(c)) return FALSE;
    len = MBCLEN_CHARFOUND_LEN(c);
    c = rb_enc_mbc_to_codepoint(name, end, enc);
    if (rb_enc_isupper(c, enc)) return TRUE;
    if (rb_enc_islower(c, enc)) return FALSE;
    if (ONIGENC_IS_UNICODE(enc)) {
        static int ctype_titlecase = 0;
        if (!ctype_titlecase) {
            static const UChar cname[] = "titlecaseletter";
            static const UChar *const end = cname + sizeof(cname) - 1;
            ctype_titlecase = ONIGENC_PROPERTY_NAME_TO_CTYPE(enc, cname, end);
        }
        if (rb_enc_isctype(c, ctype_titlecase, enc)) return TRUE;
    }
    else {
        /* fallback to case-folding */
        OnigUChar fold[ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM];
        const OnigUChar *beg = (const OnigUChar *)name;
        int r = enc->mbc_case_fold(ONIGENC_CASE_FOLD,
                                   &beg, (const OnigUChar *)end,
                                   fold, enc);
        if (r > 0 && (r != len || memcmp(fold, name, r)))
            return TRUE;
    }
    return FALSE;
}

#define IDSET_ATTRSET_FOR_SYNTAX ((1U<<ID_LOCAL)|(1U<<ID_CONST))
#define IDSET_ATTRSET_FOR_INTERN (~(~0U<<(1<<ID_SCOPE_SHIFT)) & ~(1U<<ID_ATTRSET))

struct enc_synmane_type_leading_chars_tag {
    const enum { invalid, stophere, needmore, } kind;
    const enum ruby_id_types type;
    const long nread;
};

#define t struct enc_synmane_type_leading_chars_tag

static struct enc_synmane_type_leading_chars_tag
enc_synmane_type_leading_chars(const char *name, long len, rb_encoding *enc, int allowed_attrset)
{
    const char *m = name;
    const char *e = m + len;

    if (! rb_enc_asciicompat(enc)) {
        return (t) { invalid, 0, 0, };
    }
    else if (! m) {
        return (t) { invalid, 0, 0, };
    }
    else if ( len <= 0 ) {
        return (t) { invalid, 0, 0, };
    }
    switch (*m) {
      case '\0':
        return (t) { invalid, 0, 0, };

      case '$':
        if (is_special_global_name(++m, e, enc)) {
            return (t) { stophere, ID_GLOBAL, len, };
        }
        else {
            return (t) { needmore, ID_GLOBAL, 1, };
        }

      case '@':
        switch (*++m) {
          default:  return (t) { needmore, ID_INSTANCE, 1, };
          case '@': return (t) { needmore, ID_CLASS,    2, };
        }

      case '<':
        switch (*++m) {
          default:  return (t) { stophere, ID_JUNK, 1, };
          case '<': return (t) { stophere, ID_JUNK, 2, };
          case '=':
            switch (*++m) {
              default:  return (t) { stophere, ID_JUNK, 2, };
              case '>': return (t) { stophere, ID_JUNK, 3, };
            }
        }

      case '>':
        switch (*++m) {
          default:            return (t) { stophere, ID_JUNK, 1, };
          case '>': case '=': return (t) { stophere, ID_JUNK, 2, };
        }

      case '=':
        switch (*++m) {
          default:  return (t) { invalid,  0,       1, };
          case '~': return (t) { stophere, ID_JUNK, 2, };
          case '=':
            switch (*++m) {
              default:  return (t) { stophere, ID_JUNK, 2, };
              case '=': return (t) { stophere, ID_JUNK, 3, };
            }
        }

      case '*':
        switch (*++m) {
          default:  return (t) { stophere, ID_JUNK, 1, };
          case '*': return (t) { stophere, ID_JUNK, 2, };
        }

      case '+': case '-':
        switch (*++m) {
          default:  return (t) { stophere, ID_JUNK, 1, };
          case '@': return (t) { stophere, ID_JUNK, 2, };
        }

      case '|': case '^': case '&': case '/': case '%': case '~': case '`':
        return (t) { stophere, ID_JUNK, 1, };

      case '[':
        switch (*++m) {
          default: return (t) { needmore, ID_JUNK, 0, };
          case ']':
            switch (*++m) {
              default:  return (t) { stophere, ID_JUNK, 2, };
              case '=': return (t) { stophere, ID_JUNK, 3, };
            }
        }

      case '!':
        switch (*++m) {
          case '=': case '~': return (t) { stophere, ID_JUNK, 2, };
          default:
            if (allowed_attrset & (1U << ID_JUNK)) {
                return (t) { needmore, ID_JUNK, 1, };
            }
            else {
                return (t) { stophere, ID_JUNK, 1, };
            }
        }

      default:
        if (rb_sym_constant_char_p(name, len, enc)) {
            return (t) { needmore, ID_CONST, 0, };
        }
        else {
            return (t) { needmore, ID_LOCAL, 0, };
        }
    }
}
#undef t

int
rb_enc_symname_type(const char *name, long len, rb_encoding *enc, unsigned int allowed_attrset)
{
    const struct enc_synmane_type_leading_chars_tag f =
        enc_synmane_type_leading_chars(name, len, enc, allowed_attrset);
    const char *m = name + f.nread;
    const char *e = name + len;
    int type = (int)f.type;

    switch (f.kind) {
      case invalid:  return -1;
      case stophere: break;
      case needmore:

        if (m >= e || (*m != '_' && !ISALPHA(*m) && ISASCII(*m))) {
            if (len > 1 && *(e-1) == '=') {
                type = rb_enc_symname_type(name, len-1, enc, allowed_attrset);
                if (allowed_attrset & (1U << type)) return ID_ATTRSET;
            }
            return -1;
        }
        while (m < e && is_identchar(m, e, enc)) m += rb_enc_mbclen(m, e, enc);
        if (m >= e) break;
        switch (*m) {
          case '!': case '?':
            if (type == ID_GLOBAL || type == ID_CLASS || type == ID_INSTANCE) return -1;
            type = ID_JUNK;
            ++m;
            if (m + 1 < e || *m != '=') break;
            /* fall through */
          case '=':
            if (!(allowed_attrset & (1U << type))) return -1;
            type = ID_ATTRSET;
            ++m;
            break;
        }
    }

    return m == e ? type : -1;
}

int
rb_enc_symname2_p(const char *name, long len, rb_encoding *enc)
{
    return rb_enc_symname_type(name, len, enc, IDSET_ATTRSET_FOR_SYNTAX) != -1;
}

static int
rb_str_symname_type(VALUE name, unsigned int allowed_attrset)
{
    const char *ptr = StringValuePtr(name);
    long len = RSTRING_LEN(name);
    int type = rb_enc_symname_type(ptr, len, rb_enc_get(name), allowed_attrset);
    RB_GC_GUARD(name);
    return type;
}

static void
set_id_entry(rb_symbols_t *symbols, rb_id_serial_t num, VALUE str, VALUE sym)
{
    ASSERT_vm_locking();
    size_t idx = num / ID_ENTRY_UNIT;

    VALUE ary, ids = symbols->ids;
    if (idx >= (size_t)RARRAY_LEN(ids) || NIL_P(ary = rb_ary_entry(ids, (long)idx))) {
        ary = rb_ary_hidden_new(ID_ENTRY_UNIT * ID_ENTRY_SIZE);
        rb_ary_store(ids, (long)idx, ary);
    }
    idx = (num % ID_ENTRY_UNIT) * ID_ENTRY_SIZE;
    rb_ary_store(ary, (long)idx + ID_ENTRY_STR, str);
    rb_ary_store(ary, (long)idx + ID_ENTRY_SYM, sym);
}

static VALUE
get_id_serial_entry(rb_id_serial_t num, ID id, const enum id_entry_type t)
{
    VALUE result = 0;

    GLOBAL_SYMBOLS_ENTER(symbols);
    {
        if (num && num <= symbols->last_id) {
            size_t idx = num / ID_ENTRY_UNIT;
            VALUE ids = symbols->ids;
            VALUE ary;
            if (idx < (size_t)RARRAY_LEN(ids) && !NIL_P(ary = rb_ary_entry(ids, (long)idx))) {
                long pos = (long)(num % ID_ENTRY_UNIT) * ID_ENTRY_SIZE;
                result = rb_ary_entry(ary, pos + t);

                if (NIL_P(result)) {
                    result = 0;
                }
                else if (CHECK_ID_SERIAL) {
                    if (id) {
                        VALUE sym = result;
                        if (t != ID_ENTRY_SYM)
                          sym = rb_ary_entry(ary, pos + ID_ENTRY_SYM);
                        if (STATIC_SYM_P(sym)) {
                            if (STATIC_SYM2ID(sym) != id) result = 0;
                        }
                        else {
                            if (RSYMBOL(sym)->id != id) result = 0;
                        }
                    }
                }
            }
        }
    }
    GLOBAL_SYMBOLS_LEAVE();

    return result;
}

static VALUE
get_id_entry(ID id, const enum id_entry_type t)
{
    return get_id_serial_entry(rb_id_to_serial(id), id, t);
}

int
rb_static_id_valid_p(ID id)
{
    return STATIC_ID2SYM(id) == get_id_entry(id, ID_ENTRY_SYM);
}

static inline ID
rb_id_serial_to_id(rb_id_serial_t num)
{
    if (is_notop_id((ID)num)) {
        VALUE sym = get_id_serial_entry(num, 0, ID_ENTRY_SYM);
        if (sym) return SYM2ID(sym);
        return ((ID)num << ID_SCOPE_SHIFT) | ID_INTERNAL | ID_STATIC_SYM;
    }
    else {
        return (ID)num;
    }
}

static int
register_sym_update_callback(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    if (existing) {
        rb_fatal("symbol :% "PRIsVALUE" is already registered with %"PRIxVALUE,
                 (VALUE)*key, (VALUE)*value);
    }
    *value = arg;
    return ST_CONTINUE;
}

static void
register_sym(rb_symbols_t *symbols, VALUE str, VALUE sym)
{
    ASSERT_vm_locking();

    if (SYMBOL_DEBUG) {
        st_update(symbols->str_sym, (st_data_t)str,
                  register_sym_update_callback, (st_data_t)sym);
    }
    else {
        st_add_direct(symbols->str_sym, (st_data_t)str, (st_data_t)sym);
    }
}

void
rb_free_static_symid_str(void)
{
    GLOBAL_SYMBOLS_ENTER(symbols)
    {
        st_free_table(symbols->str_sym);
    }
    GLOBAL_SYMBOLS_LEAVE();
}

static void
unregister_sym(rb_symbols_t *symbols, VALUE str, VALUE sym)
{
    ASSERT_vm_locking();

    st_data_t str_data = (st_data_t)str;
    if (!st_delete(symbols->str_sym, &str_data, NULL)) {
        rb_bug("%p can't remove str from str_id (%s)", (void *)sym, RSTRING_PTR(str));
    }
}

static ID
register_static_symid(ID id, const char *name, long len, rb_encoding *enc)
{
    VALUE str = rb_enc_str_new(name, len, enc);
    return register_static_symid_str(id, str);
}

static ID
register_static_symid_str(ID id, VALUE str)
{
    rb_id_serial_t num = rb_id_to_serial(id);
    VALUE sym = STATIC_ID2SYM(id);

    OBJ_FREEZE(str);
    str = rb_fstring(str);

    RUBY_DTRACE_CREATE_HOOK(SYMBOL, RSTRING_PTR(str));

    GLOBAL_SYMBOLS_ENTER(symbols)
    {
        register_sym(symbols, str, sym);
        set_id_entry(symbols, num, str, sym);
    }
    GLOBAL_SYMBOLS_LEAVE();

    return id;
}

static int
sym_check_asciionly(VALUE str, bool fake_str)
{
    if (!rb_enc_asciicompat(rb_enc_get(str))) return FALSE;
    switch (rb_enc_str_coderange(str)) {
      case ENC_CODERANGE_BROKEN:
        if (fake_str) {
            str = rb_enc_str_new(RSTRING_PTR(str), RSTRING_LEN(str), rb_enc_get(str));
        }
        rb_raise(rb_eEncodingError, "invalid symbol in encoding %s :%+"PRIsVALUE,
                 rb_enc_name(rb_enc_get(str)), str);
      case ENC_CODERANGE_7BIT:
        return TRUE;
    }
    return FALSE;
}

#if 0
/*
 * _str_ itself will be registered at the global symbol table.  _str_
 * can be modified before the registration, since the encoding will be
 * set to ASCII-8BIT if it is a special global name.
 */

static inline void
must_be_dynamic_symbol(VALUE x)
{
    if (UNLIKELY(!DYNAMIC_SYM_P(x))) {
        if (STATIC_SYM_P(x)) {
            VALUE str = lookup_id_str(RSHIFT((unsigned long)(x),RUBY_SPECIAL_SHIFT));

            if (str) {
                rb_bug("wrong argument: %s (inappropriate Symbol)", RSTRING_PTR(str));
            }
            else {
                rb_bug("wrong argument: inappropriate Symbol (%p)", (void *)x);
            }
        }
        else {
            rb_bug("wrong argument type %s (expected Symbol)", rb_builtin_class_name(x));
        }
    }
}
#endif

static VALUE
dsymbol_alloc(rb_symbols_t *symbols, const VALUE klass, const VALUE str, rb_encoding * const enc, const ID type)
{
    ASSERT_vm_locking();

    NEWOBJ_OF(obj, struct RSymbol, klass, T_SYMBOL | FL_WB_PROTECTED, sizeof(struct RSymbol), 0);

    long hashval;

    rb_enc_set_index((VALUE)obj, rb_enc_to_index(enc));
    OBJ_FREEZE((VALUE)obj);
    RB_OBJ_WRITE((VALUE)obj, &obj->fstr, str);
    obj->id = type;

    /* we want hashval to be in Fixnum range [ruby-core:15713] r15672 */
    hashval = (long)rb_str_hash(str);
    obj->hashval = RSHIFT((long)hashval, 1);
    register_sym(symbols, str, (VALUE)obj);
    rb_hash_aset(symbols->dsymbol_fstr_hash, str, Qtrue);
    RUBY_DTRACE_CREATE_HOOK(SYMBOL, RSTRING_PTR(obj->fstr));

    return (VALUE)obj;
}

static inline VALUE
dsymbol_check(rb_symbols_t *symbols, const VALUE sym)
{
    ASSERT_vm_locking();

    if (UNLIKELY(rb_objspace_garbage_object_p(sym))) {
        const VALUE fstr = RSYMBOL(sym)->fstr;
        const ID type = RSYMBOL(sym)->id & ID_SCOPE_MASK;
        RSYMBOL(sym)->fstr = 0;
        unregister_sym(symbols, fstr, sym);
        return dsymbol_alloc(symbols, rb_cSymbol, fstr, rb_enc_get(fstr), type);
    }
    else {
        return sym;
    }
}

static ID
lookup_str_id(VALUE str)
{
    st_data_t sym_data;
    int found;

    GLOBAL_SYMBOLS_ENTER(symbols);
    {
        found = st_lookup(symbols->str_sym, (st_data_t)str, &sym_data);
    }
    GLOBAL_SYMBOLS_LEAVE();

    if (found) {
        const VALUE sym = (VALUE)sym_data;

        if (STATIC_SYM_P(sym)) {
            return STATIC_SYM2ID(sym);
        }
        else if (DYNAMIC_SYM_P(sym)) {
            ID id = RSYMBOL(sym)->id;
            if (id & ~ID_SCOPE_MASK) return id;
        }
        else {
            rb_bug("non-symbol object %s:%"PRIxVALUE" for %"PRIsVALUE" in symbol table",
                   rb_builtin_class_name(sym), sym, str);
        }
    }
    return (ID)0;
}

static VALUE
lookup_str_sym_with_lock(rb_symbols_t *symbols, const VALUE str)
{
    st_data_t sym_data;
    if (st_lookup(symbols->str_sym, (st_data_t)str, &sym_data)) {
        VALUE sym = (VALUE)sym_data;
        if (DYNAMIC_SYM_P(sym)) {
            sym = dsymbol_check(symbols, sym);
        }
        return sym;
    }
    else {
        return Qfalse;
    }
}

static VALUE
lookup_str_sym(const VALUE str)
{
    VALUE sym;

    GLOBAL_SYMBOLS_ENTER(symbols);
    {
        sym = lookup_str_sym_with_lock(symbols, str);
    }
    GLOBAL_SYMBOLS_LEAVE();

    return sym;
}

static VALUE
lookup_id_str(ID id)
{
    return get_id_entry(id, ID_ENTRY_STR);
}

ID
rb_intern3(const char *name, long len, rb_encoding *enc)
{
    VALUE sym;
    struct RString fake_str;
    VALUE str = rb_setup_fake_str(&fake_str, name, len, enc);
    OBJ_FREEZE(str);
    sym = lookup_str_sym(str);
    if (sym) return rb_sym2id(sym);
    str = rb_enc_str_new(name, len, enc); /* make true string */
    return intern_str(str, 1);
}

static ID
next_id_base_with_lock(rb_symbols_t *symbols)
{
    ID id;
    rb_id_serial_t next_serial = symbols->last_id + 1;

    if (next_serial == 0) {
        id = (ID)-1;
    }
    else {
        const size_t num = ++symbols->last_id;
        id = num << ID_SCOPE_SHIFT;
    }

    return id;
}

static ID
next_id_base(void)
{
    ID id;
    GLOBAL_SYMBOLS_ENTER(symbols);
    {
        id = next_id_base_with_lock(symbols);
    }
    GLOBAL_SYMBOLS_LEAVE();
    return id;
}

static ID
intern_str(VALUE str, int mutable)
{
    ID id;
    ID nid;

    id = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);
    if (id == (ID)-1) id = ID_JUNK;
    if (sym_check_asciionly(str, false)) {
        if (!mutable) str = rb_str_dup(str);
        rb_enc_associate(str, rb_usascii_encoding());
    }
    if ((nid = next_id_base()) == (ID)-1) {
        str = rb_str_ellipsize(str, 20);
        rb_raise(rb_eRuntimeError, "symbol table overflow (symbol %"PRIsVALUE")",
                 str);
    }
    id |= nid;
    id |= ID_STATIC_SYM;
    return register_static_symid_str(id, str);
}

ID
rb_intern2(const char *name, long len)
{
    return rb_intern3(name, len, rb_usascii_encoding());
}

#undef rb_intern
ID
rb_intern(const char *name)
{
    return rb_intern2(name, strlen(name));
}

ID
rb_intern_str(VALUE str)
{
    VALUE sym = lookup_str_sym(str);

    if (sym) {
        return SYM2ID(sym);
    }

    return intern_str(str, 0);
}

void
rb_gc_free_dsymbol(VALUE sym)
{
#if USE_MMTK
    if (rb_mmtk_enabled_p()) {
        // With MMTk, we handle global symbol table during weak ref processing.
        // So we don't need to unregister symbols when they are dead.
        rb_bug("obj_free is not needed for symbols.");
    }
#endif
    VALUE str = RSYMBOL(sym)->fstr;

    if (str) {
        RSYMBOL(sym)->fstr = 0;

        GLOBAL_SYMBOLS_ENTER(symbols);
        {
            unregister_sym(symbols, str, sym);
            rb_hash_delete_entry(symbols->dsymbol_fstr_hash, str);
        }
        GLOBAL_SYMBOLS_LEAVE();
    }
}

/*
 *  call-seq:
 *     str.intern   -> symbol
 *     str.to_sym   -> symbol
 *
 *  Returns the +Symbol+ corresponding to <i>str</i>, creating the
 *  symbol if it did not previously exist. See Symbol#id2name.
 *
 *     "Koala".intern         #=> :Koala
 *     s = 'cat'.to_sym       #=> :cat
 *     s == :cat              #=> true
 *     s = '@cat'.to_sym      #=> :@cat
 *     s == :@cat             #=> true
 *
 *  This can also be used to create symbols that cannot be represented using the
 *  <code>:xxx</code> notation.
 *
 *     'cat and dog'.to_sym   #=> :"cat and dog"
 */

VALUE
rb_str_intern(VALUE str)
{
    VALUE sym;

    GLOBAL_SYMBOLS_ENTER(symbols);
    {
        sym = lookup_str_sym_with_lock(symbols, str);

        if (sym) {
            // ok
        }
        else if (USE_SYMBOL_GC) {
            rb_encoding *enc = rb_enc_get(str);
            rb_encoding *ascii = rb_usascii_encoding();
            if (enc != ascii && sym_check_asciionly(str, false)) {
                str = rb_str_dup(str);
                rb_enc_associate(str, ascii);
                OBJ_FREEZE(str);
                enc = ascii;
            }
            else {
                str = rb_str_dup(str);
                OBJ_FREEZE(str);
            }
            str = rb_fstring(str);
            int type = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);
            if (type < 0) type = ID_JUNK;
            sym = dsymbol_alloc(symbols, rb_cSymbol, str, enc, type);
        }
        else {
            ID id = intern_str(str, 0);
            sym = ID2SYM(id);
        }
    }
    GLOBAL_SYMBOLS_LEAVE();
    return sym;
}

ID
rb_sym2id(VALUE sym)
{
    ID id;
    if (STATIC_SYM_P(sym)) {
        id = STATIC_SYM2ID(sym);
    }
    else if (DYNAMIC_SYM_P(sym)) {
        GLOBAL_SYMBOLS_ENTER(symbols);
        {
            sym = dsymbol_check(symbols, sym);
            id = RSYMBOL(sym)->id;

            if (UNLIKELY(!(id & ~ID_SCOPE_MASK))) {
                VALUE fstr = RSYMBOL(sym)->fstr;
                ID num = next_id_base_with_lock(symbols);

                RSYMBOL(sym)->id = id |= num;
                /* make it permanent object */

#if USE_MMTK
                if (rb_mmtk_enabled_p()) {
                    // Symbols with associated ID are implicitly pinned (see gc_is_moveable_obj).
                    // When using MMTk, we need to inform MMTk not to move the object.
                    mmtk_pin_object((MMTk_ObjectReference)sym);
                }
#endif

                set_id_entry(symbols, rb_id_to_serial(num), fstr, sym);
                rb_hash_delete_entry(symbols->dsymbol_fstr_hash, fstr);
            }
        }
        GLOBAL_SYMBOLS_LEAVE();
#if USE_MMTK && RUBY_DEBUG
        if (rb_mmtk_enabled_p()) {
            // Assert that all dynamic symbols returned from this function are pinned.
            RUBY_ASSERT(mmtk_is_pinned((MMTk_ObjectReference)sym));
        }
#endif
    }
    else {
        rb_raise(rb_eTypeError, "wrong argument type %s (expected Symbol)",
                 rb_builtin_class_name(sym));
    }
    return id;
}

#undef rb_id2sym
VALUE
rb_id2sym(ID x)
{
    if (!DYNAMIC_ID_P(x)) return STATIC_ID2SYM(x);
    return get_id_entry(x, ID_ENTRY_SYM);
}

/*
 *  call-seq:
 *    name -> string
 *
 *  Returns a frozen string representation of +self+ (not including the leading colon):
 *
 *    :foo.name         # => "foo"
 *    :foo.name.frozen? # => true
 *
 *  Related: Symbol#to_s, Symbol#inspect.
 */

VALUE
rb_sym2str(VALUE sym)
{
    if (DYNAMIC_SYM_P(sym)) {
        return RSYMBOL(sym)->fstr;
    }
    else {
        return rb_id2str(STATIC_SYM2ID(sym));
    }
}

VALUE
rb_id2str(ID id)
{
    return lookup_id_str(id);
}

const char *
rb_id2name(ID id)
{
    VALUE str = rb_id2str(id);

    if (!str) return 0;
    return RSTRING_PTR(str);
}

ID
rb_make_internal_id(void)
{
    return next_id_base() | ID_INTERNAL | ID_STATIC_SYM;
}

ID
rb_make_temporary_id(size_t n)
{
    const ID max_id = RB_ID_SERIAL_MAX & ~0xffff;
    const ID id = max_id - (ID)n;
    if (id <= ruby_global_symbols.last_id) {
        rb_raise(rb_eRuntimeError, "too big to make temporary ID: %" PRIdSIZE, n);
    }
    return (id << ID_SCOPE_SHIFT) | ID_STATIC_SYM | ID_INTERNAL;
}

static int
symbols_i(st_data_t key, st_data_t value, st_data_t arg)
{
    VALUE ary = (VALUE)arg;
    VALUE sym = (VALUE)value;

    if (STATIC_SYM_P(sym)) {
        rb_ary_push(ary, sym);
        return ST_CONTINUE;
    }
    else if (!DYNAMIC_SYM_P(sym)) {
        rb_bug("invalid symbol: %s", RSTRING_PTR((VALUE)key));
    }
    else if (!SYMBOL_PINNED_P(sym) && rb_objspace_garbage_object_p(sym)) {
        RSYMBOL(sym)->fstr = 0;
        return ST_DELETE;
    }
    else {
        rb_ary_push(ary, sym);
        return ST_CONTINUE;
    }

}

VALUE
rb_sym_all_symbols(void)
{
    VALUE ary;

    GLOBAL_SYMBOLS_ENTER(symbols);
    {
        ary = rb_ary_new2(symbols->str_sym->num_entries);
        st_foreach(symbols->str_sym, symbols_i, ary);
    }
    GLOBAL_SYMBOLS_LEAVE();

    return ary;
}

size_t
rb_sym_immortal_count(void)
{
    return (size_t)ruby_global_symbols.last_id;
}

int
rb_is_const_id(ID id)
{
    return is_const_id(id);
}

int
rb_is_class_id(ID id)
{
    return is_class_id(id);
}

int
rb_is_global_id(ID id)
{
    return is_global_id(id);
}

int
rb_is_instance_id(ID id)
{
    return is_instance_id(id);
}

int
rb_is_attrset_id(ID id)
{
    return is_attrset_id(id);
}

int
rb_is_local_id(ID id)
{
    return is_local_id(id);
}

int
rb_is_junk_id(ID id)
{
    return is_junk_id(id);
}

int
rb_is_const_sym(VALUE sym)
{
    return is_const_sym(sym);
}

int
rb_is_attrset_sym(VALUE sym)
{
    return is_attrset_sym(sym);
}

ID
rb_check_id(volatile VALUE *namep)
{
    VALUE tmp;
    VALUE name = *namep;

    if (STATIC_SYM_P(name)) {
        return STATIC_SYM2ID(name);
    }
    else if (DYNAMIC_SYM_P(name)) {
        if (SYMBOL_PINNED_P(name)) {
            return RSYMBOL(name)->id;
        }
        else {
            *namep = RSYMBOL(name)->fstr;
            return 0;
        }
    }
    else if (!RB_TYPE_P(name, T_STRING)) {
        tmp = rb_check_string_type(name);
        if (NIL_P(tmp)) {
            rb_raise(rb_eTypeError, "%+"PRIsVALUE" is not a symbol nor a string",
                     name);
        }
        name = tmp;
        *namep = name;
    }

    sym_check_asciionly(name, false);

    return lookup_str_id(name);
}

// Used by yjit for handling .send without throwing exceptions
ID
rb_get_symbol_id(VALUE name)
{
    if (STATIC_SYM_P(name)) {
        return STATIC_SYM2ID(name);
    }
    else if (DYNAMIC_SYM_P(name)) {
        if (SYMBOL_PINNED_P(name)) {
            return RSYMBOL(name)->id;
        }
        else {
            return 0;
        }
    }
    else if (RB_TYPE_P(name, T_STRING)) {
        return lookup_str_id(name);
    }
    else {
        return 0;
    }
}


VALUE
rb_check_symbol(volatile VALUE *namep)
{
    VALUE sym;
    VALUE tmp;
    VALUE name = *namep;

    if (STATIC_SYM_P(name)) {
        return name;
    }
    else if (DYNAMIC_SYM_P(name)) {
        if (!SYMBOL_PINNED_P(name)) {
            GLOBAL_SYMBOLS_ENTER(symbols);
            {
                name = dsymbol_check(symbols, name);
            }
            GLOBAL_SYMBOLS_LEAVE();

            *namep = name;
        }
        return name;
    }
    else if (!RB_TYPE_P(name, T_STRING)) {
        tmp = rb_check_string_type(name);
        if (NIL_P(tmp)) {
            rb_raise(rb_eTypeError, "%+"PRIsVALUE" is not a symbol nor a string",
                     name);
        }
        name = tmp;
        *namep = name;
    }

    sym_check_asciionly(name, false);

    if ((sym = lookup_str_sym(name)) != 0) {
        return sym;
    }

    return Qnil;
}

ID
rb_check_id_cstr(const char *ptr, long len, rb_encoding *enc)
{
    struct RString fake_str;
    const VALUE name = rb_setup_fake_str(&fake_str, ptr, len, enc);

    sym_check_asciionly(name, true);

    return lookup_str_id(name);
}

VALUE
rb_check_symbol_cstr(const char *ptr, long len, rb_encoding *enc)
{
    VALUE sym;
    struct RString fake_str;
    const VALUE name = rb_setup_fake_str(&fake_str, ptr, len, enc);

    sym_check_asciionly(name, true);

    if ((sym = lookup_str_sym(name)) != 0) {
        return sym;
    }

    return Qnil;
}

#undef rb_sym_intern_ascii_cstr
#ifdef __clang__
NOINLINE(VALUE rb_sym_intern(const char *ptr, long len, rb_encoding *enc));
#else
FUNC_MINIMIZED(VALUE rb_sym_intern(const char *ptr, long len, rb_encoding *enc));
FUNC_MINIMIZED(VALUE rb_sym_intern_ascii(const char *ptr, long len));
FUNC_MINIMIZED(VALUE rb_sym_intern_ascii_cstr(const char *ptr));
#endif

VALUE
rb_sym_intern(const char *ptr, long len, rb_encoding *enc)
{
    struct RString fake_str;
    const VALUE name = rb_setup_fake_str(&fake_str, ptr, len, enc);
    return rb_str_intern(name);
}

VALUE
rb_sym_intern_ascii(const char *ptr, long len)
{
    return rb_sym_intern(ptr, len, rb_usascii_encoding());
}

VALUE
rb_sym_intern_ascii_cstr(const char *ptr)
{
    return rb_sym_intern_ascii(ptr, strlen(ptr));
}

VALUE
rb_to_symbol_type(VALUE obj)
{
    return rb_convert_type_with_id(obj, T_SYMBOL, "Symbol", idTo_sym);
}

int
rb_is_const_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_CONST;
}

int
rb_is_class_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_CLASS;
}

int
rb_is_instance_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_INSTANCE;
}

int
rb_is_local_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_LOCAL;
}

#include "id_table.c"
#include "symbol.rbinc"
