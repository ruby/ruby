/**********************************************************************

  stringio.c -

  $Author$
  $Date$
  created at: Tue Feb 19 04:10:38 JST 2002

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby.h"
#include "rubyio.h"

#define STRIO_APPEND 4

struct StringIO {
    VALUE string;
    long pos;
    long lineno;
    int flags;
    int count;
};

static struct StringIO* strio_alloc _((void));
static void strio_mark _((struct StringIO *));
static void strio_free _((struct StringIO *));
static struct StringIO* check_strio _((VALUE));
static struct StringIO* get_strio _((VALUE));
static struct StringIO* readable _((struct StringIO *));
static struct StringIO* writable _((struct StringIO *));

#define IS_STRIO(obj) (RDATA(obj)->dmark == (RUBY_DATA_FUNC)strio_mark)
#define error_inval(msg) (errno = EINVAL, rb_sys_fail(msg))

static struct StringIO *
strio_alloc()
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
strio_mark(ptr)
    struct StringIO *ptr;
{
    rb_gc_mark(ptr->string);
}

static void
strio_free(ptr)
    struct StringIO *ptr;
{
    if (--ptr->count <= 0) {
	xfree(ptr);
    }
}

static struct StringIO*
check_strio(self)
    VALUE self;
{
    Check_Type(self, T_DATA);
    if (!IS_STRIO(self)) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected String::IO)",
		 rb_class2name(CLASS_OF(self)));
    }
    return DATA_PTR(self);
}

static struct StringIO*
get_strio(self)
    VALUE self;
{
    struct StringIO *ptr = check_strio(self);

    if (!ptr) {
	rb_raise(rb_eIOError, "uninitialized stream");
    }
    return ptr;
}

#define StringIO(obj) get_strio(obj)

static struct StringIO*
readable(ptr)
    struct StringIO *ptr;
{
    if (NIL_P(ptr->string) || !(ptr->flags & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "not opened for reading");
    }
    return ptr;
}

static struct StringIO*
writable(ptr)
    struct StringIO *ptr;
{
    if (NIL_P(ptr->string) || !(ptr->flags & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "not opened for writing");
    }
    if (!OBJ_TAINTED(ptr->string)) {
	rb_secure(4);
    }
    return ptr;
}

static VALUE strio_s_allocate _((VALUE));
static VALUE strio_s_open _((int, VALUE *, VALUE));
static VALUE strio_initialize _((int, VALUE *, VALUE));
static VALUE strio_finalize _((VALUE));
static VALUE strio_self _((VALUE));
static VALUE strio_false _((VALUE));
static VALUE strio_nil _((VALUE));
static VALUE strio_0 _((VALUE));
static VALUE strio_first _((VALUE, VALUE));
static VALUE strio_unimpl _((int, VALUE *, VALUE));
static VALUE strio_get_string _((VALUE));
static VALUE strio_set_string _((VALUE, VALUE));
static VALUE strio_close _((VALUE));
static VALUE strio_close_read _((VALUE));
static VALUE strio_close_write _((VALUE));
static VALUE strio_closed _((VALUE));
static VALUE strio_closed_read _((VALUE));
static VALUE strio_closed_write _((VALUE));
static VALUE strio_eof _((VALUE));
static VALUE strio_clone _((VALUE));
static VALUE strio_get_lineno _((VALUE));
static VALUE strio_set_lineno _((VALUE, VALUE));
static VALUE strio_get_pos _((VALUE));
static VALUE strio_set_pos _((VALUE, VALUE));
static VALUE strio_rewind _((VALUE));
static VALUE strio_seek _((int, VALUE *, VALUE));
static VALUE strio_get_sync _((VALUE));
static VALUE strio_set_sync _((VALUE, VALUE));
static VALUE strio_each_byte _((VALUE));
static VALUE strio_getc _((VALUE));
static VALUE strio_ungetc _((VALUE, VALUE));
static VALUE strio_readchar _((VALUE));
static VALUE strio_gets_internal _((int, VALUE *, struct StringIO *));
static VALUE strio_gets _((int, VALUE *, VALUE));
static VALUE strio_readline _((int, VALUE *, VALUE));
static VALUE strio_each _((int, VALUE *, VALUE));
static VALUE strio_readlines _((int, VALUE *, VALUE));
static VALUE strio_write _((VALUE, VALUE));
static VALUE strio_print _((int, VALUE *, VALUE));
static VALUE strio_printf _((int, VALUE *, VALUE));
static VALUE strio_putc _((VALUE, VALUE));
static VALUE strio_read _((int, VALUE *, VALUE));
static VALUE strio_size _((VALUE));
static VALUE strio_truncate _((VALUE, VALUE));
void Init_stringio _((void));

/* Boyer-Moore search: copied from regex.c */
static void bm_init_skip _((long *, const char *, long));
static long bm_search _((const char *, long, const char *, long, const long *));

static VALUE
strio_s_allocate(klass)
    VALUE klass;
{
    struct StringIO *ptr;
    return Data_Wrap_Struct(klass, strio_mark, strio_free, 0);
}

static VALUE
strio_s_open(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj = rb_class_new_instance(argc, argv, klass);
    if (!rb_block_given_p()) return obj;
    return rb_ensure(rb_yield, obj, strio_finalize, obj);
}

static VALUE
strio_initialize(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct StringIO *ptr = check_strio(self);
    VALUE string, mode;

    if (!ptr) {
	DATA_PTR(self) = ptr = strio_alloc();
    }
    rb_call_super(0, 0);
    switch (rb_scan_args(argc, argv, "02", &string, &mode)) {
      case 2:
	StringValue(mode);
	StringValue(string);
	ptr->flags = rb_io_mode_flags(RSTRING(mode)->ptr);
	switch (*RSTRING(mode)->ptr) {
	  case 'a':
	    ptr->flags |= STRIO_APPEND;
	    break;
	  case 'w':
	    rb_str_resize(string, 0);
	    break;
	}
	break;
      case 1:
	StringValue(string);
	ptr->flags = FMODE_READWRITE;
	break;
      case 0:
	string = rb_str_new("", 0);
	ptr->flags = FMODE_READWRITE;
	break;
    }
    ptr->string = string;
    return self;
}

static VALUE
strio_finalize(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    ptr->string = Qnil;
    ptr->flags &= ~FMODE_READWRITE;
    return self;
}

static VALUE
strio_false(self)
    VALUE self;
{
    StringIO(self);
    return Qfalse;
}

static VALUE
strio_nil(self)
    VALUE self;
{
    StringIO(self);
    return Qnil;
}

static VALUE
strio_self(self)
    VALUE self;
{
    StringIO(self);
    return self;
}

static VALUE
strio_0(self)
    VALUE self;
{
    StringIO(self);
    return INT2FIX(0);
}

static VALUE
strio_first(self, arg)
    VALUE self, arg;
{
    StringIO(self);
    return arg;
}

static VALUE
strio_unimpl(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    StringIO(self);
    rb_notimplement();
    return Qnil;		/* not reached */
}

static VALUE
strio_get_string(self)
    VALUE self;
{
    return StringIO(self)->string;
}

static VALUE
strio_set_string(self, string)
    VALUE self, string;
{
    struct StringIO *ptr = StringIO(self);

    if (NIL_P(string)) {
	ptr->flags &= ~FMODE_READWRITE;
    }
    else {
	StringValue(string);
	ptr->flags |= FMODE_READWRITE;
    }
    return ptr->string = string;
}

static VALUE
strio_close(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    if (NIL_P(ptr->string)) {
	rb_raise(rb_eIOError, "closed stream");
    }
    ptr->string = Qnil;
    ptr->flags &= ~FMODE_READWRITE;
    return self;
}

static VALUE
strio_close_read(self)
    VALUE self;
{
    struct StringIO *ptr = readable(StringIO(self));
    if (!((ptr->flags &= ~FMODE_READABLE) & FMODE_READWRITE)) {
	ptr->string = Qnil;
    }
    return self;
}

static VALUE
strio_close_write(self)
    VALUE self;
{
    struct StringIO *ptr = writable(StringIO(self));
    if (!((ptr->flags &= ~FMODE_WRITABLE) & FMODE_READWRITE)) {
	ptr->string = Qnil;
    }
    return self;
}

static VALUE
strio_closed(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    if (!NIL_P(ptr->string)) return Qfalse;
    return Qtrue;
}

static VALUE
strio_closed_read(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    if (ptr->flags & FMODE_READABLE) return Qfalse;
    return Qtrue;
}

static VALUE
strio_closed_write(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    if (ptr->flags & FMODE_WRITABLE) return Qfalse;
    return Qtrue;
}

static VALUE
strio_eof(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    if (!(ptr->flags & FMODE_READABLE)) return Qtrue;
    if (NIL_P(ptr->string)) return Qtrue;
    if (ptr->pos < RSTRING(ptr->string)->len) return Qfalse;
    return Qtrue;
}

static VALUE
strio_clone(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    VALUE clone = rb_call_super(0, 0);
    DATA_PTR(clone) = ptr;
    ++ptr->count;
    return self;
}

static VALUE
strio_get_lineno(self)
    VALUE self;
{
    return LONG2NUM(StringIO(self)->lineno);
}

static VALUE
strio_set_lineno(self, lineno)
    VALUE self, lineno;
{
    StringIO(self)->lineno = NUM2LONG(lineno);
    return lineno;
}

#define strio_binmode strio_self

#define strio_reopen strio_unimpl

#define strio_fcntl strio_unimpl

#define strio_flush strio_self

#define strio_fsync strio_0

static VALUE
strio_get_pos(self)
    VALUE self;
{
    return LONG2NUM(StringIO(self)->pos);
}

static VALUE
strio_set_pos(self, pos)
    VALUE self;
    VALUE pos;
{
    struct StringIO *ptr = StringIO(self);
    long p = NUM2LONG(pos);
    if (p < 0) {
	error_inval(0);
    }
    ptr->pos = p;
    return pos;
}

static VALUE
strio_rewind(self)
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    ptr->pos = 0;
    ptr->lineno = 0;
    return INT2FIX(0);
}

static VALUE
strio_seek(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE whence;
    struct StringIO *ptr = StringIO(self);
    long offset;

    rb_scan_args(argc, argv, "11", NULL, &whence);
    offset = NUM2LONG(argv[0]);
    switch (NIL_P(whence) ? 0 : NUM2LONG(whence)) {
      case 0:
	break;
      case 1:
	offset += ptr->pos;
	break;
      case 2:
	offset += RSTRING(ptr->string)->len;
	break;
      default:
	rb_raise(rb_eArgError, "invalid whence %ld", NUM2LONG(whence));
    }
    if (offset < 0) {
	error_inval(0);
    }
    ptr->pos = offset;
    return INT2FIX(0);
}

static VALUE
strio_get_sync(self)
    VALUE self;
{
    StringIO(self);
    return Qtrue;
}

#define strio_set_sync strio_first

#define strio_tell strio_get_pos

static VALUE
strio_each_byte(self)
    VALUE self;
{
    struct StringIO *ptr = readable(StringIO(self));
    while (ptr->pos < RSTRING(ptr->string)->len) {
	char c = RSTRING(ptr->string)->ptr[ptr->pos++];
	rb_yield(CHR2FIX(c));
    }
    return Qnil;
}

static VALUE
strio_getc(self)
    VALUE self;
{
    struct StringIO *ptr = readable(StringIO(self));
    int c;
    if (ptr->pos >= RSTRING(ptr->string)->len) {
	return Qnil;
    }
    c = RSTRING(ptr->string)->ptr[ptr->pos++];
    return CHR2FIX(c);
}

static VALUE
strio_ungetc(self, ch)
    VALUE self, ch;
{
    struct StringIO *ptr = readable(StringIO(self));
    int cc = NUM2INT(ch);

    if (cc != EOF && ptr->pos > 0) {
	rb_str_modify(ptr->string);
	RSTRING(ptr->string)->ptr[--ptr->pos] = cc;
    }
    return Qnil;
}

static VALUE
strio_readchar(self)
    VALUE self;
{
    VALUE c = strio_getc(self);
    if (NIL_P(c)) rb_eof_error();
    return c;
}

static void
bm_init_skip(skip, pat, m)
     long *skip;
     const char *pat;
     long m;
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
bm_search(little, llen, big, blen, skip)
    const char *little;
    long llen;
    const char *big;
    long blen;
    const long *skip;
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

static VALUE
strio_gets_internal(argc, argv, ptr)
    int argc;
    VALUE *argv;
    struct StringIO *ptr;
{
    const char *s, *e, *p;
    long n;
    VALUE str;

    if (argc == 0) {
	str = rb_rs;
    }
    else {
	rb_scan_args(argc, argv, "1", &str);
	if (!NIL_P(str)) StringValue(str);
    }

    if (ptr->pos >= (n = RSTRING(ptr->string)->len)) return Qnil;
    s = RSTRING(ptr->string)->ptr;
    e = s + RSTRING(ptr->string)->len;
    s += ptr->pos;
    if (NIL_P(str)) {
	str = rb_str_substr(ptr->string, ptr->pos, e - s);
    }
    else if ((n = RSTRING(str)->len) == 0) {
	p = s;
	while (*p == '\n') {
	    if (++p == e) return Qnil;
	}
	s = p;
	while (p = memchr(p, '\n', e - p)) {
	    if (p == e) break;
	    if (*++p == '\n') {
		e = p;
		break;
	    }
	}
	str = rb_str_substr(ptr->string, s - RSTRING(ptr->string)->ptr, e - s); 
    }
    else if (n == 1) {
	if (p = memchr(s, RSTRING(str)->ptr[0], e - s)) {
	    e = p + 1;
	}
	str = rb_str_substr(ptr->string, ptr->pos, e - s);
    }
    else {
	if (n < s - e) {
	    if (s - e < 1024) {
		for (p = s; p + n <= e; ++p) {
		    if (MEMCMP(p, RSTRING(str)->ptr, char, n) == 0) {
			e = p + n;
			break;
		    }
		}
	    }
	    else {
		long skip[1 << CHAR_BIT], pos;
		p = RSTRING(str)->ptr;
		bm_init_skip(skip, p, n);
		if ((pos = bm_search(p, n, s, e - s, skip)) >= 0) {
		    e = s + pos + n;
		}
	    }
	}
	str = rb_str_substr(ptr->string, ptr->pos, e - s);
    }
    ptr->pos = e - RSTRING(ptr->string)->ptr;
    ptr->lineno++;
    rb_lastline_set(str);
    return str;
}

static VALUE
strio_gets(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    return strio_gets_internal(argc, argv, readable(StringIO(self)));
}

static VALUE
strio_readline(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE line = strio_gets_internal(argc, argv, readable(StringIO(self)));
    if (NIL_P(line)) rb_eof_error();
    return line;
}

static VALUE
strio_each(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    VALUE line;

    while (!NIL_P(line = strio_gets_internal(argc, argv, readable(ptr)))) {
	rb_yield(line);
    }
    return self;
}

static VALUE
strio_readlines(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct StringIO *ptr = StringIO(self);
    VALUE ary = rb_ary_new(), line;
    while (!NIL_P(line = strio_gets_internal(argc, argv, readable(ptr)))) {
	rb_ary_push(ary, line);
    }
    return ary;
}

static VALUE
strio_write(self, str)
    VALUE self, str;
{
    struct StringIO *ptr = writable(StringIO(self));
    long len;

    if (TYPE(str) != T_STRING)
	str = rb_obj_as_string(str);
    len = RSTRING(str)->len;
    if (ptr->flags & STRIO_APPEND) {
	ptr->pos = RSTRING(ptr->string)->len;
    }
    if (ptr->pos + len > RSTRING(ptr->string)->len) {
	rb_str_resize(ptr->string, ptr->pos + len);
    }
    rb_str_update(ptr->string, ptr->pos, len, str);
    ptr->pos += len;
    return LONG2NUM(len);
}

#define strio_addstr rb_io_addstr

#define strio_print rb_io_print

#define strio_printf rb_io_printf

static VALUE
strio_putc(self, ch)
    VALUE self, ch;
{
    struct StringIO *ptr = writable(StringIO(self));
    int c = NUM2CHR(ch);

    if (ptr->pos >= RSTRING(ptr->string)->len) {
	rb_str_resize(ptr->string, ptr->pos + 1);
    }
    RSTRING(ptr->string)->ptr[ptr->pos++] = c;
    return ch;
}

#define strio_puts rb_io_puts

static VALUE
strio_read(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct StringIO *ptr = readable(StringIO(self));
    VALUE str;
    long len;

    if (ptr->pos >= RSTRING(ptr->string)->len) {
	return Qnil;
    }
    switch (argc) {
      case 1:
	if (!NIL_P(argv[0])) {
	    len = NUM2LONG(argv[0]);
	    break;
	}
	/* fall through */
      case 0:
	len = RSTRING(ptr->string)->len - ptr->pos;
	break;
      default:
	rb_raise(rb_eArgError, "wrong number arguments (%d for 0)", argc);
    }
    str = rb_str_substr(ptr->string, ptr->pos, len);
    ptr->pos += len;
    return str;
}

static VALUE
strio_sysread(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE val = strio_read(argc, argv, self);
    if (NIL_P(val)) {
	rb_eof_error();
    }
    return val;
}

#define strio_syswrite strio_write

#define strio_path rb_inspect

#define strio_isatty strio_false

#define strio_pid strio_nil

#define strio_fileno strio_nil

static VALUE
strio_size(self)
    VALUE self;
{
    VALUE string = StringIO(self)->string;
    if (NIL_P(string)) {
	rb_raise(rb_eIOError, "not opened");
    }
    return ULONG2NUM(RSTRING(string)->len);
}

static VALUE
strio_truncate(self, len)
    VALUE self, len;
{
    VALUE string = writable(StringIO(self))->string;
    long l = NUM2LONG(len);
    if (l < 0) {
	error_inval("negative legnth");
    }
    rb_str_resize(string, l);
    return len;
}

void
Init_stringio()
{
    VALUE StringIO = rb_define_class("StringIO", rb_cData);
    rb_define_singleton_method(StringIO, "allocate", strio_s_allocate, 0);
    rb_define_singleton_method(StringIO, "open", strio_s_open, -1);
    rb_define_method(StringIO, "initialize", strio_initialize, -1);
    rb_enable_super(StringIO, "initialize");
    rb_define_method(StringIO, "clone", strio_clone, 0);
    rb_enable_super(StringIO, "clone");
    rb_define_method(StringIO, "reopen", strio_reopen, -1);

    rb_define_method(StringIO, "string", strio_get_string, 0);
    rb_define_method(StringIO, "string=", strio_set_string, 1);
    rb_define_method(StringIO, "lineno", strio_get_lineno, 0);
    rb_define_method(StringIO, "lineno=", strio_set_lineno, 1);

    rb_define_method(StringIO, "binmode", strio_binmode, 0);
    rb_define_method(StringIO, "close", strio_close, 0);
    rb_define_method(StringIO, "close_read", strio_close_read, 0);
    rb_define_method(StringIO, "close_write", strio_close_write, 0);
    rb_define_method(StringIO, "closed?", strio_closed, 0);
    rb_define_method(StringIO, "closed_read?", strio_closed_read, 0);
    rb_define_method(StringIO, "closed_write?", strio_closed_write, 0);
    rb_define_method(StringIO, "eof", strio_eof, 0);
    rb_define_method(StringIO, "eof?", strio_eof, 0);
    rb_define_method(StringIO, "fcntl", strio_fcntl, -1);
    rb_define_method(StringIO, "flush", strio_flush, 0);
    rb_define_method(StringIO, "fsync", strio_fsync, 0);
    rb_define_method(StringIO, "pos", strio_get_pos, 0);
    rb_define_method(StringIO, "pos=", strio_set_pos, 1);
    rb_define_method(StringIO, "rewind", strio_rewind, 0);
    rb_define_method(StringIO, "seek", strio_seek, -1);
    rb_define_method(StringIO, "sync", strio_get_sync, 0);
    rb_define_method(StringIO, "sync=", strio_set_sync, 1);
    rb_define_method(StringIO, "tell", strio_tell, 0);
    rb_define_method(StringIO, "path", strio_path, 0);

    rb_define_method(StringIO, "each", strio_each, -1);
    rb_define_method(StringIO, "each_byte", strio_each_byte, 0);
    rb_define_method(StringIO, "each_line", strio_each, -1);
    rb_define_method(StringIO, "getc", strio_getc, 0);
    rb_define_method(StringIO, "ungetc", strio_ungetc, 1);
    rb_define_method(StringIO, "readchar", strio_readchar, 0);
    rb_define_method(StringIO, "gets", strio_gets, -1);
    rb_define_method(StringIO, "readline", strio_readline, -1);
    rb_define_method(StringIO, "readlines", strio_readlines, -1);
    rb_define_method(StringIO, "read", strio_read, -1);
    rb_define_method(StringIO, "sysread", strio_sysread, -1);

    rb_define_method(StringIO, "write", strio_write, 1);
    rb_define_method(StringIO, "<<", strio_addstr, 1);
    rb_define_method(StringIO, "print", strio_print, -1);
    rb_define_method(StringIO, "printf", strio_printf, -1);
    rb_define_method(StringIO, "putc", strio_putc, 1);
    rb_define_method(StringIO, "puts", strio_puts, -1);
    rb_define_method(StringIO, "syswrite", strio_syswrite, 1);

    rb_define_method(StringIO, "isatty", strio_isatty, 0);
    rb_define_method(StringIO, "tty?", strio_isatty, 0);
    rb_define_method(StringIO, "pid", strio_pid, 0);
    rb_define_method(StringIO, "fileno", strio_fileno, 0);
    rb_define_method(StringIO, "size", strio_size, 0);
    rb_define_method(StringIO, "length", strio_size, 0);
    rb_define_method(StringIO, "truncate", strio_truncate, 1);
}
