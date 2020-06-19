/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#include "gc.h"
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

#ifndef USE_SYMBOL_GC
# define USE_SYMBOL_GC 1
#endif
#ifndef SYMBOL_DEBUG
# define SYMBOL_DEBUG 0
#endif
#ifndef CHECK_ID_SERIAL
# define CHECK_ID_SERIAL SYMBOL_DEBUG
#endif

#define SYMBOL_PINNED_P(sym) (RSYMBOL(sym)->id&~ID_SCOPE_MASK)

#define STATIC_SYM2ID(sym) RSHIFT((unsigned long)(sym), RUBY_SPECIAL_SHIFT)

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
#define global_symbols ruby_global_symbols

static const struct st_hash_type symhash = {
    rb_str_hash_cmp,
    rb_str_hash,
};

void
Init_sym(void)
{
    VALUE dsym_fstrs = rb_ident_hash_new();
    global_symbols.dsymbol_fstr_hash = dsym_fstrs;
    rb_gc_register_mark_object(dsym_fstrs);
    rb_obj_hide(dsym_fstrs);

    global_symbols.str_sym = st_init_table_with_size(&symhash, 1000);
    global_symbols.ids = rb_ary_tmp_new(0);
    rb_gc_register_mark_object(global_symbols.ids);

    Init_op_tbl();
    Init_id();
}

WARN_UNUSED_RESULT(static VALUE dsymbol_alloc(const VALUE klass, const VALUE str, rb_encoding *const enc, const ID type));
WARN_UNUSED_RESULT(static VALUE dsymbol_check(const VALUE sym));
WARN_UNUSED_RESULT(static ID lookup_str_id(VALUE str));
WARN_UNUSED_RESULT(static VALUE lookup_str_sym(const VALUE str));
WARN_UNUSED_RESULT(static VALUE lookup_id_str(ID id));
WARN_UNUSED_RESULT(static ID intern_str(VALUE str, int mutable));

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
    if (ONIGENC_IS_UNICODE(enc)) {
	static int ctype_titlecase = 0;
	if (rb_enc_isupper(c, enc)) return TRUE;
	if (rb_enc_islower(c, enc)) return FALSE;
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

int
rb_enc_symname_type(const char *name, long len, rb_encoding *enc, unsigned int allowed_attrset)
{
    const char *m = name;
    const char *e = m + len;
    int type = ID_JUNK;

    if (!rb_enc_asciicompat(enc)) return -1;
    if (!m || len <= 0) return -1;
    switch (*m) {
      case '\0':
	return -1;

      case '$':
	type = ID_GLOBAL;
	if (is_special_global_name(++m, e, enc)) return type;
	goto id;

      case '@':
	type = ID_INSTANCE;
	if (*++m == '@') {
	    ++m;
	    type = ID_CLASS;
	}
	goto id;

      case '<':
	switch (*++m) {
	  case '<': ++m; break;
	  case '=': if (*++m == '>') ++m; break;
	  default: break;
	}
	break;

      case '>':
	switch (*++m) {
	  case '>': case '=': ++m; break;
	}
	break;

      case '=':
	switch (*++m) {
	  case '~': ++m; break;
	  case '=': if (*++m == '=') ++m; break;
	  default: return -1;
	}
	break;

      case '*':
	if (*++m == '*') ++m;
	break;

      case '+': case '-':
	if (*++m == '@') ++m;
	break;

      case '|': case '^': case '&': case '/': case '%': case '~': case '`':
	++m;
	break;

      case '[':
	if (m[1] != ']') goto id;
	++m;
	if (*++m == '=') ++m;
	break;

      case '!':
	if (len == 1) return ID_JUNK;
	switch (*++m) {
	  case '=': case '~': ++m; break;
	  default:
	    if (allowed_attrset & (1U << ID_JUNK)) goto id;
	    return -1;
	}
	break;

      default:
	type = rb_sym_constant_char_p(m, e-m, enc) ? ID_CONST : ID_LOCAL;
        goto id;
    }
    goto stophere;

  id:
    if (m >= e || (*m != '_' && !ISALPHA(*m) && ISASCII(*m))) {
        if (len > 1 && *(e-1) == '=') {
            type = rb_enc_symname_type(name, len-1, enc, allowed_attrset);
            if (type != ID_ATTRSET) return ID_ATTRSET;
        }
        return -1;
    }
    while (m < e && is_identchar(m, e, enc)) m += rb_enc_mbclen(m, e, enc);
    if (m >= e) goto stophere;
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

  stophere:
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
set_id_entry(rb_id_serial_t num, VALUE str, VALUE sym)
{
    size_t idx = num / ID_ENTRY_UNIT;
    VALUE ary, ids = global_symbols.ids;
    if (idx >= (size_t)RARRAY_LEN(ids) || NIL_P(ary = rb_ary_entry(ids, (long)idx))) {
	ary = rb_ary_tmp_new(ID_ENTRY_UNIT * ID_ENTRY_SIZE);
	rb_ary_store(ids, (long)idx, ary);
    }
    idx = (num % ID_ENTRY_UNIT) * ID_ENTRY_SIZE;
    rb_ary_store(ary, (long)idx + ID_ENTRY_STR, str);
    rb_ary_store(ary, (long)idx + ID_ENTRY_SYM, sym);
}

static VALUE
get_id_serial_entry(rb_id_serial_t num, ID id, const enum id_entry_type t)
{
    if (num && num <= global_symbols.last_id) {
	size_t idx = num / ID_ENTRY_UNIT;
	VALUE ids = global_symbols.ids;
	VALUE ary;
	if (idx < (size_t)RARRAY_LEN(ids) && !NIL_P(ary = rb_ary_entry(ids, (long)idx))) {
            long pos = (long)(num % ID_ENTRY_UNIT) * ID_ENTRY_SIZE;
            VALUE result = rb_ary_entry(ary, pos + t);
            if (NIL_P(result)) return 0;
#if CHECK_ID_SERIAL
            if (id) {
                VALUE sym = result;
                if (t != ID_ENTRY_SYM)
                    sym = rb_ary_entry(ary, pos + ID_ENTRY_SYM);
                if (STATIC_SYM_P(sym)) {
                    if (STATIC_SYM2ID(sym) != id) return 0;
                }
                else {
                    if (RSYMBOL(sym)->id != id) return 0;
                }
            }
#endif
            return result;
	}
    }
    return 0;
}

static VALUE
get_id_entry(ID id, const enum id_entry_type t)
{
    return get_id_serial_entry(rb_id_to_serial(id), id, t);
}

static inline ID
#ifdef __GNUC__
__attribute__((unused))
#endif
rb_id_serial_to_id(rb_id_serial_t num)
{
    if (is_notop_id((ID)num)) {
        VALUE sym = get_id_serial_entry(num, 0, ID_ENTRY_SYM);
	return SYM2ID(sym);
    }
    else {
	return (ID)num;
    }
}

#if SYMBOL_DEBUG
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
#endif

static void
register_sym(VALUE str, VALUE sym)
{
#if SYMBOL_DEBUG
    st_update(global_symbols.str_sym, (st_data_t)str,
	      register_sym_update_callback, (st_data_t)sym);
#else
    st_add_direct(global_symbols.str_sym, (st_data_t)str, (st_data_t)sym);
#endif
}

static void
unregister_sym(VALUE str, VALUE sym)
{
    st_data_t str_data = (st_data_t)str;
    if (!st_delete(global_symbols.str_sym, &str_data, NULL)) {
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

    register_sym(str, sym);
    set_id_entry(num, str, sym);

    return id;
}

static int
sym_check_asciionly(VALUE str)
{
    if (!rb_enc_asciicompat(rb_enc_get(str))) return FALSE;
    switch (rb_enc_str_coderange(str)) {
      case ENC_CODERANGE_BROKEN:
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
dsymbol_alloc(const VALUE klass, const VALUE str, rb_encoding * const enc, const ID type)
{
    const VALUE dsym = rb_newobj_of(klass, T_SYMBOL | FL_WB_PROTECTED);
    long hashval;

    rb_enc_set_index(dsym, rb_enc_to_index(enc));
    OBJ_FREEZE(dsym);
    RB_OBJ_WRITE(dsym, &RSYMBOL(dsym)->fstr, str);
    RSYMBOL(dsym)->id = type;

    /* we want hashval to be in Fixnum range [ruby-core:15713] r15672 */
    hashval = (long)rb_str_hash(str);
    RSYMBOL(dsym)->hashval = RSHIFT((long)hashval, 1);

    register_sym(str, dsym);
    rb_hash_aset(global_symbols.dsymbol_fstr_hash, str, Qtrue);

    RUBY_DTRACE_CREATE_HOOK(SYMBOL, RSTRING_PTR(RSYMBOL(dsym)->fstr));

    return dsym;
}

static inline VALUE
dsymbol_check(const VALUE sym)
{
    if (UNLIKELY(rb_objspace_garbage_object_p(sym))) {
	const VALUE fstr = RSYMBOL(sym)->fstr;
	const ID type = RSYMBOL(sym)->id & ID_SCOPE_MASK;
	RSYMBOL(sym)->fstr = 0;

	unregister_sym(fstr, sym);
	return dsymbol_alloc(rb_cSymbol, fstr, rb_enc_get(fstr), type);
    }
    else {
	return sym;
    }
}

static ID
lookup_str_id(VALUE str)
{
    st_data_t sym_data;
    if (st_lookup(global_symbols.str_sym, (st_data_t)str, &sym_data)) {
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
lookup_str_sym(const VALUE str)
{
    st_data_t sym_data;
    if (st_lookup(global_symbols.str_sym, (st_data_t)str, &sym_data)) {
	VALUE sym = (VALUE)sym_data;

	if (DYNAMIC_SYM_P(sym)) {
	    sym = dsymbol_check(sym);
	}
	return sym;
    }
    else {
	return (VALUE)0;
    }
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
next_id_base(void)
{
    rb_id_serial_t next_serial = global_symbols.last_id + 1;

    if (next_serial == 0) {
	return (ID)-1;
    }
    else {
	const size_t num = ++global_symbols.last_id;
	return num << ID_SCOPE_SHIFT;
    }
}

static ID
intern_str(VALUE str, int mutable)
{
    ID id;
    ID nid;

    id = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);
    if (id == (ID)-1) id = ID_JUNK;
    if (sym_check_asciionly(str)) {
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
    VALUE str = RSYMBOL(sym)->fstr;

    if (str) {
	RSYMBOL(sym)->fstr = 0;
	unregister_sym(str, sym);
	rb_hash_delete_entry(global_symbols.dsymbol_fstr_hash, str);
    }
}

/*
 *  call-seq:
 *     str.intern   -> symbol
 *     str.to_sym   -> symbol
 *
 *  Returns the Symbol corresponding to <i>str</i>, creating the
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
#if USE_SYMBOL_GC
    rb_encoding *enc, *ascii;
    int type;
#else
    ID id;
#endif
    VALUE sym = lookup_str_sym(str);

    if (sym) {
	return sym;
    }

#if USE_SYMBOL_GC
    enc = rb_enc_get(str);
    ascii = rb_usascii_encoding();
    if (enc != ascii && sym_check_asciionly(str)) {
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
    type = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);
    if (type < 0) type = ID_JUNK;
    return dsymbol_alloc(rb_cSymbol, str, enc, type);
#else
    id = intern_str(str, 0);
    return ID2SYM(id);
#endif
}

ID
rb_sym2id(VALUE sym)
{
    ID id;
    if (STATIC_SYM_P(sym)) {
	id = STATIC_SYM2ID(sym);
    }
    else if (DYNAMIC_SYM_P(sym)) {
	sym = dsymbol_check(sym);
	id = RSYMBOL(sym)->id;
	if (UNLIKELY(!(id & ~ID_SCOPE_MASK))) {
	    VALUE fstr = RSYMBOL(sym)->fstr;
	    ID num = next_id_base();

	    RSYMBOL(sym)->id = id |= num;
	    /* make it permanent object */
	    set_id_entry(rb_id_to_serial(num), fstr, sym);
	    rb_hash_delete_entry(global_symbols.dsymbol_fstr_hash, fstr);
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
    VALUE ary = rb_ary_new2(global_symbols.str_sym->num_entries);
    st_foreach(global_symbols.str_sym, symbols_i, ary);
    return ary;
}

size_t
rb_sym_immortal_count(void)
{
    return (size_t)global_symbols.last_id;
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

/**
 * Returns ID for the given name if it is interned already, or 0.
 *
 * \param namep   the pointer to the name object
 * \return        the ID for *namep
 * \pre           the object referred by \p namep must be a Symbol or
 *                a String, or possible to convert with to_str method.
 * \post          the object referred by \p namep is a Symbol or a
 *                String if non-zero value is returned, or is a String
 *                if 0 is returned.
 */
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

    sym_check_asciionly(name);

    return lookup_str_id(name);
}

/**
 * Returns Symbol for the given name if it is interned already, or
 * nil.
 *
 * \param namep   the pointer to the name object
 * \return        the Symbol for *namep
 * \pre           the object referred by \p namep must be a Symbol or
 *                a String, or possible to convert with to_str method.
 * \post          the object referred by \p namep is a Symbol or a
 *                String if non-nil value is returned, or is a String
 *                if nil is returned.
 */
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
	    name = dsymbol_check(name);
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

    sym_check_asciionly(name);

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

    sym_check_asciionly(name);

    return lookup_str_id(name);
}

VALUE
rb_check_symbol_cstr(const char *ptr, long len, rb_encoding *enc)
{
    VALUE sym;
    struct RString fake_str;
    const VALUE name = rb_setup_fake_str(&fake_str, ptr, len, enc);

    sym_check_asciionly(name);

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
