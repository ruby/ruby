/**********************************************************************

  objspace_dump.c - Heap dumping ObjectSpace extender for MRI.

  $Author$
  created at: Sat Oct 11 10:11:00 2013

  NOTE: This extension library is not expected to exist except C Ruby.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "id_table.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/class.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/io.h"
#include "internal/string.h"
#include "internal/sanitizers.h"
#include "symbol.h"
#include "shape.h"
#include "node.h"
#include "objspace.h"
#include "ruby/debug.h"
#include "ruby/util.h"
#include "ruby/io.h"
#include "vm_callinfo.h"
#include "vm_core.h"

RUBY_EXTERN const char ruby_hexdigits[];

#define BUFFER_CAPACITY 4096

struct dump_config {
    VALUE given_output;
    VALUE output_io;
    VALUE string;
    FILE *stream;
    const char *root_category;
    VALUE cur_obj;
    VALUE cur_obj_klass;
    size_t cur_page_slot_size;
    size_t cur_obj_references;
    unsigned int roots: 1;
    unsigned int full_heap: 1;
    unsigned int partial_dump;
    size_t since;
    size_t shapes_since;
    unsigned long buffer_len;
    char buffer[BUFFER_CAPACITY];
};

static void
dump_flush(struct dump_config *dc)
{
    if (dc->buffer_len) {
        if (dc->stream) {
            size_t written = fwrite(dc->buffer, sizeof(dc->buffer[0]), dc->buffer_len, dc->stream);
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

static void
buffer_append(struct dump_config *dc, const char *cstr, unsigned long len)
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
    const unsigned int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT - 1) + 2;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%ld", number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_lu(struct dump_config *dc, const unsigned long number)
{
    const unsigned int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT) + 1;
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
    const unsigned int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT - 1) + 2;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%d", number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_sizet(struct dump_config *dc, const size_t number)
{
    const unsigned int width = DECIMAL_SIZE_OF_BITS(sizeof(number) * CHAR_BIT) + 1;
    buffer_ensure_capa(dc, width);
    unsigned long required = snprintf(dc->buffer + dc->buffer_len, width, "%"PRIuSIZE, number);
    RUBY_ASSERT(required <= width);
    dc->buffer_len += required;
}

static void
dump_append_c(struct dump_config *dc, unsigned char c)
{
    if (c <= 0x1f) {
        const unsigned int width = rb_strlen_lit("\\u0000") + 1;
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
dump_append_ptr(struct dump_config *dc, VALUE ref)
{
    char buffer[roomof(sizeof(VALUE) * CHAR_BIT, 4) + rb_strlen_lit("\"0x\"")];
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
dump_append_ref(struct dump_config *dc, VALUE ref)
{
    RUBY_ASSERT(ref > 0);
    dump_append_ptr(dc, ref);
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

static bool
dump_string_ascii_only(const char *str, long size)
{
    for (long i = 0; i < size; i++) {
        if (str[i] & 0x80) {
            return false;
        }
    }
    return true;
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

    if (RSTRING_LEN(obj) && rb_enc_asciicompat(rb_enc_from_index(ENCODING_GET(obj)))) {
        int cr = ENC_CODERANGE(obj);
        if (cr == RUBY_ENC_CODERANGE_UNKNOWN) {
            if (dump_string_ascii_only(RSTRING_PTR(obj), RSTRING_LEN(obj))) {
                cr = RUBY_ENC_CODERANGE_7BIT;
            }
        }
        if (cr == RUBY_ENC_CODERANGE_7BIT) {
            dump_append(dc, ", \"value\":");
            dump_append_string_value(dc, obj);
        }
    }
}

static inline void
dump_append_id(struct dump_config *dc, ID id)
{
    VALUE str = rb_sym2str(ID2SYM(id));
    if (RTEST(str)) {
        dump_append_string_value(dc, str);
    }
    else {
        dump_append(dc, "\"ID_INTERNAL(");
        dump_append_sizet(dc, rb_id_to_serial(id));
        dump_append(dc, ")\"");
    }
}


static void
dump_object(VALUE obj, struct dump_config *dc)
{
    size_t memsize;
    struct allocation_info *ainfo = objspace_lookup_allocation_info(obj);
    rb_io_t *fptr;
    ID mid;

    if (SPECIAL_CONST_P(obj)) {
        dump_append_special_const(dc, obj);
        return;
    }

    dc->cur_obj = obj;
    dc->cur_obj_references = 0;
    if (BUILTIN_TYPE(obj) == T_NODE || BUILTIN_TYPE(obj) == T_IMEMO) {
        dc->cur_obj_klass = 0;
    } else {
        dc->cur_obj_klass = RBASIC_CLASS(obj);
    }

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

    if (BUILTIN_TYPE(obj) != T_IMEMO) {
        size_t shape_id = rb_obj_shape_id(obj);
        dump_append(dc, ", \"shape_id\":");
        dump_append_sizet(dc, shape_id);
    }

    dump_append(dc, ", \"slot_size\":");
    dump_append_sizet(dc, dc->cur_page_slot_size);

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

        switch (imemo_type(obj)) {
          case imemo_callinfo:
            mid = vm_ci_mid((const struct rb_callinfo *)obj);
            if (mid != 0) {
                dump_append(dc, ", \"mid\":");
                dump_append_id(dc, mid);
            }
            break;

          case imemo_callcache:
            mid = vm_cc_cme((const struct rb_callcache *)obj)->called_id;
            if (mid != 0) {
                dump_append(dc, ", \"called_id\":");
                dump_append_id(dc, mid);

                VALUE klass = ((const struct rb_callcache *)obj)->klass;
                if (klass != 0) {
                    dump_append(dc, ", \"receiver_class\":");
                    dump_append_ref(dc, klass);
                }
            }
            break;

          default:
            break;
        }
        break;

      case T_SYMBOL:
        dump_append_string_content(dc, rb_sym2str(obj));
        break;

      case T_STRING:
        if (STR_EMBED_P(obj))
            dump_append(dc, ", \"embedded\":true");
        if (FL_TEST(obj, RSTRING_FSTR))
            dump_append(dc, ", \"fstring\":true");
        if (CHILLED_STRING_P(obj))
            dump_append(dc, ", \"chilled\":true");
        if (STR_SHARED_P(obj))
            dump_append(dc, ", \"shared\":true");
        else
            dump_append_string_content(dc, obj);

        if (!ENCODING_IS_ASCII8BIT(obj)) {
            dump_append(dc, ", \"encoding\":\"");
            dump_append(dc, rb_enc_name(rb_enc_from_index(ENCODING_GET(obj))));
            dump_append(dc, "\"");
        }

        dump_append(dc, ", \"coderange\":\"");
        switch (RB_ENC_CODERANGE(obj)) {
          case RUBY_ENC_CODERANGE_UNKNOWN:
            dump_append(dc, "unknown");
            break;
          case RUBY_ENC_CODERANGE_7BIT:
            dump_append(dc, "7bit");
            break;
          case RUBY_ENC_CODERANGE_VALID:
            dump_append(dc, "valid");
            break;
          case RUBY_ENC_CODERANGE_BROKEN:
            dump_append(dc, "broken");
            break;
        }
        dump_append(dc, "\"");

        if (RB_ENC_CODERANGE(obj) == RUBY_ENC_CODERANGE_BROKEN)
            dump_append(dc, ", \"broken\":true");

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
        if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, RARRAY_SHARED_FLAG))
            dump_append(dc, ", \"shared\":true");
        if (FL_TEST(obj, RARRAY_EMBED_FLAG))
            dump_append(dc, ", \"embedded\":true");
        break;

      case T_ICLASS:
        if (rb_class_get_superclass(obj)) {
            dump_append(dc, ", \"superclass\":");
            dump_append_ref(dc, rb_class_get_superclass(obj));
        }
        break;

      case T_CLASS:
        dump_append(dc, ", \"variation_count\":");
        dump_append_d(dc, rb_class_variation_count(obj));

      case T_MODULE:
        if (rb_class_get_superclass(obj)) {
            dump_append(dc, ", \"superclass\":");
            dump_append_ref(dc, rb_class_get_superclass(obj));
        }

        if (dc->cur_obj_klass) {
            VALUE mod_name = rb_mod_name(obj);
            if (!NIL_P(mod_name)) {
                dump_append(dc, ", \"name\":");
                dump_append_string_value(dc, mod_name);
            }
            else {
                VALUE real_mod_name = rb_mod_name(rb_class_real(obj));
                if (RTEST(real_mod_name)) {
                    dump_append(dc, ", \"real_class_name\":\"");
                    dump_append(dc, RSTRING_PTR(real_mod_name));
                    dump_append(dc, "\"");
                }
            }

            if (rb_class_singleton_p(obj)) {
                dump_append(dc, ", \"singleton\":true");
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
        if (FL_TEST(obj, ROBJECT_EMBED)) {
            dump_append(dc, ", \"embedded\":true");
        }

        dump_append(dc, ", \"ivars\":");
        dump_append_lu(dc, ROBJECT_FIELDS_COUNT(obj));
        if (rb_shape_obj_too_complex_p(obj)) {
            dump_append(dc, ", \"too_complex_shape\":true");
        }
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
        if (ainfo->path) {
            dump_append(dc, ", \"file\":\"");
            dump_append(dc, ainfo->path);
            dump_append(dc, "\"");
        }
        if (ainfo->line) {
            dump_append(dc, ", \"line\":");
            dump_append_lu(dc, ainfo->line);
        }
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

    struct rb_gc_object_metadata_entry *gc_metadata = rb_gc_object_metadata(obj);
    for (int i = 0; gc_metadata[i].name != 0; i++) {
        if (i == 0) {
            dump_append(dc, ", \"flags\":{");
        }
        else {
            dump_append(dc, ", ");
        }

        dump_append(dc, "\"");
        dump_append(dc, rb_id2name(gc_metadata[i].name));
        dump_append(dc, "\":");
        dump_append_special_const(dc, gc_metadata[i].val);
    }

    /* If rb_gc_object_metadata had any entries, we need to close the opening
     * `"flags":{`. */
    if (gc_metadata[0].name != 0) {
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
        void *ptr = rb_asan_poisoned_object_p(v);
        rb_asan_unpoison_object(v, false);
        dc->cur_page_slot_size = stride;

        if (dc->full_heap || RBASIC(v)->flags)
            dump_object(v, dc);

        if (ptr) {
            rb_asan_poison_object(v);
        }
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
dump_output(struct dump_config *dc, VALUE output, VALUE full, VALUE since, VALUE shapes)
{
    dc->given_output = output;
    dc->full_heap = 0;
    dc->buffer_len = 0;

    if (TYPE(output) == T_STRING) {
        dc->stream = NULL;
        dc->string = output;
    }
    else {
        rb_io_t *fptr;
        // Output should be an IO, typecheck and get a FILE* for writing.
        // We cannot write with the usual IO code here because writes
        // interleave with calls to rb_gc_mark(). The usual IO code can
        // cause a thread switch, raise exceptions, and even run arbitrary
        // ruby code through the fiber scheduler.
        //
        // Mark functions generally can't handle these possibilities so
        // the usual IO code is unsafe in this context. (For example,
        // there are many ways to crash when ruby code runs and mutates
        // the execution context while rb_execution_context_mark() is in
        // progress.)
        //
        // Using FILE* isn't perfect, but it avoids the most acute problems.
        output = rb_io_get_io(output);
        dc->output_io = rb_io_get_write_io(output);
        rb_io_flush(dc->output_io);
        GetOpenFile(dc->output_io, fptr);
        dc->stream = rb_io_stdio_file(fptr);
        dc->string = Qfalse;
    }

    if (full == Qtrue) {
        dc->full_heap = 1;
    }

    if (RTEST(since)) {
        dc->partial_dump = 1;
        dc->since = NUM2SIZET(since);
    }
    else {
        dc->partial_dump = 0;
    }

    dc->shapes_since = RTEST(shapes) ? NUM2SIZET(shapes) : 0;
}

static VALUE
dump_result(struct dump_config *dc)
{
    dump_flush(dc);

    if (dc->stream) {
        fflush(dc->stream);
    }
    if (dc->string) {
        return dc->string;
    }
    return dc->given_output;
}

/* :nodoc: */
static VALUE
objspace_dump(VALUE os, VALUE obj, VALUE output)
{
    struct dump_config dc = {0,};
    if (!RB_SPECIAL_CONST_P(obj)) {
        dc.cur_page_slot_size = rb_gc_obj_slot_size(obj);
    }

    dump_output(&dc, output, Qnil, Qnil, Qnil);

    dump_object(obj, &dc);

    return dump_result(&dc);
}

static void
shape_id_i(shape_id_t shape_id, void *data)
{
    struct dump_config *dc = (struct dump_config *)data;

    if (shape_id < dc->shapes_since) {
        return;
    }

    rb_shape_t *shape = RSHAPE(shape_id);
    dump_append(dc, "{\"address\":");
    dump_append_ref(dc, (VALUE)shape);

    dump_append(dc, ", \"type\":\"SHAPE\", \"id\":");
    dump_append_sizet(dc, shape_id);

    if (shape->type != SHAPE_ROOT) {
        dump_append(dc, ", \"parent_id\":");
        dump_append_lu(dc, shape->parent_id);
    }

    dump_append(dc, ", \"depth\":");
    dump_append_sizet(dc, rb_shape_depth(shape_id));

    switch((enum shape_type)shape->type) {
      case SHAPE_ROOT:
        dump_append(dc, ", \"shape_type\":\"ROOT\"");
        break;
      case SHAPE_IVAR:
        dump_append(dc, ", \"shape_type\":\"IVAR\"");

        dump_append(dc, ",\"edge_name\":");
        dump_append_id(dc, shape->edge_name);

        break;
      case SHAPE_T_OBJECT:
        dump_append(dc, ", \"shape_type\":\"T_OBJECT\"");
        break;
      case SHAPE_OBJ_ID:
        dump_append(dc, ", \"shape_type\":\"OBJ_ID\"");
        break;
    }

    dump_append(dc, ", \"edges\":");
    dump_append_sizet(dc, rb_shape_edges_count(shape_id));

    dump_append(dc, ", \"memsize\":");
    dump_append_sizet(dc, rb_shape_memsize(shape_id));

    dump_append(dc, "}\n");
}

/* :nodoc: */
static VALUE
objspace_dump_all(VALUE os, VALUE output, VALUE full, VALUE since, VALUE shapes)
{
    struct dump_config dc = {0,};
    dump_output(&dc, output, full, since, shapes);

    if (!dc.partial_dump || dc.since == 0) {
        /* dump roots */
        rb_objspace_reachable_objects_from_root(root_obj_i, &dc);
        if (dc.roots) dump_append(&dc, "]}\n");
    }

    if (RTEST(shapes)) {
        rb_shape_each_shape_id(shape_id_i, &dc);
    }

    /* dump all objects */
    rb_objspace_each_objects(heap_i, &dc);

    return dump_result(&dc);
}

/* :nodoc: */
static VALUE
objspace_dump_shapes(VALUE os, VALUE output, VALUE shapes)
{
    struct dump_config dc = {0,};
    dump_output(&dc, output, Qfalse, Qnil, shapes);

    if (RTEST(shapes)) {
        rb_shape_each_shape_id(shape_id_i, &dc);
    }
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
    rb_define_module_function(rb_mObjSpace, "_dump_all", objspace_dump_all, 4);
    rb_define_module_function(rb_mObjSpace, "_dump_shapes", objspace_dump_shapes, 2);
}
