#include <fiddle.h>

#ifdef PRIsVALUE
# define RB_OBJ_CLASSNAME(obj) rb_obj_class(obj)
# define RB_OBJ_STRING(obj) (obj)
#else
# define PRIsVALUE "s"
# define RB_OBJ_CLASSNAME(obj) rb_obj_classname(obj)
# define RB_OBJ_STRING(obj) StringValueCStr(obj)
#endif

VALUE cFiddleFunction;

#define MAX_ARGS (SIZE_MAX / (sizeof(void *) + sizeof(fiddle_generic)) - 1)

#define Check_Max_Args(name, len) \
    if ((size_t)(len) < MAX_ARGS) { \
	/* OK */ \
    } \
    else { \
	rb_raise(rb_eTypeError, \
		 name" is so large that it can cause integer overflow (%d)", \
		 (len)); \
    }

static void
deallocate(void *p)
{
    ffi_cif *ptr = p;
    if (ptr->arg_types) xfree(ptr->arg_types);
    xfree(ptr);
}

static size_t
function_memsize(const void *p)
{
    /* const */ffi_cif *ptr = (ffi_cif *)p;
    size_t size = 0;

    if (ptr) {
	size += sizeof(*ptr);
#if !defined(FFI_NO_RAW_API) || !FFI_NO_RAW_API
	size += ffi_raw_size(ptr);
#endif
    }
    return size;
}

const rb_data_type_t function_data_type = {
    "fiddle/function",
    {0, deallocate, function_memsize,},
};

static VALUE
allocate(VALUE klass)
{
    ffi_cif * cif;

    return TypedData_Make_Struct(klass, ffi_cif, &function_data_type, cif);
}

VALUE
rb_fiddle_new_function(VALUE address, VALUE arg_types, VALUE ret_type)
{
    VALUE argv[3];

    argv[0] = address;
    argv[1] = arg_types;
    argv[2] = ret_type;

    return rb_class_new_instance(3, argv, cFiddleFunction);
}

static int
parse_keyword_arg_i(VALUE key, VALUE value, VALUE self)
{
    if (key == ID2SYM(rb_intern("name"))) {
	rb_iv_set(self, "@name", value);
    } else {
	rb_raise(rb_eArgError, "unknown keyword: %"PRIsVALUE,
		 RB_OBJ_STRING(key));
    }
    return ST_CONTINUE;
}

static VALUE
initialize(int argc, VALUE argv[], VALUE self)
{
    ffi_cif * cif;
    ffi_type **arg_types;
    ffi_status result;
    VALUE ptr, args, ret_type, abi, kwds;
    int i;

    rb_scan_args(argc, argv, "31:", &ptr, &args, &ret_type, &abi, &kwds);
    if(NIL_P(abi)) abi = INT2NUM(FFI_DEFAULT_ABI);

    Check_Type(args, T_ARRAY);
    Check_Max_Args("args", RARRAY_LENINT(args));

    rb_iv_set(self, "@ptr", ptr);
    rb_iv_set(self, "@args", args);
    rb_iv_set(self, "@return_type", ret_type);
    rb_iv_set(self, "@abi", abi);

    if (!NIL_P(kwds)) rb_hash_foreach(kwds, parse_keyword_arg_i, self);

    TypedData_Get_Struct(self, ffi_cif, &function_data_type, cif);

    arg_types = xcalloc(RARRAY_LEN(args) + 1, sizeof(ffi_type *));

    for (i = 0; i < RARRAY_LEN(args); i++) {
	int type = NUM2INT(RARRAY_PTR(args)[i]);
	arg_types[i] = INT2FFI_TYPE(type);
    }
    arg_types[RARRAY_LEN(args)] = NULL;

    result = ffi_prep_cif (
	    cif,
	    NUM2INT(abi),
	    RARRAY_LENINT(args),
	    INT2FFI_TYPE(NUM2INT(ret_type)),
	    arg_types);

    if (result)
	rb_raise(rb_eRuntimeError, "error creating CIF %d", result);

    return self;
}

static VALUE
function_call(int argc, VALUE argv[], VALUE self)
{
    ffi_cif * cif;
    fiddle_generic retval;
    fiddle_generic *generic_args;
    void **values;
    VALUE cfunc, types, cPointer;
    int i;
    VALUE alloc_buffer = 0;

    cfunc    = rb_iv_get(self, "@ptr");
    types    = rb_iv_get(self, "@args");
    cPointer = rb_const_get(mFiddle, rb_intern("Pointer"));

    Check_Max_Args("number of arguments", argc);
    if(argc != RARRAY_LENINT(types)) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		argc, RARRAY_LENINT(types));
    }

    TypedData_Get_Struct(self, ffi_cif, &function_data_type, cif);

    if (rb_safe_level() >= 1) {
	for (i = 0; i < argc; i++) {
	    VALUE src = argv[i];
	    if (OBJ_TAINTED(src)) {
		rb_raise(rb_eSecurityError, "tainted parameter not allowed");
	    }
	}
    }

    generic_args = ALLOCV(alloc_buffer,
	(size_t)(argc + 1) * sizeof(void *) + (size_t)argc * sizeof(fiddle_generic));
    values = (void **)((char *)generic_args + (size_t)argc * sizeof(fiddle_generic));

    for (i = 0; i < argc; i++) {
	VALUE type = RARRAY_PTR(types)[i];
	VALUE src = argv[i];

	if(NUM2INT(type) == TYPE_VOIDP) {
	    if(NIL_P(src)) {
		src = INT2FIX(0);
	    } else if(cPointer != CLASS_OF(src)) {
		src = rb_funcall(cPointer, rb_intern("[]"), 1, src);
	    }
	    src = rb_Integer(src);
	}

	VALUE2GENERIC(NUM2INT(type), src, &generic_args[i]);
	values[i] = (void *)&generic_args[i];
    }
    values[argc] = NULL;

    ffi_call(cif, NUM2PTR(rb_Integer(cfunc)), &retval, values);

    rb_funcall(mFiddle, rb_intern("last_error="), 1, INT2NUM(errno));
#if defined(_WIN32)
    rb_funcall(mFiddle, rb_intern("win32_last_error="), 1, INT2NUM(errno));
#endif

    ALLOCV_END(alloc_buffer);

    return GENERIC2VALUE(rb_iv_get(self, "@return_type"), retval);
}

void
Init_fiddle_function(void)
{
    /*
     * Document-class: Fiddle::Function
     *
     * == Description
     *
     * A representation of a C function
     *
     * == Examples
     *
     * === 'strcpy'
     *
     *   @libc = Fiddle.dlopen "/lib/libc.so.6"
     *	    #=> #<Fiddle::Handle:0x00000001d7a8d8>
     *   f = Fiddle::Function.new(
     *     @libc['strcpy'],
     *     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
     *     Fiddle::TYPE_VOIDP)
     *	    #=> #<Fiddle::Function:0x00000001d8ee00>
     *   buff = "000"
     *	    #=> "000"
     *   str = f.call(buff, "123")
     *	    #=> #<Fiddle::Pointer:0x00000001d0c380 ptr=0x000000018a21b8 size=0 free=0x00000000000000>
     *   str.to_s
     *   => "123"
     *
     * === ABI check
     *
     *   @libc = Fiddle.dlopen "/lib/libc.so.6"
     *	    #=> #<Fiddle::Handle:0x00000001d7a8d8>
     *   f = Fiddle::Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)
     *	    #=> #<Fiddle::Function:0x00000001d8ee00>
     *   f.abi == Fiddle::Function::DEFAULT
     *	    #=> true
     */
    cFiddleFunction = rb_define_class_under(mFiddle, "Function", rb_cObject);

    /*
     * Document-const: DEFAULT
     *
     * Default ABI
     *
     */
    rb_define_const(cFiddleFunction, "DEFAULT", INT2NUM(FFI_DEFAULT_ABI));

#ifdef HAVE_CONST_FFI_STDCALL
    /*
     * Document-const: STDCALL
     *
     * FFI implementation of WIN32 stdcall convention
     *
     */
    rb_define_const(cFiddleFunction, "STDCALL", INT2NUM(FFI_STDCALL));
#endif

    rb_define_alloc_func(cFiddleFunction, allocate);

    /*
     * Document-method: call
     *
     * Calls the constructed Function, with +args+
     *
     * For an example see Fiddle::Function
     *
     */
    rb_define_method(cFiddleFunction, "call", function_call, -1);

    /*
     * Document-method: new
     * call-seq: new(ptr, args, ret_type, abi = DEFAULT)
     *
     * Constructs a Function object.
     * * +ptr+ is a referenced function, of a Fiddle::Handle
     * * +args+ is an Array of arguments, passed to the +ptr+ function
     * * +ret_type+ is the return type of the function
     * * +abi+ is the ABI of the function
     *
     */
    rb_define_method(cFiddleFunction, "initialize", initialize, -1);
}
/* vim: set noet sws=4 sw=4: */
