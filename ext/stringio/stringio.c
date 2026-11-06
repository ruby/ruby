/* -*- mode: c; indent-tabs-mode: t -*- */
/**********************************************************************

  stringio.c -

  $Author$
  $RoughId: stringio.c,v 1.13 2002/03/14 03:24:18 nobu Exp $
  created at: Tue Feb 19 04:10:38 JST 2002

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

static const char *const
STRINGIO_VERSION = "3.2.1.dev";

#include <stdbool.h>

#include "ruby.h"
#include "ruby/io.h"
#include "ruby/encoding.h"
#include "ruby/version.h"
#if defined(HAVE_FCNTL_H) || defined(_WIN32)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
#include <sys/fcntl.h>
#endif

#ifndef SIZEOF_RB_LEN_T
# define SIZEOF_RB_LEN_T SIZEOF_LONG
# define RB_LEN_MAX LONG_MAX
# define NUM2LEN(num) NUM2LONG(num)
# define NUM2ULEN(num) NUM2ULONG(num)
# define LEN2NUM(num) LONG2NUM(num)
# define ULEN2NUM(num) ULONG2NUM(num)
# define PRIdLEN "ld"
typedef long rb_len_t;
typedef unsigned long rb_ulen_t;
#endif

#ifndef RB_INTEGER_TYPE_P
# define RB_INTEGER_TYPE_P(c) (FIXNUM_P(c) || RB_TYPE_P(c, T_BIGNUM))
#endif

/* strio_free may run on any thread, so the refcount shared by #initialize_copy must be atomic */
#ifdef RUBY_TYPED_THREAD_SAFE_FREE
# include "ruby/atomic.h"
typedef rb_atomic_t strio_refcnt_t;
# define STRIO_REFCNT_INC(ptr) RUBY_ATOMIC_INC((ptr)->count)
# define STRIO_REFCNT_DEC(ptr) (RUBY_ATOMIC_FETCH_SUB((ptr)->count, 1) == 1)
#else
# define RUBY_TYPED_THREAD_SAFE_FREE RUBY_TYPED_FREE_IMMEDIATELY
typedef int strio_refcnt_t;
# define STRIO_REFCNT_INC(ptr) ((void)++(ptr)->count)
# define STRIO_REFCNT_DEC(ptr) (--(ptr)->count <= 0)
#endif

#ifndef RB_PASS_CALLED_KEYWORDS
# define rb_funcallv_kw(recv, mid, arg, argv, kw_splat) rb_funcallv(recv, mid, arg, argv)
# define rb_class_new_instance_kw(argc, argv, klass, kw_splat) rb_class_new_instance(argc, argv, klass)
#endif

static inline bool
str_chilled_p(VALUE str)
{
#if RUBY_API_VERSION_CODE >= 40100
    // Do not attempt to modify chilled strings on Ruby 4.1+
    // RUBY_FL_USER2 == STR_CHILLED
    return FL_TEST_RAW(str, RUBY_FL_USER2);
#elif RUBY_API_VERSION_CODE >= 30400
    // Do not attempt to modify chilled strings on Ruby 3.4+
    // RUBY_FL_USER2 == STR_CHILLED_LITERAL
    // RUBY_FL_USER3 == STR_CHILLED_SYMBOL_TO_S
    return FL_TEST_RAW(str, RUBY_FL_USER2 | RUBY_FL_USER3);
#else
    return false;
#endif
}

#ifndef HAVE_TYPE_RB_IO_MODE_T
typedef int rb_io_mode_t;
#endif

struct StringIO {
    VALUE string;
    rb_encoding *enc;
    rb_len_t pos;
    rb_len_t lineno;
    rb_io_mode_t flags;
    strio_refcnt_t count;
};

static struct StringIO *get_strio_for_read(VALUE self);
static VALUE strio_init(int, VALUE *, struct StringIO *, VALUE);
static VALUE strio_unget_bytes(struct StringIO *, const char *, rb_len_t);
static rb_len_t strio_write(VALUE self, VALUE str);

#define IS_STRIO(obj) (rb_typeddata_is_kind_of((obj), &strio_data_type))
#define error_inval(msg) (rb_syserr_fail(EINVAL, msg))
#define get_enc(ptr) ((ptr)->enc ? (ptr)->enc : !NIL_P((ptr)->string) ? rb_enc_get((ptr)->string) : NULL)

static bool
readonly_string_p(VALUE string)
{
    return OBJ_FROZEN_RAW(string);
}

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
    if (STRIO_REFCNT_DEC(ptr)) {
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
    0, 0, RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_WB_PROTECTED
};

#define check_strio(self) ((struct StringIO*)rb_check_typeddata((self), &strio_data_type))

static struct StringIO*
get_strio(VALUE self)
{
    rb_check_frozen(self);
    return get_strio_for_read(self);
}

static struct StringIO*
get_strio_for_read(VALUE self)
{
    struct StringIO *ptr = check_strio(self);
    if (!ptr) {
	rb_raise(rb_eIOError, "uninitialized stream");
    }
    return ptr;
}

static VALUE
enc_subseq(VALUE str, rb_len_t pos, rb_len_t len, rb_encoding *enc)
{
    str = rb_str_subseq(str, pos, len);
    rb_enc_associate(str, enc);
    return str;
}

static VALUE
strio_substr(struct StringIO *ptr, rb_len_t pos, rb_len_t len, rb_encoding *enc)
{
    VALUE str = ptr->string;
    rb_len_t rlen = RSTRING_LEN(str) - pos;

    if (len > rlen) len = rlen;
    if (len < 0) len = 0;
    if (len == 0) return rb_enc_str_new(0, 0, enc);
    return enc_subseq(str, pos, len, enc);
}

static VALUE
strio_readbuf(struct StringIO *ptr, VALUE str)
{
    if (!NIL_P(str)) {
	StringValue(str);
	rb_str_modify(str);
	if (str == ptr->string) {
	    rb_raise(rb_eArgError, "cannot read into the underlying string");
	}
    }
    return str;
}

#define StringIO(obj) get_strio(obj)
#define StringIOForRead(obj) get_strio_for_read(obj)

#define STRIO_READABLE FL_USER4
#define STRIO_WRITABLE FL_USER5
#define STRIO_READWRITE (STRIO_READABLE|STRIO_WRITABLE)
typedef char strio_flags_check[(STRIO_READABLE/FMODE_READABLE == STRIO_WRITABLE/FMODE_WRITABLE) * 2 - 1];
#ifndef RB_FL_TEST_RAW
# define RB_FL_TEST_RAW(obj, bits) (RBASIC(obj)->flags & (bits))
#endif
#ifndef RB_FL_SET_RAW
# define RB_FL_SET_RAW(obj, bits) (RBASIC(obj)->flags |= (bits))
#endif
#ifndef RB_FL_UNSET_RAW
# define RB_FL_UNSET_RAW(obj, bits) (RBASIC(obj)->flags &= ~(bits))
#endif

#define STRIO_MODE_SET_P(strio, mode) \
    (RB_FL_TEST_RAW(strio, STRIO_##mode) && \
     ((struct StringIO*)DATA_PTR(strio))->flags & FMODE_##mode)
#define CLOSED(strio) (!STRIO_MODE_SET_P(strio, READWRITE))
#define READABLE(strio) STRIO_MODE_SET_P(strio, READABLE)
#define WRITABLE(strio) STRIO_MODE_SET_P(strio, WRITABLE)

static VALUE sym_exception;

static struct StringIO*
readable(VALUE strio)
{
    struct StringIO *ptr = StringIOForRead(strio);
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
    if (NIL_P(ptr->string)) {
	/* Null device StringIO */
    }
    else if (OBJ_FROZEN_RAW(ptr->string)) {
	rb_raise(rb_eIOError, "not modifiable string");
    }
    else {
	rb_str_modify(ptr->string);
    }
}

static inline bool
outside_p(struct StringIO *ptr, rb_len_t pos)
{
    return NIL_P(ptr->string) || pos >= RSTRING_LEN(ptr->string);
}

static inline bool
eos_p(struct StringIO *ptr)
{
    return outside_p(ptr, ptr->pos);
}

static VALUE
strio_s_allocate(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &strio_data_type, 0);
}

/*
 * call-seq:
 *   StringIO.new(string = '', mode = 'r+') -> new_stringio
 *
 * Returns a new \StringIO instance formed from +string+ and +mode+;
 * the instance should be closed when no longer needed:
 *
 *   strio = StringIO.new
 *   strio.string        # => ""
 *   strio.closed_read?  # => false
 *   strio.closed_write? # => false
 *   strio.close
 *
 * If +string+ is frozen, the default +mode+ is <tt>'r'</tt>:
 *
 *   strio = StringIO.new('foo'.freeze)
 *   strio.string        # => "foo"
 *   strio.closed_read?  # => false
 *   strio.closed_write? # => true
 *   strio.close
 *
 * Argument +mode+ must be a valid
 * {Access Mode}[rdoc-ref:File@Access+Modes],
 * which may be a string or an integer constant:
 *
 *   StringIO.new('foo', 'w+')
 *   StringIO.new('foo', File::RDONLY)
 *
 * Related: StringIO.open
 * (passes the \StringIO object to the block; closes the object automatically on block exit).
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
    rb_len_t len;

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
    rb_io_enc_t convconfig;

    argc = rb_scan_args(argc, argv, "02:", &string, &vmode, &opt);
    rb_io_extract_modeenc(&vmode, 0, opt, &oflags, &ptr->flags, &convconfig);
    if (!NIL_P(string)) {
	StringValue(string);
    }
    else if (!argc) {
	string = rb_enc_str_new("", 0, rb_default_external_encoding());
    }

    if (!NIL_P(string) && readonly_string_p(string)) {
	if (ptr->flags & FMODE_WRITABLE) {
	    rb_syserr_fail(EACCES, 0);
	}
    }
    else {
	if (NIL_P(vmode)) {
	    ptr->flags |= FMODE_WRITABLE;
	}
    }
    if (!NIL_P(string) && (ptr->flags & FMODE_TRUNC)) {
	rb_str_resize(string, 0);
    }
    RB_OBJ_WRITE(self, &ptr->string, string);
    if (argc == 1 && !NIL_P(string)) {
	ptr->enc = rb_enc_get(string);
    }
    else {
	ptr->enc = convconfig.enc;
    }
    ptr->pos = 0;
    ptr->lineno = 0;
    if (ptr->flags & FMODE_SETENC_BY_BOM) set_encoding_by_bom(ptr);
    RB_FL_SET_RAW(self, (ptr->flags & FMODE_READWRITE) * (STRIO_READABLE / FMODE_READABLE));
    return self;
}

static VALUE
strio_finalize(VALUE self)
{
    struct StringIO *ptr = check_strio(self);
    if (!ptr) return Qnil;
    RB_OBJ_WRITE(self, &ptr->string, Qnil);
    ptr->flags &= ~FMODE_READWRITE;
    return self;
}

/*
 * call-seq:
 *   StringIO.open(string = '', mode = 'r+') -> new_stringio
 *   StringIO.open(string = '', mode = 'r+') {|strio| ... } -> object
 *
 * Creates new \StringIO instance by calling <tt>StringIO.new(string, mode)</tt>.
 *
 * With no block given, returns the new instance:
 *
 *   strio = StringIO.open # => #<StringIO>
 *
 * With a block given, calls the block with the new instance
 * and returns the block's value;
 * closes the instance on block exit:
 *
 *   StringIO.open('foo') {|strio| strio.string.upcase } # => "FOO"
 *
 * Related: StringIO.new.
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
 * Returns +false+; for compatibility with IO.
 */
static VALUE
strio_false(VALUE self)
{
    StringIOForRead(self);
    return Qfalse;
}

/*
 * Returns +nil+; for compatibility with IO.
 */
static VALUE
strio_nil(VALUE self)
{
    StringIOForRead(self);
    return Qnil;
}

/*
 * Returns +self+; for compatibility with IO.
 */
static VALUE
strio_self(VALUE self)
{
    StringIOForRead(self);
    return self;
}

/*
 * Returns 0; for compatibility with IO.
 */
static VALUE
strio_0(VALUE self)
{
    StringIOForRead(self);
    return INT2FIX(0);
}

/*
 * Returns the argument unchanged.  Just for compatibility to IO.
 */
static VALUE
strio_first(VALUE self, VALUE arg)
{
    StringIOForRead(self);
    return arg;
}

/*
 * Raises NotImplementedError.
 */
static VALUE
strio_unimpl(int argc, VALUE *argv, VALUE self)
{
    StringIOForRead(self);
    rb_notimplement();

    UNREACHABLE;
}

/*
 * call-seq:
 *   string -> string
 *
 * Returns underlying string:
 *
 *   StringIO.open('foo') do |strio|
 *     p strio.string
 *     strio.string = 'bar'
 *     p strio.string
 *   end
 *
 * Output:
 *
 *   "foo"
 *   "bar"
 *
 * Related: StringIO#string= (assigns the underlying string).
 */
static VALUE
strio_get_string(VALUE self)
{
    return StringIOForRead(self)->string;
}

/*
 * call-seq:
 *   string = other_string -> other_string
 *
 * Replaces the stored string with +other_string+, and sets the position to zero;
 * returns +other_string+:
 *
 *   StringIO.open('foo') do |strio|
 *     p strio.string
 *     strio.string = 'bar'
 *     p strio.string
 *   end
 *
 * Output:
 *
 *   "foo"
 *   "bar"
 *
 * Related: StringIO#string (returns the stored string).
 */
static VALUE
strio_set_string(VALUE self, VALUE string)
{
    struct StringIO *ptr = StringIO(self);

    rb_io_taint_check(self);
    ptr->flags &= ~FMODE_READWRITE;
    StringValue(string);
    ptr->flags = readonly_string_p(string) ? FMODE_READABLE : FMODE_READWRITE;
    ptr->pos = 0;
    ptr->lineno = 0;
    RB_OBJ_WRITE(self, &ptr->string, string);
    return string;
}

/*
 * call-seq:
 *   close -> nil
 *
 * Closes +self+ for both reading and writing; returns +nil+:
 *
 *   strio = StringIO.new
 *   strio.closed? # => false
 *   strio.close   # => nil
 *   strio.closed? # => true
 *   strio.read    # Raises IOError: not opened for reading
 *   strio.write   # Raises IOError: not opened for writing
 *
 * Related: StringIO#close_read, StringIO#close_write, StringIO.closed?.
 */
static VALUE
strio_close(VALUE self)
{
    StringIO(self);
    RB_FL_UNSET_RAW(self, STRIO_READWRITE);
    return Qnil;
}

/*
 * call-seq:
 *   close_read -> nil
 *
 * Closes +self+ for reading;
 * closed-write setting remains unchanged;
 * returns +nil+:
 *
 *   strio = StringIO.new
 *   strio.closed_read?  # => false
 *   strio.close_read    # => nil
 *   strio.closed_read?  # => true
 *   strio.closed_write? # => false
 *   strio.read          # Raises IOError: not opened for reading
 *
 * Related: StringIO#close, StringIO#close_write.
 */
static VALUE
strio_close_read(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    if (!(ptr->flags & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "closing non-duplex IO for reading");
    }
    RB_FL_UNSET_RAW(self, STRIO_READABLE);
    return Qnil;
}

/*
 * call-seq:
 *   close_write -> nil
 *
 * Closes +self+ for writing; closed-read setting remains unchanged; returns +nil+:
 *
 *   strio = StringIO.new
 *   strio.closed_write? # => false
 *   strio.close_write   # => nil
 *   strio.closed_write? # => true
 *   strio.closed_read?  # => false
 *   strio.write('foo')  # Raises IOError: not opened for writing
 *
 * Related: StringIO#close, StringIO#close_read, StringIO#closed_write?.
 */
static VALUE
strio_close_write(VALUE self)
{
    struct StringIO *ptr = StringIO(self);
    if (!(ptr->flags & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "closing non-duplex IO for writing");
    }
    RB_FL_UNSET_RAW(self, STRIO_WRITABLE);
    return Qnil;
}

/*
 * call-seq:
 *   closed? -> true or false
 *
 * Returns whether +self+ is closed for both reading and writing:
 *
 *   strio = StringIO.new
 *   strio.closed?     # => false  # Open for reading and writing.
 *   strio.close_read
 *   strio.closed?     # => false  # Still open for writing.
 *   strio.close_write
 *   strio.closed?     # => true   # Now closed for both.
 *
 * Related: StringIO.closed_read?, StringIO.closed_write?.
 */
static VALUE
strio_closed(VALUE self)
{
    StringIOForRead(self);
    if (!CLOSED(self)) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   closed_read? -> true or false
 *
 * Returns whether +self+ is closed for reading:
 *
 *   strio = StringIO.new
 *   strio.closed_read?   # => false
 *   strio.close_read
 *   strio.closed_read?   # => true
 *
 * Related: StringIO#closed?, StringIO#closed_write?, StringIO#close_read.
 */
static VALUE
strio_closed_read(VALUE self)
{
    StringIOForRead(self);
    if (READABLE(self)) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   closed_write? -> true or false
 *
 * Returns whether +self+ is closed for writing:
 *
 *   strio = StringIO.new
 *   strio.closed_write? # => false
 *   strio.close_write
 *   strio.closed_write? # => true
 *
 * Related: StringIO#close_write, StringIO#closed?, StringIO#closed_read?.
 */
static VALUE
strio_closed_write(VALUE self)
{
    StringIOForRead(self);
    if (WRITABLE(self)) return Qfalse;
    return Qtrue;
}

static struct StringIO *
strio_to_read(VALUE self)
{
    struct StringIO *ptr = readable(self);
    if (eos_p(ptr)) return NULL;
    return ptr;
}

/*
 * call-seq:
 *   eof? -> true or false
 *
 * Returns whether +self+ is positioned at end-of-stream:
 *
 *   strio = StringIO.new('foo')
 *   strio.pos  # => 0
 *   strio.eof? # => false
 *   strio.read # => "foo"
 *   strio.pos  # => 3
 *   strio.eof? # => true
 *   strio.close_read
 *   strio.eof? # Raises IOError: not opened for reading
 *
 * Related: StringIO#pos.
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
    struct StringIO *ptr, *old_ptr;
    VALUE old_string = Qundef;

    orig = rb_convert_type(orig, T_DATA, "StringIO", "to_strio");
    if (copy == orig) return copy;
    ptr = StringIOForRead(orig);
    old_ptr = check_strio(copy);
    if (old_ptr) {
	old_string = old_ptr->string;
	strio_free(old_ptr);
    }
    DATA_PTR(copy) = ptr;
    RB_OBJ_WRITTEN(copy, old_string, ptr->string);
    RB_FL_UNSET_RAW(copy, STRIO_READWRITE);
    RB_FL_SET_RAW(copy, RB_FL_TEST_RAW(orig, STRIO_READWRITE));
    STRIO_REFCNT_INC(ptr);
    return copy;
}

/*
 * call-seq:
 *   lineno -> current_line_number
 *
 * Returns the current line number in +self+;
 * see {Line Number}[rdoc-ref:StringIO@Line+Number].
 */
static VALUE
strio_get_lineno(VALUE self)
{
    return LEN2NUM(StringIOForRead(self)->lineno);
}

/*
 * call-seq:
 *   lineno = new_line_number -> new_line_number
 *
 * Sets the current line number in +self+ to the given +new_line_number+;
 * see {Line Number}[rdoc-ref:StringIO@Line+Number].
 */
static VALUE
strio_set_lineno(VALUE self, VALUE lineno)
{
    StringIO(self)->lineno = NUM2LEN(lineno);
    return lineno;
}

/*
 * call-seq:
 *   binmode -> self
 *
 * Sets the data mode in +self+ to binary mode;
 * see {Data Mode}[rdoc-ref:StringIO@Data+Mode].
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
 *   reopen(other, mode = 'r+') -> self
 *
 * Reinitializes the stream with the given +other+ (string or StringIO) and +mode+;
 * see IO.new:
 *
 *   StringIO.open('foo') do |strio|
 *     p strio.string
 *     strio.reopen('bar')
 *     p strio.string
 *     other_strio = StringIO.new('baz')
 *     strio.reopen(other_strio)
 *     p strio.string
 *     other_strio.close
 *   end
 *
 * Output:
 *
 *   "foo"
 *   "bar"
 *   "baz"
 *
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
 *   pos -> stream_position
 *
 * Returns the current position (in bytes);
 * see {Position}[rdoc-ref:StringIO@Position].
 */
static VALUE
strio_get_pos(VALUE self)
{
    return LEN2NUM(StringIOForRead(self)->pos);
}

/*
 * call-seq:
 *   pos = new_position -> new_position
 *
 * Sets the current position (in bytes);
 * see {Position}[rdoc-ref:StringIO@Position].
 */
static VALUE
strio_set_pos(VALUE self, VALUE pos)
{
    struct StringIO *ptr = StringIO(self);
    rb_len_t p = NUM2LEN(pos);
    if (p < 0) {
	error_inval(0);
    }
    ptr->pos = p;
    return pos;
}

/*
 * call-seq:
 *   rewind -> 0
 *
 * Sets the current position and line number to zero;
 * see {Position}[rdoc-ref:IO@Position]
 * and {Line Number}[rdoc-ref:IO@Line+Number].
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
 *   seek(offset, whence = SEEK_SET) -> 0
 *
 * Sets the position to the given integer +offset+ (in bytes),
 * with respect to a given constant +whence+;
 * see {IO#seek}[rdoc-ref:IO#seek].
 */
static VALUE
strio_seek(int argc, VALUE *argv, VALUE self)
{
    VALUE whence;
    struct StringIO *ptr = StringIO(self);
    rb_len_t amount, offset;

    rb_scan_args(argc, argv, "11", NULL, &whence);
    amount = NUM2LEN(argv[0]);
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
	if (NIL_P(ptr->string)) {
	    offset = 0;
	}
	else {
	    offset = RSTRING_LEN(ptr->string);
	}
	break;
      default:
	error_inval("invalid whence");
    }
    if (amount > RB_LEN_MAX - offset || amount + offset < 0) {
	error_inval(0);
    }
    ptr->pos = amount + offset;
    return INT2FIX(0);
}

/*
 * call-seq:
 *   sync -> true
 *
 * Returns +true+; implemented only for compatibility with other stream classes.
 */
static VALUE
strio_get_sync(VALUE self)
{
    StringIOForRead(self);
    return Qtrue;
}

#define strio_set_sync strio_first

#define strio_tell strio_get_pos

/*
 * call-seq:
 *   each_byte {|byte| ... } -> self
 *
 * With a block given, calls the block with each remaining byte in the stream;
 * positions the stream at end-of-file;
 * returns +self+:
 *
 *   bytes = []
 *   strio = StringIO.new('hello')     #  Five 1-byte characters.
 *   strio.each_byte {|byte| bytes.push(byte) }
 *   strio.eof? # => true
 *   bytes # => [104, 101, 108, 108, 111]
 *
 *   bytes = []
 *   strio = StringIO.new('こんにちは')  # Five 3-byte characters.
 *   strio.each_byte {|byte| bytes.push(byte) }
 *   bytes # => [227, 129, 147, 227, 130, 147, 227, 129, 171, 227, 129, 161, 227, 129, 175]
 *
 * The position in the stream matters:
 *
 *   bytes = []
 *   strio = StringIO.new('こんにちは')
 *   strio.getc # => "こ"
 *   strio.pos  # => 3  # 3-byte character was read.
 *   strio.each_byte {|byte| bytes.push(byte) }
 *   bytes      # => [227, 130, 147, 227, 129, 171, 227, 129, 161, 227, 129, 175]
 *
 * If at end-of-file, does not call the block:
 *
 *   strio.eof? # => true
 *   strio.each_byte {|byte| fail 'Boo!' }
 *   strio.eof? # => true
 *
 * With no block given, returns a new {Enumerator}[rdoc-ref:Enumerator].
 *
 * Related: StringIO#each_char, StringIO#each_codepoint, StringIO#each_line.
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
 *   getc -> character, byte, or nil
 *
 * Reads and returns the next character (or byte; see below) from the stream:
 *
 *   strio = StringIO.new('foo')
 *   strio.getc # => "f"
 *   strio.getc # => "o"
 *   strio.getc # => "o"
 *
 * Returns +nil+ if at end-of-stream:
 *
 *   strio.eof? # => true
 *   strio.getc # => nil
 *
 * Returns characters, not bytes:
 *
 *   strio = StringIO.new('こんにちは')
 *   strio.getc # => "こ"
 *   strio.getc # => "ん"
 *
 * In each of the examples above, the stream is positioned at the beginning of a character;
 * in other cases that need not be true:
 *
 *    strio = StringIO.new('こんにちは')  # Five 3-byte characters.
 *    strio.pos = 3 # => 3     # At beginning of second character; returns character.
 *    strio.getc    # => "ん"
 *    strio.pos = 4 # => 4     # At second byte of second character; returns byte.
 *    strio.getc    # => "\x82"
 *    strio.pos = 5 # => 5     # At third byte of second character; returns byte.
 *    strio.getc    # => "\x93"
 *
 * Related: #getbyte, #putc, #ungetc.
 *
 */
static VALUE
strio_getc(VALUE self)
{
    struct StringIO *ptr = readable(self);
    rb_encoding *enc = get_enc(ptr);
    VALUE str = ptr->string;
    rb_len_t pos = ptr->pos;
    int len;
    char *p;

    if (eos_p(ptr)) {
	return Qnil;
    }
    p = RSTRING_PTR(str)+pos;
    len = rb_enc_mbclen(p, RSTRING_END(str), enc);
    ptr->pos += len;
    return enc_subseq(str, pos, len, enc);
}

/*
 * call-seq:
 *   getbyte -> integer or nil
 *
 * Reads and returns the next integer byte (not character) from the stream:
 *
 *   s = 'foo'
 *   s.bytes       # => [102, 111, 111]
 *   strio = StringIO.new(s)
 *   strio.getbyte # => 102
 *   strio.getbyte # => 111
 *   strio.getbyte # => 111
 *
 * Returns +nil+ if at end-of-stream:
 *
 *   strio.eof?    # => true
 *   strio.getbyte # => nil
 *
 * Returns a byte, not a character:
 *
 *   s = 'こんにちは'
 *   s.bytes
 *   # => [227, 129, 147, 227, 130, 147, 227, 129, 171, 227, 129, 161, 227, 129, 175]
 *   strio = StringIO.new(s)
 *   strio.getbyte # => 227
 *   strio.getbyte # => 129
 *
 * Related: #each_byte, #ungetbyte, #getc.
 *
 */
static VALUE
strio_getbyte(VALUE self)
{
    struct StringIO *ptr = readable(self);
    int c;
    if (eos_p(ptr)) {
	return Qnil;
    }
    c = RSTRING_PTR(ptr->string)[ptr->pos++];
    return CHR2FIX(c);
}

static void
strio_extend(struct StringIO *ptr, rb_len_t pos, rb_len_t len)
{
    rb_len_t olen;

    if (len > RB_LEN_MAX - pos)
	rb_raise(rb_eArgError, "string size too big");

    check_modifiable(ptr);
    olen = RSTRING_LEN(ptr->string);
    if (pos + len > olen) {
	rb_str_resize(ptr->string, pos + len);
	if (pos > olen)
	    MEMZERO(RSTRING_PTR(ptr->string) + olen, char, pos - olen);
    }
}

static void
strio_unget_string(struct StringIO *ptr, VALUE c)
{
    const char *cp = NULL;
    rb_len_t cl = RSTRING_LEN(c);
    if (cl > 0) {
	if (c != ptr->string) cp = RSTRING_PTR(c);
	strio_unget_bytes(ptr, cp, cl);
	RB_GC_GUARD(c);
    }
}

/*
 * call-seq:
 *   ungetc(character) -> nil
 *
 * Pushes back ("unshifts") a character or integer onto the stream;
 * see {Character IO}[rdoc-ref:IO@Character+IO].
 */
static VALUE
strio_ungetc(VALUE self, VALUE c)
{
    struct StringIO *ptr = readable(self);
    rb_encoding *enc, *enc2;

    check_modifiable(ptr);
    if (NIL_P(ptr->string)) return Qnil;
    if (NIL_P(c)) return Qnil;
    if (RB_INTEGER_TYPE_P(c)) {
	int len, cc = NUM2INT(c);
	char buf[16];

	enc = rb_enc_get(ptr->string);
	len = rb_enc_codelen(cc, enc);
	if (len <= 0) {
	    rb_enc_uint_chr(cc, enc); /* to raise an exception */
	    UNREACHABLE;
	}
	rb_enc_mbcput(cc, buf, enc);
	return strio_unget_bytes(ptr, buf, len);
    }
    else {
	StringValue(c);
	if (RSTRING_LEN(c) == 0) return Qnil;
	enc = rb_enc_get(ptr->string);
	enc2 = rb_enc_get(c);
	if (enc != enc2 && enc != rb_ascii8bit_encoding()) {
	    c = rb_str_conv_enc(c, enc2, enc);
	}
	strio_unget_string(ptr, c);
	return Qnil;
    }
}

/*
 * call-seq:
 *   ungetbyte(byte) -> nil
 *
 * Pushes back ("unshifts") an 8-bit byte onto the stream;
 * see {Byte IO}[rdoc-ref:IO@Byte+IO].
 */
static VALUE
strio_ungetbyte(VALUE self, VALUE c)
{
    struct StringIO *ptr = readable(self);

    check_modifiable(ptr);
    if (NIL_P(ptr->string)) return Qnil;
    if (NIL_P(c)) return Qnil;
    if (RB_INTEGER_TYPE_P(c)) {
	/* rb_int_and() not visible from exts */
	VALUE v = rb_funcall(c, '&', 1, INT2FIX(0xff));
	const char cc = NUM2INT(v) & 0xFF;
	strio_unget_bytes(ptr, &cc, 1);
    }
    else {
	StringValue(c);
	strio_unget_string(ptr, c);
    }
    return Qnil;
}

static VALUE
strio_unget_bytes(struct StringIO *ptr, const char *cp, rb_len_t cl)
{
    rb_len_t pos = ptr->pos, len, rest;
    VALUE str = ptr->string;
    char *s;

    len = RSTRING_LEN(str);
    rest = pos - len;
    if (cl > pos) {
	rb_len_t ex = cl - (rest < 0 ? pos : len);
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
    memcpy(s + pos, (cp ? cp : s), cl);
    ptr->pos = pos;
    return Qnil;
}

/*
 * call-seq:
 *   readchar -> string
 *
 * Like +getc+, but raises an exception if already at end-of-stream;
 * see {Character IO}[rdoc-ref:IO@Character+IO].
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
 *   readbyte -> byte
 *
 * Like +getbyte+, but raises an exception if already at end-of-stream;
 * see {Byte IO}[rdoc-ref:IO@Byte+IO].
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
 *   each_char {|char| ... } -> self
 *
 * With a block given, calls the block with each remaining character in the stream;
 * positions the stream at end-of-file;
 * returns +self+:
 *
 *   chars = []
 *   strio = StringIO.new('hello')
 *   strio.each_char {|char| chars.push(char) }
 *   strio.eof? # => true
 *   chars      # => ["h", "e", "l", "l", "o"]
 *
 *   chars = []
 *   strio = StringIO.new('こんにちは')
 *   strio.each_char {|char| chars.push(char) }
 *   chars      # => ["こ", "ん", "に", "ち", "は"]
 *
 * Stream position matters:
 *
 *  chars = []
 *  strio = StringIO.new('こんにちは')
 *  strio.getc # => "こ"
 *  strio.pos  # => 3  # 3-byte character was read.
 *  strio.each_char {|char| chars.push(char) }
 *  chars      # => ["ん", "に", "ち", "は"]
 *
 * When at end-of-stream does not call the block:
 *
 *   strio.eof? # => true
 *   strio.each_char {|char| fail 'Boo!' }
 *   strio.eof? # => true
 *
 * With no block given, returns a new {Enumerator}[rdoc-ref:Enumerator].
 *
 * Related: StringIO#each_byte, StringIO#each_codepoint, StringIO#each_line.
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
 *   each_codepoint {|codepoint| ... } -> self
 *
 * With a block given, calls the block with each successive codepoint from self;
 * sets the position to end-of-stream;
 * returns +self+.
 *
 * Each codepoint is the integer value for a character; returns self:
 *
 *   codepoints = []
 *   strio = StringIO.new('hello')
 *   strio.each_codepoint {|codepoint| codepoints.push(codepoint) }
 *   strio.eof? # => true
 *   codepoints # => [104, 101, 108, 108, 111]
 *
 *   codepoints = []
 *   strio = StringIO.new('こんにちは')
 *   strio.each_codepoint {|codepoint| codepoints.push(codepoint) }
 *   codepoints # => [12371, 12435, 12395, 12385, 12399]
 *
 * Position in the stream matters:
 *
 *   codepoints = []
 *   strio = StringIO.new('こんにちは')
 *   strio.getc # => "こ"
 *   strio.pos  # => 3
 *   strio.each_codepoint {|codepoint| codepoints.push(codepoint) }
 *   codepoints # => [12435, 12395, 12385, 12399]
 *
 * When at end-of-stream, the block is not called:
 *
 *   strio.eof? # => true
 *   strio.each_codepoint {|codepoint| fail 'Boo!' }
 *   strio.eof? # => true
 *
 * With no block given, returns a new {Enumerator}[rdoc-ref:Enumerator].
 *
 * Related: StringIO#each_byte, StringIO#each_char, StringIO#each_line.
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
bm_init_skip(rb_len_t *skip, const char *pat, rb_len_t m)
{
    int c;

    for (c = 0; c < (1 << CHAR_BIT); c++) {
	skip[c] = m;
    }
    while (--m) {
	skip[(unsigned char)*pat++] = m;
    }
}

static rb_len_t
bm_search(const char *little, rb_len_t llen, const char *big, rb_len_t blen, const rb_len_t *skip)
{
    rb_len_t i, j, k;

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
    rb_len_t limit;
    unsigned int chomp: 1;
};

static struct getline_arg *
prepare_getline_args(struct StringIO *ptr, struct getline_arg *arg, int argc, VALUE *argv)
{
    VALUE rs, lim, opts;
    rb_len_t limit = -1;
    int respect_chomp;

    argc = rb_scan_args(argc, argv, "02:", &rs, &lim, &opts);
    respect_chomp = argc == 0 || !NIL_P(rs);
    switch (argc) {
      case 0:
	rs = rb_rs;
	break;

      case 1:
	if (!NIL_P(rs) && !RB_TYPE_P(rs, T_STRING)) {
	    VALUE tmp = rb_check_string_type(rs);
	    if (NIL_P(tmp)) {
		limit = NUM2LEN(rs);
		rs = rb_rs;
	    }
	    else {
		rs = tmp;
	    }
	}
	break;

      case 2:
	if (!NIL_P(rs)) StringValue(rs);
	if (!NIL_P(lim)) limit = NUM2LEN(lim);
	break;
    }
    if (!NIL_P(ptr->string) && !NIL_P(rs)) {
	rb_encoding *enc_rs, *enc_io;
	enc_rs = rb_enc_get(rs);
	enc_io = get_enc(ptr);
	if (enc_rs != enc_io &&
	    (rb_enc_str_coderange(rs) != ENC_CODERANGE_7BIT ||
	     (RSTRING_LEN(rs) > 0 && !rb_enc_asciicompat(enc_io)))) {
	    if (rs == rb_rs) {
		rs = rb_enc_str_new(0, 0, enc_io);
		rb_str_buf_cat_ascii(rs, "\n");
	    }
	    else {
		rb_raise(rb_eArgError, "encoding mismatch: %s IO with %s RS",
			 rb_enc_name(enc_io),
			 rb_enc_name(enc_rs));
	    }
	}
    }
    arg->rs = rs;
    arg->limit = limit;
    arg->chomp = 0;
    if (!NIL_P(opts)) {
	static ID keywords[1];
	VALUE vchomp;
	if (!keywords[0]) {
	    keywords[0] = rb_intern_const("chomp");
	}
	rb_get_kwargs(opts, keywords, 0, 1, &vchomp);
	if (respect_chomp) {
	    arg->chomp = (vchomp != Qundef) && RTEST(vchomp);
	}
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
    rb_len_t n, limit = arg->limit;
    VALUE str = arg->rs;
    rb_len_t w = 0;
    rb_encoding *enc = get_enc(ptr);

    if (NIL_P(ptr->string) || ptr->pos >= (n = RSTRING_LEN(ptr->string))) {
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
	const char *paragraph_end = NULL;
	p = s;
	while (p[(p + 1 < e) && (*p == '\r') && 0] == '\n') {
	    p += *p == '\r';
	    if (++p == e) {
		return Qnil;
	    }
	}
	s = p;
	while ((p = memchr(p, '\n', e - p)) && (p != e)) {
	    p++;
	    if (!((p < e && *p == '\n') ||
		  (p + 1 < e && *p == '\r' && *(p+1) == '\n'))) {
		continue;
	    }
	    paragraph_end = p - ((*(p-2) == '\r') ? 2 : 1);
	    while ((p < e && *p == '\n') ||
		   (p + 1 < e && *p == '\r' && *(p+1) == '\n')) {
		p += (*p == '\r') ? 2 : 1;
	    }
	    e = p;
	    break;
	}
	if (arg->chomp && paragraph_end) {
	    w = e - paragraph_end;
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
			e = p + n;
			w = (arg->chomp ? n : 0);
			break;
		    }
		}
	    }
	    else {
		rb_len_t skip[1 << CHAR_BIT], pos;
		p = RSTRING_PTR(str);
		bm_init_skip(skip, p, n);
		if ((pos = bm_search(p, n, s, e - s, skip)) >= 0) {
		    e = s + pos + n;
		    if (arg->chomp) w = n;
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
 *   gets(sep = $/, chomp: false) -> string or nil
 *   gets(limit, chomp: false) -> string or nil
 *   gets(sep, limit, chomp: false) -> string or nil
 *
 * Reads and returns a line from the stream;
 * returns +nil+ if at end-of-stream.
 *
 * Side effects:
 *
 * - Increments stream position by the number of bytes read.
 * - Assigns the return value to global variable <tt>$_</tt>.
 *
 * With no arguments given, reads a line using the default record separator
 * (global variable <tt>$/</tt>,* whose initial value is <tt>"\n"</tt>):
 *
 *   strio = StringIO.new(TEXT)
 *   strio.pos  # => 0
 *   strio.gets # => "First line\n"
 *   strio.pos  # => 11
 *   $_         # => "First line\n"
 *   strio.gets # => "Second line\n"
 *   strio.read # => "\nFourth line\nFifth line\n"
 *   strio.eof? # => true
 *   strio.gets # => nil
 *
 *   strio = StringIO.new('こんにちは')  # Five 3-byte characters.
 *   strio.pos  # => 0
 *   strio.gets # => "こんにちは"
 *   strio.pos  # => 15
 *
 * <b>Argument +sep+</b>
 *
 * With only string argument +sep+ given, reads a line using that string as the record separator:
 *
 *   strio = StringIO.new(TEXT)
 *   strio.gets(' ') # => "First "
 *   strio.gets(' ') # => "line\nSecond "
 *   strio.gets(' ') # => "line\n\nFourth "
 *
 * <b>Argument +limit+</b>
 *
 * With only integer argument +limit+ given,
 * reads a line using the default record separator;
 * limits the size (in characters) of each line to the given limit:
 *
 *   strio = StringIO.new(TEXT)
 *   strio.gets(10) # => "First line"
 *   strio.gets(10) # => "\n"
 *   strio.gets(10) # => "Second lin"
 *   strio.gets(10) # => "e\n"
 *
 * <b>Arguments +sep+ and +limit+</b>
 *
 * With arguments +sep+ and +limit+ both given, honors both:
 *
 *   strio = StringIO.new(TEXT)
 *   strio.gets(' ', 10) # => "First "
 *   strio.gets(' ', 10) # => "line\nSecon"
 *   strio.gets(' ', 10) # => "d "
 *
 * <b>Position</b>
 *
 * As stated above, method +gets+ reads and returns the next line in the stream.
 *
 * In the examples above each +strio+ object starts with its position at beginning-of-stream;
 * but in other cases the position may be anywhere:
 *
 *   strio = StringIO.new(TEXT)
 *   strio.pos = 12
 *   strio.gets # => "econd line\n"
 *
 * The position need not be at a character boundary:
 *
 *   strio = StringIO.new('こんにちは')  # Five 3-byte characters.
 *   strio.pos = 3                     # At beginning of second character.
 *   strio.gets  # => "んにちは"
 *   strio.pos = 4                     # Within second character.
 *   strio.gets  # => "\x82\x93にちは"
 *
 * <b>Special Record Separators</b>
 *
 * Like some methods in class IO, method +gets+ honors two special record separators;
 * see {Special Line Separators}[rdoc-ref:IO@Special+Line+Separator+Values]:
 *
 *   strio = StringIO.new(TEXT)
 *   strio.gets('')  # Read "paragraph" (up to empty line).
 *   # => "First line\nSecond line\n\n"
 *
 *   strio = StringIO.new(TEXT)
 *   strio.gets(nil) # "Slurp": read all.
 *   # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *
 * <b>Keyword Argument +chomp+</b>
 *
 * With keyword argument +chomp+ given as +true+ (the default is +false+),
 * removes the trailing newline (if any) from the returned line:
 *
 *   strio = StringIO.new(TEXT)
 *   strio.gets              # => "First line\n"
 *   strio.gets(chomp: true) # => "Second line"
 *
 * Related: #each_line, #readlines,
 * {Kernel#puts}[rdoc-ref:Kernel#puts].
 *
 */
static VALUE
strio_gets(int argc, VALUE *argv, VALUE self)
{
    struct StringIO *ptr = readable(self);
    struct getline_arg arg;
    VALUE str;

    if (prepare_getline_args(ptr, &arg, argc, argv)->limit == 0) {
	if (NIL_P(ptr->string)) return Qnil;
	return rb_enc_str_new(0, 0, get_enc(ptr));
    }

    str = strio_getline(&arg, ptr);
    rb_lastline_set(str);
    return str;
}

/*
 * call-seq:
 *   readline(sep = $/, chomp: false) -> string
 *   readline(limit, chomp: false) -> string
 *   readline(sep, limit, chomp: false) -> string
 *
 * Reads a line as with IO#gets, but raises EOFError if already at end-of-file;
 * see {Line IO}[rdoc-ref:IO@Line+IO].
 */
static VALUE
strio_readline(int argc, VALUE *argv, VALUE self)
{
    VALUE line = rb_funcallv_kw(self, rb_intern("gets"), argc, argv, RB_PASS_CALLED_KEYWORDS);
    if (NIL_P(line)) rb_eof_error();
    return line;
}

/*
 * :markup: markdown
 *
 * call-seq:
 *   each_line(sep = $/, chomp: false) {|line| ... }   -> self
 *   each_line(limit, chomp: false) {|line| ... }      -> self
 *   each_line(sep, limit, chomp: false) {|line| ... } -> self
 *
 * With a block given calls the block with each remaining line (see "Position" below) in the stream;
 * returns `self`.
 *
 * Leaves stream position at end-of-stream.
 *
 * **No Arguments**
 *
 * With no arguments given,
 * reads lines using the default record separator
 * (global variable `$/`, whose initial value is `"\n"`).
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line {|line| p line }
 * strio.eof? # => true
 * ```
 *
 * Output:
 *
 * ```
 * "First line\n"
 * "Second line\n"
 * "\n"
 * "Fourth line\n"
 * "Fifth line\n"
 * ```
 *
 * **Argument `sep`**
 *
 * With only string argument `sep` given,
 * reads lines using that string as the record separator:
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line(' ') {|line| p line }
 * ```
 *
 * Output:
 *
 * ```
 * "First "
 * "line\nSecond "
 * "line\n\nFourth "
 * "line\nFifth "
 * "line\n"
 * ```
 *
 * **Argument `limit`**
 *
 * With only integer argument `limit` given,
 * reads lines using the default record separator;
 * also limits the size (in characters) of each line to the given limit:
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line(10) {|line| p line }
 * ```
 *
 * Output:
 *
 * ```
 * "First line"
 * "\n"
 * "Second lin"
 * "e\n"
 * "\n"
 * "Fourth lin"
 * "e\n"
 * "Fifth line"
 * "\n"
 * ```
 *
 * **Arguments `sep` and `limit`**
 *
 * With arguments `sep` and `limit` both given,
 * honors both:
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line(' ', 10) {|line| p line }
 * ```
 *
 * Output:
 *
 * ```
 * "First "
 * "line\nSecon"
 * "d "
 * "line\n\nFour"
 * "th "
 * "line\nFifth"
 * " "
 * "line\n"
 * ```
 *
 * **Position**
 *
 * As stated above, method `each` _remaining_ line in the stream.
 *
 * In the examples above each `strio` object starts with its position at beginning-of-stream;
 * but in other cases the position may be anywhere (see StringIO#pos):
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.pos = 30 # Set stream position to character 30.
 * strio.each_line {|line| p line }
 * ```
 *
 * Output:
 *
 * ```
 * " line\n"
 * "Fifth line\n"
 * ```
 *
 * In all the examples above, the stream position is at the beginning of a character;
 * in other cases, that need not be so:
 *
 * ```ruby
 * s = 'こんにちは'  # Five 3-byte characters.
 * strio = StringIO.new(s)
 * strio.pos = 3   # At beginning of second character.
 * strio.each_line {|line| p line }
 * strio.pos = 4   # At second byte of second character.
 * strio.each_line {|line| p line }
 * strio.pos = 5   # At third byte of second character.
 * strio.each_line {|line| p line }
 * ```
 *
 * Output:
 *
 * ```
 * "んにちは"
 * "\x82\x93にちは"
 * "\x93にちは"
 * ```
 *
 * **Special Record Separators**
 *
 * Like some methods in class `IO`, StringIO.each honors two special record separators;
 * see {Special Line Separators}[https://docs.ruby-lang.org/en/master/IO.html#class-IO-label-Special+Line+Separator+Values].
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line('') {|line| p line } # Read as paragraphs (separated by blank lines).
 * ```
 *
 * Output:
 *
 * ```
 * "First line\nSecond line\n\n"
 * "Fourth line\nFifth line\n"
 * ```
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line(nil) {|line| p line } # "Slurp"; read it all.
 * ```
 *
 * Output:
 *
 * ```
 * "First line\nSecond line\n\nFourth line\nFifth line\n"
 * ```
 *
 * **Keyword Argument `chomp`**
 *
 * With keyword argument `chomp` given as `true` (the default is `false`),
 * removes trailing newline (if any) from each line:
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.each_line(chomp: true) {|line| p line }
 * ```
 *
 * Output:
 *
 * ```
 * "First line"
 * "Second line"
 * ""
 * "Fourth line"
 * "Fifth line"
 * ```
 *
 * With no block given, returns a new {Enumerator}[https://docs.ruby-lang.org/en/master/Enumerator.html].
 *
 *
 * Related: StringIO.each_byte, StringIO.each_char, StringIO.each_codepoint.
 *
 */
static VALUE
strio_each(int argc, VALUE *argv, VALUE self)
{
    VALUE line;
    struct StringIO *ptr = readable(self);
    struct getline_arg arg;

    RETURN_ENUMERATOR(self, argc, argv);

    if (prepare_getline_args(ptr, &arg, argc, argv)->limit == 0) {
	rb_raise(rb_eArgError, "invalid limit: 0 for each_line");
    }

    while (!NIL_P(line = strio_getline(&arg, ptr))) {
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
    struct StringIO *ptr = readable(self);
    struct getline_arg arg;

    if (prepare_getline_args(ptr, &arg, argc, argv)->limit == 0) {
	rb_raise(rb_eArgError, "invalid limit: 0 for readlines");
    }

    ary = rb_ary_new();
    while (!NIL_P(line = strio_getline(&arg, ptr))) {
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
    rb_len_t len = 0;
    while (argc-- > 0) {
	/* StringIO can't exceed rb_len_t limit */
	len += strio_write(self, *argv++);
    }
    return LEN2NUM(len);
}

static rb_len_t
strio_write(VALUE self, VALUE str)
{
    struct StringIO *ptr = writable(self);
    rb_len_t len, olen;
    rb_encoding *enc, *enc2;
    rb_encoding *const ascii8bit = rb_ascii8bit_encoding();
    rb_encoding *usascii = 0;

    if (!RB_TYPE_P(str, T_STRING))
	str = rb_obj_as_string(str);
    enc = get_enc(ptr);
    if (!enc) return 0;
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
	rb_str_modify(ptr->string);
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
 *   putc(object) -> object
 *
 * Replaces one or more bytes at position +pos+
 * with bytes of the given argument;
 * advances the position by the count of bytes written;
 * returns the argument.
 *
 * \StringIO object for 1-byte characters.
 *
 *   strio = StringIO.new('foo')
 *   strio.pos # => 0
 *
 * With 1-byte argument, replaces one byte:
 *
 *   strio.putc('b')
 *   strio.string    # => "boo"
 *   strio.pos       # => 1
 *   strio.putc('a') # => "a"
 *   strio.string    # => "bao"
 *   strio.pos       # => 2
 *   strio.putc('r') # => "r"
 *   strio.string    # => "bar"
 *   strio.pos       # => 3
 *   strio.putc('n') # => "n"
 *   strio.string    # => "barn"
 *   strio.pos       # => 4
 *
 * Fills with null characters if necessary:
 *
 *   strio.pos = 6
 *   strio.putc('x') # => "x"
 *   strio.string    # => "barn\u0000\u0000x"
 *   strio.pos       # => 7
 *
 * With integer argument, replaces one byte with the low-order byte of the integer:
 *
 *   strio = StringIO.new('foo')
 *   strio.putc(70)
 *   strio.string # => "Foo"
 *   strio.putc(79)
 *   strio.string # => "FOo"
 *   strio.putc(79 + 1024)
 *   strio.string # => "FOO"
 *
 * \StringIO object for Multi-byte characters:
 *
 *   greek = 'αβγδε' # Five 2-byte characters.
 *   strio = StringIO.new(greek)
 *   strio.string# => "αβγδε"
 *   strio.string.b        # => "\xCE\xB1\xCE\xB2\xCE\xB3\xCE\xB4\xCE\xB5"
 *   strio.string.bytesize # => 10
 *   strio.string.chars    # => ["α", "β", "γ", "δ", "ε"]
 *   strio.string.size     # => 5
 *
 * With 1-byte argument, replaces one byte of the string:
 *
 *   strio.putc(' ')       # 1-byte ascii space.
 *   strio.pos             # => 1
 *   strio.string          # => " \xB1βγδε"
 *   strio.string.b        # => " \xB1\xCE\xB2\xCE\xB3\xCE\xB4\xCE\xB5"
 *   strio.string.bytesize # => 10
 *   strio.string.chars    # => [" ", "\xB1", "β", "γ", "δ", "ε"]
 *   strio.string.size     # => 6
 *
 *   strio.putc(' ')
 *   strio.pos             # => 2
 *   strio.string          # => "  βγδε"
 *   strio.string.b        # => "  \xCE\xB2\xCE\xB3\xCE\xB4\xCE\xB5"
 *   strio.string.bytesize # => 10
 *   strio.string.chars    # => [" ", " ", "β", "γ", "δ", "ε"]
 *   strio.string.size     # => 6
 *
 * With 2-byte argument, replaces two bytes of the string:
 *
 *   strio.rewind
 *   strio.putc('α')
 *   strio.pos             # => 2
 *   strio.string          # => "αβγδε"
 *   strio.string.b        # => "\xCE\xB1\xCE\xB2\xCE\xB3\xCE\xB4\xCE\xB5"
 *   strio.string.bytesize # => 10
 *   strio.string.chars    # => ["α", "β", "γ", "δ", "ε"]
 *   strio.string.size     # => 5
 *
 * Related: #getc, #ungetc.
 *
 */
static VALUE
strio_putc(VALUE self, VALUE ch)
{
    struct StringIO *ptr = writable(self);
    VALUE str;

    check_modifiable(ptr);
    if (RB_TYPE_P(ch, T_STRING)) {
	if (NIL_P(ptr->string)) return ch;
	str = rb_str_substr(ch, 0, 1);
    }
    else {
	char c = NUM2CHR(ch);
	if (NIL_P(ptr->string)) return ch;
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
 *   read(maxlen = nil, out_string = nil) → new_string, out_string, or nil
 *
 * Reads and returns a string containing bytes read from the stream,
 * beginning at the current position;
 * advances the position by the count of bytes read.
 *
 * With no arguments given,
 * reads all remaining bytes in the stream;
 * returns a new string containing bytes read:
 *
 *   strio = StringIO.new('Hello') # Five 1-byte characters.
 *   strio.read                    # => "Hello"
 *   strio.pos                     # => 5
 *   strio.read                    # => ""
 *   StringIO.new('').read         # => ""
 *
 * With non-negative argument +maxlen+ given,
 * reads +maxlen+ bytes as available;
 * returns a new string containing the bytes read, or +nil+ if none:
 *
 *   strio.rewind
 *   strio.read(3) # => "Hel"
 *   strio.read(3) # => "lo"
 *   strio.read(3) # => nil
 *
 *   russian = 'Привет' # Six 2-byte characters.
 *   russian.b
 *   # => "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82"
 *   strio = StringIO.new(russian)
 *   strio.read(6) # => "\xD0\x9F\xD1\x80\xD0\xB8"
 *   strio.read(6) # => "\xD0\xB2\xD0\xB5\xD1\x82"
 *   strio.read(6) # => nil
 *
 *   japanese = 'こんにちは'
 *   japanese.b
 *   # => "\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"
 *   strio = StringIO.new(japanese)
 *   strio.read(9) # => "\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB"
 *   strio.read(9) # => "\xE3\x81\xA1\xE3\x81\xAF"
 *   strio.read(9) # => nil
 *
 * With argument +max_len+ as +nil+ and string argument +out_string+ given,
 * reads the remaining bytes in the stream;
 * clears +out_string+ and writes the bytes into it;
 * returns +out_string+:
 *
 *   out_string = 'Will be overwritten'
 *   strio = StringIO.new('Hello')
 *   strio.read(nil, out_string) # => "Hello"
 *   strio.read(nil, out_string) # => ""
 *
 * With non-negative argument +maxlen+ and string argument +out_string+ given,
 * reads the +maxlen bytes from the stream, as availble;
 * clears +out_string+ and writes the bytes into it;
 * returns +out_string+ if any bytes were read, or +nil+ if none:
 *
 *   out_string = 'Will be overwritten'
 *   strio = StringIO.new('Hello')
 *   strio.read(3, out_string) # => "Hel"
 *   strio.read(3, out_string) # => "lo"
 *   strio.read(3, out_string) # => nil
 *
 *   out_string = 'Will be overwritten'
 *   strio = StringIO.new(russian)
 *   strio.read(6, out_string) # => "При"
 *   strio.read(6, out_string) # => "вет"
 *   strio.read(6, out_string) # => nil
 *   strio.rewind
 *   russian.b
 *   # => "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82"
 *   strio.read(3)             # => "\xD0\x9F\xD1"
 *   strio.read(3)             # => "\x80\xD0\xB8"
 *
 *   out_string = 'Will be overwritten'
 *   strio = StringIO.new(japanese)
 *   strio.read(9, out_string) # => "こんに"
 *   strio.read(9, out_string) # => "ちは"
 *   strio.read(9, out_string) # => nil
 *   strio.rewind
 *   japanese.b
 *   # => "\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"
 *   strio.read(4)             # => "\xE3\x81\x93\xE3"
 *   strio.read(4)             # => "\x82\x93\xE3\x81"
 *
 * Related: #gets, #readlines.
 *
 */
static VALUE
strio_read(int argc, VALUE *argv, VALUE self)
{
    struct StringIO *ptr = readable(self);
    VALUE str = Qnil;
    rb_len_t len;
    int binary = 0;

    switch (argc) {
      case 2:
	str = strio_readbuf(ptr, argv[1]);
	/* fall through */
      case 1:
	if (!NIL_P(argv[0])) {
	    len = NUM2LEN(argv[0]);
	    if (len < 0) {
		rb_raise(rb_eArgError, "negative length %"PRIdLEN" given", len);
	    }
	    if (eos_p(ptr)) {
		if (!NIL_P(str)) rb_str_resize(str, 0);
		return len > 0 ? Qnil : rb_str_new(0, 0);
	    }
	    binary = 1;
	    break;
	}
	/* fall through */
      case 0:
	if (NIL_P(ptr->string)) return Qnil;
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
	rb_len_t rest = RSTRING_LEN(ptr->string) - ptr->pos;
	if (len > rest) len = rest;
	rb_str_resize(str, len);
	MEMCPY(RSTRING_PTR(str), RSTRING_PTR(ptr->string) + ptr->pos, char, len);
	if (!binary) {
	    rb_enc_copy(str, ptr->string);
	}
    }
    ptr->pos += RSTRING_LEN(str);
    return str;
}

/*
 *  call-seq:
 *    pread(maxlen, offset, out_string = nil) -> new_string or out_string
 *
 *  **Note**: \Method +pread+ is different from other reading methods
 *  in that it does not modify +self+ in any way;
 *  thus, multiple threads may read safely from the same stream.
 *
 *  Reads up to +maxlen+ bytes from the stream,
 *  beginning at 0-based byte offset +offset+;
 *  returns a string containing the read bytes.
 *
 *  The returned string:
 *
 *  - Contains +maxlen+ bytes from the stream, if available;
 *    otherwise contains all available bytes.
 *  - Has encoding +Encoding::ASCII_8BIT+.
 *
 *  With only arguments +maxlen+ and +offset+ given,
 *  returns a new string:
 *
 *    english = 'Hello'  # Five 1-byte characters.
 *    strio = StringIO.new(english)
 *    strio.pread(3, 0)  # => "Hel"
 *    strio.pread(3, 2)  # => "llo"
 *    strio.pread(0, 0)  # => ""
 *    strio.pread(50, 0) # => "Hello"
 *    strio.pread(50, 2) # => "llo"
 *    strio.pread(50, 4) # => "o"
 *    strio.pread(0, 0).encoding
 *    # => #<Encoding:BINARY (ASCII-8BIT)>
 *
 *    russian = 'Привет' # Six 2-byte characters.
 *    strio = StringIO.new(russian)
 *    strio.pread(50, 0) # All 12 bytes.
 *    # => "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82"
 *    strio.pread(3, 0)  # => "\xD0\x9F\xD1"
 *    strio.pread(3, 3)  # => "\x80\xD0\xB8"
 *    strio.pread(0, 0).encoding
 *    # => #<Encoding:BINARY (ASCII-8BIT)>
 *
 *    japanese = 'こんにちは' # Five 3-byte characters.
 *    strio = StringIO.new(japanese)
 *    strio.pread(50, 0)    # All 15 bytes.
 *    # => "\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"
 *    strio.pread(6, 0)     # => "\xE3\x81\x93\xE3\x82\x93"
 *    strio.pread(1, 2)     # => "\x93"
 *    strio.pread(0, 0).encoding
 *    # => #<Encoding:BINARY (ASCII-8BIT)>
 *
 *  Raises an exception if +offset+ is out-of-range:
 *
 *    strio = StringIO.new(english)
 *    strio.pread(5, 50) # Raises EOFError: end of file reached
 *
 *  With string argument +out_string+ given:
 *
 *  - Reads as above.
 *  - Overwrites the content of +out_string+ with the read bytes.
 *
 *  Examples:
 *
 *    out_string = 'Will be overwritten'
 *    out_string.encoding                # => #<Encoding:UTF-8>
 *    result = StringIO.new(english).pread(50, 0, out_string)
 *    result.__id__ == out_string.__id__ # => true
 *    out_string                         # => "Hello"
 *    out_string.encoding                # => #<Encoding:BINARY (ASCII-8BIT)>
 *
 */
static VALUE
strio_pread(int argc, VALUE *argv, VALUE self)
{
    VALUE rb_len, rb_offset, rb_buf;
    struct StringIO *ptr = readable(self);

    rb_scan_args(argc, argv, "21", &rb_len, &rb_offset, &rb_buf);
    rb_len_t len = NUM2LEN(rb_len);
    rb_len_t offset = NUM2LEN(rb_offset);

    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big): %" PRIsVALUE, rb_len);
    }

    if (offset < 0) {
	rb_syserr_fail_str(EINVAL, rb_sprintf("pread: Invalid offset argument: %" PRIsVALUE, rb_offset));
    }

    rb_buf = strio_readbuf(ptr, rb_buf);

    if (len == 0) {
	if (NIL_P(rb_buf)) {
	    return rb_str_new("", 0);
	}
	return rb_buf;
    }

    if (outside_p(ptr, offset)) {
	rb_eof_error();
    }

    if (NIL_P(rb_buf)) {
	return strio_substr(ptr, offset, len, rb_ascii8bit_encoding());
    }

    rb_len_t rest = RSTRING_LEN(ptr->string) - offset;
    if (len > rest) len = rest;
    rb_str_resize(rb_buf, len);
    rb_enc_associate(rb_buf, rb_ascii8bit_encoding());
    MEMCPY(RSTRING_PTR(rb_buf), RSTRING_PTR(ptr->string) + offset, char, len);
    return rb_buf;
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

/*
 * See IO#write
 */
#define strio_syswrite rb_io_write

/*
 * See IO#write_nonblock
 */
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
 *   size -> integer
 *
 * Returns the number of bytes in the string in +self+:
 *
 *   StringIO.new('hello').size     # => 5  # Five 1-byte characters.
 *   StringIO.new('こんにちは').size # => 15 # Five 3-byte characters.
 *
 */
static VALUE
strio_size(VALUE self)
{
    VALUE string = StringIOForRead(self)->string;
    if (NIL_P(string)) {
	return INT2FIX(0);
    }
    return ULEN2NUM((rb_ulen_t)RSTRING_LEN(string));
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
    rb_len_t l = NUM2LEN(len);
    rb_len_t plen;
    if (l < 0) {
	error_inval("negative length");
    }
    if (NIL_P(string)) return 0;
    plen = RSTRING_LEN(string);
    rb_str_resize(string, l);
    if (plen < l) {
	MEMZERO(RSTRING_PTR(string) + plen, char, l - plen);
    }
    return INT2FIX(0);
}

/*
 * call-seq:
 *   external_encoding -> encoding or nil
 *
 * Returns an Encoding object that represents the encoding of the string;
 * see {Encodings}[rdoc-ref:StringIO@Encodings]:
 *
 *   strio = StringIO.new('foo')
 *   strio.external_encoding # => #<Encoding:UTF-8>
 *
 * Returns +nil+ if +self+ has no string and is in write mode:
 *
 *   strio = StringIO.new(nil, 'w+')
 *   strio.external_encoding # => nil
 *
 */

static VALUE
strio_external_encoding(VALUE self)
{
    struct StringIO *ptr = StringIOForRead(self);
    return rb_enc_from_encoding(get_enc(ptr));
}

/*
 *  call-seq:
 *     internal_encoding -> nil
 *
 *  Returns +nil+; for compatibility with IO.
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
	enc = rb_find_encoding(ext_enc);
	if (!enc) {
	    rb_io_enc_t convconfig;
	    int oflags;
	    rb_io_mode_t fmode;
	    VALUE vmode = rb_str_append(rb_str_new_cstr("r:"), ext_enc);
	    rb_io_extract_modeenc(&vmode, 0, Qnil, &oflags, &fmode, &convconfig);
	    enc = convconfig.enc2;
	}
    }
    ptr->enc = enc;
    if (!NIL_P(ptr->string) && WRITABLE(self) && !str_chilled_p(ptr->string)) {
	rb_enc_associate(ptr->string, enc);
    }

    return self;
}

/*
 *  call-seq:
 *     strio.set_encoding_by_bom  => strio or nil
 *
 *  Sets the encoding according to the BOM (Byte Order Mark) in the
 *  string.
 *
 *  Returns +self+ if the BOM is found, otherwise +nil.
 */
static VALUE
strio_set_encoding_by_bom(VALUE self)
{
    struct StringIO *ptr = StringIO(self);

    if (!set_encoding_by_bom(ptr)) return Qnil;
    return rb_enc_from_encoding(ptr->enc);
}

/*
 * :markup: markdown
 *
 * \Class \StringIO supports accessing a string as a stream,
 * similar in some ways to [class IO][io class].
 *
 * You can create a \StringIO instance using:
 *
 * - StringIO.new: returns a new \StringIO object containing the given string.
 * - StringIO.open: passes a new \StringIO object to the given block.
 *
 * Like an \IO stream, a \StringIO stream has certain properties:
 *
 * - **Read/write mode**: whether the stream may be read, written, appended to, etc.;
 *   see [Read/Write Mode][read/write mode].
 * - **Data mode**: text-only or binary;
 *   see [Data Mode][data mode].
 * - **Encodings**: internal and external encodings;
 *   see [Encodings][encodings].
 * - **Position**: where in the stream the next read or write is to occur;
 *   see [Position][position].
 * - **Line number**: a special, line-oriented, "position" (different from the position mentioned above);
 *   see [Line Number][line number].
 * - **Open/closed**: whether the stream is open or closed, for reading or writing.
 *   see [Open/Closed Streams][open/closed streams].
 * - **BOM**: byte mark order;
 *   see [Byte Order Mark][bom (byte order mark)].
 *
 * ## About the Examples
 *
 * Examples on this page assume that \StringIO has been required:
 *
 * ```ruby
 * require 'stringio'
 * ```
 *
 * And that this constant has been defined:
 *
 * ```ruby
 * TEXT = <<EOT
 * First line
 * Second line
 *
 * Fourth line
 * Fifth line
 * EOT
 * ```
 *
 * ## Stream Properties
 *
 * ### Read/Write Mode
 *
 * #### Summary
 *
 * |            Mode            | Initial Clear? |   Read   |  Write   |
 * |:--------------------------:|:--------------:|:--------:|:--------:|
 * |  <tt>'r'</tt>: read-only   |       No       | Anywhere |  Error   |
 * |  <tt>'w'</tt>: write-only  |      Yes       |  Error   | Anywhere |
 * | <tt>'a'</tt>: append-only  |       No       |  Error   | End only |
 * | <tt>'r+'</tt>: read/write  |       No       | Anywhere | Anywhere |
 * | <tt>'w+'</tt>: read-write  |      Yes       | Anywhere | Anywhere |
 * | <tt>'a+'</tt>: read/append |       No       | Anywhere | End only |
 *
 * Each section below describes a read/write mode.
 *
 * Any of the modes may be given as a string or as file constants;
 * example:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'a')
 * strio = StringIO.new('foo', File::WRONLY | File::APPEND)
 * ```
 *
 * #### `'r'`: Read-Only
 *
 * Mode specified as one of:
 *
 * - String: `'r'`.
 * - Constant: `File::RDONLY`.
 *
 * Initial state:
 *
 * ```ruby
 * strio = StringIO.new('foobarbaz', 'r')
 * strio.pos    # => 0            # Beginning-of-stream.
 * strio.string # => "foobarbaz"  # Not cleared.
 * ```
 *
 * May be read anywhere:
 *
 * ```ruby
 * strio.gets(3) # => "foo"
 * strio.gets(3) # => "bar"
 * strio.pos = 9
 * strio.gets(3) # => nil
 * ```
 *
 * May not be written:
 *
 * ```ruby
 * strio.write('foo')  # Raises IOError: not opened for writing
 * ```
 *
 * #### `'w'`: Write-Only
 *
 * Mode specified as one of:
 *
 * - String: `'w'`.
 * - Constant: `File::WRONLY`.
 *
 * Initial state:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'w')
 * strio.pos    # => 0   # Beginning of stream.
 * strio.string # => ""  # Initially cleared.
 * ```
 *
 * May be written anywhere (even past end-of-stream):
 *
 * ```ruby
 * strio.write('foobar')
 * strio.string # => "foobar"
 * strio.rewind
 * strio.write('FOO')
 * strio.string # => "FOObar"
 * strio.pos = 3
 * strio.write('BAR')
 * strio.string # => "FOOBAR"
 * strio.pos = 9
 * strio.write('baz')
 * strio.string # => "FOOBAR\u0000\u0000\u0000baz"  # Null-padded.
 * ```
 *
 * May not be read:
 *
 * ```ruby
 * strio.read  # Raises IOError: not opened for reading
 * ```
 *
 * #### `'a'`: Append-Only
 *
 * Mode specified as one of:
 *
 * - String: `'a'`.
 * - Constant: `File::WRONLY | File::APPEND`.
 *
 * Initial state:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'a')
 * strio.pos    # => 0      # Beginning-of-stream.
 * strio.string # => "foo"  # Not cleared.
 * ```
 *
 * May be written only at the end; position does not affect writing:
 *
 * ```ruby
 * strio.write('bar')
 * strio.string # => "foobar"
 * strio.write('baz')
 * strio.string # => "foobarbaz"
 * strio.pos = 400
 * strio.write('bat')
 * strio.string # => "foobarbazbat"
 * ```
 *
 * May not be read:
 *
 * ```ruby
 * strio.gets  # Raises IOError: not opened for reading
 * ```
 *
 * #### `'r+'`: Read/Write
 *
 * Mode specified as one of:
 *
 * - String: `'r+'`.
 * - Constant: `File::RDWR`.
 *
 * Initial state:
 *
 * ```ruby
 * strio = StringIO.new('foobar', 'r+')
 * strio.pos    # => 0         # Beginning-of-stream.
 * strio.string # => "foobar"  # Not cleared.
 * ```
 *
 * May be written anywhere (even past end-of-stream):
 *
 * ```ruby
 * strio.write('FOO')
 * strio.string # => "FOObar"
 * strio.write('BAR')
 * strio.string # => "FOOBAR"
 * strio.write('BAZ')
 * strio.string # => "FOOBARBAZ"
 * strio.pos = 12
 * strio.write('BAT')
 * strio.string # => "FOOBARBAZ\u0000\u0000\u0000BAT"  # Null padded.
 * ```
 *
 * May be read anywhere:
 *
 * ```ruby
 * strio.pos = 0
 * strio.gets(3) # => "FOO"
 * strio.pos = 6
 * strio.gets(3) # => "BAZ"
 * strio.pos = 400
 * strio.gets(3) # => nil
 * ```
 *
 * #### `'w+'`: Read/Write (Initially Clear)
 *
 * Mode specified as one of:
 *
 * - String: `'w+'`.
 * - Constant: `File::RDWR | File::TRUNC`.
 *
 * Initial state:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'w+')
 * strio.pos    # => 0   # Beginning-of-stream.
 * strio.string # => ""  # Truncated.
 * ```
 *
 * May be written anywhere (even past end-of-stream):
 *
 * ```ruby
 * strio.write('foobar')
 * strio.string # => "foobar"
 * strio.rewind
 * strio.write('FOO')
 * strio.string # => "FOObar"
 * strio.write('BAR')
 * strio.string # => "FOOBAR"
 * strio.write('BAZ')
 * strio.string # => "FOOBARBAZ"
 * strio.pos = 12
 * strio.write('BAT')
 * strio.string # => "FOOBARBAZ\u0000\u0000\u0000BAT"  # Null-padded.
 * ```
 *
 * May be read anywhere:
 *
 * ```ruby
 * strio.rewind
 * strio.gets(3) # => "FOO"
 * strio.gets(3) # => "BAR"
 * strio.pos = 12
 * strio.gets(3) # => "BAT"
 * strio.pos = 400
 * strio.gets(3) # => nil
 * ```
 *
 * #### `'a+'`: Read/Append
 *
 * Mode specified as one of:
 *
 * - String: `'a+'`.
 * - Constant: `File::RDWR | File::APPEND`.
 *
 * Initial state:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'a+')
 * strio.pos    # => 0      # Beginning-of-stream.
 * strio.string # => "foo"  # Not cleared.
 * ```
 *
 * May be written only at the end; #rewind; position does not affect writing:
 *
 * ```ruby
 * strio.write('bar')
 * strio.string # => "foobar"
 * strio.write('baz')
 * strio.string # => "foobarbaz"
 * strio.pos = 400
 * strio.write('bat')
 * strio.string # => "foobarbazbat"
 * ```
 *
 * May be read anywhere:
 *
 * ```ruby
 * strio.rewind
 * strio.gets(3) # => "foo"
 * strio.gets(3) # => "bar"
 * strio.pos = 9
 * strio.gets(3) # => "bat"
 * strio.pos = 400
 * strio.gets(3) # => nil
 * ```
 *
 * ### Data Mode
 *
 * To specify whether the stream is to be treated as text or as binary data,
 * either of the following may be suffixed to any of the string read/write modes above:
 *
 * - `'t'`: Text;
 *   initializes the encoding as Encoding::UTF_8.
 * - `'b'`: Binary;
 *   initializes the encoding as Encoding::ASCII_8BIT.
 *
 * If neither is given, the stream defaults to text data.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'rt')
 * strio.external_encoding # => #<Encoding:UTF-8>
 * data = "\u9990\u9991\u9992\u9993\u9994"
 * strio = StringIO.new(data, 'rb')
 * strio.external_encoding # => #<Encoding:BINARY (ASCII-8BIT)>
 * ```
 *
 * When the data mode is specified, the read/write mode may not be omitted:
 *
 * ```ruby
 * StringIO.new(data, 'b')  # Raises ArgumentError: invalid access mode b
 * ```
 *
 * A text stream may be changed to binary by calling instance method #binmode;
 * a binary stream may not be changed to text.
 *
 * ### Encodings
 *
 * A stream has an encoding; see [Encodings][encodings document].
 *
 * The initial encoding for a new or re-opened stream depends on its [data mode][data mode]:
 *
 * - Text: `Encoding::UTF_8`.
 * - Binary: `Encoding::ASCII_8BIT`.
 *
 * These instance methods are relevant:
 *
 * - #external_encoding: returns the current encoding of the stream as an `Encoding` object.
 * - #internal_encoding: returns +nil+; a stream does not have an internal encoding.
 * - #set_encoding: sets the encoding for the stream.
 * - #set_encoding_by_bom: sets the encoding for the stream to the stream's BOM (byte order mark).
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new('foo', 'rt')  # Text mode.
 * strio.external_encoding # => #<Encoding:UTF-8>
 * data = "\u9990\u9991\u9992\u9993\u9994"
 * strio = StringIO.new(data, 'rb') # Binary mode.
 * strio.external_encoding # => #<Encoding:BINARY (ASCII-8BIT)>
 * strio = StringIO.new('foo')
 * strio.external_encoding # => #<Encoding:UTF-8>
 * strio.set_encoding('US-ASCII')
 * strio.external_encoding # => #<Encoding:US-ASCII>
 * ```
 *
 * ### Position
 *
 * A stream has a _position_, and integer offset (in bytes) into the stream.
 * The initial position of a stream is zero.
 *
 * #### Getting and Setting the Position
 *
 * Each of these methods initializes (to zero) the position of a new or re-opened stream:
 *
 * - ::new: returns a new stream.
 * - ::open: passes a new stream to the block.
 * - #reopen: re-initializes the stream.
 *
 * Each of these methods queries, gets, or sets the position, without otherwise changing the stream:
 *
 * - #eof?: returns whether the position is at end-of-stream.
 * - #pos: returns the position.
 * - #pos=: sets the position.
 * - #rewind: sets the position to zero.
 * - #seek: sets the position.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new('foobar')
 * strio.pos  # => 0
 * strio.pos = 3
 * strio.pos  # => 3
 * strio.eof? # => false
 * strio.rewind
 * strio.pos  # => 0
 * strio.seek(0, IO::SEEK_END)
 * strio.pos  # => 6
 * strio.eof? # => true
 * ```
 *
 * #### Position Before and After Reading
 *
 * Except for #pread, a stream reading method (see [Basic Reading][basic reading])
 * begins reading at the current position.
 *
 * Except for #pread, a read method advances the position past the read substring.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.string # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 * strio.pos    # => 0
 * strio.getc   # => "F"
 * strio.pos    # => 1
 * strio.gets   # => "irst line\n"
 * strio.pos    # => 11
 * strio.pos = 24
 * strio.gets   # => "Fourth line\n"
 * strio.pos    # => 36
 *
 * strio = StringIO.new('こんにちは')  # Five 3-byte characters.
 * strio.pos = 0  # At first byte of first character.
 * strio.read     # => "こんにちは"
 * strio.pos = 1  # At second byte of first character.
 * strio.read     # => "\x81\x93んにちは"
 * strio.pos = 2  # At third byte of first character.
 * strio.read     # => "\x93んにちは"
 * strio.pos = 3  # At first byte of second character.
 * strio.read     # => "んにちは"
 *
 * strio = StringIO.new(TEXT)
 * strio.pos = 15
 * a = []
 * strio.each_line {|line| a.push(line) }
 * a         # => ["nd line\n", "\n", "Fourth line\n", "Fifth line\n"]
 * strio.pos # => 47  ## End-of-stream.
 * ```
 *
 * #### Position Before and After Writing
 *
 * Each of these methods begins writing at the current position,
 * and advances the position to the end of the written substring:
 *
 * - #putc: writes the given character.
 * - #write: writes the given objects as strings.
 * - [Kernel#puts][kernel#puts]: writes given objects as strings, each followed by newline.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new('foo')
 * strio.pos    # => 0
 * strio.putc('b')
 * strio.string # => "boo"
 * strio.pos    # => 1
 * strio.write('r')
 * strio.string # => "bro"
 * strio.pos    # => 2
 * strio.puts('ew')
 * strio.string # => "brew\n"
 * strio.pos    # => 5
 * strio.pos = 8
 * strio.write('foo')
 * strio.string # => "brew\n\u0000\u0000\u0000foo"
 * strio.pos    # => 11
 * ```
 *
 * Each of these methods writes _before_ the current position, and decrements the position
 * so that the written data is next to be read:
 *
 * - #ungetbyte: unshifts the given byte.
 * - #ungetc: unshifts the given character.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new('foo')
 * strio.pos = 2
 * strio.ungetc('x')
 * strio.pos    # => 1
 * strio.string # => "fxo"
 * strio.ungetc('x')
 * strio.pos    # => 0
 * strio.string # => "xxo"
 * ```
 *
 * This method does not affect the position:
 *
 * - #truncate: truncates the stream's string to the given size.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new('foobar')
 * strio.pos    # => 0
 * strio.truncate(3)
 * strio.string # => "foo"
 * strio.pos    # => 0
 * strio.pos = 500
 * strio.truncate(0)
 * strio.string # => ""
 * strio.pos    # => 500
 * ```
 *
 * ### Line Number
 *
 * A stream has a line number, which initially is zero:
 *
 * - Method #lineno returns the line number.
 * - Method #lineno= sets the line number.
 *
 * The line number can be affected by reading (but never by writing);
 * in general, the line number is incremented each time the record separator (default: `"\n"`) is read.
 *
 * Examples:
 *
 * ```ruby
 * strio = StringIO.new(TEXT)
 * strio.string # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 * strio.lineno # => 0
 * strio.gets   # => "First line\n"
 * strio.lineno # => 1
 * strio.getc   # => "S"
 * strio.lineno # => 1
 * strio.gets   # => "econd line\n"
 * strio.lineno # => 2
 * strio.gets   # => "\n"
 * strio.lineno # => 3
 * strio.gets   # => "Fourth line\n"
 * strio.lineno # => 4
 * ```
 *
 * Setting the position does not affect the line number:
 *
 * ```ruby
 * strio.pos = 0
 * strio.lineno # => 4
 * strio.gets   # => "First line\n"
 * strio.pos    # => 11
 * strio.lineno # => 5
 * ```
 *
 * And setting the line number does not affect the position:
 *
 * ```ruby
 * strio.lineno = 10
 * strio.pos    # => 11
 * strio.gets   # => "Second line\n"
 * strio.lineno # => 11
 * strio.pos    # => 23
 * ```
 *
 * ### Open/Closed Streams
 *
 * A new stream is open for either reading or writing, and may be open for both;
 * see [Read/Write Mode][read/write mode].
 *
 * Each of these methods initializes the read/write mode for a new or re-opened stream:
 *
 * - ::new: returns a new stream.
 * - ::open: passes a new stream to the block.
 * - #reopen: re-initializes the stream.
 *
 * Other relevant methods:
 *
 * - #close: closes the stream for both reading and writing.
 * - #close_read: closes the stream for reading.
 * - #close_write: closes the stream for writing.
 * - #closed?: returns whether the stream is closed for both reading and writing.
 * - #closed_read?: returns whether the stream is closed for reading.
 * - #closed_write?: returns whether the stream is closed for writing.
 *
 * ### BOM (Byte Order Mark)
 *
 * The string provided for ::new, ::open, or #reopen
 * may contain an optional [BOM][bom] (byte order mark) at the beginning of the string;
 * the BOM can affect the stream's encoding.
 *
 * The BOM (if provided):
 *
 * - Is stored as part of the stream's string.
 * - Does _not_ immediately affect the encoding.
 * - Is _initially_ considered part of the stream.
 *
 * ```ruby
 * utf8_bom = "\xEF\xBB\xBF"
 * string = utf8_bom + 'foo'
 * string.bytes               # => [239, 187, 191, 102, 111, 111]
 * strio.string.bytes.take(3) # => [239, 187, 191]                  # The BOM.
 * strio = StringIO.new(string, 'rb')
 * strio.string.bytes         # => [239, 187, 191, 102, 111, 111]   # BOM is part of the stored string.
 * strio.external_encoding    # => #<Encoding:BINARY (ASCII-8BIT)>  # Default for a binary stream.
 * strio.gets                 # => "\xEF\xBB\xBFfoo"                # BOM is part of the stream.
 * ```
 *
 * You can call instance method #set_encoding_by_bom to "activate" the stored BOM;
 * after doing so the BOM:
 *
 * - Is _still_ stored as part of the stream's string.
 * - _Determines_ (and may have changed) the stream's encoding.
 * - Is _no longer_ considered part of the stream.
 *
 * ```ruby
 * strio.set_encoding_by_bom
 * strio.string.bytes      # => [239, 187, 191, 102, 111, 111]  # BOM is still part of the stored string.
 * strio.external_encoding # => #<Encoding:UTF-8>               # The new encoding.
 * strio.rewind            # => 0
 * strio.gets              # => "foo"                           # BOM is not part of the stream.
 * ```
 *
 * ## Basic Stream \IO
 *
 * ### Basic Reading
 *
 * You can read from the stream using these instance methods:
 *
 * - #getbyte: reads and returns the next byte.
 * - #getc: reads and returns the next character.
 * - #gets: reads and returns all or part of the next line.
 * - #read: reads and returns all or part of the remaining data in the stream.
 * - #readlines: reads the remaining data the stream and returns an array of its lines.
 * - [Kernel#readline][kernel#readline]: like #gets, but raises an exception if at end-of-stream.
 *
 * You can iterate over the stream using these instance methods:
 *
 * - #each_byte: reads each remaining byte, passing it to the block.
 * - #each_char: reads each remaining character, passing it to the block.
 * - #each_codepoint: reads each remaining codepoint, passing it to the block.
 * - #each_line: reads all or part of each remaining line, passing the read string to the block
 *
 * This instance method is useful in a multi-threaded application:
 *
 * - #pread: reads and returns all or part of the stream.
 *
 * ### Basic Writing
 *
 * You can write to the stream, advancing the position, using these instance methods:
 *
 * - #putc: writes a given character.
 * - #write: writes the given objects as strings.
 * - [Kernel#puts][kernel#puts] writes given objects as strings, each followed by newline.
 *
 * You can "unshift" to the stream using these instance methods;
 * each  writes _before_ the current position, and decrements the position
 * so that the written data is next to be read.
 *
 * - #ungetbyte: unshifts the given byte.
 * - #ungetc: unshifts the given character.
 *
 * One more writing method:
 *
 * - #truncate: truncates the stream's string to the given size.
 *
 * ## Line \IO
 *
 * Reading:
 *
 * - #gets: reads and returns the next line.
 * - [Kernel#readline][kernel#readline]: like #gets, but raises an exception if at end-of-stream.
 * - #readlines: reads the remaining data the stream and returns an array of its lines.
 * - #each_line: reads each remaining line, passing it to the block
 *
 * Writing:
 *
 * - [Kernel#puts][kernel#puts]: writes given objects, each followed by newline.
 *
 * ## Character \IO
 *
 * Reading:
 *
 * - #each_char: reads each remaining character, passing it to the block.
 * - #getc: reads and returns the next character.
 *
 * Writing:
 *
 * - #putc: writes the given character.
 * - #ungetc.: unshifts the given character.
 *
 * ## Byte \IO
 *
 * Reading:
 *
 * - #each_byte: reads each remaining byte, passing it to the block.
 * - #getbyte: reads and returns the next byte.
 *
 * Writing:
 *
 * - #ungetbyte: unshifts the given byte.
 *
 * ## Codepoint \IO
 *
 * Reading:
 *
 * - #each_codepoint: reads each remaining codepoint, passing it to the block.
 *
 * [bom]:                https://en.wikipedia.org/wiki/Byte_order_mark
 * [encodings document]: https://docs.ruby-lang.org/en/master/language/encodings_rdoc.html
 * [io class]:           https://docs.ruby-lang.org/en/master/IO.html
 * [kernel#puts]:        https://docs.ruby-lang.org/en/master/Kernel.html#method-i-puts
 * [kernel#readline]:    https://docs.ruby-lang.org/en/master/Kernel.html#method-i-readline
 *
 * [basic reading]:         rdoc-ref:StringIO@Basic+Reading
 * [basic writing]:         rdoc-ref:StringIO@Basic+Writing
 * [bom (byte order mark)]: rdoc-ref:StringIO@BOM+Byte+Order+Mark
 * [data mode]:             rdoc-ref:StringIO@Data+Mode
 * [encodings]:             rdoc-ref:StringIO@Encodings
 * [end-of-stream]:         rdoc-ref:StringIO@End-of-Stream
 * [line number]:           rdoc-ref:StringIO@Line+Number
 * [open/closed streams]:   rdoc-ref:StringIO@OpenClosed+Streams
 * [position]:              rdoc-ref:StringIO@Position
 * [read/write mode]:       rdoc-ref:StringIO@ReadWrite+Mode
 */
void
Init_stringio(void)
{
#undef rb_intern

#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

    VALUE StringIO = rb_define_class("StringIO", rb_cObject);

    /* The version string */
    rb_define_const(StringIO, "VERSION", rb_str_new_cstr(STRINGIO_VERSION));

    rb_include_module(StringIO, rb_mEnumerable);
    rb_define_alloc_func(StringIO, strio_s_allocate);

    /* Maximum length that a StringIO instance can hold */
    rb_define_const(StringIO, "MAX_LENGTH", LEN2NUM(RB_LEN_MAX));

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
    rb_define_method(StringIO, "pread", strio_pread, -1);

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
	/* :stopdoc: */
	VALUE mReadable = rb_define_module_under(rb_cIO, "generic_readable");
	/* :startdoc: */
	rb_define_method(mReadable, "readchar", strio_readchar, 0);
	rb_define_method(mReadable, "readbyte", strio_readbyte, 0);
	rb_define_method(mReadable, "readline", strio_readline, -1);
	rb_define_method(mReadable, "sysread", strio_sysread, -1);
	rb_define_method(mReadable, "readpartial", strio_sysread, -1);
	rb_define_method(mReadable, "read_nonblock", strio_read_nonblock, -1);
	rb_include_module(StringIO, mReadable);
    }
    {
	/* :stopdoc: */
	VALUE mWritable = rb_define_module_under(rb_cIO, "generic_writable");
	/* :startdoc: */
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
