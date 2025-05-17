/**********************************************************************

  io_buffer.c

  Copyright (C) 2021 Samuel Grant Dawson Williams

**********************************************************************/

#include "ruby/io/buffer.h"
#include "ruby/fiber/scheduler.h"

// For `rb_nogvl`.
#include "ruby/thread.h"

#include "internal.h"
#include "internal/array.h"
#include "internal/bits.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/numeric.h"
#include "internal/string.h"
#include "internal/io.h"

VALUE rb_cIOBuffer;
VALUE rb_eIOBufferLockedError;
VALUE rb_eIOBufferAllocationError;
VALUE rb_eIOBufferAccessError;
VALUE rb_eIOBufferInvalidatedError;
VALUE rb_eIOBufferMaskError;

size_t RUBY_IO_BUFFER_PAGE_SIZE;
size_t RUBY_IO_BUFFER_DEFAULT_SIZE;

#ifdef _WIN32
#else
#include <unistd.h>
#include <sys/mman.h>
#endif

enum {
    RB_IO_BUFFER_HEXDUMP_DEFAULT_WIDTH = 16,

    RB_IO_BUFFER_INSPECT_HEXDUMP_MAXIMUM_SIZE = 256,
    RB_IO_BUFFER_INSPECT_HEXDUMP_WIDTH = 16,

    // This is used to validate the flags given by the user.
    RB_IO_BUFFER_FLAGS_MASK = RB_IO_BUFFER_EXTERNAL | RB_IO_BUFFER_INTERNAL | RB_IO_BUFFER_MAPPED | RB_IO_BUFFER_SHARED | RB_IO_BUFFER_LOCKED | RB_IO_BUFFER_PRIVATE | RB_IO_BUFFER_READONLY,

    RB_IO_BUFFER_DEBUG = 0,
};

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
io_buffer_map_memory(size_t size, int flags)
{
#if defined(_WIN32)
    void * base = VirtualAlloc(0, size, MEM_COMMIT, PAGE_READWRITE);

    if (!base) {
        rb_sys_fail("io_buffer_map_memory:VirtualAlloc");
    }
#else
    int mmap_flags = MAP_ANONYMOUS;
    if (flags & RB_IO_BUFFER_SHARED) {
        mmap_flags |= MAP_SHARED;
    }
    else {
        mmap_flags |= MAP_PRIVATE;
    }

    void * base = mmap(NULL, size, PROT_READ | PROT_WRITE, mmap_flags, -1, 0);

    if (base == MAP_FAILED) {
        rb_sys_fail("io_buffer_map_memory:mmap");
    }

    ruby_annotate_mmap(base, size, "Ruby:io_buffer_map_memory");
#endif

    return base;
}

static void
io_buffer_map_file(struct rb_io_buffer *buffer, int descriptor, size_t size, rb_off_t offset, enum rb_io_buffer_flags flags)
{
#if defined(_WIN32)
    HANDLE file = (HANDLE)_get_osfhandle(descriptor);
    if (!file) rb_sys_fail("io_buffer_map_descriptor:_get_osfhandle");

    DWORD protect = PAGE_READONLY, access = FILE_MAP_READ;

    if (flags & RB_IO_BUFFER_READONLY) {
        buffer->flags |= RB_IO_BUFFER_READONLY;
    }
    else {
        protect = PAGE_READWRITE;
        access = FILE_MAP_WRITE;
    }

    if (flags & RB_IO_BUFFER_PRIVATE) {
        protect = PAGE_WRITECOPY;
        access = FILE_MAP_COPY;
        buffer->flags |= RB_IO_BUFFER_PRIVATE;
    }
    else {
        // This buffer refers to external buffer.
        buffer->flags |= RB_IO_BUFFER_EXTERNAL;
        buffer->flags |= RB_IO_BUFFER_SHARED;
    }

    HANDLE mapping = CreateFileMapping(file, NULL, protect, 0, 0, NULL);
    if (RB_IO_BUFFER_DEBUG) fprintf(stderr, "io_buffer_map_file:CreateFileMapping -> %p\n", mapping);
    if (!mapping) rb_sys_fail("io_buffer_map_descriptor:CreateFileMapping");

    void *base = MapViewOfFile(mapping, access, (DWORD)(offset >> 32), (DWORD)(offset & 0xFFFFFFFF), size);

    if (!base) {
        CloseHandle(mapping);
        rb_sys_fail("io_buffer_map_file:MapViewOfFile");
    }

    buffer->mapping = mapping;
#else
    int protect = PROT_READ, access = 0;

    if (flags & RB_IO_BUFFER_READONLY) {
        buffer->flags |= RB_IO_BUFFER_READONLY;
    }
    else {
        protect |= PROT_WRITE;
    }

    if (flags & RB_IO_BUFFER_PRIVATE) {
        buffer->flags |= RB_IO_BUFFER_PRIVATE;
        access |= MAP_PRIVATE;
    }
    else {
        // This buffer refers to external buffer.
        buffer->flags |= RB_IO_BUFFER_EXTERNAL;
        buffer->flags |= RB_IO_BUFFER_SHARED;
        access |= MAP_SHARED;
    }

    void *base = mmap(NULL, size, protect, access, descriptor, offset);

    if (base == MAP_FAILED) {
        rb_sys_fail("io_buffer_map_file:mmap");
    }
#endif

    buffer->base = base;
    buffer->size = size;

    buffer->flags |= RB_IO_BUFFER_MAPPED;
    buffer->flags |= RB_IO_BUFFER_FILE;
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
io_buffer_zero(struct rb_io_buffer *buffer)
{
    buffer->base = NULL;
    buffer->size = 0;
#if defined(_WIN32)
    buffer->mapping = NULL;
#endif
    buffer->source = Qnil;
}

static void
io_buffer_initialize(VALUE self, struct rb_io_buffer *buffer, void *base, size_t size, enum rb_io_buffer_flags flags, VALUE source)
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
            base = io_buffer_map_memory(size, flags);
        }

        if (!base) {
            rb_raise(rb_eIOBufferAllocationError, "Could not allocate buffer!");
        }
    }
    else {
        // Otherwise we don't do anything.
        return;
    }

    buffer->base = base;
    buffer->size = size;
    buffer->flags = flags;
    RB_OBJ_WRITE(self, &buffer->source, source);

#if defined(_WIN32)
    buffer->mapping = NULL;
#endif
}

static void
io_buffer_free(struct rb_io_buffer *buffer)
{
    if (buffer->base) {
        if (buffer->flags & RB_IO_BUFFER_INTERNAL) {
            free(buffer->base);
        }

        if (buffer->flags & RB_IO_BUFFER_MAPPED) {
#ifdef _WIN32
            if (buffer->flags & RB_IO_BUFFER_FILE) {
                UnmapViewOfFile(buffer->base);
            }
            else {
                VirtualFree(buffer->base, 0, MEM_RELEASE);
            }
#else
            munmap(buffer->base, buffer->size);
#endif
        }

        // Previously we had this, but we found out due to the way GC works, we
        // can't refer to any other Ruby objects here.
        // if (RB_TYPE_P(buffer->source, T_STRING)) {
        //     rb_str_unlocktmp(buffer->source);
        // }

        buffer->base = NULL;

        buffer->size = 0;
        buffer->flags = 0;
        buffer->source = Qnil;
    }

#if defined(_WIN32)
    if (buffer->mapping) {
        if (RB_IO_BUFFER_DEBUG) fprintf(stderr, "io_buffer_free:CloseHandle -> %p\n", buffer->mapping);
        if (!CloseHandle(buffer->mapping)) {
            fprintf(stderr, "io_buffer_free:GetLastError -> %lu\n", GetLastError());
        }
        buffer->mapping = NULL;
    }
#endif
}

static void
rb_io_buffer_type_free(void *_buffer)
{
    struct rb_io_buffer *buffer = _buffer;

    io_buffer_free(buffer);
}

static size_t
rb_io_buffer_type_size(const void *_buffer)
{
    const struct rb_io_buffer *buffer = _buffer;
    size_t total = sizeof(struct rb_io_buffer);

    if (buffer->flags) {
        total += buffer->size;
    }

    return total;
}

RUBY_REFERENCES(io_buffer_refs) = {
    RUBY_REF_EDGE(struct rb_io_buffer, source),
    RUBY_REF_END
};

static const rb_data_type_t rb_io_buffer_type = {
    .wrap_struct_name = "IO::Buffer",
    .function = {
        .dmark = RUBY_REFS_LIST_PTR(io_buffer_refs),
        .dfree = rb_io_buffer_type_free,
        .dsize = rb_io_buffer_type_size,
    },
    .data = NULL,
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE | RUBY_TYPED_DECL_MARKING,
};

static inline enum rb_io_buffer_flags
io_buffer_extract_flags(VALUE argument)
{
    if (rb_int_negative_p(argument)) {
        rb_raise(rb_eArgError, "Flags can't be negative!");
    }

    enum rb_io_buffer_flags flags = RB_NUM2UINT(argument);

    // We deliberately ignore unknown flags. Any future flags which are exposed this way should be safe to ignore.
    return flags & RB_IO_BUFFER_FLAGS_MASK;
}

// Extract an offset argument, which must be a non-negative integer.
static inline size_t
io_buffer_extract_offset(VALUE argument)
{
    if (rb_int_negative_p(argument)) {
        rb_raise(rb_eArgError, "Offset can't be negative!");
    }

    return NUM2SIZET(argument);
}

// Extract a length argument, which must be a non-negative integer.
// Length is generally considered a mutable property of an object and
// semantically should be considered a subset of "size" as a concept.
static inline size_t
io_buffer_extract_length(VALUE argument)
{
    if (rb_int_negative_p(argument)) {
        rb_raise(rb_eArgError, "Length can't be negative!");
    }

    return NUM2SIZET(argument);
}

// Extract a size argument, which must be a non-negative integer.
// Size is generally considered an immutable property of an object.
static inline size_t
io_buffer_extract_size(VALUE argument)
{
    if (rb_int_negative_p(argument)) {
        rb_raise(rb_eArgError, "Size can't be negative!");
    }

    return NUM2SIZET(argument);
}

// Extract a width argument, which must be a non-negative integer, and must be
// at least the given minimum.
static inline size_t
io_buffer_extract_width(VALUE argument, size_t minimum)
{
    if (rb_int_negative_p(argument)) {
        rb_raise(rb_eArgError, "Width can't be negative!");
    }

    size_t width = NUM2SIZET(argument);

    if (width < minimum) {
        rb_raise(rb_eArgError, "Width must be at least %" PRIuSIZE "!", minimum);
    }

    return width;
}

// Compute the default length for a buffer, given an offset into that buffer.
// The default length is the size of the buffer minus the offset. The offset
// must be less than the size of the buffer otherwise the length will be
// invalid; in that case, an ArgumentError exception will be raised.
static inline size_t
io_buffer_default_length(const struct rb_io_buffer *buffer, size_t offset)
{
    if (offset > buffer->size) {
        rb_raise(rb_eArgError, "The given offset is bigger than the buffer size!");
    }

    // Note that the "length" is computed by the size the offset.
    return buffer->size - offset;
}

// Extract the optional length and offset arguments, returning the buffer.
// The length and offset are optional, but if they are provided, they must be
// positive integers. If the length is not provided, the default length is
// computed from the buffer size and offset. If the offset is not provided, it
// defaults to zero.
static inline struct rb_io_buffer *
io_buffer_extract_length_offset(VALUE self, int argc, VALUE argv[], size_t *length, size_t *offset)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (argc >= 2 && !NIL_P(argv[1])) {
        *offset = io_buffer_extract_offset(argv[1]);
    }
    else {
        *offset = 0;
    }

    if (argc >= 1 && !NIL_P(argv[0])) {
        *length = io_buffer_extract_length(argv[0]);
    }
    else {
        *length = io_buffer_default_length(buffer, *offset);
    }

    return buffer;
}

// Extract the optional offset and length arguments, returning the buffer.
// Similar to `io_buffer_extract_length_offset` but with the order of arguments
// reversed.
//
// After much consideration, I decided to accept both forms.
// The `(offset, length)` order is more natural when referring about data,
// while the `(length, offset)` order is more natural when referring to
// read/write operations. In many cases, with the latter form, `offset`
// is usually not supplied.
static inline struct rb_io_buffer *
io_buffer_extract_offset_length(VALUE self, int argc, VALUE argv[], size_t *offset, size_t *length)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (argc >= 1 && !NIL_P(argv[0])) {
        *offset = io_buffer_extract_offset(argv[0]);
    }
    else {
        *offset = 0;
    }

    if (argc >= 2 && !NIL_P(argv[1])) {
        *length = io_buffer_extract_length(argv[1]);
    }
    else {
        *length = io_buffer_default_length(buffer, *offset);
    }

    return buffer;
}

VALUE
rb_io_buffer_type_allocate(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    VALUE instance = TypedData_Make_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_zero(buffer);

    return instance;
}

static VALUE io_buffer_for_make_instance(VALUE klass, VALUE string, enum rb_io_buffer_flags flags)
{
    VALUE instance = rb_io_buffer_type_allocate(klass);

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    flags |= RB_IO_BUFFER_EXTERNAL;

    if (RB_OBJ_FROZEN(string))
        flags |= RB_IO_BUFFER_READONLY;

    if (!(flags & RB_IO_BUFFER_READONLY))
        rb_str_modify(string);

    io_buffer_initialize(instance, buffer, RSTRING_PTR(string), RSTRING_LEN(string), flags, string);

    return instance;
}

struct io_buffer_for_yield_instance_arguments {
    VALUE klass;
    VALUE string;
    VALUE instance;
    enum rb_io_buffer_flags flags;
};

static VALUE
io_buffer_for_yield_instance(VALUE _arguments)
{
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
 *  Creates a zero-copy IO::Buffer from the given string's memory. Without a
 *  block a frozen internal copy of the string is created efficiently and used
 *  as the buffer source. When a block is provided, the buffer is associated
 *  directly with the string's internal buffer and updating the buffer will
 *  update the string.
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
    }
    else {
        // This internally returns the source string if it's already frozen.
        string = rb_str_tmp_frozen_acquire(string);
        return io_buffer_for_make_instance(klass, string, RB_IO_BUFFER_READONLY);
    }
}

/*
 * call-seq:
 *   IO::Buffer.string(length) {|io_buffer| ... read/write io_buffer ...} -> string
 *
 * Creates a new string of the given length and yields a zero-copy IO::Buffer
 * instance to the block which uses the string as a source. The block is
 * expected to write to the buffer and the string will be returned.
 *
 *    IO::Buffer.string(4) do |buffer|
 *      buffer.set_string("Ruby")
 *    end
 *    # => "Ruby"
 */
VALUE
rb_io_buffer_type_string(VALUE klass, VALUE length)
{
    VALUE string = rb_str_new(NULL, RB_NUM2LONG(length));

    struct io_buffer_for_yield_instance_arguments arguments = {
        .klass = klass,
        .string = string,
        .instance = Qnil,
    };

    rb_ensure(io_buffer_for_yield_instance, (VALUE)&arguments, io_buffer_for_yield_instance_ensure, (VALUE)&arguments);

    return string;
}

VALUE
rb_io_buffer_new(void *base, size_t size, enum rb_io_buffer_flags flags)
{
    VALUE instance = rb_io_buffer_type_allocate(rb_cIOBuffer);

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_initialize(instance, buffer, base, size, flags, Qnil);

    return instance;
}

VALUE
rb_io_buffer_map(VALUE io, size_t size, rb_off_t offset, enum rb_io_buffer_flags flags)
{
    io_buffer_experimental();

    VALUE instance = rb_io_buffer_type_allocate(rb_cIOBuffer);

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    int descriptor = rb_io_descriptor(io);

    io_buffer_map_file(buffer, descriptor, size, offset, flags);

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
 *    File.write('test.txt', 'test')
 *
 *    buffer = IO::Buffer.map(File.open('test.txt'), nil, 0, IO::Buffer::READONLY)
 *    # => #<IO::Buffer 0x00000001014a0000+4 MAPPED READONLY>
 *
 *    buffer.readonly?   # => true
 *
 *    buffer.get_string
 *    # => "test"
 *
 *    buffer.set_string('b', 0)
 *    # `set_string': Buffer is not writable! (IO::Buffer::AccessError)
 *
 *    # create read/write mapping: length 4 bytes, offset 0, flags 0
 *    buffer = IO::Buffer.map(File.open('test.txt', 'r+'), 4, 0)
 *    buffer.set_string('b', 0)
 *    # => 1
 *
 *    # Check it
 *    File.read('test.txt')
 *    # => "best"
 *
 *  Note that some operating systems may not have cache coherency between mapped
 *  buffers and file reads.
 */
static VALUE
io_buffer_map(int argc, VALUE *argv, VALUE klass)
{
    rb_check_arity(argc, 1, 4);

    // We might like to handle a string path?
    VALUE io = argv[0];

    size_t size;
    if (argc >= 2 && !RB_NIL_P(argv[1])) {
        size = io_buffer_extract_size(argv[1]);
    }
    else {
        rb_off_t file_size = rb_file_size(io);

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

    // This is the file offset, not the buffer offset:
    rb_off_t offset = 0;
    if (argc >= 3) {
        offset = NUM2OFFT(argv[2]);
    }

    enum rb_io_buffer_flags flags = 0;
    if (argc >= 4) {
        flags = io_buffer_extract_flags(argv[3]);
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
 *  IO::Buffer::PAGE_SIZE, the buffer would be allocated using the
 *  virtual memory mechanism (anonymous +mmap+ on Unix, +VirtualAlloc+
 *  on Windows). The behavior can be forced by passing IO::Buffer::MAPPED
 *  as a second parameter.
 *
 *    buffer = IO::Buffer.new(4)
 *    # =>
 *    # #<IO::Buffer 0x000055b34497ea10+4 INTERNAL>
 *    # 0x00000000  00 00 00 00                                     ....
 *
 *    buffer.get_string(0, 1) # => "\x00"
 *
 *    buffer.set_string("test")
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x000055b34497ea10+4 INTERNAL>
 *    # 0x00000000  74 65 73 74                                     test
 */
VALUE
rb_io_buffer_initialize(int argc, VALUE *argv, VALUE self)
{
    io_buffer_experimental();

    rb_check_arity(argc, 0, 2);

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    size_t size;
    if (argc > 0) {
        size = io_buffer_extract_size(argv[0]);
    }
    else {
        size = RUBY_IO_BUFFER_DEFAULT_SIZE;
    }

    enum rb_io_buffer_flags flags = 0;
    if (argc >= 2) {
        flags = io_buffer_extract_flags(argv[1]);
    }
    else {
        flags |= io_flags_for_size(size);
    }

    io_buffer_initialize(self, buffer, NULL, size, flags, Qnil);

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
io_buffer_validate(struct rb_io_buffer *buffer)
{
    if (buffer->source != Qnil) {
        // Only slices incur this overhead, unfortunately... better safe than sorry!
        return io_buffer_validate_slice(buffer->source, buffer->base, buffer->size);
    }
    else {
        return 1;
    }
}

enum rb_io_buffer_flags
rb_io_buffer_get_bytes(VALUE self, void **base, size_t *size)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (io_buffer_validate(buffer)) {
        if (buffer->base) {
            *base = buffer->base;
            *size = buffer->size;

            return buffer->flags;
        }
    }

    *base = NULL;
    *size = 0;

    return 0;
}

// Internal function for accessing bytes for writing, wil
static inline void
io_buffer_get_bytes_for_writing(struct rb_io_buffer *buffer, void **base, size_t *size)
{
    if (buffer->flags & RB_IO_BUFFER_READONLY ||
        (!NIL_P(buffer->source) && OBJ_FROZEN(buffer->source))) {
        rb_raise(rb_eIOBufferAccessError, "Buffer is not writable!");
    }

    if (!io_buffer_validate(buffer)) {
        rb_raise(rb_eIOBufferInvalidatedError, "Buffer is invalid!");
    }

    if (buffer->base) {
        *base = buffer->base;
        *size = buffer->size;
    } else {
        *base = NULL;
        *size = 0;
    }
}

void
rb_io_buffer_get_bytes_for_writing(VALUE self, void **base, size_t *size)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_get_bytes_for_writing(buffer, base, size);
}

static void
io_buffer_get_bytes_for_reading(struct rb_io_buffer *buffer, const void **base, size_t *size)
{
    if (!io_buffer_validate(buffer)) {
        rb_raise(rb_eIOBufferInvalidatedError, "Buffer has been invalidated!");
    }

    if (buffer->base) {
        *base = buffer->base;
        *size = buffer->size;
    } else {
        *base = NULL;
        *size = 0;
    }
}

void
rb_io_buffer_get_bytes_for_reading(VALUE self, const void **base, size_t *size)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_get_bytes_for_reading(buffer, base, size);
}

/*
 *  call-seq: to_s -> string
 *
 *  Short representation of the buffer. It includes the address, size and
 *  symbolic flags. This format is subject to change.
 *
 *    puts IO::Buffer.new(4) # uses to_s internally
 *    # #<IO::Buffer 0x000055769f41b1a0+4 INTERNAL>
 */
VALUE
rb_io_buffer_to_s(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    VALUE result = rb_str_new_cstr("#<");

    rb_str_append(result, rb_class_name(CLASS_OF(self)));
    rb_str_catf(result, " %p+%"PRIdSIZE, buffer->base, buffer->size);

    if (buffer->base == NULL) {
        rb_str_cat2(result, " NULL");
    }

    if (buffer->flags & RB_IO_BUFFER_EXTERNAL) {
        rb_str_cat2(result, " EXTERNAL");
    }

    if (buffer->flags & RB_IO_BUFFER_INTERNAL) {
        rb_str_cat2(result, " INTERNAL");
    }

    if (buffer->flags & RB_IO_BUFFER_MAPPED) {
        rb_str_cat2(result, " MAPPED");
    }

    if (buffer->flags & RB_IO_BUFFER_FILE) {
        rb_str_cat2(result, " FILE");
    }

    if (buffer->flags & RB_IO_BUFFER_SHARED) {
        rb_str_cat2(result, " SHARED");
    }

    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        rb_str_cat2(result, " LOCKED");
    }

    if (buffer->flags & RB_IO_BUFFER_PRIVATE) {
        rb_str_cat2(result, " PRIVATE");
    }

    if (buffer->flags & RB_IO_BUFFER_READONLY) {
        rb_str_cat2(result, " READONLY");
    }

    if (buffer->source != Qnil) {
        rb_str_cat2(result, " SLICE");
    }

    if (!io_buffer_validate(buffer)) {
        rb_str_cat2(result, " INVALID");
    }

    return rb_str_cat2(result, ">");
}

// Compute the output size of a hexdump of the given width (bytes per line), total size, and whether it is the first line in the output.
// This is used to preallocate the output string.
inline static size_t
io_buffer_hexdump_output_size(size_t width, size_t size, int first)
{
    // The preview on the right hand side is 1:1:
    size_t total = size;

    size_t whole_lines = (size / width);
    size_t partial_line = (size % width) ? 1 : 0;

    // For each line:
    // 1 byte    10 bytes  1 byte  width*3 bytes   1 byte  size bytes
    // (newline) (address) (space) (hexdump      ) (space) (preview)
    total += (whole_lines + partial_line) * (1 + 10 + width*3 + 1 + 1);

    // If the hexdump is the first line, one less newline will be emitted:
    if (size && first) total -= 1;

    return total;
}

// Append a hexdump of the given width (bytes per line), base address, size, and whether it is the first line in the output.
// If the hexdump is not the first line, it will prepend a newline if there is any output at all.
// If formatting here is adjusted, please update io_buffer_hexdump_output_size accordingly.
static VALUE
io_buffer_hexdump(VALUE string, size_t width, const char *base, size_t length, size_t offset, int first)
{
    char *text = alloca(width+1);
    text[width] = '\0';

    for (; offset < length; offset += width) {
        memset(text, '\0', width);
        if (first) {
            rb_str_catf(string, "0x%08" PRIxSIZE " ", offset);
            first = 0;
        }
        else {
            rb_str_catf(string, "\n0x%08" PRIxSIZE " ", offset);
        }

        for (size_t i = 0; i < width; i += 1) {
            if (offset+i < length) {
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

/*
 *  call-seq: inspect -> string
 *
 *  Inspect the buffer and report useful information about it's internal state.
 *  Only a limited portion of the buffer will be displayed in a hexdump style
 *  format.
 *
 *    buffer = IO::Buffer.for("Hello World")
 *    puts buffer.inspect
 *    # #<IO::Buffer 0x000000010198ccd8+11 EXTERNAL READONLY SLICE>
 *    # 0x00000000  48 65 6c 6c 6f 20 57 6f 72 6c 64                Hello World
 */
VALUE
rb_io_buffer_inspect(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    VALUE result = rb_io_buffer_to_s(self);

    if (io_buffer_validate(buffer)) {
        // Limit the maximum size generated by inspect:
        size_t size = buffer->size;
        int clamped = 0;

        if (size > RB_IO_BUFFER_INSPECT_HEXDUMP_MAXIMUM_SIZE) {
            size = RB_IO_BUFFER_INSPECT_HEXDUMP_MAXIMUM_SIZE;
            clamped = 1;
        }

        io_buffer_hexdump(result, RB_IO_BUFFER_INSPECT_HEXDUMP_WIDTH, buffer->base, size, 0, 0);

        if (clamped) {
            rb_str_catf(result, "\n(and %" PRIuSIZE " more bytes not printed)", buffer->size - size);
        }
    }

    return result;
}

/*
 *  call-seq: size -> integer
 *
 *  Returns the size of the buffer that was explicitly set (on creation with ::new
 *  or on #resize), or deduced on buffer's creation from string or file.
 */
VALUE
rb_io_buffer_size(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return SIZET2NUM(buffer->size);
}

/*
 *  call-seq: valid? -> true or false
 *
 *  Returns whether the buffer buffer is accessible.
 *
 *  A buffer becomes invalid if it is a slice of another buffer (or string)
 *  which has been freed or re-allocated at a different address.
 */
static VALUE
rb_io_buffer_valid_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(io_buffer_validate(buffer));
}

/*
 *  call-seq: null? -> true or false
 *
 *  If the buffer was freed with #free, transferred with #transfer, or was
 *  never allocated in the first place.
 *
 *    buffer = IO::Buffer.new(0)
 *    buffer.null? #=> true
 *
 *    buffer = IO::Buffer.new(4)
 *    buffer.null? #=> false
 *    buffer.free
 *    buffer.null? #=> true
 */
static VALUE
rb_io_buffer_null_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->base == NULL);
}

/*
 *  call-seq: empty? -> true or false
 *
 *  If the buffer has 0 size: it is created by ::new with size 0, or with ::for
 *  from an empty string. (Note that empty files can't be mapped, so the buffer
 *  created with ::map will never be empty.)
 */
static VALUE
rb_io_buffer_empty_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->size == 0);
}

/*
 *  call-seq: external? -> true or false
 *
 *  The buffer is _external_ if it references the memory which is not
 *  allocated or mapped by the buffer itself.
 *
 *  A buffer created using ::for has an external reference to the string's
 *  memory.
 *
 *  External buffer can't be resized.
 */
static VALUE
rb_io_buffer_external_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->flags & RB_IO_BUFFER_EXTERNAL);
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
 */
static VALUE
rb_io_buffer_internal_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->flags & RB_IO_BUFFER_INTERNAL);
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
 */
static VALUE
rb_io_buffer_mapped_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->flags & RB_IO_BUFFER_MAPPED);
}

/*
 *  call-seq: shared? -> true or false
 *
 *  If the buffer is _shared_, meaning it references memory that can be shared
 *  with other processes (and thus might change without being modified
 *  locally).
 *
 *    # Create a test file:
 *    File.write('test.txt', 'test')
 *
 *    # Create a shared mapping from the given file, the file must be opened in
 *    # read-write mode unless we also specify IO::Buffer::READONLY:
 *    buffer = IO::Buffer.map(File.open('test.txt', 'r+'), nil, 0)
 *    # => #<IO::Buffer 0x00007f1bffd5e000+4 EXTERNAL MAPPED SHARED>
 *
 *    # Write to the buffer, which will modify the mapped file:
 *    buffer.set_string('b', 0)
 *    # => 1
 *
 *    # The file itself is modified:
 *    File.read('test.txt')
 *    # => "best"
 */
static VALUE
rb_io_buffer_shared_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->flags & RB_IO_BUFFER_SHARED);
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
 */
static VALUE
rb_io_buffer_locked_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->flags & RB_IO_BUFFER_LOCKED);
}

/*  call-seq: private? -> true or false
 *
 *  If the buffer is _private_, meaning modifications to the buffer will not
 *  be replicated to the underlying file mapping.
 *
 *    # Create a test file:
 *    File.write('test.txt', 'test')
 *
 *    # Create a private mapping from the given file. Note that the file here
 *    # is opened in read-only mode, but it doesn't matter due to the private
 *    # mapping:
 *    buffer = IO::Buffer.map(File.open('test.txt'), nil, 0, IO::Buffer::PRIVATE)
 *    # => #<IO::Buffer 0x00007fce63f11000+4 MAPPED PRIVATE>
 *
 *    # Write to the buffer (invoking CoW of the underlying file buffer):
 *    buffer.set_string('b', 0)
 *    # => 1
 *
 *    # The file itself is not modified:
 *    File.read('test.txt')
 *    # => "test"
 */
static VALUE
rb_io_buffer_private_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return RBOOL(buffer->flags & RB_IO_BUFFER_PRIVATE);
}

int
rb_io_buffer_readonly_p(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    return buffer->flags & RB_IO_BUFFER_READONLY;
}

/*
 *  call-seq: readonly? -> true or false
 *
 *  If the buffer is <i>read only</i>, meaning the buffer cannot be modified using
 *  #set_value, #set_string or #copy and similar.
 *
 *  Frozen strings and read-only files create read-only buffers.
 */
static VALUE
io_buffer_readonly_p(VALUE self)
{
    return RBOOL(rb_io_buffer_readonly_p(self));
}

static void
io_buffer_lock(struct rb_io_buffer *buffer)
{
    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Buffer already locked!");
    }

    buffer->flags |= RB_IO_BUFFER_LOCKED;
}

VALUE
rb_io_buffer_lock(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_lock(buffer);

    return self;
}

static void
io_buffer_unlock(struct rb_io_buffer *buffer)
{
    if (!(buffer->flags & RB_IO_BUFFER_LOCKED)) {
        rb_raise(rb_eIOBufferLockedError, "Buffer not locked!");
    }

    buffer->flags &= ~RB_IO_BUFFER_LOCKED;
}

VALUE
rb_io_buffer_unlock(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_unlock(buffer);

    return self;
}

int
rb_io_buffer_try_unlock(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        buffer->flags &= ~RB_IO_BUFFER_LOCKED;
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
 *  The following operations acquire a lock: #resize, #free.
 *
 *  Locking is not thread safe. It is designed as a safety net around
 *  non-blocking system calls. You can only share a buffer between threads with
 *  appropriate synchronisation techniques.
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
 *        buffer.set_string("test", 0)
 *      end
 *    end
 */
VALUE
rb_io_buffer_locked(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Buffer already locked!");
    }

    buffer->flags |= RB_IO_BUFFER_LOCKED;

    VALUE result = rb_yield(self);

    buffer->flags &= ~RB_IO_BUFFER_LOCKED;

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
 *  You can resize a freed buffer to re-allocate it.
 *
 *    buffer = IO::Buffer.for('test')
 *    buffer.free
 *    # => #<IO::Buffer 0x0000000000000000+0 NULL>
 *
 *    buffer.get_value(:U8, 0)
 *    # in `get_value': The buffer is not allocated! (IO::Buffer::AllocationError)
 *
 *    buffer.get_string
 *    # in `get_string': The buffer is not allocated! (IO::Buffer::AllocationError)
 *
 *    buffer.null?
 *    # => true
 */
VALUE
rb_io_buffer_free(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Buffer is locked!");
    }

    io_buffer_free(buffer);

    return self;
}

VALUE rb_io_buffer_free_locked(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_unlock(buffer);
    io_buffer_free(buffer);

    return self;
}

// Validate that access to the buffer is within bounds, assuming you want to
// access length bytes from the specified offset.
static inline void
io_buffer_validate_range(struct rb_io_buffer *buffer, size_t offset, size_t length)
{
    // We assume here that offset + length won't overflow:
    if (offset + length > buffer->size) {
        rb_raise(rb_eArgError, "Specified offset+length is bigger than the buffer size!");
    }
}

/*
 *  call-seq: hexdump([offset, [length, [width]]]) -> string
 *
 *  Returns a human-readable string representation of the buffer. The exact
 *  format is subject to change.
 *
 *    buffer = IO::Buffer.for("Hello World")
 *    puts buffer.hexdump
 *    # 0x00000000  48 65 6c 6c 6f 20 57 6f 72 6c 64                Hello World
 *
 *  As buffers are usually fairly big, you may want to limit the output by
 *  specifying the offset and length:
 *
 *    puts buffer.hexdump(6, 5)
 *    # 0x00000006  57 6f 72 6c 64                                  World
 */
static VALUE
rb_io_buffer_hexdump(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 3);

    size_t offset, length;
    struct rb_io_buffer *buffer = io_buffer_extract_offset_length(self, argc, argv, &offset, &length);

    size_t width = RB_IO_BUFFER_HEXDUMP_DEFAULT_WIDTH;
    if (argc >= 3) {
        width = io_buffer_extract_width(argv[2], 1);
    }

    // This may raise an exception if the offset/length is invalid:
    io_buffer_validate_range(buffer, offset, length);

    VALUE result = Qnil;

    if (io_buffer_validate(buffer) && buffer->base) {
        result = rb_str_buf_new(io_buffer_hexdump_output_size(width, length, 1));

        io_buffer_hexdump(result, width, buffer->base, offset+length, offset, 1);
    }

    return result;
}

static VALUE
rb_io_buffer_slice(struct rb_io_buffer *buffer, VALUE self, size_t offset, size_t length)
{
    io_buffer_validate_range(buffer, offset, length);

    VALUE instance = rb_io_buffer_type_allocate(rb_class_of(self));
    struct rb_io_buffer *slice = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, slice);

    slice->flags |= (buffer->flags & RB_IO_BUFFER_READONLY);
    slice->base = (char*)buffer->base + offset;
    slice->size = length;

    // The source should be the root buffer:
    if (buffer->source != Qnil) {
        RB_OBJ_WRITE(instance, &slice->source, buffer->source);
    }
    else {
        RB_OBJ_WRITE(instance, &slice->source, self);
    }

    return instance;
}

/*
 *  call-seq: slice([offset, [length]]) -> io_buffer
 *
 *  Produce another IO::Buffer which is a slice (or view into) the current one
 *  starting at +offset+ bytes and going for +length+ bytes.
 *
 *  The slicing happens without copying of memory, and the slice keeps being
 *  associated with the original buffer's source (string, or file), if any.
 *
 *  If the offset is not given, it will be zero. If the offset is negative, it
 *  will raise an ArgumentError.
 *
 *  If the length is not given, the slice will be as long as the original
 *  buffer minus the specified offset. If the length is negative, it will raise
 *  an ArgumentError.
 *
 *  Raises RuntimeError if the <tt>offset+length</tt> is out of the current
 *  buffer's bounds.
 *
 *    string = 'test'
 *    buffer = IO::Buffer.for(string).dup
 *
 *    slice = buffer.slice
 *    # =>
 *    # #<IO::Buffer 0x0000000108338e68+4 SLICE>
 *    # 0x00000000  74 65 73 74                                     test
 *
 *    buffer.slice(2)
 *    # =>
 *    # #<IO::Buffer 0x0000000108338e6a+2 SLICE>
 *    # 0x00000000  73 74                                           st
 *
 *    slice = buffer.slice(1, 2)
 *    # =>
 *    # #<IO::Buffer 0x00007fc3d34ebc49+2 SLICE>
 *    # 0x00000000  65 73                                           es
 *
 *    # Put "o" into 0s position of the slice
 *    slice.set_string('o', 0)
 *    slice
 *    # =>
 *    # #<IO::Buffer 0x00007fc3d34ebc49+2 SLICE>
 *    # 0x00000000  6f 73                                           os
 *
 *    # it is also visible at position 1 of the original buffer
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x00007fc3d31e2d80+4 INTERNAL>
 *    # 0x00000000  74 6f 73 74                                     tost
 */
static VALUE
io_buffer_slice(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 2);

    size_t offset, length;
    struct rb_io_buffer *buffer = io_buffer_extract_offset_length(self, argc, argv, &offset, &length);

    return rb_io_buffer_slice(buffer, self, offset, length);
}

/*
 *  call-seq: transfer -> new_io_buffer
 *
 *  Transfers ownership of the underlying memory to a new buffer, causing the
 *  current buffer to become uninitialized.
 *
 *    buffer = IO::Buffer.new('test')
 *    other = buffer.transfer
 *    other
 *    # =>
 *    # #<IO::Buffer 0x00007f136a15f7b0+4 SLICE>
 *    # 0x00000000  74 65 73 74                                     test
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x0000000000000000+0 NULL>
 *    buffer.null?
 *    # => true
 */
VALUE
rb_io_buffer_transfer(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Cannot transfer ownership of locked buffer!");
    }

    VALUE instance = rb_io_buffer_type_allocate(rb_class_of(self));
    struct rb_io_buffer *transferred;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, transferred);

    *transferred = *buffer;
    io_buffer_zero(buffer);

    return instance;
}

static void
io_buffer_resize_clear(struct rb_io_buffer *buffer, void* base, size_t size)
{
    if (size > buffer->size) {
        memset((unsigned char*)base+buffer->size, 0, size - buffer->size);
    }
}

static void
io_buffer_resize_copy(VALUE self, struct rb_io_buffer *buffer, size_t size)
{
    // Slow path:
    struct rb_io_buffer resized;
    io_buffer_initialize(self, &resized, NULL, size, io_flags_for_size(size), Qnil);

    if (buffer->base) {
        size_t preserve = buffer->size;
        if (preserve > size) preserve = size;
        memcpy(resized.base, buffer->base, preserve);

        io_buffer_resize_clear(buffer, resized.base, size);
    }

    io_buffer_free(buffer);
    *buffer = resized;
}

void
rb_io_buffer_resize(VALUE self, size_t size)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eIOBufferLockedError, "Cannot resize locked buffer!");
    }

    if (buffer->base == NULL) {
        io_buffer_initialize(self, buffer, NULL, size, io_flags_for_size(size), Qnil);
        return;
    }

    if (buffer->flags & RB_IO_BUFFER_EXTERNAL) {
        rb_raise(rb_eIOBufferAccessError, "Cannot resize external buffer!");
    }

#if defined(HAVE_MREMAP) && defined(MREMAP_MAYMOVE)
    if (buffer->flags & RB_IO_BUFFER_MAPPED) {
        void *base = mremap(buffer->base, buffer->size, size, MREMAP_MAYMOVE);

        if (base == MAP_FAILED) {
            rb_sys_fail("rb_io_buffer_resize:mremap");
        }

        io_buffer_resize_clear(buffer, base, size);

        buffer->base = base;
        buffer->size = size;

        return;
    }
#endif

    if (buffer->flags & RB_IO_BUFFER_INTERNAL) {
        if (size == 0) {
            io_buffer_free(buffer);
            return;
        }

        void *base = realloc(buffer->base, size);

        if (!base) {
            rb_sys_fail("rb_io_buffer_resize:realloc");
        }

        io_buffer_resize_clear(buffer, base, size);

        buffer->base = base;
        buffer->size = size;

        return;
    }

    io_buffer_resize_copy(self, buffer, size);
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
 *    # =>
 *    # #<IO::Buffer 0x0000555f5d1a1630+8 INTERNAL>
 *    # 0x00000000  74 65 73 74 00 00 00 00                         test....
 *
 *  External buffer (created with ::for), and locked buffer
 *  can not be resized.
 */
static VALUE
io_buffer_resize(VALUE self, VALUE size)
{
    rb_io_buffer_resize(self, io_buffer_extract_size(size));

    return self;
}

/*
 * call-seq: <=>(other) -> true or false
 *
 * Buffers are compared by size and exact contents of the memory they are
 * referencing using +memcmp+.
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
        rb_raise(rb_eArgError, "Type extends beyond end of buffer! (offset=%"PRIdSIZE" > size=%"PRIdSIZE")", offset, size);
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

#define IO_BUFFER_DECLARE_TYPE(name, type, endian, wrap, unwrap, swap) \
static ID RB_IO_BUFFER_DATA_TYPE_##name; \
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
} \
\
enum { \
    RB_IO_BUFFER_DATA_TYPE_##name##_SIZE = sizeof(type) \
};

IO_BUFFER_DECLARE_TYPE(U8, uint8_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap8)
IO_BUFFER_DECLARE_TYPE(S8, int8_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap8)

IO_BUFFER_DECLARE_TYPE(u16, uint16_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap16)
IO_BUFFER_DECLARE_TYPE(U16, uint16_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap16)
IO_BUFFER_DECLARE_TYPE(s16, int16_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap16)
IO_BUFFER_DECLARE_TYPE(S16, int16_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap16)

IO_BUFFER_DECLARE_TYPE(u32, uint32_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap32)
IO_BUFFER_DECLARE_TYPE(U32, uint32_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap32)
IO_BUFFER_DECLARE_TYPE(s32, int32_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap32)
IO_BUFFER_DECLARE_TYPE(S32, int32_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap32)

IO_BUFFER_DECLARE_TYPE(u64, uint64_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_ULL2NUM, RB_NUM2ULL, ruby_swap64)
IO_BUFFER_DECLARE_TYPE(U64, uint64_t, RB_IO_BUFFER_BIG_ENDIAN, RB_ULL2NUM, RB_NUM2ULL, ruby_swap64)
IO_BUFFER_DECLARE_TYPE(s64, int64_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_LL2NUM, RB_NUM2LL, ruby_swap64)
IO_BUFFER_DECLARE_TYPE(S64, int64_t, RB_IO_BUFFER_BIG_ENDIAN, RB_LL2NUM, RB_NUM2LL, ruby_swap64)

IO_BUFFER_DECLARE_TYPE(f32, float, RB_IO_BUFFER_LITTLE_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf32)
IO_BUFFER_DECLARE_TYPE(F32, float, RB_IO_BUFFER_BIG_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf32)
IO_BUFFER_DECLARE_TYPE(f64, double, RB_IO_BUFFER_LITTLE_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf64)
IO_BUFFER_DECLARE_TYPE(F64, double, RB_IO_BUFFER_BIG_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf64)
#undef IO_BUFFER_DECLARE_TYPE

static inline size_t
io_buffer_buffer_type_size(ID buffer_type)
{
#define IO_BUFFER_DATA_TYPE_SIZE(name) if (buffer_type == RB_IO_BUFFER_DATA_TYPE_##name) return RB_IO_BUFFER_DATA_TYPE_##name##_SIZE;
    IO_BUFFER_DATA_TYPE_SIZE(U8)
    IO_BUFFER_DATA_TYPE_SIZE(S8)
    IO_BUFFER_DATA_TYPE_SIZE(u16)
    IO_BUFFER_DATA_TYPE_SIZE(U16)
    IO_BUFFER_DATA_TYPE_SIZE(s16)
    IO_BUFFER_DATA_TYPE_SIZE(S16)
    IO_BUFFER_DATA_TYPE_SIZE(u32)
    IO_BUFFER_DATA_TYPE_SIZE(U32)
    IO_BUFFER_DATA_TYPE_SIZE(s32)
    IO_BUFFER_DATA_TYPE_SIZE(S32)
    IO_BUFFER_DATA_TYPE_SIZE(u64)
    IO_BUFFER_DATA_TYPE_SIZE(U64)
    IO_BUFFER_DATA_TYPE_SIZE(s64)
    IO_BUFFER_DATA_TYPE_SIZE(S64)
    IO_BUFFER_DATA_TYPE_SIZE(f32)
    IO_BUFFER_DATA_TYPE_SIZE(F32)
    IO_BUFFER_DATA_TYPE_SIZE(f64)
    IO_BUFFER_DATA_TYPE_SIZE(F64)
#undef IO_BUFFER_DATA_TYPE_SIZE

    rb_raise(rb_eArgError, "Invalid type name!");
}

/*
 *  call-seq:
 *    size_of(buffer_type) -> byte size
 *    size_of(array of buffer_type) -> byte size
 *
 *  Returns the size of the given buffer type(s) in bytes.
 *
 *    IO::Buffer.size_of(:u32) # => 4
 *    IO::Buffer.size_of([:u32, :u32]) # => 8
 */
static VALUE
io_buffer_size_of(VALUE klass, VALUE buffer_type)
{
    if (RB_TYPE_P(buffer_type, T_ARRAY)) {
        size_t total = 0;
        for (long i = 0; i < RARRAY_LEN(buffer_type); i++) {
            total += io_buffer_buffer_type_size(RB_SYM2ID(RARRAY_AREF(buffer_type, i)));
        }
        return SIZET2NUM(total);
    }
    else {
        return SIZET2NUM(io_buffer_buffer_type_size(RB_SYM2ID(buffer_type)));
    }
}

static inline VALUE
rb_io_buffer_get_value(const void* base, size_t size, ID buffer_type, size_t *offset)
{
#define IO_BUFFER_GET_VALUE(name) if (buffer_type == RB_IO_BUFFER_DATA_TYPE_##name) return io_buffer_read_##name(base, size, offset);
    IO_BUFFER_GET_VALUE(U8)
    IO_BUFFER_GET_VALUE(S8)

    IO_BUFFER_GET_VALUE(u16)
    IO_BUFFER_GET_VALUE(U16)
    IO_BUFFER_GET_VALUE(s16)
    IO_BUFFER_GET_VALUE(S16)

    IO_BUFFER_GET_VALUE(u32)
    IO_BUFFER_GET_VALUE(U32)
    IO_BUFFER_GET_VALUE(s32)
    IO_BUFFER_GET_VALUE(S32)

    IO_BUFFER_GET_VALUE(u64)
    IO_BUFFER_GET_VALUE(U64)
    IO_BUFFER_GET_VALUE(s64)
    IO_BUFFER_GET_VALUE(S64)

    IO_BUFFER_GET_VALUE(f32)
    IO_BUFFER_GET_VALUE(F32)
    IO_BUFFER_GET_VALUE(f64)
    IO_BUFFER_GET_VALUE(F64)
#undef IO_BUFFER_GET_VALUE

    rb_raise(rb_eArgError, "Invalid type name!");
}

/*
 *  call-seq: get_value(buffer_type, offset) -> numeric
 *
 *  Read from buffer a value of +type+ at +offset+. +buffer_type+ should be one
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
 *  A buffer type refers specifically to the type of binary buffer that is stored
 *  in the buffer. For example, a +:u32+ buffer type is a 32-bit unsigned
 *  integer in little-endian format.
 *
 *    string = [1.5].pack('f')
 *    # => "\x00\x00\xC0?"
 *    IO::Buffer.for(string).get_value(:f32, 0)
 *    # => 1.5
 */
static VALUE
io_buffer_get_value(VALUE self, VALUE type, VALUE _offset)
{
    const void *base;
    size_t size;
    size_t offset = io_buffer_extract_offset(_offset);

    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    return rb_io_buffer_get_value(base, size, RB_SYM2ID(type), &offset);
}

/*
 *  call-seq: get_values(buffer_types, offset) -> array
 *
 *  Similar to #get_value, except that it can handle multiple buffer types and
 *  returns an array of values.
 *
 *    string = [1.5, 2.5].pack('ff')
 *    IO::Buffer.for(string).get_values([:f32, :f32], 0)
 *    # => [1.5, 2.5]
 */
static VALUE
io_buffer_get_values(VALUE self, VALUE buffer_types, VALUE _offset)
{
    size_t offset = io_buffer_extract_offset(_offset);

    const void *base;
    size_t size;
    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    if (!RB_TYPE_P(buffer_types, T_ARRAY)) {
        rb_raise(rb_eArgError, "Argument buffer_types should be an array!");
    }

    VALUE array = rb_ary_new_capa(RARRAY_LEN(buffer_types));

    for (long i = 0; i < RARRAY_LEN(buffer_types); i++) {
        VALUE type = rb_ary_entry(buffer_types, i);
        VALUE value = rb_io_buffer_get_value(base, size, RB_SYM2ID(type), &offset);
        rb_ary_push(array, value);
    }

    return array;
}

// Extract a count argument, which must be a positive integer.
// Count is generally considered relative to the number of things.
static inline size_t
io_buffer_extract_count(VALUE argument)
{
    if (rb_int_negative_p(argument)) {
        rb_raise(rb_eArgError, "Count can't be negative!");
    }

    return NUM2SIZET(argument);
}

static inline void
io_buffer_extract_offset_count(ID buffer_type, size_t size, int argc, VALUE *argv, size_t *offset, size_t *count)
{
    if (argc >= 1) {
        *offset = io_buffer_extract_offset(argv[0]);
    }
    else {
        *offset = 0;
    }

    if (argc >= 2) {
        *count = io_buffer_extract_count(argv[1]);
    }
    else {
        if (*offset > size) {
            rb_raise(rb_eArgError, "The given offset is bigger than the buffer size!");
        }

        *count = (size - *offset) / io_buffer_buffer_type_size(buffer_type);
    }
}

/*
 *  call-seq:
 *    each(buffer_type, [offset, [count]]) {|offset, value| ...} -> self
 *    each(buffer_type, [offset, [count]]) -> enumerator
 *
 *  Iterates over the buffer, yielding each +value+ of +buffer_type+ starting
 *  from +offset+.
 *
 *  If +count+ is given, only +count+ values will be yielded.
 *
 *    IO::Buffer.for("Hello World").each(:U8, 2, 2) do |offset, value|
 *      puts "#{offset}: #{value}"
 *    end
 *    # 2: 108
 *    # 3: 108
 */
static VALUE
io_buffer_each(int argc, VALUE *argv, VALUE self)
{
    RETURN_ENUMERATOR_KW(self, argc, argv, RB_NO_KEYWORDS);

    const void *base;
    size_t size;

    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    ID buffer_type;
    if (argc >= 1) {
        buffer_type = RB_SYM2ID(argv[0]);
    }
    else {
        buffer_type = RB_IO_BUFFER_DATA_TYPE_U8;
    }

    size_t offset, count;
    io_buffer_extract_offset_count(buffer_type, size, argc-1, argv+1, &offset, &count);

    for (size_t i = 0; i < count; i++) {
        size_t current_offset = offset;
        VALUE value = rb_io_buffer_get_value(base, size, buffer_type, &offset);
        rb_yield_values(2, SIZET2NUM(current_offset), value);
    }

    return self;
}

/*
 *  call-seq: values(buffer_type, [offset, [count]]) -> array
 *
 *  Returns an array of values of +buffer_type+ starting from +offset+.
 *
 *  If +count+ is given, only +count+ values will be returned.
 *
 *    IO::Buffer.for("Hello World").values(:U8, 2, 2)
 *    # => [108, 108]
 */
static VALUE
io_buffer_values(int argc, VALUE *argv, VALUE self)
{
    const void *base;
    size_t size;

    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    ID buffer_type;
    if (argc >= 1) {
        buffer_type = RB_SYM2ID(argv[0]);
    }
    else {
        buffer_type = RB_IO_BUFFER_DATA_TYPE_U8;
    }

    size_t offset, count;
    io_buffer_extract_offset_count(buffer_type, size, argc-1, argv+1, &offset, &count);

    VALUE array = rb_ary_new_capa(count);

    for (size_t i = 0; i < count; i++) {
        VALUE value = rb_io_buffer_get_value(base, size, buffer_type, &offset);
        rb_ary_push(array, value);
    }

    return array;
}

/*
 *  call-seq:
 *    each_byte([offset, [count]]) {|offset, byte| ...} -> self
 *    each_byte([offset, [count]]) -> enumerator
 *
 *  Iterates over the buffer, yielding each byte starting from +offset+.
 *
 *  If +count+ is given, only +count+ bytes will be yielded.
 *
 *    IO::Buffer.for("Hello World").each_byte(2, 2) do |offset, byte|
 *      puts "#{offset}: #{byte}"
 *    end
 *    # 2: 108
 *    # 3: 108
 */
static VALUE
io_buffer_each_byte(int argc, VALUE *argv, VALUE self)
{
    RETURN_ENUMERATOR_KW(self, argc, argv, RB_NO_KEYWORDS);

    const void *base;
    size_t size;

    rb_io_buffer_get_bytes_for_reading(self, &base, &size);

    size_t offset, count;
    io_buffer_extract_offset_count(RB_IO_BUFFER_DATA_TYPE_U8, size, argc-1, argv+1, &offset, &count);

    for (size_t i = 0; i < count; i++) {
        unsigned char *value = (unsigned char *)base + i + offset;
        rb_yield(RB_INT2FIX(*value));
    }

    return self;
}

static inline void
rb_io_buffer_set_value(const void* base, size_t size, ID buffer_type, size_t *offset, VALUE value)
{
#define IO_BUFFER_SET_VALUE(name) if (buffer_type == RB_IO_BUFFER_DATA_TYPE_##name) {io_buffer_write_##name(base, size, offset, value); return;}
    IO_BUFFER_SET_VALUE(U8);
    IO_BUFFER_SET_VALUE(S8);

    IO_BUFFER_SET_VALUE(u16);
    IO_BUFFER_SET_VALUE(U16);
    IO_BUFFER_SET_VALUE(s16);
    IO_BUFFER_SET_VALUE(S16);

    IO_BUFFER_SET_VALUE(u32);
    IO_BUFFER_SET_VALUE(U32);
    IO_BUFFER_SET_VALUE(s32);
    IO_BUFFER_SET_VALUE(S32);

    IO_BUFFER_SET_VALUE(u64);
    IO_BUFFER_SET_VALUE(U64);
    IO_BUFFER_SET_VALUE(s64);
    IO_BUFFER_SET_VALUE(S64);

    IO_BUFFER_SET_VALUE(f32);
    IO_BUFFER_SET_VALUE(F32);
    IO_BUFFER_SET_VALUE(f64);
    IO_BUFFER_SET_VALUE(F64);
#undef IO_BUFFER_SET_VALUE

    rb_raise(rb_eArgError, "Invalid type name!");
}

/*
 *  call-seq: set_value(type, offset, value) -> offset
 *
 *  Write to a buffer a +value+ of +type+ at +offset+. +type+ should be one of
 *  symbols described in #get_value.
 *
 *    buffer = IO::Buffer.new(8)
 *    # =>
 *    # #<IO::Buffer 0x0000555f5c9a2d50+8 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00
 *
 *    buffer.set_value(:U8, 1, 111)
 *    # => 1
 *
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x0000555f5c9a2d50+8 INTERNAL>
 *    # 0x00000000  00 6f 00 00 00 00 00 00                         .o......
 *
 *  Note that if the +type+ is integer and +value+ is Float, the implicit truncation is performed:
 *
 *    buffer = IO::Buffer.new(8)
 *    buffer.set_value(:U32, 0, 2.5)
 *
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x0000555f5c9a2d50+8 INTERNAL>
 *    # 0x00000000  00 00 00 02 00 00 00 00
 *    #                      ^^ the same as if we'd pass just integer 2
 */
static VALUE
io_buffer_set_value(VALUE self, VALUE type, VALUE _offset, VALUE value)
{
    void *base;
    size_t size;
    size_t offset = io_buffer_extract_offset(_offset);

    rb_io_buffer_get_bytes_for_writing(self, &base, &size);

    rb_io_buffer_set_value(base, size, RB_SYM2ID(type), &offset, value);

    return SIZET2NUM(offset);
}

/*
 *  call-seq: set_values(buffer_types, offset, values) -> offset
 *
 *  Write +values+ of +buffer_types+ at +offset+ to the buffer. +buffer_types+
 *  should be an array of symbols as described in #get_value. +values+ should
 *  be an array of values to write.
 *
 *    buffer = IO::Buffer.new(8)
 *    buffer.set_values([:U8, :U16], 0, [1, 2])
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x696f717561746978+8 INTERNAL>
 *    # 0x00000000  01 00 02 00 00 00 00 00                         ........
 */
static VALUE
io_buffer_set_values(VALUE self, VALUE buffer_types, VALUE _offset, VALUE values)
{
    if (!RB_TYPE_P(buffer_types, T_ARRAY)) {
        rb_raise(rb_eArgError, "Argument buffer_types should be an array!");
    }

    if (!RB_TYPE_P(values, T_ARRAY)) {
        rb_raise(rb_eArgError, "Argument values should be an array!");
    }

    if (RARRAY_LEN(buffer_types) != RARRAY_LEN(values)) {
        rb_raise(rb_eArgError, "Argument buffer_types and values should have the same length!");
    }

    size_t offset = io_buffer_extract_offset(_offset);

    void *base;
    size_t size;
    rb_io_buffer_get_bytes_for_writing(self, &base, &size);

    for (long i = 0; i < RARRAY_LEN(buffer_types); i++) {
        VALUE type = rb_ary_entry(buffer_types, i);
        VALUE value = rb_ary_entry(values, i);
        rb_io_buffer_set_value(base, size, RB_SYM2ID(type), &offset, value);
    }

    return SIZET2NUM(offset);
}

static size_t IO_BUFFER_BLOCKING_SIZE = 1024*1024;

struct io_buffer_memmove_arguments {
    unsigned char * destination;
    const unsigned char * source;
    size_t length;
};

static void *
io_buffer_memmove_blocking(void *data)
{
    struct io_buffer_memmove_arguments *arguments = (struct io_buffer_memmove_arguments *)data;

    memmove(arguments->destination, arguments->source, arguments->length);

    return NULL;
}

static void
io_buffer_memmove_unblock(void *data)
{
    // No safe way to interrupt.
}

static void
io_buffer_memmove(struct rb_io_buffer *buffer, size_t offset, const void *source_base, size_t source_offset, size_t source_size, size_t length)
{
    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    io_buffer_validate_range(buffer, offset, length);

    if (source_offset + length > source_size) {
        rb_raise(rb_eArgError, "The computed source range exceeds the size of the source buffer!");
    }

    struct io_buffer_memmove_arguments arguments = {
        .destination = (unsigned char*)base+offset,
        .source = (unsigned char*)source_base+source_offset,
        .length = length
    };

    if (arguments.length >= IO_BUFFER_BLOCKING_SIZE) {
        rb_nogvl(io_buffer_memmove_blocking, &arguments, io_buffer_memmove_unblock, &arguments, RB_NOGVL_OFFLOAD_SAFE);
    } else if (arguments.length != 0) {
        memmove(arguments.destination, arguments.source, arguments.length);
    }
}

// (offset, length, source_offset) -> length
static VALUE
io_buffer_copy_from(struct rb_io_buffer *buffer, const void *source_base, size_t source_size, int argc, VALUE *argv)
{
    size_t offset = 0;
    size_t length;
    size_t source_offset;

    // The offset we copy into the buffer:
    if (argc >= 1) {
        offset = io_buffer_extract_offset(argv[0]);
    }

    // The offset we start from within the string:
    if (argc >= 3) {
        source_offset = io_buffer_extract_offset(argv[2]);

        if (source_offset > source_size) {
            rb_raise(rb_eArgError, "The given source offset is bigger than the source itself!");
        }
    }
    else {
        source_offset = 0;
    }

    // The length we are going to copy:
    if (argc >= 2 && !RB_NIL_P(argv[1])) {
        length = io_buffer_extract_length(argv[1]);
    }
    else {
        // Default to the source offset -> source size:
        length = source_size - source_offset;
    }

    io_buffer_memmove(buffer, offset, source_base, source_offset, source_size, length);

    return SIZET2NUM(length);
}

/*
 *  call-seq:
 *    dup -> io_buffer
 *    clone -> io_buffer
 *
 *  Make an internal copy of the source buffer. Updates to the copy will not
 *  affect the source buffer.
 *
 *    source = IO::Buffer.for("Hello World")
 *    # =>
 *    # #<IO::Buffer 0x00007fd598466830+11 EXTERNAL READONLY SLICE>
 *    # 0x00000000  48 65 6c 6c 6f 20 57 6f 72 6c 64                Hello World
 *    buffer = source.dup
 *    # =>
 *    # #<IO::Buffer 0x0000558cbec03320+11 INTERNAL>
 *    # 0x00000000  48 65 6c 6c 6f 20 57 6f 72 6c 64                Hello World
 */
static VALUE
rb_io_buffer_initialize_copy(VALUE self, VALUE source)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    const void *source_base;
    size_t source_size;

    rb_io_buffer_get_bytes_for_reading(source, &source_base, &source_size);

    io_buffer_initialize(self, buffer, NULL, source_size, io_flags_for_size(source_size), Qnil);

    return io_buffer_copy_from(buffer, source_base, source_size, 0, NULL);
}

/*
 *  call-seq:
 *    copy(source, [offset, [length, [source_offset]]]) -> size
 *
 *  Efficiently copy from a source IO::Buffer into the buffer, at +offset+
 *  using +memmove+. For copying String instances, see #set_string.
 *
 *    buffer = IO::Buffer.new(32)
 *    # =>
 *    # #<IO::Buffer 0x0000555f5ca22520+32 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ................
 *    # 0x00000010  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ................  *
 *
 *    buffer.copy(IO::Buffer.for("test"), 8)
 *    # => 4 -- size of buffer copied
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x0000555f5cf8fe40+32 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00 74 65 73 74 00 00 00 00 ........test....
 *    # 0x00000010  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ................ *
 *
 *  #copy can be used to put buffer into strings associated with buffer:
 *
 *    string = "data:    "
 *    # => "data:    "
 *    buffer = IO::Buffer.for(string) do |buffer|
 *      buffer.copy(IO::Buffer.for("test"), 5)
 *    end
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
 *    buffer.copy(IO::Buffer.for("boom"), 0)
 *    # => 4
 *    File.read('test.txt')
 *    # => "boom"
 *
 *  Attempt to copy the buffer which will need place outside of buffer's
 *  bounds will fail:
 *
 *    buffer = IO::Buffer.new(2)
 *    buffer.copy(IO::Buffer.for('test'), 0)
 *    # in `copy': Specified offset+length is bigger than the buffer size! (ArgumentError)
 *
 *  It is safe to copy between memory regions that overlaps each other.
 *  In such case, the data is copied as if the data was first copied from the source buffer to
 *  a temporary buffer, and then copied from the temporary buffer to the destination buffer.
 *
 *    buffer = IO::Buffer.new(10)
 *    buffer.set_string("0123456789")
 *    buffer.copy(buffer, 3, 7)
 *    # => 7
 *    buffer
 *    # =>
 *    # #<IO::Buffer 0x000056494f8ce440+10 INTERNAL>
 *    # 0x00000000  30 31 32 30 31 32 33 34 35 36                   0120123456
 */
static VALUE
io_buffer_copy(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, 4);

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    VALUE source = argv[0];
    const void *source_base;
    size_t source_size;

    rb_io_buffer_get_bytes_for_reading(source, &source_base, &source_size);

    return io_buffer_copy_from(buffer, source_base, source_size, argc-1, argv+1);
}

/*
 *  call-seq: get_string([offset, [length, [encoding]]]) -> string
 *
 *  Read a chunk or all of the buffer into a string, in the specified
 *  +encoding+. If no encoding is provided +Encoding::BINARY+ is used.
 *
 *    buffer = IO::Buffer.for('test')
 *    buffer.get_string
 *    # => "test"
 *    buffer.get_string(2)
 *    # => "st"
 *    buffer.get_string(2, 1)
 *    # => "s"
 */
static VALUE
io_buffer_get_string(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 3);

    size_t offset, length;
    struct rb_io_buffer *buffer = io_buffer_extract_offset_length(self, argc, argv, &offset, &length);

    const void *base;
    size_t size;
    io_buffer_get_bytes_for_reading(buffer, &base, &size);

    rb_encoding *encoding;
    if (argc >= 3) {
        encoding = rb_find_encoding(argv[2]);
    }
    else {
        encoding = rb_ascii8bit_encoding();
    }

    io_buffer_validate_range(buffer, offset, length);

    return rb_enc_str_new((const char*)base + offset, length, encoding);
}

/*
 *  call-seq: set_string(string, [offset, [length, [source_offset]]]) -> size
 *
 *  Efficiently copy from a source String into the buffer, at +offset+ using
 *  +memmove+.
 *
 *    buf = IO::Buffer.new(8)
 *    # =>
 *    # #<IO::Buffer 0x0000557412714a20+8 INTERNAL>
 *    # 0x00000000  00 00 00 00 00 00 00 00                         ........
 *
 *    # set buffer starting from offset 1, take 2 bytes starting from string's
 *    # second
 *    buf.set_string('test', 1, 2, 1)
 *    # => 2
 *    buf
 *    # =>
 *    # #<IO::Buffer 0x0000557412714a20+8 INTERNAL>
 *    # 0x00000000  00 65 73 00 00 00 00 00                         .es.....
 *
 *  See also #copy for examples of how buffer writing might be used for changing
 *  associated strings and files.
 */
static VALUE
io_buffer_set_string(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, 4);

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    VALUE string = rb_str_to_str(argv[0]);

    const void *source_base = RSTRING_PTR(string);
    size_t source_size = RSTRING_LEN(string);

    return io_buffer_copy_from(buffer, source_base, source_size, argc-1, argv+1);
}

void
rb_io_buffer_clear(VALUE self, uint8_t value, size_t offset, size_t length)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    io_buffer_validate_range(buffer, offset, length);

    memset((char*)base + offset, value, length);
}

/*
 *  call-seq: clear(value = 0, [offset, [length]]) -> self
 *
 *  Fill buffer with +value+, starting with +offset+ and going for +length+
 *  bytes.
 *
 *    buffer = IO::Buffer.for('test').dup
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 INTERNAL>
 *    #   0x00000000  74 65 73 74         test
 *
 *    buffer.clear
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 INTERNAL>
 *    #   0x00000000  00 00 00 00         ....
 *
 *    buf.clear(1) # fill with 1
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 INTERNAL>
 *    #   0x00000000  01 01 01 01         ....
 *
 *    buffer.clear(2, 1, 2) # fill with 2, starting from offset 1, for 2 bytes
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 INTERNAL>
 *    #   0x00000000  01 02 02 01         ....
 *
 *    buffer.clear(2, 1) # fill with 2, starting from offset 1
 *    # =>
 *    #   <IO::Buffer 0x00007fca40087c38+4 INTERNAL>
 *    #   0x00000000  01 02 02 02         ....
 */
static VALUE
io_buffer_clear(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 3);

    uint8_t value = 0;
    if (argc >= 1) {
        value = NUM2UINT(argv[0]);
    }

    size_t offset, length;
    io_buffer_extract_offset_length(self, argc-1, argv+1, &offset, &length);

    rb_io_buffer_clear(self, value, offset, length);

    return self;
}

static size_t
io_buffer_default_size(size_t page_size)
{
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

struct io_buffer_blocking_region_argument {
    struct rb_io *io;
    struct rb_io_buffer *buffer;
    rb_blocking_function_t *function;
    void *data;
};

static VALUE
io_buffer_blocking_region_begin(VALUE _argument)
{
    struct io_buffer_blocking_region_argument *argument = (void*)_argument;

    return rb_io_blocking_region(argument->io, argument->function, argument->data);
}

static VALUE
io_buffer_blocking_region_ensure(VALUE _argument)
{
    struct io_buffer_blocking_region_argument *argument = (void*)_argument;

    io_buffer_unlock(argument->buffer);

    return Qnil;
}

static VALUE
io_buffer_blocking_region(VALUE io, struct rb_io_buffer *buffer, rb_blocking_function_t *function, void *data)
{
    struct rb_io *ioptr;
    RB_IO_POINTER(io, ioptr);

    struct io_buffer_blocking_region_argument argument = {
        .io = ioptr,
        .buffer = buffer,
        .function = function,
        .data = data,
    };

    // If the buffer is already locked, we can skip the ensure (unlock):
    if (buffer->flags & RB_IO_BUFFER_LOCKED) {
        return io_buffer_blocking_region_begin((VALUE)&argument);
    }
    else {
        // The buffer should be locked for the duration of the blocking region:
        io_buffer_lock(buffer);

        return rb_ensure(io_buffer_blocking_region_begin, (VALUE)&argument, io_buffer_blocking_region_ensure, (VALUE)&argument);
    }
}

struct io_buffer_read_internal_argument {
    // The file descriptor to read from:
    int descriptor;
    // The base pointer to read from:
    char *base;
    // The size of the buffer:
    size_t size;
    // The minimum number of bytes to read:
    size_t length;
};

static VALUE
io_buffer_read_internal(void *_argument)
{
    size_t total = 0;
    struct io_buffer_read_internal_argument *argument = _argument;

    while (true) {
        ssize_t result = read(argument->descriptor, argument->base, argument->size);

        if (result < 0) {
            return rb_fiber_scheduler_io_result(result, errno);
        }
        else if (result == 0) {
            return rb_fiber_scheduler_io_result(total, 0);
        }
        else {
            total += result;

            if (total >= argument->length) {
                return rb_fiber_scheduler_io_result(total, 0);
            }

            argument->base = argument->base + result;
            argument->size = argument->size - result;
        }
    }
}

VALUE
rb_io_buffer_read(VALUE self, VALUE io, size_t length, size_t offset)
{
    io = rb_io_get_io(io);

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_read(scheduler, io, self, length, offset);

        if (!UNDEF_P(result)) {
            return result;
        }
    }

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_validate_range(buffer, offset, length);

    int descriptor = rb_io_descriptor(io);

    void * base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    base = (unsigned char*)base + offset;
    size = size - offset;

    struct io_buffer_read_internal_argument argument = {
        .descriptor = descriptor,
        .base = base,
        .size = size,
        .length = length,
    };

    return io_buffer_blocking_region(io, buffer, io_buffer_read_internal, &argument);
}

/*
 *  call-seq: read(io, [length, [offset]]) -> read length or -errno
 *
 *  Read at least +length+ bytes from the +io+, into the buffer starting at
 *  +offset+. If an error occurs, return <tt>-errno</tt>.
 *
 *  If +length+ is not given or +nil+, it defaults to the size of the buffer
 *  minus the offset, i.e. the entire buffer.
 *
 *  If +length+ is zero, exactly one <tt>read</tt> operation will occur.
 *
 *  If +offset+ is not given, it defaults to zero, i.e. the beginning of the
 *  buffer.
 *
 *    IO::Buffer.for('test') do |buffer|
 *      p buffer
 *      # =>
 *      # <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *      # 0x00000000  74 65 73 74         test
 *      buffer.read(File.open('/dev/urandom', 'rb'), 2)
 *      p buffer
 *      # =>
 *      # <IO::Buffer 0x00007f3bc65f2a58+4 EXTERNAL SLICE>
 *      # 0x00000000  05 35 73 74         .5st
 *    end
 */
static VALUE
io_buffer_read(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, 3);

    VALUE io = argv[0];

    size_t length, offset;
    io_buffer_extract_length_offset(self, argc-1, argv+1, &length, &offset);

    return rb_io_buffer_read(self, io, length, offset);
}

struct io_buffer_pread_internal_argument {
    // The file descriptor to read from:
    int descriptor;
    // The base pointer to read from:
    char *base;
    // The size of the buffer:
    size_t size;
    // The minimum number of bytes to read:
    size_t length;
    // The offset to read from:
    off_t offset;
};

static VALUE
io_buffer_pread_internal(void *_argument)
{
    size_t total = 0;
    struct io_buffer_pread_internal_argument *argument = _argument;

    while (true) {
        ssize_t result = pread(argument->descriptor, argument->base, argument->size, argument->offset);

        if (result < 0) {
            return rb_fiber_scheduler_io_result(result, errno);
        }
        else if (result == 0) {
            return rb_fiber_scheduler_io_result(total, 0);
        }
        else {
            total += result;

            if (total >= argument->length) {
                return rb_fiber_scheduler_io_result(total, 0);
            }

            argument->base = argument->base + result;
            argument->size = argument->size - result;
            argument->offset = argument->offset + result;
        }
    }
}

VALUE
rb_io_buffer_pread(VALUE self, VALUE io, rb_off_t from, size_t length, size_t offset)
{
    io = rb_io_get_io(io);

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_pread(scheduler, io, from, self, length, offset);

        if (!UNDEF_P(result)) {
            return result;
        }
    }

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_validate_range(buffer, offset, length);

    int descriptor = rb_io_descriptor(io);

    void * base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    base = (unsigned char*)base + offset;
    size = size - offset;

    struct io_buffer_pread_internal_argument argument = {
        .descriptor = descriptor,
        .base = base,
        .size = size,
        .length = length,
        .offset = from,
    };

    return io_buffer_blocking_region(io, buffer, io_buffer_pread_internal, &argument);
}

/*
 *  call-seq: pread(io, from, [length, [offset]]) -> read length or -errno
 *
 *  Read at least +length+ bytes from the +io+ starting at the specified +from+
 *  position, into the buffer starting at +offset+. If an error occurs,
 *  return <tt>-errno</tt>.
 *
 *  If +length+ is not given or +nil+, it defaults to the size of the buffer
 *  minus the offset, i.e. the entire buffer.
 *
 *  If +length+ is zero, exactly one <tt>pread</tt> operation will occur.
 *
 *  If +offset+ is not given, it defaults to zero, i.e. the beginning of the
 *  buffer.
 *
 *    IO::Buffer.for('test') do |buffer|
 *      p buffer
 *      # =>
 *      # <IO::Buffer 0x00007fca40087c38+4 SLICE>
 *      # 0x00000000  74 65 73 74         test
 *
 *      # take 2 bytes from the beginning of urandom,
 *      # put them in buffer starting from position 2
 *      buffer.pread(File.open('/dev/urandom', 'rb'), 0, 2, 2)
 *      p buffer
 *      # =>
 *      # <IO::Buffer 0x00007f3bc65f2a58+4 EXTERNAL SLICE>
 *      # 0x00000000  05 35 73 74         te.5
 *    end
 */
static VALUE
io_buffer_pread(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 2, 4);

    VALUE io = argv[0];
    rb_off_t from = NUM2OFFT(argv[1]);

    size_t length, offset;
    io_buffer_extract_length_offset(self, argc-2, argv+2, &length, &offset);

    return rb_io_buffer_pread(self, io, from, length, offset);
}

struct io_buffer_write_internal_argument {
    // The file descriptor to write to:
    int descriptor;
    // The base pointer to write from:
    const char *base;
    // The size of the buffer:
    size_t size;
    // The minimum length to write:
    size_t length;
};

static VALUE
io_buffer_write_internal(void *_argument)
{
    size_t total = 0;
    struct io_buffer_write_internal_argument *argument = _argument;

    while (true) {
        ssize_t result = write(argument->descriptor, argument->base, argument->size);

        if (result < 0) {
            return rb_fiber_scheduler_io_result(result, errno);
        }
        else if (result == 0) {
            return rb_fiber_scheduler_io_result(total, 0);
        }
        else {
            total += result;

            if (total >= argument->length) {
                return rb_fiber_scheduler_io_result(total, 0);
            }

            argument->base = argument->base + result;
            argument->size = argument->size - result;
        }
    }
}

VALUE
rb_io_buffer_write(VALUE self, VALUE io, size_t length, size_t offset)
{
    io = rb_io_get_write_io(rb_io_get_io(io));

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_write(scheduler, io, self, length, offset);

        if (!UNDEF_P(result)) {
            return result;
        }
    }

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_validate_range(buffer, offset, length);

    int descriptor = rb_io_descriptor(io);

    const void * base;
    size_t size;
    io_buffer_get_bytes_for_reading(buffer, &base, &size);

    base = (unsigned char*)base + offset;
    size = size - offset;

    struct io_buffer_write_internal_argument argument = {
        .descriptor = descriptor,
        .base = base,
        .size = size,
        .length = length,
    };

    return io_buffer_blocking_region(io, buffer, io_buffer_write_internal, &argument);
}

/*
 *  call-seq: write(io, [length, [offset]]) -> written length or -errno
 *
 *  Write at least +length+ bytes from the buffer starting at +offset+, into the +io+.
 *  If an error occurs, return <tt>-errno</tt>.
 *
 *  If +length+ is not given or +nil+, it defaults to the size of the buffer
 *  minus the offset, i.e. the entire buffer.
 *
 *  If +length+ is zero, exactly one <tt>write</tt> operation will occur.
 *
 *  If +offset+ is not given, it defaults to zero, i.e. the beginning of the
 *  buffer.
 *
 *    out = File.open('output.txt', 'wb')
 *    IO::Buffer.for('1234567').write(out, 3)
 *
 *  This leads to +123+ being written into <tt>output.txt</tt>
 */
static VALUE
io_buffer_write(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, 3);

    VALUE io = argv[0];

    size_t length, offset;
    io_buffer_extract_length_offset(self, argc-1, argv+1, &length, &offset);

    return rb_io_buffer_write(self, io, length, offset);
}

struct io_buffer_pwrite_internal_argument {
    // The file descriptor to write to:
    int descriptor;
    // The base pointer to write from:
    const char *base;
    // The size of the buffer:
    size_t size;
    // The minimum length to write:
    size_t length;
    // The offset to write to:
    off_t offset;
};

static VALUE
io_buffer_pwrite_internal(void *_argument)
{
    size_t total = 0;
    struct io_buffer_pwrite_internal_argument *argument = _argument;

    while (true) {
        ssize_t result = pwrite(argument->descriptor, argument->base, argument->size, argument->offset);

        if (result < 0) {
            return rb_fiber_scheduler_io_result(result, errno);
        }
        else if (result == 0) {
            return rb_fiber_scheduler_io_result(total, 0);
        }
        else {
            total += result;

            if (total >= argument->length) {
                return rb_fiber_scheduler_io_result(total, 0);
            }

            argument->base = argument->base + result;
            argument->size = argument->size - result;
            argument->offset = argument->offset + result;
        }
    }
}

VALUE
rb_io_buffer_pwrite(VALUE self, VALUE io, rb_off_t from, size_t length, size_t offset)
{
    io = rb_io_get_write_io(rb_io_get_io(io));

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_pwrite(scheduler, io, from, self, length, offset);

        if (!UNDEF_P(result)) {
            return result;
        }
    }

    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    io_buffer_validate_range(buffer, offset, length);

    int descriptor = rb_io_descriptor(io);

    const void * base;
    size_t size;
    io_buffer_get_bytes_for_reading(buffer, &base, &size);

    base = (unsigned char*)base + offset;
    size = size - offset;

    struct io_buffer_pwrite_internal_argument argument = {
        .descriptor = descriptor,

        // Move the base pointer to the offset:
        .base = base,

        // And the size to the length of buffer we want to read:
        .size = size,

        // And the length of the buffer we want to write:
        .length = length,

        // And the offset in the file we want to write from:
        .offset = from,
    };

    return io_buffer_blocking_region(io, buffer, io_buffer_pwrite_internal, &argument);
}

/*
 *  call-seq: pwrite(io, from, [length, [offset]]) -> written length or -errno
 *
 *  Write at least +length+ bytes from the buffer starting at +offset+, into
 *  the +io+ starting at the specified +from+ position. If an error occurs,
 *  return <tt>-errno</tt>.
 *
 *  If +length+ is not given or +nil+, it defaults to the size of the buffer
 *  minus the offset, i.e. the entire buffer.
 *
 *  If +length+ is zero, exactly one <tt>pwrite</tt> operation will occur.
 *
 *  If +offset+ is not given, it defaults to zero, i.e. the beginning of the
 *  buffer.
 *
 *  If the +from+ position is beyond the end of the file, the gap will be
 *  filled with null (0 value) bytes.
 *
 *    out = File.open('output.txt', File::RDWR) # open for read/write, no truncation
 *    IO::Buffer.for('1234567').pwrite(out, 2, 3, 1)
 *
 *  This leads to +234+ (3 bytes, starting from position 1) being written into
 *  <tt>output.txt</tt>, starting from file position 2.
 */
static VALUE
io_buffer_pwrite(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 2, 4);

    VALUE io = argv[0];
    rb_off_t from = NUM2OFFT(argv[1]);

    size_t length, offset;
    io_buffer_extract_length_offset(self, argc-2, argv+2, &length, &offset);

    return rb_io_buffer_pwrite(self, io, from, length, offset);
}

static inline void
io_buffer_check_mask(const struct rb_io_buffer *buffer)
{
    if (buffer->size == 0)
        rb_raise(rb_eIOBufferMaskError, "Zero-length mask given!");
}

static void
memory_and(unsigned char * restrict output, unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        output[offset] = base[offset] & mask[offset % mask_size];
    }
}

/*
 *  call-seq:
 *    source & mask -> io_buffer
 *
 *  Generate a new buffer the same size as the source by applying the binary AND
 *  operation to the source, using the mask, repeating as necessary.
 *
 *    IO::Buffer.for("1234567890") & IO::Buffer.for("\xFF\x00\x00\xFF")
 *    # =>
 *    # #<IO::Buffer 0x00005589b2758480+4 INTERNAL>
 *    # 0x00000000  31 00 00 34 35 00 00 38 39 00                   1..45..89.
 */
static VALUE
io_buffer_and(VALUE self, VALUE mask)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    struct rb_io_buffer *mask_buffer = NULL;
    TypedData_Get_Struct(mask, struct rb_io_buffer, &rb_io_buffer_type, mask_buffer);

    io_buffer_check_mask(mask_buffer);

    VALUE output = rb_io_buffer_new(NULL, buffer->size, io_flags_for_size(buffer->size));
    struct rb_io_buffer *output_buffer = NULL;
    TypedData_Get_Struct(output, struct rb_io_buffer, &rb_io_buffer_type, output_buffer);

    memory_and(output_buffer->base, buffer->base, buffer->size, mask_buffer->base, mask_buffer->size);

    return output;
}

static void
memory_or(unsigned char * restrict output, unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        output[offset] = base[offset] | mask[offset % mask_size];
    }
}

/*
 *  call-seq:
 *    source | mask -> io_buffer
 *
 *  Generate a new buffer the same size as the source by applying the binary OR
 *  operation to the source, using the mask, repeating as necessary.
 *
 *    IO::Buffer.for("1234567890") | IO::Buffer.for("\xFF\x00\x00\xFF")
 *    # =>
 *    # #<IO::Buffer 0x0000561785ae3480+10 INTERNAL>
 *    # 0x00000000  ff 32 33 ff ff 36 37 ff ff 30                   .23..67..0
 */
static VALUE
io_buffer_or(VALUE self, VALUE mask)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    struct rb_io_buffer *mask_buffer = NULL;
    TypedData_Get_Struct(mask, struct rb_io_buffer, &rb_io_buffer_type, mask_buffer);

    io_buffer_check_mask(mask_buffer);

    VALUE output = rb_io_buffer_new(NULL, buffer->size, io_flags_for_size(buffer->size));
    struct rb_io_buffer *output_buffer = NULL;
    TypedData_Get_Struct(output, struct rb_io_buffer, &rb_io_buffer_type, output_buffer);

    memory_or(output_buffer->base, buffer->base, buffer->size, mask_buffer->base, mask_buffer->size);

    return output;
}

static void
memory_xor(unsigned char * restrict output, unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        output[offset] = base[offset] ^ mask[offset % mask_size];
    }
}

/*
 *  call-seq:
 *    source ^ mask -> io_buffer
 *
 *  Generate a new buffer the same size as the source by applying the binary XOR
 *  operation to the source, using the mask, repeating as necessary.
 *
 *    IO::Buffer.for("1234567890") ^ IO::Buffer.for("\xFF\x00\x00\xFF")
 *    # =>
 *    # #<IO::Buffer 0x000055a2d5d10480+10 INTERNAL>
 *    # 0x00000000  ce 32 33 cb ca 36 37 c7 c6 30                   .23..67..0
 */
static VALUE
io_buffer_xor(VALUE self, VALUE mask)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    struct rb_io_buffer *mask_buffer = NULL;
    TypedData_Get_Struct(mask, struct rb_io_buffer, &rb_io_buffer_type, mask_buffer);

    io_buffer_check_mask(mask_buffer);

    VALUE output = rb_io_buffer_new(NULL, buffer->size, io_flags_for_size(buffer->size));
    struct rb_io_buffer *output_buffer = NULL;
    TypedData_Get_Struct(output, struct rb_io_buffer, &rb_io_buffer_type, output_buffer);

    memory_xor(output_buffer->base, buffer->base, buffer->size, mask_buffer->base, mask_buffer->size);

    return output;
}

static void
memory_not(unsigned char * restrict output, unsigned char * restrict base, size_t size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        output[offset] = ~base[offset];
    }
}

/*
 *  call-seq:
 *    ~source -> io_buffer
 *
 *  Generate a new buffer the same size as the source by applying the binary NOT
 *  operation to the source.
 *
 *    ~IO::Buffer.for("1234567890")
 *    # =>
 *    # #<IO::Buffer 0x000055a5ac42f120+10 INTERNAL>
 *    # 0x00000000  ce cd cc cb ca c9 c8 c7 c6 cf                   ..........
 */
static VALUE
io_buffer_not(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    VALUE output = rb_io_buffer_new(NULL, buffer->size, io_flags_for_size(buffer->size));
    struct rb_io_buffer *output_buffer = NULL;
    TypedData_Get_Struct(output, struct rb_io_buffer, &rb_io_buffer_type, output_buffer);

    memory_not(output_buffer->base, buffer->base, buffer->size);

    return output;
}

static inline int
io_buffer_overlaps(const struct rb_io_buffer *a, const struct rb_io_buffer *b)
{
    if (a->base > b->base) {
        return io_buffer_overlaps(b, a);
    }

    return (b->base >= a->base) && (b->base < (void*)((unsigned char *)a->base + a->size));
}

static inline void
io_buffer_check_overlaps(struct rb_io_buffer *a, struct rb_io_buffer *b)
{
    if (io_buffer_overlaps(a, b))
        rb_raise(rb_eIOBufferMaskError, "Mask overlaps source buffer!");
}

static void
memory_and_inplace(unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        base[offset] &= mask[offset % mask_size];
    }
}

/*
 *  call-seq:
 *    source.and!(mask) -> io_buffer
 *
 *  Modify the source buffer in place by applying the binary AND
 *  operation to the source, using the mask, repeating as necessary.
 *
 *    source = IO::Buffer.for("1234567890").dup # Make a read/write copy.
 *    # =>
 *    # #<IO::Buffer 0x000056307a0d0c20+10 INTERNAL>
 *    # 0x00000000  31 32 33 34 35 36 37 38 39 30                   1234567890
 *
 *    source.and!(IO::Buffer.for("\xFF\x00\x00\xFF"))
 *    # =>
 *    # #<IO::Buffer 0x000056307a0d0c20+10 INTERNAL>
 *    # 0x00000000  31 00 00 34 35 00 00 38 39 00                   1..45..89.
 */
static VALUE
io_buffer_and_inplace(VALUE self, VALUE mask)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    struct rb_io_buffer *mask_buffer = NULL;
    TypedData_Get_Struct(mask, struct rb_io_buffer, &rb_io_buffer_type, mask_buffer);

    io_buffer_check_mask(mask_buffer);
    io_buffer_check_overlaps(buffer, mask_buffer);

    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    memory_and_inplace(base, size, mask_buffer->base, mask_buffer->size);

    return self;
}

static void
memory_or_inplace(unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        base[offset] |= mask[offset % mask_size];
    }
}

/*
 *  call-seq:
 *    source.or!(mask) -> io_buffer
 *
 *  Modify the source buffer in place by applying the binary OR
 *  operation to the source, using the mask, repeating as necessary.
 *
 *    source = IO::Buffer.for("1234567890").dup # Make a read/write copy.
 *    # =>
 *    # #<IO::Buffer 0x000056307a272350+10 INTERNAL>
 *    # 0x00000000  31 32 33 34 35 36 37 38 39 30                   1234567890
 *
 *    source.or!(IO::Buffer.for("\xFF\x00\x00\xFF"))
 *    # =>
 *    # #<IO::Buffer 0x000056307a272350+10 INTERNAL>
 *    # 0x00000000  ff 32 33 ff ff 36 37 ff ff 30                   .23..67..0
 */
static VALUE
io_buffer_or_inplace(VALUE self, VALUE mask)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    struct rb_io_buffer *mask_buffer = NULL;
    TypedData_Get_Struct(mask, struct rb_io_buffer, &rb_io_buffer_type, mask_buffer);

    io_buffer_check_mask(mask_buffer);
    io_buffer_check_overlaps(buffer, mask_buffer);

    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    memory_or_inplace(base, size, mask_buffer->base, mask_buffer->size);

    return self;
}

static void
memory_xor_inplace(unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        base[offset] ^= mask[offset % mask_size];
    }
}

/*
 *  call-seq:
 *    source.xor!(mask) -> io_buffer
 *
 *  Modify the source buffer in place by applying the binary XOR
 *  operation to the source, using the mask, repeating as necessary.
 *
 *    source = IO::Buffer.for("1234567890").dup # Make a read/write copy.
 *    # =>
 *    # #<IO::Buffer 0x000056307a25b3e0+10 INTERNAL>
 *    # 0x00000000  31 32 33 34 35 36 37 38 39 30                   1234567890
 *
 *    source.xor!(IO::Buffer.for("\xFF\x00\x00\xFF"))
 *    # =>
 *    # #<IO::Buffer 0x000056307a25b3e0+10 INTERNAL>
 *    # 0x00000000  ce 32 33 cb ca 36 37 c7 c6 30                   .23..67..0
 */
static VALUE
io_buffer_xor_inplace(VALUE self, VALUE mask)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    struct rb_io_buffer *mask_buffer = NULL;
    TypedData_Get_Struct(mask, struct rb_io_buffer, &rb_io_buffer_type, mask_buffer);

    io_buffer_check_mask(mask_buffer);
    io_buffer_check_overlaps(buffer, mask_buffer);

    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    memory_xor_inplace(base, size, mask_buffer->base, mask_buffer->size);

    return self;
}

static void
memory_not_inplace(unsigned char * restrict base, size_t size)
{
    for (size_t offset = 0; offset < size; offset += 1) {
        base[offset] = ~base[offset];
    }
}

/*
 *  call-seq:
 *    source.not! -> io_buffer
 *
 *  Modify the source buffer in place by applying the binary NOT
 *  operation to the source.
 *
 *    source = IO::Buffer.for("1234567890").dup # Make a read/write copy.
 *    # =>
 *    # #<IO::Buffer 0x000056307a33a450+10 INTERNAL>
 *    # 0x00000000  31 32 33 34 35 36 37 38 39 30                   1234567890
 *
 *    source.not!
 *    # =>
 *    # #<IO::Buffer 0x000056307a33a450+10 INTERNAL>
 *    # 0x00000000  ce cd cc cb ca c9 c8 c7 c6 cf                   ..........
 */
static VALUE
io_buffer_not_inplace(VALUE self)
{
    struct rb_io_buffer *buffer = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, buffer);

    void *base;
    size_t size;
    io_buffer_get_bytes_for_writing(buffer, &base, &size);

    memory_not_inplace(base, size);

    return self;
}

/*
 *  Document-class: IO::Buffer
 *
 *  IO::Buffer is a efficient zero-copy buffer for input/output. There are
 *  typical use cases:
 *
 *  * Create an empty buffer with ::new, fill it with buffer using #copy or
 *    #set_value, #set_string, get buffer with #get_string or write it directly
 *    to some file with #write.
 *  * Create a buffer mapped to some string with ::for, then it could be used
 *    both for reading with #get_string or #get_value, and writing (writing will
 *    change the source string, too).
 *  * Create a buffer mapped to some file with ::map, then it could be used for
 *    reading and writing the underlying file.
 *  * Create a string of a fixed size with ::string, then #read into it, or
 *    modify it using #set_value.
 *
 *  Interaction with string and file memory is performed by efficient low-level
 *  C mechanisms like `memcpy`.
 *
 *  The class is meant to be an utility for implementing more high-level mechanisms
 *  like Fiber::Scheduler#io_read and Fiber::Scheduler#io_write and parsing binary
 *  protocols.
 *
 *  == Examples of Usage
 *
 *  Empty buffer:
 *
 *    buffer = IO::Buffer.new(8)  # create empty 8-byte buffer
 *    # =>
 *    # #<IO::Buffer 0x0000555f5d1a5c50+8 INTERNAL>
 *    # ...
 *    buffer
 *    # =>
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
 *    IO::Buffer.for(string) do |buffer|
 *      buffer
 *      # =>
 *      # #<IO::Buffer 0x00007f3f02be9b18+4 SLICE>
 *      # 0x00000000  64 61 74 61                                     data
 *
 *      buffer.get_string(2)  # read content starting from offset 2
 *      # => "ta"
 *      buffer.set_string('---', 1) # write content, starting from offset 1
 *      # => 3
 *      buffer
 *      # =>
 *      # #<IO::Buffer 0x00007f3f02be9b18+4 SLICE>
 *      # 0x00000000  64 2d 2d 2d                                     d---
 *      string  # original string changed, too
 *      # => "d---"
 *    end
 *
 *  \Buffer from file:
 *
 *    File.write('test.txt', 'test data')
 *    # => 9
 *    buffer = IO::Buffer.map(File.open('test.txt'))
 *    # =>
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
 *  <b>The class is experimental and the interface is subject to change, this
 *  is especially true of file mappings which may be removed entirely in
 *  the future.</b>
 */
void
Init_IO_Buffer(void)
{
    rb_cIOBuffer = rb_define_class_under(rb_cIO, "Buffer", rb_cObject);

    /* Raised when an operation would resize or re-allocate a locked buffer. */
    rb_eIOBufferLockedError = rb_define_class_under(rb_cIOBuffer, "LockedError", rb_eRuntimeError);

    /* Raised when the buffer cannot be allocated for some reason, or you try to use a buffer that's not allocated. */
    rb_eIOBufferAllocationError = rb_define_class_under(rb_cIOBuffer, "AllocationError", rb_eRuntimeError);

    /* Raised when you try to write to a read-only buffer, or resize an external buffer. */
    rb_eIOBufferAccessError = rb_define_class_under(rb_cIOBuffer, "AccessError", rb_eRuntimeError);

    /* Raised if you try to access a buffer slice which no longer references a valid memory range of the underlying source. */
    rb_eIOBufferInvalidatedError = rb_define_class_under(rb_cIOBuffer, "InvalidatedError", rb_eRuntimeError);

    /* Raised if the mask given to a binary operation is invalid, e.g. zero length or overlaps the target buffer. */
    rb_eIOBufferMaskError = rb_define_class_under(rb_cIOBuffer, "MaskError", rb_eArgError);

    rb_define_alloc_func(rb_cIOBuffer, rb_io_buffer_type_allocate);
    rb_define_singleton_method(rb_cIOBuffer, "for", rb_io_buffer_type_for, 1);
    rb_define_singleton_method(rb_cIOBuffer, "string", rb_io_buffer_type_string, 1);

#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    RUBY_IO_BUFFER_PAGE_SIZE = info.dwPageSize;
#else /* not WIN32 */
    RUBY_IO_BUFFER_PAGE_SIZE = sysconf(_SC_PAGESIZE);
#endif

    RUBY_IO_BUFFER_DEFAULT_SIZE = io_buffer_default_size(RUBY_IO_BUFFER_PAGE_SIZE);

    /* The operating system page size. Used for efficient page-aligned memory allocations. */
    rb_define_const(rb_cIOBuffer, "PAGE_SIZE", SIZET2NUM(RUBY_IO_BUFFER_PAGE_SIZE));

    /* The default buffer size, typically a (small) multiple of the PAGE_SIZE.
       Can be explicitly specified by setting the RUBY_IO_BUFFER_DEFAULT_SIZE
       environment variable. */
    rb_define_const(rb_cIOBuffer, "DEFAULT_SIZE", SIZET2NUM(RUBY_IO_BUFFER_DEFAULT_SIZE));

    rb_define_singleton_method(rb_cIOBuffer, "map", io_buffer_map, -1);

    rb_define_method(rb_cIOBuffer, "initialize", rb_io_buffer_initialize, -1);
    rb_define_method(rb_cIOBuffer, "initialize_copy", rb_io_buffer_initialize_copy, 1);
    rb_define_method(rb_cIOBuffer, "inspect", rb_io_buffer_inspect, 0);
    rb_define_method(rb_cIOBuffer, "hexdump", rb_io_buffer_hexdump, -1);
    rb_define_method(rb_cIOBuffer, "to_s", rb_io_buffer_to_s, 0);
    rb_define_method(rb_cIOBuffer, "size", rb_io_buffer_size, 0);
    rb_define_method(rb_cIOBuffer, "valid?", rb_io_buffer_valid_p, 0);

    rb_define_method(rb_cIOBuffer, "transfer", rb_io_buffer_transfer, 0);

    /* Indicates that the memory in the buffer is owned by someone else. See #external? for more details. */
    rb_define_const(rb_cIOBuffer, "EXTERNAL", RB_INT2NUM(RB_IO_BUFFER_EXTERNAL));

    /* Indicates that the memory in the buffer is owned by the buffer. See #internal? for more details. */
    rb_define_const(rb_cIOBuffer, "INTERNAL", RB_INT2NUM(RB_IO_BUFFER_INTERNAL));

    /* Indicates that the memory in the buffer is mapped by the operating system. See #mapped? for more details. */
    rb_define_const(rb_cIOBuffer, "MAPPED", RB_INT2NUM(RB_IO_BUFFER_MAPPED));

    /* Indicates that the memory in the buffer is also mapped such that it can be shared with other processes. See #shared? for more details. */
    rb_define_const(rb_cIOBuffer, "SHARED", RB_INT2NUM(RB_IO_BUFFER_SHARED));

    /* Indicates that the memory in the buffer is locked and cannot be resized or freed. See #locked? and #locked for more details. */
    rb_define_const(rb_cIOBuffer, "LOCKED", RB_INT2NUM(RB_IO_BUFFER_LOCKED));

    /* Indicates that the memory in the buffer is mapped privately and changes won't be replicated to the underlying file. See #private? for more details. */
    rb_define_const(rb_cIOBuffer, "PRIVATE", RB_INT2NUM(RB_IO_BUFFER_PRIVATE));

    /* Indicates that the memory in the buffer is read only, and attempts to modify it will fail. See #readonly? for more details.*/
    rb_define_const(rb_cIOBuffer, "READONLY", RB_INT2NUM(RB_IO_BUFFER_READONLY));

    /* Refers to little endian byte order, where the least significant byte is stored first. See #get_value for more details. */
    rb_define_const(rb_cIOBuffer, "LITTLE_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_LITTLE_ENDIAN));

    /* Refers to big endian byte order, where the most significant byte is stored first. See #get_value for more details. */
    rb_define_const(rb_cIOBuffer, "BIG_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_BIG_ENDIAN));

    /* Refers to the byte order of the host machine. See #get_value for more details. */
    rb_define_const(rb_cIOBuffer, "HOST_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_HOST_ENDIAN));

    /* Refers to network byte order, which is the same as big endian. See #get_value for more details. */
    rb_define_const(rb_cIOBuffer, "NETWORK_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_NETWORK_ENDIAN));

    rb_define_method(rb_cIOBuffer, "null?", rb_io_buffer_null_p, 0);
    rb_define_method(rb_cIOBuffer, "empty?", rb_io_buffer_empty_p, 0);
    rb_define_method(rb_cIOBuffer, "external?", rb_io_buffer_external_p, 0);
    rb_define_method(rb_cIOBuffer, "internal?", rb_io_buffer_internal_p, 0);
    rb_define_method(rb_cIOBuffer, "mapped?", rb_io_buffer_mapped_p, 0);
    rb_define_method(rb_cIOBuffer, "shared?", rb_io_buffer_shared_p, 0);
    rb_define_method(rb_cIOBuffer, "locked?", rb_io_buffer_locked_p, 0);
    rb_define_method(rb_cIOBuffer, "private?", rb_io_buffer_private_p, 0);
    rb_define_method(rb_cIOBuffer, "readonly?", io_buffer_readonly_p, 0);

    // Locking to prevent changes while using pointer:
    // rb_define_method(rb_cIOBuffer, "lock", rb_io_buffer_lock, 0);
    // rb_define_method(rb_cIOBuffer, "unlock", rb_io_buffer_unlock, 0);
    rb_define_method(rb_cIOBuffer, "locked", rb_io_buffer_locked, 0);

    // Manipulation:
    rb_define_method(rb_cIOBuffer, "slice", io_buffer_slice, -1);
    rb_define_method(rb_cIOBuffer, "<=>", rb_io_buffer_compare, 1);
    rb_define_method(rb_cIOBuffer, "resize", io_buffer_resize, 1);
    rb_define_method(rb_cIOBuffer, "clear", io_buffer_clear, -1);
    rb_define_method(rb_cIOBuffer, "free", rb_io_buffer_free, 0);

    rb_include_module(rb_cIOBuffer, rb_mComparable);

#define IO_BUFFER_DEFINE_DATA_TYPE(name) RB_IO_BUFFER_DATA_TYPE_##name = rb_intern_const(#name)
    IO_BUFFER_DEFINE_DATA_TYPE(U8);
    IO_BUFFER_DEFINE_DATA_TYPE(S8);

    IO_BUFFER_DEFINE_DATA_TYPE(u16);
    IO_BUFFER_DEFINE_DATA_TYPE(U16);
    IO_BUFFER_DEFINE_DATA_TYPE(s16);
    IO_BUFFER_DEFINE_DATA_TYPE(S16);

    IO_BUFFER_DEFINE_DATA_TYPE(u32);
    IO_BUFFER_DEFINE_DATA_TYPE(U32);
    IO_BUFFER_DEFINE_DATA_TYPE(s32);
    IO_BUFFER_DEFINE_DATA_TYPE(S32);

    IO_BUFFER_DEFINE_DATA_TYPE(u64);
    IO_BUFFER_DEFINE_DATA_TYPE(U64);
    IO_BUFFER_DEFINE_DATA_TYPE(s64);
    IO_BUFFER_DEFINE_DATA_TYPE(S64);

    IO_BUFFER_DEFINE_DATA_TYPE(f32);
    IO_BUFFER_DEFINE_DATA_TYPE(F32);
    IO_BUFFER_DEFINE_DATA_TYPE(f64);
    IO_BUFFER_DEFINE_DATA_TYPE(F64);
#undef IO_BUFFER_DEFINE_DATA_TYPE

    rb_define_singleton_method(rb_cIOBuffer, "size_of", io_buffer_size_of, 1);

    // Data access:
    rb_define_method(rb_cIOBuffer, "get_value", io_buffer_get_value, 2);
    rb_define_method(rb_cIOBuffer, "get_values", io_buffer_get_values, 2);
    rb_define_method(rb_cIOBuffer, "each", io_buffer_each, -1);
    rb_define_method(rb_cIOBuffer, "values", io_buffer_values, -1);
    rb_define_method(rb_cIOBuffer, "each_byte", io_buffer_each_byte, -1);
    rb_define_method(rb_cIOBuffer, "set_value", io_buffer_set_value, 3);
    rb_define_method(rb_cIOBuffer, "set_values", io_buffer_set_values, 3);

    rb_define_method(rb_cIOBuffer, "copy", io_buffer_copy, -1);

    rb_define_method(rb_cIOBuffer, "get_string", io_buffer_get_string, -1);
    rb_define_method(rb_cIOBuffer, "set_string", io_buffer_set_string, -1);

    // Binary buffer manipulations:
    rb_define_method(rb_cIOBuffer, "&", io_buffer_and, 1);
    rb_define_method(rb_cIOBuffer, "|", io_buffer_or, 1);
    rb_define_method(rb_cIOBuffer, "^", io_buffer_xor, 1);
    rb_define_method(rb_cIOBuffer, "~", io_buffer_not, 0);

    rb_define_method(rb_cIOBuffer, "and!", io_buffer_and_inplace, 1);
    rb_define_method(rb_cIOBuffer, "or!", io_buffer_or_inplace, 1);
    rb_define_method(rb_cIOBuffer, "xor!", io_buffer_xor_inplace, 1);
    rb_define_method(rb_cIOBuffer, "not!", io_buffer_not_inplace, 0);

    // IO operations:
    rb_define_method(rb_cIOBuffer, "read", io_buffer_read, -1);
    rb_define_method(rb_cIOBuffer, "pread", io_buffer_pread, -1);
    rb_define_method(rb_cIOBuffer, "write", io_buffer_write, -1);
    rb_define_method(rb_cIOBuffer, "pwrite", io_buffer_pwrite, -1);
}
