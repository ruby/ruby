/**********************************************************************

  string.c -

  $Author$
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include <ctype.h>
#include <errno.h>
#include <math.h>

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#include "debug_counter.h"
#include "encindex.h"
#include "gc.h"
#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/compar.h"
#include "internal/compilers.h"
#include "internal/encoding.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/re.h"
#include "internal/sanitizers.h"
#include "internal/string.h"
#include "internal/transcode.h"
#include "probes.h"
#include "ruby/encoding.h"
#include "ruby/re.h"
#include "ruby/util.h"
#include "ruby_assert.h"
#include "vm_sync.h"

#if defined HAVE_CRYPT_R
# if defined HAVE_CRYPT_H
#  include <crypt.h>
# endif
#elif !defined HAVE_CRYPT
# include "missing/crypt.h"
# define HAVE_CRYPT_R 1
#endif

#define BEG(no) (regs->beg[(no)])
#define END(no) (regs->end[(no)])

#undef rb_str_new
#undef rb_usascii_str_new
#undef rb_utf8_str_new
#undef rb_enc_str_new
#undef rb_str_new_cstr
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

VALUE rb_cString;
VALUE rb_cSymbol;

/* FLAGS of RString
 *
 * 1:     RSTRING_NOEMBED
 * 2:     STR_SHARED (== ELTS_SHARED)
 * 2-6:   RSTRING_EMBED_LEN (5 bits == 32)
 * 5:     STR_SHARED_ROOT (RSTRING_NOEMBED==1 && STR_SHARED == 0, there may be
 *                         other strings that rely on this string's buffer)
 * 6:     STR_BORROWED (when RSTRING_NOEMBED==1 && klass==0, unsafe to recycle
 *                      early, specific to rb_str_tmp_frozen_{acquire,release})
 * 7:     STR_TMPLOCK (set when a pointer to the buffer is passed to syscall
 *                     such as read(2). Any modification and realloc is prohibited)
 *
 * 8-9:   ENC_CODERANGE (2 bits)
 * 10-16: ENCODING (7 bits == 128)
 * 17:    RSTRING_FSTR
 * 18:    STR_NOFREE (do not free this string's buffer when a String is freed.
 *                    used for a string object based on C string literal)
 * 19:    STR_FAKESTR (when RVALUE is not managed by GC. Typically, the string
 *                     object header is temporarily allocated on C stack)
 */

#define RUBY_MAX_CHAR_LEN 16
#define STR_SHARED_ROOT FL_USER5
#define STR_BORROWED FL_USER6
#define STR_TMPLOCK FL_USER7
#define STR_NOFREE FL_USER18
#define STR_FAKESTR FL_USER19

#define STR_SET_NOEMBED(str) do {\
    FL_SET((str), STR_NOEMBED);\
    if (USE_RVARGC) {\
        FL_UNSET((str), STR_SHARED | STR_SHARED_ROOT | STR_BORROWED);\
    }\
    else {\
        STR_SET_EMBED_LEN((str), 0);\
    }\
} while (0)
#define STR_SET_EMBED(str) FL_UNSET((str), (STR_NOEMBED|STR_NOFREE))
#if USE_RVARGC
# define STR_SET_EMBED_LEN(str, n) do { \
    assert(str_embed_capa(str) > (n));\
    RSTRING(str)->as.embed.len = (n);\
} while (0)
#else
# define STR_SET_EMBED_LEN(str, n) do { \
    long tmp_n = (n);\
    RBASIC(str)->flags &= ~RSTRING_EMBED_LEN_MASK;\
    RBASIC(str)->flags |= (tmp_n) << RSTRING_EMBED_LEN_SHIFT;\
} while (0)
#endif

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

static inline bool
str_enc_fastpath(VALUE str)
{
    // The overwhelming majority of strings are in one of these 3 encodings.
    switch (ENCODING_GET_INLINED(str)) {
      case ENCINDEX_ASCII_8BIT:
      case ENCINDEX_UTF_8:
      case ENCINDEX_US_ASCII:
        return true;
      default:
        return false;
    }
}

#define TERM_LEN(str) (str_enc_fastpath(str) ? 1 : rb_enc_mbminlen(rb_enc_from_index(ENCODING_GET(str))))
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
        if (str_embed_capa(str) < capacity + termlen) {\
            char *const tmp = ALLOC_N(char, (size_t)(capacity) + (termlen));\
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
        SIZED_REALLOC_N(RSTRING(str)->as.heap.ptr, char, \
                        (size_t)(capacity) + (termlen), STR_HEAP_SIZE(str)); \
        RSTRING(str)->as.heap.aux.capa = (capacity);\
    }\
} while (0)

#define STR_SET_SHARED(str, shared_str) do { \
    if (!FL_TEST(str, STR_FAKESTR)) { \
        assert(RSTRING_PTR(shared_str) <= RSTRING_PTR(str)); \
        assert(RSTRING_PTR(str) <= RSTRING_PTR(shared_str) + RSTRING_LEN(shared_str)); \
        RB_OBJ_WRITE((str), &RSTRING(str)->as.heap.aux.shared, (shared_str)); \
        FL_SET((str), STR_SHARED); \
        FL_SET((shared_str), STR_SHARED_ROOT); \
        if (RBASIC_CLASS((shared_str)) == 0) /* for CoW-friendliness */ \
            FL_SET_RAW((shared_str), STR_BORROWED); \
    } \
} while (0)

#define STR_HEAP_PTR(str)  (RSTRING(str)->as.heap.ptr)
#define STR_HEAP_SIZE(str) ((size_t)RSTRING(str)->as.heap.aux.capa + TERM_LEN(str))
/* TODO: include the terminator size in capa. */

#define STR_ENC_GET(str) get_encoding(str)

#if !defined SHARABLE_MIDDLE_SUBSTRING
# define SHARABLE_MIDDLE_SUBSTRING 0
#endif
#if !SHARABLE_MIDDLE_SUBSTRING
#define SHARABLE_SUBSTRING_P(beg, len, end) ((beg) + (len) == (end))
#else
#define SHARABLE_SUBSTRING_P(beg, len, end) 1
#endif


static inline long
str_embed_capa(VALUE str)
{
#if USE_RVARGC
    return rb_gc_obj_slot_size(str) - offsetof(struct RString, as.embed.ary);
#else
    return RSTRING_EMBED_LEN_MAX + 1;
#endif
}

bool
rb_str_reembeddable_p(VALUE str)
{
    return !FL_TEST(str, STR_NOFREE|STR_SHARED_ROOT|STR_SHARED);
}

static inline size_t
rb_str_embed_size(long capa)
{
    return offsetof(struct RString, as.embed.ary) + capa;
}

size_t
rb_str_size_as_embedded(VALUE str)
{
    size_t real_size;
#if USE_RVARGC
    if (STR_EMBED_P(str)) {
        real_size = rb_str_embed_size(RSTRING(str)->as.embed.len) + TERM_LEN(str);
    }
    /* if the string is not currently embedded, but it can be embedded, how
     * much space would it require */
    else if (rb_str_reembeddable_p(str)) {
        real_size = rb_str_embed_size(RSTRING(str)->as.heap.aux.capa) + TERM_LEN(str);
    }
    else {
#endif
        real_size = sizeof(struct RString);
#if USE_RVARGC
    }
#endif
    return real_size;
}

static inline bool
STR_EMBEDDABLE_P(long len, long termlen)
{
#if USE_RVARGC
    return rb_gc_size_allocatable_p(rb_str_embed_size(len + termlen));
#else
    return len <= RSTRING_EMBED_LEN_MAX + 1 - termlen;
#endif
}

static VALUE str_replace_shared_without_enc(VALUE str2, VALUE str);
static VALUE str_new_frozen(VALUE klass, VALUE orig);
static VALUE str_new_frozen_buffer(VALUE klass, VALUE orig, int copy_encoding);
static VALUE str_new_static(VALUE klass, const char *ptr, long len, int encindex);
static VALUE str_new(VALUE klass, const char *ptr, long len);
static void str_make_independent_expand(VALUE str, long len, long expand, const int termlen);
static inline void str_modifiable(VALUE str);
static VALUE rb_str_downcase(int argc, VALUE *argv, VALUE str);

static inline void
str_make_independent(VALUE str)
{
    long len = RSTRING_LEN(str);
    int termlen = TERM_LEN(str);
    str_make_independent_expand((str), len, 0L, termlen);
}

static inline int str_dependent_p(VALUE str);

void
rb_str_make_independent(VALUE str)
{
    if (str_dependent_p(str)) {
        str_make_independent(str);
    }
}

void
rb_str_make_embedded(VALUE str)
{
    RUBY_ASSERT(rb_str_reembeddable_p(str));
    RUBY_ASSERT(!STR_EMBED_P(str));

    char *buf = RSTRING(str)->as.heap.ptr;
    long len = RSTRING(str)->as.heap.len;

    STR_SET_EMBED(str);
    STR_SET_EMBED_LEN(str, len);

    if (len > 0) {
        memcpy(RSTRING_PTR(str), buf, len);
        ruby_xfree(buf);
    }

    TERM_FILL(RSTRING(str)->as.embed.ary + len, TERM_LEN(str));
}

void
rb_str_update_shared_ary(VALUE str, VALUE old_root, VALUE new_root)
{
    // if the root location hasn't changed, we don't need to update
    if (new_root == old_root) {
        return;
    }

    // if the root string isn't embedded, we don't need to touch the ponter.
    // it already points to the shame shared buffer
    if (!STR_EMBED_P(new_root)) {
        return;
    }

    size_t offset = (size_t)((uintptr_t)RSTRING(str)->as.heap.ptr - (uintptr_t)RSTRING(old_root)->as.embed.ary);

    RUBY_ASSERT(RSTRING(str)->as.heap.ptr >= RSTRING(old_root)->as.embed.ary);
    RSTRING(str)->as.heap.ptr = RSTRING(new_root)->as.embed.ary + offset;
}

void
rb_debug_rstring_null_ptr(const char *func)
{
    fprintf(stderr, "%s is returning NULL!! "
            "SIGSEGV is highly expected to follow immediately.\n"
            "If you could reproduce, attach your debugger here, "
            "and look at the passed string.\n",
            func);
}

/* symbols for [up|down|swap]case/capitalize options */
static VALUE sym_ascii, sym_turkic, sym_lithuanian, sym_fold;

static rb_encoding *
get_encoding(VALUE str)
{
    return rb_enc_from_index(ENCODING_GET(str));
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

static VALUE register_fstring(VALUE str, bool copy);

const struct st_hash_type rb_fstring_hash_type = {
    fstring_cmp,
    rb_str_hash,
};

#define BARE_STRING_P(str) (!FL_ANY_RAW(str, FL_EXIVAR) && RBASIC_CLASS(str) == rb_cString)

struct fstr_update_arg {
    VALUE fstr;
    bool copy;
};

static int
fstr_update_callback(st_data_t *key, st_data_t *value, st_data_t data, int existing)
{

    struct fstr_update_arg *arg = (struct fstr_update_arg *)data;
    VALUE str = (VALUE)*key;

    if (existing) {
        /* because of lazy sweep, str may be unmarked already and swept
         * at next time */

        if (rb_objspace_garbage_object_p(str)) {
            arg->fstr = Qundef;
            return ST_DELETE;
        }

        arg->fstr = str;
        return ST_STOP;
    }
    else {
        if (FL_TEST_RAW(str, STR_FAKESTR)) {
            if (arg->copy) {
                VALUE new_str = str_new(rb_cString, RSTRING(str)->as.heap.ptr, RSTRING(str)->as.heap.len);
                rb_enc_copy(new_str, str);
                str = new_str;
            }
            else {
                str = str_new_static(rb_cString, RSTRING(str)->as.heap.ptr,
                                     RSTRING(str)->as.heap.len,
                                     ENCODING_GET(str));
            }
            OBJ_FREEZE_RAW(str);
        }
        else {
            if (!OBJ_FROZEN(str))
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

        *key = *value = arg->fstr = str;
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
    if (!bare) {
        if (STR_EMBED_P(str)) {
            OBJ_FREEZE_RAW(str);
            return str;
        }
        if (FL_TEST_RAW(str, STR_NOEMBED|STR_SHARED_ROOT|STR_SHARED) == (STR_NOEMBED|STR_SHARED_ROOT)) {
            assert(OBJ_FROZEN(str));
            return str;
        }
    }

    if (!OBJ_FROZEN(str))
        rb_str_resize(str, RSTRING_LEN(str));

    fstr = register_fstring(str, FALSE);

    if (!bare) {
        str_replace_shared_without_enc(str, fstr);
        OBJ_FREEZE_RAW(str);
        return str;
    }
    return fstr;
}

static VALUE
register_fstring(VALUE str, bool copy)
{
    struct fstr_update_arg args;
    args.copy = copy;

    RB_VM_LOCK_ENTER();
    {
        st_table *frozen_strings = rb_vm_fstring_table();
        do {
            args.fstr = str;
            st_update(frozen_strings, (st_data_t)str, fstr_update_callback, (st_data_t)&args);
        } while (UNDEF_P(args.fstr));
    }
    RB_VM_LOCK_LEAVE();

    assert(OBJ_FROZEN(args.fstr));
    assert(!FL_TEST_RAW(args.fstr, STR_FAKESTR));
    assert(!FL_TEST_RAW(args.fstr, FL_EXIVAR));
    assert(RBASIC_CLASS(args.fstr) == rb_cString);
    return args.fstr;
}

static VALUE
setup_fake_str(struct RString *fake_str, const char *name, long len, int encidx)
{
    fake_str->basic.flags = T_STRING|RSTRING_NOEMBED|STR_NOFREE|STR_FAKESTR;
    /* SHARED to be allocated by the callback */

    if (!name) {
        RUBY_ASSERT_ALWAYS(len == 0);
        name = "";
    }

    ENCODING_SET_INLINED((VALUE)fake_str, encidx);

    RBASIC_SET_CLASS_RAW((VALUE)fake_str, rb_cString);
    fake_str->as.heap.len = len;
    fake_str->as.heap.ptr = (char *)name;
    fake_str->as.heap.aux.capa = len;
    return (VALUE)fake_str;
}

/*
 * set up a fake string which refers a static string literal.
 */
VALUE
rb_setup_fake_str(struct RString *fake_str, const char *name, long len, rb_encoding *enc)
{
    return setup_fake_str(fake_str, name, len, rb_enc_to_index(enc));
}

/*
 * rb_fstring_new and rb_fstring_cstr family create or lookup a frozen
 * shared string which refers a static string literal.  `ptr` must
 * point a constant string.
 */
MJIT_FUNC_EXPORTED VALUE
rb_fstring_new(const char *ptr, long len)
{
    struct RString fake_str;
    return register_fstring(setup_fake_str(&fake_str, ptr, len, ENCINDEX_US_ASCII), FALSE);
}

VALUE
rb_fstring_enc_new(const char *ptr, long len, rb_encoding *enc)
{
    struct RString fake_str;
    return register_fstring(rb_setup_fake_str(&fake_str, ptr, len, enc), FALSE);
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
    const uintptr_t *s, *t;

#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
# if SIZEOF_UINTPTR_T == 8
#  define NONASCII_MASK UINT64_C(0x8080808080808080)
# elif SIZEOF_UINTPTR_T == 4
#  define NONASCII_MASK UINT32_C(0x80808080)
# else
#  error "don't know what to do."
# endif
#else
# if SIZEOF_UINTPTR_T == 8
#  define NONASCII_MASK ((uintptr_t)0x80808080UL << 32 | (uintptr_t)0x80808080UL)
# elif SIZEOF_UINTPTR_T == 4
#  define NONASCII_MASK 0x80808080UL /* or...? */
# else
#  error "don't know what to do."
# endif
#endif

    if (UNALIGNED_WORD_ACCESS || e - p >= SIZEOF_VOIDP) {
#if !UNALIGNED_WORD_ACCESS
        if ((uintptr_t)p % SIZEOF_VOIDP) {
            int l = SIZEOF_VOIDP - (uintptr_t)p % SIZEOF_VOIDP;
            p += l;
            switch (l) {
              default: UNREACHABLE;
#if SIZEOF_VOIDP > 4
              case 7: if (p[-7]&0x80) return p-7;
              case 6: if (p[-6]&0x80) return p-6;
              case 5: if (p[-5]&0x80) return p-5;
              case 4: if (p[-4]&0x80) return p-4;
#endif
              case 3: if (p[-3]&0x80) return p-3;
              case 2: if (p[-2]&0x80) return p-2;
              case 1: if (p[-1]&0x80) return p-1;
              case 0: break;
            }
        }
#endif
#if defined(HAVE_BUILTIN___BUILTIN_ASSUME_ALIGNED) &&! UNALIGNED_WORD_ACCESS
#define aligned_ptr(value) \
        __builtin_assume_aligned((value), sizeof(uintptr_t))
#else
#define aligned_ptr(value) (uintptr_t *)(value)
#endif
        s = aligned_ptr(p);
        t = (uintptr_t *)(e - (SIZEOF_VOIDP-1));
#undef aligned_ptr
        for (;s < t; s++) {
            if (*s & NONASCII_MASK) {
#ifdef WORDS_BIGENDIAN
                return (const char *)s + (nlz_intptr(*s&NONASCII_MASK)>>3);
#else
                return (const char *)s + (ntz_intptr(*s&NONASCII_MASK)>>3);
#endif
            }
        }
        p = (const char *)s;
    }

    switch (e - p) {
      default: UNREACHABLE;
#if SIZEOF_VOIDP > 4
      case 7: if (e[-7]&0x80) return e-7;
      case 6: if (e[-6]&0x80) return e-6;
      case 5: if (e[-5]&0x80) return e-5;
      case 4: if (e[-4]&0x80) return e-4;
#endif
      case 3: if (e[-3]&0x80) return e-3;
      case 2: if (e[-2]&0x80) return e-2;
      case 1: if (e[-1]&0x80) return e-1;
      case 0: return NULL;
    }
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

static int
enc_coderange_scan(VALUE str, rb_encoding *enc)
{
    return coderange_scan(RSTRING_PTR(str), RSTRING_LEN(str), enc);
}

int
rb_enc_str_coderange_scan(VALUE str, rb_encoding *enc)
{
    return enc_coderange_scan(str, enc);
}

int
rb_enc_str_coderange(VALUE str)
{
    int cr = ENC_CODERANGE(str);

    if (cr == ENC_CODERANGE_UNKNOWN) {
        cr = enc_coderange_scan(str, get_encoding(str));
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
    else if (is_ascii_string(str))
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
#if USE_RVARGC
        return str_embed_capa(str) - termlen;
#else
        return (RSTRING_EMBED_LEN_MAX + 1 - termlen);
#endif
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
str_alloc_embed(VALUE klass, size_t capa)
{
    size_t size = rb_str_embed_size(capa);
    assert(size > 0);
    assert(rb_gc_size_allocatable_p(size));
#if !USE_RVARGC
    assert(size <= sizeof(struct RString));
#endif

    RVARGC_NEWOBJ_OF(str, struct RString, klass,
                     T_STRING | (RGENGC_WB_PROTECTED_STRING ? FL_WB_PROTECTED : 0), size);

    return (VALUE)str;
}

static inline VALUE
str_alloc_heap(VALUE klass)
{
    RVARGC_NEWOBJ_OF(str, struct RString, klass,
                     T_STRING | STR_NOEMBED | (RGENGC_WB_PROTECTED_STRING ? FL_WB_PROTECTED : 0), sizeof(struct RString));

    return (VALUE)str;
}

static inline VALUE
empty_str_alloc(VALUE klass)
{
    RUBY_DTRACE_CREATE_HOOK(STRING, 0);
    VALUE str = str_alloc_embed(klass, 0);
    memset(RSTRING(str)->as.embed.ary, 0, str_embed_capa(str));
    return str;
}

static VALUE
str_new0(VALUE klass, const char *ptr, long len, int termlen)
{
    VALUE str;

    if (len < 0) {
        rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    RUBY_DTRACE_CREATE_HOOK(STRING, len);

    if (STR_EMBEDDABLE_P(len, termlen)) {
        str = str_alloc_embed(klass, len + termlen);
        if (len == 0) {
            ENC_CODERANGE_SET(str, ENC_CODERANGE_7BIT);
        }
    }
    else {
        str = str_alloc_heap(klass);
        RSTRING(str)->as.heap.aux.capa = len;
        /* :FIXME: @shyouhei guesses `len + termlen` is guaranteed to never
         * integer overflow.  If we can STATIC_ASSERT that, the following
         * mul_add_mul can be reverted to a simple ALLOC_N. */
        RSTRING(str)->as.heap.ptr =
            rb_xmalloc_mul_add_mul(sizeof(char), len, sizeof(char), termlen);
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
    /* rb_str_new_cstr() can take pointer from non-malloc-generated
     * memory regions, and that cannot be detected by the MSAN.  Just
     * trust the programmer that the argument passed here is a sane C
     * string. */
    __msan_unpoison_string(ptr);
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
        str = str_alloc_heap(klass);
        RSTRING(str)->as.heap.len = len;
        RSTRING(str)->as.heap.ptr = (char *)ptr;
        RSTRING(str)->as.heap.aux.capa = len;
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

static VALUE str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
                                   rb_encoding *from, rb_encoding *to,
                                   int ecflags, VALUE ecopts);

static inline bool
is_enc_ascii_string(VALUE str, rb_encoding *enc)
{
    int encidx = rb_enc_to_index(enc);
    if (rb_enc_get_index(str) == encidx)
        return is_ascii_string(str);
    return enc_coderange_scan(str, enc) == ENC_CODERANGE_7BIT;
}

VALUE
rb_str_conv_enc_opts(VALUE str, rb_encoding *from, rb_encoding *to, int ecflags, VALUE ecopts)
{
    long len;
    const char *ptr;
    VALUE newstr;

    if (!to) return str;
    if (!from) from = rb_enc_get(str);
    if (from == to) return str;
    if ((rb_enc_asciicompat(to) && is_enc_ascii_string(str, from)) ||
        rb_is_ascii8bit_enc(to)) {
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
    return newstr;
}

VALUE
rb_str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
                         rb_encoding *from, int ecflags, VALUE ecopts)
{
    long olen;

    olen = RSTRING_LEN(newstr);
    if (ofs < -olen || olen < ofs)
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

VALUE
rb_str_initialize(VALUE str, const char *ptr, long len, rb_encoding *enc)
{
    STR_SET_LEN(str, 0);
    rb_enc_associate(str, enc);
    rb_str_cat(str, ptr, len);
    return str;
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
    rb_encoding *ienc;
    VALUE str;
    const int eidx = rb_enc_to_index(eenc);

    if (!ptr) {
        return rb_enc_str_new(ptr, len, eenc);
    }

    /* ASCII-8BIT case, no conversion */
    if ((eidx == rb_ascii8bit_encindex()) ||
        (eidx == rb_usascii_encindex() && search_nonascii(ptr, ptr + len))) {
        return rb_str_new(ptr, len);
    }
    /* no default_internal or same encoding, no conversion */
    ienc = rb_default_internal_encoding();
    if (!ienc || eenc == ienc) {
        return rb_enc_str_new(ptr, len, eenc);
    }
    /* ASCII compatible, and ASCII only string, no conversion in
     * default_internal */
    if ((eidx == rb_ascii8bit_encindex()) ||
        (eidx == rb_usascii_encindex()) ||
        (rb_enc_asciicompat(eenc) && !search_nonascii(ptr, ptr + len))) {
        return rb_enc_str_new(ptr, len, ienc);
    }
    /* convert from the given encoding to default_internal */
    str = rb_enc_str_new(NULL, 0, ienc);
    /* when the conversion failed for some reason, just ignore the
     * default_internal and result in the given encoding as-is. */
    if (NIL_P(rb_str_cat_conv_enc_opts(str, 0, ptr, len, eenc, 0, Qnil))) {
        rb_str_initialize(str, ptr, len, eenc);
    }
    return str;
}

VALUE
rb_external_str_with_enc(VALUE str, rb_encoding *eenc)
{
    int eidx = rb_enc_to_index(eenc);
    if (eidx == rb_usascii_encindex() &&
        !is_ascii_string(str)) {
        rb_enc_associate_index(str, rb_ascii8bit_encindex());
        return str;
    }
    rb_enc_associate_index(str, eidx);
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
    return rb_str_export_to_enc(str, rb_default_external_encoding());
}

VALUE
rb_str_export_locale(VALUE str)
{
    return rb_str_export_to_enc(str, rb_locale_encoding());
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
    if (str_embed_capa(str2) >= len + termlen) {
        char *ptr2 = RSTRING(str2)->as.embed.ary;
        STR_SET_EMBED(str2);
        memcpy(ptr2, RSTRING_PTR(str), len);
        STR_SET_EMBED_LEN(str2, len);
        TERM_FILL(ptr2+len, termlen);
    }
    else {
        VALUE root;
        if (STR_SHARED_P(str)) {
            root = RSTRING(str)->as.heap.aux.shared;
            RSTRING_GETMEM(str, ptr, len);
        }
        else {
            root = rb_str_new_frozen(str);
            RSTRING_GETMEM(root, ptr, len);
        }
        assert(OBJ_FROZEN(root));
        if (!STR_EMBED_P(str2) && !FL_TEST_RAW(str2, STR_SHARED|STR_NOFREE)) {
            if (FL_TEST_RAW(str2, STR_SHARED_ROOT)) {
                rb_fatal("about to free a possible shared root");
            }
            char *ptr2 = STR_HEAP_PTR(str2);
            if (ptr2 != ptr) {
                ruby_sized_xfree(ptr2, STR_HEAP_SIZE(str2));
            }
        }
        FL_SET(str2, STR_NOEMBED);
        RSTRING(str2)->as.heap.len = len;
        RSTRING(str2)->as.heap.ptr = ptr;
        STR_SET_SHARED(str2, root);
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
    return str_replace_shared(str_alloc_heap(klass), str);
}

VALUE
rb_str_new_shared(VALUE str)
{
    return str_new_shared(rb_obj_class(str), str);
}

VALUE
rb_str_new_frozen(VALUE orig)
{
    if (OBJ_FROZEN(orig)) return orig;
    return str_new_frozen(rb_obj_class(orig), orig);
}

static VALUE
rb_str_new_frozen_String(VALUE orig)
{
    if (OBJ_FROZEN(orig) && rb_obj_class(orig) == rb_cString) return orig;
    return str_new_frozen(rb_cString, orig);
}

VALUE
rb_str_tmp_frozen_acquire(VALUE orig)
{
    if (OBJ_FROZEN_RAW(orig)) return orig;
    return str_new_frozen_buffer(0, orig, FALSE);
}

VALUE
rb_str_tmp_frozen_no_embed_acquire(VALUE orig)
{
    if (OBJ_FROZEN_RAW(orig) && !STR_EMBED_P(orig) && !rb_str_reembeddable_p(orig)) return orig;
    if (STR_SHARED_P(orig) && !STR_EMBED_P(RSTRING(orig)->as.heap.aux.shared)) return rb_str_tmp_frozen_acquire(orig);

    VALUE str = str_alloc_heap(0);
    OBJ_FREEZE(str);
    /* Always set the STR_SHARED_ROOT to ensure it does not get re-embedded. */
    FL_SET(str, STR_SHARED_ROOT);

    size_t capa = str_capacity(orig, TERM_LEN(orig));

    /* If the string is embedded then we want to create a copy that is heap
     * allocated. If the string is shared then the shared root must be
     * embedded, so we want to create a copy. If the string is a shared root
     * then it must be embedded, so we want to create a copy. */
    if (STR_EMBED_P(orig) || FL_TEST_RAW(orig, STR_SHARED | STR_SHARED_ROOT)) {
        RSTRING(str)->as.heap.ptr = rb_xmalloc_mul_add_mul(sizeof(char), capa, sizeof(char), TERM_LEN(orig));
        memcpy(RSTRING(str)->as.heap.ptr, RSTRING_PTR(orig), capa);
    }
    else {
        /* orig must be heap allocated and not shared, so we can safely transfer
         * the pointer to str. */
        RSTRING(str)->as.heap.ptr = RSTRING(orig)->as.heap.ptr;
        RBASIC(str)->flags |= RBASIC(orig)->flags & STR_NOFREE;
        RBASIC(orig)->flags &= ~STR_NOFREE;
        STR_SET_SHARED(orig, str);
    }

    RSTRING(str)->as.heap.len = RSTRING(orig)->as.heap.len;
    RSTRING(str)->as.heap.aux.capa = capa;

    return str;
}

void
rb_str_tmp_frozen_release(VALUE orig, VALUE tmp)
{
    if (RBASIC_CLASS(tmp) != 0)
        return;

    if (STR_EMBED_P(tmp)) {
        assert(OBJ_FROZEN_RAW(tmp));
    }
    else if (FL_TEST_RAW(orig, STR_SHARED) &&
            !FL_TEST_RAW(orig, STR_TMPLOCK|RUBY_FL_FREEZE)) {
        VALUE shared = RSTRING(orig)->as.heap.aux.shared;

        if (shared == tmp && !FL_TEST_RAW(tmp, STR_BORROWED)) {
            assert(RSTRING(orig)->as.heap.ptr == RSTRING(tmp)->as.heap.ptr);
            assert(RSTRING(orig)->as.heap.len == RSTRING(tmp)->as.heap.len);

            /* Unshare orig since the root (tmp) only has this one child. */
            FL_UNSET_RAW(orig, STR_SHARED);
            RSTRING(orig)->as.heap.aux.capa = RSTRING(tmp)->as.heap.aux.capa;
            RBASIC(orig)->flags |= RBASIC(tmp)->flags & STR_NOFREE;
            assert(OBJ_FROZEN_RAW(tmp));

            /* Make tmp embedded and empty so it is safe for sweeping. */
            STR_SET_EMBED(tmp);
            STR_SET_EMBED_LEN(tmp, 0);
        }
    }
}

static VALUE
str_new_frozen(VALUE klass, VALUE orig)
{
    return str_new_frozen_buffer(klass, orig, TRUE);
}

static VALUE
heap_str_make_shared(VALUE klass, VALUE orig)
{
    assert(!STR_EMBED_P(orig));
    assert(!STR_SHARED_P(orig));

    VALUE str = str_alloc_heap(klass);
    RSTRING(str)->as.heap.len = RSTRING_LEN(orig);
    RSTRING(str)->as.heap.ptr = RSTRING_PTR(orig);
    RSTRING(str)->as.heap.aux.capa = RSTRING(orig)->as.heap.aux.capa;
    RBASIC(str)->flags |= RBASIC(orig)->flags & STR_NOFREE;
    RBASIC(orig)->flags &= ~STR_NOFREE;
    STR_SET_SHARED(orig, str);
    if (klass == 0)
        FL_UNSET_RAW(str, STR_BORROWED);
    return str;
}

static VALUE
str_new_frozen_buffer(VALUE klass, VALUE orig, int copy_encoding)
{
    VALUE str;

    long len = RSTRING_LEN(orig);
    int termlen = copy_encoding ? TERM_LEN(orig) : 1;

    if (STR_EMBED_P(orig) || STR_EMBEDDABLE_P(len, termlen)) {
        str = str_new0(klass, RSTRING_PTR(orig), len, termlen);
        assert(STR_EMBED_P(str));
    }
    else {
        if (FL_TEST_RAW(orig, STR_SHARED)) {
            VALUE shared = RSTRING(orig)->as.heap.aux.shared;
            long ofs = RSTRING(orig)->as.heap.ptr - RSTRING_PTR(shared);
            long rest = RSTRING_LEN(shared) - ofs - RSTRING(orig)->as.heap.len;
            assert(ofs >= 0);
            assert(rest >= 0);
            assert(ofs + rest <= RSTRING_LEN(shared));
#if !USE_RVARGC
            assert(!STR_EMBED_P(shared));
#endif
            assert(OBJ_FROZEN(shared));

            if ((ofs > 0) || (rest > 0) ||
                (klass != RBASIC(shared)->klass) ||
                ENCODING_GET(shared) != ENCODING_GET(orig)) {
                str = str_new_shared(klass, shared);
                assert(!STR_EMBED_P(str));
                RSTRING(str)->as.heap.ptr += ofs;
                RSTRING(str)->as.heap.len -= ofs + rest;
            }
            else {
                if (RBASIC_CLASS(shared) == 0)
                    FL_SET_RAW(shared, STR_BORROWED);
                return shared;
            }
        }
        else if (STR_EMBEDDABLE_P(RSTRING_LEN(orig), TERM_LEN(orig))) {
            str = str_alloc_embed(klass, RSTRING_LEN(orig) + TERM_LEN(orig));
            STR_SET_EMBED(str);
            memcpy(RSTRING_PTR(str), RSTRING_PTR(orig), RSTRING_LEN(orig));
            STR_SET_EMBED_LEN(str, RSTRING_LEN(orig));
            TERM_FILL(RSTRING_END(str), TERM_LEN(orig));
        }
        else {
            str = heap_str_make_shared(klass, orig);
        }
    }

    if (copy_encoding) rb_enc_cr_str_exact_copy(str, orig);
    OBJ_FREEZE(str);
    return str;
}

VALUE
rb_str_new_with_class(VALUE obj, const char *ptr, long len)
{
    return str_new0(rb_obj_class(obj), ptr, len, TERM_LEN(obj));
}

static VALUE
str_new_empty_String(VALUE str)
{
    VALUE v = rb_str_new(0, 0);
    rb_enc_copy(v, str);
    return v;
}

#define STR_BUF_MIN_SIZE 63
#if !USE_RVARGC
STATIC_ASSERT(STR_BUF_MIN_SIZE, STR_BUF_MIN_SIZE > RSTRING_EMBED_LEN_MAX);
#endif

VALUE
rb_str_buf_new(long capa)
{
    if (STR_EMBEDDABLE_P(capa, 1)) {
        return str_alloc_embed(rb_cString, capa + 1);
    }

    VALUE str = str_alloc_heap(rb_cString);

#if !USE_RVARGC
    if (capa < STR_BUF_MIN_SIZE) {
        capa = STR_BUF_MIN_SIZE;
    }
#endif
    RSTRING(str)->as.heap.aux.capa = capa;
    RSTRING(str)->as.heap.ptr = ALLOC_N(char, (size_t)capa + 1);
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

        RB_VM_LOCK_ENTER();
        {
            st_delete(rb_vm_fstring_table(), &fstr, NULL);
            RB_DEBUG_COUNTER_INC(obj_str_fstr);
        }
        RB_VM_LOCK_LEAVE();
    }

    if (STR_EMBED_P(str)) {
        RB_DEBUG_COUNTER_INC(obj_str_embed);
    }
    else if (FL_TEST(str, STR_SHARED | STR_NOFREE)) {
        (void)RB_DEBUG_COUNTER_INC_IF(obj_str_shared, FL_TEST(str, STR_SHARED));
        (void)RB_DEBUG_COUNTER_INC_IF(obj_str_shared, FL_TEST(str, STR_NOFREE));
    }
    else {
        RB_DEBUG_COUNTER_INC(obj_str_ptr);
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
    return rb_convert_type_with_id(str, T_STRING, "String", idTo_str);
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

    RUBY_ASSERT(str2 != str);
    enc = STR_ENC_GET(str2);
    cr = ENC_CODERANGE(str2);
    str_discard(str);
    termlen = rb_enc_mbminlen(enc);

    if (str_embed_capa(str) >= RSTRING_LEN(str2) + termlen) {
        STR_SET_EMBED(str);
        memcpy(RSTRING_PTR(str), RSTRING_PTR(str2), (size_t)RSTRING_LEN(str2) + termlen);
        STR_SET_EMBED_LEN(str, RSTRING_LEN(str2));
        rb_enc_associate(str, enc);
        ENC_CODERANGE_SET(str, cr);
    }
    else {
#if USE_RVARGC
        if (STR_EMBED_P(str2)) {
            assert(!FL_TEST(str2, STR_SHARED));
            long len = RSTRING(str2)->as.embed.len;
            assert(len + termlen <= str_embed_capa(str2));

            char *new_ptr = ALLOC_N(char, len + termlen);
            memcpy(new_ptr, RSTRING(str2)->as.embed.ary, len + termlen);
            RSTRING(str2)->as.heap.ptr = new_ptr;
            RSTRING(str2)->as.heap.len = len;
            RSTRING(str2)->as.heap.aux.capa = len;
            STR_SET_NOEMBED(str2);
        }
#endif

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
    return rb_obj_as_string_result(str, obj);
}

MJIT_FUNC_EXPORTED VALUE
rb_obj_as_string_result(VALUE str, VALUE obj)
{
    if (!RB_TYPE_P(str, T_STRING))
        return rb_any_to_s(obj);
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

    return str;
}

static inline VALUE
ec_str_alloc_embed(struct rb_execution_context_struct *ec, VALUE klass, size_t capa)
{
    size_t size = rb_str_embed_size(capa);
    assert(size > 0);
    assert(rb_gc_size_allocatable_p(size));
#if !USE_RVARGC
    assert(size <= sizeof(struct RString));
#endif

    RB_RVARGC_EC_NEWOBJ_OF(ec, str, struct RString, klass,
                           T_STRING | (RGENGC_WB_PROTECTED_STRING ? FL_WB_PROTECTED : 0), size);

    return (VALUE)str;
}

static inline VALUE
ec_str_alloc_heap(struct rb_execution_context_struct *ec, VALUE klass)
{
    RB_RVARGC_EC_NEWOBJ_OF(ec, str, struct RString, klass,
                           T_STRING | STR_NOEMBED | (RGENGC_WB_PROTECTED_STRING ? FL_WB_PROTECTED : 0), sizeof(struct RString));

    return (VALUE)str;
}

static inline VALUE
str_duplicate_setup(VALUE klass, VALUE str, VALUE dup)
{
    const VALUE flag_mask =
#if !USE_RVARGC
        RSTRING_NOEMBED | RSTRING_EMBED_LEN_MASK |
#endif
        ENC_CODERANGE_MASK | ENCODING_MASK |
        FL_FREEZE
        ;
    VALUE flags = FL_TEST_RAW(str, flag_mask);
    int encidx = 0;
    if (STR_EMBED_P(str)) {
        long len = RSTRING_EMBED_LEN(str);

        assert(STR_EMBED_P(dup));
        assert(str_embed_capa(dup) >= len + 1);
        STR_SET_EMBED_LEN(dup, len);
        MEMCPY(RSTRING(dup)->as.embed.ary, RSTRING(str)->as.embed.ary, char, len + 1);
    }
    else {
        VALUE root = str;
        if (FL_TEST_RAW(str, STR_SHARED)) {
            root = RSTRING(str)->as.heap.aux.shared;
        }
        else if (UNLIKELY(!(flags & FL_FREEZE))) {
            root = str = str_new_frozen(klass, str);
            flags = FL_TEST_RAW(str, flag_mask);
        }
        assert(!STR_SHARED_P(root));
        assert(RB_OBJ_FROZEN_RAW(root));
        if (0) {}
#if !USE_RVARGC
        else if (STR_EMBED_P(root)) {
            MEMCPY(RSTRING(dup)->as.embed.ary, RSTRING(root)->as.embed.ary,
                   char, RSTRING_EMBED_LEN_MAX + 1);
            FL_UNSET(dup, STR_NOEMBED);
        }
#endif
        else {
            RSTRING(dup)->as.heap.len = RSTRING_LEN(str);
            RSTRING(dup)->as.heap.ptr = RSTRING_PTR(str);
            FL_SET(root, STR_SHARED_ROOT);
            RB_OBJ_WRITE(dup, &RSTRING(dup)->as.heap.aux.shared, root);
            flags |= RSTRING_NOEMBED | STR_SHARED;
        }
    }

    if ((flags & ENCODING_MASK) == (ENCODING_INLINE_MAX<<ENCODING_SHIFT)) {
        encidx = rb_enc_get_index(str);
        flags &= ~ENCODING_MASK;
    }
    FL_SET_RAW(dup, flags & ~FL_FREEZE);
    if (encidx) rb_enc_associate_index(dup, encidx);
    return dup;
}

static inline VALUE
ec_str_duplicate(struct rb_execution_context_struct *ec, VALUE klass, VALUE str)
{
    VALUE dup;
    if (FL_TEST(str, STR_NOEMBED)) {
        dup = ec_str_alloc_heap(ec, klass);
    }
    else {
        dup = ec_str_alloc_embed(ec, klass, RSTRING_EMBED_LEN(str) + TERM_LEN(str));
    }

    return str_duplicate_setup(klass, str, dup);
}

static inline VALUE
str_duplicate(VALUE klass, VALUE str)
{
    VALUE dup;
    if (FL_TEST(str, STR_NOEMBED)) {
        dup = str_alloc_heap(klass);
    }
    else {
       dup = str_alloc_embed(klass, RSTRING_EMBED_LEN(str) + TERM_LEN(str));
    }

    return str_duplicate_setup(klass, str, dup);
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

VALUE
rb_ec_str_resurrect(struct rb_execution_context_struct *ec, VALUE str)
{
    RUBY_DTRACE_CREATE_HOOK(STRING, RSTRING_LEN(str));
    return ec_str_duplicate(ec, rb_cString, str);
}

/*
 *
 *  call-seq:
 *    String.new(string = '', **opts) -> new_string
 *
 *  :include: doc/string/new.rdoc
 *
 */

static VALUE
rb_str_init(int argc, VALUE *argv, VALUE str)
{
    static ID keyword_ids[2];
    VALUE orig, opt, venc, vcapa;
    VALUE kwargs[2];
    rb_encoding *enc = 0;
    int n;

    if (!keyword_ids[0]) {
        keyword_ids[0] = rb_id_encoding();
        CONST_ID(keyword_ids[1], "capacity");
    }

    n = rb_scan_args(argc, argv, "01:", &orig, &opt);
    if (!NIL_P(opt)) {
        rb_get_kwargs(opt, keyword_ids, 0, 2, kwargs);
        venc = kwargs[0];
        vcapa = kwargs[1];
        if (!UNDEF_P(venc) && !NIL_P(venc)) {
            enc = rb_to_encoding(venc);
        }
        if (!UNDEF_P(vcapa) && !NIL_P(vcapa)) {
            long capa = NUM2LONG(vcapa);
            long len = 0;
            int termlen = enc ? rb_enc_mbminlen(enc) : 1;

            if (capa < STR_BUF_MIN_SIZE) {
                capa = STR_BUF_MIN_SIZE;
            }
            if (n == 1) {
                StringValue(orig);
                len = RSTRING_LEN(orig);
                if (capa < len) {
                    capa = len;
                }
                if (orig == str) n = 0;
            }
            str_modifiable(str);
            if (STR_EMBED_P(str) || FL_TEST(str, STR_SHARED|STR_NOFREE)) {
                /* make noembed always */
                const size_t size = (size_t)capa + termlen;
                const char *const old_ptr = RSTRING_PTR(str);
                const size_t osize = RSTRING_LEN(str) + TERM_LEN(str);
                char *new_ptr = ALLOC_N(char, size);
                if (STR_EMBED_P(str)) RUBY_ASSERT((long)osize <= str_embed_capa(str));
                memcpy(new_ptr, old_ptr, osize < size ? osize : size);
                FL_UNSET_RAW(str, STR_SHARED|STR_NOFREE);
                RSTRING(str)->as.heap.ptr = new_ptr;
            }
            else if (STR_HEAP_SIZE(str) != (size_t)capa + termlen) {
                SIZED_REALLOC_N(RSTRING(str)->as.heap.ptr, char,
                        (size_t)capa + termlen, STR_HEAP_SIZE(str));
            }
            RSTRING(str)->as.heap.len = len;
            TERM_FILL(&RSTRING(str)->as.heap.ptr[len], termlen);
            if (n == 1) {
                memcpy(RSTRING(str)->as.heap.ptr, RSTRING_PTR(orig), len);
                rb_enc_cr_str_exact_copy(str, orig);
            }
            FL_SET(str, STR_NOEMBED);
            RSTRING(str)->as.heap.aux.capa = capa;
        }
        else if (n == 1) {
            rb_str_replace(str, orig);
        }
        if (enc) {
            rb_enc_associate(str, enc);
            ENC_CODERANGE_CLEAR(str);
        }
    }
    else if (n == 1) {
        rb_str_replace(str, orig);
    }
    return str;
}

#ifdef NONASCII_MASK
#define is_utf8_lead_byte(c) (((c)&0xC0) != 0x80)

/*
 * UTF-8 leading bytes have either 0xxxxxxx or 11xxxxxx
 * bit representation. (see https://en.wikipedia.org/wiki/UTF-8)
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
    d = (d>>6) | (~d>>7);
    d &= NONASCII_MASK >> 7;

    /* Gather all bytes. */
#if defined(HAVE_BUILTIN___BUILTIN_POPCOUNT) && defined(__POPCNT__)
    /* use only if it can use POPCNT */
    return rb_popcount_intptr(d);
#else
    d += (d>>8);
    d += (d>>16);
# if SIZEOF_VOIDP == 8
    d += (d>>32);
# endif
    return (d&0xF);
#endif
}
#endif

static inline long
enc_strlen(const char *p, const char *e, rb_encoding *enc, int cr)
{
    long c;
    const char *q;

    if (rb_enc_mbmaxlen(enc) == rb_enc_mbminlen(enc)) {
        long diff = (long)(e - p);
        return diff / rb_enc_mbminlen(enc) + !!(diff % rb_enc_mbminlen(enc));
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
        long diff = (long)(e - p);
        return diff / rb_enc_mbminlen(enc) + !!(diff % rb_enc_mbminlen(enc));
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
 *    length -> integer
 *
 *  :include: doc/string/length.rdoc
 *
 */

VALUE
rb_str_length(VALUE str)
{
    return LONG2NUM(str_strlen(str, NULL));
}

/*
 *  call-seq:
 *    bytesize -> integer
 *
 *  :include: doc/string/bytesize.rdoc
 *
 */

static VALUE
rb_str_bytesize(VALUE str)
{
    return LONG2NUM(RSTRING_LEN(str));
}

/*
 *  call-seq:
 *    empty? -> true or false
 *
 *  Returns +true+ if the length of +self+ is zero, +false+ otherwise:
 *
 *    "hello".empty? # => false
 *    " ".empty? # => false
 *    "".empty? # => true
 *
 */

static VALUE
rb_str_empty(VALUE str)
{
    return RBOOL(RSTRING_LEN(str) == 0);
}

/*
 *  call-seq:
 *    string + other_string -> new_string
 *
 *  Returns a new \String containing +other_string+ concatenated to +self+:
 *
 *    "Hello from " + self.to_s # => "Hello from main"
 *
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
    if (len1 > LONG_MAX - len2) {
        rb_raise(rb_eArgError, "string size too big");
    }
    str3 = str_new0(rb_cString, 0, len1+len2, termlen);
    ptr3 = RSTRING_PTR(str3);
    memcpy(ptr3, ptr1, len1);
    memcpy(ptr3+len1, ptr2, len2);
    TERM_FILL(&ptr3[len1+len2], termlen);

    ENCODING_CODERANGE_SET(str3, rb_enc_to_index(enc),
                           ENC_CODERANGE_AND(ENC_CODERANGE(str1), ENC_CODERANGE(str2)));
    RB_GC_GUARD(str1);
    RB_GC_GUARD(str2);
    return str3;
}

/* A variant of rb_str_plus that does not raise but return Qundef instead. */
MJIT_FUNC_EXPORTED VALUE
rb_str_opt_plus(VALUE str1, VALUE str2)
{
    assert(RBASIC_CLASS(str1) == rb_cString);
    assert(RBASIC_CLASS(str2) == rb_cString);
    long len1, len2;
    MAYBE_UNUSED(char) *ptr1, *ptr2;
    RSTRING_GETMEM(str1, ptr1, len1);
    RSTRING_GETMEM(str2, ptr2, len2);
    int enc1 = rb_enc_get_index(str1);
    int enc2 = rb_enc_get_index(str2);

    if (enc1 < 0) {
        return Qundef;
    }
    else if (enc2 < 0) {
        return Qundef;
    }
    else if (enc1 != enc2) {
        return Qundef;
    }
    else if (len1 > LONG_MAX - len2) {
        return Qundef;
    }
    else {
        return rb_str_plus(str1, str2);
    }

}

/*
 *  call-seq:
 *    string * integer -> new_string
 *
 *  Returns a new \String containing +integer+ copies of +self+:
 *
 *    "Ho! " * 3 # => "Ho! Ho! Ho! "
 *    "Ho! " * 0 # => ""
 *
 */

VALUE
rb_str_times(VALUE str, VALUE times)
{
    VALUE str2;
    long n, len;
    char *ptr2;
    int termlen;

    if (times == INT2FIX(1)) {
        return str_duplicate(rb_cString, str);
    }
    if (times == INT2FIX(0)) {
        str2 = str_alloc_embed(rb_cString, 0);
        rb_enc_copy(str2, str);
        return str2;
    }
    len = NUM2LONG(times);
    if (len < 0) {
        rb_raise(rb_eArgError, "negative argument");
    }
    if (RSTRING_LEN(str) == 1 && RSTRING_PTR(str)[0] == 0) {
        if (STR_EMBEDDABLE_P(len, 1)) {
            str2 = str_alloc_embed(rb_cString, len + 1);
            memset(RSTRING_PTR(str2), 0, len + 1);
        }
        else {
            str2 = str_alloc_heap(rb_cString);
            RSTRING(str2)->as.heap.aux.capa = len;
            RSTRING(str2)->as.heap.ptr = ZALLOC_N(char, (size_t)len + 1);
        }
        STR_SET_LEN(str2, len);
        rb_enc_copy(str2, str);
        return str2;
    }
    if (len && LONG_MAX/len <  RSTRING_LEN(str)) {
        rb_raise(rb_eArgError, "argument too big");
    }

    len *= RSTRING_LEN(str);
    termlen = TERM_LEN(str);
    str2 = str_new0(rb_cString, 0, len, termlen);
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
    rb_enc_cr_str_copy_for_substr(str2, str);

    return str2;
}

/*
 *  call-seq:
 *    string % object -> new_string
 *
 *  Returns the result of formatting +object+ into the format specification +self+
 *  (see Kernel#sprintf for formatting details):
 *
 *    "%05d" % 123 # => "00123"
 *
 *  If +self+ contains multiple substitutions, +object+ must be
 *  an \Array or \Hash containing the values to be substituted:
 *
 *    "%-5s: %016x" % [ "ID", self.object_id ] # => "ID   : 00002b054ec93168"
 *    "foo = %{foo}" % {foo: 'bar'} # => "foo = bar"
 *    "foo = %{foo}, baz = %{baz}" % {foo: 'bar', baz: 'bat'} # => "foo = bar, baz = bat"
 *
 */

static VALUE
rb_str_format_m(VALUE str, VALUE arg)
{
    VALUE tmp = rb_check_array_type(arg);

    if (!NIL_P(tmp)) {
        return rb_str_format(RARRAY_LENINT(tmp), RARRAY_CONST_PTR(tmp), str);
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
    char *oldptr;
    long capa = len + expand;

    if (len > capa) len = capa;

    if (!STR_EMBED_P(str) && str_embed_capa(str) >= capa + termlen) {
        ptr = RSTRING(str)->as.heap.ptr;
        STR_SET_EMBED(str);
        memcpy(RSTRING(str)->as.embed.ary, ptr, len);
        TERM_FILL(RSTRING(str)->as.embed.ary + len, termlen);
        STR_SET_EMBED_LEN(str, len);
        return;
    }

    ptr = ALLOC_N(char, (size_t)capa + termlen);
    oldptr = RSTRING_PTR(str);
    if (oldptr) {
        memcpy(ptr, oldptr, len);
    }
    if (FL_TEST_RAW(str, STR_NOEMBED|STR_NOFREE|STR_SHARED) == STR_NOEMBED) {
        xfree(oldptr);
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
    int termlen = TERM_LEN(str);
    long len = RSTRING_LEN(str);

    if (expand < 0) {
        rb_raise(rb_eArgError, "negative expanding string size");
    }
    if (expand >= LONG_MAX - len) {
        rb_raise(rb_eArgError, "string size too big");
    }

    if (!str_independent(str)) {
        str_make_independent_expand(str, len, expand, termlen);
    }
    else if (expand > 0) {
        RESIZE_CAPA_TERM(str, len + expand, termlen);
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
    if (!enc) {
        rb_raise(rb_eTypeError, "not encoding capable object");
    }
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
    /* This function assumes that (capa + termlen) bytes of memory
     * is allocated, like many other functions in this file.
     */
    if (str_dependent_p(str)) {
        if (!zero_filled(s + len, termlen))
            str_make_independent_expand(str, len, 0L, termlen);
    }
    else {
        TERM_FILL(s + len, termlen);
        return s;
    }
    return RSTRING_PTR(str);
}

void
rb_str_change_terminator_length(VALUE str, const int oldtermlen, const int termlen)
{
    long capa = str_capacity(str, oldtermlen) + oldtermlen;
    long len = RSTRING_LEN(str);

    assert(capa >= len);
    if (capa - len < termlen) {
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
            RSTRING(str)->as.heap.aux.capa = capa - termlen;
        }
        if (termlen > oldtermlen) {
            TERM_FILL(RSTRING_PTR(str) + len, termlen);
        }
    }

    return;
}

static char *
str_null_check(VALUE str, int *w)
{
    char *s = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);
    rb_encoding *enc = rb_enc_get(str);
    const int minlen = rb_enc_mbminlen(enc);

    if (minlen > 1) {
        *w = 1;
        if (str_null_char(s, len, minlen, enc)) {
            return NULL;
        }
        return str_fill_term(str, s, len, minlen);
    }
    *w = 0;
    if (!s || memchr(s, 0, len)) {
        return NULL;
    }
    if (s[len]) {
        s = str_fill_term(str, s, len, minlen);
    }
    return s;
}

char *
rb_str_to_cstr(VALUE str)
{
    int w;
    return str_null_check(str, &w);
}

char *
rb_string_value_cstr(volatile VALUE *ptr)
{
    VALUE str = rb_string_value(ptr);
    int w;
    char *s = str_null_check(str, &w);
    if (!s) {
        if (w) {
            rb_raise(rb_eArgError, "string contains null char");
        }
        rb_raise(rb_eArgError, "string contains null byte");
    }
    return s;
}

char *
rb_str_fill_terminator(VALUE str, const int newminlen)
{
    char *s = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);
    return str_fill_term(str, s, len, newminlen);
}

VALUE
rb_check_string_type(VALUE str)
{
    str = rb_check_convert_type_with_id(str, T_STRING, "String", idTo_str);
    return str;
}

/*
 *  call-seq:
 *    String.try_convert(object) -> object, new_string, or nil
 *
 *  If +object+ is a \String object, returns +object+.
 *
 *  Otherwise if +object+ responds to <tt>:to_str</tt>,
 *  calls <tt>object.to_str</tt> and returns the result.
 *
 *  Returns +nil+ if +object+ does not respond to <tt>:to_str</tt>.
 *
 *  Raises an exception unless <tt>object.to_str</tt> returns a \String object.
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

static VALUE
str_subseq(VALUE str, long beg, long len)
{
    VALUE str2;

    const long rstring_embed_capa_max = ((sizeof(struct RString) - offsetof(struct RString, as.embed.ary)) / sizeof(char)) - 1;

    if (!SHARABLE_SUBSTRING_P(beg, len, RSTRING_LEN(str)) ||
            len <= rstring_embed_capa_max) {
        str2 = rb_str_new(RSTRING_PTR(str) + beg, len);
        RB_GC_GUARD(str);
    }
    else {
        str2 = str_new_shared(rb_cString, str);
        ENC_CODERANGE_CLEAR(str2);
        RSTRING(str2)->as.heap.ptr += beg;
        if (RSTRING(str2)->as.heap.len > len) {
            RSTRING(str2)->as.heap.len = len;
        }
    }

    return str2;
}

VALUE
rb_str_subseq(VALUE str, long beg, long len)
{
    VALUE str2 = str_subseq(str, beg, len);
    rb_enc_cr_str_copy_for_substr(str2, str);
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
        if (len > blen - beg)
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

static VALUE str_substr(VALUE str, long beg, long len, int empty);

VALUE
rb_str_substr(VALUE str, long beg, long len)
{
    return str_substr(str, beg, len, TRUE);
}

static VALUE
str_substr(VALUE str, long beg, long len, int empty)
{
    char *p = rb_str_subpos(str, beg, &len);

    if (!p) return Qnil;
    if (!len && !empty) return Qnil;

    beg = p - RSTRING_PTR(str);

    VALUE str2 = str_subseq(str, beg, len);
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
 *   +string -> new_string or self
 *
 * Returns +self+ if +self+ is not frozen.
 *
 * Otherwise returns <tt>self.dup</tt>, which is not frozen.
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
 *   -string -> frozen_string
 *
 * Returns a frozen, possibly pre-existing copy of the string.
 *
 * The returned \String will be deduplicated as long as it does not have
 * any instance variables set on it and is not a String subclass.
 *
 * String#dedup is an alias for String#-@.
 */
static VALUE
str_uminus(VALUE str)
{
    if (!BARE_STRING_P(str) && !rb_obj_frozen_p(str)) {
        str = rb_str_dup(str);
    }
    return rb_fstring(str);
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
    if (len > (capa = (long)str_capacity(str, termlen)) || len < 0) {
        rb_bug("probable buffer overflow: %ld for %ld", len, capa);
    }

    int cr = ENC_CODERANGE(str);
    if (cr == ENC_CODERANGE_UNKNOWN) {
        /* Leave unknown. */
    }
    else if (len > RSTRING_LEN(str)) {
        if (ENC_CODERANGE_CLEAN_P(cr)) {
            /* Update the coderange regarding the extended part. */
            const char *const prev_end = RSTRING_END(str);
            const char *const new_end = RSTRING_PTR(str) + len;
            rb_encoding *enc = rb_enc_get(str);
            rb_str_coderange_scan_restartable(prev_end, new_end, enc, &cr);
            ENC_CODERANGE_SET(str, cr);
        }
        else if (cr == ENC_CODERANGE_BROKEN) {
            /* May be valid now, by appended part. */
            ENC_CODERANGE_SET(str, ENC_CODERANGE_UNKNOWN);
        }
    }
    else if (len < RSTRING_LEN(str)) {
        if (cr != ENC_CODERANGE_7BIT) {
            /* ASCII-only string is keeping after truncated.  Valid
             * and broken may be invalid or valid, leave unknown. */
            ENC_CODERANGE_SET(str, ENC_CODERANGE_UNKNOWN);
        }
    }

    STR_SET_LEN(str, len);
    TERM_FILL(&RSTRING_PTR(str)[len], termlen);
}

VALUE
rb_str_resize(VALUE str, long len)
{
    if (len < 0) {
        rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    int independent = str_independent(str);
    long slen = RSTRING_LEN(str);

    if (slen > len && ENC_CODERANGE(str) != ENC_CODERANGE_7BIT) {
        ENC_CODERANGE_CLEAR(str);
    }

    {
        long capa;
        const int termlen = TERM_LEN(str);
        if (STR_EMBED_P(str)) {
            if (len == slen) return str;
            if (str_embed_capa(str) >= len + termlen) {
                STR_SET_EMBED_LEN(str, len);
                TERM_FILL(RSTRING(str)->as.embed.ary + len, termlen);
                return str;
            }
            str_make_independent_expand(str, slen, len - slen, termlen);
        }
        else if (str_embed_capa(str) >= len + termlen) {
            char *ptr = STR_HEAP_PTR(str);
            STR_SET_EMBED(str);
            if (slen > len) slen = len;
            if (slen > 0) MEMCPY(RSTRING(str)->as.embed.ary, ptr, char, slen);
            TERM_FILL(RSTRING(str)->as.embed.ary + len, termlen);
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
            SIZED_REALLOC_N(RSTRING(str)->as.heap.ptr, char,
                            (size_t)len + termlen, STR_HEAP_SIZE(str));
            RSTRING(str)->as.heap.aux.capa = len;
        }
        else if (len == slen) return str;
        RSTRING(str)->as.heap.len = len;
        TERM_FILL(RSTRING(str)->as.heap.ptr + len, termlen); /* sentinel */
    }
    return str;
}

static VALUE
str_buf_cat4(VALUE str, const char *ptr, long len, bool keep_cr)
{
    if (keep_cr) {
        str_modify_keep_cr(str);
    }
    else {
        rb_str_modify(str);
    }
    if (len == 0) return 0;

    long capa, total, olen, off = -1;
    char *sptr;
    const int termlen = TERM_LEN(str);
#if !USE_RVARGC
    assert(termlen < RSTRING_EMBED_LEN_MAX + 1); /* < (LONG_MAX/2) */
#endif

    RSTRING_GETMEM(str, sptr, olen);
    if (ptr >= sptr && ptr <= sptr + olen) {
        off = ptr - sptr;
    }

    if (STR_EMBED_P(str)) {
        capa = str_embed_capa(str) - termlen;
        sptr = RSTRING(str)->as.embed.ary;
        olen = RSTRING_EMBED_LEN(str);
    }
    else {
        capa = RSTRING(str)->as.heap.aux.capa;
        sptr = RSTRING(str)->as.heap.ptr;
        olen = RSTRING(str)->as.heap.len;
    }
    if (olen > LONG_MAX - len) {
        rb_raise(rb_eArgError, "string sizes too big");
    }
    total = olen + len;
    if (capa < total) {
        if (total >= LONG_MAX / 2) {
            capa = total;
        }
        while (total > capa) {
            capa = 2 * capa + termlen; /* == 2*(capa+termlen)-termlen */
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

#define str_buf_cat(str, ptr, len) str_buf_cat4((str), (ptr), len, false)
#define str_buf_cat2(str, ptr) str_buf_cat4((str), (ptr), rb_strlen_lit(ptr), false)

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
                rb_str_change_terminator_length(str, rb_enc_mbminlen(str_enc), rb_enc_mbminlen(ptr_enc));
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
        goto incompatible;
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

  incompatible:
    rb_raise(rb_eEncCompatError, "incompatible character encodings: %s and %s",
             rb_enc_name(str_enc), rb_enc_name(ptr_enc));
    UNREACHABLE_RETURN(Qundef);
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
    int str2_cr = rb_enc_str_coderange(str2);

    if (str_enc_fastpath(str)) {
        switch (str2_cr) {
          case ENC_CODERANGE_7BIT:
            // If RHS is 7bit we can do simple concatenation
            str_buf_cat4(str, RSTRING_PTR(str2), RSTRING_LEN(str2), true);
            RB_GC_GUARD(str2);
            return str;
          case ENC_CODERANGE_VALID:
            // If RHS is valid, we can do simple concatenation if encodings are the same
            if (ENCODING_GET_INLINED(str) == ENCODING_GET_INLINED(str2)) {
                str_buf_cat4(str, RSTRING_PTR(str2), RSTRING_LEN(str2), true);
                int str_cr = ENC_CODERANGE(str);
                if (UNLIKELY(str_cr != ENC_CODERANGE_VALID)) {
                    ENC_CODERANGE_SET(str, RB_ENC_CODERANGE_AND(str_cr, str2_cr));
                }
                RB_GC_GUARD(str2);
                return str;
            }
        }
    }

    rb_enc_cr_str_buf_cat(str, RSTRING_PTR(str2), RSTRING_LEN(str2),
        ENCODING_GET(str2), str2_cr, &str2_cr);

    ENC_CODERANGE_SET(str2, str2_cr);

    return str;
}

VALUE
rb_str_append(VALUE str, VALUE str2)
{
    StringValue(str2);
    return rb_str_buf_append(str, str2);
}

#define MIN_PRE_ALLOC_SIZE 48

MJIT_FUNC_EXPORTED VALUE
rb_str_concat_literals(size_t num, const VALUE *strary)
{
    VALUE str;
    size_t i, s;
    long len = 1;

    if (UNLIKELY(!num)) return rb_str_new(0, 0);
    if (UNLIKELY(num == 1)) return rb_str_resurrect(strary[0]);

    for (i = 0; i < num; ++i) { len += RSTRING_LEN(strary[i]); }
    if (LIKELY(len < MIN_PRE_ALLOC_SIZE)) {
        str = rb_str_resurrect(strary[0]);
        s = 1;
    }
    else {
        str = rb_str_buf_new(len);
        rb_enc_copy(str, strary[0]);
        s = 0;
    }

    for (i = s; i < num; ++i) {
        const VALUE v = strary[i];
        int encidx = ENCODING_GET(v);

        rb_str_buf_append(str, v);
        if (encidx != ENCINDEX_US_ASCII) {
            if (ENCODING_GET_INLINED(str) == ENCINDEX_US_ASCII)
                rb_enc_set_index(str, encidx);
        }
    }
    return str;
}

/*
 *  call-seq:
 *     concat(*objects) -> string
 *
 *  Concatenates each object in +objects+ to +self+ and returns +self+:
 *
 *    s = 'foo'
 *    s.concat('bar', 'baz') # => "foobarbaz"
 *    s                      # => "foobarbaz"
 *
 *  For each given object +object+ that is an \Integer,
 *  the value is considered a codepoint and converted to a character before concatenation:
 *
 *    s = 'foo'
 *    s.concat(32, 'bar', 32, 'baz') # => "foo bar baz"
 *
 *  Related: String#<<, which takes a single argument.
 */
static VALUE
rb_str_concat_multi(int argc, VALUE *argv, VALUE str)
{
    str_modifiable(str);

    if (argc == 1) {
        return rb_str_concat(str, argv[0]);
    }
    else if (argc > 1) {
        int i;
        VALUE arg_str = rb_str_tmp_new(0);
        rb_enc_copy(arg_str, str);
        for (i = 0; i < argc; i++) {
            rb_str_concat(arg_str, argv[i]);
        }
        rb_str_buf_append(str, arg_str);
    }

    return str;
}

/*
 *  call-seq:
 *    string << object -> string
 *
 *  Concatenates +object+ to +self+ and returns +self+:
 *
 *    s = 'foo'
 *    s << 'bar' # => "foobar"
 *    s          # => "foobar"
 *
 *  If +object+ is an \Integer,
 *  the value is considered a codepoint and converted to a character before concatenation:
 *
 *    s = 'foo'
 *    s << 33 # => "foo!"
 *
 *  Related: String#concat, which takes multiple arguments.
 */
VALUE
rb_str_concat(VALUE str1, VALUE str2)
{
    unsigned int code;
    rb_encoding *enc = STR_ENC_GET(str1);
    int encidx;

    if (RB_INTEGER_TYPE_P(str2)) {
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

    encidx = rb_ascii8bit_appendable_encoding_index(enc, code);
    if (encidx >= 0) {
        char buf[1];
        buf[0] = (char)code;
        rb_str_cat(str1, buf, 1);
        if (encidx != rb_enc_to_index(enc)) {
            rb_enc_associate_index(str1, encidx);
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
        if (cr == ENC_CODERANGE_7BIT && code > 127) {
            cr = ENC_CODERANGE_VALID;
        }
        else if (cr == ENC_CODERANGE_BROKEN) {
            cr = ENC_CODERANGE_UNKNOWN;
        }
        ENC_CODERANGE_SET(str1, cr);
    }
    return str1;
}

int
rb_ascii8bit_appendable_encoding_index(rb_encoding *enc, unsigned int code)
{
    int encidx = rb_enc_to_index(enc);

    if (encidx == ENCINDEX_ASCII_8BIT || encidx == ENCINDEX_US_ASCII) {
        /* US-ASCII automatically extended to ASCII-8BIT */
        if (code > 0xFF) {
            rb_raise(rb_eRangeError, "%u out of char range", code);
        }
        if (encidx == ENCINDEX_US_ASCII && code > 127) {
            return ENCINDEX_ASCII_8BIT;
        }
        return encidx;
    }
    else {
        return -1;
    }
}

/*
 *  call-seq:
 *    prepend(*other_strings)  -> string
 *
 *  Prepends each string in +other_strings+ to +self+ and returns +self+:
 *
 *    s = 'foo'
 *    s.prepend('bar', 'baz') # => "barbazfoo"
 *    s                       # => "barbazfoo"
 *
 *  Related: String#concat.
 */

static VALUE
rb_str_prepend_multi(int argc, VALUE *argv, VALUE str)
{
    str_modifiable(str);

    if (argc == 1) {
        rb_str_update(str, 0L, 0L, argv[0]);
    }
    else if (argc > 1) {
        int i;
        VALUE arg_str = rb_str_tmp_new(0);
        rb_enc_copy(arg_str, str);
        for (i = 0; i < argc; i++) {
            rb_str_append(arg_str, argv[i]);
        }
        rb_str_update(str, 0L, 0L, arg_str);
    }

    return str;
}

st_index_t
rb_str_hash(VALUE str)
{
    int e = ENCODING_GET(str);
    if (e && is_ascii_string(str)) {
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
 *   hash -> integer
 *
 * Returns the integer hash value for +self+.
 * The value is based on the length, content and encoding of +self+.
 *
 * Related: Object#hash.
 */

static VALUE
rb_str_hash_m(VALUE str)
{
    st_index_t hval = rb_str_hash(str);
    return ST2FIX(hval);
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

/*
 *  call-seq:
 *    string == object -> true or false
 *    string === object -> true or false
 *
 *  Returns +true+ if +object+ has the same length and content;
 *  as +self+; +false+ otherwise:
 *
 *    s = 'foo'
 *    s == 'foo' # => true
 *    s == 'food' # => false
 *    s == 'FOO' # => false
 *
 *  Returns +false+ if the two strings' encodings are not compatible:
 *    "\u{e4 f6 fc}".encode("ISO-8859-1") == ("\u{c4 d6 dc}") # => false
 *
 *  If +object+ is not an instance of \String but responds to +to_str+, then the
 *  two strings are compared using <code>object.==</code>.
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
    return rb_str_eql_internal(str1, str2);
}

/*
 * call-seq:
 *   eql?(object) -> true or false
 *
 *  Returns +true+ if +object+ has the same length and content;
 *  as +self+; +false+ otherwise:
 *
 *    s = 'foo'
 *    s.eql?('foo') # => true
 *    s.eql?('food') # => false
 *    s.eql?('FOO') # => false
 *
 *  Returns +false+ if the two strings' encodings are not compatible:
 *
 *    "\u{e4 f6 fc}".encode("ISO-8859-1").eql?("\u{c4 d6 dc}") # => false
 *
 */

MJIT_FUNC_EXPORTED VALUE
rb_str_eql(VALUE str1, VALUE str2)
{
    if (str1 == str2) return Qtrue;
    if (!RB_TYPE_P(str2, T_STRING)) return Qfalse;
    return rb_str_eql_internal(str1, str2);
}

/*
 *  call-seq:
 *    string <=> other_string -> -1, 0, 1, or nil
 *
 *  Compares +self+ and +other_string+, returning:
 *
 *  - -1 if +other_string+ is larger.
 *  - 0 if the two are equal.
 *  - 1 if +other_string+ is smaller.
 *  - +nil+ if the two are incomparable.
 *
 *  Examples:
 *
 *    'foo' <=> 'foo' # => 0
 *    'foo' <=> 'food' # => -1
 *    'food' <=> 'foo' # => 1
 *    'FOO' <=> 'foo' # => -1
 *    'foo' <=> 'FOO' # => 1
 *    'foo' <=> 1 # => nil
 *
 */

static VALUE
rb_str_cmp_m(VALUE str1, VALUE str2)
{
    int result;
    VALUE s = rb_check_string_type(str2);
    if (NIL_P(s)) {
        return rb_invcmp(str1, str2);
    }
    result = rb_str_cmp(str1, s);
    return INT2FIX(result);
}

static VALUE str_casecmp(VALUE str1, VALUE str2);
static VALUE str_casecmp_p(VALUE str1, VALUE str2);

/*
 *  call-seq:
 *    casecmp(other_string) -> -1, 0, 1, or nil
 *
 *  Compares <tt>self.downcase</tt> and <tt>other_string.downcase</tt>; returns:
 *
 *  - -1 if <tt>other_string.downcase</tt> is larger.
 *  - 0 if the two are equal.
 *  - 1 if <tt>other_string.downcase</tt> is smaller.
 *  - +nil+ if the two are incomparable.
 *
 *  Examples:
 *
 *    'foo'.casecmp('foo') # => 0
 *    'foo'.casecmp('food') # => -1
 *    'food'.casecmp('foo') # => 1
 *    'FOO'.casecmp('foo') # => 0
 *    'foo'.casecmp('FOO') # => 0
 *    'foo'.casecmp(1) # => nil
 *
 *  See {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#casecmp?.
 *
 */

static VALUE
rb_str_casecmp(VALUE str1, VALUE str2)
{
    VALUE s = rb_check_string_type(str2);
    if (NIL_P(s)) {
        return Qnil;
    }
    return str_casecmp(str1, s);
}

static VALUE
str_casecmp(VALUE str1, VALUE str2)
{
    long len;
    rb_encoding *enc;
    const char *p1, *p1end, *p2, *p2end;

    enc = rb_enc_compatible(str1, str2);
    if (!enc) {
        return Qnil;
    }

    p1 = RSTRING_PTR(str1); p1end = RSTRING_END(str1);
    p2 = RSTRING_PTR(str2); p2end = RSTRING_END(str2);
    if (single_byte_optimizable(str1) && single_byte_optimizable(str2)) {
        while (p1 < p1end && p2 < p2end) {
            if (*p1 != *p2) {
                unsigned int c1 = TOLOWER(*p1 & 0xff);
                unsigned int c2 = TOLOWER(*p2 & 0xff);
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
                c1 = TOLOWER(c1);
                c2 = TOLOWER(c2);
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

/*
 *  call-seq:
 *    casecmp?(other_string) -> true, false, or nil
 *
 *  Returns +true+ if +self+ and +other_string+ are equal after
 *  Unicode case folding, otherwise +false+:
 *
 *    'foo'.casecmp?('foo') # => true
 *    'foo'.casecmp?('food') # => false
 *    'food'.casecmp?('foo') # => false
 *    'FOO'.casecmp?('foo') # => true
 *    'foo'.casecmp?('FOO') # => true
 *
 *  Returns +nil+ if the two values are incomparable:
 *
 *    'foo'.casecmp?(1) # => nil
 *
 *  See {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#casecmp.
 *
 */

static VALUE
rb_str_casecmp_p(VALUE str1, VALUE str2)
{
    VALUE s = rb_check_string_type(str2);
    if (NIL_P(s)) {
        return Qnil;
    }
    return str_casecmp_p(str1, s);
}

static VALUE
str_casecmp_p(VALUE str1, VALUE str2)
{
    rb_encoding *enc;
    VALUE folded_str1, folded_str2;
    VALUE fold_opt = sym_fold;

    enc = rb_enc_compatible(str1, str2);
    if (!enc) {
        return Qnil;
    }

    folded_str1 = rb_str_downcase(1, &fold_opt, str1);
    folded_str2 = rb_str_downcase(1, &fold_opt, str2);

    return rb_str_eql(folded_str1, folded_str2);
}

static long
strseq_core(const char *str_ptr, const char *str_ptr_end, long str_len,
            const char *sub_ptr, long sub_len, long offset, rb_encoding *enc)
{
    const char *search_start = str_ptr;
    long pos, search_len = str_len - offset;

    for (;;) {
        const char *t;
        pos = rb_memsearch(sub_ptr, sub_len, search_start, search_len, enc);
        if (pos < 0) return pos;
        t = rb_enc_right_char_head(search_start, search_start+pos, str_ptr_end, enc);
        if (t == search_start + pos) break;
        search_len -= t - search_start;
        if (search_len <= 0) return -1;
        offset += t - search_start;
        search_start = t;
    }
    return pos + offset;
}

#define rb_str_index(str, sub, offset) rb_strseq_index(str, sub, offset, 0)

static long
rb_strseq_index(VALUE str, VALUE sub, long offset, int in_byte)
{
    const char *str_ptr, *str_ptr_end, *sub_ptr;
    long str_len, sub_len;
    rb_encoding *enc;

    enc = rb_enc_check(str, sub);
    if (is_broken_string(sub)) return -1;

    str_ptr = RSTRING_PTR(str);
    str_ptr_end = RSTRING_END(str);
    str_len = RSTRING_LEN(str);
    sub_ptr = RSTRING_PTR(sub);
    sub_len = RSTRING_LEN(sub);

    if (str_len < sub_len) return -1;

    if (offset != 0) {
        long str_len_char, sub_len_char;
        int single_byte = single_byte_optimizable(str);
        str_len_char = (in_byte || single_byte) ? str_len : str_strlen(str, enc);
        sub_len_char = in_byte ? sub_len : str_strlen(sub, enc);
        if (offset < 0) {
            offset += str_len_char;
            if (offset < 0) return -1;
        }
        if (str_len_char - offset < sub_len_char) return -1;
        if (!in_byte) offset = str_offset(str_ptr, str_ptr_end, offset, enc, single_byte);
        str_ptr += offset;
    }
    if (sub_len == 0) return offset;

    /* need proceed one character at a time */
    return strseq_core(str_ptr, str_ptr_end, str_len, sub_ptr, sub_len, offset, enc);
}


/*
 *  call-seq:
 *    index(substring, offset = 0) -> integer or nil
 *    index(regexp, offset = 0) -> integer or nil
 *
 *  :include: doc/string/index.rdoc
 *
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

    if (RB_TYPE_P(sub, T_REGEXP)) {
        if (pos > str_strlen(str, NULL)) {
            rb_backref_set(Qnil);
            return Qnil;
        }
        pos = str_offset(RSTRING_PTR(str), RSTRING_END(str), pos,
                         rb_enc_check(str, sub), single_byte_optimizable(str));

        if (rb_reg_search(sub, str, pos, 0) < 0) {
            return Qnil;
        }
        else {
            VALUE match = rb_backref_get();
            struct re_registers *regs = RMATCH_REGS(match);
            pos = rb_str_sublen(str, BEG(0));
            return LONG2NUM(pos);
        }
    }
    else {
        StringValue(sub);
        pos = rb_str_index(str, sub, pos);
        pos = rb_str_sublen(str, pos);
    }

    if (pos == -1) return Qnil;
    return LONG2NUM(pos);
}

/* whether given pos is valid character boundary or not
 * Note that in this function, "character" means a code point
 * (Unicode scalar value), not a grapheme cluster.
 */
static bool
str_check_byte_pos(VALUE str, long pos)
{
    const char *s = RSTRING_PTR(str);
    const char *e = RSTRING_END(str);
    const char *p = s + pos;
    const char *pp = rb_enc_left_char_head(s, p, e, rb_enc_get(str));
    return p == pp;
}

/*
 *  call-seq:
 *    byteindex(substring, offset = 0) -> integer or nil
 *    byteindex(regexp, offset = 0) -> integer or nil
 *
 *  Returns the \Integer byte-based index of the first occurrence of the given +substring+,
 *  or +nil+ if none found:
 *
 *    'foo'.byteindex('f') # => 0
 *    'foo'.byteindex('o') # => 1
 *    'foo'.byteindex('oo') # => 1
 *    'foo'.byteindex('ooo') # => nil
 *
 *  Returns the \Integer byte-based index of the first match for the given \Regexp +regexp+,
 *  or +nil+ if none found:
 *
 *    'foo'.byteindex(/f/) # => 0
 *    'foo'.byteindex(/o/) # => 1
 *    'foo'.byteindex(/oo/) # => 1
 *    'foo'.byteindex(/ooo/) # => nil
 *
 *  \Integer argument +offset+, if given, specifies the byte-based position in the
 *  string to begin the search:
 *
 *    'foo'.byteindex('o', 1) # => 1
 *    'foo'.byteindex('o', 2) # => 2
 *    'foo'.byteindex('o', 3) # => nil
 *
 *  If +offset+ is negative, counts backward from the end of +self+:
 *
 *    'foo'.byteindex('o', -1) # => 2
 *    'foo'.byteindex('o', -2) # => 1
 *    'foo'.byteindex('o', -3) # => 1
 *    'foo'.byteindex('o', -4) # => nil
 *
 *  If +offset+ does not land on character (codepoint) boundary, +IndexError+ is
 *  raised.
 *
 *  Related: String#index, String#byterindex.
 */

static VALUE
rb_str_byteindex_m(int argc, VALUE *argv, VALUE str)
{
    VALUE sub;
    VALUE initpos;
    long pos;

    if (rb_scan_args(argc, argv, "11", &sub, &initpos) == 2) {
        long slen = RSTRING_LEN(str);
        pos = NUM2LONG(initpos);
        if (pos < 0) {
            pos += slen;
        }
        if (pos < 0 || pos > slen) {
            if (RB_TYPE_P(sub, T_REGEXP)) {
                rb_backref_set(Qnil);
            }
            return Qnil;
        }
    }
    else {
        pos = 0;
    }

    if (!str_check_byte_pos(str, pos)) {
        rb_raise(rb_eIndexError,
                 "offset %ld does not land on character boundary", pos);
    }

    if (RB_TYPE_P(sub, T_REGEXP)) {
        if (rb_reg_search(sub, str, pos, 0) < 0) {
            return Qnil;
        }
        else {
            VALUE match = rb_backref_get();
            struct re_registers *regs = RMATCH_REGS(match);
            pos = BEG(0);
            return LONG2NUM(pos);
        }
    }
    else {
        StringValue(sub);
        pos = rb_strseq_index(str, sub, pos, 1);
    }

    if (pos == -1) return Qnil;
    return LONG2NUM(pos);
}

#ifdef HAVE_MEMRCHR
static long
str_rindex(VALUE str, VALUE sub, const char *s, rb_encoding *enc)
{
    char *hit, *adjusted;
    int c;
    long slen, searchlen;
    char *sbeg, *e, *t;

    sbeg = RSTRING_PTR(str);
    slen = RSTRING_LEN(sub);
    if (slen == 0) return s - sbeg;
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
            return hit - sbeg;
        searchlen = adjusted - sbeg;
    } while (searchlen > 0);

    return -1;
}
#else
static long
str_rindex(VALUE str, VALUE sub, const char *s, rb_encoding *enc)
{
    long slen;
    char *sbeg, *e, *t;

    sbeg = RSTRING_PTR(str);
    e = RSTRING_END(str);
    t = RSTRING_PTR(sub);
    slen = RSTRING_LEN(sub);

    while (s) {
        if (memcmp(s, t, slen) == 0) {
            return s - sbeg;
        }
        if (s <= sbeg) break;
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
    return rb_str_sublen(str, str_rindex(str, sub, s, enc));
}

/*
 *  call-seq:
 *    rindex(substring, offset = self.length) -> integer or nil
 *    rindex(regexp, offset = self.length) -> integer or nil
 *
 *  Returns the \Integer index of the _last_ occurrence of the given +substring+,
 *  or +nil+ if none found:
 *
 *    'foo'.rindex('f') # => 0
 *    'foo'.rindex('o') # => 2
 *    'foo'.rindex('oo') # => 1
 *    'foo'.rindex('ooo') # => nil
 *
 *  Returns the \Integer index of the _last_ match for the given \Regexp +regexp+,
 *  or +nil+ if none found:
 *
 *    'foo'.rindex(/f/) # => 0
 *    'foo'.rindex(/o/) # => 2
 *    'foo'.rindex(/oo/) # => 1
 *    'foo'.rindex(/ooo/) # => nil
 *
 *  The _last_ match means starting at the possible last position, not
 *  the last of longest matches.
 *
 *    'foo'.rindex(/o+/) # => 2
 *    $~ #=> #<MatchData "o">
 *
 *  To get the last longest match, needs to combine with negative
 *  lookbehind.
 *
 *    'foo'.rindex(/(?<!o)o+/) # => 1
 *    $~ #=> #<MatchData "oo">
 *
 *  Or String#index with negative lookforward.
 *
 *    'foo'.index(/o+(?!.*o)/) # => 1
 *    $~ #=> #<MatchData "oo">
 *
 *  \Integer argument +offset+, if given and non-negative, specifies the maximum starting position in the
 *   string to _end_ the search:
 *
 *    'foo'.rindex('o', 0) # => nil
 *    'foo'.rindex('o', 1) # => 1
 *    'foo'.rindex('o', 2) # => 2
 *    'foo'.rindex('o', 3) # => 2
 *
 *  If +offset+ is a negative \Integer, the maximum starting position in the
 *  string to _end_ the search is the sum of the string's length and +offset+:
 *
 *    'foo'.rindex('o', -1) # => 2
 *    'foo'.rindex('o', -2) # => 1
 *    'foo'.rindex('o', -3) # => nil
 *    'foo'.rindex('o', -4) # => nil
 *
 *  Related: String#index.
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

    if (RB_TYPE_P(sub, T_REGEXP)) {
        /* enc = rb_get_check(str, sub); */
        pos = str_offset(RSTRING_PTR(str), RSTRING_END(str), pos,
                         enc, single_byte_optimizable(str));

        if (rb_reg_search(sub, str, pos, 1) >= 0) {
            VALUE match = rb_backref_get();
            struct re_registers *regs = RMATCH_REGS(match);
            pos = rb_str_sublen(str, BEG(0));
            return LONG2NUM(pos);
        }
    }
    else {
        StringValue(sub);
        pos = rb_str_rindex(str, sub, pos);
        if (pos >= 0) return LONG2NUM(pos);
    }
    return Qnil;
}

static long
rb_str_byterindex(VALUE str, VALUE sub, long pos)
{
    long len, slen;
    char *sbeg, *s;
    rb_encoding *enc;

    enc = rb_enc_check(str, sub);
    if (is_broken_string(sub)) return -1;
    len = RSTRING_LEN(str);
    slen = RSTRING_LEN(sub);

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

    s = sbeg + pos;
    return str_rindex(str, sub, s, enc);
}


/*
 *  call-seq:
 *    byterindex(substring, offset = self.bytesize) -> integer or nil
 *    byterindex(regexp, offset = self.bytesize) -> integer or nil
 *
 *  Returns the \Integer byte-based index of the _last_ occurrence of the given +substring+,
 *  or +nil+ if none found:
 *
 *    'foo'.byterindex('f') # => 0
 *    'foo'.byterindex('o') # => 2
 *    'foo'.byterindex('oo') # => 1
 *    'foo'.byterindex('ooo') # => nil
 *
 *  Returns the \Integer byte-based index of the _last_ match for the given \Regexp +regexp+,
 *  or +nil+ if none found:
 *
 *    'foo'.byterindex(/f/) # => 0
 *    'foo'.byterindex(/o/) # => 2
 *    'foo'.byterindex(/oo/) # => 1
 *    'foo'.byterindex(/ooo/) # => nil
 *
 *  The _last_ match means starting at the possible last position, not
 *  the last of longest matches.
 *
 *    'foo'.byterindex(/o+/) # => 2
 *    $~ #=> #<MatchData "o">
 *
 *  To get the last longest match, needs to combine with negative
 *  lookbehind.
 *
 *    'foo'.byterindex(/(?<!o)o+/) # => 1
 *    $~ #=> #<MatchData "oo">
 *
 *  Or String#byteindex with negative lookforward.
 *
 *    'foo'.byteindex(/o+(?!.*o)/) # => 1
 *    $~ #=> #<MatchData "oo">
 *
 *  \Integer argument +offset+, if given and non-negative, specifies the maximum starting byte-based position in the
 *   string to _end_ the search:
 *
 *    'foo'.byterindex('o', 0) # => nil
 *    'foo'.byterindex('o', 1) # => 1
 *    'foo'.byterindex('o', 2) # => 2
 *    'foo'.byterindex('o', 3) # => 2
 *
 *  If +offset+ is a negative \Integer, the maximum starting position in the
 *  string to _end_ the search is the sum of the string's length and +offset+:
 *
 *    'foo'.byterindex('o', -1) # => 2
 *    'foo'.byterindex('o', -2) # => 1
 *    'foo'.byterindex('o', -3) # => nil
 *    'foo'.byterindex('o', -4) # => nil
 *
 *  If +offset+ does not land on character (codepoint) boundary, +IndexError+ is
 *  raised.
 *
 *  Related: String#byteindex.
 */

static VALUE
rb_str_byterindex_m(int argc, VALUE *argv, VALUE str)
{
    VALUE sub;
    VALUE vpos;
    long pos, len = RSTRING_LEN(str);

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

    if (!str_check_byte_pos(str, pos)) {
        rb_raise(rb_eIndexError,
                 "offset %ld does not land on character boundary", pos);
    }

    if (RB_TYPE_P(sub, T_REGEXP)) {
        if (rb_reg_search(sub, str, pos, 1) >= 0) {
            VALUE match = rb_backref_get();
            struct re_registers *regs = RMATCH_REGS(match);
            pos = BEG(0);
            return LONG2NUM(pos);
        }
    }
    else {
        StringValue(sub);
        pos = rb_str_byterindex(str, sub, pos);
        if (pos >= 0) return LONG2NUM(pos);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    string =~ regexp -> integer or nil
 *    string =~ object -> integer or nil
 *
 *  Returns the \Integer index of the first substring that matches
 *  the given +regexp+, or +nil+ if no match found:
 *
 *    'foo' =~ /f/ # => 0
 *    'foo' =~ /o/ # => 1
 *    'foo' =~ /x/ # => nil
 *
 *  Note: also updates Regexp@Special+global+variables.
 *
 *  If the given +object+ is not a \Regexp, returns the value
 *  returned by <tt>object =~ self</tt>.
 *
 *  Note that <tt>string =~ regexp</tt> is different from <tt>regexp =~ string</tt>
 *  (see Regexp#=~):
 *
 *    number= nil
 *    "no. 9" =~ /(?<number>\d+)/
 *    number # => nil (not assigned)
 *    /(?<number>\d+)/ =~ "no. 9"
 *    number #=> "9"
 *
 */

static VALUE
rb_str_match(VALUE x, VALUE y)
{
    switch (OBJ_BUILTIN_TYPE(y)) {
      case T_STRING:
        rb_raise(rb_eTypeError, "type mismatch: String given");

      case T_REGEXP:
        return rb_reg_match(y, x);

      default:
        return rb_funcall(y, idEqTilde, 1, x);
    }
}


static VALUE get_pat(VALUE);


/*
 *  call-seq:
 *    match(pattern, offset = 0) -> matchdata or nil
 *    match(pattern, offset = 0) {|matchdata| ... } -> object
 *
 *  Returns a \MatchData object (or +nil+) based on +self+ and the given +pattern+.
 *
 *  Note: also updates Regexp@Special+global+variables.
 *
 *  - Computes +regexp+ by converting +pattern+ (if not already a \Regexp).
 *      regexp = Regexp.new(pattern)
 *  - Computes +matchdata+, which will be either a \MatchData object or +nil+
 *    (see Regexp#match):
 *      matchdata = <tt>regexp.match(self)
 *
 *  With no block given, returns the computed +matchdata+:
 *
 *    'foo'.match('f') # => #<MatchData "f">
 *    'foo'.match('o') # => #<MatchData "o">
 *    'foo'.match('x') # => nil
 *
 *  If \Integer argument +offset+ is given, the search begins at index +offset+:
 *
 *    'foo'.match('f', 1) # => nil
 *    'foo'.match('o', 1) # => #<MatchData "o">
 *
 *  With a block given, calls the block with the computed +matchdata+
 *  and returns the block's return value:
 *
 *    'foo'.match(/o/) {|matchdata| matchdata } # => #<MatchData "o">
 *    'foo'.match(/x/) {|matchdata| matchdata } # => nil
 *    'foo'.match(/f/, 1) {|matchdata| matchdata } # => nil
 *
 */

static VALUE
rb_str_match_m(int argc, VALUE *argv, VALUE str)
{
    VALUE re, result;
    if (argc < 1)
        rb_check_arity(argc, 1, 2);
    re = argv[0];
    argv[0] = str;
    result = rb_funcallv(get_pat(re), rb_intern("match"), argc, argv);
    if (!NIL_P(result) && rb_block_given_p()) {
        return rb_yield(result);
    }
    return result;
}

/*
 *  call-seq:
 *    match?(pattern, offset = 0) -> true or false
 *
 *  Returns +true+ or +false+ based on whether a match is found for +self+ and +pattern+.
 *
 *  Note: does not update Regexp@Special+global+variables.
 *
 *  Computes +regexp+ by converting +pattern+ (if not already a \Regexp).
 *    regexp = Regexp.new(pattern)
 *
 *  Returns +true+ if <tt>self+.match(regexp)</tt> returns a \MatchData object,
 *  +false+ otherwise:
 *
 *    'foo'.match?(/o/) # => true
 *    'foo'.match?('o') # => true
 *    'foo'.match?(/x/) # => false
 *
 *  If \Integer argument +offset+ is given, the search begins at index +offset+:
 *    'foo'.match?('f', 1) # => false
 *    'foo'.match?('o', 1) # => true
 *
 */

static VALUE
rb_str_match_m_p(int argc, VALUE *argv, VALUE str)
{
    VALUE re;
    rb_check_arity(argc, 1, 2);
    re = get_pat(argv[0]);
    return rb_reg_match_p(re, str, argc > 1 ? NUM2LONG(argv[1]) : 0);
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
 *    succ -> new_str
 *
 *  Returns the successor to +self+. The successor is calculated by
 *  incrementing characters.
 *
 *  The first character to be incremented is the rightmost alphanumeric:
 *  or, if no alphanumerics, the rightmost character:
 *
 *    'THX1138'.succ # => "THX1139"
 *    '<<koala>>'.succ # => "<<koalb>>"
 *    '***'.succ # => '**+'
 *
 *  The successor to a digit is another digit, "carrying" to the next-left
 *  character for a "rollover" from 9 to 0, and prepending another digit
 *  if necessary:
 *
 *    '00'.succ # => "01"
 *    '09'.succ # => "10"
 *    '99'.succ # => "100"
 *
 *  The successor to a letter is another letter of the same case,
 *  carrying to the next-left character for a rollover,
 *  and prepending another same-case letter if necessary:
 *
 *    'aa'.succ # => "ab"
 *    'az'.succ # => "ba"
 *    'zz'.succ # => "aaa"
 *    'AA'.succ # => "AB"
 *    'AZ'.succ # => "BA"
 *    'ZZ'.succ # => "AAA"
 *
 *  The successor to a non-alphanumeric character is the next character
 *  in the underlying character set's collating sequence,
 *  carrying to the next-left character for a rollover,
 *  and prepending another character if necessary:
 *
 *    s = 0.chr * 3
 *    s # => "\x00\x00\x00"
 *    s.succ # => "\x00\x00\x01"
 *    s = 255.chr * 3
 *    s # => "\xFF\xFF\xFF"
 *    s.succ # => "\x01\x00\x00\x00"
 *
 *  Carrying can occur between and among mixtures of alphanumeric characters:
 *
 *    s = 'zz99zz99'
 *    s.succ # => "aaa00aa00"
 *    s = '99zz99zz'
 *    s.succ # => "100aa00aa"
 *
 *  The successor to an empty \String is a new empty \String:
 *
 *    ''.succ # => ""
 *
 *  String#next is an alias for String#succ.
 */

VALUE
rb_str_succ(VALUE orig)
{
    VALUE str;
    str = rb_str_new(RSTRING_PTR(orig), RSTRING_LEN(orig));
    rb_enc_cr_str_copy_for_substr(str, orig);
    return str_succ(str);
}

static VALUE
str_succ(VALUE str)
{
    rb_encoding *enc;
    char *sbeg, *s, *e, *last_alnum = 0;
    int found_alnum = 0;
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
        found_alnum = 1;
        carry_pos = s - sbeg;
        carry_len = l;
    }
    if (!found_alnum) {		/* str contains no alnum */
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
        ENC_CODERANGE_SET(str, ENC_CODERANGE_UNKNOWN);
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
 *    succ! -> self
 *
 *  Equivalent to String#succ, but modifies +self+ in place; returns +self+.
 *
 *  String#next! is an alias for String#succ!.
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

static int
str_upto_i(VALUE str, VALUE arg)
{
    rb_yield(str);
    return 0;
}

/*
 *  call-seq:
 *    upto(other_string, exclusive = false) {|string| ... } -> self
 *    upto(other_string, exclusive = false) -> new_enumerator
 *
 *  With a block given, calls the block with each \String value
 *  returned by successive calls to String#succ;
 *  the first value is +self+, the next is <tt>self.succ</tt>, and so on;
 *  the sequence terminates when value +other_string+ is reached;
 *  returns +self+:
 *
 *    'a8'.upto('b6') {|s| print s, ' ' } # => "a8"
 *  Output:
 *
 *    a8 a9 b0 b1 b2 b3 b4 b5 b6
 *
 *  If argument +exclusive+ is given as a truthy object, the last value is omitted:
 *
 *    'a8'.upto('b6', true) {|s| print s, ' ' } # => "a8"
 *
 *  Output:
 *
 *    a8 a9 b0 b1 b2 b3 b4 b5
 *
 *  If +other_string+ would not be reached, does not call the block:
 *
 *    '25'.upto('5') {|s| fail s }
 *    'aa'.upto('a') {|s| fail s }
 *
 *  With no block given, returns a new \Enumerator:
 *
 *    'a8'.upto('b6') # => #<Enumerator: "a8":upto("b6")>
 *
 */

static VALUE
rb_str_upto(int argc, VALUE *argv, VALUE beg)
{
    VALUE end, exclusive;

    rb_scan_args(argc, argv, "11", &end, &exclusive);
    RETURN_ENUMERATOR(beg, argc, argv);
    return rb_str_upto_each(beg, end, RTEST(exclusive), str_upto_i, Qnil);
}

VALUE
rb_str_upto_each(VALUE beg, VALUE end, int excl, int (*each)(VALUE, VALUE), VALUE arg)
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
            VALUE args[2], fmt = rb_fstring_lit("%.*d");

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
    current = str_duplicate(rb_cString, beg);
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

VALUE
rb_str_upto_endless_each(VALUE beg, int (*each)(VALUE, VALUE), VALUE arg)
{
    VALUE current;
    ID succ;

    CONST_ID(succ, "succ");
    /* both edges are all digits */
    if (is_ascii_string(beg) && ISDIGIT(RSTRING_PTR(beg)[0]) &&
        all_digits_p(RSTRING_PTR(beg), RSTRING_LEN(beg))) {
        VALUE b, args[2], fmt = rb_fstring_lit("%.*d");
        int width = RSTRING_LENINT(beg);
        b = rb_str_to_inum(beg, 10, FALSE);
        if (FIXNUM_P(b)) {
            long bi = FIX2LONG(b);
            rb_encoding *usascii = rb_usascii_encoding();

            while (FIXABLE(bi)) {
                if ((*each)(rb_enc_sprintf(usascii, "%.*ld", width, bi), arg)) break;
                bi++;
            }
            b = LONG2NUM(bi);
        }
        args[0] = INT2FIX(width);
        while (1) {
            args[1] = b;
            if ((*each)(rb_str_format(numberof(args), args, fmt), arg)) break;
            b = rb_funcallv(b, succ, 0, 0);
        }
    }
    /* normal case */
    current = str_duplicate(rb_cString, beg);
    while (1) {
        VALUE next = rb_funcallv(current, succ, 0, 0);
        if ((*each)(current, arg)) break;
        current = next;
        StringValue(current);
        if (RSTRING_LEN(current) == 0)
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
                    return RBOOL(!RTEST(exclusive) && v == e);
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
    rb_str_upto_each(beg, end, RTEST(exclusive), include_range_i, (VALUE)&val);

    return RBOOL(NIL_P(val));
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
    }
    else if (RB_TYPE_P(indx, T_REGEXP)) {
        return rb_str_subpat(str, indx, INT2FIX(0));
    }
    else if (RB_TYPE_P(indx, T_STRING)) {
        if (rb_str_index(str, indx, 0) != -1)
            return str_duplicate(rb_cString, indx);
        return Qnil;
    }
    else {
        /* check if indx is Range */
        long beg, len = str_strlen(str, NULL);
        switch (rb_range_beg_len(indx, &beg, &len, len, 0)) {
          case Qfalse:
            break;
          case Qnil:
            return Qnil;
          default:
            return rb_str_substr(str, beg, len);
        }
        idx = NUM2LONG(indx);
    }

    return str_substr(str, idx, 1, FALSE);
}


/*
 *  call-seq:
 *    string[index] -> new_string or nil
 *    string[start, length] -> new_string or nil
 *    string[range] -> new_string or nil
 *    string[regexp, capture = 0] -> new_string or nil
 *    string[substring] -> new_string or nil
 *
 *  Returns the substring of +self+ specified by the arguments.
 *  See examples at {String Slices}[rdoc-ref:String@String+Slices].
 *
 *
 */

static VALUE
rb_str_aref_m(int argc, VALUE *argv, VALUE str)
{
    if (argc == 2) {
        if (RB_TYPE_P(argv[0], T_REGEXP)) {
            return rb_str_subpat(str, argv[0], argv[1]);
        }
        else {
            long beg = NUM2LONG(argv[0]);
            long len = NUM2LONG(argv[1]);
            return rb_str_substr(str, beg, len);
        }
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
    if (str_embed_capa(str) >= nlen + TERM_LEN(str)) {
        char *oldptr = ptr;
        int fl = (int)(RBASIC(str)->flags & (STR_NOEMBED|STR_SHARED|STR_NOFREE));
        STR_SET_EMBED(str);
        STR_SET_EMBED_LEN(str, nlen);
        ptr = RSTRING(str)->as.embed.ary;
        memmove(ptr, oldptr + len, nlen);
        if (fl == STR_NOEMBED) xfree(oldptr);
    }
    else {
        if (!STR_SHARED_P(str)) {
            VALUE shared = heap_str_make_shared(rb_obj_class(str), str);
            rb_enc_cr_str_exact_copy(shared, str);
            OBJ_FREEZE(shared);
        }
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
    int cr;

    if (beg == 0 && vlen == 0) {
        rb_str_drop_bytes(str, len);
        return;
    }

    str_modify_keep_cr(str);
    RSTRING_GETMEM(str, sptr, slen);
    if (len < vlen) {
        /* expand string */
        RESIZE_CAPA(str, slen + vlen - len);
        sptr = RSTRING_PTR(str);
    }

    if (ENC_CODERANGE(str) == ENC_CODERANGE_7BIT)
        cr = rb_enc_str_coderange(val);
    else
        cr = ENC_CODERANGE_UNKNOWN;

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
    ENC_CODERANGE_SET(str, cr);
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

    if ((slen < beg) || ((beg < 0) && (beg + slen < 0))) {
        rb_raise(rb_eIndexError, "index %ld out of string", beg);
    }
    if (beg < 0) {
        beg += slen;
    }
    assert(beg >= 0);
    assert(beg <= slen);
    if (len > slen - beg) {
        len = slen - beg;
    }
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
    if ((nth >= regs->num_regs) || ((nth < 0) && (-nth >= regs->num_regs))) {
        rb_raise(rb_eIndexError, "index %d out of regexp", nth);
    }
    if (nth < 0) {
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

      default:
        /* check if indx is Range */
        {
            long beg, len;
            if (rb_range_beg_len(indx, &beg, &len, str_strlen(str, NULL), 2)) {
                rb_str_splice(str, beg, len, val);
                return val;
            }
        }
        /* FALLTHROUGH */

      case T_FIXNUM:
        idx = NUM2LONG(indx);
        rb_str_splice(str, idx, 1, val);
        return val;
    }
}

/*
 *  call-seq:
 *    string[index] = new_string
 *    string[start, length] = new_string
 *    string[range] = new_string
 *    string[regexp, capture = 0] = new_string
 *    string[substring] = new_string
 *
 *  Replaces all, some, or none of the contents of +self+; returns +new_string+.
 *  See {String Slices}[rdoc-ref:String@String+Slices].
 *
 *  A few examples:
 *
 *    s = 'foo'
 *    s[2] = 'rtune'     # => "rtune"
 *    s                  # => "fortune"
 *    s[1, 5] = 'init'   # => "init"
 *    s                  # => "finite"
 *    s[3..4] = 'al'     # => "al"
 *    s                  # => "finale"
 *    s[/e$/] = 'ly'     # => "ly"
 *    s                  # => "finally"
 *    s['lly'] = 'ncial' # => "ncial"
 *    s                  # => "financial"
 *
 *  String#slice is an alias for String#[].
 *
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
 *    insert(index, other_string) -> self
 *
 *  Inserts the given +other_string+ into +self+; returns +self+.
 *
 *  If the \Integer +index+ is positive, inserts +other_string+ at offset +index+:
 *
 *    'foo'.insert(1, 'bar') # => "fbaroo"
 *
 *  If the \Integer +index+ is negative, counts backward from the end of +self+
 *  and inserts +other_string+ at offset <tt>index+1</tt>
 *  (that is, _after_ <tt>self[index]</tt>):
 *
 *    'foo'.insert(-2, 'bar') # => "fobaro"
 *
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
 *    slice!(index)               -> new_string or nil
 *    slice!(start, length)       -> new_string or nil
 *    slice!(range)               -> new_string or nil
 *    slice!(regexp, capture = 0) -> new_string or nil
 *    slice!(substring)           -> new_string or nil
 *
 *  Removes and returns the substring of +self+ specified by the arguments.
 *  See {String Slices}[rdoc-ref:String@String+Slices].
 *
 *  A few examples:
 *
 *     string = "This is a string"
 *     string.slice!(2)        #=> "i"
 *     string.slice!(3..6)     #=> " is "
 *     string.slice!(/s.*t/)   #=> "sa st"
 *     string.slice!("r")      #=> "r"
 *     string                  #=> "Thing"
 *
 */

static VALUE
rb_str_slice_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE result = Qnil;
    VALUE indx;
    long beg, len = 1;
    char *p;

    rb_check_arity(argc, 1, 2);
    str_modify_keep_cr(str);
    indx = argv[0];
    if (RB_TYPE_P(indx, T_REGEXP)) {
        if (rb_reg_search(indx, str, 0, 0) < 0) return Qnil;
        VALUE match = rb_backref_get();
        struct re_registers *regs = RMATCH_REGS(match);
        int nth = 0;
        if (argc > 1 && (nth = rb_reg_backref_number(match, argv[1])) < 0) {
            if ((nth += regs->num_regs) <= 0) return Qnil;
        }
        else if (nth >= regs->num_regs) return Qnil;
        beg = BEG(nth);
        len = END(nth) - beg;
        goto subseq;
    }
    else if (argc == 2) {
        beg = NUM2LONG(indx);
        len = NUM2LONG(argv[1]);
        goto num_index;
    }
    else if (FIXNUM_P(indx)) {
        beg = FIX2LONG(indx);
        if (!(p = rb_str_subpos(str, beg, &len))) return Qnil;
        if (!len) return Qnil;
        beg = p - RSTRING_PTR(str);
        goto subseq;
    }
    else if (RB_TYPE_P(indx, T_STRING)) {
        beg = rb_str_index(str, indx, 0);
        if (beg == -1) return Qnil;
        len = RSTRING_LEN(indx);
        result = str_duplicate(rb_cString, indx);
        goto squash;
    }
    else {
        switch (rb_range_beg_len(indx, &beg, &len, str_strlen(str, NULL), 0)) {
          case Qnil:
            return Qnil;
          case Qfalse:
            beg = NUM2LONG(indx);
            if (!(p = rb_str_subpos(str, beg, &len))) return Qnil;
            if (!len) return Qnil;
            beg = p - RSTRING_PTR(str);
            goto subseq;
          default:
            goto num_index;
        }
    }

  num_index:
    if (!(p = rb_str_subpos(str, beg, &len))) return Qnil;
    beg = p - RSTRING_PTR(str);

  subseq:
    result = rb_str_new(RSTRING_PTR(str)+beg, len);
    rb_enc_cr_str_copy_for_substr(result, str);

  squash:
    if (len > 0) {
        if (beg == 0) {
            rb_str_drop_bytes(str, len);
        }
        else {
            char *sptr = RSTRING_PTR(str);
            long slen = RSTRING_LEN(str);
            if (beg + len > slen) /* pathological check */
                len = slen - beg;
            memmove(sptr + beg,
                    sptr + beg + len,
                    slen - (beg + len));
            slen -= len;
            STR_SET_LEN(str, slen);
            TERM_FILL(&sptr[slen], TERM_LEN(str));
        }
    }
    return result;
}

static VALUE
get_pat(VALUE pat)
{
    VALUE val;

    switch (OBJ_BUILTIN_TYPE(pat)) {
      case T_REGEXP:
        return pat;

      case T_STRING:
        break;

      default:
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

    switch (OBJ_BUILTIN_TYPE(pat)) {
      case T_REGEXP:
        return pat;

      case T_STRING:
        break;

      default:
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
                str = rb_str_new_frozen_String(str);
                rb_backref_set_string(str, pos, RSTRING_LEN(pat));
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
 *    sub!(pattern, replacement)   -> self or nil
 *    sub!(pattern) {|match| ... } -> self or nil
 *
 *  Returns +self+ with only the first occurrence
 *  (not all occurrences) of the given +pattern+ replaced.
 *
 *  See {Substitution Methods}[rdoc-ref:String@Substitution+Methods].
 *
 *  Related: String#sub, String#gsub, String#gsub!.
 *
 */

static VALUE
rb_str_sub_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE pat, repl, hash = Qnil;
    int iter = 0;
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
        if (ENC_CODERANGE_UNKNOWN < cr && cr < ENC_CODERANGE_BROKEN) {
            int cr2 = ENC_CODERANGE(repl);
            if (cr2 == ENC_CODERANGE_BROKEN ||
                (cr == ENC_CODERANGE_VALID && cr2 == ENC_CODERANGE_7BIT))
                cr = ENC_CODERANGE_UNKNOWN;
            else
                cr = cr2;
        }
        plen = end0 - beg0;
        rlen = RSTRING_LEN(repl);
        len = RSTRING_LEN(str);
        if (rlen > plen) {
            RESIZE_CAPA(str, len + rlen - plen);
        }
        p = RSTRING_PTR(str);
        if (rlen != plen) {
            memmove(p + beg0 + rlen, p + beg0 + plen, len - beg0 - plen);
        }
        rp = RSTRING_PTR(repl);
        memmove(p + beg0, rp, rlen);
        len += rlen - plen;
        STR_SET_LEN(str, len);
        TERM_FILL(&RSTRING_PTR(str)[len], TERM_LEN(str));
        ENC_CODERANGE_SET(str, cr);

        return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *    sub(pattern, replacement)   -> new_string
 *    sub(pattern) {|match| ... } -> new_string
 *
 *  Returns a copy of +self+ with only the first occurrence
 *  (not all occurrences) of the given +pattern+ replaced.
 *
 *  See {Substitution Methods}[rdoc-ref:String@Substitution+Methods].
 *
 *  Related: String#sub!, String#gsub, String#gsub!.
 *
 */

static VALUE
rb_str_sub(int argc, VALUE *argv, VALUE str)
{
    str = str_duplicate(rb_cString, str);
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
        break;
      default:
        rb_error_arity(argc, 1, 2);
    }

    pat = get_pat_quoted(argv[0], 1);
    beg = rb_pat_search(pat, str, 0, need_backref);
    if (beg < 0) {
        if (bang) return Qnil;	/* no match, no substitution */
        return str_duplicate(rb_cString, str);
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
        str = dest;
    }

    return str;
}


/*
 *  call-seq:
 *     gsub!(pattern, replacement)   -> self or nil
 *     gsub!(pattern) {|match| ... } -> self or nil
 *     gsub!(pattern)                -> an_enumerator
 *
 *  Performs the specified substring replacement(s) on +self+;
 *  returns +self+ if any replacement occurred, +nil+ otherwise.
 *
 *  See {Substitution Methods}[rdoc-ref:String@Substitution+Methods].
 *
 *  Returns an Enumerator if no +replacement+ and no block given.
 *
 *  Related: String#sub, String#gsub, String#sub!.
 *
 */

static VALUE
rb_str_gsub_bang(int argc, VALUE *argv, VALUE str)
{
    str_modify_keep_cr(str);
    return str_gsub(argc, argv, str, 1);
}


/*
 *  call-seq:
 *     gsub(pattern, replacement)   -> new_string
 *     gsub(pattern) {|match| ... } -> new_string
 *     gsub(pattern)                -> enumerator
 *
 *  Returns a copy of +self+ with all occurrences of the given +pattern+ replaced.
 *
 *  See {Substitution Methods}[rdoc-ref:String@Substitution+Methods].
 *
 *  Returns an Enumerator if no +replacement+ and no block given.
 *
 *  Related: String#sub, String#sub!, String#gsub!.
 *
 */

static VALUE
rb_str_gsub(int argc, VALUE *argv, VALUE str)
{
    return str_gsub(argc, argv, str, 0);
}


/*
 *  call-seq:
 *    replace(other_string) -> self
 *
 *  Replaces the contents of +self+ with the contents of +other_string+:
 *
 *    s = 'foo'        # => "foo"
 *    s.replace('bar') # => "bar"
 *
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
 *    clear -> self
 *
 *  Removes the contents of +self+:
 *
 *    s = 'foo' # => "foo"
 *    s.clear   # => ""
 *
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
 *    chr -> string
 *
 *  Returns a string containing the first character of +self+:
 *
 *    s = 'foo' # => "foo"
 *    s.chr     # => "f"
 *
 */

static VALUE
rb_str_chr(VALUE str)
{
    return rb_str_substr(str, 0, 1);
}

/*
 *  call-seq:
 *    getbyte(index) -> integer or nil
 *
 *  Returns the byte at zero-based +index+ as an integer, or +nil+ if +index+ is out of range:
 *
 *    s = 'abcde'   # => "abcde"
 *    s.getbyte(0)  # => 97
 *    s.getbyte(-1) # => 101
 *    s.getbyte(5)  # => nil
 *
 *  Related: String#setbyte.
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
 *    setbyte(index, integer) -> integer
 *
 *  Sets the byte at zero-based +index+ to +integer+; returns +integer+:
 *
 *    s = 'abcde'      # => "abcde"
 *    s.setbyte(0, 98) # => 98
 *    s                # => "bbcde"
 *
 *  Related: String#getbyte.
 */
static VALUE
rb_str_setbyte(VALUE str, VALUE index, VALUE value)
{
    long pos = NUM2LONG(index);
    long len = RSTRING_LEN(str);
    char *ptr, *head, *left = 0;
    rb_encoding *enc;
    int cr = ENC_CODERANGE_UNKNOWN, width, nlen;

    if (pos < -len || len <= pos)
        rb_raise(rb_eIndexError, "index %ld out of string", pos);
    if (pos < 0)
        pos += len;

    VALUE v = rb_to_int(value);
    VALUE w = rb_int_and(v, INT2FIX(0xff));
    char byte = (char)(NUM2INT(w) & 0xFF);

    if (!str_independent(str))
        str_make_independent(str);
    enc = STR_ENC_GET(str);
    head = RSTRING_PTR(str);
    ptr = &head[pos];
    if (!STR_EMBED_P(str)) {
        cr = ENC_CODERANGE(str);
        switch (cr) {
          case ENC_CODERANGE_7BIT:
            left = ptr;
            *ptr = byte;
            if (ISASCII(byte)) goto end;
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
str_byte_substr(VALUE str, long beg, long len, int empty)
{
    long n = RSTRING_LEN(str);

    if (beg > n || len < 0) return Qnil;
    if (beg < 0) {
        beg += n;
        if (beg < 0) return Qnil;
    }
    if (len > n - beg)
        len = n - beg;
    if (len <= 0) {
        if (!empty) return Qnil;
        len = 0;
    }

    VALUE str2 = str_subseq(str, beg, len);

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

    return str2;
}

static VALUE
str_byte_aref(VALUE str, VALUE indx)
{
    long idx;
    if (FIXNUM_P(indx)) {
        idx = FIX2LONG(indx);
    }
    else {
        /* check if indx is Range */
        long beg, len = RSTRING_LEN(str);

        switch (rb_range_beg_len(indx, &beg, &len, len, 0)) {
          case Qfalse:
            break;
          case Qnil:
            return Qnil;
          default:
            return str_byte_substr(str, beg, len, TRUE);
        }

        idx = NUM2LONG(indx);
    }
    return str_byte_substr(str, idx, 1, FALSE);
}

/*
 *  call-seq:
 *    byteslice(index, length = 1) -> string or nil
 *    byteslice(range)             -> string or nil
 *
 *  Returns a substring of +self+, or +nil+ if the substring cannot be constructed.
 *
 *  With integer arguments +index+ and +length+ given,
 *  returns the substring beginning at the given +index+
 *  of the given +length+ (if possible),
 *  or +nil+ if +length+ is negative or +index+ falls outside of +self+:
 *
 *    s = '0123456789' # => "0123456789"
 *    s.byteslice(2)   # => "2"
 *    s.byteslice(200) # => nil
 *    s.byteslice(4, 3)  # => "456"
 *    s.byteslice(4, 30) # => "456789"
 *    s.byteslice(4, -1) # => nil
 *    s.byteslice(40, 2) # => nil
 *
 *  In either case above, counts backwards from the end of +self+
 *  if +index+ is negative:
 *
 *    s = '0123456789'   # => "0123456789"
 *    s.byteslice(-4)    # => "6"
 *    s.byteslice(-4, 3) # => "678"
 *
 *  With Range argument +range+ given, returns
 *  <tt>byteslice(range.begin, range.size)</tt>:
 *
 *    s = '0123456789'    # => "0123456789"
 *    s.byteslice(4..6)   # => "456"
 *    s.byteslice(-6..-4) # => "456"
 *    s.byteslice(5..2)   # => "" # range.size is zero.
 *    s.byteslice(40..42) # => nil
 *
 *  In all cases, a returned string has the same encoding as +self+:
 *
 *    s.encoding              # => #<Encoding:UTF-8>
 *    s.byteslice(4).encoding # => #<Encoding:UTF-8>
 *
 */

static VALUE
rb_str_byteslice(int argc, VALUE *argv, VALUE str)
{
    if (argc == 2) {
        long beg = NUM2LONG(argv[0]);
        long len = NUM2LONG(argv[1]);
        return str_byte_substr(str, beg, len, TRUE);
    }
    rb_check_arity(argc, 1, 2);
    return str_byte_aref(str, argv[0]);
}

/*
 *  call-seq:
 *    bytesplice(index, length, str) -> string
 *    bytesplice(range, str)         -> string
 *
 *  Replaces some or all of the content of +self+ with +str+, and returns +self+.
 *  The portion of the string affected is determined using
 *  the same criteria as String#byteslice, except that +length+ cannot be omitted.
 *  If the replacement string is not the same length as the text it is replacing,
 *  the string will be adjusted accordingly.
 *  The form that take an Integer will raise an IndexError if the value is out
 *  of range; the Range form will raise a RangeError.
 *  If the beginning or ending offset does not land on character (codepoint)
 *  boundary, an IndexError will be raised.
 */

static VALUE
rb_str_bytesplice(int argc, VALUE *argv, VALUE str)
{
    long beg, end, len, slen;
    VALUE val;
    rb_encoding *enc;
    int cr;

    rb_check_arity(argc, 2, 3);
    if (argc == 2) {
        if (!rb_range_beg_len(argv[0], &beg, &len, RSTRING_LEN(str), 2)) {
            rb_raise(rb_eTypeError, "wrong argument type %s (expected Range)",
                     rb_builtin_class_name(argv[0]));
        }
        val = argv[1];
    }
    else {
        beg = NUM2LONG(argv[0]);
        len = NUM2LONG(argv[1]);
        val = argv[2];
    }
    if (len < 0) rb_raise(rb_eIndexError, "negative length %ld", len);
    slen = RSTRING_LEN(str);
    if ((slen < beg) || ((beg < 0) && (beg + slen < 0))) {
        rb_raise(rb_eIndexError, "index %ld out of string", beg);
    }
    if (beg < 0) {
        beg += slen;
    }
    assert(beg >= 0);
    assert(beg <= slen);
    if (len > slen - beg) {
        len = slen - beg;
    }
    end = beg + len;
    if (!str_check_byte_pos(str, beg)) {
        rb_raise(rb_eIndexError,
                 "offset %ld does not land on character boundary", beg);
    }
    if (!str_check_byte_pos(str, end)) {
        rb_raise(rb_eIndexError,
                 "offset %ld does not land on character boundary", end);
    }
    StringValue(val);
    enc = rb_enc_check(str, val);
    str_modify_keep_cr(str);
    rb_str_splice_0(str, beg, len, val);
    rb_enc_associate(str, enc);
    cr = ENC_CODERANGE_AND(ENC_CODERANGE(str), ENC_CODERANGE(val));
    if (cr != ENC_CODERANGE_BROKEN)
        ENC_CODERANGE_SET(str, cr);
    return str;
}

/*
 *  call-seq:
 *    reverse -> string
 *
 *  Returns a new string with the characters from +self+ in reverse order.
 *
 *    'stressed'.reverse # => "desserts"
 *
 */

static VALUE
rb_str_reverse(VALUE str)
{
    rb_encoding *enc;
    VALUE rev;
    char *s, *e, *p;
    int cr;

    if (RSTRING_LEN(str) <= 1) return str_duplicate(rb_cString, str);
    enc = STR_ENC_GET(str);
    rev = rb_str_new(0, RSTRING_LEN(str));
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
    str_enc_copy(rev, str);
    ENC_CODERANGE_SET(rev, cr);

    return rev;
}


/*
 *  call-seq:
 *    reverse! -> self
 *
 *  Returns +self+ with its characters reversed:
 *
 *    s = 'stressed'
 *    s.reverse! # => "desserts"
 *    s          # => "desserts"
 *
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
 *    include? other_string -> true or false
 *
 *  Returns +true+ if +self+ contains +other_string+, +false+ otherwise:
 *
 *    s = 'foo'
 *    s.include?('f')    # => true
 *    s.include?('fo')   # => true
 *    s.include?('food') # => false
 *
 */

VALUE
rb_str_include(VALUE str, VALUE arg)
{
    long i;

    StringValue(arg);
    i = rb_str_index(str, arg, 0);

    return RBOOL(i != -1);
}


/*
 *  call-seq:
 *    to_i(base = 10) -> integer
 *
 *  Returns the result of interpreting leading characters in +self+
 *  as an integer in the given +base+ (which must be in (0, 2..36)):
 *
 *    '123456'.to_i     # => 123456
 *    '123def'.to_i(16) # => 1195503
 *
 *  With +base+ zero, string +object+ may contain leading characters
 *  to specify the actual base:
 *
 *    '123def'.to_i(0)   # => 123
 *    '0123def'.to_i(0)  # => 83
 *    '0b123def'.to_i(0) # => 1
 *    '0o123def'.to_i(0) # => 83
 *    '0d123def'.to_i(0) # => 123
 *    '0x123def'.to_i(0) # => 1195503
 *
 *  Characters past a leading valid number (in the given +base+) are ignored:
 *
 *    '12.345'.to_i   # => 12
 *    '12345'.to_i(2) # => 1
 *
 *  Returns zero if there is no leading valid number:
 *
 *    'abcdef'.to_i # => 0
 *    '2'.to_i(2)   # => 0
 *
 */

static VALUE
rb_str_to_i(int argc, VALUE *argv, VALUE str)
{
    int base = 10;

    if (rb_check_arity(argc, 0, 1) && (base = NUM2INT(argv[0])) < 0) {
        rb_raise(rb_eArgError, "invalid radix %d", base);
    }
    return rb_str_to_inum(str, base, FALSE);
}


/*
 *  call-seq:
 *    to_f -> float
 *
 *  Returns the result of interpreting leading characters in +self+ as a Float:
 *
 *    '3.14159'.to_f  # => 3.14159
      '1.234e-2'.to_f # => 0.01234
 *
 *  Characters past a leading valid number (in the given +base+) are ignored:
 *
 *    '3.14 (pi to two places)'.to_f # => 3.14
 *
 *  Returns zero if there is no leading valid number:
 *
 *    'abcdef'.to_f # => 0.0
 *
 */

static VALUE
rb_str_to_f(VALUE str)
{
    return DBL2NUM(rb_str_to_dbl(str, FALSE));
}


/*
 *  call-seq:
 *    to_s -> self or string
 *
 *  Returns +self+ if +self+ is a \String,
 *  or +self+ converted to a \String if +self+ is a subclass of \String.
 *
 *  String#to_str is an alias for String#to_s.
 *
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

const char *
ruby_escaped_char(int c)
{
    switch (c) {
      case '\0': return "\\0";
      case '\n': return "\\n";
      case '\r': return "\\r";
      case '\t': return "\\t";
      case '\f': return "\\f";
      case '\013': return "\\v";
      case '\010': return "\\b";
      case '\007': return "\\a";
      case '\033': return "\\e";
      case '\x7f': return "\\c?";
    }
    return NULL;
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
        unsigned int c;
        const char *cc;
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
        cc = ruby_escaped_char(c);
        if (cc) {
            if (p - n > prev) str_buf_cat(result, prev, p - n - prev);
            str_buf_cat(result, cc, strlen(cc));
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

    return result;
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a printable version of +self+, enclosed in double-quotes,
 *  and with special characters escaped:
 *
 *    s = "foo\tbar\tbaz\n"
 *    s.inspect
 *    # => "\"foo\\tbar\\tbaz\\n\""
 *
 */

VALUE
rb_str_inspect(VALUE str)
{
    int encidx = ENCODING_GET(str);
    rb_encoding *enc = rb_enc_from_index(encidx);
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
        /* The special casing of 0x85 (NEXT_LINE) here is because
         * Oniguruma historically treats it as printable, but it
         * doesn't match the print POSIX bracket class or character
         * property in regexps.
         *
         * See Ruby Bug #16842 for details:
         * https://bugs.ruby-lang.org/issues/16842
         */
        if ((enc == resenc && rb_enc_isprint(c, enc) && c != 0x85) ||
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

    return result;
}

#define IS_EVSTR(p,e) ((p) < (e) && (*(p) == '$' || *(p) == '@' || *(p) == '{'))

/*
 *  call-seq:
 *    dump -> string
 *
 *  Returns a printable version of +self+, enclosed in double-quotes,
 *  with special characters escaped, and with non-printing characters
 *  replaced by hexadecimal notation:
 *
 *    "hello \n ''".dump    # => "\"hello \\n ''\""
 *    "\f\x00\xff\\\"".dump # => "\"\\f\\x00\\xFF\\\\\\\"\""
 *
 *  Related: String#undump (inverse of String#dump).
 *
 */

VALUE
rb_str_dump(VALUE str)
{
    int encidx = rb_enc_get_index(str);
    rb_encoding *enc = rb_enc_from_index(encidx);
    long len;
    const char *p, *pend;
    char *q, *qend;
    VALUE result;
    int u8 = (encidx == rb_utf8_encindex());
    static const char nonascii_suffix[] = ".dup.force_encoding(\"%s\")";

    len = 2;			/* "" */
    if (!rb_enc_asciicompat(enc)) {
        len += strlen(nonascii_suffix) - rb_strlen_lit("%s");
        len += strlen(enc->name);
    }

    p = RSTRING_PTR(str); pend = p + RSTRING_LEN(str);
    while (p < pend) {
        int clen;
        unsigned char c = *p++;

        switch (c) {
          case '"':  case '\\':
          case '\n': case '\r':
          case '\t': case '\f':
          case '\013': case '\010': case '\007': case '\033':
            clen = 2;
            break;

          case '#':
            clen = IS_EVSTR(p, pend) ? 2 : 1;
            break;

          default:
            if (ISPRINT(c)) {
                clen = 1;
            }
            else {
                if (u8 && c > 0x7F) {	/* \u notation */
                    int n = rb_enc_precise_mbclen(p-1, pend, enc);
                    if (MBCLEN_CHARFOUND_P(n)) {
                        unsigned int cc = rb_enc_mbc_to_codepoint(p-1, pend, enc);
                        if (cc <= 0xFFFF)
                            clen = 6;  /* \uXXXX */
                        else if (cc <= 0xFFFFF)
                            clen = 9;  /* \u{XXXXX} */
                        else
                            clen = 10; /* \u{XXXXXX} */
                        p += MBCLEN_CHARFOUND_LEN(n)-1;
                        break;
                    }
                }
                clen = 4;	/* \xNN */
            }
            break;
        }

        if (clen > LONG_MAX - len) {
            rb_raise(rb_eRuntimeError, "string size too big");
        }
        len += clen;
    }

    result = rb_str_new(0, len);
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
                    if (cc <= 0xFFFF)
                        snprintf(q, qend-q, "u%04X", cc);    /* \uXXXX */
                    else
                        snprintf(q, qend-q, "u{%X}", cc);  /* \u{XXXXX} or \u{XXXXXX} */
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
        snprintf(q, qend-q, nonascii_suffix, enc->name);
        encidx = rb_ascii8bit_encindex();
    }
    /* result from dump is ASCII */
    rb_enc_associate_index(result, encidx);
    ENC_CODERANGE_SET(result, ENC_CODERANGE_7BIT);
    return result;
}

static int
unescape_ascii(unsigned int c)
{
    switch (c) {
      case 'n':
        return '\n';
      case 'r':
        return '\r';
      case 't':
        return '\t';
      case 'f':
        return '\f';
      case 'v':
        return '\13';
      case 'b':
        return '\010';
      case 'a':
        return '\007';
      case 'e':
        return 033;
    }
    UNREACHABLE_RETURN(-1);
}

static void
undump_after_backslash(VALUE undumped, const char **ss, const char *s_end, rb_encoding **penc, bool *utf8, bool *binary)
{
    const char *s = *ss;
    unsigned int c;
    int codelen;
    size_t hexlen;
    unsigned char buf[6];
    static rb_encoding *enc_utf8 = NULL;

    switch (*s) {
      case '\\':
      case '"':
      case '#':
        rb_str_cat(undumped, s, 1); /* cat itself */
        s++;
        break;
      case 'n':
      case 'r':
      case 't':
      case 'f':
      case 'v':
      case 'b':
      case 'a':
      case 'e':
        *buf = unescape_ascii(*s);
        rb_str_cat(undumped, (char *)buf, 1);
        s++;
        break;
      case 'u':
        if (*binary) {
            rb_raise(rb_eRuntimeError, "hex escape and Unicode escape are mixed");
        }
        *utf8 = true;
        if (++s >= s_end) {
            rb_raise(rb_eRuntimeError, "invalid Unicode escape");
        }
        if (enc_utf8 == NULL) enc_utf8 = rb_utf8_encoding();
        if (*penc != enc_utf8) {
            *penc = enc_utf8;
            rb_enc_associate(undumped, enc_utf8);
        }
        if (*s == '{') { /* handle \u{...} form */
            s++;
            for (;;) {
                if (s >= s_end) {
                    rb_raise(rb_eRuntimeError, "unterminated Unicode escape");
                }
                if (*s == '}') {
                    s++;
                    break;
                }
                if (ISSPACE(*s)) {
                    s++;
                    continue;
                }
                c = scan_hex(s, s_end-s, &hexlen);
                if (hexlen == 0 || hexlen > 6) {
                    rb_raise(rb_eRuntimeError, "invalid Unicode escape");
                }
                if (c > 0x10ffff) {
                    rb_raise(rb_eRuntimeError, "invalid Unicode codepoint (too large)");
                }
                if (0xd800 <= c && c <= 0xdfff) {
                    rb_raise(rb_eRuntimeError, "invalid Unicode codepoint");
                }
                codelen = rb_enc_mbcput(c, (char *)buf, *penc);
                rb_str_cat(undumped, (char *)buf, codelen);
                s += hexlen;
            }
        }
        else { /* handle \uXXXX form */
            c = scan_hex(s, 4, &hexlen);
            if (hexlen != 4) {
                rb_raise(rb_eRuntimeError, "invalid Unicode escape");
            }
            if (0xd800 <= c && c <= 0xdfff) {
                rb_raise(rb_eRuntimeError, "invalid Unicode codepoint");
            }
            codelen = rb_enc_mbcput(c, (char *)buf, *penc);
            rb_str_cat(undumped, (char *)buf, codelen);
            s += hexlen;
        }
        break;
      case 'x':
        if (*utf8) {
            rb_raise(rb_eRuntimeError, "hex escape and Unicode escape are mixed");
        }
        *binary = true;
        if (++s >= s_end) {
            rb_raise(rb_eRuntimeError, "invalid hex escape");
        }
        *buf = scan_hex(s, 2, &hexlen);
        if (hexlen != 2) {
            rb_raise(rb_eRuntimeError, "invalid hex escape");
        }
        rb_str_cat(undumped, (char *)buf, 1);
        s += hexlen;
        break;
      default:
        rb_str_cat(undumped, s-1, 2);
        s++;
    }

    *ss = s;
}

static VALUE rb_str_is_ascii_only_p(VALUE str);

/*
 *  call-seq:
 *    undump -> string
 *
 *  Returns an unescaped version of +self+:
 *
 *    s_orig = "\f\x00\xff\\\""    # => "\f\u0000\xFF\\\""
 *    s_dumped = s_orig.dump       # => "\"\\f\\x00\\xFF\\\\\\\"\""
 *    s_undumped = s_dumped.undump # => "\f\u0000\xFF\\\""
 *    s_undumped == s_orig         # => true
 *
 *  Related: String#dump (inverse of String#undump).
 *
 */

static VALUE
str_undump(VALUE str)
{
    const char *s = RSTRING_PTR(str);
    const char *s_end = RSTRING_END(str);
    rb_encoding *enc = rb_enc_get(str);
    VALUE undumped = rb_enc_str_new(s, 0L, enc);
    bool utf8 = false;
    bool binary = false;
    int w;

    rb_must_asciicompat(str);
    if (rb_str_is_ascii_only_p(str) == Qfalse) {
        rb_raise(rb_eRuntimeError, "non-ASCII character detected");
    }
    if (!str_null_check(str, &w)) {
        rb_raise(rb_eRuntimeError, "string contains null byte");
    }
    if (RSTRING_LEN(str) < 2) goto invalid_format;
    if (*s != '"') goto invalid_format;

    /* strip '"' at the start */
    s++;

    for (;;) {
        if (s >= s_end) {
            rb_raise(rb_eRuntimeError, "unterminated dumped string");
        }

        if (*s == '"') {
            /* epilogue */
            s++;
            if (s == s_end) {
                /* ascii compatible dumped string */
                break;
            }
            else {
                static const char force_encoding_suffix[] = ".force_encoding(\""; /* "\")" */
                static const char dup_suffix[] = ".dup";
                const char *encname;
                int encidx;
                ptrdiff_t size;

                /* check separately for strings dumped by older versions */
                size = sizeof(dup_suffix) - 1;
                if (s_end - s > size && memcmp(s, dup_suffix, size) == 0) s += size;

                size = sizeof(force_encoding_suffix) - 1;
                if (s_end - s <= size) goto invalid_format;
                if (memcmp(s, force_encoding_suffix, size) != 0) goto invalid_format;
                s += size;

                if (utf8) {
                    rb_raise(rb_eRuntimeError, "dumped string contained Unicode escape but used force_encoding");
                }

                encname = s;
                s = memchr(s, '"', s_end-s);
                size = s - encname;
                if (!s) goto invalid_format;
                if (s_end - s != 2) goto invalid_format;
                if (s[0] != '"' || s[1] != ')') goto invalid_format;

                encidx = rb_enc_find_index2(encname, (long)size);
                if (encidx < 0) {
                    rb_raise(rb_eRuntimeError, "dumped string has unknown encoding name");
                }
                rb_enc_associate_index(undumped, encidx);
            }
            break;
        }

        if (*s == '\\') {
            s++;
            if (s >= s_end) {
                rb_raise(rb_eRuntimeError, "invalid escape");
            }
            undump_after_backslash(undumped, &s, s_end, &enc, &utf8, &binary);
        }
        else {
            rb_str_cat(undumped, s++, 1);
        }
    }

    return undumped;
invalid_format:
    rb_raise(rb_eRuntimeError, "invalid dumped string; not wrapped with '\"' nor '\"...\".force_encoding(\"...\")' form");
}

static void
rb_str_check_dummy_enc(rb_encoding *enc)
{
    if (rb_enc_dummy_p(enc)) {
        rb_raise(rb_eEncCompatError, "incompatible encoding with this operation: %s",
                 rb_enc_name(enc));
    }
}

static rb_encoding *
str_true_enc(VALUE str)
{
    rb_encoding *enc = STR_ENC_GET(str);
    rb_str_check_dummy_enc(enc);
    return enc;
}

static OnigCaseFoldType
check_case_options(int argc, VALUE *argv, OnigCaseFoldType flags)
{
    if (argc==0)
        return flags;
    if (argc>2)
        rb_raise(rb_eArgError, "too many options");
    if (argv[0]==sym_turkic) {
        flags |= ONIGENC_CASE_FOLD_TURKISH_AZERI;
        if (argc==2) {
            if (argv[1]==sym_lithuanian)
                flags |= ONIGENC_CASE_FOLD_LITHUANIAN;
            else
                rb_raise(rb_eArgError, "invalid second option");
        }
    }
    else if (argv[0]==sym_lithuanian) {
        flags |= ONIGENC_CASE_FOLD_LITHUANIAN;
        if (argc==2) {
            if (argv[1]==sym_turkic)
                flags |= ONIGENC_CASE_FOLD_TURKISH_AZERI;
            else
                rb_raise(rb_eArgError, "invalid second option");
        }
    }
    else if (argc>1)
        rb_raise(rb_eArgError, "too many options");
    else if (argv[0]==sym_ascii)
        flags |= ONIGENC_CASE_ASCII_ONLY;
    else if (argv[0]==sym_fold) {
        if ((flags & (ONIGENC_CASE_UPCASE|ONIGENC_CASE_DOWNCASE)) == ONIGENC_CASE_DOWNCASE)
            flags ^= ONIGENC_CASE_FOLD|ONIGENC_CASE_DOWNCASE;
        else
            rb_raise(rb_eArgError, "option :fold only allowed for downcasing");
    }
    else
        rb_raise(rb_eArgError, "invalid option");
    return flags;
}

static inline bool
case_option_single_p(OnigCaseFoldType flags, rb_encoding *enc, VALUE str)
{
    if ((flags & ONIGENC_CASE_ASCII_ONLY) && (enc==rb_utf8_encoding() || rb_enc_mbmaxlen(enc) == 1))
        return true;
    return !(flags & ONIGENC_CASE_FOLD_TURKISH_AZERI) && ENC_CODERANGE(str) == ENC_CODERANGE_7BIT;
}

/* 16 should be long enough to absorb any kind of single character length increase */
#define CASE_MAPPING_ADDITIONAL_LENGTH 20
#ifndef CASEMAP_DEBUG
# define CASEMAP_DEBUG 0
#endif

struct mapping_buffer;
typedef struct mapping_buffer {
    size_t capa;
    size_t used;
    struct mapping_buffer *next;
    OnigUChar space[FLEX_ARY_LEN];
} mapping_buffer;

static void
mapping_buffer_free(void *p)
{
    mapping_buffer *previous_buffer;
    mapping_buffer *current_buffer = p;
    while (current_buffer) {
        previous_buffer = current_buffer;
        current_buffer  = current_buffer->next;
        ruby_sized_xfree(previous_buffer, previous_buffer->capa);
    }
}

static const rb_data_type_t mapping_buffer_type = {
    "mapping_buffer",
    {0, mapping_buffer_free,}
};

static VALUE
rb_str_casemap(VALUE source, OnigCaseFoldType *flags, rb_encoding *enc)
{
    VALUE target;

    const OnigUChar *source_current, *source_end;
    int target_length = 0;
    VALUE buffer_anchor;
    mapping_buffer *current_buffer = 0;
    mapping_buffer **pre_buffer;
    size_t buffer_count = 0;
    int buffer_length_or_invalid;

    if (RSTRING_LEN(source) == 0) return str_duplicate(rb_cString, source);

    source_current = (OnigUChar*)RSTRING_PTR(source);
    source_end = (OnigUChar*)RSTRING_END(source);

    buffer_anchor = TypedData_Wrap_Struct(0, &mapping_buffer_type, 0);
    pre_buffer = (mapping_buffer **)&DATA_PTR(buffer_anchor);
    while (source_current < source_end) {
        /* increase multiplier using buffer count to converge quickly */
        size_t capa = (size_t)(source_end-source_current)*++buffer_count + CASE_MAPPING_ADDITIONAL_LENGTH;
        if (CASEMAP_DEBUG) {
            fprintf(stderr, "Buffer allocation, capa is %"PRIuSIZE"\n", capa); /* for tuning */
        }
        current_buffer = xmalloc(offsetof(mapping_buffer, space) + capa);
        *pre_buffer = current_buffer;
        pre_buffer = &current_buffer->next;
        current_buffer->next = NULL;
        current_buffer->capa = capa;
        buffer_length_or_invalid = enc->case_map(flags,
                                   &source_current, source_end,
                                   current_buffer->space,
                                   current_buffer->space+current_buffer->capa,
                                   enc);
        if (buffer_length_or_invalid < 0) {
            current_buffer = DATA_PTR(buffer_anchor);
            DATA_PTR(buffer_anchor) = 0;
            mapping_buffer_free(current_buffer);
            rb_raise(rb_eArgError, "input string invalid");
        }
        target_length  += current_buffer->used = buffer_length_or_invalid;
    }
    if (CASEMAP_DEBUG) {
        fprintf(stderr, "Buffer count is %"PRIuSIZE"\n", buffer_count); /* for tuning */
    }

    if (buffer_count==1) {
        target = rb_str_new((const char*)current_buffer->space, target_length);
    }
    else {
        char *target_current;

        target = rb_str_new(0, target_length);
        target_current = RSTRING_PTR(target);
        current_buffer = DATA_PTR(buffer_anchor);
        while (current_buffer) {
            memcpy(target_current, current_buffer->space, current_buffer->used);
            target_current += current_buffer->used;
            current_buffer  = current_buffer->next;
        }
    }
    current_buffer = DATA_PTR(buffer_anchor);
    DATA_PTR(buffer_anchor) = 0;
    mapping_buffer_free(current_buffer);

    RB_GC_GUARD(buffer_anchor);

    /* TODO: check about string terminator character */
    str_enc_copy(target, source);
    /*ENC_CODERANGE_SET(mapped, cr);*/

    return target;
}

static VALUE
rb_str_ascii_casemap(VALUE source, VALUE target, OnigCaseFoldType *flags, rb_encoding *enc)
{
    const OnigUChar *source_current, *source_end;
    OnigUChar *target_current, *target_end;
    long old_length = RSTRING_LEN(source);
    int length_or_invalid;

    if (old_length == 0) return Qnil;

    source_current = (OnigUChar*)RSTRING_PTR(source);
    source_end = (OnigUChar*)RSTRING_END(source);
    if (source == target) {
        target_current = (OnigUChar*)source_current;
        target_end = (OnigUChar*)source_end;
    }
    else {
        target_current = (OnigUChar*)RSTRING_PTR(target);
        target_end = (OnigUChar*)RSTRING_END(target);
    }

    length_or_invalid = onigenc_ascii_only_case_map(flags,
                               &source_current, source_end,
                               target_current, target_end, enc);
    if (length_or_invalid < 0)
        rb_raise(rb_eArgError, "input string invalid");
    if (CASEMAP_DEBUG && length_or_invalid != old_length) {
        fprintf(stderr, "problem with rb_str_ascii_casemap"
                "; old_length=%ld, new_length=%d\n", old_length, length_or_invalid);
        rb_raise(rb_eArgError, "internal problem with rb_str_ascii_casemap"
                 "; old_length=%ld, new_length=%d\n", old_length, length_or_invalid);
    }

    str_enc_copy(target, source);

    return target;
}

static bool
upcase_single(VALUE str)
{
    char *s = RSTRING_PTR(str), *send = RSTRING_END(str);
    bool modified = false;

    while (s < send) {
        unsigned int c = *(unsigned char*)s;

        if ('a' <= c && c <= 'z') {
            *s = 'A' + (c - 'a');
            modified = true;
        }
        s++;
    }
    return modified;
}

/*
 *  call-seq:
 *    upcase!(*options) -> self or nil
 *
 *  Upcases the characters in +self+;
 *  returns +self+ if any changes were made, +nil+ otherwise:
 *
 *    s = 'Hello World!' # => "Hello World!"
 *    s.upcase!          # => "HELLO WORLD!"
 *    s                  # => "HELLO WORLD!"
 *    s.upcase!          # => nil
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#upcase, String#downcase, String#downcase!.
 *
 */

static VALUE
rb_str_upcase_bang(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_UPCASE;

    flags = check_case_options(argc, argv, flags);
    str_modify_keep_cr(str);
    enc = str_true_enc(str);
    if (case_option_single_p(flags, enc, str)) {
        if (upcase_single(str))
            flags |= ONIGENC_CASE_MODIFIED;
    }
    else if (flags&ONIGENC_CASE_ASCII_ONLY)
        rb_str_ascii_casemap(str, str, &flags, enc);
    else
        str_shared_replace(str, rb_str_casemap(str, &flags, enc));

    if (ONIGENC_CASE_MODIFIED&flags) return str;
    return Qnil;
}


/*
 *  call-seq:
 *    upcase(*options) -> string
 *
 *  Returns a string containing the upcased characters in +self+:
 *
 *     s = 'Hello World!' # => "Hello World!"
 *     s.upcase           # => "HELLO WORLD!"
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#upcase!, String#downcase, String#downcase!.
 *
 */

static VALUE
rb_str_upcase(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_UPCASE;
    VALUE ret;

    flags = check_case_options(argc, argv, flags);
    enc = str_true_enc(str);
    if (case_option_single_p(flags, enc, str)) {
        ret = rb_str_new(RSTRING_PTR(str), RSTRING_LEN(str));
        str_enc_copy(ret, str);
        upcase_single(ret);
    }
    else if (flags&ONIGENC_CASE_ASCII_ONLY) {
        ret = rb_str_new(0, RSTRING_LEN(str));
        rb_str_ascii_casemap(str, ret, &flags, enc);
    }
    else {
        ret = rb_str_casemap(str, &flags, enc);
    }

    return ret;
}

static bool
downcase_single(VALUE str)
{
    char *s = RSTRING_PTR(str), *send = RSTRING_END(str);
    bool modified = false;

    while (s < send) {
        unsigned int c = *(unsigned char*)s;

        if ('A' <= c && c <= 'Z') {
            *s = 'a' + (c - 'A');
            modified = true;
        }
        s++;
    }

    return modified;
}

/*
 *  call-seq:
 *    downcase!(*options) -> self or nil
 *
 *  Downcases the characters in +self+;
 *  returns +self+ if any changes were made, +nil+ otherwise:
 *
 *    s = 'Hello World!' # => "Hello World!"
 *    s.downcase!        # => "hello world!"
 *    s                  # => "hello world!"
 *    s.downcase!        # => nil
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#downcase, String#upcase, String#upcase!.
 *
 */

static VALUE
rb_str_downcase_bang(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_DOWNCASE;

    flags = check_case_options(argc, argv, flags);
    str_modify_keep_cr(str);
    enc = str_true_enc(str);
    if (case_option_single_p(flags, enc, str)) {
        if (downcase_single(str))
            flags |= ONIGENC_CASE_MODIFIED;
    }
    else if (flags&ONIGENC_CASE_ASCII_ONLY)
        rb_str_ascii_casemap(str, str, &flags, enc);
    else
        str_shared_replace(str, rb_str_casemap(str, &flags, enc));

    if (ONIGENC_CASE_MODIFIED&flags) return str;
    return Qnil;
}


/*
 *  call-seq:
 *    downcase(*options) -> string
 *
 *  Returns a string containing the downcased characters in +self+:
 *
 *     s = 'Hello World!' # => "Hello World!"
 *     s.downcase         # => "hello world!"
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#downcase!, String#upcase, String#upcase!.
 *
 */

static VALUE
rb_str_downcase(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_DOWNCASE;
    VALUE ret;

    flags = check_case_options(argc, argv, flags);
    enc = str_true_enc(str);
    if (case_option_single_p(flags, enc, str)) {
        ret = rb_str_new(RSTRING_PTR(str), RSTRING_LEN(str));
        str_enc_copy(ret, str);
        downcase_single(ret);
    }
    else if (flags&ONIGENC_CASE_ASCII_ONLY) {
        ret = rb_str_new(0, RSTRING_LEN(str));
        rb_str_ascii_casemap(str, ret, &flags, enc);
    }
    else {
        ret = rb_str_casemap(str, &flags, enc);
    }

    return ret;
}


/*
 *  call-seq:
 *    capitalize!(*options) -> self or nil
 *
 *  Upcases the first character in +self+;
 *  downcases the remaining characters;
 *  returns +self+ if any changes were made, +nil+ otherwise:
 *
 *    s = 'hello World!' # => "hello World!"
 *    s.capitalize!      # => "Hello world!"
 *    s                  # => "Hello world!"
 *    s.capitalize!      # => nil
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#capitalize.
 *
 */

static VALUE
rb_str_capitalize_bang(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_UPCASE | ONIGENC_CASE_TITLECASE;

    flags = check_case_options(argc, argv, flags);
    str_modify_keep_cr(str);
    enc = str_true_enc(str);
    if (RSTRING_LEN(str) == 0 || !RSTRING_PTR(str)) return Qnil;
    if (flags&ONIGENC_CASE_ASCII_ONLY)
        rb_str_ascii_casemap(str, str, &flags, enc);
    else
        str_shared_replace(str, rb_str_casemap(str, &flags, enc));

    if (ONIGENC_CASE_MODIFIED&flags) return str;
    return Qnil;
}


/*
 *  call-seq:
 *    capitalize(*options) -> string
 *
 *  Returns a string containing the characters in +self+;
 *  the first character is upcased;
 *  the remaining characters are downcased:
 *
 *     s = 'hello World!' # => "hello World!"
 *     s.capitalize       # => "Hello world!"
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#capitalize!.
 *
 */

static VALUE
rb_str_capitalize(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_UPCASE | ONIGENC_CASE_TITLECASE;
    VALUE ret;

    flags = check_case_options(argc, argv, flags);
    enc = str_true_enc(str);
    if (RSTRING_LEN(str) == 0 || !RSTRING_PTR(str)) return str;
    if (flags&ONIGENC_CASE_ASCII_ONLY) {
        ret = rb_str_new(0, RSTRING_LEN(str));
        rb_str_ascii_casemap(str, ret, &flags, enc);
    }
    else {
        ret = rb_str_casemap(str, &flags, enc);
    }
    return ret;
}


/*
 *  call-seq:
 *    swapcase!(*options) -> self or nil
 *
 *  Upcases each lowercase character in +self+;
 *  downcases uppercase character;
 *  returns +self+ if any changes were made, +nil+ otherwise:
 *
 *    s = 'Hello World!' # => "Hello World!"
 *    s.swapcase!        # => "hELLO wORLD!"
 *    s                  # => "hELLO wORLD!"
 *    ''.swapcase!       # => nil
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#swapcase.
 *
 */

static VALUE
rb_str_swapcase_bang(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_UPCASE | ONIGENC_CASE_DOWNCASE;

    flags = check_case_options(argc, argv, flags);
    str_modify_keep_cr(str);
    enc = str_true_enc(str);
    if (flags&ONIGENC_CASE_ASCII_ONLY)
        rb_str_ascii_casemap(str, str, &flags, enc);
    else
        str_shared_replace(str, rb_str_casemap(str, &flags, enc));

    if (ONIGENC_CASE_MODIFIED&flags) return str;
    return Qnil;
}


/*
 *  call-seq:
 *    swapcase(*options) -> string
 *
 *  Returns a string containing the characters in +self+, with cases reversed;
 *  each uppercase character is downcased;
 *  each lowercase character is upcased:
 *
 *     s = 'Hello World!' # => "Hello World!"
 *     s.swapcase         # => "hELLO wORLD!"
 *
 *  The casing may be affected by the given +options+;
 *  see {Case Mapping}[rdoc-ref:case_mapping.rdoc].
 *
 *  Related: String#swapcase!.
 *
 */

static VALUE
rb_str_swapcase(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    OnigCaseFoldType flags = ONIGENC_CASE_UPCASE | ONIGENC_CASE_DOWNCASE;
    VALUE ret;

    flags = check_case_options(argc, argv, flags);
    enc = str_true_enc(str);
    if (RSTRING_LEN(str) == 0 || !RSTRING_PTR(str)) return str_duplicate(rb_cString, str);
    if (flags&ONIGENC_CASE_ASCII_ONLY) {
        ret = rb_str_new(0, RSTRING_LEN(str));
        rb_str_ascii_casemap(str, ret, &flags, enc);
    }
    else {
        ret = rb_str_casemap(str, &flags, enc);
    }
    return ret;
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
      nextpart:
        if (!t->gen) {
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
    unsigned char *s, *send;
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

    if (cr == ENC_CODERANGE_VALID && rb_enc_asciicompat(e1))
        cr = ENC_CODERANGE_7BIT;
    str_modify_keep_cr(str);
    s = (unsigned char *)RSTRING_PTR(str); send = (unsigned char *)RSTRING_END(str);
    termlen = rb_enc_mbminlen(enc);
    if (sflag) {
        int clen, tlen;
        long offset, max = RSTRING_LEN(str);
        unsigned int save = -1;
        unsigned char *buf = ALLOC_N(unsigned char, max + termlen), *t = buf;

        while (s < send) {
            int may_modify = 0;

            c0 = c = rb_enc_codepoint_len((char *)s, (char *)send, &clen, e1);
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
            if ((offset = t - buf) + tlen > max) {
                size_t MAYBE_UNUSED(old) = max + termlen;
                max = offset + tlen + (send - s);
                SIZED_REALLOC_N(buf, unsigned char, max + termlen, old);
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
        TERM_FILL((char *)t, termlen);
        RSTRING(str)->as.heap.ptr = (char *)buf;
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
        unsigned char *buf = ALLOC_N(unsigned char, max + termlen), *t = buf;

        while (s < send) {
            int may_modify = 0;
            c0 = c = rb_enc_codepoint_len((char *)s, (char *)send, &clen, e1);
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
            if ((offset = t - buf) + tlen > max) {
                size_t MAYBE_UNUSED(old) = max + termlen;
                max = offset + tlen + (long)((send - s) * 1.2);
                SIZED_REALLOC_N(buf, unsigned char, max + termlen, old);
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
        TERM_FILL((char *)t, termlen);
        RSTRING(str)->as.heap.ptr = (char *)buf;
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
 *    tr!(selector, replacements) -> self or nil
 *
 *  Like String#tr, but modifies +self+ in place.
 *  Returns +self+ if any changes were made, +nil+ otherwise.
 *
 */

static VALUE
rb_str_tr_bang(VALUE str, VALUE src, VALUE repl)
{
    return tr_trans(str, src, repl, 0);
}


/*
 *  call-seq:
 *    tr(selector, replacements) -> new_string
 *
 *  Returns a copy of +self+ with each character specified by string +selector+
 *  translated to the corresponding character in string +replacements+.
 *  The correspondence is _positional_:
 *
 *  - Each occurrence of the first character specified by +selector+
 *    is translated to the first character in +replacements+.
 *  - Each occurrence of the second character specified by +selector+
 *    is translated to the second character in +replacements+.
 *  - And so on.
 *
 *  Example:
 *
 *    'hello'.tr('el', 'ip') #=> "hippo"
 *
 *  If +replacements+ is shorter than +selector+,
 *  it is implicitly padded with its own last character:
 *
 *    'hello'.tr('aeiou', '-')   # => "h-ll-"
 *    'hello'.tr('aeiou', 'AA-') # => "hAll-"
 *
 *  Arguments +selector+ and +replacements+ must be valid character selectors
 *  (see {Character Selectors}[rdoc-ref:character_selectors.rdoc]),
 *  and may use any of its valid forms, including negation, ranges, and escaping:
 *
 *    # Negation.
 *    'hello'.tr('^aeiou', '-') # => "-e--o"
 *    # Ranges.
 *    'ibm'.tr('b-z', 'a-z') # => "hal"
 *    # Escapes.
 *    'hel^lo'.tr('\^aeiou', '-')     # => "h-l-l-"    # Escaped leading caret.
 *    'i-b-m'.tr('b\-z', 'a-z')       # => "ibabm"     # Escaped embedded hyphen.
 *    'foo\\bar'.tr('ab\\', 'XYZ')    # => "fooZYXr"   # Escaped backslash.
 *
 */

static VALUE
rb_str_tr(VALUE str, VALUE src, VALUE repl)
{
    str = str_duplicate(rb_cString, str);
    tr_trans(str, src, repl, 0);
    return str;
}

#define TR_TABLE_MAX (UCHAR_MAX+1)
#define TR_TABLE_SIZE (TR_TABLE_MAX+1)
static void
tr_setup_table(VALUE str, char stable[TR_TABLE_SIZE], int first,
               VALUE *tablep, VALUE *ctablep, rb_encoding *enc)
{
    const unsigned int errc = -1;
    char buf[TR_TABLE_MAX];
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
        for (i=0; i<TR_TABLE_MAX; i++) {
            stable[i] = 1;
        }
        stable[TR_TABLE_MAX] = cflag;
    }
    else if (stable[TR_TABLE_MAX] && !cflag) {
        stable[TR_TABLE_MAX] = 0;
    }
    for (i=0; i<TR_TABLE_MAX; i++) {
        buf[i] = cflag;
    }

    while ((c = trnext(&tr, enc)) != errc) {
        if (c < TR_TABLE_MAX) {
            buf[(unsigned char)c] = !cflag;
        }
        else {
            VALUE key = UINT2NUM(c);

            if (!table && (first || *tablep || stable[TR_TABLE_MAX])) {
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
    for (i=0; i<TR_TABLE_MAX; i++) {
        stable[i] = stable[i] && buf[i];
    }
    if (!table && !cflag) {
        *tablep = 0;
    }
}


static int
tr_find(unsigned int c, const char table[TR_TABLE_SIZE], VALUE del, VALUE nodel)
{
    if (c < TR_TABLE_MAX) {
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
        return table[TR_TABLE_MAX] ? TRUE : FALSE;
    }
}

/*
 *  call-seq:
 *    delete!(*selectors) -> self or nil
 *
 *  Like String#delete, but modifies +self+ in place.
 *  Returns +self+ if any changes were made, +nil+ otherwise.
 *
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
 *    delete(*selectors) -> new_string
 *
 *  Returns a copy of +self+ with characters specified by +selectors+ removed
 *  (see {Multiple Character Selectors}[rdoc-ref:character_selectors.rdoc@Multiple+Character+Selectors]):
 *
 *     "hello".delete "l","lo"        #=> "heo"
 *     "hello".delete "lo"            #=> "he"
 *     "hello".delete "aeiou", "^e"   #=> "hell"
 *     "hello".delete "ej-m"          #=> "ho"
 *
 */

static VALUE
rb_str_delete(int argc, VALUE *argv, VALUE str)
{
    str = str_duplicate(rb_cString, str);
    rb_str_delete_bang(argc, argv, str);
    return str;
}


/*
 *  call-seq:
 *    squeeze!(*selectors) -> self or nil
 *
 *  Like String#squeeze, but modifies +self+ in place.
 *  Returns +self+ if any changes were made, +nil+ otherwise.
 */

static VALUE
rb_str_squeeze_bang(int argc, VALUE *argv, VALUE str)
{
    char squeez[TR_TABLE_SIZE];
    rb_encoding *enc = 0;
    VALUE del = 0, nodel = 0;
    unsigned char *s, *send, *t;
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
    s = t = (unsigned char *)RSTRING_PTR(str);
    if (!s || RSTRING_LEN(str) == 0) return Qnil;
    send = (unsigned char *)RSTRING_END(str);
    save = -1;
    ascompat = rb_enc_asciicompat(enc);

    if (singlebyte) {
        while (s < send) {
            unsigned int c = *s++;
            if (c != save || (argc > 0 && !squeez[c])) {
                *t++ = save = c;
            }
        }
    }
    else {
        while (s < send) {
            unsigned int c;
            int clen;

            if (ascompat && (c = *s) < 0x80) {
                if (c != save || (argc > 0 && !squeez[c])) {
                    *t++ = save = c;
                }
                s++;
            }
            else {
                c = rb_enc_codepoint_len((char *)s, (char *)send, &clen, enc);

                if (c != save || (argc > 0 && !tr_find(c, squeez, del, nodel))) {
                    if (t != s) rb_enc_mbcput(c, t, enc);
                    save = c;
                    t += clen;
                }
                s += clen;
            }
        }
    }

    TERM_FILL((char *)t, TERM_LEN(str));
    if ((char *)t - RSTRING_PTR(str) != RSTRING_LEN(str)) {
        STR_SET_LEN(str, (char *)t - RSTRING_PTR(str));
        modify = 1;
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *    squeeze(*selectors) -> new_string
 *
 *  Returns a copy of +self+ with characters specified by +selectors+ "squeezed"
 *  (see {Multiple Character Selectors}[rdoc-ref:character_selectors.rdoc@Multiple+Character+Selectors]):
 *
 *  "Squeezed" means that each multiple-character run of a selected character
 *  is squeezed down to a single character;
 *  with no arguments given, squeezes all characters:
 *
 *     "yellow moon".squeeze                  #=> "yelow mon"
 *     "  now   is  the".squeeze(" ")         #=> " now is the"
 *     "putters shoot balls".squeeze("m-z")   #=> "puters shot balls"
 *
 */

static VALUE
rb_str_squeeze(int argc, VALUE *argv, VALUE str)
{
    str = str_duplicate(rb_cString, str);
    rb_str_squeeze_bang(argc, argv, str);
    return str;
}


/*
 *  call-seq:
 *    tr_s!(selector, replacements) -> self or nil
 *
 *  Like String#tr_s, but modifies +self+ in place.
 *  Returns +self+ if any changes were made, +nil+ otherwise.
 *
 *  Related: String#squeeze!.
 */

static VALUE
rb_str_tr_s_bang(VALUE str, VALUE src, VALUE repl)
{
    return tr_trans(str, src, repl, 1);
}


/*
 *  call-seq:
 *    tr_s(selector, replacements) -> string
 *
 *  Like String#tr, but also squeezes the modified portions of the translated string;
 *  returns a new string (translated and squeezed).
 *
 *    'hello'.tr_s('l', 'r')   #=> "hero"
 *    'hello'.tr_s('el', '-')  #=> "h-o"
 *    'hello'.tr_s('el', 'hx') #=> "hhxo"
 *
 *  Related: String#squeeze.
 *
 */

static VALUE
rb_str_tr_s(VALUE str, VALUE src, VALUE repl)
{
    str = str_duplicate(rb_cString, str);
    tr_trans(str, src, repl, 1);
    return str;
}


/*
 *  call-seq:
 *    count(*selectors) -> integer
 *
 *  Returns the total number of characters in +self+
 *  that are specified by the given +selectors+
 *  (see {Multiple Character Selectors}[rdoc-ref:character_selectors.rdoc@Multiple+Character+Selectors]):
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
    size_t n = 0;

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
            int clen;
            unsigned char c = rb_enc_codepoint_len(ptstr, ptstr+1, &clen, enc);

            s = RSTRING_PTR(str);
            if (!s || RSTRING_LEN(str) == 0) return INT2FIX(0);
            send = RSTRING_END(str);
            while (s < send) {
                if (*(unsigned char*)s++ == c) n++;
            }
            return SIZET2NUM(n);
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
    while (s < send) {
        unsigned int c;

        if (ascompat && (c = *(unsigned char*)s) < 0x80) {
            if (table[c]) {
                n++;
            }
            s++;
        }
        else {
            int clen;
            c = rb_enc_codepoint_len(s, send, &clen, enc);
            if (tr_find(c, table, del, nodel)) {
                n++;
            }
            s += clen;
        }
    }

    return SIZET2NUM(n);
}

static VALUE
rb_fs_check(VALUE val)
{
    if (!NIL_P(val) && !RB_TYPE_P(val, T_STRING) && !RB_TYPE_P(val, T_REGEXP)) {
        val = rb_check_string_type(val);
        if (NIL_P(val)) return 0;
    }
    return val;
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

static long
split_string(VALUE result, VALUE str, long beg, long len, long empty_count)
{
    if (empty_count >= 0 && len == 0) {
        return empty_count + 1;
    }
    if (empty_count > 0) {
        /* make different substrings */
        if (result) {
            do {
                rb_ary_push(result, str_new_empty_String(str));
            } while (--empty_count > 0);
        }
        else {
            do {
                rb_yield(str_new_empty_String(str));
            } while (--empty_count > 0);
        }
    }
    str = rb_str_subseq(str, beg, len);
    if (result) {
        rb_ary_push(result, str);
    }
    else {
        rb_yield(str);
    }
    return empty_count;
}

typedef enum {
    SPLIT_TYPE_AWK, SPLIT_TYPE_STRING, SPLIT_TYPE_REGEXP, SPLIT_TYPE_CHARS
} split_type_t;

static split_type_t
literal_split_pattern(VALUE spat, split_type_t default_type)
{
    rb_encoding *enc = STR_ENC_GET(spat);
    const char *ptr;
    long len;
    RSTRING_GETMEM(spat, ptr, len);
    if (len == 0) {
        /* Special case - split into chars */
        return SPLIT_TYPE_CHARS;
    }
    else if (rb_enc_asciicompat(enc)) {
        if (len == 1 && ptr[0] == ' ') {
            return SPLIT_TYPE_AWK;
        }
    }
    else {
        int l;
        if (rb_enc_ascget(ptr, ptr + len, &l, enc) == ' ' && len == l) {
            return SPLIT_TYPE_AWK;
        }
    }
    return default_type;
}

/*
 *  call-seq:
 *    split(field_sep = $;, limit = nil) -> array
 *    split(field_sep = $;, limit = nil) {|substring| ... } -> self
 *
 *  :include: doc/string/split.rdoc
 *
 */

static VALUE
rb_str_split_m(int argc, VALUE *argv, VALUE str)
{
    rb_encoding *enc;
    VALUE spat;
    VALUE limit;
    split_type_t split_type;
    long beg, end, i = 0, empty_count = -1;
    int lim = 0;
    VALUE result, tmp;

    result = rb_block_given_p() ? Qfalse : Qnil;
    if (rb_scan_args(argc, argv, "02", &spat, &limit) == 2) {
        lim = NUM2INT(limit);
        if (lim <= 0) limit = Qnil;
        else if (lim == 1) {
            if (RSTRING_LEN(str) == 0)
                return result ? rb_ary_new2(0) : str;
            tmp = str_duplicate(rb_cString, str);
            if (!result) {
                rb_yield(tmp);
                return str;
            }
            return rb_ary_new3(1, tmp);
        }
        i = 1;
    }
    if (NIL_P(limit) && !lim) empty_count = 0;

    enc = STR_ENC_GET(str);
    split_type = SPLIT_TYPE_REGEXP;
    if (!NIL_P(spat)) {
        spat = get_pat_quoted(spat, 0);
    }
    else if (NIL_P(spat = rb_fs)) {
        split_type = SPLIT_TYPE_AWK;
    }
    else if (!(spat = rb_fs_check(spat))) {
        rb_raise(rb_eTypeError, "value of $; must be String or Regexp");
    }
    else {
        rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "$; is set to non-nil value");
    }
    if (split_type != SPLIT_TYPE_AWK) {
        switch (BUILTIN_TYPE(spat)) {
          case T_REGEXP:
            rb_reg_options(spat); /* check if uninitialized */
            tmp = RREGEXP_SRC(spat);
            split_type = literal_split_pattern(tmp, SPLIT_TYPE_REGEXP);
            if (split_type == SPLIT_TYPE_AWK) {
                spat = tmp;
                split_type = SPLIT_TYPE_STRING;
            }
            break;

          case T_STRING:
            mustnot_broken(spat);
            split_type = literal_split_pattern(spat, SPLIT_TYPE_STRING);
            break;

          default:
            UNREACHABLE_RETURN(Qnil);
        }
    }

#define SPLIT_STR(beg, len) (empty_count = split_string(result, str, beg, len, empty_count))

    if (result) result = rb_ary_new();
    beg = 0;
    char *ptr = RSTRING_PTR(str);
    char *eptr = RSTRING_END(str);
    if (split_type == SPLIT_TYPE_AWK) {
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
                    SPLIT_STR(beg, end-beg);
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
                    SPLIT_STR(beg, end-beg);
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
    else if (split_type == SPLIT_TYPE_STRING) {
        char *str_start = ptr;
        char *substr_start = ptr;
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
            SPLIT_STR(substr_start - str_start, (ptr+end) - substr_start);
            ptr += end + slen;
            substr_start = ptr;
            if (!NIL_P(limit) && lim <= ++i) break;
        }
        beg = ptr - str_start;
    }
    else if (split_type == SPLIT_TYPE_CHARS) {
        char *str_start = ptr;
        int n;

        mustnot_broken(str);
        enc = rb_enc_get(str);
        while (ptr < eptr &&
               (n = rb_enc_precise_mbclen(ptr, eptr, enc)) > 0) {
            SPLIT_STR(ptr - str_start, n);
            ptr += n;
            if (!NIL_P(limit) && lim <= ++i) break;
        }
        beg = ptr - str_start;
    }
    else {
        long len = RSTRING_LEN(str);
        long start = beg;
        long idx;
        int last_null = 0;
        struct re_registers *regs;
        VALUE match = 0;

        for (; rb_reg_search(spat, str, start, 0) >= 0;
             (match ? (rb_match_unbusy(match), rb_backref_set(match)) : (void)0)) {
            match = rb_backref_get();
            if (!result) rb_match_busy(match);
            regs = RMATCH_REGS(match);
            end = BEG(0);
            if (start == end && BEG(0) == END(0)) {
                if (!ptr) {
                    SPLIT_STR(0, 0);
                    break;
                }
                else if (last_null == 1) {
                    SPLIT_STR(beg, rb_enc_fast_mbclen(ptr+beg, eptr, enc));
                    beg = start;
                }
                else {
                    if (start == len)
                        start++;
                    else
                        start += rb_enc_fast_mbclen(ptr+start,eptr,enc);
                    last_null = 1;
                    continue;
                }
            }
            else {
                SPLIT_STR(beg, end-beg);
                beg = start = END(0);
            }
            last_null = 0;

            for (idx=1; idx < regs->num_regs; idx++) {
                if (BEG(idx) == -1) continue;
                SPLIT_STR(BEG(idx), END(idx)-BEG(idx));
            }
            if (!NIL_P(limit) && lim <= ++i) break;
        }
        if (match) rb_match_unbusy(match);
    }
    if (RSTRING_LEN(str) > 0 && (!NIL_P(limit) || RSTRING_LEN(str) > beg || lim < 0)) {
        SPLIT_STR(beg, RSTRING_LEN(str)-beg);
    }

    return result ? result : str;
}

VALUE
rb_str_split(VALUE str, const char *sep0)
{
    VALUE sep;

    StringValue(str);
    sep = rb_str_new_cstr(sep0);
    return rb_str_split_m(1, &sep, str);
}

#define WANTARRAY(m, size) (!rb_block_given_p() ? rb_ary_new_capa(size) : 0)

static inline int
enumerator_element(VALUE ary, VALUE e)
{
    if (ary) {
        rb_ary_push(ary, e);
        return 0;
    }
    else {
        rb_yield(e);
        return 1;
    }
}

#define ENUM_ELEM(ary, e) enumerator_element(ary, e)

static const char *
chomp_newline(const char *p, const char *e, rb_encoding *enc)
{
    const char *prev = rb_enc_prev_char(p, e, e, enc);
    if (rb_enc_is_newline(prev, e, enc)) {
        e = prev;
        prev = rb_enc_prev_char(p, e, e, enc);
        if (prev && rb_enc_ascget(prev, e, NULL, enc) == '\r')
            e = prev;
    }
    return e;
}

static VALUE
get_rs(void)
{
    VALUE rs = rb_rs;
    if (!NIL_P(rs) &&
        (!RB_TYPE_P(rs, T_STRING) ||
         RSTRING_LEN(rs) != 1 ||
         RSTRING_PTR(rs)[0] != '\n')) {
        rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "$/ is set to non-default value");
    }
    return rs;
}

#define rb_rs get_rs()

static VALUE
rb_str_enumerate_lines(int argc, VALUE *argv, VALUE str, VALUE ary)
{
    rb_encoding *enc;
    VALUE line, rs, orig = str, opts = Qnil, chomp = Qfalse;
    const char *ptr, *pend, *subptr, *subend, *rsptr, *hit, *adjusted;
    long pos, len, rslen;
    int rsnewline = 0;

    if (rb_scan_args(argc, argv, "01:", &rs, &opts) == 0)
        rs = rb_rs;
    if (!NIL_P(opts)) {
        static ID keywords[1];
        if (!keywords[0]) {
            keywords[0] = rb_intern_const("chomp");
        }
        rb_get_kwargs(opts, keywords, 0, 1, &chomp);
        chomp = (!UNDEF_P(chomp) && RTEST(chomp));
    }

    if (NIL_P(rs)) {
        if (!ENUM_ELEM(ary, str)) {
            return ary;
        }
        else {
            return orig;
        }
    }

    if (!RSTRING_LEN(str)) goto end;
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
        /* paragraph mode */
        int n;
        const char *eol = NULL;
        subend = subptr;
        while (subend < pend) {
            long chomp_rslen = 0;
            do {
                if (rb_enc_ascget(subend, pend, &n, enc) != '\r')
                    n = 0;
                rslen = n + rb_enc_mbclen(subend + n, pend, enc);
                if (rb_enc_is_newline(subend + n, pend, enc)) {
                    if (eol == subend) break;
                    subend += rslen;
                    if (subptr) {
                        eol = subend;
                        chomp_rslen = -rslen;
                    }
                }
                else {
                    if (!subptr) subptr = subend;
                    subend += rslen;
                }
                rslen = 0;
            } while (subend < pend);
            if (!subptr) break;
            if (rslen == 0) chomp_rslen = 0;
            line = rb_str_subseq(str, subptr - ptr,
                                 subend - subptr + (chomp ? chomp_rslen : rslen));
            if (ENUM_ELEM(ary, line)) {
                str_mod_check(str, ptr, len);
            }
            subptr = eol = NULL;
        }
        goto end;
    }
    else {
        rsptr = RSTRING_PTR(rs);
        if (RSTRING_LEN(rs) == rb_enc_mbminlen(enc) &&
            rb_enc_is_newline(rsptr, rsptr + RSTRING_LEN(rs), enc)) {
            rsnewline = 1;
        }
    }

    if ((rs == rb_default_rs) && !rb_enc_asciicompat(enc)) {
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
        subend = hit += rslen;
        if (chomp) {
            if (rsnewline) {
                subend = chomp_newline(subptr, subend, enc);
            }
            else {
                subend -= rslen;
            }
        }
        line = rb_str_subseq(str, subptr - ptr, subend - subptr);
        if (ENUM_ELEM(ary, line)) {
            str_mod_check(str, ptr, len);
        }
        subptr = hit;
    }

    if (subptr != pend) {
        if (chomp) {
            if (rsnewline) {
                pend = chomp_newline(subptr, pend, enc);
            }
            else if (pend - subptr >= rslen &&
                     memcmp(pend - rslen, rsptr, rslen) == 0) {
                pend -= rslen;
            }
        }
        line = rb_str_subseq(str, subptr - ptr, pend - subptr);
        ENUM_ELEM(ary, line);
        RB_GC_GUARD(str);
    }

  end:
    if (ary)
        return ary;
    else
        return orig;
}

/*
 *  call-seq:
 *    each_line(line_sep = $/, chomp: false) {|substring| ... } -> self
 *    each_line(line_sep = $/, chomp: false)                    -> enumerator
 *
 *  :include: doc/string/each_line.rdoc
 *
 */

static VALUE
rb_str_each_line(int argc, VALUE *argv, VALUE str)
{
    RETURN_SIZED_ENUMERATOR(str, argc, argv, 0);
    return rb_str_enumerate_lines(argc, argv, str, 0);
}

/*
 *  call-seq:
 *    lines(Line_sep = $/, chomp: false) -> array_of_strings
 *
 *  Forms substrings ("lines") of +self+ according to the given arguments
 *  (see String#each_line for details); returns the lines in an array.
 *
 */

static VALUE
rb_str_lines(int argc, VALUE *argv, VALUE str)
{
    VALUE ary = WANTARRAY("lines", 0);
    return rb_str_enumerate_lines(argc, argv, str, ary);
}

static VALUE
rb_str_each_byte_size(VALUE str, VALUE args, VALUE eobj)
{
    return LONG2FIX(RSTRING_LEN(str));
}

static VALUE
rb_str_enumerate_bytes(VALUE str, VALUE ary)
{
    long i;

    for (i=0; i<RSTRING_LEN(str); i++) {
        ENUM_ELEM(ary, INT2FIX((unsigned char)RSTRING_PTR(str)[i]));
    }
    if (ary)
        return ary;
    else
        return str;
}

/*
 *  call-seq:
 *    each_byte {|byte| ... } -> self
 *    each_byte               -> enumerator
 *
 *  :include: doc/string/each_byte.rdoc
 *
 */

static VALUE
rb_str_each_byte(VALUE str)
{
    RETURN_SIZED_ENUMERATOR(str, 0, 0, rb_str_each_byte_size);
    return rb_str_enumerate_bytes(str, 0);
}

/*
 *  call-seq:
 *    bytes -> array_of_bytes
 *
 *  :include: doc/string/bytes.rdoc
 *
 */

static VALUE
rb_str_bytes(VALUE str)
{
    VALUE ary = WANTARRAY("bytes", RSTRING_LEN(str));
    return rb_str_enumerate_bytes(str, ary);
}

static VALUE
rb_str_each_char_size(VALUE str, VALUE args, VALUE eobj)
{
    return rb_str_length(str);
}

static VALUE
rb_str_enumerate_chars(VALUE str, VALUE ary)
{
    VALUE orig = str;
    long i, len, n;
    const char *ptr;
    rb_encoding *enc;

    str = rb_str_new_frozen(str);
    ptr = RSTRING_PTR(str);
    len = RSTRING_LEN(str);
    enc = rb_enc_get(str);

    if (ENC_CODERANGE_CLEAN_P(ENC_CODERANGE(str))) {
        for (i = 0; i < len; i += n) {
            n = rb_enc_fast_mbclen(ptr + i, ptr + len, enc);
            ENUM_ELEM(ary, rb_str_subseq(str, i, n));
        }
    }
    else {
        for (i = 0; i < len; i += n) {
            n = rb_enc_mbclen(ptr + i, ptr + len, enc);
            ENUM_ELEM(ary, rb_str_subseq(str, i, n));
        }
    }
    RB_GC_GUARD(str);
    if (ary)
        return ary;
    else
        return orig;
}

/*
 *  call-seq:
 *    each_char {|c| ... } -> self
 *    each_char            -> enumerator
 *
 *  :include: doc/string/each_char.rdoc
 *
 */

static VALUE
rb_str_each_char(VALUE str)
{
    RETURN_SIZED_ENUMERATOR(str, 0, 0, rb_str_each_char_size);
    return rb_str_enumerate_chars(str, 0);
}

/*
 *  call-seq:
 *    chars -> array_of_characters
 *
 *  :include: doc/string/chars.rdoc
 *
 */

static VALUE
rb_str_chars(VALUE str)
{
    VALUE ary = WANTARRAY("chars", rb_str_strlen(str));
    return rb_str_enumerate_chars(str, ary);
}

static VALUE
rb_str_enumerate_codepoints(VALUE str, VALUE ary)
{
    VALUE orig = str;
    int n;
    unsigned int c;
    const char *ptr, *end;
    rb_encoding *enc;

    if (single_byte_optimizable(str))
        return rb_str_enumerate_bytes(str, ary);

    str = rb_str_new_frozen(str);
    ptr = RSTRING_PTR(str);
    end = RSTRING_END(str);
    enc = STR_ENC_GET(str);

    while (ptr < end) {
        c = rb_enc_codepoint_len(ptr, end, &n, enc);
        ENUM_ELEM(ary, UINT2NUM(c));
        ptr += n;
    }
    RB_GC_GUARD(str);
    if (ary)
        return ary;
    else
        return orig;
}

/*
 *  call-seq:
 *    each_codepoint {|integer| ... } -> self
 *    each_codepoint                  -> enumerator
 *
 *  :include: doc/string/each_codepoint.rdoc
 *
 */

static VALUE
rb_str_each_codepoint(VALUE str)
{
    RETURN_SIZED_ENUMERATOR(str, 0, 0, rb_str_each_char_size);
    return rb_str_enumerate_codepoints(str, 0);
}

/*
 *  call-seq:
 *    codepoints -> array_of_integers
 *
 *  :include: doc/string/codepoints.rdoc
 *
 */

static VALUE
rb_str_codepoints(VALUE str)
{
    VALUE ary = WANTARRAY("codepoints", rb_str_strlen(str));
    return rb_str_enumerate_codepoints(str, ary);
}

static regex_t *
get_reg_grapheme_cluster(rb_encoding *enc)
{
    int encidx = rb_enc_to_index(enc);

    const OnigUChar source_ascii[] = "\\X";
    const OnigUChar *source = source_ascii;
    size_t source_len = sizeof(source_ascii) - 1;

    switch (encidx) {
#define CHARS_16BE(x) (OnigUChar)((x)>>8), (OnigUChar)(x)
#define CHARS_16LE(x) (OnigUChar)(x), (OnigUChar)((x)>>8)
#define CHARS_32BE(x) CHARS_16BE((x)>>16), CHARS_16BE(x)
#define CHARS_32LE(x) CHARS_16LE(x), CHARS_16LE((x)>>16)
#define CASE_UTF(e) \
      case ENCINDEX_UTF_##e: { \
        static const OnigUChar source_UTF_##e[] = {CHARS_##e('\\'), CHARS_##e('X')}; \
        source = source_UTF_##e; \
        source_len = sizeof(source_UTF_##e); \
        break; \
      }
        CASE_UTF(16BE); CASE_UTF(16LE); CASE_UTF(32BE); CASE_UTF(32LE);
#undef CASE_UTF
#undef CHARS_16BE
#undef CHARS_16LE
#undef CHARS_32BE
#undef CHARS_32LE
    }

    regex_t *reg_grapheme_cluster;
    OnigErrorInfo einfo;
    int r = onig_new(&reg_grapheme_cluster, source, source + source_len,
                        ONIG_OPTION_DEFAULT, enc, OnigDefaultSyntax, &einfo);
    if (r) {
        UChar message[ONIG_MAX_ERROR_MESSAGE_LEN];
        onig_error_code_to_str(message, r, &einfo);
        rb_fatal("cannot compile grapheme cluster regexp: %s", (char *)message);
    }

    return reg_grapheme_cluster;
}

static regex_t *
get_cached_reg_grapheme_cluster(rb_encoding *enc)
{
    int encidx = rb_enc_to_index(enc);
    static regex_t *reg_grapheme_cluster_utf8 = NULL;

    if (encidx == rb_utf8_encindex()) {
        if (!reg_grapheme_cluster_utf8) {
            reg_grapheme_cluster_utf8 = get_reg_grapheme_cluster(enc);
        }

        return reg_grapheme_cluster_utf8;
    }

    return NULL;
}

static VALUE
rb_str_each_grapheme_cluster_size(VALUE str, VALUE args, VALUE eobj)
{
    size_t grapheme_cluster_count = 0;
    rb_encoding *enc = get_encoding(str);
    const char *ptr, *end;

    if (!rb_enc_unicode_p(enc)) {
        return rb_str_length(str);
    }

    bool cached_reg_grapheme_cluster = true;
    regex_t *reg_grapheme_cluster = get_cached_reg_grapheme_cluster(enc);
    if (!reg_grapheme_cluster) {
        reg_grapheme_cluster = get_reg_grapheme_cluster(enc);
        cached_reg_grapheme_cluster = false;
    }

    ptr = RSTRING_PTR(str);
    end = RSTRING_END(str);

    while (ptr < end) {
        OnigPosition len = onig_match(reg_grapheme_cluster,
                                      (const OnigUChar *)ptr, (const OnigUChar *)end,
                                      (const OnigUChar *)ptr, NULL, 0);
        if (len <= 0) break;
        grapheme_cluster_count++;
        ptr += len;
    }

    if (!cached_reg_grapheme_cluster) {
        onig_free(reg_grapheme_cluster);
    }

    return SIZET2NUM(grapheme_cluster_count);
}

static VALUE
rb_str_enumerate_grapheme_clusters(VALUE str, VALUE ary)
{
    VALUE orig = str;
    rb_encoding *enc = get_encoding(str);
    const char *ptr0, *ptr, *end;

    if (!rb_enc_unicode_p(enc)) {
        return rb_str_enumerate_chars(str, ary);
    }

    if (!ary) str = rb_str_new_frozen(str);

    bool cached_reg_grapheme_cluster = true;
    regex_t *reg_grapheme_cluster = get_cached_reg_grapheme_cluster(enc);
    if (!reg_grapheme_cluster) {
        reg_grapheme_cluster = get_reg_grapheme_cluster(enc);
        cached_reg_grapheme_cluster = false;
    }

    ptr0 = ptr = RSTRING_PTR(str);
    end = RSTRING_END(str);

    while (ptr < end) {
        OnigPosition len = onig_match(reg_grapheme_cluster,
                                      (const OnigUChar *)ptr, (const OnigUChar *)end,
                                      (const OnigUChar *)ptr, NULL, 0);
        if (len <= 0) break;
        ENUM_ELEM(ary, rb_str_subseq(str, ptr-ptr0, len));
        ptr += len;
    }

    if (!cached_reg_grapheme_cluster) {
        onig_free(reg_grapheme_cluster);
    }

    RB_GC_GUARD(str);
    if (ary)
        return ary;
    else
        return orig;
}

/*
 *  call-seq:
 *    each_grapheme_cluster {|gc| ... } -> self
 *    each_grapheme_cluster             -> enumerator
 *
 *  :include: doc/string/each_grapheme_cluster.rdoc
 *
 */

static VALUE
rb_str_each_grapheme_cluster(VALUE str)
{
    RETURN_SIZED_ENUMERATOR(str, 0, 0, rb_str_each_grapheme_cluster_size);
    return rb_str_enumerate_grapheme_clusters(str, 0);
}

/*
 *  call-seq:
 *    grapheme_clusters -> array_of_grapheme_clusters
 *
 *  :include: doc/string/grapheme_clusters.rdoc
 *
 */

static VALUE
rb_str_grapheme_clusters(VALUE str)
{
    VALUE ary = WANTARRAY("grapheme_clusters", rb_str_strlen(str));
    return rb_str_enumerate_grapheme_clusters(str, ary);
}

static long
chopped_length(VALUE str)
{
    rb_encoding *enc = STR_ENC_GET(str);
    const char *p, *p2, *beg, *end;

    beg = RSTRING_PTR(str);
    end = beg + RSTRING_LEN(str);
    if (beg >= end) return 0;
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
 *    chop! -> self or nil
 *
 *  Like String#chop, but modifies +self+ in place;
 *  returns +nil+ if +self+ is empty, +self+ otherwise.
 *
 *  Related: String#chomp!.
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
 *    chop -> new_string
 *
 *  :include: doc/string/chop.rdoc
 *
 */

static VALUE
rb_str_chop(VALUE str)
{
    return rb_str_subseq(str, 0, chopped_length(str));
}

static long
smart_chomp(VALUE str, const char *e, const char *p)
{
    rb_encoding *enc = rb_enc_get(str);
    if (rb_enc_mbminlen(enc) > 1) {
        const char *pp = rb_enc_left_char_head(p, e-rb_enc_mbminlen(enc), e, enc);
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
        return smart_chomp(str, e, p);
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
                return smart_chomp(str, e, p);
        }
        else {
            if (rb_enc_is_newline(rsptr, rsptr+rslen, enc))
                return smart_chomp(str, e, p);
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

/*!
 * Returns the separator for arguments of rb_str_chomp.
 *
 * @return returns rb_rs ($/) as default, the default value of rb_rs ($/) is "\n".
 */
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

VALUE
rb_str_chomp_string(VALUE str, VALUE rs)
{
    long olen = RSTRING_LEN(str);
    long len = chompped_length(str, rs);
    if (len >= olen) return Qnil;
    str_modify_keep_cr(str);
    STR_SET_LEN(str, len);
    TERM_FILL(&RSTRING_PTR(str)[len], TERM_LEN(str));
    if (ENC_CODERANGE(str) != ENC_CODERANGE_7BIT) {
        ENC_CODERANGE_CLEAR(str);
    }
    return str;
}

/*
 *  call-seq:
 *    chomp!(line_sep = $/) -> self or nil
 *
 *  Like String#chomp, but modifies +self+ in place;
 *  returns +nil+ if no modification made, +self+ otherwise.
 *
 */

static VALUE
rb_str_chomp_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE rs;
    str_modifiable(str);
    if (RSTRING_LEN(str) == 0) return Qnil;
    rs = chomp_rs(argc, argv);
    if (NIL_P(rs)) return Qnil;
    return rb_str_chomp_string(str, rs);
}


/*
 *  call-seq:
 *    chomp(line_sep = $/) -> new_string
 *
 *  :include: doc/string/chomp.rdoc
 *
 */

static VALUE
rb_str_chomp(int argc, VALUE *argv, VALUE str)
{
    VALUE rs = chomp_rs(argc, argv);
    if (NIL_P(rs)) return str_duplicate(rb_cString, str);
    return rb_str_subseq(str, 0, chompped_length(str, rs));
}

static long
lstrip_offset(VALUE str, const char *s, const char *e, rb_encoding *enc)
{
    const char *const start = s;

    if (!s || s >= e) return 0;

    /* remove spaces at head */
    if (single_byte_optimizable(str)) {
        while (s < e && (*s == '\0' || ascii_isspace(*s))) s++;
    }
    else {
        while (s < e) {
            int n;
            unsigned int cc = rb_enc_codepoint_len(s, e, &n, enc);

            if (cc && !rb_isspace(cc)) break;
            s += n;
        }
    }
    return s - start;
}

/*
 *  call-seq:
 *    lstrip! -> self or nil
 *
 *  Like String#lstrip, except that any modifications are made in +self+;
 *  returns +self+ if any modification are made, +nil+ otherwise.
 *
 *  Related: String#rstrip!, String#strip!.
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
        TERM_FILL(start+len, rb_enc_mbminlen(enc));
        return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *    lstrip -> new_string
 *
 *  Returns a copy of +self+ with leading whitespace removed;
 *  see {Whitespace in Strings}[rdoc-ref:String@Whitespace+in+Strings]:
 *
 *    whitespace = "\x00\t\n\v\f\r "
 *    s = whitespace + 'abc' + whitespace
 *    s        # => "\u0000\t\n\v\f\r abc\u0000\t\n\v\f\r "
 *    s.lstrip # => "abc\u0000\t\n\v\f\r "
 *
 *  Related: String#rstrip, String#strip.
 */

static VALUE
rb_str_lstrip(VALUE str)
{
    char *start;
    long len, loffset;
    RSTRING_GETMEM(str, start, len);
    loffset = lstrip_offset(str, start, start+len, STR_ENC_GET(str));
    if (loffset <= 0) return str_duplicate(rb_cString, str);
    return rb_str_subseq(str, loffset, len - loffset);
}

static long
rstrip_offset(VALUE str, const char *s, const char *e, rb_encoding *enc)
{
    const char *t;

    rb_str_check_dummy_enc(enc);
    if (rb_enc_str_coderange(str) == ENC_CODERANGE_BROKEN) {
        rb_raise(rb_eEncCompatError, "invalid byte sequence in %s", rb_enc_name(enc));
    }
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
 *    rstrip! -> self or nil
 *
 *  Like String#rstrip, except that any modifications are made in +self+;
 *  returns +self+ if any modification are made, +nil+ otherwise.
 *
 *  Related: String#lstrip!, String#strip!.
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
        TERM_FILL(start+len, rb_enc_mbminlen(enc));
        return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *    rstrip -> new_string
 *
 *  Returns a copy of the receiver with trailing whitespace removed;
 *  see {Whitespace in Strings}[rdoc-ref:String@Whitespace+in+Strings]:
 *
 *    whitespace = "\x00\t\n\v\f\r "
 *    s = whitespace + 'abc' + whitespace
 *    s        # => "\u0000\t\n\v\f\r abc\u0000\t\n\v\f\r "
 *    s.rstrip # => "\u0000\t\n\v\f\r abc"
 *
 *  Related: String#lstrip, String#strip.
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

    if (roffset <= 0) return str_duplicate(rb_cString, str);
    return rb_str_subseq(str, 0, olen-roffset);
}


/*
 *  call-seq:
 *    strip! -> self or nil
 *
 *  Like String#strip, except that any modifications are made in +self+;
 *  returns +self+ if any modification are made, +nil+ otherwise.
 *
 *  Related: String#lstrip!, String#strip!.
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
        TERM_FILL(start+len, rb_enc_mbminlen(enc));
        return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *    strip -> new_string
 *
 *  Returns a copy of the receiver with leading and trailing whitespace removed;
 *  see {Whitespace in Strings}[rdoc-ref:String@Whitespace+in+Strings]:
 *
 *    whitespace = "\x00\t\n\v\f\r "
 *    s = whitespace + 'abc' + whitespace
 *    s       # => "\u0000\t\n\v\f\r abc\u0000\t\n\v\f\r "
 *    s.strip # => "abc"
 *
 *  Related: String#lstrip, String#rstrip.
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

    if (loffset <= 0 && roffset <= 0) return str_duplicate(rb_cString, str);
    return rb_str_subseq(str, loffset, olen-loffset-roffset);
}

static VALUE
scan_once(VALUE str, VALUE pat, long *start, int set_backref_str)
{
    VALUE result, match;
    struct re_registers *regs;
    int i;
    long end, pos = rb_pat_search(pat, str, *start, set_backref_str);
    if (pos >= 0) {
        if (BUILTIN_TYPE(pat) == T_STRING) {
            regs = NULL;
            end = pos + RSTRING_LEN(pat);
        }
        else {
            match = rb_backref_get();
            regs = RMATCH_REGS(match);
            pos = BEG(0);
            end = END(0);
        }
        if (pos == end) {
            rb_encoding *enc = STR_ENC_GET(str);
            /*
             * Always consume at least one character of the input string
             */
            if (RSTRING_LEN(str) > end)
                *start = end + rb_enc_fast_mbclen(RSTRING_PTR(str) + end,
                                                  RSTRING_END(str), enc);
            else
                *start = end + 1;
        }
        else {
            *start = end;
        }
        if (!regs || regs->num_regs == 1) {
            result = rb_str_subseq(str, pos, end - pos);
            return result;
        }
        result = rb_ary_new2(regs->num_regs);
        for (i=1; i < regs->num_regs; i++) {
            VALUE s = Qnil;
            if (BEG(i) >= 0) {
                s = rb_str_subseq(str, BEG(i), END(i)-BEG(i));
            }
            rb_ary_push(result, s);
        }

        return result;
    }
    return Qnil;
}


/*
 *  call-seq:
 *    scan(string_or_regexp) -> array
 *    scan(string_or_regexp) {|matches| ... } -> self
 *
 *  Matches a pattern against +self+; the pattern is:
 *
 *  - +string_or_regexp+ itself, if it is a Regexp.
 *  - <tt>Regexp.quote(string_or_regexp)</tt>, if +string_or_regexp+ is a string.
 *
 *  Iterates through +self+, generating a collection of matching results:
 *
 *  - If the pattern contains no groups, each result is the
 *    matched string, <code>$&</code>.
 *  - If the pattern contains groups, each result is an array
 *    containing one entry per group.
 *
 *  With no block given, returns an array of the results:
 *
 *    s = 'cruel world'
 *    s.scan(/\w+/)      # => ["cruel", "world"]
 *    s.scan(/.../)      # => ["cru", "el ", "wor"]
 *    s.scan(/(...)/)    # => [["cru"], ["el "], ["wor"]]
 *    s.scan(/(..)(..)/) # => [["cr", "ue"], ["l ", "wo"]]
 *
 *  With a block given, calls the block with each result; returns +self+:
 *
 *    s.scan(/\w+/) {|w| print "<<#{w}>> " }
 *    print "\n"
 *    s.scan(/(.)(.)/) {|x,y| print y, x }
 *    print "\n"
 *
 *  Output:
 *
 *     <<cruel>> <<world>>
 *     rceu lowlr
 *
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

        while (!NIL_P(result = scan_once(str, pat, &start, 0))) {
            last = prev;
            prev = start;
            rb_ary_push(ary, result);
        }
        if (last >= 0) rb_pat_search(pat, str, last, 1);
        else rb_backref_set(Qnil);
        return ary;
    }

    while (!NIL_P(result = scan_once(str, pat, &start, 1))) {
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
 *    hex -> integer
 *
 *  Interprets the leading substring of +self+ as a string of hexadecimal digits
 *  (with an optional sign and an optional <code>0x</code>) and returns the
 *  corresponding number;
 *  returns zero if there is no such leading substring:
 *
 *    '0x0a'.hex        # => 10
 *    '-1234'.hex       # => -4660
 *    '0'.hex           # => 0
 *    'non-numeric'.hex # => 0
 *
 *  Related: String#oct.
 *
 */

static VALUE
rb_str_hex(VALUE str)
{
    return rb_str_to_inum(str, 16, FALSE);
}


/*
 *  call-seq:
 *    oct -> integer
 *
 *  Interprets the leading substring of +self+ as a string of octal digits
 *  (with an optional sign) and returns the corresponding number;
 *  returns zero if there is no such leading substring:
 *
 *    '123'.oct             # => 83
 *    '-377'.oct            # => -255
 *    '0377non-numeric'.oct # => 255
 *    'non-numeric'.oct     # => 0
 *
 *  If +self+ starts with <tt>0</tt>, radix indicators are honored;
 *  see Kernel#Integer.
 *
 *  Related: String#hex.
 *
 */

static VALUE
rb_str_oct(VALUE str)
{
    return rb_str_to_inum(str, -8, FALSE);
}

#ifndef HAVE_CRYPT_R
# include "ruby/thread_native.h"
# include "ruby/atomic.h"

static struct {
    rb_nativethread_lock_t lock;
} crypt_mutex = {PTHREAD_MUTEX_INITIALIZER};

static void
crypt_mutex_initialize(void)
{
}
#endif

/*
 *  call-seq:
 *    crypt(salt_str) -> new_string
 *
 *  Returns the string generated by calling <code>crypt(3)</code>
 *  standard library function with <code>str</code> and
 *  <code>salt_str</code>, in this order, as its arguments.  Please do
 *  not use this method any longer.  It is legacy; provided only for
 *  backward compatibility with ruby scripts in earlier days.  It is
 *  bad to use in contemporary programs for several reasons:
 *
 *  * Behaviour of C's <code>crypt(3)</code> depends on the OS it is
 *    run.  The generated string lacks data portability.
 *
 *  * On some OSes such as Mac OS, <code>crypt(3)</code> never fails
 *    (i.e. silently ends up in unexpected results).
 *
 *  * On some OSes such as Mac OS, <code>crypt(3)</code> is not
 *    thread safe.
 *
 *  * So-called "traditional" usage of <code>crypt(3)</code> is very
 *    very very weak.  According to its manpage, Linux's traditional
 *    <code>crypt(3)</code> output has only 2**56 variations; too
 *    easy to brute force today.  And this is the default behaviour.
 *
 *  * In order to make things robust some OSes implement so-called
 *    "modular" usage. To go through, you have to do a complex
 *    build-up of the <code>salt_str</code> parameter, by hand.
 *    Failure in generation of a proper salt string tends not to
 *    yield any errors; typos in parameters are normally not
 *    detectable.
 *
 *    * For instance, in the following example, the second invocation
 *      of String#crypt is wrong; it has a typo in "round=" (lacks
 *      "s").  However the call does not fail and something unexpected
 *      is generated.
 *
 *         "foo".crypt("$5$rounds=1000$salt$") # OK, proper usage
 *         "foo".crypt("$5$round=1000$salt$")  # Typo not detected
 *
 *  * Even in the "modular" mode, some hash functions are considered
 *    archaic and no longer recommended at all; for instance module
 *    <code>$1$</code> is officially abandoned by its author: see
 *    http://phk.freebsd.dk/sagas/md5crypt_eol/ .  For another
 *    instance module <code>$3$</code> is considered completely
 *    broken: see the manpage of FreeBSD.
 *
 *  * On some OS such as Mac OS, there is no modular mode. Yet, as
 *    written above, <code>crypt(3)</code> on Mac OS never fails.
 *    This means even if you build up a proper salt string it
 *    generates a traditional DES hash anyways, and there is no way
 *    for you to be aware of.
 *
 *        "foo".crypt("$5$rounds=1000$salt$") # => "$5fNPQMxC5j6."
 *
 *  If for some reason you cannot migrate to other secure contemporary
 *  password hashing algorithms, install the string-crypt gem and
 *  <code>require 'string/crypt'</code> to continue using it.
 */

static VALUE
rb_str_crypt(VALUE str, VALUE salt)
{
#ifdef HAVE_CRYPT_R
    VALUE databuf;
    struct crypt_data *data;
#   define CRYPT_END() ALLOCV_END(databuf)
#else
    extern char *crypt(const char *, const char *);
#   define CRYPT_END() rb_nativethread_lock_unlock(&crypt_mutex.lock)
#endif
    VALUE result;
    const char *s, *saltp;
    char *res;
#ifdef BROKEN_CRYPT
    char salt_8bit_clean[3];
#endif

    StringValue(salt);
    mustnot_wchar(str);
    mustnot_wchar(salt);
    s = StringValueCStr(str);
    saltp = RSTRING_PTR(salt);
    if (RSTRING_LEN(salt) < 2 || !saltp[0] || !saltp[1]) {
        rb_raise(rb_eArgError, "salt too short (need >=2 bytes)");
    }

#ifdef BROKEN_CRYPT
    if (!ISASCII((unsigned char)saltp[0]) || !ISASCII((unsigned char)saltp[1])) {
        salt_8bit_clean[0] = saltp[0] & 0x7f;
        salt_8bit_clean[1] = saltp[1] & 0x7f;
        salt_8bit_clean[2] = '\0';
        saltp = salt_8bit_clean;
    }
#endif
#ifdef HAVE_CRYPT_R
    data = ALLOCV(databuf, sizeof(struct crypt_data));
# ifdef HAVE_STRUCT_CRYPT_DATA_INITIALIZED
    data->initialized = 0;
# endif
    res = crypt_r(s, saltp, data);
#else
    crypt_mutex_initialize();
    rb_nativethread_lock_lock(&crypt_mutex.lock);
    res = crypt(s, saltp);
#endif
    if (!res) {
        int err = errno;
        CRYPT_END();
        rb_syserr_fail(err, "crypt");
    }
    result = rb_str_new_cstr(res);
    CRYPT_END();
    return result;
}


/*
 *  call-seq:
 *    ord -> integer
 *
 *  :include: doc/string/ord.rdoc
 *
 */

static VALUE
rb_str_ord(VALUE s)
{
    unsigned int c;

    c = rb_enc_codepoint(RSTRING_PTR(s), RSTRING_END(s), STR_ENC_GET(s));
    return UINT2NUM(c);
}
/*
 *  call-seq:
 *    sum(n = 16) -> integer
 *
 *  :include: doc/string/sum.rdoc
 *
 */

static VALUE
rb_str_sum(int argc, VALUE *argv, VALUE str)
{
    int bits = 16;
    char *ptr, *p, *pend;
    long len;
    VALUE sum = INT2FIX(0);
    unsigned long sum0 = 0;

    if (rb_check_arity(argc, 0, 1) && (bits = NUM2INT(argv[0])) < 0) {
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
    if (width < 0 || len >= width) return str_duplicate(rb_cString, str);
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
    res = str_new0(rb_cString, 0, len, termlen);
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
 *    ljust(size, pad_string = ' ') -> new_string
 *
 *  :include: doc/string/ljust.rdoc
 *
 *  Related: String#rjust, String#center.
 *
 */

static VALUE
rb_str_ljust(int argc, VALUE *argv, VALUE str)
{
    return rb_str_justify(argc, argv, str, 'l');
}

/*
 *  call-seq:
 *    rjust(size, pad_string = ' ') -> new_string
 *
 *  :include: doc/string/rjust.rdoc
 *
 *  Related: String#ljust, String#center.
 *
 */

static VALUE
rb_str_rjust(int argc, VALUE *argv, VALUE str)
{
    return rb_str_justify(argc, argv, str, 'r');
}


/*
 *  call-seq:
 *    center(size, pad_string = ' ') -> new_string
 *
 *  :include: doc/string/center.rdoc
 *
 *  Related: String#ljust, String#rjust.
 *
 */

static VALUE
rb_str_center(int argc, VALUE *argv, VALUE str)
{
    return rb_str_justify(argc, argv, str, 'c');
}

/*
 *  call-seq:
 *    partition(string_or_regexp) -> [head, match, tail]
 *
 *  :include: doc/string/partition.rdoc
 *
 */

static VALUE
rb_str_partition(VALUE str, VALUE sep)
{
    long pos;

    sep = get_pat_quoted(sep, 0);
    if (RB_TYPE_P(sep, T_REGEXP)) {
        if (rb_reg_search(sep, str, 0, 0) < 0) {
            goto failed;
        }
        VALUE match = rb_backref_get();
        struct re_registers *regs = RMATCH_REGS(match);

        pos = BEG(0);
        sep = rb_str_subseq(str, pos, END(0) - pos);
    }
    else {
        pos = rb_str_index(str, sep, 0);
        if (pos < 0) goto failed;
    }
    return rb_ary_new3(3, rb_str_subseq(str, 0, pos),
                          sep,
                          rb_str_subseq(str, pos+RSTRING_LEN(sep),
                                             RSTRING_LEN(str)-pos-RSTRING_LEN(sep)));

  failed:
    return rb_ary_new3(3, str_duplicate(rb_cString, str), str_new_empty_String(str), str_new_empty_String(str));
}

/*
 *  call-seq:
 *    rpartition(sep) -> [head, match, tail]
 *
 *  :include: doc/string/rpartition.rdoc
 *
 */

static VALUE
rb_str_rpartition(VALUE str, VALUE sep)
{
    long pos = RSTRING_LEN(str);

    sep = get_pat_quoted(sep, 0);
    if (RB_TYPE_P(sep, T_REGEXP)) {
        if (rb_reg_search(sep, str, pos, 1) < 0) {
            goto failed;
        }
        VALUE match = rb_backref_get();
        struct re_registers *regs = RMATCH_REGS(match);

        pos = BEG(0);
        sep = rb_str_subseq(str, pos, END(0) - pos);
    }
    else {
        pos = rb_str_sublen(str, pos);
        pos = rb_str_rindex(str, sep, pos);
        if (pos < 0) {
            goto failed;
        }
        pos = rb_str_offset(str, pos);
    }

    return rb_ary_new3(3, rb_str_subseq(str, 0, pos),
                          sep,
                          rb_str_subseq(str, pos+RSTRING_LEN(sep),
                                        RSTRING_LEN(str)-pos-RSTRING_LEN(sep)));
  failed:
    return rb_ary_new3(3, str_new_empty_String(str), str_new_empty_String(str), str_duplicate(rb_cString, str));
}

/*
 *  call-seq:
 *    start_with?(*string_or_regexp) -> true or false
 *
 *  :include: doc/string/start_with_p.rdoc
 *
 */

static VALUE
rb_str_start_with(int argc, VALUE *argv, VALUE str)
{
    int i;

    for (i=0; i<argc; i++) {
        VALUE tmp = argv[i];
        if (RB_TYPE_P(tmp, T_REGEXP)) {
            if (rb_reg_start_with_p(tmp, str))
                return Qtrue;
        }
        else {
            StringValue(tmp);
            rb_enc_check(str, tmp);
            if (RSTRING_LEN(str) < RSTRING_LEN(tmp)) continue;
            if (memcmp(RSTRING_PTR(str), RSTRING_PTR(tmp), RSTRING_LEN(tmp)) == 0)
                return Qtrue;
        }
    }
    return Qfalse;
}

/*
 *  call-seq:
 *    end_with?(*strings) -> true or false
 *
 *  :include: doc/string/end_with_p.rdoc
 *
 */

static VALUE
rb_str_end_with(int argc, VALUE *argv, VALUE str)
{
    int i;
    char *p, *s, *e;
    rb_encoding *enc;

    for (i=0; i<argc; i++) {
        VALUE tmp = argv[i];
        long slen, tlen;
        StringValue(tmp);
        enc = rb_enc_check(str, tmp);
        if ((tlen = RSTRING_LEN(tmp)) == 0) return Qtrue;
        if ((slen = RSTRING_LEN(str)) < tlen) continue;
        p = RSTRING_PTR(str);
        e = p + slen;
        s = e - tlen;
        if (rb_enc_left_char_head(p, s, e, enc) != s)
            continue;
        if (memcmp(s, RSTRING_PTR(tmp), RSTRING_LEN(tmp)) == 0)
            return Qtrue;
    }
    return Qfalse;
}

/*!
 * Returns the length of the <i>prefix</i> to be deleted in the given <i>str</i>,
 * returning 0 if <i>str</i> does not start with the <i>prefix</i>.
 *
 * @param str the target
 * @param prefix the prefix
 * @retval 0 if the given <i>str</i> does not start with the given <i>prefix</i>
 * @retval Positive-Integer otherwise
 */
static long
deleted_prefix_length(VALUE str, VALUE prefix)
{
    char *strptr, *prefixptr;
    long olen, prefixlen;

    StringValue(prefix);
    if (is_broken_string(prefix)) return 0;
    rb_enc_check(str, prefix);

    /* return 0 if not start with prefix */
    prefixlen = RSTRING_LEN(prefix);
    if (prefixlen <= 0) return 0;
    olen = RSTRING_LEN(str);
    if (olen < prefixlen) return 0;
    strptr = RSTRING_PTR(str);
    prefixptr = RSTRING_PTR(prefix);
    if (memcmp(strptr, prefixptr, prefixlen) != 0) return 0;

    return prefixlen;
}

/*
 *  call-seq:
 *    delete_prefix!(prefix) -> self or nil
 *
 *  Like String#delete_prefix, except that +self+ is modified in place.
 *  Returns +self+ if the prefix is removed, +nil+ otherwise.
 *
 */

static VALUE
rb_str_delete_prefix_bang(VALUE str, VALUE prefix)
{
    long prefixlen;
    str_modify_keep_cr(str);

    prefixlen = deleted_prefix_length(str, prefix);
    if (prefixlen <= 0) return Qnil;

    return rb_str_drop_bytes(str, prefixlen);
}

/*
 *  call-seq:
 *    delete_prefix(prefix) -> new_string
 *
 *  :include: doc/string/delete_prefix.rdoc
 *
 */

static VALUE
rb_str_delete_prefix(VALUE str, VALUE prefix)
{
    long prefixlen;

    prefixlen = deleted_prefix_length(str, prefix);
    if (prefixlen <= 0) return str_duplicate(rb_cString, str);

    return rb_str_subseq(str, prefixlen, RSTRING_LEN(str) - prefixlen);
}

/*!
 * Returns the length of the <i>suffix</i> to be deleted in the given <i>str</i>,
 * returning 0 if <i>str</i> does not end with the <i>suffix</i>.
 *
 * @param str the target
 * @param suffix the suffix
 * @retval 0 if the given <i>str</i> does not end with the given <i>suffix</i>
 * @retval Positive-Integer otherwise
 */
static long
deleted_suffix_length(VALUE str, VALUE suffix)
{
    char *strptr, *suffixptr, *s;
    long olen, suffixlen;
    rb_encoding *enc;

    StringValue(suffix);
    if (is_broken_string(suffix)) return 0;
    enc = rb_enc_check(str, suffix);

    /* return 0 if not start with suffix */
    suffixlen = RSTRING_LEN(suffix);
    if (suffixlen <= 0) return 0;
    olen = RSTRING_LEN(str);
    if (olen < suffixlen) return 0;
    strptr = RSTRING_PTR(str);
    suffixptr = RSTRING_PTR(suffix);
    s = strptr + olen - suffixlen;
    if (memcmp(s, suffixptr, suffixlen) != 0) return 0;
    if (rb_enc_left_char_head(strptr, s, strptr + olen, enc) != s) return 0;

    return suffixlen;
}

/*
 *  call-seq:
 *    delete_suffix!(suffix) -> self or nil
 *
 *  Like String#delete_suffix, except that +self+ is modified in place.
 *  Returns +self+ if the suffix is removed, +nil+ otherwise.
 *
 */

static VALUE
rb_str_delete_suffix_bang(VALUE str, VALUE suffix)
{
    long olen, suffixlen, len;
    str_modifiable(str);

    suffixlen = deleted_suffix_length(str, suffix);
    if (suffixlen <= 0) return Qnil;

    olen = RSTRING_LEN(str);
    str_modify_keep_cr(str);
    len = olen - suffixlen;
    STR_SET_LEN(str, len);
    TERM_FILL(&RSTRING_PTR(str)[len], TERM_LEN(str));
    if (ENC_CODERANGE(str) != ENC_CODERANGE_7BIT) {
        ENC_CODERANGE_CLEAR(str);
    }
    return str;
}

/*
 *  call-seq:
 *    delete_suffix(suffix) -> new_string
 *
 *  :include: doc/string/delete_suffix.rdoc
 *
 */

static VALUE
rb_str_delete_suffix(VALUE str, VALUE suffix)
{
    long suffixlen;

    suffixlen = deleted_suffix_length(str, suffix);
    if (suffixlen <= 0) return str_duplicate(rb_cString, str);

    return rb_str_subseq(str, 0, RSTRING_LEN(str) - suffixlen);
}

void
rb_str_setter(VALUE val, ID id, VALUE *var)
{
    if (!NIL_P(val) && !RB_TYPE_P(val, T_STRING)) {
        rb_raise(rb_eTypeError, "value of %"PRIsVALUE" must be String", rb_id2str(id));
    }
    *var = val;
}

static void
rb_fs_setter(VALUE val, ID id, VALUE *var)
{
    val = rb_fs_check(val);
    if (!val) {
        rb_raise(rb_eTypeError,
                 "value of %"PRIsVALUE" must be String or Regexp",
                 rb_id2str(id));
    }
    if (!NIL_P(val)) {
        rb_warn_deprecated("`$;'", NULL);
    }
    *var = val;
}


/*
 *  call-seq:
 *    force_encoding(encoding) -> self
 *
 *  :include: doc/string/force_encoding.rdoc
 *
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
 *    b -> string
 *
 *  :include: doc/string/b.rdoc
 *
 */

static VALUE
rb_str_b(VALUE str)
{
    VALUE str2;
    if (FL_TEST(str, STR_NOEMBED)) {
        str2 = str_alloc_heap(rb_cString);
    }
    else {
        str2 = str_alloc_embed(rb_cString, RSTRING_EMBED_LEN(str) + TERM_LEN(str));
    }
    str_replace_shared_without_enc(str2, str);

    if (rb_enc_asciicompat(STR_ENC_GET(str))) {
        // BINARY strings can never be broken; they're either 7-bit ASCII or VALID.
        // If we know the receiver's code range then we know the result's code range.
        int cr = ENC_CODERANGE(str);
        switch (cr) {
          case ENC_CODERANGE_7BIT:
            ENC_CODERANGE_SET(str2, ENC_CODERANGE_7BIT);
            break;
          case ENC_CODERANGE_BROKEN:
          case ENC_CODERANGE_VALID:
            ENC_CODERANGE_SET(str2, ENC_CODERANGE_VALID);
            break;
          default:
            ENC_CODERANGE_CLEAR(str2);
            break;
        }
    }

    return str2;
}

/*
 *  call-seq:
 *    valid_encoding? -> true or false
 *
 *  Returns +true+ if +self+ is encoded correctly, +false+ otherwise:
 *
 *    "\xc2\xa1".force_encoding("UTF-8").valid_encoding? # => true
 *    "\xc2".force_encoding("UTF-8").valid_encoding?     # => false
 *    "\x80".force_encoding("UTF-8").valid_encoding?     # => false
 */

static VALUE
rb_str_valid_encoding_p(VALUE str)
{
    int cr = rb_enc_str_coderange(str);

    return RBOOL(cr != ENC_CODERANGE_BROKEN);
}

/*
 *  call-seq:
 *    ascii_only? -> true or false
 *
 *  Returns +true+ if +self+ contains only ASCII characters,
 *  +false+ otherwise:
 *
 *    'abc'.ascii_only?         # => true
 *    "abc\u{6666}".ascii_only? # => false
 *
 */

static VALUE
rb_str_is_ascii_only_p(VALUE str)
{
    int cr = rb_enc_str_coderange(str);

    return RBOOL(cr == ENC_CODERANGE_7BIT);
}

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
            ret = rb_str_new(ellipsis, len);
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

static VALUE enc_str_scrub(rb_encoding *enc, VALUE str, VALUE repl, int cr);

VALUE
rb_str_scrub(VALUE str, VALUE repl)
{
    rb_encoding *enc = STR_ENC_GET(str);
    return enc_str_scrub(enc, str, repl, ENC_CODERANGE(str));
}

VALUE
rb_enc_str_scrub(rb_encoding *enc, VALUE str, VALUE repl)
{
    int cr = ENC_CODERANGE_UNKNOWN;
    if (enc == STR_ENC_GET(str)) {
        /* cached coderange makes sense only when enc equals the
         * actual encoding of str */
        cr = ENC_CODERANGE(str);
    }
    return enc_str_scrub(enc, str, repl, cr);
}

static VALUE
enc_str_scrub(rb_encoding *enc, VALUE str, VALUE repl, int cr)
{
    int encidx;
    VALUE buf = Qnil;
    const char *rep, *p, *e, *p1, *sp;
    long replen = -1;
    long slen;

    if (rb_block_given_p()) {
        if (!NIL_P(repl))
            rb_raise(rb_eArgError, "both of block and replacement given");
        replen = 0;
    }

    if (ENC_CODERANGE_CLEAN_P(cr))
        return Qnil;

    if (!NIL_P(repl)) {
        repl = str_compat_and_valid(repl, enc);
    }

    if (rb_enc_dummy_p(enc)) {
        return Qnil;
    }
    encidx = rb_enc_to_index(enc);

#define DEFAULT_REPLACE_CHAR(str) do { \
        static const char replace[sizeof(str)-1] = str; \
        rep = replace; replen = (int)sizeof(replace); \
    } while (0)

    slen = RSTRING_LEN(str);
    p = RSTRING_PTR(str);
    e = RSTRING_END(str);
    p1 = p;
    sp = p;

    if (rb_enc_asciicompat(enc)) {
        int rep7bit_p;
        if (!replen) {
            rep = NULL;
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
                    str_mod_check(str, sp, slen);
                    repl = str_compat_and_valid(repl, enc);
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
                str_mod_check(str, sp, slen);
                repl = str_compat_and_valid(repl, enc);
                rb_str_buf_cat(buf, RSTRING_PTR(repl), RSTRING_LEN(repl));
                if (ENC_CODERANGE(repl) == ENC_CODERANGE_VALID)
                    cr = ENC_CODERANGE_VALID;
            }
        }
    }
    else {
        /* ASCII incompatible */
        long mbminlen = rb_enc_mbminlen(enc);
        if (!replen) {
            rep = NULL;
        }
        else if (!NIL_P(repl)) {
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
                    repl = rb_yield(rb_enc_str_new(p, clen, enc));
                    str_mod_check(str, sp, slen);
                    repl = str_compat_and_valid(repl, enc);
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
                str_mod_check(str, sp, slen);
                repl = str_compat_and_valid(repl, enc);
                rb_str_buf_cat(buf, RSTRING_PTR(repl), RSTRING_LEN(repl));
            }
        }
        cr = ENC_CODERANGE_VALID;
    }
    ENCODING_CODERANGE_SET(buf, rb_enc_to_index(enc), cr);
    return buf;
}

/*
 *  call-seq:
 *    scrub(replacement_string = default_replacement) -> new_string
 *    scrub{|bytes| ... } -> new_string
 *
 *  :include: doc/string/scrub.rdoc
 *
 */
static VALUE
str_scrub(int argc, VALUE *argv, VALUE str)
{
    VALUE repl = argc ? (rb_check_arity(argc, 0, 1), argv[0]) : Qnil;
    VALUE new = rb_str_scrub(str, repl);
    return NIL_P(new) ? str_duplicate(rb_cString, str): new;
}

/*
 *  call-seq:
 *    scrub! -> self
 *    scrub!(replacement_string = default_replacement) -> self
 *    scrub!{|bytes| ... } -> self
 *
 *  Like String#scrub, except that any replacements are made in +self+.
 *
 */
static VALUE
str_scrub_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE repl = argc ? (rb_check_arity(argc, 0, 1), argv[0]) : Qnil;
    VALUE new = rb_str_scrub(str, repl);
    if (!NIL_P(new)) rb_str_replace(str, new);
    return str;
}

static ID id_normalize;
static ID id_normalized_p;
static VALUE mUnicodeNormalize;

static VALUE
unicode_normalize_common(int argc, VALUE *argv, VALUE str, ID id)
{
    static int UnicodeNormalizeRequired = 0;
    VALUE argv2[2];

    if (!UnicodeNormalizeRequired) {
        rb_require("unicode_normalize/normalize.rb");
        UnicodeNormalizeRequired = 1;
    }
    argv2[0] = str;
    if (rb_check_arity(argc, 0, 1)) argv2[1] = argv[0];
    return rb_funcallv(mUnicodeNormalize, id, argc+1, argv2);
}

/*
 *  call-seq:
 *    unicode_normalize(form = :nfc) -> string
 *
 *  Returns a copy of +self+ with
 *  {Unicode normalization}[https://unicode.org/reports/tr15] applied.
 *
 *  Argument +form+ must be one of the following symbols
 *  (see {Unicode normalization forms}[https://unicode.org/reports/tr15/#Norm_Forms]):
 *
 *  - +:nfc+: Canonical decomposition, followed by canonical composition.
 *  - +:nfd+: Canonical decomposition.
 *  - +:nfkc+: Compatibility decomposition, followed by canonical composition.
 *  - +:nfkd+: Compatibility decomposition.
 *
 *  The encoding of +self+ must be one of:
 *
 *  - Encoding::UTF_8
 *  - Encoding::UTF_16BE
 *  - Encoding::UTF_16LE
 *  - Encoding::UTF_32BE
 *  - Encoding::UTF_32LE
 *  - Encoding::GB18030
 *  - Encoding::UCS_2BE
 *  - Encoding::UCS_4BE
 *
 *  Examples:
 *
 *    "a\u0300".unicode_normalize      # => "a"
 *    "\u00E0".unicode_normalize(:nfd) # => "a "
 *
 *  Related: String#unicode_normalize!, String#unicode_normalized?.
 */
static VALUE
rb_str_unicode_normalize(int argc, VALUE *argv, VALUE str)
{
    return unicode_normalize_common(argc, argv, str, id_normalize);
}

/*
 *  call-seq:
 *    unicode_normalize!(form = :nfc) -> self
 *
 *  Like String#unicode_normalize, except that the normalization
 *  is performed on +self+.
 *
 *  Related String#unicode_normalized?.
 *
 */
static VALUE
rb_str_unicode_normalize_bang(int argc, VALUE *argv, VALUE str)
{
    return rb_str_replace(str, unicode_normalize_common(argc, argv, str, id_normalize));
}

/*  call-seq:
 *   unicode_normalized?(form = :nfc) -> true or false
 *
 *  Returns +true+ if +self+ is in the given +form+ of Unicode normalization,
 *  +false+ otherwise.
 *  The +form+ must be one of +:nfc+, +:nfd+, +:nfkc+, or +:nfkd+.
 *
 *  Examples:
 *
 *    "a\u0300".unicode_normalized?       # => false
 *    "a\u0300".unicode_normalized?(:nfd) # => true
 *    "\u00E0".unicode_normalized?        # => true
 *    "\u00E0".unicode_normalized?(:nfd)  # => false
 *
 *
 *  Raises an exception if +self+ is not in a Unicode encoding:
 *
 *    s = "\xE0".force_encoding('ISO-8859-1')
 *    s.unicode_normalized? # Raises Encoding::CompatibilityError.
 *
 *  Related: String#unicode_normalize, String#unicode_normalize!.
 *
 */
static VALUE
rb_str_unicode_normalized_p(int argc, VALUE *argv, VALUE str)
{
    return unicode_normalize_common(argc, argv, str, id_normalized_p);
}

/**********************************************************************
 * Document-class: Symbol
 *
 * Symbol objects represent named identifiers inside the Ruby interpreter.
 *
 * You can create a \Symbol object explicitly with:
 *
 * - A {symbol literal}[rdoc-ref:syntax/literals.rdoc@Symbol+Literals].
 *
 * The same Symbol object will be
 * created for a given name or string for the duration of a program's
 * execution, regardless of the context or meaning of that name. Thus
 * if <code>Fred</code> is a constant in one context, a method in
 * another, and a class in a third, the Symbol <code>:Fred</code>
 * will be the same object in all three contexts.
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
 * Constant, method, and variable names are returned as symbols:
 *
 *     module One
 *       Two = 2
 *       def three; 3 end
 *       @four = 4
 *       @@five = 5
 *       $six = 6
 *     end
 *     seven = 7
 *
 *     One.constants
 *     # => [:Two]
 *     One.instance_methods(true)
 *     # => [:three]
 *     One.instance_variables
 *     # => [:@four]
 *     One.class_variables
 *     # => [:@@five]
 *     global_variables.grep(/six/)
 *     # => [:$six]
 *     local_variables
 *     # => [:seven]
 *
 * Symbol objects are different from String objects in that
 * Symbol objects represent identifiers, while String objects
 * represent text or data.
 *
 * == What's Here
 *
 * First, what's elsewhere. \Class \Symbol:
 *
 * - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 * - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
 *
 * Here, class \Symbol provides methods that are useful for:
 *
 * - {Querying}[rdoc-ref:Symbol@Methods+for+Querying]
 * - {Comparing}[rdoc-ref:Symbol@Methods+for+Comparing]
 * - {Converting}[rdoc-ref:Symbol@Methods+for+Converting]
 *
 * === Methods for Querying
 *
 * - ::all_symbols: Returns an array of the symbols currently in Ruby's symbol table.
 * - #=~: Returns the index of the first substring in symbol that matches a
 *   given Regexp or other object; returns +nil+ if no match is found.
 * - #[], #slice : Returns a substring of symbol
 *   determined by a given index, start/length, or range, or string.
 * - #empty?: Returns +true+ if +self.length+ is zero; +false+ otherwise.
 * - #encoding: Returns the Encoding object that represents the encoding
 *   of symbol.
 * - #end_with?: Returns +true+ if symbol ends with
 *   any of the given strings.
 * - #match: Returns a MatchData object if symbol
 *   matches a given Regexp; +nil+ otherwise.
 * - #match?: Returns +true+ if symbol
 *   matches a given Regexp; +false+ otherwise.
 * - #length, #size: Returns the number of characters in symbol.
 * - #start_with?: Returns +true+ if symbol starts with
 *   any of the given strings.
 *
 * === Methods for Comparing
 *
 * - #<=>: Returns -1, 0, or 1 as a given symbol is smaller than, equal to,
 *   or larger than symbol.
 * - #==, #===: Returns +true+ if a given symbol has the same content and
 *   encoding.
 * - #casecmp: Ignoring case, returns -1, 0, or 1 as a given
 *   symbol is smaller than, equal to, or larger than symbol.
 * - #casecmp?: Returns +true+ if symbol is equal to a given symbol
 *   after Unicode case folding; +false+ otherwise.
 *
 * === Methods for Converting
 *
 * - #capitalize: Returns symbol with the first character upcased
 *   and all other characters downcased.
 * - #downcase: Returns symbol with all characters downcased.
 * - #inspect: Returns the string representation of +self+ as a symbol literal.
 * - #name: Returns the frozen string corresponding to symbol.
 * - #succ, #next: Returns the symbol that is the successor to symbol.
 * - #swapcase: Returns symbol with all upcase characters downcased
 *   and all downcase characters upcased.
 * - #to_proc: Returns a Proc object which responds to the method named by symbol.
 * - #to_s, #id2name: Returns the string corresponding to +self+.
 * - #to_sym, #intern: Returns +self+.
 * - #upcase: Returns symbol with all characters upcased.
 *
 */


/*
 *  call-seq:
 *    symbol == object -> true or false
 *
 *  Returns +true+ if +object+ is the same object as +self+, +false+ otherwise.
 *
 *  Symbol#=== is an alias for Symbol#==.
 *
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
        !rb_enc_symname2_p(ptr, len, enc) || !sym_printable(ptr, ptr + len, enc)) {
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
        return rb_str_escape(str);
    }
    return str;
}

MJIT_FUNC_EXPORTED VALUE
rb_id_quote_unprintable(ID id)
{
    VALUE str = rb_id2str(id);
    if (!rb_str_symname_p(str)) {
        return rb_str_escape(str);
    }
    return str;
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+ (including the leading colon):
 *
 *    :foo.inspect # => ":foo"
 *
 *  Related:  Symbol#to_s, Symbol#name.
 *
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
 *    to_s -> string
 *
 *  Returns a string representation of +self+ (not including the leading colon):
 *
 *    :foo.to_s # => "foo"
 *
 *  Symbol#id2name is an alias for Symbol#to_s.
 *
 *  Related: Symbol#inspect, Symbol#name.
 */

VALUE
rb_sym_to_s(VALUE sym)
{
    return str_new_shared(rb_cString, rb_sym2str(sym));
}

MJIT_FUNC_EXPORTED VALUE
rb_sym_proc_call(ID mid, int argc, const VALUE *argv, int kw_splat, VALUE passed_proc)
{
    VALUE obj;

    if (argc < 1) {
        rb_raise(rb_eArgError, "no receiver given");
    }
    obj = argv[0];
    return rb_funcall_with_block_kw(obj, mid, argc - 1, argv + 1, passed_proc, kw_splat);
}

/*
 *  call-seq:
 *    succ
 *
 *  Equivalent to <tt>self.to_s.succ.to_sym</tt>:
 *
 *    :foo.succ # => :fop
 *
 *  Symbol#next is an alias for Symbol#succ.
 *
 *  Related: String#succ.
 */

static VALUE
sym_succ(VALUE sym)
{
    return rb_str_intern(rb_str_succ(rb_sym2str(sym)));
}

/*
 *  call-seq:
 *   symbol <=> object -> -1, 0, +1, or nil
 *
 *  If +object+ is a symbol,
 *  returns the equivalent of <tt>symbol.to_s <=> object.to_s</tt>:
 *
 *    :bar <=> :foo # => -1
 *    :foo <=> :foo # => 0
 *    :foo <=> :bar # => 1
 *
 *  Otherwise, returns +nil+:
 *
 *   :foo <=> 'bar' # => nil
 *
 *  Related: String#<=>.
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
 *  call-seq:
 *    casecmp(object) -> -1, 0, 1, or nil
 *
 *  :include: doc/symbol/casecmp.rdoc
 *
 */

static VALUE
sym_casecmp(VALUE sym, VALUE other)
{
    if (!SYMBOL_P(other)) {
        return Qnil;
    }
    return str_casecmp(rb_sym2str(sym), rb_sym2str(other));
}

/*
 *  call-seq:
 *    casecmp?(object) -> true, false, or nil
 *
 *  :include: doc/symbol/casecmp_p.rdoc
 *
 */

static VALUE
sym_casecmp_p(VALUE sym, VALUE other)
{
    if (!SYMBOL_P(other)) {
        return Qnil;
    }
    return str_casecmp_p(rb_sym2str(sym), rb_sym2str(other));
}

/*
 *  call-seq:
 *    symbol =~ object -> integer or nil
 *
 *  Equivalent to <tt>symbol.to_s =~ object</tt>,
 *  including possible updates to global variables;
 *  see String#=~.
 *
 */

static VALUE
sym_match(VALUE sym, VALUE other)
{
    return rb_str_match(rb_sym2str(sym), other);
}

/*
 *  call-seq:
 *    match(pattern, offset = 0) -> matchdata or nil
 *    match(pattern, offset = 0) {|matchdata| } -> object
 *
 *  Equivalent to <tt>self.to_s.match</tt>,
 *  including possible updates to global variables;
 *  see String#match.
 *
 */

static VALUE
sym_match_m(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_match_m(argc, argv, rb_sym2str(sym));
}

/*
 *  call-seq:
 *    match?(pattern, offset) -> true or false
 *
 *  Equivalent to <tt>sym.to_s.match?</tt>;
 *  see String#match.
 *
 */

static VALUE
sym_match_m_p(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_match_m_p(argc, argv, sym);
}

/*
 *  call-seq:
 *    symbol[index] -> string or nil
 *    symbol[start, length] -> string or nil
 *    symbol[range] -> string or nil
 *    symbol[regexp, capture = 0] -> string or nil
 *    symbol[substring] -> string or nil
 *
 *  Equivalent to <tt>symbol.to_s[]</tt>; see String#[].
 *
 */

static VALUE
sym_aref(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_aref_m(argc, argv, rb_sym2str(sym));
}

/*
 *  call-seq:
 *    length -> integer
 *
 *  Equivalent to <tt>self.to_s.length</tt>; see String#length.
 *
 *  Symbol#size is an alias for Symbol#length.
 *
 */

static VALUE
sym_length(VALUE sym)
{
    return rb_str_length(rb_sym2str(sym));
}

/*
 *  call-seq:
 *    empty? -> true or false
 *
 *  Returns +true+ if +self+ is <tt>:''</tt>, +false+ otherwise.
 *
 */

static VALUE
sym_empty(VALUE sym)
{
    return rb_str_empty(rb_sym2str(sym));
}

/*
 *  call-seq:
 *    upcase(*options) -> symbol
 *
 *  Equivalent to <tt>sym.to_s.upcase.to_sym</tt>.
 *
 *  See String#upcase.
 *
 */

static VALUE
sym_upcase(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_intern(rb_str_upcase(argc, argv, rb_sym2str(sym)));
}

/*
 *  call-seq:
 *    downcase(*options) -> symbol
 *
 *  Equivalent to <tt>sym.to_s.downcase.to_sym</tt>.
 *
 *  See String#downcase.
 *
 *  Related: Symbol#upcase.
 *
 */

static VALUE
sym_downcase(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_intern(rb_str_downcase(argc, argv, rb_sym2str(sym)));
}

/*
 *  call-seq:
 *    capitalize(*options) -> symbol
 *
 *  Equivalent to <tt>sym.to_s.capitalize.to_sym</tt>.
 *
 *  See String#capitalize.
 *
 */

static VALUE
sym_capitalize(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_intern(rb_str_capitalize(argc, argv, rb_sym2str(sym)));
}

/*
 *  call-seq:
 *    swapcase(*options) -> symbol
 *
 *  Equivalent to <tt>sym.to_s.swapcase.to_sym</tt>.
 *
 *  See String#swapcase.
 *
 */

static VALUE
sym_swapcase(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_intern(rb_str_swapcase(argc, argv, rb_sym2str(sym)));
}

/*
 *  call-seq:
 *    start_with?(*string_or_regexp) -> true or false
 *
 *  Equivalent to <tt>self.to_s.start_with?</tt>; see String#start_with?.
 *
 */

static VALUE
sym_start_with(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_start_with(argc, argv, rb_sym2str(sym));
}

/*
 *  call-seq:
 *    end_with?(*string_or_regexp) -> true or false
 *
 *
 *  Equivalent to <tt>self.to_s.end_with?</tt>; see String#end_with?.
 *
 */

static VALUE
sym_end_with(int argc, VALUE *argv, VALUE sym)
{
    return rb_str_end_with(argc, argv, rb_sym2str(sym));
}

/*
 *  call-seq:
 *    encoding -> encoding
 *
 *  Equivalent to <tt>self.to_s.encoding</tt>; see String#encoding.
 *
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
 *  call-seq:
 *    Symbol.all_symbols -> array_of_symbols
 *
 *  Returns an array of all symbols currently in Ruby's symbol table:
 *
 *    Symbol.all_symbols.size    # => 9334
 *    Symbol.all_symbols.take(3) # => [:!, :"\"", :"#"]
 *
 */

static VALUE
sym_all_symbols(VALUE _)
{
    return rb_sym_all_symbols();
}

VALUE
rb_str_to_interned_str(VALUE str)
{
    return rb_fstring(str);
}

VALUE
rb_interned_str(const char *ptr, long len)
{
    struct RString fake_str;
    return register_fstring(setup_fake_str(&fake_str, ptr, len, ENCINDEX_US_ASCII), TRUE);
}

VALUE
rb_interned_str_cstr(const char *ptr)
{
    return rb_interned_str(ptr, strlen(ptr));
}

VALUE
rb_enc_interned_str(const char *ptr, long len, rb_encoding *enc)
{
    if (UNLIKELY(rb_enc_autoload_p(enc))) {
        rb_enc_autoload(enc);
    }

    struct RString fake_str;
    return register_fstring(rb_setup_fake_str(&fake_str, ptr, len, enc), TRUE);
}

VALUE
rb_enc_interned_str_cstr(const char *ptr, rb_encoding *enc)
{
    return rb_enc_interned_str(ptr, strlen(ptr), enc);
}

void
Init_String(void)
{
    rb_cString  = rb_define_class("String", rb_cObject);
    assert(rb_vm_fstring_table());
    st_foreach(rb_vm_fstring_table(), fstring_set_class_i, rb_cString);
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
    rb_define_method(rb_cString, "casecmp?", rb_str_casecmp_p, 1);
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
    rb_define_method(rb_cString, "match?", rb_str_match_m_p, -1);
    rb_define_method(rb_cString, "succ", rb_str_succ, 0);
    rb_define_method(rb_cString, "succ!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "next", rb_str_succ, 0);
    rb_define_method(rb_cString, "next!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "upto", rb_str_upto, -1);
    rb_define_method(rb_cString, "index", rb_str_index_m, -1);
    rb_define_method(rb_cString, "byteindex", rb_str_byteindex_m, -1);
    rb_define_method(rb_cString, "rindex", rb_str_rindex_m, -1);
    rb_define_method(rb_cString, "byterindex", rb_str_byterindex_m, -1);
    rb_define_method(rb_cString, "replace", rb_str_replace, 1);
    rb_define_method(rb_cString, "clear", rb_str_clear, 0);
    rb_define_method(rb_cString, "chr", rb_str_chr, 0);
    rb_define_method(rb_cString, "getbyte", rb_str_getbyte, 1);
    rb_define_method(rb_cString, "setbyte", rb_str_setbyte, 2);
    rb_define_method(rb_cString, "byteslice", rb_str_byteslice, -1);
    rb_define_method(rb_cString, "bytesplice", rb_str_bytesplice, -1);
    rb_define_method(rb_cString, "scrub", str_scrub, -1);
    rb_define_method(rb_cString, "scrub!", str_scrub_bang, -1);
    rb_define_method(rb_cString, "freeze", rb_str_freeze, 0);
    rb_define_method(rb_cString, "+@", str_uplus, 0);
    rb_define_method(rb_cString, "-@", str_uminus, 0);
    rb_define_alias(rb_cString, "dedup", "-@");

    rb_define_method(rb_cString, "to_i", rb_str_to_i, -1);
    rb_define_method(rb_cString, "to_f", rb_str_to_f, 0);
    rb_define_method(rb_cString, "to_s", rb_str_to_s, 0);
    rb_define_method(rb_cString, "to_str", rb_str_to_s, 0);
    rb_define_method(rb_cString, "inspect", rb_str_inspect, 0);
    rb_define_method(rb_cString, "dump", rb_str_dump, 0);
    rb_define_method(rb_cString, "undump", str_undump, 0);

    sym_ascii      = ID2SYM(rb_intern_const("ascii"));
    sym_turkic     = ID2SYM(rb_intern_const("turkic"));
    sym_lithuanian = ID2SYM(rb_intern_const("lithuanian"));
    sym_fold       = ID2SYM(rb_intern_const("fold"));

    rb_define_method(rb_cString, "upcase", rb_str_upcase, -1);
    rb_define_method(rb_cString, "downcase", rb_str_downcase, -1);
    rb_define_method(rb_cString, "capitalize", rb_str_capitalize, -1);
    rb_define_method(rb_cString, "swapcase", rb_str_swapcase, -1);

    rb_define_method(rb_cString, "upcase!", rb_str_upcase_bang, -1);
    rb_define_method(rb_cString, "downcase!", rb_str_downcase_bang, -1);
    rb_define_method(rb_cString, "capitalize!", rb_str_capitalize_bang, -1);
    rb_define_method(rb_cString, "swapcase!", rb_str_swapcase_bang, -1);

    rb_define_method(rb_cString, "hex", rb_str_hex, 0);
    rb_define_method(rb_cString, "oct", rb_str_oct, 0);
    rb_define_method(rb_cString, "split", rb_str_split_m, -1);
    rb_define_method(rb_cString, "lines", rb_str_lines, -1);
    rb_define_method(rb_cString, "bytes", rb_str_bytes, 0);
    rb_define_method(rb_cString, "chars", rb_str_chars, 0);
    rb_define_method(rb_cString, "codepoints", rb_str_codepoints, 0);
    rb_define_method(rb_cString, "grapheme_clusters", rb_str_grapheme_clusters, 0);
    rb_define_method(rb_cString, "reverse", rb_str_reverse, 0);
    rb_define_method(rb_cString, "reverse!", rb_str_reverse_bang, 0);
    rb_define_method(rb_cString, "concat", rb_str_concat_multi, -1);
    rb_define_method(rb_cString, "<<", rb_str_concat, 1);
    rb_define_method(rb_cString, "prepend", rb_str_prepend_multi, -1);
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
    rb_define_method(rb_cString, "delete_prefix", rb_str_delete_prefix, 1);
    rb_define_method(rb_cString, "delete_suffix", rb_str_delete_suffix, 1);

    rb_define_method(rb_cString, "sub!", rb_str_sub_bang, -1);
    rb_define_method(rb_cString, "gsub!", rb_str_gsub_bang, -1);
    rb_define_method(rb_cString, "chop!", rb_str_chop_bang, 0);
    rb_define_method(rb_cString, "chomp!", rb_str_chomp_bang, -1);
    rb_define_method(rb_cString, "strip!", rb_str_strip_bang, 0);
    rb_define_method(rb_cString, "lstrip!", rb_str_lstrip_bang, 0);
    rb_define_method(rb_cString, "rstrip!", rb_str_rstrip_bang, 0);
    rb_define_method(rb_cString, "delete_prefix!", rb_str_delete_prefix_bang, 1);
    rb_define_method(rb_cString, "delete_suffix!", rb_str_delete_suffix_bang, 1);

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
    rb_define_method(rb_cString, "each_grapheme_cluster", rb_str_each_grapheme_cluster, 0);

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

    /* define UnicodeNormalize module here so that we don't have to look it up */
    mUnicodeNormalize          = rb_define_module("UnicodeNormalize");
    id_normalize               = rb_intern_const("normalize");
    id_normalized_p            = rb_intern_const("normalized?");

    rb_define_method(rb_cString, "unicode_normalize", rb_str_unicode_normalize, -1);
    rb_define_method(rb_cString, "unicode_normalize!", rb_str_unicode_normalize_bang, -1);
    rb_define_method(rb_cString, "unicode_normalized?", rb_str_unicode_normalized_p, -1);

    rb_fs = Qnil;
    rb_define_hooked_variable("$;", &rb_fs, 0, rb_fs_setter);
    rb_define_hooked_variable("$-F", &rb_fs, 0, rb_fs_setter);
    rb_gc_register_address(&rb_fs);

    rb_cSymbol = rb_define_class("Symbol", rb_cObject);
    rb_include_module(rb_cSymbol, rb_mComparable);
    rb_undef_alloc_func(rb_cSymbol);
    rb_undef_method(CLASS_OF(rb_cSymbol), "new");
    rb_define_singleton_method(rb_cSymbol, "all_symbols", sym_all_symbols, 0);

    rb_define_method(rb_cSymbol, "==", sym_equal, 1);
    rb_define_method(rb_cSymbol, "===", sym_equal, 1);
    rb_define_method(rb_cSymbol, "inspect", sym_inspect, 0);
    rb_define_method(rb_cSymbol, "to_s", rb_sym_to_s, 0);
    rb_define_method(rb_cSymbol, "id2name", rb_sym_to_s, 0);
    rb_define_method(rb_cSymbol, "name", rb_sym2str, 0); /* in symbol.c */
    rb_define_method(rb_cSymbol, "to_proc", rb_sym_to_proc, 0); /* in proc.c */
    rb_define_method(rb_cSymbol, "succ", sym_succ, 0);
    rb_define_method(rb_cSymbol, "next", sym_succ, 0);

    rb_define_method(rb_cSymbol, "<=>", sym_cmp, 1);
    rb_define_method(rb_cSymbol, "casecmp", sym_casecmp, 1);
    rb_define_method(rb_cSymbol, "casecmp?", sym_casecmp_p, 1);
    rb_define_method(rb_cSymbol, "=~", sym_match, 1);

    rb_define_method(rb_cSymbol, "[]", sym_aref, -1);
    rb_define_method(rb_cSymbol, "slice", sym_aref, -1);
    rb_define_method(rb_cSymbol, "length", sym_length, 0);
    rb_define_method(rb_cSymbol, "size", sym_length, 0);
    rb_define_method(rb_cSymbol, "empty?", sym_empty, 0);
    rb_define_method(rb_cSymbol, "match", sym_match_m, -1);
    rb_define_method(rb_cSymbol, "match?", sym_match_m_p, -1);

    rb_define_method(rb_cSymbol, "upcase", sym_upcase, -1);
    rb_define_method(rb_cSymbol, "downcase", sym_downcase, -1);
    rb_define_method(rb_cSymbol, "capitalize", sym_capitalize, -1);
    rb_define_method(rb_cSymbol, "swapcase", sym_swapcase, -1);

    rb_define_method(rb_cSymbol, "start_with?", sym_start_with, -1);
    rb_define_method(rb_cSymbol, "end_with?", sym_end_with, -1);

    rb_define_method(rb_cSymbol, "encoding", sym_encoding, 0);
}
