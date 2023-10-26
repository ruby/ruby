/* -*- C -*-
 * $Id$
 */

#include <stdbool.h>
#include <ruby/ruby.h>
#include <ruby/io.h>

#include <ctype.h>
#include <fiddle.h>

#ifdef HAVE_RUBY_MEMORY_VIEW_H
# include <ruby/memory_view.h>
#endif

#ifdef PRIsVALUE
# define RB_OBJ_CLASSNAME(obj) rb_obj_class(obj)
# define RB_OBJ_STRING(obj) (obj)
#else
# define PRIsVALUE "s"
# define RB_OBJ_CLASSNAME(obj) rb_obj_classname(obj)
# define RB_OBJ_STRING(obj) StringValueCStr(obj)
#endif

VALUE rb_cPointer;

typedef rb_fiddle_freefunc_t freefunc_t;

struct ptr_data {
    void *ptr;
    long size;
    freefunc_t free;
    bool freed;
    VALUE wrap[2];
};

#define RPTR_DATA(obj) ((struct ptr_data *)(DATA_PTR(obj)))

static inline freefunc_t
get_freefunc(VALUE func, volatile VALUE *wrap)
{
    VALUE addrnum;
    if (NIL_P(func)) {
	*wrap = 0;
	return NULL;
    }
    addrnum = rb_Integer(func);
    *wrap = (addrnum != func) ? func : 0;
    return (freefunc_t)(VALUE)NUM2PTR(addrnum);
}

static ID id_to_ptr;

static void
fiddle_ptr_mark(void *ptr)
{
    struct ptr_data *data = ptr;
    if (data->wrap[0]) {
	rb_gc_mark(data->wrap[0]);
    }
    if (data->wrap[1]) {
	rb_gc_mark(data->wrap[1]);
    }
}

static void
fiddle_ptr_free_ptr(void *ptr)
{
    struct ptr_data *data = ptr;
    if (data->ptr && data->free && !data->freed) {
	data->freed = true;
	(*(data->free))(data->ptr);
    }
}

static void
fiddle_ptr_free(void *ptr)
{
    fiddle_ptr_free_ptr(ptr);
    xfree(ptr);
}

static size_t
fiddle_ptr_memsize(const void *ptr)
{
    const struct ptr_data *data = ptr;
    return sizeof(*data) + data->size;
}

static const rb_data_type_t fiddle_ptr_data_type = {
    .wrap_struct_name = "fiddle/pointer",
    .function = {
        .dmark = fiddle_ptr_mark,
        .dfree = fiddle_ptr_free,
        .dsize = fiddle_ptr_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

#ifdef HAVE_RUBY_MEMORY_VIEW_H
static struct ptr_data *
fiddle_ptr_check_memory_view(VALUE obj)
{
    struct ptr_data *data;
    TypedData_Get_Struct(obj, struct ptr_data, &fiddle_ptr_data_type, data);
    if (data->ptr == NULL || data->size == 0) return NULL;
    return data;
}

static bool
fiddle_ptr_memory_view_available_p(VALUE obj)
{
    return fiddle_ptr_check_memory_view(obj) != NULL;
}

static bool
fiddle_ptr_get_memory_view(VALUE obj, rb_memory_view_t *view, int flags)
{
    struct ptr_data *data = fiddle_ptr_check_memory_view(obj);
    rb_memory_view_init_as_byte_array(view, obj, data->ptr, data->size, true);

    return true;
}

static const rb_memory_view_entry_t fiddle_ptr_memory_view_entry = {
    fiddle_ptr_get_memory_view,
    NULL,
    fiddle_ptr_memory_view_available_p
};
#endif

static VALUE
rb_fiddle_ptr_new2(VALUE klass, void *ptr, long size, freefunc_t func, VALUE wrap0, VALUE wrap1)
{
    struct ptr_data *data;
    VALUE val;

    val = TypedData_Make_Struct(klass, struct ptr_data, &fiddle_ptr_data_type, data);
    data->ptr = ptr;
    data->free = func;
    data->freed = false;
    data->size = size;
    RB_OBJ_WRITE(val, &data->wrap[0], wrap0);
    RB_OBJ_WRITE(val, &data->wrap[1], wrap1);

    return val;
}

VALUE
rb_fiddle_ptr_new_wrap(void *ptr, long size, freefunc_t func, VALUE wrap0, VALUE wrap1)
{
    return rb_fiddle_ptr_new2(rb_cPointer, ptr, size, func, wrap0, wrap1);
}

static VALUE
rb_fiddle_ptr_new(void *ptr, long size, freefunc_t func)
{
    return rb_fiddle_ptr_new2(rb_cPointer, ptr, size, func, 0, 0);
}

static VALUE
rb_fiddle_ptr_malloc(VALUE klass, long size, freefunc_t func)
{
    void *ptr;

    ptr = ruby_xmalloc((size_t)size);
    memset(ptr,0,(size_t)size);
    return rb_fiddle_ptr_new2(klass, ptr, size, func, 0, 0);
}

static void *
rb_fiddle_ptr2cptr(VALUE val)
{
    struct ptr_data *data;
    void *ptr;

    if (rb_obj_is_kind_of(val, rb_cPointer)) {
	TypedData_Get_Struct(val, struct ptr_data, &fiddle_ptr_data_type, data);
	ptr = data->ptr;
    }
    else if (val == Qnil) {
	ptr = NULL;
    }
    else{
	rb_raise(rb_eTypeError, "Fiddle::Pointer was expected");
    }

    return ptr;
}

static VALUE
rb_fiddle_ptr_s_allocate(VALUE klass)
{
    VALUE obj;
    struct ptr_data *data;

    obj = TypedData_Make_Struct(klass, struct ptr_data, &fiddle_ptr_data_type, data);
    data->ptr = 0;
    data->size = 0;
    data->free = 0;
    data->freed = false;

    return obj;
}

/*
 * call-seq:
 *    Fiddle::Pointer.new(address)      => fiddle_cptr
 *    new(address, size)		=> fiddle_cptr
 *    new(address, size, freefunc)	=> fiddle_cptr
 *
 * Create a new pointer to +address+ with an optional +size+ and +freefunc+.
 *
 * +freefunc+ will be called when the instance is garbage collected.
 */
static VALUE
rb_fiddle_ptr_initialize(int argc, VALUE argv[], VALUE self)
{
    VALUE ptr, sym, size, wrap = 0, funcwrap = 0;
    struct ptr_data *data;
    void *p = NULL;
    freefunc_t f = NULL;
    long s = 0;

    if (rb_scan_args(argc, argv, "12", &ptr, &size, &sym) >= 1) {
	VALUE addrnum = rb_Integer(ptr);
	if (addrnum != ptr) wrap = ptr;
	p = NUM2PTR(addrnum);
    }
    if (argc >= 2) {
	s = NUM2LONG(size);
    }
    if (argc >= 3) {
	f = get_freefunc(sym, &funcwrap);
    }

    if (p) {
	TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
	if (data->ptr && data->free) {
	    /* Free previous memory. Use of inappropriate initialize may cause SEGV. */
	    (*(data->free))(data->ptr);
	}
	RB_OBJ_WRITE(self, &data->wrap[0], wrap);
	RB_OBJ_WRITE(self, &data->wrap[1], funcwrap);
	data->ptr  = p;
	data->size = s;
	data->free = f;
    }

    return Qnil;
}

static VALUE
rb_fiddle_ptr_call_free(VALUE self);

/*
 * call-seq:
 *    Fiddle::Pointer.malloc(size, freefunc = nil)  => fiddle pointer instance
 *    Fiddle::Pointer.malloc(size, freefunc) { |pointer| ... } => ...
 *
 * == Examples
 *
 *    # Automatically freeing the pointer when the block is exited - recommended
 *    Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE) do |pointer|
 *      ...
 *    end
 *
 *    # Manually freeing but relying on the garbage collector otherwise
 *    pointer = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)
 *    ...
 *    pointer.call_free
 *
 *    # Relying on the garbage collector - may lead to unlimited memory allocated before freeing any, but safe
 *    pointer = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)
 *    ...
 *
 *    # Only manually freeing
 *    pointer = Fiddle::Pointer.malloc(size)
 *    begin
 *      ...
 *    ensure
 *      Fiddle.free pointer
 *    end
 *
 *    # No free function and no call to free - the native memory will leak if the pointer is garbage collected
 *    pointer = Fiddle::Pointer.malloc(size)
 *    ...
 *
 * Allocate +size+ bytes of memory and associate it with an optional
 * +freefunc+.
 *
 * If a block is supplied, the pointer will be yielded to the block instead of
 * being returned, and the return value of the block will be returned. A
 * +freefunc+ must be supplied if a block is.
 *
 * If a +freefunc+ is supplied it will be called once, when the pointer is
 * garbage collected or when the block is left if a block is supplied or
 * when the user calls +call_free+, whichever happens first. +freefunc+ must be
 * an address pointing to a function or an instance of +Fiddle::Function+.
 */
static VALUE
rb_fiddle_ptr_s_malloc(int argc, VALUE argv[], VALUE klass)
{
    VALUE size, sym, obj, wrap = 0;
    long s;
    freefunc_t f;

    switch (rb_scan_args(argc, argv, "11", &size, &sym)) {
      case 1:
	s = NUM2LONG(size);
	f = NULL;
	break;
      case 2:
	s = NUM2LONG(size);
	f = get_freefunc(sym, &wrap);
	break;
      default:
	rb_bug("rb_fiddle_ptr_s_malloc");
    }

    obj = rb_fiddle_ptr_malloc(klass, s,f);
    if (wrap) RB_OBJ_WRITE(obj, &RPTR_DATA(obj)->wrap[1], wrap);

    if (rb_block_given_p()) {
        if (!f) {
            rb_raise(rb_eArgError, "a free function must be supplied to Fiddle::Pointer.malloc when it is called with a block");
        }
        return rb_ensure(rb_yield, obj, rb_fiddle_ptr_call_free, obj);
    } else {
        return obj;
    }
}

/*
 * call-seq: to_i
 *
 * Returns the integer memory location of this pointer.
 */
static VALUE
rb_fiddle_ptr_to_i(VALUE self)
{
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    return PTR2NUM(data->ptr);
}

/*
 * call-seq: to_value
 *
 * Cast this pointer to a ruby object.
 */
static VALUE
rb_fiddle_ptr_to_value(VALUE self)
{
    struct ptr_data *data;
    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    return (VALUE)(data->ptr);
}

/*
 * call-seq: ptr
 *
 * Returns a new Fiddle::Pointer instance that is a dereferenced pointer for
 * this pointer.
 *
 * Analogous to the star operator in C.
 */
static VALUE
rb_fiddle_ptr_ptr(VALUE self)
{
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    return rb_fiddle_ptr_new(*((void**)(data->ptr)),0,0);
}

/*
 * call-seq: ref
 *
 * Returns a new Fiddle::Pointer instance that is a reference pointer for this
 * pointer.
 *
 * Analogous to the ampersand operator in C.
 */
static VALUE
rb_fiddle_ptr_ref(VALUE self)
{
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    return rb_fiddle_ptr_new(&(data->ptr),0,0);
}

/*
 * call-seq: null?
 *
 * Returns +true+ if this is a null pointer.
 */
static VALUE
rb_fiddle_ptr_null_p(VALUE self)
{
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    return data->ptr ? Qfalse : Qtrue;
}

/*
 * call-seq: free=(function)
 *
 * Set the free function for this pointer to +function+ in the given
 * Fiddle::Function.
 */
static VALUE
rb_fiddle_ptr_free_set(VALUE self, VALUE val)
{
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    data->free = get_freefunc(val, &data->wrap[1]);

    return Qnil;
}

/*
 * call-seq: free => Fiddle::Function
 *
 * Get the free function for this pointer.
 *
 * Returns a new instance of Fiddle::Function.
 *
 * See Fiddle::Function.new
 */
static VALUE
rb_fiddle_ptr_free_get(VALUE self)
{
    struct ptr_data *pdata;
    VALUE address;
    VALUE arg_types;
    VALUE ret_type;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, pdata);

    if (!pdata->free)
	return Qnil;

    address = PTR2NUM(pdata->free);
    ret_type = INT2NUM(TYPE_VOID);
    arg_types = rb_ary_new();
    rb_ary_push(arg_types, INT2NUM(TYPE_VOIDP));

    return rb_fiddle_new_function(address, arg_types, ret_type);
}

/*
 * call-seq: call_free => nil
 *
 * Call the free function for this pointer. Calling more than once will do
 * nothing. Does nothing if there is no free function attached.
 */
static VALUE
rb_fiddle_ptr_call_free(VALUE self)
{
    struct ptr_data *pdata;
    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, pdata);
    fiddle_ptr_free_ptr(pdata);
    return Qnil;
}

/*
 * call-seq: freed? => bool
 *
 * Returns if the free function for this pointer has been called.
 */
static VALUE
rb_fiddle_ptr_freed_p(VALUE self)
{
    struct ptr_data *pdata;
    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, pdata);
    return pdata->freed ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *
 *    ptr.to_s        => string
 *    ptr.to_s(len)   => string
 *
 * Returns the pointer contents as a string.
 *
 * When called with no arguments, this method will return the contents until
 * the first NULL byte.
 *
 * When called with +len+, a string of +len+ bytes will be returned.
 *
 * See to_str
 */
static VALUE
rb_fiddle_ptr_to_s(int argc, VALUE argv[], VALUE self)
{
    struct ptr_data *data;
    VALUE arg1, val;
    int len;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    switch (rb_scan_args(argc, argv, "01", &arg1)) {
      case 0:
	val = rb_str_new2((char*)(data->ptr));
	break;
      case 1:
	len = NUM2INT(arg1);
	val = rb_str_new((char*)(data->ptr), len);
	break;
      default:
	rb_bug("rb_fiddle_ptr_to_s");
    }

    return val;
}

/*
 * call-seq:
 *
 *    ptr.to_str        => string
 *    ptr.to_str(len)   => string
 *
 * Returns the pointer contents as a string.
 *
 * When called with no arguments, this method will return the contents with the
 * length of this pointer's +size+.
 *
 * When called with +len+, a string of +len+ bytes will be returned.
 *
 * See to_s
 */
static VALUE
rb_fiddle_ptr_to_str(int argc, VALUE argv[], VALUE self)
{
    struct ptr_data *data;
    VALUE arg1, val;
    int len;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    switch (rb_scan_args(argc, argv, "01", &arg1)) {
      case 0:
	val = rb_str_new((char*)(data->ptr),data->size);
	break;
      case 1:
	len = NUM2INT(arg1);
	val = rb_str_new((char*)(data->ptr), len);
	break;
      default:
	rb_bug("rb_fiddle_ptr_to_str");
    }

    return val;
}

/*
 * call-seq: inspect
 *
 * Returns a string formatted with an easily readable representation of the
 * internal state of the pointer.
 */
static VALUE
rb_fiddle_ptr_inspect(VALUE self)
{
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    return rb_sprintf("#<%"PRIsVALUE":%p ptr=%p size=%ld free=%p>",
		      RB_OBJ_CLASSNAME(self), (void *)data, data->ptr, data->size, (void *)data->free);
}

/*
 *  call-seq:
 *    ptr == other    => true or false
 *    ptr.eql?(other) => true or false
 *
 * Returns true if +other+ wraps the same pointer, otherwise returns
 * false.
 */
static VALUE
rb_fiddle_ptr_eql(VALUE self, VALUE other)
{
    void *ptr1, *ptr2;

    if(!rb_obj_is_kind_of(other, rb_cPointer)) return Qfalse;

    ptr1 = rb_fiddle_ptr2cptr(self);
    ptr2 = rb_fiddle_ptr2cptr(other);

    return ptr1 == ptr2 ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *    ptr <=> other   => -1, 0, 1, or nil
 *
 * Returns -1 if less than, 0 if equal to, 1 if greater than +other+.
 *
 * Returns nil if +ptr+ cannot be compared to +other+.
 */
static VALUE
rb_fiddle_ptr_cmp(VALUE self, VALUE other)
{
    void *ptr1, *ptr2;
    SIGNED_VALUE diff;

    if(!rb_obj_is_kind_of(other, rb_cPointer)) return Qnil;

    ptr1 = rb_fiddle_ptr2cptr(self);
    ptr2 = rb_fiddle_ptr2cptr(other);
    diff = (SIGNED_VALUE)ptr1 - (SIGNED_VALUE)ptr2;
    if (!diff) return INT2FIX(0);
    return diff > 0 ? INT2NUM(1) : INT2NUM(-1);
}

/*
 * call-seq:
 *    ptr + n   => new cptr
 *
 * Returns a new pointer instance that has been advanced +n+ bytes.
 */
static VALUE
rb_fiddle_ptr_plus(VALUE self, VALUE other)
{
    void *ptr;
    long num, size;

    ptr = rb_fiddle_ptr2cptr(self);
    size = RPTR_DATA(self)->size;
    num = NUM2LONG(other);
    return rb_fiddle_ptr_new((char *)ptr + num, size - num, 0);
}

/*
 * call-seq:
 *    ptr - n   => new cptr
 *
 * Returns a new pointer instance that has been moved back +n+ bytes.
 */
static VALUE
rb_fiddle_ptr_minus(VALUE self, VALUE other)
{
    void *ptr;
    long num, size;

    ptr = rb_fiddle_ptr2cptr(self);
    size = RPTR_DATA(self)->size;
    num = NUM2LONG(other);
    return rb_fiddle_ptr_new((char *)ptr - num, size + num, 0);
}

/*
 *  call-seq:
 *     ptr[index]                -> an_integer
 *     ptr[start, length]        -> a_string
 *
 * Returns integer stored at _index_.
 *
 * If _start_ and _length_ are given, a string containing the bytes from
 * _start_ of _length_ will be returned.
 */
static VALUE
rb_fiddle_ptr_aref(int argc, VALUE argv[], VALUE self)
{
    VALUE arg0, arg1;
    VALUE retval = Qnil;
    size_t offset, len;
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    if (!data->ptr) rb_raise(rb_eFiddleDLError, "NULL pointer dereference");
    switch( rb_scan_args(argc, argv, "11", &arg0, &arg1) ){
      case 1:
	offset = NUM2ULONG(arg0);
	retval = INT2NUM(*((char *)data->ptr + offset));
	break;
      case 2:
	offset = NUM2ULONG(arg0);
	len    = NUM2ULONG(arg1);
	retval = rb_str_new((char *)data->ptr + offset, len);
	break;
      default:
	rb_bug("rb_fiddle_ptr_aref()");
    }
    return retval;
}

/*
 *  call-seq:
 *     ptr[index]         = int                    ->  int
 *     ptr[start, length] = string or cptr or addr ->  string or dl_cptr or addr
 *
 * Set the value at +index+ to +int+.
 *
 * Or, set the memory at +start+ until +length+ with the contents of +string+,
 * the memory from +dl_cptr+, or the memory pointed at by the memory address
 * +addr+.
 */
static VALUE
rb_fiddle_ptr_aset(int argc, VALUE argv[], VALUE self)
{
    VALUE arg0, arg1, arg2;
    VALUE retval = Qnil;
    size_t offset, len;
    void *mem;
    struct ptr_data *data;

    TypedData_Get_Struct(self, struct ptr_data, &fiddle_ptr_data_type, data);
    if (!data->ptr) rb_raise(rb_eFiddleDLError, "NULL pointer dereference");
    switch( rb_scan_args(argc, argv, "21", &arg0, &arg1, &arg2) ){
      case 2:
	offset = NUM2ULONG(arg0);
	((char*)data->ptr)[offset] = NUM2UINT(arg1);
	retval = arg1;
	break;
      case 3:
	offset = NUM2ULONG(arg0);
	len    = NUM2ULONG(arg1);
	if (RB_TYPE_P(arg2, T_STRING)) {
	    mem = StringValuePtr(arg2);
	}
	else if( rb_obj_is_kind_of(arg2, rb_cPointer) ){
	    mem = rb_fiddle_ptr2cptr(arg2);
	}
	else{
	    mem    = NUM2PTR(arg2);
	}
	memcpy((char *)data->ptr + offset, mem, len);
	retval = arg2;
	break;
      default:
	rb_bug("rb_fiddle_ptr_aset()");
    }
    return retval;
}

/*
 * call-seq: size=(size)
 *
 * Set the size of this pointer to +size+
 */
static VALUE
rb_fiddle_ptr_size_set(VALUE self, VALUE size)
{
    RPTR_DATA(self)->size = NUM2LONG(size);
    return size;
}

/*
 * call-seq: size
 *
 * Get the size of this pointer.
 */
static VALUE
rb_fiddle_ptr_size_get(VALUE self)
{
    return LONG2NUM(RPTR_DATA(self)->size);
}

/*
 * call-seq:
 *    Fiddle::Pointer[val]         => cptr
 *    to_ptr(val)  => cptr
 *
 * Get the underlying pointer for ruby object +val+ and return it as a
 * Fiddle::Pointer object.
 */
static VALUE
rb_fiddle_ptr_s_to_ptr(VALUE self, VALUE val)
{
    VALUE ptr, wrap = val, vptr;

    if (RTEST(rb_obj_is_kind_of(val, rb_cIO))){
	rb_io_t *fptr;
	FILE *fp;
	GetOpenFile(val, fptr);
	fp = rb_io_stdio_file(fptr);
	ptr = rb_fiddle_ptr_new(fp, 0, NULL);
    }
    else if (RTEST(rb_obj_is_kind_of(val, rb_cString))){
	char *str = StringValuePtr(val);
        wrap = val;
	ptr = rb_fiddle_ptr_new(str, RSTRING_LEN(val), NULL);
    }
    else if ((vptr = rb_check_funcall(val, id_to_ptr, 0, 0)) != Qundef){
	if (rb_obj_is_kind_of(vptr, rb_cPointer)){
	    ptr = vptr;
	    wrap = 0;
	}
	else{
	    rb_raise(rb_eFiddleDLError, "to_ptr should return a Fiddle::Pointer object");
	}
    }
    else{
	VALUE num = rb_Integer(val);
	if (num == val) wrap = 0;
	ptr = rb_fiddle_ptr_new(NUM2PTR(num), 0, NULL);
    }
    if (wrap) RB_OBJ_WRITE(ptr, &RPTR_DATA(ptr)->wrap[0], wrap);
    return ptr;
}

/*
 * call-seq:
 *    Fiddle::Pointer.read(address, len)     => string
 *
 * Or read the memory at address +address+ with length +len+ and return a
 * string with that memory
 */

static VALUE
rb_fiddle_ptr_read_mem(VALUE klass, VALUE address, VALUE len)
{
    return rb_str_new((char *)NUM2PTR(address), NUM2ULONG(len));
}

/*
 * call-seq:
 *    Fiddle::Pointer.write(address, str)
 *
 * Write bytes in +str+ to the location pointed to by +address+.
 */
static VALUE
rb_fiddle_ptr_write_mem(VALUE klass, VALUE addr, VALUE str)
{
    memcpy(NUM2PTR(addr), StringValuePtr(str), RSTRING_LEN(str));
    return str;
}

void
Init_fiddle_pointer(void)
{
#undef rb_intern
    id_to_ptr = rb_intern("to_ptr");

    /* Document-class: Fiddle::Pointer
     *
     * Fiddle::Pointer is a class to handle C pointers
     *
     */
    rb_cPointer = rb_define_class_under(mFiddle, "Pointer", rb_cObject);
    rb_define_alloc_func(rb_cPointer, rb_fiddle_ptr_s_allocate);
    rb_define_singleton_method(rb_cPointer, "malloc", rb_fiddle_ptr_s_malloc, -1);
    rb_define_singleton_method(rb_cPointer, "to_ptr", rb_fiddle_ptr_s_to_ptr, 1);
    rb_define_singleton_method(rb_cPointer, "[]", rb_fiddle_ptr_s_to_ptr, 1);
    rb_define_singleton_method(rb_cPointer, "read", rb_fiddle_ptr_read_mem, 2);
    rb_define_singleton_method(rb_cPointer, "write", rb_fiddle_ptr_write_mem, 2);
    rb_define_method(rb_cPointer, "initialize", rb_fiddle_ptr_initialize, -1);
    rb_define_method(rb_cPointer, "free=", rb_fiddle_ptr_free_set, 1);
    rb_define_method(rb_cPointer, "free",  rb_fiddle_ptr_free_get, 0);
    rb_define_method(rb_cPointer, "call_free",  rb_fiddle_ptr_call_free, 0);
    rb_define_method(rb_cPointer, "freed?",  rb_fiddle_ptr_freed_p, 0);
    rb_define_method(rb_cPointer, "to_i",  rb_fiddle_ptr_to_i, 0);
    rb_define_method(rb_cPointer, "to_int",  rb_fiddle_ptr_to_i, 0);
    rb_define_method(rb_cPointer, "to_value",  rb_fiddle_ptr_to_value, 0);
    rb_define_method(rb_cPointer, "ptr",   rb_fiddle_ptr_ptr, 0);
    rb_define_method(rb_cPointer, "+@", rb_fiddle_ptr_ptr, 0);
    rb_define_method(rb_cPointer, "ref",   rb_fiddle_ptr_ref, 0);
    rb_define_method(rb_cPointer, "-@", rb_fiddle_ptr_ref, 0);
    rb_define_method(rb_cPointer, "null?", rb_fiddle_ptr_null_p, 0);
    rb_define_method(rb_cPointer, "to_s", rb_fiddle_ptr_to_s, -1);
    rb_define_method(rb_cPointer, "to_str", rb_fiddle_ptr_to_str, -1);
    rb_define_method(rb_cPointer, "inspect", rb_fiddle_ptr_inspect, 0);
    rb_define_method(rb_cPointer, "<=>", rb_fiddle_ptr_cmp, 1);
    rb_define_method(rb_cPointer, "==", rb_fiddle_ptr_eql, 1);
    rb_define_method(rb_cPointer, "eql?", rb_fiddle_ptr_eql, 1);
    rb_define_method(rb_cPointer, "+", rb_fiddle_ptr_plus, 1);
    rb_define_method(rb_cPointer, "-", rb_fiddle_ptr_minus, 1);
    rb_define_method(rb_cPointer, "[]", rb_fiddle_ptr_aref, -1);
    rb_define_method(rb_cPointer, "[]=", rb_fiddle_ptr_aset, -1);
    rb_define_method(rb_cPointer, "size", rb_fiddle_ptr_size_get, 0);
    rb_define_method(rb_cPointer, "size=", rb_fiddle_ptr_size_set, 1);

#ifdef HAVE_RUBY_MEMORY_VIEW_H
    rb_memory_view_register(rb_cPointer, &fiddle_ptr_memory_view_entry);
#endif

    /*  Document-const: NULL
     *
     * A NULL pointer
     */
    rb_define_const(mFiddle, "NULL", rb_fiddle_ptr_new(0, 0, 0));
}
