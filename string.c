/**********************************************************************

  string.c -

  $Author$
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal.h"
#include "ruby/re.h"
#include "encindex.h"
#include "probes.h"
#include "gc.h"
#include <assert.h>
#include "id.h"

#define BEG(no) (regs->beg[(no)])
#define END(no) (regs->end[(no)])

#include <math.h>
#include <ctype.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#define STRING_ENUMERATORS_WANTARRAY 0 /* next major */

#undef rb_str_new
#undef rb_usascii_str_new
#undef rb_utf8_str_new
#undef rb_enc_str_new
#undef rb_str_new_cstr
#undef rb_tainted_str_new_cstr
#undef rb_usascii_str_new_cstr
#undef rb_utf8_str_new_cstr
#undef rb_enc_str_new_cstr
#undef rb_external_str_new_cstr
#undef rb_locale_str_new_cstr
#undef rb_str_dup_frozen
#undef rb_str_buf_new_cstr
#undef rb_str_buf_cat
#undef rb_str_buf_cat2
#undef rb_str_cat2
#undef rb_str_cat_cstr
#undef rb_fstring_cstr

static VALUE rb_str_clear(VALUE str);

VALUE rb_cString;
VALUE rb_cSymbol;

/* FLAGS of RString
 *
 * 1:     RSTRING_NOEMBED
 * 2:     STR_SHARED (== ELTS_SHARED)
 * 2-6:   RSTRING_EMBED_LEN (5 bits == 32)
 * 7:     STR_TMPLOCK
 * 8-9:   ENC_CODERANGE (2 bits)
 * 10-16: ENCODING (7 bits == 128)
 * 17:    RSTRING_FSTR
 * 18:    STR_NOFREE
 * 19:    STR_FAKESTR
 */

#define RUBY_MAX_CHAR_LEN 16
#define STR_TMPLOCK FL_USER7
#define STR_NOFREE FL_USER18
#define STR_FAKESTR FL_USER19

#define STR_SET_NOEMBED(str) do {\
    FL_SET((str), STR_NOEMBED);\
    STR_SET_EMBED_LEN((str), 0);\
} while (0)
#define STR_SET_EMBED(str) FL_UNSET((str), (STR_NOEMBED|STR_NOFREE))
#define STR_SET_EMBED_LEN(str, n) do { \
    long tmp_n = (n);\
    RBASIC(str)->flags &= ~RSTRING_EMBED_LEN_MASK;\
    RBASIC(str)->flags |= (tmp_n) << RSTRING_EMBED_LEN_SHIFT;\
} while (0)

#define STR_SET_LEN(str, n) do { \
    if (STR_EMBED_P(str)) {\
	STR_SET_EMBED_LEN((str), (n));\
    }\
    else {\
	RSTRING(str)->as.heap.len = (n);\
    }\
} while (0)

#define STR_DEC_LEN(str) do {\
    if (STR_EMBED_P(str)) {\
	long n = RSTRING_LEN(str);\
	n--;\
	STR_SET_EMBED_LEN((str), n);\
    }\
    else {\
	RSTRING(str)->as.heap.len--;\
    }\
} while (0)

#define TERM_LEN(str) rb_enc_mbminlen(rb_enc_get(str))
#define TERM_FILL(ptr, termlen) do {\
    char *const term_fill_ptr = (ptr);\
    const int term_fill_len = (termlen);\
    *term_fill_ptr = '\0';\
    if (UNLIKELY(term_fill_len > 1))\
	memset(term_fill_ptr, 0, term_fill_len);\
} while (0)

#define RESIZE_CAPA(str,capacity) do {\
    const int termlen = TERM_LEN(str);\
    RESIZE_CAPA_TERM(str,capacity,termlen);\
} while (0)
#define RESIZE_CAPA_TERM(str,capacity,termlen) do {\
    if (STR_EMBED_P(str)) {\
	if ((capacity) > (RSTRING_EMBED_LEN_MAX + 1 - (termlen))) {\
	    char *const tmp = ALLOC_N(char, (capacity)+termlen);\
	    const long tlen = RSTRING_LEN(str);\
	    memcpy(tmp, RSTRING_PTR(str), tlen);\
	    RSTRING(str)->as.heap.ptr = tmp;\
	    RSTRING(str)->as.heap.len = tlen;\
            STR_SET_NOEMBED(str);\
	    RSTRING(str)->as.heap.aux.capa = (capacity);\
	}\
    }\
    else {\
	assert(!FL_TEST((str), STR_SHARED)); \
	REALLOC_N(RSTRING(str)->as.heap.ptr, char, (capacity)+termlen);\
	RSTRING(str)->as.heap.aux.capa = (capacity);\
    }\
} while (0)

#define STR_SET_SHARED(str, shared_str) do { \
    if (!FL_TEST(str, STR_FAKESTR)) { \
	RB_OBJ_WRITE((str), &RSTRING(str)->as.heap.aux.shared, (shared_str)); \
	FL_SET((str), STR_SHARED); \
    } \
} while (0)

#define STR_HEAP_PTR(str)  (RSTRING(str)->as.heap.ptr)
#define STR_HEAP_SIZE(str) (RSTRING(str)->as.heap.aux.capa + TERM_LEN(str))

#define STR_ENC_GET(str) get_encoding(str)

#if !defined SHARABLE_MIDDLE_SUBSTRING
# define SHARABLE_MIDDLE_SUBSTRING 0
#endif
#if !SHARABLE_MIDDLE_SUBSTRING
#define SHARABLE_SUBSTRING_P(beg, len, end) ((beg) + (len) == (end))
#else
#define SHARABLE_SUBSTRING_P(beg, len, end) 1
#endif

static VALUE str_replace_shared_without_enc(VALUE str2, VALUE str);
static VALUE str_new_shared(VALUE klass, VALUE str);
static VALUE str_new_frozen(VALUE klass, VALUE orig);
static VALUE str_new_static(VALUE klass, const char *ptr, long len, int encindex);
static void str_make_independent_expand(VALUE str, long len, long expand, const int termlen);

static inline void
str_make_independent(VALUE str)
{
    long len = RSTRING_LEN(str);
    int termlen = TERM_LEN(str);
    str_make_independent_expand((str), len, 0L, termlen);
}

static rb_encoding *
get_actual_encoding(const int encidx, VALUE str)
{
    const unsigned char *q;

    switch (encidx) {
      case ENCINDEX_UTF_16:
	if (RSTRING_LEN(str) < 2) break;
	q = (const unsigned char *)RSTRING_PTR(str);
	if (q[0] == 0xFE && q[1] == 0xFF) {
	    return rb_enc_get_from_index(ENCINDEX_UTF_16BE);
	}
	if (q[0] == 0xFF && q[1] == 0xFE) {
	    return rb_enc_get_from_index(ENCINDEX_UTF_16LE);
	}
	return rb_ascii8bit_encoding();
      case ENCINDEX_UTF_32:
	if (RSTRING_LEN(str) < 4) break;
	q = (const unsigned char *)RSTRING_PTR(str);
	if (q[0] == 0 && q[1] == 0 && q[2] == 0xFE && q[3] == 0xFF) {
	    return rb_enc_get_from_index(ENCINDEX_UTF_32BE);
	}
	if (q[3] == 0 && q[2] == 0 && q[1] == 0xFE && q[0] == 0xFF) {
	    return rb_enc_get_from_index(ENCINDEX_UTF_32LE);
	}
	return rb_ascii8bit_encoding();
    }
    return rb_enc_from_index(encidx);
}

static rb_encoding *
get_encoding(VALUE str)
{
    return get_actual_encoding(ENCODING_GET(str), str);
}

static void
mustnot_broken(VALUE str)
{
    if (is_broken_string(str)) {
	rb_raise(rb_eArgError, "invalid byte sequence in %s", rb_enc_name(STR_ENC_GET(str)));
    }
}

static void
mustnot_wchar(VALUE str)
{
    rb_encoding *enc = STR_ENC_GET(str);
    if (rb_enc_mbminlen(enc) > 1) {
	rb_raise(rb_eArgError, "wide char encoding: %s", rb_enc_name(enc));
    }
}

static int fstring_cmp(VALUE a, VALUE b);

static VALUE register_fstring(VALUE str);

st_table *rb_vm_fstring_table(void);

const struct st_hash_type rb_fstring_hash_type = {
    fstring_cmp,
    rb_str_hash,
};

#define BARE_STRING_P(str) (!FL_ANY_RAW(str, FL_TAINT|FL_EXIVAR) && RBASIC_CLASS(str) == rb_cString)

static int
fstr_update_callback(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    VALUE *fstr = (VALUE *)arg;
    VALUE str = (VALUE)*key;

    if (existing) {
	/* because of lazy sweep, str may be unmarked already and swept
	 * at next time */

	if (rb_objspace_garbage_object_p(str)) {
	    *fstr = Qundef;
	    return ST_DELETE;
	}

	*fstr = str;
	return ST_STOP;
    }
    else {
	if (FL_TEST_RAW(str, STR_FAKESTR)) {
	    str = str_new_static(rb_cString, RSTRING(str)->as.heap.ptr,
				 RSTRING(str)->as.heap.len,
				 ENCODING_GET(str));
	    OBJ_FREEZE_RAW(str);
	}
	else {
	    str = str_new_frozen(rb_cString, str);
	    if (STR_SHARED_P(str)) { /* str should not be shared */
		/* shared substring  */
		str_make_independent(str);
		assert(OBJ_FROZEN(str));
	    }
	    if (!BARE_STRING_P(str)) {
		str = str_new_frozen(rb_cString, str);
	    }
	}
	RBASIC(str)->flags |= RSTRING_FSTR;

	*key = *value = *fstr = str;
	return ST_CONTINUE;
    }
}

RUBY_FUNC_EXPORTED
VALUE
rb_fstring(VALUE str)
{
    VALUE fstr;
    int bare;

    Check_Type(str, T_STRING);

    if (FL_TEST(str, RSTRING_FSTR))
	return str;

    bare = BARE_STRING_P(str);
    if (STR_EMBED_P(str) && !bare) {
	OBJ_FREEZE_RAW(str);
	return str;
    }

    fstr = register_fstring(str);

    if (!bare) {
	str_replace_shared_without_enc(str, fstr);
	OBJ_FREEZE_RAW(str);
	return str;
    }
    return fstr;
}

static VALUE
register_fstring(VALUE str)
{
    VALUE ret;
    st_table *frozen_strings = rb_vm_fstring_table();

    do {
	ret = str;
	st_update(frozen_strings, (st_data_t)str,
		  fstr_update_callback, (st_data_t)&ret);
    } while (ret == Qundef);

    assert(OBJ_FROZEN(ret));
    assert(!FL_TEST_RAW(ret, STR_FAKESTR));
    assert(!FL_TEST_RAW(ret, FL_EXIVAR));
    assert(!FL_TEST_RAW(ret, FL_TAINT));
    assert(RBASIC_CLASS(ret) == rb_cString);
    return ret;
}

static VALUE
setup_fake_str(struct RString *fake_str, const char *name, long len, int encidx)
{
    fake_str->basic.flags = T_STRING|RSTRING_NOEMBED|STR_NOFREE|STR_FAKESTR;
    /* SHARED to be allocated by the callback */

    ENCODING_SET_INLINED((VALUE)fake_str, encidx);

    RBASIC_SET_CLASS_RAW((VALUE)fake_str, rb_cString);
    fake_str->as.heap.len = len;
    fake_str->as.heap.ptr = (char *)name;
    fake_str->as.heap.aux.capa = len;
    return (VALUE)fake_str;
}

VALUE
rb_setup_fake_str(struct RString *fake_str, const char *name, long len, rb_encoding *enc)
{
    return setup_fake_str(fake_str, name, len, rb_enc_to_index(enc));
}

VALUE
rb_fstring_new(const char *ptr, long len)
{
    struct RString fake_str;
    return register_fstring(setup_fake_str(&fake_str, ptr, len, ENCINDEX_US_ASCII));
}

VALUE
rb_fstring_cstr(const char *ptr)
{
    return rb_fstring_new(ptr, strlen(ptr));
}

static int
fstring_set_class_i(st_data_t key, st_data_t val, st_data_t arg)
{
    RBASIC_SET_CLASS((VALUE)key, (VALUE)arg);
    return ST_CONTINUE;
}

static int
fstring_cmp(VALUE a, VALUE b)
{
    long alen, blen;
    const char *aptr, *bptr;
    RSTRING_GETMEM(a, aptr, alen);
    RSTRING_GETMEM(b, bptr, blen);
    return (alen != blen ||
	    ENCODING_GET(a) != ENCODING_GET(b) ||
	    memcmp(aptr, bptr, alen) != 0);
}

static inline int
single_byte_optimizable(VALUE str)
{
    rb_encoding *enc;

    /* Conservative.  It may be ENC_CODERANGE_UNKNOWN. */
    if (ENC_CODERANGE(str) == ENC_CODERANGE_7BIT)
        return 1;

    enc = STR_ENC_GET(str);
    if (rb_enc_mbmaxlen(enc) == 1)
        return 1;

    /* Conservative.  Possibly single byte.
     * "\xa1" in Shift_JIS for example. */
    return 0;
}

VALUE rb_fs;

static inline const char *
search_nonascii(const char *p, const char *e)
{
#if SIZEOF_VOIDP == 8
# define NONASCII_MASK 0x8080808080808080ULL
#elif SIZEOF_VOIDP == 4
# define NONASCII_MASK 0x80808080UL
#endif
#ifdef NONASCII_MASK
    if ((int)SIZEOF_VOIDP * 2 < e - p) {
        const uintptr_t *s, *t;
        const uintptr_t lowbits = SIZEOF_VOIDP - 1;
        s = (const uintptr_t*)(~lowbits & ((uintptr_t)p + lowbits));
        while (p < (const char *)s) {
            if (!ISASCII(*p))
                return p;
            p++;
        }
        t = (const uintptr_t*)(~lowbits & (uintptr_t)e);
        while (s < t) {
            if (*s & NONASCII_MASK) {
                t = s;
                break;
            }
            s++;
        }
        p = (const char *)t;
    }
#endif
    while (p < e) {
        if (!ISASCII(*p))
            return p;
        p++;
    }
    return NULL;
}

static int
coderange_scan(const char *p, long len, rb_encoding *enc)
{
    const char *e = p + len;

    if (rb_enc_to_index(enc) == rb_ascii8bit_encindex()) {
        /* enc is ASCII-8BIT.  ASCII-8BIT string never be broken. */
        p = search_nonascii(p, e);
        return p ? ENC_CODERANGE_VALID : ENC_CODERANGE_7BIT;
    }

    if (rb_enc_asciicompat(enc)) {
        p = search_nonascii(p, e);
        if (!p) return ENC_CODERANGE_7BIT;
        for (;;) {
            int ret = rb_enc_precise_mbclen(p, e, enc);
            if (!MBCLEN_CHARFOUND_P(ret)) return ENC_CODERANGE_BROKEN;
            p += MBCLEN_CHARFOUND_LEN(ret);
            if (p == e) break;
            p = search_nonascii(p, e);
            if (!p) break;
        }
    }
    else {
        while (p < e) {
            int ret = rb_enc_precise_mbclen(p, e, enc);
            if (!MBCLEN_CHARFOUND_P(ret)) return ENC_CODERANGE_BROKEN;
            p += MBCLEN_CHARFOUND_LEN(ret);
        }
    }
    return ENC_CODERANGE_VALID;
}

long
rb_str_coderange_scan_restartable(const char *s, const char *e, rb_encoding *enc, int *cr)
{
    const char *p = s;

    if (*cr == ENC_CODERANGE_BROKEN)
	return e - s;

    if (rb_enc_to_index(enc) == rb_ascii8bit_encindex()) {
	/* enc is ASCII-8BIT.  ASCII-8BIT string never be broken. */
	if (*cr == ENC_CODERANGE_VALID) return e - s;
	p = search_nonascii(p, e);
        *cr = p ? ENC_CODERANGE_VALID : ENC_CODERANGE_7BIT;
	return e - s;
    }
    else if (rb_enc_asciicompat(enc)) {
	p = search_nonascii(p, e);
	if (!p) {
	    if (*cr != ENC_CODERANGE_VALID) *cr = ENC_CODERANGE_7BIT;
	    return e - s;
	}
	for (;;) {
	    int ret = rb_enc_precise_mbclen(p, e, enc);
	    if (!MBCLEN_CHARFOUND_P(ret)) {
		*cr = MBCLEN_INVALID_P(ret) ? ENC_CODERANGE_BROKEN: ENC_CODERANGE_UNKNOWN;
		return p - s;
	    }
	    p += MBCLEN_CHARFOUND_LEN(ret);
	    if (p == e) break;
	    p = search_nonascii(p, e);
	    if (!p) break;
	}
    }
    else {
	while (p < e) {
	    int ret = rb_enc_precise_mbclen(p, e, enc);
	    if (!MBCLEN_CHARFOUND_P(ret)) {
		*cr = MBCLEN_INVALID_P(ret) ? ENC_CODERANGE_BROKEN: ENC_CODERANGE_UNKNOWN;
		return p - s;
	    }
	    p += MBCLEN_CHARFOUND_LEN(ret);
	}
    }
    *cr = ENC_CODERANGE_VALID;
    return e - s;
}

static inline void
str_enc_copy(VALUE str1, VALUE str2)
{
    rb_enc_set_index(str1, ENCODING_GET(str2));
}

static void
rb_enc_cr_str_copy_for_substr(VALUE dest, VALUE src)
{
    /* this function is designed for copying encoding and coderange
     * from src to new string "dest" which is made from the part of src.
     */
    str_enc_copy(dest, src);
    if (RSTRING_LEN(dest) == 0) {
	if (!rb_enc_asciicompat(STR_ENC_GET(src)))
	    ENC_CODERANGE_SET(dest, ENC_CODERANGE_VALID);
	else
	    ENC_CODERANGE_SET(dest, ENC_CODERANGE_7BIT);
	return;
    }
    switch (ENC_CODERANGE(src)) {
      case ENC_CODERANGE_7BIT:
	ENC_CODERANGE_SET(dest, ENC_CODERANGE_7BIT);
	break;
      case ENC_CODERANGE_VALID:
	if (!rb_enc_asciicompat(STR_ENC_GET(src)) ||
	    search_nonascii(RSTRING_PTR(dest), RSTRING_END(dest)))
	    ENC_CODERANGE_SET(dest, ENC_CODERANGE_VALID);
	else
	    ENC_CODERANGE_SET(dest, ENC_CODERANGE_7BIT);
	break;
      default:
	break;
    }
}

static void
rb_enc_cr_str_exact_copy(VALUE dest, VALUE src)
{
    str_enc_copy(dest, src);
    ENC_CODERANGE_SET(dest, ENC_CODERANGE(src));
}

int
rb_enc_str_coderange(VALUE str)
{
    int cr = ENC_CODERANGE(str);

    if (cr == ENC_CODERANGE_UNKNOWN) {
	int encidx = ENCODING_GET(str);
	rb_encoding *enc = rb_enc_from_index(encidx);
	if (rb_enc_mbminlen(enc) > 1 && rb_enc_dummy_p(enc)) {
	    cr = ENC_CODERANGE_BROKEN;
	}
	else {
	    cr = coderange_scan(RSTRING_PTR(str), RSTRING_LEN(str),
				get_actual_encoding(encidx, str));
	}
        ENC_CODERANGE_SET(str, cr);
    }
    return cr;
}

int
rb_enc_str_asciionly_p(VALUE str)
{
    rb_encoding *enc = STR_ENC_GET(str);

    if (!rb_enc_asciicompat(enc))
        return FALSE;
    else if (rb_enc_str_coderange(str) == ENC_CODERANGE_7BIT)
        return TRUE;
    return FALSE;
}

static inline void
str_mod_check(VALUE s, const char *p, long len)
{
    if (RSTRING_PTR(s) != p || RSTRING_LEN(s) != len){
	rb_raise(rb_eRuntimeError, "string modified");
    }
}

static size_t
str_capacity(VALUE str, const int termlen)
{
    if (STR_EMBED_P(str)) {
	return (RSTRING_EMBED_LEN_MAX + 1 - termlen);
    }
    else if (FL_TEST(str, STR_SHARED|STR_NOFREE)) {
	return RSTRING(str)->as.heap.len;
    }
    else {
	return RSTRING(str)->as.heap.aux.capa;
    }
}

size_t
rb_str_capacity(VALUE str)
{
    return str_capacity(str, TERM_LEN(str));
}

static inline void
must_not_null(const char *ptr)
{
    if (!ptr) {
	rb_raise(rb_eArgError, "NULL pointer given");
    }
}

static inline VALUE
str_alloc(VALUE klass)
{
    NEWOBJ_OF(str, struct RString, klass, T_STRING | (RGENGC_WB_PROTECTED_STRING ? FL_WB_PROTECTED : 0));
    return (VALUE)str;
}

static inline VALUE
empty_str_alloc(VALUE klass)
{
    RUBY_DTRACE_CREATE_HOOK(STRING, 0);
    return str_alloc(klass);
}

static VALUE
str_new0(VALUE klass, const char *ptr, long len, int termlen)
{
    VALUE str;

    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    RUBY_DTRACE_CREATE_HOOK(STRING, len);

    str = str_alloc(klass);
    if (len > (RSTRING_EMBED_LEN_MAX + 1 - termlen)) {
	RSTRING(str)->as.heap.aux.capa = len;
	RSTRING(str)->as.heap.ptr = ALLOC_N(char, len + termlen);
	STR_SET_NOEMBED(str);
    }
    else if (len == 0) {
	ENC_CODERANGE_SET(str, ENC_CODERANGE_7BIT);
    }
    if (ptr) {
	memcpy(RSTRING_PTR(str), ptr, len);
    }
    STR_SET_LEN(str, len);
    TERM_FILL(RSTRING_PTR(str) + len, termlen);
    return str;
}

static VALUE
str_new(VALUE klass, const char *ptr, long len)
{
    return str_new0(klass, ptr, len, 1);
}

VALUE
rb_str_new(const char *ptr, long len)
{
    return str_new(rb_cString, ptr, len);
}

VALUE
rb_usascii_str_new(const char *ptr, long len)
{
    VALUE str = rb_str_new(ptr, len);
    ENCODING_CODERANGE_SET(str, rb_usascii_encindex(), ENC_CODERANGE_7BIT);
    return str;
}

VALUE
rb_utf8_str_new(const char *ptr, long len)
{
    VALUE str = str_new(rb_cString, ptr, len);
    rb_enc_associate_index(str, rb_utf8_encindex());
    return str;
}

VALUE
rb_enc_str_new(const char *ptr, long len, rb_encoding *enc)
{
    VALUE str;

    if (!enc) return rb_str_new(ptr, len);

    str = str_new0(rb_cString, ptr, len, rb_enc_mbminlen(enc));
    rb_enc_associate(str, enc);
    return str;
}

VALUE
rb_str_new_cstr(const char *ptr)
{
    must_not_null(ptr);
    return rb_str_new(ptr, strlen(ptr));
}

VALUE
rb_usascii_str_new_cstr(const char *ptr)
{
    VALUE str = rb_str_new_cstr(ptr);
    ENCODING_CODERANGE_SET(str, rb_usascii_encindex(), ENC_CODERANGE_7BIT);
    return str;
}

VALUE
rb_utf8_str_new_cstr(const char *ptr)
{
    VALUE str = rb_str_new_cstr(ptr);
    rb_enc_associate_index(str, rb_utf8_encindex());
    return str;
}

VALUE
rb_enc_str_new_cstr(const char *ptr, rb_encoding *enc)
{
    must_not_null(ptr);
    if (rb_enc_mbminlen(enc) != 1) {
	rb_raise(rb_eArgError, "wchar encoding given");
    }
    return rb_enc_str_new(ptr, strlen(ptr), enc);
}

static VALUE
str_new_static(VALUE klass, const char *ptr, long len, int encindex)
{
    VALUE str;

    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    if (!ptr) {
	rb_encoding *enc = rb_enc_get_from_index(encindex);
	str = str_new0(klass, ptr, len, rb_enc_mbminlen(enc));
    }
    else {
	RUBY_DTRACE_CREATE_HOOK(STRING, len);
	str = str_alloc(klass);
	RSTRING(str)->as.heap.len = len;
	RSTRING(str)->as.heap.ptr = (char *)ptr;
	RSTRING(str)->as.heap.aux.capa = len;
	STR_SET_NOEMBED(str);
	RBASIC(str)->flags |= STR_NOFREE;
    }
    rb_enc_associate_index(str, encindex);
    return str;
}

VALUE
rb_str_new_static(const char *ptr, long len)
{
    return str_new_static(rb_cString, ptr, len, 0);
}

VALUE
rb_usascii_str_new_static(const char *ptr, long len)
{
    return str_new_static(rb_cString, ptr, len, ENCINDEX_US_ASCII);
}

VALUE
rb_utf8_str_new_static(const char *ptr, long len)
{
    return str_new_static(rb_cString, ptr, len, ENCINDEX_UTF_8);
}

VALUE
rb_enc_str_new_static(const char *ptr, long len, rb_encoding *enc)
{
    return str_new_static(rb_cString, ptr, len, rb_enc_to_index(enc));
}

VALUE
rb_tainted_str_new(const char *ptr, long len)
{
    VALUE str = rb_str_new(ptr, len);

    OBJ_TAINT(str);
    return str;
}

static VALUE
rb_tainted_str_new_with_enc(const char *ptr, long len, rb_encoding *enc)
{
    VALUE str = rb_enc_str_new(ptr, len, enc);

    OBJ_TAINT(str);
    return str;
}

VALUE
rb_tainted_str_new_cstr(const char *ptr)
{
    VALUE str = rb_str_new_cstr(ptr);

    OBJ_TAINT(str);
    return str;
}

static VALUE str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
				   rb_encoding *from, rb_encoding *to,
				   int ecflags, VALUE ecopts);

VALUE
rb_str_conv_enc_opts(VALUE str, rb_encoding *from, rb_encoding *to, int ecflags, VALUE ecopts)
{
    long len;
    const char *ptr;
    VALUE newstr;

    if (!to) return str;
    if (!from) from = rb_enc_get(str);
    if (from == to) return str;
    if ((rb_enc_asciicompat(to) && is_ascii_string(str)) ||
	to == rb_ascii8bit_encoding()) {
	if (STR_ENC_GET(str) != to) {
	    str = rb_str_dup(str);
	    rb_enc_associate(str, to);
	}
	return str;
    }

    RSTRING_GETMEM(str, ptr, len);
    newstr = str_cat_conv_enc_opts(rb_str_buf_new(len), 0, ptr, len,
				   from, to, ecflags, ecopts);
    if (NIL_P(newstr)) {
	/* some error, return original */
	return str;
    }
    OBJ_INFECT(newstr, str);
    return newstr;
}

VALUE
rb_str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
			 rb_encoding *from, int ecflags, VALUE ecopts)
{
    long olen;

    olen = RSTRING_LEN(newstr);
    if (ofs < -olen || olen <= ofs)
        rb_raise(rb_eIndexError, "index %ld out of string", ofs);
    if (ofs < 0) ofs += olen;
    if (!from) {
	STR_SET_LEN(newstr, ofs);
	return rb_str_cat(newstr, ptr, len);
    }

    rb_str_modify(newstr);
    return str_cat_conv_enc_opts(newstr, ofs, ptr, len, from,
				 rb_enc_get(newstr),
				 ecflags, ecopts);
}

static VALUE
str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
		      rb_encoding *from, rb_encoding *to,
		      int ecflags, VALUE ecopts)
{
    rb_econv_t *ec;
    rb_econv_result_t ret;
    long olen;
    VALUE econv_wrapper;
    const unsigned char *start, *sp;
    unsigned char *dest, *dp;
    size_t converted_output = (size_t)ofs;

    olen = rb_str_capacity(newstr);

    econv_wrapper = rb_obj_alloc(rb_cEncodingConverter);
    RBASIC_CLEAR_CLASS(econv_wrapper);
    ec = rb_econv_open_opts(from->name, to->name, ecflags, ecopts);
    if (!ec) return Qnil;
    DATA_PTR(econv_wrapper) = ec;

    sp = (unsigned char*)ptr;
    start = sp;
    while ((dest = (unsigned char*)RSTRING_PTR(newstr)),
	   (dp = dest + converted_output),
	   (ret = rb_econv_convert(ec, &sp, start + len, &dp, dest + olen, 0)),
	   ret == econv_destination_buffer_full) {
	/* destination buffer short */
	size_t converted_input = sp - start;
	size_t rest = len - converted_input;
	converted_output = dp - dest;
	rb_str_set_len(newstr, converted_output);
	if (converted_input && converted_output &&
	    rest < (LONG_MAX / converted_output)) {
	    rest = (rest * converted_output) / converted_input;
	}
	else {
	    rest = olen;
	}
	olen += rest < 2 ? 2 : rest;
	rb_str_resize(newstr, olen);
    }
    DATA_PTR(econv_wrapper) = 0;
    rb_econv_close(ec);
    rb_gc_force_recycle(econv_wrapper);
    switch (ret) {
      case econv_finished:
	len = dp - (unsigned char*)RSTRING_PTR(newstr);
	rb_str_set_len(newstr, len);
	rb_enc_associate(newstr, to);
	return newstr;

      default:
	return Qnil;
    }
}

VALUE
rb_str_conv_enc(VALUE str, rb_encoding *from, rb_encoding *to)
{
    return rb_str_conv_enc_opts(str, from, to, 0, Qnil);
}

VALUE
rb_external_str_new_with_enc(const char *ptr, long len, rb_encoding *eenc)
{
    VALUE str;

    str = rb_tainted_str_new_with_enc(ptr, len, eenc);
    return rb_external_str_with_enc(str, eenc);
}

VALUE
rb_external_str_with_enc(VALUE str, rb_encoding *eenc)
{
    if (eenc == rb_usascii_encoding() &&
	rb_enc_str_coderange(str) != ENC_CODERANGE_7BIT) {
	rb_enc_associate(str, rb_ascii8bit_encoding());
	return str;
    }
    rb_enc_associate(str, eenc);
    return rb_str_conv_enc(str, eenc, rb_default_internal_encoding());
}

VALUE
rb_external_str_new(const char *ptr, long len)
{
    return rb_external_str_new_with_enc(ptr, len, rb_default_external_encoding());
}

VALUE
rb_external_str_new_cstr(const char *ptr)
{
    return rb_external_str_new_with_enc(ptr, strlen(ptr), rb_default_external_encoding());
}

VALUE
rb_locale_str_new(const char *ptr, long len)
{
    return rb_external_str_new_with_enc(ptr, len, rb_locale_encoding());
}

VALUE
rb_locale_str_new_cstr(const char *ptr)
{
    return rb_external_str_new_with_enc(ptr, strlen(ptr), rb_locale_encoding());
}

VALUE
rb_filesystem_str_new(const char *ptr, long len)
{
    return rb_external_str_new_with_enc(ptr, len, rb_filesystem_encoding());
}

VALUE
rb_filesystem_str_new_cstr(const char *ptr)
{
    return rb_external_str_new_with_enc(ptr, strlen(ptr), rb_filesystem_encoding());
}

VALUE
rb_str_export(VALUE str)
{
    return rb_str_conv_enc(str, STR_ENC_GET(str), rb_default_external_encoding());
}

VALUE
rb_str_export_locale(VALUE str)
{
    return rb_str_conv_enc(str, STR_ENC_GET(str), rb_locale_encoding());
}

VALUE
rb_str_export_to_enc(VALUE str, rb_encoding *enc)
{
    return rb_str_conv_enc(str, STR_ENC_GET(str), enc);
}

static VALUE
str_replace_shared_without_enc(VALUE str2, VALUE str)
{
    const int termlen = TERM_LEN(str);
    char *ptr;
    long len;

    RSTRING_GETMEM(str, ptr, len);
    if (len+termlen <= RSTRING_EMBED_LEN_MAX+1) {
	char *ptr2 = RSTRING(str2)->as.ary;
	STR_SET_EMBED(str2);
	memcpy(ptr2, RSTRING_PTR(str), len);
	STR_SET_EMBED_LEN(str2, len);
	TERM_FILL(ptr2+len, termlen);
    }
    else {
	str = rb_str_new_frozen(str);
	FL_SET(str2, STR_NOEMBED);
	RSTRING_GETMEM(str, ptr, len);
	RSTRING(str2)->as.heap.len = len;
	RSTRING(str2)->as.heap.ptr = ptr;
	STR_SET_SHARED(str2, str);
    }
    return str2;
}

static VALUE
str_replace_shared(VALUE str2, VALUE str)
{
    str_replace_shared_without_enc(str2, str);
    rb_enc_cr_str_exact_copy(str2, str);
    return str2;
}

static VALUE
str_new_shared(VALUE klass, VALUE str)
{
    return str_replace_shared(str_alloc(klass), str);
}

VALUE
rb_str_new_shared(VALUE str)
{
    VALUE str2 = str_new_shared(rb_obj_class(str), str);

    OBJ_INFECT(str2, str);
    return str2;
}

VALUE
rb_str_new_frozen(VALUE orig)
{
    VALUE str;

    if (OBJ_FROZEN(orig)) return orig;

    str = str_new_frozen(rb_obj_class(orig), orig);
    OBJ_INFECT(str, orig);
    return str;
}

static VALUE
str_new_frozen(VALUE klass, VALUE orig)
{
    VALUE str;

    if (STR_EMBED_P(orig)) {
	str = str_new(klass, RSTRING_PTR(orig), RSTRING_LEN(orig));
    }
    else {
	if (FL_TEST_RAW(orig, STR_SHARED)) {
	    VALUE shared = RSTRING(orig)->as.heap.aux.shared;
	    long ofs = RSTRING(orig)->as.heap.ptr - RSTRING(shared)->as.heap.ptr;
	    long rest = RSTRING(shared)->as.heap.len - ofs - RSTRING(orig)->as.heap.len;
	    assert(!STR_EMBED_P(shared));
	    assert(OBJ_FROZEN(shared));

	    if ((ofs > 0) || (rest > 0) ||
		(klass != RBASIC(shared)->klass) ||
		((RBASIC(shared)->flags ^ RBASIC(orig)->flags) & FL_TAINT) ||
		ENCODING_GET(shared) != ENCODING_GET(orig)) {
		str = str_new_shared(klass, shared);
		RSTRING(str)->as.heap.ptr += ofs;
		RSTRING(str)->as.heap.len -= ofs + rest;
	    }
	    else {
		return shared;
	    }
	}
	else if (RSTRING_LEN(orig)+TERM_LEN(orig) <= RSTRING_EMBED_LEN_MAX+1) {
	    str = str_alloc(klass);
	    STR_SET_EMBED(str);
	    memcpy(RSTRING_PTR(str), RSTRING_PTR(orig), RSTRING_LEN(orig));
	    STR_SET_EMBED_LEN(str, RSTRING_LEN(orig));
	    TERM_FILL(RSTRING_END(str), TERM_LEN(orig));
	}
	else {
	    str = str_alloc(klass);
	    STR_SET_NOEMBED(str);
	    RSTRING(str)->as.heap.len = RSTRING_LEN(orig);
	    RSTRING(str)->as.heap.ptr = RSTRING_PTR(orig);
	    RSTRING(str)->as.heap.aux.capa = RSTRING(orig)->as.heap.aux.capa;
	    RBASIC(str)->flags |= RBASIC(orig)->flags & STR_NOFREE;
	    RBASIC(orig)->flags &= ~STR_NOFREE;
	    STR_SET_SHARED(orig, str);
	}
    }

    rb_enc_cr_str_exact_copy(str, orig);
    OBJ_FREEZE(str);
    return str;
}

VALUE
rb_str_new_with_class(VALUE obj, const char *ptr, long len)
{
    return str_new0(rb_obj_class(obj), ptr, len, TERM_LEN(obj));
}

static VALUE
str_new_empty(VALUE str)
{
    VALUE v = rb_str_new_with_class(str, 0, 0);
    rb_enc_copy(v, str);
    OBJ_INFECT(v, str);
    return v;
}

#define STR_BUF_MIN_SIZE 128

VALUE
rb_str_buf_new(long capa)
{
    VALUE str = str_alloc(rb_cString);

    if (capa < STR_BUF_MIN_SIZE) {
	capa = STR_BUF_MIN_SIZE;
    }
    FL_SET(str, STR_NOEMBED);
    RSTRING(str)->as.heap.aux.capa = capa;
    RSTRING(str)->as.heap.ptr = ALLOC_N(char, capa+1);
    RSTRING(str)->as.heap.ptr[0] = '\0';

    return str;
}

VALUE
rb_str_buf_new_cstr(const char *ptr)
{
    VALUE str;
    long len = strlen(ptr);

    str = rb_str_buf_new(len);
    rb_str_buf_cat(str, ptr, len);

    return str;
}

VALUE
rb_str_tmp_new(long len)
{
    return str_new(0, 0, len);
}

void
rb_str_free(VALUE str)
{
    if (FL_TEST(str, RSTRING_FSTR)) {
	st_data_t fstr = (st_data_t)str;
	st_delete(rb_vm_fstring_table(), &fstr, NULL);
    }

    if (!STR_EMBED_P(str) && !FL_TEST(str, STR_SHARED|STR_NOFREE)) {
	ruby_sized_xfree(STR_HEAP_PTR(str), STR_HEAP_SIZE(str));
    }
}

RUBY_FUNC_EXPORTED size_t
rb_str_memsize(VALUE str)
{
    if (FL_TEST(str, STR_NOEMBED|STR_SHARED|STR_NOFREE) == STR_NOEMBED) {
	return STR_HEAP_SIZE(str);
    }
    else {
	return 0;
    }
}

VALUE
rb_str_to_str(VALUE str)
{
    return rb_convert_type(str, T_STRING, "String", "to_str");
}

static inline void str_discard(VALUE str);
static void str_shared_replace(VALUE str, VALUE str2);

void
rb_str_shared_replace(VALUE str, VALUE str2)
{
    if (str != str2) str_shared_replace(str, str2);
}

static void
str_shared_replace(VALUE str, VALUE str2)
{
    rb_encoding *enc;
    int cr;
    int termlen;

    ASSUME(str2 != str);
    enc = STR_ENC_GET(str2);
    cr = ENC_CODERANGE(str2);
    str_discard(str);
    OBJ_INFECT(str, str2);
    termlen = rb_enc_mbminlen(enc);

    if (RSTRING_LEN(str2) <= (RSTRING_EMBED_LEN_MAX + 1 - termlen)) {
	STR_SET_EMBED(str);
	memcpy(RSTRING_PTR(str), RSTRING_PTR(str2), RSTRING_LEN(str2)+termlen);
	STR_SET_EMBED_LEN(str, RSTRING_LEN(str2));
        rb_enc_associate(str, enc);
        ENC_CODERANGE_SET(str, cr);
    }
    else {
	STR_SET_NOEMBED(str);
	FL_UNSET(str, STR_SHARED);
	RSTRING(str)->as.heap.ptr = RSTRING_PTR(str2);
	RSTRING(str)->as.heap.len = RSTRING_LEN(str2);

	if (FL_TEST(str2, STR_SHARED)) {
	    VALUE shared = RSTRING(str2)->as.heap.aux.shared;
	    STR_SET_SHARED(str, shared);
	}
	else {
	    RSTRING(str)->as.heap.aux.capa = RSTRING(str2)->as.heap.aux.capa;
	}

	/* abandon str2 */
	STR_SET_EMBED(str2);
	RSTRING_PTR(str2)[0] = 0;
	STR_SET_EMBED_LEN(str2, 0);
	rb_enc_associate(str, enc);
	ENC_CODERANGE_SET(str, cr);
    }
}

VALUE
rb_obj_as_string(VALUE obj)
{
    VALUE str;

    if (RB_TYPE_P(obj, T_STRING)) {
	return obj;
    }
    str = rb_funcall(obj, idTo_s, 0);
    if (!RB_TYPE_P(str, T_STRING))
	return rb_any_to_s(obj);
    if (!FL_TEST_RAW(str, RSTRING_FSTR) && FL_ABLE(obj))
	/* fstring must not be tainted, at least */
	OBJ_INFECT_RAW(str, obj);
    return str;
}

static VALUE
str_replace(VALUE str, VALUE str2)
{
    long len;

    len = RSTRING_LEN(str2);
    if (STR_SHARED_P(str2)) {
	VALUE shared = RSTRING(str2)->as.heap.aux.shared;
	assert(OBJ_FROZEN(shared));
	STR_SET_NOEMBED(str);
	RSTRING(str)->as.heap.len = len;
	RSTRING(str)->as.heap.ptr = RSTRING_PTR(str2);
	STR_SET_SHARED(str, shared);
	rb_enc_cr_str_exact_copy(str, str2);
    }
    else {
	str_replace_shared(str, str2);
    }

    OBJ_INFECT(str, str2);
    return str;
}

static inline VALUE
str_duplicate(VALUE klass, VALUE str)
{
    enum {embed_size = RSTRING_EMBED_LEN_MAX + 1};
    const VALUE flag_mask =
	RSTRING_NOEMBED | RSTRING_EMBED_LEN_MASK |
	ENC_CODERANGE_MASK | ENCODING_MASK |
	FL_TAINT | FL_FREEZE
	;
    VALUE flags = FL_TEST_RAW(str, flag_mask);
    VALUE dup = str_alloc(klass);
    MEMCPY(RSTRING(dup)->as.ary, RSTRING(str)->as.ary,
	   char, embed_size);
    if (flags & STR_NOEMBED) {
	if (UNLIKELY(!(flags & FL_FREEZE))) {
	    str = str_new_frozen(klass, str);
	    FL_SET_RAW(str, flags & FL_TAINT);
	    flags = FL_TEST_RAW(str, flag_mask);
	}
	if (flags & STR_NOEMBED) {
	    RB_OBJ_WRITE(dup, &RSTRING(dup)->as.heap.aux.shared, str);
	    flags |= STR_SHARED;
	}
	else {
	    MEMCPY(RSTRING(dup)->as.ary, RSTRING(str)->as.ary,
		   char, embed_size);
	}
    }
    FL_SET_RAW(dup, flags & ~FL_FREEZE);
    return dup;
}

VALUE
rb_str_dup(VALUE str)
{
    return str_duplicate(rb_obj_class(str), str);
}

VALUE
rb_str_resurrect(VALUE str)
{
    RUBY_DTRACE_CREATE_HOOK(STRING, RSTRING_LEN(str));
    return str_duplicate(rb_cString, str);
}

/*
 *  call-seq:
 *     String.new(str="")   -> new_str
 *     String.new(str="", encoding: enc) -> new_str
 *
 *  Returns a new string object containing a copy of <i>str</i>.
 *  The optional <i>enc</i> argument specifies the encoding of the new string.
 *  If not specified, the encoding of <i>str</i> (or ASCII-8BIT, if <i>str</i>
 *  is not specified) is used.
 */

static VALUE
rb_str_init(int argc, VALUE *argv, VALUE str)
{
    static ID keyword_ids[1];
    VALUE orig, opt, enc;
    int n;

    if (!keyword_ids[0])
	keyword_ids[0] = rb_id_encoding();

    n = rb_scan_args(argc, argv, "01:", &orig, &opt);
    if (argc > 0 && n == 1)
	rb_str_replace(str, orig);
    if (!NIL_P(opt)) {
	rb_get_kwargs(opt, keyword_ids, 0, 1, &enc);
	if (enc != Qundef && !NIL_P(enc)) {
	    rb_enc_associate(str, rb_to_encoding(enc));
	    ENC_CODERANGE_CLEAR(str);
	}
    }
    return str;
}

#ifdef NONASCII_MASK
#define is_utf8_lead_byte(c) (((c)&0xC0) != 0x80)

/*
 * UTF-8 leading bytes have either 0xxxxxxx or 11xxxxxx
 * bit representation. (see http://en.wikipedia.org/wiki/UTF-8)
 * Therefore, the following pseudocode can detect UTF-8 leading bytes.
 *
 * if (!(byte & 0x80))
 *   byte |= 0x40;          // turn on bit6
 * return ((byte>>6) & 1);  // bit6 represent whether this byte is leading or not.
 *
 * This function calculates whether a byte is leading or not for all bytes
 * in the argument word by concurrently using the above logic, and then
 * adds up the number of leading bytes in the word.
 */
static inline uintptr_t
count_utf8_lead_bytes_with_word(const uintptr_t *s)
{
    uintptr_t d = *s;

    /* Transform so that bit0 indicates whether we have a UTF-8 leading byte or not. */
    d |= ~(d>>1);
    d >>= 6;
    d &= NONASCII_MASK >> 7;

    /* Gather all bytes. */
    d += (d>>8);
    d += (d>>16);
#if SIZEOF_VOIDP == 8
    d += (d>>32);
#endif
    return (d&0xF);
}
#endif

static inline long
enc_strlen(const char *p, const char *e, rb_encoding *enc, int cr)
{
    long c;
    const char *q;

    if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
        return (e - p + rb_enc_mbminlen(enc) - 1) / rb_enc_mbminlen(enc);
    }
#ifdef NONASCII_MASK
    else if (cr == ENC_CODERANGE_VALID && enc == rb_utf8_encoding()) {
	uintptr_t len = 0;
	if ((int)sizeof(uintptr_t) * 2 < e - p) {
	    const uintptr_t *s, *t;
	    const uintptr_t lowbits = sizeof(uintptr_t) - 1;
	    s = (const uintptr_t*)(~lowbits & ((uintptr_t)p + lowbits));
	    t = (const uintptr_t*)(~lowbits & (uintptr_t)e);
	    while (p < (const char *)s) {
		if (is_utf8_lead_byte(*p)) len++;
		p++;
	    }
	    while (s < t) {
		len += count_utf8_lead_bytes_with_word(s);
		s++;
	    }
	    p = (const char *)s;
	}
	while (p < e) {
	    if (is_utf8_lead_byte(*p)) len++;
	    p++;
	}
	return (long)len;
    }
#endif
    else if (rb_enc_asciicompat(enc)) {
        c = 0;
	if (ENC_CODERANGE_CLEAN_P(cr)) {
	    while (p < e) {
		if (ISASCII(*p)) {
		    q = search_nonascii(p, e);
		    if (!q)
			return c + (e - p);
		    c += q - p;
		    p = q;
		}
		p += rb_enc_fast_mbclen(p, e, enc);
		c++;
	    }
	}
	else {
	    while (p < e) {
		if (ISASCII(*p)) {
		    q = search_nonascii(p, e);
		    if (!q)
			return c + (e - p);
		    c += q - p;
		    p = q;
		}
		p += rb_enc_mbclen(p, e, enc);
		c++;
	    }
	}
        return c;
    }

    for (c=0; p<e; c++) {
        p += rb_enc_mbclen(p, e, enc);
    }
    return c;
}

long
rb_enc_strlen(const char *p, const char *e, rb_encoding *enc)
{
    return enc_strlen(p, e, enc, ENC_CODERANGE_UNKNOWN);
}

/* To get strlen with cr
 * Note that given cr is not used.
 */
long
rb_enc_strlen_cr(const char *p, const char *e, rb_encoding *enc, int *cr)
{
    long c;
    const char *q;
    int ret;

    *cr = 0;
    if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
	return (e - p + rb_enc_mbminlen(enc) - 1) / rb_enc_mbminlen(enc);
    }
    else if (rb_enc_asciicompat(enc)) {
	c = 0;
	while (p < e) {
	    if (ISASCII(*p)) {
		q = search_nonascii(p, e);
		if (!q) {
		    if (!*cr) *cr = ENC_CODERANGE_7BIT;
		    return c + (e - p);
		}
		c += q - p;
		p = q;
	    }
	    ret = rb_enc_precise_mbclen(p, e, enc);
	    if (MBCLEN_CHARFOUND_P(ret)) {
		*cr |= ENC_CODERANGE_VALID;
		p += MBCLEN_CHARFOUND_LEN(ret);
	    }
	    else {
		*cr = ENC_CODERANGE_BROKEN;
		p++;
	    }
	    c++;
	}
	if (!*cr) *cr = ENC_CODERANGE_7BIT;
	return c;
    }

    for (c=0; p<e; c++) {
	ret = rb_enc_precise_mbclen(p, e, enc);
	if (MBCLEN_CHARFOUND_P(ret)) {
	    *cr |= ENC_CODERANGE_VALID;
	    p += MBCLEN_CHARFOUND_LEN(ret);
	}
	else {
	    *cr = ENC_CODERANGE_BROKEN;
            if (p + rb_enc_mbminlen(enc) <= e)
                p += rb_enc_mbminlen(enc);
            else
                p = e;
	}
    }
    if (!*cr) *cr = ENC_CODERANGE_7BIT;
    return c;
}

/* enc must be str's enc or rb_enc_check(str, str2) */
static long
str_strlen(VALUE str, rb_encoding *enc)
{
    const char *p, *e;
    int cr;

    if (single_byte_optimizable(str)) return RSTRING_LEN(str);
    if (!enc) enc = STR_ENC_GET(str);
    p = RSTRING_PTR(str);
    e = RSTRING_END(str);
    cr = ENC_CODERANGE(str);

    if (cr == ENC_CODERANGE_UNKNOWN) {
	long n = rb_enc_strlen_cr(p, e, enc, &cr);
	if (cr) ENC_CODERANGE_SET(str, cr);
	return n;
    }
    else {
	return enc_strlen(p, e, enc, cr);
    }
}

long
rb_str_strlen(VALUE str)
{
    return str_strlen(str, NULL);
}

/*
 *  call-seq:
 *     str.length   -> integer
 *     str.size     -> integer
 *
 *  Returns the character length of <i>str</i>.
 */

VALUE
rb_str_length(VALUE str)
{
    return LONG2NUM(str_strlen(str, NULL));
}

/*
 *  call-seq:
 *     str.bytesize  -> integer
 *
 *  Returns the length of +str+ in bytes.
 *
 *    "\x80\u3042".bytesize  #=> 4
 *    "hello".bytesize       #=> 5
 */

static VALUE
rb_str_bytesize(VALUE str)
{
    return LONG2NUM(RSTRING_LEN(str));
}

/*
 *  call-seq:
 *     str.empty?   -> true or false
 *
 *  Returns <code>true</code> if <i>str</i> has a length of zero.
 *
 *     "hello".empty?   #=> false
 *     " ".empty?       #=> false
 *     "".empty?        #=> true
 */

static VALUE
rb_str_empty(VALUE str)
{
    if (RSTRING_LEN(str) == 0)
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     str + other_str   -> new_str
 *
 *  Concatenation---Returns a new <code>String</code> containing
 *  <i>other_str</i> concatenated to <i>str</i>.
 *
 *     "Hello from " + self.to_s   #=> "Hello from main"
 */

VALUE
rb_str_plus(VALUE str1, VALUE str2)
{
    VALUE str3;
    rb_encoding *enc;
    char *ptr1, *ptr2, *ptr3;
    long len1, len2;
    int termlen;

    StringValue(str2);
    enc = rb_enc_check_str(str1, str2);
    RSTRING_GETMEM(str1, ptr1, len1);
    RSTRING_GETMEM(str2, ptr2, len2);
    termlen = rb_enc_mbminlen(enc);
    str3 = str_new0(rb_cString, 0, len1+len2, termlen);
    ptr3 = RSTRING_PTR(str3);
    memcpy(ptr3, ptr1, len1);
    memcpy(ptr3+len1, ptr2, len2);
    TERM_FILL(&ptr3[len1+len2], termlen);

    FL_SET_RAW(str3, OBJ_TAINTED_RAW(str1) | OBJ_TAINTED_RAW(str2));
    ENCODING_CODERANGE_SET(str3, rb_enc_to_index(enc),
			   ENC_CODERANGE_AND(ENC_CODERANGE(str1), ENC_CODERANGE(str2)));
    RB_GC_GUARD(str1);
    RB_GC_GUARD(str2);
    return str3;
}

/*
 *  call-seq:
 *     str * integer   -> new_str
 *
 *  Copy --- Returns a new String containing +integer+ copies of the receiver.
 *  +integer+ must be greater than or equal to 0.
 *
 *     "Ho! " * 3   #=> "Ho! Ho! Ho! "
 *     "Ho! " * 0   #=> ""
 */

VALUE
rb_str_times(VALUE str, VALUE times)
{
    VALUE str2;
    long n, len;
    char *ptr2;
    int termlen;

    if (times == INT2FIX(1)) {
	return rb_str_dup(str);
    }
    if (times == INT2FIX(0)) {
	str2 = str_alloc(rb_obj_class(str));
	rb_enc_copy(str2, str);
	OBJ_INFECT(str2, str);
	return str2;
    }
    len = NUM2LONG(times);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative argument");
    }
    if (len && LONG_MAX/len <  RSTRING_LEN(str)) {
	rb_raise(rb_eArgError, "argument too big");
    }

    len *= RSTRING_LEN(str);
    termlen = TERM_LEN(str);
    str2 = str_new0(rb_obj_class(str), 0, len, termlen);
    ptr2 = RSTRING_PTR(str2);
    if (len) {
        n = RSTRING_LEN(str);
        memcpy(ptr2, RSTRING_PTR(str), n);
        while (n <= len/2) {
            memcpy(ptr2 + n, ptr2, n);
            n *= 2;
        }
        memcpy(ptr2 + n, ptr2, len-n);
    }
    STR_SET_LEN(str2, len);
    TERM_FILL(&ptr2[len], termlen);
    OBJ_INFECT(str2, str);
    rb_enc_cr_str_copy_for_substr(str2, str);

    return str2;
}

/*
 *  call-seq:
 *     str % arg   -> new_str
 *
 *  Format---Uses <i>str</i> as a format specification, and returns the result
 *  of applying it to <i>arg</i>. If the format specification contains more than
 *  one substitution, then <i>arg</i> must be an <code>Array</code> or <code>Hash</code>
 *  containing the values to be substituted. See <code>Kernel::sprintf</code> for
 *  details of the format string.
 *
 *     "%05d" % 123                              #=> "00123"
 *     "%-5s: %08x" % [ "ID", self.object_id ]   #=> "ID   : 200e14d6"
 *     "foo = %{foo}" % { :foo => 'bar' }        #=> "foo = bar"
 */

static VALUE
rb_str_format_m(VALUE str, VALUE arg)
{
    VALUE tmp = rb_check_array_type(arg);

    if (!NIL_P(tmp)) {
	VALUE rv = rb_str_format(RARRAY_LENINT(tmp), RARRAY_CONST_PTR(tmp), str);
	RB_GC_GUARD(tmp);
	return rv;
    }
    return rb_str_format(1, &arg, str);
}

static inline void
rb_check_lockedtmp(VALUE str)
{
    if (FL_TEST(str, STR_TMPLOCK)) {
	rb_raise(rb_eRuntimeError, "can't modify string; temporarily locked");
    }
}

static inline void
str_modifiable(VALUE str)
{
    rb_check_lockedtmp(str);
    rb_check_frozen(str);
}

static inline int
str_dependent_p(VALUE str)
{
    if (STR_EMBED_P(str) || !FL_TEST(str, STR_SHARED|STR_NOFREE)) {
	return 0;
    }
    else {
	return 1;
    }
}

static inline int
str_independent(VALUE str)
{
    str_modifiable(str);
    return !str_dependent_p(str);
}

static void
str_make_independent_expand(VALUE str, long len, long expand, const int termlen)
{
    char *ptr;
    const char *oldptr;
    long capa = len + expand;

    if (len > capa) len = capa;

    if (capa + termlen - 1 <= RSTRING_EMBED_LEN_MAX && !STR_EMBED_P(str)) {
	ptr = RSTRING(str)->as.heap.ptr;
	STR_SET_EMBED(str);
	memcpy(RSTRING(str)->as.ary, ptr, len);
	TERM_FILL(RSTRING(str)->as.ary + len, termlen);
	STR_SET_EMBED_LEN(str, len);
	return;
    }

    ptr = ALLOC_N(char, capa + termlen);
    oldptr = RSTRING_PTR(str);
    if (oldptr) {
	memcpy(ptr, oldptr, len);
    }
    STR_SET_NOEMBED(str);
    FL_UNSET(str, STR_SHARED|STR_NOFREE);
    TERM_FILL(ptr + len, termlen);
    RSTRING(str)->as.heap.ptr = ptr;
    RSTRING(str)->as.heap.len = len;
    RSTRING(str)->as.heap.aux.capa = capa;
}

void
rb_str_modify(VALUE str)
{
    if (!str_independent(str))
	str_make_independent(str);
    ENC_CODERANGE_CLEAR(str);
}

void
rb_str_modify_expand(VALUE str, long expand)
{
    int termlen;
    if (expand < 0) {
	rb_raise(rb_eArgError, "negative expanding string size");
    }
    termlen = TERM_LEN(str);
    if (!str_independent(str)) {
	long len = RSTRING_LEN(str);
	str_make_independent_expand(str, len, expand, termlen);
    }
    else if (expand > 0) {
	long len = RSTRING_LEN(str);
	long capa = len + expand;
	if (expand >= LONG_MAX - len - termlen) {
	    rb_raise(rb_eArgError, "string size too big");
	}
	if (!STR_EMBED_P(str)) {
	    REALLOC_N(RSTRING(str)->as.heap.ptr, char, capa + termlen);
	    RSTRING(str)->as.heap.aux.capa = capa;
	}
	else if (capa + termlen > RSTRING_EMBED_LEN_MAX + 1) {
	    str_make_independent_expand(str, len, expand, termlen);
	}
    }
    ENC_CODERANGE_CLEAR(str);
}

/* As rb_str_modify(), but don't clear coderange */
static void
str_modify_keep_cr(VALUE str)
{
    if (!str_independent(str))
	str_make_independent(str);
    if (ENC_CODERANGE(str) == ENC_CODERANGE_BROKEN)
	/* Force re-scan later */
	ENC_CODERANGE_CLEAR(str);
}

static inline void
str_discard(VALUE str)
{
    str_modifiable(str);
    if (!STR_EMBED_P(str) && !FL_TEST(str, STR_SHARED|STR_NOFREE)) {
	ruby_sized_xfree(STR_HEAP_PTR(str), STR_HEAP_SIZE(str));
	RSTRING(str)->as.heap.ptr = 0;
	RSTRING(str)->as.heap.len = 0;
    }
}

void
rb_must_asciicompat(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);
    if (!rb_enc_asciicompat(enc)) {
	rb_raise(rb_eEncCompatError, "ASCII incompatible encoding: %s", rb_enc_name(enc));
    }
}

VALUE
rb_string_value(volatile VALUE *ptr)
{
    VALUE s = *ptr;
    if (!RB_TYPE_P(s, T_STRING)) {
	s = rb_str_to_str(s);
	*ptr = s;
    }
    return s;
}

char *
rb_string_value_ptr(volatile VALUE *ptr)
{
    VALUE str = rb_string_value(ptr);
    return RSTRING_PTR(str);
}

static int
zero_filled(const char *s, int n)
{
    for (; n > 0; --n) {
	if (*s++) return 0;
    }
    return 1;
}

static const char *
str_null_char(const char *s, long len, const int minlen, rb_encoding *enc)
{
    const char *e = s + len;

    for (; s + minlen <= e; s += rb_enc_mbclen(s, e, enc)) {
	if (zero_filled(s, minlen)) return s;
    }
    return 0;
}

static char *
str_fill_term(VALUE str, char *s, long len, int termlen)
{
    long capa = str_capacity(str, termlen);

    /* This function assumes that (capa + termlen) bytes of memory
     * is allocated, like many other functions in this file.
     */

    if (capa < len) {
	rb_check_lockedtmp(str);
	str_make_independent_expand(str, len, 0L, termlen);
    }
    else if (str_dependent_p(str)) {
	if (!zero_filled(s + len, termlen))
	    str_make_independent_expand(str, len, 0L, termlen);
    }
    else {
	TERM_FILL(s + len, termlen);
    }
    return s;
}

void
rb_str_change_terminator_length(VALUE str, const int oldtermlen, const int termlen)
{
    long capa = str_capacity(str, oldtermlen);
    long len = RSTRING_LEN(str);

    if (capa < len + termlen - oldtermlen) {
	rb_check_lockedtmp(str);
	str_make_independent_expand(str, len, 0L, termlen);
    }
    else if (str_dependent_p(str)) {
	if (termlen > oldtermlen)
	    str_make_independent_expand(str, len, 0L, termlen);
    }
    else {
	if (!STR_EMBED_P(str)) {
	    /* modify capa instead of realloc */
	    assert(!FL_TEST((str), STR_SHARED));
	    RSTRING(str)->as.heap.aux.capa = capa - (termlen - oldtermlen);
	}
	if (termlen > oldtermlen) {
	    TERM_FILL(RSTRING_PTR(str) + len, termlen);
	}
    }

    return;
}

char *
rb_string_value_cstr(volatile VALUE *ptr)
{
    VALUE str = rb_string_value(ptr);
    char *s = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);
    rb_encoding *enc = rb_enc_get(str);
    const int minlen = rb_enc_mbminlen(enc);

    if (minlen > 1) {
	if (str_null_char(s, len, minlen, enc)) {
	    rb_raise(rb_eArgError, "string contains null char");
	}
	return str_fill_term(str, s, len, minlen);
    }
    if (!s || memchr(s, 0, len)) {
	rb_raise(rb_eArgError, "string contains null byte");
    }
    if (s[len]) {
	s = str_fill_term(str, s, len, minlen);
    }
    return s;
}

void
rb_str_fill_terminator(VALUE str, const int newminlen)
{
    char *s = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);
    str_fill_term(str, s, len, newminlen);
}

VALUE
rb_check_string_type(VALUE str)
{
    str = rb_check_convert_type(str, T_STRING, "String", "to_str");
    return str;
}

/*
 *  call-seq:
 *     String.try_convert(obj) -> string or nil
 *
 *  Try to convert <i>obj</i> into a String, using to_str method.
 *  Returns converted string or nil if <i>obj</i> cannot be converted
 *  for any reason.
 *
 *     String.try_convert("str")     #=> "str"
 *     String.try_convert(/re/)      #=> nil
 */
static VALUE
rb_str_s_try_convert(VALUE dummy, VALUE str)
{
    return rb_check_string_type(str);
}

static char*
str_nth_len(const char *p, const char *e, long *nthp, rb_encoding *enc)
{
    long nth = *nthp;
    if (rb_enc_mbmaxlen(enc) == 1) {
        p += nth;
    }
    else if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
        p += nth * rb_enc_mbmaxlen(enc);
    }
    else if (rb_enc_asciicompat(enc)) {
        const char *p2, *e2;
        int n;

        while (p < e && 0 < nth) {
            e2 = p + nth;
            if (e < e2) {
                *nthp = nth;
                return (char *)e;
            }
            if (ISASCII(*p)) {
                p2 = search_nonascii(p, e2);
                if (!p2) {
		    nth -= e2 - p;
		    *nthp = nth;
                    return (char *)e2;
                }
                nth -= p2 - p;
                p = p2;
            }
            n = rb_enc_mbclen(p, e, enc);
            p += n;
            nth--;
        }
        *nthp = nth;
        if (nth != 0) {
            return (char *)e;
        }
        return (char *)p;
    }
    else {
        while (p < e && nth--) {
            p += rb_enc_mbclen(p, e, enc);
        }
    }
    if (p > e) p = e;
    *nthp = nth;
    return (char*)p;
}

char*
rb_enc_nth(const char *p, const char *e, long nth, rb_encoding *enc)
{
    return str_nth_len(p, e, &nth, enc);
}

static char*
str_nth(const char *p, const char *e, long nth, rb_encoding *enc, int singlebyte)
{
    if (singlebyte)
	p += nth;
    else {
	p = str_nth_len(p, e, &nth, enc);
    }
    if (!p) return 0;
    if (p > e) p = e;
    return (char *)p;
}

/* char offset to byte offset */
static long
str_offset(const char *p, const char *e, long nth, rb_encoding *enc, int singlebyte)
{
    const char *pp = str_nth(p, e, nth, enc, singlebyte);
    if (!pp) return e - p;
    return pp - p;
}

long
rb_str_offset(VALUE str, long pos)
{
    return str_offset(RSTRING_PTR(str), RSTRING_END(str), pos,
		      STR_ENC_GET(str), single_byte_optimizable(str));
}

#ifdef NONASCII_MASK
static char *
str_utf8_nth(const char *p, const char *e, long *nthp)
{
    long nth = *nthp;
    if ((int)SIZEOF_VOIDP * 2 < e - p && (int)SIZEOF_VOIDP * 2 < nth) {
	const uintptr_t *s, *t;
	const uintptr_t lowbits = SIZEOF_VOIDP - 1;
	s = (const uintptr_t*)(~lowbits & ((uintptr_t)p + lowbits));
	t = (const uintptr_t*)(~lowbits & (uintptr_t)e);
	while (p < (const char *)s) {
	    if (is_utf8_lead_byte(*p)) nth--;
	    p++;
	}
	do {
	    nth -= count_utf8_lead_bytes_with_word(s);
	    s++;
	} while (s < t && (int)SIZEOF_VOIDP <= nth);
	p = (char *)s;
    }
    while (p < e) {
	if (is_utf8_lead_byte(*p)) {
	    if (nth == 0) break;
	    nth--;
	}
	p++;
    }
    *nthp = nth;
    return (char *)p;
}

static long
str_utf8_offset(const char *p, const char *e, long nth)
{
    const char *pp = str_utf8_nth(p, e, &nth);
    return pp - p;
}
#endif

/* byte offset to char offset */
long
rb_str_sublen(VALUE str, long pos)
{
    if (single_byte_optimizable(str) || pos < 0)
        return pos;
    else {
	char *p = RSTRING_PTR(str);
        return enc_strlen(p, p + pos, STR_ENC_GET(str), ENC_CODERANGE(str));
    }
}

VALUE
rb_str_subseq(VALUE str, long beg, long len)
{
    VALUE str2;

    if ((RSTRING_EMBED_LEN_MAX + 1 - TERM_LEN(str)) < len && SHARABLE_SUBSTRING_P(beg, len, RSTRING_LEN(str))) {
	long olen;
	str2 = rb_str_new_shared(rb_str_new_frozen(str));
	RSTRING(str2)->as.heap.ptr += beg;
	olen = RSTRING(str2)->as.heap.len;
	if (olen > len) RSTRING(str2)->as.heap.len = len;
    }
    else {
        str2 = rb_str_new_with_class(str, RSTRING_PTR(str)+beg, len);
	RB_GC_GUARD(str);
    }

    rb_enc_cr_str_copy_for_substr(str2, str);
    OBJ_INFECT(str2, str);

    return str2;
}

char *
rb_str_subpos(VALUE str, long beg, long *lenp)
{
    long len = *lenp;
    long slen = -1L;
    long blen = RSTRING_LEN(str);
    rb_encoding *enc = STR_ENC_GET(str);
    char *p, *s = RSTRING_PTR(str), *e = s + blen;

    if (len < 0) return 0;
    if (!blen) {
	len = 0;
    }
    if (single_byte_optimizable(str)) {
	if (beg > blen) return 0;
	if (beg < 0) {
	    beg += blen;
	    if (beg < 0) return 0;
	}
	if (beg + len > blen)
	    len = blen - beg;
	if (len < 0) return 0;
	p = s + beg;
	goto end;
    }
    if (beg < 0) {
	if (len > -beg) len = -beg;
	if (-beg * rb_enc_mbmaxlen(enc) < RSTRING_LEN(str) / 8) {
	    beg = -beg;
	    while (beg-- > len && (e = rb_enc_prev_char(s, e, e, enc)) != 0);
	    p = e;
	    if (!p) return 0;
	    while (len-- > 0 && (p = rb_enc_prev_char(s, p, e, enc)) != 0);
	    if (!p) return 0;
	    len = e - p;
	    goto end;
	}
	else {
	    slen = str_strlen(str, enc);
	    beg += slen;
	    if (beg < 0) return 0;
	    p = s + beg;
	    if (len == 0) goto end;
	}
    }
    else if (beg > 0 && beg > RSTRING_LEN(str)) {
	return 0;
    }
    if (len == 0) {
	if (beg > str_strlen(str, enc)) return 0; /* str's enc */
	p = s + beg;
    }
#ifdef NONASCII_MASK
    else if (ENC_CODERANGE(str) == ENC_CODERANGE_VALID &&
        enc == rb_utf8_encoding()) {
        p = str_utf8_nth(s, e, &beg);
        if (beg > 0) return 0;
        len = str_utf8_offset(p, e, len);
    }
#endif
    else if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
	int char_sz = rb_enc_mbmaxlen(enc);

	p = s + beg * char_sz;
	if (p > e) {
	    return 0;
	}
        else if (len * char_sz > e - p)
            len = e - p;
        else
	    len *= char_sz;
    }
    else if ((p = str_nth_len(s, e, &beg, enc)) == e) {
	if (beg > 0) return 0;
	len = 0;
    }
    else {
	len = str_offset(p, e, len, enc, 0);
    }
  end:
    *lenp = len;
    RB_GC_GUARD(str);
    return p;
}

VALUE
rb_str_substr(VALUE str, long beg, long len)
{
    VALUE str2;
    char *p = rb_str_subpos(str, beg, &len);

    if (!p) return Qnil;
    if (len > (RSTRING_EMBED_LEN_MAX + 1 - TERM_LEN(str)) && SHARABLE_SUBSTRING_P(p, len, RSTRING_END(str))) {
	long ofs = p - RSTRING_PTR(str);
	str2 = rb_str_new_frozen(str);
	str2 = str_new_shared(rb_obj_class(str2), str2);
	RSTRING(str2)->as.heap.ptr += ofs;
	RSTRING(str2)->as.heap.len = len;
    }
    else {
	str2 = rb_str_new_with_class(str, p, len);
	OBJ_INFECT(str2, str);
	RB_GC_GUARD(str);
    }
    rb_enc_cr_str_copy_for_substr(str2, str);

    return str2;
}

VALUE
rb_str_freeze(VALUE str)
{
    if (OBJ_FROZEN(str)) return str;
    rb_str_resize(str, RSTRING_LEN(str));
    return rb_obj_freeze(str);
}


/*
 * call-seq:
 *   +str  -> str (mutable)
 *
 * If the string is frozen, then return duplicated mutable string.
 *
 * If the string is not frozen, then return the string itself.
 */
static VALUE
str_uplus(VALUE str)
{
    if (OBJ_FROZEN(str)) {
	return rb_str_dup(str);
    }
    else {
	return str;
    }
}

/*
 * call-seq:
 *   -str  -> str (frozen)
 *
 * If the string is frozen, then return the string itself.
 *
 * If the string is not frozen, then duplicate the string
 * freeze it and return it.
 */
static VALUE
str_uminus(VALUE str)
{
    if (OBJ_FROZEN(str)) {
	return str;
    }
    else {
	return rb_str_freeze(rb_str_dup(str));
    }
}

RUBY_ALIAS_FUNCTION(rb_str_dup_frozen(VALUE str), rb_str_new_frozen, (str))
#define rb_str_dup_frozen rb_str_new_frozen

VALUE
rb_str_locktmp(VALUE str)
{
    if (FL_TEST(str, STR_TMPLOCK)) {
	rb_raise(rb_eRuntimeError, "temporal locking already locked string");
    }
    FL_SET(str, STR_TMPLOCK);
    return str;
}

VALUE
rb_str_unlocktmp(VALUE str)
{
    if (!FL_TEST(str, STR_TMPLOCK)) {
	rb_raise(rb_eRuntimeError, "temporal unlocking already unlocked string");
    }
    FL_UNSET(str, STR_TMPLOCK);
    return str;
}

RUBY_FUNC_EXPORTED VALUE
rb_str_locktmp_ensure(VALUE str, VALUE (*func)(VALUE), VALUE arg)
{
    rb_str_locktmp(str);
    return rb_ensure(func, arg, rb_str_unlocktmp, str);
}

void
rb_str_set_len(VALUE str, long len)
{
    long capa;
    const int termlen = TERM_LEN(str);

    str_modifiable(str);
    if (STR_SHARED_P(str)) {
	rb_raise(rb_eRuntimeError, "can't set length of shared string");
    }
    if (len + termlen - 1 > (capa = (long)rb_str_capacity(str))) {
	rb_bug("probable buffer overflow: %ld for %ld", len, capa);
    }
    STR_SET_LEN(str, len);
    TERM_FILL(&RSTRING_PTR(str)[len], termlen);
}

VALUE
rb_str_resize(VALUE str, long len)
{
    long slen;
    int independent;

    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    independent = str_independent(str);
    ENC_CODERANGE_CLEAR(str);
    slen = RSTRING_LEN(str);

    {
	long capa;
	const int termlen = TERM_LEN(str);
	if (STR_EMBED_P(str)) {
	    if (len == slen) return str;
	    if (len + termlen <= RSTRING_EMBED_LEN_MAX + 1) {
		STR_SET_EMBED_LEN(str, len);
		TERM_FILL(RSTRING(str)->as.ary + len, termlen);
		return str;
	    }
	    str_make_independent_expand(str, slen, len - slen, termlen);
	}
	else if (len + termlen <= RSTRING_EMBED_LEN_MAX + 1) {
	    char *ptr = STR_HEAP_PTR(str);
	    STR_SET_EMBED(str);
	    if (slen > len) slen = len;
	    if (slen > 0) MEMCPY(RSTRING(str)->as.ary, ptr, char, slen);
	    TERM_FILL(RSTRING(str)->as.ary + len, termlen);
	    STR_SET_EMBED_LEN(str, len);
	    if (independent) ruby_xfree(ptr);
	    return str;
	}
	else if (!independent) {
	    if (len == slen) return str;
	    str_make_independent_expand(str, slen, len - slen, termlen);
	}
	else if ((capa = RSTRING(str)->as.heap.aux.capa) < len ||
		 (capa - len) > (len < 1024 ? len : 1024)) {
	    REALLOC_N(RSTRING(str)->as.heap.ptr, char, len + termlen);
	    RSTRING(str)->as.heap.aux.capa = len;
	}
	else if (len == slen) return str;
	RSTRING(str)->as.heap.len = len;
	TERM_FILL(RSTRING(str)->as.heap.ptr + len, termlen); /* sentinel */
    }
    return str;
}

static VALUE
str_buf_cat(VALUE str, const char *ptr, long len)
{
    long capa, total, olen, off = -1;
    char *sptr;
    const int termlen = TERM_LEN(str);

    RSTRING_GETMEM(str, sptr, olen);
    if (ptr >= sptr && ptr <= sptr + olen) {
        off = ptr - sptr;
    }
    rb_str_modify(str);
    if (len == 0) return 0;
    if (STR_EMBED_P(str)) {
	capa = RSTRING_EMBED_LEN_MAX + 1 - termlen;
	sptr = RSTRING(str)->as.ary;
	olen = RSTRING_EMBED_LEN(str);
    }
    else {
	capa = RSTRING(str)->as.heap.aux.capa;
	sptr = RSTRING(str)->as.heap.ptr;
	olen = RSTRING(str)->as.heap.len;
    }
    if (olen >= LONG_MAX - len) {
	rb_raise(rb_eArgError, "string sizes too big");
    }
    total = olen + len;
    if (capa <= total) {
	if (LIKELY(capa > 0)) {
	    while (total > capa) {
		if (capa > LONG_MAX / 2) {
		    capa = (total + 4095) / 4096 * 4096;
		    break;
		}
		capa = 2 * capa;
	    }
	}
	else {
	    capa = total;
	}
	RESIZE_CAPA_TERM(str, capa, termlen);
	sptr = RSTRING_PTR(str);
    }
    if (off != -1) {
        ptr = sptr + off;
    }
    memcpy(sptr + olen, ptr, len);
    STR_SET_LEN(str, total);
    TERM_FILL(sptr + total, termlen); /* sentinel */

    return str;
}

#define str_buf_cat2(str, ptr) str_buf_cat((str), (ptr), strlen(ptr))

VALUE
rb_str_cat(VALUE str, const char *ptr, long len)
{
    if (len == 0) return str;
    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }
    return str_buf_cat(str, ptr, len);
}

VALUE
rb_str_cat_cstr(VALUE str, const char *ptr)
{
    must_not_null(ptr);
    return rb_str_buf_cat(str, ptr, strlen(ptr));
}

RUBY_ALIAS_FUNCTION(rb_str_buf_cat(VALUE str, const char *ptr, long len), rb_str_cat, (str, ptr, len))
RUBY_ALIAS_FUNCTION(rb_str_buf_cat2(VALUE str, const char *ptr), rb_str_cat_cstr, (str, ptr))
RUBY_ALIAS_FUNCTION(rb_str_cat2(VALUE str, const char *ptr), rb_str_cat_cstr, (str, ptr))

static VALUE
rb_enc_cr_str_buf_cat(VALUE str, const char *ptr, long len,
    int ptr_encindex, int ptr_cr, int *ptr_cr_ret)
{
    int str_encindex = ENCODING_GET(str);
    int res_encindex;
    int str_cr, res_cr;
    rb_encoding *str_enc, *ptr_enc;

    str_cr = RSTRING_LEN(str) ? ENC_CODERANGE(str) : ENC_CODERANGE_7BIT;

    if (str_encindex == ptr_encindex) {
	if (str_cr != ENC_CODERANGE_UNKNOWN && ptr_cr == ENC_CODERANGE_UNKNOWN) {
            ptr_cr = coderange_scan(ptr, len, rb_enc_from_index(ptr_encindex));
        }
    }
    else {
	str_enc = rb_enc_from_index(str_encindex);
	ptr_enc = rb_enc_from_index(ptr_encindex);
        if (!rb_enc_asciicompat(str_enc) || !rb_enc_asciicompat(ptr_enc)) {
            if (len == 0)
                return str;
            if (RSTRING_LEN(str) == 0) {
                rb_str_buf_cat(str, ptr, len);
                ENCODING_CODERANGE_SET(str, ptr_encindex, ptr_cr);
                return str;
            }
            goto incompatible;
        }
	if (ptr_cr == ENC_CODERANGE_UNKNOWN) {
	    ptr_cr = coderange_scan(ptr, len, ptr_enc);
	}
        if (str_cr == ENC_CODERANGE_UNKNOWN) {
            if (ENCODING_IS_ASCII8BIT(str) || ptr_cr != ENC_CODERANGE_7BIT) {
                str_cr = rb_enc_str_coderange(str);
            }
        }
    }
    if (ptr_cr_ret)
        *ptr_cr_ret = ptr_cr;

    if (str_encindex != ptr_encindex &&
        str_cr != ENC_CODERANGE_7BIT &&
        ptr_cr != ENC_CODERANGE_7BIT) {
	str_enc = rb_enc_from_index(str_encindex);
	ptr_enc = rb_enc_from_index(ptr_encindex);
      incompatible:
        rb_raise(rb_eEncCompatError, "incompatible character encodings: %s and %s",
		 rb_enc_name(str_enc), rb_enc_name(ptr_enc));
    }

    if (str_cr == ENC_CODERANGE_UNKNOWN) {
        res_encindex = str_encindex;
        res_cr = ENC_CODERANGE_UNKNOWN;
    }
    else if (str_cr == ENC_CODERANGE_7BIT) {
        if (ptr_cr == ENC_CODERANGE_7BIT) {
            res_encindex = str_encindex;
            res_cr = ENC_CODERANGE_7BIT;
        }
        else {
            res_encindex = ptr_encindex;
            res_cr = ptr_cr;
        }
    }
    else if (str_cr == ENC_CODERANGE_VALID) {
        res_encindex = str_encindex;
	if (ENC_CODERANGE_CLEAN_P(ptr_cr))
	    res_cr = str_cr;
	else
	    res_cr = ptr_cr;
    }
    else { /* str_cr == ENC_CODERANGE_BROKEN */
        res_encindex = str_encindex;
        res_cr = str_cr;
        if (0 < len) res_cr = ENC_CODERANGE_UNKNOWN;
    }

    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }
    str_buf_cat(str, ptr, len);
    ENCODING_CODERANGE_SET(str, res_encindex, res_cr);
    return str;
}

VALUE
rb_enc_str_buf_cat(VALUE str, const char *ptr, long len, rb_encoding *ptr_enc)
{
    return rb_enc_cr_str_buf_cat(str, ptr, len,
        rb_enc_to_index(ptr_enc), ENC_CODERANGE_UNKNOWN, NULL);
}

VALUE
rb_str_buf_cat_ascii(VALUE str, const char *ptr)
{
    /* ptr must reference NUL terminated ASCII string. */
    int encindex = ENCODING_GET(str);
    rb_encoding *enc = rb_enc_from_index(encindex);
    if (rb_enc_asciicompat(enc)) {
        return rb_enc_cr_str_buf_cat(str, ptr, strlen(ptr),
            encindex, ENC_CODERANGE_7BIT, 0);
    }
    else {
        char *buf = ALLOCA_N(char, rb_enc_mbmaxlen(enc));
        while (*ptr) {
            unsigned int c = (unsigned char)*ptr;
            int len = rb_enc_codelen(c, enc);
            rb_enc_mbcput(c, buf, enc);
            rb_enc_cr_str_buf_cat(str, buf, len,
                encindex, ENC_CODERANGE_VALID, 0);
            ptr++;
        }
        return str;
    }
}

VALUE
rb_str_buf_append(VALUE str, VALUE str2)
{
    int str2_cr;

    str2_cr = ENC_CODERANGE(str2);

    rb_enc_cr_str_buf_cat(str, RSTRING_PTR(str2), RSTRING_LEN(str2),
        ENCODING_GET(str2), str2_cr, &str2_cr);

    OBJ_INFECT(str, str2);
    ENC_CODERANGE_SET(str2, str2_cr);

    return str;
}

VALUE
rb_str_append(VALUE str, VALUE str2)
{
    StringValue(str2);
    return rb_str_buf_append(str, str2);
}

VALUE
rb_str_append_literal(VALUE str, VALUE str2)
{
    int encidx = rb_enc_get_index(str2);
    rb_str_buf_append(str, str2);
    if (encidx != ENCINDEX_US_ASCII) {
	if (rb_enc_get_index(str) == ENCINDEX_US_ASCII)
	    rb_enc_associate_index(str, encidx);
    }
    return str;
}

/*
 *  call-seq:
 *     str << integer       -> str
 *     str.concat(integer)  -> str
 *     str << obj           -> str
 *     str.concat(obj)      -> str
 *
 *  Append---Concatenates the given object to <i>str</i>. If the object is a
 *  <code>Integer</code>, it is considered as a codepoint, and is converted
 *  to a character before concatenation.
 *
 *     a = "hello "
 *     a << "world"   #=> "hello world"
 *     a.concat(33)   #=> "hello world!"
 */

VALUE
rb_str_concat(VALUE str1, VALUE str2)
{
    unsigned int code;
    rb_encoding *enc = STR_ENC_GET(str1);

    if (FIXNUM_P(str2) || RB_TYPE_P(str2, T_BIGNUM)) {
	if (rb_num_to_uint(str2, &code) == 0) {
	}
	else if (FIXNUM_P(str2)) {
	    rb_raise(rb_eRangeError, "%ld out of char range", FIX2LONG(str2));
	}
	else {
	    rb_raise(rb_eRangeError, "bignum out of char range");
	}
    }
    else {
	return rb_str_append(str1, str2);
    }

    if (enc == rb_usascii_encoding()) {
	/* US-ASCII automatically extended to ASCII-8BIT */
	char buf[1];
	buf[0] = (char)code;
	if (code > 0xFF) {
	    rb_raise(rb_eRangeError, "%u out of char range", code);
	}
	rb_str_cat(str1, buf, 1);
	if (code > 127) {
	    rb_enc_associate(str1, rb_ascii8bit_encoding());
	    ENC_CODERANGE_SET(str1, ENC_CODERANGE_VALID);
	}
    }
    else {
	long pos = RSTRING_LEN(str1);
	int cr = ENC_CODERANGE(str1);
	int len;
	char *buf;

	switch (len = rb_enc_codelen(code, enc)) {
	  case ONIGERR_INVALID_CODE_POINT_VALUE:
	    rb_raise(rb_eRangeError, "invalid codepoint 0x%X in %s", code, rb_enc_name(enc));
	    break;
	  case ONIGERR_TOO_BIG_WIDE_CHAR_VALUE:
	  case 0:
	    rb_raise(rb_eRangeError, "%u out of char range", code);
	    break;
	}
	buf = ALLOCA_N(char, len + 1);
	rb_enc_mbcput(code, buf, enc);
	if (rb_enc_precise_mbclen(buf, buf + len + 1, enc) != len) {
	    rb_raise(rb_eRangeError, "invalid codepoint 0x%X in %s", code, rb_enc_name(enc));
	}
	rb_str_resize(str1, pos+len);
	memcpy(RSTRING_PTR(str1) + pos, buf, len);
	if (cr == ENC_CODERANGE_7BIT && code > 127)
	    cr = ENC_CODERANGE_VALID;
	ENC_CODERANGE_SET(str1, cr);
    }
    return str1;
}

/*
 *  call-seq:
 *     str.prepend(other_str)  -> str
 *
 *  Prepend---Prepend the given string to <i>str</i>.
 *
 *     a = "world"
 *     a.prepend("hello ") #=> "hello world"
 *     a                   #=> "hello world"
 */

static VALUE
rb_str_prepend(VALUE str, VALUE str2)
{
    StringValue(str2);
    StringValue(str);
    rb_str_update(str, 0L, 0L, str2);
    return str;
}

st_index_t
rb_str_hash(VALUE str)
{
    int e = ENCODING_GET(str);
    if (e && rb_enc_str_coderange(str) == ENC_CODERANGE_7BIT) {
	e = 0;
    }
    return rb_memhash((const void *)RSTRING_PTR(str), RSTRING_LEN(str)) ^ e;
}

int
rb_str_hash_cmp(VALUE str1, VALUE str2)
{
    long len1, len2;
    const char *ptr1, *ptr2;
    RSTRING_GETMEM(str1, ptr1, len1);
    RSTRING_GETMEM(str2, ptr2, len2);
    return (len1 != len2 ||
	    !rb_str_comparable(str1, str2) ||
	    memcmp(ptr1, ptr2, len1) != 0);
}

/*
 * call-seq:
 *    str.hash   -> fixnum
 *
 * Return a hash based on the string's length, content and encoding.
 *
 * See also Object#hash.
 */

static VALUE
rb_str_hash_m(VALUE str)
{
    st_index_t hval = rb_str_hash(str);
    return INT2FIX(hval);
}

#define lesser(a,b) (((a)>(b))?(b):(a))

int
rb_str_comparable(VALUE str1, VALUE str2)
{
    int idx1, idx2;
    int rc1, rc2;

    if (RSTRING_LEN(str1) == 0) return TRUE;
    if (RSTRING_LEN(str2) == 0) return TRUE;
    idx1 = ENCODING_GET(str1);
    idx2 = ENCODING_GET(str2);
    if (idx1 == idx2) return TRUE;
    rc1 = rb_enc_str_coderange(str1);
    rc2 = rb_enc_str_coderange(str2);
    if (rc1 == ENC_CODERANGE_7BIT) {
	if (rc2 == ENC_CODERANGE_7BIT) return TRUE;
	if (rb_enc_asciicompat(rb_enc_from_index(idx2)))
	    return TRUE;
    }
    if (rc2 == ENC_CODERANGE_7BIT) {
	if (rb_enc_asciicompat(rb_enc_from_index(idx1)))
	    return TRUE;
    }
    return FALSE;
}

int
rb_str_cmp(VALUE str1, VALUE str2)
{
    long len1, len2;
    const char *ptr1, *ptr2;
    int retval;

    if (str1 == str2) return 0;
    RSTRING_GETMEM(str1, ptr1, len1);
    RSTRING_GETMEM(str2, ptr2, len2);
    if (ptr1 == ptr2 || (retval = memcmp(ptr1, ptr2, lesser(len1, len2))) == 0) {
	if (len1 == len2) {
	    if (!rb_str_comparable(str1, str2)) {
		if (ENCODING_GET(str1) > ENCODING_GET(str2))
		    return 1;
		return -1;
	    }
	    return 0;
	}
	if (len1 > len2) return 1;
	return -1;
    }
    if (retval > 0) return 1;
    return -1;
}

/* expect tail call optimization */
static VALUE
str_eql(const VALUE str1, const VALUE str2)
{
    const long len = RSTRING_LEN(str1);
    const char *ptr1, *ptr2;

    if (len != RSTRING_LEN(str2)) return Qfalse;
    if (!rb_str_comparable(str1, str2)) return Qfalse;
    if ((ptr1 = RSTRING_PTR(str1)) == (ptr2 = RSTRING_PTR(str2)))
	return Qtrue;
    if (memcmp(ptr1, ptr2, len) == 0)
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     str == obj    -> true or false
 *     str === obj   -> true or false
 *
 *  === Equality
 *
 *  Returns whether +str+ == +obj+, similar to Object#==.
 *
 *  If +obj+ is not an instance of String but responds to +to_str+, then the
 *  two strings are compared using case equality Object#===.
 *
 *  Otherwise, returns similarly to String#eql?, comparing length and content.
 */

VALUE
rb_str_equal(VALUE str1, VALUE str2)
{
    if (str1 == str2) return Qtrue;
    if (!RB_TYPE_P(str2, T_STRING)) {
	if (!rb_respond_to(str2, idTo_str)) {
	    return Qfalse;
	}
	return rb_equal(str2, str1);
    }
    return str_eql(str1, str2);
}

/*
 * call-seq:
 *   str.eql?(other)   -> true or false
 *
 * Two strings are equal if they have the same length and content.
 */

static VALUE
rb_str_eql(VALUE str1, VALUE str2)
{
    if (str1 == str2) return Qtrue;
    if (!RB_TYPE_P(str2, T_STRING)) return Qfalse;
    return str_eql(str1, str2);
}

/*
 *  call-seq:
 *     string <=> other_string   -> -1, 0, +1 or nil
 *
 *
 *  Comparison---Returns -1, 0, +1 or nil depending on whether +string+ is less
 *  than, equal to, or greater than +other_string+.
 *
 *  +nil+ is returned if the two values are incomparable.
 *
 *  If the strings are of different lengths, and the strings are equal when
 *  compared up to the shortest length, then the longer string is considered
 *  greater than the shorter one.
 *
 *  <code><=></code> is the basis for the methods <code><</code>,
 *  <code><=</code>, <code>></code>, <code>>=</code>, and
 *  <code>between?</code>, included from module Comparable. The method
 *  String#== does not use Comparable#==.
 *
 *     "abcdef" <=> "abcde"     #=> 1
 *     "abcdef" <=> "abcdef"    #=> 0
 *     "abcdef" <=> "abcdefg"   #=> -1
 *     "abcdef" <=> "ABCDEF"    #=> 1
 *     "abcdef" <=> 1           #=> nil
 */

static VALUE
rb_str_cmp_m(VALUE str1, VALUE str2)
{
    int result;

    if (!RB_TYPE_P(str2, T_STRING)) {
	VALUE tmp = rb_check_funcall(str2, idTo_str, 0, 0);
	if (RB_TYPE_P(tmp, T_STRING)) {
	    result = rb_str_cmp(str1, tmp);
	}
	else {
	    return rb_invcmp(str1, str2);
	}
    }
    else {
	result = rb_str_cmp(str1, str2);
    }
    return INT2FIX(result);
}

/*
 *  call-seq:
 *     str.casecmp(other_str)   -> -1, 0, +1 or nil
 *
 *  Case-insensitive version of <code>String#<=></code>.
 *
 *     "abcdef".casecmp("abcde")     #=> 1
 *     "aBcDeF".casecmp("abcdef")    #=> 0
 *     "abcdef".casecmp("abcdefg")   #=> -1
 *     "abcdef".casecmp("ABCDEF")    #=> 0
 */

static VALUE
rb_str_casecmp(VALUE str1, VALUE str2)
{
    long len;
    rb_encoding *enc;
    char *p1, *p1end, *p2, *p2end;

    StringValue(str2);
    enc = rb_enc_compatible(str1, str2);
    if (!enc) {
	return Qnil;
    }

    p1 = RSTRING_PTR(str1); p1end = RSTRING_END(str1);
    p2 = RSTRING_PTR(str2); p2end = RSTRING_END(str2);
    if (single_byte_optimizable(str1) && single_byte_optimizable(str2)) {
	while (p1 < p1end && p2 < p2end) {
	    if (*p1 != *p2) {
		unsigned int c1 = TOUPPER(*p1 & 0xff);
		unsigned int c2 = TOUPPER(*p2 & 0xff);
                if (c1 != c2)
                    return INT2FIX(c1 < c2 ? -1 : 1);
	    }
	    p1++;
	    p2++;
	}
    }
    else {
	while (p1 < p1end && p2 < p2end) {
            int l1, c1 = rb_enc_ascget(p1, p1end, &l1, enc);
            int l2, c2 = rb_enc_ascget(p2, p2end, &l2, enc);

            if (0 <= c1 && 0 <= c2) {
                c1 = TOUPPER(c1);
                c2 = TOUPPER(c2);
                if (c1 != c2)
                    return INT2FIX(c1 < c2 ? -1 : 1);
            }
            else {
                int r;
                l1 = rb_enc_mbclen(p1, p1end, enc);
                l2 = rb_enc_mbclen(p2, p2end, enc);
                len = l1 < l2 ? l1 : l2;
                r = memcmp(p1, p2, len);
                if (r != 0)
                    return INT2FIX(r < 0 ? -1 : 1);
                if (l1 != l2)
                    return INT2FIX(l1 < l2 ? -1 : 1);
            }
	    p1 += l1;
	    p2 += l2;
	}
    }
    if (RSTRING_LEN(str1) == RSTRING_LEN(str2)) return INT2FIX(0);
    if (RSTRING_LEN(str1) > RSTRING_LEN(str2)) return INT2FIX(1);
    return INT2FIX(-1);
}

#define rb_str_index(str, sub, offset) rb_strseq_index(str, sub, offset, 0)

static long
rb_strseq_index(VALUE str, VALUE sub, long offset, int in_byte)
{
    const char *s, *sptr, *e;
    long pos, len, slen;
    int single_byte = single_byte_optimizable(str);
    rb_encoding *enc;

    enc = rb_enc_check(str, sub);
    if (is_broken_string(sub)) return -1;

    len = (in_byte || single_byte) ? RSTRING_LEN(str) : str_strlen(str, enc); /* rb_enc_check */
    slen = in_byte ? RSTRING_LEN(sub) : str_strlen(sub, enc); /* rb_enc_check */
    if (offset < 0) {
	offset += len;
	if (offset < 0) return -1;
    }
    if (len - offset < slen) return -1;

    s = RSTRING_PTR(str);
    e = RSTRING_END(str);
    if (offset) {
	if (!in_byte) offset = str_offset(s, e, offset, enc, single_byte);
	s += offset;
    }
    if (slen == 0) return offset;
    /* need proceed one character at a time */
    sptr = RSTRING_PTR(sub);
    slen = RSTRING_LEN(sub);
    len = RSTRING_LEN(str) - offset;
    for (;;) {
	const char *t;
	pos = rb_memsearch(sptr, slen, s, len, enc);
	if (pos < 0) return pos;
	t = rb_enc_right_char_head(s, s+pos, e, enc);
	if (t == s + pos) break;
	len -= t - s;
	if (len <= 0) return -1;
	offset += t - s;
	s = t;
    }
    return pos + offset;
}


/*
 *  call-seq:
 *     str.index(substring [, offset])   -> fixnum or nil
 *     str.index(regexp [, offset])      -> fixnum or nil
 *
 *  Returns the index of the first occurrence of the given <i>substring</i> or
 *  pattern (<i>regexp</i>) in <i>str</i>. Returns <code>nil</code> if not
 *  found. If the second parameter is present, it specifies the position in the
 *  string to begin the search.
 *
 *     "hello".index('e')             #=> 1
 *     "hello".index('lo')            #=> 3
 *     "hello".index('a')             #=> nil
 *     "hello".index(?e)              #=> 1
 *     "hello".index(/[aeiou]/, -3)   #=> 4
 */

static VALUE
rb_str_index_m(int argc, VALUE *argv, VALUE str)
{
    VALUE sub;
    VALUE initpos;
    long pos;

    if (rb_scan_args(argc, argv, "11", &sub, &initpos) == 2) {
	pos = NUM2LONG(initpos);
    }
    else {
	pos = 0;
    }
    if (pos < 0) {
	pos += str_strlen(str, NULL);
	if (pos < 0) {
	    if (RB_TYPE_P(sub, T_REGEXP)) {
		rb_backref_set(Qnil);
	    }
	    return Qnil;
	}
    }

    if (SPECIAL_CONST_P(sub)) goto generic;
    switch (BUILTIN_TYPE(sub)) {
      case T_REGEXP:
	if (pos > str_strlen(str, NULL))
	    return Qnil;
	pos = str_offset(RSTRING_PTR(str), RSTRING_END(str), pos,
			 rb_enc_check(str, sub), single_byte_optimizable(str));

	pos = rb_reg_search(sub, str, pos, 0);
	pos = rb_str_sublen(str, pos);
	break;

      generic:
      default: {
	VALUE tmp;

	tmp = rb_check_string_type(sub);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sub));
	}
	sub = tmp;
      }
	/* fall through */
      case T_STRING:
	pos = rb_str_index(str, sub, pos);
	pos = rb_str_sublen(str, pos);
	break;
    }

    if (pos == -1) return Qnil;
    return LONG2NUM(pos);
}

#ifdef HAVE_MEMRCHR
static long
str_rindex(VALUE str, VALUE sub, const char *s, long pos, rb_encoding *enc)
{
    char *hit, *adjusted;
    int c;
    long slen, searchlen;
    char *sbeg, *e, *t;

    slen = RSTRING_LEN(sub);
    if (slen == 0) return pos;
    sbeg = RSTRING_PTR(str);
    e = RSTRING_END(str);
    t = RSTRING_PTR(sub);
    c = *t & 0xff;
    searchlen = s - sbeg + 1;

    do {
	hit = memrchr(sbeg, c, searchlen);
	if (!hit) break;
	adjusted = rb_enc_left_char_head(sbeg, hit, e, enc);
	if (hit != adjusted) {
	    searchlen = adjusted - sbeg;
	    continue;
	}
	if (memcmp(hit, t, slen) == 0)
	    return rb_str_sublen(str, hit - sbeg);
	searchlen = adjusted - sbeg;
    } while (searchlen > 0);

    return -1;
}
#else
static long
str_rindex(VALUE str, VALUE sub, const char *s, long pos, rb_encoding *enc)
{
    long slen;
    char *sbeg, *e, *t;

    sbeg = RSTRING_PTR(str);
    e = RSTRING_END(str);
    t = RSTRING_PTR(sub);
    slen = RSTRING_LEN(sub);

    while (s) {
	if (memcmp(s, t, slen) == 0) {
	    return pos;
	}
	if (pos == 0) break;
	pos--;
	s = rb_enc_prev_char(sbeg, s, e, enc);
    }

    return -1;
}
#endif

static long
rb_str_rindex(VALUE str, VALUE sub, long pos)
{
    long len, slen;
    char *sbeg, *s;
    rb_encoding *enc;
    int singlebyte;

    enc = rb_enc_check(str, sub);
    if (is_broken_string(sub)) return -1;
    singlebyte = single_byte_optimizable(str);
    len = singlebyte ? RSTRING_LEN(str) : str_strlen(str, enc); /* rb_enc_check */
    slen = str_strlen(sub, enc); /* rb_enc_check */

    /* substring longer than string */
    if (len < slen) return -1;
    if (len - pos < slen) pos = len - slen;
    if (len == 0) return pos;

    sbeg = RSTRING_PTR(str);

    if (pos == 0) {
	if (memcmp(sbeg, RSTRING_PTR(sub), RSTRING_LEN(sub)) == 0)
	    return 0;
	else
	    return -1;
    }

    s = str_nth(sbeg, RSTRING_END(str), pos, enc, singlebyte);
    return str_rindex(str, sub, s, pos, enc);
}


/*
 *  call-seq:
 *     str.rindex(substring [, fixnum])   -> fixnum or nil
 *     str.rindex(regexp [, fixnum])   -> fixnum or nil
 *
 *  Returns the index of the last occurrence of the given <i>substring</i> or
 *  pattern (<i>regexp</i>) in <i>str</i>. Returns <code>nil</code> if not
 *  found. If the second parameter is present, it specifies the position in the
 *  string to end the search---characters beyond this point will not be
 *  considered.
 *
 *     "hello".rindex('e')             #=> 1
 *     "hello".rindex('l')             #=> 3
 *     "hello".rindex('a')             #=> nil
 *     "hello".rindex(?e)              #=> 1
 *     "hello".rindex(/[aeiou]/, -2)   #=> 1
 */

static VALUE
rb_str_rindex_m(int argc, VALUE *argv, VALUE str)
{
    VALUE sub;
    VALUE vpos;
    rb_encoding *enc = STR_ENC_GET(str);
    long pos, len = str_strlen(str, enc); /* str's enc */

    if (rb_scan_args(argc, argv, "11", &sub, &vpos) == 2) {
	pos = NUM2LONG(vpos);
	if (pos < 0) {
	    pos += len;
	    if (pos < 0) {
		if (RB_TYPE_P(sub, T_REGEXP)) {
		    rb_backref_set(Qnil);
		}
		return Qnil;
	    }
	}
	if (pos > len) pos = len;
    }
    else {
	pos = len;
    }

    if (SPECIAL_CONST_P(sub)) goto generic;
    switch (BUILTIN_TYPE(sub)) {
      case T_REGEXP:
	/* enc = rb_get_check(str, sub); */
	pos = str_offset(RSTRING_PTR(str), RSTRING_END(str), pos,
			 enc, single_byte_optimizable(str));

	if (!RREGEXP(sub)->ptr || RREGEXP_SRC_LEN(sub)) {
	    pos = rb_reg_search(sub, str, pos, 1);
	    pos = rb_str_sublen(str, pos);
	}
	if (pos >= 0) return LONG2NUM(pos);
	break;

      generic:
      default: {
	VALUE tmp;

	tmp = rb_check_string_type(sub);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sub));
	}
	sub = tmp;
      }
	/* fall through */
      case T_STRING:
	pos = rb_str_rindex(str, sub, pos);
	if (pos >= 0) return LONG2NUM(pos);
	break;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     str =~ obj   -> fixnum or nil
 *
 *  Match---If <i>obj</i> is a <code>Regexp</code>, use it as a pattern to match
 *  against <i>str</i>,and returns the position the match starts, or
 *  <code>nil</code> if there is no match. Otherwise, invokes
 *  <i>obj.=~</i>, passing <i>str</i> as an argument. The default
 *  <code>=~</code> in <code>Object</code> returns <code>nil</code>.
 *
 *  Note: <code>str =~ regexp</code> is not the same as
 *  <code>regexp =~ str</code>. Strings captured from named capture groups
 *  are assigned to local variables only in the second case.
 *
 *     "cat o' 9 tails" =~ /\d/   #=> 7
 *     "cat o' 9 tails" =~ 9      #=> nil
 */

static VALUE
rb_str_match(VALUE x, VALUE y)
{
    if (SPECIAL_CONST_P(y)) goto generic;
    switch (BUILTIN_TYPE(y)) {
      case T_STRING:
	rb_raise(rb_eTypeError, "type mismatch: String given");

      case T_REGEXP:
	return rb_reg_match(y, x);

      generic:
      default:
	return rb_funcall(y, idEqTilde, 1, x);
    }
}


static VALUE get_pat(VALUE);


/*
 *  call-seq:
 *     str.match(pattern)        -> matchdata or nil
 *     str.match(pattern, pos)   -> matchdata or nil
 *
 *  Converts <i>pattern</i> to a <code>Regexp</code> (if it isn't already one),
 *  then invokes its <code>match</code> method on <i>str</i>.  If the second
 *  parameter is present, it specifies the position in the string to begin the
 *  search.
 *
 *     'hello'.match('(.)\1')      #=> #<MatchData "ll" 1:"l">
 *     'hello'.match('(.)\1')[0]   #=> "ll"
 *     'hello'.match(/(.)\1/)[0]   #=> "ll"
 *     'hello'.match('xx')         #=> nil
 *
 *  If a block is given, invoke the block with MatchData if match succeed, so
 *  that you can write
 *
 *     str.match(pat) {|m| ...}
 *
 *  instead of
 *
 *     if m = str.match(pat)
 *       ...
 *     end
 *
 *  The return value is a value from block execution in this case.
 */

static VALUE
rb_str_match_m(int argc, VALUE *argv, VALUE str)
{
    VALUE re, result;
    if (argc < 1)
	rb_check_arity(argc, 1, 2);
    re = argv[0];
    argv[0] = str;
    result = rb_funcall2(get_pat(re), rb_intern("match"), argc, argv);
    if (!NIL_P(result) && rb_block_given_p()) {
	return rb_yield(result);
    }
    return result;
}

enum neighbor_char {
    NEIGHBOR_NOT_CHAR,
    NEIGHBOR_FOUND,
    NEIGHBOR_WRAPPED
};

static enum neighbor_char
enc_succ_char(char *p, long len, rb_encoding *enc)
{
    long i;
    int l;

    if (rb_enc_mbminlen(enc) > 1) {
	/* wchar, trivial case */
	int r = rb_enc_precise_mbclen(p, p + len, enc), c;
	if (!MBCLEN_CHARFOUND_P(r)) {
	    return NEIGHBOR_NOT_CHAR;
	}
	c = rb_enc_mbc_to_codepoint(p, p + len, enc) + 1;
	l = rb_enc_code_to_mbclen(c, enc);
	if (!l) return NEIGHBOR_NOT_CHAR;
	if (l != len) return NEIGHBOR_WRAPPED;
	rb_enc_mbcput(c, p, enc);
	r = rb_enc_precise_mbclen(p, p + len, enc);
	if (!MBCLEN_CHARFOUND_P(r)) {
	    return NEIGHBOR_NOT_CHAR;
	}
	return NEIGHBOR_FOUND;
    }
    while (1) {
        for (i = len-1; 0 <= i && (unsigned char)p[i] == 0xff; i--)
            p[i] = '\0';
        if (i < 0)
            return NEIGHBOR_WRAPPED;
        ++((unsigned char*)p)[i];
        l = rb_enc_precise_mbclen(p, p+len, enc);
        if (MBCLEN_CHARFOUND_P(l)) {
            l = MBCLEN_CHARFOUND_LEN(l);
            if (l == len) {
                return NEIGHBOR_FOUND;
            }
            else {
                memset(p+l, 0xff, len-l);
            }
        }
        if (MBCLEN_INVALID_P(l) && i < len-1) {
            long len2;
            int l2;
            for (len2 = len-1; 0 < len2; len2--) {
                l2 = rb_enc_precise_mbclen(p, p+len2, enc);
                if (!MBCLEN_INVALID_P(l2))
                    break;
            }
            memset(p+len2+1, 0xff, len-(len2+1));
        }
    }
}

static enum neighbor_char
enc_pred_char(char *p, long len, rb_encoding *enc)
{
    long i;
    int l;
    if (rb_enc_mbminlen(enc) > 1) {
	/* wchar, trivial case */
	int r = rb_enc_precise_mbclen(p, p + len, enc), c;
	if (!MBCLEN_CHARFOUND_P(r)) {
	    return NEIGHBOR_NOT_CHAR;
	}
	c = rb_enc_mbc_to_codepoint(p, p + len, enc);
	if (!c) return NEIGHBOR_NOT_CHAR;
	--c;
	l = rb_enc_code_to_mbclen(c, enc);
	if (!l) return NEIGHBOR_NOT_CHAR;
	if (l != len) return NEIGHBOR_WRAPPED;
	rb_enc_mbcput(c, p, enc);
	r = rb_enc_precise_mbclen(p, p + len, enc);
	if (!MBCLEN_CHARFOUND_P(r)) {
	    return NEIGHBOR_NOT_CHAR;
	}
	return NEIGHBOR_FOUND;
    }
    while (1) {
        for (i = len-1; 0 <= i && (unsigned char)p[i] == 0; i--)
            p[i] = '\xff';
        if (i < 0)
            return NEIGHBOR_WRAPPED;
        --((unsigned char*)p)[i];
        l = rb_enc_precise_mbclen(p, p+len, enc);
        if (MBCLEN_CHARFOUND_P(l)) {
            l = MBCLEN_CHARFOUND_LEN(l);
            if (l == len) {
                return NEIGHBOR_FOUND;
            }
            else {
                memset(p+l, 0, len-l);
            }
        }
        if (MBCLEN_INVALID_P(l) && i < len-1) {
            long len2;
            int l2;
            for (len2 = len-1; 0 < len2; len2--) {
                l2 = rb_enc_precise_mbclen(p, p+len2, enc);
                if (!MBCLEN_INVALID_P(l2))
                    break;
            }
            memset(p+len2+1, 0, len-(len2+1));
        }
    }
}

/*
  overwrite +p+ by succeeding letter in +enc+ and returns
  NEIGHBOR_FOUND or NEIGHBOR_WRAPPED.
  When NEIGHBOR_WRAPPED, carried-out letter is stored into carry.
  assuming each ranges are successive, and mbclen
  never change in each ranges.
  NEIGHBOR_NOT_CHAR is returned if invalid character or the range has only one
  character.
 */
static enum neighbor_char
enc_succ_alnum_char(char *p, long len, rb_encoding *enc, char *carry)
{
    enum neighbor_char ret;
    unsigned int c;
    int ctype;
    int range;
    char save[ONIGENC_CODE_TO_MBC_MAXLEN];

    /* skip 03A2, invalid char between GREEK CAPITAL LETTERS */
    int try;
    const int max_gaps = 1;

    c = rb_enc_mbc_to_codepoint(p, p+len, enc);
    if (rb_enc_isctype(c, ONIGENC_CTYPE_DIGIT, enc))
        ctype = ONIGENC_CTYPE_DIGIT;
    else if (rb_enc_isctype(c, ONIGENC_CTYPE_ALPHA, enc))
        ctype = ONIGENC_CTYPE_ALPHA;
    else
        return NEIGHBOR_NOT_CHAR;

    MEMCPY(save, p, char, len);
    for (try = 0; try <= max_gaps; ++try) {
	ret = enc_succ_char(p, len, enc);
	if (ret == NEIGHBOR_FOUND) {
	    c = rb_enc_mbc_to_codepoint(p, p+len, enc);
	    if (rb_enc_isctype(c, ctype, enc))
		return NEIGHBOR_FOUND;
	}
    }
    MEMCPY(p, save, char, len);
    range = 1;
    while (1) {
        MEMCPY(save, p, char, len);
        ret = enc_pred_char(p, len, enc);
        if (ret == NEIGHBOR_FOUND) {
            c = rb_enc_mbc_to_codepoint(p, p+len, enc);
            if (!rb_enc_isctype(c, ctype, enc)) {
                MEMCPY(p, save, char, len);
                break;
            }
        }
        else {
            MEMCPY(p, save, char, len);
            break;
        }
        range++;
    }
    if (range == 1) {
        return NEIGHBOR_NOT_CHAR;
    }

    if (ctype != ONIGENC_CTYPE_DIGIT) {
        MEMCPY(carry, p, char, len);
        return NEIGHBOR_WRAPPED;
    }

    MEMCPY(carry, p, char, len);
    enc_succ_char(carry, len, enc);
    return NEIGHBOR_WRAPPED;
}


static VALUE str_succ(VALUE str);

/*
 *  call-seq:
 *     str.succ   -> new_str
 *     str.next   -> new_str
 *
 *  Returns the successor to <i>str</i>. The successor is calculated by
 *  incrementing characters starting from the rightmost alphanumeric (or
 *  the rightmost character if there are no alphanumerics) in the
 *  string. Incrementing a digit always results in another digit, and
 *  incrementing a letter results in another letter of the same case.
 *  Incrementing nonalphanumerics uses the underlying character set's
 *  collating sequence.
 *
 *  If the increment generates a ``carry,'' the character to the left of
 *  it is incremented. This process repeats until there is no carry,
 *  adding an additional character if necessary.
 *
 *     "abcd".succ        #=> "abce"
 *     "THX1138".succ     #=> "THX1139"
 *     "<<koala>>".succ   #=> "<<koalb>>"
 *     "1999zzz".succ     #=> "2000aaa"
 *     "ZZZ9999".succ     #=> "AAAA0000"
 *     "***".succ         #=> "**+"
 */

VALUE
rb_str_succ(VALUE orig)
{
    VALUE str;
    str = rb_str_new_with_class(orig, RSTRING_PTR(orig), RSTRING_LEN(orig));
    rb_enc_cr_str_copy_for_substr(str, orig);
    OBJ_INFECT(str, orig);
    return str_succ(str);
}

static VALUE
str_succ(VALUE str)
{
    rb_encoding *enc;
    char *sbeg, *s, *e, *last_alnum = 0;
    int c = -1;
    long l, slen;
    char carry[ONIGENC_CODE_TO_MBC_MAXLEN] = "\1";
    long carry_pos = 0, carry_len = 1;
    enum neighbor_char neighbor = NEIGHBOR_FOUND;

    slen = RSTRING_LEN(str);
    if (slen == 0) return str;

    enc = STR_ENC_GET(str);
    sbeg = RSTRING_PTR(str);
    s = e = sbeg + slen;

    while ((s = rb_enc_prev_char(sbeg, s, e, enc)) != 0) {
	if (neighbor == NEIGHBOR_NOT_CHAR && last_alnum) {
	    if (ISALPHA(*last_alnum) ? ISDIGIT(*s) :
		ISDIGIT(*last_alnum) ? ISALPHA(*s) : 0) {
		s = last_alnum;
		break;
	    }
	}
	l = rb_enc_precise_mbclen(s, e, enc);
	if (!ONIGENC_MBCLEN_CHARFOUND_P(l)) continue;
	l = ONIGENC_MBCLEN_CHARFOUND_LEN(l);
        neighbor = enc_succ_alnum_char(s, l, enc, carry);
        switch (neighbor) {
	  case NEIGHBOR_NOT_CHAR:
	    continue;
	  case NEIGHBOR_FOUND:
	    return str;
	  case NEIGHBOR_WRAPPED:
	    last_alnum = s;
	    break;
	}
        c = 1;
        carry_pos = s - sbeg;
        carry_len = l;
    }
    if (c == -1) {		/* str contains no alnum */
	s = e;
	while ((s = rb_enc_prev_char(sbeg, s, e, enc)) != 0) {
            enum neighbor_char neighbor;
	    char tmp[ONIGENC_CODE_TO_MBC_MAXLEN];
	    l = rb_enc_precise_mbclen(s, e, enc);
	    if (!ONIGENC_MBCLEN_CHARFOUND_P(l)) continue;
	    l = ONIGENC_MBCLEN_CHARFOUND_LEN(l);
	    MEMCPY(tmp, s, char, l);
	    neighbor = enc_succ_char(tmp, l, enc);
	    switch (neighbor) {
	      case NEIGHBOR_FOUND:
		MEMCPY(s, tmp, char, l);
                return str;
		break;
	      case NEIGHBOR_WRAPPED:
		MEMCPY(s, tmp, char, l);
		break;
	      case NEIGHBOR_NOT_CHAR:
		break;
	    }
            if (rb_enc_precise_mbclen(s, s+l, enc) != l) {
                /* wrapped to \0...\0.  search next valid char. */
                enc_succ_char(s, l, enc);
            }
            if (!rb_enc_asciicompat(enc)) {
                MEMCPY(carry, s, char, l);
                carry_len = l;
            }
            carry_pos = s - sbeg;
	}
    }
    RESIZE_CAPA(str, slen + carry_len);
    sbeg = RSTRING_PTR(str);
    s = sbeg + carry_pos;
    memmove(s + carry_len, s, slen - carry_pos);
    memmove(s, carry, carry_len);
    slen += carry_len;
    STR_SET_LEN(str, slen);
    TERM_FILL(&sbeg[slen], rb_enc_mbminlen(enc));
    rb_enc_str_coderange(str);
    return str;
}


/*
 *  call-seq:
 *     str.succ!   -> str
 *     str.next!   -> str
 *
 *  Equivalent to <code>String#succ</code>, but modifies the receiver in
 *  place.
 */

static VALUE
rb_str_succ_bang(VALUE str)
{
    rb_str_modify(str);
    str_succ(str);
    return str;
}

static int
all_digits_p(const char *s, long len)
{
    while (len-- > 0) {
	if (!ISDIGIT(*s)) return 0;
	s++;
    }
    return 1;
}

static VALUE str_upto_each(VALUE beg, VALUE end, int excl, int (*each)(VALUE, VALUE), VALUE);

static int
str_upto_i(VALUE str, VALUE arg)
{
    rb_yield(str);
    return 0;
}

/*
 *  call-seq:
 *     str.upto(other_str, exclusive=false) {|s| block }   -> str
 *     str.upto(other_str, exclusive=false)                -> an_enumerator
 *
 *  Iterates through successive values, starting at <i>str</i> and
 *  ending at <i>other_str</i> inclusive, passing each value in turn to
 *  the block. The <code>String#succ</code> method is used to generate
 *  each value.  If optional second argument exclusive is omitted or is false,
 *  the last value will be included; otherwise it will be excluded.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     "a8".upto("b6") {|s| print s, ' ' }
 *     for s in "a8".."b6"
 *       print s, ' '
 *     end
 *
 *  <em>produces:</em>
 *
 *     a8 a9 b0 b1 b2 b3 b4 b5 b6
 *     a8 a9 b0 b1 b2 b3 b4 b5 b6
 *
 *  If <i>str</i> and <i>other_str</i> contains only ascii numeric characters,
 *  both are recognized as decimal numbers. In addition, the width of
 *  string (e.g. leading zeros) is handled appropriately.
 *
 *     "9".upto("11").to_a   #=> ["9", "10", "11"]
 *     "25".upto("5").to_a   #=> []
 *     "07".upto("11").to_a  #=> ["07", "08", "09", "10", "11"]
 */

static VALUE
rb_str_upto(int argc, VALUE *argv, VALUE beg)
{
    VALUE end, exclusive;

    rb_scan_args(argc, argv, "11", &end, &exclusive);
    RETURN_ENUMERATOR(beg, argc, argv);
    return str_upto_each(beg, end, RTEST(exclusive), str_upto_i, Qnil);
}

static VALUE
str_upto_each(VALUE beg, VALUE end, int excl, int (*each)(VALUE, VALUE), VALUE arg)
{
    VALUE current, after_end;
    ID succ;
    int n, ascii;
    rb_encoding *enc;

    CONST_ID(succ, "succ");
    StringValue(end);
    enc = rb_enc_check(beg, end);
    ascii = (is_ascii_string(beg) && is_ascii_string(end));
    /* single character */
    if (RSTRING_LEN(beg) == 1 && RSTRING_LEN(end) == 1 && ascii) {
	char c = RSTRING_PTR(beg)[0];
	char e = RSTRING_PTR(end)[0];

	if (c > e || (excl && c == e)) return beg;
	for (;;) {
	    if ((*each)(rb_enc_str_new(&c, 1, enc), arg)) break;
	    if (!excl && c == e) break;
	    c++;
	    if (excl && c == e) break;
	}
	return beg;
    }
    /* both edges are all digits */
    if (ascii && ISDIGIT(RSTRING_PTR(beg)[0]) && ISDIGIT(RSTRING_PTR(end)[0]) &&
	all_digits_p(RSTRING_PTR(beg), RSTRING_LEN(beg)) &&
	all_digits_p(RSTRING_PTR(end), RSTRING_LEN(end))) {
	VALUE b, e;
	int width;

	width = RSTRING_LENINT(beg);
	b = rb_str_to_inum(beg, 10, FALSE);
	e = rb_str_to_inum(end, 10, FALSE);
	if (FIXNUM_P(b) && FIXNUM_P(e)) {
	    long bi = FIX2LONG(b);
	    long ei = FIX2LONG(e);
	    rb_encoding *usascii = rb_usascii_encoding();

	    while (bi <= ei) {
		if (excl && bi == ei) break;
		if ((*each)(rb_enc_sprintf(usascii, "%.*ld", width, bi), arg)) break;
		bi++;
	    }
	}
	else {
	    ID op = excl ? '<' : idLE;
	    VALUE args[2], fmt = rb_obj_freeze(rb_usascii_str_new_cstr("%.*d"));

	    args[0] = INT2FIX(width);
	    while (rb_funcall(b, op, 1, e)) {
		args[1] = b;
		if ((*each)(rb_str_format(numberof(args), args, fmt), arg)) break;
		b = rb_funcallv(b, succ, 0, 0);
	    }
	}
	return beg;
    }
    /* normal case */
    n = rb_str_cmp(beg, end);
    if (n > 0 || (excl && n == 0)) return beg;

    after_end = rb_funcallv(end, succ, 0, 0);
    current = rb_str_dup(beg);
    while (!rb_str_equal(current, after_end)) {
	VALUE next = Qnil;
	if (excl || !rb_str_equal(current, end))
	    next = rb_funcallv(current, succ, 0, 0);
	if ((*each)(current, arg)) break;
	if (NIL_P(next)) break;
	current = next;
	StringValue(current);
	if (excl && rb_str_equal(current, end)) break;
	if (RSTRING_LEN(current) > RSTRING_LEN(end) || RSTRING_LEN(current) == 0)
	    break;
    }

    return beg;
}

static int
include_range_i(VALUE str, VALUE arg)
{
    VALUE *argp = (VALUE *)arg;
    if (!rb_equal(str, *argp)) return 0;
    *argp = Qnil;
    return 1;
}

VALUE
rb_str_include_range_p(VALUE beg, VALUE end, VALUE val, VALUE exclusive)
{
    beg = rb_str_new_frozen(beg);
    StringValue(end);
    end = rb_str_new_frozen(end);
    if (NIL_P(val)) return Qfalse;
    val = rb_check_string_type(val);
    if (NIL_P(val)) return Qfalse;
    if (rb_enc_asciicompat(STR_ENC_GET(beg)) &&
	rb_enc_asciicompat(STR_ENC_GET(end)) &&
	rb_enc_asciicompat(STR_ENC_GET(val))) {
	const char *bp = RSTRING_PTR(beg);
	const char *ep = RSTRING_PTR(end);
	const char *vp = RSTRING_PTR(val);
	if (RSTRING_LEN(beg) == 1 && RSTRING_LEN(end) == 1) {
	    if (RSTRING_LEN(val) == 0 || RSTRING_LEN(val) > 1)
		return Qfalse;
	    else {
		char b = *bp;
		char e = *ep;
		char v = *vp;

		if (ISASCII(b) && ISASCII(e) && ISASCII(v)) {
		    if (b <= v && v < e) return Qtrue;
		    if (!RTEST(exclusive) && v == e) return Qtrue;
		    return Qfalse;
		}
	    }
	}
#if 0
	/* both edges are all digits */
	if (ISDIGIT(*bp) && ISDIGIT(*ep) &&
	    all_digits_p(bp, RSTRING_LEN(beg)) &&
	    all_digits_p(ep, RSTRING_LEN(end))) {
	    /* TODO */
	}
#endif
    }
    str_upto_each(beg, end, RTEST(exclusive), include_range_i, (VALUE)&val);

    return NIL_P(val) ? Qtrue : Qfalse;
}

static VALUE
rb_str_subpat(VALUE str, VALUE re, VALUE backref)
{
    if (rb_reg_search(re, str, 0, 0) >= 0) {
        VALUE match = rb_backref_get();
        int nth = rb_reg_backref_number(match, backref);
	return rb_reg_nth_match(nth, match);
    }
    return Qnil;
}

static VALUE
rb_str_aref(VALUE str, VALUE indx)
{
    long idx;

    if (FIXNUM_P(indx)) {
	idx = FIX2LONG(indx);

      num_index:
	str = rb_str_substr(str, idx, 1);
	if (!NIL_P(str) && RSTRING_LEN(str) == 0) return Qnil;
	return str;
    }

    if (SPECIAL_CONST_P(indx)) goto generic;
    switch (BUILTIN_TYPE(indx)) {
      case T_REGEXP:
	return rb_str_subpat(str, indx, INT2FIX(0));

      case T_STRING:
	if (rb_str_index(str, indx, 0) != -1)
	    return rb_str_dup(indx);
	return Qnil;

      generic:
      default:
	/* check if indx is Range */
	{
	    long beg, len;
	    VALUE tmp;

	    len = str_strlen(str, NULL);
	    switch (rb_range_beg_len(indx, &beg, &len, len, 0)) {
	      case Qfalse:
		break;
	      case Qnil:
		return Qnil;
	      default:
		tmp = rb_str_substr(str, beg, len);
		return tmp;
	    }
	}
	idx = NUM2LONG(indx);
	goto num_index;
    }

    UNREACHABLE;
}


/*
 *  call-seq:
 *     str[index]                 -> new_str or nil
 *     str[start, length]         -> new_str or nil
 *     str[range]                 -> new_str or nil
 *     str[regexp]                -> new_str or nil
 *     str[regexp, capture]       -> new_str or nil
 *     str[match_str]             -> new_str or nil
 *     str.slice(index)           -> new_str or nil
 *     str.slice(start, length)   -> new_str or nil
 *     str.slice(range)           -> new_str or nil
 *     str.slice(regexp)          -> new_str or nil
 *     str.slice(regexp, capture) -> new_str or nil
 *     str.slice(match_str)       -> new_str or nil
 *
 *  Element Reference --- If passed a single +index+, returns a substring of
 *  one character at that index. If passed a +start+ index and a +length+,
 *  returns a substring containing +length+ characters starting at the
 *  +start+ index. If passed a +range+, its beginning and end are interpreted as
 *  offsets delimiting the substring to be returned.
 *
 *  In these three cases, if an index is negative, it is counted from the end
 *  of the string.  For the +start+ and +range+ cases the starting index
 *  is just before a character and an index matching the string's size.
 *  Additionally, an empty string is returned when the starting index for a
 *  character range is at the end of the string.
 *
 *  Returns +nil+ if the initial index falls outside the string or the length
 *  is negative.
 *
 *  If a +Regexp+ is supplied, the matching portion of the string is
 *  returned.  If a +capture+ follows the regular expression, which may be a
 *  capture group index or name, follows the regular expression that component
 *  of the MatchData is returned instead.
 *
 *  If a +match_str+ is given, that string is returned if it occurs in
 *  the string.
 *
 *  Returns +nil+ if the regular expression does not match or the match string
 *  cannot be found.
 *
 *     a = "hello there"
 *
 *     a[1]                   #=> "e"
 *     a[2, 3]                #=> "llo"
 *     a[2..3]                #=> "ll"
 *
 *     a[-3, 2]               #=> "er"
 *     a[7..-2]               #=> "her"
 *     a[-4..-2]              #=> "her"
 *     a[-2..-4]              #=> ""
 *
 *     a[11, 0]               #=> ""
 *     a[11]                  #=> nil
 *     a[12, 0]               #=> nil
 *     a[12..-1]              #=> nil
 *
 *     a[/[aeiou](.)\1/]      #=> "ell"
 *     a[/[aeiou](.)\1/, 0]   #=> "ell"
 *     a[/[aeiou](.)\1/, 1]   #=> "l"
 *     a[/[aeiou](.)\1/, 2]   #=> nil
 *
 *     a[/(?<vowel>[aeiou])(?<non_vowel>[^aeiou])/, "non_vowel"] #=> "l"
 *     a[/(?<vowel>[aeiou])(?<non_vowel>[^aeiou])/, "vowel"]     #=> "e"
 *
 *     a["lo"]                #=> "lo"
 *     a["bye"]               #=> nil
 */

static VALUE
rb_str_aref_m(int argc, VALUE *argv, VALUE str)
{
    if (argc == 2) {
	if (RB_TYPE_P(argv[0], T_REGEXP)) {
	    return rb_str_subpat(str, argv[0], argv[1]);
	}
	return rb_str_substr(str, NUM2LONG(argv[0]), NUM2LONG(argv[1]));
    }
    rb_check_arity(argc, 1, 2);
    return rb_str_aref(str, argv[0]);
}

VALUE
rb_str_drop_bytes(VALUE str, long len)
{
    char *ptr = RSTRING_PTR(str);
    long olen = RSTRING_LEN(str), nlen;

    str_modifiable(str);
    if (len > olen) len = olen;
    nlen = olen - len;
    if (nlen <= (RSTRING_EMBED_LEN_MAX + 1 - TERM_LEN(str))) {
	char *oldptr = ptr;
	int fl = (int)(RBASIC(str)->flags & (STR_NOEMBED|STR_SHARED|STR_NOFREE));
	STR_SET_EMBED(str);
	STR_SET_EMBED_LEN(str, nlen);
	ptr = RSTRING(str)->as.ary;
	memmove(ptr, oldptr + len, nlen);
	if (fl == STR_NOEMBED) xfree(oldptr);
    }
    else {
	if (!STR_SHARED_P(str)) rb_str_new_frozen(str);
	ptr = RSTRING(str)->as.heap.ptr += len;
	RSTRING(str)->as.heap.len = nlen;
    }
    ptr[nlen] = 0;
    ENC_CODERANGE_CLEAR(str);
    return str;
}

static void
rb_str_splice_0(VALUE str, long beg, long len, VALUE val)
{
    char *sptr;
    long slen, vlen = RSTRING_LEN(val);

    if (beg == 0 && vlen == 0) {
	rb_str_drop_bytes(str, len);
	OBJ_INFECT(str, val);
	return;
    }

    rb_str_modify(str);
    RSTRING_GETMEM(str, sptr, slen);
    if (len < vlen) {
	/* expand string */
	RESIZE_CAPA(str, slen + vlen - len);
	sptr = RSTRING_PTR(str);
    }

    if (vlen != len) {
	memmove(sptr + beg + vlen,
		sptr + beg + len,
		slen - (beg + len));
    }
    if (vlen < beg && len < 0) {
	MEMZERO(sptr + slen, char, -len);
    }
    if (vlen > 0) {
	memmove(sptr + beg, RSTRING_PTR(val), vlen);
    }
    slen += vlen - len;
    STR_SET_LEN(str, slen);
    TERM_FILL(&sptr[slen], TERM_LEN(str));
    OBJ_INFECT(str, val);
}

void
rb_str_update(VALUE str, long beg, long len, VALUE val)
{
    long slen;
    char *p, *e;
    rb_encoding *enc;
    int singlebyte = single_byte_optimizable(str);
    int cr;

    if (len < 0) rb_raise(rb_eIndexError, "negative length %ld", len);

    StringValue(val);
    enc = rb_enc_check(str, val);
    slen = str_strlen(str, enc); /* rb_enc_check */

    if (slen < beg) {
      out_of_range:
	rb_raise(rb_eIndexError, "index %ld out of string", beg);
    }
    if (beg < 0) {
	if (-beg > slen) {
	    goto out_of_range;
	}
	beg += slen;
    }
    if (slen < len || slen < beg + len) {
	len = slen - beg;
    }
    str_modify_keep_cr(str);
    p = str_nth(RSTRING_PTR(str), RSTRING_END(str), beg, enc, singlebyte);
    if (!p) p = RSTRING_END(str);
    e = str_nth(p, RSTRING_END(str), len, enc, singlebyte);
    if (!e) e = RSTRING_END(str);
    /* error check */
    beg = p - RSTRING_PTR(str);	/* physical position */
    len = e - p;		/* physical length */
    rb_str_splice_0(str, beg, len, val);
    rb_enc_associate(str, enc);
    cr = ENC_CODERANGE_AND(ENC_CODERANGE(str), ENC_CODERANGE(val));
    if (cr != ENC_CODERANGE_BROKEN)
	ENC_CODERANGE_SET(str, cr);
}

#define rb_str_splice(str, beg, len, val) rb_str_update(str, beg, len, val)

static void
rb_str_subpat_set(VALUE str, VALUE re, VALUE backref, VALUE val)
{
    int nth;
    VALUE match;
    long start, end, len;
    rb_encoding *enc;
    struct re_registers *regs;

    if (rb_reg_search(re, str, 0, 0) < 0) {
	rb_raise(rb_eIndexError, "regexp not matched");
    }
    match = rb_backref_get();
    nth = rb_reg_backref_number(match, backref);
    regs = RMATCH_REGS(match);
    if (nth >= regs->num_regs) {
      out_of_range:
	rb_raise(rb_eIndexError, "index %d out of regexp", nth);
    }
    if (nth < 0) {
	if (-nth >= regs->num_regs) {
	    goto out_of_range;
	}
	nth += regs->num_regs;
    }

    start = BEG(nth);
    if (start == -1) {
	rb_raise(rb_eIndexError, "regexp group %d not matched", nth);
    }
    end = END(nth);
    len = end - start;
    StringValue(val);
    enc = rb_enc_check_str(str, val);
    rb_str_splice_0(str, start, len, val);
    rb_enc_associate(str, enc);
}

static VALUE
rb_str_aset(VALUE str, VALUE indx, VALUE val)
{
    long idx, beg;

    if (FIXNUM_P(indx)) {
	idx = FIX2LONG(indx);
      num_index:
	rb_str_splice(str, idx, 1, val);
	return val;
    }

    if (SPECIAL_CONST_P(indx)) goto generic;
    switch (TYPE(indx)) {
      case T_REGEXP:
	rb_str_subpat_set(str, indx, INT2FIX(0), val);
	return val;

      case T_STRING:
	beg = rb_str_index(str, indx, 0);
	if (beg < 0) {
	    rb_raise(rb_eIndexError, "string not matched");
	}
	beg = rb_str_sublen(str, beg);
	rb_str_splice(str, beg, str_strlen(indx, NULL), val);
	return val;

      generic:
      default:
	/* check if indx is Range */
	{
	    long beg, len;
	    if (rb_range_beg_len(indx, &beg, &len, str_strlen(str, NULL), 2)) {
		rb_str_splice(str, beg, len, val);
		return val;
	    }
	}
	idx = NUM2LONG(indx);
	goto num_index;
    }
}

/*
 *  call-seq:
 *     str[fixnum] = new_str
 *     str[fixnum, fixnum] = new_str
 *     str[range] = aString
 *     str[regexp] = new_str
 *     str[regexp, fixnum] = new_str
 *     str[regexp, name] = new_str
 *     str[other_str] = new_str
 *
 *  Element Assignment---Replaces some or all of the content of <i>str</i>. The
 *  portion of the string affected is determined using the same criteria as
 *  <code>String#[]</code>. If the replacement string is not the same length as
 *  the text it is replacing, the string will be adjusted accordingly. If the
 *  regular expression or string is used as the index doesn't match a position
 *  in the string, <code>IndexError</code> is raised. If the regular expression
 *  form is used, the optional second <code>Fixnum</code> allows you to specify
 *  which portion of the match to replace (effectively using the
 *  <code>MatchData</code> indexing rules. The forms that take a
 *  <code>Fixnum</code> will raise an <code>IndexError</code> if the value is
 *  out of range; the <code>Range</code> form will raise a
 *  <code>RangeError</code>, and the <code>Regexp</code> and <code>String</code>
 *  will raise an <code>IndexError</code> on negative match.
 */

static VALUE
rb_str_aset_m(int argc, VALUE *argv, VALUE str)
{
    if (argc == 3) {
	if (RB_TYPE_P(argv[0], T_REGEXP)) {
	    rb_str_subpat_set(str, argv[0], argv[1], argv[2]);
	}
	else {
	    rb_str_splice(str, NUM2LONG(argv[0]), NUM2LONG(argv[1]), argv[2]);
	}
	return argv[2];
    }
    rb_check_arity(argc, 2, 3);
    return rb_str_aset(str, argv[0], argv[1]);
}

/*
 *  call-seq:
 *     str.insert(index, other_str)   -> str
 *
 *  Inserts <i>other_str</i> before the character at the given
 *  <i>index</i>, modifying <i>str</i>. Negative indices count from the
 *  end of the string, and insert <em>after</em> the given character.
 *  The intent is insert <i>aString</i> so that it starts at the given
 *  <i>index</i>.
 *
 *     "abcd".insert(0, 'X')    #=> "Xabcd"
 *     "abcd".insert(3, 'X')    #=> "abcXd"
 *     "abcd".insert(4, 'X')    #=> "abcdX"
 *     "abcd".insert(-3, 'X')   #=> "abXcd"
 *     "abcd".insert(-1, 'X')   #=> "abcdX"
 */

static VALUE
rb_str_insert(VALUE str, VALUE idx, VALUE str2)
{
    long pos = NUM2LONG(idx);

    if (pos == -1) {
	return rb_str_append(str, str2);
    }
    else if (pos < 0) {
	pos++;
    }
    rb_str_splice(str, pos, 0, str2);
    return str;
}


/*
 *  call-seq:
 *     str.slice!(fixnum)           -> new_str or nil
 *     str.slice!(fixnum, fixnum)   -> new_str or nil
 *     str.slice!(range)            -> new_str or nil
 *     str.slice!(regexp)           -> new_str or nil
 *     str.slice!(other_str)        -> new_str or nil
 *
 *  Deletes the specified portion from <i>str</i>, and returns the portion
 *  deleted.
 *
 *     string = "this is a string"
 *     string.slice!(2)        #=> "i"
 *     string.slice!(3..6)     #=> " is "
 *     string.slice!(/s.*t/)   #=> "sa st"
 *     string.slice!("r")      #=> "r"
 *     string                  #=> "thing"
 */

static VALUE
rb_str_slice_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE result;
    VALUE buf[3];
    int i;

    rb_check_arity(argc, 1, 2);
    for (i=0; i<argc; i++) {
	buf[i] = argv[i];
    }
    str_modify_keep_cr(str);
    result = rb_str_aref_m(argc, buf, str);
    if (!NIL_P(result)) {
	buf[i] = rb_str_new(0,0);
	rb_str_aset_m(argc+1, buf, str);
    }
    return result;
}

static VALUE
get_pat(VALUE pat)
{
    VALUE val;

    if (SPECIAL_CONST_P(pat)) goto to_string;
    switch (BUILTIN_TYPE(pat)) {
      case T_REGEXP:
	return pat;

      case T_STRING:
	break;

      default:
      to_string:
	val = rb_check_string_type(pat);
	if (NIL_P(val)) {
	    Check_Type(pat, T_REGEXP);
	}
	pat = val;
    }

    return rb_reg_regcomp(pat);
}

static VALUE
get_pat_quoted(VALUE pat, int check)
{
    VALUE val;

    if (SPECIAL_CONST_P(pat)) goto to_string;
    switch (BUILTIN_TYPE(pat)) {
      case T_REGEXP:
	return pat;

      case T_STRING:
	break;

      default:
      to_string:
	val = rb_check_string_type(pat);
	if (NIL_P(val)) {
	    Check_Type(pat, T_REGEXP);
	}
	pat = val;
    }
    if (check && is_broken_string(pat)) {
	rb_exc_raise(rb_reg_check_preprocess(pat));
    }
    return pat;
}

static long
rb_pat_search(VALUE pat, VALUE str, long pos, int set_backref_str)
{
    if (BUILTIN_TYPE(pat) == T_STRING) {
	pos = rb_strseq_index(str, pat, pos, 1);
	if (set_backref_str) {
	    if (pos >= 0) {
		VALUE match;
		str = rb_str_new_frozen(str);
		rb_backref_set_string(str, pos, RSTRING_LEN(pat));
		match = rb_backref_get();
		OBJ_INFECT(match, pat);
	    }
	    else {
		rb_backref_set(Qnil);
	    }
	}
	return pos;
    }
    else {
	return rb_reg_search0(pat, str, pos, 0, set_backref_str);
    }
}


/*
 *  call-seq:
 *     str.sub!(pattern, replacement)          -> str or nil
 *     str.sub!(pattern) {|match| block }      -> str or nil
 *
 *  Performs the same substitution as String#sub in-place.
 *
 *  Returns +str+ if a substitution was performed or +nil+ if no substitution
 *  was performed.
 */

static VALUE
rb_str_sub_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE pat, repl, hash = Qnil;
    int iter = 0;
    int tainted = 0;
    long plen;
    int min_arity = rb_block_given_p() ? 1 : 2;
    long beg;

    rb_check_arity(argc, min_arity, 2);
    if (argc == 1) {
	iter = 1;
    }
    else {
	repl = argv[1];
	hash = rb_check_hash_type(argv[1]);
	if (NIL_P(hash)) {
	    StringValue(repl);
	}
	tainted = OBJ_TAINTED_RAW(repl);
    }

    pat = get_pat_quoted(argv[0], 1);

    str_modifiable(str);
    beg = rb_pat_search(pat, str, 0, 1);
    if (beg >= 0) {
	rb_encoding *enc;
	int cr = ENC_CODERANGE(str);
	long beg0, end0;
	VALUE match, match0 = Qnil;
	struct re_registers *regs;
	char *p, *rp;
	long len, rlen;

	match = rb_backref_get();
	regs = RMATCH_REGS(match);
	if (RB_TYPE_P(pat, T_STRING)) {
	    beg0 = beg;
	    end0 = beg0 + RSTRING_LEN(pat);
	    match0 = pat;
	}
	else {
	    beg0 = BEG(0);
	    end0 = END(0);
	    if (iter) match0 = rb_reg_nth_match(0, match);
	}

	if (iter || !NIL_P(hash)) {
	    p = RSTRING_PTR(str); len = RSTRING_LEN(str);

            if (iter) {
                repl = rb_obj_as_string(rb_yield(match0));
            }
            else {
                repl = rb_hash_aref(hash, rb_str_subseq(str, beg0, end0 - beg0));
                repl = rb_obj_as_string(repl);
            }
	    str_mod_check(str, p, len);
	    rb_check_frozen(str);
	}
	else {
	    repl = rb_reg_regsub(repl, str, regs, RB_TYPE_P(pat, T_STRING) ? Qnil : pat);
	}

        enc = rb_enc_compatible(str, repl);
        if (!enc) {
            rb_encoding *str_enc = STR_ENC_GET(str);
	    p = RSTRING_PTR(str); len = RSTRING_LEN(str);
	    if (coderange_scan(p, beg0, str_enc) != ENC_CODERANGE_7BIT ||
		coderange_scan(p+end0, len-end0, str_enc) != ENC_CODERANGE_7BIT) {
                rb_raise(rb_eEncCompatError, "incompatible character encodings: %s and %s",
			 rb_enc_name(str_enc),
			 rb_enc_name(STR_ENC_GET(repl)));
            }
            enc = STR_ENC_GET(repl);
        }
	rb_str_modify(str);
	rb_enc_associate(str, enc);
	tainted |= OBJ_TAINTED_RAW(repl);
	if (ENC_CODERANGE_UNKNOWN < cr && cr < ENC_CODERANGE_BROKEN) {
	    int cr2 = ENC_CODERANGE(repl);
            if (cr2 == ENC_CODERANGE_BROKEN ||
                (cr == ENC_CODERANGE_VALID && cr2 == ENC_CODERANGE_7BIT))
                cr = ENC_CODERANGE_UNKNOWN;
            else
                cr = cr2;
	}
	plen = end0 - beg0;
	rp = RSTRING_PTR(repl); rlen = RSTRING_LEN(repl);
	len = RSTRING_LEN(str);
	if (rlen > plen) {
	    RESIZE_CAPA(str, len + rlen - plen);
	}
	p = RSTRING_PTR(str);
	if (rlen != plen) {
	    memmove(p + beg0 + rlen, p + beg0 + plen, len - beg0 - plen);
	}
	memcpy(p + beg0, rp, rlen);
	len += rlen - plen;
	STR_SET_LEN(str, len);
	TERM_FILL(&RSTRING_PTR(str)[len], TERM_LEN(str));
	ENC_CODERANGE_SET(str, cr);
	FL_SET_RAW(str, tainted);

	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.sub(pattern, replacement)         -> new_str
 *     str.sub(pattern, hash)                -> new_str
 *     str.sub(pattern) {|match| block }     -> new_str
 *
 *  Returns a copy of +str+ with the _first_ occurrence of +pattern+
 *  replaced by the second argument. The +pattern+ is typically a Regexp; if
 *  given as a String, any regular expression metacharacters it contains will
 *  be interpreted literally, e.g. <code>'\\\d'</code> will match a backlash
 *  followed by 'd', instead of a digit.
 *
 *  If +replacement+ is a String it will be substituted for the matched text.
 *  It may contain back-references to the pattern's capture groups of the form
 *  <code>"\\d"</code>, where <i>d</i> is a group number, or
 *  <code>"\\k<n>"</code>, where <i>n</i> is a group name. If it is a
 *  double-quoted string, both back-references must be preceded by an
 *  additional backslash. However, within +replacement+ the special match
 *  variables, such as <code>&$</code>, will not refer to the current match.
 *  If +replacement+ is a String that looks like a pattern's capture group but
 *  is actually not a pattern capture group e.g. <code>"\\'"</code>, then it
 *  will have to be preceded by two backslashes like so <code>"\\\\'"</code>.
 *
 *  If the second argument is a Hash, and the matched text is one of its keys,
 *  the corresponding value is the replacement string.
 *
 *  In the block form, the current match string is passed in as a parameter,
 *  and variables such as <code>$1</code>, <code>$2</code>, <code>$`</code>,
 *  <code>$&</code>, and <code>$'</code> will be set appropriately. The value
 *  returned by the block will be substituted for the match on each call.
 *
 *  The result inherits any tainting in the original string or any supplied
 *  replacement string.
 *
 *     "hello".sub(/[aeiou]/, '*')                  #=> "h*llo"
 *     "hello".sub(/([aeiou])/, '<\1>')             #=> "h<e>llo"
 *     "hello".sub(/./) {|s| s.ord.to_s + ' ' }     #=> "104 ello"
 *     "hello".sub(/(?<foo>[aeiou])/, '*\k<foo>*')  #=> "h*e*llo"
 *     'Is SHELL your preferred shell?'.sub(/[[:upper:]]{2,}/, ENV)
 *      #=> "Is /bin/bash your preferred shell?"
 */

static VALUE
rb_str_sub(int argc, VALUE *argv, VALUE str)
{
    str = rb_str_dup(str);
    rb_str_sub_bang(argc, argv, str);
    return str;
}

static VALUE
str_gsub(int argc, VALUE *argv, VALUE str, int bang)
{
    VALUE pat, val = Qnil, repl, match, match0 = Qnil, dest, hash = Qnil;
    struct re_registers *regs;
    long beg, beg0, end0;
    long offset, blen, slen, len, last;
    enum {STR, ITER, MAP} mode = STR;
    char *sp, *cp;
    int tainted = 0;
    int need_backref = -1;
    rb_encoding *str_enc;

    switch (argc) {
      case 1:
	RETURN_ENUMERATOR(str, argc, argv);
	mode = ITER;
	break;
      case 2:
	repl = argv[1];
	hash = rb_check_hash_type(argv[1]);
	if (NIL_P(hash)) {
	    StringValue(repl);
	}
	else {
	    mode = MAP;
	}
	tainted = OBJ_TAINTED_RAW(repl);
	break;
      default:
	rb_check_arity(argc, 1, 2);
    }

    pat = get_pat_quoted(argv[0], 1);
    beg = rb_pat_search(pat, str, 0, need_backref);
    if (beg < 0) {
	if (bang) return Qnil;	/* no match, no substitution */
	return rb_str_dup(str);
    }

    offset = 0;
    blen = RSTRING_LEN(str) + 30; /* len + margin */
    dest = rb_str_buf_new(blen);
    sp = RSTRING_PTR(str);
    slen = RSTRING_LEN(str);
    cp = sp;
    str_enc = STR_ENC_GET(str);
    rb_enc_associate(dest, str_enc);
    ENC_CODERANGE_SET(dest, rb_enc_asciicompat(str_enc) ? ENC_CODERANGE_7BIT : ENC_CODERANGE_VALID);

    do {
	match = rb_backref_get();
	regs = RMATCH_REGS(match);
	if (RB_TYPE_P(pat, T_STRING)) {
	    beg0 = beg;
	    end0 = beg0 + RSTRING_LEN(pat);
	    match0 = pat;
	}
	else {
	    beg0 = BEG(0);
	    end0 = END(0);
	    if (mode == ITER) match0 = rb_reg_nth_match(0, match);
	}

	if (mode) {
            if (mode == ITER) {
                val = rb_obj_as_string(rb_yield(match0));
            }
            else {
                val = rb_hash_aref(hash, rb_str_subseq(str, beg0, end0 - beg0));
                val = rb_obj_as_string(val);
            }
	    str_mod_check(str, sp, slen);
	    if (val == dest) { 	/* paranoid check [ruby-dev:24827] */
		rb_raise(rb_eRuntimeError, "block should not cheat");
	    }
	}
	else if (need_backref) {
	    val = rb_reg_regsub(repl, str, regs, RB_TYPE_P(pat, T_STRING) ? Qnil : pat);
	    if (need_backref < 0) {
		need_backref = val != repl;
	    }
	}
	else {
	    val = repl;
	}

	tainted |= OBJ_TAINTED_RAW(val);

	len = beg0 - offset;	/* copy pre-match substr */
        if (len) {
            rb_enc_str_buf_cat(dest, cp, len, str_enc);
        }

        rb_str_buf_append(dest, val);

	last = offset;
	offset = end0;
	if (beg0 == end0) {
	    /*
	     * Always consume at least one character of the input string
	     * in order to prevent infinite loops.
	     */
	    if (RSTRING_LEN(str) <= end0) break;
	    len = rb_enc_fast_mbclen(RSTRING_PTR(str)+end0, RSTRING_END(str), str_enc);
            rb_enc_str_buf_cat(dest, RSTRING_PTR(str)+end0, len, str_enc);
	    offset = end0 + len;
	}
	cp = RSTRING_PTR(str) + offset;
	if (offset > RSTRING_LEN(str)) break;
	beg = rb_pat_search(pat, str, offset, need_backref);
    } while (beg >= 0);
    if (RSTRING_LEN(str) > offset) {
        rb_enc_str_buf_cat(dest, cp, RSTRING_LEN(str) - offset, str_enc);
    }
    rb_pat_search(pat, str, last, 1);
    if (bang) {
        str_shared_replace(str, dest);
    }
    else {
	RBASIC_SET_CLASS(dest, rb_obj_class(str));
	tainted |= OBJ_TAINTED_RAW(str);
	str = dest;
    }

    FL_SET_RAW(str, tainted);
    return str;
}


/*
 *  call-seq:
 *     str.gsub!(pattern, replacement)        -> str or nil
 *     str.gsub!(pattern, hash)               -> str or nil
 *     str.gsub!(pattern) {|match| block }    -> str or nil
 *     str.gsub!(pattern)                     -> an_enumerator
 *
 *  Performs the substitutions of <code>String#gsub</code> in place, returning
 *  <i>str</i>, or <code>nil</code> if no substitutions were performed.
 *  If no block and no <i>replacement</i> is given, an enumerator is returned instead.
 */

static VALUE
rb_str_gsub_bang(int argc, VALUE *argv, VALUE str)
{
    str_modify_keep_cr(str);
    return str_gsub(argc, argv, str, 1);
}


/*
 *  call-seq:
 *     str.gsub(pattern, replacement)       -> new_str
 *     str.gsub(pattern, hash)              -> new_str
 *     str.gsub(pattern) {|match| block }   -> new_str
 *     str.gsub(pattern)                    -> enumerator
 *
 *  Returns a copy of <i>str</i> with the <em>all</em> occurrences of
 *  <i>pattern</i> substituted for the second argument. The <i>pattern</i> is
 *  typically a <code>Regexp</code>; if given as a <code>String</code>, any
 *  regular expression metacharacters it contains will be interpreted
 *  literally, e.g. <code>'\\\d'</code> will match a backlash followed by 'd',
 *  instead of a digit.
 *
 *  If <i>replacement</i> is a <code>String</code> it will be substituted for
 *  the matched text. It may contain back-references to the pattern's capture
 *  groups of the form <code>\\\d</code>, where <i>d</i> is a group number, or
 *  <code>\\\k<n></code>, where <i>n</i> is a group name. If it is a
 *  double-quoted string, both back-references must be preceded by an
 *  additional backslash. However, within <i>replacement</i> the special match
 *  variables, such as <code>$&</code>, will not refer to the current match.
 *
 *  If the second argument is a <code>Hash</code>, and the matched text is one
 *  of its keys, the corresponding value is the replacement string.
 *
 *  In the block form, the current match string is passed in as a parameter,
 *  and variables such as <code>$1</code>, <code>$2</code>, <code>$`</code>,
 *  <code>$&</code>, and <code>$'</code> will be set appropriately. The value
 *  returned by the block will be substituted for the match on each call.
 *
 *  The result inherits any tainting in the original string or any supplied
 *  replacement string.
 *
 *  When neither a block nor a second argument is supplied, an
 *  <code>Enumerator</code> is returned.
 *
 *     "hello".gsub(/[aeiou]/, '*')                  #=> "h*ll*"
 *     "hello".gsub(/([aeiou])/, '<\1>')             #=> "h<e>ll<o>"
 *     "hello".gsub(/./) {|s| s.ord.to_s + ' '}      #=> "104 101 108 108 111 "
 *     "hello".gsub(/(?<foo>[aeiou])/, '{\k<foo>}')  #=> "h{e}ll{o}"
 *     'hello'.gsub(/[eo]/, 'e' => 3, 'o' => '*')    #=> "h3ll*"
 */

static VALUE
rb_str_gsub(int argc, VALUE *argv, VALUE str)
{
    return str_gsub(argc, argv, str, 0);
}


/*
 *  call-seq:
 *     str.replace(other_str)   -> str
 *
 *  Replaces the contents and taintedness of <i>str</i> with the corresponding
 *  values in <i>other_str</i>.
 *
 *     s = "hello"         #=> "hello"
 *     s.replace "world"   #=> "world"
 */

VALUE
rb_str_replace(VALUE str, VALUE str2)
{
    str_modifiable(str);
    if (str == str2) return str;

    StringValue(str2);
    str_discard(str);
    return str_replace(str, str2);
}

/*
 *  call-seq:
 *     string.clear    ->  string
 *
 *  Makes string empty.
 *
 *     a = "abcde"
 *     a.clear    #=> ""
 */

static VALUE
rb_str_clear(VALUE str)
{
    str_discard(str);
    STR_SET_EMBED(str);
    STR_SET_EMBED_LEN(str, 0);
    RSTRING_PTR(str)[0] = 0;
    if (rb_enc_asciicompat(STR_ENC_GET(str)))
	ENC_CODERANGE_SET(str, ENC_CODERANGE_7BIT);
    else
	ENC_CODERANGE_SET(str, ENC_CODERANGE_VALID);
    return str;
}

/*
 *  call-seq:
 *     string.chr    ->  string
 *
 *  Returns a one-character string at the beginning of the string.
 *
 *     a = "abcde"
 *     a.chr    #=> "a"
 */

static VALUE
rb_str_chr(VALUE str)
{
    return rb_str_substr(str, 0, 1);
}

/*
 *  call-seq:
 *     str.getbyte(index)          -> 0 .. 255
 *
 *  returns the <i>index</i>th byte as an integer.
 */
static VALUE
rb_str_getbyte(VALUE str, VALUE index)
{
    long pos = NUM2LONG(index);

    if (pos < 0)
        pos += RSTRING_LEN(str);
    if (pos < 0 ||  RSTRING_LEN(str) <= pos)
        return Qnil;

    return INT2FIX((unsigned char)RSTRING_PTR(str)[pos]);
}

/*
 *  call-seq:
 *     str.setbyte(index, integer) -> integer
 *
 *  modifies the <i>index</i>th byte as <i>integer</i>.
 */
static VALUE
rb_str_setbyte(VALUE str, VALUE index, VALUE value)
{
    long pos = NUM2LONG(index);
    int byte = NUM2INT(value);
    long len = RSTRING_LEN(str);
    char *head, *ptr, *left = 0;
    rb_encoding *enc;
    int cr = ENC_CODERANGE_UNKNOWN, width, nlen;

    if (pos < -len || len <= pos)
        rb_raise(rb_eIndexError, "index %ld out of string", pos);
    if (pos < 0)
        pos += len;

    if (!str_independent(str))
	str_make_independent(str);
    enc = STR_ENC_GET(str);
    head = RSTRING_PTR(str);
    ptr = &head[pos];
    if (len > (RSTRING_EMBED_LEN_MAX + 1 - rb_enc_mbminlen(enc))) {
	cr = ENC_CODERANGE(str);
	switch (cr) {
	  case ENC_CODERANGE_7BIT:
	    left = ptr;
	    *ptr = byte;
	    if (ISASCII(byte)) break;
	    nlen = rb_enc_precise_mbclen(left, head+len, enc);
	    if (!MBCLEN_CHARFOUND_P(nlen))
		ENC_CODERANGE_SET(str, ENC_CODERANGE_BROKEN);
	    else
		ENC_CODERANGE_SET(str, ENC_CODERANGE_VALID);
	    goto end;
	  case ENC_CODERANGE_VALID:
	    left = rb_enc_left_char_head(head, ptr, head+len, enc);
	    width = rb_enc_precise_mbclen(left, head+len, enc);
	    *ptr = byte;
	    nlen = rb_enc_precise_mbclen(left, head+len, enc);
	    if (!MBCLEN_CHARFOUND_P(nlen))
		ENC_CODERANGE_SET(str, ENC_CODERANGE_BROKEN);
	    else if (MBCLEN_CHARFOUND_LEN(nlen) != width || ISASCII(byte))
		ENC_CODERANGE_CLEAR(str);
	    goto end;
	}
    }
    ENC_CODERANGE_CLEAR(str);
    *ptr = byte;

  end:
    return value;
}

static VALUE
str_byte_substr(VALUE str, long beg, long len)
{
    char *p, *s = RSTRING_PTR(str);
    long n = RSTRING_LEN(str);
    VALUE str2;

    if (beg > n || len < 0) return Qnil;
    if (beg < 0) {
	beg += n;
	if (beg < 0) return Qnil;
    }
    if (beg + len > n)
	len = n - beg;
    if (len <= 0) {
	len = 0;
	p = 0;
    }
    else
	p = s + beg;

    if (len > (RSTRING_EMBED_LEN_MAX + 1 - TERM_LEN(str)) && SHARABLE_SUBSTRING_P(beg, len, n)) {
	str2 = rb_str_new_frozen(str);
	str2 = str_new_shared(rb_obj_class(str2), str2);
	RSTRING(str2)->as.heap.ptr += beg;
	RSTRING(str2)->as.heap.len = len;
    }
    else {
	str2 = rb_str_new_with_class(str, p, len);
    }

    str_enc_copy(str2, str);

    if (RSTRING_LEN(str2) == 0) {
	if (!rb_enc_asciicompat(STR_ENC_GET(str)))
	    ENC_CODERANGE_SET(str2, ENC_CODERANGE_VALID);
	else
	    ENC_CODERANGE_SET(str2, ENC_CODERANGE_7BIT);
    }
    else {
	switch (ENC_CODERANGE(str)) {
	  case ENC_CODERANGE_7BIT:
	    ENC_CODERANGE_SET(str2, ENC_CODERANGE_7BIT);
	    break;
	  default:
	    ENC_CODERANGE_SET(str2, ENC_CODERANGE_UNKNOWN);
	    break;
	}
    }

    OBJ_INFECT_RAW(str2, str);

    return str2;
}

static VALUE
str_byte_aref(VALUE str, VALUE indx)
{
    long idx;
    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = FIX2LONG(indx);

      num_index:
	str = str_byte_substr(str, idx, 1);
	if (NIL_P(str) || RSTRING_LEN(str) == 0) return Qnil;
	return str;

      default:
	/* check if indx is Range */
	{
	    long beg, len = RSTRING_LEN(str);

	    switch (rb_range_beg_len(indx, &beg, &len, len, 0)) {
	      case Qfalse:
		break;
	      case Qnil:
		return Qnil;
	      default:
		return str_byte_substr(str, beg, len);
	    }
	}
	idx = NUM2LONG(indx);
	goto num_index;
    }

    UNREACHABLE;
}

/*
 *  call-seq:
 *     str.byteslice(fixnum)           -> new_str or nil
 *     str.byteslice(fixnum, fixnum)   -> new_str or nil
 *     str.byteslice(range)            -> new_str or nil
 *
 *  Byte Reference---If passed a single <code>Fixnum</code>, returns a
 *  substring of one byte at that position. If passed two <code>Fixnum</code>
 *  objects, returns a substring starting at the offset given by the first, and
 *  a length given by the second. If given a <code>Range</code>, a substring containing
 *  bytes at offsets given by the range is returned. In all three cases, if
 *  an offset is negative, it is counted from the end of <i>str</i>. Returns
 *  <code>nil</code> if the initial offset falls outside the string, the length
 *  is negative, or the beginning of the range is greater than the end.
 *  The encoding of the resulted string keeps original encoding.
 *
 *     "hello".byteslice(1)     #=> "e"
 *     "hello".byteslice(-1)    #=> "o"
 *     "hello".byteslice(1, 2)  #=> "el"
 *     "\x80\u3042".byteslice(1, 3) #=> "\u3042"
 *     "\x03\u3042\xff".byteslice(1..3) #=> "\u3042"
 */

static VALUE
rb_str_byteslice(int argc, VALUE *argv, VALUE str)
{
    if (argc == 2) {
	return str_byte_substr(str, NUM2LONG(argv[0]), NUM2LONG(argv[1]));
    }
    rb_check_arity(argc, 1, 2);
    return str_byte_aref(str, argv[0]);
}

/*
 *  call-seq:
 *     str.reverse   -> new_str
 *
 *  Returns a new string with the characters from <i>str</i> in reverse order.
 *
 *     "stressed".reverse   #=> "desserts"
 */

static VALUE
rb_str_reverse(VALUE str)
{
    rb_encoding *enc;
    VALUE rev;
    char *s, *e, *p;
    int cr;

    if (RSTRING_LEN(str) <= 1) return rb_str_dup(str);
    enc = STR_ENC_GET(str);
    rev = rb_str_new_with_class(str, 0, RSTRING_LEN(str));
    s = RSTRING_PTR(str); e = RSTRING_END(str);
    p = RSTRING_END(rev);
    cr = ENC_CODERANGE(str);

    if (RSTRING_LEN(str) > 1) {
	if (single_byte_optimizable(str)) {
	    while (s < e) {
		*--p = *s++;
	    }
	}
	else if (cr == ENC_CODERANGE_VALID) {
	    while (s < e) {
		int clen = rb_enc_fast_mbclen(s, e, enc);

		p -= clen;
		memcpy(p, s, clen);
		s += clen;
	    }
	}
	else {
	    cr = rb_enc_asciicompat(enc) ?
		ENC_CODERANGE_7BIT : ENC_CODERANGE_VALID;
	    while (s < e) {
		int clen = rb_enc_mbclen(s, e, enc);

		if (clen > 1 || (*s & 0x80)) cr = ENC_CODERANGE_UNKNOWN;
		p -= clen;
		memcpy(p, s, clen);
		s += clen;
	    }
	}
    }
    STR_SET_LEN(rev, RSTRING_LEN(str));
    OBJ_INFECT_RAW(rev, str);
    str_enc_copy(rev, str);
    ENC_CODERANGE_SET(rev, cr);

    return rev;
}


/*
 *  call-seq:
 *     str.reverse!   -> str
 *
 *  Reverses <i>str</i> in place.
 */

static VALUE
rb_str_reverse_bang(VALUE str)
{
    if (RSTRING_LEN(str) > 1) {
	if (single_byte_optimizable(str)) {
	    char *s, *e, c;

	    str_modify_keep_cr(str);
	    s = RSTRING_PTR(str);
	    e = RSTRING_END(str) - 1;
	    while (s < e) {
		c = *s;
		*s++ = *e;
		*e-- = c;
	    }
	}
	else {
	    str_shared_replace(str, rb_str_reverse(str));
	}
    }
    else {
	str_modify_keep_cr(str);
    }
    return str;
}


/*
 *  call-seq:
 *     str.include? other_str   -> true or false
 *
 *  Returns <code>true</code> if <i>str</i> contains the given string or
 *  character.
 *
 *     "hello".include? "lo"   #=> true
 *     "hello".include? "ol"   #=> false
 *     "hello".include? ?h     #=> true
 */

static VALUE
rb_str_include(VALUE str, VALUE arg)
{
    long i;

    StringValue(arg);
    i = rb_str_index(str, arg, 0);

    if (i == -1) return Qfalse;
    return Qtrue;
}


/*
 *  call-seq:
 *     str.to_i(base=10)   -> integer
 *
 *  Returns the result of interpreting leading characters in <i>str</i> as an
 *  integer base <i>base</i> (between 2 and 36). Extraneous characters past the
 *  end of a valid number are ignored. If there is not a valid number at the
 *  start of <i>str</i>, <code>0</code> is returned. This method never raises an
 *  exception when <i>base</i> is valid.
 *
 *     "12345".to_i             #=> 12345
 *     "99 red balloons".to_i   #=> 99
 *     "0a".to_i                #=> 0
 *     "0a".to_i(16)            #=> 10
 *     "hello".to_i             #=> 0
 *     "1100101".to_i(2)        #=> 101
 *     "1100101".to_i(8)        #=> 294977
 *     "1100101".to_i(10)       #=> 1100101
 *     "1100101".to_i(16)       #=> 17826049
 */

static VALUE
rb_str_to_i(int argc, VALUE *argv, VALUE str)
{
    int base;

    if (argc == 0) base = 10;
    else {
	VALUE b;

	rb_scan_args(argc, argv, "01", &b);
	base = NUM2INT(b);
    }
    if (base < 0) {
	rb_raise(rb_eArgError, "invalid radix %d", base);
    }
    return rb_str_to_inum(str, base, FALSE);
}


/*
 *  call-seq:
 *     str.to_f   -> float
 *
 *  Returns the result of interpreting leading characters in <i>str</i> as a
 *  floating point number. Extraneous characters past the end of a valid number
 *  are ignored. If there is not a valid number at the start of <i>str</i>,
 *  <code>0.0</code> is returned. This method never raises an exception.
 *
 *     "123.45e1".to_f        #=> 1234.5
 *     "45.67 degrees".to_f   #=> 45.67
 *     "thx1138".to_f         #=> 0.0
 */

static VALUE
rb_str_to_f(VALUE str)
{
    return DBL2NUM(rb_str_to_dbl(str, FALSE));
}


/*
 *  call-seq:
 *     str.to_s     -> str
 *     str.to_str   -> str
 *
 *  Returns +self+.
 *
 *  If called on a subclass of String, converts the receiver to a String object.
 */

static VALUE
rb_str_to_s(VALUE str)
{
    if (rb_obj_class(str) != rb_cString) {
	return str_duplicate(rb_cString, str);
    }
    return str;
}

#if 0
static void
str_cat_char(VALUE str, unsigned int c, rb_encoding *enc)
{
    char s[RUBY_MAX_CHAR_LEN];
    int n = rb_enc_codelen(c, enc);

    rb_enc_mbcput(c, s, enc);
    rb_enc_str_buf_cat(str, s, n, enc);
}
#endif

#define CHAR_ESC_LEN 13 /* sizeof(\x{ hex of 32bit unsigned int } \0) */

int
rb_str_buf_cat_escaped_char(VALUE result, unsigned int c, int unicode_p)
{
    char buf[CHAR_ESC_LEN + 1];
    int l;

#if SIZEOF_INT > 4
    c &= 0xffffffff;
#endif
    if (unicode_p) {
	if (c < 0x7F && ISPRINT(c)) {
	    snprintf(buf, CHAR_ESC_LEN, "%c", c);
	}
	else if (c < 0x10000) {
	    snprintf(buf, CHAR_ESC_LEN, "\\u%04X", c);
	}
	else {
	    snprintf(buf, CHAR_ESC_LEN, "\\u{%X}", c);
	}
    }
    else {
	if (c < 0x100) {
	    snprintf(buf, CHAR_ESC_LEN, "\\x%02X", c);
	}
	else {
	    snprintf(buf, CHAR_ESC_LEN, "\\x{%X}", c);
	}
    }
    l = (int)strlen(buf);	/* CHAR_ESC_LEN cannot exceed INT_MAX */
    rb_str_buf_cat(result, buf, l);
    return l;
}

VALUE
rb_str_escape(VALUE str)
{
    int encidx = ENCODING_GET(str);
    rb_encoding *enc = rb_enc_from_index(encidx);
    const char *p = RSTRING_PTR(str);
    const char *pend = RSTRING_END(str);
    const char *prev = p;
    char buf[CHAR_ESC_LEN + 1];
    VALUE result = rb_str_buf_new(0);
    int unicode_p = rb_enc_unicode_p(enc);
    int asciicompat = rb_enc_asciicompat(enc);

    while (p < pend) {
	unsigned int c, cc;
	int n = rb_enc_precise_mbclen(p, pend, enc);
        if (!MBCLEN_CHARFOUND_P(n)) {
	    if (p > prev) str_buf_cat(result, prev, p - prev);
            n = rb_enc_mbminlen(enc);
            if (pend < p + n)
                n = (int)(pend - p);
            while (n--) {
                snprintf(buf, CHAR_ESC_LEN, "\\x%02X", *p & 0377);
                str_buf_cat(result, buf, strlen(buf));
                prev = ++p;
            }
	    continue;
	}
        n = MBCLEN_CHARFOUND_LEN(n);
	c = rb_enc_mbc_to_codepoint(p, pend, enc);
	p += n;
	switch (c) {
	  case '\n': cc = 'n'; break;
	  case '\r': cc = 'r'; break;
	  case '\t': cc = 't'; break;
	  case '\f': cc = 'f'; break;
	  case '\013': cc = 'v'; break;
	  case '\010': cc = 'b'; break;
	  case '\007': cc = 'a'; break;
	  case 033: cc = 'e'; break;
	  default: cc = 0; break;
	}
	if (cc) {
	    if (p - n > prev) str_buf_cat(result, prev, p - n - prev);
	    buf[0] = '\\';
	    buf[1] = (char)cc;
	    str_buf_cat(result, buf, 2);
	    prev = p;
	}
	else if (asciicompat && rb_enc_isascii(c, enc) && ISPRINT(c)) {
	}
	else {
	    if (p - n > prev) str_buf_cat(result, prev, p - n - prev);
	    rb_str_buf_cat_escaped_char(result, c, unicode_p);
	    prev = p;
	}
    }
    if (p > prev) str_buf_cat(result, prev, p - prev);
    ENCODING_CODERANGE_SET(result, rb_usascii_encindex(), ENC_CODERANGE_7BIT);

    OBJ_INFECT_RAW(result, str);
    return result;
}

/*
 * call-seq:
 *   str.inspect   -> string
 *
 * Returns a printable version of _str_, surrounded by quote marks,
 * with special characters escaped.
 *
 *    str = "hello"
 *    str[3] = "\b"
 *    str.inspect       #=> "\"hel\\bo\""
 */

VALUE
rb_str_inspect(VALUE str)
{
    int encidx = ENCODING_GET(str);
    rb_encoding *enc = rb_enc_from_index(encidx), *actenc;
    const char *p, *pend, *prev;
    char buf[CHAR_ESC_LEN + 1];
    VALUE result = rb_str_buf_new(0);
    rb_encoding *resenc = rb_default_internal_encoding();
    int unicode_p = rb_enc_unicode_p(enc);
    int asciicompat = rb_enc_asciicompat(enc);

    if (resenc == NULL) resenc = rb_default_external_encoding();
    if (!rb_enc_asciicompat(resenc)) resenc = rb_usascii_encoding();
    rb_enc_associate(result, resenc);
    str_buf_cat2(result, "\"");

    p = RSTRING_PTR(str); pend = RSTRING_END(str);
    prev = p;
    actenc = get_actual_encoding(encidx, str);
    if (actenc != enc) {
	enc = actenc;
	if (unicode_p) unicode_p = rb_enc_unicode_p(enc);
    }
    while (p < pend) {
	unsigned int c, cc;
	int n;

        n = rb_enc_precise_mbclen(p, pend, enc);
        if (!MBCLEN_CHARFOUND_P(n)) {
	    if (p > prev) str_buf_cat(result, prev, p - prev);
            n = rb_enc_mbminlen(enc);
            if (pend < p + n)
                n = (int)(pend - p);
            while (n--) {
                snprintf(buf, CHAR_ESC_LEN, "\\x%02X", *p & 0377);
                str_buf_cat(result, buf, strlen(buf));
                prev = ++p;
            }
	    continue;
	}
        n = MBCLEN_CHARFOUND_LEN(n);
	c = rb_enc_mbc_to_codepoint(p, pend, enc);
	p += n;
	if ((asciicompat || unicode_p) &&
	  (c == '"'|| c == '\\' ||
	    (c == '#' &&
             p < pend &&
             MBCLEN_CHARFOUND_P(rb_enc_precise_mbclen(p,pend,enc)) &&
             (cc = rb_enc_codepoint(p,pend,enc),
              (cc == '$' || cc == '@' || cc == '{'))))) {
	    if (p - n > prev) str_buf_cat(result, prev, p - n - prev);
	    str_buf_cat2(result, "\\");
	    if (asciicompat || enc == resenc) {
		prev = p - n;
		continue;
	    }
	}
	switch (c) {
	  case '\n': cc = 'n'; break;
	  case '\r': cc = 'r'; break;
	  case '\t': cc = 't'; break;
	  case '\f': cc = 'f'; break;
	  case '\013': cc = 'v'; break;
	  case '\010': cc = 'b'; break;
	  case '\007': cc = 'a'; break;
	  case 033: cc = 'e'; break;
	  default: cc = 0; break;
	}
	if (cc) {
	    if (p - n > prev) str_buf_cat(result, prev, p - n - prev);
	    buf[0] = '\\';
	    buf[1] = (char)cc;
	    str_buf_cat(result, buf, 2);
	    prev = p;
	    continue;
	}
	if ((enc == resenc && rb_enc_isprint(c, enc)) ||
	    (asciicompat && rb_enc_isascii(c, enc) && ISPRINT(c))) {
	    continue;
	}
	else {
	    if (p - n > prev) str_buf_cat(result, prev, p - n - prev);
	    rb_str_buf_cat_escaped_char(result, c, unicode_p);
	    prev = p;
	    continue;
	}
    }
    if (p > prev) str_buf_cat(result, prev, p - prev);
    str_buf_cat2(result, "\"");

    OBJ_INFECT_RAW(result, str);
    return result;
}

#define IS_EVSTR(p,e) ((p) < (e) && (*(p) == '$' || *(p) == '@' || *(p) == '{'))

/*
 *  call-seq:
 *     str.dump   -> new_str
 *
 *  Produces a version of +str+ with all non-printing characters replaced by
 *  <code>\nnn</code> notation and all special characters escaped.
 *
 *    "hello \n ''".dump  #=> "\"hello \\n ''\"
 */

VALUE
rb_str_dump(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);
    long len;
    const char *p, *pend;
    char *q, *qend;
    VALUE result;
    int u8 = (enc == rb_utf8_encoding());

    len = 2;			/* "" */
    p = RSTRING_PTR(str); pend = p + RSTRING_LEN(str);
    while (p < pend) {
	unsigned char c = *p++;
	switch (c) {
	  case '"':  case '\\':
	  case '\n': case '\r':
	  case '\t': case '\f':
	  case '\013': case '\010': case '\007': case '\033':
	    len += 2;
	    break;

	  case '#':
	    len += IS_EVSTR(p, pend) ? 2 : 1;
	    break;

	  default:
	    if (ISPRINT(c)) {
		len++;
	    }
	    else {
		if (u8 && c > 0x7F) {	/* \u{NN} */
		    int n = rb_enc_precise_mbclen(p-1, pend, enc);
		    if (MBCLEN_CHARFOUND_P(n)) {
			unsigned int cc = rb_enc_mbc_to_codepoint(p-1, pend, enc);
			while (cc >>= 4) len++;
			len += 5;
			p += MBCLEN_CHARFOUND_LEN(n)-1;
			break;
		    }
		}
		len += 4;	/* \xNN */
	    }
	    break;
	}
    }
    if (!rb_enc_asciicompat(enc)) {
	len += 19;		/* ".force_encoding('')" */
	len += strlen(enc->name);
    }

    result = rb_str_new_with_class(str, 0, len);
    p = RSTRING_PTR(str); pend = p + RSTRING_LEN(str);
    q = RSTRING_PTR(result); qend = q + len + 1;

    *q++ = '"';
    while (p < pend) {
	unsigned char c = *p++;

	if (c == '"' || c == '\\') {
	    *q++ = '\\';
	    *q++ = c;
	}
	else if (c == '#') {
	    if (IS_EVSTR(p, pend)) *q++ = '\\';
	    *q++ = '#';
	}
	else if (c == '\n') {
	    *q++ = '\\';
	    *q++ = 'n';
	}
	else if (c == '\r') {
	    *q++ = '\\';
	    *q++ = 'r';
	}
	else if (c == '\t') {
	    *q++ = '\\';
	    *q++ = 't';
	}
	else if (c == '\f') {
	    *q++ = '\\';
	    *q++ = 'f';
	}
	else if (c == '\013') {
	    *q++ = '\\';
	    *q++ = 'v';
	}
	else if (c == '\010') {
	    *q++ = '\\';
	    *q++ = 'b';
	}
	else if (c == '\007') {
	    *q++ = '\\';
	    *q++ = 'a';
	}
	else if (c == '\033') {
	    *q++ = '\\';
	    *q++ = 'e';
	}
	else if (ISPRINT(c)) {
	    *q++ = c;
	}
	else {
	    *q++ = '\\';
	    if (u8) {
		int n = rb_enc_precise_mbclen(p-1, pend, enc) - 1;
		if (MBCLEN_CHARFOUND_P(n)) {
		    int cc = rb_enc_mbc_to_codepoint(p-1, pend, enc);
		    p += n;
		    snprintf(q, qend-q, "u{%x}", cc);
		    q += strlen(q);
		    continue;
		}
	    }
	    snprintf(q, qend-q, "x%02X", c);
	    q += 3;
	}
    }
    *q++ = '"';
    *q = '\0';
    if (!rb_enc_asciicompat(enc)) {
	snprintf(q, qend-q, ".force_encoding(\"%s\")", enc->name);
	enc = rb_ascii8bit_encoding();
    }
    OBJ_INFECT_RAW(result, str);
    /* result from dump is ASCII */
    rb_enc_associate(result, enc);
    ENC_CODERANGE_SET(result, ENC_CODERANGE_7BIT);
    return result;
}


static void
rb_str_check_dummy_enc(rb_encoding *enc)
{
    if (rb_enc_dummy_p(enc)) {
	rb_raise(rb_eEncCompatError, "incompatible encoding with this operation: %s",
		 rb_enc_name(enc));
    }
}

/*
 *  call-seq:
 *     str.upcase!   -> str or nil
 *
 *  Upcases the contents of <i>str</i>, returning <code>nil</code> if no changes
 *  were made.
 *  Note: case replacement is effective only in ASCII region.
 */

static VALUE
rb_str_upcase_bang(VALUE str)
{
    rb_encoding *enc;
    char *s, *send;
    int modify = 0;
    int n;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    rb_str_check_dummy_enc(enc);
    s = RSTRING_PTR(str); send = RSTRING_END(str);
    if (single_byte_optimizable(str)) {
	while (s < send) {
	    unsigned int c = *(unsigned char*)s;

	    if (rb_enc_isascii(c, enc) && 'a' <= c && c <= 'z') {
		*s = 'A' + (c - 'a');
		modify = 1;
	    }
	    s++;
	}
    }
    else {
	int ascompat = rb_enc_asciicompat(enc);

	while (s < send) {
	    unsigned int c;

	    if (ascompat && (c = *(unsigned char*)s) < 0x80) {
		if (rb_enc_isascii(c, enc) && 'a' <= c && c <= 'z') {
		    *s = 'A' + (c - 'a');
		    modify = 1;
		}
		s++;
	    }
	    else {
		c = rb_enc_codepoint_len(s, send, &n, enc);
		if (rb_enc_islower(c, enc)) {
		    /* assuming toupper returns codepoint with same size */
		    rb_enc_mbcput(rb_enc_toupper(c, enc), s, enc);
		    modify = 1;
		}
		s += n;
	    }
	}
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.upcase   -> new_str
 *
 *  Returns a copy of <i>str</i> with all lowercase letters replaced with their
 *  uppercase counterparts. The operation is locale insensitive---only
 *  characters ``a'' to ``z'' are affected.
 *  Note: case replacement is effective only in ASCII region.
 *
 *     "hEllO".upcase   #=> "HELLO"
 */

static VALUE
rb_str_upcase(VALUE str)
{
    str = rb_str_dup(str);
    rb_str_upcase_bang(str);
    return str;
}


/*
 *  call-seq:
 *     str.downcase!   -> str or nil
 *
 *  Downcases the contents of <i>str</i>, returning <code>nil</code> if no
 *  changes were made.
 *  Note: case replacement is effective only in ASCII region.
 */

static VALUE
rb_str_downcase_bang(VALUE str)
{
    rb_encoding *enc;
    char *s, *send;
    int modify = 0;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    rb_str_check_dummy_enc(enc);
    s = RSTRING_PTR(str); send = RSTRING_END(str);
    if (single_byte_optimizable(str)) {
	while (s < send) {
	    unsigned int c = *(unsigned char*)s;

	    if (rb_enc_isascii(c, enc) && 'A' <= c && c <= 'Z') {
		*s = 'a' + (c - 'A');
		modify = 1;
	    }
	    s++;
	}
    }
    else {
	int ascompat = rb_enc_asciicompat(enc);

	while (s < send) {
	    unsigned int c;
	    int n;

	    if (ascompat && (c = *(unsigned char*)s) < 0x80) {
		if (rb_enc_isascii(c, enc) && 'A' <= c && c <= 'Z') {
		    *s = 'a' + (c - 'A');
		    modify = 1;
		}
		s++;
	    }
	    else {
		c = rb_enc_codepoint_len(s, send, &n, enc);
		if (rb_enc_isupper(c, enc)) {
		    /* assuming toupper returns codepoint with same size */
		    rb_enc_mbcput(rb_enc_tolower(c, enc), s, enc);
		    modify = 1;
		}
		s += n;
	    }
	}
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.downcase   -> new_str
 *
 *  Returns a copy of <i>str</i> with all uppercase letters replaced with their
 *  lowercase counterparts. The operation is locale insensitive---only
 *  characters ``A'' to ``Z'' are affected.
 *  Note: case replacement is effective only in ASCII region.
 *
 *     "hEllO".downcase   #=> "hello"
 */

static VALUE
rb_str_downcase(VALUE str)
{
    str = rb_str_dup(str);
    rb_str_downcase_bang(str);
    return str;
}


/*
 *  call-seq:
 *     str.capitalize!   -> str or nil
 *
 *  Modifies <i>str</i> by converting the first character to uppercase and the
 *  remainder to lowercase. Returns <code>nil</code> if no changes are made.
 *  Note: case conversion is effective only in ASCII region.
 *
 *     a = "hello"
 *     a.capitalize!   #=> "Hello"
 *     a               #=> "Hello"
 *     a.capitalize!   #=> nil
 */

static VALUE
rb_str_capitalize_bang(VALUE str)
{
    rb_encoding *enc;
    char *s, *send;
    int modify = 0;
    unsigned int c;
    int n;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    rb_str_check_dummy_enc(enc);
    if (RSTRING_LEN(str) == 0 || !RSTRING_PTR(str)) return Qnil;
    s = RSTRING_PTR(str); send = RSTRING_END(str);

    c = rb_enc_codepoint_len(s, send, &n, enc);
    if (rb_enc_islower(c, enc)) {
	rb_enc_mbcput(rb_enc_toupper(c, enc), s, enc);
	modify = 1;
    }
    s += n;
    while (s < send) {
	c = rb_enc_codepoint_len(s, send, &n, enc);
	if (rb_enc_isupper(c, enc)) {
	    rb_enc_mbcput(rb_enc_tolower(c, enc), s, enc);
	    modify = 1;
	}
	s += n;
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.capitalize   -> new_str
 *
 *  Returns a copy of <i>str</i> with the first character converted to uppercase
 *  and the remainder to lowercase.
 *  Note: case conversion is effective only in ASCII region.
 *
 *     "hello".capitalize    #=> "Hello"
 *     "HELLO".capitalize    #=> "Hello"
 *     "123ABC".capitalize   #=> "123abc"
 */

static VALUE
rb_str_capitalize(VALUE str)
{
    str = rb_str_dup(str);
    rb_str_capitalize_bang(str);
    return str;
}


/*
 *  call-seq:
 *     str.swapcase!   -> str or nil
 *
 *  Equivalent to <code>String#swapcase</code>, but modifies the receiver in
 *  place, returning <i>str</i>, or <code>nil</code> if no changes were made.
 *  Note: case conversion is effective only in ASCII region.
 */

static VALUE
rb_str_swapcase_bang(VALUE str)
{
    rb_encoding *enc;
    char *s, *send;
    int modify = 0;
    int n;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    rb_str_check_dummy_enc(enc);
    s = RSTRING_PTR(str); send = RSTRING_END(str);
    while (s < send) {
	unsigned int c = rb_enc_codepoint_len(s, send, &n, enc);

	if (rb_enc_isupper(c, enc)) {
	    /* assuming toupper returns codepoint with same size */
	    rb_enc_mbcput(rb_enc_tolower(c, enc), s, enc);
	    modify = 1;
	}
	else if (rb_enc_islower(c, enc)) {
	    /* assuming tolower returns codepoint with same size */
	    rb_enc_mbcput(rb_enc_toupper(c, enc), s, enc);
	    modify = 1;
	}
	s += n;
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.swapcase   -> new_str
 *
 *  Returns a copy of <i>str</i> with uppercase alphabetic characters converted
 *  to lowercase and lowercase characters converted to uppercase.
 *  Note: case conversion is effective only in ASCII region.
 *
 *     "Hello".swapcase          #=> "hELLO"
 *     "cYbEr_PuNk11".swapcase   #=> "CyBeR_pUnK11"
 */

static VALUE
rb_str_swapcase(VALUE str)
{
    str = rb_str_dup(str);
    rb_str_swapcase_bang(str);
    return str;
}

typedef unsigned char *USTR;

struct tr {
    int gen;
    unsigned int now, max;
    char *p, *pend;
};

static unsigned int
trnext(struct tr *t, rb_encoding *enc)
{
    int n;

    for (;;) {
	if (!t->gen) {
nextpart:
	    if (t->p == t->pend) return -1;
	    if (rb_enc_ascget(t->p, t->pend, &n, enc) == '\\' && t->p + n < t->pend) {
		t->p += n;
	    }
	    t->now = rb_enc_codepoint_len(t->p, t->pend, &n, enc);
	    t->p += n;
	    if (rb_enc_ascget(t->p, t->pend, &n, enc) == '-' && t->p + n < t->pend) {
		t->p += n;
		if (t->p < t->pend) {
		    unsigned int c = rb_enc_codepoint_len(t->p, t->pend, &n, enc);
		    t->p += n;
		    if (t->now > c) {
			if (t->now < 0x80 && c < 0x80) {
			    rb_raise(rb_eArgError,
				     "invalid range \"%c-%c\" in string transliteration",
				     t->now, c);
			}
			else {
			    rb_raise(rb_eArgError, "invalid range in string transliteration");
			}
			continue; /* not reached */
		    }
		    t->gen = 1;
		    t->max = c;
		}
	    }
	    return t->now;
	}
	else {
	    while (ONIGENC_CODE_TO_MBCLEN(enc, ++t->now) <= 0) {
		if (t->now == t->max) {
		    t->gen = 0;
		    goto nextpart;
		}
	    }
	    if (t->now < t->max) {
		return t->now;
	    }
	    else {
		t->gen = 0;
		return t->max;
	    }
	}
    }
}

static VALUE rb_str_delete_bang(int,VALUE*,VALUE);

static VALUE
tr_trans(VALUE str, VALUE src, VALUE repl, int sflag)
{
    const unsigned int errc = -1;
    unsigned int trans[256];
    rb_encoding *enc, *e1, *e2;
    struct tr trsrc, trrepl;
    int cflag = 0;
    unsigned int c, c0, last = 0;
    int modify = 0, i, l;
    char *s, *send;
    VALUE hash = 0;
    int singlebyte = single_byte_optimizable(str);
    int termlen;
    int cr;

#define CHECK_IF_ASCII(c) \
    (void)((cr == ENC_CODERANGE_7BIT && !rb_isascii(c)) ? \
	   (cr = ENC_CODERANGE_VALID) : 0)

    StringValue(src);
    StringValue(repl);
    if (RSTRING_LEN(str) == 0 || !RSTRING_PTR(str)) return Qnil;
    if (RSTRING_LEN(repl) == 0) {
	return rb_str_delete_bang(1, &src, str);
    }

    cr = ENC_CODERANGE(str);
    e1 = rb_enc_check(str, src);
    e2 = rb_enc_check(str, repl);
    if (e1 == e2) {
	enc = e1;
    }
    else {
	enc = rb_enc_check(src, repl);
    }
    trsrc.p = RSTRING_PTR(src); trsrc.pend = trsrc.p + RSTRING_LEN(src);
    if (RSTRING_LEN(src) > 1 &&
	rb_enc_ascget(trsrc.p, trsrc.pend, &l, enc) == '^' &&
	trsrc.p + l < trsrc.pend) {
	cflag = 1;
	trsrc.p += l;
    }
    trrepl.p = RSTRING_PTR(repl);
    trrepl.pend = trrepl.p + RSTRING_LEN(repl);
    trsrc.gen = trrepl.gen = 0;
    trsrc.now = trrepl.now = 0;
    trsrc.max = trrepl.max = 0;

    if (cflag) {
	for (i=0; i<256; i++) {
	    trans[i] = 1;
	}
	while ((c = trnext(&trsrc, enc)) != errc) {
	    if (c < 256) {
		trans[c] = errc;
	    }
	    else {
		if (!hash) hash = rb_hash_new();
		rb_hash_aset(hash, UINT2NUM(c), Qtrue);
	    }
	}
	while ((c = trnext(&trrepl, enc)) != errc)
	    /* retrieve last replacer */;
	last = trrepl.now;
	for (i=0; i<256; i++) {
	    if (trans[i] != errc) {
		trans[i] = last;
	    }
	}
    }
    else {
	unsigned int r;

	for (i=0; i<256; i++) {
	    trans[i] = errc;
	}
	while ((c = trnext(&trsrc, enc)) != errc) {
	    r = trnext(&trrepl, enc);
	    if (r == errc) r = trrepl.now;
	    if (c < 256) {
		trans[c] = r;
		if (rb_enc_codelen(r, enc) != 1) singlebyte = 0;
	    }
	    else {
		if (!hash) hash = rb_hash_new();
		rb_hash_aset(hash, UINT2NUM(c), UINT2NUM(r));
	    }
	}
    }

    if (cr == ENC_CODERANGE_VALID)
	cr = ENC_CODERANGE_7BIT;
    str_modify_keep_cr(str);
    s = RSTRING_PTR(str); send = RSTRING_END(str);
    termlen = rb_enc_mbminlen(enc);
    if (sflag) {
	int clen, tlen;
	long offset, max = RSTRING_LEN(str);
	unsigned int save = -1;
	char *buf = ALLOC_N(char, max + termlen), *t = buf;

	while (s < send) {
	    int may_modify = 0;

	    c0 = c = rb_enc_codepoint_len(s, send, &clen, e1);
	    tlen = enc == e1 ? clen : rb_enc_codelen(c, enc);

	    s += clen;
	    if (c < 256) {
		c = trans[c];
	    }
	    else if (hash) {
		VALUE tmp = rb_hash_lookup(hash, UINT2NUM(c));
		if (NIL_P(tmp)) {
		    if (cflag) c = last;
		    else c = errc;
		}
		else if (cflag) c = errc;
		else c = NUM2INT(tmp);
	    }
	    else {
		c = errc;
	    }
	    if (c != (unsigned int)-1) {
		if (save == c) {
		    CHECK_IF_ASCII(c);
		    continue;
		}
		save = c;
		tlen = rb_enc_codelen(c, enc);
		modify = 1;
	    }
	    else {
		save = -1;
		c = c0;
		if (enc != e1) may_modify = 1;
	    }
	    while (t - buf + tlen >= max) {
		offset = t - buf;
		max *= 2;
		REALLOC_N(buf, char, max + termlen);
		t = buf + offset;
	    }
	    rb_enc_mbcput(c, t, enc);
	    if (may_modify && memcmp(s, t, tlen) != 0) {
		modify = 1;
	    }
	    CHECK_IF_ASCII(c);
	    t += tlen;
	}
	if (!STR_EMBED_P(str)) {
	    ruby_sized_xfree(STR_HEAP_PTR(str), STR_HEAP_SIZE(str));
	}
	TERM_FILL(t, termlen);
	RSTRING(str)->as.heap.ptr = buf;
	RSTRING(str)->as.heap.len = t - buf;
	STR_SET_NOEMBED(str);
	RSTRING(str)->as.heap.aux.capa = max;
    }
    else if (rb_enc_mbmaxlen(enc) == 1 || (singlebyte && !hash)) {
	while (s < send) {
	    c = (unsigned char)*s;
	    if (trans[c] != errc) {
		if (!cflag) {
		    c = trans[c];
		    *s = c;
		    modify = 1;
		}
		else {
		    *s = last;
		    modify = 1;
		}
	    }
	    CHECK_IF_ASCII(c);
	    s++;
	}
    }
    else {
	int clen, tlen;
	long offset, max = (long)((send - s) * 1.2);
	char *buf = ALLOC_N(char, max + termlen), *t = buf;

	while (s < send) {
	    int may_modify = 0;
	    c0 = c = rb_enc_codepoint_len(s, send, &clen, e1);
	    tlen = enc == e1 ? clen : rb_enc_codelen(c, enc);

	    if (c < 256) {
		c = trans[c];
	    }
	    else if (hash) {
		VALUE tmp = rb_hash_lookup(hash, UINT2NUM(c));
		if (NIL_P(tmp)) {
		    if (cflag) c = last;
		    else c = errc;
		}
		else if (cflag) c = errc;
		else c = NUM2INT(tmp);
	    }
	    else {
		c = cflag ? last : errc;
	    }
	    if (c != errc) {
		tlen = rb_enc_codelen(c, enc);
		modify = 1;
	    }
	    else {
		c = c0;
		if (enc != e1) may_modify = 1;
	    }
	    while (t - buf + tlen >= max) {
		offset = t - buf;
		max *= 2;
		REALLOC_N(buf, char, max + termlen);
		t = buf + offset;
	    }
	    if (s != t) {
		rb_enc_mbcput(c, t, enc);
		if (may_modify && memcmp(s, t, tlen) != 0) {
		    modify = 1;
		}
	    }
	    CHECK_IF_ASCII(c);
	    s += clen;
	    t += tlen;
	}
	if (!STR_EMBED_P(str)) {
	    ruby_sized_xfree(STR_HEAP_PTR(str), STR_HEAP_SIZE(str));
	}
	TERM_FILL(t, termlen);
	RSTRING(str)->as.heap.ptr = buf;
	RSTRING(str)->as.heap.len = t - buf;
	STR_SET_NOEMBED(str);
	RSTRING(str)->as.heap.aux.capa = max;
    }

    if (modify) {
	if (cr != ENC_CODERANGE_BROKEN)
	    ENC_CODERANGE_SET(str, cr);
	rb_enc_associate(str, enc);
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.tr!(from_str, to_str)   -> str or nil
 *
 *  Translates <i>str</i> in place, using the same rules as
 *  <code>String#tr</code>. Returns <i>str</i>, or <code>nil</code> if no
 *  changes were made.
 */

static VALUE
rb_str_tr_bang(VALUE str, VALUE src, VALUE repl)
{
    return tr_trans(str, src, repl, 0);
}


/*
 *  call-seq:
 *     str.tr(from_str, to_str)   => new_str
 *
 *  Returns a copy of +str+ with the characters in +from_str+ replaced by the
 *  corresponding characters in +to_str+.  If +to_str+ is shorter than
 *  +from_str+, it is padded with its last character in order to maintain the
 *  correspondence.
 *
 *     "hello".tr('el', 'ip')      #=> "hippo"
 *     "hello".tr('aeiou', '*')    #=> "h*ll*"
 *     "hello".tr('aeiou', 'AA*')  #=> "hAll*"
 *
 *  Both strings may use the <code>c1-c2</code> notation to denote ranges of
 *  characters, and +from_str+ may start with a <code>^</code>, which denotes
 *  all characters except those listed.
 *
 *     "hello".tr('a-y', 'b-z')    #=> "ifmmp"
 *     "hello".tr('^aeiou', '*')   #=> "*e**o"
 *
 *  The backslash character <code>\\</code> can be used to escape
 *  <code>^</code> or <code>-</code> and is otherwise ignored unless it
 *  appears at the end of a range or the end of the +from_str+ or +to_str+:
 *
 *     "hello^world".tr("\\^aeiou", "*") #=> "h*ll**w*rld"
 *     "hello-world".tr("a\\-eo", "*")   #=> "h*ll**w*rld"
 *
 *     "hello\r\nworld".tr("\r", "")   #=> "hello\nworld"
 *     "hello\r\nworld".tr("\\r", "")  #=> "hello\r\nwold"
 *     "hello\r\nworld".tr("\\\r", "") #=> "hello\nworld"
 *
 *     "X['\\b']".tr("X\\", "")   #=> "['b']"
 *     "X['\\b']".tr("X-\\]", "") #=> "'b'"
 */

static VALUE
rb_str_tr(VALUE str, VALUE src, VALUE repl)
{
    str = rb_str_dup(str);
    tr_trans(str, src, repl, 0);
    return str;
}

#define TR_TABLE_SIZE 257
static void
tr_setup_table(VALUE str, char stable[TR_TABLE_SIZE], int first,
	       VALUE *tablep, VALUE *ctablep, rb_encoding *enc)
{
    const unsigned int errc = -1;
    char buf[256];
    struct tr tr;
    unsigned int c;
    VALUE table = 0, ptable = 0;
    int i, l, cflag = 0;

    tr.p = RSTRING_PTR(str); tr.pend = tr.p + RSTRING_LEN(str);
    tr.gen = tr.now = tr.max = 0;

    if (RSTRING_LEN(str) > 1 && rb_enc_ascget(tr.p, tr.pend, &l, enc) == '^') {
	cflag = 1;
	tr.p += l;
    }
    if (first) {
	for (i=0; i<256; i++) {
	    stable[i] = 1;
	}
	stable[256] = cflag;
    }
    else if (stable[256] && !cflag) {
	stable[256] = 0;
    }
    for (i=0; i<256; i++) {
	buf[i] = cflag;
    }

    while ((c = trnext(&tr, enc)) != errc) {
	if (c < 256) {
	    buf[c & 0xff] = !cflag;
	}
	else {
	    VALUE key = UINT2NUM(c);

	    if (!table && (first || *tablep || stable[256])) {
		if (cflag) {
		    ptable = *ctablep;
		    table = ptable ? ptable : rb_hash_new();
		    *ctablep = table;
		}
		else {
		    table = rb_hash_new();
		    ptable = *tablep;
		    *tablep = table;
		}
	    }
	    if (table && (!ptable || (cflag ^ !NIL_P(rb_hash_aref(ptable, key))))) {
		rb_hash_aset(table, key, Qtrue);
	    }
	}
    }
    for (i=0; i<256; i++) {
	stable[i] = stable[i] && buf[i];
    }
    if (!table && !cflag) {
	*tablep = 0;
    }
}


static int
tr_find(unsigned int c, const char table[TR_TABLE_SIZE], VALUE del, VALUE nodel)
{
    if (c < 256) {
	return table[c] != 0;
    }
    else {
	VALUE v = UINT2NUM(c);

	if (del) {
	    if (!NIL_P(rb_hash_lookup(del, v)) &&
		    (!nodel || NIL_P(rb_hash_lookup(nodel, v)))) {
		return TRUE;
	    }
	}
	else if (nodel && !NIL_P(rb_hash_lookup(nodel, v))) {
	    return FALSE;
	}
	return table[256] ? TRUE : FALSE;
    }
}

/*
 *  call-seq:
 *     str.delete!([other_str]+)   -> str or nil
 *
 *  Performs a <code>delete</code> operation in place, returning <i>str</i>, or
 *  <code>nil</code> if <i>str</i> was not modified.
 */

static VALUE
rb_str_delete_bang(int argc, VALUE *argv, VALUE str)
{
    char squeez[TR_TABLE_SIZE];
    rb_encoding *enc = 0;
    char *s, *send, *t;
    VALUE del = 0, nodel = 0;
    int modify = 0;
    int i, ascompat, cr;

    if (RSTRING_LEN(str) == 0 || !RSTRING_PTR(str)) return Qnil;
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    for (i=0; i<argc; i++) {
	VALUE s = argv[i];

	StringValue(s);
	enc = rb_enc_check(str, s);
	tr_setup_table(s, squeez, i==0, &del, &nodel, enc);
    }

    str_modify_keep_cr(str);
    ascompat = rb_enc_asciicompat(enc);
    s = t = RSTRING_PTR(str);
    send = RSTRING_END(str);
    cr = ascompat ? ENC_CODERANGE_7BIT : ENC_CODERANGE_VALID;
    while (s < send) {
	unsigned int c;
	int clen;

	if (ascompat && (c = *(unsigned char*)s) < 0x80) {
	    if (squeez[c]) {
		modify = 1;
	    }
	    else {
		if (t != s) *t = c;
		t++;
	    }
	    s++;
	}
	else {
	    c = rb_enc_codepoint_len(s, send, &clen, enc);

	    if (tr_find(c, squeez, del, nodel)) {
		modify = 1;
	    }
	    else {
		if (t != s) rb_enc_mbcput(c, t, enc);
		t += clen;
		if (cr == ENC_CODERANGE_7BIT) cr = ENC_CODERANGE_VALID;
	    }
	    s += clen;
	}
    }
    TERM_FILL(t, TERM_LEN(str));
    STR_SET_LEN(str, t - RSTRING_PTR(str));
    ENC_CODERANGE_SET(str, cr);

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.delete([other_str]+)   -> new_str
 *
 *  Returns a copy of <i>str</i> with all characters in the intersection of its
 *  arguments deleted. Uses the same rules for building the set of characters as
 *  <code>String#count</code>.
 *
 *     "hello".delete "l","lo"        #=> "heo"
 *     "hello".delete "lo"            #=> "he"
 *     "hello".delete "aeiou", "^e"   #=> "hell"
 *     "hello".delete "ej-m"          #=> "ho"
 */

static VALUE
rb_str_delete(int argc, VALUE *argv, VALUE str)
{
    str = rb_str_dup(str);
    rb_str_delete_bang(argc, argv, str);
    return str;
}


/*
 *  call-seq:
 *     str.squeeze!([other_str]*)   -> str or nil
 *
 *  Squeezes <i>str</i> in place, returning either <i>str</i>, or
 *  <code>nil</code> if no changes were made.
 */

static VALUE
rb_str_squeeze_bang(int argc, VALUE *argv, VALUE str)
{
    char squeez[TR_TABLE_SIZE];
    rb_encoding *enc = 0;
    VALUE del = 0, nodel = 0;
    char *s, *send, *t;
    int i, modify = 0;
    int ascompat, singlebyte = single_byte_optimizable(str);
    unsigned int save;

    if (argc == 0) {
	enc = STR_ENC_GET(str);
    }
    else {
	for (i=0; i<argc; i++) {
	    VALUE s = argv[i];

	    StringValue(s);
	    enc = rb_enc_check(str, s);
	    if (singlebyte && !single_byte_optimizable(s))
		singlebyte = 0;
	    tr_setup_table(s, squeez, i==0, &del, &nodel, enc);
	}
    }

    str_modify_keep_cr(str);
    s = t = RSTRING_PTR(str);
    if (!s || RSTRING_LEN(str) == 0) return Qnil;
    send = RSTRING_END(str);
    save = -1;
    ascompat = rb_enc_asciicompat(enc);

    if (singlebyte) {
        while (s < send) {
	    unsigned int c = *(unsigned char*)s++;
	    if (c != save || (argc > 0 && !squeez[c])) {
	        *t++ = save = c;
	    }
	}
    }
    else {
	while (s < send) {
	    unsigned int c;
	    int clen;

	    if (ascompat && (c = *(unsigned char*)s) < 0x80) {
		if (c != save || (argc > 0 && !squeez[c])) {
		    *t++ = save = c;
		}
		s++;
	    }
	    else {
		c = rb_enc_codepoint_len(s, send, &clen, enc);

		if (c != save || (argc > 0 && !tr_find(c, squeez, del, nodel))) {
		    if (t != s) rb_enc_mbcput(c, t, enc);
		    save = c;
		    t += clen;
		}
		s += clen;
	    }
	}
    }

    TERM_FILL(t, TERM_LEN(str));
    if (t - RSTRING_PTR(str) != RSTRING_LEN(str)) {
	STR_SET_LEN(str, t - RSTRING_PTR(str));
	modify = 1;
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.squeeze([other_str]*)    -> new_str
 *
 *  Builds a set of characters from the <i>other_str</i> parameter(s) using the
 *  procedure described for <code>String#count</code>. Returns a new string
 *  where runs of the same character that occur in this set are replaced by a
 *  single character. If no arguments are given, all runs of identical
 *  characters are replaced by a single character.
 *
 *     "yellow moon".squeeze                  #=> "yelow mon"
 *     "  now   is  the".squeeze(" ")         #=> " now is the"
 *     "putters shoot balls".squeeze("m-z")   #=> "puters shot balls"
 */

static VALUE
rb_str_squeeze(int argc, VALUE *argv, VALUE str)
{
    str = rb_str_dup(str);
    rb_str_squeeze_bang(argc, argv, str);
    return str;
}


/*
 *  call-seq:
 *     str.tr_s!(from_str, to_str)   -> str or nil
 *
 *  Performs <code>String#tr_s</code> processing on <i>str</i> in place,
 *  returning <i>str</i>, or <code>nil</code> if no changes were made.
 */

static VALUE
rb_str_tr_s_bang(VALUE str, VALUE src, VALUE repl)
{
    return tr_trans(str, src, repl, 1);
}


/*
 *  call-seq:
 *     str.tr_s(from_str, to_str)   -> new_str
 *
 *  Processes a copy of <i>str</i> as described under <code>String#tr</code>,
 *  then removes duplicate characters in regions that were affected by the
 *  translation.
 *
 *     "hello".tr_s('l', 'r')     #=> "hero"
 *     "hello".tr_s('el', '*')    #=> "h*o"
 *     "hello".tr_s('el', 'hx')   #=> "hhxo"
 */

static VALUE
rb_str_tr_s(VALUE str, VALUE src, VALUE repl)
{
    str = rb_str_dup(str);
    tr_trans(str, src, repl, 1);
    return str;
}


/*
 *  call-seq:
 *     str.count([other_str]+)   -> fixnum
 *
 *  Each +other_str+ parameter defines a set of characters to count.  The
 *  intersection of these sets defines the characters to count in +str+.  Any
 *  +other_str+ that starts with a caret <code>^</code> is negated.  The
 *  sequence <code>c1-c2</code> means all characters between c1 and c2.  The
 *  backslash character <code>\\</code> can be used to escape <code>^</code> or
 *  <code>-</code> and is otherwise ignored unless it appears at the end of a
 *  sequence or the end of a +other_str+.
 *
 *     a = "hello world"
 *     a.count "lo"                   #=> 5
 *     a.count "lo", "o"              #=> 2
 *     a.count "hello", "^l"          #=> 4
 *     a.count "ej-m"                 #=> 4
 *
 *     "hello^world".count "\\^aeiou" #=> 4
 *     "hello-world".count "a\\-eo"   #=> 4
 *
 *     c = "hello world\\r\\n"
 *     c.count "\\"                   #=> 2
 *     c.count "\\A"                  #=> 0
 *     c.count "X-\\w"                #=> 3
 */

static VALUE
rb_str_count(int argc, VALUE *argv, VALUE str)
{
    char table[TR_TABLE_SIZE];
    rb_encoding *enc = 0;
    VALUE del = 0, nodel = 0, tstr;
    char *s, *send;
    int i;
    int ascompat;

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);

    tstr = argv[0];
    StringValue(tstr);
    enc = rb_enc_check(str, tstr);
    if (argc == 1) {
	const char *ptstr;
	if (RSTRING_LEN(tstr) == 1 && rb_enc_asciicompat(enc) &&
	    (ptstr = RSTRING_PTR(tstr),
	     ONIGENC_IS_ALLOWED_REVERSE_MATCH(enc, (const unsigned char *)ptstr, (const unsigned char *)ptstr+1)) &&
	    !is_broken_string(str)) {
	    int n = 0;
	    int clen;
	    unsigned char c = rb_enc_codepoint_len(ptstr, ptstr+1, &clen, enc);

	    s = RSTRING_PTR(str);
	    if (!s || RSTRING_LEN(str) == 0) return INT2FIX(0);
	    send = RSTRING_END(str);
	    while (s < send) {
		if (*(unsigned char*)s++ == c) n++;
	    }
	    return INT2NUM(n);
	}
    }

    tr_setup_table(tstr, table, TRUE, &del, &nodel, enc);
    for (i=1; i<argc; i++) {
	tstr = argv[i];
	StringValue(tstr);
	enc = rb_enc_check(str, tstr);
	tr_setup_table(tstr, table, FALSE, &del, &nodel, enc);
    }

    s = RSTRING_PTR(str);
    if (!s || RSTRING_LEN(str) == 0) return INT2FIX(0);
    send = RSTRING_END(str);
    ascompat = rb_enc_asciicompat(enc);
    i = 0;
    while (s < send) {
	unsigned int c;

	if (ascompat && (c = *(unsigned char*)s) < 0x80) {
	    if (table[c]) {
		i++;
	    }
	    s++;
	}
	else {
	    int clen;
	    c = rb_enc_codepoint_len(s, send, &clen, enc);
	    if (tr_find(c, table, del, nodel)) {
		i++;
	    }
	    s += clen;
	}
    }

    return INT2NUM(i);
}

static const char isspacetable[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

#define ascii_isspace(c) isspacetable[(unsigned char)(c)]

/*
 *  call-seq:
 *     str.split(pattern=nil, [limit])   -> anArray
 *
 *  Divides <i>str</i> into substrings based on a delimiter, returning an array
 *  of these substrings.
 *
 *  If <i>pattern</i> is a <code>String</code>, then its contents are used as
 *  the delimiter when splitting <i>str</i>. If <i>pattern</i> is a single
 *  space, <i>str</i> is split on whitespace, with leading whitespace and runs
 *  of contiguous whitespace characters ignored.
 *
 *  If <i>pattern</i> is a <code>Regexp</code>, <i>str</i> is divided where the
 *  pattern matches. Whenever the pattern matches a zero-length string,
 *  <i>str</i> is split into individual characters. If <i>pattern</i> contains
 *  groups, the respective matches will be returned in the array as well.
 *
 *  If <i>pattern</i> is <code>nil</code>, the value of <code>$;</code> is used.
 *  If <code>$;</code> is <code>nil</code> (which is the default), <i>str</i> is
 *  split on whitespace as if ` ' were specified.
 *
 *  If the <i>limit</i> parameter is omitted, trailing null fields are
 *  suppressed. If <i>limit</i> is a positive number, at most that number of
 *  fields will be returned (if <i>limit</i> is <code>1</code>, the entire
 *  string is returned as the only entry in an array). If negative, there is no
 *  limit to the number of fields returned, and trailing null fields are not
 *  suppressed.
 *
 *  When the input +str+ is empty an empty Array is returned as the string is
 *  considered to have no fields to split.
 *
 *     " now's  the time".split        #=> ["now's", "the", "time"]
 *     " now's  the time".split(' ')   #=> ["now's", "the", "time"]
 *     " now's  the time".split(/ /)   #=> ["", "now's", "", "the", "time"]
 *     "1, 2.34,56, 7".split(%r{,\s*}) #=> ["1", "2.34", "56", "7"]
 *     "hello".split(//)               #=> ["h", "e", "l", "l", "o"]
 *     "hello".split(//, 3)            #=> ["h", "e", "llo"]
 *     "hi mom".split(%r{\s*})         #=> ["h", "i", "m", "o", "m"]
 *
 *     "mellow yellow".split("ello")   #=> ["m", "w y", "w"]
 *     "1,2,,3,4,,".split(',')         #=> ["1", "2", "", "3", "4"]
 *     "1,2,,3,4,,".split(',', 4)      #=> ["1", "2", "", "3,4,,"]
 *     "1,2,,3,4,,".split(',', -4)     #=> ["1", "2", "", "3", "4", "", ""]
 *
 *     "".split(',', -1)               #=> []
 */

static VALUE
rb_str_split_m(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    VALUE spat;
    VALUE limit;
    enum {awk, string, regexp} split_type;
    long beg, end, i = 0;
    int lim = 0;
    VALUE result, tmp;

    if (rb_scan_args(argc, argv, "02", &spat, &limit) == 2) {
	lim = NUM2INT(limit);
	if (lim <= 0) limit = Qnil;
	else if (lim == 1) {
	    if (RSTRING_LEN(str) == 0)
		return rb_ary_new2(0);
	    return rb_ary_new3(1, str);
	}
	i = 1;
    }

    enc = STR_ENC_GET(str);
    if (NIL_P(spat) && NIL_P(spat = rb_fs)) {
	split_type = awk;
    }
    else {
	spat = get_pat_quoted(spat, 0);
	if (BUILTIN_TYPE(spat) == T_STRING) {
	    rb_encoding *enc2 = STR_ENC_GET(spat);

	    mustnot_broken(spat);
	    split_type = string;
	    if (RSTRING_LEN(spat) == 0) {
		/* Special case - split into chars */
		spat = rb_reg_regcomp(spat);
		split_type = regexp;
	    }
	    else if (rb_enc_asciicompat(enc2) == 1) {
		if (RSTRING_LEN(spat) == 1 && RSTRING_PTR(spat)[0] == ' '){
		    split_type = awk;
		}
	    }
	    else {
		int l;
		if (rb_enc_ascget(RSTRING_PTR(spat), RSTRING_END(spat), &l, enc2) == ' ' &&
		    RSTRING_LEN(spat) == l) {
		    split_type = awk;
		}
	    }
	}
	else {
	    split_type = regexp;
	}
    }

    result = rb_ary_new();
    beg = 0;
    if (split_type == awk) {
	char *ptr = RSTRING_PTR(str);
	char *eptr = RSTRING_END(str);
	char *bptr = ptr;
	int skip = 1;
	unsigned int c;

	end = beg;
	if (is_ascii_string(str)) {
	    while (ptr < eptr) {
		c = (unsigned char)*ptr++;
		if (skip) {
		    if (ascii_isspace(c)) {
			beg = ptr - bptr;
		    }
		    else {
			end = ptr - bptr;
			skip = 0;
			if (!NIL_P(limit) && lim <= i) break;
		    }
		}
		else if (ascii_isspace(c)) {
		    rb_ary_push(result, rb_str_subseq(str, beg, end-beg));
		    skip = 1;
		    beg = ptr - bptr;
		    if (!NIL_P(limit)) ++i;
		}
		else {
		    end = ptr - bptr;
		}
	    }
	}
	else {
	    while (ptr < eptr) {
		int n;

		c = rb_enc_codepoint_len(ptr, eptr, &n, enc);
		ptr += n;
		if (skip) {
		    if (rb_isspace(c)) {
			beg = ptr - bptr;
		    }
		    else {
			end = ptr - bptr;
			skip = 0;
			if (!NIL_P(limit) && lim <= i) break;
		    }
		}
		else if (rb_isspace(c)) {
		    rb_ary_push(result, rb_str_subseq(str, beg, end-beg));
		    skip = 1;
		    beg = ptr - bptr;
		    if (!NIL_P(limit)) ++i;
		}
		else {
		    end = ptr - bptr;
		}
	    }
	}
    }
    else if (split_type == string) {
	char *ptr = RSTRING_PTR(str);
	char *temp = ptr;
	char *eptr = RSTRING_END(str);
	char *sptr = RSTRING_PTR(spat);
	long slen = RSTRING_LEN(spat);

	mustnot_broken(str);
	enc = rb_enc_check(str, spat);
	while (ptr < eptr &&
	       (end = rb_memsearch(sptr, slen, ptr, eptr - ptr, enc)) >= 0) {
	    /* Check we are at the start of a char */
	    char *t = rb_enc_right_char_head(ptr, ptr + end, eptr, enc);
	    if (t != ptr + end) {
		ptr = t;
		continue;
	    }
	    rb_ary_push(result, rb_str_subseq(str, ptr - temp, end));
	    ptr += end + slen;
	    if (!NIL_P(limit) && lim <= ++i) break;
	}
	beg = ptr - temp;
    }
    else {
	char *ptr = RSTRING_PTR(str);
	long len = RSTRING_LEN(str);
	long start = beg;
	long idx;
	int last_null = 0;
	struct re_registers *regs;

	while ((end = rb_reg_search(spat, str, start, 0)) >= 0) {
	    regs = RMATCH_REGS(rb_backref_get());
	    if (start == end && BEG(0) == END(0)) {
		if (!ptr) {
		    rb_ary_push(result, str_new_empty(str));
		    break;
		}
		else if (last_null == 1) {
		    rb_ary_push(result, rb_str_subseq(str, beg,
						      rb_enc_fast_mbclen(ptr+beg,
									 ptr+len,
									 enc)));
		    beg = start;
		}
		else {
                    if (start == len)
                        start++;
                    else
                        start += rb_enc_fast_mbclen(ptr+start,ptr+len,enc);
		    last_null = 1;
		    continue;
		}
	    }
	    else {
		rb_ary_push(result, rb_str_subseq(str, beg, end-beg));
		beg = start = END(0);
	    }
	    last_null = 0;

	    for (idx=1; idx < regs->num_regs; idx++) {
		if (BEG(idx) == -1) continue;
		if (BEG(idx) == END(idx))
		    tmp = str_new_empty(str);
		else
		    tmp = rb_str_subseq(str, BEG(idx), END(idx)-BEG(idx));
		rb_ary_push(result, tmp);
	    }
	    if (!NIL_P(limit) && lim <= ++i) break;
	}
    }
    if (RSTRING_LEN(str) > 0 && (!NIL_P(limit) || RSTRING_LEN(str) > beg || lim < 0)) {
	if (RSTRING_LEN(str) == beg)
	    tmp = str_new_empty(str);
	else
	    tmp = rb_str_subseq(str, beg, RSTRING_LEN(str)-beg);
	rb_ary_push(result, tmp);
    }
    if (NIL_P(limit) && lim == 0) {
	long len;
	while ((len = RARRAY_LEN(result)) > 0 &&
	       (tmp = RARRAY_AREF(result, len-1), RSTRING_LEN(tmp) == 0))
	    rb_ary_pop(result);
    }

    return result;
}

VALUE
rb_str_split(VALUE str, const char *sep0)
{
    VALUE sep;

    StringValue(str);
    sep = rb_str_new_cstr(sep0);
    return rb_str_split_m(1, &sep, str);
}


static VALUE
rb_str_enumerate_lines(int argc, VALUE *argv, VALUE str, int wantarray)
{
    rb_encoding *enc;
    VALUE line, rs, orig = str;
    const char *ptr, *pend, *subptr, *subend, *rsptr, *hit, *adjusted;
    long pos, len, rslen;
    int paragraph_mode = 0;

    VALUE UNINITIALIZED_VAR(ary);

    if (argc == 0)
	rs = rb_rs;
    else
	rb_scan_args(argc, argv, "01", &rs);

    if (rb_block_given_p()) {
	if (wantarray) {
#if STRING_ENUMERATORS_WANTARRAY
	    rb_warn("given block not used");
	    ary = rb_ary_new();
#else
	    rb_warning("passing a block to String#lines is deprecated");
	    wantarray = 0;
#endif
	}
    }
    else {
	if (wantarray)
	    ary = rb_ary_new();
	else
	    return SIZED_ENUMERATOR(str, argc, argv, 0);
    }

    if (NIL_P(rs)) {
	if (wantarray) {
	    rb_ary_push(ary, str);
	    return ary;
	}
	else {
	    rb_yield(str);
	    return orig;
	}
    }

    str = rb_str_new_frozen(str);
    ptr = subptr = RSTRING_PTR(str);
    pend = RSTRING_END(str);
    len = RSTRING_LEN(str);
    StringValue(rs);
    rslen = RSTRING_LEN(rs);

    if (rs == rb_default_rs)
	enc = rb_enc_get(str);
    else
	enc = rb_enc_check(str, rs);

    if (rslen == 0) {
	rsptr = "\n\n";
	rslen = 2;
	paragraph_mode = 1;
    }
    else {
	rsptr = RSTRING_PTR(rs);
    }

    if ((rs == rb_default_rs || paragraph_mode) && !rb_enc_asciicompat(enc)) {
	rs = rb_str_new(rsptr, rslen);
	rs = rb_str_encode(rs, rb_enc_from_encoding(enc), 0, Qnil);
	rsptr = RSTRING_PTR(rs);
	rslen = RSTRING_LEN(rs);
    }

    while (subptr < pend) {
	pos = rb_memsearch(rsptr, rslen, subptr, pend - subptr, enc);
	if (pos < 0) break;
	hit = subptr + pos;
	adjusted = rb_enc_right_char_head(subptr, hit, pend, enc);
	if (hit != adjusted) {
	    subptr = adjusted;
	    continue;
	}
	subend = hit + rslen;
	if (paragraph_mode) {
	    while (subend < pend && rb_enc_is_newline(subend, pend, enc)) {
		subend += rb_enc_mbclen(subend, pend, enc);
	    }
	}
	line = rb_str_subseq(str, subptr - ptr, subend - subptr);
	if (wantarray) {
	    rb_ary_push(ary, line);
	}
	else {
	    rb_yield(line);
	    str_mod_check(str, ptr, len);
	}
	subptr = subend;
    }

    if (subptr != pend) {
	line = rb_str_subseq(str, subptr - ptr, pend - subptr);
	if (wantarray)
	    rb_ary_push(ary, line);
	else
	    rb_yield(line);
	RB_GC_GUARD(str);
    }

    if (wantarray)
	return ary;
    else
	return orig;
}

/*
 *  call-seq:
 *     str.each_line(separator=$/) {|substr| block }   -> str
 *     str.each_line(separator=$/)                     -> an_enumerator
 *
 *  Splits <i>str</i> using the supplied parameter as the record
 *  separator (<code>$/</code> by default), passing each substring in
 *  turn to the supplied block.  If a zero-length record separator is
 *  supplied, the string is split into paragraphs delimited by
 *  multiple successive newlines.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     print "Example one\n"
 *     "hello\nworld".each_line {|s| p s}
 *     print "Example two\n"
 *     "hello\nworld".each_line('l') {|s| p s}
 *     print "Example three\n"
 *     "hello\n\n\nworld".each_line('') {|s| p s}
 *
 *  <em>produces:</em>
 *
 *     Example one
 *     "hello\n"
 *     "world"
 *     Example two
 *     "hel"
 *     "l"
 *     "o\nworl"
 *     "d"
 *     Example three
 *     "hello\n\n\n"
 *     "world"
 */

static VALUE
rb_str_each_line(int argc, VALUE *argv, VALUE str)
{
    return rb_str_enumerate_lines(argc, argv, str, 0);
}

/*
 *  call-seq:
 *     str.lines(separator=$/)  -> an_array
 *
 *  Returns an array of lines in <i>str</i> split using the supplied
 *  record separator (<code>$/</code> by default).  This is a
 *  shorthand for <code>str.each_line(separator).to_a</code>.
 *
 *  If a block is given, which is a deprecated form, works the same as
 *  <code>each_line</code>.
 */

static VALUE
rb_str_lines(int argc, VALUE *argv, VALUE str)
{
    return rb_str_enumerate_lines(argc, argv, str, 1);
}

static VALUE
rb_str_each_byte_size(VALUE str, VALUE args, VALUE eobj)
{
    return LONG2FIX(RSTRING_LEN(str));
}

static VALUE
rb_str_enumerate_bytes(VALUE str, int wantarray)
{
    long i;
    VALUE UNINITIALIZED_VAR(ary);

    if (rb_block_given_p()) {
	if (wantarray) {
#if STRING_ENUMERATORS_WANTARRAY
	    rb_warn("given block not used");
	    ary = rb_ary_new();
#else
	    rb_warning("passing a block to String#bytes is deprecated");
	    wantarray = 0;
#endif
	}
    }
    else {
	if (wantarray)
	    ary = rb_ary_new2(RSTRING_LEN(str));
	else
	    return SIZED_ENUMERATOR(str, 0, 0, rb_str_each_byte_size);
    }

    for (i=0; i<RSTRING_LEN(str); i++) {
	if (wantarray)
	    rb_ary_push(ary, INT2FIX(RSTRING_PTR(str)[i] & 0xff));
	else
	    rb_yield(INT2FIX(RSTRING_PTR(str)[i] & 0xff));
    }
    if (wantarray)
	return ary;
    else
	return str;
}

/*
 *  call-seq:
 *     str.each_byte {|fixnum| block }    -> str
 *     str.each_byte                      -> an_enumerator
 *
 *  Passes each byte in <i>str</i> to the given block, or returns an
 *  enumerator if no block is given.
 *
 *     "hello".each_byte {|c| print c, ' ' }
 *
 *  <em>produces:</em>
 *
 *     104 101 108 108 111
 */

static VALUE
rb_str_each_byte(VALUE str)
{
    return rb_str_enumerate_bytes(str, 0);
}

/*
 *  call-seq:
 *     str.bytes    -> an_array
 *
 *  Returns an array of bytes in <i>str</i>.  This is a shorthand for
 *  <code>str.each_byte.to_a</code>.
 *
 *  If a block is given, which is a deprecated form, works the same as
 *  <code>each_byte</code>.
 */

static VALUE
rb_str_bytes(VALUE str)
{
    return rb_str_enumerate_bytes(str, 1);
}

static VALUE
rb_str_each_char_size(VALUE str, VALUE args, VALUE eobj)
{
    return rb_str_length(str);
}

static VALUE
rb_str_enumerate_chars(VALUE str, int wantarray)
{
    VALUE orig = str;
    VALUE substr;
    long i, len, n;
    const char *ptr;
    rb_encoding *enc;
    VALUE UNINITIALIZED_VAR(ary);

    str = rb_str_new_frozen(str);
    ptr = RSTRING_PTR(str);
    len = RSTRING_LEN(str);
    enc = rb_enc_get(str);

    if (rb_block_given_p()) {
	if (wantarray) {
#if STRING_ENUMERATORS_WANTARRAY
	    rb_warn("given block not used");
	    ary = rb_ary_new_capa(str_strlen(str, enc)); /* str's enc*/
#else
	    rb_warning("passing a block to String#chars is deprecated");
	    wantarray = 0;
#endif
	}
    }
    else {
	if (wantarray)
	    ary = rb_ary_new_capa(str_strlen(str, enc)); /* str's enc*/
	else
	    return SIZED_ENUMERATOR(str, 0, 0, rb_str_each_char_size);
    }

    if (ENC_CODERANGE_CLEAN_P(ENC_CODERANGE(str))) {
	for (i = 0; i < len; i += n) {
	    n = rb_enc_fast_mbclen(ptr + i, ptr + len, enc);
	    substr = rb_str_subseq(str, i, n);
	    if (wantarray)
		rb_ary_push(ary, substr);
	    else
		rb_yield(substr);
	}
    }
    else {
	for (i = 0; i < len; i += n) {
	    n = rb_enc_mbclen(ptr + i, ptr + len, enc);
	    substr = rb_str_subseq(str, i, n);
	    if (wantarray)
		rb_ary_push(ary, substr);
	    else
		rb_yield(substr);
	}
    }
    RB_GC_GUARD(str);
    if (wantarray)
	return ary;
    else
	return orig;
}

/*
 *  call-seq:
 *     str.each_char {|cstr| block }    -> str
 *     str.each_char                    -> an_enumerator
 *
 *  Passes each character in <i>str</i> to the given block, or returns
 *  an enumerator if no block is given.
 *
 *     "hello".each_char {|c| print c, ' ' }
 *
 *  <em>produces:</em>
 *
 *     h e l l o
 */

static VALUE
rb_str_each_char(VALUE str)
{
    return rb_str_enumerate_chars(str, 0);
}

/*
 *  call-seq:
 *     str.chars    -> an_array
 *
 *  Returns an array of characters in <i>str</i>.  This is a shorthand
 *  for <code>str.each_char.to_a</code>.
 *
 *  If a block is given, which is a deprecated form, works the same as
 *  <code>each_char</code>.
 */

static VALUE
rb_str_chars(VALUE str)
{
    return rb_str_enumerate_chars(str, 1);
}


static VALUE
rb_str_enumerate_codepoints(VALUE str, int wantarray)
{
    VALUE orig = str;
    int n;
    unsigned int c;
    const char *ptr, *end;
    rb_encoding *enc;
    VALUE UNINITIALIZED_VAR(ary);

    if (single_byte_optimizable(str))
	return rb_str_enumerate_bytes(str, wantarray);

    str = rb_str_new_frozen(str);
    ptr = RSTRING_PTR(str);
    end = RSTRING_END(str);
    enc = STR_ENC_GET(str);

    if (rb_block_given_p()) {
	if (wantarray) {
#if STRING_ENUMERATORS_WANTARRAY
	    rb_warn("given block not used");
	    ary = rb_ary_new_capa(str_strlen(str, enc)); /* str's enc*/
#else
	    rb_warning("passing a block to String#codepoints is deprecated");
	    wantarray = 0;
#endif
	}
    }
    else {
	if (wantarray)
	    ary = rb_ary_new_capa(str_strlen(str, enc)); /* str's enc*/
	else
	    return SIZED_ENUMERATOR(str, 0, 0, rb_str_each_char_size);
    }

    while (ptr < end) {
	c = rb_enc_codepoint_len(ptr, end, &n, enc);
	if (wantarray)
	    rb_ary_push(ary, UINT2NUM(c));
	else
	    rb_yield(UINT2NUM(c));
	ptr += n;
    }
    RB_GC_GUARD(str);
    if (wantarray)
	return ary;
    else
	return orig;
}

/*
 *  call-seq:
 *     str.each_codepoint {|integer| block }    -> str
 *     str.each_codepoint                       -> an_enumerator
 *
 *  Passes the <code>Integer</code> ordinal of each character in <i>str</i>,
 *  also known as a <i>codepoint</i> when applied to Unicode strings to the
 *  given block.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     "hello\u0639".each_codepoint {|c| print c, ' ' }
 *
 *  <em>produces:</em>
 *
 *     104 101 108 108 111 1593
 */

static VALUE
rb_str_each_codepoint(VALUE str)
{
    return rb_str_enumerate_codepoints(str, 0);
}

/*
 *  call-seq:
 *     str.codepoints   -> an_array
 *
 *  Returns an array of the <code>Integer</code> ordinals of the
 *  characters in <i>str</i>.  This is a shorthand for
 *  <code>str.each_codepoint.to_a</code>.
 *
 *  If a block is given, which is a deprecated form, works the same as
 *  <code>each_codepoint</code>.
 */

static VALUE
rb_str_codepoints(VALUE str)
{
    return rb_str_enumerate_codepoints(str, 1);
}


static long
chopped_length(VALUE str)
{
    rb_encoding *enc = STR_ENC_GET(str);
    const char *p, *p2, *beg, *end;

    beg = RSTRING_PTR(str);
    end = beg + RSTRING_LEN(str);
    if (beg > end) return 0;
    p = rb_enc_prev_char(beg, end, end, enc);
    if (!p) return 0;
    if (p > beg && rb_enc_ascget(p, end, 0, enc) == '\n') {
	p2 = rb_enc_prev_char(beg, p, end, enc);
	if (p2 && rb_enc_ascget(p2, end, 0, enc) == '\r') p = p2;
    }
    return p - beg;
}

/*
 *  call-seq:
 *     str.chop!   -> str or nil
 *
 *  Processes <i>str</i> as for <code>String#chop</code>, returning <i>str</i>,
 *  or <code>nil</code> if <i>str</i> is the empty string.  See also
 *  <code>String#chomp!</code>.
 */

static VALUE
rb_str_chop_bang(VALUE str)
{
    str_modify_keep_cr(str);
    if (RSTRING_LEN(str) > 0) {
	long len;
	len = chopped_length(str);
	STR_SET_LEN(str, len);
	TERM_FILL(&RSTRING_PTR(str)[len], TERM_LEN(str));
	if (ENC_CODERANGE(str) != ENC_CODERANGE_7BIT) {
	    ENC_CODERANGE_CLEAR(str);
	}
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.chop   -> new_str
 *
 *  Returns a new <code>String</code> with the last character removed.  If the
 *  string ends with <code>\r\n</code>, both characters are removed. Applying
 *  <code>chop</code> to an empty string returns an empty
 *  string. <code>String#chomp</code> is often a safer alternative, as it leaves
 *  the string unchanged if it doesn't end in a record separator.
 *
 *     "string\r\n".chop   #=> "string"
 *     "string\n\r".chop   #=> "string\n"
 *     "string\n".chop     #=> "string"
 *     "string".chop       #=> "strin"
 *     "x".chop.chop       #=> ""
 */

static VALUE
rb_str_chop(VALUE str)
{
    return rb_str_subseq(str, 0, chopped_length(str));
}


static long
chompped_length(VALUE str, VALUE rs)
{
    rb_encoding *enc;
    int newline;
    char *pp, *e, *rsptr;
    long rslen;
    char *const p = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);

    if (len == 0) return 0;
    e = p + len;
    if (rs == rb_default_rs) {
      smart_chomp:
	enc = rb_enc_get(str);
	if (rb_enc_mbminlen(enc) > 1) {
	    pp = rb_enc_left_char_head(p, e-rb_enc_mbminlen(enc), e, enc);
	    if (rb_enc_is_newline(pp, e, enc)) {
		e = pp;
	    }
	    pp = e - rb_enc_mbminlen(enc);
	    if (pp >= p) {
		pp = rb_enc_left_char_head(p, pp, e, enc);
		if (rb_enc_ascget(pp, e, 0, enc) == '\r') {
		    e = pp;
		}
	    }
	}
	else {
	    switch (*(e-1)) { /* not e[-1] to get rid of VC bug */
	      case '\n':
		if (--e > p && *(e-1) == '\r') {
		    --e;
		}
		break;
	      case '\r':
		--e;
		break;
	    }
	}
	return e - p;
    }

    enc = rb_enc_get(str);
    RSTRING_GETMEM(rs, rsptr, rslen);
    if (rslen == 0) {
	if (rb_enc_mbminlen(enc) > 1) {
	    while (e > p) {
		pp = rb_enc_left_char_head(p, e-rb_enc_mbminlen(enc), e, enc);
		if (!rb_enc_is_newline(pp, e, enc)) break;
		e = pp;
		pp -= rb_enc_mbminlen(enc);
		if (pp >= p) {
		    pp = rb_enc_left_char_head(p, pp, e, enc);
		    if (rb_enc_ascget(pp, e, 0, enc) == '\r') {
			e = pp;
		    }
		}
	    }
	}
	else {
	    while (e > p && *(e-1) == '\n') {
		--e;
		if (e > p && *(e-1) == '\r')
		    --e;
	    }
	}
	return e - p;
    }
    if (rslen > len) return len;

    enc = rb_enc_get(rs);
    newline = rsptr[rslen-1];
    if (rslen == rb_enc_mbminlen(enc)) {
	if (rslen == 1) {
	    if (newline == '\n')
		goto smart_chomp;
	}
	else {
	    if (rb_enc_is_newline(rsptr, rsptr+rslen, enc))
		goto smart_chomp;
	}
    }

    enc = rb_enc_check(str, rs);
    if (is_broken_string(rs)) {
	return len;
    }
    pp = e - rslen;
    if (p[len-1] == newline &&
	(rslen <= 1 ||
	 memcmp(rsptr, pp, rslen) == 0)) {
	if (rb_enc_left_char_head(p, pp, e, enc) == pp)
	    return len - rslen;
	RB_GC_GUARD(rs);
    }
    return len;
}

static VALUE
chomp_rs(int argc, const VALUE *argv)
{
    rb_check_arity(argc, 0, 1);
    if (argc > 0) {
	VALUE rs = argv[0];
	if (!NIL_P(rs)) StringValue(rs);
	return rs;
    }
    else {
	return rb_rs;
    }
}

/*
 *  call-seq:
 *     str.chomp!(separator=$/)   -> str or nil
 *
 *  Modifies <i>str</i> in place as described for <code>String#chomp</code>,
 *  returning <i>str</i>, or <code>nil</code> if no modifications were made.
 */

static VALUE
rb_str_chomp_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE rs;
    long olen;
    str_modify_keep_cr(str);
    if ((olen = RSTRING_LEN(str)) > 0 && !NIL_P(rs = chomp_rs(argc, argv))) {
	long len;
	len = chompped_length(str, rs);
	if (len < olen) {
	    STR_SET_LEN(str, len);
	    TERM_FILL(&RSTRING_PTR(str)[len], TERM_LEN(str));
	    if (ENC_CODERANGE(str) != ENC_CODERANGE_7BIT) {
		ENC_CODERANGE_CLEAR(str);
	    }
	    return str;
	}
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.chomp(separator=$/)   -> new_str
 *
 *  Returns a new <code>String</code> with the given record separator removed
 *  from the end of <i>str</i> (if present). If <code>$/</code> has not been
 *  changed from the default Ruby record separator, then <code>chomp</code> also
 *  removes carriage return characters (that is it will remove <code>\n</code>,
 *  <code>\r</code>, and <code>\r\n</code>). If <code>$/</code> is an empty string,
 *  it will remove all trailing newlines from the string.
 *
 *     "hello".chomp                #=> "hello"
 *     "hello\n".chomp              #=> "hello"
 *     "hello\r\n".chomp            #=> "hello"
 *     "hello\n\r".chomp            #=> "hello\n"
 *     "hello\r".chomp              #=> "hello"
 *     "hello \n there".chomp       #=> "hello \n there"
 *     "hello".chomp("llo")         #=> "he"
 *     "hello\r\n\r\n".chomp('')    #=> "hello"
 *     "hello\r\n\r\r\n".chomp('')  #=> "hello\r\n\r"
 */

static VALUE
rb_str_chomp(int argc, VALUE *argv, VALUE str)
{
    VALUE rs = chomp_rs(argc, argv);
    if (NIL_P(rs)) return rb_str_dup(str);
    return rb_str_subseq(str, 0, chompped_length(str, rs));
}

static long
lstrip_offset(VALUE str, const char *s, const char *e, rb_encoding *enc)
{
    const char *const start = s;

    if (!s || s >= e) return 0;
    /* remove spaces at head */
    while (s < e) {
	int n;
	unsigned int cc = rb_enc_codepoint_len(s, e, &n, enc);

	if (!rb_isspace(cc)) break;
	s += n;
    }
    return s - start;
}

/*
 *  call-seq:
 *     str.lstrip!   -> self or nil
 *
 *  Removes leading whitespace from <i>str</i>, returning <code>nil</code> if no
 *  change was made. See also <code>String#rstrip!</code> and
 *  <code>String#strip!</code>.
 *
 *  Refer to <code>strip</code> for the definition of whitespace.
 *
 *     "  hello  ".lstrip   #=> "hello  "
 *     "hello".lstrip!      #=> nil
 */

static VALUE
rb_str_lstrip_bang(VALUE str)
{
    rb_encoding *enc;
    char *start, *s;
    long olen, loffset;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    RSTRING_GETMEM(str, start, olen);
    loffset = lstrip_offset(str, start, start+olen, enc);
    if (loffset > 0) {
	long len = olen-loffset;
	s = start + loffset;
	memmove(start, s, len);
	STR_SET_LEN(str, len);
#if !SHARABLE_MIDDLE_SUBSTRING
	TERM_FILL(start+len, rb_enc_mbminlen(enc));
#endif
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.lstrip   -> new_str
 *
 *  Returns a copy of <i>str</i> with leading whitespace removed. See also
 *  <code>String#rstrip</code> and <code>String#strip</code>.
 *
 *  Refer to <code>strip</code> for the definition of whitespace.
 *
 *     "  hello  ".lstrip   #=> "hello  "
 *     "hello".lstrip       #=> "hello"
 */

static VALUE
rb_str_lstrip(VALUE str)
{
    char *start;
    long len, loffset;
    RSTRING_GETMEM(str, start, len);
    loffset = lstrip_offset(str, start, start+len, STR_ENC_GET(str));
    if (loffset <= 0) return rb_str_dup(str);
    return rb_str_subseq(str, loffset, len - loffset);
}

static long
rstrip_offset(VALUE str, const char *s, const char *e, rb_encoding *enc)
{
    const char *t;

    rb_str_check_dummy_enc(enc);
    if (!s || s >= e) return 0;
    t = e;

    /* remove trailing spaces or '\0's */
    if (single_byte_optimizable(str)) {
	unsigned char c;
	while (s < t && ((c = *(t-1)) == '\0' || ascii_isspace(c))) t--;
    }
    else {
	char *tp;

        while ((tp = rb_enc_prev_char(s, t, e, enc)) != NULL) {
	    unsigned int c = rb_enc_codepoint(tp, e, enc);
	    if (c && !rb_isspace(c)) break;
	    t = tp;
	}
    }
    return e - t;
}

/*
 *  call-seq:
 *     str.rstrip!   -> self or nil
 *
 *  Removes trailing whitespace from <i>str</i>, returning <code>nil</code> if
 *  no change was made. See also <code>String#lstrip!</code> and
 *  <code>String#strip!</code>.
 *
 *  Refer to <code>strip</code> for the definition of whitespace.
 *
 *     "  hello  ".rstrip   #=> "  hello"
 *     "hello".rstrip!      #=> nil
 */

static VALUE
rb_str_rstrip_bang(VALUE str)
{
    rb_encoding *enc;
    char *start;
    long olen, roffset;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    RSTRING_GETMEM(str, start, olen);
    roffset = rstrip_offset(str, start, start+olen, enc);
    if (roffset > 0) {
	long len = olen - roffset;

	STR_SET_LEN(str, len);
#if !SHARABLE_MIDDLE_SUBSTRING
	TERM_FILL(start+len, rb_enc_mbminlen(enc));
#endif
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.rstrip   -> new_str
 *
 *  Returns a copy of <i>str</i> with trailing whitespace removed. See also
 *  <code>String#lstrip</code> and <code>String#strip</code>.
 *
 *  Refer to <code>strip</code> for the definition of whitespace.
 *
 *     "  hello  ".rstrip   #=> "  hello"
 *     "hello".rstrip       #=> "hello"
 */

static VALUE
rb_str_rstrip(VALUE str)
{
    rb_encoding *enc;
    char *start;
    long olen, roffset;

    enc = STR_ENC_GET(str);
    RSTRING_GETMEM(str, start, olen);
    roffset = rstrip_offset(str, start, start+olen, enc);

    if (roffset <= 0) return rb_str_dup(str);
    return rb_str_subseq(str, 0, olen-roffset);
}


/*
 *  call-seq:
 *     str.strip!   -> str or nil
 *
 *  Removes leading and trailing whitespace from <i>str</i>. Returns
 *  <code>nil</code> if <i>str</i> was not altered.
 *
 *  Refer to <code>strip</code> for the definition of whitespace.
 */

static VALUE
rb_str_strip_bang(VALUE str)
{
    char *start;
    long olen, loffset, roffset;
    rb_encoding *enc;

    str_modify_keep_cr(str);
    enc = STR_ENC_GET(str);
    RSTRING_GETMEM(str, start, olen);
    loffset = lstrip_offset(str, start, start+olen, enc);
    roffset = rstrip_offset(str, start+loffset, start+olen, enc);

    if (loffset > 0 || roffset > 0) {
	long len = olen-roffset;
	if (loffset > 0) {
	    len -= loffset;
	    memmove(start, start + loffset, len);
	}
	STR_SET_LEN(str, len);
#if !SHARABLE_MIDDLE_SUBSTRING
	TERM_FILL(start+len, rb_enc_mbminlen(enc));
#endif
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.strip   -> new_str
 *
 *  Returns a copy of <i>str</i> with leading and trailing whitespace removed.
 *
 *  Whitespace is defined as any of the following characters:
 *  null, horizontal tab, line feed, vertical tab, form feed, carriage return, space.
 *
 *     "    hello    ".strip   #=> "hello"
 *     "\tgoodbye\r\n".strip   #=> "goodbye"
 *     "\x00\t\n\v\f\r ".strip #=> ""
 */

static VALUE
rb_str_strip(VALUE str)
{
    char *start;
    long olen, loffset, roffset;
    rb_encoding *enc = STR_ENC_GET(str);

    RSTRING_GETMEM(str, start, olen);
    loffset = lstrip_offset(str, start, start+olen, enc);
    roffset = rstrip_offset(str, start+loffset, start+olen, enc);

    if (loffset <= 0 && roffset <= 0) return rb_str_dup(str);
    return rb_str_subseq(str, loffset, olen-loffset-roffset);
}

static VALUE
scan_once(VALUE str, VALUE pat, long *start)
{
    VALUE result, match;
    struct re_registers *regs;
    int i;

    if (rb_pat_search(pat, str, *start, 1) >= 0) {
	match = rb_backref_get();
	regs = RMATCH_REGS(match);
	if (BEG(0) == END(0)) {
	    rb_encoding *enc = STR_ENC_GET(str);
	    /*
	     * Always consume at least one character of the input string
	     */
	    if (RSTRING_LEN(str) > END(0))
		*start = END(0)+rb_enc_fast_mbclen(RSTRING_PTR(str)+END(0),
						   RSTRING_END(str), enc);
	    else
		*start = END(0)+1;
	}
	else {
	    *start = END(0);
	}
	if (regs->num_regs == 1) {
	    return rb_reg_nth_match(0, match);
	}
	result = rb_ary_new2(regs->num_regs);
	for (i=1; i < regs->num_regs; i++) {
	    rb_ary_push(result, rb_reg_nth_match(i, match));
	}

	return result;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.scan(pattern)                         -> array
 *     str.scan(pattern) {|match, ...| block }   -> str
 *
 *  Both forms iterate through <i>str</i>, matching the pattern (which may be a
 *  <code>Regexp</code> or a <code>String</code>). For each match, a result is
 *  generated and either added to the result array or passed to the block. If
 *  the pattern contains no groups, each individual result consists of the
 *  matched string, <code>$&</code>.  If the pattern contains groups, each
 *  individual result is itself an array containing one entry per group.
 *
 *     a = "cruel world"
 *     a.scan(/\w+/)        #=> ["cruel", "world"]
 *     a.scan(/.../)        #=> ["cru", "el ", "wor"]
 *     a.scan(/(...)/)      #=> [["cru"], ["el "], ["wor"]]
 *     a.scan(/(..)(..)/)   #=> [["cr", "ue"], ["l ", "wo"]]
 *
 *  And the block form:
 *
 *     a.scan(/\w+/) {|w| print "<<#{w}>> " }
 *     print "\n"
 *     a.scan(/(.)(.)/) {|x,y| print y, x }
 *     print "\n"
 *
 *  <em>produces:</em>
 *
 *     <<cruel>> <<world>>
 *     rceu lowlr
 */

static VALUE
rb_str_scan(VALUE str, VALUE pat)
{
    VALUE result;
    long start = 0;
    long last = -1, prev = 0;
    char *p = RSTRING_PTR(str); long len = RSTRING_LEN(str);

    pat = get_pat_quoted(pat, 1);
    mustnot_broken(str);
    if (!rb_block_given_p()) {
	VALUE ary = rb_ary_new();

	while (!NIL_P(result = scan_once(str, pat, &start))) {
	    last = prev;
	    prev = start;
	    rb_ary_push(ary, result);
	}
	if (last >= 0) rb_pat_search(pat, str, last, 1);
	return ary;
    }

    while (!NIL_P(result = scan_once(str, pat, &start))) {
	last = prev;
	prev = start;
	rb_yield(result);
	str_mod_check(str, p, len);
    }
    if (last >= 0) rb_pat_search(pat, str, last, 1);
    return str;
}


/*
 *  call-seq:
 *     str.hex   -> integer
 *
 *  Treats leading characters from <i>str</i> as a string of hexadecimal digits
 *  (with an optional sign and an optional <code>0x</code>) and returns the
 *  corresponding number. Zero is returned on error.
 *
 *     "0x0a".hex     #=> 10
 *     "-1234".hex    #=> -4660
 *     "0".hex        #=> 0
 *     "wombat".hex   #=> 0
 */

static VALUE
rb_str_hex(VALUE str)
{
    return rb_str_to_inum(str, 16, FALSE);
}


/*
 *  call-seq:
 *     str.oct   -> integer
 *
 *  Treats leading characters of <i>str</i> as a string of octal digits (with an
 *  optional sign) and returns the corresponding number.  Returns 0 if the
 *  conversion fails.
 *
 *     "123".oct       #=> 83
 *     "-377".oct      #=> -255
 *     "bad".oct       #=> 0
 *     "0377bad".oct   #=> 255
 *
 *  If +str+ starts with <code>0</code>, radix indicators are hornored.
 *  See Kernel#Integer.
 */

static VALUE
rb_str_oct(VALUE str)
{
    return rb_str_to_inum(str, -8, FALSE);
}


/*
 *  call-seq:
 *     str.crypt(salt_str)   -> new_str
 *
 *  Applies a one-way cryptographic hash to <i>str</i> by invoking the
 *  standard library function <code>crypt(3)</code> with the given
 *  salt string.  While the format and the result are system and
 *  implementation dependent, using a salt matching the regular
 *  expression <code>\A[a-zA-Z0-9./]{2}</code> should be valid and
 *  safe on any platform, in which only the first two characters are
 *  significant.
 *
 *  This method is for use in system specific scripts, so if you want
 *  a cross-platform hash function consider using Digest or OpenSSL
 *  instead.
 */

static VALUE
rb_str_crypt(VALUE str, VALUE salt)
{
    extern char *crypt(const char *, const char *);
    VALUE result;
    const char *s, *saltp;
    char *res;
#ifdef BROKEN_CRYPT
    char salt_8bit_clean[3];
#endif

    StringValue(salt);
    mustnot_wchar(str);
    mustnot_wchar(salt);
    if (RSTRING_LEN(salt) < 2) {
      short_salt:
	rb_raise(rb_eArgError, "salt too short (need >=2 bytes)");
    }

    s = StringValueCStr(str);
    saltp = RSTRING_PTR(salt);
    if (!saltp[0] || !saltp[1]) goto short_salt;
#ifdef BROKEN_CRYPT
    if (!ISASCII((unsigned char)saltp[0]) || !ISASCII((unsigned char)saltp[1])) {
	salt_8bit_clean[0] = saltp[0] & 0x7f;
	salt_8bit_clean[1] = saltp[1] & 0x7f;
	salt_8bit_clean[2] = '\0';
	saltp = salt_8bit_clean;
    }
#endif
    res = crypt(s, saltp);
    if (!res) {
	rb_sys_fail("crypt");
    }
    result = rb_str_new_cstr(res);
    FL_SET_RAW(result, OBJ_TAINTED_RAW(str) | OBJ_TAINTED_RAW(salt));
    return result;
}


/*
 *  call-seq:
 *     str.ord   -> integer
 *
 *  Return the <code>Integer</code> ordinal of a one-character string.
 *
 *     "a".ord         #=> 97
 */

VALUE
rb_str_ord(VALUE s)
{
    unsigned int c;

    c = rb_enc_codepoint(RSTRING_PTR(s), RSTRING_END(s), STR_ENC_GET(s));
    return UINT2NUM(c);
}
/*
 *  call-seq:
 *     str.sum(n=16)   -> integer
 *
 *  Returns a basic <em>n</em>-bit checksum of the characters in <i>str</i>,
 *  where <em>n</em> is the optional <code>Fixnum</code> parameter, defaulting
 *  to 16. The result is simply the sum of the binary value of each byte in
 *  <i>str</i> modulo <code>2**n - 1</code>. This is not a particularly good
 *  checksum.
 */

static VALUE
rb_str_sum(int argc, VALUE *argv, VALUE str)
{
    VALUE vbits;
    int bits;
    char *ptr, *p, *pend;
    long len;
    VALUE sum = INT2FIX(0);
    unsigned long sum0 = 0;

    if (argc == 0) {
	bits = 16;
    }
    else {
	rb_scan_args(argc, argv, "01", &vbits);
	bits = NUM2INT(vbits);
        if (bits < 0)
            bits = 0;
    }
    ptr = p = RSTRING_PTR(str);
    len = RSTRING_LEN(str);
    pend = p + len;

    while (p < pend) {
        if (FIXNUM_MAX - UCHAR_MAX < sum0) {
            sum = rb_funcall(sum, '+', 1, LONG2FIX(sum0));
            str_mod_check(str, ptr, len);
            sum0 = 0;
        }
        sum0 += (unsigned char)*p;
        p++;
    }

    if (bits == 0) {
        if (sum0) {
            sum = rb_funcall(sum, '+', 1, LONG2FIX(sum0));
        }
    }
    else {
        if (sum == INT2FIX(0)) {
            if (bits < (int)sizeof(long)*CHAR_BIT) {
                sum0 &= (((unsigned long)1)<<bits)-1;
            }
            sum = LONG2FIX(sum0);
        }
        else {
            VALUE mod;

            if (sum0) {
                sum = rb_funcall(sum, '+', 1, LONG2FIX(sum0));
            }

            mod = rb_funcall(INT2FIX(1), idLTLT, 1, INT2FIX(bits));
            mod = rb_funcall(mod, '-', 1, INT2FIX(1));
            sum = rb_funcall(sum, '&', 1, mod);
        }
    }
    return sum;
}

static VALUE
rb_str_justify(int argc, VALUE *argv, VALUE str, char jflag)
{
    rb_encoding *enc;
    VALUE w;
    long width, len, flen = 1, fclen = 1;
    VALUE res;
    char *p;
    const char *f = " ";
    long n, size, llen, rlen, llen2 = 0, rlen2 = 0;
    VALUE pad;
    int singlebyte = 1, cr;
    int termlen;

    rb_scan_args(argc, argv, "11", &w, &pad);
    enc = STR_ENC_GET(str);
    termlen = rb_enc_mbminlen(enc);
    width = NUM2LONG(w);
    if (argc == 2) {
	StringValue(pad);
	enc = rb_enc_check(str, pad);
	f = RSTRING_PTR(pad);
	flen = RSTRING_LEN(pad);
	fclen = str_strlen(pad, enc); /* rb_enc_check */
	singlebyte = single_byte_optimizable(pad);
	if (flen == 0 || fclen == 0) {
	    rb_raise(rb_eArgError, "zero width padding");
	}
    }
    len = str_strlen(str, enc); /* rb_enc_check */
    if (width < 0 || len >= width) return rb_str_dup(str);
    n = width - len;
    llen = (jflag == 'l') ? 0 : ((jflag == 'r') ? n : n/2);
    rlen = n - llen;
    cr = ENC_CODERANGE(str);
    if (flen > 1) {
       llen2 = str_offset(f, f + flen, llen % fclen, enc, singlebyte);
       rlen2 = str_offset(f, f + flen, rlen % fclen, enc, singlebyte);
    }
    size = RSTRING_LEN(str);
    if ((len = llen / fclen + rlen / fclen) >= LONG_MAX / flen ||
       (len *= flen) >= LONG_MAX - llen2 - rlen2 ||
       (len += llen2 + rlen2) >= LONG_MAX - size) {
       rb_raise(rb_eArgError, "argument too big");
    }
    len += size;
    res = str_new0(rb_obj_class(str), 0, len, termlen);
    p = RSTRING_PTR(res);
    if (flen <= 1) {
       memset(p, *f, llen);
       p += llen;
    }
    else {
       while (llen >= fclen) {
	    memcpy(p,f,flen);
	    p += flen;
	    llen -= fclen;
	}
       if (llen > 0) {
           memcpy(p, f, llen2);
           p += llen2;
	}
    }
    memcpy(p, RSTRING_PTR(str), size);
    p += size;
    if (flen <= 1) {
       memset(p, *f, rlen);
       p += rlen;
    }
    else {
       while (rlen >= fclen) {
	    memcpy(p,f,flen);
	    p += flen;
	    rlen -= fclen;
	}
       if (rlen > 0) {
           memcpy(p, f, rlen2);
           p += rlen2;
	}
    }
    TERM_FILL(p, termlen);
    STR_SET_LEN(res, p-RSTRING_PTR(res));
    OBJ_INFECT_RAW(res, str);
    if (!NIL_P(pad)) OBJ_INFECT_RAW(res, pad);
    rb_enc_associate(res, enc);
    if (argc == 2)
	cr = ENC_CODERANGE_AND(cr, ENC_CODERANGE(pad));
    if (cr != ENC_CODERANGE_BROKEN)
	ENC_CODERANGE_SET(res, cr);

    RB_GC_GUARD(pad);
    return res;
}


/*
 *  call-seq:
 *     str.ljust(integer, padstr=' ')   -> new_str
 *
 *  If <i>integer</i> is greater than the length of <i>str</i>, returns a new
 *  <code>String</code> of length <i>integer</i> with <i>str</i> left justified
 *  and padded with <i>padstr</i>; otherwise, returns <i>str</i>.
 *
 *     "hello".ljust(4)            #=> "hello"
 *     "hello".ljust(20)           #=> "hello               "
 *     "hello".ljust(20, '1234')   #=> "hello123412341234123"
 */

static VALUE
rb_str_ljust(int argc, VALUE *argv, VALUE str)
{
    return rb_str_justify(argc, argv, str, 'l');
}


/*
 *  call-seq:
 *     str.rjust(integer, padstr=' ')   -> new_str
 *
 *  If <i>integer</i> is greater than the length of <i>str</i>, returns a new
 *  <code>String</code> of length <i>integer</i> with <i>str</i> right justified
 *  and padded with <i>padstr</i>; otherwise, returns <i>str</i>.
 *
 *     "hello".rjust(4)            #=> "hello"
 *     "hello".rjust(20)           #=> "               hello"
 *     "hello".rjust(20, '1234')   #=> "123412341234123hello"
 */

static VALUE
rb_str_rjust(int argc, VALUE *argv, VALUE str)
{
    return rb_str_justify(argc, argv, str, 'r');
}


/*
 *  call-seq:
 *     str.center(width, padstr=' ')   -> new_str
 *
 *  Centers +str+ in +width+.  If +width+ is greater than the length of +str+,
 *  returns a new String of length +width+ with +str+ centered and padded with
 *  +padstr+; otherwise, returns +str+.
 *
 *     "hello".center(4)         #=> "hello"
 *     "hello".center(20)        #=> "       hello        "
 *     "hello".center(20, '123') #=> "1231231hello12312312"
 */

static VALUE
rb_str_center(int argc, VALUE *argv, VALUE str)
{
    return rb_str_justify(argc, argv, str, 'c');
}

/*
 *  call-seq:
 *     str.partition(sep)              -> [head, sep, tail]
 *     str.partition(regexp)           -> [head, match, tail]
 *
 *  Searches <i>sep</i> or pattern (<i>regexp</i>) in the string
 *  and returns the part before it, the match, and the part
 *  after it.
 *  If it is not found, returns two empty strings and <i>str</i>.
 *
 *     "hello".partition("l")         #=> ["he", "l", "lo"]
 *     "hello".partition("x")         #=> ["hello", "", ""]
 *     "hello".partition(/.l/)        #=> ["h", "el", "lo"]
 */

static VALUE
rb_str_partition(VALUE str, VALUE sep)
{
    long pos;

    sep = get_pat_quoted(sep, 0);
    if (RB_TYPE_P(sep, T_REGEXP)) {
	pos = rb_reg_search(sep, str, 0, 0);
	if (pos < 0) {
	  failed:
	    return rb_ary_new3(3, str, str_new_empty(str), str_new_empty(str));
	}
	sep = rb_str_subpat(str, sep, INT2FIX(0));
	if (pos == 0 && RSTRING_LEN(sep) == 0) goto failed;
    }
    else {
	pos = rb_str_index(str, sep, 0);
	if (pos < 0) goto failed;
    }
    return rb_ary_new3(3, rb_str_subseq(str, 0, pos),
		          sep,
		          rb_str_subseq(str, pos+RSTRING_LEN(sep),
					     RSTRING_LEN(str)-pos-RSTRING_LEN(sep)));
}

/*
 *  call-seq:
 *     str.rpartition(sep)             -> [head, sep, tail]
 *     str.rpartition(regexp)          -> [head, match, tail]
 *
 *  Searches <i>sep</i> or pattern (<i>regexp</i>) in the string from the end
 *  of the string, and returns the part before it, the match, and the part
 *  after it.
 *  If it is not found, returns two empty strings and <i>str</i>.
 *
 *     "hello".rpartition("l")         #=> ["hel", "l", "o"]
 *     "hello".rpartition("x")         #=> ["", "", "hello"]
 *     "hello".rpartition(/.l/)        #=> ["he", "ll", "o"]
 */

static VALUE
rb_str_rpartition(VALUE str, VALUE sep)
{
    long pos = RSTRING_LEN(str);
    int regex = FALSE;

    if (RB_TYPE_P(sep, T_REGEXP)) {
	pos = rb_reg_search(sep, str, pos, 1);
	regex = TRUE;
    }
    else {
	VALUE tmp;

	tmp = rb_check_string_type(sep);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sep));
	}
	sep = tmp;
	pos = rb_str_sublen(str, pos);
	pos = rb_str_rindex(str, sep, pos);
    }
    if (pos < 0) {
	return rb_ary_new3(3, str_new_empty(str), str_new_empty(str), str);
    }
    if (regex) {
	sep = rb_reg_nth_match(0, rb_backref_get());
    }
    else {
	pos = rb_str_offset(str, pos);
    }
    return rb_ary_new3(3, rb_str_subseq(str, 0, pos),
		          sep,
		          rb_str_subseq(str, pos+RSTRING_LEN(sep),
					RSTRING_LEN(str)-pos-RSTRING_LEN(sep)));
}

/*
 *  call-seq:
 *     str.start_with?([prefixes]+)   -> true or false
 *
 *  Returns true if +str+ starts with one of the +prefixes+ given.
 *
 *    "hello".start_with?("hell")               #=> true
 *
 *    # returns true if one of the prefixes matches.
 *    "hello".start_with?("heaven", "hell")     #=> true
 *    "hello".start_with?("heaven", "paradise") #=> false
 */

static VALUE
rb_str_start_with(int argc, VALUE *argv, VALUE str)
{
    int i;

    for (i=0; i<argc; i++) {
	VALUE tmp = argv[i];
	StringValue(tmp);
	rb_enc_check(str, tmp);
	if (RSTRING_LEN(str) < RSTRING_LEN(tmp)) continue;
	if (memcmp(RSTRING_PTR(str), RSTRING_PTR(tmp), RSTRING_LEN(tmp)) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     str.end_with?([suffixes]+)   -> true or false
 *
 *  Returns true if +str+ ends with one of the +suffixes+ given.
 *
 *    "hello".end_with?("ello")               #=> true
 *
 *    # returns true if one of the +suffixes+ matches.
 *    "hello".end_with?("heaven", "ello")     #=> true
 *    "hello".end_with?("heaven", "paradise") #=> false
 */

static VALUE
rb_str_end_with(int argc, VALUE *argv, VALUE str)
{
    int i;
    char *p, *s, *e;
    rb_encoding *enc;

    for (i=0; i<argc; i++) {
	VALUE tmp = argv[i];
	StringValue(tmp);
	enc = rb_enc_check(str, tmp);
	if (RSTRING_LEN(str) < RSTRING_LEN(tmp)) continue;
	p = RSTRING_PTR(str);
        e = p + RSTRING_LEN(str);
	s = e - RSTRING_LEN(tmp);
	if (rb_enc_left_char_head(p, s, e, enc) != s)
	    continue;
	if (memcmp(s, RSTRING_PTR(tmp), RSTRING_LEN(tmp)) == 0)
	    return Qtrue;
    }
    return Qfalse;
}

void
rb_str_setter(VALUE val, ID id, VALUE *var)
{
    if (!NIL_P(val) && !RB_TYPE_P(val, T_STRING)) {
	rb_raise(rb_eTypeError, "value of %"PRIsVALUE" must be String", rb_id2str(id));
    }
    *var = val;
}


/*
 *  call-seq:
 *     str.force_encoding(encoding)   -> str
 *
 *  Changes the encoding to +encoding+ and returns self.
 */

static VALUE
rb_str_force_encoding(VALUE str, VALUE enc)
{
    str_modifiable(str);
    rb_enc_associate(str, rb_to_encoding(enc));
    ENC_CODERANGE_CLEAR(str);
    return str;
}

/*
 *  call-seq:
 *     str.b   -> str
 *
 *  Returns a copied string whose encoding is ASCII-8BIT.
 */

static VALUE
rb_str_b(VALUE str)
{
    VALUE str2 = str_alloc(rb_cString);
    str_replace_shared_without_enc(str2, str);
    OBJ_INFECT_RAW(str2, str);
    ENC_CODERANGE_CLEAR(str2);
    return str2;
}

/*
 *  call-seq:
 *     str.valid_encoding?  -> true or false
 *
 *  Returns true for a string which encoded correctly.
 *
 *    "\xc2\xa1".force_encoding("UTF-8").valid_encoding?  #=> true
 *    "\xc2".force_encoding("UTF-8").valid_encoding?      #=> false
 *    "\x80".force_encoding("UTF-8").valid_encoding?      #=> false
 */

static VALUE
rb_str_valid_encoding_p(VALUE str)
{
    int cr = rb_enc_str_coderange(str);

    return cr == ENC_CODERANGE_BROKEN ? Qfalse : Qtrue;
}

/*
 *  call-seq:
 *     str.ascii_only?  -> true or false
 *
 *  Returns true for a string which has only ASCII characters.
 *
 *    "abc".force_encoding("UTF-8").ascii_only?          #=> true
 *    "abc\u{6666}".force_encoding("UTF-8").ascii_only?  #=> false
 */

static VALUE
rb_str_is_ascii_only_p(VALUE str)
{
    int cr = rb_enc_str_coderange(str);

    return cr == ENC_CODERANGE_7BIT ? Qtrue : Qfalse;
}

/**
 * Shortens _str_ and adds three dots, an ellipsis, if it is longer
 * than _len_ characters.
 *
 * \param str	the string to ellipsize.
 * \param len	the maximum string length.
 * \return	the ellipsized string.
 * \pre 	_len_ must not be negative.
 * \post	the length of the returned string in characters is less than or equal to _len_.
 * \post	If the length of _str_ is less than or equal _len_, returns _str_ itself.
 * \post	the encoding of returned string is equal to the encoding of _str_.
 * \post	the class of returned string is equal to the class of _str_.
 * \note	the length is counted in characters.
 */
VALUE
rb_str_ellipsize(VALUE str, long len)
{
    static const char ellipsis[] = "...";
    const long ellipsislen = sizeof(ellipsis) - 1;
    rb_encoding *const enc = rb_enc_get(str);
    const long blen = RSTRING_LEN(str);
    const char *const p = RSTRING_PTR(str), *e = p + blen;
    VALUE estr, ret = 0;

    if (len < 0) rb_raise(rb_eIndexError, "negative length %ld", len);
    if (len * rb_enc_mbminlen(enc) >= blen ||
	(e = rb_enc_nth(p, e, len, enc)) - p == blen) {
	ret = str;
    }
    else if (len <= ellipsislen ||
	     !(e = rb_enc_step_back(p, e, e, len = ellipsislen, enc))) {
	if (rb_enc_asciicompat(enc)) {
	    ret = rb_str_new_with_class(str, ellipsis, len);
	    rb_enc_associate(ret, enc);
	}
	else {
	    estr = rb_usascii_str_new(ellipsis, len);
	    ret = rb_str_encode(estr, rb_enc_from_encoding(enc), 0, Qnil);
	}
    }
    else if (ret = rb_str_subseq(str, 0, e - p), rb_enc_asciicompat(enc)) {
	rb_str_cat(ret, ellipsis, ellipsislen);
    }
    else {
	estr = rb_str_encode(rb_usascii_str_new(ellipsis, ellipsislen),
			     rb_enc_from_encoding(enc), 0, Qnil);
	rb_str_append(ret, estr);
    }
    return ret;
}

static VALUE
str_compat_and_valid(VALUE str, rb_encoding *enc)
{
    int cr;
    str = StringValue(str);
    cr = rb_enc_str_coderange(str);
    if (cr == ENC_CODERANGE_BROKEN) {
	rb_raise(rb_eArgError, "replacement must be valid byte sequence '%+"PRIsVALUE"'", str);
    }
    else {
	rb_encoding *e = STR_ENC_GET(str);
	if (cr == ENC_CODERANGE_7BIT ? rb_enc_mbminlen(enc) != 1 : enc != e) {
	    rb_raise(rb_eEncCompatError, "incompatible character encodings: %s and %s",
		     rb_enc_name(enc), rb_enc_name(e));
	}
    }
    return str;
}

/**
 * @param str the string to be scrubbed
 * @param repl the replacement character
 * @return If given string is invalid, returns a new string. Otherwise, returns Qnil.
 */
VALUE
rb_str_scrub(VALUE str, VALUE repl)
{
    return rb_enc_str_scrub(STR_ENC_GET(str), str, repl);
}

VALUE
rb_enc_str_scrub(rb_encoding *enc, VALUE str, VALUE repl)
{
    int cr = ENC_CODERANGE(str);
    int encidx;
    VALUE buf = Qnil;
    const char *rep;
    long replen;
    int tainted = 0;

    if (ENC_CODERANGE_CLEAN_P(cr))
	return Qnil;

    if (!NIL_P(repl)) {
	repl = str_compat_and_valid(repl, enc);
	tainted = OBJ_TAINTED_RAW(repl);
    }

    if (rb_enc_dummy_p(enc)) {
	return Qnil;
    }
    encidx = rb_enc_to_index(enc);

#define DEFAULT_REPLACE_CHAR(str) do { \
	static const char replace[sizeof(str)-1] = str; \
	rep = replace; replen = (int)sizeof(replace); \
    } while (0)

    if (rb_enc_asciicompat(enc)) {
	const char *p = RSTRING_PTR(str);
	const char *e = RSTRING_END(str);
	const char *p1 = p;
	int rep7bit_p;
	if (rb_block_given_p()) {
	    rep = NULL;
	    replen = 0;
	    rep7bit_p = FALSE;
	}
	else if (!NIL_P(repl)) {
	    rep = RSTRING_PTR(repl);
	    replen = RSTRING_LEN(repl);
	    rep7bit_p = (ENC_CODERANGE(repl) == ENC_CODERANGE_7BIT);
	}
	else if (encidx == rb_utf8_encindex()) {
	    DEFAULT_REPLACE_CHAR("\xEF\xBF\xBD");
	    rep7bit_p = FALSE;
	}
	else {
	    DEFAULT_REPLACE_CHAR("?");
	    rep7bit_p = TRUE;
	}
	cr = ENC_CODERANGE_7BIT;

	p = search_nonascii(p, e);
	if (!p) {
	    p = e;
	}
	while (p < e) {
	    int ret = rb_enc_precise_mbclen(p, e, enc);
	    if (MBCLEN_NEEDMORE_P(ret)) {
		break;
	    }
	    else if (MBCLEN_CHARFOUND_P(ret)) {
		cr = ENC_CODERANGE_VALID;
		p += MBCLEN_CHARFOUND_LEN(ret);
	    }
	    else if (MBCLEN_INVALID_P(ret)) {
		/*
		 * p1~p: valid ascii/multibyte chars
		 * p ~e: invalid bytes + unknown bytes
		 */
		long clen = rb_enc_mbmaxlen(enc);
		if (NIL_P(buf)) buf = rb_str_buf_new(RSTRING_LEN(str));
		if (p > p1) {
		    rb_str_buf_cat(buf, p1, p - p1);
		}

		if (e - p < clen) clen = e - p;
		if (clen <= 2) {
		    clen = 1;
		}
		else {
		    const char *q = p;
		    clen--;
		    for (; clen > 1; clen--) {
			ret = rb_enc_precise_mbclen(q, q + clen, enc);
			if (MBCLEN_NEEDMORE_P(ret)) break;
			if (MBCLEN_INVALID_P(ret)) continue;
			UNREACHABLE;
		    }
		}
		if (rep) {
		    rb_str_buf_cat(buf, rep, replen);
		    if (!rep7bit_p) cr = ENC_CODERANGE_VALID;
		}
		else {
		    repl = rb_yield(rb_enc_str_new(p, clen, enc));
		    repl = str_compat_and_valid(repl, enc);
		    tainted |= OBJ_TAINTED_RAW(repl);
		    rb_str_buf_cat(buf, RSTRING_PTR(repl), RSTRING_LEN(repl));
		    if (ENC_CODERANGE(repl) == ENC_CODERANGE_VALID)
			cr = ENC_CODERANGE_VALID;
		}
		p += clen;
		p1 = p;
		p = search_nonascii(p, e);
		if (!p) {
		    p = e;
		    break;
		}
	    }
	    else {
		UNREACHABLE;
	    }
	}
	if (NIL_P(buf)) {
	    if (p == e) {
		ENC_CODERANGE_SET(str, cr);
		return Qnil;
	    }
	    buf = rb_str_buf_new(RSTRING_LEN(str));
	}
	if (p1 < p) {
	    rb_str_buf_cat(buf, p1, p - p1);
	}
	if (p < e) {
	    if (rep) {
		rb_str_buf_cat(buf, rep, replen);
		if (!rep7bit_p) cr = ENC_CODERANGE_VALID;
	    }
	    else {
		repl = rb_yield(rb_enc_str_new(p, e-p, enc));
		repl = str_compat_and_valid(repl, enc);
		tainted |= OBJ_TAINTED_RAW(repl);
		rb_str_buf_cat(buf, RSTRING_PTR(repl), RSTRING_LEN(repl));
		if (ENC_CODERANGE(repl) == ENC_CODERANGE_VALID)
		    cr = ENC_CODERANGE_VALID;
	    }
	}
    }
    else {
	/* ASCII incompatible */
	const char *p = RSTRING_PTR(str);
	const char *e = RSTRING_END(str);
	const char *p1 = p;
	long mbminlen = rb_enc_mbminlen(enc);
	if (!NIL_P(repl)) {
	    rep = RSTRING_PTR(repl);
	    replen = RSTRING_LEN(repl);
	}
	else if (encidx == ENCINDEX_UTF_16BE) {
	    DEFAULT_REPLACE_CHAR("\xFF\xFD");
	}
	else if (encidx == ENCINDEX_UTF_16LE) {
	    DEFAULT_REPLACE_CHAR("\xFD\xFF");
	}
	else if (encidx == ENCINDEX_UTF_32BE) {
	    DEFAULT_REPLACE_CHAR("\x00\x00\xFF\xFD");
	}
	else if (encidx == ENCINDEX_UTF_32LE) {
	    DEFAULT_REPLACE_CHAR("\xFD\xFF\x00\x00");
	}
	else {
	    DEFAULT_REPLACE_CHAR("?");
	}

	while (p < e) {
	    int ret = rb_enc_precise_mbclen(p, e, enc);
	    if (MBCLEN_NEEDMORE_P(ret)) {
		break;
	    }
	    else if (MBCLEN_CHARFOUND_P(ret)) {
		p += MBCLEN_CHARFOUND_LEN(ret);
	    }
	    else if (MBCLEN_INVALID_P(ret)) {
		const char *q = p;
		long clen = rb_enc_mbmaxlen(enc);
		if (NIL_P(buf)) buf = rb_str_buf_new(RSTRING_LEN(str));
		if (p > p1) rb_str_buf_cat(buf, p1, p - p1);

		if (e - p < clen) clen = e - p;
		if (clen <= mbminlen * 2) {
		    clen = mbminlen;
		}
		else {
		    clen -= mbminlen;
		    for (; clen > mbminlen; clen-=mbminlen) {
			ret = rb_enc_precise_mbclen(q, q + clen, enc);
			if (MBCLEN_NEEDMORE_P(ret)) break;
			if (MBCLEN_INVALID_P(ret)) continue;
			UNREACHABLE;
		    }
		}
		if (rep) {
		    rb_str_buf_cat(buf, rep, replen);
		}
		else {
		    repl = rb_yield(rb_enc_str_new(p, e-p, enc));
		    repl = str_compat_and_valid(repl, enc);
		    tainted |= OBJ_TAINTED_RAW(repl);
		    rb_str_buf_cat(buf, RSTRING_PTR(repl), RSTRING_LEN(repl));
		}
		p += clen;
		p1 = p;
	    }
	    else {
		UNREACHABLE;
	    }
	}
	if (NIL_P(buf)) {
	    if (p == e) {
		ENC_CODERANGE_SET(str, ENC_CODERANGE_VALID);
		return Qnil;
	    }
	    buf = rb_str_buf_new(RSTRING_LEN(str));
	}
	if (p1 < p) {
	    rb_str_buf_cat(buf, p1, p - p1);
	}
	if (p < e) {
	    if (rep) {
		rb_str_buf_cat(buf, rep, replen);
	    }
	    else {
		repl = rb_yield(rb_enc_str_new(p, e-p, enc));
		repl = str_compat_and_valid(repl, enc);
		tainted |= OBJ_TAINTED_RAW(repl);
		rb_str_buf_cat(buf, RSTRING_PTR(repl), RSTRING_LEN(repl));
	    }
	}
	cr = ENC_CODERANGE_VALID;
    }
    FL_SET_RAW(buf, tainted|OBJ_TAINTED_RAW(str));
    ENCODING_CODERANGE_SET(buf, rb_enc_to_index(enc), cr);
    return buf;
}

/*
 *  call-seq:
 *    str.scrub -> new_str
 *    str.scrub(repl) -> new_str
 *    str.scrub{|bytes|} -> new_str
 *
 *  If the string is invalid byte sequence then replace invalid bytes with given replacement
 *  character, else returns self.
 *  If block is given, replace invalid bytes with returned value of the block.
 *
 *     "abc\u3042\x81".scrub #=> "abc\u3042\uFFFD"
 *     "abc\u3042\x81".scrub("*") #=> "abc\u3042*"
 *     "abc\u3042\xE3\x80".scrub{|bytes| '<'+bytes.unpack('H*')[0]+'>' } #=> "abc\u3042<e380>"
 */
static VALUE
str_scrub(int argc, VALUE *argv, VALUE str)
{
    VALUE repl = argc ? (rb_check_arity(argc, 0, 1), argv[0]) : Qnil;
    VALUE new = rb_str_scrub(str, repl);
    return NIL_P(new) ? rb_str_dup(str): new;
}

/*
 *  call-seq:
 *    str.scrub! -> str
 *    str.scrub!(repl) -> str
 *    str.scrub!{|bytes|} -> str
 *
 *  If the string is invalid byte sequence then replace invalid bytes with given replacement
 *  character, else returns self.
 *  If block is given, replace invalid bytes with returned value of the block.
 *
 *     "abc\u3042\x81".scrub! #=> "abc\u3042\uFFFD"
 *     "abc\u3042\x81".scrub!("*") #=> "abc\u3042*"
 *     "abc\u3042\xE3\x80".scrub!{|bytes| '<'+bytes.unpack('H*')[0]+'>' } #=> "abc\u3042<e380>"
 */
static VALUE
str_scrub_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE repl = argc ? (rb_check_arity(argc, 0, 1), argv[0]) : Qnil;
    VALUE new = rb_str_scrub(str, repl);
    if (!NIL_P(new)) rb_str_replace(str, new);
    return str;
}

/**********************************************************************
 * Document-class: Symbol
 *
 *  <code>Symbol</code> objects represent names and some strings
 *  inside the Ruby
 *  interpreter. They are generated using the <code>:name</code> and
 *  <code>:"string"</code> literals
 *  syntax, and by the various <code>to_sym</code> methods. The same
 *  <code>Symbol</code> object will be created for a given name or string
 *  for the duration of a program's execution, regardless of the context
 *  or meaning of that name. Thus if <code>Fred</code> is a constant in
 *  one context, a method in another, and a class in a third, the
 *  <code>Symbol</code> <code>:Fred</code> will be the same object in
 *  all three contexts.
 *
 *     module One
 *       class Fred
 *       end
 *       $f1 = :Fred
 *     end
 *     module Two
 *       Fred = 1
 *       $f2 = :Fred
 *     end
 *     def Fred()
 *     end
 *     $f3 = :Fred
 *     $f1.object_id   #=> 2514190
 *     $f2.object_id   #=> 2514190
 *     $f3.object_id   #=> 2514190
 *
 */


/*
 *  call-seq:
 *     sym == obj   -> true or false
 *
 *  Equality---If <i>sym</i> and <i>obj</i> are exactly the same
 *  symbol, returns <code>true</code>.
 */

#define sym_equal rb_obj_equal

static int
sym_printable(const char *s, const char *send, rb_encoding *enc)
{
    while (s < send) {
	int n;
	int c = rb_enc_precise_mbclen(s, send, enc);

	if (!MBCLEN_CHARFOUND_P(c)) return FALSE;
	n = MBCLEN_CHARFOUND_LEN(c);
	c = rb_enc_mbc_to_codepoint(s, send, enc);
	if (!rb_enc_isprint(c, enc)) return FALSE;
	s += n;
    }
    return TRUE;
}

int
rb_str_symname_p(VALUE sym)
{
    rb_encoding *enc;
    const char *ptr;
    long len;
    rb_encoding *resenc = rb_default_internal_encoding();

    if (resenc == NULL) resenc = rb_default_external_encoding();
    enc = STR_ENC_GET(sym);
    ptr = RSTRING_PTR(sym);
    len = RSTRING_LEN(sym);
    if ((resenc != enc && !rb_str_is_ascii_only_p(sym)) || len != (long)strlen(ptr) ||
	!rb_enc_symname_p(ptr, enc) || !sym_printable(ptr, ptr + len, enc)) {
	return FALSE;
    }
    return TRUE;
}

VALUE
rb_str_quote_unprintable(VALUE str)
{
    rb_encoding *enc;
    const char *ptr;
    long len;
    rb_encoding *resenc;

    Check_Type(str, T_STRING);
    resenc = rb_default_internal_encoding();
    if (resenc == NULL) resenc = rb_default_external_encoding();
    enc = STR_ENC_GET(str);
    ptr = RSTRING_PTR(str);
    len = RSTRING_LEN(str);
    if ((resenc != enc && !rb_str_is_ascii_only_p(str)) ||
	!sym_printable(ptr, ptr + len, enc)) {
	return rb_str_inspect(str);
    }
    return str;
}

VALUE
rb_id_quote_unprintable(ID id)
{
    return rb_str_quote_unprintable(rb_id2str(id));
}

/*
 *  call-seq:
 *     sym.inspect    -> string
 *
 *  Returns the representation of <i>sym</i> as a symbol literal.
 *
 *     :fred.inspect   #=> ":fred"
 */

static VALUE
sym_inspect(VALUE sym)
{
    VALUE str = rb_sym2str(sym);
    const char *ptr;
    long len;
    char *dest;

    if (!rb_str_symname_p(str)) {
	str = rb_str_inspect(str);
	len = RSTRING_LEN(str);
	rb_str_resize(str, len + 1);
	dest = RSTRING_PTR(str);
	memmove(dest + 1, dest, len);
    }
    else {
	rb_encoding *enc = STR_ENC_GET(str);
	RSTRING_GETMEM(str, ptr, len);
	str = rb_enc_str_new(0, len + 1, enc);
	dest = RSTRING_PTR(str);
	memcpy(dest + 1, ptr, len);
    }
    dest[0] = ':';
    return str;
}


/*
 *  call-seq:
 *     sym.id2name   -> string
 *     sym.to_s      -> string
 *
 *  Returns the name or string corresponding to <i>sym</i>.
 *
 *     :fred.id2name   #=> "fred"
 */


VALUE
rb_sym_to_s(VALUE sym)
{
    return str_new_shared(rb_cString, rb_sym2str(sym));
}


/*
 * call-seq:
 *   sym.to_sym   -> sym
 *   sym.intern   -> sym
 *
 * In general, <code>to_sym</code> returns the <code>Symbol</code> corresponding
 * to an object. As <i>sym</i> is already a symbol, <code>self</code> is returned
 * in this case.
 */

static VALUE
sym_to_sym(VALUE sym)
{
    return sym;
}

VALUE
rb_sym_proc_call(VALUE args, VALUE sym, int argc, const VALUE *argv, VALUE passed_proc)
{
    VALUE obj;

    if (argc < 1) {
	rb_raise(rb_eArgError, "no receiver given");
    }
    obj = argv[0];
    return rb_funcall_with_block(obj, (ID)sym, argc - 1, argv + 1, passed_proc);
}

#if 0
/*
 * call-seq:
 *   sym.to_proc
 *
 * Returns a _Proc_ object which respond to the given method by _sym_.
 *
 *   (1..3).collect(&:to_s)  #=> ["1", "2", "3"]
 */

VALUE
rb_sym_to_proc(VALUE sym)
{
}
#endif

/*
 * call-seq:
 *
 *   sym.succ
 *
 * Same as <code>sym.to_s.succ.intern</code>.
 */

static VALUE
sym_succ(VALUE sym)
{
    return rb_str_intern(rb_str_succ(rb_sym2str(sym)));
}

/*
 * call-seq:
 *
 *   symbol <=> other_symbol       -> -1, 0, +1 or nil
 *
 * Compares +symbol+ with +other_symbol+ after calling #to_s on each of the
 * symbols. Returns -1, 0, +1 or nil depending on whether +symbol+ is less
 * than, equal to, or greater than +other_symbol+.
 *
 *  +nil+ is returned if the two values are incomparable.
 *
 * See String#<=> for more information.
 */

static VALUE
sym_cmp(VALUE sym, VALUE other)
{
    if (!SYMBOL_P(other)) {
	return Qnil;
    }
    return rb_str_cmp_m(rb_sym2str(sym), rb_sym2str(other));
}

/*
 * call-seq:
 *
 *   sym.casecmp(other)  -> -1, 0, +1 or nil
 *
 * Case-insensitive version of <code>Symbol#<=></code>.
 */

static VALUE
sym_casecmp(VALUE sym, VALUE other)
{
    if (!SYMBOL_P(other)) {
	return Qnil;
    }
    return rb_str_casecmp(rb_sym2str(sym), rb_sym2str(other));
}

/*
 * call-seq:
 *   sym =~ obj   -> fixnum or nil
 *   sym.match(obj)   -> fixnum or nil
 *
 * Returns <code>sym.to_s =~ obj</code>.
 */

static VALUE
sym_match(VALUE sym, VALUE other)
{
    return rb_str_match(rb_sym2str(sym), other);
}

/*
 * call-seq:
 *   sym[idx]      -> char
 *   sym[b, n]     -> string
 *   sym.slice(idx)      -> char
 *   sym.slice(b, n)     -> string
 *
 * Returns <code>sym.to_s[]</code>.
 */

static VALUE
sym_aref(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_aref_m(argc, argv, rb_sym2str(sym));
}

/*
 * call-seq:
 *   sym.length    -> integer
 *   sym.size    -> integer
 *
 * Same as <code>sym.to_s.length</code>.
 */

static VALUE
sym_length(VALUE sym)
{
    return rb_str_length(rb_sym2str(sym));
}

/*
 * call-seq:
 *   sym.empty?   -> true or false
 *
 * Returns that _sym_ is :"" or not.
 */

static VALUE
sym_empty(VALUE sym)
{
    return rb_str_empty(rb_sym2str(sym));
}

/*
 * call-seq:
 *   sym.upcase    -> symbol
 *
 * Same as <code>sym.to_s.upcase.intern</code>.
 */

static VALUE
sym_upcase(VALUE sym)
{
    return rb_str_intern(rb_str_upcase(rb_sym2str(sym)));
}

/*
 * call-seq:
 *   sym.downcase  -> symbol
 *
 * Same as <code>sym.to_s.downcase.intern</code>.
 */

static VALUE
sym_downcase(VALUE sym)
{
    return rb_str_intern(rb_str_downcase(rb_sym2str(sym)));
}

/*
 * call-seq:
 *   sym.capitalize  -> symbol
 *
 * Same as <code>sym.to_s.capitalize.intern</code>.
 */

static VALUE
sym_capitalize(VALUE sym)
{
    return rb_str_intern(rb_str_capitalize(rb_sym2str(sym)));
}

/*
 * call-seq:
 *   sym.swapcase  -> symbol
 *
 * Same as <code>sym.to_s.swapcase.intern</code>.
 */

static VALUE
sym_swapcase(VALUE sym)
{
    return rb_str_intern(rb_str_swapcase(rb_sym2str(sym)));
}

/*
 * call-seq:
 *   sym.encoding   -> encoding
 *
 * Returns the Encoding object that represents the encoding of _sym_.
 */

static VALUE
sym_encoding(VALUE sym)
{
    return rb_obj_encoding(rb_sym2str(sym));
}

static VALUE
string_for_symbol(VALUE name)
{
    if (!RB_TYPE_P(name, T_STRING)) {
	VALUE tmp = rb_check_string_type(name);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "%+"PRIsVALUE" is not a symbol",
		     name);
	}
	name = tmp;
    }
    return name;
}

ID
rb_to_id(VALUE name)
{
    if (SYMBOL_P(name)) {
	return SYM2ID(name);
    }
    name = string_for_symbol(name);
    return rb_intern_str(name);
}

VALUE
rb_to_symbol(VALUE name)
{
    if (SYMBOL_P(name)) {
	return name;
    }
    name = string_for_symbol(name);
    return rb_str_intern(name);
}

/*
 *  A <code>String</code> object holds and manipulates an arbitrary sequence of
 *  bytes, typically representing characters. String objects may be created
 *  using <code>String::new</code> or as literals.
 *
 *  Because of aliasing issues, users of strings should be aware of the methods
 *  that modify the contents of a <code>String</code> object.  Typically,
 *  methods with names ending in ``!'' modify their receiver, while those
 *  without a ``!'' return a new <code>String</code>.  However, there are
 *  exceptions, such as <code>String#[]=</code>.
 *
 */

void
Init_String(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_cString  = rb_define_class("String", rb_cObject);
    rb_include_module(rb_cString, rb_mComparable);
    rb_define_alloc_func(rb_cString, empty_str_alloc);
    rb_define_singleton_method(rb_cString, "try_convert", rb_str_s_try_convert, 1);
    rb_define_method(rb_cString, "initialize", rb_str_init, -1);
    rb_define_method(rb_cString, "initialize_copy", rb_str_replace, 1);
    rb_define_method(rb_cString, "<=>", rb_str_cmp_m, 1);
    rb_define_method(rb_cString, "==", rb_str_equal, 1);
    rb_define_method(rb_cString, "===", rb_str_equal, 1);
    rb_define_method(rb_cString, "eql?", rb_str_eql, 1);
    rb_define_method(rb_cString, "hash", rb_str_hash_m, 0);
    rb_define_method(rb_cString, "casecmp", rb_str_casecmp, 1);
    rb_define_method(rb_cString, "+", rb_str_plus, 1);
    rb_define_method(rb_cString, "*", rb_str_times, 1);
    rb_define_method(rb_cString, "%", rb_str_format_m, 1);
    rb_define_method(rb_cString, "[]", rb_str_aref_m, -1);
    rb_define_method(rb_cString, "[]=", rb_str_aset_m, -1);
    rb_define_method(rb_cString, "insert", rb_str_insert, 2);
    rb_define_method(rb_cString, "length", rb_str_length, 0);
    rb_define_method(rb_cString, "size", rb_str_length, 0);
    rb_define_method(rb_cString, "bytesize", rb_str_bytesize, 0);
    rb_define_method(rb_cString, "empty?", rb_str_empty, 0);
    rb_define_method(rb_cString, "=~", rb_str_match, 1);
    rb_define_method(rb_cString, "match", rb_str_match_m, -1);
    rb_define_method(rb_cString, "succ", rb_str_succ, 0);
    rb_define_method(rb_cString, "succ!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "next", rb_str_succ, 0);
    rb_define_method(rb_cString, "next!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "upto", rb_str_upto, -1);
    rb_define_method(rb_cString, "index", rb_str_index_m, -1);
    rb_define_method(rb_cString, "rindex", rb_str_rindex_m, -1);
    rb_define_method(rb_cString, "replace", rb_str_replace, 1);
    rb_define_method(rb_cString, "clear", rb_str_clear, 0);
    rb_define_method(rb_cString, "chr", rb_str_chr, 0);
    rb_define_method(rb_cString, "getbyte", rb_str_getbyte, 1);
    rb_define_method(rb_cString, "setbyte", rb_str_setbyte, 2);
    rb_define_method(rb_cString, "byteslice", rb_str_byteslice, -1);
    rb_define_method(rb_cString, "scrub", str_scrub, -1);
    rb_define_method(rb_cString, "scrub!", str_scrub_bang, -1);
    rb_define_method(rb_cString, "freeze", rb_str_freeze, 0);
    rb_define_method(rb_cString, "+@", str_uplus, 0);
    rb_define_method(rb_cString, "-@", str_uminus, 0);

    rb_define_method(rb_cString, "to_i", rb_str_to_i, -1);
    rb_define_method(rb_cString, "to_f", rb_str_to_f, 0);
    rb_define_method(rb_cString, "to_s", rb_str_to_s, 0);
    rb_define_method(rb_cString, "to_str", rb_str_to_s, 0);
    rb_define_method(rb_cString, "inspect", rb_str_inspect, 0);
    rb_define_method(rb_cString, "dump", rb_str_dump, 0);

    rb_define_method(rb_cString, "upcase", rb_str_upcase, 0);
    rb_define_method(rb_cString, "downcase", rb_str_downcase, 0);
    rb_define_method(rb_cString, "capitalize", rb_str_capitalize, 0);
    rb_define_method(rb_cString, "swapcase", rb_str_swapcase, 0);

    rb_define_method(rb_cString, "upcase!", rb_str_upcase_bang, 0);
    rb_define_method(rb_cString, "downcase!", rb_str_downcase_bang, 0);
    rb_define_method(rb_cString, "capitalize!", rb_str_capitalize_bang, 0);
    rb_define_method(rb_cString, "swapcase!", rb_str_swapcase_bang, 0);

    rb_define_method(rb_cString, "hex", rb_str_hex, 0);
    rb_define_method(rb_cString, "oct", rb_str_oct, 0);
    rb_define_method(rb_cString, "split", rb_str_split_m, -1);
    rb_define_method(rb_cString, "lines", rb_str_lines, -1);
    rb_define_method(rb_cString, "bytes", rb_str_bytes, 0);
    rb_define_method(rb_cString, "chars", rb_str_chars, 0);
    rb_define_method(rb_cString, "codepoints", rb_str_codepoints, 0);
    rb_define_method(rb_cString, "reverse", rb_str_reverse, 0);
    rb_define_method(rb_cString, "reverse!", rb_str_reverse_bang, 0);
    rb_define_method(rb_cString, "concat", rb_str_concat, 1);
    rb_define_method(rb_cString, "<<", rb_str_concat, 1);
    rb_define_method(rb_cString, "prepend", rb_str_prepend, 1);
    rb_define_method(rb_cString, "crypt", rb_str_crypt, 1);
    rb_define_method(rb_cString, "intern", rb_str_intern, 0); /* in symbol.c */
    rb_define_method(rb_cString, "to_sym", rb_str_intern, 0); /* in symbol.c */
    rb_define_method(rb_cString, "ord", rb_str_ord, 0);

    rb_define_method(rb_cString, "include?", rb_str_include, 1);
    rb_define_method(rb_cString, "start_with?", rb_str_start_with, -1);
    rb_define_method(rb_cString, "end_with?", rb_str_end_with, -1);

    rb_define_method(rb_cString, "scan", rb_str_scan, 1);

    rb_define_method(rb_cString, "ljust", rb_str_ljust, -1);
    rb_define_method(rb_cString, "rjust", rb_str_rjust, -1);
    rb_define_method(rb_cString, "center", rb_str_center, -1);

    rb_define_method(rb_cString, "sub", rb_str_sub, -1);
    rb_define_method(rb_cString, "gsub", rb_str_gsub, -1);
    rb_define_method(rb_cString, "chop", rb_str_chop, 0);
    rb_define_method(rb_cString, "chomp", rb_str_chomp, -1);
    rb_define_method(rb_cString, "strip", rb_str_strip, 0);
    rb_define_method(rb_cString, "lstrip", rb_str_lstrip, 0);
    rb_define_method(rb_cString, "rstrip", rb_str_rstrip, 0);

    rb_define_method(rb_cString, "sub!", rb_str_sub_bang, -1);
    rb_define_method(rb_cString, "gsub!", rb_str_gsub_bang, -1);
    rb_define_method(rb_cString, "chop!", rb_str_chop_bang, 0);
    rb_define_method(rb_cString, "chomp!", rb_str_chomp_bang, -1);
    rb_define_method(rb_cString, "strip!", rb_str_strip_bang, 0);
    rb_define_method(rb_cString, "lstrip!", rb_str_lstrip_bang, 0);
    rb_define_method(rb_cString, "rstrip!", rb_str_rstrip_bang, 0);

    rb_define_method(rb_cString, "tr", rb_str_tr, 2);
    rb_define_method(rb_cString, "tr_s", rb_str_tr_s, 2);
    rb_define_method(rb_cString, "delete", rb_str_delete, -1);
    rb_define_method(rb_cString, "squeeze", rb_str_squeeze, -1);
    rb_define_method(rb_cString, "count", rb_str_count, -1);

    rb_define_method(rb_cString, "tr!", rb_str_tr_bang, 2);
    rb_define_method(rb_cString, "tr_s!", rb_str_tr_s_bang, 2);
    rb_define_method(rb_cString, "delete!", rb_str_delete_bang, -1);
    rb_define_method(rb_cString, "squeeze!", rb_str_squeeze_bang, -1);

    rb_define_method(rb_cString, "each_line", rb_str_each_line, -1);
    rb_define_method(rb_cString, "each_byte", rb_str_each_byte, 0);
    rb_define_method(rb_cString, "each_char", rb_str_each_char, 0);
    rb_define_method(rb_cString, "each_codepoint", rb_str_each_codepoint, 0);

    rb_define_method(rb_cString, "sum", rb_str_sum, -1);

    rb_define_method(rb_cString, "slice", rb_str_aref_m, -1);
    rb_define_method(rb_cString, "slice!", rb_str_slice_bang, -1);

    rb_define_method(rb_cString, "partition", rb_str_partition, 1);
    rb_define_method(rb_cString, "rpartition", rb_str_rpartition, 1);

    rb_define_method(rb_cString, "encoding", rb_obj_encoding, 0); /* in encoding.c */
    rb_define_method(rb_cString, "force_encoding", rb_str_force_encoding, 1);
    rb_define_method(rb_cString, "b", rb_str_b, 0);
    rb_define_method(rb_cString, "valid_encoding?", rb_str_valid_encoding_p, 0);
    rb_define_method(rb_cString, "ascii_only?", rb_str_is_ascii_only_p, 0);

    rb_fs = Qnil;
    rb_define_variable("$;", &rb_fs);
    rb_define_variable("$-F", &rb_fs);

    rb_cSymbol = rb_define_class("Symbol", rb_cObject);
    rb_include_module(rb_cSymbol, rb_mComparable);
    rb_undef_alloc_func(rb_cSymbol);
    rb_undef_method(CLASS_OF(rb_cSymbol), "new");
    rb_define_singleton_method(rb_cSymbol, "all_symbols", rb_sym_all_symbols, 0); /* in symbol.c */

    rb_define_method(rb_cSymbol, "==", sym_equal, 1);
    rb_define_method(rb_cSymbol, "===", sym_equal, 1);
    rb_define_method(rb_cSymbol, "inspect", sym_inspect, 0);
    rb_define_method(rb_cSymbol, "to_s", rb_sym_to_s, 0);
    rb_define_method(rb_cSymbol, "id2name", rb_sym_to_s, 0);
    rb_define_method(rb_cSymbol, "intern", sym_to_sym, 0);
    rb_define_method(rb_cSymbol, "to_sym", sym_to_sym, 0);
    rb_define_method(rb_cSymbol, "to_proc", rb_sym_to_proc, 0);
    rb_define_method(rb_cSymbol, "succ", sym_succ, 0);
    rb_define_method(rb_cSymbol, "next", sym_succ, 0);

    rb_define_method(rb_cSymbol, "<=>", sym_cmp, 1);
    rb_define_method(rb_cSymbol, "casecmp", sym_casecmp, 1);
    rb_define_method(rb_cSymbol, "=~", sym_match, 1);

    rb_define_method(rb_cSymbol, "[]", sym_aref, -1);
    rb_define_method(rb_cSymbol, "slice", sym_aref, -1);
    rb_define_method(rb_cSymbol, "length", sym_length, 0);
    rb_define_method(rb_cSymbol, "size", sym_length, 0);
    rb_define_method(rb_cSymbol, "empty?", sym_empty, 0);
    rb_define_method(rb_cSymbol, "match", sym_match, 1);

    rb_define_method(rb_cSymbol, "upcase", sym_upcase, 0);
    rb_define_method(rb_cSymbol, "downcase", sym_downcase, 0);
    rb_define_method(rb_cSymbol, "capitalize", sym_capitalize, 0);
    rb_define_method(rb_cSymbol, "swapcase", sym_swapcase, 0);

    rb_define_method(rb_cSymbol, "encoding", sym_encoding, 0);

    assert(rb_vm_fstring_table());
    st_foreach(rb_vm_fstring_table(), fstring_set_class_i, rb_cString);
}
