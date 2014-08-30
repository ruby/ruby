/**********************************************************************

  symbol.h -

  $Author$
  created at: Tue Jul  8 15:49:54 JST 2014

  Copyright (C) 2014 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/encoding.h"
#include "internal.h"
#include "node.h"
#include "symbol.h"
#include "gc.h"
#include "probes.h"

#define SYMBOL_PINNED        FL_USER1
#define SYMBOL_PINNED_P(sym) FL_TEST((sym), SYMBOL_PINNED)

#define ID_DYNAMIC_SYM_P(id) (!(id&ID_STATIC_SYM)&&id>tLAST_OP_ID)
#define STATIC_SYM2ID(sym) RSHIFT((unsigned long)(sym), RUBY_SPECIAL_SHIFT)
#define STATIC_ID2SYM(id)  (((VALUE)(id)<<RUBY_SPECIAL_SHIFT)|SYMBOL_FLAG)

static ID register_static_symid(ID, const char *, long, rb_encoding *);
static ID register_static_symid_str(ID, VALUE);
#define REGISTER_SYMID(id, name) register_static_symid((id), (name), strlen(name), enc)
#include "id.c"

#define is_identchar(p,e,enc) (rb_enc_isalnum((unsigned char)(*(p)),(enc)) || (*(p)) == '_' || !ISASCII(*(p)))

#define tUPLUS  RUBY_TOKEN(UPLUS)
#define tUMINUS RUBY_TOKEN(UMINUS)
#define tPOW    RUBY_TOKEN(POW)
#define tCMP    RUBY_TOKEN(CMP)
#define tEQ     RUBY_TOKEN(EQ)
#define tEQQ    RUBY_TOKEN(EQQ)
#define tNEQ    RUBY_TOKEN(NEQ)
#define tGEQ    RUBY_TOKEN(GEQ)
#define tLEQ    RUBY_TOKEN(LEQ)
#define tMATCH  RUBY_TOKEN(MATCH)
#define tNMATCH RUBY_TOKEN(NMATCH)
#define tDOT2   RUBY_TOKEN(DOT2)
#define tDOT3   RUBY_TOKEN(DOT3)
#define tAREF   RUBY_TOKEN(AREF)
#define tASET   RUBY_TOKEN(ASET)
#define tLSHFT  RUBY_TOKEN(LSHFT)
#define tRSHFT  RUBY_TOKEN(RSHFT)

static const struct {
    unsigned short token;
    const char name[3], term;
} op_tbl[] = {
    {tDOT2,	".."},
    {tDOT3,	"..."},
    {tPOW,	"**"},
    {tUPLUS,	"+@"},
    {tUMINUS,	"-@"},
    {tCMP,	"<=>"},
    {tGEQ,	">="},
    {tLEQ,	"<="},
    {tEQ,	"=="},
    {tEQQ,	"==="},
    {tNEQ,	"!="},
    {tMATCH,	"=~"},
    {tNMATCH,	"!~"},
    {tAREF,	"[]"},
    {tASET,	"[]="},
    {tLSHFT,	"<<"},
    {tRSHFT,	">>"},
};

#define op_tbl_count numberof(op_tbl)
STATIC_ASSERT(op_tbl_name_size, sizeof(op_tbl[0].name) == 3);
#define op_tbl_len(i) (!op_tbl[i].name[1] ? 1 : !op_tbl[i].name[2] ? 2 : 3)

static struct symbols {
    ID last_id;
    st_table *str_id;
    st_table *id_str;
    VALUE dsymbol_fstr_hash;
} global_symbols = {tNEXT_ID-1};

static const struct st_hash_type symhash = {
    rb_str_hash_cmp,
    rb_str_hash,
};

void
Init_sym(void)
{
    VALUE dsym_fstrs = rb_hash_new();
    global_symbols.dsymbol_fstr_hash = dsym_fstrs;
    rb_gc_register_mark_object(dsym_fstrs);
    rb_obj_hide(dsym_fstrs);

    global_symbols.str_id = st_init_table_with_size(&symhash, 1000);
    global_symbols.id_str = st_init_numtable_with_size(1000);

    Init_id();
}

static ID attrsetname_to_attr(VALUE name);
static VALUE lookup_id_str(ID id);

ID
rb_id_attrset(ID id)
{
    if (!is_notop_id(id)) {
	switch (id) {
	  case tAREF: case tASET:
	    return tASET;	/* only exception */
	}
	rb_name_error(id, "cannot make operator ID :%"PRIsVALUE" attrset",
		      rb_id2str(id));
    }
    else {
	int scope = id_type(id);
	switch (scope) {
	  case ID_LOCAL: case ID_INSTANCE: case ID_GLOBAL:
	  case ID_CONST: case ID_CLASS: case ID_JUNK:
	    break;
	  case ID_ATTRSET:
	    return id;
	  default:
	    {
		VALUE str;
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
    if (id&ID_STATIC_SYM) {
        id &= ~ID_SCOPE_MASK;
        id |= ID_ATTRSET;
    }
    else {
	VALUE str;

        /* make new dynamic symbol */
	str = rb_str_dup(RSYMBOL((VALUE)id)->fstr);
	rb_str_cat(str, "=", 1);
	id = SYM2ID(rb_str_dynamic_intern(str));
    }
    return id;
}

ID
rb_id_attrget(ID id)
{
    return attrsetname_to_attr(rb_id2str(id));
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
	if (!rb_enc_isdigit(*m, enc)) return 0;
	do {
	    if (!ISASCII(*m)) mb = 1;
	    ++m;
	} while (m < e && rb_enc_isdigit(*m, enc));
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

#define IDSET_ATTRSET_FOR_SYNTAX ((1U<<ID_LOCAL)|(1U<<ID_CONST))
#define IDSET_ATTRSET_FOR_INTERN (~(~0U<<(1<<ID_SCOPE_SHIFT)) & ~(1U<<ID_ATTRSET))

static int
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
	if (*++m != ']') return -1;
	if (*++m == '=') ++m;
	break;

      case '!':
	if (len == 1) return ID_JUNK;
	switch (*++m) {
	  case '=': case '~': ++m; break;
	  default: return -1;
	}
	break;

      default:
	type = rb_enc_isupper(*m, enc) ? ID_CONST : ID_LOCAL;
      id:
	if (m >= e || (*m != '_' && !rb_enc_isalpha(*m, enc) && ISASCII(*m)))
	    return -1;
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
	break;
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
register_symid_direct(VALUE str, ID id)
{
    st_add_direct(global_symbols.str_id, (st_data_t)str, (st_data_t)id);
    st_add_direct(global_symbols.id_str, (st_data_t)id, (st_data_t)str);
}

static int
unregister_sym_str(VALUE str)
{
    st_data_t str_data = (st_data_t)str;
    return st_delete(global_symbols.str_id, &str_data, NULL);
}

static int
unregister_sym_id(VALUE sym)
{
    st_data_t sym_data = (st_data_t)sym;
    return st_delete(global_symbols.id_str, &sym_data, NULL);
}

static void
unregister_sym(VALUE str, VALUE sym)
{
    if (!unregister_sym_str(str)) {
	rb_bug("%p can't remove str from str_id (%s)", (void *)sym, RSTRING_PTR(str));
    }
    if (!unregister_sym_id(sym)) {
	rb_bug("%p can't remove sym from id_str (%s)", (void *)sym, RSTRING_PTR(str));
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

    if (RUBY_DTRACE_SYMBOL_CREATE_ENABLED()) {
	RUBY_DTRACE_SYMBOL_CREATE(RSTRING_PTR(str), rb_sourcefile(), rb_sourceline());
    }

    register_symid_direct(str, id);
    rb_gc_register_mark_object(str);

    return id;
}

static int
sym_check_asciionly(VALUE str)
{
    if (!rb_enc_asciicompat(rb_enc_get(str))) return FALSE;
    switch (rb_enc_str_coderange(str)) {
      case ENC_CODERANGE_BROKEN:
	rb_raise(rb_eEncodingError, "invalid encoding symbol");
      case ENC_CODERANGE_7BIT:
	return TRUE;
    }
    return FALSE;
}

/*
 * _str_ itself will be registered at the global symbol table.  _str_
 * can be modified before the registration, since the encoding will be
 * set to ASCII-8BIT if it is a special global name.
 */
static ID intern_str(VALUE str);

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

static VALUE
dsymbol_alloc(const VALUE klass, const VALUE str, rb_encoding * const enc)
{
    const VALUE dsym = rb_newobj_of(klass, T_SYMBOL | FL_WB_PROTECTED);
    const ID type = rb_str_symname_type(str, IDSET_ATTRSET_FOR_INTERN);

    rb_enc_associate(dsym, enc);
    OBJ_FREEZE(dsym);
    RB_OBJ_WRITE(dsym, &RSYMBOL(dsym)->fstr, str);
    RSYMBOL(dsym)->type = type;

    register_symid_direct(str, (ID)dsym);
    rb_hash_aset(global_symbols.dsymbol_fstr_hash, str, Qtrue);

    if (RUBY_DTRACE_SYMBOL_CREATE_ENABLED()) {
	RUBY_DTRACE_SYMBOL_CREATE(RSTRING_PTR(RSYMBOL(dsym)->fstr), rb_sourcefile(), rb_sourceline());
    }

    return dsym;
}

static inline VALUE
dsymbol_check(const VALUE sym)
{
    if (UNLIKELY(rb_objspace_garbage_object_p(sym))) {
	const VALUE fstr = RSYMBOL(sym)->fstr;
	RSYMBOL(sym)->fstr = 0;

	unregister_sym(fstr, sym);
	return dsymbol_alloc(rb_cSymbol, fstr, rb_enc_get(fstr));
    }
    else {
	return sym;
    }
}

static ID
dsymbol_pindown(VALUE sym)
{
    must_be_dynamic_symbol(sym);

    if (UNLIKELY(SYMBOL_PINNED_P(sym) == 0)) {
	VALUE fstr = RSYMBOL(sym)->fstr;
	sym = dsymbol_check(sym);
	FL_SET(sym, SYMBOL_PINNED);

	/* make it permanent object */
	rb_gc_register_mark_object(sym);
	rb_gc_register_mark_object(fstr);
	rb_hash_delete(global_symbols.dsymbol_fstr_hash, fstr);
    }

    return (ID)sym;
}

static ID
lookup_str_id(VALUE str)
{
    st_data_t id_data;
    if (st_lookup(global_symbols.str_id, (st_data_t)str, &id_data)) {
	const ID id = (ID)id_data;

	if (!ID_DYNAMIC_SYM_P(id) || SYMBOL_PINNED_P(id)) {
	    return id;
	}
    }
    return (ID)0;
}

static VALUE
lookup_str_sym(const VALUE str)
{
    st_data_t sym_data;
    if (st_lookup(global_symbols.str_id, (st_data_t)str, &sym_data)) {
	const ID id = (ID)sym_data;

	if (ID_DYNAMIC_SYM_P(id)) {
	    return dsymbol_check(id);
	}
	else {
	    return STATIC_ID2SYM(id);
	}
    }
    else {
	return (VALUE)0;
    }
}

static VALUE
lookup_id_str(ID id)
{
    st_data_t data;
    if (ID_DYNAMIC_SYM_P(id)) {
	return RSYMBOL(id)->fstr;
    }
    if (st_lookup(global_symbols.id_str, id, &data)) {
	return (VALUE)data;
    }
    return 0;
}

ID
rb_intern_cstr_without_pindown(const char *name, long len, rb_encoding *enc)
{
    st_data_t id;
    struct RString fake_str;
    VALUE str = rb_setup_fake_str(&fake_str, name, len, enc);
    OBJ_FREEZE(str);

    if (st_lookup(global_symbols.str_id, str, &id)) {
	return (ID)id;
    }

    str = rb_enc_str_new(name, len, enc); /* make true string */
    return intern_str(str);
}

ID
rb_intern3(const char *name, long len, rb_encoding *enc)
{
    ID id;

    id = rb_intern_cstr_without_pindown(name, len, enc);
    if (ID_DYNAMIC_SYM_P(id)) {
	id = dsymbol_pindown((VALUE)id);
    }

    return id;
}

static ID
next_id_base(void)
{
    if (global_symbols.last_id >= ~(ID)0 >> (ID_SCOPE_SHIFT+RUBY_SPECIAL_SHIFT)) {
	return (ID)-1;
    }
    ++global_symbols.last_id;
    return global_symbols.last_id << ID_SCOPE_SHIFT;
}

static ID
next_id(VALUE str)
{
    const char *name, *m, *e;
    long len, last;
    rb_encoding *enc, *symenc;
    unsigned char c;
    ID id;
    ID nid;
    int mb;

    RSTRING_GETMEM(str, name, len);
    m = name;
    e = m + len;
    enc = rb_enc_get(str);
    symenc = enc;

    if (!len || (rb_cString && !rb_enc_asciicompat(enc))) {
      junk:
	id = ID_JUNK;
	goto new_id;
    }
    last = len-1;
    id = 0;
    switch (*m) {
      case '$':
	if (len < 2) goto junk;
	id |= ID_GLOBAL;
	if ((mb = is_special_global_name(++m, e, enc)) != 0) {
	    if (!--mb) symenc = rb_usascii_encoding();
	    goto new_id;
	}
	break;
      case '@':
	if (m[1] == '@') {
	    if (len < 3) goto junk;
	    m++;
	    id |= ID_CLASS;
	}
	else {
	    if (len < 2) goto junk;
	    id |= ID_INSTANCE;
	}
	m++;
	break;
      default:
	c = m[0];
	if (c != '_' && rb_enc_isascii(c, enc) && rb_enc_ispunct(c, enc)) {
	    /* operators */
	    int i;

	    if (len == 1) {
		id = c;
                return id;
	    }
	    for (i = 0; i < op_tbl_count; i++) {
		if (*op_tbl[i].name == *m &&
		    strcmp(op_tbl[i].name, m) == 0) {
		    id = op_tbl[i].token;
                    return id;
		}
	    }
	}
	break;
    }
    if (name[last] == '=') {
	/* attribute assignment */
	if (last > 1 && name[last-1] == '=')
	    goto junk;
	id = rb_intern3(name, last, enc);
	if (id > tLAST_OP_ID && !is_attrset_id(id)) {
	    enc = rb_enc_get(rb_id2str(id));
	    id = rb_id_attrset(id);
	    return id;
	}
	id = ID_ATTRSET;
    }
    else if (id == 0) {
	if (rb_enc_isupper(m[0], enc)) {
	    id = ID_CONST;
	}
	else {
	    id = ID_LOCAL;
	}
    }
    if (!rb_enc_isdigit(*m, enc)) {
	while (m <= name + last && is_identchar(m, e, enc)) {
	    if (ISASCII(*m)) {
		m++;
	    }
	    else {
		m += rb_enc_mbclen(m, e, enc);
	    }
	}
    }
    if (id != ID_ATTRSET && m - name < len) id = ID_JUNK;
    if (sym_check_asciionly(str)) symenc = rb_usascii_encoding();
  new_id:
    if (symenc != enc) rb_enc_associate(str, symenc);
    if ((nid = next_id_base()) == (ID)-1) {
	str = rb_str_ellipsize(str, 20);
	rb_raise(rb_eRuntimeError, "symbol table overflow (symbol %"PRIsVALUE")",
		 str);
    }
    id |= nid;
    id |= ID_STATIC_SYM;
    return id;
}

static ID
intern_str(VALUE str)
{
    ID id = next_id(str);
    if (ID_DYNAMIC_SYM_P(id) && is_attrset_id(id)) return id;
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

    return intern_str(rb_str_dup(str));
}

void
rb_gc_free_dsymbol(VALUE sym)
{
    VALUE str = RSYMBOL(sym)->fstr;

    if (str) {
	RSYMBOL(sym)->fstr = 0;
	unregister_sym(str, sym);
    }
}

/*
 *  call-seq:
 *     str.intern   -> symbol
 *     str.to_sym   -> symbol
 *
 *  Returns the <code>Symbol</code> corresponding to <i>str</i>, creating the
 *  symbol if it did not previously exist. See <code>Symbol#id2name</code>.
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
rb_str_dynamic_intern(VALUE str)
{
#if USE_SYMBOL_GC
    rb_encoding *enc, *ascii;
    VALUE sym = lookup_str_sym(str);

    if (sym) {
	return sym;
    }

    enc = rb_enc_get(str);
    ascii = rb_usascii_encoding();
    if (enc != ascii) {
	if (sym_check_asciionly(str)) {
	    str = rb_str_dup(str);
	    rb_enc_associate(str, ascii);
	    OBJ_FREEZE(str);
	    enc = ascii;
	}
    }

    return dsymbol_alloc(rb_cSymbol, rb_fstring(str), enc);
#else
    return rb_str_intern(str);
#endif
}

ID
rb_sym2id(VALUE sym)
{
    if (STATIC_SYM_P(sym)) {
	return STATIC_SYM2ID(sym);
    }
    else {
	if (!SYMBOL_PINNED_P(sym)) {
	    return dsymbol_pindown(sym);
	}
	return (ID)sym;
    }
}

VALUE
rb_id2sym(ID x)
{
    if (!ID_DYNAMIC_SYM_P(x)) {
	return STATIC_ID2SYM(x);
    }
    else {
	return (VALUE)x;
    }
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
    VALUE str;

    if (id < tLAST_OP_ID) {
	int i = 0;

	if (id < INT_MAX && rb_ispunct((int)id)) {
	    char name[1];
	    name[0] = (char)id;
	    return rb_fstring_new(name, 1);
	}
	for (i = 0; i < op_tbl_count; i++) {
	    if (op_tbl[i].token == id) {
		const char *name = op_tbl[i].name;
		return rb_fstring_new(name, op_tbl_len(i));
	    }
	}
    }

    if ((str = lookup_id_str(id)) != 0) {
        if (RBASIC(str)->klass == 0)
            RBASIC_SET_CLASS_RAW(str, rb_cString);
	return str;
    }

    if (is_attrset_id(id)) {
	ID id_stem = (id & ~ID_SCOPE_MASK) | ID_STATIC_SYM;

	do {
	    if (!!(str = rb_id2str(id_stem | ID_LOCAL))) break;
	    if (!!(str = rb_id2str(id_stem | ID_CONST))) break;
	    if (!!(str = rb_id2str(id_stem | ID_INSTANCE))) break;
	    if (!!(str = rb_id2str(id_stem | ID_GLOBAL))) break;
	    if (!!(str = rb_id2str(id_stem | ID_CLASS))) break;
	    if (!!(str = rb_id2str(id_stem | ID_JUNK))) break;
	    return 0;
	} while (0);
	str = rb_str_dup(str);
	rb_str_cat(str, "=", 1);
	register_static_symid_str(id, str);
	if ((str = lookup_id_str(id)) != 0) {
            if (RBASIC(str)->klass == 0)
                RBASIC_SET_CLASS_RAW(str, rb_cString);
            return str;
        }
    }
    return 0;
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
    VALUE sym = ID2SYM((ID)value);

    if (DYNAMIC_SYM_P(sym) && !SYMBOL_PINNED_P(sym) && rb_objspace_garbage_object_p(sym)) {
	RSYMBOL(sym)->fstr = 0;
	unregister_sym_id(sym);
	return ST_DELETE;
    }
    else {
	rb_ary_push(ary, sym);
	return ST_CONTINUE;
    }

}

/*
 *  call-seq:
 *     Symbol.all_symbols    => array
 *
 *  Returns an array of all the symbols currently in Ruby's symbol
 *  table.
 *
 *     Symbol.all_symbols.size    #=> 903
 *     Symbol.all_symbols[1,20]   #=> [:floor, :ARGV, :Binding, :symlink,
 *                                     :chown, :EOFError, :$;, :String,
 *                                     :LOCK_SH, :"setuid?", :$<,
 *                                     :default_proc, :compact, :extend,
 *                                     :Tms, :getwd, :$=, :ThreadGroup,
 *                                     :wait2, :$>]
 */

VALUE
rb_sym_all_symbols(void)
{
    VALUE ary = rb_ary_new2(global_symbols.str_id->num_entries);
    st_foreach(global_symbols.str_id, symbols_i, ary);
    return ary;
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
    ID id;
    VALUE tmp;
    VALUE name = *namep;

    if (STATIC_SYM_P(name)) {
	return STATIC_SYM2ID(name);
    }
    else if (DYNAMIC_SYM_P(name)) {
	if (SYMBOL_PINNED_P(name)) {
	    return (ID)name;
	}
	else {
	    *namep = RSYMBOL(name)->fstr;
	    return 0;
	}
    }
    else if (!RB_TYPE_P(name, T_STRING)) {
	tmp = rb_check_string_type(name);
	if (NIL_P(tmp)) {
	    tmp = rb_inspect(name);
	    rb_raise(rb_eTypeError, "%s is not a symbol nor a string",
		     RSTRING_PTR(tmp));
	}
	name = tmp;
	*namep = name;
    }

    sym_check_asciionly(name);

    if ((id = lookup_str_id(name)) != 0) {
	return id;
    }

    {
	ID gid = attrsetname_to_attr(name);
	if (gid) return rb_id_attrset(gid);
    }

    return (ID)0;
}

VALUE
rb_check_symbol(volatile VALUE *namep)
{
    VALUE sym;
    VALUE tmp;
    VALUE name = *namep;

    if (SYMBOL_P(name)) {
	return name;
    }
    else if (!RB_TYPE_P(name, T_STRING)) {
	tmp = rb_check_string_type(name);
	if (NIL_P(tmp)) {
	    tmp = rb_inspect(name);
	    rb_raise(rb_eTypeError, "%s is not a symbol nor a string",
		     RSTRING_PTR(tmp));
	}
	name = tmp;
	*namep = name;
    }

    sym_check_asciionly(name);

    if ((sym = lookup_str_sym(name)) != 0) {
	return sym;
    }

    {
	ID gid = attrsetname_to_attr(name);
	if (gid) return ID2SYM(rb_id_attrset(gid));
    }

    return Qnil;
}

ID
rb_check_id_cstr(const char *ptr, long len, rb_encoding *enc)
{
    ID id;
    struct RString fake_str;
    const VALUE name = rb_setup_fake_str(&fake_str, ptr, len, enc);

    sym_check_asciionly(name);

    if ((id = lookup_str_id(name)) != 0) {
	return id;
    }

    if (rb_is_attrset_name(name)) {
	fake_str.as.heap.len = len - 1;
	if ((id = lookup_str_id(name)) != 0) {
	    return rb_id_attrset(id);
	}
    }

    return (ID)0;
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

    if (rb_is_attrset_name(name)) {
	fake_str.as.heap.len = len - 1;
	if ((sym = lookup_str_sym(name)) != 0) {
	    return ID2SYM(rb_id_attrset(SYM2ID(sym)));
	}
    }

    return Qnil;
}

static ID
attrsetname_to_attr(VALUE name)
{
    if (rb_is_attrset_name(name)) {
	ID id;
	struct RString fake_str;
	/* make local name by chopping '=' */
	const VALUE localname = rb_setup_fake_str(&fake_str,
						  RSTRING_PTR(name), RSTRING_LEN(name) - 1,
						  rb_enc_get(name));
	OBJ_FREEZE(localname);

	if ((id = lookup_str_id(localname)) != 0) {
	    return id;
	}
	RB_GC_GUARD(name);
    }

    return (ID)0;
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
rb_is_global_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_GLOBAL;
}

int
rb_is_instance_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_INSTANCE;
}

int
rb_is_attrset_name(VALUE name)
{
    return rb_str_symname_type(name, IDSET_ATTRSET_FOR_INTERN) == ID_ATTRSET;
}

int
rb_is_local_name(VALUE name)
{
    return rb_str_symname_type(name, 0) == ID_LOCAL;
}

int
rb_is_method_name(VALUE name)
{
    switch (rb_str_symname_type(name, 0)) {
      case ID_LOCAL: case ID_ATTRSET: case ID_JUNK:
	return TRUE;
    }
    return FALSE;
}

int
rb_is_junk_name(VALUE name)
{
    return rb_str_symname_type(name, IDSET_ATTRSET_FOR_SYNTAX) == -1;
}
