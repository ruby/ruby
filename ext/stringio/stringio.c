/* -*- mode: c; indent-tabs-mode: t -*- */
/**********************************************************************

  stringio.c -

  $Author$
  $RoughId: stringio.c,v 1.13 2002/03/14 03:24:18 nobu Exp $
  created at: Tue Feb 19 04:10:38 JST 2002

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#define STRINGIO_VERSION "3.0.1.2"

#include "ruby.h"
#include "ruby/io.h"
#include "ruby/encoding.h"
#if defined(HAVE_FCNTL_H) || defined(_WIN32)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
#include <sys/fcntl.h>
#endif

#ifndef RB_INTEGER_TYPE_P
# define RB_INTEGER_TYPE_P(c) (FIXNUM_P(c) || RB_TYPE_P(c, T_BIGNUM))
#endif

#ifndef RB_PASS_CALLED_KEYWORDS
# define rb_funcallv_kw(recv, mid, arg, argv, kw_splat) rb_funcallv(recv, mid, arg, argv)
# define rb_class_new_instance_kw(argc, argv, klass, kw_splat) rb_class_new_instance(argc, argv, klass)
#endif

#ifndef HAVE_RB_IO_EXTRACT_MODEENC
#define rb_io_extract_modeenc strio_extract_modeenc
static void
strio_extract_modeenc(VALUE *vmode_p, VALUE *vperm_p, VALUE opthash,
		      int *oflags_p, int *fmode_p, struct rb_io_enc_t *convconfig_p)
{
    VALUE mode = *vmode_p;
    VALUE intmode;
    int fmode;
    int has_enc = 0, has_vmode = 0;

    convconfig_p->enc = convconfig_p->enc2 = 0;

  vmode_handle:
    if (NIL_P(mode)) {
	fmode = FMODE_READABLE;
    }
    else if (!NIL_P(intmode = rb_check_to_integer(mode, "to_int"))) {
	int flags = NUM2INT(intmode);
	fmode = rb_io_oflags_fmode(flags);
    }
    else {
	const char *m = StringValueCStr(mode), *n, *e;
	fmode = rb_io_modestr_fmode(m);
	n = strchr(m, ':');
	if (n) {
	    long len;
	    char encname[ENCODING_MAXNAMELEN+1];
	    has_enc = 1;
	    if (fmode & FMODE_SETENC_BY_BOM) {
		n = strchr(n, '|');
	    }
	    e = strchr(++n, ':');
	    len = e ? e - n : (long)strlen(n);
	    if (len > 0 && len <= ENCODING_MAXNAMELEN) {
		if (e) {
		    memcpy(encname, n, len);
		    encname[len] = '\0';
		    n = encname;
		}
		convconfig_p->enc = rb_enc_find(n);
	    }
	    if (e && (len = strlen(++e)) > 0 && len <= ENCODING_MAXNAMELEN) {
		convconfig_p->enc2 = rb_enc_find(e);
	    }
	}
    }

    if (!NIL_P(opthash)) {
	rb_encoding *extenc = 0, *intenc = 0;
	VALUE v;
	if (!has_vmode) {
	    ID id_mode;
	    CONST_ID(id_mode, "mode");
	    v = rb_hash_aref(opthash, ID2SYM(id_mode));
	    if (!NIL_P(v)) {
		if (!NIL_P(mode)) {
		    rb_raise(rb_eArgError, "mode specified twice");
		}
		has_vmode = 1;
		mode = v;
		goto vmode_handle;
	    }
	}

	if (rb_io_extract_encoding_option(opthash, &extenc, &intenc, &fmode)) {
	    if (has_enc) {
		rb_raise(rb_eArgError, "encoding specified twice");
	    }
	}
    }
    *fmode_p = fmode;
}
#endif

struct StringIO {
    VALUE string;
    rb_encoding *enc;
    long pos;
    long lineno;
    int flags;
    int count;
};

static VALUE strio_init(int, VALUE *, struct StringIO *, VALUE);
static VALUE strio_unget_bytes(struct StringIO *, const char *, long);
static long strio_write(VALUE self, VALUE str);

#define IS_STRIO(obj) (rb_typeddata_is_kind_of((obj), &strio_data_type))
#define error_inval(msg) (rb_syserr_fail(EINVAL, msg))
#define get_enc(ptr) ((ptr)->enc ? (ptr)->enc : rb_enc_get((ptr)->string))

static struct StringIO *
strio_alloc(void)
{
    struct StringIO *ptr = ALLOC(struct StringIO);
    ptr->string = Qnil;
    ptr->pos = 0;
    ptr->lineno = 0;
    ptr->flags = 0;
    ptr->count = 1;
    return ptr;
}

static void
strio_mark(void *p)
{
    struct StringIO *ptr = p;

    rb_gc_mark(ptr->string);
}

static void
strio_free(void *p)
{
    struct StringIO *ptr = p;
    if (--ptr->count <= 0) {
	xfree(ptr);
    }
}

static size_t
strio_memsize(const void *p)
{
    return sizeof(struct StringIO);
}

static const rb_data_type_t strio_data_type = {
    "strio",
    {
	strio_mark,
	strio_free,
	strio_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#define check_strio(self) ((struct StringIO*)rb_check_typeddata((self), &strio_data_type))

static struct StringIO*
get_strio(VALUE self)
{
    struct StringIO *ptr = check_strio(rb_io_taint_check(self));

    if (!ptr) {
	rb_raise(rb_eIOError, "uninitialized stream");
    }
    return ptr;
}

static VALUE
enc_subseq(VALUE str, long pos, long len, rb_encoding *enc)
{
    str = rb_str_subseq(str, pos, len);
    rb_enc_associate(str, enc);
    return str;
}

static VALUE
strio_substr(struct StringIO *ptr, long pos, long len, rb_encoding *enc)
{
    VALUE str = ptr->string;
    long rlen = RSTRING_LEN(str) - pos;

    if (len > rlen) len = rlen;
    if (len < 0) len = 0;
    if (len == 0) return rb_enc_str_new(0, 0, enc);
    return enc_subseq(str, pos, len, enc);
}

#define StringIO(obj) get_strio(obj)

#define STRIO_READABLE FL_USER4
#define STRIO_WRITABLE FL_USER5
#define STRIO_READWRITE (STRIO_READABLE|STRIO_WRITABLE)
typedef char strio_flags_check[(STRIO_READABLE/FMODE_READABLE == STRIO_WRITABLE/FMODE_WRITABLE) * 2 - 1];
#define STRIO_MODE_SET_P(strio, mode) \
    ((RBASIC(strio)->flags & STRIO_##mode) && \
     ((struct StringIO*)DATA_PTR(strio))->flags & FMODE_##mode)
#define CLOSED(strio) (!STRIO_MODE_SET_P(strio, READWRITE))
#define READABLE(strio) STRIO_MODE_SET_P(strio, READABLE)
#define WRITABLE(strio) STRIO_MODE_SET_P(strio, WRITABLE)

static VALUE sym_exception;

static struct StringIO*
readable(VALUE strio)
{
    struct StringIO *ptr = StringIO(strio);
    if (!READABLE(strio)) {
	rb_raise(rb_eIOError, "not opened for reading");
    }
    return ptr;
}

static struct StringIO*
writable(VALUE strio)
{
    struct StringIO *ptr = StringIO(strio);
    if (!WRITABLE(strio)) {
	rb_raise(rb_eIOError, "not opened for writing");
    }
    return ptr;
}

static void
check_modifiable(struct StringIO *ptr)
{
    if (OBJ_FROZEN(ptr->string)) {
	rb_raise(rb_eIOError, "not modifiable string");
    }
}

static VALUE
strio_s_allocate(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &strio_data_type, 0);
}

/*
 * call-seq: StringIO.new(string=""[, mode])
 *
 * Creates new StringIO instance from with _string_ and _mode_.
 */
static VALUE
strio_initialize(int argc, VALUE *argv, VALUE self)
{
    struct StringIO *ptr = check_strio(self);

    if (!ptr) {
	DATA_PTR(self) = ptr = strio_alloc();
    }
    rb_call_super(0, 0);
    return strio_init(argc, argv, ptr, self);
}

static int
detect_bom(VALUE str, int *bomlen)
{
    const char *p;
    long len;

    RSTRING_GETMEM(str, p, len);
    if (len < 1) return 0;
    switch ((unsigned char)p[0]) {
      case 0xEF:
	if (len < 2) break;
	if ((unsigned char)p[1] == 0xBB && len > 2) {
	    if ((unsigned char)p[2] == 0xBF) {
		*bomlen = 3;
		return rb_utf8_encindex();
	    }
	}
	break;

      case 0xFE:
	if (len < 2) break;
	if ((unsigned char)p[1] == 0xFF) {
	    *bomlen = 2;
	    return rb_enc_find_index("UTF-16BE");
	}
	break;

      case 0xFF:
	if (len < 2) break;
	if ((unsigned char)p[1] == 0xFE) {
	    if (len >= 4 && (unsigned char)p[2] == 0 && (unsigned char)p[3] == 0) {
		*bomlen = 4;
		return rb_enc_find_index("UTF-32LE");
	    }
	    *bomlen = 2;
	    return rb_enc_find_index("UTF-16LE");
	}
	break;

      case 0:
	if (len < 4) break;
	if ((unsigned char)p[1] == 0 && (unsigned char)p[2] == 0xFE && (unsigned char)p[3] == 0xFF) {
	    *bomlen = 4;
	    return rb_enc_find_index("UTF-32BE");
	}
	break;
    }
    return 0;
}

static rb_encoding *
set_encoding_by_bom(struct StringIO *ptr)
{
    int bomlen, idx = detect_bom(ptr->string, &bomlen);
    rb_encoding *extenc = NULL;

    if (idx) {
	extenc = rb_enc_from_index(idx);
	ptr->pos = bomlen;
	if (ptr->flags & FMODE_WRITABLE) {
	    rb_enc_associate_index(ptr->string, idx);
	}
    }
    ptr->enc = extenc;
    return extenc;
}

static VALUE
strio_init(int argc, VALUE *argv, struct StringIO *ptr, VALUE self)
{
    VALUE string, vmode, opt;
    int oflags;
    struct rb_io_enc_t convconfig;

    argc = rb_scan_args(argc, argv, "02:", &string, &vmode, &opt);
    rb_io_extract_modeenc(&vmode, 0, opt, &oflags, &ptr->flags, &convconfig);
    if (argc) {
	StringValue(string);
    }
    else {
	string = rb_enc_str_new("", 0, rb_default_external_encoding());
    }
    if (OBJ_FROZEN_RAW(string)) {
	if (ptr->flags & FMODE_WRITABLE) {
	    rb_syserr_fail(EACCES, 0);
	}
    }
    else {
	if (NIL_P(vmode)) {
	    ptr->flags |= FMODE_WRITABLE;
	}
    }
    if (ptr->flags & FMODE_TRUNC) {
	rb_str_resize(string, 0);
    }
    ptr->string = string;
    if (argc == 1) {
	ptr->enc = rb_enc_get(string);
    }
    else {
	ptr->enc = convconfig.enc;
    }
    ptr->pos = 0;
    ptr->lineno = 0;
    if (ptr->flags & FMODE_SETENC_BY_BOM) set_encoding_by_bom(ptr);
    RBASIC(self)->flags |= (ptr->flags & FMODE_READWRITE) * (STRIO_READABLE / FMODE_READABLE);
    return self;
}

static VALUE
strio_finalize(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    ptr->string = Qnil;
    ptr->flags &= ~FMODE_READWRITE;
    return self;
}

/*
 * call-seq: StringIO.open(string=""[, mode]) {|strio| ...}
 *
 * Equivalent to StringIO.new except that when it is called with a block, it
 * yields with the new instance and closes it, and returns the result which
 * returned from the block.
 */
static VALUE
strio_s_open(int argc, VALUE *argv, VALUE klass)
{
    VALUE obj = rb_class_new_instance_kw(argc, argv, klass, RB_PASS_CALLED_KEYWORDS);
    if (!rb_block_given_p()) return obj;
    return rb_ensure(rb_yield, obj, strio_finalize, obj);
}

/* :nodoc: */
static VALUE
strio_s_new(int argc, VALUE *argv, VALUE klass)
{
    if (rb_block_given_p()) {
	VALUE cname = rb_obj_as_string(klass);

	rb_warn("%"PRIsVALUE"::new() does not take block; use %"PRIsVALUE"::open() instead",
		cname, cname);
    }
    return rb_class_new_instance_kw(argc, argv, klass, RB_PASS_CALLED_KEYWORDS);
}

/*
 * Returns +false+.  Just for compatibility to IO.
 */
static VALUE
strio_false(VALUE self)
{
    StringIO(self);
    return Qfalse;
}

/*
 * Returns +nil+.  Just for compatibility to IO.
 */
static VALUE
strio_nil(VALUE self)
{
    StringIO(self);
    return Qnil;
}

/*
 * Returns an object itself.  Just for compatibility to IO.
 */
static VALUE
strio_self(VALUE self)
{
    StringIO(self);
    return self;
}

/*
 * Returns 0.  Just for compatibility to IO.
 */
static VALUE
strio_0(VALUE self)
{
    StringIO(self);
    return INT2FIX(0);
}

/*
 * Returns the argument unchanged.  Just for compatibility to IO.
 */
static VALUE
strio_first(VALUE self, VALUE arg)
{
    StringIO(self);
    return arg;
}

/*
 * Raises NotImplementedError.
 */
static VALUE
strio_unimpl(int argc, VALUE *argv, VALUE self)
{
    StringIO(self);
    rb_notimplement();

    UNREACHABLE;
}

/*
 * call-seq: strio.string     -> string
 *
 * Returns underlying String object, the subject of IO.
 */
static VALUE
strio_get_string(VALUE self)
{
    return StringIO(self)->string;
}

/*
 * call-seq:
 *   strio.string = string  -> string
 *
 * Changes underlying String object, the subject of IO.
 */
static VALUE
strio_set_string(VALUE self, VALUE string)
{
    struct StringIO *ptr = StringIO(self);

    rb_io_taint_check(self);
    ptr->flags &= ~FMODE_READWRITE;
    StringValue(string);
    ptr->flags = OBJ_FROZEN(string) ? FMODE_READABLE : FMODE_READWRITE;
    ptr->pos = 0;
    ptr->lineno = 0;
    return ptr->string = string;
}

/*
 * call-seq:
 *   strio.close  -> nil
 *
 * Closes a StringIO. The stream is unavailable for any further data
 * operations; an +IOError+ is raised if such an attempt is made.
 */
static VALUE
strio_close(VALUE self)
{
    StringIO(self);
    RBASIC(self)->flags &= ~STRIO_READWRITE;
    return Qnil;
}

/*
 * call-seq:
 *   strio.close_read    -> nil
 *
 * Closes the read end of a StringIO.  Will raise an +IOError+ if the
 * receiver is not readable.
 */
static VALUE
strio_close_read(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    if (!(ptr->flags & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "closing non-duplex IO for reading");
    }
    RBASIC(self)->flags &= ~STRIO_READABLE;
    return Qnil;
}

/*
 * call-seq:
 *   strio.close_write    -> nil
 *
 * Closes the write end of a StringIO.  Will raise an  +IOError+ if the
 * receiver is not writeable.
 */
static VALUE
strio_close_write(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    if (!(ptr->flags & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "closing non-duplex IO for writing");
    }
    RBASIC(self)->flags &= ~STRIO_WRITABLE;
    return Qnil;
}

/*
 * call-seq:
 *   strio.closed?    -> true or false
 *
 * Returns +true+ if the stream is completely closed, +false+ otherwise.
 */
static VALUE
strio_closed(VALUE self)
{
    StringIO(self);
    if (!CLOSED(self)) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   strio.closed_read?    -> true or false
 *
 * Returns +true+ if the stream is not readable, +false+ otherwise.
 */
static VALUE
strio_closed_read(VALUE self)
{
    StringIO(self);
    if (READABLE(self)) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   strio.closed_write?    -> true or false
 *
 * Returns +true+ if the stream is not writable, +false+ otherwise.
 */
static VALUE
strio_closed_write(VALUE self)
{
    StringIO(self);
    if (WRITABLE(self)) return Qfalse;
    return Qtrue;
}

static struct StringIO *
strio_to_read(VALUE self)
{
    struct StringIO *ptr = readable(self);
    if (ptr->pos < RSTRING_LEN(ptr->string)) return ptr;
    return NULL;
}

/*
 * call-seq:
 *   strio.eof     -> true or false
 *   strio.eof?    -> true or false
 *
 * Returns true if the stream is at the end of the data (underlying string).
 * The stream must be opened for reading or an +IOError+ will be raised.
 */
static VALUE
strio_eof(VALUE self)
{
    if (strio_to_read(self)) return Qfalse;
    return Qtrue;
}

/* :nodoc: */
static VALUE
strio_copy(VALUE copy, VALUE orig)
{
    struct StringIO *ptr;

    orig = rb_convert_type(orig, T_DATA, "StringIO", "to_strio");
    if (copy == orig) return copy;
    ptr = StringIO(orig);
    if (check_strio(copy)) {
	strio_free(DATA_PTR(copy));
    }
    DATA_PTR(copy) = ptr;
    RBASIC(copy)->flags &= ~STRIO_READWRITE;
    RBASIC(copy)->flags |= RBASIC(orig)->flags & STRIO_READWRITE;
    ++ptr->count;
    return copy;
}

/*
 * call-seq:
 *   strio.lineno    -> integer
 *
 * Returns the current line number. The stream must be
 * opened for reading. +lineno+ counts the number of times  +gets+ is
 * called, rather than the number of newlines  encountered. The two
 * values will differ if +gets+ is  called with a separator other than
 * newline.  See also the  <code>$.</code> variable.
 */
static VALUE
strio_get_lineno(VALUE self)
{
    return LONG2NUM(StringIO(self)->lineno);
}

/*
 * call-seq:
 *   strio.lineno = integer    -> integer
 *
 * Manually sets the current line number to the given value.
 * <code>$.</code> is updated only on the next read.
 */
static VALUE
strio_set_lineno(VALUE self, VALUE lineno)
{
    StringIO(self)->lineno = NUM2LONG(lineno);
    return lineno;
}

/*
 * call-seq:
 *   strio.binmode    -> stringio
 *
 * Puts stream into binary mode. See IO#binmode.
 *
 */
static VALUE
strio_binmode(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    rb_encoding *enc = rb_ascii8bit_encoding();

    ptr->enc = enc;
    if (WRITABLE(self)) {
	rb_enc_associate(ptr->string, enc);
    }
    return self;
}

#define strio_fcntl strio_unimpl

#define strio_flush strio_self

#define strio_fsync strio_0

/*
 * call-seq:
 *   strio.reopen(other_StrIO)     -> strio
 *   strio.reopen(string, mode)    -> strio
 *
 * Reinitializes the stream with the given <i>other_StrIO</i> or _string_
 * and _mode_ (see StringIO#new).
 */
static VALUE
strio_reopen(int argc, VALUE *argv, VALUE self)
{
    rb_io_taint_check(self);
    if (argc == 1 && !RB_TYPE_P(*argv, T_STRING)) {
	return strio_copy(self, *argv);
    }
    return strio_init(argc, argv, StringIO(self), self);
}

/*
 * call-seq:
 *   strio.pos     -> integer
 *   strio.tell    -> integer
 *
 * Returns the current offset (in bytes).
 */
static VALUE
strio_get_pos(VALUE self)
{
    return LONG2NUM(StringIO(self)->pos);
}

/*
 * call-seq:
 *   strio.pos = integer    -> integer
 *
 * Seeks to the given position (in bytes).
 */
static VALUE
strio_set_pos(VALUE self, VALUE pos)
{
    struct StringIO *ptr = StringIO(self);
    long p = NUM2LONG(pos);
    if (p < 0) {
	error_inval(0);
    }
    ptr->pos = p;
    return pos;
}

/*
 * call-seq:
 *   strio.rewind    -> 0
 *
 * Positions the stream to the beginning of input, resetting
 * +lineno+ to zero.
 */
static VALUE
strio_rewind(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    ptr->pos = 0;
    ptr->lineno = 0;
    return INT2FIX(0);
}

/*
 * call-seq:
 *   strio.seek(amount, whence=SEEK_SET) -> 0
 *
 * Seeks to a given offset _amount_ in the stream according to
 * the value of _whence_ (see IO#seek).
 */
static VALUE
strio_seek(int argc, VALUE *argv, VALUE self)
{
    VALUE whence;
    struct StringIO *ptr = StringIO(self);
    long amount, offset;

    rb_scan_args(argc, argv, "11", NULL, &whence);
    amount = NUM2LONG(argv[0]);
    if (CLOSED(self)) {
	rb_raise(rb_eIOError, "closed stream");
    }
    switch (NIL_P(whence) ? 0 : NUM2LONG(whence)) {
      case 0:
	offset = 0;
	break;
      case 1:
	offset = ptr->pos;
	break;
      case 2:
	offset = RSTRING_LEN(ptr->string);
	break;
      default:
	error_inval("invalid whence");
    }
    if (amount > LONG_MAX - offset || amount + offset < 0) {
	error_inval(0);
    }
    ptr->pos = amount + offset;
    return INT2FIX(0);
}

/*
 * call-seq:
 *   strio.sync    -> true
 *
 * Returns +true+ always.
 */
static VALUE
strio_get_sync(VALUE self)
{
    StringIO(self);
    return Qtrue;
}

#define strio_set_sync strio_first

#define strio_tell strio_get_pos

/*
 * call-seq:
 *   strio.each_byte {|byte| block }  -> strio
 *   strio.each_byte                  -> anEnumerator
 *
 * See IO#each_byte.
 */
static VALUE
strio_each_byte(VALUE self)
{
    struct StringIO *ptr;

    RETURN_ENUMERATOR(self, 0, 0);

    while ((ptr = strio_to_read(self)) != NULL) {
	char c = RSTRING_PTR(ptr->string)[ptr->pos++];
	rb_yield(CHR2FIX(c));
    }
    return self;
}

/*
 * call-seq:
 *   strio.getc   -> string or nil
 *
 * See IO#getc.
 */
static VALUE
strio_getc(VALUE self)
{
    struct StringIO *ptr = readable(self);
    rb_encoding *enc = get_enc(ptr);
    VALUE str = ptr->string;
    long pos = ptr->pos;
    int len;
    char *p;

    if (pos >= RSTRING_LEN(str)) {
	return Qnil;
    }
    p = RSTRING_PTR(str)+pos;
    len = rb_enc_mbclen(p, RSTRING_END(str), enc);
    ptr->pos += len;
    return enc_subseq(str, pos, len, enc);
}

/*
 * call-seq:
 *   strio.getbyte   -> fixnum or nil
 *
 * See IO#getbyte.
 */
static VALUE
strio_getbyte(VALUE self)
{
    struct StringIO *ptr = readable(self);
    int c;
    if (ptr->pos >= RSTRING_LEN(ptr->string)) {
	return Qnil;
    }
    c = RSTRING_PTR(ptr->string)[ptr->pos++];
    return CHR2FIX(c);
}

static void
strio_extend(struct StringIO *ptr, long pos, long len)
{
    long olen;

    if (len > LONG_MAX - pos)
	rb_raise(rb_eArgError, "string size too big");

    check_modifiable(ptr);
    olen = RSTRING_LEN(ptr->string);
    if (pos + len > olen) {
	rb_str_resize(ptr->string, pos + len);
	if (pos > olen)
	    MEMZERO(RSTRING_PTR(ptr->string) + olen, char, pos - olen);
    }
    else {
	rb_str_modify(ptr->string);
    }
}

/*
 * call-seq:
 *   strio.ungetc(string)   -> nil
 *
 * Pushes back one character (passed as a parameter)
 * such that a subsequent buffered read will return it.  There is no
 * limitation for multiple pushbacks including pushing back behind the
 * beginning of the buffer string.
 */
static VALUE
strio_ungetc(VALUE self, VALUE c)
{
    struct StringIO *ptr = readable(self);
    rb_encoding *enc, *enc2;

    check_modifiable(ptr);
    if (NIL_P(c)) return Qnil;
    if (RB_INTEGER_TYPE_P(c)) {
	int len, cc = NUM2INT(c);
	char buf[16];

	enc = rb_enc_get(ptr->string);
	len = rb_enc_codelen(cc, enc);
	if (len <= 0) rb_enc_uint_chr(cc, enc);
	rb_enc_mbcput(cc, buf, enc);
	return strio_unget_bytes(ptr, buf, len);
    }
    else {
	SafeStringValue(c);
	enc = rb_enc_get(ptr->string);
	enc2 = rb_enc_get(c);
	if (enc != enc2 && enc != rb_ascii8bit_encoding()) {
	    c = rb_str_conv_enc(c, enc2, enc);
	}
	strio_unget_bytes(ptr, RSTRING_PTR(c), RSTRING_LEN(c));
	RB_GC_GUARD(c);
	return Qnil;
    }
}

/*
 * call-seq:
 *   strio.ungetbyte(fixnum)   -> nil
 *
 * See IO#ungetbyte
 */
static VALUE
strio_ungetbyte(VALUE self, VALUE c)
{
    struct StringIO *ptr = readable(self);

    check_modifiable(ptr);
    if (NIL_P(c)) return Qnil;
    if (RB_INTEGER_TYPE_P(c)) {
        /* rb_int_and() not visible from exts */
        VALUE v = rb_funcall(c, '&', 1, INT2FIX(0xff));
        const char cc = NUM2INT(v) & 0xFF;
        strio_unget_bytes(ptr, &cc, 1);
    }
    else {
	long cl;
	SafeStringValue(c);
	cl = RSTRING_LEN(c);
	if (cl > 0) {
	    strio_unget_bytes(ptr, RSTRING_PTR(c), cl);
	    RB_GC_GUARD(c);
	}
    }
    return Qnil;
}

static VALUE
strio_unget_bytes(struct StringIO *ptr, const char *cp, long cl)
{
    long pos = ptr->pos, len, rest;
    VALUE str = ptr->string;
    char *s;

    len = RSTRING_LEN(str);
    rest = pos - len;
    if (cl > pos) {
	long ex = cl - (rest < 0 ? pos : len);
	rb_str_modify_expand(str, ex);
	rb_str_set_len(str, len + ex);
	s = RSTRING_PTR(str);
	if (rest < 0) memmove(s + cl, s + pos, -rest);
	pos = 0;
    }
    else {
	if (rest > 0) {
	    rb_str_modify_expand(str, rest);
	    rb_str_set_len(str, len + rest);
	}
	s = RSTRING_PTR(str);
	if (rest > cl) memset(s + len, 0, rest - cl);
	pos -= cl;
    }
    memcpy(s + pos, cp, cl);
    ptr->pos = pos;
    return Qnil;
}

/*
 * call-seq:
 *   strio.readchar   -> string
 *
 * See IO#readchar.
 */
static VALUE
strio_readchar(VALUE self)
{
    VALUE c = rb_funcallv(self, rb_intern("getc"), 0, 0);
    if (NIL_P(c)) rb_eof_error();
    return c;
}

/*
 * call-seq:
 *   strio.readbyte   -> fixnum
 *
 * See IO#readbyte.
 */
static VALUE
strio_readbyte(VALUE self)
{
    VALUE c = rb_funcallv(self, rb_intern("getbyte"), 0, 0);
    if (NIL_P(c)) rb_eof_error();
    return c;
}

/*
 * call-seq:
 *   strio.each_char {|char| block }  -> strio
 *   strio.each_char                  -> anEnumerator
 *
 * See IO#each_char.
 */
static VALUE
strio_each_char(VALUE self)
{
    VALUE c;

    RETURN_ENUMERATOR(self, 0, 0);

    while (!NIL_P(c = strio_getc(self))) {
	rb_yield(c);
    }
    return self;
}

/*
 * call-seq:
 *   strio.each_codepoint {|c| block }  -> strio
 *   strio.each_codepoint               -> anEnumerator
 *
 * See IO#each_codepoint.
 */
static VALUE
strio_each_codepoint(VALUE self)
{
    struct StringIO *ptr;
    rb_encoding *enc;
    unsigned int c;
    int n;

    RETURN_ENUMERATOR(self, 0, 0);

    ptr = readable(self);
    enc = get_enc(ptr);
    while ((ptr = strio_to_read(self)) != NULL) {
	c = rb_enc_codepoint_len(RSTRING_PTR(ptr->string)+ptr->pos,
				 RSTRING_END(ptr->string), &n, enc);
	ptr->pos += n;
	rb_yield(UINT2NUM(c));
    }
    return self;
}

/* Boyer-Moore search: copied from regex.c */
static void
bm_init_skip(long *skip, const char *pat, long m)
{
    int c;

    for (c = 0; c < (1 << CHAR_BIT); c++) {
	skip[c] = m;
    }
    while (--m) {
	skip[(unsigned char)*pat++] = m;
    }
}

static long
bm_search(const char *little, long llen, const char *big, long blen, const long *skip)
{
    long i, j, k;

    i = llen - 1;
    while (i < blen) {
	k = i;
	j = llen - 1;
	while (j >= 0 && big[k] == little[j]) {
	    k--;
	    j--;
	}
	if (j < 0) return k + 1;
	i += skip[(unsigned char)big[i]];
    }
    return -1;
}

struct getline_arg {
    VALUE rs;
    long limit;
    unsigned int chomp: 1;
};

static struct getline_arg *
prepare_getline_args(struct getline_arg *arg, int argc, VALUE *argv)
{
    VALUE str, lim, opts;
    long limit = -1;

    argc = rb_scan_args(argc, argv, "02:", &str, &lim, &opts);
    switch (argc) {
      case 0:
	str = rb_rs;
	break;

      case 1:
	if (!NIL_P(str) && !RB_TYPE_P(str, T_STRING)) {
	    VALUE tmp = rb_check_string_type(str);
	    if (NIL_P(tmp)) {
		limit = NUM2LONG(str);
		str = rb_rs;
	    }
	    else {
		str = tmp;
	    }
	}
	break;

      case 2:
	if (!NIL_P(str)) StringValue(str);
	if (!NIL_P(lim)) limit = NUM2LONG(lim);
	break;
    }
    arg->rs = str;
    arg->limit = limit;
    arg->chomp = 0;
    if (!NIL_P(opts)) {
	static ID keywords[1];
	VALUE vchomp;
	if (!keywords[0]) {
	    keywords[0] = rb_intern_const("chomp");
	}
	rb_get_kwargs(opts, keywords, 0, 1, &vchomp);
	arg->chomp = (vchomp != Qundef) && RTEST(vchomp);
    }
    return arg;
}

static inline int
chomp_newline_width(const char *s, const char *e)
{
    if (e > s && *--e == '\n') {
	if (e > s && *--e == '\r') return 2;
	return 1;
    }
    return 0;
}

static VALUE
strio_getline(struct getline_arg *arg, struct StringIO *ptr)
{
    const char *s, *e, *p;
    long n, limit = arg->limit;
    VALUE str = arg->rs;
    int w = 0;
    rb_encoding *enc = get_enc(ptr);

    if (ptr->pos >= (n = RSTRING_LEN(ptr->string))) {
	return Qnil;
    }
    s = RSTRING_PTR(ptr->string);
    e = s + RSTRING_LEN(ptr->string);
    s += ptr->pos;
    if (limit > 0 && (size_t)limit < (size_t)(e - s)) {
	e = rb_enc_right_char_head(s, s + limit, e, get_enc(ptr));
    }
    if (NIL_P(str)) {
	if (arg->chomp) {
	    w = chomp_newline_width(s, e);
	}
	str = strio_substr(ptr, ptr->pos, e - s - w, enc);
    }
    else if ((n = RSTRING_LEN(str)) == 0) {
	p = s;
	while (p[(p + 1 < e) && (*p == '\r') && 0] == '\n') {
	    p += *p == '\r';
	    if (++p == e) {
		return Qnil;
	    }
	}
	s = p;
	while ((p = memchr(p, '\n', e - p)) && (p != e)) {
	    if (*++p == '\n') {
		e = p + 1;
		w = (arg->chomp ? 1 : 0);
		break;
	    }
	    else if (*p == '\r' && p < e && p[1] == '\n') {
		e = p + 2;
		w = (arg->chomp ? 2 : 0);
		break;
	    }
	}
	if (!w && arg->chomp) {
	    w = chomp_newline_width(s, e);
	}
	str = strio_substr(ptr, s - RSTRING_PTR(ptr->string), e - s - w, enc);
    }
    else if (n == 1) {
	if ((p = memchr(s, RSTRING_PTR(str)[0], e - s)) != 0) {
	    e = p + 1;
	    w = (arg->chomp ? (p > s && *(p-1) == '\r') + 1 : 0);
	}
	str = strio_substr(ptr, ptr->pos, e - s - w, enc);
    }
    else {
	if (n < e - s + arg->chomp) {
	    /* unless chomping, RS at the end does not matter */
	    if (e - s < 1024 || n == e - s) {
		for (p = s; p + n <= e; ++p) {
		    if (MEMCMP(p, RSTRING_PTR(str), char, n) == 0) {
			e = p + (arg->chomp ? 0 : n);
			break;
		    }
		}
	    }
	    else {
		long skip[1 << CHAR_BIT], pos;
		p = RSTRING_PTR(str);
		bm_init_skip(skip, p, n);
		if ((pos = bm_search(p, n, s, e - s, skip)) >= 0) {
		    e = s + pos + (arg->chomp ? 0 : n);
		}
	    }
	}
	str = strio_substr(ptr, ptr->pos, e - s - w, enc);
    }
    ptr->pos = e - RSTRING_PTR(ptr->string);
    ptr->lineno++;
    return str;
}

/*
 * call-seq:
 *   strio.gets(sep=$/, chomp: false)     -> string or nil
 *   strio.gets(limit, chomp: false)      -> string or nil
 *   strio.gets(sep, limit, chomp: false) -> string or nil
 *
 * See IO#gets.
 */
static VALUE
strio_gets(int argc, VALUE *argv, VALUE self)
{
    struct getline_arg arg;
    VALUE str;

    if (prepare_getline_args(&arg, argc, argv)->limit == 0) {
	struct StringIO *ptr = readable(self);
	return rb_enc_str_new(0, 0, get_enc(ptr));
    }

    str = strio_getline(&arg, readable(self));
    rb_lastline_set(str);
    return str;
}

/*
 * call-seq:
 *   strio.readline(sep=$/, chomp: false)     -> string
 *   strio.readline(limit, chomp: false)      -> string or nil
 *   strio.readline(sep, limit, chomp: false) -> string or nil
 *
 * See IO#readline.
 */
static VALUE
strio_readline(int argc, VALUE *argv, VALUE self)
{
    VALUE line = rb_funcallv_kw(self, rb_intern("gets"), argc, argv, RB_PASS_CALLED_KEYWORDS);
    if (NIL_P(line)) rb_eof_error();
    return line;
}

/*
 * call-seq:
 *   strio.each(sep=$/, chomp: false) {|line| block }         -> strio
 *   strio.each(limit, chomp: false) {|line| block }          -> strio
 *   strio.each(sep, limit, chomp: false) {|line| block }     -> strio
 *   strio.each(...)                                          -> anEnumerator
 *
 *   strio.each_line(sep=$/, chomp: false) {|line| block }     -> strio
 *   strio.each_line(limit, chomp: false) {|line| block }      -> strio
 *   strio.each_line(sep, limit, chomp: false) {|line| block } -> strio
 *   strio.each_line(...)                                      -> anEnumerator
 *
 * See IO#each.
 */
static VALUE
strio_each(int argc, VALUE *argv, VALUE self)
{
    VALUE line;
    struct getline_arg arg;

    StringIO(self);
    RETURN_ENUMERATOR(self, argc, argv);

    if (prepare_getline_args(&arg, argc, argv)->limit == 0) {
	rb_raise(rb_eArgError, "invalid limit: 0 for each_line");
    }

    while (!NIL_P(line = strio_getline(&arg, readable(self)))) {
	rb_yield(line);
    }
    return self;
}

/*
 * call-seq:
 *   strio.readlines(sep=$/, chomp: false)     ->   array
 *   strio.readlines(limit, chomp: false)      ->   array
 *   strio.readlines(sep, limit, chomp: false) ->   array
 *
 * See IO#readlines.
 */
static VALUE
strio_readlines(int argc, VALUE *argv, VALUE self)
{
    VALUE ary, line;
    struct getline_arg arg;

    StringIO(self);
    ary = rb_ary_new();
    if (prepare_getline_args(&arg, argc, argv)->limit == 0) {
	rb_raise(rb_eArgError, "invalid limit: 0 for readlines");
    }

    while (!NIL_P(line = strio_getline(&arg, readable(self)))) {
	rb_ary_push(ary, line);
    }
    return ary;
}

/*
 * call-seq:
 *   strio.write(string, ...) -> integer
 *   strio.syswrite(string)   -> integer
 *
 * Appends the given string to the underlying buffer string.
 * The stream must be opened for writing.  If the argument is not a
 * string, it will be converted to a string using <code>to_s</code>.
 * Returns the number of bytes written.  See IO#write.
 */
static VALUE
strio_write_m(int argc, VALUE *argv, VALUE self)
{
    long len = 0;
    while (argc-- > 0) {
	/* StringIO can't exceed long limit */
	len += strio_write(self, *argv++);
    }
    return LONG2NUM(len);
}

static long
strio_write(VALUE self, VALUE str)
{
    struct StringIO *ptr = writable(self);
    long len, olen;
    rb_encoding *enc, *enc2;
    rb_encoding *const ascii8bit = rb_ascii8bit_encoding();
    rb_encoding *usascii = 0;

    if (!RB_TYPE_P(str, T_STRING))
	str = rb_obj_as_string(str);
    enc = get_enc(ptr);
    enc2 = rb_enc_get(str);
    if (enc != enc2 && enc != ascii8bit && enc != (usascii = rb_usascii_encoding())) {
	VALUE converted = rb_str_conv_enc(str, enc2, enc);
	if (converted == str && enc2 != ascii8bit && enc2 != usascii) { /* conversion failed */
	    rb_enc_check(rb_enc_from_encoding(enc), str);
	}
	str = converted;
    }
    len = RSTRING_LEN(str);
    if (len == 0) return 0;
    check_modifiable(ptr);
    olen = RSTRING_LEN(ptr->string);
    if (ptr->flags & FMODE_APPEND) {
	ptr->pos = olen;
    }
    if (ptr->pos == olen) {
	if (enc == ascii8bit || enc2 == ascii8bit) {
	    rb_enc_str_buf_cat(ptr->string, RSTRING_PTR(str), len, enc);
	}
	else {
	    rb_str_buf_append(ptr->string, str);
	}
    }
    else {
	strio_extend(ptr, ptr->pos, len);
	memmove(RSTRING_PTR(ptr->string)+ptr->pos, RSTRING_PTR(str), len);
    }
    RB_GC_GUARD(str);
    ptr->pos += len;
    return len;
}

/*
 * call-seq:
 *   strio << obj     -> strio
 *
 * See IO#<<.
 */
#define strio_addstr rb_io_addstr

/*
 * call-seq:
 *   strio.print()             -> nil
 *   strio.print(obj, ...)     -> nil
 *
 * See IO#print.
 */
#define strio_print rb_io_print

/*
 * call-seq:
 *   strio.printf(format_string [, obj, ...] )   -> nil
 *
 * See IO#printf.
 */
#define strio_printf rb_io_printf

/*
 * call-seq:
 *   strio.putc(obj)    -> obj
 *
 * See IO#putc.
 */
static VALUE
strio_putc(VALUE self, VALUE ch)
{
    struct StringIO *ptr = writable(self);
    VALUE str;

    check_modifiable(ptr);
    if (RB_TYPE_P(ch, T_STRING)) {
	str = rb_str_substr(ch, 0, 1);
    }
    else {
	char c = NUM2CHR(ch);
	str = rb_str_new(&c, 1);
    }
    strio_write(self, str);
    return ch;
}

/*
 * call-seq:
 *   strio.puts(obj, ...)    -> nil
 *
 * See IO#puts.
 */
#define strio_puts rb_io_puts

/*
 * call-seq:
 *   strio.read([length [, outbuf]])    -> string, outbuf, or nil
 *
 * See IO#read.
 */
static VALUE
strio_read(int argc, VALUE *argv, VALUE self)
{
    struct StringIO *ptr = readable(self);
    VALUE str = Qnil;
    long len;
    int binary = 0;

    switch (argc) {
      case 2:
	str = argv[1];
	if (!NIL_P(str)) {
	    StringValue(str);
	    rb_str_modify(str);
	}
	/* fall through */
      case 1:
	if (!NIL_P(argv[0])) {
	    len = NUM2LONG(argv[0]);
	    if (len < 0) {
		rb_raise(rb_eArgError, "negative length %ld given", len);
	    }
	    if (len > 0 && ptr->pos >= RSTRING_LEN(ptr->string)) {
		if (!NIL_P(str)) rb_str_resize(str, 0);
		return Qnil;
	    }
	    binary = 1;
	    break;
	}
	/* fall through */
      case 0:
	len = RSTRING_LEN(ptr->string);
	if (len <= ptr->pos) {
	    rb_encoding *enc = get_enc(ptr);
	    if (NIL_P(str)) {
		str = rb_str_new(0, 0);
	    }
	    else {
		rb_str_resize(str, 0);
	    }
	    rb_enc_associate(str, enc);
	    return str;
	}
	else {
	    len -= ptr->pos;
	}
	break;
      default:
        rb_error_arity(argc, 0, 2);
    }
    if (NIL_P(str)) {
	rb_encoding *enc = binary ? rb_ascii8bit_encoding() : get_enc(ptr);
	str = strio_substr(ptr, ptr->pos, len, enc);
    }
    else {
	long rest = RSTRING_LEN(ptr->string) - ptr->pos;
	if (len > rest) len = rest;
	rb_str_resize(str, len);
	MEMCPY(RSTRING_PTR(str), RSTRING_PTR(ptr->string) + ptr->pos, char, len);
	if (binary)
	    rb_enc_associate(str, rb_ascii8bit_encoding());
	else
	    rb_enc_copy(str, ptr->string);
    }
    ptr->pos += RSTRING_LEN(str);
    return str;
}

/*
 * call-seq:
 *   strio.sysread(integer[, outbuf])    -> string
 *   strio.readpartial(integer[, outbuf])    -> string
 *
 * Similar to #read, but raises +EOFError+ at end of string instead of
 * returning +nil+, as well as IO#sysread does.
 */
static VALUE
strio_sysread(int argc, VALUE *argv, VALUE self)
{
    VALUE val = rb_funcallv_kw(self, rb_intern("read"), argc, argv, RB_PASS_CALLED_KEYWORDS);
    if (NIL_P(val)) {
	rb_eof_error();
    }
    return val;
}

/*
 * call-seq:
 *   strio.read_nonblock(integer[, outbuf [, opts]])    -> string
 *
 * Similar to #read, but raises +EOFError+ at end of string unless the
 * +exception: false+ option is passed in.
 */
static VALUE
strio_read_nonblock(int argc, VALUE *argv, VALUE self)
{
    VALUE opts = Qnil, val;

    rb_scan_args(argc, argv, "11:", NULL, NULL, &opts);

    if (!NIL_P(opts)) {
	argc--;
    }

    val = strio_read(argc, argv, self);
    if (NIL_P(val)) {
	if (!NIL_P(opts) &&
	      rb_hash_lookup2(opts, sym_exception, Qundef) == Qfalse)
	    return Qnil;
	else
	    rb_eof_error();
    }

    return val;
}

#define strio_syswrite rb_io_write

static VALUE
strio_syswrite_nonblock(int argc, VALUE *argv, VALUE self)
{
    VALUE str;

    rb_scan_args(argc, argv, "10:", &str, NULL);
    return strio_syswrite(self, str);
}

#define strio_isatty strio_false

#define strio_pid strio_nil

#define strio_fileno strio_nil

/*
 * call-seq:
 *   strio.length -> integer
 *   strio.size   -> integer
 *
 * Returns the size of the buffer string.
 */
static VALUE
strio_size(VALUE self)
{
    VALUE string = StringIO(self)->string;
    if (NIL_P(string)) {
	rb_raise(rb_eIOError, "not opened");
    }
    return ULONG2NUM(RSTRING_LEN(string));
}

/*
 * call-seq:
 *   strio.truncate(integer)    -> 0
 *
 * Truncates the buffer string to at most _integer_ bytes. The stream
 * must be opened for writing.
 */
static VALUE
strio_truncate(VALUE self, VALUE len)
{
    VALUE string = writable(self)->string;
    long l = NUM2LONG(len);
    long plen = RSTRING_LEN(string);
    if (l < 0) {
	error_inval("negative length");
    }
    rb_str_resize(string, l);
    if (plen < l) {
	MEMZERO(RSTRING_PTR(string) + plen, char, l - plen);
    }
    return len;
}

/*
 *  call-seq:
 *     strio.external_encoding   => encoding
 *
 *  Returns the Encoding object that represents the encoding of the file.
 *  If the stream is write mode and no encoding is specified, returns
 *  +nil+.
 */

static VALUE
strio_external_encoding(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    return rb_enc_from_encoding(get_enc(ptr));
}

/*
 *  call-seq:
 *     strio.internal_encoding   => encoding
 *
 *  Returns the Encoding of the internal string if conversion is
 *  specified.  Otherwise returns +nil+.
 */

static VALUE
strio_internal_encoding(VALUE self)
{
    return Qnil;
}

/*
 *  call-seq:
 *     strio.set_encoding(ext_enc, [int_enc[, opt]])  => strio
 *
 *  Specify the encoding of the StringIO as <i>ext_enc</i>.
 *  Use the default external encoding if <i>ext_enc</i> is nil.
 *  2nd argument <i>int_enc</i> and optional hash <i>opt</i> argument
 *  are ignored; they are for API compatibility to IO.
 */

static VALUE
strio_set_encoding(int argc, VALUE *argv, VALUE self)
{
    rb_encoding* enc;
    struct StringIO *ptr = StringIO(self);
    VALUE ext_enc, int_enc, opt;

    argc = rb_scan_args(argc, argv, "11:", &ext_enc, &int_enc, &opt);

    if (NIL_P(ext_enc)) {
	enc = rb_default_external_encoding();
    }
    else {
	enc = rb_to_encoding(ext_enc);
    }
    ptr->enc = enc;
    if (WRITABLE(self)) {
	rb_enc_associate(ptr->string, enc);
    }

    return self;
}

static VALUE
strio_set_encoding_by_bom(VALUE self)
{
    struct StringIO *ptr = StringIO(self);

    if (!set_encoding_by_bom(ptr)) return Qnil;
    return rb_enc_from_encoding(ptr->enc);
}

/*
 * Pseudo I/O on String object, with interface corresponding to IO.
 *
 * Commonly used to simulate <code>$stdio</code> or <code>$stderr</code>
 *
 * === Examples
 *
 *   require 'stringio'
 *
 *   # Writing stream emulation
 *   io = StringIO.new
 *   io.puts "Hello World"
 *   io.string #=> "Hello World\n"
 *
 *   # Reading stream emulation
 *   io = StringIO.new "first\nsecond\nlast\n"
 *   io.getc #=> "f"
 *   io.gets #=> "irst\n"
 *   io.read #=> "second\nlast\n"
 */
void
Init_stringio(void)
{
#undef rb_intern

#ifdef HAVE_RB_EXT_RACTOR_SAFE
  rb_ext_ractor_safe(true);
#endif

    VALUE StringIO = rb_define_class("StringIO", rb_cObject);

    rb_define_const(StringIO, "VERSION", rb_str_new_cstr(STRINGIO_VERSION));

    rb_include_module(StringIO, rb_mEnumerable);
    rb_define_alloc_func(StringIO, strio_s_allocate);
    rb_define_singleton_method(StringIO, "new", strio_s_new, -1);
    rb_define_singleton_method(StringIO, "open", strio_s_open, -1);
    rb_define_method(StringIO, "initialize", strio_initialize, -1);
    rb_define_method(StringIO, "initialize_copy", strio_copy, 1);
    rb_define_method(StringIO, "reopen", strio_reopen, -1);

    rb_define_method(StringIO, "string", strio_get_string, 0);
    rb_define_method(StringIO, "string=", strio_set_string, 1);
    rb_define_method(StringIO, "lineno", strio_get_lineno, 0);
    rb_define_method(StringIO, "lineno=", strio_set_lineno, 1);


    /* call-seq: strio.binmode -> true */
    rb_define_method(StringIO, "binmode", strio_binmode, 0);
    rb_define_method(StringIO, "close", strio_close, 0);
    rb_define_method(StringIO, "close_read", strio_close_read, 0);
    rb_define_method(StringIO, "close_write", strio_close_write, 0);
    rb_define_method(StringIO, "closed?", strio_closed, 0);
    rb_define_method(StringIO, "closed_read?", strio_closed_read, 0);
    rb_define_method(StringIO, "closed_write?", strio_closed_write, 0);
    rb_define_method(StringIO, "eof", strio_eof, 0);
    rb_define_method(StringIO, "eof?", strio_eof, 0);
    /* call-seq: strio.fcntl */
    rb_define_method(StringIO, "fcntl", strio_fcntl, -1);
    /* call-seq: strio.flush -> strio */
    rb_define_method(StringIO, "flush", strio_flush, 0);
    /* call-seq: strio.fsync -> 0 */
    rb_define_method(StringIO, "fsync", strio_fsync, 0);
    rb_define_method(StringIO, "pos", strio_get_pos, 0);
    rb_define_method(StringIO, "pos=", strio_set_pos, 1);
    rb_define_method(StringIO, "rewind", strio_rewind, 0);
    rb_define_method(StringIO, "seek", strio_seek, -1);
    rb_define_method(StringIO, "sync", strio_get_sync, 0);
    /* call-seq: strio.sync = boolean -> boolean */
    rb_define_method(StringIO, "sync=", strio_set_sync, 1);
    rb_define_method(StringIO, "tell", strio_tell, 0);

    rb_define_method(StringIO, "each", strio_each, -1);
    rb_define_method(StringIO, "each_line", strio_each, -1);
    rb_define_method(StringIO, "each_byte", strio_each_byte, 0);
    rb_define_method(StringIO, "each_char", strio_each_char, 0);
    rb_define_method(StringIO, "each_codepoint", strio_each_codepoint, 0);
    rb_define_method(StringIO, "getc", strio_getc, 0);
    rb_define_method(StringIO, "ungetc", strio_ungetc, 1);
    rb_define_method(StringIO, "ungetbyte", strio_ungetbyte, 1);
    rb_define_method(StringIO, "getbyte", strio_getbyte, 0);
    rb_define_method(StringIO, "gets", strio_gets, -1);
    rb_define_method(StringIO, "readlines", strio_readlines, -1);
    rb_define_method(StringIO, "read", strio_read, -1);

    rb_define_method(StringIO, "write", strio_write_m, -1);
    rb_define_method(StringIO, "putc", strio_putc, 1);

    /*
     * call-seq:
     *   strio.isatty -> nil
     *   strio.tty? -> nil
     *
     */
    rb_define_method(StringIO, "isatty", strio_isatty, 0);
    rb_define_method(StringIO, "tty?", strio_isatty, 0);

    /* call-seq: strio.pid -> nil */
    rb_define_method(StringIO, "pid", strio_pid, 0);

    /* call-seq: strio.fileno -> nil */
    rb_define_method(StringIO, "fileno", strio_fileno, 0);
    rb_define_method(StringIO, "size", strio_size, 0);
    rb_define_method(StringIO, "length", strio_size, 0);
    rb_define_method(StringIO, "truncate", strio_truncate, 1);

    rb_define_method(StringIO, "external_encoding", strio_external_encoding, 0);
    rb_define_method(StringIO, "internal_encoding", strio_internal_encoding, 0);
    rb_define_method(StringIO, "set_encoding", strio_set_encoding, -1);
    rb_define_method(StringIO, "set_encoding_by_bom", strio_set_encoding_by_bom, 0);

    {
	VALUE mReadable = rb_define_module_under(rb_cIO, "generic_readable");
	rb_define_method(mReadable, "readchar", strio_readchar, 0);
	rb_define_method(mReadable, "readbyte", strio_readbyte, 0);
	rb_define_method(mReadable, "readline", strio_readline, -1);
	rb_define_method(mReadable, "sysread", strio_sysread, -1);
	rb_define_method(mReadable, "readpartial", strio_sysread, -1);
	rb_define_method(mReadable, "read_nonblock", strio_read_nonblock, -1);
	rb_include_module(StringIO, mReadable);
    }
    {
	VALUE mWritable = rb_define_module_under(rb_cIO, "generic_writable");
	rb_define_method(mWritable, "<<", strio_addstr, 1);
	rb_define_method(mWritable, "print", strio_print, -1);
	rb_define_method(mWritable, "printf", strio_printf, -1);
	rb_define_method(mWritable, "puts", strio_puts, -1);
	rb_define_method(mWritable, "syswrite", strio_syswrite, 1);
	rb_define_method(mWritable, "write_nonblock", strio_syswrite_nonblock, -1);
	rb_include_module(StringIO, mWritable);
    }

    sym_exception = ID2SYM(rb_intern("exception"));
}
