/**********************************************************************

  io_buffer.c

  Copyright (C) 2021 Samuel Grant Dawson Williams

**********************************************************************/

#include "ruby/io.h"
#include "ruby/io/buffer.h"
#include "ruby/fiber/scheduler.h"

#include "internal.h"
#include "internal/string.h"
#include "internal/bits.h"
#include "internal/error.h"

VALUE rb_cIOBuffer;
VALUE rb_eIOBufferLockedError;
VALUE rb_eIOBufferAllocationError;
VALUE rb_eIOBufferAccessError;
VALUE rb_eIOBufferInvalidatedError;

size_t RUBY_IO_BUFFER_PAGE_SIZE;
size_t RUBY_IO_BUFFER_DEFAULT_SIZE;

#ifdef _WIN32
#else
#include <unistd.h>
#include <sys/mman.h>
#endif

struct rb_io_buffer {
    void *base;
    size_t size;
    enum rb_io_buffer_flags flags;

#if defined(_WIN32)
    HANDLE mapping;
#endif

    VALUE source;
};

static inline void *
io_buffer_map_memory(size_t size)
{
#if defined(_WIN32)
    void * base = VirtualAlloc(0, size, MEM_COMMIT, PAGE_READWRITE);

    if (!base) {
        rb_sys_fail("io_buffer_map_memory:VirtualAlloc");
    }
#else
    void * base = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);

    if (base == MAP_FAILED) {
        rb_sys_fail("io_buffer_map_memory:mmap");
    }
#endif

    return base;
}

static void
io_buffer_map_file(struct rb_io_buffer *data, int descriptor, size_t size, off_t offset, enum rb_io_buffer_flags flags)
{
#if defined(_WIN32)
    HANDLE file = (HANDLE)_get_osfhandle(descriptor);
    if (!file) rb_sys_fail("io_buffer_map_descriptor:_get_osfhandle");

    DWORD protect = PAGE_READONLY, access = FILE_MAP_READ;

    if (flags & RB_IO_BUFFER_READONLY) {
        data->flags |= RB_IO_BUFFER_READONLY;
    }
    else {
        protect = PAGE_READWRITE;
        access = FILE_MAP_WRITE;
    }

    HANDLE mapping = CreateFileMapping(file, NULL, protect, 0, 0, NULL);
    if (!mapping) rb_sys_fail("io_buffer_map_descriptor:CreateFileMapping");

    if (flags & RB_IO_BUFFER_PRIVATE) {
        access |= FILE_MAP_COPY;
        data->flags |= RB_IO_BUFFER_PRIVATE;
    } else {
        // This buffer refers to external data.
        data->flags |= RB_IO_BUFFER_EXTERNAL;
    }

    void *base = MapViewOfFile(mapping, access, (DWORD)(offset >> 32), (DWORD)(offset & 0xFFFFFFFF), size);

    if (!base) {
        CloseHandle(mapping);
        rb_sys_fail("io_buffer_map_file:MapViewOfFile");
    }

    data->mapping = mapping;
#else
    int protect = PROT_READ, access = 0;

    if (flags & RB_IO_BUFFER_READONLY) {
        data->flags |= RB_IO_BUFFER_READONLY;
    }
    else {
        protect |= PROT_WRITE;
    }

    if (flags & RB_IO_BUFFER_PRIVATE) {
        data->flags |= RB_IO_BUFFER_PRIVATE;
    }
    else {
        // This buffer refers to external data.
        data->flags |= RB_IO_BUFFER_EXTERNAL;
        access |= MAP_SHARED;
    }

    void *base = mmap(NULL, size, protect, access, descriptor, offset);

    if (base == MAP_FAILED) {
        rb_sys_fail("io_buffer_map_file:mmap");
    }
#endif

    data->base = base;
    data->size = size;

    data->flags |= RB_IO_BUFFER_MAPPED;
}

static inline void
io_buffer_unmap(void* base, size_t size)
{
#ifdef _WIN32
    VirtualFree(base, 0, MEM_RELEASE);
#else
    munmap(base, size);
#endif
}

static void
io_buffer_experimental(void)
{
    static int warned = 0;

    if (warned) return;

    warned = 1;

    if (rb_warning_category_enabled_p(RB_WARN_CATEGORY_EXPERIMENTAL)) {
        rb_category_warn(RB_WARN_CATEGORY_EXPERIMENTAL,
          "IO::Buffer is experimental and both the Ruby and C interface may change in the future!"
        );
    }
}

static void
io_buffer_zero(struct rb_io_buffer *data)
{
    data->base = NULL;
    data->size = 0;
#if defined(_WIN32)
    data->mapping = NULL;
#endif
    data->source = Qnil;
}

static void
io_buffer_initialize(struct rb_io_buffer *data, void *base, size_t size, enum rb_io_buffer_flags flags, VALUE source)
{
    if (base) {
        // If we are provided a pointer, we use it.
    }
    else if (size) {
        // If we are provided a non-zero size, we allocate it:
        if (flags & RB_IO_BUFFER_INTERNAL) {
            base = calloc(size, 1);
        }
        else if (flags & RB_IO_BUFFER_MAPPED) {
            base = io_buffer_map_memory(size);
        }

        if (!base) {
            rb_raise(rb_eIOBufferAllocationError, "Could not allocate buffer!");
        }
    } else {
        // Otherwise we don't do anything.
        return;
    }

    data->base = base;
    data->size = size;
    data->flags = flags;
    data->source = source;
}

static int
io_buffer_free(struct rb_io_buffer *data)
{
    if (data->base) {
        if (data->flags & RB_IO_BUFFER_INTERNAL) {
            free(data->base);
        }

        if (data->flags & RB_IO_BUFFER_MAPPED) {
            io_buffer_unmap(data->base, data->size);
        }

        // Previously we had this, but we found out due to the way GC works, we
        // can't refer to any other Ruby objects here.
        // if (RB_TYPE_P(data->source, T_STRING)) {
        //     rb_str_unlocktmp(data->source);
        // }

        data->base = NULL;

#if defined(_WIN32)
        if (data->mapping) {
            CloseHandle(data->mapping);
            data->mapping = NULL;
        }
#endif
        data->size = 0;
        data->flags = 0;
        data->source = Qnil;

        return 1;
    }

    return 0;
}

void
rb_io_buffer_type_mark(void *_data)
{
    struct rb_io_buffer *data = _data;
    rb_gc_mark(data->source);
}

void
rb_io_buffer_type_free(void *_data)
{
    struct rb_io_buffer *data = _data;

    io_buffer_free(data);

    free(data);
}

size_t
rb_io_buffer_type_size(const void *_data)
{
    const struct rb_io_buffer *data = _data;
    size_t total = sizeof(struct rb_io_buffer);

    if (data->flags) {
        total += data->size;
    }

    return total;
}

static const rb_data_type_t rb_io_buffer_type = {
    .wrap_struct_name = "IO::Buffer",
    .function = {
        .dmark = rb_io_buffer_type_mark,
        .dfree = rb_io_buffer_type_free,
        .dsize = rb_io_buffer_type_size,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

VALUE
rb_io_buffer_type_allocate(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    VALUE instance = TypedData_Make_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_zero(data);

    return instance;
}

static VALUE io_buffer_for_make_instance(VALUE klass, VALUE string, enum rb_io_buffer_flags flags)
{
    VALUE instance = rb_io_buffer_type_allocate(klass);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, data);

    flags |= RB_IO_BUFFER_EXTERNAL;

    if (RB_OBJ_FROZEN(string))
        flags |= RB_IO_BUFFER_READONLY;

    if (!(flags & RB_IO_BUFFER_READONLY))
        rb_str_modify(string);

    io_buffer_initialize(data, RSTRING_PTR(string), RSTRING_LEN(string), flags, string);

    return instance;
}

struct io_buffer_for_yield_instance_arguments {
    VALUE klass;
    VALUE string;
    VALUE instance;
    enum rb_io_buffer_flags flags;
};

static VALUE
io_buffer_for_yield_instance(VALUE _arguments) {
    struct io_buffer_for_yield_instance_arguments *arguments = (struct io_buffer_for_yield_instance_arguments *)_arguments;

    arguments->instance = io_buffer_for_make_instance(arguments->klass, arguments->string, arguments->flags);

    rb_str_locktmp(arguments->string);

    return rb_yield(arguments->instance);
}

static VALUE
io_buffer_for_yield_instance_ensure(VALUE _arguments)
{
    struct io_buffer_for_yield_instance_arguments *arguments = (struct io_buffer_for_yield_instance_arguments *)_arguments;

    if (arguments->instance != Qnil) {
        rb_io_buffer_free(arguments->instance);
    }

    rb_str_unlocktmp(arguments->string);

    return Qnil;
}

/*
 *  call-seq:
 *    IO::Buffer.for(string) -> readonly io_buffer
 *    IO::Buffer.for(string) {|io_buffer| ... read/write io_buffer ...}
 *
 *  Creates a IO::Buffer from the given string's memory. Without a block a
 *  frozen internal copy of the string is created efficiently and used as the
 *  buffer source. When a block is provided, the buffer is associated directly
 *  with the string's internal data and updating the buffer will update the
 *  string.
 *
 *  Until #free is invoked on the buffer, either explicitly or via the garbage
 *  collector, the source string will be locked and cannot be modified.
 *
 *  If the string is frozen, it will create a read-only buffer which cannot be
 *  modified. If the string is shared, it may trigger a copy-on-write when
 *  using the block form.
 *
 *    string = 'test'
 *    buffer = IO::Buffer.for(string)
 *    buffer.external? #=> true
 *
 *    buffer.get_string(0, 1)
 *    # => "t"
 *    string
 *    # => "best"
 *
 *    buffer.resize(100)
 *    # in `resize': Cannot resize external buffer! (IO::Buffer::AccessError)
 *
 *    IO::Buffer.for(string) do |buffer|
 *      buffer.set_string("T")
 *      string
 *      # => "Test"
 *    end
 */
VALUE
rb_io_buffer_type_for(VALUE klass, VALUE string)
{
    StringValue(string);

    // If the string is frozen, both code paths are okay.
    // If the string is not frozen, if a block is not given, it must be frozen.
    if (rb_block_given_p()) {
        struct io_buffer_for_yield_instance_arguments arguments = {
            .klass = klass,
            .string = string,
            .instance = Qnil,
            .flags = 0,
        };

      return rb_ensure(io_buffer_for_yield_instance, (VALUE)&arguments, io_buffer_for_yield_instance_ensure, (VALUE)&arguments);
    } else {
        // This internally returns the source string if it's already frozen.
        string = rb_str_tmp_frozen_acquire(string);
        return io_buffer_for_make_instance(klass, string, RB_IO_BUFFER_READONLY);
    }
}

VALUE
rb_io_buffer_new(void *base, size_t size, enum rb_io_buffer_flags flags)
{
    VALUE instance = rb_io_buffer_type_allocate(rb_cIOBuffer);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_initialize(data, base, size, flags, Qnil);

    return instance;
}

VALUE
rb_io_buffer_map(VALUE io, size_t size, off_t offset, enum rb_io_buffer_flags flags)
{
    io_buffer_experimental();

    VALUE instance = rb_io_buffer_type_allocate(rb_cIOBuffer);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, data);

    int descriptor = rb_io_descriptor(io);

    io_buffer_map_file(data, descriptor, size, offset, flags);

    return instance;
}

/*
 *  call-seq: IO::Buffer.map(file, [size, [offset, [flags]]]) -> io_buffer
 *
 *  Create an IO::Buffer for reading from +file+ by memory-mapping the file.
 *  +file_io+ should be a +File+ instance, opened for reading.
 *
 *  Optional +size+ and +offset+ of mapping can be specified.
 *
 *  By default, the buffer would be immutable (read only); to create a writable
 *  mapping, you need to open a file in read-write mode, and explicitly pass
 *  +flags+ argument without IO::Buffer::IMMUTABLE.
 *
 *     File.write('test.txt', 'test')
 *
 *     buffer = IO::Buffer.map(File.open('test.txt'), nil, 0, IO::Buffer::READONLY)
 *     # => #<IO::Buffer 0x00000001014a0000+4 MAPPED READONLY>
 *
 *     buffer.readonly?   # => true
 *
 *     buffer.get_string
 *     # => "test"
 *
 *     buffer.set_string('b', 0)
 *     # `set_string': Buffer is not writable! (IO::Buffer::AccessError)
 *
 *     # create read/write mapping: length 4 bytes, offset 0, flags 0
 *     buffer = IO::Buffer.map(File.open('test.txt', 'r+'), 4, 0)
 *     buffer.set_string('b', 0)
 *     # => 1
 *
 *     # Check it
 *     File.read('test.txt')
 *     # => "best"
 *
 *  Note that some operating systems may not have cache coherency between mapped
 *  buffers and file reads.
 *
 */
static VALUE
io_buffer_map(int argc, VALUE *argv, VALUE klass)
{
    if (argc < 1 || argc > 4) {
        rb_error_arity(argc, 2, 4);
    }

    // We might like to handle a string path?
    VALUE io = argv[0];

    size_t size;
    if (argc >= 2 && !RB_NIL_P(argv[1])) {
        size = RB_NUM2SIZE(argv[1]);
    }
    else {
        off_t file_size = rb_file_size(io);

        // Compiler can confirm that we handled file_size < 0 case:
        if (file_size < 0) {
            rb_raise(rb_eArgError, "Invalid negative file size!");
        }
        // Here, we assume that file_size is positive:
        else if ((uintmax_t)file_size > SIZE_MAX) {
            rb_raise(rb_eArgError, "File larger than address space!");
        }
        else {
            // This conversion should be safe:
            size = (size_t)file_size;
        }
    }

    off_t offset = 0;
    if (argc >= 3) {
        offset = NUM2OFFT(argv[2]);
    }

    enum rb_io_buffer_flags flags = 0;
    if (argc >= 4) {
        flags = RB_NUM2UINT(argv[3]);
    }

    return rb_io_buffer_map(io, size, offset, flags);
}

// Compute the optimal allocation flags for a buffer of the given size.
static inline enum rb_io_buffer_flags
io_flags_for_size(size_t size)
{
    if (size >= RUBY_IO_BUFFER_PAGE_SIZE) {
        return RB_IO_BUFFER_MAPPED;
    }

    return RB_IO_BUFFER_INTERNAL;
}

/*
 *  call-seq: IO::Buffer.new([size = DEFAULT_SIZE, [flags = 0]]) -> io_buffer
 *
 *  Create a new zero-filled IO::Buffer of +size+ bytes.
 *  By default, the buffer will be _internal_: directly allocated chunk
 *  of the memory. But if the requested +size+ is more than OS-specific
 *  IO::Bufer::PAGE_SIZE, the buffer would be allocated using the
 *  virtual memory mechanism (anonymous +mmap+ on Unix, +VirtualAlloc+
 *  on Windows). The behavior can be forced by passing IO::Buffer::MAPPED
 *  as a second parameter.
 *
 *  Examples
 *
 *    buffer = IO::Buffer.new(4)
 *    # =>
 *    #  #<IO::Buffer 0x000055b34497ea10+4 INTERNAL>
 *    #  0x00000000  00 00 00 00                                     ....
 *
 *    buffer.get_string(0, 1) # => "\x00"
 *
 *    buffer.set_string("test")
 *    buffer
 *    #  =>
 *    # #<IO::Buffer 0x000055b34497ea10+4 INTERNAL>
 *    # 0x00000000  74 65 73 74                                     test
 *
 */
VALUE
rb_io_buffer_initialize(int argc, VALUE *argv, VALUE self)
{
    io_buffer_experimental();

    if (argc < 0 || argc > 2) {
        rb_error_arity(argc, 0, 2);
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    size_t size;

    if (argc > 0) {
        size = RB_NUM2SIZE(argv[0]);
    } else {
        size = RUBY_IO_BUFFER_DEFAULT_SIZE;
    }

    enum rb_io_buffer_flags flags = 0;
    if (argc >= 2) {
        flags = RB_NUM2UINT(argv[1]);
    }
    else {
        flags |= io_flags_for_size(size);
    }

    io_buffer_initialize(data, NULL, size, flags, Qnil);

    return self;
}

static int
io_buffer_validate_slice(VALUE source, void *base, size_t size)
{
    void *source_base = NULL;
    size_t source_size = 0;

    if (RB_TYPE_P(source, T_STRING)) {
        RSTRING_GETMEM(source, source_base, source_size);
    }
    else {
        rb_io_buffer_get_bytes(source, &source_base, &source_size);
    }

    // Source is invalid:
    if (source_base == NULL) return 0;

    // Base is out of range:
    if (base < source_base) return 0;

    const void *source_end = (char*)source_base + source_size;
    const void *end = (char*)base + size;

    // End is out of range:
    if (end > source_end) return 0;

    // It seems okay:
    return 1;
}

static int
io_buffer_validate(struct rb_io_buffer *data)
{
    if (data->source != Qnil) {
        // Only slices incur this overhead, unfortunately... better safe than sorry!
        return io_buffer_validate_slice(data->source, data->base, data->size);
    }
    else {
        return 1;
    }
}

/*
 *  call-seq: to_s -> string
 *
 *  Short representation of the buffer. It includes the address, size and
 *  symbolic flags. This format is subject to change.
 *
 *    puts IO::Buffer.new(4) # uses to_s internally
 *    # #<IO::Buffer 0x000055769f41b1a0+4 INTERNAL>
 *
 */
VALUE
rb_io_buffer_to_s(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE result = rb_str_new_cstr("#<");

    rb_str_append(result, rb_class_name(CLASS_OF(self)));
    rb_str_catf(result, " %p+%"PRIdSIZE, data->base, data->size);

    if (data->base == NULL) {
        rb_str_cat2(result, " NULL");
    }

    if (data->flags & RB_IO_BUFFER_EXTERNAL) {
        rb_str_cat2(result, " EXTERNAL");
    }

    if (data->flags & RB_IO_BUFFER_INTERNAL) {
        rb_str_cat2(result, " INTERNAL");
    }

    if (data->flags & RB_IO_BUFFER_MAPPED) {
        rb_str_cat2(result, " MAPPED");
    }

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_str_cat2(result, " LOCKED");
    }

    if (data->flags & RB_IO_BUFFER_READONLY) {
        rb_str_cat2(result, " READONLY");
    }

    if (data->source != Qnil) {
        rb_str_cat2(result, " SLICE");
    }

    if (!io_buffer_validate(data)) {
        rb_str_cat2(result, " INVALID");
    }

    return rb_str_cat2(result, ">");
}

static VALUE
io_buffer_hexdump(VALUE string, size_t width, char *base, size_t size, int first)
{
    char *text = alloca(width+1);
    text[width] = '\0';

    for (size_t offset = 0; offset < size; offset += width) {
        memset(text, '\0', width);
        if (first) {
            rb_str_catf(string, "0x%08zx ", offset);
            first = 0;
        } else {
            rb_str_catf(string, "\n0x%08zx ", offset);
        }

        for (size_t i = 0; i < width; i += 1) {
            if (offset+i < size) {
                unsigned char value = ((unsigned char*)base)[offset+i];

                if (value < 127 && isprint(value)) {
                    text[i] = (char)value;
                }
                else {
                    text[i] = '.';
                }

                rb_str_catf(string, " %02x", value);
            }
            else {
                rb_str_cat2(string, "   ");
            }
        }

        rb_str_catf(string, " %s", text);
    }

    return string;
}

static VALUE
rb_io_buffer_hexdump(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE result = Qnil;

    if (io_buffer_validate(data) && data->base) {
        result = rb_str_buf_new(data->size*3 + (data->size/16)*12 + 1);

        io_buffer_hexdump(result, 16, data->base, data->size, 1);
    }

    return result;
}

VALUE
rb_io_buffer_inspect(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE result = rb_io_buffer_to_s(self);

    if (io_buffer_validate(data)) {
        // Limit the maximum size genearted by inspect.
        if (data->size <= 256) {
            io_buffer_hexdump(result, 16, data->base, data->size, 0);
        }
    }

    return result;
}

/*
 *  call-seq: size -> integer
 *
 *  Returns the size of the buffer that was explicitly set (on creation with ::new
 *  or on #resize), or deduced on buffer's creation from string or file.
 *
 */
VALUE
rb_io_buffer_size(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return SIZET2NUM(data->size);
}

/*
 *  call-seq: valid? -> true or false
 *
 *  Returns whether the buffer data is accessible.
 *
 *  A buffer becomes invalid if it is a slice of another buffer which has been
 *  freed.
 *
 */
static VALUE
rb_io_buffer_valid_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(io_buffer_validate(data));
}

/*
 *  call-seq: null? -> true or false
 *
 *  If the buffer was freed with #free or was never allocated in the first
 *  place.
 *
 */
static VALUE
rb_io_buffer_null_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(data->base == NULL);
}

/*
 *  call-seq: external? -> true or false
 *
 *  If the buffer is _external_, meaning it references from memory which is not
 *  allocated or mapped by the buffer itself.
 *
 *  A buffer created using ::for has an external reference to the string's
 *  memory.
 *
 * External buffer can't be resized.
 *
 */
static VALUE
rb_io_buffer_empty_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(data->size == 0);
}

static VALUE
rb_io_buffer_external_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(data->flags & RB_IO_BUFFER_EXTERNAL);
}

/*
 *  call-seq: internal? -> true or false
 *
 *  If the buffer is _internal_, meaning it references memory allocated by the
 *  buffer itself.
 *
 *  An internal buffer is not associated with any external memory (e.g. string)
 *  or file mapping.
 *
 *  Internal buffers are created using ::new and is the default when the
 *  requested size is less than the IO::Buffer::PAGE_SIZE and it was not
 *  requested to be mapped on creation.
 *
 *  Internal buffers can be resized, and such an operation will typically
 *  invalidate all slices, but not always.
 *
 */
static VALUE
rb_io_buffer_internal_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(data->flags & RB_IO_BUFFER_INTERNAL);
}

/*
 *  call-seq: mapped? -> true or false
 *
 *  If the buffer is _mapped_, meaning it references memory mapped by the
 *  buffer.
 *
 *  Mapped buffers are either anonymous, if created by ::new with the
 *  IO::Buffer::MAPPED flag or if the size was at least IO::Buffer::PAGE_SIZE,
 *  or backed by a file if created with ::map.
 *
 *  Mapped buffers can usually be resized, and such an operation will typically
 *  invalidate all slices, but not always.
 *
 */
static VALUE
rb_io_buffer_mapped_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(data->flags & RB_IO_BUFFER_MAPPED);
}

/*
 *  call-seq: locked? -> true or false
 *
 *  If the buffer is _locked_, meaning it is inside #locked block execution.
 *  Locked buffer can't be resized or freed, and another lock can't be acquired
 *  on it.
 *
 *  Locking is not thread safe, but is a semantic used to ensure buffers don't
 *  move while being used by a system call.
 *
 *    buffer.locked do
 *      buffer.write(io) # theoretical system call interface
 *    end
 *
 */
static VALUE
rb_io_buffer_locked_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return RBOOL(data->flags & RB_IO_BUFFER_LOCKED);
}

/*
 *  call-seq: readonly? -> true or false
 *
 *  If the buffer is _read only_, meaning the buffer cannot be modified using
 *  #set_value, #set_string or #copy and similar.
 *
 *  Frozen strings and read-only files create read-only buffers.
 *
 */
int
rb_io_buffer_readonly_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return data->flags & RB_IO_BUFFER_READONLY;
}

static VALUE
io_buffer_readonly_p(VALUE self)
{
    return RBOOL(rb_io_buffer_readonly_p(self));
}

VALUE
rb_io_buffer_lock(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Buffer already locked!");
    }

    data->flags |= RB_IO_BUFFER_LOCKED;

    return self;
}

VALUE
rb_io_buffer_unlock(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (!(data->flags & RB_IO_BUFFER_LOCKED)) {
        rb_raise(rb_eIOBufferLockedError, "Buffer not locked!");
    }

    data->flags &= ~RB_IO_BUFFER_LOCKED;

    return self;
}

int
rb_io_buffer_try_unlock(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        data->flags &= ~RB_IO_BUFFER_LOCKED;
        return 1;
    }

    return 0;
}

/*
 *  call-seq: locked { ... }
 *
 *  Allows to process a buffer in exclusive way, for concurrency-safety. While
 *  the block is performed, the buffer is considered locked, and no other code
 *  can enter the lock. Also, locked buffer can't be changed with #resize or
 *  #free.
 *
 *    buffer = IO::Buffer.new(4)
 *    buffer.locked? #=> false
 *
 *    Fiber.schedule do
 *      buffer.locked do
 *        buffer.write(io) # theoretical system call interface
 *      end
 *    end
 *
 *    Fiber.schedule do
 *      # in `locked': Buffer already locked! (IO::Buffer::LockedError)
 *      buffer.locked do
 *        buffer.set_string(...)
 *      end
 *    end
 *
 *  The following operations acquire a lock: #resize, #free.
 *
 *  Locking is not thread safe. It is designed as a safety net around
 *  non-blocking system calls. You can only share a buffer between threads with
 *  appropriate synchronisation techniques.
 */
VALUE
rb_io_buffer_locked(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Buffer already locked!");
    }

    data->flags |= RB_IO_BUFFER_LOCKED;

    VALUE result = rb_yield(self);

    data->flags &= ~RB_IO_BUFFER_LOCKED;

    return result;
}

/*
 *  call-seq: free -> self
 *
 *  If the buffer references memory, release it back to the operating system.
 *  * for a _mapped_ buffer (e.g. from file): unmap.
 *  * for a buffer created from scratch: free memory.
 *  * for a buffer created from string: undo the association.
 *
 *  After the buffer is freed, no further operations can't be performed on it.
 *
 *     buffer = IO::Buffer.for('test')
 *     buffer.free
 *     # => #<IO::Buffer 0x0000000000000000+0 NULL>
 *
 *     buffer.get_value(:U8, 0)
 *     # in `get_value': The buffer is not allocated! (IO::Buffer::AllocationError)
 *
 *     buffer.get_string
 *     # in `get_string': The buffer is not allocated! (IO::Buffer::AllocationError)
 *
 *     buffer.null?
 *     # => true
 *
 *  You can resize a freed buffer to re-allocate it.
 *
 */
VALUE
rb_io_buffer_free(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Buffer is locked!");
    }

    io_buffer_free(data);

    return self;
}

static inline void
io_buffer_validate_range(struct rb_io_buffer *data, size_t offset, size_t length)
{
    if (offset > data->size) {
        rb_raise(rb_eArgError, "Specified offset exceeds buffer size!");
    }
    if (offset + length > data->size) {
        rb_raise(rb_eArgError, "Specified offset+length exceeds buffer size!");
    }
}

/*
 *  call-seq: slice(offset, length) -> io_buffer
 *
 *  Produce another IO::Buffer which is a slice (or view into) the current one
 *  starting at +offset+ bytes and going for +length+ bytes.
 *
 *  The slicing happens without copying of memory, and the slice keeps being
 *  associated with the original buffer's source (string, or file), if any.
 *
 *  Raises RuntimeError if the <tt>offset+length<tt> is out of the current
 *  buffer's bounds.
 *
 *     string = 'test'
 *     buffer = IO::Buffer.for(string)
 *
 *     slice = buffer.slice(1, 2)
 *     # =>
 *     #  #<IO::Buffer 0x00007fc3d34ebc49+2 SLICE>
 *     #  0x00000000  65 73                                           es
 *
 *     # Put "o" into 0s position of the slice
 *     slice.set_string('o', 0)
 *     slice
 *     # =>
 *     #  #<IO::Buffer 0x00007fc3d34ebc49+2 SLICE>
 *     #  0x00000000  6f 73                                           os
 *
 *
 *     # it is also visible at position 1 of the original buffer
 *     buffer
 *     # =>
 *     #  #<IO::Buffer 0x00007fc3d31e2d80+4 SLICE>
 *     #  0x00000000  74 6f 73 74                                     tost
 *
 *     # ...and original string
 *     string
 *     # => tost
 *
 */
VALUE
rb_io_buffer_slice(VALUE self, VALUE _offset, VALUE _length)
{
    // TODO fail on negative offets/lengths.
    size_t offset = NUM2SIZET(_offset);
    size_t length = NUM2SIZET(_length);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_validate_range(data, offset, length);

    VALUE instance = rb_io_buffer_type_allocate(rb_class_of(self));
    struct rb_io_buffer *slice = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, slice);

    slice->base = (char*)data->base + offset;
    slice->size = length;

    // The source should be the root buffer:
    if (data->source != Qnil)
        slice->source = data->source;
    else
        slice->source = self;

    return instance;
}

int rb_io_buffer_get_bytes(VALUE self, void **base, size_t *size)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (io_buffer_validate(data)) {
        if (data->base) {
            *base = data->base;
            *size = data->size;

            return data->flags;
        }
    }

    *base = NULL;
    *size = 0;

    return 0;
}

static void
io_buffer_get_bytes_for_writing(struct rb_io_buffer *data, void **base, size_t *size)
{
    if (data->flags & RB_IO_BUFFER_READONLY) {
        rb_raise(rb_eIOBufferAccessError, "Buffer is not writable!");
    }

    if (!io_buffer_validate(data)) {
        rb_raise(rb_eIOBufferInvalidatedError, "Buffer is invalid!");
    }

    if (data->base) {
        *base = data->base;
        *size = data->size;

        return;
    }

    rb_raise(rb_eIOBufferAllocationError, "The buffer is not allocated!");
}

void
rb_io_buffer_get_bytes_for_writing(VALUE self, void **base, size_t *size)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_get_bytes_for_writing(data, base, size);
}

static void
io_buffer_get_bytes_for_reading(struct rb_io_buffer *data, const void **base, size_t *size)
{
    if (!io_buffer_validate(data)) {
        rb_raise(rb_eIOBufferInvalidatedError, "Buffer has been invalidated!");
    }

    if (data->base) {
        *base = data->base;
        *size = data->size;

        return;
    }

    rb_raise(rb_eIOBufferAllocationError, "The buffer is not allocated!");
}

void
rb_io_buffer_get_bytes_for_reading(VALUE self, const void **base, size_t *size)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_get_bytes_for_reading(data, base, size);
}

/*
 *  call-seq: transfer -> new_io_buffer
 *
 *  Transfers ownership to a new buffer, deallocating the current one.
 *
 *     buffer = IO::Buffer.new('test')
 *     other = buffer.transfer
 *     other
 *     #  =>
 *     # #<IO::Buffer 0x00007f136a15f7b0+4 SLICE>
 *     # 0x00000000  74 65 73 74                                     test
 *     buffer
 *     #  =>
 *     # #<IO::Buffer 0x0000000000000000+0 NULL>
 *     buffer.null?
 *     # => true
 *
 */
VALUE
rb_io_buffer_transfer(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Cannot transfer ownership of locked buffer!");
    }

    VALUE instance = rb_io_buffer_type_allocate(rb_class_of(self));
    struct rb_io_buffer *transferred;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, transferred);

    *transferred = *data;
    io_buffer_zero(data);

    return instance;
}

static void
io_buffer_resize_clear(struct rb_io_buffer *data, void* base, size_t size)
{
    if (size > data->size) {
        memset((unsigned char*)base+data->size, 0, size - data->size);
    }
}

static void
io_buffer_resize_copy(struct rb_io_buffer *data, size_t size)
{
    // Slow path:
    struct rb_io_buffer resized;
    io_buffer_initialize(&resized, NULL, size, io_flags_for_size(size), Qnil);

    if (data->base) {
        size_t preserve = data->size;
        if (preserve > size) preserve = size;
        memcpy(resized.base, data->base, preserve);

        io_buffer_resize_clear(data, resized.base, size);
    }

    io_buffer_free(data);
    *data = resized;
}

void
rb_io_buffer_resize(VALUE self, size_t size)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Cannot resize locked buffer!");
    }

    if (data->base == NULL) {
        io_buffer_initialize(data, NULL, size, io_flags_for_size(size), Qnil);
        return;
    }

    if (data->flags & RB_IO_BUFFER_EXTERNAL) {
        rb_raise(rb_eIOBufferAccessError, "Cannot resize external buffer!");
    }

#ifdef MREMAP_MAYMOVE
    if (data->flags & RB_IO_BUFFER_MAPPED) {
        void *base = mremap(data->base, data->size, size, MREMAP_MAYMOVE);

        if (base == MAP_FAILED) {
            rb_sys_fail("rb_io_buffer_resize:mremap");
        }

        io_buffer_resize_clear(data, base, size);

        data->base = base;
        data->size = size;

        return;
    }
#endif

    if (data->flags & RB_IO_BUFFER_INTERNAL) {
        if (size == 0) {
            io_buffer_free(data);
            return;
        }

        void *base = realloc(data->base, size);

        if (!base) {
            rb_sys_fail("rb_io_buffer_resize:realloc");
        }

        io_buffer_resize_clear(data, base, size);

        data->base = base;
        data->size = size;

        return;
    }

    io_buffer_resize_copy(data, size);
}

/*
 *  call-seq: resize(new_size) -> self
 *
 *  Resizes a buffer to a +new_size+ bytes, preserving its content.
 *  Depending on the old and new size, the memory area associated with
 *  the buffer might be either extended, or rellocated at different
 *  address with content being copied.
 *
 *    buffer = IO::Buffer.new(4)
 *    buffer.set_string("test", 0)
 *    buffer.resize(8) # resize to 8 bytes
 *    #  =>
 *    # #<IO::Buffer 0x0000555f5d1a1630+8 INTERNAL>
 *    # 0x00000000  74 65 73 74 00 00 00 00                         test....
 *
 *  External buffer (created with ::for), and locked buffer
 *  can not be resized.
 *
 */
static VALUE
io_buffer_resize(VALUE self, VALUE size)
{
    rb_io_buffer_resize(self, NUM2SIZET(size));

    return self;
}

/*
 * call-seq: <=>(other) -> true or false
 *
 * Buffers are compared by size and exact contents of the memory they are
 * referencing using +memcmp+.
 *
 */
static VALUE
rb_io_buffer_compare(VALUE self, VALUE other)
{
    const void *ptr1, *ptr2;
    size_t size1, size2;

    rb_io_buffer_get_bytes_for_reading(self, &ptr1, &size1);
    rb_io_buffer_get_bytes_for_reading(other, &ptr2, &size2);

    if (size1 < size2) {
        return RB_INT2NUM(-1);
    }

    if (size1 > size2) {
        return RB_INT2NUM(1);
    }

    return RB_INT2NUM(memcmp(ptr1, ptr2, size1));
}

static void
io_buffer_validate_type(size_t size, size_t offset)
{
    if (offset > size) {
        rb_raise(rb_eArgError, "Type extends beyond end of buffer!");
    }
}

// Lower case: little endian.
// Upper case: big endian (network endian).
//
// :U8        | unsigned 8-bit integer.
// :S8        | signed 8-bit integer.
//
// :u16, :U16 | unsigned 16-bit integer.
// :s16, :S16 | signed 16-bit integer.
//
// :u32, :U32 | unsigned 32-bit integer.
// :s32, :S32 | signed 32-bit integer.
//
// :u64, :U64 | unsigned 64-bit integer.
// :s64, :S64 | signed 64-bit integer.
//
// :f32, :F32 | 32-bit floating point number.
// :f64, :F64 | 64-bit floating point number.

#define ruby_swap8(value) value

union swapf32 {
    uint32_t integral;
    float value;
};

static float
ruby_swapf32(float value)
{
    union swapf32 swap = {.value = value};
    swap.integral = ruby_swap32(swap.integral);
    return swap.value;
}

union swapf64 {
    uint64_t integral;
    double value;
};

static double
ruby_swapf64(double value)
{
    union swapf64 swap = {.value = value};
    swap.integral = ruby_swap64(swap.integral);
    return swap.value;
}

#define DECLARE_TYPE(name, type, endian, wrap, unwrap, swap) \
static ID RB_IO_BUFFER_TYPE_##name; \
\
static VALUE \
io_buffer_read_##name(const void* base, size_t size, size_t *offset) \
{ \
    io_buffer_validate_type(size, *offset + sizeof(type)); \
    type value; \
    memcpy(&value, (char*)base + *offset, sizeof(type)); \
    if (endian != RB_IO_BUFFER_HOST_ENDIAN) value = swap(value); \
    *offset += sizeof(type); \
    return wrap(value); \
} \
\
static void \
io_buffer_write_##name(const void* base, size_t size, size_t *offset, VALUE _value) \
{ \
    io_buffer_validate_type(size, *offset + sizeof(type)); \
    type value = unwrap(_value); \
    if (endian != RB_IO_BUFFER_HOST_ENDIAN) value = swap(value); \
    memcpy((char*)base + *offset, &value, sizeof(type)); \
    *offset += sizeof(type); \
}

DECLARE_TYPE(U8, uint8_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap8)
DECLARE_TYPE(S8, int8_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap8)

DECLARE_TYPE(u16, uint16_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap16)
DECLARE_TYPE(U16, uint16_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap16)
DECLARE_TYPE(s16, int16_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap16)
DECLARE_TYPE(S16, int16_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap16)

DECLARE_TYPE(u32, uint32_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap32)
DECLARE_TYPE(U32, uint32_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap32)
DECLARE_TYPE(s32, int32_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap32)
DECLARE_TYPE(S32, int32_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap32)

DECLARE_TYPE(u64, uint64_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_ULL2NUM, RB_NUM2ULL, ruby_swap64)
DECLARE_TYPE(U64, uint64_t, RB_IO_BUFFER_BIG_ENDIAN, RB_ULL2NUM, RB_NUM2ULL, ruby_swap64)
DECLARE_TYPE(s64, int64_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_LL2NUM, RB_NUM2LL, ruby_swap64)
DECLARE_TYPE(S64, int64_t, RB_IO_BUFFER_BIG_ENDIAN, RB_LL2NUM, RB_NUM2LL, ruby_swap64)

DECLARE_TYPE(f32, float, RB_IO_BUFFER_LITTLE_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf32)
DECLARE_TYPE(F32, float, RB_IO_BUFFER_BIG_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf32)
DECLARE_TYPE(f64, double, RB_IO_BUFFER_LITTLE_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf64)
DECLARE_TYPE(F64, double, RB_IO_BUFFER_BIG_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf64)
#undef DECLARE_TYPE

VALUE
rb_io_buffer_get_value(const void* base, size_t size, ID type, size_t offset)
{
#define READ_TYPE(name) if (type == RB_IO_BUFFER_TYPE_##name) return io_buffer_read_##name(base, size, &offset);
    READ_TYPE(U8)
    READ_TYPE(S8)

    READ_TYPE(u16)
    READ_TYPE(U16)
    READ_TYPE(s16)
    READ_TYPE(S16)

    READ_TYPE(u32)
    READ_TYPE(U32)
    READ_TYPE(s32)
    READ_TYPE(S32)

    READ_TYPE(u64)
    READ_TYPE(U64)
    READ_TYPE(s64)
    READ_TYPE(S64)

    READ_TYPE(f32)
    READ_TYPE(F32)
    READ_TYPE(f64)
    READ_TYPE(F64)
#undef READ_TYPE

    rb_raise(rb_eArgError, "Invalid type name!");
}

/*
 *  call-seq: get_value(type, offset) -> numeric
 *
 *  Read from buffer a value of +type+ at +offset+. +type+ should be one
 *  of symbols:
 *
 *  * +:U8+: unsigned integer, 1 byte
 *  * +:S8+: signed integer, 1 byte
 *  * +:u16+: unsigned integer, 2 bytes, little-endian
 *  * +:U16+: unsigned integer, 2 bytes, big-endian
 *  * +:s16+: signed integer, 2 bytes, little-endian
 *  * +:S16+: signed integer, 2 bytes, big-endian
 *  * +:u32+: unsigned integer, 4 bytes, little-endian
 *  * +:U32+: unsigned integer, 4 bytes, big-endian
 *  * +:s32+: signed integer, 4 bytes, little-endian
 *  * +:S32+: signed integer, 4 bytes, big-endian
 *  * +:u64+: unsigned integer, 8 bytes, little-endian
 *  * +:U64+: unsigned integer, 8 bytes, big-endian
 *  * +:s64+: signed integer, 8 bytes, little-endian
 *  * +:S64+: signed integer, 8 bytes, big-endian
 *  * +:f32+: float, 4 bytes, little-endian
 *  * +:F32+: float, 4 bytes, big-endian
 *  * +:f64+: double, 8 bytes, little-endian
 *  * +:F64+: double, 8 bytes, big-endian
 *
 *  Example:
 *
 *    string = [1.5].pack('f')
 *    # => "\x00\x00\xC0?"
 *    IO::Buffer.for(string).get_value(:f32, 0)
 *    # => 1.5
 *
 */
static VALUE
io_buffer_get_value(VALUE self, VALUE type, VALUE _offset)
{
    const void *base;
    size_t size;
    size_t offset = NUM2SIZET(_offset);

    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    return rb_io_buffer_get_value(base, size, RB_SYM2ID(type), offset);
}

void
rb_io_buffer_set_value(const void* base, size_t size, ID type, size_t offset, VALUE value)
{
#define WRITE_TYPE(name) if (type == RB_IO_BUFFER_TYPE_##name) {io_buffer_write_##name(base, size, &offset, value); return;}
    WRITE_TYPE(U8)
    WRITE_TYPE(S8)

    WRITE_TYPE(u16)
    WRITE_TYPE(U16)
    WRITE_TYPE(s16)
    WRITE_TYPE(S16)

    WRITE_TYPE(u32)
    WRITE_TYPE(U32)
    WRITE_TYPE(s32)
    WRITE_TYPE(S32)

    WRITE_TYPE(u64)
    WRITE_TYPE(U64)
    WRITE_TYPE(s64)
    WRITE_TYPE(S64)

    WRITE_TYPE(f32)
    WRITE_TYPE(F32)
    WRITE_TYPE(f64)
    WRITE_TYPE(F64)
#undef WRITE_TYPE

    rb_raise(rb_eArgError, "Invalid type name!");
}

/*
 *  call-seq: set_value(type, offset, value) -> offset
 *
 *  Write to a buffer a +value+ of +type+ at +offset+. +type+ should be one of
 *  symbols described in #get_value.
 *
 *    buffer = IO::Buffer.new(8)
 *    #  =>
 *    # #<IO::Buffer 0x0000555f5c9a2d50+8 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00
 *    buffer.set_value(:U8, 1, 111)
 *    # => 1
 *    buffer
 *    #  =>
 *    # #<IO::Buffer 0x0000555f5c9a2d50+8 INTERNAL>
 *    # 0x00000000  00 6f 00 00 00 00 00 00                         .o......
 *
 *  Note that if the +type+ is integer and +value+ is Float, the implicit truncation is performed:
 *
 *    buffer = IO::Buffer.new(8)
 *    buffer.set_value(:U32, 0, 2.5)
 *    buffer
 *    #   =>
 *    #  #<IO::Buffer 0x0000555f5c9a2d50+8 INTERNAL>
 *    #  0x00000000  00 00 00 02 00 00 00 00
 *    #                       ^^ the same as if we'd pass just integer 2
 */
static VALUE
io_buffer_set_value(VALUE self, VALUE type, VALUE _offset, VALUE value)
{
    void *base;
    size_t size;
    size_t offset = NUM2SIZET(_offset);

    rb_io_buffer_get_bytes_for_writing(self, &base, &size);

    rb_io_buffer_set_value(base, size, RB_SYM2ID(type), offset, value);

    return SIZET2NUM(offset);
}

static void
io_buffer_memcpy(struct rb_io_buffer *data, size_t offset, const void *source_base, size_t source_offset, size_t source_size, size_t length)
{
    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(data, &base, &size);

    io_buffer_validate_range(data, offset, length);

    if (source_offset + length > source_size) {
        rb_raise(rb_eArgError, "The computed source range exceeds the size of the source!");
    }

    memcpy((unsigned char*)base+offset, (unsigned char*)source_base+source_offset, length);
}

// (offset, length, source_offset) -> length
static VALUE
io_buffer_copy_from(struct rb_io_buffer *data, const void *source_base, size_t source_size, int argc, VALUE *argv)
{
    size_t offset;
    size_t length;
    size_t source_offset;

    // The offset we copy into the buffer:
    if (argc >= 1) {
        offset = NUM2SIZET(argv[0]);
    } else {
        offset = 0;
    }

    // The offset we start from within the string:
    if (argc >= 3) {
        source_offset = NUM2SIZET(argv[2]);

        if (source_offset > source_size) {
            rb_raise(rb_eArgError, "The given source offset is bigger than the source itself!");
        }
    } else {
        source_offset = 0;
    }

    // The length we are going to copy:
    if (argc >= 2 && !RB_NIL_P(argv[1])) {
        length = NUM2SIZET(argv[1]);
    } else {
        // Default to the source offset -> source size:
        length = source_size - source_offset;
    }

    io_buffer_memcpy(data, offset, source_base, source_offset, source_size, length);

    return SIZET2NUM(length);
}

/*
 *  call-seq:
 *    copy(source, [offset, [length, [source_offset]]]) -> size
 *
 *  Efficiently copy data from a source IO::Buffer into the buffer,
 *  at +offset+ using +memcpy+. For copying String instances, see #set_string.
 *
 *    buffer = IO::Buffer.new(32)
 *    #  =>
 *    # #<IO::Buffer 0x0000555f5ca22520+32 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ................
 *    # 0x00000010  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ................  *
 *
 *    buffer.copy(IO::Buffer.for("test"), 8)
 *    # => 4 -- size of data copied
 *    buffer
 *    #  =>
 *    # #<IO::Buffer 0x0000555f5cf8fe40+32 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00 74 65 73 74 00 00 00 00 ........test....
 *    # 0x00000010  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ................ *
 *
 *  #copy can be used to put data into strings associated with buffer:
 *
 *    string= "data:    "
 *    # => "data:    "
 *    buffer = IO::Buffer.for(str)
 *    buffer.copy(IO::Buffer.for("test"), 5)
 *    # => 4
 *    string
 *    # => "data:test"
 *
 *  Attempt to copy into a read-only buffer will fail:
 *
 *    File.write('test.txt', 'test')
 *    buffer = IO::Buffer.map(File.open('test.txt'), nil, 0, IO::Buffer::READONLY)
 *    buffer.copy(IO::Buffer.for("test"), 8)
 *    # in `copy': Buffer is not writable! (IO::Buffer::AccessError)
 *
 *  See ::map for details of creation of mutable file mappings, this will
 *  work:
 *
 *    buffer = IO::Buffer.map(File.open('test.txt', 'r+'))
 *    buffer.copy("boom", 0)
 *    # => 4
 *    File.read('test.txt')
 *    # => "boom"
 *
 *  Attempt to copy the data which will need place outside of buffer's
 *  bounds will fail:
 *
 *    buffer = IO::Buffer.new(2)
 *    buffer.copy('test', 0)
 *    # in `copy': Specified offset+length exceeds source size! (ArgumentError)
 *
 */
static VALUE
io_buffer_copy(int argc, VALUE *argv, VALUE self)
{
    if (argc < 1 || argc > 4) rb_error_arity(argc, 1, 4);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE source = argv[0];
    const void *source_base;
    size_t source_size;

    rb_io_buffer_get_bytes_for_reading(source, &source_base, &source_size);

    return io_buffer_copy_from(data, source_base, source_size, argc-1, argv+1);
}

/*
 *  call-seq: get_string([offset, [length, [encoding]]]) -> string
 *
 *  Read a chunk or all of the buffer into a string, in the specified
 *  +encoding+. If no encoding is provided +Encoding::BINARY+ is used.
 *
 *
 *     buffer = IO::Buffer.for('test')
 *     buffer.get_string
 *     # => "test"
 *     buffer.get_string(2)
 *     # => "st"
 *     buffer.get_string(2, 1)
 *     # => "s"
 *
 */
static VALUE
io_buffer_get_string(int argc, VALUE *argv, VALUE self)
{
    if (argc > 3) rb_error_arity(argc, 0, 3);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    const void *base;
    size_t size;
    io_buffer_get_bytes_for_reading(data, &base, &size);

    size_t offset = 0;
    size_t length = size;
    rb_encoding *encoding = rb_ascii8bit_encoding();

    if (argc >= 1) {
        offset = NUM2SIZET(argv[0]);
    }

    if (argc >= 2 && !RB_NIL_P(argv[1])) {
        length = NUM2SIZET(argv[1]);
    } else {
        length = size - offset;
    }

    if (argc >= 3) {
        encoding = rb_find_encoding(argv[2]);
    }

    io_buffer_validate_range(data, offset, length);

    return rb_enc_str_new((const char*)base + offset, length, encoding);
}

static VALUE
io_buffer_set_string(int argc, VALUE *argv, VALUE self)
{
    if (argc < 1 || argc > 4) rb_error_arity(argc, 1, 4);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE string = rb_str_to_str(argv[0]);

    const void *source_base = RSTRING_PTR(string);
    size_t source_size = RSTRING_LEN(string);

    return io_buffer_copy_from(data, source_base, source_size, argc-1, argv+1);
}

void
rb_io_buffer_clear(VALUE self, uint8_t value, size_t offset, size_t length)
{
    void *base;
    size_t size;

    rb_io_buffer_get_bytes_for_writing(self, &base, &size);

    if (offset + length > size) {
        rb_raise(rb_eArgError, "The given offset + length out of bounds!");
    }

    memset((char*)base + offset, value, length);
}

/*
 *  call-seq: clear(value = 0, [offset, [length]]) -> self
 *
 *  Fill buffer with +value+, starting with +offset+ and going for +length+
 *  bytes.
 *
 *    buffer = IO::Buffer.for('test')
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *    #   0x00000000  74 65 73 74         test
 *
 *    buffer.clear
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *    #   0x00000000  00 00 00 00         ....
 *
 *    buf.clear(1) # fill with 1
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *    #   0x00000000  01 01 01 01         ....
 *
 *    buffer.clear(2, 1, 2) # fill with 2, starting from offset 1, for 2 bytes
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *    #   0x00000000  01 02 02 01         ....
 *
 *    buffer.clear(2, 1) # fill with 2, starting from offset 1
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *    #   0x00000000  01 02 02 02         ....
 *
 */
static VALUE
io_buffer_clear(int argc, VALUE *argv, VALUE self)
{
    if (argc > 3) rb_error_arity(argc, 0, 3);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    uint8_t value = 0;
    if (argc >= 1) {
        value = NUM2UINT(argv[0]);
    }

    size_t offset = 0;
    if (argc >= 2) {
        offset = NUM2SIZET(argv[1]);
    }

    size_t length;
    if (argc >= 3) {
        length = NUM2SIZET(argv[2]);
    } else {
        length = data->size - offset;
    }

    rb_io_buffer_clear(self, value, offset, length);

    return self;
}

static
size_t io_buffer_default_size(size_t page_size) {
    // Platform agnostic default size, based on empirical performance observation:
    const size_t platform_agnostic_default_size = 64*1024;

    // Allow user to specify custom default buffer size:
    const char *default_size = getenv("RUBY_IO_BUFFER_DEFAULT_SIZE");
    if (default_size) {
        // For the purpose of setting a default size, 2^31 is an acceptable maximum:
        int value = atoi(default_size);

        // assuming sizeof(int) <= sizeof(size_t)
        if (value > 0) {
            return value;
        }
    }

    if (platform_agnostic_default_size < page_size) {
        return page_size;
    }

    return platform_agnostic_default_size;
}

VALUE
rb_io_buffer_read(VALUE self, VALUE io, size_t length)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_read(scheduler, io, self, length);

        if (result != Qundef) {
            return result;
        }
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_validate_range(data, 0, length);

    int descriptor = rb_io_descriptor(io);

    void * base;
    size_t size;
    io_buffer_get_bytes_for_writing(data, &base, &size);

    ssize_t result = read(descriptor, base, size);

    return rb_fiber_scheduler_io_result(result, errno);
}

static VALUE
io_buffer_read(VALUE self, VALUE io, VALUE length)
{
    return rb_io_buffer_read(self, io, RB_NUM2SIZE(length));
}

VALUE
rb_io_buffer_pread(VALUE self, VALUE io, size_t length, off_t offset)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_pread(scheduler, io, self, length, offset);

        if (result != Qundef) {
            return result;
        }
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_validate_range(data, 0, length);

    int descriptor = rb_io_descriptor(io);

    void * base;
    size_t size;
    io_buffer_get_bytes_for_writing(data, &base, &size);

#if defined(HAVE_PREAD)
    ssize_t result = pread(descriptor, base, size, offset);
#else
    // This emulation is not thread safe, but the GVL means it's unlikely to be a problem.
    off_t current_offset = lseek(descriptor, 0, SEEK_CUR);
    if (current_offset == (off_t)-1)
        return rb_fiber_scheduler_io_result(-1, errno);

    if (lseek(descriptor, offset, SEEK_SET) == (off_t)-1)
        return rb_fiber_scheduler_io_result(-1, errno);

    ssize_t result = read(descriptor, base, size);

    if (lseek(descriptor, current_offset, SEEK_SET) == (off_t)-1)
        return rb_fiber_scheduler_io_result(-1, errno);
#endif

    return rb_fiber_scheduler_io_result(result, errno);
}

static VALUE
io_buffer_pread(VALUE self, VALUE io, VALUE length, VALUE offset)
{
    return rb_io_buffer_pread(self, io, RB_NUM2SIZE(length), NUM2OFFT(offset));
}

VALUE
rb_io_buffer_write(VALUE self, VALUE io, size_t length)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_write(scheduler, io, self, length);

        if (result != Qundef) {
            return result;
        }
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_validate_range(data, 0, length);

    int descriptor = rb_io_descriptor(io);

    const void * base;
    size_t size;
    io_buffer_get_bytes_for_reading(data, &base, &size);

    ssize_t result = write(descriptor, base, length);

    return rb_fiber_scheduler_io_result(result, errno);
}

static VALUE
io_buffer_write(VALUE self, VALUE io, VALUE length)
{
    return rb_io_buffer_write(self, io, RB_NUM2SIZE(length));
}

VALUE
rb_io_buffer_pwrite(VALUE self, VALUE io, size_t length, off_t offset)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_pwrite(scheduler, io, self, length, OFFT2NUM(offset));

        if (result != Qundef) {
            return result;
        }
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_validate_range(data, 0, length);

    int descriptor = rb_io_descriptor(io);

    const void * base;
    size_t size;
    io_buffer_get_bytes_for_reading(data, &base, &size);

#if defined(HAVE_PWRITE)
    ssize_t result = pwrite(descriptor, base, length, offset);
#else
    // This emulation is not thread safe, but the GVL means it's unlikely to be a problem.
    off_t current_offset = lseek(descriptor, 0, SEEK_CUR);
    if (current_offset == (off_t)-1)
        return rb_fiber_scheduler_io_result(-1, errno);

    if (lseek(descriptor, offset, SEEK_SET) == (off_t)-1)
        return rb_fiber_scheduler_io_result(-1, errno);

    ssize_t result = write(descriptor, base, length);

    if (lseek(descriptor, current_offset, SEEK_SET) == (off_t)-1)
        return rb_fiber_scheduler_io_result(-1, errno);
#endif

    return rb_fiber_scheduler_io_result(result, errno);
}

static VALUE
io_buffer_pwrite(VALUE self, VALUE io, VALUE length, VALUE offset)
{
    return rb_io_buffer_pwrite(self, io, RB_NUM2SIZE(length), NUM2OFFT(offset));
}

/*
 *  Document-class: IO::Buffer
 *
 *  IO::Buffer is a low-level efficient buffer for input/output. There are three
 *  ways of using buffer:
 *
 *  * Create an empty buffer with ::new, fill it with data using #copy or
 *    #set_value, #set_string, get data with #get_string;
 *  * Create a buffer mapped to some string with ::for, then it could be used
 *    both for reading with #get_string or #get_value, and writing (writing will
 *    change the source string, too);
 *  * Create a buffer mapped to some file with ::map, then it could be used for
 *    reading and writing the underlying file.
 *
 *  Interaction with string and file memory is performed by efficient low-level
 *  C mechanisms like `memcpy`.
 *
 *  The class is meant to be an utility for implementing more high-level mechanisms
 *  like Fiber::SchedulerInterface#io_read and Fiber::SchedulerInterface#io_write.
 *
 *  <b>Examples of usage:</b>
 *
 *  Empty buffer:
 *
 *    buffer = IO::Buffer.new(8)  # create empty 8-byte buffer
 *    #  =>
 *    # #<IO::Buffer 0x0000555f5d1a5c50+8 INTERNAL>
 *    # ...
 *    buffer
 *    #  =>
 *    # <IO::Buffer 0x0000555f5d156ab0+8 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00
 *    buffer.set_string('test', 2) # put there bytes of the "test" string, starting from offset 2
 *    # => 4
 *    buffer.get_string  # get the result
 *    # => "\x00\x00test\x00\x00"
 *
 *  \Buffer from string:
 *
 *    string = 'data'
 *    buffer = IO::Buffer.for(str)
 *    #  =>
 *    # #<IO::Buffer 0x00007f3f02be9b18+4 SLICE>
 *    # ...
 *    buffer
 *    #  =>
 *    # #<IO::Buffer 0x00007f3f02be9b18+4 SLICE>
 *    # 0x00000000  64 61 74 61                                     data
 *
 *    buffer.get_string(2)  # read content starting from offset 2
 *    # => "ta"
 *    buffer.set_string('---', 1) # write content, starting from offset 1
 *    # => 3
 *    buffer
 *    #  =>
 *    # #<IO::Buffer 0x00007f3f02be9b18+4 SLICE>
 *    # 0x00000000  64 2d 2d 2d                                     d---
 *    string  # original string changed, too
 *    # => "d---"
 *
 *  \Buffer from file:
 *
 *    File.write('test.txt', 'test data')
 *    # => 9
 *    buffer = IO::Buffer.map(File.open('test.txt'))
 *    #  =>
 *    # #<IO::Buffer 0x00007f3f0768c000+9 MAPPED IMMUTABLE>
 *    # ...
 *    buffer.get_string(5, 2) # read 2 bytes, starting from offset 5
 *    # => "da"
 *    buffer.set_string('---', 1) # attempt to write
 *    # in `set_string': Buffer is not writable! (IO::Buffer::AccessError)
 *
 *    # To create writable file-mapped buffer
 *    # Open file for read-write, pass size, offset, and flags=0
 *    buffer = IO::Buffer.map(File.open('test.txt', 'r+'), 9, 0, 0)
 *    buffer.set_string('---', 1)
 *    # => 3 -- bytes written
 *    File.read('test.txt')
 *    # => "t--- data"
 *
 *  <b>The class is experimental and the interface is subject to change.</b>
 */
void
Init_IO_Buffer(void)
{
    rb_cIOBuffer = rb_define_class_under(rb_cIO, "Buffer", rb_cObject);
    rb_eIOBufferLockedError = rb_define_class_under(rb_cIOBuffer, "LockedError", rb_eRuntimeError);
    rb_eIOBufferAllocationError = rb_define_class_under(rb_cIOBuffer, "AllocationError", rb_eRuntimeError);
    rb_eIOBufferAccessError = rb_define_class_under(rb_cIOBuffer, "AccessError", rb_eRuntimeError);
    rb_eIOBufferInvalidatedError = rb_define_class_under(rb_cIOBuffer, "InvalidatedError", rb_eRuntimeError);

    rb_define_alloc_func(rb_cIOBuffer, rb_io_buffer_type_allocate);
    rb_define_singleton_method(rb_cIOBuffer, "for", rb_io_buffer_type_for, 1);

#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    RUBY_IO_BUFFER_PAGE_SIZE = info.dwPageSize;
#else /* not WIN32 */
    RUBY_IO_BUFFER_PAGE_SIZE = sysconf(_SC_PAGESIZE);
#endif

    RUBY_IO_BUFFER_DEFAULT_SIZE = io_buffer_default_size(RUBY_IO_BUFFER_PAGE_SIZE);

    // Efficient sizing of mapped buffers:
    rb_define_const(rb_cIOBuffer, "PAGE_SIZE", SIZET2NUM(RUBY_IO_BUFFER_PAGE_SIZE));
    rb_define_const(rb_cIOBuffer, "DEFAULT_SIZE", SIZET2NUM(RUBY_IO_BUFFER_DEFAULT_SIZE));

    rb_define_singleton_method(rb_cIOBuffer, "map", io_buffer_map, -1);

    // General use:
    rb_define_method(rb_cIOBuffer, "initialize", rb_io_buffer_initialize, -1);
    rb_define_method(rb_cIOBuffer, "inspect", rb_io_buffer_inspect, 0);
    rb_define_method(rb_cIOBuffer, "hexdump", rb_io_buffer_hexdump, 0);
    rb_define_method(rb_cIOBuffer, "to_s", rb_io_buffer_to_s, 0);
    rb_define_method(rb_cIOBuffer, "size", rb_io_buffer_size, 0);
    rb_define_method(rb_cIOBuffer, "valid?", rb_io_buffer_valid_p, 0);

    // Ownership:
    rb_define_method(rb_cIOBuffer, "transfer", rb_io_buffer_transfer, 0);

    // Flags:
    rb_define_const(rb_cIOBuffer, "EXTERNAL", RB_INT2NUM(RB_IO_BUFFER_EXTERNAL));
    rb_define_const(rb_cIOBuffer, "INTERNAL", RB_INT2NUM(RB_IO_BUFFER_INTERNAL));
    rb_define_const(rb_cIOBuffer, "MAPPED", RB_INT2NUM(RB_IO_BUFFER_MAPPED));
    rb_define_const(rb_cIOBuffer, "LOCKED", RB_INT2NUM(RB_IO_BUFFER_LOCKED));
    rb_define_const(rb_cIOBuffer, "PRIVATE", RB_INT2NUM(RB_IO_BUFFER_PRIVATE));
    rb_define_const(rb_cIOBuffer, "READONLY", RB_INT2NUM(RB_IO_BUFFER_READONLY));

    // Endian:
    rb_define_const(rb_cIOBuffer, "LITTLE_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_LITTLE_ENDIAN));
    rb_define_const(rb_cIOBuffer, "BIG_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_BIG_ENDIAN));
    rb_define_const(rb_cIOBuffer, "HOST_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_HOST_ENDIAN));
    rb_define_const(rb_cIOBuffer, "NETWORK_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_NETWORK_ENDIAN));

    rb_define_method(rb_cIOBuffer, "null?", rb_io_buffer_null_p, 0);
    rb_define_method(rb_cIOBuffer, "empty?", rb_io_buffer_empty_p, 0);
    rb_define_method(rb_cIOBuffer, "external?", rb_io_buffer_external_p, 0);
    rb_define_method(rb_cIOBuffer, "internal?", rb_io_buffer_internal_p, 0);
    rb_define_method(rb_cIOBuffer, "mapped?", rb_io_buffer_mapped_p, 0);
    rb_define_method(rb_cIOBuffer, "locked?", rb_io_buffer_locked_p, 0);
    rb_define_method(rb_cIOBuffer, "readonly?", io_buffer_readonly_p, 0);

    // Locking to prevent changes while using pointer:
    // rb_define_method(rb_cIOBuffer, "lock", rb_io_buffer_lock, 0);
    // rb_define_method(rb_cIOBuffer, "unlock", rb_io_buffer_unlock, 0);
    rb_define_method(rb_cIOBuffer, "locked", rb_io_buffer_locked, 0);

    // Manipulation:
    rb_define_method(rb_cIOBuffer, "slice", rb_io_buffer_slice, 2);
    rb_define_method(rb_cIOBuffer, "<=>", rb_io_buffer_compare, 1);
    rb_define_method(rb_cIOBuffer, "resize", io_buffer_resize, 1);
    rb_define_method(rb_cIOBuffer, "clear", io_buffer_clear, -1);
    rb_define_method(rb_cIOBuffer, "free", rb_io_buffer_free, 0);

    rb_include_module(rb_cIOBuffer, rb_mComparable);

#define DEFINE_TYPE(name) RB_IO_BUFFER_TYPE_##name = rb_intern_const(#name)
    DEFINE_TYPE(U8); DEFINE_TYPE(S8);
    DEFINE_TYPE(u16); DEFINE_TYPE(U16); DEFINE_TYPE(s16); DEFINE_TYPE(S16);
    DEFINE_TYPE(u32); DEFINE_TYPE(U32); DEFINE_TYPE(s32); DEFINE_TYPE(S32);
    DEFINE_TYPE(u64); DEFINE_TYPE(U64); DEFINE_TYPE(s64); DEFINE_TYPE(S64);
    DEFINE_TYPE(f32); DEFINE_TYPE(F32); DEFINE_TYPE(f64); DEFINE_TYPE(F64);
#undef DEFINE_TYPE

    // Data access:
    rb_define_method(rb_cIOBuffer, "get_value", io_buffer_get_value, 2);
    rb_define_method(rb_cIOBuffer, "set_value", io_buffer_set_value, 3);

    rb_define_method(rb_cIOBuffer, "copy", io_buffer_copy, -1);

    rb_define_method(rb_cIOBuffer, "get_string", io_buffer_get_string, -1);
    rb_define_method(rb_cIOBuffer, "set_string", io_buffer_set_string, -1);

    // IO operations:
    rb_define_method(rb_cIOBuffer, "read", io_buffer_read, 2);
    rb_define_method(rb_cIOBuffer, "pread", io_buffer_pread, 3);
    rb_define_method(rb_cIOBuffer, "write", io_buffer_write, 2);
    rb_define_method(rb_cIOBuffer, "pwrite", io_buffer_pwrite, 3);
}
