/**********************************************************************

  objspace_dump.c - Heap dumping ObjectSpace extender for MRI.

  $Author$
  created at: Sat Oct 11 10:11:00 2013

  NOTE: This extension library is not expected to exist except C Ruby.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/debug.h"
#include "ruby/encoding.h"
#include "ruby/io.h"
#include "gc.h"
#include "node.h"
#include "vm_core.h"
#include "objspace.h"

static VALUE sym_output, sym_stdout, sym_string, sym_file;

struct dump_config {
    VALUE type;
    FILE *stream;
    VALUE string;
    int roots;
    const char *root_category;
    VALUE cur_obj;
    VALUE cur_obj_klass;
    size_t cur_obj_references;
};

static void
dump_append(struct dump_config *dc, const char *format, ...)
{
    va_list vl;
    va_start(vl, format);

    if (dc->stream) {
	vfprintf(dc->stream, format, vl);
	fflush(dc->stream);
    }
    else if (dc->string)
	rb_str_vcatf(dc->string, format, vl);

    va_end(vl);
}

static void
dump_append_string_value(struct dump_config *dc, VALUE obj)
{
    int i;
    char c, *value;

    dump_append(dc, "\"");
    for (i = 0, value = RSTRING_PTR(obj); i < RSTRING_LEN(obj); i++) {
	switch ((c = value[i])) {
	  case '\\':
	  case '"':
	    dump_append(dc, "\\%c", c);
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
	  default:
	    dump_append(dc, "%c", c);
	}
    }
    dump_append(dc, "\"");
}

static inline const char *
obj_type(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
#define CASE_TYPE(type) case T_##type: return #type; break
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
	CASE_TYPE(UNDEF);
	CASE_TYPE(NODE);
	CASE_TYPE(ZOMBIE);
#undef CASE_TYPE
    }
    return "UNKNOWN";
}

static void
reachable_object_i(VALUE ref, void *data)
{
    struct dump_config *dc = (struct dump_config *)data;

    if (dc->cur_obj_klass == ref)
	return;

    if (dc->cur_obj_references == 0)
	dump_append(dc, ", \"references\":[\"%p\"", (void *)ref);
    else
	dump_append(dc, ", \"%p\"", (void *)ref);

    dc->cur_obj_references++;
}

static void
dump_object(VALUE obj, struct dump_config *dc)
{
    size_t memsize;
    struct allocation_info *ainfo;
    rb_io_t *fptr;

    dc->cur_obj = obj;
    dc->cur_obj_references = 0;
    dc->cur_obj_klass = BUILTIN_TYPE(obj) == T_NODE ? 0 : RBASIC_CLASS(obj);

    if (dc->cur_obj == dc->string)
	return;

    dump_append(dc, "{\"address\":\"%p\", \"type\":\"%s\"", (void *)obj, obj_type(obj));

    if (dc->cur_obj_klass)
	dump_append(dc, ", \"class\":\"%p\"", (void *)dc->cur_obj_klass);
    if (rb_obj_frozen_p(obj))
	dump_append(dc, ", \"frozen\":true");

    switch (BUILTIN_TYPE(obj)) {
      case T_NODE:
	dump_append(dc, ", \"node_type\":\"%s\"", ruby_node_name(nd_type(obj)));
	break;

      case T_STRING:
	if (STR_EMBED_P(obj))
	    dump_append(dc, ", \"embedded\":true");
	if (STR_ASSOC_P(obj))
	    dump_append(dc, ", \"associated\":true");
	if (is_broken_string(obj))
	    dump_append(dc, ", \"broken\":true");
	if (STR_SHARED_P(obj))
	    dump_append(dc, ", \"shared\":true");
	else {
	    dump_append(dc, ", \"bytesize\":%ld", RSTRING_LEN(obj));
	    if (!STR_EMBED_P(obj) && !STR_NOCAPA_P(obj) && (long)rb_str_capacity(obj) != RSTRING_LEN(obj))
		dump_append(dc, ", \"capacity\":%ld", rb_str_capacity(obj));

	    if (is_ascii_string(obj)) {
		dump_append(dc, ", \"value\":");
		dump_append_string_value(dc, obj);
	    }
	}

	if (!ENCODING_IS_ASCII8BIT(obj))
	    dump_append(dc, ", \"encoding\":\"%s\"", rb_enc_name(rb_enc_from_index(ENCODING_GET(obj))));
	break;

      case T_HASH:
	dump_append(dc, ", \"size\":%ld", RHASH_SIZE(obj));
	if (FL_TEST(obj, HASH_PROC_DEFAULT))
	    dump_append(dc, ", \"default\":\"%p\"", (void *)RHASH_IFNONE(obj));
	break;

      case T_ARRAY:
	dump_append(dc, ", \"length\":%ld", RARRAY_LEN(obj));
	if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, ELTS_SHARED))
	    dump_append(dc, ", \"shared\":true");
	if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, RARRAY_EMBED_FLAG))
	    dump_append(dc, ", \"embedded\":true");
	break;

      case T_CLASS:
      case T_MODULE:
	if (dc->cur_obj_klass)
	    dump_append(dc, ", \"name\":\"%s\"", rb_class2name(obj));
	break;

      case T_DATA:
	if (RTYPEDDATA_P(obj))
	    dump_append(dc, ", \"struct\":\"%s\"", RTYPEDDATA_TYPE(obj)->wrap_struct_name);
	break;

      case T_FLOAT:
	dump_append(dc, ", \"value\":\"%g\"", RFLOAT_VALUE(obj));
	break;

      case T_OBJECT:
	dump_append(dc, ", \"ivars\":%ld", ROBJECT_NUMIV(obj));
	break;

      case T_FILE:
	fptr = RFILE(obj)->fptr;
	dump_append(dc, ", \"fd\":%d", fptr->fd);
	break;

      case T_ZOMBIE:
	dump_append(dc, "}\n");
	return;
    }

    rb_objspace_reachable_objects_from(obj, reachable_object_i, dc);
    if (dc->cur_obj_references > 0)
	dump_append(dc, "]");

    if ((ainfo = objspace_lookup_allocation_info(obj))) {
	dump_append(dc, ", \"file\":\"%s\", \"line\":%lu", ainfo->path, ainfo->line);
	if (RTEST(ainfo->mid))
	    dump_append(dc, ", \"method\":\"%s\"", rb_id2name(SYM2ID(ainfo->mid)));
	dump_append(dc, ", \"generation\":%zu", ainfo->generation);
    }

    if ((memsize = rb_obj_memsize_of(obj)) > 0)
	dump_append(dc, ", \"memsize\":%zu", memsize);

    dump_append(dc, "}\n");
}

static int
heap_i(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
	if (RBASIC(v)->flags)
	    dump_object(v, data);
    }
    return 0;
}

static void
root_obj_i(const char *category, VALUE obj, void *data)
{
    struct dump_config *dc = (struct dump_config *)data;

    if (dc->root_category != NULL && category != dc->root_category)
	dump_append(dc, "]}\n");
    if (dc->root_category == NULL || category != dc->root_category)
	dump_append(dc, "{\"type\":\"ROOT\", \"root\":\"%s\", \"references\":[\"%p\"", category, (void *)obj);
    else
	dump_append(dc, ", \"%p\"", (void *)obj);

    dc->root_category = category;
    dc->roots++;
}

#ifndef HAVE_MKSTEMP
#define dump_output(dc, opts, output, filename) dump_output(dc, opts, output)
#endif
static VALUE
dump_output(struct dump_config *dc, VALUE opts, VALUE output, char *filename)
{
    if (RTEST(opts))
	output = rb_hash_aref(opts, sym_output);

    if (output == sym_stdout) {
	dc->stream = stdout;
	dc->string = Qnil;
    }
    else if (output == sym_file) {
#ifdef HAVE_MKSTEMP
	int fd = mkstemp(filename);
	dc->string = rb_filesystem_str_new_cstr(filename);
	if (fd == -1) rb_sys_fail_path(dc->string);
	dc->stream = fdopen(fd, "w");
#else
	rb_raise(rb_eArgError, "output to temprary file is not supported");
#endif
    }
    else if (output == sym_string) {
	dc->string = rb_str_new_cstr("");
    }
    else {
	rb_raise(rb_eArgError, "wrong output option: %"PRIsVALUE, output);
    }
    return output;
}

static VALUE
dump_result(struct dump_config *dc, VALUE output)
{
    if (output == sym_string) {
	return dc->string;
    }
    else if (output == sym_file) {
	fclose(dc->stream);
	return dc->string;
    }
    else {
	return Qnil;
    }
}

/*
 *  call-seq:
 *    ObjectSpace.dump(obj[, output: :string]) # => "{ ... }"
 *    ObjectSpace.dump(obj, output: :file) # => "/tmp/rubyobj000000"
 *    ObjectSpace.dump(obj, output: :stdout) # => nil
 *
 *  Dump the contents of a ruby object as JSON.
 *
 *  This method is only expected to work with C Ruby.
 *  This is an experimental method and is subject to change.
 *  In particular, the function signature and output format are
 *  not guaranteed to be compatible in future versions of ruby.
 */

static VALUE
objspace_dump(int argc, VALUE *argv, VALUE os)
{
#ifdef HAVE_MKSTEMP
    char filename[] = "/tmp/rubyobjXXXXXX";
#endif
    VALUE obj = Qnil, opts = Qnil, output;
    struct dump_config dc = {0,};

    rb_scan_args(argc, argv, "1:", &obj, &opts);

    output = dump_output(&dc, opts, sym_string, filename);

    dump_object(obj, &dc);

    return dump_result(&dc, output);
}

/*
 *  call-seq:
 *    ObjectSpace.dump_all([output: :file]) # => "/tmp/rubyheap000000"
 *    ObjectSpace.dump_all(output: :stdout) # => nil
 *    ObjectSpace.dump_all(output: :string) # => "{...}\n{...}\n..."
 *
 *  Dump the contents of the ruby heap as JSON.
 *
 *  This method is only expected to work with C Ruby.
 *  This is an experimental method and is subject to change.
 *  In particular, the function signature and output format are
 *  not guaranteed to be compatible in future versions of ruby.
 */

static VALUE
objspace_dump_all(int argc, VALUE *argv, VALUE os)
{
#ifdef HAVE_MKSTEMP
    char filename[] = "/tmp/rubyheapXXXXXX";
#endif
    VALUE opts = Qnil, output;
    struct dump_config dc = {0,};

    rb_scan_args(argc, argv, "0:", &opts);

    output = dump_output(&dc, opts, sym_file, filename);

    /* dump roots */
    rb_objspace_reachable_objects_from_root(root_obj_i, &dc);
    if (dc.roots) dump_append(&dc, "]}\n");

    /* dump all objects */
    rb_objspace_each_objects(heap_i, &dc);

    return dump_result(&dc, output);
}

void
Init_objspace_dump(VALUE rb_mObjSpace)
{
#if 0
    rb_mObjSpace = rb_define_module("ObjectSpace"); /* let rdoc know */
#endif

    rb_define_module_function(rb_mObjSpace, "dump", objspace_dump, -1);
    rb_define_module_function(rb_mObjSpace, "dump_all", objspace_dump_all, -1);

    sym_output = ID2SYM(rb_intern("output"));
    sym_stdout = ID2SYM(rb_intern("stdout"));
    sym_string = ID2SYM(rb_intern("string"));
    sym_file   = ID2SYM(rb_intern("file"));
}
