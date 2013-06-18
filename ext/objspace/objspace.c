/**********************************************************************

  objspace.c - ObjectSpace extender for MRI.

  $Author$
  created at: Wed Jun 17 07:39:17 2009

  NOTE: This extension library is not expected to exist except C Ruby.

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include <ruby/ruby.h>
#include <ruby/st.h>
#include <ruby/io.h>
#include <ruby/re.h>
#include "node.h"
#include "gc.h"
#include "regint.h"
#include "internal.h"

size_t rb_str_memsize(VALUE);
size_t rb_ary_memsize(VALUE);
size_t rb_io_memsize(const rb_io_t *);
size_t rb_generic_ivar_memsize(VALUE);
size_t rb_objspace_data_type_memsize(VALUE obj);

static size_t
memsize_of(VALUE obj)
{
    size_t size = 0;

    if (SPECIAL_CONST_P(obj)) {
	return 0;
    }

    if (FL_TEST(obj, FL_EXIVAR)) {
	size += rb_generic_ivar_memsize(obj);
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
	if (!(RBASIC(obj)->flags & ROBJECT_EMBED) &&
	    ROBJECT(obj)->as.heap.ivptr) {
	    size += ROBJECT(obj)->as.heap.numiv * sizeof(VALUE);
	}
	break;
      case T_MODULE:
      case T_CLASS:
	if (RCLASS_M_TBL(obj)) {
	    size += st_memsize(RCLASS_M_TBL(obj));
	}
	if (RCLASS_IV_TBL(obj)) {
	    size += st_memsize(RCLASS_IV_TBL(obj));
	}
	if (RCLASS_IV_INDEX_TBL(obj)) {
	    size += st_memsize(RCLASS_IV_INDEX_TBL(obj));
	}
	if (RCLASS(obj)->ptr->iv_tbl) {
	    size += st_memsize(RCLASS(obj)->ptr->iv_tbl);
	}
	if (RCLASS(obj)->ptr->const_tbl) {
	    size += st_memsize(RCLASS(obj)->ptr->const_tbl);
	}
	size += sizeof(rb_classext_t);
	break;
      case T_STRING:
	size += rb_str_memsize(obj);
	break;
      case T_ARRAY:
	size += rb_ary_memsize(obj);
	break;
      case T_HASH:
	if (RHASH(obj)->ntbl) {
	    size += st_memsize(RHASH(obj)->ntbl);
	}
	break;
      case T_REGEXP:
	if (RREGEXP(obj)->ptr) {
	    size += onig_memsize(RREGEXP(obj)->ptr);
	}
	break;
      case T_DATA:
	size += rb_objspace_data_type_memsize(obj);
	break;
      case T_MATCH:
	if (RMATCH(obj)->rmatch) {
            struct rmatch *rm = RMATCH(obj)->rmatch;
	    size += onig_region_memsize(&rm->regs);
	    size += sizeof(struct rmatch_offset) * rm->char_offset_num_allocated;
	    size += sizeof(struct rmatch);
	}
	break;
      case T_FILE:
	if (RFILE(obj)->fptr) {
	    size += rb_io_memsize(RFILE(obj)->fptr);
	}
	break;
      case T_RATIONAL:
      case T_COMPLEX:
	break;
      case T_ICLASS:
	/* iClass shares table with the module */
	break;

      case T_FLOAT:
	break;

      case T_BIGNUM:
	if (!(RBASIC(obj)->flags & RBIGNUM_EMBED_FLAG) && RBIGNUM_DIGITS(obj)) {
	    size += RBIGNUM_LEN(obj) * sizeof(BDIGIT);
	}
	break;
      case T_NODE:
	switch (nd_type(obj)) {
	  case NODE_SCOPE:
	    if (RNODE(obj)->u1.tbl) {
		/* TODO: xfree(RANY(obj)->as.node.u1.tbl); */
	    }
	    break;
	  case NODE_ALLOCA:
	    /* TODO: xfree(RANY(obj)->as.node.u1.node); */
	    ;
	}
	break;			/* no need to free iv_tbl */

      case T_STRUCT:
	if ((RBASIC(obj)->flags & RSTRUCT_EMBED_LEN_MASK) == 0 &&
	    RSTRUCT(obj)->as.heap.ptr) {
	    size += sizeof(VALUE) * RSTRUCT_LEN(obj);
	}
	break;

      case T_ZOMBIE:
	break;

      default:
	rb_bug("objspace/memsize_of(): unknown data type 0x%x(%p)",
	       BUILTIN_TYPE(obj), (void*)obj);
    }

    return size;
}

/*
 *  call-seq:
 *    ObjectSpace.memsize_of(obj) -> Integer
 *
 *  Return consuming memory size of obj.
 *
 *  Note that the return size is incomplete.  You need to deal with
 *  this information as only a *HINT*.  Especially, the size of
 *  T_DATA may not be correct.
 *
 *  This method is not expected to work except C Ruby.
 */

static VALUE
memsize_of_m(VALUE self, VALUE obj)
{
    return SIZET2NUM(memsize_of(obj));
}

struct total_data {
    size_t total;
    VALUE klass;
};

static int
total_i(void *vstart, void *vend, size_t stride, void *ptr)
{
    VALUE v;
    struct total_data *data = (struct total_data *)ptr;

    for (v = (VALUE)vstart; v != (VALUE)vend; v += stride) {
	if (RBASIC(v)->flags) {
	    switch (BUILTIN_TYPE(v)) {
	      case T_NONE:
	      case T_ICLASS:
	      case T_NODE:
	      case T_ZOMBIE:
		continue;
	      case T_CLASS:
		if (FL_TEST(v, FL_SINGLETON))
		  continue;
	      default:
		if (data->klass == 0 || rb_obj_is_kind_of(v, data->klass)) {
		    data->total += memsize_of(v);
		}
	    }
	}
    }

    return 0;
}

/*
 *  call-seq:
 *    ObjectSpace.memsize_of_all([klass]) -> Integer
 *
 *  Return consuming memory size of all living objects.
 *  If klass (should be Class object) is given, return the total
 *  memory size of instances of the given class.
 *
 *  Note that the returned size is incomplete.  You need to deal with
 *  this information as only a *HINT*.  Especially, the size of
 *  T_DATA may not be correct.
 *
 *  Note that this method does *NOT* return total malloc'ed memory size.
 *
 *  This method can be defined by the following Ruby code:
 *
 *  def memsize_of_all klass = false
 *    total = 0
 *    ObjectSpace.each_object{|e|
 *      total += ObjectSpace.memsize_of(e) if klass == false || e.kind_of?(klass)
 *    }
 *    total
 *  end
 *
 *  This method is not expected to work except C Ruby.
 */

static VALUE
memsize_of_all_m(int argc, VALUE *argv, VALUE self)
{
    struct total_data data = {0, 0};

    if (argc > 0) {
	rb_scan_args(argc, argv, "01", &data.klass);
    }

    rb_objspace_each_objects(total_i, &data);
    return SIZET2NUM(data.total);
}

static int
set_zero_i(st_data_t key, st_data_t val, st_data_t arg)
{
    VALUE k = (VALUE)key;
    VALUE hash = (VALUE)arg;
    rb_hash_aset(hash, k, INT2FIX(0));
    return ST_CONTINUE;
}

static int
cos_i(void *vstart, void *vend, size_t stride, void *data)
{
    size_t *counts = (size_t *)data;
    VALUE v = (VALUE)vstart;

    for (;v != (VALUE)vend; v += stride) {
	if (RBASIC(v)->flags) {
	    counts[BUILTIN_TYPE(v)] += memsize_of(v);
	}
    }
    return 0;
}

static VALUE
type2sym(enum ruby_value_type i)
{
    VALUE type;
    switch (i) {
#define CASE_TYPE(t) case t: type = ID2SYM(rb_intern(#t)); break;
	CASE_TYPE(T_NONE);
	CASE_TYPE(T_OBJECT);
	CASE_TYPE(T_CLASS);
	CASE_TYPE(T_MODULE);
	CASE_TYPE(T_FLOAT);
	CASE_TYPE(T_STRING);
	CASE_TYPE(T_REGEXP);
	CASE_TYPE(T_ARRAY);
	CASE_TYPE(T_HASH);
	CASE_TYPE(T_STRUCT);
	CASE_TYPE(T_BIGNUM);
	CASE_TYPE(T_FILE);
	CASE_TYPE(T_DATA);
	CASE_TYPE(T_MATCH);
	CASE_TYPE(T_COMPLEX);
	CASE_TYPE(T_RATIONAL);
	CASE_TYPE(T_NIL);
	CASE_TYPE(T_TRUE);
	CASE_TYPE(T_FALSE);
	CASE_TYPE(T_SYMBOL);
	CASE_TYPE(T_FIXNUM);
	CASE_TYPE(T_UNDEF);
	CASE_TYPE(T_NODE);
	CASE_TYPE(T_ICLASS);
	CASE_TYPE(T_ZOMBIE);
#undef CASE_TYPE
      default: rb_bug("type2sym: unknown type (%d)", i);
    }
    return type;
}

/*
 *  call-seq:
 *    ObjectSpace.count_objects_size([result_hash]) -> hash
 *
 *  Counts objects size (in bytes) for each type.
 *
 *  Note that this information is incomplete.  You need to deal with
 *  this information as only a *HINT*.  Especially, total size of
 *  T_DATA may not right size.
 *
 *  It returns a hash as:
 *    {:TOTAL=>1461154, :T_CLASS=>158280, :T_MODULE=>20672, :T_STRING=>527249, ...}
 *
 *  If the optional argument, result_hash, is given,
 *  it is overwritten and returned.
 *  This is intended to avoid probe effect.
 *
 *  The contents of the returned hash is implementation defined.
 *  It may be changed in future.
 *
 *  This method is not expected to work except C Ruby.
 */

static VALUE
count_objects_size(int argc, VALUE *argv, VALUE os)
{
    size_t counts[T_MASK+1];
    size_t total = 0;
    enum ruby_value_type i;
    VALUE hash;

    if (rb_scan_args(argc, argv, "01", &hash) == 1) {
        if (!RB_TYPE_P(hash, T_HASH))
            rb_raise(rb_eTypeError, "non-hash given");
    }

    for (i = 0; i <= T_MASK; i++) {
	counts[i] = 0;
    }

    rb_objspace_each_objects(cos_i, &counts[0]);

    if (hash == Qnil) {
        hash = rb_hash_new();
    }
    else if (!RHASH_EMPTY_P(hash)) {
        st_foreach(RHASH_TBL(hash), set_zero_i, hash);
    }

    for (i = 0; i <= T_MASK; i++) {
	if (counts[i]) {
	    VALUE type = type2sym(i);
	    total += counts[i];
	    rb_hash_aset(hash, type, SIZET2NUM(counts[i]));
	}
    }
    rb_hash_aset(hash, ID2SYM(rb_intern("TOTAL")), SIZET2NUM(total));
    return hash;
}

static int
cn_i(void *vstart, void *vend, size_t stride, void *n)
{
    size_t *nodes = (size_t *)n;
    VALUE v = (VALUE)vstart;

    for (; v != (VALUE)vend; v += stride) {
	if (RBASIC(v)->flags && BUILTIN_TYPE(v) == T_NODE) {
	    size_t s = nd_type((NODE *)v);
	    nodes[s]++;
	}
    }

    return 0;
}

/*
 *  call-seq:
 *     ObjectSpace.count_nodes([result_hash]) -> hash
 *
 *  Counts nodes for each node type.
 *
 *  This method is not for ordinary Ruby programmers, but for MRI developers
 *  who have interest in MRI performance and memory usage.
 *
 *  It returns a hash as:
 *  {:NODE_METHOD=>2027, :NODE_FBODY=>1927, :NODE_CFUNC=>1798, ...}
 *
 *  If the optional argument, result_hash, is given,
 *  it is overwritten and returned.
 *  This is intended to avoid probe effect.
 *
 *  The contents of the returned hash is implementation defined.
 *  It may be changed in future.
 *
 *  This method is not expected to work except C Ruby.
 */

static VALUE
count_nodes(int argc, VALUE *argv, VALUE os)
{
    size_t nodes[NODE_LAST+1];
    size_t i;
    VALUE hash;

    if (rb_scan_args(argc, argv, "01", &hash) == 1) {
        if (!RB_TYPE_P(hash, T_HASH))
            rb_raise(rb_eTypeError, "non-hash given");
    }

    for (i = 0; i <= NODE_LAST; i++) {
	nodes[i] = 0;
    }

    rb_objspace_each_objects(cn_i, &nodes[0]);

    if (hash == Qnil) {
        hash = rb_hash_new();
    }
    else if (!RHASH_EMPTY_P(hash)) {
        st_foreach(RHASH_TBL(hash), set_zero_i, hash);
    }

    for (i=0; i<NODE_LAST; i++) {
	if (nodes[i] != 0) {
	    VALUE node;
	    switch (i) {
#define COUNT_NODE(n) case n: node = ID2SYM(rb_intern(#n)); break;
		COUNT_NODE(NODE_SCOPE);
		COUNT_NODE(NODE_BLOCK);
		COUNT_NODE(NODE_IF);
		COUNT_NODE(NODE_CASE);
		COUNT_NODE(NODE_WHEN);
		COUNT_NODE(NODE_OPT_N);
		COUNT_NODE(NODE_WHILE);
		COUNT_NODE(NODE_UNTIL);
		COUNT_NODE(NODE_ITER);
		COUNT_NODE(NODE_FOR);
		COUNT_NODE(NODE_BREAK);
		COUNT_NODE(NODE_NEXT);
		COUNT_NODE(NODE_REDO);
		COUNT_NODE(NODE_RETRY);
		COUNT_NODE(NODE_BEGIN);
		COUNT_NODE(NODE_RESCUE);
		COUNT_NODE(NODE_RESBODY);
		COUNT_NODE(NODE_ENSURE);
		COUNT_NODE(NODE_AND);
		COUNT_NODE(NODE_OR);
		COUNT_NODE(NODE_MASGN);
		COUNT_NODE(NODE_LASGN);
		COUNT_NODE(NODE_DASGN);
		COUNT_NODE(NODE_DASGN_CURR);
		COUNT_NODE(NODE_GASGN);
		COUNT_NODE(NODE_IASGN);
		COUNT_NODE(NODE_IASGN2);
		COUNT_NODE(NODE_CDECL);
		COUNT_NODE(NODE_CVASGN);
		COUNT_NODE(NODE_CVDECL);
		COUNT_NODE(NODE_OP_ASGN1);
		COUNT_NODE(NODE_OP_ASGN2);
		COUNT_NODE(NODE_OP_ASGN_AND);
		COUNT_NODE(NODE_OP_ASGN_OR);
		COUNT_NODE(NODE_OP_CDECL);
		COUNT_NODE(NODE_CALL);
		COUNT_NODE(NODE_FCALL);
		COUNT_NODE(NODE_VCALL);
		COUNT_NODE(NODE_SUPER);
		COUNT_NODE(NODE_ZSUPER);
		COUNT_NODE(NODE_ARRAY);
		COUNT_NODE(NODE_ZARRAY);
		COUNT_NODE(NODE_VALUES);
		COUNT_NODE(NODE_HASH);
		COUNT_NODE(NODE_RETURN);
		COUNT_NODE(NODE_YIELD);
		COUNT_NODE(NODE_LVAR);
		COUNT_NODE(NODE_DVAR);
		COUNT_NODE(NODE_GVAR);
		COUNT_NODE(NODE_IVAR);
		COUNT_NODE(NODE_CONST);
		COUNT_NODE(NODE_CVAR);
		COUNT_NODE(NODE_NTH_REF);
		COUNT_NODE(NODE_BACK_REF);
		COUNT_NODE(NODE_MATCH);
		COUNT_NODE(NODE_MATCH2);
		COUNT_NODE(NODE_MATCH3);
		COUNT_NODE(NODE_LIT);
		COUNT_NODE(NODE_STR);
		COUNT_NODE(NODE_DSTR);
		COUNT_NODE(NODE_XSTR);
		COUNT_NODE(NODE_DXSTR);
		COUNT_NODE(NODE_EVSTR);
		COUNT_NODE(NODE_DREGX);
		COUNT_NODE(NODE_DREGX_ONCE);
		COUNT_NODE(NODE_ARGS);
		COUNT_NODE(NODE_ARGS_AUX);
		COUNT_NODE(NODE_OPT_ARG);
		COUNT_NODE(NODE_KW_ARG);
		COUNT_NODE(NODE_POSTARG);
		COUNT_NODE(NODE_ARGSCAT);
		COUNT_NODE(NODE_ARGSPUSH);
		COUNT_NODE(NODE_SPLAT);
		COUNT_NODE(NODE_TO_ARY);
		COUNT_NODE(NODE_BLOCK_ARG);
		COUNT_NODE(NODE_BLOCK_PASS);
		COUNT_NODE(NODE_DEFN);
		COUNT_NODE(NODE_DEFS);
		COUNT_NODE(NODE_ALIAS);
		COUNT_NODE(NODE_VALIAS);
		COUNT_NODE(NODE_UNDEF);
		COUNT_NODE(NODE_CLASS);
		COUNT_NODE(NODE_MODULE);
		COUNT_NODE(NODE_SCLASS);
		COUNT_NODE(NODE_COLON2);
		COUNT_NODE(NODE_COLON3);
		COUNT_NODE(NODE_CREF);
		COUNT_NODE(NODE_DOT2);
		COUNT_NODE(NODE_DOT3);
		COUNT_NODE(NODE_FLIP2);
		COUNT_NODE(NODE_FLIP3);
		COUNT_NODE(NODE_SELF);
		COUNT_NODE(NODE_NIL);
		COUNT_NODE(NODE_TRUE);
		COUNT_NODE(NODE_FALSE);
		COUNT_NODE(NODE_ERRINFO);
		COUNT_NODE(NODE_DEFINED);
		COUNT_NODE(NODE_POSTEXE);
		COUNT_NODE(NODE_ALLOCA);
		COUNT_NODE(NODE_BMETHOD);
		COUNT_NODE(NODE_MEMO);
		COUNT_NODE(NODE_IFUNC);
		COUNT_NODE(NODE_DSYM);
		COUNT_NODE(NODE_ATTRASGN);
		COUNT_NODE(NODE_PRELUDE);
		COUNT_NODE(NODE_LAMBDA);
#undef COUNT_NODE
	      default: node = INT2FIX(i);
	    }
	    rb_hash_aset(hash, node, SIZET2NUM(nodes[i]));
	}
    }
    return hash;
}

static int
cto_i(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE hash = (VALUE)data;
    VALUE v = (VALUE)vstart;

    for (; v != (VALUE)vend; v += stride) {
	if (RBASIC(v)->flags && BUILTIN_TYPE(v) == T_DATA) {
	    VALUE counter;
	    VALUE key = RBASIC(v)->klass;

	    if (key == 0) {
		const char *name = rb_objspace_data_type_name(v);
		if (name == 0) name = "unknown";
		key = ID2SYM(rb_intern(name));
	    }

	    counter = rb_hash_aref(hash, key);
	    if (NIL_P(counter)) {
		counter = INT2FIX(1);
	    }
	    else {
		counter = INT2FIX(FIX2INT(counter) + 1);
	    }

	    rb_hash_aset(hash, key, counter);
	}
    }

    return 0;
}

/*
 *  call-seq:
 *     ObjectSpace.count_tdata_objects([result_hash]) -> hash
 *
 *  Counts objects for each T_DATA type.
 *
 *  This method is not for ordinary Ruby programmers, but for MRI developers
 *  who interest on MRI performance.
 *
 *  It returns a hash as:
 *  {RubyVM::InstructionSequence=>504, :parser=>5, :barrier=>6,
 *   :mutex=>6, Proc=>60, RubyVM::Env=>57, Mutex=>1, Encoding=>99,
 *   ThreadGroup=>1, Binding=>1, Thread=>1, RubyVM=>1, :iseq=>1,
 *   Random=>1, ARGF.class=>1, Data=>1, :autoload=>3, Time=>2}
 *  # T_DATA objects existing at startup on r32276.
 *
 *  If the optional argument, result_hash, is given,
 *  it is overwritten and returned.
 *  This is intended to avoid probe effect.
 *
 *  The contents of the returned hash is implementation defined.
 *  It may be changed in future.
 *
 *  In this version, keys are Class object or Symbol object.
 *  If object is kind of normal (accessible) object, the key is Class object.
 *  If object is not a kind of normal (internal) object, the key is symbol
 *  name, registered by rb_data_type_struct.
 *
 *  This method is not expected to work except C Ruby.
 */

static VALUE
count_tdata_objects(int argc, VALUE *argv, VALUE self)
{
    VALUE hash;

    if (rb_scan_args(argc, argv, "01", &hash) == 1) {
        if (!RB_TYPE_P(hash, T_HASH))
            rb_raise(rb_eTypeError, "non-hash given");
    }

    if (hash == Qnil) {
        hash = rb_hash_new();
    }
    else if (!RHASH_EMPTY_P(hash)) {
        st_foreach(RHASH_TBL(hash), set_zero_i, hash);
    }

    rb_objspace_each_objects(cto_i, (void *)hash);

    return hash;
}

static void
iow_mark(void *ptr)
{
    rb_gc_mark((VALUE)ptr);
}

static size_t
iow_size(const void *ptr)
{
    VALUE obj = (VALUE)ptr;
    return memsize_of(obj);
}

static const rb_data_type_t iow_data_type = {
    "ObjectSpace::InternalObjectWrapper",
    {iow_mark, 0, iow_size,},
};

static VALUE rb_mInternalObjectWrapper;

static VALUE
iow_newobj(VALUE obj)
{
    return rb_data_typed_object_alloc(rb_mInternalObjectWrapper, (void *)obj, &iow_data_type);
}

/* Returns the type of the internal object. */
static VALUE
iow_type(VALUE self)
{
    VALUE obj = (VALUE)DATA_PTR(self);
    return type2sym(BUILTIN_TYPE(obj));
}

/* See Object#inspect. */
static VALUE
iow_inspect(VALUE self)
{
    VALUE obj = (VALUE)DATA_PTR(self);
    VALUE type = type2sym(BUILTIN_TYPE(obj));

    return rb_sprintf("#<InternalObject:%p %s>", (void *)obj, rb_id2name(SYM2ID(type)));
}

/* Returns the Object#object_id of the internal object. */
static VALUE
iow_internal_object_id(VALUE self)
{
    VALUE obj = (VALUE)DATA_PTR(self);
    return rb_obj_id(obj);
}

struct rof_data {
    st_table *refs;
    VALUE internals;
};

static void
reachable_object_from_i(VALUE obj, void *data_ptr)
{
    struct rof_data *data = (struct rof_data *)data_ptr;
    VALUE key = obj;
    VALUE val = obj;

    if (rb_objspace_markable_object_p(obj)) {
	if (rb_objspace_internal_object_p(obj)) {
	    val = iow_newobj(obj);
	    rb_ary_push(data->internals, val);
	}
	st_insert(data->refs, key, val);
    }
}

static int
collect_values(st_data_t key, st_data_t value, st_data_t data)
{
    VALUE ary = (VALUE)data;
    rb_ary_push(ary, (VALUE)value);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     ObjectSpace.reachable_objects_from(obj) -> array or nil
 *
 *  [MRI specific feature] Return all reachable objects from `obj'.
 *
 *  This method returns all reachable objects from `obj'.
 *  If `obj' has two or more references to the same object `x',
 *  then returned array only includes one `x' object.
 *  If `obj' is a non-markable (non-heap management) object such as
 *  true, false, nil, symbols and Fixnums (and Flonum) then it simply
 *  returns nil.
 *
 *  If `obj' has references to an internal object, then it returns
 *  instances of `ObjectSpace::InternalObjectWrapper' class.
 *  This object contains a reference to an internal object and
 *  you can check the type of internal object with `type' method.
 *
 *  If `obj' is instance of `ObjectSpace::InternalObjectWrapper'
 *  class, then this method returns all reachable object from
 *  an internal object, which is pointed by `obj'.
 *
 *  With this method, you can find memory leaks.
 *
 *  This method is not expected to work except in C Ruby.
 *
 *  Example:
 *    ObjectSpace.reachable_objects_from(['a', 'b', 'c'])
 *    #=> [Array, 'a', 'b', 'c']
 *
 *    ObjectSpace.reachable_objects_from(['a', 'a', 'a'])
 *    #=> [Array, 'a', 'a', 'a'] # all 'a' strings have different object id
 *
 *    ObjectSpace.reachable_objects_from([v = 'a', v, v])
 *    #=> [Array, 'a']
 *
 *    ObjectSpace.reachable_objects_from(1)
 *    #=> nil # 1 is not markable (heap managed) object
 *
 */

static VALUE
reachable_objects_from(VALUE self, VALUE obj)
{
    if (rb_objspace_markable_object_p(obj)) {
	VALUE ret = rb_ary_new();
	struct rof_data data;

	if (rb_typeddata_is_kind_of(obj, &iow_data_type)) {
	    obj = (VALUE)DATA_PTR(obj);
	}

	data.refs = st_init_numtable();
	data.internals = rb_ary_new();

	rb_objspace_reachable_objects_from(obj, reachable_object_from_i, &data);

	st_foreach(data.refs, collect_values, (st_data_t)ret);
	return ret;
    }
    else {
	return Qnil;
    }
}

void Init_object_tracing(VALUE rb_mObjSpace);
void Init_gc_hook(VALUE rb_mObjSpace);

/*
 * Document-module: ObjectSpace
 *
 * == The objspace library
 *
 * The objspace library extends the ObjectSpace module and adds several
 * methods to get internal statistic information about
 * object/memory management.
 *
 * You need to <code>require 'objspace'</code> to use this extension module.
 *
 * Generally, you *SHOULD NOT* use this library if you do not know
 * about the MRI implementation.  Mainly, this library is for (memory)
 * profiler developers and MRI developers who need to know about MRI
 * memory usage.
 */

void
Init_objspace(void)
{
    VALUE rb_mObjSpace;
#if 0
    rb_mObjSpace = rb_define_module("ObjectSpace"); /* let rdoc know */
#endif
    rb_mObjSpace = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));

    rb_define_module_function(rb_mObjSpace, "memsize_of", memsize_of_m, 1);
    rb_define_module_function(rb_mObjSpace, "memsize_of_all", memsize_of_all_m, -1);

    rb_define_module_function(rb_mObjSpace, "count_objects_size", count_objects_size, -1);
    rb_define_module_function(rb_mObjSpace, "count_nodes", count_nodes, -1);
    rb_define_module_function(rb_mObjSpace, "count_tdata_objects", count_tdata_objects, -1);

    rb_define_module_function(rb_mObjSpace, "reachable_objects_from", reachable_objects_from, 1);

    /*
     * This class is used as a return value from
     * ObjectSpace::reachable_objects_from.
     *
     * When ObjectSpace::reachable_objects_from returns an object with
     * references to an internal object, an instance of this class is returned.
     *
     * You can use the #type method to check the type of the internal object.
     */
    rb_mInternalObjectWrapper = rb_define_class_under(rb_mObjSpace, "InternalObjectWrapper", rb_cObject);
    rb_define_method(rb_mInternalObjectWrapper, "type", iow_type, 0);
    rb_define_method(rb_mInternalObjectWrapper, "inspect", iow_inspect, 0);
    rb_define_method(rb_mInternalObjectWrapper, "internal_object_id", iow_internal_object_id, 0);

    Init_object_tracing(rb_mObjSpace);
    Init_gc_hook(rb_mObjSpace);
}
