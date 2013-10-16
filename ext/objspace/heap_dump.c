/**********************************************************************

  heap_dump.c - Heap dumping ObjectSpace extender for MRI.

  $Author$
  created at: Sat Oct 11 10:11:00 2013

  NOTE: This extension library is not expected to exist except C Ruby.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/debug.h"
#include "ruby/encoding.h"
#include "node.h"
#include "vm_core.h"
#include "objspace.h"

/* from string.c */
#define STR_NOEMBED FL_USER1
#define STR_SHARED  FL_USER2 /* = ELTS_SHARED */
#define STR_ASSOC   FL_USER3
#define STR_SHARED_P(s) FL_ALL((s), STR_NOEMBED|ELTS_SHARED)
#define STR_ASSOC_P(s)  FL_ALL((s), STR_NOEMBED|STR_ASSOC)
#define STR_NOCAPA  (STR_NOEMBED|ELTS_SHARED|STR_ASSOC)
#define STR_NOCAPA_P(s) (FL_TEST((s),STR_NOEMBED) && FL_ANY((s),ELTS_SHARED|STR_ASSOC))
#define STR_EMBED_P(str) (!FL_TEST((str), STR_NOEMBED))
#define is_ascii_string(str) (rb_enc_str_coderange(str) == ENC_CODERANGE_7BIT)
#define is_broken_string(str) (rb_enc_str_coderange(str) == ENC_CODERANGE_BROKEN)
/* from hash.c */
#define HASH_PROC_DEFAULT FL_USER2

struct heap_dump_config {
    FILE *stream;
    int roots;
    const char *root_category;
    VALUE cur_obj;
    VALUE cur_obj_klass;
    size_t cur_obj_references;
};

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
    struct heap_dump_config *hdc = (struct heap_dump_config *)data;

    if (hdc->cur_obj_klass == ref)
	return;

    if (hdc->cur_obj_references == 0)
	fprintf(hdc->stream, ", \"references\":[\"%p\"", (void *)ref);
    else
	fprintf(hdc->stream, ", \"%p\"", (void *)ref);

    hdc->cur_obj_references++;
}

static void
json_dump_string(FILE *stream, VALUE obj)
{
    int i;
    char c, *value;

    fprintf(stream, "\"");
    for (i = 0, value = RSTRING_PTR(obj); i < RSTRING_LEN(obj); i++) {
	switch ((c = value[i])) {
	    case '\\':
	    case '"':
		fprintf(stream, "\\%c", c);
		break;
	    case '\b':
		fprintf(stream, "\\b");
		break;
	    case '\t':
		fprintf(stream, "\\t");
		break;
	    case '\f':
		fprintf(stream, "\\f");
		break;
	    case '\n':
		fprintf(stream, "\\n");
		break;
	    case '\r':
		fprintf(stream, "\\r");
		break;
	    default:
		fprintf(stream, "%c", c);
	}
    }
    fprintf(stream, "\"");
}

static void
dump_object(VALUE obj, struct heap_dump_config *hdc)
{
    int enc;
    long length;
    size_t memsize;
    struct allocation_info *ainfo;

    hdc->cur_obj = obj;
    hdc->cur_obj_references = 0;
    hdc->cur_obj_klass = BUILTIN_TYPE(obj) == T_NODE ? 0 : RBASIC_CLASS(obj);

    fprintf(hdc->stream, "{\"address\":\"%p\", \"type\":\"%s\"", (void *)obj, obj_type(obj));

    if (hdc->cur_obj_klass)
	fprintf(hdc->stream, ", \"class\":\"%p\"", (void *)hdc->cur_obj_klass);
    if (rb_obj_frozen_p(obj))
	fprintf(hdc->stream, ", \"frozen\":true");

    switch (BUILTIN_TYPE(obj)) {
	case T_NODE:
	    fprintf(hdc->stream, ", \"node_type\":\"%s\"", ruby_node_name(nd_type(obj)));
	    break;

	case T_STRING:
	    if (STR_EMBED_P(obj))
		fprintf(hdc->stream, ", \"embedded\":true");
	    if (STR_ASSOC_P(obj))
		fprintf(hdc->stream, ", \"associated\":true");
	    if (is_broken_string(obj))
		fprintf(hdc->stream, ", \"broken\":true");
	    if (STR_SHARED_P(obj))
		fprintf(hdc->stream, ", \"shared\":true");
	    else {
		fprintf(hdc->stream, ", \"bytesize\":%ld", RSTRING_LEN(obj));
		if (!STR_EMBED_P(obj) && !STR_NOCAPA_P(obj) && rb_str_capacity(obj) != RSTRING_LEN(obj))
		    fprintf(hdc->stream, ", \"capacity\":%ld", rb_str_capacity(obj));

		if (is_ascii_string(obj)) {
		    fprintf(hdc->stream, ", \"value\":");
		    json_dump_string(hdc->stream, obj);
		}
	    }

	    if (!ENCODING_IS_ASCII8BIT(obj))
		fprintf(hdc->stream, ", \"encoding\":\"%s\"", rb_enc_name(rb_enc_from_index(ENCODING_GET(obj))));
	    break;

	case T_HASH:
	    fprintf(hdc->stream, ", \"size\":%ld", RHASH_SIZE(obj));
	    if (FL_TEST(obj, HASH_PROC_DEFAULT))
		fprintf(hdc->stream, ", \"default\":\"%p\"", (void *)RHASH_IFNONE(obj));
	    break;

	case T_ARRAY:
	    fprintf(hdc->stream, ", \"length\":%ld", RARRAY_LEN(obj));
	    if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, ELTS_SHARED))
		fprintf(hdc->stream, ", \"shared\":true");
	    if (RARRAY_LEN(obj) > 0 && FL_TEST(obj, RARRAY_EMBED_FLAG))
		fprintf(hdc->stream, ", \"embedded\":true");
	    break;

	case T_CLASS:
	case T_MODULE:
	    if (hdc->cur_obj_klass)
		fprintf(hdc->stream, ", \"name\":\"%s\"", rb_class2name(obj));
	    break;

	case T_DATA:
	    if (RTYPEDDATA_P(obj))
		fprintf(hdc->stream, ", \"struct\":\"%s\"", RTYPEDDATA_TYPE(obj)->wrap_struct_name);
	    break;

	case T_FLOAT:
	    fprintf(hdc->stream, ", \"value\":\"%g\"", RFLOAT_VALUE(obj));
	    break;

	case T_OBJECT:
	    fprintf(hdc->stream, ", \"ivars\":%ld", ROBJECT_NUMIV(obj));
	    break;

	case T_ZOMBIE:
	    fprintf(hdc->stream, "}\n");
	    return;
    }

    rb_objspace_reachable_objects_from(obj, reachable_object_i, hdc);
    if (hdc->cur_obj_references > 0)
	fprintf(hdc->stream, "]");

    if ((ainfo = objspace_lookup_allocation_info(obj))) {
	fprintf(hdc->stream, ", \"file\":\"%s\", \"line\":%lu", ainfo->path, ainfo->line);
	if (RTEST(ainfo->mid))
	    fprintf(hdc->stream, ", \"method\":\"%s\"", rb_id2name(SYM2ID(ainfo->mid)));
	fprintf(hdc->stream, ", \"generation\":%zu", ainfo->generation);
    }

    if ((memsize = objspace_memsize_of(obj)) > 0)
	fprintf(hdc->stream, ", \"memsize\":%zu", memsize);

    fprintf(hdc->stream, "}\n");
}

static int
heap_i(void *vstart, void *vend, int stride, void *data)
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
    struct heap_dump_config *hdc = (struct heap_dump_config *)data;

    if (hdc->root_category != NULL && category != hdc->root_category)
	fprintf(hdc->stream, "]}\n");
    if (hdc->root_category == NULL || category != hdc->root_category)
	fprintf(hdc->stream, "{\"type\":\"ROOT\", \"root\":\"%s\", \"references\":[\"%p\"", category, (void *)obj);
    else
	fprintf(hdc->stream, ", \"%p\"", (void *)obj);

    hdc->root_category = category;
    hdc->roots++;
}

/*
 *  call-seq:
 *    ObjectSpace.heap_dump([filename]) -> nil
 *
 *  Dump the contents of the ruby heap as JSON.
 *
 *  If the optional argument, filename, is given,
 *  the heap dump is written to filename instead of stdout.
 *
 *  This method is only expected to work with C Ruby.
 */

static VALUE
heap_dump(int argc, VALUE *argv, VALUE os)
{
    VALUE filename = Qnil;
    struct heap_dump_config hdc = {
	.stream = stdout,
	.roots = 0,
	.root_category = NULL
    };

    if (rb_scan_args(argc, argv, "01", &filename) == 1) {
	FilePathStringValue(filename);
	hdc.stream = fopen(RSTRING_PTR(filename), "w");
    }

    /* dump roots */
    rb_objspace_reachable_objects_from_root(root_obj_i, &hdc);
    if (hdc.roots) fprintf(hdc.stream, "]}\n");

    /* dump objects */
    rb_objspace_each_objects(heap_i, &hdc);

    if (hdc.stream != stdout)
	fclose(hdc.stream);

    return Qnil;
}

void
Init_heap_dump(VALUE rb_mObjSpace)
{
#if 0
    rb_mObjSpace = rb_define_module("ObjectSpace"); /* let rdoc know */
#endif

    rb_define_module_function(rb_mObjSpace, "heap_dump", heap_dump, -1);
}
