/**********************************************************************

  objspace_dump.c - Heap dumping ObjectSpace extender for MRI.

  $Author$
  created at: Sat Oct 11 10:11:00 2013

  NOTE: This extension library is not expected to exist except C Ruby.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "gc.h"
#include "internal.h"
#include "internal/hash.h"
#include "internal/string.h"
#include "node.h"
#include "objspace.h"
#include "ruby/debug.h"
#include "ruby/util.h"
#include "ruby/io.h"
#include "vm_core.h"

RUBY_EXTERN const char ruby_hexdigits[];

#define BUFFER_CAPACITY 4096

struct dump_config {
    VALUE type;
    VALUE stream;
    VALUE string;
    const char *root_category;
    VALUE cur_obj;
    VALUE cur_obj_klass;
    size_t cur_obj_references;
    unsigned int roots: 1;
    unsigned int full_heap: 1;
    unsigned int partial_dump;
    size_t since;
    unsigned long buffer_len;
    char buffer[BUFFER_CAPACITY];
};

static void
dump_flush(struct dump_config *dc)
{
    if (dc->buffer_len) {
        if (dc->stream) {
            size_t written = rb_io_bufwrite(dc->stream, dc->buffer, dc->buffer_len);
            if (written < dc->buffer_len) {
                MEMMOVE(dc->buffer, dc->buffer + written, char, dc->buffer_len - written);
                dc->buffer_len -= written;
                return;
            }
        }
        else if (dc->string) {
            rb_str_cat(dc->string, dc->buffer, dc->buffer_len);
        }
        dc->buffer_len = 0;
    }
}

static inline void
buffer_ensure_capa(struct dump_config *dc, unsigned long requested)
{
    RUBY_ASSERT(requested <= BUFFER_CAPACITY);
    if (requested + dc->buffer_len >= BUFFER_CAPACITY) {
        dump_flush(dc);
        if (requested + dc->buffer_len >= BUFFER_CAPACITY) {
            rb_raise(rb_eIOError, "full buffer");
        }
    }
}

static void buffer_append(struct dump_config *dc, const char *cstr, unsigned long len)
{
    if (LIKELY(len > 0)) {
        buffer_ensure_capa(dc, len);
        MEMCPY(dc->buffer + dc->buffer_len, cstr, char, len);
        dc->buffer_len += len;
    }
}

# define dump_append(dc, str) buffer_append(dc, (str), (long)strlen(str))

static void
dump_append_ld(struct dump_config *dc, const long number)
{
    const int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT - 1) + 2;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%ld", number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_lu(struct dump_config *dc, const unsigned long number)
{
    const int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT) + 1;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%lu", number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_g(struct dump_config *dc, const double number)
{
    unsigned long capa_left = BUFFER_CAPACITY - dc->buffer_len;
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, capa_left, "%#g", number);

    if (required >= capa_left) {
        buffer_ensure_capa(dc, required);
        capa_left = BUFFER_CAPACITY - dc->buffer_len;
        snprintf(dc->buffer + dc->buffer_len, capa_left, "%#g", number);
    }
    dc->buffer_len += required;
}

static void
dump_append_d(struct dump_config *dc, const int number)
{
    const int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT - 1) + 2;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%d", number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_sizet(struct dump_config *dc, const size_t number)
{
    const int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT) + 1;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%"PRIuSIZE, number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_c(struct dump_config *dc, char c)
{
    if (c <= 0x1f) {
        const int width = (sizeof(c) * CHAR_BIT / 4) + 5;
        buffer_ensure_capa(dc, width);
        unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "\\u00%02x", c);
        RUBY_ASSERT(required <= width);
        dc->buffer_len += required;
    }
    else {
        buffer_ensure_capa(dc, 1);
        dc->buffer[dc->buffer_len] = c;
        dc->buffer_len++;
    }
}

static void
dump_append_ref(struct dump_config *dc, VALUE ref)
{
    RUBY_ASSERT(ref > 0);

    char buffer[((sizeof(VALUE) * CHAR_BIT + 3) / 4) + 4];
    char *buffer_start, *buffer_end;

    buffer_start = buffer_end = &buffer[sizeof(buffer)];
    *--buffer_start = '"';
    while (ref) {
        *--buffer_start = ruby_hexdigits[ref & 0xF];
        ref >>= 4;
    }
    *--buffer_start = 'x';
    *--buffer_start = '0';
    *--buffer_start = '"';
    buffer_append(dc, buffer_start, buffer_end - buffer_start);
}

static void
dump_append_string_value(struct dump_config *dc, VALUE obj)
{
    long i;
    char c;
    const char *value;

    dump_append(dc, "\"");
    for (i = 0, value = RSTRING_PTR(obj); i < RSTRING_LEN(obj); i++) {
        switch ((c = value[i])) {
          case '\\':
            dump_append(dc, "\\\\");
            break;
          case '"':
            dump_append(dc, "\\\"");
            break;
          case '\0':
            dump_append(dc, "\\u0000");
            break;
          case '\b':
            dump_append(dc, "\\b");
            break;
          case '\t':
            dump_append(dc, "\\t");
            break;
          case '\f':
            dump_append(dc, "\\f");
            break;
          case '\n':
            dump_append(dc, "\\n");
            break;
          case '\r':
            dump_append(dc, "\\r");
            break;
          case '\177':
            dump_append(dc, "\\u007f");
            break;
          default:
            dump_append_c(dc, c);
        }
    }
    dump_append(dc, "\"");
}

static void
dump_append_symbol_value(struct dump_config *dc, VALUE obj)
{
    dump_append(dc, "{\"type\":\"SYMBOL\", \"value\":");
    dump_append_string_value(dc, rb_sym2str(obj));
    dump_append(dc, "}");
}

static inline const char *
obj_type(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
#define CASE_TYPE(type) case T_##type: return #type
	CASE_TYPE(NONE);
	CASE_TYPE(NIL);
	CASE_TYPE(OBJECT);
	CASE_TYPE(CLASS);
	CASE_TYPE(ICLASS);
	CASE_TYPE(MODULE);
	CASE_TYPE(FLOAT);
	CASE_TYPE(STRING);
	CASE_TYPE(REGEXP);
	CASE_TYPE(ARRAY);
	CASE_TYPE(HASH);
	CASE_TYPE(STRUCT);
	CASE_TYPE(BIGNUM);
	CASE_TYPE(FILE);
	CASE_TYPE(FIXNUM);
	CASE_TYPE(TRUE);
	CASE_TYPE(FALSE);
	CASE_TYPE(DATA);
	CASE_TYPE(MATCH);
	CASE_TYPE(SYMBOL);
	CASE_TYPE(RATIONAL);
	CASE_TYPE(COMPLEX);
	CASE_TYPE(IMEMO);
	CASE_TYPE(UNDEF);
	CASE_TYPE(NODE);
	CASE_TYPE(ZOMBIE);
#undef CASE_TYPE
      default: break;
    }
    return "UNKNOWN";
}

static void
dump_append_special_const(struct dump_config *dc, VALUE value)
{
    if (value == Qtrue) {
        dump_append(dc, "true");
    }
    else if (value == Qfalse) {
        dump_append(dc, "false");
    }
    else if (value == Qnil) {
        dump_append(dc, "null");
    }
    else if (FIXNUM_P(value)) {
        dump_append_ld(dc, FIX2LONG(value));
    }
    else if (FLONUM_P(value)) {
        dump_append_g(dc, RFLOAT_VALUE(value));
    }
    else if (SYMBOL_P(value)) {
        dump_append_symbol_value(dc, value);
    }
    else {
        dump_append(dc, "{}");
    }
}

static void
reachable_object_i(VALUE ref, void *data)
{
    struct dump_config *dc = (struct dump_config *)data;

    if (dc->cur_obj_klass == ref)
        return;

    if (dc->cur_obj_references == 0) {
        dump_append(dc, ", \"references\":[");
        dump_append_ref(dc, ref);
    }
    else {
        dump_append(dc, ", ");
        dump_append_ref(dc, ref);
    }

    dc->cur_obj_references++;
}

static void
dump_append_string_content(struct dump_config *dc, VALUE obj)
{
    dump_append(dc, ", \"bytesize\":");
    dump_append_ld(dc, RSTRING_LEN(obj));
    if (!STR_EMBED_P(obj) && !STR_SHARED_P(obj) && (long)rb_str_capacity(obj) != RSTRING_LEN(obj)) {
        dump_append(dc, ", \"capacity\":");
        dump_append_sizet(dc, rb_str_capacity(obj));
    }

    if (is_ascii_string(obj)) {
        dump_append(dc, ", \"value\":");
        dump_append_string_value(dc, obj);
    }
}

static void
dump_object(VALUE obj, struct dump_config *dc)
{
    size_t memsize;
    struct allocation_info *ainfo = objspace_lookup_allocation_info(obj);
    rb_io_t *fptr;
    ID flags[RB_OBJ_GC_FLAGS_MAX];
    size_t n, i;

    if (SPECIAL_CONST_P(obj)) {
        dump_append_special_const(dc, obj);
        return;
    }

    dc->cur_obj = obj;
    dc->cur_obj_references = 0;
    dc->cur_obj_klass = BUILTIN_TYPE(obj) == T_NODE ? 0 : RBASIC_CLASS(obj);

    if (dc->partial_dump && (!ainfo || ainfo->generation < dc->since)) {
        return;
    }

    if (dc->cur_obj == dc->string)
        return;

    dump_append(dc, "{\"address\":");
    dump_append_ref(dc, obj);

    dump_append(dc, ", \"type\":\"");
    dump_append(dc, obj_type(obj));
    dump_append(dc, "\"");

    if (dc->cur_obj_klass) {
        dump_append(dc, ", \"class\":");
        dump_append_ref(dc, dc->cur_obj_klass);
    }
    if (rb_obj_frozen_p(obj))
        dump_append(dc, ", \"frozen\":true");

    switch (BUILTIN_TYPE(obj)) {
      case T_NONE:
        dump_append(dc, "}\n");
        return;

      case T_IMEMO:
        dump_append(dc, ", \"imemo_type\":\"");
        dump_append(dc, rb_imemo_name(imemo_type(obj)));
        dump_append(dc, "\"");
        break;

      case T_SYMBOL:
        dump_append_string_content(dc, rb_sym2str(obj));
        break;

      case T_STRING:
        if (STR_EMBED_P(obj))
            dump_append(dc, ", \"embedded\":true");
        if (is_broken_string(obj))
            dump_append(dc, ", \"broken\":true");
        if (FL_TEST(obj, RSTRING_FSTR))
            dump_append(dc, ", \"fstring\":true");
        if (STR_SHARED_P(obj))
            dump_append(dc, ", \"shared\":true");
        else
            dump_append_string_content(dc, obj);

        if (!ENCODING_IS_ASCII8BIT(obj)) {
            dump_append(dc, ", \"encoding\":\"");
            dump_append(dc, rb_enc_name(rb_enc_from_index(ENCODING_GET(obj))));
            dump_append(dc, "\"");
        }
        break;

      case T_HASH:
        dump_append(dc, ", \"size\":");
        dump_append_sizet(dc, (size_t)RHASH_SIZE(obj));
        if (FL_TEST(obj, RHASH_PROC_DEFAULT)) {
            dump_append(dc, ", \"default\":");
            dump_append_ref(dc, RHASH_IFNONE(obj));
        }
        break;

      case T_ARRAY:
        dump_append(dc, ", \"length\":");
        dump_append_ld(dc, RARRAY_LEN(obj));
        if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, ELTS_SHARED))
            dump_append(dc, ", \"shared\":true");
        if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, RARRAY_EMBED_FLAG))
            dump_append(dc, ", \"embedded\":true");
        break;

      case T_CLASS:
      case T_MODULE:
        if (dc->cur_obj_klass) {
            VALUE mod_name = rb_mod_name(obj);
            if (!NIL_P(mod_name)) {
                dump_append(dc, ", \"name\":\"");
                dump_append(dc, RSTRING_PTR(mod_name));
                dump_append(dc, "\"");
            }
        }
        break;

      case T_DATA:
        if (RTYPEDDATA_P(obj)) {
            dump_append(dc, ", \"struct\":\"");
            dump_append(dc, RTYPEDDATA_TYPE(obj)->wrap_struct_name);
            dump_append(dc, "\"");
        }
        break;

      case T_FLOAT:
        dump_append(dc, ", \"value\":\"");
        dump_append_g(dc, RFLOAT_VALUE(obj));
        dump_append(dc, "\"");
        break;

      case T_OBJECT:
        dump_append(dc, ", \"ivars\":");
        dump_append_lu(dc, ROBJECT_NUMIV(obj));
        break;

      case T_FILE:
        fptr = RFILE(obj)->fptr;
        if (fptr) {
            dump_append(dc, ", \"fd\":");
            dump_append_d(dc, fptr->fd);
        }
        break;

      case T_ZOMBIE:
          dump_append(dc, "}\n");
          return;

      default:
        break;
    }

    rb_objspace_reachable_objects_from(obj, reachable_object_i, dc);
    if (dc->cur_obj_references > 0)
        dump_append(dc, "]");

    if (ainfo) {
        dump_append(dc, ", \"file\":\"");
        dump_append(dc, ainfo->path);
        dump_append(dc, "\", \"line\":");
        dump_append_lu(dc, ainfo->line);
        if (RTEST(ainfo->mid)) {
            VALUE m = rb_sym2str(ainfo->mid);
            dump_append(dc, ", \"method\":");
            dump_append_string_value(dc, m);
        }
        dump_append(dc, ", \"generation\":");
        dump_append_sizet(dc, ainfo->generation);
    }

    if ((memsize = rb_obj_memsize_of(obj)) > 0) {
        dump_append(dc, ", \"memsize\":");
        dump_append_sizet(dc, memsize);
    }

    if ((n = rb_obj_gc_flags(obj, flags, sizeof(flags))) > 0) {
        dump_append(dc, ", \"flags\":{");
        for (i=0; i<n; i++) {
            dump_append(dc, "\"");
            dump_append(dc, rb_id2name(flags[i]));
            dump_append(dc, "\":true");
            if (i != n-1) dump_append(dc, ", ");
        }
        dump_append(dc, "}");
    }

    dump_append(dc, "}\n");
}

static int
heap_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct dump_config *dc = (struct dump_config *)data;
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
	if (dc->full_heap || RBASIC(v)->flags)
	    dump_object(v, dc);
    }
    return 0;
}

static void
root_obj_i(const char *category, VALUE obj, void *data)
{
    struct dump_config *dc = (struct dump_config *)data;

    if (dc->root_category != NULL && category != dc->root_category)
        dump_append(dc, "]}\n");
    if (dc->root_category == NULL || category != dc->root_category) {
        dump_append(dc, "{\"type\":\"ROOT\", \"root\":\"");
        dump_append(dc, category);
        dump_append(dc, "\", \"references\":[");
        dump_append_ref(dc, obj);
    }
    else {
        dump_append(dc, ", ");
        dump_append_ref(dc, obj);
    }

    dc->root_category = category;
    dc->roots = 1;
}

static void
dump_output(struct dump_config *dc, VALUE output, VALUE full, VALUE since)
{

    dc->full_heap = 0;
    dc->buffer_len = 0;

    if (TYPE(output) == T_STRING) {
        dc->stream = Qfalse;
        dc->string = output;
    } else {
        dc->stream = output;
        dc->string = Qfalse;
    }

    if (full == Qtrue) {
        dc->full_heap = 1;
    }

    if (RTEST(since)) {
        dc->partial_dump = 1;
        dc->since = NUM2SIZET(since);
    } else {
        dc->partial_dump = 0;
    }
}

static VALUE
dump_result(struct dump_config *dc)
{
    dump_flush(dc);

    if (dc->string) {
        return dc->string;
    } else {
        rb_io_flush(dc->stream);
        return dc->stream;
    }
}

static VALUE
objspace_dump(VALUE os, VALUE obj, VALUE output)
{
    struct dump_config dc = {0,};
    dump_output(&dc, output, Qnil, Qnil);

    dump_object(obj, &dc);

    return dump_result(&dc);
}

static VALUE
objspace_dump_all(VALUE os, VALUE output, VALUE full, VALUE since)
{
    struct dump_config dc = {0,};
    dump_output(&dc, output, full, since);

    if (!dc.partial_dump || dc.since == 0) {
        /* dump roots */
        rb_objspace_reachable_objects_from_root(root_obj_i, &dc);
        if (dc.roots) dump_append(&dc, "]}\n");
    }

    /* dump all objects */
    rb_objspace_each_objects(heap_i, &dc);

    return dump_result(&dc);
}

void
Init_objspace_dump(VALUE rb_mObjSpace)
{
#undef rb_intern
#if 0
    rb_mObjSpace = rb_define_module("ObjectSpace"); /* let rdoc know */
#endif

    rb_define_module_function(rb_mObjSpace, "_dump", objspace_dump, 2);
    rb_define_module_function(rb_mObjSpace, "_dump_all", objspace_dump_all, 3);

    /* force create static IDs */
    rb_obj_gc_flags(rb_mObjSpace, 0, 0);
}
