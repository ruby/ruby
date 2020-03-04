#include <fiddle.h>
#include <ruby/thread.h>

int ruby_thread_has_gvl_p(void); /* from internal.h */

VALUE cFiddleClosure;

typedef struct {
    void * code;
    ffi_closure *pcl;
    ffi_cif cif;
    int argc;
    ffi_type **argv;
} fiddle_closure;

static void
dealloc(void * ptr)
{
    fiddle_closure * cls = (fiddle_closure *)ptr;
    ffi_closure_free(cls->pcl);
    if (cls->argv) xfree(cls->argv);
    xfree(cls);
}

static size_t
closure_memsize(const void * ptr)
{
    fiddle_closure * cls = (fiddle_closure *)ptr;
    size_t size = 0;

    size += sizeof(*cls);
#if !defined(FFI_NO_RAW_API) || !FFI_NO_RAW_API
    size += ffi_raw_size(&cls->cif);
#endif
    size += sizeof(*cls->argv);
    size += sizeof(ffi_closure);

    return size;
}

const rb_data_type_t closure_data_type = {
    "fiddle/closure",
    {0, dealloc, closure_memsize,},
};

struct callback_args {
    ffi_cif *cif;
    void *resp;
    void **args;
    void *ctx;
};

static void *
with_gvl_callback(void *ptr)
{
    struct callback_args *x = ptr;

    VALUE self      = (VALUE)x->ctx;
    VALUE rbargs    = rb_iv_get(self, "@args");
    VALUE ctype     = rb_iv_get(self, "@ctype");
    int argc        = RARRAY_LENINT(rbargs);
    VALUE params    = rb_ary_tmp_new(argc);
    VALUE ret;
    VALUE cPointer;
    int i, type;

    cPointer = rb_const_get(mFiddle, rb_intern("Pointer"));

    for (i = 0; i < argc; i++) {
        type = NUM2INT(RARRAY_AREF(rbargs, i));
        switch (type) {
	  case TYPE_VOID:
	    argc = 0;
	    break;
	  case TYPE_INT:
	    rb_ary_push(params, INT2NUM(*(int *)x->args[i]));
	    break;
	  case -TYPE_INT:
	    rb_ary_push(params, UINT2NUM(*(unsigned int *)x->args[i]));
	    break;
	  case TYPE_VOIDP:
	    rb_ary_push(params,
			rb_funcall(cPointer, rb_intern("[]"), 1,
				   PTR2NUM(*(void **)x->args[i])));
	    break;
	  case TYPE_LONG:
	    rb_ary_push(params, LONG2NUM(*(long *)x->args[i]));
	    break;
	  case -TYPE_LONG:
	    rb_ary_push(params, ULONG2NUM(*(unsigned long *)x->args[i]));
	    break;
	  case TYPE_CHAR:
	    rb_ary_push(params, INT2NUM(*(signed char *)x->args[i]));
	    break;
	  case -TYPE_CHAR:
	    rb_ary_push(params, UINT2NUM(*(unsigned char *)x->args[i]));
	    break;
	  case TYPE_SHORT:
	    rb_ary_push(params, INT2NUM(*(signed short *)x->args[i]));
	    break;
	  case -TYPE_SHORT:
	    rb_ary_push(params, UINT2NUM(*(unsigned short *)x->args[i]));
	    break;
	  case TYPE_DOUBLE:
	    rb_ary_push(params, rb_float_new(*(double *)x->args[i]));
	    break;
	  case TYPE_FLOAT:
	    rb_ary_push(params, rb_float_new(*(float *)x->args[i]));
	    break;
#if HAVE_LONG_LONG
	  case TYPE_LONG_LONG:
	    rb_ary_push(params, LL2NUM(*(LONG_LONG *)x->args[i]));
	    break;
	  case -TYPE_LONG_LONG:
	    rb_ary_push(params, ULL2NUM(*(unsigned LONG_LONG *)x->args[i]));
	    break;
#endif
	  default:
	    rb_raise(rb_eRuntimeError, "closure args: %d", type);
        }
    }

    ret = rb_funcall2(self, rb_intern("call"), argc, RARRAY_CONST_PTR(params));
    RB_GC_GUARD(params);

    type = NUM2INT(ctype);
    switch (type) {
      case TYPE_VOID:
	break;
      case TYPE_LONG:
	*(long *)x->resp = NUM2LONG(ret);
	break;
      case -TYPE_LONG:
	*(unsigned long *)x->resp = NUM2ULONG(ret);
	break;
      case TYPE_CHAR:
      case TYPE_SHORT:
      case TYPE_INT:
	*(ffi_sarg *)x->resp = NUM2INT(ret);
	break;
      case -TYPE_CHAR:
      case -TYPE_SHORT:
      case -TYPE_INT:
	*(ffi_arg *)x->resp = NUM2UINT(ret);
	break;
      case TYPE_VOIDP:
	*(void **)x->resp = NUM2PTR(ret);
	break;
      case TYPE_DOUBLE:
	*(double *)x->resp = NUM2DBL(ret);
	break;
      case TYPE_FLOAT:
	*(float *)x->resp = (float)NUM2DBL(ret);
	break;
#if HAVE_LONG_LONG
      case TYPE_LONG_LONG:
	*(LONG_LONG *)x->resp = NUM2LL(ret);
	break;
      case -TYPE_LONG_LONG:
	*(unsigned LONG_LONG *)x->resp = NUM2ULL(ret);
	break;
#endif
      default:
	rb_raise(rb_eRuntimeError, "closure retval: %d", type);
    }
    return 0;
}

static void
callback(ffi_cif *cif, void *resp, void **args, void *ctx)
{
    struct callback_args x;

    x.cif = cif;
    x.resp = resp;
    x.args = args;
    x.ctx = ctx;

    if (ruby_thread_has_gvl_p()) {
	(void)with_gvl_callback(&x);
    } else {
	(void)rb_thread_call_with_gvl(with_gvl_callback, &x);
    }
}

static VALUE
allocate(VALUE klass)
{
    fiddle_closure * closure;

    VALUE i = TypedData_Make_Struct(klass, fiddle_closure,
	    &closure_data_type, closure);

    closure->pcl = ffi_closure_alloc(sizeof(ffi_closure), &closure->code);

    return i;
}

static VALUE
initialize(int rbargc, VALUE argv[], VALUE self)
{
    VALUE ret;
    VALUE args;
    VALUE abi;
    fiddle_closure * cl;
    ffi_cif * cif;
    ffi_closure *pcl;
    ffi_status result;
    int i, argc;

    if (2 == rb_scan_args(rbargc, argv, "21", &ret, &args, &abi))
	abi = INT2NUM(FFI_DEFAULT_ABI);

    Check_Type(args, T_ARRAY);

    argc = RARRAY_LENINT(args);

    TypedData_Get_Struct(self, fiddle_closure, &closure_data_type, cl);

    cl->argv = (ffi_type **)xcalloc(argc + 1, sizeof(ffi_type *));

    for (i = 0; i < argc; i++) {
        int type = NUM2INT(RARRAY_AREF(args, i));
        cl->argv[i] = INT2FFI_TYPE(type);
    }
    cl->argv[argc] = NULL;

    rb_iv_set(self, "@ctype", ret);
    rb_iv_set(self, "@args", args);

    cif = &cl->cif;
    pcl = cl->pcl;

    result = ffi_prep_cif(cif, NUM2INT(abi), argc,
                INT2FFI_TYPE(NUM2INT(ret)),
		cl->argv);

    if (FFI_OK != result)
	rb_raise(rb_eRuntimeError, "error prepping CIF %d", result);

    result = ffi_prep_closure_loc(pcl, cif, callback,
		(void *)self, cl->code);

    if (FFI_OK != result)
	rb_raise(rb_eRuntimeError, "error prepping closure %d", result);

    return self;
}

static VALUE
to_i(VALUE self)
{
    fiddle_closure * cl;
    void *code;

    TypedData_Get_Struct(self, fiddle_closure, &closure_data_type, cl);

    code = cl->code;

    return PTR2NUM(code);
}

void
Init_fiddle_closure(void)
{
#if 0
    mFiddle = rb_define_module("Fiddle"); /* let rdoc know about mFiddle */
#endif

    /*
     * Document-class: Fiddle::Closure
     *
     * == Description
     *
     * An FFI closure wrapper, for handling callbacks.
     *
     * == Example
     *
     *   closure = Class.new(Fiddle::Closure) {
     *     def call
     *       10
     *     end
     *   }.new(Fiddle::TYPE_INT, [])
     *	    #=> #<#<Class:0x0000000150d308>:0x0000000150d240>
     *   func = Fiddle::Function.new(closure, [], Fiddle::TYPE_INT)
     *	    #=> #<Fiddle::Function:0x00000001516e58>
     *   func.call
     *	    #=> 10
     */
    cFiddleClosure = rb_define_class_under(mFiddle, "Closure", rb_cObject);

    rb_define_alloc_func(cFiddleClosure, allocate);

    /*
     * Document-method: new
     *
     * call-seq: new(ret, args, abi = Fiddle::DEFAULT)
     *
     * Construct a new Closure object.
     *
     * * +ret+ is the C type to be returned
     * * +args+ is an Array of arguments, passed to the callback function
     * * +abi+ is the abi of the closure
     *
     * If there is an error in preparing the ffi_cif or ffi_prep_closure,
     * then a RuntimeError will be raised.
     */
    rb_define_method(cFiddleClosure, "initialize", initialize, -1);

    /*
     * Document-method: to_i
     *
     * Returns the memory address for this closure
     */
    rb_define_method(cFiddleClosure, "to_i", to_i, 0);
}
/* vim: set noet sw=4 sts=4 */
