#include <ruby.h>
#include <fiddle.h>

VALUE rb_cHandle;

struct dl_handle {
    void *ptr;
    int  open;
    int  enable_close;
};

#ifdef _WIN32
# ifndef _WIN32_WCE
static void *
w32_coredll(void)
{
    MEMORY_BASIC_INFORMATION m;
    memset(&m, 0, sizeof(m));
    if( !VirtualQuery(_errno, &m, sizeof(m)) ) return NULL;
    return m.AllocationBase;
}
# endif

static int
w32_dlclose(void *ptr)
{
# ifndef _WIN32_WCE
    if( ptr == w32_coredll() ) return 0;
# endif
    if( FreeLibrary((HMODULE)ptr) ) return 0;
    return errno = rb_w32_map_errno(GetLastError());
}
#define dlclose(ptr) w32_dlclose(ptr)
#endif

static void
fiddle_handle_free(void *ptr)
{
    struct dl_handle *fiddle_handle = ptr;
    if( fiddle_handle->ptr && fiddle_handle->open && fiddle_handle->enable_close ){
	dlclose(fiddle_handle->ptr);
    }
    xfree(ptr);
}

static size_t
fiddle_handle_memsize(const void *ptr)
{
    return sizeof(struct dl_handle);
}

static const rb_data_type_t fiddle_handle_data_type = {
    .wrap_struct_name = "fiddle/handle",
    .function = {
        .dmark = 0,
        .dfree = fiddle_handle_free,
        .dsize = fiddle_handle_memsize
    },
    .flags = RUBY_TYPED_WB_PROTECTED,
};

/*
 * call-seq: close
 *
 * Close this handle.
 *
 * Calling close more than once will raise a Fiddle::DLError exception.
 */
static VALUE
rb_fiddle_handle_close(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    if(fiddle_handle->open) {
	int ret = dlclose(fiddle_handle->ptr);
	fiddle_handle->open = 0;

	/* Check dlclose for successful return value */
	if(ret) {
#if defined(HAVE_DLERROR)
	    rb_raise(rb_eFiddleDLError, "%s", dlerror());
#else
	    rb_raise(rb_eFiddleDLError, "could not close handle");
#endif
	}
	return INT2NUM(ret);
    }
    rb_raise(rb_eFiddleDLError, "dlclose() called too many times");

    UNREACHABLE;
}

static VALUE
rb_fiddle_handle_s_allocate(VALUE klass)
{
    VALUE obj;
    struct dl_handle *fiddle_handle;

    obj = TypedData_Make_Struct(rb_cHandle, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    fiddle_handle->ptr  = 0;
    fiddle_handle->open = 0;
    fiddle_handle->enable_close = 0;

    return obj;
}

static VALUE
predefined_fiddle_handle(void *handle)
{
    VALUE obj = rb_fiddle_handle_s_allocate(rb_cHandle);
    struct dl_handle *fiddle_handle = DATA_PTR(obj);

    fiddle_handle->ptr = handle;
    fiddle_handle->open = 1;
    OBJ_FREEZE(obj);
    return obj;
}

/*
 * call-seq:
 *    new(library = nil, flags = Fiddle::RTLD_LAZY | Fiddle::RTLD_GLOBAL)
 *
 * Create a new handler that opens +library+ with +flags+.
 *
 * If no +library+ is specified or +nil+ is given, DEFAULT is used, which is
 * the equivalent to RTLD_DEFAULT. See <code>man 3 dlopen</code> for more.
 *
 *	lib = Fiddle::Handle.new
 *
 * The default is dependent on OS, and provide a handle for all libraries
 * already loaded. For example, in most cases you can use this to access +libc+
 * functions, or ruby functions like +rb_str_new+.
 */
static VALUE
rb_fiddle_handle_initialize(int argc, VALUE argv[], VALUE self)
{
    void *ptr;
    struct dl_handle *fiddle_handle;
    VALUE lib, flag;
    char  *clib;
    int   cflag;
    const char *err;

    switch( rb_scan_args(argc, argv, "02", &lib, &flag) ){
      case 0:
	clib = NULL;
	cflag = RTLD_LAZY | RTLD_GLOBAL;
	break;
      case 1:
	clib = NIL_P(lib) ? NULL : StringValueCStr(lib);
	cflag = RTLD_LAZY | RTLD_GLOBAL;
	break;
      case 2:
	clib = NIL_P(lib) ? NULL : StringValueCStr(lib);
	cflag = NUM2INT(flag);
	break;
      default:
	rb_bug("rb_fiddle_handle_new");
    }

#if defined(_WIN32)
    if( !clib ){
	HANDLE rb_libruby_handle(void);
	ptr = rb_libruby_handle();
    }
    else if( STRCASECMP(clib, "libc") == 0
# ifdef RUBY_COREDLL
	     || STRCASECMP(clib, RUBY_COREDLL) == 0
	     || STRCASECMP(clib, RUBY_COREDLL".dll") == 0
# endif
	){
# ifdef _WIN32_WCE
	ptr = dlopen("coredll.dll", cflag);
# else
	(void)cflag;
	ptr = w32_coredll();
# endif
    }
    else
#endif
	ptr = dlopen(clib, cflag);
#if defined(HAVE_DLERROR)
    if( !ptr && (err = dlerror()) ){
	rb_raise(rb_eFiddleDLError, "%s", err);
    }
#else
    if( !ptr ){
	err = dlerror();
	rb_raise(rb_eFiddleDLError, "%s", err);
    }
#endif
    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    if( fiddle_handle->ptr && fiddle_handle->open && fiddle_handle->enable_close ){
	dlclose(fiddle_handle->ptr);
    }
    fiddle_handle->ptr = ptr;
    fiddle_handle->open = 1;
    fiddle_handle->enable_close = 0;

    if( rb_block_given_p() ){
	rb_ensure(rb_yield, self, rb_fiddle_handle_close, self);
    }

    return Qnil;
}

/*
 * call-seq: enable_close
 *
 * Enable a call to dlclose() when this handle is garbage collected.
 */
static VALUE
rb_fiddle_handle_enable_close(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    fiddle_handle->enable_close = 1;
    return Qnil;
}

/*
 * call-seq: disable_close
 *
 * Disable a call to dlclose() when this handle is garbage collected.
 */
static VALUE
rb_fiddle_handle_disable_close(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    fiddle_handle->enable_close = 0;
    return Qnil;
}

/*
 * call-seq: close_enabled?
 *
 * Returns +true+ if dlclose() will be called when this handle is garbage collected.
 *
 * See man(3) dlclose() for more info.
 */
static VALUE
rb_fiddle_handle_close_enabled_p(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);

    if(fiddle_handle->enable_close) return Qtrue;
    return Qfalse;
}

/*
 * call-seq: to_i
 *
 * Returns the memory address for this handle.
 */
static VALUE
rb_fiddle_handle_to_i(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    return PTR2NUM(fiddle_handle->ptr);
}

/*
 * call-seq: to_ptr
 *
 * Returns the Fiddle::Pointer of this handle.
 */
static VALUE
rb_fiddle_handle_to_ptr(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    return rb_fiddle_ptr_new_wrap(fiddle_handle->ptr, 0, 0, self, 0);
}

static VALUE fiddle_handle_sym(void *handle, VALUE symbol);

/*
 * Document-method: sym
 *
 * call-seq: sym(name)
 *
 * Get the address as an Integer for the function named +name+.
 */
static VALUE
rb_fiddle_handle_sym(VALUE self, VALUE sym)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    if( ! fiddle_handle->open ){
	rb_raise(rb_eFiddleDLError, "closed handle");
    }

    return fiddle_handle_sym(fiddle_handle->ptr, sym);
}

#ifndef RTLD_NEXT
#define RTLD_NEXT NULL
#endif
#ifndef RTLD_DEFAULT
#define RTLD_DEFAULT NULL
#endif

/*
 * Document-method: sym
 *
 * call-seq: sym(name)
 *
 * Get the address as an Integer for the function named +name+.  The function
 * is searched via dlsym on RTLD_NEXT.
 *
 * See man(3) dlsym() for more info.
 */
static VALUE
rb_fiddle_handle_s_sym(VALUE self, VALUE sym)
{
    return fiddle_handle_sym(RTLD_NEXT, sym);
}

typedef void (*fiddle_void_func)(void);

static fiddle_void_func
fiddle_handle_find_func(void *handle, VALUE symbol)
{
#if defined(HAVE_DLERROR)
    const char *err;
# define CHECK_DLERROR if ((err = dlerror()) != 0) { func = 0; }
#else
# define CHECK_DLERROR
#endif
    fiddle_void_func func;
    const char *name = StringValueCStr(symbol);

#ifdef HAVE_DLERROR
    dlerror();
#endif
    func = (fiddle_void_func)(VALUE)dlsym(handle, name);
    CHECK_DLERROR;
#if defined(FUNC_STDCALL)
    if( !func ){
	int  i;
	int  len = (int)strlen(name);
	char *name_n;
#if defined(__CYGWIN__) || defined(_WIN32) || defined(__MINGW32__)
	{
	    char *name_a = (char*)xmalloc(len+2);
	    strcpy(name_a, name);
	    name_n = name_a;
	    name_a[len]   = 'A';
	    name_a[len+1] = '\0';
	    func = dlsym(handle, name_a);
	    CHECK_DLERROR;
	    if( func ) goto found;
	    name_n = xrealloc(name_a, len+6);
	}
#else
	name_n = (char*)xmalloc(len+6);
#endif
	memcpy(name_n, name, len);
	name_n[len++] = '@';
	for( i = 0; i < 256; i += 4 ){
	    sprintf(name_n + len, "%d", i);
	    func = dlsym(handle, name_n);
	    CHECK_DLERROR;
	    if( func ) break;
	}
	if( func ) goto found;
	name_n[len-1] = 'A';
	name_n[len++] = '@';
	for( i = 0; i < 256; i += 4 ){
	    sprintf(name_n + len, "%d", i);
	    func = dlsym(handle, name_n);
	    CHECK_DLERROR;
	    if( func ) break;
	}
      found:
	xfree(name_n);
    }
#endif

    return func;
}

static VALUE
rb_fiddle_handle_s_sym_defined(VALUE self, VALUE sym)
{
    fiddle_void_func func;

    func = fiddle_handle_find_func(RTLD_NEXT, sym);

    if( func ) {
	return PTR2NUM(func);
    }
    else {
	return Qnil;
    }
}

static VALUE
rb_fiddle_handle_sym_defined(VALUE self, VALUE sym)
{
    struct dl_handle *fiddle_handle;
    fiddle_void_func func;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);
    if( ! fiddle_handle->open ){
	rb_raise(rb_eFiddleDLError, "closed handle");
    }

    func = fiddle_handle_find_func(fiddle_handle->ptr, sym);

    if( func ) {
	return PTR2NUM(func);
    }
    else {
	return Qnil;
    }
}

static VALUE
fiddle_handle_sym(void *handle, VALUE symbol)
{
    fiddle_void_func func;

    func = fiddle_handle_find_func(handle, symbol);

    if( !func ){
	rb_raise(rb_eFiddleDLError, "unknown symbol \"%"PRIsVALUE"\"", symbol);
    }

    return PTR2NUM(func);
}

/*
 * call-seq: file_name
 *
 * Returns the file name of this handle.
 */
static VALUE
rb_fiddle_handle_file_name(VALUE self)
{
    struct dl_handle *fiddle_handle;

    TypedData_Get_Struct(self, struct dl_handle, &fiddle_handle_data_type, fiddle_handle);

#if defined(HAVE_DLINFO) && defined(HAVE_CONST_RTLD_DI_LINKMAP)
    {
	struct link_map *lm = NULL;
	int res = dlinfo(fiddle_handle->ptr, RTLD_DI_LINKMAP, &lm);
	if (res == 0 && lm != NULL) {
	    return rb_str_new_cstr(lm->l_name);
	}
	else {
#if defined(HAVE_DLERROR)
	    rb_raise(rb_eFiddleDLError, "could not get handle file name: %s", dlerror());
#else
	    rb_raise(rb_eFiddleDLError, "could not get handle file name");
#endif
	}
    }
#elif defined(HAVE_GETMODULEFILENAME)
    {
	char filename[MAX_PATH];
	DWORD res = GetModuleFileName(fiddle_handle->ptr, filename, MAX_PATH);
	if (res == 0) {
	    rb_raise(rb_eFiddleDLError, "could not get handle file name: %s", dlerror());
	}
	return rb_str_new_cstr(filename);
    }
#else
    (void)fiddle_handle;
    return Qnil;
#endif
}

void
Init_fiddle_handle(void)
{
    /*
     * Document-class: Fiddle::Handle
     *
     * The Fiddle::Handle is the manner to access the dynamic library
     *
     * == Example
     *
     * === Setup
     *
     *   libc_so = "/lib64/libc.so.6"
     *   => "/lib64/libc.so.6"
     *   @handle = Fiddle::Handle.new(libc_so)
     *   => #<Fiddle::Handle:0x00000000d69ef8>
     *
     * === Setup, with flags
     *
     *   libc_so = "/lib64/libc.so.6"
     *   => "/lib64/libc.so.6"
     *   @handle = Fiddle::Handle.new(libc_so, Fiddle::RTLD_LAZY | Fiddle::RTLD_GLOBAL)
     *   => #<Fiddle::Handle:0x00000000d69ef8>
     *
     * See RTLD_LAZY and RTLD_GLOBAL
     *
     * === Addresses to symbols
     *
     *   strcpy_addr = @handle['strcpy']
     *   => 140062278451968
     *
     * or
     *
     *   strcpy_addr = @handle.sym('strcpy')
     *   => 140062278451968
     *
     */
    rb_cHandle = rb_define_class_under(mFiddle, "Handle", rb_cObject);
    rb_define_alloc_func(rb_cHandle, rb_fiddle_handle_s_allocate);
    rb_define_singleton_method(rb_cHandle, "sym", rb_fiddle_handle_s_sym, 1);
    rb_define_singleton_method(rb_cHandle, "sym_defined?", rb_fiddle_handle_s_sym_defined, 1);
    rb_define_singleton_method(rb_cHandle, "[]", rb_fiddle_handle_s_sym,  1);

    /* Document-const: NEXT
     *
     * A predefined pseudo-handle of RTLD_NEXT
     *
     * Which will find the next occurrence of a function in the search order
     * after the current library.
     */
    rb_define_const(rb_cHandle, "NEXT", predefined_fiddle_handle(RTLD_NEXT));

    /* Document-const: DEFAULT
     *
     * A predefined pseudo-handle of RTLD_DEFAULT
     *
     * Which will find the first occurrence of the desired symbol using the
     * default library search order
     */
    rb_define_const(rb_cHandle, "DEFAULT", predefined_fiddle_handle(RTLD_DEFAULT));

    /* Document-const: RTLD_GLOBAL
     *
     * rtld Fiddle::Handle flag.
     *
     * The symbols defined by this library will be made available for symbol
     * resolution of subsequently loaded libraries.
     */
    rb_define_const(rb_cHandle, "RTLD_GLOBAL", INT2NUM(RTLD_GLOBAL));

    /* Document-const: RTLD_LAZY
     *
     * rtld Fiddle::Handle flag.
     *
     * Perform lazy binding.  Only resolve symbols as the code that references
     * them is executed.  If the  symbol is never referenced, then it is never
     * resolved.  (Lazy binding is only performed for function references;
     * references to variables are always immediately bound when the library
     * is loaded.)
     */
    rb_define_const(rb_cHandle, "RTLD_LAZY",   INT2NUM(RTLD_LAZY));

    /* Document-const: RTLD_NOW
     *
     * rtld Fiddle::Handle flag.
     *
     * If this value is specified or the environment variable LD_BIND_NOW is
     * set to a nonempty string, all undefined symbols in the library are
     * resolved before Fiddle.dlopen returns.  If this cannot be done an error
     * is returned.
     */
    rb_define_const(rb_cHandle, "RTLD_NOW",    INT2NUM(RTLD_NOW));

    rb_define_method(rb_cHandle, "initialize", rb_fiddle_handle_initialize, -1);
    rb_define_method(rb_cHandle, "to_i", rb_fiddle_handle_to_i, 0);
    rb_define_method(rb_cHandle, "to_ptr", rb_fiddle_handle_to_ptr, 0);
    rb_define_method(rb_cHandle, "close", rb_fiddle_handle_close, 0);
    rb_define_method(rb_cHandle, "sym",  rb_fiddle_handle_sym, 1);
    rb_define_method(rb_cHandle, "[]",  rb_fiddle_handle_sym,  1);
    rb_define_method(rb_cHandle, "sym_defined?", rb_fiddle_handle_sym_defined, 1);
    rb_define_method(rb_cHandle, "file_name", rb_fiddle_handle_file_name, 0);
    rb_define_method(rb_cHandle, "disable_close", rb_fiddle_handle_disable_close, 0);
    rb_define_method(rb_cHandle, "enable_close", rb_fiddle_handle_enable_close, 0);
    rb_define_method(rb_cHandle, "close_enabled?", rb_fiddle_handle_close_enabled_p, 0);
}

/* vim: set noet sws=4 sw=4: */
