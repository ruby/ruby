/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"
#include "internal/concurrent_set.h"
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
#include "ruby/internal/attr/nonstring.h"

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

#define IDSET_ATTRSET_FOR_SYNTAX ((1U<<ID_LOCAL)|(1U<<ID_CONST))
#define IDSET_ATTRSET_FOR_INTERN (~(~0U<<(1<<ID_SCOPE_SHIFT)) & ~(1U<<ID_ATTRSET))

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


#define GLOBAL_SYMBOLS_LOCKING(symbols) \
    for (rb_symbols_t *symbols = &ruby_global_symbols, **locking = &symbols; \
         locking; \
         locking = NULL) \
        RB_VM_LOCKING()

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

typedef struct {
    rb_id_serial_t last_id;
    VALUE sym_set;

    VALUE ids;
} rb_symbols_t;

rb_symbols_t ruby_global_symbols = {tNEXT_ID-1};

struct sym_set_static_sym_entry {
    VALUE sym;
    VALUE str;
};

#define SYM_SET_SYM_STATIC_TAG 1

static bool
sym_set_sym_static_p(VALUE sym)
{
    return sym & SYM_SET_SYM_STATIC_TAG;
}

static VALUE
sym_set_static_sym_tag(struct sym_set_static_sym_entry *sym)
{
    VALUE value = (VALUE)sym | SYM_SET_SYM_STATIC_TAG;
    RUBY_ASSERT(IMMEDIATE_P(value));
    RUBY_ASSERT(sym_set_sym_static_p(value));

    return value;
}

static struct sym_set_static_sym_entry *
sym_set_static_sym_untag(VALUE sym)
{
    RUBY_ASSERT(sym_set_sym_static_p(sym));

    return (struct sym_set_static_sym_entry *)(sym & ~((VALUE)SYM_SET_SYM_STATIC_TAG));
}

static VALUE
sym_set_sym_get_str(VALUE sym)
{
    VALUE str;
    if (sym_set_sym_static_p(sym)) {
        str = sym_set_static_sym_untag(sym)->str;
    }
    else {
        RUBY_ASSERT(RB_TYPE_P(sym, T_SYMBOL));
        str = RSYMBOL(sym)->fstr;
    }

    RUBY_ASSERT(RB_TYPE_P(str, T_STRING));

    return str;
}

static VALUE
sym_set_hash(VALUE sym)
{
    if (sym_set_sym_static_p(sym)) {
        return (VALUE)rb_str_hash(sym_set_static_sym_untag(sym)->str);
    }
    else {
        return (VALUE)RSYMBOL(sym)->hashval;
    }
}

static bool
sym_set_cmp(VALUE a, VALUE b)
{
    return rb_str_hash_cmp(sym_set_sym_get_str(a), sym_set_sym_get_str(b)) == false;
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

static VALUE
dup_string_for_create(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);

    str = rb_enc_str_new(RSTRING_PTR(str), RSTRING_LEN(str), enc);

    rb_encoding *ascii = rb_usascii_encoding();
    if (enc != ascii && sym_check_asciionly(str, false)) {
        rb_enc_associate(str, ascii);
    }
    OBJ_FREEZE(str);

    str = rb_fstring(str);

    return str;
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
    GLOBAL_SYMBOLS_LOCKING(symbols) {
        id = next_id_base_with_lock(symbols);
    }
    return id;
}

static void
set_id_entry(rb_symbols_t *symbols, rb_id_serial_t num, VALUE str, VALUE sym)
{
    ASSERT_vm_locking();
    RUBY_ASSERT_BUILTIN_TYPE(str, T_STRING);
    RUBY_ASSERT_BUILTIN_TYPE(sym, T_SYMBOL);

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
sym_set_create(VALUE sym, void *data)
{
    bool create_dynamic_symbol = (bool)data;

    struct sym_set_static_sym_entry *static_sym_entry = sym_set_static_sym_untag(sym);

    VALUE str = dup_string_for_create(static_sym_entry->str);

    if (create_dynamic_symbol) {
        NEWOBJ_OF(obj, struct RSymbol, rb_cSymbol, T_SYMBOL | FL_WB_PROTECTED, sizeof(struct RSymbol), 0);

        rb_encoding *enc = rb_enc_get(str);
        rb_enc_set_index((VALUE)obj, rb_enc_to_index(enc));
        OBJ_FREEZE((VALUE)obj);
        RB_OBJ_WRITE((VALUE)obj, &obj->fstr, str);

        int id = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);
        if (id < 0) id = ID_JUNK;
        obj->id = id;

        obj->hashval = rb_str_hash(str);
        RUBY_DTRACE_CREATE_HOOK(SYMBOL, RSTRING_PTR(obj->fstr));

        return (VALUE)obj;
    }
    else {
        struct sym_set_static_sym_entry *new_static_sym_entry = xmalloc(sizeof(struct sym_set_static_sym_entry));
        new_static_sym_entry->str = str;

        VALUE static_sym = static_sym_entry->sym;
        if (static_sym == 0) {
            ID id = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);
            if (id == (ID)-1) id = ID_JUNK;

            ID nid = next_id_base();
            if (nid == (ID)-1) {
                str = rb_str_ellipsize(str, 20);
                rb_raise(rb_eRuntimeError, "symbol table overflow (symbol %"PRIsVALUE")", str);
            }

            id |= nid;
            id |= ID_STATIC_SYM;

            static_sym = STATIC_ID2SYM(id);
        }
        new_static_sym_entry->sym = static_sym;

        RB_VM_LOCKING() {
            set_id_entry(&ruby_global_symbols, rb_id_to_serial(STATIC_SYM2ID(static_sym)), str, static_sym);
        }

        return sym_set_static_sym_tag(new_static_sym_entry);
    }
}

static void
sym_set_free(VALUE sym)
{
    if (sym_set_sym_static_p(sym)) {
        xfree(sym_set_static_sym_untag(sym));
    }
}

static const struct rb_concurrent_set_funcs sym_set_funcs = {
    .hash = sym_set_hash,
    .cmp = sym_set_cmp,
    .create = sym_set_create,
    .free = sym_set_free,
};

static VALUE
sym_set_entry_to_sym(VALUE entry)
{
    if (sym_set_sym_static_p(entry)) {
        RUBY_ASSERT(STATIC_SYM_P(sym_set_static_sym_untag(entry)->sym));

        if (!STATIC_SYM_P(sym_set_static_sym_untag(entry)->sym)) rb_bug("not sym");

        return sym_set_static_sym_untag(entry)->sym;
    }
    else {
        RUBY_ASSERT(DYNAMIC_SYM_P(entry));
        if (!DYNAMIC_SYM_P(entry)) rb_bug("not sym");

        return entry;
    }
}

static VALUE
sym_find_or_insert_dynamic_symbol(rb_symbols_t *symbols, const VALUE str)
{
    struct sym_set_static_sym_entry static_sym = {
        .str = str
    };
    return sym_set_entry_to_sym(
        rb_concurrent_set_find_or_insert(&symbols->sym_set, sym_set_static_sym_tag(&static_sym), (void *)true)
    );
}

static VALUE
sym_find_or_insert_static_symbol(rb_symbols_t *symbols, const VALUE str)
{
    struct sym_set_static_sym_entry static_sym = {
        .str = str
    };
    return sym_set_entry_to_sym(
        rb_concurrent_set_find_or_insert(&symbols->sym_set, sym_set_static_sym_tag(&static_sym), (void *)false)
    );
}

static VALUE
sym_find_or_insert_static_symbol_id(rb_symbols_t *symbols, const VALUE str, ID id)
{
    struct sym_set_static_sym_entry static_sym = {
        .sym = STATIC_ID2SYM(id),
        .str = str,
    };
    return sym_set_entry_to_sym(
        rb_concurrent_set_find_or_insert(&symbols->sym_set, sym_set_static_sym_tag(&static_sym), (void *)false)
    );
}

void
Init_sym(void)
{
    rb_symbols_t *symbols = &ruby_global_symbols;

    symbols->sym_set = rb_concurrent_set_new(&sym_set_funcs, 1024);
    symbols->ids = rb_ary_hidden_new(0);

    Init_op_tbl();
    Init_id();
}

void
rb_sym_global_symbols_mark(void)
{
    rb_symbols_t *symbols = &ruby_global_symbols;

    rb_gc_mark_movable(symbols->sym_set);
    rb_gc_mark_movable(symbols->ids);
}

void
rb_sym_global_symbols_update_references(void)
{
    rb_symbols_t *symbols = &ruby_global_symbols;

    symbols->sym_set = rb_gc_location(symbols->sym_set);
    symbols->ids = rb_gc_location(symbols->ids);
}

WARN_UNUSED_RESULT(static ID lookup_str_id(VALUE str));
WARN_UNUSED_RESULT(static VALUE lookup_id_str(ID id));

ID
rb_id_attrset(ID id)
{
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
                VALUE str = lookup_id_str(id);
                if (str != 0) {
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

    bool error = false;
    GLOBAL_SYMBOLS_LOCKING(symbols) {
        /* make new symbol and ID */
        VALUE str = lookup_id_str(id);
        if (str) {
            str = rb_str_dup(str);
            rb_str_cat(str, "=", 1);
            if (sym_check_asciionly(str, false)) {
                rb_enc_associate(str, rb_usascii_encoding());
            }

            VALUE sym = sym_find_or_insert_static_symbol(symbols, str);
            id = rb_sym2id(sym);
        }
        else {
            error = true;
        }
    }

    if (error) {
        RBIMPL_ATTR_NONSTRING_ARRAY() static const char id_types[][8] = {
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

static VALUE
get_id_serial_entry(rb_id_serial_t num, ID id, const enum id_entry_type t)
{
    VALUE result = 0;

    GLOBAL_SYMBOLS_LOCKING(symbols) {
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

    if (result) {
        switch (t) {
          case ID_ENTRY_STR:
            RUBY_ASSERT_BUILTIN_TYPE(result, T_STRING);
            break;
          case ID_ENTRY_SYM:
            RUBY_ASSERT_BUILTIN_TYPE(result, T_SYMBOL);
            break;
          default:
            break;
        }
    }

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

static ID
register_static_symid(ID id, const char *name, long len, rb_encoding *enc)
{
    VALUE str = rb_enc_str_new(name, len, enc);
    return register_static_symid_str(id, str);
}

static ID
register_static_symid_str(ID id, VALUE str)
{
    OBJ_FREEZE(str);
    str = rb_fstring(str);

    RUBY_DTRACE_CREATE_HOOK(SYMBOL, RSTRING_PTR(str));

    GLOBAL_SYMBOLS_LOCKING(symbols) {
        // TODO: remove this function
        sym_find_or_insert_static_symbol_id(symbols, str, id);
    }

    return id;
}

static VALUE
sym_find(VALUE str)
{
    VALUE sym;

    GLOBAL_SYMBOLS_LOCKING(symbols) {
        struct sym_set_static_sym_entry static_sym = {
            .str = str
        };
        sym = rb_concurrent_set_find(&symbols->sym_set, sym_set_static_sym_tag(&static_sym));
    }

    if (sym) {
        return sym_set_entry_to_sym(sym);
    }
    else {
        return 0;
    }
}

static ID
lookup_str_id(VALUE str)
{
    VALUE sym = sym_find(str);

    if (sym == 0) {
        return (ID)0;
    }

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

    return (ID)0;
}

static VALUE
lookup_id_str(ID id)
{
    return get_id_entry(id, ID_ENTRY_STR);
}

ID
rb_intern3(const char *name, long len, rb_encoding *enc)
{
    struct RString fake_str;
    VALUE str = rb_setup_fake_str(&fake_str, name, len, enc);
    OBJ_FREEZE(str);

    VALUE sym;
    GLOBAL_SYMBOLS_LOCKING(symbols) {
        sym = sym_find_or_insert_static_symbol(symbols, str);
    }
    return rb_sym2id(sym);
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
    VALUE sym;
    GLOBAL_SYMBOLS_LOCKING(symbols) {
        sym = sym_find_or_insert_static_symbol(symbols, str);
    }
    return SYM2ID(sym);
}

bool
rb_obj_is_symbol_table(VALUE obj)
{
    return obj == ruby_global_symbols.sym_set;
}

struct global_symbol_table_foreach_weak_reference_data {
    int (*callback)(VALUE *key, void *data);
    void *data;
};

static int
rb_sym_global_symbol_table_foreach_weak_reference_i(VALUE *key, void *d)
{
    struct global_symbol_table_foreach_weak_reference_data *data = d;
    VALUE sym = *key;

    if (sym_set_sym_static_p(sym)) {
        struct sym_set_static_sym_entry *static_sym = sym_set_static_sym_untag(sym);

        return data->callback(&static_sym->str, data->data);
    }
    else {
        return data->callback(key, data->data);
    }
}

void
rb_sym_global_symbol_table_foreach_weak_reference(int (*callback)(VALUE *key, void *data), void *data)
{
    if (!ruby_global_symbols.sym_set) return;

    struct global_symbol_table_foreach_weak_reference_data foreach_data = {
        .callback = callback,
        .data = data,
    };

    rb_concurrent_set_foreach_with_replace(ruby_global_symbols.sym_set, rb_sym_global_symbol_table_foreach_weak_reference_i, &foreach_data);
}

void
rb_gc_free_dsymbol(VALUE sym)
{
    VALUE str = RSYMBOL(sym)->fstr;

    if (str) {
        GLOBAL_SYMBOLS_LOCKING(symbols) {
            rb_concurrent_set_delete_by_identity(symbols->sym_set, sym);
        }

        RSYMBOL(sym)->fstr = 0;
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
    return sym_find_or_insert_dynamic_symbol(&ruby_global_symbols, str);
}

ID
rb_sym2id(VALUE sym)
{
    ID id = 0;
    if (STATIC_SYM_P(sym)) {
        id = STATIC_SYM2ID(sym);
    }
    else if (DYNAMIC_SYM_P(sym)) {
        GLOBAL_SYMBOLS_LOCKING(symbols) {
            RUBY_ASSERT(!rb_objspace_garbage_object_p(sym));
            id = RSYMBOL(sym)->id;

            if (UNLIKELY(!(id & ~ID_SCOPE_MASK))) {
                VALUE fstr = RSYMBOL(sym)->fstr;
                ID num = next_id_base_with_lock(symbols);

                RSYMBOL(sym)->id = id |= num;
                /* make it permanent object */

                set_id_entry(symbols, rb_id_to_serial(num), fstr, sym);
            }
        }
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
    VALUE str;
    if (DYNAMIC_SYM_P(sym)) {
        str = RSYMBOL(sym)->fstr;
        RUBY_ASSERT_BUILTIN_TYPE(str, T_STRING);
    }
    else {
        str = rb_id2str(STATIC_SYM2ID(sym));
        if (str) RUBY_ASSERT_BUILTIN_TYPE(str, T_STRING);
    }

    return str;
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
symbols_i(VALUE *key, void *data)
{
    VALUE ary = (VALUE)data;
    VALUE sym = (VALUE)*key;

    if (sym_set_sym_static_p(sym)) {
        rb_ary_push(ary, sym_set_static_sym_untag(sym)->sym);
    }
    else if (rb_objspace_garbage_object_p(sym)) {
        return ST_DELETE;
    }
    else {
        rb_ary_push(ary, sym);
    }

    return ST_CONTINUE;
}

VALUE
rb_sym_all_symbols(void)
{
    VALUE ary;

    GLOBAL_SYMBOLS_LOCKING(symbols) {
        ary = rb_ary_new2(rb_concurrent_set_size(symbols->sym_set));
        rb_concurrent_set_foreach_with_replace(symbols->sym_set, symbols_i, (void *)ary);
    }

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
        RUBY_ASSERT(!rb_objspace_garbage_object_p(name));
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

    if ((sym = sym_find(name)) != 0) {
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

    if ((sym = sym_find(name)) != 0) {
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
