#include <fiddle.h>
#include <ruby/thread.h>

#include <stdbool.h>

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
    Check_Max_Args_(name, len, "")
#define Check_Max_Args_Long(name, len) \
    Check_Max_Args_(name, len, "l")
#define Check_Max_Args_(name, len, fmt) \
    do { \
        if ((size_t)(len) >= MAX_ARGS) { \
            rb_raise(rb_eTypeError, \
                     "%s is so large " \
                     "that it can cause integer overflow (%"fmt"d)", \
                     (name), (len)); \
        } \
    } while (0)

static void
deallocate(void *p)
{
    ffi_cif *cif = p;
    if (cif->arg_types) xfree(cif->arg_types);
    xfree(cif);
}

static size_t
function_memsize(const void *p)
{
    /* const */ffi_cif *ptr = (ffi_cif *)p;
    size_t size = 0;

    size += sizeof(*ptr);
#if !defined(FFI_NO_RAW_API) || !FFI_NO_RAW_API
    size += ffi_raw_size(ptr);
#endif

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
normalize_argument_types(const char *name,
                         VALUE arg_types,
                         bool *is_variadic)
{
    VALUE normalized_arg_types;
    int i;
    int n_arg_types;
    *is_variadic = false;

    Check_Type(arg_types, T_ARRAY);
    n_arg_types = RARRAY_LENINT(arg_types);
    Check_Max_Args(name, n_arg_types);

    normalized_arg_types = rb_ary_new_capa(n_arg_types);
    for (i = 0; i < n_arg_types; i++) {
        VALUE arg_type = RARRAY_AREF(arg_types, i);
        int c_arg_type = NUM2INT(arg_type);
        if (c_arg_type == TYPE_VARIADIC) {
            if (i != n_arg_types - 1) {
                rb_raise(rb_eArgError,
                         "Fiddle::TYPE_VARIADIC must be the last argument type: "
                         "%"PRIsVALUE,
                         arg_types);
            }
            *is_variadic = true;
            break;
        }
        else {
            (void)INT2FFI_TYPE(c_arg_type); /* raise */
        }
        rb_ary_push(normalized_arg_types, INT2FIX(c_arg_type));
    }

    /* freeze to prevent inconsistency at calling #to_int later */
    OBJ_FREEZE(normalized_arg_types);
    return normalized_arg_types;
}

static VALUE
initialize(int argc, VALUE argv[], VALUE self)
{
    ffi_cif * cif;
    VALUE ptr, arg_types, ret_type, abi, kwds;
    int c_ret_type;
    bool is_variadic = false;
    ffi_abi c_ffi_abi;
    void *cfunc;

    rb_scan_args(argc, argv, "31:", &ptr, &arg_types, &ret_type, &abi, &kwds);
    rb_iv_set(self, "@closure", ptr);

    ptr = rb_Integer(ptr);
    cfunc = NUM2PTR(ptr);
    PTR2NUM(cfunc);
    c_ffi_abi = NIL_P(abi) ? FFI_DEFAULT_ABI : NUM2INT(abi);
    abi = INT2FIX(c_ffi_abi);
    c_ret_type = NUM2INT(ret_type);
    (void)INT2FFI_TYPE(c_ret_type); /* raise */
    ret_type = INT2FIX(c_ret_type);

    arg_types = normalize_argument_types("argument types",
                                         arg_types,
                                         &is_variadic);
#ifndef HAVE_FFI_PREP_CIF_VAR
    if (is_variadic) {
        rb_raise(rb_eNotImpError,
                 "ffi_prep_cif_var() is required in libffi "
                 "for variadic arguments");
    }
#endif

    rb_iv_set(self, "@ptr", ptr);
    rb_iv_set(self, "@argument_types", arg_types);
    rb_iv_set(self, "@return_type", ret_type);
    rb_iv_set(self, "@abi", abi);
    rb_iv_set(self, "@is_variadic", is_variadic ? Qtrue : Qfalse);

    if (!NIL_P(kwds)) rb_hash_foreach(kwds, parse_keyword_arg_i, self);

    TypedData_Get_Struct(self, ffi_cif, &function_data_type, cif);
    cif->arg_types = NULL;

    return self;
}

struct nogvl_ffi_call_args {
    ffi_cif *cif;
    void (*fn)(void);
    void **values;
    fiddle_generic retval;
};

static void *
nogvl_ffi_call(void *ptr)
{
    struct nogvl_ffi_call_args *args = ptr;

    ffi_call(args->cif, args->fn, &args->retval, args->values);

    return NULL;
}

static VALUE
function_call(int argc, VALUE argv[], VALUE self)
{
    struct nogvl_ffi_call_args args = { 0 };
    fiddle_generic *generic_args;
    VALUE cfunc;
    VALUE abi;
    VALUE arg_types;
    VALUE cPointer;
    VALUE is_variadic;
    int n_arg_types;
    int n_fixed_args = 0;
    int n_call_args = 0;
    int i;
    int i_call;
    VALUE converted_args = Qnil;
    VALUE alloc_buffer = 0;

    cfunc    = rb_iv_get(self, "@ptr");
    abi      = rb_iv_get(self, "@abi");
    arg_types = rb_iv_get(self, "@argument_types");
    cPointer = rb_const_get(mFiddle, rb_intern("Pointer"));
    is_variadic = rb_iv_get(self, "@is_variadic");

    n_arg_types = RARRAY_LENINT(arg_types);
    n_fixed_args = n_arg_types;
    if (RTEST(is_variadic)) {
        if (argc < n_arg_types) {
            rb_error_arity(argc, n_arg_types, UNLIMITED_ARGUMENTS);
        }
        if (((argc - n_arg_types) % 2) != 0) {
            rb_raise(rb_eArgError,
                     "variadic arguments must be type and value pairs: "
                     "%"PRIsVALUE,
                     rb_ary_new_from_values(argc, argv));
        }
        n_call_args = n_arg_types + ((argc - n_arg_types) / 2);
    }
    else {
        if (argc != n_arg_types) {
            rb_error_arity(argc, n_arg_types, n_arg_types);
        }
        n_call_args = n_arg_types;
    }
    Check_Max_Args("the number of arguments", n_call_args);

    TypedData_Get_Struct(self, ffi_cif, &function_data_type, args.cif);

    if (is_variadic && args.cif->arg_types) {
        xfree(args.cif->arg_types);
        args.cif->arg_types = NULL;
    }

    if (!args.cif->arg_types) {
        VALUE fixed_arg_types = arg_types;
        VALUE return_type;
        int c_return_type;
        ffi_type *ffi_return_type;
        ffi_type **ffi_arg_types;
        ffi_status result;

        arg_types = rb_ary_dup(fixed_arg_types);
        for (i = n_fixed_args; i < argc; i += 2) {
          VALUE arg_type = argv[i];
          int c_arg_type = NUM2INT(arg_type);
          (void)INT2FFI_TYPE(c_arg_type); /* raise */
          rb_ary_push(arg_types, INT2FIX(c_arg_type));
        }

        return_type = rb_iv_get(self, "@return_type");
        c_return_type = FIX2INT(return_type);
        ffi_return_type = INT2FFI_TYPE(c_return_type);

        ffi_arg_types = xcalloc(n_call_args + 1, sizeof(ffi_type *));
        for (i_call = 0; i_call < n_call_args; i_call++) {
            VALUE arg_type;
            int c_arg_type;
            arg_type = RARRAY_AREF(arg_types, i_call);
            c_arg_type = FIX2INT(arg_type);
            ffi_arg_types[i_call] = INT2FFI_TYPE(c_arg_type);
        }
        ffi_arg_types[i_call] = NULL;

        if (is_variadic) {
#ifdef HAVE_FFI_PREP_CIF_VAR
            result = ffi_prep_cif_var(args.cif,
                                      FIX2INT(abi),
                                      n_fixed_args,
                                      n_call_args,
                                      ffi_return_type,
                                      ffi_arg_types);
#else
            /* This code is never used because ffi_prep_cif_var()
             * availability check is done in #initialize. */
            result = FFI_BAD_TYPEDEF;
#endif
        }
        else {
            result = ffi_prep_cif(args.cif,
                                  FIX2INT(abi),
                                  n_call_args,
                                  ffi_return_type,
                                  ffi_arg_types);
        }
        if (result != FFI_OK) {
            xfree(ffi_arg_types);
            args.cif->arg_types = NULL;
            rb_raise(rb_eRuntimeError, "error creating CIF %d", result);
        }
    }

    generic_args = ALLOCV(alloc_buffer,
                          sizeof(fiddle_generic) * n_call_args +
                          sizeof(void *) * (n_call_args + 1));
    args.values = (void **)((char *)generic_args +
                            sizeof(fiddle_generic) * n_call_args);

    for (i = 0, i_call = 0;
         i < argc && i_call < n_call_args;
         i++, i_call++) {
        VALUE arg_type;
        int c_arg_type;
        VALUE original_src;
        VALUE src;
        arg_type = RARRAY_AREF(arg_types, i_call);
        c_arg_type = FIX2INT(arg_type);
        if (i >= n_fixed_args) {
            i++;
        }
        src = argv[i];

        if (c_arg_type == TYPE_VOIDP) {
            if (NIL_P(src)) {
                src = INT2FIX(0);
            }
            else if (cPointer != CLASS_OF(src)) {
                src = rb_funcall(cPointer, rb_intern("[]"), 1, src);
                if (NIL_P(converted_args)) {
                    converted_args = rb_ary_new();
                }
                rb_ary_push(converted_args, src);
            }
            src = rb_Integer(src);
        }

        original_src = src;
        VALUE2GENERIC(c_arg_type, src, &generic_args[i_call]);
        if (src != original_src) {
            if (NIL_P(converted_args)) {
                converted_args = rb_ary_new();
            }
            rb_ary_push(converted_args, src);
        }
        args.values[i_call] = (void *)&generic_args[i_call];
    }
    args.values[i_call] = NULL;
    args.fn = (void(*)(void))NUM2PTR(cfunc);

    (void)rb_thread_call_without_gvl(nogvl_ffi_call, &args, 0, 0);

    rb_funcall(mFiddle, rb_intern("last_error="), 1, INT2NUM(errno));
#if defined(_WIN32)
    rb_funcall(mFiddle, rb_intern("win32_last_error="), 1, INT2NUM(errno));
#endif

    ALLOCV_END(alloc_buffer);

    return GENERIC2VALUE(rb_iv_get(self, "@return_type"), args.retval);
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
     * Calls the constructed Function, with +args+.
     * Caller must ensure the underlying function is called in a
     * thread-safe manner if running in a multi-threaded process.
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
